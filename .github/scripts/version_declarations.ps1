#requires -version 5
<#
  LW-WATCHTOWER version declaration guard.

      powershell -NoProfile -ExecutionPolicy Bypass -File .github\scripts\version_declarations.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File .github\scripts\version_declarations.ps1 -Live
      powershell -NoProfile -ExecutionPolicy Bypass -File .github\scripts\version_declarations.ps1 -Live -Tag v0.4.0

  WHY THIS FILE EXISTS

  This file was written while this repository had never cut a release from
  itself: no tag, no GitHub Release, and - until the workflow beside this file -
  nothing that reacts to a tag. THAT IS NO LONGER TRUE, and the sentence is
  rewritten rather than deleted because the guard's reason for existing is
  clearer with its own starting condition on the record. `v0.4.0` was tagged at
  `7952992` on 2026-09-04 and published, and this file's first real exercise was
  that tag's own run. CONTRIBUTING.md already carries the checklist and the rule
  it exists for - `main` must never declare a version a tag has already published -
  and names the five sites that declare it. Nothing enforced any of it at the
  moment a tag is pushed, which is the only moment the rule can still be acted
  on cheaply.

  WHERE IT RUNS, AND WHY THE TWO CALLERS ASK DIFFERENT QUESTIONS (#219)

  This file was invoked from `release.yml` and from nowhere else until 3
  September 2026, and `release.yml` is tag-triggered - so a declaration that had
  drifted apart was checked on release day and at no other moment. Quiet drift
  turned into a release-day failure, in the one workflow where the cost of
  stopping is highest. `ci.yml` now runs it too, and the two invocations are
  deliberately not the same run:

    ci.yml, every push and pull request   -Live, NO -Tag. Asserts that the five
                                          declarations agree WITH EACH OTHER,
                                          and that the version they state is not
                                          one an existing tag already published.
                                          The two tag-shaped rules print NOT
                                          CHECKED, which is a decline.

    release.yml, on a tag                 -Live -Tag vX.Y.Z. Asserts that every
                                          site states exactly what the TAG says
                                          and that CHANGELOG.md's heading for
                                          that version is dated. Those are the
                                          two rules the pull-request run cannot
                                          ask, because there is no tag to ask
                                          them about.

  Both callers run the FIXTURES first and refuse to trust a -Live answer from a
  guard whose own rules did not fire.

  WHAT IT CHECKS, AND WHAT EACH ONE COSTS WHEN IT IS WRONG

    * declarations-agree - all five declaration sites state the same version.
      A half-finished bump - plugin.json edited, config.json left behind - ships
      one tree under two numbers, and the loader and the banner then disagree
      about what a reporter is running.

    * tag-matches-declarations - when a tag is being released, every site states
      exactly what the tag says. A Release published from a tree that declares
      something else is a Release whose own manifests contradict its name, and
      no consumer can tell which of the two is the tested one.

    * changelog-entry-is-dated - CHANGELOG.md carries a `## [X.Y.Z]` heading for
      the version and that heading is NOT `unreleased`. The heading is the only
      tracked record of what a tag contained, and publishing while it still says
      `unreleased` produces a Release whose notes say the release has not
      happened.

    * version-not-a-published-tag - OFF a release, the declared version is not
      one `git tag -l` already lists. This is CONTRIBUTING.md's rule, and it is
      the one that has never been checkable here: it needs a visible tag ref AND
      at least one tag to exist. An empty tag list is reported NOT CHECKED, not
      as a pass - the same choice tests\doc_claims.ps1 makes, and for the same
      reason: a probe that could not run must never render as a probe that ran
      and found nothing.

  THE DECLARATION / CITATION DISTINCTION IS THE WHOLE POINT, and it is
  CONTRIBUTING.md's, not this file's. A DECLARATION is a field a machine reads,
  and there are five. Everything else that names a version - a changelog heading
  for an old release, a line recording which tag an acceptance pass ran against,
  a handoff page's record
  of what a banner printed on a day - is a CITATION of a tag and is correct
  forever. This file reads the five declarations and one changelog heading it is
  handed the version for. It reads no prose, matches no version-shaped string
  anywhere else, and therefore cannot turn a record into an error.

  WHY IT IS NOT UNDER tests\

  Every file in tests\ exercises the PLUGIN, and tests\doc_claims.ps1 derives
  two documented numbers by enumerating tests\*.ps1. This one asserts nothing
  about the product - it reads manifests and a changelog at release time - so
  counting it there would make both of those numbers less true. It sits beside
  identity_scan.ps1 and pr_issue_ref.ps1, which are in .github\scripts\ for
  exactly that reason, and beside the workflows that call it.

  FIXTURES FIRST, THE TREE SECOND

  A bare invocation runs the FIXTURES: planted trees in a throwaway directory
  under the temp root, one per rule, each proving that rule can FIRE. A guard
  proved only against a clean tree is proved against nothing, which is the shape
  this repository has been bitten by more than once. Only -Live reads this
  repository, and only -Live can pass or fail it.

  EXIT CODES - the 0/1/2 contract every guard here uses.

      0  everything asked was checked and held
      1  a rule failed - read the lines above the summary
      2  the guard ABORTED: a declaration site was missing or unreadable, so
         nothing was established. Not clean, and not a pass.

  No network. It reads files, runs `git tag -l`, and under the fixture run
  writes only into a GUID directory under the temp root that it deletes again.
#>
[CmdletBinding()]
param(
    # DEFAULT is the fixture run, the same way round as pr_issue_ref.ps1: a bare
    # invocation establishes that the rules fire and judges no real tree.
    [switch]$Live,

    # The tag being released, with or without the leading `v`. When given, the
    # five declarations must equal it and the changelog heading for it must be
    # dated. When absent, the published-tag rule runs instead.
    [string]$Tag,

    # The tree to read. Defaults to the repository this file is in.
    [string]$Root,

    # Write the changelog section for the version to this file, for a release
    # body. Only written when every rule passed - notes for a tree that failed
    # its own checks are notes nobody should publish.
    [string]$NotesPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

# A dash class rather than a literal em dash: the headings in CHANGELOG.md use
# U+2014, this file stays ASCII so no encoding can maim it, and a hyphen typed
# by hand still matches.
$script:DashClass = '[-\u2010-\u2015]'

function Say { param([string]$Text) Write-Host $Text }

# ===========================================================================
# READING THE TREE
#
# The five sites and the regexes are CONTRIBUTING.md's table and
# tests\doc_claims.ps1's derivation. They are duplicated here rather than
# imported because doc_claims.ps1 is a suite that aborts the build on a sibling
# failure and this file has to run inside a release workflow with no suite
# around it - but they must move together. If a literal moves in lib\, it moves
# in tests\doc_claims.ps1 and here.
# ===========================================================================

function Get-LwgLineOf {
    param([string[]]$Lines, [string]$Pattern)
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match $Pattern) { return ($i + 1) }
    }
    return 0
}

