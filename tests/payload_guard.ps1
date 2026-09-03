#requires -version 5
<#
  LW-WATCHTOWER payload disclosure guard.

      powershell -NoProfile -ExecutionPolicy Bypass -File tests\payload_guard.ps1

  WHY THIS FILE EXISTS

  `.claude-plugin/marketplace.json` declares `"source": "./"`. There is no
  exclusion mechanism on that form, so EVERY TRACKED FILE IN THIS REPOSITORY IS
  THE SHIPPED PAYLOAD. A consumer who installs this plugin receives the whole
  root, and the `checklist` command rendered one of those files on their
  machine - `commands/checklist.md` instructed the model to print the output
  verbatim, so whatever the manifest carried reached a stranger's screen. That
  command went in 0.4.0; the files it rendered still ship, so these rules stay.

  Four disclosures reached the payload that way and none of them was caught by
  anything, because every guard in tests\ answers a different question:

    * tests\portability_scan.ps1 asks whether a tracked file names one MACHINE.
      A pull ref, a commit SHA and a release-plan heading are portable. They
      pass it.
    * tests\doc_claims.ps1 derives COUNTED QUANTITIES and holds prose to them.
      A containment claim resting on the repository not being published yet
      carries no number, so it is not a claim that file can read at all.
    * tests\evidence_states.ps1 asks whether the evidence engine tells a probe
      that could not run from a probe that found nothing. It reads rules, not
      prose, and it is indifferent to what a caveat says.

  So the disclosures were found by audit. An audit is a person remembering to
  look, and the three that found these had to be told where. This file is the
  same check run by a machine, over the same file list the marketplace copies.

  WHAT IT REFUSES, and why each one is a disclosure rather than a wart:

    1. THE PULL-REF NARRATIVE. One ref on this remote is owned by GitHub rather
       than by this repository, and no force-push can reach it; its ancestry
       still carries the pre-rewrite commits and the owner's former personal
       address. Naming that ref, its tip commit, the commit count and - worst -
       the fetch invocation that retrieves it turns a bounded exposure into a
       signposted one. A reader who did not know to look is handed both the
       location and the method.

       THIS PARAGRAPH DESCRIBES THE REF AND DOES NOT SPELL IT, and that is not
       squeamishness. This file is tracked, so it is payload; the rules below
       are exempted from the sweep by a region marker, but prose is not, and a
       guard whose header trips its own rules is a guard that goes red on the
       day it is added. The same fix was made once already in this repository -
       an illustration was moved to letters that spell nothing rather than
       having the exemption widened around it - and widening the region here
       would have hidden the header from every future rule as well as this one.
    2. THE FORMER PERSONAL ADDRESS. Held here rot13-encoded and decoded at match
       time, the same mechanism `bin\lwg-evidence.ps1` uses and for the same
       reason: a guard that spells the string it forbids IS the disclosure. See
       THE ENCODED NEEDLE below.
    3. THE PLAN PATH. A path into the per-user plans directory that ends in a
       plan file's own NAME points at an untracked personal file on one laptop.
       The generic elided form - the same directory with no file name - is a
       legitimate reference to a location and is deliberately NOT matched; the
       file name is the disclosure, and it is the only part of it that is.
    4. THE RELEASE-PLAN HEADINGS. The go-public phase heading of the MAINTAINER'S
       release plan, rendered on a consumer's machine by a command that presents
       every row as a finding, reads as a phase of THEIR work rather than of a
       project they have never heard of.
    6. A DELETED SCRIPT, NAMED AS LIVE BY A SHIPPED FILE. Not a privacy
       disclosure like the five below it, and it is here rather than in a suite
       of its own for the reason this file exists at all: it is a property of
       what a STRANGER RECEIVES, and every other guard in tests\ answers a
       different question. A consumer's model reads a shipped page or a
       maintainer reads a shipped comment, follows it to a script that is not
       in the payload, and the failure is silent in both directions - the
       invocation fails, or the reader reasons from a mechanism that does not
       exist. Wave 1 deleted the state resolver, its library half, its command
       and the marker the clearing mechanism turned on, and eleven tracked
       sites went on naming them. See DETECTION RULES and, immediately after
       them, HISTORICAL MENTIONS - naming a deleted thing AND SAYING IT IS
       DELETED is the opposite of this defect, and the two are told apart one
       line at a time rather than one file at a time.
    5. VISIBILITY-CONDITIONED CONTAINMENT. A sentence asserting that the exposure
       reaches no further than whoever can already read the repository, resting
       on the repository not yet being published, is true today and becomes a
       FALSE SAFETY CLAIM about an unresolved PII exposure the instant visibility
       flips - inside a file that is by then public. This is the one rule here
       that guards against a sentence which is CORRECT NOW. That is the point:
       the flip is a single event that inverts it, and a claim whose truth
       depends on an event nobody will re-read the file after is a claim that
       should not be written down. The rules below carry the literal shapes;
       this paragraph paraphrases them, for the reason given in item 1.

  HOW IT WORKS

  Every file `git ls-files` reports is read and matched against the DETECTION
  RULES table. The file list is NEVER hardcoded - a hardcoded list is the defect
  this guard exists to prevent, and it is exactly how the payload boundary was
  lost in the first place: `"source": "./"` is a wildcard nobody enumerated.

  A hit is then offered to the BARRED LEDGER. An entry there does not mean the
  site is acceptable; it means the file is outside this pass's ownership and the
  named issue owns it. Ledger'd hits are PRINTED, with their issue number, above
  the result - never folded silently into a pass.

  SELF-EXEMPTION. This file must contain the very strings it forbids. It is not
  skipped wholesale: the exempt lines are bracketed by a region marker, and only
  the path in $RegionOwners may declare one, so a marker appearing in any other
  tracked file is itself reported as a violation and the mechanism cannot become
  an escape hatch. The same discipline as tests\portability_scan.ps1, and for
  the same reason - this repository has already shipped a prose example that
  matched the sweep hunting for the thing it described.

  WHAT IS NOT SCANNED IS NOT CLEAN. A tracked path with nothing on disk, or a
  file whose first 8 KB holds a NUL byte, is NAMED and exits 2. A run that did
  not read everything cannot report "checked, and clean"; zero files enumerated
  is an abort and never a pass.

  EXIT CODES - a CI job reads these and nothing else.

      0  every tracked file was read, and no unledger'd disclosure was found
      1  at least one disclosure is in the payload at a site no ledger entry
         covers - the payload discloses, and the site is named
      2  the scan ABORTED, or could not read every tracked file, or an owner
         file left a region open. The tree was NOT fully checked, which is not
         the same as passing, and 2 takes precedence over 1.
