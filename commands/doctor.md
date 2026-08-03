---
description: "LW-WATCHTOWER health check - reports what is NOT working: hook registration, state-dir resolution, status-line wiring, config drift and the last SessionStart self-check"
allowed-tools: "Bash(powershell:*)"
---

Run this command and show the user its output **verbatim**:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/bin/lwg-doctor.ps1"
```

Add `-Quiet` to the command if the user only wants the problems and not the passing checks.

**The script's exit code is the verdict. Report it as it is.**

| Exit | What it means | How to report it |
| --- | --- | --- |
| `0` | every check passed | healthy |
| `1` | at least one check FAILED | **not healthy** - name every `[FAIL]` row |
| `2` | no failures, but warnings | working, with caveats - name every `[WARN]` row |
| `3` | the doctor could not complete | **unknown** - the lines printed are a fragment of a checkup, not the result of one. Do not report this as healthy |

Rules for reporting it:

- **A non-zero exit is a real finding, not a glitch.** Do not retry it hoping for a better
  answer, do not attribute a `[FAIL]` to the environment, and do not soften it. This script
  exists because a health check that cannot say "broken" is worthless.
- **Never summarise a failure away.** If `state-dir` reports UNRESOLVED, that means every log
  write is going to a directory the live plugin never reads - say that, do not call it a
  path warning.
- **Do not diagnose past the evidence.** Each row states the fault it found and why it matters.
  If the user wants a fix, propose one, but keep it clearly separate from what the script
  reported.
- Exit `3` is not exit `1`. "I found a fault" and "I could not look" are different statements
  and must not be collapsed.

The script prints its own blind spots on every run, including green ones. **Repeat them.**
A doctor that passes has checked the plugin's *wiring*, not its *behaviour*: it does not establish
that the advisories fire, that the right context reaches a subagent, that the installer merges a
`settings.json` correctly, or that Claude Code has this plugin enabled in the current session.
**Nothing the doctor runs tests behaviour, and no command in this plugin does either.** Both security
gates and both of their harnesses were removed on 30 July 2026 at the owner's instruction; the one
gate that ships since, `delegate_gate`, is exercised by `tests/gate_delegate.ps1` — which is a test
file run by CI and by hand, not something a command can invoke. Say that plainly rather than pointing
at a command that would establish it, because there is none.
