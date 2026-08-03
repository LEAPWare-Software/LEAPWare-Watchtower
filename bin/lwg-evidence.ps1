#requires -version 5
<#
  LW-WATCHTOWER evidence engine - shared by /lw-watchtower:checklist and /lw-watchtower:sitrep.

      . (Join-Path $PSScriptRoot 'lwg-evidence.ps1')

  Dot-sourced, never run directly. It defines functions and touches nothing.

  WHAT THIS FILE IS FOR. Both reporting commands answer the same question about
  different things: is this state a FACT I checked, or a CLAIM someone made? So
  the rule that decides it lives in one place. An item is DONE only when a probe
  in here returned pass; anything a probe could not answer comes back 'unknown'
  and the caller must render it as unverified rather than as incomplete. There is
  deliberately no code path that turns "I could not look" into "it is not done".

  THAT SENTENCE WAS FALSE FOR `kind: command` UNTIL 31 JULY 2026, and it is
  recorded here rather than quietly fixed, because the sentence had been sitting
  above the defect the whole time. A `command` rule scored ANY unexpected exit
  code as a finding. On the marketplace install route - the one docs/install.md
  recommends to consumers - the plugin directory carries no `.git`, so every
  git-backed rule exited 128 having read nothing, and two rows rendered
  `[ ] NOT STARTED`: to a reader, "the owner's personal address WAS left in
  history" and "the private sibling project's name IS in the tree". Neither had
  been measured. It was found by adversarial UAT against the v0.3.0 tag, on the
  install route the maintainer does not use, and not by anything in tests/.
  Get-LwgProbeUnreachable and the empty-stdout case in the `command` evaluator
  are the fix; tests/evidence_states.ps1 is what stops it coming back.

  WHY THE SUBPROCESS HELPER IS DUPLICATED HERE. lib/stop_advisories.ps1 has one
  already and says, in its own comment, why it must stay there: common.ps1 was
  dot-sourced by both PreToolUse gates, and a gate that can spawn a process is a
  gate that can hang the tool call it is guarding. Both gates went on 30 July
  2026 and delegate_gate replaced them as the only one later the same day, so a
  PreToolUse hook IS registered and the hazard is live rather than historical:
  lib/gate_delegate.ps1 dot-sources common.ps1 on the PreToolUse path and
  common.ps1 still contains no subprocess helper at all. This paragraph asserted
  the opposite - that no such hook was registered any more - until 3 August 2026.
  That was true for the few hours between the two removals and the new gate, and
  a reader deciding whether the quarantine still matters would have taken it as
  "the hazard has lapsed" and merged the helper back into common.ps1, which is
  precisely the outcome the quarantine exists to prevent.
  See bin/lwg-cmdlib.ps1, which carries the same rationale and was kept current.
  Dot-sourcing stop_advisories
  to borrow the helper would additionally RUN a Stop hook. So the shape is copied
  and the quarantine is preserved. Nothing in bin/ is on a hook path: these are
  user-invoked commands, and git/gh calls here cost the operator a second of
  their own time and nothing else.

  Every child is bounded and killed on expiry, and a child that does not answer
  makes its item UNVERIFIED - never done, and never quietly "not started".
#>

# --- output shaping ---------------------------------------------------------

function Format-LwgWrapped {
    <#
      One string as indented lines no wider than $Width, hard-wrapping any single
      token longer than the width (a URL, a long path) rather than letting it
      overhang.

      NEVER truncates. Both commands print evidence and error text, and a report
      that shortens either has softened a finding to fit a column - which is the
      one thing neither command is allowed to do.
    #>
    param([string]$Text, [string]$Indent = '      ', [int]$Width = 96)

    $out = @()
    if ([string]::IsNullOrWhiteSpace($Text)) { return $out }
    $line = ''
    foreach ($w in ($Text -split '\s+')) {
        $word = $w
        while ($word.Length -gt $Width) {
            if ($line.Length -gt 0) { $out += ($Indent + $line); $line = '' }
            $out  += ($Indent + $word.Substring(0, $Width))
            $word  = $word.Substring($Width)
        }
        if ($line.Length -eq 0) { $line = $word; continue }
        if (($line.Length + 1 + $word.Length) -gt $Width) { $out += ($Indent + $line); $line = $word; continue }
        $line = "$line $word"
    }
    if ($line.Length -gt 0) { $out += ($Indent + $line) }
    return $out
}

# --- bounded subprocess -----------------------------------------------------

function Invoke-LwgRptProcess {
    <#
      Run a program, capture its output, give up after $TimeoutMs.

      Returns @{ ok; state; code; out; err; ms } where state is one of:

        ok        started, exited inside the timeout, exit code 0
        nonzero   ran to completion but exited non-zero
        timeout   still running when the clock ran out; killed
        missing   could not be started at all (not on PATH)
        error     anything else

      `ok` is $true for 'ok' and nothing else. Every caller must be able to tell
      "the tool answered no" apart from "the tool did not answer", because
      collapsing those two is how a report claims a state it never observed.

      A hashtable, so the result survives the function boundary un-enumerated.

      The output streams are drained ASYNCHRONOUSLY. ReadToEnd() then
      WaitForExit($ms) deadlocks on a child that fills a pipe buffer, and
      WaitForExit($ms) alone deadlocks on a child that never exits - neither of
      them bounds anything.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$File,
        [string[]]$ProcArgs = @(),
        [string]$WorkDir,
        [int]$TimeoutMs = 6000
    )

    $r = @{ ok = $false; state = 'error'; code = -1; out = ''; err = ''; ms = 0 }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $p  = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $File
        # .NET Framework 4.x has no ProcessStartInfo.ArgumentList, so the
        # argument string is built by hand. Every argument passed by either
        # command comes from checklist.json or from a literal in this repo -
        # never from anything a session typed.
        $psi.Arguments = (@($ProcArgs | ForEach-Object {
            if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { [string]$_ }
        }) -join ' ')
        $psi.UseShellExecute        = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.RedirectStandardInput  = $true
        $psi.CreateNoWindow         = $true
        if (-not [string]::IsNullOrWhiteSpace($WorkDir)) { $psi.WorkingDirectory = $WorkDir }
        # Nothing here may ever wait on a human. A credential helper that decides
        # to prompt would otherwise sit there until the operator gives up on the
        # command entirely.
        $psi.EnvironmentVariables['GIT_TERMINAL_PROMPT']   = '0'
        $psi.EnvironmentVariables['GIT_OPTIONAL_LOCKS']    = '0'
        $psi.EnvironmentVariables['GCM_INTERACTIVE']       = 'never'
        $psi.EnvironmentVariables['GH_PROMPT_DISABLED']    = '1'
        $psi.EnvironmentVariables['GH_NO_UPDATE_NOTIFIER'] = '1'

        try {
            $p = [System.Diagnostics.Process]::Start($psi)
        } catch {
            $r.state = 'missing'
            $r.err   = $_.Exception.Message
            return $r
        }
        if ($null -eq $p) { $r.state = 'missing'; return $r }

        # Close stdin at once: a child that reads it gets EOF rather than
        # blocking forever on input this process is never going to send.
        try { $p.StandardInput.Close() } catch { }

        $so = $p.StandardOutput.ReadToEndAsync()
        $se = $p.StandardError.ReadToEndAsync()

        if ($p.WaitForExit($TimeoutMs)) {
            try { if ($so.Wait(1000)) { $r.out = [string]$so.Result } } catch { }
            try { if ($se.Wait(1000)) { $r.err = [string]$se.Result } } catch { }
            $r.code  = $p.ExitCode
            $r.ok    = ($r.code -eq 0)
            $r.state = $(if ($r.ok) { 'ok' } else { 'nonzero' })
        } else {
            $r.state = 'timeout'
            try { $p.Kill() } catch { }
        }
    } catch {
        $r.state = 'error'
        $r.err   = $_.Exception.Message
    } finally {
        $sw.Stop()
        $r.ms = [int]$sw.ElapsedMilliseconds
        if ($null -ne $p) { try { $p.Dispose() } catch { } }
    }
    return $r
}

