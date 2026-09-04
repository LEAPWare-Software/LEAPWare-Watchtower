#requires -version 5
<#
  LW-WATCHTOWER advisory handler - context_pressure, docs_coupling and
  git_hygiene, on the Stop event.

  Invoked from hooks/hooks.json in exec form:
      command: "powershell"
      args:    ["-NoProfile","-ExecutionPolicy","Bypass","-File",
                "${CLAUDE_PLUGIN_ROOT}/lib/stop_advisories.ps1"]

  WHY ONE SCRIPT FOR THREE MODULES
  Stop fires at the end of every single turn, and each registered hook is a
  separate PowerShell process - roughly 285 ms of interpreter startup that buys
  nothing. Three hooks would put most of a second on every turn end. So the
  three modules share one process and each gates itself independently: switching
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

        @{ p; so; se; sw; state; ok; code; out; err; ms; wait_ms; child_pid; kill }

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

    # child_pid and kill are what make an expired child attributable in the
    # evidence log - #98 item 3 - and they are NOT the same shape as each other.
    # child_pid is filled in below on every path where the child started, and
    # stays -1 where it did not; it is captured AT LAUNCH rather than read back
    # later because Complete-LwgProcess disposes the Process object in its
    # finally and .Id throws after that. kill is written only by the timeout
    # path, and names the route Stop-LwgProcessTree took.
    $h = @{ p = $null; so = $null; se = $null; sw = [System.Diagnostics.Stopwatch]::StartNew()
            state = 'error'; ok = $false; code = -1; out = ''; err = ''; ms = 0; wait_ms = 0
            child_pid = -1; kill = '' }
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
        try { $h.child_pid = [int]$h.p.Id } catch { $h.child_pid = -1 }

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

function Stop-LwgProcessTree {
    <#
      Terminate $Proc AND EVERYTHING BENEATH IT, and say by which route.
      Returns @{ method = <string>; pid = <int> }; method is one of

        taskkill            taskkill /T /F ran and reported success
        taskkill-exit-<n>   it ran and REFUSED - access denied, or a process in
                            the tree it could not terminate. The distinction is
                            the whole value of this field: a taskkill that merely
                            STARTED proves nothing, and a field that said
                            'taskkill' for a refusal would report the tree dead
                            when it is not.
        taskkill-timeout    it was started and had to be killed itself
        taskkill-failed     it could not be started at all (not on PATH)
        kill-only           the child had already exited, or has no usable id

      WHY THIS EXISTS. Process.Kill() with no argument terminates the direct
      child and nothing else. .NET Framework 4.x - the runtime Windows
      PowerShell 5.1 runs on, which is the only supported host - has no
      Kill(bool entireProcessTree); that overload arrived in .NET Core 3.0. So
      the timeout path used to leave a credential helper, a pager or any other
      helper the child had spawned running, holding the inherited write ends of
      the redirected pipes, after the hook had exited.

      THAT IS NO LONGER AN INFERENCE. #98 argued it from what git and gh are
      known to spawn, and the counter-argument on that issue - that no orphan had
      ever been observed from this plugin - was true when it was written. It is
      not true now: tests\stop_behaviour.ps1 case B26 plants a real
      grandchild under a real child, runs the real timeout path, and reads the
      process table afterwards. It found the grandchild alive. The decision that
      rested on "unobserved" is therefore reopened by evidence rather than by
      argument, and this is the answer.

      WHY taskkill AND NOT THE OTHER TWO OPTIONS #98 LISTS.
        * A Job Object with JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE is the clean
          mechanism and is unavailable at an acceptable price: it needs
          Add-Type, which compiles C# on every single hook invocation - on the
          FAST path, not this one - to buy something only the timeout path uses.
        * A Win32_Process ParentProcessId walk is one WMI query, and it has to
          be written correctly: descendants must be enumerated BEFORE the root
          dies, recursively, and killed leaf-first, or PID reuse turns it into a
          way of killing unrelated processes. taskkill /T does exactly that,
          correctly, in a binary that ships with the OS.
      The cost is one process spawn on a path where a child has ALREADY burned
      its whole timeout, so it is charged where the time was already lost.

      ORDERING IS THE WHOLE THING, and it is why taskkill runs before the
      fallback Kill() rather than after. Windows never rewrites a child's
      ParentProcessId when its parent dies, so /T against an already-dead root
      walks nothing at all. The root must still be alive when taskkill reads the
      table.

      THE RESIDUAL, NAMED. Between HasExited returning false and taskkill
      reading the process table, the child can exit and Windows can in principle
      reissue its pid. The window is microseconds and the check narrows it
      rather than closing it; there is no API on this runtime that closes it.
      The fallback Kill() below carries the same window and always did.

      OUTPUT IS REDIRECTED AND DELIBERATELY NEVER READ. taskkill prints a line
      per process it terminates, and this runs inside a Stop hook whose stdout is
      the systemMessage envelope - an unredirected SUCCESS: line would land in
      it. The async reads are started and dropped so the pipe cannot fill and
      stall the WaitForExit below; nothing here wants the text.
    #>
    param($Proc)

    $out = @{ method = 'kill-only'; pid = -1 }
    if ($null -eq $Proc) { return $out }
    try { $out.pid = [int]$Proc.Id } catch { $out.pid = -1 }

    try {
        if ($out.pid -gt 0 -and -not $Proc.HasExited) {
            $tk = New-Object System.Diagnostics.ProcessStartInfo
            $tk.FileName               = 'taskkill'
            # A literal built from an integer. Nothing from any payload reaches
            # this string, which is why it needs no quoting rule of its own.
            $tk.Arguments              = ('/PID {0} /T /F' -f $out.pid)
            $tk.UseShellExecute        = $false
            $tk.CreateNoWindow         = $true
            $tk.RedirectStandardOutput = $true
            $tk.RedirectStandardError  = $true

            $k = [System.Diagnostics.Process]::Start($tk)
            if ($null -eq $k) {
                $out.method = 'taskkill-failed'
            } else {
                $out.method = 'taskkill'
                try { $k.StandardOutput.ReadToEndAsync() | Out-Null } catch { }
                try { $k.StandardError.ReadToEndAsync()  | Out-Null } catch { }
                # NOT routed through Complete-LwgProcess, on purpose: that
                # function's timeout path calls this one, so a taskkill that
                # hung would tree-kill taskkill, recursively.
                try {
                    if (-not $k.WaitForExit(1000)) {
                        $out.method = 'taskkill-timeout'
                        try { $k.Kill() } catch { }
                    } else {
                        # STARTED IS NOT SUCCEEDED. taskkill exits nonzero when
                        # it is denied access or cannot terminate a process in
                        # the tree, and reporting that as 'taskkill' would be
                        # this field claiming the tree died when it did not.
                        $kc = -1
                        try { $kc = [int]$k.ExitCode } catch { $kc = -1 }
                        if ($kc -ne 0) { $out.method = ('taskkill-exit-{0}' -f $kc) }
                    }
                } catch { }
                try { $k.Dispose() } catch { }
            }
        }
    } catch {
        # taskkill not on PATH, or Start threw. The fallback below is then the
        # whole of the kill, and the caller is told which it got.
        $out.method = 'taskkill-failed'
    }

    # The belt. Whatever taskkill did or did not manage, the DIRECT child must
    # die - that half of the guarantee was never in doubt and must not become
    # conditional on a binary being present.
    try { if (-not $Proc.HasExited) { $Proc.Kill() } } catch { }

    return $out
}