#>

[CmdletBinding()]
param(
    # Repo root. Defaults to this file's parent, correct for a run from
    # anywhere as long as this file stays in tests\.
    [string]$Root
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }

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

# ===========================================================================
# THE ENCODED NEEDLE
#
# The owner's former personal address local-part, rot13-encoded, decoded in
# memory at match time and never written to output. Byte-identical in form to
# checklist.json's `stdout_not_match`, and decoded by the same transformation
# bin\lwg-evidence.ps1's Expand-LwgRptLiteral applies.
#
# WHY A GUARD MAY NOT SPELL ITS OWN TARGET. The requirement this repository
# holds is that NO TRACKED FILE spells the string in reading order - because a
# tracked file is a shipped file, and a `git filter-repo --replace-text` pass
# matches a literal in reading order and walks past anything else. A guard that
# hardcoded the plain local-part would satisfy its own assertion by containing
# a counter-example to it, and would put the string back into the payload it is
# meant to keep clean. Rot13 is a transposition and not secrecy - anyone can
# undo it in one line - and that is the right strength: the requirement is
# reading order, not concealment.
# ===========================================================================
function Expand-LwgRot13 {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    if (-not $Text.StartsWith('rot13:', [StringComparison]::Ordinal)) { return $Text }
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $Text.Substring(6).ToCharArray()) {
        $c = [int][char]$ch
        if     ($c -ge 65 -and $c -le 90)  { [void]$sb.Append([char](65 + (($c - 65 + 13) % 26))) }
        elseif ($c -ge 97 -and $c -le 122) { [void]$sb.Append([char](97 + (($c - 97 + 13) % 26))) }
        else                               { [void]$sb.Append($ch) }
    }
    return $sb.ToString()
}

$AddressPattern = Expand-LwgRot13 -Text 'rot13:(?v)ovm_grpu_rkrp'

# The one file permitted to declare an exempt region, and why it has to.
# Anything else carrying a region marker is a violation, not an exemption.
$RegionOwners = @(
    @{ path = 'tests/payload_guard.ps1'
       why  = 'holds the detection patterns themselves; every rule would match its own definition' }
)

# Matches `# LWG-PAYLOAD-REGION: begin` in PowerShell and the HTML-comment form
# in markdown. Anchored to the start of a comment so this line, which holds the
# same words mid-expression, cannot match itself.
$RegionMarker = '^\s*(?:#|<!--)\s*LWG-PAYLOAD-REGION:\s*(begin|end)\b'

