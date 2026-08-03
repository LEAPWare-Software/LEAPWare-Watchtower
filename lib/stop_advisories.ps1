#requires -version 5
<#
  LW-WATCHTOWER advisory handler - context_pressure, verification_gate, docs_coupling,
  git_hygiene and mission_drift, on the Stop event.

  Invoked from hooks/hooks.json in exec form:
      command: "powershell"
      args:    ["-NoProfile","-ExecutionPolicy","Bypass","-File",
                "${CLAUDE_PLUGIN_ROOT}/lib/stop_advisories.ps1"]

  WHY ONE SCRIPT FOR FIVE MODULES
  Stop fires at the end of every single turn, and each registered hook is a
  separate PowerShell process - roughly 285 ms of interpreter startup that buys
  nothing. Five hooks would put well over a second on every turn end. So the
  five modules share one process and each gates itself independently: switching
  one off leaves the others running, and switching all of them off makes this
  script exit before it resolves a repo or touches the state dir.

  TURN-END COST IS THE MAX OF THE STOP HOOKS, NOT THEIR SUM.
  Phase 7 measured it rather than assuming: Claude Code starts the hooks
  registered for one event CONCURRENTLY. Sampling the OS process table through a
  real session showed lib/supervisor.ps1 and this script created 26 ms apart and
  alive together for more than a second. So this script - the slower of the two -
  sets turn-end cost on its own, which is why the work below is ordered to
  overlap rather than merged with the supervisor. Merging them was considered and
  rejected: it would save nothing measurable and would put the supervisor's
  exit-2 alerting behind this script's stdout, which the CLI ignores on exit 2.

  THESE ARE ADVISORIES. THEY MUST NEVER BLOCK.
  On Stop a hook blocks the turn by exiting 2 (without asyncRewake) or by
  printing {"decision":"block"}. This script does neither, and cannot: it exits
  0 on every path, and its only stdout is the systemMessage envelope from
  Write-LwgAdvisory, which carries no `decision` field. Phase 4's two PreToolUse
  gates remain the only things in this plugin that can stop anything.

  ALWAYS exits 0. A broken governance layer must never break a session.
#>

$ErrorActionPreference = 'Stop'

$payload = [pscustomobject]@{}
$messages = @()

function Add-Advisory([string]$Text) {
    if (-not [string]::IsNullOrWhiteSpace($Text)) { $script:messages += $Text }
}

function Format-Tokens([int]$n) {
    if ($n -ge 1000000) { return ('{0:0.0}M' -f ($n / 1000000.0)) }
    if ($n -ge 1000)    { return ('{0:0}k'   -f ($n / 1000.0)) }
    return [string]$n
}

function Expand-LwgAgentName {
    <#
      Every spelling one configured agent name can arrive as, for
      verification_gate's two lists: the name as written, plus its bare form if
      it was written with a `<plugin>:` prefix.

      An agent role shipped by a plugin is reported by SubagentStop under its
      NAMESPACED name - "lw-watchtower:lw-verifier" - while the same role copied into
      ~/.claude/agents is reported bare, as "lw-verifier". An operator may
      reasonably write either into config.json, so neither spelling can be
      required. Expanding the configured side here and stripping the observed
      side at the match point means the two meet whichever way round they were
      written.

      EVERY return is comma-wrapped, and that is load-bearing rather than style.
      PowerShell unrolls a returned collection, so a bare `return @()` reaches the
      caller as $null - and in Windows PowerShell 5.1 `foreach ($x in $null)`
      runs ONCE, with $x null, which would put a null into a
      HashSet[string] whose comparer throws on one. `,@(...)` returns the array
      itself, so the empty case iterates zero times and the one-name case
      iterates over the NAME rather than over its characters.
    #>
    param([string]$Name)

    $n = [string]$Name
    if ([string]::IsNullOrWhiteSpace($n)) { return ,@() }
    $n = $n.Trim()

    # A plugin name cannot contain ':', so the FIRST colon is the separator. A
    # trailing colon with nothing after it is not a prefix, it is a typo, and
    # stripping it would add the empty string to the match set.
    $ci = $n.IndexOf(':')
    if ($ci -ge 0 -and $ci -lt ($n.Length - 1)) { return ,@($n, $n.Substring($ci + 1)) }
    return ,@($n)
}

# --- subprocess plumbing (git_hygiene only) --------------------------------
# These live HERE and not in common.ps1 on purpose. common.ps1 was dot-sourced by
# both PreToolUse gates, and a gate that can spawn a process is a gate that can
# hang the tool call it is meant to be guarding. Keeping the only subprocess
# helper in the Stop handler makes that structurally impossible rather than
# merely unintended.
#
# Those two gates were removed on 30 July 2026 and lib/gate_delegate.ps1
# replaced them as the only one later the same day - and it dot-sources
# common.ps1 on the PreToolUse path. So this is not a historical arrangement
# kept for tidiness: there is a live blocking hook again, and the reason it
# cannot shell out is that the only subprocess helper in this plugin is in this
# file, which nothing on the PreToolUse path loads. Do not move it.

function Start-LwgProcess {
    <#
      Launch a bounded child and return a HANDLE to it without waiting:

        @{ p; so; se; sw; state; ok; code; out; err; ms; wait_ms }

      state is 'running' when it started and 'missing' when it could not be
      started at all. Pass the handle to Complete-LwgProcess to collect it.

      Split out from Invoke-LwgProcess so `git status` can be started FIRST and
      collected LAST, overlapping the child's run with the other modules' work
      instead of adding it to them. Measured on this repo: git itself runs about
      93 ms, of which roughly 400 ms of other work now covers all but 26 ms, so
      what lands on turn end is the ~65 ms Process.Start costs here plus that
      remainder rather than the whole thing.

      THAT ACCOUNTING COVERS TWO CHILDREN AND THERE ARE THREE. The overlapped
      `git status` and the once-per-branch-head `gh` are the two it names; the
      third is `git rev-list --count HEAD --not --remotes`, run through the
      BLOCKING Invoke-LwgProcess below on any branch with no upstream in a repo
      that has a remote, at EVERY turn end for the life of that branch. It
      cannot be launched at the top of the script - whether it is needed depends
      on `git status`'s answer - so all of it lands on turn end. Measured 3
      August 2026 on this repo, 15 runs interleaved: 327 ms median against
      307 ms for `git status` measured the same way in the same run, on a
      machine running eight concurrent sessions. The absolutes are inflated by
      that load and the ratio is the transferable part - the second child costs
      about what the first does, and none of it is overlapped. Numbers and the
      reason a commit-oid cache was rejected are in docs/architecture.md under
      `git_hygiene` and the `gh` call.

      The child's clock starts here, so it still gets exactly TimeoutMs of wall
      time and no more - the overlap shortens the hook, never the leash.

      The output streams are drained ASYNCHRONOUSLY. The obvious shape -
      ReadToEnd() then WaitForExit($ms) - deadlocks on a child that fills a pipe
      buffer, and WaitForExit($ms) alone deadlocks on a child that never exits,
      so neither of them actually bounds anything.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$File,
        [string[]]$ProcArgs = @(),
        [string]$WorkDir
    )

    $h = @{ p = $null; so = $null; se = $null; sw = [System.Diagnostics.Stopwatch]::StartNew()
            state = 'error'; ok = $false; code = -1; out = ''; err = ''; ms = 0; wait_ms = 0 }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $File
        # .NET Framework 4.x has no ProcessStartInfo.ArgumentList, so the
        # argument string is built by hand.
        #
        # THIS COMMENT USED TO SAY "every argument this file passes is a literal
        # from the code below, never anything from the payload", AND THAT WAS
        # FALSE. The `gh pr list` call site passes two values that are not
        # literals: $ghRepo is the repo slug, resolved from the hook payload's
        # cwd and parsed out of the raw `url = ` line in .git/config by a regex
        # whose repo half is `(?<r>.+?)`; and $branch is parsed from
        # `# branch.head` in git status output, so it is controlled by anyone
        # who can get a branch created in a repo the operator checks out. The
        # sentence was true when it was written and the gh call site was added
        # later without revisiting it. It is the load-bearing kind of comment -
        # the one the next person adding a call site would have relied on to
        # decide their untrusted value was fine.
        #
        # WHAT ACTUALLY MAKES THIS SAFE, stated so it can be checked:
        # UseShellExecute is $false below and the targets are `git` and `gh`,
        # which resolve to PE binaries on a standard install. With that pairing
        # cmd.exe is never in the path and the string is parsed by
        # CommandLineToArgvW, to which &, | and > are ordinary characters. The
        # residual, named rather than hidden: CreateProcess launches a .cmd or
        # .bat target THROUGH cmd.exe regardless of UseShellExecute, so a `gh`
        # that resolves to a batch shim - which some package managers install -
        # would have this string re-parsed by cmd.exe. That is the
        # CVE-2024-24576 class and is untested here; no .cmd-shimmed gh install
        # was available. The call-site validation on $ghRepo and $branch is what
        # stops that residual mattering, and it is at the gh call, not here.
        #
        # THE BACKSLASH RULE IS CommandLineToArgvW'S, and the old quoter did not
        # have it: it escaped `"` as `\"` and doubled nothing, so a value ending
        # in a backslash escaped its own closing quote and swallowed the
        # following argument into itself. Backslashes immediately before a quote
        # (including the closing one this adds) are doubled; backslashes
        # anywhere else are literal, which is why the lookahead is there and why
        # an ordinary Windows path is untouched.
        $psi.Arguments = (@($ProcArgs | ForEach-Object {
            $a = [string]$_
            if ($a -match '[\s"]') { '"' + ($a -replace '(\\+)(?="|$)', '$1$1' -replace '"', '\"') + '"' } else { $a }
        }) -join ' ')
        $psi.UseShellExecute        = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.RedirectStandardInput  = $true
        $psi.CreateNoWindow         = $true
        if (-not [string]::IsNullOrWhiteSpace($WorkDir)) { $psi.WorkingDirectory = $WorkDir }
        # Nothing here may ever wait on a human. A credential helper that decides
        # to prompt would otherwise sit there until the hook timeout kills the
        # whole advisory run. GIT_OPTIONAL_LOCKS=0 additionally stops `git
        # status` taking the index lock, so this cannot collide with real work -
        # which is also what makes it safe to leave running while this script
        # gets on with the other modules.
        $psi.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
        $psi.EnvironmentVariables['GIT_OPTIONAL_LOCKS']  = '0'
        $psi.EnvironmentVariables['GCM_INTERACTIVE']     = 'never'
        $psi.EnvironmentVariables['GH_PROMPT_DISABLED']  = '1'
        $psi.EnvironmentVariables['GH_NO_UPDATE_NOTIFIER'] = '1'

        try {
            $h.p = [System.Diagnostics.Process]::Start($psi)
        } catch {
            $h.state = 'missing'
            $h.err   = $_.Exception.Message
            return $h
        }
        if ($null -eq $h.p) { $h.state = 'missing'; return $h }

        # Close stdin immediately: a child that reads it gets EOF instead of
        # blocking forever on input this hook is never going to send.
        try { $h.p.StandardInput.Close() } catch { }

        $h.so = $h.p.StandardOutput.ReadToEndAsync()
        $h.se = $h.p.StandardError.ReadToEndAsync()
        $h.state = 'running'
    } catch {
        $h.state = 'error'
        $h.err   = $_.Exception.Message
    }
    return $h
}

