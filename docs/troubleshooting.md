# Troubleshooting

Start here:

```
/lw-watchtower:doctor
```

It runs nine checks and **is built to be able to fail**. A non-zero exit is a real finding, not a
glitch — and `2` (warnings, no failures) is the ordinary result on a machine where the status line
has not been installed. See [Commands](commands.md#lw-watchtowerdoctor) for the exit codes.

Remember what a green doctor does **not** mean: it checks the plugin's *wiring*, not its
*behaviour*. It does not establish that any advisory fires, or that Claude Code has the plugin
enabled in the current session. It cannot establish that anything is blocked, and on a default
install there is nothing to establish: `destructive_gate` and `secret_scan` went on 30 July 2026 and
**nothing here inspects a command, a path or a credential**. One `PreToolUse` gate does ship —
`delegate_gate`, which refuses `Edit`, `Write`, `NotebookEdit`, `Bash` and `PowerShell` for calls
that did not come from a subagent — and it is **off by default**, so a green doctor says nothing
about whether it would refuse anything if you armed it. See
[Both gates were removed](modules.md#both-gates-were-removed) and
[`delegate_gate`](modules.md#delegate_gate).

---

## Nothing appears at session start

**No banner, no `HH` segment.**

1. Confirm the plugin is discovered. Under a junction install, the folder at
   `%USERPROFILE%\.claude\skills\lw-watchtower` must contain `.claude-plugin/plugin.json`. Under a
   marketplace install, check `/plugin`.
2. Confirm hooks are registered: `/lw-watchtower:doctor` → `hooks-declared`.
3. Confirm the interpreter. Every hook launches `powershell` — Windows PowerShell 5.1. If your `PATH`
   resolves `powershell` to something else, or to nothing, no hook runs at all.
4. The `HH` segment is the **status line**, which is a separate install and is not part of the
   plugin. See [Install § status line](install.md#installing-the-status-line-optional-and-separate).
   A `GM` segment was named here until 3 August 2026; it was deleted on 30 July 2026 with the trip
   ledger it read, so no status line renders one and its absence is not a symptom.

## The banner says `unverified`

`self_health` is switched off in [`config.json`](../config.json), so the self-check did not run.
**Nothing failed and nothing was checked.** Set `self_health: true` and start a new session.

## The banner says `degraded`

The self-check **ran and failed**. Governance may not fire; do not rely on it. The banner and the
model-visible context name the failing probe. The most common cause is a state directory that could
not be written — see [state-dir reports UNRESOLVED](#state-dir-reports-unresolved).

## The banner says `observe-only`

**Expected as shipped.** `observe-only` means no gate is **live**, so nothing can be blocked. One
gate does ship — `delegate_gate` — and it is switched off, which is where it is meant to be. The two
older gates were removed on 30 July 2026 by explicit owner decision and are not coming back; see
[Both gates were removed](modules.md#both-gates-were-removed).

Switching an observing module off does **not** change the word — `mission_drift: false` changes
`9/10 (1 off)` to `8/10 (2 off)` and leaves the mode at `observe-only`, because the mode ladder tests
the live gate count first. **The one setting that does change it** is
`/lw-watchtower:delegate on`, which arms the gate: the mode then reads `enforcing`, or `partial` if
anything else is switched off. Read [`delegate_gate`](modules.md#delegate_gate) before running it —
it cannot be turned off again from the main thread.

## The banner says `partial` or `enforcing`

Then `delegate_gate` is **armed**, and `Edit`, `Write`, `NotebookEdit`, `Bash` and `PowerShell` are being refused
on the main thread. That is not a fault; somebody ran `/lw-watchtower:delegate on`, or
`interaction.delegate` is `true` in `config.json` — possibly only for this repository, under
`repos[slug]`. To undo it, have a **subagent** run `/lw-watchtower:delegate off`, or set the key back to
`false` by hand; the command cannot do it from the main thread, because it runs through `Bash`.
Check that the session actually loaded the tree you think it did — under a marketplace install the
plugin is a *copy* and an edit to your clone does nothing until `claude plugin update`, and running
both install routes at once gives you two live copies. `/lw-watchtower:doctor` reports which is wired up.

## The banner says `inert`

No implemented module is enabled at all. Nothing is running. That is a configuration state: check
the `modules` block in `config.json`.

---

## `state-dir` reports UNRESOLVED

This is the one to take seriously. It means every log write is going to a directory the live plugin
never reads.

The state directory is `$CLAUDE_PLUGIN_DATA`, which **only a hook receives**. The status line,
`lib/resolve.ps1` and any out-of-harness run are not hooks and must discover it instead. See
[State directory](architecture.md#state-directory) for the resolution order.

If discovery reports `unresolved`, no suffixed candidate was found under
`~/.claude/plugins/data`. That usually means the plugin has never been loaded by Claude Code on this
machine — start a session with it enabled once, and the harness creates the directory.

**There is a second cause on any machine that ran this plugin before 3 August 2026**, and it looks
identical. The product was renamed from `lw-gmhh` to `lw-watchtower` that day. The data directory's
name comes from the plugin id, so it moved: discovery now looks for `lw-watchtower*` and the old
`lw-gmhh*` directory is not a candidate and never will be. **Nothing migrates it, and no data was
deleted** — the old directory and its `lw-gmhh.jsonl` are exactly where they were. What you lose is
continuity, not records: the status line, `/lw-watchtower:sitrep` and the health count all start
from empty. `/lw-watchtower:uninstall` still finds and reports the old directory, marked `LEGACY`,
so removing this plugin does not strand it. The whole of what the rename does and does not move is
written out under `## [0.4.0]` in [CHANGELOG.md](../CHANGELOG.md).

## The status line shows dim `HH-` / `GM-`

Nothing about this session was found to read. **This is not an all-clear.**

For `GM-` this is now the normal state and not a symptom — see
[The `GM` segment has gone from the status line](#the-gm-segment-has-gone-from-the-status-line).

For `HH-`, either no hook has written a record for this session id yet, or the status line is
reading a different directory than the hooks are writing to. Run `/lw-watchtower:doctor` and check
`state-dir` and `statusline`.

## The status line shows purple `HH?` or `HHx`

Neither is a fault count and neither is an all-clear. **Both mean the health system could not tell
you anything**, and they differ in why:

| Glyph | What it actually means |
| --- | --- |
| green `HH` | the health logs were read and this session is clean |
| **purple `HH?`** | **`lib/supervisor.ps1` or the healer role was not found on any candidate path** — the machinery that would answer the question is not installed |
| **purple `HHx`** | **a log file exists and could not be read** — the machinery is here and the evidence would not open |

Every state on that row carries a glyph as well as a colour, so the text alone is enough: red is
`HH`*n* with the fault count, dim is `HH-` with a trailing hyphen precisely so that "nothing was
found to read" cannot be mistaken for "clean", and a trailing `!` marks a record too large to parse.
Note that `!` and `x` are different: `!` means part of the log was skipped and a verdict was still
reached, `x` means no verdict was reachable.

**Before 1 August 2026 both purple states rendered a bare `HH`** — the identical three characters as
the green all-clear — so on a remapped terminal palette, a monochrome or high-contrast profile, or in
a screenshot, a plugin that had established nothing rendered as one reporting good health. That was
the exact thing [Architecture](architecture.md#status-line) says an indicator here must never do. If
you are reading a bare purple `HH` on a machine today, the installed copy at
`~/.claude/statusline.ps1` is stale — re-copy it, and see
[`doctor` warns about status-line drift](#doctor-warns-about-status-line-drift) below.

For `HH?`, install or re-copy what is missing. For `HHx`, the log named by `/lw-watchtower:doctor`'s
`state-dir` row is unreadable — check its permissions and whether another process holds it open. In
both cases, to answer "is the health system working", run:

```
/lw-watchtower:doctor
```

The doctor cannot express a fault by colour — it has to print `[FAIL]` or `[WARN]` and a row name —
so its `state-dir`, `sessionstart` and `statusline` rows tell you whether the health system is
working. A green `HH` you have not corroborated is worth less than the doctor's exit code.

## `doctor` warns about status-line drift

`~/.claude/statusline.ps1` and this repo's [`statusline/statusline.ps1`](../statusline/statusline.ps1)
are two independent files and nothing keeps them in step. Re-copy in whichever direction is correct
and compare hashes — see
[Install § this is a copy](install.md#this-is-a-copy-and-it-can-drift).

---

## Something was blocked and I think this plugin did it

**Check the message first: if it begins `LW-WATCHTOWER delegate_gate:`, then it did.** That is
`delegate_gate` refusing `Edit`, `Write`, `NotebookEdit`, `Bash` or `PowerShell` because the call came from the
main thread and `interaction.delegate` is on. The fix is to dispatch a subagent to do the work, or to
turn the gate off — see [The banner says `partial` or `enforcing`](#the-banner-says-partial-or-enforcing)
just above, and [`delegate_gate`](modules.md#delegate_gate).

**Anything else did not come from here.** That is the only hook this plugin registers that can block,
it looks at nothing except whether the caller was a subagent, and it is off by default. Nothing here
inspects a command, a path or a credential. See
[Both gates were removed](modules.md#both-gates-were-removed).

A denial from anywhere else comes from one of two places, and the message tells you which:

| Source | How to recognise it | What to do |
| --- | --- | --- |
| your own `permissions.deny` in `~/.claude/settings.json` | the CLI names the matching rule pattern | edit or remove that rule. On a machine set up before 30 July 2026 these may well be rules `/lw-watchtower:setup` wrote at the time — it no longer writes any, and it never removes one |
| Claude Code itself | a permission prompt, a mode restriction, or a built-in refusal | nothing in this plugin is involved |

Setting `secret_scan: false` is not an unblock and not a key: there is no such module any more, and
`/lw-watchtower:config` will reject the name because it is not in the registry.

## Something was NOT blocked and I think it should have been

**Read the next two paragraphs in order — the answer is different depending on which of the two
things you mean.**

*If you mean the content, the path or the command:* there is no gap to file, because that whole
surface is gone rather than leaky. Specifically, and by removal rather than by design: **no shell
command is inspected**, no write to a credential path is refused, no write carrying a credential is
refused, no write inside `.git/` is refused, and the installer adds no `permissions.deny` rule that
would refuse any of them. That is a documented state, not a regression, and not a security report.

*If you mean `delegate_gate`:* **that is a gap, and it is a bug report.** One `PreToolUse` gate does
ship. It is off by default, and when `interaction.delegate` is on it refuses `Edit`, `Write`,
`NotebookEdit`, `Bash` and `PowerShell` for any call that did not come from a subagent. If you armed
it and one of those reached the main thread anyway, file it — that is exactly the class of report
this repository exists to receive, and the bug form has an entry for it. The gate decides on the
*caller* and reads no path, command or content, so it is not the answer to the paragraph above and
never will be.

What is also a security report: a defect in what this plugin *does* do — a log record leaking an
unredacted credential, for example. See [SECURITY.md](../SECURITY.md).

If you want any of it back, the layer to write is `permissions.deny` in your own `settings.json`.
The CLI evaluates it itself and it cannot fail open. This plugin will not write it for you.

## The `GM` segment has gone from the status line

Removed on 30 July 2026, deliberately. Row 1 now reads `model  HH  ORC  ctx  5h  7d  #branch  PR#
owner/repo` — if yours still shows `GM`, you are running an older copy of `statusline/statusline.ps1`
than the one in this repo, and `/lw-watchtower:doctor` will say so under `statusline`.

`GM` read the per-session trip ledger. Both gates went earlier that day, so nothing could write a
trip; the ledger files were then backed up and removed too. With no ledger anywhere, `GmState` could
only ever return `none` and the segment could only ever render the dim `GM-`. An indicator that can
report exactly one value reports nothing, so it was deleted rather than left as decoration.

Nothing was lost with it. `HH` still reports health faults, and historical gate denials are still in
`lw-watchtower.jsonl` where `/lw-watchtower:sitrep` counts them under `GOVERNANCE`. There is no longer any
command that opens them one at a time — that was `lw-watchtower:tripped`, removed in the same change.

---

## An advisory keeps firing / never fires again

Every advisory fires **on a change, not on a state**, and stores its dedupe position in
`advisory-<session>.json` in the state dir. A condition that stays true does not repeat at every turn
end. Once the condition clears, the stored signature is cleared too, so it will warn again if it
comes back.

## `git_hygiene` says the tree state is UNKNOWN

git did not answer — it is missing, timed out, or exited nonzero. **Do not read this as a clean
tree.** Raise `module_config.git_hygiene.timeout_ms` if the repo is large enough that 1 500 ms is
genuinely too short, or check `git status` by hand.

## Turn end feels slow

Measured figures and where the time goes: [Turn-end cost](architecture.md#turn-end-cost). The
short version — the remaining cost above the interpreter floor is PowerShell 5.1 engine warm-up, not
data work, and the two `Stop` hooks run **in parallel**, so turn end costs the max and not the sum.

The one avoidable network cost is `git_hygiene`'s `gh` call. Set
`module_config.git_hygiene.use_gh` to `false` to remove it.

## `context_pressure` shows no percentage

Deliberate. The computed occupancy exceeded the resolved window size, which makes the figure
arithmetically impossible, so the denominator is wrong. The module suppresses the percentage rather
than report a false `100% CRITICAL`, and logs `ContextWindowUnknown` naming the model to add to
`module_config.context_pressure.window_tokens`.

## `verification_gate` nags about work I verified myself

Despite the name it is **not a gate** and never was — it is an advisory on `Stop` that warns and
never blocks.

It sees **subagents only**, via `SubagentStop` records. Verification you did yourself leaves no
record. Tune `module_config.verification_gate.work_agents` and `verify_agents`, or switch the module
off. Its full blind-spot list is in [Modules](modules.md#verification_gate).

---

## The verify command is gone

`lw-watchtower:verify` and the 233-case suite behind it were deleted on 30 July 2026 with the destructive
command gate. There is no replacement, and no command in this plugin tests behaviour. `/lw-watchtower:doctor`
is a sub-second **wiring** check — use it, while being clear that wiring is not behaviour. See
[Testing](testing.md).

The `permissions.deny` parity test went the same day with `secret_scan`. **Thirteen test files remain**,
and **ten of them test behaviour**: `tests/gate_delegate.ps1` (the one gate), `tests/setup_merge.ps1`
(the installer's `statusline` merge and what its `hooks` section decides),
`tests/stop_behaviour.ps1` (the two turn-end hooks),
`tests/uninstall_footprint.ps1` (the uninstaller's state-data deletions),
`tests/evidence_states.ps1` (the evidence engine), `tests/doctor_behaviour.ps1` (two of the doctor's
nine checks), `tests/toggle_behaviour.ps1` (the toggle's write to `config.json`),
`tests/subagent_scan.ps1` (the `SubagentStart` fast path) and `tests/payload_guard.ps1` (what the
shipped payload discloses). The other three — `tests/workflow_guard.ps1`,
`tests/portability_scan.ps1` and `tests/doc_claims.ps1` — check tracked files and their stated
counts, and assert nothing about behaviour. **None of the eight is reachable from a command**; they
are run by CI and by hand, which is why no command here can tell you whether this plugin works.

---

## Reporting a problem

- Bugs and feature requests: [issues](https://github.com/LEAPWare-Software/LEAPWare-Watchtower/issues), and
  see [CONTRIBUTING.md](../CONTRIBUTING.md).
- A leaked secret, or a defect in what this plugin *does* do — an unredacted credential reaching a
  log record, say: **[SECURITY.md](../SECURITY.md)** — do not open a public issue.
- **A gate bypass is not a security category here.** Nothing inspects a command, a path or a
  credential, and the installer writes no `permissions.deny` rule. The one gate, `delegate_gate`,
  refuses main-thread work as a **discipline**: a subagent can do everything it refuses, by design,
  so getting past it is not a vulnerability. An action this plugin does not refuse is the documented
  state. A `delegate_gate` that failed **open** — permitting a main-thread call while the switch was
  on — is an ordinary bug: open an issue with the payload shape that did it.
