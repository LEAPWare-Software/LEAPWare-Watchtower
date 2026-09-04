# Limitations — what this plugin cannot do

This page is the consolidated list of everything LW-WATCHTOWER does not do, cannot do, or does not check.
The facts on it are scattered across the rest of `docs/`, `config.json` and `README.md` by necessity —
each one belongs next to the thing it is about — so this is the one place they are collected and
counted. Nothing here is a plan to fix any of it.

Read it as the counterweight to every other page. This project's only distinguishing claim is that it
reports accurately on itself, and a project making that claim owes the reader a page that is nothing
but the negative half.

**Every claim below was checked against this tree** — the source, the config, the hook registrations,
the test files and the checklist's own output. The performance figures are the exception and are
quoted rather than re-measured: they are one development machine's medians, labelled as such at every
point they appear, and yours will differ. Where something is asserted from reading source rather than
from running it, it says so.

---

## The short version

| | |
| --- | --- |
| Can it refuse a destructive command? | **No.** Nothing inspects a shell command. |
| Can it stop a credential reaching disk? | **No.** Nothing inspects written content, and nothing inspects a path in order to refuse it — one hook reads an edited path *after* the write, to feed two advisories. |
| Does it install any `permissions.deny` rule? | **No.** The installer has no rule table any more — the function and the section that wrote it are both deleted. |
| Can it block anything at all? | **Three things**, and it ships switched off — see [the gates](#the-three-gates-block-little-and-all-ship-off). |
| Can it block assistant text? | **No.** There is no hook between the model and the transcript. |
| How many of its eleven modules are tested? | **All eleven** — all three gates and all eight observing ones — but only in the cases somebody thought to write, and for several of them one or two properties apiece is the whole of it. See [What no test covers](#what-no-test-covers) before reading that as coverage. |
| Does it run anywhere but Windows PowerShell 5.1? | **No**, and it does not pretend to. |

---

## Contents

- [The plugin blocks almost nothing](#the-plugin-blocks-almost-nothing)
- [Why the gates went](#why-the-gates-went)
- [The three gates block little, and all ship off](#the-three-gates-block-little-and-all-ship-off)
- [The advisory modules advise; they do not enforce](#the-advisory-modules-advise-they-do-not-enforce)
- [The gate costs ~330 ms on every edit and command, on or off](#the-gate-costs-330-ms-on-every-edit-and-command-on-or-off)
- [What no test covers](#what-no-test-covers)
- [Platform, install and state](#platform-install-and-state)
- [The documentation is not checked against the tree](#the-documentation-is-not-checked-against-the-tree)
- [Things that were specified and cannot be built](#things-that-were-specified-and-cannot-be-built)
- [What a fully green run actually establishes](#what-a-fully-green-run-actually-establishes)

---

## The plugin blocks almost nothing

Every destructive-command and secret-scanning gate was removed on **30 July 2026** by explicit owner
decision, and neither is coming back. As shipped today:

- **No hook inspects a shell command.** `hooks/hooks.json` registers nothing on `Bash` or
  `PowerShell` for the purpose of reading a command. Force pushes, hard resets, `git clean -f`,
  history rewrites, reflog expiry, recursive deletes and GitHub repository destruction are all
  unexamined.
- **No hook inspects a path or the bytes being written *in order to refuse anything*.** A write to
  `*.pem`, `*.key`, `id_rsa*` or `.env`, or a write whose content is a live GitHub, AWS or Slack
  token, reaches disk with nothing here refusing it. **One hook does read a path**, and it is stated
  here rather than left to be discovered: `lib/post_edit.ps1` runs on `PostToolUse` and appends
  `tool_input.file_path` (or `notebook_path`) to a per-session list, which `docs_coupling`
  reads at turn end. It runs **after** the write, it makes no judgement about the
  path, and it can refuse nothing — but "no hook inspects a path" was false as written, and a page
  about what this plugin does not do cannot afford a false negative. Nothing here inspects the
  **bytes** being written, by any route.
- **No hook refuses a write inside `.git/`.** `[core] sshCommand` in `.git/config` is arbitrary code
  execution on the next git command, and no layer here refuses it.
- **`permissions.deny` is empty.** `Get-DenyGroups` in [`bin/lwg-setup.ps1`](../lw-watchtower/bin/lwg-setup.ps1)
  no longer exists, and neither does the `permissions` section that called it, so
  `/lw-watchtower:setup` writes **zero** rules. It wrote 181 in six groups until
  that date. `-SecretGate` and `-DestructiveGate` are not accepted parameters that select nothing —
  they are **not parameters**: the installer is `[CmdletBinding()]`, so passing either is a binding
  error before a line of the script runs and nothing is written. `-Section permissions` is refused by
  the same mechanism.
- **The secret regex patterns that survive in `lib/common.ps1` are used for log redaction only**
  (`Get-LwgRedacted`). Nothing scans a write with them.

The full before-and-after table is at
[Modules § Both gates were removed](modules.md#both-gates-were-removed). The installer's side is at
[Install § the installer writes no `permissions.deny` rules](install.md#the-installer-writes-no-permissionsdeny-rules).

**One consequence is easy to miss.** A machine set up before 30 July 2026 still carries the old 181
rules in its own `settings.json`, and the CLI still evaluates them. Nothing here renews them and
setup never removes a rule already in your file, so two machines running the same version of this
plugin can behave differently, and the difference is invisible from inside the plugin.
`/lw-watchtower:uninstall` is the only code left that knows what those rules looked like.

**If you want that layer back, you write it yourself.** `permissions.deny` in your own
`settings.json` is the only layer here that cannot fail open, because the CLI evaluates it before any
hook runs. This plugin will not write it for you.

## Why the gates went

The removals were owner decisions, not a verdict this repository reached on its own. But the record
of *why the last attempt cost what it did* is kept, in full, at
[Gates were removed deliberately](gates-removed.md), and it is the strongest evidence on this page
that a green result here means less than it looks like.

Summarised honestly, without softening:

- **Four separate attempts were made to fix one hole** in `destructive_gate` — a here-document body
  walked as ordinary shell source, so a stray quote inside it swallowed everything after it and the
  gate ALLOWED the command that followed. Real, not theoretical: re-run against GNU bash 5.3.9, the
  trailing `git push --force origin main` executed.
- **Two of the four were reverted, and between them they opened five new bypasses.** Every one came
  from the same kind of addition — a decision that some input was *safe not to scan*. The isolation
  logic they all shared opened zero. The exemption was the entire failure surface.
- **The test suite never once caught a bypass.** It was **67 of 67 green while five bypasses were
  open**. Every hole in the record was found by somebody deliberately trying to break the gate, and
  turned into a regression case afterwards. The suite's growth from 67 to 233 cases is a record of
  what break-attempts found, not evidence that testing found anything.
- The standing conclusion drawn from that, in `gates-removed.md`:
  **a gate with a green suite and no independent break-attempt should be assumed broken.**

That conclusion applies to `tests/gate_delegate.ps1` too. It is 93 of 93 green, and that fact is
worth exactly what the paragraph above says it is worth.

What a future gate now has to **rebuild from nothing**, because it was removed rather than kept, is
listed at
[The trip ledger was NOT kept](gates-removed.md#the-trip-ledger-was-not-kept--a-gate-has-to-rebuild-it):
the ledger format, the writer, the acknowledge path, the turn-end sweep and the indicator. That is
most of the work of adding a gate, and this repository no longer contains any of it.

## The three gates block little, and all ship off

`delegate_gate` ([`lib/gate_delegate.ps1`](../lw-watchtower/lib/gate_delegate.ps1)) is the only thing in this plugin
that can refuse a tool call. Its limits:

- **It ships switched off** (`interaction.delegate: false`), so as shipped the live gate count is `0`
  and a healthy session reads `observe-only`.
- **It makes no safety determination of any kind.** Nothing it decides consults the tool name, the
  path, the command or the content. Its one rule is: when the switch is on, refuse `Edit`, `Write`,
  `NotebookEdit`, `Bash` and `PowerShell` for any call that did not come from a subagent. It *does* read
  `payload.tool_name`, after the decision, for the single purpose of naming the refused tool in the
  deny text — the gated tool list itself lives only in the `hooks/hooks.json` matcher, so a stale
  second copy inside the script cannot open a hole. The distinction is written out here because
  "it does not read the tool name" was stated flatly and is not true of the code.
- **The gated tool list is an enumeration, and an enumeration is a thing that can be short.** It was
  short until 1 August 2026: the matcher named `Bash` and not `PowerShell` on a plugin that supports
  **Windows and nothing else**, where the CLI offers both shell tools — so with the gate armed the
  main thread could do every bit of the work the gate claims to refuse by asking for the other
  shell, while `/lw-watchtower:doctor` printed *"1 gate(s) LIVE — it can refuse a tool call right now"*.
  Nothing in the gate script was wrong; the CLI never invoked it. That specific hole is closed and
  [`tests/gate_delegate.ps1`](../tests/gate_delegate.ps1) section M is the regression case — it is
  the only section of that suite that models the CLI's matcher selection instead of assuming it.
  **The shape of the hole is not closed.** Two things are still uncovered, and neither is a bug that
  can be fixed by adding a name:
  - **`mcp__*` tools.** A tool from an MCP server the operator installed can write files and run
    commands, it reaches `PreToolUse` like any other tool, and **its name is not knowable from this
    repository** — it depends on that operator's servers. No enumeration can cover it.
  - **Any tool the CLI adds after this was written.** The matcher does not learn.

  A matcher permissive enough to cover both was considered and rejected, for two reasons rather than
  one. The registration cannot be made conditional, so it would put the gate's ~436 ms on **every**
  `Read`, `Grep` and `Glob` in the main thread *and* in every subagent, on by default for operators
  who never arm it. And it would select `Agent` — the dispatch the deny text tells the operator to
  make — which is not an over-block but a session with no exit, since the other route out runs
  through `Bash` and is refused on purpose.
- **It is not a security control and a way past it is not a vulnerability.** A subagent can do
  everything it refuses, by design. It refuses a main-thread write of a credential and permits a
  subagent's, which is not a security property. The two uncovered routes above are read in that
  light: they are the gate refusing less than an operator might assume, not a control being broken.
- **It enforces delegation, not good delegation.** It never checks that a dispatch was any good.
- **Turning it on is close to one-way from the chat session.** `/lw-watchtower:delegate off` runs through
  `Bash`, which is one of the five refused tools, and there is deliberately no exemption for it —
  nor is `PowerShell` a way round that, since 1 August 2026. The two routes back are a subagent
  running the command, or setting `interaction.delegate` to `false` by hand in
  `config.override.json` under the state directory — `$CLAUDE_PLUGIN_DATA`, or
  `~/.claude/plugins/data/lw-watchtower*/`. **Not in `config.json`**: that file is the shipped
  defaults, and an edit there changes nothing while the override still says `true`.
- **Read-only verification costs a dispatch, and this is an accepted cost rather than an oversight.**
  With the switch armed, *every* `Bash` and `PowerShell` call from the main thread is refused,
  read-only ones included: `git status --short` is refused exactly as `git push --force` is, exit 2,
  with the deny text offering one route — dispatch a subagent and have it make the call. So checking
  a worker's output from the main thread costs a full agent dispatch, every time.
  **The gate will not be taught to allow the safe ones.** Doing that means classifying what a command
  does from a string, which is the thing this repository has already failed at four separate times
  (the record is [gates-removed.md](gates-removed.md)) and which
  [`lib/gate_delegate.ps1`](../lw-watchtower/lib/gate_delegate.ps1)'s own header names, at three
  separate points, as the entire reason the gate is trustworthy: it reads no path, no command, and
  not even `tool_name` before deciding. An allowlist reopens the *scanner stricter than its consumer*
  defect class that this very file has shipped twice since. The cost is a latency cost and not a
  capability cost — the escape hatch is named in the deny text — and if it is ever judged intolerable
  the honest fix is upstream: an orchestrator that batches its verifications into one dispatch, not
  an exemption inside the gate.
- **A denial is not tracked as an open item.** It is written to `lw-watchtower.jsonl` as a `GateDeny`
  event; nothing records, reads, closes or acknowledges it, and the status line has no governance
  segment. The `sitrep` command counted those records as history and went on 2 September 2026, so
  nothing counts them now and nothing can clear one.

Full detail: [`delegate_gate`](modules.md#delegate_gate).

## The advisory modules advise; they do not enforce

Eight of the eleven modules are kind `observe`. **Not one of them can stop, delay or alter anything** —
they warn at turn end, or write a log record, and the action happens regardless. The advisory handler
exits 0 on every path and its only stdout is a `systemMessage` envelope with no `decision` field.
*That was a property of the source, established by reading it, until 31 July 2026. It is now run:
`tests/stop_behaviour.ps1` asserts exit 0 on every case it drives, and case B8 asserts on a real
emitted envelope that it carries no `decision` member. That covers the five modules that suite
reaches — `failure_capture`, `context_pressure`, `docs_coupling`, `git_hygiene` and
`log_rotation`. For the other observing modules it is still a property of the source and
nothing more.*

The useful distinction is between a module that observes a **fact** and one that
runs a **heuristic**. Both are advisory; only the first is telling you something it actually saw.

| Module | Observes | What limits it |
| --- | --- | --- |
| `failure_capture` | a fact — the hook event it was handed | Records what the CLI reports. It cannot see a failure the CLI does not report as one. |
| `self_health` | a fact — five probes, each asserting a real returned value | Runs at `SessionStart` only. With `self_health` off, no probe runs and the session reports mode `unverified`, not a pass. |
| `log_rotation` | a fact — the file's size | Caps two named logs, `health.jsonl` and `lw-watchtower.jsonl`. It does **not** bound the state dir — the per-session `advisory-*` and `edits-*` files are swept by nothing. Asserts nothing about content. |
| `context_pressure` | **partly** — real token counts, an **inferred** denominator | No hook receives `context_window`. Occupancy is recomputed from the transcript with the CLI's own arithmetic, but the **window size** depends on account entitlement and is assumed at 200 000 unless configured, `[1m]`-tagged, or proven by observation. For an unrecognised 1 M model, occupancy between 150 k and 200 k reads as `75–100%` until one turn crosses 200 k. |
| `docs_coupling` | a fact — the paths edited, over a **narrow window** | `Write`/`Edit`/`NotebookEdit` only. **A file rewritten by a shell command is invisible to it.** Its doc/source/neither classification is a configurable word list, not an analysis. |
| `git_hygiene` | a fact — git's own answer | The only module that spawns a subprocess, on `Stop` only. If git is missing, times out or exits nonzero it reports **UNKNOWN**, never "clean" — but the operator has to read that word. Its open-PR half needs `gh` and the network and is best-effort by construction. |
| `context_injection` | a fact — it emits the current bytes of one file per dispatch | It injects; it cannot block, because `SubagentStart` has no blocking channel. **Nothing verifies the worker read it or acted on it.** That the escaper emits pure ASCII rests on inspection of the source. |

Blind spots per module, in the modules' own words:
[the per-module caveats in Modules](modules.md).

## The gate costs ~330 ms on every edit and command, on or off

A hook registration cannot be made conditional, so `lib/gate_delegate.ps1` runs before **every**
`Edit`, `Write`, `NotebookEdit`, `Bash` and `PowerShell` call whether `interaction.delegate` is on
or off. An
operator who never touches the switch pays the whole cost.

Measured on one development machine, `cmd` piping a payload into a fresh interpreter, 9 runs
interleaved — read these as one machine's medians, not as constants:

| | median | min–max |
| --- | --- | --- |
| bare `powershell -File` that drains stdin and exits 0 — the interpreter floor | 294 ms | 278–304 |
| `delegate_gate`, switch off (shipped), main thread | 436 ms | 423–510 |
| `delegate_gate`, switch off (shipped), subagent | 426 ms | 411–512 |
| `delegate_gate`, switch **on**, main thread — the deny | 868 ms | 785–1064 |

So roughly **142 ms of the gate's own work**, on top of a 294 ms floor it does not control, on every
one of those five tools. The figures were **not** re-measured when `PowerShell` was added to the
matcher on 1 August 2026: they are the cost of **one call**, and adding a tool to the matcher changes
how many calls are charged, not what a call costs. What it does change is a session's total bill, by
however much of its shell use goes through the second shell.

That is now true. **It was not true when it was first written**, and the correction is the point.
Both of `bin/lwg-setup.ps1`'s hook-identity functions key on the matcher **string**, so widening the
matcher made every `v0.3.0` registration of the gate unrecognisable: re-running setup on a machine
whose hooks live in `settings.json` added a **second** `PreToolUse` group beside the first, both
invoking the same `lib/gate_delegate.ps1`. On those machines one `Edit`, `Write`, `NotebookEdit` or
`Bash` call cost **two** gate runs — the per-call figure in the table above doubled, for an operator
who never armed the switch. So the sentence "a fifth tool changes how many calls are charged, not
what a call costs" was a claim about the consequences of that edit, asserted rather than established,
and the edit falsified it.

What makes it true now is not an argument but a table and a case:
`$script:LwgSupersededMatchers` in `bin/lwg-setup.ps1` maps the `v0.3.0` spelling to the current one
so the old registration is recognised instead of duplicated, and
`tests/setup_merge.ps1`'s `superseded matcher` cases pin that `gate_delegate.ps1` ends up registered
**exactly once** and that the stale matcher is **reported** — because recognising it silently would
leave `PowerShell` unhooked while telling the operator the gate was present. The maintenance cost is
real and is not designed away: the next matcher change needs another entry in that table, in the same
commit, or the duplicate comes back. Nothing detects a missing entry automatically.

Those figures were re-measured
on 31 July 2026 when a fast path landed; the
off-path median was **652 ms** before it. **The deny path got slower** — it was 743 ms — because with
the switch on the fast path runs, fails to prove the switch off, and the slow path then does
everything it always did. That is recorded here rather than left out: the saving goes to the operator
who never arms the gate, and the extra cost to the one who did, on a call being blocked anyway. The
only way to remove any of it is to delete the `PreToolUse` entry from
[`hooks/hooks.json`](../lw-watchtower/hooks/hooks.json), which also removes the ability to ever turn the gate on.

Turn end costs are separate and are measured at
[Architecture § turn-end cost](architecture.md#turn-end-cost). The short version: about 1 212 ms
median for the advisory handler against a 283 ms interpreter floor, and the remaining ~930 ms is
overwhelmingly **PowerShell 5.1 engine warm-up, not data work**. It is not reducible much further
from this side.

## What no test covers

**Eleven suites in this repository establish a behaviour of this plugin, and between them they reach
all three gates, three writers, one deleter, the session-start hook, two of the doctor's ten checks,
one hook's fast path, the shipped payload, and all eight observing modules.**

| Suite | What it establishes |
| --- | --- |
| `tests/gate_delegate.ps1` | 93 cases through a real pipe into a real child process: that `delegate_gate` refuses what it declares, and that the gate and the command that reports it give the same answer for the same config. |
| `tests/stop_behaviour.ps1` | 117 cases, the helpers in process and the hooks in real child processes: pinned behaviours of `failure_capture`, `context_pressure`, `docs_coupling`, `git_hygiene` and `log_rotation`, including two supervisor bugs that had already shipped, and the redaction helper every module's error text passes through — asserted to keep no part of a credential pasted into a prompt out of a state file or an advisory. |
| `tests/uninstall_footprint.ps1` | 27 cases against `bin/lwg-uninstall.ps1`, asserting on the filesystem as well as on the report: that the state-data footprint names what it deletes, deletes what it named, and exits non-zero rather than calling a no-op deletion a success; that what it attributes to this plugin really is this plugin's, including all 181 `permissions.deny` rules the pre-30-July installer wrote; and that what it refuses — a reparse point, a directory holding none of this plugin's files, a `settings.json` it could not parse — it names and counts as un-removed. The only suite that tests a **deletion**. |
| `tests/setup_merge.ps1` | 185 cases. Against `bin/lwg-setup.ps1`: that the installer's merge preserves settings it was not asked to touch, takes one backup, is idempotent and rolls back; that it recognises a marketplace install and a registration of its own scripts under another root. The only suite that tests a **write**. Its last sections are not about the installer — they are the only coverage the **reporting surfaces that survive it** have: `statusline/statusline.ps1` (payload decoding, the three states a number can be in, the `HH` fault gauge, the reset clock, the paths and the config it reads) and `bin/lwg-update.ps1` (`-Offline` with `-Apply`, a diverged branch, the exit-4 attribution, the junction route). Nothing exercised `bin/lwg-update.ps1` in any form before that. |
| `tests/doctor_behaviour.ps1` | 32 cases driving `bin/lwg-doctor.ps1` from a scratch copy of the whole plugin tree against seeded configs and seeded `settings.json` files: that `config-registry` refuses a switch whose value is not a real `[bool]` rather than passing it for being present, that `statusline` asks whose file a status line is before diagnosing it as a stale copy of this plugin's, and that it reads the `settings.json` the CLI actually reads rather than one composed from the profile. **Two of the doctor's ten checks and no others**, and a substantial minority are `CONTROL` cases that pass before the fix too. A byte-identical or token-bearing foreign status line is a stated limit, not something these cases catch. |
| `tests/toggle_behaviour.ps1` | 28 cases against `bin/lwg-toggle.ps1`'s write to `config.override.json`, in real child processes against a byte copy of `bin/` and `lib/`: that the write takes a backup, re-checks that the file on disk is still the one it read, keeps a BOM, refuses a config it cannot read back, never reports exit `3` for a run that changed the file, and closes with an invariant that no run moved a byte of the plugin root's `config.json`. The only suite besides the merge one that tests a **write to a file an operator owns**. |
| `tests/subagent_scan.ps1` | 8 cases piping payloads into the real `lib/subagent_start.ps1`: that its raw-text fast path answers the **global** `modules` flag whatever order the top-level keys appear in, and agrees with the slow path it exists to avoid. The only coverage `context_injection` has. Every case asserting silence re-runs the same fixture with one bit changed and requires the injection to appear, because a bare negative is satisfied by a hook that crashed. It asserts on answers, **not on the milliseconds** the fast path exists to save. |
| `tests/payload_guard.ps1` | 22 cases over two enumerations, and the split is the point: the **shipped payload**, which since the restructure is `lw-watchtower/` alone because `marketplace.json` declares `"source": "./lw-watchtower"`, and the rest of the tracked tree, which a consumer never receives. That no tracked file carries a pull-ref narrative, a former personal address, a plan file's name, a release-plan heading, a containment claim that inverts when visibility changes, or — inside the payload — a shipped file naming a script this branch deleted. It reads files rather than running this plugin's code, and it is a statement about **the shapes it carries**, not about everything a reader would rather not ship. |
| `tests/portability_scan.ps1` | That no tracked file names a machine. **Nothing about behaviour** — a file can be perfectly portable and completely broken. |
| `tests/workflow_guard.ps1` | That no workflow definition reaches a runner GitHub does not host. A *file* check, not a behaviour. |
| `tests/doc_claims.ps1` | That no tracked page states a count — of suites, cases, CI steps, doctor checks, commands or modules — that the tree contradicts, and that every page under `docs/` is reachable from the index the site's front door renders. A check on the *documentation*, not on anything this plugin does. |
| `tests/config_behaviour.ps1` | 42 cases against `bin/lwg-config.ps1`, the module switchboard's write path, which nothing in `tests/` had ever executed: the refusals it is built around, the two-phase preview, the surgical JSON edit and the exit-2 read-back. Like the toggle suite it closes with an invariant that no run moved a byte of the plugin root's `config.json`. |
| `tests/state_resolution.ps1` | 32 cases against `lib/session_start.ps1` — the one surface every session sees — which nothing in `tests/` had ever executed either: the five self-check probes, the mode words, the state-directory resolution including `CLAUDE_CONFIG_DIR`, the banner, and the `additionalContext` envelope. Its own header states why its later sections exist: **execution is not coverage**, and the hook was being run nine times by cases that asserted almost nothing about it. |
| `tests/supervision.ps1` | 64 cases against the other two gates, `send_liveness_gate` and `completion_audit`, and against `orphan_watch`, through a real pipe into a real child process against a throwaway plugin root. Its anchor cases reproduce the measured 1 August 2026 failure exactly — a 28-minute-45-second-stale transcript with no stop record, and a completion claim whose turn ends in `SendMessage` — and require the deny, the block and the orphan alert respectively. It carries the same standing caveat as the delegate suite: a green run says these cases still behave, not that the gates are sound. |

**Every module in the registry is now reached by some suite, and that is a much weaker statement than
it sounds.** Coverage here is the cases somebody thought to write, not coverage in general.
`stop_behaviour.ps1` reaching `failure_capture` moved the count off zero on 31 July 2026; the
`context_pressure`, `docs_coupling`, `git_hygiene` and `log_rotation` cases followed on 3 August 2026;
`subagent_scan.ps1` reached `context_injection`; `supervision.ps1` reached `orphan_watch` and the two
supervision gates; and `state_resolution.ps1` reached `self_health`'s probes through the session-start
hook. None of that made the observing half *tested*, and for several of them one or two properties are
the whole of it. Read [Testing and CI](testing.md) for the current inventory rather than trusting a
count transcribed here.

**A green CI run therefore says that tracked files parse, that no tracked file names a machine, that
no tracked page states a count the tree contradicts, and that the suites in the table above still
behave as their cases declare. It is not evidence that this plugin is sound**, and for most of the
observing modules it is evidence about one or two properties and nothing wider.

Uncovered, item by item, because an absence nobody writes down reads as coverage:

- **Thin coverage of most of the observing modules.** Five are reached by
  `tests/stop_behaviour.ps1`, in the cases somebody thought to write: `failure_capture` since
  31 July 2026, and `context_pressure`, `docs_coupling`, `git_hygiene` and `log_rotation` since
  3 August 2026. `context_injection` is reached by `tests/subagent_scan.ps1`, `orphan_watch` by
  `tests/supervision.ps1`, and `self_health`'s probes by `tests/state_resolution.ps1`.
  **This list said seven modules were exercised by nothing until the second set landed and named four
  of them — it was the coverage claim itself going stale, which is the failure this page exists to
  prevent, and nothing in `tests/` checks it.** What the four amount to, counted on 3 August 2026:
  `context_pressure` has TWO cases, on the impossible-occupancy refusal and on a window being learned
  only after a second reading; `log_rotation` has THREE — the on/off pair and the tail-carry;
  `docs_coupling` has TWO, and only one of them is about `docs_coupling` itself (that its advisory is
  bounded), the other being about the write that feeds it; `git_hygiene` has ONE, that an UNKNOWN tree
  state is repeated at every turn end rather than once. None of them establishes that its module
  advises the right thing. `context_injection` has ONE, that the fast scan answers the global flag
  whatever order the top-level keys are written in; what the hook does with `worker_facts.md` has no
  case at all.
- **The installer's WRITER outside `statusline`.** `tests/setup_merge.ps1` establishes, for the
  `statusline` section, that `/lw-watchtower:setup` leaves unrelated settings byte-identical and in order,
  takes exactly one backup holding the original bytes, refuses `apply` without a matching `BaseHash`,
  is idempotent, and rolls back byte for byte. The `hooks` section now has cases, but they are about
  what it **decides** — that a marketplace install is seen, and that a registration of the same
  script under another root is reported rather than duplicated. **The byte-level writer properties
  are still only inherited by `hooks`**, since both go through the same `Save-Settings` path; the
  backup-collision suffix, the post-write auto-restore and **the atomicity of the write itself** are
  named as uncovered in the suite's own header. `permissions` writes nothing, so there is nothing
  there to merge-test — the parity test that once covered the deny table went with the table itself,
  and that half is settled rather than outstanding. Its **diff** is now driven, for the one thing
  that section still reports: rules already in the operator's own file that cannot match anything.
- **The write is not an atomic replace, and is not claimed to be.** `Save-Settings` stages the new
  file beside the target and copies it over, so a process killed or a volume filled part-way through
  can leave `settings.json` truncated; the re-read and parse-check after the write is what catches
  that, and the automatic restore uses the same call and can fail for the same reason. The atomic
  `[IO.File]::Replace` was measured and rejected — it refuses whenever any other process holds the
  file open read-write, which an indexer or an anti-virus scan routinely does — and the reasoning is
  recorded in that function's docstring. No test induces an interrupted write.
- **Where a marketplace install lives is evidence, not a contract.** The paths
  `bin/lwg-setup.ps1` and `statusline/statusline.ps1` probe —
  `~\.claude\plugins\cache\<marketplace>\<plugin>\<version>` and
  `~\.claude\plugins\marketplaces\<marketplace>` — were read off a live `~/.claude` tree and out of a
  2.1.x CLI binary, in which the previously assumed `plugins/repos` appears zero times. Both files
  still scan `plugins\repos` as well, precisely because no build promises any of this. Both also
  resolve the **base** of those paths the same way — `CLAUDE_CODE_PLUGIN_CACHE_DIR` if it is set,
  `~\.claude\plugins` otherwise, and **both bases when it is set**, since a machine that relocates
  today may still carry an install written under the default. That agreement is recent: the probe
  rewrite taught the installer to read that variable and left the status line hardcoding
  `$env:USERPROFILE`, so on a supported relocation — no layout change at all — setup reported
  `marketplace install: <relocated path>` and *"Claude Code can auto-discover it"* while the status
  line on the same profile rendered `HH?` and silently replaced the operator's configured thresholds
  with the built-ins. Those are the two symptoms this entry exists to describe, and one fix had left
  them alive in the other file. `tests/setup_merge.ps1` now covers it, which it could not before:
  the status-line sandbox cleared that variable as part of its setup, so the guard was blind by
  construction.

  The remaining asymmetry is the registry. The installer additionally reads the CLI's own
  `installed_plugins.json`, which is layout-independent; **the status line does not** — it is a
  `settings.json` command that dot-sources nothing and renders on every message, and parsing a
  registry per render was not worth the cost, so it is still the file that goes wrong first if the
  layout moves. The failure is silent either way: the installer writes a duplicate set of hook
  registrations, and the status line renders `HH?` on a working install.
- **"Installed" is not "loads here", and setup does not resolve the difference.** A plugin loads only
  if an `enabledPlugins` entry switches it on, and a **project-scoped** install belonging to another
  repository writes into exactly the same `plugins\cache` tree as a user-scoped one. Setup counts
  either as discoverable, so on a machine whose only install is scoped elsewhere it will report that
  the plugin supplies its own hooks and decline to wire any — leaving **nothing** running. It prints
  the `scope` and `projectPath` it read on the same line as the claim, and deliberately does not
  narrow the verdict on them: setup runs from wherever the session is, which is not necessarily the
  project the settings file will be used from.
- **The `SessionStart` banner beyond its text.** `tests/state_resolution.ps1` asserts the banner and
  the `additionalContext` envelope the hook prints; nothing asserts that the CLI displays either, so a
  banner suppressed at the harness would not fail a build.
- **The status line beyond what `tests/setup_merge.ps1` drives.** That suite runs
  `statusline/statusline.ps1` from a scratch copy against real payloads — the decoding, the three
  states a number can be in, the `HH` gauge, the reset clock. Nothing asserts that the rendered line
  reaches a terminal; a blanked row would surface only by being looked at.
- **That the advisory handler cannot block** — inspection of the source.
- **That the `context_injection` escaper emits pure ASCII** — inspection of the source.
- **`Get-LwgRedacted` beyond the shapes somebody enumerated.** This entry said "no test exercises
  it" until 3 August 2026 and that had been wrong since 1 August; it is corrected here rather than
  quietly deleted, because the sentence was load-bearing for a reader deciding whether to trust the
  redaction. Section A of `tests/stop_behaviour.ps1` exercises the helper directly and section C
  drives the supervisor path that reaches it end to end. No per-section count is quoted here on
  purpose: it would be a second number to keep in step with the suite, and this page already
  carries the only one that is checked. **What is still true is narrower and worse:** the helper
  matches credential *shapes*, so a shape nobody listed is not caught — a value under six
  characters, a value containing a quote, comma, brace, bracket or backslash, the base64 body of a
  PEM key after its `BEGIN` line, or a credential named by a word outside its keyword list.
  [`SECURITY.md`](../SECURITY.md#in-scope) enumerates both halves. An unredacted credential
  reaching a log record is still the one thing here that is a security report rather than a public
  issue.

`/lw-watchtower:doctor` is a **wiring** check, not a behaviour check. It confirms that hooks are registered,
that the scripts they name exist, that a module's switch is a key that really exists, and that the
state directory resolved and accepted a write. It cannot establish that any advisory fires, that
anything is protected, or that Claude Code has this plugin enabled in the current session — and it
says all three on every run, including the green ones. (It prints its own check count, which is why
no number for it is transcribed here.)

Full list: [Testing § what is not covered](testing.md#what-is-not-covered).

**Branch protection is a live hazard, not a hypothetical.** Any rule on `main` that still requires the
`gate-regression` context will block every merge, because that job was deleted and can never report
again. `fast-checks` is not the context to put in its place: that is the YAML job id, and a required
status check is matched by the check run's **name**, so requiring the id blocks every merge exactly as
requiring `gate-regression` does. The only requirable string is the surviving job's display name,
quoted verbatim under [Branch protection](testing.md#branch-protection) — the page the
documentation-claim guard holds to that string, deriving it from `ci.yml`. It is not repeated here,
because nothing holds this page to it. The checklist probe can see that a
protection object exists but not which contexts it names. Until **2026-08-28** it could not see even
that on this repository, because the protection API answered `403` on the plan then in force; the
visibility flip on that date lifted the `403`, measured by running
`gh api repos/LEAPWare-Software/LEAPWare-Watchtower/branches/main/protection`, which now answers.
**That leaves the probe's own limit as the whole of what is unchecked, and it is the more
consequential half** — a protection object requiring a string GitHub will never produce a check run
for still renders that row `DONE`. See [Branch protection](testing.md#branch-protection).

## Platform, install and state

- **Windows only, Windows PowerShell 5.1 only.** All thirteen hook registrations name the binary
  `powershell`, so `pwsh` is **not** a substitute *for a hook* — but the constraint is the
  registration and not the language level. Every tracked script declares `#requires -version 5`,
  which PowerShell 7 satisfies, so running one by hand under `pwsh` is not refused by the interpreter
  and says nothing about whether the hooks will fire. One script was checked under PowerShell 7 and
  produced byte-identical output; that is one script, not a claim about all twenty-one. There is no
  OS matrix in CI and no plan for one.
- **Hook events were read out of the claude-code 2.1.220 binary.** `SubagentStart`,
  `PostToolUseFailure` and `StopFailure` may not exist on older builds. Every claim in `docs/` about
  what a hook payload carries is pinned to that build and is a claim about it, not a law.
- **The status line is not part of the plugin and cannot be.** `statusLine` is a top-level
  `settings.json` key; a plugin has no manifest field for it and no hook event renders a line. The
  tracked [`statusline/statusline.ps1`](../lw-watchtower/statusline/statusline.ps1) has to be **copied** to your
  profile, and **the two files then drift silently** — including the case that costs most, a fix made
  to the live file and overwritten the next time the repo copy is installed over it. The doctor
  detects the drift; nothing prevents it. See
  [Install § this is a copy](install.md#this-is-a-copy-and-it-can-drift).
- **Two install routes are two identities and two data directories.** A marketplace install is
  `lw-watchtower@leapware-watchtower`; a skills-directory junction is `lw-watchtower@skills-dir`. Claude Code hands each
  its own `CLAUDE_PLUGIN_DATA`, so state written under one is invisible to a session resolving the
  other, and **no rule inside the resolution code can change that** — the `env` branch every live hook
  takes never reaches the ranking code at all. The durable fix is to stop having two install routes.
  See [Three data directories](architecture.md#three-data-directories-and-why-picking-between-them-is-not-the-fix).
- **Running both install routes at once gives you two live copies of every hook**, firing twice per
  event.
- **Nothing migrates or deletes old state.** Historical data directories stay where they are.
- **There is no trip ledger and no governance segment on the status line.** `GM` was removed on
  30 July 2026 because with no ledger it could return exactly one value, and an indicator that can
  report one value reports nothing. The 12 ledger files holding 64 uncleared trips were backed up and
  removed. See [The trip ledger](architecture.md#the-trip-ledger--removed-and-recorded-here-as-a-design).
- **`HH` dim (`HH-`) is not an all-clear.** It means nothing about this session was found to read.
  Green and dim are different facts and the trailing `-` is what separates them.

## The documentation is not checked against the tree

Two automated checks touch prose, and between them they cover very little of it:

- `/lw-watchtower:doctor`'s `commands` check fails on any `/lw-watchtower:<name>` reference anywhere in the repo
  with no `commands/<name>.md` behind it. That catches a signpost to a command that does not exist,
  and nothing else.
- `tests/portability_scan.ps1` fails on a tracked file naming a machine. That catches one laptop's
  facts shipping as universal truth, and nothing else.
- `tests/doc_claims.ps1` fails on a tracked page stating a **checkable quantity** the tree
  contradicts — the number of test files, of behavioural suites, of cases in each of them, of CI
  check steps, of doctor checks, of commands, and of declared and observing modules. It derives every
  one of those from the tree when it runs. That catches a stale count, and **only the phrasings it
  recognises**: a new way of writing "there are five suites" is invisible to it until a pattern is
  added.

**Nothing checks that a sentence in `docs/` is still true**, and adding the guard above did not
change that — it checks *numbers*, not *claims*. No test compares a documented cost, a documented
hook registration, a documented exit code or a documented capability against the tree, and every page
in `docs/` is still maintained by hand. A page can carry every count correctly and describe a plugin
that does not exist; **that is exactly what several of these pages were doing on 31 July 2026**, when
two adversarial UAT passes found this page asserting that no observing module is exercised by
anything four lines under a table showing two of them are.

This repository also removes things at speed: on
30 July 2026 alone it lost both gates and their handlers, two unbuildable placeholder modules, two
test suites, a CI job, the trip ledger with its readers and its files, the `GM` status-line segment
and six slash commands — and gained one gate, one behavioural suite and one command in the same day. <!-- doc-claims:ignore — these are counts of what MOVED on one date, not of what the tree holds now. The point of the sentence is the rate of change; updating the numbers would destroy it. -->
A stale sentence describing a capability that no longer exists is therefore the likeliest defect on
the page you are reading, and the second likeliest is a sentence describing an absence that has since
been filled.

Treat a dated claim as a record of what was true then. The tree is the authority.

## Things that were specified and cannot be built

Five names were on this project's plan and are **not merely unwritten**. Each is recorded rather than
deleted, so nobody re-attempts it without the evidence.

| Name | Why it cannot be built |
| --- | --- |
| `ratelimit_escalation` | `rate_limits` is assembled in exactly one place in the claude-code 2.1.220 binary — the status-line input builder. **No hook event carries it.** The escalation therefore lives in the status line, where the data actually arrives. |
| `cost_tracking` | Same finding for `cost.total_cost_usd` and the line counts. There is no on-disk cache to read instead: the CLI holds them in process memory, `~/.claude.json` has no such keys, and the transcript records tokens but no dollars. |
| the subscription plan name on the status line | **There is no plan name, tier name, entitlement field or account identifier anywhere in the status-line payload**, and no hook payload carries one either. Verified against the status-line reference on 2 September 2026: the payload carries `model.*`, `cost.*`, `context_window.*`, `prompt_cache.*`, `fast_mode`, `effort.level`, `thinking.enabled`, `workspace.*`, `worktree.*`, `pr.*`, `agent.name` and `rate_limits.*` — and nothing of this class. The only proxy that exists is **presence**: `rate_limits` is absent on free and present on Pro/Max, which distinguishes two buckets and does not name a plan, so rendering it as one would be the overstatement this plugin exists to catch. It is filed as an upstream request and closes if the field is added; it is deliberately **not** to be worked around by inference from rate-limit shape, `~/.claude.json`, or any other indirect signal. |
| `ask` | Would need a `Stop` hook refusing to end a turn while an unanswered decision is outstanding. A `Stop` hook can block turn end but **cannot stop prose that has already appeared**, and cannot detect a question that should have been asked and was not. The half that matters is unreachable. |
| `ask_inline` | Would need something that counts and merges the questions asked in a turn. **Nothing can merge them after the fact.** |

The first two were carried as `planned` placeholders until 30 July 2026 and were then removed
from the switchboard, because a name that can never be built is not a plan and carrying it in a
switchboard invites someone to switch it on. The reasoning is at
[Attempted and blocked](modules.md#attempted-and-blocked-ratelimit_escalation-and-cost_tracking) and,
for the interaction pair, in [`config.json`](../lw-watchtower/config.json).

**No amount of work inside this repository unblocks any of them.** What would: a `rate_limits` /
`cost` block added to the hook input upstream, or a release that persists either to disk.

## What a fully green run actually establishes

Everything passing — a clean `/lw-watchtower:doctor`, a green CI run, a green gate suite, a green
portability scan — establishes this and no more:

> The plugin's manifests and hooks are wired correctly and point at files that exist; its module
> switches are keys that really exist; its state directory resolved to a live one and accepted a
> write; the `SessionStart` hook has fired at least once and its self-check passed; every tracked
> JSON and PowerShell file parses; no tracked file names a machine; and `delegate_gate` still refuses
> what it declares.

It establishes nothing about whether any advisory fires, nothing about whether the plugin is enabled
in your current session, and nothing about anything being protected — because, `delegate_gate` aside,
nothing here protects anything.

---

**Related:** [FAQ](faq.md) · [Modules](modules.md) · [Testing and CI](testing.md) ·
[Gates were removed deliberately](gates-removed.md) · [Architecture](architecture.md) ·
[Troubleshooting](troubleshooting.md) · [SECURITY.md](../SECURITY.md)
