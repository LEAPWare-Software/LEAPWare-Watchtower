---
description: "LW-WATCHTOWER plan checklist - every item's state derived from a commit, a file, an exit code or a CI conclusion. An item with no evidence renders as unverified, which is not a synonym for incomplete"
allowed-tools: "Bash(powershell:*)"
---

Run this command and show the user its output **verbatim**:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/bin/lwg-checklist.ps1"
```

**Output the checklist and nothing else.** No preamble, no "here is the current state", no
narrative summary underneath, no offer to work on the outstanding items. The script's output
*is* the answer; anything you add around it is the part most likely to be wrong.

**This overrides any active output style.** `lw-watchtower-brief`'s word ceiling explicitly excludes
command output, and `lw-watchtower-plain` cannot rewrite an evidence citation into friendlier words
without destroying the thing that makes it evidence. Print the block as emitted. If you are
asked to shorten it, say which rows you are omitting rather than dropping them quietly.

## The five states, and the one that gets mishandled

| Render | Means |
| --- | --- |
| `[x] DONE` | a probe passed. The evidence is printed on the next line |
| `[~] IN PROGRESS` | part of a required set exists, or CI is mid-run |
| `[ ] NOT STARTED` | a probe **ran** and found the thing absent |
| `[!] BLOCKED` | a named prerequisite is not done. `DECLARED` marks a blocker asserted by `checklist.json` rather than observed |
| `[?] UNVERIFIED` | the probe **could not run at all** |

**`[x*]` is a `DONE` row carrying a caveat**, not a sixth state. The probe passed *and* the
`does NOT prove:` text printed beneath it limits what passing establishes. A section heading holding
one or more of them is annotated `<- N QUALIFIED item(s) below; this heading is NOT established by
them`, so a reader scanning the tick column sees the contradiction without reading the caveat body.
Never report a `[x*]` row as plainly done, and never treat a section of them as its heading met.

**`UNVERIFIED` is a third state, not a quieter `NOT STARTED`.** It means no gh, no network, no
git, or no automatable evidence exists — the item may well be finished and this command has no
right to say either way. Never fold it into the incomplete count, never describe those items as
outstanding, and never total `done / (done + not started)` in a way that silently drops them.

## Rules for reporting it

- **Do not re-derive a state.** If a row says `NOT STARTED`, it says so because a probe ran and
  found nothing. Do not overrule it from memory of this conversation, from a worker's report, or
  from a file you happen to have read. A checklist that ticks an item because someone said so is
  the exact defect this plugin exists to catch.
- **Never tick something the script did not.** This is the one prohibition that matters. If the
  user says an item is done, the answer is that the evidence rule did not find it, and what the
  rule looks for — not a corrected checkbox.
- **Repeat the `does NOT prove:` lines.** They appear under `DONE` rows whose evidence is
  weaker than the item, and they are the difference between a citation and a claim.
- **Repeat the `DRIFT:` lines.** They mean the plan changed after `checklist.json` was written,
  so items may be missing from the list entirely.
- If the script exits `3` it produced no checklist. Say that nothing is known about plan state,
  rather than describing progress from this conversation.

## What the source of truth is, and how it goes stale

The item list comes from **`checklist.json`, tracked in this repo** — not from the plan file
under `~/.claude/plans`, which is per-machine, untracked, ships with nothing, and whose
checkboxes are hand-ticked; and not from the session task list, which is ephemeral, unreachable
from a script and carries no evidence at all. A tracked file is reviewable in a pull request and
can carry a machine-checkable rule per item.

It is transcribed **by hand**, so it can drift three ways: an item deleted here vanishes from
the report, a new plan item never transcribed never appears, and a loosely written rule can pass
without the work being done. The first two are measured on every run against the plan file when
it is present, and the run says so plainly when it is not. **The third is not detectable by any
automated means**, which is why every `DONE` row prints its evidence — judge the rule, do not
trust the tick.

**The plan file is on one laptop, so drift is measurable on one laptop.** Its path is under a
single user profile and it is neither tracked nor shipped, so the `STALENESS MEASURED` line can
only ever appear on the machine that holds it. Everywhere else the run prints `STALENESS NOT
MEASURED` with the reason — which is the command working, and is **not** the same as no drift.
Report it that way: on a second machine an untranscribed plan item is undetectable, so the list
can be short an item and look complete. `STALENESS NOT MEASURED` means *nobody here can tell you
whether the plan and this file agree*, and it must never be summarised as "no drift" or omitted
because it is not a `DRIFT:` line.

This command **reports**; it does not judge, and exits `0` however much is outstanding. For what
is broken use `/lw-watchtower:doctor`; for what is underway right now use `/lw-watchtower:sitrep`.