function Get-LwgRptProcessWhy {
    <#
      One clause explaining why a probe did not answer, in words that name the
      cause rather than the symptom. Used verbatim in the UNVERIFIED detail, so
      the operator can tell a missing tool from a hung one from a real refusal.
    #>
    param($Result, [string]$Tool)

    # 'not on PATH' is about the PROGRAM, so only the first word of a label like
    # 'gh run list' is used - "gh run list is not on PATH" reads as though the
    # subcommand were the missing thing.
    $exe = @($Tool -split '\s+')[0]
    switch ($Result.state) {
        'missing' { return "$exe is not on PATH" }
        'timeout' { return "$Tool did not answer within the timeout and was killed" }
        'nonzero' {
            $e = Get-LwgRedacted -Text ([string]$Result.err) -MaxLength 140
            if ([string]::IsNullOrWhiteSpace($e)) { return "$Tool exited $($Result.code)" }
            return "$Tool exited $($Result.code): $($e.Trim())"
        }
        default   { return "$Tool could not be run ($($Result.state))" }
    }
}

function Get-LwgProbeUnreachable {
    <#
      Why a process that RAN TO COMPLETION should still be read as "the probe
      never got to look". Returns a clause for the UNVERIFIED detail, or '' when
      the exit code really is an answer to the question the rule asked.

      Invoke-LwgRptProcess already separates "the tool did not answer" - missing,
      timeout, error - from "the tool answered no". This is the case it cannot
      see: the tool started, exited, and its exit code means it declined to look
      at all. A nonzero exit is only evidence about the item if the program got
      as far as the thing being asked about.

      WHAT THIS WAS BUILT FOR, because it is a shipped defect and not a
      hypothetical. On the MARKETPLACE install route - the one docs/install.md
      calls recommended for consumers - the plugin directory has no `.git`, so
      every git-backed `command` rule in checklist.json exits 128 having read
      nothing. The engine scored that as "the probe ran and the condition was not
      met" and rendered `[ ] NOT STARTED`, which the product's own documentation
      defines as "a probe RAN and found the thing absent". The two rows that
      flipped read, to a consumer, as "the owner's personal address WAS left in
      history" and "the private sibling project's name IS in the tree" - the
      checklist asserting the opposite of the truth about facts it never
      measured. A false negative here is worse than a false tick would be in the
      other direction, because it accuses.

      THE EXIT CODE ALONE IS NOT ENOUGH and matching on it alone would be the
      papering-over this file exists to refuse: 128 is also git's code for a bad
      revision, a bad object, an ambiguous ref - real refusals, where the probe
      genuinely ran and the answer genuinely is no. So the fatal: line has to say
      which of the two happened, and both halves are required.
    #>
    param($Result, [string]$Tool)

    $exe = @($Tool -split '\s+')[0]
    $err = [string]$Result.err

    # git's four ways of saying "there is no repository here for me to read":
    # no .git found walking up, a bare/absent work tree, and the two ownership
    # refusals git raises before it will touch a repository it does not trust.
    if ([int]$Result.code -eq 128 -and
        $err -match '(?im)fatal:.*(not a git repository|this operation must be run in a work tree|detected dubious ownership|unsafe repository)') {
        $e = (Get-LwgRedacted -Text $err -MaxLength 160).Trim()
        return "$exe exited 128 without reaching a repository, so nothing about this item was measured: $e"
    }

    # The interpreter started and then refused, because the script it was
    # pointed at is not there. Invoke-LwgRptProcess reports 'missing' only for a
    # PROGRAM that will not start; a `powershell -File <script>` rule whose
    # script is absent starts powershell perfectly well and gets an exit code
    # from it. That code is 0xFFFD0000 - it is not 1 - but the rule cannot know
    # that, and "the suite this item runs is not installed" is not "the suite
    # ran and found a violation". Matched on the message rather than the code so
    # a genuine nonzero from a script that IS there stays a finding.
    if ($err -match '(?i)to the -File parameter does not exist') {
        $e = (Get-LwgRedacted -Text $err -MaxLength 160).Trim()
        return "$exe would not start the script this item runs, so the item was never checked: $e"
    }

    return ''
}

# --- context ----------------------------------------------------------------

function New-LwgEvidenceContext {
    <#
      Shared caches for one reporting run. Returns a HASHTABLE so it survives the
      function boundary un-enumerated.

      The caches are the reason a 38-item checklist does not spawn 38 children:
      every `commit` item is answered from ONE `git log` per ref, and every `ci`
      item from ONE `gh run list` per workflow-and-branch pair.
    #>
    param([Parameter(Mandatory = $true)][string]$PluginRoot)

    $repo = Get-LwgRepoInfo -Path $PluginRoot

    # use_gh, READ ONCE AND HONOURED HERE TOO.
    #
    # docs/install.md told a first-time installer that `gh` is optional, that only
    # the open-PR check uses it, and that use_gh: false "removes it entirely".
    # Measured on 3 August 2026: the key had exactly ONE reader,
    # lib/stop_advisories.ps1's git_hygiene open-PR check, and THREE further call
    # sites shelled out to gh regardless - this file's `ci` evaluator, and the two
    # checklist rows whose evidence is a `gh` command. So a documented off switch
    # gated one of four sites, which is a switch wired to nothing wearing the name
    # of a switch that works, on a plugin whose whole promise is that it does not
    # do that.
    #
    # The key belongs to git_hygiene and is read from there rather than copied to
    # a second key: two keys spelling the same intention drift, and the operator
    # who set the documented one would be the person surprised. The scope it now
    # has is stated in docs/install.md's requirements table in the same change.
    #
    # WHAT THIS DOES NOT CLOSE, so the row below is not read as more than it is:
    # two shipped checklist rows query the MAINTAINER'S repository by name, so on
    # a consumer's machine `use_gh: true` still means an authenticated outbound
    # call to a repository they never named. Turning the key off now genuinely
    # stops it; leaving it on does not announce it. That half needs those rows out
    # of the shipped payload and is tracked separately.
    $useGh = $true
    try {
        $cfg = Get-LwgConfig
        $useGh = [bool](Get-LwgModuleFlag -Config $cfg -Module 'git_hygiene' -Key 'use_gh' -Default $true)
    } catch {
        # A config this cannot read must not silently disable a probe: the
        # shipped default is on, and failing closed here would turn every gh-backed
        # row UNVERIFIED for a reason the operator never chose.
        $useGh = $true
    }

    return @{
        root     = $PluginRoot
        git_root = $repo.root
        slug     = $repo.slug
        use_gh   = $useGh
        commits  = @{}
        ci       = @{}
        spawned  = 0
        spent_ms = 0
    }
}

