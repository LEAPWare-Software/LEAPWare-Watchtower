# Monitors feasibility spike: can any hook receive rate-limit or cost data?

**Verdict: NEGATIVE.** No hook event this plugin can register on carries rate-limit or cost
data. This record is the evidence for that verdict — what was run, what came back, and what
would have to change in the CLI before either module could be built.

This is a re-confirmation of the finding already written up at
[Modules § Attempted and blocked](modules.md#attempted-and-blocked-ratelimit_escalation-and-cost_tracking),
pinned to the **same CLI build**, `2.1.220 (Claude Code)` — see the pin-to-build note there.
Re-confirming on the same build is not a drift test; it does not show the finding still holds
on a newer one. **The check needs repeating after a CLI upgrade.**

## Method

A scratch project outside this repo registered project-scope hooks for every documented event
— `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `Notification`, `PreCompact`,
`PreToolUse(*)`, `PostToolUse(*)`, `PostToolUseFailure(*)`, `SubagentStart`, `SubagentStop`,
`Stop`, `StopFailure` — each one dumping raw stdin to its own file. The dumper was self-tested
first: a known payload piped through it round-tripped byte-for-byte, so an empty capture from a
real session means "this event carried no data," not "the probe never ran." A minimal
non-interactive session then exercised the events, and every capture file was inspected.

This establishes what the CLI actually sends. It does not establish what the CLI could be made
to send — that question is answered separately, below, by reading the binary rather than by
running it.

## What each event's payload actually carried

| Event | Top-level keys beyond the shared base |
| --- | --- |
| `SessionStart` | `agent_type`, `cwd`, `hook_event_name`, `session_id`, `source`, `transcript_path` |
| `UserPromptSubmit` | adds `prompt` |
| `PreToolUse` | adds `tool_input`, `tool_name`, `tool_use_id` |
| `PostToolUse` | adds `duration_ms`, `tool_input`, `tool_name`, `tool_response`, `tool_use_id` |
| `SubagentStart` | adds `agent_id` |
| `SubagentStop` | adds `agent_id`, `agent_transcript_path`, `background_tasks`, `last_assistant_message`, `session_crons`, `stop_hook_active` |
| `Stop` | adds `background_tasks`, `last_assistant_message`, `session_crons`, `stop_hook_active` |
| `SessionEnd` | adds `reason` |

`Notification`, `PreCompact`, `PostToolUseFailure` and `StopFailure` carried the shared base
object and nothing beyond it in this session — no additional keys of any kind, cost-related or
otherwise.

**Sweep.** Every captured payload was walked recursively with the regex
`rate.?limit|cost|usd|dollar|context.?window|quota|budget|spend|billing|remaining|five_hour|seven_day`.
**Zero matches.** The only `token` hits anywhere in the corpus were token counts (`input_tokens`,
`output_tokens`, and the cache variants) — the same figures `context_pressure` already reads
from the transcript, not from a hook payload.

An observational sweep only proves absence in the sessions run. It cannot prove the field is
never sent under some other tool sequence or account state, which is why the next section
matters more.

## Schema-level evidence

Observation says the field was absent from what was tried. The binary says it is absent from
what is *possible*, which is the stronger claim.

All 31 hook events implemented in the CLI binary share one Zod base object: `session_id`,
`transcript_path`, `cwd`, plus optional `prompt_id` / `permission_mode` / `agent_id` /
`agent_type` / `effort`. No per-event extension schema adds a cost or rate-limit member to any
of them. The strings `rate_limits` and `total_cost_usd` occur 45 times in the binary; **zero**
of those occurrences fall within 1500 characters of any `hook_event_name` string. The two
clusters do not overlap.

The only place in the whole binary that assembles `context_window`, `exceeds_200k_tokens` and
`rate_limits` (with `five_hour` / `seven_day`) together is the status-line input builder — and
it starts from the same shared base object and adds them there, for that one consumer, only.
This is exactly what the modules.md record already states from the same-build evidence; this
spike confirms it independently by walking the schema definitions directly rather than by
citing the earlier finding.

## On-disk survey

If the CLI does not hand the data to a hook, the remaining question is whether it persists the
data somewhere a hook-time script could read instead. It does not.

**The user-level CLI state file** (`~/.claude.json`) was checked for every plausible key:

- a per-project `lastCost`-shaped key, present on only some projects, valued `0`, and not
  written at all for a fresh session — not usable as a live figure
- `organizationRateLimitTier` — a static tier *name*, not a consumption number; it does not move
  as the window is used
- a passes-remaining counter, unrelated to the five-hour / seven-day rate windows the module
  would need
- assorted pricing and feature caches, none holding a live rate-limit or cost value

**The transcript JSONL** carries token counts only — input, output, cache-creation, cache-read —
which is the same source `context_pressure` already uses. No dollar figures. No rate-limit
members.

Neither location gives a hook anything the hook payloads themselves don't already rule out.

## Two refinements to the existing record

The modules.md table is otherwise accurate, but two things surfaced in this spike that were not
in the original record:

1. **`PostToolUse` for the `Agent` tool specifically** carries `tool_response.toolStats`
   (`linesAdded`, `linesRemoved`, `readCount`, `editFileCount`, and siblings) plus
   `tool_response.usage` and a `totalTokens` figure. This is genuinely hook-reachable data —
   unlike everything else checked in this spike. It does not flip the verdict, because it is
   scoped three ways at once: per-subagent-invocation only, `Agent`-tool-only (no other tool's
   `PostToolUse` carries anything like it), and dollar-free — token and line counts, never cost
   or rate-limit figures. See the amended row in
   [Modules](modules.md#attempted-and-blocked-ratelimit_escalation-and-cost_tracking).
2. **`claude --output-format json` of a newly spawned session** returns a real `total_cost_usd`
   in its result object. This is not a viable source either: it is the **child session's**
   result, produced only once that child session ends, not hook-time data describing the
   session the hook is running inside of. A monitor cannot spawn a session per turn to read its
   own cost back.

## What would flip the verdict

Either of two changes, and nothing short of them:

- the CLI adding `rate_limits` / `cost` to the shared 31-event base object — one change that
  would light up every hook at once, rather than a per-event addition
- a CLI release that persists either figure to a documented, hook-time-readable file (the
  status-line input is assembled at status-line render time, not at hook time, and today
  nothing else writes it to disk)

## Why this spike, not a `monitors/` directory

The plugin's own self-check rule is that a file existing is not evidence a monitor can fire
(see `lib/session_start.ps1`). A `monitors/monitors.json` naming `ratelimit_escalation` or
`cost_tracking` before either has a reachable data source would be exactly that defect: a name
shipped ahead of the code that could make it true, counted as coverage by anyone who reads the
directory listing rather than runs the check. So this spike produced a docs record instead of a
`monitors/` directory, and none was created.

## Footnote: hook events beyond this plugin's documented set

The same binary walk that produced the schema-level evidence above also turned up hook events
this plugin's docs do not name: `PostToolBatch`, `PostCompact`, `PermissionRequest`,
`PermissionDenied`, `Setup`, `TeammateIdle`, `TaskCreated`, `TaskCompleted`, `Elicitation`,
`ConfigChange`, `WorktreeCreate` / `WorktreeRemove`, `InstructionsLoaded`, `CwdChanged`,
`FileChanged`, `DirectoryAdded`, `MessageDisplay`. None of them carries cost or rate-limit data
either — the schema-level check above covers all 31 events in the binary, not only the twelve
this spike instrumented. Recorded here as a footnote, not a lead: it does not change the
verdict, and none of them was probed live.
