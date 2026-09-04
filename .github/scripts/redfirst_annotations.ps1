#requires -version 5
<#
  LW-WATCHTOWER red-first annotation guard.

      powershell -NoProfile -ExecutionPolicy Bypass -File .github\scripts\redfirst_annotations.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File .github\scripts\redfirst_annotations.ps1 -Live

  WHY THIS FILE EXISTS

  This project's closure rule is red-first: a fix closes an issue when a case
  FAILS at a named baseline and passes with the fix. The claim is written in the
  suite, beside the case, as an annotation - "RED AT ec80e88", "confirmed RED AT
  fd8d023", "the red-first proof for this defect is M1".

  **Nothing checked those sentences.** #152 item 1 was an annotation pointing at
  a case that passed at the baseline it cited, and it was found by a person
  reading the file. Twenty-nine vacuous cases were found across eight suites the
  same way once. An annotation is evidence a reader trusts without re-running
  anything, so an annotation nothing checks is the same shape as the evidence
  rule tests\workflow_guard.ps1 replaced: a claim of a verified property, and no
  verification.

  WHAT THIS CAN AND CANNOT ESTABLISH, STATED FIRST BECAUSE IT IS THE WHOLE LIMIT

  It CANNOT re-run a baseline. No clone in this project reaches fd8d023 - see
  #153 - and a guard that tried would be red on every machine for a reason no
  contributor can fix. So this checks the SHAPE of the claim, never its truth:

    * an annotation that cites a baseline must actually cite one, as a SHA;
    * a case id an annotation names must be a case that EXISTS in that suite.

  An annotation citing a real SHA against a case that could never have failed
  there passes this guard and is still wrong. That is #152 item 1's exact shape
  and this file does not close it. What it closes is the cheaper half: a
  citation that names nothing, and a reference to a case that is not there -
  which is what a renamed or deleted case leaves behind.

  WHAT COUNTS AS AN ANNOTATION - MEASURED, NOT ASSUMED

  Measured over tests\*.ps1 at 4342980 by matching every line mentioning `red`
  and reading them. TWO SETS, because the two rules can honestly check different
  things:

    BASELINE-CITING (rule 1): a line carrying `red-first` or `red at`. SIXTEEN
    at 4342980, in six suites - doc_claims 1, gate_delegate 1, setup_merge 5,
    stop_behaviour 7, toggle_behaviour 1, uninstall_footprint 1. These are the
    lines that name a commit, and a SHA is a thing a regex can require.

    CASE-REFERENCING (rule 2): a wider set - any line making a claim about a
    case being red, including `went red`, `goes red`, `CANNOT GO RED`,
    `confirmed red against`, `proved red against`. Rule 2 asks only whether the
    case ids on such a line exist, and that question is answerable whatever
    baseline the line names.

  WHAT IS DELIBERATELY OUT OF RULE 1'S REACH, AND IT IS NOT A SMALL SET. About
  eighteen lines name a baseline as a TREE rather than as a commit - "red
  against the pre-fix command", "red against the WORKING TREE as it stood after
  the four parallel fixes", "BASELINE: red against the working tree before this
  fix". Those are legitimate annotations and this guard cannot check them: the
  tree they name no longer exists anywhere, so there is no token to require and
  no way to tell a real one from an invented one. SAID PLAINLY: an annotation
  written in that form evades rule 1 entirely. Rule 2 still reads it.

  ONE MEASURED WRONG-ROUTE PASS, recorded rather than left to be discovered.
  tests\doc_claims.ps1:1240 says a case "can go red at a commit where the
  lookbehind is absent" - it names no commit at all. It passes rule 1 because
  its comment block says "THE BASELINE FOR THAT IS THE PRE-FIX WORKING TREE, NOT
  fd8d023", and the SHA in that NEGATION is what the rule finds. The rule looks
  for a SHA in the block, not for the SHA's grammatical role, and it is the
  right answer by the wrong route.

  WHY IT LIVES IN .github\scripts\ AND NOT IN tests\

  It asserts nothing about the plugin - it reads the test suites as text. Two
  documented numbers count the files in tests\ and the behavioural suites among
  them, so a file added there costs edits at both. Same reason, and the same
  place, as .github\scripts\identity_scan.ps1 and .github\scripts\pr_issue_ref.ps1.

  THE LEDGER, AND WHY A ZERO IS AN ABORT

  tests\doc_claims.ps1 found seven of its thirty-seven patterns matching nothing
  anywhere in the tree - rules that could not fail on any input the repository
  contained, with no line of output saying so. So each rule here reports how
  many annotations it actually checked, per suite, and a rule that checked NONE
  exits 2 naming itself.

  MEASURED at 4342980: rule 1 checks SIXTEEN annotations, rule 2 checks ELEVEN
  case references - nine in gate_delegate.ps1, two in stop_behaviour.ps1. Eight
  of the fourteen suites contribute nothing to either number, which is not a
  defect: most of them annotate a tree rather than a commit, and several name
  their cases in a shape rule 2 cannot read - doctor_behaviour.ps1 writes
  "CASE 16", not "C16", so its references are invisible here. A live pattern
  set is a floor, not a ceiling, and the per-suite table is printed so the
  floor is visible rather than summed away.

  EXIT CONTRACT, the same 0/1/2 every guard in this repository uses:

      0  every annotation checked has the shape it claims
      1  an annotation cites no baseline, or names a case that does not exist
      2  nothing was established: no suite was read, or a rule checked nothing

  No network. No writes outside a throwaway temp directory in fixture mode.
