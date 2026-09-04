#requires -version 5
<#
  LW-WATCHTOWER toggle WRITE-PATH regression suite - bin\lwg-toggle.ps1.

      powershell -NoProfile -ExecutionPolicy Bypass -File tests\toggle_behaviour.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File tests\toggle_behaviour.ps1 -Verbose

  WHAT THIS IS

  bin\lwg-toggle.ps1 backs /lw-watchtower:delegate, and it WRITES config.json.
  Nothing in tests\ had ever driven that write. tests\gate_delegate.ps1
  exercises lib\gate_delegate.ps1 - the READER of interaction.delegate - end to end;
  the writer was covered by nothing at all, which is why three defects in it
  survived being read several times.

  IT BACKED THREE COMMANDS UNTIL THE OUTPUT-STYLE FEATURE WAS REMOVED. The
  toggle also wrote output_style.verbosity and output_style.plain, for two
  commands whose keys nothing in this plugin ever read. Those flags, their
  commands, the output-styles\ directory and config.json's `output_style` block
  are all gone, and the cases that drove them went with them - see the note on
  SECTION F, which lost three of its four.

  The three this suite pins:

    #103  the write was a bare truncating [IO.File]::WriteAllText - no backup, no
          re-check that the file on disk is still the one that was read, and a
          hardcoded no-BOM encoding, where bin\lwg-config.ps1 routes the same
          file through Save-LwgTextFile and gets all three.
    #105  on a config.json that ALREADY does not parse, the toggle edited the
          broken text, failed to parse the result, blamed ITS OWN EDIT, and
          interpolated Windows PowerShell 5.1's ConvertFrom-Json message - which
          embeds the whole input - into operator output.
    #27   a config.json with no top-level `modules` block made the toggle WRITE
          the file and then exit 3, while bin\lwg-toggle.ps1's own header and
          commands\delegate.md both define exit 3 as "config.json was not
          changed".

  A FOURTH DEFECT USED TO BE PINNED HERE AND NO LONGER IS, and it is recorded
  rather than quietly dropped. Found by review rather than by an issue, it was a
  SECOND route to exit 3 on a file that was written: the write is fine and the
  REPORT after it throws - with USERPROFILE unset, the output-style ACTIVATION
  block built a settings path out of that variable - and every throw in that
  file lands in one handler that exits 3. It reached ONLY the two `style` flags,
  measured at both baselines as `-Flag plain on` -> exit 3, file CHANGED, and
  those flags no longer exist. Three cases drove it and are deleted. The GUARD
  in the toggle's catch is still there and is deliberately not deleted with
  them - it guards the class rather than that one line - but NO CASE HERE
  REACHES IT any more, and this file states that rather than leaving a reader to
  infer coverage from a section heading. Section F is now its former control
  alone. See the note on WHAT A GREEN RUN DOES NOT MEAN.

  ---------------------------------------------------------------------------
  HOW A CASE IS RUN, AND THE SANDBOX CONTRACT
  ---------------------------------------------------------------------------
  In a real child process, against a BYTE COPY of bin\ and lib\ under a scratch
  plugin root built at runtime from [IO.Path]::GetTempPath():

      <scratch>\plugin\bin\lwg-toggle.ps1     copied from the repo
      <scratch>\plugin\lib\common.ps1         copied from the repo
      <scratch>\plugin\config.json            SEEDED PER CASE

  bin\lwg-toggle.ps1 resolves its own config as
  (Split-Path -Parent $PSScriptRoot)\config.json, so a copied tree redirects the
  write with no seam at all. That is deliberate: it is what lets every case below
  run unchanged against fd8d023, which is the whole point of a red-first suite.
  The one exception is section E, which drives the -ConfigPath parameter added
  with the fix and therefore cannot exist at fd8d023 - it is labelled NEW SURFACE
  and is not offered as evidence that anything was fixed.

  Around every child, four environment variables are set or cleared and restored
  in a finally, for the reasons tests\setup_merge.ps1:55-61 already documents:

      USERPROFILE                    -> <scratch>\profile
      CLAUDE_PLUGIN_DATA             -> <scratch>\data
      CLAUDE_PLUGIN_ROOT             cleared
      CLAUDE_CODE_PLUGIN_CACHE_DIR   cleared

  Section F is the one place that deliberately runs with USERPROFILE UNSET, and
  it puts it back in the same finally as everything else. It ran that way to
  reach a defect in the output-style report block; with that block gone the one
  case left there asserts the other direction - that nothing on the surviving
  path reads USERPROFILE at all.

  ONE ENVIRONMENT TRAP THAT IS NOT THIS SUITE'S DOING, recorded so the next
  person does not lose an hour to it: if the shell that launches this file
  carries a PowerShell 7 PSModulePath, the Windows PowerShell 5.1 children below
  cannot resolve Get-FileHash, and EVERY toggle run exits 3 with "config.json
  could not be read". Run this suite from a 5.1 console, or set PSModulePath to
  the 5.1 default before launching it. An operator in a real 5.1 console never
  sees this; a CI job launched from pwsh does.

  USERPROFILE and CLAUDE_PLUGIN_DATA are not decoration. lib\common.ps1 resolves
  its state directory from CLAUDE_PLUGIN_DATA and then from
  $env:USERPROFILE\.claude\plugins\data, and the toggle reaches
  Write-LwgInvalidFlag on any config holding a non-boolean flag - which several
  fixtures below do on purpose. Without the swap, every run of this suite would
  append records to the OPERATOR'S event log, which is the exact defect
  tests\stop_behaviour.ps1:96-104 records having shipped once already. The child
  also runs with its working directory set to <scratch>\work, which is not inside
  a git repository, so no per-repo override can apply and no case depends on the
  machine it runs on.

  Nothing here reads or writes the operator's ~\.claude tree. No network. No
  elevation. Every path is built at runtime, which is what
  tests\portability_scan.ps1 holds every tracked file to.

  ---------------------------------------------------------------------------
  THE BASELINE FOR EACH SECTION - stated per case, not assumed
  ---------------------------------------------------------------------------
  Sections A (except A5), B, C and D: fd8d023. bin\lwg-toggle.ps1 differs between
  fd8d023 and 19bb85d only in the plugin's name strings, so the write path under
  test is the same code, and each case's comment states what fd8d023 actually
  printed or left on disk.

  Section A5 (changed under us) has fd8d023 as its baseline too, and it is the one
  case whose RED is a timing-anchored observation rather than a plain assertion -
  read its own comment before trusting it. It is conclusive or it ABORTS the
  suite; it can never pass by missing its window.

  Section E has NO fd8d023 baseline: -ConfigPath does not exist there, so the
  child dies on a parameter-binding error. Those two cases pin new surface.

  Section F's remaining case has fd8d023 as its baseline and passes there, like
  every other control. The defect that section was written for is unreachable
  now that the flags carrying it are deleted; see the note above.

  ---------------------------------------------------------------------------
  WHICH CASE CARRIES WHICH DEFECT - because "it went red" is not the same as
  "it discriminates the fix"
  ---------------------------------------------------------------------------
  #103 is carried by the three backup cases, the BOM case and A5.
  #27  is carried by the two modules-less cases and by G's invariant.
  #105 is carried by THREE of section B's cases and not by the fourth: the
       wording case (which requires the REFUSED banner and the BUILT-IN DEFAULTS
       sentence, both of which only the pre-write check can print), the doctor
       route, and the bound. "Nothing is written" is TRUE at both baselines and
       is labelled CONTROL for that reason. The wording case asserted only the
       absence of the old phrase until 3 August 2026 and stayed green with the
       pre-check deleted; it is written as it is because of that.

  ---------------------------------------------------------------------------
  WHAT A GREEN RUN DOES NOT MEAN
  ---------------------------------------------------------------------------
  These cases establish that the toggle takes a backup, re-checks the file it is
  about to replace, keeps a BOM, refuses a config it cannot read back, and does
  not return exit 3 on any run below that changed the file. They establish
  NOTHING about three things that are in the code and are not reached from here:

    * the bounded parser message on a file that parsed BEFORE the edit. A
      surgical editor cannot turn a parsing, modules-bearing config into text
      that does not parse, so no case constructs one. The bound itself IS
      covered, on the pre-write refusal, by the one-line fixture in section B.
    * the pre-write resolution of the edited TEXT. It sits behind the
      built-in-defaults refusal, which fires first on every input that would
      reach it. Deleting that refusal on 3 August 2026 left the modules-less
      cases green - so it does work - but in the shipped build no case reaches
      it.
    * the post-write read-back handler. With the pre-write resolution in place
      the only way it can fire is that the bytes on disk are no longer the ones
      the command wrote, which requires a second writer inside a window of a few
      milliseconds. No case constructs that, and the toggle's own header names
      it as the one state where exit 3 and "the bytes are as they were" can
      still disagree. An automatic rollback lived in that handler for one day
      and was removed: it could only fire in a state where firing it would
      overwrite another writer's file.
    * the $script:LwgVerified guard in the toggle's catch - the exit-0-after-a
      -verified-write path. Three cases in section F drove it through the
      output-style ACTIVATION block, the only line that ever threw there
      deterministically, and that block was deleted with the two style flags.
      Nothing here reaches the guard now, and nothing CAN: every line printed
      after that flag is set is a Write-Output over already-resolved values. The
      guard stays in the toggle on the same terms as the read-back handler above
      - it covers the class, and the next report line someone adds is what it is
      for. This is a COVERAGE LOSS rather than a decision, and it is written
      down as one so nobody reads section F's survivor as covering it.

  Read G for the property that is actually general.

  -Scope repo IS NOT COVERED EITHER, and that is a gap rather than a decision.
  The scratch working directory is deliberately not a git repository, so every
  repo-scoped run exits 2 at bin\lwg-toggle.ps1's slug check before it reaches
  the write at all. The pre-write read-back the fix adds runs the same
  Get-LwgPrefRepo the old post-write check ran, against the same object shape, so
  a repo-scoped write is not expected to behave differently - but "not expected"
  is not "was run", and no case here ran one. A case would need a scratch repo
  with a local bare origin, as tests\setup_merge.ps1 section 26 builds.

  CONTROL CASES ARE LABELLED. SEVEN of the cases below pass before the fix as
  well as after it, on purpose - they pin the other direction, so a "fix" that
  simply refuses everything, or that reformats the file, or that turns every run
  into a reported fault, fails them. They are marked CONTROL in their name and
  none is offered as evidence of a fix.

  THE BASELINE COUNT IS NOW DERIVED, NOT MEASURED, and it is labelled as such.
  TEN of twenty-six passed at fd8d023 and the same ten at 19bb85d, both measured
  on those commits. Four cases have since been deleted with the output-style
  flags they drove: section F's three, none of which passed at either baseline,
  and one CONTROL - the level axis - which passed at both. Only that CONTROL
  comes off the ten, so NINE of twenty-two is what subtraction from those
  per-case baselines gives. Nobody has re-run the suite against
  fd8d023 since the deletion, and the deleted cases cannot be re-run there in
  this form anyway. Treat the nine as arithmetic over a measurement, not as one.

  Those seven CONTROLs, plus two that are NOT controls and pass at the baselines
  for their own reasons: the BOM-bearing file still exits 0 at both (it just
  loses the BOM), and section E's second case passes vacuously because the child
  never starts. That is stated here so a reader counting greens in a red run
  does not read those two as coverage.

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

