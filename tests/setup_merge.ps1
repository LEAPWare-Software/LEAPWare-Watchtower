#requires -version 5
<#
  LW-WATCHTOWER installer settings-merge regression suite.

      powershell -NoProfile -ExecutionPolicy Bypass -File tests\setup_merge.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File tests\setup_merge.ps1 -Verbose

  WHAT THIS IS AND WHY IT IS BACK

  bin\lwg-setup.ps1 merges into the operator's real settings.json - the file that
  holds every other setting they have. Its merge behaviour was covered end to end
  by tests\deny_parity.ps1, which was deleted on 30 July 2026 along with the
  permissions.deny table it was really aimed at. The table is genuinely gone;
  the MERGE PATH is not. /lw-watchtower:setup still writes through it, so from that day
  until this file landed nothing checked that the installer preserves keys it was
  never asked to touch, takes exactly one backup, refuses a stale BaseHash, or
  rolls back.

  This suite is that harness re-targeted at a section that still writes: the
  STATUSLINE section. It is not a revival of the deny-parity fixtures and covers
  none of the deny table, because there is no deny table.

  ---------------------------------------------------------------------------
  WHAT "PRESERVED" MEANS HERE - read this before reading a green run
  ---------------------------------------------------------------------------
  Applying RE-SERIALISES the whole file. Indentation becomes PowerShell's, and
  < > & ' become < > & '. So the claim these cases make about
  an unrelated top-level key is VALUE AND ORDER identity - its compressed JSON
  serialisation is unchanged and it sits in the same position - and NOT byte
  identity of the file. Byte identity is asserted only where the installer really
  promises it: the no-op short-circuit (case: idempotent second run), the backup
  it takes, and rollback. Stating this in the header rather than in a footnote,
  because "preserved" is exactly the word a reader will take to mean more than it
  does.

  ---------------------------------------------------------------------------
  HOW A CASE IS RUN
  ---------------------------------------------------------------------------
  In a real child process, against the real bin\lwg-setup.ps1, because that is
  the file /lw-watchtower:setup invokes. The installer takes parameters rather than
  stdin, so each case is

      powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-setup.ps1 `
                 -Step <detect|diff|apply|rollback> -Section statusline `
                 -SettingsPath <scratch>\settings.json ...

  with $env:USERPROFILE swapped to <scratch>\profile around the call and restored
  in a finally. Those two knobs are the whole sandbox contract, documented in the
  installer's own header: -SettingsPath redirects every settings read and write,
  and everything else - the status-line target, the state directory, the agent
  directory - hangs off the CONFIGURATION DIRECTORY, which is CLAUDE_CONFIG_DIR
  when set and $env:USERPROFILE\.claude otherwise. Nothing here can reach the
  operator's own .claude directory, and no case runs elevated or constructs a
  destructive command.

  FOUR ENVIRONMENT VARIABLES ARE ALSO CLEARED around every child, and restored in
  the same finally: CLAUDE_PLUGIN_ROOT, CLAUDE_PLUGIN_DATA,
  CLAUDE_CODE_PLUGIN_CACHE_DIR and CLAUDE_CONFIG_DIR. Each one, if the runner's
  own process happened to carry it, would redirect the code under test somewhere
  outside the scratch tree and make a case pass or fail for a reason that is not
  in this file. They were not cleared before because nothing here read them; the
  install-mode detection reads the first three.

  CLAUDE_CONFIG_DIR JOINED THAT LIST ON 3 SEPTEMBER 2026 AND IT IS THE MOST
  IMPORTANT OF THE FOUR. Until then nothing in this repository read it, so
  swapping USERPROFILE alone WAS the whole sandbox. Now that every path resolves
  through it, a runner that happens to set the variable would point every child
  in this file at that machine's REAL configuration directory - with USERPROFILE
  pointing harmlessly at the scratch tree the whole time, so the sandbox would
  look intact while nothing was in it. It is cleared by default and set only by a
  case that is about it, through the -ConfigDir parameter each launcher takes.

  Every scratch path is BUILT AT RUNTIME from [IO.Path]::GetTempPath(). No path
  in this file names a machine, an account or an install location, which is what
  tests\portability_scan.ps1 holds every tracked file to.

  Two real files are read: statusline\statusline.ps1 and .claude-plugin\plugin.json
  (for the plugin NAME, which is derived rather than spelled out here so a rename
  moves the fixtures with it). statusline\statusline.ps1 is also EXECUTED, from a
  byte copy under the scratch profile - never in place, because in place its own
  $PSScriptRoot resolves the real repo and the marketplace candidate it is being
  asked about would never be reached.

  ---------------------------------------------------------------------------
  THE HOOKS SECTION, AND THE STATUS LINE'S PLUGIN-ROOT RESOLUTION
  ---------------------------------------------------------------------------
  Added when the INSTALL-MODE detection defect was fixed. Until then this suite
  drove the statusline section only and reached the hooks path not at all, which
  is exactly why that defect survived: bin\lwg-setup.ps1 looked for a marketplace
  install in ~\.claude\plugins\repos, a directory that does not exist on a live
  Claude Code install, so a marketplace-installed plugin was classified NOT
  DISCOVERABLE and setup wrote a full SECOND copy of every hook registration -
  with its own duplicate-firing warning suppressed, because the warning is keyed
  on the same flag.

  statusline\statusline.ps1 carried the same wrong assumption in LwgPluginRoots,
  so the cases below cover BOTH files: it is one defect - one wrong belief about
  where a marketplace install lives - with two symptoms.

  THOSE CASES ARE ABOUT WHAT THE SECTION DECIDES, NOT WHAT IT WRITES, and the
  distinction cost this file a wrong reading. Sections 17 to 19c establish
  install-mode detection, hook identity, duplicate registration and what the
  consent screen discloses; none of them is a merge-writer property. Until
  SECTION 31 landed, every claim in this suite about the WRITER - unrelated keys
  preserved by value and order, exactly one backup holding the original bytes, a
  stale BaseHash refused, a byte-identical second apply, rollback byte for byte -
  was established for `statusline` and merely INHERITED by `hooks` on the
  argument that both go through Save-Settings. That is an argument from shared
  code and not a measurement, and the two paths are not in fact identical above
  Save-Settings. Section 31 measures the five, on `hooks`, against FIXTURE B.
  Read that fixture's comment before reading section 31: it is a different
  fixture for one specific reason.

  ---------------------------------------------------------------------------
  SECTIONS 23 AND 26 DO NOT TEST THE INSTALLER AT ALL
  ---------------------------------------------------------------------------
  Section 23 tests statusline\statusline.ps1 - the payload it decodes, the three states
  every number it takes from outside can be in, the paths it probes, the config
  it opens, the fault count it derives from health.jsonl and the reset clock it
  formats. That is stated here rather than left to be inferred from a green run.

  SECTION 26 IS HERE FOR THE SAME REASON and is equally not about the installer:
  it drives bin\lwg-update.ps1, which nothing in tests\ had ever run in any form.

  THE NUMBERING SKIPS 24 AND 25 ON PURPOSE. Those two sections drove
  the sitrep and resolve reporting commands, which have been removed from this
  plugin; the sections went with them. Section 26 keeps its number so that a
  case name or a baseline note written against it elsewhere still points at the
  same cases.

  They live in this file because it already owns the only harness in the
  repository that runs any of these for real, and sections 20 and 20b set the
  precedent. The alternative was another file in tests\, which moves the
  `tests-file-count` and `behavioural-suite-count` claims in every tracked page
  that states them - a cost paid for infrastructure rather than for coverage.
  If this file is ever split, those two sections are the seam.

  BASELINE FOR EVERY CASE IN SECTIONS 23 AND 26 IS cc44c99, not fd8d023, and each
  case states what the baseline actually printed. The defects are all present at
  fd8d023 too; a marketplace root does not resolve there at all, so the
  status-line fixtures would go red for a reason that is not the defect beside
  them, and cc44c99 is the tree this wave started from.

  SECTION 26 ADDS ONE EXTERNAL DEPENDENCY: git on PATH. A missing git ABORTS
  rather than skipping. Every remote it builds is a local bare repository under
  the scratch tree, so no case reaches a network.

  WHERE THE FIXTURE LAYOUT COMES FROM. It is not invented. It is the layout the
  CLI itself writes, read off this machine's ~\.claude tree and out of the 2.1.x
  binary: plugins\cache\<marketplace>\<plugin>\<version> is the install root
  (installed_plugins.json records it as installPath), plugins\marketplaces\<name>
  is the marketplace checkout, and the string "plugins/repos" appears in that
  binary zero times.

  CONTROL CASES ARE LABELLED. NINE of the cases below pass before the fix they
  sit beside as well as after it, on purpose - they pin the OTHER direction, so
  a "fix" that simply answers yes to everything fails them. They are marked
  CONTROL in their comment and in their case name, and none of them is offered
  as evidence that anything was fixed.

  That count said THREE until 3 August 2026 and there were four even then; the
  fifth arrived with the relocated-cache cases, the sixth and seventh with the
  read-only write and the permissions diff, the eighth and ninth with section 23
  - the fault gauge and the reset clock - and the tenth with the update check.
  IT IS BACK TO NINE: the permissions-diff CONTROL was deleted with section 22
  when the installer's permissions section went, so the sixth of that list no
  longer exists. The list above is the ORDER THEY ARRIVED IN and is not
  renumbered, because renumbering it would erase the record of which change
  brought which case.
  It is a hand-count of the CALLS to Add-Result whose case name begins CONTROL,
  and tests\doc_claims.ps1 cannot read it - that guard recognises "N cases"
  against a suite FILENAME only, so it stayed green over the wrong number. If you
  add or remove a CONTROL, change this line.

  COUNT THE CALLS, NOT THE MATCHES: THIS PARAGRAPH IS ONE OF THE MATCHES. A bare
  grep for the word CONTROL over this file answers with the case comments and
  with this header's own prose as well as the case names, so it always over-counts
  and the amount it over-counts by changes every time somebody edits a comment.
  This paragraph used to name a specific over-count, and that number was wrong
  when it was measured here - which is exactly the failure it was warning about.
  The only countable spelling is the CALL: the case names all begin with a quote
  and then CONTROL, so count Add-Result lines whose name starts that way. That is
  the same shape as the checklist rule this project already caught spelling, in
  its own title, the string it asserted was absent - a rule whose stated method
  defeats its stated answer. It is called out here instead of being dodged by
  un-quoting the literal, because the quotation is what makes the instruction
  followable at all.

  IT HAS ALREADY GONE STALE ONCE FROM TWO PEOPLE EDITING ONE FILE, which is the
  cost of a hand-count and is recorded rather than tidied away: this line read
  SEVEN and then NINE while the real count was ten, because two changes landed in
  this file in the same window and each incremented from what it could see.
  Count them, do not add to or subtract from the number you find.

  NOT EVERY CONTROL HAS THE SAME BASELINE, and collapsing them would be the
  overstatement this file is about. The four older ones pass at fd8d023, the
  commit whose defect this suite was built around. The relocated-cache CONTROL
  passes against the WORKING TREE as it stood before the fix beside it, because
  the behaviour it guards - reading CLAUDE_CODE_PLUGIN_CACHE_DIR at all - did
  not exist at fd8d023 in either file. Each case comment states its own.

  ---------------------------------------------------------------------------
  WHAT IS DELIBERATELY NOT COVERED, so a green run is not read as more
  ---------------------------------------------------------------------------
  * THE BACKUP-COLLISION SUFFIX. Save-Settings names its backup for the current
    second and appends -1, -2 ... if that name is taken. Reaching the loop needs
    two writes inside one second, which is a race with the clock; a case that
    sometimes exercises it and sometimes does not is a case that gets deleted the
    first time it goes red for no reason. Not covered, not faked.
  * THE POST-WRITE AUTO-RESTORE. If what lands on disk does not parse,
    Save-Settings copies the backup back. The merged JSON is parse-checked BEFORE
    the write, so the branch is unreachable without injecting a fault into the
    writer. Not covered, not faked. That branch now reports WHY a restore failed
    instead of swallowing it, and nothing here exercises that either.
  * THE ATOMICITY OF THE WRITE. Save-Settings stages the new file beside the
    target and copies it over with [IO.File]::Copy, which is not an atomic
    replace: a process killed or a volume filled part-way through the copy can
    leave settings.json truncated. Inducing that needs an interrupted write and
    no case here induces one. The docstring on Save-Settings states the gap and
    records why the atomic call was measured and rejected; a green run here says
    nothing about it either way.
  * ANYTHING TO DO WITH THE CONTENT OF permissions.deny. There is no permissions
    section left in bin\lwg-setup.ps1 to drive: it proposed nothing on any run
    and was removed, and the two cases here that drove its diff went with it -
    see the stub where section 22 was. What section 28 DOES cover, and all it
    covers, is that the removal is complete at the door: -Section permissions,
    -DestructiveGate and -SecretGate are rejected by parameter binding rather
    than accepted and discarded. The installer still REPORTS the operator's own
    inert deny rules under -Step detect, through Get-InertRules, and no case
    here drives that report. Also not covered: the questions and the doctor
    step. Detection's report is read by the hooks cases, but only for the
    install-mode lines.
  * A REAL MARKETPLACE INSTALL. Every case here plants the layout under a
    scratch profile. Nothing in this suite proves the CLI still writes that
    layout in the build you are running - only that setup and the status line
    agree with the layout this machine's CLI wrote when the fix was made. The
    legacy plugins\repos candidate is kept in both files for that reason.
  * TWO WAYS THE DETECTION CAN STILL BE WRONG, both in the SAME direction: it
    says the plugin loads when nothing does, and the hooks section then wires up
    nothing at all. (1) An installed plugin that is switched off in
    enabledPlugins registers nothing. (2) A PROJECT-SCOPED install belonging to
    a different repository sits in exactly the same plugins\cache tree as a
    user-scoped one - installed_plugins.json records the scope and projectPath,
    setup PRINTS them, and does not narrow its verdict on them. Neither is
    covered by a case here, and both are named in the detection report itself
    and in the comment above the probe.

  ---------------------------------------------------------------------------
  EXIT CODES - a CI job reads these and nothing else
  ---------------------------------------------------------------------------
      0  every case passed
      1  at least one case FAILED
      2  the suite ABORTED - it could not set up or could not run a case, so
         nothing was established either way. Zero cases run is an abort, never
         an empty-set pass.
#>
[CmdletBinding()]
param(
    # The PLUGIN PAYLOAD root - lw-watchtower\ under this file's parent, not the
    # repository root, which is what this parameter meant before the restructure, correct for a run from anywhere
    # as long as this file stays in tests\.
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

$SetupPath      = Join-Path $Root 'bin\lwg-setup.ps1'
$RepoStatusLine = Join-Path $Root 'statusline\statusline.ps1'
$ManifestPath   = Join-Path $Root '.claude-plugin\plugin.json'
$UpdatePath     = Join-Path $Root 'bin\lwg-update.ps1'

$script:Pass    = 0
$script:Results = New-Object System.Collections.ArrayList
$script:Aborted = ''
$script:Work    = ''

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

# ---------------------------------------------------------------------------
# FIXTURE A
#
# Top-level keys in DELIBERATE non-alphabetical order - zeta, permissions,
# statusLine, alpha - because the defect Set-PropValue exists to prevent is a
# key silently moving to the end of the file, and an alphabetical fixture cannot
# tell "kept in place" from "re-sorted". permissions.ask holds exactly ONE
# element for the same reason: a one-element JSON array is the shape PowerShell
# is most likely to flatten into a bare string on the way back out.
#
# statusLine already carries refreshInterval 45, which is not the installer's
# default of 120, so "the operator's own tuning is kept" is a claim with a value
# behind it rather than a coincidence.
#
# Written as BYTES with no BOM, so the file on disk is exactly these characters
# and a byte comparison against it means something.
# ---------------------------------------------------------------------------
$FixtureText = @'
{
    "zeta": {
        "one": 1,
        "two": [ "a", "b" ]
    },
    "permissions": {
        "ask": [ "Bash(lwg-noop-fixture)" ],
        "defaultMode": "acceptEdits"
    },
    "statusLine": {
        "type": "command",
        "command": "powershell -NoProfile -File lwg-noop-fixture.ps1",
        "refreshInterval": 45
    },
    "alpha": "keep me"
}
'@

$Utf8NoBom    = New-Object System.Text.UTF8Encoding($false)
$Utf8Bom      = New-Object System.Text.UTF8Encoding($true)
$FixtureBytes = $Utf8NoBom.GetBytes($FixtureText)
$FixtureBom   = [byte[]]($Utf8Bom.GetPreamble() + $FixtureBytes)

# The expected top-level order, written out ONCE. Every order assertion is made
# against this rather than against the fixture text, so a case cannot pass by
# agreeing with a fixture that was itself re-sorted.
$ExpectedOrder = @('zeta', 'permissions', 'statusLine', 'alpha')

# ---------------------------------------------------------------------------
# FIXTURE B - THE HOOKS FIXTURE (section 31)
#
# FIXTURE A CANNOT BE USED FOR THE HOOKS WRITER PROPERTIES, and the reason is
# the whole point of the order assertion. Fixture A has no `hooks` key at all,
# so a hooks apply APPENDS one; "top-level order is unchanged" then only means
# "the new key went last", which no plausible defect breaks. The property
# Set-PropValue exists for is REPLACE IN PLACE - Add-Member -Force removes a key
# and re-appends it, silently moving it to the end of the operator's file - and
# it can only be falsified by a fixture in which the touched key already exists
# and is NOT last.
#
# So `hooks` sits SECOND of five, holding one registration that is the
# operator's own: UserPromptSubmit is an event this plugin registers on in
# hooks/hooks.json zero times, and the script leaf is a fixture name, so the
# hooks plan iterates past it and it must come out untouched. That is the merge
# claim inside the touched key, as distinct from the four unrelated top-level
# keys around it.
#
# statusLine is carried over from fixture A deliberately: it is the key the
# OTHER section writes, so "a hooks apply does not touch it" is a claim worth
# having and is not available from a fixture that omits it.
#
# Written as BYTES with no BOM, for the same reason fixture A is - the backup
# and rollback cases below compare bytes against exactly these characters.
# ---------------------------------------------------------------------------
$HooksFixtureText = @'
{
    "zeta": {
        "one": 1,
        "two": [ "a", "b" ]
    },
    "hooks": {
        "UserPromptSubmit": [
            {
                "matcher": "*",
                "hooks": [
                    {
                        "type": "command",
                        "command": "powershell -NoProfile -File lwg-noop-userprompt-fixture.ps1"
                    }
                ]
            }
        ]
    },
    "permissions": {
        "ask": [ "Bash(lwg-noop-fixture)" ],
        "defaultMode": "acceptEdits"
    },
    "statusLine": {
        "type": "command",
        "command": "powershell -NoProfile -File lwg-noop-fixture.ps1",
        "refreshInterval": 45
    },
    "alpha": "keep me"
}
'@

$HooksFixtureBytes  = $Utf8NoBom.GetBytes($HooksFixtureText)
$HooksExpectedOrder = @('zeta', 'hooks', 'permissions', 'statusLine', 'alpha')

# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

function Get-ScratchAppData {
    <#
      The AppData pair that goes with a swapped USERPROFILE, created on demand.

      APPDATA AND LOCALAPPDATA GO WITH IT, and that is not tidiness - it is the
      reason this suite left an untracked directory in the checkout. With
      USERPROFILE moved and those two left alone, the child powershell.exe
      failed to resolve its LocalApplicationData folder and wrote
      Microsoft\Windows\PowerShell\ModuleAnalysisCache RELATIVE TO ITS CURRENT
      DIRECTORY - which, for a suite run from the repository root, is the
      repository. Measured at ec80e88: two of two runs from the repo root left
      `?? Microsoft/` in `git status --porcelain`, and bin\lwg-update.ps1 counts
      any non-`#` porcelain-v2 line as dirty, so the plugin's own update command
      then refused with "1 uncommitted change(s) on batch/b2-bin". Running this
      suite disabled the update command.

      tests\stop_behaviour.ps1:2058-2064 diagnosed exactly this and fixed it in
      its own renderer on 3 August 2026. The fix was never carried across to
      this file, whose four child launchers all swapped USERPROFILE alone. It is
      carried across here in ONE helper rather than four spellings, and section
      29 asserts the OUTCOME - a clean working directory - rather than the
      mechanism, so a fifth launcher added later is covered by the same case.

      Derived from the case's own profile directory, so each child gets the
      AppData of the home it was told it has, and everything lands under
      $script:Work, which the finally at the bottom of this file deletes.

      THE DIRECTORIES MUST EXIST, AND THAT - NOT THE VARIABLE - IS THE FIX.
      Measured on this branch by running the whole suite three times with
      section 29 in place and one half of this helper removed each time:

        neither variable set, neither directory created   RED, ?? Microsoft/
        both variables set, directories NOT created       RED, ?? Microsoft/
        directories created, variables NOT set            green

      So a LOCALAPPDATA naming a directory that is not there is worth exactly
      nothing: the folder resolution verifies existence and gives up when it
      fails, and it gives up under the RELOCATED profile, which is why moving
      USERPROFILE alone was enough to break it. Both halves are kept anyway -
      the CreateDirectory because it is what actually works, the two assignments
      because a child that reads $env:LOCALAPPDATA itself must not be silently
      pointed at the runner's real one, and because tests\stop_behaviour.ps1
      spells it the same way and two harnesses solving one problem differently
      is how the second one goes stale.
    #>
    param([string]$ProfileDir)
    $r = [IO.Path]::Combine($ProfileDir, 'AppData\Roaming')
    $l = [IO.Path]::Combine($ProfileDir, 'AppData\Local')
    foreach ($d in @($r, $l)) { try { [void][IO.Directory]::CreateDirectory($d) } catch { } }
    return @{ roaming = $r; local = $l }
}

function New-CaseTree {
    <#
      A throwaway tree for one case: <work>\<tag>\ holding settings.json and a
      profile\ directory that stands in for $env:USERPROFILE. Pass $null for
      -Bytes to leave the settings file absent, which is one of the cases.
    #>
    param([string]$Tag, $Bytes)

    $dir = Join-Path $script:Work $Tag
    [void][IO.Directory]::CreateDirectory($dir)
    $prof = Join-Path $dir 'profile'
    [void][IO.Directory]::CreateDirectory((Join-Path $prof '.claude'))
    $sp = Join-Path $dir 'settings.json'
    if ($null -ne $Bytes) { [IO.File]::WriteAllBytes($sp, $Bytes) }
    return @{ dir = $dir; profile = $prof; settings = $sp }
}

function Invoke-Setup {
    <#
      Run the installer once with the profile pointed at the case's scratch tree.
      Returns @{ code; out } - a hashtable, so PowerShell does not enumerate it
      away across the function boundary.

      $env:USERPROFILE is RESTORED rather than removed: this process inherited a
      real value and a suite that strips it changes the environment of whatever
      runs after it. The restore is in a finally, so it happens even when the
      child throws. The three plugin variables are handled the same way - see the
      header - and are set to '' rather than removed, which Windows PowerShell
      treats as unset for the -and tests the code under test makes on them.

      stdout is captured and stderr is deliberately NOT merged with 2>&1: in
      Windows PowerShell 5.1 that wraps a native command's stderr in
      NativeCommandError records and corrupts both the output and $?.

      -ExpectsStderr DISCARDS the child's stderr with 2>$null instead. It is
      for the three section 28 cases, whose whole subject is an argument that
      fails PARAMETER BINDING - which prints on stderr by definition. Left
      alone, that stderr becomes a NativeCommandError record in this process's
      error stream, and tests\doc_claims.ps1 runs every sibling suite through
      Start-Job and surfaces it out of Receive-Job, so a deliberate refusal read
      as an unexplained error inside a different guard's output. 2>$null
      suppresses the record; measured, it changes neither $LASTEXITCODE nor
      stdout, which are the only two things those cases assert on. It is a
      switch and not the default because everywhere else an unexpected stderr
      is a thing a maintainer should see.
    #>
    param([string]$ProfileDir, [string[]]$Arguments, [switch]$ExpectsStderr, [string]$ConfigDir = '')

    $prev  = $env:USERPROFILE
    $prevR = $env:CLAUDE_PLUGIN_ROOT
    $prevD = $env:CLAUDE_PLUGIN_DATA
    $prevC = $env:CLAUDE_CODE_PLUGIN_CACHE_DIR
    $prevG = $env:CLAUDE_CONFIG_DIR
    $prevA = $env:APPDATA
    $prevL = $env:LOCALAPPDATA
    $ad    = Get-ScratchAppData -ProfileDir $ProfileDir
    $out  = ''
    $code = 255
    try {
        $env:USERPROFILE                 = $ProfileDir
        $env:CLAUDE_PLUGIN_ROOT          = ''
        $env:CLAUDE_PLUGIN_DATA          = ''
        $env:CLAUDE_CODE_PLUGIN_CACHE_DIR = ''
        $env:CLAUDE_CONFIG_DIR           = $ConfigDir
        $env:APPDATA                     = $ad.roaming
        $env:LOCALAPPDATA                = $ad.local
        if ($ExpectsStderr) {
            # MEASURED, because the obvious spelling aborts this suite. Under
            # $ErrorActionPreference = 'Stop', `2>$null` on a native command
            # turns its stderr into a TERMINATING NativeCommandError - the bare
            # call without the redirection does not. So the preference is
            # lowered for exactly this call and restored in a finally, which is
            # the same contract every other swap in this function keeps.
            $eap = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'SilentlyContinue'
                $lines = & powershell -NoProfile -ExecutionPolicy Bypass -File $SetupPath @Arguments 2>$null
            } finally { $ErrorActionPreference = $eap }
        } else {
            $lines = & powershell -NoProfile -ExecutionPolicy Bypass -File $SetupPath @Arguments
        }
        $code  = if ($null -eq $LASTEXITCODE) { 255 } else { $LASTEXITCODE }
        $out   = ($lines | Out-String)
    } finally {
        $env:USERPROFILE                 = $prev
        $env:CLAUDE_PLUGIN_ROOT          = $prevR
        $env:CLAUDE_PLUGIN_DATA          = $prevD
        $env:CLAUDE_CODE_PLUGIN_CACHE_DIR = $prevC
        $env:CLAUDE_CONFIG_DIR           = $prevG
        $env:APPDATA                     = $prevA
        $env:LOCALAPPDATA                = $prevL
    }
    return @{ code = $code; out = $out }
}

function Invoke-StatusLine {
    <#
      Render the status line once, from the INSTALLED copy under a scratch
      profile, with a payload on stdin.

      IT MUST BE THE COPY, not statusline\statusline.ps1 in place. That file
      derives its plugin roots from $PSScriptRoot's parent among other things, so
      run from the checkout it resolves the real repo root - which exists, holds
      lib\supervisor.ps1 and holds config.json - and the marketplace candidate
      these cases are about is never reached. Copied to <profile>\.claude, which
      is where the installer puts it, that candidate is the only one left.

      Same sandbox as Invoke-Setup: USERPROFILE swapped, the three plugin
      variables cleared, everything restored in a finally.

      -CacheDir SETS CLAUDE_CODE_PLUGIN_CACHE_DIR instead of clearing it, and it
      is a parameter rather than a change to the sandbox because clearing it is
      what every other case here needs. It defaults to empty, so nothing above
      this line behaves differently. It exists because the variable was the one
      supported way to move an install that no case could reach: bin\lwg-setup.ps1
      honours it and statusline\statusline.ps1 did not, so the two files that one
      fix repaired disagreed about where the plugin lived on the same machine.
    #>
    param([string]$ProfileDir, [string]$ScriptPath, [string]$PayloadJson, [string]$CacheDir = '',
          [string]$ConfigDir = '')

    $prev  = $env:USERPROFILE
    $prevR = $env:CLAUDE_PLUGIN_ROOT
    $prevD = $env:CLAUDE_PLUGIN_DATA
    $prevC = $env:CLAUDE_CODE_PLUGIN_CACHE_DIR
    $prevG = $env:CLAUDE_CONFIG_DIR
    $prevA = $env:APPDATA
    $prevL = $env:LOCALAPPDATA
    $ad    = Get-ScratchAppData -ProfileDir $ProfileDir
    $out   = ''
    $code  = 255
    try {
        $env:USERPROFILE                 = $ProfileDir
        $env:CLAUDE_PLUGIN_ROOT          = ''
        $env:CLAUDE_PLUGIN_DATA          = ''
        $env:CLAUDE_CODE_PLUGIN_CACHE_DIR = $CacheDir
        $env:CLAUDE_CONFIG_DIR           = $ConfigDir
        $env:APPDATA                     = $ad.roaming
        $env:LOCALAPPDATA                = $ad.local
        $lines = $PayloadJson | & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath
        $code  = if ($null -eq $LASTEXITCODE) { 255 } else { $LASTEXITCODE }
        $out   = ($lines | Out-String)
    } finally {
        $env:USERPROFILE                 = $prev
        $env:CLAUDE_PLUGIN_ROOT          = $prevR
        $env:CLAUDE_PLUGIN_DATA          = $prevD
        $env:CLAUDE_CODE_PLUGIN_CACHE_DIR = $prevC
        $env:CLAUDE_CONFIG_DIR           = $prevG
        $env:APPDATA                     = $prevA
        $env:LOCALAPPDATA                = $prevL
    }
    return @{ code = $code; out = $out }
}

