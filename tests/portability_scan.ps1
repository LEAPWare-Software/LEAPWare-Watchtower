#requires -version 5
<#
  LW-WATCHTOWER portability scan.

      powershell -NoProfile -ExecutionPolicy Bypass -File tests\portability_scan.ps1

  WHY THIS FILE EXISTS

  This plugin ships to machines that are not the one it is written on, and three
  times now something true only of the author's laptop was stated - in a tracked
  file, with the authority of a governance layer - as though it were true
  everywhere:

    * statusline\statusline.ps1 resolved the plugin root from a literal install
      path. On any machine laid out differently the HH and GM segments found      <!-- doc-claims:ignore -->
      nothing and rendered "not installed" permanently and silently. The root is
      now DERIVED; see the comment above LwgPluginRoots. GM was deleted on
      30 July 2026 and is named here only because it existed when this happened;
      the marker on that line is what tells the GM rule in tests\doc_claims.ps1
      that this is a record rather than a live claim.
    * context\worker_facts.md is injected verbatim into EVERY subagent on every
      machine, and it asserted one laptop's absolute interpreter path, an
      assumed minor version, a stale-PATH quirk of one shell, and a claim about
      installed runtimes that was false on the machine it described.
    * verification_gate's agent-name arrays listed only roles that exist in one
      operator's untracked personal agents directory. Everywhere else it was
      enabled, counted toward the banner's coverage number, reported healthy -
      and could never match a single record.

  Each of those was found by an audit. An audit is a person remembering to look.
  This file is the same check run by a machine on every build, because the rule
  "no local environment dependencies in tracked files" is worth nothing if the
  only thing enforcing it is a paragraph in CONTRIBUTING.md.

  The mandate it enforces is docs\portability.md. Read that for the rule, the
  portable alternatives, and the allowlist policy.

  HOW IT WORKS

  Every file `git ls-files` reports is read and matched against the DETECTION
  RULES table below. A match is then offered to the ALLOWLIST table; if an entry
  excuses it, it is recorded as allowlisted rather than as a violation. Both
  tables are data - a table with a stated reason per row, not conditionals
  scattered through the code - because an allowlist whose entries carry no
  reason is an allowlist that rots into "the scanner is annoying, add a line".

  The file list is NEVER hardcoded. A hardcoded list is the exact bug this
  scanner exists to prevent, and this repo has already shipped one: CI's JSON
  check named three files by hand and so never validated a fourth that was added
  later.

  SELF-EXEMPTION. Two files must contain the very strings the rules look for:
  this one (the patterns) and docs\portability.md (the worked examples). Neither
  is skipped wholesale. Each marks the exact lines that are exempt with a region
  marker, and only the two files named in $RegionOwners may declare one - a
  marker anywhere else is itself reported as a violation, so the mechanism
  cannot be used as an escape hatch.

  WHAT IS NOT SCANNED IS NOT CLEAN, AND IT REACHES THE EXIT CODE

  Two channels used to remove a tracked file from this scan and then leave the
  exit code alone. Both printed something - one a per-file line, the other a
  clause of the summary - and neither appeared in either `if` that decides the
  code. So exit 0 was asserted, and the sentence defining it says "every tracked
  file was scanned", about runs that had skipped files.

    * A TRACKED FILE NOT ON DISK. `git ls-files` reports the index. A
      deleted-but-unstaged file, a cone-mode sparse checkout, or a path Windows
      will not open - a path past MAX_PATH, or one differing from a sibling only
      by case - all leave a path in the index with nothing to read. It printed
      `NOT SCANNED` above a `PASS` and exited 0.
    * A NUL BYTE IN THE FIRST 8 KB, read as binary. The heuristic is right for
      an actual binary and wrong for what it also catches ON THIS PLATFORM: a
      UTF-16LE file has a NUL as its SECOND byte, and on the shell this plugin
      targets some of the ordinary ways to write a file produce UTF-16LE.
      MEASURED on Windows PowerShell 5.1.26100.8875 rather than assumed,
      because the claim this rests on was wrong in the report it came from:

          'x' | Out-File f    ->  FF FE 78 00   UTF-16LE with a BOM
          'x' > f             ->  FF FE 78 00   UTF-16LE with a BOM
          'x' | Set-Content f ->  78 0D 0A      ASCII, no BOM

      So `>` and `Out-File` are the routes and SET-CONTENT IS NOT - it defaults
      to ASCII in Windows PowerShell 5.1, and the widely repeated claim that it
      writes UTF-16 is false here. Set-Content has a different hazard, outside
      this rule: ASCII silently replaces every non-ASCII character, and these
      pages are full of em dashes.

      One `(Get-Content x.md) -replace ... > x.md` re-encodes a tracked page and
      exempted it from this scan permanently, reported as one clause of one line
      above a PASS that did not name the file.

  Both now exit 2 and both are NAMED. 2 rather than 1 deliberately: 1 says the
  tree was checked and is dirty, and its own text tells the reader to "Fix the
  file", which is unactionable advice about a file that was never read.
  Conflating "dirty" with "not read" is the collapse the exit-code table exists
  to prevent.

  A GENUINE BINARY still has to be skippable, so $BinaryAllowList below is the
  channel - the same discipline as the allowlist further down, an entry per
  path with a stated reason. It is EMPTY today because no tracked file trips the
  probe. A UTF-16 file cannot be excused through it, and that is not an
  oversight: the answer to a UTF-16 tracked file is to re-save it, not to
  exempt it.

  NOTE WHAT THIS DOES AND DOES NOT BUY. It does not make the scan complete - it
  makes an incomplete scan impossible to mistake for a complete one on the only
  channel the header says a CI job reads. A file that is skipped is still not
  scanned.

  EXIT CODES - a CI job reads these and nothing else.

      0  every tracked file was scanned and nothing machine-specific was found
      1  at least one violation - a local environment dependency is in the tree
      2  the scan ABORTED, or it could not read every tracked file, or an owner
         file left an exempt region open; the tree was NOT fully checked, which
         is not the same as passing. An enumeration returning zero files is an
         abort, never a pass, and 2 takes precedence over 1 - a run that did not
         read everything cannot report "checked, and dirty" either.

  No network. No writes of any kind. Nothing here deletes, moves or modifies a
  file: it opens tracked files for reading and prints.
