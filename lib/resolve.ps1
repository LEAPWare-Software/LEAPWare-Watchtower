#requires -version 5
<#
  Mark this session's outstanding health faults as resolved.

  Absorbed in Phase 2 from ~/.claude/health/resolve.ps1. Only the log location
  changed - it now resolves through Get-LwgStateDir like the rest of the plugin.

  NOT TO BE INVOKED DIRECTLY. bin/lwg-resolve.ps1 is what `/lw-watchtower:resolve` and
  the `lw-healer` role run, and commands/resolve.md forbids this file in bold.
  The reason is in the resolution below: `CLAUDE_PLUGIN_DATA` is set for plugin
  HOOKS and for nothing else, so outside a hook `Get-LwgStateDir` falls through
  to the discovery rule, picks one of several data directories by modification
  time, and can write the marker into a log the live plugin never reads. The
  wrapper enumerates and PRINTS every candidate, refuses on a tie, requires
  -Session, refuses when the session appears in no candidate log, and reads the
  marker back after writing it. None of those checks is available to a caller of
  this file, however carefully it behaves, because they are not in this file.

  It is kept rather than deleted because it is the primitive that wrapper wraps
  and the two callers that named it have been repointed. Appends a Resolved
  marker to health.jsonl; the status line counts faults occurring AFTER the most
  recent marker, so a marker in the RIGHT log clears HH back to green.

  Usage:
      powershell -NoProfile -ExecutionPolicy Bypass -File resolve.ps1 -Note "restarted stalled agent"
      powershell -NoProfile -ExecutionPolicy Bypass -File resolve.ps1 -Session <id> -Note "..."

  With no -Session, the session id is taken from the newest record in the log,
  which is this session (the lw-healer runs inside it).

  On the failure_capture gate: this script warns when the module is off but still
  writes the marker. It is an operator's remediation tool, not a monitor. Refusing
  would strand HH red for any fault already recorded before the flag was flipped,
  with no way left to clear it.
#>

param(
    [string]$Session,
    [Parameter(Mandatory = $true)][string]$Note
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

$LogPath = Join-Path (Get-LwgStateDir) 'health.jsonl'

if (-not (Test-LwgModule -Name 'failure_capture')) {
    Write-Warning "failure_capture is disabled in config.json - writing the marker anyway; no new faults are being recorded."
}

if (-not (Test-Path $LogPath)) { Write-Output "No health log at $LogPath - nothing to resolve."; exit 0 }

if (-not $Session) {
    foreach ($line in (Get-Content $LogPath -Tail 200)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $r = $line | ConvertFrom-Json } catch { continue }
        if ($r.session) { $Session = $r.session }
    }
}
if (-not $Session) { Write-Output "Could not determine a session id; pass -Session explicitly."; exit 1 }

$rec = [ordered]@{
    ts      = (Get-Date).ToUniversalTime().ToString('o')
    event   = 'Resolved'
    session = $Session
    note    = $Note
}
# THE RETURN VALUE IS THE ANSWER, AND IT USED TO BE PIPED TO Out-Null.
#
# Add-LwgLine returns $true on success and $false when all five retry attempts
# failed - that return is the ONLY signal the append happened; it catches, so
# nothing throws. This file discarded it and then printed, unconditionally, that
# the marker was written and that HH returns to green, and exited 0. When the
# append failed the operator and the calling agent were both told the fault was
# cleared. It was not: the indicator stays red, the fault stays outstanding, and
# the only artefact of the attempt was a success message.
#
# `| Out-Null` is the right call at this plugin's other Add-LwgLine sites, where
# the append is a side effect. This is the one site where the append IS the
# operation and its result is the script's entire output. lib/session_start.ps1
# already reads the same return as a session-degrading fault, so the two files
# handled one failure mode in opposite directions in the same session.
#
# The retry ladder exists because health.jsonl is genuinely contended - the
# supervisor writes it on five events and the status line reads it on every
# render - so five failures inside ~300 ms is the case the function was built to
# report: an unwritable state dir, a full disk, a lock held by an antivirus or a
# backup agent.
#
# WHAT THIS DOES NOT FIX, and it is the reason bin/lwg-resolve.ps1 exists: a
# $true return means the append did not throw, not that the marker landed in the
# log the LIVE plugin reads. Outside a hook CLAUDE_PLUGIN_DATA is unset, so
# Get-LwgStateDir above picks one of several data directories by modification
# time, and this script still cannot tell you it picked the right one. Only
# bin/lwg-resolve.ps1 enumerates the candidates, refuses on a tie and reads the
# marker back. commands/resolve.md forbids invoking this file for that reason
# and the prohibition stands.
if (-not (Add-LwgLine -FileName 'health.jsonl' -Line ($rec | ConvertTo-Json -Depth 4 -Compress))) {
    Write-Output "FAILED to append the Resolved marker to $LogPath after five attempts - NOTHING was written. The fault is still outstanding and the status line stays red. Use /lw-watchtower:resolve, which verifies the write by reading it back."
    exit 1
}

Write-Output "Resolved marker written for session $Session - status line HH returns to green."
