#requires -version 5
<#
  LW-WATCHTOWER evidence-state regression suite.

      powershell -NoProfile -ExecutionPolicy Bypass -File tests\evidence_states.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File tests\evidence_states.ps1 -Verbose

  THE ONE QUESTION THIS SUITE ASKS. Can bin\lwg-evidence.ps1 tell a probe that
  RAN AND FOUND THE THING ABSENT from a probe that NEVER GOT TO LOOK? Those two
  render as `[ ] NOT STARTED` and `[?] UNVERIFIED`, the product documents them as
  different states in four places, and until 31 July 2026 the `command` evaluator
  could not tell them apart at all.

  WHAT SHIPPED, because a suite written after a defect should name it. On the
  MARKETPLACE install route - the one docs\install.md calls recommended for
  consumers - the plugin directory carries no `.git`. Every `kind: command` rule
  in checklist.json that shells out to git therefore exited 128 having read
  nothing, the engine scored that as "the condition was not met", and two rows
  rendered `[ ] NOT STARTED`. Read as the product defines that mark, they said:
  the owner's personal address WAS left in history, and the private sibling
  project's name IS in the tree. Both are false, and neither had been measured.
  On a junction install of the same commit the two rows were fine, which is why
  nothing caught it: the defect was invisible from the machine it was written on
  and needed an adversarial UAT on the other install route to surface.

  SO THE FIXTURE IS THE POINT OF THIS FILE. Section A evaluates the SHIPPED rules
  out of checklist.json - not hand-written lookalikes - against a scratch
  directory that is not inside a git repository, which is the marketplace install
  in the only respect that matters here. It is built by COPYING a few files to a
  temp directory. Nothing is ever deleted to produce it: a fixture built by
  removing a `.git` is one bad path away from removing a real one.

  THE OTHER HALF, and it is half the suite for a reason. Answering "unverified"
  to everything would make section A green and would be a worse defect than the
  one it replaced - a checklist that can never say a thing is undone reports
  nothing at all. Sections B, D and F evaluate probes that genuinely ran and
  genuinely failed, and require them to stay findings. Every rung of the ladder
  in Resolve-LwgChecklist that this change touches is asserted in both
  directions.

  SECTION H IS ABOUT THE TWO QUESTIONS THAT COME BEFORE THAT ONE, and it was
  added on 3 August 2026. Every case in it is a defect this engine or this
  manifest actually had on that date, not a hypothetical: WHICH FILE a rule was
  pointed at (a bare string-prefix containment test read a sibling directory
  whose name merely extended the plugin root's, and cited it), HOW FAR BACK a
  commit scan looked before calling a miss an absence, whether the delegate
  gate's registration rule asserted any STRUCTURE at all (it was one unanchored
  regex that a gate on PostToolUse satisfied), whether three shipped rules test
  their own titles, and whether the `use_gh` switch documented as removing the
  gh dependency removed it here. Those are separate questions from "ran and
  found nothing versus never got to look", and a suite answering only the
  second says nothing about a probe pointed at the wrong tree.

  ---------------------------------------------------------------------------
  HOW A CASE IS RUN
  ---------------------------------------------------------------------------
  Sections A-F and H call Test-LwgEvidence and Resolve-LwgChecklist IN PROCESS,
  after dot-sourcing lib\common.ps1 and bin\lwg-evidence.ps1. That is not a
  shortcut around a child process: bin\lwg-evidence.ps1 is a dot-sourced library
  that never runs on its own, and bin\lwg-checklist.ps1 reaches it exactly this
  way. A child process here would test a wrapper this file is not about.

  Section G is the end-to-end case, and it does run a real child process:
  bin\lwg-checklist.ps1 against a throwaway plugin root with no `.git`, read back
  off its own stdout. That is the consumer's view of the defect - the rendered
  mark in the rendered row - and it is the case that would have caught it.

  SEVERAL SECTION H CASES EVALUATE THE SHIPPED RULE OUT OF checklist.json rather
  than a lookalike, through Get-ShippedItem, which asserts the rule's kind and
  ABORTS the suite if the manifest no longer holds it in that shape. A case
  built on a rule nobody ships passes forever while establishing nothing, which
  is the same silent no-op Get-ShippedRule and New-LwgFakeRoot guard against.

  Every process the suite spawns is git, powershell, or a fixture script this
  file wrote to the temp directory. No network. No elevation. Nothing writes
  anywhere but the one scratch directory, which is removed at the end.

  ---------------------------------------------------------------------------
  EXIT CODES - a CI job reads these and nothing else
  ---------------------------------------------------------------------------
      0  every case passed
      1  at least one case FAILED
      2  the suite ABORTED - it could not set up or could not run a case, so
         nothing was established either way. Zero cases run is an abort, never
         an empty-set pass.

  WHAT A GREEN RUN DOES NOT MEAN. It does not mean the engine can tell the two
  apart in general. It means it can tell them apart for the signals listed here:
  git exiting 128 outside a repository, an interpreter refusing a script that is
  not installed, a program that will not start, an exit code the rule itself
  declares ambiguous, empty output under a rule that proves its item from
  output, and a commit scan that came back full. Every other way a probe can
  answer a question it never reached is still scored as a finding, and this file
  says nothing about those.

  IT ALSO DOES NOT MEAN THE MANIFEST IS SOUND. Section H holds three shipped
  rules to their own titles and asserts the SHAPE of two more; the other
  thirty-five rules in checklist.json are read by nothing here. And the
  containment cases are a path-shape test: a symlink or junction planted inside
  the plugin root still resolves to a contained path and is read, which is
  stated in Resolve-LwgRptPath's own docstring and is not covered by any case
  below.
#>
[CmdletBinding()]
param(
    # Repo root. Defaults to this file's parent, correct for a run from
    # anywhere as long as this file stays in tests\.
    [string]$Root
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }

$CommonPath    = Join-Path $Root 'lib\common.ps1'
$EvidencePath  = Join-Path $Root 'bin\lwg-evidence.ps1'
$ChecklistPath = Join-Path $Root 'bin\lwg-checklist.ps1'
$ManifestPath  = Join-Path $Root 'checklist.json'
$ConfigPath    = Join-Path $Root 'config.json'

$script:Pass    = 0
$script:Results = New-Object System.Collections.ArrayList
$script:Aborted = ''

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

