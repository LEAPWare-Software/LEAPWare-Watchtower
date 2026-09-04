#requires -version 5
<#
  LW-WATCHTOWER send_liveness_gate - refuse a SendMessage whose recipient is provably
  dead. OFF by default; its switch is supervision.send_liveness.

  Registered in hooks/hooks.json as PreToolUse with matcher "SendMessage":
      command: "powershell"
      args:    ["-NoProfile","-ExecutionPolicy","Bypass","-File",
                "${CLAUDE_PLUGIN_ROOT}/lib/gate_send.ps1"]

  ---------------------------------------------------------------------------
  THE MEASURED FAILURE THIS EXISTS FOR
  ---------------------------------------------------------------------------
  On 1 August 2026 an orchestrator issued SendMessage to subagent
  a726326973cfd6913, received "Message queued for delivery", and 3.46 seconds
  later told the user the work was done. The recipient had been dead for
  28 minutes 45 seconds - its transcript existed, its last write was half an
  hour old, and health.jsonl held NO SubagentStop record for it, because a
  subagent killed mid-flight produces no record anywhere. The message could
  never have been delivered, the file was never touched, and nothing anywhere
  refused or even flagged the send. This gate is the refusal.

  ---------------------------------------------------------------------------
  WHAT IS OBSERVABLE, AND THE RULE BUILT ONLY ON THAT
  ---------------------------------------------------------------------------
  A SendMessage PreToolUse payload carries tool_input.to - a name, a raw agent
  id (a hex string beginning 'a'), or the literal "main" - plus the base hook
  fields, of which session_id and transcript_path matter here. On disk:

    <projects>\<slug>\<session-id>\subagents\agent-<id>.jsonl       transcript
    <projects>\<slug>\<session-id>\subagents\agent-<id>.meta.json   spawn record
                                          (carries "name" when one was given)

  and in the state dir, health.jsonl, where lib/supervisor.ps1's SubagentStop
  handler records every agent that STOPPED NORMALLY. Three states follow:

    stop record exists          completed normally; a send RESUMES it   ALLOW
    no record, transcript fresh presumed running                        ALLOW
    no record, transcript stale DEAD MID-FLIGHT                         DENY

  "fresh" and "stale" divide at module_config.send_liveness_gate.stale_minutes
  (default 15). The default is above the 10-minute Bash tool ceiling on
  purpose: an agent inside one long tool call writes nothing to its transcript
  for the length of the call, and a threshold under that ceiling would deny
  sends to agents that are merely busy.

  THE VERDICT NEEDS THE RECORDER. "No SubagentStop record" only means
  something if the recorder was running, so a DENY additionally requires that
  health.jsonl holds at least one record OF ANY KIND for this session. A
  session failure_capture never saw gets an ABSTAIN (allow, logged
  SendGateAbstain) - a gate must not convict on the silence of a witness that
  was never in the room.

  ---------------------------------------------------------------------------
  RECIPIENT RESOLUTION, and the two refusals that are not liveness verdicts
  ---------------------------------------------------------------------------
    "main"                    the session itself; always ALLOW.
    contains '@'              an agent-team address. Team layouts are not
                              observable from here; ABSTAIN (allow, logged).
    a name                    matched (OrdinalIgnoreCase) against the "name"
                              field of every agent-*.meta.json in this
                              session's subagents dir; several matches and the
                              newest meta wins, which is the platform's own
                              "latest wins" rule for reused names.
    a raw id                  agent-<to>.jsonl directly. Tried AFTER the name
                              lookup, so a name that happens to look like an
                              id still resolves as a name.

  A recipient that resolves to NOTHING - no meta carries the name, no
  transcript carries the id, or the session has no subagents directory at all
  - is DENIED: no such agent exists in this session, so no such agent is
  live, and the send the gate refused could only ever have produced exactly
  the queued-and-gone failure above. This is stated as over-blocking below.

  ---------------------------------------------------------------------------
  HOW IT BLOCKS, AND WHAT FAILING SAFE MEANS PER PATH
  ---------------------------------------------------------------------------
  Same two channels as lib/gate_delegate.ps1: the reason on stderr with exit 2
  (the load-bearing one - only exit 2 blocks PreToolUse; exit 1 is a
  non-blocking error and the tool RUNS), plus the permissionDecision "deny"
  envelope on stdout, redundant on this build and emitted because the two
  channels fail open in different circumstances.

    stdin empty, truncated, not JSON, or carrying no `to`
        DENY when the switch is on. The gate's one job is to establish the
        recipient before the send; input it could not read is not evidence of
        a live recipient. Same polarity, same reasoning, as delegate_gate.
    common.ps1 fails to load, config unreadable, or this script throws
        ALLOW. A gate that cannot read its own switch must not act on a
        guess, and the switch defaults OFF.

  ---------------------------------------------------------------------------
  OVER-BLOCKING THIS ACCEPTS, stated rather than left to be discovered
  ---------------------------------------------------------------------------
    * An agent alive but silent past stale_minutes - back-to-back long tool
      calls - is denied. The deny text says exactly what was measured and
      names the knob; raising stale_minutes or switching the gate off are
      both one-line config edits.
    * A completed agent whose SubagentStop record has scrolled out of the
      health.jsonl tail this gate reads (last ~512 KB / 1,500 records) is
      denied as if dead. Rare - it takes over a thousand later records in one
      session - and the deny text names the record it looked for.
    * A recipient in an agent-team, or any future layout that does not put
      transcripts under <session>\subagents, is ABSTAINED on '@' addresses
      and DENIED on unresolvable bare names. An operator running teams
      should not arm this gate; docs/modules.md says so.

  AND THE BYPASSES, per docs/gates-removed.md Lesson 3 - what this gate does
  NOT catch, so nobody reads a green suite as soundness:
    * a recipient that died LESS than stale_minutes ago passes as "presumed
      running" - the gate narrows the window from unbounded to stale_minutes,
      it does not close it;
    * a dead agent with a name some LATER live agent took over resolves to
      the live one, exactly as the platform itself would route it;
    * nothing here establishes DELIVERY or COMPLETION - an allowed send can
      still sit queued forever if the recipient dies afterwards; that half
      belongs to completion_audit and to the orchestrator reading evidence;
    * the whole gate rests on the CLI dispatching PreToolUse for SendMessage;
      if a build stops doing that, the gate is silently out of the path (the
      same exposure every PreToolUse hook has).

  NO FAST PATH, deliberately, unlike gate_delegate: that gate sits on every
  Edit/Write/Bash call a session makes; this one fires only on SendMessage,
  which happens at orchestration frequency, so the interpreter floor is the
  cost and a raw-text scanner would buy back milliseconds nobody is paying.
