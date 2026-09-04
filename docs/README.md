# LW-WATCHTOWER documentation

| Document | What is in it |
| --- | --- |
| **[Limitations](limitations.md)** | **Everything this plugin does not do, cannot do, or does not check — consolidated in one place, and the page to read before any other** |
| [FAQ](faq.md) | The questions a new user and a returning owner actually have, answered from the tree |
| [Install](install.md) | Requirements, marketplace and junction installs, the separate status-line install |
| [Configuration](configuration.md) | `config.json` in full — the switchboard, per-repo overrides, thresholds, per-module tuning |
| [Modules](modules.md) | Every declared module: what each does, its blind spots, **the three gates, all of which ship off**, the two placeholders removed because they cannot be built, and the removal of the two original gates |
| [Gates were removed deliberately](gates-removed.md) | The rules a gate has to follow here, **what the trip ledger's removal means a new gate must rebuild**, what the four failed fix attempts taught, and what a future attempt must do differently |
| [Commands](commands.md) | All twelve slash commands, their exit codes, and what each one writes |
| [Roles](roles.md) | The six agent roles the plugin ships, and when each is dispatched |
| [Architecture](architecture.md) | File layout, hook registrations, measured costs, state directory, status line, failure policy |
| [Testing and CI](testing.md) | **Thirteen files in `tests/`, ten of which test behaviour** — what each one establishes, the exit-code contract they share, the fourteen CI check steps, and what is therefore uncovered |
| [Portability](portability.md) | The no-local-environment-dependencies mandate, the scan that enforces it, and the allowlist rules |
| [Output styles](output-styles.md) | **Removed.** A tombstone for the deleted feature, kept because pages still link to it |
| [Troubleshooting](troubleshooting.md) | Symptom-first index |

Project-level files live at the repo root: [README](../README.md),
[CONTRIBUTING](../CONTRIBUTING.md), [SECURITY](../SECURITY.md),
[CODE_OF_CONDUCT](../CODE_OF_CONDUCT.md), [CHANGELOG](../CHANGELOG.md).

**What is not here.** Five pages left this directory. Four of them were moved rather than deleted:
the v0.3.0 UAT record, the monitors feasibility spike, the style-compliance design note and the
harness hosting plan are now maintainer notes under `.github/notes/`. The fifth, the
session-transition specification, was deleted outright and lives on issue #168. GitHub Pages publishes `docs/` whole and has no exclusion
mechanism, so a page in here is a page published to the open web — which is what those five were,
without anyone having decided it. `tests/doc_claims.ps1` now holds this index to that: every page
present under `docs/` must have a row above, because a page nobody indexed is a page nobody chose
to publish.

## If you read only one thing

**[Limitations](limitations.md).** It is the consolidated list of what this plugin does not do,
cannot do, and does not check — including the largest single fact about it: both of the old gates
went on 30 July 2026 by explicit owner decision, and the three gates built since all ship
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
