# Output styles

Answer preferences on **two axes** — verbosity (`brief`, `default`, `verbose`) and **plain** — shipped
as Claude Code *output styles* in [`output-styles/`](../output-styles/), which a plugin may supply and
which Claude Code auto-discovers from that directory name.

An output style is appended to the system prompt at session start. It therefore costs nothing per
prompt, is covered by prompt caching, and cannot decay the way an instruction buried in a long
conversation does. **It also cannot be switched mid-session, and it cannot block anything.** Both
halves of that trade are load-bearing; read [What these cannot do](#what-these-cannot-do) before
treating any style as a control.

`outputStyle` is a single string, so the two axes cannot be composed at selection time. The six
combinations are shipped as five files plus the built-in Default:

| | plain **off** | plain **on** |
| --- | --- | --- |
| verbosity `brief` | [`lw-watchtower-brief`](../output-styles/lw-watchtower-brief.md) | [`lw-watchtower-brief-plain`](../output-styles/lw-watchtower-brief-plain.md) |
| verbosity `default` | **Default** (built in) | [`lw-watchtower-plain`](../output-styles/lw-watchtower-plain.md) |
| verbosity `verbose` | [`lw-watchtower-verbose`](../output-styles/lw-watchtower-verbose.md) | [`lw-watchtower-verbose-plain`](../output-styles/lw-watchtower-verbose-plain.md) |

| Style | Effect |
| --- | --- |
| [`lw-watchtower-brief`](../output-styles/lw-watchtower-brief.md) | A 150-word ceiling on prose, first sentence answers the question, no preamble, no closing summary, findings before methodology, three parallel facts go in a table. |
| [`lw-watchtower-verbose`](../output-styles/lw-watchtower-verbose.md) | The inverse axis: reasoning shown, alternatives named with the reason each lost, evidence quoted in full rather than summarised, assumptions labelled *checked* or *not checked*, numbers instead of quantifiers. **No word ceiling and, deliberately, no word floor** — a floor is met by padding, so the file bans restatement and hedging in the same breath as it removes the limit. More content, never more words for the same content. |
| [`lw-watchtower-plain`](../output-styles/lw-watchtower-plain.md) | Written for a competent adult who does not work in software. Seventeen listed terms must be explained on first use, acronyms expanded, no `file:line` and no shell commands in the body unless asked. |
| [`lw-watchtower-brief-plain`](../output-styles/lw-watchtower-brief-plain.md) | Brief and plain. Where they collide, clarity outranks the ceiling: never leave a term unexplained to stay under 150 words. |
| [`lw-watchtower-verbose-plain`](../output-styles/lw-watchtower-verbose-plain.md) | Verbose and plain. Where they collide, clarity outranks completeness: leave out the tenth mechanism rather than name it in words the reader cannot parse — and say that you left it out. |
| **Default** (built in) | Neither axis. This is the off switch. |

**There is no "off" file, deliberately.** A shipped off style would be Claude Code's built-in Default
plus a wrapper — same instructions, one more thing to keep in step. Selecting Default already turns
both axes off.

## verbosity is one key with three levels

The `verbosity` command — removed on 2 September 2026 — set **one** `config.json` key, `output_style.verbosity`, which held exactly
one of `brief`, `default` or `verbose`. Setting a level unsets the others by construction, and
`default` is the level at which this axis does nothing.

**It was two commands until 30 July 2026.** `lw-watchtower:brief` and `lw-watchtower:verbose` — named without a
leading slash here because neither exists any more — wrote this same key, so `on` claimed it and
`off` released it to `default` only when the command being switched off was the one holding it. Two
switches over one three-value setting described a model that was not there. The stored value did not
change in the merge.

**Two independent booleans were rejected, and not on taste.** A per-repo override is merged *key by
key*, so `brief` could have been `true` globally while `verbose` was `true` for one repository — a
contradiction assembled from two writes that were each valid on their own, and one that no
write-time exclusivity rule inside the toggle script could have prevented, because such a rule holds
only where that writer runs and survives neither a hand edit nor a merge. One key holding one value
cannot contradict itself at any scope. The full transition table is in
[Commands](commands.md#verbosity-is-one-key-with-three-levels).

`plain` is a genuinely independent axis — plain English is orthogonal to length — so it stays its own
boolean **and its own command**. It was explicitly kept separate when the two verbosity commands were
merged: folding a jargon rule into a length setting would have been the same category error in the
other direction.

## The never-suppress block

All five styles carry the same block, byte for byte, and it overrides every other rule in the file it
sits in. Neither brevity, nor length, nor plain language may ever remove: that something failed,
**with the exact error text verbatim**; a step skipped, not run, or not verified; anything
irreversible done or about to be; anything waiting on the operator; a blocker and what blocks it; the
difference between *I verified this* and *I was told this*; or any warning a gate or an advisory
raised. These are reported in full even where that triples the length of the answer.

The styles say why in their own text: *brevity that drops a failure is a lie by omission, and plain
language that softens a failure is the same lie in a nicer voice.* The two verbose files add the
third: *length that buries a failure* is the same lie again, and they name themselves as the styles
most able to commit it — an omission is invisible in a long answer in a way it is not in a short one.
The word ceiling is written as the first rule to yield, not the last, and the verbatim-error rule
explicitly overrides the ban on jargon — an error is reproduced exactly as emitted even where it is
full of terms the style otherwise forbids, with any plain reading added *after* it and never instead.

The block, and the term list, are delimited by marker comments
(`<!-- lw-watchtower:never-suppress begin -->`, `<!-- lw-watchtower:jargon begin -->`) so that the copies can be
compared mechanically rather than by eye:

```powershell
Get-ChildItem output-styles\*.md | ForEach-Object {
  $t = [IO.File]::ReadAllText($_.FullName)
  $b = $t.IndexOf('<!-- lw-watchtower:jargon begin -->'); $e = $t.IndexOf('<!-- lw-watchtower:jargon end -->')
  if ($b -ge 0) { "$($_.Name)  $((Get-FileHash -InputStream ([IO.MemoryStream]::new(
      [Text.Encoding]::UTF8.GetBytes($t.Substring($b, $e-$b)))) -Algorithm SHA256).Hash.Substring(0,12))" }
}
```

The markers are also **the term list's single source of truth**. Nothing duplicates them into
`config.json`, and the compliance check designed in
[`style-compliance-check.md`](style-compliance-check.md) is specified to read them back out of the
style file that is actually active. A copy of the list held anywhere else would drift from the
instruction the model was given, and would then report violations of a rule nobody was told.

## Switching

Run `/config` and choose **Output style**. Your choice is written to the `outputStyle` key in
`.claude/settings.local.json`. The standalone `/output-style` command was deprecated in Claude Code
2.1.73 and removed in 2.1.91; `/config` or the settings key are the two remaining routes.

The `verbosity` and `plain` commands did **not** replace that step and did not write the settings
key. They went on 2 September 2026 for exactly that reason, and with them went the five style files
this page describes — so this page documents a feature the tree no longer carries. What they did was record where you want each axis, work out which of the five style files that pair
implies (the grid above, since `outputStyle` is a single string), check the file is present, read back
what the settings key currently says, and print the manual step. Recording a preference and
activating a style are two different things, and the command says which one it did.

An output style is read into the system prompt once, at session start, so neither route takes effect
in the session you run it in.

After editing a file in `output-styles/`, run `/reload-plugins` or restart — a plugin's non-skill
components are not picked up live.

## What these cannot do

Four limitations, and none of them is a detail.

- **No mid-session switching.** The style is part of the system prompt, which is read once at session
  start. A change takes effect after `/clear` or in a new session, and `/clear` discards the
  conversation. Choosing a style is a decision made *before* the work, not during it.
- **One at a time.** `outputStyle` is a single string, so there is no composing an axis with an
  unrelated style — which is the entire reason `lw-watchtower-brief-plain` and `lw-watchtower-verbose-plain`
  exist as their own files rather than as combinations. Two axes, one string, five files: adding a
  third axis would need eleven.
- **Advisory, not enforcement. Nothing can block assistant text before you see it.** There is no hook
  between the model and the transcript; no event fires with the answer in hand and a decision channel
  attached. `Stop` sees `last_assistant_message` *after* it has been rendered. So a style is a
  request the model is very likely to honour, in the same way a system prompt is, and it is nothing
  stronger than that. **Anyone describing this as *enforcing* an output style is repeating this
  plugin's founding defect** — the same overstatement as counting an unbuilt module as coverage, or
  calling an advisory a gate.
- **Subagents are unaffected.** An output style applies to the main conversation only, because a
  subagent runs its own system prompt. Every worker dispatched with the `Agent` tool answers in its
  own voice regardless of the style, and a forked conversation is the sole exception since it
  inherits the parent's prompt. In a delegating setup, where most text originates in a worker's
  report, this removes most of the surface these styles appear to cover. Standing instructions for
  workers belong in [`context/worker_facts.md`](../context/worker_facts.md), which `context_injection`
  hands to every dispatch.

There is no compliance check yet. What one could and could not measure — and why the half that
matters, the never-suppress block, is **not measurable from the answer text at all**, since an
omission leaves no trace in the text that omits it — is written up in
[`style-compliance-check.md`](style-compliance-check.md).

## Why an output style rather than a hook

The obvious alternative is a `UserPromptSubmit` hook that appends the rules to every prompt. It was
rejected for the reason recorded under [`mission_drift`](modules.md#mission_drift): a hook
registration cannot be made conditional, so that process is spawned on **every prompt** whether the
preference is on or off, at a measured **285 ms** each — one development machine's figure for
PowerShell 5.1 interpreter startup, so a slower machine pays more of it, not less. An output style
costs one system-prompt append per session and is then cached. The hook buys mid-session switching with a per-prompt tax on
everyone who never turns it on.

## Why they are not modules

`verbosity` and `plain` are deliberately **absent** from `$LwgModuleRegistry` and from
`config.json`'s `modules` block, and they must stay that way for two reasons.

- **Polarity.** `Get-LwgConfig` fails *open*, which is right for a guardrail and wrong for a
  preference: a corrupt or unreadable config would switch a style flag **on**, silently changing how
  every answer is written. The built-in defaults carry no `output_style` block at all, so an
  unreadable config resolves to verbosity `default` and plain off — neither axis switched on.
- **Coverage counting.** The banner's `n/10` counts governance modules. An answer-formatting
  preference is not governance, and inflating that number with one would be the same defect the count
  exists to prevent. The tenth module, `delegate_gate`, is counted precisely because it *is*
  governance — note that only its **flag** sits outside the `modules` block, not the module.

## Frontmatter, and what is verified

Each file sets two fields, and both were checked against the published schema rather than assumed:

| Field | Value here | Why |
| --- | --- | --- |
| `description` | one line | What the `/config` picker shows. |
| `keep-coding-instructions` | `true` | **Defaults to `false`**, and a custom style that leaves it out *drops Claude Code's built-in software-engineering instructions* — how it scopes changes, writes comments and verifies work. These styles change the voice, not the engineering, so leaving this out would have quietly removed far more than it added. |
| `name` | omitted | The file name becomes the style name, so the picker entry and the file agree by construction. |
| `force-for-plugin` | omitted | It exists, and it applies a style automatically whenever the plugin is enabled, overriding the operator's own `outputStyle`. Installing a governance plugin must not silently rewrite how every answer is worded. Off is the default; it stays off. |

**No `plugin.json` change is needed, and adding one would be a regression.** `output-styles/` is
already a default-scanned location. The manifest's `outputStyles` key *replaces* that default rather
than extending it, and Claude Code 2.1.140 and later warns about the ignored folder when a plugin has
both.

**Unverified, and stated rather than assumed:** whether a plugin-supplied style's name is namespaced
in the `outputStyle` value (as plugin skills are), and therefore what exact string hand-editing the
settings key requires. The `/config` picker writes whatever is correct; the literal string has not
been confirmed against a live install, and neither has the discovery of this directory from a
junction-loaded plugin.
