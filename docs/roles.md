# Agent roles

The plugin ships six subagent roles in [`agents/`](../agents/). They once lived only in
one operator's `~/.claude/agents/` under an `hq-*` spelling, so an installing user got none of them
and the orchestrator role did not install at all. That is what this directory fixes. Those personal
files were renamed to the `lw-*` spelling on 31 July 2026 and now declare `lw-class` themselves.

`agents/` is **auto-discovered** from the plugin root, like `commands/`, `skills/` and
`output-styles/`. [`.claude-plugin/plugin.json`](../.claude-plugin/plugin.json) is not changed
and must not be — naming a directory in the manifest *replaces* the default scan rather than
adding to it.

Proven loaded against Claude Code 2.1.220 by running the CLI with `--plugin-dir` pointed at this
repo and reading the debug log:

```
[DEBUG] Loaded 6 agents from plugin lw-watchtower default directory
[DEBUG] Total plugin agents loaded: 6
```

## What ships

| File | `lw-class` | model / effort | Status |
| --- | --- | --- | --- |
| [`lw-verifier.md`](../agents/lw-verifier.md) | `verify` | `opus` / `xhigh` | **Required** |
| [`lw-healer.md`](../agents/lw-healer.md) | `work` | `opus` / `high` | **Required** |
| [`lw-orchestrator.md`](../agents/lw-orchestrator.md) | `neutral` | `opus` / `high` | Example, deletable |
| [`lw-implementer.md`](../agents/lw-implementer.md) | `work` | `opus` / `high` | Example, deletable |
| [`lw-explorer.md`](../agents/lw-explorer.md) | `neutral` | `sonnet` / `medium` | Example, deletable |
| [`lw-scribe.md`](../agents/lw-scribe.md) | `work` | `haiku` / `low` | Example, deletable |

