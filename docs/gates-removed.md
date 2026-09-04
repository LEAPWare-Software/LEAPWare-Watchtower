# Gates were removed deliberately

**Read this before adding a gate back.** It is not an argument against ever doing so — the owner
wants blocking capability re-addable, and this page is what makes that possible. It is the record of
what the last attempt cost, what it taught, and — since 30 July 2026 — **what a future gate now has
to rebuild from nothing**, written down here because the code that would have taught it is deleted.

**Gates have since been added back — three of them**, and this page is not out of date because of
it — see [What is true right now](#what-is-true-right-now) at the foot, which says exactly what they
do and do not do. Nothing else here was softened by their arrival; each of them avoids every failure
this page records by never doing the thing that produced them.

Four things are separate and must stay separate:

- **What was removed** — both gates, on 30 July 2026, each by an explicit owner decision. The
  narrative is in [Modules § Both gates were removed](modules.md#both-gates-were-removed) and the
  commits are named in [CHANGELOG.md](../CHANGELOG.md). That is not repeated here.
- **What is left to build on, and what is not**, which is the next two sections. The second of them
  corrects an earlier version of this page.
- **What the attempts taught**, which is the bulk of it.
- **What is live today**, which is the last section, and which corrects this page a second time.

## What was kept, so a gate can be re-added

None of this is protection. It is the scaffolding a future gate would otherwise have to rebuild,
and it was kept rather than deleted for that reason alone. It is **much less than this page
originally listed** — see the next section.

| Kept | Why it matters to a future gate |
| --- | --- |
| `kind = 'gate'` in `$LwgModuleRegistry` ([`lib/common.ps1`](../lw-watchtower/lib/common.ps1)) | The registry can still **express** a gate. `$script:LwgGates` is built by a loop over the registry rather than replaced with a literal `@()`, so setting that one field makes the gate count, `Get-LwgActiveGates`, the mode ladder and the banner all follow with no other change. The status line no longer follows — it has no governance segment left to light. |
| `Get-LwgSessionMode` ([`lib/common.ps1`](../lw-watchtower/lib/common.ps1)) | `enforcing` and `partial` are unreachable today only because the live gate count is zero. The ladder is guarded by that count, not by an assumption about which gates exist, so both words come back on their own. |
| Every deny family in [`bin/lwg-uninstall.ps1`](../lw-watchtower/bin/lwg-uninstall.ps1) | The only code left that knows what the original 181 `permissions.deny` rules looked like. A machine installed before the removal still carries them. |

**`Get-DenyGroups` no longer exists**, and neither do `-SecretGate` and `-DestructiveGate`. This page
said until 3 September 2026 that the function returned an empty table and the two parameters selected
nothing — that was true of an earlier tree and describes a state a reader can no longer be in. The
function was deleted with the permissions section it fed; the two parameters were deleted from
`bin/lwg-setup.ps1`'s param block, so passing either is a PowerShell binding error before any script
code runs, rather than a question whose answer selects nothing. The only mentions of all three names
left in the payload are comments in `bin/lwg-setup.ps1` and `bin/lwg-uninstall.ps1` recording that
they went. The mechanism that *writes* a settings section is intact and is what a future gate would
reuse; the deny-group builder is not.

## The trip ledger was NOT kept — a gate has to rebuild it

**This section corrects what this page used to say.** Until 30 July 2026 the ledger was listed above
as kept scaffolding, on the argument that a future gate would write a trip and everything downstream
would already work. That is no longer true, and it is stated here rather than left to be discovered
by someone who reads the old promise and plans around it.

Later the same day, by a further explicit owner decision, the `tripped` command **and the open trips
themselves** were removed. Gone:

| Removed | What a future gate has to rebuild |
| --- | --- |
| `lib/trips.ps1` | The whole ledger format, and every verb over it: writing a trip on a deny, classifying its target, closing it on a verified fact, sweeping at turn end. This was the largest single piece of scaffolding and none of it survives. |
| `lib/ack_trip.ps1` | Acknowledging a trip that has **no fact to close on** — the escape hatch that stops a ledger becoming a permanently red indicator. Do not omit this the second time. |
| `bin/lwg-tripped.ps1`, `commands/tripped.md` | The operator's only route to see what was refused and to close it, per item. |
| The `GM` segment in `statusline/statusline.ps1` | The continuous indicator. `GmState`, `GmTrips`, `GmSessionKey`, `GmSeg`, the outstanding-trip advisory row and the `Ago` helper it used are all deleted. `GmConfig` survives, but only because the threshold block reads it. |
| The ledger-open branch in `lib/session_start.ps1` | One call to `Initialize-LwgTripLedger`, guarded by the live gate count. It must only ever create a ledger that does **not** already exist — `SessionStart` fires again on resume, clear and compact, and wiping the ledger on those clears real outstanding trips on an event that means nothing about them. |
| The trip sweep in `lib/stop_advisories.ps1` | The turn-end auto-close. It belongs in that script rather than in a hook of its own: it needs no new data, so its own hook would cost a whole PowerShell process (~285 ms measured) every turn for nothing. **Every close must rest on a fact the process verified — there must be no "and it has been a while" branch.** A guardrail that forgets on a timer is the false green the ledger existed to replace. |
| The ledger **files** in the state directory | 12 `trips-*.json`, holding 64 uncleared trips between them. Backed up to `trips-backup-20260730/` in the same directory before removal, not destroyed. |

What survives and still helps: the event log is untouched, so the historical `GateDeny` records are
still on disk. The `sitrep` command counted them under `GOVERNANCE` as history until it went on
2 September 2026; nothing counts them now. That is an
audit trail, **not** a ledger — nothing can clear an entry in it, which is exactly why the
per-session ledger was built in the first place.

**On a machine installed before 3 August 2026 those records are in a file this plugin no longer
writes, and no longer reads.** The trips described above were written to `lw-gmhh.jsonl` in the
`lw-gmhh*` state directory; the product rename moved both to `lw-watchtower.jsonl` under
`lw-watchtower*`, and nothing migrates the old file. So the sentence above is true of a session
started today and NOT true of the records this page is about — those are readable, but only by
opening the old file yourself. See `## [0.4.0]` in `CHANGELOG.md` for what the rename does and does
not move.

**The order to rebuild in, if a gate comes back:** the format first (`lib/trips.ps1`), then the
acknowledge path, then the writer on the gate's deny branch, then the turn-end sweep, and the
indicator last. An indicator shipped before the acknowledge path is a red glyph with no route out,
which is the specific defect the ledger replaced and would replace again.

## The four failed fix attempts, and what they taught

All four were attempts to fix **one** hole in `destructive_gate`: a here-document body was walked as
ordinary shell source, so a stray quote inside it swallowed everything after it and the gate ALLOWED
the command that followed. Real, not theoretical — re-run against GNU bash 5.3.9, the trailing
`git push --force origin main` executed.

| # | Commit | What it did | Outcome |
| --- | --- | --- | --- |
| 1 | `498762d` | Read a quoted here-doc body as text, **and skip a body that "provably cannot run"** | Reverted (`fb426d1`) |
| 2 | `8b19975` | Read a body as data, **and exempt one only when the line cannot run it** | Reverted (`083116e`) |
| 3 | `95b54cb` | Isolate every body as its own chunk with fresh quote state, **and exempt nothing** | Shipped; still holed |
| 4 | `804c7cc` | Rescan the region after an unclosed quote with quotes ignored, **appending** fragments | Shipped; removed with the gate hours later |

**Lesson 1 — every added cleverness opened a hole; the isolation itself opened none.** Attempts 1
and 2 carried the same correct isolation as attempt 3, plus one extra decision: *this body cannot
execute, so do not scan it*. That decision, and the machinery built to serve it, produced **five**
bypasses between them — a comment pre-pass that took a bare CR for a word boundary, and a shadowing
scan that missed `eval 'git(){ sh; }'` because the parens sit inside quotes. The isolation opened
**zero** across both attempts. The exemption was the entire failure surface.

**Lesson 2 — a change that can only ever add coverage is safe by construction; one that decides
something is safe is not.** Attempt 4 was accepted because of its shape: the first pass's fragments
are untouched and still come first, and the rescan only *appends*. A change that can only add
fragments cannot turn a deny into an allow, and no argument about bash semantics is needed to
believe it. Contrast the rejected alternative — extending the fail-closed quote check into body
chunks — which would also have refused every legitimate `git commit -F -` whose prose contains an
apostrophe. That collision is unresolvable, so it was not attempted; over-blocking was accepted
elsewhere instead, and stated.

**Lesson 3 — the test suite never once caught a bypass.** The suite was **67/67 green while five
bypasses were open**. Every hole in the record — the five destructive-gate bypasses, the apostrophe
swallow, the five the reverted attempts shipped, the four terminator-line shapes — was found by
someone *trying to break the gate*, then turned into a regression case afterwards. Growth of the
suite (67 → 147 → 227 → 233) is a record of what break-attempts found, not evidence that testing
found anything. **A gate with a green suite and no independent break-attempt should be assumed
broken.**

**Lesson 4 — assertions about the shell must be executed, not recalled.** `<<\EOF`, `<<E'O'F` and
`<<"E"OF` all name the delimiter `EOF`; a trailing `|` continues the pipeline past the terminator;
an unterminated body runs to end of input; the **terminator line is scanned, not discarded** — so
`<<'git push --force'` makes the terminator a command. That last one had been missed by both
reverted attempts and produced four live bypasses. Each of these was confirmed against real bash
before being relied on.

**Lesson 5 — a parser that models a shell will keep losing to the shell.** Line continuations,
`eval`/`xargs` wrapper peeling, git's unambiguous-prefix option parsing (`git reset --ha`), NTFS 8.3
short names (`GIT~1/config`), a `..`-unnormalised temp-root allowlist: five separate bypasses, five
separate corrections, all of the same kind. The gate was never wrong about its rules; it was wrong
about what the input meant.

## What a future attempt must do differently

1. **Decide what the gate is for before writing it.** `permissions.deny` was the only layer here
   that could not fail open, because the CLI evaluates it before any hook runs. A `PreToolUse` hook
   fails open on every error path by design. A hook is an advisory with teeth, not a control.
2. **Never add an exemption, an allowlist or a safety determination.** Three of the four attempts
   above are the evidence. If a body, a fragment or a command *might* run, scan it.
3. **Prefer changes that can only add coverage.** If a change can turn a deny into an allow, its
   correctness rests on an argument about the shell rather than on the shape of the diff.
4. **Budget for an independent break-attempt, not for tests.** Tests encode what was already
   understood. Every bypass in this repository's history came from an adversarial attempt by someone
   other than the author. A regression case must fail before its fix —
   [CONTRIBUTING.md](../CONTRIBUTING.md) makes that a build rule, and it survives the gate that
   taught it.
5. **State the over-blocking.** Attempt 3 refused a commit message beginning with a backtick. That
   was the right trade and it was written down where an operator hitting it would find it. A gate
   whose false refusals are undocumented gets disabled wholesale.
6. **Test safety is not negotiable.** Use invented command names and assert on which rule fired.
   Never run a real destructive command, never against real binaries, never elevated — a worker
   testing a gate fix once deleted Git's own `etc` directory and made a live `gh repo delete` call
   believing both were stand-ins. That standing order outlived the suite that carried it.
7. **Re-declare the module honestly.** Add the entry to `$LwgModuleRegistry` with `kind = 'gate'`
   and to `config.json`'s `modules` block in the same change, keeping the two lists identical, and
   register the `PreToolUse` hook in `hooks/hooks.json`. A gate declared and not registered — or
   registered and not declared — is the founding defect this plugin exists to catch.
8. **Budget for the ledger.** It is not a detail of the gate; it is most of the work, and it is gone.
   Rebuild it in the order given above, and do not ship the indicator first.

## What is true right now

**Three gates ship, and every one of them ships switched off.** Until later on 30 July 2026 this
section said there was no `PreToolUse` key, no registry entry of kind `gate`, and nothing here
blocking anything. All three of those statements are now false, and they are corrected here rather
than left for a reader to trip over, in the same spirit as the ledger correction above. This section
also said until 3 September 2026 that `delegate_gate` was *the only* gate; two more were built on
1 August 2026 and it has not been the only one since.

`delegate_gate` was built hours after the two removals, as the one blocking switch on the plan that
research found fully buildable. `send_liveness_gate` and `completion_audit` followed on 1 August 2026,
built from a measured failure rather than from this page's plan. What exists — the authoritative list
is the `kind = 'gate'` entries in `$LwgModuleRegistry`
([`lib/common.ps1`](../lw-watchtower/lib/common.ps1)), not this page:

- `hooks/hooks.json` **has a `PreToolUse` key again**. `delegate_gate`'s entry has matcher
  `Edit|Write|NotebookEdit|Bash|PowerShell`, invoking [`lib/gate_delegate.ps1`](../lw-watchtower/lib/gate_delegate.ps1) in
  exec form; `send_liveness_gate` registers on the same event for `SendMessage`.
- Three registry entries **are** of kind `gate` — `delegate_gate`, `send_liveness_gate` and
  `completion_audit`. The first row of the *What was kept* table has stopped being a description of a
  capability held in reserve; it is the field the shipped gates turn on.
- Each declares its switch on its own registry entry's `switch` field rather than as a `modules`
  flag — `interaction.delegate`, `supervision.send_liveness` and `supervision.completion_audit` — and
  **all three ship `false`**.

The rest of this section is about `delegate_gate`, which is the gate this page's lessons were written
against. `send_liveness_gate` and `completion_audit` have a section each in
[Modules](modules.md#send_liveness_gate), written against what each one refuses and what each one
lets through.

What it does, and what it does not:

| | |
| --- | --- |
| **Does** | With `interaction.delegate` on, refuse `Edit`, `Write`, `NotebookEdit`, `Bash` and `PowerShell` for any call carrying no `agent_id` — that is, one that did not come from a subagent. |
| **Does** | Block with the reason on stderr and **`exit 2`**. Only exit 2 blocks a `PreToolUse` call; **exit 1 is a non-blocking error and the tool runs anyway**, so a gate that exits 1 has silently failed open. |
| **Does** | Fail safe in two opposite directions on purpose — unreadable stdin **denies** (no `agent_id` was read, and input the gate could not read is not evidence a subagent made the call); an unreadable or absent `config.json` **allows** (the switch is off by default, and the alternative makes a bad config a lockout on the file that has to be fixed). |
| **Does not** | Read the path, the command, the content, or `tool_name` **to decide**. It reads `payload.tool_name` exactly once, *after* the decision to refuse has been made, only to name the refused tool in the message — a payload carrying none is refused identically, with the text falling back to *"this tool"*. See [modules.md](modules.md#delegate_gate). It carries **no exemption, no allowlist and no safety determination** — Lesson 1 and rule 2 above are exactly why, and the absence is the design. |
| **Does not** | Refuse anything a subagent does, or check that a dispatch was any good. |
| **Does not** | Replace either removed gate. Nothing inspects a shell command; nothing inspects a path or the bytes of a write; the installer still writes **no** `permissions.deny` rules at all, and has no code left that could — the deny-group builder is deleted. Every cost listed in the CHANGELOG entries for those two removals is still being paid. |
| **Does not** | Block anything on a default install, because it ships off. The live gate count is `0`, and a healthy session still reads `observe-only`. |

`enforcing` and `partial` are reachable words again — but only for an operator who sets the switch,
and nothing sets it for them. A gate that is shipped and off is a capability, not a protection, and
`/lw-watchtower:doctor` reports `SHIPPED` and `LIVE` as separate numbers so the two cannot be read as one.

**No trip ledger came back with it.** A denial is a `GateDeny` line in `lw-watchtower.jsonl` and nothing
tracks it as an open item. There is still no ledger, no reader for one, no `tripped` command and no
governance segment on the status line — every word of *The trip ledger was NOT kept* above stands,
and it stands for this gate too.

**Three gates are not the lessons being over.** Each of them avoids the entire failure surface this
page documents by not having one. `delegate_gate` parses no shell, models no language, enumerates no
spellings and decides nothing about whether something is safe; `send_liveness_gate` and
`completion_audit` decide on evidence about a message and a turn, never on the content of a command
or a write. Building all three tested **none** of the five lessons. They
are still owed in full by any future gate that has to look at what a call actually contains.
