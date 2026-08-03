# Handoff — 31 July 2026 (v0.3.0 release)

## Where things are

Everything is on `origin/main`. Local and remote are in sync — nothing lives only on one laptop.

This file was rewritten on top of `2a8c17c` and lands as the **release commit** for `v0.3.0`. The
three things earlier drafts of this file listed as outstanding are all done: **the commit-author
identity rewrite has run**, **the written UAT report is in the tree** (`docs/uat-report.md`), and
**`v0.3.0` is tagged and released**. The version string reads `0.3.0` everywhere that declares it,
and `CHANGELOG.md` carries a promoted `## [0.3.0] — 2026-07-31` section which is also the release's
published notes.

**One ordering note, because it is visible in the checklist and looks like a gap if unexplained.**
This file was first written *in* the release commit, and the tag necessarily landed *on* that commit,
minutes later — so a run taken while that paragraph was being written showed `P8-tag` as NOT STARTED
and `PE-sitrep` as in progress. Both are DONE now. `P8-tag` flipped when the tag was pushed;
`PE-sitrep` flipped for a different reason than the original note predicted — its evidence was a
commit-subject match, which any commit mentioning the word satisfied, and it was replaced the same
day with a probe for the two files the feature is made of. **This file is now one commit ahead of the
tag**, carrying the post-release correction recorded in `CHANGELOG.md` and in `## Still open, and
known`. See `## Final tallies` below.

The thirteen `worktree-agent-*` branches this file reported on 31 July 2026 have since been swept.
`git ls-remote origin` on 3 August 2026 returns **one branch head**, `refs/heads/main`. The earlier
sentence claimed **14 branch heads** and advertised that it had been re-verified rather than carried
forward, which is what made it worse than an ordinary stale number: the advertisement was the part
that stopped anyone re-checking. Beyond that one head,
`origin` serves **2 tag refs** — `refs/tags/v0.3.0` and its peeled `^{}` — and one ref this
repository does not own: **`refs/pull/1/head`**, the head of a closed Dependabot pull request, at
`db74ec2`. Its ancestry still carries all **76 pre-rewrite commits** with the owner's personal
address on author and committer. A push cannot delete a pull ref and GitHub does not collect one
when the PR closes, so the identity rewrite could not reach it; a default clone never fetches
`refs/pull/*`, so nobody sees it without asking for it by name. **Resolving it is a precondition of
going public** — a GitHub Support sensitive-data purge, or deleting and recreating the repository.
See `## Still open, and known`.

## Starting on another laptop

1. **Clone it anywhere.** No path in this repo is tied to a machine, and CI checks that on every
   build — `tests/portability_scan.ps1`, with the rule written up in `docs/portability.md`.
2. Run `/lw-watchtower:setup`. **It has three sections, not two-plus-a-third:** `permissions`,
   `statusline`, `hooks` — in that order, each with its own diff and its own yes. `permissions`
   installs nothing; the deny table is empty, so that section can only report "nothing to add".
   **Agent roles are not a section.** They are `-AgentRoles yes|no`, a flag folded into the `hooks`
   step (`bin/lwg-setup.ps1`'s `-Section` `ValidateSet` is `permissions`, `statusline`, `hooks` —
   there is no fourth value). An earlier version of this file described "three sections: status
   line, hook wiring, agent roles" as if agent roles were their own confirmation step. They never
   were; that description was wrong and is corrected here.
3. Start one Claude Code session, so the plugin's state directory gets created.
4. Run `/lw-watchtower:doctor`. On the machine that did this pass's work it reports **9 passed, 0 warnings,
   0 failures**, re-run for this file rather than quoted from memory. A fresh install elsewhere
   should also land on 9 of 9 once `/lw-watchtower:setup` has written the `statusline` section, but that
   has not been re-verified from a clean clone on a second machine.

It needs Windows PowerShell 5.1. `pwsh` is not the same thing and will not do.