# LWG-PAYLOAD-REGION: begin
# ===========================================================================
# DETECTION RULES
#
#   id      short name used in the report and in ledger scoping
#   name    what the rule looks for, printed beside every hit
#   why     what is disclosed to a consumer when this ships
#   pattern the regex
#   scope   OPTIONAL path globs. Omit it and the rule runs on every tracked
#           file, which is the default and right for every disclosure rule -
#           a personal address is a disclosure wherever it sits. A rule is
#           scoped only when what it forbids is a property of a file's ROLE
#           rather than of its text, and S7 below asserts that a scoped rule
#           actually reached a file, because a scope that matches nothing is a
#           rule switched off with nobody told.
#
# PRECISION NOTES, each one measured against this tree rather than assumed:
#
#   * `76` alone is not a rule. It hits statusline\statusline.ps1's rounding
#     comment and a percentage in tests\stop_behaviour.ps1, neither of which
#     discloses anything. The rule keys on `76 pre-rewrite commits`.
#   * `USERPROFILE` alone is not a rule. Roughly twenty tracked sites use
#     `$env:USERPROFILE` correctly and portably, which is the DOCUMENTED right
#     way to write a profile path. The rule requires the plans directory AND a
#     file name, so the elided form that names the location without naming the
#     file is not matched.
#   * The CHOSEN address is not forbidden and is not matched. It is a real,
#     reachable address published on purpose; only the former personal
#     local-part is a disclosure.
#   * The containment rule keys on the CONTAINMENT VERB near the visibility
#     word, not on the visibility word alone. "This was filed in a private
#     repository until 3 August 2026" is a past-tense record and discloses
#     nothing; "readable only by people who can already read the repository"
#     is a safety claim with a fuse in it.
# ===========================================================================
$Rules = @(
    @{
        id      = 'pull-ref'
        name    = 'the pull ref that serves the pre-rewrite history'
        why     = 'names the exact location of an unresolved identity exposure. A reader who did not know to look now knows where to look.'
        pattern = 'refs/pull/\d+/head'
    }
    @{
        id      = 'pull-ref-fetch'
        name    = 'the command that retrieves the pre-rewrite history'
        why     = 'the method, beside the location. This is what turns a bounded exposure into a signposted one - it is a working recipe.'
        pattern = '(?i)git\s+fetch\s+\S+\s+refs/pull'
    }
    @{
        id      = 'pull-ref-tip'
        name    = 'the tip SHA of the pull ref'
        why     = 'the commit a reader fetches to land the pre-rewrite history in a ref their tooling will read.'
        pattern = '(?i)\bdb74ec2\w*'
    }
    @{
        id      = 'pre-rewrite-count'
        name    = 'the count of commits carrying the former personal address'
        why     = 'quantifies the exposure and confirms to a reader that the fetch is worth making.'
        pattern = '(?i)\b76\s+pre-rewrite\s+commits\b'
    }
    @{
        id      = 'personal-address'
        name    = 'the local-part of the owner''s former personal address'
        why     = 'a pre-publication audit measured this as appearing in NO public repository, so publishing it is a FIRST disclosure rather than a re-exposure.'
        pattern = $AddressPattern
    }
    @{
        id      = 'plan-path'
        name    = 'the maintainer''s personal plan file, by name'
        why     = 'an untracked file under one user profile on one laptop. It ships with nothing, so naming it tells a consumer only that it exists and what it is called.'
        # THE SEPARATOR RUN IS `+` AND NOT `{1,2}`, AND A MUTATION TEST IS WHY.
        # This file is matched as RAW TEXT, line by line, so a path inside a JSON
        # string arrives with its backslashes still escaped - one separator in the
        # decoded value is two on the line. `{1,2}` covered that and nothing more,
        # so the same path written with one extra level of escaping walked straight
        # past the rule while every other rule caught its own re-introduction. The
        # count of backslashes is not the property being guarded; the plans
        # directory followed by a file name is.
        pattern = '(?i)\.claude[\\/]+plans[\\/]+[A-Za-z0-9][A-Za-z0-9_.\-]*\.md'
    }
    @{
        id      = 'release-plan-heading'
        name    = 'a maintainer release-plan section heading'
        why     = 'rendered on a consumer machine, a phase of the maintainer''s go-public plan reads as a phase of the consumer''s own work. The `checklist` command that rendered it went in 0.4.0; the file still ships, so the rule stays.'
        pattern = '(?i)Phase\s+8\s*[-–]\s*Go\s+public'
    }
    @{
        id      = 'visibility-containment'
        name    = 'a containment claim conditioned on the repository being private'
        why     = 'TRUE TODAY, FALSE AT THE FLIP - and false inside a file that is public by then. It is the sentence a reader relies on to decide an unresolved PII exposure is contained.'
        pattern = '(?i)\bprivate\b[^.!?]{0,160}?\b(?:bounded by|readable only by|only readable by|only be read by|contained by)\b' +
                  '|(?i)\b(?:bounded by|readable only by|only readable by|only be read by|contained by)\b[^.!?]{0,160}?\bprivate\b'
    }
    @{
        id      = 'visibility-conditioned'
        name    = 'a present-tense claim that inverts when visibility flips'
        why     = 'each of these is true only while the repository is private. They invert simultaneously on one event, and nothing else in this tree reads a statement that carries no number.'
        pattern = '(?i)\b(?:this |the )?repositor(?:y|ies)\s+is\s+(?:still\s+)?private\b' +
                  '|(?i)\bwhile\s+the\s+repo(?:sitory)?\s+is\s+private\b' +
                  '|(?i)\b403\s+for\s+a\s+private\s+repo\b' +
                  '|(?i)\bnot\s+configurable\s+while\s+the\s+repo(?:sitory)?\s+is\s+private\b'
    }
    @{
        id      = 'deleted-script'
        name    = 'shipped file naming a script this branch deleted'
        why     = 'a shipped file naming a script that is not in the payload sends whoever reads it - a model following an instruction, or a maintainer following a comment - to something that is not there. The failure is silent: the invocation fails, or the reader concludes the mechanism exists and reasons from it. THE FOUR NAMES ARE #192''s DONE-CONDITION, not a general sweep for every removed file: the resolver, its library half, its command, and the marker the whole clearing mechanism turned on. All four went in wave 1 with the decision that state comes from the ledger rather than from a hand-cleared fault count.'
        # WHAT THIS RULE CANNOT DO, and it is the same limit every rule here
        # has: it reads text, so it cannot tell an instruction from a memoir.
        # THE HISTORICAL MENTIONS TABLE below is what draws that line, and it
        # draws it one LINE at a time rather than one file at a time - a file
        # is allowed to keep the sentence that records a removal without being
        # allowed to keep a live instruction three hundred lines later.
        # THE COMMAND ALTERNATIVE IS SPLIT ACROSS A CONCATENATION, and it is
        # not a stylistic tic. bin\lwg-doctor.ps1's `commands` check scans every
        # tracked .ps1 and .md for `/<plugin>:<name>` and FAILS when the command
        # page is not in commands\ - which is how the six deleted commands were
        # found. Writing this rule's needle out in reading order made a guard
        # naming a deleted command indistinguishable, to that check, from a page
        # inviting an operator to run one, and it turned the doctor red the day
        # this rule was added. The same lesson this file's header records about
        # the pull ref: a guard may not spell its own target. The split breaks
        # the doctor's literal without weakening this pattern, which is compiled
        # from the joined string.
        pattern = '(?i)lwg-resolve' +
                  '|(?i)\blib[\\/]resolve\.ps1' +
                  '|(?i)/lw-watchtower' + ':resolve\b' +
                  '|(?i)\bResolved\W{0,3}marker\b'
        # SCOPED TO THE SHIPPED EXECUTABLE PAYLOAD, MINUS commands/ AND agents/,
        # AND THE OMISSION IS TEMPORARY AND LOUD. #192's done-condition says
        # "no SHIPPED file", and the whole root ships - but commands/update.md
        # still names the deleted library, and a fixer may not edit a document.
        # That page is wave D's (#195). Including commands/ here would make this
        # branch's CI permanently red on a file nobody in this wave is allowed
        # to touch, which is a guard that has to be switched off to be merged,
        # which is not a guard. RE-ENABLE commands/ AND agents/ THE MOMENT #195
        # LANDS: they are text a model reads, which is the surface #192 was
        # filed about in the first place. tests/ is out for a different reason -
        # it ships under `"source": "./"` like everything else, but its three
        # remaining sites are assertion prose in a file this pass does not own,
        # and they are recorded on #192 rather than ledger'd here.
        scope   = @('bin/*', 'lib/*', 'hooks/*', 'statusline/*', 'context/*',
                    'config.json', '.claude-plugin/*')
    }
)
# LWG-PAYLOAD-REGION: end

