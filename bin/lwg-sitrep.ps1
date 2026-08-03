#requires -version 5
<#
  LW-WATCHTOWER sitrep - everything underway, and everything that could not be seen.

      powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-sitrep.ps1

  Backs /lw-watchtower:sitrep. Brief but COMPLETE: every section prints, including the
  empty ones, because a section that disappears when it has nothing in it is
  indistinguishable from a section that was never checked.

  TWO TAGS, and they are the reason this command exists:

      [V]  VERIFIED here - this process ran the probe, or read a record the
           plugin's own hooks wrote about their own behaviour.
      [R]  REPORTED - a claim made by an agent or a tool about its own work,
           read back out of a log. Not independently checked.

  A worker's report is a claim, not a fact. Anything tagged [R] may be wrong and
  this command has done nothing to find out.

  WHAT IT CANNOT SEE is a first-class section, not a footnote. The largest gap is
  named on every run: no hook records a subagent DISPATCH on its happy path, so
  work currently in flight in another agent is structurally invisible here. A
  sitrep that quietly omitted that would read as "nothing is running", which is a
  different and much more dangerous statement.

  Exit codes:

      0  the sitrep rendered
      3  it could not be produced at all

  There is no exit code for "the news is bad". This command reports; it does not
  judge. Degrading is not failing: no gh, no network, no git and no state dir all
  produce a sitrep that says so per item and still exits 0.

  A MARKER is written to the state dir on each run so the next sitrep can say
  what changed. -NoMark reads without advancing it.
#>

param(
    # Report the window without advancing the marker - for a second look at the
    # same window, or a dry run on a machine you would rather not write to.
    [switch]$NoMark,

    # Fall back to this many hours when no previous sitrep marker exists.
    [int]$DefaultWindowHours = 24
)

$ErrorActionPreference = 'Stop'

$script:Unknown = New-Object System.Collections.ArrayList
function Add-Unknown { param([string]$Text) [void]$script:Unknown.Add($Text) }

$script:Decisions = New-Object System.Collections.ArrayList
function Add-Decision { param([string]$Text) [void]$script:Decisions.Add($Text) }

function Get-Utc {
    <# Parse an ISO timestamp to UTC. Returns $null rather than throwing or guessing. #>
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $d = [datetime]::MinValue
    if ([datetime]::TryParse($Text, [ref]$d)) { return $d.ToUniversalTime() }
    return $null
}

function Format-Age {
    param($Utc)
    if ($null -eq $Utc) { return 'at an unparseable time' }
    $t = ((Get-Date).ToUniversalTime() - $Utc)
    if ($t.TotalMinutes -lt 90)  { return ('{0:N0} min ago' -f $t.TotalMinutes) }
    if ($t.TotalHours   -lt 72)  { return ('{0:N1} h ago'   -f $t.TotalHours) }
    return ('{0:N1} days ago' -f $t.TotalDays)
}

