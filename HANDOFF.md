# Handoff — 31 July 2026 (v0.3.0 release)

**What this file is, and what it deliberately no longer carries.** This is the part of the 31 July
2026 handoff that describes the **shipped plugin**, and nothing else. It is a tracked file, and
`.claude-plugin/marketplace.json` declares `"source": "./"` — a form with no exclusion mechanism — so
every consumer who installs this plugin receives this page. That is the whole reason the rest of it
is gone.

The maintainer-facing narrative that used to be here — the release chronology, the identity rewrite,
the open-item register, the standing orders and the incident record — belongs in the issue tracker,
where it is addressed to the people it was written for and is not copied onto a stranger's machine.
**Issue #141 is the handoff.** Read it there; it is not reproduced here in shortened form, because a
summary of a maintainer note is still a maintainer note in the payload.

Three things were removed rather than reworded, and naming them is the point:

- **The pull-ref paragraph.** It published the location of an unresolved identity exposure, its tip
  commit, the number of commits involved, and the `git fetch` invocation that retrieves them.
  Publishing that turned a bounded exposure into a signposted one: it told any reader where to look
  and exactly how. **The exposure itself is unchanged** — removing this paragraph fixed the
  signposting and nothing else, and the issue that owns the exposure is still open. What is gone is
  this page's map to it.
- **The visibility-conditioned lines.** Three sentences here were true only while the repository is
  private, and each would have inverted — silently, with nothing reading it — at the moment the flip
  made this page public. A claim whose truth turns on an event nobody re-reads the file after is a
  claim that should not be written down.
- **The standing orders and the incident record.** Both are useful internally. Neither is a
  statement about the software, and the second is an operational account of the maintainer's own
  environment.

`tests/payload_guard.ps1` fails the build if any of the first two comes back, on this page or on any
other tracked file. It is the reason this is a fix rather than a tidy-up.

**One record kept as a record.** The version string read `0.3.0` everywhere that declared it on the
day this file was written. It declares `0.4.0` now. That sentence is a record of 31 July 2026 and
correcting it would falsify the record; `CHANGELOG.md` is the authority on the current version.

Run `/lw-watchtower:checklist` for plan state and `/lw-watchtower:doctor` for install state, rather
than trusting any number written on this page.


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
- **12 files in `tests/`, and nine of them test behaviour.** `tests/gate_delegate.ps1` runs **93 cases**
  — and eight of them currently fail on this tree, for the fixture reason recorded below; it is not
  93 of 93 today —
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
  `tests/stop_behaviour.ps1` is **177 of 177** across the two hooks that fire at every turn end and
  the `lib/common.ps1` helpers they share, and reaches
  more **observing** modules than anything else in this repo: it runs `mission_drift` end to
  end — the fire condition, the suppressors (`min_files`, `require_outside_root`, `max_scan_bytes`,
  `stop_hook_active`), and specifically the **pivot property** — and it pins two supervisor bugs that
  had already shipped with no case behind them: a dedupe that silently stopped deduping on a
  multi-entry array, and a one-element failed-task list that logged as `null` and kept the health
  indicator green through a real failure. Its section A also reaches `Get-LwgRedacted`, this
  plugin's only redaction control, which had no test of any kind until 1 August 2026 and was
  carrying three defects when one was written — surrogate-splitting truncation, raw control
  characters reaching a fixed-column console report, and a trailing newline escaped into the
  message. `tests/uninstall_footprint.ps1` is **27 of 27** against
  `bin/lwg-uninstall.ps1`, asserting on the filesystem as well as on the report, and is the only
  suite that tests a **deletion**. It also holds the uninstaller's ATTRIBUTION - all 181 rules the
  installer wrote before 30 July 2026, run through `Test-MirroredDeny` from
  `tests/fixtures/deny_canonical.txt`, which is the only thing that makes that function's "the only
  code left in the repo that knows what those rules looked like" a checkable sentence. `tests/evidence_states.ps1` runs **47 cases** against
  `bin/lwg-evidence.ps1` — one of them fails in a worktree, see below — that a probe which could not run renders `UNVERIFIED` and one that ran and
  failed still renders `NOT STARTED`. `tests/doctor_behaviour.ps1` is **16 of 16** against two of the
  doctor's nine checks and no others; `tests/toggle_behaviour.ps1` is **26 of 26** against
  `bin/lwg-toggle.ps1`'s write to `config.json`, which nothing had ever driven;
  `tests/subagent_scan.ps1` is **6 of 6** against the `SubagentStart` fast path, and is the only
  coverage `context_injection` has; `tests/payload_guard.ps1` is **15 of 15** over every tracked
  file, which is the whole shipped payload. `tests/portability_scan.ps1` and `tests/workflow_guard.ps1`
  report violations rather than cases, and `tests/doc_claims.ps1`
  checks tracked files and their stated counts; none of the three asserts anything about
  behaviour.

  **All twelve were re-run for this pass and TWO of them exit 1** — this is the state of the
  integration tree, not a green board. `tests/evidence_states.ps1` fails one of its 47 cases when it
  runs in a worktree (issue #153, unrelated to any wave-1 fix). `tests/gate_delegate.ps1` fails eight
  of its 93 cases, all in section K: those cases build a scratch plugin root holding only
  `bin/lwg-toggle.ps1` and
  `lib/common.ps1`, and the toggle fix added a dot-source of `bin/lwg-cmdlib.ps1` that the fixture
  does not copy, so every one of them exits 3 on a missing file. That is a collision between two
  wave-1 fixes and not a defect in either. The **case counts** quoted throughout this page are the
  totals each suite reports about itself and are what the documentation guard checks; the
  **pass** counts are not, and a page saying a suite is green is saying more than a count does.

  **Two of the nine observing
  modules — `verification_gate` and `self_health` — are still exercised by nothing
  at all.** This line said SEVEN until 3 August 2026, when `context_pressure`, `docs_coupling`,
  `git_hygiene` and `log_rotation` gained cases in `tests/stop_behaviour.ps1` and nine tracked pages
  went on saying those four were untouched; it said THREE until `tests/subagent_scan.ps1` landed and
  drove `lib/subagent_start.ps1`, which is `context_injection`'s implementation. Four of the seven
  that are covered have one to three cases
  on at most two properties apiece — `context_pressure` 2, `docs_coupling` 2, `log_rotation` 3,
  `git_hygiene` 1 — and `context_injection` has one property run and its `worker_facts.md` handling
  untested, so "covered" here means "no longer untouched" and nothing stronger.
- **CI is one job, `fast-checks`, with fourteen check steps** after checkout: JSON validity, PowerShell
  parse, workflow guard, the delegate gate suite, the installer merge suite, the stop-hook behaviour
  suite, the uninstaller footprint suite, the evidence-state suite, the doctor behaviour suite, the
  toggle write-path suite, the `SubagentStart` fast-scan suite, the payload disclosure guard, the
  portability scan, and the
  documentation-claim guard. Its display name is still `Fast checks (JSON + PowerShell parse)` **on
  purpose** — a required status check on `main` matches that name, so renaming it would silently stop
  satisfying the requirement. **Every push to `main` runs all fourteen**, with no path filter on either
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
| [`docs/install.md`](docs/install.md) | Both install routes, the missing-directory trap in the junction route, the separate status-line install, and why the doctor exits `2` on a fresh machine |
| [`docs/faq.md`](docs/faq.md) | The questions the limitations page raises, answered from the tree — including how to run all twelve test files yourself |
| [`docs/testing.md`](docs/testing.md) | What each of the twelve files in `tests/` establishes, the shared exit-code contract, the fourteen CI check steps, and what is uncovered |
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
