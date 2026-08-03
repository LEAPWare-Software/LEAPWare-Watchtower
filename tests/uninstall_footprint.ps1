#requires -version 5
<#
  LW-WATCHTOWER uninstaller footprint-and-deletion regression suite.

      powershell -NoProfile -ExecutionPolicy Bypass -File tests\uninstall_footprint.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File tests\uninstall_footprint.ps1 -Verbose

  WHY THIS FILE EXISTS

  On 31 July 2026, adversarial UAT against v0.3.0 found bin\lwg-uninstall.ps1
  hardcoding ~\.claude\plugins\data as the state-data location and never reading
  CLAUDE_PLUGIN_DATA - the variable lib\common.ps1 calls "authoritative and ends
  the matter", the one Claude Code hands every hook, and the one every other
  component in this plugin resolves through. With the data dir redirected:

      bin\lwg-doctor.ps1     state-dir ... (source 'env')    5 live files
      bin\lwg-uninstall.ps1  state-data  absent  nothing to do
      -RemoveData -ConfirmToken DELETE-MY-LWG-LOGS
                          -> APPLIED: 0 change(s), 0 failure(s), exit 0
                          -> all five files still on disk

  An operator typed a destructive confirmation token, was told it had worked,
  and nothing had been deleted. That is both halves of the worst defect this
  plugin can have - it failed to act, AND it reported success - and it is the
  exact class of failure the plugin exists to catch, committed by the plugin.

  So the claim these cases defend is not "the uninstaller deletes things". It is
  the narrower and more useful one:

      WHAT THE FOOTPRINT SAYS IT WILL REMOVE IS WHAT IT REMOVES, AND WHEN IT
      CANNOT WORK OUT WHERE TO LOOK IT SAYS SO AND EXITS NONZERO RATHER THAN
      REPORTING AN EMPTY FOOTPRINT AS A CLEAN ONE.

  Every case therefore asserts on the FILESYSTEM as well as on the text: a case
  that only read the report could be satisfied by a script that prints well and
  deletes nothing, which is the thing that shipped.

  ---------------------------------------------------------------------------
  THREE RULES EVERY CASE HERE FOLLOWS - written down 3 August 2026
  ---------------------------------------------------------------------------
  Each of these was held by cases agreeing with each other rather than by
  anything stated, which is how one of them drifted:

    1. AN APPLY-MODE CASE WHOSE SUBJECT IS A SUCCESSFUL REMOVAL ASSERTS THE
       `APPLIED:` LINE, exactly, in both numbers. Four such cases agreed on this
       and a fifth did not; the fifth's subject was an EMPTY directory, which is
       precisely the input that makes a change counter scoped per file rather
       than per directory report zero after a real deletion.

       READ THE SCOPE, because several cases here are correctly outside it. A
       case whose subject is a REFUSAL - the wrong token, a reparse point, an
       unattributable directory, a restore carrying a removal flag - asserts
       `REFUSED` and a non-zero exit instead, and asserting an exact `APPLIED:`
       tally on one of those would pin an incidental number rather than the
       property. Test-PartialDeletionNamesWhatWent is outside it for a third
       reason: its subject is a removal that half-happened, so the assertion is
       on the count of files that went, which is the thing the report was
       getting wrong.
    2. A CASE MUST REACH THE CODE IT IS NAMED FOR. Where a name refers to a
       branch, the fixture is chosen so that branch executes and the assertion
       observes something only that branch produces. A `-notmatch` on a string
       emitted only from inside a branch the specimen never enters is
       guaranteed, not earned.
    3. NO BARE NEGATIVE STANDS ALONE for the property in a case's name. Assert
       the thing that must be true as well as the thing that must not.

  ---------------------------------------------------------------------------
  HOW A CASE IS RUN
  ---------------------------------------------------------------------------
  In a real child process, against the real bin\lwg-uninstall.ps1, because that
  is the file /lw-watchtower:uninstall invokes:

      powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-uninstall.ps1 `
                 -ClaudeHome <scratch>\profile\.claude [flags]

  with $env:USERPROFILE and $env:CLAUDE_PLUGIN_DATA swapped around the call and
  restored in a finally. Those are the two knobs that decide every path the
  script touches: the profile carries the junction, the copied status line and
  settings.json, and CLAUDE_PLUGIN_DATA carries the state data. Redirecting both
  at a throwaway tree is the whole sandbox.

  ---------------------------------------------------------------------------
  TEST SAFETY - read before adding a case
  ---------------------------------------------------------------------------
  Cases here run the uninstaller in APPLY mode with a real destructive
  confirmation token. That is only acceptable because of these rules, and a new
  case that breaks one of them is a case that can eat an operator's logs:

    * Every scratch path is BUILT AT RUNTIME from [IO.Path]::GetTempPath(). No
      path in this file names a machine, an account or an install location -
      which is also what tests\portability_scan.ps1 holds every tracked file to.
    * $env:USERPROFILE is redirected for EVERY child invocation, including the
      ones that pass no destructive flag. The uninstaller's sibling sweep hangs
      off that variable, so a case that forgot to set it would sweep the real
      ~\.claude\plugins\data - and in apply mode would delete what it found.
      Invoke-Uninstall does it unconditionally for that reason; do not add a
      code path that calls the script directly.
    * The only directories any case deletes are directories the case itself
      created seconds earlier under the temp root, seeded with invented file
      contents. Nothing here is elevated and no case constructs a shell command.
    * The scratch tree is removed in a finally. If the suite aborts before it is
      built, there is nothing to remove.

  ---------------------------------------------------------------------------
  WHAT IS DELIBERATELY NOT COVERED, so a green run is not read as more
  ---------------------------------------------------------------------------
  * A SUCCESSFUL settings.json EDIT. Whether the writer removes a statusLine
    key or a deny entry from a readable, parseable file and leaves the rest
    byte-identical is lib\common.ps1's writer's job, and tests\setup_merge.ps1
    exercises that. What IS covered here is everything AROUND that edit, which
    is this script's own: whether an entry is ATTRIBUTED to this plugin
    (Test-CanonicalDenyRulesAllAttributed, Test-MissingDenyKeyInventsNoEntry,
    Test-ThirdPartyStatusLineIsNotOurs), whether the two halves of the status
    line move together (Test-StatusLineFileKeptWhenKeyHalfCannotRun), and the
    restore path's refusals and its absent-file case. Reporting and editing are
    two subjects and the line between them is here rather than assumed.
  * THE SKILLS-JUNCTION ROW in section 1. The script refuses to remove that
    junction by design and the row is report-only, so there is no removal
    behaviour to pin. A junction under the DATA root is a different thing and IS
    covered, by Test-ReparseStateDirIsRefused.
  * WHICH of several suffixed candidates is "live" when more than one exists.
    That rule is lib\common.ps1's and is not this script's to get right.
  * A DENIED ACL as a route into the partial-delete branch. The branch itself is
    covered by Test-PartialDeletionNamesWhatWent, which reaches it with a real
    FileStream lock rather than a mock; an ACL denial is a second route to the
    same catch and is not separately covered.

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

$UninstallPath = Join-Path $Root 'bin\lwg-uninstall.ps1'

# The plugin's own name, read the way the script reads it, so the fixtures build
# directory names the sweep will actually match rather than a literal that would
# silently stop matching if the plugin were renamed.
$PluginName = 'lw-watchtower'
try {
    $pj = Get-Content -LiteralPath (Join-Path $Root '.claude-plugin\plugin.json') -Raw | ConvertFrom-Json
    if (-not [string]::IsNullOrWhiteSpace([string]$pj.name)) { $PluginName = [string]$pj.name }
} catch { }

# The token the script demands, spelled here exactly once. It is deliberately
# NOT read out of the script under test: a test that derives the password from
# the lock cannot notice the lock changing.
$Token = 'DELETE-MY-LWG-LOGS'

# What a seeded data directory holds. Invented names in the shape of the real
# ones, so a case is recognisable in a failure message.
$SeedFiles = @('health.jsonl', 'lw-watchtower.jsonl', 'advisory-lwg-test-1.json',
               'advisory-lwg-test-2.json', 'doctor.probe')

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
# HELPERS
# ---------------------------------------------------------------------------

function New-CaseTree {
    <#
      A throwaway tree for one case:

        <work>\<tag>\profile\.claude\                 stands in for the profile
        <work>\<tag>\profile\.claude\plugins\data\    the DISCOVERY root
        <work>\<tag>\elsewhere\                       somewhere the sweep cannot see

      Returns a hashtable of those paths. Nothing is seeded here - each case
      says where its data goes, because where it goes is the subject.
    #>
    param([string]$Tag)

    $dir  = Join-Path $script:Work $Tag
    $prof = Join-Path $dir 'profile'
    $home_ = Join-Path $prof '.claude'
    $root = Join-Path $home_ 'plugins\data'
    $else_ = Join-Path $dir 'elsewhere'
    foreach ($p in @($root, $else_)) { [void][IO.Directory]::CreateDirectory($p) }
    return @{ dir = $dir; profile = $prof; claudeHome = $home_; dataRoot = $root; elsewhere = $else_ }
}

function Set-CaseSettings {
    <#
      Write a settings.json into a case tree's profile. The uninstaller is given
      -ClaudeHome, and derives -SettingsPath from it, so this is the only thing
      a case has to do to give the run a settings file to read.

      The text is written verbatim, WITHOUT ConvertTo-Json, because two cases
      here are about a settings.json that does not parse and one is about the
      one-entry-per-line shape the permissions edit requires. A helper that
      round-tripped through the JSON writer could not express either.
    #>
    param([hashtable]$Tree, [string]$Text)

    [void][IO.Directory]::CreateDirectory($Tree.claudeHome)
    $p = Join-Path $Tree.claudeHome 'settings.json'
    [IO.File]::WriteAllText($p, $Text, [Text.UTF8Encoding]::new($false))
    return $p
}

function New-CaseStatusLine {
    <#
      A file standing in for an installed status line, at whatever path the case
      needs. Invented content - nothing here is a copy of the real one, because
      no case asserts on what it contains, only on whether it is still there.
    #>
    param([string]$Path)

    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, "# lwg-test statusline fixture`r`nWrite-Output 'lwg-test'`r`n", [Text.UTF8Encoding]::new($false))
    return $Path
}

function New-SeededDataDir {
    <#
      A directory holding $SeedFiles, each with distinct invented content so a
      surviving file can be told from a recreated one. Returns the full path.
    #>
    param([string]$Path)

    [void][IO.Directory]::CreateDirectory($Path)
    $i = 0
    foreach ($f in $SeedFiles) {
        $i++
        [IO.File]::WriteAllText((Join-Path $Path $f), "lwg-test-seed-$i`n", [Text.UTF8Encoding]::new($false))
    }
    return $Path
}

