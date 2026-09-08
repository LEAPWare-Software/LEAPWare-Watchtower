#requires -version 5
<#
  LW-WATCHTOWER SubagentStart fast-scan regression suite.

      powershell -NoProfile -ExecutionPolicy Bypass -File tests\subagent_scan.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File tests\subagent_scan.ps1 -Verbose

  WHY THIS FILE EXISTS

  lib\subagent_start.ps1 does NOT parse config.json. It reads its own flag out of
  the raw text, because ConvertFrom-Json costs 141-182 ms in a fresh Windows
  PowerShell 5.1 process and this hook runs on every subagent dispatch of every
  session. That duplication is deliberate and is documented in the file's own
  header. It is correct only while the span it scans is the GLOBAL `modules`
  block.

  Get-LwgJsonObjectSpan had no notion of DEPTH. It returned the first
  `"modules":` in document order at ANY nesting level, and config.json's `repos`
  block is documented to hold per-repo `modules` objects. Measured here, in a
  real child process of the real hook, against this fixture:

      {
        "repos": { "acme/example": { "modules": { "docs_coupling": false } } },
        "modules": { "context_injection": false, "git_hygiene": true }
      }

      OUT=[{"hookSpecificOutput":{"hookEventName":"SubagentStart",
            "additionalContext":"...","suppressOutput":true}]

  The module is switched OFF in the global block, /lw-watchtower:doctor, the
  SessionStart banner and Test-LwgModule all agree that it is off, and it
  injected into the worker anyway. The same bytes with the two top-level keys in
  the shipped order printed NOTHING. That is the whole defect: a raw-text scanner
  whose correctness depends on which of two sibling keys appears first in a file
  operators are invited to hand-edit, with nothing anywhere asserting that order.

  So the claim these cases defend is:

      THE FAST SCAN ANSWERS THE GLOBAL FLAG, WHATEVER ORDER THE TOP-LEVEL KEYS
      APPEAR IN, AND IT AGREES WITH THE SLOW PATH IT EXISTS TO AVOID.

  ---------------------------------------------------------------------------
  AND SINCE 6 SEPTEMBER 2026, A SECOND CLAIM: THE DISPATCH RECORD - slice 0 of
  #166, tracked on #311
  ---------------------------------------------------------------------------
  lib\subagent_start.ps1 used to write NOTHING on its happy path. It now appends
  ONE line to health.jsonl per dispatch, gated on the effort_ledger flag - the
  START half of a record whose STOP half lib\supervisor.ps1:825-830 has always
  written. Six cases below are about that row and nothing else:

      Test-TheDispatchRecordLands
      Test-FailureCaptureOffWritesNoRowAndStillInjects
      Test-ContextInjectionOffStillWritesTheRow
      Test-GarbageStdinWritesNoRowAndStillExitsZero
      Test-ANonAsciiAgentTypeIsEscapedToPureAscii
      Test-TheStateDirectoryIsNeverGuessed

  All six are RED at 97f0697, which is the easy baseline: nothing wrote that file
  from this path at all, so every positive half fails outright. The two cases
  whose SUBJECT is a silence carry their positive control inside the same case
  for the reason the rule above gives - a bare negative was already green.

  The claim they defend:

      ONE ROW PER DISPATCH, IN New-Record's ENVELOPE, GATED ON effort_ledger
      AND NOT ON THIS FILE'S OWN MODULE, WRITTEN TO THE STATE DIRECTORY THE REST
      OF THE PLUGIN RESOLVES AND NEVER TO A GUESS.

  What they deliberately do NOT cover: the COST of the row. This suite asserts on
  answers, not on milliseconds - see WHAT IS DELIBERATELY NOT COVERED below. The
  three-leg measurement is recorded in lib\subagent_start.ps1's own header and on
  the pull request, and nothing here re-measures it.

  ---------------------------------------------------------------------------
  THE RULE EVERY CASE HERE FOLLOWS
  ---------------------------------------------------------------------------
  NO BARE NEGATIVE STANDS ALONE. "It did not inject" is satisfied by a hook that
  crashed, by a missing facts file, and by a fixture that never reached the
  branch. So every case that asserts silence runs the SAME fixture a second time
  with ONE BIT changed - the global `context_injection` value - and requires the
  injection to appear. The pair is the evidence; neither half is.

  ---------------------------------------------------------------------------
  WHICH CASES ARE REGRESSION CASES AND WHICH ARE NOT - read before trusting a
  green run, and written down 3 August 2026 after review found the distinction
  was being carried by nothing
  ---------------------------------------------------------------------------
  Two of the twenty cases below FAIL on the depth-blind scanner and are the
  regression cases for it:

      Test-ReposBeforeModulesReadsTheGlobalFlag
      Test-DecoyModulesUnderANonReposKeyIsIgnored

  The other eighteen are green on the depth defect as well, and each is here for
  its own reason rather than as evidence about depth - with one exception, added
  4 September 2026, which is a regression case for a DIFFERENT defect:

      Test-ANonAsciiCwdStillResolvesThePerRepoOverride   Red on #269. The hook
          read its stdin through [Console]::In, so a cwd carrying one non-ASCII
          character named a directory that does not exist, no slug resolved, and
          every `repos` entry fell through to the global default. It is also the
          case that closes the blind spot the entry below names.

      Test-ShippedOrderReadsTheGlobalFlag   A CONTROL. It is what says a depth
          rule did not break the key order that always worked. It cannot detect
          depth-blindness and is not meant to.
      Test-NoConfigFailsOpen   A CONTRACT case, and VACUOUS with respect to the
          depth defect: with no config.json the scanner never runs. It pins
          fail-open, which a depth rule returning $null too often would break.
      Test-FastScanAgreesWithTheSlowPathOnTheShippedConfig   A CANARY, not a
          regression case. On the shipped key order `modules` (offset 12508)
          precedes `repos` (20506), so this configuration cannot exhibit the
          defect at all. What it catches is the fast scan and Test-LwgModule
          drifting apart, and it starts catching depth problems the day
          config.json's key order changes.
      Test-PerRepoOverrideStillEscalates   Pins that the escalation path RUNS
          without throwing and lands on the global answer for a dispatch that
          resolves no repo. It CANNOT distinguish escalation-taken from
          escalation-skipped: for a no-repo dispatch both paths return the
          global value, and nothing in this sandbox can resolve a repo slug
          without a real checkout with a matching remote. Stated rather than
          implied, because a case that looks like it pins the escalation and
          does not is worse than no case.

  ---------------------------------------------------------------------------
  HOW A CASE IS RUN
  ---------------------------------------------------------------------------
  In a real child process, against the real lib\subagent_start.ps1, because that
  is the file hooks\hooks.json registers:

      '{}' | powershell -NoProfile -ExecutionPolicy Bypass -File lib\subagent_start.ps1

  with $env:CLAUDE_PLUGIN_ROOT pointed at a throwaway root holding the fixture
  config.json and a fixture context\worker_facts.md. The payload is piped because
  the hook drains stdin with [Console]::In.ReadToEnd(); a child that inherited an
  open stdin would block rather than fail.

  ---------------------------------------------------------------------------
  TEST SAFETY - read before adding a case
  ---------------------------------------------------------------------------
    * Every scratch path is BUILT AT RUNTIME from [IO.Path]::GetTempPath(). No
      path here names a machine, an account or an install location, which is
      also what tests\portability_scan.ps1 holds every tracked file to.
    * $env:CLAUDE_PLUGIN_DATA is redirected for EVERY child invocation, without
      exception. lib\subagent_start.ps1's catch path dot-sources lib\common.ps1
      and calls Write-LwgEvent, which appends to the RESOLVED state directory -
      so a case that forgot the redirect would write into the operator's own
      ~\.claude\plugins\data on every failure. Invoke-SubagentStart does it
      unconditionally for that reason; do not add a path that calls the hook
      directly.
    * Nothing here deletes anything outside the scratch tree, which is removed
      in a finally.

  ---------------------------------------------------------------------------
  WHAT IS DELIBERATELY NOT COVERED, so a green run is not read as more
  ---------------------------------------------------------------------------
  * THE ESCALATION'S SLUG RESOLUTION - NARROWED 4 September 2026, not removed.
    Case Test-PerRepoOverrideStillEscalates proves the escalation still runs and
    still lands on the right answer for a dispatch with no repo in its payload,
    and it says in its own docstring that it cannot tell escalation-taken from
    escalation-skipped. Test-ANonAsciiCwdStillResolvesThePerRepoOverride now
    builds the checkout that case said this sandbox does not build, so ONE slug
    resolution is pinned end to end: a hand-built .git naming acme/example-repo,
    a payload whose cwd is its work tree, and a per-repo override that must win
    over the global flag. What is still not re-tested here is Get-LwgRepo's
    behaviour in general - the walk limit, worktrees, multiple remotes.
  * THE CONTENT AND FORMATTING OF worker_facts.md. Every fixture uses an
    invented one-line file; the comment-stripping and the 2000-character ceiling
    are lib\subagent_start.ps1's and have no case here.
  * THE PERFORMANCE BUDGET. This suite asserts on ANSWERS, not on milliseconds.
    The header of lib\subagent_start.ps1 carries the measured numbers; nothing
    here re-measures them, so a green run is not evidence the hook is still fast.

  ---------------------------------------------------------------------------
  EXIT CODES - a CI job reads these and nothing else
  ---------------------------------------------------------------------------
      0  every case passed
      1  at least one case FAILED
      2  the suite ABORTED - it could not set up or could not run a case, so
         nothing was established either way. Zero cases run is an abort, never
         an empty-set pass.
#>
[CmdletBinding()]
param(
    # The PLUGIN PAYLOAD root - lw-watchtower\ under this file's parent, not the
    # repository root, which is what this parameter meant before the restructure, correct for a run from anywhere
    # as long as this file stays in tests\.
    [string]$Root
)

$ErrorActionPreference = 'Stop'

# THE PAYLOAD ROOT, WHICH IS NO LONGER THE REPOSITORY ROOT. `Split-Path -Parent
# $PSScriptRoot` is the parent of tests\, and tests\ stayed at the repository
# root while the shipped plugin moved under lw-watchtower/. Everything this
# suite composes off $Root - bin\, lib\, config.json, statusline\ - is payload,
# so $Root is the payload root and the default says so in one place rather than
# in every Join-Path below it.
#
# WHY THE DEFAULT AND NOT A -Root FROM CI. Neither .github\workflows\ci.yml nor
# tests\doc_claims.ps1's sibling runner passes -Root at any invocation, so a
# suite's default is the only value it ever gets on either route. Putting the
# knowledge here is the only place it can be put.
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Join-Path (Split-Path -Parent $PSScriptRoot) 'lw-watchtower' }

