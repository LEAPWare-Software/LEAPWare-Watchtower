# Metrics

**What this page is.** The data sources, the definitions and the limits behind
[`/lw-watchtower:metrics`](commands.md#lw-watchtowermetrics) — the command that reads the Claude
Code transcripts already on your disk and reports how much work left the main thread, what it
cost in tokens, and whether delegation is happening at all.

**Why it exists.** The plugin could not prove it saved anyone anything. The owner asked what they
gain from routing work to subagents, and the honest answer was that nobody had measured it. This
is the measurement.

**What it is not.** This is the first slice of [issue #165](https://github.com/LEAPWare-Software/LEAPWare-Watchtower/issues/165),
and it is the transcript indexer and the scoreboard, as a command, reading only files that
already exist. There is **no hook, no ledger file, no `METRICS.md`, no usage-meter history, no
LCAP round capture, no landing detection and no keep-or-revert decision rule.** Every column with
no source prints `NOT DETERMINED`, on every run, with the requirement it is waiting on. That is a
requirement of this slice and not a fallback: a scoreboard that invents a number is worse than
one that says it cannot tell.

**No dollars.** Anywhere. The operator's subscription is metered in two rolling buckets, not in
currency, and nothing in this module reads or prints a cost in money.

---

## What it reads

Two things, both already on the disk. Nothing else, and **nothing at all is written**.

| Source | Where | What is taken from it |
| --- | --- | --- |
| Claude Code transcripts | `<configuration root>/projects/**/*.jsonl` | every token figure, every model id, every dispatch |
| This plugin's own ledger | `health.jsonl` in the state directory | a `SubagentStop` count, as a cross-check only |

The configuration root is resolved by `Get-LwgClaudeHomeInfo` in
[`lib/common.ps1`](../lw-watchtower/lib/common.ps1) — `CLAUDE_CONFIG_DIR` first, then the user
profile. The report **names the variable that resolved it and never prints the path**, because
the directory names underneath it are working directories with their separators replaced and
therefore carry the operator's account name.

### The transcript layout, as verified on 2026-09-06

```
<configuration root>/projects/
  <cwd-slug>/
    <sessionId>.jsonl                                  the main thread
    <sessionId>/subagents/agent-<17 hex>.jsonl         one dispatch
    <sessionId>/subagents/agent-<17 hex>.meta.json     that dispatch's request
    <sessionId>/subagents/workflows/wf_<id>/agent-*.jsonl   a workflow child
    <sessionId>/subagents/workflows/wf_<id>/journal.jsonl   workflow bookkeeping
    <sessionId>/tool-results/<toolUseId>.txt           spilled tool output
```

The enumeration **recurses**, and that is load-bearing: workflow children sit one directory
deeper than a plain dispatch, and a flat scan drops them silently — which makes the delegation
figure, the one thing actually asked for, come out low with nothing to say that it did. On the
machine this was written on, nine workflow directories were present.

`journal.jsonl` is counted as **unclassified** and contributes nothing. It is workflow
bookkeeping, not a conversation, and the report prints how many it skipped rather than folding
them into a total.

---

## The fields it reads, and the ones it looked for and did not find

Every row below was checked against the real transcripts on this machine on **2026-09-06**
(Claude Code `2.1.259`). Anything marked *not present here* is not a guess about the format — it
is a field the specification names that no file on this disk carries.

### On a `type: "assistant"` line

| Field | Read? | Notes |
| --- | --- | --- |
| `message.id` | **yes** | the dedupe key — see below. Load-bearing |
| `message.model` | **yes** | the model that actually ran the request |
| `message.usage.input_tokens` | yes | |
| `message.usage.cache_read_input_tokens` | yes | |
| `message.usage.cache_creation_input_tokens` | yes | |
| `message.usage.output_tokens` | yes | |
| `message.usage.output_tokens_details.thinking_tokens` | yes | reported **beside** output, never added to the composite — it is a subset of `output_tokens` |
| `isSidechain` | yes | `true` on a subagent's lines; how main-thread work is told from delegated work |
| `agentId` | yes | present on subagent lines |
| `sessionId` | yes | |
| `cwd` | yes, **never printed** | handed to `Get-LwgRepoInfo` to get a repository slug, and discarded |
| `timestamp` | yes | earliest and latest in the index |
| `requestId` | no | duplicates share it, but `message.id` is the documented key and both agreed on every line checked |
| `apiBlockIndex` | no | the content-block index; not needed once the dedupe is on `message.id` |
| `advisorModel`, `effort` | no | see the limits below — no advisor usage is recorded anywhere |
| `message.usage.service_tier`, `cache_creation.ephemeral_*` | no | not needed for any figure this slice prints |

### On an `Agent` dispatch

A dispatch occupies **two lines** and the join between them was verified rather than assumed:

1. a `type: "assistant"` line whose `message.content[]` holds a `tool_use` block with
   `name: "Agent"`;
2. a `type: "user"` line whose `message.content[]` holds a `tool_result` block whose
   **`tool_use_id` equals that block's `id`**, and whose sibling `toolUseResult` object carries
   the outcome.

| Field | Read? | Notes |
| --- | --- | --- |
| `tool_use.input.subagent_type` | yes | the role the dispatch asked for |
| `tool_use.input.model` | yes | the **requested tier** — `opus`, `sonnet`, `haiku`, `fable`, or **absent**, which means inherit |
| `tool_use.input.description`, `.prompt` | read and discarded | operator-written free text that can carry an absolute path; it never leaves the reader |
| `toolUseResult.status` | yes | |
| `toolUseResult.agentId` | yes | equals the `<17 hex>` in the subagent transcript's file name |
| `toolUseResult.resolvedModel` | yes | the **resolved model**, printed verbatim, tag and all |
| `toolUseResult.agent_id` | branch present, **never seen here** | the `teammate_spawned` shape |

**Requested and resolved are two different facts and are never collapsed.** `resolvedModel`
carries an entitlement tag — `claude-opus-5[1m]` — while the subagent's own `message.model` says
`claude-opus-5`. Comparing them unstripped reports *every* dispatch as a disagreement, so the
comparison runs on the base id with the bracket tag removed, and the tag is still printed. (`[`
is also a wildcard in PowerShell's `-like`, which is the second reason that strip is a named
function rather than an inline comparison.)

### What the specification names and this machine does not have

These are reported as `NOT DETERMINED`, never as zero:

- **`toolUseResult.status: "completed"`.** 151 of the 153 `Agent` dispatches on this machine produced a result, and every one of those carried
  `async_launched`. `completed` is the only status that carries a `usage` object and a
  `totalTokens` — so **the transcript sums have no second opinion to be cross-checked against**,
  and the report says so on every run instead of implying a check it never ran.
- **`toolUseResult.status: "teammate_spawned"`** and the `agent-<name>-<16 hex>.jsonl` file shape
  that goes with it. Not one of the 243 subagent transcripts here uses that name shape; all 243
  are `agent-<17 hex>.jsonl`.
- **`toolUseResult.agentType`.** The issue names it; it is not in any result object here. The
  role comes from `input.subagent_type` and from the sibling `.meta.json`'s `agentType`.
- **`input.name`.** Named by the issue for the teammate join; no `Agent` input on this machine
  carries it. The keys actually present were `subagent_type`, `model`, `description`, `prompt`
  and `isolation`.
- **`.meta.json` `model`.** Present on 204 of 243 files; **absent on 39**. An absent requested
  tier is reported as absent, never defaulted to `opus`.
- **`health.jsonl`.** Not in the state directory on this machine, because the plugin has not run
  here. The dispatch cross-check is therefore `NOT DETERMINED` — which is not the same as zero
  dispatches, and the report distinguishes them.

---

## The one measurement everything else rests on

**One API response is written as several `assistant` lines — one per content block — and every
one of them repeats the identical `usage` object under the same `message.id`.**

Measured over the whole local corpus, in Windows PowerShell 5.1, on 2026-09-06:

| | |
| --- | --- |
| transcript files | 268 |
| assistant lines carrying a `usage` block | 36,649 |
| **distinct `message.id`** | **19,483** |
| duplicate lines discarded | 17,166 — **46.8 %** |
| ids seen carrying two *different* usage blocks | 0 |

So a naive per-line sum overstates by roughly **1.9×**. Usage is summed **once per `message.id`,
per file**. Per file rather than globally, because a message id is unique within a conversation
and keying the whole machine on it would let two sessions that happened to collide silently drop
a request.

`<synthetic>` lines carry a usage block and are **excluded** — 124 of them were on this machine.
The report counts them so it can say it excluded them.

### The arithmetic is 64-bit, and that is not decoration

The same corpus carries **4,479,419,249** cache-read tokens against an `[int]::MaxValue` of
2,147,483,647. Every accumulator is `[long]` from its first assignment, and
[`tests/metrics_behaviour.ps1`](../tests/metrics_behaviour.ps1) drives two 2,000,000,000 reads
through it so that an `[int]` cannot creep back in unnoticed. This is the one numeric bug that
would make the scoreboard silently wrong in the direction nobody checks.

### The four categories are never merged

`input`, `cache read`, `cache creation` and `output` are reported separately, and the
**composite** — their sum — is reported *beside* them and never instead of them. On a real
session the cache read is two or three orders of magnitude larger than everything else, so a
single headline number is a cache-read number wearing a different label.

---

## Definitions

- **Session** — one main-thread transcript file `<sessionId>.jsonl`. Its `subagents/` directory
  belongs to it, at any depth.
- **Dispatch** — one `Agent` `tool_use` in a main-thread transcript, joined to its
  `toolUseResult` on `tool_use_id`.
- **Attributed** — a dispatch whose `agentId` matches a subagent transcript in the same session.
- **A transcript no dispatch claims** — a subagent transcript with no matching `Agent` `tool_use`
  in the main thread. This is **large and it is not an error**: a nested child or a workflow step
  is launched by a subagent, so the call that started it was never in the main transcript at all.
  The two counts are shown separately, exactly because they differ.
- **Project** — the repository slug `owner/name` that `Get-LwgRepoInfo` resolves from a session's
  working directory. Worktree clones of one remote are one project. A session whose working
  directory no longer resolves is counted in the totals and in no project, and the report says
  how many.
- **Cohort** — assigned **per session** from the dominant main-thread model, by deduplicated
  request count, with a **60 %** floor. Below the floor, or on a tie, the session is `mixed`. A
  session with no main-thread assistant line at all is `unknown`. `mixed` and `unknown` are
  different and are never merged. **The cohort is never a date range** — the main thread ran
  different models on different days of the same week, so any comparison keyed on dates mixes
  cohorts and proves nothing.
- **Requested / resolved disagreement** — the dispatch named a tier and the model that ran it was
  from another family. A point release is not a disagreement: `claude-opus-5` and
  `claude-opus-4-8` are both `opus`. An alias the reader does not recognise counts as neither,
  so a new tier name cannot become a disagreement on every dispatch that uses it.

---

## What it cannot tell you

Printed in the report's own `COULD NOT DETERMINE` block on **every** run, including green ones.

1. **Usage this machine cannot see.** Another device, a browser session, and the advisor tool.
   Assistant lines carry an `advisorModel` field and **no advisor usage appears in any transcript
   read**, so every token figure is a **floor**, not a total.
2. **The usage meter.** The 5-hour and 7-day percentages are the only thing the subscription
   actually charges against, and they are overwritten on every status-line render. No history
   exists, so tokens cannot be converted into a share of either bucket at all.
3. **Landings.** Not detected in this slice, so every median is **per session**, not per landing,
   and no ratio here is the one the decision rule reads.
4. **Review quality.** Nothing on this machine has ever recorded an LCAP round. Until an agent
   emits the trailer, rounds-to-clean, findings by severity and the gate-2 leak rate stay
   unknown — and are reported as unknown rather than as a clean sheet.
5. **Post-merge defects.** They need `gh` timeline calls; this command makes no network call.
6. **The verdict.** A STAY/REVERT/EXTEND call needs four inputs and three of them are in this
   list. Producing one from the fourth would be the exact failure the issue was opened about: a
   keep-or-revert decision made on impression, wearing a number.
7. **Retention.** The transcript window slides daily. A cohort older than the earliest date in
   the `INDEX` block is not missing from the report — it has been deleted from the disk. **On the
   machine this page was written on the oldest transcript was five days old**, which is the dated
   cost of having sequenced this work later rather than sooner, stated rather than hidden.

---

## Cost of running it

A full scan of the local corpus — 268 files, 254 MB — took **19–21 seconds** in Windows
PowerShell 5.1 on the machine this was written on. Lines are rejected on two substring tests
before anything is parsed, and files are read with `[IO.File]::ReadLines`, which streams;
`Get-Content` over the same corpus is minutes.

**There is no index cache in this slice, on purpose.** The issue specifies one; a cache is a file
the uninstaller has to know about, the footprint suite has to seed, and the operator has to be
told about. The scan time is printed on every run, so the case for a cache can be made from a
measurement rather than from an assumption.

**No hook runs any of this.** The command is the only thing that reads the corpus, and it only
runs when somebody types it.

---

## Where the cases are

[`tests/metrics_behaviour.ps1`](../tests/metrics_behaviour.ps1) — see
[Testing](testing.md#the-metrics-behaviour-suite). It is one of two files added under `tests/`
under a waiver granted once by the owner on 6 September 2026; the standing rule is that `tests/`
takes no new file and cases go in the suite that owns the behaviour, and no existing suite owns a
`bin/` script it is not named after.