function Get-TreeFingerprint {
    <#
      Every file under a root, as `relative-path:length` lines, sorted. Enough
      to prove a dry run changed nothing, and it does not depend on timestamps.
      A missing root is reported as the literal '<absent>' rather than as an
      empty tree, because those are different facts and one of the cases turns
      on the difference.
    #>
    param([string]$Path)

    if (-not [IO.Directory]::Exists($Path)) { return '<absent>' }
    $out = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName)) {
        $out += ("{0}:{1}" -f $f.FullName.Substring($Path.Length).TrimStart('\'), $f.Length)
    }
    return ($out -join '|')
}

function Invoke-Uninstall {
    <#
      One real child run of bin\lwg-uninstall.ps1.

      $env:USERPROFILE is redirected UNCONDITIONALLY - see TEST SAFETY in the
      header - and $env:CLAUDE_PLUGIN_DATA is set when -DataEnv is given and
      REMOVED when it is not, because "the variable is not set" is one of the
      cases and inheriting the caller's value would quietly defeat it.

      Returns @{ code; out } where `out` is the whole stdout as one string.
    #>
    param(
        [Parameter(Mandatory = $true)][hashtable]$Tree,
        [string]$DataEnv,
        [string[]]$ScriptArgs = @()
    )

    $saveProfile = $env:USERPROFILE
    $saveData    = $env:CLAUDE_PLUGIN_DATA
    try {
        $env:USERPROFILE = $Tree.profile
        if ([string]::IsNullOrWhiteSpace($DataEnv)) {
            Remove-Item -LiteralPath 'Env:\CLAUDE_PLUGIN_DATA' -ErrorAction SilentlyContinue
        } else {
            $env:CLAUDE_PLUGIN_DATA = $DataEnv
        }

        $all = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $UninstallPath,
                 '-ClaudeHome', $Tree.claudeHome) + $ScriptArgs
        $lines = & powershell.exe @all
        $code  = if ($null -eq $LASTEXITCODE) { 255 } else { $LASTEXITCODE }
        return @{ code = $code; out = (@($lines) -join "`n") }
    } finally {
        $env:USERPROFILE = $saveProfile
        if ($null -eq $saveData) {
            Remove-Item -LiteralPath 'Env:\CLAUDE_PLUGIN_DATA' -ErrorAction SilentlyContinue
        } else {
            $env:CLAUDE_PLUGIN_DATA = $saveData
        }
    }
}

function Get-StateDataRow {
    <#
      The `state-data` row of the FOOTPRINT table, as the two lines the script
      prints for it joined by a space. Returns '' when there is no such row,
      which is itself a failure every caller checks for - a missing row is not
      the same as a row saying nothing was found.
    #>
    param([string]$Out)

    $lines = @($Out -split "`r?`n")
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s{2}state-data\s{2,}') {
            $row = $lines[$i].Trim()
            if ($i + 1 -lt $lines.Count) { $row += ' ' + $lines[$i + 1].Trim() }
            return $row
        }
    }
    return ''
}

# ---------------------------------------------------------------------------
# CASES
# ---------------------------------------------------------------------------

function Test-DryRunListsRedirectedDir {
    <#
      THE HEADLINE CASE, and the direct inverse of the UAT finding. With
      CLAUDE_PLUGIN_DATA pointing at a seeded directory OUTSIDE the discovery
      root - so nothing but the environment variable can find it - the dry run
      must name that exact directory in the state-data row, and must leave every
      seeded file untouched.
    #>
    $t    = New-CaseTree 'dry-env'
    $data = New-SeededDataDir (Join-Path $t.elsewhere 'redirected-state')
    $before = Get-TreeFingerprint $data

    $r   = Invoke-Uninstall -Tree $t -DataEnv $data
    $row = Get-StateDataRow $r.out
    $after = Get-TreeFingerprint $data

    $bad = @()
    if ($r.code -ne 0)                  { $bad += "exit $($r.code), expected 0" }
    if ($row -eq '')                    { $bad += 'no state-data row in the footprint at all' }
    if ($row -notlike "*$data*")        { $bad += "the state-data row does not name $data" }
    if ($row -match '(?i)\babsent\b')   { $bad += "the row still says 'absent' - this is the shipped defect: $row" }
    if ($row -notmatch '1 dir\(s\)')    { $bad += "the row does not report exactly 1 directory: $row" }
    if ($r.out -notmatch "(?i)source 'env'") { $bad += 'the run never reports source ''env'', so the variable was not what resolved it' }
    if ($after -ne $before)             { $bad += 'THE DRY RUN CHANGED THE SEEDED FILES' }

    Add-Result -Name 'dry run: CLAUDE_PLUGIN_DATA redirected - lists exactly that directory, deletes nothing' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | row: $row")
}

