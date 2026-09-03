#requires -version 5
<#
  LW-WATCHTOWER pull-request issue-reference guard.

      powershell -NoProfile -ExecutionPolicy Bypass -File .github\scripts\pr_issue_ref.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File .github\scripts\pr_issue_ref.ps1 -Live

  WHY THIS FILE EXISTS

  The owner decided on 2026-09-03 (#147, #184) that ALL WORK STARTS AND ENDS
  THROUGH GITHUB ISSUES: one issue, one pull request, evidence attached when the
  issue closes. Two halves of that rule can be enforced by a machine, and this
  file is those two halves. Everything else in the protocol is a [review] rule
  and CONTRIBUTING.md says so rather than implying a control that is absent.

  RULE 1 - a pull request must reference an issue.

  A change that arrives without an issue has no stated done-condition, no chair
  call, and nothing to attach evidence to when it lands. This repository has
  twice ended up with fixes nobody can trace afterwards; both times the fix
  itself was fine and the record was not.

  RULE 2 - it must NOT use a closing keyword.

  `Closes #12` in a pull-request body makes GitHub close the issue the moment
  the pull request merges. The issue then closes with a merge commit as its only
  evidence, which is precisely the closure rule being broken by automation:

      "An issue closes only if it is fixed with a case proven RED before the
       fix, or it does not reproduce, or it is a limitation now documented
       honestly."  - #147, 2026-08-03

  Under this protocol the independent QA agent - never the agent that wrote the
  fix - posts the evidence comment and closes the issue by hand, naming the
  closure class. An auto-close takes that step away and nobody notices, because
  a closed issue looks the same either way. So the accepted form is `Refs #12`,
  and a closing keyword FAILS this guard even though GitHub considers it good
  practice. That disagreement is deliberate and is the reason this rule exists.

  WHAT THIS GUARD DOES NOT DO, stated plainly:

    * It does not check that the referenced issue EXISTS, is open, or has
      anything to do with the diff. That needs the network and a credential, and
      no suite in this repository uses either.
    * It does not check that the issue carries a chair call, a severity label or
      a done-condition. Those are [review].
    * It does not check who closed the issue, or whether evidence was attached.
      GitHub cannot enforce that here - `enforce_admins` is false and there are
      no required reviews, so one account can write a fix and close its own
      issue. That is a [review] rule and pretending otherwise would be the
      overstatement this project keeps finding in itself.
    * It says nothing about a push to `main`. There is no pull-request body on a
      push, so the CI step that calls this is conditional on the event. A skipped
      step is visible in the run; a step that passed because it had nothing to
      read would not be, and that shape - exit 0 from a check that never ran -
      is the defect class #39 and #42 already record here.

  EXIT CONTRACT, the same one every suite in tests\ uses:

      0  every case passed
      1  a case failed - in -Live, the body is missing a reference or carries a
         closing keyword; in fixture mode, the matcher itself is wrong
      2  the guard could not establish anything: -Live was asked for and
         LWG_PR_BODY was never handed to it, or no case ran at all. NOT CLEAN,
         and never reported as a pass.

  INPUT, and the first version of this got it wrong in a way worth recording.

  Live mode reads the body from the WEBHOOK EVENT PAYLOAD on disk: the JSON file
  at GITHUB_EVENT_PATH, property pull_request.body. LWG_PR_BODY is honoured too,
  but only as a local testing override.

  The first version had ci.yml pass the body in as an env value written
  `LWG_PR_BODY: ${{ github.event.pull_request.body }}`. That is broken as well as
  dangerous, and CI proved it on this very pull request: GitHub substitutes a
  ${{ }} expression into the WORKFLOW TEXT before the YAML is parsed, so a
  multi-line body - or one containing a quote, a colon, a backtick fence, or the
  characters ${{ - truncates the value and spills the rest into the workflow as
  stray YAML. The guard received nothing and exited 2. A pull-request body is
  attacker-controlled text on a public repository, so the same substitution is
  the textbook script-injection vector: the value must never reach the YAML at
  all.

  Reading the payload file instead is injection-proof: the body is bytes in a
  JSON file that this script parses, never text the runner expands. It also
  removes the one thing an author could control about how the check runs.
#>

[CmdletBinding()]
param(
    # DEFAULT is the fixture run: it establishes the matcher and nothing else.
    # -Live reads a real pull-request body from LWG_PR_BODY and judges it.
    #
    # That way round on purpose. tests\doc_claims.ps1 enumerates every tracked
    # tests\*.ps1 and runs it with no arguments, aborting the build if any of
    # them exits nonzero - so a live-by-default guard would abort CI on every
    # push, where there is no pull-request body to read. Making the fixture run
    # the default keeps a bare invocation meaningful (18 cases over the matcher)
    # without letting it ever report COMPLIANCE it did not measure: only -Live
    # can pass or fail a body, and with LWG_PR_BODY unset it exits 2.
    [switch]$Live
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sw = [System.Diagnostics.Stopwatch]::StartNew()

# GitHub's closing keywords, verbatim from its documentation. All three stems in
# all three tenses; GitHub matches them case-insensitively and so does this.
$script:ClosingKeywords = @(
    'close', 'closes', 'closed',
    'fix', 'fixes', 'fixed',
    'resolve', 'resolves', 'resolved'
)

function Get-LwgIssueRefs {
    <#
      Returns every issue reference in $Body as an int list.

      Two accepted forms, and nothing else:
        * #123                                    - the short form
        * https://github.com/<owner>/<repo>/issues/123
      A bare number is not a reference. #0 is not a reference - GitHub has no
      issue 0, so a body saying "#0" is a typo being read as compliance.
    #>
    param([AllowNull()][string]$Body)

    $out = New-Object System.Collections.Generic.List[int]
    if ([string]::IsNullOrWhiteSpace($Body)) { return $out }

    foreach ($m in [regex]::Matches($Body, '(?<![0-9A-Za-z_])#(?<n>[1-9][0-9]*)\b')) {
        $out.Add([int]$m.Groups['n'].Value)
    }
    foreach ($m in [regex]::Matches($Body, '(?i)https?://github\.com/[^/\s]+/[^/\s]+/issues/(?<n>[1-9][0-9]*)\b')) {
        $out.Add([int]$m.Groups['n'].Value)
    }
    return $out
}

function Get-LwgClosingKeywordHits {
    <#
      Returns each closing keyword that is actually bound to an issue reference,
      as "keyword #n". A body that merely contains the word "fixes" in prose is
      not a hit: the keyword only closes an issue when it sits immediately
      before a reference, and a guard that failed on the English word would be
      unusable on a repository whose pull requests are about fixes.
    #>
    param([AllowNull()][string]$Body)

    $out = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($Body)) { return $out }

    $kw = ($script:ClosingKeywords -join '|')
    $pattern = '(?i)(?<![0-9A-Za-z_])(?<kw>' + $kw + ')\s*:?\s+(?:#|https?://github\.com/[^/\s]+/[^/\s]+/issues/)(?<n>[1-9][0-9]*)\b'
    foreach ($m in [regex]::Matches($Body, $pattern)) {
        $out.Add(("{0} #{1}" -f $m.Groups['kw'].Value, $m.Groups['n'].Value))
    }
    return $out
}

function Resolve-PrBody {
    <#
      Where the body comes from, as a testable function rather than as inline
      logic in the live branch. It exists because the FIRST version of this
      guard resolved the body inline, CI proved the resolution wrong, and an
      inline fix would have been a second untested code path in the same file.

      Returns { body, source, abort }. A non-null `abort` means unestablished:
      exit 2, never a pass. An EMPTY body is not an abort - it is a real answer
      that fails rule 1.
    #>
    param(
        # [object], NOT [string]. A [string] parameter COERCES $null to the empty
        # string, which collapses "unset" into "empty" - the one distinction this
        # whole guard turns on, since unset is exit 2 and empty is a real answer
        # that fails rule 1. A fixture caught this: E7 went green against a
        # [string] signature while the live path would have read a missing
        # variable as an empty body and judged it.
        [AllowNull()][object]$EventPath,
        [AllowNull()][object]$EnvBody
    )

    $eventPathStr = if ($null -eq $EventPath) { $null } else { [string]$EventPath }

    $out = [pscustomobject]@{ body = $null; source = $null; abort = $null }

    if (-not [string]::IsNullOrWhiteSpace($eventPathStr)) {
        if (-not (Test-Path -LiteralPath $eventPathStr -PathType Leaf)) {
            $out.abort = "GITHUB_EVENT_PATH names $eventPathStr, which is not a file, so no body was read"
            return $out
        }
        try {
            $payload = Get-Content -Raw -LiteralPath $eventPathStr | ConvertFrom-Json
        } catch {
            $out.abort = "$eventPathStr is not readable JSON, so no body was read"
            return $out
        }
        $pr = $payload.PSObject.Properties['pull_request']
        if ($null -eq $pr -or $null -eq $pr.Value) {
            $out.abort = 'the event payload carries no pull_request, so this did not run on a pull_request event'
            return $out
        }
        $bodyProp = $pr.Value.PSObject.Properties['body']
        if ($null -ne $bodyProp -and $null -ne $bodyProp.Value) {
            $out.body   = [string]$bodyProp.Value
            $out.source = 'the webhook event payload'
            return $out
        }
        # pull_request present, body null: GitHub sends null for an empty
        # description. That is a body of zero characters, and rule 1 has an
        # opinion about it - so it is answered, not skipped.
        $out.body   = ''
        $out.source = 'the webhook event payload (empty body)'
        return $out
    }

    if ($null -ne $EnvBody) {
        $out.body   = [string]$EnvBody
        $out.source = 'LWG_PR_BODY (local override)'
        return $out
    }

    $out.abort = 'GITHUB_EVENT_PATH names no readable payload and LWG_PR_BODY is not set'
    return $out
}

# ---------------------------------------------------------------------------
# Case bookkeeping - same shape as the other suites: a case is recorded, never
# inferred, and a run with no cases is an abort rather than a pass.
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

# ---------------------------------------------------------------------------
# SELF-TEST. The matcher is the whole of this guard, so the fixtures are the
# whole of its coverage. Each fixture states what it establishes; a fixture that
# would pass whatever the matcher did is not written down as a case.
# ---------------------------------------------------------------------------
if (-not $Live) {
    Write-Output '.github\scripts\pr_issue_ref.ps1 (fixture mode): the matcher, against fixtures.'
    Write-Output 'This mode judges NO pull request. Pass -Live with LWG_PR_BODY set for that.'
    Write-Output ''

    $accepts = @(
        @{ n = 'A1 short form on its own line';                     b = "What this changes`n`nRefs #184" }
        @{ n = 'A2 lower-case refs';                                 b = 'refs #12 - the config writer' }
        @{ n = 'A3 bare reference in prose';                         b = 'This continues the work in #7.' }
        @{ n = 'A4 full issue URL';                                  b = 'See https://github.com/LEAPWare-Software/LEAPWare-Watchtower/issues/178' }
        @{ n = 'A5 several references';                              b = 'Refs #11, #91 and #92' }
        @{ n = 'A6 reference beside the word fixes, not bound to it'; b = 'Refs #60. This fixes the probe that cannot fail.' }
    )
    foreach ($f in $accepts) {
        $refs = @(Get-LwgIssueRefs -Body $f.b)
        $kws  = @(Get-LwgClosingKeywordHits -Body $f.b)
        Add-Case -Name $f.n -Ok ($refs.Count -gt 0 -and $kws.Count -eq 0) `
            -Detail ("expected a reference and no closing keyword; got {0} ref(s), {1} keyword hit(s)" -f $refs.Count, $kws.Count)
    }

    $noRef = @(
        @{ n = 'B1 empty body';                          b = '' }
        @{ n = 'B2 null body';                           b = $null }
        @{ n = 'B3 prose with no reference at all';      b = "Tidies up the installer.`nNo issue for this." }
        @{ n = 'B4 a bare hash is not a reference';      b = 'See # for details' }
        @{ n = 'B5 issue zero is a typo, not a ref';     b = 'Refs #0' }
        @{ n = 'B6 a markdown heading is not a ref';     b = "# What this changes`n`nsome prose" }
        @{ n = 'B7 a hex colour is not a ref';           b = 'the badge colour is #B60205' }
    )
    foreach ($f in $noRef) {
        $refs = @(Get-LwgIssueRefs -Body $f.b)
        Add-Case -Name $f.n -Ok ($refs.Count -eq 0) `
            -Detail ("expected no reference; matcher found {0}: {1}" -f $refs.Count, ($refs -join ', '))
    }

    $closing = @(
        @{ n = 'C1 Closes';                              b = 'Closes #184' }
        @{ n = 'C2 fixes, lower case';                   b = 'fixes #12' }
        @{ n = 'C3 Resolved with a colon';               b = 'Resolved: #3' }
        @{ n = 'C4 closing keyword on a full URL';       b = 'Fixes https://github.com/LEAPWare-Software/LEAPWare-Watchtower/issues/9' }
    )
    foreach ($f in $closing) {
        $kws = @(Get-LwgClosingKeywordHits -Body $f.b)
        Add-Case -Name $f.n -Ok ($kws.Count -gt 0) `
            -Detail 'expected the closing keyword to be caught; it was not, so an auto-close would reach main'
    }

    # ---------------------------------------------------------------------
    # E - WHERE THE BODY COMES FROM. These exist because CI failed on exactly
    # this. The first version had ci.yml interpolate the body into the workflow
    # YAML with a ${{ }} expression, which truncated a multi-line body and
    # handed the guard nothing at all. Every case below plants a real payload
    # file on disk and resolves from it.
    # ---------------------------------------------------------------------
    $fxRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("lwg-prref-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $fxRoot -Force | Out-Null

    function New-EventFile {
        param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Json)
        $f = Join-Path $fxRoot $Name
        Set-Content -LiteralPath $f -Value $Json -Encoding UTF8
        return $f
    }

    # E1 - the body the OLD mechanism could not carry: multi-line, with a code
    # fence, a quote, a colon, and the literal characters that broke it.
    $hardBody = @(
        'What this changes',
        '',
        'Refs #184',
        '',
        '```',
        'LWG_PR_BODY: ${{ github.event.pull_request.body }}',
        '```',
        '',
        'Note: "quoted", and a colon: here.'
    ) -join "`n"
    $f = New-EventFile -Name 'hard.json' -Json (@{ pull_request = @{ body = $hardBody } } | ConvertTo-Json -Depth 5)
    $r = Resolve-PrBody -EventPath $f -EnvBody $null
    $eRefs = @(Get-LwgIssueRefs -Body $r.body)
    Add-Case -Name 'E1 a multi-line body with a fence, a quote, a colon and an expression survives intact' `
        -Ok ($null -eq $r.abort -and $eRefs.Count -eq 1 -and $eRefs[0] -eq 184 -and $r.body -match 'colon' -and $r.body -match 'quoted') `
        -Detail ("this is the shape that broke the interpolated version; abort='{0}' refs='{1}'" -f $r.abort, ($eRefs -join ','))

    # E2 - GitHub sends body: null for an empty description. Zero characters is
    # a real answer that rule 1 must judge, not a reason to skip the check.
    $f = New-EventFile -Name 'nullbody.json' -Json '{"pull_request":{"body":null}}'
    $r = Resolve-PrBody -EventPath $f -EnvBody $null
    Add-Case -Name 'E2 a null body is judged as empty, not treated as unestablished' `
        -Ok ($null -eq $r.abort -and $r.body -eq '' -and @(Get-LwgIssueRefs -Body $r.body).Count -eq 0) `
        -Detail ("expected an empty body and no abort; got abort='{0}'" -f $r.abort)

    # E3 - a payload with no pull_request means this ran on the wrong event.
    $f = New-EventFile -Name 'push.json' -Json '{"ref":"refs/heads/main"}'
    $r = Resolve-PrBody -EventPath $f -EnvBody $null
    Add-Case -Name 'E3 a payload with no pull_request aborts' `
        -Ok ($null -ne $r.abort -and $r.abort -match 'no pull_request') `
        -Detail ("expected an abort naming pull_request; got '{0}'" -f $r.abort)

    # E4 - unreadable JSON aborts rather than being read as an empty body.
    $f = New-EventFile -Name 'broken.json' -Json '{"pull_request":{"body":'
    $r = Resolve-PrBody -EventPath $f -EnvBody $null
    Add-Case -Name 'E4 a truncated payload aborts' -Ok ($null -ne $r.abort) `
        -Detail ("expected an abort; got abort='{0}' body='{1}'" -f $r.abort, $r.body)

    # E5 - a path pointing at nothing aborts, and says so.
    $r = Resolve-PrBody -EventPath (Join-Path $fxRoot 'absent.json') -EnvBody $null
    Add-Case -Name 'E5 a GITHUB_EVENT_PATH pointing at nothing aborts' `
        -Ok ($null -ne $r.abort -and $r.abort -match 'not a file') `
        -Detail ("expected a not-a-file abort; got '{0}'" -f $r.abort)

    # E6 - with no payload, the env override is used. That is the local testing
    # path, and it must stay available without becoming the CI path.
    $r = Resolve-PrBody -EventPath $null -EnvBody 'Refs #7'
    Add-Case -Name 'E6 the env override is used when there is no payload' `
        -Ok ($null -eq $r.abort -and $r.body -eq 'Refs #7' -and $r.source -match 'local override') `
        -Detail ("expected the override; got abort='{0}' source='{1}'" -f $r.abort, $r.source)

    # E7 - neither source: abort.
    $r = Resolve-PrBody -EventPath $null -EnvBody $null
    Add-Case -Name 'E7 no payload and no override aborts' -Ok ($null -ne $r.abort) `
        -Detail ("expected an abort; got abort='{0}'" -f $r.abort)

    # E8 - the payload WINS over the override, so the check cannot be steered by
    # an environment variable.
    $f = New-EventFile -Name 'wins.json' -Json '{"pull_request":{"body":"Refs #99"}}'
    $r = Resolve-PrBody -EventPath $f -EnvBody 'Refs #1'
    Add-Case -Name 'E8 the event payload takes precedence over the env override' `
        -Ok ($null -eq $r.abort -and $r.body -eq 'Refs #99') `
        -Detail ("expected the payload body; got '{0}'" -f $r.body)

    Remove-Item -LiteralPath $fxRoot -Recurse -Force -ErrorAction SilentlyContinue
}
else {
    # -----------------------------------------------------------------------
    # LIVE MODE.
    # -----------------------------------------------------------------------
    $resolved = Resolve-PrBody `
        -EventPath ([Environment]::GetEnvironmentVariable('GITHUB_EVENT_PATH')) `
        -EnvBody   ([Environment]::GetEnvironmentVariable('LWG_PR_BODY'))

    if ($null -ne $resolved.abort) {
        Write-Output ("ABORTED: {0}." -f $resolved.abort)
        Write-Output 'This guard has no opinion on a push. It is called on pull_request only,'
        Write-Output 'and a run that could not read a body establishes nothing.'
        Write-Output 'EXIT: 2'
        exit 2
    }

    $bodyVar = $resolved.body
    Write-Output ("      body read from: {0} ({1} character(s))" -f $resolved.source, $bodyVar.Length)

    $refs = @(Get-LwgIssueRefs -Body $bodyVar)
    $kws  = @(Get-LwgClosingKeywordHits -Body $bodyVar)

    Add-Case -Name 'L1 the body references an issue' -Ok ($refs.Count -gt 0) -Detail @'
No issue reference in the pull-request body. Every change starts from an issue
(#147, 2026-09-03): open one, state its done-condition, and put "Refs #N" in
this body. Accepted forms are "#123" and a full .../issues/123 URL.
'@

    Add-Case -Name 'L2 the body uses no closing keyword' -Ok ($kws.Count -eq 0) `
        -Detail ("Closing keyword(s) found: {0}. Use `"Refs #N`" instead. A closing keyword makes GitHub close the issue on merge, with the merge as its only evidence - and under this protocol the independent QA agent closes it by hand, with the evidence and the closure class named." -f ($kws -join ', '))

    if ($refs.Count -gt 0) {
        Write-Output ("      referenced: {0}" -f (($refs | Sort-Object -Unique | ForEach-Object { "#$_" }) -join ', '))
    }
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
