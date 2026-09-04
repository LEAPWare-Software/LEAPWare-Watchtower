# Testing and CI

## Fourteen files in `tests/`, and eleven of them test behaviour

Read this before anything else on this page.

`tests/gate_delegate.ps1` exercises `delegate_gate` with 100 cases,
each run through a real pipe into a real child process. `tests/supervision.ps1` does the same job for
the other two gates and for `orphan_watch`, against seeded transcripts and seeded health logs, and
carries the measured failure all three were built from as its anchor cases.
`tests/setup_merge.ps1` drives
`bin/lwg-setup.ps1` against throwaway settings files and checks its **merge** on the `statusline`
section and, since section 31, on the `hooks` section too — and, in the sections that are not about
the installer at all, it is the only place the **reporting surfaces** are exercised:
`bin/lwg-update.ps1` and `statusline/statusline.ps1` against a scratch copy with a payload on stdin.
They live there
because that file already owned the only harness that runs any of them for real. **The
`bin/lwg-update.ps1` section needs `git` on `PATH` and ABORTS the suite without it** — not running is
not the same as passing —
which is the one external binary any suite here depends on besides `powershell` itself; every
"remote" it builds is a local bare repository under the temp directory and no case reaches a network.
`tests/stop_behaviour.ps1` runs the two hooks that fire at every turn end —
`lib/stop_advisories.ps1` and `lib/supervisor.ps1` — with 120 cases, and covers more
**observing** modules than anything else here. `tests/uninstall_footprint.ps1` drives `bin/lwg-uninstall.ps1` against
throwaway data directories and throwaway `settings.json` files with 40 cases, and is the only one
that covers a **deletion**.
`tests/state_resolution.ps1` runs the `SessionStart` hook itself in a real child process: the
`CLAUDE_CONFIG_DIR` precedence, the five self-check probes, every rung of the mode ladder, the banner
and the model-visible `additionalContext` envelope.
`tests/doctor_behaviour.ps1` runs `bin/lwg-doctor.ps1` against seeded configs and seeded
`settings.json` files with 42 cases, on **two of its ten checks and no others**.
`tests/toggle_behaviour.ps1` drives `bin/lwg-toggle.ps1`'s write to the override file with 32 cases,
and `tests/config_behaviour.ps1` does the same for `bin/lwg-config.ps1`, each closing with an
invariant that the plugin root's tracked `config.json` was not moved by a byte. They are the only
suites besides the merge suite that cover a **write to a file an operator owns**.
`tests/subagent_scan.ps1` pipes payloads into `lib/subagent_start.ps1` with 14 cases, and is the only
coverage of any kind that `context_injection` has.
`tests/payload_guard.ps1` reads every file `git ls-files` reports under `lw-watchtower/` — which is
the whole shipped payload — with 23 cases, and is the only one that asks what a **stranger
receives**.
`tests/portability_scan.ps1` scans tracked files for machine-specific strings,
`tests/workflow_guard.ps1` parses every workflow file and holds it to a set of rules, and
`tests/doc_claims.ps1` holds every tracked page to the tree on the quantities it states; all three
check the contents of tracked files and assert nothing about this plugin's behaviour at all.

So the coverage statement is narrow and exact: **the only behaviour any test in this repository
establishes is that the three gates refuse what they declare, that the installer's merge
preserves what it was not asked to touch, that all eight observing modules behave as
documented in the cases written for them, that the uninstaller's state-data footprint
names what it deletes and refuses to call a no-op deletion a success,
that two of the doctor's ten checks ask the question
they claim to, that the two write paths back up and re-check the file they replace and leave the
tracked `config.json` alone, and that no
tracked file carries a disclosure this repository knows the shape of.**

**Every module name is now reached by at least one suite, and that is a much weaker statement than it
sounds.** `failure_capture`, `context_pressure`, `docs_coupling`, `git_hygiene` and `log_rotation`
are driven by `tests/stop_behaviour.ps1`; `self_health` by `tests/state_resolution.ps1`;
`context_injection` by `tests/subagent_scan.ps1`; `orphan_watch`, `send_liveness_gate` and
`completion_audit` by `tests/supervision.ps1`; `delegate_gate` by `tests/gate_delegate.ps1`. Four of
the observing ones arrived on **3 August 2026** with one to three
cases each on at most two properties apiece
(`context_pressure` 2, `docs_coupling` 2, `log_rotation` 3, `git_hygiene` 1), which is enough to say
they are no longer untouched and not enough to say they are tested. Read the list as a map of what is
touched, not as a coverage claim.

**`context_injection` is the thinnest of them.** It is reached only by
`tests/subagent_scan.ps1`, and only on the question of whether its raw-text fast path answers the
**global** `modules` flag whatever order the top-level keys appear in. What that hook does with
`context/worker_facts.md` — the comment-stripping, the 2000-character ceiling — has no case
anywhere, and neither does the performance budget the fast path exists to defend. Read "covered"
as "one property of it is run", not as "tested". **Nothing in `tests/` derives which modules a suite
exercises** —
`tests/doc_claims.ps1` names that hole in its own header rather than implying it closes it — so this
paragraph is held by review and by nothing automatic.

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

A green CI run now means exactly twenty things: every tracked JSON file parses, every `.ps1` file
parses, no workflow file reaches a runner GitHub does not host, a secret or a wider `permissions:`
grant than it needs — and every other YAML
file under `.github/` at least *parses*, and the guard was shown able to fire on each of its rules
rather than only shown to say nothing — `delegate_gate` still
refuses what it declares, the two supervision gates and `orphan_watch` still answer the shapes they
were built from, the installer's merge still preserves unrelated keys and
rolls back, the two `Stop` hooks still behave as documented, the `SessionStart` hook still reports
the mode its config implies, the uninstaller still deletes exactly
the state data its footprint listed and still exits non-zero rather than reporting a no-op deletion
as a success, two of the doctor's checks still ask whose file a status line is and still refuse a
flag the reader ignores, the two write paths still back up the override file, still re-check the
bytes they are replacing and still leave the tracked `config.json` untouched, the `SubagentStart`
fast path still answers the global `modules` flag whichever order the
top-level keys are written in, no tracked file carries a disclosure the payload guard knows the shape
of, every tracked file was *read* and none names a machine, no tracked page states a count
the tree contradicts, the five version-declaration sites still agree with each other, every
red-first annotation still names a commit and a case that exists, no pull request reached `main`
without referencing an issue, and no commit
reachable from HEAD carries an identity that is not on the allowlist. **It means nothing more than that** — and note two limits inside it: parsing
`dependabot.yml` is not validating it against GitHub's schema, and a rule proved to fire on one
planted shape is not a rule proved correct.

