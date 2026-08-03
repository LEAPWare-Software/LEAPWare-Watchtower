#requires -version 5
<#
  LW-WATCHTOWER resolve - clear the outstanding health faults for ONE session, or say
  why it will not.

      powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-resolve.ps1 -Session <id>
      powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-resolve.ps1 -Session <id> -Note "..." -Apply

  Backs /lw-watchtower:resolve. It replaces the way lib/resolve.ps1 is invoked, and it
  exists because that script has a silent no-op in it.

  THE DEFECT THIS FILE FIXES

  lib/resolve.ps1 resolves its log through Get-LwgStateDir and then, with no
  -Session, infers the session from the last record in whatever file that
  returned. Both halves fail together outside a hook:

    * CLAUDE_PLUGIN_DATA is set for plugin HOOKS and for nothing else. An agent
      shell is not a hook, so the resolution falls through to the discovery rule -
      and on this machine that rule has THREE candidates to choose between
      (lw-watchtower, lw-watchtower-inline, lw-watchtower-skills-dir). It picks one by mtime.
    * The session is then read off the tail of whichever file that was. If that
      file belongs to a different install, the tail is some other session, hours
      stale.

  The result is a Resolved marker written to the wrong log for the wrong session,
  and the words "status line HH returns to green" printed over it. A success
  report about a change that did not happen - the precise defect this plugin
  exists to catch, shipped inside the plugin itself.

  WHAT THIS DOES INSTEAD

    1. Enumerates every candidate data dir and PRINTS them, with what each one
       holds for the session in question. Nothing is chosen invisibly.
    2. Pins the write target: -DataDir wins, then CLAUDE_PLUGIN_DATA, then the
       single candidate whose log actually holds this session. A tie is an
       ambiguity and exits 2 rather than picking one.
    3. Pins the session: -Session is required. Inference from a log tail is
       available only behind -InferSession, prints the record it inferred from
       and its age, and refuses outright when that record is stale.
    4. REFUSES, loudly, when the session is not in any candidate log. This is the
       case lib/resolve.ps1 reports as success.
    5. Refuses when there is nothing outstanding to clear - a marker written over
       a clean session is another success report about nothing.
    6. Writes only under -Apply, and then RE-READS the logs and recounts the
       faults. If they did not go to zero it says so and exits 4.

  Faults are counted with the same ladder ~/.claude/statusline.ps1 uses, over the
  same union of logs, including its cross-file dedup - if the two disagreed, this
  command would clear a number the operator never saw.

  Exit codes:

      0  the dry run completed, or the marker was written and verified
      1  REFUSED - stated reason; nothing was written
      2  the data dir could not be pinned from the evidence; nothing was written
      3  this script could not complete
      4  the marker was written and the faults did NOT clear
#>

param(
    # The session to clear. Required unless -InferSession is passed.
    [string]$Session,

    # Recorded in the marker. Required to write; a marker with no note is an
    # unexplained edit to an evidence log.
    [string]$Note,

    # Pin the data dir explicitly. Use this when the candidate table below shows
    # more than one plausible home for the session.
    [string]$DataDir,

    # Opt in to inferring the session from the newest record in the pinned log.
    # This is the behaviour that caused the defect, so it is never the default and
    # it refuses on stale evidence.
    [switch]$InferSession,
    [int]$MaxAgeMinutes = 120,

    # Write the marker. Without it nothing is appended to any log.
    [switch]$Apply,

    # Show the candidates and the fault picture, then stop.
    [switch]$List
)

$ErrorActionPreference = 'Stop'

$script:SavedEnv = $env:CLAUDE_PLUGIN_DATA

function Use-LwgDataDir {
    <#
      Point every Get-Lwg* helper at ONE directory for the rest of this call.
      CLAUDE_PLUGIN_DATA is the authoritative input to Get-LwgStateDirInfo, and
      -Refresh is what defeats its memoisation - without that this process would
      keep answering with the first directory it resolved.
      Process-local: nothing outside this PowerShell process sees it.
    #>
    param([string]$Path)
    $env:CLAUDE_PLUGIN_DATA = $Path
    $i = Get-LwgStateDirInfo -Refresh
    return $i
}

