#requires -version 5
<#
  LW-WATCHTOWER metrics INDEXER + SCOREBOARD regression suite -
  bin\lwg-metrics.ps1 and lib\metrics.ps1.

      powershell -NoProfile -ExecutionPolicy Bypass -File tests\metrics_behaviour.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File tests\metrics_behaviour.ps1 -Verbose

  ---------------------------------------------------------------------------
  WHY THIS FILE EXISTS AT ALL, WHEN THE STANDING RULE IS THAT tests\ TAKES NO
  NEW FILE
  ---------------------------------------------------------------------------
  It is a WAIVER, granted once, by the owner, on 6 September 2026 - ruling F5,
  recorded on #147 and restated on #165 and #311. The rule exists to stop a
  suite being added for every change; it was never meant to force a
  transcript indexer under a suite named for the doctor. Two files are covered
  by that one ruling - this one and tests\stack_mode.ps1 (#179) - and the
  ruling's own words are that it is THE ONLY WAIVER IN THE RELEASE.

  The obligation that came with it is discharged in the same commit as this
  file: tests\ goes from FOURTEEN files to FIFTEEN, and every prose site that
  states the suite count is restated with it. tests\doc_claims.ps1 derives that
  number from the tree and fails the build rather than letting it rot.

  ---------------------------------------------------------------------------
  WHAT IS UNDER TEST, AND WHAT IS DELIBERATELY NOT
  ---------------------------------------------------------------------------
  #165 asks for a metrics module with three surfaces: a hook that records a row
  per dispatch (R1), a transcript indexer and scoreboard (R2), a usage-meter
  history (R3), LCAP round capture (R5), landing detection (R6), a decision rule
  (R8) and a written METRICS.md (R9).

  THIS SLICE IS R2 AND NOTHING ELSE. The owner's 2026-09-06 ruling: the first
  slice is the transcript indexer and the scoreboard, as a command, reading only
  files that already exist - no hook change, no module flag, no METRICS.md, no
  decision rule, and R1's per-dispatch cost field is #166's row and is not built
  here.

  So the criteria this file drives are #165's A1 and A2, plus the properties the
  SLICE itself has to hold:

      SECTION A   A1 - usage is summed ONCE per message.id; <synthetic> lines are
                  excluded; subagents\workflows\wf_*\ is recursed; the arithmetic
                  is 64-bit
      SECTION B   A2 - a dispatch is attributed to its subagent transcript, and
                  the REQUESTED tier and the RESOLVED model are both recorded and
                  never collapsed into one
      SECTION S   the slice's own contract - every column with no source in this
                  slice prints NOT DETERMINED and never a zero; the report exits
                  3 rather than inventing one when it cannot look; no operator
                  path reaches stdout; and S8, THE ONE CASE HERE WRITTEN AFTER A
                  REAL DEFECT RATHER THAN BEFORE ONE - the command creates no
                  directory anywhere. The first build resolved the state
                  directory through lib\common.ps1's Get-LwgStateDir, which
                  CREATES what it resolves, so three real runs left an empty
                  directory under the unsuffixed fallback name on the operator's
                  disk and handed bin\lwg-doctor.ps1 a state-dir FAIL, while
                  every page describing this command said it wrote nothing. No
                  case could see it, because every other run here is handed an
                  existing scratch data directory

  RESERVED, AND NOT SILENTLY MISSING. #165's remaining acceptance criteria each
  belong to a requirement this slice does not build, and each is named here with
  the slice that owns it so a reader counting sections does not read their
  absence as coverage:

      SECTION C   A3 - meter calibration, reset-crossing intervals, `unreliable`
                  under 5 intervals.                            needs R3
      SECTION D   A4 - the LCAP-ROUND trailer read from a hook payload.
                                                                needs R5, and it
                  is tests\stop_behaviour.ps1's, not this file's - that suite
                  owns the SubagentStop handler
      SECTION E   A5 - landing detection and the Claude-Session join.  needs R6
      SECTION F   A6 - the decision table, rules 1-6 and their boundaries.
                                                                needs R8
      SECTION G   A7 - METRICS.md written only with a marker, at the repository
                  root, never staged.                           needs R9
      SECTION H   A8/A9 - hook budgets and the supervisor contract. Those are
                  tests\stop_behaviour.ps1's by #311's own mapping, and this
                  slice adds no hook for them to measure

  ---------------------------------------------------------------------------
  RED FIRST - what this suite did at the baseline 5d52516
  ---------------------------------------------------------------------------
  BASELINE: 5d52516 ("The orchestrator role becomes a system prompt that can
  stand on its own..."), which is origin/main at the time this file was written.

  At 5d52516 there is no lw-watchtower\bin\lwg-metrics.ps1 and no
  lw-watchtower\lib\metrics.ps1. Every case below therefore fails at the
  baseline, and the suite ABORTS at set-up with

      ABORTED: the copied tree has no bin\lwg-metrics.ps1 at <scratch>\plugin\bin\lwg-metrics.ps1

  which is exit 2 and zero cases run. That is the honest red for a command that
  does not exist: there is no state of the tree at 5d52516 in which any of these
  cases could pass, and none of them is a CONTROL that passes both sides.

  A green run of this file therefore establishes exactly one thing - that the
  indexer's arithmetic and attribution are what section A and section B say, and
  that the scoreboard refuses to invent the columns it has no source for. It
  establishes NOTHING about a hook, a meter, a landing, a verdict or a written
  file, because this slice contains none of them.

  ---------------------------------------------------------------------------
  HOW A CASE IS RUN, AND THE SANDBOX CONTRACT
  ---------------------------------------------------------------------------
  In a real child process, against a BYTE COPY of bin\ and lib\ under a scratch
  plugin root built at runtime from [IO.Path]::GetTempPath(), exactly as
  tests\toggle_behaviour.ps1 and tests\state_resolution.ps1 do:

      <scratch>\plugin\bin\lwg-metrics.ps1    copied from the repo
      <scratch>\plugin\lib\common.ps1         copied from the repo
      <scratch>\plugin\lib\metrics.ps1        copied from the repo
      <scratch>\plugin\config.json            copied from the repo
      <scratch>\home\projects\...             THE FIXTURE CORPUS, built per case
      <scratch>\work\example-repo             a scratch working directory

  Around every child, five environment variables are set or cleared and restored
  in a finally:

      USERPROFILE                    -> <scratch>\profile
      CLAUDE_CONFIG_DIR              -> <scratch>\home
      CLAUDE_PLUGIN_DATA             -> <scratch>\data
      CLAUDE_PLUGIN_ROOT             cleared
      CLAUDE_CODE_PLUGIN_CACHE_DIR   cleared

  CLAUDE_CONFIG_DIR IS THE WHOLE TEST SEAM, and there is deliberately no
  -ProjectsRoot parameter on the command to go with it. lib\common.ps1's
  Get-LwgClaudeHomeInfo already resolves the configuration root from
  CLAUDE_CONFIG_DIR before USERPROFILE, and the indexer composes
  <that root>\projects. Pointing the variable at a scratch tree is therefore the
  REAL resolution path with a different answer, not a test-only branch - so
  every case below drives the code an operator runs, and the command grows no
  surface that exists only for this file.

  NO REAL TRANSCRIPT, SESSION ID, PATH OR MODEL RESPONSE IS IN ANY FIXTURE.
  R10 requires it and tests\portability_scan.ps1 enforces the class. Every
  fixture below is hand-built from the FIELD NAMES this repo has verified on
  real files, with invented ids, an invented cwd of C:\work\example-repo and
  content blocks that are the literal string "<redacted>".

  ---------------------------------------------------------------------------
  EXIT CODES - a CI job reads these and nothing else
  ---------------------------------------------------------------------------
      0  every case passed
      1  at least one case FAILED
      2  the suite ABORTED - it could not set up, or a case could not be made
         conclusive, so nothing was established either way. Zero cases run is an
         abort, never an empty-set pass.
#>
[CmdletBinding()]
param(
    # The PLUGIN PAYLOAD root - lw-watchtower\ under this file's parent, not the
    # repository root. Neither .github\workflows\ci.yml nor tests\doc_claims.ps1's
    # sibling runner passes -Root, so this default is the only value it ever gets.
    [string]$Root
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Join-Path (Split-Path -Parent $PSScriptRoot) 'lw-watchtower' }

$script:Pass    = 0
$script:Results = New-Object System.Collections.ArrayList
$script:Aborted = ''

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

# ===========================================================================
# FIXTURES
#
# Every line below is a hand-built JSONL record in the shape this repository
# verified against real transcripts on 2026-09-06, with every identifying value
# invented. The field names are the real ones; the values are not.
# ===========================================================================

function ConvertTo-Line {
    <#
      One JSONL record. ConvertTo-Json -Compress on Windows PowerShell 5.1
      escapes < > ' and & into \u00xx, which is harmless inside a fixture the
      indexer reads back with ConvertFrom-Json - the round trip is exact - and
      is the reason the "<redacted>" content blocks below are still recognisable
      to the reader of this file and not to a naive string search of the fixture.
    #>
    param($Object)
    return ($Object | ConvertTo-Json -Depth 12 -Compress)
}

function New-AssistantLine {
    <#
      One `type:"assistant"` line carrying a usage block.

      -MessageId is the DEDUPE KEY. The CLI writes one API response as several
      assistant lines - one per content block - each repeating the identical
      usage under the same message.id, and summing per line overstates by
      roughly 2x. Measured on this machine's own corpus on 2026-09-06: 36,535
      assistant lines carrying usage resolve to 19,480 distinct message.id, and
      no id was ever seen carrying two DIFFERENT usage blocks.
    #>
    param(
        [string]$MessageId,
        [string]$Model = 'claude-opus-5',
        [long]$Input_ = 2,
        [long]$CacheRead = 0,
        [long]$CacheCreation = 0,
        [long]$Output = 0,
        [long]$Thinking = 0,
        [string]$Timestamp = '2026-09-05T10:00:00.000Z',
        [string]$SessionId,
        [string]$AgentId,
        [bool]$Sidechain = $false,
        [string]$Cwd = 'C:\work\example-repo',
        [int]$BlockIndex = 0
    )
    $usage = [ordered]@{
        input_tokens                = $Input_
        cache_creation_input_tokens = $CacheCreation
        cache_read_input_tokens     = $CacheRead
        output_tokens               = $Output
        service_tier                = 'standard'
    }
    if ($Thinking -gt 0) { $usage['output_tokens_details'] = [ordered]@{ thinking_tokens = $Thinking } }

    $rec = [ordered]@{
        parentUuid    = '00000000-0000-4000-8000-00000000000f'
        isSidechain   = $Sidechain
        message       = [ordered]@{
            model       = $Model
            id          = $MessageId
            type        = 'message'
            role        = 'assistant'
            content     = @([ordered]@{ type = 'text'; text = '<redacted>' })
            stop_reason = 'tool_use'
            usage       = $usage
        }
        apiBlockIndex = $BlockIndex
        requestId     = ('req_' + $MessageId)
        type          = 'assistant'
        uuid          = ('00000000-0000-4000-8000-' + ('{0:d12}' -f ($BlockIndex + 1)))
        timestamp     = $Timestamp
        userType      = 'external'
        entrypoint    = 'cli'
        cwd           = $Cwd
        sessionId     = $SessionId
        version       = '2.1.259'
        gitBranch     = 'main'
    }
    if ($AgentId) { $rec['agentId'] = $AgentId }
    return (ConvertTo-Line $rec)
}

function New-DispatchLines {
    <#
      The TWO lines one Agent dispatch occupies in a main-thread transcript, and
      the join between them.

        1. an `assistant` line whose message.content carries a
           `tool_use` block with name "Agent" and an `input` object
        2. a `user` line whose message.content carries a `tool_result` block
           with `tool_use_id` equal to that block's id, and whose
           `toolUseResult` object carries the status, the agentId and the
           resolvedModel

      VERIFIED ON THIS MACHINE 2026-09-06: the pairing key is
      message.content[].tool_use_id on a type:"user" line, and every one of the
      151 results the 153 Agent dispatches in the local corpus produced carried
      status "async_launched" - never "completed" and never "teammate_spawned".
      The other two statuses are
      documented in #165 and are not reachable from any file on this disk, which
      is why section B drives async_launched and the scoreboard reports the
      cross-check those other statuses would have supplied as NOT DETERMINED.

      -NoModel omits input.model, which is the "inherit the caller's tier" case
      and is how 39 of this machine's 243 subagent .meta.json files record a
      dispatch. The requested tier is then NOT DETERMINED, never "opus".
    #>
    param(
        [string]$ToolUseId,
        [string]$AgentId,
        [string]$SubagentType = 'general-purpose',
        [string]$RequestedModel = 'opus',
        [string]$ResolvedModel = 'claude-opus-5[1m]',
        [string]$Status = 'async_launched',
        [string]$SessionId,
        [switch]$NoModel,
        [string]$Timestamp = '2026-09-05T10:00:05.000Z'
    )

    $input_ = [ordered]@{
        subagent_type = $SubagentType
        description   = 'fixture dispatch'
        prompt        = '<redacted>'
    }
    if (-not $NoModel) { $input_['model'] = $RequestedModel }

    $a = [ordered]@{
        isSidechain = $false
        message     = [ordered]@{
            model   = 'claude-opus-5'
            id      = ('msg_tu_' + $ToolUseId)
            type    = 'message'
            role    = 'assistant'
            content = @([ordered]@{ type = 'tool_use'; id = $ToolUseId; name = 'Agent'; input = $input_ })
        }
        type        = 'assistant'
        uuid        = '00000000-0000-4000-8000-0000000000a1'
        timestamp   = $Timestamp
        cwd         = 'C:\work\example-repo'
        sessionId   = $SessionId
        gitBranch   = 'main'
    }

    $res = [ordered]@{
        isAsync           = $true
        status            = $Status
        agentId           = $AgentId
        description       = 'fixture dispatch'
        resolvedModel     = $ResolvedModel
        prompt            = '<redacted>'
        canReadOutputFile = $true
        outputFile        = 'C:\work\example-repo\out.txt'
    }

    $u = [ordered]@{
        isSidechain   = $false
        message       = [ordered]@{
            role    = 'user'
            content = @([ordered]@{ type = 'tool_result'; tool_use_id = $ToolUseId; content = '<redacted>' })
        }
        toolUseResult = $res
        type          = 'user'
        uuid          = '00000000-0000-4000-8000-0000000000a2'
        timestamp     = $Timestamp
        cwd           = 'C:\work\example-repo'
        sessionId     = $SessionId
        session_id    = $SessionId
        gitBranch     = 'main'
    }

    return @((ConvertTo-Line $a), (ConvertTo-Line $u))
}

function Write-Jsonl {
    param([string]$Path, [string[]]$Lines)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
    # UTF-8 WITHOUT BOM, and never `>` or Out-File: Windows PowerShell 5.1 writes
    # UTF-16LE through both, and the indexer reads these back as UTF-8. R10.
    [IO.File]::WriteAllText($Path, (($Lines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
}

function New-Sandbox {
    <#
      A throwaway plugin root plus a throwaway CLAUDE_CONFIG_DIR. The code under
      test is copied ONCE per run - it does not change between cases - and each
      case builds its own corpus under <scratch>\home\projects.
    #>
    # NOT $root: PowerShell variable names are case-insensitive, so a local
    # $root would shadow this script's $Root parameter.
    $base = Join-Path ([IO.Path]::GetTempPath()) ('lwg-metrics-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
    $sand = @{
        root    = $base
        plugin  = (Join-Path $base 'plugin')
        home    = (Join-Path $base 'home')
        data    = (Join-Path $base 'data')
        profile = (Join-Path $base 'profile')
        work    = (Join-Path $base 'work')
    }
    foreach ($d in @($sand.root, $sand.plugin, $sand.home, $sand.data, $sand.profile, $sand.work)) {
        [void](New-Item -ItemType Directory -Path $d -Force)
    }
    foreach ($sub in @('bin', 'lib')) {
        $src = Join-Path $Root $sub
        if (Test-Path -LiteralPath $src) {
            Copy-Item -LiteralPath $src -Destination (Join-Path $sand.plugin $sub) -Recurse -Force
        }
    }
    $cfg = Join-Path $Root 'config.json'
    if (Test-Path -LiteralPath $cfg) { Copy-Item -LiteralPath $cfg -Destination (Join-Path $sand.plugin 'config.json') -Force }

    # DELIBERATELY NOT CREATED. Section S8 points CLAUDE_PLUGIN_DATA here and
    # then asserts it is still not there afterwards.
    $sand.nostate  = Join-Path $base 'never-created'
    $sand.metrics  = Join-Path $sand.plugin 'bin\lwg-metrics.ps1'
    $sand.lib      = Join-Path $sand.plugin 'lib\metrics.ps1'
    $sand.projects = Join-Path $sand.home 'projects'
    [void](New-Item -ItemType Directory -Path $sand.projects -Force)

    # THE RED-FIRST ABORT. At the baseline 5d52516 neither file exists, and the
    # suite says so in the one place a reader will look rather than failing all
    # 23 cases with 23 copies of the same message.
    if (-not (Test-Path -LiteralPath $sand.metrics -PathType Leaf)) {
        throw "the copied tree has no bin\lwg-metrics.ps1 at $($sand.metrics)"
    }
    if (-not (Test-Path -LiteralPath $sand.lib -PathType Leaf)) {
        throw "the copied tree has no lib\metrics.ps1 at $($sand.lib)"
    }
    return $sand
}

function Clear-Corpus {
    param([hashtable]$Sand)
    if (Test-Path -LiteralPath $Sand.projects) {
        Remove-Item -LiteralPath $Sand.projects -Recurse -Force -ErrorAction SilentlyContinue
    }
    [void](New-Item -ItemType Directory -Path $Sand.projects -Force)
}

function Push-ChildEnv {
    <#
      Returns the previous values so the caller can restore them in a finally.
      Same shape, same reason and same wording as tests\toggle_behaviour.ps1's.

      CLAUDE_CONFIG_DIR is NOT cleared here, unlike in that suite - it is the
      seam this whole file drives. Pointing it at the sandbox is what makes the
      indexer look at <scratch>\home\projects instead of the real machine's.

      -NoHome clears BOTH CLAUDE_CONFIG_DIR and USERPROFILE, which is the state
      in which the configuration root cannot be resolved at all. Section S uses
      it to prove the command exits 3 rather than reporting an empty corpus as a
      measurement.

      -NoState points CLAUDE_PLUGIN_DATA at a path that DOES NOT EXIST, which is
      the only environment in which "this command writes nothing" is testable.
      Every other case here hands the child an existing scratch data directory,
      so none of them can see a create. lib\common.ps1's Get-LwgStateDir CREATES
      the directory it resolves - deliberately, and outside its own memoisation,
      so that a state dir deleted mid-session comes back for the hooks that write
      to it - and a read-only report that reached for it would leave an empty
      directory on the operator's disk under the unsuffixed fallback name, which
      is precisely the shape bin\lwg-doctor.ps1's state-dir check reports as a
      FAIL. Section S8 is the case that holds the command to Get-LwgStateDirInfo.
    #>
    param([hashtable]$Sand, [switch]$NoHome, [switch]$NoState)
    $prev = @{
        up  = $env:USERPROFILE
        dat = $env:CLAUDE_PLUGIN_DATA
        rt  = $env:CLAUDE_PLUGIN_ROOT
        cd_ = $env:CLAUDE_CODE_PLUGIN_CACHE_DIR
        cfg = $env:CLAUDE_CONFIG_DIR
    }
    $env:USERPROFILE                  = $(if ($NoHome) { $null } else { $Sand.profile })
    $env:CLAUDE_CONFIG_DIR            = $(if ($NoHome) { $null } else { $Sand.home })
    $env:CLAUDE_PLUGIN_DATA           = $(if ($NoState) { $Sand.nostate } else { $Sand.data })
    $env:CLAUDE_PLUGIN_ROOT           = $null
    $env:CLAUDE_CODE_PLUGIN_CACHE_DIR = $null
    return $prev
}

function Pop-ChildEnv {
    param([hashtable]$Prev)
    $env:USERPROFILE                  = $Prev.up
    $env:CLAUDE_PLUGIN_DATA           = $Prev.dat
    $env:CLAUDE_PLUGIN_ROOT           = $Prev.rt
    $env:CLAUDE_CODE_PLUGIN_CACHE_DIR = $Prev.cd_
    $env:CLAUDE_CONFIG_DIR            = $Prev.cfg
}

function Invoke-Child {
    <#
      Run one script in a real child process and return
      @{ code; out; err } - a hashtable, so PowerShell does not enumerate it
      away across the function boundary.

      A .cmd file rather than one long `cmd /c` string, for the reason
      tests\stop_behaviour.ps1:199-203 gives: cmd's rule about stripping the
      first and last quote of a /c argument makes a quoted path in such a string
      unreliable, and a harness that breaks on a temp path with a space in it is
      a harness that stops being run.
    #>
    param(
        [hashtable]$Sand,
        [string]$ScriptPath,
        [string]$ScriptArgs = '',
        [string]$Tag,
        [string]$WorkDir,
        [switch]$NoHome,
        [switch]$NoState
    )
    if ([string]::IsNullOrWhiteSpace($WorkDir)) { $WorkDir = $Sand.work }

    $of  = Join-Path $Sand.root "$Tag.out"
    $ef  = Join-Path $Sand.root "$Tag.err"
    $bat = Join-Path $Sand.root "$Tag.cmd"

    $cmd = ('powershell -NoProfile -ExecutionPolicy Bypass -File "{0}" {1} 1>"{2}" 2>"{3}"' -f $ScriptPath, $ScriptArgs, $of, $ef)
    [IO.File]::WriteAllLines($bat, @('@echo off', ('cd /d "{0}"' -f $WorkDir), $cmd, 'exit /b %ERRORLEVEL%'), [Text.ASCIIEncoding]::new())

    $prev = Push-ChildEnv -Sand $Sand -NoHome:$NoHome -NoState:$NoState
    try {
        & $env:ComSpec /c $bat | Out-Null
        $code = $LASTEXITCODE
    } finally {
        Pop-ChildEnv -Prev $prev
    }

    $out = ''; $err = ''
    try { $out = [IO.File]::ReadAllText($of) } catch { }
    try { $err = [IO.File]::ReadAllText($ef) } catch { }
    return @{ code = $code; out = $out; err = $err; tag = $Tag }
}

function New-Probe {
    <#
      A one-shot script that dot-sources the COPIED lib\common.ps1 and
      lib\metrics.ps1 and prints ONE compressed JSON object. Written into the
      sandbox and run through Invoke-Child, so a pure function is exercised in a
      fresh process with the case's environment - never in this one, where
      lib\common.ps1's memoised resolvers would carry an answer from a previous
      case. The pattern and the reason are tests\state_resolution.ps1's.
    #>
    param([hashtable]$Sand, [string]$Name, [string]$Body)

    $path = Join-Path $Sand.root "$Name.ps1"
    $libDir = (Join-Path $Sand.plugin 'lib') -replace "'", "''"
    $text = @"
`$ErrorActionPreference = 'Continue'
`$o = [ordered]@{}
try {
    . (Join-Path '$libDir' 'common.ps1')
    . (Join-Path '$libDir' 'metrics.ps1')
$Body
} catch {
    `$o['error'] = `$_.Exception.Message
}
[Console]::Out.Write((`$o | ConvertTo-Json -Depth 8 -Compress))
"@
    [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
    return $path
}

function Read-ProbeJson {
    param([hashtable]$Res, [string]$What)
    $t = [string]$Res.out
    if ([string]::IsNullOrWhiteSpace($t)) {
        return @{ ok = $false; why = "$What printed nothing (exit $($Res.code)). stderr: $($Res.err)" }
    }
    try { return @{ ok = $true; obj = ($t | ConvertFrom-Json) } }
    catch { return @{ ok = $false; why = "$What printed something that is not JSON: $t" } }
}

# ===========================================================================
# RUN
# ===========================================================================

$sw   = [Diagnostics.Stopwatch]::StartNew()
$sand = $null

try {
    $sand = New-Sandbox

    # A scratch working directory that is NOT a git repository. Every case runs
    # the command from here, so the "current project" resolution has nothing to
    # find and the command reports across the whole corpus - which is what makes
    # a fixture corpus readable without building a repository around it.
    $work = Join-Path $sand.work 'example-repo'
    [void](New-Item -ItemType Directory -Path $work -Force)

    $slug    = 'C--work-example-repo'
    $sessA   = '11111111-1111-4111-8111-111111111111'
    $sessB   = '22222222-2222-4222-8222-222222222222'

    # =======================================================================
    # SECTION A - #165 A1: usage is summed ONCE per message.id
    #
    # The single measurement that decides whether any number this module ever
    # prints is true. A naive per-line sum overstates by roughly 2x.
    # =======================================================================

    Clear-Corpus -Sand $sand

    $mainA = Join-Path $sand.projects "$slug\$sessA.jsonl"
    $linesA = @()
    # THE DUPLICATE SHAPE. Three assistant lines, one message.id, byte-identical
    # usage - the thinking block, the tool_use block and the text block of a
    # single API response.
    foreach ($i in 0..2) {
        $linesA += New-AssistantLine -MessageId 'msg_dup_one' -Model 'claude-opus-5' `
            -Input_ 2 -CacheCreation 26477 -CacheRead 29810 -Output 389 -Thinking 280 `
            -SessionId $sessA -BlockIndex $i -Timestamp '2026-09-05T10:00:01.000Z'
    }
    # A SECOND, DISTINCT REQUEST.
    $linesA += New-AssistantLine -MessageId 'msg_two' -Model 'claude-opus-5' `
        -Input_ 5 -CacheCreation 100 -CacheRead 200 -Output 11 `
        -SessionId $sessA -BlockIndex 0 -Timestamp '2026-09-05T10:00:02.000Z'
    # A <synthetic> LINE. It carries a usage block and must contribute nothing:
    # 124 of them are in this machine's own corpus.
    $linesA += New-AssistantLine -MessageId 'msg_synth' -Model '<synthetic>' `
        -Input_ 999999 -CacheCreation 999999 -CacheRead 999999 -Output 999999 `
        -SessionId $sessA -BlockIndex 0 -Timestamp '2026-09-05T10:00:03.000Z'
    # A LINE THAT IS NOT AN ASSISTANT TURN AT ALL.
    $linesA += (ConvertTo-Line ([ordered]@{ type = 'user'; sessionId = $sessA; message = [ordered]@{ role = 'user'; content = '<redacted>' } }))
    Write-Jsonl -Path $mainA -Lines $linesA

    $probeA = New-Probe -Sand $sand -Name 'probeA' -Body @"
    `$s = Read-LwgMetricsTranscript -Path '$($mainA -replace "'","''")'
    `$o['requests']   = `$s.requests
    `$o['usage_lines']= `$s.usage_lines
    `$o['duplicates'] = `$s.duplicates
    `$o['synthetic']  = `$s.synthetic
    `$o['input']      = `$s.totals.input
    `$o['cache_read'] = `$s.totals.cache_read
    `$o['cache_creation'] = `$s.totals.cache_creation
    `$o['output']     = `$s.totals.output
    `$o['thinking']   = `$s.totals.thinking
    `$o['composite']  = `$s.totals.composite
    `$o['models']     = @(`$s.models.Keys | Sort-Object)
"@
    $rA = Invoke-Child -Sand $sand -ScriptPath $probeA -Tag 'a1' -WorkDir $work
    $jA = Read-ProbeJson -Res $rA -What 'the A1 probe'

    if (-not $jA.ok) {
        Add-Result 'A1 the indexer reads a transcript at all' $false $jA.why
    } else {
        $o = $jA.obj
        Add-Result 'A1 usage is summed ONCE per message.id - three duplicate lines count as one request' `
            ($o.requests -eq 2 -and $o.usage_lines -eq 4 -and $o.duplicates -eq 2) `
            ("expected requests 2, usage_lines 4, duplicates 2; got requests $($o.requests), usage_lines $($o.usage_lines), duplicates $($o.duplicates). " +
             "A naive per-line sum would report 4 requests and roughly double every category.")

        Add-Result 'A1 the four usage categories are deduplicated and kept SEPARATE' `
            ($o.input -eq 7 -and $o.cache_creation -eq 26577 -and $o.cache_read -eq 30010 -and $o.output -eq 400) `
            ("expected input 7 (2+5), cache_creation 26577 (26477+100), cache_read 30010 (29810+200), output 400 (389+11); " +
             "got input $($o.input), cache_creation $($o.cache_creation), cache_read $($o.cache_read), output $($o.output)")

        Add-Result 'A1 composite is the sum of the four, and thinking is NOT added to it' `
            ($o.composite -eq 56994 -and $o.thinking -eq 280) `
            ("expected composite 56994 (7+30010+26577+400) and thinking 280 reported beside it, not inside it; " +
             "got composite $($o.composite), thinking $($o.thinking). thinking_tokens is a SUBSET of output_tokens - " +
             "adding it to the composite double-counts every reasoning token.")

        Add-Result 'A1 a <synthetic> line contributes nothing and is counted as excluded' `
            ($o.synthetic -eq 1 -and @($o.models) -notcontains '<synthetic>') `
            ("expected synthetic 1 and no <synthetic> entry in the per-model table; got synthetic $($o.synthetic), models $(@($o.models) -join ', '). " +
             "The fixture's synthetic line carries 999999 in every category, so a leak is unmistakable.")
    }

    # --- A1, second property: 64-bit arithmetic ----------------------------
    # This machine's own corpus carries 4,479,419,249 cache-read tokens across
    # 268 files, which is beyond [int]::MaxValue (2,147,483,647). An accumulator
    # typed [int] does not merely round here - it throws or wraps, and the
    # scoreboard is then silently wrong in the one direction nobody checks.
    $mainOv = Join-Path $sand.projects "$slug\$sessB.jsonl"
    Write-Jsonl -Path $mainOv -Lines @(
        (New-AssistantLine -MessageId 'msg_big_1' -CacheRead 2000000000 -Output 1 -SessionId $sessB -Timestamp '2026-09-05T11:00:00.000Z'),
        (New-AssistantLine -MessageId 'msg_big_2' -CacheRead 2000000000 -Output 1 -SessionId $sessB -Timestamp '2026-09-05T11:00:01.000Z')
    )
    $probeOv = New-Probe -Sand $sand -Name 'probeOv' -Body @"
    `$s = Read-LwgMetricsTranscript -Path '$($mainOv -replace "'","''")'
    `$o['cache_read'] = `$s.totals.cache_read
    `$o['composite']  = `$s.totals.composite
    `$o['type']       = `$s.totals.cache_read.GetType().Name
"@
    $rOv = Invoke-Child -Sand $sand -ScriptPath $probeOv -Tag 'a2' -WorkDir $work
    $jOv = Read-ProbeJson -Res $rOv -What 'the 64-bit probe'
    if (-not $jOv.ok) {
        Add-Result 'A1 token totals are 64-bit' $false $jOv.why
    } else {
        Add-Result 'A1 token totals are 64-bit - two 2,000,000,000 cache reads do not overflow' `
            ([long]$jOv.obj.cache_read -eq 4000000000 -and $jOv.obj.type -eq 'Int64') `
            ("expected cache_read 4000000000 held as Int64; got $($jOv.obj.cache_read) as $($jOv.obj.type). " +
             "[int]::MaxValue is 2147483647 and this machine's real corpus is already past it.")
    }

    # --- A1, third property: subagents\workflows\wf_*\ is recursed ---------
    Clear-Corpus -Sand $sand
    Write-Jsonl -Path (Join-Path $sand.projects "$slug\$sessA.jsonl") -Lines @(
        (New-AssistantLine -MessageId 'msg_main' -Output 10 -SessionId $sessA)
    )
    Write-Jsonl -Path (Join-Path $sand.projects "$slug\$sessA\subagents\agent-a1111111111111111.jsonl") -Lines @(
        (New-AssistantLine -MessageId 'msg_sub' -Output 20 -SessionId $sessA -AgentId 'a1111111111111111' -Sidechain $true)
    )
    # ONE LEVEL DEEPER. A workflow child lives at
    # subagents\workflows\wf_<id>\agent-*.jsonl; nine such directories are in
    # this machine's corpus. A non-recursive enumeration silently drops them,
    # and the delegation figure - the one the owner actually asked for - comes
    # out too low with nothing to say it did.
    Write-Jsonl -Path (Join-Path $sand.projects "$slug\$sessA\subagents\workflows\wf_abc123\agent-a2222222222222222.jsonl") -Lines @(
        (New-AssistantLine -MessageId 'msg_wf' -Output 40 -SessionId $sessA -AgentId 'a2222222222222222' -Sidechain $true)
    )

    $rRec = Invoke-Child -Sand $sand -ScriptPath $sand.metrics -ScriptArgs '-All -Json' -Tag 'a3' -WorkDir $work
    $jRec = Read-ProbeJson -Res $rRec -What 'the recursion run (-All -Json)'
    if (-not $jRec.ok) {
        Add-Result 'A1 subagents\workflows\wf_* is recursed' $false $jRec.why
    } else {
        $idx = $jRec.obj.index
        Add-Result 'A1 subagents\workflows\wf_* is recursed - the nested child is indexed, not dropped' `
            ($idx.subagent_transcripts -eq 2 -and $idx.session_transcripts -eq 1 -and [long]$jRec.obj.totals.output -eq 70) `
            ("expected 1 session transcript, 2 subagent transcripts (one flat, one under subagents\workflows\wf_abc123) and output 70 (10+20+40); " +
             "got session_transcripts $($idx.session_transcripts), subagent_transcripts $($idx.subagent_transcripts), output $($jRec.obj.totals.output)")
    }

    # =======================================================================
    # SECTION B - #165 A2: dispatch attribution
    #
    # The REQUESTED tier and the RESOLVED model are two different facts and the
    # scoreboard must never collapse them: they disagree when a tier-up rerun or
    # a settings default intervenes, and that disagreement is the whole of R4's
    # tier-up measurement.
    # =======================================================================

    Clear-Corpus -Sand $sand

    $mainB = Join-Path $sand.projects "$slug\$sessA.jsonl"
    $linesB = @()
    $linesB += New-AssistantLine -MessageId 'msg_b_main' -Model 'claude-opus-5' -Output 100 -SessionId $sessA
    # 1. asked for opus, resolved to claude-opus-5[1m] - the [1m] tag is on the
    #    RESOLVED model and is not on the model name the subagent's own lines
    #    carry. Comparing the two without stripping it reports every dispatch as
    #    a mismatch.
    $linesB += New-DispatchLines -ToolUseId 'toolu_b1' -AgentId 'a1111111111111111' -RequestedModel 'opus' -ResolvedModel 'claude-opus-5[1m]' -SessionId $sessA
    # 2. asked for haiku, resolved to opus - a real disagreement, and it must be
    #    reported as one.
    $linesB += New-DispatchLines -ToolUseId 'toolu_b2' -AgentId 'a3333333333333333' -RequestedModel 'haiku' -ResolvedModel 'claude-opus-5' -SessionId $sessA
    # 3. no input.model at all - inherit. 39 of this machine's 243 dispatches
    #    look like this, and the requested tier is NOT DETERMINED, never 'opus'.
    $linesB += New-DispatchLines -ToolUseId 'toolu_b3' -AgentId 'a4444444444444444' -NoModel -ResolvedModel 'claude-sonnet-5' -SessionId $sessA
    Write-Jsonl -Path $mainB -Lines $linesB

    Write-Jsonl -Path (Join-Path $sand.projects "$slug\$sessA\subagents\agent-a1111111111111111.jsonl") -Lines @(
        (New-AssistantLine -MessageId 'msg_b_s1' -Model 'claude-opus-5' -Output 200 -SessionId $sessA -AgentId 'a1111111111111111' -Sidechain $true)
    )
    Write-Jsonl -Path (Join-Path $sand.projects "$slug\$sessA\subagents\agent-a3333333333333333.jsonl") -Lines @(
        (New-AssistantLine -MessageId 'msg_b_s2' -Model 'claude-opus-5' -Output 300 -SessionId $sessA -AgentId 'a3333333333333333' -Sidechain $true)
    )
    Write-Jsonl -Path (Join-Path $sand.projects "$slug\$sessA\subagents\agent-a4444444444444444.jsonl") -Lines @(
        (New-AssistantLine -MessageId 'msg_b_s3' -Model 'claude-sonnet-5' -Output 400 -SessionId $sessA -AgentId 'a4444444444444444' -Sidechain $true)
    )

    $probeB = New-Probe -Sand $sand -Name 'probeB' -Body @"
    `$d = @(Get-LwgMetricsDispatch -Path '$($mainB -replace "'","''")')
    `$o['count'] = `$d.Count
    `$o['rows']  = @(`$d | ForEach-Object {
        [ordered]@{
            tool_use_id     = `$_.tool_use_id
            agent_id        = `$_.agent_id
            status          = `$_.status
            requested_model = `$_.requested_model
            resolved_model  = `$_.resolved_model
            resolved_base   = `$_.resolved_base
            subagent_type   = `$_.subagent_type
        }
    })
    `$o['base_1m']  = (Get-LwgMetricsModelBase -Model 'claude-opus-5[1m]')
    `$o['base_pln'] = (Get-LwgMetricsModelBase -Model 'claude-opus-5')
"@
    $rB = Invoke-Child -Sand $sand -ScriptPath $probeB -Tag 'b1' -WorkDir $work
    $jB = Read-ProbeJson -Res $rB -What 'the A2 probe'

    if (-not $jB.ok) {
        Add-Result 'A2 dispatches are read out of a main transcript' $false $jB.why
    } else {
        $rows = @($jB.obj.rows)
        Add-Result 'A2 every Agent tool_use is joined to its result on message.content[].tool_use_id' `
            ($jB.obj.count -eq 3 -and ($rows | Where-Object { $_.agent_id }).Count -eq 3 -and ($rows | Where-Object { $_.status -eq 'async_launched' }).Count -eq 3) `
            ("expected 3 dispatches, each carrying the agentId and the status from its paired type:'user' line; got count $($jB.obj.count), " +
             "agent ids $(@($rows | ForEach-Object { $_.agent_id }) -join ', '), statuses $(@($rows | ForEach-Object { $_.status }) -join ', ')")

        $r1 = $rows | Where-Object { $_.tool_use_id -eq 'toolu_b1' } | Select-Object -First 1
        Add-Result 'A2 the [1m] tag is stripped for comparison and kept in the reported resolved model' `
            ($null -ne $r1 -and $r1.requested_model -eq 'opus' -and $r1.resolved_model -eq 'claude-opus-5[1m]' -and $r1.resolved_base -eq 'claude-opus-5') `
            ("expected requested 'opus', resolved 'claude-opus-5[1m]' reported verbatim, resolved_base 'claude-opus-5' for the comparison; " +
             "got requested '$($r1.requested_model)', resolved '$($r1.resolved_model)', base '$($r1.resolved_base)'. " +
             "The subagent's own lines say 'claude-opus-5', so an unstripped comparison calls every dispatch a mismatch.")

        Add-Result 'A2 Get-LwgMetricsModelBase strips a bracket tag and leaves an untagged id alone' `
            ($jB.obj.base_1m -eq 'claude-opus-5' -and $jB.obj.base_pln -eq 'claude-opus-5') `
            ("expected 'claude-opus-5' from both 'claude-opus-5[1m]' and 'claude-opus-5'; got '$($jB.obj.base_1m)' and '$($jB.obj.base_pln)'. " +
             "'[' is also a wildcard character in -like, which is the second reason this is a function and not an inline comparison.")

        $r3 = $rows | Where-Object { $_.tool_use_id -eq 'toolu_b3' } | Select-Object -First 1
        Add-Result 'A2 a dispatch with no input.model has NO requested tier, and it is not defaulted to one' `
            ($null -ne $r3 -and [string]::IsNullOrEmpty([string]$r3.requested_model) -and $r3.resolved_base -eq 'claude-sonnet-5') `
            ("expected an absent requested tier - the inherit case, 39 of this machine's 243 dispatches - and resolved_base 'claude-sonnet-5'; " +
             "got requested '$($r3.requested_model)', base '$($r3.resolved_base)'. Reporting 'opus' here would invent a routing decision nobody made.")
    }

    # --- A2, the report side: requested vs resolved is not collapsed -------
    $rB2 = Invoke-Child -Sand $sand -ScriptPath $sand.metrics -ScriptArgs '-All -Json' -Tag 'b2' -WorkDir $work
    $jB2 = Read-ProbeJson -Res $rB2 -What 'the attribution run (-All -Json)'
    if (-not $jB2.ok) {
        Add-Result 'A2 the scoreboard reports the dispatch/transcript join' $false $jB2.why
    } else {
        $orc = $jB2.obj.orchestration
        Add-Result 'A2 the scoreboard reports dispatches and attributed transcripts as TWO counts' `
            ($orc.dispatches -eq 3 -and $orc.attributed -eq 3 -and $orc.unattributed_transcripts -eq 0) `
            ("expected dispatches 3, attributed 3, unattributed 0; got dispatches $($orc.dispatches), attributed $($orc.attributed), unattributed $($orc.unattributed_transcripts). " +
             "#165 R4 requires the two counts shown separately when they differ - on this machine's real corpus they do: 131 Agent tool_use against 243 subagent transcripts.")

        Add-Result 'A2 a requested tier that did not survive resolution is reported as a disagreement' `
            ($orc.tier_disagreements -eq 1) `
            ("expected exactly 1 disagreement - the fixture asks for haiku and resolves to claude-opus-5 - and NOT one for the [1m] dispatch; " +
             "got $($orc.tier_disagreements)")
    }

    # =======================================================================
    # SECTION S - the slice's own contract
    #
    # Not one of #165's lettered criteria. These are the properties the OWNER's
    # 2026-09-06 ruling attached to this slice: print NOT DETERMINED in every
    # column with no source yet, and do not report a number you could not
    # measure.
    # =======================================================================

    # --- S1: every unsourced column says so, and none of them is a zero ----
    $rS1 = Invoke-Child -Sand $sand -ScriptPath $sand.metrics -ScriptArgs '-All' -Tag 's1' -WorkDir $work
    $txt = [string]$rS1.out

    # The columns this slice has no source for, and the requirement each one is
    # waiting on. Every one of them must appear, and every one must be followed
    # by NOT DETERMINED on the same line.
    $undetermined = @(
        @{ label = 'per-dispatch token cost'; why = 'R1/#166' },
        @{ label = 'usage meter';             why = 'R3' },
        @{ label = 'tokens per percent';      why = 'R3' },
        @{ label = 'landings';                why = 'R6' },
        @{ label = 'tokens per landing';      why = 'R6' },
        @{ label = 'LCAP rounds to clean';    why = 'R5' },
        @{ label = 'gate-2 leak rate';        why = 'R5' },
        @{ label = 'post-merge defects';      why = 'R5.6' },
        @{ label = 'VERDICT';                 why = 'R8' }
    )
    $missing = @()
    foreach ($u in $undetermined) {
        $pat = '(?m)^.*' + [regex]::Escape($u.label) + '.*NOT DETERMINED.*$'
        if ($txt -notmatch $pat) { $missing += $u.label }
    }
    Add-Result 'S1 every column with no source in this slice prints NOT DETERMINED on its own line' `
        ($missing.Count -eq 0 -and $rS1.code -eq 0) `
        ("exit $($rS1.code); these labels did not appear with NOT DETERMINED beside them: $(if ($missing.Count) { $missing -join ', ' } else { 'none' }). " +
         "A scoreboard that invents a number is worse than one that says it cannot tell.")

    Add-Result 'S1 no unsourced figure is rendered as a zero, a dash or a blank' `
        ($txt -notmatch '(?mi)^\s*(VERDICT|usage meter|tokens per percent|landings)\b.*\b0(\s|$)' -and $txt -notmatch 'NOT DETERMINED\s*\(\s*0') `
        ("the report printed a 0 against a column it has no source for. #165's own rule, inherited from the deleted sitrep command and " +
         "restated by #311 as the plugin's standing rule: unknown is never reported as fine. Output was:`n$txt")

    # --- S2: the sections R9.2 names are all present, empty or not ---------
    $sections = @('INDEX', 'DELEGATION', 'WORK SPLIT', 'BY MODEL', 'COHORT', 'ORCHESTRATION', 'QUALITY', 'BUCKET', 'VERDICT', 'COULD NOT DETERMINE')
    $absent = @($sections | Where-Object { $txt -notmatch ('(?m)^' + [regex]::Escape($_)) })
    Add-Result 'S2 every section R9.2 names is rendered, including the ones this slice leaves empty' `
        ($absent.Count -eq 0) `
        ("missing section heading(s): $($absent -join ', '). commands\metrics.md tells the model to print the output verbatim, " +
         "every section including empty ones - a section that is simply absent reads as a section that had nothing wrong with it.")

    # --- S3: masking. No operator path reaches stdout ----------------------
    # The transcript directory names are the cwd with its separators replaced,
    # so they carry the operator's account name. This is the single highest
    # masking risk in the whole module: tests\portability_scan.ps1 guards the
    # PAYLOAD, and nothing but this case guards what the payload PRINTS.
    Add-Result 'S3 the report prints no filesystem path from the corpus it read' `
        ($txt -notmatch '(?i)[A-Z]:\\\\?[Uu]sers\\' -and $txt -notmatch [regex]::Escape($sand.projects) -and $txt -notmatch [regex]::Escape($slug)) `
        ("the report leaked a path or a project-slug directory name. Those directory names are the cwd with separators replaced, " +
         "so they carry the operator's account name into anything the output is pasted into. Output was:`n$txt")

    Add-Result 'S3 the projects root is named by the VARIABLE that resolved it, not by its value' `
        ($txt -match '(?m)projects root.*CLAUDE_CONFIG_DIR') `
        ("expected the INDEX block to name the root as `$env:CLAUDE_CONFIG_DIR\projects with its source, so the operator can tell WHICH tree was read " +
         "without the path itself being in the output. Output was:`n$txt")

    # --- S4: it exits 3 rather than reporting an empty corpus --------------
    $rS4 = Invoke-Child -Sand $sand -ScriptPath $sand.metrics -ScriptArgs '-All' -Tag 's4' -WorkDir $work -NoHome
    Add-Result 'S4 with no configuration root at all the command exits 3 and does not print a report' `
        ($rS4.code -eq 3 -and [string]$rS4.out -notmatch '(?m)^COHORT') `
        ("expected exit 3 - the lwg-status convention this repo uses for `"could not produce a report`" - and no scoreboard; " +
         "got exit $($rS4.code). Output was:`n$($rS4.out)")

    # --- S5: an empty but resolvable corpus is zero sessions, not exit 3 ---
    Clear-Corpus -Sand $sand
    $rS5 = Invoke-Child -Sand $sand -ScriptPath $sand.metrics -ScriptArgs '-All' -Tag 's5' -WorkDir $work
    Add-Result 'S5 a resolvable but EMPTY corpus is reported as zero sessions, not as a failure to look' `
        ($rS5.code -eq 0 -and [string]$rS5.out -match '(?m)^COULD NOT DETERMINE') `
        ("expected exit 0 with the report rendered and every figure NOT DETERMINED or 0-of-nothing; got exit $($rS5.code). " +
         "`"I looked and there was nothing`" and `"I could not look`" are different statements and this command must not collapse them. " +
         "Output was:`n$($rS5.out)")

    # --- S6: cohort assignment is per session, and a mixed session says so --
    $probeC = New-Probe -Sand $sand -Name 'probeC' -Body @"
    `$a = Get-LwgMetricsCohort -Models @{ 'claude-opus-5' = 7; 'claude-fable-5-1' = 3 }
    `$b = Get-LwgMetricsCohort -Models @{ 'claude-opus-5' = 5; 'claude-fable-5-1' = 5 }
    `$c = Get-LwgMetricsCohort -Models @{}
    `$o['a'] = `$a.cohort; `$o['a_share'] = [math]::Round(`$a.share, 3)
    `$o['b'] = `$b.cohort
    `$o['c'] = `$c.cohort
"@
    $rC = Invoke-Child -Sand $sand -ScriptPath $probeC -Tag 's6' -WorkDir $work
    $jC = Read-ProbeJson -Res $rC -What 'the cohort probe'
    if (-not $jC.ok) {
        Add-Result 'S6 cohort assignment' $false $jC.why
    } else {
        Add-Result 'S6 a session is assigned to the cohort its main thread dominated, and a 50/50 session is `mixed`' `
            ($jC.obj.a -eq 'claude-opus-5' -and $jC.obj.a_share -eq 0.7 -and $jC.obj.b -eq 'mixed' -and $jC.obj.c -eq 'unknown') `
            ("expected 'claude-opus-5' at share 0.7, 'mixed' below the 60 % floor #165 R6 sets, and 'unknown' for a session with no assistant line at all; " +
             "got '$($jC.obj.a)' at $($jC.obj.a_share), '$($jC.obj.b)', '$($jC.obj.c)'")
    }

    # --- S7: delegation is answered, because it is the question -----------
    # "Whether delegation is happening at all" is the measurement the whole
    # responsiveness design assumes and nothing has ever checked. A session that
    # dispatched nothing must be counted and named, not averaged away.
    Clear-Corpus -Sand $sand
    Write-Jsonl -Path (Join-Path $sand.projects "$slug\$sessA.jsonl") -Lines (
        @(New-AssistantLine -MessageId 'msg_s7_main' -Output 100 -SessionId $sessA) +
        (New-DispatchLines -ToolUseId 'toolu_s7' -AgentId 'a5555555555555555' -SessionId $sessA)
    )
    Write-Jsonl -Path (Join-Path $sand.projects "$slug\$sessA\subagents\agent-a5555555555555555.jsonl") -Lines @(
        (New-AssistantLine -MessageId 'msg_s7_sub' -Output 300 -SessionId $sessA -AgentId 'a5555555555555555' -Sidechain $true)
    )
    # A SECOND SESSION THAT DELEGATED NOTHING.
    Write-Jsonl -Path (Join-Path $sand.projects "$slug\$sessB.jsonl") -Lines @(
        (New-AssistantLine -MessageId 'msg_s7_solo' -Output 50 -SessionId $sessB -Timestamp '2026-09-05T12:00:00.000Z')
    )

    $rS7 = Invoke-Child -Sand $sand -ScriptPath $sand.metrics -ScriptArgs '-All -Json' -Tag 's7' -WorkDir $work
    $jS7 = Read-ProbeJson -Res $rS7 -What 'the delegation run (-All -Json)'
    if (-not $jS7.ok) {
        Add-Result 'S7 delegation is measured' $false $jS7.why
    } else {
        $d = $jS7.obj.delegation
        Add-Result 'S7 sessions that delegated NOTHING are counted separately, not averaged away' `
            ($d.sessions -eq 2 -and $d.sessions_with_dispatch -eq 1 -and $d.sessions_without_dispatch -eq 1) `
            ("expected 2 sessions, 1 with a dispatch and 1 without; got $($d.sessions), $($d.sessions_with_dispatch), $($d.sessions_without_dispatch). " +
             "`"Is delegation happening at all`" is the measurement the responsiveness design assumes and nothing has ever checked.")

        $ws = $jS7.obj.work_split
        Add-Result 'S7 the main-thread / subagent split is reported on output tokens as well as the composite' `
            ([long]$ws.main.output -eq 150 -and [long]$ws.subagent.output -eq 300 -and $null -ne $ws.subagent_output_share) `
            ("expected main output 150 (100+50) and subagent output 300, with a subagent share reported; " +
             "got main $($ws.main.output), subagent $($ws.subagent.output), share $($ws.subagent_output_share). " +
             "#165 R4 requires both the composite share and the output share because on cache-read-dominated sessions the two diverge widely.")
    }

    # --- S8: "it writes nothing" is a claim, so it is checked ------------
    # THIS CASE EXISTS BECAUSE THE COMMAND FAILED IT. The first build reached
    # for the state directory through lib\common.ps1's Get-LwgStateDir, whose
    # own doc block says "created if absent" - a CreateDirectory call kept
    # outside its memoisation on purpose, so that a state dir deleted mid-session
    # comes back for the hooks that write to it. Three real runs on the machine
    # this was written on therefore left an empty directory under the UNSUFFIXED
    # fallback name on the operator's disk, which is not where the live plugin
    # writes and which bin\lwg-doctor.ps1's state-dir check reports as a FAIL
    # whose text reads "can only have been created by this plugin's own
    # fallback". A read-only report had manufactured a fault and would not have
    # been the thing blamed for it, while its own header, its command page, its
    # documentation page and its changelog entry all said it wrote nothing.
    #
    # No case could see it: every other run here hands the child an EXISTING
    # scratch data directory. This one hands it a path that does not exist, which
    # is the only environment in which the claim is testable. Get-LwgStateDirInfo
    # resolves without creating; Get-LwgStateDir creates.
    Clear-Corpus -Sand $sand
    Write-Jsonl -Path (Join-Path $sand.projects "$slug\$sessA.jsonl") -Lines @(
        (New-AssistantLine -MessageId 'msg_s8' -Output 5 -SessionId $sessA)
    )
    $fallback = Join-Path $sand.profile '.claude\plugins\data'
    $rS8 = Invoke-Child -Sand $sand -ScriptPath $sand.metrics -ScriptArgs '-All' -Tag 's8' -WorkDir $work -NoState
    Add-Result 'S8 the report creates no directory anywhere - "it writes nothing" is checked, not asserted' `
        ($rS8.code -eq 0 -and -not (Test-Path -LiteralPath $sand.nostate) -and -not (Test-Path -LiteralPath $fallback)) `
        ("exit $($rS8.code); CLAUDE_PLUGIN_DATA was pointed at a path that does not exist and it $(if (Test-Path -LiteralPath $sand.nostate) { 'WAS CREATED' } else { 'was not created' }); " +
         "the profile fallback <profile>\.claude\plugins\data $(if (Test-Path -LiteralPath $fallback) { 'WAS CREATED' } else { 'was not created' }). " +
         "lib\common.ps1's Get-LwgStateDir creates the directory it resolves; this command must resolve through Get-LwgStateDirInfo, which does not. " +
         "A read-only report that leaves an empty state directory behind hands bin\lwg-doctor.ps1 a FAIL it did not earn.")

} catch {
    $script:Aborted = $_.Exception.Message
} finally {
    if ($null -ne $sand -and (Test-Path -LiteralPath $sand.root)) {
        try { Remove-Item -LiteralPath $sand.root -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    }
}

$sw.Stop()
$fail = @($script:Results | Where-Object { -not $_.ok })

Write-Output ''
Write-Output '==========================================================================='

if ($script:Aborted) {
    Write-Output "ABORTED: $($script:Aborted)"
    Write-Output "$($script:Results.Count) case(s) had run. The suite did NOT complete, so nothing above is a verdict."
    Write-Output 'EXIT: 2'
    exit 2
}

if ($script:Results.Count -eq 0) {
    # Zero cases is an abort wearing a pass's clothes.
    Write-Output 'ABORTED: no case ran at all, so nothing was established.'
    Write-Output 'EXIT: 2'
    exit 2
}

Write-Output ("RESULT: {0} of {1} case(s) passed in {2} ms" -f $script:Pass, $script:Results.Count, [int]$sw.Elapsed.TotalMilliseconds)

if ($fail.Count -gt 0) {
    Write-Output ''
    Write-Output "$($fail.Count) FAILED:"
    foreach ($f in $fail) { Write-Output ("  - {0}: {1}" -f $f.name, $f.detail) }
    Write-Output 'EXIT: 1'
    exit 1
}

Write-Output ''
Write-Output 'Every case above passed. Read that as "the indexer sums usage once per request,'
Write-Output 'keeps the four token categories apart, recurses the workflow children, tells a'
Write-Output 'requested tier from a resolved model, and refuses to invent the columns this'
Write-Output 'slice has no source for" - and NOT as "the metrics module works". This slice is'
Write-Output 'R2 alone. There is no hook, no meter history, no LCAP round, no landing and no'
Write-Output 'verdict, and sections C through H above are reserved rather than passing.'
Write-Output 'EXIT: 0'
exit 0
