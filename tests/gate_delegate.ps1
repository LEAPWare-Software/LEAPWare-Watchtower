#requires -version 5
<#
  LW-WATCHTOWER delegate_gate regression suite.

      powershell -NoProfile -ExecutionPolicy Bypass -File tests\gate_delegate.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File tests\gate_delegate.ps1 -Verbose

  This is the only test of a GATE in this repository, and one of the five tests
  of behaviour here - tests\setup_merge.ps1 covers the installer's merge,
  tests\stop_behaviour.ps1 the two hooks that run at turn end,
  tests\uninstall_footprint.ps1 the only thing here that deletes, and
  tests\evidence_states.ps1 the checklist's evidence engine. Everything else
  that runs - the JSON and PowerShell parse steps,
  tests\portability_scan.ps1, tests\workflow_guard.ps1, tests\doc_claims.ps1 -
  asks whether files are well formed or whether the pages state true numbers.
  This one asks whether the gate refuses what it says it refuses, which is the
  only question a gate has to answer.

  This paragraph said THREE and named only two siblings until 3 August 2026,
  omitting the uninstaller and evidence-state suites by name. It is not read by
  tests\doc_claims.ps1 and still is not: that guard's $proseFiles set is
  tracked .md/.json/.yml/.yaml, so no .ps1 header in this directory is read at
  all - including the ones that publish their own case counts. Widening it to
  cover tests\*.ps1 was deliberately NOT done on the strength of this one
  example; it is a measurement somebody has to make first, per that file's own
  note about adding a branch and checking the CHECKED count moves.

  WHAT IT IS NOT. docs\gates-removed.md, Lesson 3: the last gate's suite was
  67/67 green while five bypasses were open, and every hole in this repository's
  history was found by somebody trying to break the gate, then written up as a
  regression case afterwards. A green run here is a statement that the cases
  below still behave, not that the gate is sound. It is written down at the top
  rather than in a footnote because the number of passing cases is exactly the
  thing that reads as assurance and is not.

  ---------------------------------------------------------------------------
  HOW A CASE IS RUN
  ---------------------------------------------------------------------------
  Through a real pipe, in a real child process, because a PowerShell object pipe
  never reaches [Console]::In and a hook reads its payload from there. Each case
  writes a one-line .cmd that does

      type payload.json | powershell -File lib\gate_delegate.ps1 1>out 2>err

  and the suite reads the exit code, stdout and stderr back off disk. An
  in-process call of the script's functions would test different code from the
  one Claude Code invokes, which is the failure this arrangement exists to
  avoid.

  NOTHING REAL IS TOUCHED, AND SECTION L PUTS ONE ASSERTION BEHIND ONE CLAUSE OF
  THAT RATHER THAN LEAVING ALL OF IT AS A SENTENCE. Every case runs against a
  THROWAWAY plugin root under the temp directory holding a copy of config.json,
  with CLAUDE_PLUGIN_ROOT and CLAUDE_PLUGIN_DATA pointed at it, so no case reads
  or writes the operator's config, the live state directory or the event log.
  The gate script itself is the real one - it is the thing under test - and it
  is only ever read.

  READ WHAT SECTION L COVERS OF THAT, BECAUSE IT IS ONE CLAUSE OF THREE. It
  compares the SIZE of the operator's event log before and after the run, and
  nothing else: not that log's contents, not the rest of the live state
  directory, and not the config. Those two are still promised here on the
  strength of the sandbox and asserted by no case. The event log is the one that
  is checked because it is the one the leak below actually reached.

  THE SANDBOX IS THE WHOLE RUN, NOT ONLY THE CHILD PROCESSES, and that is a fix
  rather than the original design. The two environment windows in Invoke-Gate
  and Invoke-Toggle wrap a `cmd /c` spawn and put the variables back the moment
  it returns. That is correct for a child process and covers nothing this
  process does itself - and this process does plenty: lib\common.ps1 is
  dot-sourced into it, and section K then calls Test-LwgModule directly on seven
  fixture configs, five of which hold a non-boolean ON PURPOSE, because the
  ignore-and-log path is exactly what those cases exercise. Write-LwgInvalidFlag
  resolves the state directory AT CALL TIME, so with no window open it resolved
  the OPERATOR'S, and every run of this suite appended five ConfigInvalidFlag
  records to the live event log while the paragraph above said it did not.
  1,644 bytes per run, measured. The records themselves were correct behaviour;
  the destination was the defect.

  The sandbox is therefore installed once, at the top of the run, and taken down
  in the finally so an abort cannot leave it standing. The per-case windows are
  KEPT rather than folded into it: they are still the only thing that points a
  child at its own fixture root, and they now nest inside the outer sandbox
  instead of dropping back to the operator's environment between cases.

  The two configs both start as a byte copy of the repository's own
  config.json rather than a fixture written here. A hand-written fixture tests
  the shape somebody imagined; the shipped file tests the shape that ships,
  including its several thousand words of comments, one of which contains the
  text "delegate": true inside a JSON string and would fool a reader that went
  looking for the flag with a substring search.

  ---------------------------------------------------------------------------
  99 CASES, WHY NONE OF THEM MAY BE SKIPPED, AND WHAT SECTION I CANNOT SEE
  ---------------------------------------------------------------------------
  Sections A-H are 58 cases about the gate's rule. Section I is 12 more about
  the FAST PATH in lib/gate_delegate.ps1 - the scan that proves the switch off
  from the raw text of config.json and exits 0 before the JSON engine is ever
  loaded. Five of those twelve - I7 to I11, added 3 September 2026 - are about
  the OPERATOR OVERRIDE (#11): config.json became the shipped defaults, the
  configuring commands write config.override.json under the state directory,
  and a scan that read config.json alone would have proved the switch off over
  an override that arms it - a gate reporting ARMED everywhere and refusing
  nothing. Section J is 11 more about the member NAMES that scan matches on, and
  about what a non-boolean value in the switch means. Ten of the eleven pipe a
  payload into the gate and read what comes back; the eleventh, J7b, is the
  only case in this file that calls the fast scan DIRECTLY, because an
  abstention and a swallowed throw are byte-identical from outside the gate
  process and J7 beside it therefore cannot tell them apart.

  Section K is 8 more, and
  it is the only section here that runs something OTHER than the gate: it puts
  bin/lwg-toggle.ps1 - the command an operator reads the gate's state off - in
  front of the same configs and requires the same answer. That pair had already
  come apart once, in the direction where the command reported an armed gate
  the gate itself considered off.

  Section M is 3 more, and it is the only section here that asks a question
  about the CLI rather than about the gate: WOULD THE HOOK HAVE BEEN INVOKED?
  Every case in A-L but J7b pipes a payload straight into the gate script,
  which models a hook the CLI already decided to run - and the gate is
  tool-blind on purpose,
  so a tool the matcher never selects passes all of its cases by being handed a
  hook run that would not have happened. It is written after the section it
  covers because a suite that only tests the thing it can invoke is exactly how
  the matcher went on omitting PowerShell - on a Windows-only plugin, with the
  other shell tool one line away - while this header said 80 of 80.

  Section P is 2 more, and it is the only thing in this tree that reads a line
  of the informational roster bin\lwg-doctor.ps1 prints below its verdict. That
  roster is the third reader of the same switch - the gate, the toggle and the
  report - and until 3 August 2026 it was the one nothing checked. It used to
  be a command of its own, bin\lwg-status.ps1; the command is deleted and these
  two cases followed the output into the doctor rather than being deleted with
  it, because neither property is covered anywhere else in this file.

  Section N is 4 more, and it is the only section here that reads PROSE. Four
  claims other files make about this gate - that no PreToolUse hook is
  registered and nothing here can block, that a PreToolUse denial goes in
  stdout on exit 0, that the banner prints no built-but-off parenthetical, and
  that the gate does not read tool_name at all - were false on 3 August 2026
  across eight tracked surfaces, including the contributing guide's rule for
  writing a hook. Each case derives the fact from the tree first and only then
  asserts that no file contradicts it. Read the section's own header for the
  three things the sweep cannot see; it is a phrase list, not a proof.

  Section L is 1 more, and it is the only case in this file that asserts on THIS
  SUITE instead of on something the suite tests: that the operator's live event
  log is the same size after the run as it was before it. It is the case that
  would have caught the leak described above, and it is the only shape of case
  that could have. Every other case here reads an exit code, a stream, a file
  this suite created under the temp directory, or - J7b alone - the return
  value of a function lifted out of the gate and run in a runspace of its own,
  and a record appended to a file in
  the operator's profile moves none of those - so all 79 of them stayed green
  for as long as the leak ran. A promise that nothing real is touched is worth
  exactly what the assertion behind it is worth, and until section L there was
  none. It runs LAST, after sections M, P and N, whatever the letters say: it
  measures the whole run, so nothing may be appended behind its back.

  THE COUNT ABOVE IS NOW A CONSTANT THIS FILE CHECKS, not only a sentence.
  $script:ExpectedCases is declared once below and a completed run whose tally
  does not match it ABORTS with exit 2 instead of printing a number. 58 + 7 + 11
  + 8 + 3 + 2 + 4 + 1 is the arithmetic; if you add a case, that constant, this
  paragraph, the heading above and the tracked documents quoting the number all
  move in the same edit, which is the point of it.

  A CASE THAT CANNOT RUN IS AN ABORT OR A FAILURE, NEVER A QUIET SUBTRACTION,
  and this file learned that the hard way rather than on principle. Section H -
  the per-repo override, which is the two cases nearest the fail-open section J
  exists for - used to take its slug from THIS checkout's origin remote, and
  when none resolved it printed a note and ran nothing. The suite then said
  "RESULT: 60 of 60 case(s) passed": a green run, a true sentence, and a
  denominator two short of the one this header advertises. Nobody reading it
  learns that the override path was never exercised, and the two cases that
  went missing were the ones a live fail-open was hiding behind. Section H now
  FABRICATES the repository identity it needs - a directory carrying a
  .git/config that names an origin, which is the whole of what Get-LwgRepoInfo
  reads - so it runs on a worktree, a path clone, a CI checkout and a machine
  with no git at all. The fabrication is asserted, not assumed. The count above
  is fixed: every case passes, fails, or aborts the whole suite with exit 2,
  and there is no path left that makes the number smaller in silence.

  Here is the limit of what section I establishes, stated up front because it
  is exactly the kind of thing that reads as coverage and is not. A run that
  exits 0 in silence is a run that exits 0 in silence. The fast path's only
  affirmative outcome is byte-identical to the slow path's outcome for an off
  switch - that is the whole design - so from OUTSIDE the process there is no
  observable difference between "the fast path proved the switch off" and "the
  fast path fell through and the slow path decided the same thing". A fast path
  deleted entirely would leave every case in section I green.

  What section I therefore tests is the property that actually matters: that a
  config of each of these shapes still produces the RIGHT answer, whichever
  path produced it. The half it cannot test - that the fast path is the one
  answering - was established by the break-then-fix protocol at the time it was
  written and is recorded in that commit rather than here.

  ONE CONSEQUENCE OF THE DESIGN IS WORTH SPELLING OUT, because it decides which
  of these cases are sentinels and which are documentation. The fast path can
  only ever ALLOW. So no bug in it can turn an allow-expecting case red, and
  I1, I2, I3a and I4 are therefore incapable of failing on account of the
  scanner - a scanner deleted, inverted or fooled leaves all four green. Only
  the deny-expecting cases can catch it, and they catch exactly the one error
  that matters: proving the switch off while it is on. I3c and I6 are the two
  built for that, and case H in section H is the third.

  A change that makes the fast path silently stop RUNNING will not be caught by
  this file at all. It will show up as the cost going back to what
  docs/modules.md says it used to be.

  ---------------------------------------------------------------------------
  EXIT CODES - a CI job reads these and nothing else
  ---------------------------------------------------------------------------
      0  every case passed
      1  at least one case FAILED
      2  the suite ABORTED - it could not set up or could not run a case, so
         nothing was established either way. Zero cases run is an abort, never
         an empty-set pass.

  No network. No elevation. No real destructive command is ever constructed,
  even as a string: the payloads below name invented files and an invented
  command, per the standing order in docs\gates-removed.md that outlived the
  suite that taught it.
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
$script:RepoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Join-Path $script:RepoRoot 'lw-watchtower' }

$GatePath   = Join-Path $Root 'lib\gate_delegate.ps1'
$HooksPath  = Join-Path $Root 'hooks\hooks.json'
$CfgPath    = Join-Path $Root 'config.json'
$CommonPath = Join-Path $Root 'lib\common.ps1'
# The REPORTER. Section K runs it against the same fixtures the gate is run
# against, because the two answering differently is the defect this whole
# repository is an argument about.
$TogglePath = Join-Path $Root 'bin\lwg-toggle.ps1'
# bin\lwg-toggle.ps1 DOT-SOURCES this as of the #103 fix, for Read-LwgTextFile
# and Save-LwgTextFile. A scratch root without it makes every section-K case
# exit 3 on a missing file - which is what happened, and it is worth saying how
# it was missed: the fixture and the toggle live in different files, so no
# file-level ownership boundary couples them, and the suite's tally is "N of M"
# with M unchanged at the number this file declares - 93 on the day this
# happened - so `doc_claims` reads the M and every "93 of 93" in the tree stayed
# green while eight cases were failing. Add a file here whenever the toggle
# grows a dot-source.
$CmdlibPath = Join-Path $Root 'bin\lwg-cmdlib.ps1'
# The OTHER reporter, and it MOVED. Until this edit it was bin\lwg-status.ps1,
# a report command that did nothing else; that command is deleted and the one
# thing it printed which nothing else did - the per-module listing and a
# paragraph per gate - now prints at the foot of bin\lwg-doctor.ps1 as an
# INFORMATIONAL block, below RESULT: and below the verdict prose. Section P
# follows the output rather than the file name: it renders the gate's switch
# and the file behind it, and section P is still the only thing in this tree
# that reads what that surface actually prints.
#
# WHAT CHANGED IN THE CASES AND WHAT DID NOT. The two properties are identical -
# the stored value is not rendered as a config.json assignment, and a registry
# `impl` path that is not on disk is said to be missing. The EXIT ASSERTION had
# to change and the change is not cosmetic: the report command exited 0 because
# reporting was its whole job, while the doctor exits on its VERDICT, and
# against a fixture root holding four files most of its nine checks fail. So
# these cases assert the doctor COMPLETED - a `RESULT:` line, which the abort
# path at exit 3 never prints - and deliberately assert nothing about which
# code it chose. A case here that demanded exit 0 would be asserting the
# fixture is a healthy plugin install, which it is not and is not meant to be.
$DoctorPath = Join-Path $Root 'bin\lwg-doctor.ps1'

# The tools the gate is registered on. Written out ONCE here, and every
# assertion about the tool list is made against this - including the one that
# reads hooks.json. A test that took the list from hooks.json and then checked
# hooks.json against it would pass whatever hooks.json said.
#
# PowerShell IS ON THIS LIST AND WAS NOT, AND THAT WAS THE HOLE. This plugin
# supports Windows and nothing else - every hook in hooks/hooks.json invokes
# `powershell`, and lib/portability rules exist because 5.1 is the floor. On
# Windows the CLI offers BOTH shell tools: Bash and PowerShell.
#
# THAT IS NOT AN ASSUMPTION ABOUT THE CLI, IT IS THIS REPOSITORY'S OWN RECORD.
# docs/modules.md, under "Both gates were removed", describes the deleted
# destructive_gate as "a PreToolUse hook on Bash|PowerShell" - the gate this one
# replaced knew there were two shell tools and matched both. The list narrowed
# when the gate was rewritten and nothing carried the second name across.
#
# The matcher named Bash and not PowerShell, so with interaction.delegate ON the main thread
# could run any command it liked by picking the other shell, while
# the report command lw-watchtower:status (deleted; its roster now prints at the
# foot of bin\lwg-doctor.ps1) went on printing "1 gate(s) LIVE: delegate_gate - it can
# refuse a tool call right now". A gate reporting healthy while doing nothing is
# the defect this repository exists to prevent, and it was open on the only OS
# this plugin ships to.
#
# WHY THE LIST IS STILL AN ENUMERATION rather than "everything", now that it has
# been wrong once. Two reasons, and section M asserts the second:
#
#   COST. A hook registration cannot be made conditional, so this runs before
#   every matching call whether the switch is on or off - ~436 ms measured, for
#   every operator, by default. Bounded to the tools that can DO the work that
#   is being pushed onto subagents, that is a bill on a handful of calls per
#   turn. On a permissive matcher it is a bill on every Read, Grep, Glob and
#   TodoWrite in the main thread AND in every subagent, which is most calls in
#   a session. That is not a rounding error, it is the largest single cost this
#   plugin has, multiplied.
#
#   LOCKOUT. The gate refuses main-thread calls, and the way out it prints is
#   "dispatch a subagent with the Agent tool and have IT make this call". A
#   matcher that also selected Agent would refuse the dispatch, and there is no
#   other way out from inside the session - /lw-watchtower:delegate off runs through
#   Bash, which is refused on purpose. Widening a PreToolUse matcher widens what
#   can be refused, and past a certain point that stops being "the safe
#   direction" and becomes a session with no exit. Section M pins both edges.
#
# WHAT THIS LIST DOES NOT COVER, said here rather than discovered later: MCP
# tools. An `mcp__*` tool from a server the operator installed can write files
# and run commands, it reaches PreToolUse like any other tool, and its name is
# not knowable from this tree - it depends on that operator's servers. No
# enumeration can cover it and a matcher wide enough to try would buy the two
# costs above. It is a stated hole in docs/limitations.md, not a closed one.
$GatedTools = @('Edit', 'Write', 'NotebookEdit', 'Bash', 'PowerShell')

# Tools the matcher must NEVER select, and the reason each one is here. Section
# M asserts this against hooks.json under the LOOSEST reading of matcher
# semantics - see Test-LwgMatcherSelects - because the harm from being wrong in
# this direction is a main thread that cannot get out of the mode it is in.
#
# Both names are taken from this tree, not from memory: hooks/hooks.json
# registers PostToolUseFailure on matcher "Agent", the deny text in
# lib/gate_delegate.ps1 tells the operator to "Dispatch a subagent with the
# Agent tool", and agents/lw-orchestrator.md declares
# `tools: Agent, Skill, ToolSearch, ..., Read, Grep, Glob, ...` for the role the
# main conversation runs as when delegating.
$UngatedTools = @(
    @{ tool = 'Agent'; why = 'the dispatch. It is the one way out of an armed gate that works from inside the session - the deny text names it - so gating it is a lockout with no exit, not an over-block' }
    @{ tool = 'Read';  why = 'the main thread must still be able to read, or it cannot write the dispatch the deny text demands: a worker cannot see the conversation, so the context, the absolute paths and the definition of done have to be restated from something' }
)

$script:Pass    = 0
$script:Results = New-Object System.Collections.ArrayList
$script:Aborted = ''

# THE DENOMINATOR, DECLARED ONCE AND CHECKED AT THE FOOT OF THIS FILE.
#
# The header above says how many cases there are and eleven tracked documents
# repeat the number. Until this constant existed that was a sentence, not
# something the file checked: a case that stopped being reached subtracted
# itself from the tally and the run said so in a line nobody can tell apart
# from a stale header. Section A's registration cases did exactly that -
# measured at cc44c99, "79 case(s) had run" - which is the incident this
# constant is the durable half of.
#
# WHAT IT COVERS IS A COMPLETED RUN, and the boundary is the point. An abort
# exits 2 above this check with "N case(s) had run. The suite did NOT
# complete", which already says nothing was established; this is for the run
# that reaches a verdict with the wrong number of cases behind it. A case
# added on purpose has to move this number, the header, and the documents
# quoting it in the same edit, which is the coupling that keeps them true.
$script:ExpectedCases = 99

