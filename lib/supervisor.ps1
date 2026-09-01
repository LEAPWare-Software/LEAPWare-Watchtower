#requires -version 5
<#
  LW-WATCHTOWER failure_capture module - Claude Code hook handler.

  Absorbed in Phase 2 from ~/.claude/health/supervisor.ps1. The behaviour that
  matters is unchanged and deliberately so: the record schema, the append-retry
  ladder, the exit-2 alerting semantics and the alerted.json dedupe are all
  carried over verbatim. What changed is where it writes (the plugin data dir,
  via Get-LwgStateDir) and that it now gates on the failure_capture flag.

  Invoked from hooks/hooks.json in exec form:
      command: "powershell"
      args:    ["-NoProfile","-ExecutionPolicy","Bypass","-File",
                "${CLAUDE_PLUGIN_ROOT}/lib/supervisor.ps1","-HookEvent","<Event>"]

  Reads the hook JSON payload on stdin, appends a record to health.jsonl, and for
  failure events exits 2 so an asyncRewake hook injects a task-notification into the
  live session (that exit-2 path is the ONLY way to alert the orchestrator).

  Exit codes:  0 = healthy / nothing to report     2 = alert the orchestrator
  Any internal error exits 0 - a broken supervisor must never break the session.

  THAT PROMISE HAS EXACTLY ONE EXCEPTION AND IT IS STATED HERE RATHER THAN ONLY
  IN THE BODY. Parameter binding runs BEFORE any statement in this script, so a
  missing -HookEvent or one outside the [ValidateSet] below exits 1 with a raw
  error record and no try can catch it. That is reachable only from a wrong
  hooks.json registration, never from a payload, and it is left open on purpose
  - see the note above the setup block. Six OTHER statements used to sit outside
  the try and exit 1 the same way; those are closed. This line said "any
  internal error" with no exception until 3 August 2026, which was the header
  overstating the fix that had just been made underneath it.
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('SessionStart', 'PostToolUseFailure', 'Stop', 'SubagentStop', 'StopFailure')]
    [string]$HookEvent
)

$ErrorActionPreference = 'Stop'

# --- THE SETUP IS INSIDE THE HANDLER, AND IT WAS NOT -------------------------
# THE HEADER PROMISES "any internal error exits 0" AND SIX STATEMENTS RAN
# OUTSIDE THE ONLY try THAT KEPT IT: the dot-source, the stdin read, the config
# read, the repo resolve, and both Test-LwgModule calls. Under
# $ErrorActionPreference = 'Stop' a terminating error in any of them left
# PowerShell to print a raw error record to stderr and exit 1 - the two things
# the header says cannot happen. The blast radius is per-event and none of it is
# cosmetic: this handler is registered on five events, exit 2 is its DESIGNED
# alerting channel on Stop and PostToolUseFailure, so exit 1 was a third,
# undesigned outcome on the same events, and on SessionStart it landed at the
# top of the session where it is most visible and least actionable. Nothing was
# recorded either: the catch at the bottom writes a supervisor_error record the
# status line counts as a fault, and a failure above the old boundary wrote
# nothing at all, rendering as "nothing was found to read about this session" -
# indistinguishable from a supervisor that was never registered.
#
# WHAT CAN ACTUALLY THROW THERE is unlikely one at a time and is exactly the
# class the contract exists for: a common.ps1 that is absent, locked or fails to
# parse - which is what a half-completed /lw-watchtower:update leaves behind - plus a
# malformed hook payload, an unreadable config.json, filesystem work on a
# payload-supplied cwd, and a Test-LwgModule indexing a registry that does not
# exist because the dot-source produced no definitions.
#
# THE OTHER FOUR HOOK SCRIPTS ALREADY DREW THE BOUNDARY HERE.
# lib/stop_advisories.ps1, lib/session_start.ps1 and lib/post_edit.ps1 all put
# their dot-source inside their own try. This file was the outlier.
#
# ONE EXIT-1 PATH REMAINS AND NO try CAN CLOSE IT: the param() block above has
# [Parameter(Mandatory)] and [ValidateSet], and parameter binding runs BEFORE
# any statement in the script body. An -HookEvent outside the set, or a missing
# one, still fails binding and still exits 1 with a raw error record. That is
# reachable only from a wrong hooks.json registration, never from a payload, and
# closing it would mean dropping the validation that makes a wrong registration
# loud. It is named here rather than left for the next reader to discover.
#
# `exit` is not catchable in PowerShell, so the `exit 0`s inside the handler -
# the module gate and every branch of the switch - still terminate the process
# with their own code rather than falling into it. Verified on 5.1 rather than
# assumed.
#
# HOW THE BOUNDARY WAS MOVED, because the obvious way is worse. Wrapping the
# whole file in a second try would re-indent 140 lines and leave two handlers
# with the same job. Instead the six statements MOVED DOWN into the handler that
# already exists, and only the definitions stayed here: a function definition
# executes nothing, so it cannot throw, and the bodies below resolve
# common.ps1's helpers at CALL time, by which point the dot-source inside the
# handler has run.
$LogName = 'health.jsonl'