$HookPath   = Join-Path $Root 'lib\subagent_start.ps1'
$CommonPath = Join-Path $Root 'lib\common.ps1'

# The module this hook is, spelled here exactly once. Deliberately NOT read out
# of the script under test: a case that derives the subject from the specimen
# cannot notice the subject changing.
$ModuleName = 'context_injection'

# The one line every fixture facts file holds. Invented, and distinctive enough
# that finding it in the hook's stdout is proof the injection came from the
# fixture rather than from the operator's real install.
$FactLine = 'lwg-subagent-scan-fixture-fact'

$script:Pass    = 0
$script:Results = New-Object System.Collections.ArrayList
$script:Aborted = ''
$script:Work    = ''

function Add-Result {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    if ($Ok) { $script:Pass++ }
    [void]$script:Results.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail })
    if (-not $Ok) {
        Write-Output ("  FAIL  {0}" -f $Name)
        Write-Output ("        {0}" -f $Detail)
    } elseif ($VerbosePreference -ne 'SilentlyContinue') {
        Write-Output ("  ok    {0}" -f $Name)
    }
}

# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

function New-CaseRoot {
    <#
      A throwaway plugin root for one case:

        <work>\<tag>\root\context\worker_facts.md   the thing that gets injected
        <work>\<tag>\data\                          the redirected state dir
        <work>\<tag>\home\                          the redirected CLAUDE_CONFIG_DIR,
                                                    used ONLY by -NoStateDir cases

      config.json is NOT written here - each case says what its config looks
      like, because the config is the subject.
    #>
    param([string]$Tag)

    $dir  = Join-Path $script:Work $Tag
    $root = Join-Path $dir 'root'
    $ctx  = Join-Path $root 'context'
    $data = Join-Path $dir 'data'
    $home_ = Join-Path $dir 'home'
    foreach ($p in @($ctx, $data, $home_)) { [void][IO.Directory]::CreateDirectory($p) }
    [IO.File]::WriteAllText((Join-Path $ctx 'worker_facts.md'),
                            "# a comment line the hook must drop`r`n$FactLine`r`n",
                            [Text.UTF8Encoding]::new($false))
    return @{ dir = $dir; root = $root; data = $data; home = $home_ }
}

function Invoke-SubagentStart {
    <#
      One real child run of lib\subagent_start.ps1 against a case root.

      $env:CLAUDE_PLUGIN_ROOT points the hook's own Get-LwgRootLocal at the
      fixture; $env:CLAUDE_PLUGIN_DATA is redirected UNCONDITIONALLY - see TEST
      SAFETY in the header - and both are restored in a finally.

      -Config writes config.json verbatim, WITHOUT ConvertTo-Json, because the
      subject of this suite is the ORDER OF THE KEYS IN THE FILE TEXT and a
      helper that round-tripped through the JSON writer could not express it.
      Omitting -Config leaves the root with no config.json at all, which is one
      of the cases.

      -Override writes config.override.json into the redirected STATE DIRECTORY,
      under the same rule and for the same reason - #11. That file is the one
      the operator's own ON/OFF choices go to, and the hook reads it merged over
      config.json. Omitting it deletes any left by a previous run in the same
      tree, so a case that says "no override" gets one.

      PRESENCE IS TESTED WITH $PSBoundParameters AND NOT AGAINST $null, and that
      is a correction rather than a style choice. PowerShell gives an unpassed
      [string] parameter the value '' - never $null - so `if ($null -ne $Config)`
      was ALWAYS true, and the case that says "no config.json at all" was in fact
      run against a ZERO-BYTE one. It passed, and for a near-enough reason (the
      hook treats unreadable and absent alike, by design), but it was not the
      fixture the case names. The same trap cost QA-C4 two timing runs on #11
      when empty override files silently made the gate's fast exit unreachable.

      Returns @{ code; out } where `out` is the whole stdout as one string.
    #>
    param(
        [Parameter(Mandatory = $true)][hashtable]$Tree,
        [string]$Config,
        [string]$Override
    )

    $cfgPath = Join-Path $Tree.root 'config.json'
    if ($PSBoundParameters.ContainsKey('Config')) {
        [IO.File]::WriteAllText($cfgPath, $Config, [Text.UTF8Encoding]::new($false))
    } elseif ([IO.File]::Exists($cfgPath)) {
        [IO.File]::Delete($cfgPath)
    }

    $ovPath = Join-Path $Tree.data 'config.override.json'
    if ($PSBoundParameters.ContainsKey('Override')) {
        [IO.File]::WriteAllText($ovPath, $Override, [Text.UTF8Encoding]::new($false))
    } elseif ([IO.File]::Exists($ovPath)) {
        [IO.File]::Delete($ovPath)
    }

    $saveRoot = $env:CLAUDE_PLUGIN_ROOT
    $saveData = $env:CLAUDE_PLUGIN_DATA
    try {
        $env:CLAUDE_PLUGIN_ROOT = $Tree.root
        $env:CLAUDE_PLUGIN_DATA = $Tree.data
        $lines = '{}' | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $HookPath
        $code  = if ($null -eq $LASTEXITCODE) { 255 } else { $LASTEXITCODE }
        return @{ code = $code; out = (@($lines) -join '') }
    } finally {
        if ($null -eq $saveRoot) {
            Remove-Item -LiteralPath 'Env:\CLAUDE_PLUGIN_ROOT' -ErrorAction SilentlyContinue
        } else { $env:CLAUDE_PLUGIN_ROOT = $saveRoot }
        if ($null -eq $saveData) {
            Remove-Item -LiteralPath 'Env:\CLAUDE_PLUGIN_DATA' -ErrorAction SilentlyContinue
        } else { $env:CLAUDE_PLUGIN_DATA = $saveData }
    }
}

function Invoke-SubagentStartWithPayload {
    <#
      One real child run of lib\subagent_start.ps1 with a PAYLOAD THAT REACHES
      IT, spawned the way Claude Code spawns a hook.

      WHY THIS EXISTS BESIDE Invoke-SubagentStart, WHICH IS OTHERWISE THE RIGHT
      HARNESS. That one runs `'{}' | & powershell.exe -File <hook>`, and a
      PowerShell OBJECT PIPE does not reach the child's standard input at all -
      this repository says so in three places. It has never mattered, because
      every case above answers the GLOBAL flag and the fast path never looks at
      the payload. The moment a case is about what the payload CONTAINS, that
      harness cannot express it.

      Two things are therefore different, and both are load-bearing:

        * the payload is written to StandardInput.BaseStream as raw UTF-8 bytes,
          no BOM and no trailing newline, which is what Claude Code writes;
        * CreateNoWindow is set - what Node's `windowsHide: true` does - so the
          child gets its OWN console at the system OEM code page rather than
          inheriting the terminal this suite was started from. A hook's
          [Console]::InputEncoding IS the console's input code page, so without
          this the case would test whatever code page the developer's terminal
          happens to sit at, and on one at 65001 it would pass at the baseline
          having proved nothing.

      -Override writes config.override.json into the redirected state directory,
      under the same verbatim rule Invoke-SubagentStart uses and for the same
      reason (#11). Omitting it DELETES any file a previous run in the same tree
      left, so a case that says "no override" gets one.

      -NoStateDir REMOVES CLAUDE_PLUGIN_DATA from the child's environment rather
      than blanking it, and points CLAUDE_CONFIG_DIR at $Tree.home instead. That
      is the one condition under which lib\subagent_start.ps1 may not compose the
      state directory itself, and the case that uses it is about where the row
      lands. It is REMOVED and not set to '' because an empty variable is a
      different state from an absent one for [Environment]::GetEnvironmentVariable
      and this suite must exercise the absent one.

      TEST SAFETY: -NoStateDir still writes nothing outside the scratch tree.
      Get-LwgClaudeHomeInfo reads CLAUDE_CONFIG_DIR first and USERPROFILE only
      when that is empty, so redirecting the former keeps the whole discovery
      inside $Tree.home. A case that passed -NoStateDir without it would append
      to the operator's own ~\.claude\plugins\data, which is what the TEST SAFETY
      section in this header forbids.

      Returns @{ code; out }, the shape Invoke-SubagentStart returns.
    #>
    param(
        [Parameter(Mandatory = $true)][hashtable]$Tree,
        [Parameter(Mandatory = $true)][string]$Config,
        [Parameter(Mandatory = $true)][string]$Payload,
        [string]$Override,
        [switch]$NoStateDir
    )

    [IO.File]::WriteAllText((Join-Path $Tree.root 'config.json'), $Config, [Text.UTF8Encoding]::new($false))
    $ovPath = Join-Path $Tree.data 'config.override.json'
    if ($PSBoundParameters.ContainsKey('Override')) {
        [IO.File]::WriteAllText($ovPath, $Override, [Text.UTF8Encoding]::new($false))
    } elseif ([IO.File]::Exists($ovPath)) {
        [IO.File]::Delete($ovPath)
    }

    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName  = 'powershell'
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $HookPath + '"'
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $psi.StandardErrorEncoding  = New-Object Text.UTF8Encoding($false)
    $psi.CreateNoWindow         = $true
    $psi.EnvironmentVariables['CLAUDE_PLUGIN_ROOT'] = $Tree.root
    if ($NoStateDir) {
        [void]$psi.EnvironmentVariables.Remove('CLAUDE_PLUGIN_DATA')
        $psi.EnvironmentVariables['CLAUDE_CONFIG_DIR'] = $Tree.home
    } else {
        $psi.EnvironmentVariables['CLAUDE_PLUGIN_DATA'] = $Tree.data
    }

    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Payload)
    $out = ''; $code = 255
    $p = [Diagnostics.Process]::Start($psi)
    try {
        $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $p.StandardInput.BaseStream.Flush()
        $p.StandardInput.Close()
        $out = $p.StandardOutput.ReadToEnd()
        [void]$p.StandardError.ReadToEnd()
        $p.WaitForExit()
        $code = $p.ExitCode
    } finally { $p.Dispose() }
    return @{ code = $code; out = $out }
}