function Invoke-LwgCtxProcess {
    <# Invoke-LwgRptProcess, counting the cost onto the context. #>
    param($Ctx, [string]$File, [string[]]$ProcArgs, [string]$WorkDir, [int]$TimeoutMs = 6000)

    $r = Invoke-LwgRptProcess -File $File -ProcArgs $ProcArgs -WorkDir $WorkDir -TimeoutMs $TimeoutMs
    $Ctx.spawned  = [int]$Ctx.spawned + 1
    $Ctx.spent_ms = [int]$Ctx.spent_ms + [int]$r.ms
    return $r
}

function Get-LwgRptCommits {
    <#
      The newest $Limit commits reachable from $Ref, newest first, as
      @{ ok; why; truncated; limit; commits = @(@{sha; subject}) }.

      ok $false means the history could not be READ - not that it is empty. The
      caller must turn that into unverified.

      truncated $true means the scan CAME BACK FULL, so the history may well be
      deeper than what is in `commits` and a MISS proves nothing. It is reported
      rather than left to be inferred because the caller cannot work it out: the
      function used to return a list and a flag saying only whether git ran, and
      "no commit matched" then read identically whether the scan had reached the
      root of history or stopped 600 commits short of it. The `commit` evaluator
      turned that into 'fail', which /lw-watchtower:checklist renders `[ ] NOT STARTED`
      and the product defines as "a probe RAN and found the thing absent" - the
      exact could-not-look-scored-as-a-finding shape this file's header says has
      no code path, one evaluator along from the one that was fixed for it.

      It is a CONSERVATIVE flag and says so: `count -ge Limit` is true for a
      history that is exactly $Limit deep, where the scan really did reach the
      root. That direction costs an UNVERIFIED where a finding was available; the
      other direction costs a wrong accusation, which is the one this project
      refuses. Asking git for $Limit+1 to distinguish the two was considered and
      not done - it moves the ambiguity by one rather than removing it, because
      the same reasoning applies at $Limit+1.
    #>
    param($Ctx, [string]$Ref = 'main', [int]$Limit = 600)

    $key = "$Ref/$Limit"
    if ($Ctx.commits.ContainsKey($key)) { return $Ctx.commits[$key] }

    $res = @{ ok = $false; why = ''; truncated = $false; limit = $Limit; commits = @() }
    if ([string]::IsNullOrWhiteSpace([string]$Ctx.git_root)) {
        $res.why = 'not inside a git repository, so no commit can be cited'
        $Ctx.commits[$key] = $res
        return $res
    }

    # %x09 is a tab: a subject can contain anything except a newline, so the
    # first tab is the only safe split point.
    $r = Invoke-LwgCtxProcess -Ctx $Ctx -File 'git' -WorkDir $Ctx.git_root -TimeoutMs 6000 -ProcArgs @(
        '--no-pager', 'log', $Ref, '--format=%H%x09%s', '-n', [string]$Limit)

    if (-not $r.ok) {
        $res.why = Get-LwgRptProcessWhy -Result $r -Tool 'git log'
        $Ctx.commits[$key] = $res
        return $res
    }

    $acc = New-Object 'System.Collections.Generic.List[hashtable]'
    foreach ($raw in $r.out.Split([char]10)) {
        $line = $raw.TrimEnd([char]13)
        if ($line.Length -eq 0) { continue }
        $t = $line.IndexOf([char]9)
        if ($t -lt 0) { continue }
        [void]$acc.Add(@{ sha = $line.Substring(0, $t); subject = $line.Substring($t + 1) })
    }
    $res.ok        = $true
    $res.commits   = $acc.ToArray()
    $res.truncated = ($acc.Count -ge $Limit)
    $Ctx.commits[$key] = $res
    return $res
}

function Get-LwgRptCiRun {
    <#
      The newest CI run for one workflow on one branch, as
      @{ ok; why; status; conclusion; url; created }.

      ok $false means gh could not be asked. An EMPTY answer is ok $true with an
      empty status - "no run exists" is a finding, "I could not ask" is not.
    #>
    param($Ctx, [string]$Workflow = 'CI', [string]$Branch = 'main', [int]$TimeoutMs = 8000)

    $key = "$Workflow|$Branch"
    if ($Ctx.ci.ContainsKey($key)) { return $Ctx.ci[$key] }

    $res = @{ ok = $false; why = ''; status = ''; conclusion = ''; url = ''; created = '' }
    # `ok $false` is the right shape for this: the operator switched the tool off,
    # so the question was not asked and the caller must render unverified. It is
    # NOT "no run exists", which is the empty-status pass below and a finding.
    if ($null -ne $Ctx.use_gh -and -not $Ctx.use_gh) {
        $res.why = 'gh calls are switched off by module_config.git_hygiene.use_gh = false, so no CI conclusion was fetched'
        $Ctx.ci[$key] = $res
        return $res
    }
    if ([string]::IsNullOrWhiteSpace([string]$Ctx.slug)) {
        $res.why = 'no origin remote slug could be resolved, so there is no repo to query'
        $Ctx.ci[$key] = $res
        return $res
    }

    $r = Invoke-LwgCtxProcess -Ctx $Ctx -File 'gh' -WorkDir $Ctx.git_root -TimeoutMs $TimeoutMs -ProcArgs @(
        'run', 'list', '--repo', $Ctx.slug, '--workflow', $Workflow, '--branch', $Branch,
        '--limit', '1', '--json', 'status,conclusion,url,createdAt')

    if (-not $r.ok) {
        $res.why = Get-LwgRptProcessWhy -Result $r -Tool 'gh run list'
        $Ctx.ci[$key] = $res
        return $res
    }

    try {
        $runs = @($r.out | ConvertFrom-Json -ErrorAction Stop)
        $res.ok = $true
        if ($runs.Count -gt 0 -and $null -ne $runs[0]) {
            $res.status     = [string]$runs[0].status
            $res.conclusion = [string]$runs[0].conclusion
            $res.url        = [string]$runs[0].url
            $res.created    = [string]$runs[0].createdAt
        }
    } catch {
        $res.ok = $false
        $res.why = "gh returned output this command could not parse as JSON: $($_.Exception.Message)"
    }
    $Ctx.ci[$key] = $res
    return $res
}

# --- evidence evaluation ----------------------------------------------------