function Invoke-StatusLineRaw {
    <#
      Render the status line once with EXACT BYTES on stdin, decoding stdout as
      UTF-8 whatever the runner's console code page is, and optionally with a
      culture forced on the child.

      WHY NOT Invoke-StatusLine FOR THESE CASES. That helper pipes a PowerShell
      STRING into the child, and Windows PowerShell 5.1 encodes a string on its
      way into a native command using [Console]::OutputEncoding - the runner's
      console code page, IBM437 on a stock console - and decodes what comes back
      the same way. A payload carrying a non-ASCII character or a byte-order
      mark therefore cannot be delivered through it, and the answer cannot be
      read back, on a runner whose code page is not 65001. Both directions would
      make a case here pass or fail for a reason that is not in the file under
      test. Writing bytes into the child's stdin and setting
      StandardOutputEncoding takes the console out of both ends, and bytes are
      what Claude Code actually writes.

      -Culture runs the script through -Command with CurrentCulture set first.
      It cannot be done from this process: a child powershell.exe takes its
      culture from the user locale, not from the parent's thread. The script
      still reads its payload from [Console]::OpenStandardInput(), which is the
      PROCESS's stdin and not PowerShell's $input, so the -Command wrapper does
      not intercept it - checked before this was written rather than assumed.

      The sandbox is the same contract as Invoke-Setup and Invoke-StatusLine,
      applied to the CHILD's environment block rather than to this process's:
      USERPROFILE is pointed at the case tree and the three plugin variables are
      removed, so nothing here can reach the operator's own .claude directory
      and this process's own environment is never mutated at all.
    #>
    param([string]$ProfileDir, [string]$ScriptPath, [byte[]]$PayloadBytes,
          [string]$CacheDir = '', [string]$Culture = '')

    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName               = 'powershell'
    if ([string]::IsNullOrWhiteSpace($Culture)) {
        $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $ScriptPath + '"'
    } else {
        $inner = "[Threading.Thread]::CurrentThread.CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo('$Culture'); & '" +
                 ($ScriptPath -replace "'", "''") + "'"
        $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -Command "' + ($inner -replace '"', '\"') + '"'
    }
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $psi.EnvironmentVariables['USERPROFILE'] = $ProfileDir
    $adRaw = Get-ScratchAppData -ProfileDir $ProfileDir
    $psi.EnvironmentVariables['APPDATA']      = $adRaw.roaming
    $psi.EnvironmentVariables['LOCALAPPDATA'] = $adRaw.local
    foreach ($v in @('CLAUDE_PLUGIN_ROOT', 'CLAUDE_PLUGIN_DATA', 'CLAUDE_CONFIG_DIR')) {
        if ($psi.EnvironmentVariables.ContainsKey($v)) { [void]$psi.EnvironmentVariables.Remove($v) }
    }
    if ([string]::IsNullOrWhiteSpace($CacheDir)) {
        if ($psi.EnvironmentVariables.ContainsKey('CLAUDE_CODE_PLUGIN_CACHE_DIR')) {
            [void]$psi.EnvironmentVariables.Remove('CLAUDE_CODE_PLUGIN_CACHE_DIR')
        }
    } else {
        $psi.EnvironmentVariables['CLAUDE_CODE_PLUGIN_CACHE_DIR'] = $CacheDir
    }

    $out  = ''
    $code = 255
    $p = [Diagnostics.Process]::Start($psi)
    try {
        $p.StandardInput.BaseStream.Write($PayloadBytes, 0, $PayloadBytes.Length)
        $p.StandardInput.BaseStream.Flush()
        $p.StandardInput.Close()
        $out = $p.StandardOutput.ReadToEnd()
        $p.WaitForExit()
        $code = $p.ExitCode
    } finally { $p.Dispose() }
    return @{ code = $code; out = $out }
}

function Invoke-Git {
    <#
      One git command in one directory, throwing on failure so a broken fixture
      ABORTS the suite rather than producing a case that passes for the wrong
      reason. Identity and signing are forced per invocation with -c, never
      written to a global config: this suite must not change the machine.

      EVERY REMOTE IN THESE FIXTURES IS A LOCAL BARE REPOSITORY under the scratch
      tree. No case here reaches a network, and none can: there is no URL.

      $ErrorActionPreference IS DROPPED TO Continue AROUND THE CALL. This file
      runs under 'Stop', and git writes ordinary progress to stderr - "warning:
      You appear to have cloned an empty repository" on the first clone of a
      fresh bare repo, which is the expected path here. Under 'Stop' that stderr
      becomes a terminating NativeCommandError and ABORTS the suite on a fixture
      that worked perfectly. The exit code is the verdict; stderr is captured for
      the failure message and nothing else.
    #>
    param([string]$WorkDir, [string[]]$GitArgs, [switch]$AllowFail)
    $common = @('-c', 'user.name=lwg-fixture', '-c', 'user.email=lwg-fixture@example.invalid',
                '-c', 'commit.gpgsign=false', '-c', 'init.defaultBranch=main')
    $prevEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $o = & git -C $WorkDir @common @GitArgs 2>&1
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $prevEap }
    $text = ($o | Out-String)
    if (-not $AllowFail -and $code -ne 0) {
        throw "git $($GitArgs -join ' ') exited $code in ${WorkDir}: $text"
    }
    return $text
}

function Invoke-Update {
    <#
      Run bin\lwg-update.ps1 once, with the profile pointed at a case's scratch
      tree so the junction probe and the status-line comparison cannot see the
      operator's own .claude directory. Same env contract as Invoke-Setup.
    #>
    param([string]$ProfileDir, [string[]]$Arguments, [string]$ConfigDir = '')

    $prev  = $env:USERPROFILE
    $prevR = $env:CLAUDE_PLUGIN_ROOT
    $prevD = $env:CLAUDE_PLUGIN_DATA
    $prevG = $env:CLAUDE_CONFIG_DIR
    $prevA = $env:APPDATA
    $prevL = $env:LOCALAPPDATA
    $ad    = Get-ScratchAppData -ProfileDir $ProfileDir
    $out  = ''
    $code = 255
    try {
        $env:USERPROFILE        = $ProfileDir
        $env:CLAUDE_PLUGIN_ROOT = ''
        $env:CLAUDE_PLUGIN_DATA = ''
        $env:CLAUDE_CONFIG_DIR  = $ConfigDir
        $env:APPDATA            = $ad.roaming
        $env:LOCALAPPDATA       = $ad.local
        $lines = & powershell -NoProfile -ExecutionPolicy Bypass -File $UpdatePath @Arguments
        $code  = if ($null -eq $LASTEXITCODE) { 255 } else { $LASTEXITCODE }
        $out   = ($lines | Out-String)
    } finally {
        $env:USERPROFILE        = $prev
        $env:CLAUDE_PLUGIN_ROOT = $prevR
        $env:CLAUDE_PLUGIN_DATA = $prevD
        $env:CLAUDE_CONFIG_DIR  = $prevG
        $env:APPDATA            = $prevA
        $env:LOCALAPPDATA       = $prevL
    }
    return @{ code = $code; out = $out }
}

function New-BehindClone {
    <#
      A bare "remote" and a checkout of it that is genuinely one commit behind,
      built entirely under the scratch tree:

          <Dir>\upstream.git   a bare repository - the remote
          <Dir>\seed           the clone that publishes the incoming commit
          <Dir>\consumer       the checkout under test

      -IncomingFile is the path the incoming commit touches. The consumer is
      FETCHED at the end, so `behind` is already in its tracking ref and an
      -Offline run can see it - which is the state the -Offline/-Apply cases
      need, and is exactly the state an earlier online run leaves behind.

      -BaseFiles is a hashtable of <relative path> = <byte[]> written into the
      seed BEFORE the first commit, so they arrive in the consumer already
      COMMITTED and the checkout is still clean and still exactly one behind.
      Section 26h needs one: bin\lwg-update.ps1 compares the live status line
      against <checkout>\statusline\statusline.ps1, and a consumer clone that
      does not have that file makes the comparison unreachable - the row is not
      merely wrong then, it is absent, which is a third answer no case should be
      satisfied by. Defaults to empty, so every case above this one is unchanged.
    #>
    param([string]$Dir, [string]$IncomingFile = 'notes.md', [hashtable]$BaseFiles = @{})

    $bare     = Join-Path $Dir 'upstream.git'
    $seed     = Join-Path $Dir 'seed'
    $consumer = Join-Path $Dir 'consumer'
    [void][IO.Directory]::CreateDirectory($Dir)

    [void](Invoke-Git -WorkDir $Dir -GitArgs @('init', '--bare', '--quiet', $bare))
    [void](Invoke-Git -WorkDir $Dir -GitArgs @('clone', '--quiet', $bare, $seed))
    [IO.File]::WriteAllText((Join-Path $seed 'seed.md'), "lwg fixture seed`r`n")
    foreach ($rel in @($BaseFiles.Keys)) {
        $p = Join-Path $seed $rel
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $p))
        [IO.File]::WriteAllBytes($p, $BaseFiles[$rel])
    }
    [void](Invoke-Git -WorkDir $seed -GitArgs @('add', '-A'))
    [void](Invoke-Git -WorkDir $seed -GitArgs @('commit', '--quiet', '-m', 'lwg fixture: first commit'))
    [void](Invoke-Git -WorkDir $seed -GitArgs @('push', '--quiet', 'origin', 'HEAD:refs/heads/main'))

    [void](Invoke-Git -WorkDir $Dir  -GitArgs @('clone', '--quiet', '--branch', 'main', $bare, $consumer))

    $inc = Join-Path $seed $IncomingFile
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $inc))
    [IO.File]::WriteAllText($inc, "lwg fixture incoming`r`n")
    [void](Invoke-Git -WorkDir $seed -GitArgs @('add', '-A'))
    [void](Invoke-Git -WorkDir $seed -GitArgs @('commit', '--quiet', '-m', 'lwg fixture: incoming commit'))
    [void](Invoke-Git -WorkDir $seed -GitArgs @('push', '--quiet', 'origin', 'HEAD:refs/heads/main'))

    [void](Invoke-Git -WorkDir $consumer -GitArgs @('fetch', '--quiet'))
    return @{ bare = $bare; seed = $seed; consumer = $consumer }
}

function New-GitFixture {
    <#
      A directory that looks enough like a git checkout for the status line's
      owner/repo segment to resolve one: <dir>\.git\config naming a single
      remote. No git binary is involved and nothing is initialised - the status
      line parses .git/config itself, deliberately, so this is the whole input.

      -Url is the remote URL, so a case can put a non-ASCII character in it.
      The file is written as UTF-8 WITHOUT a BOM, which is what git writes.
    #>
    param([string]$Dir, [string]$Url)
    $g = Join-Path $Dir '.git'
    [void][IO.Directory]::CreateDirectory($g)
    [IO.File]::WriteAllText((Join-Path $g 'config'),
        ("[core]`r`n`trepositoryformatversion = 0`r`n[remote ""origin""]`r`n`turl = $Url`r`n"),
        (New-Object Text.UTF8Encoding($false)))
    return $g
}

function New-MarketplaceRoot {
    <#
      Plant a marketplace install of THIS plugin under a scratch profile, in the
      layout the CLI actually writes:

          <profile>\.claude\plugins\cache\<marketplace>\<plugin>\<version>

      The marketplace and version segments are fixture names with no meaning to
      anything - the CLI sanitises both to [A-Za-z0-9-_] and neither file under
      test parses them. The PLUGIN segment is the real declared name, read from
      .claude-plugin\plugin.json, because both files under test match on it: the
      installer globs the name it derives, and statusline\statusline.ps1 globs
      the name it has spelled literally. If a rename ever separates those two,
      these cases go red - which is the signal wanted, not a nuisance.

      -Contents decides how complete the planted tree is. 'manifest' is enough
      for the installer, which asks only whether an install is THERE. The status
      line probes for files, so its cases plant those files too.

      -PluginsBase RELOCATES the plugins directory, which is what
      CLAUDE_CODE_PLUGIN_CACHE_DIR does on a real machine. It defaults to
      <profile>\.claude\plugins, so every existing caller is unchanged.
    #>
    param([string]$ProfileDir, [string]$PluginName, [string]$Contents = 'manifest', [string]$PluginsBase = '')

    if ([string]::IsNullOrWhiteSpace($PluginsBase)) { $PluginsBase = Join-Path $ProfileDir '.claude\plugins' }
    $root = Join-Path $PluginsBase ("cache\lwg-fixture-marketplace\$PluginName\0.0.0-fixture")
    [void][IO.Directory]::CreateDirectory((Join-Path $root '.claude-plugin'))
    [IO.File]::WriteAllText((Join-Path $root '.claude-plugin\plugin.json'),
        ('{"name":"' + $PluginName + '","version":"0.0.0-fixture"}'))
    if ($Contents -eq 'full') {
        [void][IO.Directory]::CreateDirectory((Join-Path $root 'lib'))
        [void][IO.Directory]::CreateDirectory((Join-Path $root 'agents'))
        [IO.File]::WriteAllText((Join-Path $root 'lib\supervisor.ps1'),   "# lwg-merge-suite fixture - never executed`r`n")
        [IO.File]::WriteAllText((Join-Path $root 'agents\lw-healer.md'),  "lwg-merge-suite fixture`r`n")
    }
    return $root
}

function Get-HookGroupsFor {
    <#
      The registered groups for one event whose script leaf matches $Leaf, as
      the list of .ps1 paths each one runs. Counting these is how the cases ask
      "is this hook registered once or twice", which is the whole question the
      root-independent signature exists to answer.
    #>
    param($Obj, [string]$Event, [string]$Leaf)
    $found = @()
    if ($null -eq $Obj) { return , $found }
    $hooks = $Obj.PSObject.Properties['hooks']
    if ($null -eq $hooks) { return , $found }
    $ev = $hooks.Value.PSObject.Properties[$Event]
    if ($null -eq $ev) { return , $found }
    foreach ($g in @($ev.Value)) {
        $txt = ConvertTo-Json -InputObject $g -Depth 40 -Compress
        $ps1 = @([regex]::Matches($txt, '[^"\\/]+\.ps1') | ForEach-Object { $_.Value.ToLowerInvariant() })
        if ($ps1 -contains $Leaf.ToLowerInvariant()) { $found += , @($ps1) }
    }
    return , $found
}

function Get-BaseHashFrom {
    <#
      The BASEHASH line -Step diff prints. Anchored to the start of the line so
      the same word inside the prose beneath it cannot be picked up instead.
      Returns '' when the line is absent, which every caller treats as a failure
      rather than passing '' on as a hash.
    #>
    param([string]$Text)
    $m = [regex]::Match($Text, '(?m)^BASEHASH:\s*(\S+)\s*$')
    if (-not $m.Success) { return '' }
    return $m.Groups[1].Value
}

function Test-BytesEqual {
    param($A, $B)
    if ($null -eq $A -or $null -eq $B) { return $false }
    if ($A.Length -ne $B.Length) { return $false }
    for ($i = 0; $i -lt $A.Length; $i++) { if ($A[$i] -ne $B[$i]) { return $false } }
    return $true
}

function Get-SettingsBackups {
    <#
      The backups Save-Settings took beside settings.json, with the pre-rollback
      safety copies filtered out the same way Invoke-Rollback filters them - a
      pre-rollback copy is not a backup of an apply and counting it would make
      "exactly one backup" pass for the wrong reason.
    #>
    param([string]$Dir)
    $all = @()
    try { $all = @([IO.Directory]::GetFiles($Dir, 'settings.json.lwg-*.bak')) } catch { }
    return , @($all | Where-Object { $_ -notlike '*.lwg-prerollback-*' })
}

function Get-PreRollbackBackups {
    param([string]$Dir)
    $all = @()
    try { $all = @([IO.Directory]::GetFiles($Dir, 'settings.json.lwg-prerollback-*.bak')) } catch { }
    return , @($all)
}

