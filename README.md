# LW-WATCHTOWER

**A governance layer for Claude Code that refuses to overstate itself.**

**LW** is LEAPWare, the publisher. **Watchtower** is an ordinary English word and expands to nothing
— a tower you watch from, which sees and reports and does not intervene. That is the whole of the
name, said here because the name this replaced (`LW-GMHH`, until 3 August 2026) was an initialism
whose last two letters were never expanded anywhere in the tree, including in its own manifest
description. **A watchtower is not a wall**, and the word was chosen over a candidate that implied
protection for exactly that reason: eight of the eleven modules below can block nothing at all, and
every one of the three that can ships switched off.

LW-WATCHTOWER is a Claude Code plugin that applies one governance layer to every session, in every repo,
without per-project setup. Eight of its eleven modules **observe** and warn and can block nothing. The
other three — `delegate_gate`, `send_liveness_gate` and `completion_audit` — are the only things here
that can refuse anything, and all three ship **switched off**. Two further modules were specified,
found to be impossible — the data they need reaches no
hook — and removed rather than left on the banner as names that could never mean anything. The
reasoning was kept so nobody re-attempts them.

It had two security gates. Both were removed at the owner's instruction — the destructive command
gate and then `secret_scan` — on 30 July 2026, leaving none at all. `delegate_gate` was built later
the same day as the first gate that could be built honestly and completely, and the two supervision
gates followed it. See [Both gates were removed](#both-gates-were-removed) and
[The three gates](#the-three-gates).

That the banner reads `0 gates` and `observe-only` until you arm one of the three, rather than
counting gates that are shipped but disabled, is the point. This project exists because a monitor
that reports healthy while doing nothing is worse than no monitor, and most of its own history is
finding that defect inside itself.

- **Platform:** Windows, Windows PowerShell 5.1. Not portable, and not pretending to be.
- **Licence:** [Apache-2.0](LICENSE)
- **Version:** 0.4.0 — pre-1.0, and **not yet tagged**. This repository has no release tag at all:
  `v0.3.0` was tagged on a predecessor repository whose history this one does not carry, so there is
  no earlier tree to check out here. See [Install](#60-second-quickstart) for what the one install
  route actually gives you.

---

## Who this is for

You, if you run Claude Code on Windows and you want a layer that reports honestly on what a session
is doing — and that will tell you plainly when it has stopped being able to see anything.

**It will not stop `git push --force`, and it will not stop a credential being written to disk.** It
used to do both. See [Both gates were removed](#both-gates-were-removed). What it will stop, once you
ask it to, is *you* doing work on the main thread instead of delegating it, a send to an agent it can
prove is dead, and a turn ending on a completion claim nothing verified — three disciplines, not a
safety net.

Not for you if you need cross-platform support, a linter, or a security boundary. See the next
section.

## What this does NOT do

Read this before anything else. The full list, consolidated in one place and kept there deliberately,
is **[docs/limitations.md](docs/limitations.md)** — this section is the headline of it.

- **It inspects nothing about what a tool would do.** Two `PreToolUse` hooks are registered and
  neither reads the call's intent. `delegate_gate` decides on exactly one thing — whether the call
  came from a subagent — and reads the tool's name only to word its refusal, once the refusal is
  already settled. `send_liveness_gate` reads a `SendMessage`'s recipient, and only to look it up in
  this session's own liveness records; it never reads the message. **No path, no command and no file
  content is ever examined in order to decide anything.** Every other module observes, logs or warns
  after or alongside the fact, and the action happens regardless; one of them,
  [`lw-watchtower/lib/post_edit.ps1`](lw-watchtower/lib/post_edit.ps1), does record the path of a file that was **already**
  edited, so that two turn-end advisories have something to read.
- **It is not a security boundary,** and now not even a speed bump. A credential can be written to
  any file by any route with nothing from this plugin noticing beforehand. `delegate_gate` refuses a
  main-thread write of a credential and permits a subagent's, which is not a security property.
- **It ships no `permissions.deny` rules.** `/lw-watchtower:setup` used to write 181, then 48; it now
  writes none. If you want that layer — and it is the only one that cannot fail open, since the CLI
  evaluates it itself — you write it yourself. Rules already in your `settings.json` are never
  touched or removed by setup.
- **Nothing here can block assistant text.** There is no hook between the model and the transcript.
  Five output styles once asked for a house voice; they were requests and never enforcement, and they
  were removed on 2 September 2026 along with the two commands that recorded the preference. Anyone
  describing a style as enforcing is repeating this project's founding defect.
- **All eleven declared modules are built. Seven are enabled; `orphan_watch` and the three gates are not.**
  `ratelimit_escalation` and `cost_tracking`
  were declared and are *blocked*, not merely unwritten: the data they need reaches no hook, and no
  further work on this plugin will change that, so on 30 July 2026 the placeholders were removed and
  the reasoning kept. See
  [Attempted and blocked](docs/modules.md#attempted-and-blocked-ratelimit_escalation-and-cost_tracking).
- **Eleven suites test behaviour, and a green run of all of them is a narrower claim than the
  totals suggest.** `tests/gate_delegate.ps1` runs 99 cases against `delegate_gate`;
  `tests/supervision.ps1` runs 66 against `send_liveness_gate`, `completion_audit` and
  `orphan_watch`; `tests/stop_behaviour.ps1` runs 120 against the two turn-end hooks and the
  advisory modules behind them; `tests/setup_merge.ps1` runs 203 against the installer's `statusline`
  and `hooks` merge and against the reporting surfaces that have no suite of their own;
  `tests/uninstall_footprint.ps1` runs 38 against the uninstaller's footprint, attribution and
  state-data deletions; `tests/config_behaviour.ps1` runs 56 and `tests/toggle_behaviour.ps1` runs 32
  against the two commands that write `config.override.json`; `tests/state_resolution.ps1` runs 37
  against the state-directory resolver; `tests/doctor_behaviour.ps1` runs 42 against the doctor's
  driven checks; `tests/subagent_scan.ps1` runs 14 against the `SubagentStart` fast path — the only
  coverage `context_injection` has — and `tests/payload_guard.ps1` runs 22 against what the shipped
  payload discloses. They all go through a real pipe or a real child process. **Per-module coverage
  is much thinner than the case totals**: several observing modules are reached by one to three cases
  each, on at most two properties apiece, and `context_injection`'s `worker_facts.md` handling has no
  case at all. Which module is covered by what, and how narrowly, is enumerated in
  [Testing and CI](docs/testing.md) — read the totals here as "these modules are no longer
  untouched", not as "these modules are tested". The 233-case gate suite went with the destructive
  gate and the `permissions.deny` parity test went with `secret_scan`; neither came back, and nothing
  here inspects a command or a credential for one to cover.
- **It does not see shell edits.** `docs_coupling` is fed by `Write`/`Edit`/`NotebookEdit`. A file
  rewritten by a shell command is invisible to it.

## Both gates were removed

Both removals were explicit decisions of the repository owner, on **30 July 2026**, and are recorded
here rather than left to be inferred from an absence.

**`destructive_gate`** went first, in full: the `PreToolUse` hook on `Bash`/`PowerShell` that refused
force pushes, hard resets, `git clean -f`, history rewrites, reflog expiry, recursive deletes and
GitHub repository destruction; the `.git`-internals write rule; the 233-case regression suite; the
command that ran it; and the CI job that ran that. Its four `permissions.deny` groups — 133 of the
installer's 181 rules — went with it.

**`secret_scan`** went second, and it was the last gate. Removed in full: `lib/gate_write.ps1`, its
`PreToolUse` registration on `Write`/`Edit`/`NotebookEdit`, its path rules over `*.pem`, `*.key`,
`id_rsa*`, `.env` and friends, and its scan of written content for live GitHub, AWS and Slack
tokens. Its two `permissions.deny` groups — the remaining 48 rules — went with it, as did
`tests/deny_parity.ps1` and its fixtures.

So the installer's deny table is now **empty**, and **nothing in this plugin inspects a shell
command, a path or a credential, by any route.** Neither gate is coming back.

A machine set up before those dates still carries the old rules in its own `settings.json` and the
CLI still evaluates them; nothing here renews them, and `/lw-watchtower:uninstall` is the only thing that
still knows how to attribute them.

The removed code is recoverable from git history, and **the trip ledger is not**: it and everything
that read it were removed hours after the gates, so anything that wants a durable record of a
refusal has to rebuild the ledger format, its writer, the acknowledge path, the turn-end sweep and
any indicator over them. `delegate_gate` deliberately did not: a denial is written to
`lw-watchtower.jsonl` as a `GateDeny` event and nothing tracks it as an open item.

Before writing a second gate, read
[Gates were removed deliberately](docs/gates-removed.md): it records how four attempts to close a
single hole in the last gate failed, how every added cleverness opened a new hole, and how not one
of them was caught by the test suite.

## The three gates

Three modules are of kind `gate`, meaning each can actually refuse something. **All three ship
switched off**, none of them is a security control, and each is switched by its own key rather than a
`modules` flag — a corrupt config must never arm a blocking gate.

| Gate | Refuses | Switch |
| --- | --- | --- |
| `delegate_gate` | `Edit`, `Write`, `NotebookEdit`, `Bash`, `PowerShell` on the main thread | `interaction.delegate` |
| `send_liveness_gate` | a `SendMessage` whose recipient it can prove is dead mid-flight | `supervision.send_liveness` |
| `completion_audit` | a turn end whose final message claims completed work while the turn's last action was a queued `SendMessage` | `supervision.completion_audit` |

`send_liveness_gate` **abstains** wherever the evidence cannot support a verdict — an unresolvable
recipient it denies, but a session it has no records for it allows and logs. `completion_audit` fires
at most once per turn end, so it forces one round of verification and **cannot force honesty**; its
claim detection is a regex over prose and is stated as such. Both are covered by
`tests/supervision.ps1`. Full detail and blind spots: [Modules](docs/modules.md).

The rest of this section is `delegate_gate`, which is the one an operator is most likely to arm.

`delegate_gate` was built on **30 July 2026**, hours after the two security gates were removed,
because it is the first gate on this project's plan that could be built completely rather than
partially. It is
[`lw-watchtower/lib/gate_delegate.ps1`](lw-watchtower/lib/gate_delegate.ps1), registered as a `PreToolUse` hook on
`Edit|Write|NotebookEdit|Bash|PowerShell`. `PowerShell` joined that matcher on **1 August 2026**:
this is a Windows-only plugin, the CLI offers both shell tools there, and until then an armed gate
could be walked round by asking for the other shell while `/lw-watchtower:doctor` reported it live.

It has one rule and no exceptions to it:

> When `interaction.delegate` is on, refuse those five tools for any call that did **not** come from
> a subagent.

- **It is off by default.** Turn it on with `/lw-watchtower:delegate on`. Until then it refuses nothing,
  the live gate count is `0`, and the mode stays `observe-only`.
- **It really blocks.** A `PreToolUse` deny is honoured even under
  `permissions.defaultMode: "bypassPermissions"`, so for anyone running in that mode this is a
  stronger layer than a `permissions.deny` rule.
- **It decides on the presence of `agent_id`, never `agent_type`.** A `settings.json` `agent` key
  gives the *main thread* a non-empty `agent_type`; a gate matching on that would classify the main
  thread as a subagent and allow every call it exists to refuse.
- **It has no allowlist and makes no safety determination.** It does not read the tool name, the
  path, the command or the content. The matcher in `lw-watchtower/hooks/hooks.json` is the only place the tool
  list lives.
- **Turning it on is close to one-way from the chat session.** `/lw-watchtower:delegate off` runs through
  `Bash`, and `Bash` is one of the five tools refused — so is `PowerShell`, so switching shell is not
  a way round it. There is deliberately no exemption for it — an exemption for "the command that
  turns me off" is a named bypass. Have a **subagent** run the command, or set `interaction.delegate`
  to `false` by hand in `config.override.json` under the state directory — `$CLAUDE_PLUGIN_DATA`, or
  `~/.claude/plugins/data/lw-watchtower*/`. **Not in `config.json`**: that file is the shipped
  defaults, and an edit there changes nothing while the override still says `true`. If no override
  file exists, the gate is off already and there is nothing to turn off.
- **It enforces delegation, not good delegation.** It refuses nothing a subagent does and never
  checks that a dispatch was any good.

## 60-second quickstart

Requires Windows and Windows PowerShell 5.1 (`powershell.exe`). The constraint is the literal binary
name in the thirteen hook registrations in `lw-watchtower/hooks/hooks.json`, not a 5.1 language feature — every tracked
script declares `#requires -version 5`, which PowerShell 7 satisfies, so running one under `pwsh` by
hand is not refused by the interpreter — one was checked and produced byte-identical output, which is
one script and not a guarantee about all of them. The hooks will still invoke `powershell`.

```
/plugin marketplace add LEAPWare-Software/LEAPWare-Watchtower
/plugin install lw-watchtower@leapware-watchtower
```

**This gives you `main`, not a release.** `.claude-plugin/marketplace.json` sources the plugin from
the `lw-watchtower/` subdirectory with no `ref`, `tag` or `branch` key, so the marketplace resolves
the **default branch**, and you get whatever `main` held at the moment you installed. It is not
pinned and no two installs on different days need be the same tree. That is a property of this
install route and no version number can fix it, so it is stated here rather than papered over.

**You can still read which commit you got.** The banner tells you the declared version and nothing
more, but the CLI records the commit it copied and the marketplace's own clone is checked out at it,
so either of these answers the question without a junction install:

```powershell
(Get-Content "$env:USERPROFILE\.claude\plugins\installed_plugins.json" -Raw | ConvertFrom-Json).plugins.'lw-watchtower@leapware-watchtower'[0].gitCommitSha
git -C "$env:USERPROFILE\.claude\plugins\marketplaces\leapware-watchtower" rev-parse HEAD
```

Both printed the same 40-character sha when this was measured, and it was the sha `refs/heads/main`
pointed at. Substitute `$env:CLAUDE_CONFIG_DIR` for `$env:USERPROFILE\.claude` if you have set one.
Knowing which commit you are on is not the same as pinning it — nothing in this repository makes the
marketplace resolve anything but `main` — and *choosing* the commit is still the junction route's
advantage, not this one's.

**This is the only install route, and no route on this page is called tested.** This repository has
no release tag yet. `v0.3.0` was tagged on a predecessor repository whose history this one does not
carry, so there is no earlier tree to check out here and no page tells you to. The first tag this
repository serves will be `v0.4.0`, cut after the acceptance pass recorded in
[CHANGELOG.md](CHANGELOG.md#040--unreleased); this section will say "tested" when someone other than
the maintainer has installed it from the marketplace and reported back, and not before.

Start a new session. You should see:

```
LW-WATCHTOWER v0.4.0 · 7/11 modules enabled (4 off) · 0 gates · observe-only
```

The four that are off are `send_liveness_gate`, `completion_audit`, `orphan_watch` and
`delegate_gate` — all four built, all four shipped switched off, and off is where they are meant to
be. The parenthetical accounts for the remainder rather than warning about it: everything not counted
is named, so the total always adds up.

Then:

```
/lw-watchtower:doctor
```

Checks on the plugin's wiring, in under a second — it prints how many it ran, so no count is
transcribed here to go stale. It is built to be able to fail, and a
non-zero exit is a real finding.

**Expect `VERDICT: NOT healthy` and exit `1` here, on the `statusline` row — that is the state a
first install is genuinely in, not a fault in what you just did.** The status line is a
`settings.json` key that no plugin manifest can carry, so it is installed by a step of its own, and
the doctor is not healthy until you have run it. That step is:

```
/lw-watchtower:setup
```

It asks its questions one at a time and writes nothing you have not agreed to, each section behind
its own diff. Apply the `statusline` section, then run `/lw-watchtower:doctor` again. Run the doctor
*before* starting a session and `state-dir` and `sessionstart` fail beside it; both clear as soon as
a session has written a record, which is what *"start a new session"* above is for. See
[Install § installing the status line](docs/install.md#installing-the-status-line-part-of-the-install-and-a-separate-step)
for what that step writes and how to undo it, and
[Install § confirming it loaded](docs/install.md#confirming-it-loaded) for what each doctor exit code
means.

*Now* that is the whole install. Configuration is optional and lives in one file,
[`lw-watchtower/config.json`](lw-watchtower/config.json).

**Developing on it instead?** Use a directory junction so the clone is live — see
[Install](docs/install.md#option-b--directory-junction-recommended-for-development).

## What is actually running

**Three modules are of kind `gate`, and they are the last three rows.** Every other row observes; none of them can
block anything.

| Module | Kind | Status |
| --- | --- | --- |
| `failure_capture` | observe | implemented — records tool, hook and subagent failures |
| `self_health` | observe | implemented — proves the governance layer itself can still fire |
| `log_rotation` | observe | implemented — caps `health.jsonl` and `lw-watchtower.jsonl`; the per-session files are **not** swept |
| `context_pressure` | observe | implemented — warns before a lossy compaction |
| `docs_coupling` | observe | implemented — flags source changes shipped without docs |
| `git_hygiene` | observe | implemented — branch, commit and push discipline at turn end |
| `context_injection` | observe | implemented — hands every subagent facts current at *dispatch* time |
| `orphan_watch` | observe | implemented — reconciles subagent transcripts against their stop records and reports agents that were spawned, never stopped and have gone silent. **Ships OFF. The verdict is inferred from silence, and that inference has been measured calling a live agent dead** |
| `delegate_gate` | **gate** | implemented — refuses `Edit`/`Write`/`NotebookEdit`/`Bash`/`PowerShell` on the main thread. **Ships OFF.** See [The three gates](#the-three-gates) |
| `send_liveness_gate` | **gate** | implemented — refuses a `SendMessage` whose recipient it can prove is dead mid-flight; abstains wherever the evidence cannot support a verdict. **Ships OFF** |
| `completion_audit` | **gate** | implemented — refuses a turn end whose final message claims completed work while the turn's last tool action was a queued `SendMessage`. Fires at most once per turn end, so it forces one round of verification and **cannot force honesty**. **Ships OFF** |

Full detail, blind spots and tuning: [Modules](docs/modules.md). Two names that were in this table
until 30 July 2026 — `ratelimit_escalation` and `cost_tracking` — are gone from the registry because
they cannot be built; the evidence is kept at
[Attempted and blocked](docs/modules.md#attempted-and-blocked-ratelimit_escalation-and-cost_tracking).

A gate denial used to be recorded in a durable per-session **trip ledger**, read by the status line's
`GM` glyph and by `lw-watchtower:tripped`. **All of that is gone, and `delegate_gate` did not bring it
back.** The two removed gates went first, so nothing could write a trip; the ledger, its readers, the
`GM` segment and the 12 remaining ledger files went hours later by a further explicit owner
decision — the files backed up, not destroyed. A `delegate_gate` denial is written to
`lw-watchtower.jsonl` as a `GateDeny` event and **nothing tracks it as an open item**: nothing records,
reads, closes or acknowledges a trip, and the status line has no governance segment. The `sitrep`
command counted `GateDeny` records as history, and it went on 2 September 2026, so nothing counts
them now either. The design, and what an indicator would have to rebuild, is
preserved at
[The trip ledger](docs/architecture.md#the-trip-ledger--removed-and-recorded-here-as-a-design) and
[Gates were removed deliberately](docs/gates-removed.md).

## Commands

Six slash commands. Claude Code namespaces a plugin's commands with the plugin name and the
prefix **cannot be suppressed**, so they are `/lw-watchtower:…` and nothing shorter.

**Report on governance** — this reads and prints; it changes nothing.

| Command | What it does |
| --- | --- |
| `/lw-watchtower:doctor` | Wiring checks aimed at what is **not** working, counted in its own output, then the module roster — every module with its kind, whether it is enabled and, the only column that reports behaviour, its state. Exits non-zero when it finds something. |

**Lifecycle** — the four that can change your machine all dry-run by default.

| Command | What it does |
| --- | --- |
| `/lw-watchtower:setup` | Guided installer. Detects what is already there, asks in plain language, then writes `statusLine`, hooks and agent roles one section at a time — each behind its own diff and its own yes. Its `permissions.deny` section now writes **nothing**: the rule table is empty. |
| `/lw-watchtower:config` | Module switchboard: turn a governance module on or off, globally or for one repo, after being told exactly what the change does. Needs `-Apply` to write. |
| `/lw-watchtower:update` | Fetches and reports what is new and what would need re-approval. Fast-forward only; merges nothing without `-Apply`. |
| `/lw-watchtower:uninstall` | Reports this plugin's whole footprint and what removing it would take, and names everything it **cannot** remove. Dry run by default. |

**Preferences** — one command, and it is the only one that arms anything. Read
[what it does and does not do](docs/commands.md#lw-watchtowerdelegate-the-one-preference-command-left)
before treating it as a control.

| Command | Default | Enforced | What it does |
| --- | --- | --- | --- |
| `/lw-watchtower:delegate` | off | **yes** | Reserve the chat session for the operator and send all work to subagents. Arms `delegate_gate`, which really refuses `Edit`, `Write`, `NotebookEdit`, `Bash` and `PowerShell` on the main thread. **Read [The three gates](#the-three-gates) before turning it on** — it cannot be turned off again from the main thread. |

**Six commands were removed on 2 September 2026** — `lw-watchtower:status`, folded into the doctor
that already printed the same roster off the same registry; `lw-watchtower:checklist` and
`lw-watchtower:sitrep`, which reported the maintainer's own project on a consumer's machine;
`lw-watchtower:resolve`, which hand-cleared a fault count it could not clear in the case that
mattered; and `lw-watchtower:verbosity` and `lw-watchtower:plain`, which recorded an output-style
preference that nothing applied. [Commands](docs/commands.md) carries the reasoning for each.

`lw-watchtower:ask` and `lw-watchtower:ask-inline` were here until 30 July 2026 and were **removed** by an
explicit owner decision. (Both are written without a leading slash, here and everywhere else, because
`/lw-watchtower:doctor` fails on a `/lw-watchtower:<name>` reference with no command file behind it — a
live-looking reference to a deleted command is a signpost to nothing.) Both had been on by default
since they shipped while enforcing nothing, and **neither can be built**: a `Stop` hook can refuse to
end a turn but cannot stop prose that has already appeared, and cannot detect a question that should
have been asked and was not; nothing can merge questions after they have been asked. The reasoning
is kept in [`lw-watchtower/config.json`](lw-watchtower/config.json) so nobody re-attempts them.

Exit codes and reporting rules: [Commands](docs/commands.md).

## Documentation

| | |
| --- | --- |
| **[Limitations](docs/limitations.md)** | **Everything this plugin does not do, cannot do, or does not check, in one place. Start here** |
| [FAQ](docs/faq.md) | The questions a new user and a returning owner actually have, answered from the tree |
| [Install](docs/install.md) | Requirements, both install routes, the separate status-line install |
| [Configuration](docs/configuration.md) | `lw-watchtower/config.json` and the override beside it, in full |
| [Modules](docs/modules.md) | All eleven, with their blind spots, **the three gates**, and the removal of the two that could not be built |
| [Gates were removed deliberately](docs/gates-removed.md) | The rules a gate has to follow here, **what the trip ledger's removal means a new gate must rebuild**, and what four failed fix attempts taught |
| [Commands](docs/commands.md) | All six slash commands, their exit codes, and which preference commands are enforced |
| [Roles](docs/roles.md) | The six agent roles the plugin ships, and when each is dispatched |
| [Architecture](docs/architecture.md) | Layout, hooks, measured costs, state, failure policy |
| [Testing and CI](docs/testing.md) | **Fourteen files in `tests/`, and eleven of them test behaviour** — what each one covers, and what is uncovered |
| [Portability](docs/portability.md) | The no-local-environment-dependencies mandate, and the scan that enforces it |
| [Troubleshooting](docs/troubleshooting.md) | Symptom-first index |

## Project status

Pre-1.0. The manifests declare `0.4.0`, which **no tag has published yet**. This repository has never
cut a release: `v0.3.0` was tagged on a predecessor repository whose history this one does not carry,
and `v0.4.0` will be the first tag served from here. Two changes on this branch alter how an existing
`config.json` is read, which is why the first number is `0.4.0` and not `0.3.1`. See
[CHANGELOG.md](CHANGELOG.md#040--unreleased) for what those are and what to check in your own config.

`main` never declares a version a tag already published, and
[`tests/doc_claims.ps1`](tests/doc_claims.ps1) fails the build if it does — on a clone that has tag
refs. See [CONTRIBUTING.md](CONTRIBUTING.md#versions-and-releases) for the rule and for the part the
guard cannot see.

CI runs on `windows-latest` under Windows PowerShell 5.1, in **one job with twenty check steps**:
JSON validity, PowerShell parse, the workflow guard, the delegate gate suite, the installer merge
suite, the stop-hook behaviour suite, the uninstaller footprint suite, the doctor behaviour suite,
the toggle write-path suite, the `SubagentStart` fast-scan suite, the payload disclosure guard, the
supervision suite, the config write-path suite, the state resolution suite, the portability scan, the
documentation-claim guard, the pull-request issue-reference guard, the commit-identity guard, the
red-first annotation guard, and the version-declaration guard. The `gate-regression` job and the
233-case suite behind it were deleted on 30 July 2026 with the destructive command gate; the
`permissions.deny` parity step and `tests/deny_parity.ps1` went the same day with `secret_scan`.
**A green CI run says tracked files parse, name no machine, that no workflow reaches a runner GitHub
does not host or grants itself more than read, that `delegate_gate` still refuses what it declares,
that the two supervision gates deny and abstain where they say they do, that the installer's
`statusline` merge still preserves what it was not asked to touch, that the pinned turn-end cases
still behave for the observing modules `tests/stop_behaviour.ps1` reaches, that the uninstaller
deletes exactly the state data it listed, that the two config writers touch only the override, that
no page here states a count the tree contradicts, that the five version declarations agree with each
other, and that no pull request arrived without an issue reference. For several observing modules it
is evidence about at most two properties apiece and no more, and for the ones no suite reaches it is
evidence about nothing at all.** See [Testing and CI](docs/testing.md).

If branch protection on `main` still requires the `gate-regression` context, it has to be removed —
that job can never report again. `fast-checks` is not the replacement: that is the YAML job id, and a
required status check is matched by the check run's **name**, so requiring the id blocks every merge
for the same reason. The one requirable string is the surviving job's display name, quoted verbatim in
[Testing § Branch protection](docs/testing.md#branch-protection). It is not repeated here on purpose:
that page is held to the string by the documentation-claim guard, which derives it from `ci.yml`, and
this page is not.

There is no status badge here, deliberately: a green badge covering three gates and eight observing
modules would read as far broader assurance than it is. A second reason stood here until
**2026-08-28** — that a badge would not render for most viewers of a repository they cannot read —
and it went with the visibility flip on that date. It is recorded rather than quietly dropped,
because the surviving objection is the one that was always the real one, and a badge is a decision
that would still have to answer it.

## Support

Questions go to [Discussions › Q&A](https://github.com/LEAPWare-Software/LEAPWare-Watchtower/discussions/categories/q-a),
bugs and feature requests through the
[issue forms](https://github.com/LEAPWare-Software/LEAPWare-Watchtower/issues/new/choose), and
vulnerabilities through [SECURITY.md](SECURITY.md) — never through a public issue. **A human replies
within five working days; a reply is not a promise of a fix.**
[SUPPORT.md](SUPPORT.md) says what to include so the first reply is a useful one.

## Contributing

Bug reports, questions and feature requests are welcome; code is by invitation — open an issue before
a pull request. Read [CONTRIBUTING.md](CONTRIBUTING.md) first — in particular the three rules it puts
above the rest. Two of them fail the build outright and the first one is only partly checked, which
is a distinction worth carrying away:

- **A regression test must fail before the fix.** *Held by review, and only its bookkeeping is
  enforced.* `.github/scripts/redfirst_annotations.ps1` runs in CI and holds the **shape** of a
  red-first annotation — a claimed baseline has to name a commit, and a case id it names has to be a
  case that suite declares — but no clone here can reach the baseline to re-run it, so an annotation
  that cites a real commit against a case which could never have failed there passes. This project's
  suite was 67/67 green while five gate bypasses were open, which is the whole reason the rule is
  written down. It applies to `tests/gate_delegate.ps1` exactly as it applied to the suite that
  taught it: every case there was confirmed to fail against a deliberately broken gate before it was
  kept.
- **No local environment dependencies.** *CI fails the build on a hit.* No account name, computer
  name, profile path or absolute interpreter path in a tracked file. `tests/portability_scan.ps1`
  scans every tracked file in CI — because one laptop's private facts have shipped as universal truth
  three times, including a status line that rendered *not installed* forever on every other machine.
  The mandate is [docs/portability.md](docs/portability.md).
- **No self-hosted runner, no `pull_request_target`, no secrets, and no `permissions:` grant wider
  than read in any workflow.** *CI fails the build on a hit.* `tests/workflow_guard.ps1` parses every
  workflow file rather than grepping it — the check it replaced could be satisfied by a comment. This
  is the one whose failure mode is **somebody else's machine rather than your build**: a self-hosted
  runner reachable from a public repository hands a stranger code execution on the maintainer's
  hardware.

Three further rules on that page are enforced by CI too, and a contributor meets them before a
reviewer does: a pull request body must carry an issue reference, every commit must come from an
identity on the allowlist, and the five version-declaration sites must agree with each other.

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

**No gate here is a security control and a way past one is not a vulnerability.** `delegate_gate`
refuses main-thread work as a discipline and a subagent can do anything it refuses, by design; the
two supervision gates hold a reporting discipline and abstain wherever the evidence cannot support a
verdict. What is a security report rather than a bug report is a credential leaking through this
plugin's own logs, or the plugin damaging your `settings.json`. See [SECURITY.md](SECURITY.md).

## Licence

Apache-2.0. See [LICENSE](LICENSE).