function ConvertTo-SafeField($v) {
    <#
      One payload-derived value, made fit to appear in a log record: redacted
      through Get-LwgRedacted and truncated to $script:LwgLogFieldMax.

      NOT A SECOND RULE. lib/gate_delegate.ps1 has always put its payload-derived
      error through Get-LwgRedacted at 200 characters, and this file - writing
      the same class of data, into a log the status line parses on every single
      render - wrote it raw and unbounded. That is the same helper at the same
      cap, reached through the same constant, so the two cannot drift apart.

      Numbers and booleans pass through as themselves: failed_tasks must stay a
      JSON number or the status line's [int] read of it changes meaning, and
      is_interrupt must stay a JSON bool. Everything else is stringified first -
      a field the CLI hands us as an object is still payload, and
      "[System.Object]" in a log line is not evidence of anything.

      THE ConvertTo-Json BELOW MANUFACTURED THE ONE SHAPE THE REDACTION COULD
      NOT SEE, and it did so for every non-scalar field of every record written
      here. Until 3 August 2026 Get-LwgRedacted's generic rule required a key
      name to be immediately followed by a colon or an equals sign, so
      {"api_key":"<value>"} - which is precisely what this line produces out of
      a payload object - went through unchanged and into health.jsonl, and on
      the PostToolUseFailure path into the stderr that asyncRewake injects into
      the live session. The fix is in lib/common.ps1, not here.

      REDACTING THE OBJECT BEFORE SERIALISING IT WAS CONSIDERED AND REFUSED,
      and the reasons are worth stating because it is the obvious move. Walking
      the object and masking any property whose NAME looks like a credential
      would be more precise than matching the serialised text - it would catch
      a value containing a comma or a quote, which the string rules cannot.
      Three things outweigh that:

        IT WOULD FIX ONE CALLER OUT OF TWELVE. Get-LwgRedacted is called from
        eleven other places, and every one of them hands it a STRING it did not
        build: a failed task's stderr from git or gh (which prints JSON error
        bodies and Authorization headers), an exception message, a config
        value. Those need the string rules regardless, so an object walk would
        be added to them rather than instead of them.

        IT WOULD BE THE SECOND RULE THIS FUNCTION EXISTS TO NOT BE. See the
        paragraph above: the whole reason this helper routes through
        Get-LwgRedacted at $script:LwgLogFieldMax is that the supervisor and
        gate_delegate cannot then drift apart. A masking rule that lives here
        and nowhere else is a rule only this file gets, which is how the two
        diverged the first time.

        IT WOULD NEED A DEPTH AND CYCLE GUARD OF ITS OWN, in a hook whose one
        hard requirement is that it never throws. ConvertTo-Json already has
        -Depth 4 and already handles the cycle; an object walk would have to
        reimplement both.

      What that trade costs is named rather than hidden: a credential whose
      VALUE contains a quote, comma, semicolon, brace, bracket or backslash is
      not fully masked by the string rules, and an object walk would have
      caught it. That limitation is listed in Get-LwgRedacted's own docstring
      and in SECURITY.md, where a reader looking for the boundary will find it.
    #>
    if ($null -eq $v) { return $null }
    if ($v -is [bool] -or $v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal]) { return $v }

    $s = ''
    if ($v -is [string]) { $s = $v }
    else { try { $s = ($v | ConvertTo-Json -Depth 4 -Compress) } catch { $s = [string]$v } }
    return (Get-LwgRedacted -Text $s -MaxLength $script:LwgLogFieldMax)
}

function Write-Record($obj) {
    # THE CAP IS APPLIED HERE, at the single choke point every branch below goes
    # through, and not at the ten call sites that build the fields. A field
    # added later is capped because it was written, not because whoever added it
    # remembered - which is what went wrong the first time.
    #
    # What it cost to leave uncapped: one crafted payload produced a
    # 200,199-character line in health.jsonl. statusline.ps1 reads the tail of
    # that file on every render, and the render median went from ~1.3 s clean to
    # ~10.6 s with one such record and ~106 s with ten. Rotation carried the last
    # 500 lines forward, so it PRESERVED the poison rather than ageing it out.
    # Both of those were fixed on the reading side as well, and neither fix
    # removes the reason to cap the write: this is the only place in the chain
    # that knows the value is payload rather than evidence.
    try {
        $safe = [ordered]@{}
        foreach ($k in @($obj.Keys)) { $safe[$k] = ConvertTo-SafeField $obj[$k] }
        # Rotation is NOT done here. It used to be, and that quietly made
        # log_rotation a sub-feature of failure_capture - see the block below.
        # Add-LwgLine carries the original 5-attempt 20/40/60/80/100 ms retry -
        # concurrent hooks race on this file and must not throw.
        Add-LwgLine -FileName $LogName -Line ($safe | ConvertTo-Json -Depth 6 -Compress) | Out-Null
    } catch { }
}

function New-Record($extra) {
    $r = [ordered]@{
        ts      = (Get-Date).ToUniversalTime().ToString('o')
        event   = $HookEvent
        session = $script:payload.session_id
        cwd     = $script:payload.cwd
    }
    if ($extra) { foreach ($k in $extra.Keys) { $r[$k] = $extra[$k] } }
    return $r
}