# ===========================================================================
# HISTORICAL MENTIONS
#
#   files  repo-relative path, matched exactly
#   rules  rule ids this entry covers in that file
#   test   a regex matched against the LINE. It identifies ONE line.
#   why    why naming the deleted thing on that line is honest
#
# THE DISTINCTION THIS TABLE EXISTS TO DRAW. `deleted-script` above forbids
# naming a deleted script AS LIVE. It does not forbid recording that the thing
# existed and was removed - that record is the opposite of the defect, and
# #198 established the form for it in CHANGELOG.md: name what went, and say it
# went. A guard that could not tell the two apart would push every honest
# tombstone out of the tree and leave the next reader wondering why a branch
# in statusline/statusline.ps1 reads a field nothing writes.
#
# WHY THE TEST IS A LINE PATTERN AND NOT A LINE NUMBER. A number goes stale on
# the next edit above it and then silently excuses whatever moved into its
# place - a line-numbered allowlist is a vacuous one waiting for a reflow.
#
# WHY THE TEST PATTERNS DO NOT SPELL THE FORBIDDEN NAMES. Same discipline as
# the ledger below and as THE ENCODED NEEDLE: this table sits OUTSIDE the
# exempt region, so a test that quoted the string it excuses would put that
# string back into the payload and would be a counter-example to its own rule.
# Each entry keys on a distinctive phrase from its line instead. That is also
# why they are narrow: a phrase from one sentence cannot excuse a live
# instruction written somewhere else in the same file.
#
# AN ENTRY THAT MATCHES NOTHING IS PRINTED, NOT FAILED. Zero means the file was
# fixed or reflowed, and going red on a fix punishes the person who made it -
# the same reasoning the ledger states below. It is printed so a table that has
# rotted into decoration is visible rather than assumed.
# ===========================================================================
$HistoricalMentions = @(
    @{ files = 'lib/common.ps1'
       rules = @('deleted-script')
       test  = 'how the healer wrote a'
       why   = 'past tense, recounting the founding defect: a healer wrote a clearing record into the wrong file while the log it was meant to clear stayed empty. The sentence is the reason the surrounding code exists and cannot be told without naming what did it.' }
    @{ files = 'statusline/statusline.ps1'
       rules = @('deleted-script')
       test  = '^\s*#\s*writers of that record were'
       why   = 'the tombstone on the arm that used to zero the health counters. It names the two writers AND says both are deleted, in the same sentence, which is the form #198 settled on. Without it the missing arm reads as an oversight rather than as a decision, and the next reader re-adds it.' }
    @{ files = 'statusline/statusline.ps1'
       rules = @('deleted-script')
       test  = 'to name the tasks\..{0,40}:136 read'
       why   = 'the record of why three readers of one log disagreed about one number. The sentence that follows it states outright that two of the three are deleted and that this file is the last of them, so the mention is dated on the spot rather than left to be checked.' }
)