#>
[CmdletBinding()]
param(
    # Print every allowlisted match with the entry that excused it, not just the
    # per-entry totals. Use this when reviewing whether the allowlist still
    # earns its place.
    [switch]$ShowAllowed,

    # Repo root. Defaults to this file's parent, which is correct for a run from
    # anywhere as long as the file stays in tests\.
    [string]$Root
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }

# The two files permitted to declare an exempt region, and why each one has to.
# Anything else carrying a region marker is a violation, not an exemption.
$RegionOwners = @(
    @{ path = 'tests/portability_scan.ps1'
       why  = 'holds the detection patterns themselves; every rule would match its own definition' }
    @{ path = 'docs/portability.md'
       why  = 'the mandate has to SHOW what is refused, so its worked examples are deliberate violations' }
)

# ===========================================================================
# BINARY ALLOWLIST - DELIBERATELY EMPTY.
#
# The only legitimate way for a tracked file to leave this scan unread. A file
# whose first 8 KB holds a NUL byte cannot be scanned as text; if it is a real
# binary - an icon, a fixture recorded byte for byte - it belongs here with a
# reason, and it is then counted and named in the report rather than folded
# into a clean exit. Anything else that trips the probe exits 2.
#
#   files  repo-relative path globs
#   why    one line, stating why this file is legitimately unreadable as text
#
# THE POLICY, which matters more than the schema. A UTF-16 file is NOT a
# candidate and is refused this channel by construction - see the header. The
# fix for one is to re-save it as UTF-8, which takes a minute and restores the
# scan's coverage of that page; exempting it here would hand away coverage of a
# tracked page permanently, in exchange for nothing.
# ===========================================================================
$BinaryAllowList = @()

# Matches `# LWG-SCAN-REGION: begin` in PowerShell and `<!-- LWG-SCAN-REGION: end -->`
# in markdown. Anchored to the start of a comment so this line, which holds the
# same words in the middle of an expression, cannot match itself.
$RegionMarker = '^\s*(?:#|<!--)\s*LWG-SCAN-REGION:\s*(begin|end)\b'