#>

[CmdletBinding()]
param(
    # DEFAULT is the fixture run, which plants suites carrying good and bad
    # annotations and proves each rule fires. -Live reads this repository's
    # tests\*.ps1. Same shape, and for the same reason, as
    # .github\scripts\identity_scan.ps1.
    [switch]$Live,

    # The directory of suites to read in -Live mode. A parameter so the guard
    # can be pointed at a planted directory, which is how it is proved to catch
    # anything at all.
    [string]$SuiteDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sw = [System.Diagnostics.Stopwatch]::StartNew()

# ---------------------------------------------------------------------------
# THE PATTERNS. Each is stated with what it was measured against, because a
# pattern nobody measured is the defect this file is about.
# ---------------------------------------------------------------------------

# Rule 1's set: a line claiming a baseline. `red-first` names the protocol;
# `red at` names a commit. Sixteen lines at 4342980.
$script:BaselineAnnotation = '(?i)\bred[- ]first\b|\bred\s+at\b'

# Rule 2's set: any line making a claim about a case going red, whatever
# baseline it names. Deliberately wider than rule 1's, and it includes the
# CANNOT-GO-RED disclaimers, which name case ids as often as the positive
# claims do and are just as capable of naming one that is gone.
$script:CaseAnnotation = '(?i)\bred[- ]first\b|\bred\s+(?:at|against)\b|\b(?:go|goes|going|went|was|were|is|are|confirmed|proved|proven|measured|turn|turns|turned)\s+(?:it\s+)?red\b'

# A commit SHA as this tree writes them: short hex, seven or more. It is
# deliberately not anchored to a length - the tree uses 7 and this repository's
# `git log` prints 7 - and it is deliberately hex-only, which is the one false
# PASS it can produce: an ordinary English word spelled out of the letters a-f
# and seven characters long would satisfy it. That direction is the safe one.
$script:ShaToken = '\b[0-9a-f]{7,40}\b'

# A case id as every suite in tests\ writes one: a capital, one or two digits,
# an optional lower-case discriminator. A1, J10, B25b, M1, K5. Anchored at both
# ends so `#152`, `v0.4.0`, a date and a lower-case SHA are none of them a case
# id.
#
# THE LOOKBEHIND IS A MEASURED FALSE POSITIVE, NOT A PRECAUTION. Without it this
# read `X4` as a case id out of tests\stop_behaviour.ps1:722, where the text is
# a .NET format specifier - '{0:X4}' -f [int]$_ - inside a failure message. A
# format specifier is a capital and a digit and nothing else distinguishes it,
# so the rule is positional: a case id is never preceded by `{` or `:`.
$script:CaseIdToken = '(?<![:{A-Za-z0-9_])[A-Z]\d{1,2}[a-z]?\b'

function Get-DeclaredCaseIds {
    <#
      Every case id a suite declares, taken from the LEADING token of every
      string literal in it.

      PARSED, NOT GREPPED, and for the same reason tests\workflow_guard.ps1
      parses YAML: a quoted string inside a comment, or an apostrophe inside a
      double-quoted message, defeats a regex over quotes. ci.yml's PowerShell
      parse step already establishes that every file here parses, so this
      cannot be the thing that fails.

      A SUPERSET IS THE RIGHT DIRECTION. Every case title is a string literal,
      but not every string literal is a case title, so an id found here may
      belong to a message rather than to a case. The question asked of it is
      only "does this id exist in this suite" - a superset can produce a false
      PASS and never a false FAIL, and a false FAIL on a suite nobody can edit
      is how a guard gets deleted.

      INTERPOLATED TITLES COUNT, AND THEY WERE MISSED ONCE. Reading an
      ExpandableStringExpressionAst through its Extent.Text keeps the opening
      quote character, so the id is no longer at the start of what is examined.
      tests\stop_behaviour.ps1's C1 is written
      `Add-Result "C1 ($($shape.n)): ..."` and went unfound that way, while C2
      one section above it - a single-quoted literal - was found. The whole
      suite's header sentence "Both are regression cases here (C1, C2)" was
      then reported as naming a case that does not exist. .Value is read on
      both kinds for that reason.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($null -eq $ast) { return $null }
    if (@($errors).Count -gt 0) { return $null }

    $ids = @{}
    $strings = $ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
        $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst]
    }, $true)
    foreach ($s in @($strings)) {
        # .Value on BOTH kinds - see the note above. On an expandable string it
        # is the body with the `$` sub-expressions left as written, which is
        # exactly what a title's leading id sits at the front of.
        $v = [string]$s.Value
        if ([string]::IsNullOrWhiteSpace($v)) { continue }
        $m = [regex]::Match($v.TrimStart(), '^(?:CASE\s+)?([A-Z]\d{1,2}[a-z]?)\b')
        if ($m.Success) { $ids[$m.Groups[1].Value] = $true }
    }
    return $ids
}

