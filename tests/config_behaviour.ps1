#requires -version 5
<#
  LW-WATCHTOWER config WRITE-PATH regression suite - bin\lwg-config.ps1.

      powershell -NoProfile -ExecutionPolicy Bypass -File tests\config_behaviour.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File tests\config_behaviour.ps1 -Verbose

  WHAT THIS IS

  bin\lwg-config.ps1 backs /lw-watchtower:config. It is 471 lines of WRITE PATH -
  the only supported way to change a `modules` flag, globally or for one repo -
  and until this file existed NOTHING IN tests\ HAD EVER EXECUTED ANY OF IT. Not
  the refusals it is built around, not the two-phase preview, not the surgical
  JSON edit, not the exit-2 read-back. tests\toggle_behaviour.ps1 covers the
  OTHER writer of the same file (bin\lwg-toggle.ps1, the `interaction.delegate`
  flag) and has done since the three defects in it were found; this one covers
  the module switchboard.

  THE TWO IT PINS

    #92  the unknown-module refusal tested membership with `-notcontains`, which
         in PowerShell is case-INSENSITIVE, while its own hint says "Module names
         are case-sensitive". So the one input that hint describes never reached
         the refusal: `-Module Git_Hygiene` passed validation, passed the
         registry lookup (an [ordered] hashtable is case-insensitive too) and
         died in the JSON editor, which matches with -ceq. At global scope that
         printed "config.json has no modules.Git_Hygiene member to change (its
         `modules` block has DRIFTED FROM THE REGISTRY)" and sent the operator to
         a doctor that reports the config healthy - a typo diagnosed as file
         corruption. WITHOUT -Apply it was worse: a full plan under WHAT THIS
         DOES, "PREVIEW ONLY", exit 0. A change promised that could never be
         made. Section A.

    #91  `-Repo <owner/name>` was taken verbatim: its SHAPE was never validated
         and it was never reconciled against the `repos` keys already in the
         file. The JSON writer matches member names with -ceq (JSON names are
         case-sensitive, bin\lwg-cmdlib.ps1:128) and EVERY reader - the OVERRIDE
         column of this command's own table, Test-LwgModule, the exit-2
         verification - resolves repos.<slug> by PowerShell property lookup,
         which is not. Two wrong outcomes follow from that one gap, and a third
         from the missing shape check:
           - on a file holding "Owner/Name", -Repo owner/name reads as a live
             override and writes as a missing one, so -Clear prints "Nothing to
             clear" and exits 0 over an override the same command has just
             printed as effective;
           - an -On/-Off in that state builds an edit carrying BOTH spellings,
             and cannot write it: two `repos` keys differing only in case make
             PowerShell 5.1's ConvertFrom-Json refuse the document, so the
             command's own last-gate parse check catches its output and exits 1
             with "This is a bug in this script" - after printing the full plan.
             The operator is sent to report a bug in the command, the override
             is unchanged, and nothing names the slug. That gate is the only
             thing between this defect and a config.json no hook can load;
           - -Repo https://github.com/owner/name.git wrote exactly that string as
             a `repos` key. lib\common.ps1's Get-LwgRepoInfo emits owner/name and
             nothing else, so no hook could ever match it - and the exit-2 check
             could not tell, because it re-resolves the same bad key through the
             same case-insensitive lookup that just wrote it. A write nothing
             will honour, reported as verified.
         Section B.

  ---------------------------------------------------------------------------
  HOW A CASE IS RUN, AND THE SANDBOX CONTRACT
  ---------------------------------------------------------------------------
  In a real child process, against a BYTE COPY of bin\ and lib\ under a scratch
  plugin root built at runtime from [IO.Path]::GetTempPath():

      <scratch>\plugin\bin\lwg-config.ps1     copied from the repo
      <scratch>\plugin\bin\lwg-cmdlib.ps1     copied from the repo
      <scratch>\plugin\lib\common.ps1         copied from the repo
      <scratch>\plugin\config.json            SEEDED PER CASE

  bin\lwg-config.ps1 resolves its own config as
  (Split-Path -Parent $PSScriptRoot)\config.json, so a copied tree redirects the
  write with no seam at all - the same arrangement tests\toggle_behaviour.ps1
  uses and for the same reason: every case below runs UNCHANGED against the
  pre-fix file. Nothing here drives -ConfigPath, so nothing here depends on a
  parameter the baseline might not have.

  Around every child, four environment variables are set and restored in a
  finally, for the reasons tests\setup_merge.ps1:55-61 and
  tests\toggle_behaviour.ps1:92-101 already document:

      USERPROFILE                    -> <scratch>\profile
      CLAUDE_PLUGIN_DATA             -> <scratch>\data
      CLAUDE_PLUGIN_ROOT             cleared
      CLAUDE_CODE_PLUGIN_CACHE_DIR   cleared

  THESE ARE NOT DECORATION AND THE OMISSION HAS SHIPPED BEFORE. lib\common.ps1
  resolves its state directory from CLAUDE_PLUGIN_DATA and then from
  $env:USERPROFILE\.claude\plugins\data, and this command reaches
  Write-LwgInvalidFlag through Test-LwgModule on any config holding a
  non-boolean flag. Without the swap, a run of this suite would append records to
  the OPERATOR'S OWN event log - the defect tests\stop_behaviour.ps1:96-104
  records having shipped once, and #147 records a QA agent repeating. Clearing
  CLAUDE_PLUGIN_ROOT matters just as much: left set, Get-LwgPluginRoot in the
  child returns the operator's REAL installed plugin directory.

  The child also runs with its working directory set to <scratch>\work, which is
  not inside a git repository, so no per-repo override can apply by accident and
  no case depends on the machine it runs on. -ThisRepo is therefore NOT covered
  here and that is a gap rather than a decision - a case would need a scratch
  repo with a local origin, as tests\setup_merge.ps1 section 26 builds. Every
  repo-scoped case below passes the slug explicitly with -Repo.

  Nothing here reads or writes the operator's ~\.claude tree. No network. No
  elevation. Every path is built at runtime, which is what
  tests\portability_scan.ps1 holds every tracked file to.

  ONE ENVIRONMENT TRAP THAT IS NOT THIS SUITE'S DOING, recorded because
  tests\toggle_behaviour.ps1:84-90 lost an hour to it first: if the shell that
  launches this file carries a PowerShell 7 PSModulePath, the Windows PowerShell
  5.1 children below cannot resolve Get-FileHash, Read-LwgTextFile fails, and
  EVERY case refuses with "cannot read". Run this suite from a 5.1 console, or
  set PSModulePath to the 5.1 default before launching it.

  ---------------------------------------------------------------------------
  WHICH CASE CARRIES WHICH DEFECT - "it went red" is not "it discriminates"
  ---------------------------------------------------------------------------
  #92 is carried by A1 and A2, and A1 is the stronger of the two: it flips an
      EXIT CODE (0 -> 1) and the presence of the PREVIEW ONLY banner, where A2
      discriminates on wording alone (both builds refuse; they disagree about
      WHAT they are refusing). A3 is a CONTROL.
  #91 is carried by B2, B7, B3 and B4, and all four discriminate on BYTES or an
      exit code rather than on prose: B2 flips `changed` false -> true, B7 flips
      exit 1 -> 0 and `changed` false -> true, B4 flips exit 0 -> 1 AND `changed`
      true -> false, and B3 asserts which key text the file ends up holding. B1,
      B5 and B6 are CONTROLS - B1 is the one that makes B2 and B7 contradictions
      rather than preferences, because it establishes that the same command, on
      the same file, reports that override as live.

  THE BASELINE COUNT IS MEASURED, NOT DERIVED. THIRTY-TWO cases. Twenty-three
  PASS at origin/main (a2d9447) and NINE FAIL there - three in section A, six in
  section B - measured by running this file unchanged against a tree holding
  origin/main's bin\lwg-config.ps1, bin\lwg-cmdlib.ps1 and lib\common.ps1.
  bin\lwg-config.ps1 is the ONLY file that differs between that run and the
  green one, byte for byte, so the nine are attributable to it and to nothing in
  lib\.

  CONTROL CASES ARE LABELLED. Twenty-one of the twenty-three that pass at the
  baseline carry the word CONTROL in their name; the other two are section G's
  invariants, which hold at both builds by construction. They pin the other
  direction, so a "fix" that refuses everything, or that rewrites the file, or
  that turns a legitimate no-op into a refusal, fails them. None is offered as
  evidence of a fix.

  ---------------------------------------------------------------------------
  WHAT A GREEN RUN DOES NOT MEAN
  ---------------------------------------------------------------------------
  These cases establish that the command refuses a wrong-case module name before
  it plans anything, canonicalises -Repo once against the shape a hook produces
  and the spelling the file already uses, previews without writing, writes what
  it previewed, and leaves the file untouched on every refusal. They establish
  NOTHING about:

    * -ThisRepo, for the sandbox reason above.
    * the exit-2 FAULT paths. Both require the file on disk to disagree with
      what was just written to it - a second writer inside a window of
      milliseconds, or a post-write parse failure that the pre-write
      Test-LwgJsonParses gate makes unreachable. No case constructs either;
      tests\toggle_behaviour.ps1's A5 shows what constructing the first one
      costs. The exit-2 code path is therefore UNRUN, and the reason #91 could
      hide there for as long as it did is that "verified" is exactly what it
      printed.
    * the not-implemented refusal. Every entry in $LwgModuleRegistry is status
      'implemented', so nothing this suite can pass to -Module -On reaches it.
      That refusal is the FIRST of the two the file's header calls its point,
      and no case here fires it. It would need a registry with a planned entry
      in it, which is a fixture over lib\common.ps1 rather than over config.json.
    * the ownSwitch refusal ("its flag is interaction.delegate, not a `modules`
      key"). It is reachable - pass -Module delegate_gate - and it is not
      covered here, because it is the toggle's territory and the toggle has its
      own suite.

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
    # Repo root. Defaults to this file's parent, correct for a run from anywhere
    # as long as this file stays in tests\. Point it at a tree assembled from an
    # older commit to measure a baseline.
    [string]$Root
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }

