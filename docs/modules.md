# Modules

Ten module names exist. **All ten are built.** There is no name here with no code behind it.
**Nine ship enabled; one — `delegate_gate` — ships switched off**, and off is where it is meant to
be.

There were thirteen until 30 July 2026, and that day four went and one arrived, each by an explicit
owner decision. **Both of the old gates were removed** — `destructive_gate` first, `secret_scan`
second — leaving no gate and no `PreToolUse` hook of any kind; see
[Both gates were removed](#both-gates-were-removed) for the narrative and
[Gates were removed deliberately](gates-removed.md) for the rules a new one has to follow.
**Then the two unbuildable placeholders were removed** — `ratelimit_escalation` and `cost_tracking`
— and the reasoning kept, at
[Attempted and blocked](#attempted-and-blocked-ratelimit_escalation-and-cost_tracking). The same day
the owner switched `mission_drift` **on**, and **`delegate_gate` was built** as the one gate on this
project's plan that could be built completely rather than partially — see
[`delegate_gate`](#delegate_gate).

The authoritative split lives in `$LwgModuleRegistry` in [`lib/common.ps1`](../lib/common.ps1),
which is what the session banner counts. **The flags in [`config.json`](../config.json) are never
counted as coverage** — a `true` flag is a forward-declaration, not evidence that code exists.

| Module | Kind | Status | What it is for |
| --- | --- | --- | --- |
| `failure_capture` | observe | **implemented** | Record tool, hook and subagent failures so nothing fails silently. |
| `self_health` | observe | **implemented** | Prove the governance layer itself can still fire. |
| `log_rotation` | observe | **implemented** | Cap `health.jsonl` and `lw-watchtower.jsonl`. It does **not** bound the state dir: `advisory-<sessionkey>.json` and `edits-<sessionkey>.txt` are one file per session each and nothing sweeps them. |
| `context_pressure` | observe | **implemented** | Warn before the context window forces a lossy compaction. |
| `verification_gate` | observe | **implemented** | Warn when work was done and nothing independently checked it. |
| `docs_coupling` | observe | **implemented** | Flag source changes shipped without documentation. |
| `git_hygiene` | observe | **implemented** | Branch, commit and push discipline at turn end. |
| `mission_drift` | observe | **implemented** | Notice when a session has wandered off the task it was given. Shipped `false` until 30 July 2026 and now ships `true` — see [below](#mission_drift) for what that accepts. |
| `context_injection` | observe | **implemented** | Hand every subagent facts that are current at *dispatch* time, because `CLAUDE.md` is snapshotted at session start. |
| `delegate_gate` | **gate** | **implemented** | Refuse `Edit`/`Write`/`NotebookEdit`/`Bash`/`PowerShell` for calls that did not come from a subagent, so the chat session is reserved for talking to the operator. **The only module that can block anything, and it ships OFF** — see [below](#delegate_gate). |

## Caveats on the ten that only observe

Read these before treating any module as coverage. Every one of the nine below **observes**; not one
of them can stop anything. `delegate_gate` is the tenth and is the exception, with
[its own section](#delegate_gate).

- `self_health` (the `SessionStart` self-check) honours its flag. With it **off** no probe runs at
  all, and the session reports mode `unverified` rather than any word that would imply it was
  validated. See [`self_health`](#self_health).
- `log_rotation` runs on **its own flag alone**. The rotation call sits above the
  `failure_capture` flag check in [`lib/supervisor.ps1`](../lib/supervisor.ps1), so switching failure
  capture off stops the writes to `health.jsonl` but never the cap on its size.
- `context_pressure` does not read a context percentage — no hook is given one. It recomputes
  occupancy from the transcript, and the window *size* is inferred. See
  [`context_pressure`](#context_pressure).
- `verification_gate` sees **subagents only**. Work the main thread did itself is invisible to it.
- `docs_coupling` sees **`Write`/`Edit`/`NotebookEdit` only**. A file rewritten by a shell command
  is invisible to it.
- `git_hygiene` is the **only module that spawns a subprocess**, and it does so on `Stop` only.
  Nothing outside a repo, nothing with the flag off. See [Turn-end cost](architecture.md#turn-end-cost).
- `mission_drift` is **on by default since 30 July 2026**, sees `Write`/`Edit`/`NotebookEdit` edits
  only, and by design detects only work that landed outside the workspace root. It is the one module
  here whose trigger was **never validated against real sessions** before being switched on for
  everyone, and that is still true — what changed on 31 July 2026 is that
  [`tests/stop_behaviour.ps1`](../tests/stop_behaviour.ps1) exercises the module end to end, so the
  code is now known to do what it is documented to do. See [`mission_drift`](#mission_drift).
- `context_injection` runs once **per subagent dispatch** and is the only module on that event.
  It injects, it never blocks — `SubagentStart` has no blocking channel at all.

## Gates, and what counts as one

**Gates** are the modules that can block an action rather than merely report one. **One ships, and
it ships switched off** — so there are two numbers here and collapsing them is the mistake this
section exists to prevent:

| Number | Value as shipped | What it means |
| --- | --- | --- |
| gates **shipped** | **1** | `delegate_gate` is in `$LwgModuleRegistry` with `kind = 'gate'` and its hook is registered. The capability exists and you own it. |
| gates **live** | **0** | `Get-LwgActiveGates` counts only gates that are *switched on*. `interaction.delegate` is `false`, so nothing is blocking, `config.json` records `gates_live: 0`, and a healthy session reads `observe-only`. |

Reporting only the first would claim protection that is switched off. Reporting only the second would
hide a capability the operator has and was never told about, and nobody turns on a thing they do not
know they have. `/lw-watchtower:status` prints both, plus a `GATES` block naming each gate's switch.

`observe-only` therefore holds as shipped, and `enforcing` and `partial` are **reachable** by running
`/lw-watchtower:delegate on` — nothing else has to change. The ladder in `Get-LwgSessionMode`
([`lib/common.ps1`](../lib/common.ps1)) returns `observe-only` on a **live** gate count of zero
*before* it ever tests whether a module is switched off. That ordering is deliberate: "some module is
off" is a smaller fact than "nothing can be blocked", and the smaller fact must not be the one a
reader sees.

A session banner from before 30 July 2026 reads `2 gates`, and one from the middle of that day reads
`1 gate` or `0 gates`. Each is a record of what was true then, not a target to get back to by
recounting.

`verification_gate` **keeps the word "gate" in its name and is not one.** It always was kind
`observe`: it warns on `Stop` and never blocks, and it is not counted in the gate total. The name is
a leftover from its original specification and is kept only so that logs and configs written against
it keep working. Calling an advisory a gate would be the same class of overstatement as counting an
unbuilt module as coverage.

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
| a destructive shell command | `destructive_gate` hook + 133 deny rules | **nothing.** No hook is registered on `Bash` or `PowerShell`; the installer writes no rule |
| a write inside `.git/` | the write gate's path rule + the `git-internals` group | **nothing.** `[core] sshCommand` in `.git/config` is arbitrary code execution on the next git command, and no layer here refuses it |
| a write to a credential file | `secret_scan` path half + `secret-paths` | **nothing** |
| a write whose content is a credential | `secret_scan` content half | **nothing** |
| a credential read through a shell command | `secret-reads` | **nothing** |

- **`hooks/hooks.json`'s one `PreToolUse` registration is `delegate_gate`, and it reads none of the
  things this table is about.** The plugin registers on `SessionStart`, `PreToolUse`,
  `PostToolUse`, `PostToolUseFailure`, `SubagentStart`, `SubagentStop`, `Stop` and `StopFailure`.
  Exactly one registration has a blocking channel and it arrived later the same day — see
  [`delegate_gate`](#delegate_gate) — but it decides on the *caller*, never on the command, the
  path or the content, so every **nothing** in the rows above stands with it registered and armed.
- **The installer's deny table is empty.** `Get-DenyGroups` in
  [`bin/lwg-setup.ps1`](../bin/lwg-setup.ps1) returns an empty table, so `/lw-watchtower:setup` writes
  **zero** `permissions.deny` rules. `-SecretGate` and `-DestructiveGate` are still accepted and
  select nothing at either layer; setup says so where it asks. See
  [Install](install.md#the-installer-writes-no-permissionsdeny-rules).
- **A machine set up before 30 July 2026 still carries the old rules** in its own `settings.json`,
  and the CLI still evaluates them. Nothing here renews them, and setup never removes a rule already
  in your file. `bin/lwg-uninstall.ps1` keeps the full description of all 181 families, because it
  is now the only code that knows what they looked like well enough to attribute and remove them.

**What was kept, and why it is not protection.** These read the past; none of them can produce a new
record:

| Kept | What it does now |
| --- | --- |
| `lw-watchtower.jsonl` | the append-only event log. It still holds every historical `GateDeny`, and `/lw-watchtower:sitrep` counts them under `GOVERNANCE` as history. It is an audit trail, **not** a ledger — nothing can clear an entry in it |
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
and the indicator, in that order. What that costs, and what the four failed fix attempts on the last
gate actually taught, is written up in
[Gates were removed deliberately](gates-removed.md). Read it before writing a second `PreToolUse`
hook.

## `delegate_gate`

**The only gate this plugin ships. Off by default.**
[`lib/gate_delegate.ps1`](../lib/gate_delegate.ps1), registered as a `PreToolUse` hook with matcher
`Edit|Write|NotebookEdit|Bash|PowerShell`. Built on 30 July 2026, hours after the other two gates were removed,
because it is the one gate on this project's plan that can be built **completely** rather than
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
[`hooks/hooks.json`](../hooks/hooks.json) is the single place the gated tool list lives, because a
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
by asking for the other shell while `/lw-watchtower:status` reported it live. What an enumeration still
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
`false` in `config.json` by hand. The deny text says both.

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
is a hook registration in [`hooks/hooks.json`](../hooks/hooks.json) and removing that entry removes
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

## Session modes

The banner reports active (implemented **and** enabled), whatever is not active, and the mode:

| Mode | Meaning |
| --- | --- |
| `enforcing` | Every implemented module on, at least one live gate, self-check passed. **Reachable**: turn `delegate_gate` on and, with everything else enabled, this is what a healthy session reads. |
| `partial` | Self-check passed, at least one live gate, but some implemented module is switched off. **Reachable** the same way, with anything else switched off as well. |
| `observe-only` | No live gate — nothing can be blocked. **This is the shipped steady state**, because `delegate_gate` ships off, and it holds until someone runs `/lw-watchtower:delegate on`. |
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
LW-WATCHTOWER v0.4.0 · 9/10 modules active (1 off) · 0 gates · observe-only
```

Nine of ten, and **the one that is off is `delegate_gate`**. The parenthetical is the remainder being
accounted for rather than a warning: everything not active is named, so the total always adds up.
Setting `mission_drift: false` as well gives:

```
LW-WATCHTOWER v0.4.0 · 8/10 modules active (2 off) · 0 gates · observe-only
```

**The mode word does not change** in either case, and that is the point of these examples. How many
observing modules are on has never bought `enforcing`: that word is about a **live gate**, and with
`delegate_gate` off there is none. Run `/lw-watchtower:delegate on` and the same shipped config gives:

```
LW-WATCHTOWER v0.4.0 · 10/10 modules active · 1 gate · enforcing
```

Setting `self_health: false` gives, honestly:

```
LW-WATCHTOWER v0.4.0 · 8/10 modules active (2 off) · 0 gates · unverified (self_health off - nothing was checked)
```

Whatever is not active is named in the model-visible context too — unbuilt, unbuildable, or
built-but-off — and the context says **"no gate is live"** rather than "no gate exists", because one
does. A coverage report with an unexplained gap in it fails as quietly as one that overstates
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
to the table below. See [Monitors feasibility spike](monitors-spike.md) for the method and the
full finding; that record also needs repeating after a CLI upgrade, same as this one.

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
never `total_cost_usd` or a rate-limit figure. See
[Monitors feasibility spike](monitors-spike.md#two-refinements-to-the-existing-record) for the
full finding.

The only process on the machine that receives rate-limit and cost data is the status line
([`statusline/statusline.ps1`](../statusline/statusline.ps1)), and it already colours both and
prints a `land all work` advisory at `thresholds.ratelimit.land_all_pct`. That is where the
escalation lives, because that is where the data is. There is no on-disk cache to read instead:
the CLI holds rate limits in process memory, `~/.claude.json` has no rate-limit or cost keys, and
the transcript records token counts but no dollars and no line counts.

**What would unblock them.** A `rate_limits` / `cost` block added to the hook input by Anthropic,
or a Claude Code release that persists either to disk. Nothing short of that unblocks them, and no
amount of work inside this repository is that thing.

**If you are re-attempting one**, the order is: verify against the *current* CLI build that a hook
event now carries the field — the evidence above is pinned to 2.1.220 and is a claim about that
build, not a law — then add the module to `$LwgModuleRegistry` in
[`lib/common.ps1`](../lib/common.ps1) and to `config.json`'s `modules` block, keeping the two lists
identical. Do not add the flag first: a flag with no reachable data behind it is the founding defect
this plugin exists to catch, and it has now been shipped here twice.

---

## Advisories

Five modules warn without ever blocking. They run in **one** process on `Stop`
([`lib/stop_advisories.ps1`](../lib/stop_advisories.ps1)), because each registered hook is a
separate PowerShell startup and `Stop` fires at every turn end — five hooks would have cost well
over a second more per turn for nothing.

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

### `verification_gate`

Advisory, not a gate. On `Stop` it reads `health.jsonl` — written by `failure_capture`'s
`SubagentStop` handler, which records `agent_type` — and warns when the newest **work** agent
record for this session is newer than the newest **verify** agent record.

It is gated on evidence that work happened, not on the turn merely ending, which is what keeps a
session that only answered a question from being nagged.

Its blind spots are real and worth knowing:

- **False negatives** — work done by the main thread with no subagent is invisible; a
  `SubagentStop` whose `agent_type` is empty or absent is invisible, and deliberately so, because
  such a record is *no information* rather than *not a verifier* and must neither arm the gate nor
  disarm it; an agent on neither list is invisible.
- **False positives** — an implementer dispatched only to read or investigate; verification done
  by you, or by an orchestrator reading the diff itself, which leaves no record; a verifier run in
  a different session for the same work.

#### How a role is classified

**From the role's own `lw-class` frontmatter key — `work`, `verify` or `neutral`.** The observed
`agent_type` is resolved back to the `.md` file it names, the key is read out of that file, and the
value decides whether the record arms the gate, disarms it, or does neither. `neutral` is a real
answer and does neither: an explorer that read files and found nothing wrong has not verified
anything. See [Agent roles](roles.md#lw-class).

The name arrays in `config.json` are kept as a **fallback and only as one**. `lw-class` wins wherever
it is present; the arrays are consulted only for a role that declares no class — a role file written
before the key existed and never given one, or a generic name like `implementer` or `code-review`
that has no file at all and so can never declare it. See
[Configuration](configuration.md#verification_gate).

Name resolution walks the same precedence as the loader — project `.claude/agents/`, then
`~/.claude/agents/`, then this plugin's `agents/` — and a `<plugin>:` prefix puts the plugin scope
first, because a namespaced `agent_type` is evidence that a plugin's own copy is the one that ran.
Both spellings keep working: a plugin-shipped role arrives as `lw-watchtower:lw-explorer`, while the same
role copied into `~/.claude/agents/` arrives bare.

**When the name cannot be resolved, the answer is *no information* — never *not a verifier*.** Three
things produce that: a role belonging to some other plugin (no other plugin's install path is
derivable from a hook, so its roles are unreachable by construction), a file that was deleted,
renamed or never existed, and a file that resolves but declares no class and is in neither array.
All three fall through exactly the way an empty `agent_type` does — they neither arm the gate nor
disarm it. Degrading to *not a verifier* would let a missing file silence the one warning that
exists to notice unverified work.

**Cost on the Stop path**: about **67 ms** at the median, whole-hook, against the name-array version
it replaced — 25 interleaved runs each over a 400-record `health.jsonl` with five distinct agent
types, medians 1000 ms → 1067 ms. Isolated, the resolution itself measured 85 ms median over 21
fresh processes for five distinct names, of which almost all is one-time .NET and PowerShell
first-use rather than file I/O: the file lookup is memoised per name, and the loop caches one
verdict per distinct `agent_type` rather than calling the classifier per record. Read those as **one
machine's medians**, taken while other work was running on it, not as a property of the module. What
is invariant is the shape: the work is per *distinct role name* seen in a session — a handful — not
per record.

An earlier draft of the same code cost 119 ms because it used `-split`, `-match`, `Join-Path` and
`New-Object`; in a fresh PowerShell 5.1 process the first use of the regex engine costs ~20 ms and
the first `New-Object` ~75 ms. Replacing those four with `[IO.Path]::Combine`, `[IO.File]::ReadAllText`
and plain string indexing is where most of the difference went.

### `docs_coupling`

[`lib/post_edit.ps1`](../lib/post_edit.ps1) records each edited path on `PostToolUse`
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

**The shared edit list, and the two bounds on it.** Both this module and `mission_drift` read one
per-session file, `edits-<sessionkey>.txt` in the state directory, written by the same hook. Two
bounds apply to it and both cost something:

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
- Every child gets a hard timeout (`timeout_ms`, `gh_timeout_ms`) and **the child** is killed on
  expiry — **a helper it spawned is not**. Windows PowerShell 5.1 runs on .NET Framework 4.x, which
  has no kill-the-process-tree overload (that arrived in .NET Core 3.0), so a `git` or `gh` that had
  invoked a credential helper leaves that helper running. Turn end is still never blocked: the hook
  returns immediately after the kill. This page said plainly *"killed"* until 3 August 2026;
  `docs/architecture.md` and `config.json` still do.
  Output is drained asynchronously, so a child that fills a pipe buffer cannot deadlock the hook,
  and stdin is closed so a credential helper that decides to prompt gets EOF instead of stalling
  turn end.

It warns on a **change of condition set**, never on the counts, so editing one more file does not
re-fire the same warning at the next turn end. Once the tree goes clean the stored signature is
cleared, so the same condition warns again if it comes back. **`query-failed` and `gh-unavailable`
are exempt** and repeat at every turn end while they hold — they describe the observation, not the
tree, and an observation that did not happen is worth saying every time it does not happen.

### `mission_drift`

**On by default since 30 July 2026, by explicit owner decision.** It ships `true` in
[`config.json`](../config.json); there is nothing to install, because the mission is read out of the
transcript rather than captured by a hook of its own. Set `modules.mission_drift` to `false` to turn
it off again, and nothing else changes — the cost goes back to zero on the same flag.

**The tradeoff that decision accepts, stated plainly rather than left in the commit message.** This
module shipped `false` for a reason that has not been retired by turning it on:

- **Its trigger was never validated against real sessions.** That was the whole reason for the
  default, and no validation has happened since. A drift warning that fires on a legitimate change
  of direction gets switched off within a day and then protects nothing — the difference now is that
  it is switched off *after* an operator has been warned wrongly, rather than before.
- **Its behaviour was untested for its whole life**, and stopped being so on 31 July 2026:
  [`tests/stop_behaviour.ps1`](../tests/stop_behaviour.ps1) runs this module in a real child process
  across several turns, including the pivot path below. That closes the gap between what this page
  claims and what the code does. It does **not** close the one above it — a test says the trigger
  behaves as written, never that being warned by it is right. See [Testing](testing.md).
- **It costs about 137 ms at every turn end** where it previously cost nothing — one development
  machine's median, 122 ms fastest and 169 ms slowest, scaling with transcript growth and disk
  speed. See [Architecture](architecture.md#mission_drift-which-is-switched-on-by-default).
- **One false-positive class survives** and is now live for every install; it is described under
  *False positives it can still produce* below.

What is on the other side of the trade: the module is silent unless four conditions hold at once,
and it warns **at most once per session** — against a class of failure (a session quietly working on
something nobody asked for) that nothing else here can see at all. **If it warns wrongly, turn it
off** and say so, rather than learning to skip it.

That bound was wrong until 3 August 2026 and is worth stating precisely, because it is the number
this decision rests on. The page used to say *"once per distinct set of unaccounted files … so the
realistic worst case is one wrong warning per session"*. The first half described the code exactly;
the second did not follow from it. The signature was the **list** of unaccounted files, and that
list grows with the work, so every turn that touched one more unrelated file produced a new distinct
set and a new warning — four warnings in five turns on the ordinary shape of a session editing more
than three files outside the workspace root. The signature is now the **verdict** — *none of this
session's edits is accounted for* — which does not change when a fourth file joins it. The bound
holds for a fixed configuration and workspace root: editing `require_outside_root` mid-session, or a
`cwd` that moves the git root, are outside it and are not claimed.

It asks one question at turn end: *is the work still serving anything that was actually asked
for?*

**Where the mission comes from.** Every hook receives `transcript_path`, and the operator's typed
prompts are records in it. Each turn this reads only the bytes the transcript has grown by since
the last turn — so the cost is one turn's growth, not the size of the session — and folds any new
prompt into a set of **anchors** carried in the session's state file.

**Every prompt is redacted before it is tokenised, and the limit of that is stated here.** This is
the only module that reads what the operator typed, so it is the only one that can copy a secret out
of a prompt — and it keeps two copies of what it derives: the anchors in
`advisory-<sessionkey>.json` under the state directory, and up to four of them quoted back in the
turn-end advisory. Tokenising is **not** redaction: the tokeniser splits on whitespace and
punctuation, and *some* credential shapes contain neither, so a key pasted into a prompt used to
survive the split intact — as an ordinary word, or, if it was pasted inside a path, as one of that
path's segments, which is the kind the advisory quotes. Each prompt now goes through the same
`Get-LwgRedacted` every other module's log text does, on the whole sentence and before the split,
because that function reads context (`api_key = ` in front of a value, the case of the characters in
it) that a lowercased token no longer has.

**What is left, on both destinations.** This page said until 3 August 2026 that the result was
"exactly as good as the pattern list in `lib/common.ps1` and no better", and that whatever got
through was "still written to the state file". Both halves were wrong. An **enumerated** shape got
through: the `private_key` rule matched a pasted PEM and replaced its `BEGIN` line only, and the
base64 body that survived contains `/`, which the tokeniser reads as a **path separator** — so the
body was promoted to the anchor kind the advisory *quotes*. Measured end to end against the pre-fix
tree, **three of the four** quoted slots were key material and `parser.ps1` — the file the operator
had actually named — was pushed out of the list to make room. And the state file is only one of the
**two** destinations named in the sentence above it.
The `BEGIN`-line-only gap is closed as of the same date and pinned by `B19` in
`tests/stop_behaviour.ps1`, on both destinations.

What genuinely remains: a high-entropy string in a shape nobody enumerated — a 32-character hex key,
a passphrase typed as a word — still becomes an anchor, is still written to
`advisory-<sessionkey>.json`, **and can still be quoted back in the `systemMessage`**; anchors are
sorted, so such a value can sort first and *lead* the quoted list rather than merely appear in it.
The opposite failure is real too and is the acceptable direction: over-redaction can cost this module
its standing, because the word `token:` in front of a path makes the **path** the value. Measured:
`Rework the token: C:/work/ws/module/parser.ps1 handling please.` yields **zero** path anchors, where
the same sentence without that one word yields **four**. Zero path anchors means the module has no
standing and says nothing. Silence is this module's documented failure direction; a leak is not.
A session that was already running
when this landed re-reads its transcript **once**, from the start, and rebuilds its anchors through
the redaction — the pre-redaction anchors are discarded rather than cleaned, because a token with
its sentence gone can no longer be recognised as a credential by anything.

There is deliberately **no `UserPromptSubmit` hook**, which is the obvious way to capture a
mission. A hook registration cannot be made conditional, so that hook's process would be spawned
on every prompt whether the module was on or off — a measured **285 ms per prompt**, which was
charged for a feature that then shipped disabled and would now be charged twice per turn on top of
the `Stop` work. Reading the transcript costs ~137 ms inside a process that already exists, and
costs exactly nothing when the flag is off. Both numbers are one development machine's
measurements rather than constants — the 285 ms is PowerShell 5.1 interpreter startup, which a
slower machine pays more of, not less — and the distribution behind the 137 ms is in
[Architecture](architecture.md#mission_drift-which-is-switched-on-by-default).

**The trigger.** It warns only when *all* of these hold:

1. the operator has named at least one concrete path or filename in some prompt this session —
   with nothing named there is no basis to judge anything, and it stays silent;
2. at least `min_files` (default 3) source or documentation files were edited;
3. **every** one of them is outside the workspace root (git root, else `cwd`);
4. and **none** of them shares a directory segment, a filename stem or an ordinary word with
   anything named in **any** prompt this session — not just the first.

**A pivot cannot trip it.** Anchors accumulate across the whole session and are never reset. The
moment the operator redirects the work, that prompt's own nouns and paths become anchors, and the
work that follows matches them. Drift is work matching *nothing that was ever asked for*; a pivot
is by construction something that *was* asked for. This is the case the module was built around,
and since 31 July 2026 it is **run rather than read**: case B2 of
[`tests/stop_behaviour.ps1`](../tests/stop_behaviour.ps1) drives three turns — a prompt naming a file
in the workspace, a redirection naming a sibling tree with the work landing there, and a third turn
whose prompt names only the *original* file while another unrelated file is edited. The third turn is
the one that bites: nothing in its own slice of the transcript excuses the work, so only an anchor
carried over from an earlier turn can, and the case goes red the moment anchors stop accumulating.

**And it holds only while the anchor set is below `max_anchors`.** The accumulator stops adding at
the cap rather than making room, and the total it tests is carried in the state file and only ever
grows — so the first turn that reaches 400 anchors is the last turn that learns anything. A prompt
typed after that contributes nothing, and a pivot announced in it would be invisible. As of 3 August
2026 the module **latches silent** when the set saturates, exactly as it does for the two bounds
below, and writes one `MissionAnchorsCapped` record to `lw-watchtower.jsonl` naming the cap and the total.
Before that date it went on judging the session against a mission that had stopped being updated,
and warned that the operator had never asked for work they asked for one turn ago. The latch is a
guarantee that it will not say that; it is **not** a repair of the pivot property, which is gone for
the rest of the session once the cap is reached. Repairing it means evicting old word anchors to
make room, in `Add-LwgMissionAnchors`, and that is not done.

**False positives it can still produce** — one class, and it is real: a redirection phrased with
no concrete noun at all (*"now go fix the other repo"*) followed by edits in a tree nobody named.
The anchor matching is deliberately generous — one shared directory segment anywhere in the path
is enough to excuse a file — so this needs the new work to share nothing at all with anything said
so far.

**False negatives, which are many and deliberate:**

- any drift that stayed **inside** the workspace root — the default rule cannot see it;
- any drift in a session that also touched something that *was* asked for — one accounted file
  silences the whole assessment;
- anything changed by a shell command rather than `Write`/`Edit`/`NotebookEdit`;
- anything edited before the shared edit list rolled at 256 KB, and any path longer than 1 024
  characters — both bounds are described under [`docs_coupling`](#docs_coupling), which reads the
  same file;
- any session where a single turn appended more than `max_scan_bytes` (2 MB) of transcript. That
  region is **skipped**, and the module then stays silent for the rest of the session rather than
  judging on a partial record — silence on incomplete evidence, never a guess.
- any session where one slice held more than **400 records** the parse had to read. That is a second
  bound, on what is parsed rather than on what is read, and it now latches the same silence for the
  same reason. It is only reachable where a slice is a whole session rather than one turn's growth —
  the first turn of a resumed session, and the one-turn rebuild described above — and until 3 August
  2026 it broke out of the parse **without** setting that latch, leaving the module to judge a
  session on an anchor set it did not know was short.
- any session whose accumulated anchor set reaches `max_anchors` (400). From that turn on nothing
  further is learned, so the module latches the same silence — see *A pivot cannot trip it* above for
  what that costs. Reachable in ordinary use: words and paths share one budget, every token of four
  or more letters that is not a stop word is a word anchor, and each surviving path segment is
  another, so a handful of substantial prompts — a pasted stack trace, a directory listing, a
  specification — get there without difficulty. Note the latch can fire one turn early, on a set that
  landed exactly on the cap with nothing further to add.

Segments that distinguish nothing are dropped before matching: the universal ones (`users`,
`appdata`, `tmp`…), drive letters, and **every segment at or above the workspace's parent**.
Without that last rule one pasted absolute path would share the drive letter, the account name and
the enclosing folders with every file on the disk, and nothing could ever look unrelated.

| Knob (`module_config.mission_drift`) | Default | Effect |
| --- | --- | --- |
| `min_files` | 3 | how much unrelated work is needed before it will speak |
| `require_outside_root` | `true` | `false` also flags unrelated work **inside** the workspace — considerably more useful and considerably noisier, because a task routinely reaches past the one file that was named |
| `max_scan_bytes` | 2 097 152 | one turn's transcript growth beyond which the region is skipped and the module goes silent |
| `max_parse_records` | 400 | how many records of one slice the parse will read. Reaching it **latches the same silence** `max_scan_bytes` does. Reachable only where a slice is a whole session rather than one turn's growth — a resumed session, or the one-turn anchor rebuild. Note the budget is spent on records that pass a loose pre-filter, not on prompts, so it is reached sooner than the number suggests |
| `max_anchors` | 400 | cap on the accumulated anchor set. **Reaching it silences the module for the rest of the session** — accumulation stops rather than making room, so nothing said afterwards can be learned, and the module latches rather than judge on a set it can no longer add to |

It warns **at most once per session**: the dedupe signature is the verdict *none of this session's
edits is accounted for*, not the list of files behind it, so a standing condition does not repeat at
every turn end and does not repeat when the list grows either. `git_hygiene` has the same property,
built the same way, from condition ids with counts excluded. `docs_coupling` does **not** — it
re-warns each time the source-file count exceeds the count it last warned at — so read that one as
once per additional source file, not once per condition.

---

## `self_health`

The `SessionStart` self-check ([`lib/session_start.ps1`](../lib/session_start.ps1)). Five probes,
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
construction. [`lib/subagent_start.ps1`](../lib/subagent_start.ps1) reads
[`context/worker_facts.md`](../context/worker_facts.md) — live, every single time — and hands it to
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

## `failure_capture` and healing

See [Health and healing](architecture.md#health-and-healing).
