#requires -version 5
<#
  LW-WATCHTOWER doctor - what is NOT working.

      powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-doctor.ps1

  Backs /lw-watchtower:doctor. The logic lives here rather than in the command's
  prose because a health check a model performs by reading instructions is a
  health check that reports whatever the model infers. This file either finds a
  fault or it does not, and it exits on the answer.

  THIS SCRIPT IS ALLOWED TO FAIL, and that is the entire point of it. A doctor
  that cannot return a bad verdict is the exact defect this plugin exists to
  catch: a switch wired to nothing, reporting green. Every check below was
  written by first arranging for it to fail and confirming it said so.

  Exit codes - a caller reads these and nothing else. Where several apply,
  3 beats 1 beats 2:

      0  every check passed
      1  at least one check FAILED - something is broken now
      2  no failures, but at least one WARNING - working, with a caveat
      3  the doctor itself could not complete; the lines printed are a
         fragment of a checkup rather than the result of one

  3 is separate from 1 deliberately. "I found a fault" and "I could not look"
  are different statements, and collapsing them would let a crashed doctor be
  read as a diagnosis.

  What a PASS here does and does not mean is printed at the end of every run,
  because the checks below cover the plugin's wiring and not its behaviour. The
  one piece of behaviour that IS tested lives elsewhere: tests\gate_delegate.ps1
  exercises the only gate this plugin ships. The two suites that went on 30 July
  2026 - the gate regression suite with the destructive command gate, the
  permissions.deny parity test with secret_scan - are not coming back, and
  neither is what they covered. A green doctor is a statement about wiring: that
  hooks are registered, that scripts they name exist, that a module's switch is a
  key that really exists, and that state is writable. It is not a statement that
  anything is protected.
#>

param(
    # Print only the verdict line and any WARN/FAIL rows, and drop the module
    # inventory from the informational roster at the foot. The GATES paragraphs
    # in that roster survive -Quiet on purpose: a gate that can refuse a tool
    # call is not noise at any verbosity. The exit code is identical either
    # way - quiet changes what is shown, never what is judged.
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

# Everything printed below is ASCII. The doctor may well be the thing you run
# when the console encoding is what is broken.
$script:Rows     = New-Object System.Collections.ArrayList
$script:Aborted  = $null

# The slash-command prefix, used only in prose. It carries a literal default
# because the report at the bottom is printed on the abort path too - including
# the abort where dot-sourcing the file that defines Get-LwgPluginName is
# itself what failed.
$script:Slug     = 'lw-watchtower'

function Add-Row {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][ValidateSet('PASS', 'INFO', 'WARN', 'FAIL')][string]$Status,
        [Parameter(Mandatory = $true)][string]$Detail
    )
    [void]$script:Rows.Add([pscustomobject]@{ Id = $Id; Status = $Status; Detail = $Detail })
}

# A check that throws is a FAILED check, never a skipped one. An exception
# swallowed into silence is how a monitor comes to report green over a fault -
# so the catch below records the fault rather than hiding it.
function Invoke-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][scriptblock]$Body
    )
    try { & $Body }
    catch { Add-Row -Id $Id -Status 'FAIL' -Detail "check threw: $($_.Exception.Message)" }
}

# Collect every string in a decoded JSON tree - used to find the script paths
# buried in hooks.json's args arrays without hardcoding its shape.
function Get-JsonStrings {
    param($Node)
    if ($null -eq $Node) { return }
    if ($Node -is [string]) { return $Node }
    if ($Node -is [System.Collections.IEnumerable]) {
        foreach ($item in $Node) { Get-JsonStrings -Node $item }
        return
    }
    if ($Node -is [System.Management.Automation.PSCustomObject]) {
        foreach ($p in $Node.PSObject.Properties) { Get-JsonStrings -Node $p.Value }
    }
}

