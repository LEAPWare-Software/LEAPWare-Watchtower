#requires -version 5
<#
  LW-WATCHTOWER Stop-hook behaviour suite - mission_drift and failure_capture.

      powershell -NoProfile -ExecutionPolicy Bypass -File tests\stop_behaviour.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File tests\stop_behaviour.ps1 -Verbose

  WHAT THIS EXISTS FOR. Until this file landed, mission_drift ran at every turn
  end on every install with NO TEST OF ANY KIND, and lib\supervisor.ps1 carried
  two comments describing bugs that had already shipped - a dedupe that stopped
  deduping when alerted.json came back from ConvertFrom-Json nested or bare, and
  a one-element failed-task list whose .Count is $null, which logged
  "failed_tasks":null and left the status line green through a real failure -
  with no case pinning either fix. Both are now regression cases here (C1, C2),
  and each was confirmed to go RED with the guard removed before it was kept.

  ---------------------------------------------------------------------------
  FIVE SECTIONS, AND THEY ANSWER DIFFERENT KINDS OF QUESTION
  ---------------------------------------------------------------------------
  A. PURE HELPERS, in process. lib\common.ps1 is dot-sourced and the mission
     anchor helpers, the incremental transcript reader, the agent-class reader,
     the `modules` flag resolver and the redaction helper are called directly.
     These have no I/O contract worth a child process, and a unit call names the
     failure precisely - "a version number was read as a filename" rather than
     "the advisory did not fire".

     THE LAST TWO ARE NOT STOP-HOOK CODE and are here because this is where the
     helpers in lib\common.ps1 are exercised, not because they belong to
     mission_drift. Test-LwgModule decides whether every module in sections B
     and C runs at all, and Get-LwgRedacted is what those modules put their
     error text through on the way to the log - it is this plugin's ONLY
     redaction control and it had no test of any kind until these cases.
     Splitting them into a fourth suite would have bought a third CI step and a
     third copy of this plumbing.

  B. mission_drift, END TO END, in a child process. lib\stop_advisories.ps1 is
     run for real with a payload on stdin, because that is how Claude Code
     invokes it and because the module's whole behaviour is carried in state
     files between turns. A turn is one child run; a multi-turn case is several,
     with the transcript grown and the edit list extended in between.

  C. failure_capture, END TO END, in a child process, the same way -
     lib\supervisor.ps1 -HookEvent <Event>.

  D. LOG HYGIENE - the size, the encoding and the archive set of the files the
     other three sections write. Invoke-LwgRotate is called directly, in this
     process, against a throwaway state dir; the status line is run for real in
     a child process because what section D asserts about it is how long it
     takes, and that is not a property an in-process function call has.

     D is the only section that MEASURES rather than compares. Its one timing
     case asserts a DIFFERENCE between two medians taken back to back on the
     same machine in the same run, never an absolute duration, because an
     absolute threshold is a case that fails on a slow laptop and passes on a
     fast one for reasons that have nothing to do with the code.

  E. THIS SUITE ITSELF. One case, and the only one here that asserts on the
     harness rather than on anything the harness drives: that the operator's
     live event log is the same size after the run as it was before it. See
     NOTHING REAL IS TOUCHED below - one clause of which it turns from a claim
     into a check, and the leak it was written against.

  ---------------------------------------------------------------------------
  HOW A CHILD CASE IS RUN
  ---------------------------------------------------------------------------
  Through a real pipe, in a real child process, because a PowerShell object pipe
  never reaches [Console]::In and a hook reads its payload from there. Each run
  writes a one-line .cmd that does

      type payload.json | powershell -File lib\stop_advisories.ps1 1>out 2>err

  and the suite reads the exit code, stdout and stderr back off disk. The same
  arrangement as tests\gate_delegate.ps1, and for the same reason: an in-process
  call of the script's functions would test different code from the one Claude
  Code invokes.

  NOTHING REAL IS TOUCHED, AND SECTION E PUTS ONE ASSERTION BEHIND ONE CLAUSE OF
  THAT RATHER THAN LEAVING ALL OF IT AS A SENTENCE. Every case runs against a
  THROWAWAY plugin root under the temp directory with CLAUDE_PLUGIN_ROOT and
  CLAUDE_PLUGIN_DATA pointed at it, so no case reads or writes the operator's
  config, the live state directory, the event log or health.jsonl. The scripts
  under test are the real ones - they are the thing under test - and they are
  only ever read.

  READ WHAT SECTION E COVERS OF THAT, BECAUSE IT IS ONE CLAUSE OF FOUR. It
  compares the SIZE of the operator's event log before and after the run, and
  nothing else: not that log's contents, not health.jsonl, not the rest of the
  live state directory, and not the config. Those three are still promised here
  on the strength of the sandbox and asserted by no case. The event log is the
  one that is checked because it is the one the leak below actually reached.

  THE SANDBOX IS THE WHOLE RUN, NOT ONLY THE CHILD PROCESSES, and that is a fix
  rather than the original design. Invoke-LwgHook's environment window wraps a
  `cmd /c` spawn and puts the variables back the moment it returns, which is
  correct for a child process and covers nothing this process does itself.
  Section A runs ENTIRELY in this process, and eight of its calls deliberately
  hand a non-boolean to Test-LwgModule or Get-LwgModuleFlag, because the
  ignore-and-log path is the thing those cases are about. Write-LwgInvalidFlag
  resolves the state directory AT CALL TIME, so with no window open it resolved
  the OPERATOR'S, and every run of this suite appended eight ConfigInvalidFlag
  records to the live event log while the paragraph above said it did not.
  2,679 bytes per run, measured, and on a machine whose plugin had not written
  yet it CREATED that file rather than merely growing it. The records themselves
  were correct behaviour; the destination was the defect.

  The sandbox is therefore installed once, at the top of the run, and taken down
  in the finally so an abort cannot leave it standing. The three narrow windows
  further down - two in section A around the ConfigInvalidFlag assertions, one
  across section D's rotation cases - are KEPT rather than folded into it: each
  reads back a state directory it needs to hold nothing but the records of the
  call under test, and an outer sandbox shared by the whole run would mix them
  with every other record. They now nest inside the outer sandbox instead of
  dropping back to the operator's environment between cases.

  THE CONFIGS HERE ARE HAND-BUILT FIXTURES, and that is a deliberate difference
  from the gate suite, which byte-copies the shipped config.json. These cases
  need one module on and the other four off, and several need a knob at a value
  nothing ships (max_scan_bytes 512, so a transcript can be made to overflow it
  in a few hundred bytes rather than two megabytes). A fixture states exactly
  what each case assumes; the shipped file would leave four other modules
  running, spawning git and writing advisories that have nothing to do with the
  question being asked.

  EVERY PATH AND EVERY COMMAND NAMED IN A FIXTURE IS INVENTED. No case
  constructs a destructive command, even as a string it never runs, and every
  scratch path is built at runtime from [IO.Path]::GetTempPath() so nothing in
  this tracked file names a machine.

  ---------------------------------------------------------------------------
  WHAT A GREEN RUN DOES NOT MEAN
  ---------------------------------------------------------------------------
  docs\gates-removed.md, Lesson 3: the last gate's suite was 67/67 green while
  five bypasses were open. A green run here says the cases below still behave.
  It does NOT say mission_drift's trigger is right - the false-positive class in
  docs\modules.md is still live, and no case here can tell a warning that is
  correct from one an operator would call noise, because that judgement is not
  in the code. What the cases do establish is the pivot property (B2), which was
  the module's central design claim and had been read rather than run.

  ---------------------------------------------------------------------------
  EXIT CODES - a CI job reads these and nothing else
  ---------------------------------------------------------------------------
      0  every case passed
      1  at least one case FAILED
      2  the suite ABORTED - it could not set up or could not run a case, so
         nothing was established either way. Zero cases run is an abort, never
         an empty-set pass.

  No network. No elevation. Nothing runs outside the temp directory this file
  creates and deletes.
#>
[CmdletBinding()]
param(
    # Repo root. Defaults to this file's parent, correct for a run from
    # anywhere as long as this file stays in tests\.
    [string]$Root
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }

$AdvisoryPath   = Join-Path $Root 'lib\stop_advisories.ps1'
$PostEditPath   = Join-Path $Root 'lib\post_edit.ps1'
$SupervisorPath = Join-Path $Root 'lib\supervisor.ps1'
$CommonPath     = Join-Path $Root 'lib\common.ps1'
$HooksPath      = Join-Path $Root 'hooks\hooks.json'
$StatuslinePath = Join-Path $Root 'statusline\statusline.ps1'

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
# CHILD-PROCESS PLUMBING
# ===========================================================================

function Invoke-LwgHook {
    <#
      Run one hook script once against $Payload, with the plugin root and data
      dir pointed at a throwaway tree. Returns @{ code; out; err } - a hashtable,
      so PowerShell does not enumerate it away across the function boundary.

      $Payload is written as BYTES rather than through Set-Content so a case can
      hand the script exactly what it means to, byte for byte.

      A .cmd file rather than `cmd /c "<one long string>"`: cmd's rule about
      stripping the first and last quote of a /c argument makes a quoted path in
      such a string unreliable, and a test harness that breaks on a temp
      directory with a space in it is a test harness that stops being run.
    #>
    param(
        [string]$ScriptPath,
        [string]$ScriptArgs = '',
        [string]$Payload,
        [string]$PluginRoot,
        [string]$DataDir,
        [string]$WorkDir,
        [string]$Tag,
        # Replaces PATH for the child only. One case needs `git` to be
        # unresolvable, and there is no other way to produce that state without
        # touching a real installation. System32 is kept because the .cmd below
        # invokes powershell by name.
        [string]$PathOverride
    )

    $pf  = Join-Path $WorkDir "$Tag.json"
    $of  = Join-Path $WorkDir "$Tag.out"
    $ef  = Join-Path $WorkDir "$Tag.err"
    $bat = Join-Path $WorkDir "$Tag.cmd"

    [IO.File]::WriteAllText($pf, $Payload, [Text.UTF8Encoding]::new($false))
    foreach ($f in @($of, $ef)) { if ([IO.File]::Exists($f)) { [IO.File]::WriteAllText($f, '') } }

    $cmd = ('type "{0}" | powershell -NoProfile -ExecutionPolicy Bypass -File "{1}"' -f $pf, $ScriptPath)
    if (-not [string]::IsNullOrWhiteSpace($ScriptArgs)) { $cmd += (' ' + $ScriptArgs) }
    $cmd += (' 1>"{0}" 2>"{1}"' -f $of, $ef)

    [IO.File]::WriteAllLines($bat, @('@echo off', $cmd, 'exit /b %ERRORLEVEL%'), [Text.ASCIIEncoding]::new())

    $prevRoot = $env:CLAUDE_PLUGIN_ROOT
    $prevData = $env:CLAUDE_PLUGIN_DATA
    $prevPath = $env:PATH
    try {
        $env:CLAUDE_PLUGIN_ROOT = $PluginRoot
        $env:CLAUDE_PLUGIN_DATA = $DataDir
        if (-not [string]::IsNullOrWhiteSpace($PathOverride)) { $env:PATH = $PathOverride }
        & $env:ComSpec /c $bat | Out-Null
        $code = $LASTEXITCODE
    } finally {
        $env:PATH = $prevPath
        # Restored rather than removed: this process may have inherited real
        # values, and a suite that strips them changes the environment of
        # whatever runs after it.
        $env:CLAUDE_PLUGIN_ROOT = $prevRoot
        $env:CLAUDE_PLUGIN_DATA = $prevData
    }

    $out = ''; $err = ''
    try { $out = [IO.File]::ReadAllText($of) } catch { }
    try { $err = [IO.File]::ReadAllText($ef) } catch { }
    return @{ code = $code; out = $out; err = $err }
}

