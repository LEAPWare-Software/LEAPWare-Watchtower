#requires -version 5
<#
  LW-WATCHTOWER doctor behaviour regression suite.

      powershell -NoProfile -ExecutionPolicy Bypass -File tests\doctor_behaviour.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File tests\doctor_behaviour.ps1 -Verbose

  WHAT THIS IS

  bin\lwg-doctor.ps1 is the one component whose whole job is to notice a switch
  wired to nothing. Nothing in tests\ had ever RUN it against a seeded config or
  a seeded settings.json - tests\doc_claims.ps1 runs it once, on the real tree,
  and reads only the "- N checks" line out of its header. So two checks inside
  it had never been driven at all, and both were wrong in the same direction:
  they answered a question that is cheaper than the one they claim to answer.

  This file drives SIX of the doctor's ten checks and no others:

    config-registry  #41. It tested a declared switch for PRESENCE and stopped,
                     so `"delegate": "true"` - quoted - passed while
                     Test-LwgFlag, which requires a real [bool], ignored the
                     string and left the only gate this plugin ships on its
                     built-in default of $false. The `modules` block had the
                     same hole with the opposite polarity: the check read
                     .PSObject.Properties.Name, never a value, and an ignored
                     `modules` value leaves the module ON.
    statusline       #55. It took the first token ending in .ps1 out of
                     statusLine.command and hash-compared it against this repo's
                     statusline\statusline.ps1 with no test of whose file it is.
                     A third party's status line was therefore diagnosed as a
                     stale copy of this plugin's, with the printed remedy being
                     to overwrite it. The inverse was quieter and also wrong: an
                     identical file attested an install that never happened.
                     #146 is the same row's other half and is about WHICH FILE
                     it opens: the settings path was composed from
                     $env:USERPROFILE and a literal `.claude` - the last live
                     composition of that shape in the tree - so on a machine
                     that sets CLAUDE_CONFIG_DIR the row health-checked a
                     settings.json the CLI does not read and reported green
                     about it. One case drives the relocated directory and every
                     statusline case above it holds the profile branch that must
                     not be lost to it. The number of those is not written here:
                     it is a count, it would go stale, and "every one of them" is
                     what the claim actually needs.
    sessionstart     #42. It read at most the last 256 KB of the event log and,
                     finding no SessionStart record in that window, reported
                     "the hook is not firing" and failed the run - a definite
                     fault claim, with the remedy of reinstalling the plugin,
                     produced by a read that never established absence. A log
                     that grew past 256 KB since the session started is enough.
    commands         #204. It enumerated the FILESYSTEM under the plugin root
                     with two name filters and scanned everything else, tracked
                     or not, so an untracked directory of generated output made
                     it report the plugin NOT healthy from a checkout whose
                     tracked tree was clean. The enumeration is now the tracked
                     tree when git can answer for the directory, the walk when
                     it cannot - and the row names which one it used, because a
                     scan that read nothing must never be readable as a clean
                     one.
    platform         #132. Nothing in this plugin read the operating system.
                     hooks\hooks.json invokes `powershell` by that name in every
                     registration and every path composed anywhere is
                     NTFS-shaped, so a non-Windows machine is a SILENT
                     non-install. Only the PASS branch is reachable from a
                     Windows runner, and the case says so.
    claude-version   #132. Three of the registered events were read out of one
                     specific binary; on a build without them the registrations
                     are inert, and an inert hook is silent while the banner
                     goes on counting the modules that need them as active. All
                     three states are driven - unread, below, at or above -
                     because an unread build must not render as one that was
                     read and matched. Since #218 that distinction lives in the
                     row's DETAIL and not in its status: unread is a PASS whose
                     text says it was not read, and only a build that WAS read
                     and disagrees warns. Cases 27 and 28 assert the exit code
                     on both sides of that line, because it is the exit code
                     that #218 was about.

  It does NOT drive the other four checks. Case 25 establishes that they RAN and
  nothing else, and a green run here says nothing about what any of them
  answered.

  IT ALSO DRIVES ONE THING THAT IS NOT A CHECK AT ALL: the informational roster
  at the foot of the report - the per-gate paragraphs and the module table that
  used to be bin\lwg-status.ps1, a report command now deleted. Cases 16-18 are
  about the BOUNDARY that move has to keep rather than about the content: the
  roster must print, it must print below the RESULT: line, it must add no row
  the header counts, and the exit code must stay the one the tally implies. A
  report merged into a diagnosis is one edit away from becoming part of the
  diagnosis, and every gate here ships OFF, so a leak would fail a correct
  default install.

  AND IT PINS WHICH CHECKS EXIST AT ALL. Case 25 asserts the SET of check ids
  the doctor printed against the literal list at $script:ExpectedCheckIds, for
  the reason written above that list: until it existed, a doctor with a whole
  Invoke-Check block deleted reported 19 of 19 and exit 0 here. It is the only
  thing in this file that says anything about the other four checks, and what it
  says is that they RAN - never what they answered.

  ---------------------------------------------------------------------------
  HOW A CASE IS RUN, AND WHY IT CANNOT REACH THE OPERATOR'S OWN STATE
  ---------------------------------------------------------------------------
  The whole plugin tree is COPIED once into a scratch directory, minus .git and
  .claude, and every case runs the copy's own bin\lwg-doctor.ps1 in a real child
  process. The doctor derives its plugin root from its own $PSScriptRoot, so the
  copy is what it reads: the copy's config.json is the config under test, and
  the copy's statusline\statusline.ps1 is the repo copy every hash is compared
  against. Nothing is written back to the checkout.

  Three environment variables are the rest of the sandbox, set on the child and
  restored in a finally:

      USERPROFILE                   points at a per-case scratch profile, which
                                    is where check 7 looks for settings.json
      CLAUDE_PLUGIN_DATA            points at a per-case scratch state dir, so
                                    check 5's write probe and any event this run
                                    logs land there and nowhere else
      CLAUDE_PLUGIN_ROOT            cleared, or it would redirect the doctor out
      CLAUDE_CODE_PLUGIN_CACHE_DIR  of the scratch tree entirely

  NO TEST SEAM WAS ADDED TO bin\lwg-doctor.ps1 for this. That is deliberate:
  the doctor as shipped is what runs here, and the same suite therefore runs
  unmodified against fd8d023, which is what makes the red proofs below mean
  anything.

  THE ZERO-BYTES PROPERTY IS ASSERTED, NOT ASSUMED. The last case measures every
  <plugin>*\*.jsonl under the operator's REAL ~\.claude\plugins\data before the
  first child process and again after the last, and fails if any length changed
  or any file appeared. Two cases in other suites make the same claim about the
  live event log; this one makes it about this suite.

  ---------------------------------------------------------------------------
  BASELINES - each case states its own, and they are not all the same
  ---------------------------------------------------------------------------
  fd8d023 is the baseline for every case here. All three defects predate the
  current wave and the three checks are byte-identical between fd8d023 and
  19bb85d apart from the lw-gmhh -> lw-watchtower rename, so the red proof was
  taken by restoring bin\, lib\ and statusline\ to fd8d023 with this file left
  in place. The two #42 cases added afterwards were proved red against the tree
  they landed in, which carries that check unchanged from fd8d023.

  THE THREE FIGURES BELOW ARE A RECORD OF THE DAY THE BASELINE WAS TAKEN, NOT A
  COUNT OF WHAT THIS FILE RUNS NOW. This file held THIRTY cases when the fd8d023
  proof was taken, and every sub-count in this section is over those thirty.
  They are left as they were: the arithmetic of a red-first proof at fd8d023, a
  tree NO CLONE OF THIS REPOSITORY REACHES - it is not an ancestor of anything
  here - so re-deriving them is not available, and moving the total alone would
  leave three figures in one section contradicting each
  other (#240 item 3). The SHA sits on the line that names the proof, and that
  is deliberate: .github\scripts\redfirst_annotations.ps1 groups consecutive
  hash-comment lines into a block, and inside a block-comment header like this
  one every line is its own block - so a baseline claim whose commit sits on the
  NEXT line reads to that guard as a claim naming no commit at all.

  IT HAS GROWN SINCE, AND THIS HEADER DELIBERATELY DOES NOT SAY BY HOW MUCH. The
  live total is the `RESULT: N of N case(s) passed` line this file prints, which
  is also where tests\doc_claims.ps1 reads it from; a second copy here is a
  number nobody maintains, and the one that used to be here went stale twice
  before anything noticed. Same treatment as tests\config_behaviour.ps1's
  header, for the same reason, decided on the same issue.

  ELEVEN OF THE THIRTY CASES WERE LABELLED CONTROL, in the name and in the
  comment. None is offered as evidence that anything was fixed. They exist
  because the cheapest way to pass the others is to answer "not ours" to
  everything, "FAIL" to every config, "PASS" to every log, to read no file at
  all and to WARN at every build, and the controls are what make that not work.
  That is still what every case named CONTROL here is for, and cases added since
  carry the label on the same terms. EIGHT of the eleven pass at fd8d023 too.
  The two #204 controls do not - they assert the phrase naming the enumeration,
  which no row carried there - and neither does the #132 one, over a check that
  did not exist there.

  THE #204 CASES BASELINE ON c3e4139, NOT ON fd8d023 - that is the tree the
  defect was reproduced on and the tree they were proved red against, and each
  says so in its own comment.

  NINE OF THE THIRTY HAD NO fd8d023 BASELINE AT ALL - cases 16-18, on the
  informational roster, which did not exist there and is not a defect being
  fixed; case 24, on a code path that did not exist there either; case 25, which
  pins WHICH CHECKS RUN and would pass at fd8d023 only for a doctor carrying the
  same ids; and cases 26-29, on the platform and build rows, which no earlier
  tree carries at all - their red is the absence of the row, and Get-DoctorRow
  returning found = $false is never a pass here. They pin a boundary rather than
  a repair, and their red proof is a mutation or an absent row stated in their
  own comment, not an old commit.

  ---------------------------------------------------------------------------
  WHAT IS DELIBERATELY NOT COVERED
  ---------------------------------------------------------------------------
  * A FOREIGN FILE THAT IS BYTE-IDENTICAL TO THE REPO COPY. It cannot be
    detected and no case here pretends to. Once the provenance marker lives in
    statusline\statusline.ps1, a byte-identical file CARRIES the marker, and it
    is this plugin's status line by every test a content marker can make. What
    the fix removes is the INFERENCE FROM HASH ALONE; case 10 pins the closest
    reachable state instead - the repo copy with its marker line removed, which
    is as near ours as a file can get without being ours - and says so.
  * A FOREIGN FILE THAT MERELY CONTAINS THE TOKEN. The marker is FORGEABLE and
    no case here pretends otherwise: any file with the string
    LWG-STATUSLINE-IDENTITY in its first 4096 bytes is claimed as this
    plugin's, and it then gets the drift WARN and the re-copy remedy - the
    exact harm of #55, reachable by a file that copied one comment line. A
    content token cannot be made unforgeable, so this is a LIMIT rather than a
    defect awaiting a fix, and it is written down because an unstated limit is
    what #55 was. What the marker buys is that an UNRELATED status line - one
    that was never derived from this one and has no reason to carry the token -
    is no longer diagnosed as ours, and that is the case an operator actually
    hits. It buys nothing against a file that quotes it.
  * WHETHER THE STATUS LINE RENDERS. Not a question this file asks. The row's
    prose says the HH segment will not be rendered for a foreign status line;
    nothing here executes anything to confirm that, and
    tests\setup_merge.ps1 section 23 is where the renderer is driven.
  * THE OTHER FIVE CHECKS, and the doctor's exit code on anything but the three
    rows below. Case 3 asserts exit 1 for a seeded non-boolean switch because
    that is the fault's contract with a caller. Cases 17 and 18 read the code
    without asserting a VALUE for it - 17 requires it to equal what the printed
    tally implies, 18 requires the -Quiet run to match the loud one - so neither
    says anything about which code a healthy tree produces.
  * WHAT THE ROSTER SAYS. Cases 16-18 assert that it renders, where it renders
    and what it may not touch. Whether a gate's `resolved:` line is CORRECT is
    tests\gate_delegate.ps1 section P, which drives the same block against
    fixture configs this suite has no way to build.
  * CONFIGINVALIDFLAG IN THE EVENT LOG. Test-LwgFlag writes one and no command
    surfaces it. Surfacing it is a new capability rather than this defect, and
    nothing here asserts on the log's contents.

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

$ManifestPath = Join-Path $Root '.claude-plugin\plugin.json'

$script:Pass    = 0
$script:Results = New-Object System.Collections.ArrayList
$script:Aborted = ''
$script:Work    = ''

# The provenance marker this suite asserts on, spelled ONCE here. It is the
# token bin\lwg-doctor.ps1 greps for in the wired status line and the token
# statusline\statusline.ps1 carries on a comment line near its top. A third
# spelling of it in this file is a third place for it to go stale.
$script:Marker = 'LWG-STATUSLINE-IDENTITY'

# THE CHECK SURFACE, PINNED BY IDENTITY AND NOT BY SIZE (#205).
#
# WHAT WAS WRONG. This suite could not tell that a check had DISAPPEARED. An
# independent QA agent deleted a whole Invoke-Check block from a scratch copy of
# bin\lwg-doctor.ps1 and ran the suite against it:
#
#     doctor with 8 checks  ->  19 of 19, exit 0
#     doctor with 7 checks  ->  19 of 19, exit 0
#
# Green both times. The reason is that the one case reading the header - the
# roster case - asserts the printed rows against the number the DOCTOR derived
# at run time, and header and rows come from the same ArrayList. They agree at
# any count. That derivation is correct and stays: it is why the doctor has
# never transcribed its own number and why the count could not drift silently
# when agent-roles was deleted with verification_gate. The gap was that nothing
# held the other end.
#
# WHY NOT `Rows.Count -eq 8`. A bare count buys the guard and hands back the
# coupling tax this project has already measured (#195): a number asserted here
# AND in every page that counts checks, so adding one check moves assertions
# across the tree. Worse, it reports a smaller number and leaves the reader to
# work out which check went.
#
# WHAT THIS LIST IS. The IDENTITY of the surface, and it is deliberately a
# literal - a list derived from the doctor would be the same tautology the
# header/rows comparison already is. It fails loudly and NAMES the id when a
# check vanishes; it fails when one is ADDED too, which is the moment that
# check's documentation and every row-count claim need writing, so the failure
# is the reminder; and it reads as a decision in the diff - `+ 'platform'` says
# something, `8 -> 9` does not. The count stays derived everywhere else.
$script:ExpectedCheckIds = @(
    'plugin-manifest'
    'marketplace'
    'hooks-declared'
    'config-registry'
    'state-dir'
    'sessionstart'
    'statusline'
    'commands'
    'platform'
    'claude-version'
)

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
# HELPERS
# ---------------------------------------------------------------------------

function Copy-PluginTree {
    <#
      A byte copy of the checkout under the scratch root, minus .git (object
      storage, and a file rather than a directory inside a linked worktree) and
      minus .claude (local harness state - settings.local.json and agent
      worktrees, which are whole second copies of this tree).

      The copy is what every child process runs, so a case can rewrite
      config.json and statusline\statusline.ps1's neighbours without touching
      the checkout.
    #>
    param([string]$From, [string]$To)

    [void][IO.Directory]::CreateDirectory($To)
    foreach ($e in @(Get-ChildItem -LiteralPath $From -Force)) {
        if ($e.Name -eq '.git' -or $e.Name -eq '.claude') { continue }
        Copy-Item -LiteralPath $e.FullName -Destination $To -Recurse -Force
    }
}

function New-CaseTree {
    <#
      A throwaway tree for one case: <work>\<tag>\ holding a profile\ directory
      that stands in for $env:USERPROFILE and a state\ directory that stands in
      for the plugin's data dir.
    #>
    param([string]$Tag)

    $dir = Join-Path $script:Work $Tag
    [void][IO.Directory]::CreateDirectory($dir)
    $prof = Join-Path $dir 'profile'
    [void][IO.Directory]::CreateDirectory((Join-Path $prof '.claude'))
    $state = Join-Path $dir 'state'
    [void][IO.Directory]::CreateDirectory($state)
    return @{ dir = $dir; profile = $prof; state = $state }
}

function Invoke-Doctor {
    <#
      Run the scratch copy's bin\lwg-doctor.ps1 once. Returns @{ code; out } - a
      hashtable, so PowerShell does not enumerate it away across the function
      boundary.

      Every variable is RESTORED rather than removed: this process inherited real
      values and a suite that strips them changes the environment of whatever
      runs after it. The restore is in a finally, so it happens even when the
      child throws.

      stdout is captured and stderr is deliberately NOT merged with 2>&1: in
      Windows PowerShell 5.1 that wraps a native command's stderr in
      NativeCommandError records and corrupts both the output and $?.

      -DoctorPath NAMES A DIFFERENT COPY and defaults to the one shared tree
      every other case drives. The #204 cases need a SECOND plugin copy - one
      with a real .git and an index - because the shared copy is made by
      Copy-PluginTree, which drops .git by design, and the enumeration under
      test is exactly "the tracked tree, or the filesystem when git cannot
      answer". Passing the path is preferred to reassigning $script:DoctorPath:
      a case that forgot to put it back would silently move every case after it
      onto a tree it was not written for.

      CLAUDE_CODE_VERSION IS A FOURTH SANDBOX VARIABLE and it is SEEDED rather
      than cleared. It is seeded to make every case in this file INDEPENDENT OF
      THE MACHINE IT RUNS ON: the variable is inherited, and a host that carried
      an old value would put a claude-version WARN - and therefore exit 2 - on
      every case here that has nothing to do with what it seeded. The default
      seed is the verified build READ OUT OF lib\common.ps1, never spelled here:
      a second copy of that number in this file is a second thing to go stale,
      and it would go stale silently in the direction of a passing case.

      IT USED TO BE SEEDED FOR A SECOND REASON THAT NO LONGER HOLDS, recorded
      because the seed outlived it. An unread build was a WARN until #218, so a
      sandbox that left the variable unset put every exit-0 case in this file on
      a permanent warning and case 1 could not establish that a healthy tree
      reaches 0. An unread build is now a PASS whose detail says it was not
      read, so an unset variable no longer costs the run its exit code - case 27
      is exactly that assertion. The seed stays for the first reason only.

      -Build overrides the seed, and passing '' clears the variable outright,
      which is how the "the build was not read" case is driven. An omitted
      -Build is not the same as an empty one; $PSBoundParameters is what tells
      them apart.

      CLAUDE_CODE_VERSION IS A FIFTH SANDBOX VARIABLE AND IT IS CLEARED (#146).
      The statusline check resolves the configuration directory through
      lib\common.ps1's Get-LwgClaudeHomeInfo, whose precedence puts
      CLAUDE_CONFIG_DIR AHEAD of USERPROFILE - so on a machine that sets it,
      every case here would silently run against the operator's real
      configuration directory instead of the scratch profile it seeded, and the
      statusline cases would report on somebody's live settings.json. Cleared by
      default, and -ConfigDir is how the one case that wants it set gets it.

    #>
    param([string]$ProfileDir, [string]$StateDir, [switch]$QuietRun, [string]$DoctorPath, [string]$Build, [string]$ConfigDir)

    if ([string]::IsNullOrWhiteSpace($DoctorPath)) { $DoctorPath = $script:DoctorPath }
    $seedBuild = if ($PSBoundParameters.ContainsKey('Build')) { $Build } else { $script:VerifiedBuild }

    $prevV = $env:CLAUDE_CODE_VERSION
    $prev  = $env:USERPROFILE
    $prevD = $env:CLAUDE_PLUGIN_DATA
    $prevR = $env:CLAUDE_PLUGIN_ROOT
    $prevC = $env:CLAUDE_CODE_PLUGIN_CACHE_DIR
    $prevH = $env:CLAUDE_CONFIG_DIR
    $out  = ''
    $code = 255
    try {
        $env:USERPROFILE                  = $ProfileDir
        $env:CLAUDE_PLUGIN_DATA           = $StateDir
        $env:CLAUDE_PLUGIN_ROOT           = ''
        $env:CLAUDE_CODE_PLUGIN_CACHE_DIR = ''
        $env:CLAUDE_CONFIG_DIR            = $ConfigDir
        $env:CLAUDE_CODE_VERSION          = $seedBuild
        # -Quiet is passed as a real switch on the child's command line rather
        # than spliced into a string: the only case that uses it asserts what
        # the shipped switch does, and a hand-built argument list is a second
        # thing that can be wrong.
        $lines = if ($QuietRun) {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $DoctorPath -Quiet
        } else {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $DoctorPath
        }
        $code  = if ($null -eq $LASTEXITCODE) { 255 } else { $LASTEXITCODE }
        $out   = ($lines | Out-String)
    } finally {
        $env:USERPROFILE                  = $prev
        $env:CLAUDE_PLUGIN_DATA           = $prevD
        $env:CLAUDE_PLUGIN_ROOT           = $prevR
        $env:CLAUDE_CODE_PLUGIN_CACHE_DIR = $prevC
        $env:CLAUDE_CONFIG_DIR            = $prevH
        $env:CLAUDE_CODE_VERSION          = $prevV
    }
    return @{ code = $code; out = $out }
}

function New-NoFileHashRunner {
    <#
      A one-line launcher script that runs $Target in a real Windows PowerShell
      5.1 child with ONE difference: `Get-FileHash` does not resolve. Any call
      to it throws the CommandNotFoundException a 5.1 child throws when a
      PowerShell 7 PSModulePath has shadowed Microsoft.PowerShell.Utility,
      message included, verbatim (#273). Returns the launcher's path, to be
      passed wherever the script under test would have been.

      WHY THE NAME IS SHADOWED RATHER THAN THE MODULE, and this is the honest
      limit of the case. The fault itself is a PSModulePath state: 5.1 resolves
      `Microsoft.PowerShell.Utility` to PS7's 7.0.0.0 manifest ahead of its own
      3.1.0.0 and loses every FUNCTION that module exports, Get-FileHash among
      them. A SYNTHETIC module does not reproduce it, and that was measured
      before this was written rather than assumed: four manifests were tried -
      PS7's copied verbatim, the same without its NestedModules line, one with
      an empty .psm1, and one exporting a Get-FileHash function - and under
      every one 5.1 fell through to the real 3.1.0.0 module and Get-FileHash
      resolved. Only the REAL PowerShell 7 module directory shadows, because 5.1
      stops searching only when the shadowing module imports for real with its
      own assembly - which a test cannot fabricate, and must not require to be
      installed on the runner.

      So the case reproduces the CONSEQUENCE deterministically instead: the
      command is gone and the error is the measured one, exception type
      included. That a PowerShell 7 launch is what produces that state was
      measured by hand on 2026-09-04, with both runs, and is recorded on #273.
      Nothing here establishes that half.

      WHY AN ALIAS AND NOT A FUNCTION, since a function is the obvious tool and
      was tried first: a function - even `function global:` - loses. It is found
      by Get-Command while the module is still unloaded, but the CALL triggers
      the module auto-load, and the module's own Get-FileHash function replaces
      it before the call binds. An alias is looked up ahead of both, and a
      global alias survives the import.

      The launcher passes its own arguments through, so a caller that adds a
      switch keeps it.
    #>
    param([Parameter(Mandatory = $true)][string]$Path,
          [Parameter(Mandatory = $true)][string]$Target)

    $dir = Split-Path -Parent $Path
    [void][IO.Directory]::CreateDirectory($dir)
    $thrower = Join-Path $dir 'lwg-no-filehash.ps1'
    [IO.File]::WriteAllText($thrower, (
        'throw (New-Object System.Management.Automation.CommandNotFoundException(' +
        '"The term ''Get-FileHash'' is not recognized as the name of a cmdlet, function, script file, ' +
        'or operable program. Check the spelling of the name, or if a path was included, verify that ' +
        'the path is correct and try again."))' + "`r`n"), (New-Object Text.UTF8Encoding($false)))
    $text = @(
        'param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)'
        ''
        ('Set-Alias -Name Get-FileHash -Value ' + "'" + $thrower.Replace("'", "''") + "'" + ' -Scope Global -Force')
        ('& ' + "'" + $Target.Replace("'", "''") + "'" + ' @Rest')
    ) -join "`r`n"
    [IO.File]::WriteAllText($Path, $text + "`r`n", (New-Object Text.UTF8Encoding($false)))
    return $Path
}

function Get-DoctorRow {
    <#
      The FIRST row with this id out of the doctor's report, as
      @{ found; status; detail }.

      found = $false is never treated as a pass by any case here. A row that is
      missing means the check did not run or the report changed shape, and both
      are things a case must go red on rather than quietly satisfy a -notmatch.

      READ "FIRST" BEFORE USING THIS FOR AN ABSENCE. A check can Add-Row more
      than once - Add-Row appends and nothing dedupes an id - so this answers
      "what did the check say first", not "what does the report say". An
      ASSERTION THAT SOMETHING IS ABSENT MUST BE MADE AGAINST THE WHOLE REPORT
      TEXT and never against one row, and every -notmatch in this file is.
      Dropping the `return` after the marker-absent PASS in check 7 makes the
      doctor emit that PASS and then the drift WARN for the SAME target, which
      puts "re-copy it to make the repo's version live" back on a third party's
      file - the entire harm in issue #55 - while the first row still reads
      clean. That mutation was run and this suite stayed green on it until the
      negatives were widened. Positive assertions about what a row SAYS stay
      here, because those are about the check's own answer.
    #>
    param([string]$Text, [string]$Id)

    foreach ($line in ($Text -split "`r?`n")) {
        $m = [regex]::Match($line, '^\s+\[(PASS|INFO|WARN|FAIL)\]\s+(\S+)\s+(.*)$')
        if ($m.Success -and $m.Groups[2].Value -eq $Id) {
            return @{ found = $true; status = $m.Groups[1].Value; detail = $m.Groups[3].Value.Trim() }
        }
    }
    return @{ found = $false; status = '(no row)'; detail = '' }
}

function Set-CaseConfig {
    <#
      Rewrite the scratch copy's config.json from the checkout's PRISTINE text,
      with one mutation applied. Called before EVERY case that reads the config,
      including the ones that want it untouched, so no case here depends on the
      order the cases run in.

      The mutation is applied to the DECODED object and the file is re-emitted,
      so a case seeds the value the doctor's own property lookup will read
      rather than a string this file spliced into JSON by hand.
    #>
    param([scriptblock]$Mutate)

    $cfg = $script:PristineConfigText | ConvertFrom-Json
    if ($null -ne $Mutate) { & $Mutate $cfg }
    $json = ConvertTo-Json -InputObject $cfg -Depth 60
    [IO.File]::WriteAllText($script:PlugConfig, $json, (New-Object Text.UTF8Encoding($false)))
}

function Set-CaseSettings {
    <#
      Write <profile>\.claude\settings.json, which is the only file check 7
      reads. -Command $null writes a settings file with no statusLine key at
      all, which is one of the cases.

      The command line is the shape docs\install.md tells an operator to write:
      powershell, some switches, then a QUOTED path. Quoted deliberately - the
      token scan under test accepts quoted or bare, and quoted is what survives
      a path with a space in it.
    #>
    param([string]$ProfileDir, $Command)

    $p = Join-Path $ProfileDir '.claude\settings.json'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $p))
    $obj = [ordered]@{ someUnrelatedKey = 'left alone' }
    if ($null -ne $Command) {
        $obj['statusLine'] = [ordered]@{ type = 'command'; command = $Command; refreshInterval = 120 }
    }
    [IO.File]::WriteAllText($p, (ConvertTo-Json -InputObject ([pscustomobject]$obj) -Depth 20),
                            (New-Object Text.UTF8Encoding($false)))
    return $p
}

function New-StatusLineCommand {
    param([string]$ScriptPath)
    return ('powershell -NoProfile -ExecutionPolicy Bypass -File "' + $ScriptPath + '"')
}

function Get-EventLogLeafName {
    <#
      The file name check 6 looks for in the state dir, READ OUT OF THE DOCTOR
      ITSELF rather than spelled here.

      This is not cleverness for its own sake. That leaf is a literal in
      bin\lwg-doctor.ps1 and it CHANGED on 3 August 2026 with the lw-gmhh ->
      lw-watchtower rename. A suite that hardcoded either spelling would seed a
      log the doctor does not read at one of the two trees it has to run
      against, check 6 would fail there for a reason that is not in any case
      below, and every exit-code assertion in this file would then be satisfied
      by that unrelated failure instead of by the fault it seeded. Deriving it
      is what keeps cases 1 and 3 honest at both trees.

      A leaf that cannot be derived ABORTS. Guessing one would produce exactly
      the false green just described.
    #>
    param([string]$DoctorSource)

    $txt = [IO.File]::ReadAllText($DoctorSource, [Text.Encoding]::UTF8)
    $m = [regex]::Match($txt, "Join-Path\s+\`$info\.path\s+'([^']+\.jsonl)'")
    if (-not $m.Success) {
        throw "could not read the event-log leaf name out of $DoctorSource, so no case here could seed a log the sessionstart check would read"
    }
    return $m.Groups[1].Value
}

function Get-VerifiedBuild {
    <#
      The Claude Code build the hook events were read out of, READ OUT OF
      lib\common.ps1 rather than spelled here - the same rule, and for the same
      reason, as Get-EventLogLeafName above it.

      Every case in this file that expects exit 0 depends on the seeded build
      being at or above this number, so a second copy of it here would go stale
      silently in the direction of a case that passes. When the plugin's
      verified build moves, the seed moves with it because it IS it.

      A build that cannot be read ABORTS. Guessing one would seed a version
      below the real number and turn every exit-0 case into a WARN nobody wrote.
    #>
    param([string]$CommonSource)

    $txt = [IO.File]::ReadAllText($CommonSource, [Text.Encoding]::UTF8)
    $m = [regex]::Match($txt, '\$script:LwgVerifiedBuild\s*=\s*''([^'']+)''')
    if (-not $m.Success) {
        throw "could not read `$script:LwgVerifiedBuild out of $CommonSource, so no case here could seed the build the claude-version check compares against"
    }
    return $m.Groups[1].Value
}

function New-HealthyCase {
    <#
      A case tree whose sandbox the doctor can actually return EXIT 0 for.

      Two facts a scratch profile cannot have on its own are seeded:

        the SessionStart record  check 6 asks for evidence that the hook has
                                 fired. Nothing has fired in a scratch tree, so
                                 without this the doctor exits 1 in EVERY
                                 sandbox and an exit-code case passes without
                                 ever reading the fault it seeded. That is the
                                 vacuous case this repository has already found
                                 29 of, and it is why this helper exists.
        the status line          check 7 wants settings.json wired at a real
                                 file; it is pointed at a byte copy of the
                                 repo's own statusline\statusline.ps1.

      The record is the minimum check 6 reads: a SessionStart event, a ts inside
      30 days, and a self-check that both RAN and passed.
    #>
    param([string]$Tag, [string]$RepoStatusLine, [string]$LogLeaf)

    $t = New-CaseTree -Tag $Tag
    $rec = [ordered]@{
        event     = 'SessionStart'
        ts        = (Get-Date).ToUniversalTime().ToString('o')
        mode      = 'lwg-doctor-behaviour-fixture'
        selfcheck = [ordered]@{ ran = $true; ok = $true }
    }
    [IO.File]::WriteAllText((Join-Path $t.state $LogLeaf),
        ((ConvertTo-Json -InputObject ([pscustomobject]$rec) -Depth 10 -Compress) + "`r`n"),
        (New-Object Text.UTF8Encoding($false)))

    $installed = Join-Path $t.profile '.claude\statusline.ps1'
    [IO.File]::Copy($RepoStatusLine, $installed, $true)
    [void](Set-CaseSettings -ProfileDir $t.profile -Command (New-StatusLineCommand $installed))
    return $t
}

function Add-LogFiller {
    <#
      Append well-formed event records that are NOT SessionStart until the log
      is at least $MinBytes long, and return the length it reached.

      THE RECORDS ARE VALID JSON ON PURPOSE. Check 6 skips a line it cannot
      parse, so filler that does not decode would prove only that the check
      ignores garbage. What is under test is a window, so the filler has to be
      the thing a window pushes out: real records the check reads and discards
      because their event is not the one it wants.

      Written in ONE append rather than per record. A 9 MB log built line by
      line through the filesystem costs minutes; built in memory and written
      once it costs milliseconds, and the file on disk is identical.
    #>
    param([string]$Path, [int]$MinBytes)

    $have = if ([IO.File]::Exists($Path)) { (Get-Item -LiteralPath $Path).Length } else { 0 }
    $enc  = New-Object Text.UTF8Encoding($false)
    $sb   = New-Object Text.StringBuilder
    $n    = 0
    while (($have + $sb.Length) -lt $MinBytes) {
        $rec = [ordered]@{
            event = 'PostToolUse'
            ts    = (Get-Date).ToUniversalTime().ToString('o')
            n     = $n
            pad   = ('x' * 160)
        }
        [void]$sb.AppendLine((ConvertTo-Json -InputObject ([pscustomobject]$rec) -Depth 5 -Compress))
        $n++
    }
    [IO.File]::AppendAllText($Path, $sb.ToString(), $enc)
    return (Get-Item -LiteralPath $Path).Length
}

function Invoke-GitQuiet {
    <#
      One git command in $Dir. Returns its exit code and swallows both streams.

      stderr is sent to nul and ErrorActionPreference is dropped to 'Continue'
      for the call. In Windows PowerShell 5.1 a native command's stderr comes
      back as NativeCommandError records under 'Stop', and git writes to stderr
      on the ordinary path - `init` prints its hint, `add` prints the CRLF
      warning - so without this every case below would ABORT the suite on a
      command that succeeded.

      -1 means git could not be invoked at all. That is never treated as a pass
      by any case here: a case that cannot build its fixture says so and fails,
      because a skipped case that reports success is the failure mode this
      whole suite exists to argue against.
    #>
    param([string]$Dir, [string[]]$GitArgs)

    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $all = @('-C', $Dir) + $GitArgs
        # Reset first: a missing git binary leaves $LASTEXITCODE untouched, and
        # a stale 0 from some earlier native call would read as success.
        $global:LASTEXITCODE = -1
        & git @all 2>$null | Out-Null
        return $(if ($null -eq $LASTEXITCODE) { -1 } else { $LASTEXITCODE })
    } catch {
        return -1
    } finally { $ErrorActionPreference = $eap }
}