function Test-DryRunWithRemoveDataDeletesNothing {
    <#
      The same tree, run with the FULL destructive flag set but WITHOUT -Apply.
      The dry run is the default and is the mode an operator can be talked into
      by a model, so "the flags were present and it still wrote nothing" is the
      property worth a case of its own.
    #>
    $t    = New-CaseTree 'dry-armed'
    $data = New-SeededDataDir (Join-Path $t.elsewhere 'redirected-state')
    $before = Get-TreeFingerprint $data

    $r = Invoke-Uninstall -Tree $t -DataEnv $data -ScriptArgs @('-RemoveData', '-ConfirmToken', $Token)
    $after = Get-TreeFingerprint $data

    $bad = @()
    if ($r.code -ne 0)      { $bad += "exit $($r.code), expected 0" }
    if ($after -ne $before) { $bad += 'THE DRY RUN DELETED OR ALTERED FILES' }
    if ($r.out -notmatch 'DRY RUN - nothing above was written') { $bad += 'the run did not state that it wrote nothing' }
    if ($r.out -match '(?m)^\s+deleted ')                       { $bad += 'the run printed a deletion line' }

    Add-Result -Name 'dry run: -RemoveData with the real token still deletes nothing' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | exit $($r.code)")
}

function Test-ApplyDeletesRedirectedDir {
    <#
      The apply half of the headline case. The directory must really be gone
      afterwards, and the count the script reports must be the truth: one
      directory planned, one deletion line, one change applied.
    #>
    $t    = New-CaseTree 'apply-env'
    $data = New-SeededDataDir (Join-Path $t.elsewhere 'redirected-state')

    $r = Invoke-Uninstall -Tree $t -DataEnv $data -ScriptArgs @('-Apply', '-RemoveData', '-ConfirmToken', $Token)
    $gone = -not [IO.Directory]::Exists($data)

    $bad = @()
    if ($r.code -ne 0)                                  { $bad += "exit $($r.code), expected 0" }
    if (-not $gone)                                     { $bad += "THE DIRECTORY SURVIVED: $data" }
    if ($r.out -notmatch [regex]::Escape("deleted $data")) { $bad += 'no line naming that directory as deleted' }
    if ($r.out -notmatch 'APPLIED: 1 change\(s\), 0 failure\(s\)') { $bad += 'the APPLIED line does not report exactly 1 change and 0 failures' }
    $deletions = @([regex]::Matches($r.out, '(?m)^\s+deleted ')).Count
    if ($deletions -ne 1)                               { $bad += "$deletions deletion line(s), expected 1" }

    Add-Result -Name 'apply: -RemoveData with the token deletes the redirected directory and counts it truthfully' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | exit $($r.code)")
}

function Test-FallbackUsedWhenEnvUnset {
    <#
      With the variable UNSET, resolution must fall through to the discovery
      rule - a <name>-<source> directory under <profile>\.claude\plugins\data -
      and the footprint must name that directory and call it 'discovered'. This
      is the case that proves the fix did not simply swap one hardcoded answer
      for the environment variable and lose the fallback.
    #>
    $t    = New-CaseTree 'fallback'
    $data = New-SeededDataDir (Join-Path $t.dataRoot "$PluginName-lwgtestsource")

    $r   = Invoke-Uninstall -Tree $t
    $row = Get-StateDataRow $r.out

    $bad = @()
    if ($r.code -ne 0)                { $bad += "exit $($r.code), expected 0" }
    if ($row -eq '')                  { $bad += 'no state-data row in the footprint at all' }
    if ($row -notlike "*$data*")      { $bad += "the state-data row does not name $data" }
    if ($row -match '(?i)\babsent\b') { $bad += "the row says 'absent' while the directory exists: $row" }
    if ($r.out -notmatch "(?i)source 'discovered'") { $bad += 'the run does not report source ''discovered''' }
    if (-not [IO.Directory]::Exists($data))         { $bad += 'the dry run deleted the fallback directory' }

    Add-Result -Name 'no CLAUDE_PLUGIN_DATA: the discovered fallback location is used and named' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | row: $row")
}

function Test-UnresolvableIsNotAbsent {
    <#
      Nothing set, nothing to discover: no CLAUDE_PLUGIN_DATA and a profile whose
      data root holds no candidate at all. The script has not established that
      there is no state data - it has established nothing - and the row must say
      so. 'absent' here is the exact word that made the shipped defect readable
      as a clean bill of health, so it is asserted against by name.

      The plain dry run still exits 0: nothing was asked of it. The exit code is
      the subject of the next two cases.
    #>
    $t = New-CaseTree 'unresolvable'

    $r   = Invoke-Uninstall -Tree $t
    $row = Get-StateDataRow $r.out

    $bad = @()
    if ($r.code -ne 0)                    { $bad += "exit $($r.code), expected 0 for a dry run that was asked nothing" }
    if ($row -eq '')                      { $bad += 'no state-data row in the footprint at all' }
    if ($row -notmatch 'UNRESOLVED')      { $bad += "the row does not say UNRESOLVED: $row" }
    if ($row -match '(?i)\babsent\b')     { $bad += "the row says 'absent' for a location it never resolved: $row" }
    if ($r.out -notmatch '(?i)state-data directories, wherever they are') { $bad += 'LEFT BEHIND does not name the state data it could not find' }

    Add-Result -Name 'unresolvable location: reported as UNRESOLVED, never as absent' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | row: $row")
}

function Test-UnresolvableRemoveDataApplyExitsNonZero {
    <#
      THE OTHER HALF OF THE SHIPPED DEFECT. -RemoveData with the real token,
      -Apply, and a location that will not resolve: the run must NOT report a
      successful no-op. It must state that it could not find out where to look,
      and exit nonzero.
    #>
    $t = New-CaseTree 'unresolvable-apply'

    $r = Invoke-Uninstall -Tree $t -ScriptArgs @('-Apply', '-RemoveData', '-ConfirmToken', $Token)

    $bad = @()
    if ($r.code -eq 0)                                              { $bad += 'EXIT 0 - a no-op deletion reported as success, which is the shipped defect' }
    elseif ($r.code -ne 2)                                          { $bad += "exit $($r.code), expected 2" }
    if ($r.out -notmatch '(?i)could not work out WHERE the state data lives') { $bad += 'the run does not say it could not work out where to look' }
    if ($r.out -notmatch 'APPLIED: 0 change\(s\), 1 failure\(s\)')  { $bad += 'the APPLIED line does not count the unresolvable location as a failure' }

    Add-Result -Name 'apply: -RemoveData against an unresolvable location fails loudly and exits 2' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | exit $($r.code)")
}

function Test-UnresolvableRemoveDataDryRunExitsNonZero {
    <#
      The same question asked without -Apply. "Would you delete the data?" is
      answerable only if the location is known, so the dry run exits 2 as well
      rather than printing a clean plan an operator would then arm.
    #>
    $t = New-CaseTree 'unresolvable-dry'

    $r = Invoke-Uninstall -Tree $t -ScriptArgs @('-RemoveData', '-ConfirmToken', $Token)

    $bad = @()
    if ($r.code -ne 2) { $bad += "exit $($r.code), expected 2" }
    if ($r.out -notmatch '(?i)could NOT establish where the state data lives') { $bad += 'the run does not say the location could not be established' }

    Add-Result -Name 'dry run: -RemoveData against an unresolvable location exits 2 rather than 0' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | exit $($r.code)")
}

