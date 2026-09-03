# Install

LW-WATCHTOWER is a Claude Code plugin. It is **Windows-only** and runs under **Windows PowerShell 5.1**.

## Requirements

| Requirement | Why |
| --- | --- |
| Windows | Every path this plugin classifies is an NTFS path, including 8.3 short names, and the status line and installer are written against Windows profile layout. |
| Windows PowerShell 5.1 (`powershell.exe`) | All ten registrations in [`hooks/hooks.json`](../hooks/hooks.json) name the binary `powershell`, so **the constraint is the registration, not a 5.1 language feature**. Every tracked script declares `#requires -version 5`, which PowerShell 7 satisfies — running one under `pwsh` by hand is not refused by the interpreter, and one was checked and produced byte-identical output. That is one script, not a claim about all twenty-one. The hooks will still invoke `powershell`, and on a machine where that name does not resolve they do not run at all. |
| Claude Code | The hook events used here (`SubagentStart`, `PostToolUseFailure`, `StopFailure`) were read out of the 2.1.220 binary. Older builds may not carry all of them. |
| `git` on `PATH` | Optional. Only `git_hygiene` shells out, and only at turn end inside a repo. Without it that module reports `UNKNOWN`, never "clean". |
| `gh` on `PATH` | Optional. **One** thing uses it: `git_hygiene`'s open-PR check at turn end. `module_config.git_hygiene.use_gh: false` switches it off, and with it off that check reports that it did not run rather than reporting clean. The three evidence probes that also used `gh` went on 2 September 2026 with the `checklist` and `sitrep` commands — **and with them went the only outbound traffic this plugin generated that was not about your own tree**, two rows that queried the maintainer's own repository with your token. |

Nothing here needs Node, npm, or Python.

## Option A — marketplace install (recommended for consumers)

The repo hosts its own single-plugin marketplace in
[`.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json), named `leapware-watchtower`,
whose one entry sources `lw-watchtower` from the repo root.

```
/plugin marketplace add LEAPWare-Software/LEAPWare-Watchtower
/plugin install lw-watchtower@leapware-watchtower
```

A marketplace install *copies* the plugin root into an internal cache, so an edit to your clone
does nothing until `claude plugin update`. That is correct for consumers and wrong for anyone
developing the plugin — see Option B.

### Which tree this actually gives you

**The default branch, `main`. Not a tag, and not a pinned commit.** The entry in
[`.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json) is `"source": "./"` with no
`ref`, `tag` or `branch` key, so the reference resolved is the repository's default branch. Three
consequences, stated because none of them is obvious from the two commands above:

- **You get whatever `main` held at the moment you installed.** Two people who run those commands a
  week apart can be running different code with the same version number on the banner.
