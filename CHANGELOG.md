<!-- doc-claims:ignore-file — a changelog is a RECORD, and every count in an entry below is
     what was true on the day that entry describes. `tests/gate_delegate.ps1`, **54 cases** is
     correct history and would be a lie if it were updated to today's number, so
     tests/doc_claims.ps1 reads nothing in this file. Everywhere else in the tree, that guard
     holds a stated count to the tree; see its header for the per-line marker. -->

# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **`v0.3.0` (2026-07-31) is the first tagged release.** Every heading below it is a
> manifest-version record, not a publication date: those headings are the values recorded in
> `.claude-plugin/plugin.json` at the time, and the date on each is the date that number was set in
> the manifest. **No tag existed before `v0.3.0`** — `0.1.0` and `0.2.0` were declared and worked
> under, never published, which is why neither carries a link at the foot of this file.

## [0.4.0] — unreleased

**The manifests declare `0.4.0` and no tag carries it.** That is deliberate and it is the rule this
release adds: `main` must never declare a version a tag has already published. It was written
because this section was EMPTY while twelve commits and +5322/-489 lines sat on `main` past
`v0.3.0`, every declaration site still reading `0.3.0` — so the tag and the branch were two
different trees wearing one name, and two of those commits changed how an existing `config.json` is
read. Two entries below were also written into the released `[0.3.0]` section after the tag existed;
they are moved here, unedited, because they describe post-tag work.

**Why `0.4.0` and not `0.3.1`.** See Breaking. A patch number would be a lie about a config file
whose meaning changed.

This section carries a `### Breaking` heading, which the rest of this file does not use. It is here
because burying a config-semantics change under "Changed" is precisely the understatement this
project exists to refuse.

### Breaking

