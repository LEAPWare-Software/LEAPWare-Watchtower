---
description: "LW-WATCHTOWER session banner - which governance modules are active, planned or switched off, how many gates are live, and the session mode"
allowed-tools: "Bash(powershell:*)"
---

Run this command and show the user its output **verbatim**:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/bin/lwg-status.ps1"
```

Add `-Brief` to the command if the user asked for just the summary without the module table.

The script is the answer. It reads the module registry in `lib/common.ps1`, which is the
single source of truth for what this plugin actually does, and the same `Get-Lwg*` helpers
the SessionStart banner calls.

Rules for reporting it:

- **Do not recompute, re-count, or re-word the numbers.** If the script says 9 of 10 modules
  are active, say 9 of 10. Do not add up the table yourself and offer a different figure.
- **Report BOTH gate numbers, and never collapse them.** The script prints gates `SHIPPED` and
  gates `LIVE`, and by default they are `1` and `0`. Saying "one gate" alone claims protection
  that is switched off; saying "no gates" alone hides a capability the operator owns and was
  never told about. Report the `GATES` block with them.
- **The `STATE` column is the only one that reports behaviour.** `ENABLED` is an intention.
  Never describe an enabled-but-unbuilt module as running, or as coverage.
- **Do not upgrade the mode word — and do not downgrade it either.** `observe-only` is the expected
  steady state, and while it holds it is the whole truth: nothing is blocking. The ladder returns
  `observe-only` as soon as the **live** gate count is zero, which it is until someone runs
  `/lw-watchtower:delegate on`. But `partial` and `enforcing` became **reachable again** when
  `delegate_gate` shipped on 30 July 2026, so if the script prints one of them, print it. Reporting
  a session that really is refusing calls as `observe-only` is the same class of lie as the reverse,
  pointing the other way, and it teaches the operator to distrust a guardrail that works.
- `unverified` means the self-check never ran, which is not `observe-only` and not a pass.
  `degraded` means a probe failed. Do not collapse them.
- If the mode prints as `unknown`, say so. It means no SessionStart record was found, and the
  mode genuinely cannot be stated without one.
- If the script exits 3 it could not produce a report. Say that nothing is known, rather than
  describing the plugin from memory or from these instructions.

This command **reports**; it does not check anything. It will happily describe a plugin that is
perfectly configured and completely switched off. To find out what is broken, use
`/lw-watchtower:doctor`.

A gate count of `0` means no gate is **live**, not that none exists. One ships — `delegate_gate` —
and it is switched off by default, which is why `SHIPPED` and `LIVE` are reported as separate
numbers. Its blocking *is* tested, by `tests/gate_delegate.ps1` — one of nine behavioural suites in
`tests/`, and the only one that covers a gate. Of the modules this banner counts, seven are exercised
by something — `mission_drift`, `failure_capture`, `context_pressure`, `docs_coupling`,
`git_hygiene` and `log_rotation`, the last four by one to three cases apiece on at most two
properties, and `context_injection` on one property only —
and the other two, `verification_gate` and `self_health`, are exercised by
nothing. What the banner reports is which modules are loaded and observing, and nothing more than
that — a module can be counted here and be completely broken.
