# Testing and CI

## Eight files in `tests/`, and five of them test behaviour

Read this before anything else on this page.

`tests/gate_delegate.ps1` exercises `delegate_gate` — the one gate this plugin ships — with 93 cases,
each run through a real pipe into a real child process. `tests/setup_merge.ps1` drives
`bin/lwg-setup.ps1` against throwaway settings files and checks its **merge** on the `statusline`
section and what its `hooks` section **decides** — and, in four sections that are not about the
installer at all, it is the only place the **reporting surfaces** are exercised: `statusline/statusline.ps1`
run from a scratch copy with a payload on stdin, `bin/lwg-sitrep.ps1` and `lib/resolve.ps1` against a
scratch state directory, and `bin/lwg-update.ps1` against a local bare repository. They live there
because that file already owned the only harness that runs any of them for real. **That last section
needs `git` on `PATH` and ABORTS the suite without it** — not running is not the same as passing —
which is the one external binary any suite here depends on besides `powershell` itself; every
"remote" it builds is a local bare repository under the temp directory and no case reaches a network.
`tests/stop_behaviour.ps1` runs the two hooks that fire at every turn end —
`lib/stop_advisories.ps1` and `lib/supervisor.ps1` — with 169 cases, and is the only one that covers
an **observing** module. `tests/uninstall_footprint.ps1` drives `bin/lwg-uninstall.ps1` against
throwaway data directories and throwaway `settings.json` files with 22 cases, and is the only one
that covers a **deletion**.
`tests/evidence_states.ps1` holds `bin/lwg-evidence.ps1` to the one distinction the checklist rests
on — a probe that **ran and found the thing absent** versus a probe that **never got to look** —
with 47 cases, and is the only one that covers a **reporting** command.
`tests/portability_scan.ps1` scans tracked files for machine-specific strings,
`tests/workflow_guard.ps1` parses every workflow file and holds it to a set of rules, and
`tests/doc_claims.ps1` holds every tracked page to the tree on the quantities it states; all three
check the contents of tracked files and assert nothing about this plugin's behaviour at all.

So the coverage statement is narrow and exact: **the only behaviour any test in this repository
establishes is that the gate refuses what it declares, that the installer's statusline merge
preserves what it was not asked to touch, that six of the nine observing modules behave as
documented at turn end in the cases written for them, that the uninstaller's state-data footprint
names what it deletes and refuses to call a no-op deletion a success, and that the evidence engine
does not report a state it never observed.** The other three — `verification_gate`, `self_health`
and `context_injection` — are not exercised by anything, anywhere. The six are `mission_drift`,
`failure_capture`, `context_pressure`, `docs_coupling`, `git_hygiene` and `log_rotation`, and the
last four arrived on **3 August 2026** with one to three cases each on at most two properties apiece
(`context_pressure` 2, `docs_coupling` 2, `log_rotation` 3, `git_hygiene` 1), which is enough to say
they are no longer untouched and not enough to say they are tested.

Two removals and one addition got it here, all on **30 July 2026**, all explicit owner decisions.
First the removals:

| Removed | What it covered | What went with it |
| --- | --- | --- |
| the gate regression suite | 233 cases over the two `PreToolUse` gates | the `lw-watchtower:verify` command and the `gate-regression` CI job |
| the `permissions.deny` parity test | the installer's deny table, and the installer's merge behaviour end to end | its two fixtures and the `permissions.deny parity` CI step |