# --- failing background tasks ---------------------------------------------
function Get-FailedTasks {
    $bad = @()
    if ($payload.background_tasks) {
        foreach ($t in $payload.background_tasks) {
            if ($t.status -in @('failed', 'killed')) {
                # Capped HERE, once, so the id that is matched against
                # alerted.json is the same value that was written into it. A cap
                # applied on the write alone would make a long id never match
                # what it stored, and a dedupe that silently stops deduping
                # re-alerts the same dead task at every turn end - the exact
                # failure C1 exists to pin.
                $bad += [pscustomobject]@{
                    id          = ConvertTo-SafeField $t.id
                    type        = ConvertTo-SafeField $t.type
                    status      = ConvertTo-SafeField $t.status
                    description = ConvertTo-SafeField $t.description
                    agent_type  = ConvertTo-SafeField $t.agent_type
                }
            }
        }
    }
    return $bad
}

# --- orphaned subagents (orphan_watch, OFF by default) ----------------------
# Get-FailedTasks above is BLIND to a subagent killed mid-flight: it counts
# only `failed`/`killed` entries in $payload.background_tasks, and a killed
# subagent appears in that list not at all. Measured on 1 August 2026: a
# cross-check of 70 subagent transcripts against this very log found FOUR
# transcripts with no SubagentStop record - four agents that died and left
# failed_tasks reading 0 - and the log held ZERO PostToolUseFailure records in
# 1,175 entries. "Green" here has only ever meant "no Agent tool call RETURNED
# an error", and this function is the reconciliation that closes the gap:
#
#     an agent SPAWNED (its transcript exists in this session's subagents dir)
#     that never STOPPED (no SubagentStop record for its id in health.jsonl)
#     and has gone SILENT (transcript unwritten for stale_minutes, default 15,
#     above the 10-minute Bash ceiling so one long tool call is not "silent")
#     is an ORPHAN.
#
# It sits BELOW the failure_capture gate on purpose, and the coupling is
# correct rather than convenient: SubagentStop records are what failure_capture
# WRITES, and reconciling transcripts against records nothing was writing would
# call every finished agent an orphan. The same reasoning bounds the verdict at
# runtime: a session with NO health records at all yields no orphans, because
# the recorder's silence proves nothing.

function Get-LwgFailedTaskIds {
    <#
      Agent ids the HARNESS ITSELF has declared failed, read out of the PARENT
      transcript. Returns @{ id = summary }.

      THIS IS THE ONLY STATED, NON-INFERRED DEATH SIGNAL AVAILABLE, and finding
      it changes what this module is. Everything else here reasons from silence:
      no stop record, transcript gone quiet, wait out a threshold, conclude.
      The harness meanwhile writes a task-notification into the parent
      transcript naming the agent and saying <status>failed</status>, in
      milliseconds, for every death - measured on 10 August 2026 across all
      FOUR deaths in one session:

          abc279cf  03:32:45.448Z  terminated early due to an API error
          a67fc028  03:32:45.523Z  terminated early due to an API error
          ae2d5a57  04:52:02.008Z  stalled: no progress for 600s
          a97a0bd1  05:27:18.752Z  terminated early due to an API error

      The two at 03:32:45 were not reported until the 05:02:46 Stop - NINETY
      MINUTES of a fault the harness had already stated in writing. The stall
      had no isApiErrorMessage tail at all (a watchdog kill leaves "[Request
      interrupted by user]"), so the transcript-sniffing fast path could never
      have caught it; only the 15-minute silence rule would, late and labelled
      'orphan' rather than 'died'.

      NO SILENCE THRESHOLD APPLIES to an id found here. A status of `failed` is
      a terminal statement about a specific agent, not an inference that could
      be premature. A transcript-tail fast path that guessed at this from an
      isApiErrorMessage record was removed on 10 August 2026 after it was
      measured reporting a live agent dead; see Get-OrphanAgents for the four
      recovery gaps that killed it.

      LIMITS, because this is a tail and not an index. The window is bounded, so
      a notification that has scrolled out of it is not seen; the silence rule
      remains the backstop and is deliberately not weakened. Parsing is a regex
      over the raw line rather than ConvertFrom-Json, because the notification is
      XML-ish text nested inside a JSON string field and the id is what matters -
      a shape change makes this return nothing, which degrades to the old
      behaviour rather than to a false alert. NEVER THROWS.
    #>
    param([string]$Path)

    $out = @{}
    try {
        if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.File]::Exists($Path)) { return $out }
        foreach ($line in @(Get-LwgTailLines -Path $Path -Bytes 262144)) {
            $s = [string]$line
            if ($s.Length -lt 20) { continue }
            if ($s.IndexOf('<task-id>', [StringComparison]::Ordinal) -lt 0) { continue }
            if ($s.IndexOf('<status>failed</status>', [StringComparison]::Ordinal) -lt 0) { continue }
            $m = [regex]::Match($s, '<task-id>([^<]{1,64})</task-id>')
            if (-not $m.Success) { continue }
            $id = $m.Groups[1].Value
            $sum = ''
            $ms = [regex]::Match($s, '<summary>([^<]{0,400})</summary>')
            if ($ms.Success) { $sum = $ms.Groups[1].Value -replace '\\n', ' ' }
            $out[$id] = $sum
        }
    } catch { }
    return $out
}