function New-FixtureWorkTree {
    <#
      A directory Get-LwgRepoInfo resolves to $Slug: a .git holding one `config`
      with one [remote "origin"] url, and nothing else. That is the entire input
      that function takes - walk up for .git, parse the remote urls out of
      `config` - so a fabricated tree is the same evidence a real clone gives
      it, with no network and no git binary. Returns the work-tree path.

      $LeafName is a parameter because one caller needs a leaf carrying
      characters that are not ASCII, and that is the whole subject of the case
      that asks for it.
    #>
    param([string]$Base, [string]$LeafName, [string]$Slug)

    $wt = Join-Path $Base $LeafName
    $gd = Join-Path $wt '.git'
    [void][IO.Directory]::CreateDirectory($gd)
    [IO.File]::WriteAllLines((Join-Path $gd 'config'), @(
        '[core]',
        '    repositoryformatversion = 0',
        '[remote "origin"]',
        "    url = https://github.com/$Slug.git",
        '    fetch = +refs/heads/*:refs/remotes/origin/*'), [Text.ASCIIEncoding]::new())
    return $wt
}

function Test-Injected {
    <#
      Did this run inject? Both halves are checked rather than just the envelope
      name: an envelope carrying somebody else's text would mean the fixture was
      not what was read.
    #>
    param([string]$Out)
    return ($Out -like '*"hookEventName":"SubagentStart"*') -and ($Out -like "*$FactLine*")
}

# ---------------------------------------------------------------------------
# THE DISPATCH RECORD - helpers (slice 0 of #166, tracked on #311)
# ---------------------------------------------------------------------------

# The two flags every ledger case sets, spelled once. effort_ledger is the
# module the ROW is gated on; context_injection is the module this FILE is. They
# are deliberately independent, and three of the six cases below exist to say so.
$LedgerModule = 'effort_ledger'

# The fixture payload's fields, invented and distinctive, so finding them in
# health.jsonl is proof the row came from this dispatch and not from anywhere
# else. agent_id is what supervisor.ps1:403 keys on; agent_type is what #168's
# black tier will render; session is what every reader filters by.
$LedgerSession   = 'lwg-scan-session-0001'
$LedgerAgentId   = 'lwg-scan-agent-abcdef0123'
$LedgerAgentType = 'lwg-scan-fixture-type'

function New-LedgerConfig {
    <#
      A config.json carrying BOTH flags and nothing else, written verbatim for
      the same reason every other fixture here is: the subject is the file text.
      The shipped key order (`modules` at depth 1, no `repos`) keeps these cases
      on the FAST path, so what they measure is the fast path's own answer.
    #>
    param([bool]$FailureCapture, [bool]$ContextInjection)
    $fc = if ($FailureCapture)   { 'true' } else { 'false' }
    $ci = if ($ContextInjection) { 'true' } else { 'false' }
    return '{"modules":{"' + $LedgerModule + '":' + $fc + ',"' + $ModuleName + '":' + $ci + '}}'
}

function New-LedgerPayload {
    <#
      A SubagentStart payload of the shape the CLI writes. cwd is present and
      carries a path, because the row must NOT contain it: redaction cannot run
      on this path (the regex engine's first use costs more than everything else
      the hook does), and cwd is the one field carrying an operator name and a
      clone root. Its ABSENCE from the row is asserted, not assumed.
    #>
    param([string]$AgentType = $LedgerAgentType, [string]$SessionId = $LedgerSession)
    return '{"session_id":"' + $SessionId + '","agent_id":"' + $LedgerAgentId +
           '","agent_type":"' + $AgentType + '","cwd":"C:\\lwg-scan-fixture\\nowhere"}'
}

function Get-LedgerLines {
    <#
      Every non-blank line of health.jsonl under $Dir, decoded as UTF-8 without
      a BOM - the encoding every writer in this plugin emits and the encoding
      Get-Content in Windows PowerShell 5.1 does NOT assume. Returns an EMPTY
      ARRAY when the file does not exist, which is the "no row" answer.
    #>
    param([string]$Dir)
    $p = Join-Path $Dir 'health.jsonl'
    if (-not [IO.File]::Exists($p)) { return @() }
    $raw = [Text.UTF8Encoding]::new($false).GetString([IO.File]::ReadAllBytes($p))
    return @($raw.Split([char]10) | ForEach-Object { $_.TrimEnd([char]13) } | Where-Object { $_.Trim() -ne '' })
}

function Get-LedgerStartRows {
    <#
      The SubagentStart rows among them, PARSED WITH ConvertFrom-Json, which is
      deliberate: that is the parser all four readers of this file use
      (supervisor.ps1:403, gate_send.ps1:330, Get-LwgHealthRecords,
      statusline.ps1:942), so parsing the row here proves reader compatibility
      rather than asserting it. A line that will not parse is NOT silently
      dropped - it is returned as $null so the caller can fail on it.
    #>
    param([string[]]$Lines)
    $out = @()
    foreach ($l in $Lines) {
        $o = $null
        try { $o = $l | ConvertFrom-Json } catch { $o = $null }
        if ($null -eq $o) { $out += $null; continue }
        if ([string]$o.event -eq 'SubagentStart') { $out += $o }
    }
    return $out
}

function New-OrderedConfig {
    <#
      The fixture, in one of the two top-level key orders, with the global
      `context_injection` set either way.

      The per-repo block names a DIFFERENT module on purpose. That is the half
      of the defect the escalation cannot save: a per-repo `modules` block
      naming `context_injection` makes Get-LwgJsonBool find the key inside the
      `repos` span, which sets $escalate and sends the run down the exact path,
      masking the misread. Naming `docs_coupling` instead leaves $escalate false,
      so the misread global answer is the one that is used.

      The $comment paragraph is not decoration. config.json is more prose than
      data and its comment fields carry braces and escaped quotes; the brace
      matcher is documented as string-aware, and a fixture with no such text
      would not exercise that.
    #>
    param([switch]$ReposFirst, [bool]$Enabled)

    $modules = '  "modules": { "' + $ModuleName + '": ' + $(if ($Enabled) { 'true' } else { 'false' }) + ', "git_hygiene": true }'
    $repos   = '  "repos": { "acme/example-repo": { "modules": { "docs_coupling": false } } }'
    $comment = '  "$comment": "Edit this file; no reinstall is needed. A brace { and a quote \" live here on purpose."'
    $body = if ($ReposFirst) { @($comment, $repos, $modules) } else { @($comment, $modules, $repos) }
    return "{`r`n" + ($body -join ",`r`n") + "`r`n}`r`n"
}

# ---------------------------------------------------------------------------
# CASES
# ---------------------------------------------------------------------------

function Test-ReposBeforeModulesReadsTheGlobalFlag {
    <#
      THE HEADLINE CASE. `repos` before `modules` in the file text, with a
      per-repo `modules` block that names a different module, and the GLOBAL
      block carrying the answer.

      Get-LwgJsonObjectSpan took the first `"modules":` in document order at any
      depth, so the span it returned was `{ "docs_coupling": false }` - four
      levels down inside `repos`. Get-LwgJsonBool found no context_injection in
      it, $enabled kept its fail-open default of $true, the escalation did not
      fire because the `repos` span holds no context_injection either, and every
      subagent dispatch was handed context\worker_facts.md while the module was
      switched off.

      RUN TWICE, one bit apart. The two configs differ only in the global
      `context_injection` value, so `false` printing nothing is earned against
      `true` printing the injection rather than against nothing at all.
    #>
    $t = New-CaseRoot 'repos-first'

    $off = Invoke-SubagentStart -Tree $t -Config (New-OrderedConfig -ReposFirst -Enabled $false)
    $on  = Invoke-SubagentStart -Tree $t -Config (New-OrderedConfig -ReposFirst -Enabled $true)

    $bad = @()
    if ($off.code -ne 0)         { $bad += "the off run exited $($off.code); this hook must always exit 0" }
    if ($on.code  -ne 0)         { $bad += "the on run exited $($on.code); this hook must always exit 0" }
    if (Test-Injected $off.out)  { $bad += "IT INJECTED WHILE THE GLOBAL FLAG IS false - the per-repo modules block was read as the global one: $($off.out)" }
    if ($off.out -ne '')         { $bad += "the off run printed something: $($off.out)" }
    if (-not (Test-Injected $on.out)) { $bad += "the on run did not inject, so the off run's silence proves nothing: $($on.out)" }

    Add-Result -Name 'repos before modules: the GLOBAL context_injection flag is what the fast scan answers' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | off exit $($off.code), on exit $($on.code)")
}

function Test-DecoyModulesUnderANonReposKeyIsIgnored {
    <#
      THE STRONGER FORM OF THE DEFECT, and the one where NOTHING can catch the
      misread afterwards. The case above puts the decoy under `repos`, which at
      least gives the escalation a chance to fire when the per-repo block happens
      to name this module. Here the decoy sits under an ordinary top-level key
      that is not `repos` at all - a `defaults` block, at depth 2 - so:

        * the depth-blind scanner takes it as the global `modules` block;
        * `repos` is ABSENT, so Get-LwgJsonObjectSpan returns $null for it, the
          escalation cannot fire under any circumstances, and the fast scan's
          answer is final.

      There is no second chance in this shape. It is also the case that says the
      fix is a DEPTH rule rather than a special case for `repos` - a scanner
      patched only to skip the `repos` span would still read `defaults.modules`
      as the global block and pass the case above while failing this one.

      Run twice, one bit apart, for the reason in the header.
    #>
    $t = New-CaseRoot 'decoy-non-repos'

    $tmpl = @'
{
  "defaults": { "modules": { "__MOD__": __DECOY__ } },
  "modules": { "__MOD__": __GLOBAL__, "git_hygiene": true }
}
'@
    $off = Invoke-SubagentStart -Tree $t -Config ($tmpl.Replace('__MOD__', $ModuleName).Replace('__DECOY__', 'true').Replace('__GLOBAL__', 'false'))
    $on  = Invoke-SubagentStart -Tree $t -Config ($tmpl.Replace('__MOD__', $ModuleName).Replace('__DECOY__', 'false').Replace('__GLOBAL__', 'true'))

    $bad = @()
    if ($off.code -ne 0)              { $bad += "the off run exited $($off.code); this hook must always exit 0" }
    if ($on.code  -ne 0)              { $bad += "the on run exited $($on.code); this hook must always exit 0" }
    if (Test-Injected $off.out)       { $bad += "IT INJECTED WHILE THE GLOBAL FLAG IS false - a nested modules block under a key that is not repos was read as the global one, and with no repos block nothing can escalate to correct it: $($off.out)" }
    if ($off.out -ne '')              { $bad += "the off run printed something: $($off.out)" }
    if (-not (Test-Injected $on.out)) { $bad += "the on run did not inject, so the off run's silence proves nothing: $($on.out)" }

    Add-Result -Name 'a nested modules block under a key that is NOT repos is ignored, and nothing can escalate to correct it' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | off exit $($off.code), on exit $($on.code)")
}

