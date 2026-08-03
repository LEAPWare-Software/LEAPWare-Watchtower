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
    # Print only the verdict line and any WARN/FAIL rows. The exit code is
    # identical either way - quiet changes what is shown, never what is judged.
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
        [Parameter(Mandatory = $true)][ValidateSet('PASS', 'WARN', 'FAIL')][string]$Status,
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
            Add-Row -Id 'marketplace' -Status 'WARN' -Detail 'no marketplace.json - the repo cannot be added with /plugin marketplace add'
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
        }

        if ($bits.Count -gt 0) {
            Add-Row -Id 'config-registry' -Status 'FAIL' -Detail ($bits -join '; ')
            return
        }
        $extra = if ($own.Count -gt 0) {
            "; $($own.Count) module(s) switched from outside that block, each on a key that exists: " +
            (($own | ForEach-Object {
                $s = $script:LwgModuleRegistry[$_].switch
                "$_ -> $($s.block).$($s.key)" }) -join ', ')
        } else { '' }
        Add-Row -Id 'config-registry' -Status 'PASS' -Detail "parses; all $($inConfig.Count) module flags match the registry exactly$extra"
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
        # 256 KB of tail is many hundreds of records and costs one seek.
        $rec = $null
        foreach ($line in @(Get-LwgTailLines -Path $log -Bytes 262144)) {
            try { $r = $line | ConvertFrom-Json } catch { continue }
            if ($r.event -eq 'SessionStart') { $rec = $r }
        }
        if ($null -eq $rec) {
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
    Invoke-Check -Id 'statusline' -Body {
        $sp = Join-Path $env:USERPROFILE '.claude\settings.json'
        if (-not (Test-Path -LiteralPath $sp)) {
            Add-Row -Id 'statusline' -Status 'FAIL' -Detail "no settings file at $sp - the status line cannot be configured"
            return
        }
        # PS 5.1's Get-Content -Raw keeps a UTF-8 BOM, which ConvertFrom-Json
        # rejects. Settings files written by other tools do carry one.
        $raw = (Get-Content -LiteralPath $sp -Raw).TrimStart([char]0xFEFF)
        $st  = ($raw | ConvertFrom-Json).statusLine
        if ($null -eq $st -or [string]::IsNullOrWhiteSpace([string]$st.command)) {
            Add-Row -Id 'statusline' -Status 'FAIL' -Detail "$sp has no statusLine.command - the HH segment is not rendered, so this plugin has no visible indicator"
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

        # The installed copy is a COPY. docs/install.md is explicit that the
        # two can drift and that nothing else detects it. This detects it.
        $repoCopy = Join-Path $pluginRoot 'statusline\statusline.ps1'
        $drift    = ''
        if (Test-Path -LiteralPath $repoCopy) {
            $a = (Get-FileHash -LiteralPath $target   -Algorithm SHA256).Hash
            $b = (Get-FileHash -LiteralPath $repoCopy -Algorithm SHA256).Hash
            if ($a -ne $b) {
                Add-Row -Id 'statusline' -Status 'WARN' -Detail "wired to $target, but it DIFFERS from statusline/statusline.ps1 in this repo - the installed copy is stale or locally modified; re-copy it to make the repo's version live"
                return
            }
            $drift = '; matches the repo copy'
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
        # not even true: verbosity, plain and delegate all invoke the one
        # bin\lwg-toggle.ps1 with a different -Flag, because three copies of the
        # same read/validate/write/report path would be three things to keep
        # correct. Asserting the convention would fail those three for being
        # written properly, while still missing a command that names a script it
        # does not have. What matters is that the file it actually invokes is on
        # disk, which is the same ${CLAUDE_PLUGIN_ROOT} test the hooks-declared
        # check applies to hook scripts.
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
        # .git is skipped as object storage; .claude is local harness state -
        # settings.local.json and agent worktrees, which are whole second copies
        # of this tree - and is not part of the plugin.
        #
        # BOTH exclusions are matched against the path RELATIVE TO $pluginRoot,
        # never against the absolute path. This plugin is normally reached
        # through a junction under ~\.claude\skills\, so EVERY absolute path in
        # the tree contains '\.claude\', and an absolute-path exclusion swallowed
        # the ENTIRE plugin: 0 files scanned, 12 command files checked by
        # nothing. A check whose result depends on where the thing is installed
        # is not a check. Relative matching also keeps '.claude-plugin\' in
        # scope, which is a real part of the plugin and must stay scanned.
        $re   = [regex]('(?<![A-Za-z0-9_-])/' + [regex]::Escape($p) + ':([A-Za-z0-9][A-Za-z0-9_-]*)')
        $refs = @{}
        $scanned = 0
        foreach ($f in @(Get-ChildItem -LiteralPath $pluginRoot -Recurse -File -ErrorAction SilentlyContinue |
                         Where-Object { $_.Extension -in @('.md', '.ps1', '.json', '.yml', '.yaml', '.txt') })) {
            $rel = $f.FullName.Substring($pluginRoot.Length).TrimStart('\', '/')
            if ($rel -like '.git\*' -or $rel -like '.claude\*') { continue }
            $text = ''
            try { $text = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop } catch { continue }
            $scanned++
            if ([string]::IsNullOrEmpty($text)) { continue }
            foreach ($m in $re.Matches($text)) {
                $n = $m.Groups[1].Value.ToLowerInvariant()
                if (-not $refs.ContainsKey($n)) { $refs[$n] = @() }
                if ($refs[$n] -notcontains $rel) { $refs[$n] += $rel }
            }
        }

        # An enumeration that found nothing has checked nothing, and a check that
        # cannot fail is the defect this file exists to catch. The same rule the
        # CI JSON step was given in d1ff015.
        if ($refs.Count -eq 0) {
            Add-Row -Id 'commands' -Status 'FAIL' -Detail "scanned $scanned file(s) and found NO /${p}:* reference at all - the reference scan is broken, so this check proved nothing about the command surface"
            return
        }

        foreach ($n in @($refs.Keys | Sort-Object)) {
            if ($names -contains $n) { continue }
            $problems += "/${p}:$n is referenced in $($refs[$n] -join ', ') but commands\$n.md does not exist"
        }

        if ($problems.Count -gt 0) {
            Add-Row -Id 'commands' -Status 'FAIL' -Detail ($problems -join '; ')
            return
        }
        Add-Row -Id 'commands' -Status 'PASS' -Detail "$($cmds.Count) command(s), each with its backing script: $(($names | ForEach-Object { "/${p}:$_" }) -join ', '); $($refs.Count) distinct command(s) referenced across $scanned scanned file(s), all declared"
    }

    # ---------------------------------------------------------------------
    # 9. verification_gate has something that can DISARM it
    # ---------------------------------------------------------------------
    # THE ASSERTION, stated exactly, because its plan wording is terse: while
    # verification_gate is enabled, ZERO verify-class roles being installed is a
    # FAULT, and this check fails on it. docs/roles.md is the reasoning - "with
    # no verify-class role installed, verification_gate can only ever nag and
    # never clear: it warns when the newest work-agent record is newer than the
    # newest verify-agent record, and with no verifier there is never a verify
    # record to be newer than." A module in that state is not off, and it does
    # not report itself broken; it is on, counted toward the SessionStart
    # banner's coverage number, and permanently unable to reach the outcome it
    # exists to ask for. That is the founding-defect shape, and it is exactly
    # what an install that deleted agents\lw-verifier.md would have.
    #
    # A role counts as verify-class two ways, and both are counted because both
    # are how the classifier itself decides (lib/stop_advisories.ps1):
    #
    #   lw-class    the role's own frontmatter says `lw-class: verify`. This is
    #               the authoritative one and it wins wherever it is present.
    #   config-name the role declares no class, and its name is in
    #               module_config.verification_gate.verify_agents. Only a name
    #               with a role file ON DISK is counted - a name in the array
    #               with no role behind it cannot disarm anything, and counting
    #               it here would be this check reporting a list as coverage,
    #               which is the defect one paragraph up.
    #
    # It is a LOWER BOUND and says so. Roles shipped by OTHER plugins are not
    # enumerable from here (no other plugin's install path is derivable), so a
    # machine may have a verifier this cannot see. That direction is safe: it can
    # produce a spurious FAIL, never a false PASS, and a spurious FAIL is a
    # sentence the operator can read and disagree with.
    Invoke-Check -Id 'agent-roles' -Body {
        $cfg   = Get-LwgConfig
        $on    = Test-LwgModule -Name 'verification_gate' -Config $cfg
        $roles = @(Get-LwgInstalledAgents -ProjectRoot ((Get-Location).Path))

        if ($roles.Count -eq 0) {
            # An enumeration that found nothing has checked nothing. Same rule as
            # the reference scan in check 8.
            $where = @(Get-LwgAgentRoots -ProjectRoot ((Get-Location).Path) | ForEach-Object { $_.path })
            $st = if ($on) { 'FAIL' } else { 'WARN' }
            Add-Row -Id 'agent-roles' -Status $st -Detail "no agent role file found in any scope ($($where -join '; ')) - nothing can be classified, so verification_gate cannot see work OR verification$(if ($on) { ', and it is ENABLED' } else { ' (it is switched off)' })"
            return
        }

        $named    = @($cfg.module_config.verification_gate.verify_agents | ForEach-Object { [string]$_ })
        $classed  = @($roles | Where-Object { $_.class -eq 'verify' })
        $bynameOnly = @($roles | Where-Object {
            $_.class -eq '' -and ($named -contains $_.name -or $named -contains "$(Get-LwgPluginName):$($_.name)") })
        $declaring = @($roles | Where-Object { $_.class -ne '' })

        $verifiers = $classed.Count + $bynameOnly.Count

        if ($on -and $verifiers -eq 0) {
            Add-Row -Id 'agent-roles' -Status 'FAIL' -Detail "verification_gate is ENABLED and ZERO verify-class roles are installed across $($roles.Count) role(s) - no role declares lw-class: verify and no installed role is named in module_config.verification_gate.verify_agents, so the advisory can nag and can NEVER clear. Restore agents\lw-verifier.md, or install a role whose frontmatter carries lw-class: verify"
            return
        }

        $how = @()
        if ($classed.Count -gt 0)     { $how += "$($classed.Count) by lw-class ($(@($classed | ForEach-Object { $_.name }) -join ', '))" }
        if ($bynameOnly.Count -gt 0)  { $how += "$($bynameOnly.Count) by verify_agents name ($(@($bynameOnly | ForEach-Object { $_.name }) -join ', '))" }

        if (-not $on) {
            Add-Row -Id 'agent-roles' -Status 'PASS' -Detail "verification_gate is switched OFF, so nothing here can be violated; $($roles.Count) role(s) visible, $verifiers verify-class"
            return
        }

        # The classifier reads lw-class. If NOT ONE installed role declares it,
        # the key is being read and is answering nothing, and every classification
        # is resting on the hand-maintained arrays - working, but the state the
        # arrays were supposed to be retired from. Said out loud rather than left
        # to be inferred from a green line.
        if ($declaring.Count -eq 0) {
            Add-Row -Id 'agent-roles' -Status 'WARN' -Detail "verification_gate is enabled and $verifiers verify-class role(s) resolve ($($how -join '; ')), but NOT ONE of the $($roles.Count) installed role(s) declares lw-class - every classification is falling back to the config.json name arrays, which have to be maintained by hand"
            return
        }

        Add-Row -Id 'agent-roles' -Status 'PASS' -Detail "verification_gate is enabled and $verifiers verify-class role(s) can disarm it: $($how -join '; '). $($declaring.Count) of $($roles.Count) visible role(s) declare lw-class (lower bound - other plugins' roles are not enumerable from here)"
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

Write-Output ("RESULT: {0} passed, {1} warning(s), {2} failure(s)" -f $pass.Count, $warns.Count, $fails.Count)

# What a green run does not cover. Stated on every run, including the green
# ones, because a health report that omits its own blind spots is how "all
# checks passed" comes to be read as "everything works".
Write-Output ''
Write-Output "NOT checked here: whether the advisories actually fire, and whether Claude Code has"
Write-Output "this plugin ENABLED in the current session - a hook can be perfectly configured and"
Write-Output "still be switched off. SIX of the nine observing modules - mission_drift,"
Write-Output "failure_capture, context_pressure, docs_coupling, git_hygiene and log_rotation - are"
Write-Output "exercised by tests\stop_behaviour.ps1, which CI runs on every push and every PR,"
Write-Output "though for four of those six that is one to three cases on at most two properties"
Write-Output "and not end to end. The other THREE - verification_gate, self_health and"
Write-Output "context_injection - are exercised by nothing, anywhere. Neither"
Write-Output "fact is established by this command: no test is run here, and a green run above says"
Write-Output "nothing about whether any advisory would fire."
Write-Output ''
Write-Output "ONE GATE SHIPS AND NOTHING HERE EXERCISES IT. delegate_gate - lib\gate_delegate.ps1,"
Write-Output "registered on PreToolUse - refuses Edit, Write, NotebookEdit, Bash and PowerShell on the"
Write-Output "main thread"
Write-Output "when interaction.delegate is on, and it is OFF by default. The checks above confirm it is"
Write-Output "registered and that its switch is a real key; whether it actually refuses a call is tested"
Write-Output "by tests\gate_delegate.ps1, not here. Run /lw-watchtower:status for whether it is armed. The two"
Write-Output "gates removed on 30 July 2026 - the destructive command gate, then secret_scan - are gone"
Write-Output "and are not coming back by accident: nothing here inspects a shell command or a credential."

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
Write-Output 'VERDICT: healthy - every check above passed.'
exit 0
