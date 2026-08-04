# Configuration

Everything is configured in one file: [`config.json`](../config.json) at the repo root.

No reinstall and no restart of anything but the session is needed. Under a
[junction install](install.md#option-b--directory-junction-recommended-for-development) the file
you edit *is* the file that runs.

**Why a config file rather than a built-in switch:** Claude Code has no per-hook disable.
`disableAllHooks` is all-or-nothing, and turning it on would also take down the status line and the
health supervisor. So every module gates itself on `config.json` instead.

## Configuring the plugin dirties this checkout

**Read this before running your first configuring command.** `config.json` is a **tracked** file in
this repository and it is **not** ignored, and the four commands that configure the plugin rewrite it
in place:

| command | script | writes |
| --- | --- | --- |
| `/lw-watchtower:delegate` | `bin/lwg-toggle.ps1` | `interaction.delegate` |
| `/lw-watchtower:plain` | `bin/lwg-toggle.ps1` | `interaction.plain` |
| `/lw-watchtower:verbosity` | `bin/lwg-toggle.ps1` | `interaction.verbosity` |
| `/lw-watchtower:config` | `bin/lwg-config.ps1` | any `modules` flag, global or per-repo |

Both scripts resolve the file as `Join-Path $pluginRoot 'config.json'`, and `$pluginRoot` is
`Split-Path -Parent $PSScriptRoot` — the checkout root, not the state directory. So the first action
this documentation asks a new operator to take, `/lw-watchtower:delegate on`, leaves
`git status --porcelain` reporting ` M config.json`. Measured, in a throwaway clone.

**What that costs.** `/lw-watchtower:update` will not pull over an uncommitted change — deliberately,
and the refusal is correct on its own terms — so it raises a `[FAIL] worktree` row and stops. It
reports *"N uncommitted change(s)"* without naming the file, which reads as your own work in
progress. It does not clear with time, a new session, or a reinstall of the same checkout.

**Neither obvious escape is good.** `git checkout -- config.json` restores the updater by discarding
your configuration, including the gate you just armed. Committing the change puts a commit on local
`main` that `origin/main` does not have, and the next upstream commit turns the `--ff-only` pull into
a divergence — the same permanent refusal wearing a different message.

**What actually works today:** copy the value out, `git checkout -- config.json`, run the update, then
set it again. That is a workaround for a defect, not a workflow, and it is written here because
nothing else in these pages warns about it.

**No test covers this, and none is shipped with this page.** `checklist.json`'s nearest row,
`P5-setup`, only checks that two files exist. A harness named `tests/tree_cleanliness.ps1` was
written for it and run — it drives the command in a throwaway clone and reads `git status` — and its
two substantive rows, *the checkout stays clean* and *`config.json` is not a tracked unignored file*,
fail at the current commit and failed identically at `fd8d023`, so the defect predates this release.
**That file is not in this repository**: `tests/doc_claims.ps1` runs every tracked `tests/*.ps1` and
aborts on any nonzero exit, so committing a suite that is honestly red would fail a CI step. Do not
go looking for it in a clone — the check lands with the fix, not before it. `docs/architecture.md`
states the rule this breaks under [State directory](architecture.md#state-directory).

## `modules` — the switchboard

```jsonc
"modules": {
  "failure_capture": true,
  "docs_coupling": true,
  "mission_drift": true,
  …
}
```

**Nine keys, all implemented, all `true`.** The `$status` block at the top of the file lists which
modules are implemented; a flag on a *planned* module would be recorded and reported, but there
would be no code for it to switch. `$status.planned` is **empty** as of 30 July 2026 — the two names
that were in it, `ratelimit_escalation` and `cost_tracking`, were removed along with their flags,
because neither can ever be built and a switchboard is not the place to keep that record. The
reasoning was kept in full at
[Attempted and blocked](modules.md#attempted-and-blocked-ratelimit_escalation-and-cost_tracking).
See [Modules](modules.md).

There is no `secret_scan` key any more, and **no gate key in this block at all**. `destructive_gate`
and `secret_scan` were removed on 30 July 2026 by explicit owner decision and their flags went with
their code, rather than being left behind as switches wired to nothing — see
[Both gates were removed](modules.md#both-gates-were-removed). `$status` carries a comment recording
each removal so neither has to be inferred from an absence.

**One gate does ship, and its switch is deliberately not here.** `delegate_gate` is switched by
`interaction.delegate`, further down this file, because one gate must have exactly one switch — see
[`output_style` and `interaction`](#output_style-and-interaction--two-preferences-and-one-gate-switch).
`$status.gates_live` reads `0` because that number counts gates that are **live**, and the gate ships
off. **No flag in the `modules` block turns blocking on or off**; `interaction.delegate` is the only
key in this file that does.

**No flag ships `false` any more.** `mission_drift` was the one that did; the owner switched it on
by default on 30 July 2026, and `$status.default_off` in `config.json` is now empty. That decision
accepts a real tradeoff — the module's trigger was never validated against real sessions, nothing in
this repository tests it, and it costs about 137 ms at every turn end. Read
[`mission_drift`](modules.md#mission_drift) before deciding to keep it on: it states the exact
trigger, the knobs, and the false positives it can still produce. Setting it back to `false` is the
whole of turning it off; nothing else is required.

Every module honours its flag with **zero side effects** when off: no log record; in
`docs_coupling`'s and `mission_drift`'s case no per-session edit list is created at all; in
`mission_drift`'s case no transcript read and no state written; in `git_hygiene`'s case no
subprocess is started; in `self_health`'s case no probe runs and no `selfcheck.probe` is written;
and in `context_injection`'s case no envelope is emitted and `worker_facts.md` is never opened.

## `repos` — per-repo overrides

```jsonc
{
  "modules": { "docs_coupling": false },        // off everywhere

  "repos": {
    "some-org/some-repo": {                     // off for one repo only
      "modules": { "docs_coupling": true }
    }
  }
}
```

Per-repo entries are keyed by the `owner/name` slug of the **origin remote**, and override the
global default for the listed modules only. Everything unlisted falls through. Sessions outside a
recognised repo always use the global defaults. Keys are matched case-insensitively.

The block ships empty.

### How the repo slug is resolved

This is worth reading, because it was wrong once in a way that made this entire block apply to
nothing.

The slug used to be read from `payload.workspace.repo`. `workspace` is **status-line-only** — it is
built in exactly one place in the CLI, the status-line input builder, and appears in **no hook
event** (the same finding that blocked `ratelimit_escalation` and `cost_tracking`; see
[Attempted and blocked](modules.md#attempted-and-blocked-ratelimit_escalation-and-cost_tracking)). So
`Get-LwgRepo` returned `null` for every hook, this entire block applied to **nothing** — including
the two `PreToolUse` gates that were live at the time — and every log record read `"repo":null`.

It is now resolved from `payload.cwd`, which every hook does carry: walk up for `.git` (bounded to
12 levels, handling the `gitdir:` file form used by worktrees and submodules, and following
`commondir` to the git dir that actually holds `config`), then parse `owner/name` out of the
`origin` remote — or the first remote if there is no `origin`. SSH (`git@host:owner/repo.git`) and
URL (`https://`, `ssh://`, `git://`) forms are both handled; a plain local-path remote has no slug
and yields `null`.

It sat on the `PreToolUse` path when there were gates, and is still memoised per process, does **no**
network access and spawns **no** subprocess — it is at most 12 `Test-Path` probes and one small config read, about
4 ms cold on one development machine and free thereafter. A directory that is not in a repo, or a repo that cannot be read,
returns `null` rather than throwing.

## `thresholds`

The numbers the pressure monitors compare against.

| Key | Default | Consumed by |
| --- | --- | --- |
| `ratelimit.warn_pct` | 88 | the **status line** — prints `approaching limit` |
| `ratelimit.land_all_pct` | 92 | the **status line** — prints `land all work` |
| `context.warn_pct` | 75 | `context_pressure` |
| `context.critical_pct` | 90 | `context_pressure` |

The rate-limit pair is consumed by the status line, **not by a module**: `ratelimit_escalation`
does not exist and cannot, for the reason given in
[Attempted and blocked](modules.md#attempted-and-blocked-ratelimit_escalation-and-cost_tracking).

## `module_config` — per-module tuning

Every key in it is optional; the code carries the same defaults, so deleting the block changes
nothing.

### `context_pressure`

| Key | Default | Effect |
| --- | --- | --- |
| `window_tokens` | `{}` — **empty, deliberately** | Model id → context window size, in tokens. An entry here is the highest-trust source and removes all guessing for that model. |

**An entry wins outright, so leave it empty unless you are stating a fact about your own account.**
It beats the `[1m]` tag, it beats a window *proven* by observation, and it beats the 200 000
default — which is correct for an operator who knows their entitlement, and wrong for a value
shipped to every reader, because the window size depends on **account entitlement** and no single
number is true for everyone. It shipped as `{ "claude-opus-5": 1000000 }`, which on a 200 k-entitled
account made `context_pressure` report occupancy at one fifth of the truth and stay silent straight
through a compaction — the hardcoded entry suppressing the very fallbacks that would have
self-corrected it.

Empty, the chain in [Modules](modules.md#context_pressure) runs instead: `[1m]` tag, else a window
proven by having been seen holding more than 200 000 tokens, else 200 000 assumed with the advisory
saying so. An absent block and an empty one are read identically, so deleting it changes nothing.

### `verification_gate`

Despite the name it is **not a gate** and never was: it is kind `observe`, it warns on `Stop`, and it
cannot block. Tuning the lists below changes when it *warns*, never what is allowed.

| Key | Default | Effect |
| --- | --- | --- |
| `work_agents` | `lw-implementer`, `lw-scribe`, `lw-healer`, `implementer`, `scribe`, `engineer`, `healer` | Agent types whose completion counts as *work happened* — **only for a role that declares no `lw-class`**. |
| `verify_agents` | `lw-verifier`, `verifier`, `qa-agent`, `code-review`, `security-adversarial-review` | Agent types whose completion counts as *it was checked* — same condition. |

**These two lists are a fallback, not the classifier.** A role is classified from the `lw-class` key
in its own frontmatter, and that wins wherever it is present — so adding a name here does **not**
override a role that declares its own class, and it is not part of
[adding your own role](roles.md#adding-your-own-role). What the lists still do, and why they are not
deleted:

- they classify roles written before the key existed and never given one. The `hq-*` files in
  `~/.claude/agents/` were that case, and their four names stayed in these defaults until 31 July
  2026 for exactly that reason — striking them earlier would have silently unclassified all six of
  those roles at once. They were struck only once those files had been renamed to `lw-*` and given
  the key. A machine still carrying role files under the old spelling loses classification for them
  until it repeats that rename;
- they classify names that have no role file at all — `implementer`, `engineer`, `qa-agent`,
  `code-review`, `security-adversarial-review`;
- they are also the code's fallback defaults in `lib/stop_advisories.ps1`, because `Get-LwgConfig`
  fails open, and a default naming only roles that exist on one machine fails open into a module that
  matches nothing.

Matched case-insensitively against `SubagentStop.agent_type` as recorded in `health.jsonl`. **A name
may be written namespaced or bare and both are matched** — a plugin-shipped role is reported as
`lw-watchtower:lw-explorer` while the same role copied into the user scope is reported bare. See
[Agent roles](roles.md#how-verification_gate-classifies-these-roles).

An **empty** `agent_type` is in neither list and cannot be put in one: it is treated as *no
information*, so it neither arms the gate nor disarms it. The same is true of a name that resolves to
no role file and appears in neither list.

Deleting `agents/lw-verifier.md` without installing another `verify`-class role leaves the module
enabled with nothing that can ever disarm it. `bin/lwg-doctor.ps1` fails on exactly that — see the
`agent-roles` check.

### `git_hygiene`

| Key | Default | Effect |
| --- | --- | --- |
| `timeout_ms` | 1500 | Hard bound on each `git` child; killed on expiry. |
| `gh_timeout_ms` | 2500 | Hard bound on the one optional `gh` call. |
| `use_gh` | `true` | `false` removes the open-PR check, and with it the only network call this plugin makes. |
| `default_branches` | `["main", "master", "trunk"]` | Fallback when `refs/remotes/origin/HEAD` is absent — normal in a repo that was created rather than cloned. |

### `mission_drift`

| Key | Default | Effect |
| --- | --- | --- |
| `min_files` | 3 | How much unrelated work is needed before it will speak. |
| `require_outside_root` | `true` | `false` also flags unrelated work **inside** the workspace — more useful and considerably noisier. |
| `max_scan_bytes` | 2097152 | One turn's transcript growth beyond which the region is skipped and the module goes silent for the session. |
| `max_anchors` | 400 | Cap on the accumulated anchor set. |

### `docs_coupling`

| Key | Effect |
| --- | --- |
| `doc_extensions` | Extensions classified as documentation (`.md`, `.rst`, `.adoc`, `.txt`, …). |
| `doc_directories` | Directory names classified as documentation, matched on a whole path **segment** (`docs`, `doc`, `documentation`). |
| `doc_names` | Stems classified as documentation regardless of directory (`readme`, `changelog`, `license`, …). |
| `source_extensions` | Extensions classified as source. |

A path is **doc**, **source**, or **neither**; doc wins over source. JSON, YAML, TOML and lockfiles
are deliberately in *neither* bucket — counting lockfile churn as a source change is how this
module would become noise nobody reads.

## `context/worker_facts.md`

Not part of `config.json`, but it is configuration rather than code:
[`context/worker_facts.md`](../context/worker_facts.md) is the text `context_injection` hands to
every subagent at dispatch time.

Edit it and the next dispatch picks it up — no code change, no restart, no reinstall. Lines whose
first non-space character is `#` are comments and are not injected; blank lines are dropped.

**Keep it under 80 words.** Every dispatch pays for the text, and a worker handed a wall of
standing rules reads none of it. Only facts that *go stale* and that workers repeatedly get wrong
belong there. Anything durable belongs in `CLAUDE.md`, which is snapshotted once and costs nothing
per dispatch.

## `output_style` and `interaction` — two preferences and one gate switch

These two blocks hold the three keys set by `/lw-watchtower:verbosity`, `:plain` and `:delegate`.
**Hand-editing them works exactly as well as running the commands**, except that the commands also
state what each one does and does not do.

| Block | Keys | Default when absent |
| --- | --- | --- |
| `output_style` | `verbosity` — one of `brief`, `default`, `verbose` | `"default"` |
| `output_style` | `plain` | `false` |
| `interaction` | `delegate` | `false` — it arms a **blocking gate**, and nothing here arms itself |

**`interaction.ask` and `interaction.ask_inline` were in this block and were removed on 30 July
2026**, with the two commands that wrote them, by an explicit owner decision. Both defaulted to
`true` and enforced nothing, and neither can be built — see
[the four deleted commands](commands.md#commands) and `$removed_keys_comment` in
[`config.json`](../config.json). A flag left here would be a setting nothing reads.

> **Three commands, three keys — one apiece.** `verbosity` is a *level*, not a switch: it holds one
> of three values and `/lw-watchtower:verbosity` sets it by name. It was two commands, `lw-watchtower:brief` and
> `lw-watchtower:verbose`, over this one key until 30 July 2026; the stored value did not change in the
> merge. Two booleans were rejected because a per-repo override is merged *key by key* — `brief`
> global and `verbose` per-repo would have contradicted each other from two individually valid
> writes, and no rule inside the toggle script could have stopped it. A value that is not one of the
> three is **ignored and named as unrecognised**, never coerced. An `output_style.brief` key — the
> boolean `verbosity` replaced — is dead, and is **named as obsolete** at whichever scope it
> survives at rather than being migrated or deleted for you. See
> [`verbosity` is one key with three levels](commands.md#verbosity-is-one-key-with-three-levels).

**Every one of these three keys sits outside `modules`, and for one shared reason:** `Get-LwgConfig`
fails **open**, so an unreadable `config.json` switches every `modules` flag *on*. That is the right
polarity for an observing module and the wrong one for both an answer-formatting preference — it
would rewrite every answer you see — and for a gate, where it would arm a blocking hook off a file
nobody could read. Outside `modules` they are read through a `Get-LwgModuleOption`-shaped accessor
that returns the built-in default when the key is absent, so a corrupt config leaves verbosity at
`default`, `plain` off, and the gate **off**.

**Where they differ is the module count.** `verbosity` and `plain` are absent from
`$LwgModuleRegistry` too — the banner's `n/10` counts governance coverage and an answer-formatting
preference is not governance. `interaction.delegate` **is** in the registry, as `delegate_gate` of
`kind = 'gate'`, because a gate is governance in its strongest form. So the total is 10, and running
`/lw-watchtower:delegate` moves both the active count and the live gate count; running the other two moves
nothing.

> **One gate, one switch.** The `delegate_gate` registry entry declares
> `switch = @{ block = 'interaction'; key = 'delegate'; default = $false }` instead of taking a
> `modules` flag. A second flag would let `/lw-watchtower:delegate on` succeed while the gate stayed silent
> because the other flag was false — a switch wired to nothing.
> [`bin/lwg-doctor.ps1`](../bin/lwg-doctor.ps1)'s `config-registry` check knows about the exemption,
> asserts that `interaction.delegate` really exists, and **fails if both spellings are present**.

They take per-repo overrides in the same `repos` block, in a sub-block of the same name alongside
`modules`. The gate honours them: it resolves its switch through the same `Test-LwgModule` the banner
uses, so an override applies to it exactly as it applies to a module.

```jsonc
"repos": {
  "LEAPWare-Software/example-repo": {
    "modules":     { "docs_coupling": false },
    "interaction": { "delegate": true }
  }
}
```

**`verbosity` and `plain` are enforced by nothing. `delegate` really blocks.** Setting
`interaction.delegate` to `true` — by hand or by command — arms
[`lib/gate_delegate.ps1`](../lib/gate_delegate.ps1) on the very next tool call, and it will then
refuse `Edit`, `Write`, `NotebookEdit`, `Bash` and `PowerShell` for anything that is not a subagent. **That
includes the command that would turn it off again**, which runs through `Bash`; set the key back to
`false` by hand, or have a subagent run `/lw-watchtower:delegate off`. See
[what each preference command actually does](commands.md#the-three-preference-commands-and-what-each-one-actually-does).

## Output styles

The five output styles in [`output-styles/`](../output-styles/) are **not** modules. The `.md` files
themselves are configured nowhere — the style Claude Code applies is the `outputStyle` key in a
settings file, written by `/config`, and **nothing in this plugin writes that key**. The
`output_style` block above records which style you *want*; it does not activate one. See
[Output styles](output-styles.md) — including why they are not configured here, and the four things
they cannot do.

## `permissions.deny`

**Not configured here, and no longer written by anything this plugin ships.** It is a key in your own
`~/.claude/settings.json`, evaluated by the CLI itself — the one layer that cannot fail open — and
`/lw-watchtower:setup` now writes **zero** rules into it. `Get-DenyGroups` in `bin/lwg-setup.ps1` returns
an empty table: the four destructive groups (133 rules) and then the two credential groups (48) were
removed on 30 July 2026 with the gates that mirrored them. See
[Both gates were removed](modules.md#both-gates-were-removed) and
[Install](install.md#the-installer-writes-no-permissionsdeny-rules).

Whatever is in that key on your machine is yours. Nothing here reads it, renews it or removes it.

## Keeping `config.json` and the registry in step

`config.json`'s module keys and `$LwgModuleRegistry` in [`lib/common.ps1`](../lib/common.ps1) must
name the same modules. A flag with no registry entry is a switch wired to nothing; a registry entry
with no flag is a module nobody can turn off.

`/lw-watchtower:doctor`'s `config-registry` check fails when they disagree.
