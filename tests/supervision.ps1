#requires -version 5
<#
  LW-WATCHTOWER supervision regression suite - send_liveness_gate, completion_audit
  and orphan_watch.

      powershell -NoProfile -ExecutionPolicy Bypass -File tests\supervision.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File tests\supervision.ps1 -Verbose

  Built to the same contract as tests\gate_delegate.ps1, and with the same
  standing caveat from docs\gates-removed.md Lesson 3 at the top rather than in
  a footnote: a green run here says these cases still behave, NOT that the
  gates are sound. Every hole in this repository's history was found by
  somebody trying to break a gate, then written up as a regression case
  afterwards.

  THE ANCHOR CASE, because a suite for these modules that did not carry it
  would be missing its reason to exist: on 1 August 2026 an orchestrator sent
  SendMessage to an agent whose transcript had been silent for 28 minutes
  45 seconds and for which health.jsonl held no SubagentStop record, read
  "Message queued for delivery" as done, and told the user a file was updated
  that was never touched. Case C1 below reproduces exactly that shape -
  28m45s-stale transcript, live recorder, no stop record - and requires the
  DENY. Case D1 reproduces the prose half - a completion claim whose turn
  ends in SendMessage - and requires the BLOCK. Case E1 reproduces the
  bookkeeping half - a spawned agent with no stop record - and requires the
  orphan alert.

  HOW A CASE IS RUN: through a real pipe into a real child process
  (`type payload.json | powershell -File <script>`), against a THROWAWAY
  plugin root and data dir under the temp directory, because a PowerShell
  object pipe never reaches [Console]::In and an in-process call would test
  different code from the one Claude Code invokes. The fixture configs start
  as byte copies of the repository's own config.json - the shape that ships,
  comments and all - with exactly the switches under test flipped, and every
  flip is ASSERTED so a fixture that silently failed to arm a gate cannot
  turn a deny case into a false pass.

  NOTHING REAL IS TOUCHED. No case reads or writes the operator's config, the
  live state directory, the live health log or any real session transcript.
  All timestamps are set with [IO.File]::SetLastWriteTimeUtc on files this
  suite created. No real agent is spawned and no real message is sent.

  EXIT CODES - a CI job reads these and nothing else:
      0  every case passed
      1  at least one case FAILED
      2  the suite ABORTED - nothing was established either way. Zero cases
         run is an abort, never an empty-set pass.
#>
[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }

$SendGatePath   = Join-Path $Root 'lib\gate_send.ps1'
$StopGatePath   = Join-Path $Root 'lib\gate_stop.ps1'
$SupervisorPath = Join-Path $Root 'lib\supervisor.ps1'
$HooksPath      = Join-Path $Root 'hooks\hooks.json'
$CfgPath        = Join-Path $Root 'config.json'
$CommonPath     = Join-Path $Root 'lib\common.ps1'

$script:Pass    = 0
$script:Results = New-Object System.Collections.ArrayList

function Add-Result {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    if ($Ok) { $script:Pass++ }
    [void]$script:Results.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail })
    if (-not $Ok) {
        Write-Output ("  FAIL  {0}" -f $Name)
        Write-Output ("        {0}" -f $Detail)
    } elseif ($VerbosePreference -ne 'SilentlyContinue') {
        Write-Output ("  ok    {0}" -f $Name)
    }
}

function New-LwgSupRoot {
    <#
      A throwaway plugin root holding the repository's own config.json with the
      three supervision switches set to $On. Every replacement is asserted to
      have matched exactly once: the GLOBAL keys are the only place the literal
      `"<key>": false` occurs (the per-repo block spells them `: true`), and a
      config in which that stops being so must abort the suite rather than
      quietly build deny cases against a disarmed gate.
    #>
    param([string]$Base, [bool]$On)

    $dir = Join-Path $Base ("root-" + $(if ($On) { 'on' } else { 'off' }))
    [void][IO.Directory]::CreateDirectory($dir)
    [void][IO.Directory]::CreateDirectory((Join-Path $dir 'data'))

    $raw = [IO.File]::ReadAllText($CfgPath)
    if ($On) {
        foreach ($k in @('send_liveness', 'completion_audit', 'orphan_watch')) {
            $from = ('"{0}": false' -f $k)
            $n = ([regex]::Matches($raw, [regex]::Escape($from))).Count
            if ($n -ne 1) {
                throw "config.json holds $n occurrence(s) of '$from', expected exactly 1 - the fixture cannot be built, and building it wrong would make every deny case a false pass"
            }
            $raw = $raw.Replace($from, ('"{0}": true' -f $k))
        }
    }
    [IO.File]::WriteAllText((Join-Path $dir 'config.json'), $raw, [Text.UTF8Encoding]::new($false))
    return $dir
}

function New-LwgSession {
    <#
      A fabricated session tree mirroring the layout Claude Code writes:

          <dir>\<session-id>.jsonl                     the main transcript
          <dir>\<session-id>\subagents\agent-<id>.jsonl
          <dir>\<session-id>\subagents\agent-<id>.meta.json

      Returns @{ id; main; subdir }. The main transcript starts empty; cases
      that need records append them.
    #>
    param([string]$Base, [string]$Tag)

    $id  = "lwg-sup-$Tag"
    $dir = Join-Path $Base "sess-$Tag"
    $sub = Join-Path (Join-Path $dir $id) 'subagents'
    [void][IO.Directory]::CreateDirectory($sub)
    $main = Join-Path $dir "$id.jsonl"
    [IO.File]::WriteAllText($main, '', [Text.UTF8Encoding]::new($false))
    return @{ id = $id; main = $main; subdir = $sub }
}