#>

$ErrorActionPreference = 'Stop'

# stdin is drained first and unconditionally - a pipe is consumed exactly once,
# and the writer at the other end must never be left holding an unread pipe.
#
# DECODED AS UTF-8 EXPLICITLY, and deliberately NOT through [Console]::In,
# whose encoding is the CONSOLE's input code page and not the payload's. This
# gate reads tool_input.to, and a recipient it cannot resolve is DENIED - so a
# worker whose name is not ASCII would be refused for the encoding rather than
# for the evidence. lib/common.ps1's Read-LwgStdinText is the same three lines
# with the full reasoning; this file drains before it is dot-sourced.
$LwgRawStdin = ''
try {
    $LwgStdinReader = [IO.StreamReader]::new([Console]::OpenStandardInput(), [Text.UTF8Encoding]::new($false), $true)
    try { $LwgRawStdin = $LwgStdinReader.ReadToEnd() } finally { $LwgStdinReader.Dispose() }
} catch { $LwgRawStdin = '' }

$payload = [pscustomobject]@{}

try {
    . (Join-Path $PSScriptRoot 'common.ps1')
} catch {
    # Without the shared readers this script cannot read its switch, and a gate
    # that cannot read its own switch must not act on a guess. Allow, silently.
    exit 0
}

function Get-LwgSendStaleMinutes {
    param($Config)
    $m = 15
    try { $m = [int](Get-LwgModuleOption -Config $Config -Module 'send_liveness_gate' -Key 'stale_minutes' -Default 15) } catch { $m = 15 }
    if ($m -lt 1) { $m = 1 }
    return $m
}

function Get-LwgSubagentsDir {
    <#
      The subagents directory for this session, derived from the payload alone:
      <dir of transcript_path>\<session_id>\subagents for a main-thread call,
      and the transcript's own directory when the call already comes from
      inside a subagent (its transcript_path ends ...\subagents\agent-X.jsonl).
      Returns $null when it cannot be derived or does not exist.
    #>
    param($Payload)

    try {
        $tp  = [string]$Payload.transcript_path
        $sid = [string]$Payload.session_id
        if ([string]::IsNullOrWhiteSpace($tp)) { return $null }
        $base = [IO.Path]::GetDirectoryName($tp)
        if ([string]::IsNullOrWhiteSpace($base)) { return $null }
        if ([string]::Equals([IO.Path]::GetFileName($base), 'subagents', [StringComparison]::OrdinalIgnoreCase)) {
            if ([IO.Directory]::Exists($base)) { return $base }
            return $null
        }
        if ([string]::IsNullOrWhiteSpace($sid)) { return $null }
        $d = [IO.Path]::Combine($base, $sid, 'subagents')
        if ([IO.Directory]::Exists($d)) { return $d }
    } catch { }
    return $null
}