# ===========================================================================
# THE BARRED LEDGER
#
#   files  repo-relative path, matched exactly
#   rules  rule ids this entry excuses in that file, or '*' for all
#   issue  the issue that OWNS the site
#   why    why this pass did not fix it
#
# AN ENTRY HERE IS NOT AN ACCEPTANCE. It records that the disclosure is real,
# is still in the payload, and is owned elsewhere. Every ledger'd hit is
# printed with its issue number above the result, because the alternative -
# a silent exclusion - is how a guard becomes a green log over a dirty tree.
#
# WHAT THIS LEDGER DELIBERATELY DOES NOT DO: it does not assert that the sites
# it names still exist. An entry that went red when somebody FIXED the file it
# points at would punish the fix and would have to be edited by whoever made
# it, which is the wrong incentive on the wrong person.
# ===========================================================================
$BarredLedger = @(
    @{ files = 'CHANGELOG.md'
       rules = @('pull-ref', 'pull-ref-tip', 'pre-rewrite-count', 'visibility-conditioned')
       issue = '#118 / #121'
       why   = 'CHANGELOG.md is a historical record and is outside this pass''s ownership. It carries the same pull-ref narrative and ships under the same "source": "./" - the payload-boundary decision that covers it is #47''s, taken once when the published tree is built.' }
    @{ files = 'README.md'
       rules = @('visibility-conditioned')
       issue = '#124'
       why   = 'the no-CI-badge justification. Outside this pass''s ownership, and its verbatim twin in docs/testing.md is too - fixing one half alone would leave two identical sentences disagreeing, which is the drift shape tests/doc_claims.ps1 exists to catch, introduced by hand.' }
    @{ files = 'docs/testing.md'
       rules = @('visibility-conditioned')
       issue = '#124'
       why   = 'verbatim twin of README.md''s badge sentence. Outside this pass''s ownership.' }
    @{ files = 'docs/limitations.md'
       rules = @('visibility-conditioned')
       issue = '#124'
       why   = 'the branch-protection 403 the page describes stops being returned at the flip. Outside this pass''s ownership. Phrased without the trigger words on purpose - this table is prose in a tracked file, so a ledger entry quoting the sentence it excuses would itself be a hit.' }
    @{ files = 'lib/common.ps1'
       rules = @('deleted-script')
       issue = '#192 (lane C4)'
       why   = 'TWO SITES, BOTH LIVE, BOTH IN SHIPPED CODE AND NEITHER HONEST. One says the deleted library is run by an agent, in the present tense and with a "verified" that makes it read as checked-and-current; the other gives the deleted resolver''s console report as the STATED REASON the redaction helper escapes control characters, so live behaviour is justified by a file that is not in the payload. They are real, they are still shipping, and this entry is not an acceptance of them - lib/common.ps1 belongs to another lane in this same wave and its pull request was open when this guard landed. TEMPORARY: DELETE THIS ENTRY when that lane merges, and this rule goes red until the two lines are rewritten. A third site in the same file - the founding-defect sentence - is honestly historical and is covered by the HISTORICAL MENTIONS table above, so removing this entry does not take that one with it.' }
    @{ files = '.gitignore'
       rules = @('visibility-conditioned')
       issue = '#124'
       why   = 'A SEVENTH SITE, NAMED BY NO ISSUE: the comment above the workflow entries says those settings are not even settable before the flip. Found by this sweep rather than by the six-site enumeration #124 was filed with, which is the strongest argument for having a sweep at all. Outside this pass''s ownership; recorded here so it reaches whoever runs the flip runbook. The wording is paraphrased rather than quoted, for the reason in the docs/limitations.md entry above.' }
)

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$missing    = New-Object System.Collections.ArrayList
$binary     = New-Object System.Collections.ArrayList
$openRegion = New-Object System.Collections.ArrayList
$strayMark  = New-Object System.Collections.ArrayList
$hits       = New-Object System.Collections.ArrayList
$ledgered   = New-Object System.Collections.ArrayList
$historical = New-Object System.Collections.ArrayList
# Per-entry match counts for the historical table, and per-rule file counts for
# any rule carrying a scope. Both are derived every run, and both are printed:
# an entry excusing nothing and a scope reaching nothing are the two ways this
# mechanism can rot into decoration, and neither is visible unless counted.
$histCount  = @{}
foreach ($h in $HistoricalMentions) { $histCount[$h.test] = 0 }
$scopedFiles = @{}
$fileCount  = 0

