# Configuration

Two files, and only one of them is yours: [`config.json`](../lw-watchtower/config.json) inside the
plugin payload is the **shipped defaults**, and your own settings live in `config.override.json`
under the state directory.

No reinstall and no restart of anything but the session is needed. Under a
[junction install](install.md#option-b--directory-junction-recommended-for-development) the file
you edit *is* the file that runs.

**Why a config file rather than a built-in switch:** Claude Code has no per-hook disable.
`disableAllHooks` is all-or-nothing, and turning it on would also take down the status line and the
health supervisor. So every module gates itself on the resolved configuration instead.

## Where your settings live

`config.json` here is the shipped defaults. `/lw-watchtower:config` and `/lw-watchtower:delegate`
write `config.override.json` in the state directory, and every reader resolves the two together with
the override winning. Both commands print both paths on every run. Deleting the override is safe and
returns every setting to the shipped default; deleting `config.json` is not, and the commands refuse
to write when it cannot be read, because an override is merged over defaults and not over a file
nobody could parse.

And one carve-out that has to be said, because it is a refusal an operator will meet:

`context_injection` is the one module `/lw-watchtower:config` will not switch. `lib/subagent_start.ps1`
reads `config.json` directly for its own flag rather than through the shared resolver, so an override
for it would be reported as applied and ignored by the hook it switches. The command refuses and says
so; see #11.

**This is why configuring the plugin no longer dirties the checkout.** Until 3 September 2026 both
commands rewrote the tracked `config.json` in place, so arming the gate left
`git status --porcelain` reporting ` M config.json` and `/lw-watchtower:update` refused to pull over
it — permanently, because neither obvious escape was any good. Nothing this plugin ships writes into
the plugin root now; a dirty tree there is work somebody did in this repository.

### Which configuration directory this resolves under

The state directory that holds `config.override.json` is found in one place, and the order is: an
explicit `-ClaudeHome` / `-SettingsPath` / `-DataRoot` parameter, then `$env:CLAUDE_PLUGIN_DATA` for
the data directory only, then `$env:CLAUDE_CONFIG_DIR`, then `$env:USERPROFILE` + `.claude`. **If you
have pointed the CLI at another configuration directory, this plugin follows it** rather than
composing a path from your profile and ignoring the variable. A trailing separator is trimmed, a
relative value is made absolute against the process working directory, and a directory that does not
exist is reported as not existing rather than silently replaced by the profile — see
[Install](install.md#where-this-plugin-looks-for-claude-codes-configuration-directory) for the whole
rule and why each part of it is that way round.

## `modules` — the switchboard

```jsonc
"modules": {
  "failure_capture": true,
  "docs_coupling": true,
  "context_injection": true,
  …
}
```

**Seven keys, all implemented, all `true`.** The `$status` block at the top of the file records what
has been removed and why, and states the rules the `modules` block below it follows. It does not list
which modules are implemented: `$LwgModuleRegistry` in `lib/common.ps1` is the one authoritative list,
`bin/lwg-doctor.ps1`'s `config-registry` check holds the `modules` block to it, and an `implemented`
array that duplicated it was deleted on 3 September 2026 because nothing ever read it (#75).
`$status.planned` is **empty** as of 30 July 2026 — the two names
that were in it, `ratelimit_escalation` and `cost_tracking`, were removed along with their flags,
because neither can ever be built and a switchboard is not the place to keep that record. The
reasoning was kept in full at
[Attempted and blocked](modules.md#attempted-and-blocked-ratelimit_escalation-and-cost_tracking).
See [Modules](modules.md).

**Four more modules are switched from outside this block**, each on a key of its own:
`send_liveness_gate` on `supervision.send_liveness`, `completion_audit` on
`supervision.completion_audit`, `orphan_watch` on `supervision.orphan_watch`, and `delegate_gate` on
`interaction.delegate`. All four ship `false`. The reason they are not here is polarity, and it is
given under [`interaction`](#interaction--the-one-gate-switch).

There is no `secret_scan` key any more, and **no gate key in this block at all**. `destructive_gate`
and `secret_scan` were removed on 30 July 2026 by explicit owner decision and their flags went with
their code, rather than being left behind as switches wired to nothing — see
[Both gates were removed](modules.md#both-gates-were-removed). `$status` carries a comment recording
each removal so neither has to be inferred from an absence.

**One gate does ship, and its switch is deliberately not here.** `delegate_gate` is switched by
`interaction.delegate`, further down this file, because one gate must have exactly one switch — see
[`interaction`](#interaction--the-one-gate-switch).
No number in this file records how many gates are live. `Get-LwgActiveGates` computes that from the
module registry and the switches whenever something asks, which is the only way it can be right after
an operator arms one; a literal here went false the moment `interaction.delegate` was set to `true`,
and `config.json`'s `$gates_comment` records why it was deleted. **No flag in the `modules` block
turns blocking on or off**; `interaction.delegate` and the two `supervision` gate switches are the
only keys in this file that do.

**No flag in `modules` ships `false`.** All seven are `true`, and `$status.default_off` is empty for
exactly that reason — it only ever described this block. It is **not** a claim that nothing ships off:
the four modules switched from `supervision` and `interaction` all do, and the comment beside the key
says so rather than leaving the reader to reconcile the two.

Every module honours its flag with **zero side effects** when off: no log record; in
`docs_coupling`'s case no per-session edit list is created at all; in `git_hygiene`'s case no
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

### `git_hygiene`

| Key | Default | Effect |
| --- | --- | --- |
| `timeout_ms` | 1500 | Hard bound on each `git` child; killed on expiry. |
| `gh_timeout_ms` | 2500 | Hard bound on the one optional `gh` call. |
| `use_gh` | `true` | `false` removes the open-PR check, and with it the only network call this plugin makes. |
| `default_branches` | `["main", "master", "trunk"]` | Fallback when `refs/remotes/origin/HEAD` is absent — normal in a repo that was created rather than cloned. |

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
[`context/worker_facts.md`](../lw-watchtower/context/worker_facts.md) is the text `context_injection` hands to
every subagent at dispatch time.

Edit it and the next dispatch picks it up — no code change, no restart, no reinstall. Lines whose
first non-space character is `#` are comments and are not injected; blank lines are dropped.

**Keep it under 80 words.** Every dispatch pays for the text, and a worker handed a wall of
standing rules reads none of it. Only facts that *go stale* and that workers repeatedly get wrong
belong there. Anything durable belongs in `CLAUDE.md`, which is snapshotted once and costs nothing
per dispatch.

## `interaction` — the one gate switch

This block holds the single key set by `/lw-watchtower:delegate`. **Hand-edit it in
`config.override.json`, not here** — an edit to the shipped `config.json` is honoured only where no
override overrides it, and the command writes the override. Otherwise hand-editing works exactly as
well as running the command, except that the command also states what it does and does not do.

| Block | Keys | Default when absent |
| --- | --- | --- |
| `interaction` | `delegate` | `false` — it arms a **blocking gate**, and nothing here arms itself |

**`output_style` went on 2 September 2026**, with the `verbosity` and `plain` commands that wrote it
and the five output-style files they named. Both keys recorded a preference that **nothing applied**:
the style Claude Code uses is the `outputStyle` key in a settings file, and this plugin never wrote
it. A config written before that date may still carry an `output_style` block; nothing reads it.

**`interaction.ask` and `interaction.ask_inline` were in this block and were removed on 30 July
2026**, with the two commands that wrote them, by an explicit owner decision. Both defaulted to
`true` and enforced nothing, and neither can be built — see
[Commands](commands.md#commands) and `$removed_keys_comment` in
[`config.json`](../lw-watchtower/config.json). A flag left here would be a setting nothing reads.

**The key sits outside `modules`, and the reason is polarity:** `Get-LwgConfig` fails **open**, so an
unreadable `config.json` switches every `modules` flag *on*. That is the right polarity for an
observing module and the wrong one for a gate, where it would arm a blocking hook off a file nobody
could read. Outside `modules` it is read through a `Get-LwgModuleOption`-shaped accessor that returns
the built-in default when the key is absent, so a corrupt config leaves the gate **off**.

`interaction.delegate` **is** in `$LwgModuleRegistry`, as `delegate_gate` of `kind = 'gate'`, because
a gate is governance in its strongest form — so running `/lw-watchtower:delegate` moves both the
active count and the live gate count.

> **One gate, one switch.** The `delegate_gate` registry entry declares
> `switch = @{ block = 'interaction'; key = 'delegate'; default = $false }` instead of taking a
> `modules` flag. A second flag would let `/lw-watchtower:delegate on` succeed while the gate stayed silent
> because the other flag was false — a switch wired to nothing.
> [`bin/lwg-doctor.ps1`](../lw-watchtower/bin/lwg-doctor.ps1)'s `config-registry` check knows about the exemption,
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

**`delegate` really blocks, and it is the only preference here that ever did.** Setting
`interaction.delegate` to `true` — by hand or by command — arms
[`lib/gate_delegate.ps1`](../lw-watchtower/lib/gate_delegate.ps1) on the very next tool call, and it will then
refuse `Edit`, `Write`, `NotebookEdit`, `Bash` and `PowerShell` for anything that is not a subagent. **That
includes the command that would turn it off again**, which runs through `Bash`. Two routes back: have
a subagent run `/lw-watchtower:delegate off`, or set `interaction.delegate` to `false` by hand in
`config.override.json` under the state directory — `$CLAUDE_PLUGIN_DATA`, or
`~/.claude/plugins/data/lw-watchtower*/`. **Not in `config.json`**: that file is the shipped defaults,
and an edit there changes nothing while the override still says `true`. If no override file exists,
the gate is off already and there is nothing to turn off. See
[what the one preference command actually does](commands.md#lw-watchtowerdelegate-the-one-preference-command-left).

## `permissions.deny`

**Not configured here, and no longer written by anything this plugin ships.** It is a key in your own
`~/.claude/settings.json`, evaluated by the CLI itself — the one layer that cannot fail open — and
`/lw-watchtower:setup` now writes **zero** rules into it. `Get-DenyGroups` in `bin/lwg-setup.ps1` no
longer exists, and neither does the `permissions` section that called it: the four destructive groups
(133 rules) and then the two credential groups (48) were
removed on 30 July 2026 with the gates that mirrored them. See
[Both gates were removed](modules.md#both-gates-were-removed) and
[Install](install.md#the-installer-writes-no-permissionsdeny-rules).

Whatever is in that key on your machine is yours. Nothing here reads it, renews it or removes it.

## Keeping `config.json` and the registry in step

`config.json`'s module keys and `$LwgModuleRegistry` in [`lib/common.ps1`](../lw-watchtower/lib/common.ps1) must
name the same modules. A flag with no registry entry is a switch wired to nothing; a registry entry
with no flag is a module nobody can turn off.

`/lw-watchtower:doctor`'s `config-registry` check fails when they disagree.
