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
  Two of the thirteen cases below FAIL on the depth-blind scanner and are the
  regression cases for it:

      Test-ReposBeforeModulesReadsTheGlobalFlag
      Test-DecoyModulesUnderANonReposKeyIsIgnored

  The other eleven are green on the defect as well, and each is here for its own
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
    Test-NoConfigFailsOpen
    Test-TheOperatorOverrideSwitchesTheModuleOff
    Test-TheOperatorOverrideSwitchesTheModuleOn
    Test-AnOverrideWithoutThisModuleLeavesTheDefaultStanding
    Test-APerRepoBlockInTheOverrideEscalatesAndResolvesIt
    Test-AnEscapedKeyInTheOverrideIsNotReadAsAbsence
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