**If you check `git tag -l v0.3.0` on a shallow or `--no-tags` clone and see nothing, that is not
evidence the tag was never cut.** `git tag -l` exits `0` with empty stdout when the ref namespace
simply was not fetched, and `checklist.json`'s `P8-tag` evidence rule cannot tell that case apart
from "no tag exists" — **and that has been false since 31 July 2026.** `bin/lwg-evidence.ps1` now
carries the empty-stdout knob: when a rule proves an item **from** its output via `stdout_match`,
empty output returns `unverified` rather than a pass or a fail, because "there was nothing to match
against" is not an answer either way. So read a `P8-tag` row on a clone with no tag refs as
`UNVERIFIED`, not as `NOT STARTED` — that row can no longer render `NOT STARTED` at all. The tag does
exist; `git ls-remote --tags origin` is the check that does not depend on what your clone fetched.

## What this plugin is now

**An advisory layer. It blocks almost nothing, and that is the finished state, not a gap.**

- **12 commands:** `checklist`, `config`, `delegate`, `doctor`, `plain`, `resolve`, `setup`,
  `sitrep`, `status`, `uninstall`, `update`, `verbosity`.
- **10 modules, 9 of them active.** Nine only observe — `failure_capture`, `context_pressure`,
  `verification_gate`, `self_health`, `log_rotation`, `docs_coupling`, `git_hygiene`,
  `mission_drift`, `context_injection`. They report, log or advise; the action happens anyway.
  `verification_gate` keeps the word "gate" in its name and is not one — read the name as historical.
- **1 gate, and it ships switched off.** `delegate_gate` (`lib/gate_delegate.ps1`) refuses `Edit`,
  `Write`, `NotebookEdit`, `Bash` and `PowerShell` on the main chat thread, so work goes to subagents. It turns on
  only with `/lw-watchtower:delegate on`. It reads no path and no command, and nothing it decides consults
  the tool name — it reads that only to name the refused tool in the denial text. **It is not a
  security control.**
- **Nothing inspects a shell command, a path or a credential**, and `permissions.deny` is empty.
  Force pushes, hard resets, recursive deletes, repo deletion, writes to `.git/`, writes of a live
  token — none are examined by anything here.
- **8 files in `tests/`, and five of them test behaviour.** `tests/gate_delegate.ps1` is **93 of 93**
  — 58 exercise the gate's rule, 7 (section I) are aimed at the **fast path**, 3 (section M) are
  aimed at the CLI's matcher rather than at the gate, and the rest were added since. The section-I count was 8 until 31 July 2026, when one of its cases moved
  into section J. **An earlier version of this file said those section-I cases exist to catch the
  fast path silently falling through to the slow path. They do not, and cannot** — the suite's own
  header says so twice: a fast path deleted entirely would leave every case in section I green, and
  a change that makes it silently stop *running* is not caught by that file at all. The fast path's
  only affirmative outcome is byte-identical to the slow path's, so from outside the process the two
  are indistinguishable. What section I does establish is that a config of each of those shapes
  still gets the **right answer**, whichever path produced it; and because the fast path can only
  ever *allow*, only the deny-expecting cases can catch the one error that matters — proving the
  switch off while it is on.
  `tests/setup_merge.ps1` is **124 of 124**, driving the real `bin/lwg-setup.ps1` in a real child
  process against throwaway settings files. On `statusline`: unrelated top-level keys keep their
  value and order, exactly one backup is taken holding the original bytes, a stale `BaseHash` is
  refused, a second run is a no-op, rollback restores byte for byte. On `hooks`: a marketplace
  install planted in the layout the CLI actually writes is detected, so the section plans nothing
  and a forced `-HookMode standalone` still warns about duplicate firing; and a registration of the
  same script under a **different root** is reported rather than added beside it. It also runs
  `statusline/statusline.ps1` itself, from a copy under a scratch profile, to check that a
  marketplace root resolves at all. Five cases are labelled `CONTROL` and pass before the fix they
  sit beside as well as after it — four at `fd8d023`, and the relocated-cache one only against the
  working tree immediately before its own fix. `permissions` writes nothing.
  `tests/stop_behaviour.ps1` is **169 of 169** across the two hooks that fire at every turn end and
  the `lib/common.ps1` helpers they share, and is
  the only thing in this repo that exercises an **observing** module: it runs `mission_drift` end to
  end — the fire condition, the suppressors (`min_files`, `require_outside_root`, `max_scan_bytes`,
  `stop_hook_active`), and specifically the **pivot property** — and it pins two supervisor bugs that
  had already shipped with no case behind them: a dedupe that silently stopped deduping on a
  multi-entry array, and a one-element failed-task list that logged as `null` and kept the health
  indicator green through a real failure. Its section A also reaches `Get-LwgRedacted`, this
  plugin's only redaction control, which had no test of any kind until 1 August 2026 and was
  carrying three defects when one was written — surrogate-splitting truncation, raw control
  characters reaching a fixed-column console report, and a trailing newline escaped into the
  message. `tests/uninstall_footprint.ps1` is **22 of 22** against
  `bin/lwg-uninstall.ps1`, asserting on the filesystem as well as on the report, and is the only
  suite that tests a **deletion**. It also holds the uninstaller's ATTRIBUTION - all 181 rules the
  installer wrote before 30 July 2026, run through `Test-MirroredDeny` from
  `tests/fixtures/deny_canonical.txt`, which is the only thing that makes that function's "the only
  code left in the repo that knows what those rules looked like" a checkable sentence. `tests/evidence_states.ps1` is **47 of 47** against
  `bin/lwg-evidence.ps1` — that a probe which could not run renders `UNVERIFIED` and one that ran and
  failed still renders `NOT STARTED`. `tests/portability_scan.ps1`, `tests/workflow_guard.ps1` and
  `tests/doc_claims.ps1` check tracked files and their stated counts and assert nothing about
  behaviour. All eight were re-run for this pass and all eight exit 0. **Three of the nine observing
  modules — `verification_gate`, `self_health`, `context_injection` — are still exercised by nothing
  at all.** This line said SEVEN until 3 August 2026, when `context_pressure`, `docs_coupling`,
  `git_hygiene` and `log_rotation` gained cases in `tests/stop_behaviour.ps1` and nine tracked pages
  went on saying those four were untouched. Four of the six that are covered have one to three cases
  on at most two properties apiece — `context_pressure` 2, `docs_coupling` 2, `log_rotation` 3,
  `git_hygiene` 1 — so "covered" here means "no longer untouched" and nothing stronger.
