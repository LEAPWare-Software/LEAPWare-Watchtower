# Architecture

How the pieces fit, what each file is for, what it costs, and where the mutable state lives.

> **A note on names.** A few passages here cite a **private sibling project** of this repo's
> author. The incidents are real and are the reason a rule exists; the project is not public and
> nothing here depends on it.

## Layout

```
lw-watchtower/               THE SHIPPED PAYLOAD. Everything the marketplace
                             copies onto a consumer's machine is under this one
                             directory and nothing outside it
lw-watchtower/.claude-plugin/plugin.json
                             manifest: identity only. Declares NO paths at all -
                             hooks/hooks.json, commands/ and agents/ are all
                             default-scanned, and naming one here REPLACES the
                             default scan rather than adding to it. A
                             "hooks": "./hooks/hooks.json" key used to sit here
                             and cost a startup ERROR every session - see "The
                             manifest declares no paths"
.claude-plugin/marketplace.json
                             AT THE REPOSITORY ROOT, not in the payload: a
                             marketplace manifest describes where a plugin is,
                             so it cannot live inside the thing it points at.
                             Single-plugin marketplace so the repo can be added
                             with /plugin marketplace add. Not read by the
                             junction install
lw-watchtower/config.json    module switchboard, per-repo overrides, thresholds,
                             per-module tuning (module_config), plus the
                             interaction and supervision switch blocks, which
                             carry the gate switches and are NOT modules keys
lw-watchtower/commands/*.md  six slash commands - prose only; every one of
                             them is a thin wrapper that runs a script in bin/
                             and reports its output. The logic is never in the
                             command prose - see docs/commands.md
lw-watchtower/agents/lw-*.md the six agent roles the plugin ships. Discovered
                             from this directory name - see docs/roles.md
lw-watchtower/bin/lwg-doctor.ps1
                             ten checks for what is NOT working. Exits 0/1/2/3
                             and is meant to be able to exit non-zero
lw-watchtower/bin/lwg-setup.ps1
                             the guided installer: detects, asks, then writes
                             one section at a time behind its own diff and yes
lw-watchtower/bin/lwg-config.ps1
                             the module switchboard; needs -Apply to write
lw-watchtower/bin/lwg-update.ps1
                             fetch-and-report, fast-forward only; -Apply to take
lw-watchtower/bin/lwg-uninstall.ps1
                             footprint report and removal; dry run by default
lw-watchtower/bin/lwg-toggle.ps1
                             ONE flag, -Flag delegate, backing
                             /lw-watchtower:delegate. It was five, then three,
                             then one: ask and ask-inline went with the two old
                             gates on 30 July 2026, and verbosity and plain went
                             with the whole output-style feature. The per-flag
                             facts live in one table at its top
lw-watchtower/bin/lwg-cmdlib.ps1
                             the shared read/validate/write/report path the
                             lifecycle commands use, so there is one copy
lw-watchtower/hooks/hooks.json
                             hook registrations (SessionStart, PreToolUse,
                             PostToolUse, PostToolUseFailure, SubagentStart,
                             SubagentStop, Stop, StopFailure). 13 registrations
                             across those 8 events, and THREE of them carry a
                             channel that can refuse something: the two
                             PreToolUse gates, and completion_audit's Stop and
                             SubagentStop entries, which are one gate registered
                             twice. The PreToolUse key was absent for a few
                             hours on 30 July 2026, between the last old gate
                             being removed and delegate_gate arriving
lw-watchtower/context/worker_facts.md
                             the block context_injection hands to every subagent.
                             Data, not code - edit it and the next dispatch picks
                             it up. '#' lines are comments and are not injected
lw-watchtower/lib/common.ps1 module registry (implemented vs planned vs blocked -
                             source of truth for the banner), config load, module
                             resolution, the session-mode ladder (shared by the
                             banner and /lw-watchtower:doctor so the two cannot drift),
                             repo identity from cwd (bounded .git walk
                             + origin remote parse), state-dir resolution,
                             append-with-retry writer, rotation,
                             advisory emitter, seek-based tail reader,
                             incremental append-only reader, transcript token
                             accounting, context-window resolution, path
                             classification, health-log reader, quote-aware
                             tokeniser, secret patterns - now used for LOG
                             REDACTION ONLY (Get-LwgRedacted), never for scanning
                             a write. Note what is still NOT here -
                             any way to spawn a process. That is what makes "a
                             gate cannot shell out" a fact about the file layout
lw-watchtower/lib/session_start.ps1
                             SessionStart handler - banner and self-check
lw-watchtower/lib/gate_delegate.ps1
                             delegate_gate. PreToolUse on
                             Edit|Write|NotebookEdit|Bash|PowerShell; refuses
                             a call carrying no agent_id, i.e. one that did not
                             come from a subagent, and ONLY when
                             interaction.delegate is on, which it is not by
                             default. Reads no path and no command. It reads
                             tool_name ONLY to name the refused tool in the deny
                             text, AFTER the decision is made; nothing it decides
                             consults it, because the matcher in hooks/hooks.json
                             is the single place the gated tool list lives.
                             The two handlers it replaced - secret_scan's and
                             destructive_gate's - were deleted on 30 July 2026 by
                             explicit owner decision and nothing replaced what
                             they inspected. See docs/modules.md
lw-watchtower/lib/gate_send.ps1
                             send_liveness_gate. PreToolUse on SendMessage;
                             THREE outcomes, not two. It refuses a send whose
                             recipient it can prove is dead mid-flight - the
                             liveness verdict, and the only one of its FIVE
                             refusals that is one. It also refuses a
                             recipient that resolves to nothing at all: no
                             readable `to`, no subagents directory for the
                             session, no agent of that name, or no transcript
                             for the agent the name resolved to. What is left
                             to abstain on is an address it does not judge
                             (main, or any name@team) and evidence it cannot
                             use (a session health.jsonl never recorded, a
                             transcript still inside the stale window). See
                             docs/modules.md, which states the same split.
                             OFF by default; its switch is
                             supervision.send_liveness
lw-watchtower/lib/gate_stop.ps1
                             completion_audit. Registered on Stop AND on
                             SubagentStop, both deliberately without asyncRewake
                             so its exit 2 BLOCKS the turn end rather than
                             alerting. OFF by default; its switch is
                             supervision.completion_audit
lw-watchtower/lib/stop_advisories.ps1
                             context_pressure + docs_coupling + git_hygiene -
                             one Stop process for all three; warns, never blocks.
                             The ONLY file here that
                             spawns a subprocess, and the bounded-process helper
                             lives here rather than in common.ps1 so that the
                             PreToolUse gates cannot reach it - a gate that can
                             spawn a process can hang the call it guards. git
                             status is started before the in-process modules and
                             collected after them. Carried the trip sweep until
                             30 July 2026; that went with the ledger
lw-watchtower/lib/post_edit.ps1
                             the edited-path recorder for docs_coupling -
                             PostToolUse on Write|Edit|NotebookEdit
lw-watchtower/lib/subagent_start.ps1
                             context_injection - SubagentStart, once per dispatch.
                             Deliberately dot-sources NOTHING and uses no cmdlet,
                             no character loop and no JSON engine on its fast path
lw-watchtower/lib/supervisor.ps1
                             failure_capture - the five-event health hook handler,
                             orphan_watch below its flag check, and the one place
                             log_rotation is invoked (above the failure_capture
                             gate, so those two are independent)
lw-watchtower/statusline/statusline.ps1
                             the status-line renderer (HH, ORC and the payload
                             segments) - the source of truth,
                             NOT loaded by the plugin. statusLine is a settings.json
                             key, so this must be COPIED to ~\.claude\statusline.ps1;
                             the two can drift - see docs/install.md
tests/gate_delegate.ps1      100 cases against lib/gate_delegate.ps1, each run
                             through a real pipe into a real child process. One
                             of ELEVEN behavioural suites, and the only one that
                             covers a PreToolUse gate - see docs/testing.md
tests/stop_behaviour.ps1     120 cases against the Stop-hook handlers:
                             helpers in process, lib/stop_advisories.ps1 and
                             lib/supervisor.ps1 in real child processes. The
                             suite that reaches the most OBSERVING modules
tests/supervision.ps1        the three supervision modules - send_liveness_gate,
                             completion_audit and orphan_watch - against seeded
                             transcripts and seeded health logs
tests/setup_merge.ps1        203 cases driving bin/lwg-setup.ps1 against throwaway
                             settings files. The only suite that tests a WRITE.
                             The writer properties are established on the
                             statusline section and, since section 31, on the
                             hooks section too. It ALSO carries the
                             only coverage the reporting surfaces have, because
                             it owns the only harness that runs them for real:
                             statusline/statusline.ps1 from a scratch copy, and
                             bin/lwg-update.ps1 against a local bare repo. Those
                             sections are not about the installer at all
tests/state_resolution.ps1   the SessionStart hook in a real child process: the
                             CLAUDE_CONFIG_DIR precedence, the five self-check
                             probes, every rung of the mode ladder, the banner
                             and the model-visible additionalContext envelope
tests/config_behaviour.ps1   bin/lwg-config.ps1's read/validate/write path,
                             including the override file it writes and the
                             invariant that the plugin root's config.json is not
                             moved by a byte
tests/uninstall_footprint.ps1
                             40 cases driving bin/lwg-uninstall.ps1 against
                             throwaway data directories and throwaway
                             settings.json files, asserting on the FILESYSTEM as
                             well as on the report: what the footprint says it
                             will remove is what it removes, what it attributes
                             to this plugin really is this plugin's, and what it
                             refuses to touch it names. The only suite that
                             tests a DELETION
tests/doctor_behaviour.ps1   42 cases driving bin/lwg-doctor.ps1 from a scratch
                             copy of the whole plugin tree, against seeded
                             configs and seeded settings.json files. It drives
                             TWO of the doctor's ten checks - config-registry
                             and statusline - and no others. Fourteen of its cases
                             are labelled CONTROL and pass before the fix too
tests/toggle_behaviour.ps1   32 cases driving bin/lwg-toggle.ps1's WRITE to
                             the override file, against a byte copy of bin/ and
                             lib/ under a scratch plugin root
tests/subagent_scan.ps1      14 cases piping payloads into lib/subagent_start.ps1,
                             holding its raw-text fast path to the GLOBAL modules
                             block whatever order the top-level keys appear in.
                             The only coverage context_injection has. It asserts
                             on answers, not on the milliseconds the fast path
                             exists to save
tests/payload_guard.ps1      23 cases over every file git ls-files reports under
                             lw-watchtower/, which is the whole shipped payload
                             because marketplace.json declares
                             "source": "./lw-watchtower". The only
                             suite that asks what a STRANGER receives. It tallies
                             cases rather than violations, so doc_claims counts
                             it behavioural, but it reads files rather than
                             running this plugin's code
tests/workflow_guard.ps1     every file under .github/workflows/, PARSED into a
                             tree rather than grepped, against 10 rules about
                             runners, pull_request_target, secrets and the
                             permissions: grant. Asserts
                             nothing about this plugin's behaviour
tests/portability_scan.ps1   every tracked file, against docs/portability.md.
                             Asserts nothing about behaviour either
tests/doc_claims.ps1         every tracked .md/.json/.yml, against counts DERIVED
                             from the tree at run time - test files, behavioural
                             suites, per-suite cases, CI check steps, doctor
                             checks, commands, modules. Asserts nothing about
                             behaviour either; it checks the pages, not the code
.github/workflows/ci.yml     CI - one job, TWENTY check steps: JSON validity,
                             PowerShell parse, workflow guard, delegate gate
                             suite, installer merge suite, stop-hook behaviour
                             suite, supervision suite, uninstaller footprint
                             suite, state-resolution suite, config write-path
                             suite, doctor behaviour suite, toggle write-path
                             suite, SubagentStart fast-scan suite, payload
                             disclosure guard, portability scan, documentation
                             claims, pull-request issue reference,
                             commit identity, version declarations and red-first
                             annotations. Eleven
                             of the twenty test BEHAVIOUR; the other nine ask
                             whether files are well formed or whether the docs
                             agree with the tree. The job's DISPLAY
                             NAME is deliberately unchanged and now understates
                             it - a required check on main is matched by that
                             name; windows-latest, Windows PowerShell 5.1
.github/notes/               maintainer notes - a feasibility spike, an
                             unimplemented hosting plan, a v0.3.0 acceptance
                             record, a design note for an unbuilt check, and the
                             session handoff. NOT published: GitHub Pages serves
                             docs/ and this directory is deliberately outside it
docs/                        this documentation set, and what Pages publishes
```