function New-Rule {
    <#
      An evidence rule in the shape checklist.json produces. Round-tripped
      through JSON rather than passed as a hashtable, because that is what
      Test-LwgEvidence is handed in production - a PSCustomObject whose absent
      members read as $null - and a hashtable answers `.expect_exit` differently
      enough to make a case pass for the wrong reason.
    #>
    param([hashtable]$Rule)
    return ($Rule | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
}

function Get-ShippedRule {
    <#
      One evidence rule lifted from the tracked checklist.json BY ID.

      The shape is ASSERTED rather than assumed. If the manifest ever stops
      holding that id, or the rule stops being a git `command` rule, this throws
      and the suite aborts - because the case would otherwise go on passing
      against a rule that no longer exercises the thing it was written for,
      which is the same silent no-op New-LwgFakeRoot guards against in
      tests\gate_delegate.ps1.
    #>
    param([string]$Id, $Items)

    $hits = @($Items | Where-Object { [string]$_.id -eq $Id })
    if ($hits.Count -ne 1) {
        throw "checklist.json holds $($hits.Count) item(s) with id '$Id', expected exactly 1 - the shipped-rule case cannot be built, and building it wrong would test a rule nobody ships"
    }
    $ev = $hits[0].evidence
    if ($null -eq $ev -or [string]$ev.kind -ne 'command' -or [string]$ev.file -ne 'git') {
        throw "checklist.json's '$Id' is no longer a git 'command' rule (kind '$([string]$ev.kind)', file '$([string]$ev.file)') - this case exists to exercise git exiting 128 outside a repository and would establish nothing"
    }
    return $ev
}

function Get-ShippedItem {
    <#
      One whole ITEM out of the tracked checklist.json, by id, with its evidence
      kind asserted.

      Same reasoning as Get-ShippedRule above and the same failure mode it exists
      to refuse: a case built against a rule the manifest no longer holds, or no
      longer holds in the shape the case was written for, goes on passing while
      exercising something else. Section H's cases are about SHIPPED rules rather
      than lookalikes - the whole point of them is that the manifest itself is the
      thing under test - so the shape check throws and the suite aborts rather
      than reporting a verdict about a rule nobody ships.
    #>
    param([string]$Id, [string]$Kind, $Items)

    $hits = @($Items | Where-Object { [string]$_.id -eq $Id })
    if ($hits.Count -ne 1) {
        throw "checklist.json holds $($hits.Count) item(s) with id '$Id', expected exactly 1 - a case built on it would test a rule nobody ships"
    }
    $ev = $hits[0].evidence
    if ($null -eq $ev -or [string]$ev.kind -ne $Kind) {
        throw "checklist.json's '$Id' is evidence kind '$([string]$ev.kind)', not '$Kind' - the case written for it exercises the '$Kind' path and would establish nothing here"
    }
    return $hits[0]
}

function Test-State {
    <# One expected state, with the observed detail carried into the failure. #>
    param($Result, [string]$Want)
    if ($null -eq $Result) { return @{ ok = $false; why = 'Test-LwgEvidence returned nothing at all' } }
    if ([string]$Result.state -ne $Want) {
        return @{ ok = $false; why = "state is '$([string]$Result.state)', expected '$Want'. The probe reported: $([string]$Result.detail)" }
    }
    return @{ ok = $true; why = '' }
}

# ===========================================================================
# MAIN
# ===========================================================================
$sw = [Diagnostics.Stopwatch]::StartNew()
$work = ''

try {
    Write-Output 'LW-WATCHTOWER evidence-state regression suite'
    Write-Output "  repo     : $Root"
    Write-Output "  engine   : $EvidencePath"
    Write-Output ''

    foreach ($p in @($CommonPath, $EvidencePath, $ChecklistPath, $ManifestPath)) {
        if (-not [IO.File]::Exists($p)) { throw "missing: $p" }
    }

    . $CommonPath
    . $EvidencePath

    # git is the subject of half these cases. Without it, sections A and B would
    # report 'unknown' for the RIGHT verdict by the WRONG route - a program that
    # would not start rather than a program that started and found no repository
    # - and would be green while establishing nothing.
    $gitProbe = Invoke-LwgRptProcess -File 'git' -ProcArgs @('--version') -TimeoutMs 6000
    if ([string]$gitProbe.state -ne 'ok') {
        throw "git is not runnable here (state '$($gitProbe.state)'). Every case about exit 128 outside a repository needs a real git, so this is an abort rather than a skip"
    }

    $manifest = [IO.File]::ReadAllText($ManifestPath) | ConvertFrom-Json
    $items    = @($manifest.items)
    if ($items.Count -eq 0) { throw 'checklist.json parsed but declares no items' }

    $work = Join-Path ([IO.Path]::GetTempPath()) ('lwg-evstate-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
    [void][IO.Directory]::CreateDirectory($work)

    # --- the fixture: a plugin root that is not inside a repository ---------
    # Built by COPYING. Nothing is deleted to make it, and the source tree is
    # only ever read.
    $noRepo = Join-Path $work 'plugin-no-git'
    [void][IO.Directory]::CreateDirectory($noRepo)
    [void][IO.Directory]::CreateDirectory((Join-Path $noRepo 'bin'))
    [void][IO.Directory]::CreateDirectory((Join-Path $noRepo 'lib'))
    Copy-Item -LiteralPath $ManifestPath  -Destination (Join-Path $noRepo 'checklist.json')      -Force
    Copy-Item -LiteralPath $ChecklistPath -Destination (Join-Path $noRepo 'bin\lwg-checklist.ps1') -Force
    Copy-Item -LiteralPath $EvidencePath  -Destination (Join-Path $noRepo 'bin\lwg-evidence.ps1')  -Force
    Copy-Item -LiteralPath $CommonPath    -Destination (Join-Path $noRepo 'lib\common.ps1')        -Force
    if ([IO.File]::Exists($ConfigPath)) {
        Copy-Item -LiteralPath $ConfigPath -Destination (Join-Path $noRepo 'config.json') -Force
    }

    # THE FIXTURE ASSERTION, and it is the one that keeps this whole suite
    # honest. Get-LwgRepoInfo walks UP for a .git, so a temp directory that
    # happened to sit inside a checkout would give the fixture a repository, git
    # would answer every probe about SOME OTHER TREE, and section A would go
    # green having exercised nothing.
    $noRepoInfo = Get-LwgRepoInfo -Path $noRepo
    if (-not [string]::IsNullOrWhiteSpace([string]$noRepoInfo.root)) {
        throw "the scratch fixture at $noRepo resolves a git root at $($noRepoInfo.root), so it is not the no-repository fixture these cases need"
    }
    # And the mirror: the repo cases need a real checkout. Running this suite
    # from a copy that is not one would leave only the negative half, which is
    # exactly the shape that made the shipped defect invisible.
    $rootInfo = Get-LwgRepoInfo -Path $Root
    if ([string]::IsNullOrWhiteSpace([string]$rootInfo.root)) {
        throw "$Root is not inside a git checkout, so the cases that require a probe to REACH its question cannot run. Half a suite is not a suite"
    }

    # --- fixture programs ----------------------------------------------------
    # Tiny scripts with exactly the exit code and output each case needs. A real
    # command whose exit code happened to suit would make the case depend on that
    # command's behaviour instead of on the engine's.
    $fx = Join-Path $work 'fixtures'
    [void][IO.Directory]::CreateDirectory($fx)
    $fxSilent0 = Join-Path $fx 'exit0-silent.ps1'
    $fxToken0  = Join-Path $fx 'exit0-token.ps1'
    $fxSilent1 = Join-Path $fx 'exit1-silent.ps1'
    $fxSilent7 = Join-Path $fx 'exit7-silent.ps1'
    $fxAbsent  = Join-Path $fx 'this-script-is-not-installed.ps1'
    $enc = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($fxSilent0, "exit 0`r`n", $enc)
    [IO.File]::WriteAllText($fxToken0,  "Write-Output 'LWG-FIXTURE-TOKEN'`r`nexit 0`r`n", $enc)
    [IO.File]::WriteAllText($fxSilent1, "exit 1`r`n", $enc)
    [IO.File]::WriteAllText($fxSilent7, "exit 7`r`n", $enc)
    if ([IO.File]::Exists($fxAbsent)) { throw "the 'absent script' fixture exists at $fxAbsent, so its case would test the opposite of what it says" }

    $ctxNoRepo = New-LwgEvidenceContext -PluginRoot $noRepo
    $ctxRepo   = New-LwgEvidenceContext -PluginRoot $Root

    $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File')

    # -------------------------------------------------------------------
    # A. THE BLOCKER. The rules that ship, evaluated where there is no
    #    repository. Every case here was RED before the fix, reporting
    #    'fail' - which the checklist renders as `[ ] NOT STARTED`, which
    #    the product defines as "a probe RAN and found the thing absent".
    # -------------------------------------------------------------------
    $ruleIdentity = Get-ShippedRule -Id 'P3-identity'     -Items $items
    $ruleSibling  = Get-ShippedRule -Id 'P3-sibling-name' -Items $items

    $rA1 = Test-LwgEvidence -Ctx $ctxNoRepo -Ev $ruleIdentity
    $v = Test-State -Result $rA1 -Want 'unknown'
    Add-Result "A1  P3-identity's shipped rule, no .git anywhere above it -> unknown" $v.ok `
        ("$($v.why)  --  'fail' here renders as NOT STARTED, which tells a consumer the owner's personal address WAS left in history. Nothing measured it")

    Add-Result 'A2  and its detail names git declining, not the thing being absent' `
        ([string]$rA1.detail -match 'without reaching a repository' -and [string]$rA1.detail -match 'never looked') `
        ("the detail was: $([string]$rA1.detail)  --  an UNVERIFIED row whose detail does not say WHY is a row an operator cannot act on, and 'unknown' reached by some other route would pass A1 while establishing nothing")

    $rA3 = Test-LwgEvidence -Ctx $ctxNoRepo -Ev $ruleSibling
    $v = Test-State -Result $rA3 -Want 'unknown'
    Add-Result "A3  P3-sibling-name's shipped rule (expect_exit 1), no .git -> unknown" $v.ok `
        ("$($v.why)  --  this rule PASSES on exit 1, so outside a repository the 128 is not merely unexpected, it is the opposite verdict: rendered NOT STARTED it says the private sibling project's name IS in the tree")

    Add-Result 'A4  and its detail names git declining too' `
        ([string]$rA3.detail -match 'without reaching a repository') `
        ("the detail was: $([string]$rA3.detail)")

    # -------------------------------------------------------------------
    # B. THE MIRROR. The same two shipped rules against this checkout,
    #    where git CAN reach the question. If the fix had been "answer
    #    unknown to anything git-shaped", these two would be red.
    # -------------------------------------------------------------------
    # B1's assertion was `[string]$rB1.state -ne 'unknown'` until 3 August 2026,
    # which is a bare negative satisfied by every state except one. Measured
    # against degenerate results: $null, @{}, state='', state='error' and
    # state='fail' ALL passed it, so a change that made the evaluator return
    # nothing at all would have left this case green. Positive now, and the same
    # shape B2 twenty lines down already used.
    #
    # THIS DOES NOT MAKE SECTION B REACH THE CODE IT IS NAMED FOR, and reading
    # it as though it does is the mistake to avoid. B1 and B2 both exit with
    # exactly the code their rule declared - P3-identity wants 0 and git log
    # exits 0, P3-sibling-name wants 1 and git grep exits 1 - so
    # `$res.code -ne $want` at bin\lwg-evidence.ps1:552 is FALSE for both, and
    # the unreachable ladder behind it, where Get-LwgProbeUnreachable and the
    # whole 31 July fix live, is never entered by either. Section B's stated job
    # is to catch a blanket-unverify introduced INSIDE that ladder, and neither
    # case can, because neither gets there. Closing that needs a third case in
    # this section using a rule that reaches its question and answers no; no
    # shipped rule in checklist.json can do it (checked: every kind: command
    # rule either exits the code it declared in a healthy checkout, or carries
    # nonzero_means 'unverified'), so it needs a constructed rule and a case of
    # its own. That is still open.
    $rB1 = Test-LwgEvidence -Ctx $ctxRepo -Ev $ruleIdentity
    $v = Test-State -Result $rB1 -Want 'pass'
    Add-Result 'B1  P3-identity in a real checkout -> pass, a real verdict rather than any non-unknown state' $v.ok `
        ("$($v.why)  --  the fix must not blanket-unverify git. A checklist that can never say anything about history reports nothing. If this is 'fail', that is the rule working: the owner's address is in the history it scanned")

    $rB2 = Test-LwgEvidence -Ctx $ctxRepo -Ev $ruleSibling
    $v = Test-State -Result $rB2 -Want 'pass'
    Add-Result 'B2  P3-sibling-name in a real checkout -> pass (git grep exits 1: no occurrence)' $v.ok `
        ("$($v.why)  --  if this is 'fail', that is not a bug in the engine: the private sibling project's name is in the tracked tree and the rule is working")

    # -------------------------------------------------------------------
    # C. THE OTHER WAYS A PROBE NEVER REACHES ITS QUESTION.
    # -------------------------------------------------------------------
    $rC1 = Test-LwgEvidence -Ctx $ctxNoRepo -Ev (New-Rule @{
        kind = 'command'; file = 'lwg-no-such-program-fixture'; args = @('--version'); expect_exit = 0; timeout_ms = 6000 })
    $v = Test-State -Result $rC1 -Want 'unknown'
    Add-Result 'C1  a rule naming a program that does not exist -> unknown' $v.ok `
        ("$($v.why)  --  a tool that will not start has answered nothing")

    $rC2 = Test-LwgEvidence -Ctx $ctxNoRepo -Ev (New-Rule @{
        kind = 'command'; file = 'powershell'; args = @($psArgs + $fxAbsent); expect_exit = 0; timeout_ms = 20000 })
    $v = Test-State -Result $rC2 -Want 'unknown'
    Add-Result 'C2  a rule whose -File script is not installed -> unknown' $v.ok `
        ("$($v.why)  --  powershell starts fine and then refuses, so this is NOT the 'missing program' case. checklist.json runs tests\workflow_guard.ps1 this way, and 'the suite is not installed' must not read as 'the suite found a violation'")

    $rC3 = Test-LwgEvidence -Ctx $ctxNoRepo -Ev (New-Rule @{
        kind = 'command'; file = 'powershell'; args = @($psArgs + $fxSilent7); expect_exit = 0
        nonzero_means = 'unverified'; timeout_ms = 20000 })
    $v = Test-State -Result $rC3 -Want 'unknown'
    Add-Result "C3  nonzero_means 'unverified' still honoured (exit 7, rule wanted 0) -> unknown" $v.ok `
        ("$($v.why)  --  this knob predates the fix and two shipped gh rules depend on it. The new checks run BEFORE it and must not have displaced it")

    # -------------------------------------------------------------------
    # D. FINDINGS ARE STILL FINDINGS. The half that stops this fix from
    #    becoming a worse defect than the one it replaced.
    # -------------------------------------------------------------------
    $rD1 = Test-LwgEvidence -Ctx $ctxNoRepo -Ev (New-Rule @{
        kind = 'command'; file = 'powershell'; args = @($psArgs + $fxSilent1); expect_exit = 1; timeout_ms = 20000 })
    $v = Test-State -Result $rD1 -Want 'pass'
    Add-Result 'D1  expect_exit 1 genuinely met -> pass' $v.ok `
        ("$($v.why)  --  a rule whose pass IS a nonzero exit must not be caught by any of the new could-not-run checks")

    $rD2 = Test-LwgEvidence -Ctx $ctxNoRepo -Ev (New-Rule @{
        kind = 'command'; file = 'powershell'; args = @($psArgs + $fxSilent7); expect_exit = 0; timeout_ms = 20000 })
    $v = Test-State -Result $rD2 -Want 'fail'
    Add-Result 'D2  an unexpected exit with no could-not-run signal -> fail' $v.ok `
        ("$($v.why)  --  the program ran, reached the question and answered no. Reporting that as unverified would launder every real failure")

    $rD3 = Test-LwgEvidence -Ctx $ctxNoRepo -Ev (New-Rule @{
        kind = 'command'; file = 'powershell'; args = @($psArgs + $fxToken0); expect_exit = 0
        stdout_match = 'LWG-PATTERN-THAT-IS-NOT-THERE'; timeout_ms = 20000 })
    $v = Test-State -Result $rD3 -Want 'fail'
    Add-Result 'D3  output present and NOT matching stdout_match -> fail' $v.ok `
        ("$($v.why)  --  there was output to judge, and it did not match. That is a finding, not a gap")

    $rD4 = Test-LwgEvidence -Ctx $ctxNoRepo -Ev (New-Rule @{
        kind = 'command'; file = 'powershell'; args = @($psArgs + $fxToken0); expect_exit = 0
        stdout_not_match = 'LWG-FIXTURE-TOKEN'; timeout_ms = 20000 })
    $v = Test-State -Result $rD4 -Want 'fail'
    Add-Result 'D4  output that still matches stdout_not_match -> fail' $v.ok $v.why

    # -------------------------------------------------------------------
    # E. EMPTY OUTPUT. The gap checklist.json's P8-tag caveat carried in
    #    writing from the day that rule was written: `git tag -l` exits 0
    #    with empty stdout on a clone whose tags were never fetched.
    # -------------------------------------------------------------------
    $rE1 = Test-LwgEvidence -Ctx $ctxNoRepo -Ev (New-Rule @{
        kind = 'command'; file = 'powershell'; args = @($psArgs + $fxSilent0); expect_exit = 0
        stdout_match = 'LWG-FIXTURE-TOKEN'; timeout_ms = 20000 })
    $v = Test-State -Result $rE1 -Want 'unknown'
    Add-Result 'E1  expected exit, EMPTY stdout, rule proves the item from stdout -> unknown' $v.ok `
        ("$($v.why)  --  a pattern cannot be settled either way against output that does not exist. This was 'fail', and on a --no-tags clone it told the reader no release had been cut")

    $rE2 = Test-LwgEvidence -Ctx $ctxNoRepo -Ev (New-Rule @{
        kind = 'command'; file = 'powershell'; args = @($psArgs + $fxSilent0); expect_exit = 0
        stdout_not_match = 'LWG-FIXTURE-TOKEN'; timeout_ms = 20000 })
    $v = Test-State -Result $rE2 -Want 'pass'
    Add-Result 'E2  empty stdout under stdout_not_match ALONE -> pass, deliberately' $v.ok `
        ("$($v.why)  --  a probe that lists offenders and lists none is answering, and refusing that would manufacture UNVERIFIED rows out of correct answers. The rule that wants both readings carries both keys")

    # -------------------------------------------------------------------
    # F. THE LADDER. Test-LwgEvidence decides 'unknown' vs 'fail';
    #    Resolve-LwgChecklist turns those into the words a reader sees.
    #    Both items go through ONE call, so no ordering or memoisation
    #    quirk can make one right at the other's expense.
    # -------------------------------------------------------------------
    $ladderItems = @(
        (New-Rule @{ id = 'FX-offrepo'; section = 'fixture'; title = 'a git rule with no repository to read'
                     evidence = @{ kind = 'command'; file = 'git'; args = @('--no-pager', 'log', '-n', '1', '--format=%H')
                                   expect_exit = 0; stdout_match = '[0-9a-f]{7}'; timeout_ms = 8000 } })
        (New-Rule @{ id = 'FX-genuine'; section = 'fixture'; title = 'a probe that ran and answered no'
                     evidence = @{ kind = 'command'; file = 'powershell'; args = @($psArgs + $fxSilent7)
                                   expect_exit = 0; timeout_ms = 20000 } })
    )
    $rows = @(Resolve-LwgChecklist -Ctx $ctxNoRepo -Items $ladderItems)

    $rowOff = @($rows | Where-Object { $_.Id -eq 'FX-offrepo' })[0]
    Add-Result 'F1  ladder: a probe that could not run renders UNVERIFIED' `
        ($null -ne $rowOff -and [string]$rowOff.State -eq 'UNVERIFIED') `
        ("rendered '$([string]$rowOff.State)': $([string]$rowOff.Detail)  --  rung 3 of the ladder, not rung 8")

    $rowGen = @($rows | Where-Object { $_.Id -eq 'FX-genuine' })[0]
    Add-Result 'F2  ladder: a probe that ran and failed still renders NOT STARTED' `
        ($null -ne $rowGen -and [string]$rowGen.State -eq 'NOT STARTED') `
        ("rendered '$([string]$rowGen.State)': $([string]$rowGen.Detail)  --  rung 8 must survive the fix, or the checklist loses the ability to report anything undone")

    # -------------------------------------------------------------------
    # G. END TO END, in a real child process, on the install shape that
    #    shipped the defect: a plugin directory with no `.git`. This is
    #    the case that reads the RENDERED MARK, which is what a consumer
    #    actually sees.
    # -------------------------------------------------------------------
    $childOut = ''
    $childCode = -1
    $prevPref = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $childOut = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $noRepo 'bin\lwg-checklist.ps1') | Out-String)
        $childCode = $(if ($null -eq $LASTEXITCODE) { 255 } else { $LASTEXITCODE })
    } finally {
        $ErrorActionPreference = $prevPref
    }

    Add-Result 'G1  the checklist still renders from a plugin root with no .git (exit 0)' `
        ($childCode -eq 0 -and $childOut -match '(?m)^\s+\d+ items from checklist\.json') `
        ("exit $childCode, and the output did not carry an item count. Output was:`n$childOut")

    foreach ($id in @('P3-identity', 'P3-sibling-name')) {
        Add-Result "G2  $id renders [?] UNVERIFIED there" `
            ($childOut -match ('(?m)^\s*\[\?\]\s+UNVERIFIED\s+' + [regex]::Escape($id) + '\s')) `
            ("no '[?] UNVERIFIED $id' row was printed. This is the consumer-visible half of the blocker")

        Add-Result "G3  $id is NOT rendered [ ] NOT STARTED there" `
            ($childOut -notmatch ('(?m)NOT STARTED\s+' + [regex]::Escape($id) + '\s')) `
            ("the row printed NOT STARTED, which the product defines as 'a probe RAN and found the thing absent'. Nothing ran")
    }

    # G4 WAS ONE ASSERTION UNTIL 3 AUGUST 2026, AND IT WAS THE WRONG HALF.
    # Its name claimed "renders UNVERIFIED, not NOT STARTED" and the case was a
    # bare -notmatch, which asserts only that one string is absent - so it passed
    # for every state in which that string does not appear, including the row
    # rendering DONE, the row rendering any other mark, the item being RENAMED,
    # the item being deleted from checklist.json, and lwg-checklist.ps1 printing
    # nothing at all. The last three are why it is a defect rather than a
    # stylistic gap: G4 stopped being about P6-workflow-guard the moment
    # P6-workflow-guard stopped existing, and said so by passing.
    #
    # The G2/G3 pair twelve lines up is the shape this should always have had, and
    # they were written as a pair on purpose - G3 alone has exactly this problem.
    # G4 is kept out of that loop rather than folded into it because its detail
    # string is the reason this item is in the fixture at all and is worth keeping
    # verbatim; the requirement was never the loop, it was the positive assertion.
    #
    # THE GENERAL RULE, stated here because this is where it was found: a case
    # whose name asserts "X, not Y" needs TWO assertions. Every way of the subject
    # not existing satisfies a bare -notmatch. That is the same failure this file
    # refuses one level up - the checklist rendering `[ ]` for a probe that never
    # ran - applied to the suite instead of to the engine. The other bare
    # negatives in tests\ were swept when this was found: gate_delegate.ps1's
    # `source: never reads agent_type` and `no shell: form anywhere in the entry`
    # each sit beside a positive case on the same subject, so both are sound.
    Add-Result 'G4  a rule whose suite is not installed renders [?] UNVERIFIED there' `
        ($childOut -match '(?m)^\s*\[\?\]\s+UNVERIFIED\s+P6-workflow-guard\s') `
        ("no '[?] UNVERIFIED P6-workflow-guard' row was printed. Without this half, G4b below passes for a row that renders DONE, for a row that was renamed, and for a row that is no longer in checklist.json at all")

    Add-Result 'G4b  and it is NOT rendered [ ] NOT STARTED there' `
        ($childOut -notmatch '(?m)NOT STARTED\s+P6-workflow-guard\s') `
        ('P6-workflow-guard printed NOT STARTED in a copy that carries no tests\ directory. Exit 1 from that rule means the guard found a violation; a guard that is not installed must not borrow that meaning')

    # The tally line itself, because it is what gets quoted. Nothing here
    # requires a particular number - only that no row reached NOT STARTED by
    # way of a probe that never ran, which on this fixture means none of the
    # git rules did.
    if ($childOut -match '(?m)^\s+(\d+) done\s+(\d+) in progress\s+(\d+) blocked\s+(\d+) UNVERIFIED\s+(\d+) not started') {
        Write-Output ("  note  fixture tally: {0} done, {1} in progress, {2} blocked, {3} UNVERIFIED, {4} not started" -f `
            $Matches[1], $Matches[2], $Matches[3], $Matches[4], $Matches[5])
    } else {
        Add-Result 'G5  the tally line is still printed' $false `
            "the count line could not be parsed out of the child's output, so G2-G4b read a report whose shape has changed"
    }

    # -------------------------------------------------------------------
    # H. WHAT A PROBE IS POINTED AT, AND HOW FAR IT LOOKED.
    #
    #    Sections A-G are all about ONE distinction - could not look versus
    #    looked and found nothing. Section H is about the two questions
    #    that come before it, and every case here is a defect this engine
    #    or this manifest actually had on 3 August 2026:
    #
    #      H1-H3   is the file the rule names the file that was read?
    #      H4-H5   did the scan reach far enough back to answer?
    #      H6-H9   does the rule assert the STRUCTURE it claims to?
    #      H10-H13 do the shipped rules test their own titles?
    #      H14-H16 does the documented off switch actually switch anything?
    #
    #    They live in this file rather than in a new suite on purpose. A
    #    ninth file under tests\ moves two counts - "files in tests/" and
    #    "behavioural suites" - that are stated across seven tracked pages,
    #    and tests\doc_claims.ps1 derives both from the tree.
    # -------------------------------------------------------------------

    # --- H1-H3: containment -------------------------------------------------
    # Resolve-LwgRptPath's test was a bare string prefix with no separator
    # boundary, so a SIBLING directory whose name merely extends the plugin
    # root's was "contained": with a root at ...\lw-watchtower, ...\lw-watchtower-fix\x
    # passed. The file was then read, matched and CITED as the evidence for a
    # DONE row - about a tree the operator is not running. Not an exotic shape
    # here: this repository's own fix work happens in a worktree beside the
    # checkout.
    $sibling = $noRepo + '-fix'
    [void][IO.Directory]::CreateDirectory((Join-Path $sibling 'docs'))
    $siblingFile = Join-Path $sibling 'docs\limitations.md'
    [IO.File]::WriteAllText($siblingFile, "a file in the OTHER checkout`r`n", $enc)

    $rH1 = Test-LwgEvidence -Ctx $ctxNoRepo -Ev (New-Rule @{
        kind = 'file'; paths = @('../' + [IO.Path]::GetFileName($sibling) + '/docs/limitations.md') })
    $v = Test-State -Result $rH1 -Want 'unknown'
    Add-Result 'H1  a path resolving into a SIBLING whose name extends the root is refused' $v.ok `
        ("$($v.why)  --  the file was read from a directory that is not the plugin root and the row would have cited it as evidence about this tree")

    Add-Result 'H2  and the refusal says the path was NOT read' `
        ([string]$rH1.detail -match 'outside the plugin root' -and [string]$rH1.detail -match 'NOT read') `
        ("the detail was: $([string]$rH1.detail)  --  a refusal an operator cannot act on is a refusal that will be read as a missing file")

    $rH3 = Test-LwgEvidence -Ctx $ctxNoRepo -Ev (New-Rule @{
        kind = 'file'; paths = @((Join-Path $noRepo 'checklist.json')) })
    $v = Test-State -Result $rH3 -Want 'unknown'
    Add-Result 'H3  a ROOTED manifest path is refused even when it lands inside the root' $v.ok `
        ("$($v.why)  --  [IO.Path]::Combine returns a rooted argument unchanged, so an absolute path never gets joined under the root at all. A manifest naming one is a manifest error, and refusing it by name beats normalising it and hoping the boundary test catches it")

    $rH3b = Test-LwgEvidence -Ctx $ctxNoRepo -Ev (New-Rule @{ kind = 'file'; paths = @('checklist.json') })
    $v = Test-State -Result $rH3b -Want 'pass'
    Add-Result 'H3b  an ordinary relative path inside the root still resolves and is read' $v.ok `
        ("$($v.why)  --  the mirror. Anchoring containment on a separator makes the ROOT ITSELF fail the test, so this is the case that would go red if that anchoring were applied somewhere it should not be")

    # --- H4-H5: how far back the commit scan looked -------------------------
    # Get-LwgRptCommits reads a bounded window. A miss inside a FULL window is a
    # scan that stopped where it was told, not an absence - and it used to return
    # 'fail', which renders `[ ] NOT STARTED`: the could-not-look-scored-as-a-
    # finding shape this file's whole subject is, one evaluator along from the one
    # it was written for.
    $rH4 = Test-LwgEvidence -Ctx $ctxRepo -Ev (New-Rule @{
        kind = 'commit'; ref = 'HEAD'; match = 'LWG-SUBJECT-THAT-IS-NOT-IN-ANY-COMMIT'; scan_limit = 1 })
    $v = Test-State -Result $rH4 -Want 'unknown'
    Add-Result 'H4  a commit rule that missed inside a FULL scan window -> unknown' $v.ok `
        ("$($v.why)  --  'fail' here renders NOT STARTED, which the product defines as 'a probe RAN and found the thing absent'. The scan was truncated; absence was never established")

    Add-Result 'H5  and its detail names the window rather than only the miss' `
        ([string]$rH4.detail -match 'came back full' -and [string]$rH4.detail -match 'scan_limit') `
        ("the detail was: $([string]$rH4.detail)  --  the old detail did say 'N commits scanned', in the row body, next to a checkbox that had already said the opposite")

    $rH6 = Test-LwgEvidence -Ctx $ctxRepo -Ev (New-Rule @{
        kind = 'commit'; ref = 'HEAD'; match = 'LWG-SUBJECT-THAT-IS-NOT-IN-ANY-COMMIT'; scan_limit = 100000 })
    $v = Test-State -Result $rH6 -Want 'fail'
    Add-Result 'H5b  a miss in a scan that reached the root of history is STILL a finding' $v.ok `
        ("$($v.why)  --  the other half, and the half that matters more. A checklist that can never say a thing is undone reports nothing at all")

    # --- H6-H9: the delegate gate's registration ----------------------------
    # PD-delegate is the row attesting this plugin's only blocking component. Its
    # rule was a (?s) regex over the raw text of hooks/hooks.json whose three
    # fragments were bound to nothing - so the gate registered on PostToolUse,
    # which runs AFTER the tool call and can refuse nothing, satisfied it.
    $itemDelegate = Get-ShippedItem -Id 'PD-delegate' -Kind 'hook' -Items $items
    $ruleDelegate = $itemDelegate.evidence

    $rH6a = Test-LwgEvidence -Ctx $ctxRepo -Ev $ruleDelegate
    $v = Test-State -Result $rH6a -Want 'pass'
    Add-Result "H6  PD-delegate's shipped rule passes against this tree's real hooks.json" $v.ok `
        ("$($v.why)  --  if this is 'fail' that is not a bug in the case: hooks/hooks.json no longer registers lib/gate_delegate.ps1 on PreToolUse with a matcher naming every tool the row's caveat claims")

    # A registration that cannot refuse anything, in the shape a contributor
    # would actually produce: nine of the ten registrations in that file are
    # post-hoc observers and the block ordering invites the mistake.
    $hookFx = Join-Path $work 'hooks-postonly'
    [void][IO.Directory]::CreateDirectory((Join-Path $hookFx 'hooks'))
    [IO.File]::WriteAllText((Join-Path $hookFx 'hooks\hooks.json'), (@'
{
  "hooks": {
    "PreToolUse": [],
    "PostToolUse": [
      { "matcher": "Edit|Write|NotebookEdit|Bash|PowerShell",
        "hooks": [ { "type": "command", "command": "powershell",
                     "args": [ "-File", "${CLAUDE_PLUGIN_ROOT}/lib/gate_delegate.ps1" ] } ] }
    ]
  }
}
'@), $enc)
    $rH7 = Test-LwgEvidence -Ctx (New-LwgEvidenceContext -PluginRoot $hookFx) -Ev $ruleDelegate
    $v = Test-State -Result $rH7 -Want 'fail'
    Add-Result 'H7  the gate registered on PostToolUse instead of PreToolUse -> fail' $v.ok `
        ("$($v.why)  --  PostToolUse fires after the tool call has already run, so this plugin refuses NOTHING in that state. The old regex reported the row DONE over it")

    # The narrowing case: registered on the right event, one tool short.
    $hookFx2 = Join-Path $work 'hooks-narrow'
    [void][IO.Directory]::CreateDirectory((Join-Path $hookFx2 'hooks'))
    [IO.File]::WriteAllText((Join-Path $hookFx2 'hooks\hooks.json'), (@'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Edit|Write|NotebookEdit|Bash",
        "hooks": [ { "type": "command", "command": "powershell",
                     "args": [ "-File", "${CLAUDE_PLUGIN_ROOT}/lib/gate_delegate.ps1" ] } ] }
    ]
  }
}
'@), $enc)
    $rH8 = Test-LwgEvidence -Ctx (New-LwgEvidenceContext -PluginRoot $hookFx2) -Ev $ruleDelegate
    $v = Test-State -Result $rH8 -Want 'fail'
    Add-Result 'H8  a PreToolUse matcher one tool short of the caveat -> fail' $v.ok `
        ("$($v.why)  --  the matcher is the only place the gate's tool coverage is expressed. This is the exact shape of the PowerShell hole closed on 1 August 2026, and the manifest could not see it")

    Add-Result 'H9  and the failure names the tool that is missing' `
        ([string]$rH8.detail -match 'PowerShell') `
        ("the detail was: $([string]$rH8.detail)  --  'the matcher is wrong' is not actionable; 'the matcher is missing PowerShell' is")

    # --- H10-H13: shipped rules that must test their own titles -------------
    # P1-lineendings asks whether two files AGREE and proved only that both
    # exist: 'file' evidence opens nothing unless contains/not_contains is set.
    $itemLineEnd = Get-ShippedItem -Id 'P1-lineendings' -Kind 'file' -Items $items
    $ruleLineEnd = $itemLineEnd.evidence

    $leOk = Join-Path $work 'lineendings-agree'
    [void][IO.Directory]::CreateDirectory($leOk)
    [IO.File]::WriteAllText((Join-Path $leOk '.gitattributes'),
        "* text=auto eol=lf`nstatusline/statusline.ps1 text eol=lf`n", $enc)
    [IO.File]::WriteAllText((Join-Path $leOk '.editorconfig'),
        "[*]`nend_of_line = lf`n`n[statusline/statusline.ps1]`nend_of_line = lf`n", $enc)
    $v = Test-State -Result (Test-LwgEvidence -Ctx (New-LwgEvidenceContext -PluginRoot $leOk) -Ev $ruleLineEnd) -Want 'pass'
    Add-Result 'H10  P1-lineendings passes where both files carry the statusline LF pin' $v.ok `
        ("$($v.why)  --  the two files are written in different syntaxes and one `contains` is applied to both, so this is the case that fails if the shared pattern stops fitting either one")

    # The disagreement the row is named after: the pin dropped from ONE file.
    $leBad = Join-Path $work 'lineendings-disagree'
    [void][IO.Directory]::CreateDirectory($leBad)
    [IO.File]::WriteAllText((Join-Path $leBad '.gitattributes'),
        "* text=auto eol=lf`nstatusline/statusline.ps1 text eol=lf`n", $enc)
    [IO.File]::WriteAllText((Join-Path $leBad '.editorconfig'),
        "[*]`nend_of_line = lf`n", $enc)
    $rH11 = Test-LwgEvidence -Ctx (New-LwgEvidenceContext -PluginRoot $leBad) -Ev $ruleLineEnd
    $v = Test-State -Result $rH11 -Want 'fail'
    Add-Result 'H11  P1-lineendings FAILS when only one of the two files carries the pin' $v.ok `
        ("$($v.why)  --  both files exist, so an existence-only rule reports the disagreement its own title is named after as settled. docs/install.md records what that pin buys: without it the doctor's Get-FileHash drift check reports drift on every fresh clone")

    # PE-checklist proved itself from a commit subject matching the bare feature
    # name, which a commit DELETING the feature satisfies. Swept as a class
    # rather than fixed as an instance, because that is what PE-sitrep's caveat
    # said nobody had done.
    $looseCommit = @()
    foreach ($it in $items) {
        $ev = $it.evidence
        if ($null -eq $ev -or [string]$ev.kind -ne 'commit') { continue }
        # Inline mode flags are not part of the phrase - (?i) would otherwise
        # count as a word and lift a bare feature name over the bar on its own.
        $bare   = ([string]$ev.match) -replace '\(\?[imsx]+\)', ''
        $tokens = @([regex]::Matches($bare, '[A-Za-z]{2,}'))
        if ($tokens.Count -lt 3) { $looseCommit += ("{0} (match /{1}/, {2} word(s))" -f $it.id, [string]$ev.match, $tokens.Count) }
    }
    Add-Result 'H12  no kind:commit rule proves itself from a bare feature name' `
        ($looseCommit.Count -eq 0) `
        ("these rules are satisfied by any commit whose subject mentions the word, INCLUDING one that deletes the feature: $($looseCommit -join '; ')  --  the bar is three words of two or more letters, which is a HEURISTIC that bounds the shape and does not remove it: a subject pattern is subject-satisfiable whatever it says, and this case cannot tell an accurate subject from an inaccurate one")

    # P5-setup ticks five behavioural properties of a 1,700-line installer on the
    # evidence that two files exist, and carried no caveat at all until 3 August
    # 2026 - the largest unqualified claim in the manifest.
    $itemSetup = Get-ShippedItem -Id 'P5-setup' -Kind 'file' -Items $items
    $rowSetup  = @(Resolve-LwgChecklist -Ctx $ctxRepo -Items @($itemSetup))[0]
    Add-Result 'H13  P5-setup renders DONE with a caveat, never a bare tick' `
        ($null -ne $rowSetup -and [string]$rowSetup.State -eq 'DONE' -and -not [string]::IsNullOrWhiteSpace([string]$rowSetup.Caveat)) `
        ("rendered '$([string]$rowSetup.State)' with caveat '$([string]$rowSetup.Caveat)'  --  bin\lwg-checklist.ps1 marks a caveated DONE `[x*]` and a bare one `[x]`, so with no caveat this row prints as a full claim that per-section confirmation, diff-before-write, backup, rollback and never-clobber all hold, on the evidence that two paths are files")

    # --- H14-H16: the documented gh off switch ------------------------------
    # docs/install.md told an installer that use_gh: false "removes it entirely".
    # The key had ONE reader - git_hygiene's open-PR check - and three further
    # sites shelled out to gh regardless. A switch wired to nothing, wearing the
    # name of a switch that works.
    $ctxNoGh = New-LwgEvidenceContext -PluginRoot $Root
    $ctxNoGh.use_gh = $false

    $rH14 = Test-LwgEvidence -Ctx $ctxNoGh -Ev (New-Rule @{ kind = 'ci'; workflow = 'CI'; branch = 'main' })
    $v = Test-State -Result $rH14 -Want 'unknown'
    Add-Result 'H14  a kind:ci rule with use_gh off -> unknown, and no gh is spawned' `
        ($v.ok -and [string]$rH14.detail -match 'use_gh' -and [int]$ctxNoGh.spawned -eq 0) `
        ("$($v.why)  --  detail was: $([string]$rH14.detail); the context spawned $([int]$ctxNoGh.spawned) child process(es), and any is one too many for a tool the operator switched off")

    $rH15 = Test-LwgEvidence -Ctx $ctxNoGh -Ev (New-Rule @{
        kind = 'command'; file = 'gh'; args = @('repo', 'view'); expect_exit = 0; timeout_ms = 8000 })
    $v = Test-State -Result $rH15 -Want 'unknown'
    Add-Result 'H15  a kind:command rule naming gh with use_gh off -> unknown, nothing spawned' `
        ($v.ok -and [string]$rH15.detail -match 'use_gh' -and [int]$ctxNoGh.spawned -eq 0) `
        ("$($v.why)  --  detail was: $([string]$rH15.detail); spawned $([int]$ctxNoGh.spawned). Two shipped rows run gh against a repository named in this manifest, so on a consumer's machine this is an authenticated outbound call they did not ask for")

    # The mirror: with the switch in its shipped position the rule is NOT
    # short-circuited. Deliberately asserted on the DETAIL and not on the state,
    # because whether gh is installed on the machine running this suite is not
    # something the suite gets to require.
    $ctxGh = New-LwgEvidenceContext -PluginRoot $Root
    $ctxGh.use_gh = $true
    $rH16 = Test-LwgEvidence -Ctx $ctxGh -Ev (New-Rule @{
        kind = 'command'; file = 'gh'; args = @('--version'); expect_exit = 0; timeout_ms = 8000 })
    Add-Result 'H16  with use_gh on, a gh rule is not short-circuited' `
        ([string]$rH16.detail -notmatch 'use_gh') `
        ("the detail was: $([string]$rH16.detail)  --  gating every gh rule unconditionally would make the switch a way to make rows disappear rather than a way to remove a dependency")

    # --- H17-H21: the two literals the manifest must not spell ---------------
    # checklist.json's two NEGATIVE rules used to spell their own targets in
    # reading order, in a tracked file that ships in the plugin payload, and
    # /lw-watchtower:checklist PRINTED both in the rendered row - so the row asserting
    # the private sibling project's name is absent published that name on every
    # machine that ran the command. Both are now stored rot13-encoded and decoded
    # by Expand-LwgRptLiteral at the moment they are applied.
    #
    # THE NEEDLES BELOW ARE ROT13 TOO, for the same reason and by the same
    # helper: a case that searched for a plain literal would put the literal back
    # into a tracked file, which is the defect it is testing for.
    #
    # H19/H20 ARE THE CASES THIS CHANGE MADE NECESSARY, and they matter more than
    # the disclosure ones. A decode that silently produced the WRONG string would
    # leave `git grep -e <garbage>` exiting 1 - which is P3-sibling-name's PASS
    # condition - so a broken decoder turns the row permanently and silently
    # green. Round-tripping the encoder cannot catch that. What catches it is
    # asserting the decoded PATTERN still matches a decoded SAMPLE of the thing it
    # exists to find.
    $needleSibling = Expand-LwgRptLiteral -Text 'rot13:yrncpbegrk'
    $needleAddress = Expand-LwgRptLiteral -Text 'rot13:ovm_grpu_rkrp'

    # READING ORDER, NOT `grep`. The criterion is what a HUMAN, an indexer or a
    # model gets by reading left to right - which is what the bracket-class
    # construction failed while satisfying every literal search. So single-letter
    # character classes are collapsed to their first letter before the needle is
    # looked for: `[Ff][Oo][Oo]...` reduces to `FOO...` and is caught. A plain
    # literal is caught with no reduction at all. This is a NARROW reduction and
    # is not a general obfuscation detector - it knows about one construction,
    # the one this manifest actually used.
    #
    # THE ILLUSTRATION USES NEUTRAL LETTERS ON PURPOSE, since 3 August 2026. It
    # used to be written with the first three letters of the name the removed
    # construction spelled. Those three letters are also the first three of the
    # PUBLISHER's name, so they disclosed nothing on their own - but they matched
    # the by-hand pre-publication sweep for that bracket construction, which
    # cannot distinguish a prose example from a real obfuscated name. A sweep
    # that always returns the same explained-away hits is a sweep people learn to
    # wave through. The letters carry no part of the argument, so they were
    # changed and the sweep now answers zero. Get-ReadingOrder below is UNCHANGED
    # by that edit and still collapses any single-letter class, which is what
    # actually enforces the property; the sweep is a second pair of eyes, not the
    # mechanism.
    function Get-ReadingOrder {
        param([string]$Text)
        if ([string]::IsNullOrEmpty($Text)) { return '' }
        return [regex]::Replace($Text, '\[([A-Za-z])[A-Za-z]?\]', '$1')
    }

    $manifestFlat = Get-ReadingOrder -Text ([IO.File]::ReadAllText($ManifestPath))
    Add-Result 'H17  checklist.json spells neither target in reading order' `
        ($manifestFlat -notmatch ('(?i)' + [regex]::Escape($needleSibling)) -and
         $manifestFlat -notmatch ('(?i)' + [regex]::Escape($needleAddress))) `
        ('the tracked manifest spells one of the two targets in reading order, as a plain literal or as a per-letter character class. It ships in the plugin payload and its rows are printed to the operator, so a reader, an indexer or a model gets the string for free - and a git filter-repo --replace-text pass, which matches literals, walks past the class form and reports success on exactly the input designed to defeat it')

    Add-Result 'H18  and neither does this suite' `
        (([IO.File]::ReadAllText($PSCommandPath)) -notmatch ('(?i)' + [regex]::Escape($needleSibling))) `
        ('the case written to check that no tracked file spells the name spells it itself, which is the defect wearing a test as a disguise')

    $patSibling = Expand-LwgRptLiteral -Text ([string]@($ruleSibling.args)[-1])
    Add-Result 'H19  the decoded sibling-name pattern still matches what it must find' `
        ($needleSibling -match $patSibling -and $needleSibling.ToUpperInvariant() -match $patSibling) `
        ("the decoded pattern does not match the target it exists to find, in either case. P3-sibling-name PASSES on `git grep` exiting 1, so a decoder that produced garbage would make this row permanently and silently green - the exact 'reports healthy while doing nothing' shape this plugin is named for, introduced by the fix for a disclosure")

    $patAddress = Expand-LwgRptLiteral -Text ([string]$ruleIdentity.stdout_not_match)
    Add-Result 'H20  the decoded address pattern still matches what it must find' `
        ($needleAddress -match $patAddress -and $needleAddress.ToUpperInvariant() -match $patAddress) `
        ('the decoded stdout_not_match does not match the local-part it exists to exclude, so P3-identity would pass over a history that still carried it')

    $rH21 = Test-LwgEvidence -Ctx $ctxRepo -Ev $ruleSibling
    Add-Result 'H21  the rendered detail does not spell the name in reading order either' `
        ((Get-ReadingOrder -Text ([string]$rH21.detail)) -notmatch ('(?i)' + [regex]::Escape($needleSibling))) `
        ("the detail was: $([string]$rH21.detail)  --  this string is what /lw-watchtower:checklist prints under the row on every machine that runs it, so the row asserting the name is ABSENT was the one publishing it. Decoding for DISPLAY as well as for execution would put it straight back")

} catch {
    $script:Aborted = "$($_.Exception.Message)  [line $($_.InvocationInfo.ScriptLineNumber)]"
} finally {
    # Best effort, and deliberately narrow: one directory this script created
    # under the temp root, by a name it generated. Never recursive over anything
    # it was given.
    if ($work -and [IO.Directory]::Exists($work)) {
        try { [IO.Directory]::Delete($work, $true) } catch { }
    }
}

$sw.Stop()
$fail = @($script:Results | Where-Object { -not $_.ok })

Write-Output ''
Write-Output '==========================================================================='

if ($script:Aborted) {
    Write-Output "ABORTED: $($script:Aborted)"
    Write-Output "$($script:Results.Count) case(s) had run. The suite did NOT complete, so nothing above is a verdict."
    Write-Output 'EXIT: 2'
    exit 2
}

if ($script:Results.Count -eq 0) {
    # Zero cases is an abort wearing a pass's clothes - the empty-set pass this
    # repo has been bitten by before.
    Write-Output 'ABORTED: no case ran at all, so nothing was established.'
    Write-Output 'EXIT: 2'
    exit 2
}

Write-Output ("RESULT: {0} of {1} case(s) passed in {2} ms" -f $script:Pass, $script:Results.Count, [int]$sw.Elapsed.TotalMilliseconds)

if ($fail.Count -gt 0) {
    Write-Output ''
    Write-Output "$($fail.Count) FAILED:"
    foreach ($f in $fail) { Write-Output ("  - {0}: {1}" -f $f.name, $f.detail) }
    Write-Output 'EXIT: 1'
    exit 1
}

Write-Output ''
Write-Output 'Every case above passed. Read that as "the engine tells these five could-not-run'
Write-Output 'signals from a finding", not as "it can always tell the difference" - see the header.'
Write-Output 'EXIT: 0'
exit 0