function Get-OrphanAgents {
    $out = @()
    try {
        if (-not (Test-LwgModule -Name 'orphan_watch' -Config $script:cfg -Repo $script:repo)) { return $out }

        $sid = [string]$payload.session_id
        $tp  = [string]$payload.transcript_path
        if ([string]::IsNullOrWhiteSpace($sid) -or [string]::IsNullOrWhiteSpace($tp)) { return $out }

        $base = [IO.Path]::GetDirectoryName($tp)
        if ([string]::IsNullOrWhiteSpace($base)) { return $out }
        $sub = [IO.Path]::Combine($base, $sid, 'subagents')
        if (-not [IO.Directory]::Exists($sub)) { return $out }

        $staleMin = 15
        try { $staleMin = [int](Get-LwgModuleOption -Config $script:cfg -Module 'orphan_watch' -Key 'stale_minutes' -Default 15) } catch { }
        if ($staleMin -lt 1) { $staleMin = 1 }

        # THERE IS NO SECOND, SHORTER THRESHOLD, AND THE REASON IS MEASURED.
        #
        # A five-minute fast path keyed on an isApiErrorMessage transcript tail
        # WAS shipped here, on the reasoning that such a record states a cause
        # rather than inferring one, with rate_limit and 529 excluded as
        # back-pressure that pauses and resumes. An adversarial re-derivation
        # over 1,050 transcripts on this install falsified it:
        #
        #   gap      error          apiErrorStatus  text
        #     25.4s  server_error   529             529 Overloaded
        #     93.8s  server_error   (none)          Response stalled mid-stream
        #  3,824.0s  server_error   529             529 Overloaded
        #  4,011.2s  server_error   (none)          Server error mid-response
        #
        # All four RECOVERED and carried on. The 4,011.2 s one carries NO 529 and
        # NO "Overloaded", so it fell straight through the class exclusion onto
        # the five-minute path: a live agent reported DIED after five minutes,
        # which then worked for another sixty-two. A measured false-positive rate
        # of ONE IN FOUR, on the exact control that exists to stop an operator
        # being told something is dead when it is not.
        #
        # Nor can the threshold be raised to fix it: the longest live recovery
        # observed is 66.85 MINUTES, so a safe fast path would have to wait
        # longer than the fifteen-minute silence rule it was meant to beat. IT
        # BUYS NOTHING, AND IT IS GONE.
        #
        # What replaces it is strictly better on both axes: the harness's own
        # <status>failed</status> task-notification, read by Get-LwgFailedTaskIds
        # above, which is terminal by construction (a recovering agent is never
        # given one) and is believed with NO threshold at all. A death is
        # therefore reported FASTER than the deleted fast path managed, and an
        # agent that is merely struggling is not reported at all.
        #
        # DO NOT REINTRODUCE A THRESHOLD KEYED ON TRANSCRIPT PROSE. The
        # classification failed because it substring-matched English that the
        # API is free to reword; the one genuine 529 was distinguishable only by
        # a structured apiErrorStatus field, and even that does not separate the
        # two long recoveries from each other.

        $recs = @(Get-LwgHealthRecords -Session $sid -Tail 1500)
        if ($recs.Count -eq 0) { return $out }   # recorder never saw this session - its silence proves nothing
        $stopped = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

        # THE EVIDENCE HORIZON, and without it this module resurrects agents it
        # already saw finish cleanly.
        #
        # Get-LwgHealthRecords reads a BOUNDED tail - 512 KB, then the last 1500
        # lines - and the byte window is applied BEFORE the session filter. This
        # install's log is already past both at 1,743 records and 596 KB, and
        # log_rotation makes it worse by design: rotation keeps the last 500
        # lines, so a SubagentStop record can leave the window while the agent's
        # transcript sits on disk forever.
        #
        # The whole verdict is "no stop record exists", so a lost record does not
        # weaken the conclusion, it INVERTS it: a cleanly stopped agent becomes an
        # orphan and stays one, and under the peak-since-Resolved indicator that
        # is a red light nobody can turn off.
        #
        # Absence of evidence is only evidence of absence where we can prove we
        # looked at all of it. SessionStart is written once per session before any
        # agent can be dispatched, so its presence in the window proves the window
        # reaches back past every SubagentStop this session could have written.
        # Without it we know only that the window begins somewhere mid-session,
        # and the earliest record we can see is the furthest back we may judge.
        # This is the same principle as the $recs.Count check above - the
        # recorder's silence proves nothing - applied to a window rather than to
        # a file.
        $sawStart = $false
        $horizon  = [datetime]::MaxValue
        foreach ($r in $recs) {
            if ([string]$r.event -eq 'SubagentStop' -and -not [string]::IsNullOrWhiteSpace([string]$r.agent_id)) {
                [void]$stopped.Add([string]$r.agent_id)
            }
            if ([string]$r.event -eq 'SessionStart') { $sawStart = $true }
            try {
                $t = ([datetime]::Parse([string]$r.ts)).ToUniversalTime()
                if ($t -lt $horizon) { $horizon = $t }
            } catch { }
        }
        # A complete window judges everything; a truncated one judges only what
        # it can see the whole of.
        if ($sawStart) { $horizon = [datetime]::MinValue }
        elseif ($horizon -eq [datetime]::MaxValue) { return $out }

        # Read once per call, not once per transcript: one bounded tail of the
        # parent, reused across every candidate below.
        $failedIds = Get-LwgFailedTaskIds -Path $tp

        $files = @()
        try { $files = @([IO.Directory]::GetFiles($sub, 'agent-*.jsonl')) } catch { }
        $n = 0
        foreach ($f in $files) {
            $n++; if ($n -gt 200) { break }
            $leaf = [IO.Path]::GetFileName($f)
            # agent-<id>.jsonl -> <id>; the glob also lets agent-*.meta.json
            # through on 8.3 short-name matching in principle, so the suffix is
            # re-checked in managed code rather than trusted from the pattern.
            if (-not $leaf.EndsWith('.jsonl', [StringComparison]::OrdinalIgnoreCase)) { continue }
            if ($leaf.Length -le 12) { continue }
            $id = $leaf.Substring(6, $leaf.Length - 6 - 6)
            if ($stopped.Contains($id)) { continue }
            $lastWrite = [datetime]::MinValue
            try { $lastWrite = [IO.File]::GetLastWriteTimeUtc($f) } catch { continue }
            # Past the evidence horizon this agent's SubagentStop record may
            # simply have scrolled out of the window - see the horizon block
            # above. Abstaining costs a late alert; not abstaining manufactures a
            # permanent false one.
            if ($lastWrite -lt $horizon) { continue }
            $age = ([datetime]::UtcNow - $lastWrite).TotalMinutes

            # Read the STATED cause before falling back to inference. A transcript
            # whose last record is an API error is a death the harness has already
            # described in writing; anything else is only silence, and silence has
            # to serve the full stale window before it means anything.
            $reason = 'orphan'
            $detail = ''
            $need   = $staleMin
            $stated = $false

            if ($failedIds.ContainsKey($id)) {
                # The harness NAMED this agent as failed. Strongest evidence
                # available, and the only kind that is not an inference, so it
                # serves NO silence threshold at all - see Get-LwgFailedTaskIds
                # for the 90-minute delay this exists to remove, and for why the
                # 600s stall could never have been caught any other way.
                $reason = 'died'
                # The summary arrives JSON-escaped inside the transcript's own
                # string field; unescape the quotes so the agent's description
                # is readable rather than littered with backslashes.
                $detail = ([string]$failedIds[$id]) -replace '\\"', '"'
                $need   = 0
                $stated = $true
            }
            # NO else-branch. Everything the harness has not named is plain
            # silence and serves the full window - see the block above for the
            # measured reason the transcript-tail fast path was removed rather
            # than tuned.

            if ($age -lt $need) { continue }   # still running, or still retrying

            $out += [pscustomobject]@{
                id          = $id
                age_minutes = [int][Math]::Floor($age)
                reason      = $reason
                detail      = $detail
                stated      = $stated
            }
        }
    } catch { }
    return $out
}