## The manifest declares no paths

[`.claude-plugin/plugin.json`](../lw-watchtower/.claude-plugin/plugin.json) carries identity and nothing else — no
`hooks`, no `commands`, no `outputStyles`, no `agents`. Every one of those directories is
default-scanned, and naming one in the manifest **replaces** the default scan rather than extending
it.

`"hooks": "./hooks/hooks.json"` was in the manifest until this was fixed, and it named the one path
that is already scanned. Claude Code 2.1.220, loading this tree with `--plugin-dir`:

```
[DEBUG] Read hooks.json for plugin lw-watchtower (enabled=true): <root>\hooks\hooks.json
[DEBUG] Skipping duplicate hooks file for plugin lw-watchtower: ./hooks/hooks.json (resolves to
        already-loaded file: <root>\hooks\hooks.json)
[ERROR] Duplicate hooks file detected: ./hooks/hooks.json resolves to already-loaded file
        <root>\hooks\hooks.json. The standard hooks/hooks.json is loaded automatically, so
        manifest.hooks should only reference additional hook files.
[DEBUG] Plugin not available for MCP: <root-leaf>@inline - error type: hook-load-failed
[DEBUG] Plugin loading errors: Hook load failed: Duplicate hooks file detected: ...
```

Note what this did **not** do: the hooks still registered — `Registered 11 hooks from 1 plugins`,
before and after. The cost was a startup `[ERROR]` on every session that loads this plugin with
`--plugin-dir`, the plugin permanently flagged `hook-load-failed`, that flag repeated through startup
as a "Plugin loading errors" line, and the plugin excluded from MCP for a fault it did not have.
Describing it as "hooks fail to load" would be the overstatement this repo keeps having to correct in
itself.

With the key removed, the same command logs the plugin's `hooks.json` once, no skip, no `[ERROR]` and
no "Plugin loading errors" line, and still `Registered 11 hooks from 1 plugins`. Verified live rather
than by reading: `SessionStart`, `PreToolUse`, `PostToolUse`, `SubagentStart`, `SubagentStop` and
`Stop` were all observed firing in one `--plugin-dir` session afterwards — in the debug log, in
`health.jsonl`, and in the `edits-<session>.txt` the `PostToolUse` hook wrote. `PostToolUseFailure`
and `StopFailure` fire only on a failure and were not induced; they are covered by the registration
count, which was unchanged by that fix.

**That observation is dated.** It was made while both of the old `PreToolUse` gates were registered,
which is why the count reads 11. The tree registers **13** hooks now — the two old gate
registrations went with the gates on 30 July 2026, one came back with `delegate_gate` later the same
day, and `send_liveness_gate` and `completion_audit` added three more on 1 August 2026 — and the
`--plugin-dir` run above has not been repeated since. Read the line as a record of what was seen
then, not as a current count.

The severity differs by install route, which is worth knowing before anyone calls this cosmetic.
Loaded from the skills dir the duplicate is only a `[DEBUG] Skipping duplicate hooks file` line with
no `[ERROR]` and no failure flag. Loaded with `--plugin-dir` — what every worktree agent session uses
— it is the full error above.

## Hook registrations

All in [`hooks/hooks.json`](../lw-watchtower/hooks/hooks.json). Hooks are registered in **exec form**
(`command` + `args`), never `shell: "powershell"` — `pwsh` is a different binary and the shell form
mangles Windows paths. `${CLAUDE_PLUGIN_ROOT}` is substituted inside the `args` array.