function Get-LwgVersionSites {
    <#
      The five declaration sites, or a throw naming the one that could not be
      read. A site this file cannot read is an ABORT: reporting four agreeing
      declarations while the fifth was never opened is the empty-set pass.
    #>
    param([string]$TreeRoot)

    $sites = @()

    # FOUR OF THE FIVE SITES MOVED WITH THE PAYLOAD RESTRUCTURE and one did not.
    # $TreeRoot is still the REPOSITORY root - correct and unchanged - but the
    # plugin manifest, config.json and the two PowerShell literals now live under
    # lw-watchtower/, while marketplace.json stays at the repository root because
    # that is the file the CLI reads to add the marketplace. A site this file
    # cannot read is a throw by design, so getting this wrong is a hard release
    # failure rather than a silent one - which is why the prefix is named once
    # here and not spelled into four Join-Path calls.
    $payloadRel = 'lw-watchtower'

    $plugRel  = "$payloadRel/.claude-plugin/plugin.json"
    $plugPath = Join-Path $TreeRoot "$payloadRel\.claude-plugin\plugin.json"
    if (-not (Test-Path -LiteralPath $plugPath -PathType Leaf)) { throw "missing $plugRel" }
    $plugLines = @(Get-Content -LiteralPath $plugPath)
    try { $plugJson = ($plugLines -join "`n") | ConvertFrom-Json }
    catch { throw "$plugRel did not parse, so its version was never read: $($_.Exception.Message)" }
    if ([string]::IsNullOrWhiteSpace([string]$plugJson.version)) { throw "$plugRel declares no version." }
    $sites += [pscustomobject]@{ Rel = $plugRel; Line = (Get-LwgLineOf $plugLines '"version"\s*:'); Value = [string]$plugJson.version }

    $mktRel  = '.claude-plugin/marketplace.json'
    $mktPath = Join-Path $TreeRoot '.claude-plugin\marketplace.json'
    if (-not (Test-Path -LiteralPath $mktPath -PathType Leaf)) { throw "missing $mktRel" }
    $mktLines = @(Get-Content -LiteralPath $mktPath)
    try { $mktJson = ($mktLines -join "`n") | ConvertFrom-Json }
    catch { throw "$mktRel did not parse, so its version was never read: $($_.Exception.Message)" }
    # By NAME, never by index: this marketplace hosts one plugin today and an
    # index would start reading the wrong entry the day it hosts two.
    $mktEntry = @($mktJson.plugins | Where-Object { $_.name -eq $plugJson.name })
    if ($mktEntry.Count -ne 1) {
        throw ("$mktRel holds {0} entries named '{1}', expected exactly 1, so its version was never read." -f $mktEntry.Count, $plugJson.name)
    }
    if ([string]::IsNullOrWhiteSpace([string]$mktEntry[0].version)) { throw "$mktRel's '$($plugJson.name)' entry declares no version." }
    $sites += [pscustomobject]@{ Rel = $mktRel; Line = (Get-LwgLineOf $mktLines '"version"\s*:'); Value = [string]$mktEntry[0].version }

    $cfgRel  = "$payloadRel/config.json"
    $cfgPath = Join-Path $TreeRoot "$payloadRel\config.json"
    if (-not (Test-Path -LiteralPath $cfgPath -PathType Leaf)) { throw "missing $cfgRel" }
    $cfgLines = @(Get-Content -LiteralPath $cfgPath)
    try { $cfgJson = ($cfgLines -join "`n") | ConvertFrom-Json }
    catch { throw "$cfgRel did not parse, so its version was never read: $($_.Exception.Message)" }
    if ([string]::IsNullOrWhiteSpace([string]$cfgJson.version)) { throw "$cfgRel declares no version." }
    $sites += [pscustomobject]@{ Rel = $cfgRel; Line = (Get-LwgLineOf $cfgLines '"version"\s*:'); Value = [string]$cfgJson.version }

    # The two PowerShell literals are read by regex because there is nothing to
    # parse - they are assignments, and dot-sourcing either file to learn one
    # string would run a hook prologue.
    $literals = @(
        @{ Rel = "$payloadRel/lib/common.ps1";        Path = "$payloadRel\lib\common.ps1";        Pattern = "\`$script:LwgVersion\s*=\s*'([^']+)'" }
        @{ Rel = "$payloadRel/lib/session_start.ps1"; Path = "$payloadRel\lib\session_start.ps1"; Pattern = "(?m)^\s*\`$version\s*=\s*'([^']+)'" }
    )
    foreach ($lit in $literals) {
        $litPath = Join-Path $TreeRoot $lit.Path
        if (-not (Test-Path -LiteralPath $litPath -PathType Leaf)) { throw ("missing {0}" -f $lit.Rel) }
        $litLines = @(Get-Content -LiteralPath $litPath)
        $m = [regex]::Match(($litLines -join "`n"), $lit.Pattern)
        if (-not $m.Success) {
            throw ("no version literal matched in {0}, so that declaration was never read. If it moved, this pattern moves with it - and so does tests\doc_claims.ps1's." -f $lit.Rel)
        }
        $sites += [pscustomobject]@{ Rel = $lit.Rel; Line = (Get-LwgLineOf $litLines $lit.Pattern); Value = $m.Groups[1].Value }
    }

    return $sites
}

