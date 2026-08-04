# Commands

Twelve slash commands. Claude Code namespaces a plugin's commands with the plugin name and the
prefix **cannot be suppressed**, so they are `/lw-watchtower:…` and nothing shorter.

**Two were merged into one on 30 July 2026.** `lw-watchtower:brief` and `lw-watchtower:verbose` were two
commands over the single `output_style.verbosity` key, which holds one of three values. They are now
[`/lw-watchtower:verbosity`](#verbosity-is-one-key-with-three-levels), which sets the level by name.
Nothing about the stored value changed. `/lw-watchtower:plain` was **not** folded in: plain English is a
genuinely separate axis, about jargon rather than length.

**Four were deleted on 30 July 2026, and every deletion was deliberate.** All four are written below
**without a leading slash**, because [`bin/lwg-doctor.ps1`](../bin/lwg-doctor.ps1)'s `commands` check
fails on a `/lw-watchtower:<name>` reference with no command file behind it — the right rule, since a
live-looking reference to a deleted command is a signpost to nothing.

- `lw-watchtower:verify` ran the gate regression suite and went with the destructive command gate that
  suite mostly covered. **No command tests behaviour.** Nine suites test behaviour and only one of
  them covers the gate — see [Testing](testing.md).
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
  `interaction.ask` and `interaction.ask_inline` went with them, and [`config.json`](../config.json)
  keeps the reasoning under `$removed_keys_comment` so nobody re-attempts them.

## Report on governance

Read and print; none of these changes anything.

| Command | Backed by | What it does | Exits non-zero |
| --- | --- | --- | --- |
| [`/lw-watchtower:status`](#lw-watchtowerstatus) | [`bin/lwg-status.ps1`](../bin/lwg-status.ps1) | The SessionStart banner, expanded: every module with its kind, whether it is built, whether it is enabled, and — the only column that reports behaviour — its state. Plus **two** gate counts, `SHIPPED` and `LIVE`, which are `1` and `0` by default, a `GATES` block naming each gate's switch, and the mode. | only if it cannot produce a report |
| [`/lw-watchtower:doctor`](#lw-watchtowerdoctor) | [`bin/lwg-doctor.ps1`](../bin/lwg-doctor.ps1) | Nine checks aimed at what is **not** working. | **yes — that is the point** |

## Report on the plan

Every item's state is derived from evidence — a commit, a file, an exit code, a CI conclusion —
never self-asserted. **An item with no evidence renders `unverified`, which is not a synonym for
incomplete.**

| Command | Backed by | What it does | Exits non-zero |
| --- | --- | --- | --- |
| [`/lw-watchtower:checklist`](#lw-watchtowerchecklist) | [`bin/lwg-checklist.ps1`](../bin/lwg-checklist.ps1) | Plan state, item by item, against [`checklist.json`](../checklist.json). | only if the probes cannot run |
| [`/lw-watchtower:sitrep`](#lw-watchtowersitrep) | [`bin/lwg-sitrep.ps1`](../bin/lwg-sitrep.ps1) | Work in flight, work finished since the last sitrep, blockers, and decisions awaiting you. Separates **verified** from **reported** and names what it could not determine. `--no-mark` leaves the "last sitrep" watermark alone. | as above |

## Lifecycle

All four of the commands that can change your machine **dry-run by default** and need an explicit
second run with `-Apply` to write anything.

| Command | Backed by | What it does | Exits non-zero |
| --- | --- | --- | --- |
| [`/lw-watchtower:setup`](#lw-watchtowersetup) | [`bin/lwg-setup.ps1`](../bin/lwg-setup.ps1) | Guided installer. Detects what is already present, asks in plain language, then writes `statusLine` and hooks **one section at a time, each behind its own diff and its own yes**. Its `permissions` section is still run and can only ever report that it has nothing to add — the rule table is empty and it installs no `permissions.deny` rules. | yes, on a step that could not be completed |
| [`/lw-watchtower:config`](#lw-watchtowerconfig) | [`bin/lwg-config.ps1`](../bin/lwg-config.ps1) | Module switchboard: turn a governance module on or off, globally or for one repo, after being told exactly what the change does. | yes, on a bad key or an unwritable config |
| [`/lw-watchtower:update`](#lw-watchtowerupdate) | [`bin/lwg-update.ps1`](../bin/lwg-update.ps1) | Fetches, then lists what would change and what needs re-approval afterwards. **Fast-forward only.** Re-runs the doctor after applying. | yes, if the fetch fails or a fast-forward is not possible |
| [`/lw-watchtower:uninstall`](#lw-watchtoweruninstall) | [`bin/lwg-uninstall.ps1`](../bin/lwg-uninstall.ps1) | Reports the plugin's whole footprint and what removing it would take, and **names everything it cannot remove**. | yes, if part of the removal could not be completed |
| [`/lw-watchtower:resolve`](#lw-watchtowerresolve) | [`bin/lwg-resolve.ps1`](../bin/lwg-resolve.ps1) | Marks one session's outstanding health faults resolved, with the **data directory and the session both pinned** — or refuses and says why. Always list first. | yes, when it refuses |

## Preferences

Three commands, all running [`bin/lwg-toggle.ps1`](../bin/lwg-toggle.ps1) with a different `-Flag`.
**One of the three is enforced and two are not.** Read
[what each one actually does](#the-three-preference-commands-and-what-each-one-actually-does)
before treating any of them as a control.

| Command | Default | Records | Enforced? |
| --- | --- | --- | --- |
| `/lw-watchtower:verbosity` | `default` | `output_style.verbosity` = `brief`, `default` or `verbose` | no — an output style is advisory |
| `/lw-watchtower:plain` | off | `output_style.plain` | no |
| `/lw-watchtower:delegate` | off | `interaction.delegate` | **yes** — arms `delegate_gate`, a real `PreToolUse` block |

**The logic is in the scripts, not in the command prose.** A `commands/*.md` file tells the model to
run one command and report the result honestly; it does not tell it how to assess anything. A health
check the model performs by following instructions is a health check that reports whatever the model
infers, which is the failure mode this plugin exists to catch. The markdown carries the reporting
discipline — *do not soften a `[FAIL]`, do not read exit `4` as a pass* — and the exit code carries
the verdict.

Each script can be run directly, which is how CI uses them:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-doctor.ps1 -Quiet
```

---

## `/lw-watchtower:status`

Reports; it does not check anything. It will happily describe a plugin that is perfectly configured
and completely switched off.

It reads `$LwgModuleRegistry` in [`lib/common.ps1`](../lib/common.ps1) — the single source of truth
for what this plugin actually does — and the same `Get-Lwg*` helpers the SessionStart banner calls,
so the two cannot drift.

Add `-Brief` for the summary line without the module table.

Two columns are easy to confuse and mean different things: **`ENABLED` is an intention; `STATE` is
the only column that reports behaviour.** An enabled-but-unbuilt module is not running and is not
coverage.

---

## `/lw-watchtower:doctor`

Nine checks: `plugin-manifest`, `marketplace`, `hooks-declared`, `config-registry`, `state-dir`,
`sessionstart`, `statusline`, `commands`, `agent-roles`.

`agent-roles` was missing from this list, and the count above read *eight*, until 3 August 2026 — on
a page the doctor's own slash command points the model at for what a row means. It is the check most
likely to FAIL on a fresh install, so the one row a stranger was most likely to be told about was the
one row this reference did not document. The script has never transcribed the number: it prints
`$script:Rows.Count`, and `tests/doc_claims.ps1` now reads the three phrasings on this page against
that header rather than against a sibling sentence.

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

Two of the nine checks exist because this repo has already shipped the bug they look for:

- **`state-dir`** fails when the state directory resolves to a *guess* rather than to the live
  directory — the defect that had the status line rendering unconditional green off an empty log.
  See [State directory](architecture.md#state-directory).
- **`config-registry`** fails when `config.json`'s module keys and the registry in `lib/common.ps1`
  disagree: a flag with no registry entry is a switch wired to nothing, and a registry entry with no
  flag is a module nobody can turn off.

**`agent-roles`** fails when `verification_gate` is enabled — it is on by default — and **zero**
verify-class roles are installed. That is a reachable state rather than a theoretical branch:
[`docs/uat-report.md`](uat-report.md) records the FAIL being deliberately provoked and confirmed. A module in that state is not off: it can nag and can never clear,
because it warns when the newest work-agent record is newer than the newest verify-agent record and
with no verifier there is never a verify record to be newer than. A role counts by its own
`lw-class: verify` frontmatter, or by a name in `module_config.verification_gate.verify_agents` that
has a role file on disk. The remedy is to restore `agents/lw-verifier.md`, install a role declaring
`lw-class: verify`, or switch `verification_gate` off. It is a **lower bound** and says so in its own
detail line: roles shipped by other plugins are not enumerable from here, so it can produce a
spurious FAIL and never a false PASS. See [Roles](roles.md).

`statusline` also reports **drift** between `~/.claude/statusline.ps1` and this repo's
[`statusline/statusline.ps1`](../statusline/statusline.ps1) as a warning. That copy is installed by
hand and the two can silently diverge.

### What a green doctor does not mean

It checks the plugin's *wiring*, not its *behaviour*. It does **not** establish that any advisory
fires, or that Claude Code has the plugin enabled in the current session — a hook can be flawlessly
configured and switched off. It cannot establish that anything is blocked: the two security gates
were removed on 30 July 2026, and the one `PreToolUse` gate registered since — `delegate_gate` —
ships switched off, so on a default install nothing here blocks anything. The script prints those
blind spots on every run, including the green ones.

**No command tests behaviour.** The one that did — `lw-watchtower:verify`, over a 233-case suite — was
removed with the destructive command gate. Nine behavioural test files survive it —
[`tests/gate_delegate.ps1`](../tests/gate_delegate.ps1) for `delegate_gate`, and eight more covering
the installer's `statusline` and hooks merge, the two `Stop` hooks, the uninstaller's deletions,
the evidence engine, two of the doctor's nine checks, the toggle's write to `config.json`, the
`SubagentStart` fast path and what the shipped payload discloses — and every one of them is run by CI and by hand, while **no command reaches any
of them.** So a green doctor is the only automated statement any *command* here makes about this
plugin, and it is a statement about wiring alone. Do not fill that gap with an inference.

---

## `/lw-watchtower:checklist`

**This command reports on the LW-WATCHTOWER project's own release plan. It does not report on your
repository, and no row it prints is a finding about your work.**

[`checklist.json`](../checklist.json) is this plugin's internal release audit. It ships inside the
plugin because the whole repository root is the payload — `.claude-plugin/marketplace.json` sets
`"source": "./"`, and that form has no exclusion mechanism — so if you installed LW-WATCHTOWER from
the marketplace, you received it, and running this command renders it on your machine. Forty rows
about somebody else's project, each formatted exactly like a finding about your own tree, is a
confusing thing to be handed; the command now says so in its own first four lines of output, on
every run. Read a `NOT STARTED` row as work outstanding *on this plugin*, never on your repository.

**Two of its rows make an authenticated `gh` request, as you, about a repository that is not
yours.** `P6-branch-protection` and `P8-visibility` query the maintainer's own repository, so a
`403` from either is a permissions answer about a repository you have nothing to do with — not a
problem with your credentials or your environment. Set `module_config.git_hygiene.use_gh` to
`false` to switch all four `gh` call sites off; [`install.md`](install.md) records the requirement.

Every item's state is **derived from evidence** by
[`bin/lwg-evidence.ps1`](../bin/lwg-evidence.ps1) — a commit, a file on disk, an exit code, or a CI
conclusion — never from a claim written into the plan.

**`unverified` is not a synonym for incomplete.** It means no probe could establish the item either
way, and it is rendered as its own state precisely so that "done" and "nobody checked" cannot be read
as the same thing. An item the probes cannot reach says so and names what it could not read.

**A `DONE` row whose caveat limits it renders `[x*]`, not `[x]`.** The caveat itself was always
printed; what was missing is that a reader scanning the tick column never reached it, so a section
headed with a goal its own items say was *not* met read as met. Sections holding such rows are
annotated at the heading with how many. This is presentation only — no state and no evidence rule
depends on the glyph.

---

## `/lw-watchtower:sitrep`

Work in flight, work finished since the last sitrep, blockers, decisions awaiting you, and current
governance state — off the same evidence probes as the checklist.

Two things it will not do: it does not report anything it could not determine as clear, and it
**separates verified from reported**. Something a subagent claimed and something the probes confirmed
appear under different headings.

Running it moves the "last sitrep" watermark. `--no-mark` reads without moving it.

---

## `/lw-watchtower:setup`

The guided installer, for someone who has never heard of a hook, a glob or a JSON key.

**The model is the interface, not the installer.** Every decision, rule, path and diff comes out of
[`bin/lwg-setup.ps1`](../bin/lwg-setup.ps1); the command prose only puts its questions to the
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

The module switchboard, and the only supported way to change `config.json`'s `modules` block without
hand-editing it.

Run with no arguments it reports what is currently on. To change something it is run **twice**: once
without `-Apply`, which prints the exact diff and states what the change does to your coverage, and
once with, which writes it. `-Scope repo` writes an override for the current repository only.

It refuses rather than guesses: a key that is not in the registry in [`lib/common.ps1`](../lib/common.ps1)
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

## `/lw-watchtower:resolve`

Marks one session's outstanding health faults resolved, and is the command
[`lw-healer`](roles.md)-shaped agents run.

**Always `-List` first**, and only pass `-Note` after the operator has seen which faults would be
cleared. Both the data directory and the session id are **pinned explicitly** rather than inferred,
because the defect this replaced did exactly that inference and wrote a `Resolved` marker into the
wrong file for the wrong session, taking the status line back to green while the fault stood. If it
cannot pin both, it refuses and says which one it could not resolve.

---

## The three preference commands, and what each one actually does

`verbosity`, `plain` and `delegate` all run the same script,
[`bin/lwg-toggle.ps1`](../bin/lwg-toggle.ps1), with a different `-Flag`. They differ only in which key
they write and which sentence they print about enforcement, and a second copy of the
read/validate/write/report path would be a second thing to keep correct. The per-flag facts live in
one table at the top of that script.

Each one, with no argument, **reports** and changes nothing. With an argument it writes the global
default; with a trailing `repo` it writes an override for this repository only.

**Two of the three are booleans and take `on` or `off`.** Anything else — `true`, `1`, `yes`,
`enable` — is **rejected** with a usage message and exit `2`, and nothing is written. A toggle that
guesses what you meant is a toggle you cannot be sure you set.

**`verbosity` is the third, and it is a level rather than a switch.** It takes one of `brief`,
`default` or `verbose` **by name**; `on`, `off`, `short`, `long` and `terse` are rejected the same
way, for the same reason.

**Every run prints one of two blocks, and the heading is chosen by the flag.** A flag that is
enforced prints `ENFORCED`, naming what it blocks and what turning it on costs; a flag that is not
prints `NOT WIRED`. There is no default branch: a heading is the first thing read, so an unwired
switch printing `ENFORCED` — or a wired one printing `NOT WIRED` — would be the loudest lie this
command could tell about itself.

### `verbosity` is one key with three levels

`output_style.verbosity` holds exactly one of `brief`, `default` or `verbose`. Setting a level
unsets the others by construction — there is no state in which two are active — and `default` is
the level at which this axis does nothing. It is the off position, not a fourth thing.

| You run | The key becomes | Because |
| --- | --- | --- |
| `/lw-watchtower:verbosity brief` | `brief` | the argument is the value |
| `/lw-watchtower:verbosity verbose` while it reads `brief` | `verbose` | one key, one value — the `changed` line prints `'brief' -> 'verbose'` |
| `/lw-watchtower:verbosity default` | `default` | the axis is switched off; nothing else has to be said about the other two |
| `/lw-watchtower:verbosity brief repo` | `brief` **here only** | a per-repo override is created, and the `changed` line names the global level it was inherited from |

**This was two commands until 30 July 2026.** `lw-watchtower:brief` and `lw-watchtower:verbose` — written
without a leading slash here because neither command file exists any more, and
[`bin/lwg-doctor.ps1`](../bin/lwg-doctor.ps1)'s `commands` check fails on a `/lw-watchtower:<name>`
reference with nothing behind it — wrote this same single key. `on` claimed it and `off` released it
to `default`, but only when the command being switched off was the one holding the key: so
`brief off` while the key read `verbose` correctly wrote **nothing at all**, and the script had to
explain that on every run. Two switches over one three-value setting describe a model that is not
there, and the explanation was the tell. **Nothing about the stored value changed in the merge** — a
`config.json` written by the old pair is read identically by the new command.

**Two independent booleans were rejected, and not on taste.** A per-repo override under `repos` is
merged *key by key*, so `brief` could have been `true` globally while `verbose` was `true` for one
repository — a contradiction assembled from two writes that were each valid on their own, which no
write-time exclusivity rule inside the script could have prevented. Exclusivity enforced by a writer
holds only where that writer runs; it survives neither a hand edit nor a merge. One key holding one
value cannot contradict itself at any scope. Any other value in that key is **ignored and named as
unrecognised** on the next run, never coerced quietly into one of the three.

**A stale `output_style.brief` key is named too.** `verbosity` replaced an older boolean of that
name, and nothing reads the old key any more. So a config written before that change states a
preference that no longer applies, at either scope. `/lw-watchtower:verbosity` prints an `OBSOLETE KEY`
block naming the scope, the full path — `repos["owner/name"].output_style.brief` when the stale copy
is inside a per-repo override — and its value, and says plainly that it is being ignored rather than
honoured. **Nothing is rewritten.** The key is not deleted and not migrated: a migration would have
to guess whether the old `false` meant `default` or `verbose`, and deleting a key on your behalf
when you asked only to *read* a setting is a worse surprise than the stale key itself. Set the level
by name, then delete the old key by hand.

`plain` is a genuinely independent axis — jargon, not length — and stays its own boolean and its own
command. Verbosity × plain is six combinations, which map onto five shipped style files plus the
built-in Default — see [Output styles](output-styles.md).

| Exit | Meaning |
| --- | --- |
| `0` | the state was reported, or changed and reported |
| `2` | the argument was not one the flag accepts — `on`/`off` for a boolean, a level name for `verbosity` — or `-Scope repo` was used outside a repo. **Nothing was written** |
| `3` | `config.json` could not be read, could not be written, or would not have parsed afterwards. **Nothing was written** |

**`verbosity` and `plain` are not modules, and must never become modules.** They are absent from
`$LwgModuleRegistry` and from `config.json`'s `modules` block for the same two reasons the output
styles are (see [Why they are not modules](output-styles.md#why-they-are-not-modules)):
`Get-LwgConfig` fails *open*, which would switch a preference **on** when the config is corrupt — the
wrong polarity for anything that is not a guardrail — and the banner's `n/10` counts governance
coverage, which an answer-formatting preference is not. They live in the `output_style` block, read
through a `Get-LwgModuleOption`-shaped accessor that returns the built-in default when the key is
absent. Running either changes the module count by nothing.

**`delegate` is the exception, and it is in the registry.** It is a gate, which is governance in its
strongest form, so `delegate_gate` is a registry entry of `kind = 'gate'` and the banner counts it —
the total is **10**, and `9/10 active` with the gate off is the honest reading rather than a fault.
What stayed *out* of the `modules` block is its **flag**: the registry entry declares
`switch = @{ block = 'interaction'; key = 'delegate' }`, so `interaction.delegate` is the one and only
switch. A second flag in `modules` would let you run `/lw-watchtower:delegate on` and have the gate stay
silent because the other flag was false — a switch wired to nothing, which is the founding defect
this plugin exists to catch. [`bin/lwg-doctor.ps1`](../bin/lwg-doctor.ps1)'s `config-registry` check
knows about the exemption and asserts the declared key really exists, and fails if both spellings are
present at once. Because the flag is outside `modules`, it does **not** inherit the fail-open
polarity: an unreadable `config.json` leaves the gate **off**, which is what keeps a bad config a
nuisance rather than a lockout.

**`config.json` is edited surgically, not round-tripped.** PowerShell 5.1's `ConvertTo-Json` rewrites
an apostrophe and an angle bracket into six-character `\uXXXX` escape sequences, and roughly 60 % of
`config.json` is explanatory `$comment` prose full of both — 126 apostrophes at the time of writing.
A single toggle would have rewritten every one of those comments into escape sequences, and produced
a whole-file diff for a one-word change. So the script walks the text with a string-and-escape-aware
scanner and replaces exactly one value, or inserts exactly one member. It then parses the **result**
with `ConvertFrom-Json` and only writes the file if that parse succeeds, so a bad edit leaves
`config.json` untouched rather than needing to be undone. That matters more here than anywhere else
in this repo: `Get-LwgConfig` fails open, so a `config.json` this command corrupted would switch every
module **on**.

### What is actually wired, and what is not

This is the part to read before treating any of the three as a control. **Two record a preference and
enforce nothing. One really blocks.**

| Command | Behaviour exists? | Activated by this command? | Enforced? |
| --- | --- | --- | --- |
| `verbosity` | **yes** — [`lw-watchtower-brief.md`](../output-styles/lw-watchtower-brief.md) and [`lw-watchtower-verbose.md`](../output-styles/lw-watchtower-verbose.md); level `default` is the built-in style | **no** — one manual step remains | no; an output style is advisory, and always was |
| `plain` | **yes** — [`output-styles/lw-watchtower-plain.md`](../output-styles/lw-watchtower-plain.md) | **no** — one manual step remains | no |
| `delegate` | **yes** — [`lib/gate_delegate.ps1`](../lib/gate_delegate.ps1) | **yes** — the write takes effect on the next tool call, with no restart | **yes** |

**`verbosity` and `plain` do not switch a style on.** The style Claude Code applies is the `outputStyle`
key in a settings file, and **nothing in this plugin writes that key**. Two reasons, both deliberate:
a settings file is not part of this plugin, and the `/config` picker already owns that value and
writes whatever string the installed plugin actually needs — a string
[this repo has not confirmed against a live install](output-styles.md#frontmatter-and-what-is-verified),
since a plugin-supplied style may or may not be namespaced in it. So the command records the
preference, works out which of the five style files the two axes imply, **reads** the `outputStyle` key out
of the project and user settings files and prints what it currently says, and tells you to run
`/config`. It also states, every time, that the change cannot take effect in the current session: an
output style is read into the system prompt once, at session start.

So what `verbosity` and `plain` do is record a preference and have the slash command state the
resulting instruction to the model, which may honour it and which **nothing checks**. That is written
here, in each `commands/*.md`, and in a `NOT WIRED` block the script prints on every single run —
because *a switch wired to nothing, reporting green, is the founding defect this plugin exists to
catch*.

**`delegate` IS enforced, and it is the only thing in this plugin that is.** Turning it on arms
[`delegate_gate`](modules.md#delegate_gate) — [`lib/gate_delegate.ps1`](../lib/gate_delegate.ps1), a
`PreToolUse` hook on `Edit|Write|NotebookEdit|Bash|PowerShell` — which refuses those five tools for any call
that did not come from a subagent. The refusal is real: a `PreToolUse` deny is honoured **even under
`permissions.defaultMode: "bypassPermissions"`**, so for anyone running in that mode this is a
stronger layer than a `permissions.deny` rule. It takes effect on the very next tool call; there is
nothing to restart.

**Read this before turning it on.** With the gate armed, `/lw-watchtower:delegate off` **will not turn it
off**, because this command runs its script through `Bash` and `Bash` is one of the five tools
refused. There is deliberately no exemption for it — an exemption for "the command that turns me off"
is a named bypass, and one named bypass is an argument about which others deserve one. The two ways
back:

1. Have a **subagent** run `/lw-watchtower:delegate off`. Its calls carry `agent_id` and are allowed.
2. Set `interaction.delegate` to `false` in [`config.json`](../config.json) by hand.

**What it still does not do.** It refuses nothing a subagent does, and it never checks that a
dispatch was any good. Delegation is enforced; delegating *well* is not, and describing it as
supervision, review or safety would be exactly the overstatement this page exists to avoid.

**There is no argument that deletes a per-repo override.** `on`, `off` and nothing at all are the
only three things you type; a fourth verb that removes a key is a fourth thing to get wrong. When an
override exists the script says where it is, and you delete the entry from `config.json` by hand to
fall back to the global default.

---

## No manifest entry is needed

`commands/` is **auto-discovered** from the plugin root; so are `agents/`, `skills/` and
`output-styles/`. [`.claude-plugin/plugin.json`](../.claude-plugin/plugin.json) was **not** changed
to add the command surface and must not be — naming `commands` in the manifest *replaces* the
default directory scan rather than adding to it, so declaring it would at best change nothing and at
worst hide the very files it names.

Verified against Claude Code 2.1.220 with `claude plugin validate --strict`, which walks and parses
every discovered command, and end-to-end by loading the repo into a live session with
`claude --plugin-dir` and invoking `/lw-watchtower:status`.

`bin/` **is** added to the Bash tool's `PATH` while the plugin is enabled. Nothing here relies on
it: a `.ps1` is not executable as a bare command on `PATH`, and it would have to be launched through
`powershell -File` regardless. So each command invokes its script by absolute path through
`${CLAUDE_PLUGIN_ROOT}`, which is expanded in command bodies. The `PATH` entry is added whether or
not the directory exists, so its presence is not evidence that anything is installed in it.
