---
description: "LW-WATCHTOWER removal - uninstall the plugin through the Claude CLI, verify by reading the registry, then report the footprint the uninstall leaves behind"
allowed-tools: "Bash(powershell:*), Bash(claude plugin:*)"
disallowed-tools: "PowerShell"
---

**"Uninstall the plugin" IS A REQUEST TO REMOVE IT.** Until 8 September 2026 this page said the
opposite — *"'Uninstall the plugin' is a request to see the plan"* — and the command behaved that
way: it printed 83 lines, exited `0`, and left the plugin installed, on the owner's own machine,
which is how the defect was reported. This script has never been able to deregister the plugin and
still cannot; **you** run the CLI command that does, through the Bash tool. The footprint is the
**second** half of the answer, not the whole of it.

Run this through the **Bash** tool. Do not use the PowerShell tool: its validator refuses any command that launches `powershell`, so every attempt costs the operator a permission prompt and then falls back to Bash anyway.

## Step 1 — the dry run, always first

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/bin/lwg-uninstall.ps1"
```

It reads and prints and changes nothing. Its **first block is `TO REMOVE THIS PLUGIN`**, and it
carries the exact commands for **this** machine with the id and marketplace already interpolated.
Read them from that block. Do not compose them yourself and do not guess an id.

## Step 2 — run the removal the first block names

On a marketplace install that is `claude plugin uninstall <plugin>@<marketplace> --keep-data -y`,
and — only if the operator is done with the source as well — `claude plugin marketplace remove
<marketplace>`. **Copy them out of the report rather than typing them from memory.** Two things
about them, both read off `claude plugin uninstall --help` on CLI 2.1.263 rather than assumed:

- `--keep-data` preserves `~/.claude/plugins/data/{id}/` **and nothing else**. See the
  `--keep-data` rule further down — it is wrong to describe it as protecting "the logs".
- `-y` is documented as skipping the **`--prune`** confirmation, "required when stdin or stdout is
  not a TTY". It is not required by the uninstall itself: measured on 8 September 2026, the plain
  form with no `-y` succeeded and exited `0` from a tool call with no TTY on either end. Pass it
  anyway — it is cheap — but do not tell the operator the command hangs without it. **Never add
  `--prune`**: that removes other plugins.
- `claude plugin marketplace remove` has **no `-y`**; its only options are `-h` and `--scope`.
  Passing `-y` to it is an unknown-option error.

On a junction install there is no CLI id, and the first block prints the `cmd /c rmdir` line for
the link instead. Use that verbatim.

**If the operator asked only to see the plan, stop after step 1 and say so.** Everything after this
point acts.

## Step 3 — verify by reading state, never by trusting the exit code

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<the absolute path the first block printed>" -VerifyRemoved
```

**Use the absolute path from the report, not `${CLAUDE_PLUGIN_ROOT}`** — after a successful
uninstall that variable is gone and the file is not.

`-VerifyRemoved` opens `~/.claude/plugins/installed_plugins.json` and answers from what is in it:

| exit | meaning |
| --- | --- |
| `0` | the file parsed and holds no key for this plugin — **removed** |
| `2` | the key is still there — **NOT removed**, whatever the uninstall printed |
| `3` | the registry could not be read, or there is no file at that path — **nothing was established** |
| `1` | refused: `-VerifyRemoved` was passed with `-Apply` or a removal flag |

**`3` is not `0`.** Do not report "removed" on a `3`. This is not belt-and-braces: an exit code is a
claim by the thing being checked, and `lib/supervisor.ps1` records this repository's own instance of
trusting one — a check that read a roster file nothing ever wrote and reported `0 orphans`
unconditionally for its entire life.

## Step 4 — report