function Write-LwgFixtureConfig {
    <#
      A config.json fixture: the five Stop modules, failure_capture and
      log_rotation, plus an optional module_config block. Written through
      ConvertTo-Json so a fixture cannot be malformed by a quoting mistake here
      and then read as "config unreadable", which Get-LwgConfig FAILS OPEN on -
      turning every module back on and quietly making the case test the opposite
      of what it says.
    #>
    param([string]$Dir, [hashtable]$Modules, [hashtable]$MissionKnobs)

    $mods = [ordered]@{}
    foreach ($k in @('failure_capture', 'context_pressure', 'verification_gate', 'self_health',
                     'log_rotation', 'docs_coupling', 'git_hygiene', 'mission_drift', 'context_injection')) {
        $mods[$k] = $(if ($null -ne $Modules -and $Modules.ContainsKey($k)) { [bool]$Modules[$k] } else { $false })
    }

    $cfg = [ordered]@{
        version     = '0.2.0'
        modules     = [pscustomobject]$mods
        repos       = [pscustomobject]@{}
        interaction = [pscustomobject]@{ delegate = $false }
    }
    if ($null -ne $MissionKnobs) {
        $md = [ordered]@{}
        foreach ($k in @('min_files', 'require_outside_root', 'max_scan_bytes', 'max_anchors')) {
            if ($MissionKnobs.ContainsKey($k)) { $md[$k] = $MissionKnobs[$k] }
        }
        $cfg['module_config'] = [pscustomobject]@{ mission_drift = [pscustomobject]$md }
    }

    [IO.File]::WriteAllText((Join-Path $Dir 'config.json'),
        ($cfg | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
}

function Get-LwgRealLogBytes {
    <#
      The size of a file in bytes, or -1 when it is not there. Used on exactly
      one path - the operator's live lw-watchtower.jsonl - by section E.

      -1 RATHER THAN 0 FOR AN ABSENT FILE, and the distinction is the one the
      case actually turns on rather than a nicety. "The file is not there" and
      "the file is there and holds nothing" are two different states of the
      operator's machine, and a run that CREATED the event log where there had
      never been one has written into the state directory just as surely as one
      that appended to an existing log. A helper that returned 0 for both would
      report that as no change - and creating the file is precisely what the
      pre-fix suite did on a machine whose plugin had not written yet.

      NEVER THROWS, and an unreadable path is reported as absent rather than
      raised. This helper decides a case; a case that cannot be decided has to be
      able to FAIL, and an exception here would abort the suite instead, which
      says nothing either way about the question being asked.
    #>
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return [long](-1) }
    try {
        if ([IO.File]::Exists($Path)) { return [long]([IO.FileInfo]::new($Path)).Length }
    } catch { }
    return [long](-1)
}

# ===========================================================================
# MAIN
# ===========================================================================
$sw = [Diagnostics.Stopwatch]::StartNew()
$work = ''

# CAPTURED OUT HERE, OUTSIDE THE try, so the finally can put them back even when
# the setup below throws before the sandbox is fully installed. A suite that
# aborts halfway has still altered this process's environment, and whatever runs
# next in the same shell or the same CI step inherits it.
$prevPluginRoot = $env:CLAUDE_PLUGIN_ROOT
$prevPluginData = $env:CLAUDE_PLUGIN_DATA

# The operator's live event log, and its size before this suite ran. Both are
# filled in at the top of the try - after lib\common.ps1 is loaded, because its
# resolver is what decides where that file is, and before the sandbox replaces
# the environment that resolver reads. Section E compares the two at the end.
$realLog      = ''
$realLogBytes = [long](-1)

try {
    Write-Output 'LW-WATCHTOWER Stop-hook behaviour suite'
    Write-Output "  repo       : $Root"
    Write-Output "  advisories : $AdvisoryPath"
    Write-Output "  supervisor : $SupervisorPath"
    Write-Output "  statusline : $StatuslinePath"
    Write-Output ''

    foreach ($p in @($AdvisoryPath, $SupervisorPath, $CommonPath, $HooksPath, $StatuslinePath)) {
        if (-not [IO.File]::Exists($p)) { throw "missing: $p" }
    }

    $work = Join-Path ([IO.Path]::GetTempPath()) ('lwg-stop-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
    [void][IO.Directory]::CreateDirectory($work)

    . $CommonPath

    # -------------------------------------------------------------------
    # THE SANDBOX, FOR THE WHOLE RUN. See the header. Invoke-LwgHook's window
    # wraps child spawns only; this is what covers everything THIS process
    # does, which is where the leak was.
    # -------------------------------------------------------------------
    # WHERE THIS PROCESS WOULD OTHERWISE HAVE WRITTEN. Resolved from the AMBIENT
    # environment - the operator's - because that is the destination the
    # unwindowed calls in section A actually reached, and the only path section E
    # can honestly make a claim about. Get-LwgStateDirInfo reads and never
    # creates (Get-LwgStateDir is the one that creates), so asking the question
    # does not itself touch anything.
    $realDir = ''
    try { $realDir = [string](Get-LwgStateDirInfo).path } catch { }
    if (-not [string]::IsNullOrWhiteSpace($realDir)) {
        $realLog = Join-Path $realDir 'lw-watchtower.jsonl'
    }
    $realLogBytes = Get-LwgRealLogBytes $realLog

    # Now point both variables at a throwaway tree under $work. The resolution is
    # MEMOISED for the life of the process, so setting the variable is not on its
    # own enough and the memo is refreshed - the same pairing the narrower
    # windows further down already use, hoisted to cover the whole run.
    $sandboxRoot = Join-Path $work 'sandbox'
    $sandboxData = Join-Path $sandboxRoot 'data'
    [void][IO.Directory]::CreateDirectory($sandboxData)
    $env:CLAUDE_PLUGIN_ROOT = $sandboxRoot
    $env:CLAUDE_PLUGIN_DATA = $sandboxData
    Get-LwgStateDirInfo -Refresh | Out-Null

    # =====================================================================
    # SECTION A - PURE HELPERS
    # =====================================================================
    # Everything below this line runs IN THIS PROCESS, which is the whole reason
    # the sandbox above exists. MOST of it does not write - the readers are
    # handed files this suite created under $work and the mission helpers are
    # pure string work - but the flag resolvers below DO, every time they are
    # handed the non-boolean a case is about, and that claim used to be made
    # here as though it covered them. It did not.
    Write-Output 'A. helpers (in process)'

    $aDir = Join-Path $work 'a'
    [void][IO.Directory]::CreateDirectory($aDir)

    # --- Get-LwgPromptText -----------------------------------------------
    # The gate between the transcript and the anchor set. Everything ambiguous
    # must return $null: a tool RESULT is also a record of type 'user', and a
    # subagent's prompts are the orchestrator's words rather than the operator's.
    # Anchoring on either lets the plugin's own output feed back into its own
    # drift assessment.
    #
    # The records are built by PARSING JSON rather than by constructing
    # PSCustomObjects here, because that is the shape the module actually sees -
    # a line off the transcript through ConvertFrom-Json.
    function ConvertTo-Rec { param([string]$Json) return ($Json | ConvertFrom-Json) }

    $r = ConvertTo-Rec '{"type":"user","message":{"content":"rework the crimson parser"}}'
    Add-Result 'promptText: plain string content is the prompt' `
        ((Get-LwgPromptText -Record $r) -eq 'rework the crimson parser') `
        'a message.content that is a plain string is the ordinary typed-prompt shape and must be returned as-is'

    $r = ConvertTo-Rec '{"type":"user","toolUseResult":{"stdout":"x"},"message":{"content":"crimson output"}}'
    Add-Result 'promptText: a tool result is NOT a prompt' `
        ($null -eq (Get-LwgPromptText -Record $r)) `
        'a record carrying toolUseResult is a tool result wearing role user; treating it as a prompt anchors on the plugin''s own output'

    $r = ConvertTo-Rec '{"type":"user","isSidechain":true,"message":{"content":"crimson worker brief"}}'
    Add-Result 'promptText: a sidechain record is NOT a prompt' `
        ($null -eq (Get-LwgPromptText -Record $r)) `
        'isSidechain marks a subagent turn - those are the orchestrator''s words, not the operator''s'

    $r = ConvertTo-Rec '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu_1","content":"ok"}]}}'
    Add-Result 'promptText: a block carrying tool_use_id rejects the whole record' `
        ($null -eq (Get-LwgPromptText -Record $r)) `
        'a content block with tool_use_id is a tool result in array form; the record must be rejected outright rather than partially read'

    $r = ConvertTo-Rec '{"type":"user","message":{"content":[{"type":"text","text":"first half"},{"type":"text","text":"second half"}]}}'
    Add-Result 'promptText: text blocks are joined' `
        ((Get-LwgPromptText -Record $r) -eq 'first half second half') `
        'a multi-block text prompt must contribute all of its blocks'

    $r = ConvertTo-Rec '{"type":"assistant","message":{"content":"crimson answer"}}'
    Add-Result 'promptText: an assistant record is NOT a prompt' `
        ($null -eq (Get-LwgPromptText -Record $r)) `
        'only type user can be a typed prompt'

    # --- Add-LwgMissionAnchors -------------------------------------------
    # $aScope's root is invented and never created on disk: Get-LwgMissionScope
    # is pure string work, and what it needs is a path whose PARENT segments are
    # the ones to stop-list.
    $aScope = Get-LwgMissionScope -Root 'C:/lwg-fixture-hq/workspace'

    $an = New-LwgMissionAnchors
    $added = Add-LwgMissionAnchors -Text 'please rework module/crimson_parser.ps1 before the release' -Anchors $an -Scope $aScope
    Add-Result 'anchors: a path token contributes its segments AND the leaf stem' `
        ($added -gt 0 -and $an.paths.Contains('module') -and
         $an.paths.Contains('crimson_parser.ps1') -and $an.paths.Contains('crimson_parser')) `
        ("a named path must anchor on every segment and on the stem of its leaf, or a later edit to the same file under a different spelling looks unrelated. got: " + (@($an.paths) -join ', '))

    # A system-reminder is injected text, not the user speaking - and in this
    # plugin's case one of the things injected is its OWN advisory. If that
    # anchored, the module would silence itself by warning.
    $an2 = New-LwgMissionAnchors
    $added2 = Add-LwgMissionAnchors -Text "<system-reminder>edit outside/crimson_one.ps1 and outside/crimson_two.ps1</system-reminder>" -Anchors $an2 -Scope $aScope
    Add-Result 'anchors: system-reminder content contributes nothing' `
        ($added2 -eq 0 -and $an2.paths.Count -eq 0 -and $an2.words.Count -eq 0) `
        ("injected wrapper text is not the operator naming a file. got paths: " + (@($an2.paths) -join ', ') + ' / words: ' + (@($an2.words) -join ', '))

    $an3 = New-LwgMissionAnchors
    [void](Add-LwgMissionAnchors -Text 'bump the version to 0.2.0 and pin the schema at v1.4' -Anchors $an3 -Scope $aScope)
    Add-Result 'anchors: version numbers are not filenames' `
        ($an3.paths.Count -eq 0) `
        ("0.2.0 and v1.4 have a dot and are not files. Anchoring on them would put '2' and '4' in the path set and excuse almost anything. got: " + (@($an3.paths) -join ', '))

    $an4 = New-LwgMissionAnchors
    [void](Add-LwgMissionAnchors -Text 'the crimson telemetry needs rework' -Anchors $an4 -Scope $aScope)
    Add-Result 'anchors: four-letter-plus words land in the word set' `
        ($an4.words.Contains('crimson') -and $an4.words.Contains('telemetry') -and $an4.paths.Count -eq 0) `
        ("ordinary words can only EXCUSE a file, never accuse one, so they belong in words and never in paths. got words: " + (@($an4.words) -join ', '))

    # The cap is checked at the TOP of each token, so a set that has reached it
    # stops growing. Asserted exactly rather than as "roughly bounded": a cap
    # that is off by a token is a cap, and one that is ignored is not.
    $an5 = New-LwgMissionAnchors
    [void](Add-LwgMissionAnchors -Text 'crimson telemetry zebra kestrel juniper' -Anchors $an5 -Scope $aScope -MaxAnchors 2)
    Add-Result 'anchors: MaxAnchors caps the set' `
        ($an5.total -eq 2 -and ($an5.paths.Count + $an5.words.Count) -eq 2) `
        "five distinct words with MaxAnchors 2 must leave a set of exactly 2; got total $($an5.total)"

    # --- Test-LwgPathUnder ------------------------------------------------
    Add-Result 'pathUnder: a sibling sharing a prefix is NOT under' `
        (-not (Test-LwgPathUnder -Path 'C:/lwg-fixture/repo-two/file.ps1' -Root 'C:/lwg-fixture/repo')) `
        'repo-two is not inside repo. A StartsWith without the segment boundary would call every unrelated sibling accounted for, which is the silent direction'
    Add-Result 'pathUnder: comparison is case-insensitive' `
        (Test-LwgPathUnder -Path 'C:/LWG-Fixture/Repo/Lib/File.ps1' -Root 'c:/lwg-fixture/repo') `
        'Windows paths are case-insensitive; a case-sensitive test would report work inside the workspace as outside it'
    Add-Result 'pathUnder: the root itself is under the root' `
        (Test-LwgPathUnder -Path 'C:/lwg-fixture/repo' -Root 'C:/lwg-fixture/repo/') `
        'the root, with or without a trailing separator, is inside itself'
    Add-Result 'pathUnder: an empty root is never a match' `
        (-not (Test-LwgPathUnder -Path 'C:/lwg-fixture/repo/x.ps1' -Root '')) `
        'an unresolved workspace root must not make every path look inside it'

    # --- Test-LwgMissionAccounted ----------------------------------------
    # Deliberately generous: every near-miss resolves towards "accounted", which
    # costs recall and protects credibility. Each of the three routes is pinned
    # separately so a change that drops one is named rather than merely counted.
    $an6 = New-LwgMissionAnchors
    [void](Add-LwgMissionAnchors -Text 'work in module/crimson_parser.ps1 and mind the telemetry' -Anchors $an6 -Scope $aScope)

    Add-Result 'accounted: a shared directory segment excuses a file' `
        (Test-LwgMissionAccounted -Path 'D:/elsewhere/module/other.ps1' -Anchors $an6 -Scope $aScope) `
        'the prompt named a path with segment "module"; a file under module/ shares it and must be excused'
    Add-Result 'accounted: a shared filename stem excuses a file' `
        (Test-LwgMissionAccounted -Path 'D:/elsewhere/deep/crimson_parser.psm1' -Anchors $an6 -Scope $aScope) `
        'the stem crimson_parser was anchored from the named file and must excuse the same stem elsewhere'
    Add-Result 'accounted: an ordinary word from a prompt excuses a file' `
        (Test-LwgMissionAccounted -Path 'D:/elsewhere/deep/telemetry.ps1' -Anchors $an6 -Scope $aScope) `
        'a word anchor can only excuse, never accuse - a file whose stem is a word the operator used is accounted for'
    Add-Result 'accounted: sharing nothing is NOT accounted' `
        (-not (Test-LwgMissionAccounted -Path 'D:/elsewhere/kestrel/juniper.ps1' -Anchors $an6 -Scope $aScope)) `
        'a path sharing no segment, stem or word with anything named must come back unaccounted, or the module can never fire at all'

    # --- Read-LwgAppendedLines -------------------------------------------
    # The reader that makes a per-turn transcript scan affordable. Its contract
    # is the offset: always just past the last newline CONSUMED, never mid-record.
    $tf = Join-Path $aDir 'append.txt'
    [IO.File]::WriteAllText($tf, "alpha`nbravo`n", [Text.UTF8Encoding]::new($false))
    $s1 = Read-LwgAppendedLines -Path $tf -Offset 0
    Add-Result 'appended: a first read takes the whole file' `
        (@($s1.lines).Count -eq 2 -and $s1.offset -eq 12 -and -not $s1.truncated -and -not $s1.reset) `
        "expected 2 lines and offset 12; got $(@($s1.lines).Count) line(s), offset $($s1.offset)"

    [IO.File]::AppendAllText($tf, "charlie`n", [Text.UTF8Encoding]::new($false))
    $s2 = Read-LwgAppendedLines -Path $tf -Offset $s1.offset
    Add-Result 'appended: a resumed read takes only the growth' `
        (@($s2.lines).Count -eq 1 -and @($s2.lines)[0] -eq 'charlie' -and $s2.offset -eq 20) `
        "resuming from $($s1.offset) must yield only the new line; got $(@($s2.lines) -join ',') at offset $($s2.offset)"

    # A half-written record is left alone rather than parsed and discarded: the
    # transcript is appended to by another process while this runs.
    [IO.File]::AppendAllText($tf, 'delt', [Text.UTF8Encoding]::new($false))
    $s3 = Read-LwgAppendedLines -Path $tf -Offset $s2.offset
    Add-Result 'appended: a partial last line is left unconsumed' `
        (@($s3.lines).Count -eq 0 -and $s3.offset -eq $s2.offset) `
        "a record with no terminating newline must not be consumed; got $(@($s3.lines).Count) line(s) at offset $($s3.offset)"

    [IO.File]::AppendAllText($tf, "a`n", [Text.UTF8Encoding]::new($false))
    $s4 = Read-LwgAppendedLines -Path $tf -Offset $s3.offset
    Add-Result 'appended: the completed record is picked up whole on the next read' `
        (@($s4.lines).Count -eq 1 -and @($s4.lines)[0] -eq 'delta') `
        "the previously partial record must arrive complete; got $(@($s4.lines) -join ',')"

    [IO.File]::WriteAllText($tf, "zulu`n", [Text.UTF8Encoding]::new($false))
    $s5 = Read-LwgAppendedLines -Path $tf -Offset $s4.offset
    Add-Result 'appended: a file shorter than the offset resets to 0' `
        ($s5.reset -and @($s5.lines).Count -eq 1 -and @($s5.lines)[0] -eq 'zulu') `
        'a file shorter than where we left off is a different file - a new session or a rotated log - and must be re-read from the start rather than seeked past the end'

    $big = Join-Path $aDir 'big.txt'
    [IO.File]::WriteAllText($big, (('x' * 200) + "`n" + ('y' * 200) + "`n"), [Text.UTF8Encoding]::new($false))
    $s6 = Read-LwgAppendedLines -Path $big -Offset 0 -MaxBytes 64
    Add-Result 'appended: growth beyond MaxBytes is SKIPPED and reported' `
        ($s6.truncated -and @($s6.lines).Count -eq 0 -and $s6.offset -eq (Get-Item $big).Length) `
        'past the cap the region must be skipped, the offset moved to EOF and the caller TOLD - silently reading a prefix would leave the caller believing it had seen everything'

    # --- the agent classifier, PINNED ------------------------------------
    # This is a rename guard as much as a behaviour test. `lw-class` was
    # declared by six shipped roles and read by nothing for its whole life; the
    # value that matters most is the one that looks like nothing - '' is NO
    # INFORMATION and must never be read as "not a verifier", because that would
    # silence verification_gate on the strength of an absence.
    $agDir = Join-Path $aDir 'agents'
    [void][IO.Directory]::CreateDirectory($agDir)
    function New-LwgRoleFixture {
        param([string]$Name, [string]$Body, [switch]$Bom)
        $p = Join-Path $agDir $Name
        [IO.File]::WriteAllText($p, $Body, [Text.UTF8Encoding]::new([bool]$Bom))
        return $p
    }

    $fNone   = New-LwgRoleFixture -Name 'f_none.md'   -Body "---`nname: fixture-none`ndescription: no class declared`n---`nbody`n"
    $fVerify = New-LwgRoleFixture -Name 'f_verify.md' -Body "---`nname: fixture-verify`nlw-class: verify`n---`nbody`n"
    $fCase   = New-LwgRoleFixture -Name 'f_case.md'   -Body "---`nname: fixture-case`nlw-class: Work`n---`nbody`n"
    $fTypo   = New-LwgRoleFixture -Name 'f_typo.md'   -Body "---`nname: fixture-typo`nlw-class: verifier`n---`nbody`n"
    $fPlain  = New-LwgRoleFixture -Name 'f_plain.md'  -Body "no frontmatter at all`nlw-class: verify`n"
    $fBom    = New-LwgRoleFixture -Name 'f_bom.md'    -Body "---`nname: fixture-bom`nlw-class: neutral`n---`nbody`n" -Bom

    Add-Result "class: a file with no lw-class key reads '' (NO INFORMATION)" `
        ((Get-LwgFrontmatterClass -Path $fNone) -eq '') `
        "'' means the file said nothing about its class. It must NOT be read as 'not a verifier' - that would let an absence disarm verification_gate"
    Add-Result 'class: lw-class: verify reads verify' `
        ((Get-LwgFrontmatterClass -Path $fVerify) -eq 'verify') `
        'the declared value is the answer, and it is the whole reason the key exists'
    Add-Result 'class: the value is case-insensitive' `
        ((Get-LwgFrontmatterClass -Path $fCase) -eq 'work') `
        "lw-class: Work must resolve to 'work'; a case-sensitive read would silently unclassify a role that declared itself correctly"
    Add-Result "class: a typo'd value reads '' rather than being coerced" `
        ((Get-LwgFrontmatterClass -Path $fTypo) -eq '') `
        "'verifier' is not one of work/verify/neutral. Guessing at it would classify a role from a value nobody checked"
    Add-Result "class: a file with no frontmatter reads ''" `
        ((Get-LwgFrontmatterClass -Path $fPlain) -eq '') `
        'a lw-class written in the prose is not metadata and the loader would not honour it either'
    Add-Result 'class: a BOM does not hide the frontmatter' `
        ((Get-LwgFrontmatterClass -Path $fBom) -eq 'neutral') `
        'PowerShell 5.1 writes a BOM by default, so a role file authored on this platform routinely has one; a BOM left on the opening fence would unclassify it'
    Add-Result "class: a missing file reads ''" `
        ((Get-LwgFrontmatterClass -Path (Join-Path $agDir 'f_absent.md')) -eq '') `
        'unreadable is no information, never a class'

    # THE RESOLVER'S POSITIVE ARM, WHICH DID NOT EXIST. Every case above calls
    # Get-LwgFrontmatterClass directly and bypasses the resolver; the two below
    # were the only calls to Get-LwgAgentClassInfo in tests\, and both were
    # negative. So the one path from "a role name" to "the class
    # verification_gate reads" had no case that could tell a working resolver
    # from one returning nothing - which is one-directional coverage on the
    # function that decides whether the module can classify anything at all.
    # The fixture goes under .claude\agents, which is what Get-LwgAgentRoots
    # calls PROJECT scope. $agDir above is <root>\agents, the PLUGIN scope of a
    # different plugin root, and nothing resolves through it - which is exactly
    # why the two cases below could only ever be negative ones.
    $agProj = Join-Path $aDir '.claude\agents'
    [void][IO.Directory]::CreateDirectory($agProj)
    $fResolve = Join-Path $agProj 'lwg-fixture-resolver.md'
    [IO.File]::WriteAllText($fResolve,
        "---`nname: lwg-fixture-resolver`nlw-class: verify`n---`nbody`n", [Text.UTF8Encoding]::new($false))

    $aiHit = Get-LwgAgentClassInfo -Name 'lwg-fixture-resolver' -ProjectRoot $aDir
    Add-Result 'class: a name that DOES resolve reads its class, its file and its scope' `
        ($null -ne $aiHit -and [string]$aiHit.class -eq 'verify' -and
         [string]$aiHit.file -eq $fResolve -and [string]$aiHit.scope -eq 'project') `
        ("the resolver is the only path from a role name to a class, and until this row its only cases were negative ones satisfied by it returning nothing. got: " +
         $(if ($null -eq $aiHit) { '<null>' } else { ($aiHit | ConvertTo-Json -Compress -Depth 4) }))

    # `[string]$x.member -eq ''` IS AN "IT RETURNED NOTHING" TEST TOO. [string]$null
    # is '', so all three conjuncts below were satisfied by Get-LwgAgentClassInfo
    # returning $null or an empty hashtable - and this is the only case in the
    # repository that exercises the resolver's miss path. The container is
    # asserted first, then its members, so an empty answer and no answer stop
    # being the same result.
    # The container test is `-is [hashtable]` plus ContainsKey, not
    # PSObject.Properties: this function returns a HASHTABLE on purpose - its
    # docstring says so, because a hashtable is not enumerated on return - and a
    # hashtable's PSObject.Properties are Keys, Values and Count, never the
    # entries. Getting that wrong makes the guard itself always false, which is
    # the mirror image of the defect being fixed.
    $ai = Get-LwgAgentClassInfo -Name 'lwg-fixture-role-that-does-not-exist' -ProjectRoot $aDir
    $aiKeys = ($ai -is [hashtable])
    Add-Result "class: a name resolving to no file reads '' with no file and no scope" `
        ($null -ne $ai -and $aiKeys -and $ai.ContainsKey('class') -and $ai.ContainsKey('file') -and $ai.ContainsKey('scope') -and
         [string]$ai.class -eq '' -and [string]$ai.file -eq '' -and [string]$ai.scope -eq '') `
        ("a name with no role file behind it is NO INFORMATION: it neither arms nor disarms verification_gate. got: " +
         $(if ($null -eq $ai) { '<null>' } else { ($ai | ConvertTo-Json -Compress -Depth 4) }))

    $ai2 = Get-LwgAgentClassInfo -Name 'lw-watchtower:lwg-fixture-role-that-does-not-exist' -ProjectRoot $aDir
    Add-Result 'class: a namespaced name is split on the FIRST colon' `
        ([string]$ai2.namespace -eq 'lw-watchtower' -and [string]$ai2.bare -eq 'lwg-fixture-role-that-does-not-exist') `
        "a plugin-shipped role arrives namespaced and the bare stem is what names the file. got namespace '$($ai2.namespace)', bare '$($ai2.bare)'"

    # --- Test-LwgModule, the `modules` block ------------------------------
    # ONLY A REAL BOOLEAN IS A SETTING, and this block is where that rule
    # arrived last. Test-LwgFlag had it for the `switch` keys while this still
    # did a bare [bool], where [bool] on a non-empty string is $true and
    # [bool]'' and [bool]0 are $false - so a `modules` value that was a string
    # or a number decided a governance module's fate by an accident of
    # PowerShell's coercion table rather than by anything an operator wrote.
    #
    # THE DIRECTION OF "IGNORED" IS THE OPPOSITE ONE HERE and the cases below
    # are chosen around it. A `modules` flag defaults ON, so an ignored value
    # leaves a module RUNNING; a `switch` flag defaults off, so an ignored value
    # leaves a gate DOWN. Same rule, different floor underneath it.
    #
    # WHICH OF THESE COULD GO RED, since it is not all of them: '"x": "false"'
    # is $true by coercion and $true by the rule, so the four cases marked
    # CANNOT GO RED are pinning that the fix moved no answer that was already
    # right. The red ones are the empty string, the number 0, and any
    # non-boolean OVERRIDE - the three shapes where coercion and the rule
    # disagree.
    function New-LwgModCfg { param([string]$Json) return ($Json | ConvertFrom-Json) }
    $mSlug = 'lwg-fixture/mod-suite'

    $mTrue  = New-LwgModCfg '{"modules":{"docs_coupling":true}}'
    $mFalse = New-LwgModCfg '{"modules":{"docs_coupling":false}}'
    Add-Result 'modflag: a real true enables' `
        (Test-LwgModule -Name 'docs_coupling' -Config $mTrue -Repo '') `
        'CANNOT GO RED. The regression a boolean-only rule is likeliest to introduce is refusing the values that were always valid, so both spellings are pinned'
    Add-Result 'modflag: a real false disables' `
        (-not (Test-LwgModule -Name 'docs_coupling' -Config $mFalse -Repo '')) `
        'CANNOT GO RED, and it is the one an operator relies on most - a module they switched off must stay off'

    $mRepoOff = New-LwgModCfg ('{"modules":{"docs_coupling":true},"repos":{"' + $mSlug + '":{"modules":{"docs_coupling":false}}}}')
    Add-Result 'modflag: a real per-repo false overrides a global true' `
        ((Test-LwgModule -Name 'docs_coupling' -Config $mRepoOff -Repo '') -and
         -not (Test-LwgModule -Name 'docs_coupling' -Config $mRepoOff -Repo $mSlug)) `
        'CANNOT GO RED. The override path has to keep working at all before it is worth asking what it does with rubbish'

    $mStr = New-LwgModCfg '{"modules":{"docs_coupling":"false"}}'
    Add-Result 'modflag: the STRING "false" is ignored, so the module stays ON' `
        (Test-LwgModule -Name 'docs_coupling' -Config $mStr -Repo '') `
        'CANNOT GO RED - [bool] on a non-empty string was $true, which is the same answer by the wrong route. It is pinned anyway because the ANSWER is the uncomfortable one: an operator who wrote "false" has a module that is still running, and the rule says so out loud rather than guessing at the quotes'

    $mEmpty = New-LwgModCfg '{"modules":{"docs_coupling":""}}'
    Add-Result 'modflag: the EMPTY STRING is ignored rather than read as off' `
        (Test-LwgModule -Name 'docs_coupling' -Config $mEmpty -Repo '') `
        'an empty string is not false, it is not a value at all. [bool]"" is $false, so this silently DISABLED a governance module on the strength of a quoting accident, and nothing anywhere said so'

    $mZero = New-LwgModCfg '{"modules":{"docs_coupling":0}}'
    Add-Result 'modflag: the NUMBER 0 is ignored rather than read as off' `
        (Test-LwgModule -Name 'docs_coupling' -Config $mZero -Repo '') `
        '[bool]0 is $false, so a JSON number disabled the module. It is the same class as the empty string and the more plausible typo of the two'

    $mRepoStr = New-LwgModCfg ('{"modules":{"docs_coupling":false},"repos":{"' + $mSlug + '":{"modules":{"docs_coupling":"true"}}}}')
    Add-Result 'modflag: a non-boolean per-repo override cannot re-enable what the global switched off' `
        (-not (Test-LwgModule -Name 'docs_coupling' -Config $mRepoStr -Repo $mSlug)) `
        'the override is not a boolean, so it is not an override and the global false stands. [bool] on the string turned it into $true and restarted a module the operator had switched off for every repo'

    $mRepoJunk = New-LwgModCfg ('{"modules":{"docs_coupling":true},"repos":{"' + $mSlug + '":{"modules":{"docs_coupling":"nonsense"}}}}')
    Add-Result 'modflag: a non-boolean per-repo override does not disarm a global true either' `
        (Test-LwgModule -Name 'docs_coupling' -Config $mRepoJunk -Repo $mSlug) `
        'CANNOT GO RED, by coercion landing on the right answer again. It pins the direction: an invalid value is not a vote for false, so it can neither switch a module on nor switch one off'

    # THE IGNORED VALUE IS LOGGED, and through the SAME helper Test-LwgFlag
    # uses. A setting that does not take effect and says nothing is the founding
    # defect of this whole plugin, so the record is part of the fix.
    #
    # THIS WINDOW IS ABOUT ISOLATION, NOT SAFETY, and that changed under it. It
    # was written as the thing that kept these two calls off the operator's live
    # log - "put back immediately, this process inherited whatever the operator
    # had set" - which was true of these two calls and of nothing else in the
    # section, so the eight OTHER resolver calls above wrote to the live log
    # unwindowed. The outer sandbox at the top of MAIN is what stops that now.
    # What this window still earns is a state dir holding NOTHING BUT the two
    # records asserted below; sharing the run's sandbox would mix them with
    # every other ConfigInvalidFlag this section produces and the assertion
    # would stop naming the calls it is about.
    $mLogDir  = Join-Path $aDir 'invalidflag'
    [void][IO.Directory]::CreateDirectory($mLogDir)
    $mPrevData = $env:CLAUDE_PLUGIN_DATA
    $mEvents = ''
    try {
        $env:CLAUDE_PLUGIN_DATA = $mLogDir
        Get-LwgStateDirInfo -Refresh | Out-Null
        [void](Test-LwgModule -Name 'docs_coupling' -Config $mZero -Repo '')
        [void](Test-LwgModule -Name 'docs_coupling' -Config $mRepoStr -Repo $mSlug)
        try { $mEvents = [IO.File]::ReadAllText((Join-Path $mLogDir 'lw-watchtower.jsonl')) } catch { }
    } finally {
        $env:CLAUDE_PLUGIN_DATA = $mPrevData
        Get-LwgStateDirInfo -Refresh | Out-Null
    }

    Add-Result 'modflag: an ignored value is written as ConfigInvalidFlag naming the block, the key and the scope' `
        ($mEvents -match '"event":"ConfigInvalidFlag"' -and
         $mEvents -match '"block":"modules"' -and
         $mEvents -match '"key":"docs_coupling"' -and
         $mEvents -match '"scope":"global"' -and
         $mEvents -match ('"scope":"repo:' + [regex]::Escape($mSlug) + '"')) `
        ("both scopes must produce a record, or a config that does not take effect is a config nobody is told about. lw-watchtower.jsonl held:`n$mEvents")

    # --- Get-LwgModuleFlag, the `module_config` booleans -------------------
    # THE SAME RULE, ONE LAYER DOWN. The `modules` block above decides whether a
    # module runs; `module_config` decides how it behaves once it does, and its
    # boolean options were still read with a bare [bool] after the block above
    # was fixed. lib\stop_advisories.ps1 did
    #
    #     [bool](Get-LwgModuleOption ... -Key 'require_outside_root' -Default $true)
    #
    # so an empty string or a 0 switched mission_drift's largest suppressor OFF
    # and the module warned about work it exists to excuse.
    #
    # WHAT THESE CASES CAN AND CANNOT ESTABLISH, said plainly because the honest
    # red set is small. Against the pre-fix tree these unit cases fail because
    # the FUNCTION DOES NOT EXIST, which is a weaker red than a wrong answer -
    # they pin the rule, they do not prove the defect. B10 and B11 in section B
    # are the ones that go red against pre-fix code that runs: they drive the
    # real hook and catch it warning where it must be silent.
    #
    # THE FLOOR IS THE CALLER'S $Default, not a fixed polarity - a
    # `module_config` key is tuning, not the module's switch - so "ignored"
    # means "tuned as shipped" and both current callers ship $true.
    $fTrue  = New-LwgModCfg '{"module_config":{"mission_drift":{"require_outside_root":true}}}'
    $fFalse = New-LwgModCfg '{"module_config":{"mission_drift":{"require_outside_root":false}}}'
    Add-Result 'modcfg: a real true is honoured' `
        (Get-LwgModuleFlag -Config $fTrue -Module 'mission_drift' -Key 'require_outside_root' -Default $false) `
        'CANNOT GO RED against code that runs. Pinned because refusing the values that were always valid is the regression a boolean-only rule is likeliest to introduce'
    Add-Result 'modcfg: a real false is honoured' `
        (-not (Get-LwgModuleFlag -Config $fFalse -Module 'mission_drift' -Key 'require_outside_root' -Default $true)) `
        'CANNOT GO RED against code that runs, and it is the one an operator relies on: switching a suppressor off must actually switch it off'

    $fAbsent = New-LwgModCfg '{"module_config":{"mission_drift":{}}}'
    Add-Result 'modcfg: an absent key falls to the caller default' `
        (Get-LwgModuleFlag -Config $fAbsent -Module 'mission_drift' -Key 'require_outside_root' -Default $true) `
        'CANNOT GO RED against code that runs. A stripped-down config must yield a working module, not a module tuned by whatever [bool] $null happens to be'

    $fEmpty = New-LwgModCfg '{"module_config":{"mission_drift":{"require_outside_root":""}}}'
    Add-Result 'modcfg: the EMPTY STRING is ignored rather than read as off' `
        (Get-LwgModuleFlag -Config $fEmpty -Module 'mission_drift' -Key 'require_outside_root' -Default $true) `
        '[bool]"" is $false, so an empty string silently disarmed the suppressor. An empty string is not false, it is not a value at all'

    $fZero = New-LwgModCfg '{"module_config":{"mission_drift":{"require_outside_root":0}}}'
    Add-Result 'modcfg: the NUMBER 0 is ignored rather than read as off' `
        (Get-LwgModuleFlag -Config $fZero -Module 'mission_drift' -Key 'require_outside_root' -Default $true) `
        '[bool]0 is $false. JSON has real booleans, so a 0 here is a mistake, and a mistake must not be read as a decision'

    $fStr = New-LwgModCfg '{"module_config":{"mission_drift":{"require_outside_root":"false"}}}'
    Add-Result 'modcfg: the STRING "false" is ignored, so the default stands' `
        (Get-LwgModuleFlag -Config $fStr -Module 'mission_drift' -Key 'require_outside_root' -Default $true) `
        'CANNOT GO RED - [bool] on a non-empty string was $true, the same answer by the wrong route. Pinned because the ANSWER is the uncomfortable one: an operator who wrote "false" has a suppressor that is still on, and the rule now says so in the log instead of guessing at the quotes'

    # The record, through the SAME helper, naming the module in the block so a
    # reader can tell module_config.mission_drift from the `modules` entry of
    # the same name.
    $fLogDir = Join-Path $aDir 'invalidmodcfg'
    [void][IO.Directory]::CreateDirectory($fLogDir)
    $fPrevData = $env:CLAUDE_PLUGIN_DATA
    $fEvents = ''
    try {
        $env:CLAUDE_PLUGIN_DATA = $fLogDir
        Get-LwgStateDirInfo -Refresh | Out-Null
        [void](Get-LwgModuleFlag -Config $fZero -Module 'mission_drift' -Key 'require_outside_root' -Default $true)
        try { $fEvents = [IO.File]::ReadAllText((Join-Path $fLogDir 'lw-watchtower.jsonl')) } catch { }
    } finally {
        $env:CLAUDE_PLUGIN_DATA = $fPrevData
        Get-LwgStateDirInfo -Refresh | Out-Null
    }

    Add-Result 'modcfg: an ignored value is written as ConfigInvalidFlag naming module_config and the module' `
        ($fEvents -match '"event":"ConfigInvalidFlag"' -and
         $fEvents -match '"block":"module_config\.mission_drift"' -and
         $fEvents -match '"key":"require_outside_root"') `
        ("a tuning key that does not take effect and says nothing is the same defect as a switch that does not take effect. lw-watchtower.jsonl held:`n$fEvents")

    # --- Format-LwgFlagState, the reporting half of the rule ---------------
    # A READER THAT IGNORES A VALUE AND A REPORTER THAT PRINTS IT AS `on` IS THE
    # DIVERGENCE THIS PLUGIN EXISTS TO CATCH, and bin\lwg-config.ps1 had exactly
    # that: the OVERRIDE column rendered a raw member with a bare [bool] while
    # Test-LwgModule, two lines below on the same value, ignored it. The third
    # word is the whole point - a value that is not a setting cannot honestly be
    # shown as either setting.
    #
    # NO SUITE DRIVES bin\lwg-config.ps1 OR bin\lwg-update.ps1 END TO END, so
    # what is covered here is the RULE those commands now share, not the
    # commands themselves. Said out loud rather than left for a reader to assume
    # from a green run.
    Add-Result 'flagstate: a real true renders on' `
        ((Format-LwgFlagState $true) -eq 'on') 'the valid values have to keep rendering before it is worth asking what rubbish renders as'
    Add-Result 'flagstate: a real false renders off' `
        ((Format-LwgFlagState $false) -eq 'off') 'an operator who switched something off must read off'
    Add-Result 'flagstate: an absent value renders as no override at all' `
        ((Format-LwgFlagState $null) -eq '-') '$null is the absence of an override, which is not the same as an override set to off'
    Add-Result 'flagstate: the STRING "false" renders ignored, not on' `
        ((Format-LwgFlagState 'false') -eq 'ignored') 'this is the exact cell that printed `on` for an operator who had written "false" - the reporter contradicting the resolver in the same table'
    Add-Result 'flagstate: the NUMBER 0 renders ignored, not off' `
        ((Format-LwgFlagState 0) -eq 'ignored') 'reporting a 0 as off would agree with the OLD reader and disagree with the current one, which is the divergence pointing the other way'
    Add-Result 'flagstate: the EMPTY STRING renders ignored' `
        ((Format-LwgFlagState '') -eq 'ignored') 'the empty string is the shape a quoting accident most often takes, and it must read as ignored in the report exactly as it is ignored by the resolver'

    # --- Get-LwgRedacted --------------------------------------------------
    # THE ONLY REDACTION CONTROL THIS PLUGIN HAS, and until these cases it had
    # no test of any kind - docs/limitations.md said so in as many words. It is
    # also load bearing twice over: every module runs it over anything headed
    # for the log, and bin\lwg-resolve.ps1 PRINTS its output into a
    # fixed-column console report, a row at a time.
    #
    # The two properties below the credential masking are the ones that were
    # broken, and both are about what the value IS rather than what it hides:
    # it has to be one line, and it has to be text.
    function Test-LwgIsCleanField {
        <#
          Is this value emittable? Two questions a log field has to answer yes
          to, asked together because every case here needs both:

            no control character, so it cannot end a row early or drive a
            terminal;

            it survives a UTF-8 round trip unchanged, which a lone surrogate
            does not - the writer substitutes U+FFFD for it, so the bytes on
            disk stop being the string that was checked.
        #>
        param([string]$V)
        if ($V -match '\p{Cc}') { return $false }
        return ([Text.Encoding]::UTF8.GetString([Text.Encoding]::UTF8.GetBytes($V)) -eq $V)
    }

    # A specimen is never a literal in a tracked file - see the note above
    # $script:LwgSecretPatterns. Both of these are assembled at runtime.
    $rTok = 'ghp_' + ('A' * 30)
    $rOut = Get-LwgRedacted -Text ("prefix " + $rTok + " suffix")
    Add-Result 'redact: a token-shaped value is replaced whole, and no part of it survives' `
        ($rOut -eq 'prefix [REDACTED:github_token] suffix' -and $rOut -notmatch 'AAAA') `
        "CANNOT GO RED - this is the behaviour that already worked, pinned because it is the function's reason to exist. got: $rOut"

    $rAssign = Get-LwgRedacted -Text 'api_key = swordfish99 and on we go'
    Add-Result 'redact: an assignment the pattern list does not cover is masked by the generic rule' `
        ($rAssign -eq 'api_key = [REDACTED] and on we go') `
        "CANNOT GO RED. The generic rule is what catches a credential in a shape nobody enumerated. got: $rAssign"

    $rUnder = Get-LwgRedacted -Text ('u' * 39) -MaxLength 40
    $rAt    = Get-LwgRedacted -Text ('u' * 40) -MaxLength 40
    $rOver  = Get-LwgRedacted -Text ('u' * 41) -MaxLength 40
    Add-Result 'redact: one under the cap and exactly at the cap are both returned whole' `
        ($rUnder -eq ('u' * 39) -and $rAt -eq ('u' * 40)) `
        "CANNOT GO RED. An off-by-one at the cap would mark a value as truncated that was not, which is a report saying something that did not happen. got lengths $($rUnder.Length) and $($rAt.Length)"
    Add-Result 'redact: one over the cap is cut to the cap and marked as cut' `
        ($rOver -eq (('u' * 40) + '...')) `
        "CANNOT GO RED. The ellipsis is outside the cap on purpose - the cap bounds the PAYLOAD, and a truncation nobody can see is a payload silently changed. got: $rOver"

    # A character outside the Basic Multilingual Plane is TWO UTF-16 units, and
    # the cap can land between them. Built with ConvertFromUtf32 rather than
    # written literally: this file stays ASCII, and a source-encoding accident
    # would turn the case into a different one without saying so.
    $rAstral   = [char]::ConvertFromUtf32(0x1F600)
    $rStraddle = Get-LwgRedacted -Text (('s' * 9) + $rAstral + ('t' * 5)) -MaxLength 10
    Add-Result 'redact: a character straddling the cap is dropped, never cut in half' `
        ((Test-LwgIsCleanField $rStraddle) -and $rStraddle -eq (('s' * 9) + '...')) `
        "the cut used to land between the two units and emit a lone high surrogate: not a character, not encodable as UTF-8, and not valid JSON when PowerShell 5.1 serialises it. The cut must move back one unit instead. got: $(($rStraddle.ToCharArray() | ForEach-Object { '{0:X4}' -f [int]$_ }) -join ' ')"

    $rWhole = Get-LwgRedacted -Text (('s' * 8) + $rAstral + ('t' * 5)) -MaxLength 10
    Add-Result 'redact: a character that ENDS exactly at the cap is kept whole' `
        ((Test-LwgIsCleanField $rWhole) -and $rWhole -eq (('s' * 8) + $rAstral + '...')) `
        "CANNOT GO RED, and it is the case a careless surrogate guard breaks: backing off unconditionally would throw away a character that fitted. got: $(($rWhole.ToCharArray() | ForEach-Object { '{0:X4}' -f [int]$_ }) -join ' ')"

    # An unpaired surrogate can also arrive in the INPUT - ConvertFrom-Json will
    # hand one back from a config value written as a bare \udXXX escape, and
    # Write-LwgInvalidFlag redacts config values.
    $rLoneIn = Get-LwgRedacted -Text ('a' + [string][char]0xD83D + 'b')
    Add-Result 'redact: an unpaired surrogate in the INPUT is never emitted' `
        ((Test-LwgIsCleanField $rLoneIn) -and $rLoneIn.Length -eq 3 -and $rLoneIn[1] -eq [char]0xFFFD) `
        "it cannot be made whole, so it must be replaced rather than passed on. got: $(($rLoneIn.ToCharArray() | ForEach-Object { '{0:X4}' -f [int]$_ }) -join ' ')"

    $rNl = Get-LwgRedacted -Text "first half`nsecond half"
    Add-Result 'redact: a newline cannot end the row' `
        ((Test-LwgIsCleanField $rNl) -and $rNl -eq 'first half\nsecond half') `
        "bin\lwg-resolve.ps1 prints this value into a fixed-column report one row per fault, and the text inside it is a failed task's stderr. A raw newline splits one record into two ROWS, and the second row is a fault record the operator never had. got: $rNl"

    $rCrTab = Get-LwgRedacted -Text "a`r`nb`tc"
    Add-Result 'redact: CR and TAB are escaped too' `
        ((Test-LwgIsCleanField $rCrTab) -and $rCrTab -eq 'a\r\nb\tc') `
        "a bare CR returns the cursor to the start of the row and overwrites what is already printed there, which is worse than a newline rather than milder. got: $rCrTab"

    $rCtl = Get-LwgRedacted -Text ('x' + [char]0 + [char]27 + '[31mred')
    Add-Result 'redact: NUL and ESC are escaped as \xHH' `
        ((Test-LwgIsCleanField $rCtl) -and $rCtl -eq 'x\x00\x1B[31mred') `
        "an ESC reaches the operator's terminal as an escape sequence and can repaint or erase what is on it. got: $rCtl"

    $rTrail = Get-LwgRedacted -Text "git said no`r`n"
    Add-Result 'redact: a trailing newline is trimmed rather than escaped into the message' `
        ((Test-LwgIsCleanField $rTrail) -and $rTrail -eq 'git said no') `
        "captured stderr almost always ends in one, and bin\lwg-evidence.ps1 builds a one-sentence checklist detail out of this value. Escaping it would put a visible \r\n on the end of nearly every message, where the caller's Trim() cannot reach it - a literal backslash-n is not whitespace. got: $rTrail"

    $rOnce  = Get-LwgRedacted -Text ("see " + $rTok + " and password: swordfish99 and`na newline and " + ('z' * 300))
    $rTwice = Get-LwgRedacted -Text $rOnce
    Add-Result 'redact: redacting an already-redacted value changes nothing' `
        ($rOnce -eq $rTwice) `
        "CANNOT GO RED - it was idempotent before as well. It is pinned because a value is routinely redacted on the way into a log and again on the way out of one, and a function that ate a character per pass would rewrite history slowly. got:`n  once : $rOnce`n  twice: $rTwice"

    Add-Result 'redact: an empty string and $null both return an empty string' `
        ((Get-LwgRedacted -Text '') -eq '' -and (Get-LwgRedacted -Text $null) -eq '' -and
         (Get-LwgRedacted -Text $null) -is [string]) `
        'CANNOT GO RED. Callers interpolate the result straight into a record, so $null must come back as a string rather than as the word null or as nothing at all'

    $rLong = Get-LwgRedacted -Text ('ghp_' + ('B' * 500))
    Add-Result 'redact: a very long single token leaves nothing of itself' `
        ($rLong -eq '[REDACTED:github_token]' -and $rLong -notmatch 'BBBB') `
        "CANNOT GO RED. Redaction runs BEFORE truncation, and this is the case that depends on it: truncating first would have left 200 characters of the credential standing in the field. got: $rLong"

    $rMarker = Get-LwgRedacted -Text ('[REDACTED:github_token] then a real one ' + $rTok)
    Add-Result 'redact: the marker text in the INPUT is passed through, and a real credential beside it is still caught' `
        ($rMarker -eq ('[REDACTED:github_token] then a real one [REDACTED:github_token]')) `
        "CANNOT GO RED, and it is a LIMITATION being pinned rather than a property being celebrated: the marker is not authenticated, so text that was written to look like a redaction reads exactly like one that happened. What must hold is that its presence does not stop the scan. got: $rMarker"

    # ----------------------------------------------------------------------
    # THE SHAPES THE GENERIC RULE COULD NOT SEE, one case each
    # ----------------------------------------------------------------------
    # WHY THIS BLOCK EXISTS AT ALL, given the fifteen cases above it: not one
    # of those fifteen is quoted, JSON-shaped or a header. They pin the shape
    # that ALREADY WORKED - a bare `key: value` with the separator touching the
    # key name - and the rule in force until 3 August 2026 required exactly
    # that. A single quote defeated it. So the suite was green, the docs said
    # the redaction existed, and four shapes went through untouched.
    #
    # AND THE PLUGIN BUILDS ONE OF THEM ITSELF. lib\supervisor.ps1's
    # ConvertTo-SafeField pipes every non-scalar payload field through
    # ConvertTo-Json -Compress and hands the resulting string straight to
    # Get-LwgRedacted, so {"api_key":"..."} - a quoted key - is what that
    # function was actually being asked to read on the health.jsonl path. C9 in
    # section C runs that path for real. These call the helper directly, ONE
    # SHAPE PER CASE, so a failure names the shape rather than the module.
    #
    # EACH OF THE SEVEN BELOW WAS CONFIRMED RED AT fd8d023 INDIVIDUALLY, by
    # dropping this block into that tree's copy of this file and running it.
    # The two after them cannot go red there and say so themselves.
    #
    # Specimens are assembled from pieces at runtime and never written as
    # literals - the same rule the note above $script:LwgSecretPatterns follows.
    $rSecret = 'sk-live-' + 'abcdef1234567890'
    $rJwt    = 'eyJhbGciOiJIUzI1NiJ9' + '.' + 'payloadpart'
    $rBear   = 'abcdef1234567890' + 'abcdef'

    $rJson = Get-LwgRedacted -Text ('{"api_key": "' + $rSecret + '"}')
    Add-Result 'redact: a JSON-quoted key and value is masked, and what is left is still JSON-shaped' `
        ($rJson -eq '{"api_key": "[REDACTED]"}' -and $rJson -notlike ('*' + $rSecret + '*')) `
        "REGRESSION: the generic rule required the key name to be followed IMMEDIATELY by a colon or an equals sign, so the closing quote of a JSON key defeated it and this went into health.jsonl unchanged. Masking must also stop at the quote rather than eating the rest of the object. got: $rJson"

    $rJsonTight = Get-LwgRedacted -Text ('{"token":"' + $rJwt + '"}')
    Add-Result 'redact: a compact JSON key with a JWT-shaped value is masked' `
        ($rJsonTight -eq '{"token":"[REDACTED]"}' -and $rJsonTight -notlike ('*payloadpart*')) `
        "REGRESSION: this is the exact output ConvertTo-Json -Compress produces - no space anywhere - and it is what lib\supervisor.ps1 hands this function. A JWT is not covered by any of the five vendor patterns, so the generic rule is the only thing that could have caught it, and it did not. got: $rJsonTight"

    $rJsonEsc = Get-LwgRedacted -Text ('{"error":"{\"api_key\":\"' + $rSecret + '\"}"}')
    Add-Result 'redact: a DOUBLY escaped JSON field is masked without wrecking the escaping' `
        ($rJsonEsc -eq '{"error":"{\"api_key\":\"[REDACTED]\"}"}' -and $rJsonEsc -notlike ('*' + $rSecret + '*')) `
        "REGRESSION, and it is the shape a real record takes: a payload field that is ITSELF a JSON string comes back from ConvertTo-Json with its quotes escaped, so the quote around the value has a backslash in front of it. A value pattern that swallowed the backslash would mask the credential and leave a malformed record behind. got: $rJsonEsc"

    $rAuth = Get-LwgRedacted -Text ('Authorization: Bearer ' + $rBear)
    Add-Result 'redact: an Authorization header masks the TOKEN and keeps the scheme word' `
        ($rAuth -eq 'Authorization: Bearer [REDACTED]' -and $rAuth -notlike ('*' + $rBear + '*')) `
        "REGRESSION, AND THE ONE THAT KILLS THE OBVIOUS FIX. Adding authorization and bearer to the keyword list makes the keyword match and then lets the VALUE group capture the literal word Bearer - six characters, which clears the {6,} floor - and stop at the space. The output is then 'Authorization: [REDACTED] <token>': a green-looking marker with the credential still standing next to it, which is worse than no redaction at all. A header needs its own rule whose prefix CONSUMES the scheme word. got: $rAuth"

    $rAuthJson = Get-LwgRedacted -Text ('{"Authorization":"Bearer ' + $rBear + '"}')
    Add-Result 'redact: an Authorization header inside a JSON object is masked too' `
        ($rAuthJson -eq '{"Authorization":"Bearer [REDACTED]"}' -and $rAuthJson -notlike ('*' + $rBear + '*')) `
        "REGRESSION. Both defeats at once - the quote AND the scheme word - and this is how a header reaches the log in practice, because git and gh print request headers into stderr and lib\stop_advisories.ps1 puts that stderr through this function. got: $rAuthJson"

    $rEnv = Get-LwgRedacted -Text ('export SECRET_VALUE=' + $rBear)
    Add-Result 'redact: a name that CONTAINS the keyword rather than ending with it is masked' `
        ($rEnv -eq 'export SECRET_VALUE=[REDACTED]' -and $rEnv -notlike ('*' + $rBear + '*')) `
        "REGRESSION, missed by exactly one character: the old rule anchored the separator to the end of the keyword, so 'SECRET=' matched and 'SECRET_VALUE=' did not. Every prefixed environment variable an operator actually sets - GITHUB_TOKEN, MY_API_KEY_ID - is this shape. got: $rEnv"

    $rUrl = Get-LwgRedacted -Text ('fatal: https://alice:hunter2secret@example.invalid/x.git not found')
    Add-Result 'redact: a password in a URL userinfo is masked, and a plain remote URL is left alone' `
        ($rUrl -eq 'fatal: https://alice:[REDACTED]@example.invalid/x.git not found' -and
         (Get-LwgRedacted -Text 'remote: https://example.invalid/owner/repo.git') -eq 'remote: https://example.invalid/owner/repo.git') `
        "REGRESSION. A credential with NO KEY NAME AT ALL, which neither the keyword rule nor the header rule can see - and git and gh print remote URLs into stderr on nearly every failure, which bin\lwg-evidence.ps1 and lib\stop_advisories.ps1 feed straight to this function. The second half is the guard: the rule keys on a colon-delimited userinfo followed by an at-sign, so an ordinary remote URL must come back untouched. got: $rUrl"

    $rShapeOnce  = Get-LwgRedacted -Text ('{"api_key":"' + $rSecret + '","Authorization":"Bearer ' + $rBear + '"}')
    $rShapeTwice = Get-LwgRedacted -Text $rShapeOnce
    Add-Result 'redact: the new shapes survive a second pass unchanged' `
        ($rShapeOnce -eq $rShapeTwice) `
        "CANNOT GO RED AT fd8d023 - the shapes were unchanged there, so a second pass changed nothing either, and this passes against the defect. It is here because it goes red against two REPAIRS that look right: a value pattern admitting an opening bracket re-matches the marker [REDACTED] on the second pass, and a header rule with an optional scheme word and no guard takes the word Bearer itself as the value once the token behind it is gone. Both were observed while building this fix. got:`n  once : $rShapeOnce`n  twice: $rShapeTwice"

    $rBenign = '{"ts":"2026-01-01T00:00:00Z","event":"Stop","session_id":"lwg-1","tool_name":"Bash","cwd":"C:/repo","failed_tasks":1}'
    Add-Result 'redact: an ordinary health record passes through with nothing masked' `
        ((Get-LwgRedacted -Text $rBenign -MaxLength 400) -eq $rBenign) `
        "CANNOT GO RED AT fd8d023 - nothing was masked there either. It is the BLAST-RADIUS guard on the rules above, and the direction they fail in is over-redaction: the keyword may now be followed by more identifier, so a wider keyword list would start masking session_id, tool_name and failed_tasks - the fields the status line and bin\lwg-resolve.ps1 exist to read. got: $(Get-LwgRedacted -Text $rBenign -MaxLength 400)"

    # ----------------------------------------------------------------------
    # A10-A13: THE FOUR SHAPES THE 3 AUGUST RULES CLAIMED AND DID NOT HAVE
    # ----------------------------------------------------------------------
    # THE BASELINE IS NOT THE SAME FOR ALL FOUR, AND CLAIMING ONE FOR ALL OF
    # THEM WOULD BE THE OVERSTATEMENT THIS BLOCK EXISTS TO REMOVE. All four were
    # confirmed red against the WORKING TREE as it stood after the four parallel
    # fixes landed and before this one - a filesystem copy of that tree, this
    # block spliced in, run once. Against fd8d023 they DIFFER, and the
    # difference was MEASURED, by putting the same specimens through all three
    # copies of lib\common.ps1, rather than reasoned about from the diff:
    #
    #                        fd8d023    pre-fix tree   this tree
    #   Bearer token-...     unmasked   unmasked       masked
    #   array head           unmasked   unmasked       masked
    #   newline, raw         MASKED     unmasked       masked
    #   newline, escaped     MASKED     unmasked       masked
    #   PEM body             unmasked   unmasked       masked
    #
    # So three of these cases go red at fd8d023 as well - and the NEWLINE one
    # does NOT. It PASSES there, because the rule fd8d023 shipped crossed a
    # newline and the rule that replaced it stopped doing so. That case is a
    # regression against the 3 August rewrite specifically, and calling it an
    # fd8d023 regression would be false in the direction that flatters this fix.
    #
    # WHY THEY EXIST: every one of the four was published as covered. Three were
    # written into Get-LwgRedacted's docstring or SECURITY.md as an unqualified
    # affirmative; the fourth was published as a pure gain over a rule that
    # actually did more. A documented claim with no case behind it is what this
    # suite exists to stop, and the fifteen cases above were all green over all
    # four of these.
    $rSchemeVal = 'token-' + '9f3a2b7c8d'
    $rSchemeOut = Get-LwgRedacted -Text ('Authorization: Bearer ' + $rSchemeVal)
    $rSchemeBare = Get-LwgRedacted -Text ('Authorization: ' + 'basic-auth-' + '9f3a2b7c')
    Add-Result 'redact: an Authorization value that BEGINS with a scheme word is still masked' `
        ($rSchemeOut -eq 'Authorization: Bearer [REDACTED]' -and $rSchemeOut -notlike ('*' + $rSchemeVal + '*') -and
         $rSchemeBare -eq 'Authorization: [REDACTED]') `
        "REGRESSION. Red against the working tree, and MEASURED red at fd8d023 too - though for a different reason there, since fd8d023 had no header rule at all and simply never looked. The rule's idempotency guard ended in \b, which fires between a scheme word and ANY non-word character, so a value merely BEGINNING with one of the five words disqualified itself; the engine then retried with the optional scheme group skipped and disqualified the scheme word too, and the rule matched NOWHERE. A hyphen was all it took, and an issuer prefixing a token with 'token-' is ordinary. Both the docstring and SECURITY.md stated this shape as covered while it went through in the clear. got: $rSchemeOut / $rSchemeBare"

    $rSchemeNl  = 'eyJhbGciOiJIUzI1NiJ9' + 'sekrit'
    $rSchemeNlA = Get-LwgRedacted -Text ('Authorization: bearer' + "`n" + $rSchemeNl) -MaxLength 400
    $rSchemeNlB = Get-LwgRedacted -Text ('Proxy-Authorization: digest' + "`r`n" + $rSchemeNl) -MaxLength 400
    Add-Result 'redact: a scheme word that ENDS A LINE does not become the value' `
        ($rSchemeNlA -notlike ('*' + $rSchemeNl + '*') -and $rSchemeNlB -notlike ('*' + $rSchemeNl + '*') -and
         $rSchemeNlA -like '*bearer*' -and $rSchemeNlB -like '*digest*') `
        "REGRESSION AGAINST THE FIRST VERSION OF THIS SESSION'S OWN REPAIR, kept because it is the worst output this rule can produce and nothing else here reaches it. Replacing the guard's \b with (?:[ \t]|`$) fixed a value that BEGINS with a scheme word and opened a value that FOLLOWS one across a newline: the scheme group could not consume 'bearer' plus a newline, so it was skipped, and the guard did not fire on a newline either, so the literal word 'bearer' cleared the six-character floor and was taken as the value. Measured output was 'Authorization: [REDACTED]<newline><token>' - the scheme word masked, the credential standing, and a green-looking marker in front of it saying the opposite, which the rule's own comment calls worse than no redaction at all. The second half of each assertion pins that the SCHEME WORD is still left in the clear, because which scheme was used is evidence and is not the secret. got:`n  A: $rSchemeNlA`n  B: $rSchemeNlB"

    $rPemBody = 'MIIEowIBAAKCAQEA' + '0aqrstuvwxyz/3dfghjklzxcv' + 'bnmqwertyuio+mnbvcxzlkjhg'
    $rPemOut  = Get-LwgRedacted -Text ("-----BEGIN RSA PRIVATE KEY-----`n$rPemBody`n-----END RSA PRIVATE KEY-----") -MaxLength 400
    $rPemTrunc = Get-LwgRedacted -Text ("-----BEGIN RSA PRIVATE KEY-----`n$rPemBody") -MaxLength 400
    Add-Result 'redact: a PEM block loses its BODY, not just its BEGIN line' `
        ($rPemOut -eq '[REDACTED:private_key]' -and $rPemOut -notlike '*MIIEow*' -and
         $rPemTrunc -like '[[]REDACTED:private_key[]]*' -and $rPemTrunc -like '*MIIEow*') `
        "REGRESSION, and it goes red at fd8d023 TOO - this gap predates the 3 August rules and was carried forward by them. The vendor pattern replaced the marker LINE and left every base64 byte standing behind it, which is a redaction that redacts nothing of value. It is worst on the mission_drift path: Add-LwgMissionAnchors reads / as a PATH SEPARATOR, / is in the base64 alphabet, so a surviving body was PROMOTED to the anchor kind the advisory QUOTES BACK. The second half of this assertion is the deliberate boundary: a block with no END line still loses only its BEGIN line, exactly as before, because making the trailing group mandatory would have meant a truncated key matching nothing at all. got: $rPemOut / $rPemTrunc"

    $rArrVal = 'sk-live-' + 'ARR4Yr3d4ct10nG4p'
    $rArrOut = Get-LwgRedacted -Text ('{"api_key":["' + $rArrVal + '"]}')
    $rArrIdem = Get-LwgRedacted -Text $rArrOut
    Add-Result 'redact: a credential as the HEAD of a JSON array is masked, and the marker is not re-eaten' `
        ($rArrOut -eq '{"api_key":["[REDACTED]"]}' -and $rArrOut -notlike ('*' + $rArrVal + '*') -and
         $rArrIdem -eq $rArrOut -and (Get-LwgRedacted -Text 'api_key: [REDACTED]') -eq 'api_key: [REDACTED]') `
        "REGRESSION. Red against the working tree, and MEASURED red at fd8d023 too - this shape has never been masked by anything here. ConvertTo-Json -Depth 4 -Compress manufactures ARRAYS as readily as quoted scalars, and the separator's optional quote could not match [ while the value class excludes it, so the rule found NO start position anywhere in the string and the whole record went through untouched. The last two assertions are the trap: admitting a bare \[? closes this shape AND BREAKS IDEMPOTENCY - it was tried, and 'api_key: [REDACTED]' came back 'api_key: [[REDACTED]]' on the second pass. The bracket is admitted only when an opening quote follows it, which an array of strings always has and the marker never does. got: $rArrOut"

    $rNlVal  = 'sk-live-' + 'NEWL1NEr3gr3ss10n'
    $rNlRaw  = Get-LwgRedacted -Text ("remote: rejected`ntoken:`n$rNlVal") -MaxLength 400
    $rNlEsc  = Get-LwgRedacted -Text ('remote: rejected\ntoken:\n' + $rNlVal) -MaxLength 400
    $rNlIdem = Get-LwgRedacted -Text $rNlRaw -MaxLength 400
    Add-Result 'redact: a newline between the key and the value is crossed, raw and JSON-escaped alike' `
        ($rNlRaw -notlike ('*' + $rNlVal + '*') -and $rNlEsc -notlike ('*' + $rNlVal + '*') -and
         $rNlRaw -like '*[[]REDACTED[]]*' -and $rNlEsc -like '*[[]REDACTED[]]*' -and $rNlIdem -eq $rNlRaw) `
        "REGRESSION, AND IT IS A STEP THIS TREE TOOK BACKWARDS - so unlike its three neighbours this case PASSES at fd8d023, measured, and only goes red against the 3 August rewrite. The rule fd8d023 shipped was \s*[:=]\s*(\S{6,}), which CROSSED a newline; the 3 August separator narrowed that to [ \t]{0,8} to kill a false positive, and eight shapes the old rule masked stopped being masked. This one is REACHABLE - lib\supervisor.ps1 pipes a payload field through ConvertTo-Json, which turns a real newline into backslash-n, so a multi-line error.stderr whose key ends a line arrives here in the escaped spelling. It was published as a pure gain. The last assertion is why BOTH spellings are admitted rather than the escaped one alone: this function escapes control characters AFTER redacting, so with only \\n admitted a raw value passed pass 1 in the clear and was masked on pass 2 - the output moved between passes, which this file pins as a property. got:`n  raw: $rNlRaw`n  esc: $rNlEsc"

    # =====================================================================
    # SECTION B - mission_drift, END TO END
    # =====================================================================
    Write-Output 'B. mission_drift (child process)'

    $bDir = Join-Path $work 'b'
    [void][IO.Directory]::CreateDirectory($bDir)

    function New-LwgMissionCase {
        <#
          One case's world:

            <case>\root\           throwaway plugin root, holding config.json
            <case>\root\data\      throwaway state dir (CLAUDE_PLUGIN_DATA)
            <case>\ws\             the workspace - the payload's cwd
            <case>\outside\        a SIBLING of ws, where the unaccounted work goes
            <case>\transcript.jsonl

          THE SIBLING PLACEMENT IS LOAD-BEARING. Get-LwgMissionScope stop-lists
          every path segment at or above the workspace's PARENT, so a tree
          placed above <case> would share <case>'s own segment with ws and be
          excused by it - the case would then pass for the wrong reason, or
          never fire at all. As a sibling, the only segments the outside tree
          contributes are its own.

          ws has no .git, so Get-LwgRepoInfo resolves no root and the workspace
          root falls back to the payload's cwd - the same path either way, but
          reached by the branch a session outside a repository takes.
        #>
        param([string]$Name, [hashtable]$Knobs, [hashtable]$Modules)

        $dir = Join-Path $bDir $Name
        $c = @{
            name    = $Name
            dir     = $dir
            root    = (Join-Path $dir 'root')
            data    = (Join-Path $dir 'root\data')
            ws      = (Join-Path $dir 'ws')
            outside = (Join-Path $dir 'outside')
            tx      = (Join-Path $dir 'transcript.jsonl')
            session = ('lwg-stop-' + $Name)
        }
        foreach ($d in @($c.dir, $c.root, $c.data, $c.ws, $c.outside)) { [void][IO.Directory]::CreateDirectory($d) }
        $c['key']   = Get-LwgSessionKey -SessionId $c.session
        $c['state'] = Join-Path $c.data ("advisory-" + $c.key + '.json')

        # mission_drift alone unless a case asks for more. B23 needs
        # docs_coupling as well, because the systemMessage it bounds is
        # docs_coupling's; every other case here would be testing a second
        # module by accident if that were the default.
        $mods = $(if ($null -ne $Modules) { $Modules } else { @{ mission_drift = $true } })
        Write-LwgFixtureConfig -Dir $c.root -Modules $mods -MissionKnobs $Knobs
        [IO.File]::WriteAllText($c.tx, '', [Text.UTF8Encoding]::new($false))
        return $c
    }

    function Add-LwgPrompt {
        <#
          Append one typed-prompt record. The shape is the one the module
          filters for: type user, a string content, no toolUseResult, no
          isSidechain. Built through ConvertTo-Json so a Windows path in the
          text is escaped correctly rather than by hand.
        #>
        param($Case, [string]$Text)
        $rec = [ordered]@{ type = 'user'; message = [ordered]@{ content = $Text } }
        [IO.File]::AppendAllText($Case.tx, (($rec | ConvertTo-Json -Depth 6 -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
    }

    function Add-LwgNonPrompt {
        <# Records the prompt filter must reject, plus bulk for the byte cap. #>
        param($Case, [int]$Count = 1)
        for ($i = 0; $i -lt $Count; $i++) {
            $rec = [ordered]@{
                type    = 'user'
                toolUseResult = [ordered]@{ stdout = ('filler ' + ('z' * 120)) }
                message = [ordered]@{ content = 'tool output, not a prompt' }
            }
            [IO.File]::AppendAllText($Case.tx, (($rec | ConvertTo-Json -Depth 6 -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
        }
    }

    function Set-LwgEdits {
        <#
          Seed the per-session edit list lib\post_edit.ps1 writes on PostToolUse
          and lib\stop_advisories.ps1 reads at turn end - one path per line, in
          edits-<sessionkey>.txt under the state dir. The file NAME is part of
          the contract between those two scripts; it is spelled the same way
          here as in both of them.
        #>
        param($Case, [string[]]$Paths)
        [IO.File]::WriteAllText((Join-Path $Case.data ('edits-' + $Case.key + '.txt')),
            (($Paths -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    }

    function Invoke-LwgStop {
        param($Case, [string]$Tag, [switch]$StopHookActive, [string]$PathOverride)
        $parts = @(
            ('"session_id":"' + $Case.session + '"')
            ('"transcript_path":"' + ($Case.tx -replace '\\', '/') + '"')
            ('"cwd":"' + ($Case.ws -replace '\\', '/') + '"')
            '"hook_event_name":"Stop"'
        )
        if ($StopHookActive) { $parts += '"stop_hook_active":true' }
        return (Invoke-LwgHook -ScriptPath $AdvisoryPath -Payload ('{' + ($parts -join ',') + '}') `
                    -PluginRoot $Case.root -DataDir $Case.data -WorkDir $Case.dir -Tag $Tag `
                    -PathOverride $PathOverride)
    }

    function Invoke-LwgPostEdit {
        <#
          Run lib\post_edit.ps1 once, as the CLI runs it: a PostToolUse payload
          carrying one tool_input.file_path, against the case's throwaway root
          and state dir. The recording half of docs_coupling and mission_drift
          was driven by no case in this suite until B22/B23; every earlier case
          seeds edits-<key>.txt by hand through Set-LwgEdits, which tests the
          reader and never the writer.

          The path is embedded through ConvertTo-Json so a Windows path - or a
          200 000-character one - is escaped rather than hand-quoted.
        #>
        param($Case, [string]$Path, [string]$Tag)
        $payload = ([ordered]@{
            session_id      = $Case.session
            cwd             = ($Case.ws -replace '\\', '/')
            hook_event_name = 'PostToolUse'
            tool_name       = 'Write'
            tool_input      = [ordered]@{ file_path = $Path }
        } | ConvertTo-Json -Depth 6 -Compress)
        return (Invoke-LwgHook -ScriptPath $PostEditPath -Payload $payload `
                    -PluginRoot $Case.root -DataDir $Case.data -WorkDir $Case.dir -Tag $Tag)
    }

    function Get-LwgCaseEditLines {
        param($Case)
        $p = Join-Path $Case.data ('edits-' + $Case.key + '.txt')
        if (-not [IO.File]::Exists($p)) { return @() }
        return @([IO.File]::ReadAllLines($p) | Where-Object { $_.Length -gt 0 })
    }

    function Get-LwgCaseState {
        param($Case)
        $h = @{}
        try {
            if ([IO.File]::Exists($Case.state)) {
                $o = [IO.File]::ReadAllText($Case.state) | ConvertFrom-Json
                foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = $p.Value }
            }
        } catch { }
        return $h
    }

    function Test-LwgMissionAdvisory {
        <#
          Did this run emit the mission advisory? The contract, in full:

            exit 0        ALWAYS. An advisory that exits nonzero on Stop blocks
                          the turn, and these must never block.
            stdout        one JSON envelope, {systemMessage, suppressOutput}
            systemMessage carries "LW-WATCHTOWER mission:"
            stderr        empty - the advisory channel is stdout
        #>
        param($R)
        if ($R.code -ne 0) { return @{ ok = $false; why = "exited $($R.code); an advisory must exit 0 on every path or it blocks the turn" } }
        if (-not [string]::IsNullOrWhiteSpace($R.err)) { return @{ ok = $false; why = "wrote to stderr: $($R.err)" } }
        $env0 = $null
        try { $env0 = $R.out | ConvertFrom-Json } catch { }
        if ($null -eq $env0) { return @{ ok = $false; why = "stdout did not parse as JSON: [$($R.out)]" } }
        if ([string]$env0.systemMessage -notlike '*LW-WATCHTOWER mission:*') {
            return @{ ok = $false; why = "the envelope carries no mission advisory: $($R.out)" }
        }
        if ($env0.suppressOutput -ne $true) { return @{ ok = $false; why = 'suppressOutput is not true, so the raw envelope would be shown to the user' } }
        return @{ ok = $true; why = ''; env = $env0 }
    }

    function Test-LwgSilent {
        <# Did this run stay out of the way? Exit 0 and not one byte emitted. #>
        param($R)
        if ($R.code -ne 0) { return @{ ok = $false; why = "exited $($R.code), expected 0" } }
        if (-not [string]::IsNullOrWhiteSpace($R.out)) { return @{ ok = $false; why = "wrote to stdout when it should have been silent: $($R.out)" } }
        if (-not [string]::IsNullOrWhiteSpace($R.err)) { return @{ ok = $false; why = "wrote to stderr when it should have been silent: $($R.err)" } }
        return @{ ok = $true; why = '' }
    }

    # The three unaccounted files every firing case uses. Invented names that
    # share no segment, stem or word with any prompt text below - which is the
    # only reason they are unaccounted, and is checked by B2 turning them
    # accounted with one prompt.
    function Get-LwgOutsideEdits {
        param($Case, [int]$Count = 3)
        # Five and six exist for B20, which adds one file per turn to show the
        # dedupe does not re-fire on growth. Appended rather than inserted:
        # every existing caller asks for 2, 3 or 4 and takes the same first N.
        $all = @('crimson_one.ps1', 'crimson_two.ps1', 'crimson_three.ps1', 'crimson_four.ps1',
                 'crimson_five.ps1', 'crimson_six.ps1')
        return @($all | Select-Object -First $Count | ForEach-Object { Join-Path $Case.outside $_ })
    }

    # --- B1: it fires ----------------------------------------------------
    $b1 = New-LwgMissionCase -Name 'b1' -Knobs @{ min_files = 3; require_outside_root = $true; max_scan_bytes = 2097152; max_anchors = 400 }
    Add-LwgPrompt -Case $b1 -Text ("Rework the header handling in " + (Join-Path $b1.ws 'module\parser.ps1') + " and keep it readable.")
    Set-LwgEdits -Case $b1 -Paths (Get-LwgOutsideEdits -Case $b1 -Count 3)
    $rb1 = Invoke-LwgStop -Case $b1 -Tag 'b1-run1'
    $vb1 = Test-LwgMissionAdvisory $rb1
    Add-Result 'B1: three unaccounted edits outside the workspace -> advisory, exit 0' $vb1.ok `
        ("$($vb1.why)  --  the operator named one file inside the workspace and every edit landed in a sibling tree sharing nothing with it. This is the whole trigger")

    # `@($x).Count -gt 0` IS NOT A PRESENCE TEST IN WINDOWS POWERSHELL, which is
    # what this assertion used for md_paths. `@($null).Count` is 1, and an
    # absent hashtable key reads as $null, so `@($sb1['md_paths']).Count -gt 0`
    # was TRUE on a state file with no md_paths in it at all - the one thing the
    # case is named for was the one conjunct that could not fail. Measured: with
    # the persistence write mutated to `$state.Remove('md_paths')` this row and
    # B2 turn 1 both reported ok, and the break surfaced three turns downstream
    # in B2 turn 3, whose failure text is about a warning being emitted and
    # sends a reader to the assessment logic rather than to the state write.
    #
    # SO ASSERT THE CONTENTS, not the count. The fixture knows what the anchor
    # should be: the prompt above names module\parser.ps1, so `parser` and
    # `module` are the anchors that prompt produces, and a set that holds
    # neither is not "the anchors" whatever its length. The other two conjuncts
    # were always sound - [long]$null is 0 and IsNullOrWhiteSpace on an absent
    # key is true - and are unchanged.
    $sb1 = Get-LwgCaseState $b1
    $sb1Paths = @(); if ($null -ne $sb1['md_paths']) { $sb1Paths = @($sb1['md_paths']) }
    Add-Result 'B1: the state file carries the anchors, the offset and the warned signature' `
        (($sb1Paths -contains 'parser') -and ($sb1Paths -contains 'module') -and
         [long]$sb1['md_offset'] -gt 0 -and
         -not [string]::IsNullOrWhiteSpace([string]$sb1['md_sig'])) `
        ("without md_paths the next turn re-derives nothing, without md_offset it re-reads the whole transcript, and without md_sig it repeats the same warning at every turn end. got md_paths [" + ($sb1Paths -join ', ') + "]; full state: " + ([IO.File]::ReadAllText($b1.state)))

    # --- B8: it never blocks ---------------------------------------------
    # Asserted on the envelope B1 actually emitted rather than on a fresh run.
    # On Stop a hook blocks by exiting 2 or by printing {"decision":"block"};
    # this envelope must have no decision member at all, and the exit code is
    # already asserted above.
    if ($vb1.ok) {
        $hasDecision = $false
        try { $hasDecision = ($null -ne ($vb1.env.PSObject.Properties | Where-Object { $_.Name -eq 'decision' })) } catch { }
        Add-Result 'B8: the advisory envelope carries NO decision member' `
            ((-not $hasDecision) -and $rb1.out -notlike '*decision*') `
            "a decision member would make this advisory able to block a turn end, which no module in this plugin may do: $($rb1.out)"
    }

    # --- B7: warn once ---------------------------------------------------
    $rb7 = Invoke-LwgStop -Case $b1 -Tag 'b1-run2'
    $vb7 = Test-LwgSilent $rb7
    Add-Result 'B7: the same unaccounted set does not warn twice' $vb7.ok `
        ("$($vb7.why)  --  a standing condition repeated at every turn end trains the reader to ignore the channel")

    # --- B2: a pivot cannot trip it (the module's central claim) ---------
    # THIS IS THE CASE THE MODULE WAS DESIGNED AROUND and the one that had never
    # been run. Three turns, and the third is not padding:
    #
    #   turn 1  the operator names a file in the workspace. No edits yet.
    #   turn 2  the operator REDIRECTS to the outside tree by name, and the
    #           first three edits land there.
    #   turn 3  the operator says something that names only the ORIGINAL file
    #           again, and a fourth edit lands in the outside tree.
    #
    # Turn 3 is what distinguishes accumulation from per-turn anchors. In turn 2
    # the redirecting prompt is inside the same slice as the edits, so a module
    # that reset its anchors every turn would still see it and still stay quiet.
    # In turn 3 the only thing excusing the outside tree is an anchor from a
    # PREVIOUS turn - so if md_paths were not rehydrated from the state file,
    # turn 3 warns. That is the break this case was written against.
    $b2 = New-LwgMissionCase -Name 'b2' -Knobs @{ min_files = 3; require_outside_root = $true; max_scan_bytes = 2097152; max_anchors = 400 }
    Add-LwgPrompt -Case $b2 -Text ("Rework the header handling in " + (Join-Path $b2.ws 'module\parser.ps1') + " and keep it readable.")
    $rb2a = Invoke-LwgStop -Case $b2 -Tag 'b2-run1'
    $vb2a = Test-LwgSilent $rb2a
    Add-Result 'B2 turn 1: a prompt with no edits behind it says nothing' $vb2a.ok $vb2a.why

    # Same coercion, same repair as B1 above, and it matters more here: this is
    # the half of the B2 sequence that claims to read the state file, and the
    # block comment above says anchor persistence is what the whole sequence
    # exists to establish. Two conjuncts, one of which could not fail, means
    # half of this case was certifying nothing.
    $sb2a = Get-LwgCaseState $b2
    $sb2aPaths = @(); if ($null -ne $sb2a['md_paths']) { $sb2aPaths = @($sb2a['md_paths']) }
    Add-Result 'B2 turn 1: the anchors and the read offset are persisted' `
        (($sb2aPaths -contains 'parser') -and ($sb2aPaths -contains 'module') -and
         [long]$sb2a['md_offset'] -gt 0) `
        ('anchors that do not survive the turn cannot excuse work done in a later one, which is the entire pivot property. got md_paths [' + ($sb2aPaths -join ', ') + ']')

    Add-LwgPrompt -Case $b2 -Text ("Change of plan - move to " + (Join-Path $b2.outside 'crimson_one.ps1') + " and its siblings instead.")
    Set-LwgEdits -Case $b2 -Paths (Get-LwgOutsideEdits -Case $b2 -Count 3)
    $rb2b = Invoke-LwgStop -Case $b2 -Tag 'b2-run2'
    $vb2b = Test-LwgSilent $rb2b
    Add-Result 'B2 turn 2: work following an explicit redirection is not drift' $vb2b.ok `
        ("$($vb2b.why)  --  the redirecting prompt named the tree, so its nouns are anchors and the work matches them")

    $sb2b = Get-LwgCaseState $b2
    Add-Result 'B2 turn 2: the read offset advanced (the transcript is read incrementally)' `
        ([long]$sb2b['md_offset'] -gt [long]$sb2a['md_offset']) `
        "offset went $($sb2a['md_offset']) -> $($sb2b['md_offset']); if it does not advance the module re-reads the whole transcript at every turn end, which is the cost this design exists to avoid"

    Add-LwgPrompt -Case $b2 -Text ("Keep the header shape from " + (Join-Path $b2.ws 'module\parser.ps1') + " while you are in there.")
    Set-LwgEdits -Case $b2 -Paths (Get-LwgOutsideEdits -Case $b2 -Count 4)
    $rb2c = Invoke-LwgStop -Case $b2 -Tag 'b2-run3'
    $vb2c = Test-LwgSilent $rb2c
    Add-Result 'B2 turn 3: an anchor from an EARLIER turn still excuses the work' $vb2c.ok `
        ("$($vb2c.why)  --  nothing in this turn's slice names the outside tree. Only the anchors carried over from turn 2 can excuse it, so a warning here means anchors are not accumulating and every mid-session pivot would be reported as drift")

    # --- B3: the min_files floor -----------------------------------------
    $b3 = New-LwgMissionCase -Name 'b3' -Knobs @{ min_files = 3; require_outside_root = $true; max_scan_bytes = 2097152; max_anchors = 400 }
    Add-LwgPrompt -Case $b3 -Text ("Rework the header handling in " + (Join-Path $b3.ws 'module\parser.ps1') + ".")
    Set-LwgEdits -Case $b3 -Paths (Get-LwgOutsideEdits -Case $b3 -Count 2)
    $vb3 = Test-LwgSilent (Invoke-LwgStop -Case $b3 -Tag 'b3-run1')
    Add-Result 'B3: fewer than min_files unaccounted edits stays silent' $vb3.ok `
        ("$($vb3.why)  --  two stray files is a task reaching one directory sideways, which happens constantly and must not warn")

    # --- B4: require_outside_root ----------------------------------------
    $b4 = New-LwgMissionCase -Name 'b4' -Knobs @{ min_files = 3; require_outside_root = $true; max_scan_bytes = 2097152; max_anchors = 400 }
    Add-LwgPrompt -Case $b4 -Text ("Rework the header handling in " + (Join-Path $b4.ws 'module\parser.ps1') + ".")
    Set-LwgEdits -Case $b4 -Paths @(
        (Join-Path $b4.ws 'crimson_one.ps1')
        (Join-Path $b4.ws 'crimson_two.ps1')
        (Join-Path $b4.ws 'crimson_three.ps1'))
    $vb4 = Test-LwgSilent (Invoke-LwgStop -Case $b4 -Tag 'b4-run1')
    Add-Result 'B4: unrelated work INSIDE the workspace stays silent by default' $vb4.ok `
        ("$($vb4.why)  --  with require_outside_root true, being under the workspace root accounts for a file on its own. This is the module's largest deliberate false negative and it is a default, not an accident")

    # --- B10, B11: a non-boolean require_outside_root cannot disarm it ----
    # THE END-TO-END HALF OF THE modcfg CASES IN SECTION A, and the pair that
    # actually goes red against a pre-fix tree that runs rather than against a
    # missing function.
    #
    # Both are B4's world exactly - a prompt naming a file inside the workspace,
    # three edits inside the workspace whose names share nothing with it - so
    # with the suppressor ON they are accounted for and the run is silent. The
    # only thing changed is the SHAPE of require_outside_root's value.
    #
    # Pre-fix, the option was read as [bool] of whatever JSON held: [bool]0 and
    # [bool]'' are both $false, so the suppressor came back OFF, the three inside
    # edits became unaccounted, min_files was met and the module WARNED. An
    # operator who fat-fingered a 0 into a tuning key got a false positive from
    # the one module that is on by default, with nothing telling them the key
    # was the cause. Post-fix the value is not a boolean, so it is not a setting:
    # the shipped default $true stands and the run is silent again.
    $b10 = New-LwgMissionCase -Name 'b10' -Knobs @{ min_files = 3; require_outside_root = 0; max_scan_bytes = 2097152; max_anchors = 400 }
    Add-LwgPrompt -Case $b10 -Text ("Rework the header handling in " + (Join-Path $b10.ws 'module\parser.ps1') + ".")
    Set-LwgEdits -Case $b10 -Paths @(
        (Join-Path $b10.ws 'crimson_one.ps1')
        (Join-Path $b10.ws 'crimson_two.ps1')
        (Join-Path $b10.ws 'crimson_three.ps1'))
    $vb10 = Test-LwgSilent (Invoke-LwgStop -Case $b10 -Tag 'b10-run1')
    Add-Result 'B10: require_outside_root as the NUMBER 0 is ignored, and the suppressor holds' $vb10.ok `
        ("$($vb10.why)  --  identical to B4 but for the 0. [bool]0 is `$false, so this warned about three files inside the very workspace the operator named, on the strength of a typo in a tuning key")

    $b11 = New-LwgMissionCase -Name 'b11' -Knobs @{ min_files = 3; require_outside_root = ''; max_scan_bytes = 2097152; max_anchors = 400 }
    Add-LwgPrompt -Case $b11 -Text ("Rework the header handling in " + (Join-Path $b11.ws 'module\parser.ps1') + ".")
    Set-LwgEdits -Case $b11 -Paths @(
        (Join-Path $b11.ws 'crimson_one.ps1')
        (Join-Path $b11.ws 'crimson_two.ps1')
        (Join-Path $b11.ws 'crimson_three.ps1'))
    $vb11 = Test-LwgSilent (Invoke-LwgStop -Case $b11 -Tag 'b11-run1')
    Add-Result 'B11: require_outside_root as the EMPTY STRING is ignored, and the suppressor holds' $vb11.ok `
        ("$($vb11.why)  --  the same defect reached by the other coercion that lands on `$false. A key an operator quoted out of habit must not change what the module warns about")

    # --- B5: the truncated latch -----------------------------------------
    # A turn bigger than max_scan_bytes is SKIPPED, not partially read, and the
    # module then stays silent for the REST OF THE SESSION. The second run is
    # the one that matters: it is small enough to read, it carries a prompt that
    # would give the module standing, and it must still say nothing, because the
    # skipped region may have held the very prompt that would have excused this
    # work. Silence on incomplete evidence, never a guess.
    $b5 = New-LwgMissionCase -Name 'b5' -Knobs @{ min_files = 3; require_outside_root = $true; max_scan_bytes = 512; max_anchors = 400 }
    Add-LwgPrompt -Case $b5 -Text ("Rework the header handling in " + (Join-Path $b5.ws 'module\parser.ps1') + ".")
    Add-LwgNonPrompt -Case $b5 -Count 6
    Set-LwgEdits -Case $b5 -Paths (Get-LwgOutsideEdits -Case $b5 -Count 3)
    $vb5a = Test-LwgSilent (Invoke-LwgStop -Case $b5 -Tag 'b5-run1')
    Add-Result 'B5 turn 1: a turn larger than max_scan_bytes is skipped, and it is silent' $vb5a.ok $vb5a.why

    $sb5 = Get-LwgCaseState $b5
    Add-Result 'B5 turn 1: the incomplete flag is latched into the state file' `
        ($sb5['md_incomplete'] -eq $true -and [long]$sb5['md_offset'] -eq (Get-Item $b5.tx).Length) `
        "the skip must be recorded and the offset moved to EOF, or the next turn re-reads the same oversized region forever. got: $([IO.File]::ReadAllText($b5.state))"

    Add-LwgPrompt -Case $b5 -Text ("Carry on with " + (Join-Path $b5.ws 'module\parser.ps1') + ".")
    $vb5b = Test-LwgSilent (Invoke-LwgStop -Case $b5 -Tag 'b5-run2')
    Add-Result 'B5 turn 2: the latch holds for the rest of the session' $vb5b.ok `
        ("$($vb5b.why)  --  this turn is small, readable and carries a prompt with a path in it, so every condition for a warning is met EXCEPT that the module knows its picture of the session has a hole in it. Warning here would be judging on a partial record")

    # --- B6: no anchors, no standing -------------------------------------
    $b6 = New-LwgMissionCase -Name 'b6' -Knobs @{ min_files = 3; require_outside_root = $true; max_scan_bytes = 2097152; max_anchors = 400 }
    Add-LwgNonPrompt -Case $b6 -Count 2
    Set-LwgEdits -Case $b6 -Paths (Get-LwgOutsideEdits -Case $b6 -Count 3)
    $vb6 = Test-LwgSilent (Invoke-LwgStop -Case $b6 -Tag 'b6-run1')
    Add-Result 'B6: with no path named in any prompt it has no basis to judge' $vb6.ok `
        ("$($vb6.why)  --  a session whose only user records are tool results has named nothing, and a module with no idea what the work was supposed to touch must not guess")

    # --- B9: the loop guard ----------------------------------------------
    $b9 = New-LwgMissionCase -Name 'b9' -Knobs @{ min_files = 3; require_outside_root = $true; max_scan_bytes = 2097152; max_anchors = 400 }
    Add-LwgPrompt -Case $b9 -Text ("Rework the header handling in " + (Join-Path $b9.ws 'module\parser.ps1') + ".")
    Set-LwgEdits -Case $b9 -Paths (Get-LwgOutsideEdits -Case $b9 -Count 3)
    $b9Before = @()
    if ([IO.Directory]::Exists($b9.data)) { $b9Before = @([IO.Directory]::GetFileSystemEntries($b9.data)) }
    $rb9 = Invoke-LwgStop -Case $b9 -Tag 'b9-run1' -StopHookActive
    $vb9 = Test-LwgSilent $rb9
    Add-Result 'B9: stop_hook_active suppresses the whole run' $vb9.ok `
        ("$($vb9.why)  --  stop_hook_active means some hook already blocked this turn end once; re-running the advisories would repeat every warning for as long as that lasts")
    # THE WHOLE DIRECTORY, NOT ONE FILE IN IT. This asserted
    # `-not Exists($b9.state)` - advisory-<key>.json alone - while its own name
    # quantifies over the state dir. lib\stop_advisories.ps1 calls Write-LwgEvent
    # on a dozen paths and every one of them lands in lw-watchtower.jsonl in this same
    # directory, and health.jsonl is a third file. A loop guard that moved below
    # any of those - or below the module-resolution block, where a config
    # carrying a non-boolean flag writes a ConfigInvalidFlag record - would leave
    # those files while leaving advisory-<key>.json absent, and the only case
    # named for the guard's "before anything touches a file" contract would have
    # reported ok. Measured: with the guard moved below the module resolution,
    # the old assertion stayed green and this one goes red naming the file it
    # found.
    #
    # GetFileSystemEntries, NOT A LIST OF KNOWN FILENAMES. A named list is the
    # same defect one level up - it covers the writers somebody remembered. An
    # empty directory is the assertion the case name makes.
    #
    # WHICH HALF OF "read or written" IS ACTUALLY ASSERTED: the written half. A
    # filesystem check cannot see that a suppressed run opened
    # advisory-<key>.json for reading and closed it again. The name is kept
    # because the contract is about both; the limit is stated here rather than
    # left to be inferred, per this repository's standing practice.
    # The comparison is against a SNAPSHOT taken before the run, not against an
    # empty directory: Set-LwgEdits above seeds edits-<key>.txt into this same
    # directory, so "empty" would be wrong for a reason that has nothing to do
    # with the guard.
    $b9After = @()
    if ([IO.Directory]::Exists($b9.data)) { $b9After = @([IO.Directory]::GetFileSystemEntries($b9.data)) }
    $b9New = @($b9After | Where-Object { $b9Before -notcontains $_ })
    Add-Result 'B9: nothing was read or written under the state dir' `
        ($b9New.Count -eq 0) `
        ("the loop guard is checked before anything touches a file, so a suppressed run must leave no state behind. Only the WRITTEN half is asserted - a filesystem check cannot see a read. New entries after the run: " + ($b9New -join ', '))

    # --- B12-B15: a credential in a prompt reaches neither disk nor message
    # THIS MODULE IS THE ONLY ONE IN THE PLUGIN THAT READS WHAT THE OPERATOR
    # TYPED, and until the redaction at its ingest point landed it kept what it
    # read. The anchors it derives from a prompt are written verbatim, lowercased,
    # into advisory-<sessionkey>.json, and up to four of them are quoted back in
    # the systemMessage the hook prints at turn end. Neither copy went through
    # Get-LwgRedacted, and mission_drift is ON BY DEFAULT, so every install was
    # affected.
    #
    # TOKENISING IS NOT REDACTION, which is the assumption the defect rested on.
    # The tokeniser splits on whitespace and punctuation, and a credential
    # contains neither: the AWS-shaped specimen below is one unbroken
    # alphanumeric run pasted inside a path, so it survived the split as a PATH
    # SEGMENT - and a path anchor is the kind the advisory quotes. The assignment
    # specimen survived the same split as an ordinary word.
    #
    # ONE PROMPT, FOUR CASES, and two of them can go red. B13 and B14 are the
    # regression proper, one per destination. B12 and B15 are the guards that
    # stop the other two passing for the wrong reason: a "fix" that dropped the
    # prompt entirely - returning an empty string, or truncating at the default
    # 200 characters - would take the module's standing to speak with it, the
    # advisory would never fire, and a search of an empty message would find no
    # credential and report success. B12 pins that the advisory still fires and
    # B15 that the ordinary anchors in the SAME sentence are still there.
    #
    # THE SPECIMENS ARE ASSEMBLED AT RUNTIME and never written as literals, by
    # the rule stated above $script:LwgSecretPatterns in lib\common.ps1 and
    # already followed by the redaction cases in section A: a credential-shaped
    # string in a tracked file is a liability whether or not anything scans it.
    $b12 = New-LwgMissionCase -Name 'b12' -Knobs @{ min_files = 3; require_outside_root = $true; max_scan_bytes = 2097152; max_anchors = 400 }
    $b12Key  = 'AKIA' + ('Z' * 8) + ('7' * 8)   # a key id, pasted inside a path
    $b12Pass = 'zebra' + 'kestrel99'            # the value of an assignment
    Add-LwgPrompt -Case $b12 -Text (
        'Rework the header handling in ' + (Join-Path $b12.ws 'module\parser.ps1') +
        ', the deploy key lives under C:\keys\' + $b12Key + '\config.json, and api_key = ' +
        $b12Pass + ' for the run.')
    Set-LwgEdits -Case $b12 -Paths (Get-LwgOutsideEdits -Case $b12 -Count 3)
    $rb12 = Invoke-LwgStop -Case $b12 -Tag 'b12-run1'
    $vb12 = Test-LwgMissionAdvisory $rb12

    Add-Result 'B12: the prompt still gives the module standing, and it warns' $vb12.ok `
        ("$($vb12.why)  --  CANNOT GO RED against the pre-fix tree; it is the anti-vacuity guard for B13 and B14. This prompt names a file inside the workspace exactly as B1's does, so the run must warn about the three outside edits. If it does not, the redaction has eaten the prompt rather than the credential in it, and the two searches below would then be searching an advisory that was never emitted")

    $b12Raw = ''
    try { if ([IO.File]::Exists($b12.state)) { $b12Raw = [IO.File]::ReadAllText($b12.state) } } catch { }
    $b12Msg = ''
    if ($vb12.ok) { $b12Msg = [string]$vb12.env.systemMessage }

    # -match, so the comparison is CASE-INSENSITIVE, and that is the whole point
    # rather than laziness: an anchor is stored lowercased, so a case-sensitive
    # search for the specimen as it was typed would walk straight past the copy
    # the module actually made. [regex]::Escape because a specimen is data here.
    $b12InState = @(@($b12Key, $b12Pass) | Where-Object { $b12Raw -match [regex]::Escape($_) })
    $b12InMsg   = @(@($b12Key, $b12Pass) | Where-Object { $b12Msg -match [regex]::Escape($_) })

    Add-Result 'B13: no credential from the prompt reaches advisory-<sessionkey>.json' `
        ($b12Raw.Length -gt 0 -and $b12InState.Count -eq 0) `
        ("REGRESSION: the operator's typed prompt was written to the state directory unredacted. leaked: [$($b12InState -join ', ')]. A state file that holds nothing at all fails this too - the module has to have run and persisted its anchors for the absence to mean anything. got: [$b12Raw]")

    Add-Result 'B14: no credential from the prompt reaches the emitted systemMessage' `
        ($vb12.ok -and $b12InMsg.Count -eq 0) `
        ("REGRESSION: the advisory quoted the operator's credential back into the session. The `"you named:`" list is the four path anchors sorted, and a key pasted inside a path becomes one of those segments - it sorts early and lands in the first four. leaked: [$($b12InMsg -join ', ')]. got: [$b12Msg]")

    $sb12 = Get-LwgCaseState $b12
    Add-Result 'B15: the ordinary anchors in the same sentence survive the redaction' `
        ((@($sb12['md_paths']) -contains 'parser') -and (@($sb12['md_paths']) -contains 'module') -and
         (@($sb12['md_paths']) -contains 'config')) `
        ("CANNOT GO RED against the pre-fix tree - it pins that the fix is SURGICAL, which is the half a leak test cannot see. 'module' and 'parser' come from the path the operator named, 'config' from the tail of the path the key was pasted into: the redaction has to remove the segment that is a credential and leave the segments either side of it. got md_paths: [" + (@($sb12['md_paths']) -join ', ') + ']')

    # --- B16, B17: a state file written BEFORE the redaction landed -------
    # THE OTHER HALF OF THE SAME DEFECT, AND THE HALF B12-B15 CANNOT SEE.
    # Redacting prompts on the way in fixes every session that starts after the
    # update and none of the ones already running: those have an
    # advisory-<sessionkey>.json on disk whose anchors ARE the raw prompt text,
    # and rehydrating one carries the credential straight back into the set this
    # turn persists and quotes. A fix that closed the new sessions and left the
    # old ones leaking would be the kind of half-fix this repository keeps a rule
    # about.
    #
    # THE ANCHORS CANNOT BE CLEANED, ONLY DISCARDED, which is what makes this
    # testable as a distinct behaviour rather than as more redaction. An anchor
    # is one lowercased token with its sentence gone, and Get-LwgRedacted decides
    # from the sentence: the specimen below no longer matches its own pattern
    # once it is lowercased, and would sail through a second pass untouched. So
    # the set is thrown away, the read offset goes back to zero, and the anchors
    # are rebuilt from the transcript through the redaction.
    #
    # THE CREDENTIAL IS SEEDED ONLY INTO THE STATE FILE and deliberately does NOT
    # appear in this case's transcript. If it were in both, a green result would
    # not say which mechanism produced it - the rebuild discarding it, or the
    # redaction catching it on the way back in. Here the transcript is clean, so
    # the only way the specimen can leave the state file is by being discarded,
    # and the only way 'parser' can be in it afterwards is by the transcript
    # having been re-read.
    #
    # THE SEEDED OFFSET IS EOF, which is the other thing this pins. Nothing else
    # about this turn is new - no unread bytes, no new prompt, no change to the
    # incomplete latch - so on the pre-fix tree the module has nothing to write
    # and does not write, and the old anchors simply stay on disk. The rebuild
    # therefore has to force the write itself rather than relying on some other
    # change to trigger one.
    $b16 = New-LwgMissionCase -Name 'b16' -Knobs @{ min_files = 3; require_outside_root = $true; max_scan_bytes = 2097152; max_anchors = 400 }
    $b16Key = 'AKIA' + ('Y' * 8) + ('3' * 8)
    Add-LwgPrompt -Case $b16 -Text ('Rework the header handling in ' + (Join-Path $b16.ws 'module\parser.ps1') + '.')
    # Hand-built, byte for byte, because the point is what this code does with a
    # file a PREVIOUS VERSION of it wrote - and that version cannot be run from
    # here. The shape is the one the pre-redaction writer produced: anchors, an
    # offset at end of file, the latch, and NO md_redact key.
    [IO.File]::WriteAllText($b16.state,
        ('{"md_paths":["module","parser.ps1","parser","' + $b16Key.ToLowerInvariant() +
         '"],"md_words":["rework","header"],"md_offset":' + ([IO.FileInfo]::new($b16.tx)).Length +
         ',"md_incomplete":false}'),
        [Text.UTF8Encoding]::new($false))
    [void](Invoke-LwgStop -Case $b16 -Tag 'b16-run1')

    $s16raw = ''
    try { $s16raw = [IO.File]::ReadAllText($b16.state) } catch { }
    $s16 = Get-LwgCaseState $b16
    Add-Result 'B16: anchors written before the redaction are discarded and rebuilt, and the credential in them goes' `
        ($s16raw.Length -gt 0 -and $s16raw -notmatch [regex]::Escape($b16Key) -and
         (@($s16['md_paths']) -contains 'parser')) `
        ("REGRESSION: a session already running when the plugin was updated keeps re-persisting and re-quoting the credential its pre-redaction anchors hold. 'parser' has to be back in the set as well, or this passes for a rebuild that simply deleted everything and left the module with no standing to speak. got: [$s16raw]")

    Add-Result 'B17: the rebuilt state records that its anchors are redacted' `
        ([int]$s16['md_redact'] -eq 1) `
        ("REGRESSION: without the marker there is nothing on disk that distinguishes a rebuilt file from a pre-redaction one, so the transcript is re-read from byte zero at EVERY turn end for the rest of the session - the whole cost the incremental read exists to avoid. It is written where the anchors are written and never on its own. got: [$s16raw]")

    # --- B18: the RECORD bound is a hole in the picture, and it says so ---
    # THERE ARE TWO BOUNDS ON WHAT ONE TURN TAKES IN AND ONLY ONE OF THEM USED
    # TO ADMIT IT. B5 covers `max_scan_bytes`, which bounds the BYTES READ and
    # latches `md_incomplete`. The other bound is on the loop that PARSES what
    # was read - it stops at 400 records - and it used to break out silently:
    # anchors from the first 400 records, the offset written at end of file, and
    # `md_incomplete` still false. The module then judged the session believing
    # it had seen all of it, which is precisely what B5 exists to forbid,
    # reached by the other door.
    #
    # THE BOUND IS PER SLICE, so this needs a slice holding the whole session.
    # Two paths hand it one: the first turn of a session whose transcript
    # already exists, which is what this case builds, and the one-turn rebuild
    # B16 covers. A turn that GREW by 400 typed prompts is not a real session,
    # which is why the bound could sit there unnoticed.
    #
    # THE ANCHOR-BEARING PROMPT IS LAST, AND THAT IS THE WHOLE CONSTRUCTION.
    # The 400 fillers name nothing, so they contribute word anchors and no path
    # anchor; the 401st names a file and would give the module standing to speak.
    # It is never parsed. So the run is SILENT either way - before the fix for
    # want of standing, after it because the latch is set - and silence is
    # therefore not the discriminator. `md_incomplete` is: it is false on the
    # pre-fix tree and true here, and it is the difference between a module that
    # knows its picture is short and one that does not.
    $b18 = New-LwgMissionCase -Name 'b18' -Knobs @{ min_files = 3; require_outside_root = $true; max_scan_bytes = 2097152; max_anchors = 400 }
    # Built as Add-LwgPrompt builds it and appended ONCE rather than 400 times:
    # the record shape is the thing that matters and 400 opens of the same file
    # would be the slowest case in this suite by a wide margin.
    $b18Rec = (([ordered]@{ type = 'user'; message = [ordered]@{ content = 'carry on' } } |
                ConvertTo-Json -Depth 6 -Compress) + "`n")
    [IO.File]::AppendAllText($b18.tx, ($b18Rec * 400), [Text.UTF8Encoding]::new($false))
    Add-LwgPrompt -Case $b18 -Text ('Rework the header handling in ' + (Join-Path $b18.ws 'module\parser.ps1') + '.')
    Set-LwgEdits -Case $b18 -Paths (Get-LwgOutsideEdits -Case $b18 -Count 3)
    $vb18 = Test-LwgSilent (Invoke-LwgStop -Case $b18 -Tag 'b18-run1')
    $s18  = Get-LwgCaseState $b18
    Add-Result 'B18: a slice that hits the RECORD bound latches incomplete, as an oversized one does' `
        ($vb18.ok -and $s18['md_incomplete'] -eq $true) `
        ("REGRESSION: the parse stopped at 400 records and said nothing, so the anchor set is missing everything named after the 400th and the module does not know it. The next turn that meets the fire condition warns on a set it believes is complete - a false positive on the one module that is on by default. The run must also stay silent: $($vb18.why). got: " + ([IO.File]::ReadAllText($b18.state)))

    # --- B19: a PASTED PEM KEY, on both destinations ----------------------
    # THE SHAPE THAT WAS ENUMERATED AND STILL WENT THROUGH, which is why it gets
    # its own case rather than being folded into B13/B14. Those two paste an
    # AWS-shaped key id; this pastes a PEM block, and the difference is not
    # cosmetic. The vendor rule MATCHED a PEM - private_key is one of the five -
    # and replaced the BEGIN LINE ONLY, so the base64 body survived intact.
    # base64 contains '/', Add-LwgMissionAnchors reads '/' as a PATH SEPARATOR,
    # and a path anchor is the kind the advisory QUOTES. So the body was not
    # merely stored, it was PROMOTED into the four-item "you named:" list and
    # pushed the file the operator actually named out of the message.
    #
    # BASELINE: red against the working tree before this fix AND at fd8d023 -
    # the BEGIN-line-only pattern is the same in both, so this is one of the two
    # cases here that is a genuine fd8d023 regression rather than a repair of
    # something a parallel fix introduced.
    #
    # The third assertion is the anti-vacuity guard, in the same role B15 plays:
    # a "fix" that dropped the whole prompt would pass the two leak searches by
    # emitting nothing worth searching.
    $b19 = New-LwgMissionCase -Name 'b19' -Knobs @{ min_files = 3; require_outside_root = $true; max_scan_bytes = 2097152; max_anchors = 400 }
    # Assembled at runtime, never a literal - the same rule section A follows.
    # The '/' characters are what make this reach the QUOTED list rather than
    # just the state file, so they are deliberate and not incidental padding.
    $b19Body = 'MIIEowIBAAKCAQEA' + '0aqrstuvwxyz/3dfghjklzxcv' + 'bnmqwertyuio+mnbvcxzlkjhg' + '/abcdefghijklmnop'
    $b19Pem  = '-----BEGIN RSA PRIVATE KEY-----' + "`n" + $b19Body + "`n" + '-----END RSA PRIVATE KEY-----'
    Add-LwgPrompt -Case $b19 -Text (
        'Rework the header handling in ' + (Join-Path $b19.ws 'module\parser.ps1') +
        ' using this deploy key: ' + $b19Pem)
    Set-LwgEdits -Case $b19 -Paths (Get-LwgOutsideEdits -Case $b19 -Count 3)
    $rb19 = Invoke-LwgStop -Case $b19 -Tag 'b19-run1'
    $vb19 = Test-LwgMissionAdvisory $rb19

    $b19Raw = ''
    try { if ([IO.File]::Exists($b19.state)) { $b19Raw = [IO.File]::ReadAllText($b19.state) } } catch { }
    $b19Msg = if ($vb19.ok) { [string]$vb19.env.systemMessage } else { '' }
    # The body is searched in FRAGMENTS, because the tokeniser is what splits it:
    # a search for the whole base64 run would pass while every piece of it stood
    # in the message. These are the segments '/' produces.
    $b19Frags = @('0aqrstuvwxyz', '3dfghjklzxcv', 'bnmqwertyuio', 'abcdefghijklmnop')
    $b19InState = @($b19Frags | Where-Object { $b19Raw -match [regex]::Escape($_) })
    $b19InMsg   = @($b19Frags | Where-Object { $b19Msg -match [regex]::Escape($_) })

    Add-Result 'B19: no fragment of a pasted PEM body reaches advisory-<sessionkey>.json' `
        ($b19Raw.Length -gt 0 -and $b19InState.Count -eq 0) `
        ("REGRESSION, red at fd8d023 as well: the vendor rule replaced the BEGIN line and left the body, and the body tokenised into anchors that were persisted. leaked: [$($b19InState -join ', ')]. got: [$b19Raw]")

    Add-Result 'B19: no fragment of a pasted PEM body reaches the emitted systemMessage' `
        ($vb19.ok -and $b19InMsg.Count -eq 0) `
        ("REGRESSION, and this is the destination the module's own comment used to omit: base64 contains '/', which the tokeniser reads as a path separator, so the body was promoted to the anchor kind the advisory QUOTES and took the slots the operator's own file should have had. leaked: [$($b19InMsg -join ', ')]. got: [$b19Msg]")

    $sb19 = Get-LwgCaseState $b19
    Add-Result 'B19: the file the operator actually named still survives the redaction' `
        ((@($sb19['md_paths']) -contains 'parser') -and (@($sb19['md_paths']) -contains 'module')) `
        ("CANNOT GO RED against the pre-fix tree - it is the anti-vacuity guard for the two searches above, in the same role B15 plays for B13 and B14. Removing a PEM must not remove the workspace path in the same sentence, or the module loses the standing that makes it speak at all. got md_paths: [" + (@($sb19['md_paths']) -join ', ') + ']')

    # --- B20: ONE WARNING PER SESSION, not one per file that joins the set ---
    # THE NUMBER THE ON-BY-DEFAULT DECISION RESTS ON. docs/modules.md offers
    # "the realistic worst case is one wrong warning per session" as the other
    # side of shipping this module on. That was drawn from "it warns once per
    # distinct set of unaccounted files", which the code did exactly - and the
    # conclusion did not follow, because the set GROWS. The edit list is a
    # deduped union of the whole session, so a fourth unrelated file produced a
    # different signature and re-fired the same warning with a longer list.
    #
    # B7 above cannot see this. It re-runs the SAME edit set, which is the case
    # the old signature handled correctly. This one adds one file per turn,
    # which is the ordinary shape of a session working outside the workspace,
    # and it is the shape that produced four warnings in five turns.
    #
    # THE DISCRIMINATOR IS A COUNT, so the assertion is on how many of the three
    # turns emitted an advisory rather than on any one of them. Turn 1 must
    # warn - a case that only asserted silence would be satisfied by a module
    # that had stopped speaking entirely, which is the failure this suite's own
    # editorial rule bans.
    #
    # BASELINE: red against the working tree before this fix, and against
    # fd8d023 and cc44c99, where `$sig = ($leaves -join '|')` is identical.
    # Pre-fix it emits three advisories; the assertion wants one.
    $b20 = New-LwgMissionCase -Name 'b20' -Knobs @{ min_files = 3; require_outside_root = $true; max_scan_bytes = 2097152; max_anchors = 400 }
    Add-LwgPrompt -Case $b20 -Text ('Rework the header handling in ' + (Join-Path $b20.ws 'module\parser.ps1') + '.')
    $b20Fired = @()
    $b20Msgs  = @()
    foreach ($n in @(3, 4, 5)) {
        Set-LwgEdits -Case $b20 -Paths (Get-LwgOutsideEdits -Case $b20 -Count $n)
        $r = Invoke-LwgStop -Case $b20 -Tag ("b20-run$n")
        $v = Test-LwgMissionAdvisory $r
        if ($v.ok) { $b20Fired += $n; $b20Msgs += [string]$v.env.systemMessage }
        elseif ($r.code -ne 0 -or -not [string]::IsNullOrWhiteSpace($r.err)) {
            $b20Fired += "$n(broken: $($v.why))"
        }
    }
    Add-Result 'B20: a standing drift warns ONCE, not again each time the set grows' `
        (@($b20Fired).Count -eq 1 -and $b20Fired[0] -eq 3) `
        ("REGRESSION: the dedupe signature was the LIST of unaccounted files, so every turn that added one produced a new distinct set and re-fired. Turns that emitted an advisory: [" + ($b20Fired -join ', ') + "] of [3, 4, 5] - expected [3] only. Messages: " + ($b20Msgs -join ' || '))

    # --- B21: a SATURATED anchor set latches, it does not judge on ----------
    # THE PIVOT GUARANTEE HAS AN EXPIRY AND THIS IS IT. Add-LwgMissionAnchors
    # stops at max_anchors with a `break`, and the total it tests is rehydrated
    # from the state file every turn and only ever grows - so the first turn to
    # reach the cap is the last turn that learns anything. Every prompt after it
    # contributes nothing, which is precisely the redirection the "a pivot
    # cannot trip it" argument depends on.
    #
    # WHAT THE PRE-FIX TREE DOES HERE, and it is the worst shape this module
    # has: turn 1 saturates the set on a workspace file, turn 2 redirects to the
    # outside tree BY NAME and the work lands there, and the module warns that
    # all three files "match nothing named in any prompt this session" while
    # quoting anchors from before the pivot as "you named:". The operator is
    # told, with specifics, that they never asked for work they asked for one
    # turn ago.
    #
    # THE CAP IS SET LOW RATHER THAN AT 400, deliberately. It is a documented
    # knob and the code path is the same at any value; reaching 400 for real
    # would need a prompt long enough to dominate this suite's runtime, and the
    # thing under test is what happens AT the cap, not what the cap is. The
    # filler tail is what saturates it, and the path is named FIRST so the path
    # anchors are in the set before the words exhaust the budget - without that
    # the module would have no standing on the pre-fix tree, would stay silent
    # for the wrong reason, and the case would pass without discriminating.
    #
    # TWO ASSERTIONS, because silence alone is satisfied by a module that has
    # stopped working. md_incomplete is the other half: it is the record that
    # the module knows its picture is short, and it is false on the pre-fix
    # tree.
    #
    # BASELINE: red against the working tree before this fix, and against
    # fd8d023 and cc44c99 - `if ($Anchors.total -ge $MaxAnchors) { break }` in
    # Add-LwgMissionAnchors is byte-identical at all three, and no caller
    # anywhere tests the total afterwards.
    $b21 = New-LwgMissionCase -Name 'b21' -Knobs @{ min_files = 3; require_outside_root = $true; max_scan_bytes = 2097152; max_anchors = 12 }
    Add-LwgPrompt -Case $b21 -Text ((Join-Path $b21.ws 'module\parser.ps1') +
        ' - rework the header handling there, keeping every existing behaviour intact,' +
        ' preserving whatever indentation surrounds those declarations, without altering' +
        ' unrelated helpers, comments, spacing, ordering, naming, formatting, structure.')
    $vb21a = Test-LwgSilent (Invoke-LwgStop -Case $b21 -Tag 'b21-run1')
    $s21a  = Get-LwgCaseState $b21

    Add-LwgPrompt -Case $b21 -Text ('Change of plan - move to ' + (Join-Path $b21.outside 'crimson_one.ps1') + ' and its siblings instead.')
    Set-LwgEdits -Case $b21 -Paths (Get-LwgOutsideEdits -Case $b21 -Count 3)
    $rb21b = Invoke-LwgStop -Case $b21 -Tag 'b21-run2'
    $vb21b = Test-LwgSilent $rb21b
    $s21b  = Get-LwgCaseState $b21

    Add-Result 'B21: an anchor set at max_anchors latches incomplete rather than going deaf in silence' `
        ($vb21a.ok -and $s21a['md_incomplete'] -eq $true) `
        ("REGRESSION: reaching the cap stopped accumulation and set nothing - no flag, no event, nothing in the state file distinguished '400 anchors and still learning' from '400 anchors and deaf since turn 5'. Turn 1 must also stay silent (it has no edits behind it): $($vb21a.why). got: " + ([IO.File]::ReadAllText($b21.state)))

    Add-Result 'B21: a pivot after the cap is not reported as drift' `
        ($vb21b.ok -and $s21b['md_incomplete'] -eq $true) `
        ("REGRESSION: the redirecting prompt contributed no anchors because the set was saturated, so the work that followed matched nothing and the module warned that the operator never asked for what they asked for one turn ago - quoting pre-pivot anchors as 'you named:'. This is the case docs/modules.md calls the one the module was built around. $($vb21b.why). got: " + ([IO.File]::ReadAllText($b21.state)))

    # --- B22: the edit list ROLLS past its cap, it does not stop recording --
    # THE WRITER'S CAP WAS A HARD STOP. `if (size -gt 262144) { exit 0 }` runs
    # before the append, so past the cap no further edit in that session was
    # ever recorded - and both reading modules carried on reporting active.
    # docs_coupling went on warning "and no documentation did" about a session
    # that had spent an hour editing documentation, because no doc path could be
    # recorded any more; mission_drift's edit set froze, so its skip guard
    # stopped it assessing at all. Two modules that look enabled and observe
    # nothing, which is what this plugin exists to catch.
    #
    # THE FIXTURE IS THE FILE AT THE CAP, which is the whole condition. The
    # filler lines name a tree that shares nothing with anything else here so
    # they cannot accidentally account for later work.
    #
    # THE SECOND ROW IS NOT DECORATION. A "fix" that truncated the file would
    # satisfy the first row and lose the session's history; rolling archives it.
    # And the first row alone is a bare negative's cousin - it would pass on a
    # writer that had simply deleted the file and started again.
    #
    # BASELINE: red against the working tree before this fix, and against
    # fd8d023 and cc44c99, where the size check is the same `exit 0`.
    $b22 = New-LwgMissionCase -Name 'b22' -Knobs @{ min_files = 3; require_outside_root = $true; max_scan_bytes = 2097152; max_anchors = 400 }
    $b22Filler = New-Object 'System.Collections.Generic.List[string]'
    for ($i = 0; $i -lt 4200; $i++) {
        [void]$b22Filler.Add((Join-Path $b22.outside ('umberfill_{0:D5}\umberfill_{0:D5}.ps1' -f $i)))
    }
    Set-LwgEdits -Case $b22 -Paths $b22Filler.ToArray()
    $b22File = Join-Path $b22.data ('edits-' + $b22.key + '.txt')
    $b22Was  = (Get-Item -LiteralPath $b22File).Length

    $b22New  = Join-Path $b22.ws 'module\afterthecap.ps1'
    $rb22    = Invoke-LwgPostEdit -Case $b22 -Path $b22New -Tag 'b22-postedit'
    $b22Now  = @(Get-LwgCaseEditLines $b22)

    Add-Result 'B22: a file edited AFTER the 256 KB cap is still recorded' `
        ($rb22.code -eq 0 -and ($b22Now -contains $b22New)) `
        ("REGRESSION: the writer stopped recording at the cap instead of rolling, so docs_coupling and mission_drift both went on reporting active while observing nothing further. Seeded $($b22Filler.Count) lines ($b22Was bytes); the hook exited $($rb22.code) and the list now holds $($b22Now.Count) line(s), last: [" + $(if ($b22Now.Count) { $b22Now[-1] } else { '<none>' }) + "]. stderr: [$($rb22.err)]")

    Add-Result 'B22: the rolled-off entries are archived, not discarded' `
        ([IO.File]::Exists($b22File + '.1') -and (Get-Item -LiteralPath $b22File).Length -lt $b22Was) `
        ("a roll that truncated would satisfy the row above and lose the session's history. Live file was $b22Was bytes, is now " + (Get-Item -LiteralPath $b22File).Length + " bytes; archive present: " + [IO.File]::Exists($b22File + '.1'))

    # --- B23: one oversized tool_input.file_path is bounded, twice ----------
    # THE CAP WAS ON THE FILE AND NOT ON THE LINE, and the size check ran BEFORE
    # the append, so a file at 100 bytes admitted an append of any length. $path
    # is payload-controlled and Add-LwgLine imposes no bound of its own.
    #
    # AND Split-Path -Leaf IS NOT A LENGTH BOUND: it returns the whole string
    # when there is no separator in it, so the value went whole into the
    # DocsCoupling record, into a log that does not rotate, and into the
    # operator's systemMessage.
    #
    # TWO ROWS BECAUSE THERE ARE TWO INDEPENDENT DEFENCES, one in each file. The
    # reader must not depend on the writer having been fixed, and asserting only
    # the end result would leave that untested.
    #
    # docs_coupling is switched ON for this case and mission_drift left on with
    # no prompt naming anything, so mission_drift has no standing and the only
    # advisory in the envelope is the one under test.
    #
    # BASELINE: red against the working tree before this fix, and against
    # fd8d023 and cc44c99 - `Add-LwgLine ... -Line ($path.Replace(...))` with no
    # cap, and a bare `Split-Path $_ -Leaf` into the message, at all three.
    $b23 = New-LwgMissionCase -Name 'b23' -Knobs @{ min_files = 3; require_outside_root = $true; max_scan_bytes = 2097152; max_anchors = 400 } `
                              -Modules @{ mission_drift = $true; docs_coupling = $true }
    # Assembled at runtime and separator-free, which is what makes Split-Path
    # -Leaf hand it back whole. `.ps1` is what makes it classify as source.
    $b23Path = ('x' * 200000) + '.ps1'
    $rb23    = Invoke-LwgPostEdit -Case $b23 -Path $b23Path -Tag 'b23-postedit'
    $b23Line = @(Get-LwgCaseEditLines $b23)
    $b23Max  = 0
    foreach ($l in $b23Line) { if ($l.Length -gt $b23Max) { $b23Max = $l.Length } }

    Add-Result 'B23: an oversized file_path is bounded at the WRITE, and still recorded' `
        ($rb23.code -eq 0 -and $b23Line.Count -eq 1 -and $b23Max -le 1100) `
        ("REGRESSION: the 200 000-character value landed whole in edits-<key>.txt, taking ~76% of the 256 KB window the Stop half reads and displacing the session's real edit history from BOTH modules - while leaving the file under the writer's cap, so recording continued and the picture stayed wrong rather than obviously broken. A bound that dropped the record instead would fail this row too: it wants one line, bounded. got $($b23Line.Count) line(s), longest $b23Max chars. stderr: [$($rb23.err)]")

    # THE READER IS DRIVEN INDEPENDENTLY OF THE WRITER, by seeding the edit list
    # by hand, and that separation is the point of the second row rather than an
    # accident of the fixture. Two files write into this pipeline's data; only
    # one of them can be fixed at a time, and a reader tested only through a
    # fixed writer is a reader with no test at all. Seeding also keeps the value
    # ending in `.ps1`, which is what makes it classify as source - the writer's
    # own cap truncates the tail and with it the extension, so a value passed
    # through the writer would reach here classified 'other' and the advisory
    # under test would not fire for a reason that has nothing to do with it.
    Set-LwgEdits -Case $b23 -Paths @($b23Path)
    $rb23s   = Invoke-LwgStop -Case $b23 -Tag 'b23-stop'
    $b23Env  = $null
    try { $b23Env = $rb23s.out | ConvertFrom-Json } catch { }
    $b23Msg  = [string]$(if ($null -ne $b23Env) { $b23Env.systemMessage } else { '' })

    Add-Result 'B23: and the advisory the operator reads is bounded too' `
        ($rb23s.code -eq 0 -and $b23Msg -like '*LW-WATCHTOWER docs:*' -and $b23Msg.Length -le 2000) `
        ("REGRESSION, and this is the SECOND destination: Split-Path -Leaf returns the whole string for a separator-free value, so the sample went unbounded into the DocsCoupling record and into the systemMessage. The advisory must still FIRE - a reader that dropped the file rather than bounding it would pass a length check and say nothing. exit $($rb23s.code), message length $($b23Msg.Length): [" + $(if ($b23Msg.Length -gt 300) { $b23Msg.Substring(0, 300) + '...' } else { $b23Msg }) + "]")

    # --- B25: an impossible occupancy is REFUSED, not absorbed --------------
    # context_pressure carries an explicit refusal: an occupancy above the
    # assumed window is arithmetically impossible, so it is proof the
    # DENOMINATOR is wrong rather than proof of pressure, and the module reports
    # nothing rather than a fabricated percentage. Three lines earlier the same
    # block used to write that occupancy into the observation store and then
    # hand the SAME in-memory hashtable to Get-LwgContextWindow, which read it
    # back, concluded the window must be 1M and returned a denominator large
    # enough that the occupancy was no longer impossible. The refusal could not
    # fire for any reading between 200k and 1M - which is every reading it
    # exists to catch.
    #
    # WHAT THAT COST: one mis-summed 260 000 pinned the model to a 1M window
    # permanently, with no expiry and no way to clear it, and a real 150k/200k
    # turn - 75%, the warn threshold - then rendered as 15%, level ok, silently.
    #
    # TWO TURNS, BECAUSE ONE SAMPLE NO LONGER PINS. Turn 1 must refuse and
    # record the reading as PENDING; turn 2 corroborates and promotes it, which
    # is what keeps a genuine 1M session able to learn its own window. The
    # store's shape is asserted directly because it is the thing that outlives
    # the session.
    #
    # BASELINE: red against the working tree before this fix, and against
    # fd8d023 and cc44c99, where the observation write precedes the resolve.
    $b25 = New-LwgMissionCase -Name 'b25' -Knobs $null -Modules @{ context_pressure = $true }
    $b25model = 'lwg-fixture-model-200k'
    $b25rec = ([ordered]@{
        type    = 'assistant'
        message = [ordered]@{ model = $b25model; usage = [ordered]@{
            input_tokens = 260000; cache_read_input_tokens = 0
            cache_creation_input_tokens = 0; output_tokens = 10 } }
    } | ConvertTo-Json -Depth 8 -Compress)
    [IO.File]::AppendAllText($b25.tx, ($b25rec + "`n"), [Text.UTF8Encoding]::new($false))

    $rb25a = Invoke-LwgStop -Case $b25 -Tag 'b25-run1'
    $b25obsPath = Join-Path $b25.data 'context_windows.json'
    $b25obs1 = ''
    try { $b25obs1 = [IO.File]::ReadAllText($b25obsPath) } catch { }
    $b25msg1 = ''
    try { $b25msg1 = [string](($rb25a.out | ConvertFrom-Json).systemMessage) } catch { }

    Add-Result 'B25: an occupancy above the assumed window reports no percentage and pins nothing' `
        ($rb25a.code -eq 0 -and $b25msg1 -notlike '*LW-WATCHTOWER context*' -and
         $b25obs1 -like '*#pending*' -and $b25obs1 -notlike ('*"' + $b25model + '":*')) `
        ("REGRESSION: the observation was written before the window was resolved and from the same hashtable, so the impossible-occupancy check could not fire below 1M and one wrong reading pinned the denominator for ever. exit $($rb25a.code), message [$b25msg1], context_windows.json [$b25obs1]")

    $rb25b = Invoke-LwgStop -Case $b25 -Tag 'b25-run2'
    $b25obs2 = ''
    try { $b25obs2 = [IO.File]::ReadAllText($b25obsPath) } catch { }
    Add-Result 'B25: a SECOND reading corroborates it and the window is then learned' `
        ($rb25b.code -eq 0 -and $b25obs2 -like ('*"' + $b25model + '":*') -and $b25obs2 -notlike '*#pending*') `
        ("CANNOT GO RED against the pre-fix tree - it is the anti-vacuity guard for the row above. A 'fix' that simply never recorded an observation would satisfy that row and leave a genuine 1M session reporting UNKNOWN for ever, which is the opposite failure. exit $($rb25b.code), context_windows.json [$b25obs2]")

    # --- B24: git_hygiene's UNKNOWN is not deduped into silence -------------
    # THE ONLY CASE IN THIS SUITE THAT IS NOT ABOUT mission_drift, and it is here
    # because it drives the same hook through the same plumbing; a section of its
    # own would buy nothing but a heading. Read section B as "the Stop advisory
    # hook, end to end", of which mission_drift is all but this case.
    #
    # WHAT IT PINS. git_hygiene's documented contract is that silence means "git
    # said there is nothing wrong" and NEVER "git was not asked". The advisory
    # carrying the UNKNOWN state was deduped on the set of condition ids, and
    # `query-failed` was an ordinary id in that set - so a git that never answers
    # produced the same signature at every turn end and was announced exactly
    # once, on the first. From turn two on, a session with git missing from the
    # hook process's PATH was indistinguishable from a clean tree.
    #
    # HOW git IS MADE UNRESOLVABLE: PATH is replaced for the child with System32
    # alone, which the .cmd still needs to find powershell. No real installation
    # is touched and nothing is uninstalled. That is also why the fixture repo is
    # a bare .git DIRECTORY with a config in it - Get-LwgRepoInfo resolves a root
    # by walking for .git and parsing that file, and never runs git to do it, so
    # the module reaches its query with no git to answer it.
    #
    # THE ASSERTION IS A COUNT OVER THREE TURNS, because one turn cannot tell the
    # two behaviours apart: both emit on turn 1. Three advisories is the fix; one
    # is the defect.
    $b24 = New-LwgMissionCase -Name 'b24' -Knobs $null -Modules @{ git_hygiene = $true }
    $b24git = Join-Path $b24.ws '.git'
    [void][IO.Directory]::CreateDirectory($b24git)
    [IO.File]::WriteAllText((Join-Path $b24git 'config'),
        "[core]`n`trepositoryformatversion = 0`n[remote `"origin`"]`n`turl = https://example.invalid/lwg/fixture.git`n",
        [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $b24git 'HEAD'), "ref: refs/heads/lwg-fixture`n", [Text.UTF8Encoding]::new($false))

    # System32 for cmd's own resolution and WindowsPowerShell\v1.0 because the
    # .cmd invokes `powershell` by name. Neither holds git on any install.
    $b24sys  = Join-Path ([Environment]::GetFolderPath('Windows')) 'System32'
    $b24path = $b24sys + ';' + (Join-Path $b24sys 'WindowsPowerShell\v1.0')
    $b24said = 0
    $b24msgs = @()
    $b24bad  = @()
    foreach ($t in @(1, 2, 3)) {
        $r = Invoke-LwgStop -Case $b24 -Tag ("b24-run$t") -PathOverride $b24path
        if ($r.code -ne 0 -or -not [string]::IsNullOrWhiteSpace($r.err)) {
            $b24bad += "turn $t exited $($r.code) stderr [$($r.err)]"
        }
        $m = ''
        try { $m = [string](($r.out | ConvertFrom-Json).systemMessage) } catch { }
        if ($m -like '*LW-WATCHTOWER git:*' -and $m -like '*UNKNOWN*') { $b24said++; $b24msgs += $m }
    }
    Add-Result 'B24: an UNKNOWN tree state is reported at EVERY turn end, not once' `
        ($b24said -eq 3 -and $b24bad.Count -eq 0) `
        ("REGRESSION: query-failed went into the same dedupe signature as the tree conditions, so a git that never answers was announced on turn 1 and never again - and this module's own documentation says its silence means git said nothing was wrong. Turns that reported UNKNOWN: $b24said of 3. Problems: [" + ($b24bad -join '; ') + "]. Messages: " + ($b24msgs -join ' || '))

    # =====================================================================
    # SECTION C - failure_capture and log_rotation, END TO END
    # =====================================================================
    Write-Output 'C. supervisor (child process)'

    $cDir = Join-Path $work 'c'
    [void][IO.Directory]::CreateDirectory($cDir)

    # --- registration ----------------------------------------------------
    # A supervisor that is not registered reports nothing, and it reports
    # nothing SILENTLY - indistinguishable from a session in which nothing
    # failed.
    $hooks = ([IO.File]::ReadAllText($HooksPath) | ConvertFrom-Json)
    foreach ($ev in @('SessionStart', 'PostToolUseFailure', 'Stop', 'SubagentStop', 'StopFailure')) {
        $entries = @()
        try { $entries = @($hooks.hooks.$ev) } catch { }
        $mine = @($entries | Where-Object { ($_ | ConvertTo-Json -Depth 8 -Compress) -like '*supervisor.ps1*' })
        $okShape = $false
        if ($mine.Count -eq 1) {
            $h = @($mine[0].hooks)[0]
            $argsJoined = (@($h.args) -join ' ')
            # The -HookEvent value has to match the key it is registered under,
            # or the record's `event` field describes a different thing from the
            # one that happened - and the Stop branch's alerting would run on
            # SessionStart.
            $okShape = ([string]$h.type -eq 'command' -and [string]$h.command -eq 'powershell' -and
                        $argsJoined -like '*${CLAUDE_PLUGIN_ROOT}*supervisor.ps1*' -and
                        $argsJoined -like "*-HookEvent $ev*")
        }
        Add-Result "C0 registration: $ev invokes the supervisor with -HookEvent $ev" $okShape `
            "expected exactly one $ev entry naming lib/supervisor.ps1 in exec form (command + args, no shell: - pwsh is absent) with -HookEvent $ev; found $($mine.Count) entry(ies)"
    }

    # asyncRewake is what makes exit 2 an ALERT rather than a BLOCK. Without it
    # the supervisor's exit 2 on Stop refuses the turn end, which is the
    # opposite of the intent and would be discovered by an operator, not here.
    foreach ($ev in @('Stop', 'PostToolUseFailure')) {
        $entry = @(@($hooks.hooks.$ev) | Where-Object { ($_ | ConvertTo-Json -Depth 8 -Compress) -like '*supervisor.ps1*' })[0]
        $h = @($entry.hooks)[0]
        Add-Result "C0 registration: the $ev supervisor entry sets asyncRewake" `
            ($h.asyncRewake -eq $true) `
            "this script exits 2 on $ev to alert the orchestrator. Without asyncRewake, exit 2 BLOCKS instead of alerting"
    }

    $advEntry = @(@($hooks.hooks.Stop) | Where-Object { ($_ | ConvertTo-Json -Depth 8 -Compress) -like '*stop_advisories.ps1*' })
    Add-Result 'C0 registration: stop_advisories is a second Stop entry with no asyncRewake' `
        ($advEntry.Count -eq 1 -and (($advEntry[0] | ConvertTo-Json -Depth 8 -Compress) -notlike '*asyncRewake*')) `
        'the advisory handler exits 0 on every path and never alerts, so it needs no rewake; a rewake here would imply it can exit 2'

    function New-LwgSupervisorCase {
        param([string]$Name, [hashtable]$Modules)
        $dir = Join-Path $cDir $Name
        $c = @{
            name    = $Name
            dir     = $dir
            root    = (Join-Path $dir 'root')
            data    = (Join-Path $dir 'root\data')
            ws      = (Join-Path $dir 'ws')
            session = ('lwg-stop-' + $Name)
        }
        foreach ($d in @($c.dir, $c.root, $c.data, $c.ws)) { [void][IO.Directory]::CreateDirectory($d) }
        $c['health']  = Join-Path $c.data 'health.jsonl'
        $c['alerted'] = Join-Path $c.data 'alerted.json'
        Write-LwgFixtureConfig -Dir $c.root -Modules $Modules -MissionKnobs $null
        return $c
    }

    function Invoke-LwgSupervisor {
        param($Case, [string]$Event, [string]$Payload, [string]$Tag)
        return (Invoke-LwgHook -ScriptPath $SupervisorPath -ScriptArgs ('-HookEvent ' + $Event) `
                    -Payload $Payload -PluginRoot $Case.root -DataDir $Case.data -WorkDir $Case.dir -Tag $Tag)
    }

    function New-LwgStopPayload {
        <#
          A Stop payload with $Tasks failing background tasks. Built as text so a
          case controls exactly which members exist - "the field is absent" and
          "the field is an empty array" are different inputs.
        #>
        param($Case, [string[]]$FailedIds, [switch]$StopHookActive)
        $parts = @(
            ('"session_id":"' + $Case.session + '"')
            ('"cwd":"' + ($Case.ws -replace '\\', '/') + '"')
            '"hook_event_name":"Stop"'
        )
        if ($StopHookActive) { $parts += '"stop_hook_active":true' }
        $tasks = @($FailedIds | ForEach-Object {
            '{"id":"' + $_ + '","type":"agent","status":"failed","description":"fixture dispatch","agent_type":"lwg-fixture-worker"}' })
        $parts += ('"background_tasks":[' + ($tasks -join ',') + ']')
        return '{' + ($parts -join ',') + '}'
    }

    # --- C2: the failed_tasks:null regression ----------------------------
    # A SHIPPED BUG, and two records carrying it survive in the inherited log.
    # ONE failed task unrolls to a bare PSCustomObject whose .Count is $null;
    # the status line reads [int]$null as 0, so the health indicator never went
    # red on exactly the sessions that had a single failure. The @() around
    # Get-FailedTasks is the fix, and this is the case that pins it - which is
    # why the record's field is asserted, not just the exit code: without the
    # wrap this run still exits 2, and only the LOG is wrong.
    $c2 = New-LwgSupervisorCase -Name 'c2' -Modules @{ failure_capture = $true; log_rotation = $false }
    $rc2 = Invoke-LwgSupervisor -Case $c2 -Event 'Stop' -Tag 'c2-run1' `
                -Payload (New-LwgStopPayload -Case $c2 -FailedIds @('task-one'))
    Add-Result 'C2: exactly one failed task alerts (exit 2, reason on stderr)' `
        ($rc2.code -eq 2 -and $rc2.err -like '*1 background task*') `
        "expected exit 2 with a count of 1 on stderr; got exit $($rc2.code), stderr [$($rc2.err)]"

    $c2rec = ''
    try { $c2rec = [IO.File]::ReadAllText($c2.health) } catch { }
    Add-Result 'C2: the health record counts the one failure as 1, not null' `
        ($c2rec -like '*"failed_tasks":1*') `
        ("REGRESSION: a one-element list unrolled to a bare object logs `"failed_tasks`":null, the status line reads [int]`$null as 0, and the health indicator stays green through a real failure. Two such records exist in the inherited log. got: " + $c2rec)

    # --- C3: the writer keeps a one-element list an ARRAY ----------------
    # The other half of the same shape problem, and the one that SEEDS it: a
    # one-element list serialised as a bare JSON string is what the reader then
    # has to flatten on the next turn.
    $c3raw = ''
    try { $c3raw = [IO.File]::ReadAllText($c2.alerted).TrimStart([char]0xFEFF).Trim() } catch { }
    Add-Result 'C3: alerted.json holds a JSON ARRAY after one id is recorded' `
        ($c3raw.StartsWith('[')) `
        ("a one-element list written as a bare JSON string is what makes the next turn's dedupe read a string instead of a list. got: [" + $c3raw + ']')

    # --- C1: the dedupe regression ---------------------------------------
    # The other SHIPPED bug. Two shapes come back from ConvertFrom-Json that a
    # plain @() does not turn into a list of ids:
    #
    #   "task-one"                a single-entry file written before the writer
    #                             was fixed - a bare JSON string, not a list;
    #   ["task-one","task-two"]   a MULTI-entry file. Windows PowerShell's
    #                             ConvertFrom-Json writes its result WITHOUT
    #                             enumerating it, so the whole array arrives as
    #                             ONE pipeline item and @() keeps it as one
    #                             element. `-notcontains 'task-one'` is then
    #                             TRUE against a file that plainly contains it.
    #
    # Either shape makes the dedupe silently stop deduping, which re-alerts the
    # same dead task at every turn end for the rest of the session. The double
    # ForEach unnests one level and then stringifies, which covers both. All
    # three shapes below are seeded as LITERAL BYTES, because the point is what
    # the reader does with a file it did not write.
    #
    # A DOUBLY nested file - [["task-one","task-two"]] - is deliberately NOT a
    # case here. The unnesting is one level deep, so that file would not dedupe;
    # but nothing writes it (the writer below always emits a flat array), so a
    # case for it would pin behaviour the code does not have against an input it
    # cannot receive.
    $c1shapes = @(
        @{ n = 'bare-string';   raw = '"task-one"' }
        @{ n = 'single-array';  raw = '["task-one"]' }
        @{ n = 'multi-array';   raw = '["task-one","task-two"]' }
    )
    foreach ($shape in $c1shapes) {
        $c1 = New-LwgSupervisorCase -Name ('c1-' + $shape.n) -Modules @{ failure_capture = $true; log_rotation = $false }
        [IO.File]::WriteAllText($c1.alerted, $shape.raw, [Text.UTF8Encoding]::new($false))
        $rc1 = Invoke-LwgSupervisor -Case $c1 -Event 'Stop' -Tag 'c1-run1' `
                    -Payload (New-LwgStopPayload -Case $c1 -FailedIds @('task-one'))
        Add-Result "C1 ($($shape.n)): an already-alerted task does not alert again" `
            ($rc1.code -eq 0 -and [string]::IsNullOrWhiteSpace($rc1.err)) `
            ("REGRESSION: alerted.json read back as $($shape.n) must still dedupe. Exit 2 here re-alerts the same dead task at every turn end for the rest of the session. got exit $($rc1.code), stderr [$($rc1.err)]")

        # THE OTHER ARM, WITHOUT WHICH THE ROW ABOVE CERTIFIES NOTHING. Dedupe
        # is a discrimination - quiet on a seen id, alert on an unseen one - and
        # "exit 0 and empty stderr" is also what a supervisor that has stopped
        # alerting at all produces. Measured: with `if (Test-Path $seenPath) {
        # exit 0 }` inserted at the top of the read, so that ANY existing
        # alerted.json swallowed every later failure, all three rows above
        # stayed green. No other case in this file consults alerted.json - C6's
        # PostToolUseFailure path never reads it - so those three rows were the
        # whole of the coverage.
        #
        # THE FILESYSTEM IS THE SECOND ASSERTION, not the stderr text: the id is
        # not in the message (the alert names type, status and description), and
        # the advice wording is reworded often. alerted.json gaining the unseen
        # id is the durable, behavioural fact.
        $rc1b = Invoke-LwgSupervisor -Case $c1 -Event 'Stop' -Tag 'c1-run2' `
                    -Payload (New-LwgStopPayload -Case $c1 -FailedIds @('task-unseen'))
        $c1After = ''
        try { $c1After = [IO.File]::ReadAllText($c1.alerted) } catch { }
        Add-Result "C1 ($($shape.n)): an UNSEEN task read through the same file still alerts" `
            ($rc1b.code -eq 2 -and $rc1b.err -like '*failed state*' -and $c1After -like '*task-unseen*') `
            ("the dedupe must let a NEW dead task through, or it is not a dedupe, it is a mute switch. alerted.json read back as $($shape.n). got exit $($rc1b.code), stderr [$($rc1b.err)], alerted.json now [$c1After]")
    }

    # --- C4: the loop guard ----------------------------------------------
    $c4 = New-LwgSupervisorCase -Name 'c4' -Modules @{ failure_capture = $true; log_rotation = $false }
    $rc4 = Invoke-LwgSupervisor -Case $c4 -Event 'Stop' -Tag 'c4-run1' `
                -Payload (New-LwgStopPayload -Case $c4 -FailedIds @('task-one') -StopHookActive)
    Add-Result 'C4: stop_hook_active suppresses the alert' `
        ($rc4.code -eq 0 -and [string]::IsNullOrWhiteSpace($rc4.err)) `
        "with a hook already holding this turn end open, alerting again would loop. got exit $($rc4.code), stderr [$($rc4.err)]"
    Add-Result 'C4: the record is still written under the loop guard' `
        ([IO.File]::Exists($c4.health)) `
        'the loop guard suppresses the ALERT, not the log - a turn that is not recorded is a turn nothing can be reconstructed from'

    # --- C6: PostToolUseFailure ------------------------------------------
    function New-LwgToolFailurePayload {
        param($Case, [bool]$Interrupt)
        return '{"session_id":"' + $Case.session + '","cwd":"' + ($Case.ws -replace '\\', '/') + '",' +
               '"hook_event_name":"PostToolUseFailure","tool_name":"Agent","tool_use_id":"lwg-fixture-tu-1",' +
               '"error":"fixture dispatch error","is_interrupt":' + $(if ($Interrupt) { 'true' } else { 'false' }) + ',' +
               '"tool_input":{"subagent_type":"lwg-fixture-worker","description":"fixture dispatch"}}'
    }

    $c6 = New-LwgSupervisorCase -Name 'c6' -Modules @{ failure_capture = $true; log_rotation = $false }
    $rc6a = Invoke-LwgSupervisor -Case $c6 -Event 'PostToolUseFailure' -Tag 'c6-interrupt' `
                -Payload (New-LwgToolFailurePayload -Case $c6 -Interrupt $true)
    # THE NAME ASSERTS TWO PROPERTIES AND THE CASE TESTED ONE. "logged and NOT
    # alerted" was checked only for the NOT: $c6.health was never read, so a
    # supervisor that had stopped recording interrupts entirely passed. Measured:
    # with Write-Record moved BELOW the `if ($payload.is_interrupt) { exit 0 }`
    # so no interrupt is ever recorded, this row stayed green. C4 at the case
    # above already shows the shape this should have had - it asserts the
    # suppression AND that the record was still written.
    $c6aLog = ''
    try { $c6aLog = [IO.File]::ReadAllText($c6.health) } catch { }
    Add-Result 'C6: an interrupted dispatch is logged and NOT alerted' `
        ($rc6a.code -eq 0 -and [string]::IsNullOrWhiteSpace($rc6a.err) -and
         $c6aLog -like '*"is_interrupt":true*' -and $c6aLog -like '*PostToolUseFailure*') `
        ("a user interrupt is not a fault. Alerting on one turns every deliberate cancellation into an incident - and NOT recording one loses it from the evidence log entirely, which is the half this row used not to check. got exit $($rc6a.code), stderr [$($rc6a.err)], health.jsonl [" + $c6aLog.Trim() + ']')

    $rc6b = Invoke-LwgSupervisor -Case $c6 -Event 'PostToolUseFailure' -Tag 'c6-failure' `
                -Payload (New-LwgToolFailurePayload -Case $c6 -Interrupt $false)
    # STABLE SUBSTRINGS ONLY. The advice on the third line of that message names
    # roles and is reworded; asserting on it would make this case fail for a
    # change of wording rather than a change of behaviour.
    Add-Result 'C6: a genuine dispatch failure alerts (exit 2, reason on stderr)' `
        ($rc6b.code -eq 2 -and $rc6b.err -like '*dispatch*' -and $rc6b.err -like '*fixture dispatch error*') `
        "expected exit 2 and a stderr line naming the failed dispatch and its error; got exit $($rc6b.code), stderr [$($rc6b.err)]"

    # --- C7: failure_capture off -----------------------------------------
    $c7 = New-LwgSupervisorCase -Name 'c7' -Modules @{ failure_capture = $false; log_rotation = $true }
    $rc7 = Invoke-LwgSupervisor -Case $c7 -Event 'Stop' -Tag 'c7-run1' `
                -Payload (New-LwgStopPayload -Case $c7 -FailedIds @('task-one'))
    Add-Result 'C7: with failure_capture off nothing is written and nothing is alerted' `
        ($rc7.code -eq 0 -and [string]::IsNullOrWhiteSpace($rc7.err) -and
         -not [IO.File]::Exists($c7.health) -and -not [IO.File]::Exists($c7.alerted)) `
        "the flag off means zero side effects: no record, no alerted list, exit 0. got exit $($rc7.code), health exists $([IO.File]::Exists($c7.health))"

    # --- C5: log_rotation is independent of failure_capture --------------
    # The rotation call sits ABOVE the failure_capture gate, and that position is
    # the whole point: it used to live inside Write-Record, downstream of the
    # gate, so switching failure capture off left health.jsonl uncapped and
    # growing without bound while log_rotation still reported itself active. A
    # module that is enabled, implemented and unreachable is the exact defect
    # this plugin exists to catch.
    #
    # Both halves of this case run with failure_capture OFF, which is what makes
    # them a test of independence rather than of rotation: nothing appends, so
    # the live file's line count after a rotation is exactly KeepLines.
    function New-LwgOversizedLog {
        param([string]$Path, [int]$Lines = 56000)
        $one = '{"ts":"2026-01-01T00:00:00.0000000Z","event":"Stop","session":"lwg-fixture","cwd":"nowhere","failed_tasks":0}'
        $sb = New-Object System.Text.StringBuilder
        for ($i = 0; $i -lt $Lines; $i++) { [void]$sb.Append($one).Append("`n") }
        [IO.File]::WriteAllText($Path, $sb.ToString(), [Text.UTF8Encoding]::new($false))
    }

    $c5 = New-LwgSupervisorCase -Name 'c5-on' -Modules @{ failure_capture = $false; log_rotation = $true }
    New-LwgOversizedLog -Path $c5.health
    $c5before = (Get-Item $c5.health).Length
    $rc5 = Invoke-LwgSupervisor -Case $c5 -Event 'Stop' -Tag 'c5-run1' `
                -Payload (New-LwgStopPayload -Case $c5 -FailedIds @())
    $c5after  = (Get-Item $c5.health).Length
    $c5lines  = @([IO.File]::ReadAllLines($c5.health)).Count
    Add-Result 'C5: log_rotation runs with failure_capture OFF' `
        ($rc5.code -eq 0 -and [IO.File]::Exists($c5.health + '.1') -and $c5after -lt $c5before) `
        ("the rotation call must sit above the module gate. If it does not, switching failure capture off leaves health.jsonl uncapped while log_rotation reports itself active. before $c5before bytes, after $c5after, archive exists $([IO.File]::Exists($c5.health + '.1'))")
    Add-Result 'C5: the rotated log carries the tail forward and gains no new record' `
        ($c5lines -eq 500) `
        ("the live file must come back holding exactly KeepLines records - the status line reads it with -Tail 300 and a plain truncate would blank the health indicator - and with failure_capture off nothing may be appended on top. got $c5lines line(s)")

    $c5b = New-LwgSupervisorCase -Name 'c5-off' -Modules @{ failure_capture = $false; log_rotation = $false }
    New-LwgOversizedLog -Path $c5b.health
    $c5bBefore = (Get-Item $c5b.health).Length
    $rc5b = Invoke-LwgSupervisor -Case $c5b -Event 'Stop' -Tag 'c5b-run1' `
                -Payload (New-LwgStopPayload -Case $c5b -FailedIds @())
    Add-Result 'C5 mirror: with log_rotation off an oversized log is left alone' `
        ($rc5b.code -eq 0 -and -not [IO.File]::Exists($c5b.health + '.1') -and
         (Get-Item $c5b.health).Length -eq $c5bBefore) `
        'the flag off means the file is left to grow, which is what that flag means. Rotating anyway would make the switch decorative in the other direction'

    # --- C8: no payload-derived field reaches the log uncapped ------------
    # A SHIPPED DEFECT. lib/gate_delegate.ps1 has always put its payload-derived
    # error through Get-LwgRedacted at 200 characters. The supervisor - writing
    # the same class of data, into the file the status line parses on EVERY
    # render - wrote it raw: one crafted payload produced a 200,199-character
    # line in health.jsonl, and because rotation carries the last 500 lines
    # forward, that line was preserved rather than aged out.
    #
    # The assertion is on the LINE LENGTH rather than on the presence of the
    # blob, because the cap is the property that matters: a redaction that left
    # the length unbounded would still poison the reader, and a truncation that
    # skipped the credential patterns would still move a secret into the audit
    # trail. Both halves are checked.
    $c8 = New-LwgSupervisorCase -Name 'c8' -Modules @{ failure_capture = $true; log_rotation = $false }
    $c8blob = 'x' * 200000
    # An invented token shape, assembled from pieces so this tracked file never
    # holds a specimen - the same rule lib/common.ps1's pattern list follows.
    $c8secret = 'ghp_' + ('A1b2C3d4E5f6G7h8J9k0' + 'LmNoPqRsTu')
    $c8payload = '{"session_id":"' + $c8.session + '","cwd":"' + ($c8.ws -replace '\\', '/') + '",' +
                 '"hook_event_name":"PostToolUseFailure","tool_name":"Agent","tool_use_id":"lwg-fixture-tu-8",' +
                 '"error":"' + $c8secret + ' ' + $c8blob + '","is_interrupt":false,' +
                 '"tool_input":{"subagent_type":"lwg-fixture-worker","description":"' + $c8blob + '"}}'
    $rc8 = Invoke-LwgSupervisor -Case $c8 -Event 'PostToolUseFailure' -Tag 'c8-run1' -Payload $c8payload

    $c8lines = @()
    try { $c8lines = @([IO.File]::ReadAllLines($c8.health)) } catch { }
    $c8max = 0
    foreach ($l in $c8lines) { if ($l.Length -gt $c8max) { $c8max = $l.Length } }
    $c8text = ($c8lines -join "`n")

    Add-Result 'C8: no health.jsonl line exceeds the log line cap' `
        ($c8lines.Count -ge 1 -and $c8max -le 8192) `
        ("REGRESSION: a payload-derived field written with no cap produced a 200,199-character line, and statusline.ps1 reads that file on every render. longest line here: $c8max char(s) across $($c8lines.Count) record(s)")
    Add-Result 'C8: the record still names the event it recorded' `
        ($c8text -like '*"event":"PostToolUseFailure"*' -and $c8text -like '*lwg-fixture-tu-8*') `
        ('capping must not turn the record into nothing - it is still the evidence that a dispatch failed. got: ' + $c8text)
    Add-Result 'C8: a credential in a payload field is redacted, not merely truncated' `
        ($c8text -notlike ('*' + $c8secret + '*') -and $c8text -like '*REDACTED*') `
        'the cap and the redaction are separate properties. A field truncated but not masked still moves a credential into this plugin''s own audit trail'
    Add-Result 'C8: the alerting stderr is capped too' `
        ($rc8.code -eq 2 -and $rc8.err.Length -lt 4096 -and $rc8.err -like '*dispatch*') `
        ("that text is injected into the live session as a task notification, so an uncapped field here spends the orchestrator's context instead of the status line's render time. got exit $($rc8.code), $($rc8.err.Length) char(s) of stderr")

    # --- C9: the plugin manufactures the shape its redaction could not see -
    # THE REACHABILITY HALF OF THE NEW REDACTION CASES IN SECTION A. Those call
    # Get-LwgRedacted directly and prove the rule was blind; this one proves the
    # blindness was REACHED, by this file, on a path that runs on every failed
    # dispatch.
    #
    # `error` is sent as an OBJECT rather than a string, which is the whole
    # point: ConvertTo-SafeField takes its ConvertTo-Json -Depth 4 -Compress
    # branch, so the string that arrives at the redaction is
    # {"message":"...","api_key":"..."} - a QUOTED key, which the generic rule
    # in force until 3 August 2026 could not match, because it required the key
    # name to be followed immediately by the separator. The plugin built the one
    # shape its own control could not read, and then logged it.
    #
    # BOTH DESTINATIONS ARE ASSERTED, because they are different exposures with
    # different remedies. health.jsonl sits on disk and is read by the status
    # line on every render. The stderr is injected into the LIVE SESSION as a
    # task notification by asyncRewake, which spends it into the orchestrator's
    # context, where nothing downstream can redact it after the fact.
    #
    # The non-secret half of the field is asserted present in both, because a
    # fix that masked the whole record would pass a leak test and destroy the
    # evidence the record exists for.
    $c9 = New-LwgSupervisorCase -Name 'c9' -Modules @{ failure_capture = $true; log_rotation = $false }
    # Invented, assembled at runtime, and deliberately NOT one of the five
    # vendor shapes - if it were, the vendor layer would catch it and this case
    # would prove nothing about the generic rule.
    $c9secret = 'sk-live-' + 'C9r3d4ct10nF1xtur3'
    $c9payload = '{"session_id":"' + $c9.session + '","cwd":"' + ($c9.ws -replace '\\', '/') + '",' +
                 '"hook_event_name":"PostToolUseFailure","tool_name":"Agent","tool_use_id":"lwg-fixture-tu-9",' +
                 '"error":{"message":"upstream refused","api_key":"' + $c9secret + '"},"is_interrupt":false,' +
                 '"tool_input":{"subagent_type":"lwg-fixture-worker","description":"fixture dispatch"}}'
    $rc9 = Invoke-LwgSupervisor -Case $c9 -Event 'PostToolUseFailure' -Tag 'c9-run1' -Payload $c9payload

    $c9text = ''
    try { $c9text = [IO.File]::ReadAllText($c9.health) } catch { }
    Add-Result 'C9: a credential in a JSON-shaped payload field does not reach health.jsonl' `
        ($c9text -notlike ('*' + $c9secret + '*') -and $c9text -like '*REDACTED*' -and $c9text -like '*upstream refused*') `
        ('REGRESSION: ConvertTo-SafeField serialises a non-scalar field with ConvertTo-Json -Compress and hands the result to Get-LwgRedacted, so the credential arrived as a QUOTED key/value - the one shape the generic rule could not see. It went into this plugin''s own audit trail unmasked. The record must still name the failure it recorded. got: ' + $c9text)
    Add-Result 'C9: nor the stderr that asyncRewake injects into the live session' `
        ($rc9.code -eq 2 -and $rc9.err -notlike ('*' + $c9secret + '*') -and $rc9.err -like '*REDACTED*') `
        ("REGRESSION, and the worse of the two destinations: this text is injected into the running session as a task notification, so an unmasked credential here is spent into the orchestrator's context where no later redaction reaches it. got exit $($rc9.code), stderr [$($rc9.err)]")

    # --- C10: the exits-0 contract, exercised against a broken dependency ---
    # THE HEADER OF lib\supervisor.ps1 SAYS "any internal error exits 0 - a
    # broken supervisor must never break the session", AND NO CASE HAD EVER RUN
    # IT. Six statements used to sit outside the only try that kept the promise -
    # the dot-source, the stdin read, the config read, the repo resolve and both
    # Test-LwgModule calls - under $ErrorActionPreference = 'Stop', so a throw in
    # any of them exited 1 with a raw PowerShell error record on stderr. This
    # handler is registered on five events and exit 2 is its DESIGNED alerting
    # channel on two of them, so exit 1 was a third, undesigned outcome on the
    # same stream.
    #
    # A BROKEN common.ps1 IS THE REALISTIC TRIGGER, not a contrived one: a
    # half-completed /lw-watchtower:update or a partial copy leaves exactly that state,
    # and it is why the other four hook scripts already put their dot-source
    # inside their own try.
    #
    # $PSScriptRoot CANNOT BE OVERRIDDEN, so the script is COPIED next to the
    # broken library rather than pointed at it. The copy is byte-for-byte, so
    # this runs the shipped file.
    #
    # WHAT THIS DOES NOT COVER, stated because the fix does not close it either:
    # the param() block's [ValidateSet] binds BEFORE any statement in the body,
    # so an -HookEvent outside the set still exits 1 and no try can catch it.
    # That is reachable from a wrong hooks.json registration and never from a
    # payload.
    #
    # BASELINE: red against the working tree before this fix, and against
    # fd8d023 and cc44c99, where the dot-source is the second statement in the
    # file and the try opens ~120 lines below it.
    $c10dir = Join-Path $cDir 'c10'
    $c10lib = Join-Path $c10dir 'lib'
    $c10data = Join-Path $c10dir 'data'
    foreach ($d in @($c10dir, $c10lib, $c10data)) { [void][IO.Directory]::CreateDirectory($d) }
    Copy-Item -LiteralPath $SupervisorPath -Destination (Join-Path $c10lib 'supervisor.ps1') -Force
    # Unparseable, so the dot-source throws at parse time rather than producing
    # a library with some functions missing - the loudest form of the fault.
    [IO.File]::WriteAllText((Join-Path $c10lib 'common.ps1'),
        "function Lwg-FixtureBrokenOnPurpose {`n", [Text.UTF8Encoding]::new($false))

    $c10payload = '{"session_id":"lwg-stop-c10","cwd":"' + ($c10dir -replace '\\', '/') + '","hook_event_name":"Stop",' +
                  '"background_tasks":[{"id":"task-c10","type":"agent","status":"failed","description":"fixture dispatch","agent_type":"lwg-fixture-worker"}]}'
    $rc10a = Invoke-LwgHook -ScriptPath (Join-Path $c10lib 'supervisor.ps1') -ScriptArgs '-HookEvent Stop' `
                -Payload $c10payload -PluginRoot $c10dir -DataDir $c10data -WorkDir $c10dir -Tag 'c10-stop'
    Add-Result 'C10: a supervisor whose common.ps1 cannot be dot-sourced still exits 0, silently' `
        ($rc10a.code -eq 0 -and [string]::IsNullOrWhiteSpace($rc10a.err)) `
        ("REGRESSION: the dot-source sat outside the handler, so this exited 1 and printed a raw PowerShell error record - file path, line number, type name - from a governance component whose stated design principle is that it must get out of the way. got exit $($rc10a.code), stderr [$($rc10a.err)]")

    $c10bpayload = '{"session_id":"lwg-stop-c10","cwd":"' + ($c10dir -replace '\\', '/') + '",' +
                   '"hook_event_name":"PostToolUseFailure","tool_name":"Agent","tool_use_id":"lwg-fixture-tu-10",' +
                   '"error":"fixture dispatch error","is_interrupt":false,' +
                   '"tool_input":{"subagent_type":"lwg-fixture-worker","description":"fixture dispatch"}}'
    $rc10b = Invoke-LwgHook -ScriptPath (Join-Path $c10lib 'supervisor.ps1') -ScriptArgs '-HookEvent PostToolUseFailure' `
                -Payload $c10bpayload -PluginRoot $c10dir -DataDir $c10data -WorkDir $c10dir -Tag 'c10-ptuf'
    Add-Result 'C10: and on the event whose stderr the CLI injects into the session' `
        ($rc10b.code -eq 0 -and [string]::IsNullOrWhiteSpace($rc10b.err)) `
        ("this event's stderr is injected into the live session by asyncRewake and exit 2 is its designed alerting channel, so a PowerShell error record here is the same channel carrying an unintended payload. got exit $($rc10b.code), stderr [$($rc10b.err)]")

    # =====================================================================
    # SECTION D - LOG HYGIENE
    # =====================================================================
    Write-Output 'D. log hygiene (rotation in process, status line in a child process)'

    $dDir = Join-Path $work 'd'
    [void][IO.Directory]::CreateDirectory($dDir)

    # Invoke-LwgRotate resolves its own directory through Get-LwgStateDir, which
    # memoises. So the env var is pointed at a throwaway dir and the resolution
    # is REFRESHED - and both are put back at the end of the section.
    #
    # WHAT IS RESTORED HERE IS THE RUN'S SANDBOX, not the operator's environment:
    # the outer sandbox at the top of MAIN is now the floor this nests on. This
    # window is kept because each rotation case reads back the archives and the
    # event records of ONE call, and a directory shared with the rest of the run
    # would not answer that question - it is isolation, not safety.
    $dPrevData = $env:CLAUDE_PLUGIN_DATA

    function New-LwgRotateCase {
        <#
          A throwaway state dir with a health.jsonl in it, and the module's own
          state-dir resolution pointed at it. $Extra lines are appended AFTER
          the filler, so they are what a tail read sees.
        #>
        param([string]$Name, [string[]]$Extra, [int]$Filler = 40)

        $dir = Join-Path $dDir $Name
        [void][IO.Directory]::CreateDirectory($dir)
        $env:CLAUDE_PLUGIN_DATA = $dir
        Get-LwgStateDirInfo -Refresh | Out-Null

        $one = '{"ts":"2026-01-01T00:00:00.0000000Z","event":"Stop","session":"lwg-fixture","cwd":"nowhere","failed_tasks":0}'
        $sb = New-Object System.Text.StringBuilder
        for ($i = 0; $i -lt $Filler; $i++) { [void]$sb.Append($one).Append("`n") }
        foreach ($e in @($Extra)) { [void]$sb.Append($e).Append("`n") }
        $log = Join-Path $dir 'health.jsonl'
        [IO.File]::WriteAllText($log, $sb.ToString(), [Text.UTF8Encoding]::new($false))
        return @{ dir = $dir; log = $log; events = (Join-Path $dir 'lw-watchtower.jsonl') }
    }

    # --- D1: a rotation that cannot complete loses no archive generation --
    # A SHIPPED DEFECT, and the state that triggers it is the ORDINARY one:
    # Add-LwgLine appends with AppendAllText, which holds the file FileShare.Read
    # for the length of the call, and concurrent hooks race on that file by
    # design. With the live log held that way, the old order shifted the archives
    # FIRST - .2 deleted, .1 moved onto it - and then failed to move the live
    # file, producing no new .1. One whole generation was destroyed and the call
    # returned $false, wrote nothing to stderr and logged nothing at all, while
    # its own docstring promised the opposite.
    $d1 = New-LwgRotateCase -Name 'd1' -Extra @()
    [IO.File]::WriteAllText(($d1.log + '.1'), "LWG-FIXTURE-GENERATION-ONE`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText(($d1.log + '.2'), "LWG-FIXTURE-GENERATION-TWO`n", [Text.UTF8Encoding]::new($false))

    # FileAccess.Write + FileShare.Read is exactly what AppendAllText takes, so
    # this is the real concurrent state and not a contrived exclusive lock.
    $d1held = [IO.File]::Open($d1.log, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    $d1ret = $null
    try { $d1ret = Invoke-LwgRotate -FileName 'health.jsonl' -MaxBytes 512 -KeepLines 10 }
    finally { $d1held.Dispose() }

    $d1gen1 = ''; $d1gen2 = ''; $d1events = ''
    try { $d1gen1 = [IO.File]::ReadAllText($d1.log + '.1') } catch { }
    try { $d1gen2 = [IO.File]::ReadAllText($d1.log + '.2') } catch { }
    try { $d1events = [IO.File]::ReadAllText($d1.events) } catch { }

    Add-Result 'D1: a rotation blocked by a held handle destroys no archive generation' `
        ($d1gen1 -like '*GENERATION-ONE*' -and $d1gen2 -like '*GENERATION-TWO*') `
        ("REGRESSION: with the live log held FileShare.Read - the share mode Add-LwgLine's own AppendAllText takes - the archives were shifted before the live file was moved, so .2 was deleted, .1 was moved onto it and no new .1 was ever produced. .1 now holds [" + $d1gen1.Trim() + "], .2 holds [" + $d1gen2.Trim() + ']')
    Add-Result 'D1: the live log is left intact and still oversized' `
        ([IO.File]::Exists($d1.log) -and (Get-Item $d1.log).Length -ge 512) `
        'a rotation that cannot proceed must leave the log alone. Losing it would be worse than leaving it oversized'
    Add-Result 'D1: the failure is REPORTED rather than returned silently' `
        ($d1ret -eq $false -and $d1events -like '*RotateFailed*' -and $d1events -like '*live-move*') `
        ("REGRESSION: the old code exited 0, wrote nothing to stderr and logged nothing, so an operator had no way to learn a generation had gone. The report goes to lw-watchtower.jsonl deliberately - the file being rotated is the one an append may not be able to reach. returned [$d1ret], events: [" + $d1events.Trim() + ']')

    # --- D2: a rotation carries non-ASCII through byte for byte -----------
    # Get-Content -Tail with no -Encoding reads ANSI in Windows PowerShell 5.1
    # while every writer here emits UTF-8, so a record naming an accented path or
    # holding a non-Latin script was mojibaked on EVERY rotation - the rotation
    # corrupted the records it exists to preserve.
    #
    # The record is assembled from code points rather than typed literally, so
    # this tracked file stays pure ASCII and cannot itself be re-encoded into
    # passing or failing by whatever edits it next.
    $dAccent = [string]([char]0x00E9) + [char]0x00E8 + [char]0x00FC + [char]0x00F1
    $dCjk    = [string]([char]0x65E5) + [char]0x672C
    $dUni    = '{"ts":"2026-01-01T00:00:01.0000000Z","event":"Stop","session":"lwg-fixture",' +
               '"cwd":"C:/lwg-fixture/dossiers/' + $dAccent + '","note":"' + $dCjk + '","failed_tasks":0}'
    $d2 = New-LwgRotateCase -Name 'd2' -Extra @($dUni)
    $d2before = [Text.UTF8Encoding]::new($false).GetBytes($dUni)
    $d2ret = Invoke-LwgRotate -FileName 'health.jsonl' -MaxBytes 512 -KeepLines 10
    $d2lines = @([IO.File]::ReadAllLines($d2.log, [Text.UTF8Encoding]::new($false)))
    $d2last  = ''
    if ($d2lines.Count -gt 0) { $d2last = $d2lines[$d2lines.Count - 1] }
    $d2after = [Text.UTF8Encoding]::new($false).GetBytes($d2last)

    Add-Result 'D2: a non-ASCII record survives a rotation byte for byte' `
        ($d2ret -eq $true -and (($d2before -join ',') -eq ($d2after -join ','))) `
        ("REGRESSION: an unencoded Get-Content -Tail reads ANSI in PS 5.1 against UTF-8 writers, so every rotation rewrote accented and non-Latin records as mojibake. expected $($d2before.Count) byte(s), got $($d2after.Count)")
    $d2parsed = $null
    try { $d2parsed = $d2last | ConvertFrom-Json } catch { $d2parsed = $null }
    Add-Result 'D2: and it is still parseable JSON afterwards' `
        ($null -ne $d2parsed -and [string]$d2parsed.cwd -like ('*' + $dAccent + '*')) `
        ('a corrupted record is not merely ugly - the status line parses these lines and drops the ones it cannot read. got: ' + $d2last)

    # --- D3: an oversized record is archived but not carried forward ------
    # The live file is what the status line parses on every render. Carrying a
    # 200,000-character line into it made every later rotation preserve the
    # poison for as long as the log lived, which is why capping the WRITER alone
    # would not have been enough for a log that already holds one.
    #
    # $KeepLines is left at the SHIPPED 500 here, unlike D1 and D2. The tail read
    # is a byte window of $KeepLines records at the maximum record size, so a
    # 10-record window is 80 KB and cannot span a 200 KB line at all - the case
    # would then be testing the window, not the drop. Only $MaxBytes is lowered,
    # which is what makes a small fixture rotate.
    $d3poison = '{"ts":"2026-01-01T00:00:02.0000000Z","event":"Stop","session":"lwg-fixture","cwd":"nowhere","blob":"' + ('x' * 200000) + '","failed_tasks":0}'
    $d3 = New-LwgRotateCase -Name 'd3' -Extra @($d3poison)
    $d3ret = Invoke-LwgRotate -FileName 'health.jsonl' -MaxBytes 512
    $d3live = @([IO.File]::ReadAllLines($d3.log))
    $d3max = 0
    foreach ($l in $d3live) { if ($l.Length -gt $d3max) { $d3max = $l.Length } }
    $d3arch = ''
    try { $d3arch = [IO.File]::ReadAllText($d3.log + '.1') } catch { }
    $d3events = ''
    try { $d3events = [IO.File]::ReadAllText($d3.events) } catch { }

    # `$d3max -le 8192` IS TRUE OF AN EMPTY FILE. $d3max starts at 0 and the loop
    # above never runs on a live log with no lines in it, so "nothing exceeds the
    # cap" was satisfied by a rotation that had discarded everything. Measured:
    # with `if ($dropped -gt 0) { $keep.Clear() }` inserted before the tail is
    # taken - one oversized record wipes the whole live log - all three D3 rows
    # stayed green, and the status line's health indicator loses its input on a
    # build that reports failure_capture active.
    #
    # SO THE CLEAN RECORDS ARE COUNTED. The fixture seeds 40 clean records and
    # one poisoned one; exactly the poisoned one may be dropped. Every "nothing
    # exceeds the cap" assertion needs an "and something is still there" beside
    # it.
    $d3want = 40
    Add-Result 'D3: an oversized record is NOT carried into the live log' `
        ($d3ret -eq $true -and $d3max -le 8192 -and $d3live.Count -eq $d3want) `
        ("REGRESSION: rotation carried the last 500 lines forward without looking at them, so a poisoned record was preserved rather than aged out - and a rotation that emptied the live log instead would satisfy the length half of this row. longest line in the rotated live log: $d3max char(s); lines kept: $($d3live.Count), expected $d3want (the 40 clean records, with only the poisoned one dropped)")
    Add-Result 'D3: the oversized record is still in the archive - nothing is deleted' `
        ($d3arch.Length -gt 200000) `
        'dropping it from the LIVE file is a render-cost decision, not a retention decision. The whole record has to remain readable in .1'
    Add-Result 'D3: the drop is recorded rather than done silently' `
        ($d3events -like '*RotateDroppedRecords*') `
        ('a log that quietly discards records is worse than one that keeps them. events: [' + $d3events.Trim() + ']')

    $env:CLAUDE_PLUGIN_DATA = $dPrevData
    Get-LwgStateDirInfo -Refresh | Out-Null

    # --- D4: one oversized record cannot dominate the render --------------
    # THE MEASUREMENT THAT NAMES THE DEFECT. Get-Content -Tail costs
    # superlinearly in LINE LENGTH, not in file size, so filtering oversized
    # lines after the read fixed nothing - the read had already happened. On this
    # machine, against a 300-record log: 19 ms clean, 9,032 ms with one
    # 200,000-character record, 80,014 ms with ten. Whole-render medians were
    # 1,280 / 10,649 / 105,988 ms.
    #
    # ASSERTED AS A DELTA, never as an absolute duration - see the header. The
    # two medians are taken back to back in the same run on the same machine, and
    # the allowance is enormous compared to the ~150 ms the fix actually costs
    # and tiny compared to the ~100,000 ms the defect did.
    function New-LwgHealthFixture {
        param([string]$Dir, [int]$Poison, [string]$Session)
        [void][IO.Directory]::CreateDirectory($Dir)
        $good = '{"ts":"2026-01-01T00:00:00.0000000Z","event":"Stop","session":"' + $Session + '","cwd":"nowhere","failed_tasks":0}'
        $blob = 'x' * 200000
        $sb = New-Object System.Text.StringBuilder
        for ($i = 0; $i -lt 300; $i++) {
            if ($i -lt $Poison) {
                [void]$sb.Append('{"ts":"2026-01-01T00:00:00.0000000Z","event":"StopFailure","session":"' +
                                 $Session + '","cwd":"nowhere","error":"' + $blob + '"}').Append("`n")
            } else {
                [void]$sb.Append($good).Append("`n")
            }
        }
        [IO.File]::WriteAllText((Join-Path $Dir 'health.jsonl'), $sb.ToString(), [Text.UTF8Encoding]::new($false))
    }

    function Measure-LwgRender {
        <#
          Median wall-clock of $Runs status-line renders against $Dir.

          USERPROFILE IS REDIRECTED to an empty throwaway tree for the duration.
          The status line globs ~/.claude/plugins/data/lw-watchtower* and reads every
          health.jsonl it finds there, so without this the case would be
          measuring the operator's real logs as well as the fixture - and the
          '!' marker asserted below could come from a record this suite never
          wrote. Restored immediately, like the plugin env vars in
          Invoke-LwgHook and for the same reason. The plugin ROOT is still the
          real repo, because the status line's presence probes have to find
          lib\supervisor.ps1 and agents\lw-healer.md or HH renders purple
          without reading anything at all.

          APPDATA AND LOCALAPPDATA GO WITH IT, and that is not tidiness. With
          USERPROFILE moved and those two left alone, powershell.exe failed to
          resolve its LocalApplicationData folder and wrote
          Microsoft\Windows\PowerShell\ModuleAnalysisCache RELATIVE TO THE
          CURRENT DIRECTORY - which for a suite run from the repo is the repo.
          A test suite that leaves an untracked directory in the working tree is
          one careless `git add -A` away from committing it.
        #>
        param([string]$Dir, [string]$Tag, [int]$Runs = 3)

        $sid = 'lwg-stop-render'
        $payload = '{"session_id":"' + $sid + '","cwd":"' + (($dDir + '\ws') -replace '\\', '/') +
                   '","model":{"display_name":"lwg-fixture-model"}}'
        $times = @()
        $last = $null
        $prevProfile = $env:USERPROFILE
        $prevAppData = $env:APPDATA
        $prevLocal   = $env:LOCALAPPDATA
        try {
            $env:USERPROFILE  = $dHome
            $env:APPDATA      = (Join-Path $dHome 'AppData\Roaming')
            $env:LOCALAPPDATA = (Join-Path $dHome 'AppData\Local')
            foreach ($d in @($env:APPDATA, $env:LOCALAPPDATA)) { [void][IO.Directory]::CreateDirectory($d) }
            for ($i = 0; $i -lt $Runs; $i++) {
                $sw = [Diagnostics.Stopwatch]::StartNew()
                $last = Invoke-LwgHook -ScriptPath $StatuslinePath -Payload $payload `
                            -PluginRoot $Root -DataDir $Dir -WorkDir $dDir -Tag ($Tag + $i)
                $sw.Stop()
                $times += [int]$sw.Elapsed.TotalMilliseconds
            }
        } finally {
            $env:USERPROFILE  = $prevProfile
            $env:APPDATA      = $prevAppData
            $env:LOCALAPPDATA = $prevLocal
        }
        $sorted = @($times | Sort-Object)
        return @{ median = $sorted[[int][Math]::Floor($sorted.Count / 2)]; times = $times; render = $last.out }
    }

    $dHome = Join-Path $dDir 'home'
    [void][IO.Directory]::CreateDirectory($dHome)

    $d4clean  = Join-Path $dDir 'render-clean'
    $d4poison = Join-Path $dDir 'render-poison'
    New-LwgHealthFixture -Dir $d4clean  -Poison 0  -Session 'lwg-stop-render'
    New-LwgHealthFixture -Dir $d4poison -Poison 10 -Session 'lwg-stop-render'

    $m4a = Measure-LwgRender -Dir $d4clean  -Tag 'd4-clean-'
    $m4b = Measure-LwgRender -Dir $d4poison -Tag 'd4-poison-'
    $d4delta = $m4b.median - $m4a.median

    Add-Result 'D4: ten oversized records cost the render almost nothing' `
        ($d4delta -lt 5000) `
        ("REGRESSION: the status line read this file with Get-Content -Tail 300, whose cost is superlinear in line length. Ten 200,000-character records took the render median from 1,280 ms to 105,988 ms on this machine - the indicator took a minute and a half to draw, several times a turn. clean median $($m4a.median) ms [$(@($m4a.times) -join ',')], poisoned median $($m4b.median) ms [$(@($m4b.times) -join ',')], delta $d4delta ms")
    Add-Result 'D4: and it SAYS the log held something it could not read' `
        ($m4b.render -match 'HH[0-9]*!' -and $m4a.render -notmatch 'HH[0-9]*!') `
        ("a skipped record could have been a fault, and a fault dropped on the floor renders green - the one failure mode this indicator must never have. The trailing '!' is what keeps the skip visible. poisoned render: [" + (($m4b.render -replace "$([char]27)\[[0-9]+m", '').Trim()) + '], clean render: [' + (($m4a.render -replace "$([char]27)\[[0-9]+m", '').Trim()) + ']')

    # =====================================================================
    # SECTION E - THIS SUITE ITSELF
    # =====================================================================
    # ONE CLAUSE OF THE HEADER'S OWN PROMISE, ASSERTED INSTEAD OF STATED.
    #
    # "NOTHING REAL IS TOUCHED" sat at the top of this file for as long as the
    # file existed and was false for most of it. The child processes were
    # sandboxed; this one was not, so section A's eight non-boolean fixtures put
    # eight ConfigInvalidFlag records into the operator's live event log on every
    # run - 2,679 bytes, measured, and on a machine whose plugin had not written
    # yet it CREATED that file rather than merely growing it.
    #
    # THIS IS THE ONLY CASE HERE THAT COULD HAVE CAUGHT IT. Every other case in
    # this file reads an exit code, a stream, a state file the suite made, or a
    # wall-clock median. A record appended to a file in the operator's profile
    # moves none of those, so 126 green cases and a live leak are the same run -
    # which is the exact shape of assurance this repository keeps warning about,
    # arriving this time in the suite rather than in the thing under test.
    #
    # IT ASSERTS A SIZE, WHICH IS NOT CONTENT, and the limit is real: a run that
    # appended one record and removed exactly as many bytes elsewhere would pass
    # this. No code path reachable from here can produce that shape - the one
    # function in this plugin that rewrites a log in place is Invoke-LwgRotate,
    # and section D only ever calls it with the state dir pointed at its own
    # throwaway directory - and a byte count is a number an operator can check by
    # hand against the file, which a hash of two megabytes is not.
    #
    # IT DOES NOT COVER AN ABORT. If the suite throws before this line the case
    # never runs, and exit 2 is then the only thing said about the environment.
    # The teardown in the finally is what makes that safe going FORWARD; nothing
    # here can testify about a run that did not reach it.
    #
    # IT CAN GO RED FOR A REASON THAT IS NOT THIS SUITE'S, and that was OBSERVED
    # while this case was being written rather than merely feared. The file it
    # watches is the LIVE one and it has exactly one writer per process, not per
    # suite: a Claude Code session open in another window appends to it through
    # its own hooks, and so does a SECOND CHECKOUT of this repository running its
    # own copy of this file. Both happened during development, and this case went
    # red for writes it did not make while the same suite run standalone measured
    # a delta of zero four times.
    #
    # NOT WORKED AROUND, DELIBERATELY. Filtering the log by content would mean
    # parsing two megabytes of JSONL and deciding which records "look like"
    # fixtures, and a check that has to guess at authorship is a check that can
    # be argued with - which is worth less than a blunt one that cannot. So if
    # this case fails ALONE, re-run the suite by itself with no session open
    # before reading it as a regression: the same instruction D4 carries about
    # the clock, and for the same reason.
    Write-Output 'E. this suite (in process)'

    $realLogAfter = Get-LwgRealLogBytes $realLog
    # Built before the call rather than inside the string: a $(if ...) with its
    # own double quotes nested in a double-quoted string is exactly the sort of
    # quoting that parses one way here and another way in a later edit.
    $eBefore = if ($realLogBytes -lt 0) { 'ABSENT' } else { "$realLogBytes byte(s)" }
    $eAfter  = if ($realLogAfter -lt 0) { 'ABSENT' } else { "$realLogAfter byte(s)" }
    $eWhere  = if ([string]::IsNullOrWhiteSpace($realLog)) { '(no state dir resolved)' } else { $realLog }
    Add-Result 'E1: the operator''s live event log is byte-unchanged by this run' `
        ($realLogAfter -eq $realLogBytes) `
        ("REGRESSION: this suite wrote into the operator's own state directory. $eWhere was " +
         "$eBefore before the run and $eAfter after it. Every in-process call that can reach " +
         'Write-LwgEvent has to happen inside the sandbox installed at the top of MAIN - ' +
         "Invoke-LwgHook's window covers child processes only, and section A calls " +
         'Test-LwgModule and Get-LwgModuleFlag in THIS process on eight configs that hold a ' +
         'non-boolean on purpose')

} catch {
    $script:Aborted = "$($_.Exception.Message)  [line $($_.InvocationInfo.ScriptLineNumber)]"
} finally {
    # THE SANDBOX COMES DOWN HERE, not at the end of the body, so an abort
    # cannot leave it standing over the rest of the shell.
    #
    # RESTORED, NOT REMOVED, and the difference matters: a run under Claude Code
    # inherits real values for both of these, and a suite that deleted them
    # would change the environment of whatever runs after it - a later hook
    # would then fall back to discovering its state dir by glob instead of being
    # told, which is the fallback lib\common.ps1 spends forty lines explaining
    # is not reliable. Same reasoning as the window in Invoke-LwgHook, applied
    # to the outer one.
    $env:CLAUDE_PLUGIN_ROOT = $prevPluginRoot
    $env:CLAUDE_PLUGIN_DATA = $prevPluginData
    # The memoised resolution goes back with them. Guarded, because this block
    # also runs when the dot-source above never happened and the function does
    # not exist. Nothing in this process reads the memo after this point; it is
    # put back so that a memo pointing into the directory the next lines delete
    # is not left as a trap for whatever gets added below.
    try { Get-LwgStateDirInfo -Refresh | Out-Null } catch { }

    # Best effort, and deliberately narrow: one directory this script created
    # under the temp root, by a name it generated. Never recursive over anything
    # it was given.
    if ($work -and [IO.Directory]::Exists($work)) {
        try { [IO.Directory]::Delete($work, $true) } catch { }
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
    # Zero cases is an abort wearing a pass's clothes - the empty-set pass this
    # repo has been bitten by before.
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
Write-Output 'Every case above passed. Read that as "these cases still behave", not as'
Write-Output '"mission_drift warns about the right things" - see the header, and'
Write-Output 'docs\gates-removed.md Lesson 3.'
Write-Output 'EXIT: 0'
exit 0
