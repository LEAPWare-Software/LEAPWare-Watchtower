<!--
Thanks for contributing.

If this fixes a SECURITY issue (a credential reaching a log, the status line or an injected
context block; setup or uninstall damaging a settings.json), do not open a public PR first — see
SECURITY.md and report privately so a fix and a disclosure can be coordinated.
-->

## What this changes

<!-- One or two sentences. What is different after this PR that was not before. -->

## Why

<!-- The defect, or the need. State the evidence, not the intention. If you measured something,
     say what you measured and how. -->

Refs #

<!-- `Refs #N`, never `Closes #N`. `.github\scripts\pr_issue_ref.ps1` runs in CI and refuses a body
     with no issue reference, and refuses a closing keyword bound to an issue number: an issue here
     closes only when it is fixed with a case proven RED before the fix, and a merge cannot know
     that. The maintainer closes it by hand, naming the evidence. -->

## Type of change

- [ ] Bug fix
- [ ] New module or module behaviour
- [ ] New or changed hook
- [ ] Test / harness
- [ ] Documentation
- [ ] CI / tooling

---

## Verification

**Paste real output. A summary of a run is not a run.**

### Every file in `tests\`

```
<!-- The RESULT: and EXIT: lines from each of
     powershell -NoProfile -ExecutionPolicy Bypass -File tests\gate_delegate.ps1
     powershell -NoProfile -ExecutionPolicy Bypass -File tests\supervision.ps1
     powershell -NoProfile -ExecutionPolicy Bypass -File tests\setup_merge.ps1
     powershell -NoProfile -ExecutionPolicy Bypass -File tests\stop_behaviour.ps1
     powershell -NoProfile -ExecutionPolicy Bypass -File tests\uninstall_footprint.ps1
     powershell -NoProfile -ExecutionPolicy Bypass -File tests\config_behaviour.ps1
     powershell -NoProfile -ExecutionPolicy Bypass -File tests\toggle_behaviour.ps1
     powershell -NoProfile -ExecutionPolicy Bypass -File tests\state_resolution.ps1
     powershell -NoProfile -ExecutionPolicy Bypass -File tests\doctor_behaviour.ps1
     powershell -NoProfile -ExecutionPolicy Bypass -File tests\subagent_scan.ps1
     powershell -NoProfile -ExecutionPolicy Bypass -File tests\payload_guard.ps1
     powershell -NoProfile -ExecutionPolicy Bypass -File tests\workflow_guard.ps1
     powershell -NoProfile -ExecutionPolicy Bypass -File tests\portability_scan.ps1
     powershell -NoProfile -ExecutionPolicy Bypass -File tests\doc_claims.ps1

     That list is `git ls-files -- tests/*.ps1`. If it and the tree disagree, the tree is right
     and this block is stale - fix it here. -->
```

- [ ] Every one of them exits `0`.
- [ ] Not all run — and I have said which, why, and what that leaves unverified.

<!-- 1 and 2 are not passes. 2 means the harness aborted and NOTHING was checked. -->

```
<!-- And the guards under .github\scripts\, which CI also runs:
     powershell -NoProfile -ExecutionPolicy Bypass -File .github\scripts\redfirst_annotations.ps1 -Live
     powershell -NoProfile -ExecutionPolicy Bypass -File .github\scripts\version_declarations.ps1 -Live
     powershell -NoProfile -ExecutionPolicy Bypass -File .github\scripts\identity_scan.ps1
     (.github\scripts\pr_issue_ref.ps1 reads a pull request body, so CI is where it fires.) -->
```

<!-- ELEVEN SUITES TEST BEHAVIOUR, each through a real pipe into a real child process:
     gate_delegate covers delegate_gate; supervision covers send_liveness_gate, completion_audit
     and orphan_watch; setup_merge covers the installer's statusline and hooks merge AND the
     surviving reporting surfaces; stop_behaviour covers the two turn-end hooks and the advisory
     modules behind them; uninstall_footprint covers the uninstaller's state-data deletions and
     its attribution; config_behaviour and toggle_behaviour cover the two commands that write
     config.override.json; state_resolution covers the state-directory resolver;
     doctor_behaviour covers the doctor's driven checks; subagent_scan covers the SubagentStart
     fast path and is the only coverage context_injection has; payload_guard covers what the
     shipped payload discloses.
     NO PER-SUITE CASE COUNT IS WRITTEN HERE ANY MORE, DELIBERATELY. tests\doc_claims.ps1 cannot
     read a number inside a parenthesis - a named hole in its header, not an oversight - and this
     block is what fell down it: three of the counts sat at 81, 153 and 10 through the wave that
     moved them to 124, 169 and 22, and two of them then sat at 169 and 22 through the wave that
     moved them to 177 and 25, while every quantity the guard DOES recognise was swept both times.
     Each suite prints its own RESULT: line; that is the number, and it cannot go stale.
     THE OTHER THREE ASSERT NOTHING THIS PLUGIN DOES: workflow_guard parses every file under
     .github\workflows\; portability_scan scans tracked files for machine-specific literals;
     doc_claims checks that the counts stated in tracked pages match the tree, and will fail
     your build if you write a number that has gone stale - fix the sentence, not the guard.
     tests\gate_regression.ps1 went on 30 July 2026 with the destructive_gate module and
     tests\deny_parity.ps1 went the same day with secret_scan; nothing replaced what either
     covered, because nothing here inspects a command or a credential any more. So unless your
     change lands inside what those suites reach, nothing automated will catch you - say below
     exactly what you exercised and how. -->

### Regression test

**A test that passes both before and after proves nothing.** For a bug fix, the case must fail
against the parent commit.

- [ ] N/A — this is not a bug fix.
- [ ] I added a case, ran it against the parent commit, and it **failed**. Case ID(s) and both
      results:

```
<!-- If your fix is inside what one of the eleven behavioural suites covers - any of the three
     gates, the installer's statusline and hooks merge, either turn-end hook, the uninstaller's
     state-data deletions, the state-directory resolver, a driven doctor check, either command's
     write to config.override.json, the SubagentStart fast path, or what the shipped payload
     discloses - ADD THE CASE TO THAT SUITE and paste its per-case line from before and after.
     Anywhere else there is no harness to hang a case on, so include the script you wrote. Take
     the red from a THROWAWAY CLONE at the parent commit carrying only your test change, never
     from your working tree. e.g.
     my_case.ps1 against <parent sha>: EXIT: 1 (case failed - the defect was present)
     my_case.ps1 against this branch:  EXIT: 0
-->
```

This repo's old suite was 67/67 green while five gate bypasses were open. Those gates and that suite
are gone; `tests/gate_delegate.ps1` covers the one gate that replaced neither of them, and every case
in it was confirmed to fail against a deliberately broken gate before it was kept. The reason this
section exists has not changed.

### Doctor

```
<!-- powershell -NoProfile -ExecutionPolicy Bypass -File lw-watchtower\bin\lwg-doctor.ps1 -Quiet -->
```

- [ ] Exit `0`, or exit `2` with the warnings explained above.

### What I did NOT verify

<!-- Required if anything is untested, which is most things. A green CI run says: every tracked
     .json and .ps1 parses, no workflow reaches a runner GitHub does not host, uses a secret or
     grants itself more than read, no tracked file names a machine, delegate_gate still refuses what
     it declares, send_liveness_gate and completion_audit deny and abstain where they say they do,
     the installer's statusline merge still preserves what it was not asked to touch, the pinned
     turn-end cases still behave for the observing modules stop_behaviour.ps1 reaches, the
     uninstaller deletes exactly the state data it listed, the state-directory resolver answers what
     it claims to, the driven doctor checks ask the question they claim to, the two config writers
     back up and re-check the file they replace and touch only the override, the SubagentStart fast
     path answers the global modules flag, no tracked file carries a disclosure the payload guard
     knows the shape of, no page states a count the tree contradicts, the five version declarations
     agree with each other, every commit identity is on the allowlist, and this body carries an
     issue reference. That is the WHOLE list. It says nothing about whether the modules it does
     reach advise the RIGHT thing (several have one to three cases on at most two properties, and
     context_injection has exactly one property run), nothing about the modules no suite reaches at
     all, and nothing about the SessionStart banner, the status line, the installer's hooks section,
     or the uninstaller's settings.json attribution. Be explicit about the difference between
     "I verified this" and "I read the source and believe this". -->

---

## Checklist

- [ ] One logical change. I have not reformatted or refactored code I was not otherwise touching.
- [ ] Line endings unchanged for files I did not otherwise edit — the repo is pure LF.
- [ ] Every `.json` I touched parses. Every `.ps1` I touched parses with
      `[System.Management.Automation.Language.Parser]::ParseFile`.
- [ ] No personal paths, usernames, machine names, tokens or emails in the diff
      (`$env:USERPROFILE`, not a literal profile path).
- [ ] Documentation updated in this PR if behaviour changed.
- [ ] **I have not documented a command, flag or behaviour that does not exist**, and every number I
      wrote comes from a file I read or a measurement I took.
- [ ] I have not described a non-zero exit code as a pass.
- [ ] The body above carries `Refs #N` for every issue this touches, and no closing keyword bound to
      an issue number.
- [ ] Every commit here is authored by an identity on `.github/scripts/identity_scan.ps1`'s
      allowlist.

### If this adds or changes a module

- [ ] `$LwgModuleRegistry` in `lw-watchtower/lib/common.ps1` and the `modules` block in
      `lw-watchtower/config.json` agree — `/lw-watchtower:doctor`'s `config-registry` check is what
      says so.
- [ ] The flag genuinely gates the behaviour, with **zero** side effects when off — no log record, no
      state written, no subprocess started, no file opened.
- [ ] `gate` only if it can actually block. If it warns, it is `observe`. **Exactly three modules in
      the registry is `kind = 'gate'` today — `delegate_gate` and `send_liveness_gate` on
      `PreToolUse`, `completion_audit` on `Stop` and `SubagentStop`, all three shipping switched
      off** — so a `gate` here means you are adding the fourth. Say so explicitly, say what it
      denies, and read [`docs/gates-removed.md`](../docs/gates-removed.md) first.

<!-- THE UNGRAMMATICAL "modules in the registry IS `kind`" ON THE LINE ABOVE IS LOAD-BEARING, not a
     typo. tests\doc_claims.ps1's gate-module-count rule has two patterns and this sentence is the
     only site in the tree that its FIRST pattern matches; that pattern requires the literal
     `is `kind`. Correcting the verb to "are" makes the pattern match nothing anywhere, and a pattern
     that matches nothing ABORTS the whole guard by its own contract - measured, on 3 September 2026,
     by making exactly that edit. The wording is fixable, but only together with the pattern, and
     the guard is not this file's to edit. -->

- [ ] `implemented` only if the code exists and can fire. If the data it needs does not reach a hook,
      it is `planned`, with the evidence recorded.

### If this adds or changes a hook

- [ ] Registered in exec form (`command` + `args`), never `shell: "powershell"`.
- [ ] The hook exits 0 on every path **unless it is a `PreToolUse` gate denying a call**, in which
      case it writes the reason to stderr and exits **2**. Only exit 2 blocks; **exit 1 is a
      non-blocking error and the tool runs anyway**, so a gate that exits 1 has silently failed open.
      Emit the `permissionDecision: "deny"` stdout envelope as well — the two channels fail open in
      different circumstances and emitting both can never turn a deny into an allow.
- [ ] I have stated its measured cost, and accounted for the fact that a hook registration cannot be
      made conditional — every user pays for it on every matching event, including those who switch
      the module off.
