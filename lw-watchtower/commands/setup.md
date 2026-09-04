---
description: "LW-WATCHTOWER guided installer - detects what is already there, asks in plain language, then writes statusLine and hooks one section at a time, each behind its own diff and its own yes. It installs no permissions.deny rules and no protection"
allowed-tools: "Bash(powershell:*), AskUserQuestion"
disallowed-tools: "PowerShell"
---

You are running an installer on someone else's machine. **You are the interface, not the
installer.** Every decision, every rule, every path and every diff comes out of
`bin/lwg-setup.ps1`. Your job is to run its steps in order, put its questions to the operator,
paste its output **verbatim**, and never write anything it has not printed first.

Assume the person answering has never heard of a hook, a glob or a JSON key. The bar is that
they finish this unaided.

## The five steps, in order

### 1. Look first

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/bin/lwg-setup.ps1" -Step detect
```

Show the output **verbatim**. It writes nothing, so there is nothing to confirm.

Then read the `THINGS THAT ARE ALREADY WRONG` block, if there is one, **out loud in your own
words** before asking anything. Those faults exist now and running setup does not fix them. An
ambiguous state directory in particular means this plugin is installed twice and its history is
split; say so plainly rather than moving past it.

Exit `2` here means findings, not failure. Exit `3` means detection did not complete - stop and
say so; do not guess at the machine's state from these instructions.

### 2. Ask the six questions

Detection ends with a `QUESTIONS TO PUT TO THE OPERATOR` block. **Use those words.** They were
written for someone non-technical and they carry the recommended answer. Ask them with
`AskUserQuestion`, one at a time, in the order given. Do not add questions of your own, do not
reword them into jargon, and do not answer any of them yourself.

**There is no longer a question about destructive commands or about credential files, and there is
no longer a parameter for either.** Both protections were removed on 30 July 2026 at the owner's
instruction, hooks and rules alike. `-DestructiveGate` and `-SecretGate` are not accepted-but-inert
parameters that select nothing - they are **not parameters at all**: `bin/lwg-setup.ps1` is
`[CmdletBinding()]`, so passing either one is a binding error before a line of the script runs,
nothing is written, and the exit code is `1` with the error on stderr. `-Section permissions` is
refused the same way, by the `ValidateSet` on that parameter. If an operator asks for either gate,
say it does not exist rather than offering a flag; if a caller still spells one, the script tells
them, which is why the parameters were removed rather than kept loudly inert.

Collect the answers into the flag string the block tells you to build. Every later command
carries that same string.

### 3. Two sections, two separate confirmations

For each of `statusline`, `hooks`, **in that order**:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/bin/lwg-setup.ps1" -Step diff -Section <name> <answer flags>
```

- Show the diff **verbatim**. It lists every line that would be added and states what is left
  alone. It writes nothing.
- Ask the operator, for **this section only**, whether to go ahead. **One yes buys one section.**
  Never ask once for both, never carry a yes forward, and never treat "yes, do the setup"
  from earlier as consent to any particular section.
- On yes, run the `TO APPLY` line the diff printed, exactly as printed - it already carries the
  `-BaseHash` value. Do not invent that value and do not reuse an older one.
- On no, say that section is unchanged and **move to the next one**. Declining one section
  cancels nothing else.

If the operator wants to see it happen without committing to it, add `-DryRun` to the apply
line: it builds and validates the merge, prints the size it would have written, and touches
nothing.

**Read the apply exit code and report it as it is:**

| Exit | Meaning | How to report it |
| --- | --- | --- |
| `0` | written, or already in that state | done |
| `1` | a write landed and did not check out, **or** an argument was rejected before the step ran | **read stdout before you report it** - the two are told apart there. See below |
| `4` | the settings file changed under us | **`settings.json` was not written.** Something else edited the file between the diff and the write. Run the diff again, show the operator the NEW diff, and ask again. Do not re-run the apply with the old hash. **Read the block before you say "nothing was written":** the check is now made before the section's first write of any kind, so it normally is nothing — but if the file moved *during* the run the block lists the file(s) that had already landed and names the `.bak` beside each. If it lists any, say so; refusing does not undo them and `-Step rollback` does not restore them. |
| `5` | refused on a precondition | nothing was written; say which precondition and carry on with the other sections |
| `3` | the step fell over | unknown - do not describe the file's state from memory |

`4` is not an error to retry. It is the guard doing its job.