function Get-FaultCount {
    <#
      Outstanding faults for one session across a set of records, counted the way
      ~/.claude/statusline.ps1 counts them:

        a Resolved marker zeroes everything before it - red means OUTSTANDING;
        supervisor_error, a non-interrupt PostToolUseFailure, a StopFailure and
        each failed task on a Stop are one fault apiece.

      The cross-file dedup is the status line's too, and is deliberately
      CROSS-FILE ONLY: two matching records in the SAME file are two events that
      writer genuinely recorded, and collapsing them undercounts.

      Returns @{ faults; resolved_at; last_ts; items }.
    #>
    param($Records)

    $r = @{ faults = 0; resolved_at = $null; last_ts = $null; items = @() }
    $seenAt = @{}
    foreach ($rec in @($Records | Sort-Object { [string]$_.ts })) {
        $key = @($rec.event, $rec.tool_use_id, $rec.agent_id, $rec.error, $rec.cwd, $rec.description) -join '|'
        $when = [datetime]::MinValue
        if ([datetime]::TryParse([string]$rec.ts, [ref]$when)) {
            $prev = $seenAt[$key]
            if ($prev -and $prev.src -ne $rec._src -and ($when - $prev.at).Duration().TotalSeconds -lt 2) { continue }
            $seenAt[$key] = @{ at = $when; src = $rec._src }
        }
        $r.last_ts = [string]$rec.ts
        if ($rec.event -eq 'Resolved') { $r.faults = 0; $r.items = @(); $r.resolved_at = [string]$rec.ts; continue }
        $n = 0
        if     ($rec.supervisor_error)                                          { $n = 1 }
        elseif ($rec.event -eq 'PostToolUseFailure' -and -not $rec.is_interrupt) { $n = 1 }
        elseif ($rec.event -eq 'Stop' -and [int]$rec.failed_tasks -gt 0)         { $n = [int]$rec.failed_tasks }
        elseif ($rec.event -eq 'StopFailure')                                    { $n = 1 }
        if ($n -gt 0) {
            $r.faults += $n
            $r.items += [pscustomobject]@{ ts = [string]$rec.ts; event = [string]$rec.event; n = $n
                                           detail = [string]$(if ($rec.error) { $rec.error } elseif ($rec.description) { $rec.description } else { '' })
                                           src = [string]$rec._src }
        }
    }
    return $r
}

