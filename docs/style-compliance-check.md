# Design note: a `Stop`-time style compliance check

**Status: not built.** This note exists so the check can be built next without re-deriving
any of it. `lib/stop_advisories.ps1` was owned by another agent when the output styles
landed, so nothing in `lib/` was touched.

The five styles in [`output-styles/`](../output-styles/) are instructions in the system
prompt. Nothing enforces them — see [Output styles](output-styles.md). A `Stop`-time check is
the only half of this feature that could produce evidence, and it is the honest half:
without it, the plugin ships a governance surface whose compliance is asserted by the
thing being governed.

## What it can measure

`Stop` receives `last_assistant_message` in its payload. That is the whole input.

| Measure | Against | Verdict when exceeded |
| --- | --- | --- |
| word count of the message's prose | the ceiling in the active style | advisory: `answer ran to N words against a 150-word ceiling` |
| occurrences of a listed jargon term | the term list in the active style | advisory: naming the terms that appeared |

Both are advisory. Neither may block — see *Failure policy* below.

## Where the numbers come from, and why not from a config file

**The checker reads the active style file itself**, and extracts both values from the
marker comments already embedded in it:

```
<!-- lw-watchtower:ceiling-words 150 -->
<!-- lw-watchtower:jargon begin --> … <!-- lw-watchtower:jargon end -->
```

This is the point of the markers. A copy of the ceiling or the term list held in
`config.json` would be a second source that drifts from the instruction the model was
actually given, and would then report violations of a rule nobody was told. Reading the
same bytes makes drift structurally impossible rather than merely unintended: the
instruction and the check are the same string.

It also gives the correct behaviour for free. `lw-watchtower-brief.md` carries no jargon block
and `lw-watchtower-plain.md` carries no ceiling, so under those styles the corresponding check
finds nothing to measure and does not run. A rule the operator did not switch on is not
one they should be warned about.

**The two verbose styles carry no ceiling marker either, and that is the correct outcome
rather than a gap to be filled.** `lw-watchtower-verbose.md` and `lw-watchtower-verbose-plain.md`
deliberately set **no word floor** — a floor is met by padding, so measuring one would
train exactly the behaviour those files ban. There is therefore nothing for the length
half of this check to measure under a verbose style, and it must not invent something: a
"too short" advisory would be a rule the operator was never given, which is the defect
this section exists to prevent. Under `lw-watchtower-verbose-plain.md` the jargon half still
runs, because that file does carry the term list.

**Resolving the active style is the fiddly part**, and it is unbuilt. It means reading
`outputStyle` through the settings precedence chain (managed policy, then
`.claude/settings.local.json`, then project, then user), then mapping that name to a file
across four possible locations — the three documented style directories plus this plugin's
own `output-styles/`. Whether a plugin-supplied style's name is namespaced in the
`outputStyle` value is **unverified** (see
[Output styles](output-styles.md#frontmatter-and-what-is-verified)). Until that is checked against a
live install, the mapping is a guess, and a checker built on a guessed mapping will
silently measure nothing while reporting itself healthy — the exact defect this plugin
exists to catch. Verify it first; if the style cannot be resolved, the module must say so
rather than pass.

## Counting words honestly

The ceiling is on commentary, not evidence. The styles exclude code blocks, tables, file
paths, command output and quoted error text, so the counter must too, or it will fire on
every answer that does its job. Strip fenced code blocks, indented code blocks, Markdown
table rows and block quotes before counting; count the remainder on whitespace runs.

A counter that does not strip these is worse than no counter. It would train answers to
drop the evidence and keep the prose, which inverts the entire point of the styles.

## What it cannot measure, and must not imply it does

**The never-suppress block is not checkable from `last_assistant_message`.** You cannot
detect an omission by reading the text that omits it: nothing in a tidy answer reveals the
failure it left out. So the check can only ever measure the two cosmetic rules — length and
vocabulary — and those are the rules that matter least.

This must be stated wherever the check reports, because a green style-compliance advisory
would otherwise read as "the answer was honest" when all it means is "the answer was
short". Suggested wording for the advisory itself:

> Length and vocabulary only. Whether a failure, a skipped step or a caveat was left out
> is not measurable from the answer text and was not checked.

Two further blind spots, both real:

- **"First use in the conversation" is not visible.** A term explained three turns ago is
  correct usage, but `last_assistant_message` carries one turn. The check can count
  occurrences; it cannot judge whether the first one was explained. Either read the
  transcript for the first occurrence, or report occurrences as an observation rather than
  as a violation.
- **Structural rules are out of reach.** No preamble, findings before methodology, a table
  for three parallel facts — these need judgement, not counting. Do not approximate them
  with regexes; a rule enforced badly is worse than one left to the instruction.

## Failure policy

Same as every other advisory here.

- Registered as `observe` in `$LwgModuleRegistry`, never as a gate. It cannot block, and
  the `Stop` advisory handler has no blocking path by construction.
- Fires on a change, not on a state, and dedupes through `advisory-<session>.json`.
- Fails open and silent. A style file that cannot be read or parsed produces no advisory.
- **The module is the checker, not the styles.** The five styles are a preference and are
  deliberately absent from `$LwgModuleRegistry` and `config.json` — `Get-LwgConfig` fails
  open, so a corrupt config would switch a style flag *on*, which is the wrong polarity for
  a preference, and it would inflate a banner count that must keep meaning governance
  coverage. A checker has the normal advisory polarity and belongs in the registry like
  the other five.
