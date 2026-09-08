#requires -version 5
<#
  LW-WATCHTOWER Stop-hook behaviour suite - the Stop advisory hook and
  effort_ledger.

      powershell -NoProfile -ExecutionPolicy Bypass -File tests\stop_behaviour.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File tests\stop_behaviour.ps1 -Verbose

  WHAT THIS EXISTS FOR. lib\supervisor.ps1 carried two comments describing bugs
  that had already shipped - a dedupe that stopped deduping when alerted.json
  came back from ConvertFrom-Json nested or bare, and a one-element failed-task
  list whose .Count is $null, which logged "failed_tasks":null and left the
  status line green through a real failure - with no case pinning either fix.
  Both are regression cases here (C1, C2), and each was confirmed to go RED with
  the guard removed before it was kept.

  IT WAS BUILT AROUND mission_drift, WHICH IS GONE. That module ran at every
  turn end on every install with no test of any kind, and section B was written
  to end that. The module was removed and its cases went with it; what section B
  held after that was the four cases that were always about something else,
  driven through the same plumbing. Read the section as "the Stop advisory hook,
  end to end" - which is what it was already called by the one case that never
  belonged to mission_drift.

  IT IS NO LONGER FOUR. #167's coverage class 2 added B27-B37 on 6 September
  2026 - twelve rows and thirteen assertions on git_hygiene's interrupted-work
  probes - so section B is now the largest here and git_hygiene is the module it
  covers most. That block also brings TWO things this file's header used to be
  able to state more simply, and both are corrected below rather than left:
  git is now a dependency of one case, and section D is no longer the only
  section that measures.

  ---------------------------------------------------------------------------
  FIVE SECTIONS, AND THEY ANSWER DIFFERENT KINDS OF QUESTION
  ---------------------------------------------------------------------------
  A. PURE HELPERS, in process. lib\common.ps1 is dot-sourced and the prompt
     reader, the path-containment test, the agent frontmatter reader, the two
     flag resolvers and the redaction helper are called directly. These have no
     I/O contract worth a child process, and a unit call names the failure
     precisely - "a typo'd class was coerced to a real one" rather than "the
     advisory did not fire".

     NOT ALL OF THIS IS STOP-HOOK CODE, and it is here because this is where the
     helpers in lib\common.ps1 are exercised. Test-LwgModule decides whether
     every module in sections B and C runs at all; Get-LwgRedacted is what those
     modules put their error text through on the way to the log - it is this
     plugin's ONLY redaction control and it had no test of any kind until these
     cases; Get-LwgPromptText is lib\gate_stop.ps1's turn-boundary reader; and
     Test-LwgPathUnder decides what bin\lwg-uninstall.ps1 is allowed to delete.
     Splitting them into a fourth suite would have bought a third CI step and a
     third copy of this plumbing.

  B. THE STOP ADVISORY HOOK, END TO END, in a child process.
     lib\stop_advisories.ps1 is run for real with a payload on stdin, because
     that is how Claude Code invokes it and because what these cases assert
     lives in state files carried between turns. A turn is one child run.

     ONE CASE OF THIS SUITE NEEDS git ON PATH, AND IT IS THE ONLY ONE. B36
     builds a real repository with a real conflicted index, because an
     unresolved conflict is stage-1/2/3 entries in the INDEX and is not a file
     whose existence can be tested. It is isolated from the operator's own git
     configuration - user.name, user.email and commit.gpgsign are forced on
     every invocation, because a machine with global signing on would otherwise
     block the fixture build on a prompt. WITHOUT git THAT CASE FAILS, with the
     reason on the line; it does not skip. Every other case in that block
     builds a .git DIRECTORY by hand and runs with git REMOVED from the child's
     PATH, which is how they prove those probes cost no subprocess.

     THAT CLAIM WAS FALSE FOR A DAY, and it is stated rather than quietly
     repaired: between 6 and 7 September 2026 B37's reference leg spawned
     `git --version` in THIS process, so a machine without git failed a case
     about how little the probes cost. #337 replaced that leg with an
     in-process one and the claim is true again.

  C. effort_ledger, END TO END, in a child process, the same way -
     lib\supervisor.ps1 -HookEvent <Event>.

  D. LOG HYGIENE - the size, the encoding and the archive set of the files the
     other three sections write. Invoke-LwgRotate is called directly, in this
     process, against a throwaway state dir; the status line is run for real in
     a child process because what section D asserts about it is how long it
     takes, and that is not a property an in-process function call has.

     D MEASURES rather than compares - and since 6 September 2026 it is not the
     only one: B37 measures the class-2 probe cost the same way. Both assert a
     DIFFERENCE between two medians taken back to back on the same machine in
     the same run, never an absolute duration, because an absolute threshold is
     a case that fails on a slow laptop and passes on a fast one for reasons
     that have nothing to do with the code.

     ESCAPING AN ABSOLUTE THRESHOLD IS NOT ENOUGH, AND THIS FILE LEARNED THAT
     BY GOING RED ON main - #337. B37 was written against one real `git`
     subprocess and asserted the probe set cost under a twentieth of it. That
     is a ratio, not a duration, and it is still machine-dependent: the same
     content measured 1:82 on a dev box and 1:17.5 on a GitHub windows-latest
     runner, because process-creation cost and in-process filesystem cost are
     properties of different parts of a host and do not move together. Neither
     leg had regressed. A COMPARATOR MUST BE THE SAME CLASS OF WORK AS THE
     THING IT MEASURES, which is the rule the two measuring cases now follow:
     B37's reference leg is one Test-Path miss - one of the very checks the
     probe set is built from - and section D's is a whole render. Measured
     across the same two machines the new quotient spreads 1.17x rather than
     4.7x: 11.99 on the dev box, 10.22 on the runner.

     THE TWO MEASURING CASES STILL DIFFER ON ONE POINT, AND IT IS DELIBERATE:
     D4 skips under LWG_SUITE_PARALLEL and B37 does not. D4 compares two
     WHOLE-RENDER medians, which sibling load moves differently. B37's two legs
     are the same in-process work taken back to back, so sibling load moves
     them together and cannot change the quotient. The reason the old B37 gave
     for not skipping - that load makes a spawn slower and so makes its
     assertion easier - was true, and was beside the point: it never failed
     under load, it failed on another machine.

     THAT ONE CASE - D4's duration verdict, and only that one - REPORTS SKIPPED
     WHEN LWG_SUITE_PARALLEL IS SET, which tests\doc_claims.ps1 sets in the
     fourteen sibling suites it starts at once (#250). The reasoning above is
     about machine speed and not about thirteen suites running beside this one.
     It is still counted in the tally, it still prints a line saying it skipped,
     and it is still enforced by this suite's own CI step and by every local
     run. Nothing else in this file may skip: a case that cannot run is an abort
     or a failure, never a quiet subtraction.

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
  from the gate suite, which byte-copies the shipped config.json. Each case needs
  ONE module on and every other one off. A fixture states exactly what a case
  assumes; the shipped file would leave the rest of the registry running,
  spawning git and writing advisories that have nothing to do with the question
  being asked.

  EVERY PATH AND EVERY COMMAND NAMED IN A FIXTURE IS INVENTED. No case
  constructs a destructive command, even as a string it never runs, and every
  scratch path is built at runtime from [IO.Path]::GetTempPath() so nothing in
  this tracked file names a machine.

  ---------------------------------------------------------------------------
  WHAT A GREEN RUN DOES NOT MEAN
  ---------------------------------------------------------------------------
  docs\gates-removed.md, Lesson 3: the last gate's suite was 67/67 green while
  five bypasses were open. A green run here says the cases below still behave.
  It does NOT say any of these modules warns about the right things - no case
  here can tell a warning that is correct from one an operator would call noise,
  because that judgement is not in the code. What the cases establish is that
  the code does what its own comments say it does.

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
    # The PLUGIN PAYLOAD root - lw-watchtower\ under this file's parent, not the
    # repository root, which is what this parameter meant before the restructure, correct for a run from
    # anywhere as long as this file stays in tests\.
    [string]$Root
)

$ErrorActionPreference = 'Stop'