- **The shipped payload became a subdirectory, and every path that pointed at it moved in the same
  commit (2026-09-03, #236).** `.claude-plugin/marketplace.json` declared `"source": "./"`, a form
  with no exclusion mechanism, so **every tracked file in this repository was the payload**: a
  consumer installing this plugin received `docs/`, `tests/`, `.github/` and `CHANGELOG.md` along
  with the code. Nine `git mv` operations put `agents/`, `bin/`, `commands/`, `context/`, `hooks/`,
  `lib/`, `statusline/`, `config.json` and `.claude-plugin/plugin.json` under `lw-watchtower/`, and
  the `source` now names that subtree. **Measured on a real install: 35 files reach a consumer
  instead of 94, and `Compare-Object` between the cache and the payload subtree is empty.**
  `.claude-plugin/marketplace.json` stays at the repository root, because it is the file the CLI
  reads to add the marketplace at all.

  **What this changes for you.** Nothing an operator has to do: the plugin id, the command surface
  and the state directory are all unchanged, and an existing install updates in place. What changes
  is every path in a bug report, a script or a note of your own — `bin\lwg-doctor.ps1` is now
  `lw-watchtower\bin\lwg-doctor.ps1` in a clone, and the marketplace cache holds the subtree rather
  than the repository. The move had to be one commit because a payload that moved while a pin did
  not is not a build failure but a silent one: `.gitattributes`' `eol=lf` pin on the status line,
  `.gitignore`'s entry for the worker-facts scratch file, and nine repo-relative literals in
  `bin/lwg-update.ps1` are each anchored to the repository root, and each fails quietly when left
  behind. `HANDOFF.md` and four working papers moved to `.github/notes/` in the same commit, for the
  same reason: they are not documentation for a consumer and they were being shipped as if they
  were.

- **The product is renamed from `lw-gmhh` to `lw-watchtower` (2026-08-03). This is the one entry in
  this file that names the old product in the present tense, and it is the canonical statement of
  what the rename does to an install that already exists.** Everywhere else the old name survives
  below, it is history and was true on the day its entry describes.

  **What moved.** The plugin id in `.claude-plugin/plugin.json`; the marketplace name and the plugin
  entry in `.claude-plugin/marketplace.json`; the whole twelve-command surface, from `/lw-gmhh:*` to
  `/lw-watchtower:*`; the five `output-styles/lw-gmhh-*.md` files, renamed on disk; the event log
  filename; the display form `LW-GMHH` on every banner, header and status message; and the
  repository, `LEAPWare-Software/LEAPWare-GMHH` → `LEAPWare-Software/LEAPWare-Watchtower`.

  **What did NOT move, and why.** The internal `lwg` / `Lwg` / `LWG` prefix — twelve `bin/lwg-*.ps1`
  scripts, every function and script variable in `lib/`, the `settings.json.lwg-<stamp>.bak` backup
  names and the `DELETE-MY-LWG-LOGS` confirmation token. It was left **wholesale**, not partly; the
  argument is written out under *The `lwg` prefix stays* in `CONTRIBUTING.md`. The short version:
  renaming it would make every settings backup taken before today invisible to the rollback that
  exists to restore them, and it is not the product name — `git grep -i gmhh` does not match it.

  **THE STATE DIRECTORY MOVED, AND NOTHING MIGRATES IT.** This is the part that costs an existing
  install something, so it is spelled out rather than listed. Claude Code names a plugin's data
  directory `<plugin-name>-<source-id>`, and every reader here derives that name from
  `plugin.json` through `Get-LwgPluginName` — so the state directory was never an independent
  choice, and renaming the plugin id moved it. `~\.claude\plugins\data\lw-gmhh*` and the
  `lw-gmhh.jsonl` inside it are still exactly where they were. **No file was moved, copied or
  deleted by this change.** What an existing install loses is continuity, not records:

  - The status line's `HH` segment, the `sitrep` command's governance counts and the health fault
    count all resolve `lw-watchtower*` and start again from zero. Historical `GateDeny` records,
    faults and advisories are readable only by opening the old file yourself.
  - `bin/lwg-doctor.ps1` was **not** taught the old name. On a pre-rename machine its `state-dir`
    row reports the new location and, until a session has run, `unresolved` — which is honest about
    where it looked and says nothing about the old directory. `docs/troubleshooting.md` names this
    as the second cause of an `unresolved` row.
  - `bin/lwg-uninstall.ps1` **was** taught it, and is the only component that knows it.
    `$script:LwgLegacyDataNames` is declared in that file and referenced only there, deliberately
    not in `lib/common.ps1`; no writer names it and no write path dot-sources this script. The
    sibling sweep runs over the legacy name as well as the current one and reports what it finds
    marked `LEGACY`; the legacy event-log name is also in the ownership list, so an operator who
    points `CLAUDE_PLUGIN_DATA` at their old directory is not told it is somebody else's data.

    **What that fixes, scoped to the branch it fixes, because the other branch was already honest.**
    On a machine where any `lw-watchtower*` directory exists — the ordinary post-upgrade state — the
    resolver resolves, the `state-data` row lists that directory and only that directory, and
    `-RemoveData -ConfirmToken` would have deleted exactly what it listed, reported success, and
    never mentioned the `lw-gmhh*` directory beside it. **That** is the clean-removal-over-a-
    directory-never-looked-at case, and it is the defect class this file records at `[0.3.0]` for
    the redirected data dir. On a machine where no `lw-watchtower*` directory exists yet, nothing
    resolves and nothing is swept, so the row already read `UNRESOLVED / CANNOT REPORT - the
    location is unknown` with an explicit "nothing here should be read as evidence that there are
    none" — wrong about the location, but never claiming a removal. The sweep improves both; only
    the first was a false success.

    **`-RemoveData` now removes more than it did, and that is the point of saying so.** The keeping
    rules are unchanged — state is still kept unless `-RemoveData` is passed with the token — but
    the SET the flag acts on has grown by the legacy directory. An operator who passes it on a
    pre-rename machine deletes their `lw-gmhh*` data too. That is the intended behaviour (leaving it
    behind while reporting a clean removal is the thing being fixed) and it is stated rather than
    left to be discovered, because an unannounced widening of what a destructive flag reaches is the
    same defect as an overstated claim.

  **No compatibility aliases were added, anywhere.** `/lw-gmhh:*` resolves to nothing;
  `/plugin install lw-gmhh@leapware-gmhh` resolves to nothing; there is no marketplace entry kept
  alive under the old name and no deprecation window. That is a decision made on a measurement, not
  an oversight: the predecessor repository reported zero forks, zero stars, zero watchers and a
  one-account collaborator list, so the rename breaks no install that exists. Landing it later would
  have cost a migration path, twelve command aliases and a deprecation cycle.

  **One thing an operator has to fix by hand.** An `outputStyle` value of `lw-gmhh-brief` (or any of
  the other four) in a settings file now names a file that does not exist.
  the `verbosity` and `plain` commands print the style the preference asks for
  beside the `outputStyle` actually set, so the mismatch is visible; neither writes that key, for
  the reasons in `bin/lwg-toggle.ps1`. Re-pick it under `/config`.

- **`"delegate": "false"` — the STRING, not the boolean — armed the only gate this plugin ships at
  `v0.3.0`, and is IGNORED at `0.4.0`.** `Test-LwgFlag` in `lib/common.ps1` tested `[bool]$g`, and
  `[bool]` on a non-empty string is `$true` in PowerShell. So the text an operator writes when they
  mean *off* switched the `delegate_gate` **on** — and an armed gate refuses the `Bash` call that
  `/lw-gmhh:delegate off` runs, which is a near one-way lockout out of a typo. The rule is now
  `$g -is [bool]`: only a real boolean is a setting. Anything else is **ignored at the scope holding
  it** — resolution continues as if that level said nothing, so a junk per-repo override cannot
  disarm a global `true` — and is recorded as a `ConfigInvalidFlag` event. Never silent, never
  coerced.

  **What an operator should check, before upgrading:** open `config.json` and look for **quoted
  booleans** — `"true"` or `"false"` with quotes — anywhere under `interaction`, under `modules`, or
  under any `repos.<slug>` override, and replace them with unquoted `true` / `false`. If you wrote
  `"delegate": "false"` you have been running with the gate ON; at `0.4.0` you will be running with
  it OFF, and **neither is what you asked for**. The same rule reached `Test-LwgModule` (`modules`
  block) and `module_config` in the same release, so `"docs_coupling": "false"` and
  `"require_outside_root": 0` change meaning too — see Fixed.

- **JSON member names are matched case-insensitively by `lib/gate_delegate.ps1`'s fast path, where
  they were matched `Ordinal`.** A config key differing only in case did not match before and does
  now. Concretely, `"Interaction": { "delegate": true }` — and `"Repos"`, and `"REPOS"`, and a name
  spelled with a `\uXXXX` escape — were **not seen** by the pre-exit scan, which then read its own
  failure to find the member as proof the member was absent and allowed the call. Five spellings
  that should have denied, allowed. If you have relied on a capitalised key being inert, it is not
  inert any more; it now means what it reads as.

### Removed

- **Six slash commands, and everything that only existed to serve them (2026-09-02, #199).**
  `/lw-watchtower:status` folded into `/lw-watchtower:doctor`, which already printed the same roster
  off the same registry; `/lw-watchtower:checklist` and `/lw-watchtower:sitrep`, which reported the
  maintainer's own project on a consumer's machine; `/lw-watchtower:resolve`, which hand-cleared a
  fault count it could not clear in the case that mattered; and `/lw-watchtower:verbosity` and
  `/lw-watchtower:plain`, which recorded an output-style preference **nothing applied** — a switch
  wired to nothing, which is the defect this plugin exists to catch, shipped inside it. Their
  scripts went with them: `bin/lwg-checklist.ps1`, `bin/lwg-sitrep.ps1`, `bin/lwg-resolve.ps1`,
  `bin/lwg-evidence.ps1` and `lib/resolve.ps1`, plus `checklist.json` and the five
  `output-styles/*.md` files. `tests/evidence_states.ps1` went with the evidence engine it drove.
  **Six commands are left**, and `/lw-watchtower:doctor` fails on a live-looking reference to a
  command with no file behind it, which is what forced the references out of the tree as well as
  the code.

  **If you set `outputStyle` to one of the five**, that key now names a file that does not exist and
  nothing here will tell you: no command reads or writes it any more. Re-pick it under `/config`.

- **`verification_gate` and `mission_drift`, and the `lw-class` classifier that only
  `verification_gate` read (2026-09-02, completed by #201).** `mission_drift` had been on by default
  on every install with its trigger never validated against a real session — the only module here
  that both fired unasked and rested on a judgement no case could establish. `verification_gate` kept
  "gate" in a name that was never one. Both are gone from `$LwgModuleRegistry` rather than switched
  off, because a name on the banner that means nothing is the thing this project refuses. The
  `lw-class` frontmatter key went with the reader: **the five role files that declared one no longer
  do, and nothing in this release reads a role's class.** A copy of `lw-class: verify` in a role of
  your own is ignored by the loader and can stay or go.

  **The registry is now eleven modules — eight observing, three gates** — and the banner reads
  `7/11 modules enabled (4 off)` on a shipped config.

### Added

- **`tests/config_behaviour.ps1` and `tests/state_resolution.ps1`** — two behavioural suites for
  surfaces that had none: the config command's write path, and the state-directory resolver whose
  precedence rules every other component depends on and no case had ever exercised.
- **A version-declaration guard that runs on a tag and on every pull request** (#209, #219, #224).
  `.github/scripts/version_declarations.ps1` holds the five declaration sites to each other, and —
  when a tag is passed — to the tag and to `CHANGELOG.md`'s heading for it. `release.yml` calls it
  with the tag and **can refuse to publish**; `ci.yml` calls it without one on every push and pull
  request, where the two tag-shaped rules report NOT CHECKED rather than passing vacuously. Both
  callers run the guard's own fixtures first and refuse to trust a live answer from a guard whose
  rules did not fire. This closes the gap where a drifted declaration was only ever noticed on
  release day, in the one workflow where stopping costs most.
- **A red-first annotation guard** (#226). `.github/scripts/redfirst_annotations.ps1` reads every
  `tests/*.ps1` and holds the **shape** of its red-first annotations: a line claiming a baseline must
  name a commit, and a case id an annotation names must be a case that suite declares. It states its
  own limit in its header rather than in a footnote — it **cannot** re-run a baseline, so an
  annotation citing a real commit against a case that could never have failed there passes it — and
  a rule that matched nothing anywhere exits 2 rather than reporting a clean run.
- **A tenth rule in `tests/workflow_guard.ps1`: `permissions-write`** (#225). Until 3 September 2026
  nothing here read a `permissions:` block, so a workflow granting `contents: write`, `pages: write`
  or `id-token: write` parsed clean and exited 0. The rule is structural rather than a grep, because
  two forms defeat one: the block sits at workflow level **or** at job level where it overrides, and
  the `write-all` shorthand is a scalar carrying no `": write"` to search for. Its allowlist holds
  two entries, both `release.yml`'s, kept separate so dropping either does not quietly widen the
  other.
- **A `claude-version` check in `/lw-watchtower:doctor`** (#218, #224), reporting the Claude Code
  build against the one the hook events were read out of. It has three states and only one warns, and
  **a build that could not be read at all is a PASS with a detail saying so in words** — that is the
  normal state, because the CLI exports no version variable, and it is a limit on what can be
  observed from here rather than a fault in the tree.

- **`tests/doc_claims.ps1` — the check that asks whether the PROSE is right.** Every other check in
  this repository asks whether the code is. It fails the build when a tracked page states a
  checkable quantity the tree contradicts: files in `tests/`, how many test behaviour, cases per
  suite, CI check steps, doctor checks, commands, and modules declared vs observing. **Nothing in it
  is hardcoded** — it counts with `git ls-files`, parses `$LwgModuleRegistry`, runs
  `bin/lwg-doctor.ps1` to read its own header, and runs every sibling suite to read the tally each
  prints about itself, which is also how it decides which are behavioural. A guard carrying its own
  copy of the numbers would be one more place for them to be wrong. Historical sentences are
  exempted by an HTML-comment marker rather than corrected, because correcting a record falsifies
  it. Green means "no phrasing this guard recognises is stale", **not** "every number is right".

- **`tests/uninstall_footprint.ps1` and `tests/evidence_states.ps1`** — two behavioural suites, each
  landing with the fix it proves, each a real child run of the real script against a throwaway tree.
  The uninstaller suite asserts on the **filesystem** as well as the report, deliberately: a suite
  that only read the text would be satisfied by a script that prints well and deletes nothing, which
  is exactly what shipped.

- **Section L of `tests/gate_delegate.ps1` (79 → 80 cases) and section E of `tests/stop_behaviour.ps1`
  (126 → 127)** — one case each, and the only case in either file that asserts on **the suite itself**
  rather than on anything the suite drives: that the operator's live event log, `lw-gmhh.jsonl` in the
  resolved state directory, is the same **size in bytes** after the run as it was before it. They land
  with the fix below, the way the two suites above landed with theirs. Each is also the only shape of
  case that could have caught that fix's defect — every other case in both files reads an exit code, a
  stream, a file the suite made under the temp directory, or a wall-clock median, and a record appended
  to a file in the operator's profile moves none of those, so **79 green cases and 126 green cases sat
  alongside a live leak for as long as it ran**.

  **Read what they cover, because it is one clause of three and one clause of four.** Neither asserts
  anything about that log's *contents*, about `health.jsonl`, about the rest of the live state
  directory, or about the operator's `config.json`. Those are still promised on the strength of the
  sandbox and **asserted by no case**; the event log is the clause that is checked because it is the
  one the leak actually reached. Three further limits are stated in the suites rather than left to be
  found: a size is not content, so a run that appended one record and removed exactly as many bytes
  elsewhere would pass; **neither case covers an abort**, since a suite that throws before it never
  runs it, and the teardown in the `finally` is what makes that safe going forward; and either can go
  red for a write it did not make, because that file has one writer per *process* — a Claude Code
  session open in another window appends to it too, which was **observed** during development rather
  than feared. A lone failure means re-run that suite standalone, with no session open, before reading
  it as a regression. Filtering the log by content to avoid that was refused: a check that has to guess
  which records "look like" fixtures is a check that can be argued with.

- **Two version-identity rules inside `tests/doc_claims.ps1`.**
  `version-declarations-agree` holds all five declaration sites to each other;
  `version-not-a-published-tag` fails the build when the declared version is one `git tag -l`
  already lists. **The second one does not run in CI and says so on every run**: `actions/checkout@v4`
  checks out at depth 1 with no tag refs, and `git tag -l` printing nothing is not evidence that
  nothing was tagged — so it reports NOT CHECKED rather than passing vacuously. It runs on an
  ordinary clone, which is where a release is cut.

- **A `## Versions and releases` section in `CONTRIBUTING.md`** stating the rule, the five
  declaration sites, the difference between a declaration and a citation of a tag (`## [0.3.0]` and
  "UAT against v0.3.0" name the tested tree and must never be bumped), and the release procedure.

### Changed

- **Operator settings leave the git working tree (#11, #229).** `/lw-watchtower:config` and
  `/lw-watchtower:delegate` used to rewrite the tracked `config.json` in the plugin root. Arming the
  gate therefore dirtied the plugin's own checkout, and `/lw-watchtower:update` then refused to pull
  — permanently, because the thing making the tree dirty was the plugin. Both commands now write
  **`config.override.json` in the state directory**, and every reader merges the override over the
  shipped defaults with the override winning. Both print both paths on every run.

  **What to check in your own config.** If you edited `config.json` by hand before 3 September 2026,
  that edit is still honoured wherever no override overrides it — but a hand edit there now changes
  nothing while an override says otherwise, and the pages that told you to make it have been
  corrected. Deleting the override is safe and returns every setting to the shipped default;
  deleting `config.json` is not, and both commands refuse to write when it cannot be read, because
  an override is merged over defaults and not over a file nobody could parse. **One carve-out:**
  `context_injection` is the module `/lw-watchtower:config` will not switch, because
  `lib/subagent_start.ps1` reads `config.json` directly on its fast path and an override for it
  would be reported as applied and ignored by the hook it switches. The command refuses and says so.

- **The doctor reads the settings file the CLI actually reads** (#224), and an unread Claude Code
  build stopped being reported as a fault.

- **The declared version is `0.4.0`.** Five sites moved together — `.claude-plugin/plugin.json`,
  `.claude-plugin/marketplace.json`, `config.json`, `lib/common.ps1`'s `$script:LwgVersion`, and the
  pre-`common.ps1` fallback in `lib/session_start.ps1`. The six sample banners that transcribe it —
  one in `README.md`, one in `docs/faq.md`, four in `docs/modules.md` — moved with them, because
  bumping some copies of one rendered string and not the others would leave the tree stating two
  versions for the same output, which is worse than being uniformly behind. `docs/faq.md`'s
  "what version is this" answer was rewritten for the same reason: a banner and an answer
  disagreeing inside one page is the defect `tests/doc_claims.ps1` was built to catch.

- **`README.md` and `docs/install.md` now say which tree each install route yields.** The marketplace
  entry is `"source": "./"` with no `ref`, `tag` or `branch` key, so
  `/plugin marketplace add` + `/plugin install` resolves the repository's **default branch** — you
  get whatever `main` held at the moment you installed, which is not the tree any tag was tested
  against, and two installs a week apart need not be the same code. **No pin was added and none is
  claimed**: that is a property of the route, not something a version key can fix. The pages state
  it, name `git checkout v0.3.0` + junction as the route that gives a known tree, and name the cost
  of doing so (`v0.3.0` receives no fixes).

- **The status line distinguishes two purple states by GLYPH, not by colour alone** — `HH?` when the
  health machinery is absent, `HHx` when a log exists and would not open. Both previously rendered
  the bare `HH`, character for character identical to the green all-clear, so an operator on a
  remapped palette, a monochrome profile or a screenshot was shown *healthy* by a plugin that had
  established nothing. `docs/architecture.md` states four lines below that table that colour must
  never be the only signal.

- **`bin/lwg-setup.ps1`'s Q1 no longer prints `recommended: YES` for an answer that selects nothing**,
  and the lead-in no longer claims every question has a recommendation that is safe to accept — it
  was already false of Q2 and is now false of two of six.

### Fixed

- **`git_hygiene`'s timeout killed the child and left its helpers running** (#98, #207). Every child
  got a hard timeout and the child was killed on expiry — a helper it had spawned was not, so a slow
  `gh` call could outlive the turn that started it. The kill is now `taskkill /T /F`, so the child
  **and the helpers it spawned** go together. Turn end is still never blocked, and the residual
  window is a pid reissued in the microseconds after the `HasExited` check, which the old `Kill()`
  fallback always carried too.

- **The doctor reported a log it could not read as a dead hook** (#42, #203), reported an untracked
  tree as tracked, and carried a check-id set that no longer matched what it ran (#204, #205, #217).
  Each of those makes an unrun check read as a passed one, which is the failure class this whole
  repository is organised against.

- **The deleted resolver was still named as live in shipped code and in the guards' own headers**
  (#192, #231, #235). `lib/resolve.ps1` and `bin/lwg-resolve.ps1` went with the `/resolve` command;
  the references to them did not, so scripts still pointed a reader at files that were not there.
  The two temporary allowlist entries #231 landed with were retired in the same pass rather than
  left to become permanent.

- **Two CI guards were being skipped by a sibling step's failure** (#209), so a red build could hide
  whether either had run at all. Both now run on `!cancelled()` and report their own verdict.

- **Two committed cases could not fail** (#136, #137, #144, #177, #216, #232). They asserted
  something true of any tree, so they had been green since the day they were written and would have
  stayed green through the defect they were named for. A case that cannot fail is worse than no case,
  because it occupies the slot where a real one would be noticed missing.

- **A non-repository identity was published on `main`, and the probe that existed to prevent it
  could not see the field it was in — PARTIALLY resolved, and the residual is named below.** Three
  squash commits carried a personal address in a `Co-authored-by:` trailer. `checklist.json`'s
  `P3-identity` rule read `git log --all --format=%ae%n%ce` — the **author and committer** fields — and
  never a commit body, so the probe was green while the exposure was live and world-readable. It was
  also a *denylist*: it forbade one address in two fields, so it could only ever catch an exposure
  somebody had already found, while claiming to establish "exactly one identity".

  **What this fixes.** `main`'s history was rewritten on 2026-09-03 (`b1e4394` → `21b8f49`), dropping
  the trailers; every rewritten commit keeps its tree hash, so the content is byte-identical and only
  message bodies changed. Two root causes were then closed as controls rather than habits: the
  repository's `squash_merge_commit_message` setting was `COMMIT_MESSAGES`, which is what pre-filled
  a `Co-authored-by:` line for every distinct branch author, and is now `PR_BODY`; and the machine's
  *global* git identity was the personal address, which every clone but this one inherited — now
  overridden by a conditional include keyed on the remote URL, so a clone that does not exist yet
  still authors correctly. `.github/scripts/identity_scan.ps1` replaces the probe with an
  **allowlist** across author, committer **and** trailers, and its report masks every address it
  finds, because a CI log on a public repository is a publisher.

  **What this does NOT cover, and it is not a small residual.** Four pull-request refs on this remote
  carry the address as the **author and committer** of their tip commits — not merely as a credit
  line. A pull-request ref is owned by GitHub: deleting the branch does not remove it, no push
  reaches it, and rewriting `main` does not touch it. **Only GitHub Support can purge one**, and that
  request is outstanding. The pre-rewrite commits also stay fetchable by SHA until GitHub collects
  them. So the honest state is *`main` is clean and the refs are not*. The scan is scoped to `main`'s
  history for exactly that reason: a check that goes red on a condition no contributor can fix is a
  check somebody eventually deletes.

  **Found while fixing it, by the new guard on its first run:** every Dependabot commit also carries
  `Signed-off-by: dependabot[bot] <support@github.com>`. Nothing had ever seen it, because nothing
  had ever read a trailer. It is a GitHub role address and is allowlisted with that reason stated.
  The guard then found a second one on its own pull request: a `pull_request` event checks out
  GitHub's ephemeral merge commit, which is authored by the maintainer account's `users.noreply`
  alias rather than by the repository identity. That alias is GitHub's own privacy mechanism and is
  the author of any web-UI commit, so it is allowlisted with that reason stated too.

- **The uninstaller reported success and deleted nothing when the data directory was redirected.**
  `bin/lwg-uninstall.ps1` hardcoded `~\.claude\plugins\data` and never read `CLAUDE_PLUGIN_DATA` —
  the variable `lib/common.ps1` calls authoritative and every other component resolves through. An
  operator typed a destructive confirmation token, was told `APPLIED: 0 change(s), exit 0`, and all
  five files were still on disk. **Both halves are the founding defect this plugin exists to
  catch: it failed to act, and it reported success.** Resolution now goes through
  `Get-LwgStateDirInfo` and nowhere else, and the report distinguishes the two answers a hardcoded
  path collapsed into one — a location that resolved and holds nothing is `absent` and exits 0; a
  location that will **not** resolve is `UNRESOLVED`, names itself, and exits 2 when `-RemoveData`
  was asked for, in the dry run as well as under `-Apply`. Deletions are verified gone before they
  are counted as a change.

- **A probe that COULD NOT RUN rendered as a probe that ran and found the thing absent.** On the
  marketplace install route the plugin directory has no `.git`, so every `kind: command` evidence
  rule that shells out to git exited 128 having read nothing, and `bin/lwg-evidence.ps1` scored that
  as `[ ] NOT STARTED` — which the product's own legend defines as "a probe RAN and found the thing
  absent". Read as the product defines that mark, two rows told a consumer that the owner's personal
  address WAS left in history and that a private project's name IS in the tree. Both false, neither
  measured. Three results now reach UNVERIFIED instead: git exiting 128 *with* a `fatal:` line
  naming no repository (both halves required — 128 is also git's code for a bad revision, where the
  probe genuinely answered no), an interpreter refusing an absent `-File` target, and the expected
  exit with **empty stdout** under a rule that proves its item from `stdout_match`. **A probe that
  reached its question and answered no still renders NOT STARTED**; eleven of the new suite's 23
  cases exist to require that.

- **A capitalised config key made the only gate fail open while `/lw-gmhh:status` reported it live.**
  See Breaking for the matcher. The rule the file now states: *a finding about absence may be used
  only when the scan that produced it abstained on everything it could not decode.* Anything the
  scanner cannot resolve to a definite name is `$null` — I DO NOT KNOW — and falls through to the
  slow path. "Not found by me" is never "not there". A member name containing any backslash aborts
  the whole scan rather than decoding it, because abstaining is correct and cheap and a decoder
  would be a second JSON reader on a blocking path.

- **The gate read a config flag as off while the command reported it on**, and then **a tuning key
  read as a boolean let a typo disarm the module that ships on.** The boolean-only rule reached one
  reader before it reached the others, which opened a reporter/reader divergence — the exact defect
  class this plugin exists to catch. It now reaches `bin/lwg-toggle.ps1`, `Test-LwgModule`,
  `module_config` via a new `Get-LwgModuleFlag`, `bin/lwg-config.ps1` and `bin/lwg-update.ps1`. Two
  shapes are worth naming: `"require_outside_root": 0` and `""` silently switched OFF
  `mission_drift`'s largest suppressor, so the module warned about files inside the very directory
  the operator had named — **a false positive from the module that is on by default, reachable by
  one typo**; and `lwg-update` read an absent `modules` key as `off` when an unlisted module is
  ENABLED, so its report announced flag moves that were not moves and missed ones that were. Every
  `[bool]` coercion in the repository was re-read; the ones left alone are listed in the commit
  bodies with why. `module_config`'s floor is the caller's `$Default`, not a fixed polarity, because
  a tuning key is not the module's switch.

- **An uncapped payload field could make the status line take a hundred seconds to draw.**
  `lib/supervisor.ps1` wrote every payload-derived field into `health.jsonl` with no cap and no
  redaction; one crafted payload produced a 200,199-character line, measured. Capping is now applied
  in `Write-Record`, the single choke point, through the same `Get-LwgRedacted` the gate has always
  used. The reading side needed a measurement to explain: `Get-Content -Tail`'s cost is superlinear
  in LINE LENGTH, so filtering after the read changed nothing. Against a 300-record log — 19 ms
  clean, 9,032 ms with one 200,000-character record, 80,014 ms with ten. `statusline.ps1` now reads
  through a bounded seek-and-decode window, and **a skipped line renders as a trailing `!`** rather
  than in silence, because a skipped record could have been a fault and a fault dropped on the floor
  renders green. Two more in the same area: rotation **destroyed an archive generation** silently
  when the live file was held in a normal concurrent share mode, and rotation **corrupted non-ASCII**
  because `Get-Content -Tail` with no `-Encoding` decodes ANSI in Windows PowerShell 5.1 while every
  writer here emits UTF-8 — the rotation was corrupting the records it exists to preserve.

- **The `commands` doctor check went unchecked wherever the plugin was installed under `.claude`.**
  It excluded `'*\.claude\*'` by ABSOLUTE path, and this plugin is normally reached through a
  junction under `~\.claude\skills\`, so the exclusion swallowed the whole tree: 194 files, 184 past
  the extension filter, **0 past the exclusion**, reported as `scanned 0 file(s) and found NO
  /lw-gmhh:* reference at all`. Twelve command files were verified by nothing. Run from the
  repository path the same check passed with 88 files — the result depended on where the thing was
  installed, not on what it contained. Both exclusions are now matched **relative** to the plugin
  root.

- **Ten documents described a plugin that no longer exists**, found by the guard above plus two
  adversarial UAT passes. `SECURITY.md` said "It registers no `PreToolUse` hook, so it cannot
  express a denial to the CLI at all" seventy lines after saying "One `PreToolUse` gate does ship" —
  a security policy that understates what ships tells a reporter not to look at the one thing that
  can refuse a call. `README.md` stated its own test coverage two incompatible ways six lines apart.
  `docs/limitations.md` drew a conclusion its own table refutes four lines above. Three pages
  claimed a doctor check count the doctor does not have. Two flat absolutes on the page whose only
  job is to be accurate about absence were false — the gate *does* read `payload.tool_name`, after
  the decision, to word the refusal. Suite counts were then reconciled to the counted tree in a
  second pass. `docs/gates-removed.md` carries the same imprecision and is deliberately **untouched**:
  it is a durable record.

- **Three statements the docs pass found that the CODE contradicted** were fixed in the code rather
  than in the prose: `bin/lwg-doctor.ps1` printed "No advisory in this plugin is exercised by
  anything, anywhere" on every run, and `lib/common.ps1`'s `mission_drift` registry note — the
  single source the docs derive from — said "NO TEST IN THIS REPOSITORY EXERCISES IT". Both now
  state what `tests/stop_behaviour.ps1` covers and keep the claim that still matters: the trigger has
  never been validated against real sessions, and no test can establish that being warned is right.

- **Three test suites wrote into the operator's real state log on every run, under a header promising
  they did not.** `tests/gate_delegate.ps1` and `tests/stop_behaviour.ps1` sandboxed their **child
  processes** and nothing else: the environment windows in `Invoke-Gate`, `Invoke-Toggle` and
  `Invoke-LwgHook` set `CLAUDE_PLUGIN_ROOT` and `CLAUDE_PLUGIN_DATA` around a `cmd /c` spawn and put
  them back the moment it returns, which is correct for a child and covers nothing the suite process
  does itself. Both suites do plenty themselves: each dot-sources `lib/common.ps1` and then hands a
  deliberate non-boolean to `Test-LwgModule` or `Get-LwgModuleFlag` — five such configs in
  `gate_delegate`'s section K, eight calls in `stop_behaviour`'s section A — because the
  ignore-and-log path is exactly what those cases exercise. `Write-LwgInvalidFlag` resolves the state
  directory **at call time**, so with no window open it resolved the **operator's**. Measured, per
  run: `tests/gate_delegate.ps1` appended **5 `ConfigInvalidFlag` records, 1,644 bytes**;
  `tests/stop_behaviour.ps1` appended **8, 2,679 bytes**; `tests/doc_claims.ps1` appended **13,
  4,323 bytes** — which is the other two exactly, because it dot-sources nothing and runs every
  sibling suite as a child, so **all of its leak was theirs**. On a machine whose plugin had not
  written yet, the suites **created** `lw-gmhh.jsonl` rather than growing it. The records themselves
  were correct behaviour; the destination was the defect — and `docs/testing.md`, `docs/faq.md` and
  both suite headers stated "nothing real is touched" while it ran.

  **The sandbox is now installed once for the whole run**, at the top of `MAIN`, and taken down in the
  `finally` so an abort cannot leave it standing over the rest of the shell. The previous values are
  **restored, not removed**: a run under Claude Code inherits real ones, and a suite that deleted them
  would push whatever ran next onto the state-directory glob fallback `lib/common.ps1` spends forty
  lines explaining is not reliable. The memoised resolution is refreshed on the way in and on the way
  out, because setting the variable alone does not move it. **The narrow windows further down are kept
  rather than folded in, for two different reasons.** In `gate_delegate` they are still the only thing
  that points a child at its own fixture root. In `stop_behaviour` — two in section A around the
  `ConfigInvalidFlag` assertions, one across section D's rotation cases — each needs a state directory
  holding *nothing but* the records of the call under test, which a directory shared by the whole run
  would not give it: those are **isolation, not safety**, and saying so is the correction, because one
  of them was written as though it were the thing keeping this suite off the operator's log. It was
  never that for the eight other calls in the same section. All of them now nest inside the outer
  sandbox instead of dropping back to the operator's environment between cases. **Measured after:
  0 bytes from each of the three.**

  **`tests/doc_claims.ps1` gained no sandbox and needs none.** Its zero is its two children's zeroes,
  not an assertion of its own; nothing in that file resolves a state directory in process. And what
  the new cases establish is one clause of the promise, not the promise — see Added.

- **`checklist.json` and `HANDOFF.md` claimed the identity rewrite reached *every ref*, and one ref it
  could not reach still served the old history (2026-07-31, after `v0.3.0` was tagged).** Final
  verification of the release found the overclaim, and the correction deliberately lands **after** the
  tag rather than being folded into it — the release said what it said, and this postdates it. The
  rewrite covered every commit reachable from every branch. What it could not cover was a ref GitHub
  owns rather than this project: such a ref survives any force-push, is not garbage-collected, and its
  ancestry still carried the pre-rewrite author and committer identities. It sat outside the default
  fetch refspec, so a fresh clone showed exactly one identity throughout. The scope word is now
  **branch** wherever the rewrite is claimed, and `P8-visibility` made resolving the exposure a
  **precondition of going public**. That precondition was met — see the paragraph below.

  **RESOLVED 2026-08-28, by destruction rather than by mitigation.** The predecessor repository that
  served the ref was permanently deleted, and a ref cannot outlive the repository serving it.
  Measured on the day: `gh api repos/LEAPWare-Software/LEAPWare-GMHH-private-history` answers
  `404 Not Found`, and `git ls-remote origin` against this repository lists no such ref. **This entry
  no longer names the ref path, its tip commit, or the commit count**, and that removal is
  deliberate: those three were the retrieval instructions rather than the record. A changelog can say
  a history was rebuilt, that one ref was out of the rewrite's reach, and how that ended, without
  republishing the way back to it. **What is NOT claimed here:** that no copy exists off GitHub.
  Anyone who fetched that ref while it was served keeps what they fetched, and nothing in this
  repository can reach or attest to that.

- **`PE-sitrep`'s evidence was a commit-subject match, which any commit mentioning the word satisfies
  (2026-07-31).** The rule required a subject on `main` matching `(?i)sitrep`, so a commit that
  *deleted* the feature would have kept the row green — the same comment-satisfiable shape this
  repository removed from `P6-workflow-guard` on 30 July 2026, missed then because nobody swept for
  the shape after fixing the one instance. It now probes for `commands/sitrep.md` and
  `bin/lwg-sitrep.ps1`, the duplicate `progress` probe is deleted, and the new caveat states that the
  existence of both files is the whole of what the tick proves.

### Not fixed in this release, and named so it is not discovered instead

- **`version-not-a-published-tag` cannot run in CI**, for the reason given above. The rule is stated
  for people in `CONTRIBUTING.md`; the machine catches it only on a clone with tag refs. Since
  3 September 2026 the *agreement* half does run on every push and pull request — see the
  version-declaration guard under Added — so what is left unenforced in CI is the comparison against
  a tag, and only that.
- **The red-first rule itself is still held by a person.** The guard added above holds the shape of
  an annotation and cannot re-run a baseline, so an annotation citing a real commit against a case
  that could never have failed there passes. That is stated in the guard's own header, in
  `CONTRIBUTING.md`, and here, because the gap between "the bookkeeping is checked" and "the rule is
  enforced" is exactly the kind of overstatement this file exists to refuse.
- **The version-identity guard reads declarations, not prose.** Pages that state the current version
  in a sentence or a sample banner are swept by hand; this pass swept `README.md`, `docs/faq.md` and
  `docs/modules.md`. `HANDOFF.md` still says `0.3.0` in that form and is **left alone on purpose** —
  it is titled *Handoff — 31 July 2026 (v0.3.0 release)* and that sentence is a record of the day,
  not a claim about today.
- **The identity exposure this list carried as unresolved was resolved on 2026-08-28**, before this
  section was released, by deleting the predecessor repository that served the ref. The bullet is
  restated rather than deleted so the list does not silently lose an item it once carried; the
  resolution and what it does **not** cover are recorded in full under Fixed above.

## [0.3.0] — 2026-07-31

### Added

- **`.github/dependabot.yml` — the one `.github` file the plan named and the tree did not have
  (2026-07-31).** It declares **exactly one** ecosystem, `github-actions`, and the comment block at
  the top of the file says why that is the whole list rather than an oversight: the only external
  dependency this repository has is `actions/checkout` in `ci.yml`. There is no `package.json`, no
  `requirements.txt`, no `.csproj` — declaring an ecosystem with no manifest behind it would add a
  check that can only ever pass, which is the exact shape of assurance this project refuses
  everywhere else.

- **`docs/monitors-spike.md` — the `monitors/` feasibility spike, run and recorded (2026-07-31).**
  The verdict is **negative**, and the page records it as a completed spike rather than an
  abandoned one.

- **`docs/uat-report.md` — the written user-acceptance record (2026-07-31).** It lands on a later
  commit of this same release pass than the one that writes this entry.

### Changed

- **The declared version is `0.3.0` (2026-07-31).** Five declarations moved together —
  `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `config.json`,
  `lib/common.ps1`'s `$script:LwgVersion`, and the pre-common fallback in `lib/session_start.ps1`
  that names a version when startup fails before the config loads. `README.md` and `docs/faq.md`
  stopped saying *"no release has been tagged"*, because this is the pass in which that stops being
  true.

- **Every commit's author and committer identity was rewritten to
  `LEAPWare-HQ <leapware@outlook.com>`, by explicit owner decision of 2026-07-31.** The plan had
  called for a GitHub `noreply` address; the owner chose this one instead, deliberately and with the
  trade-off named — a real, reachable address rather than a routing alias. `checklist.json`'s
  `P3-identity` rule was rewritten to match: it previously banned a class of consumer domain, which
  the chosen address would have failed forever, and it now **asserts the exact chosen address** on
  the author and the committer of every commit on every ref. **The rule was changed to state the
  decision; the decision was not changed to satisfy the rule.** The rewrite itself lands on a later
  commit of this same pass, so until it does, that row correctly renders NOT STARTED.

### Removed

- **The name of a private sibling project is gone from the tracked tree (2026-07-31).** Eight files
  cited it — two library comments, four documentation pages, `config.json`'s example repo slug and
  `checklist.json`'s own evidence rule. The *incidents* it was cited for are real, are the reason
  more than one rule in this repository exists, and are all still described; only the name is gone,
  replaced by "a private sibling project".

  **This entry deliberately does not quote the literal that was removed**, which is a recorded
  override of this file's own convention of naming exactly what changed. The convention exists so a
  reader can grep for the thing being discussed. Here the literal **is** the thing being removed, so
  honouring the convention would undo the change in the same commit that makes it. Git history
  retains every occurrence; this is a working-tree change and claims nothing more.

### Fixed

- **The commit citations the identity rewrite left dangling (2026-07-31).** Rewriting every author
  and committer gave every commit a new SHA, so the short SHAs cited in `CHANGELOG.md`,
  `docs/gates-removed.md`, `docs/roles.md` and `checklist.json` named objects no ref reaches; each
  was remapped through the rewrite's own commit map the same day, and every replacement prefix was
  verified to resolve against the rewritten history before it was written down.

- **Four `checklist.json` rules could never have passed as written, and one of them proved it by
  spelling its own subject (2026-07-31).** The item requiring that the private sibling project's
  name appear nowhere in the tracked tree **spelled that name in its own `id`, in its title and in
  its `git grep` argument**, so the rule guaranteed its own failure for as long as the manifest was
  tracked. It is renamed `P3-sibling-name` and now greps a bracket-class pattern that carries the
  case-insensitivity without the manifest containing the word.
  `P3-identity` asserted a domain ban the owner's chosen address could not satisfy.
  `PD-proposal` was `manual` because its research lived in an untracked file; `docs/roles.md` now
  carries the contract, so it points at a heading that exists. `P4-monitors` could only ever observe
  a **positive** spike outcome, while the plan explicitly permits a negative one; it now points at
  the page recording the verdict, whichever verdict that is. `P8-visibility` gained a **declared**
  `blocked_reason` and a corrected `blocked_by` id — a dangling blocker id renders UNVERIFIED, which
  is not what "deliberately deferred" should look like.

- **The files still describing last week's CI, update mechanics and gate figures (2026-07-31).**
  `docs/testing.md` still described the `**.md` `paths-ignore` filter that was deleted the same
  week. `commands/update.md` still claimed `git pull` **is** the update mechanism, which is true
  only for the junction route, and still said `tests/` holds a single script with no behavioural
  test. `bin/lwg-update.ps1`'s re-approval notice claimed `plugin.json` names a hooks file.
  `README.md` described a CI job of one job and four steps. The 54-case count and the 585 ms
  delegate-gate figure survived in five pages after the suite grew and the gate was measured again.
  Each was verified stale against the tree before being touched.

### Fixed

- **A documentation-only push to `main` ran no CI at all (2026-07-31).** The `push` trigger in
  `.github/workflows/ci.yml` carried `paths-ignore: ['**.md']`. A path filter sits on the trigger
  rather than on a job, so it skipped the **entire** workflow, not the steps a `.md` change
  plausibly does not affect. The comment justified it with "a README edit changes no gate and no
  JSON", which was true when this job only parsed `.json` and `.ps1` and stopped being true when the
  portability scan landed: **the scan reads every tracked file, `.md` included**, and a
  machine-specific path — an account, a host, a profile path, a hardcoded install location — appears
  in prose more often than in code. The `HANDOFF.md` push of 30 July 2026 was exactly that case and
  went unchecked.

  **The filter is deleted rather than narrowed.** A narrower one would have to stay in step with
  what the steps read, and what the scan reads is the whole tracked tree, so the only set of paths
  that provably reaches no check is the empty set — the same list-drift the `git ls-files`
  enumerations in this workflow already exist to avoid.

  **`pull_request` is unchanged and still carries no path filter**, for the separate reason already
  recorded there: a path filter on `pull_request` makes the job never report a status at all, which
  would leave a README-only PR blocked forever on a required check that never runs. The job's
  display name is likewise untouched — `Fast checks (JSON + PowerShell parse)` is matched by a
  required status check on `main`, and it is left inaccurate on purpose rather than renamed.

- **Ten tracked files were still describing the gateless, one-test state as current, and
  `checklist.json` was still requiring two deleted files (2026-07-30).** Three changes landed in
  parallel that day — `delegate_gate`, the workflow guard, the `lw-class` classifier — and each was
  forbidden from touching `checklist.json` and this file so they could not collide. This is the pass
  that closes what that left open. Nothing here is a new capability; **every single item is a page or
  a rule that had become false**, and they were found by sweeping the tracked tree for the claim
  rather than by working from a list.

  **`docs/gates-removed.md` § *What is true right now* said the opposite of the truth on three
  counts.** It stated that `hooks/hooks.json` has no `PreToolUse` key, that no registry entry is of
  kind `gate`, and that "nothing here blocks anything". All three were false the moment
  `delegate_gate` landed. The section now says one gate exists, ships off, and gives a table of what
  it does and does not do — including that it replaces neither removed gate and that no trip ledger
  came back with it. **The record of why the destructive and secret gates were removed, and what the
  four failed fix attempts taught, is untouched**, because that is the file's whole value; a
  paragraph was added saying that building `delegate_gate` tested **none** of the five lessons, since
  it parses no shell and decides nothing about what is safe.

  **`docs/architecture.md`'s layout block** called `tests/portability_scan.ps1` *"THE ONLY TEST IN THE
  REPO"* and CI *"one job, three steps"*. There are **three** test files and **five** steps. Both
  counts were taken from the tree rather than from the sentence they replaced.

  **`docs/troubleshooting.md`** carried the same *"only test left in the repository"* claim; it now
  names the three and says which one tests behaviour.

  **`.github/PULL_REQUEST_TEMPLATE.md` carried four stale claims, and one of them was actively
  dangerous.** It instructed contributors that *"the hook exits 0 on every path"* and that *"a
  `PreToolUse` denial is expressed in stdout, not in the exit code."* Following that produces a gate
  that **silently fails open** — only `exit 2` blocks a `PreToolUse` call, and `exit 1` is a
  non-blocking error that lets the tool run. It now states the exit-2 contract in full. The template
  also claimed the portability scan was the only test, that a green run establishes no behaviour, and
  that no `PreToolUse` registration exists; all three were corrected, and the verification section
  asks for all three suites rather than one.

  **Six more files were found by sweeping the tree for the claim rather than by working from a
  list**, and each said, in its own words, that this plugin has no gate or no behavioural test.
  `SECURITY.md` twice — *"THERE IS NO GATE TO BYPASS"* and *"no behavioural test harness at all"* —
  which matters more than the others, because a security policy that understates what ships tells a
  reporter not to look at the one thing that can refuse a call. Both now distinguish a **security**
  gate, of which there is none, from `delegate_gate`, which ships, is off by default, reads no path
  or command, and is **not** a security control: a way past it is a public bug report, not a private
  advisory. `.github/ISSUE_TEMPLATE/security.yml` and `config.yml` carried the same sentence and were
  corrected the same way. `CONTRIBUTING.md` told contributors that no behavioural test exists, so
  "tested" can only mean an assertion they wrote — now scoped to *unless you changed that one gate*.
  `commands/doctor.md` and `docs/commands.md` both said *"nothing tests behaviour"*; the true and
  narrower statement is that no **command** does, and `tests/gate_delegate.ps1` is a file CI and a
  human run. `commands/status.md` claimed a gate count of `0` meant "there is nothing left whose
  blocking could be tested" — it means no gate is **live**, which is why `/lw-gmhh:status` prints
  `SHIPPED` and `LIVE` separately in the first place.

  **`checklist.json`, item by item.** `P6-workflow-guard`'s rule was *"`ci.yml` contains the string
  `self-hosted`"* — **a comment satisfied it**, and it would have gone on passing while a self-hosted
  runner was introduced. It now **runs** `tests/workflow_guard.ps1` and requires exit 0, making it the
  only item on the manifest proved by executing anything; the caveat records that exit 2 is an abort
  and that `nonzero_means: unverified` was deliberately *not* set, because that knob would launder a
  real violation into "could not check". `PD-classification` and `PD-doctor-assert` were tightened for
  the same reason — both required the literal `lw-class` to appear in a script, and in both scripts
  every occurrence of it sits in a comment or a display string, so the code could have been deleted
  with the tick intact; they now name the call site and the registered check. `P4-commands` still
  listed `commands/ask.md` and `commands/ask-inline.md`, deleted hours earlier because neither can be
  built, so the row read **12 of 14 present** and rendered IN PROGRESS; both paths are removed and the
  surface is recorded as **twelve**. **That is the only state change in this pass: 21 DONE → 22, 3 in
  progress → 2.** `PD-rename` gained the constraint a sibling flagged — its blocker cleared, but
  striking the four `hq-*` names from `config.json` would unclassify all six of the owner's roles at
  once, because none of their files declares `lw-class` and those files are outside this repository.
  `P2-docs-split` gained a caveat noting its tick rests on six files existing and says nothing about
  whether the pages are good, or true. `P2-limitations`, `PC-ask` and `PC-ask-inline` were checked and
  left alone: the first passes on its own merits and the other two correctly render UNVERIFIED with
  notes that match the tree.

  **`docs/limitations.md`'s checklist tally** was a dated snapshot that the above invalidated. Recounted
  from the file: 20 `file` rules (14 existence-only), 6 `command`, 9 `manual`, 4 `commit`, 1 `ci`; and
  on a current run, 22 DONE of which **11 rest on a file merely existing**. The page's argument is
  unchanged and slightly stronger — twelve of the 22 ticks are now qualified rather than six.

  **Verified:** `bin/lwg-doctor.ps1` `commands` **PASS** (12 commands) and `agent-roles` **PASS**, with
  the pre-existing `statusline` WARN about a drifted installed copy. `tests/workflow_guard.ps1`,
  `tests/portability_scan.ps1` and `tests/gate_delegate.ps1` (54/54) all exit 0. Every tracked `.json`
  and `.ps1` parses, `ci.yml` is valid YAML and its job display name is unchanged, and **every
  internal markdown link and anchor resolves — zero broken.** One claim in the brief did not
  reproduce: `docs/testing.md`'s self-link to `#the-workflow-guard` is **not** dangling — the heading
  exists, and both an independent checker and a second one agree there are no broken anchors anywhere
  in the tree.

### Changed

- **The `hq-*` → `lw-*` role rename is finished, and the four `hq-*` names are out of
  `verification_gate` (2026-07-31).** By owner directive, no agent is named `hq-*` anywhere. The
  four names `hq-implementer`, `hq-scribe`, `hq-healer` and `hq-verifier` are struck from
  `config.json`'s `work_agents` / `verify_agents` and from the matching `-Default` arrays in
  `lib/stop_advisories.ps1`. Every **generic** name stays — `implementer`, `scribe`, `engineer`,
  `healer`, `verifier`, `qa-agent`, `code-review`, `security-adversarial-review` — because those
  have no role file to declare `lw-class` in and the arrays are the only thing that can ever
  classify them.

  **The sequencing is the whole point, and it was not optional.** Until 31 July 2026 those four
  names were load-bearing: the six role files carrying them lived in one operator's
  `~/.claude/agents/`, outside this repository, and declared no `lw-class`. Striking the names first
  would have made all six resolve to the empty string — *no information*, never *not a verifier* —
  so that operator's work **and** their verification would both have stopped reaching the gate,
  silently, while the module still counted toward the SessionStart banner's coverage number. That is
  the founding defect, reintroduced by finishing a rename. So the files were renamed to `lw-*` and
  given an explicit `lw-class` **first** — `work` for implementer, scribe and healer, `verify` for
  verifier, `neutral` for orchestrator and explorer — and the classifier was observed resolving all
  six to those values from the user scope before a single name was removed here.

  **The cross-machine consequence, stated rather than hidden.** Any *other* machine still carrying
  role files under the old spelling loses classification for them the moment it takes this config:
  each resolves to a file with no `lw-class` and to no name in either array, so `verification_gate`
  stops seeing that operator's work and their verification until they repeat the rename. This is
  accepted, not overlooked, and it is recorded at `config.json`'s `$classifier_comment`.

  **The compatibility probes are gone too**, under the same directive: `statusline/statusline.ps1`
  no longer probes `hq-healer.md` beside `lw-healer.md`, and `bin/lwg-setup.ps1` no longer reports
  it. `statusline.ps1`'s orchestrator segment matched `^(hq-)?orchestrator$` and therefore never
  matched the shipped `lw-orchestrator` at all; it now matches `^(lw-)?orchestrator$`. A machine
  holding a healer role only under the old name renders the health segment purple until it renames
  it.

  Prose in `docs/roles.md`, `docs/configuration.md`, `docs/modules.md`, `docs/commands.md`,
  `HANDOFF.md` and the `checklist.json` `PD-rename` caveat is moved to the post-strike truth, with
  the history kept in the past tense rather than deleted. The test fixture in
  `tests/gate_delegate.ps1` that passes `"hq-orchestrator"` as a payload value is deliberately left:
  it simulates a foreign `settings.json` `agent` key that the gate must **not** read, so its value
  is arbitrary by design and naming a live role there would weaken the case.

- **`verification_gate` now reads the `lw-class` key that six shipped roles declared and nothing
  looked at (2026-07-30).** All six roles in `agents/` carried an `lw-class` frontmatter key — `work`,
  `verify` or `neutral` — and that string appeared **nowhere in the code**. The module classified
  agents by matching `agent_type` against two hand-maintained name arrays in `config.json` instead.
  A switch wired to nothing, counted toward the SessionStart banner's coverage number: the founding
  defect, in the plugin that exists to catch it, for the whole life of the key.

  **The classifier.** `lib/common.ps1` gains `Get-LwgAgentClassInfo`, which resolves an observed
  `agent_type` back to the role file it names — splitting on the first colon, walking **project →
  user → plugin** precedence, and putting the plugin scope first for a *namespaced* name because the
  namespace is evidence about which file ran — then reads `lw-class` out of that file's frontmatter.
  **`lw-class` wins wherever it is present**, so a name array can no longer overrule a role's own
  declaration.

  **Resolution failure is NO INFORMATION, never "not a verifier".** This is the load-bearing rule.
  Three ways it fails and all three land in the same place: the role belongs to *another plugin*
  (no foreign install path is derivable from a hook, so those roles are unresolvable by
  construction); the file was deleted, renamed or never existed (a stale record, a built-in like
  `general-purpose`, a typo); or the file resolves and declares no `lw-class`, or a value that is not
  one of the three. Each returns the empty string and falls through exactly as an empty `agent_type`
  does — **neither arming the gate nor disarming it**. Degrading to "not a verifier" would let a
  missing file silence the one warning that exists to notice unverified work; degrading to "work"
  would nag on evidence of nothing. There is deliberately no third option.

  **The two name arrays were KEPT, against the plan, which said to delete them.** They are the only
  thing that classifies a role declaring no class — every role written before the key existed is in
  that case, including the `hq-*` files in one operator's user-scope agents directory — and they
  classify generic names with no role file at all (`implementer`, `engineer`, `qa-agent`,
  `code-review`, `security-adversarial-review`). They are also the code's fallback defaults, because
  `Get-LwgConfig` fails open and a default list naming only one laptop's roles fails open into the
  same blindness. `checklist.json`'s `PD-rename` now records the consequence in full: **striking those
  four `hq-*` names would unclassify all six of that operator's roles at once**, silently, and their
  files are outside this repository so nothing here can add the key to them.

  **`bin/lwg-doctor.ps1` gains the plan's assertion as a ninth check, `agent-roles`.**
  `verification_gate` enabled with **zero** verify-class roles installed is a **FAIL**, because the
  module can then nag and can never clear — it warns when the newest work-agent record is newer than
  the newest verify-agent record, and with no verifier there is never a verify record to be newer
  than. A role counts by its own `lw-class: verify`, **or** by a name in
  `module_config.verification_gate.verify_agents` *that has a file on disk* — a name with no role
  behind it is not counted, because counting it would be the check reporting a list as coverage,
  which is the defect one paragraph up. It is a **lower bound** and says so: other plugins' roles are
  not enumerable from here, so it can produce a spurious FAIL and never a false PASS. Proved by
  negative control — a fixture install missing `agents/lw-verifier.md` fails it and exits 1.

  **Cost, measured, on one machine — read it as that rather than as a property of the module.**
  25 interleaved runs: **+67 ms at the median turn end** (1000 → 1067 ms, 400 records, five distinct
  agent types); 85 ms median over 21 fresh processes for the resolution alone. Per *distinct*
  `agent_type` it is up to three `[IO.File]::Exists` probes and one file read, memoised for the life
  of the process, so a sixth distinct name costs well under a millisecond. Written the obvious way —
  `-split`, `-match`, `Join-Path`, `New-Object` — it cost **119 ms**, nearly all of it PowerShell
  first-use tax rather than file I/O, so the parser uses `IndexOf` and `[IO.Path]::Combine` and the
  sweep caches one verdict per distinct name. **Do not tidy any of that back.**

  **What this does not do.** Nothing in this repository tests `verification_gate`, or any other
  observing module. The behaviour was confirmed by hand: 12 end-to-end cases through the real `Stop`
  hook, covering a namespaced verifier, a namespaced implementer, a bare `hq-verifier`, a bare
  `hq-implementer`, the empty string and an unknown name. Nothing re-runs that.

### Added

- **`tests/workflow_guard.ps1` — a comment-satisfiable evidence rule replaced with one that parses
  (2026-07-30).** The check behind `checklist.json`'s `P6-workflow-guard` was *"`.github/workflows/ci.yml`
  contains the string `self-hosted`"*. **A comment satisfied it.** So did the word appearing inside a
  workflow that genuinely used a self-hosted runner — the rule passed either way, and would have gone
  on reporting a verified protection while the thing it was named after was introduced. That is the
  precise class of control this project exists to refuse, sitting in the project's own evidence
  manifest. There are self-hosted runners registered on the maintainer's machine, so it is also the
  one thing here whose failure lands on real hardware rather than on a disposable VM.

  **It parses; it does not grep.** Every file under `.github/workflows/` is read into a tree — block
  mappings, block sequences, flow collections, quoted scalars, block scalars — and the rules ask
  about *structure*: which key, in which job, holding which value, on which line. Reformatting does
  not get past it; `runs-on:` written as a scalar, a label array or a `group:` mapping is the same
  runner and three different lines of text.

  **Nine rules:** `self-hosted-runner`, `runner-group`, `matrix-self-hosted`, `runner-unresolvable`,
  `pull-request-target`, `secrets-expression`, `secrets-key`, `external-reusable-workflow`, and
  `unparseable`. The last of those **fails rather than passing** — a file that was not checked is not
  a file that passed.

  **The self-hosted rule deliberately does not look for the string `self-hosted`.** It holds
  `runs-on` to a list of known GitHub-hosted labels and reports everything else, because
  `runs-on: office-build-box` is a self-hosted runner that never says so. The accepted cost is that a
  GitHub-hosted *larger* runner, which also carries an org-chosen label, is indistinguishable from
  here and is reported too.

  **Two rules also sweep raw lines, and each sweep is the conservative half.** `${{ secrets.* }}` is
  swept over every physical line **including `run:` script**, because an expression is interpolated
  wherever it is written. `pull_request_target` is swept over YAML values but **not** over `run:`
  script, because only an `on:` block can select a trigger — this workflow's own guard step names the
  token while explaining what it refuses. **Comment text is swept by neither**: a comment cannot run,
  read a secret or pick a runner, and that is exactly the distinction the rule it replaced could not
  make.

  **Its allowlist is empty on purpose** — schema and policy only. `secrets.GITHUB_TOKEN` is
  specifically *not* pre-approved, because an entry written before a concrete step needs it is an
  entry written without a reason.

  **Proved against injected copies in a scratch directory, never in the repository.** Every rule
  fires on a fixture built for it, and all three severity classes fire on a tampered copy of this
  repo's real `ci.yml` at the exact injected lines. Controls pass: a workflow naming `self-hosted`,
  `pull_request_target` and `secrets.GITHUB_TOKEN` in **comments only**, a step-level `uses:`, and a
  local `./.github/workflows/x.yml` call. An empty workflow directory **aborts with exit 2** rather
  than reporting an empty-set pass. The reader was cross-checked against PyYAML on `ci.yml`: same
  keys, same job, same steps, same run-block line counts.

  Wired into `fast-checks` as a **fifth step**, following the pattern of the steps around it — the
  native exit code re-raised explicitly, stderr deliberately not merged with `2>&1`. Exit codes are
  `0`/`1`/`2` with no "passed with a caveat", and **exit 2 is reported as an abort, never as a pass**.
  The job's **display name is deliberately unchanged**, because a required status check on `main` is
  matched by that name. Runs in about a second; no network, no writes.

  **What a green run does not cover:** composite and third-party actions (`uses: owner/repo@ref` runs
  code the guard never reads, and digest pinning does not exist here yet), workflows on other
  branches, and everything a workflow can do that is not one of the nine rules.

- **`docs/limitations.md` and `docs/faq.md` — every honest admission on one page, and the questions
  answered (2026-07-30).**

  `docs/limitations.md` is the consolidated **negative** half: what this plugin does not do, cannot
  do, and does not check. Every fact on it already existed somewhere — in `docs/modules.md`,
  `docs/testing.md`, `docs/gates-removed.md`, `docs/architecture.md`, `config.json`'s comments or the
  README — and each one still belongs next to the thing it is about, so the page **summarises and
  links** rather than keeping a second copy to drift. What it adds is the *count*.

  **Nothing was softened.** It states that `permissions.deny` is empty and no hook inspects a
  command, a path or a credential; that the one gate ships off and is not a security control; that
  four attempts to fix **one** hole opened five bypasses between them while the suite stayed 67/67
  green; that `mission_drift` is on by default with no test of any kind and a trigger never validated
  against real sessions; that `delegate_gate` costs about 330 ms on every `Edit`, `Write`,
  `NotebookEdit` and `Bash` **whether it is switched on or off**; that plan drift is measurable on
  exactly one laptop; and that of the checklist items rendering DONE on that tree, half rested on a
  file existing and nothing else.

  **Two limitations were found while writing it, and are stated rather than filed.** Nothing checks
  that a sentence in `docs/` is still true — the doctor's command-reference check and the portability
  scan are the *whole* of automated prose checking, and neither can see a claim that has gone stale.
  And `Get-LwgRedacted`, the path the secret regex patterns were kept for after `secret_scan` went,
  is exercised by no test.

  `docs/faq.md` answers the questions a new user and a returning owner actually ask, from the tree:
  what it does now, whether it blocks anything, why the gates went, how to install on a second laptop
  and what will not carry over, why the doctor warns about the status line, what a trip was and why
  there are none, how to turn a module off, what UNVERIFIED means, and where the latency comes from.

  Both are linked from `README.md` and `docs/README.md`, and `docs/README`'s *"if you read only one
  thing"* now points at `limitations.md`.

- **`tests/portability_scan.ps1` and `docs/portability.md` — a local environment dependency now fails
  the build instead of only being documented.** This landed earlier than the entries above and was
  never recorded here; it is written up now rather than left as the one control with no changelog
  entry behind it.

  Three shipped defects were one laptop's private facts stated as universal truth: a status line that
  rendered "not installed" forever wherever the layout differed, machine facts injected verbatim into
  every subagent, and a security module whose agent-name arrays matched nothing on a fresh install.
  Each was caught by an **audit** — a person remembering to look. The scan is the same check run by a
  machine on every build, and `docs/portability.md` is the mandate it enforces.

  It scans every tracked file for machine-specific paths, usernames, hostnames and hardcoded
  interpreter or install locations, under **8 rules**. It enumerates with `git ls-files`, because a
  hardcoded file list is the exact defect the scan exists to prevent. Exit codes are `0`/`1`/`2` with
  deliberately no "passed with a caveat", and an enumeration returning zero files is an **abort**,
  never an empty-set pass.

  Its **9 allowlist entries each carry a stated reason**, and an entry that excuses nothing on the
  current tree prints as `(unused on this tree - defensive)` rather than being silently kept. The
  `changelog-removed-literal` entry — which lets an entry here quote a removed literal, since quoting
  it is what makes the entry evidence of anything — deliberately does **not** cover an owner username
  or a hostname, and requires a backtick, so it reaches code spans rather than the whole file.

  **What it proves about this plugin's behaviour: nothing.** A file can be perfectly portable and
  completely broken.

### Added

- **`delegate_gate` — one `PreToolUse` gate is added back, and it ships switched off
  (2026-07-30), by an explicit owner decision.** Hours earlier the same day both existing gates were
  removed and `hooks/hooks.json` lost its `PreToolUse` key entirely. This adds one back, and only
  one: of the three unenforced preference switches on the plan, research established that `ask`
  could only ever be partial and `ask-inline` was structurally impossible, while **`delegate` was
  fully buildable**. It was built.

  **What it does.** `lib/gate_delegate.ps1`, registered on `PreToolUse` with matcher
  `Edit|Write|NotebookEdit|Bash`. One rule, no exceptions: *when `interaction.delegate` is on, refuse
  those four tools for any call that did not come from a subagent.* When the switch is off it does
  nothing at all. It **ships off** — turning a blocking gate on by default is the opposite of what
  this plugin argues for everywhere else, so arming it is the operator's choice.

  **It decides on the presence of `agent_id`, and must never test `agent_type`.** This is the single
  most important line in this entry. Both fields are optional on the base hook input and only
  `agent_id` is populated inside a subagent. A `settings.json` `agent` key names the role the *main
  conversation* runs as, so on such a machine the main thread carries a **non-empty `agent_type`** —
  and a gate matching on that would classify the main thread as a subagent, allow every call it
  exists to refuse, and report itself as a live gate the whole time. That is the founding defect this
  plugin exists to catch, one field name away. `tests/gate_delegate.ps1` asserts it on the source
  *and* behaviourally, with a payload carrying `agent_type` and no `agent_id`.

  **How it blocks: stderr plus `exit 2`.** Only exit 2 blocks a `PreToolUse` call; **exit 1 is a
  non-blocking error and the tool runs anyway**, so a gate that exits 1 has silently failed open. An
  exit code cannot be malformed, which is why it carries the weight. The
  `permissionDecision: "deny"` envelope is written to stdout as well — this build ignores stdout
  under a nonzero exit, so it is redundant here, and it is emitted because the two channels fail open
  in *different* circumstances and emitting both can never turn a deny into an allow. A `PreToolUse`
  deny is honoured **even under `permissions.defaultMode: "bypassPermissions"`**, so for an operator
  in that mode this is a stronger layer than a `permissions.deny` rule.

  **It carries no exemption, no allowlist and no safety determination** — the rule
  `docs/gates-removed.md` draws from four failed fix attempts that produced five bypasses between
  them, every one from an exemption. It does not read the path, the command, the content, or even
  `tool_name`: the matcher in `hooks/hooks.json` is the single place the gated tool list lives, so
  widening it refuses *more* (safe, loud) where a stale second copy inside the script would refuse
  *less* (silent, a hole).

  **Failing safe is two opposite directions here, on purpose.** Unreadable stdin **denies** — there
  is then no `agent_id`, and input the gate could not read is not evidence a subagent made the call.
  An unreadable or absent `config.json` **allows** — the switch is off by default, a config nobody
  can read is no evidence it was turned on, and the alternative makes a bad config a *lockout* on the
  very file that has to be fixed.

  **The over-blocking it accepts, stated rather than left to be found:** with the gate on,
  `/lw-gmhh:delegate off` does **not** work from the main thread, because that command runs through
  `Bash`. There is deliberately no exemption for it — an exemption for "the command that turns me
  off" is a named bypass, and one named bypass is an argument about which others deserve one. The
  deny text names both ways out: have a subagent run the command, or edit `interaction.delegate` by
  hand.

  **One gate, one switch.** The registry entry declares
  `switch = @{ block = 'interaction'; key = 'delegate'; default = $false }` rather than taking a
  `modules` flag, so `interaction.delegate` is the only thing that arms it. A second flag would let
  `/lw-gmhh:delegate on` succeed while the gate stayed silent — a switch wired to nothing.
  `Test-LwgModule` resolves a declared switch through the new `Test-LwgFlag`, so the gate, the
  banner, `/lw-gmhh:status` and the per-repo override machinery all read it the same way. Because the
  flag sits outside `modules` it does **not** inherit `Get-LwgConfig`'s fail-**open** polarity: an
  unreadable config leaves the gate off.

  **Counts.** 9 modules → **10**; 10 implemented; **9 active, 1 built-but-off**; gates **1 shipped,
  0 live**. The banner reads `9/10 modules active (1 off) · 0 gates · observe-only`, and `enforcing`
  and `partial` are **reachable words again** after a few hours of being unreachable.
  `/lw-gmhh:status` now reports `SHIPPED` and `LIVE` as separate numbers with a `GATES` block naming
  each switch, because collapsing them either claims protection that is switched off or hides a
  capability the operator was never told they have. The model-visible context now says "no gate is
  live" rather than "no gate exists", because one does.

  **The trip ledger did not come back with it.** A denial is a `GateDeny` line in `lw-gmhh.jsonl` and
  nothing tracks it as an open item. `docs/gates-removed.md` is unchanged and still describes what an
  indicator would have to rebuild, in what order.

  **Two commands were taught the new shape rather than left to be wrong.** `/lw-gmhh:config`
  enumerates the registry and writes `modules.<name>`, so it would have offered `delegate_gate` and
  written a flag nothing reads; it now lists the module with its real state and **refuses** the
  write, naming `/lw-gmhh:delegate`. `bin/lwg-doctor.ps1`'s `config-registry` check excludes
  own-switch entries from the `modules` parity rule and instead asserts the declared key **exists**,
  and fails if both spellings are present — strictly more checking than before, not less.

  **Tested.** `tests/gate_delegate.ps1`, **54 cases**, wired into the `fast-checks` CI job as a
  fourth step. Each case runs `type payload.json | powershell -File lib\gate_delegate.ps1` through a
  `.cmd` file, because a PowerShell object pipe never reaches `[Console]::In`. Nothing real is
  touched: `CLAUDE_PLUGIN_ROOT` and `CLAUDE_PLUGIN_DATA` point at a throwaway directory holding a
  copy of the repository's own `config.json`, and the flip to `delegate: true` asserts it replaced
  exactly one occurrence, so a changed spelling aborts rather than producing cases that pass by
  agreeing with the wrong answer. Per `CONTRIBUTING.md`, the suite was confirmed to **fail** against
  a deliberately broken gate before being kept — three ways: `agent_type` for `agent_id` (3 failures,
  including the behavioural trap case), `exit 1` for `exit 2` (17 failures, each naming the silent
  fail-open), and a matcher narrowed to drop `Bash` (1 failure). The CI job's **display name is
  deliberately unchanged**, because a required status check on `main` is matched by that name.

  Read `tests/gate_delegate.ps1`'s header before treating a green run as assurance: the last gate's
  suite was 67/67 green while five bypasses were open.

### Removed

- **`lw-gmhh:ask` and `lw-gmhh:ask-inline` are gone (2026-07-30), by an explicit owner decision, and
  not because they were unfinished — because neither can be built.** Both had been **on by default
  since they shipped, enforcing nothing**, which is precisely the switch-wired-to-nothing this plugin
  exists to catch, shipped twice by the plugin that exists to catch it. (Both names are written here
  without a leading slash, as everywhere else in this repo: `bin/lwg-doctor.ps1`'s `commands` check
  fails the build on a `/lw-gmhh:<name>` reference with no command file behind it, and it caught this
  entry when it was first written with them.)

  `ask` would have needed a `Stop` hook refusing to end a turn while an unanswered decision was
  outstanding. A `Stop` hook **can** block turn-end — but by the time it fires the prose has already
  been printed, so it cannot stop a decision being scrolled past, which is the entire point; and it
  has no way to detect a question that *should* have been asked and was not. The half that mattered
  is unreachable at every hook event.

  `ask-inline` would have needed something that counts and merges the questions asked in a turn.
  Nothing can merge them after the fact, and the batching has to happen before the first question,
  where no hook sits. The "4 questions, 2–4 options" shape was never a rule this plugin applied
  either: it is a platform limit on the question tool, enforced there, and a flag taking credit for
  it counts someone else's constraint as its own coverage.

  **Removed:** `commands/ask.md`, `commands/ask-inline.md`, the `interaction.ask` and
  `interaction.ask_inline` keys, both entries in `$script:LwgFlags` and both names from the `-Flag`
  `ValidateSet` in `bin/lwg-toggle.ps1`, and every reference across `README.md`, `docs/commands.md`,
  `docs/configuration.md`, `bin/lwg-sitrep.ps1` and `HANDOFF.md`. The command surface is **twelve**,
  down from fourteen.

  **The reasoning was kept, in `config.json` under `$removed_keys_comment` and in
  `docs/commands.md`,** so nobody re-attempts either. The `$key_naming_comment` explaining that the
  command was `ask-inline` while the key was `ask_inline` went with them; that trap no longer exists.
  `checklist.json`'s `PC-ask` and `PC-ask-inline` now render **UNVERIFIED** with a note saying the
  work was never done and cannot be, rather than being repointed at a surviving file to keep a tick.

  `bin/lwg-toggle.ps1` now prints an `ENFORCED` block for a wired flag and `NOT WIRED` for an unwired
  one, chosen by which key the flag carries, with no default branch — a heading is the first thing
  read, and a wired switch printing `NOT WIRED` would be the loudest lie the command could tell.

### Changed

- **`lw-gmhh:brief` and `lw-gmhh:verbose` are now one command, `/lw-gmhh:verbosity` (2026-07-30), by
  an explicit owner decision.** They were always two commands over **one** key —
  `output_style.verbosity`, which holds exactly one of `brief`, `default` or `verbose` — and two
  switches over a three-value setting describe a model that is not there. The tell was in the output:
  under the old pair, `brief off` while the key read `verbose` correctly wrote **nothing at all**,
  and `bin/lwg-toggle.ps1` had to print a paragraph explaining that on every single run. The level is
  now set by name, and the name is the value written.

  **Nothing about the stored value changed.** `output_style.verbosity` still holds one of the same
  three strings, `config.json`'s default is still `"default"`, and a config written by the old pair
  is read identically by the new command. This is a command-surface change, not a schema change, and
  no migration is needed.

  **`/lw-gmhh:plain` was explicitly kept as its own command.** It is a genuinely independent axis —
  jargon, not length — and folding it into a length setting would have been the same category error
  in the other direction. The command surface is **fourteen**, down from fifteen.

  **Files.** `commands/brief.md` and `commands/verbose.md` removed; `commands/verbosity.md` added.
  In `bin/lwg-toggle.ps1` the `brief` and `verbose` entries in `$script:LwgFlags` collapse into one
  `verbosity` entry whose axis is `level` rather than `bool`: it carries the three level names and
  the sentence printed for each, and `$script:LwgVerbosityValues` is now **derived** from that table
  rather than written out a second time, so the accepted arguments, the accepted file values and the
  levels the usage text lists cannot drift apart. The `$skipWrite` branch is gone with the case that
  needed it — under a level there is no argument that has to be refused a write.

  **What was deliberately preserved.** The `OBSOLETE KEY` warning for a stale `output_style.brief`
  boolean still fires at both scopes, still names the full path, and still **does not rewrite it**;
  only the remedy sentence changed, to name the new command. The `UNRECOGNISED VALUE` block, the
  surgical text-editing of `config.json`, the parse-before-write rule, the read-back-from-disk check
  and the `0`/`2`/`3` exit contract are all unchanged.

  **No `output-styles/` file was orphaned.** Verbosity × plain is still six combinations mapping onto
  the same five files plus the built-in Default; all five are still reachable and all five stay.

  **Historical references were de-slashed, not rewritten.** Five `lw-gmhh:brief` and
  `lw-gmhh:verbose` mentions in entries below lost their leading slash — and this entry writes them
  the same way, for the same reason. `bin/lwg-doctor.ps1`'s
  `commands` check fails on a `/lw-gmhh:<name>` reference with no `commands/<name>.md` behind it —
  correctly, since such a reference is a signpost to nothing — and the record of what those commands
  were is worth more than the slash. It is the same convention the doctor's own source comment
  already used for the deleted `tripped` command.

  **`checklist.json` still names both.** `PB-verbose`'s title and evidence paths, and `PA-commands`'s
  evidence list, point at `commands/verbose.md` and `commands/brief.md`, and `PB-verbose` carries a
  slash-prefixed `lw-gmhh:verbose` reference. That file was out of scope here and was not touched,
  so the doctor's `commands` check **fails** until it is updated. See the note under *Known* below.

### Fixed

- **`checklist.json` updated to match the `verbosity` merge (2026-07-30), closing the gap left
  above.** `PB-verbose`'s title and `P4-commands`'s prose now read the de-slashed `lw-gmhh:verbose`
  and `lw-gmhh:brief`, matching the convention already used for the deleted `tripped` command.
  `PB-verbose` and `P4-commands`'s evidence paths now point at `commands/verbosity.md` instead of
  the removed `commands/verbose.md` and `commands/brief.md`, and the command-surface count in
  `P4-commands`'s caveat reads fourteen. Both items' caveat text now records that `brief` and
  `verbose` were merged into `verbosity` on 2026-07-30. `bin/lwg-doctor.ps1`'s `commands` check now
  passes; `statusline` remains the pre-existing `WARN` about a drifted installed copy.

### Removed

- **The `tripped` command, the whole trip ledger, and the open trips themselves (2026-07-30), by an
  explicit owner decision.** The gates went earlier the same day, which left the ledger machinery
  standing as a reader for per-session files already on disk. That reprieve is over: the readers, the
  format, the indicator and the data are all gone.

  **Code removed.** `lib/trips.ps1` (the ledger format and every verb over it), `lib/ack_trip.ps1`
  (the acknowledge path), `bin/lwg-tripped.ps1` and `commands/tripped.md` (the operator's only route
  in), the ledger-open branch in `lib/session_start.ps1`, and the turn-end trip sweep in
  `lib/stop_advisories.ps1` together with the `$onTrips` flag that gated it. The command surface is
  **fifteen**, down from sixteen.

  **The `GM` status-line segment went with it.** `GmState`, `GmTrips`, `GmSessionKey`, `GmSeg`, the
  outstanding-trip advisory row and the `Ago` helper whose only caller it was are all deleted from
  `statusline/statusline.ps1`. `GmConfig` survives because the threshold block reads it. The
  reasoning is on the record: `GmState` returned early on *no ledger found*, so with no ledger
  anywhere on disk the only reachable state was `none` and the only reachable glyph was the dim
  `GM-`. An indicator that can render exactly one value carries no information, which is the same
  defect — reached from the other side — as the 25-line log tail `GM` was rebuilt to escape. Row 1 is
  now `model  HH  ORC  ctx  5h  7d  #branch  PR#  owner/repo`.

  **Data removed, after being backed up and hash-verified.** Twelve `trips-<sessionkey>.json` files
  in the live state directory, 147,287,434 bytes in total, holding **64 uncleared trips** between
  them. Every one was copied to `trips-backup-20260730/` in the same directory and verified
  byte-for-byte by SHA-256 before the original was deleted by explicit individual path. Nothing else
  in that directory was touched: `health.jsonl`, `lw-gmhh.jsonl`, the `advisory-*`, `edits-*`,
  `rule_stats.json`, `context_windows.json`, `sitrep.state.json` and both probes are unchanged.

  **What survives, and what it is not.** `lw-gmhh.jsonl` is untouched, so historical `GateDeny`
  records remain and `/lw-gmhh:sitrep` still counts them — but they moved from *NEEDS AN OPERATOR
  DECISION* to `GOVERNANCE`, because nothing can add to that set and nothing can clear it:
  `GateCleared` was only ever written by the sweep. Reporting an unclosable count as a decision
  awaiting the operator would have been a permanently red indicator, which is the failure mode this
  project keeps arguing against. `rule_stats.json` is likewise now historical; nothing writes it.

  **`docs/gates-removed.md` was corrected, not just appended to.** It previously listed the ledger
  under *what was kept so a gate can be re-added*. That promise is void, and the page now says so
  under **The trip ledger was NOT kept — a gate has to rebuild it**, with a table of exactly what
  must come back and the order to build it in: format, then acknowledge path, then the writer on the
  deny branch, then the turn-end sweep, and the indicator **last** — an indicator shipped before the
  acknowledge path is a red glyph with no route out. The design itself is preserved in past tense at
  `docs/architecture.md` § *The trip ledger — REMOVED, and recorded here as a design*, including the
  close-class table and the rule that governed every auto-close: a trip could close only on a
  verified fact about the world, **never** because time had passed. Owner intent is unchanged — gate
  capability stays re-addable — and these two pages are what make that possible.

  **Checklist rows were updated to reflect reality, not deleted to look clean.** `PA-tripped-cmd`
  becomes a `manual` row recording that the command *was built and did pass* before being removed,
  and is deliberately left unverified rather than pointed at a substitute. `PA-proposal` is marked
  moot. `P4-commands` drops `commands/tripped.md` from its evidence list — the second name to leave
  that list after `commands/verify.md` — with the caveat explaining that a deleted-on-purpose file
  failing an evidence probe reports as unfinished work, which is the opposite of what happened.

  **Verified:** `bin/lwg-doctor.ps1` reports `commands` **PASS** — 15 commands, each with its backing
  script, 15 distinct references across 78 scanned files, all declared — so no signpost to the
  removed `lw-gmhh:tripped` survives anywhere. (Written without its leading slash deliberately: that
  check scans this file too, and spelling it live here would fail the check on its own evidence.) `sessionstart` FAIL and `statusline` WARN are pre-existing and
  unrelated. `tests/portability_scan.ps1` exits 0 over 83 tracked files. All 5 tracked `.json` parse,
  all 21 tracked `.ps1` parse, `.github/workflows/ci.yml` and all four issue templates are valid
  YAML, and all **248** internal markdown links resolve including anchors. The status line renders
  and exits 0. `lib/session_start.ps1` and `lib/stop_advisories.ps1` were run against real payloads
  and exit 0; the SessionStart run created **no** `trips-*.json`, confirming the branch is gone.

### Changed

- **`mission_drift` is ON by default (2026-07-30), by explicit owner decision, and the tradeoff is
  recorded rather than glossed.** `config.json` ships `"mission_drift": true`; `$status.default_off`
  is now empty and `$status.$default_off_comment` has been replaced by `$status.$mission_drift_comment`,
  which states what enabling it accepts. Nothing else was needed — the mission is read out of the
  transcript inside the existing `Stop` process, so there is no new hook and no extra process.

  **What it accepts, in the same words the config and the docs now use.** The module shipped `false`
  because its trigger **could not be validated against real sessions**, and nothing has validated it
  since; **no test in this repository exercises it**, so the legitimate-pivot path has been read and
  never run; it costs about **137 ms at every turn end** where it previously cost nothing (one
  development machine's median, 122–169 ms, scaling with transcript growth and disk speed); and one
  false-positive class survives — a redirection phrased with no concrete noun at all (*"now go fix
  the other repo"*) followed by edits in a tree nobody named. That class is now live for every
  install. `docs/modules.md`, `docs/testing.md`, `docs/architecture.md`, `README.md` and the module's
  own registry note say so in those terms; the recommendation, had one been asked for, was to
  validate the trigger first, and the decision was to enable it regardless, which is why the cost is
  written down where an operator hitting it will find it.

  **Verified by running it, not by trusting the flag.** With a constructed transcript naming
  `lib/stop_advisories.ps1` and an edit list of three `.py` files under an unrelated root, the `Stop`
  handler emitted `LW-GMHH mission: all 3 file(s) changed this session … match nothing named in any
  prompt this session (you named: lib, stop_advisories, stop_advisories.ps1)` and wrote a
  `MissionDrift` record carrying `unaccounted:3, accounted:0, path_anchors:3`. The negative control —
  the same three files, with a prompt naming that tree — produced **no** mission advisory, so the
  trigger discriminates rather than firing on any edit.

- **The banner drops its parenthetical when there is nothing to caveat.** With `0 planned` and
  `0 off` the `SessionStart` banner now reads `9/9 modules active · 0 gates · observe-only` rather
  than `9/9 modules active (0 planned)`; every non-zero case still prints, so `mission_drift: false`
  gives `8/9 modules active (1 off)`. `bin/lwg-status.ps1` likewise prints one clause — *0 planned
  and 0 switched off - every module in the registry is built and enabled* — instead of three zeroes.
  A caveat-shaped phrase with no caveat behind it is noise standing where a real caveat used to be.

### Removed

- **`ratelimit_escalation` and `cost_tracking` — the two unbuildable placeholders — removed
  (2026-07-30), and the REASON KEPT.** An explicit decision of the repository owner. Both were
  carried as `planned` entries with `blocked = $true`; neither can ever be built, because the data
  each needs is assembled in exactly one place in the claude-code 2.1.220 binary — the status-line
  input builder — and no hook event carries it.

  Removed: their flags in `config.json`'s `modules` block; their two names from `$status.planned`,
  which is now empty; their entries in `$LwgModuleRegistry` in `lib/common.ps1`. The module total
  goes from 11 to 9, and with `mission_drift` on the counts are **9 modules, 9 implemented, 9 active,
  0 planned, 0 blocked, 0 gates**.

  **Deleting the placeholder is not deleting the record.** `$status.$blocked_comment` became
  `$status.$removed_blocked_comment`, and the full evidence — the base hook input schema, the
  field-by-field reachability table, why there is no on-disk cache to read instead, and what would
  unblock them — moved to `docs/modules.md` under **Attempted and blocked: `ratelimit_escalation`
  and `cost_tracking`**, with instructions for anyone re-attempting one: verify against the *current*
  CLI build first, then declare the module in the registry and `config.json` together. Every
  reference across `README.md`, `CONTRIBUTING.md`, `docs/configuration.md`, `docs/architecture.md`,
  `bin/lwg-config.ps1` and the feature-request issue template was repointed at that section rather
  than dropped.

  **The `blocked` mechanism itself is kept.** The field, `Get-LwgBlockedModules`, and every reader of
  it stay, so the next module that has to be declared unbuildable rather than unbuilt does not have
  to reinvent the distinction. No entry carries `blocked = $true` today, and the registry comment
  says so.

- **`secret_scan` — the last gate — removed in full (2026-07-30). THIS PLUGIN NO LONGER BLOCKS
  ANYTHING.** An explicit decision of the repository owner, taken after the `destructive_gate`
  removal recorded below and on the same day, and recorded here rather than left to be inferred from
  an absence.

  Deleted: `lib/gate_write.ps1`; its `PreToolUse` registration on `Write|Edit|NotebookEdit` in
  `hooks/hooks.json` — which was the **last `PreToolUse` hook of any kind**, so that key no longer
  exists in the file; the module's entries in `config.json`'s `modules`/`implemented` and in
  `$LwgModuleRegistry` in `lib/common.ps1`; `docs/gates.md` in its entirety, there being no gate to
  document; `tests/deny_parity.ps1` with `tests/fixtures/deny_canonical.txt` and
  `tests/fixtures/settings_merge_input.json`; and the `permissions.deny parity` step in
  `.github/workflows/ci.yml`.

  **The deny table went with it, and is now empty.** `bin/lwg-setup.ps1` lost the `secret-paths`
  (30 rules) and `secret-reads` (18 rules) groups — the last 48 of the original 181. `Get-DenyGroups`
  returns an empty table, so `/lw-gmhh:setup` installs **no `permissions.deny` rules at all**.
  `-SecretGate` joins `-DestructiveGate` as a parameter that is still accepted, selects nothing at
  either layer, and says so wherever it is printed.

  **What this costs, stated rather than glossed:**

  - No hook inspects the path being written or the bytes being written. A credential can be written
    to `.env`, a `*.pem` or anything else with nothing here noticing beforehand.
  - There is no config layer either. `permissions.deny` was the one layer that could not fail open,
    because the CLI evaluates it itself before any hook runs, and this plugin now writes none of it.
  - Taken with the entry below: **no gate, no deny rule, no `PreToolUse` hook.** Nothing this plugin
    ships can refuse, delay or even see a tool call before it happens.
  - Deleting `tests/deny_parity.ps1` also removed the **only** coverage of the installer's merge
    behaviour — that it preserves an operator's own deny rules and their order, leaves unrelated
    top-level keys byte-identical, takes exactly one backup, is idempotent, and rolls back. Those
    properties still matter for the `statusLine`, hooks and agent-role sections setup does write, and
    nothing tests them now. That is outstanding work, not a decision.
  - `tests/portability_scan.ps1` is the only test left in the repository, and it tests no behaviour.
    CI is one job with three steps: JSON validity, PowerShell parse, portability scan.

    > **Superseded later the same day, and both sentences are now false.** `tests/gate_delegate.ps1`
    > arrived with `delegate_gate` and `tests/workflow_guard.ps1` with the guard — see the entries at
    > the top of this block. There are **three** test files and the job has **five** steps. The claim
    > this bullet was making still stands where it matters: *nothing replaced what the deleted suites
    > covered*, and the one suite that tests behaviour tests a gate that ships switched off.

  **What was deliberately kept, and why none of it is protection:**

  - `lib/trips.ps1`, `bin/lwg-tripped.ps1`, `commands/tripped.md` and `lib/ack_trip.ps1` — **readers
    for historical ledgers.** No gate can write a trip, so no new ledger is created and no new trip
    can occur; but per-session ledgers written before the removal are still on disk and some still
    hold **open** trips. These are the only things that can read, classify, close or acknowledge one.
    Deleting them would strand real outstanding refusals permanently unreadable.
  - The status line's `GM` segment, for the same reason. For any session started after the removal it
    finds no ledger and renders dim — "nothing was checked" — which is now permanently correct.
  - The trip auto-close sweep in `lib/stop_advisories.ps1`, **re-gated**: it ran on the `secret_scan`
    flag and now runs only when a ledger file already exists for the session, so historical open
    trips can still reach a close and a session with no ledger pays one `Test-Path`.
  - The secret regex patterns in `lib/common.ps1` — now used for **log redaction only**
    (`Get-LwgRedacted`). Nothing matches them against a pending write. A plugin that records a
    credential in its own audit trail has moved the secret rather than contained it, and that hazard
    is unaffected by the loss of the gate.
  - Every deny family in `bin/lwg-uninstall.ps1`'s `Test-MirroredDeny`. It is now the only code in
    the repository that knows what the original 181 rules looked like, and a machine installed before
    these removals still has them; an uninstaller that could not see them would report a clean
    removal while leaving them behind.

  **Banner arithmetic changes again: 11 modules, 9 implemented, 8 active, 0 gates.** The session mode
  is now `observe-only` — in the ladder in `Get-LwgSessionMode`, a gate count of zero is tested
  before the `partial` case, so `mission_drift` shipping off no longer determines the word and
  neither `partial` nor `enforcing` is reachable. The banner reads
  `LW-GMHH v0.2.0 · 8/11 modules active (2 planned, 1 off) · 0 gates · observe-only`.

  > **The arithmetic was superseded later the same day** by the two entries at the top of this block:
  > the two blocked placeholders were removed and `mission_drift` was switched on, giving
  > **9 modules, 9 implemented, 9 active, 0 gates** and a banner of
  > `LW-GMHH v0.2.0 · 9/9 modules active · 0 gates · observe-only`. The gate count, and the mode word
  > that follows from it, are unchanged and remain the point of this entry.

  A machine set up before 2026-07-30 still carries the old rules in its own `settings.json` and the
  CLI still evaluates them; nothing here renews them.

  The removed code is recoverable from git history.

- **`destructive_gate` — the destructive-command gate — removed in full (2026-07-30).** An explicit
  decision of the repository owner, recorded here rather than left to be inferred from an absence.
  Deleted: `lib/gate_bash.ps1`; its `PreToolUse` registration on `Bash|PowerShell` in
  `hooks/hooks.json`; `tests/gate_regression.ps1` (233 cases); `bin/lwg-verify.ps1`;
  `commands/verify.md`; the `gate-regression` job in `.github/workflows/ci.yml`; and the module's
  entries in `config.json`'s registry and `$LwgModuleRegistry` in `lib/common.ps1`.

  The `.git`-internals path rule was also removed from `lib/gate_write.ps1`. It was a
  destructive-action rule carried on the `destructive_gate` flag, not a credential rule, and it went
  with its module.

  **What this costs, stated rather than glossed:**

  - Nothing in this plugin inspects a shell command. There is no hook on `Bash` or `PowerShell`.
  - No hook refuses a write inside `.git/`. `[core] sshCommand` there is arbitrary code execution on
    the next git command, and only the `git-internals` group in `permissions.deny` now stands in
    front of it.
  - The bypass classes the hook closed **in general** — line continuations, wrapper commands like
    `eval`, abbreviated git flags, here-document bodies, unbalanced quotes, computed program names —
    are closed by nothing. `permissions.deny` is literal-glob matching and can only catch enumerated
    spellings.
  - This repo has **no behavioural test of any kind**. The 233-case suite was the only one, so
    `lib/gate_write.ps1` is now covered by review alone, and the SessionStart banner — asserted by a
    case in that suite — is asserted by nothing. `checklist.json` records both as regressions rather
    than dropping the items.
  - CI is one job. Any branch-protection rule still requiring the `gate-regression` context will
    block every merge, because that job can never report again.

  **What was deliberately kept — SUPERSEDED the same day; see the `secret_scan` entry above, which
  removed all of it:** `secret_scan` and `lib/gate_write.ps1` in full, including its
  `PreToolUse` registration, its `..`/trailing-dot/8.3 path canonicalisation and its credential-path
  rules, which are now carried on the `secret_scan` flag where they belong — the installer's own
  `secret-paths` deny group has always classed `.env`, `*.pem`, `id_rsa*` and `ENV~1` as secret-gate
  business. `lib/trips.ps1` and the trip ledger are kept because `secret_scan` writes to them; the
  rule names belonging to the removed gate are kept in its severity tables so that a ledger written
  before this change still sweeps correctly, and each is labelled as such.

  **The deny table went too, in the companion commit `5803a7f`.** `bin/lwg-setup.ps1` lost the
  `git-destructive`, `filesystem-destructive`, `github-destructive` and `git-internals` groups — 133
  of 181 rules — leaving the 48 of `secret-paths` and `secret-reads`, and the fixture was
  regenerated to match. So there is no hook layer AND no config layer for destructive commands.
  `-DestructiveGate` is still accepted by the installer, selects no group, and now keeps no hook
  either; it is entirely inert and every place that prints it says so.

  Banner arithmetic changes with it: **12 modules, 10 implemented, 9 active, 1 gate.** (Superseded
  hours later by the `secret_scan` removal above: 11 modules, 9 implemented, 8 active, 0 gates.)

  The removed code is recoverable from git history.

### Added

- **`docs/gates-removed.md` — the durable record that gates were removed deliberately, and what a
  future attempt must do differently.** The owner intends blocking capability to be re-addable, and
  the code that would have taught these lessons is deleted, so the lessons are written down instead.

  It records what was kept so a gate can be re-added — `kind = 'gate'` is still expressible in
  `$LwgModuleRegistry` and `$script:LwgGates` is still derived by a loop, the mode ladder is still
  guarded by the live gate count, `lib/trips.ps1` and the trip reader are intact, the ledger-open
  branch in `lib/session_start.ps1` is guarded by that count, and `bin/lwg-uninstall.ps1` still knows
  all 181 deny rules — and then the four failed attempts to close **one** hole in `destructive_gate`:
  `498762d` (reverted `fb426d1`), `8b19975` (reverted `083116e`), `95b54cb`, `804c7cc`.

  The five lessons, which are the point of the page: **every added cleverness opened a hole and the
  isolation itself opened none** — the two reverted attempts carried the same correct here-doc
  isolation plus a "provably cannot run" exemption, and all five bypasses came out of the exemption;
  **a change that can only add coverage is safe by construction**, which is why the appending rescan
  was accepted; **the suite never once caught a bypass** — 67/67 green while five were open, and every
  hole in the record was found by someone trying to break the gate; **assertions about the shell must
  be executed, not recalled**; and **a parser that models a shell keeps losing to the shell**. Seven
  rules for a future attempt follow, including *never add an exemption, an allowlist or a safety
  determination*, *budget for an independent break-attempt rather than for tests*, and the test-safety
  standing order that outlived the suite carrying it.

  Linked from `README.md`, `docs/README.md`, `docs/modules.md`, `CONTRIBUTING.md` and
  `config.json`'s `$status.$gates_comment`.

- **`tests/deny_parity.ps1` and `tests/fixtures/deny_canonical.txt` — the `permissions.deny` rule
  table is now checked on every build.**

  > **ADDED AND THEN DELETED WITHIN THE SAME UNRELEASED BLOCK, on 2026-07-30.** Both files, the
  > `settings_merge_input.json` fixture and the CI step were removed with `secret_scan` — see the
  > entry above. With `Get-DenyGroups` empty there is no table to hold to a fixture, and a step
  > reporting `deny parity: PASS` over an empty set would be exactly the false assurance this
  > repository exists to refuse. The entry is kept rather than deleted because the reasoning below —
  > in particular the counting error, and the merge properties the harness asserted — is the record
  > of why it was built, and the merge coverage it took with it is still missing.

  That table was the only layer in this plugin that could not
  fail open, which made it a security artefact, and a security artefact nobody counts drifts. Two
  independent reviews put its size at **39** rules and at **~90**; the real figure was neither, and
  one of them was wrong for an instructive reason — it counted *lines containing* the literal
  `Bash(` (39) rather than occurrences of it (90), because several rules share a line. The
  authoritative numbers, established by evaluating `Get-DenyGroups` rather than by grepping it:

  | | `Bash(` | `PowerShell(` | `Edit(` | `Read(` | total |
  | --- | ---: | ---: | ---: | ---: | ---: |
  | before this change | 90 | 54 | 18 | 15 | **177** |
  | after | 92 | 56 | 18 | 15 | **181** |

  The set the installer writes and the set in the author's live `settings.json` were, at 177 rules,
  **identical in both directions** — zero rules live-but-not-installed, zero installed-but-not-live,
  differing only in order. There was no missing-rules gap. The gap was that **nobody could state the
  number**, and nothing failed when it changed. That is what this test closes: the fixture is
  compared against the table in both directions, element for element and per tool type, and CI fails
  on any difference. Change the table and the fixture in the same commit.

  It also asserts what the installer must never stop doing, by running it end to end against a
  scratch tree: an operator's own deny rules survive at their original indices, an already-present
  rule is not written twice, unrelated top-level keys come back byte-identical, exactly one backup is
  taken holding the original bytes, `apply` refuses without a `BaseHash` and on a stale one, a second
  run writes nothing, and `rollback` restores the original byte for byte. A final section proves the
  operator's **real** `settings.json` was byte-identical before and after — the installer's two roots
  are redirected at a temp directory, and this is the proof rather than the promise. `-Simulate`
  injects a deliberate drift so the failure path is demonstrable rather than assumed.

  Wired into the existing `fast-checks` job in `.github/workflows/ci.yml`, **not** into
  `tests/gate_regression.ps1`: that suite's case count is quoted in `docs/testing.md` and asserted on
  by the workflow, so it must not grow cases. Exit codes are `0`/`1`/`2` with deliberately no
  "passed with a caveat" — a deny table is either the one that was reviewed or it is not.

- `lw-gmhh:verbose` — the seventeenth slash command, and the last one `bin/lwg-doctor.ps1`
  reported as referenced-but-missing. It runs the shared `bin/lwg-toggle.ps1` with `-Flag verbose`,
  exactly as its five sibling preference toggles do.
- `output-styles/lw-gmhh-verbose.md` and `output-styles/lw-gmhh-verbose-plain.md` — the behaviour
  half of `verbose`. Reasoning shown, alternatives named with the reason each lost, evidence quoted
  in full, assumptions labelled *checked* or *not checked*. **No word ceiling and, deliberately, no
  word floor**: a floor is met by padding, so the files ban restatement and hedging in the same
  breath as they remove the limit. Both carry the shared never-suppress block byte for byte.

- **`.editorconfig`.** Absent until now, and half of what `P1-lineendings` requires. Line-ending
  safety was already handled by `.gitattributes` — a fresh clone shows no modified files — so this
  is about indentation and charset across editors: `indent_style = space` throughout,
  `indent_size = 4` for `.ps1` and `2` elsewhere, `charset = utf-8`, final newline, trailing
  whitespace trimmed. Every value was measured against the tracked tree rather than assumed: no
  file indents with a tab, none has trailing whitespace, none carries a BOM, all end with a
  newline, and markdown uses no two-space hard line breaks, so the trim cannot eat one. The
  line-ending rules **mirror `.gitattributes` exactly** and are not a second opinion about it,
  including the `statusline/statusline.ps1` pin back to `eol=lf`.

- Open-source project documentation: `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, this
  changelog, GitHub issue and pull-request templates.
- `docs/` — the README split into `install.md`, `configuration.md`, `modules.md`, `gates.md`,
  `commands.md`, `architecture.md`, `testing.md`, `output-styles.md` and `troubleshooting.md`, with
  an index at `docs/README.md`.

### Changed

- **`config.json`: `output_style.brief` (boolean) is now `output_style.verbosity` (one of `brief`,
  `default`, `verbose`).** `lw-gmhh:brief` and `lw-gmhh:verbose` are two commands over one
  setting, so they can never both be on. Two independent booleans were rejected because a per-repo
  override is merged *key by key* — `brief` global and `verbose` per-repo would have contradicted
  each other from two individually valid writes, and no write-time rule inside the toggle script
  could have prevented it. An unrecognised value in that key is ignored and named as unrecognised
  on the next run, never coerced. **Anyone who had set `output_style.brief` by hand or with
  `lw-gmhh:brief on` must re-run the command**: the old key is no longer read, and a stale
  `"brief": true` left in the file does nothing.
- `verbose` was planned as a per-prompt binding (`checklist.json`, `PB-verbose`) and is **not**
  built that way. That approach — a `UserPromptSubmit` hook — was rejected for `brief` and `plain`
  in `a11f6f6` and is rejected here for the same measured reason: a hook registration cannot be
  made conditional, so the process is spawned on every prompt whether the preference is on or off.
  The plan item now describes what was built, and states plainly that **nothing binds** — an
  output style is advisory, and Phase B's "verbosity control that actually binds" remains
  unsatisfied.
- `README.md` rewritten as an entry point for a reader who has never seen this project: what it is,
  who it is for, what it does **not** do, a 60-second quickstart, and pointers. The internal
  "Phase N" build-sequence framing is gone. The honest-limitations material is kept in full and made
  prominent rather than trimmed.

### Fixed

- **An unclosed quote inside a here-document body swallowed every command after it, and the gate
  ALLOWED them.** Isolating heredoc bodies (see `V6`, below) stopped a dangling quote reaching *past*
  the terminator and did nothing about one running to the end of the body chunk it was in. The
  `unbalanced-quote` fault that catches this is raised only while walking the **code stream**;
  `Split-LwgSubcommands` silently appended to the current fragment on an open quote, so a body chunk
  came back as a single fragment whose first token was `#`. Rules anchor at a fragment's first token,
  so the hidden command was anchored at nothing and matched nothing.

  Two families, both confirmed executable against GNU bash 5.3.15 with a harmless `echo` standing in
  for the hidden verb, both ALLOWED at `35ced84`:

  ```
  echo hi # <<'D'                  cat <<'EOF' | sh
  # don't                          # x'
  git push --force origin main     git push --force origin main
  D                                EOF
  ```

  The left one is a **phantom here-document**: `#` is an ordinary character to the splitter, so a
  commented `<<'D'` opens a body the gate reads and bash does not. The right one needs no trick at
  all — an ordinary executor heredoc whose body contains one stray quote. Both reproduce with
  `gh repo delete … --yes` or `rm -rf /etc` as the hidden verb, and with an unpaired double quote.

  **The fix stops the swallow rather than faulting on it, and that distinction is the whole change.**
  Extending the fail-closed quote check to body chunks does close these — and it also refuses every
  legitimate `git commit -F -` whose prose contains an apostrophe, because a body containing `don't`
  and a body containing `# x'` are structurally identical to any quote-balance test. That collision
  is unresolvable, so it was not attempted.

  Instead the region from the unclosed quote to the end of the chunk is walked a **second time with
  quotes ignored**, and those fragments are *appended* to the ones the first pass produced. The first
  pass's output is untouched and still comes first, which makes the change safe by construction
  rather than by argument: every fragment the gate used to scan it still scans, in the same order, so
  the reported rule does not move; the only effect is that **more** text reaches the same rule table.
  A change that only ever adds fragments cannot turn a deny into an allow. The hidden `git push
  --force` becomes a fragment of its own and `git-push-force` denies it on its own merits.

  **There is no exemption, no allowlist and no safety determination anywhere in this change** — that
  is what the two reverted attempts before it were reverted for, and it stays absent. No new rule was
  added either: each of the six new cases trips the rule belonging to the command it hides.

  The behaviour is **uniform** — the code stream and a body chunk go through the identical path — on
  the reasoning that a second code path is a second place to drift away from bash. On the code stream
  the rescan mostly changes only the reported rule, since an unclosed quote there already raises
  `unbalanced-quote`; that fault stays as the backstop for a payload where nothing at all can be read
  past the quote.

  Six regression cases added, 227 → 233, as `V11a`–`V11f`. All six were ALLOWED at `35ced84`.
  **No existing case was changed, weakened or skipped** — in particular `N21`, the benign
  `git commit -F -` with an apostrophe in its prose, still passes, which is the case the
  fault-everywhere approach would have broken. `lib/gate_bash.ps1` only.

- **One laptop's private facts shipped to every install as universal truth.** An audit of the
  tracked files found four places where something true only on the author's machine — or true only
  of the author's preferences — was stated flatly, with the authority of a governance layer, to
  every reader. This is the defect the plugin exists to catch, committed by the plugin.

  **`context/worker_facts.md` is injected verbatim into every subagent on every machine**, and it
  asserted an absolute interpreter path (`C:\Program Files\Python312\python.exe`), an assumed minor
  version (`py -3.12`), a stale-`PATH` quirk of one shell, `PowerShell 5.1 only, no pwsh`, an
  agent-name prefix (`hq-*`) belonging to one operator's private `~/.claude/agents/` rather than to
  the `lw-*` roles this plugin ships — and *"No node/npm/npx/bun"*, which was already false on the
  machine it described and contradicted `docs/install.md`. Stripped to invariants. The portable
  stdin trick (`cmd /c "type in.json | powershell -File s.ps1"`, because a PowerShell pipe never
  reaches `[Console]::In`) is genuinely machine-independent and stays.

  Nothing was deleted outright: `lib/subagent_start.ps1` now reads an **optional, gitignored
  `context/worker_facts.local.md`** after the tracked file and appends it to the same injected
  block, under the same comment rules and the same 2000-character ceiling. When it is absent —
  the default — only the invariants are injected, with no error, no warning and no log line. That
  is where an interpreter path or an owner's push preference belongs.

  Probing for these facts at dispatch time was **measured and rejected**. In a fresh PowerShell 5.1
  process `Get-Command` costs ~9–25 ms when it finds its target but **600–1360 ms when it misses**,
  because a miss walks the whole `PATH` and the module autoload cache. Absence is precisely what a
  probe would be for, so the probe's worst case is its normal case — on a hook whose floor is
  ~300 ms and whose leash is 5 s. Stated in the file so the next reader does not retry it.

- **`verification_gate` was blind on every machine but the author's.** Its `work_agents` /
  `verify_agents` arrays listed only names that exist in one operator's untracked
  `~/.claude/agents/`. Everywhere else the module was enabled, counted toward the SessionStart
  banner's coverage number, reported healthy — and **could never match a single record**, so it
  could never warn. Two things had to change together:

  - The arrays now also carry the roles the plugin actually ships (`lw-implementer`, `lw-scribe`,
    `lw-healer`, `lw-verifier`), in `config.json` **and** in the code's own fallback defaults, so
    the module is not blind on an install whose `config.json` is missing or unreadable.
  - **A plugin-shipped role's `agent_type` arrives namespaced.** Verified from a live record:
    dispatching this repo's own explorer logs `"agent_type":"lw-gmhh:lw-explorer"`, while a
    user-scope role logs the bare `"hq-implementer"`. The matcher was an exact-string
    `HashSet.Contains` with no prefix handling, so it would have missed every shipped role while
    still appearing to work for the operator's own. It now strips a leading `<plugin>:` from the
    observed value and expands each configured name into both spellings, so the two meet whichever
    way round they were written — a role copied up into `~/.claude/agents/` loses the prefix, so
    neither form can be treated as canonical.

  **An empty `agent_type` remains "no information", never "not a verifier"**, and that is now
  stated at the code, in `config.json` and in the fixture rather than left to be inferred from a
  `continue`. About 28% of observed `SubagentStop` records carry the empty string; such a record
  can neither arm the gate nor disarm it. The advisory text also stopped naming an agent that
  exists only on one machine — it now names the `lw-verifier` the plugin ships, because advice to
  dispatch an agent the reader does not have is advice that cannot be followed.

- **`module_config.context_pressure.window_tokens` hardcoded an account entitlement.** The adjacent
  comment explained that the window depends on entitlements the hook cannot see and that the CLI
  picks 200000 or 1000000 — and then pinned `claude-opus-5` to 1000000. An explicit entry is the
  highest-trust source and **wins outright**, so it suppressed the very fallback chain documented
  beside it. On a 200k-entitled account that reported occupancy at **one fifth of the truth** and
  stayed silent straight through a compaction. The block now ships empty, and the chain runs as
  written: the `[1m]` tag, else a window *proven* by having been seen holding more than 200k tokens
  (persisted in `context_windows.json`, self-correcting after one turn), else 200k assumed with the
  advisory saying so. An operator's own entry still wins; an absent or empty block reads the same.

- **`config.json` quoted `mission_drift`'s 137 ms turn-end cost as a property of the module.** It is
  the median of one sample on one laptop (122 ms fastest, 169 ms slowest) and scales with transcript
  growth and disk speed. The number is unchanged; it is now labelled as a measurement rather than a
  constant, next to what *is* invariant about the cost — that it reads only the bytes the transcript
  grew by since the last turn.

- **`permissions.deny` had no backstop for a `+refspec` force push.** Cross-referencing the rule
  table in `lib/gate_bash.ps1` against the rules `bin/lwg-setup.ps1` writes turned up one hook rule
  with a config-layer counterpart that could have existed and did not: `git-push-force-refspec`.
  `git push origin +main` overwrites remote history exactly as `--force` does but carries no flag at
  all, so none of the twenty force-flag rules saw it and the only thing refusing it was the hook —
  the layer that fails open on every path by design. Four rules added to the `git-destructive`
  group: `Bash(git push * +*)`, `Bash(git push*+*)` and the `PowerShell(...)` twins. The spaced form
  requires the `+` to begin an argument, which is the hook's own test (`^\+[^\s]`).

  The other hook rules with no config-layer twin are now listed in
  `docs/gates.md` under *Hook rules with no config-layer counterpart*, with the reason each one
  cannot have one: `unparsable-continuation`, `unresolvable-command`, `unterminated-heredoc`,
  `unbalanced-quote` and `recursive-delete-unknown` are all properties of the *parse* rather than
  spellings a literal glob can enumerate, and the general form of `recursive-delete` is a filesystem
  question. Those genuinely rest on a layer that fails open, and now say so.

- **`docs/gates.md` claimed the opposite of what the installer does.** It read *"The plugin does not
  write your `permissions.deny` rules for you"* — true when it was written, false since
  `bin/lwg-setup.ps1` existed. A reader following that sentence would have hand-written 181 rules
  that `/lw-gmhh:setup` writes for them, or, worse, concluded the config layer was absent. Replaced
  with what actually happens, including the merge guarantee. `docs/install.md` never mentioned the
  config layer at all and now documents it as the not-optional half of the install.

- **`destructive_gate` bypass: an apostrophe in a here-document body made every command after it
  invisible.** This was live, not theoretical — re-run against GNU bash 5.3.9, the trailing command
  executes:

  ```
  git commit -F - <<'EOF'
  don't do this
  EOF
  git push --force origin main
  ```

  `Split-LwgSubcommands` walked the whole payload as one quote-aware stream, so the apostrophe in
  the **body** opened a single-quote region it then ran past the terminator and on to the end of the
  input. The force push was swallowed into a quoted blob, no rule was ever anchored at `git push`,
  and the gate ALLOWED it. bash, which knows a here-document body is data rather than shell source,
  ran it.

  `Split-LwgHeredocs` now runs before anything is split into subcommands. **Every body is cut out of
  the code stream and scanned as its own chunk, with fresh quote state — and that is the whole of
  it.** The same text reaches the same rule table, so no coverage is lost, and a dangling quote
  inside a body can no longer reach the commands after it.

  **There is no exemption, and the absence is the point.** Two earlier attempts at this shipped and
  were reverted — `498762d` (`fb426d1`) and `8b19975` (`083116e`). Both carried this same isolation
  and both added a second decision on top of it: skip scanning a body that "provably cannot run".
  The isolation opened **zero** bypasses across both attempts. All five bypasses came out of the
  exemption or out of machinery that existed only to serve it — a comment pre-pass that took a bare
  CR for a word boundary, and a shadowing scan that missed `eval 'git(){ sh; }'` because the parens
  sit inside quotes. So a body is scanned whatever quoted the delimiter, whatever program is on the
  line, and whether or not anything could execute it. There is nothing left in this code that
  decides something is safe.

  Two faults deny outright: `unterminated-heredoc` (bash warns and runs the command anyway, reading
  the body to end of input) and `unbalanced-quote`. Both are **Bash only**, as the two existing
  fail-closed rules already were.

  **This over-blocks, deliberately.** A commit-message line that begins with a backtick or a `$` is
  refused as `unresolvable-command`, because a body on its way to `git commit -F -` and a body on
  its way to `sh` are the same bytes, and `cat <<'EOF' | sh` with `$RM -rf /` in it is stopped by
  nothing else. A `<<` inside a `#` comment opens a here-document bash would not, and an apostrophe
  in a comment is refused as an unbalanced quote. Use `-F <file>` when a message trips one of these.
  The reasoning and the full cost were written up in `docs/gates.md` under "Here-documents:
  isolated, never exempt". That section went with the gate on 2026-07-30; the text is in the history
  of that file.

  Every delimiter rule was checked against real bash before being asserted, not recalled: `<<\EOF`,
  `<<E'O'F` and `<<"E"OF` all name the delimiter `EOF`; a trailing `|` really does continue the
  pipeline past the terminator; an unterminated body really does run to end of input. So was one
  thing neither reverted attempt had looked at — the **terminator line is scanned, not discarded**.
  The delimiter word is whatever the command's author wrote, so `<<'git push --force'` makes the
  terminator line a command, and a body line can continue into it with a backslash. Four such shapes
  were confirmed to execute a push or a repo delete under a shimmed `git`/`gh` — they were live
  against this branch until the terminator line was brought back into the scan — and all four are
  now cases `V9l`–`V9o`.

  80 regression cases added, 147 → 227, aimed at the reaching rather than at the rule table. `V6` is
  the apostrophe bypass. `V7` and `V8` are the five bypasses the two reverted attempts shipped, plus
  the exemption shapes that fail the moment one is reintroduced. `V9` is the delimiter and
  terminator edges. `V10` is the eighteen programs an executor allowlist would have had to name.
  `N21`–`N31` are the false positives. **No existing case was changed, weakened or skipped.**
  *(Counts as of that entry. The suite has since grown to 233 with the six `V11` cases above.)*

- **A stale `output_style.brief` key was ignored in silence.** `verbosity` replaced that boolean,
  but nothing told the operator their old key had stopped working: `lw-gmhh:brief` reported
  `brief is OFF` and exited `0` with no mention that the file said otherwise. The asymmetry was the
  bug — an unrecognised *value* of `verbosity` already produced a loud `UNRECOGNISED VALUE … It is
  being IGNORED, not honoured` block, and a dead *key* produced nothing. `bin/lwg-toggle.ps1` now
  detects it at either scope and prints an `OBSOLETE KEY` block in the same form, naming the scope,
  the full path (`repos["owner/name"].output_style.brief` for a per-repo copy), the value, and the
  command that re-sets the live key. **It is reported, never rewritten**: migrating would have to
  guess whether the old `false` meant `default` or `verbose`, and deleting a key on the operator's
  behalf during a read-only report is a worse surprise than the stale key.
- **`mission_drift`'s turn-end cost was documented as two different numbers.** `config.json`,
  `lib/common.ps1` and `lib/stop_advisories.ps1` said `13 ms`; `README.md`, `docs/modules.md` and
  `docs/testing.md` said `137 ms`. `137 ms` is the measured figure and the three code comments were
  wrong — `docs/architecture.md` carries the measurement it came from (median `137 ms`, min `122`,
  max `169`, with a per-stage breakdown summing to ~145 ms and a stated 150 ms budget), and no
  measurement of any kind supports `13 ms`. All six locations now say `137 ms`. The unrelated
  `~13 ms` character-stepping figure in `docs/architecture.md` and `lib/subagent_start.ps1` is a
  different measurement and is unchanged.
- **Checklist ticks contradicted their own section headings.** `PB-verbose` and `P2-readme-stranger`
  rendered `[x] DONE` under headings their caveats say were not met. The caveats always printed, so
  the report was honest — but a reader scanning the tick column never reached them.
  `bin/lwg-checklist.ps1` now renders a `DONE` row carrying a caveat as `[x*]`, annotates any
  section holding one with how many, and totals them beside the counts. **Presentation only**: no
  item's state, no caveat text and no evidence rule changed.
- Documentation stated that CI's JSON validity step checked a hardcoded list of three files and did
  not cover `.claude-plugin/marketplace.json`. It has checked every tracked `.json` since the
  `git ls-files` change below.
- Documentation stated that the CI workflow had never produced a passing build. It has, via exit `4`
  with the five 8.3 short-name cases skipped; that gap is now documented alongside the pass rather
  than as a pending failure.
- An operator-specific absolute clone path in the install section, replaced with
  `$env:USERPROFILE`.
- **Documentation and evidence rules that asserted one laptop's state as everyone's.** The audit
  that found them was prompted by the project being worked across more than one machine, where each
  of these is wrong rather than merely parochial.
  - `$env:USERPROFILE` was portable but `LEAPWare-HQ\leapware-software\` after it was the author's
    private folder layout presented as the install location — in **three** snippets that had to
    agree, so a reader who cloned elsewhere reached a `Copy-Item` in `docs/install.md` that copied
    nothing recognisable. All three now read a single `$Repo` variable with a neutral default
    (`docs/install.md`, `CONTRIBUTING.md`).
  - `commands/resolve.md` instructed the model that "three data directories exist on this machine
    and only one is live". That is a shipped instruction, and on a fresh install exactly one exists;
    the model was being told to expect and report a number it could not see. It now says to report
    the count actually in the candidate table.
  - `CONTRIBUTING.md` said the repo is "pure LF, despite what `.gitattributes` says about `*.ps1`",
    which told a contributor the attributes file was lying and invited a normalising sweep. The
    **index** is pure LF; the **working tree** is not, and `git ls-files --eol` shows `i/lf` on
    every tracked file and `w/crlf` on most `.ps1`. Rewritten to say that `.ps1` is checked out CRLF
    deliberately and normalised back on commit, so an editor writing either ending is harmless.
  - `checklist.json`'s `P8-tag` rule ran `git tag -l v0.3.0` with no `nonzero_means`. Tags are not
    fetched by a shallow or `--no-tags` clone, so a second machine could report a hard **fail** for
    a release it simply had not fetched. `nonzero_means: unverified` added — and the row now states
    plainly that this is a *partial* fix, because `git tag -l` exits `0` with empty stdout in the
    case it was added for, and `bin/lwg-evidence.ps1` has no empty-stdout knob to hang the rest on.
  - `checklist.json`'s `P1-github-meta` named `.github/ISSUE_TEMPLATE/bug.md` and
    `.github/dependabot.yml`. The templates are YAML issue forms (`bug_report.yml`,
    `feature_request.yml`, `security.yml`) and always were; the paths are corrected to what exists.
    `dependabot.yml` is **kept in the rule and still absent**, so the item stays incomplete for the
    piece that genuinely is not built — the paths were wrong, not the verdict.
  - The multi-laptop consequence of the untracked source plan is now written down in
    `checklist.json` and `commands/checklist.md`. The degradation was already correct — it prints
    `STALENESS NOT MEASURED` with a reason and never claims "no drift" — but nothing said that
    drift is therefore measurable on **exactly one** machine, so a second laptop cannot detect an
    untranscribed plan item and its clean-looking checklist is silence rather than agreement.
  - Bare per-machine measurements now carry their provenance: `137 ms` (`README.md`,
    `docs/testing.md`, `docs/modules.md`), `285 ms` (`docs/output-styles.md`, `docs/modules.md`,
    `checklist.json`), `3–10 minutes` / `~450 processes` (`README.md`, `CONTRIBUTING.md`,
    `docs/commands.md`, `docs/troubleshooting.md`) and `4 ms cold`
    (`docs/configuration.md`). **No number changed** — they were correct, and were being read as
    constants. `227 cases` and `181 rules` are deliberately untouched: both are asserted by CI
    against tracked fixtures, so they are genuinely invariant. *(The case count has since moved to
    233; it is invariant per commit, not forever, and CI still asserts it.)*

## [0.2.0] — 2026-07-27

The version declared in the manifests since the health supervisor was absorbed. Everything below
landed under it.

### Added

- **`destructive_gate`** (`lib/gate_bash.ps1`, `lib/gate_write.ps1`) — `PreToolUse` gates that deny
  force pushes, `reset --hard`, `clean -f`, `filter-branch`/`filter-repo`, `rebase --root`,
  `reflog expire --expire=now`, recursive deletes outside a scratch or regenerable directory,
  `gh repo delete`/`archive`, `gh api -X DELETE` on repo-level resources, writes into `.git/`, and
  writes to credential paths.
- **`secret_scan`** (`lib/gate_write.ps1`) — scans written content for GitHub/AWS/Slack tokens,
  private-key headers and credential assignments carrying a real value. Denials are logged redacted:
  rule, line number and match *length*, never the value.
- **`context_pressure`** — recomputes context occupancy from the transcript's last main-thread
  assistant usage block using the CLI's own formula, resolving the unobservable window size through
  config → `[1m]` tag → observed-over-200k → assumed, and recording which source it used.
- **`verification_gate`** — warns on `Stop` when the newest work-subagent record postdates the newest
  verifier record. Registered as `observe`, not `gate`.
- **`docs_coupling`** (`lib/post_edit.ps1` + `Stop`) — warns when source files changed this session
  and no documentation did.
- **`git_hygiene`** — branch, commit and push discipline at turn end. The only module that spawns a
  subprocess, and only on `Stop`, inside a repo, with a hard timeout.
- **`mission_drift`** — warns when every source or documentation file edited this session landed
  outside the workspace root and matches nothing the operator named in any prompt. **Ships switched
  off**; its trigger was never validated against real sessions.
- **`context_injection`** (`lib/subagent_start.ps1`) — a `SubagentStart` hook that injects
  `context/worker_facts.md` as `hookSpecificOutput.additionalContext`, read live on every dispatch,
  because Claude Code snapshots `CLAUDE.md` into a subagent at *parent-session* start.
- **`failure_capture`** (`lib/supervisor.ps1`) — the standalone health supervisor absorbed into the
  plugin, handling five hook events and exiting 2 to alert the orchestrator mid-turn.
- **`log_rotation`** — `health.jsonl` rolls at 5 MB, keeps two archives, and carries the last 500
  records into the new live file so the status line's `-Tail 300` never goes blind.
- `$LwgModuleRegistry` in `lib/common.ps1` as the single source of truth for what is implemented,
  planned or blocked, with `$LwgModules` and `$LwgGates` derived from it.
- Three slash commands — `/lw-gmhh:status`, `/lw-gmhh:doctor`, and `lw-gmhh:verify` (since removed) — each backed by a
  real script under `bin/` rather than by prose the model interprets. `lwg-doctor.ps1` runs eight
  checks and exits 0/1/2/3; `lwg-verify.ps1` passes the suite's exit code straight through.
- `.claude-plugin/marketplace.json` — a single-plugin marketplace so the repo can be installed as
  well as junctioned.
- Three output styles in `output-styles/` — `lw-gmhh-brief`, `lw-gmhh-plain` and
  `lw-gmhh-brief-plain` — carrying a shared never-suppress block, delimited by marker comments so
  the copies can be compared mechanically. Deliberately **not** modules and absent from
  `config.json`.
- `tests/gate_regression.ps1` — the gate allow/deny matrix plus one case per closed bypass and the
  fail-open cases, 143 in total. Previously the matrix lived in a scratch directory where nothing
  ran it.
- `.github/workflows/ci.yml` — `windows-latest`, Windows PowerShell 5.1, no OS matrix. Sub-second
  JSON and PowerShell-parse checks gate the ~7-minute suite.
- A capability probe (`fsutil 8dot3name query`) that runs before any case and prints
  `CAPABILITY: shortnames=available|unavailable method=…`, plus exit code `4` for a run whose only
  skips are documented capability-dependent cases on a machine probed and found to lack that
  capability. `-Simulate` makes the skip policy itself testable.
- `statusline/statusline.ps1` — the `HH`/`GM` status-line renderer brought under version control.
  It had existed in exactly one place, the live file at `~\.claude\statusline.ps1`, after its backups
  were deleted in a cleanup. Pinned to `eol=lf` in `.gitattributes` so a clone reproduces the
  installed bytes.
- `.github/CODEOWNERS` with a catch-all owner that GitHub actually accepts — a bare org handle is
  silently ignored.
- `.gitattributes`.

### Changed

- **Coverage is counted from the module registry, never from `config.json` flags.** The banner had
  read `12/12 modules, 3 gates, enforcing` when three modules had code and no gate existed at all.
- `Get-LwgRepo` resolves the repo slug from `payload.cwd` — a bounded `.git` walk plus an origin
  remote parse — instead of from `payload.workspace.repo`.
- `Get-LwgStateDir` **discovers** the plugin data directory instead of falling back to a hardcoded
  name, preferring a suffixed `<name>-*` candidate over the bare `<name>`. `Get-LwgStateDirInfo`
  reports `path`, `source`, `resolved` and `candidates` so a caller can tell the live directory from
  a guess.
- `log_rotation` is invoked *above* the `failure_capture` gate in `lib/supervisor.ps1`, making the
  two flags independent in both directions.
- `self_health` honours its own flag. A session whose self-check did not run reports mode
  `unverified`, and the log record carries `selfcheck.ran: false` with `selfcheck.ok` left **null**.
- The session-mode ladder moved from `lib/session_start.ps1` into `Get-LwgSessionMode` in
  `lib/common.ps1`, so the banner and `/lw-gmhh:status` cannot disagree.
- The five advisory modules share **one** `Stop` process. The two `Stop` hooks were deliberately
  **not** merged: measurement showed same-event hooks run concurrently, so turn end costs the max
  and not the sum, and merging would have forced a choice between the supervisor's exit-2 alert and
  the advisory's stdout.
- `lib/stop_advisories.ps1` turn-end cost cut from 1 283 ms to 1 212 ms median: `git status` is
  launched before the in-process modules and collected after them, the repo slug is resolved only
  when it can change an answer, the script exits before touching the state dir when every `Stop`
  module is off, the edit list is read and classified once, and `context_windows.json` is no longer
  rewritten every turn.
- The gate suite exits `0`/`1`/`2`/`3`/`4` rather than `0`/`1`. Precedence is 2 > 1 > 3 > 4.
- Per-case crashes in the suite are caught, counted as that case's failure, and the run continues.
- The 24 fail-open cases carry IDs `F01`–`F24` and are filtered by `-Only` like everything else.
- CI's JSON validity step enumerates every tracked `.json` with `git ls-files` instead of a hardcoded
  list of three files, and treats an empty enumeration as a failure.
- The Apache-2.0 copyright placeholder was filled in.

### Fixed

- **Five destructive-gate bypasses.** Each has a regression case verified to be ALLOWED by the commit
  before its fix:
  - Backslash-newline was treated as a separator rather than a line continuation, tearing one command
    into two fragments so that neither matched — `git push \`⏎`--force origin main` ran. The same
    shape defeated `reset --hard`, `clean -fdx`, `rm -rf` and `gh repo delete`.
  - `eval` was missing from the wrapper peel, and `xargs` was peeled by name only, so
    `eval "rm -rf /"` and `xargs -I{} rm -rf {}` both resolved to a program no rule names.
  - The delete allowlist asked whether the target *string contained* a temp root, over a path never
    normalised for `..`, so `rm -rf ".../Temp/../../../.."` was declared throwaway.
  - Git long options were matched exactly, but git's `parse-options` accepts any unambiguous prefix,
    so `git reset --ha` and `git clean --forc` were read as harmless (verified against git 2.54.0).
  - NTFS 8.3 short names were not expanded, so `<repo>/GIT~1/config` was an unguarded write to
    `.git/config` — from which `[core] sshCommand` is arbitrary code execution on the next git
    command.
- `Split-LwgTokens` returned a comma-wrapped array, so every token list had `Count` 1 and **no gate
  rule could ever fire** while the gate reported clean.
- `Get-FailedTasks` returned a bare `PSCustomObject` when exactly one task failed, whose `.Count` is
  `$null`, so a single failed background task could never turn `HH` red.
- `alerted.json` was written via `$updated | ConvertTo-Json`, which emits a bare string for one entry
  and nests on re-read, after which a dead task re-alerted every turn. It is now always a flat JSON
  array of strings.
- The status line's `HH` and `GM` segments resolved the plugin data directory as
  `~\.claude\plugins\data\lw-gmhh`, but the plugin is auto-discovered as `lw-gmhh@skills-dir` and its
  real directory is `lw-gmhh-skills-dir`. Both segments read an empty file and rendered unconditional
  green. They now glob `lw-gmhh*`, read the union, discard records by session id, and render dim
  `HH-`/`GM-` when nothing is found.
- `git_hygiene`'s `probe_ms` reported elapsed-since-launch after the `git` call was moved earlier,
  turning a 93 ms call into a logged 550 ms one. It now reports OS process times, with
  `probe_wait_ms` alongside for the part that lands on turn end.
- A suite run that died on case 3 of 143 was indistinguishable from a clean run, because the harness
  exited 0 or 1 and nothing else.
- One byte on stderr from a child killed the whole run: `$ErrorActionPreference` promotes a
  `NativeCommandError` to terminating, and under `2>&1` Windows PowerShell 5.1 raises exactly that
  for a native child writing anything at all to stderr, regardless of its exit code.
- A `-Only` filter matching no case IDs ran zero cases and exited 0, printing "every selected case ran
  and passed". It now aborts with exit `2` and names the filter.
- Suite cleanup moved into a `finally` block; it had sat on the success path, so any abort orphaned
  the temp directory it created.
- The `SessionStart` `additionalContext` hardcoded a claim that nothing was blocked or scanned, which
  became false the moment a gate went live. It is derived from the active gate list.
- Documentation claimed two kinds of test coverage that did not exist — assertions on the advisory
  emission shape, and round-trip cases for the `context_injection` escaper — and described
  `mission_drift`'s legitimate-pivot path as tested when that module has no test of any kind. All
  three claims are corrected and the uncovered areas are now named.
- The CI trigger description was wrong about blast radius: `paths-ignore` sits on `on.push`, so a
  docs-only push skips the entire workflow, both jobs, not just the suite.

### Removed

- The `SessionStart` orphaned-worker check. It read `~/.claude/daemon/roster.json`, which does not
  exist and which nothing writes, so it reported 0 orphans unconditionally for its entire life.

## [0.1.0] — 2026-07-27

Loader only. No governance module had behaviour yet.

### Added

- `.claude-plugin/plugin.json` — the manifest, pointing at `hooks/hooks.json`.
- `config.json` — the module switchboard, per-repo overrides keyed by `owner/name`, and the
  rate-limit and context thresholds. It exists because Claude Code has no per-hook disable and
  `disableAllHooks` would also kill the status line.
- `hooks/hooks.json` — `SessionStart` only, in exec form (`command` + `args`) so
  `${CLAUDE_PLUGIN_ROOT}` substitutes and Windows paths survive.
- `lib/common.ps1` — config load with fail-open defaults, module resolution with per-repo override,
  state-dir resolution, and the 20/40/60/80/100 ms append-with-retry writer.
- `lib/session_start.ps1` — a **behavioural** self-check (the config parses to real booleans, the
  thresholds are numbers, the payload carries a session id, and the state dir accepts a write) plus
  the banner and the model-visible context block. Always exits 0.
- Apache-2.0 `LICENSE`, `.gitignore`.

[0.4.0]: https://github.com/LEAPWare-Software/LEAPWare-Watchtower/tree/main

<!-- The 0.4.0 link points at `main` rather than a tag, because there is no tag to point at: `main`
     declares 0.4.0 and nothing has published it. It becomes a `releases/tag/v0.4.0` link on the day
     it is cut, and the declaration sites move off 0.4.0 in the commit after that — see
     CONTRIBUTING.md, "Versions and releases". The former `[Unreleased]` heading is gone rather than
     left empty above this one: an empty [Unreleased] is what twelve unrecorded commits sat behind.

     THE 0.3.0 LINK DEFINITION WAS DELETED ON 3 SEPTEMBER 2026 AND THE HEADING IS DELIBERATELY LEFT
     UNLINKED. It pointed at `releases/tag/v0.3.0` on THIS repository, which 404s: `git tag -l` here
     returns nothing and the GitHub tags API returns an empty list. `v0.3.0` was tagged on a
     predecessor repository whose history this one does not carry, and that repository was deleted on
     2026-08-28. A link to a release that does not exist is a citation a reader cannot resolve, which
     is worse than no link; the `## [0.3.0] — 2026-07-31` heading and every entry under it stay
     exactly as they were, because they are a record of what was released and a record is never
     corrected. It was also the last COMPARE base the 0.4.0 link used, and a compare against a ref
     this repository does not have was broken in the same way. -->