function Complete-LwgProcess {
    <#
      Collect a handle from Start-LwgProcess, killing the child if it has not
      finished within $TimeoutMs OF ITS OWN START. Fills in and returns the same
      hashtable, with state settled to ok / nonzero / timeout / missing / error.

      The remaining budget is computed from the handle's stopwatch, so time the
      child spent running while this script did other work counts against it -
      the child never gets a longer leash because the overlap existed.

      TWO timings, and they mean different things:
        ms       how long the CHILD ran, taken from the OS process times, so it
                 is the same number this returned before the work was
                 overlapped and stays comparable with the Phase 6 figures;
        wait_ms  how long THIS SCRIPT blocked here, which is the part that
                 actually lands on turn end.
      Reporting elapsed-since-launch as `ms` would have quietly turned a 130 ms
      git call into a 550 ms one in the log the moment the launch moved earlier -
      a measurement that changed meaning without changing name.
    #>
    param($Handle, [int]$TimeoutMs = 1500)

    $r = $Handle
    if ($null -eq $r) { return @{ ok = $false; state = 'error'; code = -1; out = ''; err = ''; ms = 0; wait_ms = 0 } }
    $w = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        if ($r.state -ne 'running') { return $r }

        $left = $TimeoutMs - [int]$r.sw.ElapsedMilliseconds
        if ($left -lt 0) { $left = 0 }

        if ($r.p.WaitForExit($left)) {
            try { if ($r.so.Wait(500)) { $r.out = [string]$r.so.Result } } catch { }
            try { if ($r.se.Wait(500)) { $r.err = [string]$r.se.Result } } catch { }
            $r.code  = $r.p.ExitCode
            $r.ok    = ($r.code -eq 0)
            $r.state = if ($r.ok) { 'ok' } else { 'nonzero' }
        } else {
            $r.state = 'timeout'
            # KILLS THE CHILD, NOT THE TREE BENEATH IT, and that limit is stated
            # here because four places in this repository said "killed" without
            # it. .NET Framework 4.x - the runtime Windows PowerShell 5.1 runs
            # on, which is the only supported host - has no
            # Kill(bool entireProcessTree); that overload arrived in .NET Core
            # 3.0. So a `git` or `gh` that had itself spawned a credential
            # helper leaves that helper running, holding the inherited write
            # ends of the redirected pipes, after this hook has exited.
            #
            # WHAT STILL HOLDS: turn end is not blocked. This returns
            # immediately after the kill and never awaits the read tasks on this
            # path, so the "a child that hangs cannot stall turn end" half of
            # the guarantee is intact. What does not hold is the word "killed"
            # applied to the whole tree.
            #
            # NOT FIXED HERE, deliberately. The options on this runtime are
            # `taskkill /T /F` (a real-binary spawn on a hook path), a Job
            # Object with KILL_ON_JOB_CLOSE (meaningful P/Invoke in a file that
            # keeps its subprocess plumbing minimal), or a Win32_Process walk
            # (one WMI query on the slow path). No orphan has been observed from
            # this plugin - the consequence is inferred from what git and gh are
            # known to spawn generally - so the claim is corrected rather than
            # the code changed. docs/architecture.md and config.json still state
            # the uncorrected version.
            try { $r.p.Kill() } catch { }
        }
    } catch {
        $r.state = 'error'
        $r.err   = $_.Exception.Message
    } finally {
        $w.Stop()
        $r.wait_ms = [int]$w.ElapsedMilliseconds
        $r.sw.Stop()
        # The OS knows exactly when the child started and stopped. Fall back to
        # elapsed-since-launch only when it will not say - a child that never
        # exited, or one that could not be started at all.
        $r.ms = [int]$r.sw.ElapsedMilliseconds
        try {
            if ($null -ne $r.p -and $r.p.HasExited) {
                $r.ms = [int](($r.p.ExitTime - $r.p.StartTime).TotalMilliseconds)
            }
        } catch { }
        if ($null -ne $r.p) { try { $r.p.Dispose() } catch { } }
    }
    return $r
}

function Invoke-LwgProcess {
    <#
      Run a program, capture its output, and give up after $TimeoutMs.

      Returns @{ ok; state; code; out; err; ms }, where state is one of:

        ok        started, exited within the timeout, exit code 0
        nonzero   ran to completion but failed
        timeout   still running when the clock ran out; killed
        missing   could not be started at all (not on PATH)
        error     anything else

      `ok` is $true for 'ok' and NOTHING else. That distinction is the whole
      point of this function: every caller must be able to tell "the tool said
      there is nothing wrong" apart from "the tool did not answer". Treating the
      second as the first is how a watchdog reports a clean tree it never looked
      at - a defect already fixed three times in a private sibling project's
      watchdogs, and it is not being reintroduced here.

      A hashtable, so the result survives the function boundary un-enumerated.

      Start-then-collect with nothing in between - the blocking form, for the
      calls whose answer is needed immediately. `git status` does NOT use this;
      it is started early and collected at the end.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$File,
        [string[]]$ProcArgs = @(),
        [string]$WorkDir,
        [int]$TimeoutMs = 1500
    )

    $h = Start-LwgProcess -File $File -ProcArgs $ProcArgs -WorkDir $WorkDir
    return (Complete-LwgProcess -Handle $h -TimeoutMs $TimeoutMs)
}

function Start-LwgGit {
    <# git, in a specific work tree, launched but not yet waited on. #>
    param([string[]]$GitArgs, [string]$WorkDir)
    return (Start-LwgProcess -File 'git' -ProcArgs (@('--no-pager') + @($GitArgs)) -WorkDir $WorkDir)
}