- **It is not the tree any tag was tested against.** `v0.3.0` is the only tag this project has, and
  `main` is well past it — including two changes that alter how an existing `config.json` is read
  (see [CHANGELOG.md](../CHANGELOG.md#040--unreleased)).
- **The declared version does not identify the tree, and cannot.** It tells you which *release line*
  you are on. Since 0.4.0 is not yet tagged, a `0.4.0` banner means "some commit on `main`" and
  nothing narrower.

There is no honest way to pin this route from inside the repository, so **this page does not claim
one**. If you need a known tree, use Option B against a checked-out tag.

`main` is nonetheless the *maintained* line: it is where fixes land, `v0.3.0` receives none (see
[SECURITY.md](../SECURITY.md)), and CI gates every push to it. Tracking `main` is a reasonable
choice; not knowing that you are tracking it is not.

## Option B — directory junction (recommended for development)

Any folder under a skills directory that contains `.claude-plugin/plugin.json` is auto-discovered
as a plugin on the next session. There is no `enabledPlugins` entry to add and no install step to
run. A junction needs no administrator rights.

```powershell
# Wherever you keep your clones. Nothing here depends on this particular path;
# every later snippet on this page reads it back out of $Repo, so change it once.
$Repo = "$env:USERPROFILE\src\leapware-watchtower"

git clone https://github.com/LEAPWare-Software/LEAPWare-Watchtower.git $Repo

# CREATE THE SKILLS DIRECTORY FIRST. On a profile that has never used a skill it
# does not exist, and `mklink /J` does NOT create a missing parent - it fails
# with "The system cannot find the path specified." and leaves you looking at
# the junction command rather than at the missing folder. -Force here means
# "do not complain if it is already there", not "overwrite"; it never touches an
# existing directory's contents.
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.claude\skills" | Out-Null

cmd /c mklink /J "$env:USERPROFILE\.claude\skills\lw-watchtower" "$Repo"
```

`mklink` prints `Junction created for ... <<===>> ...` on success. If it instead says **"Cannot
create a file when that file already exists"**, something is already at that path — check whether it
is an older junction (`Get-Item "$env:USERPROFILE\.claude\skills\lw-watchtower" | Select-Object LinkType,
Target`) before removing anything.

**If you installed before 3 August 2026, your junction is named `lw-gmhh`.** The product was renamed
that day. Remove the old link and make a new one at the path above — the safe verb is
`cmd /c rmdir "%USERPROFILE%\.claude\skills\lw-gmhh"`, which removes the link and leaves the clone
alone. Whether Claude Code takes a skills-dir plugin's identity from the junction's *directory name*
or from `name` in `.claude-plugin/plugin.json` was **not measured here**; recreating the junction
makes the two agree either way, which is why that is the instruction rather than a guess about
whether the old one still resolves. Separately and regardless: the rename moved the state directory
and nothing migrates it — see `## [0.4.0]` in [CHANGELOG.md](../CHANGELOG.md).

The junction keeps the clone live: the file you edit *is* the file that runs, `git pull` is the
update mechanism, and a `config.json` change takes effect on the next session with no reinstall.

**Which tree this gives you: whatever your working copy is checked out at**, which is the point —
this is the only route where you decide. `git clone` as written above leaves you on the default
branch, the same tree Option A would have given you. To run a *tested* tree instead, check out the
tag:

```powershell
git -C $Repo checkout v0.3.0
```

`v0.3.0` is the only tag this project has. Pinning to it means forgoing every fix on `main` since,
and `main` is where fixes land — so this is a real trade rather than a recommendation. Read
[CHANGELOG.md](../CHANGELOG.md#040--unreleased) and decide.

Whatever you choose, the only answer to "which tree am I running" is the commit:

```powershell
git -C $Repo rev-parse --short HEAD
```

The version on the banner is not that answer, because it does not move commit by commit.

Discovered this way the plugin is named `lw-watchtower@skills-dir`, which matters — see
[State directory](architecture.md#state-directory).

**Do not run both installs at once.** They are separate sources, distinguished by suffix
(`lw-watchtower@skills-dir` vs `lw-watchtower@leapware-watchtower`), and two copies of every hook would fire per
event. Adding the marketplace does not disturb an existing junction, but installing from it will
give you a second live copy.

## Confirming it loaded

Start a new session. The `SessionStart` banner appears, and

```
/lw-watchtower:doctor
```

checks the wiring. See [Commands](commands.md) and [Troubleshooting](troubleshooting.md).

**Read its exit code, and expect a non-zero one after a first install.** The doctor is built to be
able to fail, so a caveat is reported as a caveat: `0` every check passed, `1` at least one check
**FAILED**, `2` it finished with at least one **WARNING** and no failure, `3` it could not complete.
**`2` is the normal result before you have installed the status line** — the `statusline` check warns
when `~\.claude\statusline.ps1` is absent or differs from the tracked copy, and that is a real
finding about the machine rather than a blemish on the install. Read the rows, then do the
[status-line install](#installing-the-status-line-optional-and-separate) below if that is the only
warning. A tool that reported `0` here would be telling you something it had not checked.

`claude plugin validate --strict` walks and parses every discovered command and manifest, failing
on any field the runtime does not recognise — which is the only way to be sure a manifest field is
real rather than plausible.

## The installer writes no `permissions.deny` rules

This section used to be headed *not optional*. It is now a record of a removal.

`permissions.deny` in your own `settings.json` is the one layer that cannot fail open — the CLI
evaluates it itself, before and regardless of any hook. **This plugin no longer writes a single rule
into it.** `Get-DenyGroups` in [`bin/lwg-setup.ps1`](../bin/lwg-setup.ps1) returns an empty table, so
there is nothing to select and nothing to merge.

It wrote **181 rules in six groups** until 30 July 2026. That day the four destructive groups
(133 rules) went with `destructive_gate`, and the two credential groups — `secret-paths` (30) and
`secret-reads` (18), **48 rules** — went with `secret_scan`. Both removals were explicit owner
decisions; see [Both gates were removed](modules.md#both-gates-were-removed).

So a fresh install has **neither a hook layer nor a config layer**, for credentials or for anything
else. Nothing this plugin ships can stop a write, a read or a command.

```
/lw-watchtower:setup
```

still drives [`bin/lwg-setup.ps1`](../bin/lwg-setup.ps1), and it still asks in plain language, shows
the exact lines it would add, and writes them only after a yes for that section alone. What it writes
now is the **status line**, the **hook registrations** and the **agent roles** — the observing parts.
The `permissions` section selects an empty set and says so.

`-SecretGate` and `-DestructiveGate` are still accepted parameters and **select nothing**, at either
layer. They are kept, loudly inert, so an existing caller and the `-Step detect` question list do not
break: a parameter that quietly did nothing would be read as a bug, while one that loudly does
nothing is a record of a decision.

**Setup never removes a rule already in your `settings.json`.** A machine set up before 30 July 2026
still carries the old rules, the CLI still evaluates them, and nothing here renews or deletes them.
`/lw-watchtower:uninstall` is the only code left that knows what those 181 rules looked like well enough to
attribute and remove them.

What it will not do, by construction — these still govern the sections it does write:

- **It never replaces.** The merge is a set union with the existing order preserved, so deny rules
  you wrote yourself survive, keep their positions, and are never rewritten — including ones the
  installer would call inert. Running it twice adds nothing and does not even touch the timestamp.
- **It never writes without a matching diff.** `-Step apply` refuses (exit `5`) without the
  `BASEHASH` that `-Step diff` printed, and refuses (exit `4`) if anything rewrote the file in
  between. Claude Code rewrites `settings.json` itself, so this is a real event, not a theoretical one.
- **It never overwrites a file it cannot read.** A `settings.json` that does not parse is refused
  outright, because overwriting one is how every *other* setting in it gets lost.
- **It backs up first, and never deletes a backup.** `settings.json.lwg-<timestamp>.bak`, restored
  automatically if what landed does not parse, and on demand with `-Step rollback`. The automatic
  restore uses the same non-atomic copy as the write it is undoing, so under the condition that
  broke the write — a full volume, a lock, a killed process — it can fail too; when it does, the
  failure message now names the reason and the backup, rather than reporting only that a backup
  exists. The write itself is **not** an atomic replace and the installer does not claim to be one:
  see the docstring on `Save-Settings` in [`bin/lwg-setup.ps1`](../bin/lwg-setup.ps1), which records
  why the atomic call was measured and rejected.

**All four of those properties are tested again, on the `statusline` section only.**
`tests/setup_merge.ps1` drives the real script in a real child process against throwaway settings
files, 124 cases, and CI runs it on every push and every PR. The `permissions.deny` parity test that
used to cover the merge end to end was deleted on 30 July 2026 with the deny table it also guarded;
this suite is the half that was never about deny rules, re-aimed at the sections the installer still
writes.

**The `hooks` section is covered too, for what it decides rather than for how it writes.** Setup used
to look for a marketplace install under `~\.claude\plugins\repos` — a directory that does not exist
on a live Claude Code install — so it called one *not discoverable* and wrote a **second full copy of
every hook registration**, with the duplicate-firing warning suppressed because the warning read the
same flag. Every hook then fired twice. The suite plants the layout the CLI actually writes
(`plugins\cache\<marketplace>\<plugin>\<version>`) and checks that the section plans nothing, that a
forced `-HookMode standalone` still warns, and that the same script already registered from a
**different root** is reported and not added beside. It also runs `statusline/statusline.ps1` from a
scratch copy, because that file carried the same wrong assumption and rendered the purple `HH?`
*not installed* glyph on a working install.

**What that leaves uncovered, so the four ticks above are not read as more than they are:** the
byte-level writer properties are established on `statusline` and only *inherited* by `hooks`, which
goes through the same `Save-Settings` path; the backup-collision suffix and the post-write
auto-restore are named as uncovered in the suite's own header; and no case anywhere proves that the
CLI build you are running still writes the layout those fixtures plant. See
[Testing § what is not covered](testing.md#what-is-not-covered).

The three sections — `permissions`, `statusline`, `hooks` — are confirmed separately, always. There
is no `-Section all`, deliberately: one yes must not buy three different powers over your machine.
`permissions` is now a section that reports an empty set rather than one that writes anything.

Running it by hand, outside a session:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-setup.ps1 -Step detect
powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-setup.ps1 -Step diff  -Section statusline
powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-setup.ps1 -Step apply -Section statusline -BaseHash <the hash the diff printed>
```

Add `-DryRun` to the apply to do everything except the write. `-SettingsPath` redirects the target,
which together with `$env:USERPROFILE` is how the installer is tested against a scratch tree rather
than a real profile.

## Installing the status line (optional, and separate)

The `HH` segment of the Claude Code status line is this plugin's only live indicator surface, and
**the script that renders it is not part of the plugin.** A second segment, `GM`, rendered the
plugin's own governance state until 30 July 2026 and was deleted with the trip ledger that was its
only input — see [gates-removed.md](gates-removed.md). Nothing emits it now, so a status line that
never shows `GM` is a correct one. `statusLine` is a
top-level key Claude Code reads only from `settings.json`; a plugin has no manifest field for it
and no hook event renders a line. So the source of truth is tracked here at
[`statusline/statusline.ps1`](../statusline/statusline.ps1) and installed by copying.

`$Repo` below is the clone path you set in
[Option B](#option-b--directory-junction-recommended-for-development). In a fresh shell, set it
again first — it is an ordinary variable, not something the install persists.

```powershell
Copy-Item "$Repo\statusline\statusline.ps1" `
          "$env:USERPROFILE\.claude\statusline.ps1"
```

Then wire it up in `~\.claude\settings.json`. The `command` string is passed to the shell as
written, so the path must be spelled out in full for your own profile:

```json
"statusLine": {
  "type": "command",
  "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:/Users/<you>/.claude/statusline.ps1\"",
  "refreshInterval": 120
}
```

`-NoProfile` keeps a profile load off a path that runs on every render, and
`-ExecutionPolicy Bypass` makes it run without depending on the machine's policy.

**Pointing the command through the junction instead** —
`…\.claude\skills\lw-watchtower\statusline\statusline.ps1` — is possible and removes the copy and the
drift described below. It buys that by making the status line depend on the junction being present
and the clone being in a renderable state: a checkout mid-rebase, or a junction not yet created on
a new machine, blanks the row. Both options are real; pick the trade you prefer.

### This is a copy, and it can drift

The plugin is loaded through a junction, so the clone and the loaded code are the same bytes by
construction. **The status line is not.** The tracked file and `~\.claude\statusline.ps1` are two
independent files. Edit either and the other is silently stale — including the case that costs
most, a fix made to the live file and then overwritten the next time the repo copy is installed
over it. Re-copy after every edit, in whichever direction it was made, and check with:

```powershell
Get-FileHash "$env:USERPROFILE\.claude\statusline.ps1",
             ".\statusline\statusline.ps1" | Select-Object Hash, Path
```

`/lw-watchtower:doctor` reports this drift as a warning. The tracked file is pinned to `eol=lf` in
[`.gitattributes`](../.gitattributes) — every other `.ps1` here is `eol=crlf` — so a fresh clone
reproduces the installed file byte for byte and that hash comparison keeps meaning something.

See [Status line](architecture.md#status-line) for what the segments mean and why the rate-limit
escalation lives there.

## Uninstalling

**Start with the command written for this.**

```
/lw-watchtower:uninstall
```

It is a **dry run by default** — it reads and prints and changes nothing — and it prints three
things: a `FOOTPRINT` table of everything this plugin put on the machine, a `LEFT BEHIND` list of
what it will not remove and why, and an `AND WHAT THIS SCRIPT CANNOT SEE` list of its own blind
spots. Read all three before acting. The removals are opt-in and none of them happens without
`-Apply`:

| flag | removes |
| --- | --- |
| `-RemoveStatusLine` | the `statusLine` key in `settings.json` **and** the installed `statusline.ps1`, as one decision — the key without the file blanks the whole status row |
| `-RemovePermissions` | the `permissions.deny` entries attributable to this plugin |
| `-All` | the two above. Never data. |
| `-RemoveData` | the log and state directories. Additionally needs `-ConfirmToken DELETE-MY-LWG-LOGS`, typed exactly |
| `-RestoreSettings <path>` | puts `settings.json` back from one of the backups the dry run lists. Cannot be combined with any removal flag — that is refused, and nothing is written |

Exit `1` is a refusal with nothing written; exit `2` means something it was asked to remove was not
removed, and it names what.

### What removing the plugin leaves behind

Four classes of artefact, and removing the plugin's load path removes none of them. The
uninstaller's own `LEFT BEHIND` and `CANNOT SEE` blocks are the authority on this and are printed on
every run — this list says what to expect, not what those blocks say.

- **The copied `~\.claude\statusline.ps1`.** `copy` is the default `-StatusLineMode`, so on a default
  install this is a real file — a whole copy of [`statusline/statusline.ps1`](../statusline/statusline.ps1),
  independent of the clone — sitting in your `.claude` root. Removing the `statusLine` *key* does not
  remove it. `/lw-watchtower:uninstall -RemoveStatusLine
  -Apply` removes both halves together and keeps a `.bak` copy of the file beside it.
- **`settings.json.lwg-*.bak`.** Setup takes one before every write and, as stated above, **never
  deletes a backup**. Each one is a verbatim copy of *your* `settings.json` at the moment it was
  taken, with whatever it contained. They are retained on purpose and removing the plugin does not
  remove them. Delete them yourself when you are satisfied you no longer need a restore.
- **Hook registrations in `settings.json`, on a standalone install only.** When Claude Code can
  discover the plugin, the plugin registers its own hooks out of `hooks/hooks.json` and this section
  of `settings.json` stays empty — removing the junction unregisters everything in one step. When it
  cannot, setup writes the fallback wiring — and it does not re-spell it: `New-HooksPlan`'s
  standalone mode reads [`hooks/hooks.json`](../hooks/hooks.json) and copies what is there, changing
  only `${CLAUDE_PLUGIN_ROOT}` to the clone's path, so the count in `settings.json` is whatever that
  file declares. Today that is **10 registrations across 8 events** (`SessionStart`, `PreToolUse`,
  `PostToolUse`, `PostToolUseFailure`, `SubagentStart`, `SubagentStop`, `Stop`, `StopFailure`).
  Those point at scripts inside the clone, and deleting the clone leaves them firing at paths that no
  longer exist. `/lw-watchtower:uninstall` **reports** how many references to this plugin
  it sees under `hooks` and does **not** remove them; that edit is yours to make by hand.
- **The state and log directories.** They live under `$CLAUDE_PLUGIN_DATA` — never in the repo — and
  are kept unless you pass `-RemoveData` with the confirmation token, because `health.jsonl` and
  `lw-watchtower.jsonl` are the record of everything this plugin observed, including whatever made you want
  to uninstall it. See [State directory](architecture.md#state-directory).

### Removing the load path itself

The uninstaller deliberately does not do either of these.

- **Marketplace install:** `/plugin uninstall lw-watchtower@leapware-watchtower`. That copy lives in the CLI
  cache with its own data directory, which `/lw-watchtower:uninstall` cannot see.
- **Junction install:** delete the junction at `%USERPROFILE%\.claude\skills\lw-watchtower` with
  `cmd /c rmdir "%USERPROFILE%\.claude\skills\lw-watchtower"`, which removes the link and not the clone.
  Use that verb and not a PowerShell one. Removing the junction is what deregisters every hook,
  command and output style on a discovered install.
