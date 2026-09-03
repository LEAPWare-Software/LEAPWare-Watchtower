#requires -version 5
<#
  LW-WATCHTOWER commit-identity guard.

      powershell -NoProfile -ExecutionPolicy Bypass -File .github\scripts\identity_scan.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File .github\scripts\identity_scan.ps1 -Live

  WHY THIS FILE EXISTS

  On 2026-09-02 an independent QA pass found a non-repository identity on `main`
  in the `Co-authored-by:` trailers of three squash commits (#178). The probe
  that was supposed to prevent exactly that - `P3-identity` in the deleted
  `checklist.json` - read:

      git --no-pager log --all --format=%ae%n%ce

  `%ae` and `%ce` are the AUTHOR and COMMITTER fields. **The rule never read a
  commit body**, so a trailer was invisible to it, and the probe reported green
  while the exposure was live and world-readable on a public repository.

  Two defects, not one, and this file fixes both:

    1. IT READ THE WRONG FIELDS. A `Co-authored-by:` trailer is an identity
       GitHub attributes and displays like any other. It is in the message body.
    2. IT WAS A DENYLIST. `P3-identity` forbade one specific address in two
       specific fields, so it could only ever catch the exposure somebody had
       already found. This is an ALLOWLIST: every identity on every commit must
       be one of a named set, and anything else fails. A denylist over a subset
       of fields cannot establish the claim "exactly one identity" that the old
       probe made.

  SCOPE - `main`'s history only, and this is a deliberate limit rather than an
  oversight.

  A handful of refs on this remote are owned by GitHub rather than by this
  repository: deleting a branch does not remove them, no push can reach them,
  and rewriting `main` does not touch them. Some of them carry an identity this
  allowlist does not accept, and only GitHub Support can purge one. So a scan
  over `--all`, or over every ref a CI checkout happens to have, would go red on
  a condition **no contributor can fix** - and a check that cannot be made green
  is a check somebody eventually deletes.

  WHICH refs, their tips, and the invocation that retrieves them are ON #178 and
  deliberately NOT here. This file ships: `marketplace.json` declares
  `"source": "./"` and that form has no exclusion, so every tracked file lands on
  a consumer's machine. Writing the map here would turn a bounded exposure into a
  signposted one - it would tell a reader who did not know to look both where and
  exactly how. That is the same paragraph `tests/payload_guard.ps1` was built to
  refuse after it shipped once in `HANDOFF.md`, and the same reason #47 holds its
  evidence on the tracker instead of in the tree.

  This scans the commits that are reachable from HEAD, which on a pull request is
  the history that would become `main` if it merged. That is the question worth
  answering: "does anything about to land carry an identity we have not
  accepted?" Branch-side hygiene is a different control - a conditional git
  identity keyed on the remote URL, so a fresh clone of this repository cannot
  author with a personal address in the first place. Both were put in place on
  2026-09-03; neither is a substitute for the other, and this file says so
  rather than implying it covers more than it does.

  WHAT IT DOES NOT DO:

    * It does not read the GitHub-owned refs described above, for the reason
      given there. The residual is measured by hand and recorded on #178.
    * It does not read tags, notes or reflogs.
    * It cannot tell an identity that is WRONG from an identity that is merely
      NEW. A new maintainer is a one-line, reviewable change to the allowlist
      below - which is the point of an allowlist, and is the same argument
      tests\workflow_guard.ps1 makes for its runner-label list.
    * It does not verify signatures. Nothing here is signed; `required_signatures`
      is off on this repository.

  IT NEVER PRINTS AN OFFENDING ADDRESS IN FULL. CI logs on a public repository
  are public, so a guard that echoed the address it found would re-publish the
  thing it exists to remove - the same mistake as the pull-ref paragraph that was
  removed from HANDOFF.md. Offenders are reported as a commit SHA, the field, and
  a masked address. The SHA is enough to act on.

  EXIT CONTRACT, the same one every guard in this repository uses:

      0  every identity on every scanned commit is on the allowlist
      1  an identity that is not on the allowlist was found
      2  nothing was established: the repository is shallow, git failed, or no
         commit was read at all. NOT CLEAN, and never reported as a pass.
#>

[CmdletBinding()]
param(
    # DEFAULT is the fixture run, which builds throwaway repositories and proves
    # each rule fires. -Live scans this repository. Same shape, and for the same
    # reason, as .github\scripts\pr_issue_ref.ps1.
    [switch]$Live
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sw = [System.Diagnostics.Stopwatch]::StartNew()

# ---------------------------------------------------------------------------
# THE ALLOWLIST. Every entry states who it is and why it is accepted. An entry
# without a reason is an entry nobody will re-read - the policy
# tests\workflow_guard.ps1 states for its own allowlist, applied here.
# ---------------------------------------------------------------------------
$script:Allowed = @(
    @{ address = 'leapware@outlook.com'
       why     = 'the repository identity. Every commit authored for this project uses it, enforced clone-side by a conditional git identity keyed on the remote URL.' }

    @{ address = 'noreply@github.com'
       why     = 'GitHub itself, as the committer of every squash merge and every web-UI edit. Unavoidable and not a personal identity.' }

    @{ address = 'noreply@anthropic.com'
       why     = 'the assistant trailer on commits written with Claude. A role address, not a person, and removing it would falsify authorship rather than protect anyone.' }

    @{ address = '49699333+dependabot[bot]@users.noreply.github.com'
       why     = 'Dependabot, which authors its own dependency bumps and co-authors the squash that merges them.' }

    @{ address = 'support@github.com'
       why     = 'the Signed-off-by address Dependabot puts on every one of its commits. FOUND BY THIS GUARD on its first baseline run, at b12635b (#149) - the old P3-identity probe never read a trailer, so nothing had ever seen it. It is a GitHub role address, not a person, and it is accepted for that reason and no other.' }
)

$script:AllowedSet = @{}
foreach ($a in $script:Allowed) { $script:AllowedSet[$a.address.ToLowerInvariant()] = $true }

function Get-MaskedAddress {
    <#
      first character, then the shape. m***@f***.com out of a real address.
      Enough to recognise, not enough to publish. A public CI log is a publisher.
    #>
    param([string]$Address)

    if ([string]::IsNullOrWhiteSpace($Address)) { return '<empty>' }
    $at = $Address.IndexOf('@')
    if ($at -lt 1) { return ($Address.Substring(0, 1) + '***') }

    $local  = $Address.Substring(0, $at)
    $domain = $Address.Substring($at + 1)
    $dot    = $domain.LastIndexOf('.')
    $tld    = if ($dot -gt 0) { $domain.Substring($dot) } else { '' }

    return ('{0}***@{1}***{2}' -f $local.Substring(0, 1), $domain.Substring(0, 1), $tld)
}

function Get-CommitIdentities {
    <#
      Every identity on one commit, as objects { field, address }.

      Three sources, because the old probe read only the first two:
        author     %ae
        committer  %ce
        trailers   any Co-authored-by: line in the body, in any case, and any
                   Signed-off-by: line - both are identities a reader sees.
    #>
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string]$Sha
    )

    $out = New-Object System.Collections.Generic.List[object]

    $pair = & git -C $RepoPath log -1 --format='%ae%n%ce' $Sha 2>$null
    if ($LASTEXITCODE -ne 0 -or $null -eq $pair) { return $null }
    $pair = @($pair)
    if ($pair.Count -lt 2) { return $null }

    $out.Add([pscustomobject]@{ field = 'author';    address = $pair[0].Trim() })
    $out.Add([pscustomobject]@{ field = 'committer'; address = $pair[1].Trim() })

    $body = & git -C $RepoPath log -1 --format='%B' $Sha 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    foreach ($line in @($body)) {
        if ($null -eq $line) { continue }
        $m = [regex]::Match($line, '(?i)^\s*(?<kind>co-authored-by|signed-off-by)\s*:\s*.*?<(?<addr>[^>]+)>\s*$')
        if ($m.Success) {
            $out.Add([pscustomobject]@{
                field   = $m.Groups['kind'].Value.ToLowerInvariant()
                address = $m.Groups['addr'].Value.Trim()
            })
        }
    }

    return $out
}