- **CI is one job, `fast-checks`, with ten check steps** after checkout: JSON validity, PowerShell
  parse, workflow guard, the delegate gate suite, the installer merge suite, the stop-hook behaviour
  suite, the uninstaller footprint suite, the evidence-state suite, the portability scan, and the
  documentation-claim guard. Its display name is still `Fast checks (JSON + PowerShell parse)` **on
  purpose** — a required status check on `main` matches that name, so renaming it would silently stop
  satisfying the requirement. **Every push to `main` runs all ten**, with no path filter on either
  trigger.
- **The delegate gate got a fast path, measured on one machine.** The off-path cost — every gated
  tool call while `interaction.delegate` is off, which is every operator by default — dropped from a
  652 ms median to 436 ms, about **216 ms saved**, by proving the switch is off from raw text before
  loading the JSON engine. **The deny path got measurably slower** (roughly 743 ms before, roughly
  868 ms now), because with the switch on the fast path runs, fails to prove the switch off, and the
  slow path then does everything it always did on top. That is the accepted trade: the cost moved
  onto the operator who deliberately armed the gate. Read both figures as one machine's medians, not
  as constants — `docs/modules.md` and `docs/faq.md` carry the full distributions.

`docs/limitations.md` is the full, blunt version of this section. `docs/faq.md` answers the
questions it raises.

## The `hq-*` → `lw-*` rename is finished

**By owner directive: no agent named `hq-*` exists anywhere, on any machine this plugin knows about.**

- The six user-scope role files (implementer, scribe, healer, verifier, orchestrator, explorer) were
  renamed to `lw-*` and each given an explicit `lw-class` frontmatter key — `work`, `verify` or
  `neutral` — **outside this repository**, on the machine that holds them, and only after that was
  observed working did the four old names get struck from `config.json`'s `verification_gate` arrays
  and the matching `-Default` arrays in `lib/stop_advisories.ps1`. That order was load-bearing —
  reversing it would have unclassified all six roles at once, silently, which is the exact defect
  `verification_gate` exists to catch.