function Test-ShippedOrderReadsTheGlobalFlag {
    <#
      THE CONTROL, and the no-regression half. Byte-for-byte the same fixture
      with the two top-level keys in the order the shipped config.json uses -
      `modules` before `repos`. This order was always answered correctly, so
      this case is what says a depth rule did not break the path that worked.

      Run twice, one bit apart, for the same reason as the case above.
    #>
    $t = New-CaseRoot 'modules-first'

    $off = Invoke-SubagentStart -Tree $t -Config (New-OrderedConfig -Enabled $false)
    $on  = Invoke-SubagentStart -Tree $t -Config (New-OrderedConfig -Enabled $true)

    $bad = @()
    if ($off.code -ne 0)              { $bad += "the off run exited $($off.code); this hook must always exit 0" }
    if ($on.code  -ne 0)              { $bad += "the on run exited $($on.code); this hook must always exit 0" }
    if (Test-Injected $off.out)       { $bad += "it injected while the global flag is false: $($off.out)" }
    if ($off.out -ne '')              { $bad += "the off run printed something: $($off.out)" }
    if (-not (Test-Injected $on.out)) { $bad += "the on run did not inject, so the shipped order no longer resolves the flag at all: $($on.out)" }

    Add-Result -Name 'shipped order (modules before repos): the global flag is still answered correctly' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | off exit $($off.code), on exit $($on.code)")
}

function Test-PerRepoOverrideStillEscalates {
    <#
      THE CONTRACT THE DEPTH RULE MUST NOT COST. lib\subagent_start.ps1:82-89
      promises that a per-repo override for THIS module sends the run down the
      full path - dot-source common.ps1, parse the payload, resolve the slug,
      ask Test-LwgModule - rather than being silently applied globally or
      silently ignored.

      The fixture puts `repos` first AND names context_injection inside it, which
      is the shape that sets $escalate. The dispatch carries an empty payload, so
      no repo resolves and Test-LwgModule falls back to the global value - which
      is `false` here while the per-repo override says `true`. So the assertion
      is that the GLOBAL answer wins for a dispatch with no repo, and that the
      run still exits 0 after taking a path that dot-sources common.ps1.

      Paired with an on-run for the same reason as every other case here: the
      global bit is flipped and the injection must appear.

      WHAT THIS CANNOT SEE, stated rather than implied. It cannot tell
      escalation-TAKEN from escalation-SKIPPED. For a dispatch that resolves no
      repo, Test-LwgModule returns the global value - which is the same answer
      the fast scan gives on its own - so both paths produce identical stdout.
      Distinguishing them needs a payload that resolves to a real slug, which
      needs a checkout with a matching remote, which is not something this
      sandbox builds. So this pins that the escalation RUNS WITHOUT THROWING
      and lands on the global answer; it does not pin that it ran.
    #>
    $t = New-CaseRoot 'per-repo-override'

    $tmpl = @'
{
  "repos": { "acme/example-repo": { "modules": { "__MOD__": true } } },
  "modules": { "__MOD__": __GLOBAL__ }
}
'@
    $off = Invoke-SubagentStart -Tree $t -Config ($tmpl.Replace('__MOD__', $ModuleName).Replace('__GLOBAL__', 'false'))
    $on  = Invoke-SubagentStart -Tree $t -Config ($tmpl.Replace('__MOD__', $ModuleName).Replace('__GLOBAL__', 'true'))

    $bad = @()
    if ($off.code -ne 0)              { $bad += "the off run exited $($off.code); this hook must always exit 0 even through the escalation" }
    if ($on.code  -ne 0)              { $bad += "the on run exited $($on.code); this hook must always exit 0 even through the escalation" }
    if (Test-Injected $off.out)       { $bad += "a per-repo override was applied globally to a dispatch that resolved no repo: $($off.out)" }
    if (-not (Test-Injected $on.out)) { $bad += "the on run did not inject, so the escalation path answers nothing at all: $($on.out)" }

    Add-Result -Name 'a per-repo override for this module escalates, and a dispatch with no repo gets the global answer' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | off exit $($off.code), on exit $($on.code)")
}

function Test-ANonAsciiCwdStillResolvesThePerRepoOverride {
    <#
      #269, AND THE BLIND SPOT THE CASE ABOVE NAMES.

      That case ends by saying what it cannot see: it "cannot tell
      escalation-TAKEN from escalation-SKIPPED", because for a dispatch that
      resolves no repo the escalation lands on the same global answer the fast
      scan gives, and "distinguishing them needs a payload that resolves to a
      real slug, which needs a checkout with a matching remote, which is not
      something this sandbox builds". It builds one now, and the two questions
      turn out to be the same question.

      THE DEFECT. lib\subagent_start.ps1 drains its own stdin before common.ps1
      exists, and it read that pipe through [Console]::In - whose encoding is
      the CONSOLE's input code page, IBM437 in a child spawned the way Claude
      Code spawns a hook, never the UTF-8 the payload is written in. The one
      payload field this hook uses is `cwd`, and it uses it for exactly one
      thing: resolving the repo slug that selects a per-repo override. So on any
      machine whose project path holds one non-ASCII character, cwd named a
      directory that does not exist, the walk for .git found nothing, no slug
      resolved, and EVERY `repos` entry in config.json fell through to the
      global default - silently, with the hook still exiting 0 and still
      injecting. docs/configuration.md says of that block, about an earlier and
      different cause, that it "was wrong once in a way that made this entire
      block apply to nothing".

      THE FIXTURE. A real work tree with a hand-built .git naming
      acme/example-repo, at a leaf carrying a Latin-1 umlaut and two CJK
      characters. config.json turns context_injection ON globally and OFF for
      that slug. So:

        slug resolves      -> per-repo OFF wins -> NO injection
        slug does not      -> global ON wins    -> injection

      and the assertion is the absence, which is why the ASCII control beside it
      is not optional: a bare negative is satisfied by a hook that crashed, and
      this file's header makes that rule explicit. The control is the identical
      config against an identical repo at an ASCII path, and it must also NOT
      inject - proving the per-repo mechanism itself works and that the only
      thing separating the two runs is the encoding of one payload field.

      RED-FIRST: the non-ASCII half FAILS at 6aebcd6 and at 8f1b0c0 - it injects,
      because the override applies to nothing. The ASCII control is green at
      both, which is what makes it a control.
    #>
    $t = New-CaseRoot 'nonascii-cwd'

    $tmpl = @'
{
  "repos": { "acme/example-repo": { "modules": { "__MOD__": false } } },
  "modules": { "__MOD__": true }
}
'@
    $cfg = $tmpl.Replace('__MOD__', $ModuleName)

    # Built from code points rather than typed, so this cannot be defeated by
    # the file being saved in the wrong encoding one day - the class of defect
    # under test.
    $leaf   = 'w' + [char]0x00F6 + 'rk-' + [char]0x65E5 + [char]0x672C
    $wtWide = New-FixtureWorkTree -Base $t.dir -LeafName $leaf         -Slug 'acme/example-repo'
    $wtAscii= New-FixtureWorkTree -Base $t.dir -LeafName 'work-ascii'  -Slug 'acme/example-repo'

    $mk = { param($cwd) '{"session_id":"lwg-nonascii","cwd":"' + ($cwd -replace '\\', '\\\\') + '","agent_type":"lwg-fixture"}' }

    $wide  = Invoke-SubagentStartWithPayload -Tree $t -Config $cfg -Payload (& $mk $wtWide)
    $ascii = Invoke-SubagentStartWithPayload -Tree $t -Config $cfg -Payload (& $mk $wtAscii)

    $bad = @()
    if ($ascii.code -ne 0) { $bad += "the ASCII control exited $($ascii.code); this hook must always exit 0" }
    if ($wide.code  -ne 0) { $bad += "the non-ASCII run exited $($wide.code); this hook must always exit 0" }
    if (Test-Injected $ascii.out) {
        $bad += ('CONTROL FAILED: the per-repo override did not apply even at an ASCII path, so the non-ASCII half ' +
                 'below establishes nothing - the fixture, not the encoding, is what needs fixing')
    }
    if (Test-Injected $wide.out) {
        $bad += ('REGRESSION (#269): the per-repo override applied at an ASCII path and NOT at a path carrying one ' +
                 'non-ASCII character. cwd is read at the console code page instead of as UTF-8, so it names a ' +
                 'directory that does not exist, no .git is found, no slug resolves, and every repos entry in ' +
                 'config.json falls through to the global default - silently, exit 0, still injecting')
    }

    Add-Result -Name 'a cwd that is not ASCII still resolves its per-repo override (#269)' `
               -Ok ($bad.Count -eq 0) `
               -Detail (($bad -join '; ') + " | non-ASCII exit $($wide.code) injected $(Test-Injected $wide.out); ASCII control exit $($ascii.code) injected $(Test-Injected $ascii.out)")
}

function Test-NoConfigFailsOpen {
    <#
      NO config.json AT ALL. The file's header states the rule it shares with
      Get-LwgConfig and Test-LwgModule: a missing or unreadable config leaves
      every module ON, because a governance layer that switches itself off
      because it could not read its own settings is the failure mode.

      This is the fail-open half of the same branch the cases above exercise from
      the other side, and it is what would catch a depth rule that returned $null
      so often that the flag stopped resolving anywhere.

      NOT A REGRESSION CASE FOR THE DEPTH DEFECT, and the header says so beside
      the other two of its kind: with no config.json the scanner is never called,
      so this is green on the depth-blind version as well. It is here for the
      fail-open contract only.
    #>
    $t = New-CaseRoot 'no-config'

    $r = Invoke-SubagentStart -Tree $t

    $bad = @()
    if ($r.code -ne 0)              { $bad += "exited $($r.code); this hook must always exit 0" }
    if (-not (Test-Injected $r.out)) { $bad += "no config.json left the module OFF - it must fail OPEN: $($r.out)" }

    Add-Result -Name 'no config.json: the module fails OPEN and still injects' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | exit $($r.code)")
}

