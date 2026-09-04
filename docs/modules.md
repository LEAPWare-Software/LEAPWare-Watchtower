# Modules

Eleven module names exist. **All eleven are built.** There is no name here with no code behind it.
**Seven ship enabled; four — `send_liveness_gate`, `completion_audit`, `orphan_watch` and
`delegate_gate` — ship switched off**, and off is where each of them is meant to be.

There were thirteen until 30 July 2026, and that day four went and one arrived, each by an explicit
owner decision. **Both of the old gates were removed** — `destructive_gate` first, `secret_scan`
second — leaving no gate and no `PreToolUse` hook of any kind; see
[Both gates were removed](#both-gates-were-removed) for the narrative and
[Gates were removed deliberately](gates-removed.md) for the rules a new one has to follow.
**Then the two unbuildable placeholders were removed** — `ratelimit_escalation` and `cost_tracking`
— and the reasoning kept, at
[Attempted and blocked](#attempted-and-blocked-ratelimit_escalation-and-cost_tracking). The same day
the owner switched `mission_drift` **on**, and **`delegate_gate` was built** as the first gate on
this project's plan that could be built completely rather than partially — see
[`delegate_gate`](#delegate_gate). Two more gates followed on 1 August 2026,
`send_liveness_gate` and `completion_audit`, built from a measured failure rather than from a plan.

**`verification_gate` and `mission_drift` were removed on 2 September 2026**, along with the
`lw-class` role classifier that was `verification_gate`'s only reader. Neither name is in
`$LwgModuleRegistry` any more, neither has a flag in `config.json`, and the sections that described
them were deleted from this page rather than rewritten — a module that does not ship has no
behaviour to document. The narrative of what they were is in the git history and in
[CHANGELOG.md](../CHANGELOG.md).

The authoritative split lives in `$LwgModuleRegistry` in [`lib/common.ps1`](../lw-watchtower/lib/common.ps1),
which is what the session banner counts. **The flags in [`config.json`](../lw-watchtower/config.json) are never
counted as coverage** — a `true` flag is a forward-declaration, not evidence that code exists.

| Module | Kind | Status | What it is for |
| --- | --- | --- | --- |
| `failure_capture` | observe | **implemented** | Record tool, hook and subagent failures so nothing fails silently. |
| `self_health` | observe | **implemented** | Prove the governance layer itself can still fire. |
| `log_rotation` | observe | **implemented** | Cap `health.jsonl` and `lw-watchtower.jsonl`. It does **not** bound the state dir: `advisory-<sessionkey>.json` and `edits-<sessionkey>.txt` are one file per session each and nothing sweeps them. |
| `context_pressure` | observe | **implemented** | Warn before the context window forces a lossy compaction. |
| `docs_coupling` | observe | **implemented** | Flag source changes shipped without documentation. |
| `git_hygiene` | observe | **implemented** | Branch, commit and push discipline at turn end. |
| `context_injection` | observe | **implemented** | Hand every subagent facts that are current at *dispatch* time, because `CLAUDE.md` is snapshotted at session start. |
| `orphan_watch` | observe | **implemented** | Reconcile this session's subagent transcripts against its `SubagentStop` records and alert on one that was killed mid-flight, which otherwise produces no record anywhere. **Ships switched off**; its switch is `supervision.orphan_watch`, not a `modules` flag, and it is inert while `failure_capture` is off because those records are what `failure_capture` writes. |
| `send_liveness_gate` | **gate** | **implemented** | Refuse a `SendMessage` whose recipient it can *prove* is dead mid-flight. `PreToolUse` on `SendMessage`. **Ships switched off**; its switch is `supervision.send_liveness`. It denies on positive evidence of death and abstains — allows, logged — wherever the evidence cannot support a verdict. |
| `completion_audit` | **gate** | **implemented** | Refuse a turn end whose final assistant text claims completed work when the turn's **last** tool action was a `SendMessage`: queued for delivery is not delivery. Registered on `Stop` and `SubagentStop`. **Ships switched off**; its switch is `supervision.completion_audit`. |
| `delegate_gate` | **gate** | **implemented** | Refuse `Edit`/`Write`/`NotebookEdit`/`Bash`/`PowerShell` for calls that did not come from a subagent, so the chat session is reserved for talking to the operator. **Ships OFF** — see [below](#delegate_gate). |

## Caveats on the eight that only observe

Read these before treating any module as coverage. Every module named below **observes**; not one of
them can stop anything. The three gates are the exception — [`delegate_gate`](#delegate_gate),
[`send_liveness_gate`](#send_liveness_gate) and [`completion_audit`](#completion_audit), each with
its own section below. All three ship switched off.

- `self_health` (the `SessionStart` self-check) honours its flag. With it **off** no probe runs at
  all, and the session reports mode `unverified` rather than any word that would imply it was
  validated. See [`self_health`](#self_health).
- `log_rotation` runs on **its own flag alone**. The rotation call sits above the
  `failure_capture` flag check in [`lib/supervisor.ps1`](../lw-watchtower/lib/supervisor.ps1), so switching failure
  capture off stops the writes to `health.jsonl` but never the cap on its size.
- `context_pressure` does not read a context percentage — no hook is given one. It recomputes
  occupancy from the transcript, and the window *size* is inferred. See
  [`context_pressure`](#context_pressure).
- `docs_coupling` sees **`Write`/`Edit`/`NotebookEdit` only**. A file rewritten by a shell command
  is invisible to it.
- `git_hygiene` is the **only module that spawns a subprocess**, and it does so on `Stop` only.
  Nothing outside a repo, nothing with the flag off. See [Turn-end cost](architecture.md#turn-end-cost).
- `context_injection` runs once **per subagent dispatch** and is the only module on that event.
  It injects, it never blocks — `SubagentStart` has no blocking channel at all.
- `orphan_watch` **ships switched off**, and its switch is `supervision.orphan_watch` rather than a
  `modules` flag. It runs inside [`lib/supervisor.ps1`](../lw-watchtower/lib/supervisor.ps1) *below*
  the `failure_capture` flag check, so `failure_capture` off means `orphan_watch` inert whatever its
  own switch says. See [`orphan_watch`](#orphan_watch).

## Gates, and what counts as one

**Gates** are the modules that can block an action rather than merely report one. **Three ship, and
every one of them ships switched off** — so there are two numbers here and collapsing them is the
mistake this section exists to prevent:

| Number | Value as shipped | What it means |
| --- | --- | --- |
| gates **shipped** | **3** | `delegate_gate`, `send_liveness_gate` and `completion_audit` are in `$LwgModuleRegistry` with `kind = 'gate'` and their hooks are registered. The capability exists and you own it. |
| gates **live** | **0** | `Get-LwgActiveGates` counts only gates that are *switched on*. `interaction.delegate` is `false` and both `supervision` gate switches are `false`, so nothing is blocking and a healthy session reads `observe-only`. No number in `config.json` asserts this; it is computed. |

Reporting only the first would claim protection that is switched off. Reporting only the second would
hide a capability the operator has and was never told about, and nobody turns on a thing they do not
know they have. `/lw-watchtower:doctor` prints both, plus a `GATES` block naming each gate's switch.

`observe-only` therefore holds as shipped, and `partial` is **reachable** by running
`/lw-watchtower:delegate on` — nothing else has to change. `enforcing` is not reachable that way, and
what it additionally requires is worked through under [Session modes](#session-modes). The ladder in
`Get-LwgSessionMode`
([`lib/common.ps1`](../lw-watchtower/lib/common.ps1)) returns `observe-only` on a **live** gate count of zero
*before* it ever tests whether a module is switched off. That ordering is deliberate: "some module is
off" is a smaller fact than "nothing can be blocked", and the smaller fact must not be the one a
reader sees.

A session banner from before 30 July 2026 reads `2 gates`, and one from the middle of that day reads
`1 gate` or `0 gates`. Each is a record of what was true then, not a target to get back to by
recounting.

## Both gates were removed

Both removals were explicit decisions of the repository owner, on **30 July 2026**, and are recorded
here rather than left to be inferred from an absence. This section is the single home for that
narrative; nothing else in `docs/` keeps a second copy to drift.

**`destructive_gate` went first.** It was a `PreToolUse` hook on `Bash|PowerShell` — its handler in
`lib/` is deleted — that refused force pushes, hard resets, `git clean -f`, history rewrites, reflog
expiry, recursive deletes and GitHub repository destruction, together with a rule in the write gate
that refused any write inside a `.git` directory. Removed with it: the 233-case regression suite, the
`lw-watchtower:verify` command that ran it, the `gate-regression` CI job, and four `permissions.deny`
groups — `git-destructive` (78), `filesystem-destructive` (34), `github-destructive` (18) and
`git-internals` (3), **133 of the installer's 181 rules**.

**`secret_scan` went second, and it was the last gate.** It was a `PreToolUse` hook on
`Write|Edit|NotebookEdit` — its handler in `lib/` is deleted — with two halves: a path half that
refused writes to `*.pem`, `*.key`, `id_rsa*`, `.env`, `.npmrc`, `hosts.yml` and `.credentials.json`,
and a content half that refused a write whose bytes carried a recognisable GitHub, AWS or Slack
token or a `password=` / `api_key=` assignment with a literal value. Removed with it: the two
remaining `permissions.deny` groups — `secret-paths` (30) and `secret-reads` (18), **the last 48
rules** — the `permissions.deny` parity test in `tests/`, its two fixtures, and the CI step that ran
it.

What that leaves, stated plainly rather than left to be discovered:

| Was covered | By what | Today |
| --- | --- | --- |
| a destructive shell command | `destructive_gate` hook + 133 deny rules | **nothing.** `delegate_gate`'s matcher does name `Bash` and `PowerShell`, but it decides on the caller and never on the command, so an armed gate refuses a `rm -rf` from the main thread and a subagent's identically; the installer writes no rule |
| a write inside `.git/` | the write gate's path rule + the `git-internals` group | **nothing.** `[core] sshCommand` in `.git/config` is arbitrary code execution on the next git command, and no layer here refuses it |
| a write to a credential file | `secret_scan` path half + `secret-paths` | **nothing** |
| a write whose content is a credential | `secret_scan` content half | **nothing** |
| a credential read through a shell command | `secret-reads` | **nothing** |

- **No registration in `hooks/hooks.json` reads any of the things this table is about.** The plugin
  registers on `SessionStart`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `SubagentStart`,
  `SubagentStop`, `Stop` and `StopFailure`. `delegate_gate` arrived later the same day and two more
  gates followed on 1 August 2026 — see [`delegate_gate`](#delegate_gate) — but `delegate_gate`
  decides on the *caller*, `send_liveness_gate` on whether a message's recipient is provably dead,
  and `completion_audit` on what the final assistant text of a turn claimed. None of the three reads
  a command, a path or the bytes of a write, so every **nothing** in the rows above stands with all
  three registered and armed.
- **The installer has no deny table left to be empty.** `/lw-watchtower:setup` writes **zero**
  `permissions.deny` rules, and since 2 September 2026 it has no code that could write one:
  `Get-DenyGroups` was deleted from [`bin/lwg-setup.ps1`](../lw-watchtower/bin/lwg-setup.ps1), and
  so were `-SecretGate` and `-DestructiveGate`. This page went on saying for a day afterwards that
  the function returned an empty table and the two parameters were *"still accepted and
  select nothing"* — both
  halves are now wrong, and the second is the one that matters: the parameters are not accepted, so
  passing either is a PowerShell binding error before any script code runs rather than a question
  whose answer selects nothing. Setup no longer asks. The only mentions of the three names left in
  the payload are comments in `bin/lwg-setup.ps1` and `bin/lwg-uninstall.ps1` recording that they
  went. See [Install](install.md#the-installer-writes-no-permissionsdeny-rules).
- **A machine set up before 30 July 2026 still carries the old rules** in its own `settings.json`,
  and the CLI still evaluates them. Nothing here renews them, and setup never removes a rule already
  in your file. `bin/lwg-uninstall.ps1` keeps the full description of all 181 families, because it
  is now the only code that knows what they looked like well enough to attribute and remove them.

**What was kept, and why it is not protection.** These read the past; none of them can produce a new
record:

| Kept | What it does now |
| --- | --- |
| `lw-watchtower.jsonl` | the append-only event log. It still holds every historical `GateDeny`. The `sitrep` command counted them under `GOVERNANCE` as history and went on 2 September 2026, so nothing counts them now. It is an audit trail, **not** a ledger — nothing can clear an entry in it |
| the secret regex patterns in `lib/common.ps1` | **log redaction only** (`Get-LwgRedacted`). Nothing scans a write with them |

**The trip ledger did not survive the day.** It was kept for a few hours as a historical reader and
then removed by a further explicit owner decision, along with the open trips themselves. Gone:
`lib/trips.ps1`, `lib/ack_trip.ps1`, `bin/lwg-tripped.ps1`, `commands/tripped.md`, the status line's
`GM` segment, the ledger-open branch in `lib/session_start.ps1` and the trip sweep in
`lib/stop_advisories.ps1`. The 12 `trips-<sessionkey>.json` files in the state directory — 64
uncleared trips between them — were backed up to `trips-backup-20260730/` and removed. **Nothing now
records, reads, closes or acknowledges a trip, and the status line has no governance segment.**

The removed code is recoverable from git history; [CHANGELOG.md](../CHANGELOG.md) names the commits.
It is not coming back by accident: this section is the record that it went.

**A gate did come back, and the machinery kept on purpose is exactly what it used.** `delegate_gate`
was built hours later the same day, and adding it needed one registry field: an entry declaring
`kind = 'gate'`, after which the count, the mode word and the banner followed on their own. **The
ledger and the status line still did not follow, and `delegate_gate` did not rebuild them** — a
denial is written to `lw-watchtower.jsonl` as a `GateDeny` event, nothing tracks it as an open item, and
the status line has no governance segment. Anything that wants a durable, clearable record of a
refusal still has to rebuild the ledger format, its writer, the acknowledge path, the turn-end sweep
and the indicator, in that order. Two more gates have been written since — `send_liveness_gate` and
`completion_audit`, on 1 August 2026 — and **neither rebuilt the ledger either**. What that costs,
and what the four failed fix attempts on the last removed gate actually taught, is written up in
[Gates were removed deliberately](gates-removed.md). Read it before writing another `PreToolUse`
hook.

## `delegate_gate`

**The first gate this plugin shipped after the removals. Off by default**, as are the two that
followed it.
[`lib/gate_delegate.ps1`](../lw-watchtower/lib/gate_delegate.ps1), registered as a `PreToolUse` hook with matcher
`Edit|Write|NotebookEdit|Bash|PowerShell`. Built on 30 July 2026, hours after the other two gates were removed,
because it is the one gate on this project's plan that could be built **completely** rather than
partially — there is no half of it that a hook cannot reach.

One rule, no exceptions:

> When `interaction.delegate` is on, refuse those five tools for any call that did **not** come from
> a subagent.

**Switch.** `interaction.delegate`, written by `/lw-watchtower:delegate`, with a per-repo override under
`repos[slug].interaction.delegate`. It is **not** a `modules` key: the registry entry declares
`switch = @{ block = 'interaction'; key = 'delegate'; default = $false }`, so the gate has exactly
one switch. A second flag in `modules` would let `/lw-watchtower:delegate on` succeed while the gate stayed
silent — a switch wired to nothing. `bin/lwg-doctor.ps1`'s `config-registry` check asserts the
declared key exists and fails if both spellings are present. Because the flag sits outside `modules`
it does not inherit `Get-LwgConfig`'s fail-**open** polarity: an unreadable `config.json` leaves the
gate **off**.

**How it identifies a subagent: the presence of `agent_id`, and nothing else.** The base hook input
carries `agent_id?` and `agent_type?`, and only `agent_id` is populated when a hook fires inside a
subagent. **It must never test `agent_type`**, and this is the single most important line in this
section: a `settings.json` `agent` key names the role the *main conversation* runs as, so on such a
machine the main thread carries a non-empty `agent_type`. A gate matching on that would classify the
main thread as a subagent and allow every call it exists to refuse, while reporting itself as a live
gate — the founding defect this plugin exists to catch, one field name away.

**How it blocks: stderr plus exit 2, and the deny envelope on stdout as well.** Only exit 2 blocks a
`PreToolUse` call; **exit 1 is a non-blocking error and the tool runs anyway**, so a gate that exits
1 has silently failed open. An exit code cannot be malformed, which is why it carries the weight. The
`permissionDecision: "deny"` envelope is emitted too — on this build a nonzero exit makes stdout be
ignored, so it is redundant here, and it is emitted because the two channels fail open in different
circumstances and emitting both can never turn a deny into an allow. A `PreToolUse` deny is honoured
**even under `permissions.defaultMode: "bypassPermissions"`**.

**It makes no safety determination of any kind.** No allowlist, no exemption, no path or command
inspection, and **nothing it decides consults `tool_name`**. The matcher in
[`hooks/hooks.json`](../lw-watchtower/hooks/hooks.json) is the single place the gated tool list lives, because a
second copy here would be a second thing to keep correct, and because widening the matcher then
refuses *more*, which is the safe direction, while a stale list inside the script would refuse
*less*, silently.

**"Widening is the safe direction" has an end, and it is `Agent`.** That sentence was written about a
list of mutating tools and it is true of them; it is not true without limit. Because the script is
tool-blind, whatever the matcher selects on the main thread gets refused — so a matcher that also
selected `Agent` would refuse the **dispatch this gate's own deny text tells the operator to make**,
and `/lw-watchtower:delegate off` runs through `Bash` and is refused on purpose. That is not an
over-block; it is a session with no way out. So the matcher stays an enumeration of tools that can
*do the work* being pushed onto subagents, and
[`tests/gate_delegate.ps1`](../tests/gate_delegate.ps1) section M asserts both edges: `PowerShell`
must be selected, `Agent` and `Read` must not.

**`PowerShell` was missing from that enumeration until 1 August 2026**, on a plugin that supports
Windows and nothing else, where the CLI offers both shell tools. An armed gate could be walked round
by asking for the other shell while `/lw-watchtower:doctor` reported it live. What an enumeration still
cannot cover — `mcp__*` tools whose names are not knowable from this repository, and any tool the CLI
adds later — is in [Limitations](limitations.md#the-three-gates-block-little-and-all-ship-off) rather
than papered over here.

It does read `payload.tool_name` — once, *after* the decision to refuse has been made, to name the
refused tool in the message the operator sees. That is stated rather than glossed because the flat
claim "it does not read `tool_name`" is not true of the code, and a page arguing that this project
never overstates itself cannot afford a convenient absolute. Nothing follows from that read except
the wording of the denial; a payload with no `tool_name` is refused exactly the same way, with the
text falling back to *"this tool"*.

**What "failing safe" means here is two different directions, on purpose.**

| Situation | What it does | Why |
| --- | --- | --- |
| stdin empty, truncated or not JSON | **DENY** (when the switch is on) | there is then no `agent_id`, and input it could not read is not evidence a subagent made the call. Treating unreadable input as "probably a worker" is how a gate is talked out of firing |
| `config.json` unreadable or absent, or the script throws anywhere | **ALLOW** | the switch is off by default and an unreadable config is no evidence the operator turned it on. It is also what keeps a bad config a nuisance rather than a lockout: the file that has to be fixed is one this gate would otherwise refuse to let the main thread edit |

**The over-blocking it accepts, stated rather than left to be discovered.** With the gate on,
`/lw-watchtower:delegate off` **does not work from the main thread** — that command runs through `Bash`.
There is deliberately no exemption for it. Have a subagent run it, or set `interaction.delegate` to
`false` by hand in `config.override.json` under the state directory — `$CLAUDE_PLUGIN_DATA`, or
`~/.claude/plugins/data/lw-watchtower*/`. **Not in `config.json`**: that file is the shipped
defaults, and an edit there changes nothing while the override still says `true`. If no override
file exists, the gate is off already and there is nothing to turn off. The deny text says both.

**And read-only calls are refused too, which is the part that costs.** The matcher selects `Bash`
and `PowerShell` as tool names; the script never looks at what the command was going to do. So with
the switch armed, `git status`, `git diff`, `grep` and a test run are refused from the main thread
exactly as `rm -rf` is. **Verifying anything therefore costs a dispatch**: the main thread cannot
read the tree it is talking about, and every check has to be handed to a subagent and reported back.
That is the intended shape — the session is reserved for talking to the operator — and it is stated
here because an operator who arms the gate expecting mutations to be gated meets it on the first
`git status` (#159).

**What it is not.** It is not a security control: a subagent can do everything it refuses, by
design, so a way past it is not a vulnerability. It never checks that a dispatch was any *good*.
Delegation is enforced; delegating well is not.

**Cost, measured rather than assumed.** It runs before every `Edit`, `Write`, `NotebookEdit`,
`Bash` and `PowerShell` call, **switched on or off**, because a hook registration cannot be made conditional. Both
versions below were timed **in the same run**, interleaved round by round against the same floor,
with the old gate checked out of git into its own throwaway plugin root — comparing across two runs
would have credited the fast path with whatever else the machine was doing. Wall clock on one
development machine, `cmd` piping a payload into a fresh interpreter, 9 runs per row after a
discarded warm-up — read these as *one machine's medians*, not as constants:

| | median | min–max | above the floor |
| --- | --- | --- | --- |
| floor: `powershell -File` that drains stdin and exits 0 | **294 ms** | 278–304 | — |
| switch off (shipped), main thread — *before* | 652 ms | 608–719 | 358 ms |
| switch off (shipped), main thread — **after** | **436 ms** | 423–510 | **142 ms** |
| switch off (shipped), subagent — *before* | 630 ms | 603–717 | 336 ms |
| switch off (shipped), subagent — **after** | **426 ms** | 411–512 | **132 ms** |
| switch **on**, main thread (the deny) — *before* | 743 ms | 700–891 | 449 ms |
| switch **on**, main thread (the deny) — **after** | **868 ms** | 785–1064 | **574 ms** |

So the operator who never arms the gate — every operator, by default — pays about **216 ms less**
per gated tool call, and the gate's own work above a floor it does not control went from ~358 ms to
~142 ms.

**Re-measured on 31 July 2026** when the fast path's member-name matching was fixed — it was
comparing names case-sensitively against still-escaped text and reading "I did not find it" as "it is
not there", which allowed calls the gate was armed to refuse. The fix adds a case-insensitive
compare, an abstain-on-any-escape rule and one extra `IndexOf` over the `repos` block, and it is
free at this resolution: same method, 9 interleaved rounds after a discarded warm-up, old and new
timed against each other in the same run. **Switch off, main thread: 436 ms before → 439 ms after**
(mins 414 → 404) against a 299 ms floor. **Switch on, the deny: 856 ms → 838 ms.** Both deltas are
inside the run-to-run spread of the rows above, so the figures in the table stand and the saving is
unchanged. The shipped `config.json` still takes the fast exit — no member name in it carries an
escape, and its `repos` block contains neither the word `interaction` nor a `\u`.

**The deny path got slower**, and that is in the table rather than left out of it. With the switch on
the fast path runs, fails to prove the switch off, and the slow path then does everything it always
did, so an armed gate pays the fast path's ~90–125 ms on top. That is the right way round: the cost
falls on the operator who turned the gate on, on a call that is being blocked anyway, and it buys the
default case a saving four times its size. If even the remaining cost is too much for you, the module
is a hook registration in [`hooks/hooks.json`](../lw-watchtower/hooks/hooks.json) and removing that entry removes
it entirely, along with the ability to ever turn the gate on.

**How the saving was made.** The slow path still uses the shared readers — `common.ps1`,
`Read-LwgStdin`, `Get-LwgConfig` — rather than the hand-rolled JSON scanning `lib/subagent_start.ps1`
uses to stay near its floor, and that trade is unchanged: the scanner in there is a narrow duplicate
of two functions, and a duplicate on a **blocking** path can only fail by refusing too *little*. What
changed is that the cost is no longer paid *before the switch is read*. A fast path above the
`common.ps1` load proves `interaction.delegate` off from the raw text of `config.json` and exits 0 on
that proof alone. Its only affirmative conclusion is "provably off"; on any doubt at all it decides
nothing and falls through to the unchanged slow path. It cannot deny, and it never looks at the
caller — so no exemption can be smuggled into it. The scan is depth-tracked and string-aware for two
specific reasons written up in the file: `config.json`'s comments contain the literal text
`\"delegate\": true`, and a decoy `interaction` block one level down would otherwise read as the
setting.

**Tested.** [`tests/gate_delegate.ps1`](../tests/gate_delegate.ps1) — 93 cases through a real pipe
into a real child process, run by CI on every push and PR. Read the header before treating a green
run as assurance: the last gate's suite was 67/67 green while five bypasses were open, and the
seven fast-path cases in section I carry a limit of their own that the header spells out. It was 62
until 31 July 2026, when the ten cases of section J were added for the member-name fail-open and the
non-boolean switch value, one section-I case moved into it, and the per-repo cases stopped skipping
themselves — that skip is why a run of the 62-case version could truthfully report `60 of 60`. It
was 71 until 1 August 2026, when the eight cases of section K were added: they put the gate and the
command that reports it in front of the same config and require the same answer, after a
boolean-only rule reached the gate's reader and not the command's.

## `send_liveness_gate`

**Refuses a `SendMessage` whose recipient it can *prove* is dead. Off by default.**
[`lib/gate_send.ps1`](../lw-watchtower/lib/gate_send.ps1), registered as a `PreToolUse` hook with
matcher `SendMessage`. Built on 1 August 2026 from a measured failure rather than from a plan.

**The failure it exists for.** An orchestrator issued `SendMessage` to a subagent, received
*"Message queued for delivery"*, and 3.46 seconds later told the operator the work was done. The
recipient had been dead for **28 minutes 45 seconds**: its transcript existed, its last write was
half an hour old, and `health.jsonl` held no `SubagentStop` record for it, because a subagent killed
mid-flight produces no record anywhere. The message could never have been delivered, the file was
never touched, and nothing refused or even flagged the send.

**Switch.** `supervision.send_liveness`, declared on the registry entry's own `switch` field rather
than as a `modules` flag — the same reasoning as [`delegate_gate`](#delegate_gate): `Get-LwgConfig`
fails **open**, and a corrupt config must not arm a blocking gate.

**The rule, and it is built only on what is observable.** A `SendMessage` payload carries
`tool_input.to` and the session's `transcript_path`; on disk each spawned agent leaves
`agent-<id>.jsonl` and `agent-<id>.meta.json` under this session's `subagents` directory; and
`health.jsonl` records every agent that stopped **normally**. Three states follow:

| What the evidence says | Verdict |
| --- | --- |
| a `SubagentStop` record exists | completed normally; a send **resumes** it — **allow** |
| no record, transcript written recently | presumed running — **allow** |
| no record, transcript silent past `stale_minutes` | **dead mid-flight** — **deny** |

`module_config.send_liveness_gate.stale_minutes` defaults to **15**, deliberately above the
ten-minute `Bash` tool ceiling: an agent inside one long tool call writes nothing for the length of
that call, and a threshold under the ceiling would deny sends to agents that are merely busy.

**A verdict needs the recorder to have been in the room.** *"No `SubagentStop` record"* means
nothing if nothing was writing them, so a deny additionally requires that `health.jsonl` holds at
least one record **of any kind** for this session. A session `failure_capture` never saw gets an
**abstain** — allowed, and logged as `SendGateAbstain`. A gate must not convict on the silence of a
witness that was never present.

**Resolving the recipient**, and the two refusals that are not liveness verdicts:

- **`main`** — the session itself; always allowed.
- **an address containing `@`** — an agent-team address. Team layouts are not observable from a
  hook, so this **abstains** and logs.
- **a name** — matched case-insensitively against the `name` field of every `agent-*.meta.json` in
  this session's subagents directory. Several matches and the newest wins, which is the platform's
  own *latest wins* rule for a reused name.
- **a raw agent id** — tried *after* the name lookup, so a name that happens to look like an id
  still resolves as a name.
- **anything that resolves to nothing** — no meta carries the name, no transcript carries the id, or
  the session has no subagents directory at all — is **denied**. No such agent exists in this
  session, so no such agent is live.

**How it blocks** is `delegate_gate`'s two channels for the same reasons: the reason on stderr with
**exit 2**, which is the only code that stops a `PreToolUse` call, plus the
`permissionDecision: "deny"` envelope on stdout, redundant on this build and emitted because the two
channels fail open in different circumstances.

**Failing safe, per path.** Stdin that is empty, truncated, not JSON, or carries no `to` is a
**deny** while the switch is on — the gate's one job is to establish the recipient before the send,
and input it could not read is not evidence of a live recipient. A config it cannot read, or any
throw, is an **allow**: a gate that cannot read its own switch must not act on a guess, and the
switch defaults off.

**The over-blocking it accepts, stated rather than left to be discovered:**

- An agent that is alive but silent past `stale_minutes` — back-to-back long tool calls — is denied.
  The deny text names exactly what was measured and names the knob.
- A completed agent whose `SubagentStop` record has scrolled out of the health-log tail this gate
  reads is denied as if dead. That takes over a thousand later records in one session, and the deny
  text names the record it looked for.
- **An operator running agent teams should not arm this gate.** A `name@team` recipient abstains, and
  an unresolvable bare name is denied.

**And the bypasses**, per [Gates were removed deliberately](gates-removed.md) Lesson 3, so nobody
reads a green suite as soundness: a recipient that died **less** than `stale_minutes` ago passes as
presumed running — the gate narrows the window, it does not close it; a dead agent whose name a later
live agent took over resolves to the live one, exactly as the platform itself would route it; and
**nothing here establishes delivery or completion** — an allowed send can still sit queued forever if
the recipient dies afterwards. That half belongs to [`completion_audit`](#completion_audit).

**No fast path**, deliberately, unlike `delegate_gate`. That gate sits on every `Edit`, `Write` and
`Bash` call a session makes; this one fires only on `SendMessage`, which happens at orchestration
frequency, so the interpreter floor is the cost and a raw-text scanner would buy back milliseconds
nobody is paying.

---

## `completion_audit`

**Refuses a turn end that claims completed work on the strength of a queued message. Off by
default.** [`lib/gate_stop.ps1`](../lw-watchtower/lib/gate_stop.ps1), registered **twice** — once on
`Stop` and once on `SubagentStop` — and on both **without `asyncRewake`**, which is what makes its
exit 2 *block the turn end* and feed stderr back to the model rather than raise an alert. That is the
exact opposite of the supervisor's registrations on the same events.

It is a separate script rather than a sixth module inside
[`lib/stop_advisories.ps1`](../lw-watchtower/lib/stop_advisories.ps1) because that file's header
promises *"these are advisories, they must never block"* and exits 0 on every path; a blocking module
inside it would falsify its own header. `Stop` hooks run concurrently, so the extra process costs
roughly nothing at turn end.

**Switch.** `supervision.completion_audit`, on the registry entry's `switch` field, for the same
fail-open reason as the other two gates.

**The failure it exists for** is the prose half of `send_liveness_gate`'s. The orchestrator issued
`SendMessage` at 13:20:12.391Z and told the operator *"Added to the handoff."* at 13:20:15.851Z —
**3.46 seconds later, with no tool call in between**. The assertion rested on a *"Message queued for
delivery"* acknowledgement and on nothing else.

**The rule, exactly.** Reading the current turn — every record after the last typed user prompt — the
turn end is refused when **all four** hold:

1. the turn contains at least one `tool_use`, and the **last** one in it is `SendMessage`, so nothing
   after the send could have established anything;
2. assistant text **follows** that `SendMessage`;
3. the final assistant text matches the completion-claim vocabulary — past-tense completion verbs,
   *added*, *updated*, *fixed*, *done*, *committed*;
4. and it does **not** match the hedging vocabulary — *will*, *once*, *queued*, *dispatched*,
   *asked*, *awaiting*, *in progress*. A reply that says the work was **handed off** is the honest
   sentence this gate exists to demand, and must never be refused.

The refusal text names the evidence that would make the same claim honest: read the artifact the
claim is about, or wait for the recipient's completion notification, then assert.

**It fires at most once per turn end.** On the continuation the payload carries `stop_hook_active`
and this script stands down, as every `Stop` hook here does, or a model that repeated the claim would
loop forever. Stated plainly: **this gate can force one round of verification; it cannot force
honesty.** A model that re-asserts the same claim without verifying ends the turn.

**Why it is registered twice, and why registering the same file twice would have been worse than the
gap.** Subagents and teammates emit `SubagentStop` and never `Stop`, so under `Stop` alone this gate
fired for no worker at all. Two measured facts make the two registrations non-interchangeable:

- **On `SubagentStop`, `transcript_path` is the *parent's* transcript**; the subagent's own is
  `agent_transcript_path`. A gate reading the former there would audit the **orchestrator's** turn
  whenever any subagent stopped — and in a delegate pattern a parent whose last tool was
  `SendMessage` beside a completion claim is the common case, so it would have blocked a worker for
  what the parent said.
- **Every record in a real subagent transcript is `isSidechain: true`.** The sidechain skip is
  unconditional in `Stop` mode, so pointed at the subagent's transcript with that skip left in place
  the gate would have been a **silent no-op** — armed, auditing nothing.

So subagent mode changes three things and nothing else: which transcript is read (an absent
`agent_transcript_path` degrades to a silent no-op rather than falling back to the parent's), the
sidechain skip is lifted, and the turn boundary uses a local reader instead of the shared
`Get-LwgPromptText`. Mode is taken from **either** the `-HookEvent` argument or the payload's
`hook_event_name`, and that asymmetry is deliberate: subagent mode during a `Stop` reads an absent
path and exits 0, while `Stop` mode during a `SubagentStop` audits the parent and **falsely blocks**.

**What this is and is not — the honest half.** Detecting *"asserted completion"* in prose is a
**regex over language**, and that is the weakest kind of rule this plugin ships. It is shipped anyway
because the alternative is what allowed the measured failure, and because the trigger is guarded by
three **structural** conditions that are not prose: a tool call happened, it was `SendMessage`, and
it was last. Enumerated rather than glossed:

| It will stay silent when it should not | It can refuse an honest sentence |
| --- | --- |
| a claim phrased outside the verb list (*"the handoff now reflects it"*) | completion verbs describing **old**, already-verified work in a turn that happens to end with a `SendMessage` |
| a claim in a turn whose last tool call is anything but `SendMessage` — including a cosmetic `Read` after the send | quoted text: the model quoting a file that contains *"added"* |
| a hedge word anywhere in a message that also asserts completion — *"dispatched the fix and updated the doc"* is suppressed by *dispatched* | |
| the continuation after a block, by design | |
| a claim made in an earlier turn and merely not repeated | |

A refusal costs one continuation in which the model states its evidence or rephrases honestly, and
the block text says exactly that. An error **allows** — exit 0, logged `GateError` — because a broken
audit must never pin a session shut.

**Pinned to a CLI build.** `agent_transcript_path`, the blocking behaviour of exit 2 on
`SubagentStop`, and `stop_hook_active` on that payload are all observed facts about Claude Code
2.1.227, not documented contracts. **Re-check them after a CLI upgrade.**

## Session modes

The banner reports how many modules are **enabled** (implemented **and** switched on), whatever is
not, and the mode:

| Mode | Meaning |
| --- | --- |
| `enforcing` | Every implemented module on, at least one live gate, self-check passed. **Reachable, but not by one command**: four modules ship off, so `enforcing` needs `interaction.delegate` *and* the three `supervision` switches turned on together. |
| `partial` | Self-check passed, at least one live gate, but some implemented module is switched off. **This is what `/lw-watchtower:delegate on` alone gives**, because the other three stay off. |
| `observe-only` | No live gate — nothing can be blocked. **This is the shipped steady state**, because all three gates ship off, and it holds until someone arms one. |
| `inert` | No implemented module is enabled. Nothing at all is running. |
| `degraded` | The self-check **ran and failed**. Governance may not fire; do not rely on it. |
| `unverified` | The self-check **did not run**, because `self_health` is off. Nothing failed and nothing was checked. |

**Those top two rows became reachable again on 30 July 2026**, having been unreachable for a few
hours in between. They were kept through that gap rather than deleted, and the reason they came back
for free is that the ladder in `Get-LwgSessionMode` is guarded by the **live gate count** rather than
by any assumption about which gates exist. Do not delete a row here on the strength of today's
count.

`unverified` is a separate word on purpose. `enforcing`, `partial` and `observe-only` each assert,
in this table, that the self-check *passed*; claiming that on the strength of a check that never
ran is the same overstatement as counting an unbuilt module as coverage. `degraded` is the
opposite overstatement: it says a probe failed, and none did.

The banner as shipped, verified by running the hook rather than transcribed from intent:

```
LW-WATCHTOWER v0.4.0 · 7/11 modules enabled (4 off) · 0 gates · observe-only
```

Seven of eleven, and **the four that are off are `send_liveness_gate`, `completion_audit`,
`orphan_watch` and `delegate_gate`** — all four built, all four shipped switched off. The
parenthetical is the remainder being accounted for rather than a warning: everything not counted is
named, so the total always adds up. Setting `self_health: false` as well gives:

```
LW-WATCHTOWER v0.4.0 · 6/11 modules enabled (5 off) · 0 gates · unverified (self_health off - nothing was checked)
```

Run `/lw-watchtower:delegate on` and the same shipped config gives:

```
LW-WATCHTOWER v0.4.0 · 8/11 modules enabled (3 off) · 1 gate · partial
```

**`partial`, not `enforcing`, and that is the point of this example.** A live gate is what lifts the
session out of `observe-only`; `enforcing` additionally requires every implemented module to be on,
and three are not — `send_liveness_gate`, `completion_audit` and `orphan_watch` each need its own
switch in the `supervision` block. Turning all three on as well gives the only configuration in
which `enforcing` is honest, and it is also the only one with no remainder to account for:

```
LW-WATCHTOWER v0.4.0 · 11/11 modules enabled · 3 gates · enforcing
```

The count is **enabled**, not observed: it is the modules that are switched on in `config.json`
**and** backed by code. Nothing in this plugin records whether a registered hook ever fired, so no
line here can claim one did — see #132 and #166.

Whatever is not enabled is named in the model-visible context too — unbuilt, unbuildable, or
built-but-off — and the context says **"no gate is live"** rather than "no gate exists", because
three do. A coverage report with an unexplained gap in it fails as quietly as one that overstates
itself, and so does one that tells the model a capability it can be refused by is not there.

---

## Attempted and blocked: `ratelimit_escalation` and `cost_tracking`

**This is a record, not a plan. Do not re-attempt either module without reading it.**

Both names were carried as *planned* placeholders — declared in `config.json` and in
`$LwgModuleRegistry` with `blocked = $true` — until **30 July 2026**, when the owner removed the
placeholders. They are gone from `config.json`'s `modules` block, gone from the registry, and gone
from every count: the banner no longer says `planned` because there is nothing planned. What did
**not** go is the reason, which is this section.

Why the placeholders were carried in the first place, and why removing them is not a reversal:
carrying them made the banner say `planned` rather than silently reporting a full count of a total that
had quietly shrunk, and the alternative — shipping code that reads a field which is never present,
and counting it as coverage — is exactly the defect LW-WATCHTOWER exists to catch. That defect had
already shipped here once, in `Get-LwgRepo`, which read `payload.workspace.repo` from the same
absent block; see [How the repo slug is resolved](configuration.md#how-the-repo-slug-is-resolved).
Once the reasoning is written down somewhere durable, a permanent entry in a *switchboard* stops
buying anything and starts inviting someone to switch it on. So the entries went and the record
stayed.

**Neither can be built as specified. The blocker is not effort; it is that the data reaches no
hook.**

**Re-confirmed 31 July 2026** by an independent spike — same build, same conclusion, plus a
schema-level check (all 31 hook events, not just the ones exercised live) and two refinements
to the table below. The method and the full finding are in the maintainer note
`.github/notes/monitors-spike.md`, which is not published with these pages; that record also needs
repeating after a CLI upgrade, same as this one.

**The evidence.** In claude-code 2.1.220 the base hook input is:

```
{ session_id, transcript_path, cwd, prompt_id?, permission_mode?,
  agent_id?, agent_type?, effort? }
```

plus a handful of per-event fields (`source` on `SessionStart`; `stop_hook_active`,
`last_assistant_message`, `background_tasks`, `session_crons` on `Stop`; `agent_id`, `agent_type`,
`agent_transcript_path` on `SubagentStop`; `tool_name`, `tool_input`, `tool_response` on
`PostToolUse`). `rate_limits`, `context_window`, `cost` and `workspace` are assembled in exactly
**one** place in the whole binary — the status-line input builder, which starts from that same base
object and adds them. **No hook event carries any of them.**

| Field the module needs | Where it exists | Reachable from a hook? |
| --- | --- | --- |
| `rate_limits.five_hour` / `.seven_day` | status-line input only | **no** |
| `cost.total_cost_usd` | status-line input only | **no** |
| `cost.total_lines_added` / `.removed` | status-line input only | no for this field — but see below |
| `context_window.used_percentage` | status-line input only | no — but see [`context_pressure`](#context_pressure) |

**Exception found 31 July 2026, and why it does not change the verdict.** `PostToolUse` for the
`Agent` tool specifically carries `tool_response.toolStats` (`linesAdded`, `linesRemoved`,
`readCount`, `editFileCount`, and siblings) plus `tool_response.usage` and `totalTokens` — this
*is* reachable from a hook, unlike the status-line-only fields above it. It does not make
`cost_tracking` buildable: it is scoped to one subagent invocation at a time, to the `Agent` tool
only (no other tool's `PostToolUse` carries it), and it is dollar-free — line and token counts,
never `total_cost_usd` or a rate-limit figure. The full finding is under *Two refinements to the
existing record* in `.github/notes/monitors-spike.md`, which is not published with these pages.

The only process on the machine that receives rate-limit and cost data is the status line
([`statusline/statusline.ps1`](../lw-watchtower/statusline/statusline.ps1)) — and **it reads the
rate limits and drops the cost on the floor**. `$d.cost` is never read: the payload carries it on
every render and this file has never touched it, which its own header says at the `NOT WRITTEN:
cost` note. What it does with the rate limits it does read is print the `5h` and `7d` figures and,
on the **advisory row only**, an `approaching limit` / `land all work` line at
`thresholds.ratelimit.warn_pct` / `land_all_pct`. The *colour* of the figures comes from `Heat`,
whose three band edges are fixed at 50/75/90 and read no configuration at all — so lowering either
threshold changes the advisory and never the colour. This page said until 3 September 2026 that the
status line *"colours both"*; it was the last file in the tree still saying it (#78). That is where
any escalation would live, because that is where the data is. There is no on-disk cache to read instead:
the CLI holds rate limits in process memory, `~/.claude.json` has no rate-limit or cost keys, and
the transcript records token counts but no dollars and no line counts.

**What would unblock them.** A `rate_limits` / `cost` block added to the hook input by Anthropic,
or a Claude Code release that persists either to disk. Nothing short of that unblocks them, and no
amount of work inside this repository is that thing.

**If you are re-attempting one**, the order is: verify against the *current* CLI build that a hook
event now carries the field — the evidence above is pinned to 2.1.220 and is a claim about that
build, not a law — then add the module to `$LwgModuleRegistry` in
[`lib/common.ps1`](../lw-watchtower/lib/common.ps1) and to `config.json`'s `modules` block, keeping the two lists
identical. Do not add the flag first: a flag with no reachable data behind it is the founding defect
this plugin exists to catch, and it has now been shipped here twice.

---

## Advisories

Three modules warn without ever blocking — `context_pressure`, `docs_coupling` and `git_hygiene`.
They run in **one** process on `Stop`
([`lib/stop_advisories.ps1`](../lw-watchtower/lib/stop_advisories.ps1)), because each registered hook is a
separate PowerShell startup and `Stop` fires at every turn end — one hook per advisory would have
cost well over a second more per turn for nothing. It was five modules in one process until
2 September 2026; `verification_gate` and `mission_drift` were removed and the arrangement is the
same for the three that are left.

**They cannot block, by construction.** A `Stop` hook blocks the turn by exiting 2 without
`asyncRewake`, or by printing `{"decision":"block"}`. The advisory handler exits 0 on every path
and its only stdout is:

```json
{"systemMessage":"...","suppressOutput":true}
```

There is no `decision` field to omit by accident and no `asyncRewake` on the registration. The
envelope is built literally, and no path through the handler can add `decision`, `continue` or
`stopReason` to it. That is a property of the source, established by reading it — and since 31 July
2026 **case B8 of [`tests/stop_behaviour.ps1`](../tests/stop_behaviour.ps1) pins it**, asserting on
the envelope a real child process actually emitted that it carries no `decision` member. That is one
emitted envelope, not every path through the handler; reading the source is still what establishes
the general claim.

Each advisory fires **on a change, not on a state**, and records its dedupe position in
`advisory-<session>.json`. A condition that stays true does not repeat at every turn end; the
status line already renders the standing view in colour, and a warning that repeats forever is one
people learn to skip. **Two conditions are exempt**, and this sentence stated the general rule with
no exception until 3 August 2026, when they were made to repeat: `git_hygiene`'s `query-failed` and
`gh-unavailable` fire at **every** turn end while they hold, because they describe the observation
rather than the tree, and silence from that module is documented to mean *git said nothing is
wrong*. See [`git_hygiene`](#git_hygiene), which states the exemption where it applies, and
[faq.md](faq.md), which carries the same carve-out.

### `context_pressure`

No hook is given `context_window`. Occupancy is recomputed from the transcript's last main-thread
assistant record using the CLI's own arithmetic —
`round((input_tokens + cache_creation_input_tokens + cache_read_input_tokens) / window * 100)` —
which is real data, not a proxy. Subagent (`isSidechain`) records are skipped, so a worker's
occupancy is never reported as the session's.

The one number that genuinely cannot be observed is the **window size**, which depends on account
entitlements. The CLI only ever picks 200 000 or 1 000 000, and this module resolves between them
in descending order of trust, recording which source it used in every log record:

| `window_source` | Basis |
| --- | --- |
| `config` | an explicit entry in `module_config.context_pressure.window_tokens` |
| `1m-tag` | the model id carries `[1m]`, which the CLI itself reads as one million |
| `observed` | this model has been seen holding more than 200 000 tokens in a real turn — proof, not a guess, and self-correcting after one turn |
| `default` | none of the above; 200 000 is **assumed**, and the advisory says `window assumed` |

If occupancy ever exceeds the resolved window the figure is arithmetically impossible, so the
denominator is wrong. The module then **suppresses the percentage entirely** and logs
`ContextWindowUnknown` telling you which model to add to the config. It does not report a false
`100% CRITICAL`. Fabricating a governance number is worse than declining to produce one.

**Residual risk, stated plainly:** for an unrecognised model whose real window is 1 M, occupancy
between 150 k and 200 k will read as `75–100%` until a single turn crosses 200 k and the
`observed` rule corrects it permanently. Add the model to `window_tokens` to avoid the window
entirely. `window_tokens` **ships empty**, so this chain runs for every model until you put
something in it — an explicit entry wins outright and suppresses the three rules below it, which is
right for an operator stating a fact about their own account and wrong for a value shipped to
everyone. See [Configuration](configuration.md#context_pressure).


### `docs_coupling`

[`lib/post_edit.ps1`](../lw-watchtower/lib/post_edit.ps1) records each edited path on `PostToolUse`
(`Write|Edit|NotebookEdit`); the `Stop` half warns when source files changed this session and no
documentation did.

A path is **doc**, **source**, or **neither**, and *neither* is the load-bearing bucket: JSON,
YAML, TOML and lockfiles are deliberately excluded, because counting lockfile churn as a source
change is how this module would become noise nobody reads. Doc wins over source, so a file with a
code extension under `docs/` is documentation. Directories match on a whole path **segment**, so
`docs` does not match `src/docsify`. All four lists are configurable under
`module_config.docs_coupling`.

It only sees edits made **through the tools**. A file rewritten by a shell command never reaches a
`PostToolUse` hook and is invisible to it.

**The edit list, and the two bounds on it.** This module reads one per-session file,
`edits-<sessionkey>.txt` in the state directory, written by the `PostToolUse` hook. It was shared
with `mission_drift` until that module was removed on 2 September 2026, and the bounds below were
written when both read it. Two bounds apply and both cost something:

- **The list is capped at 256 KB and rolls.** Past that size the oldest entries are moved to
  `edits-<sessionkey>.txt.1` and the live file carries the most recent 2 000 forward, so a file
  edited only before the roll stops being counted. Roughly 3 500 recorded edits reach it — every
  `Write`, `Edit` and `NotebookEdit`, repeats included, since deduplication happens on the read side.
  Until 3 August 2026 this was **not** a roll: the hook stopped recording entirely at the cap, so
  every file edited after it was invisible to both modules while both went on being reported active.
  Nothing prunes the `.1` archives.
- **A recorded path is capped at 1 024 characters.** A longer one is truncated, which removes the
  extension, so it classifies as *neither* and neither module counts it. `MAX_PATH` is 260, so this
  bites only on a value that was not a real path — which is the case it exists for: one
  payload-supplied `tool_input.file_path` of 200 000 characters used to land whole, occupy most of
  the window the `Stop` half reads, and reach the operator's advisory intact, because
  `Split-Path -Leaf` returns the entire string when there is no separator in it.

### `git_hygiene`

The only module here that asks git anything, and therefore the only one that spawns a subprocess.
It warns at turn end about:

| Condition | Warns when |
| --- | --- |
| `dirty` | the working tree has uncommitted changes (tracked and untracked counted separately) |
| `detached` | `HEAD` is detached — commits made there belong to no branch |
| `unpushed` | there are local commits the remote does not have |
| `default-branch` | those commits are directly on the default branch, with no PR between them and everyone else |
| `pr-stale` | an open PR exists for the branch and its head is behind your local branch |
| `query-failed` | **git did not answer.** See below — this is the important one. |
| `gh-unavailable` | the open-PR check did not run |

**A failed query is not a clean tree.** If `git` is missing, times out, or exits nonzero, this
module says the tree state is **UNKNOWN** and says so out loud:

```
LW-WATCHTOWER git: working tree state is UNKNOWN - git status exited 128.
Do not read this as a clean tree; check it yourself before reporting the work as landed.
```

Silence from this module means *git said there is nothing wrong*. It never means *git was not
asked*. Conflating the two is how a watchdog reports a green tree it never looked at, and it is a
defect that has already been fixed three times over in a private sibling project's watchdogs — see
the [note on names](architecture.md).

**That claim was false between turn ends until 3 August 2026.** `query-failed` and `gh-unavailable`
went into the same dedupe signature as the tree conditions, so a git that never answered produced an
identical signature at every turn end and was announced exactly **once** — on the first. From turn
two onward, a session where git was missing from the hook process's `PATH`, hanging, or exiting
nonzero was indistinguishable to the operator from a clean tree, which is the reading the paragraph
above says silence has. The two kinds of condition are now separated: the signature is built from
the **tree** conditions only, and an unavailability note is emitted at **every** turn end for as long
as it holds. The cost is one extra sentence per turn end on a machine where git cannot be reached,
and it stops the moment the query starts answering.

**Cost control**, in the order it applies:

- Outside a git repo it does nothing, and the check for that is a `Test-Path` walk, not a
  subprocess.
- The common case is **one** `git status --porcelain=v2 --branch`, which answers dirty, detached,
  ahead and behind together rather than costing four processes.
- A second `git rev-list --count HEAD --not --remotes` runs only on a branch with **no upstream**,
  and only when the repo has a remote at all — without one, `--not --remotes` would count every
  commit ever made. **It is not overlapped, not cached, and runs at every turn end** for the life of
  such a branch, which is where a branch spends most of its life. Measured, it costs about as much
  as the `git status` above, and unlike that one none of it is covered by other work — so on an
  upstream-less branch the module's critical-path cost is roughly double the published figure. See
  [Turn-end cost](architecture.md#git_hygiene-and-the-gh-call), where the measurement and the reason
  a commit-oid cache was rejected are recorded.
- The default branch is read out of `refs/remotes/origin/HEAD` as a **file**. When that ref is
  absent — normal in a repo that was created rather than cloned — the name falls back to
  `module_config.git_hygiene.default_branches`.
- The `gh` call is the one thing that touches the network. It runs only where its answer can matter
  (unpushed work, non-default branch, not detached), at most **once per branch head per session**,
  and its answer is cached rather than merely the fact that it was asked. Set `use_gh: false` to
  remove it entirely.
- Every child gets a hard timeout (`timeout_ms`, `gh_timeout_ms`) and **the child and the helpers it
  spawned** are killed on expiry, via `taskkill /T /F`. Turn end is still never blocked: the hook
  returns immediately after the kill. The residual window is a pid reissued in the microseconds
  after the `HasExited` check, which the old `Kill()` fallback always carried too. Between 3 August
  and 3 September 2026 only the child itself was killed — Windows PowerShell 5.1 runs on
  .NET Framework 4.x, which has no kill-the-process-tree overload — so a `git` or `gh` that had
  invoked a credential helper left that helper running.
  Output is drained asynchronously, so a child that fills a pipe buffer cannot deadlock the hook,
  and stdin is closed so a credential helper that decides to prompt gets EOF instead of stalling
  turn end.

It warns on a **change of condition set**, never on the counts, so editing one more file does not
re-fire the same warning at the next turn end. Once the tree goes clean the stored signature is
cleared, so the same condition warns again if it comes back. **`query-failed` and `gh-unavailable`
are exempt** and repeat at every turn end while they hold — they describe the observation, not the
tree, and an observation that did not happen is worth saying every time it does not happen.

---

## `self_health`

The `SessionStart` self-check ([`lib/session_start.ps1`](../lw-watchtower/lib/session_start.ps1)). Five probes,
each asserting that a real value comes back rather than that a file exists: `config.json` was
genuinely parsed and not silently replaced by the built-in fallbacks; every declared module
resolves to a real boolean; both threshold groups yield numbers; the payload carried a
`session_id` and a `cwd`; and the state dir **accepted a write**, which is the only proof the
log-backed modules can record anything.

It honours its own flag. It used to run unconditionally, which made `self_health` a switch wired
to nothing — the exact defect this plugin exists to catch, sitting inside the module whose whole
job is to catch it.

**With the flag off, no probe runs and the session says so.** The mode becomes `unverified`, the
banner appends `(self_health off - nothing was checked)`, and the model-visible context ends:

> Self-check did NOT run (self_health is off), so none of the above was verified this session —
> it is what config.json and the module registry DECLARE, not what has been proven to work.

The log record carries `selfcheck.ran: false` and leaves `selfcheck.ok` **null**, not false. An
absent result must not be readable as either a pass or a failure, and a downstream reader that
treats a missing `ok` as `true` is the same class of bug as a banner counting flags as coverage.

---

## `context_injection`

**The problem.** Claude Code snapshots `CLAUDE.md` into a subagent's context when the **parent
session starts**, not when the subagent is dispatched. An instruction added mid-session therefore
never reaches a worker dispatched later in that same session. This is not theoretical: a security
classifier here refused a legitimate edit because its snapshot of `CLAUDE.md` predated the
instruction that authorised it.

**The fix.** `SubagentStart` fires once per dispatch, so anything it emits is current by
construction. [`lib/subagent_start.ps1`](../lw-watchtower/lib/subagent_start.ps1) reads
[`context/worker_facts.md`](../lw-watchtower/context/worker_facts.md) — live, every single time — and hands it to
the worker:

```json
{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"..."},
 "suppressOutput":true}
```

**The schema was verified against the 2.1.220 binary, not assumed**, because shipping a hook that
cannot fire is the defect this plugin exists to catch:

| Checked | Found |
| --- | --- |
| the event exists | `SubagentStart` is in the CLI's hook event list and has its own `executeSubagentStartHooks` entry point |
| what a hook receives | `{ …base…, hook_event_name:"SubagentStart", agent_id, agent_type }`; the matcher matches on **agent type** |
| what a hook may return | `v.object({ hookEventName: v.literal("SubagentStart"), additionalContext: v.string().optional() })` — `additionalContext` is the one field that carries injected text |
| that the subagent actually sees it | the CLI collects every hook's `additionalContext` and pushes it into the **subagent's** message list as `{type:"hook_additional_context", hookName:"SubagentStart"}` before its first turn — the identical path `SessionStart` uses |
| whether it can block | **no.** Exit 2 renders stderr as a hook-error notice in the subagent's transcript and the dispatch proceeds regardless |

**What goes in the file, and what does not.** Only facts that *go stale* and that workers
repeatedly get wrong. Anything durable belongs in `CLAUDE.md`, which is snapshotted once and costs
nothing per dispatch. The file is documented as **under 80 words** because every dispatch pays for
the text and a worker handed a wall of standing rules reads none of it. A line whose first
non-space character is `#` is a comment and is not injected; blank lines are dropped; everything
else goes verbatim. Edit the file and the next dispatch picks it up — no code change, no restart,
no reinstall. Past 2 000 characters the block is truncated at a line boundary with a note, so one
bad edit degrades the note rather than every dispatch.

**Correctness was not traded for speed.** The flag is read by scanning `config.json` textually,
which answers only the *global* default; if the `repos` block carries an override for this module
the script escalates to the real thing — dot-source `common.ps1`, parse the payload, resolve the
slug, ask `Test-LwgModule` — so an operator who configures an override pays the full cost and
nobody else does. Silently applying a per-repo override globally would have been exactly the quiet
wrongness this plugin exists to remove.

Likewise the fast `String.Replace` escaper is not the trusting one: a UTF-8 byte count that differs
from the character count proves a character above `U+007F` is present, `IndexOfAny` finds the
control characters the chain does not cover, and either one routes the string to an exact `\uXXXX`
escaper that emits every character outside printable ASCII as an escape — so the emitted envelope
is pure ASCII whatever the facts file holds and whatever the console code page is. **That, too, is
a property of the source rather than a tested one:** nothing in this repository exercises this
script.

**Failure policy.** Any error at all exits 0 and the dispatch proceeds. A missing, empty or
comment-only facts file emits nothing. Unreadable or corrupt `config.json` **fails open** and still
injects, matching `Get-LwgConfig`. Garbage or empty stdin is fine, because stdin is drained and
never parsed. Errors are logged on the error path only — logging every dispatch would cost a
`ConvertTo-Json` warm-up and a file append per worker, which is most of the budget.

Measured cost is in [Architecture § context_injection cost](architecture.md#context_injection-cost).

---

## `orphan_watch`

**Reconciles this session's subagent transcripts against its `SubagentStop` records and alerts on an
agent that died mid-flight. Off by default.** It runs inside
[`lib/supervisor.ps1`](../lw-watchtower/lib/supervisor.ps1) on `Stop` and on `SubagentStop`, and it
**observes** — it raises the supervisor's exit-2 `asyncRewake` alert, which reaches the orchestrator
mid-turn, and blocks nothing.

**Switch.** `supervision.orphan_watch`, on the registry entry's own `switch` field rather than as a
`modules` flag.

**The gap it closes.** `failure_capture`'s failed-task count reads
`$payload.background_tasks` and counts only entries the harness marked `failed` or `killed` — and
**a subagent killed mid-flight appears in that list not at all**. Measured on 1 August 2026: a
cross-check of 70 subagent transcripts against the health log found **four** transcripts with no
`SubagentStop` record — four agents that died while `failed_tasks` read `0` — in a log holding
**zero** `PostToolUseFailure` records across 1,175 entries. *Green* there has only ever meant *no
`Agent` tool call returned an error*.

**The rule.** An agent that was **spawned** — its transcript exists in this session's subagents
directory — that never **stopped** — no `SubagentStop` record for its id in `health.jsonl` — and has
gone **silent** — its transcript unwritten for `stale_minutes`, default 15, above the ten-minute
`Bash` ceiling so one long tool call is not silence — is an **orphan**.

**One death signal is stated rather than inferred, and it is believed with no threshold at all.**
The harness writes a task-notification into the parent transcript naming the agent and saying
`<status>failed</status>`, in milliseconds, for every death. Measured across all four deaths in one
session on 10 August 2026 — and two of them went unreported for **ninety minutes** because nothing
read that notification. An id found there is reported immediately; no silence rule applies to it,
because a status of `failed` is a terminal statement about a specific agent rather than an inference
that could be premature.

**There is deliberately no second, shorter threshold, and the reason is measured.** A five-minute
fast path keyed on an `isApiErrorMessage` transcript tail *was* shipped here, on the reasoning that
such a record states a cause rather than inferring one. An adversarial re-derivation over 1,050
transcripts falsified it: four gaps of 25.4 s, 93.8 s, 3,824 s and 4,011 s, **all four of which
recovered and carried on**. The longest carried no `529` and no *"Overloaded"*, so it fell straight
through the class exclusion onto the five-minute path — a live agent reported dead after five
minutes, which then worked for another sixty-two. A false-positive rate of **one in four**, on the
exact control that exists to stop an operator being told something is dead when it is not. Nor can
the threshold be raised out of the problem: the longest live recovery observed is **66.85 minutes**,
longer than the fifteen-minute silence rule it was meant to beat. **Do not reintroduce a threshold
keyed on transcript prose.**

**Where its verdict stops, in three places, and each of them is an abstain rather than a guess:**

- **It sits below the `failure_capture` flag check**, and that coupling is correct rather than
  convenient: `SubagentStop` records are what `failure_capture` writes, and reconciling transcripts
  against records nothing was writing would call every finished agent an orphan. **`failure_capture`
  off means `orphan_watch` inert**, whatever its own switch says, and the doctor's module roster
  counts it from the registry either way.
- **A session with no health records at all yields no orphans**, for the same reason: the recorder's
  silence proves nothing.
- **The evidence horizon.** The health-log reader takes a bounded tail, and rotation keeps only the
  last 500 lines, so a `SubagentStop` record can leave the window while the agent's transcript sits
  on disk forever. The verdict is *"no stop record exists"*, so a lost record does not weaken the
  conclusion — it **inverts** it, and a cleanly stopped agent becomes a permanent orphan. The module
  therefore judges only as far back as it can prove it looked: the session's `SessionStart` record is
  written once, before any agent can be dispatched, so its presence in the window proves the window
  reaches past every `SubagentStop` this session could have written. Without it, the earliest record
  visible is the furthest back the module may judge.

**Deduped, and the dedupe is what keeps the indicator honest.** An orphan is *standing*: the dead
transcript stays on disk for the rest of the session, so every later turn end re-detects it.
`alerted.json` holds the ids already alerted on, so the operator is told once; and the health record
carries the **standing** count as an evidence trail beside a separate count of what is **new**,
because the status line takes a peak of the recorded counts over the log tail it reads and a standing
orphan re-reported as new would push that indicator up forever with no way to bring it down.

---

## `failure_capture` and healing

See [Health and healing](architecture.md#health-and-healing).