| Event | Matcher | Script | Timeout | Notes |
| --- | --- | --- | --- | --- |
| `SessionStart` | — | `lib/session_start.ps1` | 15 s | banner + self-check |
| `SessionStart` | — | `lib/supervisor.ps1 -HookEvent SessionStart` | 15 s | opens the health log |
| `PreToolUse` | `Edit\|Write\|NotebookEdit\|Bash\|PowerShell` | `lib/gate_delegate.ps1` | 10 s | `delegate_gate`. Off unless `interaction.delegate` is on |
| `PreToolUse` | `SendMessage` | `lib/gate_send.ps1` | 10 s | `send_liveness_gate`. Off unless `supervision.send_liveness` is on |
| `PostToolUse` | `Write\|Edit\|NotebookEdit` | `lib/post_edit.ps1` | 5 s | records edited paths |
| `PostToolUseFailure` | `Agent` | `lib/supervisor.ps1 -HookEvent PostToolUseFailure` | 15 s | `asyncRewake` |
| `SubagentStart` | — | `lib/subagent_start.ps1` | 5 s | injects; cannot block |
| `SubagentStop` | — | `lib/supervisor.ps1 -HookEvent SubagentStop` | 15 s | `asyncRewake` |
| `SubagentStop` | — | `lib/gate_stop.ps1 -HookEvent SubagentStop` | 10 s | `completion_audit`, **no** `asyncRewake`, so its exit 2 blocks |
| `Stop` | — | `lib/supervisor.ps1 -HookEvent Stop` | 20 s | `asyncRewake` |
| `Stop` | — | `lib/stop_advisories.ps1` | 10 s | three advisories, one process |
| `Stop` | — | `lib/gate_stop.ps1` | 10 s | `completion_audit` again, same reasoning |
| `StopFailure` | — | `lib/supervisor.ps1 -HookEvent StopFailure` | 15 s | |