function Test-TheOperatorOverrideSwitchesTheModuleOff {
    <#
      #11, AND THE MODULE /lw-watchtower:config USED TO REFUSE TO WRITE.

      The heading said "THE ONE MODULE ... STILL WILL NOT WRITE" until
      4 September 2026 (#267). That refusal was lifted with #261 once this
      hook began reading the override, so the sentence had outlived the state
      it described - everything below it is a correct record of why this case
      exists and stays as written.

      Since 3 September 2026 config.json is the SHIPPED DEFAULTS and nothing
      writes it: the operator's own ON/OFF choices go to config.override.json
      under the state directory, and Get-LwgConfig merges that over the
      defaults for every reader in this plugin. This hook read config.json
      ALONE, so an operator who switched context_injection off got a flag the
      SessionStart banner, /lw-watchtower:doctor and the config command's own
      read-back all reported as off - while the hook went on injecting into
      every dispatch. bin\lwg-config.ps1 refused to write this one module
      rather than ship that, which made it the only module of seven that could
      not be switched at all - a refusal #261 removed once the hook read the
      override, so this paragraph is history rather than current behaviour.

      THE OVERRIDE IS THE ONLY DIFFERENCE BETWEEN THE TWO RUNS. Both carry the
      same config.json, with the global flag TRUE, so a silent off-run is
      earned against a fixture that injects rather than against nothing.

      RED AT c39e782: the off run injects, because config.override.json was
      read by nothing on this path.
    #>
    $t = New-CaseRoot 'override-off'

    $base = New-OrderedConfig -Enabled $true
    $off = Invoke-SubagentStart -Tree $t -Config $base -Override ('{ "modules": { "' + $ModuleName + '": false } }')
    $on  = Invoke-SubagentStart -Tree $t -Config $base -Override ('{ "modules": { "' + $ModuleName + '": true } }')

    $bad = @()
    if ($off.code -ne 0)              { $bad += "the off run exited $($off.code); this hook must always exit 0" }
    if ($on.code  -ne 0)              { $bad += "the on run exited $($on.code); this hook must always exit 0" }
    if (Test-Injected $off.out)       { $bad += "IT INJECTED WHILE THE OPERATOR OVERRIDE SAYS false - config.override.json is where /lw-watchtower:config writes, and this hook did not read it: $($off.out)" }
    if ($off.out -ne '')              { $bad += "the off run printed something: $($off.out)" }
    if (-not (Test-Injected $on.out)) { $bad += "the on run did not inject, so the off run's silence proves nothing: $($on.out)" }

    Add-Result -Name 'the operator override switches this module OFF, and config.json is only the default it overrides (#11)' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | off exit $($off.code), on exit $($on.code)")
}

function Test-TheOperatorOverrideSwitchesTheModuleOn {
    <#
      THE MIRROR, and it is what stops the case above being passed by a hook
      that simply goes silent whenever an override file exists. Here
      config.json's global flag is FALSE and the override says true, so the
      only correct answer is to INJECT - the direction in which "abstain when
      configured" gives the wrong answer.

      Paired the other way for the same reason: the same config.json with an
      override saying false must be silent, so the injection is earned.

      RED AT c39e782, in the opposite direction to the case above: the on run
      is silent, because config.json's false was the only value read.
    #>
    $t = New-CaseRoot 'override-on'

    $base = New-OrderedConfig -Enabled $false
    $on  = Invoke-SubagentStart -Tree $t -Config $base -Override ('{ "modules": { "' + $ModuleName + '": true } }')
    $off = Invoke-SubagentStart -Tree $t -Config $base -Override ('{ "modules": { "' + $ModuleName + '": false } }')

    $bad = @()
    if ($on.code  -ne 0)              { $bad += "the on run exited $($on.code); this hook must always exit 0" }
    if ($off.code -ne 0)              { $bad += "the off run exited $($off.code); this hook must always exit 0" }
    if (-not (Test-Injected $on.out)) { $bad += "IT STAYED SILENT WHILE THE OPERATOR OVERRIDE SAYS true - the override must win over the shipped default in BOTH directions, or 'abstain whenever an override exists' passes the off case for nothing: $($on.out)" }
    if (Test-Injected $off.out)       { $bad += "the paired off run injected, so the on run's injection proves nothing about the override: $($off.out)" }

    Add-Result -Name 'and switches it ON over a shipped default of false, so the override wins in both directions (#11)' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | on exit $($on.code), off exit $($off.code)")
}

function Test-AnOverrideWithoutThisModuleLeavesTheDefaultStanding {
    <#
      THE CONTROL THAT FORBIDS THE CHEAP READING. Merge-LwgConfigOverride merges
      member by member: an override with no `modules` block, or a `modules`
      block that does not name this module, changes nothing about it and the
      shipped default stands. A hook that treated "an override exists" as an
      answer - either way - would pass the two cases above and get this wrong,
      and this is the shape a configured machine is actually in: nearly every
      override in the world will hold `interaction.delegate` and nothing else,
      because that is what /lw-watchtower:delegate writes.

      GREEN AT c39e782 TOO, and it is here for that reason: it is the guard on
      the fix rather than a regression case for the defect.
    #>
    $t = New-CaseRoot 'override-silent-on-this-module'

    $ov  = '{ "interaction": { "delegate": true } }'
    $off = Invoke-SubagentStart -Tree $t -Config (New-OrderedConfig -Enabled $false) -Override $ov
    $on  = Invoke-SubagentStart -Tree $t -Config (New-OrderedConfig -Enabled $true)  -Override $ov

    $bad = @()
    if ($off.code -ne 0)              { $bad += "the off run exited $($off.code); this hook must always exit 0" }
    if ($on.code  -ne 0)              { $bad += "the on run exited $($on.code); this hook must always exit 0" }
    if (Test-Injected $off.out)       { $bad += "an override that says nothing about this module flipped it ON: $($off.out)" }
    if (-not (Test-Injected $on.out)) { $bad += "an override that says nothing about this module flipped it OFF, which is how 'abstain whenever an override exists' would pass the two cases above: $($on.out)" }

    Add-Result -Name 'CONTROL: an override that does not name this module leaves the shipped default standing (#11)' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | off exit $($off.code), on exit $($on.code)")
}

function Test-APerRepoBlockInTheOverrideEscalatesAndResolvesIt {
    <#
      THE OVERRIDE ON THE SLOW PATH TOO. A `repos` block in the override can
      only be resolved with a slug, which this path never parses, so the hook
      escalates - dot-source common.ps1, parse the payload, ask Test-LwgModule -
      exactly as it already does for a `repos` block in config.json.

      THE FIXTURE MAKES THAT ESCALATION MEASURABLE. The override carries BOTH a
      global value for this module and a per-repo one that disagrees with it,
      and config.json carries the opposite global. The dispatch has an empty
      payload, so no repo resolves and Test-LwgModule falls back to the merged
      GLOBAL - the override's, not config.json's. So the answer is only right if
      Get-LwgConfig resolved the override as well, which is the half of #11 the
      fast scan alone cannot cover.

      RED AT c39e782 in both directions: the escalation ran there too, but
      Get-LwgConfig had no override to merge, so the answer came from
      config.json's global and both runs report the opposite of what they must.
    #>
    $t = New-CaseRoot 'override-repos'

    $ovOff = '{ "modules": { "' + $ModuleName + '": false },' +
             '  "repos": { "acme/example-repo": { "modules": { "' + $ModuleName + '": true } } } }'
    $ovOn  = '{ "modules": { "' + $ModuleName + '": true },' +
             '  "repos": { "acme/example-repo": { "modules": { "' + $ModuleName + '": false } } } }'

    $off = Invoke-SubagentStart -Tree $t -Config (New-OrderedConfig -Enabled $true)  -Override $ovOff
    $on  = Invoke-SubagentStart -Tree $t -Config (New-OrderedConfig -Enabled $false) -Override $ovOn

    $bad = @()
    if ($off.code -ne 0)              { $bad += "the off run exited $($off.code); this hook must always exit 0, escalation included" }
    if ($on.code  -ne 0)              { $bad += "the on run exited $($on.code); this hook must always exit 0, escalation included" }
    if (Test-Injected $off.out)       { $bad += "the escalation answered from config.json's global and not from the merged override, or applied the per-repo value to a dispatch that resolved no repo: $($off.out)" }
    if ($off.out -ne '')              { $bad += "the off run printed something: $($off.out)" }
    if (-not (Test-Injected $on.out)) { $bad += "the escalation answered from config.json's global rather than the merged override: $($on.out)" }

    Add-Result -Name 'a repos block in the OVERRIDE escalates, and the slow path resolves the override too (#11)' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | off exit $($off.code), on exit $($on.code)")
}

function Test-AnEscapedKeyInTheOverrideIsNotReadAsAbsence {
    <#
      THE FAIL-OPEN THE SECOND SCANNER WOULD HAVE SHIPPED, and it is the same
      one lib\gate_delegate.ps1 records finding in itself on the same day.

      This path never decodes the override; it scans the raw text. So

          { "modules": { "context_injection": false } }

      contains no member spelled `modules` for the scanner to find, while
      ConvertFrom-Json hands Get-LwgConfig a member called exactly that. A
      scanner that read "no modules block" as "the override says nothing" would
      leave the shipped default standing and inject, over an override that says
      not to - a value written, verified by every reporting surface, and
      honoured by nothing, which is the whole of #11 reappearing one layer down.

      \uXXXX IS THE ONLY JSON ESCAPE THAT CAN SPELL A LETTER, so its two opening
      characters anywhere in the override are enough to abstain, and nothing on
      this path has to decode anything. The run then escalates and
      ConvertFrom-Json answers.

      RED AT c39e782 for the simpler reason that no override was read at all,
      and red against the obvious implementation of this fix for the reason
      above - which is why it is here rather than left to review.
    #>
    $t = New-CaseRoot 'override-escaped-key'

    # THE KEY IS ASSEMBLED FROM [char]92 rather than typed as a literal, so no
    # editor, diff tool or copy-paste on the way here can quietly decode it and
    # turn this case into a duplicate of the one above. What reaches the file is
    # backslash-u-0-0-6-d followed by `odules`: six characters that any JSON
    # parser reads as the letter `m` plus `odules`, and that a raw text scan for
    # the eight characters `"modules"` cannot see.
    $escKey = ([char]92) + 'u006dodules'
    $esc = '{ "' + $escKey + '": { "' + $ModuleName + '": __V__ } }'

    $off = Invoke-SubagentStart -Tree $t -Config (New-OrderedConfig -Enabled $true)  -Override $esc.Replace('__V__', 'false')
    $on  = Invoke-SubagentStart -Tree $t -Config (New-OrderedConfig -Enabled $false) -Override $esc.Replace('__V__', 'true')

    $bad = @()
    if ($off.code -ne 0)              { $bad += "the off run exited $($off.code); this hook must always exit 0" }
    if ($on.code  -ne 0)              { $bad += "the on run exited $($on.code); this hook must always exit 0" }
    if (Test-Injected $off.out)       { $bad += "an ESCAPED spelling of the modules key was read as no override at all, and the shipped default injected over an operator setting that says not to: $($off.out)" }
    if ($off.out -ne '')              { $bad += "the off run printed something: $($off.out)" }
    if (-not (Test-Injected $on.out)) { $bad += "the on run stayed silent, so the escape sent it nowhere: the override says true and config.json says false, and only the slow path can reconcile them: $($on.out)" }

    Add-Result -Name 'an escaped spelling of the override key sends the run to the slow path rather than reading it as absence (#11)' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | off exit $($off.code), on exit $($on.code)")
}

function Test-FastScanAgreesWithTheSlowPathOnTheShippedConfig {
    <#
      THE DUPLICATION IS ONLY SAFE WHILE THE TWO AGREE. The fast scan exists to
      avoid Get-LwgConfig + Test-LwgModule, and its own header calls itself "a
      deliberate, narrow duplication" of them. Nothing checked that the two
      answered the same question the same way on the config this repository
      actually ships.

      So: the hook is run against the REAL repo root, and the answer it gives -
      injected or silent - is compared with what Test-LwgModule says in a
      separate child process that dot-sources lib\common.ps1. Neither number is
      hardcoded here; flipping context_injection in config.json must move both
      or fail this case.

      The facts file is the repo's real context\worker_facts.md, so the envelope
      is checked for the SubagentStart hookEventName rather than for the fixture
      line the other cases look for.

      A CANARY, NOT A REGRESSION CASE, and the header says so. On the key order
      config.json actually ships - `modules` before `repos` - this configuration
      cannot exhibit the depth defect at all, so this case is green on the
      depth-blind scanner too. What it catches is the fast scan and the slow path
      drifting apart, and it begins catching depth problems on the day
      config.json's top-level key order changes, which is the day nothing else
      here would notice.
    #>
    $saveRoot = $env:CLAUDE_PLUGIN_ROOT
    $saveData = $env:CLAUDE_PLUGIN_DATA
    $data = Join-Path $script:Work 'shipped-config-data'
    [void][IO.Directory]::CreateDirectory($data)
    try {
        $env:CLAUDE_PLUGIN_ROOT = $Root
        $env:CLAUDE_PLUGIN_DATA = $data
        $hookOut = (@('{}' | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $HookPath) -join '')
        $hookCode = if ($null -eq $LASTEXITCODE) { 255 } else { $LASTEXITCODE }

        $probe = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `
            ". '$CommonPath'; if (Test-LwgModule -Name '$ModuleName' -Config (Get-LwgConfig)) { 'ENABLED' } else { 'DISABLED' }")
        $slow = (@($probe) -join '').Trim()
    } finally {
        if ($null -eq $saveRoot) { Remove-Item -LiteralPath 'Env:\CLAUDE_PLUGIN_ROOT' -ErrorAction SilentlyContinue }
        else { $env:CLAUDE_PLUGIN_ROOT = $saveRoot }
        if ($null -eq $saveData) { Remove-Item -LiteralPath 'Env:\CLAUDE_PLUGIN_DATA' -ErrorAction SilentlyContinue }
        else { $env:CLAUDE_PLUGIN_DATA = $saveData }
    }

    $fastEnabled = ($hookOut -like '*"hookEventName":"SubagentStart"*')

    $bad = @()
    if ($hookCode -ne 0)                        { $bad += "the hook exited $hookCode against the shipped config" }
    if ($slow -ne 'ENABLED' -and $slow -ne 'DISABLED') { $bad += "the slow path did not answer: '$slow'" }
    elseif ($fastEnabled -and $slow -eq 'DISABLED')    { $bad += 'THE FAST SCAN INJECTS WHILE Test-LwgModule SAYS THE MODULE IS OFF' }
    elseif ((-not $fastEnabled) -and $slow -eq 'ENABLED') { $bad += 'the fast scan is silent while Test-LwgModule says the module is on' }

    Add-Result -Name "the fast scan and Test-LwgModule agree about $ModuleName on the config.json this repo ships" `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | fast injected: $fastEnabled, slow: $slow")
}

# ---------------------------------------------------------------------------
# RUN
# ---------------------------------------------------------------------------

Write-Output 'LW-WATCHTOWER SubagentStart fast-scan suite'
Write-Output "  script under test: $HookPath"
Write-Output ''

function Test-TheLocalFactsFileIsStillIgnored {
    <#
      #118. THE .gitignore PIN FOR worker_facts.local.md STILL NAMES IT.

      This hook composes context\worker_facts.local.md off the plugin root and
      reads it live on every dispatch, so an operator who writes one has it read
      on every subagent start whether or not git knows about it. The file is
      UNTRACKED BY DESIGN - it is per-machine, and the entry in .gitignore is
      what stops it being swept into a commit.

      THAT ENTRY IS A FULL PATH WITH A MID-PATH SLASH, which git anchors to the
      directory holding the .gitignore - the repository root. The payload
      restructure moved context/ under lw-watchtower/, and an entry left naming
      the old path matches NOTHING: the file goes on being created, is no longer
      ignored, and the next `git add -A` stages one machine's private notes.
      Nothing goes red; the .gitignore comment above the entry and the
      neighbouring .claude/worktrees/ block both exist to describe exactly that
      hazard.

      IT IS ASKED OF GIT, not of the file on disk, and the fixture file is never
      created: `git check-ignore` answers from the ignore rules alone, so this
      case establishes the rule without leaving anything behind for the next one
      to trip over.

      BOTH DIRECTIONS ARE ASSERTED. The new path must be ignored, and the OLD
      path must not be - an entry left behind at context/worker_facts.local.md
      would ignore a path that no longer exists while the live one went
      unignored, which reads as a working pin and is not one.

      RED AT a42b169 with only this hunk applied: the entry named
      context/worker_facts.local.md, so check-ignore matched the old path and
      not the new one - the mirror image of what it must now report.
    #>
    $repo = Split-Path -Parent $PSScriptRoot
    $new  = 'lw-watchtower/context/worker_facts.local.md'
    $old  = 'context/worker_facts.local.md'
    Push-Location -LiteralPath $repo
    try {
        $newOut  = (& git check-ignore -v -- $new 2>&1 | Out-String).Trim()
        $newCode = $LASTEXITCODE
        $oldOut  = (& git check-ignore -v -- $old 2>&1 | Out-String).Trim()
        $oldCode = $LASTEXITCODE
    } finally { Pop-Location }

    Add-Result -Name 'the .gitignore entry for the per-machine facts file names its tracked-tree path' `
        -Ok ($newCode -eq 0 -and $newOut -match '\.gitignore:\d+') `
        -Detail ("git check-ignore -v -- $new exited $newCode and said '$newOut'; expected a match naming a .gitignore line. " +
                 "Unignored, lib\subagent_start.ps1 goes on creating this file on every dispatch and the next git add -A stages one machine's private notes.")

    Add-Result -Name 'and it does NOT still name the pre-restructure path, which would ignore nothing' `
        -Ok ($oldCode -eq 1) `
        -Detail ("git check-ignore -v -- $old exited $oldCode and said '$oldOut'; expected exit 1 (no match). " +
                 "A rule still anchored at the old path ignores a file that cannot exist while the live one is staged by any -A, which reads as a working pin and is not one.")
}

# ---------------------------------------------------------------------------
# THE DISPATCH RECORD - six cases (slice 0 of #166, tracked on #311)
#
# BASELINE FOR EVERY ONE OF THEM: 97f0697. At that commit lib\subagent_start.ps1
# writes NO record of any kind on any path, so health.jsonl does not exist after
# a run and every positive half below fails outright.
# ---------------------------------------------------------------------------

function Test-TheDispatchRecordLands {
    <#
      ONE ROW PER DISPATCH, IN New-Record's ENVELOPE.

      lib\supervisor.ps1:195-203 builds every record in this file as
      { ts, event, session, cwd, ...extra }, and four readers parse that shape:
      supervisor.ps1:403 (the orphan reconciliation), gate_send.ps1:330,
      Get-LwgHealthRecords in common.ps1 and statusline.ps1:942. So the start row
      is that envelope and not a new spelling - ts IS the dispatch time, and there
      is deliberately no second timestamp under a second name in a file whose
      readers sort on ts.

      FIVE FIELDS ARE ASSERTED AND SO IS THE ONE THAT MUST BE ABSENT. cwd is
      omitted deliberately: ConvertTo-SafeField routes through Get-LwgRedacted
      and therefore through the regex engine, whose first use in a fresh process
      costs more than everything this hook does put together
      (subagent_start.ps1's own header), and cwd is the one field here carrying
      an operator name and a clone root. A row that quietly grew a cwd would put
      an unredacted path into a log the status line prints from.

      THE LINE IS PARSED WITH ConvertFrom-Json rather than matched with -like,
      because that is the parser every reader uses. A row that matches a
      substring and does not parse is not a record.

      RED AT 97f0697: no health.jsonl exists after the run, so this reports zero
      rows where it requires one.
    #>
    $t   = New-CaseRoot 'ledger-lands'
    $cfg = New-LedgerConfig -FailureCapture $true -ContextInjection $true

    $r    = Invoke-SubagentStartWithPayload -Tree $t -Config $cfg -Payload (New-LedgerPayload)
    $rows = @(Get-LedgerStartRows -Lines (Get-LedgerLines -Dir $t.data))

    $bad = @()
    if ($r.code -ne 0) { $bad += "exited $($r.code); this hook must always exit 0" }
    if ($rows.Count -ne 1) {
        $bad += ("expected exactly ONE SubagentStart row in health.jsonl, found $($rows.Count). " +
                 'At 97f0697 this hook wrote no record at all, which is the defect slice 0 fixes')
    } elseif ($null -eq $rows[0]) {
        $bad += 'the row did not parse as JSON - every reader of health.jsonl parses it, so an unparsable row is not a record'
    } else {
        $row = $rows[0]
        if ([string]$row.session    -ne $LedgerSession)   { $bad += "session was '$($row.session)', expected '$LedgerSession'" }
        if ([string]$row.agent_id   -ne $LedgerAgentId)   { $bad += "agent_id was '$($row.agent_id)', expected '$LedgerAgentId' - supervisor.ps1:403 keys on this field" }
        if ([string]$row.agent_type -ne $LedgerAgentType) { $bad += "agent_type was '$($row.agent_type)', expected '$LedgerAgentType'" }
        $ts = [datetime]::MinValue
        if (-not [datetime]::TryParse([string]$row.ts, [ref]$ts)) {
            $bad += "ts '$($row.ts)' did not parse as a date; supervisor.ps1:403 and statusline.ps1 both sort on it"
        } elseif (([string]$row.ts) -notmatch 'Z$') {
            $bad += "ts '$($row.ts)' is not UTC in round-trip ('o') form; New-Record's ts always ends in Z"
        }
        $names = @($row.PSObject.Properties.Name)
        if ($names -contains 'cwd') {
            $bad += ('the row carries a cwd field. That omission is load-bearing: redaction cannot run on this ' +
                     'path and cwd is the one field carrying the operator name and the clone root')
        }
        $unexpected = @($names | Where-Object { @('ts', 'event', 'session', 'agent_id', 'agent_type') -notcontains $_ })
        if ($unexpected.Count -gt 0) { $bad += ("the row carries unexpected field(s): " + ($unexpected -join ', ')) }
    }

    Add-Result -Name 'the dispatch record lands: one SubagentStart row, five fields, no cwd (#166 slice 0)' `
               -Ok ($bad.Count -eq 0) `
               -Detail (($bad -join '; ') + " | exit $($r.code), rows $($rows.Count)")
}

function Test-FailureCaptureOffWritesNoRowAndStillInjects {
    <#
      THE ROW IS GATED ON effort_ledger, NOT ON THIS FILE'S OWN MODULE.

      The row is an addition to effort_ledger and not a new module - no
      registry entry, no `modules` key of its own, no state file, no rotation
      wiring. So the flag that stops lib\supervisor.ps1 writing to health.jsonl
      has to stop this writer too, or an operator who switched failure capture
      off would still be accruing records in the log it names.

      NO BARE NEGATIVE. This case runs the SAME fixture twice with ONE BIT
      changed - the global effort_ledger value - and requires a row in the ON
      run. Without that half, "no row" is satisfied by a hook that crashed, and
      at 97f0697 it is satisfied by a hook that never wrote one.

      AND THE INJECTION MUST SURVIVE BOTH. context_injection is true in both
      runs, so if switching effort_ledger off also silenced the injection, the
      two modules would have been coupled in the wrong direction by the same
      commit that separated them.

      RED AT 97f0697: the ON half finds no row.
    #>
    $t = New-CaseRoot 'ledger-fc-off'

    $on  = Invoke-SubagentStartWithPayload -Tree $t -Config (New-LedgerConfig -FailureCapture $true  -ContextInjection $true) -Payload (New-LedgerPayload)
    $onRows = @(Get-LedgerStartRows -Lines (Get-LedgerLines -Dir $t.data))

    # The OFF run appends to the same log, so the assertion is that the count
    # does not MOVE rather than that the file is absent - the ON run put a row
    # in it a moment ago and deleting the file would test a different thing.
    $off = Invoke-SubagentStartWithPayload -Tree $t -Config (New-LedgerConfig -FailureCapture $false -ContextInjection $true) -Payload (New-LedgerPayload)
    $offRows = @(Get-LedgerStartRows -Lines (Get-LedgerLines -Dir $t.data))

    $bad = @()
    if ($on.code  -ne 0) { $bad += "the effort_ledger ON run exited $($on.code); this hook must always exit 0" }
    if ($off.code -ne 0) { $bad += "the effort_ledger OFF run exited $($off.code); this hook must always exit 0" }
    if ($onRows.Count -ne 1) {
        $bad += ("CONTROL FAILED: effort_ledger ON wrote $($onRows.Count) rows, expected 1 - so the OFF half " +
                 'below establishes nothing. At 97f0697 nothing wrote this file at all')
    }
    if ($offRows.Count -ne $onRows.Count) {
        $bad += ("effort_ledger OFF wrote a row anyway: the log went from $($onRows.Count) to $($offRows.Count) " +
                 'SubagentStart rows. The dispatch record ships under that flag and must stop when it does')
    }
    if (-not (Test-Injected $on.out))  { $bad += 'effort_ledger ON: nothing was injected, so the fixture is wrong rather than the gate' }
    if (-not (Test-Injected $off.out)) { $bad += 'effort_ledger OFF also silenced the INJECTION - the two modules must not be coupled in that direction' }

    Add-Result -Name 'effort_ledger off: no row, and context_injection still injects (#166 slice 0)' `
               -Ok ($bad.Count -eq 0) `
               -Detail (($bad -join '; ') + " | on exit $($on.code) rows $($onRows.Count) injected $(Test-Injected $on.out); off exit $($off.code) rows $($offRows.Count) injected $(Test-Injected $off.out)")
}

function Test-ContextInjectionOffStillWritesTheRow {
    <#
      THE OTHER DIRECTION, AND IT IS THE ONE THAT IS EASY TO GET WRONG.

      This file's own early exit is `if (-not $enabled) { exit 0 }`, and until
      slice 0 that exit was the whole of the off path: no envelope, no log line,
      nothing. The row belongs to effort_ledger, so it has to be written
      BEFORE that exit or an operator who switched context_injection off would
      silently switch off a module they never touched - which is the class of
      quiet wrongness this plugin exists to remove.

      NO BARE POSITIVE EITHER: the injection is required to be ABSENT in the
      same run, so a fixture that failed to switch context_injection off cannot
      pass this case by accident.

      RED AT 97f0697: no row.
    #>
    $t   = New-CaseRoot 'ledger-ci-off'
    $cfg = New-LedgerConfig -FailureCapture $true -ContextInjection $false

    $r    = Invoke-SubagentStartWithPayload -Tree $t -Config $cfg -Payload (New-LedgerPayload)
    $rows = @(Get-LedgerStartRows -Lines (Get-LedgerLines -Dir $t.data))

    $bad = @()
    if ($r.code -ne 0) { $bad += "exited $($r.code); this hook must always exit 0" }
    if (Test-Injected $r.out) {
        $bad += 'CONTROL FAILED: context_injection is false in this fixture and the hook injected anyway, so the row below proves nothing about the off path'
    }
    if ($rows.Count -ne 1) {
        $bad += ("context_injection off suppressed the dispatch record too: expected 1 SubagentStart row, found $($rows.Count). " +
                 'The row is gated on effort_ledger and must be written above this file own early exit')
    }

    Add-Result -Name 'context_injection off: the dispatch record still lands (#166 slice 0)' `
               -Ok ($bad.Count -eq 0) `
               -Detail (($bad -join '; ') + " | exit $($r.code), rows $($rows.Count), injected $(Test-Injected $r.out)")
}

function Test-GarbageStdinWritesNoRowAndStillExitsZero {
    <#
      A PAYLOAD THAT IS NOT JSON MUST COST THE ROW AND NOTHING ELSE.

      The fast path does not parse stdin - parsing it would cost the 141-182 ms
      ConvertFrom-Json warm-up this file exists to avoid - so the row's fields
      are lifted out of the raw text by a scanner. A scanner handed bytes that
      are not JSON must find no session and no agent id and write NOTHING; a row
      whose session is unknown is matched by no reader and is pure noise in a log
      whose depth this slice already halves.

      NO BARE NEGATIVE: the same fixture is run a second time with a REAL payload
      and a row is required, so "no row" is earned against a run that writes one
      rather than against a hook that fell over.

      THE EXIT CODE IS PART OF THE CASE. This hook must always exit 0 - a
      governance layer that cannot inject a note must never be able to fail a
      dispatch - and that is now true of a ledger it cannot write as well.

      RED AT 97f0697: the control half finds no row.
    #>
    $t   = New-CaseRoot 'ledger-garbage'
    $cfg = New-LedgerConfig -FailureCapture $true -ContextInjection $true

    # Not JSON at any depth, and deliberately carrying the WORDS the scanner
    # looks for so a scanner matching on the bare name rather than on a quoted
    # member followed by a colon would be caught.
    $junk = 'session_id agent_id agent_type {{{ "unterminated'

    $g     = Invoke-SubagentStartWithPayload -Tree $t -Config $cfg -Payload $junk
    $gRows = @(Get-LedgerStartRows -Lines (Get-LedgerLines -Dir $t.data))

    $ok     = Invoke-SubagentStartWithPayload -Tree $t -Config $cfg -Payload (New-LedgerPayload)
    $okRows = @(Get-LedgerStartRows -Lines (Get-LedgerLines -Dir $t.data))

    $bad = @()
    if ($g.code  -ne 0) { $bad += "the garbage run exited $($g.code); this hook must always exit 0" }
    if ($ok.code -ne 0) { $bad += "the control run exited $($ok.code); this hook must always exit 0" }
    if ($gRows.Count -ne 0) { $bad += "garbage stdin still produced $($gRows.Count) SubagentStart row(s); a row with no session and no agent id is matched by no reader" }
    if ($okRows.Count -ne 1) {
        $bad += ("CONTROL FAILED: a real payload against the same fixture produced $($okRows.Count) rows, expected 1 - " +
                 'so the silence above establishes nothing. At 97f0697 nothing wrote this file at all')
    }
    if (-not (Test-Injected $g.out)) { $bad += 'garbage stdin also stopped the INJECTION; the facts file does not come from the payload and must still be read' }

    Add-Result -Name 'unreadable stdin: no row, still exit 0, still injects (#166 slice 0)' `
               -Ok ($bad.Count -eq 0) `
               -Detail (($bad -join '; ') + " | garbage exit $($g.code) rows $($gRows.Count); control exit $($ok.code) rows $($okRows.Count)")
}

function Test-ANonAsciiAgentTypeIsEscapedToPureAscii {
    <#
      THE ROW IS PURE ASCII WHATEVER THE PAYLOAD CARRIES, AND STILL MEANS WHAT
      THE PAYLOAD SAID.

      The row is built by hand - ConvertTo-Json would cost the warm-up this file
      exists to avoid - so the escaping is this file's own ConvertTo-LwgJsonString,
      which checks its fast Replace chain rather than trusting it: a UTF-8 byte
      count that differs from the character count proves a character above U+007F
      is present and sends the string to the exact escaper, which emits \uXXXX.

      BOTH HALVES ARE ASSERTED, and one without the other is worthless. The BYTES
      on disk must all be under 0x80 - a row written at the console code page
      would be mojibake in a log every other writer emits as UTF-8 - AND the
      parsed value must come back as the original characters, or the hook has
      escaped its way to a row that is clean and wrong.

      RED AT 97f0697: no row.
    #>
    $t   = New-CaseRoot 'ledger-nonascii'
    $cfg = New-LedgerConfig -FailureCapture $true -ContextInjection $true

    # Built from code points rather than typed, so this cannot be defeated by
    # this file being saved in the wrong encoding one day - the class of defect
    # under test. A Latin-1 umlaut and two CJK characters, as case
    # Test-ANonAsciiCwdStillResolvesThePerRepoOverride uses above.
    $type = 'agent-' + [char]0x00F6 + '-' + [char]0x65E5 + [char]0x672C

    $r = Invoke-SubagentStartWithPayload -Tree $t -Config $cfg -Payload (New-LedgerPayload -AgentType $type)

    $logPath = Join-Path $t.data 'health.jsonl'
    $bytes   = @()
    if ([IO.File]::Exists($logPath)) { $bytes = [IO.File]::ReadAllBytes($logPath) }
    $high = @($bytes | Where-Object { $_ -gt 127 })

    $rows = @(Get-LedgerStartRows -Lines (Get-LedgerLines -Dir $t.data))

    $bad = @()
    if ($r.code -ne 0) { $bad += "exited $($r.code); this hook must always exit 0" }
    if ($rows.Count -ne 1) {
        $bad += "expected exactly one SubagentStart row, found $($rows.Count). At 97f0697 nothing wrote this file at all"
    } elseif ($null -eq $rows[0]) {
        $bad += 'the row did not parse as JSON'
    } elseif ([string]$rows[0].agent_type -ne $type) {
        $bad += ("agent_type came back as '$([string]$rows[0].agent_type)' and the payload said '$type' - the row is " +
                 'escaped to something that is not what was dispatched')
    }
    if ($high.Count -gt 0) {
        $bad += ("$($high.Count) byte(s) in health.jsonl are above 0x7F. The row must escape to \uXXXX rather than " +
                 'emit raw bytes, or a console at a different code page writes mojibake into a log every other writer emits as UTF-8')
    }

    Add-Result -Name 'a non-ASCII agent_type is escaped to pure ASCII and still round-trips (#166 slice 0)' `
               -Ok ($bad.Count -eq 0) `
               -Detail (($bad -join '; ') + " | exit $($r.code), rows $($rows.Count), bytes>0x7F $($high.Count)")
}

function Test-TheStateDirectoryIsNeverGuessed {
    <#
      CLAUDE_PLUGIN_DATA UNSET MUST ESCALATE, NOT GUESS.

      Get-LwgStateDirInfo (common.ps1:766) returns CLAUDE_PLUGIN_DATA verbatim
      when it is set - "the branch every live hook takes" - so the fast path
      composes health.jsonl off it and pays nothing. When it is NOT set the
      answer is a RANKED DISCOVERY over the configuration root, and a second,
      cheaper spelling of that ranking here could pick a different directory and
      produce TWO health logs, each half a session's history. lib\supervisor.ps1:656
      records what a reader over a file nothing wrote looks like: it reported
      "0 orphans" unconditionally for its entire life.

      So this file escalates on that condition instead - the branch it already
      had at subagent_start.ps1:594 - and takes the directory from
      Get-LwgStateDir, the one resolver.

      WHAT IS ASSERTED: exactly ONE health.jsonl exists anywhere under the case
      tree, it sits under the configuration root's plugins\data, and it holds
      exactly one row. Two logs, or a log outside that root, is the defect.

      TEST SAFETY: CLAUDE_CONFIG_DIR is redirected into the case tree, so the
      discovery this case forces cannot reach the operator's own
      ~\.claude\plugins\data. See Invoke-SubagentStartWithPayload's -NoStateDir.

      RED AT 97f0697: no health.jsonl anywhere.
    #>
    $t   = New-CaseRoot 'ledger-nostatedir'
    $cfg = New-LedgerConfig -FailureCapture $true -ContextInjection $true

    $r = Invoke-SubagentStartWithPayload -Tree $t -Config $cfg -Payload (New-LedgerPayload) -NoStateDir

    $logs = @()
    try { $logs = @([IO.Directory]::GetFiles($t.dir, 'health.jsonl', [IO.SearchOption]::AllDirectories)) } catch { }

    $bad = @()
    if ($r.code -ne 0) { $bad += "exited $($r.code); this hook must always exit 0" }
    if ($logs.Count -ne 1) {
        $bad += ("expected exactly ONE health.jsonl under the case tree, found $($logs.Count)" +
                 $(if ($logs.Count -gt 0) { ': ' + (($logs | ForEach-Object { $_.Substring($t.dir.Length) }) -join ', ') } else { '' }) +
                 '. At 97f0697 there is none; more than one is the guessed-directory defect this case exists for')
    } else {
        $dir = [IO.Path]::GetDirectoryName($logs[0])
        if (-not $dir.StartsWith($t.home, [StringComparison]::OrdinalIgnoreCase)) {
            $bad += "the row landed at '$dir', which is not under the redirected configuration root '$($t.home)'"
        }
        if ($dir.IndexOf('plugins', [StringComparison]::OrdinalIgnoreCase) -lt 0) {
            $bad += "the row landed at '$dir', which is not a plugins\data state directory - the fast path guessed instead of escalating"
        }
        $rows = @(Get-LedgerStartRows -Lines (Get-LedgerLines -Dir $dir))
        if ($rows.Count -ne 1) { $bad += "the resolved log holds $($rows.Count) SubagentStart row(s), expected exactly 1" }
    }

    Add-Result -Name 'CLAUDE_PLUGIN_DATA unset: the hook escalates and writes ONE row to the resolved state dir (#166 slice 0)' `
               -Ok ($bad.Count -eq 0) `
               -Detail (($bad -join '; ') + " | exit $($r.code), health.jsonl found $($logs.Count)")
}

try {
    if (-not (Test-Path -LiteralPath $HookPath -PathType Leaf)) {
        $script:Aborted = "lib\subagent_start.ps1 not found at $HookPath"
        throw $script:Aborted
    }
    if (-not (Test-Path -LiteralPath $CommonPath -PathType Leaf)) {
        $script:Aborted = "lib\common.ps1 not found at $CommonPath - one case compares the fast scan with it"
        throw $script:Aborted
    }

    $script:Work = Join-Path ([IO.Path]::GetTempPath()) ("lwg-subagent-test-" + [Guid]::NewGuid().ToString('N').Substring(0, 10))
    [void][IO.Directory]::CreateDirectory($script:Work)

    Test-TheLocalFactsFileIsStillIgnored
    Test-ReposBeforeModulesReadsTheGlobalFlag
    Test-DecoyModulesUnderANonReposKeyIsIgnored
    Test-ShippedOrderReadsTheGlobalFlag
    Test-PerRepoOverrideStillEscalates
    Test-ANonAsciiCwdStillResolvesThePerRepoOverride
    Test-NoConfigFailsOpen
    Test-TheOperatorOverrideSwitchesTheModuleOff
    Test-TheOperatorOverrideSwitchesTheModuleOn
    Test-AnOverrideWithoutThisModuleLeavesTheDefaultStanding
    Test-APerRepoBlockInTheOverrideEscalatesAndResolvesIt
    Test-AnEscapedKeyInTheOverrideIsNotReadAsAbsence
    Test-FastScanAgreesWithTheSlowPathOnTheShippedConfig
    # The dispatch record - slice 0 of #166. All six are RED at 97f0697.
    Test-TheDispatchRecordLands
    Test-FailureCaptureOffWritesNoRowAndStillInjects
    Test-ContextInjectionOffStillWritesTheRow
    Test-GarbageStdinWritesNoRowAndStillExitsZero
    Test-ANonAsciiAgentTypeIsEscapedToPureAscii
    Test-TheStateDirectoryIsNeverGuessed
}
catch {
    if (-not $script:Aborted) { $script:Aborted = $_.Exception.Message }
}
finally {
    if ($script:Work -and (Test-Path -LiteralPath $script:Work)) {
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$total  = $script:Results.Count
$failed = $total - $script:Pass

Write-Output ''
# THE RESULT: AND EXIT: TOKENS ARE A CONTRACT, NOT DECORATION, and the literal
# `case(s)` is load-bearing: tests\doc_claims.ps1 decides which suites are
# BEHAVIOURAL by matching `N of M case(s)` in each suite's own output rather
# than from a list it is told.
if ($script:Aborted) {
    Write-Output "ABORTED: $($script:Aborted)"
    Write-Output "RESULT: $script:Pass of $total case(s) had run when it stopped. Nothing about the fast scan was established."
    Write-Output 'EXIT: 2 (the hook was NOT exercised, which is not the same as passing)'
    exit 2
}
if ($total -eq 0) {
    Write-Output 'ABORTED: no case ran. An empty set is not a pass.'
    Write-Output 'RESULT: no case ran, so nothing about the fast scan was established'
    Write-Output 'EXIT: 2 (zero cases run is an abort, never an empty-set pass)'
    exit 2
}
Write-Output ("RESULT: {0} of {1} case(s) passed." -f $script:Pass, $total)
if ($failed -gt 0) {
    Write-Output "$failed case(s) FAILED."
    Write-Output 'EXIT: 1 (at least one case failed - read the per-case lines above. A case'
    Write-Output '         reporting an injection while the global flag is false means the hook'
    Write-Output '         runs on every dispatch while every reporting surface says it is off.)'
    exit 1
}
Write-Output 'EXIT: 0 (every case passed - the fast scan answered the global flag in both key'
Write-Output '         orders, escalated for a per-repo override, failed open with no config,'
Write-Output '         agreed with Test-LwgModule on the shipped config, and the dispatch record'
Write-Output '         landed once per dispatch under effort_ledger alone, in pure ASCII, with'
Write-Output '         no cwd and no guessed state directory)'
exit 0