function Get-LwgChangelogSection {
    <#
      The `## [X.Y.Z] - <what>` heading for one version and the lines under it up
      to the next `## ` heading. Returns $null when there is no such heading.
      `What` is the text after the dash verbatim, so the caller decides what
      `unreleased` means rather than this function guessing.
    #>
    param([string]$TreeRoot, [string]$Version)

    $path = Join-Path $TreeRoot 'CHANGELOG.md'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'missing CHANGELOG.md' }
    # -Encoding UTF8 IS LOAD-BEARING AND WAS FOUND THE HARD WAY. CHANGELOG.md is
    # UTF-8 with no byte-order mark, and Windows PowerShell 5.1 reads such a file
    # as the ANSI code page by default - so the em dash the headings use came
    # back as three Latin-1 characters, the dash class did not match, and this
    # rule reported the heading for the version being released as ABSENT while it
    # was on line twenty of the file. A rule that fails for an encoding reason is
    # worse than one that does not exist, because it fails LOUDLY about the wrong
    # thing.
    $lines = @(Get-Content -LiteralPath $path -Encoding UTF8)

    $headPat = '^##\s+\[' + [regex]::Escape($Version) + '\]\s*(?:' + $script:DashClass + '\s*(.*))?$'
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $m = [regex]::Match($lines[$i], $headPat)
        if (-not $m.Success) { continue }
        $what = ''
        if ($m.Groups.Count -gt 1) { $what = $m.Groups[1].Value.Trim() }
        $body = @()
        for ($j = $i + 1; $j -lt $lines.Count; $j++) {
            if ($lines[$j] -match '^##\s') { break }
            $body += $lines[$j]
        }
        return [pscustomobject]@{
            Line = ($i + 1); Heading = $lines[$i]; What = $what; Body = ($body -join "`n").Trim()
        }
    }
    return $null
}

