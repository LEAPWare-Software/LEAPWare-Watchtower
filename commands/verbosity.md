---
description: "How much prose an answer carries - brief, default or verbose. Reports the current level when called with no argument. This records the preference; activating the output style is a manual step the script spells out"
argument-hint: "[brief|default|verbose] [repo]"
allowed-tools: "Bash(powershell:*)"
---

Run this command and show the user its output **verbatim**:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/bin/lwg-toggle.ps1" -Flag verbosity
```

Append `$1` as the level when one was given — `brief`, `default` or `verbose`. Pass **nothing**
when the user only asked what the level is. Append `-Scope repo` if they scoped it to this
repository only (they said "here", "this repo", or typed `repo` as the second word); otherwise the
write is global.

Do **not** translate anything else into a level. `on`, `off`, `short`, `long`, `terse` and
`concise` are all things the script rejects — let it reject them and print its usage. That
rejection is the feature. If the user asked in words rather than by name, ask which of the three
they mean rather than picking one for them.

The script is the answer. It reads and writes `config.json` itself and re-reads the file from
disk before reporting, so the value it prints is the value a hook would load.

Rules for reporting it:

- **This is one setting with three levels, not a switch.** `output_style.verbosity` holds exactly
  one of `brief`, `default` or `verbose`. Setting one level unsets the others by construction —
  there is no state in which two are active. `default` is the level at which this axis does
  nothing; it is the off position, and it is not a fourth thing.
- **It used to be two commands, `lw-watchtower:brief` and `lw-watchtower:verbose`, and they wrote this same
  key.** Neither exists any more — they are written here without a leading slash on purpose, so
  that `bin/lwg-doctor.ps1` does not read this sentence as a live signpost to a command that is
  gone. Say so if the user reaches for either name. The merge removed a surface that described a
  model which was not there: under the old pair, turning `brief` off while the key read `verbose`
  wrote nothing at all — correct, and confusing enough that the script had to explain it on every
  run. Nothing about the stored value changed; a `config.json` written by the old commands is read
  identically by this one.
- **One key rather than two booleans is deliberate.** A per-repo override is merged key by key, so
  two booleans could have been set at different scopes — `brief` globally, `verbose` for one
  repository — and no rule inside the script could have stopped it. Say this if the user asks why
  there is no way to have both.
- **`plain` is a separate command and a separate axis.** It is not a verbosity level and does not
  belong in this one: plain English is about jargon, not length. `/lw-watchtower:plain` is unchanged.
- **`verbosity` is a preference, not a module.** It is deliberately absent from the module registry
  and from `config.json`'s `modules` block, so it does not appear in the banner's `n/10` and the
  governance count is unchanged. Do not describe setting it as enabling a module.
- **Setting the level does not switch the style on**, and the script says so under `ACTIVATION`.
  Report that block in full. The style Claude Code applies is the `outputStyle` key in a settings
  file; nothing in this plugin writes that key. The operator has to run `/config` and choose
  **Output style** themselves.
- **Verbosity and `plain` are independent axes, and the pair selects one file.** With the level at
  `verbose` and `plain` on, the style to select is `lw-watchtower-verbose-plain`, because `outputStyle`
  is a single string and two styles cannot be composed. The script works out which of the five
  names applies and prints it; do not compute it yourself.
- **It will not take effect in this session, whatever the user does next.** An output style is
  read into the system prompt once at session start. Say this plainly rather than letting them
  discover it. `/clear` or a new session is required, and `/clear` discards the conversation.
- **Output styles reach the main conversation only.** A subagent runs its own system prompt, so
  dispatched workers answer in their own voice regardless. In a delegating setup that is most of
  the text on screen.
- **What `verbose` asks for is more content, not more words.** The style file sets no minimum
  length, deliberately, because a floor is met by padding. If the user expects longer answers as
  such, say that the level asks for reasoning, rejected alternatives and full evidence, and that
  nothing measures length in either direction.
- **An `OBSOLETE KEY` block means a dead `output_style.brief` boolean is still in the file.** That
  key was replaced by `verbosity` and nothing reads it. The script names it and **does not rewrite
  it** — report that as printed, including that removing it is a manual edit.
- The exit code is the verdict: `0` reported or changed, `2` the argument was rejected and
  **nothing was written**, `3` the command could not complete and `config.json` was not changed.
  Never report `2` or `3` as a successful change.

This command **records a preference**. To see what governance is actually running, use
`/lw-watchtower:status`; to find out what is broken, `/lw-watchtower:doctor`.