Write-Output '==========================================================================='
Write-Output 'LW-WATCHTOWER payload disclosure guard'
Write-Output "  root    : $Root"

function Test-Ledgered {
    param([string]$Rel, [string]$RuleId)
    foreach ($e in $BarredLedger) {
        if ($e.files -ne $Rel) { continue }
        if ($e.rules -contains '*' -or $e.rules -contains $RuleId) { return $e }
    }
    return $null
}

function Test-Historical {
    <#
      The historical-mention entry covering this exact line, or $null. Checked
      BEFORE the ledger, so a file that is ledger'd for a live site still has
      its honest tombstones classified as tombstones - which is what lets the
      ledger entry be deleted later without taking them with it.
    #>
    param([string]$Rel, [string]$RuleId, [string]$Line)
    foreach ($e in $HistoricalMentions) {
        if ($e.files -ne $Rel) { continue }
        if ($e.rules -notcontains $RuleId) { continue }
        if ($Line -match $e.test) { return $e }
    }
    return $null
}

function Test-RuleInScope {
    <#
      Whether a rule is asked of this file at all. No `scope` key means every
      file, which is what every disclosure rule uses. This decides whether the
      QUESTION is put; the ledger and the historical table decide whether an
      ANSWER is excused, and the three are reported separately on purpose.
    #>
    param($Rule, [string]$Rel)
    if (-not $Rule.ContainsKey('scope')) { return $true }
    foreach ($g in $Rule.scope) { if ($g -eq '*' -or $Rel -like $g) { return $true } }
    return $false
}

