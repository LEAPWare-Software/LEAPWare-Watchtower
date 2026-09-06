---
description: "LW-WATCHTOWER measurement report - reads the Claude Code transcripts already on disk and reports how much work left the main thread, what it cost in tokens by model and by category, and whether delegation is happening at all. Every column it has no source for prints NOT DETERMINED"
allowed-tools: "Bash(powershell:*)"
disallowed-tools: "PowerShell"
---

Run this command and show the user its output **verbatim**, every section including the ones
that are empty:

Run this through the **Bash** tool. Do not use the PowerShell tool: its validator refuses any
command that launches `powershell`, so every attempt costs the operator a permission prompt and
then falls back to Bash anyway.

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/bin/lwg-metrics.ps1"
```

Add `-All` to report across every project on this machine instead of the one the operator is in.
Add `-Json` for the same figures as one JSON object, with the exact integers rather than the
scaled columns.

**The script's exit code is the verdict. Report it as it is.**

| Exit | What it means | How to report it |
| --- | --- | --- |
| `0` | a report was produced | report it — an empty corpus is still a report |
| `3` | no report could be produced | **unknown** — the configuration root could not be resolved, or the transcript directory is not there. Nothing was measured, so nothing below the line is a measurement |

## What this command reads, and what it writes

It reads Claude Code's own transcripts under the configuration root, and this plugin's
`health.jsonl` if it is there. **It writes nothing at all** — no state file, no index cache, no
ledger, and nothing in the operator's repository. There is no `-Apply` because there is nothing
to apply.

It makes no network call, and it never mentions money. Token counts only.

## NOT DETERMINED is the answer, not a gap in the report

This is the first slice of the metrics work (issue #165), and it is the transcript indexer and
the scoreboard — nothing else. There is no hook, no usage-meter history, no LCAP round capture,
no landing detection and no keep-or-revert decision rule, and each of those columns prints
`NOT DETERMINED` with the requirement it is waiting on.

- **Do not fill one in.** If the report says the usage meter is NOT DETERMINED, the operator's
  5-hour and 7-day percentages are not in this report and cannot be inferred from it. Say so.
- **Do not read NOT DETERMINED as zero, or as fine.** "I could not measure it" and "it was zero"
  are different statements, and the whole reason this command exists is that a keep-or-revert
  decision was being made on impression.
- **Do not print a verdict.** The `VERDICT` section is deliberately empty. A STAY/REVERT call
  needs four inputs and three of them do not exist yet; producing one from the fourth would be
  the exact failure the issue was opened about.

## Reading the numbers it does produce

- **The composite is a cache-read number.** `composite = input + cache read + cache creation +
  output`, and on a real session the cache read is two or three orders of magnitude larger than
  everything else. Never quote the composite alone as "tokens used" — quote the category
  breakdown beside it, which the report always prints.
- **Both shares, always.** The subagent share of the composite and the subagent share of output
  answer different questions and diverge widely. Report both or neither.
- **Per session, not per landing.** Every median in the `COHORT` block is per session. The
  issue's decision rule compares cohorts per landing; landing detection is not built, so no
  ratio in this report is that ratio. Do not describe one as if it were.
- **The token figures are a floor.** Usage this machine cannot see — another device, a browser
  session, the advisor tool — is in nobody's transcript, so every total is at least this and
  possibly more.
- **The corpus is a sliding window.** Transcript retention is finite. A cohort older than the
  earliest date in the `INDEX` block is not missing from the report; it has been deleted from
  the disk and is not coming back.

## The one measurement everything else rests on

The report says it on every run: usage is summed **once per `message.id`**. One API response is
written to the transcript as several assistant lines — one per content block — each repeating
the identical usage object. A per-line sum overstates by roughly twice. If the operator compares
this report against a figure from somewhere else and the other figure is about double, that is
the likely reason, and it is worth saying rather than splitting the difference.

## What it cannot tell you

Named in full in [`docs/metrics.md`](https://github.com/LEAPWare-Software/LEAPWare-Watchtower/blob/main/docs/metrics.md),
and printed in the report's own `COULD NOT DETERMINE` block on every run, including green ones.
**Repeat that block.** It is the part of the output that keeps the rest of it honest.