Three things, in this order: **what the removal did** (the CLI's own output, verbatim), **what the
verify read** (registered or not, and the exit code), and **what is left behind** — from step 1's
`LEFT BEHIND` and `AND WHAT THIS SCRIPT CANNOT SEE`. Two facts belong in that report every time:

- **Deregistered is not deleted.** Measured on 8 September 2026 under CLI 2.1.263: a successful
  uninstall removed the registry key and left the whole unpacked copy at
  `plugins/cache/<marketplace>/<plugin>/<version>` on disk. Give the operator the
  `cmd /c rmdir /s /q "<that path>"` line the report prints if they want the disk back.
- **A restart is needed** for the running session to stop loading the plugin — commands, hooks,
  agents and output styles are read at session start. **Whether a running session drops a
  deregistered plugin without a restart is UNMEASURED.** Say "unmeasured"; do not claim either way.

## The footprint modes

These are about the **artefacts the CLI uninstall does not touch** — settings, the status line, the
state data. None of them removes the plugin; steps 2 and 3 above do that.

Only after the user has read the footprint and asked for a specific removal, add `-Apply`
together with the opt-in flag for exactly what they asked for:

```
-RemoveStatusLine    the statusLine key in settings.json AND the installed statusline.ps1
-RemovePermissions   the permissions.deny entries attributable to this plugin
-All                 both of the above. Never data.
-RemoveData          the log and state directories - additionally needs -ConfirmToken DELETE-MY-LWG-LOGS
-RestoreSettings <path>   put settings.json back from one of the backups the dry run listed
-VerifyRemoved       read the registry and say whether the plugin is still registered.
                     Reads one file, writes nothing, and is refused alongside -Apply or
                     any removal flag - see step 3.
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
  "Uninstall the plugin" is a request to remove the plugin — steps 2 and 3 — and **not** a request
  to strip the operator's settings file. Removing the `permissions.deny` entries in
  particular is a bigger decision than removing the plugin, and it has got bigger, not smaller.
  Those rules are evaluated by the CLI itself and cannot fail open, and they are now the **only**
  thing on the machine that refuses a force push or a credential read. Both gates were removed on
  30 July 2026 at the owner's instruction and the installer writes no rules at all any more, so
  whatever is in that file predates the removal and nothing will ever put it back. Removing it is
  a one-way door.
- **Never propose deleting the logs to be thorough.** `health.jsonl` and `lw-watchtower.jsonl` are the
  record of everything this plugin saw, including whatever prompted the uninstall. The script
  keeps them and says where they are; keep it that way unless the user asks in as many words.
- **The `--keep-data` rule, and it is not what the flag's name suggests.** `--keep-data` preserves
  exactly one directory: the CLI's own `~/.claude/plugins/data/{id}/`. **The help does not spell
  `{id}`, and this project has measured it both ways** — `docs/install.md` records
  `plugins/data/<name>-<marketplace>/` under CLI 2.1.260 — so do not assert a path here. Read the
  first block of the dry run: it lists every state directory it found and marks each *may be
  covered* or *NOT covered*. A directory under **any other name is not covered**, because the CLI
  has no way to know it belongs to this plugin. That is not hypothetical — on the machine the defect was reported from, measured 8 September 2026,
  `plugins/data/lw-watchtower/` **did not exist** while 2.5 MB of real event log sat beside it in
  `plugins/data/lw-gmhh/`, the pre-rename name. So the flag would have protected an absent
  directory and covered none of the logs. **The answer that does not depend on a flag is to copy
  `health.jsonl` and `lw-watchtower.jsonl` (or `lw-gmhh.jsonl`) out of the `plugins/data` tree
  first.** The dry run's first block names which of these exist on the machine in front of you —
  read it there rather than assuming either shape.
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
`-RestoreSettings` passed with a removal flag, `-VerifyRemoved` passed with `-Apply` or a removal
flag.

Exit `2` means something the script was asked to remove was not removed — either a removal failed,
or the script **declined that one thing** while doing the rest (a state-data directory that is a
reparse point, a directory its ownership test would not attribute, an installed `statusline.ps1`
whose `settings.json` key half did not complete), or the location could not be resolved. Name those
items. `-RemoveData` against an `UNRESOLVED`
state-data location exits `2` **in the dry run as well**, because "would you delete the data?" is
not answerable without knowing where the data is. Under `-VerifyRemoved`, exit `2` means the
registry key is **still there** — the plugin was not removed.

Exit `3` means the report is a fragment: do not
describe the footprint as complete, and check whether anything was changed before it stopped. Under
`-VerifyRemoved` it means the registry could not be read at all, or there is no file at that path —
**nothing was established, and it is not a pass.**