$script:Pass    = 0
$script:Results = New-Object System.Collections.ArrayList
$script:Aborted = ''
# Every child run this suite makes, with the exit code it returned, whether
# config.json changed underneath it, and whether it called itself a preview.
# Section G reads this and nothing else.
$script:Runs    = New-Object System.Collections.ArrayList

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
# ===========================================================================

function New-ConfigText {
    <#
      A config.json fixture. Small, hand-built and stated here rather than copied
      from the repo's own file, because these cases need one particular `repos`
      spelling, or a syntax error in a known place.

      It carries an apostrophe and an angle bracket in a "$comment" on purpose:
      PowerShell 5.1's ConvertTo-Json escapes both, so the surgical-edit case
      below would catch a ConvertFrom-Json / ConvertTo-Json round trip creeping
      into the write path.

      The `modules` block holds TWO real registry names - git_hygiene and
      docs_coupling - so a case can change one and assert the other did not move.
      Both are kind 'observe', status 'implemented' and declare no `switch`, so
      both are writable by this command.

        -Repos       the literal text of the `repos` value. Default '{}'.
        -BreakJson   remove one comma, so the file does not parse at all and
                     Get-LwgConfig falls back to the built-in defaults.
    #>
    param(
        [string]$Repos = '{}',
        [switch]$BreakJson
    )

    $t = @'
{
  "@C@": "scratch fixture - it's here so a <round trip> would be visible",
  "version": "0.0.0-test",
  "modules": {
    "git_hygiene": true,
    "docs_coupling": true
  },
  "interaction": {
    "delegate": false
  },
  "repos": @REPOS@,
  "thresholds": {}
}
'@
    # The key name is assembled rather than written, so no expansion rule in any
    # quoting style this file might be edited into can eat it.
    $t = $t.Replace('@C@', ([char]36 + 'comment'))
    $t = $t.Replace('@REPOS@', $Repos)

    if ($BreakJson) {
        # One comma removed. The file is unparseable from that point on.
        $t = $t.Replace('"version": "0.0.0-test",', '"version": "0.0.0-test"')
    }
    # Normalise to CRLF and end at the closing brace with no trailing newline.
    $t = ($t -replace "`r`n", "`n") -replace "`n", "`r`n"
    return $t.TrimEnd([char]13, [char]10)
}

