# LW-WATCHTOWER — Session Transition Signals and the Effort Health Daemon

**Spec for implementation. Version 1.0, 2026-09-01.**
**Target:** `lw-watchtower` plugin, currently v0.4.0, mode `observe-only`, 9/10 modules active.
**Author's note:** this spec was written after a session that died on a rate limit with nine
subagents in flight. Every design choice below traces to something that failed that day, and each
is labelled with the evidence rather than the intuition.

---

## 0. READ THIS FIRST — the constraint that shapes everything

**Two modules with these names were already attempted and are recorded as unbuildable.**
`ratelimit_escalation` and `cost_tracking` were removed from [`config.json`](../config.json) on 30 July 2026 and the
reason is preserved in [`modules.md`](modules.md) under *"Attempted and blocked"*, re-confirmed by an
independent spike on 31 July 2026 ([`monitors-spike.md`](monitors-spike.md)).

The finding, verified against the `claude-code 2.1.220` binary across **all 31 hook events**:

| Field | Where it exists | Reachable from a hook? |
|---|---|---|
| `rate_limits.five_hour` / `.seven_day` | status-line input only | **NO** |
| `context_window.used_percentage` | status-line input only | **NO** |
| `cost.total_cost_usd` | status-line input only | **NO** |

> *"`rate_limits`, `context_window`, `cost` and `workspace` are assembled in exactly **one** place in
> the whole binary — the status-line input builder... **No hook event carries any of them.**"*

**This spec does not re-attempt either module and must not be read as doing so.** It does the one
thing that record leaves open, and states it plainly:

> **The only process on the machine that receives rate-limit and context data is the status line —
> and today it renders that data to the terminal and discards it.** [`statusline/statusline.ps1`](../statusline/statusline.ps1) contains no
> write of `used_percentage`, `resets_at`, `five_hour` or `seven_day` to any file.

**Everything in this spec follows from closing that one gap.** The status line becomes the *only*
producer of the signal; every other component is a consumer of a file. A hook still never reads
`rate_limits`, so the blocked-module record stands unviolated.

**Do not** add `ratelimit_escalation` or `cost_tracking` back to the `modules` block. The modules
below are new names with new, reachable data sources.

---

## 1. Why this exists — the failure being engineered against

On 2026-09-01 a session ran 84 subagents across five feature branches. The 5-hour usage meter was
read **once**, at 54%. Nothing read it again. The session then hit its limit with **nine agents
running**, all of which died mid-task. Recovery cost:

- One commit (`24d4f21`) was **committed but unpushed** and survived only because the orchestrator
  manually searched for stranded work rather than trusting "all branches pushed".
- Three worktrees held **uncommitted, unverified** work that had to be extracted as patches by hand.
- Two agents died **between measuring a defect and filing the issue for it**, so two dry-run-fatal
  findings existed only in conversation and had to be re-filed from transcript.
- One agent died at the literal word `"Committing."` and had not committed.

**The diagnosis is not "there was no procedure."** A standing rule existed — *halt at 93% of the
5-hour window and land all work* — and it was in the orchestrator's persistent memory. **The failure
was that nothing interrupted anyone.** A rule that must be remembered by a process that is running
out of budget is not a control.

### 1.1 The design consequence: push, not pull

| | Fires on its own | Has repo access + judgement | Verdict |
|---|---|---|---|
| **Skill** | no — must be invoked | yes | wrong place for *detection* |
| **Hook** | yes, on specific events | limited; must stay fast | wrong place for *transition* |
| **Daemon** | yes, continuously | yes | right place for *watching* |

**Detection and alerting go in the plugin. The transition procedure goes in a skill that the
plugin's alert names.** A skill alone would have sat uninvoked on 2026-09-01; a hook alone cannot do
a multi-minute landing.

### 1.2 The threshold correction — budget × exposure, not budget

The current `thresholds.ratelimit` is `warn_pct: 88`, `land_all_pct: 92`. **The percentage is the
wrong variable on its own.**

