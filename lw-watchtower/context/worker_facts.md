# LW-WATCHTOWER worker facts - injected into EVERY subagent, at dispatch time.
#
# WHY THIS FILE EXISTS
# Claude Code snapshots CLAUDE.md into a subagent's context when the PARENT
# SESSION starts. An instruction added mid-session therefore never reaches a
# worker dispatched afterwards. That is not theoretical: a security classifier
# refused a legitimate edit because its snapshot of CLAUDE.md predated the
# instruction authorising it. lib/subagent_start.ps1 reads THIS file on every
# single dispatch, so what a worker is handed is always current.
#
# THIS FILE IS TRACKED, SO IT SHIPS TO EVERY MACHINE. INVARIANTS ONLY.
# It is the same bytes on every install, so anything it asserts is asserted on
# machines nobody here has ever seen. A private fact stated here - an absolute
# interpreter path, which runtimes are installed, what the PATH resolves, which
# agent roles exist, what the owner wants done with a finished branch - is
# distributed as universal truth and is wrong everywhere but one laptop. That is
# the founding defect this plugin exists to catch, so it is not committed here.
#
# PER-MACHINE FACTS: context/worker_facts.local.md
# OPTIONAL and gitignored. If it exists beside this file, subagent_start.ps1
# appends it AFTER the invariants, in the same injected block, under the same
# comment/blank-line rules and the same 2000-character ceiling. If it does not
# exist, only this file is injected - no error, no warning, nothing logged. That
# is where an interpreter path, a stale-PATH quirk, the local agent-name prefix
# or an owner's push preference belongs.
#
# NOTHING IS PROBED AT DISPATCH TIME, and that is measured rather than assumed.
# A Get-Command that FINDS its target costs ~9-25 ms in a fresh PowerShell 5.1
# process, but a Get-Command that MISSES costs 600-1360 ms - it walks the whole
# PATH and the module autoload cache before giving up. Absence is exactly what a
# probe would be for, so the probe's own worst case is its normal case, on a hook
# whose floor is ~300 ms and whose leash is 5 s. State a machine fact in the
# .local.md file instead.
#
# FORMAT
# A line whose first non-space character is '#' is a comment and is NOT
# injected. Blank lines are dropped. Every other line is injected verbatim as
# hookSpecificOutput.additionalContext. Keep it plain ASCII.
#
# KEEP IT UNDER 80 WORDS
# Every dispatch pays for this text and a worker handed a wall of standing
# rules reads none of it. Only facts that GO STALE, and that workers
# repeatedly get wrong, belong here. Anything durable belongs in CLAUDE.md,
# which is snapshotted once and costs nothing per dispatch.
#
# Edit this file and the next dispatch picks it up. No code change, no
# restart, no reinstall.

Plugin invariants - machine-independent, true on every install:
- This plugin's hooks run under Windows PowerShell 5.1: `[int]` rounds rather than truncating, and `[datetime]::UnixEpoch` does not exist.
- Test a stdin-reading script with `cmd /c "type in.json | powershell -File s.ps1"`; a PowerShell pipe never reaches [Console]::In.
- Nothing machine-specific is stated here - interpreter paths, what is on PATH, which agent roles exist. Check, do not assume.
