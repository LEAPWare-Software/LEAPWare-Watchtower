---
description: "LW-WATCHTOWER situation report - work in flight, work finished since the last sitrep, blockers, decisions awaiting you, and governance state. Separates verified from reported, and names what it could not determine"
argument-hint: "[--no-mark]"
allowed-tools: "Bash(powershell:*)"
---

Run this command and show the user its output **verbatim**:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/bin/lwg-sitrep.ps1"
```

If `$1` is `--no-mark`, append `-NoMark`. A normal run **advances a marker** in the state dir so
the next sitrep reports only what changed; `-NoMark` reads the same window again without moving
it. Say which one you ran when it matters.

**Print every section, including the empty ones.** A section that disappears when it has nothing
in it is indistinguishable from a section that was never checked, and that confusion is the
thing this command exists to prevent. This holds under any active output style: `lw-watchtower-brief`
excludes command output from its ceiling, and no styling rule may drop a section.

## The two tags

| Tag | Means |
| --- | --- |
| `[V]` | **verified** — this process ran the probe, or read a record the plugin's own hooks wrote about their own behaviour |
| `[R]` | **reported** — a claim an agent or tool made about its own work, read back out of a log. Not independently checked |
| `[ ]` | in the GOVERNANCE block: **not determined**. The probe did not answer |

A worker's report is a claim, not a fact. When you relay a `[R]` line, keep it a claim: "seven
subagents are recorded as having stopped" is right; "seven subagents completed their work" is
not, and the record does not say what any of them achieved.

## Rules for reporting it

- **`COULD NOT DETERMINE` is the most important section. Never skip it, never shorten it.** It
  is where the sitrep says what it is blind to, and its two standing entries matter every run:
  no hook records a subagent **dispatch**, so agents currently in flight are structurally
  invisible; and nothing records a question put to the operator, so a decision raised in prose
  and never answered leaves no trace this command can find.
- **An empty `IN FLIGHT` does not mean nothing is running.** It means nothing observable is.
  Say it that way.
- **Never soften a failure.** Quote a failed CI conclusion, an open gate trip and an outstanding
  health fault as they are printed. If the tree is dirty or unpushed, say so.
- **Never report unknown as fine.** `NOT DETERMINED` on the working tree is not a clean tree,
  and `0 health faults` after a note saying the log was unreadable is not a healthy machine.
- **Carry the window with the number.** Both GOVERNANCE counts are read from a bounded tail. When
  the gate-denial line says `in the last 512 KB of a NNN KB event log - earlier denials were NOT
  read`, or the health line says `(AT LEAST - only the last N record(s) ... were read)`, that
  clause is part of the figure and not decoration. Quote it. A `[V]` on a truncated read means
  *"I counted what I read"*, and dropping the clause turns it into a claim about the whole file.
- **Do not pad.** Do not restate a section in prose after printing it, do not add an assessment
  the script did not make, and do not propose next steps unless asked.
- **Surface `NEEDS AN OPERATOR DECISION` first if it is non-empty.** Those items are why the
  command exists — they are things that were raised and may have scrolled past.
- If the script exits `3` it produced no sitrep. Say that nothing was assessed. In particular
  the absence of a problem in a failed run is not evidence there is none.

## What it degrades on, and how

`gh` absent, no network, `git` absent, not a git repo, an unresolved state dir, a missing
`checklist.json` — each is reported **per item**, in `COULD NOT DETERMINE`, and the run still
exits `0`. That is degrading honestly, not failing. If you see a `NOT DETERMINED` line, the
cause is named on it; relay the cause, do not substitute an assumption.

Related: `/lw-watchtower:checklist` for plan state in full, `/lw-watchtower:doctor` for what is broken in the
plugin's own wiring, `/lw-watchtower:status` for which modules are live.