> At **92% with zero agents running**, you are fine — one turn lands everything.
> At **70% with nine agents holding uncommitted work in nine worktrees**, you are already in danger.

The harm is never "the meter reached a number". The harm is **reaching the number while holding
unlanded work**. Every trigger in this spec is a function of *budget remaining* **and** *exposure*.

---

## 2. Components

Four pieces. Each is separately testable and separately shippable.

```
  status line  ──writes──▶  signal file  ──read by──▶  effort daemon  ──asyncRewake──▶  session
  (only producer)                             ▲                │
                                              │                ▼
   PostToolUse(Agent) ──writes──▶  effort ledger  ◀──registers──  orchestrator
                                   (git + agent state)
```

| # | Component | Kind | New/changed |
|---|---|---|---|
| **A** | `signal_bridge` | change to [`statusline/statusline.ps1`](../statusline/statusline.ps1) | **BUILT 2026-09-01** |
| **B** | `effort_ledger` | new module, `PostToolUse(Agent)` + `SubagentStop` | **new** |
| **C** | `effort_daemon` | new out-of-process poller | **new** |
| **D** | `/lw-transition` | new skill | **new** |

---

## 3. Component A — `signal_bridge`

**The only new access to rate-limit data on the machine. Everything else consumes its output.**

### 3.1 Change

> **CORRECTED 2026-09-01, AND THE CORRECTION IS THE FILE NAME.** This section named
> `bin/lwg-status.ps1` as the receiver of the status-line input. **It is not one.** That script takes
> a single `[switch]$Brief`, reads no stdin, and the string `rate_limits` occurs in it zero times; it
> was the backing script for the `status` command and rendered the module table. The process the CLI
> actually hands the status-line payload to is
> [`statusline/statusline.ps1`](../statusline/statusline.ps1) — which reads
> `$d.rate_limits.five_hour`, `$d.rate_limits.seven_day` and
> `$d.context_window.used_percentage` — and both [`config.json`](../config.json)'s `thresholds`
> comment and [`modules.md`](modules.md) already name that file independently. **Component A was
> built there.** The wrong name is corrected rather than left standing, per this project's rule that
> a record is amended in the open.

[`statusline/statusline.ps1`](../statusline/statusline.ps1) already receives the status-line input object containing `rate_limits`,
`context_window` and `cost`. **It must write those fields to disk before rendering.**

- **Write target:** `$CLAUDE_PLUGIN_DATA/signals/ratelimit.json`
  (live path today: `~/.claude/plugins/data/lw-watchtower-skills-dir/signals/ratelimit.json`)
  > **AS BUILT:** written to `signals/ratelimit.json` under **every** discovered data directory, not
  > one. The status line is a `settings.json` command and is therefore *never* given
  > `CLAUDE_PLUGIN_DATA`, while its consumers — hooks — always are, so a single literal path splits
  > producer from consumer. The union is the same discipline the file already applies to reading the
  > health logs.
- **Write discipline:** write to `ratelimit.json.tmp`, then `Move-Item -Force`. A reader must never
  see a half-written file. The status line runs on every render; a torn read is otherwise certain.
  > **AS BUILT:** the temp name carries the PID — `ratelimit.json.<PID>.tmp`. Every concurrent
  > session runs its own copy of this script against the same directory, so a *fixed* temp name means
  > two writers sharing one file and one of them publishing the other's half-written bytes, which is
  > the tear this rule exists to prevent.