function Test-EmptyStateDirIsStillATarget {
    <#
      RENAMED ON 3 AUGUST 2026, and the old name is the point. It was
      `Test-ResolvedButEmptyIsNotAFailure`, and it asserted the absence of the
      string `could not work out WHERE` - a string bin\lwg-uninstall.ps1 emits
      ONLY from inside `if ($dataDirs.Count -eq 0)`. This specimen is an
      EXISTING directory handed over through CLAUDE_PLUGIN_DATA, so
      $dataDirs.Count is 1, execution takes the deletion loop, and that branch
      is never evaluated. The case was named for a branch it does not enter and
      the assertion standing in for the property was guaranteed rather than
      earned. Test-ResolvableWithNoPluginDirIsNotUnresolvable below is the case
      that enters it.

      What this specimen really covers is worth keeping and is what it is now
      called: CLAUDE_PLUGIN_DATA is authoritative, the directory it names is
      this plugin's whether or not it holds anything, and an empty state dir is
      therefore ONE DELETION, not a no-op.

      The APPLIED assertion is the other half and was the one thing this case
      lacked that its four apply-mode siblings all have. An empty directory is
      the exact input that makes a mis-scoped change counter - one incremented
      per file rather than per directory - report zero after a real deletion,
      and `APPLIED: 0 change(s), 0 failure(s)` after a destructive confirmation
      token is the string on line 19 of this header.
    #>
    $t     = New-CaseTree 'empty-target'
    $empty = Join-Path $t.elsewhere 'empty-state'
    [void][IO.Directory]::CreateDirectory($empty)

    $r = Invoke-Uninstall -Tree $t -DataEnv $empty -ScriptArgs @('-Apply', '-RemoveData', '-ConfirmToken', $Token)

    $bad = @()
    if ($r.code -ne 0)                  { $bad += "exit $($r.code), expected 0" }
    if ([IO.Directory]::Exists($empty)) { $bad += 'the resolved (empty) state directory was not removed' }
    if ($r.out -notmatch 'APPLIED: 1 change\(s\), 0 failure\(s\)') { $bad += 'the APPLIED line does not report exactly 1 change and 0 failures - an empty state directory is still one deletion' }

    Add-Result -Name 'apply: an existing but empty state dir is one deletion, and is counted as one' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | exit $($r.code)")
}

function Test-DryRunEmptyStateDirPlannedAsOne {
    <#
      THE PLAN SIDE OF THE CASE ABOVE, which had none. Every other subject in
      this file is asked both ways; the empty directory was the one subject with
      an apply-mode case and no dry-run counterpart, and "the plan says 1 and
      the apply says 0" is precisely the plan-and-action disagreement this suite
      is named for. Nothing pinned either half for an empty directory.
    #>
    $t     = New-CaseTree 'empty-plan'
    $empty = Join-Path $t.elsewhere 'empty-state'
    [void][IO.Directory]::CreateDirectory($empty)

    $r   = Invoke-Uninstall -Tree $t -DataEnv $empty -ScriptArgs @('-RemoveData', '-ConfirmToken', $Token)
    $row = Get-StateDataRow $r.out

    $bad = @()
    if ($r.code -ne 0)                       { $bad += "exit $($r.code), expected 0" }
    if ($row -eq '')                         { $bad += 'no state-data row in the footprint at all' }
    if ($row -notmatch '1 dir\(s\)')         { $bad += "the plan does not report exactly 1 directory for an empty state dir: $row" }
    if ($row -notlike "*$empty*")            { $bad += "the plan does not name $empty" }
    if (-not [IO.Directory]::Exists($empty)) { $bad += 'THE DRY RUN DELETED THE DIRECTORY' }

    Add-Result -Name 'dry run: an empty state dir is planned as 1 directory, and the dry run deletes it' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | row: $row")
}

function Test-ResolvableWithNoPluginDirIsNotUnresolvable {
    <#
      THE CASE THE OLD NAME OF Test-EmptyStateDirIsStillATarget PROMISED, and
      the one that actually enters `if ($dataDirs.Count -eq 0)` in
      bin\lwg-uninstall.ps1. CLAUDE_PLUGIN_DATA names a location that RESOLVES
      but that does not exist, so there is no deletion target at all and
      $dataLocatable is true by the resolver rather than by a find. The run must
      take the "that is an answer" limb, exit 0 and count nothing - and must NOT
      take the "could not work out WHERE" limb beside it.

      Asserted POSITIVELY on the resolvable wording. The old bare `-notmatch`
      on the unresolvable wording could not fail: that string is emitted only
      from the limb this branch chooses between, so a specimen that never
      reaches the branch is guaranteed not to see it.
    #>
    $t    = New-CaseTree 'resolvable-nodir'
    $gone = Join-Path $t.elsewhere 'state-that-was-never-created'

    $r = Invoke-Uninstall -Tree $t -DataEnv $gone -ScriptArgs @('-Apply', '-RemoveData', '-ConfirmToken', $Token)

    $bad = @()
    if ($r.code -ne 0) { $bad += "exit $($r.code), expected 0 - the location resolved, so an empty result is an answer" }
    if ($r.out -notmatch '(?i)nothing to delete\. The state-data location resolved to') { $bad += 'the run does not state that the location resolved and held nothing' }
    if ($r.out -match '(?i)could not work out WHERE') { $bad += 'a resolved location was reported as unresolvable' }
    if ($r.out -notmatch 'APPLIED: 0 change\(s\), 0 failure\(s\)') { $bad += 'the APPLIED line does not report 0 changes and 0 failures' }

    Add-Result -Name 'apply: a location that resolves but holds no plugin directory is an answer, not an unresolvable' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | exit $($r.code)")
}

function Test-WrongTokenDeletesNothing {
    <#
      The guard that was already there, pinned because the rewrite of this block
      moved every line around it. A wrong token must refuse before anything is
      deleted, and must exit 1 - the REFUSED code, not the failure code.
    #>
    $t    = New-CaseTree 'wrong-token'
    $data = New-SeededDataDir (Join-Path $t.elsewhere 'redirected-state')
    $before = Get-TreeFingerprint $data

    $r = Invoke-Uninstall -Tree $t -DataEnv $data -ScriptArgs @('-Apply', '-RemoveData', '-ConfirmToken', 'not-the-token')
    $after = Get-TreeFingerprint $data

    $bad = @()
    if ($r.code -ne 1)      { $bad += "exit $($r.code), expected 1 (REFUSED)" }
    if ($after -ne $before) { $bad += 'FILES WERE DELETED OR ALTERED DESPITE THE WRONG TOKEN' }
    if ($r.out -notmatch 'REFUSED') { $bad += 'the run does not print a refusal' }

    Add-Result -Name 'apply: a wrong -ConfirmToken refuses, deletes nothing, and exits 1' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | exit $($r.code)")
}

function Test-PlanMatchesDeletion {
    <#
      The footprint is a promise. With BOTH an env-redirected directory and a
      discoverable sibling under the profile's data root, the plan must name two
      directories and the apply must delete those two and no others - including
      the unrelated directory sitting beside them, which shares neither the name
      prefix nor the resolved location and must survive.
    #>
    $t     = New-CaseTree 'plan-match'
    $envD  = New-SeededDataDir (Join-Path $t.elsewhere 'redirected-state')
    $sibD  = New-SeededDataDir (Join-Path $t.dataRoot "$PluginName-lwgtestsource")
    $other = New-SeededDataDir (Join-Path $t.dataRoot 'some-other-plugin-data')

    $dry     = Invoke-Uninstall -Tree $t -DataEnv $envD
    $dryRow  = Get-StateDataRow $dry.out

    $bad = @()
    if ($dryRow -notmatch '2 dir\(s\)') { $bad += "the plan does not report exactly 2 directories: $dryRow" }
    if ($dryRow -notlike "*$envD*")     { $bad += 'the plan omits the env-redirected directory' }
    if ($dryRow -notlike "*$sibD*")     { $bad += 'the plan omits the discoverable sibling' }
    if ($dryRow -like "*$other*")       { $bad += 'the plan names an unrelated directory it does not own' }

    $r = Invoke-Uninstall -Tree $t -DataEnv $envD -ScriptArgs @('-Apply', '-RemoveData', '-ConfirmToken', $Token)
    if ($r.code -ne 0)                       { $bad += "apply exit $($r.code), expected 0" }
    if ([IO.Directory]::Exists($envD))       { $bad += 'the env-redirected directory survived' }
    if ([IO.Directory]::Exists($sibD))       { $bad += 'the discoverable sibling survived' }
    if (-not [IO.Directory]::Exists($other)) { $bad += 'AN UNRELATED DIRECTORY WAS DELETED' }
    if ($r.out -notmatch 'APPLIED: 2 change\(s\), 0 failure\(s\)') { $bad += 'the APPLIED line does not report exactly 2 changes' }

    Add-Result -Name 'plan and deletion agree: both owned directories go, the unrelated one stays' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | plan: $dryRow")
}