function Get-LwgPublishedTags {
    <#
      What `git tag -l` returns, and whether that answer means anything. Zero
      tags is NOT "there are none": it is also what a clone whose tag refs were
      never fetched prints, and reading that silence as a pass is the defect this
      whole rule exists to avoid.
    #>
    param([string]$TreeRoot)
    $tags = @()
    $code = $null
    Push-Location -LiteralPath $TreeRoot
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out  = & git --no-pager tag -l 2>$null
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEap
        Pop-Location
    }
    if ($code -eq 0) { $tags = @($out | Where-Object { $_ }) }
    return [pscustomobject]@{
        Known = ($code -eq 0 -and $tags.Count -gt 0)
        Tags  = $tags
    }
}

# ===========================================================================
# THE RULES
# ===========================================================================

function Invoke-LwgVersionCheck {
    <#
      Reads one tree and returns what held, what did not, and what was not
      checked. Throws on an unreadable declaration site - the caller turns that
      into exit 2.
    #>
    param([string]$TreeRoot, [string]$ReleaseTag)

    $failures = @()
    $passes   = @()
    $declined = @()

    $sites = Get-LwgVersionSites -TreeRoot $TreeRoot
    $ref   = $sites[0]

    # --- declarations-agree -------------------------------------------------
    foreach ($s in $sites) {
        if ($s.Rel -eq $ref.Rel) { continue }
        if ($s.Value -eq $ref.Value) {
            $passes += ("declarations-agree        {0}:{1} says {2}" -f $s.Rel, $s.Line, $s.Value)
        } else {
            $failures += ("declarations-agree        {0}:{1} says {2}, {3} says {4}" -f $s.Rel, $s.Line, $s.Value, $ref.Rel, $ref.Value)
        }
    }

    $declared = $ref.Value

    if (-not [string]::IsNullOrWhiteSpace($ReleaseTag)) {
        # --- tag-matches-declarations --------------------------------------
        # Both spellings, because nothing forces a tag to carry the `v` and the
        # declarations never do.
        $wanted = $ReleaseTag -replace '^v', ''
        foreach ($s in $sites) {
            if ($s.Value -eq $wanted) {
                $passes += ("tag-matches-declarations  {0}:{1} says {2}" -f $s.Rel, $s.Line, $s.Value)
            } else {
                $failures += ("tag-matches-declarations  {0}:{1} says {2}, tag {3} says {4}" -f $s.Rel, $s.Line, $s.Value, $ReleaseTag, $wanted)
            }
        }

        # --- changelog-entry-is-dated ---------------------------------------
        $section = Get-LwgChangelogSection -TreeRoot $TreeRoot -Version $wanted
        if ($null -eq $section) {
            $failures += ("changelog-entry-is-dated  CHANGELOG.md carries no '## [{0}]' heading, so this release has no tracked record of what it contains" -f $wanted)
        } elseif ($section.What -match '(?i)unreleased' -or [string]::IsNullOrWhiteSpace($section.What)) {
            $failures += ("changelog-entry-is-dated  CHANGELOG.md:{0} reads '{1}' - date it before the tag, or the Release notes announce a release that has not happened" -f $section.Line, $section.Heading.Trim())
        } elseif ([string]::IsNullOrWhiteSpace($section.Body)) {
            $failures += ("changelog-entry-is-dated  CHANGELOG.md:{0} is dated and empty, so the Release would carry no notes" -f $section.Line)
        } else {
            $passes += ("changelog-entry-is-dated  CHANGELOG.md:{0} {1}" -f $section.Line, $section.Heading.Trim())
        }
    } else {
        $declined += 'tag-matches-declarations  NOT CHECKED - no tag was named, so there is nothing to match against'
        $declined += 'changelog-entry-is-dated  NOT CHECKED - the heading to read is the one for the tag being released'

        # --- version-not-a-published-tag ------------------------------------
        $t = Get-LwgPublishedTags -TreeRoot $TreeRoot
        if (-not $t.Known) {
            $declined += 'version-not-a-published-tag  NOT CHECKED - git tag -l returned nothing, which is what an unfetched tag ref and an unreleased repository both look like. Not a pass.'
        } else {
            foreach ($s in $sites) {
                $clash = @($t.Tags | Where-Object { $_ -eq $s.Value -or $_ -eq ('v' + $s.Value) })
                if ($clash.Count -eq 0) {
                    $passes += ("version-not-a-published-tag  {0}:{1} says {2}" -f $s.Rel, $s.Line, $s.Value)
                } else {
                    $failures += ("version-not-a-published-tag  {0}:{1} says {2} and tag {3} already published it - bump the declaration" -f $s.Rel, $s.Line, $s.Value, ($clash -join ', '))
                }
            }
        }
    }

    return [pscustomobject]@{
        Declared = $declared; Sites = $sites
        Failures = $failures; Passes = $passes; Declined = $declined
    }
}