# LWG-SCAN-REGION: begin
# ===========================================================================
# DETECTION RULES
#
#   id      short name used in the report and in allowlist scoping
#   name    what the rule is looking for, printed beside every hit
#   why     what goes wrong on someone else's machine when this ships
#   pattern the regex. Group 1, where present, is the part the allowlist
#           inspects (currently only the profile-name segment).
# ===========================================================================
$Rules = @(
    @{
        id      = 'profile-path'
        name    = 'a user-profile path naming a specific profile'
        why     = 'the profile name differs on every machine, so the path resolves to nothing - or, worse, to someone else''s data. This also covers a %USERPROFILE% or $HOME that was expanded to a literal before being written down.'
        pattern = '(?:[A-Za-z]:|(?<![\w./\\])/[A-Za-z])[\\/]Users[\\/](<[^>]+>|[^\\/\s"''`,;:|()\[\]{}]+)'
    }
    @{
        id      = 'owner-username'
        name    = 'the repository owner''s account name'
        why     = 'an account name is the single most machine-specific string there is. It is never correct on another machine and never needed on this one.'
        pattern = '(?i)\bleapw\b'
    }
    @{
        id      = 'hostname'
        name    = 'a Windows default computer name'
        why     = 'a hostname identifies one physical machine. Nothing portable can branch on it, and nothing shipped should name it.'
        pattern = '(?i)\b(?:DESKTOP|LAPTOP)-[A-Z0-9]{5,}\b'
    }
    @{
        id      = 'interpreter-path'
        name    = 'an absolute path to an interpreter or tool'
        why     = 'install location and version directory both vary. worker_facts.md pinned one and injected it into every subagent on every machine; resolve the tool from PATH, or state the requirement without a path.'
        pattern = '(?i)(?:[A-Za-z]:[\\/]Program Files(?: \(x86\))?[\\/]|[\\/](?:python\d*|node|bash|gh|winget)\.exe\b)'
    }
    @{
        id      = 'private-hierarchy'
        name    = 'the owner''s private folder hierarchy'
        why     = 'this is where one person keeps their clones. Three install snippets once had to agree on it, so a reader who cloned elsewhere reached a Copy-Item that copied nothing.'
        pattern = '(?i)LEAPWare-HQ[\\/]leapware-software'
    }
    @{
        id      = 'plugin-install-path'
        name    = 'a drive-absolute plugin install path'
        why     = 'the plugin root must be DERIVED - from ${CLAUDE_PLUGIN_ROOT}, $PSScriptRoot, or $env:USERPROFILE. A literal one blinded the status line permanently on every machine laid out differently. Note the anchor: only a drive-letter-absolute spelling is refused, so the derived forms are untouched.'
        pattern = '(?i)[A-Za-z]:[\\/][^\s"''`]*\.claude[\\/](?:skills[\\/]lw-watchtower|plugins[\\/]repos)'
    }
    @{
        id      = 'region-marker'
        name    = 'a scanner-exempt region declared outside the two owner files'
        why     = 'the exempt-region mechanism exists so this file and the mandate can quote the patterns. Any other file using it is opting itself out of the scan, which is the thing the scan is for.'
        pattern = '^\s*(?:#|<!--)\s*LWG-SCAN-REGION:'
    }
)

