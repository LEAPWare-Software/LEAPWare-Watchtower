<!-- doc-claims:ignore-file — this page is a RECORD OF ONE RUN ON ONE DATE. Every number in
     it is what was observed on 2026-07-31 and must keep saying that even after the tree moves
     on; correcting one would be falsifying the record. tests/doc_claims.ps1 therefore reads
     nothing here. If this page ever needs to state a CURRENT number, put it in a new dated
     line and let the guard check that line instead of exempting the file further. -->

# LW-GMHH v0.3.0 — user acceptance test

**Run on 2026-07-31, from `2fd419685cd0e9d0db8c7c6f7a1fb15c9832f2b9` on `main`.** Windows 11,
Windows PowerShell 5.1, one machine, one pass.

Every one of the twelve commands was invoked exactly as its `commands/<name>.md` documents it, as a
child process, against a throwaway profile. The adversarial cases below were chosen to make each
command **fail** — a refusal that never fires is indistinguishable from a refusal that is not there.

Two defects were found and fixed before this report landed. Both were in the installer, both are
recorded in full under [Findings](#findings), and the rows they affected were re-run against the
fixed tree.

---

## How this was run

Everything lived in **a scratch directory outside the repository**, created under the system
temporary directory and deleted afterwards. Three subdirectories, and a fourth for a git checkout:

| Under the scratch directory | Role |
| --- | --- |
| `profile/` | becomes `USERPROFILE` for every child process. Starts as an empty `.claude/` tree |
| `plugin/` | the tree at `HEAD` **without `.git`**, extracted from `git archive`. Becomes `CLAUDE_PLUGIN_ROOT`. Every write-path command edited *this* copy's `config.json` |
| `data/` | becomes `CLAUDE_PLUGIN_DATA` |
| `clone/` | a `git clone` of the repository, used for the `update` cases and as the working directory for every run. **The real checkout was never the target of an update** |

Each case ran as its own child process:

```
powershell -NoProfile -ExecutionPolicy Bypass -File <plugin>/bin/lwg-<cmd>.ps1 ...
```

with those three environment variables set for the child, and `bin/lwg-setup.ps1` additionally given
`-SettingsPath <scratch>/profile/.claude/settings.json`. Standard output, standard error and the
exit code were captured to separate files per case, because the de-elevation wrapper below does not
relay any of them.

**Three things had to be pinned before the sandbox actually held**, and each was found by measuring
rather than by assuming:

- **The working directory is part of containment.** `bin/lwg-toggle.ps1` resolves the project it
  reports on from `Get-Location`, and probes `.claude/settings.local.json` and
  `.claude/settings.json` beneath it. The de-elevation wrapper inherits the parent's working
  directory, which was the real checkout, so the first `verbosity` run read settings files belonging
  to the real project. Read-only, and outside the two files this report hashes, but outside the
  sandbox. Every case was then pinned to `clone/` and the affected rows re-run.
- **Git for Windows does not follow a redirected `USERPROFILE`.** It resolves the global config from
  `HOME`, falling back to `HOMEDRIVE`/`HOMEPATH`, so a `git config --global` issued from a child
  wrote to the operator's **real** `.gitconfig`. That happened once, during setup of the clone, and
  was reverted; the hash pair below is the proof. The contained route is `GIT_CONFIG_GLOBAL`, which
  is what the run used thereafter.
- **A value in a git config file escapes backslashes.** A Windows path written raw into
  `GIT_CONFIG_GLOBAL` produces `fatal: bad config line 2`, not a warning.

### Elevation — the assertion this run could not make

**The assertion asked for was `IsInRole(Administrators)` → `False`. It measured `True`.** The shell
this UAT was driven from runs at High Mandatory Level with `BUILTIN\Administrators` enabled. That is
not a formality: a direct probe confirmed that shell **could create and delete a file inside the
machine's Program Files tree**, which is the class of accident that once destroyed a real tool's
configuration directory.

Rather than report a green assertion that was not true, or run the suite elevated, every command
under test was executed through `runas /trustlevel:0x20000`, which hands the child a restricted
token. Both halves were verified before the run started, with the same probe:

| Probe, run in the child | Driving shell | Command under test |
| --- | --- | --- |
| `IsInRole(Administrators)` | `True` | **`False`** |
| can write into the machine's Program Files tree | `YES` | **`NO`** |
| `USERPROFILE` / `CLAUDE_PLUGIN_ROOT` / `CLAUDE_PLUGIN_DATA` redirected | n/a | **all three intact** |

So the honest statement is narrower than the one requested, and is this: **no command in the tables
below ran with Administrators in its token, and none could write to a protected location.** The
harness that launched them did. Nothing here can retroactively de-elevate the harness, and this
paragraph exists rather than a tick.

### Containment

Hashed before the first case and after the last. Identical means no command under test altered them.

| File | Before | After | |
| --- | --- | --- | --- |
| the operator's real `.claude/settings.json` | `24AC1C4C…F0A8B` | `24AC1C4C…F0A8B` | identical |
| the tracked `config.json` | `FD70B926…50035B` | `FD70B926…50035B` | identical |
| the operator's real `.gitconfig` | `4D5F3A9B…8BC85D` | `4D5F3A9B…8BC85D` | identical — **restored**, see above |

The third pair is in this table because it did not stay untouched on its own. It was written by the
harness, detected by hashing, and reverted; restoring it byte-for-byte also required rewriting the
line endings, because the revert re-serialised the file as CRLF where git had written LF. An
identical hash here is a repair that was verified, not an event that never happened.

---

## Part 1 — the twelve commands

Verdicts are against the tree **as it now stands**, including the two installer fixes. `setup` would
have been FAIL before them.

| # | Command | Invoked as | Expected, per its command doc | Observed | |
| --- | --- | --- | --- | --- | --- |
| 1 | `checklist` | no arguments | "every item's state derived from a commit, a file, an exit code or a CI conclusion"; an item whose probe could not run "renders as unverified" | exit 0. 40 items: 21 done, 1 blocked, 15 UNVERIFIED, 3 not started. Every git-backed row degraded to UNVERIFIED naming the cause, the throwaway copy carrying no `.git` | **PASS** |
| 2 | `config` | no arguments; then `-Module … -On` | reports what is on; "refuses rather than guesses" | exit 0, full module table, and `delegate_gate` listed under `NOT SWITCHABLE HERE` unprompted | **PASS** |
| 3 | `delegate` | `-Flag delegate on` / `off` / `on -Scope repo` | flips `interaction.delegate`; "Report the `ENFORCED` block in full" | exit 0. Flag flipped `false`→`true`→`false` in the copy; `ENFORCED` block printed whole, including that `delegate off` will not work from the main thread afterwards | **PASS** |
| 4 | `doctor` | no arguments; `-Quiet` | "reports what is NOT working"; exit 1 = "at least one check FAILED" | exit 1, 9 checks, 7 passed / 2 failed. Both failures correct for a bare install. Blind spots printed on the passing run too | **PASS** |
| 5 | `plain` | no argument; `on`; `verbose` | reports current state when given no argument; rejects anything else | exit 0 reporting `OFF`; exit 0 setting `ON`; exit 2 on `verbose` — the verbosity axis does not bleed into this one | **PASS** |
| 6 | `resolve` | `-Session <invented id> -List` | "A refusal is the command working" | exit 1, `REFUSED — session … does not appear in ANY candidate health log`, candidate table printed with its one row | **PASS** |
| 7 | `setup` | all five steps, `-SettingsPath` redirected | "Nothing is written that was not shown first"; one section, one yes | exit 2 on detect (findings, not failure), nothing written; all three sections diffed before any write; see Part 2 for the eleven adversarial cases and two defects | **PASS** *(after F1, F2)* |
| 8 | `sitrep` | no arguments | "Separates verified from reported, and names what it could not determine" | exit 0. `[V]`/`[R]` tags distinct, every section printed including empty ones, `COULD NOT DETERMINE` carried both standing entries | **PASS** |
| 9 | `status` | no arguments; `-Brief` | "Report BOTH gate numbers, and never collapse them" | exit 0. `1 gate(s) SHIPPED` and `0 gate(s) LIVE` printed as separate lines; with the gate armed, `1` and `1` | **PASS** |
| 10 | `uninstall` | no arguments | dry run by default; "Show the LEFT BEHIND and the CANNOT SEE sections" | exit 0, both sections present, `cmd /c rmdir` line given verbatim for the junction. Scratch tree hashed before and after: **byte-identical** | **PASS** |
| 11 | `update` | `-Root <clone> -Offline -SkipDoctor` | "A fetch that could not run is UNKNOWN, never up to date" | exit 2. `[WARN] fetch  -Offline: … This is not evidence of being up to date.` and the position row annotated `(from a possibly stale fetch)` | **PASS** |
| 12 | `verbosity` | no argument; `brief`; `terse` | reports the level when given no argument; "`terse` … rejected on purpose" | exit 0 reporting `default`; exit 0 setting `brief`; exit 2 on `terse`, naming it and stating `Nothing was written` | **PASS** |

---

## Part 2 — adversarial cases

| # | Case | What happened | |
| --- | --- | --- | --- |
| 1a | `setup`: is a diff shown before every write, each section separately? | Three sections, three diffs, three separate `TO APPLY` lines each carrying its own `-BaseHash`. No diff step created or touched the settings file | **PASS** |
| 1b | `setup`: apply with a **stale** `-BaseHash` after a third party rewrote the file | exit **4**, `CONCURRENT MODIFICATION — NOTHING WAS WRITTEN`, both hashes quoted. File byte-unchanged | **PASS** |
| 1c | `setup`: rollback | Restored the backup **byte-identical** to the pre-write state, after keeping a pre-rollback copy first. Dry run wrote nothing. States plainly that it does not undo the status-line file copy | **PASS** |
| 1d | `setup`: apply the same section twice | "Already in the state requested. No backup taken, no write performed, the file is untouched down to its timestamp." Backup count stayed 1; hash and mtime unchanged | **PASS** |
| 1e | `setup`: corrupt the settings file to invalid JSON, then diff and apply | exit **5** on both. `Setup will not overwrite a settings file it cannot read.` The corrupt bytes were left exactly as written — not clobbered, not "repaired" | **PASS** |
| 1f | `setup`: invalid `-Step` value | Parameter validation error, exit 1, nothing written. **The exit code is shared with a real fault** — Finding **F1** | **PASS** *(F1 raised)* |
| 1g | `setup`: mistyped flag *names* — `-DryRunn`, `-StatusLineModee`, `-Nonsense` | **Silently ignored.** `-DryRunn` performed a real 15144-byte write at exit 0. Finding **F2**; fixed, re-run, now a binding error that writes nothing | **FAIL → fixed** |
| 2a | `config`: unknown module name | exit 1, `REFUSED — nothing was written`, names the registry and lists the ten known modules | **PASS** |
| 2b | `config`: write the delegate gate's flag through `config`, **with `-Apply`** | exit 1, refused. Explains that `modules.delegate_gate` would be "a flag that `Test-LwgModule` never reads", and routes to `/lw-gmhh:delegate` | **PASS** |
| 3 | `delegate`: on / off / per-repo | Global flip verified in the copy's `config.json`. `-Scope repo` created `repos["<slug>"].interaction.delegate = true` and left the global `false`. `status` moved `LIVE` from 0 to 1 and back | **PASS** |
| 4a | `verbosity`: invalid level `terse` | exit 2, named as unrecognised, not coerced; `Nothing was written`; config hash unchanged | **PASS** |
| 4b | `plain`: invalid value `verbose` | exit 2, rejected — a verbosity level is not a `plain` value | **PASS** |
| 4c | Plant an obsolete `output_style.brief` boolean in the copy's config | `OBSOLETE KEY` block fired, and **the key was not rewritten** — still present and `true` afterwards, as the doc promises | **PASS** |
| 5 | `doctor` **negative control**: remove `agents/lw-verifier.md` with `verification_gate` on | `[FAIL] agent-roles  verification_gate is ENABLED and ZERO verify-class roles are installed … so the advisory can nag and can NEVER clear.` FAIL is reachable. Restored afterwards | **PASS** |
| 6 | `resolve`: no outstanding faults | Refuses, exit 1, and says why rather than writing a marker to look busy | **PASS** |
| 7 | `uninstall`: default dry run | `plugin/`, `profile/` and `data/` hashed before and after: all three **identical**. Footprint, `LEFT BEHIND` and `AND WHAT THIS SCRIPT CANNOT SEE` all printed | **PASS** |
| 8a | `update`: `-Offline` | Reports UNKNOWN, explicitly "This is not evidence of being up to date" | **PASS** |
| 8b | `update`: dirty worktree | exit 1, `[FAIL] worktree`. The word "stash" appears **once**, in the disclaimer "This command does not stash, reset or check out anything". No offer to stash, reset or force. With `-Apply`: `[FAIL] pull  REFUSED — a check above failed. Nothing was merged.` HEAD unmoved, local edit intact | **PASS** |
| 8c | `update`: loaded-copy warning | With a junction pointing at a directory other than the checkout: `[WARN] loaded-copy  the junction points at … which is NOT this checkout. Updating here changes nothing that Claude Code loads` | **PASS** |
| 9 | `checklist`: no plan file under the redirected profile | `STALENESS NOT MEASURED: the source plan is not present at <scratch>/profile/.claude/plans/… (it lives outside this repo), so drift … cannot be measured here.` The reason is given, and the path proves the redirection held | **PASS** |
| 10 | `sitrep`: renders and separates verified from reported | `[V]` and `[R]` distinct; `COULD NOT DETERMINE` names both structural blind spots — that no hook records a subagent **dispatch**, and that nothing records a question put to the operator | **PASS** |
| 11 | `status`: gate counts | `SHIPPED` and `LIVE` printed on separate lines in both states. Never collapsed to one number | **PASS** |
| 12 | Invented flag names across ten commands | No command took a destructive action and no report claimed one. `uninstall -Apply` with an invented removal flag reported `APPLIED: 0 change(s)` and the footprint row still read `kept — pass -RemoveStatusLine`. But **eleven of the twelve scripts ignore an unknown flag in silence** — Finding **F2** | **PARTIAL** |

Two notes on Part 2, so neither reads as a discrepancy later. The `data/` directory legitimately
changed during case 12 — `doctor` appends to its write probe and `sitrep` advances its marker, both
by design. And `uninstall -Apply` with no valid removal flag is a no-op because every removal is
opt-in; that is the design working, not the flag being honoured.

---

## Findings

### F1 — `setup`'s exit `1` means two different things, and the doc described only one

`commands/setup.md` mapped exit `1` to "a write landed and did not check out", to be reported as
**a fault**, naming it and offering "the rollback line it printed". But PowerShell's own parameter
binding also exits `1`, **before a line of the script runs** — a `-Step`, `-Section` or
`-StatusLineMode` value outside its allowed set never reaches the code. Nothing is written and no
rollback line is printed, so an operator following the table would invent a fault that did not
happen and offer a recovery line that does not exist.

The two are cleanly distinguishable and the discriminator is reliable: every exit `1` the script
sets itself prints its reason on **stdout** first — verified across all three of its exit-1 paths, on
the diff, apply and rollback steps. A binding failure prints **nothing** on stdout and a
`ParameterArgumentValidationError` on stderr.

**Resolution.** `commands/setup.md` — the exit table row rewritten to name both meanings, and a
paragraph added that gives the stdout discriminator. Documentation only; no behaviour changed.
Commit `a223099`, together with F2: the two were found by the same case and the doc's exit-1 row
cannot be made accurate without the binding change beside it.

### F2 — a mistyped flag silently changed what the installer did, including turning a dry run into a write

`bin/lwg-setup.ps1` declared a plain `param()` block rather than `[CmdletBinding()]`. PowerShell
binds an unrecognised `-Something` as a **positional** argument and discards it, so a flag name the
script does not define was accepted and ignored. Measured, against the throwaway profile:

| Invocation | Before the fix | |
| --- | --- | --- |
| `-Step apply … -DryRun` | `DRY RUN COMPLETE … it would have written 15144 bytes`, file untouched | correct |
| `-Step apply … -DryRun` **`n`** | **`WROTE: 15144 bytes`**, backup taken, exit `0`, no warning of any kind | **a real write** |
| `-Step diff -Section statusline -StatusLineMode skip` | `NOTHING TO DO` | correct |
| `-Step diff -Section statusline -StatusLineMode` **`e`** ` skip` | `MODE: copy`, two actions planned | **silently used the default** |

The first row is the serious one. This installer's founding promise is that nothing is written that
was not shown first, and `-DryRun` is the mechanism the command doc offers to an operator who wants
to see the write without committing to it. One extra character turned that into the write itself, at
exit `0`. A mistyped answer flag likewise installed the **recommended** answer rather than the one
typed — the failure is silent in both directions.

**Resolution.** `[CmdletBinding()]` added to `bin/lwg-setup.ps1`, with a comment recording why it is
load-bearing. An unknown parameter is now a binding error before the script runs, and nothing is
written. Every caller in the repository passes named parameters only, so nothing legitimate is
refused. Commit `a223099`.

Re-run after the fix: `-DryRunn`, `-StatusLineModee` and `-Nonsense` all exit `1` with empty stdout
and `A parameter cannot be found that matches parameter name '…'`, writing nothing; `-DryRun`,
`-StatusLineMode skip` and a plain `-Step detect` all behave exactly as before. `tests/setup_merge.ps1`
46 of 46, `tests/gate_delegate.ps1` 62 of 62, `tests/stop_behaviour.ps1` 73 of 73,
`tests/workflow_guard.ps1` 0 violations.

### F3 — the same silent-ignore exists in the other ten scripts, and is **not** fixed here

Only `bin/lwg-toggle.ps1` declared `[CmdletBinding()]` before this run; `bin/lwg-setup.ps1` does now.
The remaining nine scripts with a `param()` block, and `bin/lwg-checklist.ps1` which has none at all,
still accept an invented flag in silence.

**It is left alone deliberately, and the reason is that they fail safe where `setup` failed unsafe.**
Every one of them defaults to the read-only behaviour and requires an explicit flag to act:
`uninstall` and `update` default to a dry run and need `-Apply`, `config` needs `-Apply` to write.
A mistyped `-Apply` therefore yields the *report*, never an unintended action — the opposite polarity
to a mistyped `-DryRun`. Their reports also stayed accurate under case 12: `uninstall -Apply` with an
invented removal flag still printed `kept — pass -RemoveStatusLine` against every item and
`APPLIED: 0 change(s)`.

This is recorded rather than fixed because adding `[CmdletBinding()]` to ten more scripts is a
behavioural change across the whole command surface that one UAT pass cannot exercise, and no test in
`tests/` covers nine of them. It is worth doing as its own change, with its own review.

---

## What this UAT does not establish

Read this section as seriously as the tables above. A green UAT is not a behavioural guarantee, and
the tables are narrower than they look.

- **One run, one machine, one day, one operating system.** Windows 11 and Windows PowerShell 5.1.
  Nothing here says how any of it behaves on another Windows build, under PowerShell 7, or on a
  machine laid out differently. The portability mandate in [portability.md](portability.md) is what
  addresses that, and it checks tracked files, not behaviour.
- **A sandboxed profile is not a real one.** Every command met an empty `.claude/` tree, no
  SessionStart record, no event log, no marketplace install and a plugin copy with no git history.
  Two `doctor` failures and fifteen `UNVERIFIED` checklist rows are consequences of the sandbox, not
  findings about the plugin — and equally, **no case here exercised a machine with real history,
  real trips or a real settings file full of someone else's keys.**
- **The commands were tested, the plugin was not.** Every case invoked a script in `bin/` directly.
  **Not one hook fired during this UAT**, no advisory was observed warning about anything, no
  SessionStart banner was rendered, and the status line was never drawn. Whether Claude Code loads
  this plugin, and whether its hooks fire when it does, is untouched by everything above.
- **`delegate_gate` was switched on and off, and never asked to refuse anything.** This run verified
  that the flag moves, that the copy's `config.json` records it and that the `LIVE` count follows.
  It did **not** verify that the gate blocks a tool call. That is `tests/gate_delegate.ps1`, which
  passed 62 of 62 here — and it remains the only behavioural test of blocking in the repository.
- **Nothing here tested the nine observing modules.** They warn; **no case in this report caused one
  to warn.** That is a statement about this run and nothing more. The second half of this sentence
  used to read *"and as limitations.md states, nothing in this repository tests that any of those
  warnings fires"* — `limitations.md` states the opposite in three places, and has since
  `tests/stop_behaviour.ps1` landed on 31 July 2026: `mission_drift` and `failure_capture` are
  exercised end to end there. Corrected by hand on 3 August 2026, this page being exempt from
  `tests/doc_claims.ps1` as a dated record of a run.
- **The verdicts are mine, and a passing row means the output matched the doc** — not that the doc
  is right, and not that the behaviour is wise. Where output and doc disagreed I recorded a finding
  rather than adjusting the expectation, but a case I did not think to run found nothing, and the
  adversarial list is a list I wrote.
- **Two defects were found by twelve adversarial cases against one command.** `setup` received by
  far the most hostile attention here, and it yielded two real defects, one of which turned a dry run
  into a write. The reasonable inference is not that the other eleven commands are clean; it is that
  they were tested less hard.
