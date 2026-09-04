# Portability: no local environment dependencies in tracked files

## The rule

**Nothing true only of one machine may be stated in a tracked file as though it were true
everywhere.** No account name, no computer name, no user-profile path, no absolute interpreter or
tool path, no private folder hierarchy, no hardcoded install location.

This is not a style preference. It is enforced: [`tests/portability_scan.ps1`](../tests/portability_scan.ps1)
scans every file `git ls-files` reports and **fails the build** on a hit. It runs in the
`fast-checks` job of [`.github/workflows/ci.yml`](../.github/workflows/ci.yml), in about two seconds,
on every pull request.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\portability_scan.ps1
```

| Exit | Meaning |
| --- | --- |
| `0` | Every tracked file was scanned; nothing machine-specific found. |
| `1` | At least one violation. Each is reported as `file:line: <matched text> - <rule>`. |
| `2` | The scan **aborted**, or it could not read every tracked file, or a **scoped rule was applied to no file at all**, or a **single glob** — in a rule's scope or an allowlist entry's `files` — **matched no scanned file** without declaring `may_be_empty`; the tree was not fully checked. Not a pass. An enumeration returning zero files is an abort, and `2` takes precedence over `1` — a run that did not read everything, or did not ask everything, cannot report "checked, and dirty" either. |

Add `-ShowAllowed` to see every match the allowlist excused, with the entry that excused it.

## Why this exists

Three shipped defects, all the same defect:

- **The status line went blind on every machine but one.** `statusline/statusline.ps1` resolved the
  plugin root from a literal install path. Where the layout differed, the `HH` and `GM` segments <!-- doc-claims:ignore -->
  found nothing and rendered *not installed* — permanently, silently, and with no error. The root is
  now derived; see the comment above `LwgPluginRoots`. (`GM` is named here because it existed at the
  time; it was deleted on 30 July 2026 and the line is left as the record it is.)
- **One laptop's machine facts were injected into every subagent.**
  [`context/worker_facts.md`](../lw-watchtower/context/worker_facts.md) is passed verbatim into every dispatch on
  every machine, and it asserted an absolute interpreter path, an assumed minor version, one shell's
  stale-`PATH` quirk, and a claim about installed runtimes that was false even on the machine it
  described.
- **A security module matched nothing on a fresh install.** `verification_gate`'s agent-name arrays
  listed only roles that exist in one operator's untracked personal agents directory. Everywhere
  else it was enabled, counted toward the session banner's coverage number, reported healthy — and
  could never match a single record, so it could never warn. (`verification_gate` is named here
  because it existed at the time; the module was removed on 2 September 2026 and the line is left as
  the record it is.)

Each was found by an audit, which is a person remembering to look. This project's whole thesis is
that a control which overstates itself is worse than no control; a rule enforced only by remembering
is such a control. Hence a scanner rather than a paragraph.

## What to write instead

| Instead of | Write |
| --- | --- |
| A hardcoded plugin root | `${CLAUDE_PLUGIN_ROOT}` when the CLI sets it, else `$PSScriptRoot` and walk up |
| A path under your profile | `$env:USERPROFILE` (PowerShell) or `%USERPROFILE%` (docs), composed with `Join-Path` |
| An absolute interpreter path | Name the requirement (*Windows PowerShell 5.1*), resolve the binary from `PATH` |
| Your clone location | A `$Repo` variable the reader sets once, with a neutral default |
| Your account or computer name | Nothing. Neither is ever needed. |
| A measurement quoted as a constant | The number, labelled as measured on one machine |

Two further rules that follow from the same principle:

- **Never hardcode a file list.** Enumerate with `git ls-files`. CI's JSON check once named three
  files by hand and therefore never validated a fourth added later; the scanner itself would be
  worthless with a hardcoded list, so it has none.
- **A machine-specific fact that is genuinely needed goes in an untracked file.**
  `context/worker_facts.local.md` is gitignored, read after the tracked facts, and appended to the
  same injected block. That is where an interpreter path or a personal preference belongs.

## The allowlist

Some legitimate things look exactly like violations. The scanner carries an allowlist as a **data
table at the top of the file** — not conditionals scattered through the code — and

> **every entry states its reason, on the entry.**

An entry without one is how an allowlist rots into a list of things that were annoying once, and a
reviewer cannot tell a legitimate exemption from a silenced defect without it. The scanner prints
the table on every run with a per-entry hit count, so an entry that has stopped excusing anything is
visible rather than quietly accumulating.

**What qualifies**

- **Derived forms.** `${CLAUDE_PLUGIN_ROOT}`, `$PSScriptRoot`, `$env:USERPROFILE` — these mostly
  need no entry, because every path rule is anchored on a literal drive letter and a derived path
  has none.
- **Universal Windows roots named as things to refuse.** `C:/Windows`, `C:/ProgramData`,
  `C:/Program Files` and the bare `C:/Users` root are deny-rule and gate-rule *targets*. They exist
  identically on every Windows install.
- **Deliberate sentinels.** Fixed non-existent profiles chosen so a test compares equal on any
  machine, including a CI runner.
- **Reader placeholders.** Angle-bracketed stand-ins that instruct the reader to substitute their
  own value.
- **Attributed observations.** A measurement labelled as one machine's, in
  [`architecture.md`](architecture.md). The attribution must be on the same line, within the three
  lines above, or heading the table the value sits in — a mention elsewhere in the file excuses
  nothing. It covers paths only: an attribution is never a reason to name an account or a host.
- **Historical quotations in [`CHANGELOG.md`](../CHANGELOG.md)**, inside a backtick span. An entry
  about a removed literal must quote it to be evidence. The changelog is never executed and nothing
  builds a path from it — and this exemption deliberately does *not* cover account or computer
  names.

**What does not qualify:** the scan being inconvenient. If it fires on something genuinely portable,
add an entry *with the reason*. If it fires on something machine-specific, fix the file.

**Every glob is asserted, one at a time, and a glob that reaches nothing fails.** A rule may be
scoped to path globs and an allowlist entry names the files it applies to; both lists are matched
against `git ls-files` output, so a rename breaks the entries whose subject moved and leaves the
ones that did not. The result is almost never zero — it is *narrowed*, and a narrowed scope is a
rule still "applied" and barely asking. Measured: the payload move took one rule's scope from 33
files to **1 of 94**, eight of its nine globs dead beside a ninth that still matched
`.claude-plugin/marketplace.json` at the repository root, and the run exited `0`. So the check is
per glob rather than per rule: a glob matching no scanned file exits `2` and is named, in a
`NOT REACHED` line beside the `NOT ASKED` line a wholly dead scope still writes.

**A glob that is meant to be empty says so.** Writing
`@{ glob = 'docs/not-yet.md'; may_be_empty = 'the page this defends is not written; see #NNN' }`
in place of the bare string exempts that glob and prints the reason beside the zero in the reach
ledger. A dead glob with no declaration is a defect; a declared one is a stated expectation a
reviewer can disagree with. That is what makes asserting a *defensive* allowlist entry safe: the
correct deletion — a glob naming something that no longer exists, or does not exist yet — is
declared rather than tolerated. Delete the glob with its subject, or declare it.

Read the two numbers in the ledger together: `0` excused of `2` in reach is a defensive entry doing
its job; `0` excused of `0` in reach is an entry that cannot fire at all.

**Self-exemption.** Two files must contain the strings the rules look for: the scanner (the patterns)
and this page (the examples below). Neither is skipped wholesale — each marks the exact exempt lines
with a region marker, and only those two files may declare one. A marker anywhere else is itself
reported as a violation, so the mechanism cannot be used as an escape hatch.

## Examples

<!-- LWG-SCAN-REGION: begin -->

Refused:

```powershell
$root = 'C:\Users\jsmith\LEAPWare-HQ\leapware-software\leapware-watchtower'
$lib  = 'C:\Users\jsmith\.claude\skills\lw-watchtower\lib\common.ps1'
& 'C:\Program Files\Python312\python.exe' probe.py
if ($env:COMPUTERNAME -eq 'DESKTOP-4K2P9QX') { ... }
```

Accepted:

```powershell
$root = if ($env:CLAUDE_PLUGIN_ROOT) { $env:CLAUDE_PLUGIN_ROOT } else { Split-Path -Parent $PSScriptRoot }
$lib  = Join-Path $root 'lib\common.ps1'
$home_ = $env:USERPROFILE
if (-not $home_) { $home_ = 'C:\Users\UNKNOWN' }   # sentinel, never a real profile
```

<!-- LWG-SCAN-REGION: end -->

## Related

- [CONTRIBUTING](../CONTRIBUTING.md#portability-no-local-environment-dependencies) — the contributor
  rule and the PR checklist item.
- [Testing and CI](testing.md) — the other checks in the same `fast-checks` job.
- [Architecture](architecture.md) — how the plugin root and state directory are resolved.
