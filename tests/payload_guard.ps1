#requires -version 5
<#
  LW-WATCHTOWER payload disclosure guard.

      powershell -NoProfile -ExecutionPolicy Bypass -File tests\payload_guard.ps1

  WHY THIS FILE EXISTS

  `.claude-plugin/marketplace.json` declares `"source": "./lw-watchtower"`. That
  is a BOUNDARY rather than a wildcard: the CLI copies only that subtree into a
  consumer's plugin cache, so `lw-watchtower/` IS the shipped payload and the
  rest of this repository - `docs/`, `tests/`, `.github/`, the root
  community-health files - reaches nobody.

  It was not always so. `"source": "./"` had no exclusion mechanism at all, so
  every tracked file in the repository was payload, and the `checklist` command
  rendered one of them on a consumer's machine - `commands/checklist.md`
  instructed the model to print the output verbatim, so whatever the maintainer's
  release manifest carried reached a stranger's screen. That command and that
  manifest were both deleted in 0.4.0 and the payload boundary was drawn in the
  same release. The rules below stay anyway: they are what would notice any of it
  coming back, and the disclosures they name are the ones this project has
  actually made.

  THIS GUARD DOES NOT TAKE THE BOUNDARY ON TRUST. It parses the marketplace
  manifest on every run and ABORTS when the declared `source` and the subtree it
  scanned have drifted apart. A guard that scanned the wrong set would report a
  clean payload it never opened, which is the failure this file is named for.
  The exemption-marker sweep still covers EVERY tracked file, because the one
  file permitted to declare an exempt region is this one, and this one is
  outside the payload.

  Four disclosures reached the payload that way and none of them was caught by
  anything, because every guard in tests\ answers a different question:

    * tests\portability_scan.ps1 asks whether a tracked file names one MACHINE.
      A pull ref, a commit SHA and a release-plan heading are portable. They
      pass it.
    * tests\doc_claims.ps1 derives COUNTED QUANTITIES and holds prose to them.
      A containment claim resting on the repository not being published yet
      carries no number, so it is not a claim that file can read at all.
    * tests\portability_scan.ps1's own scope stops at the payload subtree, so a
      disclosure written into a page under docs/ is outside every rule it has.
      (A third suite, tests\evidence_states.ps1, used to be named here. It was
      deleted with the evidence engine; the sentence is kept only to say so.)

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
       time, for the reason a guard that spells the string it forbids IS the
       disclosure. The evidence renderer that used the same transformation was
       deleted with the checklist manifest, so this file is the last place the
       mechanism lives and it is described here rather than by reference. See
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
    6. A DELETED SCRIPT, NAMED AS LIVE BY A SHIPPED FILE. Not a privacy
       disclosure like the five above, and it is here rather than in a suite of
       its own for the reason this file exists at all: it is a property of what
       a STRANGER RECEIVES, and every other guard in tests\ answers a different
       question. A consumer's model reads a shipped page or a maintainer reads
       a shipped comment, follows it to a script that is not in the payload,
       and the failure is silent in both directions - the invocation fails, or
       the reader reasons from a mechanism that does not exist. Wave 1 deleted
       the state resolver, its library half, its command and the marker the
       clearing mechanism turned on, and eleven tracked sites went on naming
       them. See DETECTION RULES and, immediately after them, HISTORICAL
       MENTIONS - naming a deleted thing AND SAYING IT IS DELETED is the
       opposite of this defect, and the two are told apart one line at a time
       rather than one file at a time.
    7. A ROLE ALLOWLIST NAMING A TOOL THE MODEL DOES NOT HAVE. The same shape as
       item 6 and here for the same reason: a shipped file asserting that
       something exists which does not. A role's `tools:` frontmatter is
       validated against nothing - an entry naming a tool the session does not
       carry is simply never matched, and nothing reports it - so the role
       advertises a capability it cannot have while a model reads that list as
       a statement of what it may do. Measured 2026-09-05: agents\lw-orchestrator.md
       named four Task tools that do not exist on the model it declares. The
       obvious guard was `claude plugin validate --strict`, and it was PROBED
       rather than assumed: it passes with those four restored, and it passes
       with a tool named NotARealToolXyz. It does not read tool names at all.
       Anchored to the `tools:` line, so a file may still record which tools it
       removed and why - the same distinction HISTORICAL MENTIONS draws for
       item 6, free here because an allowlist is exactly one line.

  HOW IT WORKS

  TWO ENUMERATIONS, AND THE SPLIT IS THE WHOLE OF THIS FILE'S CORRECTNESS.

    * The DETECTION RULES run over `git ls-files -- lw-watchtower/`, which is
      what a consumer receives. Run over the whole tree they would report
      `THE SHIPPED PAYLOAD DISCLOSES` about a file in docs/ that no consumer
      ever sees - a false accusation on a guard whose entire worth is that a
      failure means something.
    * The REGION-MARKER SWEEP runs over the FULL `git ls-files`, because the one
      file allowed to declare an exempt region is this one and this one is not
      in the payload. Narrowed to the payload, both marker cases would evaluate
      over a set that cannot contain their owner and would pass trivially: the
      exemption channel, unguarded, reported green.

  Neither list is ever hardcoded - a hardcoded list is the defect this guard
  exists to prevent, and it is exactly how the payload boundary was lost in the
  first place: `"source": "./"` was a wildcard nobody enumerated.

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
# $Root stays the REPOSITORY root: the marker sweep needs the whole tracked tree
# and this file, its owner, is outside the payload. The payload subtree is named
# relatively and checked against the manifest before anything is scanned.
$script:RepoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = $script:RepoRoot }
$script:PayloadRel = 'lw-watchtower'

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
# memory at match time and never written to output. The form was borrowed from
# the checklist manifest's `stdout_not_match`, and the transformation from the
# evidence renderer's Expand-LwgRptLiteral - BOTH OF WHICH ARE DELETED. Neither
# is a dependency and neither ever was; the helper below is this file's own, and
# the borrowing is recorded because a reader who finds the shape familiar should
# know where it came from rather than go looking for a caller that is not there.
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
        why     = 'rendered on a consumer machine, a phase of the maintainer''s go-public plan reads as a phase of the consumer''s own work. The `checklist` command that rendered it and the manifest it rendered were BOTH deleted in 0.4.0 and neither is in the tracked tree, so this rule has no live target: it is a sentinel against re-introduction, and it is kept for that and said so rather than left reading as a live finding.'
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
        # SCOPED TO THE SHIPPED PAYLOAD, AND commands/ AND agents/ ARE IN IT
        # AGAIN. They were omitted while wave D was in flight, for a reason
        # written here at the time: #192's done-condition says "no SHIPPED file"
        # and the whole payload ships, but commands/update.md still named the
        # deleted library and a fixer may not edit a document. Including the
        # directory then would have made CI permanently red on a file nobody was
        # allowed to touch, which is a guard that has to be switched off to be
        # merged, which is not a guard. The same comment named its own trigger -
        # re-enable the moment #195 lands - and #195 has landed: the four terms
        # return no live hit anywhere under commands/ or agents/, checked before
        # this glob was added rather than after.
        #
        # THESE TWO ARE THE SURFACE THE ISSUE WAS FILED ABOUT. It was
        # agents/lw-healer.md telling a shipped role to run a script that is not
        # in the payload; a model reads these files and acts on them, which makes
        # them the higher-risk half of the payload rather than the leftover half.
        # A guard that watched everything except the thing it was written for is
        # the shape this repository keeps finding inside itself.
        #
        # tests/ stays out, for a different reason: it ships like everything else
        # under the payload declaration, but its remaining sites are assertion
        # prose recorded on #192 rather than ledger'd here, and lane C8 retensed
        # them - so the omission is now a scope decision rather than a debt.
        # Repo-relative, because that is what `git ls-files` prints on both
        # enumerations. The payload prefix is spelled here rather than derived
        # because $script:PayloadRel is checked against the manifest before any
        # of this runs - see S8 - so a wrong name aborts loudly instead of
        # switching nine globs off in silence.
        #
        # output-styles/ JOINED THEM ON 6 SEPTEMBER 2026 (#316), for the reason
        # the paragraph above gives about commands/ and agents/ rather than for
        # a new one: a style is text a model reads and acts on, and it goes into
        # the MAIN thread's system prompt, which makes it the same surface this
        # rule was written for. skills/ JOINED THEM THE SAME DAY (#168), in the
        # commit that created the directory, on the identical argument: a
        # SKILL.md is text a model reads and acts on, and S16 asserts that one
        # rather than leaving it to the scope string being read.
        scope   = @('lw-watchtower/bin/*', 'lw-watchtower/lib/*', 'lw-watchtower/hooks/*',
                    'lw-watchtower/statusline/*', 'lw-watchtower/context/*',
                    'lw-watchtower/commands/*', 'lw-watchtower/agents/*',
                    'lw-watchtower/output-styles/*',
                    'lw-watchtower/skills/*',
                    'lw-watchtower/config.json', 'lw-watchtower/.claude-plugin/*')
    }
    @{
        id      = 'gated-tool'
        name    = 'a role allowlist naming a tool the model does not have'
        why     = 'the same shape as the rule above it - a shipped file asserting something exists that does not - and it is here for the same reason: it is a property of what a STRANGER RECEIVES. A `tools:` allowlist is not validated against anything. An entry naming a tool the session does not carry is never matched and nothing reports it, so the role advertises a capability it cannot have and a model reads that list as a statement of what it may do. Measured 2026-09-05: lw-orchestrator.md named TaskCreate, TaskUpdate, TaskList and TaskGet while declaring `model: opus`, and none of the four exists on Opus 5, Opus 4.8, Sonnet 5 or Fable 5 unless the operator sets CLAUDE_CODE_ENABLE_TODO_TOOLS. A switch wired to nothing, shipped inside the plugin that exists to catch them.'
        # WHY THIS IS NOT `claude plugin validate --strict`. That was the obvious
        # guard and it was PROBED before this rule was written rather than
        # assumed: with the four names restored it printed `Validation passed`,
        # exit 0, and with a tool named `NotARealToolXyz` it printed
        # `Validation passed`, exit 0. It does not check tool names at all.
        # Adding it to CI and calling it the guard here would have been a switch
        # wired to nothing standing guard over a switch wired to nothing.
        #
        # ANCHORED TO THE `tools:` LINE, AND THAT IS THE WHOLE PRECISION OF IT.
        # Matching the bare names anywhere would refuse the paragraph in
        # lw-orchestrator.md that RECORDS the removal and says why - the same
        # distinction HISTORICAL MENTIONS draws for the rule above, obtained
        # here for free because these lines are matched one at a time and a
        # frontmatter allowlist is exactly one line. Naming a gated tool while
        # saying it is gated is the opposite of this defect.
        #
        # TaskStop AND TaskOutput ARE DELIBERATELY ABSENT FROM THE NEEDLE. Both
        # are present on those models - measured in a live session's own tool
        # list, not inferred from the four being gone - and a coordinator that
        # cannot stop a runaway worker is worse than one that cannot open a task
        # ledger. `\b` after each alternative is what keeps TaskList from
        # matching inside a longer name.
        #
        # PINNED TO A CLI BUILD, NOT TO A CONTRACT, and said so here rather than
        # discovered later. The gate is CLAUDE_CODE_ENABLE_TODO_TOOLS in the
        # shipped binary, beside CLAUDE_CODE_ENABLE_TASKS. If a release returns
        # the four to the default set this rule is wrong and must be deleted in
        # the commit that says so - the same standing that bin\lwg-doctor.ps1's
        # $atRisk list has against $LwgVerifiedBuild. Re-read the gate before
        # touching it; do not reason from this comment's age.
        pattern = '(?i)^\s*tools:\s.*\b(?:TodoWrite|TaskCreate|TaskGet|TaskUpdate|TaskList)\b'
        # agents/ ONLY. commands/ pages carry `allowed-tools` for a different
        # purpose - a turn-scoped grant, not a role's standing capability - and
        # a name there that the session lacks fails loudly at invocation rather
        # than silently at every turn. Widening this to commands/ would be a
        # rule asserting something it was not written to assert.
        scope   = @('lw-watchtower/agents/*')
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
    @{ files = 'lw-watchtower/lib/common.ps1'
       rules = @('deleted-script')
       test  = 'how the healer wrote a'
       why   = 'past tense, recounting the founding defect: a healer wrote a clearing record into the wrong file while the log it was meant to clear stayed empty. The sentence is the reason the surrounding code exists and cannot be told without naming what did it.' }
    @{ files = 'lw-watchtower/lib/common.ps1'
       rules = @('deleted-script')
       test  = 'was the third caller when this was written'
       why   = 'THIS ENTRY REPLACED A BARRED-LEDGER ENTRY, and the difference is the whole point of having two tables. The line used to assert the deleted library half as a live third caller in the present tense, with a "verified" that made it read as checked-and-current; it was ledger''d to the lane that owned the file, printed on every run as real and unfixed. That lane rewrote it, and the sentence is now headed HISTORICAL in the source and says outright which wave deleted it and why the evidence still needs the name. A ledger entry would now be printing a false claim about an honest line, so it is gone and this is here instead.' }
    @{ files = 'lw-watchtower/lib/common.ps1'
       rules = @('deleted-script')
       test  = '^\s*#\s*was DELETED in wave 1 \(#192\) along with'
       why   = 'the deletion itself, stated in the source. This is the sentence the rule exists to encourage, so it would be perverse for the rule to refuse it.' }
    @{ files = 'lw-watchtower/lib/common.ps1'
       rules = @('deleted-script')
       test  = ', which laid out'
       why   = 'the redaction helper''s reason, correctly detached from the reader it was first written against. The line names that reader, says the wave deleted it, and says the reason did not go with it because it was never a property of that one reader - which is the strongest form of this: not just "it is gone" but "and here is why the code stays". Previously ledger''d as live prose asserting a deleted console report as the current justification.' }
    @{ files = 'lw-watchtower/statusline/statusline.ps1'
       rules = @('deleted-script')
       test  = '^\s*#\s*writers of that record were'
       why   = 'the tombstone on the arm that used to zero the health counters. It names the two writers AND says both are deleted, in the same sentence, which is the form #198 settled on. Without it the missing arm reads as an oversight rather than as a decision, and the next reader re-adds it.' }
    @{ files = 'lw-watchtower/statusline/statusline.ps1'
       rules = @('deleted-script')
       test  = 'to name the tasks\..{0,40}:136 read'
       why   = 'the record of why three readers of one log disagreed about one number. The sentence that follows it states outright that two of the three are deleted and that this file is the last of them, so the mention is dated on the spot rather than left to be checked.' }
)