try {
    $pluginRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $pluginRoot 'lib\common.ps1')
    . (Join-Path $PSScriptRoot 'lwg-evidence.ps1')

    $ctx     = New-LwgEvidenceContext -PluginRoot $pluginRoot
    $cfg     = Get-LwgConfig
    $dirInfo = Get-LwgStateDirInfo
    $nowUtc  = (Get-Date).ToUniversalTime()

    # --- the window ---------------------------------------------------------
    # State-dir resolution is checked BEFORE the marker is read, because an
    # unresolved dir means the marker was written somewhere the live plugin never
    # looks - and a window silently reset to 24 h would make "finished since the
    # last sitrep" quietly mean something else.
    $sinceUtc  = $nowUtc.AddHours(-1 * [Math]::Abs($DefaultWindowHours))
    $windowWhy = "no previous sitrep marker - reporting the last $([Math]::Abs($DefaultWindowHours)) h"
    $markerOk  = $dirInfo.resolved

    if (-not $markerOk) {
        Add-Unknown ("the state dir is UNRESOLVED (source '$($dirInfo.source)', path $($dirInfo.path)), so the sitrep marker, the event log and the health log may all be the wrong files. Every log-derived line below is suspect and the marker will not be advanced")
    } else {
        $mk = Read-LwgStateJson -FileName 'sitrep.state.json'
        $prev = Get-Utc ([string]$mk['last_ts'])
        if ($null -ne $prev) {
            $sinceUtc  = $prev
            $windowWhy = "since the last sitrep, written $(Format-Age $prev)"
        }
    }
    $sinceIso = $sinceUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')

    # --- session mode, from the newest SessionStart record ------------------
    # Recomputed from the live config, exactly as lwg-status.ps1 does; only the
    # two self-check facts - which no out-of-session process can observe - come
    # from the record.
    $mode     = 'unknown'
    $modeNote = 'no SessionStart record found; the mode cannot be stated without one'
    $log      = Join-Path $dirInfo.path 'lw-watchtower.jsonl'
    $planRecs = @()
    # THE READ IS A WINDOW, AND EVERY COUNT DERIVED FROM IT HAS TO SAY SO.
    # Get-LwgTailLines seeks to the last $Bytes of the file and returns lines; it
    # returns only the lines, so no caller can tell a complete read from a
    # partial one. The window is 512 KB and lw-watchtower.jsonl is allowed to grow far
    # past that - the operator log measured while this was written was 2.4 MB, so
    # 21% of it was read. Everything below that says "in the event log" was
    # therefore describing a slice and calling it the log, under a [V] whose
    # definition on this page is "this process ran the probe".
    #
    # The file size is taken here rather than inside the helper: changing that
    # helper's return shape is a change to every caller of it, and its docstring
    # is emphatic about why it returns what it returns. Comparing the length
    # against the same constant that is passed to it asks the same question from
    # the outside and costs one stat.
    $logWindowBytes = 524288
    $logBytes       = 0
    $logTruncated   = $false
    if (Test-Path -LiteralPath $log) {
        try { $logBytes = (Get-Item -LiteralPath $log -Force).Length } catch { $logBytes = 0 }
        $logTruncated = ($logBytes -gt $logWindowBytes)
        foreach ($line in @(Get-LwgTailLines -Path $log -Bytes $logWindowBytes)) {
            $r = $null
            try { $r = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            if ($null -ne $r) { $planRecs += $r }
        }
        if ($logTruncated) {
            Add-Unknown ("the event log at $log is $([Math]::Round($logBytes / 1KB)) KB and only its last $([int]($logWindowBytes / 1KB)) KB were read, so every count below that is derived from it - gate denials, the sessions they sit across, session mode - is a count of that WINDOW and not of the file. Anything earlier was not read and is not evidence of absence")
        }
    } else {
        Add-Unknown "no plugin event log at $log, so open gate trips, session mode and recent advisories are all unknown - this is NOT evidence that there are none"
    }

    $ssRec = $null
    foreach ($r in $planRecs) { if ($r.event -eq 'SessionStart') { $ssRec = $r } }
    if ($null -ne $ssRec) {
        $repo    = (Get-LwgRepoInfo -Path $pluginRoot).slug
        $active  = @(Get-LwgActiveModules -Config $cfg -Repo $repo)
        $gates   = @(Get-LwgActiveGates   -Config $cfg -Repo $repo)
        $impl    = @(Get-LwgImplementedModules)
        $mode    = Get-LwgSessionMode -ActiveCount $active.Count -GateCount $gates.Count `
                                      -ImplementedCount $impl.Count `
                                      -SelfHealthOn ([bool]($ssRec.selfcheck.ran -eq $true)) `
                                      -SelfCheckOk $ssRec.selfcheck.ok
        $modeNote = "self-check evidence from the SessionStart record written $(Format-Age (Get-Utc ([string]$ssRec.ts)))"
    }

    # --- historical gate denials in the event log ---------------------------
    # Per session, in timestamp order, with a Resolved/GateCleared marker
    # clearing everything before it. NOT filtered to one session: these are
    # history, and the operator wants all of it rather than the slice belonging
    # to the session they happen to be in.
    #
    # THE DATA SOURCE IS lw-watchtower.jsonl, WHICH SURVIVES. That is the only reason
    # this section still works. The per-session trip LEDGER it used to agree with
    # was removed on 30 July 2026 along with lib/trips.ps1 and the status line's
    # GM segment, so there is no second reader left to disagree with.
    #
    # Nothing can add to this set and nothing can clear it: no gate exists to
    # write a GateDeny, and GateCleared was only ever written by the trip sweep,
    # which is gone. It is reported as governance history, NOT as a decision
    # waiting on the operator - a count nobody can act on does not belong in a
    # list of things to act on.
    $openTrips = @()
    $bySession = @{}
    foreach ($r in ($planRecs | Sort-Object { [string]$_.ts })) {
        $s = [string]$r.session
        if (-not $bySession.ContainsKey($s)) { $bySession[$s] = New-Object System.Collections.ArrayList }
        if ($r.event -eq 'GateCleared' -or $r.event -eq 'Resolved') { $bySession[$s].Clear(); continue }
        if ($r.event -like 'Gate*' -or $r.event -like 'Block*' -or $r.gate_tripped -eq $true) {
            [void]$bySession[$s].Add($r)
        }
    }
    foreach ($k in $bySession.Keys) { $openTrips += @($bySession[$k]) }
    $openTrips = @($openTrips | Sort-Object { [string]$_.ts })
    # THE SESSIONS THE DENIALS ACTUALLY SIT ACROSS, which is not the same set as
    # the keys of $bySession. The key is created for EVERY record in the window,
    # before the event is looked at, and it survives the .Clear() a GateCleared
    # or Resolved performs - so $bySession.Keys.Count counted sessions that
    # contribute no denial at all, including sessions whose denials were
    # explicitly cleared, and every session that wrote only a SessionStart or a
    # RotateFailed. $openTrips is built from exactly these non-empty lists, so
    # the two numbers in the sentence below now come from one source.
    $sessionsWithTrips = @($bySession.Keys | Where-Object { $bySession[$_].Count -gt 0 }).Count

    if ($openTrips.Count -gt 0) {
        # The plugin event log is shared by every session that ever bound this
        # plugin, INCLUDING regression-suite runs, which deny by design and leave
        # a real GateDeny behind. Nothing in a record says which kind of session
        # wrote it, so the count below is honest about what it counted and
        # explicitly does not claim they are all live operator trips.
        Add-Unknown "the ORIGIN of a historical gate denial cannot be attributed from its record. $($openTrips.Count) uncleared denial(s) sit across $sessionsWithTrips session id(s) in one shared log that every session writes to, so one recorded by something other than live operator work is indistinguishable here. Treat the count as an upper bound on live operator denials. All of them predate 30 July 2026, when the last gate was removed, and many name rules from the destructive command gate, which no longer exists. There is no longer any command that opens them one by one: the trip ledger, its reader and lib/ack_trip.ps1 were removed with the gates"
    }

    # --- health faults ------------------------------------------------------
    # Stop.failed_tasks IS A GAUGE, NOT AN EVENT. lib/supervisor.ps1 writes one
    # Stop record at EVERY turn end holding the number of background tasks in a
    # failed/killed state at that moment, and it writes it before its own
    # alerted.json dedupe - so the dedupe suppresses the repeated ALERT and never
    # the repeated RECORD. This loop used to do `$faults += [int]$r.failed_tasks`
    # over every one of them, which counted one dead task once per turn: after
    # forty turns a single unresolved task was reported as 38 outstanding faults,
    # raised in NEEDS AN OPERATOR DECISION as a list to work through "once EACH
    # has been assessed".
    #
    # The three sibling branches keep their '++' because each of their records is
    # one event that happened once. bin/lwg-resolve.ps1:136 already reads this
    # field as a gauge, by assignment; this file and statusline/statusline.ps1
    # did not, so two commands reading one log printed two different totals -
    # the reader/reporter divergence this plugin is named for.
    #
    # WHAT THIS DOES NOT FIX: the record carries a count and no task ids, so a
    # second task failing three turns after the first, while the first is still
    # outstanding, is indistinguishable here from the first being re-sampled.
    # Closing that needs the writer to emit the ids, which is lib/supervisor.ps1
    # and not this file.
    $faults      = 0
    $lastFault   = $null
    $faultGauge  = 0
    $gaugeRec    = $null
    $healthTail  = 600
    $healthRecs = @(Get-LwgHealthRecords -Tail $healthTail)
    foreach ($r in ($healthRecs | Sort-Object { [string]$_.ts })) {
        if ($r.event -eq 'Resolved') { $faults = 0; $lastFault = $null; $faultGauge = 0; $gaugeRec = $null; continue }
        $hit = $false
        if ($r.supervisor_error) { $faults++; $hit = $true }
        elseif ($r.event -eq 'PostToolUseFailure' -and -not $r.is_interrupt) { $faults++; $hit = $true }
        elseif ($r.event -eq 'Stop') {
            # carried, not accumulated - the newest sample is the current count
            $faultGauge = [int]$r.failed_tasks
            if ($faultGauge -gt 0) { $gaugeRec = $r }
        }
        elseif ($r.event -eq 'StopFailure') { $faults++; $hit = $true }
        if ($hit) { $lastFault = $r }
    }
    if ($faultGauge -gt 0) {
        $faults += $faultGauge
        # the newest thing that contributed, whichever kind it was
        if ($null -eq $lastFault -or ($null -ne $gaugeRec -and [string]$gaugeRec.ts -gt [string]$lastFault.ts)) { $lastFault = $gaugeRec }
    }
    if ($healthRecs.Count -eq 0) {
        Add-Unknown "health.jsonl in $($dirInfo.path) is empty or absent, so the fault count below is 0 because nothing was READ, not because nothing failed"
    }
    # THE HEALTH READ IS BOUNDED TWICE and neither bound was ever stated on the
    # page. Get-LwgHealthRecords takes the last 512 KB of the file AND THEN the
    # last -Tail records of that, and health.jsonl is allowed to reach 5 MB
    # before Invoke-LwgRotate rolls it - roughly 11,000 records at the size the
    # rotation comment assumes. A fault older than the window has silently
    # expired from this count, which is the one property the decision text below
    # asserts it does not have: "they do not expire".
    #
    # Hitting the record cap is the detectable half and is the one that is
    # reported. A byte-window truncation that stops short of 600 records is not
    # separable from "the file only holds this many" without a second read, so
    # the file size is stated whenever it exceeds the window and the sentence
    # says which bound was hit.
    $healthPath  = Join-Path $dirInfo.path 'health.jsonl'
    $healthBytes = 0
    if (Test-Path -LiteralPath $healthPath) {
        try { $healthBytes = (Get-Item -LiteralPath $healthPath -Force).Length } catch { $healthBytes = 0 }
    }
    $healthCapped = ($healthRecs.Count -ge $healthTail) -or ($healthBytes -gt 524288)
    if ($healthCapped) {
        Add-Unknown ("the health read is bounded: at most the last 512 KB of $healthPath and then at most the last $healthTail records of that. The file is $([Math]::Round($healthBytes / 1KB)) KB and $($healthRecs.Count) record(s) were read, so the fault count below is AT LEAST that many and not a total. Faults older than the window are not in it, and the decision text's 'they do not expire' is true of the faults and not of this reading of them")
    }
    Add-Unknown "the health fault count covers $($dirInfo.path)\health.jsonl only. The status line additionally merges every other lw-watchtower* data dir and ~\.claude\health\health.jsonl, so its HH number can legitimately be higher than the one here"

    # --- working tree -------------------------------------------------------
    $branch = ''; $upstream = ''; $ahead = 0; $behind = 0; $dirty = 0; $untracked = 0
    $treeKnown = $false; $detached = $false
    if ([string]::IsNullOrWhiteSpace([string]$ctx.git_root)) {
        Add-Unknown "$pluginRoot is not inside a git repository, so tree cleanliness, sync state and recent commits cannot be determined"
    } else {
        $st = Invoke-LwgCtxProcess -Ctx $ctx -File 'git' -WorkDir $ctx.git_root -TimeoutMs 6000 -ProcArgs @(
            '--no-pager', 'status', '--porcelain=v2', '--branch')
        if (-not $st.ok) {
            Add-Unknown ("working tree state is UNKNOWN - " + (Get-LwgRptProcessWhy -Result $st -Tool 'git status') +
                         ". Do not read this as a clean tree")
        } else {
            $treeKnown = $true
            foreach ($raw in $st.out.Split([char]10)) {
                $l = $raw.TrimEnd([char]13)
                if ($l.Length -eq 0) { continue }
                if ($l[0] -eq '#') {
                    if     ($l -match '^# branch\.head (.+)$')     { $branch   = $Matches[1].Trim() }
                    elseif ($l -match '^# branch\.upstream (.+)$') { $upstream = $Matches[1].Trim() }
                    elseif ($l -match '^# branch\.ab \+(\d+) -(\d+)$') { $ahead = [int]$Matches[1]; $behind = [int]$Matches[2] }
                    continue
                }
                if     ($l[0] -eq '?') { $untracked++ }
                elseif ($l[0] -ne '!') { $dirty++ }
            }
            $detached = ($branch -eq '(detached)')
        }
    }

    # --- commits in the window ---------------------------------------------
    $commits = @()
    if (-not [string]::IsNullOrWhiteSpace([string]$ctx.git_root)) {
        $cl = Invoke-LwgCtxProcess -Ctx $ctx -File 'git' -WorkDir $ctx.git_root -TimeoutMs 6000 -ProcArgs @(
            '--no-pager', 'log', '--all', "--since=$sinceIso", '--format=%h%x09%s', '-n', '40')
        if ($cl.ok) {
            foreach ($raw in $cl.out.Split([char]10)) {
                $l = $raw.TrimEnd([char]13)
                if ($l.Length -eq 0) { continue }
                $t = $l.IndexOf([char]9)
                if ($t -lt 0) { continue }
                $commits += @{ sha = $l.Substring(0, $t); subject = $l.Substring($t + 1) }
            }
        } else {
            Add-Unknown ("commits landed in this window are UNKNOWN - " + (Get-LwgRptProcessWhy -Result $cl -Tool 'git log'))
        }
    }

    # --- CI -----------------------------------------------------------------
    $ciMain = Get-LwgRptCiRun -Ctx $ctx -Workflow 'CI' -Branch 'main'
    $ciHere = $null
    if ($treeKnown -and $branch -and -not $detached -and $branch -ne 'main') {
        $ciHere = Get-LwgRptCiRun -Ctx $ctx -Workflow 'CI' -Branch $branch
    }
    if (-not $ciMain.ok) { Add-Unknown "CI status on main is UNKNOWN - $($ciMain.why)" }
    if ($null -ne $ciHere -and -not $ciHere.ok) { Add-Unknown "CI status on '$branch' is UNKNOWN - $($ciHere.why)" }

    # --- the checklist ------------------------------------------------------
    $rows = @()
    $manifestPath = Join-Path $pluginRoot 'checklist.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        Add-Unknown "no checklist.json at $manifestPath, so nothing below reports plan progress, what is blocked, or what is under way against the plan"
    } else {
        try {
            $mf = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
            $rows = @(Resolve-LwgChecklist -Ctx $ctx -Items @($mf.items))
        } catch {
            Add-Unknown "checklist.json could not be resolved ($($_.Exception.Message)), so plan progress, blockers and in-flight plan work are all unknown"
        }
    }
    $inProgress = @($rows | Where-Object { $_.State -eq 'IN PROGRESS' })
    $blocked    = @($rows | Where-Object { $_.State -eq 'BLOCKED' })
    $unverified = @($rows | Where-Object { $_.State -eq 'UNVERIFIED' })

    # --- subagent activity in the window ------------------------------------
    $stops  = @()
    $failed = @()
    foreach ($r in $healthRecs) {
        $t = Get-Utc ([string]$r.ts)
        if ($null -eq $t -or $t -lt $sinceUtc) { continue }
        if ($r.event -eq 'SubagentStop') { $stops += $r }
        if ($r.event -eq 'PostToolUseFailure' -and -not $r.is_interrupt) { $failed += $r }
    }

    # THE BIGGEST BLIND SPOT, stated on every run. SubagentStart IS registered in
    # hooks/hooks.json, but lib/subagent_start.ps1 writes a record only on its
    # ERROR path - the happy path injects context and exits silently, by design,
    # because that hook is on every dispatch and pays for a 273 ms interpreter
    # floor. So a dispatch that has not yet finished leaves no trace anywhere.
    Add-Unknown "AGENTS CURRENTLY IN FLIGHT ARE NOT OBSERVABLE. Nothing records a subagent DISPATCH: hooks.json registers SubagentStart, but lib/subagent_start.ps1 writes a record only when it fails. Only SubagentStop is logged, so a worker that is still running is invisible here. An empty IN FLIGHT section therefore means 'nothing observable', never 'no agents are running'"

    # Decisions raised in conversation leave no machine-readable trace at all -
    # that was the whole premise of Phase C, and Phase C is now CLOSED UNBUILT
    # rather than pending. Saying so is the only honest thing this section can
    # do. The two command names below are written WITHOUT a leading slash on
    # purpose: bin\lwg-doctor.ps1 scans this repo for /<plugin>:<name> and fails
    # on one with no commands\<name>.md behind it - the right rule, because a
    # live-looking reference to a deleted command is a signpost to nothing.
    Add-Unknown "DECISIONS RAISED IN CONVERSATION AND NEVER ANSWERED ARE NOT OBSERVABLE, AND NOTHING IS COMING THAT WOULD MAKE THEM SO. Nothing records a question put to the operator. lw-watchtower:ask was to be that mechanism and it was REMOVED on 30 July 2026 by an explicit owner decision, along with lw-watchtower:ask-inline: a Stop hook can refuse to end a turn but cannot stop prose that has already appeared and cannot detect a question that should have been asked and was not, and nothing can merge questions after they have been asked. Do not read this line as work outstanding. NEEDS AN OPERATOR DECISION lists only those decisions that left a machine-readable trace"

    # =======================================================================
    # RENDER
    # =======================================================================
    Write-Output "LW-WATCHTOWER sitrep - $(if ($ctx.slug) { $ctx.slug } else { 'no repo slug' }) - $($nowUtc.ToString('yyyy-MM-dd HH:mm')) UTC"
    Write-Output "  window: $windowWhy (since $sinceIso)"
    Write-Output "  session mode $mode - $modeNote"
    Write-Output '  [V] verified by this command   [R] reported by an agent or tool - a claim, not a fact'

    # --- in flight ----------------------------------------------------------
    Write-Output ''
    Write-Output 'IN FLIGHT'
    $any = $false
    if ($null -ne $ciHere -and $ciHere.ok -and $ciHere.status -and $ciHere.status -ne 'completed') {
        Write-Output "  [V] CI on '$branch' is $($ciHere.status) now - $($ciHere.url)"; $any = $true
    }
    if ($ciMain.ok -and $ciMain.status -and $ciMain.status -ne 'completed') {
        Write-Output "  [V] CI on main is $($ciMain.status) now - $($ciMain.url)"; $any = $true
    }
    foreach ($r in $inProgress) {
        Write-Output "  [V] $($r.Id) - $($r.Title)"
        foreach ($l in (Format-LwgWrapped -Text $r.Detail -Indent '      ')) { Write-Output $l }
        $any = $true
    }
    if (-not $any) {
        Write-Output '  nothing observable is in flight. This is NOT the same as nothing running - see COULD NOT DETERMINE.'
    }

    # --- finished in the window --------------------------------------------
    Write-Output ''
    Write-Output "FINISHED IN THIS WINDOW"
    $any = $false
    # Capped, and the cap is STATED. Silently showing the first ten of thirty
    # would be a report that omits without saying so.
    $show = @($commits | Select-Object -First 10)
    foreach ($c in $show) { Write-Output "  [V] commit $($c.sha) $($c.subject)"; $any = $true }
    if ($commits.Count -gt $show.Count) {
        Write-Output "  [V] ... and $($commits.Count - $show.Count) further commit(s) in this window, not listed"
    }
    if ($stops.Count -gt 0) {
        # A SubagentStop record means the harness saw a worker end. What the
        # worker CLAIMS it achieved is not in the record and is not checked here,
        # which is exactly why this line is [R] and carries no outcome.
        $types = @($stops | ForEach-Object { $t = [string]$_.agent_type; if ([string]::IsNullOrWhiteSpace($t)) { '(agent_type not recorded)' } else { $t } })
        $grp = $types | Group-Object | Sort-Object Count -Descending
        Write-Output "  [R] $($stops.Count) subagent(s) stopped: $(($grp | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', ')"
        Write-Output '      the record says a worker ENDED. It does not say what it achieved, and nothing here checked.'
        $any = $true
    }
    if (-not $any) { Write-Output '  no commit and no subagent stop recorded in this window.' }

    # --- blocked ------------------------------------------------------------
    Write-Output ''
    Write-Output 'BLOCKED'
    if ($blocked.Count -eq 0) {
        Write-Output '  nothing in checklist.json resolves to blocked.'
    } else {
        foreach ($r in $blocked) {
            Write-Output "  [V] $($r.Id) - $($r.Title)"
            foreach ($l in (Format-LwgWrapped -Text $r.Detail -Indent '      ')) { Write-Output $l }
        }
    }

    # --- decisions ----------------------------------------------------------
    # Assembled last from everything above, so nothing that needs an answer can
    # be reported in one section and forgotten in this one.
    # Historical gate denials used to be raised here, in NEEDS AN OPERATOR
    # DECISION. They are not a decision any more: no gate can add one and
    # nothing can clear one, so the operator has nothing to decide. The count
    # and its rule breakdown moved to GOVERNANCE, where history belongs.
    if ($faults -gt 0) {
        $w = if ($null -ne $lastFault) { ", newest $(Format-Age (Get-Utc ([string]$lastFault.ts))) ($([string]$lastFault.event))" } else { '' }
        # "at least" when the read was capped - see the health-fault block.
        $atLeast = if ($healthCapped) { 'at least ' } else { '' }
        # NAMES THE COMMAND, NOT lib\resolve.ps1. This line used to point the
        # operator at a script commands/resolve.md forbids in bold: outside a
        # hook, lib/resolve.ps1 picks a data directory by modification time,
        # infers a session from that file's tail, writes a marker for whatever
        # session that turns out to be, and prints "status line HH returns to
        # green" - a success report about a change that did not happen. This is
        # the operator-facing surface and it names the operator-facing command.
        Add-Decision "[V] $atLeast$faults outstanding health fault(s)$w. Clear with /lw-watchtower:resolve once each has been assessed - they do not expire."
    }
    foreach ($r in $unverified) {
        Add-Decision "[V] $($r.Id) needs a human: $($r.Title). $($r.Detail)"
    }
    if ($treeKnown -and ($dirty + $untracked) -gt 0) {
        Add-Decision "[V] $($dirty + $untracked) uncommitted change(s) on '$branch' - commit them or say why they are being kept."
    }
    if ($treeKnown -and $ahead -gt 0) {
        Add-Decision "[V] $ahead commit(s) ahead of $upstream and not pushed."
    }
    if ($failed.Count -gt 0) {
        Add-Decision "[R] $($failed.Count) subagent dispatch failure(s) recorded in this window - each raised an alert that may have scrolled past: $((@($failed | ForEach-Object { [string]$_.agent_type }) | Where-Object { $_ } | Select-Object -Unique) -join ', ')"
    }

    Write-Output ''
    Write-Output 'NEEDS AN OPERATOR DECISION'
    if ($script:Decisions.Count -eq 0) {
        Write-Output '  nothing with a machine-readable trace is waiting on you.'
    } else {
        foreach ($d in $script:Decisions) {
            $lines = @(Format-LwgWrapped -Text $d -Indent '      ')
            if ($lines.Count -gt 0) {
                Write-Output ('  ' + $lines[0].Substring(6))
                for ($i = 1; $i -lt $lines.Count; $i++) { Write-Output $lines[$i] }
            }
        }
    }

    # --- governance ---------------------------------------------------------
    Write-Output ''
    Write-Output 'GOVERNANCE'
    # HISTORY, not a live count. Both gates and the trip ledger are gone, so this
    # can never rise and can never fall. GROUPED by rule rather than listed: 205
    # near-identical lines is padding, and padding is how the two or three that
    # matter get skipped.
    # THE WINDOW IS NAMED ON THE LINE when there was one. [V] is the right tag
    # for "I counted what I read"; the line has to say what it read, or the
    # phrase "in the event log" claims the whole file.
    $logScope = if ($logTruncated) { "in the last $([int]($logWindowBytes / 1KB)) KB of a $([Math]::Round($logBytes / 1KB)) KB event log - earlier denials were NOT read" } else { 'in the event log' }
    Write-Output "  [V] gate denials     : $($openTrips.Count) uncleared $logScope, all historical$(if ($openTrips.Count -gt 0) { " (newest $(Format-Age (Get-Utc ([string]$openTrips[$openTrips.Count-1].ts))))" } else { '' })"
    if ($openTrips.Count -gt 0) {
        $byRule = $openTrips | Group-Object { $(if ($_.rule) { [string]$_.rule } else { "(event $($_.event))" }) } | Sort-Object Count -Descending
        Write-Output "      by rule          : $(($byRule | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', ')"
    }
    $healthScope = if ($healthCapped) { " (AT LEAST - only the last $($healthRecs.Count) record(s) of a $([Math]::Round($healthBytes / 1KB)) KB file were read)" } else { '' }
    Write-Output "  [V] health faults    : $faults outstanding in $($dirInfo.path)\health.jsonl$healthScope"
    if ($ciMain.ok) {
        $s = if ($ciMain.status) { "$($ciMain.status)/$($ciMain.conclusion) at $($ciMain.created)" } else { 'no run recorded' }
        Write-Output "  [V] CI main          : $s"
    } else {
        Write-Output "  [ ] CI main          : NOT DETERMINED - $($ciMain.why)"
    }
    if ($null -ne $ciHere) {
        if ($ciHere.ok) {
            $s = if ($ciHere.status) { "$($ciHere.status)/$($ciHere.conclusion)" } else { "no run recorded for '$branch'" }
            Write-Output "  [V] CI this branch   : $s"
        } else {
            Write-Output "  [ ] CI this branch   : NOT DETERMINED - $($ciHere.why)"
        }
    }
    if ($treeKnown) {
        $bits = @()
        if ($detached)     { $bits += 'HEAD DETACHED' }
        if ($dirty -gt 0)  { $bits += "$dirty tracked change(s)" }
        if ($untracked -gt 0) { $bits += "$untracked untracked" }
        if ($bits.Count -eq 0) { $bits += 'clean' }
        Write-Output "  [V] working tree     : $($bits -join ', ') on '$branch'"
        if ($upstream) {
            Write-Output "  [V] sync             : $ahead ahead / $behind behind $upstream"
        } else {
            Write-Output "  [V] sync             : '$branch' has NO upstream, so ahead/behind is undefined - nothing has been pushed anywhere"
        }
    } else {
        Write-Output '  [ ] working tree     : NOT DETERMINED - see COULD NOT DETERMINE'
    }
    Write-Output "  [V] state dir        : $($dirInfo.path) (source '$($dirInfo.source)', resolved=$($dirInfo.resolved))"
    if ($rows.Count -gt 0) {
        $done = @($rows | Where-Object { $_.State -eq 'DONE' }).Count
        Write-Output "  [V] plan             : $done done, $($inProgress.Count) in progress, $($blocked.Count) blocked, $($unverified.Count) unverified, of $($rows.Count) (/lw-watchtower:checklist for the detail)"
    } else {
        Write-Output '  [ ] plan             : NOT DETERMINED - checklist.json was not read'
    }
    Write-Output "  [V] probes           : $($ctx.spawned) child process(es), $($ctx.spent_ms) ms total"

    # --- could not determine ------------------------------------------------
    Write-Output ''
    Write-Output 'COULD NOT DETERMINE'
    if ($script:Unknown.Count -eq 0) {
        Write-Output '  nothing - every probe above answered.'
    } else {
        foreach ($u in $script:Unknown) {
            $lines = @(Format-LwgWrapped -Text $u -Indent '    ')
            if ($lines.Count -gt 0) {
                Write-Output ('  - ' + $lines[0].Substring(4))
                for ($i = 1; $i -lt $lines.Count; $i++) { Write-Output $lines[$i] }
            }
        }
    }

    # --- advance the marker -------------------------------------------------
    Write-Output ''
    if ($NoMark) {
        Write-Output '  marker NOT advanced (-NoMark): the next sitrep will report this same window again.'
    } elseif (-not $markerOk) {
        Write-Output '  marker NOT advanced: the state dir is unresolved, so writing one would put it where nothing reads it.'
    } else {
        $ok = Write-LwgStateJson -FileName 'sitrep.state.json' -Data @{ last_ts = $nowUtc.ToString('o') }
        if ($ok) {
            Write-Output '  marker advanced: the next sitrep reports only what changed after this one.'
        } else {
            Write-Output '  marker COULD NOT BE WRITTEN: the next sitrep will repeat this window. Nothing above is affected.'
        }
    }

    exit 0

} catch {
    Write-Output "LW-WATCHTOWER sitrep could not be produced: $($_.Exception.Message)"
    Write-Output 'Nothing above is a situation report. In particular, the absence of a problem here is not evidence there is none.'
    exit 3
}
