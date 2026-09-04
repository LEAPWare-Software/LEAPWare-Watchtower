# FAQ

Answers checked against this tree, not recalled. Where something is unverified, it says so rather
than guessing.

If you are here to find out what this plugin **cannot** do, the consolidated answer is
[Limitations](limitations.md), and it is the more important page.

---

## Contents

**What it is**

- [What does this actually do?](#what-does-this-actually-do)
- [Does it block anything?](#does-it-block-anything)
- [Is this a security tool?](#is-this-a-security-tool)
- [Why were the gates removed?](#why-were-the-gates-removed)
- [Why does the banner say some modules are off, and `observe-only`? Is something broken?](#why-does-the-banner-say-some-modules-are-off-and-observe-only-is-something-broken)

**Installing and running it**

- [How do I install it on a second laptop?](#how-do-i-install-it-on-a-second-laptop)
- [Does it run on macOS or Linux? Does `pwsh` work?](#does-it-run-on-macos-or-linux-does-pwsh-work)
- [Why is the doctor warning about the status line?](#why-is-the-doctor-warning-about-the-status-line)
- [Why does the plugin add latency?](#why-does-the-plugin-add-latency)
- [How do I uninstall it?](#how-do-i-uninstall-it)

**Using it**

- [How do I turn a module off?](#how-do-i-turn-a-module-off)
- [I turned `delegate` on and now I cannot turn it off](#i-turned-delegate-on-and-now-i-cannot-turn-it-off)
- [What is a trip, and why can I not see any?](#what-is-a-trip-and-why-can-i-not-see-any)
- [An advisory warned me and it was wrong](#an-advisory-warned-me-and-it-was-wrong)
- [Does it see files changed by a shell command?](#does-it-see-files-changed-by-a-shell-command)
- [Where does it write its state?](#where-does-it-write-its-state)

**The plan and the tests**

- [Can I run the tests myself?](#can-i-run-the-tests-myself)
- [Why is there no CI badge in the README?](#why-is-there-no-ci-badge-in-the-readme)
- [What version is this? Is there a release?](#what-version-is-this-is-there-a-release)
- [Why do the commands all start with `/lw-watchtower:`?](#why-do-the-commands-all-start-with-lw-watchtower)
- [I found a way past `delegate_gate`. Is that a security report?](#i-found-a-way-past-delegate_gate-is-that-a-security-report)

---

## What does this actually do?

It runs ten governance modules over every Claude Code session on the machine, in every repo, with no
per-project setup. **Nine of them observe** — they record, count or warn — and **one, `delegate_gate`,
can refuse a tool call, and ships switched off.**

Concretely, as shipped:

- **At session start** it prints a banner naming what is active and what is not, and runs a
  five-probe self-check that asserts real returned values rather than that files exist. If a probe
  fails the session reports `degraded`; if `self_health` is off it reports `unverified`, which is a
  separate word from any that implies a pass.
- **On every subagent dispatch** it injects the current bytes of
  [`context/worker_facts.md`](../lw-watchtower/context/worker_facts.md) into the worker's context — because Claude
  Code snapshots `CLAUDE.md` at *parent-session* start, so an instruction added mid-session never
  reaches a worker dispatched later.
- **On every `Write`/`Edit`/`NotebookEdit`** it records the path, for two turn-end advisories.
- **At every turn end** it runs five advisories in one process: context-window pressure, whether work
  was shipped without an independent verifier, whether source changed without docs, git branch/commit/push
  hygiene, and whether the session has wandered off the task. All five warn; none blocks.
- **On five hook events** it records failures to `health.jsonl`, and on a genuine failure it exits 2,
  which injects a task notification into the live session. That exit code is the only channel that
  reaches an orchestrator mid-turn.
- **Twelve slash commands** report on governance, report on the plan, or manage the install. Four of
  the lifecycle ones dry-run by default.

What it does **not** do is a longer and more important list: [Limitations](limitations.md).

## Does it block anything?

**Almost nothing, and by default nothing at all.**

There is exactly one hook in this plugin with a blocking channel: `delegate_gate`, a `PreToolUse`
hook on `Edit|Write|NotebookEdit|Bash|PowerShell`. Its one rule is *when `interaction.delegate` is on, refuse
those five tools for any call that did not come from a subagent*. It ships with that switch **off**,
so the live gate count is `0` and a healthy session reads `observe-only`.

It reads no path, no command and no file content, and nothing it decides consults the tool name — it
reads that only to name the refused tool in the denial text, after the decision. So:

- a destructive shell command — **not inspected**
- a write to a credential file, or a write whose bytes are a credential — **not inspected**
- a write inside `.git/` — **not refused**
- `permissions.deny` rules installed — **none**

That is the state since 30 July 2026 and it is deliberate. See
[Both gates were removed](modules.md#both-gates-were-removed).

## Is this a security tool?

**No.** It is not a security boundary and, since the gates went, not even a speed bump for the things
a security boundary would cover.

`delegate_gate` is a **discipline**, not a control: it refuses main-thread work so the chat session
stays reserved for talking to you, and a subagent can do everything it refuses, by design. Refusing a
main-thread write of a credential while permitting a subagent's is not a security property.

If you want a layer that cannot fail open, write `permissions.deny` rules in your own
`settings.json`. The CLI evaluates those itself, before and regardless of any hook. This plugin will
not write them for you, and setup never removes ones you wrote.

What *is* still a security report here: a credential leaking through this plugin's own log records,
or the plugin damaging your `settings.json`. See [SECURITY.md](../SECURITY.md).

## Why were the gates removed?

Both removals — `destructive_gate` first, then `secret_scan` — were explicit decisions of the
repository owner on 30 July 2026. This repository does not claim they were forced by the evidence.

What the evidence *does* say, and it is kept in full at
[Gates were removed deliberately](gates-removed.md):

- **Four attempts were made to fix one hole** in the destructive gate — a here-document body walked as
  ordinary shell source, so a stray quote swallowed everything after it and the gate allowed the
  command that followed. Confirmed against real bash, not theorised.
- **Two of the four were reverted, having opened five new bypasses between them.** All five came from
  the same kind of change: a decision that some input was safe *not* to scan. The isolation logic all
  four shared opened none.
- **The test suite never caught a single bypass.** It was 67 of 67 green while five were open. Every
  hole in the record was found by somebody deliberately trying to break the gate.

The conclusion written down at the time — *a gate with a green suite and no independent break-attempt
should be assumed broken* — is why `tests/gate_delegate.ps1` being 93 of 93 green is stated carefully
everywhere rather than shrugged at.

A gate *can* come back; the owner intends blocking capability to be re-addable. What a new one has to
rebuild first is at
[The trip ledger was NOT kept](gates-removed.md#the-trip-ledger-was-not-kept--a-gate-has-to-rebuild-it),
and the rules it has to follow at
[What a future attempt must do differently](gates-removed.md#what-a-future-attempt-must-do-differently).

## Why does the banner say some modules are off, and `observe-only`? Is something broken?

No. That is the correct shipped state and it is what the banner is for. As shipped it reads:

```
LW-WATCHTOWER v0.4.0 · 7/11 modules enabled (4 off) · 0 gates · observe-only
```

- **`7/11`** — eleven modules are built; seven are enabled. The four that are off are
  `send_liveness_gate`, `completion_audit`, `orphan_watch` and `delegate_gate` — all four built, all
  four shipped switched off. The parenthetical is the remainder being accounted for rather than a
  warning: everything not counted is named, so the total always adds up.
- **`0 gates`** — that number counts gates that are **live**, not gates that ship. Three ship.
  Counting a switched-off capability as a gate would claim protection that is not running.
- **`observe-only`** — no live gate, so nothing can be blocked. The mode ladder tests the live gate
  count **before** it tests whether any module is switched off, because "nothing can be blocked" is a
  larger fact than "some module is off".

Turning an observing module off does not change the mode word. Running `/lw-watchtower:delegate on` does:
the mode becomes `partial`, and `enforcing` only once every implemented module is on as well. Every
mode word is defined at [Session modes](modules.md#session-modes).

## How do I install it on a second laptop?

Pick **one** route. Running both gives you two live copies of every hook, firing twice per event.

**Route A — marketplace** (what you want on a machine you are not developing on):

```
/plugin marketplace add LEAPWare-Software/LEAPWare-Watchtower
/plugin install lw-watchtower@leapware-watchtower
```

This *copies* the plugin root into an internal cache, so an edit to a clone does nothing until
`claude plugin update`.

**Route B — directory junction** (what you want if you are editing the plugin). Any folder under a
skills directory containing `.claude-plugin/plugin.json` is auto-discovered on the next session; a
junction needs no administrator rights and keeps the clone live. The exact commands, with a `$Repo`
variable you set once, are at
[Install § option B](install.md#option-b--directory-junction-recommended-for-development).

Then, on the new machine:

1. **Start a session.** The harness creates the state directory on first load. Until it has, the
   doctor's `state-dir` check can legitimately report UNRESOLVED.
2. **Run `/lw-watchtower:doctor`.** Sub-second wiring checks — it prints how many it ran — and a non-zero
   exit is a real finding, not a glitch.
3. **Install the status line separately if you want it.** It is *not* part of the plugin — `statusLine`
   is a top-level `settings.json` key and a plugin has no manifest field for it. You copy
   [`statusline/statusline.ps1`](../lw-watchtower/statusline/statusline.ps1) into your profile and wire the key by
   hand. See [Install § status line](install.md#installing-the-status-line-optional-and-separate).

Three things that will **not** carry over, stated so they are not a surprise:

- **No `permissions.deny` rules are installed.** If your first laptop was set up before 30 July 2026
  it still carries 181 rules the installer wrote back then; the new one gets none, and nothing here
  renews or copies them. The two machines will behave differently and nothing in the plugin will say
  so.
- **The status-line copy drifts silently** from the tracked original, in both directions. The doctor
  detects it; nothing prevents it.

## Does it run on macOS or Linux? Does `pwsh` work?

**No to both.**

Every hook is registered as `powershell -NoProfile -ExecutionPolicy Bypass -File …`, which is
**Windows PowerShell 5.1** specifically. `pwsh` is a different binary under a different name and is
not a substitute — `tests/portability_scan.ps1` needs a binary literally named `powershell`, and
`.github/workflows/ci.yml` runs on `windows-latest` under 5.1 with no OS matrix.

Beyond the interpreter, the path classification handles NTFS paths including 8.3 short names, and the
installer and status line are written against Windows profile layout. This is stated as a limitation
rather than a roadmap item: there is no cross-platform plan.

## Why is the doctor warning about the status line?

Almost always this exact message:

```
[WARN] statusline  wired to <path>, but it DIFFERS from statusline/statusline.ps1 in this repo -
                   the installed copy is stale or locally modified; re-copy it to make the repo's
                   version live
```

**That warning is the doctor working, not failing.** The status line is a *copy*. The plugin is loaded
through a junction so the clone and the loaded code are the same bytes by construction; the status
line is not — the tracked file and the one in your profile are two independent files, and nothing
keeps them in step. The doctor hashes both and says when they differ.

Fix it by re-copying **in whichever direction is correct** — and check which that is before you do,
because the case that costs most is a fix made to the live file and then overwritten by the repo
copy. Compare them first:

```powershell
Get-FileHash "$env:USERPROFILE\.claude\statusline.ps1", ".\lw-watchtower\statusline\statusline.ps1" |
    Select-Object Hash, Path
```

The other `statusline` outcomes mean different things: **FAIL** means there is no `statusLine.command`
at all, or it points at a file that does not exist — configured and broken, which renders as no
segments. A **WARN** saying the command names no `.ps1` it could identify means the target was not
verified, not that it is wrong.

One legitimate cause of a difference: if your copy still renders a `GM` segment, it predates 30 July
2026. `GM` was removed — see [What is a trip](#what-is-a-trip-and-why-can-i-not-see-any).

A non-zero exit from the doctor is expected here. Exit `2` means warnings only; exit `1` means a real
failure; exit `3` means the doctor itself could not complete, which is deliberately a different code
from "I found a fault".

## Why does the plugin add latency?

Because every hook is a fresh Windows PowerShell 5.1 process, and **the interpreter floor is most of
the cost**. A bare `exit 0` script measured 283 ms on the development machine — before any of this
plugin's code runs at all.

Measured figures, all one machine's medians rather than constants:

| Path | Cost |
| --- | --- |
| `delegate_gate`, before every `Edit`/`Write`/`NotebookEdit`/`Bash`/`PowerShell`, **on or off** | ~436 ms with the switch off — ~142 ms of its own work above a 294 ms floor. It was ~652 ms until a fast path landed on 31 July 2026. With the switch **on** it is ~868 ms, slower than before, and that cost falls on the operator who armed it — see [`delegate_gate`](modules.md#delegate_gate) for the full table |
| Turn end (`Stop` advisories) | ~1 212 ms median, against a 283 ms floor |
| Subagent dispatch (`context_injection`) | ~437 ms, against a 248 ms floor |

Three things worth knowing:

- **The two `Stop` hooks run in parallel**, verified by sampling the OS process table, so turn end
  costs the max and not the sum. That measurement is also why they were *not* merged: the supervisor
  signals a failure by exiting 2, and the CLI ignores a hook's stdout on exit 2, so a merged process
  could raise the alert or print the advisory but never both.
- **The remaining ~930 ms above the floor at turn end is engine warm-up, not data work.**
  `ConvertFrom-Json`'s first call in a fresh process costs 141–182 ms and every later call costs
  0.4 ms; dot-sourcing `lib/common.ps1` costs 76–104 ms. A cheaper JSON route was looked for and does
  not exist on this platform. That is also why five advisories share one process rather than five.
- **You pay for `delegate_gate` whether or not you use it**, because a hook registration cannot be
  made conditional. Deleting its `PreToolUse` entry from [`hooks/hooks.json`](../lw-watchtower/hooks/hooks.json)
  removes the cost and the ability to ever turn the gate on.

What you *can* switch off cheaply: `module_config.git_hygiene.use_gh` removes the one network call
(~980 ms worst case, capped and killed on expiry, at most once per branch head per session). Full
breakdown: [Turn-end cost](architecture.md#turn-end-cost).

## How do I uninstall it?

`/lw-watchtower:uninstall` is a **dry run by default**, and the dry run is the point: it reports the whole
footprint — plugin root, data directories, the copied status line, the settings keys it was installed
into — and **names everything it cannot remove**.

By hand:

- Marketplace install: `/plugin uninstall lw-watchtower@leapware-watchtower`.
- Junction install: delete the junction under your skills directory. Removing the link does not
  remove the clone.
- Status line: remove the `statusLine` key from your `settings.json`, and delete the copied script.
- State: it lives in `$CLAUDE_PLUGIN_DATA`, never in the repo. Nothing here deletes it for you.
- **`permissions.deny` rules from an install before 30 July 2026** stay in your `settings.json`.
  `/lw-watchtower:uninstall` is the only code left that knows what those 181 rules looked like well enough
  to attribute them.

## How do I turn a module off?

`/lw-watchtower:config`. It is run **twice**: once to see the exact diff and what the change does to your
coverage, once with `-Apply` to write it.

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/bin/lwg-config.ps1" -Module <name> -Off
```

then the identical command with `-Apply` appended. Scope it to one repository with `-ThisRepo` or
`-Repo <owner/name>`, and drop an override with `-Clear -Repo <owner/name>`.

Or write the flag into the `modules` block of `config.override.json` under the state directory by
hand. Editing `config.json` works too and is honoured where no override overrides it, but it dirties
the plugin's git checkout and stops `/lw-watchtower:update` pulling, which is what the override exists
to avoid.

Four things the command will tell you and that are easy to miss:

- **A flag lands on the next hook event, but the banner, the mode word and the status line keep
  reporting the old picture until a new session starts.** Turning something off and seeing the old
  banner is not a failed command.
- **It refuses a name that is not in the registry** in `lib/common.ps1`, rather than writing it. A
  flag with no registry entry is a switch wired to nothing.
- **`delegate_gate` is not switchable from here, deliberately.** Its switch is `interaction.delegate`,
  which is not a `modules` key, and `/lw-watchtower:delegate` is the only thing that writes it. One gate,
  one switch — two flags over one gate would let you turn it on and have it silently do nothing.
- **Exit `2` is a fault, not a caveat.** It means the file was written and the effective value is
  still not what you asked for.

## I turned `delegate` on and now I cannot turn it off

Expected, and documented before you turned it on. `/lw-watchtower:delegate off` runs its script through
`Bash`, and `Bash` is one of the five tools the gate refuses on the main thread — and so is `PowerShell`. There is
**deliberately no exemption for it** — an exemption for "the command that turns me off" is a named
bypass, and this repository's history with named exemptions is the reason there is not one.

Two ways back:

1. Have a **subagent** run `/lw-watchtower:delegate off`.
2. Set `interaction.delegate` to `false` by hand in `config.override.json` under the state
   directory — `$CLAUDE_PLUGIN_DATA`, or `~/.claude/plugins/data/lw-watchtower*/`. **Not in
   `config.json`**: that file is the shipped defaults, and an edit there changes nothing while the
   override still says `true`. If no override file exists, the gate is off already and there is
   nothing to turn off. If the gate is also refusing the edit, do that from outside the session.

The deny message states both. If a per-repo override under `repos[slug].interaction.delegate` set it,
that is the key to clear rather than the global one.

## What is a trip, and why can I not see any?

A **trip** was a durable, per-session record that a gate had refused something — written on the deny
path, closed at turn end only when the plugin could verify a fact about the world, acknowledgeable by
hand when there was no fact to close on, and surfaced by a `GM` segment on the status line.

**None of that exists.** It was all removed on 30 July 2026:

- Both gates went first, so nothing could write a trip.
- Hours later, by a further explicit owner decision, the ledger itself went: `lib/trips.ps1`, the
  acknowledge path, the `tripped` command, the `GM` status-line segment, the ledger-open branch at
  `SessionStart` and the turn-end sweep. The 12 `trips-<sessionkey>.json` files in the state
  directory, holding 64 uncleared trips between them, were **backed up and then removed** — backed
  up, not destroyed.
- `GM` was deleted rather than left as decoration, because with no ledger it could only ever return
  one value, and an indicator that can report exactly one value reports nothing.

**`delegate_gate` did not bring it back.** When it denies, it writes a `GateDeny` event to
`lw-watchtower.jsonl` and **nothing tracks it as an open item**: nothing records, reads, closes or
acknowledges a trip. The command that once counted `GateDeny` records under a `GOVERNANCE` heading
went on 2 September 2026, so nothing counts them now and nothing can clear one — that is an audit
trail, not a ledger, which is exactly why the ledger was built in the first place.

If your status line still shows a `GM` segment, you are running a copy of `statusline/statusline.ps1`
older than the one in this repo. The design, and what a future gate would have to rebuild, is kept at
[The trip ledger](architecture.md#the-trip-ledger--removed-and-recorded-here-as-a-design).

## An advisory warned me and it was wrong

Then say so and turn it off. That is the documented response, not a workaround.

Each advisory has a known false-positive class, all listed at
[the per-module caveats in Modules](modules.md). The common
ones:

- **`docs_coupling`** — it classifies a path by extension, directory segment and stem against a
  configurable word list, which is not an analysis. Tune the lists under
  `module_config.docs_coupling`, or switch the module off. **Tested is not validated** — the cases
  pin that the code does what it is documented to do, never that being warned by it is right — so a
  wrong warning is still worth reporting, and there is a suite to report it against.
- **`git_hygiene` says UNKNOWN** — that is not a false positive. It means git was missing, timed out
  or exited nonzero. **Do not read it as a clean tree.** Raise `timeout_ms` or check by hand.
- **`context_pressure` shows no percentage** — deliberate. The computed occupancy exceeded the
  resolved window, which makes the figure arithmetically impossible, so the module suppresses it
  rather than print a false `100% CRITICAL`. Add your model to
  `module_config.context_pressure.window_tokens`.

An advisory fires **on a change, not on a state**, so a condition that stays true does not repeat at
every turn end. If one seems never to fire again, its dedupe position is stored in
`advisory-<session>.json` in the state dir and clears when the condition clears.

**Two conditions are exempt, and deliberately so:** `git_hygiene`'s `query-failed` and
`gh-unavailable` repeat at **every** turn end while they hold. They describe the *observation*, not
the tree, and silence from that module is documented to mean *git said there is nothing wrong* — so
announcing a git that never answers once and then going quiet would say the opposite of what
happened. See [`git_hygiene`](modules.md#git_hygiene).

## Does it see files changed by a shell command?

**No.** `docs_coupling` is fed by `lib/post_edit.ps1`, a `PostToolUse` hook
on `Write|Edit|NotebookEdit`. A file rewritten by a shell command never reaches that hook and is
invisible to it.

That is a real blind spot, not a bug: a `PostToolUse` hook on `Bash` would receive the command string,
not the set of files it touched.

## Where does it write its state?

In `$CLAUDE_PLUGIN_DATA`, under `~/.claude/plugins/data/`. **Nothing is ever written into the plugin
root** — it is a git working tree and writing there would dirty the repo.

The directory name is `<plugin-name>-<source-id>`, so a junction install writes to
`lw-watchtower-skills-dir` and a `--plugin-dir` session to `lw-watchtower-inline`. A **bare** `lw-watchtower` directory
is not a name Claude Code produces; if resolution lands there, that is reported as unresolved rather
than used silently. `/lw-watchtower:doctor`'s `state-dir` check prints the resolved path, its source, and
whether a write probe succeeded.

What is in there: `lw-watchtower.jsonl` (the append-only event log), `health.jsonl` (failures), and
per-session `advisory-*.json` and `edits-*.txt` files, plus a cross-session `context_windows.json`
and `signals/ratelimit.json` — the last written by the **status line** rather than by a hook, because
it is the only process the CLI hands rate-limit data to. Both `.jsonl` files roll at 5 MB carrying
their last 500 records forward. Full table: [State directory](architecture.md#state-directory).

**Two install routes mean two data directories, and state written under one is invisible to a session
resolving the other.** No rule inside the resolution code can fix that; the durable fix is to install
once.

**The 3 August 2026 rename moved this directory, and nothing migrates it.** The product was
`lw-gmhh` until then, so the data directory was `lw-gmhh*` and the event log was `lw-gmhh.jsonl`.
Because the directory name comes from the plugin id, renaming the plugin renamed the directory —
`lw-watchtower*` from that day on. **No data was deleted and none was moved.** The old directory
still holds everything it held; nothing in this plugin reads it any more, so history in it does not
appear on the status line, and the counts start again from zero.
`/lw-watchtower:uninstall` is the one component that still knows the old name: it sweeps for it,
reports what it finds marked `LEGACY`, and — like every other data directory — leaves it alone
unless you pass `-RemoveData` with the confirmation token. See `## [0.4.0]` in
[CHANGELOG.md](../CHANGELOG.md).


## Can I run the tests myself?

Yes. All 14, from the repo root — the same 14 CI runs:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\gate_delegate.ps1        # the delegate gate
powershell -NoProfile -ExecutionPolicy Bypass -File tests\supervision.ps1          # the other two gates and orphan_watch
powershell -NoProfile -ExecutionPolicy Bypass -File tests\setup_merge.ps1          # the installer's statusline + hooks merge, and the status line
powershell -NoProfile -ExecutionPolicy Bypass -File tests\stop_behaviour.ps1       # the turn-end hooks
powershell -NoProfile -ExecutionPolicy Bypass -File tests\state_resolution.ps1     # the SessionStart hook and its state-dir resolution
powershell -NoProfile -ExecutionPolicy Bypass -File tests\uninstall_footprint.ps1  # the uninstaller's deletions
powershell -NoProfile -ExecutionPolicy Bypass -File tests\doctor_behaviour.ps1     # two of the doctor's ten checks
powershell -NoProfile -ExecutionPolicy Bypass -File tests\config_behaviour.ps1     # the switchboard's write to config.override.json
powershell -NoProfile -ExecutionPolicy Bypass -File tests\toggle_behaviour.ps1     # the toggle's write to config.override.json
powershell -NoProfile -ExecutionPolicy Bypass -File tests\subagent_scan.ps1        # the SubagentStart fast path
powershell -NoProfile -ExecutionPolicy Bypass -File tests\payload_guard.ps1        # the shipped payload, and the tree around it
powershell -NoProfile -ExecutionPolicy Bypass -File tests\workflow_guard.ps1       # every workflow file
powershell -NoProfile -ExecutionPolicy Bypass -File tests\portability_scan.ps1     # every tracked file
powershell -NoProfile -ExecutionPolicy Bypass -File tests\doc_claims.ps1           # every tracked page's counts
```

**The first 11 tally cases; 10 of them drive this plugin's code.** Each of those spawns a
child PowerShell process per case, through a real
pipe, because a PowerShell object pipe never reaches `[Console]::In`, which is where a hook reads its
payload. Nothing real is touched: every case builds a throwaway tree under the temp directory, and no
case constructs a destructive command even as a string it never runs. `tests\payload_guard.ps1` is
the odd one — it reads tracked files rather than running anything, but it reports
cases, so the documentation guard classifies it as behavioural.

**The last three take seconds and assert nothing about behaviour.** Two scan the contents of tracked
files; the third checks that the counts written in the documentation still match the tree, and it
re-runs the other suites in parallel to derive them rather than trusting a number typed
into it.

All 14 share one exit contract: `0` all passed, `1` at least one failed, `2` aborted — **and zero
cases run is an abort, never a pass**.

**What a green run of all of them does not mean:** that any observing module is *validated*. Each is
exercised only in the cases somebody thought to write, and for several of them that is one to three
cases on at most two properties. Read
[Testing § what is not covered](testing.md#what-is-not-covered) rather than trusting a count here.

## Why is there no CI badge in the README?

One reason now, and it is the one that was always the real one: a green badge covering suites this
thin would read as far broader assurance than it is — the exact overstatement this project exists to
avoid.

A second reason stood here until **2026-08-28** — that a badge would not render for most viewers of a
repository they cannot read — and the visibility flip on that date retired it. It is recorded rather
than quietly dropped, because a reader who remembers two reasons should be told which one went.

## What version is this? Is there a release?

The manifests declare **0.4.0**, and **no tag carries that number**. It is pre-1.0, and this
repository has **no release tag at all**: `v0.3.0` was tagged on a predecessor repository whose
history this one does not carry, so it is not served here. `v0.4.0` will be the first tag this
repository publishes.

**That gap is deliberate, and it is a rule rather than an oversight.** `main` must never declare a
version a tag has already published, because while the two carry the same number the version cannot
tell a tagged tree from the branch — and this project shipped exactly that for twelve commits, two
of which changed how an existing `config.json` is read. See
[CONTRIBUTING.md](../CONTRIBUTING.md#versions-and-releases) for the rule and
[CHANGELOG.md](../CHANGELOG.md#040--unreleased) for what changed.

**So the declared version does not identify the tree you are running**, and cannot until 0.4.0 is
tagged. It names the release *line*. The commit does the identifying: `git rev-parse --short HEAD`
in a clone. The documented marketplace install resolves the **default branch**, so it gives you
`main` rather than any release — see [Install](install.md#which-tree-this-actually-gives-you).

## Why do the commands all start with `/lw-watchtower:`?

Claude Code namespaces a plugin's commands with the plugin name and **the prefix cannot be
suppressed**. So they are `/lw-watchtower:doctor`, `/lw-watchtower:config` and so on, and nothing shorter.

You may notice that removed commands are written in this documentation **without** a leading slash —
`lw-watchtower:tripped`, and the verify command that went with the destructive gate. That is not a typo:
`/lw-watchtower:doctor`'s `commands` check **fails** on any `/lw-watchtower:<name>` reference anywhere in the repo
with no `commands/<name>.md` behind it, and a live-looking reference to a deleted command is a
signpost to nothing. (CI **does** run the doctor — `tests/doc_claims.ps1` runs it on every push and
every pull request and aborts the build with exit 2 if it cannot read the doctor's header — but it
runs it against *this repository's* tree on a runner, which says nothing about **your** install, so
this is still a check you have to run.) Both halves of it are enumerated from what is on disk rather
than from a list in the script, because a hardcoded list cannot notice a name nobody thought to add
to it — which is exactly
how the original gap survived: the old check walked three names by hand and reported 3/3 while a
command referenced five times across the repo existed nowhere.

## I found a way past `delegate_gate`. Is that a security report?

**No.** `delegate_gate` is not a security control and a way past it is not a vulnerability. It refuses
main-thread work as a discipline; **a subagent can do everything it refuses, by design.**

Likewise, an action this plugin does not refuse is the documented state, not a gap to file: nothing
inspects a shell command, a path or a credential, and the installer writes no `permissions.deny`
rule. See [Something was NOT blocked](troubleshooting.md#something-was-not-blocked-and-i-think-it-should-have-been).

What **is** worth reporting:

- **A `delegate_gate` that fails open** — permitting a main-thread call while the switch is on. That
  is an ordinary bug; open an issue with the payload shape that did it. Note that exit `1` from a
  `PreToolUse` hook does not block and the tool runs anyway, so a silent fail-open looks exactly like
  nothing happening.
- **A credential reaching a log record unredacted**, or the plugin damaging your `settings.json`.
  Those go to [SECURITY.md](../SECURITY.md), not to a public issue.

---

**Related:** [Limitations](limitations.md) · [Troubleshooting](troubleshooting.md) ·
[Commands](commands.md) · [Install](install.md) · [Configuration](configuration.md) ·
[Modules](modules.md)