# ===========================================================================
# ALLOWLIST
#
# Every entry needs a reason. An entry without one is how this rots into a
# list of "things that were annoying once", and a reviewer cannot tell a
# legitimate exemption from a silenced defect without it.
#
#   id     name used in the report and in the per-entry ledger below
#   kind   which predicate decides the entry (the vocabulary is fixed):
#            profile-name  group 1 of the match - the profile segment
#            match-text    the matched text
#            line-text     the whole line the match sits on
#            code-span     the match lies inside a `backtick span` - the only
#                          predicate that takes no `test`
#            attributed    an attribution phrase is on the line, within the
#                          three lines above it, or heads the table it is in
#   rules  which detection rules it may excuse. '*' means any.
#   files  repo-relative path globs it applies to. '*' means anywhere.
#   test   the regex the predicate applies
#   why    one line, stating why this is legitimate rather than tolerated
# ===========================================================================
$AllowList = @(
    @{
        id    = 'derived-profile-segment'
        kind  = 'profile-name'
        rules = @('profile-path')
        files = @('*')
        test  = '^[$%{]'
        why   = 'the profile segment is a variable - C:\Users\$env:USERNAME, C:\Users\%USERNAME% - so the path is BUILT on the machine it runs on rather than written down. Note what needs no entry at all: ${CLAUDE_PLUGIN_ROOT}, $PSScriptRoot and $env:USERPROFILE derivations match no rule in the first place, because every path rule is anchored on a literal drive letter. The portable forms are not exempted here; they are simply never detected.'
    }
    @{
        id    = 'reader-placeholder'
        kind  = 'profile-name'
        rules = @('profile-path')
        files = @('*')
        test  = '^<[^>]+>$'
        why   = 'an angle-bracketed stand-in - <you>, <your-name>, <path where you cloned> - is an instruction to the reader to substitute their own value. It names no machine and cannot be mistaken for a path.'
    }
    @{
        id    = 'illustrative-placeholder'
        kind  = 'profile-name'
        rules = @('profile-path')
        files = @('*')
        test  = '^(?:me|you|us|someone|somebody|user|username|USERNAME|example)$'
        why   = 'a generic stand-in inside an explanatory comment - C:/Users/me and friends. It is not a real profile on any machine and is never used to build a path. The one file that used it, lib\gate_bash.ps1, was deleted on 30 July 2026, so this entry excuses nothing on this tree today and is kept as a defensive rule for the next comment that needs a stand-in.'
    }
    @{
        id    = 'glob-wildcard'
        kind  = 'profile-name'
        rules = @('profile-path')
        files = @('*')
        test  = '^\**$'
        why   = 'a wildcard segment is a pattern that matches whatever the local profile turns out to be - the portable spelling of a deny rule, not a machine-specific path.'
    }
    @{
        id    = 'deliberate-sentinel'
        kind  = 'profile-name'
        rules = @('profile-path')
        files = @('*')
        test  = '^(?:LWG-PARITY-FIXTURE|lwtest|UNKNOWN)$'
        why   = 'fixed sentinels chosen so a test is comparable on every machine, and never a real profile. WHAT IT EXCUSES TODAY IS THREE LINES, all of them in tests\fixtures\deny_canonical.txt, where LWG-PARITY-FIXTURE is the profile segment of a deny rule. UNTIL 3 AUGUST 2026 THIS TEXT SAID "CURRENTLY EXCUSES NOTHING - the scan reports it as unused", and it was true when written: both files that used a sentinel had been deleted on 30 July 2026 - tests\gate_regression.ps1 with the destructive command gate, and tests\deny_parity.ps1 with secret_scan, the latter having pinned $env:USERPROFILE to LWG-PARITY-FIXTURE so its tracked fixture compared equal on a runner. That fixture was then restored to the tree from ef993bc as the subject of Test-CanonicalDenyRulesAllAttributed in tests\uninstall_footprint.ps1, the count moved 0 to 3, and the sentence stayed - so this scan printed the count and a denial of the count on the same line, which is the exact defect this repository exists to catch, sitting inside its own allowlist. READ THE COUNT, NOT THIS PROSE: the number to the left is derived every run and this text is not. WHAT IS EXCUSED IS WEAKER THAN WHAT WAS: a sentinel in fixture DATA, not a test pinning its own $env:USERPROFILE. No file on this tree does the latter, so the rule is still defensive in the sense that mattered - it is not currently keeping any running test portable. Keep it whatever the count says: a sentinel is the correct way to write a machine-comparable test, and re-deriving this rule under a failing build is how a real profile name gets allowlisted by mistake.'
    }
    @{
        id    = 'ci-runner-profile'
        kind  = 'profile-name'
        rules = @('profile-path')
        files = @('*')
        test  = '^runneradmin$'
        why   = 'the profile name on GitHub''s hosted Windows images - a property of the CI runner every contributor shares, not of anyone''s laptop. It appears only in prose explaining why the sentinel above is needed.'
    }
    @{
        id    = 'universal-windows-root'
        kind  = 'line-text'
        rules = @('interpreter-path')
        files = @('*')
        test  = '(?i)(?:^|[^A-Za-z])\[a-z\]:|(?:Bash|PowerShell|Read|Edit)\(|Get-LwgTargetClass|catastrophic'
        why   = 'C:/Windows, C:/ProgramData, C:/Program Files and the bare C:/Users root were named as things to REFUSE, never as paths anything builds from - they are universal on every Windows install. ALL THREE SOURCES OF THESE LITERALS ARE NOW GONE: lib\gate_bash.ps1 was deleted on 30 July 2026 with the destructive command gate, the deny table in bin\lwg-setup.ps1 emptied the same day with secret_scan, and lib\trips.ps1 - whose Get-LwgTargetClass classified a trip target - went with the trip ledger hours later. So this excuses nothing on the current tree and is kept as a defensive entry: a future gate that reinstates any of them would otherwise fail this scan for being correct. Get-LwgTargetClass is still named in the test pattern for that reason, not because the function exists.'
    }
    @{
        id    = 'changelog-removed-literal'
        kind  = 'code-span'
        rules = @('profile-path', 'interpreter-path', 'private-hierarchy', 'plugin-install-path')
        files = @('CHANGELOG.md')
        why   = 'the changelog is an append-only record of what was fixed, and an entry about a removed literal has to quote the literal to be evidence of anything. It is never executed and nothing builds a path from it. Deliberately does NOT cover owner-username or hostname: quoting one of those has no such justification, so the changelog is still refused them. The backtick requirement keeps this to code spans rather than to the whole file.'
        test  = ''
    }
    @{
        id    = 'attributed-observation'
        kind  = 'attributed'
        rules = @('profile-path', 'interpreter-path', 'private-hierarchy', 'plugin-install-path')
        files = @('docs/architecture.md')
        test  = '(?i)(the author''s machine|on this machine|measured (?:on|here)|one development machine)'
        why   = 'architecture.md records measurements and a data-directory census taken on one machine, and says so on the line or at the head of the table. An observation labelled as one machine''s is honest reporting; the defect is an unlabelled one presented as universal. The attribution must be on the same line, within the three lines above, or heading the table the match sits in - a bare mention elsewhere in the file does not excuse anything. It covers PATHS only: an attribution is a reason to quote a measured path, never a reason to name an account or a host, so those two rules still fire here.'
    }
)
# LWG-SCAN-REGION: end