function Test-Suite {
    <#
      Reads one suite and returns its annotations and its offenders. Never
      writes output, so the same function serves the live run and every
      fixture.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $result = [pscustomobject]@{
        name        = (Split-Path -Leaf $Path)
        baseline    = 0     # lines rule 1 checked
        caseRefs    = 0     # case ids rule 2 checked
        offenders   = New-Object System.Collections.Generic.List[object]
        aborted     = $null
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $result.aborted = "$Path is not a readable file"
        return $result
    }

    $ids = Get-DeclaredCaseIds -Path $Path
    if ($null -eq $ids) {
        $result.aborted = "$(Split-Path -Leaf $Path) did not parse, so its case ids were never read"
        return $result
    }

    $lines = [System.IO.File]::ReadAllLines($Path)

    # Comment BLOCKS, resolved once. An annotation is routinely the last line of
    # a wrapped comment paragraph whose SHA sits two lines above it - the
    # citation belongs to the paragraph, not to the line - so rule 1 looks at
    # the whole contiguous run of `#` lines the annotation sits in. A line that
    # is not a `#` comment (a docstring line, or a message inside a case) is its
    # own block: there is no paragraph to belong to.
    $blockStart = New-Object 'int[]' $lines.Count
    $blockEnd   = New-Object 'int[]' $lines.Count
    $i = 0
    while ($i -lt $lines.Count) {
        if ($lines[$i] -match '^\s*#') {
            $j = $i
            while ($j + 1 -lt $lines.Count -and $lines[$j + 1] -match '^\s*#') { $j++ }
            for ($k = $i; $k -le $j; $k++) { $blockStart[$k] = $i; $blockEnd[$k] = $j }
            $i = $j + 1
        } else {
            $blockStart[$i] = $i; $blockEnd[$i] = $i
            $i++
        }
    }

    for ($n = 0; $n -lt $lines.Count; $n++) {
        $text = $lines[$n]
        if ($text -notmatch '(?i)\bred\b') { continue }

        # ---- rule 1: a baseline-citing annotation must cite a SHA ----
        if ($text -match $script:BaselineAnnotation) {
            $result.baseline++
            $blockText = ($lines[$blockStart[$n]..$blockEnd[$n]] -join "`n")
            if ($blockText -notmatch $script:ShaToken) {
                $result.offenders.Add([pscustomobject]@{
                    rule = 'annotation-cites-a-baseline'
                    line = $n + 1
                    said = $text.Trim()
                    why  = 'this annotation claims a red-first baseline and names no commit. Cite the SHA the case was measured red at, in the same comment block.'
                })
            }
        }

        # ---- rule 2: a case an annotation names must exist ----
        if ($text -match $script:CaseAnnotation) {
            foreach ($m in [regex]::Matches($text, $script:CaseIdToken)) {
                $id = $m.Value
                $result.caseRefs++
                if (-not $ids.ContainsKey($id)) {
                    $result.offenders.Add([pscustomobject]@{
                        rule = 'annotation-names-a-live-case'
                        line = $n + 1
                        said = $text.Trim()
                        why  = ("this annotation names case '{0}', and no case in this suite is called that. A renamed or deleted case leaves the sentence behind, still read as evidence." -f $id)
                    })
                }
            }
        }
    }

    return $result
}