- **Cost budget:** one small JSON write per render. If this measurably slows the status line,
  **throttle to one write per 5 s** — but measure before adding the throttle, and record the
  measurement in `docs/`, not in a comment.
  > **AS BUILT — measured, and NO THROTTLE SHIPPED.** On this machine in a fresh PowerShell 5.1:
  > **1.87 ms** per render at one data directory, 3.48 ms at two, 6.19 ms at four — about 1.5 ms per
  > additional directory. The first `Get-ChildItem` in the same function already costs ~178 ms, so the
  > bridge is roughly **1%** of a cost this file already accepts. The throttle was conditional on the
  > write proving measurable against that; it did not, so it was not added. Recorded in
  > [`architecture.md`](architecture.md#the-signal-bridge) as this bullet requires.

### 3.2 Schema

```json
{
  "schema": 1,
  "written_utc": "2026-09-01T13:02:11Z",
  "session_id": "<session_id from the status-line input>",
  "five_hour":  { "used_percentage": 54, "resets_at": 1788267600 },
  "seven_day":  { "used_percentage": 31, "resets_at": 1788700000 },
  "context_window": { "used_percentage": 62 },
  "unparsed": ["five_hour.used_percentage"]
}
```

> **AS BUILT — two deviations from this block as originally written, both deliberate.**
>
> **`cost` is NOT written.** It was in this schema and §9 puts dollars out of scope; the two
> contradicted each other. §9 wins. `statusline/statusline.ps1` has never read `$d.cost`, and
> persisting it would make the bridge the first reader of a field the blocked-module record calls a
> dead end — for a consumer that, by §9, may not use it.
>
> **`unparsed` is new.** Rule 1 below names two input states; `AsNum` in the renderer discriminates
> **three** — absent, usable, and *present-but-unparseable* — and the row deliberately paints the
> third a purple `??` rather than a green figure, precisely so it is not read as an all-clear.
> Writing an unparseable value as *absent* would collapse *"the CLI did not supply this"* into
> *"the CLI supplied something I could not read"*, one function away from where the renderer argues
> against exactly that. So an unparseable figure is omitted from its own block **and** its dotted
> path is listed here. The key is omitted entirely when empty.

**Rules the writer must follow, and each exists because its opposite has already shipped a bug in
this plugin:**

1. **A field absent from the input is absent from the file. Never write a zero, a null or a
   default.** A reader must be able to distinguish *"the CLI did not supply this"* from *"the value
   is 0"*. This is the `Get-LwgRepo` defect (`payload.workspace.repo`) that [`modules.md`](modules.md)
   records; do not repeat it one directory over.
2. **`written_utc` is mandatory.** Every consumer treats a stale file as no signal at all — see §5.3.
3. **`schema` is mandatory** and consumers refuse an unknown version rather than guessing.

### 3.3 What this does NOT do

It does not decide anything, warn anyone, or block. It is a bridge. **If the status line stops
running — a different status line configured, the CLI upgraded — the file simply goes stale, and
every consumer is required to notice that rather than to trust the last value.**

---

## 4. Component B — `effort_ledger`

**Answers "what is in flight and what would be lost right now."** This is the *exposure* half of
every trigger, and it is the half that did not exist on 2026-09-01.

### 4.1 Data sources — all reachable from hooks today

| Source | Event | Fields |
|---|---|---|
| Subagent dispatch | `PostToolUse` matcher `Agent` | `tool_response.usage`, `totalTokens`, `toolStats.linesAdded/linesRemoved/editFileCount`, `agent_id`, `agent_type` |
| Subagent completion | `SubagentStop` | `agent_id`, `agent_type`, `agent_transcript_path` |
| Session start | `SessionStart` | `session_id`, `cwd` |

**`PostToolUse(Agent)` carrying `tool_response.usage` and `totalTokens` is the exception the
31 July spike found** ([`monitors-spike.md`](monitors-spike.md), *"Two refinements to the existing record"*). It is
per-invocation, `Agent`-tool-only and dollar-free. **That is sufficient here and it is not
sufficient for `cost_tracking`** — this module reports token spend and work-at-risk, never dollars,
and must not be described as cost tracking in any banner or doc.

### 4.2 Ledger file

`$CLAUDE_PLUGIN_DATA/signals/efforts-<session_id>.json`

```json
{
  "schema": 1,
  "session_id": "...",
  "updated_utc": "2026-09-01T13:02:11Z",
  "efforts": [
    {
      "agent_id": "...",
      "name": "preflight-fix",
      "agent_type": "lw-implementer",
      "state": "running",
      "started_utc": "...",
      "last_seen_utc": "...",
      "total_tokens": 184203,
      "worktree": "C:/Temp/cpt-preflight",
      "branch": "feat/preflight",
      "issue": 155
    }
  ]
}
```

`state` ∈ `running` | `completed` | `failed` | `stale`.

### 4.3 Coordination with the Orchestrator — the registration contract

**The hook layer knows `agent_id` and `agent_type`. It does NOT know which worktree, branch or issue
an agent owns.** That mapping exists only in the orchestrator's head, and on 2026-09-01 that is
precisely why nobody could enumerate what was at risk.

**The contract:** the orchestrator writes one line per dispatch to
`$CLAUDE_PLUGIN_DATA/signals/registry-<session_id>.jsonl`:

```json
{"name":"preflight-fix","worktree":"C:/Temp/cpt-preflight","branch":"feat/preflight","issue":155,"registered_utc":"..."}
```

The daemon joins registry to ledger **by `name`**, and reports any effort present in one and absent
from the other rather than silently dropping it. **An unregistered running agent is itself a
finding** — it means work is happening in a location nobody is watching.

**This must be advisory, not enforced.** An orchestrator that forgets to register still gets its
agents watched by `agent_id`; it just loses the worktree join. **Never make dispatch depend on
registration succeeding** — a monitoring layer that can block work is worse than no monitoring
layer, which is why `delegate_gate` is the only gate this plugin ships and it ships off.

---

## 5. Component C — `effort_daemon`

**The piece that did not exist and whose absence caused the failure.**

### 5.1 Why a daemon and not a hook

Hooks fire on events. **Between `SubagentStop` firings, nine agents can run for twenty minutes with
nothing observing them.** Worse: an agent that hangs, or whose process dies without a clean stop,
may produce no event at all. `SubagentStop` tells you an agent *finished*; nothing tells you an
agent is *still running and the budget is nearly gone*.

**The daemon is the only component that can observe the passage of time.**

### 5.2 Lifecycle

- **Started by** `SessionStart` (`lib/session_start.ps1`), detached, one per session.
- **Stopped by** `Stop`, and by a heartbeat check: if the parent session id is gone, exit.
- **Single instance** enforced by a lock file carrying its own PID, `$CLAUDE_PLUGIN_DATA/signals/daemon.lock`.
  **Fail closed: never reclaim a lock you cannot prove is yours, and do NOT implement PID-liveness
  reclaim.** `os.kill(pid, 0)`-style checks are unreliable on Windows and PID reuse turns a wrong
  answer into a reclaimed *live* lock. A missed daemon start is recoverable; two daemons writing one
  file is not. *(This ruling was made and tested on `feat/149-shadow-d7` on 2026-09-01; the same
  reasoning applies unchanged.)*
- **Poll interval:** 60 s default, `daemon.poll_seconds` in `config.json`.
- **Must be cheap.** Target under 200 ms per poll. It reads files and runs `git status --porcelain`
  per registered worktree; nothing else.

### 5.3 What it computes each poll

```
  budget      = min(five_hour.used_percentage, seven_day.used_percentage adjusted)   [from A]
  signal_age  = now - ratelimit.written_utc
  burn_rate   = d(used_percentage)/dt over the last N polls
  in_flight   = count(efforts where state == running)
  dirty       = count(registered worktrees with non-empty git status --porcelain)
  unpushed    = count(registered branches with commits not on origin)
  exposure    = in_flight + dirty + unpushed
```

**`signal_age` is load-bearing.** If the file is older than `daemon.signal_stale_seconds`
(default 120), the daemon **must report "signal unavailable" and must not reuse the last value.**
A stale meter read as current is how the 2026-09-01 session believed it was at 54% for four hours.

### 5.4 Trigger table

| Tier | Condition | Action |
|---|---|---|
| **GREEN** | `budget < warn_pct` and `exposure` any | log only |
| **AMBER** | `budget ≥ warn_pct` **or** projected to cross `land_all_pct` before `resets_at` at current `burn_rate` | **advise**: name the exposure, recommend landing in-flight work before dispatching more |
| **RED** | `budget ≥ land_all_pct` **or** (`budget ≥ warn_pct` **and** `exposure ≥ daemon.exposure_limit`) | **interrupt**: `asyncRewake`, name `/lw-transition`, enumerate every dirty worktree and unpushed branch by path |
| **BLACK** | signal unavailable for > `signal_stale_seconds` **and** `exposure > 0` | **interrupt**: state that the meter cannot be read and that work is at risk. **Do not guess the budget.** |

`daemon.exposure_limit` default **3**. Rationale: three concurrent efforts is the point at which an
orchestrator can no longer land everything inside one or two turns. **This number is a judgement,
not a measurement, and must be labelled as such wherever it is documented.**

**BLACK exists because of §3.3.** The most dangerous state is not "budget low" — it is "budget
unknown while holding work", and a system that only alerts on a number can never report it.

### 5.5 Alert mechanism — use what exists, add nothing

The plugin already has the contract: **`asyncRewake` with exit 2**, documented in [`lib/common.ps1`](../lib/common.ps1)
(the CLI ignores stdout and reads stderr under exit 2). The orchestrator's standing instruction is
to treat such a notification as an interrupt.

**Do not invent a second alerting path.** Emit through `Write-LwgAdvisory` / the existing advisory
plumbing so the message reaches both the state file and the session.

**Alert body must carry, in this order:**
1. **The tier and the number**, with `written_utc` so the reader can judge freshness.
2. **The exposure, enumerated by path** — not a count. `C:/Temp/cpt-shadow (4 files dirty)` is
   actionable; `exposure: 9` is not.
3. **The named next action:** `/lw-transition`.
4. **What it could not determine.** If the registry join failed for an agent, say so.

---

## 6. Component D — the `/lw-transition` skill

**The runbook. Invoked by the alert, or by the operator. Never fires on its own — that is the
daemon's job.**

### 6.1 Responsibilities

1. **Re-derive, never trust.** Read the signal file fresh; re-derive every branch head with
   `git ls-remote`; re-derive dirty state per worktree. The daemon's ledger is a *pointer to where
   to look*, not evidence.
2. **Enumerate stranded work** in this order, because this is the order in which it was nearly lost:
   - commits **committed but unpushed** (highest risk — invisible to `git status`)
   - **uncommitted** changes in registered worktrees
   - findings that exist **only in conversation** — measurements taken, issues not yet filed
3. **Preserve before deciding.** Write patches for every dirty worktree to a stable path
   (`C:/Temp/cpt-wip-patches/` was used on 2026-09-01 and worked). **Verify each patch reverse-applies
   against its worktree** — an unverified patch is not a backup.
4. **Land what is verifiable.** Push committed work. Do not commit unverified mid-edit work to a
   feature branch; preserve it as a patch and record where.
5. **Write the handoff**, and mark every figure's provenance: measured-by-this-session versus
   relayed-from-an-agent. *(On 2026-09-01 the handoff stated relayed figures with the document's
   authority — the exact defect the session had spent the day removing.)*
6. **Report what could not be landed and why.**

### 6.2 Two transitions, not one

| Signal | Meaning | Transition |
|---|---|---|
| **5-hour** exhausted | wait and resume | land, handoff, **stop**. Session resumes after `resets_at`. |
| **7-day** exhausted | re-plan the week | land, handoff, **and say so** — the next session cannot simply retry. Scope must shrink. |
| **Context window** high | compaction imminent | land, handoff, **clear** — a fresh session with a good handoff beats a compacted one. |

**These are different outcomes and the skill must not collapse them.** `context_pressure` already
handles the third signal today; `/lw-transition` should call it rather than reimplement it.

---

## 7. Configuration

Add to `config.json` under a new `daemon` key. **Do not add anything to the `modules` block until
the code exists** — a `true` flag is a forward-declaration, not coverage, and that rule is the
plugin's own.

```json
"daemon": {
  "enabled": false,
  "poll_seconds": 60,
  "signal_stale_seconds": 120,
  "exposure_limit": 3,
  "registry_join": true
}
```

**Ships `false`.** Every new module in this plugin ships off until it has been run against real
sessions; `mission_drift` shipping `true` before its trigger was validated is recorded in
`config.json` as a mistake worth not repeating.

Existing `thresholds.ratelimit` (`warn_pct: 88`, `land_all_pct: 92`) is **reused unchanged** so the
status line and the daemon cannot disagree about what "warn" means.

---

## 8. Acceptance criteria

**Each of these must be demonstrated by a run, not by reading the code.**

| # | Criterion | Evidence required |
|---|---|---|
| 1 | The signal file is written and is never torn | 1000 concurrent reads during continuous status-line renders; zero parse failures |
| 2 | An absent CLI field is absent from the file | force an input with no `rate_limits`; assert the key is missing, not zero |
| 3 | A stale signal produces BLACK, not a stale number | stop the status line, hold `exposure > 0`, assert the alert says *unavailable* |
| 4 | Exposure is enumerated by path | dirty two worktrees; assert both paths appear in the alert body |
| 5 | An unregistered running agent is reported | dispatch without registering; assert the daemon names it |
| 6 | The daemon never blocks | kill it mid-poll during a dispatch; assert the dispatch completes |
| 7 | Two daemons cannot run | start twice; assert the second refuses and the first is unaffected |
| 8 | A crashed daemon's lock is NOT auto-reclaimed | kill -9; assert the next start refuses and says how to clear it by hand |
| 9 | RED fires on exposure below `land_all_pct` | set budget to `warn_pct + 1`, exposure 4; assert RED |
| 10 | `/lw-transition` recovers an unpushed commit | commit without pushing in a registered worktree; assert the skill finds and reports it |

**Criterion 10 is the one that matters most.** It is the exact loss that nearly occurred.

---

## 9. Explicitly out of scope

- **Dollar cost.** Not reachable, and `cost_tracking` is a recorded dead end. Token counts only.
- **Any gate.** Nothing here blocks a tool call. This is `observe` kind throughout.
- **Reading `rate_limits` from a hook.** Architecturally impossible; the bridge exists because of it.
- **Predicting the model's own token spend.** The daemon observes; it does not forecast beyond a
  linear burn-rate projection, and that projection must be labelled as a projection in the alert.

---

## 10. Risks, stated rather than discovered

**The status line is a single point of failure.** If it is replaced or misconfigured, every signal
goes dark. Mitigation is BLACK tier (§5.4) — the system must be loud about blindness. **A monitor
that fails silent is worse than no monitor**, because it converts "I don't know" into "I'm fine".

**Poll cost on a saturated machine.** On 2026-09-01, suites took 5–6 minutes instead of 3 because
several agents ran concurrently. A 60 s poll running `git status` across nine worktrees adds to
that. **Measure before shipping and record the measurement.**

**The registry depends on orchestrator discipline.** It will be forgotten. §4.3 requires the daemon
to work degraded rather than fail — and to say it is degraded.

**A CLI upgrade can invalidate §0.** The blocked-module record was re-confirmed on 31 July 2026 and
[`modules.md`](modules.md) states it needs repeating after any CLI upgrade. **The same applies to this
spec's premise that the status line is the sole producer.** Re-verify on upgrade; if a hook ever
carries `rate_limits`, Component A becomes unnecessary and should be deleted rather than left as a
second source of truth.

---

## 11. Build order

1. **A** — `signal_bridge`. Smallest, unblocks everything, independently useful.
2. **B** — `effort_ledger` from hooks alone (no registry join). Useful without C.
3. **D** — `/lw-transition` reading A + B. **Delivers most of the value with no daemon at all**, and
   is the piece an operator can invoke manually today.
4. **C** — `effort_daemon`. Last, because it is the only always-on process and therefore the one
   with the most ways to be wrong.

**Stop after any step and the system is better than it is now.** Nothing here requires the whole
stack to land before it earns its keep.
