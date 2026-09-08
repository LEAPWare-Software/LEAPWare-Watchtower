<!-- doc-claims:ignore-file — a handoff is a RECORD of what was true when it was written.
     Every count below is measured at the SHA named in section 2 and must not be updated to
     today's number; doing so would falsify the record. tests/doc_claims.ps1 reads nothing here. -->

# Handoff — 2026-09-08

Written by following `lw-watchtower/skills/lw-handoff/SKILL.md`, the plugin's own procedure.
Four sections, all four required. **Written after landing, not before** — step 2 first.

**Session shape:** v0.5.0 step 1 was completed, then the owner reported a defect in the shipped
`v0.4.0` uninstall and made it priority 1. A patch release was cut from the tag, delivered and
verified on the owner's machine. The owner then said: **no new work, complete in flight, hand off.**

---

## 1. Work in flight

**Nothing is running.** Nine build lanes were dispatched this session and **all nine returned and
reported**; every one of their PRs is merged. Verified rather than assumed — each branch was checked
against `gh pr list --state all --head <branch>` and all nine read `MERGED` before any local branch
was deleted.

Per the handoff skill's own warning, that statement is **written from knowledge of this turn**, not
read off a roster: `health.jsonl`'s START rows are a lead and not an answer, no code reads them, and
an empty in-flight section means *nothing was observable*, never *nothing is running*.

| what | where | state |
| --- | --- | --- |
| the ten merges | `main` | landed, CI green |
| `v0.4.1` patch | tag `v0.4.1` → `ffba152` | tagged, pushed, **installed and verified on the owner's machine** |
| background CI monitor | this session | a watcher; dies with the session, nothing depends on it |