function New-PluginCopy {
    <#
      A SECOND copy of the plugin tree, its own directory under the work root,
      returned as @{ root; doctor }.

      The shared $Plug copy cannot be used for the #204 cases: they plant an
      untracked file in the tree, and a plant left in the copy every other case
      runs would change what those cases measure. A fresh copy per case keeps
      each fixture to itself.
    #>
    param([string]$Tag, [string]$From)

    $root = Join-Path $script:Work ($Tag + '-tree')
    Copy-PluginTree -From $From -To $root
    return @{ root = $root; doctor = (Join-Path $root 'bin\lwg-doctor.ps1') }
}

function Initialize-TrackedCopy {
    <#
      Turn a plugin copy into a real repository with a real index: `git init`
      then `git add`, so `git ls-files` inside it answers with exit 0 and a
      non-empty listing. No commit is made - ls-files reads the INDEX, and a
      commit would need an identity this suite has no business setting.

      -Only restricts what is added, which is how the zero-references case is
      built: a tree where git answers and the answer is one file that mentions
      no command at all.

      Returns the number of files git then lists, or -1 if any git call failed.
      The caller asserts on that rather than assuming the fixture was built.
    #>
    param([string]$Root, [string[]]$Only)

    # A branch name is supplied so git does not print its default-branch advice,
    # and autocrlf is pinned off so a checkout's global setting cannot rewrite
    # bytes on the way into the index.
    if ((Invoke-GitQuiet -Dir $Root -GitArgs @('-c', 'init.defaultBranch=fixture', 'init', '-q')) -ne 0) { return -1 }
    $add = if ($Only) { @('-c', 'core.autocrlf=false', 'add', '--') + $Only }
           else       { @('-c', 'core.autocrlf=false', 'add', '-A') }
    if ((Invoke-GitQuiet -Dir $Root -GitArgs $add) -ne 0) { return -1 }

    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $global:LASTEXITCODE = -1
        $listed = & git -C $Root -c core.quotePath=false ls-files 2>$null
        if ($LASTEXITCODE -ne 0) { return -1 }
        return @($listed | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count
    } catch { return -1 } finally { $ErrorActionPreference = $eap }
}