function Invoke-LwgGit {
    <# git, in a specific work tree, bounded. Same result contract as above. #>
    param([string[]]$GitArgs, [string]$WorkDir, [int]$TimeoutMs = 1500)
    return (Invoke-LwgProcess -File 'git' -ProcArgs (@('--no-pager') + @($GitArgs)) `
                              -WorkDir $WorkDir -TimeoutMs $TimeoutMs)
}

try {
    . (Join-Path $PSScriptRoot 'common.ps1')

    $payload = Read-LwgStdin
    $cfg     = Get-LwgConfig

    # Loop guard, same contract as the supervisor's. stop_hook_active means some
    # hook already blocked this turn end once; re-running the advisories would
    # repeat every warning for as long as that lasts. Checked before anything
    # reads a file.
    if ($payload.stop_hook_active) { exit 0 }

    # --- repo slug, resolved only if it can change an answer ---------------
    # Get-LwgRepo walks up for .git and parses the origin remote - about 65 ms
    # cold on this platform. Module resolution only needs it when config.json
    # actually carries a per-repo override, and git_hygiene only needs it for
    # the optional gh call. So it is resolved on demand instead of always, and
    # memoised here as well as inside Get-LwgRepoInfo. With an empty `repos`
    # block - the shipped default - Test-LwgModule sees $null and behaves
    # identically, because it skips the override lookup for an empty repo.
    $script:repoDone  = $false
    $script:repoValue = $null
    function Get-CachedRepo {
        if (-not $script:repoDone) {
            $script:repoValue = Get-LwgRepo $script:payload
            $script:repoDone  = $true
        }
        return $script:repoValue
    }

    $hasRepoOverrides = $false
    try {
        if ($null -ne $cfg.repos) {
            foreach ($p in $cfg.repos.PSObject.Properties) {
                # '$comment' and friends are documentation, not repo slugs.
                if ($p.Name -notlike '$*') { $hasRepoOverrides = $true; break }
            }
        }
    } catch { }
    $repo = $(if ($hasRepoOverrides) { Get-CachedRepo } else { $null })

    # --- which modules are live for this turn ------------------------------
    # Resolved once, up front, so the flags can decide what work happens at all
    # rather than each block re-asking. With every one of them off this script
    # exits without resolving a repo, reading the state dir or spawning anything.
    $onContext = Test-LwgModule -Name 'context_pressure'  -Config $cfg -Repo $repo
    $onVerify  = Test-LwgModule -Name 'verification_gate' -Config $cfg -Repo $repo
    $onDocs    = Test-LwgModule -Name 'docs_coupling'     -Config $cfg -Repo $repo
    $onGit     = Test-LwgModule -Name 'git_hygiene'       -Config $cfg -Repo $repo
    $onMission = Test-LwgModule -Name 'mission_drift'     -Config $cfg -Repo $repo
    # A sixth flag, $onTrips, sat here. It was a Test-Path for this session's
    # trips-<sessionkey>.json rather than a module lookup, because no module owned
    # it any more: the gates that wrote trips went on 30 July 2026 and the sweep
    # below was kept only so ledgers written BEFORE that could still reach a
    # close. The ledger files were removed later the same day and lib/trips.ps1
    # with them, so the Test-Path can no longer be true for anything and the file
    # it decided whether to dot-source no longer exists.
    if (-not ($onContext -or $onVerify -or $onDocs -or $onGit -or $onMission)) { exit 0 }

    $sessionId = [string]$payload.session_id
    $sessKey   = Get-LwgSessionKey -SessionId $sessionId
    $stateFile = "advisory-$sessKey.json"
    $state     = Read-LwgStateJson -FileName $stateFile
    $stateDirty = $false

    # =====================================================================
    # git_hygiene, part one - LAUNCH ONLY
    # =====================================================================
    # `git status` is the only subprocess this script starts. It is launched
    # HERE, before the four in-process modules run, and collected after them, so
    # the child runs alongside their work instead of after it. Nothing between
    # here and the collection point depends on the answer.
    #
    # Measured: git runs ~93 ms; ~400 ms of other module work now overlaps it,
    # leaving ~26 ms still to wait for at the collection point instead of the
    # ~140 ms this blocked for before. Process.Start itself (~65 ms) is
    # unavoidably synchronous and is still paid here.
    #
    # It is safe to leave running: GIT_OPTIONAL_LOCKS=0 means it takes no index
    # lock, it only reads, and its timeout is measured from this line rather
    # than from the collection point, so the leash is unchanged.
    $gitInfo   = $null
    $gitStatus = $null
    $gitMs     = 1500
    if ($onGit) {
        try {
            # Not a repo: nothing is spawned at all, and the check for that is a
            # bounded Test-Path walk rather than a subprocess.
            $gitInfo = Get-LwgRepoInfo -Path ([string]$payload.cwd)
            if ($null -ne $gitInfo.root) {
                $gitMs     = [int](Get-LwgModuleOption -Config $cfg -Module 'git_hygiene' -Key 'timeout_ms' -Default 1500)
                $gitStatus = Start-LwgGit -GitArgs @('status', '--porcelain=v2', '--branch') -WorkDir $gitInfo.root
            }
        } catch {
            try { Write-LwgEvent -Event 'AdvisoryError' -Payload $payload -Extra @{
                module = 'git_hygiene'; phase = 'launch'; error = $_.Exception.Message } | Out-Null } catch { }
        }
    }

    # =====================================================================
    # context_pressure
    # =====================================================================
    # DATA SOURCE, stated plainly: `context_window` is NOT in any hook payload.
    # In claude-code 2.1.220 the hook input is
    #   {session_id, transcript_path, cwd, prompt_id?, permission_mode?,
    #    agent_id?, agent_type?, effort?}
    # plus per-event fields, and context_window/cost/rate_limits are assembled
    # in exactly one place - the status-line input builder. What every hook does
    # get is transcript_path, and the transcript's assistant records carry the
    # `message.usage` block the CLI itself divides by. So occupancy here is
    # recomputed from real numbers with the CLI's own formula, not read from a
    # field that does not exist.
    if ($onContext) {
        try {
            $usage = Get-LwgTranscriptUsage -Path ([string]$payload.transcript_path)
            if ($null -ne $usage) {

                # The window SIZE is the one number that genuinely is not
                # observable - it depends on account entitlements the hook
                # cannot see. Observation narrows it: the CLI only ever picks
                # 200k or 1M, so a model seen holding more than 200k tokens is
                # PROOF of the larger window. That proof is persisted and reused.
                $obsFile = 'context_windows.json'
                $obs     = Read-LwgStateJson -FileName $obsFile
                $model   = [string]$usage.model

                # --- RESOLVE FIRST, RECORD AFTER --------------------------
                # THE ORDER IS THE WHOLE FIX. This block used to write the
                # turn's own total_input into the observation store and then
                # hand that same in-memory hashtable to Get-LwgContextWindow,
                # which read it back, concluded the window must be 1M, and
                # returned a denominator large enough that the occupancy was no
                # longer impossible. So the trust check three lines below could
                # not fire for any reading between 200k and 1M: the inference
                # had already absorbed exactly the readings the refusal exists
                # to catch. Resolving against the store AS IT IS ON DISK
                # restores it, and is a re-ordering rather than new logic.
                $win    = Get-LwgContextWindow -Model $model -Config $cfg -Observed $obs
                $winTok = [int]$win.tokens
                $src    = [string]$win.source

                # An occupancy above the window is arithmetically impossible, so
                # it is proof the denominator is wrong rather than proof of
                # pressure. Reporting 100% CRITICAL here would be exactly the
                # fabricated-number failure this plugin exists to prevent.
                $trusted = $true
                if ($usage.total_input -gt $winTok) { $trusted = $false }
                if ($winTok -le 0) { $trusted = $false }

                # --- ONE SAMPLE IS NOT PROOF; TWO ARE ---------------------
                # THE STORE STILL HAS TO LEARN, or a model on a real 1M window
                # would report UNKNOWN for ever and the module would be silent
                # through the range it exists to cover. What changed is what
                # counts as proof. An occupancy above the assumed window is
                # ambiguous by construction - it is either a bigger window or a
                # wrong numerator (a mis-summed usage block, records spanning a
                # compaction, two models' figures landing under one key) - and
                # the old code resolved that ambiguity in favour of the window
                # on a SINGLE reading, permanently, with no expiry and no way to
                # clear it. A 260 000 mis-read then pinned the denominator to 1M
                # and a real 150k/200k turn - 75%, the warn threshold - rendered
                # as 15%, level ok, silently.
                #
                # So a first such reading is stored as PENDING and changes
                # nothing; a second, on a later turn, promotes it to the proven
                # entry Get-LwgContextWindow reads. Two independent turns above
                # 200k is near-certain on a genuine 1M session, because
                # occupancy grows, and is much harder to produce by accident.
                # The cost is honest and is stated: the first one or two turns
                # of such a session report the window as UNKNOWN and print no
                # percentage, and the ContextWindowUnknown record below is what
                # tells the operator the window_tokens knob exists - which on
                # the old code they were never shown, because the branch that
                # names it could not be reached.
                #
                # THE PENDING KEY IS A SEPARATE KEY IN THE SAME FILE, spelled
                # '<model>#pending'. Get-LwgContextWindow indexes the store by
                # the exact model id, so a key that is not one is invisible to
                # it - which is what keeps $obs[$model] meaning strictly "this
                # window is proven" for a function this change does not own.
                #
                # WHAT THIS DOES NOT DO: it does not give a wrong pinned entry a
                # way out. Once promoted, an entry above the default is never
                # rewritten and nothing in the plugin clears it - see the note
                # in docs/modules.md. Corroboration makes a wrong pin much less
                # likely; it does not make it recoverable.
                if (-not [string]::IsNullOrWhiteSpace($model)) {
                    $prevObs = 0
                    if ($null -ne $obs[$model]) { try { $prevObs = [int]$obs[$model] } catch { $prevObs = 0 } }

                    if ($trusted -and $prevObs -le $script:LwgContextWindowDefault -and
                        $usage.total_input -gt $prevObs -and
                        $usage.total_input -gt $script:LwgContextWindowDefault) {
                        # Accepted reading above the default: only reachable when
                        # the window was already known from config or the [1m]
                        # tag, so there is nothing left to infer - but keeping
                        # the lower bound current costs one write and makes the
                        # store agree with what was seen.
                        $obs[$model] = $usage.total_input
                        Write-LwgStateJson -FileName $obsFile -Data $obs | Out-Null
                    }
                    elseif (-not $trusted -and $prevObs -le $script:LwgContextWindowDefault -and
                            $usage.total_input -gt $script:LwgContextWindowDefault -and
                            $usage.total_input -le $script:LwgContextWindowExtended) {
                        $pendKey = $model + '#pending'
                        $pend = 0
                        if ($null -ne $obs[$pendKey]) { try { $pend = [int]$obs[$pendKey] } catch { $pend = 0 } }
                        if ($pend -gt $script:LwgContextWindowDefault) {
                            $obs[$model] = $(if ($pend -gt $usage.total_input) { $pend } else { $usage.total_input })
                            $obs.Remove($pendKey)
                        } else {
                            $obs[$pendKey] = $usage.total_input
                        }
                        Write-LwgStateJson -FileName $obsFile -Data $obs | Out-Null
                    }
                }

                if (-not $trusted) {
                    if ($state['ctx_untrusted'] -ne $model) {
                        $state['ctx_untrusted'] = $model
                        $stateDirty = $true
                        Write-LwgEvent -Event 'ContextWindowUnknown' -Payload $payload -Extra @{
                            module       = 'context_pressure'
                            model        = $model
                            total_input  = $usage.total_input
                            assumed      = $winTok
                            window_source = $src
                            detail       = 'occupancy exceeds the assumed window; no percentage reported. Set module_config.context_pressure.window_tokens for this model.'
                        } | Out-Null
                    }
                } else {
                    $warnPct = [double](Get-LwgThreshold -Config $cfg -Group 'context' -Key 'warn_pct'     -Default 75)
                    $critPct = [double](Get-LwgThreshold -Config $cfg -Group 'context' -Key 'critical_pct' -Default 90)

                    # The CLI's own arithmetic: round(total_input / window * 100),
                    # clamped to 0..100.
                    $pct = [Math]::Round(($usage.total_input / [double]$winTok) * 100)
                    if ($pct -lt 0)   { $pct = 0 }
                    if ($pct -gt 100) { $pct = 100 }

                    $level = 'ok'
                    if     ($pct -ge $critPct) { $level = 'critical' }
                    elseif ($pct -ge $warnPct) { $level = 'warn' }

                    $rank  = @{ ok = 0; warn = 1; critical = 2 }
                    $was   = [string]$state['ctx_level']
                    if ([string]::IsNullOrWhiteSpace($was)) { $was = 'ok' }

                    if ($level -ne $was) {
                        $state['ctx_level'] = $level
                        $stateDirty = $true
                        Write-LwgEvent -Event 'ContextPressure' -Payload $payload -Extra @{
                            module        = 'context_pressure'
                            level         = $level
                            previous      = $was
                            used_pct      = $pct
                            total_input   = $usage.total_input
                            output_tokens = $usage.output
                            window_tokens = $winTok
                            window_source = $src
                            model         = $model
                        } | Out-Null
                    }

                    # Advisory only when the level RISES. The status line already
                    # renders context pressure continuously and in colour; a
                    # systemMessage repeating it at every turn end would be noise
                    # that trains the reader to ignore the channel.
                    if ($rank[$level] -gt $rank[$was]) {
                        # THE DENOMINATOR'S PROVENANCE IS PART OF THE NUMBER.
                        # 'default' printed as ", window assumed" and everything
                        # else printed as nothing, so an INFERRED window - one
                        # this code concluded from an earlier turn's occupancy,
                        # not one anybody configured - read exactly like a known
                        # one. The distinction between a known window and an
                        # inferred one is the distinction this module exists to
                        # preserve. 'config' and '1m-tag' stay bare: those are
                        # stated by the operator and by the model id itself.
                        $assumed = switch ($src) {
                            'default'  { ', window assumed' }
                            'observed' { ', window inferred from earlier turns' }
                            default    { '' }
                        }
                        $where   = "$(Format-Tokens $usage.total_input)/$(Format-Tokens $winTok)$assumed"
                        if ($level -eq 'critical') {
                            Add-Advisory "LW-WATCHTOWER context $pct% CRITICAL ($where) - compact now or hand off to a fresh session; work after this point risks a lossy compaction."
                        } else {
                            Add-Advisory "LW-WATCHTOWER context $pct% ($where) - plan for compaction; land or hand off the current thread of work."
                        }
                    }
                }
            }
        } catch {
            try { Write-LwgEvent -Event 'AdvisoryError' -Payload $payload -Extra @{
                module = 'context_pressure'; error = $_.Exception.Message } | Out-Null } catch { }
        }
    }

    # =====================================================================
    # verification_gate  (ADVISORY - it does not gate anything)
    # =====================================================================
    # DATA SOURCE: health.jsonl, written by lib/supervisor.ps1's SubagentStop
    # handler, which records agent_type from the payload. Confirmed against the
    # live log: SubagentStop records carry the MAIN session id, so they join to
    # this Stop event on `session`.
    #
    # HEURISTIC, and its failure modes, stated up front because a governance
    # warning that people cannot reason about gets ignored:
    #
    #   Warn when the newest work-agent SubagentStop for this session is NEWER
    #   than the newest verify-agent SubagentStop (or there is no verify record
    #   at all).
    #
    #   FALSE NEGATIVES - it will stay silent when it should not:
    #     * work done by the main thread itself, with no subagent, is invisible
    #     * a SubagentStop whose agent_type is null is invisible (about half the
    #       records in the inherited log are null - older CLI builds did not
    #       populate the field)
    #     * a worker not on the work_agents list is invisible
    #   FALSE POSITIVES - it will warn when nothing was wrong:
    #     * an implementer dispatched to READ or investigate, changing nothing
    #     * verification done by the user, or by the orchestrator reading the
    #       diff itself, leaves no SubagentStop record
    #     * a verifier run in a different session for the same work
    #
    #   It is gated on evidence of WORK, not on the turn merely ending, which is
    #   what keeps a session that only answered a question from being nagged.
    #
    # HOW A ROLE IS CLASSIFIED, since 30 July 2026: from the `lw-class` key in
    # the role's OWN frontmatter - `work`, `verify` or `neutral` - resolved by
    # Get-LwgAgentClassInfo, which turns the observed agent_type back into the
    # .md file it names and reads the key out of it. That is the design in
    # docs/roles.md, and until this landed nothing anywhere read the key: all six
    # shipped roles declared it, the module was enabled and counted as coverage,
    # and it classified from two hand-maintained name arrays - a switch wired to
    # nothing reporting itself as coverage, which is the founding defect this
    # plugin exists to catch, committed by the plugin that exists to catch it.
    #
    # THE ARRAYS ARE KEPT, AS A FALLBACK AND ONLY AS ONE. `lw-class` wins
    # wherever it is present. They are consulted only for a role that declares
    # no class, and they are not redundant: the generic entries (`implementer`,
    # `qa-agent`, `code-review`) name no file at all and so can never declare a
    # key. The four hq-* names that sat here alongside them were struck on 31
    # July 2026, after the user-scope role files that carried them had been
    # renamed to lw-* and given an explicit lw-class; the consequence for a
    # machine that still has hq-* role files is recorded at config.json's
    # $classifier_comment. Removing the generic entries would silently
    # unclassify every role that has no file to declare a key in.
    #
    # A NAME THAT RESOLVES TO NO FILE AND IS IN NEITHER ARRAY IS "NO
    # INFORMATION", handled exactly like an empty agent_type: it neither arms the
    # gate nor disarms it. It is NOT counted as work, because nagging on evidence
    # of nothing is how this channel gets ignored, and it is NOT counted as
    # verification, because that would silence the gate on the same absence.
    if ($onVerify) {
        try {
            if (-not [string]::IsNullOrWhiteSpace($sessionId)) {
                # The DEFAULTS carry the plugin's own shipped roles as well as the
                # bare names, so this module is not blind on an install whose
                # config.json is missing, stripped or unreadable. Get-LwgConfig
                # fails open to built-in defaults, and a default list naming only
                # roles that exist on one laptop is a gate that reports itself
                # configured and matches nothing.
                $workAgents = @(Get-LwgModuleOption -Config $cfg -Module 'verification_gate' -Key 'work_agents' `
                    -Default @('lw-implementer', 'lw-scribe', 'lw-healer',
                               'implementer', 'scribe', 'engineer', 'healer'))
                $verifyAgents = @(Get-LwgModuleOption -Config $cfg -Module 'verification_gate' -Key 'verify_agents' `
                    -Default @('lw-verifier', 'verifier', 'qa-agent',
                               'code-review', 'security-adversarial-review'))

                # Both the namespaced and the bare spelling of every configured
                # name go into the set. The match below normalises the OBSERVED
                # side only, and an operator may have written either spelling
                # here, so the configured side is expanded rather than assumed.
                # See the note on the prefix at the match itself.
                $workSet   = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
                foreach ($a in $workAgents)   { foreach ($n in (Expand-LwgAgentName $a)) { [void]$workSet.Add($n) } }
                $verifySet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
                foreach ($a in $verifyAgents) { foreach ($n in (Expand-LwgAgentName $a)) { [void]$verifySet.Add($n) } }

                # @() is load-bearing. Get-LwgHealthRecords emits a stream, and
                # an unwrapped single record has a $null .Count that compares as
                # 0 - which would make this module report "no work happened" on
                # exactly the sessions that had one work record.
                $recs = @(Get-LwgHealthRecords -Session $sessionId -Event 'SubagentStop' -Tail 400)

                # One sweep. ISO-8601 'o' timestamps compare correctly as plain
                # strings, so the newest of each kind is just a running maximum -
                # Sort-Object with a script block over a few hundred records
                # costs more than everything else this module does put together.
                $workCount   = 0
                $verifyCount = 0
                $workTs      = ''
                $verifyTs    = ''
                $workTypes   = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

                # How each classified record was decided, for the event record.
                # A gate that cannot say WHY it classified something the way it
                # did is a gate nobody can debug, and these two numbers are also
                # how the migration off the arrays is measured.
                $byClass = 0
                $byName  = 0
                $unknown = 0

                # The project scope of the precedence chain, from the payload's
                # own cwd. Absent or unreadable simply drops that scope: the user
                # and plugin scopes still resolve, and a role that only exists in
                # a project directory this hook cannot see is unresolved, which is
                # "no information" like every other unresolved name.
                $projRoot = [string]$payload.cwd

                # One VERDICT per distinct agent_type, not per record. A hashtable,
                # so the lookup is case-insensitive on the key exactly as the two
                # name sets are.
                #
                # Get-LwgAgentClassInfo memoises the file lookup already, so this
                # saves no I/O - it saves the CALL. Measured on one machine: 400
                # fully-memoised calls to it cost 42 ms of pure PowerShell
                # function-call overhead, for an answer that cannot differ between
                # two records naming the same role. A hashtable hit is what is
                # left, and there are five distinct names behind those 400 records.
                $verdict = @{}

                foreach ($r in $recs) {
                    if ($r.event -ne 'SubagentStop') { continue }
                    $at = [string]$r.agent_type

                    # AN EMPTY agent_type IS "NO INFORMATION", NEVER "NOT A
                    # VERIFIER". About 28% of observed SubagentStop records carry
                    # the empty string, and such a record is unclassifiable by any
                    # scheme: it can neither arm the gate nor disarm it. `continue`
                    # is the only correct handling and it must stay - counting it
                    # as work would nag on evidence of nothing, and counting it as
                    # verification would silence the gate on the same evidence.
                    if ([string]::IsNullOrWhiteSpace($at)) { continue }

                    $ts = [string]$r.ts

                    # --- 1. the role's own declaration ----------------------
                    # A PLUGIN-SHIPPED ROLE ARRIVES NAMESPACED. Verified from a
                    # live record: dispatching this plugin's own explorer logs
                    # agent_type "lw-watchtower:lw-explorer", while the same role
                    # copied into ~/.claude/agents logs it bare. Both
                    # spellings have to keep working, so the prefix is stripped
                    # for the lookup and used to decide which scope to search
                    # first. Get-LwgAgentClassInfo does both, and memoises, so a
                    # session's handful of distinct names costs a handful of
                    # [IO.File]::Exists probes for the whole 400-record sweep.
                    if ($verdict.ContainsKey($at)) {
                        $v    = $verdict[$at]
                        $cls  = [string]$v.cls
                        $how  = [string]$v.how
                    } else {
                        $ai   = Get-LwgAgentClassInfo -Name $at -ProjectRoot $projRoot
                        $cls  = [string]$ai.class
                        $bare = [string]$ai.bare
                        $how  = 'lw-class'

                        # --- 2. the configured arrays, ONLY as a fallback ---
                        # Reached when the role declares no lw-class: a role
                        # file written before the key existed and never given
                        # one, a name with no file at all, a role belonging to
                        # another plugin. An operator may have written either
                        # spelling into config.json, so both are tried against
                        # both spellings of the observed value.
                        if ($cls -eq '') {
                            $how = 'config-name'
                            if     ($workSet.Contains($at)   -or $workSet.Contains($bare))   { $cls = 'work' }
                            elseif ($verifySet.Contains($at) -or $verifySet.Contains($bare)) { $cls = 'verify' }
                        }
                        $verdict[$at] = @{ cls = $cls; how = $how }
                    }

                    # --- 3. act on the class, and on nothing else -----------
                    # 'neutral' is a REAL answer and deliberately does neither:
                    # an explorer that read files and found nothing wrong has not
                    # verified anything, and classing it as verification would let
                    # a search satisfy a gate that exists to demand a check.
                    # '' after both steps is NO INFORMATION and falls through the
                    # same way an empty agent_type does.
                    if ($cls -eq 'work') {
                        if ($how -eq 'lw-class') { $byClass++ } else { $byName++ }
                        $workCount++
                        [void]$workTypes.Add($at)
                        if ($ts -gt $workTs) { $workTs = $ts }
                    } elseif ($cls -eq 'verify') {
                        if ($how -eq 'lw-class') { $byClass++ } else { $byName++ }
                        $verifyCount++
                        if ($ts -gt $verifyTs) { $verifyTs = $ts }
                    } elseif ($cls -eq 'neutral') {
                        $byClass++
                    } else {
                        $unknown++
                    }
                }

                if ($workCount -gt 0) {

                    $unverified = ($verifyTs -eq '' -or ($verifyTs -lt $workTs))
                    if ($unverified -and ([string]$state['verify_warned_ts']) -ne $workTs) {
                        $state['verify_warned_ts'] = $workTs
                        $stateDirty = $true

                        $who = (@($workTypes) -join ', ')
                        Write-LwgEvent -Event 'VerificationMissing' -Payload $payload -Extra @{
                            module           = 'verification_gate'
                            work_agents_seen = $who
                            work_count       = $workCount
                            verify_count     = $verifyCount
                            last_work_ts     = $workTs
                            last_verify_ts   = $verifyTs
                            # HOW, not just what. by_lw_class counts records
                            # decided from the role's own frontmatter,
                            # by_config_name those that fell back to the arrays,
                            # and unclassified those that reached neither - the
                            # records this module deliberately drew NO conclusion
                            # from, which is the number to look at first when it
                            # says something surprising.
                            by_lw_class      = $byClass
                            by_config_name   = $byName
                            unclassified     = $unknown
                        } | Out-Null

                        $tail = if ($verifyCount -gt 0) { 'the last verification predates it' } else { 'nothing has independently verified it' }
                        # The role NAMED here is the one this plugin ships, not
                        # the one on the author's laptop: an advisory that tells
                        # every installing user to dispatch an agent that exists
                        # only in someone else's ~/.claude/agents is advice that
                        # cannot be followed.
                        Add-Advisory "LW-WATCHTOWER verification: $workCount work subagent(s) finished this session ($who) and $tail. Read the changed files or dispatch a verify-class agent (lw-verifier) before reporting this as done."
                    }
                }
            }
        } catch {
            try { Write-LwgEvent -Event 'AdvisoryError' -Payload $payload -Extra @{
                module = 'verification_gate'; error = $_.Exception.Message } | Out-Null } catch { }
        }
    }

    # =====================================================================
    # docs_coupling  (ADVISORY)
    # =====================================================================
    # DATA SOURCE: the per-session path list lib/post_edit.ps1 appends to on
    # PostToolUse. Both halves gate on the same flag, so with the flag off there
    # is no list to read and nothing to say.
    #
    #   Warn when source files changed this session and no documentation did.
    #
    #   Blind spots, stated: only edits made THROUGH Write/Edit/NotebookEdit are
    #   recorded, so a file rewritten by a shell command is invisible; and data
    #   files (JSON, YAML, lockfiles) are classified 'other' on purpose, because
    #   counting lockfile churn as source is how this turns into noise nobody
    #   reads.
    # The edit list is read and classified ONCE here, because mission_drift
    # needs the same three buckets. Reading and re-classifying it per module
    # would pay the same ~35 ms twice for an identical answer.
    $srcPaths   = @()
    $docPaths   = @()
    $otherCount = 0
    $haveEdits  = $false
    if ($onDocs -or $onMission) {
        try {
            $editFile = Join-Path (Get-LwgStateDir) ("edits-$sessKey.txt")
            if (Test-Path -LiteralPath $editFile) {
                # One pass, one set, one rules build. The obvious shape - two
                # Where-Object passes each rebuilding the classification lists
                # per path - measured 284 ms on 200 edits, which is not
                # acceptable on a hook that runs at every turn end.
                $rules = Get-LwgDocRules -Config $cfg
                $seen  = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

                foreach ($line in @(Get-LwgTailLines -Path $editFile -Bytes 262144)) {
                    if (-not $seen.Add($line)) { continue }
                    switch (Get-LwgPathClass -Path $line -Config $cfg -Rules $rules) {
                        'source' { $srcPaths += $line }
                        'doc'    { $docPaths += $line }
                        default  { $otherCount++ }
                    }
                }
                $haveEdits = $true
            }
        } catch {
            # THE READ IS SHARED AND SO IS THE ATTRIBUTION, which it was not.
            # The guard five lines up is `$onDocs -or $onMission`; this handler
            # named docs_coupling unconditionally, so on a session running
            # `docs_coupling: false, mission_drift: true` - a supported pair,
            # and the one lib/post_edit.ps1's gate was widened to keep working -
            # the evidence log recorded an error against a module that was not
            # running and recorded nothing against the module that had just
            # silently produced no assessment. `module` is the only routing a
            # record carries; bin/lwg-sitrep.ps1 and bin/lwg-evidence.ps1 read
            # it, so a wrong value there is a wrong report, not a cosmetic one.
            #
            # The value is now the modules the read was actually for, joined -
            # 'docs_coupling', 'mission_drift' or 'docs_coupling+mission_drift'.
            # `phase = 'read-edits'` still distinguishes this handler from
            # docs_coupling's own below, which is what made the misattribution
            # survivable for anyone who knew the code.
            $editOwners = @(@(if ($onDocs) { 'docs_coupling' }) + @(if ($onMission) { 'mission_drift' })) -join '+'
            try { Write-LwgEvent -Event 'AdvisoryError' -Payload $payload -Extra @{
                module = $editOwners; phase = 'read-edits'; error = $_.Exception.Message } | Out-Null } catch { }
        }
    }

    if ($onDocs) {
        try {
            if ($haveEdits) {
                $warnedAt = 0
                if ($null -ne $state['docs_warned_sources']) { $warnedAt = [int]$state['docs_warned_sources'] }

                # Re-warn only when MORE source files have been touched since the
                # last warning. Without this the same untouched-docs condition
                # repeats at every turn end for the rest of the session.
                if ($srcPaths.Count -gt 0 -and $docPaths.Count -eq 0 -and $srcPaths.Count -gt $warnedAt) {
                    $state['docs_warned_sources'] = $srcPaths.Count
                    $stateDirty = $true

                    # Split-Path -Leaf RETURNS THE WHOLE STRING when there is no
                    # separator in it, so it is not a length bound and was being
                    # relied on as one. A payload-controlled tool_input.file_path
                    # that classified as source therefore went whole into this
                    # sample, into the DocsCoupling record in a log that does not
                    # rotate, and into the systemMessage below. lib/post_edit.ps1
                    # now caps the line it writes; this cap is independent on
                    # purpose - two files write into this pipeline's data and the
                    # reader must not depend on the writer having been fixed.
                    $sample = @($srcPaths | Select-Object -First 3 |
                                ForEach-Object { Get-LwgRedacted -Text (Split-Path $_ -Leaf) -MaxLength 160 })
                    Write-LwgEvent -Event 'DocsCoupling' -Payload $payload -Extra @{
                        module       = 'docs_coupling'
                        source_files = $srcPaths.Count
                        doc_files    = $docPaths.Count
                        other_files  = $otherCount
                        sample       = $sample
                    } | Out-Null

                    $more = if ($srcPaths.Count -gt 3) { " (+$($srcPaths.Count - 3) more)" } else { '' }
                    Add-Advisory "LW-WATCHTOWER docs: $($srcPaths.Count) source file(s) changed - $($sample -join ', ')$more - and no documentation did. If any of this is user-visible, update the docs in the same change."
                }
            }
        } catch {
            try { Write-LwgEvent -Event 'AdvisoryError' -Payload $payload -Extra @{
                module = 'docs_coupling'; error = $_.Exception.Message } | Out-Null } catch { }
        }
    }

    # =====================================================================
    # mission_drift  (ADVISORY - ON BY DEFAULT SINCE 30 JULY 2026)
    # =====================================================================
    # DATA SOURCE: the transcript, read INCREMENTALLY. Every hook receives
    # transcript_path, and the operator's typed prompts are records in it. Each
    # turn this reads only the bytes the file has grown by since the last turn -
    # so the cost is one turn's growth, not the size of the session - and folds
    # any new prompts into a set of anchors carried in the session's state file.
    #
    # WHAT IT KEEPS OF A PROMPT, AND WHY IT KEEPS IT AS TEXT. This module is the
    # only one here that reads what the operator TYPED, so it is the only one
    # that can copy a secret out of a prompt, and it keeps two things: anchors on
    # disk in advisory-<sessionkey>.json, and up to four of them quoted in the
    # advisory. Every prompt therefore goes through Get-LwgRedacted before it is
    # tokenised - see the call below for why that is the only workable point.
    #
    # A HASH WOULD SERVE THE MATCHING AND WAS REJECTED ANYWAY. The comparison
    # this module performs is exact, case-insensitive equality between an anchor
    # and a segment of an edited path, so hashing both sides would answer the
    # same question with nothing readable left on disk. Two things stop it. The
    # advisory NAMES the anchors it compared against - "you named: ..." is the
    # whole of what makes a drift warning arguable rather than mystifying, and
    # by the time one fires the prompt that named the work is many turns back,
    # so the persisted form is the only copy there is. And the matching itself
    # lives in Test-LwgMissionAccounted and Get-LwgPathSegments in
    # lib/common.ps1, which are shared: hashing here would mean either changing
    # them for every caller or reimplementing them at this call site, and a
    # second copy of the segmenting rules is how the two copies drift apart.
    # Redaction at the point of ingest is what is done instead, and its limit -
    # the pattern list, and nothing beyond it - is stated at the call.
    #
    # There is deliberately NO UserPromptSubmit hook. That is the obvious place
    # to capture a mission and it costs a whole PowerShell process (285 ms
    # measured) on every prompt, spawned whether the module is on or off,
    # because a hook registration cannot be made conditional. Reading the
    # transcript costs ~137 ms inside a process that already exists, and costs
    # exactly nothing when the flag is off.
    #
    # THE TRIGGER, stated exactly, because a warning nobody can reason about is
    # a warning nobody trusts. It fires only when ALL of these hold:
    #
    #   1. the operator has named at least one concrete path or filename in some
    #      prompt this session. With nothing named there is no basis to judge
    #      anything, so the module says nothing at all;
    #   2. at least `min_files` source or documentation files were edited;
    #   3. EVERY one of them is outside the workspace root (git root, else cwd) -
    #      relaxable with require_outside_root:false, at a real cost in false
    #      positives;
    #   4. and NONE of them shares a directory segment, a filename stem or an
    #      ordinary word with anything the operator has named, in ANY prompt this
    #      session - not just the first.
    #
    # WHY A PIVOT CANNOT TRIP IT. Anchors ACCUMULATE across the whole session
    # and are never reset. The moment the operator redirects the work, that new
    # prompt's nouns and paths become anchors too, and the work that follows
    # matches them. Drift is work that matches NOTHING that was ever asked for -
    # a pivot is, by construction, something that was asked for.
    #
    # THAT HOLDS ONLY BELOW max_anchors, and it is a guarantee with an expiry
    # rather than a guarantee. Accumulation STOPS at the cap instead of making
    # room, and the total is carried in the state file and only grows, so the
    # first turn to reach 400 anchors is the last turn that learns anything.
    # The module latches silent when that happens - see the saturation check
    # below the parse loop - which stops it warning about a pivot it could not
    # see, and does NOT restore the property. Once the cap is reached the pivot
    # argument no longer applies for the rest of the session.
    #
    # FALSE POSITIVES it can still produce: a redirection phrased with no
    # concrete noun at all ("now fix the other repo") followed by edits in a
    # tree nobody named. FALSE NEGATIVES, which are many and deliberate: any
    # drift inside the workspace root, any drift that also touched something
    # asked for, and anything done by a shell command rather than an edit tool.
    #
    # IT IS ON BY DEFAULT since 30 July 2026, by explicit owner decision. It
    # shipped OFF because that trigger was never validated against real
    # sessions, and it still has not been - so the false-positive class named
    # two paragraphs up is live for every install. What IS tested, from 31 July
    # 2026, is that the code does what this comment says: tests/stop_behaviour.ps1
    # runs this block in a real child process across several turns, and the
    # pivot path above is now RUN rather than read - anchors that stop
    # accumulating turn that case red. A test of the trigger is not a validation
    # of the trigger; do not read one as the other. See the registry note in
    # lib/common.ps1 and "mission_drift" in docs/modules.md.
    if ($onMission) {
        try {
            $mdMaxScan  = [int](Get-LwgModuleOption -Config $cfg -Module 'mission_drift' -Key 'max_scan_bytes'       -Default 2097152)
            $mdMaxAnch  = [int](Get-LwgModuleOption -Config $cfg -Module 'mission_drift' -Key 'max_anchors'          -Default 400)
            $mdMinFiles = [int](Get-LwgModuleOption -Config $cfg -Module 'mission_drift' -Key 'min_files'            -Default 3)
            # The record bound was a bare literal in the parse loop while the
            # three above were knobs, and it is the bound most likely to want
            # raising: it bites on a RESUMED session, where one slice is the
            # whole transcript, and latching costs that session the module for
            # the rest of its life. Floored at 1 rather than trusted - a 0 or a
            # negative would latch on the first record and silence the module
            # unconditionally, which is a config typo turning a module off
            # without saying so.
            $mdMaxRec   = [int](Get-LwgModuleOption -Config $cfg -Module 'mission_drift' -Key 'max_parse_records'    -Default 400)
            if ($mdMaxRec -lt 1) { $mdMaxRec = 400 }
            # A BOOLEAN OPTION, so it goes through Get-LwgModuleFlag and not a
            # bare [bool]: only a real boolean is a setting here, by the same
            # rule as the `modules` block. The three numeric knobs above are
            # numbers and the rule does not apply to them.
            $mdOutside  = Get-LwgModuleFlag -Config $cfg -Module 'mission_drift' -Key 'require_outside_root' -Default $true

            # WHAT SHAPE THE PERSISTED ANCHORS ARE IN, written into the state
            # file as md_redact and compared against it on the way back. Not a
            # tuning knob and not read from config: it is this code's own record
            # of what it wrote, and an operator has no business setting it. 1 is
            # "every anchor in this file came out of a prompt that had been
            # through Get-LwgRedacted first". 0, which is what absent reads as,
            # is a file written before that was true. See the rebuild below.
            $mdRedactMark = 1

            # The workspace root: the git root when there is one, else cwd. It is
            # both the "inside" test in condition 3 and the source of the
            # segments that carry no information (see Get-LwgMissionScope).
            $mdRoot = ''
            $mdInfo = $(if ($null -ne $gitInfo) { $gitInfo } else { Get-LwgRepoInfo -Path ([string]$payload.cwd) })
            if ($null -ne $mdInfo -and $mdInfo.root) { $mdRoot = [string]$mdInfo.root }
            if ([string]::IsNullOrWhiteSpace($mdRoot)) { $mdRoot = [string]$payload.cwd }
            $mdScope = Get-LwgMissionScope -Root $mdRoot

            # Rehydrate the anchors carried over from earlier turns. @() is
            # load-bearing: a single-element array round-trips through JSON as a
            # bare string, and foreach over a bare string yields the string,
            # which is what we want - but .Count on it would be $null.
            $mdAnchors = New-LwgMissionAnchors
            foreach ($a in @($state['md_paths'])) { if (-not [string]::IsNullOrWhiteSpace([string]$a)) { if ($mdAnchors.paths.Add([string]$a)) { $mdAnchors.total++ } } }
            foreach ($a in @($state['md_words'])) { if (-not [string]::IsNullOrWhiteSpace([string]$a)) { if ($mdAnchors.words.Add([string]$a)) { $mdAnchors.total++ } } }

            $mdIncomplete = ($state['md_incomplete'] -eq $true)
            $mdOffset = 0
            if ($null -ne $state['md_offset']) { try { $mdOffset = [long]$state['md_offset'] } catch { $mdOffset = 0 } }

            # --- state written before prompts were redacted -----------------
            # UNTIL THE REDACTION BELOW LANDED, EVERY ANCHOR IN THIS FILE WAS
            # RAW PROMPT TEXT. A session that was already running when the
            # plugin was updated has such a file on disk, and rehydrating it
            # would take those anchors straight back into the set this turn
            # persists and quotes in its advisory - so the fix would hold for
            # new sessions and leave the old ones leaking, which is a fix that
            # overstates itself.
            #
            # THEY CANNOT BE CLEANED IN PLACE, and that is why this discards
            # rather than launders. An anchor is one lowercased token with its
            # sentence gone: 'zebrakestrel99' is unrecognisable as a credential
            # once `api_key = ` is no longer beside it, and an AWS-shaped value
            # no longer matches its own pattern once it has been lowercased.
            # Get-LwgRedacted needs the surrounding text to decide, so the only
            # honest place to run it is on the prompt, which is where it now
            # runs. Anything already reduced to a token is past saving.
            #
            # SO THE ANCHORS GO AND THE OFFSET GOES BACK TO ZERO: the transcript
            # is re-read from the start on this one turn and the anchors are
            # rebuilt through the redaction path, which costs one full read once
            # per upgraded session and nothing afterwards.
            #
            # A REBUILD IS THE ONE READ THAT CAN HIT EITHER BOUND, and BOTH of
            # them now latch. Bigger than max_scan_bytes and the read is skipped;
            # more than 400 records and the parse stops early. Either way
            # md_incomplete is set and the module falls silent for the rest of
            # the session rather than judging on an anchor set it knows is short -
            # see the latch below the parse loop, which had to be added for this
            # rebuild to be safe. Silence is the direction this module fails in.
            #
            # md_assessed and md_sig are deliberately NOT reset. They record what
            # has already been said, and clearing them would re-fire a warning
            # the operator has already read.
            #
            # The marker is a NUMBER, not a boolean, so a later change to what is
            # persisted can raise it and get the same one-turn rebuild. It is
            # written where the anchors are written, below, and never on its own -
            # a marker claiming the file is redacted must not be able to land in a
            # file whose anchors were not rewritten in the same pass.
            #
            # Read the way md_offset is read directly above, and for the same
            # reason: a hand-edited or half-written state file must not throw out
            # of this block. A value this cannot parse reads as 0, which is the
            # same as absent, which rebuilds - the safe answer either way.
            $mdMark = 0
            if ($null -ne $state['md_redact']) { try { $mdMark = [int]$state['md_redact'] } catch { $mdMark = 0 } }

            $mdMigrated = $false
            if ($mdMark -ne $mdRedactMark -and
                ($null -ne $state['md_paths'] -or $null -ne $state['md_words'] -or $null -ne $state['md_offset'])) {
                $mdAnchors  = New-LwgMissionAnchors
                $mdOffset   = 0
                $mdMigrated = $true
            }

            $slice = Read-LwgAppendedLines -Path ([string]$payload.transcript_path) -Offset $mdOffset -MaxBytes $mdMaxScan

            # A skipped region may have contained the very prompt that would have
            # excused this turn's work, so the module stops speaking for the rest
            # of the session rather than judging on a partial record. Silence on
            # incomplete evidence, never a guess.
            if ($slice.truncated) { $mdIncomplete = $true }

            $mdPrompts = 0
            $mdParsed  = 0
            $mdBounded = $false
            foreach ($line in @($slice.lines)) {
                if ($mdParsed -ge $mdMaxRec) { $mdBounded = $true; break }   # bound the parse, not just the read
                # THE FILTER BELOW IS STILL LOOSE AND THE BUDGET IS STILL SPENT
                # ON IT. `-notlike '*user*'` is a case-insensitive substring
                # test on the raw JSON line, and every transcript record carries
                # a cwd - which on the only supported platform is routinely
                # under the user profile directory, whose path carries the
                # segment "Users". So assistant and
                # system records pass it, $mdParsed counts them, and the budget
                # is spent on the transcript rather than on prompts. Tightening
                # it to '*"type":"user"*' is the obvious move and is NOT made
                # here: if a real transcript shape does not carry that literal,
                # this module reads zero prompts while reporting active, which
                # is the founding defect of this plugin, and no real-transcript
                # specimen was available to check against. The consequence of
                # leaving it is that the latch below fires sooner than it needs
                # to - silence, which is this module's documented failure
                # direction - so the loose filter costs coverage, never a wrong
                # warning.
                if ($line.Length -gt 262144)          { continue }
                if ($line -notlike '*user*')          { continue }
                if ($line -like '*"toolUseResult"*')  { continue }
                if ($line -like '*"isSidechain":true*') { continue }
                $rec = $null
                try { $rec = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
                $mdParsed++
                $txt = Get-LwgPromptText -Record $rec
                if ($null -eq $txt) { continue }
                $mdPrompts++

                # --- REDACT BEFORE TOKENISING -----------------------------
                # THIS IS THE OPERATOR'S TYPED PROMPT and everything downstream
                # of this line keeps a piece of it: the tokens become anchors,
                # the anchors are written to advisory-<sessionkey>.json in the
                # state directory, and up to four of them are quoted back in the
                # systemMessage this hook emits. None of that passed through
                # Get-LwgRedacted, so a credential pasted into a prompt was
                # copied to disk and into the session by a module that is ON BY
                # DEFAULT.
                #
                # TOKENISING IS NOT REDACTION, which is the assumption that made
                # this look safe. Add-LwgMissionAnchors splits on whitespace and
                # punctuation, and SOME credential shapes survive that split
                # whole: an AWS-shaped key id is one unbroken alphanumeric run,
                # so it comes through the split intact, matches the ordinary-word
                # pattern and is stored lowercased but otherwise complete. A key
                # inside a pasted path survives the same way as one of that
                # path's segments, and a path anchor is the kind the advisory
                # QUOTES.
                #
                # THAT SENTENCE USED TO READ "no credential shape in
                # $script:LwgSecretPatterns contains any of those characters",
                # AND IT WAS FALSE ABOUT A FIVE-ELEMENT LIST IN THIS REPOSITORY.
                # private_key is '-----BEGIN(?:[A-Z ]+)?PRIVATE KEY-----', which
                # carries a literal SPACE - character 32, the first entry in
                # $script:LwgMissionSeparators - and slack_token and github_pat
                # carry '-' and '_'. The claim was load-bearing: it was the whole
                # argument for why tokenising was not already redaction, and it
                # was stated as a property of a list anyone can read. Splitting
                # DOES break some shapes up; what matters is that it breaks them
                # into pieces rather than removing them, and a piece of a
                # credential in a quoted advisory is still a piece of a
                # credential. That is the argument, and it does not need the
                # false absolute to stand.
                #
                # IT HAS TO HAPPEN HERE, ON THE WHOLE PROMPT, and not on the way
                # out. Get-LwgRedacted decides from context - `api_key = ` in
                # front of a value, the case of the characters in it - and a
                # token that has already been split off and lowercased has none
                # of that left to read. There is exactly one point where the
                # sentence is still intact, and this is it.
                #
                # CONTROL CHARACTERS ARE FLATTENED FIRST, and that is not
                # cosmetic. Get-LwgRedacted turns a newline into a literal
                # backslash-n because its other callers print into a fixed-column
                # report, and a backslash arriving in this tokeniser is read as a
                # PATH SEPARATOR - so an ordinary two-line prompt would start
                # producing path anchors out of prose, and a path anchor is what
                # gives this module standing to speak at all. Mapping them to
                # spaces first keeps the split exactly where it already was: CR,
                # LF and TAB are already separators here, so for every prompt
                # that does not contain an exotic control character this changes
                # nothing whatsoever.
                #
                # TRUNCATION IS TURNED OFF, deliberately, by asking for a cap
                # nothing can exceed. The 200-character default exists because
                # this function's usual output is one field of one log record;
                # here the output is fed to a tokeniser, and cutting the prompt
                # at 200 characters would silently throw away every file the
                # operator named after the first sentence. Redaction runs before
                # truncation inside that function, so the cap is not what makes
                # this safe and switching it off costs nothing.
                #
                # WHAT THIS DOES NOT DO, restated on 3 August 2026 because the
                # version that stood here was wrong twice in one sentence. It
                # said this was "exactly as good as the pattern list in
                # lib/common.ps1 and no better", scoping the gap to "a shape
                # nobody enumerated", and it named ONE destination for whatever
                # got through - "still written to the state file".
                #
                # BOTH HALVES WERE FALSE. An ENUMERATED shape got through: the
                # private_key rule matched and replaced the BEGIN LINE ONLY,
                # leaving the base64 body, and base64 contains '/', which
                # Add-LwgMissionAnchors reads as a PATH SEPARATOR - so the body
                # was promoted to the anchor kind this advisory QUOTES. Measured
                # end to end by case B19 against the pre-fix tree, the message
                # it emitted read:
                #
                #   (you named: 3dfghjklzxcvbnmqwertyuio+mnbvcxzlkjhg,
                #    abcdefghijklmnop, miieowibaakcaqea0aqrstuvwxyz, module)
                #
                # THREE of the four quoted slots are private key material, and
                # parser.ps1 - the file the operator actually named - has been
                # pushed out of the list to make room. Three rather than four
                # because anchors sort: `module` survived, `parser.ps1` did not.
                # That is the SECOND destination, the one the opening paragraph
                # of this block identifies and the old text did not admit. The
                # BEGIN-line-only gap is closed in lib/common.ps1 as of the
                # same date.
                #
                # WHAT IS ACTUALLY LEFT, both destinations named. A bare
                # high-entropy string in a shape nobody enumerated - a
                # 32-character hex API key, a passphrase typed as a word - still
                # tokenises into an anchor, is still written to
                # advisory-<sessionkey>.json, AND can still be QUOTED BACK in
                # the systemMessage: measured, a 32-hex value sorts first and
                # leads the "you named:" list. Anchors are sorted, so an unnamed
                # credential is not merely present, it is preferentially shown.
                #
                # AND OVER-REDACTION COSTS THIS MODULE ITS STANDING, which is the
                # other direction and is not a leak. Routing the prompt through
                # Get-LwgRedacted means the word "token:" in front of a path
                # makes the PATH the value: measured on this tree, "Rework the
                # token: C:/work/ws/module/parser.ps1 handling please." redacts
                # to "Rework the token: [REDACTED] handling please." and yields
                # ZERO path anchors, where the same sentence without that one
                # word yields FOUR (work, module, parser.ps1, parser). Zero path
                # anchors means the module has no standing and stays silent.
                # Silence is its documented failure direction, so this is the
                # acceptable one - but B12 pins a single prompt shape, and a
                # sibling shape defeats what B12 is for.
                $mdSafe = Get-LwgRedacted -Text ([regex]::Replace($txt, '\p{Cc}', ' ')) -MaxLength ([int]::MaxValue)
                [void](Add-LwgMissionAnchors -Text $mdSafe -Anchors $mdAnchors -Scope $mdScope -MaxAnchors $mdMaxAnch)
            }

            # --- THE RECORD BOUND LATCHES THE SAME WAY THE BYTE BOUND DOES ---
            # THERE ARE TWO WAYS THIS MODULE CAN END A TURN WITH A HOLE IN ITS
            # PICTURE, and until this line only one of them said so. max_scan_bytes
            # bounds what is READ and latches md_incomplete above; the 400 on the
            # loop bounds what is PARSED and, until now, broke out silently -
            # leaving anchors from the first 400 records, an offset written at end
            # of file, and md_incomplete FALSE. The module then judged the session
            # believing it had seen all of it. That is the one thing the paragraph
            # above forbids, reached by the other bound.
            #
            # IT MATTERS MORE NOW THAN IT DID, which is why it is being closed
            # here rather than left. The bound is per-SLICE, and a slice was one
            # turn's growth, so 400 typed prompts in a single turn was not a real
            # session. Two paths bulk-parse: the first turn of a session whose
            # transcript already exists (a resumed one), and - since the rebuild
            # above - the first turn after an update. Both hand this loop the
            # whole session at once, which is exactly where 400 is reachable.
            #
            # LATCHING COSTS SILENCE, WHICH IS THE DIRECTION THIS MODULE FAILS IN
            # BY DESIGN. The alternative is a warning built on an anchor set that
            # is missing everything the operator named after the 400th record -
            # a false positive, on a module that is on by default, with nothing
            # telling the reader the set was short. Silence on incomplete
            # evidence, never a guess: the same rule, applied to the same kind of
            # hole.
            if ($mdBounded) { $mdIncomplete = $true }

            # --- AND SO DOES A SATURATED ANCHOR SET ---------------------------
            # THERE IS A THIRD WAY TO END A TURN WITH A HOLE IN THE PICTURE and
            # it is the one that breaks the module's headline argument.
            # Add-LwgMissionAnchors stops at MaxAnchors with a `break`, not a
            # `continue`, and the total it tests is rehydrated from the state
            # file every turn and only ever grows. So the first turn that
            # reaches 400 is the last turn that learns anything: every prompt
            # after it contributes nothing, for the rest of the session.
            #
            # WHAT THAT COSTS IS THE PIVOT PROPERTY, exactly. "A pivot cannot
            # trip it" holds because the redirecting prompt's own nouns become
            # anchors and the work that follows matches them. With the set
            # saturated that prompt contributes no anchors, the work that
            # follows matches nothing, and the module warns that the operator
            # never asked for work they asked for one turn ago - while quoting
            # four anchors from before the pivot as "you named:". That is the
            # case docs/modules.md calls the one the module was built around.
            #
            # LATCHING IS THE SAME ANSWER THE OTHER TWO BOUNDS GET, and it is
            # the only one available here. The better fix is eviction - word
            # anchors can only ever EXCUSE a file, so dropping the oldest words
            # to make room can add a warning and never remove the ability to
            # excuse recent work - but that lives in Add-LwgMissionAnchors in
            # lib/common.ps1, which this change does not own. So this fails
            # honestly rather than preserving the property: silence on
            # incomplete evidence, never a guess.
            #
            # IT CAN LATCH ONE TURN EARLY, and that is stated rather than left
            # to be discovered. The test is `total -ge MaxAnchors`, which is
            # true of a set that landed exactly on the cap with nothing further
            # to add - a session that would have carried on correctly is
            # silenced anyway. Distinguishing the two needs a saturation signal
            # out of Add-LwgMissionAnchors, which is the same out-of-scope file;
            # erring towards silence is the direction this module fails in.
            #
            # ONE EVENT, ONCE. The condition is written to lw-watchtower.jsonl the
            # first time it bites and never again, because md_incomplete is
            # persisted below and rehydrated at the top of the next turn, which
            # short-circuits this test. Without the record an operator reading
            # the log cannot tell "400 anchors and still accumulating" from
            # "400 anchors and deaf since turn 5".
            if (-not $mdIncomplete -and $mdAnchors.total -ge $mdMaxAnch) {
                $mdIncomplete = $true
                Write-LwgEvent -Event 'MissionAnchorsCapped' -Payload $payload -Extra @{
                    module       = 'mission_drift'
                    max_anchors  = $mdMaxAnch
                    total        = $mdAnchors.total
                    path_anchors = $mdAnchors.paths.Count
                    word_anchors = $mdAnchors.words.Count
                } | Out-Null
            }

            # $mdMigrated is in this condition so that a rebuild is always
            # WRITTEN. Without it a session whose transcript had not grown would
            # rebuild its anchors in memory, throw them away at exit and leave
            # the pre-redaction file standing on disk to be rebuilt again next
            # turn - the old anchors would never actually be overwritten.
            #
            # What is persisted here is not redacted at this line and does not
            # need to be: every anchor in the set came from a prompt that went
            # through Get-LwgRedacted above, or from a state file this code
            # wrote after doing so. Re-running the redactor over lowercased
            # context-free tokens would catch nothing it did not already catch
            # and would read as a second line of defence that is not one.
            if ($mdMigrated -or $slice.offset -ne $mdOffset -or $mdPrompts -gt 0 -or $mdIncomplete -ne ($state['md_incomplete'] -eq $true)) {
                $state['md_offset']     = $slice.offset
                $state['md_incomplete'] = $mdIncomplete
                $state['md_paths']      = @($mdAnchors.paths)
                $state['md_words']      = @($mdAnchors.words)
                $state['md_redact']     = $mdRedactMark
                $stateDirty = $true
            }

            # --- assess ------------------------------------------------------
            # Skipped outright when the edit set has not grown since the last
            # assessment. The verdict depends on exactly two things, and neither
            # can have moved against us: the edit set is deduped and therefore
            # monotonic, so an unchanged count is an unchanged set; and anchors
            # only ever ACCUMULATE, so a new prompt can turn a warning into
            # silence but never silence into a warning. Re-deciding an unchanged
            # question at every turn end is the work this skips.
            $considered = @(@($srcPaths) + @($docPaths))
            $mdAssessed = -1
            if ($null -ne $state['md_assessed']) { try { $mdAssessed = [int]$state['md_assessed'] } catch { } }

            if (-not $mdIncomplete -and $mdAnchors.paths.Count -gt 0 -and
                $considered.Count -ge $mdMinFiles -and $considered.Count -ne $mdAssessed) {

                $state['md_assessed'] = $considered.Count
                $stateDirty = $true

                # One cheap pass to find out whether ANY file is accounted for,
                # which is all the trigger needs - it fires only when none is.
                # The under-the-workspace test comes first because it is plain
                # string work, where the anchor test decomposes the path; and the
                # loop stops at the first hit rather than scoring all of them.
                # On a session doing what it was asked, that is one comparison
                # instead of two per edited file.
                $anyAccounted = $false
                foreach ($p in $considered) {
                    if ($mdOutside -and (Test-LwgPathUnder -Path $p -Root $mdRoot)) { $anyAccounted = $true; break }
                    if (Test-LwgMissionAccounted -Path $p -Anchors $mdAnchors -Scope $mdScope) { $anyAccounted = $true; break }
                }
                $unaccounted = $(if ($anyAccounted) { @() } else { $considered })
                $accounted   = $(if ($anyAccounted) { $considered.Count } else { 0 })

                if ($unaccounted.Count -ge $mdMinFiles) {
                    # Bounded for the same reason docs_coupling's sample is:
                    # Split-Path -Leaf is not a length bound, and these leaves
                    # reach both the MissionDrift record and the systemMessage.
                    $leaves = @($unaccounted |
                                ForEach-Object { Get-LwgRedacted -Text (Split-Path $_ -Leaf) -MaxLength 160 } |
                                Sort-Object -Unique)

                    # --- THE SIGNATURE IS THE VERDICT, NOT THE FILE LIST ------
                    # IT USED TO BE `($leaves -join '|')`, WHICH IS THE COUNTED
                    # THING ITSELF. The edit set is a deduped union of the whole
                    # session's edits and therefore only grows, so one more
                    # unaccounted file produced a different string and re-fired
                    # the same warning with a slightly longer list. Four
                    # warnings in five turns is the ordinary shape of a session
                    # working on more than three files outside the workspace
                    # root, and docs/modules.md offered "the realistic worst
                    # case is one wrong warning per session" as the other side
                    # of the decision to ship this module ON BY DEFAULT. The
                    # narrow claim - "once per distinct set of unaccounted
                    # files" - was true; the bound drawn from it was not.
                    #
                    # WHAT IS REPORTED IS ONE CONDITION: none of this session's
                    # edits is accounted for. That condition does not change
                    # when a fourth file joins it, so neither does the
                    # signature. The list in the message is a SAMPLE of the
                    # condition and has stopped being the trigger for it.
                    #
                    # AND ONE WARNING PER SESSION IS NOW A PROPERTY RATHER THAN
                    # AN ESTIMATE, which is why the signature needs no re-arm.
                    # $anyAccounted is monotone: $considered only grows, anchors
                    # only accumulate, and Test-LwgPathUnder's answer for a
                    # given path never changes - so a file accounted for on one
                    # turn is accounted for on every later turn, and the block
                    # below is unreachable for the rest of the session once any
                    # file is. The bound holds for a FIXED configuration and
                    # workspace root: editing require_outside_root mid-session,
                    # or a cwd that moves the git root, are outside it, and
                    # neither is claimed.
                    #
                    # git_hygiene above builds its signature the same way, from
                    # condition ids with counts excluded. docs_coupling does
                    # NOT - `$srcPaths.Count -gt $warnedAt` re-warns on each
                    # additional source file - so docs/modules.md's "like every
                    # other advisory here" is still wrong about that one, and
                    # this change does not close it.
                    $sig = 'none-accounted'
                    if (([string]$state['md_sig']) -ne $sig) {
                        $state['md_sig'] = $sig
                        $stateDirty = $true

                        $sample  = @($leaves | Select-Object -First 3)
                        # The four anchors the advisory quotes back at the
                        # operator. They are already redacted - they were
                        # redacted on the way IN, which is the only place it can
                        # be done properly - so this pass is a BOUND rather than
                        # a second defence, and is described as one. A path
                        # anchor is one segment of something the operator pasted
                        # and nothing caps how long that is; four of them
                        # unbounded can push a 600-character absolute path into
                        # a turn-end message that has to stay readable.
                        $named   = Get-LwgRedacted -Text ((@(@($mdAnchors.paths) | Sort-Object | Select-Object -First 4)) -join ', ') -MaxLength 160
                        Write-LwgEvent -Event 'MissionDrift' -Payload $payload -Extra @{
                            module        = 'mission_drift'
                            unaccounted   = $unaccounted.Count
                            accounted     = $accounted
                            considered    = $considered.Count
                            path_anchors  = $mdAnchors.paths.Count
                            word_anchors  = $mdAnchors.words.Count
                            prompts_seen  = $mdPrompts
                            workspace     = $mdRoot
                            sample        = $sample
                        } | Out-Null

                        $more = $(if ($unaccounted.Count -gt 3) { " (+$($unaccounted.Count - 3) more)" } else { '' })
                        # The "outside the workspace" clause is only TRUE in the
                        # default mode, where being outside is part of the
                        # trigger. With require_outside_root:false the files may
                        # be in the workspace, and claiming otherwise would be
                        # the advisory stating something it did not check.
                        $where = $(if ($mdOutside) { " are outside $mdRoot and" } else { '' })
                        Add-Advisory ("LW-WATCHTOWER mission: all $($unaccounted.Count) file(s) changed this session - $($sample -join ', ')$more -$where match nothing named in any prompt this session (you named: $named). If the work was redirected, name the new area in a prompt and this goes quiet; otherwise check it is still serving the task.")
                    }
                }
            }
        } catch {
            try { Write-LwgEvent -Event 'AdvisoryError' -Payload $payload -Extra @{
                module = 'mission_drift'; error = $_.Exception.Message } | Out-Null } catch { }
        }
    }

    # =====================================================================
    # trip ledger auto-close - REMOVED 30 JULY 2026
    # =====================================================================
    # Invoke-LwgTripSweep ran here, once per turn end, reading
    # trips-<sessionkey>.json and closing any trip it could close on a fact this
    # process had verified. It survived the gates by a few hours on the argument
    # that ledgers written before the removal still held OPEN trips and still
    # needed a route out. Those ledgers were then backed up and removed by an
    # explicit owner decision, and lib/trips.ps1 went with them, so there is no
    # ledger to sweep and no Invoke-LwgTripSweep to call.
    #
    # Two properties are worth restoring along with it, and are recorded here
    # because the code that carried them is deleted:
    #
    #   * it belongs in THIS script, not a hook of its own. It needs to run once
    #     per turn end and needs no new data, so its own hook would buy nothing
    #     and cost a whole PowerShell process (~285 ms measured) every turn. It
    #     sat BEFORE the git_hygiene collection point so it overlapped the
    #     `git status` child launched at the top rather than adding to it.
    #   * every close rested on a verified fact - an unchanged
    #     exists/mtime/length signature, a rule that denied because the path
    #     could not be resolved, a target proven to be under a temp root. There
    #     was deliberately NO "and it has been a while" branch. A guardrail that
    #     forgets on a timer is the false green the ledger existed to replace.
    #
    # It also raised the one advisory worth saying at turn end: a hard refusal
    # that was worked around anyway by another route, which is the single trip
    # state that never clears itself.

    # =====================================================================
    # git_hygiene  (ADVISORY)
    # =====================================================================
    # DATA SOURCE: git itself. This is the ONE module in the plugin allowed to
    # spawn a subprocess, and the reasons it is tolerable here are worth stating
    # because they are also the constraints:
    #
    #   * it runs on Stop only - never per render, never on PreToolUse, so it
    #     can never delay or hang a tool call;
    #   * it does nothing at all outside a git repo, and the check for that is a
    #     Test-Path walk in Get-LwgRepoInfo, not a subprocess;
    #   * the common case is ONE `git status`. The second git call only happens
    #     on a branch with no upstream, and the single network call (gh) only
    #     when there is unpushed work on a non-default branch, once per branch
    #     head per session;
    #   * every child gets a hard timeout and the child itself is killed on
    #     expiry - see Complete-LwgProcess for what that does NOT cover: on
    #     .NET Framework 4.x there is no kill-the-tree overload, so a helper the
    #     child spawned survives it. Turn end is still never blocked.
    #
    # WHAT A FAILED QUERY MEANS. If git does not answer - not installed, timed
    # out, exited nonzero - this module says the tree state is UNKNOWN and says
    # so out loud. It does NOT fall through to silence, because silence from this
    # module reads as "your tree is clean". That confusion is the exact defect
    # fixed three times over in a private sibling project's watchdogs.
    #
    #   Warns on: uncommitted changes, detached HEAD, local commits directly on
    #   the default branch, unpushed commits, and an open PR whose branch has
    #   moved since the last push.
    if ($onGit) {
        try {
            $info = $gitInfo

            # Not a repo: exit silently, having spawned nothing.
            if ($null -ne $info -and $null -ne $info.root) {
                $ghMs    = [int](Get-LwgModuleOption -Config $cfg -Module 'git_hygiene' -Key 'gh_timeout_ms' -Default 2500)
                $useGh   = Get-LwgModuleFlag   -Config $cfg -Module 'git_hygiene' -Key 'use_gh'       -Default $true
                $defList = @(Get-LwgModuleOption -Config $cfg -Module 'git_hygiene' -Key 'default_branches' -Default @('main', 'master', 'trunk'))

                $notes = @()   # the sentence fragments the user will read
                $conds = @()   # condition ids - the dedupe signature, counts excluded
                # The subset of $notes belonging to conditions that describe the
                # OBSERVATION rather than the tree. See the dedupe at the bottom
                # of this block for why they are tracked separately.
                $obsNotes = @()

                # --- one call answers four questions --------------------------
                # porcelain=v2 --branch yields branch.oid / branch.head /
                # branch.upstream / branch.ab plus one line per changed path, so
                # dirty, detached, ahead and behind all come out of a single
                # process rather than four.
                #
                # COLLECTED here, but STARTED at the top of this script, so it
                # ran alongside the four in-process modules. Its timeout is
                # measured from the launch, so a git that hangs is still killed
                # $gitMs after it started, not $gitMs after this line.
                # A launch that failed leaves $gitStatus $null, and
                # Complete-LwgProcess turns that into state 'error' - which the
                # branch below reports as UNKNOWN, never as a clean tree.
                $st = Complete-LwgProcess -Handle $gitStatus -TimeoutMs $gitMs

                if (-not $st.ok) {
                    $conds += 'query-failed'
                    $why = switch ($st.state) {
                        'timeout' { "git status did not return within $gitMs ms" }
                        'missing' { 'git is not on PATH' }
                        'nonzero' { "git status exited $($st.code)" }
                        default   { "git status could not be run ($($st.state))" }
                    }
                    $stNote = "working tree state is UNKNOWN - $why. Do not read this as a clean tree; check it yourself before reporting the work as landed"
                    $notes    += $stNote
                    $obsNotes += $stNote
                    Write-LwgEvent -Event 'GitHygieneUnavailable' -Payload $payload -Extra @{
                        module = 'git_hygiene'; probe = 'status'; state = $st.state
                        code   = $st.code; ms = $st.ms; error = (Get-LwgRedacted -Text ([string]$st.err) -MaxLength 160)
                    } | Out-Null
                } else {
                    $branch = ''; $upstream = ''; $oid = ''
                    $ahead  = 0;  $behind   = 0
                    $dirty  = 0;  $untracked = 0

                    foreach ($raw in $st.out.Split([char]10)) {
                        $l = $raw.TrimEnd([char]13)
                        if ($l.Length -eq 0) { continue }
                        if ($l[0] -eq '#') {
                            if     ($l -match '^# branch\.oid (.+)$')      { $oid      = $Matches[1].Trim() }
                            elseif ($l -match '^# branch\.head (.+)$')     { $branch   = $Matches[1].Trim() }
                            elseif ($l -match '^# branch\.upstream (.+)$') { $upstream = $Matches[1].Trim() }
                            elseif ($l -match '^# branch\.ab \+(\d+) -(\d+)$') { $ahead = [int]$Matches[1]; $behind = [int]$Matches[2] }
                            continue
                        }
                        # '?' is untracked, '!' is ignored (not requested here),
                        # everything else - 1, 2, u - is a tracked change.
                        if     ($l[0] -eq '?') { $untracked++ }
                        elseif ($l[0] -ne '!') { $dirty++ }
                    }

                    $detached = ($branch -eq '(detached)')
                    $changed  = $dirty + $untracked

                    # --- unpushed work -------------------------------------
                    # With an upstream, branch.ab already answered it for free.
                    # Without one, ask which commits are on no remote at all -
                    # which also covers a detached HEAD. Skipped entirely when
                    # the repo has no remote, where "unpushed" is meaningless
                    # and `--not --remotes` would count every commit ever made.
                    $unpushed = 0
                    $unpushedKnown = $false
                    $pushTarget = $upstream
                    if ($upstream) {
                        $unpushed = $ahead
                        $unpushedKnown = $true
                    } elseif ($info.remote_count -gt 0) {
                        $pushTarget = 'any remote'
                        $rl = Invoke-LwgGit -GitArgs @('rev-list', '--count', 'HEAD', '--not', '--remotes') -WorkDir $info.root -TimeoutMs $gitMs
                        if ($rl.ok -and $rl.out.Trim() -match '^\d+$') {
                            $unpushed = [int]$rl.out.Trim()
                            $unpushedKnown = $true
                        } else {
                            $conds += 'query-failed'
                            $rlNote = "unpushed-commit count is UNKNOWN - git rev-list $($rl.state)"
                            $notes    += $rlNote
                            $obsNotes += $rlNote
                            Write-LwgEvent -Event 'GitHygieneUnavailable' -Payload $payload -Extra @{
                                module = 'git_hygiene'; probe = 'rev-list'; state = $rl.state
                                code   = $rl.code; ms = $rl.ms; error = (Get-LwgRedacted -Text ([string]$rl.err) -MaxLength 160)
                            } | Out-Null
                        }
                    }

                    # --- which branch is the default? -----------------------
                    # Read refs/remotes/origin/HEAD directly rather than paying
                    # for another process. That ref only exists if the repo was
                    # cloned or `git remote set-head` was run, so the configured
                    # name list is a real fallback, not a formality.
                    $defBranch = ''
                    try {
                        $hp = Join-Path $info.common 'refs\remotes\origin\HEAD'
                        if (Test-Path -LiteralPath $hp -PathType Leaf) {
                            $t = (Get-Content -LiteralPath $hp -Raw -ErrorAction Stop).Trim()
                            if ($t -match 'refs/remotes/[^/]+/(.+)$') { $defBranch = $Matches[1].Trim() }
                        }
                    } catch { }
                    $onDefault = $false
                    if ($defBranch) {
                        $onDefault = ($branch -eq $defBranch)
                    } elseif (-not $detached -and $branch -and ($defList -contains $branch)) {
                        $onDefault = $true
                        $defBranch = $branch
                    }

                    # --- conditions -----------------------------------------
                    if ($detached) {
                        $conds += 'detached'
                        $short = if ($oid.Length -ge 8) { $oid.Substring(0, 8) } else { $oid }
                        $notes += "HEAD is DETACHED at $short - commits made here belong to no branch and become unreachable the moment anything else is checked out"
                    }

                    if ($changed -gt 0) {
                        $conds += 'dirty'
                        $where = if ($detached) { 'a detached HEAD' } else { "'$branch'" }
                        $bits  = @()
                        if ($dirty -gt 0)     { $bits += "$dirty tracked" }
                        if ($untracked -gt 0) { $bits += "$untracked untracked" }
                        $notes += "$changed uncommitted change(s) on $where ($($bits -join ', ')) at turn end"
                    }

                    if ($unpushedKnown -and $unpushed -gt 0) {
                        $conds += 'unpushed'
                        $notes += "$unpushed commit(s) not pushed to $pushTarget - local and remote are out of sync"

                        if ($onDefault) {
                            $conds += 'default-branch'
                            $notes += "and they are directly on the default branch '$defBranch', so nothing reviewed them - branch first and land through a PR"
                        }

                        # --- open PR, the one network call ------------------
                        # Only reachable when there IS unpushed work on a
                        # non-default branch, which is precisely the situation
                        # where "the PR branch has moved since the last push" can
                        # be true.
                        #
                        # Asked at most once per branch head per session and the
                        # ANSWER is cached, not just the fact that it was asked -
                        # caching only the latter would drop the PR sentence out
                        # of the signature on the next turn and re-fire the whole
                        # advisory without it.
                        # The slug is resolved HERE rather than at the top of the
                        # script: this is the only place that genuinely needs it,
                        # and Get-LwgRepoInfo has already been called for this
                        # path, so the walk is memoised and costs ~2 ms.
                        $ghRepo = Get-CachedRepo
                        if ($useGh -and -not $onDefault -and -not $detached -and $ghRepo) {
                            $ghKey = "$branch@$oid"
                            if (([string]$state['git_gh_key']) -ne $ghKey) {
                                $state['git_gh_key']  = $ghKey
                                $state['git_gh_cond'] = ''
                                $state['git_gh_note'] = ''
                                $stateDirty = $true

                                # --- THE TWO NON-LITERAL ARGUMENTS ------------
                                # $ghRepo is payload-derived (cwd -> .git/config
                                # -> a regex whose repo half is `.+?`) and
                                # $branch is repository-controlled. They are the
                                # two values that made the hand-rolled quoter's
                                # "every argument is a literal" comment false.
                                # Checked here rather than trusted to the
                                # quoter, because the quoter's safety rests on
                                # the target being a .exe - and a `gh` that
                                # resolves to a .cmd shim is re-parsed by
                                # cmd.exe whatever UseShellExecute says.
                                #
                                # WHAT IT COSTS: a branch name outside
                                # [A-Za-z0-9_.+/-] - non-ASCII is legal in git -
                                # skips the PR probe. That is a real
                                # degradation, and it is the LOUD one: it lands
                                # on the same gh-unavailable path a missing gh
                                # takes, so the operator is told the check did
                                # not run rather than left to assume it ran and
                                # found nothing.
                                $ghSafe  = '^[A-Za-z0-9_.+/-]+$'
                                $ghClean = ($ghRepo -match $ghSafe) -and ($branch -match $ghSafe) -and
                                           (-not $ghRepo.StartsWith('-')) -and (-not $branch.StartsWith('-'))

                                $gh = $null
                                if ($ghClean) {
                                    $gh = Invoke-LwgProcess -File 'gh' -WorkDir $info.root -TimeoutMs $ghMs -ProcArgs @(
                                        'pr', 'list', '--repo', $ghRepo, '--head', $branch, '--state', 'open',
                                        '--limit', '1', '--json', 'number,headRefOid,url')
                                } else {
                                    $gh = @{ ok = $false; state = 'unsafe-argument'; code = -1; ms = 0; err = '' }
                                }

                                if ($gh.ok) {
                                    $prs = @()
                                    try { $prs = @($gh.out | ConvertFrom-Json -ErrorAction Stop) } catch { $prs = @() }
                                    if ($prs.Count -gt 0 -and $null -ne $prs[0].number) {
                                        $head = [string]$prs[0].headRefOid
                                        if ($head -ne $oid) {
                                            $hs = if ($head.Length -ge 8) { $head.Substring(0, 8) } else { $head }
                                            $state['git_gh_cond'] = 'pr-stale'
                                            $state['git_gh_note'] = "PR #$($prs[0].number) is open and still points at $hs, which is behind your local branch - push before treating it as reviewed"
                                        }
                                    }
                                } else {
                                    # Skipped LOUDLY: the user is told the PR half
                                    # of this advisory did not run, rather than
                                    # being left to assume it ran and found
                                    # nothing. A hung or missing gh costs the
                                    # timeout once, not once per turn.
                                    $state['git_gh_cond'] = 'gh-unavailable'
                                    $state['git_gh_note'] = "open-PR state NOT checked (gh $($gh.state))"
                                    Write-LwgEvent -Event 'GitHygieneUnavailable' -Payload $payload -Extra @{
                                        module = 'git_hygiene'; probe = 'gh-pr-list'; state = $gh.state
                                        code   = $gh.code; ms = $gh.ms; error = (Get-LwgRedacted -Text ([string]$gh.err) -MaxLength 160)
                                    } | Out-Null
                                }
                            }
                            if (-not [string]::IsNullOrWhiteSpace([string]$state['git_gh_cond'])) {
                                $conds += [string]$state['git_gh_cond']
                                $notes += [string]$state['git_gh_note']
                                if ([string]$state['git_gh_cond'] -eq 'gh-unavailable') {
                                    $obsNotes += [string]$state['git_gh_note']
                                }
                            }
                        }
                    }

                    if ($conds.Count -gt 0) {
                        Write-LwgEvent -Event 'GitHygiene' -Payload $payload -Extra @{
                            module    = 'git_hygiene'
                            conditions = ($conds -join ',')
                            branch    = $branch
                            default_branch = $defBranch
                            detached  = $detached
                            tracked_changes   = $dirty
                            untracked_changes = $untracked
                            unpushed  = $(if ($unpushedKnown) { $unpushed } else { $null })
                            behind    = $behind
                            upstream  = $upstream
                            probe_ms  = $st.ms        # how long git itself ran
                            probe_wait_ms = $st.wait_ms   # how much of that landed on turn end
                        } | Out-Null
                    }
                }

                # --- dedupe -------------------------------------------------
                # The signature is the SET of conditions, never their counts, so
                # editing one more file does not re-fire the same warning at the
                # next turn end. A clean turn stores an empty signature, which is
                # what lets the same condition warn again if it comes back.
                #
                # TWO KINDS OF CONDITION, AND ONLY ONE OF THEM DEDUPES. The
                # reasoning above is right about `dirty`, `unpushed`, `detached`,
                # `default-branch` and `pr-stale`: those are states of the TREE,
                # their counts move while the condition holds, and repeating them
                # every turn is how an advisory channel becomes noise. It does
                # not transfer to `query-failed` and `gh-unavailable`, which are
                # states of the OBSERVATION. Those went into the same signature,
                # so a git that never answers - not on PATH for the hook process,
                # hanging, or exiting nonzero on a corrupt index or a
                # safe.directory refusal - produced an identical signature at
                # every turn end and was announced exactly ONCE, on the first.
                # From turn two on, that session was indistinguishable to the
                # operator from a clean tree - and this module's documented
                # reading of its own silence is "git said there is nothing
                # wrong". Conflating those two is the defect the header of this
                # block names as fixed three times over elsewhere, and the
                # dedupe was quietly re-introducing it.
                #
                # SO THE SIGNATURE IS BUILT FROM THE TREE CONDITIONS ONLY, and
                # an unavailability note is emitted on every turn end where it
                # holds. An observation that did not happen is worth saying
                # every time it does not happen.
                #
                # WHAT IT COSTS, stated rather than left to be discovered: one
                # extra sentence per turn end for as long as git or gh cannot be
                # reached. That is deliberately the machine that most needs it,
                # and it stops the moment the query starts answering. The
                # evidence log was already recording this at every turn end
                # (GitHygieneUnavailable, above, which sits outside the dedupe);
                # what was missing was the operator-visible half.
                #
                # NOTE THE FAQ. docs/faq.md states the general rule - "an
                # advisory fires on a change, not on a state" - in terms that no
                # longer cover these two conditions. That page is outside this
                # change and still needs the carve-out.
                $obsIds    = @('query-failed', 'gh-unavailable')
                $treeConds = @($conds | Where-Object { $obsIds -notcontains $_ })
                $sig  = ($treeConds -join '+')
                $prev = [string]$state['git_sig']
                if ($sig -ne $prev) {
                    $state['git_sig'] = $sig
                    $stateDirty = $true
                    if ($conds.Count -gt 0) {
                        Add-Advisory ('LW-WATCHTOWER git: ' + ($notes -join '; ') + '.')
                    }
                } elseif ($obsNotes.Count -gt 0) {
                    # The tree conditions have already been said this session and
                    # have not changed; the unavailability has not been said this
                    # turn. Only the latter is repeated, so the operator is not
                    # re-told about the same uncommitted files alongside it.
                    Add-Advisory ('LW-WATCHTOWER git: ' + ($obsNotes -join '; ') + '.')
                }
            }
        } catch {
            try { Write-LwgEvent -Event 'AdvisoryError' -Payload $payload -Extra @{
                module = 'git_hygiene'; error = $_.Exception.Message } | Out-Null } catch { }
        }
    }

    if ($stateDirty) { Write-LwgStateJson -FileName $stateFile -Data $state | Out-Null }

    if ($messages.Count -gt 0) { Write-LwgAdvisory -Messages $messages | Out-Null }

} catch {
    # Anything that escaped the per-module handlers above - a failed dot-source,
    # an unreadable state dir. Log it if we can and get out of the way.
    try { Write-LwgEvent -Event 'AdvisoryError' -Payload $payload -Extra @{
        module = 'stop_advisories'; error = $_.Exception.Message } | Out-Null } catch { }
}

exit 0
