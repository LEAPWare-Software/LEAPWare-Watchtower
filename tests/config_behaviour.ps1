#requires -version 5
<#
  LW-WATCHTOWER config WRITE-PATH regression suite - bin\lwg-config.ps1.

      powershell -NoProfile -ExecutionPolicy Bypass -File tests\config_behaviour.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File tests\config_behaviour.ps1 -Verbose

  WHAT THIS IS

  bin\lwg-config.ps1 backs /lw-watchtower:config. It is 680 lines of WRITE PATH -
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
         And a fourth thing, which neither the shape check nor the
         reconciliation can reach and which is what #91's third "what done
         looks like" item asks for: a slug of the right shape, matching no key
         in the file, that is simply the WRONG REPOSITORY. 'owner/nmae' passes
         both, is written, and is then "verified" by an exit-2 read-back that
         re-resolves the very key it just wrote through the same
         case-insensitive property lookup - so it agrees with anything. #91
         calls that machinery structurally blind to this class, and it is. The
         requirement is not a refusal, because writing an override for a repo
         you are not standing in is legitimate and this command cannot tell
         that apart from a typo; it is that the difference between CHECKED and
         TAKEN ON TRUST is stated. B8 and B9.
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

  The child runs with its working directory set to <scratch>\work by default,
  which is not inside a git repository, so no per-repo override can apply by
  accident and no case depends on the machine it runs on. Every repo-scoped case
  below passes the slug explicitly with -Repo.

  ONE CASE OVERRIDES THAT, and it is the only reason the seam exists. B9 runs
  from <scratch>\repo, a directory carrying a hand-built .git\config whose
  origin url is https://github.com/owner/name.git. Nothing shells out to git:
  Get-LwgRepoInfo walks up for .git, reads `config` and matches the url with two
  regexes, so that file is indistinguishable from a real one to the only code
  that reads it. B8 and B9 are the same argument run from the two sides of that
  line - outside any repo, and inside the repo the slug names - and the note
  under test must fire for the first and not the second. Without the second
  case the assertion would pass on unconditional text.

  -ThisRepo ITSELF IS STILL NOT COVERED. <scratch>\repo makes it reachable now,
  which it was not before, but no case passes -ThisRepo, so its own resolution
  and its disagreement refusal remain unexecuted.

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

  THE BASELINE COUNT IS MEASURED, NOT DERIVED, AND IT IS A RECORD OF ONE DAY
  RATHER THAN A COUNT OF WHAT THIS FILE RUNS NOW. This file held THIRTY-TWO
  cases when that baseline was taken. Twenty-three PASS at origin/main
  (a2d9447) and NINE FAIL there - three in section A, six in section B -
  measured by running this file unchanged against a tree holding origin/main's
  bin\lwg-config.ps1, bin\lwg-cmdlib.ps1 and lib\common.ps1.
  bin\lwg-config.ps1 is the ONLY file that differs between that run and the
  green one, byte for byte, so the nine are attributable to it and to nothing in
  lib\.

  IT HAS GROWN SINCE, AND THIS HEADER DELIBERATELY DOES NOT SAY BY HOW MUCH.
  The live total is the `RESULT: N of N case(s) passed` line this file prints,
  which is also where tests\doc_claims.ps1 reads it from; a second copy here is
  a number nobody maintains, and it went stale twice before anything noticed
  (#240). Sections H and I and the section A/G additions all landed without it.

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
    # The PLUGIN PAYLOAD root - lw-watchtower\ under this file's parent, not the
    # repository root, which is what this parameter meant before the restructure, correct for a run from anywhere
    # as long as this file stays in tests\. Point it at a tree assembled from an
    # older commit to measure a baseline.
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

function New-OverrideText {
    <#
      The OPERATOR OVERRIDE fixture - the document bin\lwg-config.ps1 actually
      writes since #11. config.json in the plugin root is the SHIPPED DEFAULTS
      and is no longer written by anything; the override under the state
      directory is where a `modules` flag and a `repos` entry now live, and
      Get-LwgConfig merges it over the defaults.

      It carries the same apostrophe and angle bracket in a "$comment" as
      New-ConfigText, and for the same reason - the surgical-edit case compares
      this file's bytes before and after, and a ConvertFrom-Json /
      ConvertTo-Json round trip would escape both and fail there. The reason
      moved to this file with the write.

      The `modules` block holds the SAME two real registry names as the defaults
      - git_hygiene and docs_coupling - so an -Off is a one-literal edit rather
      than a member insertion, which is what the surgical case is about.

        -Repos   the literal text of the `repos` value. Default '{}'.
        -Empty   the state a machine is in before anything has been configured.
    #>
    param([string]$Repos = '{}', [switch]$Empty)

    if ($Empty) { return "{}" }

    $t = @'
{
  "@C@": "scratch override fixture - it's here so a <round trip> would be visible",
  "modules": {
    "git_hygiene": true,
    "docs_coupling": true
  },
  "repos": @REPOS@
}
'@
    $t = $t.Replace('@C@', ([char]36 + 'comment'))
    $t = $t.Replace('@REPOS@', $Repos)
    $t = ($t -replace "`r`n", "`n") -replace "`n", "`r`n"
    return $t.TrimEnd([char]13, [char]10)
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
        # A SECOND working directory, and this one IS a git work tree whose
        # origin is owner/name. Nothing here shells out to git: Get-LwgRepoInfo
        # walks up for .git, reads `config`, and matches the url with two
        # regexes, so a hand-built .git\config is indistinguishable from a real
        # one to the only code that reads it. `work` is deliberately NOT a repo
        # - the system temp directory has no .git above it - so the two
        # directories are the two sides of the question B8 and B9 ask.
        repo    = (Join-Path $base 'repo')
    }
    foreach ($d in @($sand.root, $sand.plugin, $sand.data, $sand.profile, $sand.work, $sand.repo)) {
        [void](New-Item -ItemType Directory -Path $d -Force)
    }
    $dotgit = Join-Path $sand.repo '.git'
    [void](New-Item -ItemType Directory -Path $dotgit -Force)
    [IO.File]::WriteAllLines((Join-Path $dotgit 'config'), @(
        '[core]',
        '    repositoryformatversion = 0',
        '[remote "origin"]',
        '    url = https://github.com/owner/name.git',
        '    fetch = +refs/heads/*:refs/remotes/origin/*'), [Text.ASCIIEncoding]::new())
    # commands\ IS COPIED AND IT USED TO BE bin AND lib ALONE (#274). The command
    # now derives the route to a switch it cannot write by asking whether
    # commands\<key>.md exists under the plugin root, so a sandbox without that
    # directory would answer "no command writes it" for delegate too - a fixture
    # artefact that would make F8 assert against a tree the operator never has.
    foreach ($sub in @('bin', 'lib', 'commands')) {
        $src = Join-Path $Root $sub
        if (Test-Path -LiteralPath $src) {
            Copy-Item -LiteralPath $src -Destination (Join-Path $sand.plugin $sub) -Recurse -Force
        }
    }
    $sand.config = Join-Path $sand.plugin 'bin\lwg-config.ps1'
    # THE TWO FILES - #11. config.json in the copied plugin root is the SHIPPED
    # DEFAULTS and this command no longer writes it; the operator's choice goes
    # to config.override.json under the state directory, which Get-LwgConfig
    # merges over the defaults. Every assertion below about what a run did to
    # disk therefore reads .ov, and section G asserts that no run of this suite
    # ever moved a byte of .cfg.
    $sand.cfg    = Join-Path $sand.plugin 'config.json'
    $sand.ov     = Join-Path $sand.data   'config.override.json'
    if (-not (Test-Path -LiteralPath $sand.config -PathType Leaf)) {
        throw "the copied tree has no bin\lwg-config.ps1 at $($sand.config)"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $sand.plugin 'lib\common.ps1') -PathType Leaf)) {
        throw "the copied tree has no lib\common.ps1 - bin\lwg-config.ps1 dot-sources it and every case would abort"
    }
    return $sand
}