try {
    $pluginRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $pluginRoot 'lib\common.ps1')
    . (Join-Path $PSScriptRoot 'lwg-cmdlib.ps1')

    Write-Output "LW-WATCHTOWER resolve v$($script:LwgVersion)"

    # --- what the UNPINNED resolution would have done -----------------------
    # Printed first, and on every run, because it is the thing that was silently
    # wrong. If this line says 'discovered' and names a directory that turns out
    # not to hold the session, that is the bug happening in front of the reader.
    $naive = Get-LwgStateDirInfo
    Write-Output ''
    Write-Output "  Get-LwgStateDirInfo (unpinned) -> $($naive.path)"
    Write-Output ("    source '{0}', resolved {1}, {2} candidate(s){3}" -f `
        $naive.source, $naive.resolved, $naive.candidates, `
        $(if ($naive.source -eq 'env') { ' - CLAUDE_PLUGIN_DATA is set in this shell' } else { ' - CLAUDE_PLUGIN_DATA is NOT set, so this is a discovery, not an instruction' }))

    # --- enumerate every candidate ------------------------------------------
    $name = Get-LwgPluginName
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'lw-watchtower' }
    $dataRoot = Join-Path $env:USERPROFILE '.claude\plugins\data'

    $cands = @()
    if (-not [string]::IsNullOrWhiteSpace($script:SavedEnv)) { $cands += [string]$script:SavedEnv }
    if (-not [string]::IsNullOrWhiteSpace($DataDir))         { $cands += [string]$DataDir }
    try {
        foreach ($d in @(Get-ChildItem -LiteralPath $dataRoot -Directory -Filter "$name*" -ErrorAction Stop)) { $cands += $d.FullName }
    } catch { }
    # The status line also merges the pre-plugin health log, and a Resolved marker
    # in one file clears a fault recorded in another, so it is read here too.
    $legacy = Join-Path $env:USERPROFILE '.claude\health'
    if (Test-Path -LiteralPath (Join-Path $legacy 'health.jsonl')) { $cands += $legacy }

    $seen = @{}; $dirs = @()
    foreach ($c in $cands) {
        $k = ([string]$c).TrimEnd('\', '/').ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($k) -or $seen.ContainsKey($k)) { continue }
        $seen[$k] = $true; $dirs += $c
    }

    if ($dirs.Count -eq 0) {
        Write-Output ''
        Write-Output "REFUSED - no candidate data directory exists under $dataRoot matching '$name*', and no -DataDir was given."
        Write-Output '  There is no log to resolve anything in. Nothing was written.'
        exit 1
    }

    # --- read each candidate, scoped to the session when we have one ---------
    # Tail 300 per file, which is exactly what the status line reads. A wider
    # window here would let this command clear a fault the indicator never showed.
    $rows = @()
    $all  = @()
    foreach ($d in $dirs) {
        $log = Join-Path $d 'health.jsonl'
        $row = @{ dir = $d; log = $log; exists = (Test-Path -LiteralPath $log); size = 0; mtime = $null
                  records = 0; session_records = 0; newest_session_ts = $null; newest_ts = $null; newest_session = $null }
        if ($row.exists) {
            try {
                $fi = Get-Item -LiteralPath $log -ErrorAction Stop
                $row.size = $fi.Length; $row.mtime = $fi.LastWriteTime
            } catch { }
            $null = Use-LwgDataDir -Path $d
            $recs = @(Get-LwgHealthRecords -Tail 300)
            $row.records = $recs.Count
            foreach ($rec in $recs) {
                if ($null -ne $rec.ts) { $row.newest_ts = [string]$rec.ts }
                if (-not [string]::IsNullOrWhiteSpace([string]$rec.session)) { $row.newest_session = [string]$rec.session }
            }
            foreach ($rec in $recs) {
                if (-not [string]::IsNullOrWhiteSpace($Session) -and ([string]$rec.session) -ne $Session) { continue }
                if ([string]::IsNullOrWhiteSpace($Session)) { continue }
                $row.session_records++
                $row.newest_session_ts = [string]$rec.ts
                $all += ($rec | Add-Member -NotePropertyName _src -NotePropertyValue $log -Force -PassThru)
            }
        }
        $rows += [pscustomobject]$row
    }

    Write-Output ''
    Write-Output '  CANDIDATE DATA DIRECTORIES (the status line reads all of them and merges by session)'
    Write-Output ''
    Write-Output '    HEALTH.JSONL                     SIZE      RECORDS  THIS SESSION  DIRECTORY'
    Write-Output '    -------------------------------- --------- -------- ------------- ---------'
    foreach ($r in $rows) {
        Write-Output ('    {0} {1} {2} {3} {4}' -f `
            $(if ($r.exists) { 'present' } else { 'ABSENT' }).PadRight(32), `
            $(if ($r.exists) { (Format-LwgBytes $r.size) } else { '-' }).PadRight(9), `
            ([string]$r.records).PadRight(8), `
            $(if ([string]::IsNullOrWhiteSpace($Session)) { '(no -Session)' } else { [string]$r.session_records }).PadRight(13), `
            $r.dir)
    }

    # --- pin the session -----------------------------------------------------
    $sessionSource = 'the -Session argument'
    if ([string]::IsNullOrWhiteSpace($Session)) {
        if (-not $InferSession) {
            Write-Output ''
            Write-Output 'REFUSED - no -Session was given.'
            Write-Output '  This command will not guess which session it is clearing. Inferring the session from the'
            Write-Output '  tail of a log is exactly how lib/resolve.ps1 comes to write a marker for a session that'
            Write-Output '  ended hours ago, in an install that is not this one, and then report success.'
            Write-Output ''
            Write-Output '  Pass -Session <id>. The newest session id in each candidate log, for reference only:'
            foreach ($r in $rows) {
                if (-not $r.exists) { continue }
                Write-Output ("    {0}  newest record {1}  session {2}" -f $r.dir, $(if ($r.newest_ts) { $r.newest_ts } else { '(none)' }), $(if ($r.newest_session) { $r.newest_session } else { '(none)' }))
            }
            Write-Output '  Or pass -InferSession to accept the newest one on the record, which prints its age and'
            Write-Output "  refuses when that record is more than $MaxAgeMinutes minutes old."
            exit 1
        }

        # Inference, done in the open: newest record ACROSS the candidates wins,
        # and its age is the evidence that it is this session rather than a
        # leftover.
        $best = $null; $bestT = [datetime]::MinValue; $bestDir = $null
        foreach ($r in $rows) {
            if (-not $r.exists -or [string]::IsNullOrWhiteSpace($r.newest_session)) { continue }
            $t = [datetime]::MinValue
            if (-not [datetime]::TryParse([string]$r.newest_ts, [ref]$t)) { continue }
            if ($t -gt $bestT) { $bestT = $t; $best = $r.newest_session; $bestDir = $r.dir }
        }
        if ($null -eq $best) {
            Write-Output ''
            Write-Output 'REFUSED - -InferSession was passed but no candidate log holds a record with a session id.'
            exit 1
        }
        $age = ((Get-Date).ToUniversalTime() - $bestT.ToUniversalTime())
        Write-Output ''
        Write-Output ("  INFERRED session {0} from the newest record in {1}, written {2:N1} minutes ago." -f $best, $bestDir, $age.TotalMinutes)
        if ($age.TotalMinutes -gt $MaxAgeMinutes) {
            Write-Output ''
            Write-Output ("REFUSED - that record is {0:N1} minutes old, past the {1} minute limit." -f $age.TotalMinutes, $MaxAgeMinutes)
            Write-Output '  A stale tail is not evidence of the current session. Pass -Session <id> explicitly.'
            exit 1
        }
        $Session = $best
        $sessionSource = "inference from the newest record in $bestDir"

        # The rows were built before the session was known, so re-read them now
        # that there is something to filter by.
        $all = @()
        foreach ($r in $rows) {
            if (-not $r.exists) { continue }
            $null = Use-LwgDataDir -Path $r.dir
            $recs = @(Get-LwgHealthRecords -Session $Session -Tail 300)
            $r.session_records = $recs.Count
            foreach ($rec in $recs) { $r.newest_session_ts = [string]$rec.ts; $all += ($rec | Add-Member -NotePropertyName _src -NotePropertyValue $r.log -Force -PassThru) }
        }
    }

    Write-Output ''
    Write-Output "  SESSION: $Session"
    Write-Output "    pinned from $sessionSource"

    # --- THE REFUSAL --------------------------------------------------------
    # The session is not in any log that exists. lib/resolve.ps1 would append a
    # marker and print that HH is green.
    $holders = @($rows | Where-Object { $_.session_records -gt 0 })
    if ($holders.Count -eq 0) {
        Write-Output ''
        Write-Output "REFUSED - session $Session does not appear in ANY candidate health log."
        Write-Output '  Nothing was written. A Resolved marker for a session no log knows about clears nothing,'
        Write-Output '  and reporting it as done would be a success report about a change that did not happen.'
        Write-Output ''
        Write-Output '  Logs searched (last 300 records of each, which is what the status line reads):'
        foreach ($r in $rows) {
            Write-Output ("    {0}  {1}" -f $(if ($r.exists) { "$($r.records) record(s)" } else { 'no health.jsonl' }).PadRight(20), $r.log)
        }
        Write-Output ''
        Write-Output '  Either the session id is wrong, or its faults were recorded somewhere none of these'
        Write-Output '  directories covers. Pass -DataDir <path> to name that directory explicitly.'
        exit 1
    }

    # --- pin the write target ------------------------------------------------
    $target = $null; $targetWhy = ''
    if (-not [string]::IsNullOrWhiteSpace($DataDir)) {
        $target = $DataDir; $targetWhy = 'pinned by -DataDir'
    } elseif (-not [string]::IsNullOrWhiteSpace($script:SavedEnv)) {
        $target = [string]$script:SavedEnv; $targetWhy = 'CLAUDE_PLUGIN_DATA, which is authoritative when it is set'
    } elseif ($holders.Count -eq 1) {
        $target = $holders[0].dir; $targetWhy = 'the one candidate whose log holds this session'
    } else {
        # Several logs hold the session. Choose on evidence - the one carrying its
        # newest record - and only when that evidence actually distinguishes them.
        $ranked = @($holders | Sort-Object { [string]$_.newest_session_ts } -Descending)
        if ($ranked.Count -ge 2 -and [string]$ranked[0].newest_session_ts -eq [string]$ranked[1].newest_session_ts) {
            Write-Output ''
            Write-Output "AMBIGUOUS - $($holders.Count) candidate logs hold session $Session and their newest records are indistinguishable."
            foreach ($r in $ranked) { Write-Output ("    {0} record(s), newest {1}  {2}" -f $r.session_records, $r.newest_session_ts, $r.dir) }
            Write-Output '  Nothing was written. Pass -DataDir <path> to say which log the marker belongs in.'
            exit 2
        }
        $target = $ranked[0].dir
        $targetWhy = "the candidate carrying this session's newest record ($($ranked[0].newest_session_ts)); the others are listed above"
    }

    $targetInfo = Use-LwgDataDir -Path $target
    Write-Output ''
    Write-Output "  WRITE TARGET: $($targetInfo.path)"
    Write-Output "    chosen because: $targetWhy"
    if ($holders.Count -gt 1) {
        Write-Output "    NOTE: $($holders.Count) logs hold records for this session. The status line merges every"
        Write-Output '    lw-watchtower* data dir plus ~/.claude/health, so one marker clears the merged count - but the'
        Write-Output '    other logs keep their own fault records, and any reader of a single file still sees them.'
    }
    if ($target -ne $naive.path) {
        Write-Output "    This is NOT the directory the unpinned resolution returned ($($naive.path))."
        Write-Output '    A bare lib/resolve.ps1 run would have written the marker there.'
    }

    # --- the fault picture ---------------------------------------------------
    $f = Get-FaultCount -Records $all
    Write-Output ''
    Write-Output ("  OUTSTANDING FAULTS: {0}   (from {1} record(s) for this session across {2} log(s))" -f $f.faults, @($all).Count, $holders.Count)
    if ($f.resolved_at) { Write-Output "    the last Resolved marker for this session is dated $($f.resolved_at); only faults after it are counted" }
    foreach ($i in @($f.items | Select-Object -Last 10)) {
        Write-Output ("    {0}  {1}  x{2}  {3}" -f $i.ts, ([string]$i.event).PadRight(20), $i.n, (Get-LwgRedacted -Text $i.detail -MaxLength 90))
    }

    if ($List) { exit 0 }

    if ($f.faults -eq 0) {
        Write-Output ''
        Write-Output "REFUSED - session $Session has no outstanding faults to clear."
        Write-Output '  Nothing was written. A Resolved marker over a clean session changes nothing and would be'
        Write-Output '  one more success report about nothing. The status line is already green for this session'
        Write-Output '  unless something outside this count is red - /lw-watchtower:doctor covers the rest.'
        exit 1
    }

    if ([string]::IsNullOrWhiteSpace($Note)) {
        Write-Output ''
        Write-Output 'REFUSED - -Note is required.'
        Write-Output '  health.jsonl is evidence. A marker that does not say what was fixed turns an outstanding'
        Write-Output '  fault into a silent one.'
        exit 1
    }

    if (-not (Test-LwgModule -Name 'failure_capture')) {
        Write-Output ''
        Write-Output '  WARNING: failure_capture is switched off in config.json, so no NEW faults are being recorded.'
        Write-Output '  The marker is still written - it is the only way to clear faults logged before the flag was'
        Write-Output '  flipped - but the log is no longer a live picture of anything.'
    }

    $rec = [ordered]@{
        ts      = (Get-Date).ToUniversalTime().ToString('o')
        event   = 'Resolved'
        session = $Session
        note    = $Note
        by      = 'lwg-resolve'
    }
    $line = ($rec | ConvertTo-Json -Depth 4 -Compress)

    Write-Output ''
    Write-Output "  WOULD APPEND to $(Join-Path $targetInfo.path 'health.jsonl') :"
    Write-Output "    $line"

    if (-not $Apply) {
        Write-Output ''
        Write-Output 'DRY RUN - nothing was written. Re-run with -Apply to write the marker.'
        exit 0
    }

    if (-not (Add-LwgLine -FileName 'health.jsonl' -Line $line)) {
        Write-Output ''
        Write-Output "FAILED - the append to $(Join-Path $targetInfo.path 'health.jsonl') did not succeed after five attempts."
        Write-Output '  Nothing was written and nothing is cleared.'
        exit 1
    }

    # --- prove it -----------------------------------------------------------
    # Re-read from disk, across the same union of logs, and recount. Printing
    # "HH returns to green" without this is the whole defect.
    $after = @()
    foreach ($r in $rows) {
        $null = Use-LwgDataDir -Path $r.dir
        foreach ($x in @(Get-LwgHealthRecords -Session $Session -Tail 300)) {
            $after += ($x | Add-Member -NotePropertyName _src -NotePropertyValue $r.log -Force -PassThru)
        }
    }
    $f2 = Get-FaultCount -Records $after
    $wrote = @($after | Where-Object { $_.event -eq 'Resolved' -and [string]$_.ts -eq [string]$rec.ts })

    Write-Output ''
    Write-Output 'WRITTEN.'
    Write-Output "  file:    $(Join-Path $targetInfo.path 'health.jsonl')"
    Write-Output "  verify:  the marker was read back from disk: $($wrote.Count -gt 0)"
    Write-Output "  verify:  outstanding faults for $Session recounted across $($rows.Count) log(s): $($f.faults) -> $($f2.faults)"

    if ($wrote.Count -eq 0 -or $f2.faults -ne 0) {
        Write-Output ''
        Write-Output 'FAULT: the marker was appended but the faults did NOT clear.'
        Write-Output '  Do not report this session as resolved. Re-run with -List to see what is still counted.'
        exit 4
    }

    Write-Output ''
    Write-Output "Session $Session is clear in the logs above. The status line renders HH from the same records,"
    Write-Output 'so it goes green on its next refresh - provided ~/.claude/statusline.ps1 is the wired renderer'
    Write-Output '(/lw-watchtower:doctor checks that) and the session id it is given matches this one.'
    exit 0

} catch {
    Write-Output ''
    Write-Output "LW-WATCHTOWER resolve could not complete: $($_.Exception.Message)"
    Write-Output 'Nothing above should be read as evidence that anything was cleared.'
    exit 3
} finally {
    # Leave the process as it was found. This variable is inherited by anything
    # this shell starts next, and a leaked value would redirect it too.
    $env:CLAUDE_PLUGIN_DATA = $script:SavedEnv
}
