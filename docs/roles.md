# Agent roles

The plugin ships six subagent roles in [`lw-watchtower/agents/`](../lw-watchtower/agents/). They once
lived only in one operator's `~/.claude/agents/` under an `hq-*` spelling, so an installing user got
none of them and the orchestrator role did not install at all. That is what this directory fixes.
Those personal files were renamed to the `lw-*` spelling on 31 July 2026.

`agents/` is **auto-discovered** from the plugin root, like `commands/`.
[`.claude-plugin/plugin.json`](../lw-watchtower/.claude-plugin/plugin.json) is not changed
and must not be — naming a directory in the manifest *replaces* the default scan rather than
adding to it.

Proven loaded against Claude Code 2.1.220 by running the CLI with `--plugin-dir` pointed at this
repo and reading the debug log:

```
[DEBUG] Loaded 6 agents from plugin lw-watchtower default directory
[DEBUG] Total plugin agents loaded: 6
```

## What ships

| File | model / effort | Status |
| --- | --- | --- |
| [`lw-healer.md`](../lw-watchtower/agents/lw-healer.md) | `opus` / `high` | **Required** |
| [`lw-verifier.md`](../lw-watchtower/agents/lw-verifier.md) | `opus` / `xhigh` | Example, deletable |
| [`lw-orchestrator.md`](../lw-watchtower/agents/lw-orchestrator.md) | `opus` / `high` | Example, deletable |
| [`lw-implementer.md`](../lw-watchtower/agents/lw-implementer.md) | `opus` / `high` | Example, deletable |
| [`lw-explorer.md`](../lw-watchtower/agents/lw-explorer.md) | `sonnet` / `medium` | Example, deletable |
| [`lw-scribe.md`](../lw-watchtower/agents/lw-scribe.md) | `haiku` / `low` | Example, deletable |

**`lw-verifier` used to be required** and is not any more. It was the only `verify`-class role in the
box, and without one `verification_gate` could nag and never clear. That module, its classifier and
the doctor check that asserted a verifier existed were all removed on 2 September 2026, and
`git grep lw-verifier -- '*.ps1'` now returns nothing: no code looks for this file by name or reads
a role's class. Deleting it costs you the role and nothing else.