- **Every generic name stays** — `implementer`, `scribe`, `engineer`, `healer`, `verifier`,
  `qa-agent`, `code-review`, `security-adversarial-review` — because none of those has a role file to
  declare `lw-class` in, and the arrays are the only thing that can ever classify them.
- The old compatibility probes in `statusline/statusline.ps1` and `bin/lwg-setup.ps1` are gone, and
  the status line's orchestrator segment now matches `^(lw-)?orchestrator$` instead of a pattern that
  never matched the shipped `lw-orchestrator` in the first place.
- **The cross-machine consequence is accepted, not overlooked.** Any other machine still carrying
  role files under the old spelling loses classification for them the moment it takes this config:
  each resolves to a file declaring no `lw-class` and to no name in either array, which is *no
  information* — `verification_gate` stops seeing that operator's work **and** their verification
  until the rename is repeated there too. Recorded at `config.json`'s `$classifier_comment` and in
  `docs/roles.md`.

## Why the gates went

On **30 July 2026**, by owner decision, the destructive-command gate and then the secret-scanning
gate were both removed in full, along with the 181 `permissions.deny` rules the installer used to
write and the trip ledger that tracked denials. The short reason: four attempts were made to fix one
false positive in the command gate. Two were reverted, and between them they opened five new security
holes. The test suite was 67 of 67 green the whole time and never caught one of them — every hole was
found by somebody deliberately trying to break the gate. The standing conclusion is that a gate with
a green suite and no independent break-attempt should be assumed broken.

**`docs/gates-removed.md` is the durable record.** Read it before adding any gate. That conclusion
applies to `delegate_gate` too — its suite being 93 of 93 green is worth exactly what the paragraph
above says it is worth, which is why 7 of those 93 (section I) go at the fast path rather than adding
more of the same shape. The total in this sentence has gone stale twice and been corrected by hand
both times: it read 71 before the eight cases of section K, and 79 before section L's single case.
Section I's size read 8 until one of its cases moved into section J on 31 July 2026. No run of
`tests/doc_claims.ps1` caught any of the three, and the reason is worth knowing before you trust a
green run of it — this sentence names the MODULE, `delegate_gate`, and that guard only opens a
window on a suite's FILE name. Its header states that hole.

## The UAT, and the bug it found

**All 12 commands PASS, after one fix.** `docs/uat-report.md` is the written record, with a verdict
per command and the adversarial cases.

**The finding was real, and it was in the installer.** `bin/lwg-setup.ps1` declared a bare `param()`
block rather than `[CmdletBinding()]`, so PowerShell bound an unrecognised `-Something` as a
**positional** argument and discarded it in silence. A flag the script does not define was therefore
accepted and ignored. Measured against a throwaway profile:

```
-DryRun           DRY RUN COMPLETE ... would have written 15144 bytes
-DryRunn          WROTE: 15144 bytes, backup taken, exit 0, no warning
```

**One mistyped character turned a dry run into a real write, at exit 0, with no warning** — against
an installer whose founding promise is that nothing is written that was not shown first. Fixed by
adding `[CmdletBinding()]`, which makes an unknown flag a hard parameter-binding error. The fix is
the commit *"Stop a mistyped setup flag from turning a dry run into a real write"*.

**Three things about this UAT are recorded honestly rather than quietly.**

- **The UAT harness itself ran elevated.** That was measured, not assumed, and it is a deviation from
  this file's own test-safety standing order.
- **Every command under test was de-elevated** via `runas /trustlevel` before it ran, so the verdicts
  are from a normal-integrity process even though the harness around them was not.
- **Ten other scripts share the same silent-unknown-flag pattern.** They fail safe — all are
  read-only by default, so an ignored flag cannot cause a write the way it could in the installer.
  They are **recorded for review and deliberately not changed at release time**, because a
  ten-script parameter-binding change is not something to land in a release commit on the strength of
  one script's bug.

## The identity rewrite

**Done, and verified from outside the working copy.**

- **89 commits** — every commit reachable from every **branch** — had author and committer rewritten
  through a **mailmap**, applied by `git-filter-repo` **2.47.0**. That scope word was *any ref* until
  final verification of the release found it to be an overclaim; see `## Still open, and known`.