The first went with `destructive_gate`, the second with `secret_scan` — see
[Both gates were removed](modules.md#both-gates-were-removed). Neither was deleted because it was
failing or redundant. The suites went because the code they covered went.

Then the additions. `delegate_gate` was built later the same day and `tests/gate_delegate.ps1` was
written with it. **It is not a revival of the 233-case suite** and covers none of what that covered —
nothing here inspects a shell command, a path or a credential any more.
`tests/workflow_guard.ps1` came after it, and replaced an evidence rule rather than a test: see
[The workflow guard](#the-workflow-guard).

A green CI run now means exactly ten things: every tracked JSON file parses, every `.ps1` file
parses, no workflow file reaches a runner GitHub does not host or a secret — and every other YAML
file under `.github/` at least *parses*, and the guard was shown able to fire on each of its rules
rather than only shown to say nothing — `delegate_gate` still
refuses what it declares, the installer's `statusline` merge still preserves unrelated keys and
rolls back, the two `Stop` hooks still behave as documented, the uninstaller still deletes exactly
the state data its footprint listed and still exits non-zero rather than reporting a no-op deletion
as a success, the evidence engine still tells a probe that could not run from a probe that ran and
failed, every tracked file was *read* and none names a machine, and no tracked page states a count
the tree contradicts. **It means nothing more than that** — and note two limits inside it: parsing
`dependabot.yml` is not validating it against GitHub's schema, and a rule proved to fire on one
planted shape is not a rule proved correct.

## What still runs

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\gate_delegate.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\setup_merge.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\stop_behaviour.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\uninstall_footprint.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\evidence_states.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\workflow_guard.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\portability_scan.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\doc_claims.ps1
```

Eight files, all in the `fast-checks` CI job. Each behavioural suite spawns a child PowerShell process
per case, and that is the point of them; the parse steps, the guard and the scan are seconds at most.
Measured on 3 August 2026 on **one developer machine** — not on a GitHub runner, which nothing here
has timed — the merge suite took 248 s, the gate suite 179 s, the stop-hook suite 149 s, the
uninstaller suite 102 s and the evidence-state suite 17 s. **These figures move every time a suite
gains cases and they had been four times out of date before that measurement**, so read them as an
order of magnitude and re-measure rather than quoting them.

The documentation-claim guard re-runs the seven other files in parallel to read the tallies they print
about themselves, so it costs the slowest of them — 249 s on the same machine — rather than the sum.
`-SkipSuites` skips that and then **exits 2 rather than 0**, because a run that did not check
something must not report as one that did. The job's `timeout-minutes` and the `-SuiteTimeoutSec` the
CI step gives that guard are held in step by a rule inside the guard itself, which reads both numbers
out of `ci.yml` and fails if the wait is not strictly inside the budget — otherwise the job cap wins
and the guard's documented abort can never fire.

## The delegate gate suite

`tests/gate_delegate.ps1` runs every case as

```
type payload.json | powershell -File lib\gate_delegate.ps1
```

through a `.cmd` file, because **a PowerShell object pipe never reaches `[Console]::In`**, which is
where a hook reads its payload. Calling the script's functions in-process would test different code
from the one Claude Code invokes.

Nothing real is touched. Every case points `CLAUDE_PLUGIN_ROOT` and `CLAUDE_PLUGIN_DATA` at a
throwaway directory holding a copy of the repository's own `config.json` — the shipped file rather
than a hand-written fixture, so the cases run against the shape that ships, comments and all. The
flip to `delegate: true` asserts it replaced exactly one occurrence, so a config whose spelling
changed aborts the run instead of quietly producing cases that all pass by agreeing with the wrong
answer. No case constructs a destructive command, even as a string it never runs.

What it covers: the registration in `hooks.json` (exec form, no `shell:`, matcher covering every gated
tool, and — since 1 August 2026 — that it does **not** cover `Agent` or `Read`); that the source reads `agent_id` and **never** `agent_type`; that the registry entry is
`kind = 'gate'` with `switch = interaction.delegate` defaulting off; that `/lw-watchtower:delegate` reports
storing to the same key the gate reads; that the shipped config leaves the gate off; deny and allow
for each of the five tools in each of the four switch/caller combinations; the exit-2 contract, with
**exit 1 checked for by name** because exit 1 does not block and is the silent fail-open; a payload
carrying `agent_type` but no `agent_id`; an empty and a whitespace `agent_id`; a forged `agent_id`
inside `tool_input.content`; eight shapes of malformed or absent stdin in both switch states; a
corrupt and an absent `config.json`; and the per-repo override in both directions.

Exit codes: `0` every case passed, `1` at least one failed, `2` the suite aborted — and zero cases
run is an abort, never a pass.

**What a green run does not mean.** See the header of the file itself, and
[Why a regression test must still fail before the fix](#why-a-regression-test-must-still-fail-before-the-fix)
below: the last gate's suite was 67/67 green while five bypasses were open. The inversion
(`agent_type` for `agent_id`), the fail-open (`exit 1` for `exit 2`) and a narrowed matcher were each
introduced deliberately and each caught.

**"Every case here was confirmed red before it was kept" is no longer true of every case, and the
exception is named rather than dropped.** It was true when written. On 1 August 2026 `PowerShell`
was added to the gated tool list, and the four section-D cases that came with it — deny and allow,
switch on and off — were **run against the pre-fix tree and passed there**. They could not have
done anything else: the gate is tool-blind, so piping a `PowerShell` payload into it produces a
correct refusal on a tree whose matcher would never have delivered that payload. Those four pin
that the rule treats the second shell like the first, which is worth having and is not what was
broken. The two cases that *did* go red on the pre-fix tree are the registration case in section A
and **M1**, and section M exists precisely because a case that cannot see the matcher cannot see
that class of hole.

## The installer merge suite

`tests/setup_merge.ps1` is the half of the deleted `permissions.deny` parity test that was never
about deny rules, re-targeted at a section that still writes. `bin/lwg-setup.ps1` merges into the
operator's real `settings.json` — the file holding every other setting they have — and from
30 July 2026 until this suite landed, nothing checked that merge while `/lw-watchtower:setup` went on
performing it.

It drives the **real installer in a real child process**, because that is the file the command
invokes. The installer takes parameters rather than stdin, so each case is
`-Step diff|apply|rollback -Section statusline|hooks -SettingsPath <scratch>\settings.json`, with
`$env:USERPROFILE` swapped to a scratch profile around the call and restored in a `finally`. Those
two knobs are the whole sandbox contract, documented in the installer's own header: `-SettingsPath`
redirects every settings read and write, and the status-line target, state directory and agent
directory all hang off `$env:USERPROFILE`. `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA` and
`CLAUDE_CODE_PLUGIN_CACHE_DIR` are **cleared** around every child and restored in the same `finally`
— the install-mode detection reads all three, and one inherited from the runner's own process would
point the code under test outside the scratch tree. The one exception is deliberate and is why the
relocated-cache cases below can exist at all: `Invoke-StatusLine` takes a `-CacheDir` that **sets**
`CLAUDE_CODE_PLUGIN_CACHE_DIR` instead of clearing it, defaulting to empty so every other case is
unchanged. Clearing it unconditionally is what made that variable's own failure mode unreachable by
any case for as long as it existed. Every scratch path is built at runtime from
`[IO.Path]::GetTempPath()`, so nothing in the tracked file names a machine.

The fixture has its top-level keys in **deliberate non-alphabetical order** — `zeta`, `permissions`,
`statusLine`, `alpha` — because the defect `Set-PropValue` exists to prevent is a replaced key
silently moving to the end of the file, and an alphabetical fixture cannot tell "kept in place" from
"re-sorted". `permissions.ask` holds exactly one element, and `statusLine.refreshInterval` is 45
rather than the installer's default of 120, so "the operator's own tuning is kept" is a claim with a
value behind it.

What it covers: a settings file that does not exist yet (`BASEHASH: none`, and an apply that accepts
that literal); `apply` with no `-BaseHash` refused with exit 5; a **stale** `BaseHash` refused with
exit 4, the other writer's bytes left alone and **no backup taken**, because a backup is a write;
unrelated top-level keys keeping their values and their order; exactly one backup, holding the
original bytes; `refreshInterval` 45 preserved; the `copyfile` extra action in both its branches —
creating the status line, and overwriting a different one while keeping a `.bak` beside it; an
idempotent second run that takes no second backup and leaves the file byte-identical; rollback
restoring byte for byte and keeping a pre-rollback copy; rollback **never offering that copy** as a
restore target, which would let repeated rollbacks walk forwards again; a BOM round-trip, where the
backup keeps the BOM and the newly written file has none; a target that does not parse, refused by
both `diff` and `apply` even with a matching hash; `-DryRun` writing neither the settings file nor
the status-line copy; rollback with nothing to restore; and a backup that does not itself parse.

**The `hooks` section, and the install-mode detection that decides it.** Setup looked for a
marketplace install under `~\.claude\plugins\repos`, a directory that does not exist on a live
Claude Code install — the string appears **zero** times in the 2.1.x CLI binary, while
`marketplaces` appears 86 times. So a marketplace-installed plugin was classified *not discoverable*
and the section wrote a **second full copy of every hook registration**, with the duplicate-firing
warning suppressed because it read the same flag: eight events, each firing twice.
`statusline/statusline.ps1` carried the identical assumption in `LwgPluginRoots`. The suite plants
the layout the CLI actually writes — `plugins\cache\<marketplace>\<plugin>\<version>`, the path
`installed_plugins.json` records as `installPath` — and covers: detection naming it rather than
reporting `NOT DISCOVERABLE`; `-HookMode auto` resolving to `MODE: plugin` and planning nothing;
applying that section writing nothing at all; a forced `-HookMode standalone` still printing the
duplicate-firing warning **and the evidence it rests on**; the same script already registered from a
**different root** being reported and not added beside it, so `session_start.ps1` ends up registered
exactly once; and `statusline/statusline.ps1` itself, run from a copy under the scratch profile,
resolving that root — no purple `HH?`, the dim `HH-` instead, and a `config.json` under that root
actually read.

Three further groups landed on 3 August 2026, all of them about the same failure — **one hook
registered twice** — reached by routes the section above could not see:

- **A superseded matcher.** Both hook-identity functions key on the matcher *string*, and `v0.3.0`
  wired the delegate gate to `Edit|Write|NotebookEdit|Bash`. Widening that matcher made every
  `v0.3.0` registration unrecognisable, so an upgrade added a second `PreToolUse` group invoking the
  same `lib/gate_delegate.ps1` — two runs per call of the only hook here that can *block* one. Until
  these cases there was **no `PreToolUse` fixture in this suite at all**, so its green said nothing
  about any of it. Covered: the old registration recognised rather than duplicated,
  `gate_delegate.ps1` registered exactly once after `apply`, and the stale matcher **named in the
  report** — because recognising it silently would leave `PowerShell` unhooked while telling the
  operator the gate was present.
- **A hook spelled as a `command` string.** The path walk tested `\.ps1$` against the whole string,
  so it saw that shape only when the path was the last thing on the line. Both realistic spellings —
  a quoted path, and a path with a trailing argument, which this plugin's own `supervisor.ps1`
  registration needs — were missed, and each produced two registrations. Covered in both spellings.
- **A relocated plugins directory.** `CLAUDE_CODE_PLUGIN_CACHE_DIR` is supported and the installer
  reads it; the status line did not, so the two files disagreed about where the plugin lived on the
  same machine. Covered: the status line resolving an install under a relocated base and reading its
  `config.json`, plus a **control** that an install at the *default* base is still found when the
  variable points elsewhere — so the fix cannot degenerate into "read the variable instead".

**Five of those cases are labelled `CONTROL` and pass before the fix they sit beside as well as after
it.** They pin the other direction: a profile with no install still resolves to `standalone` and
still plans the registrations; the operator's own registration under another root survives the apply,
because this installer never removes; an install at the *default* base is still found when
`CLAUDE_CODE_PLUGIN_CACHE_DIR` points elsewhere; and with nothing planted the status line still
renders `HH?`. **They do not share one baseline** — four of the five pass at `fd8d023`, the commit
this suite was built around, and the relocated-cache one passes only against the working tree as it
stood immediately before its own fix, because neither file read that variable at `fd8d023`. None of
them is offered as evidence that anything was fixed, and each is named in its own comment.

**What "preserved" means here, since it is less than it sounds.** Applying re-serialises the whole
file, so the claim about an unrelated key is **value and order** identity, not byte identity. Byte
identity is asserted only where the installer really promises it: the no-op short-circuit, the backup
it takes, and rollback.

Four things are **named as not covered** in the suite header rather than left to be inferred. The
backup-collision suffix needs two writes inside one second, which is a race with the clock, and a
case that is sometimes exercised gets deleted the first time it goes red for no reason. The
post-write auto-restore is unreachable without fault injection, because the merged JSON is
parse-checked before the write. **No case proves that the CLI build you are running still writes the
plugin layout the fixtures plant** — that layout was read off one machine and one binary, which is
why both files also keep the legacy `plugins\repos` candidate. And **two ways the detection can still
be wrong, both in the same direction** — it reports the plugin as loading when nothing does, and the
`hooks` section then wires up nothing at all: whether an *installed* plugin is also *enabled* is an
`enabledPlugins` entry in a settings file whose project scope is invisible from the installer; and a
**project-scoped** install belonging to a different repository sits in exactly the same
`plugins\cache` tree as a user-scoped one. `installed_plugins.json` records `scope` and
`projectPath`, setup prints both on the evidence line, and it does **not** narrow its verdict on
them — a verdict narrowed on a guess about which project a settings file will be used from would be a
second wrong answer dressed as a fix. None of the four is faked.

Exit codes: `0` every case passed, `1` at least one failed, `2` the suite aborted — and zero cases
run is an abort, never a pass. The byte-level **writer** properties are established on the
`statusline` section and merely inherited by `hooks`, which goes through the same `Save-Settings`
path; `permissions` writes nothing and is not exercised at all.

## The stop-hook behaviour suite

`tests/stop_behaviour.ps1` covers the two hooks that run at **every turn end**: the advisory handler
`lib/stop_advisories.ps1` and the health supervisor `lib/supervisor.ps1`. It landed on 31 July 2026,
and what it replaced was nothing at all — `mission_drift` had been on by default, at every turn end,
on every install, with **no test of any kind**, and the supervisor carried two comments describing
bugs that had already shipped with no case pinning either fix.

Five sections, 169 cases:

- **A — pure helpers, in process.** `lib/common.ps1` is dot-sourced and the mission-anchor helpers,
  the incremental transcript reader and the agent-class reader are called directly. A unit call names
  the failure precisely: *a version number was read as a filename*, rather than *the advisory did not
  fire*. Among them are the two values that look like nothing and are not: an `lw-class` that is
  absent reads `''` — **no information**, never "not a verifier" — and a typo'd value is not coerced.
- **B — `mission_drift`, end to end, in child processes.** A turn is one child run; a multi-turn case
  is several, with the transcript grown and the edit list extended in between, because the module's
  whole behaviour is carried in state files from one turn to the next. It fires on three unaccounted
  edits outside the workspace and emits an envelope with **no `decision` member**; it stays silent
  below `min_files`, for work inside the workspace, with nothing named in any prompt, after it has
  already warned about that set, once a turn has overrun `max_scan_bytes` (and for the rest of that
  session), and when `stop_hook_active` is set. **Ten cases** (B12–B19) cover what it keeps of a
  **prompt** and the bounds on what it reads: that a credential pasted into one reaches neither
  `advisory-<sessionkey>.json` nor the emitted `systemMessage`, tested with an AWS-shaped key id and
  again with a pasted **PEM private key** — whose base64 body contains `/`, which the tokeniser reads
  as a path separator, so its fragments were promoted to the anchor kind the advisory *quotes*; that
  the ordinary anchors in the same sentence survive both; that anchors persisted before the redaction
  landed are discarded and rebuilt rather than carried forward; and that the 400-record parse bound
  latches `md_incomplete` exactly as the byte bound does instead of leaving the module judging a
  session on a set it does not know is short. Three of the ten are anti-vacuity guards rather than
  leak tests — they pin that the module still speaks, because a "fix" that ate the prompt would pass
  every search made of an advisory it never emitted.

  Six later cases (B20–B25) pin the bounds the module reports *under*, and each was proved red
  against `cc44c99` before its fix landed: that a standing drift warns **once per session** rather
  than again on every turn that adds a file to the unaccounted set; that an anchor set which reaches
  `max_anchors` latches `md_incomplete` instead of going deaf while still judging, and that a pivot
  announced after that point is therefore not reported as drift; that the shared edit list **rolls**
  at 256 KB rather than stopping, so a file edited after the cap is still recorded; and that one
  200 000-character `tool_input.file_path` is bounded both where it is written and where it reaches
  the operator's `systemMessage`. B24 is the only case in this suite that is not about
  `mission_drift`: it drives three turn ends with `git` unresolvable and asserts the **UNKNOWN** tree
  state is reported at every one of them, because `git_hygiene`'s silence is documented to mean *git
  said there is nothing wrong*. B25 is the other one: it feeds `context_pressure` an occupancy above
  the assumed window and asserts the module **refuses** it — reports no percentage and pins nothing —
  and then that a second, corroborating reading is what promotes it to a learned window.

  <!-- This number is not one doc_claims can read: it recognises "N cases" only against a suite
       FILENAME, and this is a count of one section inside one suite. It was wrong before (it said
       five when the block held seven) and the guard was green over it. Counted by hand from the
       `Add-Result` calls between B12 and B19. -->

- **C — `failure_capture` and `log_rotation`, end to end.** Registration in `hooks.json` including
  the `asyncRewake` that makes exit 2 an *alert* rather than a *block*; the two shipped-bug
  regressions below; the interrupt that must not alert **and must still be recorded**; that the
  dedupe lets an *unseen* dead task through, which is the arm that makes it a dedupe rather than a
  mute switch; and that rotation runs with `failure_capture` **off**, which is the whole reason its
  call sits above that gate. C10 runs the supervisor against a `common.ps1` that cannot be
  dot-sourced and asserts **exit 0 and empty stderr** — the file's header has promised that since
  Phase 2 and no case had ever run it.
- **D — log hygiene.** The size, the encoding and the archive set of the files the other three
  sections write. `Invoke-LwgRotate` is called in process against a throwaway state directory; the
  status line is run for real in a child process, because what this section asserts about it is how
  long it takes. D is the only section that **measures** rather than compares, and its one timing
  case asserts a *difference* between two medians taken back to back in the same run, never an
  absolute duration — an absolute threshold is a case that fails on a slow laptop for reasons that
  have nothing to do with the code.
- **E — this suite itself, in process.** One case, and the only one here that asserts on the suite
  rather than on something the suite tests: that the operator's live event log is the same size in
  bytes after the run as it was before it. Section A's in-process calls used to append a record to
  that file for every non-boolean fixture it passed, and no other case in this file could have seen
  it — every other case reads an exit code, a stream, a state file the suite made, or a wall-clock
  median, and an appended record moves none of those. Two limits are stated in the suite rather than
  left to be found: it asserts a **size**, which is not content, and it can go red for a write it did
  not make, because that file has one writer per *process* — a Claude Code session open in another
  window appends to it too. If it fails alone, re-run the suite with no session open before reading
  it as a regression.

**The two shipped-bug regressions**, named because they are the reason the file exists:

| Case | The bug that shipped |
| --- | --- |
| C1 | `ConvertFrom-Json` hands back a single-entry file as a bare string, and in Windows PowerShell it writes a multi-entry array to the pipeline **without enumerating it**, so `@()` keeps the whole array as one element and `-notcontains` stops matching. A dedupe that silently stops deduping re-alerts the same dead task at every turn end for the rest of the session. |
| C2 | One failed background task unrolls to a bare `PSCustomObject` whose `.Count` is `$null`; the status line reads `[int]$null` as `0`, so `"failed_tasks":null` was logged and the health indicator stayed green through a real failure. Two such records exist in the inherited log. The case asserts the **record**, not just the exit code — without the fix the run still exits 2 and only the log is wrong. |

Every case was written by breaking the code and checking the break was caught. Five breaks, five
distinct reds: clearing the anchor rehydration turned **B2 turn 3** red and nothing else; removing
the truncation latch turned both B5 cases red; dropping the `@()` around `Get-FailedTasks` turned
only the C2 *record* assertion red; removing the dedupe flatten turned the two array-shaped C1
variants red **but not the bare-string one**, which is why the multi-entry array is the variant that
carries that guard; and moving the rotation call below the module gate turned both C5 cases red.

Fixtures here are **hand-built**, unlike the gate suite's byte copy of the shipped `config.json`:
these cases need one module on and the other four off, and several need a knob at a value nothing
ships — `max_scan_bytes` at 512, so a transcript can overrun it in a few hundred bytes rather than
two megabytes. The workspace and the "outside" tree are **siblings** under one scratch directory,
which is load-bearing: `Get-LwgMissionScope` stop-lists every segment at or above the workspace's
parent, so a tree placed anywhere above would share a segment with the workspace and be excused by
it, and the case would pass for the wrong reason.

Exit codes: `0` every case passed, `1` at least one failed, `2` the suite aborted — and zero cases
run is an abort, never a pass.

**What a green run does not mean.** No case here can tell a *correct* warning from one an operator
would call noise, because that judgement is not in the code. The trigger has still never been
validated against real sessions, and the false-positive class in [Modules](modules.md#mission_drift)
is still live for every install.

## The uninstaller footprint suite

`tests/uninstall_footprint.ps1` is the only suite that tests a **deletion**, and it exists because
the thing it now pins had already shipped.

Adversarial UAT against `v0.3.0` on 31 July 2026 found `bin/lwg-uninstall.ps1` resolving the
state-data location with a **hardcoded** `~\.claude\plugins\data` and never reading
`CLAUDE_PLUGIN_DATA` — the variable `lib/common.ps1` calls "authoritative and ends the matter", the
one Claude Code hands every hook, and the one every other component resolves through. With the data
directory redirected, `/lw-watchtower:doctor` reported `state-dir … (source 'env')` holding five live
files while the uninstaller reported `state-data absent`, and
`-RemoveData -ConfirmToken DELETE-MY-LWG-LOGS` printed `APPLIED: 0 change(s), 0 failure(s)` and
exited `0` with all five files still on disk. An operator typed a destructive confirmation token,
was told it had worked, and nothing had been deleted — a switch wired to nothing wearing a success
message, which is the founding defect this plugin exists to catch.

Ten cases, each a real child run of the real script with `$env:USERPROFILE` and
`$env:CLAUDE_PLUGIN_DATA` redirected at a throwaway tree under the temp directory. Every case
asserts on the **filesystem** as well as on the report, because a suite that only read the text
could be satisfied by a script that prints well and deletes nothing — which is what shipped. What
they pin:

- with `CLAUDE_PLUGIN_DATA` pointing at a seeded directory that the discovery sweep cannot reach,
  the dry run names **that** directory, reports `source 'env'`, and leaves every file alone;
- `-Apply -RemoveData -ConfirmToken` really removes it, prints one deletion line, and reports
  `APPLIED: 1 change(s), 0 failure(s)`;
- with the variable unset, the discovered `<name>-<source>` fallback is used and named, so the fix
  did not swap one hardcoded answer for the environment variable and lose the fallback;
- **`UNRESOLVED` is never reported as `absent`.** A location that resolves and holds nothing is
  `absent` and exits `0`; a location that will not resolve at all is `UNRESOLVED` and exits `2`,
  in the dry run as well as under `-Apply`;
- the plan and the deletion agree: with both an env-redirected directory and a discoverable
  sibling present, both go and an unrelated directory sitting beside them survives;
- the dry run deletes nothing **even with the destructive flags and the real token present**, and a
  wrong token refuses with exit `1` and touches nothing.

**Test safety is a stated contract in the suite header, not an assumption.** These cases run the
uninstaller in apply mode with a real confirmation token, so: every scratch path is built at runtime
from `[IO.Path]::GetTempPath()`; `$env:USERPROFILE` is redirected for *every* child invocation,
including the ones passing no destructive flag, because the sibling sweep hangs off it and a case
that forgot would sweep the real `~\.claude\plugins\data`; and the only directories any case can
reach are ones it created seconds earlier. Read that header before adding a case.

Exit codes: `0` every case passed, `1` at least one failed, `2` the suite aborted — and zero cases
run is an abort, never a pass.

**What a green run does not mean.** It covers the state-data half only. The `settings.json` edits —
the `statusLine` removal, the `permissions.deny` removal, the concurrent-change refusal and the
`-RestoreSettings` path — are not exercised here, nor is the junction row, which is report-only by
design. Nor is a deletion that *partially* fails: the script now verifies the directory is really
gone before counting a change, but reaching that branch needs a file held open by another process,
and a case that faked it would assert on the fake.

## The evidence-state suite

`tests/evidence_states.ps1` covers `bin/lwg-evidence.ps1`, the engine both `/lw-watchtower:checklist` and
`/lw-watchtower:sitrep` read. It asks one question in 47 cases: **can the engine tell a probe that ran and
found the thing absent from a probe that never got to look?** Those two render as `[ ] NOT STARTED`
and `[?] UNVERIFIED`, and the difference between them is the entire argument this plugin makes.

### What shipped, and how it was found

Until 31 July 2026 a `kind: command` rule scored **any** unexpected exit code as a finding. On the
**marketplace install route** — the one [Install](install.md) calls recommended for consumers — the
plugin directory carries no `.git`, so every git-backed rule exited `128` having read nothing, and
the engine rendered that as *the condition was not met*. Two rows flipped, and read as the product
defines that mark they said: **the owner's personal address WAS left in history**, and **the private
sibling project's name IS in the tree**. Both are false, and neither had been measured. On a junction
install of the same commit both rows were correct, which is exactly why nothing caught it — the
defect was invisible from the machine the plugin is written on, and it took an adversarial UAT
against the `v0.3.0` tag on the other install route to surface it.

### What the engine now treats as "could not run"

The **ladder in `Resolve-LwgChecklist` did not change**, and its rung order is untouched. What
changed is which results reach rung 3 (*evidence could not be checked → `UNVERIFIED`*) rather than
falling to rung 8 (*otherwise → `NOT STARTED`*):

| Signal | Why it is not a finding |
| --- | --- |
| the program will not start | it answered nothing — this one always did degrade correctly |
| git exits `128` with a `fatal:` naming no repository, no work tree, or a refused ownership check | git declined before reaching the question. **Both halves are required**: `128` is also git's code for a bad revision, where the probe genuinely ran |
| an interpreter refuses the script it was pointed at (`-File` target absent) | `powershell` starts fine and *then* refuses, so this is not the missing-program case. `P6-workflow-guard` runs its suite this way, and *the suite is not installed* must not borrow the meaning of *the suite found a violation* |
| an exit code the rule declares ambiguous, via `nonzero_means: unverified` | the older knob, unchanged, and now checked *after* the two above so a rule that never declared it still gets the honest answer |
| the expected exit code with **empty stdout**, under a rule that proves its item from `stdout_match` | a pattern cannot be settled either way against output that does not exist. `git tag -l` exits 0 and prints nothing on a clone whose tags were never fetched — a gap `P8-tag`'s caveat had carried in writing since that rule was written |

Empty stdout under `stdout_not_match` **alone** is still a pass, deliberately: a probe that lists
offenders and lists none is answering. A rule that wants both readings carries both keys, and
`stdout_match` is tested first.

### The half that matters more

Answering `UNVERIFIED` to everything would make the blocker's cases green and would be a **worse**
defect than the one it replaced — a checklist that can never say a thing is undone reports nothing at
all. So **fifteen of the 47 cases require an answer to stay an answer** — a `pass`, a `fail`, or a
rendered `NOT STARTED`. Among them: an unexpected exit with no could-not-run signal, output that is present and
does not match, output that still matches a `stdout_not_match`, a rule whose pass *is* a nonzero
exit, the same shipped git rules evaluated in a real checkout where they must reach a verdict, a
commit miss in a scan that reached the root of history, a hook registration that is genuinely wrong,
and a line-ending pin genuinely absent from one of two files. Those fifteen are the sentinels: each
one goes red if a fix in this engine is ever made by widening what counts as "could not look".

### The fixture

Sections A–F call the engine in process — it is a dot-sourced library, and `bin/lwg-checklist.ps1`
reaches it exactly that way. Section G runs `bin/lwg-checklist.ps1` in a **real child process**
against a throwaway plugin root and reads the rendered mark out of its stdout, because the rendered
mark is what a consumer sees.

That throwaway root is built by **copying** four files to a temp directory. Nothing is deleted to
produce it: a fixture built by removing a `.git` is one bad path away from removing a real one. Two
fixture assertions abort the run rather than let a case pass for the wrong reason — that the scratch
root resolves **no** git root (a temp directory inside a checkout would give the fixture a repository
and section A would exercise nothing), and that the repo root resolves **one** (without it only the
negative half would run, which is the shape that made the defect invisible). Section A takes its two
rules **out of the tracked `checklist.json` by id** rather than restating them, and aborts if either
stops being a git `command` rule.

Exit codes: `0` every case passed, `1` at least one failed, `2` the suite aborted — and zero cases
run is an abort, never a pass.

**What a green run does not mean.** It does not mean the engine can tell the two apart in general. It
means it can for the five signals in the table above. Every other way a probe can answer a question
it never reached is still scored as a finding — a `gh` call that returns success with an unexpected
body, a script that exits 0 having done nothing — and this suite says nothing about those.

## The workflow guard

`tests/workflow_guard.ps1` parses **every file under `.github/workflows/`** and holds it to the nine
rules below, failing the build when one of them fires. Since 3 August 2026 it also **parses, without
applying any rule,** the rest of `.github/` — `dependabot.yml` and the issue-template files, which
GitHub reads at run time and which no CI step read before that date. A file there that does not parse
fails the build under `unparseable`; a file that parses but is wrong for GitHub's schema does not,
because **parsing is not schema validation** and nothing here validates one.

The guard is also **run against fixtures built to violate each rule**, with
`tests/workflow_guard.ps1 -SelfTest`, from inside the same CI step. Until that landed, nothing in this
repository had ever run it against a violating workflow: every invocation pointed it at a clean tree,
where the expected answer is `0`, so the branch that *fires* had no evidence behind it at all. The
self-test asserts each rule fires on one shape of input planted for it, that a clean fixture directory
exits `0`, and that an empty or absent one exits `2`. **One shape per rule is a floor, not proof the
rule is right in general** — the matrix rule is proved on a list of literal labels, not on an
`include:` entry or a `fromJSON`.

The nine rules fire when a workflow file:

| Rule | Fires on |
| --- | --- |
| `self-hosted-runner` | a `runs-on` label that is not a known GitHub-hosted image — scalar, label array, or `labels:` list |
| `runner-group` | `runs-on:` selecting a runner by `group:`, whose membership is repository configuration this scan cannot read |
| `matrix-self-hosted` | the same, reached through `runs-on: ${{ matrix.x }}` and a value in `strategy.matrix` or its `include:` |
| `runner-unresolvable` | a `runs-on` expression that does not resolve here — an undeclared matrix key, a `vars.`/`inputs.`/`needs.` reference — or a job with no `runs-on` at all |
| `pull-request-target` | the `pull_request_target` trigger, as a key or in an `on:` list |
| `secrets-expression` | any `${{ secrets.* }}`, including `${{ toJSON(secrets) }}` |
| `secrets-key` | a `secrets:` key anywhere — `secrets: inherit` on a reusable-workflow call, or an `on.workflow_call.secrets` declaration |
| `external-reusable-workflow` | a **job-level** `uses:` calling a workflow in another repository. A local `./.github/workflows/x.yml` call is not reported, because that file is scanned too |
| `unparseable` | a file the reader could not parse, or a construct it does not implement — anchors, aliases, merge keys, multiple documents, tab indentation |

The self-hosted rule is the reason the file exists, and it is **not** a search for the string
`self-hosted`. It holds `runs-on` to a list of known GitHub-hosted labels and reports everything
else, because `runs-on: office-build-box` is a self-hosted runner that never spells it out. The cost
is that a GitHub-hosted *larger* runner, which also carries an org-chosen label, is indistinguishable
from here and is reported too.

**It parses; it does not grep.** Files are read into a tree — block mappings, block sequences, flow
collections, quoted scalars, block scalars — and the rules ask about structure: which key, in which
job, on which line. That is what lets a job-level `uses:` be told apart from a step's `uses:`, and a
label array from a `group:` mapping. Two rules also run a raw line sweep on top of the structural
walk, and both are the conservative half: `${{ secrets.* }}` is swept over every line **including
`run:` script**, because an expression is interpolated wherever it is written;
`pull_request_target` is swept over YAML values but **not** over `run:` script, because only an
`on:` block can select a trigger and a token in a shell command cannot.

Comment text is not swept. A comment cannot run, read a secret or select a runner — and that is
exactly the distinction the rule this guard replaced could not make.

Enumeration is a glob of the directory, recursive, never a file list. Exit codes: `0` nothing fired,
`1` at least one hit **or at least one file that would not parse**, `2` the guard aborted — and an
enumeration returning zero files is an abort, never an empty-set pass. A file that could not be
parsed is reported as a violation rather than as a clean file, because a file that was not checked is
not a file that passed.

### What it replaced

The evidence rule for this check used to be *"`.github/workflows/ci.yml` contains the string
`self-hosted`"*. **A comment satisfied it** — and it would have gone on passing while a self-hosted
runner was actually introduced, since the string is present either way. There are self-hosted runners
registered on the maintainer's machine, so the thing that rule claimed to watch is the thing that
would end worst: a workflow reaching one hands whoever can trigger it code execution on real
hardware.

### What it does not cover

- **Composite actions and third-party actions.** `uses: owner/repo@ref` in a step runs code this
  guard never reads. Pinning those to a digest is a separate control and it does not exist yet.
- **Workflows on other branches.** It scans the working tree it runs in.
- Everything a workflow can do that is not one of the nine rules above.

Its allowlist is **deliberately empty**. The schema is in the file so a future exemption has a shape
to take; `secrets.GITHUB_TOKEN` is specifically *not* pre-approved, because an entry written before a
concrete step needs it is an entry written without a reason.

## The portability scan

`tests/portability_scan.ps1` scans every tracked file for machine-specific paths, usernames,
hostnames and hardcoded interpreter or install locations. The mandate it enforces is
[Portability](portability.md). It enumerates with `git ls-files`, because a hardcoded file list is
the exact defect the scan exists to prevent.

Exit codes: `0` nothing machine-specific found, `1` at least one violation, `2` the scan aborted —
and an enumeration that returns zero files is an abort, never an empty-set pass. There is
deliberately no "passed with a caveat": a tracked file either carries a local environment dependency
or it does not.

Its allowlist entries each carry a stated reason, and an entry that excuses nothing on the current
tree is printed as `(unused on this tree - defensive)` rather than silently kept. Three entries
became partly or wholly unused as the two gates, their suites and the deny table were deleted; each
now says so on the entry rather than being quietly dropped.

**What this proves about the plugin's behaviour: nothing.** A file can be perfectly portable and
completely broken.

## The documentation-claim guard

`tests/doc_claims.ps1` fails the build when a tracked page states a checkable quantity the tree
contradicts. It exists because a count could be wrong in ten files at once with nothing to catch it —
which is what two adversarial UAT passes found, including `README.md` describing its own test
coverage two incompatible ways six lines apart, and three pages naming a doctor check count the
doctor does not have.

**It hardcodes none of the expected numbers**, for the same reason the portability scan enumerates
with `git ls-files`: a guard carrying its own copy of the answer is one more place for the answer to
be wrong, and it goes green the day somebody updates the guard instead of the tree. Every expected
value is derived when it runs:

| Quantity | How it is derived |
| --- | --- |
| files in `tests/`, slash commands | `git ls-files` |
| which suites are *behavioural*, and how many cases each runs | every other `tests/*.ps1` is **run**, in parallel; the ones that report an `N of M case(s)` tally are the behavioural suites and `M` is their count. The classification is an observation, not a list. |
| CI check steps | the named steps in `ci.yml` that carry a `run:` block. Counting `shell: powershell` was tried first and read the job-level `defaults.run` as a step. |
| doctor checks | `bin/lwg-doctor.ps1` is run and its `- N checks` header parsed. Its exit code is ignored: how many checks it performs is a different question from whether they passed. |
| modules declared, and how many only observe | `$LwgModuleRegistry` in `lib/common.ps1`, parsed |

Exit codes: `0` every recognised claim agrees, `1` at least one disagrees, `2` a derivation failed or
`-SkipSuites` was passed — and **finding zero claims is an abort**, because a pattern set that matches
nothing is broken rather than clean. A sibling suite exiting non-zero aborts this one on purpose: a
case tally from a failing suite is not a fact.

### The opt-out, and when to use it

Some sentences are records and must keep their old numbers — a changelog entry saying what a suite
held the day it landed, a UAT observation from a date. Correcting one would be falsifying it. Two
markers exempt them, both written **inside an HTML comment**:

- `doc-claims:ignore` — on the offending line, or the line directly above it.
- `doc-claims:ignore-file` — anywhere in a file that is a record end to end. `CHANGELOG.md` and
  [the v0.3.0 UAT report](uat-report.md) carry this one and say why at the top.

**The delimiters are required, and that is not decoration.** The markers have to be named in tracked
prose — this section names them, and so does `CONTRIBUTING.md` — and with a bare token any page that
*mentioned* the convention would exempt itself from it. That is not hypothetical: it exempted
`ci.yml` the first time the guard ran. A marker is itself a claim — *this number is deliberately
frozen* — and is not for a number that is merely inconvenient to fix.

### What it cannot see

It matches **the phrasings this tree uses**, listed rule by rule in the file. A new way of writing
"there are five suites" is invisible to it until a pattern is added, so a green run means *no
phrasing this guard recognises is stale*, which is narrower than *every number in the docs is right*.
And it says nothing about whether a sentence whose numbers check out is true in any other respect: a
page can carry every count correctly and still describe a plugin that does not exist.

## What is not covered

Everything except the ten CI check steps named above — which is every module in the plugin bar two,
since the five behavioural suites cover the gate, one section of the installer, the two hooks that
run at turn end, one command's deletions, and the evidence engine the two reporting commands share.
Stated item by item, because an absence nobody writes down reads as coverage:

1. **The installer's merge is tested on `statusline` only.** The `permissions.deny` parity test used
   to cover it end to end and went on 30 July 2026; [the merge suite](#the-installer-merge-suite) put
   that coverage back on 31 July 2026, aimed at the one section it could be aimed at. The deny table
   the parity test also guarded is genuinely gone — `Get-DenyGroups` returns an empty table — but
   `/lw-watchtower:setup` still writes a `hooks` section and still reports on agent roles, and **those go
   through the same `Save-Settings` writer without a case of their own**. The properties the suite
   establishes for `statusline` — unrelated keys and their order preserved, one backup holding the
   original bytes, a stale `BaseHash` refused, idempotence, rollback — are properties of that writer
   and are very likely to hold for `hooks` too, but *likely* is not *tested*, and the `hooks` plan
   does reach code (`Get-PropArray`, `Get-HookSignature`) that the statusline plan never touches.
   Two paths inside the writer are also named as uncovered in the suite's own header: the
   backup-collision suffix and the post-write auto-restore.
2. That the advisory handler in `lib/stop_advisories.ps1` **cannot block** rests on inspection of the
   source.
3. That the `context_injection` escaper in `lib/subagent_start.ps1` emits **pure ASCII** rests on
   inspection of the source.
4. **`mission_drift`'s trigger has still never been validated against real sessions**, and that is a
   different claim from the one below it. Its *behaviour* stopped being untested on 31 July 2026:
   [the stop-hook suite](#the-stop-hook-behaviour-suite) runs the module across several turns and
   pins the pivot path that had until then been read rather than run. What no case in that suite
   establishes — and what nothing here can establish — is whether the work it warns about deserved a
   warning, because that judgement is not in the code. So the position since the owner switched the
   module on by default on 30 July 2026 is unchanged in the way that matters: an advisory whose
   trigger nobody has checked against real sessions runs at every turn end for every install, and the
   false-positive class in [Modules](modules.md#mission_drift) is live. Its 137 ms turn-end cost is
   measured on one development machine, with the distribution behind that median in
   [Architecture](architecture.md#mission_drift-which-is-switched-on-by-default).
5. The **SessionStart banner** is not asserted by anything. It was asserted by a case in the deleted
   gate suite, so a silent or wrong banner would not now fail a build. `checklist.json` records this
   as a regression rather than quietly dropping the item.
6. The **status line** is not asserted by anything, and it lost a segment on 30 July 2026 when `GM`
   and the trip ledger it read were removed. A rendering defect — a blanked line, a dropped segment,
   a nonzero exit — would surface only by being looked at. The trip machinery it read
   (`lib/trips.ps1`, `lib/ack_trip.ps1`, `bin/lwg-tripped.ps1`) was untested for its whole life and
   is now deleted, so that gap is closed by subtraction rather than by a test.

## Why a regression test must still fail before the fix

The rule survives the suites that motivated it, and it is in
[CONTRIBUTING](../CONTRIBUTING.md#a-regression-test-must-fail-before-the-fix).

The allow/deny matrix the gate suite carried was **67/67 green while five holes were open**. A rule
table can be entirely correct and still be reachable around, so a case that earns its place is aimed
at the reaching, not at the rules — and it has to be shown ALLOWED by the commit before the fix. A
test that passes both before and after proves nothing at all.

That history is why `tests/gate_delegate.ps1` being green is worth restating rather than shrugging
at: the one thing this project has proven about itself is that green is not the same as covered. The
suite was written by breaking the gate three ways and checking each break was caught, not by
enumerating what the gate happens to do.

`tests/setup_merge.ps1` was written the same way, and the third break is worth recording because it
**did not** do what was expected. Replacing `Set-PropValue` with `Add-Member -Force` turned the
key-order case red and nothing else; deleting the hash guard in `Save-Settings` turned all three
concurrent-modification cases red. Removing the `, @()` protection from `Get-PropArray` — the
installer's named defence against a one-element array flattening to a bare string — changed
**nothing**, because `Get-PropArray` is reached only by the `permissions` and `hooks` plans and the
`statusline` plan never calls it. What actually keeps `permissions.ask` an array through a statusline
apply is the full-depth serialiser round-trip, and reducing that depth is what finally turned the
case red. The case was kept and its comment now says which guard it covers; had the break not been
chased down, that comment would have claimed a guard the case cannot see.

`tests/evidence_states.ps1` did not need a break to be introduced: the defect was already in the
tree. The whole suite as it then stood was run against the **unmodified pre-fix
`bin/lwg-evidence.ps1`** and **12 of its 23 cases were red** — the two shipped git rules and their <!-- doc-claims:ignore -->
detail lines, the uninstalled-script case, the empty-stdout case, the ladder case, and all five
end-to-end assertions on the rendered marks. The other 11 were green before as well as after, and
they are the ones that pin a finding staying a finding. *(Those two figures are a record of what was
measured on 31 July 2026 against a 23-case suite, and are deliberately frozen; the suite is larger
now.)* The same was done for the twenty-four cases added on 3 August 2026: **eleven were red at
`fd8d023`** with only the manifest and this suite carried forward — the containment cases, the
truncated-commit cases, the four `hook`-kind cases and the two `use_gh` cases — and **three more**
were red against the pre-fix manifest with the fixed engine in place, and **two more** against the
pre-fix spelling of the two literals the manifest may not carry - the only baselines at which a rule
shape introduced in that same pass can go red. The remaining eight are mirrors and positives that
were green throughout, by design. That split is the point: a suite where
every case goes red on the old code is a suite that only tested the new behaviour, and it would not
have caught a fix that
blanket-`UNVERIFIED`s everything.

## Continuous integration

[`.github/workflows/ci.yml`](../.github/workflows/ci.yml) runs on `windows-latest` under **Windows
PowerShell 5.1** (`shell: powershell`). There is no OS matrix, and `pwsh` is not a substitute:
`tests\portability_scan.ps1` needs a binary literally named `powershell` and `-ExecutionPolicy`.

**One job, `fast-checks`, with ten check steps** after the checkout. It was two jobs with four steps
until 30 July 2026, then one job with three; the fourth step is the gate suite added with
`delegate_gate`, the fifth is the workflow guard, and the sixth, seventh and eighth — the installer
merge suite, the stop-hook behaviour suite and the evidence-state suite — were all added on 31 July
2026, alongside the uninstaller footprint suite. The tenth, the documentation-claim guard, landed on
1 August 2026. The job's **display name is deliberately still**
`Fast checks (JSON + PowerShell parse)`, which now understates what it runs: a required status check
on `main` is matched by that name, so renaming it would silently stop satisfying the requirement.
Rename it only together with the branch-protection setting.

| Step | What it does |
| --- | --- |
| JSON validity | parses **every tracked `.json`**, enumerated with `git ls-files` rather than from a hardcoded list, so a new JSON file is covered the moment it is tracked. Missing or empty counts as a failure, since `ConvertFrom-Json` accepts an empty input silently. An enumeration that returns zero files is itself a failure. |
| PowerShell parse | `[Parser]::ParseFile` over every `.ps1` outside `.git`, annotating file, line and column |
| Workflow guard | `tests\workflow_guard.ps1` — **the step that guards the file it is written in.** Every file under `.github\workflows\` is parsed and held to the rules in [The workflow guard](#the-workflow-guard). A missing guard file fails the build, since not running is not the same as passing. |
| Delegate gate suite | `tests\gate_delegate.ps1` — one of the five steps that test behaviour. A missing suite file fails the build, since not running is not the same as passing. An abort (exit 2) is reported as an abort, never as a pass. |
| Installer merge suite | `tests\setup_merge.ps1` — the only step that tests a **write to settings.json**. It drives `bin\lwg-setup.ps1` against throwaway settings files under the temp directory. A missing suite file fails the build; an abort (exit 2) is reported as an abort. |
| Stop-hook behaviour suite | `tests\stop_behaviour.ps1` — the only step that tests an **observing module**. It runs `lib\stop_advisories.ps1` and `lib\supervisor.ps1` in real child processes against throwaway plugin roots under the temp directory. A missing suite file fails the build; an abort (exit 2) is reported as an abort. |
| Uninstaller footprint suite | `tests\uninstall_footprint.ps1` — the only step that tests a **deletion**. It drives `bin\lwg-uninstall.ps1` against throwaway data directories under the temp directory, with `$env:USERPROFILE` and `$env:CLAUDE_PLUGIN_DATA` redirected around every call, and asserts on the filesystem as well as on the report. A missing suite file fails the build; an abort (exit 2) is reported as an abort. |
| Evidence-state suite | `tests\evidence_states.ps1` — the only step that tests a **reporting command**. It holds `bin\lwg-evidence.ps1` to the difference between a probe that ran and found nothing and a probe that never got to look, against a throwaway plugin root with no `.git` — the marketplace install route. A missing suite file fails the build; an abort (exit 2) is reported as an abort. |
| Portability scan | `tests\portability_scan.ps1` — every tracked file, against the mandate in [Portability](portability.md). A missing scan file fails the build, since not running is not the same as passing. |
| Documentation claims | `tests\doc_claims.ps1` — **the only step that checks the prose.** Every tracked `.md`, `.json` and `.yml` is held to counts derived from the tree at run time, including a parallel re-run of the five behavioural suites to read the tally each prints about itself. A missing guard file fails the build; an abort (exit 2) is reported as an abort, and so is a run that found no claims at all. |

**No step was replaced with a weaker one.** In particular there is no step asserting that the
installer's now-empty deny table is still empty: it would print a pass on every run, which reads as a
verified protection and is the precise class of false assurance this repo exists to refuse.

Triggers are `push` and `pull_request` on `main`, plus `workflow_dispatch`. **Neither trigger carries
a path filter.** `on.push` held `paths-ignore: ['**.md']` until 31 July 2026, on the reasoning that a
README edit changes no gate and no JSON — and that reasoning went stale the day the portability scan
landed, because **the scan reads every tracked file, `.md` included**, and a machine-specific path
turns up in prose more often than in code. A filter sits on the trigger rather than on a job, so it
skipped the **entire** workflow rather than the steps a `.md` change plausibly does not affect.

It was **deleted rather than narrowed**. The scan's input is the whole tracked tree, so the only set
of paths that provably reaches no check is the empty set; any narrower filter is a list somebody has
to keep in step with what the steps read, which is the same drift the `git ls-files` enumerations
exist to avoid.

`pull_request` has never carried one and must not be given one, for a separate reason that still
holds: a path filter there makes the job **never report a status at all**, which would leave a
docs-only PR blocked forever on a required check that never runs.

### Branch protection

A required status check on `main` is matched by the **check run's name**, which is a job's `name:`
key — *not* its YAML job id. This workflow declares one job whose id is `fast-checks` and whose name
is **`Fast checks (JSON + PowerShell parse)`**. That string, exactly — capitalisation, spaces and
parentheses as written — is the only requirable context.

Any rule still requiring **`Gate regression suite`**, the display name of the `gate-regression` job
deleted on 30 July 2026, blocks every merge and has to be removed: that job no longer exists and can
never report. Requiring `fast-checks` or `gate-regression` — the job **ids** — blocks every merge for
exactly the same reason, because no check run is ever produced under either string. GitHub's
required-checks field takes free text and validates it against no workflow, so a wrong entry here is
silent and permanent: every pull request, including the one that would fix it, sits at *"Expected —
Waiting for status to be reported"* with no error and no failing check to read.

This paragraph named the two job ids until 3 August 2026, so following it to the letter removed
nothing and required a context that can never report.

Renaming the job's `name:` key silently stops satisfying the requirement, so rename it only together
with this setting — see the comment above the job in
[`ci.yml`](../.github/workflows/ci.yml), and `checklist.json`'s `P6-branch-protection`, whose probe
can see that a protection object exists but not which contexts it names. `tests/doc_claims.ps1`
derives the job's `name:` from the workflow and fails if this section does not quote it verbatim.
**That is the page half only.** Nothing in this repository can read the live branch-protection
setting, so a correctly worded page and a correctly configured `main` remain two separate claims and
only the first of them is checked here.

**There is no status badge in the README**, deliberately: the repository is private, so a badge would
not render for most viewers — and a green badge covering one gate and two of the nine observing
modules would read as far broader assurance than it is, which would be the
exact overstatement this project exists to avoid.