# ---------------------------------------------------------------------------
# Case bookkeeping - the same shape as .github\scripts\identity_scan.ps1.
# ---------------------------------------------------------------------------
$script:Results = New-Object System.Collections.Generic.List[object]

function Add-Case {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Ok,
        [string]$Detail = ''
    )
    $script:Results.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail })
    if ($Ok) { Write-Output ("ok    {0}" -f $Name) }
    else     { Write-Output ("FAIL  {0}`n      {1}" -f $Name, $Detail) }
}

if (-not $Live) {
    # -----------------------------------------------------------------------
    # FIXTURES. Planted suites, each carrying one shape, so both rules are
    # shown able to FIRE rather than only shown to say nothing about a tree
    # that happens to be clean. That is the whole standing this guard has.
    # -----------------------------------------------------------------------
    Write-Output '.github\scripts\redfirst_annotations.ps1 (fixture mode): the rules, against planted suites.'
    Write-Output 'This mode reads NO real suite. Pass -Live for that.'
    Write-Output ''

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("lwg-redfirst-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $root -Force | Out-Null

    function New-FixtureSuite {
        param(
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][string]$Body
        )
        $p = Join-Path $root $Name
        Set-Content -LiteralPath $p -Value $Body -Encoding ASCII
        return $p
    }

    try {
        # A1 - a well-formed suite. A case, an annotation citing a SHA, and an
        #      annotation naming that case. Without this row, "report every
        #      annotation" passes every B case below and reds all six live
        #      suites on the day it lands.
        $good = New-FixtureSuite -Name 'good.ps1' -Body @'
# A1 was measured RED AT abc1234 and passes with the fix.
Add-Result 'A1 the thing the fix does' $true 'detail'
# The red-first proof for this defect is A1 alone, taken at abc1234.
'@
        $r = Test-Suite -Path $good
        Add-Case -Name 'A1 a suite whose annotations cite a SHA and name a live case is clean' `
            -Ok ($null -eq $r.aborted -and $r.offenders.Count -eq 0 -and $r.baseline -eq 2) `
            -Detail ("expected 2 baseline annotations, 0 offenders, no abort; got baseline={0} offenders={1} abort='{2}'" -f $r.baseline, $r.offenders.Count, $r.aborted)

        # A2 - the paragraph case, which is the shape five of the six live
        #      suites actually use: the SHA is two lines above the annotation,
        #      in the same wrapped comment block. A line-scoped rule would red
        #      setup_merge.ps1:3024 and doc_claims.ps1:1240 on a tree nobody
        #      can fix.
        $para = New-FixtureSuite -Name 'paragraph.ps1' -Body @'
# BASELINE abc1234: the row carried nothing about the config, so these
# cases are the covering evidence that did not land with the fix, and
# that is where the red-first proof for them was taken.
Add-Result 'B1 the covering evidence' $true 'detail'
'@
        $r = Test-Suite -Path $para
        Add-Case -Name 'A2 a SHA elsewhere in the same comment block satisfies the citation' `
            -Ok ($null -eq $r.aborted -and $r.offenders.Count -eq 0 -and $r.baseline -eq 1) `
            -Detail ("expected 1 baseline annotation and 0 offenders; got baseline={0} offenders={1}" -f $r.baseline, $r.offenders.Count)

        # B1 - AN ANNOTATION THAT CITES NOTHING. The rule-1 red.
        $noSha = New-FixtureSuite -Name 'no-sha.ps1' -Body @'
Add-Result 'A1 the thing the fix does' $true 'detail'
# This case is RED at the baseline, obviously.
'@
        $r = Test-Suite -Path $noSha
        $hit = @($r.offenders | Where-Object { $_.rule -eq 'annotation-cites-a-baseline' })
        Add-Case -Name 'B1 an annotation claiming a baseline and naming no commit is caught' `
            -Ok ($null -eq $r.aborted -and $hit.Count -eq 1 -and $hit[0].line -eq 2) `
            -Detail ("expected exactly one annotation-cites-a-baseline offender on line 2; got {0} offender(s): {1}" -f $r.offenders.Count, (($r.offenders | ForEach-Object { "$($_.rule)@$($_.line)" }) -join ', '))

        # B2 - THE #152 SHAPE, as far as a shape check reaches it: the
        #      annotation names a case the suite does not have. A rename or a
        #      deletion leaves exactly this behind, and the sentence goes on
        #      being read as evidence.
        $ghost = New-FixtureSuite -Name 'ghost-case.ps1' -Body @'
Add-Result 'A1 the thing the fix does' $true 'detail'
# A1 and J9 were both confirmed RED AT abc1234.
'@
        $r = Test-Suite -Path $ghost
        $hit = @($r.offenders | Where-Object { $_.rule -eq 'annotation-names-a-live-case' })
        Add-Case -Name 'B2 an annotation naming a case the suite does not declare is caught' `
            -Ok ($null -eq $r.aborted -and $hit.Count -eq 1 -and $hit[0].why -match "'J9'") `
            -Detail ("expected exactly one annotation-names-a-live-case offender naming J9; got {0}: {1}" -f $hit.Count, (($r.offenders | ForEach-Object { $_.why }) -join ' | '))

        # B3 - the same rule on a line that names no baseline at all. Rule 2's
        #      set is wider than rule 1's on purpose: "CANNOT GO RED" names
        #      case ids as freely as a positive claim does, and a rule that
        #      only read the baseline-citing lines could be evaded by writing
        #      the annotation in the other form.
        $disclaimer = New-FixtureSuite -Name 'disclaimer.ps1' -Body @'
Add-Result 'A1 the thing the fix does' $true 'detail'
# A1 goes red under the mutation; K4 CANNOT GO RED against the pre-fix tree.
'@
        $r = Test-Suite -Path $disclaimer
        $hit = @($r.offenders | Where-Object { $_.rule -eq 'annotation-names-a-live-case' })
        Add-Case -Name 'B3 a CANNOT-GO-RED line naming a missing case is caught too' `
            -Ok ($null -eq $r.aborted -and $hit.Count -eq 1 -and $hit[0].why -match "'K4'") `
            -Detail ("expected one offender naming K4; got {0}: {1}" -f $hit.Count, (($r.offenders | ForEach-Object { $_.why }) -join ' | '))

        # C1 - THE ANTI-VACUITY ROW. A suite with no annotation at all must
        #      report zero checked, and the live run turns that into an abort.
        #      Without this, a matcher that matched nothing would pass A1 and
        #      A2 by reporting no offenders.
        $silent = New-FixtureSuite -Name 'silent.ps1' -Body @'
Add-Result 'A1 the thing the fix does' $true 'detail'
# Nothing here claims anything about a baseline.
'@
        $r = Test-Suite -Path $silent
        Add-Case -Name 'C1 a suite with no annotation reports zero checked, not zero offenders' `
            -Ok ($null -eq $r.aborted -and $r.baseline -eq 0 -and $r.caseRefs -eq 0 -and $r.offenders.Count -eq 0) `
            -Detail ("expected baseline=0 caseRefs=0 offenders=0; got baseline={0} caseRefs={1} offenders={2}" -f $r.baseline, $r.caseRefs, $r.offenders.Count)

        # C2 - a suite that does not parse ABORTS. Its case ids were never
        #      read, so every id an annotation names would look missing and the
        #      guard would report a wall of offenders about a file it could not
        #      read. Not clean, and not a pass either.
        $broken = New-FixtureSuite -Name 'broken.ps1' -Body @'
Add-Result 'A1 unterminated (
# A1 was RED AT abc1234.
'@
        $r = Test-Suite -Path $broken
        Add-Case -Name 'C2 a suite that does not parse aborts rather than reporting offenders' `
            -Ok ($null -ne $r.aborted -and $r.aborted -match 'did not parse') `
            -Detail ("expected a parse abort; got abort='{0}' offenders={1}" -f $r.aborted, $r.offenders.Count)

        # C3 - a file that is not there aborts.
        $r = Test-Suite -Path (Join-Path $root 'does-not-exist.ps1')
        Add-Case -Name 'C3 a missing suite aborts' -Ok ($null -ne $r.aborted) `
            -Detail ("expected an abort; got abort='{0}'" -f $r.aborted)
    } finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
else {
    # -----------------------------------------------------------------------
    # LIVE. Read this repository's suites.
    # -----------------------------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($SuiteDir)) {
        $repo = (& git rev-parse --show-toplevel 2>$null)
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repo)) {
            Write-Output 'ABORTED: not inside a git repository and no -SuiteDir was given, so no suite was read.'
            Write-Output 'EXIT: 2'
            exit 2
        }
        $SuiteDir = Join-Path ($repo.Trim() -replace '/', '\') 'tests'
    }

    if (-not (Test-Path -LiteralPath $SuiteDir -PathType Container)) {
        Write-Output ("ABORTED: {0} does not exist, so no suite was read." -f $SuiteDir)
        Write-Output 'EXIT: 2'
        exit 2
    }

    $suites = @(Get-ChildItem -LiteralPath $SuiteDir -Filter '*.ps1' -File | Sort-Object Name)
    if ($suites.Count -eq 0) {
        Write-Output ("ABORTED: no .ps1 file under {0} - the enumeration is broken, or the suites are gone." -f $SuiteDir)
        Write-Output 'EXIT: 2'
        exit 2
    }

    Write-Output ("reading {0} suite(s) under {1}" -f $suites.Count, $SuiteDir)
    Write-Output ''

    $totalBaseline = 0
    $totalCaseRefs = 0
    $allOffenders  = New-Object System.Collections.Generic.List[object]
    $aborts        = New-Object System.Collections.Generic.List[string]

    Write-Output '  suite                        baseline annotations   case references'
    foreach ($s in $suites) {
        $r = Test-Suite -Path $s.FullName
        if ($null -ne $r.aborted) { $aborts.Add($r.aborted); continue }
        $totalBaseline += $r.baseline
        $totalCaseRefs += $r.caseRefs
        Write-Output ("  {0,-28} {1,10}   {2,17}" -f $r.name, $r.baseline, $r.caseRefs)
        foreach ($o in $r.offenders) {
            $allOffenders.Add([pscustomobject]@{ file = $r.name; line = $o.line; rule = $o.rule; said = $o.said; why = $o.why })
        }
    }
    Write-Output ''

    if ($aborts.Count -gt 0) {
        foreach ($a in $aborts) { Write-Output ("ABORTED: {0}" -f $a) }
        Write-Output 'Nothing about these annotations was established by this run.'
        Write-Output 'EXIT: 2'
        exit 2
    }

    # THE LEDGER. A rule that checked nothing is an abort, not a clean run -
    # tests\doc_claims.ps1's rule, applied here for the same reason.
    if ($totalBaseline -eq 0) {
        Write-Output 'ABORTED: rule annotation-cites-a-baseline matched NO line in any suite.'
        Write-Output 'A rule that checks nothing reports a coverage it does not have. Either the'
        Write-Output 'annotations were reworded and the pattern must follow them, or they are gone.'
        Write-Output 'EXIT: 2'
        exit 2
    }
    if ($totalCaseRefs -eq 0) {
        Write-Output 'ABORTED: rule annotation-names-a-live-case read NO case reference in any suite.'
        Write-Output 'Same reason as above: a live pattern set is a floor, and zero is not one.'
        Write-Output 'EXIT: 2'
        exit 2
    }

    if ($allOffenders.Count -gt 0) {
        Write-Output 'ANNOTATIONS WHOSE SHAPE DOES NOT HOLD:'
        foreach ($o in $allOffenders) {
            Write-Output ("  {0}:{1}  [{2}]" -f $o.file, $o.line, $o.rule)
            Write-Output ("      said: {0}" -f $o.said)
            Write-Output ("      {0}" -f $o.why)
        }
        Write-Output ''
    }

    Add-Case -Name ("L1 every baseline-citing annotation names a commit ({0} checked)" -f $totalBaseline) `
        -Ok (@($allOffenders | Where-Object { $_.rule -eq 'annotation-cites-a-baseline' }).Count -eq 0) `
        -Detail ("{0} annotation(s) claim a baseline and name no SHA - see the list above" -f @($allOffenders | Where-Object { $_.rule -eq 'annotation-cites-a-baseline' }).Count)

    Add-Case -Name ("L2 every case an annotation names exists in that suite ({0} checked)" -f $totalCaseRefs) `
        -Ok (@($allOffenders | Where-Object { $_.rule -eq 'annotation-names-a-live-case' }).Count -eq 0) `
        -Detail ("{0} annotation(s) name a case their suite does not declare - see the list above" -f @($allOffenders | Where-Object { $_.rule -eq 'annotation-names-a-live-case' }).Count)
}

# ---------------------------------------------------------------------------
# Report.
# ---------------------------------------------------------------------------
$fail = @($script:Results | Where-Object { -not $_.ok })
$pass = @($script:Results | Where-Object { $_.ok }).Count

if ($script:Results.Count -eq 0) {
    Write-Output ''
    Write-Output 'ABORTED: no case ran at all, so nothing was established.'
    Write-Output 'EXIT: 2'
    exit 2
}

Write-Output ''
Write-Output ("RESULT: {0} of {1} case(s) passed in {2} ms" -f $pass, $script:Results.Count, [int]$sw.Elapsed.TotalMilliseconds)

if ($fail.Count -gt 0) {
    Write-Output 'EXIT: 1'
    exit 1
}

Write-Output 'EXIT: 0'
exit 0