function Test-Repository {
    <#
      Scans one repository and returns a result object. Never writes output, so
      the same function serves the live run and every fixture.
    #>
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [string]$Rev = 'HEAD'
    )

    $result = [pscustomobject]@{
        commits   = 0
        offenders = New-Object System.Collections.Generic.List[object]
        aborted   = $null
    }

    if (-not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) {
        $result.aborted = "$RepoPath is not a git repository"
        return $result
    }

    # A shallow clone is the empty-set pass this repository has been bitten by
    # before: the scan would read three commits, find nothing, and report clean
    # about a history it never saw.
    $shallow = & git -C $RepoPath rev-parse --is-shallow-repository 2>$null
    if ($LASTEXITCODE -eq 0 -and "$shallow".Trim() -eq 'true') {
        $result.aborted = 'the repository is SHALLOW, so most of the history was never fetched. Use fetch-depth: 0.'
        return $result
    }

    $shas = & git -C $RepoPath rev-list $Rev 2>$null
    if ($LASTEXITCODE -ne 0) {
        $result.aborted = "git rev-list $Rev failed, so no commit was read"
        return $result
    }

    foreach ($sha in @($shas)) {
        if ([string]::IsNullOrWhiteSpace($sha)) { continue }
        $result.commits++
        $ids = Get-CommitIdentities -RepoPath $RepoPath -Sha $sha
        if ($null -eq $ids) {
            $result.aborted = "could not read the identities on $sha, so the scan is incomplete"
            return $result
        }
        foreach ($id in $ids) {
            if (-not $script:AllowedSet.ContainsKey($id.address.ToLowerInvariant())) {
                $result.offenders.Add([pscustomobject]@{
                    sha    = $sha.Substring(0, [Math]::Min(9, $sha.Length))
                    field  = $id.field
                    masked = (Get-MaskedAddress $id.address)
                })
            }
        }
    }

    if ($result.commits -eq 0) {
        $result.aborted = 'no commit was read at all, so nothing was established'
    }

    return $result
}

