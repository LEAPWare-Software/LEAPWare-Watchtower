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

function Get-LeftBehind {
    <#
      The LEFT BEHIND block of the report, as one string, or '' when there is
      no such block. It runs from the `LEFT BEHIND` heading to the
      `AND WHAT THIS SCRIPT CANNOT SEE` heading below it.

      SCOPED RATHER THAN SWEPT, because "the report mentions it somewhere" and
      "the report lists it under what was left behind" are different claims and
      the whole subject of the hook cases is that the second one was never true.
      A -match against the whole of stdout would be satisfied by the plan row,
      which is exactly the thing that was already there.
    #>
    param([string]$Out)

    $lines = @($Out -split "`r?`n")
    $from = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*LEFT BEHIND\s*$') { $from = $i + 1; break }
    }
    if ($from -lt 0) { return '' }
    $out = @()
    for ($i = $from; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*AND WHAT THIS SCRIPT CANNOT SEE\s*$') { break }
        $out += $lines[$i]
    }
    return ($out -join "`n")
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

function New-HookSettings {
    <#
      A settings.json whose `hooks` block holds one group per supplied command
      string, each in the canonical CLI shape:

          "hooks": { "<event>": [ { "hooks": [ { "type": "command",
                                                 "command": "<the string>" } ] } ] }

      One group per command, and each group gets its own invented event name, so
      the number of REGISTRATIONS in the file is exactly the number of strings
      handed in. That is the number the footprint has to report, and a helper
      that packed several commands into one group could not express the
      difference between a count of entries and a count of anything else.

      Written as TEXT rather than through ConvertTo-Json for the reason the
      header gives for Set-CaseSettings, and because one shape below is a
      settings.json that does not parse.
    #>
    param([string[]]$Commands)

    $groups = @()
    $i = 0
    foreach ($c in $Commands) {
        $i++
        $esc = $c.Replace('\', '\\').Replace('"', '\"')
        $groups += ("  `"LwgTestEvent$i`": [`r`n" +
                    "    {`r`n      `"hooks`": [`r`n" +
                    "        { `"type`": `"command`", `"command`": `"$esc`" }`r`n" +
                    "      ]`r`n    }`r`n  ]")
    }
    return ("{`r`n  `"hooks`": {`r`n" + ($groups -join ",`r`n") + "`r`n  }`r`n}`r`n")
}

function Test-HookRegistrationInSettingsIsDetectedAndCounted {
    <#
      THE SCAN IN SECTION 2 EXISTS FOR ONE PURPOSE, stated in the script beside
      it: "a hand-added entry pointing at these scripts would survive the
      junction's removal and then fail on every event." It found nothing.

      Three defects in five lines, all of them live until this case:

        1. The plugin-root needle was `($pluginRoot -replace '\\', '\\\\')`. In
           a .NET replacement string a backslash is literal, so that is FOUR
           backslashes per separator where ConvertTo-Json emits TWO. Measured
           under Windows PowerShell 5.1: needle `C:\\\\repos\\\\governance`
           (len 25) against JSON `C:\\repos\\governance` (len 21), -like False.
           The needle could not match any settings.json ever written.
        2. `$hookRefs++` ran at most once per needle over a three-element array,
           so it counted needle KINDS with a ceiling of 3 - and the row printed
           it as a count of references.
        3. Nothing carried a hit into LEFT BEHIND.

      THE CLONE PATH IS THE WHOLE POINT of the first needle failing too. This
      repository is checked out wherever it is checked out; the junction is what
      supplies the plugin's name, not the directory. So needle 1 ($name) misses
      unless the checkout path happens to contain it, needle 2
      (CLAUDE_PLUGIN_ROOT) misses because bin\lwg-setup.ps1 substitutes the
      literal before writing, and needle 3 could not match at all. The operator
      was told `0 reference(s)`, removed the junction on the script's own
      instruction, and every one of those entries then fired on every event of
      every session pointing at an unloaded script.

      FIVE REGISTRATIONS, FOUR OF THEM THIS PLUGIN'S, in the four spellings a
      hand-added entry can legally take:

        * an absolute path into THIS checkout naming a script hooks.json
          registers - the case needle 3 was for;
        * an absolute path into THIS checkout naming a script hooks.json does
          NOT register. THIS ONE IS ONLY REACHABLE BY THE ROOT, and it is here
          because without it the leaf rule below would cover for a broken root
          rule and needle 3's successor would have no case of its own. Running
          the doctor from a SessionStart hook is the realistic shape.
        * an unsubstituted ${CLAUDE_PLUGIN_ROOT} - the case needle 2 was for -
          POINTED AT A SCRIPT hooks.json DOES NOT REGISTER, for exactly the same
          reason. It named lib/session_start.ps1 until 3 August 2026, which is a
          shipped leaf, so the leaf rule covered for the CLAUDE_PLUGIN_ROOT rule
          and that branch could be deleted whole with this case still green.
          It then named bin/lwg-sitrep.ps1, which satisfied that constraint
          until the script was deleted; a fixture naming a .ps1 this plugin does
          NOT ship is the decoy's shape, not this one's, so it moved again.
          bin/lwg-update.ps1 is in this plugin and is not a hook, so only the
          CLAUDE_PLUGIN_ROOT signal can reach it.

          THE STRING IS THE FIXTURE, NOT A DEPENDENCY ON THE FILE. The signal
          this branch pins is bin\lwg-uninstall.ps1's `$Text.Contains(
          'CLAUDE_PLUGIN_ROOT')`, which reads the registration text and never
          touches the disk, so the case would go on passing with a script that
          does not exist. That is exactly why the name has to be maintained by
          hand: nothing here fails when it rots, and a fixture naming a deleted
          script quietly stops standing for the thing the case says it does.
        * an absolute path into a DIFFERENT checkout, recognisable only by the
          script leaf name, which is the shape bin\lwg-setup.ps1's own
          Get-HookIdentity keys on because the root is exactly the thing that
          varies between the machine that wrote the entry and the machine
          reading it.

      The fifth names a .ps1 this plugin does not ship, from a path that is
      neither checkout, and must NOT be counted or named: a scan that claims
      everything is a scan that says nothing.

      THE NAMING ASSERTIONS GO THROUGH Get-LeftBehind, not through the whole of
      stdout. Every one of these paths appears in the report the moment the
      script echoes the settings file it read, so a sweep of $r.out would be
      satisfied by output no operator could act on - and it coupled this case to
      the Add-Left call, whose own case is below. "The report mentions it" and
      "the report lists it under LEFT BEHIND" are different claims and this file
      has a helper for the second one.
    #>
    $t = New-CaseTree 'hooks-detect'
    $mine  = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $Root 'lib\gate_delegate.ps1') + '"'
    $notAHook = Join-Path $Root 'bin\lwg-doctor.ps1'
    $rootOnly = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $notAHook + '"'
    $unsub = 'powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/bin/lwg-update.ps1"'
    $other = Join-Path $t.elsewhere 'another-checkout\lib\supervisor.ps1'
    $far   = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $other + '" -HookEvent Stop'
    $alien = Join-Path $t.elsewhere 'some-other-tool\bin\unrelated_thing.ps1'
    $decoy = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $alien + '"'
    [void](Set-CaseSettings -Tree $t -Text (New-HookSettings -Commands @($mine, $rootOnly, $unsub, $far, $decoy)))

    $r = Invoke-Uninstall -Tree $t
    $left = Get-LeftBehind $r.out

    $bad = @()
    if ($r.code -ne 0) { $bad += "exit $($r.code), expected 0" }
    if ($r.out -notmatch 'holds 4 reference\(s\) to this plugin') {
        $m = [regex]::Match($r.out, 'holds (\d+) reference\(s\)')
        $bad += "the hooks row does not report 4 references - it reports '$(if ($m.Success) { $m.Value } else { '<no such row>' })'"
    }
    if ($left -notlike "*$(Join-Path $Root 'lib\gate_delegate.ps1')*") {
        $bad += 'LEFT BEHIND never names the registration that points into this checkout, so the operator cannot find it'
    }
    if ($left -notlike "*$notAHook*")        { $bad += 'LEFT BEHIND never names the registration that only the clone root can identify - a script in this checkout that hooks.json does not register' }
    if ($left -notlike "*$other*")           { $bad += 'LEFT BEHIND never names the registration from another checkout, which the leaf name identifies' }
    if ($left -notmatch 'lwg-update\.ps1')   { $bad += 'LEFT BEHIND never names the unsubstituted ${CLAUDE_PLUGIN_ROOT} registration, which nothing but that signal can reach' }
    if ($left -like "*$alien*")              { $bad += "a .ps1 this plugin does not ship was attributed to it: $alien" }

    Add-Result -Name 'dry run: hand-added settings.json hook registrations are found in all three spellings, and a foreign one is not' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | exit $($r.code)")
}

function Test-HookLeafMatchIsCaseInsensitive {
    <#
      `Supervisor.PS1` AND `supervisor.ps1` ARE THE SAME FILE ON WINDOWS, and
      the leaf extraction did not know it. Get-PluginHookLeaves compiled its own
      extraction with (?i) and the leaf set is a PowerShell hashtable, whose
      comparer is case-insensitive - so the ONE case-sensitive step in the chain
      was the extraction inside Get-HookRefReason. Measured in isolation:

          powershell -File "C:\some\other\lib\Supervisor.PS1"   0 matches
          powershell -File "C:\some\other\lib\supervisor.ps1"   1 match

      End to end that is a live registration reported as `0 reference(s)`, which
      is this scan's founding defect surviving in a narrow form. An operator
      typing the path by hand, a tool that title-cases, or a settings.json
      carried from a machine where it was written that way all produce it.

      TWO SHAPES. An upper-cased SHIPPED leaf must be found; an upper-cased leaf
      this plugin does NOT ship must still not be, so the fix is a case rule and
      not a loosening that makes every .ps1 ours.
    #>
    $bad = @()

    $t1 = New-CaseTree 'hooks-case-ours'
    $mixed = Join-Path $t1.elsewhere 'another-checkout\lib\Supervisor.PS1'
    [void](Set-CaseSettings -Tree $t1 -Text (New-HookSettings -Commands @(
        'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $mixed + '" -HookEvent Stop')))
    $r1 = Invoke-Uninstall -Tree $t1
    $left1 = Get-LeftBehind $r1.out

    if ($r1.code -ne 0) { $bad += "ours: exit $($r1.code), expected 0" }
    if ($r1.out -notmatch 'holds 1 reference\(s\) to this plugin') {
        $m = [regex]::Match($r1.out, 'holds (\d+) reference\(s\)')
        $bad += "ours: a registration naming Supervisor.PS1 reports '$(if ($m.Success) { $m.Value } else { '<no such row>' })' - the leaf match is case-sensitive"
    }
    if ($left1 -notlike "*$mixed*") { $bad += 'ours: LEFT BEHIND does not name the upper-cased registration' }

    $t2 = New-CaseTree 'hooks-case-theirs'
    $alien = Join-Path $t2.elsewhere 'some-other-tool\bin\Unrelated_Thing.PS1'
    [void](Set-CaseSettings -Tree $t2 -Text (New-HookSettings -Commands @(
        'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $alien + '"')))
    $r2 = Invoke-Uninstall -Tree $t2
    $left2 = Get-LeftBehind $r2.out

    if ($r2.code -ne 0) { $bad += "theirs: exit $($r2.code), expected 0" }
    if ($r2.out -notmatch 'holds 0 reference\(s\) to this plugin') { $bad += 'theirs: an upper-cased .ps1 this plugin does not ship was attributed to it' }
    if ($left2 -match '(?i)hook registration') { $bad += 'theirs: LEFT BEHIND warns about a registration that is not this plugin''s' }

    Add-Result -Name 'a hook registration naming a shipped script in a different CASE is found; a foreign one in any case is not' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | exits $($r1.code)/$($r2.code)")
}

function Test-HookPathInArgsArrayIsRead {
    <#
      THE SHAPE hooks.json ITSELF USES, and it had no case. This plugin's
      hooks/hooks.json writes `"command": "powershell"` with the script path in
      an `args` ARRAY, so a copy-paste out of it into settings.json - which is
      exactly how an operator reproduces a registration by hand - puts the only
      identifying string somewhere the `command` member never sees.
      bin\lwg-setup.ps1 documents the same split at :1433 and :1453 and its own
      Get-HookScriptPaths walks for it rather than reading a known field.

      Proved non-equivalent rather than assumed: with the args append removed
      from Get-SettingsHookRefs, this fixture drops from 1 reference to 0 while
      every other case in this file stays green.

      THE PATH IS AN ABSOLUTE ONE INTO THIS CHECKOUT, naming a script hooks.json
      does not register. That is deliberate for the same reason as the two
      fixtures above: an args array holding ${CLAUDE_PLUGIN_ROOT} or a shipped
      leaf would be found by a scan that never looked at args at all.

      IT NAMED bin\lwg-status.ps1 UNTIL THAT SCRIPT WAS DELETED. Nothing failed
      when it went - the signal here is `$norm.Contains($RootNorm)`, a string
      test over the registration, with no Test-Path anywhere in the chain - so
      the case stayed green while its fixture named a file this plugin no longer
      ships, which is the decoy's shape rather than this one's. bin\lwg-config.ps1
      is shipped, is in this checkout, and is not a hooks.json leaf.

      The negative half is the same shape with an args array naming somebody
      else's script, so this pins reading args rather than counting any entry
      that happens to have them.
    #>
    $bad = @()

    $t1 = New-CaseTree 'hooks-args-ours'
    $ours = (Join-Path $Root 'bin\lwg-config.ps1')
    $j1 = "{`r`n  `"hooks`": {`r`n    `"LwgTestEvent1`": [`r`n      {`r`n        `"hooks`": [`r`n" +
          "          { `"type`": `"command`", `"command`": `"powershell`", `"args`": [ `"-NoProfile`", `"-File`", `"" +
          $ours.Replace('\', '\\') + "`" ] }`r`n        ]`r`n      }`r`n    ]`r`n  }`r`n}`r`n"
    [void](Set-CaseSettings -Tree $t1 -Text $j1)
    $r1 = Invoke-Uninstall -Tree $t1
    $left1 = Get-LeftBehind $r1.out

    if ($r1.code -ne 0) { $bad += "ours: exit $($r1.code), expected 0" }
    if ($r1.out -notmatch 'holds 1 reference\(s\) to this plugin') {
        $m = [regex]::Match($r1.out, 'holds (\d+) reference\(s\)')
        $bad += "ours: a registration whose path is in an args array reports '$(if ($m.Success) { $m.Value } else { '<no such row>' })' - args is not being read"
    }
    if ($left1 -notlike "*$ours*") { $bad += 'ours: LEFT BEHIND does not name the script, which is only in the args array' }

    $t2 = New-CaseTree 'hooks-args-theirs'
    $theirs = Join-Path $t2.elsewhere 'some-other-tool\bin\unrelated_thing.ps1'
    $j2 = "{`r`n  `"hooks`": {`r`n    `"LwgTestEvent1`": [`r`n      {`r`n        `"hooks`": [`r`n" +
          "          { `"type`": `"command`", `"command`": `"powershell`", `"args`": [ `"-NoProfile`", `"-File`", `"" +
          $theirs.Replace('\', '\\') + "`" ] }`r`n        ]`r`n      }`r`n    ]`r`n  }`r`n}`r`n"
    [void](Set-CaseSettings -Tree $t2 -Text $j2)
    $r2 = Invoke-Uninstall -Tree $t2

    if ($r2.code -ne 0) { $bad += "theirs: exit $($r2.code), expected 0" }
    if ($r2.out -notmatch 'holds 0 reference\(s\) to this plugin') { $bad += 'theirs: an args array naming somebody else''s script was attributed to this plugin' }

    Add-Result -Name 'a registration whose script path is in the args array - the shape hooks.json itself uses - is read' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | exits $($r1.code)/$($r2.code)")
}

function Test-HookRefsCountsEntriesNotNeedleKinds {
    <#
      THE CEILING. `foreach ($needle in @(a, b, c)) { if (match) { $hookRefs++ } }`
      increments once per needle, so the largest number that construct could
      ever print was 3 - and line 470 printed it as "settings.json holds
      $hookRefs reference(s) to this plugin under `hooks`".

      Seven registrations, every one of them an absolute path into THIS
      checkout, is the specimen that separates a count of references from a
      count of needle kinds: the two agree at 0 and at 1 and part company here.
      Seven is also realistic - bin\lwg-setup.ps1 -HookMode standalone writes a
      registration per event, and hooks\hooks.json declares eight.

      The number is asserted EXACTLY. "At least one" would be satisfied by the
      broken construct the moment any needle matched, which is the state this
      case exists to tell apart from a correct one.
    #>
    $t = New-CaseTree 'hooks-count'
    $events = @('SessionStart', 'PreToolUse', 'PostToolUse', 'SubagentStart',
                'SubagentStop', 'Stop', 'StopFailure')
    $cmds = @($events | ForEach-Object {
        'powershell -NoProfile -ExecutionPolicy Bypass -File "' +
        (Join-Path $Root 'lib\supervisor.ps1') + '" -HookEvent ' + $_
    })
    [void](Set-CaseSettings -Tree $t -Text (New-HookSettings -Commands $cmds))

    $r = Invoke-Uninstall -Tree $t

    $bad = @()
    if ($r.code -ne 0) { $bad += "exit $($r.code), expected 0" }
    if ($r.out -notmatch "holds $($cmds.Count) reference\(s\) to this plugin") {
        $m = [regex]::Match($r.out, 'holds (\d+) reference\(s\)')
        $bad += "$($cmds.Count) registrations are reported as '$(if ($m.Success) { $m.Value } else { '<no such row>' })' - the count is of needle kinds, not of references"
    }

    Add-Result -Name "dry run: $($events.Count) hook registrations are counted as $($events.Count), not capped at the number of needles" `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | exit $($r.code)")
}

function Test-HookRegistrationReachesLeftBehind {
    <#
      THE ONE THING THE SCAN WAS WRITTEN TO WARN ABOUT WAS THE ONE THING THAT
      NEVER REACHED THE WARNING LIST. Add-Left is called for the junction, the
      unattributable statusLine key, permissions, the data directories and the
      clone; there was no call anywhere for a surviving settings.json hook
      entry, and none guarded by the count.

      ORDER IS THE PART THAT MATTERS. Section 1 prints the exact
      `cmd /c rmdir "<link>"` that removes the junction. Once the junction is
      gone, a settings.json entry pointing into the clone fires on every event
      and finds nothing - so the warning has to be in front of the operator
      BEFORE they run that command, not discoverable afterwards in
      docs/install.md.

      THREE SHAPES, because an unconditional warning is not a finding:

        present    one registration into this checkout - it must be named in
                   LEFT BEHIND, with the ordering instruction.
        absent     a settings.json whose hooks block holds only a foreign
                   registration - the row must say 0 and LEFT BEHIND must not
                   invent an entry. This is the half that stops the fix being
                   "always warn", which would be the same defect wearing the
                   opposite sign.
        unreadable a settings.json that reads but does not parse. `0
                   reference(s)` there is an assertion about a file this run
                   never inspected - the same class of untruth as the phantom
                   permissions.deny entry two cases below - so it must say it
                   did not look, and say so in LEFT BEHIND too.
    #>
    $bad = @()

    # --- present -----------------------------------------------------------
    $t1 = New-CaseTree 'hooks-left-present'
    $cmd1 = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $Root 'lib\post_edit.ps1') + '"'
    [void](Set-CaseSettings -Tree $t1 -Text (New-HookSettings -Commands @($cmd1)))
    $r1 = Invoke-Uninstall -Tree $t1
    $left1 = Get-LeftBehind $r1.out

    if ($r1.code -ne 0)                                     { $bad += "present: exit $($r1.code), expected 0" }
    if ($left1 -eq '')                                      { $bad += 'present: the run printed no LEFT BEHIND block at all' }
    if ($left1 -notmatch '(?i)hook registration')           { $bad += 'present: LEFT BEHIND does not mention the surviving hook registration' }
    if ($left1 -notlike "*$(Join-Path $Root 'lib\post_edit.ps1')*") { $bad += 'present: LEFT BEHIND does not name the entry, so the operator cannot find it' }
    if ($left1 -notmatch '(?i)BEFORE you remove the junction') { $bad += 'present: LEFT BEHIND does not say to remove the entry BEFORE the junction, which is the order that matters' }

    # --- absent ------------------------------------------------------------
    $t2 = New-CaseTree 'hooks-left-absent'
    $alien = Join-Path $t2.elsewhere 'some-other-tool\bin\unrelated_thing.ps1'
    [void](Set-CaseSettings -Tree $t2 -Text (New-HookSettings -Commands @(
        'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $alien + '"')))
    $r2 = Invoke-Uninstall -Tree $t2
    $left2 = Get-LeftBehind $r2.out

    if ($r2.code -ne 0)                           { $bad += "absent: exit $($r2.code), expected 0" }
    if ($r2.out -notmatch 'holds 0 reference\(s\) to this plugin') { $bad += 'absent: the hooks row does not report 0 references for a file holding none' }
    if ($left2 -match '(?i)hook registration')    { $bad += 'absent: LEFT BEHIND warns about a hook registration that does not exist' }

    # --- unreadable --------------------------------------------------------
    $t3 = New-CaseTree 'hooks-left-unreadable'
    # The trailing comma is the whole fixture: it READS and does not PARSE.
    [void](Set-CaseSettings -Tree $t3 -Text ("{`r`n  `"hooks`": {`r`n    `"LwgTestEvent1`": []`r`n  },`r`n}`r`n"))
    $r3 = Invoke-Uninstall -Tree $t3
    $left3 = Get-LeftBehind $r3.out

    if ($r3.out -match 'holds 0 reference\(s\) to this plugin') { $bad += 'unreadable: the hooks row asserts 0 references about a settings.json it could not parse' }
    if ($r3.out -notmatch '(?i)not inspected for hook')         { $bad += 'unreadable: the hooks row does not say the file was never inspected' }
    if ($left3 -notmatch '(?i)hook registration')               { $bad += 'unreadable: LEFT BEHIND does not name the hook entries it could not look for' }

    Add-Result -Name 'a surviving settings.json hook registration reaches LEFT BEHIND - and is not invented when there is none' `
               -Ok ($bad.Count -eq 0) -Detail (($bad -join '; ') + " | exits $($r1.code)/$($r2.code)/$($r3.code)")
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
    Test-HookRegistrationInSettingsIsDetectedAndCounted
    Test-HookLeafMatchIsCaseInsensitive
    Test-HookPathInArgsArrayIsRead
    Test-HookRefsCountsEntriesNotNeedleKinds
    Test-HookRegistrationReachesLeftBehind
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