$script:Pass    = 0
$script:Results = New-Object System.Collections.ArrayList
$script:Aborted = ''
# Every child run this suite makes, with the exit code it returned and whether
# config.json changed underneath it. Section C3 reads this and nothing else.
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
      from the repo's own file, because these cases need exactly one non-boolean
      flag, exactly one missing block, or a syntax error in a known place.

      It carries an apostrophe and an angle bracket in a "$comment" on purpose:
      PowerShell 5.1's ConvertTo-Json escapes both, so any case asserting byte
      layout would catch a ConvertFrom-Json / ConvertTo-Json round trip creeping
      into the write path.

        -NoModules   drop the top-level `modules` block. Get-LwgConfig requires
                     it (lib\common.ps1:452), so the file parses and STILL
                     resolves to built-in defaults - the #27 shape.
        -BreakJson   remove one comma, so the file does not parse at all - #105.
        -Delegate    the literal text of interaction.delegate. '"false"' (a
                     STRING) makes the toggle log a ConfigInvalidFlag record,
                     which A5 uses as a clock.
        -PadKb       inflate the file with one long comment BEFORE the block that
                     gets edited. A5 needs the text scan to take real time; B2
                     needs a file big enough that dumping it is unmistakable.
    #>
    param(
        [switch]$NoModules,
        [switch]$BreakJson,
        [string]$Delegate = 'false',
        [int]$PadKb = 0,
        # Strip every line break, so the file is ONE line. A parser message from
        # such a file has no first line to take, which is what makes the
        # character bound - rather than the line split - the thing under test.
        [switch]$Minify
    )

    $t = @'
{
  "@C@": "scratch fixture - it's here so a <round trip> would be visible",
  "version": "0.0.0-test",@PAD@@MODULES@
  "interaction": {
    "delegate": @DELEGATE@
  },
  "repos": {},
  "thresholds": {}
}
'@
    # The key name is assembled rather than written, so no expansion rule in any
    # quoting style this file might be edited into can eat it.
    $t = $t.Replace('@C@', ([char]36 + 'comment'))
    $t = $t.Replace('@DELEGATE@', $Delegate)

    $pad = ''
    if ($PadKb -gt 0) {
        $filler = ('the same sentence again and again, so the scanner has real work to do. ' * 16)
        $n = [int][Math]::Ceiling(($PadKb * 1024) / $filler.Length)
        $pad = ([Environment]::NewLine + '  "' + [char]36 + 'padding": "' + ($filler * $n) + '",')
    }
    $t = $t.Replace('@PAD@', $pad)

    # The block Get-LwgConfig requires (lib\common.ps1:452). Absent, the file
    # parses and STILL resolves to the built-in defaults - the #27 shape.
    $mods = if ($NoModules) { '' } else { ([Environment]::NewLine + '  "modules": {' + [Environment]::NewLine + '    "git_hygiene": true' + [Environment]::NewLine + '  },') }
    $t = $t.Replace('@MODULES@', $mods)

    if ($BreakJson) {
        # One comma removed. The file is then unparseable from that point on,
        # which is the hand edit #105 describes.
        $t = $t.Replace('"version": "0.0.0-test",', '"version": "0.0.0-test"')
    }
    # Normalise to CRLF and end at the closing brace with NO trailing newline, so
    # A5 can append a two-byte marker and recognise it again.
    $t = ($t -replace "`r`n", "`n") -replace "`n", "`r`n"
    $t = $t.TrimEnd([char]13, [char]10)
    if ($Minify) { $t = ($t -replace "`r`n", ' ') }
    return $t
}

function New-OverrideText {
    <#
      The OPERATOR OVERRIDE fixture - the document bin\lwg-toggle.ps1 actually
      writes since #11. Small, because that is what it is in life: it holds only
      what somebody has set.

      It carries an apostrophe and an angle bracket in a "$comment" for the same
      reason New-ConfigText does, and the reason now applies to this file rather
      than to config.json: PowerShell 5.1's ConvertTo-Json escapes both, so the
      surgical-edit case in section D would catch a ConvertFrom-Json /
      ConvertTo-Json round trip creeping into the write path.

        -Delegate  the LITERAL written for interaction.delegate. Default false;
                   '"false"' (a STRING) makes the toggle log a ConfigInvalidFlag
                   record, which is A5's clock.
        -Empty     an override holding nothing at all, which is the state a
                   machine is in before anything has ever been configured.
    #>
    param([string]$Delegate = 'false', [switch]$Empty)

    if ($Empty) { return "{}" }

    $t = @'
{
  "@C@": "scratch override fixture - it's here so a <round trip> would be visible",
  "interaction": {
    "delegate": @D@
  }
}
'@
    $t = $t.Replace('@C@', ([char]36 + 'comment'))
    $t = $t.Replace('@D@', $Delegate)
    $t = ($t -replace "`r`n", "`n") -replace "`n", "`r`n"
    return $t.TrimEnd([char]13, [char]10)
}

