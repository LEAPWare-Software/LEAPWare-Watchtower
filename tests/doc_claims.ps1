#requires -version 5
<#
  LW-WATCHTOWER documentation-claim guard.

      powershell -NoProfile -ExecutionPolicy Bypass -File tests\doc_claims.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File tests\doc_claims.ps1 -ShowPasses
      powershell -NoProfile -ExecutionPolicy Bypass -File tests\doc_claims.ps1 -SkipSuites

  ---------------------------------------------------------------------------
  WHY THIS EXISTS
  ---------------------------------------------------------------------------
  This plugin's single promise is that it never overstates itself. Every other
  check here asks whether the CODE is right. This one asks whether the PROSE
  is, because on this tree the prose is the product.

  It exists because a checkable quantity - how many suites there are, how many
  cases one of them runs, how many checks the doctor performs - was stated in
  ten tracked files at once with nothing holding any of them to the tree. Two
  adversarial UAT passes found README.md contradicting ITSELF six lines apart
  on test coverage, three pages claiming a doctor check count the doctor does
  not have, and a limitations page whose own table refuted its own conclusion
  in the next paragraph. Every one of those was written by somebody who had
  read a sibling sentence rather than the tree.

  ---------------------------------------------------------------------------
  NOTHING HERE IS HARDCODED, AND THAT IS THE WHOLE POINT
  ---------------------------------------------------------------------------
  A guard carrying its own copy of the expected numbers is a ninth place for
  them to be wrong, and it would go green the day somebody updated it instead
  of the tree. So every expected value below is DERIVED at run time:

    tests/ file count      git ls-files -- tests/*.ps1, minus any the index
                           still lists that the working tree has deleted
    behavioural suites     every tests/*.ps1 except this one is RUN; the ones
                           that report an "N of M case(s)" tally are the
                           behavioural suites, the ones that report violations
                           are scans. The classification is an observation,
                           not a list.
    per-suite case counts   the M each suite prints about itself
    CI check steps         named steps with a run: block in .github/workflows/ci.yml
                           (`- name: Check out` uses an action and checks
                           nothing, so it is not one)
    doctor checks          bin\lwg-doctor.ps1 is run and its header parsed
    command count          git ls-files -- commands/*.md, same disk filter
    suite output contract  the RESULT: and EXIT: lines each sibling suite
                           prints are read off the run above, not asserted
                           from a list of which suites are supposed to have
                           them
    the CI job's name      the `name:` key of the one job in ci.yml, which is
                           the string a required status check on main matches
    the CI job's budget    timeout-minutes in ci.yml, against the sibling-suite
                           wait this file is given on the command line there
    module counts          $LwgModuleRegistry in lib/common.ps1, parsed
    declared version       the five DECLARATION sites, read from the files:
                           both .claude-plugin manifests, config.json, and the
                           two PowerShell literals. Prose about the version is
                           NOT read - see below.
    published tags         git tag -l, and an EMPTY result is "I do not know",
                           never "nothing has been tagged"

  If a derivation cannot complete, this suite ABORTS with exit 2 rather than
  reporting the claims it did manage to check. Zero files scanned is an abort,
  never an empty-set pass - the same rule the other suites here follow.

  ---------------------------------------------------------------------------
  THE OPT-OUT, AND WHAT IT IS FOR
  ---------------------------------------------------------------------------
  Some sentences in this tree are HISTORY and must keep their old numbers: a
  changelog entry recording what a suite held the day it landed, a UAT report
  recording what was observed on a date. Correcting those would be falsifying
  a record. Two markers exempt them, and both live in the file itself rather
  than in a sidecar list this guard would have to keep in step:

    <!-- doc-claims:ignore-file -->   anywhere in the file - the whole file is
                                      a record; nothing in it is read
    <!-- doc-claims:ignore -->        on the offending line, or on the line
                                      directly above it - that one sentence is
                                      a record

  A MARKER ONLY COUNTS INSIDE AN HTML COMMENT, and that is not decoration. The
  markers have to be described in tracked prose - CONTRIBUTING.md and
  docs/testing.md both explain them - and a bare token would mean any page that
  MENTIONS the convention exempts itself from it. That is not hypothetical: it
  happened to .github/workflows/ci.yml the first time this ran. Requiring the
  delimiters lets a page name the marker in prose or in backticks without
  invoking it. An HTML comment is also invisible in rendered Markdown, legal
  after a `#` in YAML, and legal inside a JSON string.

  A marker is a claim in itself: it says "this number is deliberately frozen".
  Do not reach for one to silence a number that is merely inconvenient to fix.

  ---------------------------------------------------------------------------
  WHAT IT DOES NOT DO
  ---------------------------------------------------------------------------
  It matches the PHRASINGS THIS TREE ACTUALLY USES, listed rule by rule below.
  It is not a natural-language checker and cannot be: a new way of writing
  "there are five suites" is invisible to it until a pattern is added. So a
  green run means "no phrasing this guard recognises disagrees with the tree",
  which is narrower than "every number in the docs is right". It is written
  down here rather than left to be assumed.

  It also says nothing about whether a sentence is TRUE in any other respect.
  A page can carry every number correctly and still describe a plugin that
  does not exist.

  ---------------------------------------------------------------------------
  EVERY PATTERN HAS TO FIRE, AND SEVEN OF THIRTY-SEVEN DID NOT
  ---------------------------------------------------------------------------
  The paragraph above says this guard reads "the PHRASINGS THIS TREE ACTUALLY
  USES". That was measured on 3 August 2026 by re-running the enumeration below
  over the tracked prose at cc44c99 and counting raw regex matches per pattern,
  and it was not true: SEVEN of the thirty-seven patterns matched nothing
  anywhere in the tree, so they could not fail on any input the repository
  contained and no line of output said so. They were:

    behavioural-suite-count  ^#{2,4}\s+The\s+(N)\s+suites
                             exactly (N) behavioural test
                             (N) things? (have|has) a behavioural test
                             \|\s*(N) suite,\s+covering
    ci-check-steps           one job, (`x`, )?with (N) steps
    doctor-check-count       doctor (performs|has) (N) checks
    observing-module-count   all (N) observing modules

  The first of those is the one that matters, because it is not merely a shape
  nobody ever wrote: it was written FOR docs\testing.md's heading, which today
  reads `## Eight files in \`tests/\`, and five of them test behaviour`. The
  heading was reworded and the pattern was not, so a rule went blind and the
  guard whose whole job is stale numbers reported the same green run either
  way. That is this file's own failure mode, occurring inside this file. All
  seven are DELETED rather than kept with a comment: a pattern retained as "not
  currently used" reports a coverage it does not have.

  So the rule now, enforced rather than remembered: A PATTERN THAT CHECKED NO
  CLAIM ANYWHERE IN THE TREE IS AN ABORT, NOT A CLEAN RUN. Every pattern is
  entered in a ledger with the number of claims it actually checked, and a zero
  exits 2 naming the rule and the pattern. Fix the pattern or delete it; do NOT
  allowlist it, and do NOT soften this to a warning - a warning line in a
  hundred-line green log is an unrun check reading as a passed one, which is
  the whole argument of this file.

  WHAT THAT COSTS, SAID PLAINLY. Deleting the last sentence a pattern reads now
  fails the build with exit 2 rather than passing silently. That is intended
  and it is the point, but it means an ordinary, improving documentation edit
  can turn this red. The message names the pattern and the rule; the two honest
  answers are to repoint the pattern at the new phrasing or to delete it.

  WHAT IT STILL DOES NOT ESTABLISH. A pattern firing once proves it can read
  THAT sentence, not that its shape is right in general, and it says nothing
  about the phrasings nobody has written a pattern for - the four named holes
  above are all still open. A live pattern set is a floor, not a ceiling.

  THE SAME RULE FIRED AGAIN WHEN checklist.json WAS DELETED, and this is the
  record of what went with it. The manifest and the NINE rules derived from it
  are gone; so is one pattern of a SURVIVING rule, which is the interesting
  half - the rule lives on and only its checklist-fed phrasing died.

  NINE, not four, and the difference is the point of that block's design: the
  per-kind rule was GENERATED, one Test-Claim per distinct evidence.kind in the
  manifest, so the number of rules was itself derived. The deleted file held 40
  items over six kinds - ci 1, command 6, commit 2, file 22, hook 1, manual 8 -
  which is 1 + 6 + 1 + 1 = 9 rules of one pattern each:

    DELETED WHOLE, because the file they derived from no longer exists. Each
    aborted this suite at `missing ...\checklist.json` before any claim was
    read, so the tree got no verdict at all until they went:

      checklist-item-total       `checklist.json` carries (N) items
      checklist-kind:<kind>      SIX of these, one per evidence.kind above,
                                 each reading its row of the histogram table in
                                 docs/limitations.md
      checklist-existence-only   (N) test nothing but existence
      checklist-file-rules       of the (N) `file` rules

    DELETED FROM A SURVIVING RULE, having gone dead by the liveness rule above:

      command-count #4           surface is (N) commands
                                 Its ONLY reader anywhere in the tree was
                                 checklist.json's own P4-commands caveat -
                                 "THE SURFACE IS TWELVE COMMANDS, down from
                                 fourteen". CHANGELOG.md phrases it as "the
                                 command surface is **twelve**," with no
                                 `commands` after the number, and is exempt
                                 whole in any case. The other three
                                 command-count patterns still read live claims,
                                 so the RULE is not blind - only this shape is
                                 gone.

  WHAT THAT COSTS, and it is not nothing: docs/limitations.md's evidence
  histogram is now held to the tree by NOTHING. It was the page written to be
  taken at face value about how little a green checklist established, its
  figures were stale-by-one in both directions once already, and the rules that
  caught that are the nine deleted above. The page describes a manifest that no
  longer ships, so the honest repair is to delete the section rather than to
  re-derive it, and that is a documentation pass and not this file's to make.

  THE DEAD-PATTERN CHECK RUNS BEFORE THE FAILURE REPORT, which is a choice and
  not an accident. On a tree that has BOTH a dead pattern and a stale number,
  this exits 2 and the stale number is never listed - the claims were not
  checked, so reporting some of them as checked would be the smaller lie told
  in place of the true one. Fix the pattern, run again, and the stale number is
  there. The alternative - report failures first and mention the dead pattern
  underneath - makes exit 1 mean "checked, and dirty" about a run that was not
  fully checked, which is the same collapse the exit-code table exists to stop.

  ---------------------------------------------------------------------------
  WHAT THIS GUARD DECLINES TO CHECK IS COUNTED AND NAMED
  ---------------------------------------------------------------------------
  A pattern can match a sentence and this file can then decline to check it,
  two ways: the captured token is not a quantity at all (`the nine that only
  observe` used to capture `that`), or the line carries a doc-claims:ignore
  marker. Both used to `continue` above the CHECKED counter, so a declined
  claim was not counted, not listed and not hinted at - and a run in which a
  stale number was silenced with an inline marker was byte-identical to a run
  in which the sentence was right. FILE-level exemptions were named out loud in
  the result and line-level ones were not, which is the asymmetry that made it
  invisible.

  Both are now counted and printed with file:line beside the result. They are
  NOT failures: a `doc-claims:ignore` marker is a decision the tree has already
  made and re-litigating it here would make the marker useless, and a
  non-quantity capture is usually running prose the pattern brushed against
  rather than a claim anybody made. They are reportable events, so a reviewer
  can diff them.

  FOUR SHAPES OF PER-SUITE CASE-COUNT CLAIM HAVE BEEN FOUND UNREAD BY THIS
  RULE. One of the four is read now; three are not. This rule is the one that
  reads "how many cases does suite X run", and it is the most-quoted number in
  this tree, so what it cannot see is named here with a live example each
  rather than described in general.

  READ THE LIST FOR WHAT IT IS: the shapes somebody has gone looking for and
  found, not a proof that no others exist. Two of the four were found after
  this block already declared itself complete, which is the reason it no longer
  states a total as though the search were over.

    1. DISTANCE - OPEN. A claim more than 240 characters after the suite's file
       name is NOT READ. Live example: docs/testing.md:176 says "Five sections,
       127 cases" about tests/stop_behaviour.ps1. That page names the file four
       times - lines 10, 61, 170 and 598 - so four windows open, and the only
       one that could reach line 176 is the one at line 170. Measured from the
       anchor this rule actually uses, $nm.Index + $nm.Length, over the
       LF-joined text: the claim starts 443 characters past the end of that
       occurrence of the file name, so it lies 203 characters beyond the end of
       a 240-character window. That sentence said 87 until 2 August 2026 -
       wrong by 40 against the 127 the suite reports - and this guard called the
       whole tree green over it that day. Correcting it did not bring it under
       the rule; it is still unread today, and the next person to edit it gets
       no help from here.

    2. NAMING - OPEN. A claim that names the MODULE rather than the suite FILE
       opens no window at all and is NOT COVERED, at all, by anything in this
       file. Live example: HANDOFF.md:171, "That conclusion applies to
       `delegate_gate` too - its suite being 80 of 80 green". `delegate_gate`
       is the module; tests/gate_delegate.ps1 is the file this rule keys on,
       and that string does not appear in the sentence. Compare HANDOFF.md:81,
       which states the same tally and DOES name the file - that one is read
       on every run. The difference is the file name and nothing else. That
       sentence's total has now gone stale twice with nothing here seeing it -
       71, then 79 - while the covered one was corrected against the tree both
       times. Matching module names as well was considered and is not done:
       a module has no case count of its own, so the guard would have to
       assume which suite a module's prose meant, and a guard that guesses at
       the subject of a sentence is a guard that reports on a claim nobody
       made.

    3. A COUNT TRAILING A COMMA - CLOSED on 2 August 2026, and the reason this
       block no longer says "two holes". Live example, CONTRIBUTING.md:111:
       `... -File tests\stop_behaviour.ps1      # the two turn-end hooks, 127`.
       That count read 126 until this shape was added and the guard failed the
       tree over it. It names the suite FILE correctly and the count sits 32
       characters past it, well inside the window, so it was neither 1 nor 2 -
       the rule simply had no shape for a bare count trailing a comma at the end
       of a line. It had been stale since section E of that suite landed. The
       shape is in $qtyPat now, this line is READ on every run, and what adding
       it read is row E of the table below.

    4. A COUNT IN PARENTHESES - OPEN, and found while closing 3.
       .github/PULL_REQUEST_TEMPLATE.md names tests\stop_behaviour.ps1 on line
       56 and states its count on line 57 as "failure_capture (127)", 48
       characters past the file name and inside the window. That number read
       126 until it was corrected by hand on 2 August 2026, and it is still
       unread today. Its three siblings in the same HTML comment - (46), (10)
       and (23) - are the same shape and happen to be right. It was NOT closed
       alongside 3: a bare `(\d+)` is a looser shape than a comma-anchored
       end-of-line count, nothing has yet measured what it would newly read
       across the tree, and adding a shape on the strength of one example
       instead of a measurement is the move this whole block argues against.

  WHY THE WINDOW WAS NOT WIDENED, WITH THE NUMBERS. Hole 1 looks like it wants
  a bigger window. It was tried, on this tree, and the counts below are from
  those runs rather than from an argument - the per-suite rule only, since that
  is the only rule any of it touches.

  READ THE PROVENANCE BEFORE RE-RUNNING THESE. Rows A to D were taken earlier on
  2 August 2026, on the tree AS IT STOOD BEFORE the stale numbers they turned up
  were corrected, with tests\gate_delegate.ps1 reporting 79 and
  tests\stop_behaviour.ps1 reporting 126. Only row B has been re-run since, on
  the corrected tree later the same day with the suites reporting 80 and 127:
  its CHECKED count reproduced exactly at 34 and its failures went to 0. A, C
  and D have NOT been re-run, so their failure counts belong to that earlier
  tree and nothing here says what they would be today. Which claims each
  configuration READS is the thing being compared; whether those claims happened
  to be true on the day is not.

    A  the rule as it stood, 240-char window, no bare `N of M`
                                                    32 checked, 0 failures
    B  + the bare `N of M` shape, window unchanged  34 checked, 2 failures
    C  + window bounded by section instead: 1500-char cap, terminated by a
       heading or by ANY .ps1 path                  29 checked, 2 failures
    D  + window bounded by section: 1500-char cap, terminated by a heading or
       by the next SUITE name only                  36 checked, 4 failures
    E  B + the trailing-comma shape, window unchanged
                                                    38 checked, 1 failure

  E IS WHAT SHIPS. It was measured on 2 August 2026 against the corrected tree
  by running this file with -ShowPasses before and after the change and diffing
  the two claim lists. The four claims E reads that B does not are the four
  annotated lines of one code block in CONTRIBUTING.md, lines 110 to 113, and
  nothing else anywhere in the tree; no claim B read was lost. One of the four
  was the stale 126 of hole 3 above, and the other three already agreed. Zero
  false positives, on that tree, by that diff - which is a statement about this
  tree on that day, not about the shape in general.

  A -> B is the change the rest of this note was written for: its two new
  failures are real stale numbers (docs/faq.md and docs/limitations.md, both
  saying 71 of a suite that reported 79) and it read nothing else new anywhere
  in the tree.

  C is strictly worse and not a trade at all: it catches nothing B does not and
  goes BLIND on five claims B reads, because the paragraph in docs/testing.md
  that introduces the suites names bin\ and lib\ scripts between each suite
  name and its count, so an any-.ps1 terminator cuts every window short.

  D is the tempting one and is still refused. It does catch hole 1 -
  docs/testing.md:176 - but it also reads CONTRIBUTING.md:125, which is about
  the DELETED gate_regression suite and says "233 cases over both PreToolUse
  gates", as a claim about tests/evidence_states.ps1, whose name appears 12
  lines earlier in a code block with no heading in between. That sentence is
  TRUE and is about a suite deleted with the gates on 30 July 2026. So D buys
  one true catch with one false accusation against a correct sentence, and the
  only ways to clear it are to freeze a true sentence behind doc-claims:ignore
  or to change a right number to a wrong one. On a guard whose whole worth is
  that a failure means something, a false failure costs more than a missed one.
  Hole 1 stays open, named, and unfixed rather than closed by something that
  lies.

  D CANNOT BE REPRODUCED AS WRITTEN ANY MORE, and the record is kept rather
  than corrected because the CONCLUSION still stands. tests/evidence_states.ps1
  has since been deleted, so the specific false accusation D produced no longer
  has a suite to be made against. The argument does not depend on that one
  sentence - it is that a window terminated only by the next SUITE name will
  reach across an unrelated code block - so D is still refused. Anyone
  re-running these rows will get different counts from a different tree; the
  numbers above belong to 2 August 2026 and are not a prediction about today.

  On the version specifically, two limits are worth stating because a green run
  looks like more than it is. It reads DECLARATIONS, not prose - a page saying
  "the manifests declare 0.3.0" is invisible to it, on purpose, because the
  same pattern would flag `## [0.3.0]` in the changelog and every "UAT against
  v0.3.0" in the docs, which name the tag and are right forever. And
  version-not-a-published-tag needs a visible tag ref, so it does not run on a
  depth-1 CI checkout; that gap is printed on every run and stated again in
  CONTRIBUTING.md.

  ---------------------------------------------------------------------------
  FOUR RULES IN THIS SECTION ARE NOT ABOUT QUANTITIES - AND THEY ARE NOT THE
  ONLY NON-QUANTITY RULES IN THE FILE
  ---------------------------------------------------------------------------
  Everything above matches a NUMBER out of prose. The four listed below do not,
  and they are written out longhand rather than forced through Test-Claim for the
  same reason the two version rules are - see the note above those. The
  FRONT-DOOR RULES section in the body carries more of the same shape; this
  heading read FOUR with no qualification until 3 August 2026, when those landed
  in the same change and it was not swept with them. Each one below is here
  because the fact it checks is coupled to a number or a string this file
  already derives, and there was nowhere else in the tree that could check it:

    suite-output-contract        every sibling suite prints a RESULT: line and
                                 an EXIT: line, which CONTRIBUTING.md and the
                                 PR template require a contributor to paste
    branch-protection-context    docs\testing.md quotes the CI job's `name:`
                                 verbatim, because that string - not the YAML
                                 job id - is what a required status check on
                                 main matches
    doc-claims-suite-budget      the sibling-suite wait this file is given in
                                 ci.yml is strictly inside the job's own
                                 timeout, so its exit-2 abort can actually fire
    doctor-is-run-by-ci          no tracked page says the doctor is outside CI,
                                 because this file runs it on every push
    docs-index-is-complete       every page under docs/ is linked from
                                 docs/README.md, because GitHub Pages publishes
                                 that whole directory to the open web and a page
                                 nobody indexed is a page nobody decided to
                                 publish. ONE DIRECTION ONLY - see the rule

  EXIT CODES - the same contract as this repo's other suites, and 2 is not a
  pass:
    0  every recognised claim agrees with the tree
    1  at least one claim disagrees
    2  a derivation or the enumeration failed, or a pattern checked nothing;
       the claims were NOT checked
#>

[CmdletBinding()]
param(
    # Print the claims that agreed as well as the ones that did not.
    [switch]$ShowPasses,

    # Skip running the sibling suites. The rules that depend on their tallies
    # are then NOT CHECKED, and this script exits 2 rather than 0 - an unrun
    # check must never read as a passed one. For a fast docs-only edit loop.
    [switch]$SkipSuites,

    # How long to wait for the parallel suite run, in seconds. THE DEFAULT IS
    # NOT WHAT CI USES and must not be read as the sanctioned value: the
    # Documentation claims step in .github\workflows\ci.yml passes an explicit
    # number, and the doc-claims-suite-budget rule at the foot of this file
    # holds whatever it passes strictly inside that job's timeout-minutes. The
    # default exists for a run from a clone, where there is no outer budget to
    # collide with. Measured on 3 August 2026, the healthy parallel run was
    # 249 s on one developer machine.
    [int]$SuiteTimeoutSec = 900
)

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent $PSScriptRoot

# THE PAYLOAD IS A SUBDIRECTORY NOW, AND THIS FILE NEEDS BOTH ROOTS. tests/,
# docs/, .github/ and the root community-health files stayed where they were;
# the shipped plugin moved under lw-watchtower/. Every $rel this file gets from
# `git ls-files` is repo-relative and keeps resolving off $script:RepoRoot
# unchanged - it is the HARDCODED payload paths, and the regexes that filter the
# tracked list, that had to move.
#
# THE HARDCODE IS A CHECKED CLAIM, NOT A CONSTANT. Immediately after the
# marketplace entry is resolved below, the declared `source` is compared against
# $script:PayloadRel and the run ABORTS if they disagree - because a guard that
# derived `command-count = 0` from a path that no longer exists would report
# every "six commands" sentence in the tree as wrong, which is a worse failure
# than not running at all.
$script:PayloadRel  = 'lw-watchtower'
$script:PayloadRoot = Join-Path $script:RepoRoot $script:PayloadRel
$script:SelfPath = $MyInvocation.MyCommand.Path
$script:Failures = @()
$script:Passes   = 0
$script:Checked  = 0

# One row per pattern that was offered to the tree, carrying the number of
# claims it actually CHECKED - not the number of raw regex matches, because a
# pattern whose every match was declined checked nothing. A zero here is an
# abort at the foot of this file. See the header for the seven that were dead.
$script:PatternLedger = @()

# Rules whose whole pattern set checked nothing. Derived from the ledger rather
# than kept in step by hand.
$script:DeadRules = @()

# Claims a pattern matched and this guard then declined to check, with the
# reason. Counted and named in the result; never a failure. See the header.
$script:Declines = @()

function Say { param([string]$Text = '') Write-Output $Text }

function Abort {
    param([string]$Why)
    Say ''
    Say "ABORT: $Why"
    Say 'Nothing about the documentation was established by this run.'
    Say 'EXIT: 2'
    exit 2
}

function Invoke-Git {
    param([string[]]$GitArgs)
    Push-Location -LiteralPath $script:RepoRoot
    try {
        $out = & git @GitArgs 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return @($out | Where-Object { $_ })
    } finally { Pop-Location }
}

# --- number words ----------------------------------------------------------
# The docs spell small numbers out as often as they use digits, and the two
# spellings drift independently - README.md said "Three things" and "62 cases"
# in the same bullet. Both forms are read here so neither can hide.
$script:Words = @{
    'zero' = 0; 'one' = 1; 'two' = 2; 'three' = 3; 'four' = 4; 'five' = 5
    'six' = 6; 'seven' = 7; 'eight' = 8; 'nine' = 9; 'ten' = 10
    'eleven' = 11; 'twelve' = 12; 'thirteen' = 13; 'fourteen' = 14
    'fifteen' = 15; 'sixteen' = 16; 'seventeen' = 17; 'eighteen' = 18
    'nineteen' = 19; 'twenty' = 20
}

# The number-word alternation, built FROM $script:Words so the two cannot drift.
# Used by patterns whose surrounding text is ordinary prose, where the usual
# `([a-z]+|\d+)` capture would match any word at all: README.md writes "Wiring
# checks aimed at what is not working" on purpose - it deliberately transcribes
# no count - and a loose capture reads "Wiring" and then declines it, which puts
# a line in the report about a sentence that is doing the right thing.
$script:NumWordPat = ((($script:Words.Keys | Sort-Object) -join '|') + '|\d+')

function ConvertTo-Quantity {
    param([string]$Token)
    if ([string]::IsNullOrWhiteSpace($Token)) { return $null }
    $t = $Token.Trim().ToLowerInvariant()
    if ($t -match '^\d+$') { return [int]$t }
    if ($script:Words.ContainsKey($t)) { return [int]$script:Words[$t] }
    return $null
}

# =========================================================================
# DERIVATIONS
# =========================================================================

Say '==========================================================================='
Say 'LW-WATCHTOWER documentation-claim guard'
Say "  repo root : $script:RepoRoot"
Say ''
Say 'Deriving the truth from the tree.'
Say ''

# --- tracked files ---------------------------------------------------------
# TRACKED **AND STILL ON DISK**, and the second half is not belt-and-braces.
# `git ls-files` reads the INDEX, so a file deleted in the working tree and not
# yet staged is still listed. A wave of deletions is exactly that state for as
# long as it takes to stage them, and during it this file derived twelve slash
# commands against six that ship and thirteen files in tests/ against twelve -
# so `command-count` and `tests-file-count` would have failed every correct
# sentence in the tree and passed the stale ones. Worse, the parallel sibling
# runner below calls `Resolve-Path -LiteralPath` on every entry under
# $ErrorActionPreference = 'Stop', so one deleted suite ended the whole run in
# an unhandled exception - not even the exit-2 ABORT this file promises.
#
# THE PROSE LOOP FURTHER DOWN HAS ALWAYS DONE THIS (`if (-not (Test-Path ...))
# { continue }`), so this is that convention extended to the two enumerations
# that had been left out of it, not a new rule. Once the deletions are staged
# the index and the disk agree and this filter is a no-op; it costs nothing and
# it is what stops the guard reporting on files that are gone.
function Test-StillOnDisk {
    param([string]$Rel)
    return (Test-Path -LiteralPath (Join-Path $script:RepoRoot ($Rel -replace '/', '\')) -PathType Leaf)
}

$tracked = Invoke-Git @('ls-files')
if (-not $tracked -or $tracked.Count -eq 0) {
    Abort 'git ls-files returned nothing - the enumeration is broken, not the repo.'
}

$testFiles = @($tracked | Where-Object { $_ -match '^tests/.+\.ps1$' -and (Test-StillOnDisk $_) })
if ($testFiles.Count -eq 0) { Abort 'no tracked files under tests/ are present on disk - the enumeration is broken.' }

$commandFiles = @($tracked | Where-Object { $_ -match ('^' + [regex]::Escape($script:PayloadRel) + '/commands/.+\.md$') -and (Test-StillOnDisk $_) })
if ($commandFiles.Count -eq 0) { Abort 'no tracked files under commands/ are present on disk - the enumeration is broken.' }

# --- CI check steps --------------------------------------------------------
# A CHECK STEP is a step that RUNS something. `- name: Check out` uses an
# action and checks nothing, so counting `- name:` overcounts by one forever.
# Counting `shell: powershell` is wrong in the other direction and was tried
# first: the job declares one under `defaults.run`, which is not a step at all,
# so that count read one too high with no step to point at. So: enumerate the
# named steps, and keep the ones that carry a `run:` block.
$ciPath = Join-Path $script:RepoRoot '.github\workflows\ci.yml'
if (-not (Test-Path -LiteralPath $ciPath -PathType Leaf)) { Abort "missing $ciPath" }
$ciText = Get-Content -Raw -LiteralPath $ciPath
$stepHeads = @([regex]::Matches($ciText, '(?m)^\s+-\s+name:\s*\S'))
if ($stepHeads.Count -eq 0) { Abort 'ci.yml declares no named steps - the parse is broken.' }
$ciSteps = 0
for ($i = 0; $i -lt $stepHeads.Count; $i++) {
    $start = $stepHeads[$i].Index
    $end   = if ($i + 1 -lt $stepHeads.Count) { $stepHeads[$i + 1].Index } else { $ciText.Length }
    $block = $ciText.Substring($start, $end - $start)
    if ($block -match '(?m)^\s+run:\s*\|') { $ciSteps++ }
}
if ($ciSteps -eq 0) { Abort 'no named step in ci.yml carries a run: block - the parse is broken.' }

# --- module registry -------------------------------------------------------
# Parsed out of lib/common.ps1 rather than dot-sourced: dot-sourcing a hook
# library to count a hashtable runs its whole prologue for one number.
$commonPath = Join-Path $script:PayloadRoot 'lib\common.ps1'
if (-not (Test-Path -LiteralPath $commonPath -PathType Leaf)) { Abort "missing $commonPath" }
$commonText = Get-Content -Raw -LiteralPath $commonPath
$regMatch = [regex]::Match($commonText,
    '(?s)\$script:LwgModuleRegistry\s*=\s*\[ordered\]@\{(.+?)(?m:^\})')
if (-not $regMatch.Success) { Abort 'could not locate $LwgModuleRegistry in lib/common.ps1.' }
$regBody = $regMatch.Groups[1].Value

$moduleEntries = @()
foreach ($m in [regex]::Matches($regBody, '(?m)^\s{4}(\w+)\s*=\s*@\{')) {
    $name  = $m.Groups[1].Value
    $start = $m.Index
    $next  = [regex]::Match($regBody.Substring($start + $m.Length), '(?m)^\s{4}\w+\s*=\s*@\{')
    $len   = if ($next.Success) { $next.Index } else { $regBody.Length - $start - $m.Length }
    $body  = $regBody.Substring($start + $m.Length, $len)
    $moduleEntries += [pscustomobject]@{
        Name = $name
        Kind = if ($body -match "kind\s*=\s*'(\w+)'") { $Matches[1] } else { 'unknown' }
    }
}
if ($moduleEntries.Count -eq 0) { Abort 'the module registry parsed to zero entries.' }
$moduleTotal     = $moduleEntries.Count
$moduleObserving = @($moduleEntries | Where-Object { $_.Kind -eq 'observe' }).Count
$moduleGates     = @($moduleEntries | Where-Object { $_.Kind -eq 'gate' }).Count
if ($moduleObserving -eq 0) { Abort 'the module registry parsed to zero observing modules.' }

# --- the declared version, and the tags already published ------------------
# WHY A VERSION BELONGS IN A GUARD ABOUT PROSE. A version string is the one
# claim in this tree that is made to a MACHINE and to a person at once: it is
# what `/plugin install` records, and it is what an operator quotes in a bug
# report. Between the `v0.3.0` tag and the commit that added this block, `main`
# moved 12 commits and +5322/-489 lines while all five declaration sites went
# on reading `0.3.0`. Two of those commits changed how an EXISTING config.json
# is interpreted. So "0.3.0" named two different trees that behaved differently
# on the same input, and nothing anywhere could tell them apart. That is not a
# stale number in a sentence; it is an identifier that had stopped identifying.
#
# The marketplace route in README.md and docs/install.md pins no ref, so it
# resolves the DEFAULT BRANCH. There is no version key that can fix that - it
# is a property of the route - which is why the fix is documentation plus this
# guard, and why the guard checks the one thing that IS in the tree's control:
# main must never declare a version that a published tag already claims.
#
# WHAT IS READ, AND WHAT IS DELIBERATELY NOT. Only DECLARATION sites - the
# fields a machine reads. Prose ABOUT the version is not read, and that is a
# deliberate limit rather than an oversight: a pattern loose enough to catch
# "the manifests declare 0.3.0" is loose enough to catch `## [0.3.0]` in the
# changelog and every "adversarial UAT against v0.3.0" in the docs, which name
# the TAG - the tested tree - and are correct at 0.3.0 forever. Distinguishing
# the two needs a reader, so the prose sweep is a release-checklist item in
# CONTRIBUTING.md and is NOT claimed here.
function Get-LineOf {
    param([string[]]$Lines, [string]$Pattern)
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match $Pattern) { return $i + 1 }
    }
    return 0   # the value was still read; only its line is unknown
}

$versionSites = @()

# The two manifests and config.json are read with ConvertFrom-Json rather than
# by regex over the raw text. lib/gate_delegate.ps1 carries the scar that
# argues for this: its raw-text member scan compared names Ordinally against
# still-escaped bytes and turned every spelling it was too strict to see into a
# silent pass. A guard is the last place that failure belongs, so the VALUE
# comes from a real parse and the regex is used only to point at a line.
$pluginRel   = "$($script:PayloadRel)/.claude-plugin/plugin.json"
$pluginPath  = Join-Path $script:PayloadRoot '.claude-plugin\plugin.json'
if (-not (Test-Path -LiteralPath $pluginPath -PathType Leaf)) { Abort "missing $pluginPath" }
$pluginLines = @(Get-Content -LiteralPath $pluginPath)
try { $pluginJson = ($pluginLines -join "`n") | ConvertFrom-Json }
catch { Abort "$pluginRel did not parse, so the declared version was never read: $($_.Exception.Message)" }
if ([string]::IsNullOrWhiteSpace([string]$pluginJson.version)) { Abort "$pluginRel declares no version." }
$versionSites += [pscustomobject]@{
    Rel = $pluginRel; Line = (Get-LineOf $pluginLines '"version"\s*:'); Value = [string]$pluginJson.version
}

$mktRel   = '.claude-plugin/marketplace.json'
$mktPath  = Join-Path $script:RepoRoot '.claude-plugin\marketplace.json'
if (-not (Test-Path -LiteralPath $mktPath -PathType Leaf)) { Abort "missing $mktPath" }
$mktLines = @(Get-Content -LiteralPath $mktPath)
try { $mktJson = ($mktLines -join "`n") | ConvertFrom-Json }
catch { Abort "$mktRel did not parse, so the declared version was never read: $($_.Exception.Message)" }
# Matched by NAME rather than by taking [0]: this marketplace hosts one plugin
# today, and an index would silently start reading the wrong entry the day it
# hosts two.
$mktEntry = @($mktJson.plugins | Where-Object { $_.name -eq $pluginJson.name })
if ($mktEntry.Count -ne 1) {
    Abort ("$mktRel holds {0} entries named '{1}', expected exactly 1, so its version was never read." -f $mktEntry.Count, $pluginJson.name)
}
if ([string]::IsNullOrWhiteSpace([string]$mktEntry[0].version)) { Abort "$mktRel's '$($pluginJson.name)' entry declares no version." }
$versionSites += [pscustomobject]@{
    Rel = $mktRel; Line = (Get-LineOf $mktLines '"version"\s*:'); Value = [string]$mktEntry[0].version
}

# THE PAYLOAD PATH THIS FILE HARDCODES, CHECKED AGAINST THE FILE THE CLI READS.
# $script:PayloadRel appears in eight places above and below - the command
# filter, the module registry, three version sites, the status line, hooks.json
# and the plugin description. Every one of them would go quietly wrong together
# if the subtree were renamed in marketplace.json and not here, and the failure
# would not look like a broken guard: `command-count` would derive ZERO and this
# suite would then report every "six commands" sentence in the tree as a stale
# claim. That is a guard confidently reporting the opposite of the truth, which
# is worse than one that does not run. So it aborts instead.
$declaredSource = [string]$mktEntry[0].source
if ($declaredSource -ne ('./' + $script:PayloadRel)) {
    Abort ("$mktRel declares source '$declaredSource' but this guard resolved the payload at './$($script:PayloadRel)'. One of them is wrong and nothing below was checked.")
}

$cfgRel   = "$($script:PayloadRel)/config.json"
$cfgPath  = Join-Path $script:PayloadRoot 'config.json'
if (-not (Test-Path -LiteralPath $cfgPath -PathType Leaf)) { Abort "missing $cfgPath" }
$cfgLines = @(Get-Content -LiteralPath $cfgPath)
try { $cfgJson = ($cfgLines -join "`n") | ConvertFrom-Json }
catch { Abort "$cfgRel did not parse, so the declared version was never read: $($_.Exception.Message)" }
if ([string]::IsNullOrWhiteSpace([string]$cfgJson.version)) { Abort "$cfgRel declares no version." }
$versionSites += [pscustomobject]@{
    Rel = $cfgRel; Line = (Get-LineOf $cfgLines '"version"\s*:'); Value = [string]$cfgJson.version
}

# The two PowerShell literals are read by regex because there is nothing to
# parse - they are assignments, and dot-sourcing either file to learn one
# string would run a hook prologue, which is the same reason the module
# registry above is parsed rather than loaded.
$verLiterals = @(
    @{ Rel = "$($script:PayloadRel)/lib/common.ps1";        Path = 'lib\common.ps1';        Pattern = "\`$script:LwgVersion\s*=\s*'([^']+)'" }
    @{ Rel = "$($script:PayloadRel)/lib/session_start.ps1"; Path = 'lib\session_start.ps1'; Pattern = "(?m)^\s*\`$version\s*=\s*'([^']+)'" }
)
foreach ($lit in $verLiterals) {
    $litPath = Join-Path $script:PayloadRoot $lit.Path
    if (-not (Test-Path -LiteralPath $litPath -PathType Leaf)) { Abort "missing $litPath" }
    $litLines = @(Get-Content -LiteralPath $litPath)
    $litMatch = [regex]::Match(($litLines -join "`n"), $lit.Pattern)
    if (-not $litMatch.Success) {
        Abort ("no version literal matched in {0}, so that declaration was never read. If it moved, this pattern has to move with it." -f $lit.Rel)
    }
    $versionSites += [pscustomobject]@{
        Rel = $lit.Rel; Line = (Get-LineOf $litLines $lit.Pattern); Value = $litMatch.Groups[1].Value
    }
}

# WHY ZERO TAGS IS "I DO NOT KNOW" AND NOT "THERE ARE NONE". `git tag -l` exits
# 0 and prints nothing on a clone whose tag refs were never fetched, which is
# the default shape of an actions/checkout@v4 checkout - fetch-depth 1, no
# tags. Reading that silence as "no tag has been published" would make the
# identity rule pass vacuously on exactly the machine that runs it most, and
# that is the defect bin/lwg-evidence.ps1 was fixed for in 23f2ef2: a probe
# that could not run rendering as a probe that ran and found the thing absent.
# So an empty tag list is NOT CHECKED, said out loud in the result, and never
# counted as a pass.
$tagsKnown     = $false
$publishedTags = @()
$tagExit       = $null
Push-Location -LiteralPath $script:RepoRoot
try {
    $tagOut  = & git --no-pager tag -l 2>$null
    $tagExit = $LASTEXITCODE
} finally { Pop-Location }
if ($tagExit -eq 0) { $publishedTags = @($tagOut | Where-Object { $_ }) }
if ($tagExit -eq 0 -and $publishedTags.Count -gt 0) { $tagsKnown = $true }

# --- doctor checks ---------------------------------------------------------
# The doctor is RUN. Its exit code is deliberately ignored: it exits non-zero
# on a real finding about the machine this happens to run on, and how many
# checks it performs is a different question from whether they passed.
$doctorPath = Join-Path $script:PayloadRoot 'bin\lwg-doctor.ps1'
if (-not (Test-Path -LiteralPath $doctorPath -PathType Leaf)) { Abort "missing $doctorPath" }
$doctorOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $doctorPath
$doctorText = ($doctorOut -join "`n")
$docMatch = [regex]::Match($doctorText, 'doctor\s*-\s*(\d+)\s+checks')
if (-not $docMatch.Success) {
    Abort 'bin\lwg-doctor.ps1 printed no "- N checks" header, so its check count was never observed.'
}
$doctorChecks = [int]$docMatch.Groups[1].Value

# --- the sibling suites ----------------------------------------------------
# Run in parallel, each in its own child process. Every suite here builds its
# scratch tree under [IO.Path]::GetTempPath() with a fresh GUID, so parallel
# runs cannot collide by construction - checked before this was written.
# Serial would cost the sum of them; this costs the slowest one.
$suiteTallies = @{}
$behaviouralCount = $null
$suitesRan = $false
# Kept so the RESULT:/EXIT: contract rule below can read what each suite
# actually printed rather than being told which suites are supposed to print
# it. Same principle as the tally: an observation, not a list.
$suiteOutputs = @{}

if (-not $SkipSuites) {
    $toRun = @()
    foreach ($rel in $testFiles) {
        $full = Join-Path $script:RepoRoot ($rel -replace '/', '\')
        if ($script:SelfPath -and
            ((Resolve-Path -LiteralPath $full).Path -eq (Resolve-Path -LiteralPath $script:SelfPath).Path)) {
            continue
        }
        $toRun += [pscustomobject]@{ Rel = $rel; Full = $full; Base = [IO.Path]::GetFileNameWithoutExtension($full) }
    }
    if ($toRun.Count -eq 0) { Abort 'no sibling suites to run - the enumeration is broken.' }

    Say ("  running $($toRun.Count) sibling suite(s) in parallel to read their own tallies ...")
    $jobs = @()
    foreach ($s in $toRun) {
        $jobs += Start-Job -ArgumentList $s.Full, $s.Base -ScriptBlock {
            param($Path, $Base)
            $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Path
            [pscustomobject]@{ Base = $Base; Code = $LASTEXITCODE; Out = ($out -join "`n") }
        }
    }
    $done = $jobs | Wait-Job -Timeout $SuiteTimeoutSec
    if ($done.Count -ne $jobs.Count) {
        $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
        Abort "a sibling suite did not finish inside $SuiteTimeoutSec s, so its case count was never observed."
    }
    $results = $done | Receive-Job
    $jobs | Remove-Job -Force -ErrorAction SilentlyContinue

    foreach ($r in $results) {
        if ($r.Code -ne 0) {
            Abort ("tests\{0}.ps1 exited {1}. Its tally cannot be trusted, so no claim about it was checked. Fix that suite first." -f $r.Base, $r.Code)
        }
        # The classifier. A behavioural suite tallies CASES; a scan tallies
        # violations. Neither is told which it is - it is read off what each
        # one says about itself.
        $m = [regex]::Match($r.Out, '(\d+)\s+of\s+(\d+)\s+case\(s\)')
        if ($m.Success) { $suiteTallies[$r.Base] = [int]$m.Groups[2].Value }
        $suiteOutputs[$r.Base] = $r.Out
    }
    if ($suiteTallies.Count -eq 0) {
        Abort 'no sibling suite reported an "N of M case(s)" tally, so the behavioural-suite count was never observed.'
    }
    $behaviouralCount = $suiteTallies.Count
    $suitesRan = $true
}

Say ''
Say '  DERIVED FROM THE TREE'
Say ("    files in tests/                  {0}" -f $testFiles.Count)
if ($suitesRan) {
    Say ("    behavioural suites               {0}" -f $behaviouralCount)
    foreach ($k in ($suiteTallies.Keys | Sort-Object)) {
        Say ("      tests\{0,-24} {1} case(s)" -f ($k + '.ps1'), $suiteTallies[$k])
    }
} else {
    Say  '    behavioural suites               NOT CHECKED (-SkipSuites)'
}
Say ("    CI check steps                   {0}" -f $ciSteps)
Say ("    doctor checks                    {0}" -f $doctorChecks)
Say ("    slash commands                   {0}" -f $commandFiles.Count)
Say ("    modules declared                 {0} ({1} observe, {2} gate)" -f $moduleTotal, $moduleObserving, $moduleGates)
Say ("    version declared                 {0} in {1} site(s)" -f (($versionSites | ForEach-Object { $_.Value } | Sort-Object -Unique) -join ', '), $versionSites.Count)
if ($tagsKnown) {
    Say ("    tags already published           {0} ({1})" -f $publishedTags.Count, ($publishedTags -join ', '))
} else {
    Say ("    tags already published           NOT CHECKED - {0}" -f $(if ($tagExit -ne 0) { "git tag -l exited $tagExit" } else { 'this clone has no tag ref' }))
}
Say ''

# =========================================================================
# THE FILES TO READ
# =========================================================================
# Prose files only. A .ps1 is checked by the parse step and by its own suite;
# what this guard is about is the pages a reader believes.
$proseFiles = @($tracked | Where-Object { $_ -match '\.(md|json|yml|yaml)$' })
if ($proseFiles.Count -eq 0) { Abort 'no tracked prose files found - the enumeration is broken.' }

$docs = @()
$skippedWhole = @()
foreach ($rel in $proseFiles) {
    $full = Join-Path $script:RepoRoot ($rel -replace '/', '\')
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
    $lines = @(Get-Content -LiteralPath $full)
    $text  = ($lines -join "`n")
    if ($text -match '<!--[^>]*doc-claims:ignore-file') { $skippedWhole += $rel; continue }
    $docs += [pscustomobject]@{ Rel = $rel; Lines = $lines; Text = $text }
}
if ($docs.Count -eq 0) { Abort 'every prose file was exempted - that is not a pass.' }

# A line is exempt when it carries the marker, or when the line directly above
# it does. The second form is what lets a Markdown paragraph be excused
# without an HTML comment landing mid-sentence.
function Test-LineExempt {
    param($Doc, [int]$LineNo)   # 1-based
    $i = $LineNo - 1
    if ($i -ge 0 -and $i -lt $Doc.Lines.Count -and $Doc.Lines[$i] -match '<!--[^>]*doc-claims:ignore') { return $true }
    if ($i -ge 1 -and $Doc.Lines[$i - 1] -match '<!--[^>]*doc-claims:ignore') { return $true }
    return $false
}

function Get-LineNumber {
    param($Doc, [int]$Index)
    return (($Doc.Text.Substring(0, $Index) -split "`n").Count)
}

function Get-Excerpt {
    param($Doc, [int]$LineNo)
    $i = $LineNo - 1
    if ($i -lt 0 -or $i -ge $Doc.Lines.Count) { return '' }
    $s = $Doc.Lines[$i].Trim()
    if ($s.Length -gt 132) { $s = $s.Substring(0, 129) + '...' }
    return $s
}

# =========================================================================
# THE RULES
# =========================================================================
# Each rule is: a name, the derived number it must agree with, where that
# number came from, and the phrasings this tree uses to state it. Group 1 of
# every pattern is the quantity, in digits or in words.

function Add-Decline {
    <#
      A claim a pattern matched and this guard then declined to check. Recorded
      rather than dropped: see the header. Kind is 'no-quantity' or
      'line-exempt', and both are printed with file:line beside the result.
    #>
    param([string]$Rule, [string]$Kind, [string]$File, [int]$Line, [string]$Token)
    $script:Declines += [pscustomobject]@{
        Rule = $Rule; Kind = $Kind; File = $File; Line = $Line; Token = $Token
    }
}

# WHY THIS RETURNS NOTHING, AND WHY THE $null = ASSIGNMENTS ARE GONE. Until
# 3 August 2026 this function ended `return $hits` and all eight call sites read
# `$null = Test-Claim ...`. The stated cost was that a rule which stopped
# matching became invisible. The real cost was larger and nobody had noticed
# it: Say is Write-Output, so `$null =` swallowed the function's WHOLE output
# stream - every [FAIL] line and every -ShowPasses [ok] line for all eight
# quantity rules went nowhere. Measured at cc44c99: `-SkipSuites -ShowPasses`
# printed nine [ok] lines, all of them from the two version rules further down,
# which are written longhand and outside this function. Failures still reached
# the report at the foot of the file and the exit code was still right, so the
# swallowing had never shown up as a wrong answer.
#
# A function that PRINTS must not also return a value in PowerShell, so the
# count is published on $script:PatternLedger instead of returned, and the call
# sites are bare. That is what makes the per-pattern liveness check possible at
# all, and it is why there is no `$hits` to discard any more.
function Test-Claim {
    param(
        [string]$Rule,
        [int]$Expected,
        [string]$Source,
        [string[]]$Patterns
    )
    # Iterated pattern-outermost rather than document-outermost so each pattern
    # gets its own tally. The claims are the same set either way; only the order
    # of the printed lines changes, and per-pattern is the order that lets a
    # dead pattern be named.
    for ($pi = 0; $pi -lt $Patterns.Count; $pi++) {
        $pat = $Patterns[$pi]
        $patHits = 0
        foreach ($doc in $docs) {
            foreach ($m in [regex]::Matches($doc.Text, $pat)) {
                $ln  = Get-LineNumber $doc $m.Index
                $qty = ConvertTo-Quantity $m.Groups[1].Value
                if ($null -eq $qty) {
                    Add-Decline -Rule $Rule -Kind 'no-quantity' -File $doc.Rel -Line $ln -Token $m.Groups[1].Value
                    continue
                }
                if (Test-LineExempt $doc $ln) {
                    Add-Decline -Rule $Rule -Kind 'line-exempt' -File $doc.Rel -Line $ln -Token ([string]$qty)
                    continue
                }
                $patHits++
                $script:Checked++
                if ($qty -eq $Expected) {
                    $script:Passes++
                    if ($ShowPasses) {
                        Say ("  [ok]   {0,-26} {1}:{2}  says {3}" -f $Rule, $doc.Rel, $ln, $qty)
                    }
                } else {
                    $script:Failures += [pscustomobject]@{
                        Rule = $Rule; File = $doc.Rel; Line = $ln
                        Said = $qty; Expected = $Expected; Source = $Source
                        Excerpt = (Get-Excerpt $doc $ln)
                    }
                    Say ("  [FAIL] {0,-26} {1}:{2}  says {3}, tree says {4}" -f $Rule, $doc.Rel, $ln, $qty, $Expected)
                    Say ("         {0}" -f (Get-Excerpt $doc $ln))
                }
            }
        }
        $script:PatternLedger += [pscustomobject]@{
            Rule = $Rule; Index = ($pi + 1); Pattern = $pat; Hits = $patHits
        }
    }
}

Say 'Reading the claims.'
Say ''

# --- how many files are in tests/ -----------------------------------------
Test-Claim -Rule 'tests-file-count' -Expected $testFiles.Count `
    -Source 'git ls-files -- tests/*.ps1, present on disk' -Patterns @(
    '(?i)(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+(?:test\s+)?files?\s+in\s+`tests/`',
    '(?i)`tests/`\s+holds\s+(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+files?',
    '(?i)(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+test\s+files?\s+remain',
    '(?i)(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+files?,\s+all\s+in\s+the\s+`fast-checks`'
)

# --- how many of them test behaviour --------------------------------------
if ($suitesRan) {
    # THE TWO SHAPES ADDED ON 3 AUGUST 2026, AND WHAT EACH ONE WENT RED ON.
    # Both were written against a sentence that was in the tree and wrong, and
    # both still read that sentence after it was corrected - which is the only
    # way to add a pattern here without leaving a dead one behind.
    #
    #   `N of the M tests of behaviour` - .github\workflows\ci.yml said "One of
    #   the three tests of behaviour in this repository" 279 lines below its own
    #   header saying FIVE. Note the capture: the quantity is the SECOND number,
    #   because the subject of the sentence is M and not N. That is why no
    #   existing branch read it - every other shape here captures the first
    #   number it sees.
    #
    #   `N behavioural test files survive` - docs\commands.md said "One
    #   behavioural test file survives it" and named tests\gate_delegate.ps1 as
    #   the only one, while four documents counted five.
    Test-Claim -Rule 'behavioural-suite-count' -Expected $behaviouralCount `
        -Source 'every tests/*.ps1 was run; these reported a case tally' -Patterns @(
        '(?i)(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+of\s+them\s+(?:test\s+behaviour|behavioural)',
        '(?i)(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+behavioural\s+suites?',
        '(?i)([a-z]+|\d+)\s+suites?\s+test\s+behaviour',
        '(?i)(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+suites?\s+in\s+this\s+repository',
        '(?i)(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+suites?\s+tests?\s+behaviour',
        '(?i)([a-z]+|\d+)\s+of\s+its\s+(?:[a-z]+|\d+)\s+check\s+steps\s+test\s+behaviour',
        '(?i)(?:[a-z]+|\d+)\s+of\s+the\s+(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+tests\s+of\s+behaviour',
        '(?i)(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+behavioural\s+test\s+files?\s+surviv'
    )
}

# --- how many cases each suite runs ---------------------------------------
# For each suite, every mention of its file name opens a window that closes at
# the next suite's name or 240 characters, whichever is sooner. The FIRST
# quantity in that window, in any of the shapes below, is the claim being made
# about THAT suite. Windowing this way is what stops a run of suite names in
# one paragraph from swapping their numbers around.
#
# THE WINDOW IS 240 CHARACTERS AND IT STAYS THAT WAY. Widening it was tried
# and measured, not reasoned about; the numbers and the reason it was rejected
# are in this file's header under WHAT IT DOES NOT DO. A claim that sits
# further from the suite's name than this is NOT CHECKED, and there is at least
# one in the tree right now - docs/testing.md:176, measured in the header. At
# least one, not exactly one: a claim outside every window is by definition
# something this file never looks at, so nothing here can count them.
if ($suitesRan) {
    $anyName = ($suiteTallies.Keys | ForEach-Object { [regex]::Escape($_ + '.ps1') }) -join '|'
    # The (?<![\w.]) is load-bearing: without it `bin\lwg-setup.ps1 against a
    # throwaway tree` reads the `1` out of `.ps1` and reports the suite as
    # claiming one case. A quantity has to start at a word boundary that is not
    # a decimal point.
    #
    # ORDER MATTERS, AND THE BARE `N of M` IS LAST ON PURPOSE. .NET tries the
    # alternatives left to right at each start position, so at one position the
    # earlier branch wins. `79 of 79 cases` must be read by the cases branch and
    # `**79 of 79**` by the bolded one; a bare branch placed first would swallow
    # both and the rule would still be right by luck rather than by shape.
    #
    # The bare branch exists because two pages stated a tally with no marker on
    # it at all - `tests/gate_delegate.ps1 being 71 of 71 green` in docs/faq.md
    # and `It is 71 of 71 green` in docs/limitations.md - and both went unread
    # by every shape above while the suite reported 79. That is a stale number
    # in a tracked file that the guard whose whole job is stale numbers called
    # green. Note what it costs: `N of M` is the loosest shape here, so it is
    # the one most able to read some unrelated ratio that happens to fall
    # inside a window as a case count. Nothing in the tree does that today -
    # checked by running this file over every tracked page before and after
    # adding it, and the only two claims it newly read were the two above - but
    # it is the branch to suspect first if this rule ever flags something odd.
    #
    # THE TRAILING-COMMA SHAPE, AND WHY IT IS ANCHORED AT BOTH ENDS. A third
    # shape was found unread on 2 August 2026, and it is neither of the holes
    # this file's header had named until then: CONTRIBUTING.md:111,
    # `tests\stop_behaviour.ps1 ... # the two turn-end hooks, <count>`, named
    # the suite FILE correctly and sat 32 characters after it, well inside the
    # window - the rule simply had no shape for a count that trails a comma with
    # no noun after it. Its count had been stale since section E landed, and
    # adding this branch is what failed the tree over it. Three sibling lines in
    # the same code block carry the same shape and were already right, so this
    # is how that block annotates a suite invocation rather than a one-off.
    #
    # It is anchored on BOTH sides on purpose. The comma stops it reading a
    # count out of running prose, and the end-of-line lookahead stops it reading
    # the first number of a list ("..., 3 files and 2 dirs") or a date ("landed
    # on 31 July 2026, 8 days after"). `(?=\n|$)` rather than `(?m)$`: an inline
    # mode flag in .NET applies from where it appears to the end of the pattern,
    # so it would silently change the meaning of every branch written after it.
    # It also cannot race the branches above it whatever order they sit in -
    # every one of those starts at a digit and this one starts at a comma, so no
    # start position ever offers the engine both.
    $qtyPat  = '(?:\*\*(?<![\w.])(\d+)\s+of\s+\d+\*\*' +
               '|(?<![\w.])(\d+)\s+of\s+\d+\s+cases?\b' +
               '|(?<![\w.])(\d+)\s+cases?\b' +
               '|(?<![\w.])(\d+)\s+against\b' +
               '|,[ \t]*(?<![\w.])(\d+)[ \t]*(?=\n|$)' +
               '|(?<![\w.])(\d+)\s+of\s+\d+\b)'

    foreach ($base in ($suiteTallies.Keys | Sort-Object)) {
        $expected = $suiteTallies[$base]
        $namePat  = [regex]::Escape($base + '.ps1')
        foreach ($doc in $docs) {
            foreach ($nm in [regex]::Matches($doc.Text, $namePat)) {
                $from = $nm.Index + $nm.Length
                if ($from -ge $doc.Text.Length) { continue }
                $span = [Math]::Min(240, $doc.Text.Length - $from)
                $win  = $doc.Text.Substring($from, $span)
                $stop = [regex]::Match($win, $anyName)
                if ($stop.Success) { $win = $win.Substring(0, $stop.Index) }
                $q = [regex]::Match($win, $qtyPat)
                if (-not $q.Success) { continue }
                # ONE GROUP PER BRANCH OF $qtyPat, AND THE LIST HAS TO GROW WITH
                # IT. This was got wrong while adding the bare `N of M` branch:
                # the branch matched, its group 5 was never read, $tok came back
                # empty, ConvertTo-Quantity returned $null and the next line
                # skipped the claim. The run then reported the SAME 32 per-suite
                # claims and the same zero failures as before the change - a
                # green diff that looks like "no false positives introduced"
                # when in fact nothing had been introduced at all. If a branch
                # is ever added below, add its group here and check the CHECKED
                # COUNT moves, not just that the failure list is empty.
                $tok = @($q.Groups[1].Value, $q.Groups[2].Value, $q.Groups[3].Value,
                         $q.Groups[4].Value, $q.Groups[5].Value, $q.Groups[6].Value) |
                       Where-Object { $_ } | Select-Object -First 1
                $qty = ConvertTo-Quantity $tok
                $ln  = Get-LineNumber $doc ($from + $q.Index)
                # Both declines are RECORDED here for the same reason they are
                # in Test-Claim: a per-suite claim that was matched and then
                # dropped used to leave no trace at all, so a silenced stale
                # tally and a correct one produced identical output.
                if ($null -eq $qty) {
                    Add-Decline -Rule "cases:$base" -Kind 'no-quantity' -File $doc.Rel -Line $ln -Token $tok
                    continue
                }
                if ((Test-LineExempt $doc $ln) -or (Test-LineExempt $doc (Get-LineNumber $doc $nm.Index))) {
                    Add-Decline -Rule "cases:$base" -Kind 'line-exempt' -File $doc.Rel -Line $ln -Token ([string]$qty)
                    continue
                }
                $script:Checked++
                if ($qty -eq $expected) {
                    $script:Passes++
                    if ($ShowPasses) {
                        Say ("  [ok]   {0,-26} {1}:{2}  says {3}" -f "cases:$base", $doc.Rel, $ln, $qty)
                    }
                } else {
                    $script:Failures += [pscustomobject]@{
                        Rule = "cases:$base"; File = $doc.Rel; Line = $ln
                        Said = $qty; Expected = $expected
                        Source = "tests\$base.ps1 reported $expected of $expected"
                        Excerpt = (Get-Excerpt $doc $ln)
                    }
                    Say ("  [FAIL] {0,-26} {1}:{2}  says {3}, the suite reported {4}" -f "cases:$base", $doc.Rel, $ln, $qty, $expected)
                    Say ("         {0}" -f (Get-Excerpt $doc $ln))
                }
            }
        }
    }
}

# --- how many check steps CI runs -----------------------------------------
Test-Claim -Rule 'ci-check-steps' -Expected $ciSteps `
    -Source 'named steps carrying a run: block in .github/workflows/ci.yml' -Patterns @(
    '(?i)one\s+job\s+with\s+(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+check\s+steps',
    '(?i)one\s+job,\s+([A-Za-z]+|\d+)\s+check\s+steps',
    '(?i)of\s+its\s+([A-Za-z]+|\d+)\s+check\s+steps',
    '(?i)means\s+exactly\s+(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+things',
    '(?i)except\s+the\s+(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+(?:CI\s+)?check\s+steps\s+named\s+above',
    '(?i)runs\s+all\s+(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s*(?:of\s+them)?\s*[.,]'
)

# --- how many checks the doctor runs --------------------------------------
# THREE SHAPES ADDED ON 3 AUGUST 2026, AND WHAT THEY WERE MISSING.
# docs/commands.md - the reference the doctor's own slash command points the
# model at for what a row means - said "Eight" in three places and enumerated
# eight names while bin\lwg-doctor.ps1 ran nine. The check it omitted was
# `agent-roles`, which was on by default and whose FAIL was reachable -
# docs/uat-report.md records it being deliberately provoked - so the reference
# was missing a row a stranger could be shown. THAT CHECK HAS SINCE BEEN
# DELETED along with the verification_gate module it served, which is why the
# doctor derives EIGHT today; the shapes below are kept because they read live
# sentences about whatever the count now is, not because agent-roles still
# exists. None of the three sentences was read
# here: each states the count as a bare noun phrase rather than after "runs" or
# after the script's file name, which are the only two shapes this rule had.
#
# MEASURED, not reasoned about, in the way the per-suite note below insists on:
# this file was run with -ShowPasses over the tracked tree before and after, and
# the CHECKED count moved by exactly three - `Nine checks aimed at`,
# `Nine checks:` and `Two of the nine checks`, all in docs/commands.md, with no
# claim lost anywhere else.
#
# THE THIRD BRANCH IS THE LOOSE ONE and is the one to suspect first if this rule
# ever flags something odd: "of the N checks" carries no reference to the doctor
# and this file cannot know the subject of a sentence, so a page writing that
# phrase about CI steps or a suite's cases would be read here as a doctor claim.
# Nothing in the tree does today, by that same diff. The sentence it reads was
# reworded in the same change from "Two of the eight" to "Two of the nine
# checks" precisely so the noun is present rather than inherited from the
# preceding paragraph.
Test-Claim -Rule 'doctor-check-count' -Expected $doctorChecks `
    -Source 'bin\lwg-doctor.ps1 was run and its header read' -Patterns @(
    '(?i)\bruns\s+(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+checks\b',
    '(?i)lwg-doctor\.ps1\s+(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+checks\b',
    ('(?i)(?:\*\*)?(' + $script:NumWordPat + ')(?:\*\*)?\s+checks\s+aimed\s+at\b'),
    ('(?im)^\|?\s*(?:\*\*)?(' + $script:NumWordPat + ')(?:\*\*)?\s+checks:'),
    ('(?i)\bof\s+the\s+(?:\*\*)?(' + $script:NumWordPat + ')(?:\*\*)?\s+checks\b')
)

# --- how many slash commands ship -----------------------------------------
Test-Claim -Rule 'command-count' -Expected $commandFiles.Count `
    -Source 'git ls-files -- commands/*.md, present on disk' -Patterns @(
    '(?i)all\s+(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+(?:slash\s+)?commands\b',
    '(?i)(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+slash\s+commands\b',
    '(?i)\*\*([a-z]+|\d+)\s+commands:'
)

# --- how many modules there are, and how many only observe ----------------
Test-Claim -Rule 'module-total' -Expected $moduleTotal `
    -Source '$LwgModuleRegistry in lib/common.ps1' -Patterns @(
    '(?i)all\s+(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+declared\s+modules',
    '(?i)of\s+(?:its|the)\s+(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+modules\b',
    '(?i)(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+modules,\s+(?:[a-z]+|\d+)\s+of\s+them\s+active'
)

# Only phrasings that assert the TOTAL are read here. "The other three
# observing modules are exercised by nothing" is a statement about a SUBSET and
# is true at nine; a rule that flagged it would be teaching people to write
# vaguer sentences to get past a guard.
#
# THAT EXAMPLE READ "seven" UNTIL 3 AUGUST 2026 AND IT IS WORTH KNOWING WHY IT
# CHANGED, because the reason is a hole in this guard rather than a typo. The
# subset is not a count of modules, it is a count of modules NOTHING EXERCISES,
# and it went from seven to three the day tests\stop_behaviour.ps1 gained cases
# for context_pressure, docs_coupling, git_hygiene and log_rotation. TEN
# tracked files went on saying seven - nine of them pages or scripts, plus the
# example in this very comment, and one of the nine is a line bin\lwg-doctor.ps1
# PRINTS to the operator - and every suite here stayed green, because no rule
# in this file derives which modules a suite exercises. Deriving it means
# parsing assertions out of a suite to decide what they are about, which is a
# real mechanism and not one that should be invented in passing; it is left
# undone and named here instead. IT IS NOT THE ONLY UNCHECKED NUMBER, and the
# sentence here said it was until 3 August 2026: the five per-suite case counts
# in .github\PULL_REQUEST_TEMPLATE.md sit in PARENTHESES, which no pattern here
# reads, and that block carries the same warning in its own comment. What this
# file checks is every case count written in a shape it recognises, which is a
# smaller set than every case count in the tree.
#
# THE `only observe` BRANCH LOST FOUR CLAIMS OUT OF FIVE TO ITS OWN ALTERNATION.
# `([a-z]+|\d+)` matches whatever WORD precedes "only observe", so on the three
# pages that say "the nine that only observe" it captured `that`,
# ConvertTo-Quantity returned $null, and the claim was discarded above the
# CHECKED counter with nothing said. The number was sitting two words to the
# left the whole time. Adding `that` to the connector group is what reaches it.
# Measured at cc44c99: that branch was raw=5 kept=1; it is raw=5 kept=4 now.
# The fifth is docs\testing.md's table row "modules declared, and how many only
# observe", which states no quantity at all - it is a decline, not a claim, and
# it is now printed as one rather than vanishing.
Test-Claim -Rule 'observing-module-count' -Expected $moduleObserving `
    -Source '$LwgModuleRegistry entries of kind observe' -Patterns @(
    '(?i)of\s+the\s+(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+observing\b',
    # THE LOOKBEHIND IS WHAT THE PARAGRAPH ABOVE ALREADY PROMISED. This branch
    # read "Nine of the ten modules observe and can block nothing" as a claim
    # that TEN observe, because it captures whatever word sits immediately
    # before `modules` - so on 3 August 2026 it failed two sentences in
    # .github\ISSUE_TEMPLATE\ that state the SUBSET correctly and name the total
    # in the same breath. "N of the M" is exactly the subset shape this rule
    # says it does not read; without the lookbehind it was reading it, and the
    # only ways to clear it were to freeze a true sentence behind
    # doc-claims:ignore or to write a vaguer one. .NET allows a variable-length
    # lookbehind, so this needs no fixed-width dance.
    #
    # THE SECOND LOOKBEHIND IS THERE BECAUSE THE FIRST ONE LEAKED, and the leak
    # is a backtracking hole rather than a spelling mistake. Blocking a match at
    # `ten` does not stop the engine retrying one character to the right: `[a-z]+`
    # then captures `en`, the text before `en` is `of the t` rather than
    # `of the `, the lookbehind is satisfied, and the branch matched again with a
    # word FRAGMENT as its quantity. It cost nothing visible - `en` is not a
    # number word, so Test-Claim declined it instead of failing - but a guard
    # against stale numbers reporting `en` as a candidate quantity is the guard
    # misreading the tree, and a decline is not a check. `(?<![A-Za-z])` refuses
    # a start position with a letter in front of it, which is the property the
    # first lookbehind was assumed to have. It is NOT written as a leading `\b`:
    # the optional `**` means the character before the capture is often `*`, and
    # `\b` between a space and a `*` does not hold, so a `\b` would have dropped
    # every bold spelling this branch exists to read.
    #
    # MEASURED OVER EVERY TRACKED .md/.json/.yml/.ps1/.txt IN THIS TREE ON
    # 3 AUGUST 2026, since a pattern edit that kills a pattern ABORTS this suite
    # by the liveness rule above. Before: five matches - `Nine` in
    # .claude-plugin\marketplace.json and \plugin.json, and `en` in
    # .github\ISSUE_TEMPLATE\bug_report.yml, \config.yml and this file. After:
    # the same two `Nine` matches and nothing else. The branch still checks a
    # live claim, so it does not go dead, and the two declines it was producing
    # are gone. THE BASELINE FOR THAT IS THE PRE-FIX WORKING TREE, NOT fd8d023:
    # the lookbehind this corrects landed in the same wave, so no case written
    # against this defect can go red at a commit where the lookbehind is absent.
    '(?i)(?<!of\s+the\s+)(?<![A-Za-z])(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+modules\s+OBSERVE\b',
    '(?i)(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+(?:of\s+them\s+|that\s+)?only\s+observe\b'
)

Test-Claim -Rule 'gate-module-count' -Expected $moduleGates `
    -Source '$LwgModuleRegistry entries of kind gate' -Patterns @(
    # `is|are`, AND THE ALTERNATION IS THE WHOLE POINT OF THIS EDIT. This branch
    # required the literal `is`, and its only site in the tree was the pull
    # request template's "Exactly three modules in the registry IS `kind`" - so
    # correcting that verb to the grammatical `are` made the branch match
    # nothing anywhere and ABORTED the whole guard, which lane D3 measured on
    # 3 September 2026 by making exactly that edit and reverting it. The page
    # was then carrying an ungrammatical sentence to keep a guard alive, with an
    # HTML comment explaining why - a document shaped by a regex rather than the
    # other way round. Accepting both verbs costs nothing (the second branch
    # keys on `of kind \`gate\`` and does not reach this sentence, so there is
    # still exactly one hit) and lets the sentence read as English.
    '(?i)exactly\s+(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+modules?\s+in\s+the\s*\n?\s*registry\s+(?:is|are)\s+`?kind',
    '(?i)(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+modules?\s+(?:is|are)\s+of\s+kind\s+`gate`'
)

# --- the declared version ---------------------------------------------------
# These two do not go through Test-Claim, and the reason is its signature: it
# takes an [int]$Expected and matches a QUANTITY out of prose. A version is
# neither. Routing a string through an int comparison to reuse a function
# would be the sort of near-fit that this repository keeps finding inside
# itself, so the rule is written out - but it appends to the SAME
# $script:Failures in the SAME shape, so the report and the exit contract at
# the foot of this file are untouched.

# Rule one: every declaration agrees with every other. plugin.json is the
# reference because it is the manifest Claude Code itself reads; the others
# are echoes of it. This one CANNOT have caught the defect it was written
# for - all five sites read 0.3.0 together, in step and wrong - and it is here
# because the obvious way to fix that defect is to bump one site and miss four.
$versionRef = $versionSites[0]
foreach ($site in $versionSites) {
    if ($site.Rel -eq $versionRef.Rel) { continue }
    $script:Checked++
    if ($site.Value -eq $versionRef.Value) {
        $script:Passes++
        if ($ShowPasses) {
            Say ("  [ok]   {0,-26} {1}:{2}  says {3}" -f 'version-declarations-agree', $site.Rel, $site.Line, $site.Value)
        }
    } else {
        $script:Failures += [pscustomobject]@{
            Rule = 'version-declarations-agree'; File = $site.Rel; Line = $site.Line
            Said = $site.Value; Expected = $versionRef.Value
            Source = ("the version declared in {0}" -f $versionRef.Rel)
            Excerpt = (Get-Excerpt ([pscustomobject]@{ Lines = @(Get-Content -LiteralPath (Join-Path $script:RepoRoot ($site.Rel -replace '/', '\'))) }) $site.Line)
        }
        Say ("  [FAIL] {0,-26} {1}:{2}  says {3}, tree says {4}" -f 'version-declarations-agree', $site.Rel, $site.Line, $site.Value, $versionRef.Value)
    }
}

# Rule two: the declared version is not one a tag has already published. THIS
# is the rule the defect argues for. A tag is immutable and names a tested
# tree; the default branch is neither, and the documented install route
# resolves the default branch. While the two carry the same number, the
# version identifier cannot tell a consumer which of the two they are running,
# and on this project that is not cosmetic - `interaction.delegate: "false"`
# armed the gate at v0.3.0 and is ignored on main.
#
# Checked per SITE rather than once against the reference, deliberately: a
# half-finished bump that moved plugin.json and left config.json on the tag
# value is exactly the state this has to catch, and checking only the
# reference would call that tree clean.
if ($tagsKnown) {
    foreach ($site in $versionSites) {
        $script:Checked++
        # Both spellings, because nothing forces a tag to carry the `v`.
        $clash = @($publishedTags | Where-Object { $_ -eq $site.Value -or $_ -eq ('v' + $site.Value) })
        if ($clash.Count -eq 0) {
            $script:Passes++
            if ($ShowPasses) {
                Say ("  [ok]   {0,-26} {1}:{2}  says {3}" -f 'version-not-a-published-tag', $site.Rel, $site.Line, $site.Value)
            }
        } else {
            $script:Failures += [pscustomobject]@{
                Rule = 'version-not-a-published-tag'; File = $site.Rel; Line = $site.Line
                Said = $site.Value
                Expected = ("anything but {0} - that tag is published" -f ($clash -join ', '))
                Source = 'git tag -l'
                Excerpt = ("tag {0} already names a released tree; this branch is not that tree" -f ($clash -join ', '))
            }
            Say ("  [FAIL] {0,-26} {1}:{2}  declares {3}, which tag {4} already published" -f 'version-not-a-published-tag', $site.Rel, $site.Line, $site.Value, ($clash -join ', '))
        }
    }
}

# =========================================================================
# THE FOUR RULES THAT ARE NOT ABOUT QUANTITIES
# =========================================================================
# Each is written out for the same reason the two version rules above are:
# Test-Claim takes an [int]$Expected and matches a QUANTITY out of prose, and
# none of these is a quantity. They append to the SAME $script:Failures in the
# SAME shape, so the report and the exit contract at the foot are untouched.

function Add-LongFailure {
    param([string]$Rule, [string]$File, [int]$Line, [string]$Said, [string]$Expected, [string]$Source, [string]$Excerpt)
    $script:Failures += [pscustomobject]@{
        Rule = $Rule; File = $File; Line = $Line
        Said = $Said; Expected = $Expected; Source = $Source; Excerpt = $Excerpt
    }
    Say ("  [FAIL] {0,-26} {1}:{2}" -f $Rule, $File, $Line)
    Say ("         {0}" -f $Excerpt)
}

function Add-LongPass {
    param([string]$Rule, [string]$File, [int]$Line, [string]$Said)
    $script:Checked++
    $script:Passes++
    if ($ShowPasses) { Say ("  [ok]   {0,-26} {1}:{2}  {3}" -f $Rule, $File, $Line, $Said) }
}

# --- rule: every sibling suite prints RESULT: and EXIT: --------------------
# CONTRIBUTING.md's pre-PR checklist and .github\PULL_REQUEST_TEMPLATE.md both
# require a contributor to paste "the RESULT: and EXIT: lines from each" of the
# eight files in tests\. tests\uninstall_footprint.ps1 printed neither token,
# so the instruction could not be followed for one of the eight and the
# contributor had no way to tell a suite that omits them from a run of their
# own that went wrong. The likeliest outcomes were a PR with seven pastes and a
# note, or eight pastes one of which was invented - and pushing anybody toward
# reconstructing output is the wrong shape on a project whose rule is that an
# unverified thing must be said to be unverified.
#
# It is checked HERE rather than by a new suite because this file already runs
# every sibling in a child process and holds its stdout. Nothing else in the
# tree does, and adding a ninth file to tests\ to assert it would move the
# tests-file-count claim in six documents to check one string.
#
# WHAT IT DOES NOT COVER: this file's OWN output. doc_claims.ps1 is the eighth
# of the eight and it is the one doing the looking, so its two lines are held
# by reading the foot of this file and by nothing automatic. It also says
# nothing about whether the two lines are CORRECT - only that a suite emits
# them - and it cannot see a suite's exit-2 abort paths, because a suite that
# exits nonzero aborts this whole run several hundred lines above.
if ($suitesRan) {
    foreach ($base in ($suiteOutputs.Keys | Sort-Object)) {
        $rel = "tests/$base.ps1"
        $out = [string]$suiteOutputs[$base]
        $missingTokens = @()
        if ($out -notmatch '(?m)^\s*RESULT:') { $missingTokens += 'RESULT:' }
        if ($out -notmatch '(?m)^\s*EXIT:')   { $missingTokens += 'EXIT:' }
        if ($missingTokens.Count -eq 0) {
            Add-LongPass -Rule 'suite-output-contract' -File $rel -Line 0 -Said 'prints RESULT: and EXIT:'
        } else {
            $script:Checked++
            Add-LongFailure -Rule 'suite-output-contract' -File $rel -Line 0 `
                -Said ("printed no " + ($missingTokens -join ' and no ') + ' line') `
                -Expected 'a RESULT: line and an EXIT: line, the tokens the other suites print' `
                -Source 'the suite was run here and its stdout read' `
                -Excerpt ("CONTRIBUTING.md and .github/PULL_REQUEST_TEMPLATE.md both require the RESULT: and EXIT: lines from EACH file in tests\; this one emits no " + ($missingTokens -join ' and no '))
        }
    }
}

# --- rule: docs\testing.md names the CI job's check-run name verbatim -------
# A required status check on main is matched by the CHECK RUN's NAME, which for
# a job carrying a `name:` key is that display name and NOT the YAML job id.
# docs\testing.md's Branch protection section is the only page in the tree that
# tells a maintainer which contexts to require, and it named two job ids -
# `gate-regression` to remove and `fast-checks` to require. Neither has ever
# been a context on this repository. Following it to the letter removes nothing
# and adds a required context no run can ever satisfy, which leaves every pull
# request - including the one that would fix it - stuck at "Expected - Waiting
# for status to be reported" with no error to read.
#
# So the string is DERIVED from ci.yml and the page is required to quote it.
# ci.yml:110-115 already says "matched by this NAME" directly above the key;
# this is the half that holds the doc to it.
#
# WHAT IT DOES NOT COVER, and it is the bigger half: nothing here can see the
# LIVE branch-protection setting, and NOTHING IN THIS REPOSITORY DOES ANY MORE.
# checklist.json carried a P6-branch-protection probe that could not see it
# either - it asked whether a protection object exists, not which contexts it
# names - and that manifest has since been deleted, so the second half is not
# merely unchecked here, it is unchecked anywhere. A correctly quoted page and
# a correctly configured repository remain two separate claims and only the
# first is checked.
# EXACTLY ONE MATCH IS REQUIRED, and taking [0] would have been the near-fit.
# This workflow declares one job today. The day it declares two, a rule that
# silently reads the first would hold the page to one of two contexts and call
# the tree clean - and which contexts main requires is precisely the thing
# nothing here can see. Two jobs means two requirable names and a different
# paragraph, so this aborts and says so rather than checking half of it.
$ciJobNameMatches = @([regex]::Matches($ciText, '(?m)^  (?<id>[A-Za-z0-9_-]+):[ \t]*\r?\n[ \t]+name:[ \t]*(?<name>\S.*?)[ \t]*$'))
if ($ciJobNameMatches.Count -ne 1) {
    Abort ("expected exactly one job carrying a name: key in .github/workflows/ci.yml, found {0}, so the required check-run name was never derived. If a second job was added, docs/testing.md's Branch protection section has to name every requirable context and this rule has to read them all." -f $ciJobNameMatches.Count)
}
$ciJobNameMatch = $ciJobNameMatches[0]
$ciJobId   = $ciJobNameMatch.Groups['id'].Value
$ciJobName = $ciJobNameMatch.Groups['name'].Value
$bpRel  = 'docs/testing.md'
$bpDoc  = @($docs | Where-Object { $_.Rel -eq $bpRel })
if ($bpDoc.Count -ne 1) {
    Abort "expected exactly one $bpRel in the prose set, found $($bpDoc.Count), so the branch-protection paragraph was never read."
}
$bpHead = [regex]::Match($bpDoc[0].Text, '(?m)^#{2,4}\s+Branch\s+protection\s*$')
if (-not $bpHead.Success) {
    Abort "$bpRel has no 'Branch protection' heading, so the required check-run name could not be checked against it."
}
$bpFrom = $bpHead.Index
$bpNext = [regex]::Match($bpDoc[0].Text.Substring($bpFrom + $bpHead.Length), '(?m)^#{2,4}\s+\S')
$bpText = if ($bpNext.Success) { $bpDoc[0].Text.Substring($bpFrom, $bpHead.Length + $bpNext.Index) } else { $bpDoc[0].Text.Substring($bpFrom) }
$bpLine = Get-LineNumber $bpDoc[0] $bpFrom
if ($bpText.Contains($ciJobName)) {
    Add-LongPass -Rule 'branch-protection-context' -File $bpRel -Line $bpLine -Said "quotes '$ciJobName'"
} else {
    $script:Checked++
    Add-LongFailure -Rule 'branch-protection-context' -File $bpRel -Line $bpLine `
        -Said "the Branch protection section does not contain the string '$ciJobName'" `
        -Expected "the check-run name verbatim: $ciJobName" `
        -Source "the name: key of job '$ciJobId' in .github/workflows/ci.yml" `
        -Excerpt "a required status check is matched by the check run's NAME, not by the YAML job id '$ciJobId'; a rule naming the id blocks every merge"
}

# --- rule: the sibling-suite wait fits inside the CI job's own budget -------
# This file waits $SuiteTimeoutSec for the parallel sibling run and, on expiry,
# aborts with exit 2 and a diagnostic naming what did not finish. That abort is
# reachable only if the wait is shorter than the budget of the job it runs in.
# It was not: the default is 900 s and ci.yml caps the job at 10 minutes, so
# GitHub cancelled the job first - the step is marked cancelled rather than
# failed, `exit $code` is never reached, no ::error annotation is emitted and
# nothing is appended to the job summary. The build still went red, so the cost
# was the entire diagnostic rather than a wrong answer.
#
# The two numbers are in two files and nothing bound them, which is the defect
# this repository catalogues elsewhere. Binding them by passing the budget in
# on the command line was rejected as the whole fix for the reason the header
# gives about hardcoding: this rule reads BOTH numbers off the files and holds
# one to the other, so neither can move alone.
#
# WHAT IT DOES NOT COVER: a hang in any step OTHER than this one still cancels
# the job with no diagnostic. Per-step timeout-minutes is the general fix for
# that and is a separate change; this rule only makes THIS file's documented
# abort reachable.
$jobTimeoutMatch = [regex]::Match($ciText, '(?m)^\s+timeout-minutes:\s*(\d+)\s*$')
if (-not $jobTimeoutMatch.Success) {
    Abort 'no timeout-minutes: found in .github/workflows/ci.yml, so this suite''s wait was never held to the job budget.'
}
$jobBudgetSec = [int]$jobTimeoutMatch.Groups[1].Value * 60
$passedWait   = [regex]::Match($ciText, '-File\s+\$suite\s+-SuiteTimeoutSec\s+(\d+)')
$effectiveWait = if ($passedWait.Success) { [int]$passedWait.Groups[1].Value } else { $SuiteTimeoutSec }
$ciYmlRel      = '.github/workflows/ci.yml'
$waitLine      = (($ciText.Substring(0, $jobTimeoutMatch.Index) -split "`n").Count)
if ($effectiveWait -lt $jobBudgetSec) {
    Add-LongPass -Rule 'doc-claims-suite-budget' -File $ciYmlRel -Line $waitLine -Said "wait ${effectiveWait}s < budget ${jobBudgetSec}s"
} else {
    $script:Checked++
    Add-LongFailure -Rule 'doc-claims-suite-budget' -File $ciYmlRel -Line $waitLine `
        -Said "the Documentation claims step gives this suite a ${effectiveWait}s sibling-suite wait" `
        -Expected "strictly less than the job's own ${jobBudgetSec}s budget" `
        -Source 'timeout-minutes in ci.yml, against -SuiteTimeoutSec on the Documentation claims step (or this suite''s default when none is passed)' `
        -Excerpt 'the job cap wins, so the documented exit-2 abort cannot fire in CI: GitHub cancels the job and no diagnostic is printed at all'
}

# --- rule: no page says the doctor is outside CI ---------------------------
# docs\faq.md told the reader, parenthetically and as the REASON to run a check
# by hand, that the doctor is not run by CI. It is: this file runs
# bin\lwg-doctor.ps1 on every invocation and ABORTS with exit 2 if it cannot
# read the header, and ci.yml runs this file as one of its check steps. So a
# doctor that stops printing its header takes the build red, and a reader who
# believes otherwise will not connect a red Documentation claims step to a
# broken doctor.
#
# This is the one rule here with no quantity and no derived string - it is a
# forbidden phrasing. Both halves of the fact it rests on are re-derived from
# the tree above rather than assumed, and if either stops being true the rule
# must go rather than the sentence.
#
# WHAT IT DOES NOT COVER: the phrasings it knows, which are the two in the tree
# plus the obvious variants. It is not a natural-language checker, exactly like
# every quantity rule above. And the ADVICE the FAQ gives is still right for a
# different reason - CI runs the doctor against this repository's tree, which
# says nothing about the reader's install - so this rule refuses the false
# justification, not the recommendation.
$doctorInCi = ($ciText -match 'doc_claims\.ps1')
if (-not $doctorInCi) {
    Abort '.github/workflows/ci.yml does not run tests\doc_claims.ps1, so "the doctor is run by CI" could not be derived and no page was held to it.'
}
$notInCiPat = '(?i)\bdoctor\s+(?:is\s+)?(?:not|never)\s+run\s+by\s+CI\b'
foreach ($doc in $docs) {
    foreach ($m in [regex]::Matches($doc.Text, $notInCiPat)) {
        $ln = Get-LineNumber $doc $m.Index
        if (Test-LineExempt $doc $ln) {
            Add-Decline -Rule 'doctor-is-run-by-ci' -Kind 'line-exempt' -File $doc.Rel -Line $ln -Token $m.Value
            continue
        }
        $script:Checked++
        Add-LongFailure -Rule 'doctor-is-run-by-ci' -File $doc.Rel -Line $ln `
            -Said $m.Value `
            -Expected 'no such claim - tests\doc_claims.ps1 runs bin\lwg-doctor.ps1 and ci.yml runs that' `
            -Source 'ci.yml runs tests\doc_claims.ps1, which runs the doctor and aborts if its header will not parse' `
            -Excerpt (Get-Excerpt $doc $ln)
    }
}
# The absence of a forbidden phrasing is a real observation, so it is counted
# rather than left silent - otherwise this rule contributes nothing to the
# CHECKED total on a clean tree and is indistinguishable from a rule that was
# never run.
if (-not ($script:Failures | Where-Object { $_.Rule -eq 'doctor-is-run-by-ci' })) {
    Add-LongPass -Rule 'doctor-is-run-by-ci' -File $ciYmlRel -Line 0 -Said 'no tracked page says the doctor is outside CI'
}

# =========================================================================
# THE FRONT-DOOR RULES
# =========================================================================
# Twelve more non-quantity rules, all of them about what a STRANGER reads: the
# public front page, the contributor path, the security channel, the two
# marketplace manifests, and the strings bin\ prints at an operator. They are
# here for the same reason the four above are - this is the only suite in
# tests\ whose own tally no tracked file quotes, so it is the only one that can
# grow a case without moving a number in nine documents, four of which belong
# to other people. That is a fact about coupling, not a claim that a docs guard
# is the natural home for "is this label real".
#
# THEY NEED A WIDER FILE SET THAN $docs. $docs is .md/.json/.yml only, on the
# stated principle that "a .ps1 is checked by the parse step and by its own
# suite". That principle holds for CODE and fails for the STRINGS code prints:
# four sentences under bin\ went on promising a status-line segment deleted on
# 30 July 2026, and no suite reaches any of them. So these rules build their
# own enumeration and $docs is left exactly as it was - widening it globally
# would hand every quantity rule above a file set nobody measured them against.
#
# SELF-EXEMPTION, and it is a real hole. tests\doc_claims.ps1 must contain the
# patterns these rules look for, so it excludes itself from the wide set. That
# is the same problem tests\portability_scan.ps1 solves with region markers,
# solved here more bluntly because this file is a guard rather than a surface
# anybody reads. A GM promise or a forbidden phrasing written INTO this file
# would not be caught by it.
$script:WideSelf = 'tests/doc_claims.ps1'
$wideFiles = @($tracked | Where-Object {
    $_ -match '\.(ps1|md|json|ya?ml|txt)$' -and $_ -ne $script:WideSelf
})
if ($wideFiles.Count -eq 0) {
    Abort 'the wide file enumeration returned nothing - the front-door rules were NOT run, which is not the same as passing.'
}
$wide = @()
$wideSkipped = @()
foreach ($rel in $wideFiles) {
    $full = Join-Path $script:RepoRoot ($rel -replace '/', '\')
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
    $lines = @(Get-Content -LiteralPath $full)
    $text  = ($lines -join "`n")
    # The SAME two markers the quantity rules honour, and for the same reason:
    # CHANGELOG.md is a record end to end, and a line that quotes what an
    # operator was once shown is a record too. Correcting either would be
    # falsifying it. A marker is a claim - "this is frozen on purpose" - and it
    # is declined loudly at the foot of this file, never silently.
    if ($text -match '<!--[^>]*doc-claims:ignore-file') { $wideSkipped += $rel; continue }
    $wide += [pscustomobject]@{ Rel = $rel; Lines = $lines; Text = $text }
}
if ($wide.Count -eq 0) {
    Abort 'every file in the wide set was exempted by doc-claims:ignore-file - that is not a pass.'
}

function Get-WideDoc {
    param([string]$Rel)
    $hit = @($wide | Where-Object { $_.Rel -eq $Rel })
    if ($hit.Count -ne 1) { return $null }
    return $hit[0]
}

# Every forbidden-phrasing rule below shares this shape, so it is written once.
#
# IT PUBLISHES ITS COUNT ON $script:ForbiddenHits AND RETURNS NOTHING, for the
# reason written out above Test-Claim: Say is Write-Output, so a function that
# PRINTS and also returns a value hands the caller its whole output stream. The
# first draft of this helper ended `return $hits`, and the caller's `$fbHits++`
# died with "The '++' operator works only on numbers. The operand is a
# 'System.Object[]'" - after every [FAIL] line it had printed went into the
# variable instead of onto the console. That is the same defect this file
# already carries a paragraph about, reproduced by someone who had read the
# paragraph, which is why the rule is repeated here at the second site.
function Test-ForbiddenPhrasing {
    param(
        [string]$Rule, [string]$Pattern, [string]$Expected, [string]$Source,
        [object[]]$Set
    )
    $script:ForbiddenHits = 0
    foreach ($doc in $Set) {
        foreach ($m in [regex]::Matches($doc.Text, $Pattern)) {
            $ln = Get-LineNumber $doc $m.Index
            if (Test-LineExempt $doc $ln) {
                Add-Decline -Rule $Rule -Kind 'line-exempt' -File $doc.Rel -Line $ln -Token $m.Value
                continue
            }
            $script:ForbiddenHits++
            $script:Checked++
            Add-LongFailure -Rule $Rule -File $doc.Rel -Line $ln `
                -Said $m.Value -Expected $Expected -Source $Source `
                -Excerpt (Get-Excerpt $doc $ln)
        }
    }
}

# --- rule: nothing promises the GM status-line segment ----------------------
# GM rendered this plugin's own governance state until 30 July 2026, when it
# was deleted along with the per-session trip ledger that was its only input.
# Seven documents recorded the removal correctly that day. Program output did
# not: bin\lwg-setup.ps1's section blurb, bin\lwg-doctor.ps1's statusline FAIL
# detail, bin\lwg-uninstall.ps1's footprint row and bin\lwg-update.ps1's INFO
# row all went on naming it, so a stranger was told at first install, at first
# fault and at first update that a segment they can never see is supposed to be
# there - and docs\install.md, the page they would check, agreed. The FAQ
# inverts it: there, GM's PRESENCE is the sign of a stale copy.
#
# THE PRECONDITION IS DERIVED, NOT ASSUMED. If the segment ever comes back this
# rule must stop firing on its own rather than have to be remembered, so the
# renderer is read for a GmSeg-shaped function AND for an assembly line that
# emits one. Either is enough to stand the rule down.
$slRel  = "$($script:PayloadRel)/statusline/statusline.ps1"
$slFull = Join-Path $script:RepoRoot ($slRel -replace '/', '\')
if (-not (Test-Path -LiteralPath $slFull -PathType Leaf)) {
    Abort "$slRel is missing, so whether the GM segment still exists could not be derived and no surface was held to its absence."
}
$slText = ((Get-Content -LiteralPath $slFull) -join "`n")
$gmDefined = ($slText -match '(?m)^\s*function\s+Gm(?:Seg|State|Trips)\b')
$gmEmitted = ($slText -match '(?m)^\s*\$out\s*\+=\s*Gm(?:Seg|State)\b')
if ($gmDefined -or $gmEmitted) {
    Add-LongPass -Rule 'gm-segment-removed' -File $slRel -Line 0 `
        -Said 'the renderer defines or emits a GM segment again, so nothing is held to its absence'
} else {
    # The pair, not either name alone. `GM` on its own appears in every page
    # that records the removal and in the tombstone comment in the renderer,
    # and those sentences are right. What is wrong is naming the two segments
    # TOGETHER as a thing that renders - "HH/GM", "HH and GM", "`HH` and `GM`" -
    # which is the shape all six live sites used and the shape no correct
    # sentence in this tree uses.
    Test-ForbiddenPhrasing -Rule 'gm-segment-removed' `
        -Pattern '`?HH`?\s*(?:/|and)\s*`?GM`?' `
        -Expected 'the HH segment alone - GM was deleted on 30 July 2026 with the trip ledger it read' `
        -Source "$slRel defines no GmSeg/GmState/GmTrips and emits no GM segment" `
        -Set $wide
    if ($script:ForbiddenHits -eq 0) {
        Add-LongPass -Rule 'gm-segment-removed' -File $slRel -Line 0 `
            -Said 'no tracked surface names an HH/GM segment pair'
    }
}

# --- rule: .gitignore covers the credential file classes --------------------
# This one is a BOOLEAN and it is here for the coupling reason at the top of
# this section, not because a documentation guard is where an ignore file
# belongs. It earns its place by being the only automatic check between a
# contributor's working copy and a public commit: GitHub secret scanning and
# push protection are both off and are not settable while this repository is
# private, and the secret_scan module that used to inspect writes was removed
# on 30 July 2026.
#
# THE PROBE LIST IS WRITTEN OUT AND THAT IS A HARDCODED LIST. The header of
# this file argues against hardcoding, and the argument there is specific: a
# number this guard carries is a ninth place for a number the tree already
# states to be wrong.
#
# THE JUSTIFICATION THAT USED TO SIT HERE HAS EXPIRED, AND IT IS RECORDED
# RATHER THAN QUIETLY REPLACED. It read: '"What a credential file is named" is
# stated NOWHERE in the tree - the fixture that held it,
# tests\fixtures\deny_canonical.txt, was deleted with tests\deny_parity.ps1 on
# 30 July 2026 - so there is no second place for this to disagree with.' That
# was true until 3 August 2026, when the fixture was restored to the tree from
# ef993bc as the subject of a case in tests\uninstall_footprint.ps1. It names
# credential file classes - *.pem, *.key, id_rsa*, id_dsa*, id_ecdsa*,
# id_ed25519*, .env and three variants, .npmrc, hosts.yml, .credentials.json -
# so there IS a second place now, and the list below is no longer alone.
#
# THE THREE LISTS DO NOT AGREE, AND NOTHING HERE MAKES THEM. Measured on
# 3 August 2026: the fixture names id_dsa*, id_ecdsa* and hosts.yml, none of
# which .gitignore ignores and none of which this list probes; .gitignore
# ignores *.pfx and *.p12, which the fixture does not name. This rule was NOT
# widened to close that, and the reason is not tidiness: the fixture is a
# RECORD of what a removed gate refused, restored so a deletion case has
# something to read, and promoting a record to a specification would make an
# ignore rule appear because a historical artefact was restored. hosts.yml in
# particular is an ordinary enough name that ignoring it would hide a
# legitimately tracked file, which is the trap .gitignore's own comment warns
# about for secrets.json and creds.txt. So this stays one hand-written list;
# what has changed is that it can now be WRONG relative to something else in
# the tree, and no check will say so.
#
# WHAT IT DOES NOT COVER: file CLASSES only. A token pasted into a tracked .md,
# or a credential inside a .json that is not *.local.json, walks past both the
# ignore file and this rule. `secrets.json` and `creds.txt` are deliberately
# still trackable and are named in .gitignore's own comment as such.
$credProbes = @(
    '.env', '.env.local', 'key.pem', 'server.key', 'cert.pfx', 'cert.p12',
    'id_rsa', 'id_ed25519', 'x.credentials.json', '.npmrc'
)
$credNotIgnored = @()
foreach ($probe in $credProbes) {
    Push-Location -LiteralPath $script:RepoRoot
    try {
        $null = & git check-ignore -q -- $probe 2>$null
        $code = $LASTEXITCODE
    } finally { Pop-Location }
    # 0 ignored, 1 not ignored, anything else is git failing rather than
    # answering - and an unanswered probe must never read as a pass.
    if ($code -eq 1)      { $credNotIgnored += $probe }
    elseif ($code -ne 0)  { Abort "git check-ignore exited $code on '$probe'; the credential classes were NOT checked." }
}
if ($credNotIgnored.Count -eq 0) {
    Add-LongPass -Rule 'credential-classes-ignored' -File '.gitignore' -Line 0 `
        -Said ("all {0} credential file class(es) are ignored" -f $credProbes.Count)
} else {
    $script:Checked++
    Add-LongFailure -Rule 'credential-classes-ignored' -File '.gitignore' -Line 0 `
        -Said ("git check-ignore says these are TRACKABLE: " + ($credNotIgnored -join ', ')) `
        -Expected 'every one of them ignored' `
        -Source 'git check-ignore -q, run once per class from the repo root' `
        -Excerpt 'secret scanning and push protection are both off on this repository, so .gitignore is the only layer between a contributor working copy and a public commit'
}

# --- rule: every issue form declares a label this repository documents -------
# GitHub applies the labels a form declares that EXIST and silently drops the
# ones that do not. There is no error, the submission succeeds, and the issue
# arrives unlabelled - outside the very triage query the label was invented
# for. .github\ISSUE_TEMPLATE\security.yml declared `security-process` from the
# day it was written; that label has never existed on this repository or on its
# predecessor, so every submission through the one form built to be triaged
# differently arrived looking like any other issue.
#
# WHAT THIS IS: two TRACKED DECLARATIONS held to each other, exactly like
# version-declarations-agree above, which compares five sites and asks no
# outside authority which of them is right. The roster is CONTRIBUTING.md's
# label table.
#
# WHAT IT IS NOT, and this is the whole limit: it does not call GitHub. No
# suite here uses the network or a credential, so nothing local can tell you a
# label on that table still exists on the repository. Keeping the table true is
# one `gh label list` and is a person's job. A form declaring a label that is on
# the table and gone from GitHub fails silently exactly as before.
$labelRosterRel = 'CONTRIBUTING.md'
$labelRosterDoc = Get-WideDoc $labelRosterRel
if ($null -eq $labelRosterDoc) {
    Abort "$labelRosterRel is not in the wide set, so the label roster was never read."
}
$rosterHead = [regex]::Match($labelRosterDoc.Text, '(?m)^#{2,4}\s+The\s+labels\s+this\s+repository\s+defines\s*$')
if (-not $rosterHead.Success) {
    Abort "$labelRosterRel has no 'The labels this repository defines' heading, so no issue form was held to a roster."
}
$rosterFrom = $rosterHead.Index + $rosterHead.Length
$rosterNext = [regex]::Match($labelRosterDoc.Text.Substring($rosterFrom), '(?m)^#{1,4}\s+\S')
$rosterText = if ($rosterNext.Success) { $labelRosterDoc.Text.Substring($rosterFrom, $rosterNext.Index) } else { $labelRosterDoc.Text.Substring($rosterFrom) }
$roster = @()
foreach ($row in ($rosterText -split "`n")) {
    if ($row -notmatch '^\s*\|') { continue }
    foreach ($tok in [regex]::Matches($row, '`([^`]+)`')) { $roster += $tok.Groups[1].Value }
}
$roster = @($roster | Sort-Object -Unique)
if ($roster.Count -eq 0) {
    Abort "the label table in $labelRosterRel yielded no label names, so no issue form was held to it."
}
$formRels = @($tracked | Where-Object {
    $_ -match '^\.github/ISSUE_TEMPLATE/.+\.ya?ml$' -and $_ -notmatch '/config\.ya?ml$'
})
if ($formRels.Count -eq 0) {
    Abort 'no issue forms were found under .github/ISSUE_TEMPLATE/, so their labels were NOT checked.'
}
foreach ($rel in $formRels) {
    $formDoc = Get-WideDoc $rel
    if ($null -eq $formDoc) { continue }
    $lm = [regex]::Match($formDoc.Text, '(?m)^\s*labels:\s*\[(?<list>[^\]]*)\]')
    if (-not $lm.Success) {
        # A form declaring NO label is a decision, not a defect - it is the
        # bug template's business whether it wants one - so this is not a
        # failure. It is not a silent skip either.
        Add-Decline -Rule 'issue-template-label-declared' -Kind 'no-quantity' -File $rel -Line 1 -Token 'no labels: key'
        continue
    }
    $ln = Get-LineNumber $formDoc $lm.Index
    foreach ($raw in ($lm.Groups['list'].Value -split ',')) {
        $lbl = $raw.Trim().Trim('"').Trim("'").Trim()
        if ([string]::IsNullOrWhiteSpace($lbl)) { continue }
        if ($roster -contains $lbl) {
            Add-LongPass -Rule 'issue-template-label-declared' -File $rel -Line $ln -Said "declares '$lbl'"
        } else {
            $script:Checked++
            Add-LongFailure -Rule 'issue-template-label-declared' -File $rel -Line $ln `
                -Said "declares the label '$lbl'" `
                -Expected ("one of the labels documented in ${labelRosterRel}: " + ($roster -join ', ')) `
                -Source "the label table under 'The labels this repository defines' in $labelRosterRel" `
                -Excerpt "GitHub silently applies none of a label it cannot resolve, so every submission through this form arrives unlabelled and outside the triage query written to find it"
        }
    }
}

# --- rule: the security fallback names a form that exists -------------------
# SECURITY.md and the security form both told a reporter who could not reach
# private vulnerability reporting to "open a public issue containing only the
# words ...". That route did not exist. blank_issues_enabled is false in the
# same directory, so GitHub's New issue page offers only the declared forms,
# and each of those required ticking a box a vulnerability reporter would have
# been asserting falsely. With private vulnerability reporting off - which is
# repository configuration, and returns 404 for everyone when it is - that
# fallback is not an edge case, it is the ENTIRE reporting path.
#
# Two halves, both derived from the tree: the forbidden instruction, and the
# requirement that the sentence offering a fallback names a form that is
# actually declared in .github\ISSUE_TEMPLATE\.
#
# WHAT IT DOES NOT COVER: whether the named form is one a reporter can honestly
# complete. That is a property of the words on its required checkboxes and no
# pattern can read it - it is the reason this defect existed with three forms
# already declared. It is held by review.
#
# The trigger is the HAND-OFF phrasing this tree uses, "that page/tab is not
# available to you", and like every phrasing rule in this file it is escapable
# by writing the same instruction a different way. The forbidden half below is
# the tighter of the two for exactly that reason: it names the shape of the
# route that does not exist rather than the shape of the sentence offering it.
$itCfgRel  = '.github/ISSUE_TEMPLATE/config.yml'
$itCfgDoc  = Get-WideDoc $itCfgRel
if ($null -eq $itCfgDoc) {
    Abort "$itCfgRel is not in the wide set, so whether blank issues are disabled was never derived."
}
$blankOff = ($itCfgDoc.Text -match '(?m)^\s*blank_issues_enabled:\s*false\b')
if (-not $blankOff) {
    # Blank issues re-enabled makes "open a public issue" a real instruction
    # again. The rule stands itself down rather than being remembered.
    Add-LongPass -Rule 'security-fallback-names-a-form' -File $itCfgRel -Line 1 `
        -Said 'blank issues are enabled, so a bare "open a public issue" is a route that exists'
} else {
    $formNames = @($formRels | ForEach-Object { Split-Path $_ -Leaf })
    Test-ForbiddenPhrasing -Rule 'security-fallback-names-a-form' `
        -Pattern '(?i)open\s+a\s+public\s+issue\s+containing' `
        -Expected 'a named issue form - blank issues are disabled, so there is no public issue to open' `
        -Source "blank_issues_enabled: false in $itCfgRel" `
        -Set $wide
    # The positive half. Every sentence that hands a reporter a fallback has to
    # name the form it is handing them.
    $trigPat = '(?i)(?:page|tab)\s+is\s+not\s+available\s+to\s+you'
    $trigSeen = 0
    foreach ($doc in $wide) {
        foreach ($m in [regex]::Matches($doc.Text, $trigPat)) {
            $ln = Get-LineNumber $doc $m.Index
            if (Test-LineExempt $doc $ln) {
                Add-Decline -Rule 'security-fallback-names-a-form' -Kind 'line-exempt' -File $doc.Rel -Line $ln -Token $m.Value
                continue
            }
            $trigSeen++
            $from = $m.Index + $m.Length
            $span = [Math]::Min(700, $doc.Text.Length - $from)
            $win  = if ($span -gt 0) { $doc.Text.Substring($from, $span) } else { '' }
            $named = @($formNames | Where-Object { $win.Contains($_) })
            if ($named.Count -gt 0) {
                Add-LongPass -Rule 'security-fallback-names-a-form' -File $doc.Rel -Line $ln -Said ("names " + ($named -join ', '))
            } else {
                $script:ForbiddenHits++
                $script:Checked++
                Add-LongFailure -Rule 'security-fallback-names-a-form' -File $doc.Rel -Line $ln `
                    -Said 'offers a fallback and names no issue form' `
                    -Expected ('one of: ' + ($formNames -join ', ')) `
                    -Source "blank_issues_enabled: false in $itCfgRel, and the forms declared beside it" `
                    -Excerpt (Get-Excerpt $doc $ln)
            }
        }
    }
    if ($script:ForbiddenHits -eq 0 -and $trigSeen -eq 0) {
        Add-LongPass -Rule 'security-fallback-names-a-form' -File $itCfgRel -Line 1 `
            -Said 'no page offers a fallback route at all'
    }
}

# --- rule: a junction command creates its own parent directory --------------
# `mklink /J` does not create the parent, and ~\.claude\skills does not exist on
# a machine that has never installed a skill - which is exactly a first-time
# contributor. The failure is "The system cannot find the path specified.",
# which names the mklink call rather than the missing folder, so it reads as a
# permissions problem and is not one. docs\install.md has carried the New-Item
# line and a comment explaining this since the junction route was written;
# CONTRIBUTING.md restated the block as a subset and dropped exactly that line,
# on the page whose whole job is to be followed by somebody who has never run
# any of this before.
$mkPat = '(?i)mklink\s+/J\s+"?\$env:USERPROFILE\\\.claude\\skills'
$mkSeen = 0
foreach ($doc in $wide) {
    foreach ($m in [regex]::Matches($doc.Text, $mkPat)) {
        $ln = Get-LineNumber $doc $m.Index
        if (Test-LineExempt $doc $ln) {
            Add-Decline -Rule 'junction-creates-its-parent' -Kind 'line-exempt' -File $doc.Rel -Line $ln -Token 'mklink /J'
            continue
        }
        $mkSeen++
        $script:Checked++
        $start  = [Math]::Max(0, $m.Index - 900)
        $before = $doc.Text.Substring($start, $m.Index - $start)
        if ($before -match '(?i)New-Item[^\r\n]*\$env:USERPROFILE\\\.claude\\skills') {
            $script:Passes++
            if ($ShowPasses) { Say ("  [ok]   {0,-26} {1}:{2}  creates the parent first" -f 'junction-creates-its-parent', $doc.Rel, $ln) }
        } else {
            Add-LongFailure -Rule 'junction-creates-its-parent' -File $doc.Rel -Line $ln `
                -Said 'links into ~\.claude\skills without creating it' `
                -Expected 'a New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.claude\skills" above it, the line docs/install.md carries' `
                -Source 'mklink /J does not create the parent; the error it prints names the link, not the folder' `
                -Excerpt (Get-Excerpt $doc $ln)
        }
    }
}
if ($mkSeen -eq 0) {
    Add-LongPass -Rule 'junction-creates-its-parent' -File 'CONTRIBUTING.md' -Line 0 -Said 'no page documents a junction install'
}

# --- rule: the contributor path names the fork step -------------------------
# The documented flow ended at "open a PR", which an outside contributor cannot
# do: the collaborator list is one account, so a branch cloned straight from
# upstream has nowhere to go. There was no sentence anywhere in the repository
# telling them to fork - `grep -in fork CONTRIBUTING.md README.md` returned
# nothing - and the step they cannot take is the LAST one, so the cost lands
# after the whole contribution is written and the suites have been run.
#
# WHAT IT DOES NOT COVER: it checks that the word is on the page near the
# instruction, not that the fork instructions are correct or complete. A
# presence assertion is the weakest shape in this file and it is used here
# because the alternative - no check at all - is how this got shipped.
$contribDoc = Get-WideDoc 'CONTRIBUTING.md'
if ($null -eq $contribDoc) {
    Abort 'CONTRIBUTING.md is not in the wide set, so the contributor path was never read.'
}
# `\bPRs?\b` as well as the spelled-out form, because the guide said "PR"
# fourteen times and "pull request" not once - the first shape of this rule
# looked only for the long form, found nothing, and took its own no-PR-asked-for
# pass branch on a page whose entire last section is about opening one.
if ($contribDoc.Text -match '(?i)\bpull requests?\b|\bPRs?\b') {
    $script:Checked++
    if ($contribDoc.Text -match '(?i)\bfork\b') {
        $script:Passes++
        if ($ShowPasses) { Say ("  [ok]   {0,-26} {1}  names the fork step" -f 'contributor-path-names-the-fork', 'CONTRIBUTING.md') }
    } else {
        Add-LongFailure -Rule 'contributor-path-names-the-fork' -File 'CONTRIBUTING.md' -Line 0 `
            -Said 'asks for a pull request and never mentions forking' `
            -Expected 'a fork step, since an outside contributor cannot push a branch to this repository' `
            -Source 'the guide instructs opening a pull request' `
            -Excerpt 'the step they cannot take is the last one, so the cost lands after the whole contribution is written'
    }
} else {
    Add-LongPass -Rule 'contributor-path-names-the-fork' -File 'CONTRIBUTING.md' -Line 0 `
        -Said 'the guide does not ask for a pull request, so no fork step is owed'
}

# --- rule: ci.yml's own invariants are repeated in CONTRIBUTING.md ----------
# ci.yml marks its two invariants with the word DELIBERATELY, at the point of
# edit, and CONTRIBUTING.md's checklist explicitly invites a contributor to
# edit that file. A comment is read only by somebody already on the line it
# sits on, and both consequences land somewhere else: a path filter on
# pull_request makes the required status check NEVER REPORT, so every PR waits
# forever on a check that cannot arrive; and renaming the job's display name
# silently stops satisfying a required context, which goes GREEN while the
# protection stops applying.
#
# Both halves are derived from ci.yml rather than typed here - the display name
# comes from $ciJobName, which the branch-protection rule above already read
# out of the YAML.
#
# WHAT IT DOES NOT COVER: it checks that the guide NAMES each invariant, not
# that what it says about it is right. And the third coupling - one broken
# sibling suite producing two red CI steps, because this file exits 2 when any
# of them exits nonzero - is documented in CONTRIBUTING.md and checked by
# nothing, here or anywhere.
#
# IT ABORTS RATHER THAN GOING QUIET IF THE MARKERS MOVE. Both halves below are
# conditioned on ci.yml carrying the marker they key on, so rewording either
# comment would have made this rule contribute no pass, no fail and no decline -
# the only rule in this file able to disappear from the CHECKED total without
# leaving a trace. Every other rule here emits a countable pass on its clean
# path, including the ones that stand themselves down. This one now aborts, and
# 2 rather than 1 because a marker that moved means the tree was not checked
# rather than that it is dirty.
if ($ciText -notmatch 'DELIBERATELY NO PATH FILTER' -or $ciText -notmatch 'DELIBERATELY UNCHANGED') {
    Abort ('.github/workflows/ci.yml no longer carries both of the DELIBERATELY markers this rule ' +
           'keys on, so CONTRIBUTING.md was held to neither CI invariant. Repoint the rule at the ' +
           'new wording, or delete it and say the invariant is gone - do not leave it silent.')
}
if ($ciText -match 'DELIBERATELY NO PATH FILTER') {
    $script:Checked++
    if ($contribDoc.Text -match '(?i)path filter') {
        $script:Passes++
        if ($ShowPasses) { Say ("  [ok]   {0,-26} {1}  names the path-filter invariant" -f 'ci-invariants-documented', 'CONTRIBUTING.md') }
    } else {
        Add-LongFailure -Rule 'ci-invariants-documented' -File 'CONTRIBUTING.md' -Line 0 `
            -Said 'never mentions the path-filter invariant' `
            -Expected 'the invariant ci.yml marks DELIBERATELY, stated on the page that invites editing ci.yml' `
            -Source '.github/workflows/ci.yml: "THERE IS DELIBERATELY NO PATH FILTER HERE, AND ADDING ONE IS A REGRESSION"' `
            -Excerpt 'a path filter on pull_request makes the required check never report, so every PR waits forever'
    }
}
if ($ciText -match 'DELIBERATELY UNCHANGED') {
    $script:Checked++
    if ($contribDoc.Text.Contains($ciJobName)) {
        $script:Passes++
        if ($ShowPasses) { Say ("  [ok]   {0,-26} {1}  quotes '{2}'" -f 'ci-invariants-documented', 'CONTRIBUTING.md', $ciJobName) }
    } else {
        Add-LongFailure -Rule 'ci-invariants-documented' -File 'CONTRIBUTING.md' -Line 0 `
            -Said "does not quote the check-run name '$ciJobName'" `
            -Expected "the display name verbatim, so a contributor can see what a rename would break" `
            -Source "the name: key of job '$ciJobId' in .github/workflows/ci.yml, marked DELIBERATELY UNCHANGED" `
            -Excerpt 'a required status check is matched by this NAME; renaming it goes green while the protection stops applying'
    }
}

# --- rule: both manifests state the platform --------------------------------
# The two manifest descriptions are the first and often the only text a
# stranger reads before /plugin install, and neither said Windows or named the
# interpreter. Every registration in hooks\hooks.json is the literal string
# `powershell`, which does not exist on macOS or Linux, so a marketplace user
# on either has no signal at manifest level and no chance to avoid it.
#
# THE PRECONDITION IS DERIVED: if the registrations ever stop naming
# powershell, the platform claim stops being owed and this rule stands down.
$hooksRel  = "$($script:PayloadRel)/hooks/hooks.json"
$hooksFull = Join-Path $script:RepoRoot ($hooksRel -replace '/', '\')
if (-not (Test-Path -LiteralPath $hooksFull -PathType Leaf)) {
    Abort "$hooksRel is missing, so the platform requirement could not be derived."
}
$hooksText = (Get-Content -LiteralPath $hooksFull -Raw)
$cmdAll = @([regex]::Matches($hooksText, '"command"\s*:\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
if ($cmdAll.Count -eq 0) {
    Abort "$hooksRel declares no hook command, so the platform requirement could not be derived."
}
$cmdPs = @($cmdAll | Where-Object { $_ -eq 'powershell' })
if ($cmdPs.Count -ne $cmdAll.Count) {
    Add-LongPass -Rule 'manifest-states-the-platform' -File $hooksRel -Line 0 `
        -Said ("{0} of {1} registrations name powershell, so no manifest is held to a Windows-only claim" -f $cmdPs.Count, $cmdAll.Count)
} else {
    foreach ($pair in @(
        # THE FIRST MOVED AND THE SECOND DID NOT, and both Rels are looked up in
        # $wide, which is built from `git ls-files` - so each must be spelled
        # exactly as git prints it. Prefixing marketplace.json here would make
        # Get-WideDoc return $null and Abort this suite on a green tree; leaving
        # plugin.json unprefixed does the same in the other direction.
        @{ Rel = "$($script:PayloadRel)/.claude-plugin/plugin.json"; Pat = '"description"\s*:\s*"([^"]+)"' },
        @{ Rel = '.claude-plugin/marketplace.json';                 Pat = '"name"\s*:\s*"lw-[^"]+"\s*,\s*\r?\n?\s*"description"\s*:\s*"([^"]+)"' }
    )) {
        $mDoc = Get-WideDoc $pair.Rel
        if ($null -eq $mDoc) { Abort ("{0} is not in the wide set, so its description was never read." -f $pair.Rel) }
        $dm = [regex]::Match($mDoc.Text, $pair.Pat)
        if (-not $dm.Success) { Abort ("no plugin description was found in {0}, so the platform claim was NOT checked." -f $pair.Rel) }
        $desc = $dm.Groups[1].Value
        $ln   = Get-LineNumber $mDoc $dm.Index
        $script:Checked++
        if ($desc -match '(?i)windows' -and $desc -match '(?i)powershell\s*5\.1') {
            $script:Passes++
            if ($ShowPasses) { Say ("  [ok]   {0,-26} {1}:{2}  states the platform" -f 'manifest-states-the-platform', $pair.Rel, $ln) }
        } else {
            Add-LongFailure -Rule 'manifest-states-the-platform' -File $pair.Rel -Line $ln `
                -Said 'the description names neither Windows nor PowerShell 5.1' `
                -Expected 'both, in the first clause - a marketplace card truncates and this is the sentence that must survive it' `
                -Source ("all {0} registrations in {1} name the binary powershell" -f $cmdAll.Count, $hooksRel) `
                -Excerpt 'a macOS or Linux user reads this description, installs, and every hook command fails to resolve'
        }
    }
}

# --- rule: "pwsh is not a substitute" says what the constraint actually is ---
# README.md and docs\install.md both said PowerShell 7 "is not a substitute",
# phrased as a statement about the CODE. It is a statement about the hook
# REGISTRATIONS. Every tracked script declares `#requires -version 5`, which
# PowerShell 7 satisfies, so a reader who tries it finds it works - and then
# discounts the next warning the documentation gives them, which on this tree
# includes several that are load-bearing.
#
# WHAT IT DOES NOT COVER, and it is worth being blunt: this rule is satisfied
# by DELETING the phrase as readily as by qualifying it, so a green run does
# not mean the platform requirement is stated well. It means no page makes the
# specific overstatement that was made.
$reqMax = 0
foreach ($rel in @($tracked | Where-Object { $_ -match ('^' + [regex]::Escape($script:PayloadRel) + '/(bin|lib|statusline)/.+\.ps1$') })) {
    $full = Join-Path $script:RepoRoot ($rel -replace '/', '\')
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
    foreach ($rm in [regex]::Matches(((Get-Content -LiteralPath $full -TotalCount 5) -join "`n"), '(?im)^#requires\s+-version\s+(\d+(?:\.\d+)?)')) {
        $v = [double]$rm.Groups[1].Value
        if ($v -gt $reqMax) { $reqMax = $v }
    }
}
if ($reqMax -eq 0) {
    Abort 'no #requires -version line was found under bin/, lib/ or statusline/, so what the scripts actually demand was never derived.'
}
if ($reqMax -ge 5.1) {
    Add-LongPass -Rule 'pwsh-claim-names-the-constraint' -File 'docs/install.md' -Line 0 `
        -Said ("a tracked script requires -version {0}, so 'not a substitute' is a true statement about the code" -f $reqMax)
} else {
    $subHits = 0
    foreach ($doc in $wide) {
        # `not\**` and not a bare `not`: docs\install.md wrote it as "is **not**
        # a substitute" and the first shape of this pattern walked straight past
        # the bolded form while catching the plain one in README.md. Two pages
        # making the same claim, one read and one not, is the shape of miss this
        # file's header spends four screens on.
        foreach ($m in [regex]::Matches($doc.Text, '(?i)\bnot\**\s+a\s+substitute')) {
            $ln = Get-LineNumber $doc $m.Index
            $start = [Math]::Max(0, $m.Index - 400)
            $span  = [Math]::Min(400, $doc.Text.Length - $m.Index)
            $win   = $doc.Text.Substring($start, ($m.Index - $start) + $span)
            if ($win -notmatch '(?i)\bpwsh\b|PowerShell\s*7') { continue }
            if (Test-LineExempt $doc $ln) {
                Add-Decline -Rule 'pwsh-claim-names-the-constraint' -Kind 'line-exempt' -File $doc.Rel -Line $ln -Token $m.Value
                continue
            }
            $script:Checked++
            # WHAT COUNTS AS NAMING THE CONSTRAINT, measured rather than guessed.
            # The first shape of this rule accepted `#requires` alone and failed
            # two sentences that are RIGHT - docs\faq.md and docs\testing.md both
            # say pwsh is not a substitute and both go straight on to say the
            # real reason, "needs a binary literally named powershell". A guard
            # that fails a correct sentence teaches people to write vaguer ones,
            # which is the argument this file's header makes against widening
            # the quantity window. So the naming forms in the tree are accepted
            # and nothing looser: "different binary" is NOT one of them, because
            # that is the phrasing the two overstating sentences already used.
            if ($win -match '(?i)#requires|literally named|hook registrations') {
                $script:Passes++
                if ($ShowPasses) { Say ("  [ok]   {0,-26} {1}:{2}  names the constraint" -f 'pwsh-claim-names-the-constraint', $doc.Rel, $ln) }
            } else {
                $subHits++
                Add-LongFailure -Rule 'pwsh-claim-names-the-constraint' -File $doc.Rel -Line $ln `
                    -Said 'says pwsh is not a substitute without saying what the constraint is' `
                    -Expected ("that the constraint is the literal binary name in the hook registrations - every tracked script declares #requires -version {0}, which PowerShell 7 satisfies" -f $reqMax) `
                    -Source 'the #requires lines under bin/, lib/ and statusline/, read here' `
                    -Excerpt (Get-Excerpt $doc $ln)
            }
        }
    }
    if ($subHits -eq 0) {
        Add-LongPass -Rule 'pwsh-claim-names-the-constraint' -File 'README.md' -Line 0 `
            -Said 'no page claims pwsh is not a substitute without naming the real constraint'
    }
}

# --- rule: the README summarises CONTRIBUTING's rule list correctly ---------
# The README's contributing paragraph is written to be the WHOLE briefing for
# somebody who will not read further. It named "the two rules that fail the
# build", listed two, and one of the two was rule 1 - which CONTRIBUTING.md
# says in bold that nothing enforces. The rule it omitted was the workflow
# guard, the one CONTRIBUTING.md singles out as having its failure mode on
# SOMEBODY ELSE'S MACHINE: a self-hosted runner reachable from a public
# repository hands a stranger code execution on the maintainer's hardware.
#
# The count is DERIVED from CONTRIBUTING.md's own numbered list rather than
# from its prose, so the two pages cannot drift apart silently again.
#
# WHAT IT DOES NOT COVER: the count only. Whether the README lists the RIGHT
# three, and whether it gets each one's enforcement right, is held by review.
$contribHead = $contribDoc.Text
$firstSub = [regex]::Match($contribHead, '(?m)^#{3}\s+\S')
if ($firstSub.Success) { $contribHead = $contribHead.Substring(0, $firstSub.Index) }
$ruleCount = @([regex]::Matches($contribHead, '(?m)^\d+\.\s+\[')).Count
if ($ruleCount -eq 0) {
    Abort 'CONTRIBUTING.md opens with no numbered rule list, so the README summary was held to nothing.'
}
$readmeDoc = Get-WideDoc 'README.md'
if ($null -eq $readmeDoc) { Abort 'README.md is not in the wide set, so its rule summary was never read.' }
# EVERY MATCH, NOT THE FIRST. The first shape of this rule took
# [regex]::Match and got README.md's "the old rules" - the sentence about
# permissions.deny rules a pre-30-July machine still carries - which captured
# 'old', failed ConvertTo-Quantity, and was DECLINED. The rule then checked
# nothing at all while looking exactly like a rule that had run, which is the
# failure this whole file exists to catch, reproduced inside it. So every match
# is offered and the first one carrying an actual quantity is the claim.
$rsm = $null
foreach ($cand in [regex]::Matches($readmeDoc.Text, '(?i)\bthe\s+(?:\*\*)?([a-z]+|\d+)(?:\*\*)?\s+rules\b')) {
    if ($null -ne (ConvertTo-Quantity $cand.Groups[1].Value)) { $rsm = $cand; break }
    Add-Decline -Rule 'readme-rule-count' -Kind 'no-quantity' -File 'README.md' `
        -Line (Get-LineNumber $readmeDoc $cand.Index) -Token $cand.Groups[1].Value
}
if ($null -eq $rsm) {
    $script:Checked++
    Add-LongFailure -Rule 'readme-rule-count' -File 'README.md' -Line 0 `
        -Said 'no "the N rules" summary was found' `
        -Expected ("a summary naming CONTRIBUTING.md's {0} rules" -f $ruleCount) `
        -Source "the numbered list at the top of CONTRIBUTING.md" `
        -Excerpt 'the README paragraph is the whole briefing for a contributor who will not read further'
} else {
    $ln  = Get-LineNumber $readmeDoc $rsm.Index
    # Non-null by construction - the loop above only keeps a match that parses.
    $qty = ConvertTo-Quantity $rsm.Groups[1].Value
    if (Test-LineExempt $readmeDoc $ln) {
        Add-Decline -Rule 'readme-rule-count' -Kind 'line-exempt' -File 'README.md' -Line $ln -Token $rsm.Groups[1].Value
    } else {
        $script:Checked++
        if ($qty -eq $ruleCount) {
            $script:Passes++
            if ($ShowPasses) { Say ("  [ok]   {0,-26} {1}:{2}  says {3}" -f 'readme-rule-count', 'README.md', $ln, $qty) }
        } else {
            Add-LongFailure -Rule 'readme-rule-count' -File 'README.md' -Line $ln `
                -Said "$qty" `
                -Expected "$ruleCount" `
                -Source 'the numbered list at the top of CONTRIBUTING.md' `
                -Excerpt (Get-Excerpt $readmeDoc $ln)
        }
    }
}

# --- rule: no page cites an issue in a repository nobody can open -----------
# docs\architecture.md asked a reader to accept a lesson on the authority of
# "issue #700 in a private sibling project". An outside reader cannot open it,
# cannot verify the claim it supports, and cannot tell what the lesson was
# beyond the one sentence - and the citation discloses that a private sibling
# project exists under the same owner and that its issue numbering reaches
# ~700, which is the same business-existence disclosure the tree is otherwise
# working to remove. The lesson stands on its own without the number.
Test-ForbiddenPhrasing -Rule 'no-unresolvable-citation' `
    -Pattern '(?i)issue\s+#\d+\s+in\s+a\s+private' `
    -Expected 'the lesson without the identifier - no reader outside that repository can open it' `
    -Source 'the citation names a repository this reader has no access to' `
    -Set $wide
if ($script:ForbiddenHits -eq 0) {
    Add-LongPass -Rule 'no-unresolvable-citation' -File 'docs/architecture.md' -Line 0 `
        -Said 'no page cites an issue in a private repository'
}

# --- rule: no page denies that a test suite exists --------------------------
# .github\ISSUE_TEMPLATE\config.yml told every reader of the issue chooser
# "There is no test suite." Eight files in tests\ say otherwise, and the pull
# request template in the same directory requires output from all eight - the
# chooser page and the PR template are rendered to the same person minutes
# apart. It was a leftover from 30 July 2026, when both gates were deleted and
# the portability scan was briefly the only thing left.
#
# A flat denial states no quantity, so every quantity rule above is blind to
# it by construction. That is the hole this closes, and it closes it for one
# phrasing rather than for the class.
if ($testFiles.Count -gt 0) {
    Test-ForbiddenPhrasing -Rule 'no-page-denies-the-suite' `
        -Pattern '(?i)there\s+(?:is|are)\s+no\s+test(?:\s+suite|s)\b|\bno\s+test\s+suite\s+(?:exists|at\s+all)\b' `
        -Expected ("the {0} files in tests/, five of which test behaviour" -f $testFiles.Count) `
        -Source 'git ls-files -- tests/*.ps1' `
        -Set $wide
    if ($script:ForbiddenHits -eq 0) {
        Add-LongPass -Rule 'no-page-denies-the-suite' -File '.github/ISSUE_TEMPLATE/config.yml' -Line 0 `
            -Said 'no tracked page denies that a test suite exists'
    }
}

# --- rule: every page the website publishes is indexed by docs/README.md ----
# #183. GITHUB PAGES SERVES EVERY FILE UNDER docs/ TO THE OPEN WEB, from `main`
# at path `/docs`, and a classic branch source has no exclusion mechanism - the
# only choices are `/` and `/docs`. So "what is published" is exactly "what is
# in that directory", and five internal pages were live on the public web
# because nothing connected the two facts: a feasibility spike with a negative
# verdict, a page whose second line read "Status: not built.", a v0.3.0
# acceptance record, an unimplemented hosting plan, and a design specification
# carrying an operational account of a session incident.
#
# WHAT THIS RULE REFUSES TO BE, and the refusal is the design. #183's fourth
# done-condition asks for "something that checks whatever the site publishes
# stays consumer-facing". The only mechanically checkable form of THAT is a
# hardcoded list of the pages judged internal - which is the exact defect
# tests\payload_guard.ps1 exists to prevent, and which goes green the day
# somebody adds a sixth. Whether a page is consumer-facing is a judgement, and
# no rule here can make it.
#
# WHAT IT IS INSTEAD. docs/README.md is the index the site's front door renders.
# A page nobody chose to index is a page nobody decided to publish, and that is
# checkable: "is it indexed?" stands in for "was publishing it a decision?".
# Every one of the five was unindexed or was indexed only after the fact; the
# fifth, harness-hosting-plan.md, was linked from nothing at all, which is how
# it went unnoticed by an issue that enumerated four.
#
# ONE DIRECTION ONLY, AND THE OTHER HALF IS NAMED RATHER THAN LEFT OUT. This
# checks that every page present is indexed. It does NOT check the converse -
# that the index links nothing absent - because the index carries rows for the
# pages that just left docs/, and correcting those rows is a document edit this
# pass is not permitted to make. Those four dangling rows are #195's, they are
# recorded on that issue verbatim, and until they are removed a reader of the
# index is offered four links that 404. That is a real gap and it is stated
# here rather than implied by a green line.
#
# MATCHED ON THE LINK TARGET, not on the file name appearing anywhere. A page
# mentioned in a sentence is not indexed; a page reachable from the front door
# is. The pattern accepts the bare name and a ./ prefix, which are the two
# forms a same-directory link takes.
$idxRel  = 'docs/README.md'
$idxDoc  = Get-WideDoc $idxRel
if ($null -eq $idxDoc) {
    Abort "$idxRel is not in the wide set, so no published page was checked for being indexed."
}
$idxPages = @($tracked | Where-Object { $_ -match '^docs/.+\.md$' -and $_ -ne $idxRel -and (Test-StillOnDisk $_) })
if ($idxPages.Count -eq 0) {
    Abort 'no tracked page under docs/ was found, so the index rule established nothing about what the website publishes.'
}
$idxMissing = @()
foreach ($rel in $idxPages) {
    $leaf = $rel.Substring('docs/'.Length)
    if ($idxDoc.Text -notmatch ('\]\(\s*(?:\./)?' + [regex]::Escape($leaf) + '\s*(?:#[^)]*)?\)')) {
        $idxMissing += $leaf
    }
}
# ONE CHECK PER PAGE, not one for the rule. The first draft incremented
# $script:Checked once and then emitted a failure per unindexed page, so three
# internal notes landing at once would have read as one checked claim and three
# disagreements - a denominator that does not match its own numerator, in the
# file whose subject is exactly that.
$script:Checked += $idxPages.Count
if ($idxMissing.Count -eq 0) {
    $script:Passes += $idxPages.Count
    if ($ShowPasses) { Say ("  [ok]   {0,-26} {1}  all {2} published page(s) indexed" -f 'docs-index-is-complete', $idxRel, $idxPages.Count) }
} else {
    $script:Passes += ($idxPages.Count - $idxMissing.Count)
    foreach ($leaf in $idxMissing) {
        Add-LongFailure -Rule 'docs-index-is-complete' -File $idxRel -Line 0 `
            -Said "does not link docs/$leaf" `
            -Expected 'a row for it, or the page moved out of docs/ - GitHub Pages publishes this directory whole and an unindexed page is one nobody decided to publish' `
            -Source ("git ls-files -- docs/*.md found {0} page(s) beside this index" -f $idxPages.Count) `
            -Excerpt "https://leapware-software.github.io/LEAPWare-Watchtower/$($leaf -replace '\.md$', '.html') is live to the open web and is reachable from no index. Internal notes go to .github/notes/, which neither the payload nor Pages reads."
    }
}

# =========================================================================
# RESULT
# =========================================================================
Say ''
Say '==========================================================================='
Say ("scanned {0} tracked prose file(s); {1} exempted whole by doc-claims:ignore-file" -f $docs.Count, $skippedWhole.Count)
foreach ($s in $skippedWhole) { Say ("    exempt: {0}" -f $s) }

# The line-level counterpart of the file-level list directly above. Printed on
# EVERY path including a green one, and named with file:line, because that
# asymmetry - file exemptions announced, line exemptions silent - is what made
# a silenced stale number byte-indistinguishable from a correct one.
Say ("declined {0} matched claim(s) without checking them" -f $script:Declines.Count)
foreach ($d in ($script:Declines | Sort-Object File, Line)) {
    if ($d.Kind -eq 'line-exempt') {
        Say ("    declined: {0}:{1}  {2}  doc-claims:ignore on or above this line (said {3})" -f $d.File, $d.Line, $d.Rule, $d.Token)
    } else {
        Say ("    declined: {0}:{1}  {2}  the pattern captured '{3}', which is not a quantity" -f $d.File, $d.Line, $d.Rule, $d.Token)
    }
}
Say ("RESULT: {0} of {1} recognised claim(s) agree with the tree" -f $script:Passes, $script:Checked)

# Said on EVERY path, pass or fail, because the one thing it must never do is
# be absent from a green run. See the derivation for why an empty tag list is
# not the same observation as no tag existing. This is a REAL HOLE and it is
# named rather than papered over: on the CI runner, which checks out at depth
# 1 with no tags, version-not-a-published-tag does not run at all, so CI cannot
# catch a release that reuses a published version. The rule is stated for
# people in CONTRIBUTING.md's release section, and this guard catches it for
# anyone running from an ordinary clone - which includes the release pass
# itself, where it matters.
if (-not $tagsKnown) {
    Say ''
    Say 'NOT CHECKED: version-not-a-published-tag. No tag ref is visible here, and'
    Say '  `git tag -l` printing nothing is not evidence that nothing was tagged.'
    Say '  The declared version was compared against no tag at all.'
}

if ($script:Checked -eq 0) {
    Abort 'not one recognised claim was found in the whole tree. The patterns are broken, not the docs.'
}

# A PATTERN THAT CHECKED NOTHING IS AN ABORT. The zero-check above is on the
# GRAND TOTAL, and reaching zero requires every rule in the file to go blind at
# once; one pattern going dead moves it by a few claims and trips nothing. Seven
# of thirty-seven were dead at cc44c99 and one of them was provably a phrasing
# that HAD been read and stopped being - see the header. This is the per-pattern
# form of the same rule ci.yml states for the whole file: a pattern set that
# matches nothing is broken, not clean.
#
# Exit 2 rather than 1 on purpose. A dead pattern means "the claims were NOT
# checked", not "a claim disagrees", and ci.yml already renders 2 with the right
# words. -SkipSuites cannot reach here: it exits 2 further down, and the rules
# that depend on a suite tally are not invoked at all under it, so their
# patterns are never entered in the ledger and cannot be reported dead.
$deadPatterns = @($script:PatternLedger | Where-Object { $_.Hits -eq 0 })
$script:DeadRules = @(
    $script:PatternLedger | Group-Object Rule |
        Where-Object { ($_.Group | Measure-Object -Property Hits -Sum).Sum -eq 0 } |
        ForEach-Object { $_.Name }
)
if ($deadPatterns.Count -gt 0) {
    Say ''
    Say ("ABORT: {0} of {1} pattern(s) checked no claim anywhere in the tree." -f $deadPatterns.Count, $script:PatternLedger.Count)
    foreach ($p in $deadPatterns) {
        Say ("    dead: {0} #{1}   {2}" -f $p.Rule, $p.Index, $p.Pattern)
    }
    if ($script:DeadRules.Count -gt 0) {
        Say ("  {0} whole rule(s) went blind: {1}" -f $script:DeadRules.Count, ($script:DeadRules -join ', '))
    }
    Say 'A pattern set that matches nothing is broken, not clean. Either the phrasing it'
    Say 'keys on was reworded - repoint the pattern - or the claim is gone from every page,'
    Say 'in which case DELETE the pattern and say so. Do not allowlist it and do not soften'
    Say 'this to a warning: a warning in a green log is an unrun check reading as a passed one.'
    Say 'Nothing about the documentation was established by this run.'
    Say 'EXIT: 2'
    exit 2
}

if ($script:Failures.Count -gt 0) {
    Say ''
    Say 'CLAIMS THAT DISAGREE WITH THE TREE:'
    foreach ($f in $script:Failures) {
        Say ("  {0}:{1}" -f $f.File, $f.Line)
        Say ("    rule     {0}" -f $f.Rule)
        Say ("    says     {0}" -f $f.Said)
        Say ("    tree     {0}   ({1})" -f $f.Expected, $f.Source)
        Say ("    line     {0}" -f $f.Excerpt)
    }
    Say ''
    Say 'Fix the SENTENCE, not this guard. If the sentence is a record of what was'
    Say 'true on a date, mark that line doc-claims:ignore and leave the number alone.'
    Say 'EXIT: 1'
    exit 1
}

if (-not $suitesRan) {
    Say ''
    Say 'Every claim this run looked at agrees with the tree, BUT -SkipSuites was'
    Say 'passed, so the behavioural-suite count and every per-suite case count were'
    Say 'NOT CHECKED. That is not a pass, and it exits 2 so it cannot be read as one.'
    Say 'EXIT: 2'
    exit 2
}

Say ''
Say 'Every recognised claim agrees with the tree. Read that as "no phrasing this'
Say 'guard knows about is stale", NOT as "every number in the docs is right" - the'
Say 'header lists what it cannot see.'
Say 'EXIT: 0'
exit 0