# ===========================================================================
# STILL IN THE REPOSITORY, NO LONGER IN THE PAYLOAD
#
#   files  repo-relative path, matched exactly
#   issue  the issue that OWNS the site
#   why    what is there, and why this pass did not fix it
#
# THESE FIVE WERE BARRED-LEDGER ENTRIES UNTIL THE PAYLOAD RESTRUCTURE, and
# every one of them is now OUTSIDE the scanned subtree. Mechanically the table
# could be deleted: no hit from any of these files is ever offered to
# Test-Ledgered again, so nothing here excuses anything any more.
#
# DELETING IT WOULD BE THE DISHONEST FIX. The guard's report would improve
# without a single site being repaired, and the ownership record - #118/#121,
# and #124 including the .gitignore seventh site that was found by this sweep
# and by no issue's enumeration - would disappear from the only place a machine
# was still printing it. The disclosures are still in the tree; they simply no
# longer reach anybody who installs. So the table is KEPT, printed
# unconditionally rather than only when it matches, and ASSERTED: S9 fails if a
# path named here ever comes back inside the payload, which is the one way this
# record could rot into a lie.
# ===========================================================================
$OutOfPayloadRecord = @(
    @{ files = 'CHANGELOG.md'
       issue = '#118 / #121'
       why   = 'the pull-ref narrative, the tip SHA, the commit count and a visibility-conditioned claim. CHANGELOG.md is a historical record and correcting it would falsify it; it is now outside the payload, so it reaches nobody who installs.' }
    @{ files = 'README.md'
       issue = '#124'
       why   = 'the no-CI-badge justification, conditioned on the repository being private. Its verbatim twin is docs/testing.md, and both are now outside the payload.' }
    @{ files = 'docs/testing.md'
       issue = '#124'
       why   = 'verbatim twin of README.md''s badge sentence.' }
    @{ files = 'docs/limitations.md'
       issue = '#124'
       why   = 'the branch-protection 403 the page describes stops being returned at the flip. Phrased without the trigger words on purpose - this table is prose in a tracked file, and quoting the sentence it records would itself be a hit.' }
    @{ files = '.gitignore'
       issue = '#124'
       why   = 'A SEVENTH SITE, NAMED BY NO ISSUE: the comment above the workflow entries says those settings are not even settable before the flip. Found by this sweep rather than by the six-site enumeration #124 was filed with, which is the strongest argument for having a sweep at all. Recorded here so it reaches whoever runs the flip runbook. The wording is paraphrased rather than quoted, for the reason in the docs/limitations.md entry above.' }
)