# ---------------------------------------------------------------------------
# Case bookkeeping.
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
    # FIXTURES. Throwaway repositories, each planted with one shape, so every
    # rule is shown able to FIRE rather than only shown to say nothing. A guard
    # proved only on a clean tree is a guard proved on nothing.
    # -----------------------------------------------------------------------
    Write-Output '.github\scripts\identity_scan.ps1 (fixture mode): the rules, against planted repositories.'
    Write-Output 'This mode scans NO real history. Pass -Live for that.'
    Write-Output ''

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("lwg-idscan-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $root -Force | Out-Null

    function New-FixtureRepo {
        param(
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][string]$AuthorName,
            [Parameter(Mandatory)][string]$AuthorEmail,
            [string]$BodyExtra = ''
        )
        $p = Join-Path $root $Name
        New-Item -ItemType Directory -Path $p -Force | Out-Null
        & git -C $p init --quiet 2>$null | Out-Null
        # Local config only: the fixture must not inherit a machine identity, or
        # it would pass or fail according to whose laptop ran it.
        & git -C $p config user.name  $AuthorName  | Out-Null
        & git -C $p config user.email $AuthorEmail | Out-Null
        & git -C $p config commit.gpgsign false    | Out-Null
        Set-Content -LiteralPath (Join-Path $p 'a.txt') -Value 'x' -Encoding ASCII
        & git -C $p add a.txt | Out-Null
        $msg = "fixture commit"
        if ($BodyExtra) { $msg = "$msg`n`n$BodyExtra" }
        & git -C $p commit -q -m $msg | Out-Null
        return $p
    }

    # A1 - a repository whose only identity is the repository identity passes.
    $clean = New-FixtureRepo -Name 'clean' -AuthorName 'LEAPWare' -AuthorEmail 'leapware@outlook.com'
    $r = Test-Repository -RepoPath $clean
    Add-Case -Name 'A1 an allowlisted author and committer pass' `
        -Ok ($null -eq $r.aborted -and $r.offenders.Count -eq 0 -and $r.commits -eq 1) `
        -Detail ("expected 1 commit, 0 offenders, no abort; got commits={0} offenders={1} abort='{2}'" -f $r.commits, $r.offenders.Count, $r.aborted)

    # A2 - the assistant trailer is accepted, because it is on the allowlist and
    #      the harness writes it on every commit.
    $trailerOk = New-FixtureRepo -Name 'trailer-ok' -AuthorName 'LEAPWare' -AuthorEmail 'leapware@outlook.com' `
        -BodyExtra 'Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>'
    $r = Test-Repository -RepoPath $trailerOk
    Add-Case -Name 'A2 an allowlisted trailer passes' `
        -Ok ($null -eq $r.aborted -and $r.offenders.Count -eq 0) `
        -Detail ("expected 0 offenders; got {0}" -f $r.offenders.Count)

    # B1 - THE CASE THE OLD PROBE COULD NOT SEE. Author and committer are both
    #      the repository identity; the exposure is in the trailer only. This is
    #      #178, reproduced.
    $trailerBad = New-FixtureRepo -Name 'trailer-bad' -AuthorName 'LEAPWare' -AuthorEmail 'leapware@outlook.com' `
        -BodyExtra 'Co-authored-by: A Person <a.person@example.invalid>'
    $r = Test-Repository -RepoPath $trailerBad
    $hit = @($r.offenders | Where-Object { $_.field -eq 'co-authored-by' })
    Add-Case -Name 'B1 a non-allowlisted CO-AUTHOR TRAILER is caught (the #178 case)' `
        -Ok ($null -eq $r.aborted -and $hit.Count -eq 1) `
        -Detail ("expected exactly one co-authored-by offender; got {0} offender(s) in fields: {1}" -f $r.offenders.Count, (($r.offenders | ForEach-Object { $_.field }) -join ', '))

    # B2 - the field the old probe DID read, still read here.
    $authorBad = New-FixtureRepo -Name 'author-bad' -AuthorName 'A Person' -AuthorEmail 'a.person@example.invalid'
    $r = Test-Repository -RepoPath $authorBad
    $fields = @($r.offenders | ForEach-Object { $_.field } | Sort-Object -Unique)
    Add-Case -Name 'B2 a non-allowlisted author AND committer are both caught' `
        -Ok ($null -eq $r.aborted -and $fields -contains 'author' -and $fields -contains 'committer') `
        -Detail ("expected both author and committer reported; got: {0}" -f ($fields -join ', '))

    # B3 - Signed-off-by is an identity too.
    $signBad = New-FixtureRepo -Name 'signoff-bad' -AuthorName 'LEAPWare' -AuthorEmail 'leapware@outlook.com' `
        -BodyExtra 'Signed-off-by: A Person <a.person@example.invalid>'
    $r = Test-Repository -RepoPath $signBad
    Add-Case -Name 'B3 a non-allowlisted Signed-off-by is caught' `
        -Ok ($null -eq $r.aborted -and @($r.offenders | Where-Object { $_.field -eq 'signed-off-by' }).Count -eq 1) `
        -Detail ("expected one signed-off-by offender; got fields: {0}" -f (($r.offenders | ForEach-Object { $_.field }) -join ', '))

    # B4 - the shape THIS GUARD FOUND ON ITS OWN FIRST BASELINE RUN: Dependabot
    #      signs off as a GitHub role address, on every commit it makes, and the
    #      old P3-identity probe never read a trailer so nothing had ever seen
    #      it. That address is now on the allowlist - which creates a new risk
    #      this case exists to close: an allowlist entry must not turn the whole
    #      FIELD off. A different sign-off is still caught.
    $signOther = New-FixtureRepo -Name 'signoff-other' -AuthorName 'LEAPWare' -AuthorEmail 'leapware@outlook.com' `
        -BodyExtra 'Signed-off-by: someone[bot] <not-support@github.example>'
    $r = Test-Repository -RepoPath $signOther
    Add-Case -Name 'B4 allowlisting one Signed-off-by address does not stop the field being read' `
        -Ok ($null -eq $r.aborted -and @($r.offenders | Where-Object { $_.field -eq 'signed-off-by' }).Count -eq 1) `
        -Detail ("expected the non-allowlisted sign-off to be caught; got fields: {0}" -f (($r.offenders | ForEach-Object { $_.field }) -join ', '))

    # B5 - the allowlisted Dependabot pair, exactly as it appears on b12635b:
    #      the co-author on users.noreply and the sign-off on support@github.com.
    #      This is a real commit shape from this repository's history, and it
    #      must pass or every Dependabot bump reds the build.
    $depend = New-FixtureRepo -Name 'dependabot' -AuthorName 'LEAPWare' -AuthorEmail 'leapware@outlook.com' `
        -BodyExtra "Signed-off-by: dependabot[bot] <support@github.com>`nCo-authored-by: dependabot[bot] <49699333+dependabot[bot]@users.noreply.github.com>"
    $r = Test-Repository -RepoPath $depend
    Add-Case -Name 'B5 the real Dependabot trailer pair from b12635b passes' `
        -Ok ($null -eq $r.aborted -and $r.offenders.Count -eq 0) `
        -Detail ("expected 0 offenders; got {0}" -f $r.offenders.Count)

    # Re-plant a plain non-allowlisted sign-off so C1's masking case below has an
    # offender to inspect.
    $signBad = New-FixtureRepo -Name 'signoff-bad2' -AuthorName 'LEAPWare' -AuthorEmail 'leapware@outlook.com' `
        -BodyExtra 'Signed-off-by: A Person <a.person@example.invalid>'
    $r = Test-Repository -RepoPath $signBad

    # C1 - the report never prints a full address.
    # Pulled out one property at a time and forced to [string]: indexing a
    # List[object] and then dotting a property yields something PowerShell will
    # not cast to [bool] cleanly, and the resulting "Argument types do not
    # match" says nothing about which line it came from.
    $maskedAll = @($r.offenders | ForEach-Object { [string]$_.masked })
    $masked    = if ($maskedAll.Count -gt 0) { $maskedAll[0] } else { '<no offender reported>' }
    Add-Case -Name 'C1 the offender report masks the address' `
        -Ok ($masked -notmatch 'a\.person' -and $masked -notmatch 'example\.invalid' -and $masked -match '^\w\*\*\*@\w\*\*\*') `
        -Detail ("the mask must not contain the local part or the domain; got '{0}'" -f $masked)

    # C2 - a shallow repository ABORTS. This is the empty-set pass, refused.
    $deep = New-FixtureRepo -Name 'deep' -AuthorName 'LEAPWare' -AuthorEmail 'leapware@outlook.com'
    Set-Content -LiteralPath (Join-Path $deep 'b.txt') -Value 'y' -Encoding ASCII
    & git -C $deep add b.txt | Out-Null
    & git -C $deep commit -q -m 'second' | Out-Null
    $shallowPath = Join-Path $root 'shallow'
    & git clone --quiet --depth 1 ("file://" + $deep.Replace('\', '/')) $shallowPath 2>$null | Out-Null
    if (Test-Path -LiteralPath $shallowPath) {
        $r = Test-Repository -RepoPath $shallowPath
        Add-Case -Name 'C2 a shallow clone aborts rather than reporting clean' `
            -Ok ($null -ne $r.aborted -and $r.aborted -match 'SHALLOW') `
            -Detail ("expected a SHALLOW abort; got abort='{0}' commits={1}" -f $r.aborted, $r.commits)
    } else {
        Add-Case -Name 'C2 a shallow clone aborts rather than reporting clean' -Ok $false `
            -Detail 'the shallow fixture could not be cloned, so the case did not run - which is not a pass'
    }

    # C3 - a directory that is not a repository aborts.
    $notRepo = Join-Path $root 'not-a-repo'
    New-Item -ItemType Directory -Path $notRepo -Force | Out-Null
    $r = Test-Repository -RepoPath $notRepo
    Add-Case -Name 'C3 a non-repository aborts' -Ok ($null -ne $r.aborted) `
        -Detail ("expected an abort; got abort='{0}'" -f $r.aborted)

    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
else {
    # -----------------------------------------------------------------------
    # LIVE. Scan the history that would become `main`.
    # -----------------------------------------------------------------------
    $repo = (& git rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repo)) {
        Write-Output 'ABORTED: not inside a git repository, so no history was read.'
        Write-Output 'EXIT: 2'
        exit 2
    }

    $r = Test-Repository -RepoPath $repo.Trim() -Rev 'HEAD'

    if ($null -ne $r.aborted) {
        Write-Output ("ABORTED: {0}" -f $r.aborted)
        Write-Output 'Nothing about this history was established by this run.'
        Write-Output 'EXIT: 2'
        exit 2
    }

    Write-Output ("scanned {0} commit(s) reachable from HEAD" -f $r.commits)

    if ($r.offenders.Count -gt 0) {
        Write-Output ''
        Write-Output 'IDENTITIES THAT ARE NOT ON THE ALLOWLIST:'
        foreach ($o in $r.offenders) {
            Write-Output ("  - {0}  {1,-15} {2}" -f $o.sha, $o.field, $o.masked)
        }
        Write-Output ''
        Write-Output 'The address is masked on purpose: a CI log on a public repository is a'
        Write-Output 'publisher, and printing it here would re-publish the thing this guard'
        Write-Output 'exists to remove. The SHA is enough to act on.'
        Write-Output ''
        Write-Output 'If this is a new maintainer or a new bot, add it to the allowlist in this'
        Write-Output 'file WITH A REASON. If it is a personal address, do not add it: fix the'
        Write-Output 'commit, and check `git config user.email` in the clone that made it.'
    }

    Add-Case -Name 'L1 every identity on every commit reachable from HEAD is allowlisted' `
        -Ok ($r.offenders.Count -eq 0) `
        -Detail ("{0} identity/identities are not on the allowlist - see the list above" -f $r.offenders.Count)
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