function Add-UntrackedOffender {
    <#
      An untracked file in the plugin copy's root that references two command
      names which do not exist - the shape of the generated-output directory
      that reproduced #198's failure chain from a checkout whose TRACKED tree
      was clean.

      The names are built from the manifest's own plugin id and are deliberately
      names no commands\*.md carries. Returns the path written.
    #>
    param([string]$Root, [string]$PluginName)

    $dir = Join-Path $Root 'generated-output'
    [void][IO.Directory]::CreateDirectory($dir)
    $f = Join-Path $dir 'notes.md'
    [IO.File]::WriteAllText($f,
        "generated output, no part of the plugin`r`n" +
        "run /${PluginName}:tripped then /${PluginName}:status to see the ledger`r`n",
        (New-Object Text.UTF8Encoding($false)))
    return $f
}

function Get-RowMap {
    <# Every row in a doctor report as id -> status. Used only to compare two
       runs of the SAME sandbox against each other. #>
    param([string]$Text)
    $map = [ordered]@{}
    foreach ($line in ($Text -split "`r?`n")) {
        $m = [regex]::Match($line, '^\s+\[(PASS|INFO|WARN|FAIL)\]\s+(\S+)\s+(.*)$')
        if ($m.Success) { $map[$m.Groups[2].Value] = $m.Groups[1].Value }
    }
    return $map
}

function Test-BytesEqual {
    param($A, $B)
    if ($null -eq $A -or $null -eq $B) { return $false }
    if ($A.Length -ne $B.Length) { return $false }
    for ($i = 0; $i -lt $A.Length; $i++) { if ($A[$i] -ne $B[$i]) { return $false } }
    return $true
}

function Write-StrippedStatusLine {
    <#
      The repo's status line with every line carrying the provenance marker
      REMOVED, written byte-for-byte otherwise.

      This is the closest thing to a foreign file that a content test can be
      asked about, and it is built by removing rather than by hand-writing so
      that at a baseline which has no marker at all it is BYTE-IDENTICAL to the
      repo copy - which is exactly the state issue #55 says the old check
      attested an install for.

      The read is round-trip checked before anything is removed. If UTF-8
      decode/encode is not byte-exact for this file the fixture would be a
      different file for a reason that is not in the code under test, and that
      ABORTS rather than producing a case that passes on the wrong bytes.
    #>
    param([string]$RepoCopy, [string]$Dest)

    $bytes = [IO.File]::ReadAllBytes($RepoCopy)
    $text  = [Text.Encoding]::UTF8.GetString($bytes)
    if (-not (Test-BytesEqual ([Text.Encoding]::UTF8.GetBytes($text)) $bytes)) {
        throw "UTF-8 round-trip of $RepoCopy is not byte-exact, so the marker-stripped fixture could not be built from it"
    }
    $stripped = [regex]::Replace($text, '(?m)^.*' + [regex]::Escape($script:Marker) + '.*\r?\n', '')
    [IO.File]::WriteAllBytes($Dest, [Text.Encoding]::UTF8.GetBytes($stripped))
    return (Test-BytesEqual ([IO.File]::ReadAllBytes($Dest)) $bytes)
}

function Get-LiveLogSizes {
    <#
      Every *.jsonl under the OPERATOR'S REAL ~\.claude\plugins\data that belongs
      to this plugin, as path -> length. Read-only, and narrowed to this
      plugin's own directories so another plugin writing during the run cannot
      make the last case flap.
    #>
    param([string]$RealProfile, [string]$PluginName)

    $map  = @{}
    $base = Join-Path $RealProfile '.claude\plugins\data'
    if (-not [IO.Directory]::Exists($base)) { return $map }
    foreach ($d in @(Get-ChildItem -LiteralPath $base -Directory -Filter "$PluginName*" -ErrorAction SilentlyContinue)) {
        foreach ($f in @(Get-ChildItem -LiteralPath $d.FullName -Recurse -File -ErrorAction SilentlyContinue)) {
            $map[$f.FullName] = $f.Length
        }
    }
    return $map
}

# ===========================================================================
# MAIN
# ===========================================================================
$sw = [Diagnostics.Stopwatch]::StartNew()

