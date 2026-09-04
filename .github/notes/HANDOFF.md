<!-- doc-claims:ignore-file -->
<!--
  THIS PAGE IS A RECORD OF 31 JULY 2026 AND IS READ AS ONE (#256). The
  directory's README states the rule for everything in it: these are records of
  a moment, "read as records rather than corrected into agreement with today's
  tree". Two of the five files here already carry this marker. This one could
  not until 4 September 2026, and the obstacle was mechanical rather than
  editorial: three patterns in tests/doc_claims.ps1 had their ONLY site in the
  tree on this page, and a pattern that checks no claim anywhere aborts that
  guard. So the guard was holding one maintainer note permanently current, and
  the next person to file this page as the record it says it is would have taken
  `Documentation claims` down with an abort naming a regex. Those three patterns
  are deleted, with the derivation, in the same change as this marker; the
  duplicate shapes that read the same three numbers on live pages are untouched.

  WHAT THIS COSTS, stated rather than left to be found. Every number on this
  page is now unchecked, the correct ones included, and it is out of the wide
  set too - so the forbidden-phrasing and GM-promise rules no longer read it
  either. That is what exempting a file means, and it is the right trade only
  because nothing here is documentation: the payload is lw-watchtower/, this
  file is outside it and no longer ships, and a reader is sent to docs/ and to
  /lw-watchtower:doctor for what is true today. Wave D-N corrected every count
  on this page before the marker landed, so it is a record that was accurate on
  the day it was frozen rather than one frozen mid-drift.
-->

# Handoff — 31 July 2026 (v0.3.0 release)

**What this file is, and what it deliberately no longer carries.** This is the part of the 31 July
2026 handoff that describes the **shipped plugin**, and nothing else. It is a tracked file, and when
it was cut down `.claude-plugin/marketplace.json` declared `"source": "./"` — a form with no
exclusion mechanism — so every consumer who installed this plugin received this page. That is the
whole reason the rest of it is gone. The manifest now declares `"source": "./lw-watchtower"` and this
file sits outside that subtree, so it no longer ships; the removals below stand regardless, because
the reason they were made was that the boundary had not held.

The maintainer-facing narrative that used to be here — the release chronology, the identity rewrite,
the open-item register, the standing orders and the incident record — belongs in the issue tracker,
where it is addressed to the people it was written for and is not copied onto a stranger's machine.
**Issue #141 is the handoff.** Read it there; it is not reproduced here in shortened form, because a
summary of a maintainer note is still a maintainer note in the payload.

Three things were removed rather than reworded, and naming them is the point:

- **The pull-ref paragraph.** It published the location of an unresolved identity exposure, its tip
  commit, the number of commits involved, and the `git fetch` invocation that retrieves them.
  Publishing that turned a bounded exposure into a signposted one: it told any reader where to look
  and exactly how. **Removing this paragraph fixed the signposting and nothing else** — on the day it
  went, the exposure itself was untouched and the issue that owned it was open. The exposure was
  resolved separately on **2026-08-28**, by deleting the predecessor repository that served the ref;
  `CHANGELOG.md`'s `0.4.0` Fixed section records that, and states what the resolution does **not**
  cover. The paragraph stays out either way — a resolved exposure is no more reason to ship a map
  than an open one was.
- **The visibility-conditioned lines.** Three sentences here were true only while the repository was
  private, and each would have inverted — silently, with nothing reading it — at the moment the flip
  made this page public. **That flip happened on 2026-08-28**, which is what turns this from a
  prediction into a near miss. A claim whose truth turns on an event nobody re-reads the file after is
  a claim that should not be written down.
- **The standing orders and the incident record.** Both are useful internally. Neither is a
  statement about the software, and the second is an operational account of the maintainer's own
  environment.

`tests/payload_guard.ps1`'s detection rules run over the shipped payload only, so this page is out of
their reach — it is kept out of a consumer's hands by the payload boundary rather than by a guard
reading it. The boundary itself is still asserted on every run: the guard re-parses
`marketplace.json` and fails when the declared `source` and the scanned subtree disagree, its
region-marker sweep still covers the **full** tracked tree, and its out-of-payload record names the
root files that carry the pull-ref narrative and the visibility-conditioned claims.

**One record kept as a record.** The version string read `0.3.0` everywhere that declared it on the
day this file was written. It declares `0.4.0` now. That sentence is a record of 31 July 2026 and
correcting it would falsify the record; `CHANGELOG.md` is the authority on the current version.

Run `/lw-watchtower:doctor` for install state, rather
than trusting any number written on this page.


## What this plugin was on 31 July 2026

Present tense below, because that is how it was written on the day. The heading said *"What this
plugin is now"* until 4 September 2026, which made every sentence under it read as a claim about
today's tree rather than a record of that one — the last thing on this page still doing that after
the numbers were corrected. Read it as dated. `docs/` and `/lw-watchtower:doctor` are the authorities
on what is true now.

**An advisory layer. It blocks almost nothing, and that is the finished state, not a gap.**

- **6 commands:** `config`, `delegate`, `doctor`, `setup`, `uninstall`, `update`.
- **11 modules, 7 of them active.** Eight only observe — `failure_capture`, `context_pressure`,
  `self_health`, `log_rotation`, `docs_coupling`, `git_hygiene`, `context_injection` and
  `orphan_watch`. They report, log or advise; the action happens anyway.
- **3 gates, and all three ship switched off**, along with `orphan_watch`. `send_liveness_gate`
  (`lib/gate_send.ps1`) refuses a `SendMessage` to a subagent it can prove is dead mid-flight;
  `completion_audit` (`lib/gate_stop.ps1`) refuses to end a turn that claims completed work whose
  last action was a queued send. Both are described in full in `docs/modules.md`. The third is
  `delegate_gate` (`lib/gate_delegate.ps1`), which refuses `Edit`,
  `Write`, `NotebookEdit`, `Bash` and `PowerShell` on the main chat thread, so work goes to subagents. It turns on
  only with `/lw-watchtower:delegate on`. It reads no path and no command, and nothing it decides consults
  the tool name — it reads that only to name the refused tool in the denial text. **It is not a
  security control.**
- **Nothing inspects a shell command, a path or a credential**, and `permissions.deny` is empty.
  Force pushes, hard resets, recursive deletes, repo deletion, writes to `.git/`, writes of a live
  token — none are examined by anything here.
- **14 files in `tests/`, and eleven of them test behaviour.** `tests/gate_delegate.ps1` runs **99 cases** —
  58 exercise the gate's rule, 7 (section I) are aimed at the **fast path**, 3 (section M) are
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
  `tests/setup_merge.ps1` is **198 of 198**, driving the real `bin/lwg-setup.ps1` in a real child
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
  `tests/stop_behaviour.ps1` is **117 of 117** across the two hooks that fire at every turn end and
  the `lib/common.ps1` helpers they share, and reaches
  more **observing** modules than anything else in this repo: `failure_capture`, `context_pressure`,
  `docs_coupling`, `git_hygiene` and `log_rotation`, five of the eight — and it pins two supervisor bugs that
  had already shipped with no case behind them: a dedupe that silently stopped deduping on a
  multi-entry array, and a one-element failed-task list that logged as `null` and kept the health
  indicator green through a real failure. Its section A also reaches `Get-LwgRedacted`, this
  plugin's only redaction control, which had no test of any kind until 1 August 2026 and was
  carrying three defects when one was written — surrogate-splitting truncation, raw control
  characters reaching a fixed-column console report, and a trailing newline escaped into the
  message. `tests/uninstall_footprint.ps1` is **35 of 35** against
  `bin/lwg-uninstall.ps1`, asserting on the filesystem as well as on the report, and is the only
  suite that tests a **deletion**. It also holds the uninstaller's ATTRIBUTION - all 181 rules the
  installer wrote before 30 July 2026, run through `Test-MirroredDeny` from
  `tests/fixtures/deny_canonical.txt`, which is the only thing that makes that function's "the only
  code left in the repo that knows what those rules looked like" a checkable sentence.
  `tests/doctor_behaviour.ps1` is **37 of 37** against two of the
  doctor's ten checks and no others; `tests/toggle_behaviour.ps1` is **28 of 28** against
  `bin/lwg-toggle.ps1`'s write to `config.json`, which nothing had ever driven;
  `tests/subagent_scan.ps1` is **13 of 13** against the `SubagentStart` fast path, and is the only
  coverage `context_injection` has; `tests/payload_guard.ps1` is **22 of 22** over every tracked
  file, which is the whole shipped payload. `tests/portability_scan.ps1` and `tests/workflow_guard.ps1`
  report violations rather than cases, and `tests/doc_claims.ps1`
  checks tracked files and their stated counts; none of the three asserts anything about
  behaviour.

  **All thirteen siblings were re-run for this pass and every one of them exits 0.** That is
  measured rather than asserted: `tests/doc_claims.ps1` runs them in parallel to read the tally each
  prints about itself, and it ABORTS instead of reporting when any one of them exits non-zero — so a
  run of it that reaches a `RESULT:` line is itself the evidence that none did. The **case counts**
  quoted throughout this page are the totals each suite reports about itself and are what the
  documentation guard checks; the **pass** counts are not, and a page saying a suite is green is
  saying more than a count does.

  **Every one of the eight observing
  modules is now reached by at least one suite**, which is a much weaker statement than being
  tested. This line said SEVEN untouched until 3 August 2026, when `context_pressure`,
  `docs_coupling`, `git_hygiene` and `log_rotation` gained cases in `tests/stop_behaviour.ps1` and
  nine tracked pages went on saying those four were untouched; it said THREE until
  `tests/subagent_scan.ps1` landed and drove `lib/subagent_start.ps1`, which is
  `context_injection`'s implementation, and it said TWO until
  `tests/state_resolution.ps1` drove `self_health`. Four of the eight
  have one to three cases
  on at most two properties apiece — `context_pressure` 2, `docs_coupling` 2, `log_rotation` 3,
  `git_hygiene` 1 — and `context_injection` has one property run and its `worker_facts.md` handling
  untested, so "covered" here means "no longer untouched" and nothing stronger.
- **CI is one job, `fast-checks`, with twenty check steps** after checkout: JSON validity, PowerShell
  parse, workflow guard, the delegate gate suite, the installer merge suite, the stop-hook behaviour
  suite, the uninstaller footprint suite, the doctor behaviour suite, the
  toggle write-path suite, the `SubagentStart` fast-scan suite, the payload disclosure guard, the
  supervision suite, the config write-path suite, the state-resolution suite, the
  portability scan, the
  documentation-claim guard, the pull-request issue-reference guard, the commit-identity guard, the
  red-first annotation guard and the version-declaration guard.
  Its display name is still `Fast checks (JSON + PowerShell parse)` **on
  purpose** — a required status check on `main` matches that name, so renaming it would silently stop
  satisfying the requirement. **Every push to `main` runs all twenty**, with no path filter on either
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

## Where the documentation is

Nothing below is optional reading for a new operator, and none of it was linked from this file until
1 August 2026.

| Read this | For |
| --- | --- |
| [`docs/limitations.md`](docs/limitations.md) | **First.** Everything this plugin does not do, cannot do and does not check, in one place. The blunt version of *What this plugin is now* above. |
| [`docs/install.md`](docs/install.md) | Both install routes, the missing-directory trap in the junction route, the separate status-line install, and why the doctor exits `1` on a fresh machine |
| [`docs/faq.md`](docs/faq.md) | The questions the limitations page raises, answered from the tree — including how to run all fourteen test files yourself |
| [`docs/testing.md`](docs/testing.md) | What each of the fourteen files in `tests/` establishes, the shared exit-code contract, the twenty CI check steps, and what is uncovered |
| [`docs/architecture.md`](docs/architecture.md) | File layout, hook registrations, measured costs, the state directory, the status line |
| [`docs/modules.md`](docs/modules.md) | All eleven modules, each with its own blind spots |
| [`docs/configuration.md`](docs/configuration.md) | `config.json` in full — the switchboard, per-repo overrides, thresholds |
| [`docs/commands.md`](docs/commands.md) | All six slash commands and their exit codes |
| [`docs/troubleshooting.md`](docs/troubleshooting.md) | Symptom-first index. Start here when something looks wrong |
| [`docs/gates-removed.md`](docs/gates-removed.md) | **Before adding any gate.** Why the last two went and what four failed fix attempts taught |
| [`docs/portability.md`](docs/portability.md) | The no-local-environment-dependencies mandate that fails the build |
| [`docs/roles.md`](docs/roles.md) | The six agent roles and when each is dispatched |
| [`docs/uat-report.md`](docs/uat-report.md) | The v0.3.0 acceptance record: every command, the adversarial cases, and the two installer defects it found |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | The two rules that fail your build, the regression-test rule, and the accuracy house rule |
| [`SECURITY.md`](SECURITY.md) | What is and is not a vulnerability here — read the scope section before reporting anything |
| [`docs/README.md`](docs/README.md) | The index, if you would rather browse than be pointed |