**`lw-healer` is required** because the status line probes for a healer role file and paints the
health segment purple — *"the supervisor or the healer agent is not installed"* — when it cannot
find one. The probe names **this** file first, so shipping it is what satisfies it on a machine
that has only the plugin. See [The status line probes for `lw-healer.md`](#the-status-line-probes-for-lw-healermd)
below.

The other five are examples. Nothing in the plugin reads them, and deleting one costs you only
that role. Every shipped file carries a header saying so, and saying that **the file is
overwritten on plugin update** — do not hand-edit one in place; shadow it instead (below).

## The role contract

A role is one Markdown file. YAML frontmatter is the metadata; everything after it is the
agent's system prompt.

| Key | Meaning |
| --- | --- |
| `name` | The role's name. Must match the filename stem. |
| `description` | When to dispatch it. This is what the dispatching model reads to choose. |
| `model` | `opus`, `sonnet`, `haiku` — the default tier for this role. |
| `effort` | `low`, `medium`, `high`, `xhigh`. |
| `tools` | Allowlist. Everything not named is withheld. |
| `disallowedTools` | Denylist. Everything else is granted. |
| `isolation` | `worktree` gives the agent its own git worktree. |

**A role file carries no key of this plugin's own.** Earlier releases declared an `lw-class`
(`work`, `verify`, `neutral`) that `verification_gate` classified dispatches by; that module and its
classifier were removed on 2 September 2026 and nothing in this release reads a role's class. If you
copied `lw-class: verify` into a role of your own, it is ignored by the loader and can stay or go.

Because `model` and `effort` are honoured here, **model routing lives in the role file**. It is
no longer a table in one operator's private `CLAUDE.md` that every dispatch has to remember.

### Frontmatter breaks silently — validate it

A malformed frontmatter block does not fail loudly. **The agent still loads, with every metadata
field silently dropped** — no model, no effort, no tool restrictions. A verification role that lost
its `disallowedTools` this way is a role that can edit.

The commonest cause is an unquoted `description` containing a colon-space. Quote every
description. Then check it:

```
claude plugin validate --strict lw-watchtower/.claude-plugin/plugin.json
```

The validator walks `agents/` and reports the exact failure. Confirmed by deliberately breaking
one of these files as a negative control, which produced:

```
Validating agent: ...\lw-watchtower\agents\lw-scribe.md
  ❯ frontmatter: YAML frontmatter failed to parse: YAML Parse error: Unexpected character.
    At runtime this agent loads with empty metadata (all frontmatter fields silently dropped).
✘ Validation failed
```

and passed again once restored. So a green validate is real evidence that these files parse.

### A verification role should not be able to edit

This is a convention now rather than a contract — no module reads it and nothing enforces it — but
it is the reason `lw-verifier` is shaped the way it is. A role that can fix what it finds is not an
independent check of it; it is the author, one step later. So a verification role should not name
`Edit`, `Write` or `NotebookEdit` in `tools`, and should deny them explicitly through
`disallowedTools`. `lw-verifier` carries `disallowedTools: Edit, Write, NotebookEdit`; a denylist
is used deliberately, so a tool added to the harness tomorrow does not arrive pre-granted.

## Adding your own role

One file, no config edit. Drop it in `.claude/agents/` in your project, or `~/.claude/agents/`
for every project:

```markdown
---
name: my-reviewer
description: "Reviews a diff for security defects before it is merged."
model: opus
effort: xhigh
disallowedTools: Edit, Write, NotebookEdit
---

You review diffs...
```

That is the whole procedure. There is no registry to update, no array in
[`config.json`](../lw-watchtower/config.json) to extend, and no class to declare: nothing in this
plugin reads a role file at all beyond the healer probe described below.

### Precedence

Three scopes, most specific wins:

```
project (.claude/agents/)  >  user (~/.claude/agents/)  >  plugin (this repo's agents/)
```

**A file of the same name shadows the shipped one entirely** — it is replacement, not merge, so
the shadowing file must be complete. This is the supported way to customise a shipped role:
copy it up a scope and edit the copy. Editing the file in `agents/` works until the next plugin
update overwrites it.

## What a plugin cannot do to the main thread

**A plugin cannot withhold `Bash`, `Edit` or `Write` from the main thread, and cannot force a
role onto it.** There is no plugin-side lever over the top-level session's tool grants.

**This paragraph used to say a plugin-root `settings.json` "may set only `agent` and
`subagentStatusLine`", and that was wrong** — corrected 2026-09-05 against the shipped binary rather
than argued. A plugin ships *components*, and the loader's own list of component directories is
`["commands","agents","skills","output-styles","themes"]`. `settings.json` is not among them, so a
file of that name at a plugin root is not read as settings at all and cannot set `agent`. The
sentence mattered because `agent` is precisely the key that puts the main thread into a role: had it
been true, this plugin could have bound the orchestrator itself, and the rest of this section would
be describing a choice rather than a limit. It is a limit.

**What the plugin CAN do is ship the role, and one other thing.** `output-styles` *is* on that list,
and an output style applies to the main conversation only — a subagent runs its own system prompt.
So the plugin has exactly one channel that reaches the main thread without the user configuring
anything, and it shapes the thread's *instructions*, never its *tool grants*. Keep the two apart
whenever this is described.

So `lw-orchestrator` ships as a **default, never an invariant**. Its `tools` list omits `Bash`,
`Edit` and `Write`, and that restriction is real *while the role is running* — but whether the
top-level session runs it, and whether the top-level session can edit at all, are the user's
settings to make. Denying the main thread those tools is a **documented user step**, not
something installing this plugin accomplishes.

**The documented user step, spelled out, because "documented" is worth nothing if the page never
says it.** One key in your own `settings.json`:

```json
{ "agent": "lw-watchtower:lw-orchestrator" }
```

or, for one session only, `claude --agent lw-watchtower:lw-orchestrator`. The flag's own help text on
CLI 2.1.261 reads *"Agent for the current session. Overrides the 'agent' setting."*

Two things to know before you set it. The role's system prompt **replaces** Claude Code's own rather
than adding to it — the same way `--system-prompt` does — so what the role file says is the whole of
what the main thread is told; `CLAUDE.md` and project memory still load. And the way out is a
setting, not a tool call: change the key, or start without the flag. That is the difference between
this and `delegate_gate`, whose off switch runs through `Bash` and is refused by the gate it turns
off.

Say this plainly wherever the orchestrator is described. A delegation discipline that the
governance layer only *recommends* is a different product from one it *enforces*, and pretending
otherwise is the class of defect this plugin exists to catch.

## The status line probes for `lw-healer.md`

Fixed in commit `5ee0494`. `statusline/statusline.ps1` used to look for the healer role
at exactly two paths, both spelling the `hq-` name and one of them hardcoding a skills junction:

```powershell
$healer = & $first @(
    (Join-Path $home_ '.claude\skills\lw-watchtower\agents\hq-healer.md'),
    (Join-Path $home_ '.claude\agents\hq-healer.md')
)
```

This plugin ships no `hq-healer.md`, so that probe could only ever succeed through
`~/.claude/agents/hq-healer.md` — a personal file kept outside this repo. On a machine that had one
the second candidate hid the defect; on a clean install with the plugin working correctly, neither
candidate existed and the health segment rendered purple *"not installed"* permanently.

It now derives the plugin root through `LwgPluginRoots` — from `CLAUDE_PLUGIN_ROOT`, from the
script's own parent, from a globbed `~/.claude/skills/lw-watchtower*`, from the marketplace layout the CLI
actually writes (`~/.claude/plugins/cache/<marketplace>/lw-watchtower*/<version>` and
`~/.claude/plugins/marketplaces/…`) and from the legacy `~/.claude/plugins/repos`, which is kept
because no build promises the other two — and probes `agents\lw-healer.md` under each, which is the
file this repo actually ships:

```powershell
foreach ($r in $gmPluginRoots) {
    $healers += (Join-Path $r 'agents\lw-healer.md')
}
```

`~/.claude/agents/lw-healer.md` follows as a later candidate, so a machine whose healer role lives
in the user scope still resolves. The old `hq-` spelling was kept alongside it as a compatibility
candidate until 31 July 2026, when the rename left no file under that name anywhere and the probe
dropped it; a machine that still holds one renders the health segment purple until it renames it.
Fail-safe behaviour is unchanged: no root found still degrades to the purple glyph rather than
throwing.

`bin/lwg-setup.ps1` reports the same probe, in the same order, so what setup says about the health
segment is derived from the rule the segment applies rather than from a second opinion about it.