function Write-ConfigFile {
    <# Seed a config fixture, with or without a UTF-8 BOM. Bytes, not Set-Content. #>
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

# ===========================================================================
# SANDBOX AND CHILD-PROCESS PLUMBING
# ===========================================================================

function New-Sandbox {
    <#
      A throwaway plugin root: byte copies of bin\ and lib\, plus the four
      scratch directories the child is pointed at. The code under test is copied
      ONCE per run - it does not change between cases - and only config.json is
      reseeded.

      output-styles\ was copied too until that directory was deleted with the
      output-style feature; the two flags that probed it with Test-Path are gone
      with it.
    #>
    # NOT $root: PowerShell variable names are case-insensitive, so a local $root
    # would shadow this script's $Root parameter and the copy below would take
    # its source from the temp directory.
    $base = Join-Path ([IO.Path]::GetTempPath()) ('lwg-toggle-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
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
    $sand.toggle = Join-Path $sand.plugin 'bin\lwg-toggle.ps1'
    # THE TWO FILES - #11. config.json in the copied plugin root is the SHIPPED
    # DEFAULTS and this command no longer writes it; the operator's choice goes
    # to config.override.json under the state directory, which Get-LwgConfig
    # merges over the defaults. Every case below that is about the WRITE now
    # points at .ov, and section G asserts that no run of this suite ever
    # changed .cfg at all.
    $sand.cfg    = Join-Path $sand.plugin 'config.json'
    $sand.ov     = Join-Path $sand.data   'config.override.json'
    if (-not (Test-Path -LiteralPath $sand.toggle -PathType Leaf)) {
        throw "the copied tree has no bin\lwg-toggle.ps1 at $($sand.toggle)"
    }
    return $sand
}

function New-NoFileHashRunner {
    <#
      A launcher that runs $Target in a real Windows PowerShell 5.1 child with
      one difference: `Get-FileHash` does not resolve, and any call to it throws
      the CommandNotFoundException a 5.1 child throws once a PowerShell 7
      PSModulePath has shadowed Microsoft.PowerShell.Utility - message verbatim
      (#273). Returns the launcher's path, for Invoke-Toggle -ScriptPath.

      A SECOND COPY, DELIBERATELY. tests\uninstall_footprint.ps1 carries the
      original and its full reasoning - why the NAME is shadowed rather than the
      module (a synthetic module does not reproduce it; four were measured), why
      an ALIAS rather than a function (a function is replaced by the module's own
      when the call triggers the auto-load), and what the fixture therefore does
      and does not establish. That reasoning is not repeated here. It is copied
      rather than shared because the two suites share no harness file and the
      standing rule is that no new file appears under tests\ - fifteen lines
      duplicated is the cheaper of the two.

      IT DISCRIMINATES ON THE RIGHT THING: red for any code that calls
      Get-FileHash on the path under test, green only for code that does not.
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
        'the path is correct and try again."))' + "`r`n"), [Text.UTF8Encoding]::new($false))
    # NO param BLOCK, and that is the one line where this copy differs from
    # tests\uninstall_footprint.ps1's - measured, not preferred. That one
    # forwards through `[Parameter(ValueFromRemainingArguments)]$Rest`, which is
    # enough for the switches the uninstaller takes. This suite's arguments are
    # `-Flag delegate on`, and the binder consumes `-Flag` as a parameter name
    # attempt on the LAUNCHER before $Rest ever sees it: the child then received
    # `delegate on` positionally and answered "A positional parameter cannot be
    # found that accepts argument 'delegate'". A script with no param block gets
    # every argument in $args verbatim, and `@args` re-splats them as the named
    # arguments they were written as.
    $text = @(
        ('Set-Alias -Name Get-FileHash -Value ' + "'" + $thrower.Replace("'", "''") + "'" + ' -Scope Global -Force')
        ('& ' + "'" + $Target.Replace("'", "''") + "'" + ' @args')
    ) -join "`r`n"
    [IO.File]::WriteAllText($Path, $text + "`r`n", [Text.UTF8Encoding]::new($false))
    return $Path
}

function Push-ChildEnv {
    <#
      Returns the previous values so the caller can restore them in a finally.

      -NoUserProfile leaves USERPROFILE UNSET for the child. Section F uses it.
      It was added because the deleted output-style report block built a
      settings path out of that variable, and an unset one was the state that
      made a written file exit 3; what is left asserts that no surviving path
      reads it.

      -NoPluginData CLEARS CLAUDE_PLUGIN_DATA and points CLAUDE_CONFIG_DIR at
      the sandbox profile, which is how this command is ACTUALLY spawned. Claude
      Code hands $CLAUDE_PLUGIN_DATA to plugin HOOKS; a slash command runs
      through Bash(powershell:*) and is never handed it, so it falls through to
      Get-LwgStateDirInfo's discovery. Every case here before section I ran with
      the variable set, which is a hook's environment and not this command's -
      convenient, and it is the one branch on which #270 cannot happen. Same
      switch, same wording and same reason as tests\config_behaviour.ps1's.
    #>
    param([hashtable]$Sand, [switch]$NoUserProfile, [switch]$NoPluginData)
    $prev = @{
        up  = $env:USERPROFILE
        dat = $env:CLAUDE_PLUGIN_DATA
        rt  = $env:CLAUDE_PLUGIN_ROOT
        cd_ = $env:CLAUDE_CODE_PLUGIN_CACHE_DIR
        cfg = $env:CLAUDE_CONFIG_DIR
    }
    $env:USERPROFILE                  = $(if ($NoUserProfile) { $null } else { $Sand.profile })
    $env:CLAUDE_PLUGIN_DATA           = $(if ($NoPluginData) { $null } else { $Sand.data })
    $env:CLAUDE_PLUGIN_ROOT           = $null
    $env:CLAUDE_CODE_PLUGIN_CACHE_DIR = $null
    # CLAUDE_CONFIG_DIR JOINED THE SANDBOX ON 3 SEPTEMBER 2026. No path in
    # bin\lwg-toggle.ps1 itself composes a configuration root any more - the
    # output-style block that did was deleted, which is what -NoUserProfile is
    # left asserting - but the child dot-sources lib\common.ps1, whose state-dir
    # resolver falls back to <configuration root>\plugins\data when
    # CLAUDE_PLUGIN_DATA is not set. A runner carrying the variable would point
    # that fallback at the real machine while USERPROFILE pointed harmlessly at
    # the sandbox. Cleared, so the sandbox is the whole sandbox.
    #
    # -NoPluginData is the one exception, and it points the variable at the
    # SANDBOX profile rather than clearing it: that is what makes the fallback
    # scan look under the sandbox's plugins\data, which is where section I
    # plants its two candidates.
    $env:CLAUDE_CONFIG_DIR            = $(if ($NoPluginData) { $Sand.profile } else { $null })
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

function Invoke-Toggle {
    <#
      Run bin\lwg-toggle.ps1 once, in a real child process, and return
      @{ code; out; err; before; after; changed } - a hashtable, so PowerShell
      does not enumerate it away across the function boundary.

      `before` and `after` are the bytes of the config file this run was pointed
      at, so every case can assert on what the run did to disk and C3 can assert
      the exit-3 invariant across all of them.

      A .cmd file rather than one long `cmd /c` string, and for the reason
      tests\stop_behaviour.ps1:199-203 gives: cmd's rule about stripping the
      first and last quote of a /c argument makes a quoted path in such a string
      unreliable, and a harness that breaks on a temp path with a space in it is
      a harness that stops being run.
    #>
    param(
        [hashtable]$Sand,
        [string]$ScriptArgs,
        [string]$Tag,
        # The file whose bytes this run is expected to touch. Defaults to the
        # override under the state directory, which is the file bin\lwg-toggle.ps1
        # writes since #11.
        [string]$CfgPath,
        # Run the child with USERPROFILE unset - see Push-ChildEnv.
        [switch]$NoUserProfile,
        # The script the child actually runs. Defaults to the copied
        # bin\lwg-toggle.ps1, which is what every case but one wants. The #273
        # case passes New-NoFileHashRunner's launcher, which runs that same
        # script with Get-FileHash unresolvable.
        [string]$ScriptPath,
        # Run the child the way Bash(powershell:*) runs it, with no
        # CLAUDE_PLUGIN_DATA - see Push-ChildEnv. Section I uses it.
        [switch]$NoPluginData
    )

    if ([string]::IsNullOrWhiteSpace($CfgPath)) { $CfgPath = $Sand.ov }
    if ([string]::IsNullOrWhiteSpace($ScriptPath)) { $ScriptPath = $Sand.toggle }

    $of  = Join-Path $Sand.work "$Tag.out"
    $ef  = Join-Path $Sand.work "$Tag.err"
    $bat = Join-Path $Sand.work "$Tag.cmd"

    $cmd = ('powershell -NoProfile -ExecutionPolicy Bypass -File "{0}" {1} 1>"{2}" 2>"{3}"' -f $ScriptPath, $ScriptArgs, $of, $ef)
    [IO.File]::WriteAllLines($bat, @('@echo off', ('cd /d "{0}"' -f $Sand.work), $cmd, 'exit /b %ERRORLEVEL%'), [Text.ASCIIEncoding]::new())

    $before = Get-Bytes -Path $CfgPath
    # THE SHIPPED DEFAULTS, TRACKED SEPARATELY AND ON EVERY RUN - #11. This is
    # what section G reads: the whole point of the change is that no invocation
    # of this command, on any path, for any reason, moves a byte of the file
    # that is inside the plugin's git working tree.
    $baseBefore = Get-Bytes -Path $Sand.cfg
    $prev = Push-ChildEnv -Sand $Sand -NoUserProfile:$NoUserProfile -NoPluginData:$NoPluginData
    try {
        & $env:ComSpec /c $bat | Out-Null
        $code = $LASTEXITCODE
    } finally {
        Pop-ChildEnv -Prev $prev
    }
    $after     = Get-Bytes -Path $CfgPath
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
        changed      = ((Get-B64 $before) -ne (Get-B64 $after))
        base_before  = $baseBefore
        base_after   = $baseAfter
        base_changed = ((Get-B64 $baseBefore) -ne (Get-B64 $baseAfter))
        tag          = $Tag
    }
    [void]$script:Runs.Add([pscustomobject]@{
        tag = $Tag; code = $code; changed = $r.changed; base_changed = $r.base_changed })
    return $r
}

function Get-BackupFiles {
    <#
      The .bak copies Save-LwgTextFile takes, which live BESIDE THE FILE IT
      WRITES - so since #11 they are in the state directory next to the
      override, not in the plugin root next to config.json. That is also why
      #11 needs no .gitignore rule: the backups left the working tree with the
      write that produced them.
    #>
    param([hashtable]$Sand)
    return @(Get-ChildItem -LiteralPath $Sand.data -Filter 'config.override.json.*.bak' -File -ErrorAction SilentlyContinue)
}

# ===========================================================================
# RUN
# ===========================================================================

$sw = [Diagnostics.Stopwatch]::StartNew()
$sand = $null

try {
    $sand = New-Sandbox

    Write-Output ''
    Write-Output 'LW-WATCHTOWER toggle write-path suite'
    Write-Output ("  code under test : {0}" -f (Join-Path $Root 'bin\lwg-toggle.ps1'))
    Write-Output ("  sandbox         : {0}" -f $sand.root)
    Write-Output ''

    # =======================================================================
    # SECTION A - the write itself: backup, re-check, BOM  (#103)
    # BASELINE fd8d023: the write is [IO.File]::WriteAllText($cfgPath, $updated,
    # [Text.UTF8Encoding]::new($false)) at line 786. No .bak is ever created,
    # nothing is printed about one, and the encoding is hardcoded.
    # =======================================================================
    Write-Output 'A. the write - backup, changed-under-us, BOM (#103)'

    # --- A1/A2 ---------------------------------------------------------------
    Write-ConfigFile -Path $sand.cfg -Text (New-ConfigText)
    Write-ConfigFile -Path $sand.ov  -Text (New-OverrideText)
    $orig     = Get-Bytes -Path $sand.ov
    $baseOrig = Get-Bytes -Path $sand.cfg
    foreach ($b in (Get-BackupFiles -Sand $sand)) { Remove-Item -LiteralPath $b.FullName -Force }
    $a = Invoke-Toggle -Sand $sand -ScriptArgs '-Flag delegate on' -Tag 'a1'
    $baks = @(Get-BackupFiles -Sand $sand)

    # fd8d023 leaves zero .bak files: `grep -n 'Copy-Item\|\.bak' bin\lwg-toggle.ps1`
    # matches nothing in that tree.
    Add-Result 'backup: a .bak of the written file is taken beside it' `
        ($baks.Count -eq 1) `
        ("expected exactly one config.override.json.*.bak next to the file that was written; found {0}. Without one, an operator told the file is unchanged has no way to find out otherwise" -f $baks.Count)

    $bakBytes = if ($baks.Count -eq 1) { Get-Bytes -Path $baks[0].FullName } else { $null }
    Add-Result 'backup: the .bak holds the file EXACTLY as it was before the write' `
        ((Get-B64 $bakBytes) -eq (Get-B64 $orig)) `
        'a backup whose bytes are not the pre-write file is not a recovery mechanism; compared byte for byte'

    Add-Result 'backup: the path of the backup is PRINTED' `
        (($baks.Count -eq 1) -and ($a.out -like ('*' + $baks[0].Name + '*'))) `
        ("stdout must name the backup, as bin\lwg-config.ps1 does. A backup nobody is told about is not a recovery mechanism. stdout was: " + (($a.out -split "`r?`n" | Where-Object { $_ -match 'backup' }) -join ' | '))

    # --- A1c-A1f: THE POINT OF #11 -------------------------------------------
    # Arming the one gate this plugin ships used to rewrite config.json, which
    # is TRACKED and inside the plugin's own git working tree - so the checkout
    # went dirty and /lw-watchtower:update refused to pull for good, on the
    # first thing the documentation tells a new operator to do.
    #
    # These go RED at 4342980, where the write lands in config.json and no
    # override file is ever created. A1e is the one that keeps A1c from being
    # satisfied by a command that writes nothing at all: the value has to be
    # somewhere, and the report has to say where.
    Add-Result 'the plugin root config.json is byte-identical after the write (#11)' `
        ((Get-B64 (Get-Bytes -Path $sand.cfg)) -eq (Get-B64 $baseOrig)) `
        'config.json is the SHIPPED DEFAULTS and is tracked. A write into it is what makes /lw-watchtower:update refuse to pull, and it is what this issue is'

    Add-Result 'nothing at all is left in the plugin root that was not there before (#11)' `
        (@(Get-ChildItem -LiteralPath $sand.plugin -File -ErrorAction SilentlyContinue).Count -eq 1) `
        ("the plugin root must hold config.json and nothing else after a write - not a .bak either, or `git status` is still dirty. Found: " +
         ((@(Get-ChildItem -LiteralPath $sand.plugin -File -ErrorAction SilentlyContinue) | ForEach-Object { $_.Name }) -join ', '))

    $ovAfterText = if ([IO.File]::Exists($sand.ov)) { [Text.UTF8Encoding]::new($false).GetString((Get-Bytes -Path $sand.ov)).TrimStart([char]0xFEFF) } else { '<absent>' }
    Add-Result 'the value IS recorded - an override document exists under the state dir (#11)' `
        ([IO.File]::Exists($sand.ov) -and $ovAfterText.Contains('"delegate": true')) `
        ('a clean checkout is trivially achieved by writing nowhere. The setting has to land somewhere a hook reads, and this is that place. File: ' + $ovAfterText)

    Add-Result 'and the report NAMES the file it wrote and the file it merged over (#11)' `
        (($a.out -like ('*' + $sand.ov + '*')) -and ($a.out -like ('*' + $sand.cfg + '*'))) `
        ('an operator told only one of the two paths goes and edits the wrong file - config.json looks like the settings file and is no longer written. stdout: ' +
         (($a.out -split "`r?`n" | Where-Object { $_ -match 'stored in|merged over|override' }) -join ' | '))

    # --- A3/A4: BOM ----------------------------------------------------------
    # fd8d023 hardcodes [Text.UTF8Encoding]::new($false), so the EF BB BF is gone
    # after the first toggle of a file another tool wrote with one.
    Write-ConfigFile -Path $sand.cfg -Text (New-ConfigText)
    Write-ConfigFile -Path $sand.ov  -Text (New-OverrideText) -Bom
    $b = Invoke-Toggle -Sand $sand -ScriptArgs '-Flag delegate on' -Tag 'a3'
    $after = $b.after
    $hasBom = ($null -ne $after -and $after.Length -ge 3 -and $after[0] -eq 0xEF -and $after[1] -eq 0xBB -and $after[2] -eq 0xBF)
    Add-Result 'BOM: a settings file that carried a UTF-8 BOM still carries one after a write' `
        ($hasBom -and $b.changed) `
        ("the first three bytes after the write were {0}; the file must keep the BOM another tool gave it (bin\lwg-config.ps1:434 passes -Bom for this reason), and the run must actually have written (changed={1})" -f `
            $(if ($null -ne $after -and $after.Length -ge 3) { ('{0:X2} {1:X2} {2:X2}' -f $after[0], $after[1], $after[2]) } else { '<too short>' }), $b.changed)

    Add-Result 'BOM: the BOM-bearing file still parses on the way back out - exit 0' `
        ($b.code -eq 0) `
        ("exit was {0}. A preserved BOM that the post-write re-read cannot load would be a worse defect than the one it fixes. stdout tail: {1}" -f `
            $b.code, (($b.out -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 2) -join ' | '))

    Write-ConfigFile -Path $sand.cfg -Text (New-ConfigText)
    Write-ConfigFile -Path $sand.ov  -Text (New-OverrideText)
    $c = Invoke-Toggle -Sand $sand -ScriptArgs '-Flag delegate on' -Tag 'a4'
    $afterNo = $c.after
    $gainedBom = ($null -ne $afterNo -and $afterNo.Length -ge 3 -and $afterNo[0] -eq 0xEF -and $afterNo[1] -eq 0xBB -and $afterNo[2] -eq 0xBF)
    Add-Result 'CONTROL BOM: a settings file WITHOUT a BOM does not gain one' `
        ((-not $gainedBom) -and $c.code -eq 0) `
        'the other direction: preserving a BOM must not mean adding one. This case passes at fd8d023 as well and pins that the fix did not flip the default'

    # --- A5: changed under us ------------------------------------------------
    # THE ONE TIMING-ANCHORED CASE. Read this before trusting it.
    #
    # The toggle is single-shot: there is no step boundary an outside process can
    # write between, so the mutation has to be made while the child runs. It is
    # NOT made on a bare sleep. The fixture sets interaction.delegate to the
    # STRING "false", which makes Get-LwgPrefGlobal call Write-LwgInvalidFlag,
    # which appends a ConfigInvalidFlag record to the scratch state dir. That
    # record is a CLOCK: the code order guarantees it is written
    #   - AFTER the fixed build has read the file and taken its SHA, and
    #   - BEFORE either build reaches its write,
    # and in the fd8d023 build it is written a few statements before that build's
    # [IO.File]::ReadAllText. The fixture is padded so the text scan and the two
    # JSON parses between the record and the write take real time, and the
    # mutation is made a fixed delay after the record appears - inside the
    # read-to-write window of BOTH builds.
    #
    # The mutation is two bytes of trailing whitespace appended after the closing
    # brace: it changes the SHA, keeps the file parseable, and leaves the seeded
    # text as an exact prefix. It is applied REPEATEDLY, every 50 ms from the
    # moment the record appears until the child exits, rather than once after a
    # measured delay - a single delayed append has to be tuned to a window that
    # was 305 ms on this machine and is a different number on another, and a
    # mistuned one lands after the write and proves nothing.
    #
    # That makes the run CONCLUSIVE either way:
    #   file still starts with the seeded text, is longer, and still holds the
    #   operator's own value          -> the write was refused               (pass)
    #   file no longer starts with it -> the toggle replaced it from a stale
    #                                    read                                (fail)
    #   neither                       -> nothing was appended at all;
    #                                    inconclusive, retried, and on repeated
    #                                    failure the suite ABORTS rather than
    #                                    passing.
    # fd8d023 lands in the second of those: exit 0, no refusal, the appended
    # bytes and the operator's value both gone.
    $a5 = $null
    $a5note = ''
    for ($attempt = 1; $attempt -le 3 -and $null -eq $a5; $attempt++) {
        # THE PAD STAYS ON config.json AND THE MUTATION MOVES TO THE OVERRIDE.
        # The 700 KB of defaults is what makes the run take long enough to be
        # interrupted at all - the toggle parses that file twice through
        # Get-LwgConfig before it writes - and the STRING "false" in it is
        # A5's clock, because resolving it makes the toggle log a
        # ConfigInvalidFlag record into the scratch state dir. What
        # Save-LwgTextFile hashes, though, is the file it WRITES, so the two
        # bytes have to be appended to the override or the changed-under-us
        # check has nothing to notice.
        Write-ConfigFile -Path $sand.cfg -Text (New-ConfigText -Delegate '"false"' -PadKb 700)
        Remove-Item -LiteralPath (Join-Path $sand.data '*') -Recurse -Force -ErrorAction SilentlyContinue
        Write-ConfigFile -Path $sand.ov -Text (New-OverrideText -Delegate '"false"')
        $seed = [IO.File]::ReadAllText($sand.ov)

        $of = Join-Path $sand.work "a5-$attempt.out"
        $ef = Join-Path $sand.work "a5-$attempt.err"
        $cf = Join-Path $sand.work "a5-$attempt.code"
        $bat = Join-Path $sand.work "a5-$attempt.cmd"
        # The exit code comes back through a FILE rather than through
        # $p.ExitCode: a Process obtained from Start-Process -PassThru returns an
        # empty ExitCode here, and an empty exit code in a case's evidence reads
        # as "the suite could not tell", which is the one thing it must not print.
        [IO.File]::WriteAllLines($bat, @(
            '@echo off',
            ('cd /d "{0}"' -f $sand.work),
            ('powershell -NoProfile -ExecutionPolicy Bypass -File "{0}" -Flag delegate on 1>"{1}" 2>"{2}"' -f $sand.toggle, $of, $ef),
            # The space before the > is load-bearing: `echo %ERRORLEVEL%>"f"`
            # makes cmd read the digit as a file HANDLE and redirects that
            # instead, which writes "ECHO is off." and no exit code at all.
            ('echo %ERRORLEVEL% >"{0}"' -f $cf),
            'exit /b %ERRORLEVEL%'
        ), [Text.ASCIIEncoding]::new())

        $prev = Push-ChildEnv -Sand $sand
        try {
            $p = Start-Process -FilePath $env:ComSpec -ArgumentList @('/c', ('"' + $bat + '"')) `
                -WorkingDirectory $sand.work -NoNewWindow -PassThru

            $clock = $false
            $appends = 0
            $deadline = (Get-Date).AddSeconds(120)
            while ((Get-Date) -lt $deadline -and -not $p.HasExited) {
                if (-not $clock) {
                    foreach ($f in @(Get-ChildItem -LiteralPath $sand.data -Recurse -Filter '*.jsonl' -File -ErrorAction SilentlyContinue)) {
                        $txt = ''
                        try { $txt = [IO.File]::ReadAllText($f.FullName) } catch { }
                        if ($txt -like '*ConfigInvalidFlag*') { $clock = $true; break }
                    }
                    Start-Sleep -Milliseconds 10
                    continue
                }
                # The file may be open for writing at this instant; a failed
                # append is not a failed case, the next one is 50 ms away.
                try { [IO.File]::AppendAllText($sand.ov, "`r`n", [Text.UTF8Encoding]::new($false)); $appends++ } catch { }
                Start-Sleep -Milliseconds 50
            }
            $null = $p.WaitForExit(120000)
            if (-not $p.HasExited) { $p.Kill(); throw 'the toggle did not exit within 120s' }
            $code = -1
            try { $code = [int]((Get-Content -LiteralPath $cf -Raw).Trim()) } catch { }
        } finally {
            Pop-ChildEnv -Prev $prev
        }

        $out = ''
        try { $out = [IO.File]::ReadAllText($of) } catch { }
        $now = [IO.File]::ReadAllText($sand.ov)
        # The seeded text survives as an exact PREFIX only if this run did not
        # replace the file; the appended bytes make it strictly longer.
        $seedHeld  = ($now.StartsWith($seed) -and $now.Length -gt $seed.Length)
        $valueHeld = $now.Contains('"delegate": "false"')
        $replaced  = (-not $now.StartsWith($seed))

        # The exit-3 invariant reads this like any other run: the file DID change
        # here, but by this suite's hand rather than the toggle's, so what C3 is
        # entitled to ask of it is only that the toggle's own text is not in it.
        [void]$script:Runs.Add([pscustomobject]@{ tag = "a5-$attempt"; code = $code; changed = $replaced })

        if (-not $clock) {
            $a5note = 'the ConfigInvalidFlag clock never appeared, so no mutation was ever made'
            continue
        }
        if ($appends -eq 0) {
            $a5note = 'the clock appeared but every append failed, so the file never changed under the child'
            continue
        }
        if (-not $seedHeld -and -not $replaced) {
            $a5note = 'the file is neither the seed plus appends nor a replacement; the run cannot be read either way'
            continue
        }
        if ($seedHeld -and ($out -notlike '*CHANGED UNDER US*')) {
            # The file survived, but not demonstrably because of the SHA check:
            # an append made by this suite can land while the child has the file
            # open, and the child then refuses on an I/O error instead. That is
            # this harness getting in the way, not an answer about the code, so
            # it is retried rather than scored either way. Observed once, under a
            # deliberately broken build, on 3 August 2026.
            $a5note = 'the write did not happen but the refusal did not name CHANGED UNDER US, so the reason it did not happen is not established'
            continue
        }
        $a5 = @{ code = $code; out = $out; seedHeld = $seedHeld; valueHeld = $valueHeld; appends = $appends }
    }

    if ($null -eq $a5) {
        throw ("the changed-under-us case could not be made conclusive in 3 attempts: $a5note")
    }

    Add-Result 'changed under us: a config.json modified after the toggle read it is NOT overwritten' `
        ($a5.seedHeld -and $a5.valueHeld) `
        ("after {0} append(s) made while the child ran: the file still began with the seeded text = {1}; interaction.delegate was still the operator's own value = {2}. fd8d023 replaces the whole file with text built from the stale read and loses both" -f $a5.appends, $a5.seedHeld, $a5.valueHeld)

    Add-Result 'changed under us: the refusal SAYS so, and exits 3' `
        (($a5.out -like '*CHANGED UNDER US*') -and $a5.code -eq 3) `
        ("exit was $($a5.code) and stdout " + $(if ($a5.out -like '*CHANGED UNDER US*') { 'named it' } else { 'did not mention CHANGED UNDER US' }) + ". A silent discard is the lost update bin\lwg-cmdlib.ps1:367-373 exists to prevent; fd8d023 exits 0 here and says nothing")

    # =======================================================================
    # SECTION B - an already-unparseable config.json  (#105)
    # BASELINE fd8d023: exit 3 with
    #   "The delegate command could not complete: the edited config.json would
    #    not parse (Invalid object passed in ... <THE WHOLE FILE> ...)"
    # measured at 33,228 characters for a 33,175-byte file.
    # =======================================================================
    Write-Output ''
    Write-Output 'B. an already-broken config.json (#105)'

    Write-ConfigFile -Path $sand.cfg -Text (New-ConfigText -BreakJson -PadKb 30)
    Write-ConfigFile -Path $sand.ov  -Text (New-OverrideText)
    $bBytes = Get-Bytes -Path $sand.cfg
    $d = Invoke-Toggle -Sand $sand -ScriptArgs '-Flag delegate on' -Tag 'b1'

    # The wording assertions are what discriminate the fix, and they are stated
    # as three separate facts rather than one "does not blame the edit": with the
    # _source pre-check deleted, the surviving message still avoids the old
    # phrase, so a test that only forbids the phrase stays green on a build with
    # no pre-check in it at all. Verified by deleting that check on 3 August 2026.
    # What only the pre-check can produce is the REFUSED banner, the BUILT-IN
    # DEFAULTS sentence and the doctor route, so those are what is asserted.
    Add-Result 'broken config: the refusal blames the FILE, not this command''s edit' `
        (($d.out -notlike '*the edited config.json*') -and ($d.out -notlike '*the edit this command made*') -and `
         ($d.out -like '*REFUSED - nothing was written.*') -and ($d.out -like '*BUILT-IN DEFAULTS*') -and ($d.out -match 'does not parse')) `
        ('the message must name the file that was already broken, and must be the pre-write refusal rather than a post-edit parse failure wearing better words. fd8d023 says "the edited config.json would not parse", which sends the operator to report a bug in the toggle. stdout began: ' + (($d.out -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -First 3) -join ' | '))

    Add-Result 'broken config: the operator is routed to the doctor, as /lw-watchtower:config is' `
        ($d.out -like '*doctor*') `
        'bin\lwg-config.ps1:266 names the doctor''s config-registry check for exactly this state; the two commands must not disagree about what a broken config.json means'

    # THE BOUND, not the line split. The fixture is MINIFIED - one line, 60 KB -
    # so taking the first line of ConvertFrom-Json's message takes the whole
    # thing, and only Get-LwgBriefParseError's character limit can keep stdout
    # small. With a multi-line fixture this case stayed green when that limit was
    # raised from 160 to 100000, which is the vacuity it is written to avoid.
    Write-ConfigFile -Path $sand.cfg -Text (New-ConfigText -BreakJson -PadKb 60 -Minify)
    Write-ConfigFile -Path $sand.ov  -Text (New-OverrideText)
    $bMin = Get-Bytes -Path $sand.cfg
    $dMin = Invoke-Toggle -Sand $sand -ScriptArgs '-Flag delegate on' -Tag 'b3'
    $bMinText = [Text.UTF8Encoding]::new($false).GetString($bMin)
    Add-Result 'broken config: stdout is BOUNDED even when the file is ONE line' `
        ($dMin.out.Length -lt 1500 -and $bMin.Length -gt 50000 -and ($bMinText.Split([char]10).Count -eq 1)) `
        ("stdout was {0} characters for a {1}-byte, {2}-line config. Windows PowerShell 5.1's ConvertFrom-Json embeds its whole input in the message; the bound asserted here is 1500" -f `
            $dMin.out.Length, $bMin.Length, $bMinText.Split([char]10).Count)

    # CONTROL: true before the fix as well - fd8d023 really does leave the file
    # alone here, and what was wrong there was the diagnosis, not the write. It
    # is kept because a fix that started writing to a config it cannot read would
    # be a far worse defect than the one being fixed.
    Add-Result 'CONTROL broken config: nothing is written' `
        (-not $d.changed -and -not $dMin.changed) `
        'the file must be left exactly as it was - compared byte for byte before and after, on both broken fixtures'

    # CONTROL. A read is not a write, and the refusal must not swallow one: an
    # operator whose config is broken still needs to be able to ask what the
    # state is, and line 845 of the toggle already prints BUILT-IN DEFAULTS.
    # fd8d023 passes this too.
    $e = Invoke-Toggle -Sand $sand -ScriptArgs '-Flag delegate' -Tag 'b5'
    Add-Result 'CONTROL broken config: a REPORT-ONLY run still reports, and does not refuse' `
        ($e.code -eq 0 -and ($e.out -like '*BUILT-IN DEFAULTS*') -and (-not $e.changed)) `
        ("exit was {0}; a run with no argument writes nothing and must still print the state, naming the fallback. Refusing a read would be a regression this fix must not make" -f $e.code)

    # =======================================================================
    # SECTION C - exit 3 means config.json was not changed  (#27)
    # BASELINE fd8d023, executed: with the modules-less fixture the write at line
    # 786 lands, the read-back throw at 803 fires, and line 1051 exits 3 - while
    # bin\lwg-toggle.ps1's exit-code table and commands\delegate.md both define
    # 3 as "config.json was not changed".
    # =======================================================================
    Write-Output ''
    Write-Output 'C. exit 3 means the file was not changed (#27)'

    Write-ConfigFile -Path $sand.cfg -Text (New-ConfigText -NoModules)
    Write-ConfigFile -Path $sand.ov  -Text (New-OverrideText)
    $f = Invoke-Toggle -Sand $sand -ScriptArgs '-Flag delegate on' -Tag 'c1'

    Add-Result 'modules-less config: the file is NOT written' `
        ((-not $f.changed) -and (-not $f.base_changed)) `
        ("exit was {0}; the override {1} and config.json {2}. fd8d023 writes and then exits 3, so an operator reading commands\delegate.md:49 verbatim is told the opposite of what happened. Both files are checked because the refusal has to hold for the file this command writes AND for the one it reads" -f `
            $f.code, $(if ($f.changed) { 'CHANGED on disk' } else { 'was untouched' }), $(if ($f.base_changed) { 'CHANGED on disk' } else { 'was untouched' }))

    Add-Result 'modules-less config: refused with exit 3 and a reason naming the modules block' `
        ($f.code -eq 3 -and ($f.out -like '*modules*') -and ($f.out -like '*BUILT-IN DEFAULTS*')) `
        ("exit was {0}. The file parses, so 'does not parse' would be false; what is wrong is the missing top-level modules block that makes Get-LwgConfig fall back (lib\common.ps1:452). stdout: {1}" -f `
            $f.code, (($f.out -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -First 4) -join ' | '))

    # The invariant over every run is section G, at the END of the file. It used
    # to be evaluated here, which meant it read only the runs sections A to C had
    # made - its comment claimed "every child this suite ran" while sections D, E
    # and F had not run yet.

    # =======================================================================
    # SECTION D - the behaviour that must NOT change
    # All four pass at fd8d023 as well. They pin the other direction: a fix that
    # refuses everything, reformats the file, or collapses the exit codes fails
    # here.
    # =======================================================================
    Write-Output ''
    Write-Output 'D. controls - what the fix must not have broken'

    $good = New-ConfigText
    $goodOv = New-OverrideText
    Write-ConfigFile -Path $sand.cfg -Text $good
    Write-ConfigFile -Path $sand.ov  -Text $goodOv
    $g = Invoke-Toggle -Sand $sand -ScriptArgs '-Flag delegate on' -Tag 'd1'
    $gTextAfter = [Text.UTF8Encoding]::new($false).GetString($g.after)

    Add-Result 'CONTROL: an ordinary toggle writes the value and exits 0' `
        ($g.code -eq 0 -and $gTextAfter.Contains('"delegate": true') -and ($g.out -like '*delegate is ON*')) `
        ("exit {0}; the file must hold `"delegate`": true and the report must say ON" -f $g.code)

    Add-Result 'CONTROL: the edit is SURGICAL - only the one literal moved' `
        ($gTextAfter -eq $goodOv.Replace('"delegate": false', '"delegate": true')) `
        'the whole point of the text editor in this script is that the file it writes keeps its bytes except the edited value; a ConvertFrom-Json / ConvertTo-Json round trip would escape the apostrophe and the angle bracket in the fixture''s comment and fail here'

    Write-ConfigFile -Path $sand.cfg -Text $good
    Write-ConfigFile -Path $sand.ov  -Text $goodOv
    $h = Invoke-Toggle -Sand $sand -ScriptArgs '-Flag delegate maybe' -Tag 'd3'
    Add-Result 'CONTROL: a rejected argument still exits 2, prints usage, writes nothing' `
        ($h.code -eq 2 -and (-not $h.changed) -and ($h.out -like '*Usage:*')) `
        ("exit was {0} and the file {1}; 2 and 3 are separate on purpose (bin\lwg-toggle.ps1:72-74)" -f $h.code, $(if ($h.changed) { 'CHANGED' } else { 'was untouched' }))

    # A FOURTH CONTROL WAS HERE - `-Flag verbosity brief`, pinning that the
    # level axis wrote its name and read it back. There is no second axis any
    # more: `verbosity` was deleted with the output-style feature, and a bool is
    # the only shape this script writes.

    # =======================================================================
    # SECTION E - the -ConfigPath seam.  NEW SURFACE, NOT A REGRESSION CASE.
    # -ConfigPath does not exist at fd8d023; the child there dies on a parameter
    # binding error.
    #
    # WHAT IT MEANS CHANGED WITH #11, and the cases changed with it rather than
    # being deleted. -ConfigPath used to name the file the toggle READ AND WROTE.
    # Since the write moved to the override under the state directory it names
    # the file the toggle READS - the shipped DEFAULTS - and nothing else. So
    # the two cases below now pin that: the defaults are taken from the file it
    # was given, and the write still lands in the override rather than in the
    # file named on the command line. The second one is the load-bearing half:
    # a -ConfigPath that could still be written would be a way to put operator
    # state back into any path a caller names, which is the defect this whole
    # change is about.
    # =======================================================================
    Write-Output ''
    Write-Output 'E. the -ConfigPath seam (NEW SURFACE - no fd8d023 baseline)'

    Write-ConfigFile -Path $sand.cfg -Text $good
    Write-ConfigFile -Path $sand.ov  -Text $goodOv
    $ownBefore = Get-Bytes -Path $sand.cfg
    # DELEGATE IS ALREADY true IN THESE DEFAULTS, and it is the only way this
    # case can tell that -ConfigPath was read at all: the report's `global
    # default` line comes from the defaults under the override, so a run that
    # ignored -ConfigPath would show the shipped false instead.
    $altText = $good.Replace('"delegate": false', '"delegate": true')
    $alt = Join-Path $sand.work 'elsewhere.json'
    Write-ConfigFile -Path $alt -Text $altText
    $altBefore = Get-Bytes -Path $alt
    $j = Invoke-Toggle -Sand $sand -ScriptArgs ('-Flag delegate off -ConfigPath "' + $alt + '"') -Tag 'e1'
    $jText = [Text.UTF8Encoding]::new($false).GetString($j.after)

    Add-Result 'NEW SURFACE: -ConfigPath supplies the DEFAULTS the override is merged over' `
        ($j.code -eq 0 -and ($j.out -like '*merged over*' + $alt + '*')) `
        ("exit {0}; the report must name the file it was given as the defaults it resolved against. stdout: {1}" -f `
            $j.code, (($j.out -split "`r?`n" | Where-Object { $_ -match 'stored in|merged over' }) -join ' | '))

    Add-Result 'NEW SURFACE: the write still lands in the override, not in the file -ConfigPath named' `
        ($jText.Contains('"delegate": false') -and ((Get-B64 (Get-Bytes -Path $alt)) -eq (Get-B64 $altBefore))) `
        'a -ConfigPath that could be WRITTEN would put operator state back into any path a caller names, which is exactly what #11 moved it out of'

    Add-Result 'NEW SURFACE: -ConfigPath leaves the plugin''s own config.json alone' `
        ((Get-B64 (Get-Bytes -Path $sand.cfg)) -eq (Get-B64 $ownBefore)) `
        'a seam that still touched the real file would be a sandbox that is not one'

    # =======================================================================
    # SECTION F - nothing on the write or report path reads USERPROFILE
    #
    # THREE CASES WERE DELETED FROM THIS SECTION and this comment is what
    # replaces them. They pinned a report that throws AFTER a verified write: at
    # fd8d023 AND 19bb85d, with USERPROFILE unset, `Join-Path $env:USERPROFILE
    # '.claude\settings.json'` in the output-style ACTIVATION block threw under
    # $ErrorActionPreference='Stop', landed in the single catch at the bottom of
    # bin\lwg-toggle.ps1 and exited 3 on a config.json that HAD been written -
    # measured as `-Flag plain on` -> exit 3, file CHANGED. That block was
    # reached ONLY by the two `style` flags, and it went with them when the
    # output-style feature was deleted, so there is no input left that drives
    # it. The $script:LwgVerified guard those cases proved is still in the
    # toggle and is still correct to keep - it guards the class, not that line -
    # but NOTHING HERE EXERCISES IT NOW. That is recorded in the header under
    # WHAT A GREEN RUN DOES NOT MEAN rather than papered over.
    #
    # What survives is the former CONTROL, which is now the whole point of the
    # section: with the environment-fed line gone, an unset USERPROFILE must be
    # of no consequence to any run at all. BASELINE fd8d023, where it also
    # passes - `delegate` never reached the ACTIVATION block there either.
    # =======================================================================
    Write-Output ''
    Write-Output 'F. USERPROFILE unset is of no consequence (three cases deleted - see the comment)'

    Write-ConfigFile -Path $sand.cfg -Text $good
    Write-ConfigFile -Path $sand.ov  -Text $goodOv
    $l = Invoke-Toggle -Sand $sand -ScriptArgs '-Flag delegate on' -Tag 'f4' -NoUserProfile
    $lText = [Text.UTF8Encoding]::new($false).GetString($l.after)
    Add-Result 'CONTROL: with USERPROFILE unset the write is an ordinary exit 0' `
        ($l.code -eq 0 -and $l.changed -and $lText.Contains('"delegate": true') -and ($l.out -notlike '*WAS MADE*')) `
        ("exit was {0} and the override {1}. No line on this path may read USERPROFILE: one that did threw here until the output-style report block was deleted, and the WAS MADE banner - the catch's exit-0-after-a-verified-write route - must not appear on an ordinary run. CLAUDE_PLUGIN_DATA is still set, so the state directory resolves without it" -f `
            $l.code, $(if ($l.changed) { 'CHANGED - correctly' } else { 'was NOT changed' }))

    # =======================================================================
    # SECTION H - THE TERMINAL THE OPERATOR LAUNCHED FROM (#273)
    #
    # Claude Code hands every command the environment the terminal was started
    # with. Started from a PowerShell 7 prompt - the Windows Terminal default
    # wherever pwsh is installed - every `powershell` this plugin spawns is a
    # Windows PowerShell 5.1 child carrying PS7's PSModulePath, 5.1 resolves
    # Microsoft.PowerShell.Utility to PS7's 7.0.0.0 manifest ahead of its own
    # 3.1.0.0, and Get-FileHash - a FUNCTION in 5.1's module, not a compiled
    # cmdlet - is gone.
    #
    # THIS COMMAND FAILED QUIETLY, WHICH IS WHY IT WAS FOUND LAST. The doctor
    # printed "check threw" and the uninstaller exited 3 before a single row, so
    # both were traced. Here the three call sites were bin\lwg-cmdlib.ps1's, all
    # inside a try/catch: Read-LwgTextFile returned ok = $false and the toggle
    # reported "config.json could not be read" and exited 3 - a REFUSAL that
    # blames the operator's file, on a correct install, for a reason that has
    # nothing to do with the file. An operator locked out of Bash by the gate
    # runs this command to get out, and is told their config is broken.
    #
    # RED AT 3e36d79 with this hunk alone: exit 3, nothing written, the refusal
    # naming config.json. The fixture is New-NoFileHashRunner's, whose header
    # in tests\uninstall_footprint.ps1 states what it reproduces and what it
    # does not - it makes the CONSEQUENCE deterministic on any runner; that a
    # PowerShell 7 launch produces that state was measured by hand and recorded
    # on #273, and by nothing in these suites.
    #
    # bin\lwg-toggle.ps1's OWN call site moved with them and has NO case here,
    # stated rather than implied: it sits in the read-back-disagrees branch,
    # which is reachable only when something rewrites config.override.json
    # between this command's write and its re-read. Nothing in this harness can
    # arrange that, and a case that could would be racing itself.
    # =======================================================================
    Write-Output ''
    Write-Output 'H. a child that cannot resolve Get-FileHash still writes (#273)'

    Write-ConfigFile -Path $sand.cfg -Text $good
    Write-ConfigFile -Path $sand.ov  -Text $goodOv
    $noFh = New-NoFileHashRunner -Path (Join-Path $sand.work 'run-toggle-nofh.ps1') -Target $sand.toggle
    $h1 = Invoke-Toggle -Sand $sand -ScriptArgs '-Flag delegate on' -Tag 'h1' -ScriptPath $noFh
    $h1Text = [Text.UTF8Encoding]::new($false).GetString($h1.after)
    $h1Bad = @()
    if ($h1.code -ne 0) { $h1Bad += "exit $($h1.code) rather than 0" }
    if (-not $h1.changed) { $h1Bad += 'the override was NOT written' }
    if ($h1Text -notmatch '"delegate"\s*:\s*true') { $h1Bad += 'the override does not hold the value that was asked for' }
    if ($h1.out -match '(?i)could not be read' -or $h1.err -match '(?i)could not be read') {
        $h1Bad += 'the run still refuses with "could not be read"'
    }
    if (($h1.out + $h1.err) -match 'Get-FileHash') { $h1Bad += 'Get-FileHash reached the output' }
    Add-Result 'a run whose child cannot resolve Get-FileHash still writes the override and exits 0 (#273)' `
        ($h1Bad.Count -eq 0) `
        (($h1Bad -join '; ') + " | exit $($h1.code), override $(if ($h1.changed) { 'CHANGED' } else { 'NOT changed' }). " +
         "Until bin\lwg-cmdlib.ps1's three Get-FileHash call sites moved to Get-LwgFileSha256 this exited 3 with " +
         "'config.json could not be read', which reads as a broken config file and is nothing of the kind. Output:`n$($h1.out)`n$($h1.err)")

    # =======================================================================
    # SECTION I - #270, two state directories and a command that cannot tell
    # which one a hook reads
    #
    # A hook is handed $CLAUDE_PLUGIN_DATA by Claude Code. This command runs
    # through Bash(powershell:*) and is never handed it, so it falls through to
    # Get-LwgStateDirInfo's discovery and RANKS the lw-watchtower* siblings by
    # most recent write. An operator who has run this plugin from a marketplace
    # install AND from a checkout has two of them, and the two readers then land
    # on different files. THIS COMMAND IS WHERE THAT WAS MEASURED:
    # /lw-watchtower:delegate off exited 0 and printed "delegate is OFF" with
    # "[merged over the defaults; this is what a hook reads]" beside the file it
    # had written, and the very next main-thread Bash call was refused exit 2 by
    # a gate reading the override in the OTHER directory. Seconds later the same
    # command reported ON, from the other file, with no operator action between.
    #
    # THE CODE FIX FOR THIS LANDED IN #292 AND THIS CASE DID NOT, and the reason
    # is worth keeping: the case moves this suite's count, that count was quoted
    # in files two other lanes owned in the same wave, and moving it would have
    # failed Documentation claims on a number that lane could not fix. The
    # deferral is the whole of why it is here now.
    #
    # SO THE RED IS AT 192176b, NOT AT THIS BRANCH'S BASE, and that is stated
    # rather than glossed: at 3e36d79 the refusal is already in
    # bin/lwg-toggle.ps1, so these three cases are green there with the test hunk
    # alone. 192176b is main immediately before #292, and I1 and I2 fail there.
    #
    # EVERY CASE ABOVE THIS SECTION RAN WITH CLAUDE_PLUGIN_DATA SET, which is a
    # hook's environment and not this command's. -NoPluginData puts it back on
    # its own spawn.
    # =======================================================================
    Write-Output ''
    Write-Output 'I. two state directories, and which file a hook reads (#270)'

    # Two suffixed candidates under the profile's plugins\data, which is where
    # discovery looks when CLAUDE_PLUGIN_DATA is unset. The marketplace-shaped
    # one holds the operator's real choice; the checkout-shaped one is newer, so
    # the mtime ranking prefers it - which is exactly the measured failure.
    $iData   = Join-Path $sand.profile 'plugins\data'
    $iMarket = Join-Path $iData 'lw-watchtower-leapware-watchtower'
    $iInline = Join-Path $iData 'lw-watchtower-inline'
    foreach ($d in @($iMarket, $iInline)) { [void](New-Item -ItemType Directory -Path $d -Force) }
    $iOv = Join-Path $iMarket 'config.override.json'
    [IO.File]::WriteAllText($iOv, '{"interaction":{"delegate":true}}', [Text.UTF8Encoding]::new($false))
    Start-Sleep -Milliseconds 1100
    [IO.File]::WriteAllText((Join-Path $iInline 'marker.txt'), 'newer', [Text.ASCIIEncoding]::new())

    Write-ConfigFile -Path $sand.cfg -Text $good
    $i1 = Invoke-Toggle -Sand $sand -ScriptArgs '-Flag delegate off' -Tag 'i1' -CfgPath $iOv -NoPluginData
    $i1wrote = @(Get-ChildItem -LiteralPath $iData -Recurse -Filter 'config.override.json' -File -ErrorAction SilentlyContinue)

    Add-Result 'I1 a write is REFUSED when two state directories are candidates (#270)' `
        ($i1.code -eq 3 -and $i1wrote.Count -eq 1 -and -not $i1.changed -and ($i1.out -like '*AMBIGUOUS*')) `
        ("exit was {0}, the seeded override was {1}, and {2} config.override.json file(s) exist under plugins\data (expected the 1 that was seeded). This command IS the documented escape hatch from an armed gate: an operator locked out of Bash runs it, and reporting 'delegate is OFF' over a write nothing reads leaves them locked out having done the one thing they were told to do. stdout: {3}" -f `
            $i1.code, $(if ($i1.changed) { 'CHANGED' } else { 'untouched - correctly' }), $i1wrote.Count,
            (($i1.out -split "`r?`n" | Select-Object -First 8) -join ' | '))

    $i2 = Invoke-Toggle -Sand $sand -ScriptArgs '-Flag delegate' -Tag 'i2' -CfgPath $iOv -NoPluginData

    Add-Result 'I2 the REPORT names both candidates instead of claiming the file it picked is what a hook reads (#270)' `
        ($i2.code -eq 0 -and ($i2.out -like '*AMBIGUOUS*') -and `
         ($i2.out -like '*lw-watchtower-inline*') -and ($i2.out -like '*lw-watchtower-leapware-watchtower*')) `
        ("exit was {0}. A report is allowed to run here - nothing is written - but it is not allowed to label one of two files '[merged over the defaults; this is what a hook reads]' when it cannot know that, which is the sentence an operator read while the gate went on refusing them. stdout: {1}" -f `
            $i2.code, (($i2.out -split "`r?`n" | Select-Object -First 8) -join ' | '))

    # THE CONTROL, and it is what makes I1 a statement about ambiguity rather
    # than about the environment: remove the second candidate and the identical
    # command writes and exits 0. Without it a "fix" that simply refused whenever
    # CLAUDE_PLUGIN_DATA is unset would pass I1 and I2 and break every
    # marketplace install, where the variable is never set for a command.
    Remove-Item -LiteralPath $iInline -Recurse -Force
    $i3 = Invoke-Toggle -Sand $sand -ScriptArgs '-Flag delegate off' -Tag 'i3' -CfgPath $iOv -NoPluginData
    $i3text = ''
    try { $i3text = [IO.File]::ReadAllText($iOv) } catch { }

    Add-Result 'I3 CONTROL: one candidate and the same command writes, into the directory that already had the override (#270)' `
        ($i3.code -eq 0 -and ($i3text -match '"delegate"\s*:\s*false') -and ($i3.out -notlike '*AMBIGUOUS*')) `
        ("exit was {0} and the override now reads [{1}]. The refusal above must be about not knowing WHICH file, not about the variable being unset - a command that refused whenever CLAUDE_PLUGIN_DATA is absent would refuse on every ordinary install. stdout: {2}" -f `
            $i3.code, $i3text.Trim(), (($i3.out -split "`r?`n" | Select-Object -First 6) -join ' | '))

    # =======================================================================
    # SECTION G - the invariant, over every run this suite made
    # Evaluated LAST, so $script:Runs holds sections A to I rather than A to C.
    # =======================================================================
    Write-Output ''
    Write-Output 'G. the exit-3 invariant over every run above'

    $threes  = @($script:Runs | Where-Object { $_.code -eq 3 })
    $liars   = @($threes | Where-Object { $_.changed })
    # The name says "free of the toggle's own edit" rather than "byte-identical"
    # because of A5 and only A5: that run's file really does differ from what it
    # was seeded with - THIS SUITE appended to it - and what the toggle is
    # entitled to be held to there is that none of its edit is in the file. Every
    # other run in the list is a byte comparison. Naming it byte-identical would
    # be a case whose title claims more than its assertion, which is the failure
    # this suite exists to catch in someone else's code.
    Add-Result 'INVARIANT: every exit 3 in this run left config.json free of the toggle''s own edit' `
        ($threes.Count -ge 3 -and $liars.Count -eq 0) `
        ("{0} run(s) of {1} exited 3 and {2} of them carried the toggle's edit: {3}. bin\lwg-toggle.ps1's exit-code table and commands\delegate.md both define 3 as 'nothing was written', so a single one here is a documented claim the code contradicts. (At least 3 exit-3 runs are required, so this cannot pass by there being none.)" -f `
            $threes.Count, $script:Runs.Count, $liars.Count, $(if ($liars.Count) { ($liars | ForEach-Object { $_.tag }) -join ', ' } else { 'none' }))

    # THE #11 INVARIANT, over the same set. Every case above says something
    # about one run; this says the thing that has to be true of ALL of them,
    # which is what the issue actually asks for: after any invocation of this
    # command - a write, a refusal, a rejected argument, a report - the file
    # inside the plugin's git working tree is byte-for-byte what it was. A
    # `git status` on a fresh clone is clean, and /lw-watchtower:update has
    # nothing to refuse over.
    #
    # It goes RED at 4342980 on the writing runs, and the floor is what stops it
    # passing on a suite that stopped writing: at least three runs here must
    # have exited 0 having changed the override.
    $wrote     = @($script:Runs | Where-Object { $_.code -eq 0 -and $_.changed })
    $dirtiers  = @($script:Runs | Where-Object { $_.base_changed })
    Add-Result 'INVARIANT: no run of this command changed the plugin root config.json at all (#11)' `
        ($wrote.Count -ge 3 -and $dirtiers.Count -eq 0) `
        ("{0} run(s) of {1} moved a byte of config.json: {2}. config.json is TRACKED and inside the plugin's own git working tree, so any one of them leaves the checkout dirty and makes /lw-watchtower:update refuse to pull for good - which is #11. ({3} run(s) wrote the override and exited 0; at least 3 are required, so this cannot pass by the command having stopped writing.)" -f `
            $dirtiers.Count, $script:Runs.Count, $(if ($dirtiers.Count) { ($dirtiers | ForEach-Object { $_.tag }) -join ', ' } else { 'none' }), $wrote.Count)

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
Write-Output 'Every case above passed. Read that as "the toggle takes a backup, re-checks'
Write-Output 'the file, keeps a BOM, refuses a config it cannot read back, and never returns'
Write-Output 'exit 3 after changing the file" - and NOT as "the write path is safe". See the'
Write-Output 'header for the three guards no case here reaches - one of which lost its only'
Write-Output 'coverage when the output-style flags were deleted.'
Write-Output 'EXIT: 0'
exit 0