# ---------------------------------------------------------------------------
# A FILE HASH THAT DOES NOT NEED Get-FileHash (#273) - THE CANONICAL COPY
# ---------------------------------------------------------------------------
# Get-FileHash is NOT a compiled cmdlet in Windows PowerShell 5.1. It is a
# FUNCTION exported by the Microsoft.PowerShell.Utility module, and it stops
# resolving the moment a PowerShell 7 PSModulePath is inherited. Claude Code
# hands every hook and every command the environment the terminal was launched
# with, so an operator who started the CLI from a PowerShell 7 prompt - the
# Windows Terminal default wherever pwsh is installed - runs every script in
# bin\ with PS7's Microsoft.PowerShell.Utility 7.0.0.0 ahead of 5.1's own
# 3.1.0.0 on the path. 5.1 then resolves the module name to the Core-only
# manifest, whose FunctionsToExport is empty, and Get-FileHash is simply gone.
# Measured on 2026-09-04 against 6aebcd6:
#
#     PS7> cmd /c 'powershell -NoProfile -Command "Get-FileHash ..."'
#     The term 'Get-FileHash' is not recognized as the name of a cmdlet ...
#
# What that cost, on a CORRECT install with the status line wired: this doctor
# printed [FAIL] statusline "check threw" and VERDICT: NOT healthy (exit 1),
# bin\lwg-uninstall.ps1 could not complete at all (exit 3, before it had
# printed a single footprint row), bin\lwg-update.ps1 could not complete, and
# setup -Step detect reported the drift comparison as "could not be compared".
# The hooks and statusline\statusline.ps1 were unaffected - none of them calls
# it - so the plugin WORKED and only the tools that report on it failed.
#
# MODULE-QUALIFYING THE CALL DOES NOT FIX IT, and that is the fix that looks
# right. `Microsoft.PowerShell.Utility\Get-FileHash` fails with the same
# message, because the module that name resolves to IS the shadowing one:
#
#     PS7> cmd /c 'powershell -NoProfile -Command "Microsoft.PowerShell.Utility\Get-FileHash ..."'
#     The term 'Microsoft.PowerShell.Utility\Get-FileHash' is not recognized ...
#
# `Import-Module "$PSHOME\Modules\Microsoft.PowerShell.Utility" -Force` DOES
# work and was rejected anyway: it repairs the environment instead of removing
# the dependency, it has to be repeated in every entry point, and it leaves the
# next 5.1-module-only call to be found by the next operator.
#
# So the hash is computed from .NET, which is present and identical in both
# editions and needs no module at all. The return is UPPERCASE hex with no
# separators - byte for byte what (Get-FileHash -Algorithm SHA256).Hash
# returned - so every comparison and every printed value is unchanged.
#
# THIS FUNCTION IS DUPLICATED, with the same body, in bin\lwg-uninstall.ps1 and
# bin\lwg-update.ps1, and this copy carries the reasoning for all three.
# bin\lwg-setup.ps1 is the fourth script that had the defect and gets no copy:
# it has carried its own .NET Get-Sha256 since the settings-file reader was
# written (bin\lwg-setup.ps1:199), which is exactly why `setup -Step detect`
# still printed a sha256 for settings.json from a PowerShell 7 launch while the
# status-line drift line beside it read "could not be compared" - two hashes in
# one report, one of them already immune. That site now calls the helper that
# was already there.
#
# WHY NOT ONE COPY IN lib\common.ps1: there is no file all four already load
# except lib\common.ps1, and lib\common.ps1 is the HOOK path - SessionStart and
# PreToolUse dot-source it on every turn - so a helper only the lifecycle
# scripts need does not belong there. bin\lwg-cmdlib.ps1 is loaded by uninstall
# and update but NOT by this file or by setup, so it is not the shared place
# either.
#
# TWO CALL SITES ARE STILL Get-FileHash AND ARE NOT FIXED HERE:
# bin\lwg-cmdlib.ps1:356,389,402 (Read-LwgTextFile, Save-LwgTextFile - both
# CATCH, so they degrade to "could not be read" rather than throwing, which is
# why bin\lwg-toggle.ps1 exits 3 with "config.json could not be read" on the
# same machine) and bin\lwg-toggle.ps1:955. Those two files belong to another
# lane this wave; the hunk for them is written on #273.
function Get-LwgFileSha256 {
    <#
      SHA256 of one file as uppercase hex, with no PowerShell module behind it.
      Throws what the file system throws, exactly as Get-FileHash did, so every
      caller's try/catch keeps its meaning.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)

    # ABSOLUTE, ALWAYS. Every .NET call resolves a relative path against the
    # PROCESS working directory, which is wherever the operator ran this from
    # and not this tree.
    $full = [IO.Path]::GetFullPath($Path)
    $sha  = [System.Security.Cryptography.SHA256]::Create()
    try {
        # FileShare::ReadWrite because settings.json is rewritten by the CLI
        # underneath whatever is reading it. Get-FileHash opens the same way;
        # a narrower share would fail on files that used to hash fine.
        $fs = [IO.File]::Open($full, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try { $bytes = $sha.ComputeHash($fs) } finally { $fs.Dispose() }
    } finally { $sha.Dispose() }
    return [BitConverter]::ToString($bytes).Replace('-', '')
}

# ---------------------------------------------------------------------------
# WHETHER THIS RUN HAD TO CHOOSE A STATE DIRECTORY, AND WHAT IT DID NOT LOOK AT
# ---------------------------------------------------------------------------
# #270. Claude Code hands every HOOK $CLAUDE_PLUGIN_DATA and hands a COMMAND -
# which runs through Bash(powershell:*) - nothing at all, so a command discovers
# its state directory by ranking `<name>*` directories under the data root by
# the newest write anywhere inside them. With two of those on disk, which is
# what an operator gets after running this plugin once from a checkout
# (--plugin-dir writes lw-watchtower-inline) and once from the marketplace
# (lw-watchtower-<marketplace>), the answer moves with whichever was written
# last - and this report said:
#
#     [PASS] state-dir  ...\lw-watchtower-inline (source 'discovered', 2 candidate(s))
#     resolved for repo: (not in a repo)   config: config.json   override: none - these are the shipped defaults
#     VERDICT: healthy - no check failed and none raised a caveat
#
# over a config.override.json in the OTHER directory holding
# {"interaction":{"delegate":true}} and a PreToolUse gate refusing every
# main-thread call. Healthy, and no override - both asserted about a directory
# this run had not read. The count was already on the row; nothing read it.
#
# WHAT IS NOT ATTEMPTED HERE, because it cannot be done: making a command and a
# hook resolve the same directory. A command is never handed the variable and is
# never told which directory the CLI chose, so no ranking recovers an answer it
# was never given. What is fixable is the CLAIM, and that is all this does.
#
# RANKED, NOT `candidates`. `candidates` counts every `<name>*` directory,
# including the unsuffixed fallback, and a bare directory beside one suffixed
# sibling counts two while the resolver ranks nothing - it takes the suffixed
# one outright. Only two or more SUFFIXED siblings are a real choice, and only
# on the 'discovered' branch: the 'env' branch chose nothing, so a hook and a
# command handed CLAUDE_PLUGIN_DATA are never told they are ambiguous.
#
# COLLAPSED ONTO Get-LwgStateDirInfo's OWN ANSWER - #270. This function was
# written in this file, by lane F4-D, with a second filesystem scan of its own,
# because lane F4-B's `ranked` key and Get-LwgStateDirSplit were not on that
# PR's base and a call into them would have been red until the other merged.
# Both are on main now, so the duplicated SCAN is gone: the candidate list comes
# from the resolver that actually made the choice, which is the only thing that
# can say what it chose between.
#
# The PRESENTATION stays here rather than moving to lib/common.ps1's
# Get-LwgStateDirSplit, and that is deliberate: this file's lines are indented
# and worded to sit inside a doctor row, and the two commands' lines are worded
# to sit inside a refusal. One shared list of facts, two renderings of it, is
# the right split - a shared renderer would have to be told which caller it was
# serving, which is a parameter standing in for a difference that is real.
function Get-DoctorStateSplit {
    <#
      Returns @{ ambiguous; ranked; lines }. `lines` are ready to print: one per
      suffixed candidate, saying whether it holds a config.override.json and
      which of them this run actually read.
    #>
    param($Info)

    $r = @{ ambiguous = $false; ranked = @(); lines = @() }
    if ($null -eq $Info -or "$($Info.source)" -ne 'discovered') { return $r }

    # .ranked is the SUFFIXED candidates Get-LwgStateDirInfo had to choose
    # between - empty on the env branch, which chooses nothing, and empty when
    # there was no ranking to do. Reading it here rather than re-globbing means
    # the row cannot disagree with the resolution it is reporting on, which a
    # second scan of a directory that may have changed in between could.
    $ranked = @($Info.ranked)
    if ($ranked.Count -lt 2) { return $r }

    $r.ambiguous = $true
    $r.ranked    = $ranked
    foreach ($c in ($ranked | Sort-Object)) {
        $held = $false
        try { $held = [IO.File]::Exists([IO.Path]::Combine($c, 'config.override.json')) } catch { }
        $r.lines += ("      {0}   {1}{2}" -f $c,
                     $(if ($held) { 'HOLDS a config.override.json' } else { 'no config.override.json' }),
                     $(if ("$($Info.path)" -eq "$c") { '   <== this run read this one' } else { '' }))
    }
    return $r
}

try {
    # The doctor must work when run from anywhere, including from a bin/ on
    # PATH, so the root is derived from this file rather than from the cwd.
    $pluginRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $pluginRoot 'lib\common.ps1')
    try { $n = Get-LwgPluginName; if (-not [string]::IsNullOrWhiteSpace($n)) { $script:Slug = $n } } catch { }

    # ---------------------------------------------------------------------
    # 1. plugin manifest
    # ---------------------------------------------------------------------
    Invoke-Check -Id 'plugin-manifest' -Body {
        $p = Join-Path $pluginRoot '.claude-plugin\plugin.json'
        if (-not (Test-Path -LiteralPath $p)) {
            Add-Row -Id 'plugin-manifest' -Status 'FAIL' -Detail "missing: $p - nothing here is a plugin without it"
            return
        }
        $m = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
        if ([string]::IsNullOrWhiteSpace([string]$m.name)) {
            Add-Row -Id 'plugin-manifest' -Status 'FAIL' -Detail 'plugin.json has no "name"'
            return
        }
        # The state dir is resolved from this name (Get-LwgPluginName parses the
        # file by string index and takes the FIRST "name" key), so a manifest
        # whose first key is not `name` silently redirects every log write.
        $resolvedName = Get-LwgPluginName
        if ($resolvedName -ne [string]$m.name) {
            Add-Row -Id 'plugin-manifest' -Status 'FAIL' -Detail "name mismatch: manifest says '$($m.name)' but Get-LwgPluginName reads '$resolvedName' - the state dir is resolved from the latter"
            return
        }
        Add-Row -Id 'plugin-manifest' -Status 'PASS' -Detail "parses; name '$($m.name)', version $($m.version)"
    }

    # ---------------------------------------------------------------------
    # 2. marketplace manifest (optional file, but must parse if present)
    # ---------------------------------------------------------------------
    Invoke-Check -Id 'marketplace' -Body {
        $p = Join-Path $pluginRoot '.claude-plugin\marketplace.json'
        if (-not (Test-Path -LiteralPath $p)) {
            Add-Row -Id 'marketplace' -Status 'INFO' -Detail 'no marketplace.json beside the plugin root, which is CORRECT since the payload restructure: marketplace.json lives at the marketplace repository ROOT and declares "source": "./lw-watchtower", so it is one directory above this plugin root on the dev route and is not copied into the cache at all. Its absence here says nothing about whether the repo can be added with /plugin marketplace add. Do NOT "fix" this by resolving Split-Path -Parent on the plugin root: on the junction route that parent is ~\.claude\skills and on the cache route there is no such parent.'
            return
        }
        $mk = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
        $names = @($mk.plugins | ForEach-Object { [string]$_.name })
        if ($names -notcontains (Get-LwgPluginName)) {
            Add-Row -Id 'marketplace' -Status 'FAIL' -Detail "lists [$($names -join ', ')] but not '$(Get-LwgPluginName)' - the marketplace does not offer this plugin"
            return
        }
        Add-Row -Id 'marketplace' -Status 'PASS' -Detail "parses; marketplace '$($mk.name)' offers $($names.Count) plugin(s): $($names -join ', ')"
    }

    # ---------------------------------------------------------------------
    # 3. hooks are registered AND every script they name exists
    # ---------------------------------------------------------------------
    # "hooks.json parses" is not the question. The question is whether the files
    # it points at are on disk, because a hook whose script is missing is
    # registered, invoked, and silently does nothing - which reads exactly like
    # a hook that ran and found nothing wrong.
    #
    # hooks/hooks.json is DEFAULT-SCANNED from the plugin root. This check used
    # to require a "hooks" key in plugin.json and fail without one, which had the
    # polarity exactly backwards: naming that path in the manifest REPLACES the
    # default scan rather than extending it, and naming the already-scanned path
    # makes Claude Code log a duplicate-hooks-file [ERROR], flag the plugin
    # hook-load-failed and drop it from MCP - for a fault it does not have. So
    # the absence of the key is the correct state and is what this now asserts.
    # See docs/architecture.md, "The manifest declares no paths".
    Invoke-Check -Id 'hooks-declared' -Body {
        $pj = Join-Path $pluginRoot '.claude-plugin\plugin.json'
        $m  = Get-Content -LiteralPath $pj -Raw | ConvertFrom-Json
        $hp = Join-Path $pluginRoot 'hooks\hooks.json'
        if (-not (Test-Path -LiteralPath $hp)) {
            Add-Row -Id 'hooks-declared' -Status 'FAIL' -Detail 'hooks\hooks.json does not exist - no hook of this plugin can fire'
            return
        }
        # A "hooks" key naming the default path is the duplicate-load fault. A
        # key naming some ADDITIONAL file is legitimate, so only the collision
        # is called out.
        $declared = [string]$m.hooks
        if (-not [string]::IsNullOrWhiteSpace($declared)) {
            $dp = Join-Path $pluginRoot $declared.TrimStart('.', '/', '\')
            if ((Test-Path -LiteralPath $dp) -and
                ([IO.Path]::GetFullPath($dp) -eq [IO.Path]::GetFullPath($hp))) {
                Add-Row -Id 'hooks-declared' -Status 'FAIL' -Detail "plugin.json declares hooks '$declared', which is the auto-scanned hooks\hooks.json - Claude Code logs a duplicate-hooks-file ERROR and flags this plugin hook-load-failed. Remove the key"
                return
            }
        }
        $h      = Get-Content -LiteralPath $hp -Raw | ConvertFrom-Json
        $events = @($h.hooks.PSObject.Properties.Name)
        if ($events.Count -eq 0) {
            Add-Row -Id 'hooks-declared' -Status 'FAIL' -Detail "$hp registers no events"
            return
        }

        $missing = @()
        $seen    = 0
        foreach ($s in (Get-JsonStrings -Node $h)) {
            if ($s -notlike '*${CLAUDE_PLUGIN_ROOT}*') { continue }
            $seen++
            $real = $s.Replace('${CLAUDE_PLUGIN_ROOT}', $pluginRoot)
            if (-not (Test-Path -LiteralPath $real)) { $missing += $s }
        }
        if ($missing.Count -gt 0) {
            Add-Row -Id 'hooks-declared' -Status 'FAIL' -Detail "$($missing.Count) of $seen hook scripts do not exist: $($missing -join ', ')"
            return
        }
        Add-Row -Id 'hooks-declared' -Status 'PASS' -Detail "$($events.Count) events ($($events -join ', ')); all $seen referenced scripts exist"
    }

    # ---------------------------------------------------------------------
    # 4. config.json parses AND its module list has not drifted from the registry
    # ---------------------------------------------------------------------
    # README: "The NAME list must stay identical to config.json's `modules`
    # keys - drift there silently mis-reports coverage." Nothing enforced that
    # until now. A flag in config.json for a module the registry has never heard
    # of is a switch wired to nothing; a registry entry with no flag is a module
    # nobody can turn off.
    #
    # ONE CLASS OF ENTRY IS EXEMPT FROM THE PARITY HALF AND NOT FROM THE RULE
    # BEHIND IT. A registry entry may declare `switch = @{ block; key; default }`,
    # meaning its flag lives somewhere in config.json other than the `modules`
    # block - delegate_gate's is interaction.delegate, so that the one gate has
    # exactly one switch instead of a `modules` flag AND a command that writes a
    # different key. Such an entry has no `modules` key by design, so demanding
    # one would fail the build for being correct. What it gets instead is a
    # STRICTER check: the key it declares must actually be present in
    # config.json. That is the same question in the same direction - is this
    # module's switch real - and it is the one that catches a typo in the
    # declared key, which would otherwise leave the gate permanently and
    # silently off with everything reporting healthy.
    #
    # PRESENCE WAS NOT ENOUGH, AND THE SENTENCE ABOVE IS WHY. Until 3 August
    # 2026 both halves of this check asked only whether a KEY was there: the
    # switch loop tested `$null -eq $v` and stopped, and the `modules` half read
    # .PSObject.Properties.Name and never looked at a value at all. So a typo in
    # the VALUE produced exactly the state that sentence promises to prevent.
    #
    #     "interaction": { "delegate": "true" }
    #
    # is non-null, so the check passed and the doctor said healthy - while
    # Test-LwgFlag, which is what lib\gate_delegate.ps1 actually reads, requires
    # `$g -is [bool]`, ignored the string, and left the only gate this plugin
    # ships on its registry default of $false. A monitor reporting green over a
    # switch wired to nothing is the founding defect this file exists to catch,
    # spelled by the file that exists to catch it.
    #
    # THE RULE APPLIED BELOW IS THE READER'S RULE AND NOT A THIRD ONE. It is
    # `-isnot [bool]` against the same `$cfg.$b.$k` lookup Test-LwgFlag makes
    # and the same `$cfg.modules.<name>` lookup Test-LwgModule makes, both in
    # lib\common.ps1. A checker that decided for itself what counts as a valid
    # flag would be a second answer to a question the reader already answers,
    # which is the reporter/reader divergence Test-LwgFlag's own docstring
    # records bin\lwg-toggle.ps1 shipping.
    #
    # BOTH ARE FAIL, NOT WARN, AND THE POLARITY DIFFERS BETWEEN THEM. An ignored
    # switch value leaves a gate OFF while the file says on; an ignored `modules`
    # value leaves a module ON while the file says off. Neither is a caveat -
    # in both the operator's written choice is not in effect - so each row says
    # which way the module actually ended up rather than leaving it to be
    # inferred from the word "boolean".
    Invoke-Check -Id 'config-registry' -Body {
        $cfg = Get-LwgConfig
        if ($cfg._source -ne 'file') {
            Add-Row -Id 'config-registry' -Status 'FAIL' -Detail 'config.json unreadable or invalid - running on built-in defaults, so every operator ON/OFF choice is being ignored'
            return
        }
        $inConfig   = @($cfg.modules.PSObject.Properties.Name)
        # $script:LwgModules and $script:LwgSwitchModules are set by the
        # dot-source above, in this script's own scope - the same way
        # lib/session_start.ps1 reads them.
        $own        = @($script:LwgSwitchModules)
        $inRegistry = @($script:LwgModules | Where-Object { $own -notcontains $_ })
        $onlyConfig = @($inConfig   | Where-Object { $inRegistry -notcontains $_ })
        $onlyReg    = @($inRegistry | Where-Object { $inConfig   -notcontains $_ })

        $bits = @()

        # AN OVERRIDE THAT WAS READ AND THEN DISCARDED - #11. Since 3 September
        # 2026 the operator's ON/OFF choices are not in config.json at all: they
        # are in config.override.json under the state directory, and
        # Get-LwgConfig merges that over these defaults. It IGNORES one it
        # cannot read rather than throwing - the right polarity, because a
        # half-written settings file must not arm a gate and must not take the
        # plugin down either - and carries the reason out in _override_error.
        #
        # SO THIS ROW IS THE ONLY PLACE THAT CAN SAY IT HAPPENED. _source is
        # still 'file': config.json parsed perfectly. Every check below, every
        # count in the roster at the foot, and the SessionStart banner then
        # report the SHIPPED DEFAULTS while an operator's entire configuration
        # sits in a file nothing read - and the doctor called that machine
        # healthy. Both configuring commands already refuse to write in this
        # state and name the file; this is the reporting half of the same rule.
        #
        # FAIL, NOT WARN, for exactly the reason the two rules below it are:
        # what is written is not what is in effect. The polarity is safe - the
        # defaults stand, so every gate is OFF rather than silently ON - which
        # is why it is a row here and not a refusal anywhere.
        if ("$($cfg._override_error)" -ne '') {
            $ovp = ''
            try { $ovp = "$(Get-LwgConfigOverridePath)" } catch { $ovp = '' }
            if ([string]::IsNullOrWhiteSpace($ovp)) { $ovp = 'config.override.json under the state directory' }
            $bits += "the operator override $ovp exists but $($cfg._override_error), so it was DISCARDED - every ON/OFF choice recorded in it is being ignored and everything below reports the shipped defaults instead"
        }
        if ($onlyConfig.Count -gt 0) { $bits += "in config.json but not in the registry (a switch wired to nothing): $($onlyConfig -join ', ')" }
        if ($onlyReg.Count -gt 0)    { $bits += "in the registry but not in config.json (cannot be switched off): $($onlyReg -join ', ')" }

        # Every own-switch entry: the key it names must exist. Read out of the
        # decoded config by property lookup rather than by text search, so this
        # asks the same question the module itself asks at run time.
        foreach ($m in $own) {
            $sw = $script:LwgModuleRegistry[$m].switch
            $b  = [string]$sw.block
            $k  = [string]$sw.key
            if ([string]::IsNullOrWhiteSpace($b) -or [string]::IsNullOrWhiteSpace($k)) {
                $bits += "registry entry '$m' declares a switch with no block/key - nothing can turn it on or off"
                continue
            }
            if ($inConfig -contains $m) {
                # Both spellings present is worse than neither: two switches over
                # one module, and the `modules` one is the dead letter because
                # Test-LwgModule answers from the declared switch.
                $bits += "'$m' declares its switch as $b.$k AND has a modules.$m flag - the modules flag is read by nothing, so switching it does nothing"
            }
            $v = $null
            try { $v = $cfg.$b.$k } catch { }
            if ($null -eq $v) {
                $bits += "registry entry '$m' declares its switch as $b.$k, and config.json has no such key - the module falls back to its built-in default ($($sw.default)) and nothing in the file can change it"
            }
            elseif ($v -isnot [bool]) {
                # The key is there and holds something that is not a setting.
                # Test-LwgFlag skips the level rather than coercing, so the
                # written value is not a vote either way - it is not a value at
                # all, and the registry default stands.
                $bits += "registry entry '$m' declares its switch as $b.$k, and config.json holds a $($v.GetType().Name) there ('$v') rather than a boolean - Test-LwgFlag ignores anything that is not a real boolean, so the module is running on its built-in default ($($sw.default)) and the value written in the file is doing nothing"
            }
        }

        # The `modules` block, VALUES this time. The parity test above reads
        # .PSObject.Properties.Name, which is the right question for parity and
        # cannot see this: Test-LwgModule applies the same boolean-only rule to
        # this block, and an ignored value here leaves the module RUNNING. Its
        # docstring records that "modules": { "docs_coupling": "false" } ENABLED
        # docs_coupling, because [bool] on a non-empty string is $true in
        # PowerShell - so this is the same class as the switch above with the
        # polarity reversed, and the row says which one it is.
        #
        # Every property is read, including names the registry has never heard
        # of. Those already produce their own bit above; a filter here would
        # hide a second, different fault about the same key.
        foreach ($p in @($cfg.modules.PSObject.Properties)) {
            $mv = $p.Value
            if ($mv -isnot [bool]) {
                $tn = if ($null -eq $mv) { 'null' } else { $mv.GetType().Name }
                $bits += "config.json's modules.$($p.Name) holds a $tn ('$mv') rather than a boolean - Test-LwgModule ignores anything that is not a real boolean and an unreadable modules flag defaults on, so that module STAYS ON whatever this line says"
            }
        }

        if ($bits.Count -gt 0) {
            Add-Row -Id 'config-registry' -Status 'FAIL' -Detail ($bits -join '; ')
            return
        }
        # "each on a key that exists" was the whole claim until the value test
        # above landed, and it was true and was not the question. The wording
        # now states what was actually checked.
        $extra = if ($own.Count -gt 0) {
            "; $($own.Count) module(s) switched from outside that block, each on a key that exists and holds a real boolean: " +
            (($own | ForEach-Object {
                $s = $script:LwgModuleRegistry[$_].switch
                "$_ -> $($s.block).$($s.key)" }) -join ', ')
        } else { '' }
        Add-Row -Id 'config-registry' -Status 'PASS' -Detail "parses; all $($inConfig.Count) module flags match the registry exactly and every one holds a real boolean$extra"
    }

    # ---------------------------------------------------------------------
    # 5. the state dir resolves to the LIVE directory, and is writable
    # ---------------------------------------------------------------------
    # This is the check that exists because the plugin already shipped the bug.
    # 'bare' and 'unresolved' both mean the path is a GUESS - a directory the
    # live plugin never touches - and everything written there is lost while
    # every writer reports success.
    Invoke-Check -Id 'state-dir' -Body {
        $info = Get-LwgStateDirInfo
        if ([string]::IsNullOrWhiteSpace([string]$info.path)) {
            Add-Row -Id 'state-dir' -Status 'FAIL' -Detail 'no state dir path could be worked out at all'
            return
        }
        if (-not $info.resolved) {
            $why = switch ($info.source) {
                'bare'  { "only the unsuffixed fallback name exists. Claude Code always names a plugin's data dir <name>-<source-id>, so this directory can only have been created by this plugin's own fallback - the live plugin writes somewhere else" }
                default { "nothing under ~\.claude\plugins\data matched '$(Get-LwgPluginName)*' ($($info.candidates) candidate(s) seen)" }
            }
            Add-Row -Id 'state-dir' -Status 'FAIL' -Detail "UNRESOLVED (source '$($info.source)'): $($info.path) - $why"
            return
        }
        $probe = Add-LwgLine -FileName 'doctor.probe' -Line ((Get-Date).ToUniversalTime().ToString('o'))
        if (-not $probe) {
            Add-Row -Id 'state-dir' -Status 'FAIL' -Detail "resolved to $($info.path) (source '$($info.source)') but is NOT writable - nothing can be logged"
            return
        }
        # AMBIGUOUS IS NOT PASS (#270). The write probe succeeded, so this
        # directory works - but "it works" is not the question when two of them
        # are on disk and a hook is reading the other one. A caveat rather than
        # a failure: nothing here is broken, and the operator is the only one
        # who can say which directory is the live one.
        $split = Get-DoctorStateSplit -Info $info
        if ($split.ambiguous) {
            Add-Row -Id 'state-dir' -Status 'WARN' -Detail (
                "$($info.path) (source '$($info.source)', $($info.candidates) candidate(s)); write probe succeeded - " +
                "but $($split.ranked.Count) state directories exist and THIS RUN CHOSE ONE OF THEM by which was written last. " +
                "A HOOK is handed CLAUDE_PLUGIN_DATA and may be reading a different one, so every module flag, gate state " +
                "and override reported below describes only the directory named here:`n" +
                (($split.lines) -join "`n") + "`n" +
                "      Set CLAUDE_PLUGIN_DATA to the one you mean and re-run: that puts this command on the same branch every " +
                "hook takes, and the two then agree by construction. Deleting the directory you do not want also settles it.")
            return
        }
        Add-Row -Id 'state-dir' -Status 'PASS' -Detail "$($info.path) (source '$($info.source)', $($info.candidates) candidate(s)); write probe succeeded"
    }

    # ---------------------------------------------------------------------
    # 6. the SessionStart hook has actually fired, and its self-check passed
    # ---------------------------------------------------------------------
    # The only evidence available out-of-session that a hook is REGISTERED, as
    # opposed to merely declared, is that it has left a record. Declaring a hook
    # in hooks.json and having Claude Code invoke it are different facts, and
    # this is the one that matters.
    Invoke-Check -Id 'sessionstart' -Body {
        $info = Get-LwgStateDirInfo
        $log  = Join-Path $info.path 'lw-watchtower.jsonl'
        $caveat = if ($info.resolved) { '' } else { " (and the state dir is unresolved, so this may be the wrong directory entirely)" }

        if (-not (Test-Path -LiteralPath $log)) {
            Add-Row -Id 'sessionstart' -Status 'FAIL' -Detail "no event log at $log - the SessionStart hook has never recorded a run, so it is declared but not firing$caveat"
            return
        }
        # A WINDOW IS A BOUND ON THE READ AND NEVER EVIDENCE OF ABSENCE.
        #
        # This check used to read the last 256 KB and, finding no SessionStart
        # in it, report "the hook is not firing" and fail the run. The whole of
        # the reasoning was a comment saying 256 KB is many hundreds of records.
        # Many hundreds of records is not "far enough back to reach a session
        # start": nothing bounds how many other records a busy session writes
        # between two of them, so one long session, or one regression run that
        # appends in bulk, is enough to push a perfectly good SessionStart out
        # of the window - and the operator is then told to reinstall a plugin
        # whose hook fired correctly. That is the collapse this file's own
        # header refuses at the top: "I found a fault" and "I could not look"
        # are different statements, and Get-LwgTailLines returns no signal that
        # tells them apart, so this check works the difference out itself.
        #
        # THREE ANSWERS, NOT TWO, and which one is given turns on how much of
        # the file was actually read:
        #
        #   found                     report on the record, as before.
        #   missing, whole file read  FAIL. Absence was established, so the
        #                             fault claim is earned and its wording is
        #                             unchanged.
        #   missing, read stopped short
        #                             WARN that says so. Nothing here
        #                             establishes anything about the hook.
        #
        # THE FAST PATH IS KEPT AND THE WIDE READ IS ONLY THE FALLBACK. 256 KB
        # costs one seek and answers on any log whose session start is anywhere
        # near the end, which is the ordinary case. Only a miss pays for the
        # second read, and only on a log big enough to have truncated the first.
        #
        # THE CEILING IS 8 MB BECAUSE Invoke-LwgLogRotate CAPS THE LIVE LOG AT
        # 5 MB. A file past this ceiling means rotation is not running either -
        # worth knowing, and still not a statement about the SessionStart hook.
        # It is a ceiling rather than "read the whole thing" because this runs
        # on an operator's machine against a file whose size nothing here
        # controls.
        $window = 262144
        $widest = 8388608

        # -1 means the length could not be read at all, which is neither a fault
        # nor a complete read and must not be rounded to either.
        $len = -1
        try { $len = [long](Get-Item -LiteralPath $log -ErrorAction Stop).Length } catch { }
        if ($len -lt 0) {
            Add-Row -Id 'sessionstart' -Status 'WARN' -Detail "event log $log exists but its length could not be read, so this check could not establish how much of it it was looking at - nothing here says the hook is or is not firing$caveat"
            return
        }

        $scanned = [long][Math]::Min([long]$window, $len)
        $rec = $null
        foreach ($line in @(Get-LwgTailLines -Path $log -Bytes $window)) {
            try { $r = $line | ConvertFrom-Json } catch { continue }
            if ($r.event -eq 'SessionStart') { $rec = $r }
        }
        if ($null -eq $rec -and $len -gt $scanned) {
            $scanned = [long][Math]::Min([long]$widest, $len)
            foreach ($line in @(Get-LwgTailLines -Path $log -Bytes ([int]$scanned))) {
                try { $r = $line | ConvertFrom-Json } catch { continue }
                if ($r.event -eq 'SessionStart') { $rec = $r }
            }
        }
        if ($null -eq $rec) {
            if ($scanned -lt $len) {
                # $caveat is APPENDED rather than interpolated into the format
                # string: a brace in it would be read as a placeholder by -f.
                $msg = "no SessionStart record in the last {0:N0} KB of a {1:N0} KB event log - this check could not look far enough back, which is NOT the same as the hook not firing. Nothing here is a finding about the hook; a log this size also means rotation is not keeping up with it" -f ($scanned / 1KB), ($len / 1KB)
                Add-Row -Id 'sessionstart' -Status 'WARN' -Detail ($msg + $caveat)
                return
            }
            Add-Row -Id 'sessionstart' -Status 'FAIL' -Detail "event log exists but holds no SessionStart record - the hook is not firing$caveat"
            return
        }

        $age = $null
        try { $age = ((Get-Date).ToUniversalTime() - ([datetime]$rec.ts).ToUniversalTime()) } catch { }
        $when = if ($null -ne $age) { "{0:N1} h ago" -f $age.TotalHours } else { "at $($rec.ts)" }

        # Three states, not two. A check that never ran is not a check that
        # passed, and must not be reported as one.
        if ($rec.selfcheck.ran -ne $true) {
            Add-Row -Id 'sessionstart' -Status 'WARN' -Detail "last fired $when (mode '$($rec.mode)') but the self-check did NOT run - self_health is off, so nothing about that session was verified"
            return
        }
        if ($rec.selfcheck.ok -ne $true) {
            $f = @($rec.failures)
            Add-Row -Id 'sessionstart' -Status 'FAIL' -Detail "last fired $when and the self-check FAILED (mode '$($rec.mode)'): $($f -join '; ')"
            return
        }
        if ($null -ne $age -and $age.TotalDays -gt 30) {
            Add-Row -Id 'sessionstart' -Status 'WARN' -Detail "self-check passed, but the last run was $('{0:N0}' -f $age.TotalDays) days ago - this is stale evidence about a plugin that may have changed since"
            return
        }
        Add-Row -Id 'sessionstart' -Status 'PASS' -Detail "last fired $when, mode '$($rec.mode)', self-check passed"
    }

    # ---------------------------------------------------------------------
    # 7. the status line is wired up in settings.json and points at a real file
    # ---------------------------------------------------------------------
    # statusLine is a settings.json key, NOT a plugin capability, so the plugin
    # cannot install it and cannot assume it. It is checked here because HH
    # is this plugin's only live indicator surface: with it unwired the plugin
    # runs and shows the operator nothing.
    #
    # HH ALONE, AND NOT THE OLD PAIR. A second segment, GM, rendered this plugin's
    # governance state until 30 July 2026, when it was deleted along with the
    # trip ledger that was its only input; statusline/statusline.ps1 carries the
    # tombstone. Four strings under bin/ went on naming it afterwards - this
    # one, the installer's section blurb, the uninstaller's footprint row and
    # the updater's INFO row - so an operator was told on a first install, on a
    # first fault and on a first update that a segment they can never see is
    # supposed to be there. MOST of the docs were swept on the day - seven pages
    # record the removal correctly - but not all: docs/install.md and
    # docs/troubleshooting.md still promised it on 3 August 2026, and
    # docs/faq.md inverts it, telling a reader that seeing GM is the sign of a
    # stale copy. See docs/gates-removed.md.
    #
    # THE CONFIGURATION DIRECTORY IS RESOLVED, NEVER COMPOSED (#146). This line
    # read `Join-Path $env:USERPROFILE '.claude\settings.json'` until 3 September
    # 2026, and it was the LAST live composition of that shape in the tree -
    # every other caller moved onto lib\common.ps1's Get-LwgClaudeHomeInfo when
    # that function landed. On a machine that sets CLAUDE_CONFIG_DIR the doctor
    # was therefore health-checking a settings.json the CLI does not read: a
    # green statusline row about a file nothing loads, which is worse than no
    # row at all because it converts a broken install into an attested one. The
    # resolver's own header names this command as one of the two callers that
    # must report WHICH root it resolved and why, so the path-bearing failures
    # below say which of CLAUDE_CONFIG_DIR and USERPROFILE answered.
    #
    # A MACHINE WITH NEITHER IS A FAIL THAT SAYS SO. $null comes back when
    # neither variable holds anything; it is carried as $null and reported,
    # rather than composed onto to produce a path this check invented and then
    # diagnosed.
    Invoke-Check -Id 'statusline' -Body {
        $homeInfo = $null
        try { $homeInfo = Get-LwgClaudeHomeInfo } catch { }
        if ($null -eq $homeInfo) { $homeInfo = @{ path = $null; source = 'unresolved'; exists = $false; raw = $null } }
        $cfgHome = [string]$homeInfo.path
        $via = switch ([string]$homeInfo.source) {
            'env'     { ' (resolved from CLAUDE_CONFIG_DIR)' }
            'profile' { ' (resolved from USERPROFILE\.claude - CLAUDE_CONFIG_DIR is not set)' }
            default   { '' }
        }

        if ([string]::IsNullOrWhiteSpace($cfgHome)) {
            Add-Row -Id 'statusline' -Status 'FAIL' -Detail 'no Claude Code configuration directory could be resolved: neither CLAUDE_CONFIG_DIR nor USERPROFILE holds a value. There is no settings.json to read, so nothing here says the status line is configured and nothing here says it is not'
            return
        }

        $sp = Join-Path $cfgHome 'settings.json'
        if (-not (Test-Path -LiteralPath $sp)) {
            Add-Row -Id 'statusline' -Status 'FAIL' -Detail "no settings file at $sp$via - the status line cannot be configured"
            return
        }
        # PS 5.1's Get-Content -Raw keeps a UTF-8 BOM, which ConvertFrom-Json
        # rejects. Settings files written by other tools do carry one.
        $raw = (Get-Content -LiteralPath $sp -Raw).TrimStart([char]0xFEFF)
        $st  = ($raw | ConvertFrom-Json).statusLine
        if ($null -eq $st -or [string]::IsNullOrWhiteSpace([string]$st.command)) {
            Add-Row -Id 'statusline' -Status 'FAIL' -Detail "$sp$via has no statusLine.command - the HH segment is not rendered, so this plugin has no visible indicator"
            return
        }
        # Pull the script path back out of the command line: the first token
        # that names a file which exists. Quoted or bare, forward or back slash.
        $target = $null
        foreach ($tok in ([regex]::Matches([string]$st.command, '"([^"]+)"|(\S+)'))) {
            $t = if ($tok.Groups[1].Success) { $tok.Groups[1].Value } else { $tok.Groups[2].Value }
            if ($t -match '\.ps1$') { $target = $t; break }
        }
        if ($null -eq $target) {
            Add-Row -Id 'statusline' -Status 'WARN' -Detail "statusLine.command is set but names no .ps1 this check could identify, so its target was not verified: $($st.command)"
            return
        }
        if (-not (Test-Path -LiteralPath $target)) {
            Add-Row -Id 'statusline' -Status 'FAIL' -Detail "statusLine.command points at $target which does not exist - the status line is configured and broken, which renders as no segments at all"
            return
        }

        # PROVENANCE FIRST, THEN DRIFT, AND THE ORDER IS THE FIX.
        #
        # The token scan above takes the first token ending in .ps1 with no path
        # and no name constraint, which is correct - the operator may have
        # installed this plugin's status line anywhere. What was NOT correct was
        # what came next: until 3 August 2026 the target was hash-compared
        # against this repo's copy unconditionally, and a mismatch printed
        # "stale or locally modified; re-copy it". Two hashes differing is
        # consistent with three things - our file out of date, our file locally
        # modified, or NOT OUR FILE - and the row asserted the first two by name
        # while the remedy destroyed the third. A status line belonging to
        # somebody else is the normal state of any machine where this plugin's
        # was never installed, which the preamble above already says the plugin
        # cannot assume.
        #
        # THE IDENTITY TEST is the token LWG-STATUSLINE-IDENTITY on a comment
        # line inside the first 4096 bytes of the target. statusline\statusline.ps1
        # carries it and states the format there; this is the only reader.
        # Content, not path: ~\.claude is not evidence of ownership either, and
        # issue #17 records bin\lwg-uninstall.ps1 being too loose for exactly
        # that reason.
        #
        # IT IS FORGEABLE AND THAT IS STATED RATHER THAN LEFT TO BE FOUND. A
        # file that merely CONTAINS the token is claimed here as ours and would
        # then be told it has drifted and to re-copy over itself - the same harm
        # this branch exists to prevent, reachable by a file that copied one
        # comment line. No content marker can be made unforgeable. What this
        # test buys is the case an operator actually hits: an UNRELATED status
        # line, never derived from ours and with no reason to carry the token,
        # is no longer diagnosed as a stale copy of a file it has never seen.
        # It buys nothing against a file that quotes the marker, and it is not
        # offered as if it did.
        #
        # THREE ANSWERS, NOT TWO, and the third is the doctor's own distinction
        # at the top of this file: "I found a fault" and "I could not look" are
        # different statements. A target that cannot be read is neither ours nor
        # somebody else's - it is unestablished - and it gets a WARN that says so
        # and no remedy at all. Absence of the marker is NOT that case: it is a
        # readable file that is not this plugin's, which is a legitimate
        # configuration and a PASS.
        #
        # PASS RATHER THAN WARN FOR THE MARKER-ABSENT CASE IS A JUDGEMENT AND IS
        # ARGUABLE. The operator has no HH segment either way, which is what the
        # FAIL two branches up is about. It is a PASS because the row above it
        # already reports the wiring, because nothing here is broken, and because
        # the alternative makes every machine with its own status line report a
        # caveat forever. The detail states the consequence so the reader can
        # disagree with the status and still have the fact.
        $repoCopy = Join-Path $pluginRoot 'statusline\statusline.ps1'
        $marker   = 'LWG-STATUSLINE-IDENTITY'

        # $null means "could not look". Bounded to the head of the file: the
        # marker is required to be there, and a status line is not a file this
        # should read in full on a health check.
        $isOurs = $null
        $why    = ''
        try {
            $fs = [IO.File]::Open($target, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            try {
                $buf  = New-Object byte[] 4096
                $n    = $fs.Read($buf, 0, $buf.Length)
                # A target that is not UTF-8 decodes to something the token
                # cannot appear in, which yields "not ours". That is the safe
                # direction: it declines to claim the file rather than claiming
                # it and printing an overwrite.
                $head = [Text.Encoding]::UTF8.GetString($buf, 0, $n)
            } finally { $fs.Dispose() }
            $isOurs = $head.Contains($marker)
        } catch {
            $why = $_.Exception.Message
        }

        if ($null -eq $isOurs) {
            Add-Row -Id 'statusline' -Status 'WARN' -Detail "wired to $target, which exists but could NOT be read ($why) - so whether it is this plugin's status line was not established. Nothing here says it has drifted and nothing here says to replace it"
            return
        }
        if (-not $isOurs) {
            Add-Row -Id 'statusline' -Status 'PASS' -Detail "wired to $target, which carries no $marker marker in its first 4096 bytes - it is not this plugin's status line, which is a legitimate configuration. The HH segment will not be rendered, and this file is NOT a stale copy of statusline/statusline.ps1: do not overwrite it"
            return
        }

        # Marker present. NOW the installed copy is a COPY of this repo's file,
        # docs/install.md is explicit that the two can drift and that nothing
        # else detects it, and a hash mismatch means what this row has always
        # said it means. The text and the remedy are unchanged.
        $drift = "; carries the $marker marker"
        if (Test-Path -LiteralPath $repoCopy) {
            $a = Get-LwgFileSha256 -Path $target
            $b = Get-LwgFileSha256 -Path $repoCopy
            if ($a -ne $b) {
                Add-Row -Id 'statusline' -Status 'WARN' -Detail "wired to $target, but it DIFFERS from statusline/statusline.ps1 in this repo - the installed copy is stale or locally modified; re-copy it to make the repo's version live"
                return
            }
            $drift = "; carries the $marker marker and matches the repo copy"
        }
        Add-Row -Id 'statusline' -Status 'PASS' -Detail "wired to $target$drift"
    }

    # ---------------------------------------------------------------------
    # 8. the command surface this doctor is part of
    # ---------------------------------------------------------------------
    # Two questions, and the second one is the one that was missing. The old
    # check walked a hardcoded list of three names and asked whether each was
    # present - so it could only ever find a command someone had DELETED, and it
    # reported 3/3 while the "tripped" command was referenced five times across
    # the status line, the Stop advisories and the README and existed nowhere.
    # (That name is deliberately not written with its leading slash here: check
    # (b) below scans this file too, and a live-looking reference in a comment
    # would fail the check on its own explanation. The command was later built,
    # and then removed with the trip ledger on 30 July 2026.)
    #
    # A command surface has two ways to be broken and they are not the same:
    #
    #   declared but not backed  commands\x.md with no bin\lwg-x.ps1 - a slash
    #                            command that runs nothing
    #   referenced but not declared  something tells the operator to run
    #                            /<plugin>:x and there is no commands\x.md - a
    #                            signpost to a command that does not exist
    #
    # The second is worse, because the reference is usually printed at exactly
    # the moment the operator needs the command. Both are enumerated from what
    # is actually on disk and in the files, never from a list in this script -
    # a hardcoded list cannot notice a name nobody thought to add to it, which
    # is precisely how the gap above survived.
    Invoke-Check -Id 'commands' -Body {
        $p      = Get-LwgPluginName
        $cmdDir = Join-Path $pluginRoot 'commands'
        if (-not (Test-Path -LiteralPath $cmdDir)) {
            Add-Row -Id 'commands' -Status 'FAIL' -Detail "no commands\ directory - no /${p}:* command can exist"
            return
        }
        $cmds  = @(Get-ChildItem -LiteralPath $cmdDir -Filter '*.md' -File)
        $names = @($cmds.BaseName)
        $problems = @()

        # a. declared, and backed by a real script.
        #
        # Read the script out of the command body rather than assuming
        # bin\lwg-<name>.ps1. The naming convention is not the contract and is
        # not even true: delegate invokes bin\lwg-toggle.ps1 with a -Flag, and
        # it is the survivor of three commands that shared that one script -
        # verbosity and plain were deleted with the output styles they switched
        # - because a copy of the read/validate/write/report path per command
        # would be one more thing to keep correct. Asserting the convention
        # would fail delegate for being written properly, while still missing a
        # command that names a script it does not have. What matters is that the
        # file it actually invokes is on disk, which is the same
        # ${CLAUDE_PLUGIN_ROOT} test the hooks-declared check applies to hook
        # scripts.
        $scriptRe = [regex]'\$\{CLAUDE_PLUGIN_ROOT\}[\\/]+([A-Za-z0-9_./\\-]+\.ps1)'
        foreach ($c in $cmds) {
            $n    = $c.BaseName
            $body = ''
            try { $body = Get-Content -LiteralPath $c.FullName -Raw -ErrorAction Stop } catch { }
            $hits = @($scriptRe.Matches($body) | ForEach-Object { $_.Groups[1].Value })
            if ($hits.Count -eq 0) {
                $problems += "commands\$n.md invokes no `${CLAUDE_PLUGIN_ROOT} script - /${p}:$n would run nothing"
                continue
            }
            foreach ($rel in ($hits | Select-Object -Unique)) {
                $abs = Join-Path $pluginRoot ($rel -replace '/', '\')
                if (-not (Test-Path -LiteralPath $abs)) {
                    $problems += "commands\$n.md invokes $rel which does not exist - /${p}:$n would run nothing"
                }
            }
        }

        # b. referenced anywhere in this repo, and declared.
        #
        # WHICH TREE IS ENUMERATED, AND WHY IT IS THE TRACKED ONE FIRST (#204).
        # This walked the FILESYSTEM under $pluginRoot with two name filters,
        # '.git\' and '.claude\', and scanned everything else - tracked or not.
        # A check whose verdict moves with whatever is lying around is not
        # measuring the plugin, which is the same argument the paragraph below
        # already makes about where the plugin is installed, on a different
        # axis. It was not theoretical: an untracked scratch directory of
        # generated output in a checkout whose TRACKED tree was clean carried
        # references to six commands deleted on 2 September 2026, and this check
        # reported the plugin NOT healthy over a directory that is no part of
        # it. `git add -A` in such a checkout then makes those references
        # tracked and the false FAIL becomes a real one nobody wrote on purpose.
        #
        # So: the TRACKED tree when git can answer for this directory, the
        # filesystem walk when it cannot. Every other enumeration in this
        # repository derives from `git ls-files` for the reason .github/
        # workflows/ci.yml states - it cannot drift from the repo, and `.git` is
        # excluded by construction rather than by a filter someone has to
        # remember to maintain - and this check was the outlier.
        #
        # THE FALLBACK IS NOT OPTIONAL AND IS NOT A SILENT ONE. On a marketplace
        # install the plugin directory has no `.git` at all: `git ls-files`
        # exits 128 there and enumerates nothing, and "scanned 0 files" must
        # never become a pass - that is the defect this file exists to catch,
        # and the $refs.Count guard below is the same rule. A plugin unpacked
        # inside some OTHER repository is the second shape: git answers, exit 0,
        # and lists nothing here because none of these files is tracked THERE.
        # Both fall back to the walk, and $enum says which path was taken and
        # why, so a reader never has to guess which tree was measured.
        #
        # stderr is sent to nul and never merged. In Windows PowerShell 5.1 a
        # native command's stderr comes back as NativeCommandError records under
        # ErrorActionPreference 'Stop', so `fatal: not a git repository` - the
        # ordinary marketplace case - would THROW and Invoke-Check would report
        # the check as failed rather than falling back.
        $exts = @('.md', '.ps1', '.json', '.yml', '.yaml', '.txt')
        $tracked = $null
        $gitWhy  = ''
        try {
            $eap = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                # Reset FIRST. $LASTEXITCODE is whatever the last native command
                # in this process left behind, and if `git` cannot be found at
                # all the call sets no new value - so reading a stale 0 would
                # take the tracked path on a machine that has no git.
                $global:LASTEXITCODE = -1
                # core.quotePath=false: git otherwise C-quotes any path with a
                # non-ASCII byte in it, and a quoted name is not a path.
                $raw     = & git -C $pluginRoot -c core.quotePath=false ls-files 2>$null
                $gitCode = if ($null -eq $LASTEXITCODE) { -1 } else { $LASTEXITCODE }
                if ($gitCode -eq 0) {
                    # Filtered BEFORE it is counted: @($null).Count is 1 in
                    # PowerShell, so an empty listing would otherwise read as
                    # one tracked file and take the tracked path with nothing
                    # in it.
                    $tracked = @($raw | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
                    if ($tracked.Count -eq 0) {
                        $tracked = $null
                        $gitWhy  = 'git answered but listed no tracked file under the plugin root'
                    }
                } else {
                    $gitWhy = "git ls-files exited $gitCode here, so there is no tracked tree to read"
                }
            } finally { $ErrorActionPreference = $eap }
        } catch {
            $tracked = $null
            $gitWhy  = "git could not be run ($($_.Exception.Message))"
        }

        # .claude is local harness state - settings.local.json and agent
        # worktrees, which are whole second copies of this tree - and is not part
        # of the plugin, so it is excluded on BOTH paths. .git needs no exclusion
        # on the tracked path because git never lists it.
        #
        # BOTH exclusions are matched against the path RELATIVE TO $pluginRoot,
        # never against the absolute path. This plugin is normally reached
        # through a junction under ~\.claude\skills\, so EVERY absolute path in
        # the tree contains '\.claude\', and an absolute-path exclusion swallowed
        # the ENTIRE plugin: 0 files scanned, 12 command files checked by
        # nothing. A check whose result depends on where the thing is installed
        # is not a check. Relative matching also keeps '.claude-plugin\' in
        # scope, which is a real part of the plugin and must stay scanned.
        $enum  = ''
        $files = @()
        if ($null -ne $tracked) {
            $enum = 'the tracked tree (git ls-files)'
            foreach ($t in $tracked) {
                # git reports '/' separators; every path this check prints and
                # every -like below is written in the Windows shape.
                $rel = ([string]$t) -replace '/', '\'
                if ($rel -like '.claude\*') { continue }
                if ([IO.Path]::GetExtension($rel).ToLowerInvariant() -notin $exts) { continue }
                # Tracked in the index but deleted from the working tree. It is
                # not on disk to read, and a missing file is not a reference.
                $abs = Join-Path $pluginRoot $rel
                if (-not (Test-Path -LiteralPath $abs -PathType Leaf)) { continue }
                $files += [pscustomobject]@{ rel = $rel; full = $abs }
            }
        } else {
            $enum = "the filesystem - $gitWhy"
            foreach ($f in @(Get-ChildItem -LiteralPath $pluginRoot -Recurse -File -ErrorAction SilentlyContinue |
                             Where-Object { $_.Extension -in $exts })) {
                $rel = $f.FullName.Substring($pluginRoot.Length).TrimStart('\', '/')
                if ($rel -like '.git\*' -or $rel -like '.claude\*') { continue }
                $files += [pscustomobject]@{ rel = $rel; full = $f.FullName }
            }
        }

        $re   = [regex]('(?<![A-Za-z0-9_-])/' + [regex]::Escape($p) + ':([A-Za-z0-9][A-Za-z0-9_-]*)')
        $refs = @{}
        $scanned = 0
        foreach ($f in $files) {
            $text = ''
            try { $text = Get-Content -LiteralPath $f.full -Raw -ErrorAction Stop } catch { continue }
            $scanned++
            if ([string]::IsNullOrEmpty($text)) { continue }
            foreach ($m in $re.Matches($text)) {
                $n = $m.Groups[1].Value.ToLowerInvariant()
                if (-not $refs.ContainsKey($n)) { $refs[$n] = @() }
                if ($refs[$n] -notcontains $f.rel) { $refs[$n] += $f.rel }
            }
        }

        # An enumeration that found nothing has checked nothing, and a check that
        # cannot fail is the defect this file exists to catch. The same rule the
        # CI JSON step was given in d1ff015, and the reason the tracked path
        # above falls back rather than reporting a clean sweep of zero files.
        if ($refs.Count -eq 0) {
            Add-Row -Id 'commands' -Status 'FAIL' -Detail "scanned $scanned file(s) from $enum and found NO /${p}:* reference at all - the reference scan is broken, so this check proved nothing about the command surface"
            return
        }

        foreach ($n in @($refs.Keys | Sort-Object)) {
            if ($names -contains $n) { continue }
            $problems += "/${p}:$n is referenced in $($refs[$n] -join ', ') but commands\$n.md does not exist"
        }

        if ($problems.Count -gt 0) {
            Add-Row -Id 'commands' -Status 'FAIL' -Detail (($problems -join '; ') + " [enumerated $enum, $scanned file(s) scanned]")
            return
        }
        Add-Row -Id 'commands' -Status 'PASS' -Detail "$($cmds.Count) command(s), each with its backing script: $(($names | ForEach-Object { "/${p}:$_" }) -join ', '); $($refs.Count) distinct command(s) referenced across $scanned file(s) scanned from $enum, all declared"
    }

    # ---------------------------------------------------------------------
    # 9. the machine this is installed on
    # ---------------------------------------------------------------------
    # NOTHING IN THIS PLUGIN CHECKED THE OPERATING SYSTEM until this row (#132).
    # .claude-plugin\plugin.json opens with "WINDOWS ONLY", hooks\hooks.json
    # invokes `powershell` by that name in every registration, and every path
    # composed anywhere here is NTFS-shaped - so a non-Windows machine is a
    # SILENT non-install, not a degraded one. A repository-wide search for
    # IsWindows, OSVersion.Platform, `claude --version` and CLAUDE_CODE_VERSION
    # returned nothing at all before lib\common.ps1 grew Get-LwgPlatformInfo.
    #
    # FAIL and not WARN. Every hook registration is inert on such a machine and
    # nothing this plugin ships can run; that is a fault, and the row's job is
    # to convert a silent non-install into a named one.
    #
    # THE INTERPRETER IS REPORTED ON THE PASS TOO, because it is the other half
    # of the answer: hooks.json invokes `powershell`, which is Windows
    # PowerShell 5.1, and knowing which interpreter answered is what makes a
    # later "it works in pwsh" report readable.
    Invoke-Check -Id 'platform' -Body {
        $pi   = Get-LwgPlatformInfo
        $seen = "os '$($pi.os)', PowerShell $($pi.ps_version) $($pi.ps_edition)"
        if (-not $pi.supported) {
            Add-Row -Id 'platform' -Status 'FAIL' -Detail "$seen - this plugin is WINDOWS ONLY: hooks\hooks.json invokes 'powershell' by that name in every registration and every path it composes is NTFS-shaped, so nothing it ships can fire here. Nothing is degraded; nothing is installed"
            return
        }
        Add-Row -Id 'platform' -Status 'PASS' -Detail $seen
    }

    # ---------------------------------------------------------------------
    # 10. the Claude Code build the hook events were read out of
    # ---------------------------------------------------------------------
    # THE FAILURE MODE OF AN INERT HOOK IS SILENCE (#132). Three of the events
    # hooks\hooks.json registers on were read out of one specific binary, and on
    # a build that does not carry them those registrations simply never fire -
    # while the banner goes on counting the modules that depend on them among
    # the active ones, because it counts the REGISTRY and not observed
    # behaviour. There is no symptom: a module that records nothing looks
    # exactly like a session in which nothing went wrong.
    #
    # THE THREE NAMES ARE TRANSCRIBED HERE AND THE MODULES ARE NOT. Which events
    # are at risk is a fact about a binary read on one day - it is in
    # docs\install.md and in lib\common.ps1's registry header, and no check can
    # derive it. WHICH MODULES GO INERT WITH THEM is derivable, from the
    # registry's own `events` field, so it is derived: add a module that depends
    # on one of these and it appears in this row with no edit here.
    #
    # WARN, NEVER FAIL, ON AN OLD BUILD. An older Claude Code is a real finding
    # about the machine, not a broken install, and the exit ladder at the top of
    # this file already separates the two.
    #
    # AN UNREAD BUILD IS A PASS WHOSE DETAIL SAYS IT WAS NOT READ (#218), AND
    # THE THREE STATES ARE STILL THREE. lib\common.ps1's contract for
    # build_known - "an unread version must not render as 'read, and it
    # matched'" - is obeyed here in the DETAIL and not in the status: the row
    # below says, in words, that the build was never read and that nothing was
    # established by it. What it does not do is contribute a warning.
    #
    #   read, and at or above the verified build  ->  PASS
    #   read, and disagrees with it               ->  WARN, exit 2
    #   not readable at all                       ->  PASS, detail says so
    #
    # WHY THE THIRD ROW MOVED. This check first shipped (#132, PR #217) with the
    # unread state as a WARN, on the reasoning that a green verdict must not
    # rest on a fact nobody read. The reasoning was right and the state was
    # wrong, because $env:CLAUDE_CODE_VERSION IS NEVER EXPORTED: measured in a
    # live Claude Code session, eleven CLAUDE* variables are set and the version
    # is not one of them, on the hook path or the slash-command path. So the
    # WARN was not an edge case - it was every machine, every run, permanently,
    # and /doctor could not return 0 on a healthy install.
    #
    # A CAVEAT THAT FIRES ON EVERY RUN IS A CAVEAT AN OPERATOR LEARNS TO SKIP,
    # and the next one - the real one - is skipped with it. This repository
    # already has that written down about false FAILs and it applies here
    # unchanged. The distinction being kept is the one the `commands` check
    # makes: that check FAILs on "scanned zero files" because a broken
    # enumeration proves nothing, which is a different claim from "the input is
    # absent". An absent CLAUDE_CODE_VERSION is the second of those - a limit on
    # what can be observed from here, not a fault in this tree.
    #
    # CAN THE VERSION BE DERIVED FROM CLAUDE_CODE_EXECPATH INSTEAD? MEASURED,
    # AND THE ANSWER IS NO - recorded here so the next reader does not re-open
    # it. (a) There is no manifest beside the binary: the native install is a
    # single ~210 MB claude.exe under %USERPROFILE%\.local\bin with no sibling
    # metadata of any kind. The one version record on disk is
    # %USERPROFILE%\.local\share\claude\versions\, which is not beside the
    # binary and which held THREE directories on the machine this was measured
    # on - so reading it names three answers, and a guess between three is not a
    # read. The FREE reading, open a file and get a version, does not exist.
    #
    # (b) `& $env:CLAUDE_CODE_EXECPATH --version` DOES answer - 91/52/52 ms over
    # three runs, locally, with no network call - and it is still not done here,
    # for a reason that is about where the answer would live rather than about
    # what it costs. Every other consumer of the CLI build reads it from
    # Get-LwgPlatformInfo, whose header in lib\common.ps1 refuses the subprocess
    # BY NAME because that function is also called from a SessionStart hook. A
    # spawn in this row alone would make the doctor's build authoritative and
    # every other reader's stale, which is a second source of truth for a value
    # this repository deliberately keeps in one place.
    #
    # (c) AND THE CASE PINNING IT WOULD BE VACUOUS WHERE IT MATTERS. CI has no
    # Claude Code binary, so a case for "EXECPATH was set and the version was
    # derived" would either be skipped on the runner or need a stub executable
    # planted to impersonate one. A guard proved only where it cannot fire is
    # proved against nothing, and that rule is not suspended for convenience.
    #
    # IF IT IS WANTED LATER IT BELONGS IN Get-LwgPlatformInfo, behind an
    # explicit on-demand switch so the hook path keeps its current cost and only
    # a caller that asks pays for the spawn. That would move this third state
    # from universal to rare; it would not change what any of the three states
    # render as, which is why it is not a prerequisite for the ruling above.
    Invoke-Check -Id 'claude-version' -Body {
        $pi     = Get-LwgPlatformInfo
        $atRisk = @('SubagentStart', 'PostToolUseFailure', 'StopFailure')

        # Which shipped modules stop working if those events are absent, read
        # out of the registry rather than listed here.
        $hit = @()
        foreach ($m in @($script:LwgModules)) {
            $ev = @($script:LwgModuleRegistry[$m].events)
            $on = @($ev | Where-Object { $atRisk -contains $_ })
            if ($on.Count -gt 0) { $hit += "$m (needs $($on -join ', '))" }
        }
        $depends = if ($hit.Count -gt 0) { "; the module(s) that would go inert are $($hit -join ', ') - and the banner would still count them active, because it counts the registry and not observed firing" } else { '' }

        if (-not $pi.build_known) {
            Add-Row -Id 'claude-version' -Status 'PASS' -Detail "The Claude Code build was NOT read: CLAUDE_CODE_VERSION is not set in this process and the CLI does not export it. NOTHING here establishes that $($atRisk -join ', ') exist on this machine - the events were read out of $($pi.verified_build) and older builds may not carry all of them$depends. This is a PASS because it is a limit on what can be observed from here and not a fault in this tree; it is NOT the row saying the build was read and matched"
            return
        }

        $have = $null
        $want = $null
        $raw  = [string]$pi.claude_version
        $lead = ([regex]::Match($raw, '^\d+(\.\d+)*')).Value
        if (-not [version]::TryParse($lead, [ref]$have) -or
            -not [version]::TryParse([string]$pi.verified_build, [ref]$want)) {
            Add-Row -Id 'claude-version' -Status 'WARN' -Detail "CLAUDE_CODE_VERSION is '$raw', which could not be compared against the verified build $($pi.verified_build) as a version - so this row read a build and still established nothing about $($atRisk -join ', ')$depends"
            return
        }
        if ($have -lt $want) {
            Add-Row -Id 'claude-version' -Status 'WARN' -Detail "Claude Code $raw is BELOW $($pi.verified_build), the build $($atRisk -join ', ') were read out of. Those registrations may be inert here, and an inert hook is silent$depends"
            return
        }
        Add-Row -Id 'claude-version' -Status 'PASS' -Detail "Claude Code $raw, at or above the $($pi.verified_build) the hook events were read out of. That is a statement about the BUILD ONLY: no event below SessionStart is proved to have fired on this machine by anything in this report"
    }

} catch {
    # Anything that escapes the per-check handlers - a failed dot-source, a
    # missing common.ps1 - means the checkup did not happen. That is code 3,
    # not code 1, and the difference is stated rather than smoothed over.
    $script:Aborted = $_.Exception.Message
}

# --- report -----------------------------------------------------------------
$fails = @($script:Rows | Where-Object { $_.Status -eq 'FAIL' })
$warns = @($script:Rows | Where-Object { $_.Status -eq 'WARN' })
$pass  = @($script:Rows | Where-Object { $_.Status -eq 'PASS' })
# INFO IS A FOURTH STATUS AND IT IS NOT A DEGRADED PASS. It says a check looked,
# found a state, and that state is the CORRECT one for this installation shape -
# so there is nothing to attest and nothing to warn about. It exists because the
# payload restructure made one such state permanent: marketplace.json now lives
# at the marketplace repository ROOT and is not copied into the plugin, so its
# absence beside the plugin root is the designed arrangement rather than a fault.
# Reporting that as WARN would put `working, with 1 caveat(s)` and exit 2 on
# every healthy install forever, which is the "reports a fault it does not have"
# shape this command exists to refuse. INFO is counted into NEITHER the pass
# tally nor the warning tally: it is printed, named on the RESULT line, and left
# out of the verdict arithmetic entirely.
$infos = @($script:Rows | Where-Object { $_.Status -eq 'INFO' })

$w = 3
foreach ($r in $script:Rows) { if ($r.Id.Length -gt $w) { $w = $r.Id.Length } }

Write-Output "LW-WATCHTOWER doctor - $($script:Rows.Count) checks"
Write-Output ''
foreach ($r in $script:Rows) {
    if ($Quiet -and $r.Status -eq 'PASS') { continue }
    Write-Output ("  [{0}] {1}  {2}" -f $r.Status, $r.Id.PadRight($w), $r.Detail)
}
Write-Output ''

if ($null -ne $script:Aborted) {
    Write-Output "ABORTED: $($script:Aborted)"
    Write-Output "The doctor did NOT complete. The $($script:Rows.Count) line(s) above are a fragment of a checkup, not the result of one."
    exit 3
}

# THE THREE EXISTING TERMS KEEP THEIR ORDER AND THEIR WORDING, and the
# informational count is APPENDED rather than inserted. tests\doctor_behaviour.ps1
# derives the demanded exit code from this line by capture-group position, and a
# term inserted between `passed` and `warning(s)` would have made that derivation
# read the wrong number while still matching - a guard silently checking
# something else.
Write-Output ("RESULT: {0} passed, {1} warning(s), {2} failure(s), {3} informational" -f $pass.Count, $warns.Count, $fails.Count, $infos.Count)

# What a green run does not cover. Stated on every run, including the green
# ones, because a health report that omits its own blind spots is how "all
# checks passed" comes to be read as "everything works".
#
# THIS PARAGRAPH HAS NOW GONE STALE TWICE, IN THE SAME DIRECTION BOTH TIMES -
# it understated coverage - and it is hand-written text no guard derives, so
# the derivation for the current wording is recorded here rather than left to
# be reconstructed a third time. Nothing below is computed at run time; the
# next person to change what tests\ reaches has to change this by hand, and
# these are the commands that say whether it needs changing.
#
#   the eight observing modules, and the three gates:
#     $script:LwgModuleRegistry.Keys | ? { $script:LwgModuleRegistry[$_].kind -ne 'gate' }
#   the suite that reaches self_health, and the sections that do it:
#     tests\state_resolution.ps1 - B (#60, modules_resolved), C (#106, the
#     selfcheck.probe file, which is state_writable's side effect) and F (#177,
#     config_from_file, thresholds_live, payload_session and payload_cwd).
#
# NO PROBE COUNT IS WRITTEN HERE, DELIBERATELY, and the reason is a discrepancy
# found while deriving the above rather than a preference. lib\session_start.ps1
# sets SIX boolean fields on $selfcheck - the five the tree calls "the five
# probes" plus state_writable, which docs\modules.md's own "Five probes" section
# does not count. Which of those two numbers is right is a question about what
# counts as a probe, it is not settled anywhere in the tree, and settling it in
# passing inside a paragraph nothing derives is how the last two stale numbers
# got here. So this names the SECTIONS, which are checkable by looking, and
# leaves the count to the pages that already argue about it.
#
# The "one to three cases on at most two properties" clause for the other four
# is NOT re-derived here and is not presented as though it were: it is
# docs\testing.md's per-module count (context_pressure 2, docs_coupling 2,
# log_rotation 3, git_hygiene 1), and this line and that page state the same
# thing. Counting cases BY SUBJECT means parsing assertions to decide what they
# are about, which tests\doc_claims.ps1 declines to invent in passing for the
# same reason and says so in its own comment on this exact number.
#
# WHY "EVERY ONE of the EIGHT" RATHER THAN "ALL EIGHT", and what that does NOT
# buy. `of the <N> observing` is the shape doc_claims's observing-module-count
# rule reads, so the wording matches a live rule rather than evading one - but
# NO QUANTITY RULE CHECKS THIS LINE. tests\doc_claims.ps1 runs its counting
# rules over prose only - tracked .md, .json, .yml and .yaml, "A .ps1 is checked
# by the parse step and by its own suite" - so the number below is not among
# the ones it derives. (Its WIDE set does read .ps1, this file included, but
# those rules are the forbidden-phrasing and GM-promise ones, and none of them
# counts anything.) The two sites the observing count is actually read at are
# docs\testing.md and .github\notes\HANDOFF.md. The phrasing is kept in the
# family the guard knows so a reader grepping for the claim finds this line
# beside the pages, and so the day this paragraph moves onto a page it is
# already checkable. What holds it today is the case in
# tests\doctor_behaviour.ps1 (#253) and review, and saying otherwise would be
# this paragraph's own defect one turn on.
Write-Output ''
Write-Output "NOT checked here: whether the advisories actually fire, and whether Claude Code has"
Write-Output "this plugin ENABLED in the current session - a hook can be perfectly configured and"
Write-Output "still be switched off. EVERY ONE of the EIGHT observing modules - failure_capture,"
Write-Output "context_pressure, docs_coupling, git_hygiene and log_rotation"
Write-Output "(tests\stop_behaviour.ps1), orphan_watch (tests\supervision.ps1), context_injection"
Write-Output "(tests\subagent_scan.ps1) and self_health (tests\state_resolution.ps1 sections B, C"
Write-Output "and F, written against its self-check) - is exercised by a suite CI runs on every"
Write-Output "push and every PR, though for four of those eight - context_pressure, docs_coupling,"
Write-Output "git_hygiene and log_rotation - that is one to three cases on at most two properties"
Write-Output "and not end to end. Neither fact is established by this command: no test is run"
Write-Output "here, and a green run above says nothing about whether any advisory would fire."
Write-Output ''
Write-Output "THREE GATES SHIP, ALL OFF BY DEFAULT, AND NOTHING HERE EXERCISES ANY OF THEM."
Write-Output "delegate_gate (lib\gate_delegate.ps1, PreToolUse, refuses Edit, Write, NotebookEdit,"
Write-Output "Bash and PowerShell on the main thread when interaction.delegate is on),"
Write-Output "send_liveness_gate (lib\gate_send.ps1, PreToolUse on SendMessage, refuses a send to a"
Write-Output "provably dead subagent when supervision.send_liveness is on) and completion_audit"
Write-Output "(lib\gate_stop.ps1, a blocking turn-end hook on Stop and SubagentStop, refuses a"
Write-Output "completion claim resting on a queued message when supervision.completion_audit is on)."
Write-Output "The checks above confirm each is registered and that its switch is a real key; whether"
Write-Output "each actually refuses a call is tested by tests\gate_delegate.ps1 and"
Write-Output "tests\supervision.ps1, not here. WHICH OF THEM IS ARMED ON THIS MACHINE is the roster"
Write-Output "printed below, derived from the registry and the live config rather than from this"
Write-Output "paragraph. The two gates removed on 30 July 2026 - the destructive command gate, then"
Write-Output "secret_scan - are gone and are not coming back by accident: nothing here inspects a"
Write-Output "shell command or a credential."

# --- INFORMATIONAL: what is switched on -------------------------------------
#
# THIS IS NOT A CHECK, AND THE DISTINCTION IS LOAD-BEARING RATHER THAN
# PEDANTIC. Nothing below calls Add-Row, so the "- N checks" header, the row
# list, the RESULT tally and the VERDICT are all computed before this block
# runs and cannot be moved by it. The exit code is decided underneath from
# $fails and $warns only. A reader who takes an OFF gate here for a fault has
# read a report as a diagnosis; OFF is the shipped state.
#
# WHERE IT CAME FROM. bin\lwg-status.ps1 is deleted and this is the one thing
# it printed that nothing else did: the per-module ON/OFF listing and a
# paragraph per gate. Both are DERIVED - $LwgModuleRegistry plus the resolved
# config - so a module or gate added later appears here with no edit to this
# block. It EXTENDS the static roster above rather than repeating it: that
# paragraph names the three gates this plugin ships, which is a fact about the
# source tree; this one says which of them can refuse a call on this machine,
# right now, which is a fact about the config in front of it.
#
# IT ALSO CANNOT ABORT THE DOCTOR. The whole block sits in its own try, and a
# throw is reported as one line saying the roster is missing - never as a
# check, never as an abort, and never as an exit code. A report that could
# take the diagnosis down with it would be worse than no report.
#
# -Quiet SUPPRESSES THE MODULE TABLE AND KEEPS THE GATES, which is exactly
# what bin\lwg-status.ps1's -Brief did. A gate that can block work is not
# noise at any verbosity; an eleven-row module inventory is.
try {
    $iCfg   = Get-LwgConfig
    # Outside a hook there is no payload, so repo identity comes from the cwd -
    # which is what Get-LwgRepo does with a payload anyway. Per-repo overrides
    # in config.json therefore apply here exactly as they would in a session,
    # and the repo they were resolved for is named on the line below because
    # nothing else in this report says which config actually won.
    $iRepo  = ''
    try { $iRepo = (Get-LwgRepoInfo -Path (Get-Location).Path).slug } catch { $iRepo = '' }

    $iEnabled     = @(Get-LwgEnabledModules     -Config $iCfg -Repo $iRepo)
    $iActive      = @(Get-LwgActiveModules      -Config $iCfg -Repo $iRepo)
    $iActiveGates = @(Get-LwgActiveGates        -Config $iCfg -Repo $iRepo)
    $iAll         = @($script:LwgModules)
    # TWO gate numbers, and collapsing them into one is the whole reason this
    # section exists. $iShipped is what is DECLARED kind 'gate' in the
    # registry; $iActiveGates is what is switched on and can refuse a call
    # right now. Reporting only the first would claim protection that is
    # switched off; reporting only the second would hide that a gate exists at
    # all, and an operator cannot turn on a thing they were never told they
    # have.
    $iShipped     = @($script:LwgGates)

    Write-Output ''
    Write-Output 'WHAT IS SWITCHED ON (informational - no check above depends on any of it):'
    Write-Output ''
    # "declared implemented", NOT "backed by code". $iActive is `enabled in
    # config` AND `the registry says status = 'implemented'`, and the second
    # half is a string literal in lib\common.ps1 - nothing here opens a file.
    # A module whose implementation had been deleted would still be counted,
    # so the count is left as a count and honestly labelled. The GATES block
    # below is the one that says outright when a registry path is not on disk.
    Write-Output ("  {0} of {1} modules ACTIVE (enabled in config AND declared implemented in the registry)" -f $iActive.Count, $iAll.Count)
    Write-Output ("  {0} gate(s) SHIPPED: {1}" -f $iShipped.Count, $(if ($iShipped.Count) { $iShipped -join ', ' } else { 'none - this plugin has no blocking code at all' }))
    Write-Output ("  {0} gate(s) LIVE: {1}" -f $iActiveGates.Count, $(if ($iActiveGates.Count) { ($iActiveGates -join ', ') + ' - these can BLOCK a tool call outright' } else { 'none - nothing can be blocked right now' }))
    # BOTH FILES THE VALUES CAME FROM - #11. Everything above is resolved
    # through Get-LwgConfig, which merges config.override.json under the state
    # directory over the shipped defaults, so naming config.json alone would
    # credit every operator setting to a file that does not hold one. An
    # override that EXISTS and could not be read is named too, because its
    # values are being DISCARDED and a roster that quietly showed the defaults
    # instead would be the silent no-op this report exists to catch - the
    # config-registry row above FAILS on that state, and this line is what
    # says which file it is talking about.
    #
    # THE WORDING IS LIFTED FROM bin\lwg-config.ps1's own source line rather
    # than reinvented, so the two reports do not describe one machine in two
    # vocabularies.
    $iOvPath = ''
    try { $iOvPath = "$(Get-LwgConfigOverridePath)" } catch { $iOvPath = '' }
    if ([string]::IsNullOrWhiteSpace($iOvPath)) { $iOvPath = 'config.override.json under the state directory' }
    #
    # AND "none" IS A CLAIM ABOUT ONE DIRECTORY, NOT ABOUT THE MACHINE (#270).
    # Get-LwgConfig reads the override under the state directory THIS RUN
    # resolved. With two of them on disk that resolution was a choice made on
    # mtime, and the sentence "override: none - these are the shipped defaults"
    # was printed over an armed gate whose override sat in the other directory.
    # An absence can only be reported for somewhere that was looked at, so when
    # the choice was ambiguous the line says which somewhere - and the state-dir
    # row above, now a WARN, carries the list and the way out.
    $iSplit = @{ ambiguous = $false }
    try { $iSplit = Get-DoctorStateSplit -Info (Get-LwgStateDirInfo) } catch { }
    $iOvNote =
        if ("$($iCfg._override_error)" -ne '') { "   override: IGNORED - $iOvPath $($iCfg._override_error)" }
        elseif ("$($iCfg._override)" -ne '')   { "   override: $($iCfg._override)" }
        elseif ($iSplit.ambiguous)             { "   override: none IN THE DIRECTORY THIS RUN RESOLVED - see the state-dir row, $($iSplit.ranked.Count) exist" }
        else                                   { '   override: none - these are the shipped defaults' }
    Write-Output ("  resolved for repo: {0}   config: {1}{2}" -f `
        $(if ($iRepo) { $iRepo } else { '(not in a repo)' }), `
        $(if ($iCfg._source -eq 'file') { 'config.json' } else { 'BUILT-IN DEFAULTS (config.json unreadable)' }), `
        $iOvNote)

    # --- the gates, one paragraph each --------------------------------------
    # Printed even under -Quiet. The two counts above are numbers; this is the
    # sentence that stops "3 shipped, 0 live" being read as either "protected"
    # or "there is nothing here".
    if ($iShipped.Count -gt 0) {
        Write-Output ''
        Write-Output '  GATES'
        foreach ($g in $iShipped) {
            $e     = $script:LwgModuleRegistry[$g]
            $live  = $iActiveGates -contains $g
            $sw2   = $e.switch
            $where = if ($null -ne $sw2) { "$($sw2.block).$($sw2.key)" } else { "modules.$g" }
            $dflt  = if ($null -ne $sw2) { [bool]$sw2.default } else { $true }

            # THE KEY PATH AND THE EFFECTIVE ANSWER ARE NOT JOINED BY AN `=`,
            # and that is deliberate. Printing
            #
            #     switch  : interaction.delegate = false
            #
            # puts the RESOLVED answer beside the key spelled in JSON literals,
            # so the line reads as a quotation of config.json and is not one.
            # Only a real boolean is a setting: a quoted "true" at that key is
            # ignored by the resolver and the built-in default stands, so an
            # operator could open the file, read `"delegate": "true"`, and be
            # told `interaction.delegate = false` with nothing on screen saying
            # a written value had been rejected.
            #
            # So three facts on three lines: where the switch lives, what is
            # STORED there, and what it RESOLVED to. Format-LwgFlagState is the
            # renderer the config command uses, and it has the third word -
            # 'ignored' - that a bare boolean cannot express.
            #
            # WHAT THIS STILL DOES NOT DO: name the winning SCOPE. A per-repo
            # override that differs from the global resolves correctly and
            # reports correctly, and the `in file` line shows the GLOBAL value
            # only, so on that config the two lines disagree with no
            # explanation.
            #
            # THE FALLBACK PATH GETS ITS OWN SENTENCE or this reproduces the
            # defect it is fixing. Get-LwgConfig FAILS OPEN: an unparseable
            # config.json returns the built-in defaults, which carry no
            # `interaction` block at all. Reading it for the stored value on
            # that path yields $null, and printing "not present" would be a
            # second line reading as a quotation of a file that was never read.
            $fromFile  = ($iCfg._source -eq 'file')
            $storedRaw = $null
            if ($fromFile) {
                if ($null -ne $sw2) {
                    try { $storedRaw = $iCfg.($sw2.block).($sw2.key) } catch { $storedRaw = $null }
                } else {
                    try { $storedRaw = $iCfg.modules.$g } catch { $storedRaw = $null }
                }
            }
            $storedText =
                if (-not $fromFile)                { 'NOT READ - config.json did not parse, so this is the built-in default and not the file. See the config-registry row above' }
                elseif ($null -eq $storedRaw)      { 'not present - the built-in default stands' }
                elseif ($storedRaw -isnot [bool])  { "'$storedRaw' - NOT A BOOLEAN, so it is IGNORED and the built-in default stands" }
                else                               { Format-LwgFlagState $storedRaw }

            Write-Output ("    {0}  {1}" -f $g, $(if ($live) { 'LIVE - it can refuse a tool call right now' } else { 'OFF - it refuses nothing' }))
            Write-Output ("      switch  : {0}   (ships {1})" -f $where, $(if ($dflt) { 'ON' } else { 'OFF BY DEFAULT' }))
            Write-Output ("      in file : {0}" -f $storedText)
            Write-Output ("      resolved: {0}" -f $(if ($live) { 'on' } else { 'off' }))

            # `code:` IS A REGISTRY STRING AND SAYS SO WHEN THE FILE IS NOT
            # THERE. $e.impl is a display field: for delegate_gate it is a
            # path, for log_rotation it is 'lib/common.ps1 (Invoke-LwgRotate),
            # called from lib/supervisor.ps1'. Nothing above read the disk for
            # it, so a gate whose implementation had been deleted would print
            # its file name under a heading promising the switch would make it
            # LIVE. THE FINDING IS STATED ON THE LINE AND IS NOT TURNED INTO A
            # FAILURE - this block is informational, and a missing impl file
            # becoming a FAIL row is a CHECK someone has to write above.
            $implPath = ''
            if ($e.impl -match '^[A-Za-z0-9_./\\-]+\.ps1$') { $implPath = [string]$e.impl }
            $implNote = ''
            if ($implPath) {
                $full = Join-Path $pluginRoot ($implPath -replace '/', '\')
                if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
                    $implNote = '   *** NOT ON DISK - the registry names a file that is not there ***'
                }
            }
            Write-Output ("      code    : {0}{1}" -f $e.impl, $implNote)
        }
        Write-Output ''
        Write-Output '    OFF BY DEFAULT IS THE SHIPPED STATE, not a fault and not something for this'
        Write-Output '    report to fix silently. A gate that blocks work the operator did not ask to'
        Write-Output '    have blocked gets the whole plugin disabled, so nothing here arms itself.'
        Write-Output '    Turn one on and the LIVE count above moves with it. No check above reads'
        Write-Output '    these lines, so an OFF gate never costs a passing verdict.'
    }

    if (-not $Quiet) {
        Write-Output ''
        # STATE is the only column that answers "is this doing anything". The
        # other three exist so a reader can see WHY, because "off" and "cannot
        # be built" are different facts and one column would flatten them into
        # the same silence.
        Write-Output '  MODULE                 KIND     BUILT        ENABLED  STATE'
        Write-Output '  ---------------------- -------- ------------ -------- -------------------------'
        foreach ($m in $iAll) {
            $e     = $script:LwgModuleRegistry[$m]
            $isOn  = $iEnabled -contains $m
            $built = if ($e.blocked -eq $true) { 'BLOCKED' } elseif ($e.status -eq 'implemented') { 'yes' } else { 'no' }
            $state =
                if ($iActive -contains $m)          { 'ACTIVE' }
                elseif ($e.blocked -eq $true)       { 'inert - no hook can supply its data' }
                elseif ($e.status -ne 'implemented'){ 'inert - not written yet' }
                # A module switched from outside the `modules` block names the
                # key that actually holds it. "switched off in config" would
                # send a reader to a flag that is not there.
                elseif ($null -ne $e.switch)        { "off - $($e.switch.block).$($e.switch.key) is false" }
                else                                { 'off - switched off in config' }
            Write-Output ('  {0} {1} {2} {3} {4}' -f `
                $m.PadRight(22), $e.kind.PadRight(8), $built.PadRight(12), `
                $(if ($isOn) { 'on' } else { 'off' }).PadRight(8), $state)
        }
        Write-Output ''
        Write-Output '  A flag set to on is an INTENTION. Only the STATE column reports behaviour:'
        Write-Output '  an enabled module with no code behind it is inert, and is counted nowhere'
        Write-Output '  as coverage. Nothing in this table was checked by anything above it.'
    }
} catch {
    Write-Output ''
    Write-Output "  (the module and gate roster could not be produced: $($_.Exception.Message))"
    Write-Output '  Nothing above or below is affected: this block is a report, not a check, and'
    Write-Output '  the verdict was decided before it ran.'
}

if ($fails.Count -gt 0) {
    Write-Output ''
    Write-Output "VERDICT: NOT healthy - $($fails.Count) check(s) failed."
    exit 1
}
if ($warns.Count -gt 0) {
    Write-Output ''
    Write-Output "VERDICT: working, with $($warns.Count) caveat(s) above."
    exit 2
}
Write-Output ''
if ($infos.Count -gt 0) {
    # NOT "every check above passed": an INFO row did not pass, it reported a
    # correct state there was nothing to attest about. Saying "passed" over it
    # would be the small overstatement this command is named for.
    Write-Output "VERDICT: healthy - no check failed and none raised a caveat; $($infos.Count) row(s) are informational."
} else {
    Write-Output 'VERDICT: healthy - every check above passed.'
}
exit 0
