---
description: "LW-WATCHTOWER removal - report this plugin's whole footprint and what removing it would take, as a dry run by default, and name everything it cannot remove"
allowed-tools: "Bash(powershell:*)"
disallowed-tools: "PowerShell"
---

Run this and show the output **verbatim**:

Run this through the **Bash** tool. Do not use the PowerShell tool: its validator refuses any command that launches `powershell`, so every attempt costs the operator a permission prompt and then falls back to Bash anyway.

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/bin/lwg-uninstall.ps1"
```

That is the dry run, and it is the default. It reads and prints and changes nothing.

Only after the user has read the footprint and asked for a specific removal, add `-Apply`
together with the opt-in flag for exactly what they asked for:

```
-RemoveStatusLine    the statusLine key in settings.json AND the installed statusline.ps1
-RemovePermissions   the permissions.deny entries attributable to this plugin
-All                 both of the above. Never data.
-RemoveData          the log and state directories - additionally needs -ConfirmToken DELETE-MY-LWG-LOGS
-RestoreSettings <path>   put settings.json back from one of the backups the dry run listed
```

**`-RestoreSettings` cannot be combined with any removal flag.** A restore and a removal are two
runs — the restore would put back the very `statusLine` key and `permissions.deny` entries the
removal is about to take out — so passing them together is refused with exit `1` and nothing is
written. Run the restore on its own, read the footprint it prints, then run the removal. Until
3 August 2026 the combination was accepted, the removal was silently dropped, and the run exited
`0`, which the exit contract defines as *every requested removal was made*.

Rules for reporting it:

- **Show the LEFT BEHIND and the CANNOT SEE sections. Every time.** They are the honest half of
  the report. An uninstall summary that lists what was removed and omits what was not is the
  thing this command was written to avoid.
- **Do not run `-Apply` on your own initiative, and never with more flags than were asked for.**
  "Uninstall the plugin" is a request to see the plan. Removing the `permissions.deny` entries in
  particular is a bigger decision than removing the plugin, and it has got bigger, not smaller.
  Those rules are evaluated by the CLI itself and cannot fail open, and they are now the **only**
  thing on the machine that refuses a force push or a credential read. Both gates were removed on
  30 July 2026 at the owner's instruction and the installer writes no rules at all any more, so
  whatever is in that file predates the removal and nothing will ever put it back. Removing it is
  a one-way door.
- **Never propose deleting the logs to be thorough.** `health.jsonl` and `lw-watchtower.jsonl` are the
  record of everything this plugin saw, including whatever prompted the uninstall. The script
  keeps them and says where they are; keep it that way unless the user asks in as many words.
- **The junction is not removed by this script, deliberately.** `Remove-Item -Recurse` on a
  Windows junction has deleted the TARGET's contents on some Windows PowerShell builds — measured
  on 5.1.26100.8875 it removes the link and leaves the target — and the target here is the git
  clone. Give the user the `cmd /c rmdir` line the script prints, verbatim, and do not offer a
  PowerShell alternative. **A state-data directory that is itself a junction is refused for the
  other reason:** on the build measured above the delete removes the link, the directory is then
  gone, and reporting that as `deleted` would tell the user their logs went when every one of them
  is still on the far side of the link.
- **A refusal to write settings.json is correct behaviour, not a glitch.** "CHANGED UNDER US"
  means the file was modified between the plan and the write - the CLI rewrites it, and other
  agents may be editing it. Re-run the command to re-plan; never force it.
- **Attribution is by family, not by an install manifest**, because none exists. Say so when
  reporting how many `permissions.deny` entries were counted as this plugin's - a rule the user
  added themselves can be counted here, which is why removal is opt-in and backed up first.
- **`bin/lwg-uninstall.ps1` is the only code left in the repo that knows what those rules looked
  like.** It keeps every family, including the four destructive ones the installer stopped writing
  on 30 July 2026 and the two credential ones it stopped writing the same day. A machine set up
  before then still has up to 181 of them; an uninstaller blind to those would report a clean
  removal and leave the lot behind. Do not describe the retained families as dead code. That
  sentence is checkable rather than asserted: `tests/fixtures/deny_canonical.txt` holds all 181 of
  them as the installer emitted them, and every one is driven through the matcher by
  `tests/uninstall_footprint.ps1`, which requires every single rule to be attributed. Four were not,
  until 3 August 2026 — the `+refspec` force-push rules had no family, so they survived
  `-RemovePermissions` and `LEFT BEHIND` reported them as rules this plugin had not written.
- If the CLI's own `permissions.deny` blocks one of these commands, **report the denial verbatim**
  and stop. Do not reword the command into a shape that gets past it - a governance plugin that
  helps you evade the last backstop on the machine while uninstalling itself is worse than one
  that will not uninstall. Nothing in this plugin can deny anything, so a denial here came from
  the operator's own settings file and is theirs to decide about.

- **The state-data row names the directory it resolved, and how.** It is resolved through the same
  helper every other component uses — `CLAUDE_PLUGIN_DATA` first, then the discovered
  `<name>-<source>` directory, then the bare fallback — and the header line prints that path with
  its `source`. Until 31 July 2026 this one block ignored `CLAUDE_PLUGIN_DATA` and looked only under
  the default profile path, so with the data directory redirected it reported `state-data absent`
  and `-RemoveData -ConfirmToken` reported `APPLIED: 0 change(s)` and exit `0` while every file
  survived. If the path in that row is not the one `/lw-watchtower:doctor` prints, say so and stop.
- **`UNRESOLVED` is not `absent`, and you must not report it as one.** `absent` means the location
  was resolved and holds nothing. `UNRESOLVED` means the script never worked out where to look, so
  it knows nothing about the state data at all — never summarise it as "no logs found" or "already
  clean". The row says how to pin the location; ask the user to do that and re-run.

Exit `1` means a guard refused the whole run and **nothing at all** was written: a wrong
`-ConfirmToken`, an unreadable or unparseable `settings.json`, a backup that does not parse,
`-RestoreSettings` passed with a removal flag.

Exit `2` means something the script was asked to remove was not removed — either a removal failed,
or the script **declined that one thing** while doing the rest (a state-data directory that is a
reparse point, a directory its ownership test would not attribute, an installed `statusline.ps1`
whose `settings.json` key half did not complete), or the location could not be resolved. Name those
items. `-RemoveData` against an `UNRESOLVED`
state-data location exits `2` **in the dry run as well**, because "would you delete the data?" is
not answerable without knowing where the data is. Exit `3` means the report is a fragment: do not
describe the footprint as complete, and check whether anything was changed before it stopped.