try {
    $compiled = @{}
    foreach ($r in $Rules) {
        $compiled[$r.id] = New-Object System.Text.RegularExpressions.Regex(
            $r.pattern, [System.Text.RegularExpressions.RegexOptions]::Compiled)
    }
    $markerRx = New-Object System.Text.RegularExpressions.Regex($RegionMarker)

    Push-Location $Root
    try {
        $files = @(& git ls-files | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $gitExit = $LASTEXITCODE
    } finally { Pop-Location }
    if ($gitExit -ne 0) { throw "git ls-files exited $gitExit - the file list could not be enumerated" }
    if ($files.Count -eq 0) {
        # Zero files scanned is a broken enumeration, never a clean tree.
        throw 'git ls-files returned no files - the enumeration is broken, so nothing was scanned'
    }
    $ownerPaths = @($RegionOwners | ForEach-Object { $_.path })
    Write-Output "  files   : $($files.Count) tracked"
    Write-Output ''

    foreach ($rel in $files) {
        $abs = Join-Path $Root ($rel -replace '/', '\')
        if (-not [IO.File]::Exists($abs)) { [void]$missing.Add($rel); continue }

        $bytes = [IO.File]::ReadAllBytes($abs)
        $probe = [Math]::Min($bytes.Length, 8192)
        if ($probe -gt 0 -and [Array]::IndexOf($bytes, [byte]0, 0, $probe) -ge 0) {
            [void]$binary.Add($rel); continue
        }
        $fileCount++

        $lines  = [IO.File]::ReadAllText($abs) -split "`r?`n"
        $inRegion = $false
        $isOwner  = $ownerPaths -contains $rel

        foreach ($r in $Rules) {
            if (-not $r.ContainsKey('scope')) { continue }
            if (-not $scopedFiles.ContainsKey($r.id)) { $scopedFiles[$r.id] = 0 }
            if (Test-RuleInScope -Rule $r -Rel $rel) { $scopedFiles[$r.id]++ }
        }

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            $m = $markerRx.Match($line)
            if ($m.Success) {
                if (-not $isOwner) {
                    # A region marker in a file that does not own one is an
                    # attempt to use the exemption channel as an escape hatch.
                    [void]$strayMark.Add([pscustomobject]@{ file = $rel; line = ($i + 1) })
                } else {
                    $inRegion = ($m.Groups[1].Value -eq 'begin')
                }
                continue
            }
            if ($inRegion) { continue }

            foreach ($r in $Rules) {
                if (-not (Test-RuleInScope -Rule $r -Rel $rel)) { continue }
                if ($compiled[$r.id].IsMatch($line)) {
                    $rec = [pscustomobject]@{
                        file = $rel; line = ($i + 1); rule = $r.id; name = $r.name; why = $r.why
                    }
                    # ORDER: historical, then ledger, then hit. A tombstone is
                    # not a disclosure at all, so it is classified before the
                    # question of who owns the file arises - which is what lets
                    # a temporary ledger entry be deleted without taking the
                    # file's honest history with it.
                    $hist = Test-Historical -Rel $rel -RuleId $r.id -Line $line
                    if ($hist) {
                        $histCount[$hist.test]++
                        $rec | Add-Member -NotePropertyName histWhy -NotePropertyValue $hist.why
                        [void]$historical.Add($rec)
                        continue
                    }
                    $entry = Test-Ledgered -Rel $rel -RuleId $r.id
                    if ($entry) {
                        $rec | Add-Member -NotePropertyName issue -NotePropertyValue $entry.issue
                        [void]$ledgered.Add($rec)
                    } else {
                        [void]$hits.Add($rec)
                    }
                }
            }
        }
        if ($isOwner -and $inRegion) { [void]$openRegion.Add($rel) }
    }

    # ----------------------------------------------------------------------
    # THE HISTORICAL TABLE, PRINTED WHOLE - INCLUDING THE ENTRIES THAT MATCHED
    # NOTHING. A per-entry count is the only honest answer to "is this table
    # still doing what it says?", because the `why` beside it is prose written
    # once and the number is derived every run. A zero means the file was fixed
    # or reflowed, which is not a failure and is not hidden either.
    # ----------------------------------------------------------------------
    if ($HistoricalMentions.Count -gt 0) {
        Write-Output "HISTORICAL MENTIONS - a deleted thing NAMED AS DELETED, which is the opposite of the defect ($($historical.Count) line(s) over $($HistoricalMentions.Count) entr(y/ies)):"
        foreach ($h in $HistoricalMentions) {
            $n = $histCount[$h.test]
            Write-Output ("  {0,3}  {1,-30}  {2}" -f $n, $h.files,
                $(if ($n -eq 0) { 'MATCHED NOTHING - the line was fixed, reflowed or never existed. Re-read this entry.' } else { $h.why }))
        }
        foreach ($h in $historical) {
            Write-Output ("       {0}:{1}  {2}" -f $h.file, $h.line, $h.rule)
        }
        Write-Output ''
    }

    # ----------------------------------------------------------------------
    # THE LEDGER, PRINTED. Never folded silently into a pass.
    # ----------------------------------------------------------------------
    if ($ledgered.Count -gt 0) {
        Write-Output "KNOWN, BARRED, NOT FIXED HERE - $($ledgered.Count) site(s) in files this pass does not own:"
        foreach ($l in $ledgered) {
            Write-Output ("  {0}:{1}  {2}   owned by {3}" -f $l.file, $l.line, $l.rule, $l.issue)
        }
        Write-Output 'These are REAL and are still in the payload. They are excused from the exit'
        Write-Output 'code because the files are outside this pass, not because they are acceptable.'
        Write-Output ''
    }

    # ----------------------------------------------------------------------
    # STRUCTURAL CASES - what was read, and whether the exemption channel held
    # ----------------------------------------------------------------------
    Add-Result 'S1  the tracked-file enumeration is non-empty' `
        ($files.Count -gt 0) `
        'git ls-files returned nothing; zero files scanned is a broken enumeration and never a clean tree'

    Add-Result 'S2  every tracked path exists on disk and was read' `
        ($missing.Count -eq 0) `
        ("$($missing.Count) tracked path(s) had nothing to read, so the payload was NOT fully scanned: " + ($missing -join ', '))

    Add-Result 'S3  no tracked file was skipped as binary' `
        ($binary.Count -eq 0) `
        ("$($binary.Count) tracked file(s) hold a NUL byte in the first 8 KB and were not read as text. A UTF-16 page is text in the wrong encoding, not a binary: " + ($binary -join ', '))

    Add-Result 'S4  only the declared owner carries an exempt region' `
        ($strayMark.Count -eq 0) `
        ("a region marker appeared in $($strayMark.Count) file(s) that may not declare one - the exemption channel is being used as an escape hatch: " +
            (($strayMark | ForEach-Object { "$($_.file):$($_.line)" }) -join ', '))

    Add-Result 'S5  no exempt region was left open' `
        ($openRegion.Count -eq 0) `
        ("$($openRegion.Count) owner file(s) opened a region and never closed it, so the rest of the file went unscanned: " + ($openRegion -join ', '))

    Add-Result 'S6  the encoded needle decoded to a usable pattern' `
        ($AddressPattern -ne 'rot13:(?v)ovm_grpu_rkrp' -and $AddressPattern.Length -gt 6 -and $AddressPattern.StartsWith('(?i)')) `
        "the rot13 needle did not decode, so the personal-address rule was matching a literal that appears nowhere and would have been permanently and silently green - the exact 'reports healthy while doing nothing' shape this plugin is named for"

    # A SCOPE THAT MATCHES NOTHING IS A RULE SWITCHED OFF, and it produces the
    # same output as a rule that ran everywhere and found nothing: a green line.
    # One mistyped glob would have made `deleted-script` permanently and
    # silently green over a payload it never opened - the "reports healthy while
    # doing nothing" shape this plugin is named for, built into its own guard.
    # It is S6's argument applied to the other channel that can switch a rule
    # off without saying so. This asserts the scoped rules reached a file; it
    # says nothing about whether the scope is the RIGHT one, which is a
    # judgement and is argued at the rule.
    $emptyScope = @($scopedFiles.Keys | Where-Object { $scopedFiles[$_] -eq 0 })
    Add-Result 'S7  every scoped rule was applied to at least one tracked file' `
        ($emptyScope.Count -eq 0) `
        ("$($emptyScope.Count) rule(s) declare a scope that matched no tracked file, so they asked nothing of anything and could not have found anything: " + ($emptyScope -join ', '))

    # ----------------------------------------------------------------------
    # RULE CASES - one per rule, over the payload, minus the ledger
    # ----------------------------------------------------------------------
    foreach ($r in $Rules) {
        $rHits = @($hits | Where-Object { $_.rule -eq $r.id })
        $sites = (($rHits | ForEach-Object { "$($_.file):$($_.line)" }) -join ', ')
        Add-Result ("R   the payload carries no " + $r.name) `
            ($rHits.Count -eq 0) `
            ("$($rHits.Count) site(s): $sites  --  $($r.why)")
    }

} catch {
    $script:Aborted = "$($_.Exception.Message)  [line $($_.InvocationInfo.ScriptLineNumber)]"
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
    # Zero cases is an abort wearing a pass's clothes.
    Write-Output 'ABORTED: no case ran at all, so nothing was established.'
    Write-Output 'EXIT: 2'
    exit 2
}

Write-Output ("RESULT: {0} of {1} case(s) passed in {2} ms   ({3} file(s) read, {4} ledger'd site(s), {5} historical mention(s))" -f `
    $script:Pass, $script:Results.Count, [int]$sw.Elapsed.TotalMilliseconds, $fileCount, $ledgered.Count, $historical.Count)

# 2 takes precedence over 1: a run that did not read everything cannot report
# "checked, and dirty" either. These are the structural cases, by name.
$notRead = @($fail | Where-Object { $_.name -match '^S[2345]\b' })
if ($notRead.Count -gt 0) {
    Write-Output ''
    Write-Output 'THE PAYLOAD WAS NOT FULLY SCANNED:'
    foreach ($f in $notRead) { Write-Output ("  - {0}: {1}" -f $f.name, $f.detail) }
    Write-Output 'EXIT: 2 (not scanned is not clean, and this is not a pass)'
    exit 2
}

if ($fail.Count -gt 0) {
    Write-Output ''
    Write-Output 'THE SHIPPED PAYLOAD DISCLOSES:'
    foreach ($f in $fail) { Write-Output ("  - {0}: {1}" -f $f.name, $f.detail) }
    Write-Output ''
    Write-Output 'Every tracked file here is shipped: .claude-plugin/marketplace.json declares'
    Write-Output '"source": "./" and that form has no exclusion. Fix the file, or take the'
    Write-Output 'payload-boundary decision - do not add a ledger entry to make this green.'
    Write-Output 'EXIT: 1'
    exit 1
}

Write-Output ''
Write-Output 'Every tracked file was read and no unledger''d disclosure is in the payload.'
Write-Output 'Read that as "these six shapes are absent", not as "the payload is safe to'
Write-Output 'publish" - this guard knows the disclosures it was told about and no others.'
Write-Output 'The sixth is scoped: the deleted-script rule is not yet asked of commands/ or'
Write-Output 'agents/, which is stated at the rule and is re-enabled when #195 lands.'
Write-Output 'EXIT: 0'
exit 0