# THE PAYLOAD ROOT, WHICH IS NO LONGER THE REPOSITORY ROOT. `Split-Path -Parent
# $PSScriptRoot` is the parent of tests\, and tests\ stayed at the repository
# root while the shipped plugin moved under lw-watchtower/. Everything this
# suite composes off $Root - bin\, lib\, config.json, statusline\ - is payload,
# so $Root is the payload root and the default says so in one place rather than
# in every Join-Path below it.
#
# WHY THE DEFAULT AND NOT A -Root FROM CI. Neither .github\workflows\ci.yml nor
# tests\doc_claims.ps1's sibling runner passes -Root at any invocation, so a
# suite's default is the only value it ever gets on either route. Putting the
# knowledge here is the only place it can be put.
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Join-Path (Split-Path -Parent $PSScriptRoot) 'lw-watchtower' }

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
      A config.json fixture: every key of the shipped `modules` block, each one
      OFF unless the case asked for it. Written through ConvertTo-Json so a
      fixture cannot be malformed by a quoting mistake here and then read as
      "config unreadable", which Get-LwgConfig FAILS OPEN on - turning every
      module back on and quietly making the case test the opposite of what it
      says.

      THE NAME LIST IS THE SHIPPED ONE and has to stay that way. A key that
      exists in config.json and not here is a module left to its default, which
      is ON, so a case would silently be running a module it never named.
    #>
    param([string]$Dir, [hashtable]$Modules)

    $mods = [ordered]@{}
    foreach ($k in @('effort_ledger', 'self_health',
                     'log_rotation', 'docs_coupling', 'git_hygiene', 'context_injection')) {
        $mods[$k] = $(if ($null -ne $Modules -and $Modules.ContainsKey($k)) { [bool]$Modules[$k] } else { $false })
    }

    $cfg = [ordered]@{
        version     = '0.2.0'
        modules     = [pscustomobject]$mods
        repos       = [pscustomobject]@{}
        interaction = [pscustomobject]@{ delegate = $false }
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
    #     [bool](Get-LwgModuleOption ... -Default $true)
    #
    # so an empty string or a 0 silently switched a suppressor OFF and the module
    # went on to warn about work it exists to excuse.
    #
    # THE FIXTURE NAMES git_hygiene/use_gh, WHICH IS THE LIVE PAIR. The defect
    # was found on mission_drift's require_outside_root and the two cases that
    # drove the real hook with it lived in section B; that module was removed
    # and both went with it. These cases are about the FUNCTION, so they were
    # re-pointed at a caller that still exists rather than deleted with it.
    #
    # WHAT THESE CASES CAN AND CANNOT ESTABLISH, said plainly because the honest
    # red set is small. Against the pre-fix tree they fail because the FUNCTION
    # DOES NOT EXIST, which is a weaker red than a wrong answer - they pin the
    # rule, they do not prove the defect.
    #
    # THE FLOOR IS THE CALLER'S $Default, not a fixed polarity - a
    # `module_config` key is tuning, not the module's switch - so "ignored"
    # means "tuned as shipped" and the current caller ships $true.
    $fTrue  = New-LwgModCfg '{"module_config":{"git_hygiene":{"use_gh":true}}}'
    $fFalse = New-LwgModCfg '{"module_config":{"git_hygiene":{"use_gh":false}}}'
    Add-Result 'modcfg: a real true is honoured' `
        (Get-LwgModuleFlag -Config $fTrue -Module 'git_hygiene' -Key 'use_gh' -Default $false) `
        'CANNOT GO RED against code that runs. Pinned because refusing the values that were always valid is the regression a boolean-only rule is likeliest to introduce'
    Add-Result 'modcfg: a real false is honoured' `
        (-not (Get-LwgModuleFlag -Config $fFalse -Module 'git_hygiene' -Key 'use_gh' -Default $true)) `
        'CANNOT GO RED against code that runs, and it is the one an operator relies on: switching a suppressor off must actually switch it off'

    $fAbsent = New-LwgModCfg '{"module_config":{"git_hygiene":{}}}'
    Add-Result 'modcfg: an absent key falls to the caller default' `
        (Get-LwgModuleFlag -Config $fAbsent -Module 'git_hygiene' -Key 'use_gh' -Default $true) `
        'CANNOT GO RED against code that runs. A stripped-down config must yield a working module, not a module tuned by whatever [bool] $null happens to be'

    $fEmpty = New-LwgModCfg '{"module_config":{"git_hygiene":{"use_gh":""}}}'
    Add-Result 'modcfg: the EMPTY STRING is ignored rather than read as off' `
        (Get-LwgModuleFlag -Config $fEmpty -Module 'git_hygiene' -Key 'use_gh' -Default $true) `
        '[bool]"" is $false, so an empty string silently disarmed the suppressor. An empty string is not false, it is not a value at all'

    $fZero = New-LwgModCfg '{"module_config":{"git_hygiene":{"use_gh":0}}}'
    Add-Result 'modcfg: the NUMBER 0 is ignored rather than read as off' `
        (Get-LwgModuleFlag -Config $fZero -Module 'git_hygiene' -Key 'use_gh' -Default $true) `
        '[bool]0 is $false. JSON has real booleans, so a 0 here is a mistake, and a mistake must not be read as a decision'

    $fStr = New-LwgModCfg '{"module_config":{"git_hygiene":{"use_gh":"false"}}}'
    Add-Result 'modcfg: the STRING "false" is ignored, so the default stands' `
        (Get-LwgModuleFlag -Config $fStr -Module 'git_hygiene' -Key 'use_gh' -Default $true) `
        'CANNOT GO RED - [bool] on a non-empty string was $true, the same answer by the wrong route. Pinned because the ANSWER is the uncomfortable one: an operator who wrote "false" has a suppressor that is still on, and the rule now says so in the log instead of guessing at the quotes'

    # The record, through the SAME helper, naming the module in the block so a
    # reader can tell module_config.git_hygiene from the `modules` entry of
    # the same name.
    $fLogDir = Join-Path $aDir 'invalidmodcfg'
    [void][IO.Directory]::CreateDirectory($fLogDir)
    $fPrevData = $env:CLAUDE_PLUGIN_DATA
    $fEvents = ''
    try {
        $env:CLAUDE_PLUGIN_DATA = $fLogDir
        Get-LwgStateDirInfo -Refresh | Out-Null
        [void](Get-LwgModuleFlag -Config $fZero -Module 'git_hygiene' -Key 'use_gh' -Default $true)
        try { $fEvents = [IO.File]::ReadAllText((Join-Path $fLogDir 'lw-watchtower.jsonl')) } catch { }
    } finally {
        $env:CLAUDE_PLUGIN_DATA = $fPrevData
        Get-LwgStateDirInfo -Refresh | Out-Null
    }

    Add-Result 'modcfg: an ignored value is written as ConfigInvalidFlag naming module_config and the module' `
        ($fEvents -match '"event":"ConfigInvalidFlag"' -and
         $fEvents -match '"block":"module_config\.git_hygiene"' -and
         $fEvents -match '"key":"use_gh"') `
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
    # for the log, and the resolver command this repository shipped until
    # wave 1 PRINTED its output into a fixed-column console report, a row at a
    # time. That command and its library half were deleted with the clearing
    # mechanism (#192); the one-line and text-only properties below were
    # written against it, and they are kept because the LOG has them too.
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
        "the resolver command deleted in wave 1 (#192) printed this value into a fixed-column report one row per fault, and the text inside it is a failed task's stderr. A raw newline splits one record into two ROWS, and the second row is a fault record the operator never had. The reader that remains is the JSONL log, where the same newline splits one event into two LINES. got: $rNl"

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
        "CANNOT GO RED AT fd8d023 - nothing was masked there either. It is the BLAST-RADIUS guard on the rules above, and the direction they fail in is over-redaction: the keyword may now be followed by more identifier, so a wider keyword list would start masking session_id, tool_name and failed_tasks - the fields the status line exists to read, and which the resolver command deleted in wave 1 (#192) read too. got: $(Get-LwgRedacted -Text $rBenign -MaxLength 400)"

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
        "REGRESSION, and it goes red at fd8d023 TOO - this gap predates the 3 August rules and was carried forward by them. The vendor pattern replaced the marker LINE and left every base64 byte standing behind it, which is a redaction that redacts nothing of value. The worst reachable destination it had was mission_drift's anchor builder, which read / as a PATH SEPARATOR - / is in the base64 alphabet - so a surviving body was PROMOTED to the anchor kind that advisory QUOTED BACK; that module is gone, and the destinations that remain - the event log and the DocsCoupling sample - make an unredacted key no less of a leak. The second half of this assertion is the deliberate boundary: a block with no END line still loses only its BEGIN line, exactly as before, because making the trailing group mandatory would have meant a truncated key matching nothing at all. got: $rPemOut / $rPemTrunc"

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
    # SECTION B - THE STOP ADVISORY HOOK, END TO END
    # =====================================================================
    # lib\stop_advisories.ps1 run for real, with a payload on stdin, because that
    # is how Claude Code invokes it and because what these cases assert lives in
    # state files carried between turns. A turn is one child run.
    #
    # IT USED TO BE mission_drift's SECTION and is now the surviving modules'.
    # When that module was removed the cases that drove it went with it; what is
    # was left was the plumbing plus the three cases that were always about
    # something else - the edit-list writer (B22, B23) and git_hygiene's
    # UNKNOWN (B24) - joined later by the timeout tree kill (B26) and, on
    # 6 September 2026, by git_hygiene's coverage class 2 (B27-B37), which is
    # now the largest block in the file. B25 was context_pressure's refusal and
    # went with that module the same day; see the tombstone where it stood.
    Write-Output 'B. stop advisories (child process)'

    $bDir = Join-Path $work 'b'
    [void][IO.Directory]::CreateDirectory($bDir)

    function New-LwgStopCase {
        <#
          One case's world:

            <case>\root\           throwaway plugin root, holding config.json
            <case>\root\data\      throwaway state dir (CLAUDE_PLUGIN_DATA)
            <case>\ws\             the workspace - the payload's cwd
            <case>\outside\        a SIBLING of ws, for edits outside the workspace
            <case>\transcript.jsonl

          ws has no .git, so Get-LwgRepoInfo resolves no root and the workspace
          root falls back to the payload's cwd - the same path either way, but
          reached by the branch a session outside a repository takes. B24 and
          the whole of B27-B36 create a .git inside their own ws to take the
          other branch - a DIRECTORY built by hand in every case but B36, which
          needs a real repository, and B34, whose .git is a FILE holding a
          gitdir pointer because it is the linked-worktree case.
        #>
        param([string]$Name, [hashtable]$Modules)

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

        # NOTHING IS ON BY DEFAULT. Every case names the module it is about,
        # so a case can never be testing a second module by accident - which is
        # what the old default of `mission_drift = $true` made possible for any
        # case that forgot to pass -Modules.
        $mods = $(if ($null -ne $Modules) { $Modules } else { @{} })
        Write-LwgFixtureConfig -Dir $c.root -Modules $mods
        [IO.File]::WriteAllText($c.tx, '', [Text.UTF8Encoding]::new($false))
        return $c
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
          and state dir. docs_coupling's recording half was driven by no case in
          this suite until B22/B23; the Stop-side cases seed edits-<key>.txt by
          hand through Set-LwgEdits, which tests the reader and never the
          writer.

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

    # --- B22: the edit list ROLLS past its cap, it does not stop recording --
    # THE WRITER'S CAP WAS A HARD STOP. `if (size -gt 262144) { exit 0 }` runs
    # before the append, so past the cap no further edit in that session was
    # ever recorded - and the reading module carried on reporting active.
    # docs_coupling went on warning "and no documentation did" about a session
    # that had spent an hour editing documentation, because no doc path could be
    # recorded any more. A module that looks enabled and observes nothing, which
    # is what this plugin exists to catch.
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
    $b22 = New-LwgStopCase -Name 'b22' -Modules @{ docs_coupling = $true }
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
        ("REGRESSION: the writer stopped recording at the cap instead of rolling, so docs_coupling went on reporting active while observing nothing further. Seeded $($b22Filler.Count) lines ($b22Was bytes); the hook exited $($rb22.code) and the list now holds $($b22Now.Count) line(s), last: [" + $(if ($b22Now.Count) { $b22Now[-1] } else { '<none>' }) + "]. stderr: [$($rb22.err)]")

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
    # docs_coupling is the only module switched on for this case, so the only
    # advisory the envelope can carry is the one under test.
    #
    # BASELINE: red against the working tree before this fix, and against
    # fd8d023 and cc44c99 - `Add-LwgLine ... -Line ($path.Replace(...))` with no
    # cap, and a bare `Split-Path $_ -Leaf` into the message, at all three.
    $b23 = New-LwgStopCase -Name 'b23' -Modules @{ docs_coupling = $true }
    # Assembled at runtime and separator-free, which is what makes Split-Path
    # -Leaf hand it back whole. `.ps1` is what makes it classify as source.
    $b23Path = ('x' * 200000) + '.ps1'
    $rb23    = Invoke-LwgPostEdit -Case $b23 -Path $b23Path -Tag 'b23-postedit'
    $b23Line = @(Get-LwgCaseEditLines $b23)
    $b23Max  = 0
    foreach ($l in $b23Line) { if ($l.Length -gt $b23Max) { $b23Max = $l.Length } }

    Add-Result 'B23: an oversized file_path is bounded at the WRITE, and still recorded' `
        ($rb23.code -eq 0 -and $b23Line.Count -eq 1 -and $b23Max -le 1100) `
        ("REGRESSION: the 200 000-character value landed whole in edits-<key>.txt, taking ~76% of the 256 KB window the Stop half reads and displacing the session's real edit history from docs_coupling - while leaving the file under the writer's cap, so recording continued and the picture stayed wrong rather than obviously broken. A bound that dropped the record instead would fail this row too: it wants one line, bounded. got $($b23Line.Count) line(s), longest $b23Max chars. stderr: [$($rb23.err)]")

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

    # --- B8: it never blocks ----------------------------------------------
    # Asserted on the envelope B23 actually emitted rather than on a fresh run.
    # On Stop a hook blocks by exiting 2 or by printing {"decision":"block"};
    # this envelope must have no decision member at all, and the exit code is
    # already asserted above.
    #
    # IT USED TO HANG OFF B1, mission_drift's firing case, which was the first
    # advisory this section produced. That module is gone, so the assertion
    # moved to the first advisory that is still produced here rather than being
    # dropped with it - what it pins is a property of the SCRIPT, not of any one
    # module.
    #
    # suppressOutput IS ASSERTED HERE TOO. It was pinned by
    # Test-LwgMissionAdvisory, the envelope checker every mission case ran
    # through, and that helper went with those cases - so without this conjunct
    # nothing in the suite would notice the raw JSON envelope being shown to the
    # operator instead of the message inside it.
    # IT IS NOT NESTED ON THE ENVELOPE PARSE ANY MORE, and the old form was
    # `if ($null -ne $b23Env) { ... }`. $b23Env is what B23 above establishes,
    # so that condition was another case's assertion wearing a different hat: an
    # advisory that stopped emitting failed B23 and DELETED B8 - the only check
    # in this file that no module may block a turn end, which is the plugin's
    # central constraint.
    #
    # MEASURED ON THIS TREE, 3 September 2026. With docs_coupling's emit
    # disabled in lib\stop_advisories.ps1 (`if ($onDocs)` forced false) so the
    # module is still loaded, still reads the edit list and simply never
    # produces an advisory, this suite printed
    #
    #   RESULT: 115 of 116 case(s) passed in 37169 ms
    #
    # against a file that holds 117 cases. One case was not skipped-with-a-note,
    # it was NOT RUN, and no line in the output said so. This file declares no
    # $script:ExpectedCases the way tests\gate_delegate.ps1 does, so nothing
    # else caught the smaller denominator either.
    #
    # WITH THE GUARD GONE THE ROW FAILS INSTEAD. $hasDecision already defaults
    # $false and $b23Suppress does too, both filled inside a try, so a $null
    # envelope makes the assertion false rather than making the case vanish -
    # and the detail says "there was no envelope to inspect", which is a
    # different statement from "the envelope carried a decision member" and must
    # not be confused with it. Same shape as $aUnresolved in
    # tests\gate_delegate.ps1 section A.
    $hasDecision  = $false
    $b23Suppress  = $false
    try { $hasDecision = ($null -ne ($b23Env.PSObject.Properties | Where-Object { $_.Name -eq 'decision' })) } catch { }
    try { $b23Suppress = ($b23Env.suppressOutput -eq $true) } catch { }
    Add-Result 'B8: the advisory envelope carries NO decision member, and suppresses its own output' `
        ((-not $hasDecision) -and $rb23s.out -notlike '*decision*' -and $b23Suppress) `
        $(if ($null -eq $b23Env) {
            'there was no envelope on stdout to inspect, so this case did NOT pass and it did NOT establish anything about whether a module can block a turn end. Fix B23 above it first. stdout: [' + $rb23s.out + ']'
          } else {
            "a decision member would make this advisory able to block a turn end, which no module in this plugin may do; suppressOutput false shows the operator the raw envelope instead of the message: $($rb23s.out)"
          })

    # --- B9: the loop guard suppresses the whole run ------------------------
    # EVERY Stop hook here honours the same contract: when the payload carries
    # stop_hook_active the turn end is a CONTINUATION of one this script has
    # already spoken on, and it must stand down rather than say the same thing
    # again. The guard is the first statement in the try - `if
    # ($payload.stop_hook_active) { exit 0 }` - and it is a property of the
    # SCRIPT, not of any one module, which is why the fixture below arms
    # docs_coupling and then proves the guard beat it.
    #
    # THE SECOND ROW IS WHAT MAKES THE FIRST WORTH ANYTHING. Silence alone would
    # also be produced by a run that read the edit list, resolved the state file
    # and wrote both, and then merely declined to print - which is a turn end
    # that still costs everything the guard exists to save. The state directory
    # is seeded with the edit list ONLY, so anything else appearing in it is
    # work this run did.
    #
    # IT USED TO RUN AGAINST mission_drift, as the old B9, and went with that
    # module's cases; it is restored here against a module that still exists,
    # because the guard it pins did not go anywhere.
    $b9 = New-LwgStopCase -Name 'b9' -Modules @{ docs_coupling = $true }
    Set-LwgEdits -Case $b9 -Paths @(
        (Join-Path $b9.ws 'module\umbergate_one.ps1'),
        (Join-Path $b9.ws 'module\umbergate_two.ps1'),
        (Join-Path $b9.ws 'module\umbergate_three.ps1'))
    $b9Before = @(Get-ChildItem -LiteralPath $b9.data -Force | ForEach-Object { $_.Name })
    $rb9 = Invoke-LwgStop -Case $b9 -Tag 'b9-continuation' -StopHookActive
    $b9After = @(Get-ChildItem -LiteralPath $b9.data -Force | ForEach-Object { $_.Name })

    Add-Result 'B9: stop_hook_active suppresses the whole run' `
        ($rb9.code -eq 0 -and [string]::IsNullOrWhiteSpace($rb9.out) -and [string]::IsNullOrWhiteSpace($rb9.err)) `
        ("the same source-files-and-no-docs condition WOULD have warned without the guard - B23 fires on it - so a continuation that speaks repeats a warning the operator has already read. exit $($rb9.code), stdout [$($rb9.out)], stderr [$($rb9.err)]")

    Add-Result 'B9: nothing was read or written under the state dir' `
        (($b9After.Count -eq $b9Before.Count) -and $b9Before.Count -eq 1) `
        ("the guard is the FIRST statement in the try, so a continuation must cost nothing at all - not a state file, not an advisory record, not a context-window observation. Before: [" + ($b9Before -join ', ') + "] After: [" + ($b9After -join ', ') + "]")

    # --- B25: DELETED 6 SEPTEMBER 2026 (#168) -------------------------------
    # TWO CASES STOOD HERE and their subject no longer exists. They pinned
    # context_pressure's impossible-occupancy refusal and the two-turn
    # corroboration that let a genuine 1M window be learned - both properties
    # of an inferred denominator, and the module doing the inferring is gone.
    # The transition ladder that replaced it reads a real
    # context_window.used_percentage out of signals/ratelimit.json, so there is
    # no denominator to get wrong and nothing for these cases to assert. They
    # are DELETED rather than retargeted: a case rewritten to keep a number in
    # a tally is a case that has stopped being about anything. The ladder's own
    # cases are C11-C14 in section C, where the code it exercises now lives.

    # --- B24: git_hygiene's UNKNOWN is not deduped into silence -------------
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
    $b24 = New-LwgStopCase -Name 'b24' -Modules @{ git_hygiene = $true }
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

    # --- the timeout path, against a real process table ------------------
    # B26 IS THE OBSERVATION #98 SAID DID NOT EXIST. That issue argued from what
    # git and gh are known to spawn that Process.Kill() on the timeout path
    # leaves a helper running, and the counter-argument recorded on it - that no
    # orphan had ever been observed from this plugin, so paying for a tree kill
    # was the wrong trade - was true when it was written. This case plants a real
    # grandchild under a real child, drives the REAL timeout branch, and then
    # reads the process table. Against the pre-fix file it reports the grandchild
    # ALIVE. So the decision is reopened by a measurement rather than by an
    # argument, and lib\stop_advisories.ps1 now tree-kills.
    #
    # THE HELPERS ARE EXTRACTED BY AST rather than dot-sourced. Dot-sourcing
    # lib\stop_advisories.ps1 would run the whole Stop hook and exit 0 out of
    # this suite, so the three functions are lifted from the SHIPPED FILE'S OWN
    # TEXT by [Language.Parser]::ParseFile - the same reader .github\workflows
    # already uses on this tree. Nothing is retyped here, so this cannot pass
    # against a copy that has drifted from the file it is testing.
    #
    # WHY -TimeoutMs 1 IS NOT A ONE-MILLISECOND RACE. The handle carries its own
    # stopwatch, started at launch, and the remaining budget is TimeoutMs MINUS
    # that. The marker poll above has already burned far more than 1 ms, so the
    # budget is 0 and the timeout branch is entered deterministically.
    $b26 = @{ ok = $false; detail = ''; gcPid = -1; chPid = -1; state = ''; kill = ''; alive = $true }
    $b26h = $null
    $b26dir = Join-Path $work 'b26'
    [void][IO.Directory]::CreateDirectory($b26dir)
    try {
        $b26tok = $null; $b26perr = $null
        $b26ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $AdvisoryPath, [ref]$b26tok, [ref]$b26perr)
        # Two are REQUIRED and the tree killer is OPTIONAL, deliberately. Making
        # Stop-LwgProcessTree mandatory would turn this case against the pre-fix
        # file into "the fixture could not be built", which is an abort and not
        # a red - and a regression case that cannot FAIL for the reason it names
        # proves nothing. Lifted this way it drives the real timeout branch of
        # whichever version it is pointed at, and reports the grandchild alive
        # when that version leaves it alive.
        $b26need = @('Start-LwgProcess', 'Complete-LwgProcess')
        $b26want = $b26need + @('Stop-LwgProcessTree')
        $b26defs = @($b26ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $b26want -contains $n.Name
        }.GetNewClosure(), $true))
        $b26got = @($b26defs | ForEach-Object { $_.Name })
        foreach ($n in $b26need) {
            if ($b26got -notcontains $n) {
                throw ("lib\stop_advisories.ps1 no longer defines $n, so this case could not be built at all")
            }
        }
        foreach ($d in $b26defs) { . ([scriptblock]::Create($d.Extent.Text)) }

        # The grandchild announces its own pid and then outlives everything it
        # is allowed to. The child spawns it and sleeps, so the child is the one
        # that hits the timeout and the grandchild is the thing Kill() misses.
        $b26marker = Join-Path $b26dir 'grandchild.pid'
        $b26gc     = Join-Path $b26dir 'grandchild.ps1'
        $b26ch     = Join-Path $b26dir 'child.ps1'
        [IO.File]::WriteAllText($b26gc, (
            '[IO.File]::WriteAllText(' + "'" + $b26marker + "'" + ', [string]$PID)' + "`r`n" +
            'Start-Sleep -Seconds 60' + "`r`n"), [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($b26ch, (
            "Start-Process -FilePath 'powershell' -WindowStyle Hidden -ArgumentList " +
            "@('-NoProfile','-ExecutionPolicy','Bypass','-File','" + $b26gc + "')" + "`r`n" +
            'Start-Sleep -Seconds 60' + "`r`n"), [Text.UTF8Encoding]::new($false))

        $b26h = Start-LwgProcess -File 'powershell' `
            -ProcArgs @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $b26ch) -WorkDir $b26dir
        # Read BEFORE anything that can throw. Every abort below this line -
        # the marker never appearing, most of all - leaves two 60-second
        # sleepers behind unless the cleanup knows their pids.
        try { $b26.chPid = [int]$b26h.p.Id } catch { $b26.chPid = -1 }
        if ($b26h.state -ne 'running') { throw "the child did not start: state=$($b26h.state) err=$($b26h.err)" }

        $b26sw = [Diagnostics.Stopwatch]::StartNew()
        while ($b26sw.Elapsed.TotalSeconds -lt 20 -and -not [IO.File]::Exists($b26marker)) {
            Start-Sleep -Milliseconds 100
        }
        if (-not [IO.File]::Exists($b26marker)) {
            throw 'the grandchild never wrote its marker, so the fixture never armed and this case established nothing'
        }
        $b26.gcPid = [int]([IO.File]::ReadAllText($b26marker).Trim())

        $b26r      = Complete-LwgProcess -Handle $b26h -TimeoutMs 1
        $b26.state = [string]$b26r.state
        $b26.kill  = [string]$b26r.kill

        # The OS reaps asynchronously. Poll rather than assert immediately, so a
        # slow machine reports a real result instead of a timing artefact.
        $b26sw = [Diagnostics.Stopwatch]::StartNew()
        while ($b26sw.Elapsed.TotalSeconds -lt 10) {
            $b26.alive = $false
            try { $null = Get-Process -Id $b26.gcPid -ErrorAction Stop; $b26.alive = $true } catch { }
            if (-not $b26.alive) { break }
            Start-Sleep -Milliseconds 200
        }

        $b26.ok = ($b26.state -eq 'timeout' -and -not $b26.alive)
        $b26.detail = ("state=$($b26.state) kill=$($b26.kill) grandchild pid $($b26.gcPid) alive=$($b26.alive)")
    } catch {
        $b26.ok = $false
        $b26.detail = 'the fixture did not run: ' + $_.Exception.Message
    } finally {
        # A red run, AND EVERY ABORT PATH ABOVE, must leave nothing sleeping on
        # the machine. The child tree goes first, by the same mechanism the fix
        # uses, because on the paths that threw before the timeout ran the child
        # is still alive and is the grandchild's parent; then the grandchild by
        # pid, because on the paths where the tree kill was the thing under test
        # it may be all that is left.
        #
        # BOTH ARE GUARDED ON NOT-KNOWN-DEAD, and that is not tidiness. A pid
        # whose process has exited can be reissued by Windows, so cleaning up a
        # pid this case has already watched die is a way of killing somebody
        # else's process. state is set only when Complete-LwgProcess returned -
        # which is the path on which the child is already dead - and alive is
        # left $true until the poll above actually observes the grandchild gone.
        if ($b26.chPid -gt 0 -and [string]::IsNullOrEmpty($b26.state)) {
            try {
                $b26tk = New-Object System.Diagnostics.ProcessStartInfo
                $b26tk.FileName               = 'taskkill'
                $b26tk.Arguments              = ('/PID {0} /T /F' -f $b26.chPid)
                $b26tk.UseShellExecute        = $false
                $b26tk.CreateNoWindow         = $true
                $b26tk.RedirectStandardOutput = $true
                $b26tk.RedirectStandardError  = $true
                $b26k = [System.Diagnostics.Process]::Start($b26tk)
                if ($null -ne $b26k) {
                    try { $b26k.StandardOutput.ReadToEndAsync() | Out-Null } catch { }
                    try { $b26k.StandardError.ReadToEndAsync()  | Out-Null } catch { }
                    try { if (-not $b26k.WaitForExit(2000)) { $b26k.Kill() } } catch { }
                    try { $b26k.Dispose() } catch { }
                }
            } catch { }
        }
        if ($b26.gcPid -gt 0 -and $b26.alive) {
            try { Stop-Process -Id $b26.gcPid -Force -ErrorAction SilentlyContinue } catch { }
        }
    }
    Add-Result 'B26: on timeout the child AND the helper it spawned are killed' `
        $b26.ok `
        ("REGRESSION for #98, and it was RED before the fix: Process.Kill() on .NET Framework 4.x terminates the direct child only - there is no Kill(bool entireProcessTree) before .NET Core 3.0 - so a git or gh that had spawned a credential helper left it running with the inherited write ends of the redirected pipes. Expected state=timeout and the grandchild gone; got " + $b26.detail + ". Any kill= other than plain 'taskkill' - 'taskkill-failed' (not startable), 'taskkill-exit-<n>' (started and refused), 'taskkill-timeout' - means the tree kill did not do its job, which leaves the OLD behaviour and is a real failure of the fix rather than of the fixture. An empty kill= is the pre-fix file, which had no tree kill at all.")

    # =====================================================================
    # B27-B37: COVERAGE CLASS 2 - INTERRUPTED OPERATIONS AND CONFLICTS (#167)
    # =====================================================================
    # WHAT THESE PIN, AND WHY THEY EXIST. #167's coverage class 2 - "no
    # half-finished rebase, merge, cherry-pick or bisect, no unresolved
    # conflicts, no forgotten stashes" - was ENTIRELY ABSENT from git_hygiene,
    # not partially covered. Measured on the baseline below:
    #
    #     grep -c 'MERGE_HEAD|REBASE_HEAD|CHERRY_PICK_HEAD|BISECT_LOG|stash'
    #         lw-watchtower/lib/stop_advisories.ps1      ->  0
    #
    # So a tree stopped in the middle of a rebase produced EXACTLY the advisory
    # a clean tree produced, and an interrupted rebase is the state three of
    # the September session's worktrees were actually found in.
    #
    # BASELINE: main = 97f0697. Every row below went RED against that tree,
    # with two stated exceptions that could not and are labelled where they
    # sit: B35 is the anti-vacuity control (it PASSES before the fix, which is
    # the point of it), and B36's second row asserts the count carried in the
    # event record rather than the sentence.
    #
    # NO git IS RUN TO BUILD THE MARKER FIXTURES. Every one of B27-B35 plants
    # a hand-built .git the way B24 does, and runs the hook with git REMOVED
    # FROM PATH. That is deliberate and it is the strongest form of the claim:
    # these six probes are pure Test-Path, they cost no subprocess, and they
    # therefore still answer on a machine where git cannot be reached at all -
    # where the rest of this module can only report UNKNOWN. B36 is the one
    # case that needs a real git, because an unresolved conflict lives in the
    # INDEX and the index is not a file whose existence answers the question.
    #
    # SEVEN PROBES FOR SIX CONDITIONS, and the seventh is not padding.
    # `git gc` PACKS refs/stash INTO packed-refs - measured on this machine,
    # git 2.53.0.windows.2: after `git stash` then `git gc`, .git/refs/stash is
    # GONE and the stash is still there. .git/logs/refs/stash survives, because
    # reflogs are never packed, and it is removed when the last stash is popped
    # (also measured). So the stash probe reads both, and B33 is the case that
    # would go red if the packed half were ever dropped.

    # git is made unresolvable for the child exactly as B24 does it: PATH is
    # replaced with System32 plus the PowerShell directory the .cmd needs to
    # find `powershell` by name. Nothing real is touched and nothing is
    # uninstalled. Neither directory holds git on any install.
    $c2sys  = Join-Path ([Environment]::GetFolderPath('Windows')) 'System32'
    $c2path = $c2sys + ';' + (Join-Path $c2sys 'WindowsPowerShell\v1.0')

    function New-LwgGitDirFixture {
        <#
          A .git DIRECTORY inside the case's ws, built by hand - no git is run
          to make it. Get-LwgRepoInfo resolves a root by walking for .git and
          parsing `config`, and never spawns anything to do it, so a fixture
          built this way reaches git_hygiene carrying whatever markers the case
          planted and needs no git to have planted them.

          NO REMOTE IN THE CONFIG, deliberately: remote_count 0 is what makes
          git_hygiene skip the rev-list probe, so these cases exercise the
          class-2 path and nothing else.

            -Files  paths under .git created as FILES
            -Dirs   paths under .git created as DIRECTORIES
        #>
        param($Case, [string[]]$Files = @(), [string[]]$Dirs = @())

        $g = Join-Path $Case.ws '.git'
        [void][IO.Directory]::CreateDirectory($g)
        [IO.File]::WriteAllText((Join-Path $g 'config'),
            "[core]`n`trepositoryformatversion = 0`n", [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $g 'HEAD'),
            "ref: refs/heads/lwg-fixture`n", [Text.UTF8Encoding]::new($false))
        foreach ($d in $Dirs) { [void][IO.Directory]::CreateDirectory((Join-Path $g $d)) }
        foreach ($f in $Files) {
            $p = Join-Path $g $f
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $p))
            [IO.File]::WriteAllText($p, "0000000000000000000000000000000000000000`n",
                [Text.UTF8Encoding]::new($false))
        }
        return $g
    }

    function Get-LwgStopMessage {
        <#
          One turn, and the systemMessage it produced. A hashtable so the
          detail string of a failing row can name the exit code and stderr as
          well as the sentence, which is what tells "the module said nothing"
          apart from "the hook fell over".
        #>
        param($Case, [string]$Tag, [string]$PathOverride)
        $r = Invoke-LwgStop -Case $Case -Tag $Tag -PathOverride $PathOverride
        $m = ''
        try { $m = [string](($r.out | ConvertFrom-Json).systemMessage) } catch { }
        return @{ code = $r.code; err = $r.err; out = $r.out; msg = $m }
    }

    # --- B27: a half-finished rebase, the merge backend ---------------------
    # `git rebase -i`, and any rebase that stops on a conflict, leaves
    # .git\rebase-merge\. The branch is mid-rewrite: the commits the operator
    # believes are on it are not the commits on disk.
    $b27 = New-LwgStopCase -Name 'b27' -Modules @{ git_hygiene = $true }
    [void](New-LwgGitDirFixture -Case $b27 -Dirs @('rebase-merge'))
    $r27 = Get-LwgStopMessage -Case $b27 -Tag 'b27-turn1' -PathOverride $c2path
    Add-Result 'B27: a half-finished rebase (rebase-merge) is reported at turn end' `
        ($r27.code -eq 0 -and $r27.msg -like '*REBASE is IN PROGRESS*') `
        ("RED at 97f0697, where this module had no probe for an interrupted operation of any kind and a tree mid-rebase produced the same advisory as a clean one. exit $($r27.code), message [$($r27.msg)], stderr [$($r27.err)]")

    # --- B28: a half-finished rebase, the apply backend ---------------------
    # `git rebase --apply` and `git am` use .git\rebase-apply\ instead. Two
    # backends, two directories, one condition - a fix that probed only the
    # first would pass B27 and leave half the real cases silent.
    $b28 = New-LwgStopCase -Name 'b28' -Modules @{ git_hygiene = $true }
    [void](New-LwgGitDirFixture -Case $b28 -Dirs @('rebase-apply'))
    $r28 = Get-LwgStopMessage -Case $b28 -Tag 'b28-turn1' -PathOverride $c2path
    Add-Result 'B28: a half-finished rebase (rebase-apply) is reported at turn end' `
        ($r28.code -eq 0 -and $r28.msg -like '*REBASE is IN PROGRESS*') `
        ("RED at 97f0697. This is the second rebase backend and it is a separate row on purpose: a probe for rebase-merge alone passes B27 and says nothing about a 'git rebase --apply' or a 'git am' that stopped. exit $($r28.code), message [$($r28.msg)], stderr [$($r28.err)]")

    # --- B29: a half-finished merge -----------------------------------------
    $b29 = New-LwgStopCase -Name 'b29' -Modules @{ git_hygiene = $true }
    [void](New-LwgGitDirFixture -Case $b29 -Files @('MERGE_HEAD'))
    $r29 = Get-LwgStopMessage -Case $b29 -Tag 'b29-turn1' -PathOverride $c2path
    Add-Result 'B29: a half-finished merge (MERGE_HEAD) is reported at turn end' `
        ($r29.code -eq 0 -and $r29.msg -like '*MERGE is IN PROGRESS*') `
        ("RED at 97f0697. exit $($r29.code), message [$($r29.msg)], stderr [$($r29.err)]")

    # --- B30: a half-finished cherry-pick -----------------------------------
    $b30 = New-LwgStopCase -Name 'b30' -Modules @{ git_hygiene = $true }
    [void](New-LwgGitDirFixture -Case $b30 -Files @('CHERRY_PICK_HEAD'))
    $r30 = Get-LwgStopMessage -Case $b30 -Tag 'b30-turn1' -PathOverride $c2path
    Add-Result 'B30: a half-finished cherry-pick (CHERRY_PICK_HEAD) is reported at turn end' `
        ($r30.code -eq 0 -and $r30.msg -like '*CHERRY-PICK is IN PROGRESS*') `
        ("RED at 97f0697. exit $($r30.code), message [$($r30.msg)], stderr [$($r30.err)]")

    # --- B31: a half-finished bisect ----------------------------------------
    # A bisect leaves HEAD wherever the search put it, which is neither where
    # the operator left it nor a branch - so work committed during one is the
    # detached-HEAD loss case with a second way to arrive at it.
    $b31 = New-LwgStopCase -Name 'b31' -Modules @{ git_hygiene = $true }
    [void](New-LwgGitDirFixture -Case $b31 -Files @('BISECT_LOG'))
    $r31 = Get-LwgStopMessage -Case $b31 -Tag 'b31-turn1' -PathOverride $c2path
    Add-Result 'B31: a half-finished bisect (BISECT_LOG) is reported at turn end' `
        ($r31.code -eq 0 -and $r31.msg -like '*BISECT is IN PROGRESS*') `
        ("RED at 97f0697. exit $($r31.code), message [$($r31.msg)], stderr [$($r31.err)]")

    # --- B32: a forgotten stash, loose ref ----------------------------------
    # Stashed work is invisible to `git status`, belongs to no branch, is not
    # pushed by anything, and goes with the clone. It is the class-2 condition
    # closest in shape to the committed-but-unpushed commit #167 ranks first.
    $b32 = New-LwgStopCase -Name 'b32' -Modules @{ git_hygiene = $true }
    [void](New-LwgGitDirFixture -Case $b32 -Files @('refs\stash'))
    $r32 = Get-LwgStopMessage -Case $b32 -Tag 'b32-turn1' -PathOverride $c2path
    Add-Result 'B32: a forgotten stash (refs/stash) is reported at turn end' `
        ($r32.code -eq 0 -and $r32.msg -like '*STASH*') `
        ("RED at 97f0697. exit $($r32.code), message [$($r32.msg)], stderr [$($r32.err)]")

    # --- B33: a forgotten stash AFTER git gc has packed the ref -------------
    # THIS ROW IS A MEASUREMENT, NOT A GUESS. On this machine, git
    # 2.53.0.windows.2: `git stash` then `git gc` leaves .git/refs/stash GONE
    # and the stash still held, because gc packs it into packed-refs. A probe
    # that read only refs/stash would report a clean tree on any repository
    # that had been gc'd since its last stash - which is most of them, since gc
    # runs itself. .git/logs/refs/stash survives gc (reflogs are never packed)
    # and is removed when the last stash is popped, so it is the half that
    # covers the packed case without inventing a false positive.
    $b33 = New-LwgStopCase -Name 'b33' -Modules @{ git_hygiene = $true }
    [void](New-LwgGitDirFixture -Case $b33 -Files @('logs\refs\stash'))
    $r33 = Get-LwgStopMessage -Case $b33 -Tag 'b33-turn1' -PathOverride $c2path
    Add-Result 'B33: a stash whose ref git gc has PACKED is still reported' `
        ($r33.code -eq 0 -and $r33.msg -like '*STASH*') `
        ("RED at 97f0697, and it is also the row that fails if the packed half of the stash probe is ever dropped for being redundant - it is not. Measured: after git stash + git gc, .git/refs/stash does not exist and the stash does. exit $($r33.code), message [$($r33.msg)], stderr [$($r33.err)]")

    # --- B34: a LINKED WORKTREE reads two different git directories ---------
    # The per-worktree git dir holds MERGE_HEAD, CHERRY_PICK_HEAD, BISECT_LOG
    # and the rebase directories; refs/ - and therefore the stash - lives in the
    # SHARED one, which is a different directory entirely and is reached through
    # the `commondir` pointer. Get-LwgRepoInfo already resolves both (gitdir and
    # common); a probe that used one for everything would miss half the
    # conditions in exactly the place this project does most of its work, since
    # every lane in this repository runs in a linked worktree.
    #
    # The fixture is the real on-disk shape: .git as a FILE holding
    # `gitdir: <path>`, that directory holding `commondir` and MERGE_HEAD, and
    # the shared directory holding config and refs/stash and NOT MERGE_HEAD.
    $b34 = New-LwgStopCase -Name 'b34' -Modules @{ git_hygiene = $true }
    $b34wt  = Join-Path $b34.dir 'worktreegit'
    $b34com = Join-Path $b34.dir 'commongit'
    foreach ($d in @($b34wt, $b34com, (Join-Path $b34com 'refs'))) { [void][IO.Directory]::CreateDirectory($d) }
    [IO.File]::WriteAllText((Join-Path $b34.ws '.git'), ('gitdir: ' + $b34wt + "`n"),
        [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $b34wt 'commondir'), "..\commongit`n",
        [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $b34wt 'MERGE_HEAD'),
        "0000000000000000000000000000000000000000`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $b34com 'config'),
        "[core]`n`trepositoryformatversion = 0`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $b34com 'refs\stash'),
        "0000000000000000000000000000000000000000`n", [Text.UTF8Encoding]::new($false))
    $r34 = Get-LwgStopMessage -Case $b34 -Tag 'b34-turn1' -PathOverride $c2path
    Add-Result 'B34: in a LINKED WORKTREE the merge is read from the worktree git dir and the stash from the shared one' `
        ($r34.code -eq 0 -and $r34.msg -like '*MERGE is IN PROGRESS*' -and $r34.msg -like '*STASH*') `
        ("RED at 97f0697, and it is the row that fails if both probes are pointed at the same directory. MERGE_HEAD exists ONLY in the per-worktree git dir and refs/stash ONLY in the shared one, which is where git actually puts them; every lane in this repository runs in a linked worktree. exit $($r34.code), message [$($r34.msg)], stderr [$($r34.err)]")

    # --- B35: CONTROL - a repository with none of the markers says none of it
    # THIS ROW PASSES BEFORE THE FIX AS WELL AS AFTER, and that is what it is
    # for. Every row above is satisfied by a module that shouts about a rebase
    # on every repository it sees; this one is not. It is the same shape as
    # B25's second row - the anti-vacuity guard for the eight above it - and it
    # is labelled here rather than left for somebody to discover that a whole
    # block of cases could be passed by a constant.
    $b35 = New-LwgStopCase -Name 'b35' -Modules @{ git_hygiene = $true }
    [void](New-LwgGitDirFixture -Case $b35)
    $r35 = Get-LwgStopMessage -Case $b35 -Tag 'b35-turn1' -PathOverride $c2path
    Add-Result 'B35: a repository with NO interrupted operation reports none of them' `
        ($r35.code -eq 0 -and $r35.msg -notlike '*IN PROGRESS*' -and $r35.msg -notlike '*STASH*') `
        ("CANNOT GO RED against the pre-fix tree - it is the anti-vacuity control for B27-B34, which are all satisfied by a module that reports an interrupted rebase unconditionally. The UNKNOWN sentence IS expected here, because git is off PATH for this child; nothing about an interrupted operation is. exit $($r35.code), message [$($r35.msg)], stderr [$($r35.err)]")

    # --- B35, second row: the log is not DOUBLED on the git-less path -------
    # THE COST OF THE FIX ABOVE, PINNED. Moving the GitHygiene record out of
    # the "git answered" branch is what lets a class-2 finding reach
    # lw-watchtower.jsonl on a machine with no git - and gated on the condition
    # list alone it would ALSO fire here, because `query-failed` is a condition
    # and it is on this path at every turn end. That is a second record per
    # turn, for ever, on the machine this module's own header calls the one
    # that matters, saying the same thing GitHygieneUnavailable already says
    # and carrying nothing but zeroes. The record it must NOT write is a
    # GitHygiene; the record it must still write is the Unavailable one, so
    # both halves are asserted - a "fix" that silenced the path entirely would
    # satisfy the first and undo B24.
    #
    # BASELINE: RED against 7e61bd0, the first commit of this slice, where the
    # gate was $conds.Count alone and this case reports TWO records.
    $b35ev = ''
    try { $b35ev = [IO.File]::ReadAllText((Join-Path $b35.data 'lw-watchtower.jsonl')) } catch { }
    Add-Result 'B35: git off PATH writes the Unavailable record and NOT a second GitHygiene one' `
        ($b35ev -like '*"event":"GitHygieneUnavailable"*' -and $b35ev -notlike '*"event":"GitHygiene"*') `
        ("a GitHygiene record here would be a zeroed duplicate of the Unavailable record beside it, written at every turn end for the whole session on any machine where git is missing, hanging or refusing. lw-watchtower.jsonl held:`n$b35ev")

    # --- B36: an UNRESOLVED CONFLICT is named, in a REAL repository ---------
    # THE ONE CASE HERE THAT NEEDS A REAL git, and the reason is structural: an
    # unresolved conflict lives in the INDEX as stage-1/2/3 entries, and there
    # is no file under .git whose existence answers "is anything conflicted".
    # The five interrupted operations each have one; a conflict does not.
    #
    # SO IT COSTS NO NEW SUBPROCESS EITHER. `git status --porcelain=v2` is
    # already launched by this module on every turn end in a repository, and
    # its `u` lines ARE the unmerged paths. Before this change they were summed
    # into the tracked-changes count and never named, which is #167's "conflicts
    # by name" in one line. The count still includes them - `dirty` did not move
    # - and the conflict is now said out loud beside it.
    #
    # THE FIXTURE IS ISOLATED FROM THE OPERATOR'S GIT CONFIG. user.name,
    # user.email and commit.gpgsign are forced on every invocation: a machine
    # with commit.gpgsign true globally would otherwise BLOCK the fixture build
    # on a signing prompt, and one with no user.email would fail the commit.
    # HEAD is set by symbolic-ref rather than `init -b`, which is 2.28+.
    $b36 = New-LwgStopCase -Name 'b36' -Modules @{ git_hygiene = $true }
    $b36armed = $false
    $b36err   = ''
    try {
        $b36ver = ''
        $prevEap = $ErrorActionPreference
        try { $ErrorActionPreference = 'Continue'; $b36ver = (& git --version 2>&1 | Out-String).Trim() }
        finally { $ErrorActionPreference = $prevEap }
        if ($b36ver -notlike 'git version*') {
            throw ("git is not resolvable from this suite's own process, so the one case here that needs a real index could not be built. git --version said [$b36ver]. This is an ABORT rather than a skip: a suite that quietly subtracts a case reports green about something it never ran.")
        }

        function Invoke-LwgFixtureGit {
            param([string]$WorkDir, [string[]]$GitArgs)
            $iso = @('-c', 'user.name=lwg fixture', '-c', 'user.email=lwg@example.invalid',
                     '-c', 'commit.gpgsign=false', '-c', 'core.autocrlf=false',
                     '-c', 'gc.auto=0')
            $prev = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                $null = & git -C $WorkDir @iso @GitArgs 2>&1
            } finally { $ErrorActionPreference = $prev }
        }

        $b36f = Join-Path $b36.ws 'conflicted.txt'
        Invoke-LwgFixtureGit -WorkDir $b36.ws -GitArgs @('init', '--quiet')
        Invoke-LwgFixtureGit -WorkDir $b36.ws -GitArgs @('symbolic-ref', 'HEAD', 'refs/heads/lwgmain')
        [IO.File]::WriteAllText($b36f, "base`n", [Text.UTF8Encoding]::new($false))
        Invoke-LwgFixtureGit -WorkDir $b36.ws -GitArgs @('add', '--', 'conflicted.txt')
        Invoke-LwgFixtureGit -WorkDir $b36.ws -GitArgs @('commit', '--quiet', '-m', 'base')
        Invoke-LwgFixtureGit -WorkDir $b36.ws -GitArgs @('checkout', '--quiet', '-b', 'lwgside')
        [IO.File]::WriteAllText($b36f, "side`n", [Text.UTF8Encoding]::new($false))
        Invoke-LwgFixtureGit -WorkDir $b36.ws -GitArgs @('commit', '--quiet', '-a', '-m', 'side')
        Invoke-LwgFixtureGit -WorkDir $b36.ws -GitArgs @('checkout', '--quiet', 'lwgmain')
        [IO.File]::WriteAllText($b36f, "trunk`n", [Text.UTF8Encoding]::new($false))
        Invoke-LwgFixtureGit -WorkDir $b36.ws -GitArgs @('commit', '--quiet', '-a', '-m', 'trunk')
        Invoke-LwgFixtureGit -WorkDir $b36.ws -GitArgs @('merge', 'lwgside')

        $b36armed = [IO.File]::Exists((Join-Path $b36.ws '.git\MERGE_HEAD'))
        if (-not $b36armed) {
            throw 'the merge did not conflict, so the fixture never armed and this case would have established nothing'
        }
    } catch {
        $b36err = $_.Exception.Message
    }

    $r36 = $(if ($b36armed) { Get-LwgStopMessage -Case $b36 -Tag 'b36-turn1' } else { @{ code = -1; err = $b36err; out = ''; msg = '' } })
    Add-Result 'B36: an unresolved CONFLICT is named, not folded into the change count' `
        ($b36armed -and $r36.code -eq 0 -and $r36.msg -like '*UNRESOLVED CONFLICT*') `
        ("RED at 97f0697, where the porcelain-v2 'u' lines were counted as ordinary tracked changes and the word conflict appeared nowhere. Fixture armed: $b36armed. exit $($r36.code), message [$($r36.msg)], stderr [$($r36.err)]")

    $b36ev = ''
    try { $b36ev = [IO.File]::ReadAllText((Join-Path $b36.data 'lw-watchtower.jsonl')) } catch { }
    Add-Result 'B36: the GitHygiene record carries the conflict count' `
        ($b36armed -and $b36ev -like '*"conflicts":1*') `
        ("the sentence is what the operator reads and the record is what anything else reads; a fix that only wrote the sentence leaves every reader of lw-watchtower.jsonl unable to tell a conflicted turn end from a merely dirty one. lw-watchtower.jsonl held:`n$b36ev")

    # --- B37: the probes cost what the file checks they are made of cost -----
    # THE BUDGET CASE. It is a DIFFERENCE OF MEDIANS taken back to back on the
    # same machine in the same run - section D's method, for section D's
    # reason: an absolute millisecond threshold is a case that fails on a slow
    # laptop and passes on a fast one for reasons that have nothing to do with
    # the code. It is on its SECOND comparator, because the first one was
    # machine-dependent in exactly the way an absolute threshold is, and this
    # suite found that out the expensive way.
    #
    # WHAT THE FIRST COMPARATOR WAS, AND HOW IT FAILED - #337. Until 7
    # September 2026 this case asserted that the probe set cost under a
    # TWENTIETH of one real `git` subprocess round trip, on the reasoning that
    # #167's triage calls these probes free next to the `git status` this
    # module already pays for. That escaped an absolute duration and landed on
    # a RATIO that is no more portable:
    #
    #   dev box <hostname>, 6 Sept   probes 1.17 ms   one git spawn 96.85 ms   1:82
    #   GitHub windows-latest        probes 2.15 ms   one git spawn 37.67 ms   1:17.5
    #
    # NEITHER LEG REGRESSED. The hosted runner creates a process about 2.6x
    # faster than this dev box, which pays a large per-spawn tax to its
    # security software, while the runner's in-process file checks are about
    # 1.8x SLOWER. Process-creation cost and in-process filesystem cost are
    # properties of different parts of a host and do not scale together, so the
    # quotient of the two moved by roughly 4.7x between two machines and
    # crossed the line. `main` went RED on the #330 merge, on content that had
    # passed on its own branch sixteen minutes before.
    #
    # THE COMPARATOR NOW IS ONE Test-Path MISS, and it is machine-stable
    # because it is THE SAME CLASS OF WORK as the thing being measured. The
    # probe set is seven Test-Path calls against paths that are absent on a
    # clean tree plus the Join-Path calls that build them; the reference leg is
    # one of those same calls against one of those same absent paths. Whatever
    # a host charges for a cmdlet dispatch and a failed file stat it charges
    # both legs alike, so the quotient is a property of the FUNCTION rather
    # than of the machine - bounded below by the seven checks the function must
    # make and above by the dozen or so dispatches it makes in all.
    #
    # MEASURED ON BOTH KINDS OF MACHINE BEFORE THE BAR WAS SET, which is the
    # part the first comparator skipped. Dev box <hostname> under four
    # concurrent build lanes, three separate sweeps: 11.86, 12.00, 11.99. A
    # GitHub windows-latest runner, from a deliberately failing CI run whose
    # only purpose was to make it print: 10.22 (probe set 1.3072 ms, one check
    # 0.1279 ms). A SPREAD OF 1.17x ACROSS THE TWO MACHINES, against the old
    # comparator's 4.7x on the same pair. No idle reading was taken on either
    # machine and none is claimed; what can be said is that the machine the bar
    # was calibrated on read the HIGHER of the two, so the bar is the
    # conservative one for the runner.
    #
    # THE BAR IS FORTY AND IT IS DELIBERATELY LOOSE. What is being guarded is
    # "this answers with file checks and nothing else", not a target - and the
    # distance to the thing it catches is enormous ON BOTH MACHINES, which is
    # the point of stating it twice: one `git` spawn costs about a THOUSAND of
    # these checks on the dev box (93.86 ms against 0.093 ms) and about THREE
    # HUNDRED on the runner (37.67 ms against 0.128 ms), so a probe set that
    # grew a process spawn, a directory enumeration or a file read would miss
    # this bar by orders of magnitude and not by inches. A bar set close to its
    # own measurement is how the first comparator failed.
    #
    # IT SPAWNS NOTHING NOW, which is what makes this file's header claim -
    # that B36 is the only case here needing `git` on PATH - true. The old
    # reference leg ran `git --version`, so on a machine without git this case
    # failed for a reason that had nothing to do with what it asserts.
    #
    # IT DOES NOT SKIP UNDER LWG_SUITE_PARALLEL, and the reason is now better
    # than the one it replaced. The old reason was that load makes a spawn
    # slower and so makes the assertion strictly easier - true, and beside the
    # point, since this failed across machines and not under load. The reason
    # now is that both legs are the same class of in-process work taken back to
    # back in one run, so sibling load moves them TOGETHER. That is also why D4
    # still skips and this does not: D4's two legs are whole renders, which
    # load moves differently.
    #
    # LEG ORDER IS REVERSED ON ALTERNATE ROUNDS and one warm-up sweep is
    # discarded - lib\subagent_start.ps1's measurement standard, cited by #311.
    #
    # RED-FIRST, BASELINE 010a550. At that commit this case carried the ratio
    # above, and the runner figures recorded on #337 fail it: 2.15 ms is not
    # under 37.67 / 20 = 1.88 ms, while the same content passes on the dev box.
    # A verdict that depends on which machine ran it is the defect. The
    # comparator below passes on both, and was confirmed to go red by putting a
    # single subprocess inside Get-LwgInterruptedOps - the regression this case
    # exists to catch - which reads 410.67 file checks against the bar of 40.
    $b37 = @{ ok = $false; detail = ''; probe = -1.0; check = -1.0 }
    try {
        $b37tok = $null; $b37perr = $null
        $b37ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $AdvisoryPath, [ref]$b37tok, [ref]$b37perr)
        $b37want = @('Get-LwgInterruptedOps')
        $b37defs = @($b37ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $b37want -contains $n.Name
        }.GetNewClosure(), $true))
        $b37got = @($b37defs | ForEach-Object { $_.Name })
        foreach ($n in $b37want) {
            if ($b37got -notcontains $n) {
                throw ("lib\stop_advisories.ps1 does not define $n, so the probe cost could not be measured at all")
            }
        }
        foreach ($d in $b37defs) { . ([scriptblock]::Create($d.Extent.Text)) }

        $b37dir = Join-Path $work 'b37'
        $b37git = Join-Path $b37dir '.git'
        [void][IO.Directory]::CreateDirectory($b37git)
        [IO.File]::WriteAllText((Join-Path $b37git 'config'),
            "[core]`n`trepositoryformatversion = 0`n", [Text.UTF8Encoding]::new($false))

        # THE CLEAN TREE IS THE CASE THAT MATTERS. Every probe misses, so every
        # one of the seven Test-Path calls runs - the most expensive shape this
        # function has, and the one every turn end on a tidy repository pays.
        # The reference leg is ONE of those same seven, against the same absent
        # path, so what separates the two legs is exactly the work this function
        # does around its file checks.
        $b37K = 100
        $b37ref = Join-Path $b37git 'MERGE_HEAD'
        $b37probeTimes = New-Object 'System.Collections.Generic.List[double]'
        $b37checkTimes = New-Object 'System.Collections.Generic.List[double]'

        $b37probeLeg = {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            for ($i = 0; $i -lt $b37K; $i++) {
                $null = Get-LwgInterruptedOps -GitDir $b37git -Common $b37git
            }
            $sw.Stop()
            return ($sw.Elapsed.TotalMilliseconds / $b37K)
        }

        $b37checkLeg = {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            for ($i = 0; $i -lt $b37K; $i++) {
                $null = Test-Path -LiteralPath $b37ref -PathType Leaf
            }
            $sw.Stop()
            return ($sw.Elapsed.TotalMilliseconds / $b37K)
        }

        $null = & $b37probeLeg      # warm-up, discarded
        $null = & $b37checkLeg      # warm-up, discarded

        for ($b37r = 0; $b37r -lt 9; $b37r++) {
            if ($b37r % 2 -eq 0) {
                [void]$b37probeTimes.Add([double](& $b37probeLeg))
                [void]$b37checkTimes.Add([double](& $b37checkLeg))
            } else {
                [void]$b37checkTimes.Add([double](& $b37checkLeg))
                [void]$b37probeTimes.Add([double](& $b37probeLeg))
            }
        }

        $b37ps = @($b37probeTimes | Sort-Object)
        $b37cs = @($b37checkTimes | Sort-Object)
        $b37.probe = [double]$b37ps[[int][Math]::Floor($b37ps.Count / 2)]
        $b37.check = [double]$b37cs[[int][Math]::Floor($b37cs.Count / 2)]

        # One call of the whole probe set must cost under forty of the file
        # checks it is built out of, measured on the machine running it. The
        # bar is deliberately loose: the CLAIM is "this answers with file checks
        # and nothing else", and anything that broke it - a spawn, a directory
        # walk, a file read - costs hundreds of these checks, not forty.
        $b37.ok = ($b37.check -gt 0) -and ($b37.probe -lt ($b37.check * 40.0))
        $b37.detail = ("probe median $([Math]::Round($b37.probe, 4)) ms/call [$((@($b37probeTimes | ForEach-Object { [Math]::Round($_, 4) })) -join ',')], one Test-Path miss median $([Math]::Round($b37.check, 4)) ms [$((@($b37checkTimes | ForEach-Object { [Math]::Round($_, 4) })) -join ',')], the probe set costs $([Math]::Round($(if ($b37.check -gt 0) { $b37.probe / $b37.check } else { 0 }), 2)) file checks against a bar of 40")
    } catch {
        $b37.ok = $false
        $b37.detail = 'the measurement did not run: ' + $_.Exception.Message
    }
    Add-Result 'B37: the class-2 probes cost under forty of the file checks they are made of' `
        $b37.ok `
        ("#167's triage claims these probes are free next to the git status git_hygiene already pays for, and this is the measurement rather than the assertion. Difference of medians, nine rounds, leg order reversed on alternate rounds, one warm-up sweep discarded, both legs on this machine in this run. THE COMPARATOR IS A FILE CHECK AND NOT A SUBPROCESS BECAUSE A SUBPROCESS MADE THIS VERDICT DEPEND ON THE MACHINE (#337): against one git spawn the same probe set measured 1:82 on a dev box (1.17 ms against 96.85 ms) and 1:17.5 on a GitHub windows-latest runner (2.15 ms against 37.67 ms), which is a 4.7x spread with neither leg regressing, and the twentieth-of-a-spawn bar it used to carry failed on the runner alone. Against its own file checks the same probe set measures 11.99 on that dev box and 10.22 on that runner - a spread of 1.17x rather than 4.7x, which is the whole reason this bar is counted in file checks. $($b37.detail)")

    # =====================================================================
    # SECTION C - effort_ledger and log_rotation, END TO END
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
    # SubagentStop joined this list when the reconciliation began running there
    # too: on that event an un-rewaked exit 2 would tell a subagent that has just
    # finished to carry on, which is worse than the missed alert it replaces.
    foreach ($ev in @('Stop', 'PostToolUseFailure', 'SubagentStop')) {
        $entry = @(@($hooks.hooks.$ev) | Where-Object { ($_ | ConvertTo-Json -Depth 8 -Compress) -like '*supervisor.ps1*' })[0]
        $h = @($entry.hooks)[0]
        Add-Result "C0 registration: the $ev supervisor entry sets asyncRewake" `
            ($h.asyncRewake -eq $true) `
            "this script exits 2 on $ev to alert the orchestrator. Without asyncRewake, exit 2 BLOCKS instead of alerting"
    }

    # THE REWAKE HEADER IS PART OF THE ALERT, and on Stop it now sits in front
    # of THREE different findings. asyncRewake injects rewakeMessage ahead of
    # this script's stderr and rewakeSummary into the operator's task list, so
    # that text is the FIRST SENTENCE the model and the operator read. Until
    # 6 September 2026 it was "Health supervisor detected background task
    # failure:" on an event that can now raise a failed background task, an
    # orphaned agent, or a transition-ladder tier - so a session at 90% of its
    # 5-hour limit with nothing failed at all was told a background task had
    # failed, in a header it could not see was generic. A wrong first sentence
    # on the one channel that reaches the model is a wrong answer, not a
    # cosmetic one.
    #
    # ASSERTED AS AN ABSENCE, not as a fixed string. Pinning the exact wording
    # would go red on a rewrite that is still true; what must never come back is
    # a header that names ONE of the three findings as though it were the whole
    # of them. The two other supervisor registrations are deliberately NOT
    # asked: PostToolUseFailure raises exactly one thing and says so, and
    # SubagentStop raises the orphan reconciliation alone.
    $stopSup = @(@($hooks.hooks.Stop) | Where-Object { ($_ | ConvertTo-Json -Depth 8 -Compress) -like '*supervisor.ps1*' })[0]
    $stopMsg = [string]$stopSup.hooks[0].rewakeMessage
    $stopSum = [string]$stopSup.hooks[0].rewakeSummary
    Add-Result 'C0 registration: the Stop rewake header claims none of its three findings as the only one' `
        (-not [string]::IsNullOrWhiteSpace($stopMsg) -and -not [string]::IsNullOrWhiteSpace($stopSum) -and
         $stopMsg -notmatch '(?i)background task|subagent dispatch|orphan' -and
         $stopSum -notmatch '(?i)background task|subagent dispatch|orphan') `
        ("the Stop branch alerts on a failed background task, an orphaned agent OR a transition-ladder tier, and this header is the first sentence in front of whichever one fired. got rewakeMessage [$stopMsg], rewakeSummary [$stopSum]")

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
        Write-LwgFixtureConfig -Dir $c.root -Modules $Modules
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
    $c2 = New-LwgSupervisorCase -Name 'c2' -Modules @{ effort_ledger = $true; log_rotation = $false }
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
        $c1 = New-LwgSupervisorCase -Name ('c1-' + $shape.n) -Modules @{ effort_ledger = $true; log_rotation = $false }
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
    $c4 = New-LwgSupervisorCase -Name 'c4' -Modules @{ effort_ledger = $true; log_rotation = $false }
    $rc4 = Invoke-LwgSupervisor -Case $c4 -Event 'Stop' -Tag 'c4-run1' `
                -Payload (New-LwgStopPayload -Case $c4 -FailedIds @('task-one') -StopHookActive)
    Add-Result 'C4: stop_hook_active suppresses the alert' `
        ($rc4.code -eq 0 -and [string]::IsNullOrWhiteSpace($rc4.err)) `
        "with a hook already holding this turn end open, alerting again would loop. got exit $($rc4.code), stderr [$($rc4.err)]"
    Add-Result 'C4: the record is still written under the loop guard' `
        ([IO.File]::Exists($c4.health)) `
        'the loop guard suppresses the ALERT, not the log - a turn that is not recorded is a turn nothing can be reconstructed from'

    # =====================================================================
    # C11-C15: THE TRANSITION LADDER (#168 slice 1)
    # =====================================================================
    # WHAT IT IS. Three occupancies - the 5-hour limit, the 7-day limit and the
    # context window - read from signals/ratelimit.json, which the STATUS LINE
    # writes on every render (statusline/statusline.ps1's WriteSignal, #163).
    # The worst of the three sets a tier: amber from 70, red from 85. Amber tells
    # the model to start nothing new; red tells it to land the work and run the
    # handoff skill. It rides in the supervisor's Stop branch because exit 2
    # under this registration's asyncRewake is THE ONLY CHANNEL THAT REACHES
    # THE MODEL mid-turn - lib/stop_advisories.ps1's systemMessage reaches the
    # operator's screen and not the model, which is why context_pressure, the
    # advisory this ladder replaces, could never do what this issue asks.
    #
    # NO BLACK TIER IN THIS SLICE, deliberately, and it is not caution. The
    # black tier refuses a turn end until a handoff package exists, and that
    # package's first required field is the state of every effort in flight -
    # which is structurally empty until a dispatch record exists. A gate that
    # blocks on a field nothing can fill is the exact defect this repository
    # keeps closing.
    #
    # THE STALE CASE IS HERE RATHER THAN DEFERRED, and C12b is the one that
    # matters: a monitor that fails silent converts "I don't know" into "I'm
    # fine". A ratelimit.json older than the budget reports UNAVAILABLE and
    # must not reuse the tier the previous turn computed.
    function Write-LwgSignalFile {
        <#
          A signals/ratelimit.json under a case's data dir. Built as TEXT, not
          through ConvertTo-Json, so a case can hand the reader exactly what it
          means to - "the key is absent", "the key is present and 0" and "the
          key is named in unparsed" are three different inputs and the first two
          are the pair a silent-failure bug lives between.
        #>
        param(
            $Case,
            [string]$WrittenUtc,
            [int]$Schema = 1,
            $FiveHourPct = $null,
            [string]$FiveHourResetsAt = '',
            $SevenDayPct = $null,
            $ContextPct  = $null,
            [string[]]$Unparsed = @()
        )
        $parts = @(('"schema":' + $Schema), ('"written_utc":"' + $WrittenUtc + '"'))
        if ($null -ne $FiveHourPct) {
            $b = '"used_percentage":' + $FiveHourPct
            if (-not [string]::IsNullOrWhiteSpace($FiveHourResetsAt)) { $b += ',"resets_at":"' + $FiveHourResetsAt + '"' }
            $parts += ('"five_hour":{' + $b + '}')
        }
        if ($null -ne $SevenDayPct) { $parts += ('"seven_day":{"used_percentage":' + $SevenDayPct + '}') }
        if ($null -ne $ContextPct)  { $parts += ('"context_window":{"used_percentage":' + $ContextPct + '}') }
        if ($Unparsed.Count -gt 0)  { $parts += ('"unparsed":[' + (($Unparsed | ForEach-Object { '"' + $_ + '"' }) -join ',') + ']') }
        $dir = Join-Path $Case.data 'signals'
        [void][IO.Directory]::CreateDirectory($dir)
        [IO.File]::WriteAllText((Join-Path $dir 'ratelimit.json'), ('{' + ($parts -join ',') + '}'),
                                [Text.UTF8Encoding]::new($false))
    }
    function Get-LwgUtcStamp {
        param([int]$MinutesAgo = 0)
        return ([datetime]::UtcNow.AddMinutes(-1 * $MinutesAgo)).ToString(
            "yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
    }
    function Get-LwgLadderField {
        <#
          The ladder fields off the LAST health.jsonl record, gathered back into
          one object. Read back rather than inferred from the exit code, because
          "the ladder decided nothing fires" and "the ladder never ran" are the
          same exit code and are not the same state - which is the whole of C12b.

          THEY ARE FLAT IN THE RECORD, and this reader is the only place that
          re-nests them: ConvertTo-SafeField stringifies any non-scalar field, so
          a nested object would reach the log as JSON inside JSON and the status
          line, which parses this file on every render, would have to
          double-decode it.
        #>
        param($Case)
        $last = $null
        try {
            foreach ($ln in [IO.File]::ReadAllLines($Case.health)) {
                if ([string]::IsNullOrWhiteSpace($ln)) { continue }
                try { $o = $ln | ConvertFrom-Json } catch { continue }
                if ($null -eq $o.ladder) { continue }
                $u = @()
                if (-not [string]::IsNullOrWhiteSpace([string]$o.ladder_unavailable)) {
                    $u = @(([string]$o.ladder_unavailable) -split ',')
                }
                $last = [pscustomobject]@{
                    level       = [string]$o.ladder
                    reason      = [string]$o.ladder_reason
                    signal      = [string]$o.ladder_signal
                    pct         = $o.ladder_pct
                    age_minutes = $o.ladder_age_minutes
                    unavailable = $u
                }
            }
        } catch { }
        return $last
    }

    # --- C11: the three tiers, over a file the status line could have written
    $c11 = New-LwgSupervisorCase -Name 'c11' -Modules @{ effort_ledger = $true; log_rotation = $false }
    Write-LwgSignalFile -Case $c11 -WrittenUtc (Get-LwgUtcStamp -MinutesAgo 1) -FiveHourPct 12 -SevenDayPct 40 -ContextPct 55
    $rc11a = Invoke-LwgSupervisor -Case $c11 -Event 'Stop' -Tag 'c11-ok' -Payload (New-LwgStopPayload -Case $c11 -FailedIds @())
    $l11a  = Get-LwgLadderField -Case $c11
    Add-Result 'C11: every signal under 70 ends the turn silently and records level ok' `
        ($rc11a.code -eq 0 -and [string]::IsNullOrWhiteSpace($rc11a.err) -and $null -ne $l11a -and [string]$l11a.level -eq 'ok') `
        ("a ladder that alerts below its own amber threshold is noise that trains the reader to ignore the channel. got exit $($rc11a.code), stderr [$($rc11a.err)], ladder [" + ($l11a | ConvertTo-Json -Compress) + ']')

    $c11b = New-LwgSupervisorCase -Name 'c11b' -Modules @{ effort_ledger = $true; log_rotation = $false }
    Write-LwgSignalFile -Case $c11b -WrittenUtc (Get-LwgUtcStamp -MinutesAgo 1) -FiveHourPct 12 -SevenDayPct 40 -ContextPct 72
    $rc11b = Invoke-LwgSupervisor -Case $c11b -Event 'Stop' -Tag 'c11b-amber' -Payload (New-LwgStopPayload -Case $c11b -FailedIds @())
    $l11b  = Get-LwgLadderField -Case $c11b
    Add-Result 'C11b: 72% context is AMBER - exit 2, and the text says start nothing new' `
        ($rc11b.code -eq 2 -and $rc11b.err -like '*AMBER*' -and $rc11b.err -like '*context*' -and
         $rc11b.err -like '*72*' -and $rc11b.err -match '(?i)start no new work' -and
         $null -ne $l11b -and [string]$l11b.level -eq 'amber') `
        ("exit 2 under this registration's asyncRewake is what reaches the MODEL; a systemMessage reaches the operator's screen instead. got exit $($rc11b.code), stderr [$($rc11b.err)], ladder [" + ($l11b | ConvertTo-Json -Compress) + ']')

    $c11c = New-LwgSupervisorCase -Name 'c11c' -Modules @{ effort_ledger = $true; log_rotation = $false }
    Write-LwgSignalFile -Case $c11c -WrittenUtc (Get-LwgUtcStamp -MinutesAgo 1) -FiveHourPct 90 `
        -FiveHourResetsAt '2026-09-06T20:00:00Z' -SevenDayPct 40 -ContextPct 55
    $rc11c = Invoke-LwgSupervisor -Case $c11c -Event 'Stop' -Tag 'c11c-red' -Payload (New-LwgStopPayload -Case $c11c -FailedIds @())
    $l11c  = Get-LwgLadderField -Case $c11c
    Add-Result 'C11c: 90% on the 5-hour limit is RED - the text names the skill and the reset time' `
        ($rc11c.code -eq 2 -and $rc11c.err -like '*RED*' -and $rc11c.err -like '*5-hour*' -and
         $rc11c.err -like '*/lw-watchtower:lw-handoff*' -and $rc11c.err -like '*2026-09-06T20:00:00Z*' -and
         $null -ne $l11c -and [string]$l11c.level -eq 'red') `
        ("red is the tier that tells the model to land the work, so it has to name what to run and when the lockout lifts. resets_at is passed through VERBATIM - the file holds UTC and converting it here would bake this machine's offset into a value another process reads. got exit $($rc11c.code), stderr [$($rc11c.err)], ladder [" + ($l11c | ConvertTo-Json -Compress) + ']')

    Add-Result 'C11c: the worst of the three signals sets the tier, not the first one read' `
        ($null -ne $l11c -and [string]$l11c.signal -eq 'five_hour') `
        ("five_hour was 90 while context was 55 and seven_day 40. A ladder reading them in file order and stopping at the first would report context. got signal [$(if ($null -ne $l11c) { [string]$l11c.signal } else { '<no ladder field>' })]")

    # --- C12: unavailable, and the four shapes of it ----------------------
    $c12 = New-LwgSupervisorCase -Name 'c12' -Modules @{ effort_ledger = $true; log_rotation = $false }
    $rc12 = Invoke-LwgSupervisor -Case $c12 -Event 'Stop' -Tag 'c12-absent' -Payload (New-LwgStopPayload -Case $c12 -FailedIds @())
    $l12  = Get-LwgLadderField -Case $c12
    Add-Result 'C12: no signal file at all is UNAVAILABLE, exit 0, and says why' `
        ($rc12.code -eq 0 -and $null -ne $l12 -and [string]$l12.level -eq 'unavailable' -and [string]$l12.reason -eq 'absent') `
        ("before the status line has ever rendered there is no file, and that is not an emergency and not a clean bill of health either. got exit $($rc12.code), ladder [" + ($l12 | ConvertTo-Json -Compress) + ']')

    $c12b = New-LwgSupervisorCase -Name 'c12b' -Modules @{ effort_ledger = $true; log_rotation = $false }
    Write-LwgSignalFile -Case $c12b -WrittenUtc (Get-LwgUtcStamp -MinutesAgo 1) -FiveHourPct 90 -SevenDayPct 40 -ContextPct 55
    $rc12b1 = Invoke-LwgSupervisor -Case $c12b -Event 'Stop' -Tag 'c12b-red' -Payload (New-LwgStopPayload -Case $c12b -FailedIds @())
    # The same file, now older than any sane budget. Nothing else changes.
    Write-LwgSignalFile -Case $c12b -WrittenUtc (Get-LwgUtcStamp -MinutesAgo 600) -FiveHourPct 90 -SevenDayPct 40 -ContextPct 55
    $rc12b2 = Invoke-LwgSupervisor -Case $c12b -Event 'Stop' -Tag 'c12b-stale' -Payload (New-LwgStopPayload -Case $c12b -FailedIds @())
    $l12b   = Get-LwgLadderField -Case $c12b
    Add-Result 'C12b: a STALE file reports unavailable and does NOT reuse the last tier' `
        ($rc12b1.code -eq 2 -and $rc12b2.code -eq 0 -and
         $null -ne $l12b -and [string]$l12b.level -eq 'unavailable' -and [string]$l12b.reason -eq 'stale') `
        ("THE CASE THIS SLICE EXISTS NOT TO DEFER. A monitor that fails silent converts 'I do not know' into 'I am fine', and a session believed it was at 54% for four hours on exactly that. Turn 1 was red on a fresh file (exit $($rc12b1.code)); turn 2 read the same numbers 600 minutes old and must report unavailable rather than red and rather than ok. got exit $($rc12b2.code), ladder [" + ($l12b | ConvertTo-Json -Compress) + ']')

    $c12c = New-LwgSupervisorCase -Name 'c12c' -Modules @{ effort_ledger = $true; log_rotation = $false }
    Write-LwgSignalFile -Case $c12c -WrittenUtc (Get-LwgUtcStamp -MinutesAgo 1) -Schema 99 -FiveHourPct 90
    $rc12c = Invoke-LwgSupervisor -Case $c12c -Event 'Stop' -Tag 'c12c-schema' -Payload (New-LwgStopPayload -Case $c12c -FailedIds @())
    $l12c  = Get-LwgLadderField -Case $c12c
    Add-Result 'C12c: an unknown schema is refused rather than read hopefully' `
        ($rc12c.code -eq 0 -and $null -ne $l12c -and [string]$l12c.level -eq 'unavailable' -and [string]$l12c.reason -eq 'schema') `
        ("schema 1 is the shape statusline.ps1 writes today. A reader that guesses at schema 99 is reading fields it has no contract for. got exit $($rc12c.code), ladder [" + ($l12c | ConvertTo-Json -Compress) + ']')

    $c12d = New-LwgSupervisorCase -Name 'c12d' -Modules @{ effort_ledger = $true; log_rotation = $false }
    Write-LwgSignalFile -Case $c12d -WrittenUtc (Get-LwgUtcStamp -MinutesAgo 1) -SevenDayPct 40 -Unparsed @('five_hour.used_percentage', 'context_window.used_percentage')
    $rc12d = Invoke-LwgSupervisor -Case $c12d -Event 'Stop' -Tag 'c12d-unparsed' -Payload (New-LwgStopPayload -Case $c12d -FailedIds @())
    $l12d  = Get-LwgLadderField -Case $c12d
    Add-Result 'C12d: a signal the writer could not parse is absent, never 0' `
        ($rc12d.code -eq 0 -and $null -ne $l12d -and [string]$l12d.level -eq 'ok' -and
         (@($l12d.unavailable) -contains 'five_hour') -and (@($l12d.unavailable) -contains 'context_window')) `
        ("statusline.ps1 names a value it could not read in the unparsed list and OMITS the block. Reading the missing block as 0% would report the calmest possible answer about the thing it knows least. got exit $($rc12d.code), ladder [" + ($l12d | ConvertTo-Json -Compress) + ']')

    # --- C13: the ladder alerts on a RISE, not at every turn end ----------
    $c13 = New-LwgSupervisorCase -Name 'c13' -Modules @{ effort_ledger = $true; log_rotation = $false }
    Write-LwgSignalFile -Case $c13 -WrittenUtc (Get-LwgUtcStamp -MinutesAgo 1) -ContextPct 72
    $rc13a = Invoke-LwgSupervisor -Case $c13 -Event 'Stop' -Tag 'c13-amber1' -Payload (New-LwgStopPayload -Case $c13 -FailedIds @())
    Write-LwgSignalFile -Case $c13 -WrittenUtc (Get-LwgUtcStamp -MinutesAgo 1) -ContextPct 74
    $rc13b = Invoke-LwgSupervisor -Case $c13 -Event 'Stop' -Tag 'c13-amber2' -Payload (New-LwgStopPayload -Case $c13 -FailedIds @())
    Write-LwgSignalFile -Case $c13 -WrittenUtc (Get-LwgUtcStamp -MinutesAgo 1) -ContextPct 88
    $rc13c = Invoke-LwgSupervisor -Case $c13 -Event 'Stop' -Tag 'c13-red' -Payload (New-LwgStopPayload -Case $c13 -FailedIds @())
    Add-Result 'C13: amber fires once, and a rise to red fires again' `
        ($rc13a.code -eq 2 -and $rc13b.code -eq 0 -and $rc13c.code -eq 2 -and $rc13c.err -like '*RED*') `
        ("a ladder repeating amber at every turn end is a channel the reader learns to skip, and one that stays quiet through a rise to red has failed at its only job. got exits $($rc13a.code)/$($rc13b.code)/$($rc13c.code), third stderr [$($rc13c.err)]")

    # --- C14: the ladder is not the failure alert -------------------------
    $c14 = New-LwgSupervisorCase -Name 'c14' -Modules @{ effort_ledger = $true; log_rotation = $false }
    Write-LwgSignalFile -Case $c14 -WrittenUtc (Get-LwgUtcStamp -MinutesAgo 1) -ContextPct 90
    $rc14 = Invoke-LwgSupervisor -Case $c14 -Event 'Stop' -Tag 'c14-both' `
                -Payload (New-LwgStopPayload -Case $c14 -FailedIds @('task-one'))
    Add-Result 'C14: a failed task and a red tier both reach the model in one exit 2' `
        ($rc14.code -eq 2 -and $rc14.err -like '*failed state*' -and $rc14.err -like '*RED*') `
        ("one process, one exit code, two findings - dropping either because the other fired is how a supervisor loses the thing it was watching for. got exit $($rc14.code), stderr [$($rc14.err)]")

    # --- C6: PostToolUseFailure ------------------------------------------
    function New-LwgToolFailurePayload {
        param($Case, [bool]$Interrupt)
        return '{"session_id":"' + $Case.session + '","cwd":"' + ($Case.ws -replace '\\', '/') + '",' +
               '"hook_event_name":"PostToolUseFailure","tool_name":"Agent","tool_use_id":"lwg-fixture-tu-1",' +
               '"error":"fixture dispatch error","is_interrupt":' + $(if ($Interrupt) { 'true' } else { 'false' }) + ',' +
               '"tool_input":{"subagent_type":"lwg-fixture-worker","description":"fixture dispatch"}}'
    }

    $c6 = New-LwgSupervisorCase -Name 'c6' -Modules @{ effort_ledger = $true; log_rotation = $false }
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

    # --- C6c, C6d: the alert has to NAME something - #271 -----------------
    # This hook carries asyncRewake (hooks/hooks.json), so every line it writes
    # to stderr is spent WAKING THE MODEL. On a payload it could not read it
    # produced, verbatim:
    #
    #     Subagent dispatch failed:
    #     Error:
    #     Assess whether this needs a retry (one model tier up), ...
    #
    # Both data fields empty, and a three-way instruction the model cannot act
    # on because nothing names the agent, the tool or the error. Measured
    # identical across all twelve garbage stdin shapes and both switch states.
    #
    # THE EXIT 2 IS NOT THE DEFECT AND IS NOT CHANGED. Claude Code dispatches
    # this event only when a tool call actually failed, so the event's own
    # occurrence is evidence and a wake is earned; docs/architecture.md records
    # the exit as a deliberate asyncRewake alert rather than a refusal. What was
    # wrong is a wake that names nothing while sounding like it does.
    #
    # TWO CASES BECAUSE THERE ARE TWO BRANCHES. C6c is the whole payload gone;
    # C6d is a payload that reads fine and simply carries no error text, which
    # is the commoner shape and the one a fix that only handled "empty stdin"
    # would miss. C6b above is the control for both: a fully populated payload
    # must still name the real values and must NOT acquire a placeholder.
    #
    # ASSERTED ON THE SHAPE, NOT ON THE WORDING. A line ending in a colon, and a
    # bare `Error:`, are the defect; the sentences that replace them are prose
    # and will be reworded, so matching them exactly would make this fail for a
    # change of words rather than a change of behaviour - the rule C6 states one
    # case above.
    #
    # RED-FIRST: both FAIL at 6aebcd6.
    $rc6c = Invoke-LwgSupervisor -Case $c6 -Event 'PostToolUseFailure' -Tag 'c6-emptystdin' -Payload ''
    $c6cLines = @(($rc6c.err -split "`r?`n") | Where-Object { $_.Trim() -ne '' })
    $c6cDangling = @($c6cLines | Where-Object { $_ -match ':\s*$' })
    Add-Result 'C6c: an unreadable payload still alerts, and the alert names the condition (#271)' `
        ($rc6c.code -eq 2 -and $c6cDangling.Count -eq 0 -and $c6cLines.Count -gt 0) `
        ("this hook is asyncRewake, so these lines are spent waking the model. Expected exit 2 with no line ending in a colon and nothing after it; got exit $($rc6c.code) and " +
         "$($c6cDangling.Count) dangling line(s). stderr: [" + ($rc6c.err.Trim() -replace "`r?`n", ' | ') + ']')

    $c6dPayload = '{"session_id":"' + $c6.session + '","cwd":"' + ($c6.ws -replace '\\', '/') + '",' +
                  '"hook_event_name":"PostToolUseFailure","tool_name":"Agent","tool_use_id":"lwg-fixture-tu-6d",' +
                  '"is_interrupt":false,"tool_input":{"subagent_type":"lwg-fixture-worker","description":"fixture dispatch"}}'
    $rc6d = Invoke-LwgSupervisor -Case $c6 -Event 'PostToolUseFailure' -Tag 'c6-noerrtext' -Payload $c6dPayload
    $c6dLines = @(($rc6d.err -split "`r?`n") | Where-Object { $_.Trim() -ne '' })
    $c6dDangling = @($c6dLines | Where-Object { $_ -match ':\s*$' })
    Add-Result 'C6d: a readable payload carrying no error text names the agent and says the text is missing (#271)' `
        ($rc6d.code -eq 2 -and $c6dDangling.Count -eq 0 -and $rc6d.err -like '*lwg-fixture-worker*') `
        ("the dispatch is named and the error is not, which is the commoner shape: the first line must still carry the worker and the second must say the text was absent rather than end in a colon. " +
         "got exit $($rc6d.code), $($c6dDangling.Count) dangling line(s). stderr: [" + ($rc6d.err.Trim() -replace "`r?`n", ' | ') + ']')

    Add-Result 'C6: CONTROL a fully populated payload names the real values and acquires no placeholder' `
        ($rc6b.err -notlike '*carried no*' -and $rc6b.err -like '*lwg-fixture-worker*') `
        ("C6c and C6d must not be satisfiable by always printing the placeholder. The populated run's stderr was: [" + ($rc6b.err.Trim() -replace "`r?`n", ' | ') + ']')

    # --- C7: effort_ledger off -----------------------------------------
    $c7 = New-LwgSupervisorCase -Name 'c7' -Modules @{ effort_ledger = $false; log_rotation = $true }
    $rc7 = Invoke-LwgSupervisor -Case $c7 -Event 'Stop' -Tag 'c7-run1' `
                -Payload (New-LwgStopPayload -Case $c7 -FailedIds @('task-one'))
    Add-Result 'C7: with effort_ledger off nothing is written and nothing is alerted' `
        ($rc7.code -eq 0 -and [string]::IsNullOrWhiteSpace($rc7.err) -and
         -not [IO.File]::Exists($c7.health) -and -not [IO.File]::Exists($c7.alerted)) `
        "the flag off means zero side effects: no record, no alerted list, exit 0. got exit $($rc7.code), health exists $([IO.File]::Exists($c7.health))"

    # --- C5: log_rotation is independent of effort_ledger --------------
    # The rotation call sits ABOVE the effort_ledger gate, and that position is
    # the whole point: it used to live inside Write-Record, downstream of the
    # gate, so switching failure capture off left health.jsonl uncapped and
    # growing without bound while log_rotation still reported itself active. A
    # module that is enabled, implemented and unreachable is the exact defect
    # this plugin exists to catch.
    #
    # Both halves of this case run with effort_ledger OFF, which is what makes
    # them a test of independence rather than of rotation: nothing appends, so
    # the live file's line count after a rotation is exactly KeepLines.
    function New-LwgOversizedLog {
        param([string]$Path, [int]$Lines = 56000)
        $one = '{"ts":"2026-01-01T00:00:00.0000000Z","event":"Stop","session":"lwg-fixture","cwd":"nowhere","failed_tasks":0}'
        $sb = New-Object System.Text.StringBuilder
        for ($i = 0; $i -lt $Lines; $i++) { [void]$sb.Append($one).Append("`n") }
        [IO.File]::WriteAllText($Path, $sb.ToString(), [Text.UTF8Encoding]::new($false))
    }

    $c5 = New-LwgSupervisorCase -Name 'c5-on' -Modules @{ effort_ledger = $false; log_rotation = $true }
    New-LwgOversizedLog -Path $c5.health
    $c5before = (Get-Item $c5.health).Length
    $rc5 = Invoke-LwgSupervisor -Case $c5 -Event 'Stop' -Tag 'c5-run1' `
                -Payload (New-LwgStopPayload -Case $c5 -FailedIds @())
    $c5after  = (Get-Item $c5.health).Length
    $c5lines  = @([IO.File]::ReadAllLines($c5.health)).Count
    Add-Result 'C5: log_rotation runs with effort_ledger OFF' `
        ($rc5.code -eq 0 -and [IO.File]::Exists($c5.health + '.1') -and $c5after -lt $c5before) `
        ("the rotation call must sit above the module gate. If it does not, switching failure capture off leaves health.jsonl uncapped while log_rotation reports itself active. before $c5before bytes, after $c5after, archive exists $([IO.File]::Exists($c5.health + '.1'))")
    Add-Result 'C5: the rotated log carries the tail forward and gains no new record' `
        ($c5lines -eq 500) `
        ("the live file must come back holding exactly KeepLines records - the status line reads it with -Tail 300 and a plain truncate would blank the health indicator - and with effort_ledger off nothing may be appended on top. got $c5lines line(s)")

    $c5b = New-LwgSupervisorCase -Name 'c5-off' -Modules @{ effort_ledger = $false; log_rotation = $false }
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
    $c8 = New-LwgSupervisorCase -Name 'c8' -Modules @{ effort_ledger = $true; log_rotation = $false }
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
    $c9 = New-LwgSupervisorCase -Name 'c9' -Modules @{ effort_ledger = $true; log_rotation = $false }
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
    # build that reports effort_ledger active.
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

    # THE ONLY VERDICT IN THIS FILE THAT IS A DURATION, AND IT DOES NOT RUN
    # UNDER tests\doc_claims.ps1's SIBLING PHASE - #250. That phase starts all
    # fourteen sibling suites at once, most of them spawning a child process per
    # case, and sets LWG_SUITE_PARALLEL in the children. Section D's header
    # reasons about MACHINE SPEED - a slow laptop against a fast one - and about
    # nothing else; none of it is about thirteen other suites running beside this
    # one. Two aborts of the whole documentation guard named THIS suite
    # (`ABORT: tests\stop_behaviour.ps1 exited 1`, green 117 of 117 standalone
    # minutes later, both recorded on #250), and the abort is total - "nothing
    # about the documentation was established by this run" - so one timing case
    # losing a race costs the pages their only guard.
    #
    # SKIPPED, NOT WIDENED AND NOT RETRIED. The 5000 ms difference does not
    # move, the sample count does not move, and nothing runs twice. The case is
    # still COUNTED in this suite's tally and still prints a line saying what
    # happened, so a run that skipped it cannot be mistaken for a run that
    # passed it - and it is still ENFORCED everywhere else, which is its own CI
    # step and every local run of this file. What is removed is the one context
    # in which its input is known to measure the runner.
    #
    # ONLY THE DURATION VERDICT IS SKIPPED, NOT THE MEASUREMENT AND NOT THE CASE
    # BELOW IT. $m4a and $m4b feed the render-content case as well, and that one
    # asserts on the '!' marker rather than on a clock, so it must keep running
    # here. That is a departure from the hunk written out on #250, which wrapped
    # the measurement itself; wrapping it would have starved the second case of
    # its inputs. Six child renders therefore still run under the flag - if an
    # abort ever names this suite again, the render-content case and the fixture
    # timeouts in B26 are what is left to look at.
    #
    # THE VARIABLE IS READ HERE, not declared in doc_claims: that file knows it
    # launched siblings and nothing more. A list of "which cases are timing
    # cases" held over there is a list that goes stale here. The other duration
    # verdict in the fifteen suites is tests\gate_delegate.ps1's J10, which
    # reads the same flag for the same reason.
    $d4Parallel = -not [string]::IsNullOrWhiteSpace($env:LWG_SUITE_PARALLEL)
    if ($d4Parallel) {
        Write-Output '  D4 timing  SKIPPED under the parallel runner - a difference between two medians taken beside thirteen other suites measures the runner, not the renderer (#250)'
        Add-Result 'D4: ten oversized records cost the render almost nothing' $true `
            ('SKIPPED: LWG_SUITE_PARALLEL is set, so this run is one of the fourteen sibling suites tests\doc_claims.ps1 starts at once. This is the only case in this file whose verdict is a wall-clock difference, and a difference between two medians taken while twelve other suites are spawning a process per case measures the runner. Nothing is widened and nothing is retried - run this suite on its own, which its own CI step and every local run do, and the case is enforced exactly as written. The render-content case below it is NOT skipped: it asserts on the ''!'' marker rather than on a clock, so both renders still happen. See the block above it and #250.')
    } else {
        Add-Result 'D4: ten oversized records cost the render almost nothing' `
            ($d4delta -lt 5000) `
            ("REGRESSION: the status line read this file with Get-Content -Tail 300, whose cost is superlinear in line length. Ten 200,000-character records took the render median from 1,280 ms to 105,988 ms on this machine - the indicator took a minute and a half to draw, several times a turn. clean median $($m4a.median) ms [$(@($m4a.times) -join ',')], poisoned median $($m4b.median) ms [$(@($m4b.times) -join ',')], delta $d4delta ms")
    }
    Add-Result 'D4: and it SAYS the log held something it could not read' `
        ($m4b.render -match 'HH[0-9]*!' -and $m4a.render -notmatch 'HH[0-9]*!') `
        ("a skipped record could have been a fault, and a fault dropped on the floor renders green - the one failure mode this indicator must never have. The trailing '!' is what keeps the skip visible. poisoned render: [" + (($m4b.render -replace "$([char]27)\[[0-9]+m", '').Trim()) + '], clean render: [' + (($m4a.render -replace "$([char]27)\[[0-9]+m", '').Trim()) + ']')

    # --- D5: the transition ladder's cost on the Stop path (#168) ---------
    # THE SAME METHOD AS D4 AND DELIBERATELY NOT A NEW ONE: two medians taken
    # back to back in the same run on the same machine, and a DIFFERENCE
    # asserted, never an absolute duration. An absolute threshold is a case that
    # fails on a slow laptop and passes on a fast one for reasons that have
    # nothing to do with the code.
    #
    # WHAT THE TWO ARMS ARE. Both run the real supervisor on the real Stop path
    # against the same fresh signals/ratelimit.json, so both pay the file read,
    # the JSON parse, the timestamp arithmetic and the tier comparison - the
    # whole of the ladder's own work. They differ in ONE thing: the FIRES arm
    # crosses the red threshold and therefore also reads and writes the ladder
    # state file and formats and writes four lines to stderr; the QUIET arm has
    # thresholds pushed to 101, so it computes the identical tier and finds
    # nothing to say.
    #
    # THAT PAIRING IS THE POINT. It is not "ladder on versus ladder off", which
    # would have measured the file read and told nobody anything about the
    # branch an operator actually pays for at a wall. It is the cost of ACTING
    # on the tier, over the cost of computing it, on a hook that runs at every
    # turn end.
    #
    # THE FLOOR IS REPORTED BESIDE THEM rather than subtracted from anything.
    # Both arms are a whole PowerShell 5.1 child process, most of which is
    # interpreter start-up; a reader who is not shown the floor cannot tell a
    # 30 ms difference from a 30 ms module.
    function Measure-LwgLadderStop {
        param([string]$Name, [hashtable]$Thresholds, [int]$Runs = 5)
        $c = New-LwgSupervisorCase -Name $Name -Modules @{ effort_ledger = $true; log_rotation = $false }
        if ($null -ne $Thresholds) {
            # The fixture config is rewritten with a thresholds block. Written
            # through ConvertTo-Json for the same reason Write-LwgFixtureConfig
            # is: a fixture malformed by a quoting mistake here is read as
            # "config unreadable", which Get-LwgConfig FAILS OPEN on, and the arm
            # would then measure the defaults rather than what it named.
            $cfgPath = Join-Path $c.root 'config.json'
            $cfg = [IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json
            $cfg | Add-Member -NotePropertyName 'thresholds' -NotePropertyValue ([pscustomobject]@{
                ladder = [pscustomobject]$Thresholds }) -Force
            [IO.File]::WriteAllText($cfgPath, ($cfg | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
        }
        Write-LwgSignalFile -Case $c -WrittenUtc (Get-LwgUtcStamp -MinutesAgo 1) `
            -FiveHourPct 93 -FiveHourResetsAt '2026-09-06T20:00:00Z' -SevenDayPct 44 -ContextPct 61
        $times = @()
        $codes = @()
        for ($i = 0; $i -lt $Runs; $i++) {
            # A fresh session id per run: the ladder alerts on a RISE, so the
            # second run of the FIRES arm would otherwise be deduped into
            # silence and the arm would stop measuring what it claims to.
            $pl = (New-LwgStopPayload -Case $c -FailedIds @()) -replace
                  ('"session_id":"' + [regex]::Escape($c.session) + '"'), ('"session_id":"' + $c.session + '-' + $i + '"')
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $r  = Invoke-LwgSupervisor -Case $c -Event 'Stop' -Tag ($Name + '-' + $i) -Payload $pl
            $sw.Stop()
            $times += [int]$sw.Elapsed.TotalMilliseconds
            $codes += $r.code
        }
        $sorted = @($times | Sort-Object)
        return @{ median = $sorted[[int][Math]::Floor($sorted.Count / 2)]; times = $times; codes = $codes }
    }

    # The interpreter floor, measured the same way: a child that starts
    # PowerShell and does nothing else.
    $d5floorTimes = @()
    for ($i = 0; $i -lt 5; $i++) {
        $d5sw = [Diagnostics.Stopwatch]::StartNew()
        & $env:ComSpec /c 'powershell -NoProfile -ExecutionPolicy Bypass -Command exit' | Out-Null
        $d5sw.Stop()
        $d5floorTimes += [int]$d5sw.Elapsed.TotalMilliseconds
    }
    $d5floorSorted = @($d5floorTimes | Sort-Object)
    $d5floor = $d5floorSorted[[int][Math]::Floor($d5floorSorted.Count / 2)]

    $m5quiet = Measure-LwgLadderStop -Name 'd5-quiet' -Thresholds @{ amber_pct = 101; red_pct = 101 }
    $m5fires = Measure-LwgLadderStop -Name 'd5-fires' -Thresholds $null
    $d5delta = $m5fires.median - $m5quiet.median

    $d5Parallel = -not [string]::IsNullOrWhiteSpace($env:LWG_SUITE_PARALLEL)
    $d5detail = ("floor (powershell -NoProfile -Command exit) median $d5floor ms [$(@($d5floorTimes) -join ',')]; " +
                 "ladder computed, nothing to say: median $($m5quiet.median) ms [$(@($m5quiet.times) -join ',')], exits [$(@($m5quiet.codes) -join ',')]; " +
                 "ladder RED and announcing: median $($m5fires.median) ms [$(@($m5fires.times) -join ',')], exits [$(@($m5fires.codes) -join ',')]; " +
                 "delta $d5delta ms")

    # THE ARMS ARE ASSERTED TO HAVE DONE DIFFERENT THINGS BEFORE THE CLOCK IS
    # READ. Two arms that both exited 0 would produce a delta near zero and a
    # green line that measured nothing, which is the vacuity this file refuses
    # everywhere else. This half does not depend on a clock, so it runs under
    # the parallel runner too.
    Add-Result 'D5: the budget arms really are quiet and firing' `
        ((@($m5quiet.codes | Where-Object { $_ -ne 0 }).Count -eq 0) -and
         (@($m5fires.codes | Where-Object { $_ -ne 2 }).Count -eq 0)) `
        ("the quiet arm must exit 0 on every run and the firing arm must exit 2 on every run, or the delta below is a difference between two things nobody named. $d5detail")

    if ($d5Parallel) {
        Write-Output '  D5 timing  SKIPPED under the parallel runner - a difference between two medians taken beside twelve other suites measures the runner, not the ladder (#250)'
        Add-Result 'D5: announcing a red tier costs the Stop path almost nothing' $true `
            ("SKIPPED: LWG_SUITE_PARALLEL is set, so this run is one of the thirteen sibling suites tests\doc_claims.ps1 starts at once, and a wall-clock difference taken while twelve of them spawn a process per case measures the runner. Nothing is widened and nothing is retried - run this suite on its own, which its own CI step and every local run do, and the case is enforced exactly as written. The arms-differ case above it is NOT skipped: it asserts on exit codes rather than on a clock. Same treatment as D4 and for the same reason. $d5detail")
    } else {
        # 2000 ms, the same shape of allowance as D4's 5000: enormous beside the
        # tens of milliseconds the branch actually costs, and tight enough to
        # catch a ladder that had started doing real work - a second file read
        # per turn, a transcript parse, a subprocess - on the one hook that runs
        # at every single turn end.
        Add-Result 'D5: announcing a red tier costs the Stop path almost nothing' `
            ($d5delta -lt 2000) `
            ("the ladder rides a hook that runs at EVERY turn end, so the branch an operator hits at a wall has to be cheap. Both arms compute the identical tier; only the firing arm reads and writes the ladder state file and writes to stderr. $d5detail")
    }

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
Write-Output '"these modules warn about the right things" - see the header, and'
Write-Output 'docs\gates-removed.md Lesson 3.'
Write-Output 'EXIT: 0'
exit 0
