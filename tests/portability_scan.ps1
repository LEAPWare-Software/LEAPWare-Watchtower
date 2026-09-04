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
#   scope   OPTIONAL. Path globs the rule is applied to. Omit it and the rule
#           runs on every tracked file, which is the default and the right
#           answer for every rule that asks "does this name one machine?" -
#           that question has the same answer in a test as in a shipped
#           script. A rule is scoped only when the thing it forbids is a
#           property of RUNNING CODE rather than of text, and the count of
#           files each scoped rule actually ran on is printed in the summary,
#           because a scope that matches nothing is a rule that has been
#           switched off without anyone saying so.
# ===========================================================================
$Rules = @(
    @{
        id      = 'profile-path'
        name    = 'a user-profile path naming a specific profile'
        why     = 'the profile name differs on every machine, so the path resolves to nothing - or, worse, to someone else''s data. This also covers a %USERPROFILE% or $HOME that was expanded to a literal before being written down.'
        # THE `(?i)` IS LOAD-BEARING AND WAS MISSING UNTIL 3 SEPTEMBER 2026.
        # The drive letter was already covered by [A-Za-z]; the literal `Users`
        # was not, and this engine adds no IgnoreCase of its own - both Regex
        # constructions below pass RegexOptions::Compiled and nothing else. So
        # `c:\users\someone\...` matched NOTHING, and the scan's clean verdict
        # on that spelling was guaranteed rather than earned. Lowercase drive
        # paths are the everyday spelling in Git Bash output and in anything
        # copied out of a POSIX-shaped tool on this platform, so the blind spot
        # was in the ordinary case rather than an exotic one. Every sibling rule
        # already carried (?i); this was the only content rule without it.
        pattern = '(?i)(?:[A-Za-z]:|(?<![\w./\\])/[A-Za-z])[\\/]Users[\\/](<[^>]+>|[^\\/\s"''`,;:|()\[\]{}]+)'
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
        id      = 'claude-home-composition'
        name    = 'a configuration-directory path composed from $env:USERPROFILE'
        why     = 'CLAUDE_CONFIG_DIR relocates Claude Code''s configuration directory, and a path composed from $env:USERPROFILE and a literal .claude ignores it. Every component then fails DIFFERENTLY and silently against the same misconfiguration: setup writes a settings.json the CLI does not read and reports success, the doctor health-checks that unread file and reports green, the uninstaller reports a footprint from the wrong tree, the status line reads a data root nothing wrote to. Resolve through Get-LwgClaudeHomeInfo (lib/common.ps1) or LwgClaudeHome (statusline/statusline.ps1) instead - both consult CLAUDE_CONFIG_DIR first and fall back to the profile in ONE place.'
        # WHAT THIS RULE DELIBERATELY DOES NOT CATCH, said plainly rather than
        # left to be discovered. It reads ONE LINE AT A TIME, like every rule
        # here, so:
        #
        #   * A COMMENT IS NOT A COMPOSITION. Six tracked comments record the
        #     old shape - `Join-Path $env:USERPROFILE '.claude'` and friends -
        #     as history, and a comment resolves no path. The lookbehind
        #     refuses a match with a `#` earlier on the same line rather than
        #     asking six files to be edited, or six allowlist entries to be
        #     written, for prose that is correct. A live composition written
        #     after a `#` on the same line is invisible to this, and that is
        #     the price.
        #   * THE RESOLVERS THEMSELVES compose across TWO lines - `$p =
        #     $env:USERPROFILE` on one, the Combine on the next - so they do
        #     not match at all and are not what the allowlist entry below is
        #     excusing today. It is there for a reflow, and says so.
        #
        # It is a REGRESSION guard for the shape #146 removed from four files,
        # not a proof that no path escapes the resolver.
        pattern = '(?i)(?<!#[^\n]{0,400})\$env:USERPROFILE[^\n]{0,80}?[\\/''"]\.claude\b'
        # SCOPED TO THE SHIPPED EXECUTABLE PAYLOAD, and this is the one rule in
        # the file that is scoped at all. What it forbids is a resolution done
        # by RUNNING CODE, and the fourteen sites outside this scope are not
        # that: eight are documentation and CONTRIBUTING.md telling a reader to
        # type the default location, which is correct on a machine that has not
        # relocated it (the pages needing a CLAUDE_CONFIG_DIR sentence is #146
        # item 5, a document pass, and it is filed there rather than enforced
        # here); five are suite HEADER PROSE inside <# #> blocks describing the
        # sandbox, which the one-line `#` lookbehind cannot see; and one is a
        # doc_claims -Expected string quoting an install page. A rule that went
        # red on all fourteen would be answering a different question from the
        # one it was written for - "does a page name the default path?" rather
        # than "does a shipped script resolve without the variable?" - and the
        # honest way to say so is a scope with a reason, not a rule that fires
        # and an allowlist that catches it back.
        scope   = @('bin/*', 'lib/*', 'hooks/*', 'statusline/*', 'context/*',
                    'commands/*', 'agents/*', 'config.json', '.claude-plugin/*')
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
        # NARROWED ON 3 SEPTEMBER 2026, AND THE OLD SHAPE IS RECORDED HERE
        # BECAUSE THE NARROWING IS THE POINT. This entry read
        # `files = @('*')` with a test that matched any line carrying
        # `Bash(`, `PowerShell(`, `Read(`, `Edit(` or the word `catastrophic`.
        # Those are not rare strings in this tree - they are how every
        # permissions rule, every hook matcher and every tool name is written -
        # so a `line-text` entry keyed on them disarmed `interpreter-path`
        # TREE-WIDE, on every file, forever. It excused nothing on the tree the
        # day it was measured, which is exactly what makes it dangerous: the
        # entry's own `why` asserted "this excuses nothing on the current
        # tree", nothing checked that claim, and the first line to combine a
        # `Program Files` path with the word `catastrophic` would have been
        # waved through in silence. Read the COUNT to the left of this entry in
        # the report, never this prose.
        #
        # WHAT THE NARROWING IS DERIVED FROM, rather than guessed at. The rule
        # this entry is scoped to can only ever fire on an `X:\Program Files\`
        # prefix or on a `/python.exe`-shaped interpreter name. So:
        #
        #   * `C:/Windows`, `C:/ProgramData` and the bare `C:/Users` root -
        #     three of the four roots the old `why` named - MATCH NO RULE IN
        #     THIS FILE. The canonical deny fixture carries three of them
        #     (`Bash(rm -rf C:/Windows*)` and friends) and this scan has never
        #     had anything to say about those lines. They never needed
        #     excusing, and the entry never excused them.
        #   * THE `[a-z]:` BRACKET SPELLING WAS UNREACHABLE and is dropped. In
        #     `[a-z]:/Program Files/`, the character before the colon is `]`,
        #     and `interpreter-path` requires a LETTER there - so that
        #     alternative could not have excused anything under any tree. It is
        #     removed rather than kept "just in case": an alternative that
        #     cannot fire is the same defect one level down.
        #
        # What is left is the two shapes that can actually reach the rule: a
        # tool-call rule naming a universal root or an interpreter, which is
        # what a reinstated gate writes, and a call to the deleted trip-target
        # classifier, which would sit on a line carrying such a path.
        files = @('bin/lwg-setup.ps1', 'bin/lwg-uninstall.ps1', 'lib/gate_*.ps1',
                  'tests/fixtures/deny_canonical.txt', 'tests/uninstall_footprint.ps1',
                  'docs/gates-removed.md')
        test  = '(?i)Get-LwgTargetClass' +
                '|(?i)(?:Bash|PowerShell|Read|Edit)\([^)\r\n]*(?:[A-Za-z]:[\\/]Program Files|[\\/](?:python\d*|node|bash|gh|winget)\.exe)'
        why   = 'a universal Windows root or an interpreter named INSIDE A DENY RULE - `Bash(rm -rf C:/Program Files/**)` - is a thing to REFUSE, never a path anything builds from, so it is portable in the only sense this scan measures. ALL THREE SOURCES OF THOSE LITERALS ARE GONE: lib\gate_bash.ps1 was deleted on 30 July 2026 with the destructive command gate, the deny table in bin\lwg-setup.ps1 emptied the same day with secret_scan, and lib\trips.ps1 - whose Get-LwgTargetClass classified a trip target - went with the trip ledger hours later. So this excuses nothing today and is kept as a defensive entry: a future gate that reinstates any of them would otherwise fail this scan for being correct. It is scoped to the six paths such a rule could live in, and its test requires the tool-call spelling rather than the bare presence of a tool name anywhere on a line.'
    }
    @{
        id    = 'claude-home-resolver'
        kind  = 'line-text'
        rules = @('claude-home-composition')
        files = @('lib/common.ps1', 'statusline/statusline.ps1')
        test  = '\$info\.path\s*=\s*\[IO\.Path\]::Combine|return\s+\[IO\.Path\]::Combine\(\$p\.TrimEnd'
        why   = 'the ONE place each resolver is allowed to compose the historical default, reached only after CLAUDE_CONFIG_DIR has been consulted and found empty. IT EXCUSES NOTHING TODAY AND THE COUNT TO THE LEFT SAYS SO: both resolvers read the variable on one line and Combine on the next, so a line-based rule does not see a composition at all. This entry exists for the reflow that would put them on one line - a resolver reported as the defect it prevents is how a correct fix gets reverted - and it is scoped to those two files and to the two Combine statements rather than to a file or a `*`, so it cannot excuse a second composition added elsewhere in either file.'
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

function Test-InScope {
    <#
      Whether a rule applies to this file. A rule with no `scope` key applies
      everywhere, which is the default and what every rule but one uses. This
      is deliberately NOT an exemption channel: it decides whether the QUESTION
      is asked of a file, where the allowlist decides whether an ANSWER is
      excused, and the two are reported separately for that reason.
    #>
    param([hashtable]$Rule, [string]$RelPath)
    if (-not $Rule.ContainsKey('scope')) { return $true }
    foreach ($g in $Rule.scope) { if ($g -eq '*' -or $RelPath -like $g) { return $true } }
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
# How many tracked files each SCOPED rule was actually applied to. A scope that
# matches nothing is a rule that has been switched off, and the difference
# between "asked everywhere and found nothing" and "never asked" is the whole
# subject of this file's exit-code table. Unscoped rules are absent from this
# map on purpose: they run on everything, and a count equal to the file count
# would be noise printed on every run.
$scopedFiles = @{}
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

        foreach ($r in $Rules) {
            if (-not $r.ContainsKey('scope')) { continue }
            if (-not $scopedFiles.ContainsKey($r.id)) { $scopedFiles[$r.id] = 0 }
            if (Test-InScope -Rule $r -RelPath $rel) { $scopedFiles[$r.id]++ }
        }

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
                if (-not (Test-InScope -Rule $r -RelPath $rel)) { continue }

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

# ---- the allowlist ledger, ALWAYS printed ---------------------------------
# EVERY ENTRY, EVERY RUN, WHETHER OR NOT ANYTHING WAS ALLOWLISTED. This block
# used to sit inside `if ($allowedHits.Count -gt 0)`, so on a tree where no
# entry excused anything the whole list vanished and the report said nothing
# about the allowlist at all - the one state in which "which entries are doing
# work?" is hardest to answer and easiest to stop asking. The counts are the
# only honest answer to that question: an entry's `why` is prose written once
# and the number beside it is derived every run, and this repository has
# already shipped an allowlist entry whose prose asserted "excuses nothing on
# the current tree" beside a count of three.
#
# The zero rows matter more than the non-zero ones. An entry excusing nothing
# is not automatically dead - several here are deliberately defensive - but it
# is the first thing to re-read when this list is reviewed, and an entry that
# has quietly gone from 0 to 1 is a defensive entry that has become
# load-bearing without anyone deciding it should.
"ALLOWLIST - every entry, and how many matches it excused on this tree ($($allowedHits.Count) total):"
foreach ($a in $AllowList) {
    $n = $allowCount[$a.id]
    "  {0,4}  {1,-28}  {2}" -f $n, $a.id, $(if ($n -eq 0) { '(unused on this tree - defensive)' } else { $a.why })
}
if ($allowedHits.Count -gt 0) {
    if ($ShowAllowed) {
        ''
        foreach ($h in $allowedHits) {
            "  {0}:{1}: {2}  - {3}  [allowed by {4}]" -f $h.file, $h.line, $h.text, $h.rule, $h.allowId
        }
    } else {
        '     (-ShowAllowed lists each one with the file and line it is on)'
    }
}
''

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
# A scoped rule was NOT asked of every file, and a run that does not say so
# reads as though it was. Zero is the number to look at: a scope that matches
# nothing is a rule switched off with no announcement, which is the shape this
# whole file exists to refuse.
foreach ($k in ($scopedFiles.Keys | Sort-Object)) {
    $n = $scopedFiles[$k]
    "  rule $k is SCOPED and was applied to $n of $scanned file(s)" +
        $(if ($n -eq 0) { ' - ZERO, so it asked nothing of anything and cannot have found anything' } else { '' })
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