function Push-ChildEnv {
    <#
      Returns the previous values so the caller can restore them in a finally.

      -NoPluginData CLEARS CLAUDE_PLUGIN_DATA and points CLAUDE_CONFIG_DIR at
      the sandbox profile, which is how this command is ACTUALLY spawned. Claude
      Code hands $CLAUDE_PLUGIN_DATA to plugin HOOKS; a slash command runs
      through Bash(powershell:*) and is never handed it, so it falls through to
      Get-LwgStateDirInfo's discovery. Every case here before section J ran with
      the variable set, which is the hook's environment and not the command's -
      convenient, and it is the branch on which #270 cannot happen.
    #>
    param([hashtable]$Sand, [switch]$NoPluginData)
    $prev = @{
        up  = $env:USERPROFILE
        dat = $env:CLAUDE_PLUGIN_DATA
        rt  = $env:CLAUDE_PLUGIN_ROOT
        cd_ = $env:CLAUDE_CODE_PLUGIN_CACHE_DIR
        cfg = $env:CLAUDE_CONFIG_DIR
    }
    $env:USERPROFILE                  = $Sand.profile
    $env:CLAUDE_PLUGIN_DATA           = $(if ($NoPluginData) { $null } else { $Sand.data })
    $env:CLAUDE_CONFIG_DIR            = $(if ($NoPluginData) { $Sand.profile } else { $null })
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
    $env:CLAUDE_CONFIG_DIR            = $Prev.cfg
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
        [string]$Tag,
        # The directory the child is run FROM. Defaults to $Sand.work, which is
        # inside no repository. bin\lwg-config.ps1 resolves -ThisRepo, and now
        # the -Repo provenance note, from Get-LwgRepoInfo of the working
        # directory, so this is the only knob that changes either answer. Only
        # the `cd /d` moves: the .cmd, .out and .err stay in $Sand.work so a
        # case cannot leave litter in a directory another case reads.
        [string]$WorkDir,
        # Spawn the command the way a SLASH COMMAND is spawned rather than the
        # way a hook is - no CLAUDE_PLUGIN_DATA, so the state directory is
        # discovered. Section J needs it; see Push-ChildEnv.
        [switch]$NoPluginData
    )
    if ([string]::IsNullOrWhiteSpace($WorkDir)) { $WorkDir = $Sand.work }

    $of  = Join-Path $Sand.work "$Tag.out"
    $ef  = Join-Path $Sand.work "$Tag.err"
    $bat = Join-Path $Sand.work "$Tag.cmd"

    $cmd = ('powershell -NoProfile -ExecutionPolicy Bypass -File "{0}" {1} 1>"{2}" 2>"{3}"' -f $Sand.config, $ScriptArgs, $of, $ef)
    [IO.File]::WriteAllLines($bat, @('@echo off', ('cd /d "{0}"' -f $WorkDir), $cmd, 'exit /b %ERRORLEVEL%'), [Text.ASCIIEncoding]::new())

    $before     = Get-Bytes -Path $Sand.ov
    $baseBefore = Get-Bytes -Path $Sand.cfg
    $prev = Push-ChildEnv -Sand $Sand -NoPluginData:$NoPluginData
    try {
        & $env:ComSpec /c $bat | Out-Null
        $code = $LASTEXITCODE
    } finally {
        Pop-ChildEnv -Prev $prev
    }
    $after     = Get-Bytes -Path $Sand.ov
    $baseAfter = Get-Bytes -Path $Sand.cfg

    $out = ''; $err = ''
    try { $out = [IO.File]::ReadAllText($of) } catch { }
    try { $err = [IO.File]::ReadAllText($ef) } catch { }

    $r = @{
        code         = $code
        out          = $out
        err          = $err
        before       = $before
        after        = $after
        text         = (Get-Text $after)
        changed      = ((Get-B64 $before) -ne (Get-B64 $after))
        # THE SHIPPED DEFAULTS, TRACKED ON EVERY RUN - #11. Section G reads
        # this: no invocation of this command, on any path, may move a byte of
        # the file that is inside the plugin's git working tree.
        base_before  = $baseBefore
        base_after   = $baseAfter
        base_text    = (Get-Text $baseAfter)
        base_changed = ((Get-B64 $baseBefore) -ne (Get-B64 $baseAfter))
        tag          = $Tag
    }
    [void]$script:Runs.Add([pscustomobject]@{
        tag = $Tag; code = $code; changed = $r.changed; base_changed = $r.base_changed
        preview = ($out -like '*PREVIEW ONLY*') })
    return $r
}

function Get-FirstLines {
    <# The first N non-blank lines of a run's stdout, for a failure detail. #>
    param([string]$Out, [int]$N = 4)
    return (($Out -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -First $N) -join ' | ')
}

function New-HandBuiltGitDir {
    <#
      A .git directory holding one `config` with one [remote "origin"] url, and
      nothing else. That is the entire input Get-LwgRepoInfo takes - walk up for
      .git, follow `commondir` if there is one, parse the remote urls out of
      `config` - so a fabricated directory is the same evidence a real clone
      gives it, minus the network and the git binary. New-Sandbox builds
      $sand.repo exactly this way for B9 and says why there; section I needs two
      more of them, so the shape is written once here.
    #>
    param([string]$WorkTree, [string]$Slug)

    [void](New-Item -ItemType Directory -Path $WorkTree -Force)
    $dotgit = Join-Path $WorkTree '.git'
    [void](New-Item -ItemType Directory -Path $dotgit -Force)
    # Indented lines and all, because Get-LwgRepoInfo trims each line before
    # matching and a fixture that only worked unindented would stop testing the
    # parser that reads real files.
    [IO.File]::WriteAllLines((Join-Path $dotgit 'config'), @(
        '[core]',
        '    repositoryformatversion = 0',
        '    bare = false',
        '[remote "origin"]',
        ('    url = https://github.com/' + $Slug + '.git'),
        '    fetch = +refs/heads/*:refs/remotes/origin/*'), [Text.ASCIIEncoding]::new())
    return $WorkTree
}

function New-Junction {
    <#
      A REAL directory junction, built with `mklink /J` - the same command the
      dev-route install uses, which is the whole reason section I exists. A
      junction needs no privilege (a symbolic link does), so this works on a CI
      runner and on a developer's box alike.

      Returns $true when the link exists afterwards and is a reparse point.
      Never throws: section I asserts on the answer, because a suite that
      ABORTED here would throw away the verdicts of sections A to H over an
      environment fault that has nothing to do with them.

      A .cmd file rather than one long `cmd /c` string, for the reason
      Invoke-Config gives above: cmd's rule about stripping the first and last
      quote of a /c argument makes a quoted path in such a string unreliable,
      and every path here comes out of [IO.Path]::GetTempPath().
    #>
    param([hashtable]$Sand, [string]$Link, [string]$Target, [string]$Tag)

    $bat = Join-Path $Sand.work "$Tag.cmd"
    [IO.File]::WriteAllLines($bat, @(
        '@echo off',
        ('mklink /J "{0}" "{1}" >nul 2>&1' -f $Link, $Target),
        'exit /b %ERRORLEVEL%'), [Text.ASCIIEncoding]::new())
    try { & $env:ComSpec /c $bat | Out-Null } catch { }

    if (-not (Test-Path -LiteralPath $Link)) { return $false }
    try {
        return (([IO.File]::GetAttributes($Link) -band [IO.FileAttributes]::ReparsePoint) -ne 0)
    } catch { return $false }
}