function New-RepoBlock {
    <#
      A `repos` value holding ONE repository, spelt exactly as given. The
      spelling is the whole point of sections B and E: the reader finds it
      whatever its case, and until #91 was fixed the writer only found it when
      the case matched.
    #>
    param([string]$Slug, [string]$Module = 'git_hygiene', [string]$Literal = 'false')
    return ('{' + "`n" + '    "' + $Slug + '": {' + "`n" + '      "modules": {' + "`n" +
            '        "' + $Module + '": ' + $Literal + "`n" + '      }' + "`n" + '    }' + "`n" + '  }')
}

function Write-ConfigFile {
    <# Seed a config fixture. Bytes, not Set-Content. #>
    param([string]$Path, [string]$Text, [switch]$Bom)
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new([bool]$Bom))
}

function Get-Bytes {
    param([string]$Path)
    try { return [IO.File]::ReadAllBytes($Path) } catch { return $null }
}

function Get-B64 {
    param($Bytes)
    if ($null -eq $Bytes) { return '<absent>' }
    return [Convert]::ToBase64String($Bytes)
}

function Get-Text {
    <# The bytes of a finished run, as text. '' when the file was absent. #>
    param($Bytes)
    if ($null -eq $Bytes) { return '' }
    $off = 0
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { $off = 3 }
    return [Text.UTF8Encoding]::new($false).GetString($Bytes, $off, $Bytes.Length - $off)
}

function Get-ModuleRow {
    <#
      One row of the listing table, split into its six columns:

        MODULE  KIND  BUILT  GLOBAL  OVERRIDE  EFFECTIVE

      Returns $null when the module has no row at all, so a case can say which
      of "wrong value" and "no such row" it hit rather than indexing into
      nothing. The columns are fixed-width and space-padded
      (bin\lwg-config.ps1's listing block), so a whitespace split is exact.
    #>
    param([string]$Out, [string]$Module)
    foreach ($line in ($Out -split "`r?`n")) {
        $t = $line.Trim()
        if ($t -match ('^' + [regex]::Escape($Module) + '\s')) {
            $cols = @($t -split '\s+')
            if ($cols.Count -ge 6) { return $cols }
        }
    }
    return $null
}

# ===========================================================================
# SANDBOX AND CHILD-PROCESS PLUMBING
# ===========================================================================

function New-Sandbox {
    <#
      A throwaway plugin root: byte copies of bin\ and lib\, plus the scratch
      directories the child is pointed at. The code under test is copied ONCE per
      run - it does not change between cases - and only config.json is reseeded.
    #>
    # NOT $root: PowerShell variable names are case-insensitive, so a local $root
    # would shadow this script's $Root parameter and the copy below would take
    # its source from the temp directory.
    $base = Join-Path ([IO.Path]::GetTempPath()) ('lwg-config-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
    $sand = @{
        root    = $base
        plugin  = (Join-Path $base 'plugin')
        data    = (Join-Path $base 'data')
        profile = (Join-Path $base 'profile')
        work    = (Join-Path $base 'work')
    }
    foreach ($d in @($sand.root, $sand.plugin, $sand.data, $sand.profile, $sand.work)) {
        [void](New-Item -ItemType Directory -Path $d -Force)
    }
    foreach ($sub in @('bin', 'lib')) {
        $src = Join-Path $Root $sub
        if (Test-Path -LiteralPath $src) {
            Copy-Item -LiteralPath $src -Destination (Join-Path $sand.plugin $sub) -Recurse -Force
        }
    }
    $sand.config = Join-Path $sand.plugin 'bin\lwg-config.ps1'
    $sand.cfg    = Join-Path $sand.plugin 'config.json'
    if (-not (Test-Path -LiteralPath $sand.config -PathType Leaf)) {
        throw "the copied tree has no bin\lwg-config.ps1 at $($sand.config)"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $sand.plugin 'lib\common.ps1') -PathType Leaf)) {
        throw "the copied tree has no lib\common.ps1 - bin\lwg-config.ps1 dot-sources it and every case would abort"
    }
    return $sand
}

function Push-ChildEnv {
    <# Returns the previous values so the caller can restore them in a finally. #>
    param([hashtable]$Sand)
    $prev = @{
        up  = $env:USERPROFILE
        dat = $env:CLAUDE_PLUGIN_DATA
        rt  = $env:CLAUDE_PLUGIN_ROOT
        cd_ = $env:CLAUDE_CODE_PLUGIN_CACHE_DIR
    }
    $env:USERPROFILE                  = $Sand.profile
    $env:CLAUDE_PLUGIN_DATA           = $Sand.data
    $env:CLAUDE_PLUGIN_ROOT           = $null
    $env:CLAUDE_CODE_PLUGIN_CACHE_DIR = $null
    return $prev
}

function Pop-ChildEnv {
    param([hashtable]$Prev)
    # Restored rather than removed: this process may have inherited real values.
    $env:USERPROFILE                  = $Prev.up
    $env:CLAUDE_PLUGIN_DATA           = $Prev.dat
    $env:CLAUDE_PLUGIN_ROOT           = $Prev.rt
    $env:CLAUDE_CODE_PLUGIN_CACHE_DIR = $Prev.cd_
}