function Expand-LwgRptLiteral {
    <#
      One manifest string, with a `rot13:` prefix decoded. Anything else comes
      back untouched.

      WHY A TRACKED MANIFEST MAY NOT SPELL ITS OWN TARGET.
      Two of checklist.json's rules are NEGATIVE assertions - "the private
      sibling project's name does not appear in the tracked tree" and "the
      owner's former personal address appears on no commit" - and until 3 August
      2026 both spelled their target in the manifest, in reading order, in a
      tracked file that ships in the plugin payload and is PRINTED to the
      operator by /lw-watchtower:checklist.

      One was a bracket class - shaped `[Ff][Oo][Oo]...`, with the letters
      NEUTRALISED for the reason two paragraphs down - whose caveat argued that
      it "spells no matching literal". True of `git grep`, and false of a human, a
      search engine, an indexer or a language model, all of which read it left to
      right in about two seconds - including in the rendered row, where the row
      asserting the name is absent printed the name. The other was the local-part
      of a personal address, whose caveat argued correctly that the probe reads
      `git log` output and never the tree, so the literal cannot make the probe
      pass falsely. That argument is sound about the PROBE and says nothing about
      PUBLICATION: on a public repository the local-part sits beside a changelog
      entry recording that identities were rewritten, and the two together hand a
      reader the whole address.

      Both forms also defeat the tooling meant to clean them. A history rewrite
      removes a string with `git filter-repo --replace-text` or an equivalent,
      and neither form contains its target in reading order, so a
      case-insensitive pass walks straight past both and reports success on
      exactly the input designed to defeat it.

      ROT13 IS NOT SECRECY AND NOTHING HERE PRETENDS IT IS. It is a transposition
      anyone can undo in one line, and that is the correct strength for this: the
      requirement is that no tracked file spells the target IN READING ORDER, so
      that grep finds nothing because there is nothing to find, an automated
      replace pass is not silently defeated, and a reader of the file - or of the
      rendered row - is not handed the string. Someone who wants it can still
      get it. Rearranging the bracket class or splitting the literal across a
      JSON concatenation would NOT do: both still spell it to a reader, which is
      the whole defect.

      WHY THE ILLUSTRATION ABOVE USES `[Ff][Oo][Oo]` AND NOT THE REAL LETTERS,
      changed 3 August 2026 in the three places that carried them. The first
      three letters of the removed construction were the first three letters of
      the name it spelled - and also the first three of the PUBLISHER's name, so
      they gave a reader nothing on their own. What they did do was match the
      pre-publication check `git grep -E "\[Ll\]\[Ee\]\[Aa\]"`, which is run by
      hand against a tree that is about to be published and has no way to tell a
      three-letter prose illustration from a full obfuscated name. Three hits
      that always need the same paragraph of explanation train a reader to wave
      the check through, which is how a real hit gets waved through with them.
      Nothing about the argument depended on which letters were used, so the
      illustration was moved to letters that spell nothing and the check now
      answers zero. This is a change to an EXAMPLE, not to a rule: the reduction
      in tests/evidence_states.ps1 is unchanged and still collapses any
      single-letter class, and it - not the grep - is what actually holds the
      manifest to reading order.

      Rot13 rather than reversal or base64: reversal is read at a glance, and
      base64 is unreadable to a REVIEWER too, which would mean a probe argument
      nobody can check in a pull request. Rot13 is mechanical enough to verify by
      hand and opaque enough that the string is not on the page.
    #>
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    if (-not $Text.StartsWith('rot13:', [StringComparison]::Ordinal)) { return $Text }

    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $Text.Substring(6).ToCharArray()) {
        $c = [int][char]$ch
        if ($c -ge 65 -and $c -le 90)       { [void]$sb.Append([char](65 + (($c - 65 + 13) % 26))) }
        elseif ($c -ge 97 -and $c -le 122)  { [void]$sb.Append([char](97 + (($c - 97 + 13) % 26))) }
        else                                { [void]$sb.Append($ch) }
    }
    return $sb.ToString()
}

function Get-LwgRptJsonStrings {
    <#
      Every string in a decoded JSON tree, flattened. Used by the `hook` rule to
      find a script path wherever a registration happens to put it - a `command`
      string and an `args` array are both legal shapes, and asking about one of
      them would make the probe depend on how the file is written rather than on
      what it registers.

      bin/lwg-doctor.ps1 carries the same walker as a private Get-JsonStrings and
      this is a THIRD copy of the shape rather than a shared helper, for the
      reason this file's header already gives about the subprocess helper: the one
      place both could live is lib/common.ps1, which is dot-sourced on hook paths,
      and nothing in bin/ may push work there for its own convenience. Twelve
      lines of recursion is a cheaper duplication than a shared file that grows.
    #>
    param($Node)
    if ($null -eq $Node) { return }
    if ($Node -is [string]) { return $Node }
    if ($Node -is [System.Collections.IEnumerable]) {
        foreach ($item in $Node) { Get-LwgRptJsonStrings -Node $item }
        return
    }
    if ($Node -is [System.Management.Automation.PSCustomObject]) {
        foreach ($p in $Node.PSObject.Properties) { Get-LwgRptJsonStrings -Node $p.Value }
    }
}