try {
    Write-Output 'LW-WATCHTOWER doctor behaviour regression suite'
    Write-Output "  repo    : $Root"
    Write-Output '  under   : bin\lwg-doctor.ps1, checks config-registry, statusline, sessionstart, commands, platform and claude-version only'
    Write-Output ''

    foreach ($p in @((Join-Path $Root 'bin\lwg-doctor.ps1'),
                     (Join-Path $Root 'lib\common.ps1'),
                     (Join-Path $Root 'config.json'),
                     (Join-Path $Root 'statusline\statusline.ps1'),
                     $ManifestPath)) {
        if (-not [IO.File]::Exists($p)) { throw "missing: $p" }
    }

    # The declared plugin name, derived rather than spelled out: this id changed
    # once already, on 3 August 2026, and a suite holding a second hardcoded
    # spelling of it goes stale silently the next time.
    $manifest   = ([IO.File]::ReadAllText($ManifestPath, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF)) | ConvertFrom-Json
    $PluginName = [string]$manifest.name
    if ([string]::IsNullOrWhiteSpace($PluginName)) {
        throw "$ManifestPath declares no name, so the live-log guard below could not be pointed at this plugin's directories"
    }

    $RealProfile = $env:USERPROFILE
    $liveBefore  = Get-LiveLogSizes -RealProfile $RealProfile -PluginName $PluginName

    $script:Work = Join-Path ([IO.Path]::GetTempPath()) ('lwg-doctor-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
    [void][IO.Directory]::CreateDirectory($script:Work)

    $Plug = Join-Path $script:Work 'plugin'
    Copy-PluginTree -From $Root -To $Plug

    $script:DoctorPath        = Join-Path $Plug 'bin\lwg-doctor.ps1'
    $script:PlugConfig        = Join-Path $Plug 'config.json'
    $script:PristineConfigText = [IO.File]::ReadAllText((Join-Path $Root 'config.json'), [Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
    $PlugStatusLine           = Join-Path $Plug 'statusline\statusline.ps1'

    foreach ($p in @($script:DoctorPath, $script:PlugConfig, $PlugStatusLine)) {
        if (-not [IO.File]::Exists($p)) { throw "the plugin copy is incomplete: $p is missing, so no case below would have driven the real file" }
    }

    $LogLeaf = Get-EventLogLeafName -DoctorSource $script:DoctorPath

    # Read from the COPY, which is the lib\common.ps1 the doctor under test
    # dot-sources - not from the checkout, which is one file removed from it.
    $script:VerifiedBuild = Get-VerifiedBuild -CommonSource (Join-Path $Plug 'lib\common.ps1')

    # -------------------------------------------------------------------
    # 1. CONTROL, and it passes at fd8d023 too.
    #
    #    The checkout's own config.json, round-tripped and nothing else, in a
    #    sandbox seeded so that every OTHER check can pass: config-registry must
    #    PASS and the doctor must exit 0.
    #
    #    IT CARRIES TWO JOBS AND THE SECOND IS THE IMPORTANT ONE. First, "FAIL
    #    on everything" would pass cases 2, 4 and 5 and destroy the check, and
    #    this is what stops that. Second, exit 0 HERE is what makes exit 1 in
    #    case 3 mean anything: without a sandbox that can reach 0, the seeded
    #    fault would be credited with a failure that check 6 or check 7 had
    #    already produced.
    #
    #    BASELINE fd8d023: '[PASS] config-registry  parses; all 9 module flags
    #    match the registry exactly; 1 module(s) switched from outside that
    #    block, each on a key that exists: delegate_gate -> interaction.delegate'
    #    and 'VERDICT: healthy - every check above passed.', exit 0.
    # -------------------------------------------------------------------
    Set-CaseConfig -Mutate $null
    $t = New-HealthyCase -Tag 'cfg-clean' -RepoStatusLine $PlugStatusLine -LogLeaf $LogLeaf
    $clean = Invoke-Doctor -ProfileDir $t.profile -StateDir $t.state
    $row   = Get-DoctorRow -Text $clean.out -Id 'config-registry'
    Add-Result 'CONTROL config-registry: the shipped config.json passes and the run exits 0' `
        ($row.found -and $row.status -eq 'PASS' -and $clean.code -eq 0) `
        "expected a PASS row and exit 0; got [$($row.status)] $($row.detail) at exit $($clean.code). Full output:`n$($clean.out)"

    # -------------------------------------------------------------------
    # 2. #41. A DECLARED SWITCH HOLDING A QUOTED "true".
    #
    #    Test-LwgFlag (lib\common.ps1) requires $g -is [bool] and otherwise
    #    ignores the value, so interaction.delegate = "true" leaves delegate_gate
    #    on its registry default of $false - the gate is OFF while the file says
    #    on. The check must ask the same question the reader asks.
    #
    #    KEYED ON THE DETAIL TEXT, not on the status alone: config-registry can
    #    fail for a parity reason that has nothing to do with this defect, and a
    #    case asserting only FAIL would go green on the wrong fault.
    #
    #    BASELINE fd8d023: '[PASS] config-registry  parses; all 9 module flags
    #    match the registry exactly; 1 module(s) switched from outside that
    #    block, each on a key that exists: delegate_gate -> interaction.delegate'
    #    - the doctor reported healthy over a disarmed gate.
    # -------------------------------------------------------------------
    Set-CaseConfig -Mutate { param($c) $c.interaction.delegate = 'true' }
    $t = New-HealthyCase -Tag 'cfg-switch-string' -RepoStatusLine $PlugStatusLine -LogLeaf $LogLeaf
    $seeded = Invoke-Doctor -ProfileDir $t.profile -StateDir $t.state
    $row    = Get-DoctorRow -Text $seeded.out -Id 'config-registry'
    Add-Result 'a quoted "true" on a declared switch FAILS config-registry, naming the value' `
        ($row.found -and $row.status -eq 'FAIL' -and $row.detail -match 'interaction\.delegate' -and $row.detail -match 'rather than a boolean') `
        "expected FAIL naming interaction.delegate and 'rather than a boolean'; got [$($row.status)] $($row.detail). Full output:`n$($seeded.out)"

    # -------------------------------------------------------------------
    # 3. THE SAME SEED, READ THE WAY A CALLER READS IT. The exit code is what
    #    /lw-watchtower:doctor's caller is promised and 1 is "something is
    #    broken now". A row that says FAIL under an exit 0 is a diagnosis
    #    nothing acts on.
    #
    #    This is only a claim about the SEEDED fault because case 1 established
    #    that this same sandbox exits 0 without it.
    #
    #    BASELINE fd8d023: exit 0, 'VERDICT: healthy - every check above passed.'
    # -------------------------------------------------------------------
    Add-Result 'the same seed makes the doctor exit 1, not 0' `
        ($seeded.code -eq 1) `
        "expected exit 1; got $($seeded.code), and case 1 showed this sandbox reaching 0 without the seed. Full output:`n$($seeded.out)"

    # -------------------------------------------------------------------
    # 4. CONTROL, and it passes at fd8d023 too. THE SEED MOVES ONE ROW AND NO
    #    OTHER. Two runs of the same sandbox, differing only in that one config
    #    value: every row except config-registry must hold the status it had.
    #
    #    A fix that widened a check, or that made the doctor fail for a second
    #    reason on the way, would be invisible to cases 2 and 3 and is visible
    #    here.
    #
    #    BASELINE fd8d023: passes - the two runs were identical, because the
    #    seed changed nothing at all.
    # -------------------------------------------------------------------
    $before = Get-RowMap -Text $clean.out
    $after  = Get-RowMap -Text $seeded.out
    $moved  = @()
    foreach ($id in $before.Keys) {
        if ($id -eq 'config-registry') { continue }
        $was = $before[$id]
        $now = if ($after.Contains($id)) { $after[$id] } else { '(row gone)' }
        if ($was -ne $now) { $moved += "$id ${was} -> $now" }
    }
    Add-Result 'CONTROL config-registry: seeding the switch moves that row and no other' `
        ($before.Count -gt 1 -and $moved.Count -eq 0) `
        "$($moved.Count) other row(s) changed status between the clean and seeded runs: $($moved -join '; ') (rows seen: $($before.Count))"

    # -------------------------------------------------------------------
    # 5. #41, SECOND HALF. A NON-BOOLEAN IN THE `modules` BLOCK.
    #
    #    The check read $cfg.modules.PSObject.Properties.Name - names only,
    #    never values - so this was invisible to it. Test-LwgModule's own
    #    docstring records that "modules": { "docs_coupling": "false" } ENABLED
    #    docs_coupling before the boolean rule landed in the reader. The
    #    polarity is the opposite of case 2 and the detail must say so: an
    #    ignored `modules` value leaves the module ON.
    #
    #    THREE KEYS ARE SEEDED, AT THE FIRST, A MIDDLE AND THE LAST POSITION IN
    #    THE BLOCK, and every one must be named in the row. One key was not
    #    enough and the gap was found by mutation rather than by reading: with
    #    only docs_coupling seeded - sixth of nine - a loop mutated to
    #    `| Select-Object -Skip 1` still caught it and this suite stayed green,
    #    so the case could not tell "every value is checked" from "most of them
    #    are". The first and last names are DERIVED from config.json's own
    #    property order rather than spelled here, so adding a module moves the
    #    guard with it instead of quietly retiring it.
    #
    #    The three values are a number, a string and a JSON null, which are the
    #    three shapes an operator actually writes. Null is not a special case in
    #    the reader either: Test-LwgModule skips a null exactly as it skips a
    #    string, and the module stays on.
    #
    #    BASELINE fd8d023: '[PASS] config-registry  parses; all 9 module flags
    #    match the registry exactly; 1 module(s) switched from outside that
    #    block, each on a key that exists: delegate_gate -> interaction.delegate'
    # -------------------------------------------------------------------
    $modNames = @(($script:PristineConfigText | ConvertFrom-Json).modules.PSObject.Properties.Name)
    $modFirst = $modNames[0]
    $modLast  = $modNames[$modNames.Count - 1]
    # Named by Test-LwgModule's own docstring as the flag a quoted "false"
    # ENABLED, so it is the value this case is really about.
    $modMid   = 'docs_coupling'
    if ($modNames.Count -lt 3 -or $modNames -notcontains $modMid -or
        $modMid -eq $modFirst -or $modMid -eq $modLast) {
        throw ("config.json's modules block is [$($modNames -join ', ')] - this case needs '$modMid' present and away from both ends, " +
               "or the first/last positional guard proves nothing")
    }
    Set-CaseConfig -Mutate {
        param($c)
        $c.modules.$modFirst = 1
        $c.modules.$modMid   = 'false'
        $c.modules.$modLast  = $null
    }
    $t = New-HealthyCase -Tag 'cfg-module-string' -RepoStatusLine $PlugStatusLine -LogLeaf $LogLeaf
    $r   = Invoke-Doctor -ProfileDir $t.profile -StateDir $t.state
    $row = Get-DoctorRow -Text $r.out -Id 'config-registry'
    $named = @($modFirst, $modMid, $modLast | Where-Object { $row.detail -notmatch ("modules\." + [regex]::Escape($_) + '\b') })
    Add-Result 'every non-boolean in the modules block FAILS config-registry, first, middle and last' `
        ($row.found -and $row.status -eq 'FAIL' -and $named.Count -eq 0 -and $row.detail -match 'rather than a boolean') `
        "expected FAIL naming modules.$modFirst, modules.$modMid and modules.$modLast; $($named.Count) unnamed ($($named -join ', ')). Got [$($row.status)] $($row.detail). Full output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 6. THE POLARITY IS STATED, not left to be inferred. A reader of the row
    #    has to know which way the module ended up, because the two blocks
    #    resolve opposite ways and the remedy differs: an ignored switch value
    #    leaves a gate OFF, an ignored `modules` value leaves a module ON.
    #
    #    BASELINE fd8d023: no such row - the check passed.
    # -------------------------------------------------------------------
    Add-Result 'the modules-block row says the module stays ON, which is the polarity' `
        ($row.found -and $row.detail -match '(?i)stays ON') `
        "expected the detail to say the module stays on; got [$($row.status)] $($row.detail)"

    # -------------------------------------------------------------------
    # 6a. #11. AN OPERATOR OVERRIDE THAT WAS READ AND THEN DISCARDED.
    #
    #     Since 3 September 2026 config.json is the SHIPPED DEFAULTS and nothing
    #     writes it: the operator's ON/OFF choices go to config.override.json
    #     under the state directory, and Get-LwgConfig merges that over the
    #     defaults. It IGNORES an override it cannot parse rather than throwing -
    #     the right polarity, because a half-written settings file must not arm a
    #     gate and must not take the plugin down - and carries the reason out in
    #     _override_error.
    #
    #     _source IS STILL 'file' ON THAT PATH, which is why this needs its own
    #     case. config.json parsed perfectly; it is the second document that did
    #     not. So every check below, the roster at the foot and the SessionStart
    #     banner report the SHIPPED DEFAULTS while an operator's entire
    #     configuration sits in a file nothing read - and until this row the
    #     doctor called that machine healthy and exited 0. Both configuring
    #     commands already refuse to write in this state and name the file; this
    #     is the reporting half of the same rule.
    #
    #     THE FIXTURE IS TRUNCATED JSON, not gibberish: it is what a settings
    #     file looks like after a crashed or interrupted write, which is how an
    #     operator gets into this state without doing anything wrong.
    #
    #     BASELINE c39e782: '[PASS] config-registry  parses; all 9 module flags
    #     match the registry exactly ...' and exit 0 - the doctor reported a
    #     healthy machine over a configuration it had thrown away.
    # -------------------------------------------------------------------
    Set-CaseConfig -Mutate $null
    $t = New-HealthyCase -Tag 'cfg-override-broken' -RepoStatusLine $PlugStatusLine -LogLeaf $LogLeaf
    $ovBroken = Join-Path $t.state 'config.override.json'
    [IO.File]::WriteAllText($ovBroken, '{ "modules": { "docs_coupling": fal',
                            (New-Object Text.UTF8Encoding($false)))
    $rOv  = Invoke-Doctor -ProfileDir $t.profile -StateDir $t.state
    $rowOv = Get-DoctorRow -Text $rOv.out -Id 'config-registry'

    Add-Result 'an operator override that does not parse FAILS config-registry, naming the file (#11)' `
        ($rowOv.found -and $rowOv.status -eq 'FAIL' -and
         $rowOv.detail -match [regex]::Escape($ovBroken) -and $rowOv.detail -match '(?i)ignored') `
        ("expected FAIL naming $ovBroken and saying its contents are being ignored; got [$($rowOv.status)] $($rowOv.detail). " +
         "config.json parses here, so _source is 'file' and the existing checks see nothing wrong. Full output:`n$($rOv.out)")

    # -------------------------------------------------------------------
    # 6b. THE SAME SEED, READ THE WAY A CALLER READS IT. Same argument as
    #     case 3: a row that says FAIL under an exit 0 is a diagnosis nothing
    #     acts on, and case 1 established that this sandbox reaches 0 without
    #     the seed.
    #
    #     BASELINE c39e782: exit 0.
    # -------------------------------------------------------------------
    Add-Result 'a discarded override makes the doctor exit 1, not 0 (#11)' `
        ($rOv.code -eq 1) `
        "expected exit 1; got $($rOv.code), and case 1 showed this sandbox reaching 0 without the seed. Full output:`n$($rOv.out)"

    # -------------------------------------------------------------------
    # 6c. AND THE ROSTER SAYS WHICH FILE, beside the one it already names.
    #
    #     The `config:` line at the foot of the report named config.json alone,
    #     which on a configured machine credits every operator setting to a file
    #     that holds none of them. The wording is lifted from bin\lwg-config.ps1's
    #     own source line so the two commands describe one machine in one
    #     vocabulary.
    #
    #     THE ROSTER IS NOT A ROW, so this is asserted against the whole report
    #     text. It is also informational and cannot fail the run, which is
    #     exactly why the row above exists as well: a reader who stops at the
    #     verdict must still be told.
    #
    #     BASELINE c39e782: the line read 'resolved for repo: ...   config:
    #     config.json' and said nothing about an override at all.
    # -------------------------------------------------------------------
    Add-Result 'and the roster names the discarded override rather than crediting config.json (#11)' `
        ($rOv.out -match ('(?m)^\s+resolved for repo:.*override: IGNORED - ' + [regex]::Escape($ovBroken))) `
        "expected the roster's resolved-for-repo line to carry 'override: IGNORED - $ovBroken'. Full output:`n$($rOv.out)"

    # -------------------------------------------------------------------
    # 6d. CONTROL. A VALID override is NOT a finding, and the roster names it.
    #
    #     Without this, "FAIL whenever an override exists" passes 6a, 6b and 6c
    #     and breaks every configured machine - which is the shape of over-fix
    #     this file's other controls exist to catch. The override here switches a
    #     real module off, which is the ordinary state of any machine that has
    #     ever run /lw-watchtower:config.
    #
    #     BASELINE c39e782: the row PASSED (correctly) and the roster named no
    #     override, so the second half of this case is red there and the first
    #     is green - which is what makes it a control rather than a duplicate.
    # -------------------------------------------------------------------
    $t2 = New-HealthyCase -Tag 'cfg-override-valid' -RepoStatusLine $PlugStatusLine -LogLeaf $LogLeaf
    $ovGood = Join-Path $t2.state 'config.override.json'
    [IO.File]::WriteAllText($ovGood, '{ "modules": { "docs_coupling": false } }',
                            (New-Object Text.UTF8Encoding($false)))
    $rGood  = Invoke-Doctor -ProfileDir $t2.profile -StateDir $t2.state
    $rowGood = Get-DoctorRow -Text $rGood.out -Id 'config-registry'

    Add-Result 'CONTROL: a VALID override is not a finding, and the roster names it as the file in effect (#11)' `
        ($rowGood.found -and $rowGood.status -eq 'PASS' -and $rGood.code -eq 0 -and
         $rGood.out -match ('(?m)^\s+resolved for repo:.*override: ' + [regex]::Escape($ovGood))) `
        ("expected a PASS row, exit 0 and the roster naming $ovGood; got [$($rowGood.status)] at exit $($rGood.code). Full output:`n$($rGood.out)")

    # -------------------------------------------------------------------
    # 6e. CONTROL. NO override at all - a fresh install - says so positively.
    #
    #     'none - these are the shipped defaults' is not decoration: the other
    #     two states are a path, and a blank there would be indistinguishable
    #     from a line that failed to render. This is also what stops the roster
    #     printing the word `override` only when something is wrong, which would
    #     make its absence the thing a reader has to notice.
    #
    #     BASELINE c39e782: no override text on that line in any state.
    # -------------------------------------------------------------------
    Add-Result 'CONTROL: with no override the roster says so, rather than leaving the line silent (#11)' `
        ($clean.out -match '(?m)^\s+resolved for repo:.*override: none - these are the shipped defaults') `
        "case 1's sandbox has no config.override.json, so the roster must say so positively. Full output:`n$($clean.out)"

    # -------------------------------------------------------------------
    # 7. #55. A THIRD PARTY'S STATUS LINE MUST NOT BE DIAGNOSED AS OURS.
    #
    #    The operator wrote their own status line, or another plugin ships one.
    #    docs\install.md presents this plugin's status line as a separate manual
    #    step, so a machine with somebody else's status line already wired is
    #    the NORMAL state, not a fault.
    #
    #    BASELINE fd8d023: '[WARN] statusline  wired to ...\my-statusline.ps1,
    #    but it DIFFERS from statusline/statusline.ps1 in this repo - the
    #    installed copy is stale or locally modified; re-copy it to make the
    #    repo's version live' - a destructive instruction about a file this
    #    plugin does not own.
    # -------------------------------------------------------------------
    Set-CaseConfig -Mutate $null
    $t = New-CaseTree -Tag 'sl-foreign'
    $foreign = Join-Path $t.profile '.claude\my-statusline.ps1'
    [IO.File]::WriteAllText($foreign,
        "# somebody else's status line - not this plugin's, and not derived from it`r`nWrite-Output 'x'`r`n",
        (New-Object Text.UTF8Encoding($false)))
    [void](Set-CaseSettings -ProfileDir $t.profile -Command (New-StatusLineCommand $foreign))
    $r   = Invoke-Doctor -ProfileDir $t.profile -StateDir $t.state
    $row = Get-DoctorRow -Text $r.out -Id 'statusline'
    # THE WHOLE REPORT, NOT THE ROW. See Get-DoctorRow: a check that emits its
    # provenance answer and then falls through to the drift branch prints the
    # destructive remedy in a SECOND row, and the first row still reads clean.
    Add-Result 'a foreign status line is not told to be overwritten with the repo copy' `
        ($row.found -and $r.out -notmatch 're-copy it' -and $r.out -notmatch 'stale or locally modified') `
        "the report still printed the destructive remedy for a file this plugin does not own. First statusline row: [$($row.status)] $($row.detail). Full output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 8. THE POSITIVE TWIN OF CASE 7. An absence proves nothing on its own - a
    #    check that threw, a renamed row or an aborted doctor all satisfy a
    #    -notmatch. So the row must be PRESENT, must name the target, and must
    #    say in as many words that the file was not established as this
    #    plugin's.
    #
    #    IT IS NOT A FAULT, which is why PASS is the status asserted. A status
    #    line belonging to somebody else is a legitimate configuration; what the
    #    operator is owed is the consequence, which is that this plugin's
    #    segment will not be rendered.
    #
    #    BASELINE fd8d023: the row said the opposite - that the file is this
    #    plugin's, stale.
    # -------------------------------------------------------------------
    Add-Result 'the foreign-status-line row says so, names the file, and is not a fault' `
        ($row.found -and $row.status -eq 'PASS' -and $row.detail -match 'my-statusline\.ps1' -and $row.detail -match "(?i)not this plugin's") `
        "expected a PASS row naming the target and saying it is not this plugin's status line; got [$($row.status)] $($row.detail). Full output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 9. CONTROL, and it passes at fd8d023 too. THE FILE THAT IS OURS AND HAS
    #    DRIFTED STILL GETS THE OLD WARNING, with the old remedy, unchanged.
    #
    #    This is the case that makes case 7 mean something. "Never warn" passes
    #    case 7 and deletes the only thing the check was ever right about, and
    #    a marker literal that can never match passes case 7 as well - this is
    #    what catches both.
    #
    #    BASELINE fd8d023: '[WARN] statusline  ... the installed copy is stale
    #    or locally modified; re-copy it...', for the same reason it said it
    #    about everything.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'sl-ours-drifted'
    $drifted = Join-Path $t.profile '.claude\statusline.ps1'
    [IO.File]::WriteAllBytes($drifted, ([IO.File]::ReadAllBytes($PlugStatusLine) +
        [Text.Encoding]::UTF8.GetBytes("`r`n# a local modification, so the bytes differ`r`n")))
    [void](Set-CaseSettings -ProfileDir $t.profile -Command (New-StatusLineCommand $drifted))
    $r   = Invoke-Doctor -ProfileDir $t.profile -StateDir $t.state
    $row = Get-DoctorRow -Text $r.out -Id 'statusline'
    Add-Result 'CONTROL statusline: our own file, drifted, still WARNs with the re-copy remedy' `
        ($row.found -and $row.status -eq 'WARN' -and $row.detail -match 're-copy it') `
        "expected the drift WARN; got [$($row.status)] $($row.detail). Full output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 10. #55'S INVERSE. AN IDENTICAL FILE MUST NOT ATTEST AN INSTALL.
    #
    #    The fixture is the repo copy with every marker line removed and every
    #    other byte kept. READ THE ASYMMETRY, because it is the whole point of
    #    the case: at a baseline with no marker in the file, removing nothing
    #    leaves a BYTE-IDENTICAL file, and the old check answered
    #    '; matches the repo copy' - attesting an install that never happened,
    #    off a hash and nothing else. With the marker in place the same rule
    #    yields a file that is ours in every byte but the marker, and the check
    #    must decline to attest it.
    #
    #    A file that is identical INCLUDING the marker is not covered and cannot
    #    be - see the header. This is the closest reachable state.
    #
    #    BASELINE fd8d023: '[PASS] statusline  wired to ...\statusline.ps1;
    #    matches the repo copy'.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'sl-nearly-identical'
    $nearly = Join-Path $t.profile '.claude\statusline.ps1'
    $wasIdentical = Write-StrippedStatusLine -RepoCopy $PlugStatusLine -Dest $nearly
    [void](Set-CaseSettings -ProfileDir $t.profile -Command (New-StatusLineCommand $nearly))
    $r   = Invoke-Doctor -ProfileDir $t.profile -StateDir $t.state
    $row = Get-DoctorRow -Text $r.out -Id 'statusline'
    # Whole report, same reason as case 7: a second row attesting the match is
    # exactly as wrong as a first one.
    Add-Result 'a marker-less copy of the repo file does not attest an install' `
        ($row.found -and $r.out -notmatch 'matches the repo copy') `
        "the report attested an install for a file carrying no marker (byte-identical to the repo copy: $wasIdentical). First statusline row: [$($row.status)] $($row.detail). Full output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 11. THE POSITIVE TWIN OF CASE 10, and the same rule as case 8: the row has
    #     to be there and has to say what it concluded. It must also not print
    #     the destructive remedy, because provenance was not established here
    #     either.
    #
    #     BASELINE fd8d023: the row attested a match.
    # -------------------------------------------------------------------
    Add-Result "a marker-less copy is reported as not this plugin's, with no remedy to overwrite it" `
        ($row.found -and $row.detail -match "(?i)not this plugin's" -and $r.out -notmatch 're-copy it') `
        "expected a row saying the file is not this plugin's and no overwrite remedy anywhere in the report; got [$($row.status)] $($row.detail). Full output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 12. CONTROL, and it passes at fd8d023 too. A REAL INSTALL STILL ATTESTS.
    #
    #     The repo copy, byte for byte, wired as the status line - which is what
    #     bin\lwg-setup.ps1 produces. If a fix for case 10 also stopped this from
    #     attesting, the check would have stopped answering the question it was
    #     built for.
    #
    #     BASELINE fd8d023: '[PASS] statusline  wired to ...; matches the repo
    #     copy'.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'sl-real-install'
    $installed = Join-Path $t.profile '.claude\statusline.ps1'
    [IO.File]::Copy($PlugStatusLine, $installed, $true)
    [void](Set-CaseSettings -ProfileDir $t.profile -Command (New-StatusLineCommand $installed))
    $r   = Invoke-Doctor -ProfileDir $t.profile -StateDir $t.state
    $row = Get-DoctorRow -Text $r.out -Id 'statusline'
    Add-Result 'CONTROL statusline: a real install of the repo copy still attests a match' `
        ($row.found -and $row.status -eq 'PASS' -and $row.detail -match 'matches the repo copy') `
        "expected PASS attesting the match; got [$($row.status)] $($row.detail). Full output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 13. CONTROL, and it passes at fd8d023 too. "I FOUND A FAULT" IS NOT
    #     COLLAPSED INTO "IT IS SOMEBODY ELSE'S".
    #
    #     statusLine.command naming a .ps1 that does not exist is a real fault -
    #     the status line is configured and broken, and renders as nothing. A
    #     provenance test placed ahead of the existence test would turn that
    #     into a shrug.
    #
    #     BASELINE fd8d023: '[FAIL] statusline  statusLine.command points at ...
    #     which does not exist...'.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'sl-missing-target'
    $ghost = Join-Path $t.profile '.claude\not-here.ps1'
    [void](Set-CaseSettings -ProfileDir $t.profile -Command (New-StatusLineCommand $ghost))
    $r   = Invoke-Doctor -ProfileDir $t.profile -StateDir $t.state
    $row = Get-DoctorRow -Text $r.out -Id 'statusline'
    Add-Result 'CONTROL statusline: a wired .ps1 that does not exist is still a FAIL' `
        ($row.found -and $row.status -eq 'FAIL' -and $row.detail -match 'does not exist') `
        "expected FAIL for a missing target; got [$($row.status)] $($row.detail). Full output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 14. CONTROL, and it passes at fd8d023 too. NO statusLine AT ALL IS STILL
    #     A FAIL, which is the row's original purpose: with it unwired this
    #     plugin has no visible indicator.
    #
    #     BASELINE fd8d023: '[FAIL] statusline  ...settings.json has no
    #     statusLine.command...'.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'sl-absent'
    [void](Set-CaseSettings -ProfileDir $t.profile -Command $null)
    $r   = Invoke-Doctor -ProfileDir $t.profile -StateDir $t.state
    $row = Get-DoctorRow -Text $r.out -Id 'statusline'
    Add-Result 'CONTROL statusline: no statusLine.command at all is still a FAIL' `
        ($row.found -and $row.status -eq 'FAIL' -and $row.detail -match 'no statusLine\.command') `
        "expected FAIL for an unwired status line; got [$($row.status)] $($row.detail). Full output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 15. "I FOUND A FAULT" AND "I COULD NOT LOOK" ARE DIFFERENT STATEMENTS,
    #     and bin\lwg-doctor.ps1's own header (lines 26-28) says collapsing them
    #     would let a crashed doctor be read as a diagnosis. A provenance test
    #     is a READ, and a read can fail: the wired file is held open by
    #     something else, or the account cannot open it.
    #
    #     The target here is a real file this suite holds open with
    #     FileShare.None for the duration of the child process, which is the
    #     cheapest reproducible unreadable file on Windows. The row must say
    #     provenance was NOT established, and must not print a remedy - the one
    #     thing that is certainly wrong is telling an operator to overwrite a
    #     file nothing could even read.
    #
    #     BASELINE fd8d023: '[FAIL] statusline  check threw: The process cannot
    #     access the file ... because it is being used by another process.' -
    #     Get-FileHash threw straight into Invoke-Check's catch, so an unreadable
    #     file was reported as a FAULT IN THE PLUGIN.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'sl-unreadable'
    $locked = Join-Path $t.profile '.claude\locked-statusline.ps1'
    [IO.File]::WriteAllText($locked, "# a status line this run cannot read`r`n",
                            (New-Object Text.UTF8Encoding($false)))
    [void](Set-CaseSettings -ProfileDir $t.profile -Command (New-StatusLineCommand $locked))
    $lock = [IO.File]::Open($locked, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    try {
        $r = Invoke-Doctor -ProfileDir $t.profile -StateDir $t.state
    } finally { $lock.Dispose() }
    $row = Get-DoctorRow -Text $r.out -Id 'statusline'
    Add-Result 'a wired file that cannot be read is reported as unestablished, not as a fault' `
        ($row.found -and $row.status -eq 'WARN' -and $row.detail -match '(?i)not established' -and
         $row.detail -notmatch 'check threw' -and $r.out -notmatch 're-copy it') `
        "expected a WARN saying provenance was not established, with no remedy anywhere in the report; got [$($row.status)] $($row.detail). Full output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 15b. THE TERMINAL THE OPERATOR HAPPENED TO LAUNCH FROM MUST NOT DECIDE
    #      THE VERDICT (#273).
    #
    #      Claude Code hands every hook and every command the environment it was
    #      started with. Start it from a PowerShell 7 prompt - the Windows
    #      Terminal default on any machine that has pwsh installed - and every
    #      `powershell` this plugin spawns is a Windows PowerShell 5.1 child
    #      carrying PS7's PSModulePath. 5.1 then resolves
    #      Microsoft.PowerShell.Utility to PS7's 7.0.0.0 manifest ahead of its
    #      own 3.1.0.0, and Get-FileHash - a FUNCTION in 5.1's module, not a
    #      compiled cmdlet - is gone. ConvertFrom-Json survives, so nothing else
    #      in this file notices.
    #
    #      This case is the sl-real-install control (case 12) run once more with
    #      Get-FileHash removed, so the two together say that one command is the
    #      only difference. The tree is a CORRECT install: the repo copy, byte
    #      for byte, wired as the status line.
    #
    #      BASELINE 6aebcd6: '[FAIL] statusline  check threw: The term
    #      'Get-FileHash' is not recognized as the name of a cmdlet, function,
    #      script file, or operable program...' and the report's own
    #      VERDICT: NOT healthy. A correct install, called broken, because of
    #      the terminal. Measured by hand on the same day under a REAL
    #      PowerShell 7 module path - and through the real slash command, where
    #      the model reported "NOT healthy" to the operator, correctly following
    #      commands\doctor.md.
    #
    #      WHAT THIS CASE DOES NOT ESTABLISH: nothing here runs PowerShell 7 or
    #      reproduces its PSModulePath. New-NoFileHashRunner's header records
    #      why - four synthetic module shapes were tried and none of them
    #      shadowed - and records that the causation was measured by hand.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'sl-no-filehash'
    $installed = Join-Path $t.profile '.claude\statusline.ps1'
    [IO.File]::Copy($PlugStatusLine, $installed, $true)
    [void](Set-CaseSettings -ProfileDir $t.profile -Command (New-StatusLineCommand $installed))
    $runner = New-NoFileHashRunner -Path (Join-Path $t.dir 'run-doctor.ps1') -Target $script:DoctorPath
    $r   = Invoke-Doctor -ProfileDir $t.profile -StateDir $t.state -DoctorPath $runner
    $row = Get-DoctorRow -Text $r.out -Id 'statusline'
    Add-Result 'a correct install still attests a match when Get-FileHash cannot be resolved' `
        ($row.found -and $row.status -eq 'PASS' -and $row.detail -match 'matches the repo copy' -and
         $r.out -notmatch 'Get-FileHash') `
        "expected PASS attesting the match with no mention of Get-FileHash anywhere in the report; got [$($row.status)] $($row.detail). Full output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 15c. TWO STATE DIRECTORIES, AND THE REPORT CALLED THE MACHINE HEALTHY
    #      WITH NO OVERRIDE WHILE A GATE WAS ARMED IN THE ONE IT DID NOT READ
    #      (#270).
    #
    #      Claude Code hands every HOOK $CLAUDE_PLUGIN_DATA and hands a COMMAND
    #      - which runs through Bash(powershell:*) - nothing, so a command
    #      discovers its state directory by ranking `<name>*` directories on the
    #      newest write anywhere inside them. An operator who has run this plugin
    #      from a checkout (--plugin-dir writes lw-watchtower-inline) as well as
    #      from the marketplace has two of them, and from then on the answer
    #      moves with whichever was written last.
    #
    #      THIS CASE IS THE DOCTOR'S HALF OF THAT ISSUE and nothing else. Making
    #      a command and a hook resolve the SAME directory is unachievable by
    #      construction and is not attempted: a command is never handed the
    #      variable and is never told what the CLI chose. What is fixable is the
    #      claim.
    #
    #      EVERY OTHER CHECK IS SEEDED TO PASS, deliberately, so the verdict
    #      assertion is about this row and not about a scratch tree. The
    #      SessionStart record goes into BOTH candidates, because which one the
    #      resolver picks is the whole subject and a record in only one would
    #      make check 6 flap with it.
    #
    #      BASELINE 6aebcd6 and 8f1b0c0, measured by hand on 2026-09-04 and
    #      reported on the issue by UAT pass 3:
    #
    #        [PASS] state-dir  ...\lw-watchtower-inline (source 'discovered', 2 candidate(s)); write probe succeeded
    #        resolved for repo: (not in a repo)   config: config.json   override: none - these are the shipped defaults
    #        VERDICT: healthy - no check failed and none raised a caveat
    #
    #      over {"interaction":{"delegate":true}} sitting in the other one.
    #
    #      THREE ASSERTIONS, AND THE THIRD IS THE ONE THAT COSTS MOST TO GET
    #      WRONG. A row that stopped saying PASS but left the footer asserting
    #      "override: none - these are the shipped defaults" would still tell
    #      the operator the lie that matters: the gate is off. So the footer
    #      line is asserted separately from the row.
    # -------------------------------------------------------------------
    $t = New-CaseTree -Tag 'state-split'
    $dataRoot = Join-Path $t.profile '.claude\plugins\data'
    $dirA = Join-Path $dataRoot 'lw-watchtower-lwg-fixture-marketplace'
    $dirB = Join-Path $dataRoot 'lw-watchtower-inline'
    $rec  = [ordered]@{
        event     = 'SessionStart'
        ts        = (Get-Date).ToUniversalTime().ToString('o')
        mode      = 'lwg-doctor-behaviour-fixture'
        selfcheck = [ordered]@{ ran = $true; ok = $true }
    }
    foreach ($d in @($dirA, $dirB)) {
        [void][IO.Directory]::CreateDirectory($d)
        [IO.File]::WriteAllText((Join-Path $d $LogLeaf),
            ((ConvertTo-Json -InputObject ([pscustomobject]$rec) -Depth 10 -Compress) + "`r`n"),
            (New-Object Text.UTF8Encoding($false)))
    }
    # The override lands in ONE of them, and in the one the mtime ranking is
    # least likely to pick, so a run that reported "override: none" would be
    # reporting it about a directory that has one two inches away.
    [IO.File]::WriteAllText((Join-Path $dirA 'config.override.json'),
        '{"interaction":{"delegate":true}}' + "`r`n", (New-Object Text.UTF8Encoding($false)))
    $installed = Join-Path $t.profile '.claude\statusline.ps1'
    [IO.File]::Copy($PlugStatusLine, $installed, $true)
    [void](Set-CaseSettings -ProfileDir $t.profile -Command (New-StatusLineCommand $installed))
    # -StateDir '' is what puts this on the DISCOVERY branch: every other case
    # in this file runs with CLAUDE_PLUGIN_DATA set, which is a hook's
    # environment and the one branch on which this cannot happen.
    $r   = Invoke-Doctor -ProfileDir $t.profile -StateDir ''
    $row = Get-DoctorRow -Text $r.out -Id 'state-dir'
    Add-Result 'two state directories are not reported as a PASS, and both are named' `
        ($row.found -and $row.status -ne 'PASS' -and
         $r.out -match [regex]::Escape($dirA) -and $r.out -match [regex]::Escape($dirB)) `
        "expected a non-PASS state-dir row naming both candidates; got [$($row.status)] $($row.detail). Full output:`n$($r.out)"
    Add-Result 'the roster stops reporting an absent override it only looked for in one directory' `
        ($r.out -notmatch 'override: none - these are the shipped defaults') `
        "the footer asserted the shipped defaults over a config.override.json in $dirA, which is what tells an operator an armed gate is off. Full output:`n$($r.out)"
    Add-Result 'a split state directory costs the run its healthy verdict' `
        ($r.out -notmatch '(?m)^VERDICT: healthy') `
        "expected the verdict to carry the caveat; every other check in this tree is seeded to pass, so this is the row that has to move it. Full output:`n$($r.out)"

    # -------------------------------------------------------------------
    # 16-18. THE INFORMATIONAL ROSTER AT THE FOOT, AND THE THING IT MUST NOT
    #        TOUCH.
    #
    #        bin\lwg-status.ps1 was a report command with no other job; it is
    #        deleted, and the one thing it printed that the doctor did not - a
    #        paragraph per gate and a per-module ON/OFF listing - moved to the
    #        foot of bin\lwg-doctor.ps1. THE RISK THE MOVE CREATES IS THE ONLY
    #        REASON THESE CASES EXIST: a report merged into a diagnosis is one
    #        edit away from becoming part of the diagnosis. An OFF gate is the
    #        SHIPPED state of all three gates this plugin has, so a roster that
    #        leaked into the verdict would turn a correct default install into
    #        "NOT healthy" - the false alarm this repository exists to prevent,
    #        pointing the other way.
    #
    #        WHY THE ASSERTIONS ARE SHAPED THE WAY THEY ARE, since the obvious
    #        shape is wrong. "The doctor still exits 0" cannot be used: the copy
    #        this suite drives is the checkout, its commands check scans the
    #        whole tree, and the moment any tracked file references a command
    #        whose markdown is gone that check FAILS for reasons that have
    #        nothing to do with this block. So case 17 DERIVES the expected code
    #        from the RESULT tally the doctor printed - a tally computed above
    #        the roster, from rows the roster cannot add to - and asserts the
    #        process agreed with it. That holds at exit 0, 1 and 2 alike, and it
    #        goes red exactly when the roster starts moving the verdict.
    #
    #        BASELINE: there is no fd8d023 baseline for these three. The block
    #        did not exist there and neither did the command it came from in its
    #        current shape; what they pin is the boundary the move must keep,
    #        and the red proof for that boundary is a mutation rather than an
    #        old commit. Case 17 records both mutations, what each case actually
    #        reported under them, and the one mutation shape neither reaches.
    # -------------------------------------------------------------------

    # -------------------------------------------------------------------
    # 16. IT RENDERS, IT RENDERS AFTER THE VERDICT LINE, AND IT ADDS NO ROW.
    #
    #     Four facts, and the last is the one with teeth. The doctor's header
    #     counts CHECKS, Get-DoctorRow and the CI log both key on the
    #     `  [PASS] id  detail` row shape, and this suite's other fifteen cases
    #     read rows by that pattern - so a roster line that happened to be
    #     shaped like a row would be read as a tenth check by every one of them.
    #     The count of row-shaped lines is therefore asserted against the number
    #     in the header rather than against a literal 9, which keeps this case
    #     true when a tenth check is written on purpose and false when the
    #     roster grows one by accident.
    # -------------------------------------------------------------------
    Set-CaseConfig -Mutate $null
    $t = New-HealthyCase -Tag 'roster-render' -RepoStatusLine $PlugStatusLine -LogLeaf $LogLeaf
    $rr = Invoke-Doctor -ProfileDir $t.profile -StateDir $t.state

    $hdr        = [regex]::Match($rr.out, '(?m)^LW-WATCHTOWER doctor - (\d+) checks')
    $rowLines   = @([regex]::Matches($rr.out, '(?m)^\s+\[(?:PASS|INFO|WARN|FAIL)\]\s+\S+'))
    $iResult    = $rr.out.IndexOf('RESULT:')
    $iRoster    = $rr.out.IndexOf('WHAT IS SWITCHED ON')
    $gateBlock  = ($rr.out -match '(?m)^\s+GATES\s*$' -and
                   $rr.out -match '(?m)^\s+delegate_gate\s+(LIVE|OFF)' -and
                   $rr.out -match '(?m)^\s+switch  :' -and
                   $rr.out -match '(?m)^\s+in file :' -and
                   $rr.out -match '(?m)^\s+resolved:' -and
                   $rr.out -match '(?m)^\s+code    :')
    $modTable   = ($rr.out -match '(?m)^\s+MODULE\s+KIND\s+BUILT\s+ENABLED\s+STATE' -and
                   $rr.out -match '(?m)^\s+delegate_gate\s+gate\s+')
    $counts     = ($rr.out -match '(?m)^\s+\d+ gate\(s\) SHIPPED:' -and $rr.out -match '(?m)^\s+\d+ gate\(s\) LIVE:')
    $rowsMatchHeader = ($hdr.Success -and $rowLines.Count -eq [int]$hdr.Groups[1].Value)

    Add-Result 'the informational roster renders below RESULT: and adds no check row' `
        ($hdr.Success -and $rowsMatchHeader -and $iRoster -gt 0 -and $iResult -gt 0 -and
         $iRoster -gt $iResult -and $counts -and $gateBlock -and $modTable) `
        ("header said $(if ($hdr.Success) { $hdr.Groups[1].Value } else { '<no header>' }) check(s) and " +
         "$($rowLines.Count) row-shaped line(s) were printed; roster at index $iRoster, RESULT: at index $iResult; " +
         "SHIPPED/LIVE counts $(if ($counts) { 'present' } else { 'MISSING' }); " +
         "gate paragraph $(if ($gateBlock) { 'present' } else { 'MISSING' }); " +
         "module table $(if ($modTable) { 'present' } else { 'MISSING' }). Full output:`n$($rr.out)")

    # -------------------------------------------------------------------
    # 16b. THE COVERAGE PARAGRAPH DOES NOT CLAIM A COVERAGE GAP THAT tests\
    #      CONTRADICTS - #253.
    #
    #      The doctor closes EVERY run, green ones included, with a paragraph
    #      about what the suites reach. Its last sentence read "The other ONE -
    #      self_health - is exercised by nothing, anywhere" while
    #      tests\state_resolution.ps1 had three sections written against it.
    #      That is a false claim about coverage, printed
    #      on the widest-read surface this plugin has, by the component whose
    #      job is to catch stale claims.
    #
    #      IT HAD GONE STALE ONCE BEFORE, in the same direction: the same
    #      sentence said SEVEN modules were exercised by nothing until
    #      3 August 2026 and ten tracked files went on saying seven while every
    #      suite stayed green. tests\doc_claims.ps1's own comment on
    #      observing-module-count records that and says why no rule there
    #      derives which modules a suite exercises - it would mean parsing
    #      assertions to decide what they are about. This case does not derive
    #      that either. It asserts the two things that CAN be checked without
    #      inventing that mechanism, and the second is the one with teeth.
    #
    #      1. The negative: the paragraph must not carry the "exercised by
    #         nothing" clause. On its own this is a string pin and would be
    #         satisfied by deleting the sentence, which is why it is not alone.
    #      2. The positive: wherever the paragraph names self_health it must
    #         name a suite beside it, spelled tests\<name>.ps1, AND THAT FILE
    #         MUST EXIST ON DISK beside this one. A rewrite that credits a suite
    #         that is not there fails, and so does one that quietly drops
    #         self_health from the paragraph to get past (1).
    #
    #      RED AT 09b20be on both halves: the clause is present, and the
    #      paragraph names no suite for self_health at all. 37 of 38, this case
    #      the only failure.
    # -------------------------------------------------------------------
    $covFalse   = ($rr.out -match 'exercised by nothing')
    $covSuite   = [regex]::Match($rr.out, 'self_health\s*\(\s*(tests\\[A-Za-z0-9_.-]+\.ps1)')
    $covPath    = if ($covSuite.Success) { Join-Path (Split-Path -Parent $PSScriptRoot) ($covSuite.Groups[1].Value) } else { '' }
    $covExists  = ($covSuite.Success -and [IO.File]::Exists($covPath))

    Add-Result 'the coverage paragraph names a real suite for self_health rather than claiming nothing exercises it (#253)' `
        ((-not $covFalse) -and $covExists) `
        ("the 'exercised by nothing' clause is $(if ($covFalse) { 'STILL PRESENT' } else { 'gone' }); " +
         "the paragraph names $(if ($covSuite.Success) { "'" + $covSuite.Groups[1].Value + "'" } else { 'NO SUITE AT ALL' }) beside self_health, " +
         "and that file $(if ($covExists) { 'exists' } else { 'DOES NOT EXIST' }) at [$covPath]. " +
         "A health command that understates its own coverage is still printing something untrue on every run, " +
         "and this paragraph has now gone stale twice in that direction. Full output:`n$($rr.out)")

    # -------------------------------------------------------------------
    # 17. THE EXIT CODE IS THE ONE THE TALLY IMPLIES, WITH THE ROSTER PRINTED.
    #
    #     3 beats 1 beats 2 beats 0 is the doctor's own contract; the roster is
    #     not in it. This reads the RESULT: line the doctor printed, derives the
    #     code that line demands, and requires the process to have exited on it
    #     while the roster was on screen. It asserts NOTHING about which code
    #     that is, so it survives the commands check going red on a tree whose
    #     docs are mid-reconciliation.
    #
    #     RED PROOF, AND IT IS A MUTATION RATHER THAN A COMMIT. Both mutations
    #     below were applied to bin\lwg-doctor.ps1, run, and reverted against a
    #     checksum before this file was kept. What each reported is quoted,
    #     because "it would go red" is a prediction and this repository has
    #     already been bitten by one written as a fact.
    #
    #       exit 2 as the last statement inside the roster's try
    #           this case went RED: "the doctor printed 'RESULT: 8 passed,
    #           0 warning(s), 1 failure(s)', which demands exit 1, and the
    #           process exited 2 with the roster printed". Case 3 caught it too,
    #           which is worth knowing rather than hiding - it is not the only
    #           net under an exit-code change. CASE 18 STAYED GREEN, correctly:
    #           both its runs exited 2, so a code moved identically in both is
    #           invisible to a case that compares them.
    #       a Write-Output '  [WARN] roster  leaked' inside the roster
    #           CASE 16 went red, this one did not: "header said 9 check(s) and
    #           10 row-shaped line(s) were printed". A line that only LOOKS like
    #           a row cannot move an exit code, and case 16 is the one that sees
    #           it - which is why the pair is kept rather than either alone.
    #
    #     WHAT NEITHER MUTATION REACHES, said plainly: an `Add-Row` inside the
    #     roster is INERT and would leave every case here green. $fails, $warns
    #     and $pass are snapshotted, the rows printed, and the verdict decided
    #     ABOVE the roster, so a row appended below changes nothing observable.
    #     That is a property of the ordering rather than of these cases, and if
    #     the roster is ever moved above the report it stops holding.
    # -------------------------------------------------------------------
    $tally = [regex]::Match($rr.out, '(?m)^RESULT: (\d+) passed, (\d+) warning\(s\), (\d+) failure\(s\)')
    $want  = -1
    if ($tally.Success) {
        $want = if ([int]$tally.Groups[3].Value -gt 0) { 1 }
                elseif ([int]$tally.Groups[2].Value -gt 0) { 2 }
                else { 0 }
    }
    Add-Result 'the roster does not move the exit code: it is still the one the tally implies' `
        ($tally.Success -and $iRoster -gt 0 -and $rr.code -eq $want) `
        ("the doctor printed '$(if ($tally.Success) { $tally.Value } else { '<no RESULT: line>' })', which demands " +
         "exit $want, and the process exited $($rr.code) with the roster $(if ($iRoster -gt 0) { 'printed' } else { 'ABSENT - so nothing about it was established' }). " +
         "Full output:`n$($rr.out)")

    # -------------------------------------------------------------------
    # 18. -Quiet DROPS THE MODULE TABLE AND KEEPS THE GATES.
    #
    #     The PR template runs the doctor with -Quiet, so the quiet path is the
    #     one a reviewer actually sees. A gate that can refuse a tool call is
    #     not noise at any verbosity and must survive; a thirteen-row inventory
    #     of observers is, and must not. The exit code is asserted identical to
    #     the loud run over the SAME sandbox, which is the -Quiet contract the
    #     script's own param block states: quiet changes what is shown, never
    #     what is judged.
    # -------------------------------------------------------------------
    $rq = Invoke-Doctor -ProfileDir $t.profile -StateDir $t.state -QuietRun
    $qGates = ($rq.out -match '(?m)^\s+GATES\s*$' -and $rq.out -match '(?m)^\s+delegate_gate\s+(LIVE|OFF)')
    $qTable = ($rq.out -match '(?m)^\s+MODULE\s+KIND\s+BUILT\s+ENABLED\s+STATE')
    Add-Result '-Quiet keeps the gate paragraphs, drops the module table, and changes no code' `
        ($qGates -and -not $qTable -and $rq.code -eq $rr.code) `
        ("with -Quiet the gate paragraphs were $(if ($qGates) { 'kept' } else { 'DROPPED - a live gate can now go unreported at the verbosity the PR template uses' }) " +
         "and the module table was $(if ($qTable) { 'STILL PRINTED' } else { 'dropped' }); " +
         "exit was $($rq.code) against $($rr.code) for the same sandbox without -Quiet. Full output:`n$($rq.out)")

    # -------------------------------------------------------------------
    # 19-21. #42. THE READ WINDOW IS A BOUND ON THE READ, NOT EVIDENCE OF
    #        ABSENCE.
    #
    #        Check 6 read at most the last 256 KB of the event log and, finding
    #        no SessionStart in it, reported "the hook is not firing" and failed
    #        the run. "I could not look far enough back" and "the hook is not
    #        firing" are different statements, and bin\lwg-doctor.ps1's own
    #        header argues that distinction for the exit codes - "'I found a
    #        fault' and 'I could not look' are different statements, and
    #        collapsing them would let a crashed doctor be read as a diagnosis".
    #        The three cases below are the three answers that distinction
    #        requires, and only the middle one is a fault.
    #
    #        THE OTHER SHAPE IN THE ISSUE IS NOT COVERED AND CANNOT OCCUR.
    #        #42 also describes a SessionStart inside the window that is not the
    #        newest on disk. Everything inside a tail window is newer than
    #        everything outside it, so the record the loop keeps is always the
    #        last one in the file - there is no case to write.
    # -------------------------------------------------------------------

    # -------------------------------------------------------------------
    # 19. A SessionStart PUSHED OUT OF THE 256 KB TAIL IS STILL THERE.
    #
    #     The sandbox is a HEALTHY one - the hook fired, the self-check ran and
    #     passed, the record is minutes old - and then 300 KB of ordinary
    #     records are appended after it, which is one long session or one
    #     regression run. Nothing about the install changed.
    #
    #     BASELINE fd8d023 (and every commit up to this one):
    #       [FAIL] sessionstart  event log exists but holds no SessionStart
    #                            record - the hook is not firing
    #     and VERDICT: NOT healthy, exit 1, on a machine where the hook is
    #     firing correctly. That is the defect.
    # -------------------------------------------------------------------
    $t = New-HealthyCase -Tag 'ss-past-window' -RepoStatusLine $PlugStatusLine -LogLeaf $LogLeaf
    $ssLog = Join-Path $t.state $LogLeaf
    $ssLen = Add-LogFiller -Path $ssLog -MinBytes 300000
    $ss    = Invoke-Doctor -ProfileDir $t.profile -StateDir $t.state
    $row   = Get-DoctorRow -Text $ss.out -Id 'sessionstart'
    Add-Result 'a SessionStart older than the 256 KB tail is not reported as a hook that is not firing' `
        ($row.found -and $row.status -eq 'PASS' -and $ss.code -eq 0) `
        ("the log is $ssLen bytes and its ONE SessionStart record is the first line, so it sits outside a 256 KB tail; " +
         "expected [PASS] and exit 0, got [$($row.status)] $($row.detail) at exit $($ss.code). Full output:`n$($ss.out)")

    # -------------------------------------------------------------------
    # 20. CONTROL, and it passes at fd8d023 too. A LOG THIS CHECK READ IN FULL
    #     AND FOUND NOTHING IN IS STILL A FAULT.
    #
    #     The cheapest way to pass case 19 is to stop failing, and this is what
    #     stops that: a log SHORTER than the window, read end to end, holding no
    #     SessionStart. Absence was established here, so the fault claim is
    #     earned and the wording an operator acts on must survive.
    # -------------------------------------------------------------------
    $t = New-HealthyCase -Tag 'ss-whole-file-miss' -RepoStatusLine $PlugStatusLine -LogLeaf $LogLeaf
    $ssLog = Join-Path $t.state $LogLeaf
    [IO.File]::WriteAllText($ssLog, '', (New-Object Text.UTF8Encoding($false)))
    $ssLen = Add-LogFiller -Path $ssLog -MinBytes 40000
    $ss    = Invoke-Doctor -ProfileDir $t.profile -StateDir $t.state
    $row   = Get-DoctorRow -Text $ss.out -Id 'sessionstart'
    Add-Result 'CONTROL sessionstart: a log read in full with no SessionStart in it is still a FAIL' `
        ($row.found -and $row.status -eq 'FAIL' -and $row.detail -match 'not firing' -and $ss.code -eq 1) `
        ("the log is $ssLen bytes, well inside the window, so the whole file was read and the absence IS established; " +
         "expected a [FAIL] naming the hook and exit 1, got [$($row.status)] $($row.detail) at exit $($ss.code). Full output:`n$($ss.out)")

    # -------------------------------------------------------------------
    # 21. A LOG TOO LARGE TO READ IN FULL, WITH NO SessionStart FOUND, IS "I
    #     COULD NOT LOOK" AND NOT "IT IS NOT FIRING".
    #
    #     9 MB is past the widest read check 6 will make, so the check reaches
    #     the end of what it is willing to read without an answer. That is the
    #     third state, and the row has to say which of the two it is: WARN, with
    #     a detail that says the check could not look far enough back, and NOT a
    #     FAIL that sends an operator to reinstall a working plugin.
    #
    #     THE SIZE IS DELIBERATELY ABOVE THE ROTATION THRESHOLD. Invoke-LwgLogRotate
    #     caps the live log at 5 MB, so a file this big means rotation is not
    #     running either - which is a real thing to find out, and still not a
    #     statement about the SessionStart hook.
    #
    #     BASELINE fd8d023: [FAIL] ... the hook is not firing, exit 1.
    # -------------------------------------------------------------------
    $t = New-HealthyCase -Tag 'ss-past-widest' -RepoStatusLine $PlugStatusLine -LogLeaf $LogLeaf
    $ssLog = Join-Path $t.state $LogLeaf
    [IO.File]::WriteAllText($ssLog, '', (New-Object Text.UTF8Encoding($false)))
    $ssLen = Add-LogFiller -Path $ssLog -MinBytes 9437184
    $ss    = Invoke-Doctor -ProfileDir $t.profile -StateDir $t.state
    $row   = Get-DoctorRow -Text $ss.out -Id 'sessionstart'
    Add-Result 'a log too large to read in full is reported as unread, not as a hook that is not firing' `
        ($row.found -and $row.status -eq 'WARN' -and $row.detail -match 'far enough back' -and $row.detail -notmatch 'the hook is not firing') `
        ("the log is $ssLen bytes with no SessionStart anywhere in it, which is past what this check reads, so nothing here established absence; " +
         "expected a [WARN] saying it could not look far enough back, got [$($row.status)] $($row.detail) at exit $($ss.code). Full output:`n$($ss.out)")

    # -------------------------------------------------------------------
    # 22-24. #204. THE commands CHECK ENUMERATES THE TRACKED TREE, AND SAYS SO.
    #
    #        The check walked the filesystem under the plugin root with two name
    #        filters and scanned everything else, tracked or not. So its verdict
    #        moved with whatever happened to be lying in the checkout: an
    #        untracked directory of generated output carrying references to six
    #        commands deleted on 2 September 2026 produced
    #
    #          [FAIL] commands  <plugin>:status is referenced in
    #                           scratch-out\notes.md but commands\status.md does
    #                           not exist; <plugin>:tripped is referenced
    #                           in scratch-out\notes.md but commands\tripped.md
    #                           does not exist
    #
    #        THE TWO NAMES ARE WRITTEN WITHOUT THEIR LEADING SLASH ABOVE AND
    #        EVERYWHERE ELSE IN THIS FILE. The check under test scans .ps1 files
    #        and this is one of them, so a live-looking reference in a comment
    #        fails the check on its own explanation - which is exactly what
    #        happened on the first run of these cases, and the doctor's own
    #        comment on this check warns about it for the same reason. The
    #        fixture builds its references at run time from the manifest's
    #        plugin id instead.
    #
    #        from a checkout whose `git status --short` listed nothing but that
    #        untracked directory. That is a false FAIL over a directory that is
    #        no part of the plugin, and a false FAIL is the expensive direction:
    #        it teaches an operator to ignore the doctor.
    #
    #        THE THREE CASES ARE THE THREE STATES, and the third is the one that
    #        stops the fix being worse than the defect. A marketplace install has
    #        no .git, `git ls-files` exits 128 there and enumerates nothing, and
    #        "scanned 0 files" must never become a silent pass - so the fallback
    #        has to be real, and a tracked tree with nothing in it has to keep
    #        failing.
    #
    #        EACH CASE BUILDS ITS OWN COPY OF THE PLUGIN TREE. The shared copy
    #        every other case drives is made by Copy-PluginTree, which drops
    #        .git, so it is the no-git shape by construction and a plant left in
    #        it would follow every later case.
    # -------------------------------------------------------------------

    # -------------------------------------------------------------------
    # 22. AN UNTRACKED OFFENDER IN A TRACKED TREE IS NOT THE PLUGIN'S PROBLEM.
    #
    #     The copy is git init'd and everything in it added, THEN the offender
    #     is planted - so the tracked tree is clean and the working directory is
    #     not, which is the exact state that reproduced this. The row must PASS
    #     and must name the enumeration it used, because a reader who cannot
    #     tell which tree was measured cannot tell a real clean sweep from a
    #     scan that quietly read nothing.
    #
    #     BASELINE: the tree this landed on. Run against it, this case reports
    #     '[FAIL] <plugin>:status is referenced in generated-output\notes.md
    #     but commands\status.md does not exist; ...' - the defect, reproduced
    #     inside the suite.
    # -------------------------------------------------------------------
    Set-CaseConfig -Mutate $null
    $c204   = New-PluginCopy -Tag 'cmd-tracked' -From $Root
    $nTrack = Initialize-TrackedCopy -Root $c204.root
    $plant  = Add-UntrackedOffender -Root $c204.root -PluginName $PluginName
    $t      = New-HealthyCase -Tag 'cmd-tracked-case' -RepoStatusLine $PlugStatusLine -LogLeaf $LogLeaf
    $cr     = Invoke-Doctor -ProfileDir $t.profile -StateDir $t.state -DoctorPath $c204.doctor
    $row    = Get-DoctorRow -Text $cr.out -Id 'commands'
    Add-Result 'commands: an untracked file referencing commands that do not exist does not fail a clean tracked tree' `
        ($nTrack -gt 0 -and $row.found -and $row.status -eq 'PASS' -and $row.detail -match 'tracked tree') `
        ("git listed $nTrack tracked file(s) in the copy and $plant was planted untracked afterwards; " +
         "expected a [PASS] whose detail names the tracked tree, got [$($row.status)] $($row.detail). " +
         $(if ($nTrack -le 0) { 'THE FIXTURE WAS NOT BUILT - git could not init or add, so this case established nothing. ' } else { '' }) +
         "Full output:`n$($cr.out)")

    # -------------------------------------------------------------------
    # 23. CONTROL. THE SAME OFFENDER, IN A TREE WITH NO .git, STILL FAILS.
    #
    #     The cheapest way to pass case 22 is to stop reading the offending file
    #     at all, and this is what stops that. A marketplace install has no
    #     index; the walk is then the only enumeration there is, and it must
    #     still find a signpost to a command that does not exist. The detail has
    #     to say it was the filesystem, so the operator reading a FAIL knows
    #     that an untracked file could be the cause of it.
    #
    #     BASELINE: passes on the tree this landed on too, apart from the
    #     enumeration phrase - the walk is what that tree always did.
    # -------------------------------------------------------------------
    $c204b = New-PluginCopy -Tag 'cmd-nogit' -From $Root
    $plant = Add-UntrackedOffender -Root $c204b.root -PluginName $PluginName
    $t     = New-HealthyCase -Tag 'cmd-nogit-case' -RepoStatusLine $PlugStatusLine -LogLeaf $LogLeaf
    $cr    = Invoke-Doctor -ProfileDir $t.profile -StateDir $t.state -DoctorPath $c204b.doctor
    $row   = Get-DoctorRow -Text $cr.out -Id 'commands'
    $hasGit = [IO.Directory]::Exists((Join-Path $c204b.root '.git'))
    Add-Result 'CONTROL commands: with no tracked tree to read, the filesystem walk still finds the bad reference' `
        (-not $hasGit -and $row.found -and $row.status -eq 'FAIL' -and
         $row.detail -match 'tripped' -and $row.detail -match 'filesystem') `
        ("the copy has no .git ($(if ($hasGit) { 'IT DOES - the fixture is wrong' } else { 'confirmed' })) and $plant references two commands that do not exist; " +
         "expected a [FAIL] naming them and saying it enumerated the filesystem, got [$($row.status)] $($row.detail). Full output:`n$($cr.out)")

    # -------------------------------------------------------------------
    # 24. CONTROL. A TRACKED TREE THAT MENTIONS NO COMMAND AT ALL IS A BROKEN
    #     SCAN, NOT A CLEAN ONE.
    #
    #     git answers, exit 0, and lists ONE file that carries no /<plugin>:*
    #     reference - which is also the shape of a plugin unpacked inside some
    #     other repository, where every one of its files is untracked. Zero
    #     references means the scan proved nothing, and the row has to say that
    #     rather than report a clean command surface. Without this case the fix
    #     for #204 could pass every tree by finding nothing in it.
    #
    #     BASELINE: no fd8d023 baseline - the tracked path did not exist there.
    #     Its red is the mutation of deleting the $refs.Count guard, which is
    #     the guard this case exists to hold.
    # -------------------------------------------------------------------
    $c204c = New-PluginCopy -Tag 'cmd-empty' -From $Root
    [IO.File]::WriteAllText((Join-Path $c204c.root 'nothing-to-see.md'),
        "a tracked file that mentions no command`r`n", (New-Object Text.UTF8Encoding($false)))
    $nOnly = Initialize-TrackedCopy -Root $c204c.root -Only @('nothing-to-see.md')
    $t     = New-HealthyCase -Tag 'cmd-empty-case' -RepoStatusLine $PlugStatusLine -LogLeaf $LogLeaf
    $cr    = Invoke-Doctor -ProfileDir $t.profile -StateDir $t.state -DoctorPath $c204c.doctor
    $row   = Get-DoctorRow -Text $cr.out -Id 'commands'
    Add-Result 'CONTROL commands: a tracked tree holding no command reference at all FAILS as a broken scan' `
        ($nOnly -eq 1 -and $row.found -and $row.status -eq 'FAIL' -and
         $row.detail -match 'proved nothing' -and $row.detail -match 'tracked tree') `
        ("git listed $nOnly tracked file(s), none of which names a command; " +
         "expected a [FAIL] saying the scan proved nothing and naming the tracked tree, got [$($row.status)] $($row.detail). " +
         $(if ($nOnly -ne 1) { 'THE FIXTURE WAS NOT BUILT as one tracked file, so this case established nothing. ' } else { '' }) +
         "Full output:`n$($cr.out)")

    # -------------------------------------------------------------------
    # 25. #205. THE DOCTOR RUNS EXACTLY THESE CHECKS, BY NAME.
    #
    #     The one case above that reads the header compares it against the rows
    #     the same run printed, and both come from $script:Rows - so they agree
    #     at any count, and a check deleted by an edit, a bad merge or a
    #     refactor left every suite in this repository green. That was proved by
    #     mutation, not argued: a doctor with a whole Invoke-Check block removed
    #     reported 19 of 19, exit 0.
    #
    #     This is the other end. $script:ExpectedCheckIds is a literal list, and
    #     the reasoning for a SET rather than a count is written above it.
    #
    #     THE ABORT PATH IS ASSERTED, NOT ASSUMED. On exit 3 the doctor prints a
    #     FRAGMENT of a checkup, and a fragment is missing ids for a reason that
    #     is not a deleted check. A case that compared the sets anyway would go
    #     red with the wrong message, so the abort is read first and named.
    #
    #     IT DOES NOT LOOK AT STATUS. Two of the eight FAIL on any machine where
    #     the plugin is not installed under ~\.claude\plugins\data, which is a
    #     property of the machine and not a defect; the sandbox here seeds both
    #     of them green anyway. What is pinned is which checks RAN, and that is
    #     true at PASS, WARN and FAIL alike.
    #
    #     RED PROOF, A MUTATION, RUN WHOLE AND QUOTED RATHER THAN PREDICTED.
    #     Both were applied to a scratch copy of the tree, run with -Root at it,
    #     and the copy thrown away.
    #
    #       the marketplace Invoke-Check block deleted
    #           BEFORE this case existed: 25 of 25, exit 0, over a doctor with
    #           seven checks - the hole, reproduced.
    #           AFTER: this case RED - "missing: marketplace; unexpected: none;
    #           the doctor printed 7 distinct row id(s)". No other case moved.
    #       Add-Row -Id 'phantom' -Status 'PASS' appended to that block
    #           AFTER: this case RED - "missing: none; unexpected: phantom; the
    #           doctor printed 9 distinct row id(s)". Case 16 stayed GREEN: the
    #           row is real, so the header counts it and the two still agree.
    #           That is the pair - 16 sees a line that only LOOKS like a row,
    #           this one sees a row that should not be there.
    # -------------------------------------------------------------------
    Set-CaseConfig -Mutate $null
    $t  = New-HealthyCase -Tag 'check-surface' -RepoStatusLine $PlugStatusLine -LogLeaf $LogLeaf
    $cs = Invoke-Doctor -ProfileDir $t.profile -StateDir $t.state
    $ids        = @((Get-RowMap -Text $cs.out).Keys)
    $aborted    = ($cs.code -eq 3 -or $cs.out -match '(?m)^ABORTED:')
    $missing    = @($script:ExpectedCheckIds | Where-Object { $ids -notcontains $_ })
    $unexpected = @($ids | Where-Object { $script:ExpectedCheckIds -notcontains $_ })
    Add-Result 'the doctor runs exactly the check ids this suite names - none missing, none unexpected' `
        (-not $aborted -and $missing.Count -eq 0 -and $unexpected.Count -eq 0) `
        ("missing: $(if ($missing.Count) { $missing -join ', ' } else { 'none' }); " +
         "unexpected: $(if ($unexpected.Count) { $unexpected -join ', ' } else { 'none' }); " +
         "the doctor printed $($ids.Count) distinct row id(s): $($ids -join ', ')" +
         $(if ($aborted) { '. THE DOCTOR ABORTED - the report is a fragment of a checkup, so the missing ids above are not evidence that any check was deleted' } else { '' }) +
         ". Full output:`n$($cs.out)")

    # -------------------------------------------------------------------
    # 25b. #118. NO marketplace.json BESIDE THE PLUGIN ROOT IS THE CORRECT
    #      STATE, AND IT MUST NOT COST THE OPERATOR AN EXIT CODE.
    #
    #      Before the payload restructure `"source": "./"` shipped the whole
    #      repository, so .claude-plugin\marketplace.json sat beside the plugin
    #      root on every route and this row was PASS everywhere. The payload is
    #      now lw-watchtower/ and marketplace.json stays at the MARKETPLACE root
    #      - one directory above the plugin on the dev route, and not copied at
    #      all on the cache route. Its absence is therefore the designed
    #      arrangement on every healthy install that exists.
    #
    #      WHAT THIS CASE IS ACTUALLY PROTECTING. The row used to fire WARN, and
    #      a WARN is counted into the caveat tally, which is `VERDICT: working,
    #      with N caveat(s)` and EXIT 2. Left alone, the restructure would have
    #      turned /lw-watchtower:doctor from exit 0 to exit 2 on every machine,
    #      permanently, for a fault no install has - the "reports a fault it
    #      does not have" failure, which is the same defect as reporting health
    #      it cannot see and is the one this command is named for.
    #
    #      SO THE ASSERTION IS THREE-PART and each part fails differently:
    #      the row is INFO (not WARN, not FAIL, not a silent PASS over a file
    #      that is not there); its detail says WHY the absence is correct, so an
    #      operator reading the report is not left to guess; and INFO moves
    #      NEITHER the pass tally nor the warning tally, which is what keeps the
    #      verdict arithmetic honest.
    #
    #      THE SANDBOX IS THE PROOF, not a contrivance. Copy-PluginTree copies
    #      $Root, and $Root is the payload root, so the plugin copy this case
    #      drives has exactly the shape a consumer's cache copy has: no
    #      .claude-plugin\marketplace.json anywhere beneath it. Before the
    #      restructure the same copy carried one and this row read PASS.
    #
    #      RED AT a42b169, with only this file's change applied: the sandbox
    #      still held marketplace.json, the row read [PASS], and this case
    #      failed on the status. It is red for the right reason either way -
    #      PASS before the move, WARN if the status is reverted after it.
    # -------------------------------------------------------------------
    $mkRow   = Get-DoctorRow -Text $cs.out -Id 'marketplace'
    $mkTally = [regex]::Match($cs.out, '(?m)^RESULT: (\d+) passed, (\d+) warning\(s\), (\d+) failure\(s\), (\d+) informational')
    $mkOk    = ($mkRow.found -and $mkRow.status -eq 'INFO' -and
                $mkRow.detail -match '(?i)marketplace\.json' -and
                $mkRow.detail -match '(?i)restructure' -and
                $mkTally.Success -and [int]$mkTally.Groups[4].Value -ge 1)
    Add-Result 'no marketplace.json beside the plugin root is INFO, is explained, and is counted as neither a pass nor a caveat' `
        $mkOk `
        ("expected [INFO] on the marketplace row with a detail naming marketplace.json and the restructure, and a RESULT: line whose informational count is at least 1; " +
         "got [$(if ($mkRow.found) { $mkRow.status } else { '<no marketplace row>' })] $(if ($mkRow.found) { $mkRow.detail } else { '' }) " +
         "and RESULT line '$(if ($mkTally.Success) { $mkTally.Value } else { '<no four-term RESULT: line>' })'. " +
         "Full output:`n$($cs.out)")

    # -------------------------------------------------------------------
    # 26-29. #132. THE MACHINE AND THE BUILD.
    #
    #        Nothing in this plugin checked the operating system or the Claude
    #        Code build. Three of the events hooks\hooks.json registers on were
    #        read out of one specific binary; on a build that does not carry
    #        them those registrations are inert, and the failure mode of an
    #        inert hook is SILENCE - indistinguishable from a session in which
    #        nothing went wrong - while the banner goes on counting the modules
    #        that depend on them as active.
    #
    #        WHAT THESE CASES DO NOT REACH, said plainly rather than left to be
    #        discovered: the platform FAIL. It needs a non-Windows machine, and
    #        Get-LwgPlatformInfo reads [Environment]::OSVersion.Platform - which
    #        no environment variable overrides and which lib\common.ps1 is not
    #        this file's to seam. Case 26 drives the only branch reachable here
    #        and says so; the FAIL branch is asserted by nothing, anywhere.
    #
    #        THE BUILD CASES DRIVE ALL THREE OF ITS STATES, because the middle
    #        one is the whole point: an unread build must not render as a build
    #        that was read and matched.
    #
    #        BASELINE: neither check existed before this commit, so there is no
    #        fd8d023 baseline and no earlier tree to run them against. Their red
    #        is the absence of the row - Get-DoctorRow returns found = $false,
    #        which no case here treats as a pass.
    # -------------------------------------------------------------------

    # -------------------------------------------------------------------
    # 26. THE PLATFORM ROW EXISTS, PASSES ON WINDOWS, AND NAMES THE MACHINE.
    #
    #     A weak case, deliberately labelled as one: it drives the branch that a
    #     Windows runner can reach and asserts the row is present, is a PASS,
    #     and reports the os and the interpreter rather than a bare word. The
    #     FAIL branch - the silent non-install this row exists to name - is not
    #     reachable from here and nothing below pretends it is.
    # -------------------------------------------------------------------
    Set-CaseConfig -Mutate $null
    $t  = New-HealthyCase -Tag 'platform-row' -RepoStatusLine $PlugStatusLine -LogLeaf $LogLeaf
    $pf = Invoke-Doctor -ProfileDir $t.profile -StateDir $t.state
    $row = Get-DoctorRow -Text $pf.out -Id 'platform'
    Add-Result 'the platform row runs, passes on Windows, and names the os and the interpreter' `
        ($row.found -and $row.status -eq 'PASS' -and $row.detail -match "os 'windows'" -and $row.detail -match 'PowerShell \d') `
        ("expected a [PASS] naming the os and the PowerShell it ran under; got [$($row.status)] $($row.detail). " +
         "This case cannot reach the FAIL branch - that needs a machine this suite is not running on. Full output:`n$($pf.out)")

    # -------------------------------------------------------------------
    # 27. AN UNREAD BUILD IS "I DID NOT LOOK", IT SAYS SO IN WORDS, AND IT DOES
    #     NOT COST THE RUN ITS EXIT CODE (#218).
    #
    #     CLAUDE_CODE_VERSION cleared outright - which is what EVERY real run
    #     looks like, because the CLI never exports that variable. The row must
    #     be present, must say the build was NOT read, must NOT claim the events
    #     are present, and the run must still exit 0.
    #
    #     THE EXIT CODE IS THE POINT OF THIS CASE and it is asserted rather than
    #     inferred. The row first shipped as a WARN, on the correct principle
    #     that an unread version must not render as "read, and it matched" - but
    #     since the variable is never set, that WARN fired on every machine on
    #     every run and /doctor could not return 0 on a healthy install, which
    #     is the regression #218 records. The principle is kept in the DETAIL:
    #     the negatives below are what stops the fix from being "call it a PASS
    #     and stop mentioning it".
    #
    #     Case 28 is the CONTROL: a version that IS readable and disagrees still
    #     WARNs and still exits 2, so this case cannot be satisfied by making
    #     the check unable to warn at all.
    #
    #     BASELINE 4342980: RED. The row is a [WARN] there and the run exits 2.
    # -------------------------------------------------------------------
    $t  = New-HealthyCase -Tag 'build-unread' -RepoStatusLine $PlugStatusLine -LogLeaf $LogLeaf
    $bv = Invoke-Doctor -ProfileDir $t.profile -StateDir $t.state -Build ''
    $row = Get-DoctorRow -Text $bv.out -Id 'claude-version'
    Add-Result 'a build that was never read is reported as unread, in words, and does not cost the run its exit 0' `
        ($row.found -and $row.status -eq 'PASS' -and $row.detail -match 'was NOT read' -and
         $row.detail -match 'SubagentStart' -and $row.detail -notmatch 'at or above' -and
         $bv.code -eq 0) `
        ("CLAUDE_CODE_VERSION was cleared for this child, which is what every real run looks like; expected a [PASS] " +
         "saying the build was NOT read, naming the events at risk, and exit 0 - got [$($row.status)] $($row.detail) " +
         "at exit $($bv.code). Full output:`n$($bv.out)")

    # -------------------------------------------------------------------
    # 28. CONTROL FOR 27. A BUILD BELOW THE VERIFIED ONE IS A WARN THAT NAMES
    #     THE THREE EVENTS, AND IT STILL EXITS 2.
    #
    #     WARN and not FAIL: an older Claude Code is a real finding about the
    #     machine, not a broken install, and the exit ladder already separates
    #     the two. The seeded version is DERIVED from the verified build rather
    #     than written here, so it stays below it when that number moves.
    #
    #     THE EXIT CODE IS ASSERTED HERE FOR THE SAME REASON IT IS ASSERTED IN
    #     27 (#218). The cheapest way to make 27 pass is to stop this row ever
    #     warning; this case is what that would cost. A version that WAS read
    #     and disagrees is a fact about the machine, and it must still reach the
    #     caller as exit 2 - bin\lwg-setup.ps1 and bin\lwg-update.ps1 both read
    #     that code as "pass with caveats" and print the row.
    # -------------------------------------------------------------------
    $vb  = [version]$script:VerifiedBuild
    $old = if ($vb.Major -ge 1) { "$($vb.Major - 1).0.0" } else { '0.0.1' }
    $t   = New-HealthyCase -Tag 'build-old' -RepoStatusLine $PlugStatusLine -LogLeaf $LogLeaf
    $bv  = Invoke-Doctor -ProfileDir $t.profile -StateDir $t.state -Build $old
    $row = Get-DoctorRow -Text $bv.out -Id 'claude-version'
    Add-Result 'CONTROL claude-version: a Claude Code below the verified build WARNs, names the three events at risk, and still exits 2' `
        ($row.found -and $row.status -eq 'WARN' -and $row.detail -match [regex]::Escape($old) -and
         $row.detail -match 'BELOW' -and $row.detail -match 'SubagentStart' -and
         $row.detail -match 'PostToolUseFailure' -and $row.detail -match 'StopFailure' -and
         $bv.code -eq 2) `
        ("the child was told it was Claude Code $old against a verified build of $($script:VerifiedBuild); " +
         "expected a [WARN] saying BELOW, naming all three events, and exit 2 - got [$($row.status)] $($row.detail) " +
         "at exit $($bv.code). Full output:`n$($bv.out)")

    # -------------------------------------------------------------------
    # 29. CONTROL. THE VERIFIED BUILD ITSELF PASSES, AND THE ROW STAYS HONEST
    #     ABOUT WHAT IT PROVED.
    #
    #     The cheapest way to pass 27 and 28 is to WARN at every build, and this
    #     is what stops that. It also pins the boundary case - equal to the
    #     verified build is at or above it, not below it - and requires the PASS
    #     to keep saying that a matching build is not evidence any event fired.
    # -------------------------------------------------------------------
    $t   = New-HealthyCase -Tag 'build-verified' -RepoStatusLine $PlugStatusLine -LogLeaf $LogLeaf
    $bv  = Invoke-Doctor -ProfileDir $t.profile -StateDir $t.state
    $row = Get-DoctorRow -Text $bv.out -Id 'claude-version'
    Add-Result 'CONTROL claude-version: the verified build PASSES, and the row still says it proved no event fired' `
        ($row.found -and $row.status -eq 'PASS' -and $row.detail -match [regex]::Escape($script:VerifiedBuild) -and
         $row.detail -match 'BUILD ONLY' -and $bv.code -eq 0) `
        ("the child was told it was Claude Code $($script:VerifiedBuild), which is the verified build itself; " +
         "expected a [PASS] that still disclaims observed firing, and exit 0; got [$($row.status)] $($row.detail) at exit $($bv.code). Full output:`n$($bv.out)")

    # -------------------------------------------------------------------
    # 30. THE STATUSLINE CHECK READS THE CONFIGURATION DIRECTORY THE CLI
    #     ACTUALLY USES, NOT $env:USERPROFILE + '.claude' (#146).
    #
    #     The setup is the whole case. TWO profiles: the healthy one, which has
    #     the wired settings.json and a byte copy of the repo status line, and a
    #     SECOND, EMPTY one. The child is then run with CLAUDE_CONFIG_DIR
    #     pointing at the healthy profile's .claude and USERPROFILE pointing at
    #     the empty one - which is the shape of every machine that relocates its
    #     configuration directory, and which makes the two answers point at
    #     different trees rather than at the same one by accident.
    #
    #     A check that composes the path from USERPROFILE finds nothing there
    #     and FAILs. A check that resolves it through Get-LwgClaudeHomeInfo finds
    #     the wired settings.json and PASSes. There is no reading of this case
    #     that both answers satisfy, which is what the two profiles are for: a
    #     single-profile version would pass on the composition and on the
    #     resolution alike and would establish nothing.
    #
    #     THE DETAIL IS ASSERTED TOO, and not only the status. The row is
    #     required to name which root answered, because the failure this case
    #     exists to stop is not "the doctor errored" - it is the doctor
    #     attesting a green status line against a settings.json the CLI never
    #     loads, and a green row that does not say which file it read is exactly
    #     as unreadable after the fix as before it.
    #
    #     THE CONTROL FOR THE OTHER BRANCH IS ALREADY HERE. Every statusline
    #     case above runs with CLAUDE_CONFIG_DIR CLEARED - Invoke-Doctor clears
    #     it for exactly this reason - and between them they drive this row
    #     through PASS, WARN and FAIL off USERPROFILE alone. So a check that
    #     satisfied this case by reading CLAUDE_CONFIG_DIR and nothing else
    #     would take every one of them down with it, and the precedence is
    #     pinned from both sides rather than from the side that changed. How
    #     many of them there are is deliberately not written here - it is a
    #     count, and "every one" is the claim that stays true when one is added.
    #
    #     BASELINE 4342980: RED. bin\lwg-doctor.ps1:507 reads
    #     `Join-Path $env:USERPROFILE '.claude\settings.json'` there - the last
    #     live composition of that shape in the tree - so the row FAILs with
    #     "no settings file at <the empty profile>".
    # -------------------------------------------------------------------
    $t     = New-HealthyCase -Tag 'cfgdir-relocated' -RepoStatusLine $PlugStatusLine -LogLeaf $LogLeaf
    $empty = Join-Path $t.dir 'empty-profile'
    [void][IO.Directory]::CreateDirectory((Join-Path $empty '.claude'))
    $relocated = Join-Path $t.profile '.claude'
    $r   = Invoke-Doctor -ProfileDir $empty -StateDir $t.state -ConfigDir $relocated
    $row = Get-DoctorRow -Text $r.out -Id 'statusline'
    Add-Result 'the statusline check reads CLAUDE_CONFIG_DIR''s settings.json, not one composed from USERPROFILE' `
        ($row.found -and $row.status -eq 'PASS' -and $row.detail -match 'statusline\.ps1' -and
         $row.detail -notmatch 'no settings file at') `
        ("CLAUDE_CONFIG_DIR named $relocated, which holds the wired settings.json, while USERPROFILE named " +
         "$empty, which holds nothing. Expected a [PASS] naming the wired status line; got [$($row.status)] " +
         "$($row.detail). A [FAIL] saying 'no settings file at' means the check composed the path from " +
         "USERPROFILE and health-checked a file the CLI does not read. Full output:`n$($r.out)")

    # -------------------------------------------------------------------
    # 31. THE SANDBOX ITSELF. Every child above ran with CLAUDE_PLUGIN_DATA
    #     pointed into the scratch tree; this asserts what that was supposed to
    #     buy rather than assuming it. Nothing under the operator's own
    #     ~\.claude\plugins\data\<plugin>* may have grown a byte or gained a
    #     file across this run.
    #
    #     It is a WEAK case when the operator has no such directory - it then
    #     compares two empty sets - and the detail says how many files it
    #     actually watched, so a green run is readable rather than assumed.
    #
    #     BASELINE fd8d023: passes, for the same reason it passes now.
    # -------------------------------------------------------------------
    $liveAfter = Get-LiveLogSizes -RealProfile $RealProfile -PluginName $PluginName
    $changed = @()
    foreach ($k in $liveAfter.Keys) {
        if (-not $liveBefore.ContainsKey($k)) { $changed += "appeared: $k" }
        elseif ($liveBefore[$k] -ne $liveAfter[$k]) { $changed += "grew from $($liveBefore[$k]) to $($liveAfter[$k]) bytes: $k" }
    }
    Add-Result "CONTROL sandbox: the operator's own state dir gained nothing across this run" `
        ($changed.Count -eq 0) `
        "$($changed.Count) change(s) under the live plugin data dir: $($changed -join '; ')"
    if ($changed.Count -eq 0 -and $VerbosePreference -ne 'SilentlyContinue') {
        Write-Output ("        watched $($liveBefore.Count) live file(s) under $RealProfile\.claude\plugins\data\$PluginName*")
    }

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
Write-Output 'Every case above passed. Read that as "config-registry now asks the same'
Write-Output 'question of a value that Test-LwgFlag and Test-LwgModule ask, the'
Write-Output 'statusline check establishes whose file it is looking at before it diagnoses'
Write-Output 'drift, sessionstart tells a log it could not read to the end from a hook'
Write-Output 'that is not firing, and commands measures the tracked tree and says so" - not as'
Write-Output '"the doctor is correct". Four of its ten checks are driven by nothing here'
Write-Output 'beyond the one case that establishes they RAN, no case executes the status line, and a file byte-identical'
Write-Output 'to the repo copy is indistinguishable from an install by any content marker'
Write-Output 'and is named in the header as not covered.'
Write-Output 'EXIT: 0'
exit 0