# The matcher string, as hooks.json actually spells it. Filled in by section A
# from the one entry that names the gate, and read by section M.
#
# $null MEANS SECTION M ABORTS THE SUITE rather than skipping, and that is this
# file's own rule - see "A CASE THAT CANNOT RUN" in the header, and the two
# per-repo cases that once vanished into a green run with a smaller
# denominator. There is no value of this variable that lets section M quietly
# not run: either section A read a matcher out of hooks.json or nothing here can
# say anything about what the CLI would select.
$script:GateMatcher = $null

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

function New-LwgFakeRoot {
    <#
      A throwaway plugin root holding a copy of the repository's config.json
      with interaction.delegate set to $On.

      The flip is a literal replace of the one member, and the count is
      ASSERTED. If the shipped file ever spells that member differently this
      throws rather than quietly producing a config with the flag untouched -
      which would make every "delegate is on" case below run against a gate that
      was off, and pass by agreeing with the wrong answer.
    #>
    param([string]$Base, [bool]$On)

    $dir = Join-Path $Base ("root-" + $(if ($On) { 'on' } else { 'off' }))
    [void][IO.Directory]::CreateDirectory($dir)
    [void][IO.Directory]::CreateDirectory((Join-Path $dir 'data'))

    $raw  = [IO.File]::ReadAllText($CfgPath)
    $from = '"delegate": false'
    $to   = if ($On) { '"delegate": true' } else { $from }

    $n = ([regex]::Matches($raw, [regex]::Escape($from))).Count
    if ($n -ne 1) {
        throw "config.json holds $n occurrence(s) of '$from', expected exactly 1 - the fixture cannot be built, and building it wrong would make every delegate-on case a false pass"
    }
    [IO.File]::WriteAllText((Join-Path $dir 'config.json'), $raw.Replace($from, $to), [Text.UTF8Encoding]::new($false))
    return $dir
}

function New-LwgRawRoot {
    <#
      A throwaway plugin root holding EXACTLY the config text it is given. Used
      by section I, where the point of the case is a config with a particular
      SHAPE - escaped quotes and braces inside a comment, a member that is
      absent, a value that is a string - which ConvertTo-Json cannot be asked
      for and New-LwgFakeRoot's one-member replace cannot produce.

      TWO ASSERTIONS, and both have already been the difference between a case
      and a case-shaped no-op:

        the text must PARSE. An unparseable fixture makes Get-LwgConfig fall
        back to the defaults, where delegate is off, so every "must DENY" case
        would allow and every "must ALLOW" case would pass by agreeing with the
        wrong answer.

        it must carry a `modules` block. Get-LwgConfig requires one and
        ALSO falls back to the defaults without it - same silent outcome, from a
        fixture that parses perfectly.
    #>
    param([string]$Base, [string]$Name, [string]$Json)

    $dir = Join-Path $Base $Name
    [void][IO.Directory]::CreateDirectory($dir)
    [void][IO.Directory]::CreateDirectory((Join-Path $dir 'data'))

    $probe = $null
    try { $probe = $Json | ConvertFrom-Json } catch {
        throw "fixture '$Name' is not valid JSON, so it would silently be read as the default config: $($_.Exception.Message)"
    }
    if ($null -eq $probe -or $null -eq $probe.modules) {
        # Single-quoted: a backtick in a double-quoted PowerShell string is the
        # escape character, so "no `modules` block" would lose both backticks
        # and, on the wrong letter, the letter with them.
        throw ('fixture ' + $Name + ' has no `modules` block, so Get-LwgConfig would discard it and return the defaults - the case would establish nothing')
    }

    [IO.File]::WriteAllText((Join-Path $dir 'config.json'), $Json, [Text.UTF8Encoding]::new($false))
    return $dir
}

function New-LwgFakeRepo {
    <#
      A directory that Get-LwgRepoInfo resolves to $Slug, built by hand and
      WITHOUT git: a .git directory holding a `config` with one
      [remote "origin"] url. That is the entire input Get-LwgRepoInfo takes -
      walk up for .git, follow `commondir` if there is one, parse the remote
      urls out of `config` - so a fabricated directory is the same evidence a
      cloned checkout gives it, minus the network, the git binary, and any
      dependence on how the checkout this suite happens to be run from is wired.

      WHY IT EXISTS: see "A CASE THAT CANNOT RUN" in this file's header. The
      per-repo cases used to be skipped when no origin resolved, which shrank
      the denominator without saying so.

      The resolution is ASSERTED. A fabrication Get-LwgRepoInfo does not read
      would leave the per-repo cases running against a null slug, where the
      override never applies and a "must DENY" case would fail for a reason
      that has nothing to do with the gate - or worse, an "ALLOW" case would
      pass by agreeing with the wrong answer.
    #>
    param([string]$Base, [string]$Name, [string]$Slug)

    $dir = Join-Path $Base $Name
    [void][IO.Directory]::CreateDirectory((Join-Path $dir '.git'))

    # Written the way git writes it, indented lines and all, because
    # Get-LwgRepoInfo trims each line before matching and a fixture that only
    # works unindented would stop testing the parser that reads real files.
    $cfg = @(
        '[core]'
        '    repositoryformatversion = 0'
        '    bare = false'
        '[remote "origin"]'
        ('    url = https://github.com/' + $Slug + '.git')
        '    fetch = +refs/heads/*:refs/remotes/origin/*'
    )
    [IO.File]::WriteAllLines((Join-Path $dir '.git\config'), $cfg, [Text.UTF8Encoding]::new($false))

    $got = (Get-LwgRepoInfo -Path $dir).slug
    if ($got -ne $Slug) {
        throw "the fabricated repo at $dir resolves to slug '$got', expected '$Slug' - the per-repo cases cannot be built, and building them wrong would make them pass by agreeing with the wrong answer"
    }
    return $dir
}

