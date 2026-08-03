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
            Write-Record (New-Record @{ failed_tasks = $bad.Count })
            if ($bad.Count -eq 0) { exit 0 }

            # Loop guards. Without these the same failed task re-alerts every turn.
            if ($payload.stop_hook_active) { exit 0 }

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
            $bad = @($bad | Where-Object { $seen -notcontains [string]$_.id })
            if ($bad.Count -eq 0) { exit 0 }

            try {
                $updated = @(@($seen) + @($bad | ForEach-Object { [string]$_.id })) | Select-Object -Last 200
                # -InputObject with an explicit @() keeps a one-element list a JSON
                # array instead of a bare string - the shape that seeded the nesting.
                ConvertTo-Json -InputObject @([string[]]$updated) -Compress |
                    Set-Content $seenPath -Encoding utf8
            } catch { }

            [Console]::Error.WriteLine("$($bad.Count) background task(s) ended in a failed state:")
            foreach ($b in $bad) {
                # Already capped - Get-FailedTasks builds these fields through
                # ConvertTo-SafeField, so the id that goes into alerted.json and
                # the text that goes onto this stream are the same bounded value.
                $who = ''
                if ($b.agent_type) { $who = " (agent: $($b.agent_type))" }
                [Console]::Error.WriteLine("  - [$($b.type)] $($b.status): $($b.description)$who")
            }
            [Console]::Error.WriteLine("Do not close out the turn as successful without addressing these.")
            exit 2
        }

        'SubagentStop' {
            Write-Record (New-Record @{
                agent_id       = $payload.agent_id
                agent_type     = $payload.agent_type
                transcript     = $payload.agent_transcript_path
                sibling_failed = @(Get-FailedTasks).Count   # @() - see the Stop branch
            })
            exit 0
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