**Unfinished and deliberately not started** (the owner's "no new work"): the forward-port of the
uninstall fix to `main`, and whatever `0.6.0` means. Both are named in section 3.

---

## 2. The commit and branch every note below is true of

| repo | branch | SHA | remote | pushed |
| --- | --- | --- | --- | --- |
| LEAPWare-Watchtower | `main` | **`3eee939`** | `origin` | yes — level, `+0 -0` |
| LEAPWare-Watchtower | `release/0.4.1` | **`ffba152`** | `origin` | yes |

**Tags:** `v0.4.0` at `7952992` and **`v0.4.1` at `ffba152`** (new this session). Both pushed.
**Nothing is unpushed. No local-only branch exists.** Working tree clean; one worktree; local
branches are `main` and `release/0.4.1` only — the nine squash-merged lane branches and ten agent
worktrees were removed after their PRs were confirmed merged.

**Measured at `3eee939`:** registry **10** entries / **7** observing · payload **55** files ·
`tests/` **16** files · commands **7** · UAT reports **8** · registrations **15** across 8 events ·
`main` CI **green** · **0 open PRs**.

**`v0.5.0` milestone: 12 open. GATE NOT MET — `sev:high` 1 (#345), `sev:medium` 0, `blocking` 0.**

**Owner's machine, verified directly:** `lw-watchtower@leapware-watchtower` **v0.4.1**, sha
`ffba1522`, user scope, enabled. Status line **installed and PASS**. Doctor: **7 passed, 0 warnings,
2 failures, exit 1** — `state-dir` and `sessionstart`, one root cause, pre-existing, see section 4.

---

## 3. Next actions, in order — blockers first

1. **RESTART THE CLI.** The status line was wired this session; commands, hooks, agents and output
   styles are read at session start. Whether a running session picks up a newly wired status line
   without a restart is **unmeasured**.
2. **Forward-port the uninstall fix to `main` for `v0.5.0`.** The fix exists **only on the `v0.4.1`
   tag**. `main`'s uninstaller is still the reporter that exits 0 having removed nothing.
   **#345 stays open until this lands** — it is the one `sev:high` and the whole gate.
   `main`'s `bin/lwg-uninstall.ps1` references no module flags (verified), so #166's rename does not
   complicate the port. Source of truth is `release/0.4.1`'s diff against `v0.4.0`.
3. **Ask the owner what a separate `0.6.0` uninstall means.** `0.6.0` does not exist; `main` declares
   `0.5.0`. On the obvious reading it inherits from `main` and there is nothing extra to do. **This
   was asked and not answered — do not guess it.**
4. **Decide #336.** `Stop-LwgProcessTree`'s `WaitForExit(1000)` at `lib/stop_advisories.ps1:306`
   runs **747-928 ms** under load; past it only the direct child dies and the grandchild survives,
   which is the pre-fix behaviour of #98. Three options: raise the bound, make the fallback walk the
   tree, or document the degradation. **It is a product bound, not a test threshold** — B26 is
   telling the truth and loosening it would hide this.
5. **Build #340's guard.** One bare `Get-Content` was fixed; **nothing prevents a sixteenth.** A rule
   holding `doc_claims` to its own claim needs care about self-reference and the abort contract.
6. **#125** — six GitHub Settings fields plus the `HH` abbreviation the repo description uses and the
   tree defines nowhere. `blocked-on-owner`; **only the owner can move it.**
7. **Then steps 3-8 of the release plan** (`~/.claude/plans/atomic-rolling-teapot.md`): three UAT
   passes, fixes, re-UAT, tag, round trip, production readiness. **The critical path there is not
   code** — twelve items can only be measured in a live session and Rule 18 forbids a lane starting
   one. The sharpest is **whether `--agent lw-watchtower:lw-orchestrator` actually binds the main
   thread**, which both shipped #316 layers rest on and which nobody has observed.

---

## 4. What I am not sure of

**The section a rushed handoff drops. Read it.**

- **The `v0.4.1` fix is verified on ONE machine, one route.** Marketplace route, user scope, this
  Windows build. The junction route's block was exercised from a worktree and a fixture; **a real
  junction install was never removed.** Nothing establishes it on another machine.
- **Whether a running session drops a deregistered plugin without a restart is UNMEASURED.** The
  script says so in its own output rather than guessing. Unchanged by anything this session did.
- **The doctor's two failures were not diagnosed to a fix.** `state-dir` reports the unsuffixed
  fallback `plugins/data/lw-watchtower` while the CLI names data dirs `<name>-<source-id>`; the
  owner's real 2.5 MB of logs is at `plugins/data/lw-gmhh`, a **legacy** name. `sessionstart` fails
  *because* the state dir is unresolved. **They may self-resolve after a restart and they may not.**
  This is the same root cause as uninstall finding 5 and it is worth an issue nobody has filed.
- **`--keep-data`'s `{id}` spelling is still not established.** Two shapes exist on real machines.
  The v0.4.1 report enumerates what it finds and classifies each rather than naming one path.
- **I asserted a mechanism that was wrong and it reached the owner.** I twice said `doc_claims` is
  digit-anchored and misses word-form numbers. **It is not** — `tests/doc_claims.ps1` maps `zero`
  through `twenty`. The real cause of #308's drift was a **noun**: the row described a *re-run* and
  borrowed the *behavioural-suite* noun phrase, so the guard held it to the wrong quantity and passed
  it. Corrected on #308 and in memory. **Anything else I said about why a count drifted deserves
  re-checking against the tree.**
- **My brief for the v0.4.1 lane contained a false claim** — that `-y` is required or the command
  hangs. `-y` is scoped to `--prune`; my own round trip disproved it. The lane caught it. **Three
  other lanes corrected my briefs with measurements this session and all three were right**; assume
  the briefs, not the tree, are the unreliable input.
- **One CI failure this session was mine.** `state_resolution` reported 38 of 44 because I uninstalled
  the plugin while that verification was running. Re-ran clean at 44/44. **That suite is coupled to
  the plugin being installed** — worth knowing before reading it as a defect.
- **`v0.4.1` was never UAT'd.** It carries a red-first case, full CI green on its exact SHA, and a
  real round trip on one machine. It had no CPO, CTO or adversarial pass.
- **Ruling J1 went against my recommendation.** I advised deferring #166's merge because
  `failure_capture` ships `true` and `orphan_watch` ships `false`, so one flag cannot carry both
  defaults. The owner overruled and it shipped **on** — so **orphan reconciliation is now active by
  default for every consumer**, which ruling H2 had not costed. Both sides are on #147. **What that
  costs in a real dispatch-heavy session is unmeasured.**
- **`stack_mode` ships `false`** (ruling I1) and **turning it on costs a whole second interpreter per
  dispatch, ~464 ms** (ruling I2) — the 296 ms floor is paid again because it is a second process on
  the same event. **Whether the CLI runs two `SubagentStart` hooks in parallel or in series is
  unmeasured**, and that is the difference between "a dispatch got twice as slow" and "the machine
  did twice the work".
- **The `[0.5.0]` CHANGELOG has ten lane-authored entries and no reconciled head.** Each is honest
  about its own slice; none is aware of the others. Somebody has to write the section.
- **All six enhancements re-milestone to `v0.6.0` at the tag.** Each issue's own done-condition
  demands more than the slice that shipped. The release notes must name **which slice** shipped, not
  the issue.

---

## Where the durable records are

- **`#147`** — every ruling: F1-F5, G1-G2, H1-H5 (plus H5's correction), I1-I2, J1, each with its
  reasoning and not just its outcome.
- **`~/.claude/plans/atomic-rolling-teapot.md`** — the approved 8-step v0.5.0 plan, with the owner
  queue and the estimate basis.
- **`#345`** — the uninstall defect, with every measurement taken on the owner's machine.
- Lane specs worth not re-deriving: `~/.claude/plans/atomic-rolling-teapot-agent-*.md`.
