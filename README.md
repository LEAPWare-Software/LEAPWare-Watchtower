# LW-WATCHTOWER

**A governance layer for Claude Code that refuses to overstate itself.**

**LW** is LEAPWare, the publisher. **Watchtower** is an ordinary English word and expands to nothing
— a tower you watch from, which sees and reports and does not intervene. That is the whole of the
name, said here because the name this replaced (`LW-GMHH`, until 3 August 2026) was an initialism
whose last two letters were never expanded anywhere in the tree, including in its own manifest
description. **A watchtower is not a wall**, and the word was chosen over a candidate that implied
protection for exactly that reason: ten of the thirteen modules below can block nothing at all, and the
tenth ships switched off.

LW-WATCHTOWER is a Claude Code plugin that applies one governance layer to every session, in every repo,
without per-project setup. Ten of its thirteen modules **observe** and warn and can block nothing. The
tenth, `delegate_gate`, is the one thing here that can refuse a tool call — and it ships **switched
off**. Two further modules were specified, found to be impossible — the data they need reaches no
hook — and removed rather than left on the banner as names that could never mean anything. The
reasoning was kept so nobody re-attempts them.

It had two other gates. Both were removed at the owner's instruction — the destructive command gate
and then `secret_scan` — on 30 July 2026, leaving none at all. `delegate_gate` was built later the
same day as the one gate that could be built honestly and completely. See
[Both gates were removed](#both-gates-were-removed) and [The three gates](#the-three-gates).

That the banner reads `0 gates` and `observe-only` until you turn that switch on, rather than
counting a gate that is shipped but disabled, is the point. This project exists because a monitor
that reports healthy while doing nothing is worse than no monitor, and most of its own history is
finding that defect inside itself.

- **Platform:** Windows, Windows PowerShell 5.1. Not portable, and not pretending to be.
- **Licence:** [Apache-2.0](LICENSE)
- **Version:** 0.4.0 — pre-1.0, and **not yet tagged**. `v0.3.0` is the only tag so far, and this
  tree is well past it. See [Install](#60-second-quickstart) for which tree each install route
  actually gives you.

---

## Who this is for

You, if you run Claude Code on Windows and you want a layer that reports honestly on what a session
is doing — and that will tell you plainly when it has stopped being able to see anything.

**It will not stop `git push --force`, and it will not stop a credential being written to disk.** It
used to do both. See [Both gates were removed](#both-gates-were-removed). The one thing it will stop,
once you ask it to, is *you* doing work on the main thread instead of delegating it — which is a
discipline, not a safety net.

Not for you if you need cross-platform support, a linter, or a security boundary. See the next
section.

## What this does NOT do

Read this before anything else. The full list, consolidated in one place and kept there deliberately,
is **[docs/limitations.md](docs/limitations.md)** — this section is the headline of it.

- **It inspects nothing about what a tool would do.** The one `PreToolUse` hook it registers decides
  on exactly one thing: whether the call came from a subagent. No path, no command, no file content
  and no argument is ever examined **in order to decide anything** — it reads the tool's name only to
  word its refusal, once the refusal is already settled. Every other module observes, logs or warns
  after or alongside the fact, and the action happens regardless; one of them,
  [`lib/post_edit.ps1`](lib/post_edit.ps1), does record the path of a file that was **already**
  edited, so that two turn-end advisories have something to read.
- **It is not a security boundary,** and now not even a speed bump. A credential can be written to
  any file by any route with nothing from this plugin noticing beforehand. `delegate_gate` refuses a
  main-thread write of a credential and permits a subagent's, which is not a security property.
- **It ships no `permissions.deny` rules.** `/lw-watchtower:setup` used to write 181, then 48; it now
  writes none. If you want that layer — and it is the only one that cannot fail open, since the CLI
  evaluates it itself — you write it yourself. Rules already in your `settings.json` are never
  touched or removed by setup.
- **Nothing here can block assistant text.** There is no hook between the model and the transcript.
  The [output styles](docs/output-styles.md) are requests, not enforcement, and anyone
  describing them as enforcing is repeating this project's founding defect.
- **All thirteen declared modules are built. Nine are enabled; `orphan_watch` and the three gates are not.**
  `ratelimit_escalation` and `cost_tracking`
  were declared and are *blocked*, not merely unwritten: the data they need reaches no hook, and no
  further work on this plugin will change that, so on 30 July 2026 the placeholders were removed and
  the reasoning kept. See
  [Attempted and blocked](docs/modules.md#attempted-and-blocked-ratelimit_escalation-and-cost_tracking).
- **`mission_drift` is on by default and its trigger has never been validated against real
  sessions.** It is exercised end to end by `tests/stop_behaviour.ps1` since 31 July 2026 — the fire
  condition, the suppressors and the pivot path are run rather than only read — and that is a
  different claim from the one that matters: no case can establish that being warned by it is
  *right*, because that judgement is not in the code. It costs about 137 ms at turn end — measured on
  one development machine, not a constant; the distribution behind that median is in
  [Architecture](docs/architecture.md#mission_drift-which-is-switched-on-by-default). It shipped
  `false` for want of that validation; the owner switched it on anyway on 30 July 2026, and what that
  accepts is stated at [`mission_drift`](docs/modules.md#mission_drift).
- **Ten suites test a behaviour, and two of the thirteen modules have none.**
  `tests/gate_delegate.ps1` runs 93 cases against the gate, `tests/stop_behaviour.ps1` runs 178
  against six of the ten observing modules — `mission_drift`, `failure_capture`, `context_pressure`,
  `docs_coupling`, `git_hygiene` and `log_rotation` — `tests/setup_merge.ps1` runs 124 against the
  installer's `statusline` and `hooks` merge **and against the reporting surfaces** — the status
  line, the sitrep, resolve and update, which have no suite of their own —
  `tests/uninstall_footprint.ps1` runs 27 against the uninstaller's
  footprint, attribution and state-data deletions, `tests/evidence_states.ps1` runs 47 against the evidence engine the
  checklist rests on, `tests/doctor_behaviour.ps1` runs 16 against two of the doctor's nine checks,
  `tests/toggle_behaviour.ps1` runs 26 against the toggle's write to `config.json`,
  `tests/subagent_scan.ps1` runs 6 against the `SubagentStart` fast path — the only coverage
  `context_injection` has — and `tests/payload_guard.ps1` runs 15 against what the shipped payload
  discloses; the behavioural ones all go through a real pipe or a real child process. **The other two observing
  modules — `verification_gate` and `self_health` — are exercised by nothing,
  anywhere**, and four of the seven that are covered are covered by one to three cases each, on at most
  two properties apiece — counted on 3 August 2026: `context_pressure` 2, `docs_coupling` 2,
  `log_rotation` 3, `git_hygiene` 1, which is only that an UNKNOWN tree state is repeated at every
  turn end. `context_injection` is thinner still — one property of it is run, and its
  `worker_facts.md` handling has no case at all.
  Read that as "these modules are no longer untouched", not as "these modules are tested".
  (`verification_gate` is the awkward one: the class resolver it reads has cases, the module itself
  has none.) The 233-case gate suite went with the destructive
  gate and the `permissions.deny` parity test went with `secret_scan`; neither came back, and nothing
  here inspects a command or a credential for one to cover. See [Testing and CI](docs/testing.md).
- **It does not see shell edits.** `docs_coupling` and `mission_drift` are fed by
  `Write`/`Edit`/`NotebookEdit`. A file rewritten by a shell command is invisible to both.

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

`delegate_gate` was built on **30 July 2026**, hours after the other two were removed, because it is
the one gate on this project's plan that can be built completely rather than partially. It is
[`lib/gate_delegate.ps1`](lib/gate_delegate.ps1), registered as a `PreToolUse` hook on
`Edit|Write|NotebookEdit|Bash|PowerShell`. `PowerShell` joined that matcher on **1 August 2026**:
this is a Windows-only plugin, the CLI offers both shell tools there, and until then an armed gate
could be walked round by asking for the other shell while `/lw-watchtower:status` reported it live.

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
  path, the command or the content. The matcher in `hooks/hooks.json` is the only place the tool
  list lives.
- **Turning it on is close to one-way from the chat session.** `/lw-watchtower:delegate off` runs through
  `Bash`, and `Bash` is one of the five tools refused — so is `PowerShell`, so switching shell is not
  a way round it. There is deliberately no exemption for it — an exemption for "the command that
  turns me off" is a named bypass. Have a **subagent** run the command, or set `interaction.delegate`
  to `false` in [`config.json`](config.json) by hand.
- **It enforces delegation, not good delegation.** It refuses nothing a subagent does and never
  checks that a dispatch was any good.

## 60-second quickstart

Requires Windows and Windows PowerShell 5.1 (`powershell.exe`). The constraint is the literal binary
name in the ten hook registrations in `hooks/hooks.json`, not a 5.1 language feature — every tracked
script declares `#requires -version 5`, which PowerShell 7 satisfies, so running one under `pwsh` by
hand is not refused by the interpreter — one was checked and produced byte-identical output, which is
one script and not a guarantee about all of them. The hooks will still invoke `powershell`.

```
/plugin marketplace add LEAPWare-Software/LEAPWare-Watchtower
/plugin install lw-watchtower@leapware-watchtower
```

**This gives you `main`, not a release.** `.claude-plugin/marketplace.json` sources the plugin from
the repository root with no `ref`, `tag` or `branch` key, so the marketplace resolves the **default
branch** and you get whatever `main` held at the moment you installed. It is not pinned, no two
installs on different days need be the same tree, and it is **not** the tree any tag was tested
against. That is a property of this install route and no version number can fix it — it is stated
here rather than papered over. The banner tells you the declared version and nothing more; to know
which commit you are on, use a clone (below) and read it.

For a **tested** tree, clone and check out the tag — `git checkout v0.3.0` — and install by junction
as [docs/install.md](docs/install.md) describes. Note the trade: `v0.3.0` is the last tag, so pinning
to it costs you every fix on `main` since, including the ones in
[CHANGELOG.md](CHANGELOG.md#040--unreleased).

Start a new session. You should see:

```
LW-WATCHTOWER v0.4.0 · 9/10 modules active (1 off) · 0 gates · observe-only
```

The one that is off is `delegate_gate`, and off is where it is meant to be.

Then:

```
/lw-watchtower:doctor
```

Checks on the plugin's wiring, in under a second — it prints how many it ran, so no count is
transcribed here to go stale. It is built to be able to fail, and a
non-zero exit is a real finding.

That is the whole install. Configuration is optional and lives in one file,
[`config.json`](config.json).

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
| `verification_gate` | observe | implemented — warns when work shipped unchecked. **Advisory, not a gate** |
| `docs_coupling` | observe | implemented — flags source changes shipped without docs |
| `git_hygiene` | observe | implemented — branch, commit and push discipline at turn end |
| `context_injection` | observe | implemented — hands every subagent facts current at *dispatch* time |
| `mission_drift` | observe | implemented — notices work that matches nothing that was asked for. **On by default since 30 July 2026. Tested since 31 July, but its trigger has never been validated against a real session** |
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
reads, closes or acknowledges a trip, and the status line has no governance segment. `/lw-watchtower:sitrep`
counts `GateDeny` records as history. The design, and what an indicator would have to rebuild, is
preserved at
[The trip ledger](docs/architecture.md#the-trip-ledger--removed-and-recorded-here-as-a-design) and
[Gates were removed deliberately](docs/gates-removed.md).

## Commands

Twelve slash commands. Claude Code namespaces a plugin's commands with the plugin name and the
prefix **cannot be suppressed**, so they are `/lw-watchtower:…` and nothing shorter.

**Report on governance** — these read and print; none of them changes anything.

| Command | What it does |
| --- | --- |
| `/lw-watchtower:status` | Reports which modules are active, planned or off, the mode, and **two** gate counts — how many ship and how many are live, which are `1` and `0` by default. Reports; never judges. |
| `/lw-watchtower:doctor` | Wiring checks aimed at what is **not** working, counted in its own output. Exits non-zero when it finds something. |

**Report on the plan** — evidence-derived, never self-asserted.

| Command | What it does |
| --- | --- |
| `/lw-watchtower:checklist` | Plan state with every item derived from a commit, a file, an exit code or a CI conclusion. An item with no evidence renders `unverified`, which is **not** a synonym for incomplete. |
| `/lw-watchtower:sitrep` | Work in flight, work finished since the last sitrep, blockers and decisions awaiting you. Separates verified from reported, and names what it could not determine. |

**Lifecycle** — the four that can change your machine all dry-run by default.

| Command | What it does |
| --- | --- |
| `/lw-watchtower:setup` | Guided installer. Detects what is already there, asks in plain language, then writes `statusLine`, hooks and agent roles one section at a time — each behind its own diff and its own yes. Its `permissions.deny` section now writes **nothing**: the rule table is empty. |
| `/lw-watchtower:config` | Module switchboard: turn a governance module on or off, globally or for one repo, after being told exactly what the change does. Needs `-Apply` to write. |
| `/lw-watchtower:update` | Fetches and reports what is new and what would need re-approval. Fast-forward only; merges nothing without `-Apply`. |
| `/lw-watchtower:uninstall` | Reports this plugin's whole footprint and what removing it would take, and names everything it **cannot** remove. Dry run by default. |
| `/lw-watchtower:resolve` | Marks one session's outstanding health faults resolved, with the data directory and the session both pinned — or refuses and says why. |

**Preferences** — three commands, and **one of them is enforced and two are not**. Read
[what each one does and does not do](docs/commands.md#the-three-preference-commands-and-what-each-one-actually-does)
before treating any of them as a control.

| Command | Default | Enforced | What it does |
| --- | --- | --- | --- |
| `/lw-watchtower:verbosity` | `default` | no | How much an answer carries: `brief`, `default` or `verbose`, set by name. **One key with three levels, not switches** — `output_style.verbosity` holds exactly one of them, so setting a level unsets the others. Was two commands, `brief` and `verbose`, until they were merged. Records the preference; activating the output style is a manual step the script spells out. |
| `/lw-watchtower:plain` | off | no | Plain English, no unexplained tooling jargon. A separate axis from verbosity — jargon, not length. Same manual step. |
| `/lw-watchtower:delegate` | off | **yes** | Reserve the chat session for the operator and send all work to subagents. Arms `delegate_gate`, which really refuses `Edit`, `Write`, `NotebookEdit`, `Bash` and `PowerShell` on the main thread. **Read [The one gate](#the-one-gate) before turning it on** — it cannot be turned off again from the main thread. |

`lw-watchtower:ask` and `lw-watchtower:ask-inline` were here until 30 July 2026 and were **removed** by an
explicit owner decision. (Both are written without a leading slash, here and everywhere else, because
`/lw-watchtower:doctor` fails on a `/lw-watchtower:<name>` reference with no command file behind it — a
live-looking reference to a deleted command is a signpost to nothing.) Both had been on by default
since they shipped while enforcing nothing, and **neither can be built**: a `Stop` hook can refuse to
end a turn but cannot stop prose that has already appeared, and cannot detect a question that should
have been asked and was not; nothing can merge questions after they have been asked. The reasoning
is kept in [`config.json`](config.json) so nobody re-attempts them.

Exit codes and reporting rules: [Commands](docs/commands.md).

## Documentation

| | |
| --- | --- |
| **[Limitations](docs/limitations.md)** | **Everything this plugin does not do, cannot do, or does not check, in one place. Start here** |
| [FAQ](docs/faq.md) | The questions a new user and a returning owner actually have, answered from the tree |
| [Install](docs/install.md) | Requirements, both install routes, the separate status-line install |
| [Configuration](docs/configuration.md) | `config.json` in full |
| [Modules](docs/modules.md) | All ten, with their blind spots, **the one gate**, and the removal of the other two |
| [Gates were removed deliberately](docs/gates-removed.md) | The rules a gate has to follow here, **what the trip ledger's removal means a new gate must rebuild**, and what four failed fix attempts taught |
| [Commands](docs/commands.md) | All twelve slash commands, their exit codes, and which preference commands are enforced |
| [Roles](docs/roles.md) | The six agent roles the plugin ships, and when each is dispatched |
| [Architecture](docs/architecture.md) | Layout, hooks, measured costs, state, failure policy |
| [Testing and CI](docs/testing.md) | **Thirteen files in `tests/`, ten of which test behaviour** — what each one covers, and what is uncovered |
| [Portability](docs/portability.md) | The no-local-environment-dependencies mandate, and the scan that enforces it |
| [Output styles](docs/output-styles.md) | The three verbosity levels and `plain`, and what they cannot do |
| [Troubleshooting](docs/troubleshooting.md) | Symptom-first index |

## Project status

Pre-1.0. The manifests declare `0.4.0`, which **no tag has published yet**. `v0.3.0` is the only tag
this project has, and `main` is a long way past it — far enough that two changes on this branch alter
how an existing `config.json` is read, which is why the next number is `0.4.0` and not `0.3.1`. See
[CHANGELOG.md](CHANGELOG.md#040--unreleased) for what those are and what to check in your own config.

`main` never declares a version a tag already published, and
[`tests/doc_claims.ps1`](tests/doc_claims.ps1) fails the build if it does — on a clone that has tag
refs. See [CONTRIBUTING.md](CONTRIBUTING.md#versions-and-releases) for the rule and for the part the
guard cannot see.

CI runs on `windows-latest` under Windows PowerShell 5.1, in **one job with fifteen check steps**:
JSON validity, PowerShell parse, the workflow guard, the delegate gate suite, the installer merge
suite, the stop-hook behaviour suite, the uninstaller footprint suite, the evidence-state suite, the
doctor behaviour suite, the toggle write-path suite, the `SubagentStart` fast-scan suite, the payload
disclosure guard, the
portability scan, and the documentation-claim guard. The `gate-regression` job and the
233-case suite behind it were deleted on 30 July 2026 with the destructive command gate; the
`permissions.deny` parity step and `tests/deny_parity.ps1` went the same day with `secret_scan`.
**A green CI run says tracked files parse, name no machine, that no workflow reaches a runner GitHub
does not host, that `delegate_gate` still refuses what it declares, that the installer's `statusline`
merge still preserves what it was not asked to touch, that the pinned turn-end cases still behave for
the six observing modules `tests/stop_behaviour.ps1` reaches, that the uninstaller deletes exactly the state data it listed,
that the evidence engine does not report a state it never observed, and that no page here states a
count the tree contradicts. It is not evidence that the other three observing modules work, because
not one of them is exercised by anything — and for four of the six that are, it is evidence about at
most two properties apiece and no more.** See [Testing and CI](docs/testing.md).

If branch protection on `main` still requires the `gate-regression` context, it has to be removed —
that job can never report again. `fast-checks` is not the replacement: that is the YAML job id, and a
required status check is matched by the check run's **name**, so requiring the id blocks every merge
for the same reason. The one requirable string is the surviving job's display name, quoted verbatim in
[Testing § Branch protection](docs/testing.md#branch-protection). It is not repeated here on purpose:
that page is held to the string by the documentation-claim guard, which derives it from `ci.yml`, and
this page is not.

There is no status badge here, deliberately: the repository is private, so a badge would not render
for most viewers, and a green badge covering three gates and eight of the ten observing modules would
read as far broader assurance than it is.

## Contributing

Bug reports and PRs are welcome. Read
[CONTRIBUTING.md](CONTRIBUTING.md) first — in particular the three rules it puts above the rest. Two
of them fail the build and the first one does not, which is a distinction worth carrying away:

- **A regression test must fail before the fix.** *Held by review, strictly — nothing enforces it*,
  because the only harness that could was deleted on 30 July 2026. This project's suite was 67/67
  green while five gate bypasses were open, which is the whole reason the rule is written down. It
  applies to `tests/gate_delegate.ps1` exactly as it applied to the suite that taught it: every case
  there was confirmed to fail against a deliberately broken gate before it was kept.
- **No local environment dependencies.** *CI fails the build on a hit.* No account name, computer
  name, profile path or absolute interpreter path in a tracked file. `tests/portability_scan.ps1`
  scans every tracked file in CI — because one laptop's private facts have shipped as universal truth
  three times, including a status line that rendered *not installed* forever on every other machine.
  The mandate is [docs/portability.md](docs/portability.md).
- **No self-hosted runner, no `pull_request_target`, no secrets in any workflow.** *CI fails the
  build on a hit.* `tests/workflow_guard.ps1` parses every workflow file rather than grepping it —
  the check it replaced could be satisfied by a comment. This is the one whose failure mode is
  **somebody else's machine rather than your build**: a self-hosted runner reachable from a public
  repository hands a stranger code execution on the maintainer's hardware.

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

**`delegate_gate` is not a security control and a way past it is not a vulnerability.** It refuses
main-thread work as a discipline; a subagent can do anything it refuses, by design. What is still a
security report rather than a public issue is a credential leaking through this plugin's own logs, or
the plugin damaging your `settings.json`. See [SECURITY.md](SECURITY.md).

## Licence

Apache-2.0. See [LICENSE](LICENSE).