function Invoke-Config {
    <#
      Run bin\lwg-config.ps1 once, in a real child process, and return
      @{ code; out; err; before; after; changed; text; tag } - a hashtable, so
      PowerShell does not enumerate it away across the function boundary.

      `before` and `after` are the bytes of config.json, so every case can assert
      on what the run did to disk and section G can assert its invariants across
      all of them.

      A .cmd file rather than one long `cmd /c` string, for the reason
      tests\stop_behaviour.ps1:199-203 gives: cmd's rule about stripping the
      first and last quote of a /c argument makes a quoted path in such a string
      unreliable, and a harness that breaks on a temp path with a space in it is
      a harness that stops being run.
    #>
    param(
        [hashtable]$Sand,
        [string]$ScriptArgs,
        [string]$Tag
    )

    $of  = Join-Path $Sand.work "$Tag.out"
    $ef  = Join-Path $Sand.work "$Tag.err"
    $bat = Join-Path $Sand.work "$Tag.cmd"

    $cmd = ('powershell -NoProfile -ExecutionPolicy Bypass -File "{0}" {1} 1>"{2}" 2>"{3}"' -f $Sand.config, $ScriptArgs, $of, $ef)
    [IO.File]::WriteAllLines($bat, @('@echo off', ('cd /d "{0}"' -f $Sand.work), $cmd, 'exit /b %ERRORLEVEL%'), [Text.ASCIIEncoding]::new())

    $before = Get-Bytes -Path $Sand.cfg
    $prev = Push-ChildEnv -Sand $Sand
    try {
        & $env:ComSpec /c $bat | Out-Null
        $code = $LASTEXITCODE
    } finally {
        Pop-ChildEnv -Prev $prev
    }
    $after = Get-Bytes -Path $Sand.cfg

    $out = ''; $err = ''
    try { $out = [IO.File]::ReadAllText($of) } catch { }
    try { $err = [IO.File]::ReadAllText($ef) } catch { }

    $r = @{
        code    = $code
        out     = $out
        err     = $err
        before  = $before
        after   = $after
        text    = (Get-Text $after)
        changed = ((Get-B64 $before) -ne (Get-B64 $after))
        tag     = $Tag
    }
    [void]$script:Runs.Add([pscustomobject]@{
        tag = $Tag; code = $code; changed = $r.changed; preview = ($out -like '*PREVIEW ONLY*') })
    return $r
}

function Get-FirstLines {
    <# The first N non-blank lines of a run's stdout, for a failure detail. #>
    param([string]$Out, [int]$N = 4)
    return (($Out -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -First $N) -join ' | ')
}

# ===========================================================================
# RUN
# ===========================================================================

$sw = [Diagnostics.Stopwatch]::StartNew()
$sand = $null