function Invoke-Gate {
    <#
      Run the gate once against $Payload with the plugin root pointed at $FakeRoot.
      Returns @{ code; out; err } - a hashtable, so PowerShell does not enumerate
      it away across the function boundary.

      $Payload is written as BYTES, not through Set-Content, so a case can hand
      the gate genuinely empty input or bytes that are not JSON at all. That is
      one of the cases.
    #>
    param([string]$FakeRoot, [string]$Payload, [string]$WorkDir, [string]$Tag)

    $pf  = Join-Path $WorkDir "$Tag.json"
    $of  = Join-Path $WorkDir "$Tag.out"
    $ef  = Join-Path $WorkDir "$Tag.err"
    $bat = Join-Path $WorkDir "$Tag.cmd"

    [IO.File]::WriteAllText($pf, $Payload, [Text.UTF8Encoding]::new($false))
    foreach ($f in @($of, $ef)) { if ([IO.File]::Exists($f)) { [IO.File]::WriteAllText($f, '') } }

    # A .cmd file rather than `cmd /c "<one long string>"`: cmd's rule about
    # stripping the first and last quote of a /c argument makes a quoted path in
    # such a string unreliable, and a test harness that breaks on a temp
    # directory with a space in it is a test harness that stops being run.
    $lines = @(
        '@echo off'
        ('type "{0}" | powershell -NoProfile -ExecutionPolicy Bypass -File "{1}" 1>"{2}" 2>"{3}"' -f $pf, $GatePath, $of, $ef)
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

function Test-LwgMatcherSelects {
    <#
      Would the CLI invoke a PreToolUse hook registered under $Matcher for a call
      to $Tool? This is a MODEL of a step that happens outside this repository,
      and everything about how it is written is decided by that.

      WHY IT HAS TO EXIST AT ALL. Every other case in this file pipes a payload
      straight into lib/gate_delegate.ps1, which is the right shape for testing
      the gate's RULE - and it is structurally blind to the defect that put this
      function here. The gate does not read tool_name to decide anything, so it
      denies a main-thread call whatever tool made it: pipe a PowerShell payload
      into it and it refuses, on a tree whose matcher never selects PowerShell
      and where that call would therefore have sailed through untouched. A case
      built that way is green on a hole. The selection step is the thing that
      was broken, so the selection step has to be in the case.

      WHAT IT DOES NOT KNOW, stated because a model that hides its assumptions
      is worse than no model. Claude Code's exact matcher semantics are not in
      this tree and this file cannot observe them: whether the string is
      anchored, and whether it is matched case-sensitively, are both unknown
      here. So this does not guess ONE reading - it offers the two extremes, and
      every case picks the one that makes its own assertion sound under either:

        default (STRICTEST):  ^(?:matcher)$ , case-sensitive. Selects the least.
        -Loose  (LOOSEST):    unanchored    , case-insensitive. Selects the most.

      A must-DENY case asks with the strictest reading. If the matcher selects
      the tool even under a reading that demands the whole name, exact case, it
      selects it under every looser one too - so a pass means the CLI really
      does invoke the gate, whichever rule it applies.

      A must-NOT-FIRE case asks with the loosest reading. If the matcher does
      not select Agent even under a reading where any substring, any case, hits,
      then no CLI can select it - so a pass means the dispatch really does get
      through.

      Both readings therefore fail in the direction that reports a problem, and
      neither can go green by assuming the semantics that happen to suit it.

      "*" and an empty matcher select everything, per the hook documentation
      this registration is written against. They are spelled out rather than
      left to the regex, because `*` on its own is not a valid pattern and
      [regex]::IsMatch would THROW on it - and a throw in here would abort the
      suite over a matcher that, in the CLI, gates every tool there is. That
      shape has to reach an ASSERTION (section M's must-not-fire cases catch it
      immediately), not an exception.
    #>
    param([string]$Matcher, [string]$Tool, [switch]$Loose)

    if ([string]::IsNullOrEmpty($Matcher)) { return $true }
    if ($Matcher.Trim() -eq '*')           { return $true }

    if ($Loose) {
        return [regex]::IsMatch($Tool, $Matcher,
            [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    return [regex]::IsMatch($Tool, ('^(?:' + $Matcher + ')$'),
        [Text.RegularExpressions.RegexOptions]::None)
}

function Invoke-GateAsCli {
    <#
      One tool call, END TO END: the CLI's matcher selection, and then the gate
      itself only if that selection happened. Returns Invoke-Gate's hashtable
      with one extra key - `invoked` - or, when the matcher does not select the
      tool, the outcome that state of affairs actually produces:

          @{ code = 0; out = ''; err = ''; invoked = $false }

      THAT IS NOT A FAKE PASS, it is what the operator gets. An unselected hook
      is never run, nothing is written to either stream, and the tool call
      proceeds - which is indistinguishable, from every other case in this file,
      from a gate that ran and allowed. Feeding it to Test-IsDeny therefore
      fails it for "exited 0", which is true but is not the reason; section M
      checks `invoked` FIRST and says the real one.

      $Matcher is read out of hooks.json by section A and handed here rather
      than re-read: one parse of that file, one statement of what it says.
    #>
    param([string]$FakeRoot, [string]$Payload, [string]$WorkDir, [string]$Tag,
          [string]$Tool, [string]$Matcher, [switch]$Loose)

    if (-not (Test-LwgMatcherSelects -Matcher $Matcher -Tool $Tool -Loose:$Loose)) {
        return @{ code = 0; out = ''; err = ''; invoked = $false }
    }
    $r = Invoke-Gate -FakeRoot $FakeRoot -Payload $Payload -WorkDir $WorkDir -Tag $Tag
    $r['invoked'] = $true
    return $r
}

function New-LwgToggleRoot {
    <#
      A throwaway plugin root that /lw-watchtower:delegate can actually be RUN from:
      New-LwgRawRoot's config.json, plus byte copies of the two scripts the
      command loads - bin\lwg-toggle.ps1 and the lib\common.ps1 it dot-sources.

      A copy rather than the real path, and that is forced rather than
      fastidious: the command resolves its plugin root as the PARENT of its own
      script directory and reads config.json from there. It does not consult
      CLAUDE_PLUGIN_ROOT for that, so the only way to point it at a fixture
      config is to stand it next to one. The scripts themselves are the shipped
      bytes - they are the thing under test.
    #>
    param([string]$Base, [string]$Name, [string]$Json)

    $dir = New-LwgRawRoot -Base $Base -Name $Name -Json $Json
    [void][IO.Directory]::CreateDirectory((Join-Path $dir 'bin'))
    [void][IO.Directory]::CreateDirectory((Join-Path $dir 'lib'))
    [IO.File]::Copy($TogglePath, (Join-Path $dir 'bin\lwg-toggle.ps1'),  $true)
    [IO.File]::Copy($CmdlibPath, (Join-Path $dir 'bin\lwg-cmdlib.ps1'), $true)
    [IO.File]::Copy($CommonPath, (Join-Path $dir 'lib\common.ps1'),      $true)
    return $dir
}

function Invoke-Toggle {
    <#
      Run `/lw-watchtower:delegate` with NO value - a report, nothing written - from
      inside $Cwd, against the plugin root at $FakeRoot. Returns
      @{ code; out; err }.

      $Cwd is the whole of how the command learns which repository it is in
      (Get-LwgRepoInfo over the current directory), so a per-repo override case
      is run by standing in the fabricated repo rather than by passing a slug.

      No value is passed on purpose. Every case here asks what the command
      REPORTS about a config someone else wrote; a case that wrote first would
      be testing the writer.
    #>
    param([string]$FakeRoot, [string]$WorkDir, [string]$Tag, [string]$Cwd)

    $of  = Join-Path $WorkDir "$Tag.out"
    $ef  = Join-Path $WorkDir "$Tag.err"
    $bat = Join-Path $WorkDir "$Tag.cmd"

    foreach ($f in @($of, $ef)) { if ([IO.File]::Exists($f)) { [IO.File]::WriteAllText($f, '') } }

    $lines = @(
        '@echo off'
        ('cd /d "{0}"' -f $Cwd)
        ('powershell -NoProfile -ExecutionPolicy Bypass -File "{0}" -Flag delegate 1>"{1}" 2>"{2}"' -f `
            (Join-Path $FakeRoot 'bin\lwg-toggle.ps1'), $of, $ef)
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

function New-LwgReportRoot {
    <#
      New-LwgToggleRoot's sibling for the OTHER surface that reports the gate's
      switch: the informational roster at the foot of bin\lwg-doctor.ps1. Same
      construction and for the same forced reason - the script resolves its
      plugin root as the parent of its own script directory and reads
      config.json from there, so the only way to point it at a fixture is to
      stand it next to one.

      lib\gate_delegate.ps1 is copied in as well, and not for show: section P
      asserts that the roster says so when a registry entry's `impl` path is not
      on disk, and it can only do that against a root where the file's presence
      is something the fixture controls.

      FOUR FILES IS THE WHOLE FIXTURE AND THAT IS DELIBERATE. The doctor's nine
      checks want a plugin manifest, a hooks.json, a resolvable state dir and a
      commands\ directory, and none of them is here - so most of them FAIL, and
      section P asserts nothing about them. The roster is computed from the
      module registry in lib\common.ps1 and the config.json this fixture wrote,
      which are exactly the two things a fixture can control, and it prints
      below the verdict prose whatever the checks decided.
    #>
    param([string]$Base, [string]$Name, [string]$Json, [bool]$WithGateFile = $true)

    $dir = New-LwgRawRoot -Base $Base -Name $Name -Json $Json
    [void][IO.Directory]::CreateDirectory((Join-Path $dir 'bin'))
    [void][IO.Directory]::CreateDirectory((Join-Path $dir 'lib'))
    [IO.File]::Copy($DoctorPath, (Join-Path $dir 'bin\lwg-doctor.ps1'), $true)
    [IO.File]::Copy($CommonPath, (Join-Path $dir 'lib\common.ps1'),     $true)
    if ($WithGateFile) { [IO.File]::Copy($GatePath, (Join-Path $dir 'lib\gate_delegate.ps1'), $true) }
    return $dir
}

function Invoke-Report {
    <#
      Run the doctor against $FakeRoot in a real child process and return
      @{ code; out; err }. Same cmd-file arrangement as Invoke-Toggle, and the
      same environment window around it.

      USERPROFILE IS REDIRECTED HERE AND IS NOT IN THE TOGGLE'S WINDOW. The
      doctor's status-line check reads <profile>\.claude\settings.json, which on
      a developer's machine is the operator's REAL one. The read is harmless and
      the row is not asserted on, but a suite that reaches out of its scratch
      tree for a file is a suite whose result depends on the machine it ran on,
      and this file's own header says a case that cannot be reproduced is not a
      case. Restored in the finally with the other two.
    #>
    param([string]$FakeRoot, [string]$WorkDir, [string]$Tag)

    $of  = Join-Path $WorkDir "$Tag.out"
    $ef  = Join-Path $WorkDir "$Tag.err"
    $bat = Join-Path $WorkDir "$Tag.cmd"
    foreach ($f in @($of, $ef)) { if ([IO.File]::Exists($f)) { [IO.File]::WriteAllText($f, '') } }

    $prof = Join-Path $FakeRoot 'profile'
    [void][IO.Directory]::CreateDirectory((Join-Path $prof '.claude'))

    $lines = @(
        '@echo off'
        ('cd /d "{0}"' -f $WorkDir)
        ('powershell -NoProfile -ExecutionPolicy Bypass -File "{0}" 1>"{1}" 2>"{2}"' -f `
            (Join-Path $FakeRoot 'bin\lwg-doctor.ps1'), $of, $ef)
        'exit /b %ERRORLEVEL%'
    )
    [IO.File]::WriteAllLines($bat, $lines, [Text.ASCIIEncoding]::new())

    $prevRoot = $env:CLAUDE_PLUGIN_ROOT
    $prevData = $env:CLAUDE_PLUGIN_DATA
    $prevProf = $env:USERPROFILE
    try {
        $env:CLAUDE_PLUGIN_ROOT = $FakeRoot
        $env:CLAUDE_PLUGIN_DATA = Join-Path $FakeRoot 'data'
        $env:USERPROFILE        = $prof
        & $env:ComSpec /c $bat | Out-Null
        $code = $LASTEXITCODE
    } finally {
        $env:CLAUDE_PLUGIN_ROOT = $prevRoot
        $env:CLAUDE_PLUGIN_DATA = $prevData
        $env:USERPROFILE        = $prevProf
    }

    $out = ''; $err = ''
    try { $out = [IO.File]::ReadAllText($of) } catch { }
    try { $err = [IO.File]::ReadAllText($ef) } catch { }
    return @{ code = $code; out = $out; err = $err }
}

function Get-RosterText {
    <#
      Everything from the roster's heading to the end of the doctor's stdout,
      or '' when the heading is not there.

      '' IS NEVER TREATED AS A PASS by either case that calls this. A missing
      heading means the block did not run - the doctor aborted, or the roster
      threw into its own catch - and both are things a case must go red on
      rather than quietly satisfy a -notmatch over an empty string. Section P
      asserts $p1Roster/$p2Roster is non-empty alongside every match.
    #>
    param([string]$Text)
    $i = $Text.IndexOf('WHAT IS SWITCHED ON')
    if ($i -lt 0) { return '' }
    return $Text.Substring($i)
}

function Get-ToggleEffective {
    <#
      The one word the operator reads off the report: 'ON', 'OFF', or a
      description of why neither could be found. Taken from the `effective
      here` row rather than the headline, because that row is the command's
      statement about the value a hook would resolve.
    #>
    param($R)
    if ($R.code -ne 0) { return "the command exited $($R.code); its report is a fragment, not a verdict" }
    if ($R.out -match '(?m)^\s*effective here\s*:\s*(ON|OFF)\s*$') { return $Matches[1] }
    return "no 'effective here : ON|OFF' row in the report"
}

function New-Payload {
    <#
      A PreToolUse payload. $AgentId is emitted as a member ONLY when it is not
      $null, because "the field is absent" and "the field is an empty string"
      are two different inputs and the gate has to treat both as the main
      thread. Built as text rather than through ConvertTo-Json so a case can
      control exactly which members exist.
    #>
    param([string]$Tool, $AgentId, [string]$AgentType, [string]$Extra)

    $parts = @(
        '"session_id":"lwg-test-session"'
        '"transcript_path":"C:/nowhere/transcript.jsonl"'
        '"cwd":"C:/nowhere"'
        '"hook_event_name":"PreToolUse"'
        ('"tool_name":"' + $Tool + '"')
    )
    if ($null -ne $AgentId)                             { $parts += ('"agent_id":"' + $AgentId + '"') }
    if (-not [string]::IsNullOrEmpty($AgentType))       { $parts += ('"agent_type":"' + $AgentType + '"') }
    if (-not [string]::IsNullOrEmpty($Extra))           { $parts += $Extra }
    return '{' + ($parts -join ',') + '}'
}

function Test-IsDeny {
    <#
      Did this run BLOCK? The exit-2 contract, asserted as a contract rather
      than as "nonzero":

        code 2   the only exit code that blocks a PreToolUse call
        code 1   does NOT block - the CLI reads it as a non-blocking error and
                 the tool runs. A gate that exits 1 has silently failed open,
                 so 1 is checked for by name and reported as such.
        stderr   must carry the reason; under exit 2 the CLI reads stderr and
                 ignores stdout, so an empty stderr is a block with no reason
                 attached to it.

      The stdout envelope is asserted separately - it is the redundant second
      channel, not the load-bearing one.
    #>
    param($R)
    if ($R.code -eq 1) { return @{ ok = $false; why = 'exited 1, which does NOT block - the tool call proceeds. This is the silent fail-open the contract exists to prevent' } }
    if ($R.code -ne 2) { return @{ ok = $false; why = "exited $($R.code); only exit 2 blocks a PreToolUse call" } }
    if ([string]::IsNullOrWhiteSpace($R.err)) { return @{ ok = $false; why = 'exited 2 but wrote nothing to stderr - under exit 2 the CLI reads stderr, so this blocks with no reason shown' } }
    return @{ ok = $true; why = '' }
}

function Test-IsAllow {
    <# Did this run stay out of the way? Exit 0 and not one byte emitted. #>
    param($R)
    if ($R.code -ne 0) { return @{ ok = $false; why = "exited $($R.code), expected 0" } }
    if (-not [string]::IsNullOrWhiteSpace($R.out)) { return @{ ok = $false; why = "wrote to stdout when it should have been silent: $($R.out)" } }
    if (-not [string]::IsNullOrWhiteSpace($R.err)) { return @{ ok = $false; why = "wrote to stderr when it should have been silent: $($R.err)" } }
    return @{ ok = $true; why = '' }
}

function Get-LwgRealLogBytes {
    <#
      The size of a file in bytes, or -1 when it is not there. Used on exactly
      one path - the operator's live lw-watchtower.jsonl - by section L.

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
# the environment that resolver reads. Section L compares the two at the end.
$realLog      = ''
$realLogBytes = [long](-1)

try {
    Write-Output 'LW-WATCHTOWER delegate_gate regression suite'
    Write-Output "  repo : $Root"
    Write-Output "  gate : $GatePath"
    Write-Output ''

    # $DoctorPath joined this list when section P was re-pointed at the doctor's
    # informational roster: it is copied into a fixture, and a missing source
    # file should name itself here rather than surface as a copy exception from
    # inside a case.
    foreach ($p in @($GatePath, $HooksPath, $CfgPath, $CommonPath, $TogglePath, $DoctorPath)) {
        if (-not [IO.File]::Exists($p)) { throw "missing: $p" }
    }

    $work = Join-Path ([IO.Path]::GetTempPath()) ('lwg-gate-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
    [void][IO.Directory]::CreateDirectory($work)

    # -------------------------------------------------------------------
    # THE SANDBOX, FOR THE WHOLE RUN. See the header. The windows inside
    # Invoke-Gate and Invoke-Toggle wrap child spawns only; this is what
    # covers everything THIS process does, which is where the leak was.
    # -------------------------------------------------------------------
    # lib\common.ps1 is dot-sourced HERE rather than in section C, where the
    # first case that needs it lives, and the order is forced: the sandbox has
    # to be standing before any in-process call can resolve a state directory,
    # and working out what the sandbox is REPLACING needs common.ps1's own
    # resolver. Spelling that resolution rule a second time in this file would
    # create a second thing to keep in step with it, which is the class of
    # defect this repository exists to argue about.
    . $CommonPath

    # WHERE THIS PROCESS WOULD OTHERWISE HAVE WRITTEN. Resolved from the AMBIENT
    # environment - the operator's - because that is the destination the
    # unwindowed calls in section K actually reached, and the only path section L
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
    # own enough and the memo is refreshed - the same pairing
    # tests\stop_behaviour.ps1 uses around its rotation cases, and for the same
    # reason.
    $sandboxRoot = Join-Path $work 'sandbox'
    $sandboxData = Join-Path $sandboxRoot 'data'
    [void][IO.Directory]::CreateDirectory($sandboxData)
    $env:CLAUDE_PLUGIN_ROOT = $sandboxRoot
    $env:CLAUDE_PLUGIN_DATA = $sandboxData
    Get-LwgStateDirInfo -Refresh | Out-Null

    $rootOff = New-LwgFakeRoot -Base $work -On $false
    $rootOn  = New-LwgFakeRoot -Base $work -On $true

    $gateSrc  = [IO.File]::ReadAllText($GatePath)
    $hooksRaw = [IO.File]::ReadAllText($HooksPath)
    $hooks    = $hooksRaw | ConvertFrom-Json

    # -------------------------------------------------------------------
    # A. REGISTRATION. A gate that is not registered refuses nothing, and it
    #    refuses nothing SILENTLY - which is indistinguishable from a session
    #    in which nothing needed refusing.
    #
    #    ALL SIX CASES HERE ARE UNCONDITIONAL, AND THAT IS A FIX RATHER THAN
    #    THE ORIGINAL SHAPE. Five of the six Add-Result calls used to sit
    #    inside `if` blocks whose conditions were the assertions the cases
    #    above them make - `if ($null -ne $pre)`, then `if ($mine.Count -eq 1)`.
    #    Add-Result is the only thing that puts a case in the denominator, so a
    #    registration defect DELETED cases instead of failing them.
    #
    #    MEASURED, not reasoned: a second PreToolUse entry naming the gate -
    #    the shape a merge of two branches that both widened the matcher
    #    produces on its own - was written into hooks/hooks.json in a throwaway
    #    worktree at cc44c99 and this suite reported "79 case(s) had run"
    #    against a header that says how many there are. The four that went
    #    missing from section A are the four that say WHICH tools the
    #    registration does and does not cover, whether it is exec form, and
    #    whether it resolves through CLAUDE_PLUGIN_ROOT - which is precisely
    #    the set a maintainer needs at the moment the registration is what
    #    broke.
    #
    #    So the inputs are resolved defensively and the ASSERTION is allowed to
    #    be false. $entry is $null when the entry could not be resolved, and
    #    every case below tests that FIRST rather than relying on the rest of
    #    its condition to fail: `$null | ConvertTo-Json` is the four-character
    #    string "null", which contains no "shell" key, so the shell-form case
    #    would otherwise have PASSED on a run where there was no entry to look
    #    at. A case that passes by asking its question of nothing is the same
    #    manufactured confidence as a case that was never called, with a green
    #    line to show for it.
    #
    #    WHAT THIS DOES NOT FIX, stated because the number still moves on that
    #    path: section M throws when section A resolved no matcher, which
    #    aborts the whole suite - this file's sanctioned outcome for a case
    #    that cannot run - and sections M and L then do not run either. On that
    #    path there is no tally line at all; there is "N case(s) had run. The
    #    suite did NOT complete, so nothing above is a verdict", which is a
    #    statement that nothing was established rather than a smaller verdict.
    #    The denominator guard at the foot of this file covers the COMPLETED
    #    run, which is the only place a silent subtraction could still hide.
    # -------------------------------------------------------------------
    $pre = $null
    try { $pre = $hooks.hooks.PreToolUse } catch { }
    Add-Result 'registration: hooks.json declares PreToolUse' ($null -ne $pre) `
        'hooks/hooks.json has no PreToolUse key, so the gate script is never invoked'

    $mine = @()
    if ($null -ne $pre) {
        $mine = @(@($pre) | Where-Object {
            $s = ($_ | ConvertTo-Json -Depth 8 -Compress)
            $s -like '*gate_delegate.ps1*' })
    }
    Add-Result 'registration: exactly one PreToolUse entry names the gate' ($mine.Count -eq 1) `
        ("found $($mine.Count) PreToolUse entries naming gate_delegate.ps1, expected 1" +
         $(if ($null -eq $pre) { ' - there is no PreToolUse key at all, so there was nothing to count' } else { '' }))

    $entry = if ($mine.Count -eq 1) { $mine[0] } else { $null }

    # Handed to section M, which runs the CLI's selection step against it.
    # Taken from the parse rather than re-read there: one read of hooks.json,
    # one statement of what it says.
    #
    # LEFT $null WHEN THERE IS NO ENTRY, deliberately. Section M aborts on
    # $null, and substituting a plausible matcher here to keep M running would
    # be the quiet subtraction in different clothes - three cases answering a
    # question about a string this section invented.
    if ($null -ne $entry) { $script:GateMatcher = [string]$entry.matcher }

    # The one detail string shared by the four cases below. It says "could not
    # look", not "looked and the answer was wrong", because those are different
    # statements and a red line that confuses them sends a maintainer to
    # hooks.json's matcher for a defect that is in its entry count.
    $aUnresolved = 'the PreToolUse entry naming gate_delegate.ps1 could not be resolved, so this case had nothing to inspect - it did NOT pass, and it did NOT establish anything. Fix the case above it first.'

    $declared = @()
    if ($null -ne $entry) {
        $declared = @([string]$entry.matcher -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    $missing  = @($GatedTools | Where-Object { $declared -notcontains $_ })
    $surplus  = @($declared   | Where-Object { $GatedTools -notcontains $_ })
    # A SURPLUS is REPORTED AND NOT FAILED, and the reason is narrower
    # than it used to be written here. This line used to say that
    # widening the matcher refuses more, "which is the safe direction",
    # full stop. That is true of adding a mutating tool and false past a
    # point: the gate is tool-blind, so whatever the matcher selects on
    # the main thread gets refused - and the moment that includes Agent,
    # the operator cannot make the dispatch the deny text tells them to
    # make, with /lw-watchtower:delegate off already refused through Bash. So
    # a surplus is not failed HERE, because a deliberate widening should
    # not have to edit this list first; the surplus that would actually
    # be a lockout is failed in SECTION M, by name, against
    # $UngatedTools. A MISSING tool is a hole and is failed here.
    Add-Result 'registration: the matcher names every gated tool' `
        ($null -ne $entry -and $missing.Count -eq 0) `
        $(if ($null -eq $entry) { $aUnresolved } else { "matcher '$($entry.matcher)' does not cover: $($missing -join ', ')" })
    if ($surplus.Count -gt 0) {
        Write-Output ("  note  matcher also covers {0} - more is refused. Not failed here; section M is what fails a widening that reaches Agent or Read" -f ($surplus -join ', '))
    }

    $h = $null
    try { $h = @($entry.hooks)[0] } catch { }
    Add-Result 'registration: exec form, command + args' `
        ($null -ne $entry -and $null -ne $h -and [string]$h.type -eq 'command' -and [string]$h.command -eq 'powershell' -and @($h.args).Count -gt 0) `
        $(if ($null -eq $entry) { $aUnresolved } else { "the hook must be type 'command' with command 'powershell' and an args array; got type '$($h.type)', command '$($h.command)'" })

    # pwsh is absent on the machines this ships to, and `shell:` would
    # look for it. This is a shape assertion, not a taste one.
    $entryJson = if ($null -ne $entry) { ($entry | ConvertTo-Json -Depth 8 -Compress) } else { '' }
    Add-Result 'registration: no shell: form anywhere in the entry' `
        ($null -ne $entry -and $entryJson -notmatch '"shell"\s*:') `
        $(if ($null -eq $entry) { $aUnresolved } else { 'the registration uses a "shell" key; pwsh is absent, so it must invoke powershell through command + args' })

    $argsJoined = (@($h.args) -join ' ')
    Add-Result 'registration: args resolve the gate through CLAUDE_PLUGIN_ROOT' `
        ($null -ne $entry -and $argsJoined -like '*${CLAUDE_PLUGIN_ROOT}*gate_delegate.ps1*') `
        $(if ($null -eq $entry) { $aUnresolved } else { "args do not name `${CLAUDE_PLUGIN_ROOT}/lib/gate_delegate.ps1: $argsJoined" })

    # -------------------------------------------------------------------
    # B. THE FIELD IT READS. This is the one mistake that would invert the
    #    gate, so it is asserted on the source directly rather than left to
    #    be caught by a behaviour case that happens to cover it.
    # -------------------------------------------------------------------
    Add-Result 'source: decides on agent_id' ($gateSrc -match '\$payload\.agent_id') `
        'the gate does not read $payload.agent_id - it has no way to tell a subagent from the main thread'
    Add-Result 'source: never reads agent_type' ($gateSrc -notmatch '\$payload\.agent_type') `
        'the gate reads $payload.agent_type. A settings.json `agent` key gives the MAIN thread a non-empty agent_type, so this classifies the main thread as a subagent and allows every call it exists to refuse'

    # -------------------------------------------------------------------
    # C. THE SWITCH. Two halves that must name the same key: the registry
    #    entry the gate resolves through, and the command that writes it.
    # -------------------------------------------------------------------
    # lib\common.ps1 used to be dot-sourced on this line, next to the first case
    # that needs it. It is loaded at the top of MAIN instead - see the sandbox
    # block there for why the order is forced. Nothing between there and here
    # calls into it, so the move changes what is in scope for no case.

    $entryReg = $null
    try { $entryReg = $script:LwgModuleRegistry['delegate_gate'] } catch { }
    Add-Result 'registry: delegate_gate is declared kind gate' `
        ($null -ne $entryReg -and [string]$entryReg.kind -eq 'gate') `
        "the registry has no delegate_gate entry of kind 'gate', so the gate count, the mode word and the banner cannot see it"

    $swPath = ''
    if ($null -ne $entryReg -and $null -ne $entryReg.switch) {
        $swPath = "$($entryReg.switch.block).$($entryReg.switch.key)"
    }
    Add-Result 'registry: its switch is interaction.delegate, default off' `
        ($swPath -eq 'interaction.delegate' -and $null -ne $entryReg -and [bool]$entryReg.switch.default -eq $false) `
        "the registry declares the switch as '$swPath' with default '$(if ($null -ne $entryReg -and $null -ne $entryReg.switch) { $entryReg.switch.default } else { 'none' })', expected interaction.delegate defaulting to False"

    # The command's own report is the second half. Run with no value it writes
    # nothing and prints where it stores the flag; if that ever stops being the
    # key the gate reads, the operator's toggle silently stops arming the gate.
    $toggleOut = ''
    try {
        $toggleOut = (& powershell -NoProfile -ExecutionPolicy Bypass `
            -File (Join-Path $Root 'bin\lwg-toggle.ps1') -Flag delegate 2>&1 | Out-String)
    } catch { $toggleOut = "toggle threw: $($_.Exception.Message)" }
    # $swPath IS ASSERTED NON-EMPTY IN THE SAME EXPRESSION THAT INTERPOLATES
    # IT, and that is the whole of this guard. $swPath is '' on exactly two
    # conditions - no delegate_gate entry in $LwgModuleRegistry, or an entry
    # that declares no switch - and both are states section C exists to catch.
    # [regex]::Escape('') is '', so the pattern collapsed to
    #
    #     (?m)stored in\s*:.*\b\s*$
    #
    # where `.*` backtracks until `\b` sits at the end of the last word on the
    # line and `\s*$` matches empty. Measured in Windows PowerShell 5.1:
    # "stored in : totally.different.key" MATCHES that pattern and does not
    # match the interaction.delegate one. So on the path where the registry
    # lookup failed, this case printed a green line having compared the
    # toggle's report against nothing at all - next to a sibling case that had
    # just failed for the very reason the comparison was impossible. The suite
    # still exited 1, so nothing green shipped; what shipped was a maintainer
    # fixing the registry shape, re-running, and never once having had the
    # toggle/gate key correspondence checked across that edit.
    #
    # NOT HARD-CODED to 'interaction.delegate', deliberately. This case's
    # purpose is that the command and the REGISTRY name the same key; pinning
    # the literal here would make the test agree with itself and stop it
    # noticing a registry that had moved on.
    Add-Result 'switch: /lw-watchtower:delegate writes the key the gate reads' `
        ((-not [string]::IsNullOrWhiteSpace($swPath)) -and
         $toggleOut -match ('(?m)stored in\s*:.*\b' + [regex]::Escape($swPath) + '\s*$')) `
        $(if ([string]::IsNullOrWhiteSpace($swPath)) {
            "the registry yielded no switch path, so this case had nothing to compare the toggle's report against - it did NOT pass, and it did NOT establish that the command still writes the key the gate reads. Fix the registry case above it first."
          } else {
            "bin\lwg-toggle.ps1 -Flag delegate does not report storing to '$swPath'. Its report was:`n$toggleOut"
          })

    Add-Result 'shipped config: the gate is OFF by default' `
        (-not (Test-LwgModule -Name 'delegate_gate' -Config (Get-LwgConfig -Path $CfgPath) -Repo '')) `
        'the shipped config.json arms the gate. It must ship off - a blocking gate switched on by default is the opposite of what this plugin argues for'

    # -------------------------------------------------------------------
    # D. BEHAVIOUR - every gated tool, both switch states, both callers.
    # -------------------------------------------------------------------
    #    THESE CASES CANNOT SEE A MATCHER, and that is why section M exists.
    #    They pipe a payload into the gate directly, which is the whole of what
    #    the gate does with it - but the gate is tool-blind by design, so a tool
    #    the matcher never selects passes all four of its cases here anyway.
    #    That is exactly how PowerShell was missing from the registration while
    #    a suite this file's header called 80 of 80 stayed green.
    #
    #    SO THE FOUR NEW PowerShell CASES BELOW ARE DOCUMENTATION, NOT
    #    SENTINELS, and that is measured rather than reasoned: all four were run
    #    against fd8d023 - the tree with the hole - and all four PASSED. They
    #    pin that the gate's rule treats the second shell like the first, which
    #    is worth having and is not what was broken.
    #
    #    THE RED-FIRST PROOF FOR THIS DEFECT IS M1 ALONE, AND ONLY INJECTED -
    #    which is the qualification that makes the sentence true, not a hedge
    #    on it: M1 and $script:GateMatcher do not exist at fd8d023, so M1
    #    cannot be run against that tree as it stands. Injected into a snapshot,
    #    it fails because the matcher there is "Edit|Write|NotebookEdit|Bash",
    #    so Invoke-GateAsCli's selection step never invokes the gate and M1
    #    fails on $m1.invoked.
    #
    #    SECTION A IS NOT PART OF THAT PROOF, and this comment named it until
    #    3 August 2026. Neither section-A case the old sentence could have meant
    #    fails at fd8d023: that tree's PreToolUse array holds exactly one entry
    #    naming gate_delegate.ps1, so the registration case passes, and its
    #    $GatedTools is @('Edit','Write','NotebookEdit','Bash') - the same four
    #    names its matcher spells - so $missing and $surplus are both empty and
    #    the coverage case passes too. That coverage case can only fail on a
    #    MIXED tree, this wave's widened $GatedTools against the unwidened
    #    hooks.json, and no such tree is claimed here.
    #
    #    WHAT THE LAST TWO PARAGRAPHS REST ON, since it is not the same source
    #    as the sentence above them: M1's failure and both section-A readings
    #    are DERIVED BY READING fd8d023's FILES, not measured by running this
    #    suite against that tree. That is weaker than the "all four PASSED"
    #    above, and it is said rather than blurred.
    foreach ($tool in $GatedTools) {
        # A payload shaped the way that tool's really is. The two shell ones
        # name an INVENTED command on purpose, in the invented flag spelling
        # each shell would use: no test in this repository constructs a real
        # destructive command, not even as a string it never runs.
        $extra = switch ($tool) {
            'Bash'         { '"tool_input":{"command":"lwg-noop-fixture --dry-run"}' }
            'PowerShell'   { '"tool_input":{"command":"lwg-noop-fixture -DryRun"}' }
            'NotebookEdit' { '"tool_input":{"notebook_path":"C:/nowhere/fixture.ipynb","new_source":"pass"}' }
            default        { '"tool_input":{"file_path":"C:/nowhere/fixture.txt","content":"fixture"}' }
        }

        # 1. gate ON, main thread (no agent_id at all) -> DENY
        $r = Invoke-Gate -FakeRoot $rootOn -WorkDir $work -Tag "on-main-$tool" `
                         -Payload (New-Payload -Tool $tool -AgentId $null -AgentType '' -Extra $extra)
        $v = Test-IsDeny $r
        Add-Result "on, main thread, $tool -> DENY" $v.ok $v.why

        # The stdout envelope, on one representative tool. Checked for shape
        # and for decision, because a malformed envelope is IGNORED and a gate
        # that emits one has reported a block it did not perform.
        #
        # THE CONDITION IS THE TOOL AND NOTHING ELSE, and it used to be
        # `$tool -eq 'Write' -and $v.ok`. $v.ok is the assertion of the case on
        # the line above, so a gate that stopped denying on the main thread
        # failed that case and DELETED these two - and these two are the ones
        # that say HOW the refusal was malformed. The comment above is the
        # argument against the old form: a malformed envelope is worth catching
        # on every path, not only on the path where the block already worked.
        #
        # MEASURED ON THIS TREE, 3 September 2026. With the one rule in
        # lib\gate_delegate.ps1 replaced by an unconditional `exit 0` - the gate
        # never denies - the suite ran 91 cases and aborted:
        #
        #   ABORTED: 91 case(s) ran and this file declares 93 in
        #   $script:ExpectedCases. A case was added without moving that
        #   constant, the header and the documents quoting it, or a case
        #   stopped being reached.
        #
        # $script:ExpectedCases caught the shrinkage, which is what it is for -
        # but it caught it as "somebody edited this file wrong" rather than as
        # "the gate stopped denying", and the two cases that would have named
        # the empty channel had still not run. So the constant bounds this
        # defect; it does not answer it. With the guard gone both bodies run on
        # an allow and fail honestly: $r.out is empty, so ConvertFrom-Json
        # fails and $okEnv is false; $r.err is empty, so neither -like matches.
        if ($tool -eq 'Write') {
            $env0 = $null
            try { $env0 = $r.out | ConvertFrom-Json } catch { }
            $okEnv = ($null -ne $env0 -and
                      [string]$env0.hookSpecificOutput.hookEventName      -eq 'PreToolUse' -and
                      [string]$env0.hookSpecificOutput.permissionDecision -eq 'deny' -and
                      -not [string]::IsNullOrWhiteSpace([string]$env0.hookSpecificOutput.permissionDecisionReason))
            Add-Result 'on, main thread: the stdout deny envelope is well formed' $okEnv `
                "stdout did not parse as a PreToolUse deny envelope with a reason: $($r.out)"

            Add-Result 'on, main thread: the reason names the way out' `
                ($r.err -like '*subagent*' -and $r.err -like '*config.json*') `
                "the deny reason does not tell the operator how to proceed or how to turn the gate off: $($r.err)"
        }

        # 2. gate ON, subagent (agent_id present) -> ALLOW
        $r = Invoke-Gate -FakeRoot $rootOn -WorkDir $work -Tag "on-sub-$tool" `
                         -Payload (New-Payload -Tool $tool -AgentId 'a3b438dd7dd6bb07a' -AgentType 'lw-watchtower:lw-implementer' -Extra $extra)
        $v = Test-IsAllow $r
        Add-Result "on, subagent, $tool -> ALLOW" $v.ok $v.why

        # 3. gate OFF, main thread -> ALLOW. The default state, and the one an
        #    operator who never touches this switch is in for every call.
        $r = Invoke-Gate -FakeRoot $rootOff -WorkDir $work -Tag "off-main-$tool" `
                         -Payload (New-Payload -Tool $tool -AgentId $null -AgentType '' -Extra $extra)
        $v = Test-IsAllow $r
        Add-Result "off, main thread, $tool -> ALLOW" $v.ok $v.why

        # 4. gate OFF, subagent -> ALLOW.
        $r = Invoke-Gate -FakeRoot $rootOff -WorkDir $work -Tag "off-sub-$tool" `
                         -Payload (New-Payload -Tool $tool -AgentId 'a3b438dd7dd6bb07a' -AgentType 'lw-watchtower:lw-implementer' -Extra $extra)
        $v = Test-IsAllow $r
        Add-Result "off, subagent, $tool -> ALLOW" $v.ok $v.why
    }

    # -------------------------------------------------------------------
    # E. THE TRAP. agent_type is present and non-empty, agent_id is not -
    #    which is exactly what the main thread looks like on a machine whose
    #    settings.json sets an `agent`. A gate reading agent_type allows this;
    #    this gate must refuse it.
    # -------------------------------------------------------------------
    $r = Invoke-Gate -FakeRoot $rootOn -WorkDir $work -Tag 'trap-agenttype' `
                     -Payload (New-Payload -Tool 'Write' -AgentId $null -AgentType 'hq-orchestrator' -Extra '"tool_input":{"file_path":"C:/nowhere/fixture.txt"}')
    $v = Test-IsDeny $r
    # Single-quoted tail: a backtick in a double-quoted PowerShell string is the
    # escape character, and "sets `agent`" renders as "sets gent".
    Add-Result 'on, main thread carrying agent_type but no agent_id -> DENY' $v.ok `
        ($v.why + '  --  this is the main thread of a session whose settings.json sets an `agent` key. Allowing it is the inversion the gate is built to avoid')

    # An agent_id that is present but EMPTY, or whitespace, is not evidence of a
    # subagent. "The field exists" is not the test; a value is.
    foreach ($blank in @(@{ v = ''; n = 'empty' }, @{ v = '   '; n = 'whitespace' })) {
        $r = Invoke-Gate -FakeRoot $rootOn -WorkDir $work -Tag ("blank-" + $blank.n) `
                         -Payload (New-Payload -Tool 'Edit' -AgentId $blank.v -AgentType '' -Extra '"tool_input":{"file_path":"C:/nowhere/fixture.txt"}')
        $v = Test-IsDeny $r
        Add-Result "on, main thread with an $($blank.n) agent_id -> DENY" $v.ok $v.why
    }

    # A forged agent_id in the CONTENT being written. The gate must parse the
    # payload as JSON, not search it as text - a substring check here would let
    # any write whose body mentions the field bypass the gate outright.
    $forge = '"tool_input":{"file_path":"C:/nowhere/fixture.txt","content":"logged: {\"agent_id\":\"forged-not-a-real-caller\"}"}'
    $r = Invoke-Gate -FakeRoot $rootOn -WorkDir $work -Tag 'forged-agentid' `
                     -Payload (New-Payload -Tool 'Write' -AgentId $null -AgentType '' -Extra $forge)
    $v = Test-IsDeny $r
    Add-Result 'on, main thread writing content that CONTAINS an agent_id -> DENY' $v.ok `
        ("$($v.why)  --  the payload is parsed as JSON, so a forged field in tool_input must not be mistaken for the caller's")

    # -------------------------------------------------------------------
    # F. MALFORMED AND ABSENT INPUT. With the gate on, input the script could
    #    not read is not evidence of a subagent, so it must refuse. With the
    #    gate off it must still stay out of the way.
    # -------------------------------------------------------------------
    $malformed = @(
        @{ n = 'empty';            p = '' }
        @{ n = 'whitespace';       p = "  `r`n  " }
        @{ n = 'not-json';         p = 'this is not json at all' }
        @{ n = 'truncated-json';   p = '{"session_id":"x","tool_name":"Write"' }
        @{ n = 'json-null';        p = 'null' }
        @{ n = 'json-array';       p = '[]' }
        @{ n = 'json-scalar';      p = '42' }
        @{ n = 'no-tool-name';     p = '{"session_id":"x","cwd":"C:/nowhere"}' }
    )
    foreach ($m in $malformed) {
        $r = Invoke-Gate -FakeRoot $rootOn -WorkDir $work -Tag ("bad-on-" + $m.n) -Payload $m.p
        $v = Test-IsDeny $r
        Add-Result "on, $($m.n) input -> DENY (fails safe)" $v.ok `
            ("$($v.why)  --  unreadable input is not evidence that a subagent made the call")

        $r = Invoke-Gate -FakeRoot $rootOff -WorkDir $work -Tag ("bad-off-" + $m.n) -Payload $m.p
        $v = Test-IsAllow $r
        Add-Result "off, $($m.n) input -> ALLOW" $v.ok `
            ("$($v.why)  --  with the switch off the gate must never block, whatever it was handed")
    }

    # -------------------------------------------------------------------
    # G. A CONFIG IT CANNOT READ. The gate must ALLOW - the switch is off by
    #    default and a config we could not read is no evidence the operator
    #    turned it on. It is also what keeps a corrupt config a nuisance
    #    rather than a lockout: the file that has to be fixed is one the gate
    #    would otherwise refuse to let the main thread edit.
    # -------------------------------------------------------------------
    $rootBad = Join-Path $work 'root-corrupt'
    [void][IO.Directory]::CreateDirectory($rootBad)
    [void][IO.Directory]::CreateDirectory((Join-Path $rootBad 'data'))
    [IO.File]::WriteAllText((Join-Path $rootBad 'config.json'), '{ this is not valid json', [Text.UTF8Encoding]::new($false))
    $r = Invoke-Gate -FakeRoot $rootBad -WorkDir $work -Tag 'corrupt-config' `
                     -Payload (New-Payload -Tool 'Bash' -AgentId $null -AgentType '' -Extra '"tool_input":{"command":"lwg-noop-fixture"}')
    $v = Test-IsAllow $r
    Add-Result 'corrupt config, main thread -> ALLOW' $v.ok `
        ("$($v.why)  --  an unreadable config must leave the gate off, or a bad config becomes a lockout")

    $rootNone = Join-Path $work 'root-noconfig'
    [void][IO.Directory]::CreateDirectory($rootNone)
    [void][IO.Directory]::CreateDirectory((Join-Path $rootNone 'data'))
    $r = Invoke-Gate -FakeRoot $rootNone -WorkDir $work -Tag 'absent-config' `
                     -Payload (New-Payload -Tool 'Bash' -AgentId $null -AgentType '' -Extra '"tool_input":{"command":"lwg-noop-fixture"}')
    $v = Test-IsAllow $r
    Add-Result 'absent config, main thread -> ALLOW' $v.ok $v.why

    # -------------------------------------------------------------------
    # H. PER-REPO OVERRIDE. config.json documents that repos[slug] overrides
    #    the global key by key. If the gate did not honour it, an operator who
    #    armed the gate for one repository would have armed nothing.
    # -------------------------------------------------------------------
    #    The slug is resolved from the payload's cwd by walking up for .git, so
    #    the cwd is a FABRICATED repository under the work directory rather than
    #    this checkout: see New-LwgFakeRepo, and "A CASE THAT CANNOT RUN" in the
    #    header for the skipped-case defect that made that necessary. Nothing
    #    real is read or written either way.
    $slug      = 'lwg-fixture/gate-suite'
    $otherSlug = 'lwg-fixture/some-other-repo'
    $repoNamed   = New-LwgFakeRepo -Base $work -Name 'repo-named'   -Slug $slug
    $repoUnnamed = New-LwgFakeRepo -Base $work -Name 'repo-unnamed' -Slug $otherSlug

    $rootRepo = Join-Path $work 'root-repo-override'
    [void][IO.Directory]::CreateDirectory($rootRepo)
    [void][IO.Directory]::CreateDirectory((Join-Path $rootRepo 'data'))
    # Global OFF, this one repository ON. If the override is ignored the
    # call is allowed and this case fails - which is the right polarity:
    # the failure is the gate refusing too little.
    $ovr = [ordered]@{
        version = '0.2.0'
        modules = [ordered]@{ failure_capture = $true }
        interaction = [ordered]@{ delegate = $false }
        repos = [ordered]@{ $slug = [ordered]@{ interaction = [ordered]@{ delegate = $true } } }
    }
    [IO.File]::WriteAllText((Join-Path $rootRepo 'config.json'),
        ($ovr | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))

    $pay = '{"session_id":"lwg-test-session","hook_event_name":"PreToolUse","tool_name":"Edit",' +
           '"cwd":"' + ($repoNamed -replace '\\', '/') + '",' +
           '"tool_input":{"file_path":"C:/nowhere/fixture.txt"}}'
    $r = Invoke-Gate -FakeRoot $rootRepo -WorkDir $work -Tag 'repo-override-on' -Payload $pay
    $v = Test-IsDeny $r
    Add-Result "per-repo override arms the gate for $slug -> DENY" $v.ok `
        ("$($v.why)  --  global is false, repos['$slug'].interaction.delegate is true, and the override must win")

    # And the mirror: a repo the override does not name falls through to the
    # global, which is off. A SECOND fabricated repo rather than a directory
    # that merely happens to be outside one - "no repo at all" and "a repo the
    # config does not name" are two different inputs, and this case is about
    # the second.
    $payElse = '{"session_id":"lwg-test-session","hook_event_name":"PreToolUse","tool_name":"Edit",' +
               '"cwd":"' + ($repoUnnamed -replace '\\', '/') + '",' +
               '"tool_input":{"file_path":"C:/nowhere/fixture.txt"}}'
    $r = Invoke-Gate -FakeRoot $rootRepo -WorkDir $work -Tag 'repo-override-elsewhere' -Payload $payElse
    $v = Test-IsAllow $r
    Add-Result "a repo the override does not name ($otherSlug) falls through to the global -> ALLOW" $v.ok $v.why

    # -------------------------------------------------------------------
    # I. THE FAST PATH. lib/gate_delegate.ps1 proves the switch off from the
    #    raw text of config.json before it loads the JSON engine, and exits 0
    #    on that proof alone. Read the honesty note in this file's header
    #    first: NONE of these cases can tell an allow that came from the fast
    #    path from an allow that came from the slow one. What they establish is
    #    that a config of each of these shapes still produces the RIGHT answer,
    #    whichever path produced it - which is the property that matters, and
    #    is the one that a fast path returning the wrong answer would break.
    #
    #    Two shapes are worth more than the rest. I3a is the comment trap: a
    #    config whose interaction block contains the literal text
    #    \"delegate\": true inside a JSON string, which any substring search
    #    for the flag reads as the setting. I6 is the nesting trap: a decoy
    #    interaction block one level down. Without a depth guard the scanner
    #    finds the decoy's false, exits 0, and the gate never fires - a
    #    fail-open, in the file whose whole job is not to have one.
    # -------------------------------------------------------------------
    $editPay = '"tool_input":{"file_path":"C:/nowhere/fixture.txt","content":"fixture"}'

    # A comment holding braces, escaped quotes, and the flag set the OTHER way.
    # Single-quoted here-strings: every backslash and quote below is JSON's, and
    # a double-quoted one would hand PowerShell the escaping instead.
    $trapComment = '"$comment": "Example: { \"repos\": { \"owner/name\": { \"interaction\": { \"delegate\": true } } } } - braces and all.",'

    $fastCases = @(
        @{
            tag  = 'fast-no-repos'
            name = 'I1  delegate false, no repos member at all -> ALLOW'
            deny = $false
            json = '{"version":"0.2.0","modules":{"failure_capture":true},"interaction":{"delegate":false}}'
            why  = 'the shape a config takes when nothing has ever written a per-repo override'
        }
        @{
            tag  = 'fast-repos-comment'
            name = 'I2  delegate false, repos holding only a comment -> ALLOW'
            deny = $false
            json = '{"version":"0.2.0","modules":{"failure_capture":true},"interaction":{"delegate":false},' +
                   '"repos":{"$comment":"Per-repo overrides keyed by the owner/name slug of the origin remote."}}'
            why  = 'the shape config.json actually ships in - a repos block with no repo in it'
        }
        @{
            tag  = 'fast-comment-trap-off'
            name = 'I3a delegate false under a comment containing \"delegate\": true -> ALLOW'
            deny = $false
            json = '{"version":"0.2.0","modules":{"failure_capture":true},"interaction":{' + $trapComment +
                   '"delegate":false},"repos":{"$comment":"nothing here"}}'
            why  = 'a reader that searched the text for the flag would find the comment first and read the gate as armed'
        }
        @{
            tag  = 'fast-comment-trap-on'
            name = 'I3b delegate true under a comment containing \"delegate\": true -> DENY'
            deny = $true
            json = '{"version":"0.2.0","modules":{"failure_capture":true},"interaction":{' + $trapComment +
                   '"delegate":true},"repos":{"$comment":"nothing here"}}'
            why  = 'the mirror of I3a, and the one that fails OPEN if the scanner stops at the comment'
        }
        @{
            tag  = 'fast-comment-trap-inverted'
            name = 'I3c delegate true under a comment containing \"delegate\": false -> DENY'
            deny = $true
            json = '{"version":"0.2.0","modules":{"failure_capture":true},"interaction":{' +
                   '"$comment": "Ships off: { \"interaction\": { \"delegate\": false } } is the default.",' +
                   '"delegate":true},"repos":{"$comment":"nothing here"}}'
            # THE ONE THAT CAN GO RED, and it is why it is here. I3a and I3b
            # cannot: a scanner fooled by a comment saying `true` only ever
            # declines to prove the switch off, which costs milliseconds and
            # changes no answer. This is the mirror - a comment saying `false`
            # over a switch that is really ON - and a scanner fooled by THIS one
            # exits 0 and the gate never fires.
            why  = 'a scanner that reads the comment instead of the setting proves the switch off while it is on, and the gate silently stops firing'
        }
        @{
            tag  = 'fast-no-interaction'
            name = 'I4  no interaction member at all -> ALLOW'
            deny = $false
            json = '{"version":"0.2.0","modules":{"failure_capture":true},"repos":{"$comment":"nothing here"}}'
            why  = 'an absent switch is the built-in default, which is off'
        }
        # I5 WAS HERE and is deliberately gone rather than merely renumbered.
        # It pinned `"delegate": "true"` (a STRING) as a DENY, on the reasoning
        # that the fast path cannot read a quoted literal, so the slow path
        # decides, where [bool] on a non-empty string is $true. The first half
        # of that is still true and the second half was a defect, not a design:
        # `"delegate": "false"` armed the gate by the same route. Test-LwgFlag
        # now ignores any value that is not a real boolean, and BOTH string
        # spellings are pinned in section J - J8 and J9 - with the reasoning
        # written out there. Two cases in two sections asserting opposite
        # answers about one input is worse than a case that moved.
        @{
            tag  = 'fast-nested-decoy'
            name = 'I6  a decoy interaction block nested one level down -> DENY'
            deny = $true
            json = '{"version":"0.2.0","modules":{"failure_capture":true},' +
                   '"junk":{"interaction":{"delegate":false}},' +
                   '"interaction":{"delegate":true},"repos":{"$comment":"nothing here"}}'
            why  = 'the real top-level switch is ON. A scanner without a depth guard finds the decoy false first, exits 0, and the gate never fires'
        }
    )

    foreach ($fc in $fastCases) {
        $rootFast = New-LwgRawRoot -Base $work -Name $fc.tag -Json $fc.json
        $r = Invoke-Gate -FakeRoot $rootFast -WorkDir $work -Tag $fc.tag `
                         -Payload (New-Payload -Tool 'Edit' -AgentId $null -AgentType '' -Extra $editPay)
        $v = if ($fc.deny) { Test-IsDeny $r } else { Test-IsAllow $r }
        Add-Result $fc.name $v.ok ("$($v.why)  --  $($fc.why)")
    }

    # -------------------------------------------------------------------
    # I7-I9. THE OPERATOR OVERRIDE - #11, AND THE FAIL-OPEN IT WOULD HAVE BEEN.
    #
    #    config.json is the SHIPPED DEFAULTS. Since 3 September 2026 the
    #    configuring commands write config.override.json under the state
    #    directory and Get-LwgConfig merges it over them, so the switch this
    #    gate reads can be ON in a file config.json knows nothing about.
    #
    #    THIS SCANNER READS config.json ALONE, and every rule in it is a rule
    #    for proving the switch OFF. Left as it was, it would have proved the
    #    switch off from a default the operator had overridden, exited 0, and
    #    left a gate that /lw-watchtower:doctor, the SessionStart banner and
    #    the status line all report as ARMED refusing nothing at all. That is
    #    strictly worse than the dirty working tree #11 is about, and it is the
    #    reason three earlier passes were right to refuse to move the write
    #    without moving every read.
    #
    #    It was MEASURED before it was fixed, at 4342980, in a throwaway plugin
    #    root whose lib/common.ps1 was patched to make Get-LwgConfig answer
    #    ARMED unconditionally: a main-thread Write exited 0 while the resolver
    #    said the gate was on. The evidence is on #11. I7 is that scenario
    #    without the patched resolver - the override file does the arming - and
    #    it goes RED at 4342980, where nothing in this file has ever opened the
    #    state directory.
    #
    #    I8 IS THE CASE THAT KEEPS I7 FROM BEING SATISFIED BY GIVING UP. An
    #    abstain-on-any-override rule would pass I7 and cost the fast exit to
    #    every operator who has ever set anything; an override that does not
    #    touch the switch must still take it. I9 is the mirror of I7 in the
    #    other direction: an override that turns the gate OFF over a config.json
    #    that arms it must ALLOW, which no rule reading only config.json can do.
    # -------------------------------------------------------------------
    $ovBase = '{"version":"0.2.0","modules":{"failure_capture":true},"interaction":{"delegate":false},"repos":{"$comment":"nothing here"}}'
    $ovOn   = '{"version":"0.2.0","modules":{"failure_capture":true},"interaction":{"delegate":true},"repos":{"$comment":"nothing here"}}'

    $overrideCases = @(
        @{
            tag  = 'ov-arms'
            name = 'I7  the OVERRIDE arms the gate while config.json says false -> DENY (#11)'
            deny = $true
            base = $ovBase
            ov   = '{"interaction":{"delegate":true}}'
            why  = 'the shape a fresh clone is in the moment an operator runs /lw-watchtower:delegate on. A scanner that reads config.json alone proves the switch off, exits 0, and the gate refuses nothing while everything that reports on it says ARMED'
        }
        @{
            tag  = 'ov-unrelated'
            name = 'I8  an override that does not touch the switch still takes the fast exit -> ALLOW'
            deny = $false
            base = $ovBase
            ov   = '{"modules":{"git_hygiene":false}}'
            why  = 'the guard against passing I7 by giving up: abstaining on ANY override would answer I7 correctly and charge every configured machine the slow path on every gated call'
        }
        @{
            tag  = 'ov-disarms'
            name = 'I9  the OVERRIDE turns the gate off over a config.json that arms it -> ALLOW'
            deny = $false
            base = $ovOn
            ov   = '{"interaction":{"delegate":false}}'
            why  = 'the mirror of I7. config.json is the defaults and the override wins; a scanner reading only the defaults would deny a call the operator has switched the gate off for'
        }
    )

    foreach ($oc in $overrideCases) {
        $rootOv = New-LwgRawRoot -Base $work -Name $oc.tag -Json $oc.base
        # Invoke-Gate points CLAUDE_PLUGIN_DATA at <FakeRoot>\data, which
        # New-LwgRawRoot has already created, so this is the very path
        # Get-LwgConfigOverridePath resolves for the child.
        [IO.File]::WriteAllText((Join-Path $rootOv 'data\config.override.json'), $oc.ov, [Text.UTF8Encoding]::new($false))
        $r = Invoke-Gate -FakeRoot $rootOv -WorkDir $work -Tag $oc.tag `
                         -Payload (New-Payload -Tool 'Edit' -AgentId $null -AgentType '' -Extra $editPay)
        $v = if ($oc.deny) { Test-IsDeny $r } else { Test-IsAllow $r }
        Add-Result $oc.name $v.ok ("$($v.why)  --  $($oc.why)")
    }

    # I10. AND THE CONTROL FOR THE WHOLE GROUP: the same three roots WITHOUT
    #      the override file must answer the way config.json alone says, so a
    #      reader of I7-I9 can tell the override did the work rather than the
    #      fixture. Without it, "I7 denies" is satisfied by any change that
    #      makes this gate deny more often.
    $rootCtl = New-LwgRawRoot -Base $work -Name 'ov-control-off' -Json $ovBase
    $rCtl = Invoke-Gate -FakeRoot $rootCtl -WorkDir $work -Tag 'ov-control-off' `
                        -Payload (New-Payload -Tool 'Edit' -AgentId $null -AgentType '' -Extra $editPay)
    $vCtl = Test-IsAllow $rCtl
    Add-Result 'I10 CONTROL: the same config.json with NO override file still ALLOWs' `
        $vCtl.ok `
        ("$($vCtl.why)  --  I7's config.json is byte-identical to this one. If this denied too, I7 would be measuring the fixture rather than the override.")

    # I11. THE OVERRIDE'S FILE NAME IS SPELT TWICE, AND THIS IS THE ONLY THING
    #      HOLDING THE TWO SPELLINGS TOGETHER.
    #
    #      lib/common.ps1 declares it once as $script:LwgConfigOverrideName and
    #      resolves it through Get-LwgConfigOverridePath, which every writer and
    #      every slow-path reader uses. The fast path in lib/gate_delegate.ps1
    #      cannot: it deliberately does not dot-source common.ps1, because
    #      loading it is most of the cost the fast path exists to avoid. So it
    #      carries the name as a literal.
    #
    #      A second copy of a rule that drifts from the first is a bug this
    #      repository has already shipped, and this one drifts SILENTLY IN THE
    #      WORST DIRECTION: rename the file in common.ps1 alone and the writers
    #      write one name while the gate looks for another, so the gate proves
    #      the switch off over an override that arms it - I7's defect, restored
    #      by a rename. I7 itself cannot catch that, because it writes the
    #      fixture at a path of its own and never asks the two files to agree.
    #
    #      Both sides are read out of the TREE rather than restated here, so
    #      this case has no third spelling to go stale.
    $i11Why  = ''
    $i11Ok   = $false
    try {
        $i11Common = [IO.File]::ReadAllText((Join-Path $Root 'lib\common.ps1'))
        $i11Gate   = [IO.File]::ReadAllText($GatePath)
        $i11M = [regex]::Match($i11Common, "(?m)^\s*\`$script:LwgConfigOverrideName\s*=\s*'([^']+)'")
        if (-not $i11M.Success) {
            $i11Why = 'lib\common.ps1 declares no $script:LwgConfigOverrideName literal, so the name the writers use could not be read at all and this case established nothing'
        } else {
            $i11Name = $i11M.Groups[1].Value
            $i11Ok = $i11Gate.Contains("'" + $i11Name + "'")
            if (-not $i11Ok) {
                $i11Why = ("lib\common.ps1 resolves the override as '{0}' and lib\gate_delegate.ps1 does not carry that literal anywhere, so the writers and the gate are looking at two different files" -f $i11Name)
            }
        }
    } catch { $i11Why = "the two files could not be read: $($_.Exception.Message)" }

    Add-Result 'I11 the fast path and Get-LwgConfigOverridePath spell the override file the same way' `
        $i11Ok `
        ("$i11Why  --  the fast path cannot call Get-LwgConfigOverridePath without loading common.ps1, which is the cost it exists to avoid, so it holds the name as a literal. Nothing but this case makes the two agree, and a rename that moved only one of them would put I7's defect back with no test failing.")

    # -------------------------------------------------------------------
    # J. THE MEMBER NAMES, AND WHAT A NON-BOOLEAN VALUE MEANS.
    #
    #    Section I asks whether the fast path reads the right VALUE. This
    #    section asks whether it finds the right MEMBER, which is the half it
    #    got wrong and shipped. The scanner compared member names ORDINALLY
    #    against raw, still-escaped text; the slow path it stands in for reads
    #    the same names through PowerShell property access over ConvertFrom-Json
    #    output, which is case-INSENSITIVE and is handed every \uXXXX escape
    #    already decoded. A scanner stricter than its consumer cannot merely be
    #    slow - it concludes "the member is absent" about a member that is
    #    there, and "absent" is this fast path's licence to exit 0.
    #
    #    J1-J6 are the six spellings that were ALLOWED while the gate reported
    #    itself live. Every one of them is a DENY case, and that is not an
    #    accident of authorship: per the note in this file's header, an
    #    allow-expecting case cannot catch a fast path that is wrong, because
    #    the fast path can only ever allow. A deny-expecting case is the only
    #    instrument there is.
    #
    #    J7 is the opposite polarity and is here so the abstain rule cannot be
    #    implemented as "crash on a backslash": an escaped member name that has
    #    nothing to do with this gate must still produce the right answer.
    #
    #    J7 CANNOT DO THAT ALONE, AND THAT IS WHY J7b IS NEXT TO IT. J7 asserts
    #    exit 0 and silence, which the gate also produces when the scan threw
    #    and the bare `catch { }` at the call site swallowed it - measured, with
    #    the abstain rule rewritten as a throw this whole file reported 93 of 93.
    #    J7b calls the scan in process, over J7's own config text, and requires
    #    it to RETURN $false. Read the two together: J7b says the rule abstained,
    #    J7 says the gate then answered correctly, and neither says the other.
    #
    #    J8 and J9 pin M5 - a value that is not a boolean. They are the two
    #    cases in this file whose answer CHANGED, so read them with the
    #    reasoning attached rather than as pins that were always there.
    #
    #    J10 is the only case in this suite that can tell which path answered,
    #    and it can do so only by the clock. See its own comment.
    # -------------------------------------------------------------------
    $jHead = '{"version":"0.3.0","modules":{"failure_capture":true},'
    $jTail = '"repos":{"$comment":"nothing here"}}'

    # cwd for the per-repo cases: the fabricated repository from section H,
    # whose slug is $slug. Nothing real is read.
    $jRepoPay = '{"session_id":"lwg-test-session","hook_event_name":"PreToolUse","tool_name":"Edit",' +
                '"cwd":"' + ($repoNamed -replace '\\', '/') + '",' +
                '"tool_input":{"file_path":"C:/nowhere/fixture.txt"}}'

    $jCases = @(
        @{
            tag  = 'name-cap-interaction'
            name = 'J1  a capitalised "Interaction" block holding delegate true -> DENY'
            deny = $true; repo = $false
            json = $jHead + '"Interaction":{"delegate":true},' + $jTail
            why  = 'ConvertFrom-Json plus PowerShell property access reads this as delegate = true, so the gate is armed. A scanner comparing names Ordinal finds no `interaction` member, calls it absent, applies the built-in default of off and exits 0 - the fail-open this section exists for, and the one the gate roster would keep reporting as a live gate'
        }
        @{
            tag  = 'name-cap-repos'
            name = 'J2  a capitalised "Repos" carrying a per-repo override that arms the gate -> DENY'
            deny = $true; repo = $true
            json = $jHead + '"interaction":{"delegate":false},' +
                   '"Repos":{"' + $slug + '":{"interaction":{"delegate":true}}}}'
            why  = 'the global is off and the override for this repo is on, so the gate must fire. A scanner that finds no `repos` member concludes nothing can override, reads the global false and exits 0'
        }
        @{
            tag  = 'name-escaped-interaction'
            name = 'J3  a global interaction block whose NAME is written \u0069nteraction -> DENY'
            deny = $true; repo = $false
            json = $jHead + '"\u0069nteraction":{"delegate":true},' + $jTail
            why  = 'the JSON engine decodes the escape and the slow path is handed a member called interaction holding true. A scanner matching raw text sees a name it does not recognise, reports the member absent, and exits 0'
        }
        @{
            tag  = 'name-escaped-interaction-repo'
            name = 'J4  a per-repo interaction block whose NAME is written \u0069nteraction -> DENY'
            deny = $true; repo = $true
            json = $jHead + '"interaction":{"delegate":false},' +
                   '"repos":{"' + $slug + '":{"\u0069nteraction":{"delegate":true}}}}'
            why  = 'the same escape one level down, where the fast path never parses members at all and a case-insensitive substring search for the word is the only guard. The escaped spelling contains no such word'
        }
        @{
            tag  = 'name-cap-delegate'
            name = 'J5  a mixed-case "DELEGATE" key set true -> DENY'
            deny = $true; repo = $false
            json = $jHead + '"interaction":{"DELEGATE":true},' + $jTail
            why  = 'property access reads DELEGATE, so the gate is armed. The pre-fix scanner did NOT allow this one - it failed to find `delegate` and fell through, which is the safe direction - so this case pins the abstention rather than catching the bug, and it goes red if a later change ever lets a missing key mean off'
        }
        @{
            tag  = 'name-caps-repos'
            name = 'J6  an all-caps "REPOS" carrying a per-repo override that arms the gate -> DENY'
            deny = $true; repo = $true
            json = $jHead + '"interaction":{"delegate":false},' +
                   '"REPOS":{"' + $slug + '":{"interaction":{"delegate":true}}}}'
            why  = 'the same hole as J2 in the spelling an operator is likelier to produce by accident'
        }
        @{
            tag  = 'name-escaped-irrelevant'
            name = 'J7  an escaped member name that decodes to something else entirely -> ALLOW'
            deny = $false; repo = $false
            json = '{"\u0076ersion":"0.3.0","modules":{"failure_capture":true},' +
                   '"interaction":{"delegate":false},' + $jTail
            why  = 'the switch really is off. The abstain-on-any-escape rule must make the fast path fall through here and the slow path must then answer correctly - "abstain" is not "throw", and a config with an escaped name that has nothing to do with this gate must not turn a decision into an error'
        }
        @{
            tag  = 'value-string-false'
            name = 'J8  delegate is the STRING "false" -> ALLOW (M5: not a boolean, so not a setting)'
            deny = $false; repo = $false
            json = $jHead + '"interaction":{"delegate":"false"},' + $jTail
            # THE ANSWER TO THIS CASE CHANGED, and the old one was a near
            # one-way lockout rather than a defensible reading. [bool] on a
            # non-empty string is $true in PowerShell, so the text an operator
            # writes when they mean OFF armed the only gate this plugin ships -
            # and an armed gate refuses the Bash call that /lw-watchtower:delegate off
            # runs, so the way out was a hand edit of config.json from outside
            # the session. Test-LwgFlag now ignores any value that is not a real
            # boolean and logs a ConfigInvalidFlag event, so this resolves to the
            # registry default, which is off.
            why  = 'a value that is not a boolean is not a switch setting. It must resolve to the default - off - rather than to $true by coercion, and the operator who wrote it must not be locked out of the session by it'
        }
        @{
            tag  = 'value-string-true'
            name = 'J9  delegate is the STRING "true" -> ALLOW (M5: not a boolean, so not a setting)'
            deny = $false; repo = $false
            json = $jHead + '"interaction":{"delegate":"true"},' + $jTail
            # The mirror of J8 and the uncomfortable half of the same rule: an
            # operator who wrote this MEANT to arm the gate and does not get it.
            # That is accepted deliberately. One rule - only a boolean is a
            # setting - is worth more than a rule that coerces the spelling that
            # happens to read as intended, because the coercion that grants this
            # one is exactly the coercion that produced the J8 lockout. It is not
            # silent: the same ConfigInvalidFlag event is written.
            why  = 'the same rule as J8, applied where it costs the operator something. A string is not a boolean whichever word is inside it'
        }
    )

    foreach ($jc in $jCases) {
        $rootJ = New-LwgRawRoot -Base $work -Name $jc.tag -Json $jc.json
        $payJ  = if ($jc.repo) { $jRepoPay } else {
            (New-Payload -Tool 'Edit' -AgentId $null -AgentType '' -Extra $editPay)
        }
        $r = Invoke-Gate -FakeRoot $rootJ -WorkDir $work -Tag $jc.tag -Payload $payJ
        $v = if ($jc.deny) { Test-IsDeny $r } else { Test-IsAllow $r }
        Add-Result $jc.name $v.ok ("$($v.why)  --  $($jc.why)")
    }

    # J7b THE CASE THAT CAN ACTUALLY SEE THE ABSTAIN RULE, because J7 above
    #     cannot. J7 is a black-box ALLOW case and Test-IsAllow is exit 0 and
    #     silence - which is what the fast path emits when it proves the switch
    #     off, what the slow path emits when IT decides the switch is off, and
    #     what lib\gate_delegate.ps1's
    #
    #         try { if (Test-LwgFastDelegateOff) { exit 0 } } catch { }
    #
    #     leaves behind when the scan THREW and was swallowed. Three states, one
    #     observable. So J7 cannot tell "abstain" from "throw", which is the one
    #     thing the note at the head of this section says it is here for.
    #
    #     MEASURED ON THIS TREE, 3 September 2026. With the escaped-name rule in
    #     Get-LwgFastJsonMembers rewritten from `return $null` to
    #     `throw 'MUTANT A: abstain implemented as a hard throw'` - the exact
    #     mistake J7's note names - this suite reported
    #
    #         RESULT: 93 of 93 case(s) passed in 74917 ms
    #         EXIT: 0
    #
    #     and J7 was one of the 93. Not one case in the file moved: J3 and J4
    #     carry escaped names and expect DENY, and the slow path still denies
    #     correctly. The swallow at the call site is deliberate and correct -
    #     the consequence of swallowing is that the slow path runs and answers -
    #     and that is precisely why nothing observable from OUTSIDE the gate
    #     process can be the instrument for this property.
    #
    #     SO THE SCANNER IS CALLED IN PROCESS. The two functions are lifted out
    #     of lib\gate_delegate.ps1 by AST - FunctionDefinitionAst, not a regex,
    #     and NOT a dot-source, because dot-sourcing that file runs its
    #     top-level fast path and would exit this process - and invoked over the
    #     SAME config text J7 hands the gate, read out of the table above by tag
    #     so the two cases cannot drift apart. J7's config spells its `version`
    #     member with the `v` written as a \u escape, which makes it a name this
    #     scanner cannot decode, so the scan must ABSTAIN: the contract is that
    #     Test-LwgFastDelegateOff RETURNS $false and hands the question to the
    #     slow path. A throw is invisible from outside; from in here it is a red
    #     line.
    #
    #     WHAT THIS DOES NOT ESTABLISH, said rather than left to be assumed. It
    #     is a white-box case over two functions, not a run of the gate. It says
    #     the abstain rule abstains, and it says nothing about what the gate as
    #     a whole then answers - J7 next to it is what says that, over the same
    #     config, through a real child process. Neither is the other, and the
    #     pair is the coverage. It also does not make J10 redundant: J10 is
    #     still the only case here that can tell which path answered a real
    #     invocation, and this one never invokes the gate at all.
    #
    #     AND IT IS NOT THE STRUCTURAL FIX. The tri-state return #135 proposes -
    #     the fast path recording its own abstentions once the logger is up -
    #     would let J7 assert this from the outside and would make J10's clock
    #     unnecessary. That is a change to shipped behaviour and is not made
    #     here. This case is what the suite can have without one.
    #     TWO ARMS, AND THE FIRST ONE IS NOT CEREMONY. `$false` is what this
    #     scanner returns for every doubt it has, so "it returned $false" is on
    #     its own the same bare negative the rest of this batch is about: a
    #     harness that lifted the scanner wrongly, or a scanner that had been
    #     gutted to `return $false`, satisfies it. So the case first runs a
    #     config the scan MUST prove off and requires `$true`, and only then
    #     asks J7's config for the abstention. A failure in the first arm says
    #     "the harness could not look", which is a different sentence from "the
    #     rule threw" and must not be confused with it.
    #
    #     THAT ARM EARNED ITS PLACE IMMEDIATELY, TWICE. The first version of
    #     this case lifted the two functions and not the script-level
    #     $LwgFastScanChars they scan with, so every call died on
    #     `IndexOfAny ... Value cannot be null`; the second lifted it but ran the
    #     text through `& [scriptblock]::Create(...)`, where a bare assignment
    #     lands in the block's own child scope and `$script:` inside the function
    #     still resolves to THIS file's scope, so it was null again. Both times,
    #     with only the abstain arm, the case went red under the mutant for a
    #     reason that had nothing to do with the mutant. A red that means the
    #     wrong thing is the same defect as a green that means nothing.
    #
    #     SO THE LIFTED TEXT RUNS IN A FRESH RUNSPACE, via [powershell]::Create()
    #     and AddScript, where there is no enclosing script file and `$script:`
    #     resolves to that runspace's own top level - which is where AddScript's
    #     top-level assignment lands. That is also why the lifted text is used
    #     VERBATIM: rewriting `$LwgFastScanChars =` to `$script:...` on the way
    #     past would work today and would be a copy of the gate's source with an
    #     edit in it, which is the thing this case exists to avoid. The runspace
    #     is disposed in the finally, and the environment variables are restored
    #     there too, because they are process-wide and the runspace reads them
    #     from the same process.
    $j7bJson = ''
    foreach ($jc in $jCases) { if ($jc.tag -eq 'name-escaped-irrelevant') { $j7bJson = [string]$jc.json } }
    $j7bOk   = $false
    $j7bWhy  = 'the J7 row could not be found in $jCases by its tag, so this case had nothing to run against - it did NOT pass and it did NOT establish anything'
    if ($j7bJson -ne '') {
        # The abstain specimen is J7's own text, read out of the table above so
        # the two cases cannot drift. The control is the plainest provable-off
        # config there is: no escape anywhere, so the rule under test is not
        # reached and the scan must conclude OFF.
        $j7bRootAbstain = New-LwgRawRoot -Base $work -Name 'j7b-abstain' -Json $j7bJson
        $j7bRootOff     = New-LwgRawRoot -Base $work -Name 'j7b-control' -Json (
            $jHead + '"interaction":{"delegate":false},' + $jTail)
        $j7bPrevRoot = $env:CLAUDE_PLUGIN_ROOT
        $j7bPrevData = $env:CLAUDE_PLUGIN_DATA
        # WHICH ARM WAS RUNNING WHEN SOMETHING THREW. Without this the one catch
        # below reports every throw as "the scan THREW instead of abstaining",
        # including a throw in the control arm - which is the misattribution this
        # case's own comment argues against, committed by the case itself.
        $j7bArm = 'harness'
        try {
            $j7bAst  = [System.Management.Automation.Language.Parser]::ParseFile($GatePath, [ref]$null, [ref]$null)
            $j7bText = ''

            # The scan characters are script-level state in the gate, not a
            # parameter, so the two functions are useless without them. Lifted
            # by AST like the functions rather than copied here: a literal
            # written out in this file would be a second statement of which
            # characters JSON structure can hide behind, and the two could
            # disagree without anything noticing.
            $j7bVars = @($j7bAst.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.AssignmentStatementAst]
            }, $true) | Where-Object { $_.Left.Extent.Text -eq '$LwgFastScanChars' })
            if ($j7bVars.Count -ne 1) {
                throw ("lib\gate_delegate.ps1 holds {0} assignment(s) to `$LwgFastScanChars, expected exactly 1 - the scanner cannot be run without it" -f $j7bVars.Count)
            }
            $j7bText += $j7bVars[0].Extent.Text + [Environment]::NewLine

            # Test-LwgFastDelegateOffText was split out of Test-LwgFastDelegateOff
            # on 3 September 2026 so the same rules could be applied to the
            # operator override (#11). It is lifted WHEN PRESENT rather than
            # required, so this case still runs - and still says something -
            # against a tree from before that split. The two names either side
            # of it are required, because without them there is nothing to call.
            foreach ($fnName in @('Get-LwgFastJsonMembers', 'Test-LwgFastDelegateOffText', 'Test-LwgFastDelegateOff')) {
                $j7bDefs = @($j7bAst.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.FunctionDefinitionAst]
                }, $true) | Where-Object { $_.Name -eq $fnName })
                if ($j7bDefs.Count -eq 0 -and $fnName -eq 'Test-LwgFastDelegateOffText') { continue }
                if ($j7bDefs.Count -ne 1) {
                    throw ("lib\gate_delegate.ps1 holds {0} definition(s) of {1}, expected exactly 1 - the scanner this case is about could not be located" -f $j7bDefs.Count, $fnName)
                }
                $j7bText += $j7bDefs[0].Extent.Text + [Environment]::NewLine
            }
            $j7bScript = $j7bText + [Environment]::NewLine + 'Test-LwgFastDelegateOff'

            # One call, run in a fresh runspace over whichever root the
            # environment names. Same env-var dance Invoke-Gate does for the
            # child process. A non-terminating error inside is treated as a
            # throw: HadErrors is checked before the return value is read, so a
            # scan that wrote to the error stream and returned something anyway
            # cannot be mistaken for a clean answer.
            $j7bCall = {
                param([string]$Root, [string]$Script)
                $env:CLAUDE_PLUGIN_ROOT = $Root
                $env:CLAUDE_PLUGIN_DATA = Join-Path $Root 'data'
                $sh = [powershell]::Create()
                try {
                    [void]$sh.AddScript($Script)
                    $out = $sh.Invoke()
                    if ($sh.HadErrors) {
                        throw (($sh.Streams.Error | ForEach-Object { $_.ToString() }) -join ' | ')
                    }
                    if (@($out).Count -ne 1) { throw "the scan produced $(@($out).Count) output object(s), expected exactly 1" }
                    return @($out)[0]
                } finally { $sh.Dispose() }
            }

            # Arm 1, the control: the harness works and the scan can still say
            # yes. No escape anywhere in that config, so the rule under test is
            # never reached and the only answer is $true.
            $j7bArm = 'control'
            $j7bCtl = & $j7bCall $j7bRootOff $j7bScript
            if (-not ($j7bCtl -is [bool] -and $j7bCtl -eq $true)) {
                $j7bWhy = ("THE HARNESS COULD NOT LOOK, which is not the same as the rule being wrong: over a config with no escape in it at all the scan returned [{0}] where it must return the boolean True. Read this as 'this case established nothing', and fix it before reading anything into the arm below." -f $j7bCtl)
            } else {
                # Arm 2, the property: an escaped member name must abstain, and
                # must abstain by RETURNING.
                $j7bArm = 'abstain'
                $j7bRet = & $j7bCall $j7bRootAbstain $j7bScript
                $j7bOk  = ($j7bRet -is [bool] -and $j7bRet -eq $false)
                $j7bWhy = if ($j7bOk) { '' } else {
                    "over J7's config the scan returned [$j7bRet] of type [$(if ($null -eq $j7bRet) { 'null' } else { $j7bRet.GetType().Name })] where it must return the boolean False"
                }
            }
        } catch {
            # READ OUT BEFORE THE SWITCH, and that is not style. `switch` rebinds
            # $_ to its own input inside every branch, so $_.Exception.Message
            # written in there is the message of a STRING and comes back empty -
            # measured, on the first run of this catch: the mutant threw
            # 'MUTANT A: abstain implemented as a hard throw' and the case
            # reported "the scan THREW instead of abstaining:" with nothing
            # after the colon. A red with the reason deleted out of it is most
            # of the way back to a red that means nothing.
            $j7bErr = $_.Exception.Message
            $j7bWhy = switch ($j7bArm) {
                'abstain' { "the scan THREW instead of abstaining: $j7bErr" }
                'control' { "THE HARNESS COULD NOT LOOK: the control arm threw before the rule under test was ever reached, so this case established NOTHING about the abstain rule - $j7bErr" }
                default   { "THE HARNESS COULD NOT LOOK: the scanner could not be lifted out of lib\gate_delegate.ps1 at all, so this case established NOTHING - $j7bErr" }
            }
        } finally {
            $env:CLAUDE_PLUGIN_ROOT = $j7bPrevRoot
            $env:CLAUDE_PLUGIN_DATA = $j7bPrevData
        }
    }
    Add-Result 'J7b the abstain rule abstains rather than throws, over J7''s own config, called in process' `
        $j7bOk `
        ("$j7bWhy  --  " +
         'abstain is not throw. An escaped member name is a name this scanner cannot decode, so it must return $false ' +
         'and let the slow path answer, and it must do that by RETURNING. A throw is caught by the bare `catch { }` at ' +
         'the call site, the slow path then answers correctly, and the gate exits 0 in silence - which is byte-identical ' +
         'to an abstention, so J7 above stays green over it. Measured: with the rule rewritten as a throw this suite ' +
         'reported 93 of 93. This case is the only thing in the file that can see the difference.')

    # J10. THE ONLY CASE HERE THAT CAN SEE WHICH PATH ANSWERED, and it sees it
    #      by the clock, because the design leaves no other window: the fast
    #      path's one affirmative outcome is byte-identical to the slow path's
    #      outcome for an off switch. Two configs are run that differ in ONE
    #      way - the second's repos comment contains the word "interaction",
    #      which forces the fast path to abstain and the slow path to decide -
    #      and the fast one must come back quicker.
    #
    #      MINIMUMS OF NINE INTERLEAVED RUNS, not means: a mean on a shared
    #      machine measures the machine, and the minimum is the statistic least
    #      disturbed by whatever else is running. It was five until the margin
    #      below landed; nine costs eight more process spawns, which is a few
    #      seconds on a suite that already takes the better part of a minute,
    #      and it buys a floor estimate that is less likely to be one unlucky
    #      sample on either leg. The gap this is asserting is
    #      a few hundred milliseconds against a run that already costs several
    #      hundred, so it is not a tight margin - but it IS wall clock, and if
    #      this case ever fails alone, with both legs still allowing, read it as
    #      "measure it by hand" before reading it as a regression.
    #
    #      A MARGIN, NOT A STRICT INEQUALITY - AND READ THE DIRECTION BEFORE
    #      READING THIS AS A FLAKINESS FIX, BECAUSE IT IS NOT ONE. The old form
    #      was `$j10FastMs -lt $j10SlowMs`, which PASSED on a one-millisecond
    #      difference. One millisecond is no evidence of a skipped JSON parse;
    #      it is the difference two process spawns produce on their own. What
    #      the margin buys is that half: the case now asserts a gap large
    #      enough to be the work the fast path skipped.
    #
    #      IT IS STRICTER, SO IT FAILS MORE OFTEN, NOT LESS. Under `-lt` this
    #      case went red when the gap was <= 0; it now goes red when the gap is
    #      under the margin below. The tie that motivated the change still fails
    #      - and the blast radius is unchanged: a red here still takes
    #      tests\doc_claims.ps1 down with it, because that file aborts on any
    #      sibling suite's nonzero exit and then establishes nothing about the
    #      documentation. Nothing here narrows that. What changed is that the
    #      detail line now prints both minima, the gap and the number required,
    #      so a red says "measure this" with the measurement already in it
    #      instead of leaving a reader to infer whether 291 and 291 were a
    #      regression or a busy host.
    #
    #      WHERE THE MARGIN COMES FROM, AND IT IS NOW A FLOOR RATHER THAN
    #      HEADROOM (#227). It was 50 ms, and the argument for 50 was "under a
    #      third of the smallest gap anyone had observed" - which is a fraction
    #      of the SIGNAL and says nothing about the noise the signal has to
    #      clear. The floor is the thing a margin has to be above, so it was
    #      measured directly rather than inferred: both legs pointed at the SAME
    #      provable-off config - nothing for the fast path to be faster at, so
    #      the true gap is zero - and the case run whole, three times, at
    #      c39e782, on the machine described below.
    #
    #          null gap, identical legs, best of 9 :  -20 ms,   7 ms,  11 ms
    #          real gap, this case,      best of 9 :  207 ms, 205 ms, 216 ms
    #
    #      THE 211-334 MS FLOOR THIS COMMENT USED TO CARRY WAS MEASURED AT FIVE
    #      SAMPLES PER LEG AND DOES NOT DESCRIBE THE CASE AS IT NOW RUNS. It was
    #      correct when it was taken, and it is the reason the sample count was
    #      raised to nine; quoting it against nine samples describes a case that
    #      no longer exists, which is how the file came to hold a margin its own
    #      comment said could not work. A minimum over nine interleaved spawns is
    #      what collapses that noise, and the third run above is the evidence:
    #      its per-leg spreads were 313 ms and 637 ms - a badly disturbed host,
    #      six sibling worktrees building throughout - and the gap still came
    #      back 216. THE MINIMA ARE STABLE WHEN THE SAMPLES ARE NOT, which is
    #      the whole reason this case reads minima and not means.
    #
    #      So the margin is 100 ms: five times the largest null gap measured, and
    #      under half the smallest real gap measured. Both halves of that are
    #      load-bearing. Below the floor the case cannot tell a working fast path
    #      from a stopped one; far above it, every extra millisecond of margin is
    #      bought out of the headroom that keeps a busy runner from going red on
    #      a fast path that is working perfectly.
    #
    #      WHAT IT STILL DOES NOT DO, WHICH IS THE HALF #227 WAS RIGHT ABOUT. It
    #      is a THRESHOLD, not a performance number: a fast path whose saving
    #      fell from 205 ms to 120 would pass this and nothing here would say a
    #      word. What it can see is the fast path stopping ENTIRELY - the thing
    #      the header says would otherwise "not be caught by this file at all" -
    #      and it can now say so with a margin that noise has been measured
    #      unable to reach.
    #
    #      AND IT HAS NOW BEEN MEASURED ON A CI RUNNER ONCE, which is a sentence
    #      this comment could not carry until the line below started printing.
    #      windows-latest, run 33834555561 - the run that landed this change:
    #      provable-off 280 ms (spread 29), forced-through 608 ms (spread 31),
    #      gap 328 ms. The hosted runner was QUIETER than the development
    #      machine, spreads of about 30 ms against 300+, and the gap came back
    #      larger rather than smaller, so the margin has better than three times
    #      its headroom on the only sample that machine has ever given. ONE
    #      SAMPLE IS ONE SAMPLE: if this fails on windows-latest with both legs
    #      still allowing, re-measure both legs there before reading it as a
    #      regression.
    #
    #      THE NUMBERS ARE PRINTED ON EVERY RUN, NOT ONLY WHEN THE CASE FAILS,
    #      and that is the other half of the fix. Everything above is prose
    #      written once, about the one case in this file whose inputs are wall
    #      clock and machine-specific - the exact shape that goes stale without
    #      anyone noticing, as the 211-334 did. A reader on another machine
    #      cannot re-derive the floor from a comment; they can from the line the
    #      run prints. It is one line, and it is deliberately the only per-case
    #      line a green run of this suite emits.
    $j10Fast = New-LwgRawRoot -Base $work -Name 'j10-fast' -Json (
        $jHead + '"interaction":{"delegate":false},' +
        '"repos":{"$comment":"Per-repo overrides keyed by the owner/name slug of the origin remote."}}')
    $j10Slow = New-LwgRawRoot -Base $work -Name 'j10-slow' -Json (
        $jHead + '"interaction":{"delegate":false},' +
        '"repos":{"$comment":"This comment mentions interaction, which is enough to make the fast path abstain."}}')

    $j10FastMs  = [int]::MaxValue
    $j10SlowMs  = [int]::MaxValue
    # Every sample, not only the running minimum, because the SPREAD is what
    # tells a reader whether the host was quiet - and the spread is the number
    # that decides whether a red is worth investigating or worth re-running.
    $j10FastAll = @()
    $j10SlowAll = @()
    $j10Bad     = ''
    for ($i = 0; $i -lt 9; $i++) {
        foreach ($leg in @(@{ n = 'fast'; root = $j10Fast }, @{ n = 'slow'; root = $j10Slow })) {
            $clock = [Diagnostics.Stopwatch]::StartNew()
            $rj = Invoke-Gate -FakeRoot $leg.root -WorkDir $work -Tag ("j10-$($leg.n)-$i") `
                              -Payload (New-Payload -Tool 'Edit' -AgentId $null -AgentType '' -Extra $editPay)
            $clock.Stop()
            $ms = [int]$clock.Elapsed.TotalMilliseconds
            $vj = Test-IsAllow $rj
            if (-not $vj.ok -and $j10Bad -eq '') { $j10Bad = "the $($leg.n) leg did not allow: $($vj.why)" }
            if ($leg.n -eq 'fast') { $j10FastAll += $ms; if ($ms -lt $j10FastMs) { $j10FastMs = $ms } }
            else                   { $j10SlowAll += $ms; if ($ms -lt $j10SlowMs) { $j10SlowMs = $ms } }
        }
    }
    # 100 ms, and the two numbers it sits between are in the comment above with
    # the runs they came from. Changing it without re-measuring the null is how
    # it came to be 50 against a floor of 211.
    $j10MarginMs   = 100
    $j10Gap        = $j10SlowMs - $j10FastMs
    $j10FastSpread = ($j10FastAll | Measure-Object -Maximum).Maximum - $j10FastMs
    $j10SlowSpread = ($j10SlowAll | Measure-Object -Maximum).Maximum - $j10SlowMs
    # PRINTED WHETHER OR NOT THE CASE PASSES. See the comment above: this is the
    # only case here whose inputs are wall clock, the prose describing them went
    # stale once already, and a number in the run is the only thing a reader on
    # another machine can re-derive the floor from.
    Write-Output ("  J10 timing  provable-off {0} ms (spread {1}), forced-through {2} ms (spread {3}), gap {4} ms, required >= {5} ms" -f `
        $j10FastMs, $j10FastSpread, $j10SlowMs, $j10SlowSpread, $j10Gap, $j10MarginMs)
    Add-Result 'J10 an off switch the fast path can prove still exits 0, and quicker than one it cannot' `
        ($j10Bad -eq '' -and $j10Gap -ge $j10MarginMs) `
        ("$j10Bad  --  best of 9 interleaved: provable-off $j10FastMs ms (spread $j10FastSpread over its 9 samples), forced-through $j10SlowMs ms (spread $j10SlowSpread), gap $j10Gap ms, required >= $j10MarginMs ms. The margin is five times the largest gap measured between two IDENTICAL legs at this sample count (-20, 7 and 11 ms over three whole runs at c39e782), so noise has been measured unable to reach it; the real gap measured 207, 205 and 216 ms over the same three runs. READ THE SPREADS BEFORE READING THIS AS A REGRESSION: a spread of a few hundred milliseconds says the host was disturbed, and the minimum is the statistic least disturbed by that - a gap that collapsed while both spreads stayed small is the fast path no longer running, which is the one thing this case exists to see, and the only other thing that would notice is the cost going back to what docs/modules.md says it used to be. The one measurement from a CI runner - windows-latest, run 33834555561 - read 280 and 608 ms with spreads of 29 and 31, a gap of 328: quieter than the development machine, not noisier. Measure both legs by hand there before reading a red as a regression")

    # -------------------------------------------------------------------
    # K. THE REPORTER AND THE READER, ON THE SAME CONFIG.
    #
    #    Sections I and J ask what the GATE does with a value. This section
    #    asks whether /lw-watchtower:delegate says the same thing about it, and it
    #    exists because for a while it did not.
    #
    #    The boolean-only rule - only a real boolean is a setting, anything
    #    else is ignored at the scope holding it - landed in Test-LwgFlag
    #    (lib\common.ps1) and NOT in bin\lwg-toggle.ps1, whose
    #    Get-LwgPrefGlobal, Get-LwgPrefRepo and Test-LwgFlagOn still did a bare
    #    [bool]. [bool] on a non-empty string is $true in PowerShell, so
    #    `"delegate": "false"` made the command print
    #
    #        effective here : ON
    #
    #    for a config the gate read as off. A reporter that disagrees with the
    #    reader is the founding defect this plugin exists to catch, and fixing
    #    one half of a pair is how it got in here.
    #
    #    EVERY CASE IS A THREE-WAY ASSERTION: the reader's answer, the
    #    reporter's answer, and the answer the rule requires. Comparing only
    #    the two halves to each other would go green the day they agree on
    #    something wrong.
    #
    #    THE READER IS CALLED IN THIS PROCESS AND THE REPORTER IN A CHILD ONE,
    #    which is not laziness about symmetry. The reader half is exactly the
    #    call the gate makes - Test-LwgModule over a Get-LwgConfig of that
    #    file - and sections A-J have already established what the gate does
    #    with it end to end. What has never been run is the COMMAND, and it has
    #    to be a real child process because it resolves its own plugin root
    #    from its own script path.
    #
    #    WHICH OF THESE CAN GO RED, stated because a case that cannot is
    #    documentation and this file's header says so about section I. K1, K2,
    #    K5, K6 and K7 were all confirmed RED against the pre-fix
    #    bin\lwg-toggle.ps1. K3, K4 and K8 CANNOT go red against it: the
    #    coercion they exercise happened to land on the right answer, and they
    #    are here to pin that the fix did not move an answer that was already
    #    correct.
    # -------------------------------------------------------------------
    $kHead = '{"version":"0.3.0","modules":{"failure_capture":true},'
    $kTail = '"repos":{"$comment":"nothing here"}}'

    $kCases = @(
        @{
            tag = 'rep-string-false'; name = 'K1  global delegate is the STRING "false" -> both read OFF'
            want = 'OFF'; repo = $false; red = $true
            json = $kHead + '"interaction":{"delegate":"false"},' + $kTail
            why  = 'the value an operator writes when they mean off. The gate ignores it and resolves to the registry default, off; the command printed ON, so the operator was told the gate was armed by the line they wrote to disarm it - and an armed gate refuses the Bash call that turns it off again'
        }
        @{
            tag = 'rep-string-true'; name = 'K2  global delegate is the STRING "true" -> both read OFF'
            want = 'OFF'; repo = $false; red = $true
            json = $kHead + '"interaction":{"delegate":"true"},' + $kTail
            why  = 'the uncomfortable half of the same rule, and the one that must not be special-cased: coercing the spelling that reads as intended is exactly the coercion that produced K1'
        }
        @{
            tag = 'rep-real-true'; name = 'K3  global delegate is a real true -> both read ON'
            want = 'ON'; repo = $false; red = $false
            why  = 'CANNOT GO RED against the pre-fix command - [bool] $true is $true. It pins that tightening the rule did not stop a real boolean from working, which is the regression a boolean-only rule is most likely to introduce'
            json = $kHead + '"interaction":{"delegate":true},' + $kTail
        }
        @{
            tag = 'rep-real-false'; name = 'K4  global delegate is a real false -> both read OFF'
            want = 'OFF'; repo = $false; red = $false
            why  = 'CANNOT GO RED, for the mirror reason. The shipped state, pinned at the reporter as well as at the reader'
            json = $kHead + '"interaction":{"delegate":false},' + $kTail
        }
        @{
            tag = 'rep-number'; name = 'K5  global delegate is the NUMBER 1 -> both read OFF'
            want = 'OFF'; repo = $false; red = $true
            json = $kHead + '"interaction":{"delegate":1},' + $kTail
            why  = 'a number is not a boolean either, and 1 is the spelling most likely to be believed. [bool]1 is $true, so the command reported an armed gate for a config the gate reads as off'
        }
        @{
            tag = 'rep-repo-string'; name = 'K6  a per-repo override that is the STRING "false" over a global false -> both read OFF'
            want = 'OFF'; repo = $true; red = $true
            json = $kHead + '"interaction":{"delegate":false},' +
                   '"repos":{"' + $slug + '":{"interaction":{"delegate":"false"}}}}'
            why  = 'the override is not a boolean, so it is not an override: resolution continues as if that scope said nothing and the global false stands. [bool] on the string turned an operator writing "off" into an armed gate in the report'
        }
        @{
            tag = 'rep-repo-garbage-over-true'; name = 'K7  a garbage per-repo override does NOT disarm a global true -> both read ON'
            want = 'ON'; repo = $true; red = $false
            json = $kHead + '"interaction":{"delegate":true},' +
                   '"repos":{"' + $slug + '":{"interaction":{"delegate":"nonsense"}}}}'
            why  = 'CANNOT GO RED - [bool] on a non-empty string was $true, which is the same answer by the wrong route. It pins the direction of "ignored": an invalid value is not a vote for false, so a garbage override must leave a gate the operator armed standing rather than silently disarming it'
        }
    )

    foreach ($kc in $kCases) {
        $rootK = New-LwgToggleRoot -Base $work -Name $kc.tag -Json $kc.json
        $cwdK  = if ($kc.repo) { $repoNamed } else { $work }
        $repoK = if ($kc.repo) { $slug } else { '' }

        # The reader: the exact resolution the gate performs.
        $readOn = Test-LwgModule -Name 'delegate_gate' `
                                 -Config (Get-LwgConfig -Path (Join-Path $rootK 'config.json')) -Repo $repoK
        $read   = if ($readOn) { 'ON' } else { 'OFF' }

        # The reporter: the command, run for real.
        $rep = Get-ToggleEffective (Invoke-Toggle -FakeRoot $rootK -WorkDir $work -Tag $kc.tag -Cwd $cwdK)

        Add-Result $kc.name ($read -eq $kc.want -and $rep -eq $kc.want) `
            ("gate reads '$read', /lw-watchtower:delegate reports '$rep', the rule requires '$($kc.want)'  --  $($kc.why)")
    }

    # K8. THE REPORT MUST NAME THE VALUE IT IGNORED. Resolving a broken config
    #     correctly and saying nothing about it leaves the operator with a file
    #     that plainly states a preference and a plugin that plainly ignores
    #     it - which is the same silence as getting the answer wrong, just
    #     harder to notice. Asserted on K1's fixture, whose config really does
    #     hold a string.
    $rootK8 = New-LwgToggleRoot -Base $work -Name 'rep-names-it' -Json (
        $kHead + '"interaction":{"delegate":"false"},' + $kTail)
    $outK8 = (Invoke-Toggle -FakeRoot $rootK8 -WorkDir $work -Tag 'rep-names-it' -Cwd $work).out
    Add-Result 'K8  the report NAMES a non-boolean it ignored, at the scope holding it' `
        ($outK8 -match '(?m)NOT A BOOLEAN at the global scope' -and $outK8 -match 'IGNORED') `
        ("the report never says the value was ignored. It was:`n$outK8")

    # -------------------------------------------------------------------
    # M. THE STEP BEFORE THE GATE: WOULD THE CLI HAVE RUN IT AT ALL?
    #
    #    Every case above this one starts by piping a payload into
    #    lib/gate_delegate.ps1. That models a hook the CLI decided to invoke,
    #    and it is the right model for asking what the gate's RULE does. It is
    #    incapable of asking whether the CLI would have invoked it, and the gate
    #    is tool-blind on purpose - it refuses any main-thread call whatever
    #    tool_name says - so a tool absent from the matcher passes every case
    #    above by being handed a hook run the CLI would never have performed.
    #
    #    THAT IS NOT HYPOTHETICAL. hooks/hooks.json registered the gate on
    #    Edit|Write|NotebookEdit|Bash and omitted PowerShell, on a plugin that
    #    supports Windows and only Windows, where the CLI offers both shells.
    #    With interaction.delegate ON, the gate roster printed
    #
    #        1 gate(s) LIVE: delegate_gate - it can refuse a tool call right now
    #
    #    and the main thread could run any command it wanted through the other
    #    shell. Sections A-L were 80 of 80 green throughout. Section A's
    #    registration case is the one that goes red on the omission itself; this
    #    section is the one that goes red on the CONSEQUENCE, which is the thing
    #    the operator actually has.
    #
    #    THE TWO EDGES, AND WHY THEY ARE ASSERTED UNDER DIFFERENT READINGS OF
    #    THE SAME STRING. Widening a PreToolUse matcher widens what can be
    #    refused, so the answer to a hole is not "match everything": the gate
    #    refuses the MAIN THREAD, and the exit it prints - dispatch a subagent
    #    with the Agent tool - runs through a tool call of its own. A matcher
    #    that selected Agent would refuse the dispatch, and /lw-watchtower:delegate
    #    off runs through Bash, which is refused on purpose and has no
    #    exemption. The session would have no way out at all.
    #
    #    So M1 asks "is PowerShell selected?" under the STRICTEST reading of
    #    matcher semantics, and M2-M3 ask "is this selected?" under the LOOSEST.
    #    Neither reading is known to be the CLI's - see Test-LwgMatcherSelects -
    #    and each case takes the one under which a pass is sound whichever rule
    #    the CLI really applies.
    #
    #    IT RUNS BEFORE SECTION L DESPITE COMING AFTER IT IN THE ALPHABET.
    #    Section L asserts that the operator's live event log is byte-unchanged
    #    BY THIS RUN, so it has to be the last thing that happens or it stops
    #    covering whatever was appended after it. A new section therefore goes
    #    in front of it, and the letters stop tracking the order at exactly this
    #    point. Renaming L instead would break the several documents that name
    #    it, for nothing.
    # -------------------------------------------------------------------
    if ($null -eq $script:GateMatcher) {
        # An abort, never a skip. Section A did not produce a matcher, so
        # nothing below can be established either way, and a quietly smaller
        # denominator is the failure this file's header spends a section on.
        throw 'section A read no matcher out of hooks.json, so section M cannot ask what the CLI would select. Nothing about tool coverage was established by this run'
    }

    # M1. The hole itself, end to end. The gate is ARMED, the caller is the main
    #     thread, the tool is the other shell on the only OS this plugin
    #     supports, and the CLI's selection step is in the path.
    $m1 = Invoke-GateAsCli -FakeRoot $rootOn -WorkDir $work -Tag 'cli-ps-main' `
                           -Tool 'PowerShell' -Matcher $script:GateMatcher `
                           -Payload (New-Payload -Tool 'PowerShell' -AgentId $null -AgentType '' `
                                                 -Extra '"tool_input":{"command":"lwg-noop-fixture -DryRun"}')
    if (-not $m1.invoked) {
        $m1ok  = $false
        $m1why = ("hooks.json's matcher '$($script:GateMatcher)' does not select PowerShell, so the CLI " +
                  'never invokes the gate and the call runs unrefused. The gate script itself is not at ' +
                  'fault and cannot be: it never reads tool_name to decide, so piping this same payload ' +
                  'straight into it - which is what every case above does - produces a correct DENY over ' +
                  'a registration that would never have delivered it. This is a Windows-only plugin and ' +
                  'PowerShell is the shell tool it is named after')
    } else {
        $v     = Test-IsDeny $m1
        $m1ok  = $v.ok
        $m1why = $v.why
    }
    Add-Result 'M1 armed, main thread, PowerShell, through the CLI matcher -> DENY' $m1ok $m1why

    # M2-M3. The other edge. A matcher wide enough to cover every hole is wide
    #        enough to refuse the way out of the mode it enforces.
    foreach ($u in $UngatedTools) {
        $r = Invoke-GateAsCli -FakeRoot $rootOn -WorkDir $work -Tag ("cli-ungated-" + $u.tool) `
                              -Tool $u.tool -Matcher $script:GateMatcher -Loose `
                              -Payload (New-Payload -Tool $u.tool -AgentId $null -AgentType '' -Extra '')
        Add-Result ("M  armed, main thread, $($u.tool) -> the CLI must not invoke the gate at all") `
            (-not $r.invoked) `
            ("hooks.json's matcher '$($script:GateMatcher)' selects $($u.tool) under the loosest reading " +
             "of matcher semantics, and the gate is tool-blind, so an armed gate REFUSES it from the main " +
             "thread (it exited $($r.code)). $($u.why). Widening this matcher is the safe direction only " +
             'up to here')
    }

    # -------------------------------------------------------------------
    # P. THE THIRD READER OF THE SWITCH: THE DOCTOR'S INFORMATIONAL ROSTER.
    #
    #    Section K established that the gate and the delegate toggle agree about
    #    a config. The roster is the surface an operator reads when they want to
    #    know whether anything is blocking on this machine, and until
    #    3 August 2026 nothing here read a line of what it prints.
    #
    #    IT USED TO BE ITS OWN COMMAND. These two cases drove bin\lwg-status.ps1,
    #    a report command with no other job; that command is deleted and the
    #    block it printed - a paragraph per gate, then a per-module listing -
    #    moved into bin\lwg-doctor.ps1 below the verdict prose. THE CASES WERE
    #    RE-POINTED RATHER THAN DELETED because the properties are not covered
    #    anywhere else: K8 makes the non-boolean claim about the TOGGLE, which
    #    is a different renderer with a different output, and nothing at all in
    #    this tree besides P2 reads an impl-path-not-on-disk note.
    #
    #    WHAT THE EXIT ASSERTION IS NOW, AND WHY IT IS WEAKER ON PURPOSE. The
    #    old command exited 0 because reporting was its whole job. The doctor
    #    exits on its verdict, and against a fixture root of four files most of
    #    its nine checks fail - so these cases assert only that it COMPLETED,
    #    by requiring the RESULT: line that its abort path (exit 3) never
    #    prints. Demanding a particular code here would be asserting that a
    #    four-file fixture is a healthy plugin install, which it is not.
    #
    #    P1 IS THE SAME DEFECT SHAPE AS K1, IN A DIFFERENT RENDERER. The block
    #    printed the RESOLVED answer formatted as a config.json assignment -
    #    "switch : interaction.delegate = false" - with the value spelled in
    #    JSON literals, so it read as a quotation of the file. Only a real
    #    boolean is a setting, so on a config holding "delegate": "true" the
    #    resolver ignores the string, the default stands, and the operator was
    #    told `interaction.delegate = false` over a file plainly saying true,
    #    with nothing on screen saying a written value had been rejected.
    #    bin/lwg-config.ps1 had already refused to make that mistake, in a
    #    comment naming this exact hazard.
    #
    #    P2 IS THE OTHER HALF OF THE SAME LINE. `code:` is a registry string
    #    literal. Nothing opened the file, so a gate whose implementation had
    #    been deleted still printed its path under a heading promising that
    #    turning the switch on would make it LIVE. The roster reports and does
    #    not judge, so the finding is a note on the line rather than a failure -
    #    and the doctor's nine checks, which is where a missing impl file SHOULD
    #    become a FAIL row, still do not test it. Moving the block did not close
    #    that gap and neither case here pretends it did: P2 asserts the NOTE,
    #    and asserts nothing about the verdict.
    # -------------------------------------------------------------------
    $pHead = '{"version":"0.4.0","modules":{"failure_capture":true},'
    $pTail = '"repos":{"$comment":"nothing here"}}'

    $rootP1 = New-LwgReportRoot -Base $work -Name 'report-string-true' -Json (
        $pHead + '"interaction":{"delegate":"true"},' + $pTail)
    $p1 = Invoke-Report -FakeRoot $rootP1 -WorkDir $work -Tag 'report-string-true'
    # SCOPED TO THE ROSTER, NOT TO THE WHOLE REPORT, and the difference is not
    # hypothetical. When these cases drove bin\lwg-status.ps1 the whole of stdout
    # WAS the roster; the doctor prints nine check rows above it, and the
    # config-registry row's detail is free prose about the same key. A future
    # detail string spelling `interaction.delegate = true` would red P1 over a
    # sentence in a different component. Get-RosterText cuts at the heading, so
    # both cases read the block they are about - and a missing heading makes
    # $p1Ran false rather than making the negative match vacuously true, which
    # is the failure mode a substring search invites.
    $p1Roster = Get-RosterText $p1.out
    $p1Ran    = ($p1.out -match '(?m)^RESULT:' -and $p1Roster -ne '')
    $p1Assign = ($p1Roster -match '(?m)interaction\.delegate\s*=\s*(true|false)')
    $p1Names  = ($p1Roster -match '(?i)NOT A BOOLEAN' -and $p1Roster -match "(?m)in file\s*:")
    Add-Result 'P1 the roster does not render the resolved answer as a config.json assignment' `
        ($p1Ran -and -not $p1Assign -and $p1Names) `
        ("bin\lwg-doctor.ps1 exited $($p1.code) on a config holding `"delegate`": `"true`". " +
         $(if (-not $p1Ran) { 'It printed no RESULT: line or no roster heading, so the block never ran - nothing about the rendering was established. ' } else { '' }) +
         $(if ($p1Assign) { 'Its roster printed "interaction.delegate = <value>", which reads as a quotation of config.json and is the RESOLVED answer. ' } else { '' }) +
         $(if (-not $p1Names) { 'Its roster never says the stored value was not a boolean and was ignored. ' } else { '' }) +
         "Its GATES block was:`n$(($p1Roster -split "`n" | Where-Object { $_ -match 'switch|in file|resolved|delegate_gate|code' }) -join "`n")")

    $rootP2 = New-LwgReportRoot -Base $work -Name 'report-no-gate-file' -WithGateFile $false -Json (
        $pHead + '"interaction":{"delegate":false},' + $pTail)
    $p2 = Invoke-Report -FakeRoot $rootP2 -WorkDir $work -Tag 'report-no-gate-file'
    $p2Roster = Get-RosterText $p2.out
    Add-Result 'P2 the roster says so when the registry names an impl file that is not on disk' `
        (($p2.out -match '(?m)^RESULT:') -and $p2Roster -ne '' -and $p2Roster -match '(?i)NOT ON DISK') `
        ("bin\lwg-doctor.ps1 exited $($p2.code) against a plugin root with NO lib\gate_delegate.ps1 " +
         "and its roster still printed the registry's impl string with nothing to say the file is absent " +
         '(or the block never ran, which the missing RESULT: line or missing heading would show). ' +
         "`$LwgModuleRegistry's status and impl fields are literals, so BUILT and code: are statements " +
         "about lib\common.ps1 rather than about disk. Its GATES block was:`n" +
         (($p2Roster -split "`n" | Where-Object { $_ -match 'code|delegate_gate' }) -join "`n"))

    # -------------------------------------------------------------------
    # N. WHAT THE REST OF THE TREE SAYS THIS GATE IS.
    #
    #    This is the only section here that reads PROSE, and it is here rather
    #    than in tests\doc_claims.ps1 for a reason that file states about
    #    itself: its rules are scoped to COUNTED QUANTITIES - test files,
    #    per-suite cases, CI steps, doctor checks, commands, modules - and every
    #    claim below is a statement with no number in it. doc_claims' own header
    #    records the consequence: "A sentence stating no quantity is simply
    #    invisible to a guard that matches quantities."
    #
    #    WHAT WENT WRONG, AND WHY IT IS THE GATE'S SUITE THAT SHOULD CATCH IT.
    #    delegate_gate landed on 30 July 2026 and eight tracked surfaces went on
    #    describing the tree that existed for the few hours before it: three
    #    issue forms told every reporter that there is no PreToolUse
    #    registration left at all and that "it did not stop X" is the documented
    #    state - one of them behind a REQUIRED attestation that the report is
    #    not a documented limitation - so the one class of report this
    #    repository exists to receive was the one its intake refused. The worst
    #    of the eight was CONTRIBUTING.md's rule for writing a hook: "every hook
    #    exits 0 ... exit 2 makes it discard the decision entirely", which is
    #    the exact inverse of the contract, and a gate written to it computes a
    #    correct denial, exits 0, blocks nothing, and is counted as a live gate
    #    by every surface that counts gates.
    #
    #    SO THESE FOUR CASES ARE DERIVED, NOT PINNED. Each one first establishes
    #    a fact from the tree - hooks.json really registers the gate, the
    #    registry really carries a kind 'gate' entry, the gate really exits 2 to
    #    deny, delegate_gate really is implemented and off in the shipped config
    #    - and only then asserts that no tracked file contradicts it. A case
    #    that just grepped for a forbidden phrase would agree with itself
    #    forever; these invert the moment the tree does.
    #
    #    WHAT THE SWEEP CANNOT SEE, stated because a phrase list always reads as
    #    more than it is:
    #      - It matches the SPELLINGS below and no others. A future page saying
    #        the same thing in different words is not read. This is a list of
    #        the sentences somebody found, not a proof that no others exist -
    #        the same limit doc_claims' header states about its own four shapes.
    #      - The qualifier test is positional and is the weak part. "nothing
    #        here blocks anything" is allowed through when the match, the line
    #        it starts on or the line above says "default install", "by
    #        default" or "switched off", because docs/commands.md states it that
    #        way and is correct. A page that put the qualifier three lines
    #        earlier is failed wrongly; one that put a bare absolute two lines
    #        below a qualified sentence passes wrongly.
    #      - It reads prose and cannot read intent. N4 is a targeted assertion
    #        on ONE table row rather than a sweep, because the sentence it is
    #        about is quoted-and-refuted in two other files on purpose.
    #      - CHANGELOG.md and docs/uat-report.md are exempt whole, because both
    #        quote wrong sentences deliberately as a record. This file is exempt
    #        too, for the same reason: the phrase table below IS the wrong
    #        sentences.
    # -------------------------------------------------------------------

    # The file set. A directory walk rather than `git ls-files`, so this runs on
    # a path clone and on a machine with no git - the same standing this file
    # gives section H, and for the same reason. The COUNT is asserted: an
    # enumeration that found nothing would pass every case below by having
    # nothing to fail on, which is the empty-set pass this repository has been
    # bitten by before.
    #
    # THE DIRECTORIES ARE NAMED RATHER THAN THE WALK BEING BLANKET, and that is
    # about not failing on somebody else's scratch file. A blanket recursive
    # walk under $Root reads whatever happens to be sitting in the working tree
    # - an untracked directory, a scratch note, another agent's fixture - and
    # one matching phrase in any of them would turn these cases red over
    # something that is not in this repository at all. `git ls-files` would be
    # the exact answer and is not used, because it would make the whole suite
    # need git on the machine, which section H goes to some length to avoid.
    # THE SWEEP SPANS TWO ROOTS SINCE THE PAYLOAD RESTRUCTURE, and it has to be
    # spelled out rather than inferred. Seven of these directories moved under
    # lw-watchtower/ and three - .github, docs, tests - stayed at the repository
    # root. `if (-not [IO.Directory]::Exists($r)) { continue }` below SKIPS A
    # DIRECTORY THAT IS NOT THERE, so a single-rooted walk after the move would
    # have gone on passing while quietly reading none of those three: the
    # empty-set pass, arrived at by a directory rename. `output-styles` was in
    # this list until the directory was deleted; a dead entry here is the same
    # silent skip written down on purpose, so it is gone.
    $nPayloadDirs = @('agents', 'bin', 'commands', 'context', 'hooks', 'lib', 'statusline')
    $nRepoDirs    = @('.github', 'docs', 'tests')
    # uat-report.md moved to .github\notes\ under #183 and .github IS still swept,
    # so the exemption has to follow it or the sweep starts reading a v0.3.0
    # acceptance record that quotes wrong sentences on purpose.
    $nExempt = @('CHANGELOG.md', '.github\notes\uat-report.md', 'tests\gate_delegate.ps1')
    $nFiles  = @()
    # Each root is carried with the base its $rel is computed against, so a file
    # found under the payload reports lw-watchtower\... and one found under docs\
    # reports docs\... - which is what $nExempt is matched on and what a failure
    # message has to name for anyone to find the line.
    $nRoots  = @(
        [pscustomobject]@{ Dir = $Root;            Base = $script:RepoRoot; Top = $true }
        [pscustomobject]@{ Dir = $script:RepoRoot; Base = $script:RepoRoot; Top = $true }
    )
    foreach ($d in $nPayloadDirs) { $nRoots += [pscustomobject]@{ Dir = (Join-Path $Root $d);            Base = $script:RepoRoot; Top = $false } }
    foreach ($d in $nRepoDirs)    { $nRoots += [pscustomobject]@{ Dir = (Join-Path $script:RepoRoot $d); Base = $script:RepoRoot; Top = $false } }
    foreach ($rr in $nRoots) {
        $r = $rr.Dir
        if (-not [IO.Directory]::Exists($r)) { continue }
        $depth = if ($rr.Top) { [IO.SearchOption]::TopDirectoryOnly } else { [IO.SearchOption]::AllDirectories }
        foreach ($f in [IO.Directory]::EnumerateFiles($r, '*', $depth)) {
            $rel = $f.Substring($rr.Base.Length).TrimStart('\', '/')
            if ($f -notmatch '\.(md|ya?ml|json|ps1)$') { continue }
            if ($nExempt -contains $rel) { continue }
            $nFiles += [pscustomobject]@{ Rel = $rel; Lines = @([IO.File]::ReadAllLines($f)) }
        }
    }

    # The four claim families. Each is a derived fact, the patterns that deny
    # it, and the phrases on the SAME LINE that make an otherwise-absolute
    # sentence a qualified one.
    $nAllow = '(?i)default install|by default|switched off|ships off|is off'

    $nHooksHasPre = $false
    try { $nHooksHasPre = ($null -ne $hooks.hooks.PreToolUse -and $hooksRaw -like '*gate_delegate.ps1*') } catch { }
    $nRegIsGate   = ($null -ne $entryReg -and [string]$entryReg.kind -eq 'gate')
    $nGateExits2  = ($gateSrc -match '(?m)^\s*exit\s+2\s*$')
    # Implemented and not active on the SHIPPED config, which is what puts the
    # "(1 off)" in the banner. Read through the same two calls the banner uses.
    $nOffCount = 0
    try {
        $nShipped = Get-LwgConfig -Path $CfgPath
        foreach ($m in $script:LwgModules) {
            if ((Test-LwgModuleImplemented -Name $m) -and -not (Test-LwgModule -Name $m -Config $nShipped -Repo '')) {
                $nOffCount++
            }
        }
    } catch { }

    function Find-LwgProse {
        <#
          Match over the WHOLE FILE TEXT, not line by line, and that is not a
          detail. Both of the sentences this sweep was written for wrap: the
          feature form said "**No module\nhere is a gate.**" and "and no\n
          `PreToolUse` hook is registered". A line-scoped scan found four of the
          six occurrences in the tree it was first run against and silently
          missed both of those, which is the shape of a guard that reports a
          clean sweep having looked at half the sentence. Every \s+ in a pattern
          below therefore spans the newline.

          THE QUALIFIER TEST IS STILL POSITIONAL, and it is the weak part.
          $Allow is checked against the matched text, the line the match starts
          on, and the line above it - the same two-line window
          tests\doc_claims.ps1 uses for its ignore marker. A page that put the
          qualifier three lines earlier would be failed wrongly.
        #>
        param([object[]]$Files, [string[]]$Patterns, [string]$Allow)
        $hits = @()
        foreach ($doc in $Files) {
            $text = ($doc.Lines -join "`n")
            foreach ($p in $Patterns) {
                foreach ($m in [regex]::Matches($text, $p)) {
                    $ln    = (($text.Substring(0, $m.Index) -split "`n").Count)
                    $line  = if ($ln -ge 1 -and $ln -le $doc.Lines.Count) { $doc.Lines[$ln - 1] } else { '' }
                    $above = if ($ln -ge 2) { $doc.Lines[$ln - 2] } else { '' }
                    if ($Allow -and ($m.Value -match $Allow -or $line -match $Allow -or $above -match $Allow)) { continue }
                    $t = ($m.Value -replace '\s+', ' ').Trim()
                    if ($t.Length -gt 120) { $t = $t.Substring(0, 117) + '...' }
                    $hits += ("{0}:{1}  {2}" -f $doc.Rel, $ln, $t)
                }
            }
        }
        return $hits
    }

    # N1. "no PreToolUse hook is registered", in the four spellings this tree
    #     used. Each is anchored on a present-tense standing claim, NOT on the
    #     bare words "no PreToolUse hook": config.json and checklist.json both
    #     carry that phrase correctly about the interval before the gate landed,
    #     and failing a true historical sentence would teach the next reader to
    #     delete the history rather than the falsehood.
    #
    #     THE SECOND GROUP TAKES A QUALIFIER AND THE FIRST DOES NOT, on purpose.
    #     "nothing here blocks anything" is TRUE of a default install and
    #     docs/commands.md says exactly that, correctly, in the same sentence as
    #     "ships switched off" - so that family is allowed through when the
    #     qualifier is beside it. No qualifier rescues "there is no PreToolUse
    #     key": that one is false however it is hedged.
    $n1Pat = @(
        '(?i)nothing\s+registers\s+a\s+.{0,4}PreToolUse.{0,4}\s+hook\s+now',
        '(?i)there\s+is\s+no\s+.{0,4}PreToolUse.{0,20}\s+left\s+at\s+all',
        '(?i)has\s+no\s+.{0,4}PreToolUse.{0,4}\s+key',
        '(?i)no\s+.{0,4}PreToolUse.{0,4}\s+hook\s+is\s+registered',
        '(?i)No\s+module\s+here\s+is\s+a\s+gate',
        '(?i)Every\s+module\s+in\s+the\s+registry\s+is\s+.{0,4}observe'
    )
    $n1PatQ = @(
        '(?i)nothing\s+(?:here\s+|in\s+this\s+plugin\s+)?blocks\s+anything'
    )
    $n1Hits = @(Find-LwgProse -Files $nFiles -Patterns $n1Pat -Allow '') +
              @(Find-LwgProse -Files $nFiles -Patterns $n1PatQ -Allow $nAllow)
    Add-Result 'N1 no tracked file says this plugin registers no PreToolUse hook' `
        ($nFiles.Count -ge 40 -and $nHooksHasPre -and $nRegIsGate -and $n1Hits.Count -eq 0) `
        $(if ($nFiles.Count -lt 40) { "the prose walk found only $($nFiles.Count) file(s) under $Root, which is not this repository - this case could not run" }
          elseif (-not $nHooksHasPre) { 'hooks/hooks.json does not register gate_delegate.ps1 on PreToolUse, so the premise of this case is gone. Section A is where that is failed; here it means the sweep below asserts nothing' }
          elseif (-not $nRegIsGate) { '$LwgModuleRegistry carries no delegate_gate entry of kind gate, so "no module here is a gate" would be TRUE and this sweep must not fail a page for saying it. Section C is where that is failed' }
          else { "hooks/hooks.json registers lib/gate_delegate.ps1 on PreToolUse and `$LwgModuleRegistry declares delegate_gate kind 'gate', and these line(s) say otherwise:`n    " + ($n1Hits -join "`n    ") })

    # N2. The exit-code contract, inverted. CONTRIBUTING.md carried this as a
    #     rule for writing a hook, which makes it the highest-consequence of the
    #     four: a contributor who follows it ships a gate that fails open.
    $n2Pat = @(
        '(?i)exit\s+2\s+makes\s+it\s+discard\s+the\s+decision',
        '(?i)denial\s+is\s+expressed\s+in\s+.{0,2}stdout.{0,2},\s+not\s+in\s+the\s+exit\s+code'
    )
    $n2Hits = @(Find-LwgProse -Files $nFiles -Patterns $n2Pat -Allow '')
    Add-Result 'N2 no tracked file inverts the PreToolUse denial channel' `
        ($nFiles.Count -ge 40 -and $nGateExits2 -and $n2Hits.Count -eq 0) `
        $(if ($nFiles.Count -lt 40) { "the prose walk found only $($nFiles.Count) file(s), so this case could not run" }
          elseif (-not $nGateExits2) { 'lib/gate_delegate.ps1 has no bare `exit 2`, so the denial channel this case is about is not there to be described. Fix that before this sentence' }
          else { "lib/gate_delegate.ps1 denies by writing stderr and exiting 2 - exit 1 is a NON-blocking error and the tool runs anyway - and these line(s) tell a contributor the opposite:`n    " + ($n2Hits -join "`n    ") })

    # N3. The banner. delegate_gate is implemented and ships off, so the
    #     SessionStart banner prints "(1 off)"; a page saying it prints no
    #     parenthetical is telling a reader either that the gate is armed or
    #     that it is not counted as implemented, and both are wrong about the
    #     one component here that can refuse a call.
    $n3Pat = @(
        '(?i)implemented\s+and\s+active\s+now\s+agree\s+for\s+every\s+module',
        '(?i)banner\s+prints\s+no\s+parenthetical'
    )
    $n3Hits = @(Find-LwgProse -Files $nFiles -Patterns $n3Pat -Allow '')
    Add-Result 'N3 no tracked file says the banner prints no built-but-off parenthetical' `
        ($nFiles.Count -ge 40 -and $nOffCount -gt 0 -and $n3Hits.Count -eq 0) `
        $(if ($nFiles.Count -lt 40) { "the prose walk found only $($nFiles.Count) file(s), so this case could not run" }
          elseif ($nOffCount -le 0) { 'no module is implemented-and-off on the shipped config, so the banner really would print no parenthetical and this case has nothing to assert. If delegate_gate was switched on in config.json, that is the defect' }
          else { "$nOffCount module(s) are implemented and switched off on the shipped config, so the banner prints a parenthetical, and these line(s) say it does not:`n    " + ($n3Hits -join "`n    ") })

    # N4. The one summary row a reader lands on when they want to know what
    #     survived the removals. It is a targeted assertion on one row rather
    #     than a phrase sweep, because the unqualified form is QUOTED in two
    #     places on purpose - docs/modules.md refutes it by name and
    #     lib/common.ps1's registry note records having said it - and a sweep
    #     that failed a page for quoting the sentence it is correcting would be
    #     unusable.
    $n4Row = ''
    $n4Doc = @($nFiles | Where-Object { $_.Rel -eq 'docs\gates-removed.md' })
    if ($n4Doc.Count -eq 1) {
        $n4Row = ($n4Doc[0].Lines | Where-Object { $_ -match '(?i)^\|\s*\*\*Does not\*\*' -and $_ -match 'tool_name' } | Select-Object -First 1)
    }
    $n4Reads = ($gateSrc -match '\$payload\.tool_name')
    Add-Result 'N4 the gates-removed summary qualifies the tool_name claim the code requires' `
        ($n4Doc.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace($n4Row) -and $n4Reads -and $n4Row -match '(?i)to\s+decide') `
        $(if ($n4Doc.Count -ne 1) { "docs\gates-removed.md was not found by the prose walk, so this case could not run" }
          elseif ([string]::IsNullOrWhiteSpace($n4Row)) { 'docs\gates-removed.md has no "**Does not**" row mentioning tool_name, so this case could not find the claim it is about - the table was restructured and this assertion needs re-pointing, not deleting' }
          elseif (-not $n4Reads) { 'lib/gate_delegate.ps1 no longer reads $payload.tool_name at all, so the flat claim would now be true and this case is what needs changing' }
          else { "lib/gate_delegate.ps1 reads `$payload.tool_name - after the decision, to name the refused tool - so the flat claim is not true of the code. The row must say it does not read it TO DECIDE. It reads:`n    $($n4Row.Trim())" })

    # -------------------------------------------------------------------
    # L. ONE CLAUSE OF THE HEADER'S OWN PROMISE, ASSERTED INSTEAD OF STATED.
    #
    #    "NOTHING REAL IS TOUCHED" sat at the top of this file for as long as
    #    the file existed and was false for most of it. The child processes were
    #    sandboxed; this one was not, so section K's five non-boolean fixtures
    #    put five ConfigInvalidFlag records into the operator's live event log
    #    on every run - 1,644 bytes, measured, and on a machine whose plugin had
    #    not written yet it CREATED that file rather than merely growing it.
    #
    #    THIS IS THE ONLY CASE HERE THAT COULD HAVE CAUGHT IT. Every other case
    #    in this file reads an exit code, a stream, or a file the suite made
    #    itself under the temp directory. A record appended to a file in the
    #    operator's profile moves none of those, so 79 green cases and a live
    #    leak are the same run - which is the exact shape of assurance this
    #    repository keeps warning about, arriving this time in the suite rather
    #    than in the thing under test.
    #
    #    IT ASSERTS A SIZE, WHICH IS NOT CONTENT, and the limit is real: a run
    #    that appended one record and removed exactly as many bytes elsewhere
    #    would pass this. No code path reachable from here can produce that
    #    shape - nothing in this plugin rewrites the log in place except
    #    Invoke-LwgRotate, which this suite never calls - and a byte count is a
    #    number an operator can check by hand against the file, which a hash of
    #    two megabytes is not.
    #
    #    IT DOES NOT COVER AN ABORT. If the suite throws before this line the
    #    case never runs, and exit 2 is then the only thing said about the
    #    environment. The teardown in the finally is what makes that safe going
    #    FORWARD; nothing here can testify about a run that did not reach it.
    #
    #    IT CAN GO RED FOR A REASON THAT IS NOT THIS SUITE'S, and that was
    #    OBSERVED while this case was being written rather than merely feared.
    #    The file it watches is the LIVE one and it has exactly one writer per
    #    process, not per suite: a Claude Code session open in another window
    #    appends to it through its own hooks, and so does a SECOND CHECKOUT of
    #    this repository running its own copy of this file. Both happened during
    #    development, and this case went red twice for writes it did not make
    #    while the same suite run standalone measured a delta of zero four times.
    #
    #    NOT WORKED AROUND, DELIBERATELY. Filtering the log by content would mean
    #    parsing two megabytes of JSONL and deciding which records "look like"
    #    fixtures, and a check that has to guess at authorship is a check that
    #    can be argued with - which is worth less than a blunt one that cannot.
    #    So if this case fails ALONE, re-run the suite by itself with no session
    #    open before reading it as a regression: the same instruction J10 carries
    #    about the clock, and for the same reason.
    # -------------------------------------------------------------------
    $realLogAfter = Get-LwgRealLogBytes $realLog
    # Built before the call rather than inside the string: a $(if ...) with its
    # own double quotes nested in a double-quoted string is exactly the sort of
    # quoting that parses one way here and another way in a later edit.
    $lBefore = if ($realLogBytes -lt 0) { 'ABSENT' } else { "$realLogBytes byte(s)" }
    $lAfter  = if ($realLogAfter -lt 0) { 'ABSENT' } else { "$realLogAfter byte(s)" }
    $lWhere  = if ([string]::IsNullOrWhiteSpace($realLog)) { '(no state dir resolved)' } else { $realLog }
    Add-Result 'L  the operator''s live event log is byte-unchanged by this run' `
        ($realLogAfter -eq $realLogBytes) `
        ("REGRESSION: this suite wrote into the operator's own state directory. $lWhere was " +
         "$lBefore before the run and $lAfter after it. Every in-process call that can reach " +
         'Write-LwgEvent has to happen inside the sandbox installed at the top of MAIN - the ' +
         'windows in Invoke-Gate and Invoke-Toggle cover child processes only, and section K ' +
         'calls Test-LwgModule in THIS process on five configs that hold a non-boolean on purpose')

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
    # is not reliable. Same reasoning as the per-case windows in Invoke-Gate,
    # applied to the outer one.
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

if ($script:Results.Count -ne $script:ExpectedCases) {
    # AN ABORT, NOT A FAILURE, and the distinction is the one this file makes
    # everywhere else: a tally that does not match the declared count is not a
    # statement that the gate misbehaved, it is a statement that this file
    # cannot say what it ran. tests\doc_claims.ps1 reads the tally line as the
    # tree's own answer for how many cases this suite has, so printing a
    # number the file does not vouch for would send a maintainer to correct
    # eleven correct sentences.
    Write-Output ("ABORTED: {0} case(s) ran and this file declares {1} in `$script:ExpectedCases." -f $script:Results.Count, $script:ExpectedCases)
    Write-Output 'A case was added without moving that constant, the header and the documents quoting it,'
    Write-Output 'or a case stopped being reached. Either way this run has no denominator anybody can quote.'
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
Write-Output '"the gate is sound" - see the header, and docs\gates-removed.md Lesson 3.'
Write-Output 'EXIT: 0'
exit 0