# The machine this scan is running on, added as a rule at runtime so its name is
# never a literal in a tracked file. Machine-dependent by construction: it can
# only ever find MORE than the static rules above, never fewer, so a green CI run
# is not weakened by a laptop's hostname differing from the runner's.
$thisHost = [string]$env:COMPUTERNAME
if ($thisHost.Length -ge 6) {
    $Rules += @{
        id      = 'this-hostname'
        name    = "this machine's own computer name"
        why     = 'the name of the machine the scan is running on has no business in a tracked file.'
        pattern = '(?i)\b' + [regex]::Escape($thisHost) + '\b'
    }
}

# ---------------------------------------------------------------------------
# Predicates. The vocabulary the allowlist's `kind` field selects from, and
# nothing else decides an exemption.
# ---------------------------------------------------------------------------

function Test-InCodeSpan {
    <# True when the match sits inside an odd-numbered `backtick span`. #>
    param([string]$Line, [int]$Start)
    $ticks = 0
    for ($i = 0; $i -lt $Start -and $i -lt $Line.Length; $i++) {
        if ($Line[$i] -eq '`') { $ticks++ }
    }
    return (($ticks % 2) -eq 1)
}

function Test-Attributed {
    <#
      True when the attribution phrase is on the match's own line, on one of the
      three lines above it, or - for a match inside a markdown table - on the
      line that introduces that table. Anything looser would let one honest
      "measured on this machine" halfway up a file excuse every literal below it.
    #>
    param([string[]]$Lines, [int]$Index, [string]$Attribution)

    for ($i = $Index; $i -ge 0 -and $i -ge ($Index - 3); $i--) {
        if ($Lines[$i] -match $Attribution) { return $true }
    }
    if ($Lines[$Index] -match '^\s*\|') {
        for ($i = $Index - 1; $i -ge 0; $i--) {
            if ($Lines[$i] -match '^\s*\|' -or [string]::IsNullOrWhiteSpace($Lines[$i])) { continue }
            return ($Lines[$i] -match $Attribution)
        }
    }
    return $false
}

function Test-Allowed {
    <# The first allowlist entry that excuses this match, or $null. #>
    param(
        [hashtable]$Rule, [string]$RelPath, [string[]]$Lines, [int]$Index,
        [string]$MatchText, [int]$MatchStart, [string]$Captured
    )
    $line = $Lines[$Index]
    foreach ($a in $AllowList) {
        if (($a.rules -notcontains '*') -and ($a.rules -notcontains $Rule.id)) { continue }

        $scoped = $false
        foreach ($g in $a.files) { if ($g -eq '*' -or $RelPath -like $g) { $scoped = $true; break } }
        if (-not $scoped) { continue }

        $hit = $false
        switch ($a.kind) {
            'profile-name' { $hit = ($Captured -ne '') -and ($Captured -match $a.test) }
            'match-text'   { $hit = ($MatchText -match $a.test) }
            'line-text'    { $hit = ($line -match $a.test) }
            'code-span'    { $hit = Test-InCodeSpan -Line $line -Start $MatchStart }
            'attributed'   { $hit = Test-Attributed -Lines $Lines -Index $Index -Attribution $a.test }
            default        { throw "allowlist entry '$($a.id)' declares kind '$($a.kind)', which is not one of profile-name / match-text / line-text / code-span / attributed" }
        }
        if ($hit) { return $a }
    }
    return $null
}