- **The invariants came through byte-identical**: tree hashes, author dates and commit subjects are
  unchanged. Only identity moved.
- **All 14 branch heads were force-pushed** on 2026-07-31.
- **A fresh clone shows exactly one identity**, `LEAPWare-HQ <leapware@outlook.com>`, on both the
  author and the committer of every commit.
- **CI is green on the rewritten tip.**
- **A full backup was taken before anything irreversible ran** — a mirror clone, a bundle of all
  refs, and the old→new commit map. **It lives outside this repository**, on the machine that
  performed the rewrite. No literal path for it appears in this file or anywhere else in the tracked
  tree: the portability scan reads every tracked file including this one, and a machine-specific path
  in prose is exactly what it exists to catch. `P3-backup` is `manual` evidence for the same reason —
  nothing inside the repo can attest to a backup that must live outside it.

**Every commit SHA in this project changed.** Short SHAs cited in `CHANGELOG.md`,
`docs/gates-removed.md`, `docs/roles.md` and `checklist.json` were remapped through the rewrite's own
commit map on the same day, and each replacement was verified to resolve before it was written down.
**Any SHA quoted in a document, issue or note written before 31 July 2026 is dangling** — the map is
in the backup, and it is the only way to translate one.

**`P3-identity` was rewritten twice and rescoped once more, and the last two are the ones worth
knowing about.** It
briefly asserted that *every* author and committer on *every* ref is the chosen address. `git log
--all` spans remote-tracking refs, so a single fetched bot branch failed that rule while nothing
about the rewrite had regressed — and that is measured, not hypothetical: Dependabot authored a
commit on a PR branch the same day, and `.github/dependabot.yml` schedules updates weekly. The rule
now asserts what the rewrite actually promised and can keep: **the owner's personal address appears
on no commit of any branch, and a default clone shows only the chosen address.** A rule that goes red
every week teaches people to ignore red rows. The word *branch* was *ref* until the correction
recorded in `## Still open, and known`.

## The tag and the release

- **`v0.3.0` is an annotated tag** on this release commit, pushed to `origin`.
- **A GitHub release is published for it**, titled `LW-GMHH v0.3.0`, with the `## [0.3.0] —
  2026-07-31` section of `CHANGELOG.md` as its notes. **That title keeps the old product name and is
  not a leftover.** It is the title of a release object that exists on GitHub under that string;
  renaming it here would make this line describe a release nobody can find. The rename to
  `lw-watchtower` landed after `v0.3.0` was published — see the `## [0.4.0]` entry in
  `CHANGELOG.md`.
- **This is the first tag this project has ever had.** `0.1.0` and `0.2.0` were declared in the
  manifest and worked under, never published — which is why neither carries a link at the foot of
  `CHANGELOG.md`. Read the note at the top of that file before treating any version heading in it as
  a publication date.
- **The repository is still PRIVATE at `v0.3.0`, by explicit owner decision.** Going public is
  deferred, not forgotten — `P8-visibility` carries a declared `blocked_reason` saying so.

## CI

The rewritten tip is green: run **30670565595**,
`https://github.com/LEAPWare-Software/LEAPWare-Watchtower/actions/runs/30670565595`. **The release commit
pushes its own run, which supersedes that one**; its URL belongs with the release verification rather
than in this file, because `P6-ci-green` only ever proves the *newest* run on `main` and a URL
written here would be stale the next time anything is pushed. It says nothing about the run before
it, and nothing about any branch other than `main`.

## Final tallies

From `bin/lwg-checklist.ps1`, re-run against this tree for the post-release correction commit — not
carried forward from a previous handoff:

**30 done · 0 in progress · 1 blocked · 9 UNVERIFIED · 0 not started (40 items).**
**19 of the 30 DONE items are qualified `[x*]`** — the probe passed *and* a caveat beneath it limits
what passing proves. That is up from 17 at the release commit: `PE-sitrep` gained a caveat when its
evidence was replaced, and `P3-identity` was already qualified but its caveat now also carries the
`refs/pull/1/head` correction.