function Write-LwgDeadAgentBlock {
    <#
      The stderr block describing dead/orphaned agents. Shared verbatim by the
      Stop and SubagentStop branches so the two can never drift into telling the
      orchestrator different things about the same agent.

      Every payload-derived value on this stream goes through ConvertTo-SafeField
      for the same reason the log record does: this text is injected into the live
      session, so an unbounded field spends the orchestrator's context.
    #>
    param($List)

    $died = @($List | Where-Object { $_.reason -eq 'died' })
    $silent = @($List | Where-Object { $_.reason -ne 'died' })

    if ($died.Count -gt 0) {
        [Console]::Error.WriteLine("$($died.Count) subagent(s) DIED mid-flight - the transcript records the cause:")
        foreach ($o in $died) {
            [Console]::Error.WriteLine("  - agent $($o.id): $(ConvertTo-SafeField $o.detail) (no SubagentStop record; transcript silent $($o.age_minutes) min)")
        }
    }
    if ($silent.Count -gt 0) {
        [Console]::Error.WriteLine("$($silent.Count) subagent(s) appear ORPHANED - spawned, never stopped, transcript silent:")
        foreach ($o in $silent) {
            [Console]::Error.WriteLine("  - agent $($o.id): no SubagentStop record, transcript last written $($o.age_minutes) minute(s) ago")
        }
    }
    # The provenance sentence is per-class and must stay that way. Saying
    # "inferred, not reported" over a death the harness NAMED would be exactly
    # the false claim this plugin exists to catch, and it would also teach an
    # orchestrator to discount the strongest evidence on offer.
    if (@($died | Where-Object { $_.stated }).Count -gt 0) {
        [Console]::Error.WriteLine("The quoted text above is the HARNESS's own task-notification for that agent - a REPORTED failure, not an inference. No PostToolUseFailure and no SubagentStop hook event is emitted for it, which is why nothing else here saw it.")
    }
    if (@($died | Where-Object { -not $_.stated }).Count -gt 0 -or $silent.Count -gt 0) {
        [Console]::Error.WriteLine("Any agent above WITHOUT a quoted harness notification is INFERRED from silence plus a missing SubagentStop record, not reported.")
    }
    [Console]::Error.WriteLine("Any message queued to these agents will NEVER be delivered and any work assigned to them is NOT done. Read the transcript tail to see where it died, respawn with full context if the work still matters, and do not report the task as complete without independent evidence.")
}