# ===========================================================================
# MAIN
# ===========================================================================

$sw          = [Diagnostics.Stopwatch]::StartNew()
$violations  = New-Object System.Collections.ArrayList
$allowedHits = New-Object System.Collections.ArrayList
$allowCount  = @{}
foreach ($a in $AllowList) { $allowCount[$a.id] = 0 }
$scanned = 0
# $binary was a bare counter, so the summary could say "skipped 1 binary" and a
# UTF-16 re-encode of a tracked page was indistinguishable from a committed
# .png. Each of these carries the file and the reason it was not read.
$binary        = New-Object System.Collections.ArrayList
$binaryAllowed = New-Object System.Collections.ArrayList
$missing       = New-Object System.Collections.ArrayList
# Owner files whose exempt region was opened and never closed. `$inRegion` is
# set by a `begin` marker and cleared only by an `end`, with no balance check,
# so an unmatched `begin` silently removed EVERY REMAINING LINE of the file
# from the scan - while $scanned++ had already counted the file as fully read.
$unbalanced    = New-Object System.Collections.ArrayList
# Lines an owner file's exempt region removed from the scan, per file. Reported
# beside the file count, because "scanned N file(s)" says nothing about how much
# of them was read.
$exemptLines   = @{}
$aborted = ''

try {
    'LW-WATCHTOWER portability scan'
    "  repo    : $Root"
    "  mandate : docs\portability.md"
    "  rules   : $($Rules.Count)   allowlist entries: $($AllowList.Count)"

    $compiled = @{}
    foreach ($r in $Rules) {
        $compiled[$r.id] = New-Object System.Text.RegularExpressions.Regex(
            $r.pattern, [System.Text.RegularExpressions.RegexOptions]::Compiled)
    }
    $markerRx = New-Object System.Text.RegularExpressions.Regex($RegionMarker)

    # Prescreen. Most lines match no rule at all, and running eight regexes over
    # every one of them costs seconds. This is the union of the SAME patterns,
    # built from $Rules rather than written out, so it cannot drift from them and
    # cannot quietly drop a rule the way a hand-maintained list of literal hints
    # would. A line the union does not match cannot match any single rule; a line
    # it does match is still put through all eight individually.
    $unionRx = New-Object System.Text.RegularExpressions.Regex(
        ('(?:' + (($Rules | ForEach-Object { $_.pattern }) -join ')|(?:') + ')'),
        [System.Text.RegularExpressions.RegexOptions]::Compiled)

    $files = @(& git -C $Root ls-files | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($LASTEXITCODE -ne 0) { throw "git ls-files exited $LASTEXITCODE - the file list could not be enumerated" }
    if ($files.Count -eq 0) {
        # The empty-set pass this repo has been bitten by once already. Zero
        # files scanned is a broken enumeration, never a clean tree.
        throw 'git ls-files returned no files - the enumeration is broken, so nothing was scanned'
    }
    "  files   : $($files.Count) tracked"
    ''

    $ownerPaths = @($RegionOwners | ForEach-Object { $_.path })

    foreach ($rel in $files) {
        $abs = Join-Path $Root ($rel -replace '/', '\')
        if (-not [IO.File]::Exists($abs)) { [void]$missing.Add($rel); continue }

        $bytes = [IO.File]::ReadAllBytes($abs)
        $probe = [Math]::Min($bytes.Length, 8192)
        if ($probe -gt 0 -and [Array]::IndexOf($bytes, [byte]0, 0, $probe) -ge 0) {
            # THE BOM SPLIT. A UTF-16 file is text in the wrong encoding and the
            # answer is to re-save it; a real binary is what the heuristic is
            # for. They produced the same silent line before, which is why the
            # everyday Windows case - Set-Content re-encoding a tracked page -
            # could exempt that page from the scan forever without anybody
            # reading anything but "skipped 1 binary".
            #
            # The window size is NOT the lever here and changing it fixes
            # nothing: a UTF-16 file has a NUL in its first four bytes, so no
            # window makes it text.
            $isUtf16 = ($bytes.Length -ge 2 -and (
                ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or
                ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF)))
            $allowB = $null
            if (-not $isUtf16) {
                foreach ($b in $BinaryAllowList) {
                    foreach ($g in $b.files) { if ($rel -like $g) { $allowB = $b; break } }
                    if ($allowB) { break }
                }
            }
            if ($allowB) {
                [void]$binaryAllowed.Add([pscustomobject]@{ file = $rel; why = $allowB.why })
            } else {
                $why = $(if ($isUtf16) {
                    'it carries a UTF-16 BOM. In Windows PowerShell 5.1 both > and Out-File write UTF-16LE by default (Set-Content does NOT - it writes ASCII), so this is almost certainly a tracked TEXT file that was re-saved through one of them. Re-save it as UTF-8 and re-run. It cannot be excused through $BinaryAllowList.'
                } else {
                    'its first 8 KB holds a NUL byte, so it cannot be read as text. If it is genuinely a binary, add it to $BinaryAllowList with a reason.'
                })
                [void]$binary.Add([pscustomobject]@{ file = $rel; why = $why })
            }
            continue
        }

        $lines = ([Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)) -split "`r`n|`n|`r"
        $scanned++

        $isOwner  = $ownerPaths -contains $rel
        $inRegion = $false
        $skippedHere = 0

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]

            if ($isOwner) {
                $mk = $markerRx.Match($line)
                if ($mk.Success) {
                    $inRegion = ($mk.Groups[1].Value -eq 'begin')
                    continue
                }
                if ($inRegion) { $skippedHere++; continue }
            }

            if (-not $unionRx.IsMatch($line)) { continue }

            foreach ($r in $Rules) {
                # A region marker in one of the two owner files is the mechanism
                # working as designed, so the rule that reports it elsewhere does
                # not fire on them.
                if ($r.id -eq 'region-marker' -and $isOwner) { continue }

                foreach ($m in $compiled[$r.id].Matches($line)) {
                    $captured = ''
                    if ($m.Groups.Count -gt 1 -and $m.Groups[1].Success) {
                        $captured = $m.Groups[1].Value.TrimEnd('.')
                    }
                    $allow = Test-Allowed -Rule $r -RelPath $rel -Lines $lines -Index $i `
                                          -MatchText $m.Value -MatchStart $m.Index -Captured $captured
                    $rec = [pscustomobject]@{
                        file = $rel; line = ($i + 1); text = $m.Value
                        rule = $r.id; ruleName = $r.name; why = $r.why
                        allowId = $(if ($allow) { $allow.id } else { '' })
                        allowWhy = $(if ($allow) { $allow.why } else { '' })
                    }
                    if ($allow) {
                        $allowCount[$allow.id]++
                        [void]$allowedHits.Add($rec)
                    } else {
                        [void]$violations.Add($rec)
                    }
                }
            }
        }

        # An owner file that opened an exempt region and never closed it removed
        # every remaining line of itself from the scan, and $scanned++ above had
        # already counted the file as read. There was no balance check and no
        # warning, so the two states produced identical output.
        if ($isOwner -and $inRegion) { [void]$unbalanced.Add($rel) }
        if ($skippedHere -gt 0) { $exemptLines[$rel] = $skippedHere }
    }
} catch {
    $aborted = "$($_.Exception.Message)  [line $($_.InvocationInfo.ScriptLineNumber)]"
}

$sw.Stop()

if ($aborted) {
    ''
    '==========================================================================='
    "ABORTED: $aborted"
    'EXIT: 2 (the tracked tree was NOT scanned, which is not the same as passing)'
    exit 2
}

# ---- allowlisted, and why -------------------------------------------------
if ($allowedHits.Count -gt 0) {
    "ALLOWLISTED - matched a rule, and is legitimate ($($allowedHits.Count)):"
    foreach ($a in $AllowList) {
        $n = $allowCount[$a.id]
        # An entry excusing nothing is called out rather than hidden. It is not
        # automatically dead - several are deliberately defensive - but it is
        # the first thing to re-read when this list is reviewed.
        "  {0,4}  {1,-26}  {2}" -f $n, $a.id, $(if ($n -eq 0) { '(unused on this tree - defensive)' } else { $a.why })
    }
    if ($ShowAllowed) {
        ''
        foreach ($h in $allowedHits) {
            "  {0}:{1}: {2}  - {3}  [allowed by {4}]" -f $h.file, $h.line, $h.text, $h.rule, $h.allowId
        }
    } else {
        '     (-ShowAllowed lists each one with the file and line it is on)'
    }
    ''
}

# ---- violations -----------------------------------------------------------
if ($violations.Count -gt 0) {
    "VIOLATIONS - a local environment dependency in a tracked file ($($violations.Count)):"
    ''
    foreach ($v in $violations) {
        "  {0}:{1}: {2}  - {3}: {4}" -f $v.file, $v.line, $v.text, $v.rule, $v.ruleName
    }
    ''
    'The rule each one broke, and what it costs on another machine:'
    foreach ($g in ($violations | Group-Object rule)) {
        $r = $Rules | Where-Object { $_.id -eq $g.Name } | Select-Object -First 1
        ''
        "  $($g.Name) ($($g.Count)) - $($r.name)"
        foreach ($w in ($r.why -split '(?<=\.) (?=[A-Z$%])')) { "      $($w.Trim())" }
    }
    ''
}

# ---- what was NOT read ----------------------------------------------------
# Every one of these carries the file and the reason, and every one of them
# reaches the exit code below. A skipped file is not a clean file.
$notScanned = @()
foreach ($m in $missing) {
    "  NOT SCANNED  $m - tracked but not present on disk. A deleted-but-unstaged file, a sparse checkout, or a path Windows will not open all produce this."
    $notScanned += $m
}
foreach ($b in $binary) {
    "  NOT SCANNED  $($b.file) - $($b.why)"
    $notScanned += $b.file
}
foreach ($u in $unbalanced) {
    "  PARTLY SCANNED  $u - an LWG-SCAN-REGION: begin marker was never closed, so every line after it was skipped."
    $notScanned += $u
}
if ($binaryAllowed.Count -gt 0) {
    "  ALLOWLISTED BINARY - not scanned, and deliberately so ($($binaryAllowed.Count)):"
    foreach ($b in $binaryAllowed) { "    $($b.file) - $($b.why)" }
}

'==========================================================================='
"scanned $scanned file(s) in $([int]$sw.Elapsed.TotalMilliseconds) ms" +
    $(if ($binary.Count -gt 0)        { ", $($binary.Count) unreadable as text" } else { '' }) +
    $(if ($binaryAllowed.Count -gt 0) { ", $($binaryAllowed.Count) allowlisted binary" } else { '' }) +
    $(if ($missing.Count -gt 0)       { ", $($missing.Count) not on disk" }   else { '' }) +
    $(if ($unbalanced.Count -gt 0)    { ", $($unbalanced.Count) with an unclosed exempt region" } else { '' })
foreach ($k in ($exemptLines.Keys | Sort-Object)) {
    "  $($exemptLines[$k]) line(s) of $k were inside a declared exempt region and were not read"
}
"RESULT: $($violations.Count) violation(s), $($allowedHits.Count) allowlisted"

# ORDER: 2 BEFORE 1, AND THAT IS THE DELIBERATE PART. Exit 1 means "the tree was
# checked and is dirty" and its own text tells the reader to fix a file. A run
# that could not read every tracked file has not established the first half, so
# it must not claim it - the violations it DID find are printed above either
# way, and this block says so rather than letting the exit code swallow them.
if ($notScanned.Count -gt 0) {
    "EXIT: 2 ($($notScanned.Count) tracked file(s) were not fully read, so this run cannot say"
    '         every tracked file is clean. Each is named above with the reason. A UTF-16'
    '         file - which is what Windows PowerShell Set-Content and > write by default -'
    '         lands here: re-save it as UTF-8. A real binary belongs in $BinaryAllowList'
    '         with a reason. An unclosed LWG-SCAN-REGION marker is a bug in the file.'
    if ($violations.Count -gt 0) {
        "         NOTE: $($violations.Count) violation(s) were also found and are listed above."
        '         They are real and still have to be fixed; this run simply cannot also'
        '         claim the files it never read are clean.'
    }
    exit 2
}
if ($violations.Count -gt 0) {
    'EXIT: 1 (a tracked file carries something true only of one machine. Fix the'
    '         file - do NOT add an allowlist entry unless the match is genuinely'
    '         portable, and if it is, say why in the entry. docs\portability.md)'
    exit 1
}
'EXIT: 0 (every tracked file was read, and none carries a local environment dependency)'
exit 0