## What still runs

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\gate_delegate.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\supervision.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\setup_merge.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\stop_behaviour.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\state_resolution.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\uninstall_footprint.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\doctor_behaviour.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\toggle_behaviour.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\config_behaviour.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\subagent_scan.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\payload_guard.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\workflow_guard.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\portability_scan.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\doc_claims.ps1
```

Fourteen files, all in the `fast-checks` CI job. Each behavioural suite spawns a child PowerShell process
per case, and that is the point of them; the parse steps, the guard and the scan are seconds at most.
Measured on **3 August 2026** on **one developer machine** — not on a GitHub runner, which nothing here
has timed — run one after another the way the CI steps drive them:

| Suite | Seconds |
| --- | --- |
| `tests/setup_merge.ps1` | 262 |
| `tests/uninstall_footprint.ps1` | 94 |
| `tests/gate_delegate.ps1` | 71 |
| `tests/stop_behaviour.ps1` | 70 |
| `tests/doctor_behaviour.ps1` | 31 |
| `tests/toggle_behaviour.ps1` | 27 |
| `tests/subagent_scan.ps1` | 9 |
| `tests/payload_guard.ps1` | 7 |
| `tests/portability_scan.ps1` | 4 |
| `tests/workflow_guard.ps1` | 2 |

**These figures move every time a suite gains cases and they had been four times out of date before
the first such measurement**, so read them as an order of magnitude and re-measure rather than
quoting them. They are also not the same machine's numbers as the previous revision of this table:
the merge suite read 248 s and the gate suite 179 s there, and the gate suite's drop is a change in
what it runs rather than in how fast the machine is.

The documentation-claim guard re-runs the thirteen other files in parallel to read the tallies they print
about themselves, so it costs the slowest of them rather than the sum.
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
broken. **The red-first proof for this defect is M1 alone, and only injected** — which is the
qualification that makes the sentence true: M1 and the matcher variable it reads did not exist on the
pre-fix tree, so M1 cannot be run against that tree as it stands, and "red there" means red once the
case is injected into a snapshot of it. Injected, it fails because the matcher registered there names
the four tools gated before `PowerShell` was added, so the CLI's selection step never delivers the
payload to the gate. **Section A is not part of that proof**, and this page named it until 3 August
2026. Neither section-A case that the claim could have meant fails on the pre-fix tree: that tree
registers exactly one `PreToolUse` entry naming the gate, so the registration case passes, and its
hand-written gated-tool list spells the same four names its matcher does, so the coverage case finds
nothing missing and nothing surplus. That last one can only fail on a *mixed* tree — this wave's
widened list against the un-widened `hooks.json` — and no such tree is claimed here. That does not
make those two a second exception to the rule at the top of this paragraph: both are present in the
pre-fix tree, so neither was kept as proof of *this* defect, and each answers a different question —
the entry count, and whether the matcher covers the constant. Whether either was ever proven red
against an earlier tree is not established here. Both section-A readings and M1's failure are
**derived by reading the pre-fix tree's files**, not measured by running the suite against it: a
weaker source than the run the four section-D cases above came from, and the difference is stated
rather than blurred. Section M exists precisely because a case that cannot see the matcher cannot see
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
`statusline` section **and, since section 31, on the `hooks` section too**: for both,
`/lw-watchtower:setup` leaves unrelated top-level keys value- and order-identical, takes exactly one
backup holding the original bytes, refuses `apply` without a matching `BaseHash`, is idempotent to
the byte, and rolls back byte for byte. Section 31 adds one property `statusline` has no equivalent
of — the operator's own registrations *inside* `hooks` come through value-identical, which
`Compare-UnrelatedKeys` cannot see because `hooks` is the key being touched. The word *inherited* is
gone from this page because the argument it named — that both sections go through `Save-Settings` —
was an argument from shared code, and the two paths differ above `Save-Settings`: `New-HooksPlan`
rewrites a nested object through `Get-PropArray` and calls `Set-PropValue` twice. `permissions`
writes nothing and is not exercised at all.

## The stop-hook behaviour suite

`tests/stop_behaviour.ps1` covers the two hooks that run at **every turn end**: the advisory handler
`lib/stop_advisories.ps1` and the health supervisor `lib/supervisor.ps1`. It landed on 31 July 2026,
and what it replaced was nothing at all — the module it was built around, `mission_drift`, had been
on by default, at every turn end, on every install, with **no test of any kind**, and the supervisor
carried two comments describing bugs that had already shipped with no case pinning either fix. That
module was removed on 2 September 2026; the suite outlived it, because sections A, C, D and E were
never about it.

Five sections:

- **A — pure helpers, in process.** `lib/common.ps1` is dot-sourced and the prompt reader, the
  path-containment test, the two flag resolvers and the redaction helper are called directly. A unit
  call names the failure precisely: *a typo'd flag was coerced to a real one*, rather than *the
  advisory did not fire*. Not all of it is Stop-hook code, and the suite's own header says why it is
  here anyway: `Test-LwgModule` decides whether every module in sections B and C runs at all,
  `Get-LwgRedacted` is this plugin's **only** redaction control and had no test of any kind until
  these cases, `Get-LwgPromptText` is `lib/gate_stop.ps1`'s turn-boundary reader, and
  `Test-LwgPathUnder` decides what `bin/lwg-uninstall.ps1` is allowed to delete.
- **B — the Stop advisory hook, end to end, in child processes.** `lib/stop_advisories.ps1` is run
  for real with a payload on stdin, because that is how Claude Code invokes it and because what these
  cases assert lives in state files carried between turns. A turn is one child run; a multi-turn case
  is several, with the transcript grown and the edit list extended in between.

  **This was `mission_drift`'s section and the module is gone.** Its cases went with it, and the
  suite's own header says so rather than leaving the section looking thinner than it was designed.
  What survives is the plumbing plus the four cases that were always about something else: B22 and
  B23 on the shared edit-list writer — that the list **rolls** at 256 KB rather than stopping, so a
  file edited after the cap is still recorded, and that one 200 000-character
  `tool_input.file_path` is bounded both where it is written and where it reaches the operator's
  `systemMessage`; B24, which drives three turn ends with `git` unresolvable and asserts the
  **UNKNOWN** tree state is reported at every one of them, because `git_hygiene`'s silence is
  documented to mean *git said there is nothing wrong*; and B25, which feeds `context_pressure` an
  occupancy above the assumed window and asserts the module **refuses** it — reports no percentage
  and pins nothing — and then that a second, corroborating reading is what promotes it to a learned
  window.
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
would call noise, because that judgement is not in the code. That was written about `mission_drift`,
whose trigger was never validated against a real session before it was removed, and it applies
unchanged to the three advisories that are left.

## The supervision suite

`tests/supervision.ps1` covers the two gates and the one observing module that have no other
coverage: `send_liveness_gate`, `completion_audit` and `orphan_watch`. It is built to the same
contract as the delegate gate suite — every case run through a real pipe into a real child process,
against a throwaway plugin root and data directory under the temp directory — and it carries the
same standing caveat at the top rather than in a footnote: **a green run says these cases still
behave, not that the gates are sound.**

Its fixture configs start as byte copies of the repository's own `config.json`, comments and all,
with exactly the switches under test flipped, and **every flip is asserted**, so a fixture that
silently failed to arm a gate cannot turn a deny case into a false pass.

Four groups:

- **A — the registrations themselves**, read out of `hooks/hooks.json`: that `gate_send.ps1` has
  exactly one `PreToolUse` entry and its matcher names `SendMessage`; that `gate_stop.ps1` has
  exactly one `Stop` entry and one `SubagentStop` entry, that **neither carries `asyncRewake`** —
  which is what makes its exit 2 block the turn end rather than raise an alert — and that the
  `SubagentStop` one passes `-HookEvent SubagentStop`; and that all of them are in exec form through
  `${CLAUDE_PLUGIN_ROOT}` with no `shell:` key.
- **C — `send_liveness_gate`.** The anchor case reproduces the measured failure the module was built
  from: a recipient whose transcript had been silent for 28 minutes 45 seconds with no
  `SubagentStop` record, which must **DENY**. Beside it: a stale recipient that completed normally
  **allows**, a fresh transcript with no stop record allows as presumed running, an unresolvable
  recipient denies, a `name@team` address **abstains**, a session with no health records at all
  abstains, empty stdin denies, and with the switch at its shipped default the dead recipient is
  allowed **silently**.
- **D — `completion_audit`.** The anchor case is the prose half of the same failure: a completion
  claim in a turn whose last tool action was a `SendMessage`, which must **BLOCK**. Beside it: a
  hedged sentence passes, a `Read` after the send passes because evidence-gathering followed, a claim
  *before* the send passes, `stop_hook_active` passes because the gate fires at most once per turn
  end, and with the switch at its shipped default the measured pattern passes silently.
- **E — `orphan_watch`.** The anchor case is the bookkeeping half: a spawned agent with no stop
  record, which must produce an exit-2 alert naming the agent. Beside it: the same orphan alerts
  **once** through `alerted.json`, an agent that stopped normally and one still running raise
  nothing, a session with no health records reaches no verdict, a transcript older than the health
  window **abstains** rather than guessing, and with the switch at its shipped default an orphan
  raises nothing and stamps no field. Three later cases separate a death from things that look like
  one: a harness-stated failure on a fresh transcript is a death, a completed task-notification is
  not, and a mid-stream `server_error` that recovered 67 minutes later raises no alert.

## The state-resolution suite

`tests/state_resolution.ps1` runs the real `SessionStart` hook in a real child process and asserts
all five self-check probes, all six words of the mode ladder, the banner and the model-visible
`additionalContext`. It asserts what the hook **says**; nothing in `tests/` observes a registered
hook actually firing on the machine it is installed on.

Its sections, in the order they run:

- **A** (#146) the `CLAUDE_CONFIG_DIR` precedence — that it is honoured, that an unset value falls
  back to `<profile>\.claude`, that a trailing separator, a relative value and a missing directory
  are all settled at the resolver, that `CLAUDE_PLUGIN_DATA` outranks it, and that `SessionStart`
  writes its ledger under it and nothing under the profile.
- **B** (#60) the self-check degrading on a non-boolean at a switch-backed key, and the shipped
  `config.json` still resolving clean.
- **C** (#106) the `selfcheck.probe` file holding one line after three `SessionStart` events while
  still proving the directory writable.
- **D** (#8) the marketplace install layout — that `installed_plugins.json` names the resolved
  install path, that the `cache\<marketplace>\<plugin>\<version>` layout is walked, and that no
  marketplace install is reported as none.
- **E** (#132) the platform and hook events — that the `SessionStart` record names the platform it
  ran on, and that every implemented module's declared hook events are all registered.
- **F** (#177) the four self-check probes that had no assertion anywhere in `tests/` —
  `config_from_file`, `thresholds_live`, `payload_session`, `payload_cwd` — each driven false from
  its own direction, and the five rungs of the mode ladder section B left unpinned:
  `observe-only`, `unverified`, `partial`, `enforcing`, `inert`, asserted in the ledger record and in
  the banner.
- **G** (#144, #177) the banner and the `additionalContext` envelope.

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

Every case is a real child run of the real script with `$env:USERPROFILE` and
`$env:CLAUDE_PLUGIN_DATA` redirected at a throwaway tree under the temp directory. Every case
asserts on the **filesystem** as well as on the report, because a suite that only read the text
could be satisfied by a script that prints well and deletes nothing — which is what shipped. A
selection of what they pin — this list is shorter than the suite and always has been:

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

## The doctor behaviour suite

`tests/doctor_behaviour.ps1` runs `bin/lwg-doctor.ps1` — the one component whose whole job is to
notice a switch wired to nothing. Until this suite landed, **nothing in `tests/` had ever run it
against a seeded config or a seeded `settings.json`**: `tests/doc_claims.ps1` runs it once, on the
real tree, and reads only the `- N checks` line out of its header. So two of its checks had never
been driven at all, and both were wrong in the same direction — each answered a question cheaper
than the one it claims to answer.

| Check | What it did | Why that is a defect |
| --- | --- | --- |
| `config-registry` | tested a declared switch for **presence** and stopped | `"delegate": "true"` — quoted — passed, while `Test-LwgFlag` requires a real `[bool]`, ignored the string, and left the only gate this plugin ships on its built-in default of `$false`. The `modules` block had the same hole with the opposite polarity: the check read `.PSObject.Properties.Name` and never a value, and an ignored `modules` value leaves the module **on**. |
| `statusline` | took the first token ending in `.ps1` out of `statusLine.command` and hash-compared it against this repo's copy | with **no test of whose file it is**. A third party's status line was diagnosed as a stale copy of this plugin's, with the printed remedy being to overwrite it. The inverse was quieter and also wrong: an identical file attested an install that never happened. |

**16 cases.** The whole plugin tree is copied once into a scratch directory, minus `.git` and
`.claude`, and every case runs the copy's own `bin/lwg-doctor.ps1` in a real child process — the
doctor derives its root from its own `$PSScriptRoot`, so the copy is what it reads. `USERPROFILE`
and `CLAUDE_PLUGIN_DATA` are redirected per case and both plugin-root variables are cleared.
**No test seam was added to the shipped script for this**, which is what lets every case run
unmodified against the pre-fix commit. The last case measures every `<plugin>*/*.jsonl` under the
operator's *real* state directory before the first child process and again after the last, and fails
if any length changed or any file appeared.

**Seven of the sixteen pass at the pre-fix baseline too**, and every one of them is labelled
`CONTROL` in its name and in its comment. None is offered as evidence that anything was fixed. They
exist because the cheapest way to pass the other nine is to answer "not ours" to everything and
`FAIL` to every config, and the controls are what make that not work.

Exit codes: `0` every case passed, `1` at least one failed, `2` the suite aborted — and zero cases
run is an abort, never a pass.

**What a green run does not mean.** It **drives two of the ten checks and no others**, so it says
nothing about the other seven — in particular nothing about `sessionstart`, which is owned by a
separate issue and deliberately untouched. Beyond that, the suite's header names three limits and
this page carries them rather than advertising past them:

- **a foreign status line that is byte-identical to the repo copy cannot be detected**, and no case
  pretends to. Once the provenance marker lives in `statusline/statusline.ps1`, a byte-identical
  file *carries* the marker and is this plugin's by every test a content marker can make. What the
  fix removes is the inference from hash alone;
- **the marker is forgeable.** Any file with `LWG-STATUSLINE-IDENTITY` in its first 4096 bytes is
  claimed as this plugin's and gets the drift warning and the re-copy remedy — the exact harm the
  defect caused, reachable by a file that copied one comment line. A content token cannot be made
  unforgeable, so this is a **limit rather than a defect awaiting a fix**. What the marker buys is
  that an *unrelated* status line is no longer diagnosed as ours, and that is the case an operator
  actually hits;
- **whether the status line renders** is not a question this file asks at all.

## The toggle write-path suite

`tests/toggle_behaviour.ps1` drives `bin/lwg-toggle.ps1`, which backs `/lw-watchtower:delegate`,
`:plain` and `:verbosity` and **writes `config.json`**. Nothing in `tests/` had ever driven that
write. `tests/gate_delegate.ps1` exercises the *reader* of `interaction.delegate` end to end; the
writer was covered by nothing at all, which is why three defects in it survived being read several
times:

- the write was a bare truncating `[IO.File]::WriteAllText` — **no backup, no re-check that the file
  on disk is still the one that was read, and a hardcoded no-BOM encoding** — where
  `bin/lwg-config.ps1` routes the same file through `Save-LwgTextFile` and gets all three;
- on a `config.json` that **already** does not parse, the toggle edited the broken text, failed to
  parse the result, **blamed its own edit**, and interpolated Windows PowerShell 5.1's
  `ConvertFrom-Json` message — which embeds the whole input — into operator output;
- a `config.json` with no top-level `modules` block made the toggle **write the file and then exit
  3**, while the script's own header and `commands/delegate.md`, `plain.md` and `verbosity.md` all
  define exit `3` as *"config.json was not changed"*.

A fourth came from review rather than from an issue: a **second route to exit 3 on a file that was
written**. The write is fine and the *report* after it throws — with `USERPROFILE` unset, the
activation block builds a settings path out of that variable — and every throw in that file lands in
one handler that exits 3.

`tests/toggle_behaviour.ps1` runs **32 cases**, each in a real child process against a byte copy of
`bin/` and `lib/` under a scratch plugin root built at runtime from the temp directory, with
`config.json` seeded per case. The toggle
resolves its own config as `(Split-Path -Parent $PSScriptRoot)\config.json`, so a copied tree
redirects the write **with no seam at all** — which is what lets the cases run unchanged against the
pre-fix commit. `USERPROFILE` and `CLAUDE_PLUGIN_DATA` are redirected and both plugin-root variables
cleared around every child; without that swap every run would append to the **operator's** event log,
because several fixtures hold a non-boolean flag on purpose and that reaches `Write-LwgInvalidFlag`.

**One environment trap, recorded because it cost an hour and is now fixed:** if the shell that
launches this suite carries a PowerShell 7 `PSModulePath`, the Windows PowerShell 5.1 children cannot
resolve `Get-FileHash` — it is a function exported by `Microsoft.PowerShell.Utility`, not a compiled
cmdlet, and 5.1 loses it when PowerShell 7's copy of that module shadows its own. **No script in the
payload uses it any more**, so nothing here breaks either way: `bin/lwg-cmdlib.ps1`, which is where
the toggle and `/lw-watchtower:config` read and write through, hashes from .NET, and so do the
doctor, setup, update and uninstall. Until that landed, every toggle run under such a shell exited 3
with *"config.json could not be read"*, which reads as a broken config file and was nothing of the
kind. Section H of this suite is the case that pins it, and it plants the failure deliberately rather
than waiting for a PowerShell 7 host. The only remaining `Get-FileHash` **call** in the tree is the
one-liner `docs/faq.md` and `docs/install.md` hand an operator to type, and both now say what to do
when it does not resolve. `git grep Get-FileHash` still returns plenty of lines and none of them run:
they are comments in `bin/` saying why the hash is computed from .NET instead, the alias
`tests/doctor_behaviour.ps1` plants to make the failure happen on demand, and UAT records quoting the
error as it reached an operator.

**Eight of the cases are labelled `CONTROL`** and pass before the fix as well as after it, on
purpose — they pin the other direction, so a "fix" that simply refuses everything, or reformats the
file, or turns every run into a reported fault, fails them. **Ten cases passed at the pre-fix
commit**, both measured rather than reasoned: those eight controls plus two that are *not* controls
and pass there for their own reasons. That is stated so a reader counting greens in a red run does
not read those two as coverage. It is deliberately **not** written as a ratio against the suite's
total: it stood here as "ten of the twenty-six" while the suite grew past twenty-six and then past
twenty-eight, spelled as a word and so invisible to the guard whose whole job is stale numbers
(#296). How many cases passed at that commit does not change when a case is added; a denominator
does.

Exit codes: `0` every case passed, `1` at least one failed, `2` the suite aborted **or a case could
not be made conclusive** — and zero cases run is an abort, never a pass.

**What a green run does not mean.** It establishes that the toggle takes a backup, re-checks the file
it is about to replace, keeps a BOM, refuses a config it cannot read back, and does not return exit 3
on any run that changed the file. It establishes **nothing** about three things that are in the code
and are not reached from here: the bounded parser message on a file that parsed *before* the edit;
the pre-write resolution of the edited **text**, which sits behind a refusal that fires first on
every input that would reach it; and the post-write read-back handler, which can only fire if the
bytes on disk are no longer the ones the command wrote — a few milliseconds' window that no case
constructs. **`-Scope repo` is not covered either, and that is a gap rather than a decision:** the
scratch working directory is deliberately not a git repository, so every repo-scoped run exits 2 at
the slug check before it reaches the write. A repo-scoped write is not *expected* to behave
differently, but "not expected" is not "was run".

## The SubagentStart fast-scan suite

`tests/subagent_scan.ps1` covers `lib/subagent_start.ps1`, and it is the **only coverage of any kind
that `context_injection` has**.

That hook does **not** parse `config.json`. It reads its own flag out of the raw text, because
`ConvertFrom-Json` costs 141–182 ms in a fresh Windows PowerShell 5.1 process and this hook runs on
every subagent dispatch of every session. The duplication is deliberate and documented in the file's
own header — and it is correct **only while the span it scans is the global `modules` block**.
`Get-LwgJsonObjectSpan` had no notion of depth: it returned the first `"modules":` in document order
at **any** nesting level, and `config.json`'s `repos` block is documented to hold per-repo `modules`
objects. So this fixture

```json
{
  "repos": { "acme/example": { "modules": { "docs_coupling": false } } },
  "modules": { "context_injection": false, "git_hygiene": true }
}
```

injected into the worker while `/lw-watchtower:doctor`, the `SessionStart` banner and
`Test-LwgModule` all agreed the module was **off**. The same bytes with the two top-level keys in the
shipped order printed nothing. That is the whole defect: **a raw-text scanner whose correctness
depended on which of two sibling keys appears first in a file operators are invited to hand-edit**,
with nothing anywhere asserting that order.

**There are few cases here**, and that is because of the rule every one of them follows: **no bare
negative stands alone.** "It did not inject" is satisfied by a hook that crashed, by a missing facts file, and
by a fixture that never reached the branch — so every case asserting silence runs the *same* fixture
a second time with **one bit changed** and requires the injection to appear. The pair is the
evidence; neither half is.

Each case pipes a payload into a real child process against the real `lib/subagent_start.ps1` — the
file `hooks/hooks.json` registers — because the hook drains stdin with `[Console]::In.ReadToEnd()`
and a child that inherited an open stdin would block rather than fail. `CLAUDE_PLUGIN_ROOT` points
at a throwaway root holding the fixture `config.json` and a fixture `context/worker_facts.md`, and
`CLAUDE_PLUGIN_DATA` is redirected for **every** child without exception: the hook's catch path
dot-sources `lib/common.ps1` and calls `Write-LwgEvent`, so a case that forgot the redirect would
write into the operator's own state directory on every failure.

Exit codes: `0` every case passed, `1` at least one failed, `2` the suite aborted — and zero cases
run is an abort, never a pass.

**What a green run does not mean.** It says the fast scan answers the **global** flag whatever order
the top-level keys appear in, and that it agrees with the slow path it exists to avoid. It says
nothing about:

- **the escalation's slug resolution.** One case proves the escalation still runs and still lands on
  the right answer for a dispatch with no repo in its payload; *which* repo a real payload resolves
  to is `Get-LwgRepo`'s job and is not re-tested here;
- **the content and formatting of `worker_facts.md`.** Every fixture uses an invented one-line file;
  the comment-stripping and the 2000-character ceiling have no case at all;
- **the performance budget** — which is the entire reason the raw-text path exists. This suite
  asserts on *answers*, not on milliseconds, so a green run is **not** evidence the hook is still
  fast.

## The payload disclosure guard

`tests/payload_guard.ps1` asks what a **stranger receives**. `.claude-plugin/marketplace.json`
declares `"source": "./lw-watchtower"`, so **every tracked file under that directory is the shipped
payload** and nothing outside it is. It said `"source": "./"` until the payload became a
subdirectory, and on that form there is no exclusion mechanism at all, so the answer was *every
tracked file in this repository* — and the `checklist` command rendered one of those files on the
consumer's machine, because `commands/checklist.md` instructed the model to print the output
verbatim. That command went on 2 September 2026; the files it rendered still ship, so the guard
stays.

Four disclosures reached the payload that way and **nothing caught any of them**, because every
other guard in `tests/` answers a different question. That is the argument for a separate file rather
than a wider rule in an existing one:

| Guard | The question it asks | Why it passed these |
| --- | --- | --- |
| `tests/portability_scan.ps1` | does a tracked file name one **machine**? | a pull ref, a commit SHA and a release-plan heading are portable |
| `tests/doc_claims.ps1` | do the **counted quantities** in the prose match the tree? | a containment claim carries no number, so it is not a claim that file can read at all |

So the disclosures were found by **audit** — a person remembering to look, and the three that found
these had to be told where. This is the same check run by a machine, over the same file list the
marketplace copies.

**15 cases.** Every file `git ls-files` reports under the payload directory is read and matched
against the detection rules. The
file list is **never hardcoded**: a hardcoded list is the defect this guard exists to prevent, and it
is exactly how the payload boundary was lost in the first place — the old `"source": "./"` was a
wildcard nobody enumerated.

What it refuses is a pull-ref narrative, a former personal address, a plan file's own name, a
release-plan heading, **a containment claim conditioned on who can currently reach this
repository**, and **a shipped file naming a script this branch deleted**. That last one is the rule that guards a sentence which is **correct today**, and that
is the point rather than an overreach: the claim holds now and becomes a false safety claim about an
unresolved PII exposure the moment visibility changes — inside a file that is public by then. The
change is a single event nobody will re-read the file after.

**The rules are described here and not spelled**, and neither are they spelled in the suite's own
header. A guard that writes out the string it forbids *is* the disclosure, and one whose header trips
its own rules goes red the day it is added. That is not hypothetical on this repository: it has
already shipped a prose example that matched the sweep hunting for the thing it described, and the
first draft of the CI step for this suite tripped rule `visibility-conditioned` from inside the step
that runs it. The forbidden address is held **rot13-encoded and decoded at match time**, for the reason a guard
that spells the string it forbids *is* the disclosure. The evidence renderer that shared the
transformation was deleted with the checklist manifest, so the guard now carries its own helper.

**Self-exemption is bracketed, not wholesale.** The guard must contain the strings it forbids, so its
exempt lines sit inside a region marker and **only the owner path may declare one** — a marker
appearing in any other tracked file is itself reported as a violation, so the mechanism cannot become
an escape hatch. A hit covered by the **barred ledger** is *printed with its issue number above the
result* and never folded silently into a pass: a ledger entry means the named issue owns the site,
**not that the site is acceptable**. The ledger also deliberately does not assert that the sites it
names still exist — an entry that went red when somebody *fixed* the file it points at would punish
the fix.

Exit codes: `0` every tracked file was read and no unledger'd disclosure was found, `1` at least one
disclosure sits at a site no ledger entry covers, `2` the scan aborted, could not read every tracked
file, or an owner file left a region open. **What is not scanned is not clean**: a tracked path with
nothing on disk, or a file whose first 8 KB holds a NUL byte, is named and exits `2`, and `2` takes
precedence over `1`.

**What a green run does not mean.** It is a statement about the **shapes this guard carries**, not
that the payload is free of everything a reader would rather not ship. A disclosure nobody has
written a rule for is invisible to it, exactly as a phrasing nobody has written a pattern for is
invisible to the documentation-claim guard.

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

The ten rules fire when a workflow file:

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
| `permissions-write` | a `permissions:` grant wider than read, at workflow level or at job level, including the `write-all` scalar shorthand |
| `unparseable` | a file the reader could not parse; a construct it does not implement — anchors, aliases, merge keys, multiple documents, tab indentation; or **a mapping that declares the same key twice**, which is a refusal rather than a gap — see below |

**A duplicate key in one mapping is `unparseable`, and that is a refusal rather than a gap.** The
reader's lookups return the *first* entry for a key, so a mapping holding the same key twice is one
it cannot resolve — and reporting it clean would be reporting on a file it did not fully read. That
is not hypothetical. A job written

```yaml
runs-on: ubuntu-latest
runs-on: self-hosted
```

was reported `0 violation(s)`, exit `0`, with no parse error and no warning, for a tracked file whose
text says `self-hosted`; CI then printed `workflow guard: PASS` and the checklist rendered
`P6-workflow-guard` DONE. The same thing one level up hid an entire second `jobs:` block. Both were
measured against the unmodified guard. **Returning the last match instead would not be a fix** — it
moves which of the two values is invisible and invents an answer to a question the file does not
answer. Whether GitHub Actions itself honours the first or the last is deliberately not claimed. The
check is scoped to **one mapping**: every job declares `runs-on:` and every step declares `run:`, so
a check with a longer memory would condemn every workflow ever written, this repository's own
`ci.yml` first.

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
- **The absence of a `permissions:` block.** The `permissions-write` rule holds a block that exists
  to read-scoped values; a workflow declaring none at all inherits the repository's default workflow
  permissions, which is repository configuration this scan cannot read. Requiring the block is a
  policy preference, and the exit-1 contract is reserved for real violations.
- Everything a workflow can do that is not one of the ten rules above.

Its allowlist holds **two entries**, both added on 3 September 2026 and both belonging to
`release.yml`: `release-publish-token` for the `${{ secrets.GITHUB_TOKEN }}` its publish step reads,
and `release-publish-grant` for the job-level `contents: write` that token runs under. They are
separate entries so that dropping either does not quietly widen the other.
`secrets.GITHUB_TOKEN` is still not pre-approved anywhere else: an entry written before a concrete
step needs it is an entry written without a reason.

## The red-first annotation guard

`.github/scripts/redfirst_annotations.ps1` reads every `tests/*.ps1` and checks the SHAPE of its
red-first annotations: a line claiming a baseline must name a commit, and a case id an annotation
names must be a case that suite declares. It **cannot** re-run a baseline — no clone here reaches
`fd8d023` — so an annotation citing a real SHA against a case that could never have failed there
passes it. About eighteen annotations name a working tree rather than a commit and are out of the
first rule's reach entirely; the guard says so in its own header and prints a per-suite ledger, and a
rule that matched nothing anywhere exits 2 rather than reporting a clean run. Sixteen baseline
citations and eleven case references were live at `4342980`. Run it with no arguments for fixture
mode — eight cases over planted suites — and with `-Live` for the real tree; CI runs both in one
step.

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

**Two cases do not run in that phase.** `tests/doc_claims.ps1` sets `LWG_SUITE_PARALLEL` in the
siblings it starts, and the two cases in the tree whose verdict is a wall-clock duration read it and
report SKIPPED rather than measuring a machine running thirteen suites at once. They are still
counted in their suite's tally and still enforced by that suite's own CI step and by every local
run — what the flag removes is the one context in which the number they read is about the runner.
It is not a retry: nothing runs twice, and no threshold was widened to fit.

### The opt-out, and when to use it

Some sentences are records and must keep their old numbers — a changelog entry saying what a suite
held the day it landed, a UAT observation from a date. Correcting one would be falsifying it. Two
markers exempt them, both written **inside an HTML comment**:

- `doc-claims:ignore` — on the offending line, or the line directly above it.
- `doc-claims:ignore-file` — anywhere in a file that is a record end to end. `CHANGELOG.md` carries
  it, and so do three of the five maintainer notes under `.github/notes/`: the v0.3.0 UAT record
  (`uat-report.md`), the hosting plan that was proposed and not executed (`harness-hosting-plan.md`),
  and the 31 July 2026 handoff (`HANDOFF.md`, exempted on 4 September 2026 — see #256 for why it
  could not be until then). Each says why at the top. Read the marker as a claim in its own right:
  every number in that file is now unchecked, the correct ones included.

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

Everything except the twenty CI check steps named above — and what is left out is a set of
**properties**, not a set of modules. This sentence said *"every module in the plugin bar two"* until
4 September 2026, which the same page contradicts sixty lines earlier: **every module name is now
reached by at least one suite**, and that paragraph is explicit that being reached is not being
tested. Two numbers cannot both be right, and the map is the one derived from the tree.

What the eleven behavioural suites do cover, read off that map rather than restated from memory: the
delegate gate's refusals and the two supervision gates', `orphan_watch` beside them in the same
suite, the five advisories the turn-end hooks raise, `self_health`'s self-check, the `SubagentStart`
fast path's answer to the global `modules` flag, two sections of the installer's merge, one
command's deletions, two of the doctor's ten checks, the toggle's write to `config.json`, and what
the shipped payload discloses. It named *the
evidence engine the two reporting commands share* until the same date; `bin/lwg-evidence.ps1` and the
`checklist` and `sitrep` commands were deleted in wave 1 and that clause described nothing.

**So the honest residue is per property, and the map already names the worst of it**: four of the
observing ones carry one to three cases apiece on at most two properties (`context_pressure` 2,
`docs_coupling` 2, `log_rotation` 3, `git_hygiene` 1), and `context_injection` has exactly one
property run with its `worker_facts.md` handling untested. No count is written for the properties
that remain, and that is deliberate: it would mean deciding what counts as a property and then
maintaining a number nothing derives, which is how the figure this sentence replaces came to be
wrong in the first place. Stated item by item instead, because an absence nobody writes down reads
as coverage:

1. **The installer's merge is now tested on `statusline` and on `hooks`, and on nothing else.** The
   `permissions.deny` parity test used to cover it end to end and went on 30 July 2026;
   [the merge suite](#the-installer-merge-suite) put that coverage back on 31 July 2026 for
   `statusline`, and section 31 extended it to `hooks`. The deny table the parity test also guarded is
   genuinely gone, and so is the function that built it and the whole `permissions` section that
   wrote it, so there is nothing left there to cover. Still not covered, and named rather than faked:
   the backup-collision suffix, the post-write auto-restore, and the atomicity of the write.
2. That the advisory handler in `lib/stop_advisories.ps1` **cannot block** rests on inspection of the
   source.
3. That the `context_injection` escaper in `lib/subagent_start.ps1` emits **pure ASCII** rests on
   inspection of the source.
4. **No advisory's trigger has been validated against real sessions.** A suite can establish that a
   trigger behaves as written; it cannot establish that being warned by it is right, because that
   judgement is not in the code. `mission_drift` was the standing example — on by default, at every
   turn end, on every install, with a trigger nobody had checked — and it was removed on
   2 September 2026 rather than left there. The distinction survives it and applies to
   `context_pressure`, `docs_coupling` and `git_hygiene`, all three of which ship on.
5. The **SessionStart banner** is asserted by `tests/state_resolution.ps1` section G: that it is
   emitted and non-empty, that it is none of the **three** self-reported failure strings, that its
   counts and mode word are the ones the config implies across five configurations, and that a
   degraded session still gets a banner naming what degraded it. What is still not asserted anywhere:
   that any registered hook actually fires on the machine — see #132 and #166.
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

`tests/evidence_states.ps1` — deleted in wave 1 with the evidence engine it held — did not need a
break to be introduced: the defect was already in the tree. The paragraph is kept because it is the
clearest record of what a red-first proof looks like when the red is already there. The whole suite as it then stood was run against the **unmodified pre-fix
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

**One job, `fast-checks`, with twenty check steps** after the checkout. It was two jobs with four steps
until 30 July 2026, then one job with three; the fourth step is the gate suite added with
`delegate_gate`, the fifth is the workflow guard, and the sixth, seventh and eighth — the installer
merge suite, the stop-hook behaviour suite and the evidence-state suite — were all added on 31 July
2026, alongside the uninstaller footprint suite. The tenth, the documentation-claim guard, landed on
1 August 2026. The last four — the doctor behaviour suite, the toggle write-path suite, the
`SubagentStart` fast-scan suite and the payload disclosure guard — landed together with the fixes
they pin, and each is a **behavioural** step, so the job went from five tests of behaviour to nine
in one change. The job's **display name is deliberately still**
`Fast checks (JSON + PowerShell parse)`, which now understates what it runs: a required status check
on `main` is matched by that name, so renaming it would silently stop satisfying the requirement.
Rename it only together with the branch-protection setting.

| Step | What it does |
| --- | --- |
| JSON validity | parses **every tracked `.json`**, enumerated with `git ls-files` rather than from a hardcoded list, so a new JSON file is covered the moment it is tracked. Missing or empty counts as a failure, since `ConvertFrom-Json` accepts an empty input silently. An enumeration that returns zero files is itself a failure. |
| PowerShell parse | `[Parser]::ParseFile` over every `.ps1` outside `.git`, annotating file, line and column |
| Workflow guard | `tests\workflow_guard.ps1` — **the step that guards the file it is written in.** Every file under `.github\workflows\` is parsed and held to the rules in [The workflow guard](#the-workflow-guard). A missing guard file fails the build, since not running is not the same as passing. |
| Delegate gate suite | `tests\gate_delegate.ps1` — one of the eleven steps that test behaviour, and the only one that tests a **gate**. A missing suite file fails the build, since not running is not the same as passing. An abort (exit 2) is reported as an abort, never as a pass. |
| Installer merge suite | `tests\setup_merge.ps1` — the only step that tests a **write to settings.json**. It drives `bin\lwg-setup.ps1` against throwaway settings files under the temp directory. A missing suite file fails the build; an abort (exit 2) is reported as an abort. |
| Stop-hook behaviour suite | `tests\stop_behaviour.ps1` — the step that reaches **five of the eight observing modules**, more than anything else here. It runs `lib\stop_advisories.ps1` and `lib\supervisor.ps1` in real child processes against throwaway plugin roots under the temp directory. A missing suite file fails the build; an abort (exit 2) is reported as an abort. |
| Uninstaller footprint suite | `tests\uninstall_footprint.ps1` — the only step that tests a **deletion**. It drives `bin\lwg-uninstall.ps1` against throwaway data directories under the temp directory, with `$env:USERPROFILE` and `$env:CLAUDE_PLUGIN_DATA` redirected around every call, and asserts on the filesystem as well as on the report. A missing suite file fails the build; an abort (exit 2) is reported as an abort. |
| Doctor behaviour suite | `tests\doctor_behaviour.ps1` — the step that runs the component whose job is to notice a switch wired to nothing. It copies the plugin tree to a scratch directory and drives the copy's own `bin\lwg-doctor.ps1` against seeded configs and seeded `settings.json` files, on **two of its ten checks and no others**. A missing suite file fails the build; an abort (exit 2) is reported as an abort. |
| Toggle write-path suite | `tests\toggle_behaviour.ps1` — one of the steps that test a **write to a file an operator owns**. It drives `bin\lwg-toggle.ps1` against a byte copy of `bin\` and `lib\` under a scratch plugin root with the config seeded per case, and closes with an invariant that the plugin root's tracked `config.json` was not moved by a byte. A missing suite file fails the build; an abort (exit 2) is reported as an abort. |
| Config write-path suite | `tests\config_behaviour.ps1` — the same job for `bin\lwg-config.ps1`: the module switchboard's read, validate, write and report path, the `config.override.json` it writes under the state directory, and the same untouched-`config.json` invariant. A missing suite file fails the build; an abort (exit 2) is reported as an abort. |
| Supervision suite | `tests\supervision.ps1` — the step that covers `send_liveness_gate`, `completion_audit` and `orphan_watch`, against seeded transcripts and seeded health logs, each case run through a real pipe into a real child process. Its anchor cases reproduce the measured failure all three were built from. A missing suite file fails the build; an abort (exit 2) is reported as an abort. |
| State resolution suite | `tests\state_resolution.ps1` — the step that runs the `SessionStart` hook itself: the `CLAUDE_CONFIG_DIR` precedence, the five self-check probes, every rung of the mode ladder, the banner and the model-visible `additionalContext` envelope. A missing suite file fails the build; an abort (exit 2) is reported as an abort. |
| SubagentStart fast-scan suite | `tests\subagent_scan.ps1` — the only coverage of any kind that `context_injection` has. It pipes payloads into the real `lib\subagent_start.ps1` and holds its raw-text fast path to the **global** `modules` block whatever order the top-level keys appear in. It asserts on answers, not on milliseconds. A missing suite file fails the build; an abort (exit 2) is reported as an abort. |
| Payload disclosure guard | `tests\payload_guard.ps1` — the only step that asks what a **stranger receives**. Every file `git ls-files` reports under `lw-watchtower/` is the shipped payload, because `marketplace.json` declares `"source": "./lw-watchtower"`, and each one is read and matched against the detection rules. A ledger'd hit is printed with its issue number, never folded into a pass. A missing guard file fails the build; an abort (exit 2) is reported as an abort, and a run that could not read every tracked file exits 2 rather than 0. |
| Portability scan | `tests\portability_scan.ps1` — every tracked file, against the mandate in [Portability](portability.md). A missing scan file fails the build, since not running is not the same as passing. |
| Documentation claims | `tests\doc_claims.ps1` — **the only step that checks the prose.** Every tracked `.md`, `.json` and `.yml` is held to counts derived from the tree at run time, including a parallel re-run of the eleven behavioural suites to read the tally each prints about itself. A missing guard file fails the build; an abort (exit 2) is reported as an abort, and so is a run that found no claims at all. |
| Version declarations | `.github\scripts\version_declarations.ps1` — the five version declaration sites held **to each other** on every push and pull request. **No tag is passed here**: the two tag-shaped rules (the sites equal the tag, and `CHANGELOG.md`'s heading for it is dated) report NOT CHECKED, and `release.yml` is the caller that has a tag to ask them with. An empty `git tag -l` is reported NOT CHECKED rather than clean, so this step cannot go green on the published-tag rule by never seeing a tag. Fixtures first — nine planted trees, one per rule — then the tree; a `1` is a drifted declaration, a `2` is a declaration site that could not be read, which is not the same as the sites agreeing. |
| Red-first annotations | `.github\scripts\redfirst_annotations.ps1` — the SHAPE of every red-first annotation in `tests\*.ps1`, in fixture mode and against the live tree in one step. See [The red-first annotation guard](#the-red-first-annotation-guard). |

**No step was replaced with a weaker one.** In particular there is no step asserting that the
installer's now-empty deny table is still empty: it would print a pass on every run, which reads as a
verified protection and is the precise class of false assurance this repo exists to refuse.

Triggers are `push` on `main`, `pull_request` on `main` **and on the wave integration branches**
(`wave*/**`), plus `workflow_dispatch`. The two lists differ on purpose: a base branch that is not
listed runs no job at all — not a skipped one, nothing that reports a status — and every wave of the
delivery plan lands on an integration branch before it lands on `main`, so with `[main]` alone every
pull request into one of those was unguarded (#196). Pushes to an integration branch are still not
built: the pull request that lands them is. **Neither trigger carries a path filter.** `on.push` held `paths-ignore: ['**.md']` until 31 July 2026, on the reasoning that a
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
[`ci.yml`](../.github/workflows/ci.yml). `tests/doc_claims.ps1`
derives the job's `name:` from the workflow and fails if this section does not quote it verbatim.
**That is the page half only.** Nothing in this repository reads the live branch-protection setting
at all any more. A checklist manifest carried a `P6-branch-protection` probe that could see whether a
protection object existed — never which contexts it named — and until **2026-08-28** the API refused
it even that with a `403`; the manifest and its evidence engine were deleted in wave 1. So a
correctly worded page and a correctly configured `main` are two separate claims and only the first of
them is checked here.

**There is no status badge in the README**, deliberately: a green badge covering three gates and all eight
observing modules would read as far broader assurance than it is, which would be the
exact overstatement this project exists to avoid. A second reason — that a badge would not render for
most viewers of a repository they cannot read — stood until the visibility flip on **2026-08-28** and
no longer applies. It is recorded rather than quietly dropped, because the surviving objection is the
one that was always the real one, and a badge would still have to answer it.
