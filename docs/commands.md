# Commands

Six slash commands. Claude Code namespaces a plugin's commands with the plugin name and the
prefix **cannot be suppressed**, so they are `/lw-watchtower:…` and nothing shorter.

**There were twelve.** Every deleted command below is written **without a leading slash**, because
[`bin/lwg-doctor.ps1`](../lw-watchtower/bin/lwg-doctor.ps1)'s `commands` check fails on a `/lw-watchtower:<name>`
reference with no command file behind it — the right rule, since a live-looking reference to a
deleted command is a signpost to nothing.

**Six were deleted on 2 September 2026**, under the owner's rule that a feature whose only defence is
that it exists is not a feature.

- `lw-watchtower:status` reported the module table and the gate counts. **It was folded into
  [`/lw-watchtower:doctor`](#lw-watchtowerdoctor)**, which already printed the same roster off the
  same `$LwgModuleRegistry` and the same `Get-Lwg*` helpers. Two commands reading one source is two
  places for the same answer to drift.
- `lw-watchtower:checklist` rendered this plugin's own release plan — forty rows about somebody
  else's project, formatted exactly like findings about your tree — on a consumer's machine, because
  at the time the whole repository root was the payload. It went with the manifest and the evidence
  engine behind it, and the payload boundary was drawn separately: the marketplace now sources
  `./lw-watchtower` and nothing outside that subdirectory reaches a consumer at all.
- `lw-watchtower:sitrep` reported the maintainer's repository to an operator working in their own,
  made authenticated `gh` calls with the operator's token to do it, and could not see running agents
  at all.
- `lw-watchtower:resolve` hand-cleared a health fault count. It could not clear a red raised by dead
  agents, which is the case it most needed to clear; state belongs in the ledger, not in a marker
  somebody writes over it.
- `lw-watchtower:verbosity` and `lw-watchtower:plain` recorded an output-style preference that
  **nothing enforced and nothing applied** — the style Claude Code uses is the `outputStyle` key in a
  settings file, and this plugin never wrote it. They went with the five output-style files they
  named.

**Four were deleted on 30 July 2026, and every deletion was deliberate.**

- `lw-watchtower:verify` ran the gate regression suite and went with the destructive command gate that
  suite mostly covered. **No command tests behaviour.** 11 suites test behaviour and only two of
  them cover a gate — see [Testing](testing.md).
- `lw-watchtower:tripped` listed open gate trips and went with the trip ledger it read: both gates were
  already gone, so no trip could be recorded, and the ledger files it read were then backed up and
  removed too. Nothing records, reads, closes or acknowledges a trip, and `delegate_gate` did not
  bring any of that back. What an indicator would have to rebuild is in
  [Gates were removed deliberately](gates-removed.md).
- `lw-watchtower:ask` and `lw-watchtower:ask-inline` went together, and **not because they were unfinished —
  because neither can be built.** `ask` needed a `Stop` hook refusing to end a turn while an
  unanswered decision was outstanding, and a `Stop` hook can block turn-end but cannot stop prose
  that has already appeared and cannot detect a question that should have been asked and was not, so
  the half that mattered was unreachable. `ask-inline` needed something that counts and merges the
  questions asked in a turn, and nothing can merge them after the fact; the 4-questions /
  2–4-options shape was always a platform limit on the question tool rather than a rule this plugin
  applied. Both had been **on by default since they shipped, enforcing nothing.**
  `interaction.ask` and `interaction.ask_inline` went with them, and [`config.json`](../lw-watchtower/config.json)
  keeps the reasoning under `$removed_keys_comment` so nobody re-attempts them.

## Report on governance

Read and print; it changes nothing. There is one, and it absorbed the other on
2 September 2026.

| Command | Backed by | What it does | Exits non-zero |
| --- | --- | --- | --- |
| [`/lw-watchtower:doctor`](#lw-watchtowerdoctor) | [`bin/lwg-doctor.ps1`](../lw-watchtower/bin/lwg-doctor.ps1) | 10 checks aimed at what is **not** working. | **yes — that is the point** |

## Lifecycle

All four of the commands that can change your machine **dry-run by default** and need an explicit
second run with `-Apply` to write anything.

| Command | Backed by | What it does | Exits non-zero |
| --- | --- | --- | --- |
| [`/lw-watchtower:setup`](#lw-watchtowersetup) | [`bin/lwg-setup.ps1`](../lw-watchtower/bin/lwg-setup.ps1) | Guided installer. Detects what is already present, asks in plain language, then writes `statusLine` and hooks **one section at a time, each behind its own diff and its own yes**. It has no `permissions` section any more — the function and the section that wrote `permissions.deny` rules are both deleted, and `-Section` accepts `statusline` and `hooks` only. | yes, on a step that could not be completed |
| [`/lw-watchtower:config`](#lw-watchtowerconfig) | [`bin/lwg-config.ps1`](../lw-watchtower/bin/lwg-config.ps1) | Module switchboard: turn a governance module on or off, globally or for one repo, after being told exactly what the change does. | yes, on a bad key or an unwritable config |
| [`/lw-watchtower:update`](#lw-watchtowerupdate) | [`bin/lwg-update.ps1`](../lw-watchtower/bin/lwg-update.ps1) | Fetches, then lists what would change and what needs re-approval afterwards. **Fast-forward only.** Re-runs the doctor after applying. | yes, if the fetch fails or a fast-forward is not possible |
| [`/lw-watchtower:uninstall`](#lw-watchtoweruninstall) | [`bin/lwg-uninstall.ps1`](../lw-watchtower/bin/lwg-uninstall.ps1) | Reports the plugin's whole footprint and what removing it would take, and **names everything it cannot remove**. | yes, if part of the removal could not be completed |

## Preferences

One command, running [`bin/lwg-toggle.ps1`](../lw-watchtower/bin/lwg-toggle.ps1). It was three until
2 September 2026, and the two that went were the two that enforced nothing. Read
[what it actually does](#lw-watchtowerdelegate-the-one-preference-command-left) before treating it
as a control.

| Command | Default | Records | Enforced? |
| --- | --- | --- | --- |
| `/lw-watchtower:delegate` | off | `interaction.delegate` | **yes** — arms `delegate_gate`, a real `PreToolUse` block |

**The logic is in the scripts, not in the command prose.** A `commands/*.md` file tells the model to
run one command and report the result honestly; it does not tell it how to assess anything. A health
check the model performs by following instructions is a health check that reports whatever the model
infers, which is the failure mode this plugin exists to catch. The markdown carries the reporting
discipline — *do not soften a `[FAIL]`, do not read exit `4` as a pass* — and the exit code carries
the verdict.

Each script can be run directly, which is how CI uses them:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File lw-watchtower\bin\lwg-doctor.ps1 -Quiet
```

---

## `/lw-watchtower:doctor`

10 checks: `plugin-manifest`, `marketplace`, `hooks-declared`, `config-registry`, `state-dir`,
`sessionstart`, `statusline`, `commands`, `platform`, `claude-version`.

The list has been wrong twice, both times by omission, on a page the doctor's own slash command
points the model at for what a row means. The script has never transcribed the number: it prints
`$script:Rows.Count`, and `tests/doc_claims.ps1` reads the phrasings on this page against
that header rather than against a sibling sentence.

`agent-roles` was the ninth check until 2 September 2026 and **is gone**, with `verification_gate`,
the module it was about. Nothing enumerates role classes any more and no row here reports on
`agents/`.

### It is allowed to fail

| Exit | Meaning |
| --- | --- |
| `0` | every check passed |
| `1` | at least one check **failed** — something is broken now |
| `2` | no failures, but at least one warning |
| `3` | the doctor itself could not complete; the lines printed are a fragment of a checkup rather than the result of one |

`3` is separate from `1` deliberately: *"I found a fault"* and *"I could not look"* are different
statements, and collapsing them would let a crashed doctor read as a diagnosis. Every check was
written by first arranging for it to fail and confirming it said so.

Two of the 10 checks exist because this repo has already shipped the bug they look for:

- **`state-dir`** fails when the state directory resolves to a *guess* rather than to the live
  directory — the defect that had the status line rendering unconditional green off an empty log.
  See [State directory](architecture.md#state-directory).
- **`config-registry`** fails when `config.json`'s module keys and the registry in `lib/common.ps1`
  disagree: a flag with no registry entry is a switch wired to nothing, and a registry entry with no
  flag is a module nobody can turn off.

**`claude-version`** reports the Claude Code build against the one the eight hook events in
`hooks/hooks.json` were read out of. It has three states and only one of them warns: a build that
was read and is at or above the verified one **passes**; a build that was read and is **below** it
**warns**, because `SubagentStart`, `PostToolUseFailure` and `StopFailure` may be inert there and an
inert hook is silent; and a build that could not be read at all **passes with a detail saying so in
words**. The third state is the normal one — `CLAUDE_CODE_VERSION` is not exported by the CLI on any
path — and it is a PASS because it is a limit on what can be observed from here, not a fault in the
tree. A PASS on this row is a statement about the **build only**: no event below `SessionStart` is
proved to have fired on this machine by anything in the report.

`statusline` also reports **drift** between `~/.claude/statusline.ps1` and this repo's
[`statusline/statusline.ps1`](../lw-watchtower/statusline/statusline.ps1) as a warning. That copy is installed by
hand and the two can silently diverge.

### What a green doctor does not mean

It checks the plugin's *wiring*, not its *behaviour*. It does **not** establish that any advisory
fires, or that Claude Code has the plugin enabled in the current session — a hook can be flawlessly
configured and switched off. It cannot establish that anything is blocked: the two security gates
were removed on 30 July 2026, and the one `PreToolUse` gate registered since — `delegate_gate` —
ships switched off, so on a default install nothing here blocks anything. The script prints those
blind spots on every run, including the green ones.

**No command tests behaviour.** The one that did — `lw-watchtower:verify`, over a 233-case suite — was
removed with the destructive command gate. 11 behavioural test files survive it —
[`tests/gate_delegate.ps1`](../tests/gate_delegate.ps1) for `delegate_gate`,
[`tests/supervision.ps1`](../tests/supervision.ps1) for the other two gates and `orphan_watch`, and
nine more covering the installer's `statusline` and hooks merge, the turn-end hooks, the
`SessionStart` hook and its state-directory resolution, the uninstaller's deletions,
two of the doctor's 10 checks, the two writers of `config.override.json`, the
`SubagentStart` fast path and what the shipped payload discloses — and every one of them is run by CI and by hand, while **no command reaches any
of them.** So a green doctor is the only automated statement any *command* here makes about this
plugin, and it is a statement about wiring alone. Do not fill that gap with an inference.

---

## `/lw-watchtower:setup`

The guided installer, for someone who has never heard of a hook, a glob or a JSON key.

**The model is the interface, not the installer.** Every decision, rule, path and diff comes out of
[`bin/lwg-setup.ps1`](../lw-watchtower/bin/lwg-setup.ps1); the command prose only puts its questions to the
operator and pastes its output verbatim. Nothing is written that the script has not printed first.

It detects what is already there, then writes `statusLine` and hooks **one section at a time, each
behind its own diff and its own yes** — so a stalled or refused install leaves a settings file that
is coherent rather than half-migrated. It never rewrites a settings file wholesale.

**It writes no `permissions.deny` rules.** The `permissions` section is still run and still shown,
because the installer still prints it and you will see the heading — but its rule table is empty, so
it can only ever report that it has nothing to add. The 181 rules it used to install went on
30 July 2026 with the two gates. Rules already in your own `settings.json` are never touched,
removed or rewritten. See [`docs/install.md`](install.md) and
[`docs/gates-removed.md`](gates-removed.md).

---

## `/lw-watchtower:config`

The module switchboard, and the only supported way to change the `modules` block without
hand-editing it.

Run with no arguments it reports what is currently on. To change something it is run **twice**: once
without `-Apply`, which prints the exact diff and states what the change does to your coverage, and
once with, which writes it. `-Scope repo` writes an override for the current repository only.

It refuses rather than guesses: a key that is not in the registry in [`lib/common.ps1`](../lw-watchtower/lib/common.ps1)
is rejected, because a flag with no registry entry is a switch wired to nothing — the defect
`doctor`'s `config-registry` check exists to find.

---

## `/lw-watchtower:update`

Fetches, then lists what would change and **what needs re-approval afterwards** — a new hook or a
changed command is not silently trusted because the old version was.

**Fast-forward only.** It merges nothing and rebases nothing; if the local tree has diverged it says
so and stops, rather than resolving a conflict on your behalf inside an installed plugin. It re-runs
the doctor after applying, because an update that leaves the plugin misconfigured is not a completed
update.

---

## `/lw-watchtower:uninstall`

**A dry run by default**, and the dry run is the point: it reports this plugin's whole footprint —
plugin root, data directories, the copied status line, the settings keys it was installed into — and
what removing each would take.

It **names everything it cannot remove**, which on a normal install is most of the interesting part:
`permissions.deny` entries you may want to keep, the `statusLine` key, and the historical data
directories described in
[Three data directories](architecture.md#three-data-directories-and-why-picking-between-them-is-not-the-fix).
An uninstaller that silently leaves state behind is the same class of defect as a monitor that
reports healthy while doing nothing.

**Where it looks for the state data is resolved, not assumed.** It calls the same resolver as the
doctor, the status line and every hook — `CLAUDE_PLUGIN_DATA` first, then the discovered
`<name>-<source>` directory, then the bare fallback — and prints that path and its source in the
run header. Until 31 July 2026 this one block hardcoded `~\.claude\plugins\data`, so with the data
directory redirected it reported `state-data absent` while the doctor reported five live files, and
`-RemoveData -ConfirmToken DELETE-MY-LWG-LOGS` reported `APPLIED: 0 change(s), 0 failure(s)` and
exited `0` with nothing deleted. `tests/uninstall_footprint.ps1` pins that, and pins the
distinction it turned on: a location that resolves to nothing reports **`absent`** and exits `0`,
and a location that will not resolve reports **`UNRESOLVED`** and exits `2` — including in the dry
run, because "would you delete the data?" cannot be answered by a script that does not know where
the data is.

---

## `/lw-watchtower:delegate`, the one preference command left

It runs [`bin/lwg-toggle.ps1`](../lw-watchtower/bin/lwg-toggle.ps1) with `-Flag delegate`. That script's own header
records the shape of the thing: **it was five flags, then three, and is now one.** `verbosity` and
`plain` went with the output styles they recorded a preference about, and their removal took the
`NOT WIRED` half of this page with them — the two flags that needed that block were exactly the two
that recorded a preference and enforced nothing.

With no argument it **reports** and changes nothing. With an argument it writes the global default;
with a trailing `repo` it writes an override for this repository only.

It is a boolean and takes `on` or `off`. Anything else — `true`, `1`, `yes`, `enable` — is
**rejected** with a usage message and exit `2`, and nothing is written. A toggle that guesses what
you meant is a toggle you cannot be sure you set.

**Every run prints an `ENFORCED` block**, naming what it blocks and what turning it on costs. There
is no default branch and no other heading left to print: a heading is the first thing read, so a
wired switch printing `NOT WIRED` would be the loudest lie this command could tell about itself.

### It is the only thing in this plugin that is enforced

Turning it on arms [`delegate_gate`](modules.md#delegate_gate) —
[`lib/gate_delegate.ps1`](../lw-watchtower/lib/gate_delegate.ps1), a `PreToolUse` hook on
`Edit|Write|NotebookEdit|Bash|PowerShell` — which refuses those five tools for any call that did not
come from a subagent. The refusal is real: a `PreToolUse` deny is honoured **even under
`permissions.defaultMode: "bypassPermissions"`**, so for anyone running in that mode this is a
stronger layer than a `permissions.deny` rule. It takes effect on the very next tool call; there is
nothing to restart.

**Read this before turning it on.** With the gate armed, `/lw-watchtower:delegate off` **will not turn
it off**, because this command runs its script through `Bash` and `Bash` is one of the five tools
refused. There is deliberately no exemption for it — an exemption for "the command that turns me off"
is a named bypass, and one named bypass is an argument about which others deserve one. The two ways
back:

1. Have a **subagent** run `/lw-watchtower:delegate off`. Its calls carry `agent_id` and are allowed.
2. Set `interaction.delegate` to `false` by hand in `config.override.json` under the state
   directory — `$CLAUDE_PLUGIN_DATA`, or `~/.claude/plugins/data/lw-watchtower*/`. **Not in
   `config.json`**: that file is the shipped defaults, and an edit there changes nothing while the
   override still says `true`. If no override file exists, the gate is off already and there is
   nothing to turn off.

**What it still does not do.** It refuses nothing a subagent does, and it never checks that a
dispatch was any good. Delegation is enforced; delegating *well* is not, and describing it as
supervision, review or safety would be exactly the overstatement this page exists to avoid.

### Its flag is deliberately outside the `modules` block

`delegate_gate` **is** in the registry — it is a gate, which is governance in its strongest form, so
it is a registry entry of `kind = 'gate'` and the banner counts it. What stayed *out* of the
`modules` block is its **flag**: the registry entry declares
`switch = @{ block = 'interaction'; key = 'delegate' }`, so `interaction.delegate` is the one and only
switch. A second flag in `modules` would let you run `/lw-watchtower:delegate on` and have the gate
stay silent because the other flag was false — a switch wired to nothing, which is the founding
defect this plugin exists to catch. [`bin/lwg-doctor.ps1`](../lw-watchtower/bin/lwg-doctor.ps1)'s `config-registry`
check knows about the exemption, asserts the declared key really exists, and fails if both spellings
are present at once.

Because the flag is outside `modules`, it does **not** inherit the fail-open polarity: `Get-LwgConfig`
fails *open*, which would arm a blocking gate on a corrupt config — the wrong polarity for a gate. An
unreadable `config.json` leaves it **off**, which is what keeps a bad config a nuisance rather than a
lockout.

### The settings file is edited surgically, not round-tripped

PowerShell 5.1's `ConvertTo-Json` rewrites an apostrophe and an angle bracket into six-character
escape sequences, and roughly 60 % of `config.json` is explanatory `$comment` prose full of both. A
single toggle would have rewritten every one of those comments into escape sequences, and produced a
whole-file diff for a one-word change. So the script walks the text with a string-and-escape-aware
scanner and replaces exactly one value, or inserts exactly one member. It then parses the **result**
with `ConvertFrom-Json` and only writes the file if that parse succeeds, so a bad edit leaves
`config.json` untouched rather than needing to be undone.

**There is no argument that deletes a per-repo override.** `on`, `off` and nothing at all are the
only three things you type; a fourth verb that removes a key is a fourth thing to get wrong. When an
override exists the script says where it is, and you delete the entry from `config.override.json` by hand to
fall back to the global default.

| Exit | Meaning |
| --- | --- |
| `0` | the state was reported, or changed and reported |
| `2` | the argument was not `on` or `off`, or `-Scope repo` was used outside a repo. **Nothing was written** |
| `3` | the settings file could not be read, could not be written, or would not have parsed afterwards. **Nothing was written**, and `config.json` in the plugin root is untouched on every path, because no path writes it |

---

## No manifest entry is needed

`commands/` is **auto-discovered** from the plugin root, and so is `agents/`.
[`.claude-plugin/plugin.json`](../lw-watchtower/.claude-plugin/plugin.json) was **not** changed
to add the command surface and must not be — naming `commands` in the manifest *replaces* the
default directory scan rather than adding to it, so declaring it would at best change nothing and at
worst hide the very files it names.

Verified against Claude Code 2.1.220 with `claude plugin validate --strict`, which walks and parses
every discovered command, and end-to-end by loading the repo into a live session with
`claude --plugin-dir` and invoking `/lw-watchtower:doctor`.

`bin/` **is** added to the Bash tool's `PATH` while the plugin is enabled. Nothing here relies on
it: a `.ps1` is not executable as a bare command on `PATH`, and it would have to be launched through
`powershell -File` regardless. So each command invokes its script by absolute path through
`${CLAUDE_PLUGIN_ROOT}`, which is expanded in command bodies. The `PATH` entry is added whether or
not the directory exists, so its presence is not evidence that anything is installed in it.