# ===========================================================================
# FIXTURES - one planted tree per rule, each proving the rule can FIRE
# ===========================================================================

function New-LwgFixtureTree {
    param(
        [string]$Root, [string]$Name,
        [string]$PluginVersion, [string]$MarketplaceVersion, [string]$ConfigVersion,
        [string]$CommonVersion, [string]$SessionVersion,
        [string]$ChangelogHeading, [string]$ChangelogBody
    )
    # THE FIXTURE TREE IS SHAPED LIKE THE REAL ONE, and that is the whole value
    # of it: marketplace.json at the fixture ROOT and the other four under
    # lw-watchtower/, exactly as Get-LwgVersionSites now expects. A fixture that
    # kept the flat layout would have gone on passing while the live tree threw.
    $t = Join-Path $Root $Name
    $tp = Join-Path $t 'lw-watchtower'
    New-Item -ItemType Directory -Path (Join-Path $t  '.claude-plugin') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tp '.claude-plugin') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tp 'lib') -Force | Out-Null

    Set-Content -LiteralPath (Join-Path $tp '.claude-plugin\plugin.json') -Encoding UTF8 -Value @"
{
  "name": "lw-watchtower",
  "version": "$PluginVersion"
}
"@
    Set-Content -LiteralPath (Join-Path $t '.claude-plugin\marketplace.json') -Encoding UTF8 -Value @"
{
  "name": "leapware",
  "plugins": [
    {
      "name": "lw-watchtower",
      "version": "$MarketplaceVersion"
    }
  ]
}
"@
    Set-Content -LiteralPath (Join-Path $tp 'config.json') -Encoding UTF8 -Value @"
{
  "version": "$ConfigVersion"
}
"@
    Set-Content -LiteralPath (Join-Path $tp 'lib\common.ps1') -Encoding UTF8 -Value "`$script:LwgVersion = '$CommonVersion'"
    Set-Content -LiteralPath (Join-Path $tp 'lib\session_start.ps1') -Encoding UTF8 -Value "`$version = '$SessionVersion'"

    # UTF-8 with NO byte-order mark, because that is what the real CHANGELOG.md
    # is, and a fixture written with a BOM would have let the em-dash case pass
    # while the live tree failed - which is exactly what happened before this
    # line said `$false`.
    $cl = "# Changelog`n`n$ChangelogHeading`n`n$ChangelogBody`n"
    [IO.File]::WriteAllText((Join-Path $t 'CHANGELOG.md'), $cl, (New-Object Text.UTF8Encoding($false)))
    return $t
}