function Invoke-RepoProbe {
    <#
      Ask lib\common.ps1's Get-LwgRepoInfo about a list of paths, IN A REAL CHILD
      PROCESS against the sandbox's byte copy of lib\, and return
      @{ code; out; rows } - a hashtable, so PowerShell does not enumerate it
      away across the function boundary. `rows` is tag -> @{ gitdir; root; slug }.

      A CHILD RATHER THAN A DOT-SOURCE, for two reasons this suite already pays
      for everywhere else. Dot-sourcing lib\common.ps1 into THIS process would
      load 4,000 lines of the code under test into the harness that judges it,
      and it would do so with the operator's own USERPROFILE and
      CLAUDE_PLUGIN_DATA live - the swap in Push-ChildEnv is what keeps a
      load-time side effect inside the sandbox, and it only covers children.
      The memoisation cache is per process too, so a child also guarantees that
      no probe below is answered out of a cache another case filled.

      One child for every path rather than one per path: the tags are distinct
      keys into the same cache, so a single run answers them all independently
      and the suite pays one process instead of five.
    #>
    param([hashtable]$Sand, [hashtable]$Paths, [string]$Tag)

    $probe = Join-Path $Sand.work "$Tag.ps1"
    $list  = Join-Path $Sand.work "$Tag.paths"
    $of    = Join-Path $Sand.work "$Tag.out"
    $ef    = Join-Path $Sand.work "$Tag.err"
    $bat   = Join-Path $Sand.work "$Tag.cmd"

    [IO.File]::WriteAllLines($list, @($Paths.Keys | ForEach-Object { $_ + "`t" + $Paths[$_] }), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllLines($probe, @(
        'param([string]$Common, [string]$List)',
        '$ErrorActionPreference = ''Stop''',
        '. $Common',
        'foreach ($line in [IO.File]::ReadAllLines($List)) {',
        '    if ([string]::IsNullOrWhiteSpace($line)) { continue }',
        '    $p = $line -split "`t", 2',
        '    $r = Get-LwgRepoInfo -Path $p[1]',
        '    Write-Output ("{0}|{1}|{2}|{3}" -f $p[0], $r.gitdir, $r.root, $r.slug)',
        '}'), [Text.UTF8Encoding]::new($false))

    $common = Join-Path $Sand.plugin 'lib\common.ps1'
    $cmd = ('powershell -NoProfile -ExecutionPolicy Bypass -File "{0}" -Common "{1}" -List "{2}" 1>"{3}" 2>"{4}"' -f $probe, $common, $list, $of, $ef)
    [IO.File]::WriteAllLines($bat, @('@echo off', ('cd /d "{0}"' -f $Sand.work), $cmd, 'exit /b %ERRORLEVEL%'), [Text.ASCIIEncoding]::new())

    $prev = Push-ChildEnv -Sand $Sand
    try {
        & $env:ComSpec /c $bat | Out-Null
        $code = $LASTEXITCODE
    } finally {
        Pop-ChildEnv -Prev $prev
    }

    $out = ''; $err = ''
    try { $out = [IO.File]::ReadAllText($of) } catch { }
    try { $err = [IO.File]::ReadAllText($ef) } catch { }

    $rows = @{}
    foreach ($line in ($out -split "`r?`n")) {
        if ($line -notmatch '\|') { continue }
        $f = $line -split '\|', 4
        if ($f.Count -eq 4) { $rows[$f[0]] = @{ gitdir = $f[1]; root = $f[2]; slug = $f[3] } }
    }
    return @{ code = $code; out = $out; err = $err; rows = $rows }
}

# ===========================================================================
# RUN
# ===========================================================================

$sw = [Diagnostics.Stopwatch]::StartNew()
$sand = $null

try {
    $sand = New-Sandbox
    $good = New-ConfigText
    # THE FILE THIS COMMAND WRITES - #11. config.json is seeded on every case as
    # the shipped DEFAULTS and is asserted never to move; the operator state a
    # case is about goes here.
    $goodOv = New-OverrideText

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
    Write-ConfigFile -Path $sand.ov  -Text $goodOv
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
    Write-ConfigFile -Path $sand.ov  -Text $goodOv
    $a2 = Invoke-Config -Sand $sand -ScriptArgs '-Module Git_Hygiene -Off -Apply' -Tag 'a2'

    Add-Result 'wrong case: -Apply does NOT report config.json as drifted from the registry' `
        ($a2.code -eq 1 -and ($a2.out -notlike '*drifted from the registry*') -and ($a2.out -notlike '*no modules.Git_Hygiene member*')) `
        ("exit was {0}. A typed name in the wrong case is a TYPO. Reporting it as modules-block drift is a false report about the FILE, and it routes the operator to /lw-watchtower:doctor, which reads the same config and finds it healthy. stdout: {1}" -f `
            $a2.code, (Get-FirstLines $a2.out 6))

    Add-Result 'CONTROL wrong case: nothing is written' `
        ((-not $a1.changed) -and (-not $a2.changed)) `
        'both runs must leave config.json byte-identical - compared before and after. True at origin/main as well; what was wrong there was the diagnosis, not the write'

    Write-ConfigFile -Path $sand.cfg -Text $good
    Write-ConfigFile -Path $sand.ov  -Text $goodOv
    $a3 = Invoke-Config -Sand $sand -ScriptArgs '-Module git_hygiene -Off -Apply' -Tag 'a3'

    Add-Result 'CONTROL: the SAME name in the right case still writes and exits 0' `
        ($a3.code -eq 0 -and $a3.changed -and ($a3.out -like '*WRITTEN.*') -and $a3.text.Contains('"git_hygiene": false')) `
        ("exit {0}; the other direction - a case-SENSITIVE membership test must not start refusing the exact spelling the registry holds. stdout tail: {1}" -f `
            $a3.code, (($a3.out -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 2) -join ' | '))

    Add-Result 'CONTROL: the edit is SURGICAL - only the one literal moved' `
        ($a3.text -eq $goodOv.Replace('"git_hygiene": true', '"git_hygiene": false')) `
        'the whole point of the text editor in this script is that the file it writes keeps its bytes except the edited value; a ConvertFrom-Json / ConvertTo-Json round trip would escape the apostrophe and the angle bracket in the fixture''s comment and fail here'

    # =======================================================================
    # SECTION B - -Repo is taken verbatim  (#91)
    # BASELINE origin/main: no shape check and no reconciliation against the
    # keys in the file. Measured there: B2 exits 0 saying "Nothing to clear"
    # over the override B1 has just printed as effective; B3 writes the URL
    # itself as a `repos` key and calls it verified; B4 writes "owner" as one.
    # =======================================================================
    Write-Output ''
    Write-Output 'B. -Repo is taken verbatim (#91)'

    # THE OVERRIDE IS WHERE A `repos` KEY LIVES NOW - #11, and #91 is unchanged
    # by that: the writer still matches member names with -ceq and every reader
    # still resolves them case-insensitively, so the reconciliation this section
    # is about is the same reconciliation over the same two rules. What moved is
    # only which document holds the key.
    $mixedOv = New-OverrideText -Repos (New-RepoBlock -Slug 'Owner/Name' -Module 'git_hygiene' -Literal 'false')

    # CONTROL, AND THE PREMISE OF B2. Every reader in this plugin resolves
    # repos.<slug> by PowerShell property lookup, which is case-insensitive, so
    # this command's own table reports the "Owner/Name" override as live for
    # -Repo owner/name. True at origin/main too - that is what makes the next
    # case a contradiction inside one command rather than a matter of taste.
    Write-ConfigFile -Path $sand.cfg -Text $good
    Write-ConfigFile -Path $sand.ov  -Text $mixedOv
    $b1 = Invoke-Config -Sand $sand -ScriptArgs '-Repo owner/name' -Tag 'b1'
    $b1row = Get-ModuleRow -Out $b1.out -Module 'git_hygiene'

    Add-Result 'CONTROL premise: the table reports the "Owner/Name" override as LIVE for -Repo owner/name' `
        ($b1.code -eq 0 -and $null -ne $b1row -and $b1row[4] -eq 'off' -and $b1row[5] -eq 'off' -and $b1row[3] -eq 'on') `
        ("exit {0}; the git_hygiene row was {1}. The reader is case-insensitive, so the override IS in effect for that slug; the next case asserts the WRITER agrees" -f `
            $b1.code, $(if ($null -eq $b1row) { '<no such row>' } else { ($b1row -join ' | ') }))

    Write-ConfigFile -Path $sand.cfg -Text $good
    Write-ConfigFile -Path $sand.ov  -Text $mixedOv
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
    Write-ConfigFile -Path $sand.cfg -Text $good
    Write-ConfigFile -Path $sand.ov  -Text $mixedOv
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
    Write-ConfigFile -Path $sand.ov  -Text $goodOv
    $b3 = Invoke-Config -Sand $sand -ScriptArgs '-Module git_hygiene -Off -Repo "https://github.com/owner/name.git" -Apply' -Tag 'b3'

    Add-Result 'a remote URL is reduced to the slug a hook produces, not written verbatim' `
        ($b3.code -eq 0 -and $b3.changed -and $b3.text.Contains('"owner/name"') -and (-not $b3.text.Contains('github.com'))) `
        ("exit {0}; the repos key written must be owner/name - what lib\common.ps1's Get-LwgRepoInfo hands every hook - and NOT the URL. origin/main writes the URL and then `"verifies`" it by re-resolving the same bad key through the same case-insensitive lookup, so the exit-2 check cannot detect a slug no hook will ever match. File after: {1}" -f `
            $b3.code, $b3.text)

    Write-ConfigFile -Path $sand.cfg -Text $good
    Write-ConfigFile -Path $sand.ov  -Text $goodOv
    $b4 = Invoke-Config -Sand $sand -ScriptArgs '-Module git_hygiene -Off -Repo owner -Apply' -Tag 'b4'

    Add-Result 'a slug that is not owner/name is REFUSED, not written' `
        ($b4.code -eq 1 -and (-not $b4.changed) -and ($b4.out -like '*not the shape a hook produces*')) `
        ("exit was {0} and config.json {1}. origin/main writes `"owner`" as a repos key and exits 0: a member no hook can match, verified against itself. stdout: {2}" -f `
            $b4.code, $(if ($b4.changed) { 'CHANGED' } else { 'was untouched' }), (Get-FirstLines $b4.out 6))

    # CONTROL: canonicalisation must not turn a legitimate no-op into a refusal.
    Write-ConfigFile -Path $sand.cfg -Text $good
    Write-ConfigFile -Path $sand.ov  -Text $goodOv
    $b5 = Invoke-Config -Sand $sand -ScriptArgs '-Module git_hygiene -Clear -Repo owner/name -Apply' -Tag 'b5'

    Add-Result 'CONTROL: -Clear on a repo with NO entry still says so and exits 0' `
        ($b5.code -eq 0 -and (-not $b5.changed) -and ($b5.out -like '*Nothing to clear*')) `
        ("exit was {0} and config.json {1}. There genuinely is no `"owner/name`" entry here, so `"Nothing to clear`" is the true answer and must survive the fix. Passes at origin/main" -f `
            $b5.code, $(if ($b5.changed) { 'CHANGED' } else { 'was untouched' }))

    # CONTROL: the ordinary per-repo write.
    Write-ConfigFile -Path $sand.cfg -Text $good
    Write-ConfigFile -Path $sand.ov  -Text $goodOv
    $b6 = Invoke-Config -Sand $sand -ScriptArgs '-Module git_hygiene -Off -Repo owner/name -Apply' -Tag 'b6'

    Add-Result 'CONTROL: an ordinary -Repo owner/name write adds the key and exits 0' `
        ($b6.code -eq 0 -and $b6.changed -and $b6.text.Contains('"owner/name"') -and $b6.text.Contains('"git_hygiene": false')) `
        ("exit {0}; a well-formed slug on a file with an empty repos block must still be written, spelt exactly as passed. File after: {1}" -f $b6.code, $b6.text)

    Add-Result 'CONTROL: the per-repo write does not touch the GLOBAL flag' `
        ($b6.text.Contains('"git_hygiene": true')) `
        'the global modules.git_hygiene must still read true - a per-repo override is an override, not a global edit'

    # THE THIRD THING #91 ASKED FOR, and the one the shape check and the
    # reconciliation above do NOT supply: say so when the slug cannot be
    # checked against anything.
    #
    # -ThisRepo DERIVES the slug through the same Get-LwgRepoInfo every hook
    # calls, so the key it writes is by construction a key some hook will ask
    # for. -Repo is a string. B4 refuses the wrong SHAPE and B7 reconciles the
    # wrong CASE, and neither can touch 'owner/nmae' - right shape, matching no
    # existing key, written and then "verified" by a read-back that re-resolves
    # the very key it just wrote through the same case-insensitive property
    # lookup. #91: "the exit-2 machinery is documented as the guard against
    # exactly this class, and it is structurally blind to it."
    #
    # So the requirement is not a refusal - writing an override for a repo you
    # are not standing in is a legitimate thing to do, and this command cannot
    # tell the two apart. It is that the difference between CHECKED and TAKEN
    # ON TRUST is stated, where the operator can still stop.
    Write-ConfigFile -Path $sand.cfg -Text $good
    Write-ConfigFile -Path $sand.ov  -Text $goodOv
    $b8 = Invoke-Config -Sand $sand -ScriptArgs '-Module git_hygiene -Off -Repo other/elsewhere -Apply' -Tag 'b8'

    Add-Result '-Repo naming a repo this run is not standing in says the slug is TAKEN ON TRUST' `
        ($b8.code -eq 0 -and $b8.changed -and ($b8.out -like '*UNVERIFIED SCOPE*') -and ($b8.out -like '*-ThisRepo*')) `
        ("exit was {0} and config.json {1}. The shape check and the reconciliation cannot reach a well-formed slug that is simply the wrong repository, and the exit-2 read-back re-resolves the key it just wrote, so it agrees with anything. #91 asks the command to say so once and name -ThisRepo as the path that does not have to. stdout: {2}" -f `
            $b8.code, $(if ($b8.changed) { 'CHANGED' } else { 'was NOT changed' }), (Get-FirstLines $b8.out 14))

    # THE DISCRIMINATOR. Unconditional text is not a report. Run from inside a
    # work tree whose origin IS owner/name - $sand.repo, whose hand-built
    # .git\config Get-LwgRepoInfo reads exactly as it reads a real one - the
    # same -Repo argument IS checkable, and the note must be absent.
    Write-ConfigFile -Path $sand.cfg -Text $good
    Write-ConfigFile -Path $sand.ov  -Text $goodOv
    $b9 = Invoke-Config -Sand $sand -WorkDir $sand.repo -ScriptArgs '-Module git_hygiene -Off -Repo owner/name -Apply' -Tag 'b9'

    Add-Result 'CONTROL: the same note is ABSENT when -Repo IS the repo the run is standing in' `
        ($b9.code -eq 0 -and $b9.changed -and ($b9.out -notlike '*UNVERIFIED SCOPE*') -and $b9.text.Contains('"owner/name"')) `
        ("exit was {0} and config.json {1}. $($sand.repo) is a work tree whose origin remote is https://github.com/owner/name.git, so Get-LwgRepoInfo hands this run the very slug that was typed and the write IS checked against something. A note that fires here too would be decoration rather than a finding. stdout: {2}" -f `
            $b9.code, $(if ($b9.changed) { 'CHANGED' } else { 'was NOT changed' }), (Get-FirstLines $b9.out 14))

    # =======================================================================
    # SECTION C - two phases: preview, then Apply
    # All four pass at origin/main. The file's own header promises that the
    # preview run and the applied run "say the same words in the same order",
    # and C3 is that promise as an assertion rather than a claim.
    # =======================================================================
    Write-Output ''
    Write-Output 'C. preview, then -Apply'

    Write-ConfigFile -Path $sand.cfg -Text $good
    Write-ConfigFile -Path $sand.ov  -Text $goodOv
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
    Write-ConfigFile -Path $sand.ov  -Text $goodOv
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

    $scopedOv = New-OverrideText -Repos (New-RepoBlock -Slug 'owner/name' -Module 'docs_coupling' -Literal 'false')

    Write-ConfigFile -Path $sand.cfg -Text $good
    Write-ConfigFile -Path $sand.ov  -Text $scopedOv
    $e1 = Invoke-Config -Sand $sand -ScriptArgs '-Module git_hygiene -Off -Apply' -Tag 'e1'

    Add-Result 'CONTROL: a GLOBAL write leaves an existing per-repo override untouched' `
        ($e1.code -eq 0 -and $e1.changed -and $e1.text.Contains('"git_hygiene": false') -and `
         $e1.text.Contains('"docs_coupling": false') -and $e1.text.Contains('"docs_coupling": true')) `
        ("exit {0}; the global git_hygiene must move to false while owner/name's docs_coupling override (false) and the global docs_coupling (true) both stay exactly as they were. File after: {1}" -f $e1.code, $e1.text)

    Write-ConfigFile -Path $sand.cfg -Text $good
    Write-ConfigFile -Path $sand.ov  -Text $scopedOv
    $e2 = Invoke-Config -Sand $sand -ScriptArgs '-Module docs_coupling -On -Repo owner/name -Apply' -Tag 'e2'

    Add-Result 'CONTROL: a per-repo write changes the override and not the global' `
        ($e2.code -eq 0 -and $e2.changed -and (-not $e2.text.Contains('"docs_coupling": false')) -and `
         ($e2.out -like '*scope: repo owner/name*')) `
        ("exit {0}; the override must flip to true, the global must still read true, and the report must name the scope it acted in. File after: {1}" -f $e2.code, $e2.text)

    Write-ConfigFile -Path $sand.cfg -Text $good
    Write-ConfigFile -Path $sand.ov  -Text $scopedOv
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
    Write-ConfigFile -Path $sand.ov  -Text $goodOv
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

    # -----------------------------------------------------------------------
    # F5 to F7 - #268. A config.json that PARSES and is not a config.
    # F8 is #274 and rides in this block only because it drives the SHIPPED
    # config.json, which F8 has to and nothing else here does.
    #
    # Every case above this one breaks config.json in a way ConvertFrom-Json
    # rejects, and Get-LwgConfig's guard was a NULL TEST - `$null -ne
    # $cfg.modules` - so everything that parsed at all sailed through it. In
    # PowerShell $false, 0, '', @() and 'yes' are all non-$null, so
    # {"modules":false} was read as a GOOD config: the operator's override was
    # merged over seventeen bytes carrying no thresholds, no `interaction`
    # block and none of the shipped defaults, and delegate_gate came up ARMED
    # off a file the same process's self-check reported as degraded. That is a
    # lockout - with the gate armed the main thread cannot call Bash, so it
    # cannot run the command that would switch the gate off - and two pages say
    # it cannot happen.
    #
    # This command is the right place to pin it because its refusal is the
    # OBSERVABLE consequence: it refuses to write whenever _source is not
    # 'file', so "is this document a config" and "will this command touch it"
    # are the same question, asked through a real child process.
    #
    # RED-FIRST: F5 and F6 FAIL at 6aebcd6, where both documents are accepted
    # and the command writes an override over them. F7 is the control that
    # stops the fix being "refuse anything small", and F8 is the shipped file.
    # -----------------------------------------------------------------------
    Write-ConfigFile -Path $sand.ov -Text $goodOv
    Write-ConfigFile -Path $sand.cfg -Text '{"modules":false}'
    $f5 = Invoke-Config -Sand $sand -ScriptArgs '-Module git_hygiene -Off -Apply' -Tag 'f5'

    Add-Result 'F5 {"modules":false} is not a config: refused, and no override is written (#268)' `
        ($f5.code -eq 1 -and (-not $f5.changed) -and ($f5.out -like '*BUILT-IN DEFAULTS*')) `
        ("exit was {0} and the override {1}. `$false is not `$null, so the old guard read seventeen bytes as a whole config and merged the operator's override over it - which is how a destroyed config.json armed the only blocking gate this plugin has. stdout: {2}" -f `
            $f5.code, $(if ($f5.changed) { 'WAS WRITTEN' } else { 'was untouched' }), (Get-FirstLines $f5.out 6))

    Write-ConfigFile -Path $sand.cfg -Text '{"modules":{}}'
    $f6 = Invoke-Config -Sand $sand -ScriptArgs '-Module git_hygiene -Off -Apply' -Tag 'f6'

    Add-Result 'F6 an EMPTY modules object is not a config either: refused, nothing written (#268)' `
        ($f6.code -eq 1 -and (-not $f6.changed) -and ($f6.out -like '*BUILT-IN DEFAULTS*')) `
        ("exit was {0} and the override {1}. {{}} declares nothing, so every module resolves through the absent-key default and the file is a destroyed one wearing the right brackets. An object test alone passes it, which is why the rule is 'an object with at least one member'. stdout: {2}" -f `
            $f6.code, $(if ($f6.changed) { 'WAS WRITTEN' } else { 'was untouched' }), (Get-FirstLines $f6.out 6))

    Write-ConfigFile -Path $sand.cfg -Text '{"modules":{"git_hygiene":true}}'
    $f7 = Invoke-Config -Sand $sand -ScriptArgs '' -Tag 'f7'

    Add-Result 'F7 CONTROL: a hand-written minimal config IS a config, and is read as config.json (#268)' `
        ($f7.code -eq 0 -and (-not $f7.changed) -and ($f7.out -like '*source: config.json*')) `
        ("exit was {0}. One real declaration is a small config, not a destroyed one; a check that refused this would refuse a legitimate hand-edited file and send the operator to the doctor over nothing. stdout: {1}" -f `
            $f7.code, (Get-FirstLines $f7.out 4))

    Write-ConfigFile -Path $sand.cfg -Text ([IO.File]::ReadAllText((Join-Path $Root 'config.json')))
    $f8 = Invoke-Config -Sand $sand -ScriptArgs '' -Tag 'f8'

    # The whole point of F8 is that it reads the SHIPPED file rather than a
    # fixture: a shape rule that rejected the file this plugin installs would be
    # caught by nothing else here, because every other case builds its own.
    $f8slash = @([regex]::Matches($f8.out, '/lw-watchtower:([a-z_]+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $f8missing = @($f8slash | Where-Object { -not (Test-Path -LiteralPath (Join-Path $sand.plugin ('commands\' + $_ + '.md')) -PathType Leaf) })

    Add-Result 'F8 every slash command this command names in its own output EXISTS (#274)' `
        ($f8.code -eq 0 -and $f8slash.Count -gt 0 -and $f8missing.Count -eq 0) `
        ("exit was {0}; the output named {1} slash command(s) [{2}] and {3} of them have no commands\<name>.md: [{4}]. Three of the four NOT SWITCHABLE HERE lines used to read 'use /lw-watchtower:send_liveness instead' and its two siblings, built at run time from the registry's switch key - and the plugin ships six commands, none of them those. bin\lwg-doctor.ps1's commands check scans FILES for these references, so a reference assembled at run time is invisible to it and this is the only place that can see it." -f `
            $f8.code, $f8slash.Count, ($f8slash -join ', '), $f8missing.Count, $(if ($f8missing.Count) { $f8missing -join ', ' } else { 'none' }))

    # -----------------------------------------------------------------------
    # F9. #300. A DIRECTORY AT config.override.json IS AN OVERRIDE THIS COMMAND
    #     CANNOT READ, AND IT SAYS SO ON BOTH PATHS.
    #
    #     F5-F7 pin the shapes of the SHIPPED file this command refuses to write
    #     over. This pins a shape of the OPERATOR'S file, and it is here rather
    #     than in tests\doctor_behaviour.ps1 alone because the defect is in the
    #     shared resolver: Get-LwgConfig gated its whole override read on
    #     [IO.File]::Exists, which answers $false for a directory, so
    #     _override_error stayed empty and every surface that renders it - this
    #     command's `source:` line, this command's write refusal,
    #     /lw-watchtower:doctor's config-registry row and roster,
    #     /lw-watchtower:delegate's state block - reported NO OVERRIDE over a
    #     config.override.json sitting at the path each of them names.
    #
    #     THE WRITE HALF IS THE REASON THIS IS NOT COSMETIC. Before the fix the
    #     listing said 'override: none', the write path then read $ovPath as
    #     absent, seeded it with [IO.File]::WriteAllText and took an unhandled
    #     UnauthorizedAccessException out of the middle of a run that had
    #     already printed a plan. Now the same state is a stated REFUSAL that
    #     names the file and tells the operator to delete it - the same refusal
    #     the four other unreadable shapes already get.
    #
    #     ONE CASE, BOTH PATHS. The override file this section left is SAVED and
    #     PUT BACK afterwards, bytes for bytes: section G asserts that the file
    #     every applied write landed in still exists under the state directory,
    #     and a case that swapped it for a directory and then deleted the
    #     directory would fail that invariant on a fixture rather than on a
    #     defect.
    #
    #     BASELINE 1baf6d4: the listing read 'override: none - these are the
    #     shipped defaults' and the -Apply run walked past its own refusal into
    #     [IO.File]::WriteAllText on the directory - neither of which says a
    #     config.override.json is there.
    # -----------------------------------------------------------------------
    $f9saved = Get-Bytes -Path $sand.ov
    if (Test-Path -LiteralPath $sand.ov) { Remove-Item -LiteralPath $sand.ov -Recurse -Force }
    [void][IO.Directory]::CreateDirectory($sand.ov)
    $f9a = Invoke-Config -Sand $sand -ScriptArgs '' -Tag 'f9a'
    $f9b = Invoke-Config -Sand $sand -ScriptArgs '-Module git_hygiene -Off -Apply' -Tag 'f9b'
    $f9dirStill = [IO.Directory]::Exists($sand.ov)
    if ([IO.Directory]::Exists($sand.ov)) { Remove-Item -LiteralPath $sand.ov -Recurse -Force }
    if ($null -ne $f9saved) { [IO.File]::WriteAllBytes($sand.ov, $f9saved) }

    Add-Result 'F9 an override that is a DIRECTORY is named as IGNORED and refused, not read as absent (#300)' `
        ($f9a.code -eq 0 -and ($f9a.out -like "*override: IGNORED - $($sand.ov) it is not a file*") -and
         ($f9a.out -notlike '*override: none*') -and
         $f9b.code -eq 1 -and ($f9b.out -like '*it is not a file*') -and
         $f9dirStill) `
        (("the listing exited {0} and the -Apply run exited {1}; the directory {2} after the write attempt. " +
          "[IO.File]::Exists is `$false for a directory, so the whole override read was skipped and " +
          "'override: none - these are the shipped defaults' was printed over a config.override.json that IS " +
          "at that path - then the write path, believing there was no file, tried to seed one on top of the " +
          "directory. listing: {3} || apply: {4}") -f `
            $f9a.code, $f9b.code, $(if ($f9dirStill) { 'was still there' } else { 'WAS REMOVED BY THE RUN' }),
            (Get-FirstLines $f9a.out 4), (Get-FirstLines $f9b.out 8))

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

    # THE #11 INVARIANT, over the same set. Every case above says something
    # about one run; this says what has to be true of ALL of them. config.json
    # is TRACKED and inside the plugin's own git working tree, so a single byte
    # moved in it leaves a fresh clone dirty and makes /lw-watchtower:update
    # refuse to pull for good - which is the whole of #11, and it happened on
    # every applied write this command made until 3 September 2026.
    #
    # It goes RED at 4342980 on every -Apply run here. The floor is what stops
    # it passing on a command that has stopped writing at all: at least three
    # runs must have exited 0 having changed the override.
    $wrote    = @($script:Runs | Where-Object { $_.code -eq 0 -and $_.changed })
    $dirtiers = @($script:Runs | Where-Object { $_.base_changed })
    Add-Result 'INVARIANT: no run of this command changed the plugin root config.json at all (#11)' `
        ($wrote.Count -ge 3 -and $dirtiers.Count -eq 0) `
        ("{0} run(s) of {1} moved a byte of config.json: {2}. That file is the SHIPPED DEFAULTS, it is tracked, and writing it is what made configuring this plugin disable its own updater. ({3} run(s) wrote the override and exited 0; at least 3 are required, so this cannot pass by the command having stopped writing.)" -f `
            $dirtiers.Count, $script:Runs.Count, $(if ($dirtiers.Count) { ($dirtiers | ForEach-Object { $_.tag }) -join ', ' } else { 'none' }), $wrote.Count)

    # AND THE OTHER HALF: the write has to be somewhere a hook resolves. The
    # command's own exit-2 verification re-reads through Get-LwgConfig, which
    # merges the override over the defaults, so a run that reported WRITTEN and
    # verified has already been resolved the way a hook resolves it - but only
    # if the file it wrote is the one Get-LwgConfig merges. This pins the path.
    $ovLive = @($script:Runs | Where-Object { $_.code -eq 0 -and $_.changed })
    Add-Result 'INVARIANT: the file every applied write landed in is the one under the state dir (#11)' `
        ($ovLive.Count -ge 3 -and [IO.File]::Exists($sand.ov)) `
        ("{0} run(s) wrote and exited 0, and config.override.json {1} in the state directory. A write that landed anywhere else is a write no hook resolves." -f `
            $ovLive.Count, $(if ([IO.File]::Exists($sand.ov)) { 'exists' } else { 'DOES NOT EXIST' }))

    # THE MODULE THIS COMMAND USED TO REFUSE, AND WHY IT NO LONGER DOES - #11.
    # lib/subagent_start.ps1 read <pluginRoot>\config.json directly, by raw text
    # scan, and reached Get-LwgConfig only for a per-repo override. An override
    # written for context_injection was therefore honoured by the banner, by the
    # doctor and by this command's own read-back, and IGNORED by the hook the
    # flag exists to switch - a write nothing honours, reported as verified,
    # which is the silent no-op this command exists to refuse. So it refused.
    #
    # THE HOOK NOW READS THE OVERRIDE: the same two scanners run over
    # config.override.json and every shape they cannot read escalates to
    # Get-LwgConfig, so the two readers agree and a write here takes effect. The
    # refusal went with the reason for it, in the same change as this case.
    #
    # THIS CASE IS THE MIRROR OF THE ONE IT REPLACES, and deliberately asserts
    # the WRITE rather than merely the absence of the refusal: `-not refused` is
    # satisfied by a command that has stopped doing anything at all. It goes RED
    # at 09b20be, where the block is still in bin/lwg-config.ps1 and the command
    # exits 1 having written nothing: 48 of 49, this case the only failure.
    Write-ConfigFile -Path $sand.cfg -Text $good
    Write-ConfigFile -Path $sand.ov  -Text $goodOv
    $g1 = Invoke-Config -Sand $sand -ScriptArgs '-Module context_injection -Off -Apply' -Tag 'g1'

    Add-Result 'context_injection is now WRITTEN, because lib/subagent_start.ps1 reads the override (#11)' `
        ($g1.code -eq 0 -and $g1.changed -and (-not $g1.base_changed) -and `
         ($g1.out -notlike '*cannot switch it*') -and ($g1.out -notlike '*does not switch it yet*')) `
        ("exit was {0}; the override {1} and config.json {2}. The hook that made this a silent no-op now runs the same scanners over config.override.json and escalates to Get-LwgConfig for anything they cannot read, so a write here is honoured. stdout: {3}" -f `
            $g1.code, $(if ($g1.changed) { 'changed' } else { 'was NOT changed' }), `
            $(if ($g1.base_changed) { 'CHANGED' } else { 'was untouched' }), (Get-FirstLines $g1.out 6))

    Add-Result 'CONTROL: a module with no second reader of its own is written the same way (#11)' `
        (@($script:Runs | Where-Object { $_.tag -eq 'a3' -and $_.code -eq 0 -and $_.changed }).Count -eq 1) `
        'the case above must be about context_injection reaching the same write path as everything else, not about this command writing whatever it is handed. git_hygiene has never had a fast reader of its own and case a3 wrote it; the two together say the special case is gone rather than inverted'

    # -----------------------------------------------------------------------
    # H. THE SHIPPED config.json ITSELF - #75
    #
    #    Every case above runs against a hand-built fixture, on purpose. This one
    #    reads the REPOSITORY'S OWN config.json, because the claim it pins is a
    #    property of the shipped file and of nothing else.
    #
    #    $status.implemented was an eleven-name array duplicating
    #    $LwgModuleRegistry, and the comment beside it said the two were "still
    #    held to each other by a machine rather than by memory". They were not.
    #    bin/lwg-doctor.ps1's config-registry check compares the `modules` keys
    #    against the registry and the declared switch keys and never read the
    #    array; no rule in tests/doc_claims.ps1 was sourced from it; no hook
    #    touched it. A hand-maintained copy believed on the strength of a machine
    #    that does not exist is worse than no copy, because the failure it invites
    #    is BELIEVING THE LIST: add a module, forget the array, and every check in
    #    CI stays green while the file reports one fewer module than exists.
    #
    #    So it was deleted rather than wired to a check nobody asked for, and this
    #    case is the guard that keeps it deleted. It is deliberately thin - there
    #    is no behaviour to drive, only an absence to hold - and it goes RED at
    #    4342980, where the array is present.
    #
    #    THE CONTROLS ARE WHAT MAKE THE ABSENCE MEAN ANYTHING. An assertion that a
    #    member is absent passes just as well against a file that does not parse,
    #    a file that is empty, or a path that is wrong, so the same read has to
    #    prove it found the real document first: the file parses, it carries a
    #    $status block, and that block still holds the keys nothing asked to
    #    remove. Without them, deleting config.json outright would turn this
    #    green.
    # -----------------------------------------------------------------------
    Write-Output ''
    Write-Output 'H. the shipped config.json - #75'

    $shippedPath = Join-Path $Root 'config.json'
    $shippedRaw  = ''
    $shippedObj  = $null
    $shippedWhy  = ''
    try {
        $shippedRaw = [IO.File]::ReadAllText($shippedPath, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
        $shippedObj = $shippedRaw | ConvertFrom-Json
    } catch { $shippedWhy = $_.Exception.Message }

    Add-Result 'H1 CONTROL: the repository''s own config.json is there and parses' `
        ($null -ne $shippedObj) `
        ("$shippedPath could not be read or parsed, so H2 and H3 would be asserting an absence over nothing: $shippedWhy")

    $statusBlock = $null
    if ($null -ne $shippedObj) { $statusBlock = $shippedObj.'$status' }
    $statusKeys = @()
    if ($null -ne $statusBlock) { $statusKeys = @($statusBlock.PSObject.Properties.Name) }

    Add-Result 'H2 CONTROL: it still carries a $status block holding the keys nothing asked to remove' `
        ($statusKeys -contains 'planned' -and $statusKeys -contains 'default_off' -and $statusKeys -contains '$gates_comment') `
        (('the $status block was read as {0} key(s): {1}. #75 removed ONE member from it; a block that has lost planned, default_off or $gates_comment as well means this case is looking at something other than the shipped file, and H3''s absence would prove nothing.') -f `
            $statusKeys.Count, $(if ($statusKeys.Count) { $statusKeys -join ', ' } else { 'none' }))

    Add-Result 'H3 $status.implemented is GONE, not hand-maintained beside a machine that never read it (#75)' `
        ($statusKeys.Count -gt 0 -and $statusKeys -notcontains 'implemented') `
        (('config.json''s $status block still declares an implemented array. Nothing in the tree reads it - not bin/lwg-doctor.ps1''s config-registry check, not tests/doc_claims.ps1, not any hook - so it is a second copy of $LwgModuleRegistry that goes stale in silence, under a comment that told the next reader a machine was keeping it in step. Keys found: {0}') -f ($statusKeys -join ', '))

    # And the sentence that made it dangerous. The array could have been deleted
    # while leaving behind the claim that something checks it, which is the half
    # of this defect that actually misleads a reader.
    #
    # A GUARD, NOT A RED. This one PASSES at 4342980: the sentence #75 quotes was
    # already replaced by a correct one in an earlier pass, and nothing pinned
    # that correction. H3 is the case that goes red at 4342980. This one keeps
    # the sentence from coming back beside a fresh copy of the list, which is how
    # the pair got here in the first place - and it fires on ANY member of the
    # block, including a removal note that quotes the old wording verbatim
    # instead of paraphrasing it. It caught exactly that while this change was
    # being written.
    $machineClaim = ''
    if ($null -ne $statusBlock) {
        foreach ($p in $statusBlock.PSObject.Properties) {
            if ($p.Value -is [string] -and $p.Value -match 'held to each other by a machine') { $machineClaim = $p.Name }
        }
    }
    Add-Result 'H4 and no comment in $status still claims a machine holds two module lists together (#75)' `
        ($null -ne $statusBlock -and $machineClaim -eq '') `
        (('$status.{0} still says the lists are "held to each other by a machine rather than by memory". No such machine exists: config-registry compares the modules keys against the registry and the declared switch keys, and reads nothing else. Deleting the array while keeping the sentence would leave the misleading half of #75 in place.') -f $machineClaim)

    # -----------------------------------------------------------------------
    # I. THE WALK THROUGH A JUNCTION - #228
    #
    #    Every case above reaches lib\common.ps1's Get-LwgRepoInfo through
    #    bin\lwg-config.ps1, and B8/B9 are the two sides of "am I inside a
    #    repository". This section asks the same function the question the
    #    DEV-ROUTE INSTALL SHAPE asks it, which no case anywhere had ever put:
    #    the caller's path is a DIRECTORY JUNCTION into a clone.
    #
    #    Claude Code loads this plugin from ~\.claude\skills\lw-watchtower, a
    #    junction made with `mklink /J`. It used to point at the repository
    #    ROOT, so the depth-0 `.git` probe succeeded and the shape was never
    #    exercised; since the payload moved under lw-watchtower\ (#118) it
    #    points at a SUBDIRECTORY of the clone, which has no .git of its own.
    #    `Split-Path -Parent` is a STRING operation on the link path, so the
    #    walk climbed out of the repository entirely - ~\.claude\skills ->
    #    ~\.claude -> ~ -> C:\Users -> C:\ - and gave one of two wrong answers:
    #
    #      * nothing, and bin\lwg-update.ps1:284-286 fires
    #        FAIL "<root> is not inside a git repository, so there is nothing to
    #        pull". /lw-watchtower:update dead on every dev-route machine; or
    #      * SOMEBODY ELSE'S REPOSITORY, when any directory on that climb carries
    #        a .git - a dotfiles repo under ~ is the common case. Worse than
    #        none: the update route would report and pull against it.
    #
    #    I4 IS THE FIRST WRONG ANSWER AND I5 IS THE SECOND, and they are
    #    separate cases because a fix can close one and leave the other open.
    #    Asking git only when the walk comes back EMPTY closes I4 and never
    #    fires for I5 at all: there the walk comes back FULL, holding the
    #    stranger's repository. Both are red at c39e782.
    #
    #    NOTHING HERE SHELLS OUT TO GIT, on either side of the seam. The
    #    fixtures are hand-built .git\config files for the reason New-Sandbox
    #    already gives, and they are also the reason the remedy could not be
    #    `git rev-parse`: git exits 128 on a .git holding a config and no HEAD,
    #    where this walk resolves it - so a git-first Get-LwgRepoInfo would take
    #    tests\gate_delegate.ps1's New-LwgFakeRepo assertion with it. Measured
    #    on #228 before this was written.
    #
    #    THE CONTROLS ARE WHAT MAKE THE TWO REDS MEAN ANYTHING. A junction that
    #    was never created, a probe child that never ran, a fixture repository
    #    the walk cannot read from the physical side, and a stranger fixture
    #    that is itself unreadable would each turn one of the cases below green
    #    or vacuous without a line of the behaviour being right. I7 is the other
    #    direction: a plain directory with no .git above it must still resolve
    #    to NOTHING, because "resolves a repository for everything" would pass
    #    I4 and I5 and break the cache route, where a null gitdir is the
    #    CORRECT answer.
    # -----------------------------------------------------------------------
    Write-Output ''
    Write-Output 'I. Get-LwgRepoInfo through a directory junction - #228'

    # A fixture clone whose slug is NOT the one $sand.repo carries, so no case
    # below can pass by resolving the sandbox repository B9 uses instead.
    $jRepo    = New-HandBuiltGitDir -WorkTree (Join-Path $sand.root 'jrepo') -Slug 'junction/target'
    $jPayload = Join-Path $jRepo 'payload'
    [void](New-Item -ItemType Directory -Path $jPayload -Force)

    # The dotfiles repository the string walk climbs into. The link lives INSIDE
    # its work tree, which is what makes the second wrong answer reachable.
    $sRepo    = New-HandBuiltGitDir -WorkTree (Join-Path $sand.root 'home') -Slug 'stranger/dotfiles'
    $sSkills  = Join-Path $sRepo 'skills'
    [void](New-Item -ItemType Directory -Path $sSkills -Force)

    # A plain directory - not a link, no .git of its own, and nothing above it
    # carries one either, because the sandbox root is under the system temp
    # directory. The null answer this must keep giving is the cache route's.
    $plainSub = Join-Path $sand.root 'plainsub'
    [void](New-Item -ItemType Directory -Path $plainSub -Force)

    $linkPlain    = Join-Path $sand.root 'jlink'
    $linkStranger = Join-Path $sSkills 'lw-watchtower'
    $madePlain    = New-Junction -Sand $sand -Link $linkPlain    -Target $jPayload -Tag 'i-mk1'
    $madeStranger = New-Junction -Sand $sand -Link $linkStranger -Target $jPayload -Tag 'i-mk2'

    $junctionsOk = ($madePlain -and $madeStranger -and
                    -not (Test-Path -LiteralPath (Join-Path $linkPlain '.git')) -and
                    -not (Test-Path -LiteralPath (Join-Path $linkStranger '.git')))

    Add-Result 'I1 CONTROL: two real mklink /J junctions were built, neither carrying a .git of its own' `
        $junctionsOk `
        (('the junction fixtures could not be built (plain={0}, under-stranger={1}), or one of them has a .git of its own - either way I4 and I5 below would be asking about an ordinary directory and would prove nothing about a reparse point. A junction needs no privilege, so this is a filesystem or ComSpec fault, not a permissions one.') -f $madePlain, $madeStranger)

    $probe = Invoke-RepoProbe -Sand $sand -Tag 'i-probe' -Paths @{
        link_plain    = $linkPlain
        link_stranger = $linkStranger
        physical      = $jPayload
        holder        = $sSkills
        plain         = $plainSub
    }
    $need = @('link_plain', 'link_stranger', 'physical', 'holder', 'plain')
    $got  = @($need | Where-Object { $probe.rows.ContainsKey($_) })

    Add-Result 'I2 CONTROL: the probe child ran and answered for every path it was given' `
        ($probe.code -eq 0 -and $got.Count -eq $need.Count) `
        (('the child that dot-sources the sandbox copy of lib\common.ps1 exited {0} and returned {1} of {2} row(s). Every case below reads those rows, so a child that died or answered short would make each of them assert over an empty string. stdout: {3} stderr: {4}') -f `
            $probe.code, $got.Count, $need.Count, (Get-FirstLines $probe.out 6), (Get-FirstLines $probe.err 3))

    $rPlainLink = if ($probe.rows.ContainsKey('link_plain'))    { $probe.rows['link_plain'] }    else { @{ gitdir = ''; root = ''; slug = '' } }
    $rStranger  = if ($probe.rows.ContainsKey('link_stranger')) { $probe.rows['link_stranger'] } else { @{ gitdir = ''; root = ''; slug = '' } }
    $rPhysical  = if ($probe.rows.ContainsKey('physical'))      { $probe.rows['physical'] }      else { @{ gitdir = ''; root = ''; slug = '' } }
    $rHolder    = if ($probe.rows.ContainsKey('holder'))        { $probe.rows['holder'] }        else { @{ gitdir = ''; root = ''; slug = '' } }
    $rPlain     = if ($probe.rows.ContainsKey('plain'))         { $probe.rows['plain'] }         else { @{ gitdir = ''; root = ''; slug = '' } }

    $wantGitDir = Join-Path $jRepo '.git'

    Add-Result 'I3 CONTROL: the fixture clone resolves from the PHYSICAL path' `
        ($rPhysical.gitdir -eq $wantGitDir -and $rPhysical.slug -eq 'junction/target') `
        (('the payload subdirectory reached by its real path resolved gitdir "{0}" slug "{1}", expected "{2}" and junction/target. The fixture repository is unreadable, so I4 would be failing over the fixture rather than over the junction.') -f `
            $rPhysical.gitdir, $rPhysical.slug, $wantGitDir)

    Add-Result 'I4 a junction into a clone SUBDIRECTORY resolves the clone, not nothing (#228)' `
        ($rPlainLink.gitdir -eq $wantGitDir -and $rPlainLink.root -eq $jRepo -and $rPlainLink.slug -eq 'junction/target') `
        (('through the junction Get-LwgRepoInfo answered gitdir "{0}" root "{1}" slug "{2}", expected "{3}", "{4}" and junction/target. An empty gitdir is the dev-route defect: bin\lwg-update.ps1 fires FAIL "<root> is not inside a git repository, so there is nothing to pull" off exactly this value, so /lw-watchtower:update is dead on every machine installed by junction. Split-Path -Parent is a string operation and cannot see past a reparse point; the walk has to continue from what the link POINTS AT.') -f `
            $rPlainLink.gitdir, $rPlainLink.root, $rPlainLink.slug, $wantGitDir, $jRepo)

    Add-Result 'I5 and it answers the clone even when the link sits inside SOMEBODY ELSE''S repository (#228)' `
        ($rStranger.slug -eq 'junction/target' -and $rStranger.root -eq $jRepo) `
        (('the junction lives under a work tree whose origin is stranger/dotfiles - the dotfiles-repo-under-~ shape - and Get-LwgRepoInfo answered slug "{0}" root "{1}", expected junction/target and "{2}". This is the half a git-when-the-walk-comes-back-empty fallback never reaches: the walk comes back FULL here, holding the wrong repository, and the update route would report and pull against it.') -f `
            $rStranger.slug, $rStranger.root, $jRepo)

    Add-Result 'I6 CONTROL: the directory the link LIVES in still resolves the stranger' `
        ($rHolder.slug -eq 'stranger/dotfiles') `
        (('the ordinary directory holding the junction resolved slug "{0}", expected stranger/dotfiles. The stranger fixture is unreadable, so I5 would be passing because there was nothing there to resolve rather than because the walk hopped past it.') -f $rHolder.slug)

    Add-Result 'I7 CONTROL: a plain directory with no .git above it still resolves to nothing' `
        ($rPlain.gitdir -eq '' -and $rPlain.root -eq '' -and $rPlain.slug -eq '') `
        (('a directory that is not a link and has no repository above it answered gitdir "{0}" root "{1}" slug "{2}", expected all three empty. A null gitdir is the CORRECT answer on the marketplace cache route, where there is no clone at all; a walk that resolves something for every path would satisfy I4 and I5 and break that.') -f `
            $rPlain.gitdir, $rPlain.root, $rPlain.slug)

    # The reparse points are removed HERE rather than left to the finally.
    # Directory.Delete on a junction removes the LINK and does not follow it,
    # where Remove-Item -Recurse over a tree holding one has a history of
    # deleting through it. Both targets are inside the sandbox, so nothing of
    # the operator's could be reached either way - this is about the suite not
    # modelling a pattern that is unsafe the moment somebody copies it.
    foreach ($lnk in @($linkPlain, $linkStranger)) {
        try { if (Test-Path -LiteralPath $lnk) { [IO.Directory]::Delete($lnk, $false) } } catch { }
    }

    # =======================================================================
    # SECTION J - #270, two state directories and a command that cannot tell
    # which one a hook reads
    #
    # A hook is handed $CLAUDE_PLUGIN_DATA by Claude Code. A slash command runs
    # through Bash(powershell:*) and is never handed it, so it falls through to
    # Get-LwgStateDirInfo's discovery and RANKS the lw-watchtower* siblings by
    # most recent write. An operator who has run this plugin from a marketplace
    # install AND from a checkout has two of them, and then the two readers can
    # land on different files. Measured end to end on lib/gate_delegate.ps1 and
    # bin/lwg-toggle.ps1: /lw-watchtower:delegate off exited 0, printed
    # "delegate is OFF" and "[merged over the defaults; this is what a hook
    # reads]", and the very next main-thread Bash call was refused with exit 2
    # by a gate reading the override in the OTHER directory.
    #
    # EVERY CASE ABOVE THIS SECTION RAN WITH CLAUDE_PLUGIN_DATA SET, which is a
    # hook's environment and not a command's - convenient, and the one branch on
    # which this cannot happen. -NoPluginData is what puts the command back on
    # its own spawn.
    #
    # WHY THE COMMAND REFUSES RATHER THAN WARNS. The write it would make is
    # recorded, verified against itself and read by nobody - the same silent
    # no-op every other refusal in this file exists to prevent, arrived at
    # through the DIRECTORY rather than through the key. J3 is the case that
    # says the refusal is not a dead end.
    #
    # RED-FIRST: J1 and J2 FAIL at 6aebcd6, where the command writes and reports
    # "override: none - these are the shipped defaults" over the other
    # directory's live override.
    # =======================================================================
    Write-Output ''
    Write-Output 'J. two state directories, and which file a hook reads (#270)'

    # Two suffixed candidates under the profile's plugins\data, which is where
    # discovery looks when CLAUDE_PLUGIN_DATA is unset. The marketplace-shaped
    # one holds the operator's real choice; the checkout-shaped one is newer, so
    # the mtime ranking prefers it - which is exactly the measured failure.
    $jData   = Join-Path $sand.profile 'plugins\data'
    $jMarket = Join-Path $jData 'lw-watchtower-leapware-watchtower'
    $jInline = Join-Path $jData 'lw-watchtower-inline'
    foreach ($d in @($jMarket, $jInline)) { [void](New-Item -ItemType Directory -Path $d -Force) }
    [IO.File]::WriteAllText((Join-Path $jMarket 'config.override.json'), '{"modules":{"git_hygiene":false}}', [Text.UTF8Encoding]::new($false))
    Start-Sleep -Milliseconds 1100
    [IO.File]::WriteAllText((Join-Path $jInline 'marker.txt'), 'newer', [Text.ASCIIEncoding]::new())

    Write-ConfigFile -Path $sand.cfg -Text ([IO.File]::ReadAllText((Join-Path $Root 'config.json')))
    $j1 = Invoke-Config -Sand $sand -ScriptArgs '-Module docs_coupling -Off -Apply' -Tag 'j1' -NoPluginData
    $j1wrote = @(Get-ChildItem -LiteralPath $jData -Recurse -Filter 'config.override.json' -File -ErrorAction SilentlyContinue)

    Add-Result 'J1 a write is REFUSED when two state directories are candidates (#270)' `
        ($j1.code -eq 1 -and $j1wrote.Count -eq 1 -and ($j1.out -like '*AMBIGUOUS*')) `
        ("exit was {0} and {1} config.override.json file(s) exist under plugins\data (expected the 1 that was seeded). A write here is recorded, verified against itself and read by nobody - and this command is the documented escape hatch from an armed gate, so reporting success over it leaves an operator locked out having run the one thing they were told to run. stdout: {2}" -f `
            $j1.code, $j1wrote.Count, (Get-FirstLines $j1.out 8))

    $j2 = Invoke-Config -Sand $sand -ScriptArgs '' -Tag 'j2' -NoPluginData

    Add-Result 'J2 the LISTING names both candidates instead of asserting the defaults (#270)' `
        ($j2.code -eq 0 -and ($j2.out -like '*AMBIGUOUS*') -and `
         ($j2.out -like '*lw-watchtower-inline*') -and ($j2.out -like '*lw-watchtower-leapware-watchtower*') -and `
         ($j2.out -notlike '*override: none - these are the shipped defaults*')) `
        ("exit was {0}. 'override: none - these are the shipped defaults' is an assertion about an ABSENCE, and it was made over a live override sitting in the directory this run did not resolve - which is the same sentence /lw-watchtower:doctor printed while a gate was refusing every tool call. stdout: {1}" -f `
            $j2.code, (Get-FirstLines $j2.out 8))

    # THE CONTROL, and it is what makes J1 a statement about ambiguity rather
    # than about the environment: remove the second candidate and the identical
    # command writes and exits 0. Without it a fix that simply refused whenever
    # CLAUDE_PLUGIN_DATA is unset would pass J1 and J2 and break every
    # marketplace install, where the variable is never set for a command.
    Remove-Item -LiteralPath $jInline -Recurse -Force
    $j3 = Invoke-Config -Sand $sand -ScriptArgs '-Module docs_coupling -Off -Apply' -Tag 'j3' -NoPluginData
    $j3text = ''
    try { $j3text = [IO.File]::ReadAllText((Join-Path $jMarket 'config.override.json')) } catch { }

    Add-Result 'J3 CONTROL: one candidate and the same command writes, into the directory that already had the override (#270)' `
        ($j3.code -eq 0 -and ($j3text -like '*docs_coupling*') -and ($j3.out -notlike '*AMBIGUOUS*')) `
        ("exit was {0} and the override now reads [{1}]. The refusal above must be about not knowing WHICH file, not about the variable being unset - a command that refused whenever CLAUDE_PLUGIN_DATA is absent would refuse on every ordinary install. stdout: {2}" -f `
            $j3.code, $j3text, (Get-FirstLines $j3.out 6))

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
Write-Output 'run says the same words, every refusal leaves the file byte-identical, and the'
Write-Output 'shipped config.json declares no second copy of the module registry" - and NOT'
Write-Output 'as "the write path is safe". See the header for the four things no case here reaches,'
Write-Output 'the exit-2 fault paths among them.'
Write-Output 'EXIT: 0'
exit 0
