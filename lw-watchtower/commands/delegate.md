---
description: "Reserve the chat session for talking to the operator and send all work to subagents. Off by default. ENFORCED by a PreToolUse gate that refuses Edit, Write, NotebookEdit, Bash and PowerShell on the main thread"
argument-hint: "[on|off] [repo]"
allowed-tools: "Bash(powershell:*)"
disallowed-tools: "PowerShell"
---

Run this command and show the user its output **verbatim**:

Run this through the **Bash** tool. Do not use the PowerShell tool: its validator refuses any command that launches `powershell`, so every attempt costs the operator a permission prompt and then falls back to Bash anyway.

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/bin/lwg-toggle.ps1" -Flag delegate
```

Append `$1` as the value when one was given — `on` or `off`. Pass **nothing** when the user only
asked what the setting is. Append `-Scope repo` if they scoped it to this repository only (they
said "here", "this repo", or typed `repo` as the second word); otherwise the write is global.

Do **not** translate anything else into `on` or `off`. If they typed something the script does
not accept, let the script reject it and print its usage — that rejection is the feature.

**Then honour the instruction the script printed under `IN EFFECT FROM NOW ON`, for the rest of
this session.**

Rules for reporting it:

- **Report the `ENFORCED` block in full and do not soften it.** `delegate` is the one switch in
  this plugin that really blocks. With it on, [`lib/gate_delegate.ps1`](../lib/gate_delegate.ps1) —
  a `PreToolUse` hook on `Edit|Write|NotebookEdit|Bash|PowerShell` — refuses those five tools for any call
  that did not come from a subagent, and a `PreToolUse` deny is honoured even under
  `permissions.defaultMode: "bypassPermissions"`.
- **Warn before turning it ON, every time, in the same breath as confirming it.** With the gate
  armed, `/lw-watchtower:delegate off` **will not turn it off again**, because this command runs its
  script through `Bash` and `Bash` is one of the five tools refused (so is `PowerShell` — switching shell is not a way round it). There is deliberately no
  exemption for it. The way back is to have a **subagent** run `/lw-watchtower:delegate off`, or to
  set `interaction.delegate` to `false` by hand in `config.override.json` under the state directory -
  `$CLAUDE_PLUGIN_DATA`, or `~/.claude/plugins/data/lw-watchtower*/`. **Not in `config.json`**: that
  file is the shipped defaults, and an edit there changes nothing while the override still says
  `true`. If no override file exists, the gate is off already and there is nothing to turn off.
- **A worker cannot see this conversation.** With the flag on, every dispatch has to restate the
  context, the absolute paths, the definition of done and the prohibitions — the script prints
  this, and it is the part that actually determines whether delegating works.
- **What it still does not do.** It refuses nothing a subagent does, and it does not check that a
  dispatch was any good. Delegation is enforced; delegating *well* is not. Do not describe it as
  supervision, review or safety.
- **It is a module.** `delegate_gate` is in `$LwgModuleRegistry` with `kind = 'gate'` — the only
  entry that is — so the banner counts it and the live-gate count moves with this switch. Its flag
  stays out of the `modules` block on purpose: one gate, one switch. `/lw-watchtower:doctor` reports
  gates *shipped* and gates *live* as separate numbers.
- The exit code is the verdict: `0` reported or changed, `2` the argument was rejected and
  **nothing was written**, `3` the toggle could not complete and the settings file was not changed -
  and `config.json` in the plugin root is untouched on every path, because no path writes it.