**The two rows that moved as the release landed**, per the ordering note at the top of this file:
`P8-tag` (not started) flipped when the tag was pushed, and `PE-sitrep` (in progress) flipped on its
replacement file probe rather than on a commit subject.

**The 1 blocked row:**

- **`P8-visibility`** — repository visibility flipped to public, with branch protection immediately
  after. Deferred by owner decision; `blocked_reason` is declared in `checklist.json` rather than
  inferred. Branch protection cannot be configured on a private repo on the current plan in any case.
  **It now carries a second precondition**: the `refs/pull/1/head` exposure must be resolved before
  the visibility flip, not after it — see `## Still open, and known`.

**The 9 UNVERIFIED rows.** `UNVERIFIED` is a third state, not a quieter "not started" — these could
not be checked at all, and may or may not be finished. Do not count them either way.

- **`P3-backup`** — the backup exists and was used; nothing inside the repo can attest to something
  that must live outside it.
- **`P6-runner-groups`** — whether any self-hosted runner group is visible at org level. **The
  highest-severity item on the whole plan**, and nothing on this machine can check it: reading it
  needs org admin scope, and a 403 is indistinguishable from "no groups exist". Left unverified
  rather than misreported.
- **`P6-branch-protection`** — not configurable while the repo is private.
- **`P4-banner-test`** — the SessionStart banner is asserted by no automated test; silence would not
  fail the build.
- **`P0-abort-line`**, **`PA-proposal`**, **`PA-tripped-cmd`** — moot. Their subjects (the regression
  harness, the trip lifecycle, the `tripped` command) were removed with the gates on 30 July 2026.
  Left pointing at nothing rather than repointed at a substitute, because citing something else would
  manufacture a pass for work that was never done.
- **`PC-ask`**, **`PC-ask-inline`** — **closed unbuilt, and not buildable as specified.** The command
  halves shipped and the enforcement halves never did; both commands were removed. The reasoning is
  in `checklist.json` so nobody re-attempts them.

## Still open, and known

- **`refs/pull/1/head` still serves the pre-rewrite history, and no push can reach it.** The identity
  rewrite covered every commit reachable from every **branch**, which is what it promised. The head of
  closed pull request #1 is not reachable from a branch: GitHub serves it at `db74ec2`, and its
  ancestry holds all **76 pre-rewrite commits** carrying the owner's personal address on both author
  and committer. Pull refs cannot be deleted by a push and are not garbage-collected when the PR
  closes, so no force-push ever could have reached it. It is invisible to a default clone —
  `refs/pull/*` is outside the default fetch refspec, verified by cloning fresh and finding exactly
  one identity — and the repository is **private**, so the exposure is bounded by who can read the
  repository at all. Anyone who runs `git fetch origin refs/pull/1/head` gets the old history back.
  **It is nonetheless a precondition of `P8-visibility`**, whose `blocked_reason` now names it: the
  two remedies are a **GitHub Support sensitive-data purge** or **deleting and recreating the
  repository**, and both are owner actions that nothing in this repository can take or attest to.

