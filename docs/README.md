# LW-WATCHTOWER documentation

| Document | What is in it |
| --- | --- |
| **[Limitations](limitations.md)** | **Everything this plugin does not do, cannot do, or does not check — consolidated in one place, and the page to read before any other** |
| [FAQ](faq.md) | The questions a new user and a returning owner actually have, answered from the tree |
| [Install](install.md) | Requirements, marketplace and junction installs, the separate status-line install |
| [Configuration](configuration.md) | `config.json` in full — the switchboard, per-repo overrides, thresholds, per-module tuning |
| [Modules](modules.md) | All ten: what each does, its blind spots, **`delegate_gate` — the one gate, and it ships off**, the two placeholders removed because they cannot be built, and the removal of the other two gates |
| [Gates were removed deliberately](gates-removed.md) | The rules a gate has to follow here, **what the trip ledger's removal means a new gate must rebuild**, what the four failed fix attempts taught, and what a future attempt must do differently |
| [Commands](commands.md) | All twelve slash commands, their exit codes, and which of the three preference commands is enforced |
| [Roles](roles.md) | The six agent roles the plugin ships, and when each is dispatched |
| [Architecture](architecture.md) | File layout, hook registrations, measured costs, state directory, status line, failure policy |
| [Testing and CI](testing.md) | **Eight files in `tests/`, five of which test behaviour** — what each one establishes, the exit-code contract they share, the ten CI check steps, and what is therefore uncovered |
| [UAT report (v0.3.0)](uat-report.md) | All twelve commands and the adversarial cases, run from a throwaway profile — per-item verdicts, the two installer defects it found, and **what a green UAT still does not establish** |
| [Portability](portability.md) | The no-local-environment-dependencies mandate, the scan that enforces it, and the allowlist rules |
| [Output styles](output-styles.md) | The three verbosity levels and `plain` — and the four things they cannot do |
| [Troubleshooting](troubleshooting.md) | Symptom-first index |
| [Style compliance check](style-compliance-check.md) | Design note for an **unbuilt** check: what it could and could not measure |
| [Monitors feasibility spike](monitors-spike.md) | Can any hook receive rate-limit or cost data? Method, evidence and **verdict: negative** — re-confirms and refines the [Modules](modules.md#attempted-and-blocked-ratelimit_escalation-and-cost_tracking) record on the same CLI build |

Project-level files live at the repo root: [README](../README.md),
[CONTRIBUTING](../CONTRIBUTING.md), [SECURITY](../SECURITY.md),
[CODE_OF_CONDUCT](../CODE_OF_CONDUCT.md), [CHANGELOG](../CHANGELOG.md).

## If you read only one thing

**[Limitations](limitations.md).** It is the consolidated list of what this plugin does not do,
cannot do, and does not check — including the largest single fact about it: both of the old gates
went on 30 July 2026 by explicit owner decision, and the one gate built to replace them ships
switched off, so **as shipped nothing here can block, deny or delay a tool call.** Everything this
project claims rests on being accurate about what it does not do.

The narrative of the removal itself lives at
[Modules § Both gates were removed](modules.md#both-gates-were-removed), which is its single home;
`limitations.md` summarises and links it rather than keeping a second copy to drift.

There was a separate `gates.md` in this directory until that date, describing gates that were live.
It was deleted with the last gate rather than left standing to describe a protection that no longer
ships, and everything it recorded now lives in the section linked above, which is the single home
for that narrative. [gates-removed.md](gates-removed.md) is a different page with a different job:
it does not describe any protection, it records **why the gates went, what four failed fix attempts
taught, and what a future attempt must do differently** — because the owner intends blocking
capability to be re-addable and the code that would have taught those lessons is deleted.