try {
    $sand = New-Sandbox
    $good = New-ConfigText

    Write-Output ''
    Write-Output 'LW-WATCHTOWER config write-path suite'
    Write-Output ("  code under test : {0}" -f (Join-Path $Root 'bin\lwg-config.ps1'))
    Write-Output ("  sandbox         : {0}" -f $sand.root)
    Write-Output ''

    # =======================================================================
    # SECTION A - a module name in the wrong case  (#92)
    # BASELINE origin/main: `$known -notcontains $Module` is case-INSENSITIVE,
    # so 'Git_Hygiene' passes the gate whose own hint says names are
    # case-sensitive. Measured there: the preview run exits 0 and prints
    # PREVIEW ONLY; the -Apply run exits 1 blaming config.json for having
    # "drifted from the registry".
    # =======================================================================
    Write-Output 'A. a module name in the wrong case (#92)'

    Write-ConfigFile -Path $sand.cfg -Text $good
    $a1 = Invoke-Config -Sand $sand -ScriptArgs '-Module Git_Hygiene -Off' -Tag 'a1'

    # THE STRONG ONE: an exit code and a banner, not a choice of words. A preview
    # that plans a change the -Apply run cannot make is worse than the refusal it
    # should have been, because the operator acts on the preview.
    Add-Result 'wrong case: the PREVIEW refuses instead of planning a change that cannot be applied' `
        ($a1.code -eq 1 -and ($a1.out -notlike '*PREVIEW ONLY*') -and ($a1.out -like '*REFUSED - nothing was written.*')) `
        ("exit was {0} and stdout {1} the PREVIEW ONLY banner. -Module Git_Hygiene cannot be written by any later run - the JSON editor matches with -ceq - so a preview of it promises a change that does not exist. origin/main exits 0 here. stdout began: {2}" -f `
            $a1.code, $(if ($a1.out -like '*PREVIEW ONLY*') { 'carried' } else { 'did not carry' }), (Get-FirstLines $a1.out))

    Add-Result 'wrong case: the refusal names the typo and the module it meant' `
        (($a1.out -like "*did you mean 'git_hygiene'?*") -and ($a1.out -like '*Module names are case-sensitive.*')) `
        ('the hint that says names are case-sensitive was unreachable for the only input it describes; it must now fire. stdout: ' + (Get-FirstLines $a1.out 6))

    Write-ConfigFile -Path $sand.cfg -Text $good
    $a2 = Invoke-Config -Sand $sand -ScriptArgs '-Module Git_Hygiene -Off -Apply' -Tag 'a2'

    Add-Result 'wrong case: -Apply does NOT report config.json as drifted from the registry' `
        ($a2.code -eq 1 -and ($a2.out -notlike '*drifted from the registry*') -and ($a2.out -notlike '*no modules.Git_Hygiene member*')) `
        ("exit was {0}. A typed name in the wrong case is a TYPO. Reporting it as modules-block drift is a false report about the FILE, and it routes the operator to /lw-watchtower:doctor, which reads the same config and finds it healthy. stdout: {1}" -f `
            $a2.code, (Get-FirstLines $a2.out 6))

    Add-Result 'CONTROL wrong case: nothing is written' `
        ((-not $a1.changed) -and (-not $a2.changed)) `
        'both runs must leave config.json byte-identical - compared before and after. True at origin/main as well; what was wrong there was the diagnosis, not the write'

    Write-ConfigFile -Path $sand.cfg -Text $good
    $a3 = Invoke-Config -Sand $sand -ScriptArgs '-Module git_hygiene -Off -Apply' -Tag 'a3'

    Add-Result 'CONTROL: the SAME name in the right case still writes and exits 0' `
        ($a3.code -eq 0 -and $a3.changed -and ($a3.out -like '*WRITTEN.*') -and $a3.text.Contains('"git_hygiene": false')) `
        ("exit {0}; the other direction - a case-SENSITIVE membership test must not start refusing the exact spelling the registry holds. stdout tail: {1}" -f `
            $a3.code, (($a3.out -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 2) -join ' | '))

    Add-Result 'CONTROL: the edit is SURGICAL - only the one literal moved' `
        ($a3.text -eq $good.Replace('"git_hygiene": true', '"git_hygiene": false')) `
        'the whole point of the text editor in this script is that config.json keeps its bytes except the edited value; a ConvertFrom-Json / ConvertTo-Json round trip would escape the apostrophe and the angle bracket in the fixture''s comment and fail here'

    # =======================================================================
    # SECTION B - -Repo is taken verbatim  (#91)
    # BASELINE origin/main: no shape check and no reconciliation against the
    # keys in the file. Measured there: B2 exits 0 saying "Nothing to clear"
    # over the override B1 has just printed as effective; B3 writes the URL
    # itself as a `repos` key and calls it verified; B4 writes "owner" as one.
    # =======================================================================
    Write-Output ''
    Write-Output 'B. -Repo is taken verbatim (#91)'

    $mixed = New-ConfigText -Repos (New-RepoBlock -Slug 'Owner/Name' -Module 'git_hygiene' -Literal 'false')

    # CONTROL, AND THE PREMISE OF B2. Every reader in this plugin resolves
    # repos.<slug> by PowerShell property lookup, which is case-insensitive, so
    # this command's own table reports the "Owner/Name" override as live for
    # -Repo owner/name. True at origin/main too - that is what makes the next
    # case a contradiction inside one command rather than a matter of taste.
    Write-ConfigFile -Path $sand.cfg -Text $mixed
    $b1 = Invoke-Config -Sand $sand -ScriptArgs '-Repo owner/name' -Tag 'b1'
    $b1row = Get-ModuleRow -Out $b1.out -Module 'git_hygiene'

    Add-Result 'CONTROL premise: the table reports the "Owner/Name" override as LIVE for -Repo owner/name' `
        ($b1.code -eq 0 -and $null -ne $b1row -and $b1row[4] -eq 'off' -and $b1row[5] -eq 'off' -and $b1row[3] -eq 'on') `
        ("exit {0}; the git_hygiene row was {1}. The reader is case-insensitive, so the override IS in effect for that slug; the next case asserts the WRITER agrees" -f `
            $b1.code, $(if ($null -eq $b1row) { '<no such row>' } else { ($b1row -join ' | ') }))

    Write-ConfigFile -Path $sand.cfg -Text $mixed
    $b2 = Invoke-Config -Sand $sand -ScriptArgs '-Module git_hygiene -Clear -Repo owner/name -Apply' -Tag 'b2'

    Add-Result '-Clear removes the override the table just called live, whatever case the key is in' `
        ($b2.code -eq 0 -and $b2.changed -and ($b2.out -notlike '*Nothing to clear*') -and ($b2.out -like '*WRITTEN.*')) `
        ("exit was {0} and config.json {1}. origin/main matches the repos key with -ceq and prints `"Nothing to clear: config.json has no `"owner/name`" entry`" - over an override this same command reports as effective. An operator is told the module falls through to the global default when it does not. stdout: {2}" -f `
            $b2.code, $(if ($b2.changed) { 'CHANGED - correctly' } else { 'was NOT changed' }), (Get-FirstLines $b2.out 6))

    Add-Result 'after -Clear the override is really gone from the file' `
        (-not $b2.text.Contains('"git_hygiene": false')) `
        ('the only "git_hygiene": false in the fixture is the override inside "Owner/Name"; after a successful -Clear it must not be in the bytes. File after: ' + $b2.text)

    # THE SECOND OUTCOME OF THE SAME GAP - a WRITE rather than a -Clear against
    # a key the writer cannot see. It takes the `else` branch and builds an edit
    # that ADDS a second member beside the first, differing only in case.
    #
    # WHAT ORIGIN/MAIN ACTUALLY DOES HERE WAS MEASURED, NOT ASSUMED, and it is
    # not what a first reading predicts. The edit is never written: two `repos`
    # keys differing only in case make Windows PowerShell 5.1's ConvertFrom-Json
    # refuse the whole document ("contains the duplicated keys"), and the
    # last-gate Test-LwgJsonParses check catches its own output and refuses. So
    # the run ends
    #
    #     REFUSED - nothing was written.
    #       the edited text does not parse as JSON, so it was NOT written. This
    #       is a bug in this script; config.json is untouched.
    #
    # exit 1, file byte-identical - AFTER printing the full plan, including "now
    # override for owner/name is off" and "after effective on". The operator is
    # told to report a bug in the command, the override they were shown is
    # unchanged, and nothing names the actual cause. THAT PARSE GATE IS THE ONLY
    # THING between this defect and a config.json no reader can load, which is
    # why the second case below asserts on the gate rather than on the wreckage:
    # the wreckage never happened, and saying it did would be the overstatement
    # this suite exists to catch in someone else's file.
    Write-ConfigFile -Path $sand.cfg -Text $mixed
    $b7 = Invoke-Config -Sand $sand -ScriptArgs '-Module git_hygiene -On -Repo owner/name -Apply' -Tag 'b7'
    $b7parses = $false
    try { $null = ($b7.text | ConvertFrom-Json -ErrorAction Stop); $b7parses = $true } catch { }

    Add-Result 'a per-repo write EDITS the key the file already has, it does not add a case twin' `
        ($b7.code -eq 0 -and $b7.changed -and $b7.text.Contains('"Owner/Name"') -and `
         (-not $b7.text.Contains('"owner/name"')) -and (-not $b7.text.Contains('"git_hygiene": false'))) `
        ("exit was {0} and config.json {1}. The file's own spelling must win - this command edits a file it does not own - and there must be exactly ONE key for that repository afterwards. origin/main plans this change, builds an edit carrying BOTH spellings, and then cannot write it. File after: {2}" -f `
            $b7.code, $(if ($b7.changed) { 'CHANGED - correctly' } else { 'was NOT changed' }), $b7.text)

    Add-Result 'the command does not have to refuse its OWN edit as unparseable' `
        (($b7.out -notlike '*does not parse as JSON*') -and ($b7.out -notlike '*This is a bug in this script*') -and $b7parses) `
        ('the last-gate parse check is a guard against a bug in the editor, not a supported outcome of a valid request. Reaching it means the command built a document with two case-twin `repos` keys - which ConvertFrom-Json refuses outright, so every hook would have fallen back to built-in defaults had it been written - and then told the operator to report a bug instead of naming the slug. It is the only thing standing between #91 and an unloadable config.json. File after: ' + $b7.text)

    Write-ConfigFile -Path $sand.cfg -Text $good
    $b3 = Invoke-Config -Sand $sand -ScriptArgs '-Module git_hygiene -Off -Repo "https://github.com/owner/name.git" -Apply' -Tag 'b3'

    Add-Result 'a remote URL is reduced to the slug a hook produces, not written verbatim' `
        ($b3.code -eq 0 -and $b3.changed -and $b3.text.Contains('"owner/name"') -and (-not $b3.text.Contains('github.com'))) `
        ("exit {0}; the repos key written must be owner/name - what lib\common.ps1's Get-LwgRepoInfo hands every hook - and NOT the URL. origin/main writes the URL and then `"verifies`" it by re-resolving the same bad key through the same case-insensitive lookup, so the exit-2 check cannot detect a slug no hook will ever match. File after: {1}" -f `
            $b3.code, $b3.text)

    Write-ConfigFile -Path $sand.cfg -Text $good
    $b4 = Invoke-Config -Sand $sand -ScriptArgs '-Module git_hygiene -Off -Repo owner -Apply' -Tag 'b4'

    Add-Result 'a slug that is not owner/name is REFUSED, not written' `
        ($b4.code -eq 1 -and (-not $b4.changed) -and ($b4.out -like '*not the shape a hook produces*')) `
        ("exit was {0} and config.json {1}. origin/main writes `"owner`" as a repos key and exits 0: a member no hook can match, verified against itself. stdout: {2}" -f `
            $b4.code, $(if ($b4.changed) { 'CHANGED' } else { 'was untouched' }), (Get-FirstLines $b4.out 6))

    # CONTROL: canonicalisation must not turn a legitimate no-op into a refusal.
    Write-ConfigFile -Path $sand.cfg -Text $good
    $b5 = Invoke-Config -Sand $sand -ScriptArgs '-Module git_hygiene -Clear -Repo owner/name -Apply' -Tag 'b5'

    Add-Result 'CONTROL: -Clear on a repo with NO entry still says so and exits 0' `
        ($b5.code -eq 0 -and (-not $b5.changed) -and ($b5.out -like '*Nothing to clear*')) `
        ("exit was {0} and config.json {1}. There genuinely is no `"owner/name`" entry here, so `"Nothing to clear`" is the true answer and must survive the fix. Passes at origin/main" -f `
            $b5.code, $(if ($b5.changed) { 'CHANGED' } else { 'was untouched' }))

    # CONTROL: the ordinary per-repo write.
    Write-ConfigFile -Path $sand.cfg -Text $good
    $b6 = Invoke-Config -Sand $sand -ScriptArgs '-Module git_hygiene -Off -Repo owner/name -Apply' -Tag 'b6'

    Add-Result 'CONTROL: an ordinary -Repo owner/name write adds the key and exits 0' `
        ($b6.code -eq 0 -and $b6.changed -and $b6.text.Contains('"owner/name"') -and $b6.text.Contains('"git_hygiene": false')) `
        ("exit {0}; a well-formed slug on a file with an empty repos block must still be written, spelt exactly as passed. File after: {1}" -f $b6.code, $b6.text)

    Add-Result 'CONTROL: the per-repo write does not touch the GLOBAL flag' `
        ($b6.text.Contains('"git_hygiene": true')) `
        'the global modules.git_hygiene must still read true - a per-repo override is an override, not a global edit'

    # =======================================================================
    # SECTION C - two phases: preview, then Apply
    # All four pass at origin/main. The file's own header promises that the
    # preview run and the applied run "say the same words in the same order",
    # and C3 is that promise as an assertion rather than a claim.
    # =======================================================================
    Write-Output ''
    Write-Output 'C. preview, then -Apply'

    Write-ConfigFile -Path $sand.cfg -Text $good
    $c1 = Invoke-Config -Sand $sand -ScriptArgs '-Module docs_coupling -Off' -Tag 'c1'

    Add-Result 'CONTROL preview: explains the change, writes nothing, exits 0' `
        ($c1.code -eq 0 -and (-not $c1.changed) -and ($c1.out -like '*WHAT THIS DOES*') -and ($c1.out -like '*PREVIEW ONLY - nothing was written.*')) `
        ("exit {0} and config.json {1}; without -Apply nothing on disk may be touched and the effect must still be stated" -f `
            $c1.code, $(if ($c1.changed) { 'CHANGED' } else { 'was untouched' }))

    $c2 = Invoke-Config -Sand $sand -ScriptArgs '-Module docs_coupling -Off -Apply' -Tag 'c2'

    Add-Result 'CONTROL apply: the same command with -Apply writes it and exits 0' `
        ($c2.code -eq 0 -and $c2.changed -and ($c2.out -like '*WRITTEN.*') -and $c2.text.Contains('"docs_coupling": false')) `
        ("exit {0}; the preview above left the file untouched, so this run starts from the same state and must land the value it described" -f $c2.code)

    Add-Result 'CONTROL apply: the backup path is PRINTED and the backup exists' `
        (($c2.out -match 'backup:\s+(\S.*\.bak)') -and (Test-Path -LiteralPath ($Matches[1].Trim()))) `
        ('a backup nobody is told about is not a recovery mechanism. stdout backup line: ' + (($c2.out -split "`r?`n" | Where-Object { $_ -match 'backup' }) -join ' | '))

    # The header's promise, asserted: everything the preview printed before its
    # closing banner must be a PREFIX of what the applied run printed. Both runs
    # resolve the same on-disk state, because the preview wrote nothing.
    $cut = $c1.out.IndexOf('PREVIEW ONLY')
    $prefix = if ($cut -gt 0) { $c1.out.Substring(0, $cut) } else { '' }
    Add-Result 'CONTROL: the applied run says the same words in the same order as the preview' `
        ($cut -gt 0 -and $c2.out.StartsWith($prefix)) `
        ("bin\lwg-config.ps1's header promises exactly this, and it is what makes a preview worth reading. The preview's first {0} characters were {1}a prefix of the applied run's stdout" -f `
            $prefix.Length, $(if ($cut -gt 0 -and $c2.out.StartsWith($prefix)) { '' } else { 'NOT ' }))

    # =======================================================================
    # SECTION D - a module the registry has never heard of
    # CONTROLS. This is the path #92 kept a wrong-case name OUT of: an unknown
    # name has always refused BEFORE the preview, which is the behaviour A1
    # now holds a wrong-case name to.
    # =======================================================================
    Write-Output ''
    Write-Output 'D. a module the registry has never heard of'

    Write-ConfigFile -Path $sand.cfg -Text $good
    $d1 = Invoke-Config -Sand $sand -ScriptArgs '-Module not_a_module -Off -Apply' -Tag 'd1'

    Add-Result 'CONTROL unknown module: refused, nothing written, and the known names are listed' `
        ($d1.code -eq 1 -and (-not $d1.changed) -and ($d1.out -like '*known modules:*') -and ($d1.out -like '*is not a module in the registry*')) `
        ("exit was {0} and config.json {1}. A flag for a name the registry has never heard of is a switch wired to nothing. stdout: {2}" -f `
            $d1.code, $(if ($d1.changed) { 'CHANGED' } else { 'was untouched' }), (Get-FirstLines $d1.out))

    $d2 = Invoke-Config -Sand $sand -ScriptArgs '-Module not_a_module -Off' -Tag 'd2'

    Add-Result 'CONTROL unknown module: the PREVIEW refuses too - no plan is offered' `
        ($d2.code -eq 1 -and ($d2.out -notlike '*PREVIEW ONLY*')) `
        ("exit was {0}. This has always been true for an unknown name and was NOT true for a wrong-case one, which is #92 in one line" -f $d2.code)

    # =======================================================================
    # SECTION E - per-repo scope versus global scope
    # CONTROLS. The two scopes write different places and must not reach into
    # each other, and the listing has to show all three columns honestly.
    # =======================================================================
    Write-Output ''
    Write-Output 'E. per-repo scope versus global scope'

    $scoped = New-ConfigText -Repos (New-RepoBlock -Slug 'owner/name' -Module 'docs_coupling' -Literal 'false')

    Write-ConfigFile -Path $sand.cfg -Text $scoped
    $e1 = Invoke-Config -Sand $sand -ScriptArgs '-Module git_hygiene -Off -Apply' -Tag 'e1'

    Add-Result 'CONTROL: a GLOBAL write leaves an existing per-repo override untouched' `
        ($e1.code -eq 0 -and $e1.changed -and $e1.text.Contains('"git_hygiene": false') -and `
         $e1.text.Contains('"docs_coupling": false') -and $e1.text.Contains('"docs_coupling": true')) `
        ("exit {0}; the global git_hygiene must move to false while owner/name's docs_coupling override (false) and the global docs_coupling (true) both stay exactly as they were. File after: {1}" -f $e1.code, $e1.text)

    Write-ConfigFile -Path $sand.cfg -Text $scoped
    $e2 = Invoke-Config -Sand $sand -ScriptArgs '-Module docs_coupling -On -Repo owner/name -Apply' -Tag 'e2'

    Add-Result 'CONTROL: a per-repo write changes the override and not the global' `
        ($e2.code -eq 0 -and $e2.changed -and (-not $e2.text.Contains('"docs_coupling": false')) -and `
         ($e2.out -like '*scope: repo owner/name*')) `
        ("exit {0}; the override must flip to true, the global must still read true, and the report must name the scope it acted in. File after: {1}" -f $e2.code, $e2.text)

    Write-ConfigFile -Path $sand.cfg -Text $scoped
    $e3 = Invoke-Config -Sand $sand -ScriptArgs '-Repo owner/name' -Tag 'e3'
    $e3row = Get-ModuleRow -Out $e3.out -Module 'docs_coupling'
    $e4 = Invoke-Config -Sand $sand -ScriptArgs '' -Tag 'e4'
    $e4row = Get-ModuleRow -Out $e4.out -Module 'docs_coupling'

    Add-Result 'CONTROL: the scoped listing separates GLOBAL, OVERRIDE and EFFECTIVE' `
        ($e3.code -eq 0 -and $null -ne $e3row -and $e3row[3] -eq 'on' -and $e3row[4] -eq 'off' -and $e3row[5] -eq 'off') `
        ("the docs_coupling row under -Repo owner/name was {0}; global on, override off, effective off is the only honest rendering of that fixture" -f `
            $(if ($null -eq $e3row) { '<no such row>' } else { ($e3row -join ' | ') }))

    Add-Result 'CONTROL: the UNSCOPED listing shows no override and the global effect' `
        ($e4.code -eq 0 -and (-not $e4.changed) -and $null -ne $e4row -and $e4row[4] -eq '-' -and $e4row[5] -eq 'on') `
        ("the docs_coupling row with no -Repo was {0}; a per-repo override must not leak into the global view, and a listing must write nothing" -f `
            $(if ($null -eq $e4row) { '<no such row>' } else { ($e4row -join ' | ') }))

    # =======================================================================
    # SECTION F - config.json is unreadable
    # CONTROLS. Get-LwgConfig fails OPEN to built-in defaults, so a corrupt file
    # still yields a running plugin; a write on top of that would replace the
    # operator's real settings with the defaults' shape and destroy the evidence
    # of what went wrong. F4 is the ordering assertion for the new -Repo block:
    # a well-formed slug must not pre-empt this refusal.
    # =======================================================================
    Write-Output ''
    Write-Output 'F. config.json is unreadable'

    $broken = New-ConfigText -BreakJson
    Write-ConfigFile -Path $sand.cfg -Text $broken
    $f1 = Invoke-Config -Sand $sand -ScriptArgs '-Module git_hygiene -Off -Apply' -Tag 'f1'

    Add-Result 'CONTROL broken config: refused, nothing written, and the doctor is named' `
        ($f1.code -eq 1 -and (-not $f1.changed) -and ($f1.out -like '*REFUSED - nothing was written.*') -and `
         ($f1.out -like '*BUILT-IN DEFAULTS*') -and ($f1.out -like '*doctor*')) `
        ("exit was {0} and config.json {1}. Writing over a file the plugin cannot read would replace the operator's settings with the defaults' shape and destroy the evidence. stdout: {2}" -f `
            $f1.code, $(if ($f1.changed) { 'CHANGED' } else { 'was untouched' }), (Get-FirstLines $f1.out 6))

    $f2 = Invoke-Config -Sand $sand -ScriptArgs '' -Tag 'f2'

    Add-Result 'CONTROL broken config: a READ still reports, and says which source it is reading' `
        ($f2.code -eq 0 -and (-not $f2.changed) -and ($f2.out -like '*BUILT-IN DEFAULTS (config.json is unreadable or invalid)*')) `
        ("exit was {0}; an operator whose config is broken still needs to be able to ask what the state is, and the answer must name the fallback rather than present the defaults as the file's contents" -f $f2.code)

    # The ordering assertion for the block #91 added: it sits ABOVE the header
    # and above this refusal, so a well-formed -Repo must fall through to the
    # file's own problem rather than being answered before it.
    $f3 = Invoke-Config -Sand $sand -ScriptArgs '-Module git_hygiene -Off -Repo owner/name -Apply' -Tag 'f3'

    Add-Result 'CONTROL broken config: a well-formed -Repo still lands on the file''s own refusal' `
        ($f3.code -eq 1 -and (-not $f3.changed) -and ($f3.out -like '*BUILT-IN DEFAULTS*') -and `
         ($f3.out -notlike '*not the shape a hook produces*')) `
        ("exit was {0}. The slug is fine; the FILE is not, and that is what the operator must be told. stdout: {1}" -f `
            $f3.code, (Get-FirstLines $f3.out 6))

    Remove-Item -LiteralPath $sand.cfg -Force
    $f4 = Invoke-Config -Sand $sand -ScriptArgs '-Module git_hygiene -Off -Apply' -Tag 'f4'

    Add-Result 'CONTROL absent config: refused by name, and no file is created' `
        ($f4.code -eq 1 -and (-not (Test-Path -LiteralPath $sand.cfg)) -and ($f4.out -like '*cannot read*')) `
        ("exit was {0} and config.json {1}. A missing file is not an empty one: this command edits text it read, and it must not conjure a config it never saw" -f `
            $f4.code, $(if (Test-Path -LiteralPath $sand.cfg) { 'WAS CREATED' } else { 'was not created' }))

    # =======================================================================
    # SECTION G - the invariants, over every run this suite made
    # Evaluated LAST, so $script:Runs holds sections A to F.
    # =======================================================================
    Write-Output ''
    Write-Output 'G. the invariants over every run above'

    $refusals = @($script:Runs | Where-Object { $_.code -eq 1 })
    $liars    = @($refusals | Where-Object { $_.changed })
    Add-Result 'INVARIANT: every REFUSED run left config.json byte-identical' `
        ($refusals.Count -ge 6 -and $liars.Count -eq 0) `
        ("{0} run(s) of {1} exited 1 and {2} of them changed the file: {3}. Every refusal prints 'REFUSED - nothing was written.' verbatim, so a single one here is a documented claim the code contradicts. (At least 6 refusals are required, so this cannot pass by there being none.)" -f `
            $refusals.Count, $script:Runs.Count, $liars.Count, $(if ($liars.Count) { ($liars | ForEach-Object { $_.tag }) -join ', ' } else { 'none' }))

    $previews = @($script:Runs | Where-Object { $_.preview })
    $pLiars   = @($previews | Where-Object { $_.changed })
    Add-Result 'INVARIANT: every run that called itself a PREVIEW wrote nothing' `
        ($previews.Count -ge 1 -and $pLiars.Count -eq 0) `
        ("{0} run(s) printed PREVIEW ONLY and {1} of them changed the file: {2}. 'Nothing is written without -Apply' is the contract the whole two-phase design rests on" -f `
            $previews.Count, $pLiars.Count, $(if ($pLiars.Count) { ($pLiars | ForEach-Object { $_.tag }) -join ', ' } else { 'none' }))

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
Write-Output 'Every case above passed. Read that as "a wrong-case module name is refused before'
Write-Output 'anything is planned, -Repo is canonicalised once against the shape a hook produces'
Write-Output 'and the spelling the file already uses, the preview writes nothing and the applied'
Write-Output 'run says the same words, and every refusal leaves the file byte-identical" - and NOT'
Write-Output 'as "the write path is safe". See the header for the four things no case here reaches,'
Write-Output 'the exit-2 fault paths among them.'
Write-Output 'EXIT: 0'
exit 0
