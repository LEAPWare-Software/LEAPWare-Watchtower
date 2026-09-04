# Output styles — removed

**This plugin ships no output styles.** The `output-styles/` directory, the five style files in it,
and the `/lw-watchtower:plain` and `/lw-watchtower:verbosity` commands that selected between them
were all deleted on 2 September 2026. Nothing in this release reads a verbosity level or a plain
flag, and `config.json` has no key for either. The removal is recorded in
[CHANGELOG.md](../CHANGELOG.md).

This page is a tombstone. It is still here because published pages link to it —
[README.md](../README.md) twice, [SECURITY.md](../SECURITY.md) at the anchor below, and this
directory's own [index](README.md) — plus the maintainer note
`.github/notes/style-compliance-check.md`, which is not published. A link that 404s is worse than a
page that says the subject is gone. It describes nothing that ships.

## What these cannot do

Nothing, because they do not exist. What the heading used to record is worth keeping in one
sentence, because it is why the feature went: an output style was an instruction in the system
prompt, so a model could be asked to drop a preamble and simply not do it, with nothing between the
model and the transcript to check. No hook fires with an assistant answer in hand and a decision
channel attached, and `Stop` sees `last_assistant_message` *after* it has been rendered.

**So nothing on these pages should be read as a promise that this plugin controls what the
assistant says to you.** It does not, and it never did. What it can refuse is a tool call, through
the three gates in [Modules](modules.md#gates-and-what-counts-as-one) — all three of which ship
switched off. See [Limitations](limitations.md).

## Frontmatter, and what is verified

Nothing is verified here, because there are no style files to verify. The frontmatter this heading
described belonged to the five deleted files.
