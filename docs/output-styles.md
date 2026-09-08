# Output styles

**This plugin ships one output style:**
[`output-styles/lw-orchestrator.md`](../lw-watchtower/output-styles/lw-orchestrator.md). It is not
selected for you. It appears in the `/config` output-style picker as `lw-watchtower:lw-orchestrator`,
and it does nothing until an operator picks it.

## This page was a tombstone, and the deletion it records was right

Five output styles, and the `/lw-watchtower:verbosity` and `/lw-watchtower:plain` commands that chose
between them, were deleted on **2 September 2026**. [CHANGELOG.md](../CHANGELOG.md) records why, and
the reason is worth quoting rather than paraphrasing: those two commands *"recorded an output-style
preference **nothing applied** — a switch wired to nothing, which is the defect this plugin exists to
catch, shipped inside it."* The style Claude Code actually applies is the `outputStyle` key in a
settings file; the commands never wrote it, and were right not to — a settings file is not part of a
plugin, and the `/config` picker already owns that value.

The second reason the feature went is that this plugin **cannot audit compliance**: no hook fires
with an assistant answer in hand and a decision channel attached.

**Neither reason says the mechanism fails to steer.** The first is about a *command* that reported a
control it did not exercise. The second is a limit on *verification*, not on *instruction* — and an
instruction in the system prompt is the strongest channel this plugin has. A style file that is
shipped, offered, and never silently selected exercises exactly what it claims to.

So this page is no longer a tombstone. **The old one also claimed it was kept because published pages
linked to it — [README.md](../README.md) twice and [SECURITY.md](../SECURITY.md) at an anchor — and
neither is true today.** The only links are this directory's own [index](README.md) and the
unpublished maintainer note `.github/notes/style-compliance-check.md`. Corrected here rather than left
standing.

## What ships, and what it asks for

`lw-watchtower:lw-orchestrator` asks the main thread to **talk to the operator and direct the work**,
and to send reading, searching, editing, building and testing to subagents — so the thread stays
fast, keeps its context, and stays a conversation.

It is deliberately **not** a copy of the [`lw-orchestrator` *role*](roles.md), and the difference is
the reason both exist:

| | the role, `agents/lw-orchestrator.md` | the style, `output-styles/lw-orchestrator.md` |
| --- | --- | --- |
| Turned on by | `agent`, in your own `settings.json`, or `claude --agent` | `outputStyle`, in your own `settings.json` or the `/config` picker |
| Effect on the system prompt | **replaces** it | **appended** to it |
| Effect on tool grants | real — `Bash`, `Edit`, `Write` are not in the grant | **none** |
| Ships with the plugin | yes | yes |
| Reaches subagents | no — a subagent runs its own prompt | no — same |

The role's body says *"you cannot change a file from this seat"*, and that is true while it runs. The
style must never say it, because a style withholds nothing. **The style asks for the discipline; the
role enforces the grant.** A style file that copied the role's sentence would ship a false claim
inside a system prompt, which is this project's founding defect wearing new clothes.

They are **different keys**, and nothing here needs you to pick one. Whether setting both *composes*,
or one silently wins, is unmeasured — see below.

## Why a style rather than a `SessionStart` injection

The plugin could push the same paragraphs into the conversation with `additionalContext` on
`SessionStart`. It deliberately does not.

**Under compaction the system prompt and the output style are unchanged, while hook-added context is
summarised away.** An injected policy therefore evaporates at exactly the moment a long session needs
it most — a session that has run long enough to compact is a session in which a thread that reads
instead of delegating has already spent its context. A style survives compaction by construction.

There is a second reason, and it is a fact about this tree rather than an argument: this plugin does
not register `SessionStart` with `matcher: "compact"`, which is what would re-inject after a
compaction.

## `force-for-plugin` is not set, and that is an owner decision

`force-for-plugin: true` in a plugin-shipped style's frontmatter applies the style **automatically to
every install with this plugin enabled**, without the operator choosing it. It ships **un-forced**,
pending an owner call, for two stated reasons:

1. It **silently overrides the consumer's own `outputStyle`** — the same objection that argued against
   arming a gate by default. An operator who had chosen a style would find it replaced, and nothing
   would tell them.
2. It is marked **`@internal`** in the shipped binary — *"@internal — only meaningful for
   plugin-bundled styles; ignored for user styles"* — so it can change without notice.

## Frontmatter, and what is verified

```yaml
---
name: lw-orchestrator
description: "..."
keep-coding-instructions: true
---
```

`keep-coding-instructions: true` means, in the binary's own words, *"the default coding instructions
stay in the system prompt alongside this style."* Without it the style would **replace** them, and
this file is a delegation discipline rather than a complete set of working instructions.

**What is verified, and by what.** [`tests/payload_guard.ps1`](../tests/payload_guard.ps1) case
**S15** asserts that every file under `output-styles/` carries `keep-coding-instructions: true` and
does **not** carry `force-for-plugin: true`, and it fails on an empty or absent directory rather than
passing over one. That is the owner decision above, held by a machine instead of by a sentence. Case
**S14** additionally lints the block itself — no tab, no duplicate key, balanced quotes, no
colon-space in an unquoted value — over `agents/`, `commands/`, `skills/*/SKILL.md` and this
directory together. Since 7 September 2026 it also parses YAML block scalars, because a vendored
skill ships one; see [Roles § frontmatter](roles.md).

**What is not verified anywhere else.** The CLI applies **no schema validation at all** to a
plugin-shipped style's frontmatter — measured on **2.1.263**: the strict schema runs for *user*
styles, and the plugin loader reads the fields it knows. A misspelled key is silently ignored with
nothing reported on any surface, and a style whose frontmatter fails to parse is **skipped
entirely** — it simply is not in the picker, with no message the operator sees. That is why S14 and
S15 check the spelling this repository ships rather than trusting it. A style file over 1 MiB is
skipped with a warning.

**Not measured here, and named rather than glossed:** whether an output style and a bound `--agent`
role **compose**, or one silently wins. A style is *appended* to the system prompt; `--agent`
*replaces* it. No published documentation says what happens when both are set, and answering it needs
a live session, which no lane in this project starts.

## What none of this does

**So nothing on these pages should be read as a promise that this plugin controls what the
assistant says to you.** It does not, and it never did. What its three gates can refuse is a tool
call, or a turn end that claims work a queued message did not do — never the words in an answer, and
never anything at all as shipped, because all three of them ship switched off. See
[Modules](modules.md#gates-and-what-counts-as-one) and [Limitations](limitations.md).

An output style is an instruction, so a model can be asked to delegate and simply not do it, with
nothing between the model and the transcript to check. `Stop` sees `last_assistant_message` *after*
it has been rendered. **This ships a request, and says so.**