function Save-LwgAlerted {
    <#
      Write the dedupe ledger with the SAME 5-attempt 20/40/60/80/100 ms retry
      ladder Add-LwgLine already uses for health.jsonl.

      Why it needs one at all: concurrent hooks race on this directory - that is
      documented next door as the reason the LOG write retries - and this file
      had a bare Set-Content. Losing the write is not cosmetic, because this
      ledger IS the dedupe: a dropped update means the agent is never recorded as
      alerted, so it alerts again at the next trigger, and again after that.

      The race got materially more likely when the reconciliation was added to
      the SubagentStop branch: Stop and SubagentStop now both write this file,
      and SubagentStop fires roughly 1.5x as often as Stop on this install.

      Best-effort by contract, like every other write in this file. A ledger we
      could not update costs a duplicate alert; a supervisor that throws costs
      the session.
    #>
    param([string]$Path, $Entries)

    $json = ConvertTo-Json -InputObject @([string[]]@($Entries)) -Compress
    for ($i = 0; $i -lt 5; $i++) {
        try {
            Set-Content -LiteralPath $Path -Value $json -Encoding utf8 -ErrorAction Stop
            return $true
        } catch {
            Start-Sleep -Milliseconds (20 * ($i + 1))
        }
    }
    return $false
}

function Select-LwgUnalertedAgents {
    <#
      The subset of $List not already alerted for, committing the survivors to
      alerted.json so the same dead agent is reported ONCE rather than at every
      trigger for the rest of the session.

      Stop and SubagentStop share this ledger and the same 'orphan:' key prefix -
      deliberately, so whichever fires first wins and the other stays silent. The
      prefix is unchanged from the Stop-only implementation, so ids already
      recorded by an earlier build still suppress correctly.
    #>
    param($List)

    if (@($List).Count -eq 0) { return @() }
    $seenPath = Join-Path (Get-LwgStateDir) 'alerted.json'
    $seen = @()
    if (Test-Path $seenPath) {
        # Flatten hard - same reasoning as the Stop branch: a single-entry file
        # comes back as a bare string and a multi-entry one can arrive nested,
        # and either shape makes -notcontains stop matching.
        try {
            $seen = @(Get-Content $seenPath -Raw | ConvertFrom-Json |
                      ForEach-Object { $_ } | ForEach-Object { [string]$_ })
        } catch { $seen = @() }
    }
    $fresh = @($List | Where-Object { $seen -notcontains ('orphan:' + [string]$_.id) })
    if ($fresh.Count -eq 0) { return @() }
    try {
        $updated = @(@($seen) + @($fresh | ForEach-Object { 'orphan:' + [string]$_.id })) | Select-Object -Last 200
        [void](Save-LwgAlerted -Path $seenPath -Entries $updated)
    } catch { }
    return $fresh
}