function Invoke-LwgFixtures {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("lwg-verdecl-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $cases = 0
    $bad   = 0

    function Assert-Case {
        param([string]$Name, [bool]$Ok, [string]$Detail)
        $script:fxCases++
        if ($Ok) { Say ("  [ok]   {0}" -f $Name) }
        else { $script:fxBad++; Say ("  [FAIL] {0} - {1}" -f $Name, $Detail) }
    }
    $script:fxCases = 0
    $script:fxBad   = 0

    try {
        Say 'Fixtures - one planted tree per rule, each proving the rule can fire.'
        Say ''

        # 1. A tree that agrees with itself and with its tag, dated changelog.
        $clean = New-LwgFixtureTree -Root $root -Name 'clean' `
            -PluginVersion '9.9.9' -MarketplaceVersion '9.9.9' -ConfigVersion '9.9.9' `
            -CommonVersion '9.9.9' -SessionVersion '9.9.9' `
            -ChangelogHeading '## [9.9.9] - 2026-01-01' -ChangelogBody '- an invented entry'
        $r = Invoke-LwgVersionCheck -TreeRoot $clean -ReleaseTag 'v9.9.9'
        Assert-Case 'clean tree at its tag reports no failure' ($r.Failures.Count -eq 0) ("failures: " + ($r.Failures -join '; '))

        # 2. A half-finished bump: config.json left on the old number.
        $split = New-LwgFixtureTree -Root $root -Name 'half-bumped' `
            -PluginVersion '9.9.9' -MarketplaceVersion '9.9.9' -ConfigVersion '9.9.8' `
            -CommonVersion '9.9.9' -SessionVersion '9.9.9' `
            -ChangelogHeading '## [9.9.9] - 2026-01-01' -ChangelogBody '- an invented entry'
        $r = Invoke-LwgVersionCheck -TreeRoot $split -ReleaseTag 'v9.9.9'
        Assert-Case 'declarations-agree fires on a half-finished bump' `
            (@($r.Failures | Where-Object { $_ -like 'declarations-agree*config.json*' }).Count -eq 1) `
            ("failures: " + ($r.Failures -join '; '))

        # 3. A tag that no declaration states.
        $r = Invoke-LwgVersionCheck -TreeRoot $clean -ReleaseTag 'v9.9.7'
        Assert-Case 'tag-matches-declarations fires when the tag is not the declared version' `
            (@($r.Failures | Where-Object { $_ -like 'tag-matches-declarations*' }).Count -eq 5) `
            ("failures: " + ($r.Failures -join '; '))

        # 4. A changelog heading still reading `unreleased`.
        $undated = New-LwgFixtureTree -Root $root -Name 'undated' `
            -PluginVersion '9.9.9' -MarketplaceVersion '9.9.9' -ConfigVersion '9.9.9' `
            -CommonVersion '9.9.9' -SessionVersion '9.9.9' `
            -ChangelogHeading '## [9.9.9] - unreleased' -ChangelogBody '- an invented entry'
        $r = Invoke-LwgVersionCheck -TreeRoot $undated -ReleaseTag 'v9.9.9'
        Assert-Case 'changelog-entry-is-dated fires on an unreleased heading' `
            (@($r.Failures | Where-Object { $_ -like 'changelog-entry-is-dated*' }).Count -eq 1) `
            ("failures: " + ($r.Failures -join '; '))

        # 5. No changelog heading at all for the version being released.
        $r = Invoke-LwgVersionCheck -TreeRoot $clean -ReleaseTag 'v9.9.6'
        Assert-Case 'changelog-entry-is-dated fires when the heading is absent' `
            (@($r.Failures | Where-Object { $_ -like '*carries no*heading*' }).Count -eq 1) `
            ("failures: " + ($r.Failures -join '; '))

        # 6. The em dash the real CHANGELOG.md uses, not the hyphen above.
        $emdash = New-LwgFixtureTree -Root $root -Name 'emdash' `
            -PluginVersion '9.9.9' -MarketplaceVersion '9.9.9' -ConfigVersion '9.9.9' `
            -CommonVersion '9.9.9' -SessionVersion '9.9.9' `
            -ChangelogHeading ("## [9.9.9] " + [char]0x2014 + " 2026-01-01") -ChangelogBody '- an invented entry'
        $r = Invoke-LwgVersionCheck -TreeRoot $emdash -ReleaseTag 'v9.9.9'
        Assert-Case 'the em dash heading in CHANGELOG.md is read as dated' ($r.Failures.Count -eq 0) `
            ("failures: " + ($r.Failures -join '; '))

        # 7. version-not-a-published-tag, off a release, against a real tag.
        $tagged = New-LwgFixtureTree -Root $root -Name 'tagged' `
            -PluginVersion '9.9.9' -MarketplaceVersion '9.9.9' -ConfigVersion '9.9.9' `
            -CommonVersion '9.9.9' -SessionVersion '9.9.9' `
            -ChangelogHeading '## [9.9.9] - 2026-01-01' -ChangelogBody '- an invented entry'
        # $ErrorActionPreference is dropped to Continue around these four calls
        # on purpose. git writes ordinary NOTICES to stderr - the autocrlf line
        # is the one that turns up here - and under 'Stop' PowerShell 5.1 turns
        # any stderr from a native binary into a terminating NativeCommandError.
        # A fixture repository would then fail to build for a warning about line
        # endings, and the rule it exists to prove would go unproven.
        Push-Location -LiteralPath $tagged
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & git init --quiet 2>&1 | Out-Null
            & git -c user.email=fixture@example.invalid -c user.name=fixture add -A 2>&1 | Out-Null
            & git -c user.email=fixture@example.invalid -c user.name=fixture commit --quiet -m 'fixture' 2>&1 | Out-Null
            & git tag v9.9.9 2>&1 | Out-Null
        } finally {
            $ErrorActionPreference = $prevEap
            Pop-Location
        }
        $r = Invoke-LwgVersionCheck -TreeRoot $tagged -ReleaseTag ''
        Assert-Case 'version-not-a-published-tag fires when the declared version is already a tag' `
            (@($r.Failures | Where-Object { $_ -like 'version-not-a-published-tag*' }).Count -eq 5) `
            ("failures: " + ($r.Failures -join '; ') + " declined: " + ($r.Declined -join '; '))

        # 8. The same rule on a tree with NO tags: NOT CHECKED, never a pass.
        $r = Invoke-LwgVersionCheck -TreeRoot $clean -ReleaseTag ''
        Assert-Case 'version-not-a-published-tag declines rather than passing with no tags' `
            (@($r.Declined | Where-Object { $_ -like 'version-not-a-published-tag*NOT CHECKED*' }).Count -eq 1 -and $r.Failures.Count -eq 0) `
            ("declined: " + ($r.Declined -join '; '))

        # 9. A missing declaration site ABORTS rather than reporting four agreeing.
        $maimed = New-LwgFixtureTree -Root $root -Name 'maimed' `
            -PluginVersion '9.9.9' -MarketplaceVersion '9.9.9' -ConfigVersion '9.9.9' `
            -CommonVersion '9.9.9' -SessionVersion '9.9.9' `
            -ChangelogHeading '## [9.9.9] - 2026-01-01' -ChangelogBody '- an invented entry'
        Remove-Item -LiteralPath (Join-Path $maimed 'lw-watchtower\config.json') -Force
        $threw = $false
        try { Invoke-LwgVersionCheck -TreeRoot $maimed -ReleaseTag 'v9.9.9' | Out-Null }
        catch { $threw = $true }
        Assert-Case 'a missing declaration site aborts rather than reporting the rest as clean' $threw 'no throw'

        $cases = $script:fxCases
        $bad   = $script:fxBad
    } finally {
        # A fixture repository holds a .git the shell keeps read-only handles on;
        # the retry is why this is not a bare Remove-Item.
        for ($i = 0; $i -lt 3; $i++) {
            try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop; break }
            catch { Start-Sleep -Milliseconds 200 }
        }
    }

    Say ''
    Say ("fixtures: {0} of {1} passed" -f ($cases - $bad), $cases)
    if ($bad -gt 0) { return 1 }
    return 0
}

# ===========================================================================
# MAIN
# ===========================================================================

Say 'LW-WATCHTOWER version declarations'
Say ("  root : {0}" -f $Root)
Say ("  mode : {0}" -f $(if ($Live) { 'live' } else { 'fixtures' }))
if ($Live -and -not [string]::IsNullOrWhiteSpace($Tag)) { Say ("  tag  : {0}" -f $Tag) }
Say ''

if (-not $Live) {
    exit (Invoke-LwgFixtures)
}

try {
    $result = Invoke-LwgVersionCheck -TreeRoot $Root -ReleaseTag $Tag
} catch {
    Say ("ABORTED: {0}" -f $_.Exception.Message)
    Say 'EXIT: 2 (a declaration was never read, which is not the same as it agreeing)'
    exit 2
}

Say ("declared version: {0}" -f $result.Declared)
Say ''
foreach ($p in $result.Passes)   { Say ("  [ok]      {0}" -f $p) }
foreach ($d in $result.Declined) { Say ("  [--]      {0}" -f $d) }
foreach ($f in $result.Failures) { Say ("  [FAIL]    {0}" -f $f) }
Say ''

if ($result.Failures.Count -gt 0) {
    Say ("RESULT: {0} failure(s)" -f $result.Failures.Count)
    Say 'EXIT: 1'
    exit 1
}

if (-not [string]::IsNullOrWhiteSpace($NotesPath) -and -not [string]::IsNullOrWhiteSpace($Tag)) {
    $wanted  = $Tag -replace '^v', ''
    $section = Get-LwgChangelogSection -TreeRoot $Root -Version $wanted
    if ($null -eq $section) {
        Say 'ABORTED: the changelog section passed its own rule and then could not be re-read.'
        Say 'EXIT: 2'
        exit 2
    }
    # UTF-8 with NO byte-order mark: a BOM at the head of a release body renders
    # as a stray character in the first line of the published notes, and
    # Set-Content -Encoding UTF8 writes one under Windows PowerShell 5.1.
    [IO.File]::WriteAllText($NotesPath, $section.Body, (New-Object Text.UTF8Encoding($false)))
    Say ("notes written to {0} from CHANGELOG.md:{1}" -f $NotesPath, $section.Line)
}

Say ("RESULT: 0 failure(s), {0} declined" -f $result.Declined.Count)
Say 'EXIT: 0 (every declaration this run could check agrees; a declined line is not a pass)'
exit 0