function Resolve-LwgRptPath {
    <#
      A manifest path, resolved STRICTLY INSIDE the plugin root. Returns $null for
      anything that would escape it - a manifest is tracked and reviewed, but a
      report that can be pointed at C:\Windows by a one-line edit is a report worth
      breaking.

      "STRICTLY INSIDE" IS A CORRECTION, NOT EMPHASIS. Until 3 August 2026 the
      containment test was a bare string prefix against the root with no trailing
      separator, so every SIBLING directory whose name merely EXTENDS the root's
      passed it: with the root at ...\lw-watchtower, the paths ...\lw-watchtower-fix\x,
      ...\lw-watchtower.old\x and ...\lw-watchtower2\x were all "contained". The traversal case
      the guard was written against (..\..\Windows) really was handled - GetFullPath
      normalises it and the prefix test then rejects it - and the sibling case has
      no `..` in it, so it never looked like an escape. That shape is not
      hypothetical on this project: the v0.4.0 fix work is done in a worktree
      sitting beside the checkout, and a rule resolved into the OTHER tree would
      have been read, matched and cited by /lw-watchtower:checklist as evidence about the
      tree the operator is actually running.

      Two changes, and the second is not decoration:

        1. the base carries a trailing directory separator, so containment is
           tested at a path boundary rather than at a character offset. Note the
           consequence: $Root ITSELF no longer passes. That is correct here and
           only here - this resolves FILE paths, and the one call site
           (Test-LwgEvidence's `file` branch) then requires PathType Leaf anyway -
           but it is the thing to check before this function acquires a second
           caller.

        2. a ROOTED $Rel is refused outright. [IO.Path]::Combine returns $Rel
           unchanged when it is rooted, so "C:\somewhere\x" never got joined under
           the root at all and reached the prefix test on its own. Refusing it by
           name is clearer than normalising it and hoping the boundary test catches
           it, and a manifest naming an absolute path is a manifest error whichever
           way it lands.

      WHAT THIS STILL DOES NOT DO. It is a path-shape test, not a filesystem one:
      a SYMLINK or a directory junction inside the root that points outside it
      resolves to a contained path here and is read. GetFullPath does not follow
      links, and nothing below does either. On this plugin the normal install IS
      reached through a junction - see lib/common.ps1's root probes - so resolving
      links here would have to distinguish the junction the plugin lives behind
      from one planted inside it, which is a different piece of work and is not
      attempted. Stated rather than left for the next reader to discover.
    #>
    param([string]$Root, [string]$Rel)

    if ([string]::IsNullOrWhiteSpace($Rel)) { return $null }
    try {
        if ([IO.Path]::IsPathRooted($Rel)) { return $null }
        $full = [IO.Path]::GetFullPath([IO.Path]::Combine($Root, $Rel))
        # TrimEnd before appending: a $Root that already ends in a separator - a
        # drive root, or a path built by Join-Path with a trailing slash - would
        # otherwise get a doubled one and match nothing at all, which fails in the
        # safe direction but would refuse every legitimate path in the manifest.
        $base = [IO.Path]::GetFullPath($Root).TrimEnd([char]92, [char]47) + [IO.Path]::DirectorySeparatorChar
        if (-not $full.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { return $null }
        return $full
    } catch { }
    return $null
}

function Test-LwgEvidence {
    <#
      Evaluate one evidence rule. Returns a HASHTABLE:

        @{ state; detail; present; total; partial }

        state    'pass'    the thing is demonstrably so
                 'fail'    the probe ran, REACHED the thing, and it is
                           demonstrably NOT so
                 'running' the probe ran and the thing is under way right now
                 'unknown' the probe could not be run, ran but never reached the
                           thing, or there is no probe
        detail   what was actually observed, in a form that can be quoted
        partial  $true when SOME of a required set is present

      'unknown' is the load-bearing state. Anything that returns it must be
      rendered as unverified, never as incomplete: the difference between "this
      is not done" and "I could not tell" is the whole reason this file exists.
    #>
    param($Ctx, $Ev)

    $r = @{ state = 'unknown'; detail = ''; present = 0; total = 0; partial = $false }

    if ($null -eq $Ev) {
        $r.detail = 'no evidence rule is defined for this item'
        return $r
    }

    $kind = [string]$Ev.kind
    switch ($kind) {

        'manual' {
            # Deliberately never passes. Some items genuinely cannot be checked
            # from this machine - an org-level setting, a decision recorded
            # outside the repo - and the honest report of those is "unverified
            # forever", not a checkbox someone can tick by hand.
            $n = [string]$Ev.note
            $r.detail = $(if ([string]::IsNullOrWhiteSpace($n)) { 'no automatable evidence exists for this item' } else { $n })
            return $r
        }

        'file' {
            $paths = @()
            if ($Ev.paths)          { $paths = @($Ev.paths | ForEach-Object { [string]$_ }) }
            elseif ($Ev.path)       { $paths = @([string]$Ev.path) }
            if ($paths.Count -eq 0) {
                $r.detail = 'file evidence names no path'
                return $r
            }
            $r.total = $paths.Count

            $missing = @()
            $bad     = @()
            $seen    = @()
            foreach ($rel in $paths) {
                $full = Resolve-LwgRptPath -Root $Ctx.root -Rel $rel
                if ($null -eq $full) {
                    $r.detail = "manifest path '$rel' resolves outside the plugin root and was NOT read"
                    return $r
                }
                if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { $missing += $rel; continue }
                $r.present++
                $seen += $rel

                if ($Ev.contains -or $Ev.not_contains) {
                    $txt = ''
                    try { $txt = [IO.File]::ReadAllText($full) }
                    catch {
                        $r.detail = "$rel exists but could not be read: $($_.Exception.Message)"
                        return $r   # unknown - a file we cannot read is not a file we can judge
                    }
                    if ($Ev.contains -and $txt -notmatch [string]$Ev.contains) {
                        $bad += "$rel does not contain /$([string]$Ev.contains)/"
                    }
                    if ($Ev.not_contains -and $txt -match [string]$Ev.not_contains) {
                        $bad += "$rel still contains /$([string]$Ev.not_contains)/"
                    }
                }
            }

            if ($missing.Count -eq 0 -and $bad.Count -eq 0) {
                $r.state = 'pass'
                $what = $(if ($paths.Count -eq 1) { $paths[0] } else { "all $($paths.Count) files present: $($paths -join ', ')" })
                if ($Ev.contains)     { $what += " (matches /$([string]$Ev.contains)/)" }
                if ($Ev.not_contains) { $what += " (no /$([string]$Ev.not_contains)/)" }
                $r.detail = $what
                return $r
            }

            $r.state = 'fail'
            $bits = @()
            if ($missing.Count -gt 0) {
                if ($paths.Count -eq 1) { $bits += "$($missing[0]) does not exist" }
                else { $bits += "$($r.present) of $($paths.Count) present; missing $($missing -join ', ')" }
            }
            if ($bad.Count -gt 0) { $bits += ($bad -join '; ') }
            $r.detail  = ($bits -join ' / ')
            $r.partial = ($r.present -gt 0 -and $r.present -lt $paths.Count)
            return $r
        }

        'hook' {
            # ONE HOOK REGISTRATION, ASKED ABOUT AS A REGISTRATION.
            #
            # WHY THIS KIND EXISTS AND A `contains` REGEX DOES NOT DO IT.
            # PD-delegate's rule was a single regex over the raw text of
            # hooks/hooks.json:
            #
            #   (?s)"PreToolUse".*"matcher"\s*:\s*"...".*gate_delegate\.ps1
            #
            # With (?s) the dot spans newlines and each .* is greedy across the
            # whole document, so the pattern asserted three INDEPENDENT facts -
            # the string "PreToolUse" appears; some matcher appears after it; the
            # gate's file name appears after that - and nothing bound the three to
            # one entry. Measured on this tree: a hooks.json with "PreToolUse": []
            # and the gate registered on PostToolUse SATISFIES it. PostToolUse runs
            # after the tool call has already executed and can refuse nothing, so
            # the manifest row attesting this plugin's only blocking component
            # would have rendered DONE over a plugin that refuses nothing at all.
            # Widening the same regex was rejected as the fix: matcher order is not
            # fixed by anything and the fragments stay unbound however long the
            # pattern gets. The structure has to be PARSED, so it is.
            #
            # DELIBERATELY NARROW. This is not a general JSON-query kind. It asks
            # exactly one question - is script S registered on event E, in ONE
            # entry, whose matcher names every tool in this list - because a
            # general selector language would be a second thing to get right and
            # its failure mode is a selector that resolves to nothing and reports
            # a pass, which is the defect this plugin is named for.
            #
            # WHAT IT STILL DOES NOT PROVE, and the caveat on the row says the same
            # in the operator's words: that the script refuses anything. A
            # registered hook that exits 0 on every path passes this. Refusal is
            # established by tests/gate_delegate.ps1 and by nothing here.
            $rel = [string]$Ev.path
            if ([string]::IsNullOrWhiteSpace($rel)) {
                $r.detail = 'hook evidence names no path'
                return $r
            }
            $full = Resolve-LwgRptPath -Root $Ctx.root -Rel $rel
            if ($null -eq $full) {
                $r.detail = "manifest path '$rel' resolves outside the plugin root and was NOT read"
                return $r
            }
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
                # The registration file being absent IS an answer: nothing is
                # registered. That is rung 8, not rung 3.
                $r.state  = 'fail'
                $r.detail = "$rel does not exist, so nothing is registered by it"
                return $r
            }
            $hooksDoc = $null
            try { $hooksDoc = [IO.File]::ReadAllText($full) | ConvertFrom-Json }
            catch {
                # A file we cannot parse is a file we cannot judge - unknown, not a
                # finding. Distinct from the missing case above on purpose.
                $r.detail = "$rel exists but did not parse as JSON, so its registrations were not read: $($_.Exception.Message)"
                return $r
            }

            $event  = [string]$Ev.event
            $script = [string]$Ev.script
            if ([string]::IsNullOrWhiteSpace($event) -or [string]::IsNullOrWhiteSpace($script)) {
                $r.detail = 'hook evidence names no event or no script'
                return $r
            }
            $want = @()
            if ($Ev.matcher_all) { $want = @($Ev.matcher_all | ForEach-Object { [string]$_ }) }

            $entries = @()
            try { $entries = @($hooksDoc.hooks.$event) } catch { }
            $entries = @($entries | Where-Object { $null -ne $_ })
            if ($entries.Count -eq 0) {
                $r.state  = 'fail'
                $r.detail = "$rel registers nothing on $event at all"
                return $r
            }

            # The entries on this event that invoke the named script, found by
            # walking every string in the entry rather than by assuming where the
            # path sits - a `command` string and an `args` array are both legal
            # shapes and the doctor's hooks-declared check walks the same way.
            $onEvent = @()
            foreach ($e in $entries) {
                $names = @()
                foreach ($s in @(Get-LwgRptJsonStrings -Node $e)) {
                    if ([string]$s -match ([regex]::Escape($script) -replace '/', '[\\/]')) { $names += [string]$s }
                }
                if ($names.Count -gt 0) { $onEvent += $e }
            }
            if ($onEvent.Count -eq 0) {
                $r.state  = 'fail'
                $r.detail = "$rel has $($entries.Count) $event entry/entries and NONE of them invokes $script"
                return $r
            }

            # Every wanted tool must be named by the matcher of ONE of those
            # entries. Checked per entry, not unioned across entries: two entries
            # covering half the list each would leave every call matched by only
            # one of them, which is not the same registration.
            $best     = $null
            $bestMiss = $null
            foreach ($e in $onEvent) {
                $m    = [string]$e.matcher
                $miss = @()
                foreach ($t in $want) {
                    if ($m -notmatch ('(?<![A-Za-z0-9_])' + [regex]::Escape($t) + '(?![A-Za-z0-9_])')) { $miss += $t }
                }
                if ($null -eq $bestMiss -or $miss.Count -lt $bestMiss.Count) { $bestMiss = $miss; $best = $m }
                if ($miss.Count -eq 0) {
                    $r.state  = 'pass'
                    $r.detail = "$rel registers $script on $event with matcher '$m', which names all $($want.Count) required tool(s): $($want -join ', ')"
                    return $r
                }
            }
            $r.state  = 'fail'
            $r.detail = "$rel registers $script on $event, but no single entry's matcher names every required tool - " +
                        "the closest is '$best', missing $($bestMiss -join ', ')"
            return $r
        }

        'commit' {
            $ref   = $(if ($Ev.ref) { [string]$Ev.ref } else { 'main' })
            $match = [string]$Ev.match
            if ([string]::IsNullOrWhiteSpace($match)) {
                $r.detail = 'commit evidence names no subject pattern'
                return $r
            }
            # scan_limit is how deep the rule asks git to look. It exists so the
            # window is a property OF THE RULE rather than a constant buried in a
            # helper - the previous shape had no caller passing it and no manifest
            # able to widen it - and so the truncated-miss path below can be driven
            # by a case instead of needing a 600-commit fixture. 600 remains the
            # default and no shipped rule sets it.
            $limit = $(if ($null -ne $Ev.scan_limit -and [int]$Ev.scan_limit -gt 0) { [int]$Ev.scan_limit } else { 600 })
            $log = Get-LwgRptCommits -Ctx $Ctx -Ref $ref -Limit $limit
            if (-not $log.ok) {
                $r.detail = "commit history could not be read - $($log.why)"
                return $r
            }
            foreach ($c in $log.commits) {
                if ($c.subject -match $match) {
                    $r.state  = 'pass'
                    $short    = $(if ($c.sha.Length -ge 7) { $c.sha.Substring(0, 7) } else { $c.sha })
                    $r.detail = "commit $short reachable from $ref - `"$($c.subject)`""
                    return $r
                }
            }
            # A MISS INSIDE A FULL SCAN IS NOT AN ABSENCE. The scan stopped where
            # it was told to, so the commit may sit one past the window and this
            # probe never reached the question. That is rung 3 of the ladder in
            # Resolve-LwgChecklist - UNVERIFIED - and not rung 8. A miss in a scan
            # that reached the root of history stays a finding: that one really did
            # look at every commit there is, and softening it would leave the
            # checklist unable to report anything undone, which is the mirror
            # defect and the worse of the two.
            if ($log.truncated) {
                $r.detail = "no commit in the newest $($log.limit) reachable from $ref has a subject matching /$match/, " +
                            "and the scan came back full - so the history is at least that deep and this was NOT established either way. " +
                            "Raise scan_limit on this rule to look further back"
                return $r
            }
            $r.state  = 'fail'
            $r.detail = "no commit reachable from $ref has a subject matching /$match/ ($($log.commits.Count) commits scanned, which reached the root of the scanned history)"
            return $r
        }

        'command' {
            $file = [string]$Ev.file
            if ([string]::IsNullOrWhiteSpace($file)) {
                $r.detail = 'command evidence names no program'
                return $r
            }
            # TWO ARGUMENT ARRAYS, AND THE DIFFERENCE IS THE POINT.
            #   $a    exactly as the manifest spells it - what gets PRINTED
            #   $aRun with any `rot13:` literal decoded - what gets RUN
            # Decoding for display as well would put the string back on the
            # operator's screen, which is half of what Expand-LwgRptLiteral exists
            # to stop: the row asserting the private sibling project's name is
            # absent used to print that name in its own detail line, on every
            # machine that ran the command.
            #
            # WHAT THIS DOES NOT SUPPRESS, said plainly rather than left to be
            # assumed. Only the ARGUMENTS are held back. If the program itself
            # echoes the pattern - a git usage error quoting the argument it
            # rejected - that text reaches $res.err and can reach a detail line
            # through Get-LwgRptProcessWhy, truncated to 140-160 characters by
            # Get-LwgRedacted but not filtered for this. Neither shipped rule
            # produces such output on any path observed here; that is an
            # observation about two rules, not a property of the mechanism.
            $a    = @()
            $aRun = @()
            if ($Ev.args) {
                $a    = @($Ev.args | ForEach-Object { [string]$_ })
                $aRun = @($a | ForEach-Object { Expand-LwgRptLiteral -Text $_ })
            }
            # The same off switch the `ci` evaluator honours, applied to the rules
            # that name gh directly. Matched on the program the rule runs rather
            # than on a per-rule opt-out key, because the operator's setting is
            # about the TOOL: a manifest able to declare itself exempt from the
            # switch would be the switch not working again, one indirection along.
            if (($file -eq 'gh' -or $file -eq 'gh.exe') -and $null -ne $Ctx.use_gh -and -not $Ctx.use_gh) {
                $r.detail = "this item is proved by running gh, and gh calls are switched off by " +
                            "module_config.git_hygiene.use_gh = false - so it was NOT checked. " +
                            "This is not evidence either way about the thing the item claims"
                return $r
            }
            $to = $(if ($Ev.timeout_ms) { [int]$Ev.timeout_ms } else { 6000 })
            $wd = $(if ([string]::IsNullOrWhiteSpace([string]$Ctx.git_root)) { $Ctx.root } else { $Ctx.git_root })

            $res = Invoke-LwgCtxProcess -Ctx $Ctx -File $file -ProcArgs $aRun -WorkDir $wd -TimeoutMs $to

            # 'missing' and 'timeout' are ALWAYS unknown: the tool never gave an
            # answer, so there is nothing to interpret.
            if ($res.state -eq 'missing' -or $res.state -eq 'timeout' -or $res.state -eq 'error') {
                $r.detail = "$file $($a -join ' ') - " + (Get-LwgRptProcessWhy -Result $res -Tool $file)
                return $r
            }

            $want = $(if ($null -ne $Ev.expect_exit) { [int]$Ev.expect_exit } else { 0 })
            if ($res.code -ne $want) {
                # The exit code is not what the rule asked for. Before it is read
                # as an answer, three things have to be ruled out - and each of
                # them is a probe that never reached the question.

                # 1. The program declined to look at all. A git command outside a
                #    repository is the case that shipped: see
                #    Get-LwgProbeUnreachable. Checked before nonzero_means so a
                #    rule that never declared the knob still gets the honest
                #    answer, and checked only when the code DIFFERS from $want so
                #    a rule that deliberately expects 128 keeps its own meaning.
                $unreachable = Get-LwgProbeUnreachable -Result $res -Tool $file
                if (-not [string]::IsNullOrWhiteSpace($unreachable)) {
                    $r.detail = "$file $($a -join ' ') did not run against anything: $unreachable. " +
                                "This is NOT evidence that the thing is absent - the probe never looked"
                    return $r
                }

                # 2. A non-zero exit from an API probe conflates "the thing is not
                #    configured" with "I was not allowed to look". Where the
                #    manifest says so, that becomes unverified instead of a false
                #    negative.
                if ([string]$Ev.nonzero_means -eq 'unverified') {
                    $r.detail = "$file $($a -join ' ') exited $($res.code) rather than $want, which this item declares indistinguishable from being denied the answer: " +
                                (Get-LwgRedacted -Text ([string]$res.err) -MaxLength 140).Trim()
                    return $r
                }

                # 3. Nothing above applies, so the program ran, reached the
                #    question and answered no. That is a finding.
                $r.state  = 'fail'
                $r.detail = "$file $($a -join ' ') exited $($res.code), expected $want"
                return $r
            }

            $out = [string]$res.out
            # Same split as the argument arrays above: the pattern that is APPLIED
            # is decoded, the pattern that is PRINTED is the manifest's spelling.
            # P3-identity's stdout_not_match is the local-part of the owner's
            # former personal address, so a detail line quoting the pattern would
            # publish it to every consumer who runs the command.
            $matchPat    = Expand-LwgRptLiteral -Text ([string]$Ev.stdout_match)
            $notMatchPat = Expand-LwgRptLiteral -Text ([string]$Ev.stdout_not_match)
            if ($Ev.stdout_match) {
                # EMPTY OUTPUT IS NOT A NEGATIVE ANSWER when the rule proves the
                # item FROM the output. The exit code says the program ran; it
                # does not say the program had anything to read. `git tag -l`
                # exits 0 with empty stdout on a clone whose tag refs were never
                # fetched, and P8-tag's caveat has carried that gap in writing
                # since the rule was written - "closing that needs a knob the
                # evidence engine does not have". This is the knob, and it needs
                # no manifest change: a rule that asserts a pattern over output
                # cannot be settled either way by output that does not exist.
                #
                # NOT applied to stdout_not_match on its own. There, empty output
                # can legitimately BE the pass - a probe that lists offenders and
                # lists none - so refusing it would manufacture UNVERIFIED rows
                # out of correct answers. A rule that wants both readings has
                # both keys, and stdout_match is checked first.
                if ([string]::IsNullOrWhiteSpace($out)) {
                    $r.detail = "$file $($a -join ' ') exited $($res.code) as expected but printed NOTHING, " +
                                "and this item is proved from its output (/$([string]$Ev.stdout_match)/). " +
                                "Empty output is not evidence that the thing is absent - there was nothing to match against"
                    return $r
                }
                if ($out -notmatch $matchPat) {
                    $r.state  = 'fail'
                    $r.detail = "$file exited $($res.code) as expected but its output does not match /$([string]$Ev.stdout_match)/"
                    return $r
                }
            }
            if ($Ev.stdout_not_match -and $out -match $notMatchPat) {
                $r.state  = 'fail'
                $r.detail = "$file exited $($res.code) as expected but its output still matches /$([string]$Ev.stdout_not_match)/"
                return $r
            }
            $r.state  = 'pass'
            $r.detail = "$file $($a -join ' ') exited $($res.code) in $($res.ms) ms"
            if ($Ev.stdout_match)     { $r.detail += "; output matches /$([string]$Ev.stdout_match)/" }
            if ($Ev.stdout_not_match) { $r.detail += "; output free of /$([string]$Ev.stdout_not_match)/" }
            return $r
        }

        'ci' {
            $wf = $(if ($Ev.workflow) { [string]$Ev.workflow } else { 'CI' })
            $br = $(if ($Ev.branch)   { [string]$Ev.branch }   else { 'main' })
            $run = Get-LwgRptCiRun -Ctx $Ctx -Workflow $wf -Branch $br
            if (-not $run.ok) {
                $r.detail = "CI conclusion for '$wf' on $br could not be read - $($run.why)"
                return $r
            }
            if ([string]::IsNullOrWhiteSpace($run.status)) {
                $r.state  = 'fail'
                $r.detail = "no run of workflow '$wf' is recorded on $br"
                return $r
            }
            if ($run.status -ne 'completed') {
                $r.state  = 'running'
                $r.detail = "workflow '$wf' on $br is $($run.status) right now ($($run.url))"
                return $r
            }
            if ($run.conclusion -eq 'success') {
                $r.state  = 'pass'
                $r.detail = "newest '$wf' run on $br concluded success at $($run.created) ($($run.url))"
                return $r
            }
            $r.state  = 'fail'
            $r.detail = "newest '$wf' run on $br concluded $($run.conclusion) at $($run.created) ($($run.url))"
            return $r
        }

        default {
            $r.detail = "evidence kind '$kind' is not one this command knows how to check"
            return $r
        }
    }
}

# --- item state resolution --------------------------------------------------

function Resolve-LwgChecklist {
    <#
      Turn manifest items into rendered states. Returns an ARRAY of hashtables:

        @{ id; section; title; state; detail; caveat }

      state is one of DONE, IN PROGRESS, NOT STARTED, BLOCKED, UNVERIFIED.

      THE LADDER, and its order is the whole design:

        1. evidence passed                      -> DONE, citing what was observed
        2. evidence is running                  -> IN PROGRESS
        3. evidence could not be checked        -> UNVERIFIED
        4. a blocker is itself unverified       -> UNVERIFIED
        5. a blocker is not done                -> BLOCKED, naming it
        6. the manifest declares a blocker      -> BLOCKED, marked as DECLARED
        7. part of a required set is present,
           or a progress probe passed           -> IN PROGRESS
        8. otherwise                            -> NOT STARTED

      Unverified outranks blocked (steps 3-4 before 5) for the same reason
      lwg-doctor.ps1 puts exit 3 above exit 1: "I found a fault" and "I could not
      look" are different statements, and an item whose evidence never ran must
      not be described as though its state were known.

      THE ORDER OF THE RUNGS HAS NEVER CHANGED. What changed on 31 July 2026 is
      which results reach rung 3 rather than falling to rung 8, and that is a
      change in Test-LwgEvidence rather than here. Three `command` outcomes used
      to arrive as 'fail' and now arrive as 'unknown': a git command that exited
      128 without reaching a repository (the marketplace install route, where the
      plugin directory has no `.git`); any other exit the rule declares
      indistinguishable from being denied the answer, which is the older
      nonzero_means knob; and an expected exit code with EMPTY stdout under a
      rule that proves the item from a stdout_match. Rung 8 still means what it
      says - the probe ran, reached the question, and the answer was no - and a
      genuinely unmet condition still lands there.

      Step 6 is the only rung that rests on a claim rather than a probe, and it
      is rendered as `DECLARED` so a reader can see that.
    #>
    param($Ctx, $Items)

    $list = @($Items)
    $byId = @{}
    foreach ($it in $list) { if ($it.id) { $byId[[string]$it.id] = $it } }

    # Pass one: every probe runs exactly once, before any state depends on any
    # other. Blockers can point forwards as well as backwards.
    $ev = @{}
    foreach ($it in $list) {
        $id = [string]$it.id
        $ev[$id] = @{
            main     = (Test-LwgEvidence -Ctx $Ctx -Ev $it.evidence)
            progress = $(if ($it.progress) { Test-LwgEvidence -Ctx $Ctx -Ev $it.progress } else { $null })
        }
    }

    # Pass two: resolve, memoised, with a cycle guard. A manifest that blocks A
    # on B and B on A is a manifest bug, and it must surface as unverified rather
    # than as a hang or a stack overflow.
    $state   = @{}
    $visiting = @{}

    function Resolve-One {
        param([string]$Id)

        if ($state.ContainsKey($Id)) { return $state[$Id] }
        if ($visiting.ContainsKey($Id)) {
            return @{ state = 'UNVERIFIED'; detail = "blocker cycle in checklist.json involving '$Id' - the manifest cannot be resolved" }
        }
        $visiting[$Id] = $true

        $it = $byId[$Id]
        $m  = $ev[$Id].main
        $out = $null

        if ($m.state -eq 'pass') {
            $out = @{ state = 'DONE'; detail = $m.detail }
        }
        elseif ($m.state -eq 'running') {
            $out = @{ state = 'IN PROGRESS'; detail = $m.detail }
        }
        else {
            # Blockers are resolved first so their verdict can be quoted either
            # way - as the reason this item is blocked, or as the reason its
            # state is unknowable.
            $blockedBy   = @()
            $unknownBy   = @()
            foreach ($b in @($it.blocked_by)) {
                $bid = [string]$b
                if ([string]::IsNullOrWhiteSpace($bid)) { continue }
                if (-not $byId.ContainsKey($bid)) {
                    $unknownBy += "$bid (no such item in checklist.json)"
                    continue
                }
                $bs = Resolve-One -Id $bid
                if ($bs.state -eq 'UNVERIFIED') { $unknownBy += "$bid (itself unverified)" }
                elseif ($bs.state -ne 'DONE')   { $blockedBy += "$bid ($($bs.state.ToLower()))" }
            }

            if ($m.state -eq 'unknown') {
                $d = "not verified - $($m.detail)"
                if ($blockedBy.Count -gt 0) { $d += "; it is also blocked on $($blockedBy -join ', ')" }
                $out = @{ state = 'UNVERIFIED'; detail = $d }
            }
            elseif ($unknownBy.Count -gt 0) {
                $out = @{ state = 'UNVERIFIED'; detail = "cannot say - blocked on $($unknownBy -join ', '), so whether this is merely blocked or genuinely stalled is unknown" }
            }
            elseif ($blockedBy.Count -gt 0) {
                $out = @{ state = 'BLOCKED'; detail = "blocked on $($blockedBy -join ', ') - $($m.detail)" }
            }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$it.blocked_reason)) {
                $out = @{ state = 'BLOCKED'; detail = "DECLARED in checklist.json, not observed: $([string]$it.blocked_reason)" }
            }
            elseif ($m.partial) {
                $out = @{ state = 'IN PROGRESS'; detail = $m.detail }
            }
            elseif ($null -ne $ev[$Id].progress -and ($ev[$Id].progress.state -eq 'pass' -or $ev[$Id].progress.partial)) {
                # A progress probe that PARTLY passed counts too. Half a required
                # set on disk is work under way by any reading, and calling it
                # 'not started' would be the mirror image of the sin this file
                # guards against - understating rather than overstating.
                $out = @{ state = 'IN PROGRESS'; detail = "under way: $($ev[$Id].progress.detail); not done because $($m.detail)" }
            }
            elseif ($null -ne $ev[$Id].progress -and $ev[$Id].progress.state -eq 'unknown') {
                $out = @{ state = 'UNVERIFIED'; detail = "not done ($($m.detail)), but whether it is under way could not be checked - $($ev[$Id].progress.detail)" }
            }
            else {
                $out = @{ state = 'NOT STARTED'; detail = $m.detail }
            }
        }

        $visiting.Remove($Id)
        $state[$Id] = $out
        return $out
    }

    $rows = New-Object System.Collections.ArrayList
    foreach ($it in $list) {
        $id = [string]$it.id
        $s  = Resolve-One -Id $id
        [void]$rows.Add([pscustomobject]@{
            Id      = $id
            Section = [string]$it.section
            Title   = [string]$it.title
            State   = $s.state
            Detail  = $s.detail
            Caveat  = $(if ($s.state -eq 'DONE') { [string]$it.caveat } else { '' })
        })
    }
    return $rows.ToArray()
}

# --- plan drift -------------------------------------------------------------

function Get-LwgPlanKey {
    <#
      A heading reduced to letters and digits. Comparing raw headings would make
      the drift check fail on an em dash or an emoji surviving one encoding and
      not another, which would report drift that is purely cosmetic.
    #>
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    return ([regex]::Replace($Text.ToLowerInvariant(), '[^a-z0-9]', ''))
}

function Measure-LwgPlanDrift {
    <#
      Compare checklist.json against the plan file it was transcribed from.
      Returns @{ available; why; checkboxes; sections; missing }.

      This is what makes the staleness risk of a hand-maintained manifest
      MEASURABLE rather than merely disclosed. The plan lives outside the repo,
      so on any other machine this is unavailable and says so - which is itself
      the honest answer, not a silent pass.
    #>
    param([string]$PlanPath, $Items)

    $d = @{ available = $false; why = ''; checkboxes = 0; sections = 0; missing = @() }
    if ([string]::IsNullOrWhiteSpace($PlanPath)) {
        $d.why = 'checklist.json names no source plan'
        return $d
    }
    $p = [Environment]::ExpandEnvironmentVariables($PlanPath)
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        $d.why = "the source plan is not present at $p (it lives outside this repo), so drift between it and checklist.json cannot be measured here"
        return $d
    }

    try {
        $text = [IO.File]::ReadAllText($p)
    } catch {
        $d.why = "the source plan at $p could not be read: $($_.Exception.Message)"
        return $d
    }

    $covered = @{}
    foreach ($it in @($Items)) { $covered[(Get-LwgPlanKey -Text ([string]$it.section))] = $true }

    $heading = ''
    $inSec   = @{}
    foreach ($raw in $text.Split([char]10)) {
        $line = $raw.TrimEnd([char]13)
        if ($line -match '^#{2,3}\s+(.+?)\s*$') { $heading = $Matches[1]; continue }
        if ($line -match '^\s*-\s\[[ xX]\]') {
            $d.checkboxes++
            if ($heading) { $inSec[$heading] = $true }
        }
    }
    $d.available = $true
    $d.sections  = $inSec.Count
    foreach ($h in $inSec.Keys) {
        if (-not $covered.ContainsKey((Get-LwgPlanKey -Text $h))) { $d.missing += $h }
    }
    return $d
}
