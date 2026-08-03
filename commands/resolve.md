---
description: "LW-WATCHTOWER fault clearing - mark one session's outstanding health faults resolved, with the data directory and the session both pinned, or refuse and say why"
allowed-tools: "Bash(powershell:*)"
---

Run this first, always, and show the output **verbatim**:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/bin/lwg-resolve.ps1" -Session <id> -List
```

Then, only after the user has seen which faults would be cleared, re-run with the note and
`-Apply`:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/bin/lwg-resolve.ps1" -Session <id> -Note "what was actually fixed" -Apply
```

`-DataDir <path>` pins the log when the candidate table shows more than one plausible home.
`-InferSession` accepts the newest session on record instead of an explicit id, and prints the
age of the record it took it from.

**Do not use `lib/resolve.ps1` for this.** That script resolves its log through
`Get-LwgStateDir`, and `CLAUDE_PLUGIN_DATA` is set for plugin hooks and for nothing else - so
outside a hook it picks one of several data directories by modification time, infers the session
from that file's tail, writes a marker for whatever session that turns out to be, and prints
"status line HH returns to green". This command exists because that is a success report about a
change that did not happen.

Rules for reporting it:

- **A refusal is the command working.** Exit `1` with "does not appear in ANY candidate health
  log" means the session you named has no records anywhere it looked. Report that as the finding.
  Do not retry with `-InferSession` to get a green line, do not pick a session id out of the
  candidate table because it is the only one there, and do not fall back to `lib/resolve.ps1`.
- **Never claim HH is green because this command exited 0.** It prints its own verification -
  the marker read back from disk, and the fault count recounted across every log. Quote those two
  lines. If it exits `4` the marker was written and the faults did NOT clear; say exactly that.
- **Exit `2` means the data directory could not be pinned.** Two logs hold the session and
  nothing distinguishes them. Ask the user which one, or pass `-DataDir`; do not choose for them.
- **The `-Note` is not a formality.** It goes into an evidence log. Write what was actually
  fixed, not "resolved" - and if nothing was actually fixed, do not run this at all. Clearing a
  fault you have not addressed is how a red indicator becomes a green one that means nothing.
- **Report the candidate table.** However many candidate data directories it lists — one on a
  clean install, more once a plugin has been discovered under a second name — at most one is
  live. Report the count you actually see rather than an expected one. The table is what shows
  the user that the right log was chosen, and where it lists more than one, the line beginning
  "This is NOT the directory the unpinned resolution returned" is the bug being avoided in
  real time.
- If it refuses with "no outstanding faults to clear", the session is already clean. Say so;
  do not write a marker anyway to make the command feel like it did something.