- **CLOSED 31 JULY 2026 — the evidence engine's empty-stdout knob.** This item was listed here as
  still open until 3 August 2026 and was not: `bin/lwg-evidence.ps1` grew the knob on 31 July, and
  `checklist.json`'s `P8-tag` caveat records the change. The paragraph below is the item as it was
  written and is left for the record. `bin/lwg-evidence.ps1` supported exit code,
  `stdout_match` and `stdout_not_match` — nothing distinguished "the command ran and printed nothing"
  from "the command ran and printed something else." `P8-tag`'s shallow-clone case (see `## Starting
  on another laptop`) is the concrete instance; it is untested and deferred rather than being built
  mid-release as an engine change.
- **The installer's `hooks`-section merge path is tested for RECOGNITION, not for the writer.**
  `tests/setup_merge.ps1` now reaches `hooks`, but the cases there are about what the section
  *decides*: whether an existing install is seen, whether an existing registration under another
  root is seen. The byte-level writer properties — order, one backup, stale `BaseHash`, rollback —
  are still established on `statusline` only and merely *inherited* by `hooks`, since both go
  through the same `Save-Settings` path. `permissions` writes nothing so has nothing to merge-test.
- **Nothing proves the plugin layout the fixtures plant is the layout your CLI writes.** The
  marketplace paths in `bin/lwg-setup.ps1`, `statusline/statusline.ps1` and the suite's fixtures
  were read off this machine's `~/.claude` tree and out of a 2.1.x binary. That is evidence, not a
  published contract. Both files keep the old `plugins\repos` candidate for exactly that reason, and
  a build that lays it out a third way would blind the probe again.
- **Ten scripts still bind unknown flags positionally and discard them**, as the UAT section records.
  All fail safe today. That is a property of what they currently do, not a guarantee about what they
  will do after the next edit, and it is the first thing to fix after this release.
- **`mission_drift`'s trigger has still never been validated against real sessions.** This is a
  different claim from "the module is tested," which is now true. What no case in that suite can
  establish, because the judgement is not in the code, is whether the work a run actually warns about
  deserved the warning. The known false-positive class (a redirection with no concrete noun, followed
  by edits nobody named) is still live for every install with the module on by default.

Run `/lw-watchtower:checklist` for the current picture rather than trusting a number written here.

## Where the documentation is

Nothing below is optional reading for a new operator, and none of it was linked from this file until
1 August 2026.

| Read this | For |
| --- | --- |
| [`docs/limitations.md`](docs/limitations.md) | **First.** Everything this plugin does not do, cannot do and does not check, in one place. The blunt version of *What this plugin is now* above. |
| [`docs/install.md`](docs/install.md) | Both install routes, the missing-directory trap in the junction route, the separate status-line install, and why the doctor exits `2` on a fresh machine |
| [`docs/faq.md`](docs/faq.md) | The questions the limitations page raises, answered from the tree — including how to run all eight test files yourself |
| [`docs/testing.md`](docs/testing.md) | What each of the eight files in `tests/` establishes, the shared exit-code contract, the ten CI check steps, and what is uncovered |
| [`docs/architecture.md`](docs/architecture.md) | File layout, hook registrations, measured costs, the state directory, the status line |
| [`docs/modules.md`](docs/modules.md) | All ten modules, each with its own blind spots |
| [`docs/configuration.md`](docs/configuration.md) | `config.json` in full — the switchboard, per-repo overrides, thresholds |
| [`docs/commands.md`](docs/commands.md) | All twelve slash commands and their exit codes |
| [`docs/troubleshooting.md`](docs/troubleshooting.md) | Symptom-first index. Start here when something looks wrong |
| [`docs/gates-removed.md`](docs/gates-removed.md) | **Before adding any gate.** Why the last two went and what four failed fix attempts taught |
| [`docs/portability.md`](docs/portability.md) | The no-local-environment-dependencies mandate that fails the build |
| [`docs/roles.md`](docs/roles.md) | The six agent roles, the `lw-class` key, and when each is dispatched |
| [`docs/uat-report.md`](docs/uat-report.md) | The v0.3.0 acceptance record: every command, the adversarial cases, and the two installer defects it found |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | The two rules that fail your build, the regression-test rule, and the accuracy house rule |
| [`SECURITY.md`](SECURITY.md) | What is and is not a vulnerability here — read the scope section before reporting anything |
| [`docs/README.md`](docs/README.md) | The index, if you would rather browse than be pointed |

## Standing orders

- Debate a decision between a product view and a technical view, then give the recommendation in
  plain, brief, non-technical language.
- No warnings without fixes. Anything that is a risk gets fixed, not noted.
- **Test safety.** Never run a real destructive command. Never against a real binary. Never
  elevated. Use invented command names and assert on which rule fired. **The v0.3.0 UAT harness
  breached the "never elevated" clause** — recorded in `## The UAT, and the bug it found` rather than
  left for someone to discover.

## Incidents worth remembering

A worker testing a gate fix ran a recursive delete, believing it was hitting a stand-in. The
stand-in was not executable and the session was elevated, so the command destroyed Git's own `etc`
directory. It was repaired by reinstalling Git, which upgraded it from 2.54 to 2.55. The same run
also made a live repository-delete API call, which happened to return "not found".

That is why the test-safety standing order exists, and it matters more now than it did then: both
gate suites that used to enforce those conventions are gone.
