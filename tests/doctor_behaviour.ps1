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

  This file drives TWO of the nine checks and no others:

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

  It does NOT drive the other seven checks, and a green run here says nothing
  about them. In particular it says nothing about sessionstart, which is owned
  by a separate issue and deliberately untouched here.

  IT ALSO DRIVES ONE THING THAT IS NOT A CHECK AT ALL: the informational roster
  at the foot of the report - the per-gate paragraphs and the module table that
  used to be bin\lwg-status.ps1, a report command now deleted. Cases 16-18 are
  about the BOUNDARY that move has to keep rather than about the content: the
  roster must print, it must print below the RESULT: line, it must add no row
  the header counts, and the exit code must stay the one the tally implies. A
  report merged into a diagnosis is one edit away from becoming part of the
  diagnosis, and every gate here ships OFF, so a leak would fail a correct
  default install.

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
  fd8d023 is the baseline for every case here. Both defects predate the current
  wave and the two checks are byte-identical between fd8d023 and 19bb85d apart
  from the lw-gmhh -> lw-watchtower rename, so the red proof was taken by
  restoring bin\, lib\ and statusline\ to fd8d023 with this file left in place.

  SEVEN OF THE NINETEEN CASES PASS AT fd8d023 TOO, and every one of them is
  labelled CONTROL in its name and in its comment. None is offered as evidence
  that anything was fixed. They exist because the cheapest way to pass the other
  nine is to answer "not ours" to everything and "FAIL" to every config, and the
  controls are what make that not work.

  THREE OF THE NINETEEN HAVE NO fd8d023 BASELINE AT ALL - cases 16-18, on the
  informational roster, which did not exist there and is not a defect being
  fixed. They pin a boundary rather than a repair, and their red proof is a
  mutation stated in their own comment, not an old commit.

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
  * THE OTHER SEVEN CHECKS, and the doctor's exit code on anything but the two
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
    # Repo root. Defaults to this file's parent, correct for a run from anywhere
    # as long as this file stays in tests\.
    [string]$Root
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }

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
    #>
    param([string]$ProfileDir, [string]$StateDir, [switch]$QuietRun)

    $prev  = $env:USERPROFILE
    $prevD = $env:CLAUDE_PLUGIN_DATA
    $prevR = $env:CLAUDE_PLUGIN_ROOT
    $prevC = $env:CLAUDE_CODE_PLUGIN_CACHE_DIR
    $out  = ''
    $code = 255
    try {
        $env:USERPROFILE                  = $ProfileDir
        $env:CLAUDE_PLUGIN_DATA           = $StateDir
        $env:CLAUDE_PLUGIN_ROOT           = ''
        $env:CLAUDE_CODE_PLUGIN_CACHE_DIR = ''
        # -Quiet is passed as a real switch on the child's command line rather
        # than spliced into a string: the only case that uses it asserts what
        # the shipped switch does, and a hand-built argument list is a second
        # thing that can be wrong.
        $lines = if ($QuietRun) {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $script:DoctorPath -Quiet
        } else {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $script:DoctorPath
        }
        $code  = if ($null -eq $LASTEXITCODE) { 255 } else { $LASTEXITCODE }
        $out   = ($lines | Out-String)
    } finally {
        $env:USERPROFILE                  = $prev
        $env:CLAUDE_PLUGIN_DATA           = $prevD
        $env:CLAUDE_PLUGIN_ROOT           = $prevR
        $env:CLAUDE_CODE_PLUGIN_CACHE_DIR = $prevC
    }
    return @{ code = $code; out = $out }
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
        $m = [regex]::Match($line, '^\s+\[(PASS|WARN|FAIL)\]\s+(\S+)\s+(.*)$')
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

function Get-RowMap {
    <# Every row in a doctor report as id -> status. Used only to compare two
       runs of the SAME sandbox against each other. #>
    param([string]$Text)
    $map = [ordered]@{}
    foreach ($line in ($Text -split "`r?`n")) {
        $m = [regex]::Match($line, '^\s+\[(PASS|WARN|FAIL)\]\s+(\S+)\s+(.*)$')
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
    Write-Output '  under   : bin\lwg-doctor.ps1, checks config-registry and statusline only'
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
    $rowLines   = @([regex]::Matches($rr.out, '(?m)^\s+\[(?:PASS|WARN|FAIL)\]\s+\S+'))
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
    # 19. THE SANDBOX ITSELF. Every child above ran with CLAUDE_PLUGIN_DATA
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
Write-Output 'question of a value that Test-LwgFlag and Test-LwgModule ask, and the'
Write-Output 'statusline check establishes whose file it is looking at before it diagnoses'
Write-Output 'drift" - not as "the doctor is correct". Seven of its nine checks are driven'
Write-Output 'by nothing here, no case executes the status line, and a file byte-identical'
Write-Output 'to the repo copy is indistinguishable from an install by any content marker'
Write-Output 'and is named in the header as not covered.'
Write-Output 'EXIT: 0'
exit 0