**`lw-verifier` is required** because it is the only `verify`-class role in the box. With no
verify-class role installed, `verification_gate` can only ever nag and never clear: it warns when
the newest work-agent record is newer than the newest verify-agent record, and with no verifier
there is never a verify record to be newer than. That is not left to be discovered —
`bin/lwg-doctor.ps1` fails on it; see
[The doctor asserts there is something that can disarm it](#the-doctor-asserts-there-is-something-that-can-disarm-it).

**`lw-healer` is required** because the status line probes for a healer role file and paints the
health segment purple — *"the supervisor or the healer agent is not installed"* — when it cannot
find one. The probe names **this** file first, so shipping it is what satisfies it on a machine
that has only the plugin. See [The status line probes for `lw-healer.md`](#the-status-line-probes-for-lw-healermd)
below.

The other four are examples. Nothing in the plugin reads them, and deleting one costs you only
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
| `lw-class` | This plugin's own key — `work`, `verify` or `neutral`. See below. |

Because `model` and `effort` are honoured here, **model routing lives in the role file**. It is
no longer a table in one operator's private `CLAUDE.md` that every dispatch has to remember.

### Frontmatter breaks silently — validate it

A malformed frontmatter block does not fail loudly. **The agent still loads, with every metadata
field silently dropped** — no model, no effort, no tool restrictions, no `lw-class`. A `verify`
role that lost its `disallowedTools` this way is a role that can edit.

The commonest cause is an unquoted `description` containing a colon-space. Quote every
description. Then check it:

```
claude plugin validate --strict .claude-plugin/plugin.json
```

The validator walks `agents/` and reports the exact failure. Confirmed by deliberately breaking
one of these files as a negative control, which produced:

```
Validating agent: ...\agents\lw-scribe.md
  ❯ frontmatter: YAML frontmatter failed to parse: YAML Parse error: Unexpected character.
    At runtime this agent loads with empty metadata (all frontmatter fields silently dropped).
✘ Validation failed
```

and passed again once restored. So a green validate is real evidence that these files parse.

### `lw-class`

One custom key, three values. It says what a role *does to the tree*, which is the only thing a
verification gate needs to know about it.

| Value | Meaning | Effect on `verification_gate` |
| --- | --- | --- |
| `work` | Mutates the tree. | **Arms** the gate. |
| `verify` | Independently checks someone else's work. | **Disarms** it. |
| `neutral` | Read-only recon, orchestration. | Neither. |

**A `verify` role must not be able to edit.** A role that can fix what it finds is not an
independent check of it — it is the author, one step later. So `verify` roles must not name
`Edit`, `Write` or `NotebookEdit` in `tools`, and should deny them explicitly through
`disallowedTools`. `lw-verifier` carries `disallowedTools: Edit, Write, NotebookEdit`; a denylist
is used deliberately, so a tool added to the harness tomorrow does not arrive pre-granted.

`neutral` is not a hedge. `lw-explorer` reads files and finds nothing wrong — that is not
verification, and classing it `verify` would let a search satisfy a gate that exists to demand a
check.

**Unknown frontmatter keys are silently ignored by the loader.** That is what makes `lw-class`
possible, and it is an affordance rather than a contract: nothing documents it, `--strict` does
not object to it today, and a future release could start rejecting unknown keys or, worse,
treating one as meaningful. If that happens, the symptom is these six files failing to load. It
is the reason there is exactly one custom key and not five.

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
lw-class: verify
---

You review diffs...
```

That is the whole procedure. There is no registry to update and no array in
[`config.json`](../config.json) to extend: `verification_gate` reads `lw-class` off the file, so the
role classifies itself. See
[How `verification_gate` classifies these roles](#how-verification_gate-classifies-these-roles).

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
role onto it.** A plugin-root `settings.json` may set only `agent` and `subagentStatusLine`;
there is no plugin-side lever over the top-level session's tool grants.

So `lw-orchestrator` ships as a **default, never an invariant**. Its `tools` list omits `Bash`,
`Edit` and `Write`, and that restriction is real *while the role is running* — but whether the
top-level session runs it, and whether the top-level session can edit at all, are the user's
settings to make. Denying the main thread those tools is a **documented user step**, not
something installing this plugin accomplishes.

Say this plainly wherever the orchestrator is described. A delegation discipline that the
governance layer only *recommends* is a different product from one it *enforces*, and pretending
otherwise is the class of defect this plugin exists to catch.

## How `verification_gate` classifies these roles

**Changed guidance — read this if you remember the old paragraph.** This section used to say the
`lw-class` classifier was unbuilt and that the module matched literal names out of two arrays in
[`config.json`](../config.json). **It is built.** All six shipped roles declared `lw-class` and
nothing read it — a switch wired to nothing, counted as coverage, which is the founding defect this
plugin exists to catch, committed by the plugin that exists to catch it. That is closed:
[`lib/stop_advisories.ps1`](../lib/stop_advisories.ps1) classifies from the key, through
`Get-LwgAgentClassInfo` in [`lib/common.ps1`](../lib/common.ps1).

**`lw-class` wins wherever it is present.** Adding a name to a `config.json` array does not override
a role that declares its own class, and it is still not part of
[adding your own role](#adding-your-own-role).

### Resolving a name to a file, and what happens when that fails

The hook is handed a string — `agent_type` — and the class lives in a file. Nothing in the payload
says which file, so the name is resolved back to one:

1. the observed value is split on its **first** colon. A plugin name cannot contain `:`, so
   `lw-watchtower:lw-explorer` yields the stem `lw-explorer`; a *trailing* colon with nothing after it is a
   typo, not a prefix, and is not stripped;
2. `<stem>.md` is looked for down the [precedence](#precedence) chain — project, user, plugin. A
   `<plugin>:` prefix puts the **plugin scope first**, because a namespaced `agent_type` is evidence
   that a plugin's own copy is the one that ran, and without that reordering a user file happening to
   share a stem would answer for it;
3. the **first file found wins whether or not it declares a class** — a shadowing file *replaces* the
   one below it, so falling through to a lower scope would read the class off a file that did not run;
4. its frontmatter is scanned as far as the closing `---` for `lw-class`.

**Three ways that fails, and all three mean *no information*, never *not a verifier*:**

| Failure | Why it happens |
| --- | --- |
| the role belongs to **another plugin** | no other plugin's install path is derivable from a hook — `plugin.json` carries no source id — so its roles are unreachable by construction |
| **no such file** | deleted, renamed, never existed; a stale log record; a built-in like `general-purpose` |
| **file found, no `lw-class`** | any role predating the key that has never been given one — the user-scope `hq-*` files were the live example until they were renamed and classed on 31 July 2026; also a value that is not one of the three, which is a typo rather than a class |

The third case, and only the third, then falls back to the `work_agents` / `verify_agents` arrays.
Anything still unclassified is handled exactly like an empty `agent_type`: it **neither arms the gate
nor disarms it**. Counting it as work would nag on evidence of nothing; counting it as verification
would silence the gate on the same absence.

### The arrays are kept, as a fallback

- **They classify roles that declare no class** — any role written before the key existed and never
  given one. The `hq-*` files in `~/.claude/agents/` were the live example on the machine this was
  written on, and striking their four names would have silently unclassified all six of them. That
  is why the strike waited until 31 July 2026, when those files were renamed to `lw-*` and given the
  key; the four `hq-*` names left the arrays only then. A machine that still holds role files under
  the old spelling loses classification for them until it repeats that rename.
- **They classify names with no file at all** — `implementer`, `engineer`, `qa-agent`, `code-review`,
  `security-adversarial-review`. These can never declare the key, so they can never leave.
- **They are also the code's fallback defaults.** `Get-LwgConfig` fails open, and a default list
  naming only one laptop's roles fails open into the same blindness described above.

### The classifier matches a scoped name — implemented

Load-bearing, verified rather than assumed, and now **shipped** rather than pending.
**`SubagentStop.agent_type` arrives namespaced for a plugin-shipped role and bare for a user-scope
one.** From a live run of this repo, dispatching the shipped explorer:

```json
{"event":"SubagentStop","agent_type":"lw-watchtower:lw-explorer","agent_id":"a3b438dd7dd6bb07a"}
```

against the operator's user-scope records of the day, which were bare (and which spelled the roles
`hq-*`, the spelling those files carried until they were renamed on 31 July 2026):

```
44 "agent_type":"hq-implementer"
16 "agent_type":"hq-verifier"
 1 "agent_type":"general-purpose"
```

The dispatch name is namespaced too: `lw-watchtower:lw-explorer` is what the session's agent registry
lists, and it is what worked.

A matcher that looked up a bare `lw-verifier` would therefore **miss every plugin-shipped role**
while appearing to work for the user-scope ones. Both forms have to keep working anyway, because a
user who copies a shipped role up into `~/.claude/agents/` gets the bare form for the same role.

[`lib/stop_advisories.ps1`](../lib/stop_advisories.ps1) closes this from both ends, and both ends
still matter now that the class is read from a file. The **observed** value has a leading
`<plugin>:` stripped before it is used — as the file-lookup stem *and*, if that lookup finds no
class, as the array key — and every **configured** name is expanded into both spellings by
`Expand-LwgAgentName`, so the two meet whichever way round they were written and neither form is
treated as the canonical one. A plugin name cannot contain `:`, so the *first* colon is the
separator; a trailing colon with nothing after it is a typo and is not treated as a prefix.

An empty `agent_type` is the other case, and it is handled the same way it always was — now stated
at the code rather than left to be inferred from a bare `continue`. About 28% of observed
`SubagentStop` records carry the empty string. Such a record is unclassifiable by any scheme, so it
is **"no information", never "not a verifier"**: it neither arms the gate nor disarms it. Adding
`""` to either array would not change that; the value is skipped before it reaches either set. An
unresolvable *name* now lands in the same place, by the same reasoning.

### The doctor asserts there is something that can disarm it

`bin/lwg-doctor.ps1`'s `agent-roles` check **FAILS** when `verification_gate` is enabled and **zero**
verify-class roles are installed. That is the state described under
[What ships](#what-ships) — the module is on, counted toward the SessionStart banner's coverage
number, and permanently unable to reach the outcome it exists to ask for, which is the
founding-defect shape rather than an ordinary misconfiguration.

A role counts either way the classifier counts it: `lw-class: verify`, or a name in
`verify_agents` **with a role file on disk**. A name in the array with no role behind it is not
counted, because counting it would be this check reporting a list as coverage.

The count is a **lower bound** and the check says so: roles shipped by other plugins are not
enumerable, for the reason in the failure table above. That direction is safe — it can produce a
spurious FAIL, never a false PASS.

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
