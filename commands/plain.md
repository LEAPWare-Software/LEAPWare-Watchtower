---
description: "Plain English on or off - no unexplained tooling jargon. Reports the current state when called with no argument. This records the preference; activating the output style is a manual step the script spells out"
argument-hint: "[on|off] [repo]"
allowed-tools: "Bash(powershell:*)"
---

Run this command and show the user its output **verbatim**:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/bin/lwg-toggle.ps1" -Flag plain
```

Append `$1` as the value when one was given — `on` or `off`. Pass **nothing** when the user only
asked what the setting is. Append `-Scope repo` if they scoped it to this repository only (they
said "here", "this repo", or typed `repo` as the second word); otherwise the write is global.

Do **not** translate anything else into `on` or `off`. If they typed something the script does
not accept, let the script reject it and print its usage — that rejection is the feature.

The script is the answer. It reads and writes `config.json` itself and re-reads the file from
disk before reporting, so the value it prints is the value a hook would load.

Rules for reporting it:

- **`plain` is a preference, not a module.** It is deliberately absent from the module registry
  and from `config.json`'s `modules` block, so it does not appear in the banner's `n/10` and the
  governance count is unchanged. Do not describe setting it as enabling a module.
- **Setting the flag does not switch the style on**, and the script says so under `ACTIVATION`.
  Report that block in full. The style Claude Code applies is the `outputStyle` key in a settings
  file; nothing in this plugin writes that key. The operator has to run `/config` and choose
  **Output style** themselves.
- **`plain` combines with the verbosity setting into one file.** `plain` is an independent axis
  from `output_style.verbosity` (`brief` / `default` / `verbose`), and `outputStyle` is a single
  string, so the six combinations map onto five shipped files plus the built-in Default: with
  `plain` on the style to select is `lw-watchtower-brief-plain`, `lw-watchtower-plain` or
  `lw-watchtower-verbose-plain` depending on the verbosity. The script works out which of the five
  names applies and prints it; do not compute it yourself.
- **It will not take effect in this session, whatever the user does next.** An output style is
  read into the system prompt once at session start. `/clear` or a new session is required, and
  `/clear` discards the conversation.
- **Output styles reach the main conversation only.** A subagent runs its own system prompt, so
  dispatched workers answer in their own voice regardless.
- The exit code is the verdict: `0` reported or changed, `2` the argument was rejected and
  **nothing was written**, `3` the toggle could not complete and `config.json` was not changed.
  Never report `2` or `3` as a successful toggle.

This command **records a preference**. To see what governance is actually running, use
`/lw-watchtower:status`; to find out what is broken, `/lw-watchtower:doctor`.
