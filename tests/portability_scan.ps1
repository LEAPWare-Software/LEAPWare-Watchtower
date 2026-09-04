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

  A RULE THAT ASKED NOTHING IS NOT A RULE THAT FOUND NOTHING, AND UNTIL 3
  SEPTEMBER 2026 THE TWO EXITED THE SAME WAY. A rule may carry a `scope` - path
  globs limiting it to the files whose ROLE makes its question meaningful. Those
  globs are matched against what `git ls-files` prints, which is repo-root
  relative, so ONE path change breaks all of a rule's globs at once: moving the
  shipped payload under lw-watchtower/ left every glob in
  claude-home-composition's scope matching nothing. The run PRINTED the zero -
  and exited 0, because nothing consumed that line. A rule switched off by an
  unrelated rename was therefore indistinguishable, on the only channel a CI job
  reads, from a rule that ran everywhere and found nothing. It is now exit 2 and
  the rule is NAMED, which is the answer tests\payload_guard.ps1's S7 already
  gave to the same question in the sibling guard.

  AND A SCOPE THAT NARROWED IS THE SAME DEFECT ONE LEVEL DOWN, WHICH THE
  WHOLE-RULE CHECK ABOVE CANNOT SEE. Measured, not supposed: the payload move
  did not take claude-home-composition's scope to zero, it took it to ONE. Eight
  of its nine globs died at the rename and the ninth, `.claude-plugin/*`,
  matched `.claude-plugin/marketplace.json`, which stays at the repository root
  because that is where the CLI reads a marketplace from. So the run printed
  `applied to 1 of 94 file(s)`, the boolean above was satisfied, and a rule 97%
  switched off exited 0. That is the general shape rather than a quirk of one
  path: a scope is a LIST, one entry per role it covers, and a path change
  breaks the entries that moved and leaves the ones that did not. The result is
  almost never zero. It is narrowed. (#247)

  So EVERY GLOB IS ASSERTED, NOT EVERY SCOPE - in a rule's `scope` and in an
  allowlist entry's `files` alike. A glob matching none of the scanned files
  exits 2 and is named, in a `NOT REACHED` line beside the `NOT ASKED` line the
  whole-rule check writes. Eight of the nine would have gone red on the move
  that motivated this, on the commit that made it.

  THE STRICTNESS OBJECTION IS ANSWERED BY DECLARATION RATHER THAN BY TOLERANCE.
  A glob may legitimately name a directory that is empty today - a defensive
  allowlist entry is allowed to name a file that does not exist yet. Such a glob
  writes

      @{ glob = 'docs/whatever.md'; may_be_empty = 'why it is legitimately empty' }

  in place of the bare string, and the reason is PRINTED in the reach ledger
  beside the zero. A dead glob with no such declaration is a defect; a declared
  one is a stated expectation, and the declaration is a line a reviewer can
  disagree with. That keeps a legitimate deletion honest - delete the glob with
  its subject - and a silent narrowing loud. A `may_be_empty` glob that DOES
  reach files is printed as such and not failed: going red on a correct addition
  would be the same trap the other way round.

  NO GLOB IN THIS FILE CARRIES ONE TODAY, and that sentence is not prose anybody
  has to keep true: every glob in every scope and in every entry's `files`
  reaches at least one tracked file, and the moment one stops doing so this scan
  exits 2 and names it. So the mechanism ships unused, which is the right state
  for it - a declaration is a thing to write when a real subject is missing, not
  a thing to keep one of on hand.

  THIS REVERSES WHAT THIS FILE SAID UNTIL 4 SEPTEMBER 2026, and the argument it
  reverses is worth keeping because it is right about everything except its
  conclusion. It ran: a dead SCOPE makes the scan silently ask LESS - the
  question stops being put, no file answers it, and the exit code is the same 0
  as a clean tree - while a dead ALLOWLIST entry can only make it ask MORE,
  since the matches it would have excused become violations and the run goes
  loudly red naming the file, the line and the rule. Asymmetric failure modes,
  asymmetric answers: reach was measured and printed, never failed.

  What that misses is the case where the entry excuses nothing TODAY. Then
  nothing turns red, because there is nothing to turn red: a defensive entry
  whose globs have quietly died is indistinguishable, on every channel, from a
  defensive entry standing ready - and the first line that needs it will be
  reported as a violation with no hint that an entry meant to cover it exists
  three files away. The loudness the old argument relied on is a property of
  entries that are currently firing, and those are the ones least likely to have
  gone dead. `may_be_empty` is what makes asserting both safe: the correct
  deletion the old argument protected is now declared rather than tolerated.

  The ledger still prints TWO numbers per entry, because one cannot answer for
  the other: the matches the entry excused, and the scanned files its globs
  reach. Zero excused of two in reach is a defensive entry doing its job; zero
  excused of zero in reach is now a failure rather than a note.

  EXIT CODES - a CI job reads these and nothing else.

      0  every tracked file was scanned and nothing machine-specific was found
      1  at least one violation - a local environment dependency is in the tree
      2  the scan ABORTED, or it could not read every tracked file, or an owner
         file left an exempt region open, or a SCOPED RULE was applied to no
         file at all, or a single GLOB - in a rule's scope or an allowlist
         entry's files - matched no scanned file without declaring
         `may_be_empty`; the tree was NOT fully checked, which is not the same
         as passing. An enumeration returning zero files is an abort, never a
         pass, and 2 takes precedence over 1 - a run that did not read
         everything, or did not ask everything, cannot report "checked, and
         dirty" either.

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
#           property of RUNNING CODE rather than of text. The count of files
#           each scoped rule actually ran on is printed in the summary, and a
#           count of ZERO EXITS 2 with the rule named: a scope that matches
#           nothing is a rule switched off without anyone saying so, and it is
#           printed AND asserted rather than only printed.
#
#           EVERY GLOB IN THE LIST IS ASSERTED SEPARATELY, and that is the half
#           the whole-rule count cannot supply. Nine globs down to one after a
#           rename is a rule still "applied" and barely asking - the boolean is
#           satisfied and the corpus has collapsed by 97%. Each glob's own
#           reach is printed and a zero exits 2 naming the glob (#247). An
#           entry may be written as a hashtable instead of a string to declare
#           that emptiness is expected:
#
#             scope = @('lw-watchtower/bin/*',
#                       @{ glob = 'lw-watchtower/skills/*'
#                          may_be_empty = 'no skill ships yet; the role is
#                                          named so the first one is scanned' })
#
#           The reason is printed beside the zero in the reach ledger. Omitting
#           it is not an option: `may_be_empty` with no reason aborts, because
#           the reason IS the declaration.
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
        # EVERY GLOB HERE IS MATCHED AGAINST WHAT `git ls-files` PRINTS, which is
        # repo-root-relative, and the shipped payload moved under lw-watchtower/.
        # Left unprefixed after that move these globs match NOTHING, and the rule
        # is then switched off. That used to print a line and exit 0 - the one
        # shape this whole file is written to refuse, built into the file itself.
        # It now exits 2 and names this rule; see the header. The globs stay
        # spelled out one directory at a time rather than as `lw-watchtower/*`
        # because the scope is a statement about which ROLES are asked, and a
        # single wildcard would silently absorb whatever is added beside them.
        scope   = @('lw-watchtower/bin/*', 'lw-watchtower/lib/*', 'lw-watchtower/hooks/*',
                    'lw-watchtower/statusline/*', 'lw-watchtower/context/*',
                    'lw-watchtower/commands/*', 'lw-watchtower/agents/*',
                    'lw-watchtower/config.json', 'lw-watchtower/.claude-plugin/*')
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
#
# THE `files` GLOBS ARE MATCHED AGAINST `git ls-files` OUTPUT, exactly like a
# rule's `scope`, and a path change breaks them the same way - the payload move
# under lw-watchtower/ broke three of the entries below. The ledger prints, per
# entry, how many scanned files its globs REACH alongside how many matches it
# excused, and then one line per glob with its own reach.
#
# EVERY GLOB IS ASSERTED. A glob reaching none of the scanned files exits 2 and
# is named, the same answer a rule's scope gets (#247). Until 4 September 2026
# reach here was printed and not failed, on the argument that a dead entry can
# only make the scan louder - which is true of an entry that is CURRENTLY
# EXCUSING SOMETHING and false of the defensive ones, where nothing turns red
# because there is nothing to turn red. The header carries the full reversal.
#
# A glob that is legitimately empty says so, in place of the bare string:
#
#     files = @('CHANGELOG.md',
#               @{ glob = 'docs/not-yet.md'; may_be_empty = 'the page this
#                  entry defends has not been written; see #NNN' })
#
# and its reason is printed beside the zero. `'*'` reaches every scanned file
# by construction and is never at issue.
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
        # THREE OF THESE SIX MOVED WITH THE PAYLOAD AND THREE DID NOT: the setup
        # and uninstall scripts and the gate library are under lw-watchtower/ now;
        # the fixture, the suite and the page stayed at the repository root.
        files = @('lw-watchtower/bin/lwg-setup.ps1', 'lw-watchtower/bin/lwg-uninstall.ps1',
                  'lw-watchtower/lib/gate_*.ps1',
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
        files = @('lw-watchtower/lib/common.ps1', 'lw-watchtower/statusline/statusline.ps1')
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

function Get-GlobSpecs {
    <#
      Normalises one glob list - a rule's `scope` or an allowlist entry's
      `files` - into one record per glob carrying the glob and the reason, if
      any, that it is allowed to reach nothing. Both spellings are accepted so
      that declaring an expectation is a change to one entry rather than to
      every entry in the table:

        'lw-watchtower/bin/*'
        @{ glob = 'lw-watchtower/skills/*'; may_be_empty = 'no skill ships yet' }

      A `may_be_empty` with no reason ABORTS rather than being read as a bare
      declaration. The reason is the whole of what makes a declared empty glob
      different from a dead one - without it this key is a way to switch the
      assertion off silently, which is the shape the assertion exists to refuse.

      RETURNS BARE, AND EVERY CALLER WRAPS IN @(). The other spelling of this -
      `return ,$out`, the unrolling guard lib\common.ps1:961 records - is WRONG
      here and was written that way first: the comma stops the unroll, the
      caller's @() then wraps the already-wrapped array, and `$specs` comes back
      as ONE element holding all nine globs. Member enumeration hides it - the
      ledger printed `[string]$g` of the whole array as one glob and the
      assertion read a reason built from nine empty strings, so a nine-glob
      scope passed as one declared-empty entry. Both spellings cannot be right;
      @() at the call site is the one that survives a single-glob list too.
    #>
    param($Globs)
    $out = @()
    foreach ($g in $Globs) {
        if ($g -is [hashtable]) {
            if (-not $g.ContainsKey('glob') -or [string]::IsNullOrWhiteSpace([string]$g.glob)) {
                throw "a glob written as a hashtable must carry a non-empty 'glob' key; this one carries: $(($g.Keys | Sort-Object) -join ', ')"
            }
            $reason = ''
            if ($g.ContainsKey('may_be_empty')) {
                $reason = [string]$g.may_be_empty
                if ([string]::IsNullOrWhiteSpace($reason)) {
                    throw "glob '$($g.glob)' declares may_be_empty with no reason. The reason IS the declaration: without it this is an assertion switched off in silence."
                }
            }
            $out += [pscustomobject]@{ Glob = [string]$g.glob; MayBeEmpty = $reason }
        } else {
            $out += [pscustomobject]@{ Glob = [string]$g; MayBeEmpty = '' }
        }
    }
    return $out
}

function Format-GlobNote {
    <#
      What the reach ledger prints after a glob. Silent for the ordinary case -
      a glob reaching files, undeclared - so the three states that are worth a
      reader's attention are the three that say anything.
    #>
    param($Spec)
    if ($Spec.MayBeEmpty -and $Spec.Reach -eq 0) {
        return "   DECLARED MAY BE EMPTY - $($Spec.MayBeEmpty)"
    }
    if ($Spec.MayBeEmpty) {
        return "   declared may_be_empty and reaching files, so the declaration is no longer load-bearing - $($Spec.MayBeEmpty)"
    }
    if ($Spec.Reach -eq 0) { return '   NOT REACHED - see below' }
    return ''
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
#
# SEEDED FROM $Rules HERE RATHER THAN CREATED INSIDE THE FILE LOOP, and that is
# the difference between a check and a check that can be skipped. Populated
# lazily, a scoped rule was absent from this map entirely on a run that read no
# files at all - so the assertion below would have iterated an empty set and
# found nothing to complain about in precisely the state where the rule most
# certainly asked nothing. The zero has to exist before the loop that fails to
# increment it.
$scopedFiles = @{}
foreach ($r in $Rules) { if ($r.ContainsKey('scope')) { $scopedFiles[$r.id] = 0 } }
# How many scanned files each allowlist entry's `files` globs REACH - a
# different number from how many matches it excused, and the only one that can
# tell a defensive entry apart from an entry pointing at paths that are not in
# the tree. Entries scoped to '*' are absent on purpose: their reach is every
# file by construction, so the number would be noise. PRINTED, NEVER ASSERTED;
# the header carries the argument for the asymmetry with a rule's scope.
$allowReach = @{}
foreach ($a in $AllowList) { if ($a.files -notcontains '*') { $allowReach[$a.id] = 0 } }
# EVERY GLOB, one row, from both tables - the half neither counter above can
# supply. $scopedFiles collapses a rule's whole list to one number and
# $allowReach does the same for an entry's, so eight dead globs beside one live
# one read as a healthy rule in both. Seeded here from the tables for the same
# reason $scopedFiles is: a row populated lazily is absent from the assertion on
# exactly the run that read no files, which is when it matters most.
#
# The seeding also NORMALISES the two tables in place, replacing `scope` and
# `files` with plain string arrays. Every reader below - Test-InScope,
# Test-Allowed, the per-file reach loop - then sees the spelling it was written
# against, and the hashtable form is understood in one place rather than in
# four.
$globSpecs = @()
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
    # THE ARITY FLOOR, and it is here because the nesting bug Get-GlobSpecs
    # documents produced ONE spec for nine globs and nothing noticed: the
    # ledger printed a plausible line and the assertion read a declaration that
    # was not there. One spec per glob is the only property that makes the
    # per-glob assertion per-glob, so it is checked rather than assumed.
    foreach ($r in $Rules) {
        if (-not $r.ContainsKey('scope')) { continue }
        $specs = @(Get-GlobSpecs $r.scope)
        if ($specs.Count -ne @($r.scope).Count) {
            throw "rule $($r.id) declares $(@($r.scope).Count) scope glob(s) and normalised to $($specs.Count) - the per-glob check would be reading something other than the globs"
        }
        foreach ($s in $specs) {
            $globSpecs += [pscustomobject]@{
                Owner = 'rule'; Id = $r.id; Glob = $s.Glob; MayBeEmpty = $s.MayBeEmpty; Reach = 0
            }
        }
        $r.scope = @($specs | ForEach-Object { $_.Glob })
    }
    foreach ($a in $AllowList) {
        $specs = @(Get-GlobSpecs $a.files)
        if ($specs.Count -ne @($a.files).Count) {
            throw "allowlist entry $($a.id) declares $(@($a.files).Count) files glob(s) and normalised to $($specs.Count) - the per-glob check would be reading something other than the globs"
        }
        foreach ($s in $specs) {
            $globSpecs += [pscustomobject]@{
                Owner = 'allowlist'; Id = $a.id; Glob = $s.Glob; MayBeEmpty = $s.MayBeEmpty; Reach = 0
            }
        }
        $a.files = @($specs | ForEach-Object { $_.Glob })
    }

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
            if (Test-InScope -Rule $r -RelPath $rel) { $scopedFiles[$r.id]++ }
        }

        # Counted over the SAME set the scope count is counted over - files that
        # were actually read - so the two numbers in the ledger are comparable.
        # A file that could not be read is not in reach of anything, and saying
        # otherwise would let an entry look live because of a path the scan
        # never opened.
        foreach ($a in $AllowList) {
            if (-not $allowReach.ContainsKey($a.id)) { continue }
            foreach ($g in $a.files) { if ($rel -like $g) { $allowReach[$a.id]++; break } }
        }

        # Per glob, over the same set again, and WITHOUT the `break` the two
        # loops above use: those ask "did this rule/entry reach this file?" and
        # stop at the first yes, which is the question that collapses nine globs
        # into one number. This one asks it of each glob separately, so a file
        # two globs both match is counted for both.
        foreach ($gs in $globSpecs) { if ($rel -like $gs.Glob) { $gs.Reach++ } }

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
#
# AND THE COUNT ALONE CANNOT ANSWER THE QUESTION IT LOOKS LIKE IT ANSWERS. A
# zero beside an entry has two causes that read identically: the entry was
# offered matches and excused none of them, or its `files` globs reach no
# scanned file at all and it could not have been offered anything. The first is
# a defensive entry doing exactly what it is for; the second is an entry aimed
# at paths that are not in this tree - which is what a directory rename does to
# three of the entries above in one commit. The reach is printed beside the
# count for entries that name paths, and since 4 September 2026 it is ASSERTED
# as well, glob by glob - see the header for the reversal and for what
# `may_be_empty` buys.
#
# THE PER-GLOB LINES ARE THE ONES TO READ. An entry's total reach is the same
# kind of number as a rule's scope count, and it hides the same thing: five
# globs of which one is live reads as an entry comfortably in reach.
"ALLOWLIST - every entry, how many matches it excused on this tree ($($allowedHits.Count) total),"
"           and - for entries that name paths - how many of the $scanned scanned file(s) it reaches:"
foreach ($a in $AllowList) {
    $n = $allowCount[$a.id]
    $reach = $(if ($allowReach.ContainsKey($a.id)) { $allowReach[$a.id] } else { $null })
    $note = $(if ($n -gt 0) {
        $a.why
    } elseif ($null -ne $reach -and $reach -eq 0) {
        'CANNOT FIRE - its files globs reach none of the scanned files, so the paths it names are not in this tree. Each dead glob is named in a NOT REACHED line below and this run exits 2: fix the globs, delete the entry with its subject, or declare may_be_empty with the reason the path is not there.'
    } elseif ($null -ne $reach) {
        "(unused on this tree - defensive; in reach of $reach scanned file(s), so it was offered nothing rather than unreachable)"
    } else {
        '(unused on this tree - defensive; in reach of every scanned file)'
    })
    "  {0,4}  {1,-28}  {2}" -f $n, $a.id, $note
    if ($null -ne $reach) {
        foreach ($gs in ($globSpecs | Where-Object { $_.Owner -eq 'allowlist' -and $_.Id -eq $a.id })) {
            "        {0,4}  {1}{2}" -f $gs.Reach, $gs.Glob, (Format-GlobNote $gs)
        }
    }
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

# ---- what was NOT ASKED ---------------------------------------------------
# The other way this scan can check less than it says it did, and the one it
# could not see. Everything above is a FILE that was not read; this is a RULE
# that was not put. Both leave the report describing work that did not happen,
# so both are named here, in the block a reader is sent to, and both reach the
# same exit code.
$emptyScope = @($scopedFiles.Keys | Where-Object { $scopedFiles[$_] -eq 0 } | Sort-Object)
foreach ($k in $emptyScope) {
    "  NOT ASKED  rule $k - its scope matched none of the $scanned scanned file(s), so it asked nothing of anything and cannot have found anything. Scope globs are matched against what ``git ls-files`` prints, which is repo-root-relative, so one directory rename breaks every glob of a rule at once. Fix the globs; deleting the rule is also an answer, but it has to be one somebody makes."
}

# One level down from NOT ASKED, and the level the incident actually happened
# at. The line above fires when EVERY glob of a rule died; these fire per glob,
# so eight dead ones beside a live ninth are eight lines rather than silence.
# Ordered as the tables declare them, because that is the order a reader will
# open the file at.
$deadGlobs = @($globSpecs | Where-Object { $_.Reach -eq 0 -and -not $_.MayBeEmpty })
foreach ($g in $deadGlobs) {
    $owner = $(if ($g.Owner -eq 'rule') { "rule $($g.Id)'s scope" } else { "allowlist entry $($g.Id)'s files" })
    "  NOT REACHED  $owner declares the glob [$($g.Glob)], which matched none of the $scanned scanned file(s). It is matched against what ``git ls-files`` prints, so a moved or deleted subject kills it while its siblings go on matching and the rule or entry goes on looking healthy. Three answers, and all three are somebody's decision: fix the glob, delete it with the subject it named, or write it as @{ glob = '...'; may_be_empty = '<why>' } if it is meant to name something that is not there yet."
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
# whole file exists to refuse - and it now exits 2, named in the NOT ASKED line
# above. THE COUNT IS STILL PRINTED EVERY RUN, NOT ONLY WHEN IT IS ZERO, and
# that is not redundancy with the assertion: the assertion fails at zero, which
# catches a scope switched off entirely, and says nothing about a scope that
# quietly NARROWED. Nine globs down to one after a rename is a rule still
# "applied" and barely asking. A reader comparing two runs sees the corpus
# shrink; a reader of an exit code does not.
foreach ($k in ($scopedFiles.Keys | Sort-Object)) {
    $n = $scopedFiles[$k]
    "  rule $k is SCOPED and was applied to $n of $scanned file(s)" +
        $(if ($n -eq 0) { ' - ZERO, so it asked nothing of anything and cannot have found anything' } else { '' })
    # And what each of its globs reached on its own, which is the number the
    # line above averages away. 33 of 96 was 1 of 94 the day the payload moved,
    # and both read as a rule that is asking.
    foreach ($gs in ($globSpecs | Where-Object { $_.Owner -eq 'rule' -and $_.Id -eq $k })) {
        "      {0,4}  {1}{2}" -f $gs.Reach, $gs.Glob, (Format-GlobNote $gs)
    }
}
"RESULT: $($violations.Count) violation(s), $($allowedHits.Count) allowlisted"

# ORDER: 2 BEFORE 1, AND THAT IS THE DELIBERATE PART. Exit 1 means "the tree was
# checked and is dirty" and its own text tells the reader to fix a file. A run
# that could not read every tracked file, OR that never put one of its rules,
# has not established the first half, so it must not claim it - the violations
# it DID find are printed above either way, and this block says so rather than
# letting the exit code swallow them.
#
# A ZERO SCOPE IS EXIT 2 AND NOT EXIT 1, and the reason is the one the header
# gives for the two channels already here. Exit 1's own text sends a reader to
# "fix the file", which is unactionable advice about a rule that never ran and
# a file that may be perfectly clean; and a run whose rule asked nothing has not
# checked the tree, so it cannot report "checked, and dirty" any more than a run
# that could not read a file can. Conflating "dirty" with "not asked" is the
# same collapse this table was built to prevent.
if ($notScanned.Count -gt 0 -or $emptyScope.Count -gt 0 -or $deadGlobs.Count -gt 0) {
    $why2 = @()
    if ($notScanned.Count -gt 0) { $why2 += "$($notScanned.Count) tracked file(s) were not fully read" }
    if ($emptyScope.Count -gt 0) { $why2 += "$($emptyScope.Count) scoped rule(s) were applied to no file at all" }
    if ($deadGlobs.Count -gt 0)  { $why2 += "$($deadGlobs.Count) glob(s) reached no scanned file and did not declare may_be_empty" }
    "EXIT: 2 ($($why2 -join ', and '), so this run cannot say"
    '         every tracked file is clean. Each is named above with the reason.'
    if ($notScanned.Count -gt 0) {
        '         A UTF-16 file - which is what Windows PowerShell > and Out-File write by'
        '         default, Set-Content writes ASCII - lands here: re-save it as UTF-8. A real'
        '         binary belongs in $BinaryAllowList with a reason. An unclosed'
        '         LWG-SCAN-REGION marker is a bug in the file.'
    }
    if ($emptyScope.Count -gt 0) {
        "         The rule(s) that asked nothing: $($emptyScope -join ', '). A scope is path globs"
        '         matched against `git ls-files` output, so a directory rename switches the rule'
        '         off wholesale. Fix the globs and re-run; do not delete the rule to clear this.'
    }
    if ($deadGlobs.Count -gt 0) {
        "         The glob(s) that reached nothing: $(($deadGlobs | ForEach-Object { $_.Id + ' [' + $_.Glob + ']' }) -join ', ')."
        '         A rename breaks the globs that moved and leaves the ones that did not, so the'
        '         rule or entry goes on looking healthy while its corpus collapses. Fix the glob,'
        '         delete it with the subject it named, or declare may_be_empty with the reason.'
    }
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
# THE SENTENCE THAT DEFINES A GREEN RUN, AND IT NOW CARRIES ALL THREE HALVES.
# It used to assert only that every file was READ, while the rules deciding
# what reading meant could have been switched off underneath it; then that
# every scoped rule was asked of something, which a rule asking one file of
# ninety-four satisfies. A guard whose pass line claims more than the run
# established is the shape this repository is named for, so the claim is made
# no larger than the three things above it - and no smaller: "every glob"
# includes the declared-empty ones, which are excluded from the assertion and
# named in the ledger with their reason, so a reader is not told they were
# checked.
'EXIT: 0 (every tracked file was read, every scoped rule was asked of at least one of'
'         them, every glob in a scope or an allowlist entry reached at least one file'
'         or declared why it reaches none, and none carries a local environment'
'         dependency)'
exit 0