function Resolve-LwgRecipientId {
    <#
      The agent id `to` names, or $null when nothing in this session matches.
      Names are resolved through the meta files FIRST (newest meta wins, the
      platform's own latest-takes-the-name rule); a raw id is accepted only
      when its transcript actually exists. Bounded: at most 200 metas read.
    #>
    param([string]$To, [string]$SubDir)

    try {
        # --- by name, out of the spawn metas -------------------------------
        $best   = $null
        $bestT  = [datetime]::MinValue
        $metas  = @()
        try { $metas = @([IO.Directory]::GetFiles($SubDir, 'agent-*.meta.json')) } catch { }
        $n = 0
        foreach ($mf in $metas) {
            $n++; if ($n -gt 200) { break }
            $name = $null
            try {
                $mo = [IO.File]::ReadAllText($mf) | ConvertFrom-Json
                if ($null -ne $mo) { $name = [string]$mo.name }
            } catch { continue }
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            if (-not [string]::Equals($name, $To, [StringComparison]::OrdinalIgnoreCase)) { continue }
            $t = [datetime]::MinValue
            try { $t = [IO.File]::GetLastWriteTimeUtc($mf) } catch { }
            if ($null -eq $best -or $t -gt $bestT) {
                $leaf = [IO.Path]::GetFileName($mf)
                # agent-<id>.meta.json -> <id>
                if ($leaf.Length -gt 16) { $best = $leaf.Substring(6, $leaf.Length - 6 - 10); $bestT = $t }
            }
        }
        if ($null -ne $best) { return $best }

        # --- by raw id ------------------------------------------------------
        if ($To -match '^a[0-9a-f]{10,}$') {
            if ([IO.File]::Exists([IO.Path]::Combine($SubDir, "agent-$To.jsonl"))) { return $To }
        }
    } catch { }
    return $null
}

function Deny-LwgSend {
    param([string]$Reason, [hashtable]$Extra)

    try {
        $x = @{ gate = 'send_liveness_gate'; rule = 'recipient-liveness' }
        if ($Extra) { foreach ($k in $Extra.Keys) { $x[$k] = $Extra[$k] } }
        Write-LwgEvent -Event 'GateDeny' -Payload $script:payload -Extra $x | Out-Null
    } catch { }
    try { Write-LwgDenyDecision -Reason $Reason | Out-Null } catch { }
    [Console]::Error.Write($Reason)
    exit 2
}

try {
    $payload = Read-LwgStdin -Raw $LwgRawStdin
    $script:payload = $payload
    $cfg  = Get-LwgConfig
    $repo = Get-LwgRepo $payload

    # --- the switch: supervision.send_liveness, global then per-repo, OFF ---
    if (-not (Test-LwgModule -Name 'send_liveness_gate' -Config $cfg -Repo $repo)) { exit 0 }

    # --- the recipient ------------------------------------------------------
    $to = ''
    try { $to = [string]$payload.tool_input.to } catch { $to = '' }
    if ([string]::IsNullOrWhiteSpace($to)) {
        Deny-LwgSend -Extra @{ why = 'unreadable-recipient' } -Reason (@(
            'LW-WATCHTOWER send_liveness_gate: this SendMessage carried no readable recipient, and'
            'the gate cannot establish that an unreadable recipient is a live agent. Re-issue'
            'the call with a valid `to`, or - if this recurs on every send - the payload shape'
            'has changed and the gate should be switched off (supervision.send_liveness in'
            'config.json) and the mismatch reported.'
        ) -join ' ')
    }
    $to = $to.Trim()

    if ([string]::Equals($to, 'main', [StringComparison]::OrdinalIgnoreCase)) { exit 0 }

    if ($to.IndexOf('@') -ge 0) {
        # An agent-team address. The team layout is not observable from this
        # hook, so no liveness verdict is available either way - abstain, and
        # say so in the log rather than in anyone's way.
        try { Write-LwgEvent -Event 'SendGateAbstain' -Payload $payload -Extra @{
            gate = 'send_liveness_gate'; to = (Get-LwgRedacted -Text $to -MaxLength 80); why = 'team-address' } | Out-Null } catch { }
        exit 0
    }

    $subDir = Get-LwgSubagentsDir -Payload $payload
    if ($null -eq $subDir) {
        Deny-LwgSend -Extra @{ why = 'no-subagents-dir'; to = (Get-LwgRedacted -Text $to -MaxLength 80) } -Reason (@(
            "LW-WATCHTOWER send_liveness_gate: no subagent transcript directory exists for this"
            "session, so no subagent recipient '$to' can be live here. Nothing has been"
            'spawned that this message could reach. Spawn the agent first (Agent tool), or'
            'address the main conversation. A queued message to a non-existent agent is the'
            'exact silent failure this gate exists to refuse.'
        ) -join ' ')
    }

    $id = Resolve-LwgRecipientId -To $to -SubDir $subDir
    if ($null -eq $id) {
        Deny-LwgSend -Extra @{ why = 'unresolvable-recipient'; to = (Get-LwgRedacted -Text $to -MaxLength 80) } -Reason (@(
            "LW-WATCHTOWER send_liveness_gate: no agent in this session answers to '$to' - no spawn"
            'record carries that name and no transcript carries that id. The recipient cannot'
            'be live, so this send could only be queued to nobody. Check the id or name'
            'against the spawn result, or spawn the agent. (If this is an agent-team'
            'workflow with its own layout, this gate does not understand teams - switch'
            'supervision.send_liveness off for this repo.)'
        ) -join ' ')
    }

    # --- the liveness verdict ----------------------------------------------
    $tf = [IO.Path]::Combine($subDir, "agent-$id.jsonl")
    if (-not [IO.File]::Exists($tf)) {
        Deny-LwgSend -Extra @{ why = 'no-transcript'; agent = $id } -Reason (@(
            "LW-WATCHTOWER send_liveness_gate: '$to' resolves to agent $id but no transcript exists"
            'for it in this session, so it cannot be live. Spawn it, or check the recipient.'
        ) -join ' ')
    }

    $sid      = [string]$payload.session_id
    $staleMin = Get-LwgSendStaleMinutes -Config $cfg
    $ageMin   = 0.0
    try { $ageMin = ([datetime]::UtcNow - [IO.File]::GetLastWriteTimeUtc($tf)).TotalMinutes } catch { $ageMin = 0.0 }

    if ($ageMin -lt $staleMin) { exit 0 }   # fresh: presumed running

    # Stale. Completed normally, or dead mid-flight? The SubagentStop record is
    # the difference, and the recorder's own liveness is checked before its
    # silence is allowed to convict.
    $all = @(Get-LwgHealthRecords -Session $sid -Tail 1500)
    if ($all.Count -eq 0) {
        try { Write-LwgEvent -Event 'SendGateAbstain' -Payload $payload -Extra @{
            gate = 'send_liveness_gate'; agent = $id; why = 'no-health-records-for-session'
            note = 'transcript is stale but health.jsonl never recorded this session, so a missing SubagentStop proves nothing - abstained' } | Out-Null } catch { }
        exit 0
    }
    foreach ($r in $all) {
        if ([string]$r.event -eq 'SubagentStop' -and [string]$r.agent_id -eq $id) { exit 0 }  # completed; a send resumes it
    }

    $ageTxt = [Math]::Round($ageMin)
    Deny-LwgSend -Extra @{ why = 'dead-mid-flight'; agent = $id; age_minutes = $ageTxt; stale_minutes = $staleMin } -Reason (@(
        "LW-WATCHTOWER send_liveness_gate: recipient agent $id ('$to') appears DEAD MID-FLIGHT."
        "Its transcript was last written $ageTxt minute(s) ago (threshold $staleMin) and"
        'health.jsonl holds NO SubagentStop record for it, while it does hold records for'
        'this session - an agent that finishes normally always leaves one. A message queued'
        'to it will never be delivered, and any work assigned to it is NOT done. Do not'
        'report that work as complete. Instead: read the tail of its transcript to see where'
        'it died, spawn a fresh agent restating the full context, and only report done on'
        'evidence. If the agent is genuinely alive inside one very long tool call, raise'
        'module_config.send_liveness_gate.stale_minutes in config.json and retry.'
    ) -join ' ')

} catch {
    # Anything unexpected ALLOWS - a gate must never turn its own defect into a
    # lockout - and the one thing that must not happen is a silent failure.
    try {
        Write-LwgEvent -Event 'GateError' -Payload $payload -Extra @{
            gate  = 'send_liveness_gate'
            error = (Get-LwgRedacted -Text ([string]$_.Exception.Message) -MaxLength 200)
            where = 'lib/gate_send.ps1'
        } | Out-Null
    } catch { }
    exit 0
}
