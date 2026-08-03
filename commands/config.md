---
description: "LW-WATCHTOWER module switchboard - turn a governance module on or off, globally or for one repo, after being told exactly what the change does"
allowed-tools: "Bash(powershell:*)"
---

To show the operator what is currently on, run this and show the output **verbatim**:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/bin/lwg-config.ps1"
```

To change something, run it **twice**. First without `-Apply`:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/bin/lwg-config.ps1" -Module <name> -On|-Off
```

Show that output, wait for the user to agree, then re-run the identical command with `-Apply`
appended. Scope it with `-Repo <owner/name>` or `-ThisRepo` for a per-repo override, and
`-Clear -Repo <owner/name>` to drop an override so the module falls back to the global flag.

The script is the answer. It reads `$LwgModuleRegistry` in `lib/common.ps1` - the source of
truth for what this plugin actually does - and edits `config.json` surgically, leaving every
explanatory comment in the file intact.

Rules for reporting it:

- **Show the WHAT THIS DOES block before asking for confirmation, in full.** It states the
  current value, the value after, the file that carries the behaviour, and what stops or starts
  happening. That block is the point of the command; summarising it to "turning off X" throws
  away the part the user needs to decide.
- **Do not paraphrase a refusal into a limitation of yours.** Exit `1` means the script declined
  and printed why - most often because the module is declared in `config.json` but has no code
  behind it. Say which modules those are, in its words. Never offer to edit `config.json` by
  hand instead: enabling a name with nothing behind it is the exact defect this plugin exists
  to catch, and doing it manually is the same lie with an extra step.
- **`-Apply` is not implied.** If the user said "turn off git_hygiene", that is a request to
  show them the effect first. Do not run `-Apply` in the same breath unless they have already
  seen the preview or explicitly asked for the change to be made now.
- **Exit `2` is a fault, not a success with a caveat.** It means the file was written and the
  effective value is still not what was asked for. Report it as broken, name the backup path
  the script printed, and do not describe the change as done.
- **Repeat the WHEN line.** A flag lands on the next hook event, but the SessionStart banner,
  the mode word and the status line keep reporting the old picture until a new session starts.
  A user who turns something off and sees the old banner will otherwise think the command failed.
- If the script says the config is on **BUILT-IN DEFAULTS**, every operator choice in the file
  is already being ignored. That is a `config.json` that does not parse - route to
  `/lw-watchtower:doctor`, do not attempt a write.

This command changes an INTENTION. Whether the intention is doing anything is a separate
question: `/lw-watchtower:status` reports what is actually active. **Every module you can switch here is
an observer**, and turning one on starts a warning, never a refusal — **nothing in this repo tests
that any of those warnings fires.** `destructive_gate` and `secret_scan` were removed on 30 July
2026 at the owner's instruction, along with the regression suite, the deny parity test and the
`lw-watchtower:verify` command that ran them.

**The one gate is not switchable from here, and that is deliberate.** `delegate_gate` is switched by
`interaction.delegate`, which is not a `modules` key, so this command cannot reach it: one gate has
exactly one switch, and it is `/lw-watchtower:delegate`. If the operator asks how to turn blocking on or
off, send them there rather than looking for a module flag that does not exist.