**`1` is the one code here that means two different things, and stdout is what separates them.**
The script itself sets `1` only after a step it could not verify - a write that failed, a merged
result that moved a key it should not have, a rollback whose result does not parse - and in every one
of those cases it has already printed the reason, and where a rollback applies, the line to run.
PowerShell's own parameter binding also exits `1`, and that happens **before a line of the script
runs**: a `-Step`, `-Section`, `-StatusLineMode` or answer-flag value outside its allowed set never
reaches the code at all. That failure prints **nothing on stdout** and a
`ParameterArgumentValidationError` on stderr, and **nothing was written**. Report it as a rejected
argument and fix the argument. Reporting it as the first kind invents a fault that did not happen and
offers a rollback line that was never printed.

**A flag NAME this script does not define is rejected too, and that is a change in this release.**
`bin/lwg-setup.ps1` now declares `[CmdletBinding()]`, so an unrecognised `-Something` is a
parameter-binding error **before a line of the script runs**: exit `1`, nothing on stdout, and
`A parameter cannot be found that matches parameter name 'Something'.` on stderr. Nothing was
written. Report it exactly as you would report a bad *value* — a rejected argument, fix the argument.

**Until v0.3.0 it was ignored in silence**, and the difference is worth knowing because it is why the
change was made. With a plain `param()` block PowerShell bound `-Something` as a positional argument
and discarded it, so the step ran with its defaults and exited `0` as though the flag had been
honoured: `-DryRunn` performed a real 15 KB write to `settings.json` and reported success, and
`-StatusLineModee skip` silently installed the default `copy`. Both now exit `1` and write nothing.
The UAT that found it is the v0.3.0 acceptance record, which is a maintainer note in
`.github/notes/uat-report.md` and is not shipped with this plugin.

Check the flags you pass against the `-> pass ...` lines the detect step printed anyway. The binding
error tells you a name is wrong; it cannot tell you a *correct* name carries the answer you meant.

### 4. Check it

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/bin/lwg-setup.ps1" -Step doctor
```

Show it **verbatim** and report its verdict as printed. A `FAIL` here after a clean install is a
real finding about the machine, not a blemish on your work - say both things. Setup that cannot
fail is not setup.

### 5. If it needs undoing

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/bin/lwg-setup.ps1" -Step rollback
```

Restores the newest backup this command took, after keeping a copy of the current file. Add
`-DryRun` to see which backup it would use. Backups are never deleted.

## Rules you do not get to bend

- **Nothing is written that was not shown first.** If you find yourself about to edit
  `settings.json` with `Edit` or `Write`, stop: that is the one thing this command exists to
  avoid. The script is the only writer.
- **Never bundle the two sections into one question.** `statusLine` and
  `hooks` are two different powers over the machine.
- **Do not promise a single deny rule, and do not look for a section that would write one.** There
  is no `permissions` section any more: `Get-DenyGroups`, `New-PermissionsPlan` and the
  `permissions` value of `-Section` are all deleted, and passing that value is refused by the
  parameter's `ValidateSet`. The installer wrote 181 rules in six groups until 30 July 2026, when
  all six went at the owner's instruction — the four destructive groups with the command gate, the
  two secret groups with the secret gate. Never describe setup as installing protection, because it
  installs none.
- **Setup has never removed a rule and still does not.** An operator who was set up before
  30 July 2026 still has those rules in their own `settings.json` and the CLI still evaluates
  them. Running setup again neither renews nor deletes them. If they want them gone, that is
  `/lw-watchtower:uninstall -Apply -RemovePermissions`, or their own editor.
- **Do not soften the honest bits.** The diff says a status-line copy can drift silently; it says
  wiring hooks alongside a discoverable plugin makes everything fire twice. Repeat all of it.
  An installer that oversells what it installed is how a switch wired to nothing ends up
  believed.
- **Running it twice is safe and is meant to be.** A second run adds nothing, takes no backup
  and does not touch the file's timestamp. If someone asks whether it is safe to re-run, the
  answer is yes.
- The module ON/OFF switchboard is `/lw-watchtower:config`, and this command deliberately does
  **not** touch it. The shipped defaults are in [`config.json`](../config.json), a tracked file
  nothing writes; an operator's own settings go to `config.override.json` under the state
  directory. Point the operator at the command.
- This command installs **wiring, and only wiring** — a status line, hook registrations and a
  look at the helper roles. It writes **no** `permissions.deny` rule: the function and the section that once wrote them are
  both deleted, and `-Section` accepts `statusline` and `hooks` only. The hook
  registrations do now include one `PreToolUse` entry, `delegate_gate`, and registering it installs
  **no behaviour** — it is switched by `interaction.delegate` and ships off. There is deliberately
  no install-time question about it: an operator who declined it here and later ran
  `/lw-watchtower:delegate on` would own a switch wired to a hook that was never registered. A finished
  install leaves a session in `observe-only` mode, which is the intended end state and not a partial
  one. It does not report what is running; that is `/lw-watchtower:doctor`.