function Read-Json {
    <# The parsed object of a file on disk, or $null. Never Get-Content -Raw:
       in 5.1 that decodes with the console codepage. #>
    param([string]$Path)
    try { return ([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json) }
    catch { return $null }
}

function Get-TopLevelOrder {
    param($Obj)
    if ($null -eq $Obj) { return @() }
    return @($Obj.PSObject.Properties | ForEach-Object { $_.Name })
}

function Get-KeyJson {
    <# One top-level key's value as compressed JSON - the same oracle
       Compare-UnrelatedKeys uses, so this suite asks the question the installer
       claims to answer. '(absent)' when the key is not there at all, which is
       never equal to a real value. #>
    param($Obj, [string]$Name)
    if ($null -eq $Obj) { return '(absent)' }
    $p = $Obj.PSObject.Properties[$Name]
    if ($null -eq $p) { return '(absent)' }
    return (ConvertTo-Json -InputObject $p.Value -Depth 40 -Compress)
}

# ===========================================================================
# MAIN
# ===========================================================================
$sw = [Diagnostics.Stopwatch]::StartNew()

try {
    Write-Output 'LW-WATCHTOWER installer settings-merge regression suite'
    Write-Output "  repo    : $Root"
    Write-Output "  under   : $SetupPath"
    Write-Output '  sections: statusline, hooks'
    Write-Output '  also   : statusline\statusline.ps1 - plugin-root resolution, payload decoding,'
    Write-Output '           its three numeric states, the HH fault count and the reset clock'
    Write-Output ''

    foreach ($p in @($SetupPath, $RepoStatusLine, $ManifestPath)) {
        if (-not [IO.File]::Exists($p)) { throw "missing: $p" }
    }
    $repoStatusLineBytes = [IO.File]::ReadAllBytes($RepoStatusLine)

    # -------------------------------------------------------------------
    # 0. #118. THE .gitattributes PIN STILL NAMES THE STATUS LINE.
    #
    #    Everything below rests on one property: the status line in the
    #    checkout and the copy the installer writes to ~\.claude\statusline.ps1
    #    are the same bytes, so a Get-FileHash comparison between them means
    #    something. That property is not held by any code - it is held by ONE
    #    LINE in .gitattributes pinning this file back to `text eol=lf` against
    #    the `*.ps1 text eol=crlf` default two lines above it.
    #
    #    A .gitattributes path pattern is anchored to the directory holding the
    #    file, which is the repository root. The payload restructure moved
    #    statusline\statusline.ps1 under lw-watchtower/, and a pin left naming
    #    the old path stops matching SILENTLY: the tracked file starts checking
    #    out CRLF, the installed copy is LF, and the doctor's hash comparison
    #    can never agree again on any clone made after that commit. It is not a
    #    failure anyone would attribute to a moved directory.
    #
    #    ASKED OF GIT RATHER THAN OF THE FILE ON DISK, and that is the point.
    #    Reading bytes would answer "what does this working tree have", which is
    #    whatever the last checkout happened to produce. `git check-attr` answers
    #    "what will every future clone get", which is the property at risk.
    #
    #    RED AT a42b169 with only this hunk applied: the pin named
    #    statusline/statusline.ps1, the path asked about here does not exist at
    #    that commit, and check-attr reported `eol: crlf` from the *.ps1
    #    default.
    # -------------------------------------------------------------------
    $slRelForGit = ((Resolve-Path -LiteralPath $RepoStatusLine).Path.Substring(
                        (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.Length
                    )).TrimStart('\', '/') -replace '\\', '/'
    Push-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
    try {
        $attrOut  = (& git check-attr eol -- $slRelForGit 2>&1 | Out-String).Trim()
        $attrCode = $LASTEXITCODE
    } finally { Pop-Location }
    Add-Result 'the .gitattributes eol=lf pin still names the status line at its tracked path' `
        ($attrCode -eq 0 -and $attrOut -match '(?m):\s*eol:\s*lf\s*$') `
        ("git check-attr eol -- $slRelForGit exited $attrCode and said '$attrOut'; expected 'eol: lf'. " +
         "Without that pin the tracked status line checks out CRLF, the installed copy stays LF, and " +
         "the doctor's Get-FileHash comparison between them can never agree again on any fresh clone.")

    # The declared plugin name, derived. Every fixture path below is built from
    # it rather than from a literal, for the reason lib\common.ps1 gives about
    # the state directory: this id has changed once already, and a suite holding
    # a second hardcoded spelling of it goes stale silently the next time.
    $manifest   = ([IO.File]::ReadAllText($ManifestPath, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF)) | ConvertFrom-Json
    $PluginName = [string]$manifest.name
    if ([string]::IsNullOrWhiteSpace($PluginName)) {
        throw "$ManifestPath declares no name, so no fixture below could be planted where the code under test looks"
    }

    $script:Work = Join-Path ([IO.Path]::GetTempPath()) ('lwg-merge-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
    [void][IO.Directory]::CreateDirectory($script:Work)

    # SECTION 29'S BEFORE-STATE, taken here because it must be taken before the
    # first child process starts and nothing after this line is earlier.
    #
    # Three directories are watched, deduplicated: the PROCESS working directory
    # (which is what a child inherits and therefore what a stray relative write
    # lands in), PowerShell's own location (the two can differ), and the repo
    # root. In CI all three are the same path; on a maintainer's machine they
    # need not be, and watching only one is how this defect would come back
    # under a different `cd`.
    #
    # `existed` is recorded rather than assumed absent: a maintainer whose
    # working directory legitimately holds a Microsoft\ folder must not be told
    # this suite created it. The case asserts APPEARANCE, not presence.
    $script:CacheWatch = @()
    $seenWatch = @{}
    foreach ($c in @([Environment]::CurrentDirectory, (Get-Location).ProviderPath, $Root)) {
        if ([string]::IsNullOrWhiteSpace($c)) { continue }
        $full = $c
        try { $full = [IO.Path]::GetFullPath($c) } catch { }
        $k = $full.TrimEnd('\', '/').ToLowerInvariant()
        if ($seenWatch.ContainsKey($k)) { continue }
        $seenWatch[$k] = $true
        $probe = [IO.Path]::Combine($full, 'Microsoft')
        $script:CacheWatch += [pscustomobject]@{
            dir     = $full
            probe   = $probe
            existed = [IO.Directory]::Exists($probe)
        }
    }

    # -------------------------------------------------------------------
    # 1. A SETTINGS FILE THAT DOES NOT EXIST YET. The commonest first run.
    #    diff must print the literal 'none' rather than omitting the line, and
    #    apply must accept that literal - otherwise a fresh machine can never
    #    get past the BaseHash requirement at all.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'missing' -Bytes $null
    $d = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'diff', '-Section', 'statusline', '-SettingsPath', $t.settings)
    Add-Result 'missing file: diff prints BASEHASH: none' `
        ((Get-BaseHashFrom $d.out) -eq 'none') `
        "diff exited $($d.code) and its BASEHASH line was '$(Get-BaseHashFrom $d.out)', expected 'none'"

    $a = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'apply', '-Section', 'statusline', '-SettingsPath', $t.settings, '-BaseHash', 'none')
    $obj = Read-Json $t.settings
    Add-Result 'missing file: apply -BaseHash none creates a parseable file with statusLine' `
        ($a.code -eq 0 -and [IO.File]::Exists($t.settings) -and $null -ne $obj -and $null -ne $obj.PSObject.Properties['statusLine']) `
        "apply exited $($a.code); file exists=$([IO.File]::Exists($t.settings)); parsed=$($null -ne $obj). Output:`n$($a.out)"
    Add-Result 'missing file: no backup is taken when there was no file to back up' `
        ((Get-SettingsBackups $t.dir).Count -eq 0) `
        "found $((Get-SettingsBackups $t.dir).Count) .bak beside a file that did not exist before the write"

    # -------------------------------------------------------------------
    # 2. APPLY WITH NO -BaseHash. The precondition that makes the diff the
    #    operator approved mean anything. It must REFUSE (5), not fall back to
    #    reading the file's current hash and writing anyway.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'nobase' -Bytes $FixtureBytes
    $a = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'apply', '-Section', 'statusline', '-SettingsPath', $t.settings)
    Add-Result 'apply without -BaseHash -> exit 5 and REFUSED' `
        ($a.code -eq 5 -and $a.out -match 'REFUSED') `
        "exited $($a.code), expected 5 with a REFUSED line. Output:`n$($a.out)"
    Add-Result 'apply without -BaseHash leaves the file byte-identical' `
        (Test-BytesEqual ([IO.File]::ReadAllBytes($t.settings)) $FixtureBytes) `
        'the settings file changed on a run that said NOTHING WAS WRITTEN'

    # -------------------------------------------------------------------
    # 3. CONCURRENT MODIFICATION. The file is rewritten between the diff and
    #    the apply - which Claude Code itself does. Merging onto a file the
    #    operator never saw silently discards whatever that change was, so the
    #    write must be refused with 4 and NOTHING may be written, not even a
    #    backup: a backup is a write, and one taken here would leave a .bak the
    #    operator has no reason to expect.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'concurrent' -Bytes $FixtureBytes
    $d = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'diff', '-Section', 'statusline', '-SettingsPath', $t.settings)
    $stale = Get-BaseHashFrom $d.out

    $mutatedText  = $FixtureText -replace '"alpha": "keep me"', '"alpha": "somebody else wrote this"'
    $mutatedBytes = $Utf8NoBom.GetBytes($mutatedText)
    [IO.File]::WriteAllBytes($t.settings, $mutatedBytes)

    $a = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'apply', '-Section', 'statusline', '-SettingsPath', $t.settings, '-BaseHash', $stale)
    Add-Result 'stale BaseHash -> exit 4 and CONCURRENT MODIFICATION' `
        ($stale -ne '' -and $a.code -eq 4 -and $a.out -match 'CONCURRENT MODIFICATION') `
        "diff hash was '$stale'; apply exited $($a.code), expected 4 naming CONCURRENT MODIFICATION. Output:`n$($a.out)"
    Add-Result 'stale BaseHash: the file is left as the OTHER writer left it' `
        (Test-BytesEqual ([IO.File]::ReadAllBytes($t.settings)) $mutatedBytes) `
        'the concurrent write was overwritten - which is the data loss the hash check exists to prevent'
    Add-Result 'stale BaseHash: no backup is taken' `
        ((Get-SettingsBackups $t.dir).Count -eq 0) `
        "found $((Get-SettingsBackups $t.dir).Count) .bak on a run that wrote nothing"

    # -------------------------------------------------------------------
    # 3b. CONCURRENT MODIFICATION, AND THE FILES OUTSIDE settings.json.
    #     The group above proves settings.json is left alone. It cannot see the
    #     other half: Invoke-Apply performs the section's file copies BEFORE it
    #     calls Save-Settings, and the concurrency check lived inside
    #     Save-Settings - so a refusal that printed
    #     'CONCURRENT MODIFICATION - NOTHING WAS WRITTEN.' and exited 4 had
    #     already replaced the operator's own ~\.claude\statusline.ps1. Exit 4 is
    #     defined in bin\lwg-setup.ps1's header as "NOTHING was written".
    #
    #     THE FIXTURE HAS TO PLANT A DIFFERENT statusline.ps1. With no file
    #     there the copy branch still runs (it CREATES one), but "the operator's
    #     own file was destroyed" is the claim worth pinning, and it needs a file
    #     that was theirs. With an IDENTICAL one the installer plans no copy at
    #     all and the case would be green for a reason that is not the fix.
    #     Measured on the fixture: the diff reports TO APPLY (2 change(s)) - the
    #     copy and the settings key - so the run really does reach the copy loop.
    #
    #     BASELINE: fd8d023. Measured there: 'BACKUP ... statusline.ps1.lwg-...bak'
    #     and 'COPIED ...\.claude\statusline.ps1' printed above the refusal, the
    #     planted file replaced, one .bak beside it.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'concurrent-copy' -Bytes $FixtureBytes
    $ownStatusLine = Join-Path (Join-Path $t.profile '.claude') 'statusline.ps1'
    $ownBytes      = $Utf8NoBom.GetBytes("# the operator's own status line - deliberately not the tracked one`r`n")
    [IO.File]::WriteAllBytes($ownStatusLine, $ownBytes)

    $d = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'diff', '-Section', 'statusline', '-SettingsPath', $t.settings)
    $stale = Get-BaseHashFrom $d.out
    if ($d.out -notmatch '(?m)^TO APPLY \((\d+) change') { throw 'the concurrent-copy fixture planned no change, so the apply below could never reach the file-copy loop and the cases would pass vacuously' }
    [IO.File]::WriteAllBytes($t.settings, $mutatedBytes)

    $a = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'apply', '-Section', 'statusline', '-SettingsPath', $t.settings, '-BaseHash', $stale)
    Add-Result 'concurrent + copy mode: the operator''s own statusline.ps1 is NOT overwritten' `
        ($a.code -eq 4 -and (Test-BytesEqual ([IO.File]::ReadAllBytes($ownStatusLine)) $ownBytes)) `
        "apply exited $($a.code) and the status-line file changed on a run whose headline says nothing was written. Output:`n$($a.out)"
    Add-Result 'concurrent + copy mode: no .bak is left beside the status-line file' `
        (@([IO.Directory]::GetFiles((Join-Path $t.profile '.claude'), 'statusline.ps1.lwg-*.bak')).Count -eq 0) `
        'a refusal left a backup of a file it also says it did not touch, which is an artefact the operator has no reason to expect'
    Add-Result 'concurrent + copy mode: the refusal is printed BEFORE any COPIED or BACKUP line' `
        ($a.out -notmatch '(?m)^(COPIED|BACKUP) ') `
        "the run reported a completed file write and then said NOTHING WAS WRITTEN. Output:`n$($a.out)"

    # -------------------------------------------------------------------
    # 4-9, 12, 16. THE MAIN TREE. One apply, then a second, then a rollback,
    #    all against the same fixture, because the properties that matter are
    #    about what one run does to the NEXT one.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'main' -Bytes $FixtureBytes
    $before = Read-Json $t.settings

    $d = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'diff', '-Section', 'statusline', '-SettingsPath', $t.settings)
    $h = Get-BaseHashFrom $d.out
    if ($h -eq '' -or $h -eq 'none') { throw "the diff of the main fixture printed no usable BASEHASH ('$h'), so no apply case below could establish anything" }

    $a = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'apply', '-Section', 'statusline', '-SettingsPath', $t.settings, '-BaseHash', $h)
    Add-Result 'apply on a populated fixture -> exit 0' ($a.code -eq 0) `
        "exited $($a.code), expected 0. Output:`n$($a.out)"

    $after = Read-Json $t.settings

    # 4a. ORDER. Add-Member -Force would move the replaced key to the end; the
    #     whole point of Set-PropValue is that it does not.
    $order = Get-TopLevelOrder $after
    Add-Result 'unrelated keys: top-level ORDER is unchanged' `
        ((($order -join ',') -eq ($ExpectedOrder -join ','))) `
        "order after apply is '$($order -join ', ')', expected '$($ExpectedOrder -join ', ')' - a key that was replaced in place has been moved to the end of the file"

    # 4b. VALUES. The same compressed-JSON comparison Compare-UnrelatedKeys makes.
    foreach ($k in @('zeta', 'permissions', 'alpha')) {
        $b4 = Get-KeyJson $before $k
        $af = Get-KeyJson $after  $k
        Add-Result "unrelated keys: '$k' is value-identical after apply" ($b4 -eq $af) `
            "before: $b4`n        after : $af"
    }

    # 5. EXACTLY ONE BACKUP, HOLDING THE ORIGINAL BYTES. Not "at least one":
    #    an installer that backs up twice leaves the operator guessing which
    #    file is the one to restore.
    #
    #    THE SECOND CASE IS NOT GUARDED ON THE FIRST (#136 instance 3). It used
    #    to sit inside `if ($baks.Count -eq 1)`, so an installer that took two
    #    backups failed the count case and DELETED the only case that reads a
    #    backup's bytes - the tally shrank by one with no skip line, in exactly
    #    the state where "which file is the one to restore" matters most. A case
    #    a defect can remove is a case that reports coverage it is not
    #    providing. It now runs always and fails honestly, naming which of the
    #    two things went wrong; the same hoist was made for the two sibling
    #    instances in tests\gate_delegate.ps1 and tests\stop_behaviour.ps1.
    $baks = Get-SettingsBackups $t.dir
    Add-Result 'exactly one settings backup after one apply' ($baks.Count -eq 1) `
        "found $($baks.Count): $($baks -join ', ')"
    $bakBytes = $null
    if ($baks.Count -ge 1) { try { $bakBytes = [IO.File]::ReadAllBytes($baks[0]) } catch { } }
    Add-Result 'the backup holds the original bytes exactly' `
        ($baks.Count -eq 1 -and (Test-BytesEqual $bakBytes $FixtureBytes)) `
        $(if ($baks.Count -ne 1) {
            "there is no single backup to read: found $($baks.Count) ($($baks -join ', ')). This case is NOT skipped when the count is wrong - an installer that took two backups would otherwise delete the only case that reads a backup at all."
          } else {
            'the backup is not a byte copy of the file that was replaced, so restoring it does not restore the original'
          })

    # 7. THE OPERATOR'S OWN TUNING. 45, not the installer's default of 120.
    Add-Result 'statusLine.refreshInterval 45 is preserved, not reset to the default' `
        ($null -ne $after -and [int]$after.statusLine.refreshInterval -eq 45) `
        "refreshInterval is '$($after.statusLine.refreshInterval)', expected 45"

    # 16. A ONE-ELEMENT ARRAY IS STILL AN ARRAY. PowerShell's JSON round-trip is
    #     where a one-element array becomes a bare string and an absent one
    #     becomes @($null); permissions.ask is the fixture's canary for both.
    #
    #     WHICH GUARD THIS ACTUALLY COVERS, because it is not the obvious one.
    #     Get-PropArray's `, @()` is the installer's named defence against both
    #     shapes, and it is NOT on this path - it is called only from the
    #     permissions and hooks plans. What keeps permissions.ask an array
    #     through a statusline apply is the full-depth serialiser round-trip:
    #     Copy-JsonObject and ConvertTo-CanonicalJson both at -Depth 40. That is
    #     what this case falsifies. It was confirmed to go red - reporting
    #     "came back as type 'String'" - against a build whose canonical
    #     serialiser had its depth reduced, and it stayed green against the
    #     Get-PropArray break, which is how the scoping above was established
    #     rather than assumed.
    #
    #     THE NULL-INJECTION CASE THAT USED TO SIT HERE HAS MOVED TO SECTION 31
    #     (#137 instance 4). It asserted that the written file carries no bare
    #     `null` as an array member, which is the shape Get-PropArray's `, @()`
    #     exists to prevent - on a path where Get-PropArray is never called. The
    #     measurement recorded two paragraphs above is what settled it: the
    #     ADJACENT case here was confirmed red against a reduced serialiser
    #     depth and stayed GREEN against the Get-PropArray break, so on this
    #     fixture nothing could ever have produced the null it looked for. It
    #     was a row on a published tally for a check that could not fail. It is
    #     relocated rather than deleted - deleting it moves a case count quoted
    #     in tracked pages, and the assertion is a good one in the place where
    #     the defence it names actually runs.
    $askVal = $null
    if ($null -ne $after -and $null -ne $after.PSObject.Properties['permissions']) {
        $ap = $after.permissions.PSObject.Properties['ask']
        if ($null -ne $ap) { $askVal = $ap.Value }
    }
    Add-Result 'a one-element permissions.ask survives as an array of one string' `
        ($askVal -is [array] -and @($askVal).Count -eq 1 -and @($askVal)[0] -is [string] -and @($askVal)[0] -eq 'Bash(lwg-noop-fixture)') `
        "permissions.ask came back as type '$(if ($null -eq $askVal) { 'null' } else { $askVal.GetType().Name })' with value '$($askVal -join '|')' - a one-element array flattened to a bare string, or a null was injected into it"

    # 8a. THE COPYFILE EXTRA ACTION, create branch. The settings key is pointed
    #     at a file, so the file has to be there - and has to be the tracked one.
    $copied = Join-Path (Join-Path $t.profile '.claude') 'statusline.ps1'
    Add-Result 'copy mode: the apply reports COPIED' ($a.out -match 'COPIED') `
        "no COPIED line in the apply output:`n$($a.out)"
    Add-Result 'copy mode: the copy exists under the scratch profile and matches the tracked file' `
        ([IO.File]::Exists($copied) -and (Test-BytesEqual ([IO.File]::ReadAllBytes($copied)) $repoStatusLineBytes)) `
        "expected a byte copy of $RepoStatusLine at $copied"

    # 6. IDEMPOTENCE. A second run must change nothing, take no backup and not
    #    even touch the timestamp - which is what makes re-running setup safe.
    $bytesAfterApply = [IO.File]::ReadAllBytes($t.settings)
    $d2 = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'diff', '-Section', 'statusline', '-SettingsPath', $t.settings)
    $h2 = Get-BaseHashFrom $d2.out
    $a2 = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'apply', '-Section', 'statusline', '-SettingsPath', $t.settings, '-BaseHash', $h2)
    Add-Result 'second run -> exit 0 and says it is already in the state requested' `
        ($a2.code -eq 0 -and $a2.out -match 'Already in the state requested') `
        "exited $($a2.code). Output:`n$($a2.out)"
    Add-Result 'second run takes no second backup' ((Get-SettingsBackups $t.dir).Count -eq 1) `
        "there are now $((Get-SettingsBackups $t.dir).Count) backups; a run that wrote nothing took one"
    Add-Result 'second run leaves the file byte-identical' `
        (Test-BytesEqual ([IO.File]::ReadAllBytes($t.settings)) $bytesAfterApply) `
        'the file changed on a run that reported no change'

    # 9. ROLLBACK, BYTE FOR BYTE. The promise the apply output makes in its own
    #    closing lines. Value-identical is not good enough here: the operator is
    #    being told they can get their file back.
    $r = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'rollback', '-SettingsPath', $t.settings)
    Add-Result 'rollback -> exit 0' ($r.code -eq 0) "exited $($r.code). Output:`n$($r.out)"
    Add-Result 'rollback restores the original bytes exactly' `
        (Test-BytesEqual ([IO.File]::ReadAllBytes($t.settings)) $FixtureBytes) `
        'the restored file is not byte-identical to the fixture that was replaced'
    $pre = Get-PreRollbackBackups $t.dir
    Add-Result 'rollback keeps a pre-rollback copy of what it overwrote' `
        ($pre.Count -eq 1 -and (Test-BytesEqual ([IO.File]::ReadAllBytes($pre[0])) $bytesAfterApply)) `
        "found $($pre.Count) pre-rollback copies; the applied state must be recoverable after a rollback too"

    # 12. THE PRE-ROLLBACK EXCLUSION. Offering that copy as a restore target
    #     would let repeated rollbacks walk FORWARDS again, undoing the undo.
    $r2 = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'rollback', '-SettingsPath', $t.settings, '-DryRun')
    Add-Result 'rollback -DryRun -> exit 0 and offers the real backup' `
        ($r2.code -eq 0 -and $baks.Count -eq 1 -and $r2.out -match [regex]::Escape((Split-Path -Leaf $baks[0]))) `
        "exited $($r2.code) and did not name $(if ($baks.Count -eq 1) { Split-Path -Leaf $baks[0] } else { 'the backup' }). Output:`n$($r2.out)"
    Add-Result 'rollback never offers a pre-rollback copy as a restore target' `
        ($r2.out -notmatch 'lwg-prerollback-') `
        "the pre-rollback copy is listed as something to restore TO, which lets repeated rollbacks walk forwards:`n$($r2.out)"

    # -------------------------------------------------------------------
    # 8b. THE COPYFILE OVERWRITE BRANCH. A status line is already installed and
    #     DIFFERS from the tracked one - the case that costs most, because the
    #     file being overwritten may be a fix somebody made in place.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'overwrite' -Bytes $FixtureBytes
    $planted      = Join-Path (Join-Path $t.profile '.claude') 'statusline.ps1'
    $plantedBytes = $Utf8NoBom.GetBytes("# lwg-merge-suite placeholder - deliberately not the tracked status line`r`n")
    [IO.File]::WriteAllBytes($planted, $plantedBytes)

    $d = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'diff', '-Section', 'statusline', '-SettingsPath', $t.settings)
    Add-Result 'copy mode, target differs: the diff says OVERWRITE, not create' `
        ($d.out -match 'ACTION 1\s+OVERWRITE') `
        "the diff does not warn that an existing status line would be overwritten:`n$($d.out)"

    $h = Get-BaseHashFrom $d.out
    $a = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'apply', '-Section', 'statusline', '-SettingsPath', $t.settings, '-BaseHash', $h)
    Add-Result 'copy mode, target differs: apply reports COPIED' `
        ($a.code -eq 0 -and $a.out -match 'COPIED') `
        "exited $($a.code). Output:`n$($a.out)"
    $sideBaks = @([IO.Directory]::GetFiles((Split-Path -Parent $planted), 'statusline.ps1.lwg-*.bak'))
    Add-Result 'copy mode, target differs: the overwritten file is kept as a .bak beside it' `
        ($a.out -match 'BACKUP\s+\S*statusline\.ps1\.lwg-' -and $sideBaks.Count -eq 1 -and (Test-BytesEqual ([IO.File]::ReadAllBytes($sideBaks[0])) $plantedBytes)) `
        "found $($sideBaks.Count) .bak beside the status line; the file that was overwritten must be recoverable. Output:`n$($a.out)"
    Add-Result 'copy mode, target differs: the tracked file is what landed' `
        (Test-BytesEqual ([IO.File]::ReadAllBytes($planted)) $repoStatusLineBytes) `
        'the installed status line is not a byte copy of the tracked one'

    # -------------------------------------------------------------------
    # 13. BOM ROUND-TRIP. Read-SettingsFile records hadBom and the writer
    #     normalises to no-BOM. That is a real change to the operator's file,
    #     so the backup must hold the ORIGINAL bytes - BOM included - and
    #     rollback must put them back exactly.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'bom' -Bytes $FixtureBom
    $d = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'diff', '-Section', 'statusline', '-SettingsPath', $t.settings)
    $h = Get-BaseHashFrom $d.out
    $a = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'apply', '-Section', 'statusline', '-SettingsPath', $t.settings, '-BaseHash', $h)
    Add-Result 'BOM: apply succeeds on a BOM-prefixed settings file' ($a.code -eq 0) `
        "exited $($a.code). Output:`n$($a.out)"
    $baks = Get-SettingsBackups $t.dir
    Add-Result 'BOM: the backup preserves the BOM bytes exactly' `
        ($baks.Count -eq 1 -and (Test-BytesEqual ([IO.File]::ReadAllBytes($baks[0])) $FixtureBom)) `
        "found $($baks.Count) backup(s); a backup that has dropped the BOM cannot restore the original file"
    $newBytes = [IO.File]::ReadAllBytes($t.settings)
    Add-Result 'BOM: the newly written file has no BOM' `
        ($newBytes.Length -ge 3 -and -not ($newBytes[0] -eq 0xEF -and $newBytes[1] -eq 0xBB -and $newBytes[2] -eq 0xBF)) `
        'the writer is documented as UTF8Encoding($false) and must not introduce a BOM'
    $r = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'rollback', '-SettingsPath', $t.settings)
    Add-Result 'BOM: rollback restores the BOM-prefixed original byte for byte' `
        ($r.code -eq 0 -and (Test-BytesEqual ([IO.File]::ReadAllBytes($t.settings)) $FixtureBom)) `
        "rollback exited $($r.code) and the result is not the original bytes. Output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 14. A TARGET THAT DOES NOT PARSE. Overwriting a settings file the
    #     installer cannot read is exactly how every other setting in it gets
    #     lost, so both steps must refuse rather than merge onto an empty
    #     object and write a "clean" file over the operator's broken one.
    # -------------------------------------------------------------------
    $badBytes = $Utf8NoBom.GetBytes("{ `"statusLine`": { this is not json" + "`r`n")
    $t = New-CaseTree -Tag 'unparseable' -Bytes $badBytes
    $d = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'diff', '-Section', 'statusline', '-SettingsPath', $t.settings)
    Add-Result 'unparseable target: diff -> exit 5 and REFUSED' `
        ($d.code -eq 5 -and $d.out -match 'REFUSED') `
        "exited $($d.code), expected 5. Output:`n$($d.out)"
    # The BASEHASH line is printed BEFORE the refusal, on purpose, so a caller
    # can still name the file state it saw. Feeding it back proves the apply
    # refuses on the PARSE, not merely on a missing hash.
    $h = Get-BaseHashFrom $d.out
    $a = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'apply', '-Section', 'statusline', '-SettingsPath', $t.settings, '-BaseHash', $h)
    Add-Result 'unparseable target: apply with a MATCHING BaseHash still -> exit 5' `
        ($h -ne '' -and $h -ne 'none' -and $a.code -eq 5 -and $a.out -match 'does not parse') `
        "hash '$h', apply exited $($a.code), expected 5 refusing on the parse. Output:`n$($a.out)"
    Add-Result 'unparseable target: the broken file is left exactly as it was' `
        (Test-BytesEqual ([IO.File]::ReadAllBytes($t.settings)) $badBytes) `
        'the installer rewrote a settings file it could not read'

    # -------------------------------------------------------------------
    # 15. -DryRun. Everything except the write: the merge is built and
    #     validated, and neither the settings file nor the status-line copy is
    #     touched. A dry run that leaves a .bak behind is not a dry run.
    #
    #     THE GROUP USED TO BE THREE CASES AND TWO OF THEM WERE PURE NEGATIVES -
    #     no backup, no copy, bytes unchanged - with the only positive being
    #     `-match 'DRY RUN'`, which the banner at the TOP of Invoke-Apply
    #     satisfies on its own. So the load-bearing half of the comment above,
    #     "the merge is built and validated", was asserted by nothing: a -DryRun
    #     that returned straight after the banner passed all three. The fourth
    #     case below anchors on the completion line instead, which is printed
    #     after Save-Settings has serialised the merge and can name the byte
    #     count it produced, and the first case is now anchored to the banner
    #     LINE so the two cannot be satisfied by the same string.
    #
    #     BASELINE: this is a coverage defect, not a behaviour defect - the
    #     installer builds the merge correctly today and did at fd8d023, so a
    #     case written against fd8d023 would be GREEN there and prove nothing.
    #     Proven red instead against a SNAPSHOT of this working tree with the
    #     -DryRun branch moved up to return immediately after the banner at
    #     Invoke-Apply's `if ($DryRun) { Write-Output 'DRY RUN - ...' }`. Against
    #     that build the three cases below pass and this one fails.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'dryrun' -Bytes $FixtureBytes
    $d = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'diff', '-Section', 'statusline', '-SettingsPath', $t.settings)
    $h = Get-BaseHashFrom $d.out
    $a = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'apply', '-Section', 'statusline', '-SettingsPath', $t.settings, '-BaseHash', $h, '-DryRun')
    Add-Result 'apply -DryRun -> exit 0 and says DRY RUN' `
        ($a.code -eq 0 -and $a.out -match '(?m)^DRY RUN - nothing will be written by this invocation\.\s*$') `
        "exited $($a.code). Output:`n$($a.out)"
    Add-Result 'apply -DryRun builds and validates the merge, and names the byte count it produced' `
        ($a.out -match 'DRY RUN COMPLETE\. The merge was built and validated; it would have written \d+ bytes') `
        "the dry run never reported a validated merge with a byte count, so nothing here establishes it did the work the flag exists to do - only that it printed the banner and stopped. Output:`n$($a.out)"
    Add-Result 'apply -DryRun writes nothing: no backup, file byte-identical' `
        ((Get-SettingsBackups $t.dir).Count -eq 0 -and (Test-BytesEqual ([IO.File]::ReadAllBytes($t.settings)) $FixtureBytes)) `
        "backups: $((Get-SettingsBackups $t.dir).Count); the settings file must be untouched"
    Add-Result 'apply -DryRun does not copy the status-line file either' `
        (-not [IO.File]::Exists((Join-Path (Join-Path $t.profile '.claude') 'statusline.ps1'))) `
        'the status-line copy happens before the settings write and must also be suppressed by -DryRun'

    # -------------------------------------------------------------------
    # 10. ROLLBACK WITH NOTHING TO RESTORE. Setup only ever restores a backup
    #     IT took; it must not guess that some other .bak beside the file is
    #     the right one, and it must not report success having restored
    #     nothing.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'norollback' -Bytes $FixtureBytes
    $r = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'rollback', '-SettingsPath', $t.settings)
    Add-Result 'rollback with no backup -> exit 5, nothing restored' `
        ($r.code -eq 5 -and (Test-BytesEqual ([IO.File]::ReadAllBytes($t.settings)) $FixtureBytes)) `
        "exited $($r.code), expected 5. Output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 11. A BACKUP THAT DOES NOT ITSELF PARSE. Restoring an unreadable file
    #     over a readable one makes things worse, and it is the one rollback
    #     that cannot be rolled back.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'badbackup' -Bytes $FixtureBytes
    $garbage = Join-Path $t.dir 'settings.json.lwg-19990101-000000.bak'
    [IO.File]::WriteAllBytes($garbage, $Utf8NoBom.GetBytes("{ not json either" + "`r`n"))
    $r = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'rollback', '-SettingsPath', $t.settings, '-BackupPath', $garbage)
    Add-Result 'rollback refuses a backup that does not parse -> exit 5' `
        ($r.code -eq 5 -and $r.out -match 'does not itself parse') `
        "exited $($r.code), expected 5. Output:`n$($r.out)"
    Add-Result 'rollback refusal leaves the target byte-identical' `
        (Test-BytesEqual ([IO.File]::ReadAllBytes($t.settings)) $FixtureBytes) `
        'an unreadable backup was copied over a readable settings file'
    Add-Result 'rollback refusal takes no pre-rollback copy' `
        ((Get-PreRollbackBackups $t.dir).Count -eq 0) `
        'a run that restored nothing still wrote a file beside the target'

    # -------------------------------------------------------------------
    # 21. A WRITE THAT FAILS, AND WHAT IT LEAVES BEHIND.
    #
    #     Save-Settings stages the new file in "<target>.lwg-tmp-<guid>" beside
    #     the target and deleted it as the last statement of the SUCCESS path, so
    #     every failed write left one - holding a full copy of the operator's
    #     entire settings, in their config directory, permanently. Nothing in the
    #     plugin removed it: Invoke-Rollback globs "<leaf>.lwg-*.bak" and the tmp
    #     name has no .bak suffix, and neither the uninstaller nor the doctor
    #     knows the name.
    #
    #     THE READ-ONLY ATTRIBUTE is how the write is made to fail without
    #     inventing a fault inside the installer, and it is a real state: an
    #     operator sets it, a dotfiles manager sets it, a restore from backup
    #     media sets it. The attribute is cleared immediately afterwards so the
    #     suite's own cleanup can remove the tree.
    #
    #     THE FIRST CASE IS A CONTROL and passes at fd8d023 too. Without it the
    #     "no orphan" case below is satisfied by a build that cleared the
    #     attribute and wrote anyway - which is the one wrong-direction fix an
    #     installer must never make to somebody else's file.
    #
    #     BASELINE: fd8d023. Measured there: exit 1, "FAILED: the write failed:
    #     ... Access to the path ... is denied.", and one
    #     settings.json.lwg-tmp-<guid> left in the directory.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'readonly' -Bytes $FixtureBytes
    $d = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'diff', '-Section', 'statusline', '-SettingsPath', $t.settings)
    $h = Get-BaseHashFrom $d.out
    (New-Object IO.FileInfo($t.settings)).IsReadOnly = $true
    try {
        $a = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'apply', '-Section', 'statusline', '-SettingsPath', $t.settings, '-BaseHash', $h)
    } finally {
        try { (New-Object IO.FileInfo($t.settings)).IsReadOnly = $false } catch { }
    }
    Add-Result 'CONTROL read-only target: the write FAILS and the file keeps its original bytes' `
        ($a.code -eq 1 -and $a.out -match 'FAILED' -and (Test-BytesEqual ([IO.File]::ReadAllBytes($t.settings)) $FixtureBytes)) `
        "exited $($a.code), expected 1 with a FAILED line and the target untouched - an installer that clears somebody else's read-only attribute to get its write through is worse than one that stops. Output:`n$($a.out)"
    $tmps = @([IO.Directory]::GetFiles($t.dir, 'settings.json.lwg-tmp-*'))
    Add-Result 'a failed write leaves no settings.json.lwg-tmp-* staging file behind' `
        ($tmps.Count -eq 0) `
        "found $($tmps.Count): $($tmps -join ', ') - each holds a full copy of the operator's entire settings and nothing in this plugin ever removes one"

    # THE SAME FIXTURE ALSO REACHES THE DISCLOSURE, so it is asserted here rather
    # than left to be read. Invoke-Apply copies the status-line file before it
    # writes settings.json, so a run that FAILS on the settings write has already
    # replaced a file the operator may have written themselves - and until this
    # wave it said only 'FAILED' and 'A backup exists at <settings backup>',
    # which names the wrong file. The exit-4 twin of this block is NOT covered:
    # the concurrency check now runs before the copy loop, so reaching it needs
    # settings.json to move DURING the loop, and no case induces that.
    Add-Result 'a failed write NAMES the file it had already copied and says rollback will not restore it' `
        ($a.out -match 'THIS RUN HAD ALREADY WRITTEN THE FILE\(S\) BELOW' -and $a.out -match 'statusline\.ps1\s+\((created by this run|the file it replaced is at)') `
        "the run replaced a file under the operator's profile, failed, and reported only the settings backup - which is not the file it changed. Output:`n$($a.out)"

    # -------------------------------------------------------------------
    # 27. -StatusLineMode junction, AND WHAT THE SKILLS ENTRY ACTUALLY IS.
    #
    #     THE NUMBER IS 27 BECAUSE 16 IS TAKEN, by the one-element-array case
    #     above. The numbers here are identifiers, not an order: 21 already sits
    #     between 15 and 22, and 24 and 25 are deliberately never reused.
    #
    #     The reason an operator picks junction over copy is one sentence this
    #     section prints: "the indicator can never fall behind the original,
    #     because there is only one file". That is true while
    #     ~\.claude\skills\<plugin> is a reparse point. When it is an ORDINARY
    #     DIRECTORY - a marketplace install, a hand-copied plugin folder, a
    #     restore that turned a link into its contents - there are two files,
    #     they drift exactly as copy mode's do, and the sentence is false about
    #     the single property the mode was chosen for.
    #
    #     DETECTION ALREADY HAD THE ANSWER. Get-Detection reads the
    #     reparse-point attribute into $D.skillIsLink and -Step detect prints
    #     it in the 'skills entry' row. New-StatusLinePlan never asked.
    #
    #     THE FIRST TWO SHAPES BOTH PLANT A REAL statusline.ps1 AT THE WIRED-UP
    #     PATH, so the "does not exist right now" warning fires in neither and
    #     the wording is the only thing that can differ between them. That
    #     identity is the defect: same words, opposite truth.
    #
    #     THREE SHAPES, NOT TWO, because $D.skillIsLink is $false for a real
    #     directory AND for no skills entry at all. A two-way test would let a
    #     fix tell an operator who has installed nothing that they have a copy,
    #     so the third shape below pins that it does not.
    #
    #     THE JUNCTION TARGET IS A THROWAWAY DIRECTORY INSIDE THE CASE TREE and
    #     never this checkout, and the reparse point is removed with
    #     [IO.Directory]::Delete($link) - which unlinks only - in a finally, so
    #     neither that call nor the suite's own recursive cleanup can walk
    #     THROUGH the junction and delete the target's contents. mklink /J
    #     makes a directory junction and needs no elevation; if it cannot be
    #     created the case ABORTS rather than passing on an absent fixture.
    #
    #     BASELINE origin/main (a2d9447), measured, not read: all three shapes
    #     print the identical block - "TRADE-OFF: the indicator can never fall
    #     behind the original, because there is only one file." - while the SAME
    #     run's -Step detect prints "[junction/link]" for the first and "[a real
    #     directory, NOT a link]" for the second.
    #
    #     WHICH OF THESE IS A CONTROL, EXACTLY ONE: the first assertion below,
    #     that a genuine junction is still promised no drift. It is GREEN at
    #     that baseline and is here because the cheapest wrong fix is to delete
    #     the sentence - over a real link there IS only one file and the
    #     operator is owed it. Every other assertion in this block goes RED
    #     there, the second one included: the baseline never says which shape it
    #     checked, about any of the three.
    # -------------------------------------------------------------------
    $noDrift = 'can never fall behind the original, because there is'

    $t = New-CaseTree -Tag 'junction-link' -Bytes $FixtureBytes
    $linkTarget = Join-Path $t.dir 'a-checkout-somewhere-else'
    [void][IO.Directory]::CreateDirectory((Join-Path $linkTarget 'statusline'))
    [IO.File]::Copy($RepoStatusLine, (Join-Path $linkTarget 'statusline\statusline.ps1'), $true)
    $skillsDir = Join-Path (Join-Path $t.profile '.claude') 'skills'
    [void][IO.Directory]::CreateDirectory($skillsDir)
    $link = Join-Path $skillsDir $PluginName
    $mk = ''
    $prevEap = $ErrorActionPreference
    try { $ErrorActionPreference = 'Continue'; $mk = (& cmd /c mklink /J "$link" "$linkTarget" 2>&1 | Out-String) } finally { $ErrorActionPreference = $prevEap }
    $li = New-Object IO.DirectoryInfo($link)
    if (-not [IO.Directory]::Exists($link) -or (($li.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)) {
        throw "could not create a directory junction at ${link}: $mk. This case cannot tell a link from a directory without one, and a skip would be a false pass."
    }
    try {
        $dj = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'diff', '-Section', 'statusline', '-SettingsPath', $t.settings, '-StatusLineMode', 'junction')
        $det = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'detect', '-SettingsPath', $t.settings)
    } finally {
        # UNLINK ONLY. Never Remove-Item -Recurse and never Directory.Delete
        # with $true on a reparse point - both can walk through it and empty
        # the TARGET rather than removing the link.
        try { [IO.Directory]::Delete($link) } catch { }
    }
    Add-Result 'CONTROL junction mode over a REAL junction still promises the indicator cannot fall behind' `
        ($dj.code -eq 0 -and $dj.out -match [regex]::Escape($noDrift)) `
        "exited $($dj.code). Over a genuine reparse point there IS only one file, so this sentence is true and the operator is owed it - a fix that deleted it outright would be an overcorrection. Output:`n$($dj.out)"
    # The TARGET is matched on its leaf and not on the full path: what the plan
    # prints comes back from Get-Item .Target, and a temp root that resolves
    # through an 8.3 segment or arrives with a \\?\ prefix would fail a
    # whole-path comparison while the behaviour is exactly right. The leaf is a
    # name this case invented and is no less discriminating.
    Add-Result 'junction mode over a REAL junction says so, and names what it points at' `
        ($dj.out -match 'IS a link' -and $dj.out -match 'a-checkout-somewhere-else') `
        "the plan must state the shape it checked and name the target, so the operator can contradict it. detect said: $(($det.out -split "`r?`n" | Where-Object { $_ -match 'skills entry' }) -join ' '). Output:`n$($dj.out)"

    # THE DEFECT ITSELF. Same mode, same wiring, a skills entry that is an
    # ordinary directory holding its own copy of statusline.ps1.
    $t = New-CaseTree -Tag 'junction-realdir' -Bytes $FixtureBytes
    $realDir = Join-Path (Join-Path (Join-Path $t.profile '.claude') 'skills') $PluginName
    [void][IO.Directory]::CreateDirectory((Join-Path $realDir 'statusline'))
    [IO.File]::Copy($RepoStatusLine, (Join-Path $realDir 'statusline\statusline.ps1'), $true)
    $rdi = New-Object IO.DirectoryInfo($realDir)
    if (($rdi.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "the fixture at $realDir is a reparse point; this case needs an ordinary directory and would otherwise be testing the control twice."
    }
    $dr = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'diff', '-Section', 'statusline', '-SettingsPath', $t.settings, '-StatusLineMode', 'junction')
    $detR = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'detect', '-SettingsPath', $t.settings)
    Add-Result 'junction mode over a REAL DIRECTORY does NOT claim the indicator can never fall behind' `
        ($dr.code -eq 0 -and $dr.out -notmatch [regex]::Escape($noDrift)) `
        "the skills entry is an ordinary directory holding a COPY, so there are two files and they drift exactly as copy mode's do. The plan told the operator otherwise, and detect in the same fixture said: $(($detR.out -split "`r?`n" | Where-Object { $_ -match 'skills entry' }) -join ' '). Output:`n$($dr.out)"
    Add-Result 'junction mode over a REAL DIRECTORY says it is not a link and that the copy can drift' `
        ($dr.out -match 'is a REAL DIRECTORY, NOT a link' -and $dr.out -match "drift") `
        "stating nothing is not the fix either: the operator picked this mode for a property their machine does not have and has to be told which one. Output:`n$($dr.out)"
    Add-Result 'junction mode over a REAL DIRECTORY warns before the yes' `
        ($dr.out -match '(?m)^--- READ BEFORE SAYING YES' -and $dr.out -match '(?ms)READ BEFORE SAYING YES.*REAL DIRECTORY on this machine and not a link') `
        "a mode that cannot deliver what it was chosen for is a read-before-you-say-yes condition, not a line buried in the body. Output:`n$($dr.out)"

    # THE THIRD SHAPE: NOTHING THERE AT ALL, which is the state a first run on a
    # new machine is actually in. skillIsLink is $false here for a completely
    # different reason, so the plan must neither promise one file nor accuse the
    # operator of having a copy - it has to say the question is not settled yet.
    $t = New-CaseTree -Tag 'junction-nothing' -Bytes $FixtureBytes
    $absent = Join-Path (Join-Path (Join-Path $t.profile '.claude') 'skills') $PluginName
    if ([IO.Directory]::Exists($absent)) {
        throw "the fixture at $absent exists; this case needs the skills entry to be absent and would otherwise duplicate one of the two above."
    }
    $dn = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'diff', '-Section', 'statusline', '-SettingsPath', $t.settings, '-StatusLineMode', 'junction')
    Add-Result 'junction mode with NO skills entry does not promise the indicator cannot fall behind' `
        ($dn.code -eq 0 -and $dn.out -notmatch [regex]::Escape($noDrift)) `
        "there is no link and no copy, so there is no 'only one file' to promise about - what goes there later decides it. Output:`n$($dn.out)"
    Add-Result 'junction mode with NO skills entry says so, and does not call it a real directory' `
        ($dn.out -match 'there is no skills entry at' -and $dn.out -notmatch 'REAL DIRECTORY') `
        "skillIsLink is `$false for an absent entry as well as for a copied one; a two-way test on it tells an operator who has installed nothing that they are carrying a second file. Output:`n$($dn.out)"

    # -------------------------------------------------------------------
    # 22. THE PERMISSIONS SECTION'S DIFF: SECTION REMOVED, WITH ITS SECTION.
    #
    #     Two cases lived here - one that the permissions diff reported the
    #     operator's OWN inert Write(...) rules, and a CONTROL that Edit(...)
    #     and Read(...) rules were not reported as inert. Both drove
    #     `-Step diff -Section permissions`.
    #
    #     That -Section value no longer exists. The section could only ever
    #     report "nothing to add" - New-PermissionsPlan returned at its
    #     `$rules.Count -eq 0` branch on every possible run - so the whole
    #     section was deleted from bin\lwg-setup.ps1 rather than left as a
    #     consent screen for nothing, and these two cases went with it. They
    #     are not restorable in place: `-Section permissions` is now a
    #     ValidateSet binding error, so both would abort rather than fail.
    #
    #     THE BEHAVIOUR THEY PINNED IS NOT UNTESTED, IT IS UNREACHABLE FROM
    #     THIS SURFACE. Get-InertRules is still live and still called by
    #     Write-DetectionReport, so the operator's inert rules are still
    #     named - under -Step detect, which is the only surface left that
    #     says anything about permissions.deny. NOTHING HERE DRIVES THAT
    #     REPORT for inert rules, and that gap is stated rather than papered
    #     over: a case for it would belong to the detect step, which this
    #     suite reads only for its install-mode lines.
    # -------------------------------------------------------------------

    # ===================================================================
    # 17. THE INSTALL-MODE DETECTION, AND THE HOOKS SECTION IT DECIDES.
    #
    #     A marketplace install is planted in the layout the CLI writes.
    #     Nothing else is planted: no skills junction, no settings entry.
    #     The old probe looked in ~\.claude\plugins\repos, which is absent
    #     here and absent on every real machine, so at the broken commit
    #     every one of these reports NOT DISCOVERABLE and the hooks section
    #     resolves to standalone - eight registrations added beside eight
    #     the plugin already supplies.
    # ===================================================================
    $t = New-CaseTree -Tag 'marketplace' -Bytes $FixtureBytes
    $mkRoot = New-MarketplaceRoot -ProfileDir $t.profile -PluginName $PluginName

    $det = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'detect', '-SettingsPath', $t.settings)
    Add-Result 'marketplace install: detect finds it and names the path' `
        ($det.out -match [regex]::Escape($mkRoot)) `
        "detection never named $mkRoot. Output:`n$($det.out)"
    Add-Result 'marketplace install: detect does NOT report NOT DISCOVERABLE' `
        ($det.out -notmatch 'NOT DISCOVERABLE') `
        "a plugin installed from a marketplace was reported as not discoverable, which is what makes setup write a second copy of every hook. Output:`n$($det.out)"

    # HookMode auto is what /lw-watchtower:setup drives, so this is the live path.
    $d = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'diff', '-Section', 'hooks', '-SettingsPath', $t.settings)
    Add-Result 'marketplace install: hooks -HookMode auto resolves to MODE: plugin' `
        ($d.out -match 'MODE: plugin') `
        "the hooks section chose standalone on a machine where the plugin is installed and already registers its own hooks. Output:`n$($d.out)"
    Add-Result 'marketplace install: the hooks section plans NO change' `
        ($d.out -match 'NOTHING TO DO') `
        "the hooks section would write registrations beside the ones the plugin already supplies - every hook then fires twice. Output:`n$($d.out)"

    # And it must not merely PLAN nothing - applying must write nothing.
    $h = Get-BaseHashFrom $d.out
    $a = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'apply', '-Section', 'hooks', '-SettingsPath', $t.settings, '-BaseHash', $h)
    Add-Result 'marketplace install: applying the hooks section writes nothing at all' `
        ($a.code -eq 0 -and (Test-BytesEqual ([IO.File]::ReadAllBytes($t.settings)) $FixtureBytes) -and (Get-SettingsBackups $t.dir).Count -eq 0) `
        "apply exited $($a.code); backups $((Get-SettingsBackups $t.dir).Count); the settings file must be untouched. Output:`n$($a.out)"

    # The operator OVERRIDES the mode. Setup must still write the registrations
    # they asked for - it is their machine - but the duplicate-firing warning is
    # the whole reason that override is dangerous, and it was suppressed by the
    # same broken flag that chose the mode.
    $t2 = New-CaseTree -Tag 'marketplace-forced' -Bytes $FixtureBytes
    [void](New-MarketplaceRoot -ProfileDir $t2.profile -PluginName $PluginName)
    $d2 = Invoke-Setup -ProfileDir $t2.profile -Arguments @('-Step', 'diff', '-Section', 'hooks', '-SettingsPath', $t2.settings, '-HookMode', 'standalone')
    Add-Result 'marketplace install: forcing -HookMode standalone still WARNS about duplicate firing' `
        ($d2.out -match 'WARNING - DUPLICATE FIRING') `
        "the operator forced standalone on a machine that already loads the plugin and was not told every hook would fire twice. Output:`n$($d2.out)"
    Add-Result 'marketplace install: the duplicate warning shows the EVIDENCE it rests on' `
        ($d2.out -match 'it is discoverable because:') `
        "the warning asserts discoverability without naming what it found, so an operator cannot contradict it. Output:`n$($d2.out)"

    # -------------------------------------------------------------------
    # 18. CONTROL, and it passes at the broken commit too. A profile with no
    #     install of any kind must still resolve to standalone and still plan
    #     the registrations - otherwise the fix above would be "always say
    #     discoverable", which breaks the only machine that genuinely needs
    #     this section.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'noinstall' -Bytes $FixtureBytes
    $d = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'diff', '-Section', 'hooks', '-SettingsPath', $t.settings)
    Add-Result 'CONTROL no install: hooks -HookMode auto resolves to MODE: standalone' `
        ($d.out -match 'MODE: standalone') `
        "a profile with no junction, no marketplace install and no registry entry was called discoverable. Output:`n$($d.out)"
    Add-Result 'CONTROL no install: registrations ARE planned' `
        ($d.out -match '(?m)^\d+ registration\(s\) would be ADDED') `
        "nothing would be wired in on a machine where nothing else runs the hooks. Output:`n$($d.out)"

    # -------------------------------------------------------------------
    # 18b. WHAT THE HOOKS DIFF SAYS ABOUT ITSELF, on the same standalone path.
    #
    #      This is the single screen on which a stranger consents to hook
    #      registration, and it makes two claims about itself that nothing
    #      checked.
    #
    #      (1) THE SUBSTITUTION IT DISCLOSES. The section's whole pitch is that
    #          it re-spells nothing from hooks.json and has exactly ONE
    #          substitution, which it then prints. The disclosure printed
    #          $D.pluginRoot and the code substituted $D.pluginRoot with
    #          backslashes turned to forward slashes, so the one string the
    #          section promises to disclose was the one string that does not
    #          occur in what it writes. The case takes the string OUT of the
    #          diff and looks for it in the applied file, so it cannot drift with
    #          either spelling - it is the claim being checked, not a literal.
    #
    #      (2) THE ROWS. Nine of the ten named a script and gave a reason;
    #          gate_delegate.ps1 was absent from the $keepReason table and
    #          rendered as '(unrecognised)   declared in hooks.json' - the one
    #          component here that can refuse a tool call, unnamed at the moment
    #          of consent. The second case is the general form of it, so the next
    #          hook added to hooks.json without a table entry goes red here
    #          rather than reaching an operator.
    #
    #      BASELINE: fd8d023. Measured there: the disclosure prints the
    #      backslash spelling and the written file carries the forward-slash one;
    #      the PreToolUse row reads '+ PreToolUse  (unrecognised)  declared in
    #      hooks.json'.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'hooksdiff' -Bytes $FixtureBytes
    $d = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'diff', '-Section', 'hooks', '-SettingsPath', $t.settings, '-HookMode', 'standalone')

    Add-Result 'hooks diff: the gate row NAMES gate_delegate.ps1 and says it ships switched off' `
        ($d.out -match '(?m)^\s*\+\s+PreToolUse\s+gate_delegate\.ps1\s+.*SHIPS SWITCHED OFF') `
        "the only registration here that can refuse a tool call has no name and no reason on the screen where the operator approves it. Output:`n$($d.out)"
    Add-Result 'hooks diff: no registration row renders as (unrecognised)' `
        ($d.out -notmatch '\(unrecognised\)') `
        "a row on the consent screen says the installer does not recognise what it is about to register. Output:`n$($d.out)"

    $disclosed = ''
    $m = [regex]::Match($d.out, '\$\{CLAUDE_PLUGIN_ROOT\} -> (.+?), because that variable is defined')
    if ($m.Success) { $disclosed = $m.Groups[1].Value }
    $h = Get-BaseHashFrom $d.out
    $a = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'apply', '-Section', 'hooks', '-SettingsPath', $t.settings, '-BaseHash', $h)
    $writtenText = ''
    try { $writtenText = [IO.File]::ReadAllText($t.settings, [Text.Encoding]::UTF8) } catch { }
    Add-Result 'hooks diff: the ${CLAUDE_PLUGIN_ROOT} value it discloses is the one that lands in the file' `
        ($disclosed -ne '' -and $a.code -eq 0 -and $writtenText.Contains($disclosed)) `
        "the diff disclosed '$disclosed' and the applied settings.json does not contain that string, so an operator grepping for what they were shown, or hand-writing a matching entry from it, is working from a string that is not there. apply exited $($a.code)."

    # -------------------------------------------------------------------
    # 19. THE HOOK IDENTITY IS ROOT-INDEPENDENT.
    #
    #     settings.json already registers this plugin's own SessionStart hook,
    #     from a DIFFERENT checkout. That is what a second clone leaves behind,
    #     and what renaming or moving the folder leaves behind from one clone.
    #     The old signature was built from the absolute path, so the existing
    #     entry was invisible and a second one was added beside it - both then
    #     fire.
    #
    #     The other root is a path under the scratch tree that does not exist.
    #     It is never executed and never created; only its spelling matters.
    # -------------------------------------------------------------------
    $otherRoot = (Join-Path $script:Work 'a-different-checkout').Replace('\', '/')
    $preText   = @'
{
    "alpha": "keep me",
    "hooks": {
        "SessionStart": [
            {
                "hooks": [
                    {
                        "type": "command",
                        "command": "powershell",
                        "args": [ "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "__OTHER__/lib/session_start.ps1" ],
                        "timeout": 15
                    }
                ]
            }
        ]
    }
}
'@ -replace '__OTHER__', $otherRoot
    $preBytes = $Utf8NoBom.GetBytes($preText)

    $t = New-CaseTree -Tag 'otherroot' -Bytes $preBytes
    $d = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'diff', '-Section', 'hooks', '-SettingsPath', $t.settings, '-HookMode', 'standalone')
    Add-Result 'another root: the diff REPORTS the existing registration rather than ignoring it' `
        ($d.out -match 'ALREADY REGISTERED FROM ANOTHER ROOT') `
        "setup did not notice that session_start.ps1 is already registered from a different root, so it would add a second registration and the hook would fire twice. Output:`n$($d.out)"
    # The path has to be ON the report line, not merely somewhere in the output:
    # the diff also dumps the whole merged hooks value, so a search of the output
    # for that path passes whether the report names it or not. It passed at the
    # broken commit when it was written that way, which is how this was caught.
    #
    # WHITESPACE IS STRIPPED FROM BOTH SIDES BEFORE MATCHING. A captured child
    # hard-wraps its output at the host width, so a long path is regularly split
    # across two lines and a match against the intact string fails for a reason
    # that has nothing to do with the installer. No path in this fixture contains
    # a space, so removing whitespace cannot join two things that were separate.
    $flat  = ($d.out -replace '\s', '')
    $needle = ('ALREADYREGISTEREDFROMANOTHERROOT:' + ($otherRoot -replace '\s', '') + '/lib/session_start.ps1')
    Add-Result 'another root: the report line NAMES the root it found' `
        ($flat -match [regex]::Escape($needle)) `
        "the report does not say WHERE the other registration points, so the operator cannot act on it. Expected '$needle' on the report line. Output:`n$($d.out)"

    $h = Get-BaseHashFrom $d.out
    $a = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'apply', '-Section', 'hooks', '-SettingsPath', $t.settings, '-BaseHash', $h, '-HookMode', 'standalone')
    $after = Read-Json $t.settings
    $ss    = Get-HookGroupsFor -Obj $after -Event 'SessionStart' -Leaf 'session_start.ps1'
    Add-Result 'another root: session_start.ps1 ends up registered EXACTLY ONCE' `
        ($ss.Count -eq 1) `
        "SessionStart now runs session_start.ps1 from $($ss.Count) registration(s); more than one means the banner and the self-check run that many times per session. Output:`n$($a.out)"

    # NEVER REMOVES - a CONTROL, and it passes at the broken commit too, which
    # is the point: the broken commit ADDED beside the operator's entry instead
    # of removing it. What must not change is that the entry survives. A "fix"
    # that deduplicated by deleting the other root would pass case 19 above and
    # fail this one.
    $afterText = [IO.File]::ReadAllText($t.settings, [Text.Encoding]::UTF8)
    Add-Result 'CONTROL another root: the operator''s own registration is still there afterwards' `
        ($afterText -match [regex]::Escape($otherRoot)) `
        "the installer removed a registration it did not write. It never removes - it reports. Output:`n$($a.out)"

    # A SECOND RUN OVER THE SAME TREE, which is where a true statement turns
    # false. Everything except SessionStart is now registered at this root and
    # matches exactly; SessionStart is still the other root's and is still
    # declined. So the plan changes NOTHING and carries a warning - and the
    # no-change branch of apply used to print 'Already in the state requested'
    # for every such run. It is not in the state requested. It is in a state the
    # installer declined to change, and saying otherwise is the overstatement
    # this whole project exists to refuse.
    $d3 = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'diff', '-Section', 'hooks', '-SettingsPath', $t.settings, '-HookMode', 'standalone')
    $h3 = Get-BaseHashFrom $d3.out
    $a3 = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'apply', '-Section', 'hooks', '-SettingsPath', $t.settings, '-BaseHash', $h3, '-HookMode', 'standalone')
    Add-Result 'another root: a no-change apply does NOT claim the file is already as requested' `
        ($a3.code -eq 0 -and $a3.out -notmatch 'Already in the state requested') `
        "apply exited $($a3.code) and reported the file as already in the requested state, while a registration it declined to touch is still pointing somewhere else. Output:`n$($a3.out)"
    Add-Result 'another root: a no-change apply repeats the reason it wrote nothing' `
        ($a3.out -match 'ALREADY REGISTERED FROM ANOTHER ROOT' -or $a3.out -match 'DIFFERENT root') `
        "the apply wrote nothing and did not say why - the reason appeared on the diff only, which is not where the operator is looking when they run the apply. Output:`n$($a3.out)"

    # -------------------------------------------------------------------
    # 19b. A MATCHER THIS PLUGIN HAS SUPERSEDED IS ONE HOOK, NOT TWO.
    #
    #     BASELINE NOTE, because it decides what this case proves: it was
    #     confirmed red against the WORKING TREE as it stood after the four
    #     parallel fixes and before this one, NOT against fd8d023. The matcher
    #     token it turns on did not exist at fd8d023, so a run there is silent
    #     about it. A filesystem copy of that tree, this fixture pointed at it:
    #     '10 registration(s) would be ADDED' and a merged hooks value carrying
    #     BOTH matchers against the SAME absolute gate_delegate.ps1. Fixed tree,
    #     same fixture: 9, and the existing entry reported.
    #
    #     WHY IT MATTERS MORE THAN THE OTHER GROUPS. Both identity functions key
    #     on the matcher string, and v0.3.0 - a tagged, published release - wired
    #     lib/gate_delegate.ps1 to 'Edit|Write|NotebookEdit|Bash'. PowerShell
    #     joined that matcher on 1 August 2026. So every machine upgrading from
    #     v0.3.0 with hooks in settings.json got a SECOND registration of the one
    #     hook in this plugin that can BLOCK a tool call: two gate runs per Edit,
    #     Write, NotebookEdit or Bash call, and two deny envelopes per refusal.
    #     Get-HookIdentity exists precisely to stop that, and the matcher token
    #     punched straight through it.
    #
    #     THE SECOND HALF IS THE ONE THAT KEEPS THE FIX HONEST. Recognising the
    #     old entry silently would trade a duplicate for something quieter and
    #     worse: the operator would be told the hook is present while PowerShell
    #     - the tool the matcher was widened FOR - stayed unhooked. So the report
    #     must NAME the superseded matcher. A fix that only deduplicated would
    #     pass the first assertion and fail the third.
    #
    #     The registration points at THIS root, which is what an in-place
    #     upgrade leaves behind - so it is the exact-signature path, not the
    #     other-root path that case 19 covers.
    # -------------------------------------------------------------------
    $gatePath = ($Root -replace '\\', '/') + '/lib/gate_delegate.ps1'
    $oldText  = @'
{
    "hooks": {
        "PreToolUse": [
            {
                "matcher": "Edit|Write|NotebookEdit|Bash",
                "hooks": [
                    {
                        "type": "command",
                        "command": "powershell",
                        "args": [ "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "__GATE__" ]
                    }
                ]
            }
        ]
    }
}
'@ -replace '__GATE__', $gatePath

    $t = New-CaseTree -Tag 'oldmatcher' -Bytes ($Utf8NoBom.GetBytes($oldText))
    $d = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'diff', '-Section', 'hooks', '-SettingsPath', $t.settings, '-HookMode', 'standalone')
    Add-Result 'superseded matcher: the v0.3.0 gate registration is RECOGNISED, not added beside' `
        ($d.out -notmatch '10 registration\(s\) would be ADDED') `
        "setup planned a second PreToolUse registration beside the v0.3.0 one. Both invoke the same gate_delegate.ps1, so the gate would run twice on every Edit, Write, NotebookEdit and Bash call and emit two deny envelopes per refusal. Output:`n$($d.out)"

    $h = Get-BaseHashFrom $d.out
    $a = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'apply', '-Section', 'hooks', '-SettingsPath', $t.settings, '-BaseHash', $h, '-HookMode', 'standalone')
    $afterOld = Read-Json $t.settings
    $gg = Get-HookGroupsFor -Obj $afterOld -Event 'PreToolUse' -Leaf 'gate_delegate.ps1'
    Add-Result 'superseded matcher: gate_delegate.ps1 ends up registered EXACTLY ONCE' `
        ($gg.Count -eq 1) `
        "PreToolUse now runs gate_delegate.ps1 from $($gg.Count) registration(s). More than one doubles the unconditional per-call cost of the only hook here that can refuse a call. Output:`n$($a.out)"

    Add-Result 'superseded matcher: the report NAMES the stale matcher and what it leaves unhooked' `
        ($d.out -match 'SUPERSEDED matcher' -and ($d.out -replace '\s', '') -match 'Edit\|Write\|NotebookEdit\|Bash\|PowerShell') `
        "setup recognised the old registration and said nothing about it. That is the quieter failure, not the safer one: the operator is told the gate is registered while the tool the matcher was widened for is not hooked at all. The report must name the stale string and the one it should read. Output:`n$($d.out)"

    # BOTH MATCHERS ALREADY IN THE FILE - the state the broken code CREATED, and
    # therefore the population this table actually serves. A machine that ran
    # setup once after the matcher widened has two PreToolUse groups already,
    # both invoking the same gate. Recognising the hook is then not enough: the
    # duplicate is ALREADY FIRING, and an installer that prints a bare "already
    # registered in this file" over it has reported a healthy state about a hook
    # running twice - this project's own named defect.
    #
    # RUN IN BOTH ORDERS ON PURPOSE. The first version of this repair looked the
    # matcher up first-wins per identity, so with the CURRENT-matcher group
    # written first it reported nothing at all, and with the old one first it
    # reported the stale matcher. Same file, same two groups, different message.
    # An order-dependent report is not a report.
    #
    # DETECTED, NOT REPAIRED, and the case pins the wording rather than a
    # removal: this installer never removes.
    foreach ($ord in @('oldfirst', 'newfirst')) {
        $gOld = @'
            {
                "matcher": "Edit|Write|NotebookEdit|Bash",
                "hooks": [ { "type": "command", "command": "powershell",
                             "args": [ "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "__GATE__" ] } ]
            }
'@
        $gNew = $gOld -replace 'Edit\|Write\|NotebookEdit\|Bash"', 'Edit|Write|NotebookEdit|Bash|PowerShell"'
        $pair = if ($ord -eq 'oldfirst') { $gOld + ',' + $gNew } else { $gNew + ',' + $gOld }
        $bothText = ('{ "hooks": { "PreToolUse": [' + $pair + '] } }') -replace '__GATE__', $gatePath

        $tb = New-CaseTree -Tag ('both-' + $ord) -Bytes ($Utf8NoBom.GetBytes($bothText))
        $db = Invoke-Setup -ProfileDir $tb.profile -Arguments @('-Step', 'diff', '-Section', 'hooks', '-SettingsPath', $tb.settings, '-HookMode', 'standalone')
        Add-Result "both matchers ($ord): the EXISTING duplicate is reported, not papered over" `
            ($db.out -match '2 TIMES') `
            "the file already registers gate_delegate.ps1 twice - the state a previous run of the broken code wrote - and setup reported it as simply already registered. The gate fires twice per call and the installer said nothing. Output:`n$($db.out)"
        Add-Result "both matchers ($ord): the stale matcher is named whatever order the groups are in" `
            ($db.out -match 'SUPERSEDED matcher') `
            "the report depends on which group happens to come first in the file. Same two groups, same defect, different message. Output:`n$($db.out)"
    }

    # THE OTHER ROOT AND THE OLD MATCHER AT ONCE, which is the sharper form of
    # the same defect and goes through the OTHER identity function. Case 19b
    # above matches on Get-HookSignature, which is same-root; a plugin moved
    # from a v0.3.0 marketplace-cache path carries BOTH a different root AND the
    # old matcher, and only Get-HookIdentity can see it. Before the fix that
    # produced the report the adversary described: session_start.ps1 correctly
    # caught as ALREADY REGISTERED FROM ANOTHER ROOT while the GATE group - same
    # file, same run, same moved root - was added again as an ordinary new
    # registration, the difference being only that its matcher had changed.
    #
    # Both facts have to be reported, and they are separate warnings on purpose:
    # "which checkout should run this" and "these tools are not hooked at all"
    # have different fixes.
    $movedRoot = (Join-Path $script:Work 'a-moved-v030-root').Replace('\', '/')
    $movedText = @'
{
    "hooks": {
        "PreToolUse": [
            {
                "matcher": "Edit|Write|NotebookEdit|Bash",
                "hooks": [
                    {
                        "type": "command",
                        "command": "powershell",
                        "args": [ "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "__MOVED__/lib/gate_delegate.ps1" ]
                    }
                ]
            }
        ]
    }
}
'@ -replace '__MOVED__', $movedRoot

    $tm = New-CaseTree -Tag 'movedoldmatcher' -Bytes ($Utf8NoBom.GetBytes($movedText))
    $dm = Invoke-Setup -ProfileDir $tm.profile -Arguments @('-Step', 'diff', '-Section', 'hooks', '-SettingsPath', $tm.settings, '-HookMode', 'standalone')
    $hm = Get-BaseHashFrom $dm.out
    $am = Invoke-Setup -ProfileDir $tm.profile -Arguments @('-Step', 'apply', '-Section', 'hooks', '-SettingsPath', $tm.settings, '-BaseHash', $hm, '-HookMode', 'standalone')
    $afterM = Read-Json $tm.settings
    $gm2 = Get-HookGroupsFor -Obj $afterM -Event 'PreToolUse' -Leaf 'gate_delegate.ps1'
    Add-Result 'moved root + old matcher: the gate is recognised across BOTH, and registered exactly once' `
        ($gm2.Count -eq 1 -and $dm.out -match 'ALREADY REGISTERED FROM ANOTHER ROOT') `
        "gate_delegate.ps1 is registered from $($gm2.Count) group(s). A plugin moved from a v0.3.0 cache path differs in root AND matcher at once; the root-independent identity has to see through both or the one hook that can block a call fires twice. Output:`n$($dm.out)"
    Add-Result 'moved root + old matcher: BOTH facts are reported, not just the root' `
        ($dm.out -match 'superseded matcher' -or $dm.out -match 'SUPERSEDED matcher') `
        "the report named the moved root and said nothing about the stale matcher. They have different fixes - which checkout should run it, versus which tools are unhooked - so reporting one and not the other leaves the operator believing PowerShell is gated. Output:`n$($dm.out)"

    # -------------------------------------------------------------------
    # 19c. A HOOK IS RECOGNISED IN THE `command` STRING SPELLING TOO.
    #
    #     BASELINE: red against the working tree before this fix, not against
    #     fd8d023 - Get-HookScriptPaths did not exist there.
    #
    #     Get-HookScriptPaths' docstring claimed the walk existed so that a
    #     `command` STRING was handled as well as an `args` ARRAY, and named the
    #     consequence of missing one: 'an extra copy of a hook'. The code matched
    #     '\.ps1$' against the WHOLE string, so it saw a command string only when
    #     the path was the last thing on the line. Both realistic spellings
    #     failed - a QUOTED path, which any path containing a space forces, and a
    #     path with a TRAILING ARGUMENT, which this plugin's own supervisor.ps1
    #     registration requires. Measured against the old code: 2 registrations
    #     after apply for each of these, against 1 for the args-array shape case
    #     19 happens to use.
    # -------------------------------------------------------------------
    $cmdShapes = @(
        @{ tag = 'cmdquoted'; why = 'a QUOTED path - what a path containing a space forces'
           cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File \"__OTHER__/lib/session_start.ps1\"' }
        @{ tag = 'cmdtrail';  why = 'a TRAILING ARGUMENT after the path - what this plugin''s own supervisor registration needs'
           cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File __OTHER__/lib/session_start.ps1 -HookEvent SessionStart' }
    )
    foreach ($cs in $cmdShapes) {
        $cmdRoot = (Join-Path $script:Work ('other-' + $cs.tag)).Replace('\', '/')
        $cmdText = @'
{
    "hooks": {
        "SessionStart": [
            { "hooks": [ { "type": "command", "command": "__CMD__" } ] }
        ]
    }
}
'@ -replace '__CMD__', ($cs.cmd -replace '__OTHER__', $cmdRoot)

        $tc = New-CaseTree -Tag $cs.tag -Bytes ($Utf8NoBom.GetBytes($cmdText))
        $dc = Invoke-Setup -ProfileDir $tc.profile -Arguments @('-Step', 'diff', '-Section', 'hooks', '-SettingsPath', $tc.settings, '-HookMode', 'standalone')
        Add-Result "command string: an other-root registration written as $($cs.tag) is RECOGNISED" `
            ($dc.out -match 'ALREADY REGISTERED FROM ANOTHER ROOT') `
            "setup did not see the existing session_start.ps1 registration because it is spelled as $($cs.why). It would add a second one and the banner and self-check would run twice per session. Output:`n$($dc.out)"

        $hc = Get-BaseHashFrom $dc.out
        $ac = Invoke-Setup -ProfileDir $tc.profile -Arguments @('-Step', 'apply', '-Section', 'hooks', '-SettingsPath', $tc.settings, '-BaseHash', $hc, '-HookMode', 'standalone')
        $afterC = Read-Json $tc.settings
        $ssc = Get-HookGroupsFor -Obj $afterC -Event 'SessionStart' -Leaf 'session_start.ps1'
        Add-Result "command string: $($cs.tag) leaves session_start.ps1 registered EXACTLY ONCE" `
            ($ssc.Count -eq 1) `
            "SessionStart now runs session_start.ps1 from $($ssc.Count) registration(s) - the consequence Get-HookScriptPaths' own docstring names. Output:`n$($ac.out)"
    }

    # -------------------------------------------------------------------
    # 20. THE STATUS LINE RESOLVES A MARKETPLACE ROOT.
    #
    #     Same defect, other file: statusline\statusline.ps1 looked for the
    #     marketplace install under ~\.claude\plugins\repos too. With no root
    #     resolving, HealthSeg rendered purple 'HH?' - which MEANS NOT
    #     INSTALLED - about a plugin that is installed and working, and
    #     GmConfig returned $null so the operator's configured thresholds were
    #     silently replaced by the built-in numbers.
    #
    #     The copy is run, not the tracked file: see Invoke-StatusLine.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'statusline-mkt' -Bytes $null
    $slRoot = New-MarketplaceRoot -ProfileDir $t.profile -PluginName $PluginName -Contents 'full'

    # A threshold no built-in could produce: warn at 1%, so a 10% context
    # renders the advisory only if the planted config.json was actually read.
    [IO.File]::WriteAllText((Join-Path $slRoot 'config.json'),
        '{"thresholds":{"context":{"warn_pct":1,"critical_pct":99}}}')

    $slCopy = Join-Path (Join-Path $t.profile '.claude') 'statusline.ps1'
    [IO.File]::Copy($RepoStatusLine, $slCopy, $true)

    # current_dir is the scratch tree, which is not a repo - so the git segments
    # resolve to nothing and cannot add noise to what is being matched.
    $payload = '{"session_id":"lwg-merge-suite-session","model":{"display_name":"FixtureModel"},' +
               '"context_window":{"used_percentage":10},' +
               '"workspace":{"current_dir":"' + $t.dir.Replace('\', '/') + '"}}'
    $r = Invoke-StatusLine -ProfileDir $t.profile -ScriptPath $slCopy -PayloadJson $payload

    Add-Result 'status line: a marketplace root resolves, so HH is not the purple NOT-INSTALLED glyph' `
        ($r.out -notmatch 'HH\?') `
        "the status line rendered 'HH?' - not installed - against a marketplace install that is present and complete. Output:`n$($r.out)"
    Add-Result 'status line: HH is the dim unknown glyph, not a green all-clear' `
        ($r.out -match 'HH-') `
        "with a root resolved and no health log to read, the only honest glyph is the dim 'HH-'. Rendering anything else means the segment reported on records it never read. Output:`n$($r.out)"
    Add-Result 'status line: the config.json under that root is READ, so configured thresholds win' `
        ($r.out -match 'plan for compaction') `
        "context is 10% and the planted config warns at 1%, so the advisory must appear. It did not, which means GmConfig found no root and the built-in 75% was used instead. Output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 20b. THE STATUS LINE FOLLOWS A RELOCATED PLUGINS DIRECTORY.
    #
    #     BASELINE: red against the working tree after the four parallel fixes
    #     and before this one, NOT against fd8d023 - at fd8d023 neither file read
    #     the variable, so they at least AGREED. The fix that taught
    #     bin\lwg-setup.ps1 to honour CLAUDE_CODE_PLUGIN_CACHE_DIR left this file
    #     hardcoding $env:USERPROFILE, so the two halves of ONE repair then
    #     disagreed about where the plugin lived on the same machine: setup
    #     printed 'marketplace install: <relocated path>' and 'Claude Code can
    #     auto-discover it', while this segment rendered purple HH? and dropped
    #     the operator's config.json.
    #
    #     Those are the exact two symptoms case 20 above exists to prove closed,
    #     alive on a SUPPORTED relocation with no layout change at all. No case
    #     could reach it because Invoke-StatusLine cleared the variable as part
    #     of its sandbox - the guard was blind by construction, not by oversight.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'statusline-relocated' -Bytes $null
    $altBase = Join-Path $t.dir 'elsewhere-plugins'
    $slRoot2 = New-MarketplaceRoot -ProfileDir $t.profile -PluginName $PluginName -Contents 'full' -PluginsBase $altBase
    [IO.File]::WriteAllText((Join-Path $slRoot2 'config.json'),
        '{"thresholds":{"context":{"warn_pct":1,"critical_pct":99}}}')
    $slCopy = Join-Path (Join-Path $t.profile '.claude') 'statusline.ps1'
    [IO.File]::Copy($RepoStatusLine, $slCopy, $true)
    $payload = '{"session_id":"lwg-merge-suite-session","model":{"display_name":"FixtureModel"},' +
               '"context_window":{"used_percentage":10},' +
               '"workspace":{"current_dir":"' + $t.dir.Replace('\', '/') + '"}}'
    $r = Invoke-StatusLine -ProfileDir $t.profile -ScriptPath $slCopy -PayloadJson $payload -CacheDir $altBase

    Add-Result 'relocated cache: the status line resolves the install, so HH is not the NOT-INSTALLED glyph' `
        ($r.out -notmatch 'HH\?') `
        "the status line rendered 'HH?' - not installed - against a complete install that bin\lwg-setup.ps1 detects and reports as discoverable on the same machine. CLAUDE_CODE_PLUGIN_CACHE_DIR is a supported relocation, not a layout change. Output:`n$($r.out)"
    Add-Result 'relocated cache: the config.json under the relocated root is READ' `
        ($r.out -match 'plan for compaction') `
        "context is 10% and the planted config warns at 1%, so the advisory must appear. It did not, which means GmConfig never found the relocated root and silently used the built-in 75% instead - the operator's configured thresholds replaced without a word. Output:`n$($r.out)"

    # CONTROL: the DEFAULT base is still scanned when the variable is set. The
    # fix reads both, in Get-Detection's order, and this is what stops it being
    # written as "use the variable INSTEAD" - a machine that sets the variable
    # today can still carry an install written under the default base, and
    # losing that install is the same defect in the other direction. It passes
    # before the fix as well, on purpose.
    $t = New-CaseTree -Tag 'statusline-bothbases' -Bytes $null
    $slRoot3 = New-MarketplaceRoot -ProfileDir $t.profile -PluginName $PluginName -Contents 'full'
    [IO.File]::WriteAllText((Join-Path $slRoot3 'config.json'),
        '{"thresholds":{"context":{"warn_pct":1,"critical_pct":99}}}')
    $slCopy = Join-Path (Join-Path $t.profile '.claude') 'statusline.ps1'
    [IO.File]::Copy($RepoStatusLine, $slCopy, $true)
    $payload = '{"session_id":"lwg-merge-suite-session","model":{"display_name":"FixtureModel"},' +
               '"context_window":{"used_percentage":10},' +
               '"workspace":{"current_dir":"' + $t.dir.Replace('\', '/') + '"}}'
    $r = Invoke-StatusLine -ProfileDir $t.profile -ScriptPath $slCopy -PayloadJson $payload `
                           -CacheDir (Join-Path $t.dir 'a-relocation-holding-nothing')
    Add-Result 'CONTROL relocated cache: an install at the DEFAULT base is still found when the variable is set' `
        ($r.out -notmatch 'HH\?' -and $r.out -match 'plan for compaction') `
        "the variable points somewhere empty and the real install is at the default location, which the status line must still scan. Reading the variable INSTEAD OF the default would pass the case above and lose every install that predates the relocation. Output:`n$($r.out)"

    # CONTROL, and it passes at the broken commit too. With NOTHING planted the
    # glyph must still be 'HH?'. Without this, "never render HH?" would pass the
    # case above while destroying the one state it exists to report.
    $t = New-CaseTree -Tag 'statusline-bare' -Bytes $null
    $slCopy = Join-Path (Join-Path $t.profile '.claude') 'statusline.ps1'
    [IO.File]::Copy($RepoStatusLine, $slCopy, $true)
    $payload = '{"session_id":"lwg-merge-suite-session","model":{"display_name":"FixtureModel"},' +
               '"context_window":{"used_percentage":10},' +
               '"workspace":{"current_dir":"' + $t.dir.Replace('\', '/') + '"}}'
    $r = Invoke-StatusLine -ProfileDir $t.profile -ScriptPath $slCopy -PayloadJson $payload
    Add-Result 'CONTROL status line: with no install anywhere, HH is still the purple NOT-INSTALLED glyph' `
        ($r.out -match 'HH\?') `
        "nothing is installed under this profile and the segment did not say so. Output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 20c. A THRESHOLD SUBSTITUTION THE OPERATOR IS NEVER TOLD ABOUT (#8).
    #
    #      #8's fifth failure scenario, and the half of it the marketplace fix
    #      did not close. An operator sets thresholds.ratelimit.warn_pct to 70,
    #      GmConfig cannot identify a config for ANY reason - no candidate root
    #      resolved, no config.json beside one, the file does not parse, or it
    #      parses and is not this plugin's - and all four built-ins stand. Every
    #      threshold on screen is then not the threshold in the file, on every
    #      render, for the whole session, and nothing says so.
    #
    #      The row that names a threshold READ AND UNUSABLE already existed. The
    #      row for "no config was found at all" did not, and that is the state #8
    #      is actually about: on a marketplace install the file was perfectly
    #      readable and was never looked for.
    #
    #      SAME FIXTURE AS THE BARE CONTROL ABOVE - no install anywhere - because
    #      that is a machine with no identifiable config, which is the condition
    #      under test. The bare control asserts the HH glyph; this asserts the
    #      advisory row, and they are different surfaces.
    #
    #      RED AT ec80e88: the advisory row carried nothing about the config.
    # -------------------------------------------------------------------
    Add-Result 'no config identified: the status line SAYS the built-in thresholds are in force' `
        ($r.out -match 'no lw-watchtower config\.json could be identified') `
        "all four thresholds were replaced by built-ins and the operator was told nothing. A status line that renders as though the configured values were in force is worse than one that renders nothing. Output:`n$($r.out)"

    # CONTROL: a machine whose config IS found must NOT carry that row. Without
    # this, "always warn" passes the case above and puts a permanent false
    # advisory on every correctly-installed machine. The relocated-cache fixture
    # two cases up planted a real config.json under a real marketplace root and
    # proved it was read; this re-runs that shape and asserts the silence.
    $t = New-CaseTree -Tag 'statusline-config-found' -Bytes $null
    $slRoot4 = New-MarketplaceRoot -ProfileDir $t.profile -PluginName $PluginName -Contents 'full'
    [IO.File]::WriteAllText((Join-Path $slRoot4 'config.json'),
        '{"thresholds":{"context":{"warn_pct":1,"critical_pct":99}}}')
    $slCopy = Join-Path (Join-Path $t.profile '.claude') 'statusline.ps1'
    [IO.File]::Copy($RepoStatusLine, $slCopy, $true)
    $payload = '{"session_id":"lwg-merge-suite-session","model":{"display_name":"FixtureModel"},' +
               '"context_window":{"used_percentage":10},' +
               '"workspace":{"current_dir":"' + $t.dir.Replace('\', '/') + '"}}'
    $r4 = Invoke-StatusLine -ProfileDir $t.profile -ScriptPath $slCopy -PayloadJson $payload
    Add-Result 'CONTROL: a status line that DID find a config says nothing about built-ins' `
        ($r4.out -notmatch 'could be identified' -and $r4.out -match 'plan for compaction') `
        "the planted config warns at 1% against a context of 10%, so it was read - and the row must then be silent. A permanent advisory on a healthy machine trains the operator to ignore the channel. Output:`n$($r4.out)"

    # ===================================================================
    # 23. THE STATUS LINE'S PAYLOAD READER, ITS NUMBERS AND ITS CLOCK.
    #
    #     WHY THESE LIVE IN THE INSTALLER'S SUITE. They do not test the
    #     installer, and that is said out loud rather than left to be
    #     discovered. They are here because this file already owns the only
    #     harness in the repository that runs statusline\statusline.ps1 for
    #     real - a byte copy under a scratch profile, a payload on stdin, a
    #     sandboxed USERPROFILE and the three plugin variables handled - and
    #     the alternative was a ninth file in tests\, which would move the
    #     `tests-file-count` and `behavioural-suite-count` claims in eleven
    #     tracked pages. Sections 20 and 20b already established the
    #     precedent: this suite covers the status line's resolution as well
    #     as the installer's merge.
    #
    #     BASELINE FOR EVERY CASE IN THIS SECTION: cc44c99, the commit this
    #     worktree started from, run as a byte copy exported with
    #     `git archive`. It is NOT fd8d023 for a reason worth stating - all
    #     of these defects are present at fd8d023 too, but a marketplace root
    #     does not resolve there at all, so the fixtures below would go red
    #     for the wrong reason and prove nothing about the fix beside them.
    #     Each case names what the baseline actually printed.
    # ===================================================================

    # A single non-ASCII character, spelled by code point so this file itself
    # stays ASCII - tests\portability_scan.ps1 reads every tracked file and a
    # literal here would be one more thing for a reviewer to have to decode.
    $acc = [string][char]0xE9

    # -------------------------------------------------------------------
    # 23a. A UTF-8 BOM ON THE PAYLOAD MUST NOT BLANK THE WHOLE ROW.
    #
    #      statusline.ps1 read stdin through [Console]::In, which decodes with
    #      the console's INPUT code page. A BOM decoded through cp437 makes the
    #      first character U+2229, the `if ($raw[0] -ne '{')` guard fails, the
    #      script exits 0 having printed nothing, and the file's own header
    #      records what that costs: empty stdout blanks the entire status line
    #      with no signal that the script ran.
    #
    #      BASELINE cc44c99: stdout was EMPTY. Nothing rendered at all.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'sl-bom' -Bytes $null
    $slCopy = Join-Path (Join-Path $t.profile '.claude') 'statusline.ps1'
    [IO.File]::Copy($RepoStatusLine, $slCopy, $true)
    $asciiPayload = '{"session_id":"lwg-merge-suite-session","model":{"display_name":"FixtureModel"},' +
                    '"workspace":{"current_dir":"' + $t.dir.Replace('\', '/') + '"}}'
    $bomBytes = [byte[]]($Utf8Bom.GetPreamble() + $Utf8NoBom.GetBytes($asciiPayload))
    $r = Invoke-StatusLineRaw -ProfileDir $t.profile -ScriptPath $slCopy -PayloadBytes $bomBytes
    Add-Result 'status line: a payload carrying a UTF-8 BOM still renders a row' `
        ($r.out -match 'FixtureModel') `
        "the payload was valid JSON with a byte-order mark in front of it and the row came back as [$($r.out)]. An empty row is the failure mode statusline.ps1's own header calls out: the operator sees nothing at all and has no way to tell the script ran."

    # -------------------------------------------------------------------
    # 23b. A NON-ASCII cwd IN THE PAYLOAD MUST STILL RESOLVE ITS REPOSITORY.
    #
    #      The mojibake half of the same defect, and the half that is not
    #      cosmetic: workspace.current_dir decoded through the wrong code page
    #      names a path that is not on disk, GitDir finds no .git, and the
    #      owner/repo segment silently degrades to the dim leaf name - which is
    #      ALSO what a cwd outside any repository renders, so the two states
    #      cannot be told apart on the row. `C:\Users\<accented name>\...` is
    #      enough to reach this.
    #
    #      The assertion is deliberately on an ASCII slug: what is being
    #      established is that the PATH survived the read, not what the row
    #      does with a non-ASCII repository name (23d covers that).
    #
    #      BASELINE cc44c99: the row ended with the dim directory leaf and no
    #      slug at all.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'sl-utf8-cwd' -Bytes $null
    $slCopy = Join-Path (Join-Path $t.profile '.claude') 'statusline.ps1'
    [IO.File]::Copy($RepoStatusLine, $slCopy, $true)
    $repoDir = Join-Path $t.dir ('checkout-' + $acc)
    [void][IO.Directory]::CreateDirectory($repoDir)
    [void](New-GitFixture -Dir $repoDir -Url 'https://example.invalid/lwgfixtureowner/lwgfixturerepo.git')
    $payload = '{"session_id":"lwg-merge-suite-session","model":{"display_name":"FixtureModel"},' +
               '"workspace":{"current_dir":"' + $repoDir.Replace('\', '/') + '"}}'
    $r = Invoke-StatusLineRaw -ProfileDir $t.profile -ScriptPath $slCopy -PayloadBytes ($Utf8NoBom.GetBytes($payload))
    Add-Result 'status line: a cwd with a non-ASCII segment still resolves owner/repo' `
        ($r.out -match 'lwgfixtureowner/lwgfixturerepo') `
        "the payload named a real checkout and the row did not resolve its slug, which is indistinguishable on the row from a cwd that is in no repository at all. Output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 23c. A WORKTREE'S .git FILE IS READ AS UTF-8.
    #
    #      Get-Content with no -Encoding reads ANSI in Windows PowerShell 5.1
    #      while git writes UTF-8. In a worktree or a submodule, `.git` is a
    #      FILE whose contents are a filesystem PATH, so on a profile with an
    #      accented name the decoded path does not exist and the segment is
    #      lost. This is the same bug statusline.ps1 already found, fixed and
    #      documented for health.jsonl 250 lines above the call site, and left
    #      standing here.
    #
    #      The worktree directory itself is ASCII, so this case fails only on
    #      the .git read - it does not overlap 23b.
    #
    #      BASELINE cc44c99: dim leaf 'worktree-ascii', no slug.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'sl-worktree' -Bytes $null
    $slCopy = Join-Path (Join-Path $t.profile '.claude') 'statusline.ps1'
    [IO.File]::Copy($RepoStatusLine, $slCopy, $true)
    $mainDir = Join-Path $t.dir ('main-' + $acc)
    [void][IO.Directory]::CreateDirectory($mainDir)
    $realGit = New-GitFixture -Dir $mainDir -Url 'https://example.invalid/lwgfixtureowner/lwgfixturerepo.git'
    $wtDir = Join-Path $t.dir 'worktree-ascii'
    [void][IO.Directory]::CreateDirectory($wtDir)
    [IO.File]::WriteAllText((Join-Path $wtDir '.git'), ("gitdir: $realGit`r`n"), $Utf8NoBom)
    $payload = '{"session_id":"lwg-merge-suite-session","model":{"display_name":"FixtureModel"},' +
               '"workspace":{"current_dir":"' + $wtDir.Replace('\', '/') + '"}}'
    $r = Invoke-StatusLineRaw -ProfileDir $t.profile -ScriptPath $slCopy -PayloadBytes ($Utf8NoBom.GetBytes($payload))
    Add-Result 'status line: a worktree .git file naming a non-ASCII path still resolves owner/repo' `
        ($r.out -match 'lwgfixtureowner/lwgfixturerepo') `
        "the .git file pointed at a real git directory and the row lost the segment. A worktree is a shape this file renders a [wt:] marker for, so it is an expected workflow rather than an exotic one. Output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 23d. .git/config IS READ AS UTF-8 TOO.
    #
    #      The second of the two bare Get-Content calls. Its exposure is
    #      genuinely smaller - a GitHub owner or repository name cannot carry a
    #      non-ASCII character, so it needs a self-hosted or local-path remote -
    #      and it is fixed by the same one-word change.
    #
    #      BASELINE cc44c99: the slug rendered with the UTF-8 bytes decoded as
    #      Windows-1252, so the accented character came back as two.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'sl-utf8-remote' -Bytes $null
    $slCopy = Join-Path (Join-Path $t.profile '.claude') 'statusline.ps1'
    [IO.File]::Copy($RepoStatusLine, $slCopy, $true)
    $repoDir = Join-Path $t.dir 'checkout-ascii'
    [void][IO.Directory]::CreateDirectory($repoDir)
    [void](New-GitFixture -Dir $repoDir -Url ('https://example.invalid/lwgfixture' + $acc + 'owner/lwgfixturerepo.git'))
    $payload = '{"session_id":"lwg-merge-suite-session","model":{"display_name":"FixtureModel"},' +
               '"workspace":{"current_dir":"' + $repoDir.Replace('\', '/') + '"}}'
    $r = Invoke-StatusLineRaw -ProfileDir $t.profile -ScriptPath $slCopy -PayloadBytes ($Utf8NoBom.GetBytes($payload))
    Add-Result 'status line: a non-ASCII remote URL is decoded as UTF-8, not as ANSI' `
        ($r.out -match ([regex]::Escape('lwgfixture' + $acc + 'owner/lwgfixturerepo'))) `
        "the remote URL was written as UTF-8, which is what git writes, and the row printed something else. Output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 23e. A PERCENTAGE THAT WILL NOT PARSE IS NOT A GREEN ALL-CLEAR.
    #
    #      Every number the status line took from outside was coerced with a
    #      bare [double] under $ErrorActionPreference = 'SilentlyContinue'. A
    #      failed cast in an assignment under that preference does not stop the
    #      script and does not print: the assignment simply does not happen. So
    #      an unparseable used_percentage rendered as a GREEN '%' with no digits
    #      in front of it AND produced no advisory - the state row 2 uses to
    #      mean nothing is wrong. That is the false all-clear the HH glyph table
    #      is written against, arrived at from the numeric side.
    #
    #      BASELINE cc44c99: `5h %` in green paint (32), and NO second row.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'sl-badpct' -Bytes $null
    $slCopy = Join-Path (Join-Path $t.profile '.claude') 'statusline.ps1'
    [IO.File]::Copy($RepoStatusLine, $slCopy, $true)
    $payload = '{"session_id":"lwg-merge-suite-session","model":{"display_name":"FixtureModel"},' +
               '"rate_limits":{"five_hour":{"used_percentage":"n/a"}},' +
               '"workspace":{"current_dir":"' + $t.dir.Replace('\', '/') + '"}}'
    $r = Invoke-StatusLine -ProfileDir $t.profile -ScriptPath $slCopy -PayloadJson $payload
    Add-Result 'status line: an unparseable percentage renders its own glyph, not a bare green %' `
        ($r.out -match '\?\?') `
        "the segment rendered [$($r.out)]. Present-but-unusable is a third fact and must not look like either of the other two."
    Add-Result 'status line: an unparseable percentage does not silently suppress the advisory row' `
        ($r.out -match 'would not parse') `
        "row 2 said nothing, which is what it says when everything is fine. Output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 23f. A CONFIGURED 0 IS A VALUE, NOT AN ABSENCE.
    #
    #      The threshold reads were `if ($cfg.thresholds...)`, a PowerShell
    #      truthiness test, so a configured 0 was falsy and discarded. 0 means
    #      "warn always" and it was the one value the operator could not set.
    #
    #      BASELINE cc44c99: no advisory row at all - the built-in 88 was in
    #      force and 1% is nowhere near it.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'sl-zero-threshold' -Bytes $null
    $slRootZ = New-MarketplaceRoot -ProfileDir $t.profile -PluginName $PluginName -Contents 'full'
    [IO.File]::WriteAllText((Join-Path $slRootZ 'config.json'),
        '{"thresholds":{"ratelimit":{"warn_pct":0,"land_all_pct":92}}}')
    $slCopy = Join-Path (Join-Path $t.profile '.claude') 'statusline.ps1'
    [IO.File]::Copy($RepoStatusLine, $slCopy, $true)
    $payload = '{"session_id":"lwg-merge-suite-session","model":{"display_name":"FixtureModel"},' +
               '"rate_limits":{"five_hour":{"used_percentage":1}},' +
               '"workspace":{"current_dir":"' + $t.dir.Replace('\', '/') + '"}}'
    $r = Invoke-StatusLine -ProfileDir $t.profile -ScriptPath $slCopy -PayloadJson $payload
    Add-Result 'status line: a configured threshold of 0 is honoured rather than read as absent' `
        ($r.out -match '5h 1% - approaching limit') `
        "warn_pct is 0 in the planted config and 1% did not warn, so the built-in 88 was used instead and nothing said so. Output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 23g. A THRESHOLD THAT WILL NOT PARSE IS NAMED, NOT SWAPPED IN SILENCE.
    #
    #      "80%" is the obvious thing to type in a file whose key is named
    #      _pct. It failed the cast, the built-in stood, and there was no
    #      message on the status line and none in /lw-watchtower:doctor - whose
    #      config-registry check reads nothing under `thresholds` and still
    #      does not.
    #
    #      BASELINE cc44c99: the row said nothing about it.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'sl-bad-threshold' -Bytes $null
    $slRootB = New-MarketplaceRoot -ProfileDir $t.profile -PluginName $PluginName -Contents 'full'
    [IO.File]::WriteAllText((Join-Path $slRootB 'config.json'),
        '{"thresholds":{"ratelimit":{"warn_pct":"80%","land_all_pct":92}}}')
    $slCopy = Join-Path (Join-Path $t.profile '.claude') 'statusline.ps1'
    [IO.File]::Copy($RepoStatusLine, $slCopy, $true)
    $payload = '{"session_id":"lwg-merge-suite-session","model":{"display_name":"FixtureModel"},' +
               '"rate_limits":{"five_hour":{"used_percentage":90}},' +
               '"workspace":{"current_dir":"' + $t.dir.Replace('\', '/') + '"}}'
    $r = Invoke-StatusLine -ProfileDir $t.profile -ScriptPath $slCopy -PayloadJson $payload
    Add-Result 'status line: a configured threshold that will not parse is named on the row' `
        ($r.out -match 'thresholds\.ratelimit\.warn_pct is not a number') `
        "the operator's file said something the script could not use, the script read it, could not use it, and said nothing. Output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 23h. THE NUMBER PRINTED AND THE NUMBER COMPARED ARE THE SAME NUMBER.
    #
    #      Display rounded with '{0:0}%', comparisons made on the raw double.
    #      So ctx 89.6 printed "90%" - which config.json defines as
    #      critical_pct - in the YELLOW of the band below, beside the
    #      sub-critical "plan for compaction" advisory quoting 90% back. The
    #      rate-limit direction costs more: 91.5 prints "92%", which
    #      config.json defines as land_all_pct, beside "approaching limit".
    #
    #      BASELINE cc44c99, one run, both limbs:
    #        ! ctx 90% - plan for compaction  7d/5h 92% - approaching limit
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'sl-rounding' -Bytes $null
    $slCopy = Join-Path (Join-Path $t.profile '.claude') 'statusline.ps1'
    [IO.File]::Copy($RepoStatusLine, $slCopy, $true)
    $payload = '{"session_id":"lwg-merge-suite-session","model":{"display_name":"FixtureModel"},' +
               '"context_window":{"used_percentage":89.6},' +
               '"rate_limits":{"five_hour":{"used_percentage":91.5}},' +
               '"workspace":{"current_dir":"' + $t.dir.Replace('\', '/') + '"}}'
    $r = Invoke-StatusLine -ProfileDir $t.profile -ScriptPath $slCopy -PayloadJson $payload
    Add-Result 'status line: a context figure printed as 90% advises in the band the docs call 90' `
        ($r.out -match 'ctx 90% CRITICAL') `
        "the row printed 90% and gave the advice for the band below it, so the printed number and the printed advice contradict each other against the documented thresholds. Output:`n$($r.out)"
    Add-Result 'status line: a rate limit printed as 92% advises land all work, not approaching' `
        ($r.out -match '5h 92% - land all work') `
        "92 is land_all_pct in config.json and the row printed 92% beside the approaching-limit text. Output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 23i. A BRACKET IN THE INSTALL PATH MUST NOT MAKE THE INSTALL INVISIBLE.
    #
    #      Three presence probes used Test-Path with no -LiteralPath, so a
    #      derived path was interpreted as a WILDCARD PATTERN. '[uat]' is a
    #      character class matching one of u, a, t; the pattern matches nothing;
    #      Test-Path returns $false for a file that is on disk, with no error,
    #      indistinguishably from absent. 'repo [2]' is the shape Windows itself
    #      produces when a folder is copied.
    #
    #      BASELINE cc44c99: purple HH? - which MEANS NOT INSTALLED - about a
    #      complete install, and no configured threshold read.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'sl-bracket' -Bytes $null
    $brBase = Join-Path $t.dir 'plugins [uat]'
    $slRootBr = New-MarketplaceRoot -ProfileDir $t.profile -PluginName $PluginName -Contents 'full' -PluginsBase $brBase
    [IO.File]::WriteAllText((Join-Path $slRootBr 'config.json'),
        '{"thresholds":{"context":{"warn_pct":1,"critical_pct":99}}}')
    $slCopy = Join-Path (Join-Path $t.profile '.claude') 'statusline.ps1'
    [IO.File]::Copy($RepoStatusLine, $slCopy, $true)
    $payload = '{"session_id":"lwg-merge-suite-session","model":{"display_name":"FixtureModel"},' +
               '"context_window":{"used_percentage":10},' +
               '"workspace":{"current_dir":"' + $t.dir.Replace('\', '/') + '"}}'
    $r = Invoke-StatusLine -ProfileDir $t.profile -ScriptPath $slCopy -PayloadJson $payload -CacheDir $brBase
    Add-Result 'status line: an install path containing a bracket is not reported as NOT INSTALLED' `
        ($r.out -notmatch 'HH\?') `
        "the install is complete and the segment rendered the glyph whose documented remedy is to install the plugin. Output:`n$($r.out)"
    Add-Result 'status line: the config under a bracketed install path is still read' `
        ($r.out -match 'plan for compaction') `
        "context is 10% and the planted config warns at 1%, so the advisory must appear. Every configured threshold was discarded instead. Output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 23j. A config.json IN THE PROFILE ROOT IS NOT THIS PLUGIN'S CONFIG.
    #
    #      For the INSTALLED copy at ~\.claude\statusline.ps1, candidate 2 of
    #      the plugin-root list - this script's own parent - is the PROFILE
    #      ROOT, and it is tried before the real install. GmConfig OPENS a
    #      candidate's config.json rather than merely testing for one, so a file
    #      belonging to some other tool was parsed and used as this plugin's
    #      configuration on every render.
    #
    #      THE FIXTURE'S STRANGER CARRIES A `thresholds` BLOCK ON PURPOSE. A
    #      shape test alone would not reject it; only refusing a candidate with
    #      no plugin marker beside it does. That is the harder half of the
    #      defect and the one worth pinning.
    #
    #      BASELINE cc44c99: the stranger's 99 was in force and no advisory
    #      appeared at 10%.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'sl-profile-config' -Bytes $null
    [IO.File]::WriteAllText((Join-Path $t.profile 'config.json'),
        '{"thresholds":{"context":{"warn_pct":99,"critical_pct":99}}}')
    $slRootP = New-MarketplaceRoot -ProfileDir $t.profile -PluginName $PluginName -Contents 'full'
    [IO.File]::WriteAllText((Join-Path $slRootP 'config.json'),
        '{"thresholds":{"context":{"warn_pct":1,"critical_pct":99}}}')
    $slCopy = Join-Path (Join-Path $t.profile '.claude') 'statusline.ps1'
    [IO.File]::Copy($RepoStatusLine, $slCopy, $true)
    $payload = '{"session_id":"lwg-merge-suite-session","model":{"display_name":"FixtureModel"},' +
               '"context_window":{"used_percentage":10},' +
               '"workspace":{"current_dir":"' + $t.dir.Replace('\', '/') + '"}}'
    $r = Invoke-StatusLine -ProfileDir $t.profile -ScriptPath $slCopy -PayloadJson $payload
    Add-Result 'status line: a stranger''s config.json in the profile root does not win over the plugin''s' `
        ($r.out -match 'plan for compaction') `
        "a config.json belonging to something else sat in the profile root and its thresholds were used as this plugin's. Output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 23k. Stop.failed_tasks IS A GAUGE, AND HH MUST NOT SUM IT.
    #
    #      lib\supervisor.ps1 writes one Stop record at EVERY turn end holding
    #      the number of background tasks in a failed/killed state at that
    #      moment, and it writes it BEFORE its own alerted.json dedupe - so the
    #      dedupe suppresses the repeated ALERT, never the repeated RECORD.
    #      Summing that field turned one dead task into HH1, then HH2, then HH3
    #      for the rest of the session, with nothing about the machine having
    #      got worse in between.
    #
    #      THE FIXTURE IS THREE IDENTICAL-COUNT RECORDS SECONDS APART IN ONE
    #      FILE, which the existing cross-file dedup deliberately does not
    #      touch - two records in the SAME file are two writes that writer
    #      really made.
    #
    #      BASELINE cc44c99: HH3.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'sl-gauge' -Bytes $null
    $null = New-MarketplaceRoot -ProfileDir $t.profile -PluginName $PluginName -Contents 'full'
    $dataDir = Join-Path $t.profile '.claude\plugins\data\lw-watchtower-merge-fixture'
    [void][IO.Directory]::CreateDirectory($dataDir)
    $sid = 'lwg-merge-suite-session'
    $stops = @(
        '{"ts":"2026-08-01T10:00:00.0000000Z","event":"Stop","session":"' + $sid + '","failed_tasks":1}'
        '{"ts":"2026-08-01T10:01:00.0000000Z","event":"Stop","session":"' + $sid + '","failed_tasks":1}'
        '{"ts":"2026-08-01T10:02:00.0000000Z","event":"Stop","session":"' + $sid + '","failed_tasks":1}'
    )
    [IO.File]::WriteAllText((Join-Path $dataDir 'health.jsonl'), (($stops -join "`r`n") + "`r`n"), $Utf8NoBom)
    $slCopy = Join-Path (Join-Path $t.profile '.claude') 'statusline.ps1'
    [IO.File]::Copy($RepoStatusLine, $slCopy, $true)
    $payload = '{"session_id":"' + $sid + '","model":{"display_name":"FixtureModel"},' +
               '"workspace":{"current_dir":"' + $t.dir.Replace('\', '/') + '"}}'
    $r = Invoke-StatusLine -ProfileDir $t.profile -ScriptPath $slCopy -PayloadJson $payload
    Add-Result 'status line: one failed task recorded at three turn ends is one fault, not three' `
        ($r.out -match 'HH1' -and $r.out -notmatch 'HH3') `
        "the fault count is a function of how many turns the session has run rather than of how many tasks are outstanding. Output:`n$($r.out)"

    # CONTROL, and it passes at cc44c99 too. The gauge still has to be COUNTED:
    # a "fix" that dropped the Stop arm altogether, or that clamped it to one,
    # would pass the case above and lose the fault the segment exists to report.
    $t = New-CaseTree -Tag 'sl-gauge-control' -Bytes $null
    $null = New-MarketplaceRoot -ProfileDir $t.profile -PluginName $PluginName -Contents 'full'
    $dataDir = Join-Path $t.profile '.claude\plugins\data\lw-watchtower-merge-fixture'
    [void][IO.Directory]::CreateDirectory($dataDir)
    [IO.File]::WriteAllText((Join-Path $dataDir 'health.jsonl'),
        ('{"ts":"2026-08-01T10:00:00.0000000Z","event":"Stop","session":"' + $sid + '","failed_tasks":2}' + "`r`n"),
        $Utf8NoBom)
    $slCopy = Join-Path (Join-Path $t.profile '.claude') 'statusline.ps1'
    [IO.File]::Copy($RepoStatusLine, $slCopy, $true)
    $payload = '{"session_id":"' + $sid + '","model":{"display_name":"FixtureModel"},' +
               '"workspace":{"current_dir":"' + $t.dir.Replace('\', '/') + '"}}'
    $r = Invoke-StatusLine -ProfileDir $t.profile -ScriptPath $slCopy -PayloadJson $payload
    Add-Result 'CONTROL status line: two failed tasks in the newest Stop record still read as two faults' `
        ($r.out -match 'HH2') `
        "the newest gauge said two and the segment did not report two. Output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 23l. THE RESET CLOCK KEEPS ITS am/pm ON A NON-ENGLISH WINDOWS.
    #
    #      Stamp formatted with the CURRENT culture and then applied a
    #      hardcoded English AM/PM fixup, which only fires when the designator
    #      is literally 'AM' or 'PM'. Under Windows PowerShell 5.1 - the
    #      interpreter this file declares and the one bin\lwg-setup.ps1 and
    #      docs\install.md both wire the status line to - 48 specific cultures
    #      have an EMPTY designator, so the row printed a 12-hour clock with
    #      nothing after it and the reset time was ambiguous by twelve hours.
    #      The '/' in the format string is the culture's DATE SEPARATOR too.
    #
    #      THE CULTURE HAS TO BE FORCED IN THE CHILD. A child powershell.exe
    #      takes its culture from the user locale, not from this process, so
    #      the case runs the REAL FILE through -Command with CurrentCulture set
    #      first - never a copy of Stamp pasted in here, which would prove
    #      nothing about what ships.
    #
    #      BASELINE cc44c99 under de-DE: `(07.31 11:45)`. No designator, and
    #      the date separator is not the one the format string spells.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'sl-culture' -Bytes $null
    $slCopy = Join-Path (Join-Path $t.profile '.claude') 'statusline.ps1'
    [IO.File]::Copy($RepoStatusLine, $slCopy, $true)
    $payload = '{"session_id":"lwg-merge-suite-session","model":{"display_name":"FixtureModel"},' +
               '"rate_limits":{"seven_day":{"used_percentage":93,"resets_at":"2026-07-31T15:45:00Z"}},' +
               '"workspace":{"current_dir":"' + $t.dir.Replace('\', '/') + '"}}'
    # The hour and the date are LOCAL, so neither is asserted - only the shape:
    # two digits, the separator the format string spells, and a designator.
    $clock = '\(\d\d/\d\d \d{1,2}(:\d\d)?[ap]m\)'
    $r = Invoke-StatusLineRaw -ProfileDir $t.profile -ScriptPath $slCopy `
                              -PayloadBytes ($Utf8NoBom.GetBytes($payload)) -Culture 'de-DE'
    Add-Result 'status line: the 7d reset clock keeps its am/pm designator under de-DE' `
        ($r.out -match $clock) `
        "the segment whose whole job is to say when a limit resets printed a 12-hour time a reader cannot place. Output:`n$($r.out)"

    # CONTROL, and it passes at cc44c99 too: en-US was never the broken case,
    # and a "fix" that dropped the designator entirely would pass the case above.
    $r = Invoke-StatusLineRaw -ProfileDir $t.profile -ScriptPath $slCopy `
                              -PayloadBytes ($Utf8NoBom.GetBytes($payload)) -Culture 'en-US'
    Add-Result 'CONTROL status line: the same reset clock is unchanged under en-US' `
        ($r.out -match $clock) `
        "the documented format is MM/dd h:mmtt and en-US must keep rendering exactly that. Output:`n$($r.out)"

    # ===================================================================
    # 26. bin\lwg-update.ps1, WHICH NOTHING HAS EVER EXERCISED.
    #
    #     Not with -Apply, not without it. Every UAT row that touched it used
    #     -Root <clone> -Offline -SkipDoctor, i.e. the paths below were reached
    #     by nothing.
    #
    #     THIS SECTION NEEDS git ON PATH and aborts the suite without it, which
    #     is a new external dependency for this file and is said out loud. Not
    #     running is not the same as passing, so a missing git must not be a
    #     skip. Every "remote" is a LOCAL BARE REPOSITORY under the scratch
    #     tree - there is no URL anywhere in this section and no case can reach a
    #     network.
    #
    #     BASELINE: cc44c99, run as a byte copy of the tree exported with
    #     `git archive`. Each case states what it printed there.
    # ===================================================================
    $gv = ''
    $prevEap = $ErrorActionPreference
    try { $ErrorActionPreference = 'Continue'; $gv = (& git --version 2>&1 | Out-String) } finally { $ErrorActionPreference = $prevEap }
    if ($LASTEXITCODE -ne 0) {
        throw "git is not on PATH, so section 26 could not run at all. That is an abort and not a skip: a suite that quietly drops the only coverage bin\lwg-update.ps1 has is the empty-set pass this repo has been bitten by. ($gv)"
    }

    # -------------------------------------------------------------------
    # 26a. -Offline WITH -Apply IS REFUSED, AND MERGES NOTHING.
    #
    #      -Offline is documented in two places as not touching the network, and
    #      -Apply runs `git pull`, which fetches. $Offline was consulted in
    #      exactly one place - the reporting fetch - and section 5 never looked
    #      at it. Worse than the broken promise: the INCOMING FILES list and the
    #      NEEDS RE-APPROVAL block were computed from the stale tracking ref
    #      before the pull, and the in-pull fetch then moved the tip underneath
    #      them, so the block commands/update.md orders reported "in full, even
    #      when it is empty" described a state that no longer existed.
    #
    #      BASELINE cc44c99: the pull ran, HEAD moved to the incoming commit,
    #      and the row read '[OK  ] pull  Updating ... / Fast-forward'.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'update-offline-apply' -Bytes $null
    $pair = New-BehindClone -Dir (Join-Path $t.dir 'repos')
    $headBefore = (Invoke-Git -WorkDir $pair.consumer -GitArgs @('rev-parse', 'HEAD')).Trim()
    $a = Invoke-Update -ProfileDir $t.profile -Arguments @('-Root', $pair.consumer, '-Offline', '-Apply', '-SkipDoctor')
    $headAfter = (Invoke-Git -WorkDir $pair.consumer -GitArgs @('rev-parse', 'HEAD')).Trim()
    Add-Result 'update: -Offline with -Apply is refused rather than fetching anyway' `
        ($a.out -match 'REFUSED - -Offline forbids the network') `
        "the run did not refuse. `git pull` fetches, so -Offline and -Apply cannot both be honoured. Output:`n$($a.out)"
    Add-Result 'update: -Offline with -Apply leaves the checkout on the commit it started from' `
        ($headBefore -eq $headAfter) `
        "HEAD moved from $headBefore to $headAfter on a run whose own fetch row says no fetch was made, and whose incoming-file list was computed before the merge."

    # -------------------------------------------------------------------
    # 26b. A BRANCH THAT IS AHEAD DOES NOT INVENT INCOMING FILES.
    #
    #      `git diff HEAD..$upstream` is a TREE comparison, so it lists files
    #      changed only by the operator's own unpushed commits. That list was
    #      labelled INCOMING FILES and fed to the re-approval logic, so a
    #      diverged checkout was told to expect a hook re-approval that was not
    #      coming - and $needs.Count forces exit 2.
    #
    #      The local commit touches hooks/hooks.json and the INCOMING commit
    #      touches notes.md, so the only way hooks/hooks.json can appear is the
    #      two-dot comparison.
    #
    #      BASELINE cc44c99: 'NEEDS RE-APPROVAL OR RE-INSTALL (1):' naming
    #      hooks/hooks.json, and hooks/hooks.json listed under INCOMING FILES.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'update-ahead' -Bytes $null
    $pair = New-BehindClone -Dir (Join-Path $t.dir 'repos')
    $localHooks = Join-Path $pair.consumer 'hooks\hooks.json'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $localHooks))
    [IO.File]::WriteAllText($localHooks, '{"hooks":{}}' + "`r`n")
    [void](Invoke-Git -WorkDir $pair.consumer -GitArgs @('add', '-A'))
    [void](Invoke-Git -WorkDir $pair.consumer -GitArgs @('commit', '--quiet', '-m', 'lwg fixture: local commit, not pushed'))
    $a = Invoke-Update -ProfileDir $t.profile -Arguments @('-Root', $pair.consumer, '-Offline', '-SkipDoctor')
    Add-Result 'update: a file changed only by an unpushed local commit is not reported as incoming' `
        ($a.out -notmatch 'hooks/hooks\.json changes:') `
        "the checkout is 1 ahead and 1 behind, and the re-approval block named a file the upstream never touched. Output:`n$($a.out)"
    Add-Result 'update: the changes row names the ahead count where the incoming list is read' `
        ($a.out -match 'commit\(s\) AHEAD') `
        "nothing beside the incoming list said the branch had diverged, which is why the contamination was invisible where it mattered. Output:`n$($a.out)"

    # -------------------------------------------------------------------
    # 26c. EXIT 4 MEANS "the doctor failed AFTER the update", SO IT NEEDS ONE.
    #
    #      It was selected from the doctor's exit code alone, above the refusal
    #      test, so a check-only run returned 4 - and commands/update.md tells
    #      the model that 4 means the doctor failed after the update and to "not
    #      describe the update as successful", which presupposes one.
    #
    #      The doctor here is a stub that exits 1. Its verdict is not what is
    #      being tested; the CAUSAL ATTRIBUTION on the exit code is.
    #
    #      BASELINE cc44c99: exit 4 on a run that merged nothing.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'update-doctor-nopull' -Bytes $null
    $pair = New-BehindClone -Dir (Join-Path $t.dir 'repos')
    $stubDir = Join-Path $pair.consumer 'bin'
    [void][IO.Directory]::CreateDirectory($stubDir)
    [IO.File]::WriteAllText((Join-Path $stubDir 'lwg-doctor.ps1'),
        "param([switch]`$Quiet)`r`nWrite-Output 'lwg fixture doctor - deliberately failing'`r`nexit 1`r`n")
    # COMMITTED, not left in the working tree. An uncommitted file is a dirty
    # tree, which is a real [FAIL] worktree and a real refusal - the run would
    # then exit 1 for a reason that has nothing to do with the doctor, and the
    # case would be green against the wrong cause.
    [void](Invoke-Git -WorkDir $pair.consumer -GitArgs @('add', '-A'))
    [void](Invoke-Git -WorkDir $pair.consumer -GitArgs @('commit', '--quiet', '-m', 'lwg fixture: a doctor that fails'))
    $a = Invoke-Update -ProfileDir $t.profile -Arguments @('-Root', $pair.consumer, '-Offline')
    Add-Result 'update: a doctor failure on a run that merged nothing does not exit 4' `
        ($a.code -ne 4) `
        "exit 4 is documented and reported as 'the doctor FAILED after the update'. Nothing was pulled on this run, so there was no update for it to be after. Output:`n$($a.out)"
    Add-Result 'update: that run exits 2 - finished with caveats - and not 1' `
        ($a.code -eq 2) `
        "exited $($a.code). Exit 1's documented meaning is 'REFUSED ... nothing was changed', which is a statement about this script's own refusals and not about a finding the doctor made on the tree as it already stood. Output:`n$($a.out)"

    # -------------------------------------------------------------------
    # 26d. ARRIVING THROUGH THE SKILLS JUNCTION IS THE INTENDED ROUTE.
    #
    #      $Root is $PSScriptRoot's parent, not canonicalised through reparse
    #      points, and the loaded-copy row compared it against the junction's
    #      TARGET as text - two different strings by definition. So the route
    #      commands/update.md actually uses produced a WARN saying this is not
    #      the checkout Claude Code loads, about the checkout it loads. The WARN
    #      forces exit 2 and the slash command told the model to report a
    #      correct update as landing in the wrong place.
    #
    #      mklink /J makes a DIRECTORY JUNCTION and needs no elevation, unlike a
    #      symbolic link. If it cannot be created the case ABORTS rather than
    #      passing on an absent fixture.
    #
    #      BASELINE cc44c99: '[WARN] loaded-copy  the junction points at
    #      ...\consumer, which is NOT this checkout.'
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'update-junction' -Bytes $null
    $pair = New-BehindClone -Dir (Join-Path $t.dir 'repos')
    $skills = Join-Path (Join-Path $t.profile '.claude') 'skills'
    [void][IO.Directory]::CreateDirectory($skills)
    $jn = Join-Path $skills $PluginName
    $mk = ''
    $prevEap = $ErrorActionPreference
    try { $ErrorActionPreference = 'Continue'; $mk = (& cmd /c mklink /J "$jn" "$($pair.consumer)" 2>&1 | Out-String) } finally { $ErrorActionPreference = $prevEap }
    if (-not [IO.Directory]::Exists($jn)) {
        throw "could not create a directory junction at ${jn}: $mk. The loaded-copy case cannot run without one and a skip would be a false pass."
    }
    $a = Invoke-Update -ProfileDir $t.profile -Arguments @('-Root', $jn, '-Offline', '-SkipDoctor')
    Add-Result 'update: a checkout invoked THROUGH the skills junction is not warned about' `
        ($a.out -match '(?m)^\s+\[OK\s*\]\s+loaded-copy') `
        "the junction path IS the path Claude Code loads, and the row said it was not this checkout. Output:`n$($a.out)"

    # CONTROL, and it passes at cc44c99 too: a checkout that is genuinely not the
    # junction's target still has to be reported. Without this, "never warn"
    # would pass the case above and destroy the row's whole purpose.
    $other = Join-Path $t.dir 'a-different-checkout'
    [void](Invoke-Git -WorkDir $t.dir -GitArgs @('clone', '--quiet', '--branch', 'main', $pair.bare, $other))
    $a = Invoke-Update -ProfileDir $t.profile -Arguments @('-Root', $other, '-Offline', '-SkipDoctor')
    Add-Result 'CONTROL update: a checkout that is NOT the junction target is still reported' `
        ($a.out -match '(?m)^\s+\[WARN\]\s+loaded-copy') `
        "the junction points at one directory and this run was pointed at another; the row must say it could not reconcile them. Output:`n$($a.out)"

    # -------------------------------------------------------------------
    # 26e. A PULL THAT FAILED DOES NOT GET TO DESCRIBE THE CHECKOUT.
    #
    #      bin\lwg-update.ps1's own header promises, at lines 21-22, that it
    #      "will not call a failed or timed-out git command a clean result" and
    #      that every subprocess failure "is reported as UNKNOWN". The pull's
    #      failure row broke that promise: on state `nonzero` it appended two
    #      sentences nothing had established - that nothing was merged, and that
    #      the cause is branch divergence - and on missing/error it appended the
    #      first of them.
    #
    #      NEITHER IS OBSERVED. `git pull` is a fetch and then a merge, and a
    #      non-zero exit reported by git is not the same fact as a checkout that
    #      did not move. --ff-only refuses for reasons other than divergence -
    #      a broken index, a missing object, a refused fetch - and the row named
    #      one of them regardless.
    #
    #      DIVERGENCE IS GIT'S CLAIM TO MAKE. git says so itself on stderr here
    #      and Get-LwgToolReport already prints that line, so the script's own
    #      guess added nothing where it was right and invented a cause where it
    #      was not.
    #
    #      NOT -Offline: the fetch has to run for this to be the state git
    #      really refuses in, and the "remote" is the bare repository next door.
    #
    #      BASELINE a2d9447: the pull row read '... - git refused and reported
    #      it, so nothing was merged. A fast-forward that will not apply usually
    #      means the branches have diverged; resolve that by hand. git status
    #      now reports # branch.ab +1 -1 with 0 uncommitted change(s)', with the
    #      word UNKNOWN nowhere in it and the state it failed in never named.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'update-pull-nonzero' -Bytes $null
    $pair = New-BehindClone -Dir (Join-Path $t.dir 'repos')
    [IO.File]::WriteAllText((Join-Path $pair.consumer 'local.md'), "lwg fixture local`r`n")
    [void](Invoke-Git -WorkDir $pair.consumer -GitArgs @('add', '-A'))
    [void](Invoke-Git -WorkDir $pair.consumer -GitArgs @('commit', '--quiet', '-m', 'lwg fixture: local commit, not pushed'))
    $a = Invoke-Update -ProfileDir $t.profile -Arguments @('-Root', $pair.consumer, '-Apply', '-SkipDoctor')
    $row = (@($a.out -split "`r?`n" | Where-Object { $_ -match '^\s+\[FAIL\]\s+pull\s' }) -join ' ')
    Add-Result 'update: a pull git refused does not claim that nothing was merged' `
        ([bool]($row -and $row -notmatch 'nothing was merged')) `
        "the row said so about a command that fetches before it merges and was not watched while it did either. Row:`n$row`nOutput:`n$($a.out)"
    Add-Result 'update: a pull git refused does not guess branch divergence as the cause' `
        ([bool]($row -and $row -notmatch 'branches have diverged')) `
        "--ff-only refuses for more than one reason and this run observed none of them; git's own stderr line is already printed. Row:`n$row`nOutput:`n$($a.out)"
    Add-Result 'update: the refused pull row reports the checkout state as UNKNOWN' `
        ([bool]($row -match 'UNKNOWN')) `
        "the header promises every bounded subprocess failure is reported as UNKNOWN, and this row reported a state instead. Row:`n$row`nOutput:`n$($a.out)"
    Add-Result 'update: the refused pull row names the state the pull failed in' `
        ([bool]($row -match "state 'nonzero'")) `
        "missing, timeout, nonzero and error are four different facts and the row has to say which one this was. Row:`n$row`nOutput:`n$($a.out)"

    # CONTROL, and both pass at a2d9447 too: the fix is to stop ADDING claims,
    # not to stop reporting. A row that dropped git's own words or stopped
    # asking git what the tree is now would pass the four cases above and be
    # worse than what it replaced.
    Add-Result "CONTROL update: the refused pull row still carries git's own words" `
        ([bool]($row -match 'git pull --ff-only exited')) `
        "Get-LwgToolReport's line is the only account of the failure anybody gets. Row:`n$row`nOutput:`n$($a.out)"
    Add-Result 'CONTROL update: the refused pull row still asks git what the tree is now' `
        ([bool]($row -match 'git status now reports')) `
        "UNKNOWN is the honest verdict, but the tree can be ASKED about, and the answer is the only evidence on the page. Row:`n$row`nOutput:`n$($a.out)"

    # -------------------------------------------------------------------
    # 26f. THE TIMED-OUT PULL, WHERE 'nothing was merged' WAS A LIE.
    #
    #      This is the state the old row was most wrong about, and the fixture
    #      shows why rather than arguing it: a post-merge hook that sleeps
    #      longer than the 20 s bound. git fast-forwards, moves HEAD, releases
    #      .git\index.lock, THEN runs the hook and hangs. Invoke-LwgCmdProcess
    #      kills the git process it started - not the hook's shell, which is a
    #      child of it - and returns state `timeout`. HEAD HAS ALREADY MOVED.
    #
    #      This case therefore asserts the row AND the head, because the head is
    #      what makes the row's old wording a false statement rather than a
    #      merely unproven one.
    #
    #      DEPENDENCY, ON TOP OF THIS SECTION'S git ON PATH: git's own hook
    #      shell, which Git for Windows bundles. The hook is written with LF
    #      endings and no BOM because that shell reads the shebang literally.
    #
    #      COST: this case spends ~20 s waiting for the bound, by design. There
    #      is no shorter way to observe a timeout that Invoke-LwgCmdProcess
    #      itself floors at 20 s.
    #
    #      BASELINE a2d9447: the row already said UNKNOWN here - that branch was
    #      right - so four of the five cases below are CONTROLs. What was
    #      missing is the state name.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'update-pull-timeout' -Bytes $null
    $pair = New-BehindClone -Dir (Join-Path $t.dir 'repos')
    [IO.File]::WriteAllText((Join-Path $pair.consumer '.git\hooks\post-merge'),
        "#!/bin/sh`nsleep 25`n", (New-Object Text.UTF8Encoding($false)))
    $headBefore = (Invoke-Git -WorkDir $pair.consumer -GitArgs @('rev-parse', 'HEAD')).Trim()
    $a = Invoke-Update -ProfileDir $t.profile -Arguments @('-Root', $pair.consumer, '-Apply', '-SkipDoctor')
    $headAfter = (Invoke-Git -WorkDir $pair.consumer -GitArgs @('rev-parse', 'HEAD')).Trim()
    $row = (@($a.out -split "`r?`n" | Where-Object { $_ -match '^\s+\[FAIL\]\s+pull\s' }) -join ' ')
    Add-Result 'update: the timed-out pull row names the state the pull failed in' `
        ([bool]($row -match "state 'timeout'")) `
        "a killed pull and a refused pull are different facts and the row has to say which one this was. Row:`n$row`nOutput:`n$($a.out)"
    Add-Result 'CONTROL update: the timed-out pull row reports the checkout state as UNKNOWN' `
        ([bool]($row -match 'UNKNOWN')) `
        "this branch was already right at a2d9447 and the fix must not lose it. Row:`n$row`nOutput:`n$($a.out)"
    Add-Result 'CONTROL update: the timed-out pull row does not claim that nothing was merged' `
        ([bool]($row -and $row -notmatch 'nothing was merged')) `
        "the case below shows HEAD moved on this very run, so the claim would be false and not merely unproven. Row:`n$row`nOutput:`n$($a.out)"
    Add-Result 'CONTROL update: the killed pull had ALREADY moved HEAD' `
        ([bool]($headBefore -ne $headAfter)) `
        "the fixture did not reproduce the state it exists to prove: HEAD is still $headBefore, so a killed pull that merged nothing was measured and this case establishes nothing about the row beside it. Output:`n$($a.out)"
    Add-Result 'CONTROL update: a killed pull exits 2 - finished with caveats - and not 1' `
        ([bool]($a.code -eq 2)) `
        "exited $($a.code). Exit 1's documented meaning is 'REFUSED ... nothing was changed', which is exactly the claim nobody can make about a pull killed mid-operation. Output:`n$($a.out)"

    # -------------------------------------------------------------------
    # 26g. THE OTHER TWO STATES, AND WHERE THEY CAN AND CANNOT BE REACHED.
    #
    #      Get-LwgToolReport distinguishes four failure states. Two of them
    #      cannot be produced at the pull row through this script AT ALL, and
    #      that is asserted here rather than left as a claim in a comment:
    #
    #        missing  section 1 runs `git --version` first and EXITS 2 on it, so
    #                 a run without git never reaches section 5. The case below
    #                 drives it and pins that: the git row is printed, no pull
    #                 row is, and nothing is called up to date.
    #        error    comes from Invoke-LwgCmdProcess's outer catch, which fires
    #                 on a fault in its own plumbing after Process.Start already
    #                 returned. Nothing a fixture can set from outside reaches
    #                 it. NO CASE HERE DRIVES `error`, and a green run says
    #                 nothing about that branch beyond the wording it shares
    #                 with the three above.
    #
    #      PATH is narrowed to the Windows directories for the child and
    #      RESTORED in a finally, the same contract Invoke-Setup keeps for
    #      USERPROFILE: this suite must not change the environment of whatever
    #      runs after it. WindowsPowerShell\v1.0 stays on it because
    #      Invoke-Update resolves `powershell` through PATH.
    #
    #      BOTH CASES PASS AT a2d9447. They are CONTROLs on the reachability
    #      claim, not evidence that anything was fixed.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'update-no-git' -Bytes $null
    $pair = New-BehindClone -Dir (Join-Path $t.dir 'repos')
    $prevPath = $env:PATH
    $a = @{ code = 255; out = '' }
    try {
        $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot;$env:SystemRoot\System32\WindowsPowerShell\v1.0"
        $a = Invoke-Update -ProfileDir $t.profile -Arguments @('-Root', $pair.consumer, '-Apply', '-SkipDoctor')
    } finally { $env:PATH = $prevPath }
    Add-Result 'CONTROL update: with git off PATH the run stops at the git row and prints no pull row at all' `
        ([bool](($a.out -match '(?m)^\s+\[FAIL\]\s+git\s') -and ($a.out -notmatch '(?m)^\s+\[\w+\s*\]\s+pull\s'))) `
        "the missing state is supposed to be unreachable at the pull row because section 1 exits on it. If a pull row appeared here, 26e and 26f are no longer the whole story and that branch needs a case of its own. Output:`n$($a.out)"
    Add-Result 'CONTROL update: with git off PATH nothing is reported as up to date' `
        ([bool]($a.out -match 'is not the same as being up to date')) `
        "a check that could not be made is not a check that passed, and this is the row that says so. Output:`n$($a.out)"

    # -------------------------------------------------------------------
    # 26h. THE STATUS-LINE ROW DESCRIBES THE FILE THIS MACHINE IS RUNNING (#77).
    #
    #      bin\lwg-update.ps1's section-4 row compared <config root>\statusline.ps1
    #      and nothing else - the target bin\lwg-setup.ps1 writes in its DEFAULT
    #      copy mode. The installer offers a second mode, and an operator whose
    #      status line is wired through the skills junction got
    #
    #        [INFO] statusline   no ...\.claude\statusline.ps1 - the HH segment
    #                            is not installed on this machine
    #
    #      about a status line that IS installed, IS this plugin's, and HAS
    #      drifted from the repo copy. The one state the row exists to catch was
    #      the one state it could not see. bin\lwg-doctor.ps1 check 7 was already
    #      resolving the target out of statusLine.command; this file was not, so
    #      two readers of one settings key disagreed about which file the
    #      operator runs.
    #
    #      THE FIXTURE IS A5's PROBE, BUILT HERE: a scratch profile whose
    #      settings.json wires statusLine.command at a DRIFTED copy under
    #      <profile>\.claude\skills\<plugin>\statusline\statusline.ps1, and NO
    #      <profile>\.claude\statusline.ps1 at all. Drifted deliberately - the
    #      copy is the repo bytes plus one comment line - so "found it" and
    #      "found it and compared it" are different results.
    #
    #      BASELINE ec80e88, measured through this harness:
    #        [INFO] statusline   no ...\profile\.claude\statusline.ps1 - the HH
    #                            segment is not installed on this machine
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'update-statusline-wired' -Bytes $null
    $pair = New-BehindClone -Dir (Join-Path $t.dir 'repos') -BaseFiles @{ 'statusline/statusline.ps1' = $repoStatusLineBytes }
    $wiredDir = Join-Path $t.profile (".claude\skills\" + $PluginName + '\statusline')
    [void][IO.Directory]::CreateDirectory($wiredDir)
    $wired = Join-Path $wiredDir 'statusline.ps1'
    [IO.File]::WriteAllBytes($wired, $repoStatusLineBytes)
    # The drift, appended as a comment so the file still parses. One byte would
    # do; a line says what it is for to whoever reads the fixture next.
    [IO.File]::AppendAllText($wired, "`r`n# lwg fixture: this copy has drifted from the repo copy`r`n")
    $sp = Join-Path $t.profile '.claude\settings.json'
    # ConvertTo-Json here rather than a hand-written literal, unlike the fixtures
    # at the top of this file: those are about the exact SHAPE of a settings
    # file and a round-trip would destroy them, whereas this one is about a
    # Windows path inside a JSON string, where hand-escaping the backslashes is
    # the thing most likely to be got wrong. It was, on the first attempt - the
    # path came back doubled and the case failed against a correct fix.
    [IO.File]::WriteAllText($sp,
        (@{ statusLine = @{ type = 'command'; command = ('powershell -NoProfile -File "' + $wired + '"'); refreshInterval = 120 } } |
            ConvertTo-Json -Depth 5),
        (New-Object Text.UTF8Encoding($false)))

    $a = Invoke-Update -ProfileDir $t.profile -Arguments @('-Root', $pair.consumer, '-Offline', '-SkipDoctor')
    $slRow = (@($a.out -split "`r?`n" | Where-Object { $_ -match '^\s+\[\w+\s*\]\s+statusline\s' }) -join ' ')

    Add-Result 'update: the status-line row does not report a wired status line as not installed' `
        ([bool]($slRow -and $slRow -notmatch 'not installed on this machine')) `
        "the status line IS installed, IS this plugin's and HAS drifted, and the row reported its absence. Row:`n$slRow`nOutput:`n$($a.out)"
    Add-Result 'update: the row names the file statusLine.command actually points at' `
        ([bool]($slRow -like "*$wired*")) `
        "the row must compare the file this machine runs, not the default copy target. Expected it to name $wired. Row:`n$slRow"
    Add-Result 'update: and reports it as DRIFTED, which is the state the row exists to catch' `
        ([bool]($slRow -match '(?m)\[WARN\]' -and $slRow -match 'DIFFERS')) `
        "the wired copy is the repo bytes plus one line, so the only correct answer is a drift warning. Row:`n$slRow"
    Add-Result 'update: the re-approval note names the same file the row does' `
        ([bool]($a.out -notmatch [regex]::Escape((Join-Path $t.profile '.claude\statusline.ps1')))) `
        "the note at the top of section 4 named the default copy target unconditionally, so it told the operator to re-copy a file that is not the live one - while the row talked about a third. Output:`n$($a.out)"

    # CONTROL, and it passes at ec80e88 too: with NO statusLine.command set, the
    # default copy target is still the right thing to talk about. Without this,
    # "always read settings.json" would pass the four cases above and lose the
    # machine that has not wired anything up yet.
    $t2 = New-CaseTree -Tag 'update-statusline-default' -Bytes $null
    $pair2 = New-BehindClone -Dir (Join-Path $t2.dir 'repos') -BaseFiles @{ 'statusline/statusline.ps1' = $repoStatusLineBytes }
    $def2 = Join-Path $t2.profile '.claude\statusline.ps1'
    [IO.File]::WriteAllBytes($def2, $repoStatusLineBytes)
    [IO.File]::AppendAllText($def2, "`r`n# lwg fixture: the default copy has drifted too`r`n")
    $b = Invoke-Update -ProfileDir $t2.profile -Arguments @('-Root', $pair2.consumer, '-Offline', '-SkipDoctor')
    $slRow2 = (@($b.out -split "`r?`n" | Where-Object { $_ -match '^\s+\[\w+\s*\]\s+statusline\s' }) -join ' ')
    Add-Result 'CONTROL update: with no statusLine.command the default copy target is still compared' `
        ([bool]($slRow2 -like "*$def2*" -and $slRow2 -match 'DIFFERS')) `
        "a machine that has never wired the status line up must still be told its default copy has drifted. Row:`n$slRow2`nOutput:`n$($b.out)"

    # -------------------------------------------------------------------
    # 26i. THE REFUSAL NAMES WHAT IS DIRTY, AND SAYS WHICH OF IT THE PLUGIN
    #      WROTE ITSELF (#11).
    #
    #      config.json is TRACKED, and /lw-watchtower:config and the toggle
    #      commands write into it. So arming a gate dirties the plugin's own
    #      checkout, and the next /lw-watchtower:update refuses:
    #
    #        [FAIL] worktree     1 uncommitted change(s) on main. This command
    #                            does not stash, reset or check out anything -
    #                            commit or set them aside first.
    #
    #      That sentence names no file. It reads to an operator as their own
    #      work in progress, and it is not - the plugin wrote it, by doing the
    #      thing the plugin is for. Batch A1 reproduced the whole chain end to
    #      end and refused to half-fix it, correctly: moving the WRITE without
    #      moving the READ produces a silent no-op that the command's own exit-2
    #      verification would report as verified. That decision is above a
    #      builder and is still open on #11.
    #
    #      WHAT IS LANDABLE HERE IS THE SENTENCE, which #11's own "what done
    #      looks like" asks for as the minimum. The same row is what makes #214
    #      hurt, so it is worth more than one issue.
    #
    #      TWO DIRTY PATHS, ONE OF EACH KIND: config.json, which the plugin
    #      writes, and a file that is nobody's but the operator's. A case with
    #      only config.json in it would pass against a row that names every
    #      dirty path and says nothing about which one this plugin caused.
    #
    #      BASELINE ec80e88: "2 uncommitted change(s) on main. This command does
    #      not stash..." - no path, no mention of config.json.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'update-dirty-named' -Bytes $null
    $pair = New-BehindClone -Dir (Join-Path $t.dir 'repos') -BaseFiles @{
        'config.json'      = $Utf8NoBom.GetBytes('{"modules":{}}')
        'operator-work.md' = $Utf8NoBom.GetBytes("original`r`n")
    }
    [IO.File]::WriteAllText((Join-Path $pair.consumer 'config.json'), '{"modules":{"git_hygiene":false}}')
    [IO.File]::WriteAllText((Join-Path $pair.consumer 'operator-work.md'), "edited by the operator`r`n")
    $a = Invoke-Update -ProfileDir $t.profile -Arguments @('-Root', $pair.consumer, '-Offline', '-SkipDoctor')
    $wtRow = (@($a.out -split "`r?`n" | Where-Object { $_ -match '^\s+\[\w+\s*\]\s+worktree\s' }) -join ' ')

    Add-Result 'update: the worktree refusal names the files that are dirty' `
        ([bool]($wtRow -match 'config\.json' -and $wtRow -match 'operator-work\.md')) `
        "the row counted the changes and threw the paths away, so it reads as the operator's own work in progress whatever caused it. Row:`n$wtRow"
    Add-Result 'update: and says config.json is one this plugin writes itself (#11)' `
        ([bool]($wtRow -match 'toggle commands' -and $wtRow -match '#11')) `
        "config.json is tracked and /lw-watchtower:config writes into it, so arming a gate refuses the next update over a change the operator did not make. Naming the file is not the fix - moving the write needs the reader moved with it, which is #11 - but the operator must at least be told which of these is theirs. Row:`n$wtRow"
    Add-Result 'update: the refusal still refuses - nothing about naming it makes it a warning' `
        ([bool]($wtRow -match '\[FAIL\]' -and $a.out -match 'does not stash, reset or check out anything')) `
        "a dirty tree is still a refusal; this section only changes what the refusal says. Row:`n$wtRow"

    # CONTROL, and it passes at ec80e88 too: a CLEAN tree must not grow a list.
    # Without it, "always print the paths" is satisfied by a row that prints an
    # empty one on every run.
    $t2 = New-CaseTree -Tag 'update-clean-named' -Bytes $null
    $pair2 = New-BehindClone -Dir (Join-Path $t2.dir 'repos')
    $b = Invoke-Update -ProfileDir $t2.profile -Arguments @('-Root', $pair2.consumer, '-Offline', '-SkipDoctor')
    $wtRow2 = (@($b.out -split "`r?`n" | Where-Object { $_ -match '^\s+\[\w+\s*\]\s+worktree\s' }) -join ' ')
    Add-Result 'CONTROL update: a clean worktree is still reported clean, with no file list' `
        ([bool]($wtRow2 -match '\[OK' -and $wtRow2 -match 'clean on' -and $wtRow2 -notmatch 'uncommitted')) `
        "Row:`n$wtRow2`nOutput:`n$($b.out)"

    # -------------------------------------------------------------------
    # 27. THE STATUS LINE IS NOT THE ONLY THING THE OPERATOR SEES (#175).
    #
    #     New-StatusLinePlan's blurb is the paragraph an operator reads while
    #     deciding whether to wire the status line up at all, and it said the
    #     status line is "this plugin's only visible indicator: unwired, the
    #     plugin runs and shows nothing". Two other channels are visible on
    #     every session and both go to the operator, not to the model:
    #
    #       lib\session_start.ps1:238   the SessionStart banner, as systemMessage
    #       lib\common.ps1:1996         every turn-end advisory, same channel
    #
    #     So the consequence of declining this section is overstated in the one
    #     place where overstating it changes an answer. The claim is not merely
    #     imprecise: an operator who reads it and says yes on that basis has
    #     been told the plugin is silent without the status line, and it is not.
    #
    #     RULE - NO BARE NEGATIVE. A -notmatch on the old sentence alone would
    #     pass against a blurb that had been deleted outright, which would lose
    #     the true half of what it says. The cases below assert BOTH: the false
    #     sentence is gone, AND the replacement still tells the operator what
    #     the other two channels are. The CONTROL underneath pins the true half
    #     that was always there, so a rewrite cannot quietly drop it.
    #
    #     BASELINE 21b8f49 AND 7f74eb4: the false sentence is present in both,
    #     so these are red at the pre-wave tree and at this batch's branch point.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'blurb-visible-channels' -Bytes $FixtureBytes
    $d = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'diff', '-Section', 'statusline', '-SettingsPath', $t.settings)
    $blurb = ($d.out -split '--- WHAT WOULD CHANGE')[0]

    Add-Result 'diff statusline: the blurb does not call the status line this plugin''s ONLY visible indicator' `
        ([bool]($blurb -notmatch '(?i)only visible indicator')) `
        "lib\session_start.ps1 emits a SessionStart banner and lib\common.ps1 emits every turn-end advisory, both as systemMessage, both on every session. The sentence overstates what declining this section costs, in the paragraph the operator decides on. Blurb:`n$blurb"
    Add-Result 'diff statusline: the blurb names the session-start banner as a channel that survives declining' `
        ([bool]($blurb -match '(?i)session start')) `
        "removing the false sentence is not the whole fix - the operator still has to be told what they DO see without the status line, or the paragraph has been made shorter rather than truer. Blurb:`n$blurb"
    Add-Result 'diff statusline: the blurb names the turn-end advisory as a channel that survives declining' `
        ([bool]($blurb -match '(?i)end of a turn|turn-end|turn end')) `
        "the second of the two other visible channels. Blurb:`n$blurb"
    Add-Result 'CONTROL diff statusline: the blurb still says what this section is FOR - the HH health segment' `
        ([bool]($blurb -match '(?i)HH health segment|HH segment')) `
        "the true half of the paragraph. A rewrite that deletes the overstatement and the reason together leaves the operator with no basis to say yes at all. Blurb:`n$blurb"

    # -------------------------------------------------------------------
    # 28. THE DEAD PERMISSIONS SECTION AND THE TWO DEAD GATE PARAMETERS (#173).
    #
    #     THE FIX IS NOT IN THIS COMMIT. Both halves landed in bda8f71 on
    #     wave1/cuts; these cases are the covering evidence that did not land
    #     with them, and without which #173 does not close under this project's
    #     closure rule. They are RED at 21b8f49 - the commit before bda8f71 -
    #     and that is where the red-first proof for them was taken.
    #
    #     WHAT WAS WRONG. -Section permissions printed a section header, a
    #     blurb and a consent question for a plan builder whose `$rules.Count
    #     -eq 0` return was taken on every possible run: the deny table was
    #     emptied on 30 July 2026 and the section could only ever report
    #     "nothing to add". -DestructiveGate and -SecretGate went on validating
    #     yes/no answers to questions about the two gates removed on the same
    #     day. A consent screen for nothing, and two parameters that accept an
    #     answer and discard it.
    #
    #     WHY THE ASSERTION IS "EXIT 1 AND NOTHING ON STDOUT". A parameter
    #     binding failure is raised by PowerShell before the first line of the
    #     script runs: it goes to stderr, which Invoke-Setup deliberately does
    #     not merge (see its header), and the exit code is 1. Every real run of
    #     this script prints something. So empty stdout is the discriminator
    #     between "refused at the door" and "ran and did something", and the
    #     CONTROL below drives the same invocation with the bad argument taken
    #     out to prove empty stdout is not just this harness failing to capture.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'dead-permissions-section' -Bytes $FixtureBytes

    $p1 = Invoke-Setup -ProfileDir $t.profile -ExpectsStderr -Arguments @('-Step', 'diff', '-Section', 'permissions', '-SettingsPath', $t.settings)
    Add-Result 'diff: -Section permissions is not a value this installer accepts' `
        ([bool]($p1.code -eq 1 -and [string]::IsNullOrWhiteSpace($p1.out))) `
        "the permissions section could only ever report 'nothing to add' - a consent screen for work that cannot exist. It must be rejected at binding, not printed. exit $($p1.code), stdout:`n$($p1.out)"

    $p2 = Invoke-Setup -ProfileDir $t.profile -ExpectsStderr -Arguments @('-Step', 'detect', '-DestructiveGate', 'yes', '-SettingsPath', $t.settings)
    Add-Result 'detect: -DestructiveGate is not a parameter this installer accepts' `
        ([bool]($p2.code -eq 1 -and [string]::IsNullOrWhiteSpace($p2.out))) `
        "the destructive gate was removed on 30 July 2026. A parameter that validates an answer and then selects nothing tells the caller the feature is still there. exit $($p2.code), stdout:`n$($p2.out)"

    $p3 = Invoke-Setup -ProfileDir $t.profile -ExpectsStderr -Arguments @('-Step', 'detect', '-SecretGate', 'no', '-SettingsPath', $t.settings)
    Add-Result 'detect: -SecretGate is not a parameter this installer accepts' `
        ([bool]($p3.code -eq 1 -and [string]::IsNullOrWhiteSpace($p3.out))) `
        "same day, same removal, same reasoning as -DestructiveGate. exit $($p3.code), stdout:`n$($p3.out)"

    $p4 = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'detect', '-SettingsPath', $t.settings)
    Add-Result 'CONTROL: the same run with the dead argument removed DOES print' `
        ([bool](-not [string]::IsNullOrWhiteSpace($p4.out))) `
        "without this, the three cases above are satisfied by a harness that captures no stdout at all, whatever the script does. exit $($p4.code), stdout length $($p4.out.Length)"

    # ===================================================================
    # 30. CLAUDE_CONFIG_DIR (#146).
    #
    #     Claude Code honours CLAUDE_CONFIG_DIR to relocate its configuration
    #     directory away from ~\.claude. Until 3 September 2026 NOTHING in this
    #     repository read it: every path was composed from $env:USERPROFILE and
    #     a literal `.claude`. The installer therefore wrote statusLine and hooks
    #     into a settings.json the CLI does not load, AND REPORTED SUCCESS -
    #     which is worse than failing, because an install that fails can be
    #     fixed and one that is attested cannot.
    #
    #     THE FIXTURE PUTS THE TWO TREES IN DIFFERENT PLACES ON PURPOSE. A
    #     config dir nested inside the profile would be satisfied by code that
    #     still resolves through the profile. <case>\cfg and <case>\profile are
    #     siblings, so "landed in the right one" and "landed in the wrong one"
    #     are different directories and no assertion can be true of both.
    #
    #     RED AT ec80e88, measured, all three writing cases: the settings file
    #     appeared at <case>\profile\.claude\settings.json and <case>\cfg stayed
    #     empty.
    # ===================================================================

    # -------------------------------------------------------------------
    # 30a. THE WRITE LANDS IN CLAUDE_CONFIG_DIR, AND NOT IN THE PROFILE.
    #
    #      No -SettingsPath, so the default path is what is under test - which is
    #      the path a real /lw-watchtower:setup run uses, and the one #146 is
    #      about. -Section statusline also copies the status line to
    #      <configuration root>\statusline.ps1, so the case asserts on both the
    #      file the installer WRITES and the file it COPIES.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'cfgdir-honoured' -Bytes $null
    $cfgA = Join-Path $t.dir 'cfg'
    [void][IO.Directory]::CreateDirectory($cfgA)
    $profClaude = Join-Path $t.profile '.claude'

    $r = Invoke-Setup -ProfileDir $t.profile -ConfigDir $cfgA -Arguments @('-Step', 'apply', '-Section', 'statusline', '-BaseHash', 'none')
    $landedCfg  = [IO.File]::Exists((Join-Path $cfgA 'settings.json'))
    $landedProf = [IO.File]::Exists((Join-Path $profClaude 'settings.json'))
    Add-Result 'CLAUDE_CONFIG_DIR: apply writes settings.json into the configuration directory' `
        ([bool]($r.code -eq 0 -and $landedCfg)) `
        "exit $($r.code); <cfg>\settings.json exists=$landedCfg. The installer wrote its statusLine into a settings.json the CLI does not read and reported success. Output:`n$($r.out)"
    Add-Result 'CLAUDE_CONFIG_DIR: and NOT into the user profile' `
        ([bool](-not $landedProf)) `
        "a settings.json appeared at $profClaude - the directory the CLI is NOT reading on a machine that sets CLAUDE_CONFIG_DIR. Both files existing is the same defect as only the wrong one existing: the operator now has two."
    Add-Result 'CLAUDE_CONFIG_DIR: the status-line copy goes there too' `
        ([bool]([IO.File]::Exists((Join-Path $cfgA 'statusline.ps1')) -and -not [IO.File]::Exists((Join-Path $profClaude 'statusline.ps1')))) `
        "cfg copy=$([IO.File]::Exists((Join-Path $cfgA 'statusline.ps1'))), profile copy=$([IO.File]::Exists((Join-Path $profClaude 'statusline.ps1'))). A settings.json in one tree pointing at a statusline.ps1 in another is an install that renders nothing."

    # -------------------------------------------------------------------
    # 30b. THE ROOT IS NAMED, WITH ITS SOURCE, ON EVERY detect RUN.
    #
    #      #146 item 3, applied to the installer for the same reason it asks for
    #      it of the doctor: a command that attests an install without naming
    #      the directory it attested cannot be argued with by the one person who
    #      can tell it is wrong.
    # -------------------------------------------------------------------
    $rd = Invoke-Setup -ProfileDir $t.profile -ConfigDir $cfgA -Arguments @('-Step', 'detect')
    Add-Result 'CLAUDE_CONFIG_DIR: detect names the resolved root and says it came from the variable' `
        ([bool]($rd.out -match [regex]::Escape($cfgA) -and $rd.out -match 'from CLAUDE_CONFIG_DIR')) `
        "the detect report must print the configuration directory it resolved AND how. Looked for '$cfgA' and 'from CLAUDE_CONFIG_DIR'. Output:`n$($rd.out)"

    # -------------------------------------------------------------------
    # 30c. AN EXPLICIT PARAMETER BEATS THE VARIABLE.
    #
    #      First rule of the precedence in lib\common.ps1, and the reason it is
    #      first: -SettingsPath is the test seam every case in this file drives,
    #      and a caller that names a path outright has said something no
    #      environment variable may overrule. If this case ever goes red, every
    #      other case in this file is running somewhere it was not told to.
    # -------------------------------------------------------------------
    $t2 = New-CaseTree -Tag 'cfgdir-param-wins' -Bytes $FixtureBytes
    $cfgB = Join-Path $t2.dir 'cfg'
    [void][IO.Directory]::CreateDirectory($cfgB)
    $d2 = Invoke-Setup -ProfileDir $t2.profile -ConfigDir $cfgB -Arguments @('-Step', 'diff', '-Section', 'statusline', '-SettingsPath', $t2.settings)
    $bh = Get-BaseHashFrom $d2.out
    $a2 = Invoke-Setup -ProfileDir $t2.profile -ConfigDir $cfgB -Arguments @('-Step', 'apply', '-Section', 'statusline', '-SettingsPath', $t2.settings, '-BaseHash', $bh)
    $o2 = Read-Json $t2.settings
    Add-Result 'CLAUDE_CONFIG_DIR: -SettingsPath beats it, and the write goes where the parameter said' `
        ([bool]($a2.code -eq 0 -and $null -ne $o2 -and $null -ne $o2.PSObject.Properties['statusLine'])) `
        "apply exited $($a2.code) against $($t2.settings). Output:`n$($a2.out)"
    Add-Result 'CLAUDE_CONFIG_DIR: nothing was written into the configuration directory it overruled' `
        ([bool](-not [IO.File]::Exists((Join-Path $cfgB 'settings.json')))) `
        "a settings.json appeared at $cfgB even though -SettingsPath named a different file. An explicit parameter that can be overruled by the environment is not a seam, and every case in this file depends on it being one."

    # -------------------------------------------------------------------
    # 30d. THE CONTROL: WITH THE VARIABLE UNSET, THE PROFILE DEFAULT STANDS.
    #
    #      #146 asks for this in as many words, and it is the case that would
    #      catch the fix over-reaching. It passes at ec80e88 too - that is the
    #      point of it: it is the invariant the change had to preserve, not
    #      evidence of the change.
    # -------------------------------------------------------------------
    $t3 = New-CaseTree -Tag 'cfgdir-unset-control' -Bytes $null
    $r3 = Invoke-Setup -ProfileDir $t3.profile -Arguments @('-Step', 'apply', '-Section', 'statusline', '-BaseHash', 'none')
    Add-Result 'CONTROL: with CLAUDE_CONFIG_DIR unset the default is still <profile>\.claude\settings.json' `
        ([bool]($r3.code -eq 0 -and [IO.File]::Exists((Join-Path (Join-Path $t3.profile '.claude') 'settings.json')))) `
        "exit $($r3.code). The historical default must not regress: a fix that honours the variable and loses the default breaks every machine that does not set it. Output:`n$($r3.out)"
    $rd3 = Invoke-Setup -ProfileDir $t3.profile -Arguments @('-Step', 'detect')
    Add-Result 'CONTROL: and detect says so, rather than saying nothing' `
        ([bool]($rd3.out -match 'CLAUDE_CONFIG_DIR is not set')) `
        "the report must distinguish 'resolved from the profile' from 'resolved from the variable' on the machine where the variable is unset too. Output:`n$($rd3.out)"

    # -------------------------------------------------------------------
    # 30e. THE STATUS LINE READS ITS STATE UNDER CLAUDE_CONFIG_DIR.
    #
    #      statusline\statusline.ps1 dot-sources nothing by design - it is a
    #      settings.json command that runs on every assistant message - so it
    #      carries its own copy of the resolver, cross-referenced in comment to
    #      lib\common.ps1's. A copy is a thing that can drift, which is what this
    #      case is for: the two must agree about where the data root is.
    #
    #      Asserted through the HH glyph rather than through a path, because the
    #      glyph is what an operator sees. A health log holding one fault for
    #      this session renders red HH1; read from the wrong root it renders
    #      green HH off an empty directory, which is the false green the whole
    #      indicator exists to prevent.
    # -------------------------------------------------------------------
    $t4 = New-CaseTree -Tag 'cfgdir-statusline' -Bytes $null
    $cfgC = Join-Path $t4.dir 'cfg'
    $sl4  = Join-Path (Join-Path $t4.profile '.claude') 'statusline.ps1'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $sl4))
    [IO.File]::WriteAllBytes($sl4, $repoStatusLineBytes)
    # The plugin marker the presence probes need, under the RELOCATED root.
    $inst4 = Join-Path $cfgC ("skills\" + $PluginName)
    [void][IO.Directory]::CreateDirectory((Join-Path $inst4 'lib'))
    [void][IO.Directory]::CreateDirectory((Join-Path $inst4 'agents'))
    [IO.File]::WriteAllText((Join-Path $inst4 'lib\supervisor.ps1'), '# fixture')
    [IO.File]::WriteAllText((Join-Path $inst4 'agents\lw-healer.md'), '# fixture')
    $sid4 = 'lwg-cfgdir-session'
    $dd4  = Join-Path $cfgC ("plugins\data\" + $PluginName + '-skills-dir')
    [void][IO.Directory]::CreateDirectory($dd4)
    # The record shape HealthSeg actually counts: the session key is `session`
    # (the PAYLOAD's is session_id, and they are not the same field), and one
    # fault is a StopFailure. A record that parses but matches no arm renders
    # HH-, which is 'nothing was attributed to this session' - a different
    # answer from both HH and HH1, and one this case must not be satisfied by.
    [IO.File]::WriteAllText((Join-Path $dd4 'health.jsonl'),
        ('{"session":"' + $sid4 + '","ts":"2026-09-03T10:00:00.0000000Z","event":"StopFailure","error":"lwg-fixture"}' + "`n"))
    $pay4 = '{"session_id":"' + $sid4 + '","cwd":"' + (($t4.dir -replace '\\', '/')) + '","model":{"display_name":"lwg-fixture-model"}}'
    $s4 = Invoke-StatusLine -ProfileDir $t4.profile -ScriptPath $sl4 -PayloadJson $pay4 -ConfigDir $cfgC
    Add-Result 'CLAUDE_CONFIG_DIR: the status line finds the install and the log under the relocated root' `
        ([bool]($s4.out -match 'HH1')) `
        "expected the HH segment to read the fault log under $dd4 and render HH1. Rendering HH? means the install under the relocated root was never found; rendering plain HH means the log was. Output:`n$($s4.out)"

    # ===================================================================
    # 31. THE FIVE MERGE-WRITER PROPERTIES, ON THE HOOKS SECTION (#142).
    #
    #     WHY THIS SECTION EXISTS AT ALL, given sections 17 to 19c. Those cases
    #     drive -Section hooks and assert what the section DECIDES: install-mode
    #     detection, hook identity, duplicate registration, and what the consent
    #     screen discloses. None of them is a writer property. Everything this
    #     file establishes about the MERGE - unrelated keys preserved by value
    #     and order, exactly one backup holding the original bytes, a stale
    #     -BaseHash refused, a byte-identical second apply, rollback byte for
    #     byte - was established for -Section statusline and for nothing else,
    #     and the tree said so in its own words: the writer properties are
    #     "merely INHERITED by hooks, which goes through the same Save-Settings
    #     path".
    #
    #     INHERITED IS AN ARGUMENT FROM SHARED CODE, NOT A MEASUREMENT, and the
    #     two sections do not in fact share the whole path. New-HooksPlan builds
    #     its merged object through Get-PropArray and Get-HookSignature, reads
    #     and rewrites an EXISTING nested object rather than a single scalar
    #     key, and calls Set-PropValue twice - once per event, once for `hooks`
    #     itself. Only what is below Save-Settings is common. The five
    #     properties are about the operator's real settings.json either way, and
    #     the section that writes the largest structure into it is the one that
    #     had none of them.
    #
    #     BASELINE: 4342980, and these cases are GREEN there. They are COVERAGE
    #     and they are recorded as coverage: the installer already behaves
    #     correctly on all five, and nothing here is offered as evidence that a
    #     defect was fixed. Each one was confirmed FALSIFIABLE against a
    #     deliberately broken bin\lwg-setup.ps1 rather than assumed to be, which
    #     is what docs\testing.md requires of a case with no red commit behind
    #     it - the mutations, and which case each one turns red, are recorded on
    #     the pull request that brought this section in.
    #
    #     -HookMode standalone ON EVERY CALL. Under `auto` the mode depends on
    #     what the scratch profile happens to look like, and a plan that
    #     resolved to `plugin` writes nothing at all - every case below would
    #     then pass vacuously, on a run that did not reach the writer. The diff
    #     is also checked for a planned registration before the apply, for the
    #     same reason and in the same shape section 3b uses.
    # ===================================================================
    $t = New-CaseTree -Tag 'hooks-writer' -Bytes $HooksFixtureBytes
    $before = Read-Json $t.settings

    $d = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'diff', '-Section', 'hooks', '-SettingsPath', $t.settings, '-HookMode', 'standalone')
    $h = Get-BaseHashFrom $d.out
    if ($h -eq '' -or $h -eq 'none') { throw "the hooks-writer fixture's diff printed no usable BASEHASH ('$h'), so no case in section 31 could establish anything" }
    if ($d.out -notmatch '(?m)^\d+ registration\(s\) would be ADDED') {
        throw 'the hooks-writer fixture planned no registration, so the apply below would write nothing and every writer property in section 31 would pass vacuously'
    }

    $a = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'apply', '-Section', 'hooks', '-SettingsPath', $t.settings, '-BaseHash', $h, '-HookMode', 'standalone')
    Add-Result 'hooks writer: apply on a populated fixture -> exit 0' ($a.code -eq 0) `
        "exited $($a.code), expected 0. Output:`n$($a.out)"

    $after = Read-Json $t.settings

    # 31a. ORDER (#142 row 1). `hooks` is SECOND of five and is the key being
    #      replaced, so this is the replace-in-place claim rather than the
    #      append one - see fixture B's comment.
    $order = Get-TopLevelOrder $after
    Add-Result 'hooks writer: top-level ORDER is unchanged, with the replaced hooks key still second' `
        ((($order -join ',') -eq ($HooksExpectedOrder -join ','))) `
        "order after a hooks apply is '$($order -join ', ')', expected '$($HooksExpectedOrder -join ', ')' - the key that was replaced in place has been moved to the end of the operator's file"

    # 31b. VALUES (#142 row 1). The same compressed-JSON comparison
    #      Compare-UnrelatedKeys makes. statusLine is in this list deliberately:
    #      it is the key the OTHER section writes, and a hooks apply must not
    #      touch it.
    foreach ($k in @('zeta', 'permissions', 'statusLine', 'alpha')) {
        $b4 = Get-KeyJson $before $k
        $af = Get-KeyJson $after  $k
        Add-Result "hooks writer: unrelated key '$k' is value-identical after a hooks apply" ($b4 -eq $af) `
            "before: $b4`n        after : $af"
    }

    # 31c. AND THE MERGE INSIDE THE TOUCHED KEY. The four keys above are what
    #      Compare-UnrelatedKeys guards. Nothing guards the operator's own
    #      registrations INSIDE hooks, which is where a section that rebuilds a
    #      nested object can lose them - and losing one is silent, because a
    #      hook that is not registered simply never fires.
    #
    #      COMPARED BY VALUE AND NOT THROUGH Get-HookGroupsFor, which is the
    #      helper the sections above use and is wrong for this. Its `.ps1`
    #      regex is bounded by quotes and slashes, so it reads a leaf out of the
    #      EXEC form this plugin registers in - command plus an args array, each
    #      element its own JSON string - and takes the whole of a shell-form
    #      `"command": "powershell -NoProfile -File x.ps1"` as one token. Both
    #      spellings are legal in settings.json and an operator's own entry is
    #      as likely to be the second. Measured: the first spelling of this case
    #      went red against a merge that had in fact carried the entry through
    #      perfectly, which is a case failing for a reason not in the code under
    #      test. The compressed-JSON comparison is also the stronger claim -
    #      "present" would be satisfied by an entry the merge had rewritten.
    $beforeUps = Get-KeyJson $before.hooks 'UserPromptSubmit'
    $afterUps  = Get-KeyJson $after.hooks  'UserPromptSubmit'
    Add-Result 'hooks writer: the operator''s own UserPromptSubmit registration comes through value-identical' `
        ($beforeUps -ne '(absent)' -and $beforeUps -eq $afterUps) `
        ("before: $beforeUps`n        after : $afterUps`n" +
         "        This plugin registers on UserPromptSubmit zero times, so the entry is the operator's and the merge must carry it through untouched. A hook that is not registered simply never fires, so losing one is silent.")

    # 31d. NO INJECTED NULL - RELOCATED HERE FROM SECTION 16 (#137 instance 4).
    #
    #      THE CASE IS UNCHANGED; ITS FIXTURE IS THE POINT. It asserts that no
    #      bare `null` was written as an array member, which is the shape
    #      Get-PropArray's `, @()` exists to prevent: `@($v)` on an ABSENT
    #      property is `@($null)`, a one-element array holding $null, and the
    #      null then goes back into the file as a member of the array. Every
    #      hooks event array grew a leading null that way.
    #
    #      IT SAT IN SECTION 16, ON THE STATUSLINE PATH, WHERE Get-PropArray IS
    #      NEVER CALLED. That was not an inference: the case beside it there was
    #      measured red against a reduced serialiser depth and GREEN against the
    #      Get-PropArray break, so on that fixture nothing could produce the
    #      null this line looks for. It was a row on a published tally for a
    #      check with nothing to match under any build.
    #
    #      HERE IT CAN FAIL. New-HooksPlan calls Get-PropArray once per event in
    #      hooks.json, and fixture B declares NONE of those events - it carries
    #      UserPromptSubmit only - so every one of those calls is the absent-
    #      property case the defence is for. Relocated rather than deleted: the
    #      assertion is a good one where the defence it names actually runs, and
    #      deleting it would move a case count quoted in tracked pages.
    $afterText = ''
    try { $afterText = [IO.File]::ReadAllText($t.settings, [Text.Encoding]::UTF8) } catch { }
    Add-Result 'the written file contains no injected null' `
        ($afterText -ne '' -and $afterText -notmatch '(?m)^\s*null\s*,?\s*$') `
        "a bare null appears as an array member in the written file - Get-PropArray returned @(`$null) for an event the operator's settings.json does not declare, and it was written back into the hooks array:`n$afterText"

    # 31e. EXACTLY ONE BACKUP, HOLDING THE ORIGINAL BYTES (#142 row 2). The
    #      hooks path had one Get-SettingsBackups assertion before this, and it
    #      asserted a count of ZERO on the marketplace write-nothing case.
    #
    #      NOT GUARDED ON THE COUNT CASE, for the reason section 5 gives at
    #      length (#136 instance 3): a case a defect can delete reports coverage
    #      it is not providing.
    $baks = Get-SettingsBackups $t.dir
    Add-Result 'hooks writer: exactly one settings backup after one hooks apply' ($baks.Count -eq 1) `
        "found $($baks.Count): $($baks -join ', ')"
    $hooksBakBytes = $null
    if ($baks.Count -ge 1) { try { $hooksBakBytes = [IO.File]::ReadAllBytes($baks[0]) } catch { } }
    Add-Result 'hooks writer: the backup holds the original bytes exactly' `
        ($baks.Count -eq 1 -and (Test-BytesEqual $hooksBakBytes $HooksFixtureBytes)) `
        $(if ($baks.Count -ne 1) {
            "there is no single backup to read: found $($baks.Count) ($($baks -join ', '))"
          } else {
            'the backup is not a byte copy of the file the hooks apply replaced, so restoring it does not restore the original'
          })

    # 31f. IDEMPOTENCE (#142 row 4). BYTE identity, on a plan that really did
    #      write - which is what separates this from section 19's second run,
    #      where the installer had DECLINED to change anything and the second
    #      run therefore proved nothing about a write it never made.
    $bytesAfterApply = [IO.File]::ReadAllBytes($t.settings)
    $d2 = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'diff', '-Section', 'hooks', '-SettingsPath', $t.settings, '-HookMode', 'standalone')
    $h2 = Get-BaseHashFrom $d2.out
    $a2 = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'apply', '-Section', 'hooks', '-SettingsPath', $t.settings, '-BaseHash', $h2, '-HookMode', 'standalone')
    Add-Result 'hooks writer: a second apply -> exit 0 and says it is already in the state requested' `
        ($a2.code -eq 0 -and $a2.out -match 'Already in the state requested') `
        "exited $($a2.code). Output:`n$($a2.out)"
    Add-Result 'hooks writer: a second apply takes no second backup' ((Get-SettingsBackups $t.dir).Count -eq 1) `
        "there are now $((Get-SettingsBackups $t.dir).Count) backups; a run that wrote nothing took one"
    Add-Result 'hooks writer: a second apply leaves the file BYTE-identical' `
        (Test-BytesEqual ([IO.File]::ReadAllBytes($t.settings)) $bytesAfterApply) `
        'the file changed on a hooks run that reported no change - re-running setup is the commonest thing an operator does with it'

    # 31g. ROLLBACK, BYTE FOR BYTE (#142 row 5). -Step rollback takes no
    #      -Section: it restores the last backup this installer took, whichever
    #      section took it, and until now the only section it had ever been
    #      asked to undo was statusline.
    $r = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'rollback', '-SettingsPath', $t.settings)
    Add-Result 'hooks writer: rollback of a hooks apply -> exit 0' ($r.code -eq 0) "exited $($r.code). Output:`n$($r.out)"
    Add-Result 'hooks writer: rollback restores the original bytes exactly' `
        (Test-BytesEqual ([IO.File]::ReadAllBytes($t.settings)) $HooksFixtureBytes) `
        'the restored file is not byte-identical to the fixture the hooks apply replaced, and rollback is what the apply output tells the operator they can rely on'
    Add-Result 'hooks writer: rollback keeps a pre-rollback copy of what it overwrote' `
        ((Get-PreRollbackBackups $t.dir).Count -eq 1) `
        "found $((Get-PreRollbackBackups $t.dir).Count) pre-rollback copies, expected 1 - a rollback the operator did not mean is otherwise unrecoverable"

    # -------------------------------------------------------------------
    # 31h. A STALE -BaseHash ON THE HOOKS PLAN (#142 row 3).
    #
    #      Its own tree, because it must run against a file no apply has
    #      touched. Both stale-hash cases in this suite drove -Section
    #      statusline; exit 4 and CONCURRENT MODIFICATION had never been
    #      asserted on a hooks plan, which is the section that writes the larger
    #      structure and therefore the one where merging onto a file the
    #      operator never saw discards the most.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'hooks-stale' -Bytes $HooksFixtureBytes
    $d = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'diff', '-Section', 'hooks', '-SettingsPath', $t.settings, '-HookMode', 'standalone')
    $stale = Get-BaseHashFrom $d.out
    if ($d.out -notmatch '(?m)^\d+ registration\(s\) would be ADDED') {
        throw 'the hooks-stale fixture planned no registration, so the apply below could short-circuit before the hash check and the refusal cases would pass vacuously'
    }

    $hooksMutatedBytes = $Utf8NoBom.GetBytes(($HooksFixtureText -replace '"alpha": "keep me"', '"alpha": "somebody else wrote this"'))
    [IO.File]::WriteAllBytes($t.settings, $hooksMutatedBytes)

    $a = Invoke-Setup -ProfileDir $t.profile -Arguments @('-Step', 'apply', '-Section', 'hooks', '-SettingsPath', $t.settings, '-BaseHash', $stale, '-HookMode', 'standalone')
    Add-Result 'hooks writer: a stale -BaseHash on the hooks plan -> exit 4 and CONCURRENT MODIFICATION' `
        ($stale -ne '' -and $stale -ne 'none' -and $a.code -eq 4 -and $a.out -match 'CONCURRENT MODIFICATION') `
        "diff hash was '$stale'; apply exited $($a.code), expected 4 naming CONCURRENT MODIFICATION. Output:`n$($a.out)"
    Add-Result 'hooks writer: a stale -BaseHash leaves the file as the OTHER writer left it' `
        (Test-BytesEqual ([IO.File]::ReadAllBytes($t.settings)) $hooksMutatedBytes) `
        'the concurrent write was overwritten by the hooks merge - which is the data loss the hash check exists to prevent'
    Add-Result 'hooks writer: a stale -BaseHash takes no backup' `
        ((Get-SettingsBackups $t.dir).Count -eq 0) `
        "found $((Get-SettingsBackups $t.dir).Count) .bak on a hooks run that wrote nothing; a backup is a write, and one taken here leaves an artefact the operator has no reason to expect"

    # -------------------------------------------------------------------
    # 29. THIS SUITE MUST NOT LEAVE ANYTHING IN THE WORKING DIRECTORY (#214).
    #
    #     LAST, deliberately: it is a claim about everything above it, so it can
    #     only be made once everything above it has run. Every child process this
    #     file starts has already started by now.
    #
    #     THE DEFECT. Every launcher here swapped USERPROFILE and left APPDATA
    #     and LOCALAPPDATA pointing at the runner's real ones. The child
    #     powershell.exe then could not resolve its LocalApplicationData folder
    #     and wrote Microsoft\Windows\PowerShell\ModuleAnalysisCache RELATIVE TO
    #     ITS CURRENT DIRECTORY, which it inherits from this process - the
    #     repository, for the way CI and every maintainer runs this file.
    #
    #     WHY IT IS NOT UNTIDINESS. bin\lwg-update.ps1 counts any non-`#`
    #     porcelain-v2 line as an uncommitted change, and `? Microsoft/` is one.
    #     Measured at ec80e88 immediately after a full run of this suite:
    #
    #       git status --porcelain          ->  ?? Microsoft/
    #       bin\lwg-update.ps1 -Offline -SkipDoctor
    #         [FAIL] worktree  1 uncommitted change(s) on batch/b2-bin. This
    #                          command does not stash, reset or check out
    #                          anything - commit or set them aside first.
    #
    #     Running the plugin's test suite disabled the plugin's update command,
    #     and told the maintainer it was their own uncommitted work.
    #
    #     WHY THE OUTCOME AND NOT THE MECHANISM. Asserting "the launchers set
    #     LOCALAPPDATA" would pass for a fifth launcher that forgot to. Asserting
    #     the working directory is as clean as it was found covers any launcher,
    #     present or future, and any other stray relative write besides this one.
    #
    #     The second case is the anti-vacuum guard: the cache has to have landed
    #     SOMEWHERE, and if it landed in the scratch tree then the redirect is
    #     what moved it, rather than the children having quietly stopped running.
    # -------------------------------------------------------------------
    $appeared = @()
    foreach ($w in $script:CacheWatch) {
        if ($w.existed) { continue }
        if ([IO.Directory]::Exists($w.probe)) { $appeared += $w.probe }
    }
    Add-Result 'this suite leaves no Microsoft\ ModuleAnalysisCache in the working directory (#214)' `
        ($appeared.Count -eq 0) `
        ("a child powershell.exe wrote its module cache relative to the current directory, which means APPDATA/LOCALAPPDATA were not moved with USERPROFILE. Appeared at: $($appeared -join ', '). Watched: " +
         (($script:CacheWatch | ForEach-Object { "$($_.dir) (pre-existing Microsoft\: $($_.existed))" }) -join '; '))

    $cacheInScratch = @()
    try {
        $cacheInScratch = @([IO.Directory]::GetDirectories($script:Work, 'PowerShell', [IO.SearchOption]::AllDirectories) |
                            Where-Object { $_ -like '*\AppData\Local\Microsoft\Windows\PowerShell' })
    } catch { }
    Add-Result 'ANTI-VACUUM: the module cache did land, and it landed in the scratch tree' `
        ($cacheInScratch.Count -gt 0) `
        ("nothing under $($script:Work) holds AppData\Local\Microsoft\Windows\PowerShell, so the case above may be green because no child wrote a cache at all rather than because the redirect worked. If powershell.exe stops writing this cache on a future build, DELETE THIS CASE and say so - do not weaken the one above it.")

} catch {
    $script:Aborted = "$($_.Exception.Message)  [line $($_.InvocationInfo.ScriptLineNumber)]"
} finally {
    # Best effort, and deliberately narrow: one directory this script created
    # under the temp root, by a name it generated. Never recursive over anything
    # it was given.
    if ($script:Work -and [IO.Directory]::Exists($script:Work)) {
        try { [IO.Directory]::Delete($script:Work, $true) } catch { }
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
Write-Output 'Every case above passed. Read that as "the merge still behaves on the'
Write-Output 'statusline section, the hooks section still recognises an install it did not'
Write-Output 'write, and the status line still resolves a marketplace root, decodes its'
Write-Output 'payload as UTF-8, tells an unusable number from a missing one, counts the'
Write-Output 'fault gauge once and keeps its clock legible off en-US" - not as "the'
Write-Output 'installer is safe" and not as "the status line is covered": row 1 has nine'
Write-Output 'segments and section 23 asserts on four of them. The backup-collision suffix,'
Write-Output 'the post-write auto-restore,'
Write-Output 'the ATOMICITY of the write, everything to do with permissions.deny and the'
Write-Output 'enabled/disabled'
Write-Output 'distinction are all named in the header as NOT covered, and no case here proves'
Write-Output 'what layout the CLI you are running actually writes.'
Write-Output 'EXIT: 0'
exit 0