function Test-CanonicalDenyRulesAllAttributed {
    <#
      THE 181, THROUGH THE REAL MATCHER, VIA A REAL settings.json.

      tests\fixtures\deny_canonical.txt is the permissions.deny block
      bin\lwg-setup.ps1 emitted at ef993bc, restored to the tree from that
      commit. Test-MirroredDeny's docstring calls itself "the only code left in
      the repo that knows what those rules looked like", five tracked pages
      repeat the claim, and until this case existed nothing checked it: the
      fixture and the parity test that read it were deleted together with the
      destructive deny groups on 30 July 2026.

      It knew 177. The four it did not know are the +refspec force pushes -
      `Bash(git push * +*)` and friends - which carry no --force and no -f, so
      the flag-shaped git-push family could not see them. `-RemovePermissions`
      wrote them back into the keep list AND the LEFT BEHIND block told the
      operator, in writing, that this plugin had not put them there.

      DRY RUN, deliberately. This asserts on ATTRIBUTION, which is what the
      footprint reports; the settings.json EDIT is a different subject and is
      still out of scope for this file (see the header).
    #>
    $fixture = Join-Path $Root 'tests\fixtures\deny_canonical.txt'
    if (-not [IO.File]::Exists($fixture)) {
        throw "tests\fixtures\deny_canonical.txt is missing at $fixture. It IS the subject of this case, so its absence is an abort, not a skip"
    }
    $rules = @([IO.File]::ReadAllLines($fixture) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    $t = New-CaseTree 'deny-canonical'
    $body = @($rules | ForEach-Object { '      "' + $_.Replace('\', '\\').Replace('"', '\"') + '"' }) -join ",`r`n"
    [void](Set-CaseSettings -Tree $t -Text ("{`r`n  `"permissions`": {`r`n    `"deny`": [`r`n" + $body + "`r`n    ]`r`n  }`r`n}`r`n"))

    $r = Invoke-Uninstall -Tree $t

    $bad = @()
    if ($r.code -ne 0) { $bad += "exit $($r.code), expected 0" }
    if ($r.out -notmatch "$($rules.Count) of $($rules.Count) attributable") {
        $m = [regex]::Match($r.out, '(\d+) of (\d+) attributable')
        $bad += "the permissions-deny row does not read '$($rules.Count) of $($rules.Count) attributable' - it reads '$(if ($m.Success) { $m.Value } else { '<no such row>' })'"
    }
    if ($r.out -match 'other permissions\.deny entries') {
        $bad += 'LEFT BEHIND claims some of the canonical rules were not put there by this plugin, which is false for every one of them'
    }

    Add-Result -Name "dry run: all $($rules.Count) canonical permissions.deny rules are attributed to this plugin" `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | exit $($r.code)")
}

function Test-MissingDenyKeyInventsNoEntry {
    <#
      @($x.deny) where the `deny` key does not exist is a ONE-ELEMENT ARRAY
      HOLDING $null under Windows PowerShell 5.1, not an empty array. So the
      honest `permissions-deny absent nothing to do` row was unreachable on
      every machine without a deny list - which is most of them, and all of
      them installed after 30 July 2026 since the installer writes no rules at
      all - and LEFT BEHIND opened with "1 other permissions.deny entries ...
      they were not put there by it" about an entry that does not exist.

      Three shapes are run. Two are the phantom-entry defect, whose trigger is
      the missing `deny` key whatever the parent looks like: a settings.json
      with no `permissions` block at all, and one that has `permissions` with
      `allow` but no `deny`. The second was outside the description that defect
      was first raised under and reaches the same phantom count.

      The third is NO settings.json AT ALL, and it is here to hold the other
      side of a distinction the fix for the two above nearly lost. "There is no
      settings.json" is a FINDING - there is then definitely no deny entry and
      definitely no statusLine key, and `absent` is the true word - while "there
      is one and I could not read it" is the absence of a finding. A first cut
      of that fix keyed the UNKNOWN rows on one error string that is set in both
      cases, which turned the honest `absent` row into `UNKNOWN` on every
      machine with no settings file and would have refused `-All -Apply` there
      outright. This shape is what says so.
    #>
    $bad = @()
    $shapes = @(
        @{ tag = 'no-permissions'; json = "{`r`n  `"model`": `"lwg-test-model`"`r`n}`r`n" },
        @{ tag = 'no-deny-key';    json = "{`r`n  `"permissions`": {`r`n    `"allow`": []`r`n  }`r`n}`r`n" },
        @{ tag = 'no-settings';    json = $null }
    )
    foreach ($s in $shapes) {
        $t = New-CaseTree ('deny-' + $s.tag)
        if ($null -ne $s.json) { [void](Set-CaseSettings -Tree $t -Text $s.json) }
        $r = Invoke-Uninstall -Tree $t

        if ($r.out -match '(?m)^\s+permissions-deny\s+UNKNOWN') {
            $bad += "$($s.tag): the permissions-deny row says UNKNOWN for a file whose contents this run does know"
        }
        if ($r.out -match '(?m)^\s+statusline-key\s+UNKNOWN') {
            $bad += "$($s.tag): the statusline-key row says UNKNOWN for a file whose contents this run does know"
        }

        if ($r.code -ne 0) { $bad += "$($s.tag): exit $($r.code), expected 0" }
        if ($r.out -notmatch 'settings\.json declares no permissions\.deny entries') {
            $bad += "$($s.tag): the honest 'absent' row did not print"
        }
        if ($r.out -match 'other permissions\.deny entries') {
            $bad += "$($s.tag): LEFT BEHIND names a permissions.deny entry for a file that declares none"
        }
        if ($r.out -match '0 of 1 attributable') {
            $bad += "$($s.tag): the footprint counts one deny entry that does not exist"
        }
    }

    Add-Result -Name 'dry run: a settings.json with no permissions.deny key - and no settings.json at all - report absent and invent no entry' `
               -Ok ($bad.Count -eq 0) -Detail ($bad -join '; ')
}

function Test-ThirdPartyStatusLineIsNotOurs {
    <#
      A status line the operator keeps at <ClaudeHome>\ccusage.ps1, with
      statusLine.command pointing at it. ~/.claude is the operator's whole
      Claude Code configuration directory and third-party status lines are
      routinely kept there, so "the target sits somewhere under $ClaudeHome"
      attributed it to this plugin: the plan said it "renders the HH/GM        <!-- doc-claims:ignore -->
      segments" - a sentence an operator says yes to - and -All -Apply removed
      the key. That quotation is VERBATIM and frozen: the row says "renders the
      HH segment" since 3 August 2026, because the GM segment was deleted on
      30 July 2026, and the assertion below moved with it.

      bin\lwg-setup.ps1 writes exactly two spellings, neither of which is this
      one, so the REPORT ONLY path that was already written for a foreign
      status line is the one this must take. The key must also survive -Apply.
    #>
    $t = New-CaseTree 'foreign-statusline'
    $foreign = New-CaseStatusLine (Join-Path $t.claudeHome 'ccusage.ps1')
    $cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $foreign.Replace('\', '/') + '"'
    $sp = Set-CaseSettings -Tree $t -Text ("{`r`n  `"statusLine`": {`r`n    `"type`": `"command`",`r`n    `"command`": `"" + $cmd.Replace('\', '\\').Replace('"', '\"') + "`"`r`n  }`r`n}`r`n")
    $before = [IO.File]::ReadAllText($sp)

    $dry = Invoke-Uninstall -Tree $t
    $app = Invoke-Uninstall -Tree $t -ScriptArgs @('-All', '-Apply')
    $after = [IO.File]::ReadAllText($sp)

    $bad = @()
    if ($dry.out -notmatch '(?i)REPORT ONLY - not attributable') { $bad += 'the dry run does not take the not-attributable path for a status line this plugin never installed' }
    # THE LITERAL MOVED WITH THE STRING IT WATCHES. It named the old two-segment
    # spelling until 3 August 2026 and bin\lwg-uninstall.ps1 stopped emitting
    # that spelling on the same day, when the GM segment - deleted on 30 July
    # 2026 - was swept out of the four strings under bin\ that still promised it.
    # An assertion left pointing at a string nothing can print is not a passing
    # assertion, it is an absent one that reports green.
    if ($dry.out -match '(?i)renders the HH segment')            { $bad += 'the dry run claims a third party''s status line renders this plugin''s segment' }
    if ($after -ne $before)                                      { $bad += '-All -Apply REWROTE settings.json, removing a statusLine key that is not this plugin''s' }
    if (-not [IO.File]::Exists($foreign))                        { $bad += 'the third party''s status line file was deleted' }

    Add-Result -Name 'a statusLine under ~/.claude that this installer never wrote is not attributable and survives -All -Apply' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | dry exit $($dry.code), apply exit $($app.code)")
}

function Test-StatusLineFileKeptWhenKeyHalfCannotRun {
    <#
      THE TWO HALVES ARE ONE DECISION - bin\lwg-uninstall.ps1 section 3 says so
      in those words, and the dry-run text promises "-RemoveStatusLine remove
      the statusLine key AND the installed statusline.ps1". They were two
      decisions. The file deletion was gated on -RemoveStatusLine and
      Test-Path; the key removal was gated on attribution, a successful
      re-read, a SHA match, the JSON surgery and the save.

      The specimen is the cheapest way to break the pair with no lock, no ACL
      and no race: a settings.json with a trailing comma. It READS fine, so the
      run does not refuse; it does not PARSE, and both ConvertFrom-Json calls
      that would have found the statusLine key sat in empty catches - so the
      error was never recorded, the NOTE: disclosure was suppressed, the plan
      row asserted "has no statusLine.command" about a file it could not read,
      and -RemoveStatusLine -Apply deleted the installed statusline.ps1, printed
      APPLIED: 1 change(s), 0 failure(s) and exited 0 with the key still there
      pointing at a file that is gone. Per section 3 that renders an error on
      every message and blanks the whole status row.
    #>
    $t = New-CaseTree 'statusline-halves'
    $sl = New-CaseStatusLine (Join-Path $t.claudeHome 'statusline.ps1')
    $cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $sl.Replace('\', '/') + '"'
    # The trailing comma after the statusLine object is the whole fixture.
    $sp = Set-CaseSettings -Tree $t -Text ("{`r`n  `"statusLine`": {`r`n    `"type`": `"command`",`r`n    `"command`": `"" + $cmd.Replace('\', '\\').Replace('"', '\"') + "`"`r`n  },`r`n}`r`n")
    $before = [IO.File]::ReadAllText($sp)

    $r = Invoke-Uninstall -Tree $t -ScriptArgs @('-RemoveStatusLine', '-Apply')
    $after = [IO.File]::ReadAllText($sp)

    $bad = @()
    if ($r.code -eq 0)                     { $bad += 'EXIT 0 - a statusLine removal that removed one half and not the other reported success' }
    if (-not [IO.File]::Exists($sl))       { $bad += "THE FILE WAS DELETED WHILE THE KEY SURVIVED: $sl" }
    if ($after -ne $before)                { $bad += 'settings.json was rewritten from content this run could not parse' }
    if ($r.out -match '(?i)has no statusLine\.command') { $bad += 'the plan asserts the key is absent from a settings.json it could not parse' }
    if ($r.out -notmatch '(?i)does not parse as JSON')  { $bad += 'the run never discloses that settings.json could not be parsed' }

    Add-Result -Name 'apply: -RemoveStatusLine against an unparseable settings.json removes neither half and does not exit 0' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | exit $($r.code)")
}

function Test-ReparseStateDirIsRefused {
    <#
      A JUNCTION UNDER THE DATA ROOT, POINTING AT A CANARY TREE.

      An operator relocating plugin state off the system drive with
      `mklink /J` is the pattern this plugin's own install page teaches, and
      the state dir accumulates jsonl indefinitely, so there is a reason to.
      The sweep returns the junction, [IO.Directory]::Exists is true for it,
      and `Remove-Item -Recurse -Force` removed the LINK - measured on Windows
      PowerShell 5.1.26100.8875, the target's contents survived intact - after
      which [IO.Directory]::Exists is false and the run printed
      `deleted <path>`, counted a change and exited 0. The operator typed
      DELETE-MY-LWG-LOGS, was told the logs were gone, and every one of them is
      still on the other side of the link.

      The junction is created with `cmd /c mklink /J`, which needs no elevation
      and no admin, and both sides of it are directories this case created
      seconds earlier under the temp root.
    #>
    $t = New-CaseTree 'reparse'
    $canary = New-SeededDataDir (Join-Path $t.elsewhere 'canary-target')
    $before = Get-TreeFingerprint $canary
    $link = Join-Path $t.dataRoot "$PluginName-lwgtestlink"
    $mk = & cmd.exe /c mklink /J "$link" "$canary" 2>&1
    if (-not [IO.Directory]::Exists($link)) {
        throw "could not create the junction fixture at $link ($mk). This case is about a reparse point, so a missing one is an abort, not a skip"
    }

    $r = Invoke-Uninstall -Tree $t -ScriptArgs @('-Apply', '-RemoveData', '-ConfirmToken', $Token)
    $after = Get-TreeFingerprint $canary

    $bad = @()
    if ($after -ne $before)                       { $bad += 'THE CANARY BEHIND THE JUNCTION WAS CHANGED OR DELETED' }
    if ($r.out -match [regex]::Escape("deleted $link")) { $bad += 'the run reports the junction as deleted, while every file it pointed at is still there' }
    if ($r.out -notmatch '(?i)reparse point')     { $bad += 'the run never says the target is a reparse point' }
    if ($r.code -eq 0)                            { $bad += 'EXIT 0 - -RemoveData was asked for a directory that was not removed' }

    # Cleaned up here rather than by the suite's finally: Remove-Item on the
    # work root would walk this link, and this case exists because that is not
    # a thing to do casually. cmd rmdir removes the link only.
    if ([IO.Directory]::Exists($link)) { & cmd.exe /c rmdir "$link" | Out-Null }

    Add-Result -Name 'apply: a state-data directory that is a junction is refused, not reported as deleted' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | exit $($r.code)")
}

function Test-PartialDeletionNamesWhatWent {
    <#
      `Remove-Item -Recurse` deletes children as it walks and throws on the
      first one it cannot remove. Measured on this machine: five files, one
      held open by another process, and the other four were gone before it
      threw. The catch reported `could NOT delete <path> - The process cannot
      access the file`, which an operator reads as "my logs are intact" - and
      health.jsonl and every advisory file were already destroyed.

      The lock is a FileStream opened by THIS process with FileShare::None,
      which is the same condition a running hook produces and is the only seam
      that reaches the branch without mocking anything. It is released in a
      finally.

      This case is why the header's "A DELETION THAT PARTIALLY FAILS ... Not
      covered" line is gone.
    #>
    $t    = New-CaseTree 'partial'
    $data = New-SeededDataDir (Join-Path $t.elsewhere 'redirected-state')
    $locked = Join-Path $data 'lw-watchtower.jsonl'

    $fs = [IO.File]::Open($locked, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $r = Invoke-Uninstall -Tree $t -DataEnv $data -ScriptArgs @('-Apply', '-RemoveData', '-ConfirmToken', $Token)
        $survivors = @(Get-ChildItem -LiteralPath $data -File -Force -ErrorAction SilentlyContinue).Count
    } finally { $fs.Dispose() }

    $bad = @()
    if ($r.code -eq 0)                       { $bad += 'EXIT 0 - a deletion that did not complete reported success' }
    if ($survivors -ne 1)                    { $bad += "$survivors file(s) survived, expected exactly the locked one - the fixture did not reach the partial-delete branch" }
    if ($r.out -notmatch '(?i)PARTIALLY deleted') { $bad += 'the run does not report the deletion as partial' }
    if ($r.out -notmatch "$($SeedFiles.Count - 1) of $($SeedFiles.Count) file\(s\) removed") {
        $bad += "the run does not say how many of the $($SeedFiles.Count) files went"
    }
    if ($r.out -notmatch '(?i)lw-watchtower\.jsonl') { $bad += 'the run does not name the file that is still there' }

    Add-Result -Name 'apply: a deletion that throws part way through says how many files went, not that none did' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | exit $($r.code), survivors $survivors")
}

function Test-EnvPathWithNoOwnershipSignalIsRefused {
    <#
      CLAUDE_PLUGIN_DATA reached `Remove-Item -Recurse -Force` with no ownership
      test of any kind: lib\common.ps1 returns it verbatim ahead of every
      name-based branch, and nothing between there and the delete compared the
      leaf to the plugin name or looked for a file this plugin writes. The
      sibling sweep ten lines away IS name-constrained; the asymmetry was
      between the enumeration path and the resolution path.

      The realistic failure needing no operator error: the variable set once as
      a machine-wide redirect at a directory several tools write into. The
      whole tree went, exit 0, APPLIED: 1 change(s), 0 failure(s).

      The rule this pins is deliberately CONTENT, not leaf name - a bare name
      rule would break the legitimate redirect that Test-ApplyDeletesRedirectedDir
      covers - and deliberately does NOT refuse an EMPTY directory, which
      Test-EmptyStateDirIsStillATarget covers from the other side.
    #>
    $t = New-CaseTree 'env-unowned'
    $other = Join-Path $t.elsewhere 'some-other-tools-data'
    [void][IO.Directory]::CreateDirectory($other)
    foreach ($f in @('other-tool.db', 'notes.md')) {
        [IO.File]::WriteAllText((Join-Path $other $f), "lwg-test-not-ours-$f`n", [Text.UTF8Encoding]::new($false))
    }
    $before = Get-TreeFingerprint $other

    $r = Invoke-Uninstall -Tree $t -DataEnv $other -ScriptArgs @('-Apply', '-RemoveData', '-ConfirmToken', $Token)
    $after = Get-TreeFingerprint $other

    $bad = @()
    if ($after -ne $before)                { $bad += "A DIRECTORY HOLDING NONE OF THIS PLUGIN'S FILES WAS DELETED: $other" }
    if ($r.out -notmatch '(?i)REFUSED')    { $bad += 'the run does not print a refusal' }
    if ($r.code -eq 0)                     { $bad += 'EXIT 0 - -RemoveData was asked for a directory that was not removed' }
    if ($r.out -notlike "*$other*")        { $bad += 'the refusal does not name the directory, so it is invisible to the operator' }

    Add-Result -Name 'apply: an env-named directory holding none of this plugin''s files is refused, not deleted' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | exit $($r.code)")
}

function Test-EnvPathThatContainsTheProfileIsRefused {
    <#
      THE CATASTROPHIC INSTANCE, and it needs one mis-copy rather than a wrong
      belief. The script's own remediation text tells an operator whose state
      dir did not resolve to take the state dir the doctor prints and set
      CLAUDE_PLUGIN_DATA to it, or to pass -DataRoot - two inputs named in one
      sentence, one of which is the parent of the other. Pasting the profile's
      .claude directory took settings.json, projects, todos and history.

      The refusal is on the PROTECTED path being inside the CANDIDATE, not the
      reverse, and Test-LwgPathUnder returns true on equality - so naming the
      directory exactly, which is this specimen, is covered as well as naming
      an ancestor of it. This rule applies to every source, not only the env
      var, because it costs nothing on the name-constrained paths.
    #>
    $t = New-CaseTree 'env-ancestor'
    [void](Set-CaseSettings -Tree $t -Text "{`r`n  `"model`": `"lwg-test-model`"`r`n}`r`n")
    $before = Get-TreeFingerprint $t.claudeHome

    $r = Invoke-Uninstall -Tree $t -DataEnv $t.claudeHome -ScriptArgs @('-Apply', '-RemoveData', '-ConfirmToken', $Token)
    $after = Get-TreeFingerprint $t.claudeHome

    $bad = @()
    if ($after -ne $before)             { $bad += 'THE CLAUDE CONFIG DIRECTORY, INCLUDING settings.json, WAS DELETED' }
    if ($r.out -notmatch '(?i)REFUSED') { $bad += 'the run does not print a refusal' }
    if ($r.code -eq 0)                  { $bad += 'EXIT 0 - -RemoveData was asked for a directory that was not removed' }

    Add-Result -Name 'apply: an env-named directory that IS the Claude config directory is refused' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | exit $($r.code)")
}

function Test-RestoreWithARemovalFlagRefuses {
    <#
      -RestoreSettings is a self-contained branch and every path out of it is
      an `exit`, so the dry-run block and the apply block below it are
      unreachable once it is set. Nothing inside it consulted -RemoveData,
      -RemoveStatusLine, -RemovePermissions or -ConfirmToken.

      APPLY FORM: restored the file, printed RESTORED, and exited 0 - the code
      the header defines as "every requested removal was made" - with the
      removal never attempted and never mentioned.

      DRY-RUN FORM: exited 0 at the DRY RUN line, walking around the
      -RemoveData/unlocatable guard whose exit-2 behaviour
      Test-UnresolvableRemoveDataDryRunExitsNonZero exists to assert. A
      one-flag combination defeated a guarantee this suite establishes, and
      the suite stayed green.

      Both forms are asked. Neither may exit 0, and neither may write.
    #>
    $t = New-CaseTree 'restore-plus-removal'
    $data = New-SeededDataDir (Join-Path $t.elsewhere 'redirected-state')
    $sp = Set-CaseSettings -Tree $t -Text "{`r`n  `"model`": `"lwg-test-current`"`r`n}`r`n"
    $bak = Join-Path $t.claudeHome 'settings.json.lwg-20260801-120000.bak'
    [IO.File]::WriteAllText($bak, "{`r`n  `"model`": `"lwg-test-backup`"`r`n}`r`n", [Text.UTF8Encoding]::new($false))
    $beforeSettings = [IO.File]::ReadAllText($sp)
    $beforeData     = Get-TreeFingerprint $data

    $dry = Invoke-Uninstall -Tree $t -DataEnv $data -ScriptArgs @('-RestoreSettings', $bak, '-RemoveData', '-ConfirmToken', $Token)
    $app = Invoke-Uninstall -Tree $t -DataEnv $data -ScriptArgs @('-RestoreSettings', $bak, '-Apply', '-RemoveData', '-ConfirmToken', $Token)

    $bad = @()
    if ($dry.code -eq 0) { $bad += 'the dry-run form exits 0 while carrying a removal flag it silently drops' }
    if ($app.code -eq 0) { $bad += 'EXIT 0 - the apply form reports success for a removal it never attempted' }
    if ($dry.out -notmatch '(?i)REFUSED') { $bad += 'the dry-run form prints no refusal' }
    if ($app.out -notmatch '(?i)REFUSED') { $bad += 'the apply form prints no refusal' }
    if ([IO.File]::ReadAllText($sp) -ne $beforeSettings) { $bad += 'settings.json was restored by a run that also carried a removal flag' }
    if ((Get-TreeFingerprint $data) -ne $beforeData)     { $bad += 'THE STATE DATA WAS DELETED BY A RESTORE RUN' }

    Add-Result -Name '-RestoreSettings together with a removal flag is refused, and neither half happens' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | dry exit $($dry.code), apply exit $($app.code)")
}

function Test-RestoreIntoAnAbsentSettingsFileLands {
    <#
      THE CASE A RESTORE IS ACTUALLY FOR. With settings.json deleted, $settings
      is $null, and $settings.sha - which PowerShell evaluates quietly to $null
      rather than throwing - was passed to a [Parameter(Mandatory)][string]
      parameter that rejects $null and '' alike AT BIND TIME. The exception
      reached the outer catch and the operator got
      "Cannot bind argument to parameter 'ExpectedSha' because it is an empty
      string" and exit 3, with nothing restored.

      There is nothing to hash, nothing to back up and nothing to clobber, so
      the restore must land and must say that no concurrent-change check was
      possible.
    #>
    $t = New-CaseTree 'restore-absent'
    [void][IO.Directory]::CreateDirectory($t.claudeHome)
    $sp = Join-Path $t.claudeHome 'settings.json'
    $bakText = "{`r`n  `"model`": `"lwg-test-backup`"`r`n}`r`n"
    $bak = Join-Path $t.claudeHome 'settings.json.lwg-20260801-120000.bak'
    [IO.File]::WriteAllText($bak, $bakText, [Text.UTF8Encoding]::new($false))

    $r = Invoke-Uninstall -Tree $t -ScriptArgs @('-RestoreSettings', $bak, '-Apply')

    $bad = @()
    if ($r.code -ne 0)                     { $bad += "exit $($r.code), expected 0" }
    if ($r.out -match '(?i)Cannot bind argument') { $bad += 'the run fails with a parameter-binding error naming an internal parameter' }
    if (-not [IO.File]::Exists($sp))       { $bad += 'settings.json was not created from the backup' }
    elseif ([IO.File]::ReadAllText($sp) -ne $bakText) { $bad += 'the restored settings.json does not match the backup byte for byte' }
    if ($r.out -notmatch '(?i)no concurrent-change check was possible') { $bad += 'the run does not disclose that no concurrent-change check was made' }

    Add-Result -Name '-RestoreSettings -Apply into an absent settings.json creates it, and says no change check was possible' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | exit $($r.code)")
}

# ---------------------------------------------------------------------------
# RUN
# ---------------------------------------------------------------------------

Write-Output "LW-WATCHTOWER uninstaller footprint suite"
Write-Output "  script under test: $UninstallPath"
Write-Output ''

try {
    if (-not (Test-Path -LiteralPath $UninstallPath -PathType Leaf)) {
        $script:Aborted = "bin\lwg-uninstall.ps1 not found at $UninstallPath"
        throw $script:Aborted
    }

    $script:Work = Join-Path ([IO.Path]::GetTempPath()) ("lwg-uninstall-test-" + [Guid]::NewGuid().ToString('N').Substring(0, 10))
    [void][IO.Directory]::CreateDirectory($script:Work)

    Test-DryRunListsRedirectedDir
    Test-DryRunWithRemoveDataDeletesNothing
    Test-ApplyDeletesRedirectedDir
    Test-FallbackUsedWhenEnvUnset
    Test-UnresolvableIsNotAbsent
    Test-UnresolvableRemoveDataApplyExitsNonZero
    Test-UnresolvableRemoveDataDryRunExitsNonZero
    Test-EmptyStateDirIsStillATarget
    Test-DryRunEmptyStateDirPlannedAsOne
    Test-ResolvableWithNoPluginDirIsNotUnresolvable
    Test-WrongTokenDeletesNothing
    Test-PlanMatchesDeletion
    Test-CanonicalDenyRulesAllAttributed
    Test-MissingDenyKeyInventsNoEntry
    Test-ThirdPartyStatusLineIsNotOurs
    Test-StatusLineFileKeptWhenKeyHalfCannotRun
    Test-ReparseStateDirIsRefused
    Test-PartialDeletionNamesWhatWent
    Test-EnvPathWithNoOwnershipSignalIsRefused
    Test-EnvPathThatContainsTheProfileIsRefused
    Test-RestoreWithARemovalFlagRefuses
    Test-RestoreIntoAnAbsentSettingsFileLands
}
catch {
    if (-not $script:Aborted) { $script:Aborted = $_.Exception.Message }
}
finally {
    if ($script:Work -and (Test-Path -LiteralPath $script:Work)) {
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$total  = $script:Results.Count
$failed = $total - $script:Pass

Write-Output ''
# THE RESULT: AND EXIT: TOKENS ARE A CONTRACT, NOT DECORATION. CONTRIBUTING.md's
# pre-PR checklist and .github\PULL_REQUEST_TEMPLATE.md both ask a contributor to
# paste "the RESULT: and EXIT: lines from each" of the eight files in tests\.
# This file printed neither until 3 August 2026 - its summary was correct and in
# a format of its own - so the instruction could not be followed for one of the
# eight, and the contributor had no way to tell a suite that omits the tokens
# from a run of their own that went wrong. The likely outcomes were seven pastes
# and a note, or eight pastes one of which was invented; pushing anybody toward
# reconstructing output is the wrong shape on a project whose rule is that an
# unverified thing must be said to be unverified.
#
# It cannot silently drop out again: tests\doc_claims.ps1 runs every sibling
# suite in a child process and reads both tokens off the stdout it already
# holds, and fails when one is missing.
#
# THE LITERAL `case(s)` IS LOAD-BEARING and must survive any rewording of these
# lines. doc_claims decides which suites are BEHAVIOURAL by matching
# `N of M case(s)` in each suite's own output rather than from a list. Spelling
# it `cases` would take this file out of that set, drop the derived behavioural
# count from five to four, and fail every page in the tree that states five.
if ($script:Aborted) {
    Write-Output "ABORTED: $($script:Aborted)"
    Write-Output "RESULT: $script:Pass of $total case(s) had run when it stopped. Nothing about the uninstaller was established."
    Write-Output 'EXIT: 2 (the uninstaller was NOT exercised, which is not the same as passing)'
    exit 2
}
if ($total -eq 0) {
    Write-Output 'ABORTED: no case ran. An empty set is not a pass.'
    Write-Output 'RESULT: no case ran, so nothing about the uninstaller was established'
    Write-Output 'EXIT: 2 (zero cases run is an abort, never an empty-set pass)'
    exit 2
}
Write-Output ("RESULT: {0} of {1} case(s) passed." -f $script:Pass, $total)
if ($failed -gt 0) {
    Write-Output "$failed case(s) FAILED."
    Write-Output 'EXIT: 1 (at least one case failed - read the per-case lines above. A case'
    Write-Output '         reporting a surviving directory after a confirmed deletion means'
    Write-Output '         the script tells an operator it removed data it did not remove.)'
    exit 1
}
Write-Output 'EXIT: 0 (every case passed - the footprint named the state data, the deletion'
Write-Output '         removed exactly what it listed, and an unresolvable data directory'
Write-Output '         exited 2 rather than reporting a no-op deletion as a success)'
exit 0
