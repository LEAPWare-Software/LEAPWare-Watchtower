---
description: "LW-WATCHTOWER update - fetch what is new, list what it would change and what needs re-approval afterwards, fast-forward only, then re-run the doctor"
allowed-tools: "Bash(powershell:*)"
---

Run this and show the output **verbatim**:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/bin/lwg-update.ps1"
```

That fetches and reports; it merges nothing. To actually take the update, re-run with `-Apply`,
which does `git pull --ff-only` and nothing else. `-Offline` skips the network on a check-only run
and **is refused together with `-Apply`** — `git pull` fetches, so the two cannot both be honoured,
and the run reports `[FAIL] pull REFUSED` and merges nothing rather than fetching anyway.
`-SkipDoctor` skips the health check afterwards, and `-TimeoutMs` (default `8000`) bounds every git
call so a hung network reports UNKNOWN instead of stalling the turn.

**`-Root <path>` is a test override and is not for an operator.** It points the script at a different
checkout to fetch and report on. It exists so the update path can be exercised against a throwaway
clone; pointed at a real second clone it will happily report on the one Claude Code is **not**
loading, which is the mistake the `[WARN] loaded-copy` row below exists to catch. Do not offer it,
and do not pass it unless the user asked for that checkout by name.

**On the junction route** - the plugin loaded through a directory junction into this checkout -
`git pull` **is** the update mechanism: there is no install step to re-run and no plugin cache to
refresh. That is the route this script is written for, and it is not the only one. **A marketplace
install updates through the marketplace machinery instead**, and pulling in a clone that is not the
loaded copy changes nothing Claude Code reads - which is exactly what the `[WARN] loaded-copy` row
below is for. Report that row rather than assuming the pull landed where it matters.

Rules for reporting it:

- **Report the NEEDS RE-APPROVAL section in full, even when it is empty.** It is the reason this
  exists rather than a one-line instruction to run `git pull`. A pull can change hook
  registrations, flip module flags, or leave the installed status line silently stale, and none
  of that is visible in git's own output.
- **A `[FAIL] worktree` row is not something to work around.** It means uncommitted changes. Do
  not offer to stash, reset, checkout or force anything - report it and let the user decide what
  to do with their own work. Since 3 September 2026 this plugin writes none of its own
  configuration into the checkout, so a dirty tree here is work somebody did in this repository -
  not something `/lw-watchtower:config` or `/lw-watchtower:delegate` left behind.
- **`[WARN] loaded-copy` means the two paths could NOT be reconciled — not that the checkout is
  wrong.** The row prints both spellings: the junction's target and the checkout being updated.
  If they are different directories, pulling here changes nothing Claude Code loads; if they are
  the same directory reached by another spelling — a `SUBST` drive, an 8.3 short name, a UNC path
  — the row cannot tell, and says so. Report both paths and what the row could not establish; do
  not assert either reading. Arriving *through* the junction is now `[OK]` and is the normal route.
- **A fetch that could not run is UNKNOWN, never up to date.** No network, no git, or a timeout
  all report as warnings; "0 commits behind" from a stale fetch is not evidence of anything.
- **The doctor's exit code is its verdict, not yours.** Exit `4` from this command means the
  doctor FAILED after a pull **this run actually made** — report the `[FAIL]` rows it printed and
  do not describe the update as successful. A doctor failure on a run that merged nothing is
  exit `2` and is a finding about the tree as it already stood, **not** about an update; report it
  as such rather than implying one happened. Exit `2` also covers a pull that was killed
  mid-operation, whose `[FAIL] pull` row says the tree state is UNKNOWN — that is not "nothing was
  changed", and it names `.git\index.lock` as the first thing to check.
- **Do not describe anything as live until a new session starts.** Hook registrations, commands
  and agents are read at session start. A pull that lands mid-session changes files, not
  behaviour.
- If the status line row says the installed copy differs from the repo copy, **do not copy it
  over without asking which direction is wanted**. A fix made to the live file is lost the moment
  the repo copy is installed on top of it, and nothing else on this machine compares the two.

`/lw-watchtower:doctor` is what this runs afterwards, and it checks wiring only. **Much of what a pull can
change is covered by no behavioural test.** `tests/` holds 14 files, 11 of them behavioural:
`gate_delegate.ps1` covers `delegate_gate`, `supervision.ps1` covers the other two gates and
`orphan_watch`, `setup_merge.ps1` covers the installer's `statusline`
merge and what its `hooks` section decides — **and, in sections that are not about the
installer, the reporting surfaces that survive it: `statusline/statusline.ps1` and this
command, `bin/lwg-update.ps1`, which nothing exercised in any form before
3 August 2026** — `stop_behaviour.ps1` covers the stop path and the turn-end advisories,
`state_resolution.ps1` covers the `SessionStart` hook, its probes and its state-directory
resolution, `uninstall_footprint.ps1` covers the uninstaller's state-data deletions,
`doctor_behaviour.ps1` covers two of the doctor's
10 checks, `config_behaviour.ps1` and `toggle_behaviour.ps1` cover the two writers of
`config.override.json`, `subagent_scan.ps1`
covers the `SubagentStart` fast path, and `payload_guard.ps1` covers what the shipped payload
discloses. The other three, `workflow_guard.ps1`,
`portability_scan.ps1` and `doc_claims.ps1`, check the tree and the documentation rather than
behaviour. **Nothing covers the installer's `hooks` section end to end or the uninstaller's
`settings.json` edits**, so a pull
that changes either is covered by review and by nothing else — say that rather than implying
the doctor validated the change.