# ===========================================================================
# THE BARRED LEDGER - sites INSIDE the payload that this pass does not own
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
# it, which is the wrong incentive on the wrong person. The record above is the
# opposite case and IS asserted, because a path crossing the payload boundary
# is a fact about the tree rather than about anybody's fix.
# ===========================================================================
$BarredLedger = @(
    # EMPTY, AND THAT IS A RESULT RATHER THAN AN OVERSIGHT. Two things
    # emptied it and neither was a decision to excuse less. The five
    # root-file entries moved to the record above when the payload became a
    # subdirectory - they are outside the scanned set now, so they could not
    # excuse anything even if they stayed. The one payload entry,
    # lw-watchtower/lib/common.ps1's deleted-script sites, was retired when
    # #192's lane rewrote those lines into honest tombstones; they are
    # classified by the HISTORICAL MENTIONS table above, which is a
    # different statement and the right one.
    #
    # So NO SITE INSIDE THE PAYLOAD IS EXCUSED BY ANYTHING, and the
    # KNOWN, BARRED block below simply does not print. Keep the mechanism:
    # the next cross-lane disclosure needs somewhere to be recorded that is
    # not silence, and deleting the table would make the next fixer invent
    # one under pressure.
)

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$missing    = New-Object System.Collections.ArrayList
$binary     = New-Object System.Collections.ArrayList
# S2 and S3 are reported PER SET. "not fully scanned" has to keep meaning what
# it says about the payload specifically: a tracked docs/ page that vanished
# from disk does not stop the payload from having been read end to end, and
# collapsing the two would make one of the two statements false whichever way
# it went.
$missingPayload = New-Object System.Collections.ArrayList
$binaryPayload  = New-Object System.Collections.ArrayList
$payloadRead    = 0
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
        $payloadList = @(& git ls-files -- ($script:PayloadRel + '/') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $payloadExit = $LASTEXITCODE
    } finally { Pop-Location }
    if ($gitExit -ne 0) { throw "git ls-files exited $gitExit - the file list could not be enumerated" }
    if ($payloadExit -ne 0) { throw "git ls-files -- $($script:PayloadRel)/ exited $payloadExit - the payload could not be enumerated" }
    if ($files.Count -eq 0) {
        # Zero files scanned is a broken enumeration, never a clean tree.
        throw 'git ls-files returned no files - the enumeration is broken, so nothing was scanned'
    }
    if ($payloadList.Count -eq 0) {
        # Same argument one level down, and it is the one that matters more:
        # every DETECTION rule runs over this set, so an empty payload list is a
        # guard reporting a clean payload it never opened.
        throw "git ls-files -- $($script:PayloadRel)/ returned no files - the payload enumeration is broken, so no detection rule asked anything of anything"
    }

    # ------------------------------------------------------------------
    # THE DECLARED SOURCE AND THE SCANNED SUBTREE MUST AGREE, and this is
    # checked BEFORE a single rule runs. $script:PayloadRel is the only
    # hardcoded path in this file, and it is acceptable only because it is
    # verified against the manifest the CLI actually reads. Without this the
    # subtree could be renamed in marketplace.json and every rule below would
    # go on scanning a directory nobody ships, reporting green.
    # ------------------------------------------------------------------
    $script:SourceAgrees = $false
    $script:SourceWhy    = ''
    $mktRel  = '.claude-plugin/marketplace.json'
    $mktPath = Join-Path $script:RepoRoot ($mktRel -replace '/', '\')
    $plgPath = Join-Path $script:RepoRoot ($script:PayloadRel + '\.claude-plugin\plugin.json')
    if (-not (Test-Path -LiteralPath $mktPath -PathType Leaf)) {
        $script:SourceWhy = "$mktRel is missing, so the payload boundary could not be read at all"
    } elseif (-not (Test-Path -LiteralPath $plgPath -PathType Leaf)) {
        $script:SourceWhy = "$($script:PayloadRel)/.claude-plugin/plugin.json is missing, so the entry to match in $mktRel could not be named"
    } else {
        $mkt = (Get-Content -LiteralPath $mktPath -Raw) | ConvertFrom-Json
        $plg = (Get-Content -LiteralPath $plgPath -Raw) | ConvertFrom-Json
        # BY NAME, NEVER BY INDEX - the same discipline the version guard uses.
        $ent = @($mkt.plugins | Where-Object { $_.name -eq $plg.name })
        if ($ent.Count -ne 1) {
            $script:SourceWhy = ("$mktRel holds {0} entries named '{1}', expected exactly 1, so its source was never read" -f $ent.Count, $plg.name)
        } else {
            $declared = [string]$ent[0].source
            $want     = './' + $script:PayloadRel
            if ($declared -eq $want) {
                $script:SourceAgrees = $true
                $script:SourceWhy    = "declares source '$declared'"
            } else {
                $script:SourceWhy = "$mktRel declares source '$declared' but this guard scanned '$($script:PayloadRel)/'. One of them is wrong and NOTHING below was checked against what a consumer receives."
            }
        }
    }

    $payloadSet = New-Object 'System.Collections.Generic.HashSet[string]' ([string[]]$payloadList, [StringComparer]::Ordinal)
    $ownerPaths = @($RegionOwners | ForEach-Object { $_.path })
    Write-Output "  payload : $($payloadList.Count) tracked under $($script:PayloadRel)/   (the DETECTION RULES run over these)"
    Write-Output "  tree    : $($files.Count) tracked in the repository   (the REGION-MARKER SWEEP runs over these)"
    Write-Output "  source  : $($script:SourceWhy)"
    Write-Output ''

    # ONE WALK, TWO QUESTIONS. Every tracked file is opened, because the
    # region-marker sweep has to see all of them; the DETECTION rules are asked
    # only of the files inside the payload. Splitting the walk instead would
    # have meant reading the payload twice and reporting two file counts that
    # could disagree.
    foreach ($rel in $files) {
        $inPayload = $payloadSet.Contains($rel)
        $abs = Join-Path $Root ($rel -replace '/', '\')
        if (-not [IO.File]::Exists($abs)) {
            [void]$missing.Add($rel)
            if ($inPayload) { [void]$missingPayload.Add($rel) }
            continue
        }

        $bytes = [IO.File]::ReadAllBytes($abs)
        $probe = [Math]::Min($bytes.Length, 8192)
        if ($probe -gt 0 -and [Array]::IndexOf($bytes, [byte]0, 0, $probe) -ge 0) {
            [void]$binary.Add($rel)
            if ($inPayload) { [void]$binaryPayload.Add($rel) }
            continue
        }
        $fileCount++
        if ($inPayload) { $payloadRead++ }

        $lines  = [IO.File]::ReadAllText($abs) -split "`r?`n"
        $inRegion = $false
        $isOwner  = $ownerPaths -contains $rel

        if ($inPayload) {
            foreach ($r in $Rules) {
                if (-not $r.ContainsKey('scope')) { continue }
                if (-not $scopedFiles.ContainsKey($r.id)) { $scopedFiles[$r.id] = 0 }
                if (Test-RuleInScope -Rule $r -Rel $rel) { $scopedFiles[$r.id]++ }
            }
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
            # OUTSIDE THE PAYLOAD THE MARKER SWEEP IS ALL THAT RUNS. A hit in
            # docs/ or CHANGELOG.md is not something a consumer receives, and
            # reporting it under "THE SHIPPED PAYLOAD DISCLOSES" would be a
            # false accusation on the one guard whose worth is that a failure
            # means something.
            if (-not $inPayload) { continue }

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
    # THE OUT-OF-PAYLOAD RECORD, PRINTED EVERY RUN - including now that it can
    # never match. A table that only appears when it fires is a table nobody
    # reads on the day it stops firing, and "these disclosures are still in the
    # repository" is exactly the sentence that must not go quiet just because
    # the boundary moved.
    # ----------------------------------------------------------------------
    Write-Output "STILL IN THE REPOSITORY, NO LONGER IN THE PAYLOAD - $($OutOfPayloadRecord.Count) site(s) these rules no longer reach:"
    foreach ($o in $OutOfPayloadRecord) {
        Write-Output ("  {0,-22} owned by {1}" -f $o.files, $o.issue)
        Write-Output ("      {0}" -f $o.why)
    }
    Write-Output 'They are REAL and are still tracked. They no longer reach a consumer, which is'
    Write-Output 'what the payload boundary bought - it is NOT the same as their being fixed.'
    Write-Output ''

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

    Add-Result 'S1b the payload enumeration is non-empty' `
        ($payloadList.Count -gt 0) `
        "git ls-files -- $($script:PayloadRel)/ returned nothing, so every detection rule below ran over an empty set and could not have found anything"

    Add-Result 'S2  every tracked path exists on disk and was read' `
        ($missing.Count -eq 0) `
        ("$($missing.Count) tracked path(s) had nothing to read, so the TREE was NOT fully scanned and the marker sweep is incomplete" +
            $(if ($missingPayload.Count -gt 0) { " - $($missingPayload.Count) of them are inside the payload, so the detection rules are incomplete too" } else { ' (none of them inside the payload)' }) +
            ': ' + ($missing -join ', '))

    Add-Result 'S3  no tracked file was skipped as binary' `
        ($binary.Count -eq 0) `
        ("$($binary.Count) tracked file(s) hold a NUL byte in the first 8 KB and were not read as text. A UTF-16 page is text in the wrong encoding, not a binary" +
            $(if ($binaryPayload.Count -gt 0) { " - $($binaryPayload.Count) of them are inside the payload" } else { ' (none of them inside the payload)' }) +
            ': ' + ($binary -join ', '))

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

    # THE NUMBER IS PRINTED EVERY RUN, NOT ONLY WHEN IT IS ZERO. S7 above fails
    # at zero, which catches a scope that was switched off entirely; it says
    # nothing about a scope that quietly NARROWED - seven globs down to one,
    # after a directory rename, is a rule still "applied" and barely asking. A
    # count beside the rule id is the only thing that makes that visible, and
    # tests\portability_scan.ps1 prints exactly this line for exactly this
    # reason. A reader comparing two runs sees the corpus shrink; a reader of a
    # green boolean does not.
    foreach ($k in ($scopedFiles.Keys | Sort-Object)) {
        Write-Output ("  rule {0} is SCOPED and was applied to {1} of {2} payload file(s){3}" -f `
            $k, $scopedFiles[$k], $payloadRead,
            $(if ($scopedFiles[$k] -eq 0) { ' - ZERO, so it asked nothing of anything and cannot have found anything' } else { '' }))
    }
    Write-Output ''

    # S8 IS THE PREMISE, ASSERTED RATHER THAN STATED. Every rule above runs over
    # a subtree this file NAMES, and the name is only trustworthy because the
    # manifest the CLI reads is parsed and compared to it on every run. Without
    # this case, renaming the payload directory in marketplace.json would leave
    # the guard scanning a directory nobody ships and reporting it clean - the
    # "reports healthy while doing nothing" shape, aimed at the payload boundary
    # itself. It is a named case rather than a bare throw so that a green run
    # says out loud that the premise was checked.
    Add-Result 'S8  the source marketplace.json declares and the subtree scanned are the same' `
        $script:SourceAgrees `
        $script:SourceWhy

    # S9 IS WHAT KEEPS THE RECORD ABOVE HONEST. Those five paths are excluded
    # from every rule by being outside the payload, not by any decision this
    # file makes - so if one of them is ever moved INTO lw-watchtower/, it would
    # silently become an unscanned-by-nobody file that this table still claims
    # is out of reach. The failure is loud instead.
    $recordInPayload = @($OutOfPayloadRecord | Where-Object { $payloadSet.Contains($_.files) } | ForEach-Object { $_.files })
    # S10 IS THE MOVE ITSELF, ASSERTED. S8 reads what marketplace.json DECLARES;
    # this reads what the tracked tree actually holds. The two are different
    # questions and both have to be yes: a declared source pointing at a subtree
    # with no plugin manifest in it is a marketplace entry the CLI cannot load,
    # and a plugin manifest left behind at the repository root is a second
    # definition of the same plugin that nothing ships and everything reads
    # first. Neither shape is visible to any rule above, because both are facts
    # about WHERE files are rather than about what they say.
    $plugInPayload = $payloadSet.Contains($script:PayloadRel + '/.claude-plugin/plugin.json')
    $plugAtRoot    = ($files -contains '.claude-plugin/plugin.json')
    Add-Result 'S10 the plugin manifest is inside the payload and nowhere else' `
        ($plugInPayload -and -not $plugAtRoot) `
        ("$($script:PayloadRel)/.claude-plugin/plugin.json is $(if ($plugInPayload) { 'tracked' } else { 'NOT TRACKED - the declared source names a subtree with no plugin manifest in it, so the CLI has nothing to load' })" +
         "; .claude-plugin/plugin.json at the repository root is $(if ($plugAtRoot) { 'ALSO TRACKED - two manifests define one plugin and only one of them ships' } else { 'absent, which is correct' })")

    # S11. #118. THE LICENCE TRAVELS WITH THE DISTRIBUTION, AND CANNOT DRIFT.
    #
    #     Drawing the payload boundary took LICENSE out of what a consumer
    #     receives: it is at the repository root, and only lw-watchtower/ is
    #     copied. plugin.json declares `"license": "Apache-2.0"`, and Apache-2.0
    #     section 4(a) requires a copy of the License to be given to recipients
    #     of the work. So there are two copies now, and two copies of anything
    #     is a drift problem the moment one is edited.
    #
    #     BYTES, NOT LENGTH, NOT A HASH OF THE FIRST LINE. The failure this
    #     guards against is somebody amending one copy - a year in a copyright
    #     line, a re-wrap - and a comparison that could pass on two different
    #     licences would be worse than no comparison, because the report would
    #     say they agree.
    #
    #     A MISSING FILE IS A FAILURE, NOT A SKIP. If either copy is absent the
    #     case has established nothing and must say so: the whole point is that
    #     the payload carries one.
    $licRepo    = Join-Path $script:RepoRoot 'LICENSE'
    $licPayload = Join-Path $script:RepoRoot ($script:PayloadRel + '\LICENSE')
    $licRepoOk    = [IO.File]::Exists($licRepo)
    $licPayloadOk = [IO.File]::Exists($licPayload)
    $licSame = $false
    if ($licRepoOk -and $licPayloadOk) {
        $a = [IO.File]::ReadAllBytes($licRepo)
        $b = [IO.File]::ReadAllBytes($licPayload)
        $licSame = ($a.Length -eq $b.Length)
        if ($licSame) {
            for ($i = 0; $i -lt $a.Length; $i++) { if ($a[$i] -ne $b[$i]) { $licSame = $false; break } }
        }
    }
    Add-Result 'S11 the payload carries a byte-identical copy of the repository LICENSE' `
        ($licRepoOk -and $licPayloadOk -and $licSame) `
        ("LICENSE at the repository root is $(if ($licRepoOk) { 'present' } else { 'MISSING' }); " +
         "$($script:PayloadRel)/LICENSE is $(if ($licPayloadOk) { 'present' } else { 'MISSING - a consumer receives no licence at all, and plugin.json declares Apache-2.0, whose section 4(a) requires one to travel with the distribution' }); " +
         "the two are $(if ($licSame) { 'identical' } else { 'NOT byte-identical - one of them has been edited and the two copies now say different things about the same distribution' }).")

    # S12. #277. EVERY COMMAND PAGE TAKES THE PowerShell TOOL OFF THE TABLE.
    #
    #     On Windows the CLI offers a `PowerShell` tool beside `Bash`, and in
    #     five of six measured headless sessions the model reached for it first
    #     and was refused - five refusals in seven turns on /lw-watchtower:doctor
    #     alone, for a script that runs in 1.3 s. In the TUI each refusal is a
    #     permission prompt put to the operator for a tool call the page never
    #     asked for.
    #
    #     WHY THE DENY AND NOT AN ALLOW. Adding `PowerShell(powershell:*)` to
    #     `allowed-tools` is a no-op and a case asserting it would guard nothing:
    #     the PowerShell tool's validator bundle runs BEFORE any rule is
    #     consulted and returns "ask" for any command launching a nested
    #     powershell, and the decision merge is deny -> ask -> allow, so no allow
    #     rule is ever reached. The only lever is `disallowed-tools`, which the
    #     CLI unions into the deny scope for the command's turn and replaces on
    #     the next input - so it is not a session-wide loss of the tool.
    #
    #     BOTH HALVES, because each alone is half the property. The deny is what
    #     stops the noisy path; the `Bash(powershell:*)` allow is what leaves the
    #     page a tool it can actually run its one line through. A page carrying
    #     the deny and no allow would run nothing at all, and would pass a case
    #     that only looked for the deny.
    #
    #     THE POINT OF GUARDING IT AT ALL: the frontmatter landed on all six
    #     pages with no case (#291), so the deny could come back off one page at
    #     a time and nothing would notice - which is the class of defect this
    #     repository exists to catch. Red-first for this case was PLANTED rather
    #     than historical, and that is stated on the PR: at 1baf6d4 all six pages
    #     already carry the line.
    $cmdDir   = Join-Path $script:RepoRoot ($script:PayloadRel + '\commands')
    $cmdPages = @()
    if ([IO.Directory]::Exists($cmdDir)) { $cmdPages = @([IO.Directory]::GetFiles($cmdDir, '*.md')) }
    $noDeny  = @()
    $noAllow = @()
    $noFront = @()
    foreach ($cp in $cmdPages) {
        $cpText = ''
        try { $cpText = [IO.File]::ReadAllText($cp) } catch { }
        $cpFm = if ($cpText -match '(?s)^---\r?\n(.*?)\r?\n---\r?\n') { $Matches[1] } else { '' }
        $cpName = Split-Path -Leaf $cp
        if ([string]::IsNullOrWhiteSpace($cpFm)) { $noFront += $cpName; continue }
        if ($cpFm -notmatch '(?m)^disallowed-tools:\s*"?PowerShell"?\s*$')  { $noDeny  += $cpName }
        if ($cpFm -notmatch '(?m)^allowed-tools:.*Bash\(powershell:\*\)')   { $noAllow += $cpName }
    }
    Add-Result ("S12 every commands/*.md denies the PowerShell tool and pre-approves the Bash shape ($($cmdPages.Count) page(s))") `
        ($cmdPages.Count -gt 0 -and $noFront.Count -eq 0 -and $noDeny.Count -eq 0 -and $noAllow.Count -eq 0) `
        ($(if ($cmdPages.Count -eq 0) { "no *.md was found under $cmdDir at all, so this case asked nothing of anything - an empty set is not a pass" } else { '' }) +
         $(if ($noFront.Count) { "page(s) with no parseable --- frontmatter block, so neither key could be read: $($noFront -join ', '). " } else { '' }) +
         $(if ($noDeny.Count)  { "page(s) missing disallowed-tools: `"PowerShell`", so the model is free to reach for the PowerShell tool and be refused by its own validator: $($noDeny -join ', '). " } else { '' }) +
         $(if ($noAllow.Count) { "page(s) whose allowed-tools does not carry Bash(powershell:*), so the one line the page tells the model to run is pre-approved for no tool at all: $($noAllow -join ', '). " } else { '' }) +
         "checked $($cmdPages.Count) page(s) under $($script:PayloadRel)/commands/")

    # S13. #316. THE ORCHESTRATOR ROLE MAY NOT GRANT ITSELF A WORKING TOOL.
    #
    #     THE MISSION IN ONE ASSERTION. #316's whole mechanism is that the main
    #     thread, when it runs this role, CANNOT edit or execute - so the work
    #     goes to subagents and the thread stays a conversation. That property
    #     is one frontmatter line, it is not validated by anything the CLI runs,
    #     and it would be undone by a single well-meaning addition: `Bash` on
    #     that line reads as a convenience and silently ends the delegation
    #     discipline the role's entire body is written around. The body would
    #     still SAY the thread cannot edit, which is the "switch wired to
    #     nothing" shape inverted - prose asserting a restriction the
    #     frontmatter no longer imposes.
    #
    #     NOT rule 7, AND NOT THE FRONTMATTER GUARD THAT IS STILL OWED. Rule 7
    #     (`gated-tool`) forbids naming a tool the model DOES NOT HAVE; this
    #     forbids naming five tools the model very much does have. And neither
    #     is the YAML-validity guard #316 says is "validated in CI": NOTHING in
    #     this repository parses a role's frontmatter for well-formedness, so a
    #     malformed block still loads the agent with every field silently
    #     dropped (docs/roles.md, "Frontmatter breaks silently") - INCLUDING
    #     the `tools:` line this case
    #     reads. Stated here rather than left to be assumed: a green S13 proves
    #     the LINE is right, never that the block PARSES. That guard is owed and
    #     is recorded as owed on #316.
    #
    #     PLANTED, NOT HISTORICAL, AND SAID SO. At 97f0697 the `tools:` line
    #     already carries none of the five, so there is no commit at which this
    #     case failed on its own - the same standing S12 above records. It was
    #     proved red by MUTATION: `Bash` added to that line at 97f0697, this
    #     suite run, S13 FAILED naming lw-orchestrator.md and the tool; the line
    #     was then restored and it passed. That transcript is on the PR.
    #
    #     A MISSING FILE IS A FAILURE. The role is deletable by design - the
    #     header says so - but a case that quietly passed when the file it reads
    #     is absent would be green on the one tree where the mission ships
    #     nothing at all. If the role is genuinely retired, this case is deleted
    #     in the commit that retires it.
    $orcPath = Join-Path $script:RepoRoot ($script:PayloadRel + '\agents\lw-orchestrator.md')
    $orcFound = [IO.File]::Exists($orcPath)
    $orcFm    = ''
    $orcTools = ''
    if ($orcFound) {
        $orcText = ''
        try { $orcText = [IO.File]::ReadAllText($orcPath) } catch { }
        if ($orcText -match '(?s)^---\r?\n(.*?)\r?\n---\r?\n') { $orcFm = $Matches[1] }
        if ($orcFm -match '(?m)^\s*tools:\s*(.+?)\s*$') { $orcTools = $Matches[1] }
    }
    # THE FIVE ARE THE delegate_gate MATCHER'S FIVE, and that is deliberate:
    # hooks/hooks.json names exactly Edit, Write, NotebookEdit, Bash and
    # PowerShell as the tools that do work rather than talk, and #316's table
    # sets the role against that gate as the alternative mechanism for the same
    # five. If the matcher ever widens, this needle widens with it.
    $orcGranted = @()
    if ($orcTools) {
        foreach ($t in @('Bash', 'PowerShell', 'Edit', 'Write', 'NotebookEdit')) {
            if ($orcTools -match ('(?i)(^|[,\s])' + $t + '($|[,\s])')) { $orcGranted += $t }
        }
    }
    Add-Result 'S13 the orchestrator role grants itself no tool that edits or executes' `
        ($orcFound -and $orcTools -ne '' -and $orcGranted.Count -eq 0) `
        ($(if (-not $orcFound) { "$($script:PayloadRel)/agents/lw-orchestrator.md is NOT on disk, so this case asked nothing of anything and the role #316's mission rests on is not in the payload at all - an empty set is not a pass. " } else { '' }) +
         $(if ($orcFound -and $orcTools -eq '') { "lw-orchestrator.md carries no 'tools:' line in its frontmatter, so it is an ALLOW-EVERYTHING role: the thread that runs it can edit and execute, and the body's claim that it cannot is false. " } else { '' }) +
         $(if ($orcGranted.Count) { "lw-orchestrator.md's tools allowlist names $($orcGranted -join ', '), so the main thread running this role CAN do the work itself and the delegation the whole body describes is a suggestion rather than the shape of the seat. Remove the tool, or rewrite the body in the same commit. " } else { '' }) +
         "read tools: '$orcTools'")

    # S14. #316. THE FRONTMATTER GUARD, BECAUSE THE DOCUMENTED ONE DOES NOT WORK.
    #
    #     WHAT BREAKS. A malformed frontmatter block does NOT fail loudly. The
    #     agent still loads, with its name taken from the filename and EVERY
    #     other field silently dropped - no model, no effort, and no tool
    #     restriction. A role whose entire purpose is a tool restriction is
    #     therefore one typo away from being an allow-everything role that still
    #     reads, to anyone opening the file, exactly as it did before. The same
    #     failure on a command page drops `disallowed-tools`, which is the #277
    #     property S12 above exists to protect - so this case is asked of BOTH
    #     directories, and that is deliberate rather than incidental.
    #
    #     WHY NOT `claude plugin validate --strict`, WHICH docs/roles.md's
    #     "Frontmatter breaks silently" section USED TO TELL YOU TO RUN - a
    #     section, not a line, because a line number goes stale on the next edit
    #     above it and this file's HISTORICAL MENTIONS table says so about its
    #     own allowlist. Because it does not catch the failure that page
    #     names as the commonest one. PROBED ON CLI 2.1.263, 2026-09-06, over a
    #     scratch copy with fifteen planted malformations, each independently
    #     confirmed malformed by two YAML parsers. In all fifteen the agent was
    #     never rejected and never dropped from the roster. The validator exits
    #     1 on five of them - an unclosed fence, an orphan indented key, a
    #     missing description, no frontmatter block at all, an unbalanced quote
    #     - and exits 0 on the rest:
    #
    #         * a TAB used as indentation;
    #         * a DUPLICATE key - `tools:` twice, last-wins, so the WIDER list
    #           survives and the narrower one is silently discarded;
    #         * an UNQUOTED description containing a colon-space, which
    #           that same section calls the commonest cause of all this, and
    #           which was runtime-confirmed broken - the description vanished
    #           from the roster and the always-on token cost halved;
    #         * `tools:` written as a mapping - well-formed YAML, wrong type;
    #         * a reserved character opening a value (`model: @haiku`);
    #         * `name:` not matching the filename stem, which docs/roles.md:55
    #           requires and nothing enforced until this case;
    #         * unrecognised top-level keys, despite --strict's own help
    #           promising to fail on them.
    #
    #     Re-run through all five invocation forms and --json: every one
    #     returned success. Wiring that command into CI and calling it the
    #     frontmatter guard would have been a switch wired to nothing standing
    #     guard over the exact defect it was named for - the same finding rule 7
    #     records about the same command for tool names.
    #
    #     PINNED TO CLI 2.1.263, NOT TO A CONTRACT. A later build could tighten
    #     the validator. Nobody deletes this case on the strength of this
    #     comment's age: re-probe first, the way this was probed.
    #
    #     A LINE LINTER, NOT A YAML PARSER, AND THE ASSUMPTION IS STATED.
    #     Windows PowerShell 5.1 ships no YAML parser, and shelling out to one
    #     would put a Node dependency and an install step into a suite that is
    #     pure PowerShell over a Windows-only payload. What makes a linter
    #     sufficient here is a property of THIS payload rather than of YAML:
    #     every frontmatter block in it was flat `key: value`, one pair per
    #     line, no nesting, no block scalars, no lists.
    #
    #     THAT ASSUMPTION STOPPED BEING TRUE ON 7 SEPTEMBER 2026 (#179), AND
    #     THE PARAGRAPH ABOVE ORDERED WHAT HAPPENED NEXT: "this case starts
    #     failing on a legitimate file and must be REWRITTEN RATHER THAN
    #     LOOSENED". `skills/task-observer/SKILL.md` is vendored third-party
    #     text and opens `description: >` - a FOLDED BLOCK SCALAR whose
    #     continuation lines are indented. Every one of those lines failed the
    #     flat-pair test and the `>` failed the reserved-character test:
    #     SIXTEEN defects on one legitimate, unmodified file.
    #
    #     BASELINE 010a550. RED AT 010a550, and the shape of the proof is worth
    #     stating because it is the reason the file was not touched instead:
    #     with the six vendored bodies staged and this case unchanged, S14
    #     reported those sixteen defects and the suite exited 1. Reflowing the
    #     vendored `description` to one line would have turned it green in one
    #     edit - and would have bought a permanent "Modified: yes" under
    #     CC BY 4.0 section 3(a)(1)(B) for that file, and ended byte-identical
    #     resync with upstream forever, in exchange for a line of YAML the CLI parses
    #     correctly today. A guard going red on a correct file is the guard's
    #     defect, not the file's - this suite says so in three other places.
    #
    #     WHAT THE REWRITE ADDS, AND WHAT IT DELIBERATELY DOES NOT. When a
    #     value is EXACTLY a block-scalar indicator - `>`, `>-`, `>+`, `|`,
    #     `|-`, `|+` - the following whitespace-indented lines are consumed as
    #     that scalar's BODY: they are not pairs and are not linted as pairs,
    #     and the colon-space, unbalanced-quote and reserved-character tests
    #     are skipped for them. Key uniqueness is still enforced, because the
    #     key itself is still a key. The block ends at the first non-blank line
    #     that is NOT indented; a BLANK line does not end it, which is correct
    #     for a folded scalar and is the one place a naive reading gets this
    #     wrong. An indented body of ZERO lines is still a defect - that is an
    #     EMPTY field, which is the failure this case exists for, arriving by a
    #     different door.
    #
    #     NOT ADDED: an explicit indentation indicator (`>2`), block scalars
    #     nested inside a mapping, and lists. None of the three is in this
    #     payload, `>2` still reads as a reserved-character defect, and
    #     inventing support for shapes nothing here uses is how a linter
    #     becomes a bad YAML parser. Same standing as rule 7's pinned
    #     assumption: if one of them ships, this case goes red on a legitimate
    #     file and is rewritten again.
    #
    #     THE DEFECT MESSAGE NAMES THE DIRECTORY FOR A SKILL, not just the leaf.
    #     Every skill file in this payload is called SKILL.md - there are FIVE
    #     of them as of #179 - so "SKILL.md: ..." identified nothing. Roles,
    #     commands and styles keep the leaf, which is unique for them.
    #
    #     THE COLON-SPACE TEST IS ASKED ONLY OF UNQUOTED VALUES, and that is a
    #     deliberate narrowing: a QUOTED description containing a colon-space is
    #     valid YAML and five of the six roles here carry one. It is the
    #     unquoted form that YAML reads as a nested mapping and drops.
    #
    #     ENUMERATED FROM DISK, NEVER FROM A LIST. A hardcoded set would go
    #     quietly stale the day a seventh role ships - the doctrine this file
    #     already applies to every other enumeration. AN EMPTY SET IS A FAILURE:
    #     zero files linted is a case that asked nothing of anything.
    # OUTPUT-STYLES IS THE THIRD DIRECTORY, AND ITS FAILURE MODE IS DIFFERENT.
    # Read out of the 2.1.263 bundle: the plugin style loader wraps the whole
    # frontmatter parse in a catch that logs "Failed to load output style from
    # <path>" and returns null, so a malformed style is SKIPPED ENTIRELY rather
    # than loaded with its fields dropped. Different failure, identical silence
    # to the operator - the style simply is not in the /config picker, with no
    # message on any surface they read. The loader also applies NO schema to a
    # plugin style at all (the strict one runs for user styles only), which is
    # why every key this repository ships under that directory is checked here
    # for spelling rather than trusted.
    $fmDirs = @(
        @{ rel = 'agents';        path = (Join-Path $script:RepoRoot ($script:PayloadRel + '\agents'))        },
        @{ rel = 'commands';      path = (Join-Path $script:RepoRoot ($script:PayloadRel + '\commands'))      },
        @{ rel = 'output-styles'; path = (Join-Path $script:RepoRoot ($script:PayloadRel + '\output-styles')) }
    )
    $fmFiles   = @()
    $fmMissing = @()
    foreach ($d in $fmDirs) {
        if ([IO.Directory]::Exists($d.path)) { $fmFiles += @([IO.Directory]::GetFiles($d.path, '*.md')) }
        else { $fmMissing += $d.rel }
    }
    # skills/ JOINED THIS CASE ON 6 SEPTEMBER 2026 (#168), and it is enumerated
    # one directory deeper because that is the layout: skills\<name>\SKILL.md,
    # not skills\<name>.md. The failure this case exists for is identical there
    # - a malformed block loads the file with every field silently dropped, and
    # `description` is the field a skill is SELECTED on, so losing it makes the
    # skill invisible to the model that should have started it while the page
    # still reads correctly to a human. The `name`-matches-the-stem assertion
    # below is deliberately NOT extended to it: a skill's identity is its
    # DIRECTORY name, which is a different contract from the role one, and
    # asserting the role rule here would be a guard going red on a correct file.
    $skillsRoot = Join-Path $script:RepoRoot ($script:PayloadRel + '\skills')
    if ([IO.Directory]::Exists($skillsRoot)) {
        foreach ($sd in @([IO.Directory]::GetDirectories($skillsRoot))) {
            $sm = Join-Path $sd 'SKILL.md'
            if ([IO.File]::Exists($sm)) { $fmFiles += $sm }
        }
    } else { $fmMissing += 'skills' }
    # THE KEY SET IS NOT ASSERTED. docs/roles.md:53-61 tables seven keys, and a
    # subset check over them would be red the day the CLI adds an eighth - a
    # guard that goes red on a correct file teaches the next contributor to
    # loosen it. What IS asserted is that every key parses and that no key is
    # written twice, which is the failure mode with teeth.
    $fmBad = @()
    foreach ($fp in $fmFiles) {
        # A skill is identified by its DIRECTORY - every one of them is
        # SKILL.md - so the leaf alone would name four files at once.
        $fpName = Split-Path -Leaf $fp
        if ($fp -like '*\skills\*') { $fpName = (Split-Path -Leaf (Split-Path -Parent $fp)) + '/' + $fpName }
        $fpText = ''
        try { $fpText = [IO.File]::ReadAllText($fp) } catch { $fmBad += "${fpName}: could not be read"; continue }
        if ($fpText -notmatch '(?s)^---\r?\n(.*?)\r?\n---\r?\n') {
            $fmBad += "${fpName}: no frontmatter block that opens with --- on line 1 and closes with ---, so every field is dropped"
            continue
        }
        $fmBlock = $Matches[1]
        if ($fmBlock.Contains("`t")) {
            $fmBad += "${fpName}: the block contains a TAB. YAML forbids a tab as indentation and the block does not parse"
        }
        $fmKeys = @{}
        $fmLineNo = 1
        # The key whose block scalar is currently open, '' when none, and the
        # count of body lines it has been given. See BLOCK SCALARS above.
        $fmScalarKey  = ''
        $fmScalarBody = 0
        foreach ($fmLine in ($fmBlock -split "`r?`n")) {
            # A blank line inside a folded scalar is a PARAGRAPH BREAK and does
            # not close it, so this skip must stay above the block-scalar test
            # and must not touch $fmScalarKey.
            if ([string]::IsNullOrWhiteSpace($fmLine)) { $fmLineNo++; continue }
            if ($fmScalarKey -ne '') {
                if ($fmLine -match '^\s') { $fmScalarBody++; $fmLineNo++; continue }
                if ($fmScalarBody -eq 0) {
                    $fmBad += "${fpName}: '$fmScalarKey' opens a block scalar and no indented line follows it, so the field is EMPTY - the same silent drop this case exists for, arriving by a different door"
                }
                $fmScalarKey  = ''
                $fmScalarBody = 0
            }
            if ($fmLine -notmatch '^([A-Za-z][A-Za-z0-9_-]*):\s+(\S.*)$') {
                $fmBad += "${fpName}: frontmatter line $fmLineNo is not a flat 'key: value' pair - '$fmLine'"
                $fmLineNo++
                continue
            }
            $fmKey = $Matches[1]
            $fmVal = $Matches[2]
            if ($fmKeys.ContainsKey($fmKey)) {
                $fmBad += "${fpName}: '$fmKey' appears twice. YAML takes the LAST one, so the earlier value is silently discarded - and on a tools list that means the WIDER grant wins"
            }
            $fmKeys[$fmKey] = $true
            # A value that is EXACTLY a block-scalar indicator opens a block.
            # The key is recorded above, so uniqueness still holds; the value
            # tests below are asked of the indicator's BODY by nobody, which is
            # the point - `IMPORTANT: invoke ...` inside a folded description is
            # prose, not a nested mapping.
            if ($fmVal -match '^[>|][+-]?$') {
                $fmScalarKey  = $fmKey
                $fmScalarBody = 0
                $fmLineNo++
                continue
            }
            $fmQuoted = $false
            foreach ($q in @('"', "'")) {
                if ($fmVal.StartsWith($q)) {
                    if ($fmVal.Length -ge 2 -and $fmVal.EndsWith($q)) { $fmQuoted = $true }
                    else { $fmBad += "${fpName}: '$fmKey' opens with $q and does not close with one, so the block does not parse" }
                }
            }
            if (-not $fmQuoted) {
                if ($fmVal.EndsWith('"') -or $fmVal.EndsWith("'")) {
                    $fmBad += "${fpName}: '$fmKey' closes with a quote it never opened, so the block does not parse"
                }
                if ($fmVal -match ':\s') {
                    $fmBad += "${fpName}: '$fmKey' is UNQUOTED and contains a colon-space, which YAML reads as a nested mapping. This is the case docs/roles.md's 'Frontmatter breaks silently' section calls the commonest, and it is the one 'claude plugin validate --strict' passes clean"
                }
                # THE CHARACTER CLASS IS THE CLI'S OWN, NOT ONE INVENTED HERE.
                # The 2.1.263 bundle carries `/[{}[\]*&#!|>%@` + "`" + `]|: /`
                # as the test for whether a frontmatter value has to be quoted
                # when it WRITES one - the same two questions this case asks,
                # from the other direction, and it is why the colon-space test
                # above is in the same paragraph as this one. Read out of the
                # binary rather than reasoned from a YAML specification.
                if ($fmVal -match '^[{}\[\]*&#!|>%@`]') {
                    $fmBad += "${fpName}: '$fmKey' is UNQUOTED and opens with a character the CLI's own must-quote test reserves - '$($fmVal.Substring(0,1))'"
                }
            }
            $fmLineNo++
        }
        # A block scalar left open when the block ENDS is the same empty field
        # as one closed by a following key, and it is the likelier of the two:
        # `description: >` as the last line of a frontmatter block.
        if ($fmScalarKey -ne '' -and $fmScalarBody -eq 0) {
            $fmBad += "${fpName}: '$fmScalarKey' opens a block scalar at the end of the block and no indented line follows it, so the field is EMPTY"
        }
        # ROLES ONLY. docs/roles.md:55 - "Must match the filename stem" - and
        # nothing in this repository enforced it before this line. A role whose
        # name disagrees with its filename is dispatched under one spelling and
        # shadowed under the other. Command pages carry no `name`.
        if ($fp -like '*\agents\*') {
            $fpStem = [IO.Path]::GetFileNameWithoutExtension($fp)
            if (-not $fmKeys.ContainsKey('name')) {
                $fmBad += "${fpName}: no 'name' key at all"
            } elseif ($fmBlock -match '(?m)^name:\s+(.+?)\s*$') {
                # QUOTES STRIPPED BEFORE THE COMPARE. `name: "lw-scribe"` is
                # valid YAML and resolves to the same string; a case that failed
                # it would be a guard going red on a correct file, which is the
                # thing this suite's own S13/S14 prose says teaches the next
                # contributor to loosen a rule.
                $fmName = $Matches[1].Trim('"', "'")
                if ($fmName -ne $fpStem) {
                    $fmBad += "${fpName}: name is '$fmName' but the filename stem is '$fpStem' - docs/roles.md's role-contract table requires them to match"
                }
            }
        }
    }
    Add-Result ("S14 every agents/, commands/, output-styles/ and skills/ frontmatter block parses - flat key: value, or a key opening a block scalar with a body ($($fmFiles.Count) file(s))") `
        ($fmMissing.Count -eq 0 -and $fmFiles.Count -gt 0 -and $fmBad.Count -eq 0) `
        ($(if ($fmMissing.Count) { "no directory at $($script:PayloadRel)/$($fmMissing -join ', '), so this case did not read what it claims to read. " } else { '' }) +
         $(if ($fmFiles.Count -eq 0) { 'zero .md files were enumerated, so nothing was linted - an empty set is not a pass. ' } else { '' }) +
         $(if ($fmBad.Count) { "$($fmBad.Count) defect(s), each of which loads the file with its fields silently dropped: " + ($fmBad -join ' | ') + '. ' } else { '' }) +
         "linted $($fmFiles.Count) file(s) under " + ((($fmDirs | ForEach-Object { "$($script:PayloadRel)/$($_.rel)/" }) + @("$($script:PayloadRel)/skills/*/SKILL.md")) -join ', '))

    # S15. #316. THE OWNER'S DECISION ABOUT `force-for-plugin`, HELD BY A MACHINE.
    #
    #     WHAT SHIPS. `output-styles/` returns to the payload with ONE style.
    #     The component loader in the 2.1.263 bundle reads
    #     ["commands","agents","skills","output-styles","themes"], so a style
    #     under that directory reaches every install with the plugin enabled and
    #     appears in the /config picker as `<plugin>:<style name>` - here,
    #     `lw-watchtower:lw-orchestrator`. Nothing selects it for the operator.
    #
    #     THE TWO KEYS THIS CASE HOLDS, AND WHY EACH IS A DECISION RATHER THAN A
    #     PREFERENCE.
    #
    #     `keep-coding-instructions: true` MUST BE PRESENT. The binary's own
    #     describe string: "If true, the default coding instructions stay in the
    #     system prompt alongside this style." Without it the style REPLACES
    #     them, and this style is a delegation discipline - four screens of it -
    #     not a complete set of working instructions. Shipping it absent would
    #     silently strip a consumer's assistant of its coding instructions on
    #     the day they picked a style that promised to change how work is
    #     ROUTED.
    #
    #     `force-for-plugin: true` MUST BE ABSENT. It applies the style
    #     automatically to every install with this plugin enabled, silently
    #     overriding the consumer's own `outputStyle` - the same objection that
    #     argued against arming a gate by default - and it is marked `@internal`
    #     in the binary ("only meaningful for plugin-bundled styles; ignored for
    #     user styles"), so it can change without notice. It is an OWNER
    #     decision and was not taken by the lane that shipped this. A line in a
    #     document saying "we chose not to" is undone by one well-meaning edit;
    #     this is the same sentence, asserted.
    #
    #     WHY THIS IS NOT COVERED BY S14 EVEN THOUGH S14 NOW READS THE SAME
    #     DIRECTORY. S14 asks whether the block PARSES. This asks what the block
    #     SAYS. A style with both keys spelled correctly and `force-for-plugin`
    #     set to true is perfectly well-formed and is exactly the thing that must
    #     not ship.
    #
    #     AND NOTHING ELSE CHECKS EITHER. Read out of the 2.1.263 bundle: the
    #     strict frontmatter schema for `output-style` is applied to USER styles
    #     only; the plugin loader reads the fields it knows and validates
    #     nothing, so a misspelled key on a plugin style is silently ignored with
    #     no message anywhere. That is the whole reason this case checks the
    #     spelling this repository ships rather than trusting it.
    #
    #     AN EMPTY DIRECTORY IS A FAILURE, AND THAT IS THIS CASE'S RED-FIRST.
    #     RED AT 29124d8, which is this branch's parent and has no
    #     output-styles/ directory at all: the case was written and run BEFORE
    #     the style file existed, failed naming the absent directory, and went
    #     green when the file landed. The order is the proof and it is on the
    #     PR. A case that passed over an empty directory would be green on the
    #     tree where the feature ships nothing at all.
    $osDir   = Join-Path $script:RepoRoot ($script:PayloadRel + '\output-styles')
    $osFiles = @()
    if ([IO.Directory]::Exists($osDir)) { $osFiles = @([IO.Directory]::GetFiles($osDir, '*.md')) }
    $osNoKeep  = @()
    $osForced  = @()
    foreach ($op in $osFiles) {
        $opName = Split-Path -Leaf $op
        $opText = ''
        try { $opText = [IO.File]::ReadAllText($op) } catch { }
        $opFm = if ($opText -match '(?s)^---\r?\n(.*?)\r?\n---\r?\n') { $Matches[1] } else { '' }
        if ($opFm -notmatch '(?m)^keep-coding-instructions:\s*true\s*$') { $osNoKeep += $opName }
        if ($opFm -match  '(?m)^force-for-plugin:\s*true\s*$')           { $osForced += $opName }
    }
    Add-Result ("S15 every output-styles/*.md keeps the coding instructions and forces itself on nobody ($($osFiles.Count) file(s))") `
        ($osFiles.Count -gt 0 -and $osNoKeep.Count -eq 0 -and $osForced.Count -eq 0) `
        ($(if (-not [IO.Directory]::Exists($osDir)) { "there is no $($script:PayloadRel)/output-styles/ directory, so this case asked nothing of anything - an empty set is not a pass. " } elseif ($osFiles.Count -eq 0) { "$($script:PayloadRel)/output-styles/ holds no *.md, so nothing was checked. " } else { '' }) +
         $(if ($osNoKeep.Count) { "style(s) without 'keep-coding-instructions: true', which REPLACES the default coding instructions rather than adding to them: $($osNoKeep -join ', '). " } else { '' }) +
         $(if ($osForced.Count) { "style(s) carrying 'force-for-plugin: true', which applies the style to every install with this plugin enabled and silently overrides the consumer's own outputStyle. That is an OWNER decision and is not taken here: $($osForced -join ', '). " } else { '' }) +
         "checked $($osFiles.Count) file(s) under $($script:PayloadRel)/output-styles/")

    # S16. #168. THE SKILLS DIRECTORY IS TRACKED, AND RULE 6 IS ASKED OF IT.
    #
    #     TWO PROPERTIES, ONE CASE, BECAUSE EITHER ONE ALONE IS A GREEN LINE
    #     OVER NOTHING.
    #
    #     (a) TRACKED. Every enumeration in this file starts at `git ls-files`
    #     (:670, :672) and so does tests/portability_scan.ps1 (:845),
    #     tests/doc_claims.ps1 (:566) and lw-watchtower/bin/lwg-doctor.ps1
    #     (:997). An UNTRACKED skills/ is invisible to all four: each prints a
    #     green line over files none of them opened, which is the
    #     "reports healthy while doing nothing" shape S6 and S7 exist to refuse.
    #     A skill is shipped payload - a stranger receives it and a model reads
    #     it and acts on it - so it is not optional that the guards can see it.
    #
    #     (b) IN RULE 6'S SCOPE. `deleted-script` is scoped, and its own `why`
    #     for covering commands/ and agents/ - "a model reads these files and
    #     acts on them, which makes them the higher-risk half of the payload" -
    #     is true of a SKILL.md word for word. A skill page naming a script this
    #     branch deleted is the same defect on the same surface.
    #
    #     WHY NOT RULE 7 AS WELL, since that one is also scoped and also about
    #     what a model is told it may do. Because rule 7 is anchored to
    #     `^\s*tools:\s` and a SKILL.md HAS NO `tools:` KEY - the skill schema
    #     uses `allowed-tools` / `disallowed-tools`. Adding skills/ to rule 7's
    #     scope would satisfy S7's "was applied to at least one file" boolean
    #     while the needle could never match: a switch wired to nothing, inside
    #     the guard that exists to catch switches wired to nothing. The
    #     skills-shaped analogue of rule 7 is a different needle and belongs to
    #     whoever writes it. Rule 7's scope is deliberately unchanged.
    #
    #     ENUMERATED FROM THE INDEX, not from a hardcoded name. A second skill
    #     landing beside lw-handoff is asked the same question with no edit
    #     here, and a skills/ directory that empties out fails rather than
    #     quietly asserting nothing.
    $skillsPrefix = $script:PayloadRel + '/skills/'
    $skillFiles   = @($payloadList | Where-Object { $_ -like ($skillsPrefix + '*') })
    $rule6        = @($Rules | Where-Object { $_.id -eq 'deleted-script' })[0]
    $skillsOut    = @()
    if ($null -eq $rule6) {
        $skillsOut += "the rule 'deleted-script' is not in the rule table at all, so its scope could not be read"
    } else {
        foreach ($sf in $skillFiles) {
            if (-not (Test-RuleInScope -Rule $rule6 -Rel $sf)) { $skillsOut += $sf }
        }
    }
    Add-Result ("S16 skills/ is tracked and rule 6 is asked of every file in it ($($skillFiles.Count) file(s))") `
        ($skillFiles.Count -gt 0 -and $skillsOut.Count -eq 0) `
        ($(if ($skillFiles.Count -eq 0) { "git ls-files -- $($script:PayloadRel)/ lists NOTHING under skills/. Either the directory does not exist yet, or it exists on disk and was never `git add`ed - and an untracked payload directory is scanned by no guard in this repository and by no check in bin/lwg-doctor.ps1, all four of which enumerate the index. " } else { '' }) +
         $(if ($skillsOut.Count) { "$($skillsOut.Count) tracked skill file(s) are OUTSIDE rule 6 (deleted-script)'s scope, so a skill page naming a deleted script is never asked about: " + ($skillsOut -join ', ') + ". Add '$($script:PayloadRel)/skills/*' to that rule's scope. " } else { '' }) +
         "read $($skillFiles.Count) tracked file(s) under $($script:PayloadRel)/skills/")

    # S17. #179. EVERY VENDORED FILE IN THE PAYLOAD IS NAMED IN THE NOTICES.
    #
    #     WHAT LANDED, AND WHY IT NEEDS A MACHINE. #179 vendored six
    #     third-party bodies into this payload - four under skills/ and two
    #     under context/stack/ - taken from FIVE upstream repositories, held by
    #     FIVE different copyright holders, under THREE licence types: MIT
    #     (three separate holders), CC BY 4.0, and Apache-2.0. Every one of the
    #     three conditions redistribution on a notice travelling WITH the copy.
    #     lw-watchtower/THIRD-PARTY-NOTICES.md is how this
    #     payload discharges them, and a notices file that nothing checks
    #     is a notices file that is correct on the day it is written and stale
    #     on the day the next skill lands. That is not a style complaint: an
    #     unlisted vendored file is a distribution with the attribution
    #     stripped off it, which is the one thing every one of those licences
    #     forbids by name.
    #
    #     HOW A VENDORED FILE IS TOLD FROM A HOUSE FILE, AND IT IS DERIVED
    #     FROM THE TREE RATHER THAN LISTED. Every file this project wrote for
    #     this plugin carries the house block that opens
    #     `Shipped by the LW-WATCHTOWER plugin`; #179's own rule is that a
    #     VENDORED file carries no such block, because inserting one would
    #     modify a byte-identical copy and put this project's name at the top
    #     of somebody else's text. So header-absence IS the vendored marker,
    #     and skills/lw-handoff/ - original work, and stated as such in the
    #     CHANGELOG rather than in the notices - is excluded by construction
    #     rather than by name. A hardcoded list here would be the defect this
    #     whole file exists to prevent.
    #
    #     THE MATCH IS THE PAYLOAD-RELATIVE PATH, SPELLED. Not the directory,
    #     not the skill name: `skills/task-observer/references/signals.md`
    #     rather than `task-observer`. A prefix rule would be satisfied by a
    #     sentence mentioning the directory in passing, and seven reference
    #     files under one skill are seven separate copies of somebody's work.
    #     The notices file carries the path list in its per-skill blocks, so
    #     the two agree by construction and drift on either side is red.
    #
    #     ENUMERATED FROM THE INDEX, like every other case here - `$payloadList`
    #     is `git ls-files -- lw-watchtower/`. A vendored file present on disk
    #     and never `git add`ed is invisible to this case, which is correct:
    #     it is also invisible to the marketplace copy, so it is not
    #     distributed and no notice is owed for it. S16 is the case that
    #     catches an untracked skills/ directory.
    #
    #     BASELINE 010a550. RED AT 010a550, and the proof is the honest one
    #     rather than the convenient one. Written and run with the thirteen
    #     vendored files staged and no notices file in the tree, this case
    #     reported "13 vendored of 14 file(s)" and named every one of the
    #     thirteen as shipped with no attribution beside it; the suite exited
    #     1. It went green only when lw-watchtower/THIRD-PARTY-NOTICES.md
    #     landed carrying all thirteen paths. THE ONE FILE IT DID NOT NAME was
    #     skills/lw-handoff/SKILL.md, which carries the house header - so the
    #     original/vendored split was measured on that run, not assumed.
    #
    #     AN EMPTY VENDORED SET IS A FAILURE, and the reasoning is the same
    #     "an empty set is not a pass" S14 and S16 both carry. The notices
    #     file is an obligation CREATED by the vendored files; a run that
    #     found none checked no obligation and would print a green line over
    #     nothing. If this payload ever stops vendoring, THIS CASE AND THE
    #     NOTICES FILE ARE DELETED TOGETHER - that is the correct edit, and it
    #     is a different act from letting the case quietly assert nothing.
    $noticesRel   = $script:PayloadRel + '/THIRD-PARTY-NOTICES.md'
    $vendorRoots  = @(($script:PayloadRel + '/skills/'), ($script:PayloadRel + '/context/stack/'))
    $noticeCands  = @($payloadList | Where-Object {
        $cand = $_
        ($cand -like '*.md') -and (@($vendorRoots | Where-Object { $cand -like ($_ + '*') }).Count -gt 0)
    })
    $houseMarker  = 'Shipped by the LW-WATCHTOWER plugin'
    $vendoredRel  = @()
    $noticeOut    = @()
    foreach ($nc in $noticeCands) {
        $ncPath = Join-Path $script:RepoRoot ($nc -replace '/', '\')
        if (-not [IO.File]::Exists($ncPath)) { $noticeOut += "$nc is tracked and is not on disk, so this case could not read it"; continue }
        $ncText = ''
        try { $ncText = [IO.File]::ReadAllText($ncPath) } catch { $noticeOut += "$nc could not be read"; continue }
        if ($ncText -notlike ('*' + $houseMarker + '*')) { $vendoredRel += $nc }
    }
    $noticesTracked = @($payloadList | Where-Object { $_ -eq $noticesRel }).Count -gt 0
    $noticesText    = ''
    if ($noticesTracked) {
        $noticesPath = Join-Path $script:RepoRoot ($noticesRel -replace '/', '\')
        if ([IO.File]::Exists($noticesPath)) {
            try { $noticesText = [IO.File]::ReadAllText($noticesPath) } catch { $noticesText = '' }
        }
    }
    if (-not $noticesTracked) {
        $noticeOut += "$noticesRel is not tracked under the payload at all. The vendored files below are copied to every consumer with no attribution travelling beside them"
    } elseif ([string]::IsNullOrWhiteSpace($noticesText)) {
        $noticeOut += "$noticesRel is tracked and is empty, which discharges nothing"
    } else {
        foreach ($vr in $vendoredRel) {
            $vrPayloadRel = $vr -replace ('^' + [regex]::Escape($script:PayloadRel) + '/'), ''
            if (($noticesText -notlike ('*' + $vr + '*')) -and ($noticesText -notlike ('*' + $vrPayloadRel + '*'))) {
                $noticeOut += $vr
            }
        }
    }
    Add-Result ("S17 every vendored file under skills/ and context/stack/ is named in THIRD-PARTY-NOTICES.md ($($vendoredRel.Count) vendored of $($noticeCands.Count) file(s))") `
        ($noticeCands.Count -gt 0 -and $vendoredRel.Count -gt 0 -and $noticeOut.Count -eq 0) `
        ($(if ($noticeCands.Count -eq 0) { "git ls-files -- $($script:PayloadRel)/ lists no .md under skills/ or context/stack/ at all, so this case read nothing. " } else { '' }) +
         $(if ($noticeCands.Count -gt 0 -and $vendoredRel.Count -eq 0) { "every .md under skills/ and context/stack/ carries the house '$houseMarker' block, so this case found NOTHING vendored and asserted nothing - an empty set is not a pass. If this payload has genuinely stopped vendoring, delete this case and $noticesRel together. " } else { '' }) +
         $(if ($noticeOut.Count) { "$($noticeOut.Count) vendored file(s) are shipped to every consumer with no entry in $noticesRel, which is a copy distributed without the attribution its licence requires: " + ($noticeOut -join ', ') + ". Add a block naming the path, the upstream URL, the commit, the SPDX id and the licence text - do not delete the file to make this green. " } else { '' }) +
         "read $($noticeCands.Count) tracked .md under $($script:PayloadRel)/skills/ and $($script:PayloadRel)/context/stack/, of which $($vendoredRel.Count) carry no house header and are therefore vendored")

    Add-Result 'S9  no out-of-payload record names a file that is now inside the payload' `
        ($recordInPayload.Count -eq 0) `
        ("$($recordInPayload.Count) path(s) recorded above as out of the payload are now tracked under $($script:PayloadRel)/, so they ARE shipped again and the rules that used to excuse them no longer exist: " + ($recordInPayload -join ', ') + ". Fix the file or move it back out - do not edit the record.")

    # ----------------------------------------------------------------------
    # RULE CASES - one per rule, over the payload, minus the ledger
    # ----------------------------------------------------------------------
    # THE CASE NAME STATES THE SCOPE WHEN THERE IS ONE, and this is not
    # cosmetic. `deleted-script` is asked of bin/, lib/, hooks/, statusline/,
    # context/, config.json and .claude-plugin/ - and deliberately NOT of
    # commands/ or agents/, because a page there still names a deleted library
    # and a fixer may not edit a document. A green line reading "the payload
    # carries no shipped file naming a script this branch deleted" is then a
    # broader claim than the run made: two directories of text a model reads
    # were never asked. The scope is in the sentence, so the green line is true.
    foreach ($r in $Rules) {
        $rHits = @($hits | Where-Object { $_.rule -eq $r.id })
        $sites = (($rHits | ForEach-Object { "$($_.file):$($_.line)" }) -join ', ')
        $where = if ($r.ContainsKey('scope')) {
            ' [asked only of ' + (($r.scope | ForEach-Object { $_ -replace ('^' + [regex]::Escape($script:PayloadRel) + '/', '') }) -join ' ') + ']'
        } else { '' }
        Add-Result ("R   the payload carries no " + $r.name + $where) `
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

Write-Output ("RESULT: {0} of {1} case(s) passed in {2} ms   ({3} payload file(s) matched against the rules, {4} tracked file(s) read for markers, {5} ledger'd site(s), {6} historical mention(s))" -f `
    $script:Pass, $script:Results.Count, [int]$sw.Elapsed.TotalMilliseconds, $payloadRead, $fileCount, $ledgered.Count, $historical.Count)

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
    Write-Output 'The payload is lw-watchtower/, declared by .claude-plugin/marketplace.json as'
    Write-Output '"source": "./lw-watchtower". A file named above is copied to every consumer.'
    Write-Output 'Fix the FILE, or move it out of the payload subtree - do not add a ledger entry'
    Write-Output 'to make this green.'
    Write-Output 'EXIT: 1'
    exit 1
}

Write-Output ''
Write-Output 'Every tracked file was read and no unledger''d disclosure is in the payload,'
Write-Output 'which is the lw-watchtower/ subtree and not the whole repository.'
Write-Output 'Read that as "these seven shapes are absent", not as "the payload is safe to'
Write-Output 'publish" - this guard knows the disclosures it was told about and no others.'
Write-Output 'The sixth is scoped to the payload and is now asked of commands/, agents/ and'
Write-Output 'output-styles/ too,'
Write-Output 'which is the surface it was written for. tests/ stays out, stated at the rule.'
Write-Output 'The seventh is narrower still - agents/ alone - and it is pinned to a CLI build'
Write-Output 'rather than to a contract: it names four tools that build gates off by default.'
Write-Output 'EXIT: 0'
exit 0