try {
# --- everything below is inside the exits-0 handler ------------------------
# See the block above the definitions for why the boundary is here and what it
# still does not cover.

. (Join-Path $PSScriptRoot 'common.ps1')

# --- read the hook payload -------------------------------------------------
$payload = Read-LwgStdin
$script:payload = $payload

$script:cfg  = Get-LwgConfig
$script:repo = Get-LwgRepo $payload

# --- log_rotation ----------------------------------------------------------
# ABOVE the failure_capture gate, and that position is the whole point.
#
# This call used to live inside Write-Record, which is downstream of the gate
# below. log_rotation therefore only ever ran when failure_capture was ALSO on:
# switching failure capture off left health.jsonl uncapped, growing without
# bound, with log_rotation still reporting itself active and nothing saying
# otherwise. A module that is enabled, implemented and unreachable is the exact
# defect this plugin exists to catch.
#
# The two are now independent in both directions. failure_capture off stops the
# WRITES to health.jsonl but never the cap on its size; log_rotation off leaves
# the file to grow, which is what that flag means.
#
# Cheap enough for a hook path by construction: Invoke-LwgRotate is one
# Test-Path plus one Get-Item length compare, and returns immediately while the
# file is under the cap - which is every run but one in roughly eleven thousand.
#
# TWO FILES, AND THE SECOND ONE WAS THE ONE THE DOCUMENTS NAMED. $LogName is a
# file-scope constant, so 'health.jsonl' was the only value this module ever
# rotated - while docs/architecture.md described `lw-watchtower.jsonl` as "rotated at
# 5 MB carrying 500 records forward", and README.md, docs/modules.md and
# docs/limitations.md all described this module as keeping the state dir
# bounded. lw-watchtower.jsonl is written by every module on every hook event of every
# session and nothing rolled it. That is not only housekeeping: /lw-watchtower:sitrep
# reports governance history from a bounded tail of that file, so as it grew the
# report got quieter and nothing said so.
#
# The cost argument above covers both calls and is the reason a second one is
# acceptable here rather than assumed to be: each is one Test-Path plus one
# Get-Item length compare and returns immediately under the cap.
#
# WHAT THIS DOES NOT BOUND, so the four documents are not made true by it alone:
# advisory-<sessionkey>.json and edits-<sessionkey>.txt are one file per session
# each, kept for ever, and nothing sweeps them. The per-session edit list now
# rolls at 256 KB (lib/post_edit.ps1) but its .1 archive is not swept either.
# "The state dir is bounded" is still not a true sentence about this plugin.
if (Test-LwgModule -Name 'log_rotation' -Config $script:cfg -Repo $script:repo) {
    try { Invoke-LwgRotate -FileName $LogName | Out-Null } catch { }
    try { Invoke-LwgRotate -FileName 'lw-watchtower.jsonl' | Out-Null } catch { }
}

# --- module gate -----------------------------------------------------------
# Nothing below this line runs - not even a log write - when failure_capture is
# switched off for this repo or globally.
if (-not (Test-LwgModule -Name 'failure_capture' -Config $script:cfg -Repo $script:repo)) { exit 0 }

    switch ($HookEvent) {

        'SessionStart' {
            # The orphaned-worker check that used to live here read
            # ~/.claude/daemon/roster.json. That file does not exist, nothing in
            # this system writes it, and no daemon is running - so the check
            # reported "0 orphans" unconditionally for its entire life. Removed
            # in Phase 2 rather than kept as a monitor that cannot observe
            # anything; the `orphans` field goes with it.
            Write-Record (New-Record @{ source = $payload.source })
            exit 0
        }

        'PostToolUseFailure' {
            $rec = New-Record @{
                tool         = $payload.tool_name
                tool_use_id  = $payload.tool_use_id
                error        = $payload.error
                is_interrupt = [bool]$payload.is_interrupt
                agent_type   = $payload.tool_input.subagent_type
                description  = $payload.tool_input.description
            }
            Write-Record $rec

            # A user interrupt is not a fault - do not alert.
            if ($payload.is_interrupt) { exit 0 }

            # Capped for the same reason the record is, and it is the same data:
            # this text is injected into the live session as a task
            # notification, so an unbounded field here spends the orchestrator's
            # context instead of the status line's render time. One crafted
            # payload put 200,199 characters on this stream.
            $who = if ($payload.tool_input.subagent_type) { $payload.tool_input.subagent_type } else { $payload.tool_name }
            $who = ConvertTo-SafeField $who
            $what = if ($payload.tool_input.description) { " ($(ConvertTo-SafeField $payload.tool_input.description))" } else { '' }
            [Console]::Error.WriteLine("Subagent dispatch failed: $who$what")
            [Console]::Error.WriteLine("Error: $(ConvertTo-SafeField $payload.error)")
            [Console]::Error.WriteLine("Assess whether this needs a retry (one model tier up), an lw-healer dispatch, or should be reported to the user as blocked.")
            exit 2
        }

        'Stop' {
            # @() is load-bearing: a one-element return unrolls to a bare
            # PSCustomObject, whose .Count is $null, and the status line reads
            # [int]$null as 0. Without the wrap a single failed background task
            # logs "failed_tasks":null and HH never goes red. Two such records
            # exist in the inherited log.
            $bad = @(Get-FailedTasks)

            # Orphans are counted only when orphan_watch is on, and the record
            # field is written only then too: an "orphans":0 stamped by a run
            # that never looked would be exactly the false green this plugin
            # exists to refuse. The flag is resolved here AND inside
            # Get-OrphanAgents; the duplication is a guard, not an accident.
            $orphOn = Test-LwgModule -Name 'orphan_watch' -Config $script:cfg -Repo $script:repo
            $orph = @()
            if ($orphOn) { $orph = @(Get-OrphanAgents) }

            # THE DEDUPE LEDGER IS READ BEFORE THE RECORD IS WRITTEN, not after.
            # It used to be read below, which meant the record could only ever
            # carry the STANDING orphan count - and the status line takes a PEAK
            # of that since the last Resolved marker, so an acknowledged orphan
            # re-raised HH at the very next turn end and /lw-watchtower:resolve could
            # never stick. See the SubagentStop branch for the full account.
            $seenPath = Join-Path (Get-LwgStateDir) 'alerted.json'
            $seen = @()
            if (Test-Path $seenPath) {
                # Flatten hard. ConvertFrom-Json returns a single-entry file as a
                # bare string and can hand a multi-entry file back nested one level
                # deep; either shape makes -notcontains stop matching, and a dedupe
                # that silently stops deduping re-alerts the same dead task on
                # every turn. The double ForEach unnests, then stringifies.
                try {
                    $seen = @(Get-Content $seenPath -Raw | ConvertFrom-Json |
                              ForEach-Object { $_ } | ForEach-Object { [string]$_ })
                } catch { $seen = @() }
            }

            $rec = @{ failed_tasks = $bad.Count }
            if ($orphOn) {
                # Standing count = evidence; new count = what the indicator reads.
                $rec['orphans']     = $orph.Count
                $rec['orphans_new'] = @($orph | Where-Object { $seen -notcontains ('orphan:' + [string]$_.id) }).Count
            }
            Write-Record (New-Record $rec)
            if ($bad.Count -eq 0 -and $orph.Count -eq 0) { exit 0 }

            # Loop guards. Without these the same failed task re-alerts every turn.
            if ($payload.stop_hook_active) { exit 0 }

            $bad  = @($bad  | Where-Object { $seen -notcontains [string]$_.id })
            # Orphans share the same dedupe ledger under a namespaced key, so
            # the same dead agent alerts once, not at every turn end for the
            # rest of the session.
            $orph = @($orph | Where-Object { $seen -notcontains ('orphan:' + [string]$_.id) })
            if ($bad.Count -eq 0 -and $orph.Count -eq 0) { exit 0 }

            try {
                $updated = @(@($seen) +
                             @($bad  | ForEach-Object { [string]$_.id }) +
                             @($orph | ForEach-Object { 'orphan:' + [string]$_.id })) | Select-Object -Last 200
                # -InputObject with an explicit @() keeps a one-element list a JSON
                # array instead of a bare string - the shape that seeded the
                # nesting. That now lives inside Save-LwgAlerted, which also
                # carries the retry ladder this write was missing.
                [void](Save-LwgAlerted -Path $seenPath -Entries $updated)
            } catch { }

            if ($bad.Count -gt 0) {
                [Console]::Error.WriteLine("$($bad.Count) background task(s) ended in a failed state:")
                foreach ($b in $bad) {
                    # Already capped - Get-FailedTasks builds these fields through
                    # ConvertTo-SafeField, so the id that goes into alerted.json and
                    # the text that goes onto this stream are the same bounded value.
                    $who = ''
                    if ($b.agent_type) { $who = " (agent: $($b.agent_type))" }
                    [Console]::Error.WriteLine("  - [$($b.type)] $($b.status): $($b.description)$who")
                }
            }
            # Shared with the SubagentStop branch so the two triggers can never
            # describe the same dead agent differently.
            if ($orph.Count -gt 0) { Write-LwgDeadAgentBlock -List $orph }
            if ($bad.Count -gt 0) {
                [Console]::Error.WriteLine("Do not close out the turn as successful without addressing these.")
            }
            exit 2
        }

        'SubagentStop' {
            # The record goes down FIRST and unchanged - this branch's existing
            # job is not touched by anything below it.
            Write-Record (New-Record @{
                agent_id       = $payload.agent_id
                agent_type     = $payload.agent_type
                transcript     = $payload.agent_transcript_path
                sibling_failed = @(Get-FailedTasks).Count   # @() - see the Stop branch
            })

            # WHY THE RECONCILIATION ALSO RUNS HERE, and it is the whole of the
            # fix for a MEASURED blind spot rather than a theoretical one.
            #
            # On 10 August 2026 two subagents died on "API Error: Connection
            # closed mid-response" at 04:20:12Z and 04:20:15Z. The check ran at
            # the 04:22:20Z Stop, found them 2 minutes silent - correctly under
            # the 15-minute threshold - and said nothing. The NEXT Stop was at
            # 05:02:46Z, and only then did it alert, 42 minutes after the deaths.
            #
            # Of those 42 minutes only 15 were the threshold. The other ~27 were
            # spent waiting for a Stop to come round, and THREE SubagentStop
            # events fired in that window (04:22:21, 04:53:27, 05:01:12) with the
            # check wired to none of them. Stop fires at TURN END, which is
            # precisely what does not happen while the orchestrator is busy
            # dispatching work - so the trigger was scarcest exactly when agents
            # were dying. Across this install's whole log SubagentStop outnumbers
            # Stop 991 to 662.
            #
            # This does not replace the Stop check or relax any threshold; it adds
            # a second, denser trigger for the same reconciliation.
            if (-not (Test-LwgModule -Name 'orphan_watch' -Config $script:cfg -Repo $script:repo)) { exit 0 }

            $orph = @(Get-OrphanAgents)
            if ($orph.Count -eq 0) { exit 0 }

            # DEDUPE FIRST, THEN RECORD, and the order is the whole fix for a
            # health indicator that could not be cleared.
            #
            # An orphan is STANDING: the dead transcript stays on disk for the
            # life of the session, so every later trigger re-detects it. The
            # record used to be written before this line, carrying the standing
            # count, and the status line takes a PEAK of that count since the
            # last Resolved marker. So /lw-watchtower:resolve would clear HH, the very
            # next SubagentStop would re-record the same standing orphan, and HH
            # went red again seconds later - permanently, with the operator's
            # only remedy being to switch the module off. A red light that cannot
            # be turned off is not a signal, and this module exists to avoid
            # teaching people to ignore it.
            #
            # Both numbers are now recorded and they answer different questions.
            # `orphans` is the STANDING count and stays the evidence trail - E7
            # pins that a deduped re-run still records it. `orphans_new` counts
            # only agents this run had not already alerted for, which is what the
            # indicator counts, so an acknowledged death stops re-raising while a
            # genuinely new one still turns HH red immediately.
            $fresh = @(Select-LwgUnalertedAgents -List $orph)
            Write-Record (New-Record @{
                orphans     = $orph.Count
                orphans_new = $fresh.Count
                detected_at = 'SubagentStop'
            })
            if ($fresh.Count -eq 0) { exit 0 }

            Write-LwgDeadAgentBlock -List $fresh
            # Exit 2 ALERTS here only because the SubagentStop registration in
            # hooks/hooks.json sets asyncRewake. Without it exit 2 BLOCKS instead,
            # which on this event would tell a subagent that has just finished to
            # carry on. tests/stop_behaviour.ps1's C0 registration block pins that
            # registration for exactly this reason - if the pin ever fails, fix
            # the registration rather than this exit code.
            exit 2
        }

        'StopFailure' {
            # Fire-and-forget: output and exit code are ignored by the CLI. Log only.
            Write-Record (New-Record @{
                error         = $payload.error
                error_details = $payload.error_details
            })
            exit 0
        }
    }
} catch {
    # THE RECORD WRITE IS ITSELF GUARDED, and that inner try is what does the
    # work when the failure was the dot-source: Write-Record and New-Record are
    # defined above, but their bodies call Add-LwgLine and Get-LwgRedacted out
    # of common.ps1, so on a common.ps1 that never loaded this throws and the
    # nested catch swallows it. Degrading to a silent exit 0 is correct there -
    # a supervisor that cannot load its own library cannot write its own
    # evidence, and breaking the session to say so is the one outcome the
    # header forbids. Same shape as lib/stop_advisories.ps1's outermost handler.
    try { Write-Record (New-Record @{ supervisor_error = $_.Exception.Message }) } catch { }
    exit 0
}