function Complete-LwgProcess {
    <#
      Collect a handle from Start-LwgProcess, killing the child AND EVERYTHING IT
      SPAWNED if it has not finished within $TimeoutMs OF ITS OWN START. Fills in and returns the same
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
    if ($null -eq $r) { return @{ ok = $false; state = 'error'; code = -1; out = ''; err = ''; ms = 0; wait_ms = 0; child_pid = -1; kill = '' } }
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
            # KILLS THE TREE, NOT JUST THE CHILD - #98. Process.Kill() on its own
            # terminates the direct child only on this runtime, and a `git` or
            # `gh` that had spawned a credential helper left that helper running
            # with the inherited write ends of the redirected pipes. That was
            # measured, not inferred: tests\stop_behaviour.ps1 case B26
            # planted a grandchild and found it alive after this line. See
            # Stop-LwgProcessTree for the mechanism, the ordering rule that makes
            # it work, and the pid-reuse residual it does not close.
            #
            # WHAT ALREADY HELD AND STILL DOES: turn end is not blocked. This
            # returns as soon as the kill is done and never awaits the read tasks
            # on this path. Stop-LwgProcessTree's own wait is bounded at 1000 ms
            # and it kills its taskkill rather than waiting longer.
            #
            # WHAT THE FIX DOES NOT REACH: the four documented sites #98 lists
            # now disagree with each other in the opposite direction.
            # docs/architecture.md and config.json say "killed on expiry", which
            # this makes true again; docs/modules.md was corrected on 2026-09-02
            # to say a helper the child spawned is NOT killed, which this makes
            # false. Neither page is edited from here.
            $kt = Stop-LwgProcessTree -Proc $r.p
            $r.kill = [string]$kt.method
            if ([int]$kt.pid -gt 0) { $r.child_pid = [int]$kt.pid }
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
        timeout   still running when the clock ran out; the child and its
                  descendants are killed (Stop-LwgProcessTree)
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
    $onDocs    = Test-LwgModule -Name 'docs_coupling'     -Config $cfg -Repo $repo
    $onGit     = Test-LwgModule -Name 'git_hygiene'       -Config $cfg -Repo $repo
    # A fourth flag, $onTrips, sat here. It was a Test-Path for this session's
    # trips-<sessionkey>.json rather than a module lookup, because no module owned
    # it any more: the gates that wrote trips went on 30 July 2026 and the sweep
    # below was kept only so ledgers written BEFORE that could still reach a
    # close. The ledger files were removed later the same day and lib/trips.ps1
    # with them, so the Test-Path can no longer be true for anything and the file
    # it decided whether to dot-source no longer exists.
    if (-not ($onContext -or $onDocs -or $onGit)) { exit 0 }

    $sessionId = [string]$payload.session_id
    $sessKey   = Get-LwgSessionKey -SessionId $sessionId
    $stateFile = "advisory-$sessKey.json"
    $state     = Read-LwgStateJson -FileName $stateFile
    $stateDirty = $false

    # =====================================================================
    # git_hygiene, part one - LAUNCH ONLY
    # =====================================================================
    # `git status` is the only subprocess this script starts. It is launched
    # HERE, before the two in-process modules run, and collected after them, so
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
    # The edit list is read and classified ONCE, into three buckets. It used to
    # be read for TWO modules - mission_drift wanted the same buckets - and the
    # shape is kept because the cost argument for reading it once still holds:
    # re-classifying 200 paths is ~35 ms at every turn end.
    $srcPaths   = @()
    $docPaths   = @()
    $otherCount = 0
    $haveEdits  = $false
    if ($onDocs) {
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
            # THE ATTRIBUTION IS THE MODULE THE READ WAS FOR, and it is now
            # exactly one. It used to be a join over two - the read was shared
            # with mission_drift, whose flag could be on while docs_coupling's
            # was off, and naming docs_coupling unconditionally then recorded an
            # error against a module that was not running and nothing against
            # the module that had just silently produced no assessment. With
            # mission_drift removed the guard above is `$onDocs` alone, so
            # docs_coupling is the only module this read can be for and the
            # literal is correct rather than merely usually correct. `module` is
            # the only routing a record in lw-watchtower.jsonl carries, so a
            # wrong value there is a wrong report, not a cosmetic one.
            #
            # `phase = 'read-edits'` still distinguishes this handler from
            # docs_coupling's own below, which is the only thing that separates
            # the two now that the module name no longer does.
            try { Write-LwgEvent -Event 'AdvisoryError' -Payload $payload -Extra @{
                module = 'docs_coupling'; phase = 'read-edits'; error = $_.Exception.Message } | Out-Null } catch { }
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
    #   * every child gets a hard timeout, and on expiry the child AND ANYTHING
    #     IT SPAWNED are killed - Complete-LwgProcess hands the timeout path to
    #     Stop-LwgProcessTree, which runs `taskkill /T /F` against the live child
    #     before terminating it, because .NET Framework 4.x has no kill-the-tree
    #     overload of its own. Turn end is still never blocked; the extra wait is
    #     bounded at 1000 ms and only on the path where the timeout already
    #     expired. The residual it does not close - a pid reissued in the
    #     microseconds after the HasExited check - is named at that function.
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
                # ran alongside the two in-process modules. Its timeout is
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
                    # child_pid and kill are recorded so an expired child is
                    # ATTRIBUTABLE on a real machine - #98 item 3.
                    #
                    # child_pid is the child's OWN pid and is filled in on every
                    # path where the child started at all - a `nonzero` record
                    # carries one too, which is a small bonus rather than the
                    # point. It is -1 only for 'missing' and 'error', where there
                    # was no process to name.
                    #
                    # kill is non-empty ONLY on the timeout path, because it is
                    # the route the tree kill took: 'taskkill' when taskkill ran
                    # and reported success, 'taskkill-exit-<n>' when it ran and
                    # refused (access denied, or a process it could not
                    # terminate), 'taskkill-timeout' when it had to be killed
                    # itself, 'taskkill-failed' when it could not be started, and
                    # 'kill-only' when the child had already gone. Everything
                    # except plain 'taskkill' means the pre-#98 behaviour may
                    # still hold for that child's descendants, and the pid beside
                    # it is what makes that checkable.
                    Write-LwgEvent -Event 'GitHygieneUnavailable' -Payload $payload -Extra @{
                        module = 'git_hygiene'; probe = 'status'; state = $st.state
                        code   = $st.code; ms = $st.ms; error = (Get-LwgRedacted -Text ([string]$st.err) -MaxLength 160)
                        child_pid = $st.child_pid; kill = $st.kill
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
                                child_pid = $rl.child_pid; kill = $rl.kill
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
                                        child_pid = $gh.child_pid; kill = $gh.kill
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