function Add-LwgAgent {
    <#
      A fabricated subagent: transcript with one line, optional meta name, and
      a last-write time $AgeMinutes in the past (UTC, set explicitly - never
      inherited from the clock at creation).
    #>
    param([hashtable]$Sess, [string]$AgentId, [double]$AgeMinutes, [string]$Name)

    $tf = Join-Path $Sess.subdir "agent-$AgentId.jsonl"
    [IO.File]::WriteAllText($tf, ('{"agentId":"' + $AgentId + '","type":"user","isSidechain":true,"message":{"role":"user","content":"fixture"}}' + "`n"), [Text.UTF8Encoding]::new($false))
    [IO.File]::SetLastWriteTimeUtc($tf, [datetime]::UtcNow.AddMinutes(-$AgeMinutes))

    $meta = [ordered]@{ agentType = 'lwg-fixture'; description = 'fixture'; spawnDepth = 1 }
    if (-not [string]::IsNullOrWhiteSpace($Name)) { $meta['name'] = $Name }
    $mf = Join-Path $Sess.subdir "agent-$AgentId.meta.json"
    [IO.File]::WriteAllText($mf, (([pscustomobject]$meta) | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
    return $tf
}

function Write-LwgHealth {
    <#
      A fixture health.jsonl in $RootDir\data. $Records is a list of
      hashtables; each becomes one JSONL line. Overwrites - each case states
      its whole world.
    #>
    param([string]$RootDir, [array]$Records)

    $lines = @()
    foreach ($r in @($Records)) { $lines += (([pscustomobject]$r) | ConvertTo-Json -Compress) }
    $p = Join-Path (Join-Path $RootDir 'data') 'health.jsonl'
    [IO.File]::WriteAllText($p, (($lines -join "`n") + $(if ($lines.Count) { "`n" } else { '' })), [Text.UTF8Encoding]::new($false))
    return $p
}

function Invoke-LwgScript {
    <#
      Run one hook script against $Payload through a real cmd pipe, with the
      plugin root and data dir pointed at $FakeRoot. Returns @{ code; out; err }.
    #>
    param([string]$ScriptPath, [string]$FakeRoot, [string]$Payload, [string]$WorkDir, [string]$Tag, [string]$ScriptArgs)

    $pf  = Join-Path $WorkDir "$Tag.json"
    $of  = Join-Path $WorkDir "$Tag.out"
    $ef  = Join-Path $WorkDir "$Tag.err"
    $bat = Join-Path $WorkDir "$Tag.cmd"

    [IO.File]::WriteAllText($pf, $Payload, [Text.UTF8Encoding]::new($false))
    foreach ($f in @($of, $ef)) { if ([IO.File]::Exists($f)) { [IO.File]::WriteAllText($f, '') } }

    $extra = if ([string]::IsNullOrWhiteSpace($ScriptArgs)) { '' } else { ' ' + $ScriptArgs }
    $lines = @(
        '@echo off'
        ('type "{0}" | powershell -NoProfile -ExecutionPolicy Bypass -File "{1}"{2} 1>"{3}" 2>"{4}"' -f $pf, $ScriptPath, $extra, $of, $ef)
        'exit /b %ERRORLEVEL%'
    )
    [IO.File]::WriteAllLines($bat, $lines, [Text.ASCIIEncoding]::new())

    $prevRoot = $env:CLAUDE_PLUGIN_ROOT
    $prevData = $env:CLAUDE_PLUGIN_DATA
    try {
        $env:CLAUDE_PLUGIN_ROOT = $FakeRoot
        $env:CLAUDE_PLUGIN_DATA = Join-Path $FakeRoot 'data'
        & $env:ComSpec /c $bat | Out-Null
        $code = $LASTEXITCODE
    } finally {
        $env:CLAUDE_PLUGIN_ROOT = $prevRoot
        $env:CLAUDE_PLUGIN_DATA = $prevData
    }

    $out = ''; $err = ''
    try { $out = [IO.File]::ReadAllText($of) } catch { }
    try { $err = [IO.File]::ReadAllText($ef) } catch { }
    return @{ code = $code; out = $out; err = $err }
}

function New-LwgSendPayload {
    param([hashtable]$Sess, [string]$To)
    $tp = $Sess.main -replace '\\', '/'
    return ('{"session_id":"' + $Sess.id + '","transcript_path":"' + $tp + '","cwd":"C:/nowhere",' +
            '"hook_event_name":"PreToolUse","tool_name":"SendMessage",' +
            '"tool_input":{"to":"' + $To + '","summary":"fixture","message":"fixture"}}')
}

function New-LwgStopPayload {
    param([hashtable]$Sess, [bool]$HookActive)
    $tp = $Sess.main -replace '\\', '/'
    $extra = if ($HookActive) { ',"stop_hook_active":true' } else { '' }
    return ('{"session_id":"' + $Sess.id + '","transcript_path":"' + $tp + '","cwd":"C:/nowhere",' +
            '"hook_event_name":"Stop"' + $extra + '}')
}

function Add-LwgTranscript {
    <# Append raw JSONL lines to a session's main transcript. #>
    param([hashtable]$Sess, [string[]]$JsonLines)
    [IO.File]::AppendAllText($Sess.main, (($JsonLines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
}

# Transcript record builders. Content block JSON is built as text so a case
# controls exactly which members exist, same policy as gate_delegate's payloads.
function New-UserPromptLine  { param([string]$Text)
    return ('{"type":"user","isSidechain":false,"message":{"role":"user","content":"' + $Text + '"}}') }
function New-ToolUseLine     { param([string]$Tool)
    return ('{"type":"assistant","isSidechain":false,"message":{"content":[{"type":"tool_use","id":"t1","name":"' + $Tool + '","input":{}}]}}') }
function New-TextLine        { param([string]$Text)
    return ('{"type":"assistant","isSidechain":false,"message":{"content":[{"type":"text","text":"' + $Text + '"}]}}') }

# --- SUBAGENT-MODE fixtures -----------------------------------------------
# Subagents and teammates emit SubagentStop, where the subagent's OWN transcript
# is agent_transcript_path and transcript_path is the PARENT's. Every record in
# a real subagent transcript carries isSidechain:true - measured 118 of 118 in
# one live transcript - so these builders stamp it on every line. A fixture that
# did not would be testing a shape the CLI never writes.
function New-SideUserLine    { param([string]$Text)
    return ('{"type":"user","isSidechain":true,"agentId":"a1","message":{"role":"user","content":"' + $Text + '"}}') }
function New-SideToolUseLine { param([string]$Tool)
    return ('{"type":"assistant","isSidechain":true,"agentId":"a1","message":{"content":[{"type":"tool_use","id":"t1","name":"' + $Tool + '","input":{}}]}}') }
function New-SideTextLine    { param([string]$Text)
    return ('{"type":"assistant","isSidechain":true,"agentId":"a1","message":{"content":[{"type":"text","text":"' + $Text + '"}]}}') }

function New-LwgAgentFile {
    <# An agent transcript under the session's subagents dir. Returns its path. #>
    param([hashtable]$Sess, [string]$AgentId, [string[]]$JsonLines)
    $p = Join-Path $Sess.subdir "agent-$AgentId.jsonl"
    [IO.File]::WriteAllText($p, (($JsonLines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    return $p
}

function New-LwgSubStopPayload {
    <#
      A SubagentStop payload. An empty AgentPath reproduces a payload carrying no
      agent_transcript_path - the case that must degrade to a silent no-op rather
      than fall back to the parent's transcript.
    #>
    param([hashtable]$Sess, [string]$AgentPath, [bool]$HookActive)
    $tp  = $Sess.main -replace '\\', '/'
    $apf = ''
    if (-not [string]::IsNullOrWhiteSpace($AgentPath)) {
        $apf = ',"agent_transcript_path":"' + ($AgentPath -replace '\\', '/') + '"'
    }
    $extra = if ($HookActive) { ',"stop_hook_active":true' } else { '' }
    return ('{"session_id":"' + $Sess.id + '","transcript_path":"' + $tp + '","cwd":"C:/nowhere",' +
            '"hook_event_name":"SubagentStop","agent_id":"a1"' + $apf + $extra + '}')
}

function Test-IsDeny {
    param($R)
    if ($R.code -eq 1) { return @{ ok = $false; why = 'exited 1, which does NOT block - the tool call proceeds. This is the silent fail-open the contract exists to prevent' } }
    if ($R.code -ne 2) { return @{ ok = $false; why = "exited $($R.code); only exit 2 blocks" } }
    if ([string]::IsNullOrWhiteSpace($R.err)) { return @{ ok = $false; why = 'exited 2 but wrote nothing to stderr - a block with no reason attached' } }
    return @{ ok = $true; why = '' }
}

function Test-IsAllow {
    param($R)
    if ($R.code -ne 0) { return @{ ok = $false; why = "exited $($R.code), expected 0" } }
    if (-not [string]::IsNullOrWhiteSpace($R.out)) { return @{ ok = $false; why = "wrote to stdout when it should have been silent: $($R.out)" } }
    if (-not [string]::IsNullOrWhiteSpace($R.err)) { return @{ ok = $false; why = "wrote to stderr when it should have been silent: $($R.err)" } }
    return @{ ok = $true; why = '' }
}

# ===========================================================================
# MAIN
# ===========================================================================
$sw = [Diagnostics.Stopwatch]::StartNew()
$work = ''

try {
    Write-Output 'LW-WATCHTOWER supervision regression suite'
    Write-Output "  repo : $Root"
    Write-Output ''

    foreach ($p in @($SendGatePath, $StopGatePath, $SupervisorPath, $HooksPath, $CfgPath, $CommonPath)) {
        if (-not [IO.File]::Exists($p)) { throw "missing: $p" }
    }

    $work = Join-Path ([IO.Path]::GetTempPath()) ('lwg-sup-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
    [void][IO.Directory]::CreateDirectory($work)

    $rootOn  = New-LwgSupRoot -Base $work -On $true
    $rootOff = New-LwgSupRoot -Base $work -On $false

    $hooks = ([IO.File]::ReadAllText($HooksPath) | ConvertFrom-Json)

    # -------------------------------------------------------------------
    # A. REGISTRATION. An unregistered gate refuses nothing, silently.
    # -------------------------------------------------------------------
    $pre  = @($hooks.hooks.PreToolUse)
    $mine = @($pre | Where-Object { ($_ | ConvertTo-Json -Depth 8 -Compress) -like '*gate_send.ps1*' })
    Add-Result 'A1 registration: exactly one PreToolUse entry names gate_send.ps1' ($mine.Count -eq 1) `
        "found $($mine.Count) PreToolUse entries naming gate_send.ps1, expected 1"
    if ($mine.Count -eq 1) {
        $e = $mine[0]
        $declared = @([string]$e.matcher -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        Add-Result 'A2 registration: its matcher names SendMessage' ($declared -contains 'SendMessage') `
            "matcher '$($e.matcher)' does not cover SendMessage"
        $h = @($e.hooks)[0]
        $aj = (@($h.args) -join ' ')
        Add-Result 'A3 registration: exec form through CLAUDE_PLUGIN_ROOT, no shell:' `
            ([string]$h.type -eq 'command' -and [string]$h.command -eq 'powershell' -and
             $aj -like '*${CLAUDE_PLUGIN_ROOT}*gate_send.ps1*' -and
             (($e | ConvertTo-Json -Depth 8 -Compress) -notmatch '"shell"\s*:')) `
            "the entry must be command 'powershell' + args resolving `${CLAUDE_PLUGIN_ROOT}/lib/gate_send.ps1, with no shell: key (pwsh is absent); got: $(($e | ConvertTo-Json -Depth 8 -Compress))"
    }

    $stopE = @(@($hooks.hooks.Stop) | Where-Object { ($_ | ConvertTo-Json -Depth 8 -Compress) -like '*gate_stop.ps1*' })
    Add-Result 'A4 registration: exactly one Stop entry names gate_stop.ps1' ($stopE.Count -eq 1) `
        "found $($stopE.Count) Stop entries naming gate_stop.ps1, expected 1"
    if ($stopE.Count -eq 1) {
        $ej = ($stopE[0] | ConvertTo-Json -Depth 8 -Compress)
        Add-Result 'A5 registration: the gate_stop entry carries NO asyncRewake' ($ej -notlike '*asyncRewake*') `
            'asyncRewake turns exit 2 into an alert; this entry must BLOCK, so it must not carry one'
        $h = @(@($stopE[0].hooks))[0]
        Add-Result 'A6 registration: gate_stop exec form through CLAUDE_PLUGIN_ROOT' `
            ([string]$h.type -eq 'command' -and [string]$h.command -eq 'powershell' -and
             ((@($h.args) -join ' ') -like '*${CLAUDE_PLUGIN_ROOT}*gate_stop.ps1*')) `
            "expected command 'powershell' with args resolving `${CLAUDE_PLUGIN_ROOT}/lib/gate_stop.ps1; got: $ej"
    }

    # A7-A10 - the SubagentStop registration. A4 above filters $hooks.hooks.Stop
    # and is structurally BLIND to this entry, so a bad one here would sail past
    # it; these cases exist because that blindness was found, not assumed.
    $subE = @(@($hooks.hooks.SubagentStop) | Where-Object { ($_ | ConvertTo-Json -Depth 8 -Compress) -like '*gate_stop.ps1*' })
    Add-Result 'A7 registration: exactly one SubagentStop entry names gate_stop.ps1' ($subE.Count -eq 1) `
        "found $($subE.Count) SubagentStop entries naming gate_stop.ps1, expected 1 - subagents and teammates emit SubagentStop and NOT Stop, so with no entry here the gate fires for no worker at all"
    if ($subE.Count -eq 1) {
        $sj = ($subE[0] | ConvertTo-Json -Depth 8 -Compress)
        Add-Result 'A8 registration: the SubagentStop gate_stop entry carries NO asyncRewake' ($sj -notlike '*asyncRewake*') `
            'asyncRewake turns exit 2 into an alert rather than a block; this entry must BLOCK, so it must not carry one'
        $sh = @(@($subE[0].hooks))[0]
        $saj = (@($sh.args) -join ' ')
        Add-Result 'A9 registration: SubagentStop gate_stop exec form through CLAUDE_PLUGIN_ROOT, no shell:' `
            ([string]$sh.type -eq 'command' -and [string]$sh.command -eq 'powershell' -and
             $saj -like '*${CLAUDE_PLUGIN_ROOT}*gate_stop.ps1*' -and ($sj -notmatch '"shell"\s*:')) `
            "expected command 'powershell' with args resolving `${CLAUDE_PLUGIN_ROOT}/lib/gate_stop.ps1 and no shell: key (pwsh is absent); got: $sj"
        Add-Result 'A10 registration: it passes -HookEvent SubagentStop' ($saj -like '*-HookEvent*SubagentStop*') `
            "without -HookEvent SubagentStop this entry leans on the payload alone to pick its mode; the argument is what makes the registration self-describing, and reading transcript_path on this event would audit the PARENT's turn and block the subagent for what the orchestrator said. Got args: $saj"
    }

    # -------------------------------------------------------------------
    # B. REGISTRY AND THE SHIPPED-OFF INVARIANT - against the REAL config.
    # -------------------------------------------------------------------
    . $CommonPath

    foreach ($row in @(
        @{ n = 'send_liveness_gate'; kind = 'gate';    key = 'send_liveness' },
        @{ n = 'completion_audit';   kind = 'gate';    key = 'completion_audit' },
        @{ n = 'orphan_watch';       kind = 'observe'; key = 'orphan_watch' }
    )) {
        $entry = $null
        try { $entry = $script:LwgModuleRegistry[$row.n] } catch { }
        $okReg = ($null -ne $entry -and [string]$entry.kind -eq $row.kind -and
                  $null -ne $entry.switch -and
                  [string]$entry.switch.block -eq 'supervision' -and
                  [string]$entry.switch.key -eq $row.key -and
                  [bool]$entry.switch.default -eq $false)
        Add-Result "B registry: $($row.n) is kind $($row.kind), switch supervision.$($row.key), default off" $okReg `
            "the registry entry is missing or declares kind '$($entry.kind)' / switch '$(if ($entry -and $entry.switch) { "$($entry.switch.block).$($entry.switch.key) default $($entry.switch.default)" } else { 'none' })'"

        # The shipped-off invariant, asserted against the REAL config.json the
        # repository ships - the same assertion tests\gate_delegate.ps1 makes
        # for delegate_gate. A supervision module armed by default would be a
        # blocking change nobody chose.
        Add-Result "B shipped config: $($row.n) is OFF by default" `
            (-not (Test-LwgModule -Name $row.n -Config (Get-LwgConfig -Path $CfgPath) -Repo '')) `
            "the shipped config.json arms $($row.n). It must ship off - a blocking module switched on by default is the opposite of what this plugin argues for"
    }

    # A per-repo override must arm them through the same resolution the gates
    # use - fabricated config, fabricated slug, nothing from this machine.
    $ovCfg = ('{"modules":{"failure_capture":true},' +
              '"supervision":{"send_liveness":false,"completion_audit":false,"orphan_watch":false},' +
              '"repos":{"LWG-Test/FakeRepo":{"supervision":{"send_liveness":true,"completion_audit":true,"orphan_watch":true}}}}')
    $ovObj = $ovCfg | ConvertFrom-Json
    $okOv = $true
    foreach ($n in @('send_liveness_gate', 'completion_audit', 'orphan_watch')) {
        if (-not (Test-LwgModule -Name $n -Config $ovObj -Repo 'LWG-Test/FakeRepo')) { $okOv = $false }
        if (Test-LwgModule -Name $n -Config $ovObj -Repo 'Other/Repo')              { $okOv = $false }
    }
    Add-Result 'B per-repo override arms all three for its repo and no other' $okOv `
        'repos[slug].supervision.<key> must override the global false for that slug only'

    # -------------------------------------------------------------------
    # C. send_liveness_gate BEHAVIOUR.
    # -------------------------------------------------------------------
    # C1 - THE MEASURED CASE. Transcript 28m45s stale, recorder live for the
    # session, no SubagentStop for the recipient. This is the send that was
    # allowed on 1 August 2026 and must never be allowed again.
    $s1 = New-LwgSession -Base $work -Tag 'c1'
    [void](Add-LwgAgent -Sess $s1 -AgentId 'a726326973cfd6913' -AgeMinutes 28.75)
    [void](Write-LwgHealth -RootDir $rootOn -Records @(
        @{ ts = '2026-08-01T12:00:00.0000000Z'; event = 'SessionStart'; session = $s1.id },
        @{ ts = '2026-08-01T12:30:00.0000000Z'; event = 'SubagentStop'; session = $s1.id; agent_id = 'a0000000000000001' }
    ))
    $r = Invoke-LwgScript -ScriptPath $SendGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'c1' `
             -Payload (New-LwgSendPayload -Sess $s1 -To 'a726326973cfd6913')
    $v = Test-IsDeny $r
    Add-Result 'C1 THE 28-MINUTES-DEAD RECIPIENT -> DENY' $v.ok $v.why
    if ($v.ok) {
        Add-Result 'C1a the deny names the death and the way forward' `
            ($r.err -like '*DEAD MID-FLIGHT*' -and $r.err -like '*SubagentStop*' -and $r.err -like '*spawn a fresh agent*') `
            "the deny reason must say what was measured and what to do instead: $($r.err)"
        $env0 = $null
        try { $env0 = $r.out | ConvertFrom-Json } catch { }
        Add-Result 'C1b the stdout deny envelope is well formed' `
            ($null -ne $env0 -and
             [string]$env0.hookSpecificOutput.hookEventName      -eq 'PreToolUse' -and
             [string]$env0.hookSpecificOutput.permissionDecision -eq 'deny' -and
             -not [string]::IsNullOrWhiteSpace([string]$env0.hookSpecificOutput.permissionDecisionReason)) `
            "stdout did not parse as a PreToolUse deny envelope with a reason: $($r.out)"
    }

    # C2 - completed normally: same staleness, but a SubagentStop record
    # exists. A send RESUMES a completed agent; refusing it would over-block
    # the platform's own documented behaviour.
    $s2 = New-LwgSession -Base $work -Tag 'c2'
    [void](Add-LwgAgent -Sess $s2 -AgentId 'a1111111111111111' -AgeMinutes 120)
    [void](Write-LwgHealth -RootDir $rootOn -Records @(
        @{ ts = '2026-08-01T12:00:00.0000000Z'; event = 'SessionStart'; session = $s2.id },
        @{ ts = '2026-08-01T12:30:00.0000000Z'; event = 'SubagentStop'; session = $s2.id; agent_id = 'a1111111111111111' }
    ))
    $r = Invoke-LwgScript -ScriptPath $SendGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'c2' `
             -Payload (New-LwgSendPayload -Sess $s2 -To 'a1111111111111111')
    $v = Test-IsAllow $r
    Add-Result 'C2 stale but completed normally (stop record) -> ALLOW' $v.ok $v.why

    # C3 - fresh transcript, no record: presumed running.
    $s3 = New-LwgSession -Base $work -Tag 'c3'
    [void](Add-LwgAgent -Sess $s3 -AgentId 'a2222222222222222' -AgeMinutes 0.5)
    [void](Write-LwgHealth -RootDir $rootOn -Records @(
        @{ ts = '2026-08-01T12:00:00.0000000Z'; event = 'SessionStart'; session = $s3.id }
    ))
    $r = Invoke-LwgScript -ScriptPath $SendGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'c3' `
             -Payload (New-LwgSendPayload -Sess $s3 -To 'a2222222222222222')
    $v = Test-IsAllow $r
    Add-Result 'C3 fresh transcript, no stop record -> ALLOW (presumed running)' $v.ok $v.why

    # C4 - "main" is the session itself.
    $r = Invoke-LwgScript -ScriptPath $SendGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'c4' `
             -Payload (New-LwgSendPayload -Sess $s3 -To 'main')
    $v = Test-IsAllow $r
    Add-Result 'C4 to "main" -> ALLOW' $v.ok $v.why

    # C5 - a NAME resolving through the meta to a dead agent. Latest meta wins
    # is not exercised here (one holder); what is exercised is that a name is
    # as refusable as a raw id.
    $s5 = New-LwgSession -Base $work -Tag 'c5'
    [void](Add-LwgAgent -Sess $s5 -AgentId 'a3333333333333333' -AgeMinutes 45 -Name 'researcher')
    [void](Write-LwgHealth -RootDir $rootOn -Records @(
        @{ ts = '2026-08-01T12:00:00.0000000Z'; event = 'SessionStart'; session = $s5.id }
    ))
    $r = Invoke-LwgScript -ScriptPath $SendGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'c5' `
             -Payload (New-LwgSendPayload -Sess $s5 -To 'researcher')
    $v = Test-IsDeny $r
    Add-Result 'C5 named recipient, dead -> DENY' $v.ok $v.why

    # C6 - same name, alive.
    $s6 = New-LwgSession -Base $work -Tag 'c6'
    [void](Add-LwgAgent -Sess $s6 -AgentId 'a4444444444444444' -AgeMinutes 0.5 -Name 'researcher')
    [void](Write-LwgHealth -RootDir $rootOn -Records @(
        @{ ts = '2026-08-01T12:00:00.0000000Z'; event = 'SessionStart'; session = $s6.id }
    ))
    $r = Invoke-LwgScript -ScriptPath $SendGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'c6' `
             -Payload (New-LwgSendPayload -Sess $s6 -To 'researcher')
    $v = Test-IsAllow $r
    Add-Result 'C6 named recipient, alive -> ALLOW' $v.ok $v.why

    # C7 - a recipient nothing answers to.
    $r = Invoke-LwgScript -ScriptPath $SendGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'c7' `
             -Payload (New-LwgSendPayload -Sess $s6 -To 'nonexistent-worker')
    $v = Test-IsDeny $r
    Add-Result 'C7 unresolvable recipient -> DENY' $v.ok $v.why

    # C8 - an agent-team address is outside what the gate can observe: abstain.
    $r = Invoke-LwgScript -ScriptPath $SendGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'c8' `
             -Payload (New-LwgSendPayload -Sess $s6 -To 'researcher@teamx')
    $v = Test-IsAllow $r
    Add-Result 'C8 team address -> ALLOW (abstain; layout not observable)' $v.ok $v.why

    # C9 - recorder never saw the session: its silence proves nothing.
    $s9 = New-LwgSession -Base $work -Tag 'c9'
    [void](Add-LwgAgent -Sess $s9 -AgentId 'a5555555555555555' -AgeMinutes 45)
    [void](Write-LwgHealth -RootDir $rootOn -Records @())
    $r = Invoke-LwgScript -ScriptPath $SendGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'c9' `
             -Payload (New-LwgSendPayload -Sess $s9 -To 'a5555555555555555')
    $v = Test-IsAllow $r
    Add-Result 'C9 stale transcript but NO health records for the session -> ALLOW (abstain)' $v.ok $v.why

    # C10 - the shipped default: same dead-recipient payload, switch off. The
    # gate must be inert, in silence.
    [void](Write-LwgHealth -RootDir $rootOff -Records @(
        @{ ts = '2026-08-01T12:00:00.0000000Z'; event = 'SessionStart'; session = $s1.id },
        @{ ts = '2026-08-01T12:30:00.0000000Z'; event = 'SubagentStop'; session = $s1.id; agent_id = 'a0000000000000001' }
    ))
    $r = Invoke-LwgScript -ScriptPath $SendGatePath -FakeRoot $rootOff -WorkDir $work -Tag 'c10' `
             -Payload (New-LwgSendPayload -Sess $s1 -To 'a726326973cfd6913')
    $v = Test-IsAllow $r
    Add-Result 'C10 switch off (shipped default): dead recipient -> ALLOW, silent' $v.ok $v.why

    # C11 - unreadable stdin with the switch on. Input the gate could not read
    # is not evidence of a live recipient: DENY, same polarity as delegate_gate.
    $r = Invoke-LwgScript -ScriptPath $SendGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'c11' -Payload ''
    $v = Test-IsDeny $r
    Add-Result 'C11 empty stdin, switch on -> DENY' $v.ok $v.why

    # C12 - stale_minutes is honoured: the 28-minute corpse is inside a
    # 60-minute threshold, so the gate must presume it running. The knob is
    # written into a copy of the ON config and ASSERTED.
    $rootKnob = Join-Path $work 'root-knob'
    [void][IO.Directory]::CreateDirectory($rootKnob)
    [void][IO.Directory]::CreateDirectory((Join-Path $rootKnob 'data'))
    $cfgObj = [IO.File]::ReadAllText((Join-Path $rootOn 'config.json')) | ConvertFrom-Json
    $cfgObj.module_config.send_liveness_gate.stale_minutes = 60
    [IO.File]::WriteAllText((Join-Path $rootKnob 'config.json'), ($cfgObj | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
    $probe = [IO.File]::ReadAllText((Join-Path $rootKnob 'config.json')) | ConvertFrom-Json
    if ([int]$probe.module_config.send_liveness_gate.stale_minutes -ne 60 -or $probe.supervision.send_liveness -ne $true) {
        throw 'the knob fixture did not round-trip (stale_minutes 60 with send_liveness on) - the case would establish nothing'
    }
    [void](Write-LwgHealth -RootDir $rootKnob -Records @(
        @{ ts = '2026-08-01T12:00:00.0000000Z'; event = 'SessionStart'; session = $s1.id }
    ))
    $r = Invoke-LwgScript -ScriptPath $SendGatePath -FakeRoot $rootKnob -WorkDir $work -Tag 'c12' `
             -Payload (New-LwgSendPayload -Sess $s1 -To 'a726326973cfd6913')
    $v = Test-IsAllow $r
    Add-Result 'C12 stale_minutes raised to 60 -> the 28-minute silence is ALLOWED' $v.ok $v.why

    # -------------------------------------------------------------------
    # D. completion_audit BEHAVIOUR.
    # -------------------------------------------------------------------
    # D1 - THE MEASURED PATTERN: prompt, SendMessage, "Added to the handoff."
    $d1 = New-LwgSession -Base $work -Tag 'd1'
    Add-LwgTranscript -Sess $d1 -JsonLines @(
        (New-UserPromptLine -Text 'please add the wind-down section to the handoff'),
        (New-ToolUseLine    -Tool 'SendMessage'),
        (New-TextLine       -Text 'Added to the handoff.')
    )
    $r = Invoke-LwgScript -ScriptPath $StopGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'd1' `
             -Payload (New-LwgStopPayload -Sess $d1 -HookActive $false)
    $v = Test-IsDeny $r
    Add-Result 'D1 THE MEASURED PATTERN: claim after queued send -> BLOCK' $v.ok $v.why
    if ($v.ok) {
        $env1 = $null
        try { $env1 = $r.out | ConvertFrom-Json } catch { }
        Add-Result 'D1a the stdout envelope is {"decision":"block"} with a reason' `
            ($null -ne $env1 -and [string]$env1.decision -eq 'block' -and
             -not [string]::IsNullOrWhiteSpace([string]$env1.reason)) `
            "stdout did not parse as a Stop block envelope: $($r.out)"
        Add-Result 'D1b the reason demands evidence, not repetition' `
            ($r.err -like '*queued message is not*' -and $r.err -like '*VERIFY*') `
            "the block text must say what evidence would make the claim honest: $($r.err)"
    }

    # D2 - the honest sentence: hedged, must never be refused.
    $d2 = New-LwgSession -Base $work -Tag 'd2'
    Add-LwgTranscript -Sess $d2 -JsonLines @(
        (New-UserPromptLine -Text 'please add the wind-down section to the handoff'),
        (New-ToolUseLine    -Tool 'SendMessage'),
        (New-TextLine       -Text 'I have dispatched the implementer and will report when it is done.')
    )
    $r = Invoke-LwgScript -ScriptPath $StopGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'd2' `
             -Payload (New-LwgStopPayload -Sess $d2 -HookActive $false)
    $v = Test-IsAllow $r
    Add-Result 'D2 hedged handoff sentence -> PASS' $v.ok $v.why

    # D3 - evidence-gathering after the send disarms the trigger.
    $d3 = New-LwgSession -Base $work -Tag 'd3'
    Add-LwgTranscript -Sess $d3 -JsonLines @(
        (New-UserPromptLine -Text 'please add the wind-down section to the handoff'),
        (New-ToolUseLine    -Tool 'SendMessage'),
        (New-ToolUseLine    -Tool 'Read'),
        (New-TextLine       -Text 'Added to the handoff.')
    )
    $r = Invoke-LwgScript -ScriptPath $StopGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'd3' `
             -Payload (New-LwgStopPayload -Sess $d3 -HookActive $false)
    $v = Test-IsAllow $r
    Add-Result 'D3 a Read after the send -> PASS (evidence-gathering followed)' $v.ok $v.why

    # D4 - the claim preceding the send is a different shape and not this rule.
    $d4 = New-LwgSession -Base $work -Tag 'd4'
    Add-LwgTranscript -Sess $d4 -JsonLines @(
        (New-UserPromptLine -Text 'please add the wind-down section to the handoff'),
        (New-TextLine       -Text 'Added to the handoff.'),
        (New-ToolUseLine    -Tool 'SendMessage')
    )
    $r = Invoke-LwgScript -ScriptPath $StopGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'd4' `
             -Payload (New-LwgStopPayload -Sess $d4 -HookActive $false)
    $v = Test-IsAllow $r
    Add-Result 'D4 claim BEFORE the send, nothing after -> PASS' $v.ok $v.why

    # D5 - a turn with no tools cannot trip a rule about the last tool.
    $d5 = New-LwgSession -Base $work -Tag 'd5'
    Add-LwgTranscript -Sess $d5 -JsonLines @(
        (New-UserPromptLine -Text 'what did you do earlier'),
        (New-TextLine       -Text 'Earlier I added the section and committed it; the tests passed.')
    )
    $r = Invoke-LwgScript -ScriptPath $StopGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'd5' `
             -Payload (New-LwgStopPayload -Sess $d5 -HookActive $false)
    $v = Test-IsAllow $r
    Add-Result 'D5 claim with no tool calls this turn -> PASS' $v.ok $v.why

    # D6 - the loop guard: on the continuation the same transcript must pass.
    $r = Invoke-LwgScript -ScriptPath $StopGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'd6' `
             -Payload (New-LwgStopPayload -Sess $d1 -HookActive $true)
    $v = Test-IsAllow $r
    Add-Result 'D6 stop_hook_active -> PASS (fires at most once per turn end)' $v.ok $v.why

    # D7 - shipped default: the measured pattern passes with the switch off.
    $r = Invoke-LwgScript -ScriptPath $StopGatePath -FakeRoot $rootOff -WorkDir $work -Tag 'd7' `
             -Payload (New-LwgStopPayload -Sess $d1 -HookActive $false)
    $v = Test-IsAllow $r
    Add-Result 'D7 switch off (shipped default): measured pattern -> PASS, silent' $v.ok $v.why

    # D8 - sidechain records are some other agent's turn, not this one's.
    $d8 = New-LwgSession -Base $work -Tag 'd8'
    Add-LwgTranscript -Sess $d8 -JsonLines @(
        (New-UserPromptLine -Text 'please review'),
        '{"type":"assistant","isSidechain":true,"message":{"content":[{"type":"tool_use","id":"t9","name":"SendMessage","input":{}}]}}',
        '{"type":"assistant","isSidechain":true,"message":{"content":[{"type":"text","text":"Added to the handoff."}]}}'
    )
    $r = Invoke-LwgScript -ScriptPath $StopGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'd8' `
             -Payload (New-LwgStopPayload -Sess $d8 -HookActive $false)
    $v = Test-IsAllow $r
    Add-Result 'D8 sidechain send+claim, clean main thread -> PASS' $v.ok $v.why

    # D9 - a NEW user prompt resets the turn: yesterday's send is not this
    # turn's last tool.
    $d9 = New-LwgSession -Base $work -Tag 'd9'
    Add-LwgTranscript -Sess $d9 -JsonLines @(
        (New-UserPromptLine -Text 'please add the section'),
        (New-ToolUseLine    -Tool 'SendMessage'),
        (New-UserPromptLine -Text 'thanks, and what is the total'),
        (New-TextLine       -Text 'Done - the total is 4.')
    )
    $r = Invoke-LwgScript -ScriptPath $StopGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'd9' `
             -Payload (New-LwgStopPayload -Sess $d9 -HookActive $false)
    $v = Test-IsAllow $r
    Add-Result 'D9 send in a PRIOR turn, claim in this one -> PASS (turns reset at prompts)' $v.ok $v.why

    # -------------------------------------------------------------------
    # D10-D17. completion_audit in SUBAGENT MODE.
    # Registered under Stop alone until 11 August 2026, this gate fired for no
    # subagent and no teammate. These cases hold the fix to the two ways a
    # registration-only change would have gone wrong: auditing the PARENT's turn,
    # and discarding every record of a transcript in which all of them are
    # sidechain.
    # -------------------------------------------------------------------
    # D10 - THE CORE: the measured pattern inside a SUBAGENT transcript, whose
    # records are ALL isSidechain:true, with a CLEAN parent. A block here can
    # only have come from the agent transcript, and only if sidechain records
    # were assessed rather than skipped.
    $d10 = New-LwgSession -Base $work -Tag 'd10'
    Add-LwgTranscript -Sess $d10 -JsonLines @(
        (New-UserPromptLine -Text 'delegate the handoff edit'),
        (New-TextLine       -Text 'Understood, I will dispatch a worker.')
    )
    $a10 = New-LwgAgentFile -Sess $d10 -AgentId 'aa10' -JsonLines @(
        (New-SideUserLine    -Text 'add the wind-down section to the handoff'),
        (New-SideToolUseLine -Tool 'SendMessage'),
        (New-SideTextLine    -Text 'Added to the handoff.')
    )
    $r = Invoke-LwgScript -ScriptPath $StopGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'd10' `
             -ScriptArgs '-HookEvent SubagentStop' `
             -Payload (New-LwgSubStopPayload -Sess $d10 -AgentPath $a10 -HookActive $false)
    $v = Test-IsDeny $r
    Add-Result 'D10 SUBAGENT MODE: claim after queued send, all-sidechain transcript -> BLOCK' $v.ok `
        ("$($v.why) - the subagent transcript is assessed only if agent_transcript_path is selected AND the sidechain skip is lifted; either one left as-is makes this a silent no-op")

    # D11 - THE FALSE-BLOCK GUARD, and the reason a registration-only change
    # would have been worse than the gap: the PARENT is mid-measured-pattern
    # while the subagent's own turn is clean. In a delegate pattern this is the
    # COMMON case, so a gate reading transcript_path here would block almost
    # every worker for something it did not say.
    $d11 = New-LwgSession -Base $work -Tag 'd11'
    Add-LwgTranscript -Sess $d11 -JsonLines @(
        (New-UserPromptLine -Text 'please add the wind-down section to the handoff'),
        (New-ToolUseLine    -Tool 'SendMessage'),
        (New-TextLine       -Text 'Added to the handoff.')
    )
    $a11 = New-LwgAgentFile -Sess $d11 -AgentId 'aa11' -JsonLines @(
        (New-SideUserLine    -Text 'go and read the ledger'),
        (New-SideToolUseLine -Tool 'Read'),
        (New-SideTextLine    -Text 'The ledger shows four open contracts.')
    )
    $r = Invoke-LwgScript -ScriptPath $StopGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'd11' `
             -ScriptArgs '-HookEvent SubagentStop' `
             -Payload (New-LwgSubStopPayload -Sess $d11 -AgentPath $a11 -HookActive $false)
    $v = Test-IsAllow $r
    Add-Result 'D11 SUBAGENT MODE: parent mid-pattern, subagent clean -> PASS (never blocked for the parent)' $v.ok $v.why

    # D12 - the same guard with the sharpest possible edge: NO
    # agent_transcript_path at all, parent still mid-pattern. The only safe
    # degradation is a silent no-op; falling back to transcript_path here is the
    # false block in its purest form.
    $r = Invoke-LwgScript -ScriptPath $StopGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'd12' `
             -ScriptArgs '-HookEvent SubagentStop' `
             -Payload (New-LwgSubStopPayload -Sess $d11 -AgentPath '' -HookActive $false)
    $v = Test-IsAllow $r
    Add-Result 'D12 SUBAGENT MODE: no agent_transcript_path -> PASS silently, NO fallback to the parent' $v.ok $v.why

    # D13 - the loop guard, on this event too. It is checked FIRST in the script,
    # before config and before transcript selection, and must stay there.
    $r = Invoke-LwgScript -ScriptPath $StopGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'd13' `
             -ScriptArgs '-HookEvent SubagentStop' `
             -Payload (New-LwgSubStopPayload -Sess $d10 -AgentPath $a10 -HookActive $true)
    $v = Test-IsAllow $r
    Add-Result 'D13 SUBAGENT MODE: stop_hook_active -> PASS (refuses a turn end at most once)' $v.ok $v.why

    # D14 - a user record that is WHOLLY a <system-reminder> wrapper is an
    # injection, not a turn start. Were it treated as one it would reset the turn
    # and the send would fall out of scope, silencing the gate. Measured in a
    # live subagent transcript, so this shape is real.
    $d14 = New-LwgSession -Base $work -Tag 'd14'
    $a14 = New-LwgAgentFile -Sess $d14 -AgentId 'aa14' -JsonLines @(
        (New-SideUserLine    -Text 'add the wind-down section'),
        (New-SideToolUseLine -Tool 'SendMessage'),
        (New-SideUserLine    -Text '<system-reminder> Other agents are active in this session. </system-reminder>'),
        (New-SideTextLine    -Text 'Added to the handoff.')
    )
    $r = Invoke-LwgScript -ScriptPath $StopGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'd14' `
             -ScriptArgs '-HookEvent SubagentStop' `
             -Payload (New-LwgSubStopPayload -Sess $d14 -AgentPath $a14 -HookActive $false)
    $v = Test-IsDeny $r
    Add-Result 'D14 SUBAGENT MODE: a system-reminder-only record does NOT reset the turn -> BLOCK' $v.ok $v.why

    # D15 - but a genuine re-wake DOES. Subagent transcripts are multi-turn and
    # a re-wake is structurally identical to a typed operator prompt.
    $d15 = New-LwgSession -Base $work -Tag 'd15'
    $a15 = New-LwgAgentFile -Sess $d15 -AgentId 'aa15' -JsonLines @(
        (New-SideUserLine    -Text 'add the wind-down section'),
        (New-SideToolUseLine -Tool 'SendMessage'),
        (New-SideUserLine    -Text 'thanks - now what is the total'),
        (New-SideTextLine    -Text 'Done - the total is 4.')
    )
    $r = Invoke-LwgScript -ScriptPath $StopGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'd15' `
             -ScriptArgs '-HookEvent SubagentStop' `
             -Payload (New-LwgSubStopPayload -Sess $d15 -AgentPath $a15 -HookActive $false)
    $v = Test-IsAllow $r
    Add-Result 'D15 SUBAGENT MODE: a real re-wake prompt DOES reset the turn -> PASS' $v.ok $v.why

    # D16 - the error path. A path that does not exist must exit 0 and stay
    # silent: a broken audit may never pin a session shut.
    $r = Invoke-LwgScript -ScriptPath $StopGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'd16' `
             -ScriptArgs '-HookEvent SubagentStop' `
             -Payload (New-LwgSubStopPayload -Sess $d10 -AgentPath (Join-Path $work 'no-such-agent.jsonl') -HookActive $false)
    $v = Test-IsAllow $r
    Add-Result 'D16 SUBAGENT MODE: unreadable agent transcript -> PASS silently (fails OPEN)' $v.ok $v.why

    # D17 - THE REGRESSION GUARD ON Stop MODE, which is the only completion gate
    # that fires at all today. Stop must still select transcript_path: here the
    # parent is clean and a dirty agent path is supplied, and reading the wrong
    # one would block.
    $d17 = New-LwgSession -Base $work -Tag 'd17'
    Add-LwgTranscript -Sess $d17 -JsonLines @(
        (New-UserPromptLine -Text 'what is the total'),
        (New-TextLine       -Text 'The total is 4.')
    )
    $a17 = New-LwgAgentFile -Sess $d17 -AgentId 'aa17' -JsonLines @(
        (New-SideUserLine    -Text 'add the section'),
        (New-SideToolUseLine -Tool 'SendMessage'),
        (New-SideTextLine    -Text 'Added to the handoff.')
    )
    $stopPayloadWithAgent = ('{"session_id":"' + $d17.id + '","transcript_path":"' + ($d17.main -replace '\\', '/') +
                             '","cwd":"C:/nowhere","hook_event_name":"Stop","agent_transcript_path":"' +
                             ($a17 -replace '\\', '/') + '"}')
    $r = Invoke-LwgScript -ScriptPath $StopGatePath -FakeRoot $rootOn -WorkDir $work -Tag 'd17' `
             -Payload $stopPayloadWithAgent
    $v = Test-IsAllow $r
    Add-Result 'D17 Stop MODE still selects transcript_path, not agent_transcript_path -> PASS' $v.ok $v.why

    # -------------------------------------------------------------------
    # E. orphan_watch BEHAVIOUR (through the real supervisor).
    # -------------------------------------------------------------------
    # E1 - the four-orphans case in miniature: spawned, never stopped, silent.
    $e1 = New-LwgSession -Base $work -Tag 'e1'
    [void](Add-LwgAgent -Sess $e1 -AgentId 'a6666666666666666' -AgeMinutes 40)
    [void](Write-LwgHealth -RootDir $rootOn -Records @(
        @{ ts = '2026-08-01T12:00:00.0000000Z'; event = 'SessionStart'; session = $e1.id }
    ))
    $r = Invoke-LwgScript -ScriptPath $SupervisorPath -FakeRoot $rootOn -WorkDir $work -Tag 'e1' `
             -ScriptArgs '-HookEvent Stop' -Payload (New-LwgStopPayload -Sess $e1 -HookActive $false)
    Add-Result 'E1 orphaned agent -> exit 2 alert naming the agent' `
        ($r.code -eq 2 -and $r.err -like '*ORPHANED*' -and $r.err -like '*a6666666666666666*' -and $r.err -like '*NEVER be delivered*') `
        "expected exit 2 with an orphan alert naming a6666666666666666; got exit $($r.code), stderr: $($r.err)"

    # E2 - dedupe: the same orphan must not re-alert at every turn end.
    $r = Invoke-LwgScript -ScriptPath $SupervisorPath -FakeRoot $rootOn -WorkDir $work -Tag 'e2' `
             -ScriptArgs '-HookEvent Stop' -Payload (New-LwgStopPayload -Sess $e1 -HookActive $false)
    Add-Result 'E2 the same orphan alerts once (alerted.json dedupe) -> exit 0' `
        ($r.code -eq 0 -and [string]::IsNullOrWhiteSpace($r.err)) `
        "expected a silent exit 0 on the second run; got exit $($r.code), stderr: $($r.err)"

    # Captured HERE, before later cases overwrite the fixture health log: the
    # E1/E2 evidence for case E7 below.
    $hOnE2 = ''
    try { $hOnE2 = [IO.File]::ReadAllText((Join-Path (Join-Path $rootOn 'data') 'health.jsonl')) } catch { }

    # E3 - an agent that stopped normally is not an orphan, however old.
    $e3 = New-LwgSession -Base $work -Tag 'e3'
    [void](Add-LwgAgent -Sess $e3 -AgentId 'a7777777777777777' -AgeMinutes 300)
    [void](Write-LwgHealth -RootDir $rootOn -Records @(
        @{ ts = '2026-08-01T12:00:00.0000000Z'; event = 'SessionStart'; session = $e3.id },
        @{ ts = '2026-08-01T12:30:00.0000000Z'; event = 'SubagentStop'; session = $e3.id; agent_id = 'a7777777777777777' }
    ))
    $r = Invoke-LwgScript -ScriptPath $SupervisorPath -FakeRoot $rootOn -WorkDir $work -Tag 'e3' `
             -ScriptArgs '-HookEvent Stop' -Payload (New-LwgStopPayload -Sess $e3 -HookActive $false)
    Add-Result 'E3 stopped-normally agent -> no alert' `
        ($r.code -eq 0 -and [string]::IsNullOrWhiteSpace($r.err)) `
        "expected exit 0 in silence; got exit $($r.code), stderr: $($r.err)"

    # E4 - a fresh transcript is a running agent, not an orphan.
    $e4 = New-LwgSession -Base $work -Tag 'e4'
    [void](Add-LwgAgent -Sess $e4 -AgentId 'a8888888888888888' -AgeMinutes 0.5)
    [void](Write-LwgHealth -RootDir $rootOn -Records @(
        @{ ts = '2026-08-01T12:00:00.0000000Z'; event = 'SessionStart'; session = $e4.id }
    ))
    $r = Invoke-LwgScript -ScriptPath $SupervisorPath -FakeRoot $rootOn -WorkDir $work -Tag 'e4' `
             -ScriptArgs '-HookEvent Stop' -Payload (New-LwgStopPayload -Sess $e4 -HookActive $false)
    Add-Result 'E4 running agent -> no alert' `
        ($r.code -eq 0 -and [string]::IsNullOrWhiteSpace($r.err)) `
        "expected exit 0 in silence; got exit $($r.code), stderr: $($r.err)"

    # E5 - shipped default: with orphan_watch off the orphan raises nothing,
    # and the Stop record must NOT carry an "orphans" field - a zero stamped by
    # a run that never looked is the false green this plugin exists to refuse.
    $e5 = New-LwgSession -Base $work -Tag 'e5'
    [void](Add-LwgAgent -Sess $e5 -AgentId 'a9999999999999999' -AgeMinutes 40)
    [void](Write-LwgHealth -RootDir $rootOff -Records @(
        @{ ts = '2026-08-01T12:00:00.0000000Z'; event = 'SessionStart'; session = $e5.id }
    ))
    $r = Invoke-LwgScript -ScriptPath $SupervisorPath -FakeRoot $rootOff -WorkDir $work -Tag 'e5' `
             -ScriptArgs '-HookEvent Stop' -Payload (New-LwgStopPayload -Sess $e5 -HookActive $false)
    $hOff = ''
    try { $hOff = [IO.File]::ReadAllText((Join-Path (Join-Path $rootOff 'data') 'health.jsonl')) } catch { }
    Add-Result 'E5 switch off (shipped default): orphan raises nothing and no "orphans" field is stamped' `
        ($r.code -eq 0 -and [string]::IsNullOrWhiteSpace($r.err) -and $hOff -notlike '*"orphans"*') `
        "expected silent exit 0 and no orphans field in the Stop record; got exit $($r.code), stderr: $($r.err), health tail: $hOff"

    # E6 - the recorder's silence proves nothing: an empty health.jsonl yields
    # no orphan verdict, however stale the transcript.
    $e6 = New-LwgSession -Base $work -Tag 'e6'
    [void](Add-LwgAgent -Sess $e6 -AgentId 'aaaaaaaaaaaaaaaa1' -AgeMinutes 400)
    [void](Write-LwgHealth -RootDir $rootOn -Records @())
    $r = Invoke-LwgScript -ScriptPath $SupervisorPath -FakeRoot $rootOn -WorkDir $work -Tag 'e6' `
             -ScriptArgs '-HookEvent Stop' -Payload (New-LwgStopPayload -Sess $e6 -HookActive $false)
    Add-Result 'E6 no health records for the session -> no orphan verdict' `
        ($r.code -eq 0 -and [string]::IsNullOrWhiteSpace($r.err)) `
        "expected exit 0 in silence; got exit $($r.code), stderr: $($r.err)"

    # E7 - the record still counts what the alert dedupe suppresses: on a
    # re-run the orphans field keeps saying 1, so the log is evidence even
    # when the channel is quiet. Asserted on the snapshot taken right after E2,
    # because later cases overwrite the fixture health log.
    Add-Result 'E7 the Stop records carry "orphans":1 for the E1/E2 session' `
        (([regex]::Matches($hOnE2, '"orphans":1')).Count -ge 2) `
        "expected at least two Stop records with orphans:1 (the alerting run and the deduped one); health held: $hOnE2"

    # E8 - THE STATED-CAUSE PATH, and the case the silence rule cannot serve.
    # The agent is FRESH: its transcript was written seconds ago, so every
    # silence threshold in this module says "still running". What makes it a
    # death is that the HARNESS SAID SO - a task-notification in the PARENT
    # transcript naming the agent with <status>failed</status>. Anchored on the
    # measured 600s stall of 10 August 2026, whose subagent transcript ended
    # "[Request interrupted by user]" and carried no API-error record at all, so
    # the transcript-sniffing fast path could never have reached it.
    $e8 = New-LwgSession -Base $work -Tag 'e8'
    [void](Add-LwgAgent -Sess $e8 -AgentId 'a8888888888888888' -AgeMinutes 0)
    [void](Write-LwgHealth -RootDir $rootOn -Records @(
        @{ ts = '2026-08-01T12:00:00.0000000Z'; event = 'SessionStart'; session = $e8.id }
    ))
    [IO.File]::WriteAllText($e8.main, ('{"type":"user","message":{"role":"user","content":"<task-notification>\n<task-id>a8888888888888888</task-id>\n<status>failed</status>\n<summary>Agent \"fixture\" failed: Agent stalled: no progress for 600s (stream watchdog did not recover)</summary>\n</task-notification>"}}' + "`n"), [Text.UTF8Encoding]::new($false))
    $r = Invoke-LwgScript -ScriptPath $SupervisorPath -FakeRoot $rootOn -WorkDir $work -Tag 'e8' `
             -ScriptArgs '-HookEvent Stop' -Payload (New-LwgStopPayload -Sess $e8 -HookActive $false)
    Add-Result 'E8 harness-stated failure on a FRESH transcript -> exit 2 DIED, no threshold served' `
        ($r.code -eq 2 -and $r.err -like '*DIED*' -and $r.err -like '*a8888888888888888*' -and $r.err -like '*600s*') `
        "expected exit 2 with a DIED block naming a8888888888888888 and quoting the stall; got exit $($r.code), stderr: $($r.err)"

    # E9 - the false-positive guard that makes E8 safe. TWENTY-FOUR of the 28
    # task-notifications in the measured session were <status>completed</status>;
    # a reader that keyed on <task-id> alone would have called every finished
    # agent dead. A fresh agent with a COMPLETED notification must stay silent.
    $e9 = New-LwgSession -Base $work -Tag 'e9'
    [void](Add-LwgAgent -Sess $e9 -AgentId 'a9999999999999999' -AgeMinutes 0)
    [void](Write-LwgHealth -RootDir $rootOn -Records @(
        @{ ts = '2026-08-01T12:00:00.0000000Z'; event = 'SessionStart'; session = $e9.id }
    ))
    [IO.File]::WriteAllText($e9.main, ('{"type":"user","message":{"role":"user","content":"<task-notification>\n<task-id>a9999999999999999</task-id>\n<status>completed</status>\n<summary>Agent \"fixture\" finished</summary>\n</task-notification>"}}' + "`n"), [Text.UTF8Encoding]::new($false))
    $r = Invoke-LwgScript -ScriptPath $SupervisorPath -FakeRoot $rootOn -WorkDir $work -Tag 'e9' `
             -ScriptArgs '-HookEvent Stop' -Payload (New-LwgStopPayload -Sess $e9 -HookActive $false)
    Add-Result 'E9 a COMPLETED task-notification is not a death -> silent exit 0' `
        ($r.code -eq 0 -and [string]::IsNullOrWhiteSpace($r.err)) `
        "expected silent exit 0 for a completed notification; got exit $($r.code), stderr: $($r.err)"

    # E10 - THE REGRESSION PIN FOR A REMOVED FAST PATH, and the shape that
    # removed it. A five-minute threshold keyed on an isApiErrorMessage
    # transcript tail was measured reporting a LIVE agent dead: re-derived over
    # 1,050 transcripts, all four mid-file API errors recovered, and the
    # 4,011.2s one is error 'server_error' with NO apiErrorStatus and no '529'
    # or 'Overloaded' in its text, so it fell through the back-pressure class
    # exclusion. This fixture is that record verbatim, on an agent silent EIGHT
    # minutes - past the deleted five-minute path, inside the fifteen-minute
    # silence rule. It must raise NOTHING. If this case ever fails, a fast path
    # has been reintroduced; read $removed_error_stale_comment in config.json
    # before changing the expectation.
    $e10 = New-LwgSession -Base $work -Tag 'e10'
    $t10 = Add-LwgAgent -Sess $e10 -AgentId 'aaaaaaaaaaaaaaaa2' -AgeMinutes 8
    [IO.File]::WriteAllText($t10, ('{"isApiErrorMessage":true,"error":"server_error","message":{"role":"assistant","content":[{"type":"text","text":"API Error: Server error mid-response. The response above may be incomplete."}]}}' + "`n"), [Text.UTF8Encoding]::new($false))
    [IO.File]::SetLastWriteTimeUtc($t10, [datetime]::UtcNow.AddMinutes(-8))
    [void](Write-LwgHealth -RootDir $rootOn -Records @(
        @{ ts = '2026-08-01T12:00:00.0000000Z'; event = 'SessionStart'; session = $e10.id }
    ))
    $r = Invoke-LwgScript -ScriptPath $SupervisorPath -FakeRoot $rootOn -WorkDir $work -Tag 'e10' `
             -ScriptArgs '-HookEvent Stop' -Payload (New-LwgStopPayload -Sess $e10 -HookActive $false)
    Add-Result 'E10 mid-stream server_error at 8 min (the measured 67-min recovery) -> NO alert' `
        ($r.code -eq 0 -and [string]::IsNullOrWhiteSpace($r.err)) `
        "a removed fast path appears to be back: expected silent exit 0, got exit $($r.code), stderr: $($r.err)"

    # E11 - the SubagentStop trigger itself, which no case reached: every orphan
    # case above runs -HookEvent Stop, so deleting the SubagentStop
    # reconciliation left all cases passing. This pins the denser trigger that
    # the whole 42-minute latency fix consists of.
    $e11 = New-LwgSession -Base $work -Tag 'e11'
    [void](Add-LwgAgent -Sess $e11 -AgentId 'aaaaaaaaaaaaaaaa3' -AgeMinutes 40)
    [void](Write-LwgHealth -RootDir $rootOn -Records @(
        @{ ts = '2026-08-01T12:00:00.0000000Z'; event = 'SessionStart'; session = $e11.id }
    ))
    $r = Invoke-LwgScript -ScriptPath $SupervisorPath -FakeRoot $rootOn -WorkDir $work -Tag 'e11' `
             -ScriptArgs '-HookEvent SubagentStop' -Payload (New-LwgStopPayload -Sess $e11 -HookActive $false)
    Add-Result 'E11 orphan detected on the SubagentStop trigger, not only at Stop -> exit 2' `
        ($r.code -eq 2 -and $r.err -like '*aaaaaaaaaaaaaaaa3*') `
        "expected exit 2 naming the orphan on SubagentStop; got exit $($r.code), stderr: $($r.err)"

    # E12 - HH MUST BE CLEARABLE. A standing orphan is re-detected at every
    # later trigger, and the status line takes a PEAK of the recorded count
    # since the last Resolved marker. While the record carried only the standing
    # count, /lw-watchtower:resolve cleared HH and the next SubagentStop turned it red
    # again within seconds, permanently - the operator's only remedy being to
    # switch the module off, which is how a health indicator teaches people to
    # ignore it. The first run must report the orphan as NEW; the second must
    # record it as standing but NOT new.
    $e12 = New-LwgSession -Base $work -Tag 'e12'
    [void](Add-LwgAgent -Sess $e12 -AgentId 'aaaaaaaaaaaaaaaa4' -AgeMinutes 40)
    [void](Write-LwgHealth -RootDir $rootOn -Records @(
        @{ ts = '2026-08-01T12:00:00.0000000Z'; event = 'SessionStart'; session = $e12.id }
    ))
    $r1 = Invoke-LwgScript -ScriptPath $SupervisorPath -FakeRoot $rootOn -WorkDir $work -Tag 'e12a' `
              -ScriptArgs '-HookEvent SubagentStop' -Payload (New-LwgStopPayload -Sess $e12 -HookActive $false)
    $r2 = Invoke-LwgScript -ScriptPath $SupervisorPath -FakeRoot $rootOn -WorkDir $work -Tag 'e12b' `
              -ScriptArgs '-HookEvent SubagentStop' -Payload (New-LwgStopPayload -Sess $e12 -HookActive $false)
    $h12 = ''
    try { $h12 = [IO.File]::ReadAllText((Join-Path (Join-Path $rootOn 'data') 'health.jsonl')) } catch { }
    Add-Result 'E12 a standing orphan records orphans_new:0 on re-detection, so HH can be cleared' `
        ($r1.code -eq 2 -and $r2.code -eq 0 -and $h12 -like '*"orphans_new":1*' -and $h12 -like '*"orphans_new":0*') `
        "expected first run exit 2 with orphans_new:1 and second exit 0 with orphans_new:0; got $($r1.code)/$($r2.code), health: $h12"

    # E13 - THE EVIDENCE HORIZON. health.jsonl is read as a bounded tail, and
    # this install's log already exceeds it, so a SubagentStop record can scroll
    # out of the window while the agent's transcript stays on disk forever. The
    # verdict is "no stop record exists", so a lost record does not weaken it -
    # it inverts it, and a cleanly finished agent becomes a permanent orphan.
    # Here the window holds records for the session but NO SessionStart, and the
    # agent's transcript predates the earliest record we can see, so the module
    # must abstain rather than guess.
    $e13 = New-LwgSession -Base $work -Tag 'e13'
    $t13 = Add-LwgAgent -Sess $e13 -AgentId 'aaaaaaaaaaaaaaaa5' -AgeMinutes 600
    [void](Write-LwgHealth -RootDir $rootOn -Records @(
        @{ ts = ([datetime]::UtcNow.AddMinutes(-30)).ToString('o'); event = 'Stop'; session = $e13.id; failed_tasks = 0 }
    ))
    $r = Invoke-LwgScript -ScriptPath $SupervisorPath -FakeRoot $rootOn -WorkDir $work -Tag 'e13' `
             -ScriptArgs '-HookEvent Stop' -Payload (New-LwgStopPayload -Sess $e13 -HookActive $false)
    Add-Result 'E13 transcript older than the health window (no SessionStart) -> abstain, no alert' `
        ($r.code -eq 0 -and [string]::IsNullOrWhiteSpace($r.err)) `
        "expected abstention past the evidence horizon; got exit $($r.code), stderr: $($r.err)"

    # E14 - and the horizon must not become a blanket excuse. With SessionStart
    # in the window the record set provably reaches back past every SubagentStop
    # the session could have written, so absence IS evidence and the same old
    # transcript is judged normally.
    $e14 = New-LwgSession -Base $work -Tag 'e14'
    [void](Add-LwgAgent -Sess $e14 -AgentId 'aaaaaaaaaaaaaaaa6' -AgeMinutes 600)
    [void](Write-LwgHealth -RootDir $rootOn -Records @(
        @{ ts = ([datetime]::UtcNow.AddMinutes(-30)).ToString('o'); event = 'SessionStart'; session = $e14.id }
    ))
    $r = Invoke-LwgScript -ScriptPath $SupervisorPath -FakeRoot $rootOn -WorkDir $work -Tag 'e14' `
             -ScriptArgs '-HookEvent Stop' -Payload (New-LwgStopPayload -Sess $e14 -HookActive $false)
    Add-Result 'E14 SessionStart in the window -> the horizon lifts and the orphan is reported' `
        ($r.code -eq 2 -and $r.err -like '*aaaaaaaaaaaaaaaa6*') `
        "expected exit 2 naming the orphan when the window is provably complete; got exit $($r.code), stderr: $($r.err)"

    # -------------------------------------------------------------------
    # RESULT
    # -------------------------------------------------------------------
    $sw.Stop()
    $total = $script:Results.Count
    Write-Output ''
    Write-Output ('RESULT: {0} of {1} case(s) passed in {2:0.0}s' -f $script:Pass, $total, $sw.Elapsed.TotalSeconds)
    if ($total -eq 0) {
        Write-Output 'ABORT: zero cases ran, which is never a pass.'
        Write-Output 'EXIT: 2'
        exit 2
    }
    if ($script:Pass -lt $total) {
        Write-Output 'EXIT: 1'
        exit 1
    }
    Write-Output ''
    Write-Output 'Every case above passed. Read that as "these rules still behave", not as
"an agent inferred dead from silence actually was" - that judgement is not in the code.'
    Write-Output 'EXIT: 0'
    exit 0

} catch {
    Write-Output ''
    Write-Output ("ABORT: {0}" -f $_.Exception.Message)
    Write-Output ("       at {0}" -f $_.InvocationInfo.PositionMessage)
    Write-Output 'EXIT: 2'
    exit 2
} finally {
    if (-not [string]::IsNullOrWhiteSpace($work) -and [IO.Directory]::Exists($work)) {
        try { [IO.Directory]::Delete($work, $true) } catch { }
    }
}