**Four of those registrations can refuse something, and they are three modules.** The two
`PreToolUse` rows are `delegate_gate` and `send_liveness_gate`; the two `gate_stop.ps1` rows are
`completion_audit` registered twice, on `Stop` and on `SubagentStop`, because subagents and
teammates emit `SubagentStop` and never `Stop`. Every other row cannot refuse anything:
`SubagentStart` has no blocking channel at all, and every other handler exits 0 on every path —
including the supervisor's, whose exit 2 is turned into an alert rather than a block by
`asyncRewake`. The `PreToolUse` key held one registration per gate until 30 July 2026, when both
were removed by explicit owner decision — see
[Both gates were removed](modules.md#both-gates-were-removed) — and the key was absent entirely for a
few hours until `delegate_gate` was built.

**`delegate_gate` blocks by writing its reason to stderr and exiting 2**, which is the only exit
code that stops a `PreToolUse` call; exit 1 is a non-blocking error and the tool runs anyway. It
emits the `permissionDecision: "deny"` envelope on stdout as well, which this build ignores under a
nonzero exit — see [`delegate_gate`](modules.md#delegate_gate) for why both are written. **All three
gates are off by default, so as shipped nothing in this plugin stops a tool call or a turn end.**

## Turn-end cost

`Stop` runs at every turn end, so the advisory handler is measured rather than assumed.

### Same-event hooks run in parallel, so turn end costs the MAX, not the sum

Two hooks are registered for `Stop` — `lib/supervisor.ps1` and `lib/stop_advisories.ps1` — and the
plugin had been assuming their costs added up. **They do not.** Sampling the OS process table
(`Win32_Process`, which reports the kernel's own `CreationDate` per PID) through a real session:

```
PID      created(+ms)   lastSeen(+ms)  script
3736     0              1376           supervisor.ps1 -SessionStart
20016    26             1713           session_start.ps1
20436    4378           5725           stop_advisories.ps1
23196    4404           5427           supervisor.ps1 -Stop

VERDICT: PARALLEL - hook processes were alive simultaneously
```

Both pairs — the two `SessionStart` hooks and the two `Stop` hooks — were created **26 ms apart**
and were alive together for more than a second. A serial runner would have started the second only
after the first exited. So turn end costs `max(supervisor, advisories)`, and the advisory handler
alone sets it.

**The two `Stop` hooks were therefore NOT merged.** Merging was on the table as the obvious saving,
and the measurement removed the reason for it: there is no wall-clock saving to be had, and the cost
would have been real. `supervisor.ps1` alerts the orchestrator by **exiting 2**, and the CLI ignores
a hook's stdout entirely on exit 2 — so a merged process could either raise the alert or print the
advisory, never both, and every advisory would have been silently dropped on exactly the turns where
something had failed. A saving of zero is not worth putting the only mid-turn alerting channel
behind an advisory's output.

### Measured

Same machine, same seeded load (45 health records, 25 edited files, 200-record transcript), Windows
PowerShell 5.1, including interpreter startup. The two variants are **interleaved inside one loop**,
25 rounds each: measuring one as a block and the other later compares two machine states rather than
two versions — the bare `exit 0` floor moved 6 % between two such runs, which is larger than the
effect being measured.

| | median | min | max |
| --- | --- | --- | --- |
| bare `exit 0` script — the interpreter floor | 283 ms | 252 | 357 |
| `lib/stop_advisories.ps1` **before** the latency work | 1 283 ms | 1 198 | 1 757 |
| `lib/stop_advisories.ps1` **after** | **1 212 ms** | 1 159 | 1 744 |
| `lib/supervisor.ps1` — untouched, and runs *concurrently* | 769 ms | 727 | 1 234 |

**−71 ms**, and the supervisor row no longer adds to it.

Where it came from, and what was measured rather than assumed:

- **`git status` now overlaps the other modules.** Read the count off the registry rather than off
  this sentence: `$LwgModuleRegistry` names `lib/stop_advisories.ps1` as the `impl` of exactly
  `context_pressure`, `docs_coupling` and `git_hygiene`, and those are the file's only three
  `Test-LwgModule` calls. One of the three, `git_hygiene`, **is** the git call being overlapped, so
  the child is launched before the **two** in-process modules that can cover it and collected after
  them. Instrumented on this repo: git itself runs **93 ms**, about **400 ms** of other module work
  covers it, and the collection point waits **26 ms** instead of the **140 ms** it blocked for
  before. **That 400 ms was measured when four modules, not two, sat between the launch and the
  collection point** — see [Advisories](modules.md#advisories) for the two removals that took this
  process down to its present three. It is left as the figure that was taken rather than rescaled to
  a count nobody re-measured. `Process.Start` (~65 ms) is unavoidably synchronous and is still paid.
  The child's timeout is measured from its launch, so it gets exactly the same leash — the overlap
  shortens the hook, never the bound on the child.
- **The repo slug is resolved only when it can change an answer** — when `config.repos` carries a
  real override, or when `git_hygiene` reaches its optional `gh` call. With the shipped empty
  `repos` block, `Test-LwgModule` behaves identically with a `$null` slug.
- **The script exits before touching the state dir** when every `Stop` module is off.
- **The edit list is read and classified once.** It was shared between `docs_coupling` and
  `mission_drift` until the second was removed; one read for one answer is what is left of that.
- **`context_windows.json` is no longer rewritten every turn.** Once the stored figure exceeds the
  200 k default the larger window is already proven and a bigger number proves nothing further.

### What is left, and why it cannot be cut much further

The remaining ~930 ms above the floor is overwhelmingly **PowerShell 5.1 engine warm-up, not data
work**. Measured inside a single hook process:

| First use in a fresh process | cost |
| --- | --- |
| `ConvertFrom-Json` — first call | 141–182 ms |
| `ConvertFrom-Json` — every later call | 0.4 ms |
| dot-sourcing `lib/common.ps1` | 76–104 ms |
| first seek-and-read of a file | 90–125 ms |
| first `.git` walk (`Get-LwgRepoInfo`) | 63–93 ms |

A cheaper JSON route was looked for and does not exist: `JavaScriptSerializer` called directly costs
182–198 ms against `ConvertFrom-Json`'s 212–233 ms — the same assembly, a ~30 ms difference, and it
returns dictionaries instead of `PSCustomObject`s, which would change how every hook reads its
payload. `DataContractJsonSerializer` was slower still (300–350 ms). The JSON engine is a floor on
this platform, and it is paid by every hook that parses its payload.

That is also the answer to why the advisory modules share one process rather than one apiece.

### `git_hygiene` and the `gh` call

Inside a repo `git_hygiene` costs ~90 ms on the critical path (was ~140 ms), ~2 ms with the flag off,
and nothing measurable outside a repo. **That figure is for a branch with an upstream, and it is the
only configuration it was ever measured in** — see the paragraph below, which is the correction.
The worst case remains the `gh` call, ~980 ms of network:
reachable only with unpushed work on a non-default branch, **at most once per branch head per
session**, removed entirely by `use_gh: false`, capped at `gh_timeout_ms` (2 500 ms) and killed on
expiry, so it cannot stall turn end regardless of what the network does.

**On a branch with no upstream there is a second git child, it is not overlapped, and no figure on
this page used to include it.** `git rev-list --count HEAD --not --remotes` runs whenever the branch
has no upstream and the repo has a remote — branch off `main`, start work, do not push yet, which is
where a branch spends most of its life. It runs at **every** turn end for the life of that branch;
nothing caches it. It cannot be launched at the top of the script, because whether it is needed
depends on `git status`'s answer, so all of it lands on the critical path.

Measured on this repository on 3 August 2026, through the same `ProcessStartInfo` shape
`lib/stop_advisories.ps1` uses, 15 runs each, interleaved in one session:

| child | median | min | max |
| --- | --- | --- | --- |
| `git rev-list --count HEAD --not --remotes`, whole blocking call | **327 ms** | 257 ms | 658 ms |
| `git status --porcelain=v2 --branch`, same method, same run | 307 ms | 250 ms | 397 ms |

**Read the ratio, not the absolutes.** The machine was running eight concurrent agent sessions, so
both numbers are far above the 93 ms this page records for `git status` on an idle machine. What
transfers is that the two children cost **about the same**, and that one of them is overlapped by
the in-process module work while the other is not (the ~400 ms above, taken when four modules
covered the child rather than two). So on an upstream-less branch the module's critical-path cost is
roughly the ~90 ms above **plus a whole `git status`-sized child**, and the
sentence *"the worst case remains the `gh` call"* is misleading in the way that matters: the `gh`
call is once per branch head per session, and this is once per turn.

Not fixed, and the reason is worth recording rather than leaving as an omission. **Caching it on the
commit oid was considered and rejected**: `--not --remotes` changes when *remote refs* move as well
as when `HEAD` does, so a plain `git push` — which updates the remote ref without setting an
upstream — would leave a cached count reporting unpushed work that is pushed. That is a wrong number
traded for a saved process, which is the wrong trade here. **Overlapping it** — launching it as soon
as `git status` is parsed and collecting it after the default-branch block — is the fix that does not
cost correctness, and it is not done.

Two timings are logged for the child and they mean different things: `probe_ms` is how long git
itself ran, taken from the OS process times; `probe_wait_ms` is how much of that actually landed on
turn end. Reporting elapsed-since-launch as `probe_ms` would have turned a 93 ms git call into a
550 ms one in the log the moment the launch moved earlier — a measurement changing meaning without
changing name, which is the same class of defect as an inflated module count.

### `context_injection` cost

This runs on every dispatch in every session, so the implementation is shaped entirely by what
PowerShell 5.1 charges for. Direct process spawn with stdin redirected — the way the CLI invokes it
— 15 interleaved rounds:

| | median | min | max |
| --- | --- | --- | --- |
| bare `exit 0` after draining stdin — the interpreter floor | 248 ms | 238 | 278 |
| `lib/subagent_start.ps1`, flag **on** | **437 ms** | 406 | 542 |
| `lib/subagent_start.ps1`, flag **off** | 384 ms | 364 | 440 |

**The 300 ms target this module was written to is below the floor**, so no PowerShell hook of any
kind can meet it — an empty script costs 248 ms. What could be controlled was the 189 ms above that
floor, and it was: the first draft cost 361 ms above the floor, and profiling in-process showed the
difference was never data work.

| First use in a fresh PowerShell 5.1 process | cost |
| --- | --- |
| `ConvertFrom-Json` | 141–182 ms |
| `New-Object` (loads the Utility module) | ~92 ms |
| `Test-Path` (loads the Management module) | ~40 ms |
| dot-sourcing `lib/common.ps1` | 76–104 ms |
| a character-stepping loop, per 371 chars | ~13 ms |
| reading two files and writing stdout | **3.8 ms** |

So this script uses **no cmdlet, no character loop and no JSON engine** on its fast path:
`[IO.File]::Exists` rather than `Test-Path`, `[IO.Path]::Combine` rather than `Join-Path`, brace
matching that jumps between interesting characters with `String.IndexOfAny`, and escaping that is a
chain of ordinal `String.Replace`. Running the same logic three times inside one process gives
**134 ms, then 4.7 ms, then 2.6 ms** — the remaining cost is PowerShell resolving each `.NET` call
site once, not the work, and it is not reducible from this side.

## Health and healing

`failure_capture` ([`lib/supervisor.ps1`](../lw-watchtower/lib/supervisor.ps1)) handles five hook events and
appends one JSONL record per event to `health.jsonl` in the state dir. On a genuine failure it
**exits 2**, which is what makes an `asyncRewake` hook inject a task-notification into the live
session — that exit code is the only channel that reaches the orchestrator mid-turn.

| Event | Exits 2 when |
| --- | --- |
| `SessionStart` | never — records `source` only |
| `PostToolUseFailure` | the failure is not a user interrupt |
| `Stop` | a background task ended `failed`/`killed`, not already in `alerted.json` |
| `SubagentStop` | never — records the agent and its transcript |
| `StopFailure` | never — output and exit code are ignored by the CLI |

`alerted.json` dedupes the `Stop` alert so one dead task cannot re-alert every turn, and
`stop_hook_active` guards the loop.

Until wave 1 the health indicator was cleared by a marker record, written by a resolver command
that has since been deleted along with its library half. **Nothing writes a clearing record now and
nothing reads one.** The number the status line prints after the `HH` glyph is three separate arms
added together, and they do not behave the same way, so the difference is stated rather than
averaged into one word:

- **`supervisor_error` and non-interrupt `PostToolUseFailure` records are counted**, one fault each
  ([`statusline/statusline.ps1`](../lw-watchtower/statusline/statusline.ps1), the two `$faults++` arms). No
  later record lowers them; the only thing that removes one is the record itself leaving the tail
  window the reader bounds itself to.
- **`Stop.failed_tasks` is carried, newest wins** — the gauge, `$gauge = [int]$r.failed_tasks`,
  added once below the loop. A turn end that records no failed task therefore *does* lower this arm,
  to zero. The paragraph below is where that is argued; this is only where it is counted.
- **The standing orphan count is a peak** over the same window (`$orphanPeak`, added beside the
  gauge), and *that* is the arm nothing lowers.

Driven against the shipped reader with seeded logs, one arm at a time: `failed_tasks` of `5` then
`0` renders the **green** all-clear and `0, 3, 1` renders `HH1` rather than `HH3`, while one
`PostToolUseFailure` followed by a clean `Stop` still renders `HH1` and `orphans_new` of `3` then
`0` still renders `HH3`. So a red `HH` can clear itself and a red `HH` can be permanent, depending
on which arm produced it. A log written before the deletion may still hold clearing records; they
fall through every arm of the reader untouched and are inert.

`Stop.failed_tasks` on those records is a **gauge**, not an event count: the supervisor writes the
number of currently-failed background tasks at every turn end, so the newest record is the current
count and earlier ones are the same tasks re-sampled. The one reader left —
`statusline/statusline.ps1` — carries it rather than summing it. There were three until wave 1
deleted the sitrep and resolver commands, and two of the three summed it until 3 August 2026 and
reported one dead task as one fault per turn elapsed.

**Rotation.** `health.jsonl` rolls at 5 MB to `health.jsonl.1`, keeping at most two archives. The
live file is recreated carrying its last 500 records forward, because a plain truncate would blank
`HH`. The status line's reader is `TailWindow` — seek to the final **1 MB**, decode that as UTF-8,
keep the last **300** usable records — and **both** of those are bounds: a log of very long records
can be cut by the byte window before the record cap ever applies. It has not been `Get-Content
-Tail 300` since the seek-and-decode reader replaced it, and the measurement that forced the
replacement is in `statusline/statusline.ps1` beside the reader (80 seconds for one render against a
2 MB log). The 500-record carry-forward is justified against the 300-record cap; it is consistent
with the 1 MB window only while every record field stays capped at 200 characters, which
`lib/supervisor.ps1` does today.

Rotation is gated on `log_rotation` **and nothing else**. The call sits above the `failure_capture`
gate in `lib/supervisor.ps1`, so the two flags are independent in both directions: failure capture
off stops the writes but never the cap, and `log_rotation` off leaves the file to grow, which is
what that flag means. It used to sit *inside* the record writer, downstream of the gate, so
`failure_capture: false` silently disabled rotation as well and `health.jsonl` grew without bound
while `log_rotation` still reported itself active — a module that is enabled, implemented and
unreachable, which is precisely the defect this plugin exists to catch. Cost on the hook path is one
`Test-Path` plus one length compare, returning immediately while the file is under the cap.

## State directory

Mutable state lives in `$CLAUDE_PLUGIN_DATA`, and nothing on the *hook* path is ever written into
the plugin root — it is a git working tree, and writing there dirties the repo.

`config.json` is **tracked** and **not ignored**, and that is now safe: it is the shipped
defaults and no command rewrites it. The four commands that used to write it write
`config.override.json` under the state directory instead, and `Get-LwgConfig` merges that over
the defaults (#11). *"Mutable state lives in `$CLAUDE_PLUGIN_DATA`. Nothing is ever written into
the plugin root"* — the sentence this document carried, then had to withdraw as false — **is true
again**, and it is worth recording that it was false for a month rather than quietly restoring it.

What that cost while it was open was not cosmetic. `bin/lwg-update.ps1` raises a `[FAIL] worktree`
row on any uncommitted change and refuses to pull, so arming the one gate this plugin then shipped
disabled its own updater — and the message an operator read was a generic *"N uncommitted
change(s)"* that looked like their own work in progress. The only clean escape,
`git checkout -- config.json`, threw away the configuration including the armed gate.

**A harness for it was written and deliberately never committed** — `tests/tree_cleanliness.ps1`,
which stood `bin/lwg-toggle.ps1` in a throwaway plugin root that is a real git repository, armed the
gate, and read `git status --porcelain`. It could not be committed while the defect was open:
`tests/doc_claims.ps1` enumerates every **tracked** `tests/*.ps1`, runs them, and aborts on any
nonzero exit, so a suite that is honestly red would have taken a CI step down with it (#154). What
that file measured is now measured by committed cases: `tests/toggle_behaviour.ps1` and
`tests/config_behaviour.ps1` each close with an invariant that no run of the command moved a byte of
the plugin root's `config.json`, and `tests/gate_delegate.ps1` I7 pins the half no cleanliness check
could see — that the gate observes an override the tracked file knows nothing about.

Only a plugin **hook** is given that variable. The status line is a `settings.json` command and a
test run is neither a hook nor a settings command — neither receives it, and both used to fall back
to a hardcoded `~/.claude/plugins/data/lw-watchtower/`, as did the state resolver deleted in wave 1.
**That name is not a name Claude Code produces.** A plugin auto-discovered out of the skills dir is `lw-watchtower@skills-dir`,
so the directory the harness actually creates and hands its hooks is
`~/.claude/plugins/data/lw-watchtower-skills-dir/`. Every fallback caller therefore read and wrote a dead
directory while believing it had succeeded, which cost three separate failures: the status line
rendered unconditional green off an empty log, the healer wrote a `Resolved` marker into the wrong
file for the wrong session and reported the status line back to green, and out-of-harness runs kept
recreating the dead directory after it was cleaned up.

`Get-LwgStateDir` in [`lib/common.ps1`](../lw-watchtower/lib/common.ps1) now **discovers** the directory instead:

1. `$CLAUDE_PLUGIN_DATA` wins outright when set — it is what every live hook takes.
2. Otherwise `<claude home>/plugins/data` is scanned for `<name>` and `<name>-*`, where `<name>` is
   read from `.claude-plugin/plugin.json` rather than spelled out in code. **`<claude home>` is not
   the literal `~/.claude`.** `Get-LwgClaudeHomeInfo` in
   [`lib/common.ps1`](../lw-watchtower/lib/common.ps1) takes `$CLAUDE_CONFIG_DIR` when it is set and
   falls back to `$env:USERPROFILE\.claude` when it is not, and the scan root is composed from
   whichever it returned. Driven both ways: with `CLAUDE_CONFIG_DIR` pointed at a clean profile and
   `CLAUDE_PLUGIN_DATA` unset the resolver reported `home_source: env` and discovered a candidate
   under the relocated root; with both unset it reported `home_source: profile` and `~/.claude`.
   That the variable was read by nothing is a fixed defect, and the precedence it sits in — an
   explicit parameter, then `$CLAUDE_PLUGIN_DATA` for the data directory only, then
   `$CLAUDE_CONFIG_DIR`, then `$env:USERPROFILE` — is written out above that function.
3. **A suffixed candidate beats the bare name.** Claude Code names a data dir
   `<plugin-name>-<source-id>` and a plugin always has a source, so the live directory is always
   suffixed; the bare name can only ever have been created by this fallback itself.
4. Several suffixed candidates are broken by most-recently-written, then by ordinal name order so
   the answer is deterministic. **Most-recently-written means the newest timestamp on the directory
   *or on any file it holds*, not the directory's own mtime.** NTFS stamps a directory when an entry
   is created, renamed or removed, not when an existing file inside it is appended to — and appending
   to `lw-watchtower.jsonl` is this ledger's steady state. Ranking on the directory mtime alone therefore
   ranked "most recently gained a file", which flipped the answer between two live installs twice
   within six minutes on this machine, with no code change in between.
5. With no suffixed candidate the bare path is still used — but reported as **unresolved**.

Step 2 reading the name out of the manifest is why **the 3 August 2026 product rename moved this
directory**. `lw-gmhh` became `lw-watchtower`, so the scan now looks for `lw-watchtower*` and an
older machine's `lw-gmhh*` directory is not a candidate. Nothing here migrates it and nothing here
reads it: a resolver that also matched a legacy name would be a *writer* choosing between two
directories, which is the defect above wearing a second name. The old directory and its
`lw-gmhh.jsonl` are untouched, and `bin/lwg-uninstall.ps1` is the single component that still knows
that name — as a reader, so a removal reports the stranded directory rather than walking past it.
The full account, including what an existing install loses, is under `## [0.4.0]` in
[CHANGELOG.md](../CHANGELOG.md).

The suffix test is the load-bearing part. A plain "most recently written" rule is defeated by exactly
the bug it would be fixing: out-of-harness runs keep appending to the *bare* directory, so the dead
one routinely carries the newer timestamp. Excluding it first is what makes timestamps safe to use at
all — they now only ever choose between two real installs.

**The ladder above is what a COMMAND runs, and what a HOOK never does.** Claude Code hands a plugin
hook `$CLAUDE_PLUGIN_DATA`, so step 1 ends the matter and no hook ever ranks anything; a slash
command runs through `Bash(powershell:*)` and is never handed that variable, so it walks the whole
ladder. One resolver, two branches, and on a machine with two `lw-watchtower*` directories they can
land on different files — which is the whole of #270 and is why the configuring commands refuse to
write over an ambiguous resolution rather than reporting a write nothing reads.

Because three of this repo's shipped defects were things reporting success while doing nothing,
`Get-LwgStateDirInfo` returns `@{ path; source; resolved; candidates; ranked; home; home_source }`
alongside the plain path, where `source` is `env` | `discovered` | `bare` | `unresolved` and
`resolved` is `$true` only for the first two. A caller can tell "this is the live directory" from
"this is where I would have looked" — and, through the last two fields, which root step 2 searched
and why.

`ranked` — the suffixed candidates this call had to **choose between**, as full paths. Empty on the
`env` branch, which chooses nothing, and empty when there is no suffixed sibling. **More than one
entry means the answer came out of the mtime ranking and could have gone the other way**, and it is a
different question from `candidates`: a bare directory beside one suffixed sibling counts two
candidates and ranks nothing, which is not ambiguous. The configuring commands read it because they
are the callers that have to tell an operator that the file they are about to write may not be the
file a hook reads. Like `home` and `home_source` it is an added key: every existing reader takes
`path`, `source`, `resolved` and `candidates` by name.

Resolution is memoised per process and costs, measured on this machine in a fresh PowerShell 5.1:
**~32–42 ms cold on the `env` path a live hook takes**, ~75–105 ms cold when it has to discover
(~180 ms observed on a loaded machine), and **~0.3 ms warm** — against a 5 s hook timeout and a
~273 ms interpreter floor. The old one-line fallback cost ~7–10 ms cold and ~0.7 ms warm, so this
trades roughly 30 ms of a hook's cold path
for a directory that is actually the live one. The scan uses `[IO.Directory]` and `[IO.Path]`
statics throughout, never `Test-Path`, `Get-ChildItem` or `Join-Path`, and `plugin.json` is read with
`IndexOf` rather than `ConvertFrom-Json`, whose first use in a fresh process measured 159 ms here.

Nothing was migrated. `~/.claude/plugins/data/lw-watchtower/` still exists with its old contents; it is
simply no longer preferred.

### Three data directories, and why picking between them is not the fix

The author's machine currently has all three at once:

| directory | files | what created it |
|---|---|---|
| `lw-watchtower` | 6 | the historical bare literal. First record is `v0.1.0`. Still gains records from out-of-harness runs on checkouts whose `lib/common.ps1` predates `Get-LwgStateDirInfo` — its newest entries are `"session":"gate-test"` GateDeny records from a worktree running the gate suite |
| `lw-watchtower-inline` | 10+ | `lw-watchtower@inline` — sessions started with `--plugin-dir`, i.e. every worktree agent |
| `lw-watchtower-skills-dir` | 16+ | `lw-watchtower@skills-dir` — the junction install at `~/.claude/skills/lw-watchtower`, which is what an ordinary session loads |

`~/.claude.json` `pluginUsage` records `lw-watchtower@skills-dir` at 3297 uses against `lw-watchtower@inline` at
23, so the junction install is the live one and the inline one is real but incidental.

The discovery rule now picks correctly between them, but **that is a fallback correctness fix, not a
fix for the split.** Two install routes are two identities, Claude Code hands each its own
`CLAUDE_PLUGIN_DATA`, and the `env` branch — the one every live hook takes — never reaches the
ranking code at all. A trip written under one identity stays invisible to a session resolving the
other, and no rule inside this function can change that. The durable fix is to stop having two
install routes: install once, from [`.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json),
and drop the junction. The extra directories are historical data, not garbage; nothing here deletes
them.

The status line solves the same problem differently — it reads the **union** of every `lw-watchtower*`
directory and discards records by session id — because a reader can afford to read both and a writer
cannot write to both.

### What is in there

| File | Written by | Lifetime |
| --- | --- | --- |
| `lw-watchtower.jsonl` | every module | append-only audit trail, rotated at 5 MB carrying 500 records forward. **Not rotated at all until 3 August 2026** — `log_rotation`’s only call named `health.jsonl`, while this row named this file, its threshold and its carry-forward count |
| `health.jsonl` | `lib/supervisor.ps1` | append-only, same rotation |
| `advisory-<sessionkey>.json` | `lib/stop_advisories.ps1` | per session; "what have I already said" |
| `edits-<sessionkey>.txt` | `lib/post_edit.ps1` | per session; capped at 256 KB |
| `rule_stats.json` | **nothing, since 30 July 2026** — written by the Stop trip sweep | **cross-session**; per-rule false-positive counts. Historical; left in place |
| `context_windows.json` | `context_pressure` | cross-session; observed window sizes |
| `selfcheck.probe` | `lib/session_start.ps1` | cross-session; **29 bytes forever**. It is `self_health`'s state-writable probe, written with `-Replace` rather than appended, so every `SessionStart` — start, resume, clear and compact — overwrites the one line rather than adding to it. Nothing reads it. Absent entirely when `self_health` is off, which is what [configuration.md](configuration.md) means by "no probe runs" |
| `alerted.json` | `lib/supervisor.ps1` | cross-session, **not** per session, and this is the row most likely to be misread: it is one flat list in the state directory, shared by every session that ever wrote there. It is the alert-dedupe set — failed background-task ids bare, orphaned agent ids under an `orphan:` prefix — so one dead task alerts once instead of at every turn end. Capped at its last 200 entries; both the `Stop` and `SubagentStop` branches write it |
| `signals/ratelimit.json` | the **status line**, not a hook | cross-session; overwritten every render. The only on-disk copy of `rate_limits` and `context_window` — see [The signal bridge](#the-signal-bridge) |

`trips-<sessionkey>.json` had a row here — the per-session trip ledger, and the **state**
behind the status line's `GM` segment. Both gates were removed on 30 July 2026 so nothing could write
one, and later the same day the 12 remaining files were backed up to `trips-backup-20260730/` in the
same directory and removed, along with every piece of code that read them. Nothing in the state
directory holds trip state now.

The distinction between the first two rows and the rest is the one that matters: the `.jsonl` files
are an append-only record of what happened, and the per-session JSON files are current state.
Deriving state by scanning a window of the record is what made `GM` wrong in both directions — the
lesson is preserved in [Gates were removed deliberately](gates-removed.md), because the code that
taught it is deleted.

## Status line

The `HH` segment of the Claude Code status line is this plugin's only live indicator surface, and
the script that renders it is **not part of the plugin**. It is tracked at
[`statusline/statusline.ps1`](../lw-watchtower/statusline/statusline.ps1) and installed by copying — see
[Install](install.md#installing-the-status-line-part-of-the-install-and-a-separate-step).

```
row 1   model  HH  ORC  ctx  5h  7d  #branch  PR#  owner/repo
row 2   advisories - printed only when something is actually wrong
```

Everything on row 1 except `HH` and `owner/repo` comes from the status-line stdin payload, which is
read as UTF-8 from the raw stdin stream — not through `[Console]::In`, whose code page is the
console's and not the payload's. `HH` merges the health logs, scoped to the current session id.
**It has no thresholds and reads no configuration at all**: the glyph is chosen by counting, and
the only bounds it has are the three it declares itself — a 1 MB tail window, an 8192-character
per-record limit, and the last 300 usable records. `config.json`'s `thresholds` block is read by
this file for the `ctx`, `5h` and `7d` segments' **advisory row** and for nothing else, and the
colour of those figures is fixed at 50/75/90 in `Heat` rather than configured — see
[`config.json`](../lw-watchtower/config.json), whose comments on that block state the same thing. No process is
ever spawned: the line renders on every assistant message and on every `refreshInterval` tick, and a
nonzero exit or empty stdout blanks the whole row.

| Glyph | Meaning |
| --- | --- |
| green `HH` | the logs were read and this session is clean |
| red `HH`*n* | *n* faults for this session. Whether a later clean turn end can lower it depends on which arm produced it — see [Health and healing](#health-and-healing) |
| purple `HH?` | the supervisor or a healer agent is not installed, so nothing could be determined |
| purple `HHx` | a log **exists** and could not be read |
| dim `HH-` | nothing about this session was found to read — **not** an all-clear |
| any `…!` | at least one record was too large to read and was skipped, so the glyph in front of it was drawn from less than the whole log |

Green and dim are different facts and the trailing `-` is what separates them, not the colour. An
indicator that says *healthy* when it read nothing is worse than no indicator.

**Every state on this row carries its own glyph, so colour is never load-bearing.** That was not true
until 1 August 2026: both purple states rendered a bare `HH`, **the identical three characters** as
the green all-clear, separated by colour and by nothing else — while being its opposite. An operator
on a remapped palette, a monochrome or high-contrast profile, or reading a screenshot, was shown
*healthy* by a plugin that had established nothing. `?` and `x` now separate them
([`statusline/statusline.ps1`](../lw-watchtower/statusline/statusline.ps1), the `Paint 35` returns).

The two purple states are distinct from each other as well: `?` means the machinery that would answer
the question is absent, `x` means the machinery and a log are both present and the log would not
open — a stronger and more actionable statement. `x` is also not `!`: `!` means part of the log was
skipped and a verdict was still reached, `x` means no verdict was reachable at all. For whether the
health system is working, `/lw-watchtower:doctor` is still the better instrument — it cannot express a
fault by colour and has to say it in words. See
[Troubleshooting](troubleshooting.md#the-status-line-shows-purple-hh-or-hhx).

**A second segment, `GM`, was removed on 30 July 2026.** It reported governance state off this
session's trip ledger, and it rendered red or yellow `GM!`*n* for open trips, `GM?` for an advisory,
green for a ledger read clean and dim `GM-` for no ledger at all. With both gates gone nothing could
write a ledger, and once the ledger files themselves were removed the segment could only ever return
dim — one reachable value, which is no information. It was deleted rather than left as decoration,
and row 2's outstanding-trip line went with it. A future gate has to rebuild both; see
[Gates were removed deliberately](gates-removed.md).

### The signal bridge

**This process is the only one on the machine that receives `rate_limits` and `context_window`, and
until now it rendered them and threw them away.** It now writes them to
`signals/ratelimit.json` in the state directory before rendering.

**This is not a re-attempt of a blocked module, and the record it works around is unchanged.**
[Modules](modules.md#attempted-and-blocked-ratelimit_escalation-and-cost_tracking) records
`ratelimit_escalation` and `cost_tracking` as unbuildable: verified against the `claude-code 2.1.220`
binary across all 31 hook events, those fields are assembled in exactly one place — the status-line
input builder — and **no hook event carries any of them**. That finding stands, and no hook reads
`rate_limits` after this change either. What changed is only that the process which already has the
data writes it down, so something else can read a *file*. Neither blocked name is back in the
`modules` block.

| | |
| --- | --- |
| **Written to** | `signals/ratelimit.json` under **every** discovered data directory |
| **Write discipline** | `ratelimit.json.<PID>.tmp`, then `Move-Item -Force` |
| **Schema** | `schema`, `written_utc`, `session_id`, `five_hour`, `seven_day`, `context_window`, `unparsed` |
| **Not written** | `cost` — dollars are out of scope, and this file has never read `$d.cost` |

**Every data directory, not one.** This script is a `settings.json` command and **not** a plugin
hook, so it is never given `CLAUDE_PLUGIN_DATA` — the same fact that once had it reading a directory
the live plugin had stopped writing to. The consumers of this file *are* hooks, and they do get that
variable. A single path would therefore split producer from consumer on exactly the machines the
[three-data-directory problem](#three-data-directories-and-why-picking-between-them-is-not-the-fix)
describes. Writing to all of them cannot pick the wrong one — the same argument this file already
makes for *reading* the health logs.

**The temp name carries the PID** because every concurrent session runs its own copy of this script
against the same directory. A fixed `.tmp` name would mean two processes writing one temp file and
one of them publishing the other's half-written bytes — reintroducing the tear the rename exists to
prevent.

**A field the CLI did not supply is absent from the file — never `0`, never `null`.** A reader must
be able to tell *"not supplied"* from *"the value is 0"*; writing a default is the
`payload.workspace.repo` defect recorded in [Modules](modules.md), and it is not repeated here.
There are **three** input states, not two, and the row already renders them differently: absent,
usable, and present-but-unparseable — the purple `??`. An unparseable figure is omitted from its
block **and** named in `unparsed`, so a consumer can distinguish *the CLI said nothing* from *the CLI
said something that would not parse*.

`written_utc` is mandatory and formatted under the invariant culture; if it cannot be produced,
nothing is written. Consumers are required to treat a stale file as **no signal**, never as a last
known value. `resets_at` is passed through verbatim rather than localised — converting it here would
bake this machine's offset into a file another process reads.

**Cost, measured rather than assumed, on this machine in a fresh PowerShell 5.1:** **1.87 ms** per
render at one data directory, 3.48 ms at two, 6.19 ms at four — about 1.5 ms per additional
directory, since the write is one small file each. Against the ~178 ms the first `Get-ChildItem` in
this same function already pays, that is roughly **1%** of a cost this file already accepts. **No
throttle is shipped**, and this measurement is the reason; a 5 s throttle was specified as available
*if* the write proved measurable, and it did not. The number scales with the directory count, which
grows by one on every plugin-id change.

**The bridge cannot cost the row.** A nonzero exit or empty stdout blanks the whole status line, so
every write is wrapped, emits nothing, and one unwritable directory does not stop the others.
Verified under load: **136,057 concurrent reads during continuous renders, zero torn and zero empty**,
with `written_utc` advancing throughout — a reader that never observes a new timestamp would mean the
writes were not happening, which a parse-failure count alone cannot detect.

**If the status line stops running** — a different one configured, the CLI upgraded — the file simply
goes stale, and **every consumer is required to notice that rather than trust the last value**.

### The trip ledger — REMOVED, and recorded here as a design

**None of this exists any more.** Both gates were removed on 30 July 2026 by explicit owner
decision — see [Both gates were removed](modules.md#both-gates-were-removed) — and a trip was only
ever written on a gate's deny path. Later the same day the ledger itself went: `lib/trips.ps1`,
`lib/ack_trip.ps1`, `bin/lwg-tripped.ps1`, `commands/tripped.md`, the `GM` segment, the ledger-open
branch in `lib/session_start.ps1`, the turn-end sweep in `lib/stop_advisories.ps1`, and the 12
`trips-<sessionkey>.json` files themselves, which were backed up first.

This section is kept in the **past tense** because the design is the expensive part and a future gate
has to rebuild it. [Gates were removed deliberately](gates-removed.md) lists what to rebuild and in
what order; this is the record of what the thing actually did. **Nothing described below can happen
in a session today.**

`GM` was originally derived by scanning the last 25 lines of `lw-watchtower.jsonl`, and that was broken in
**both** directions at once:

- **It could never be cleared.** The `GateCleared` marker the status line looked for was written by
  no file in this repo. A trip had no route back to green at all.
- **It cleared itself anyway.** A `GateDeny` scrolls out of a 25-line window after ~15 further
  records, and `GM` then went green with the trip still outstanding. Reproduced from the live log: 15
  trips, none ever cleared, 25 unrelated records appended — green.

A tail is a window onto a stream, and a window is not state. So the state was moved into a
per-session ledger that nothing scrolls, `trips-<sessionkey>.json`, written by the gates on their
**deny path only** and closed at turn end by `lib/trips.ps1`. `lw-watchtower.jsonl` goes on being exactly
what it was — the append-only audit trail — and it is the only half of this that survives.

**The rule that governed every auto-close, and the one to carry forward:** a trip could close
automatically only when the plugin could verify a **fact about the world** — never when it could only
verify that time had passed. There was deliberately no "and it has been a while" branch anywhere in
the sweep. A guardrail that forgets on a timer is the false green the ledger existed to replace.

| Class | Closed when | Fact it rested on |
| --- | --- | --- |
| **held** | the target was provably untouched | the exists / mtime / length signature recorded at deny time still matched |
| **worked-around** | **never** | the target changed anyway, or came back through a route that was allowed |
| **false-positive** | at the next turn end | the rule denied because the gate could not read the command, or every target was provably scratch |
| **repeating** | as its severity dictated | three or more trips of one rule and severity collapsed into a single entry with a count |

Severity came from the **rule**, never from the count. `hard` was irreversible outside scratch — force
push, history rewrite, reflog expire, repo delete, writes inside `.git`, credential paths, every
`secret_scan` rule, and recursive deletion of anything that cannot be proven throwaway. `soft` is the
parser-refusal family (`unresolvable-command`, `unparsable-continuation`, `unresolvable-path`,
`recursive-delete-unknown`) and destructive rules whose targets were all scratch-scoped or unreadable.
Replayed against the live session's own 15 denials, that is 4 ledger items — 2 hard and 2 soft —
rather than 15 red ones.

Closing a false positive incremented a **cross-session** counter in `rule_stats.json`. That counter
was the tuning signal that replaced "switch the gate off": a rule that keeps producing refusals
nobody needed is a rule to fix, and the argument for fixing it has to be a number that outlives the
session it was noticed in. The file is still in the state directory, now purely historical; nothing
writes it.

Some trips had no fact available to close on — `git push --force` names no file to probe — and those
stayed open until acknowledged deliberately, by `lib/ack_trip.ps1` against a named session. **That
escape hatch is not optional.** Without it a ledger accumulates entries with no route out and becomes
a permanently red indicator, which is the exact defect it was built to remove.

Every close, automatic or acknowledged, appended a `GateCleared` record carrying its reason (`held`,
`tuning-candidate`, `rule-quiet`, `gate-recovered`, `acknowledged`). Nothing was ever rewritten or
removed. Open trips were never dropped — the 200-entry cap evicted closed entries only, oldest first,
and counted what it evicted.

Those `GateCleared` and `GateDeny` records are in `lw-watchtower.jsonl`, which survives, so the history is
still readable, and nothing reads it back as an open item. Nothing can clear
one now — `GateCleared` was only ever written by the sweep.

**Why it lives outside the plugin.** `statusLine` is a top-level key that Claude Code reads only from
`settings.json`. A plugin cannot supply one — there is no manifest field for it, and no hook event
renders a line — so the file has to sit at `~\.claude\statusline.ps1` regardless of where its source
of truth is kept. Tracking it here is the most that can be done: a version-controlled original plus
an install step.

**Why the rate-limit escalation lives there too.** The status line is the only process on the machine
that is handed `rate_limits` and `cost`. That is the same finding that kept `ratelimit_escalation`
and `cost_tracking` unbuilt, and then removed them from the registry altogether on 30 July 2026 —
see [Attempted and blocked](modules.md#attempted-and-blocked-ratelimit_escalation-and-cost_tracking)
— so the escalation is written where the data actually arrives. It reads the same `thresholds.ratelimit`
block a module would have read: `warn_pct` prints `approaching limit`, `land_all_pct` prints `land
all work`.

## Failure policy

Three rules, and they are not negotiable.

### 1. Every hook exits 0

A broken governance layer must never break a session, so every *observing* hook exits 0 whatever it
found. The rule was written for `destructive_gate` and `secret_scan`, which expressed a denial in
their *stdout* and never in an exit code: the CLI only parses stdout as JSON on exit 0, and a hook
exiting 2 has its stdout discarded, so a denial signalled that way would have been thrown away.

**There is one denial left to express, and it is expressed the other way round.** `delegate_gate`
arrived on `PreToolUse` later on 30 July 2026 and writes its reason to **stderr**, then exits **2**,
because on this CLI build only exit 2 blocks a `PreToolUse` call — exit 1 is a non-blocking error
and the tool runs anyway, which is a gate that has silently failed open. It writes the stdout
envelope first and its header records that the envelope is redundant here for the reason above. So
the rule is *every hook exits 0 except a `PreToolUse` denial*, and the exception is the only
component in this plugin that can refuse anything.

The other deliberate nonzero exit in the tree is the `failure_capture` supervisor's exit 2, which is
an `asyncRewake` alert rather than a refusal — see [Health and healing](#health-and-healing).

### 2. A self-check asserts behaviour, not presence

`SessionStart` proves the config parsed to real booleans, the thresholds are numbers, the payload
carried a session id, and the state dir actually accepted a write. "The files exist" is not evidence
that a monitor can fire — a prior project learned that the expensive way. (The citation here named an
issue number in a private repository until 3 August 2026. No reader outside that repository could
open it, so the sentence was asking to be believed on the authority of a document nobody can read;
the lesson stands on its own without it.) A
failed probe downgrades the session to `degraded` and says so in both the banner and the model's
context.

### 3. The plugin never overstates itself

Coverage is counted from the module registry in `lib/common.ps1`, never from the flags in
`config.json`. A configured module is an intention; an implemented module is a fact, and only facts
reach the banner or the model's context. A monitor that reports healthy while doing nothing is the
failure this plugin exists to prevent, **and that includes reporting on itself.**

This is why the banner read `8/11` and not `10/11` for as long as `ratelimit_escalation` and
`cost_tracking` were declared: two of the eleven needed data that no hook receives, so they were
**not** written, and an honest 8 beat a fictional 10. On 30 July 2026 the two placeholders were
removed outright and the banner counts only what is built — the reason they cannot be built was moved to
[Attempted and blocked](modules.md#attempted-and-blocked-ratelimit_escalation-and-cost_tracking)
rather than deleted with them, because the record is the part that stops someone re-attempting them.
The same rule governs the numbers a module produces: `context_pressure` suppresses its percentage
outright rather than
divide by a denominator it does not trust, `git_hygiene` reports UNKNOWN rather than clean when git
does not answer, and `orphan_watch` is registered as `observe` rather than inflate the gate count
with something that alerts and cannot block. `verification_gate` was the long-standing example of
that last rule — a module with the word *gate* in its name, registered `observe` and never counted
— until it was removed on 2 September 2026.

It is also why the banner reads **`0 gates · observe-only`** while three shipped gates sit
switched off, rather than counting a capability that is not doing anything.
The two original gates were removed on 30 July 2026, the count is derived from the registry rather
than written down, and the mode ladder returns `observe-only` on a **live** gate count of zero before
it tests anything else. Nothing about the removal is inferred from an absence: `config.json` records
the removal of each gate in `$status`, and records no live-gate count — that number is computed by
`Get-LwgActiveGates` from the registry and the switches. The model-visible context states outright
that no gate is live, so nothing is blocked or scanned automatically.

The rule has been applied against this plugin's own code repeatedly. Each of these was a real defect
here, found and fixed:

| The defect | What it looked like |
| --- | --- |
| The banner counted `config.json` flags | `12/12 modules, 3 gates, enforcing` while three modules had code and no gate existed at all |
| `Split-LwgTokens` returned a comma-wrapped array | every token list had `Count` 1, so **no gate rule could ever fire** while the gate reported clean |
| `Get-LwgRepo` read `payload.workspace.repo` | a field no hook carries, so every per-repo override applied to nothing while appearing to work |
| `self_health` ran unconditionally | its flag was a switch wired to nothing — inside the module whose job is to catch exactly that |
| `log_rotation` sat inside the record writer | `failure_capture: false` silently disabled rotation too, while `log_rotation` still reported itself active |
| `git_hygiene`'s `probe_ms` | overlapping the git call quietly changed what the field measured: a 93 ms call logged as 550 ms |
| `HH`/`GM` resolved the data dir as `lw-watchtower` | the real dir is `lw-watchtower-skills-dir`, so the indicator read an empty file and rendered **unconditional green** | <!-- doc-claims:ignore — a record of a shipped defect; GM existed then and was deleted on 30 July 2026 -->
| The suite exited 0 or 1 and nothing else | a run that died on case 3 of 143 was indistinguishable from a clean run |
| A `-Only` filter matching nothing exited 0 | zero cases ran and it printed "every selected case ran and passed" |
| The README claimed tests that did not exist | advisory-shape assertions and escaper round-trips were never written |

Four modules are the live application of that rule today: `send_liveness_gate`,
`completion_audit`, `orphan_watch` and `delegate_gate` are all built, therefore counted as
implemented, all four ship switched off, therefore not counted as enabled, and all four are named in
the model-visible context as built-but-off rather than left unaccounted for. So on a default install
the banner reads

```
LW-WATCHTOWER v0.4.0 · 7/11 modules enabled (4 off) · 0 gates · observe-only
```

and the `(4 off)` is those four being accounted for rather than dropped from the count. This
paragraph said the opposite — that implemented and enabled agreed for every module and the
parenthetical was never printed — from 30 July 2026 until 3 August 2026, which is the interval
between the first module shipping off and nobody re-reading the sentence afterwards. The
`(0 planned)` reasoning it carried is still right and still applies: a caveat-shaped phrase with
no caveat behind it is the same overstatement pointed the other way, which is why the parenthetical
appears only when there is something in it. **A module being off never decides the mode word.** A
switched-off module used to be the reason the banner read `partial` rather than `enforcing`; while
the live gate count is zero the mode is `observe-only` whatever any flag says, because "nothing can
be blocked" is the larger fact and must be the one on the banner.

The rule bites hardest where a module is on and unvalidated, and that is now a smaller set than it
was: `mission_drift` shipped on with a trigger that had never been checked against a real session,
and it was removed on 2 September 2026 rather than left there. The distinction it stood for is worth
keeping, because it applies to every module still here. `tests/stop_behaviour.ps1` runs the Stop
handlers end to end through a real pipe into a real child process, and a suite like that can
establish that a trigger behaves as written; it cannot establish that being warned by it is right,
because that judgement is not in the code. Nothing in `tests/` closes that gap for any module, and
saying so is the point.
