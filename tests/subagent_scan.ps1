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
  Two of the five cases below FAIL on the depth-blind scanner and are the
  regression cases for it:

      Test-ReposBeforeModulesReadsTheGlobalFlag
      Test-DecoyModulesUnderANonReposKeyIsIgnored

  The other three are green on the defect as well, and each is here for its own
  reason rather than as evidence about depth:

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
  * THE ESCALATION'S SLUG RESOLUTION. Case
    Test-PerRepoOverrideStillEscalates proves the escalation still runs and
    still lands on the right answer for a dispatch with no repo in its payload.
    WHICH repo a real payload resolves to is Get-LwgRepo's job and is not
    re-tested here.
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
    # Repo root. Defaults to this file's parent, correct for a run from anywhere
    # as long as this file stays in tests\.
    [string]$Root
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }

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

      config.json is NOT written here - each case says what its config looks
      like, because the config is the subject.
    #>
    param([string]$Tag)

    $dir  = Join-Path $script:Work $Tag
    $root = Join-Path $dir 'root'
    $ctx  = Join-Path $root 'context'
    $data = Join-Path $dir 'data'
    foreach ($p in @($ctx, $data)) { [void][IO.Directory]::CreateDirectory($p) }
    [IO.File]::WriteAllText((Join-Path $ctx 'worker_facts.md'),
                            "# a comment line the hook must drop`r`n$FactLine`r`n",
                            [Text.UTF8Encoding]::new($false))
    return @{ dir = $dir; root = $root; data = $data }
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

      Returns @{ code; out } where `out` is the whole stdout as one string.
    #>
    param(
        [Parameter(Mandatory = $true)][hashtable]$Tree,
        [string]$Config
    )

    $cfgPath = Join-Path $Tree.root 'config.json'
    if ($null -ne $Config) {
        [IO.File]::WriteAllText($cfgPath, $Config, [Text.UTF8Encoding]::new($false))
    } elseif ([IO.File]::Exists($cfgPath)) {
        [IO.File]::Delete($cfgPath)
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

function Test-Injected {
    <#
      Did this run inject? Both halves are checked rather than just the envelope
      name: an envelope carrying somebody else's text would mean the fixture was
      not what was read.
    #>
    param([string]$Out)
    return ($Out -like '*"hookEventName":"SubagentStart"*') -and ($Out -like "*$FactLine*")
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

    Test-ReposBeforeModulesReadsTheGlobalFlag
    Test-DecoyModulesUnderANonReposKeyIsIgnored
    Test-ShippedOrderReadsTheGlobalFlag
    Test-PerRepoOverrideStillEscalates
    Test-NoConfigFailsOpen
    Test-FastScanAgreesWithTheSlowPathOnTheShippedConfig
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
Write-Output '         and agreed with Test-LwgModule on the shipped config)'
exit 0
