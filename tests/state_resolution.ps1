#requires -version 5
<#
  LW-WATCHTOWER state-resolution and platform regression suite.

      powershell -NoProfile -ExecutionPolicy Bypass -File tests\state_resolution.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File tests\state_resolution.ps1 -Verbose

  WHAT THIS IS

  Nothing in tests\ had ever executed lib\session_start.ps1. The SessionStart
  hook is the one surface every session sees - the banner, the model-visible
  context and the mode word all come out of it - and its five self-check probes,
  its state-dir resolution and the platform it resolves them on were asserted by
  no case at all. This file is that coverage, built around the five defects it
  pins.

  THE FOUR IT PINS

    #146 CLAUDE_CONFIG_DIR was honoured by NOTHING. Every path in the plugin
         composed $env:USERPROFILE with a literal `.claude`, so on a machine
         where Claude Code's configuration directory has been relocated the
         plugin reads, writes and reports on a directory the CLI never touches -
         and reports success while doing it. lib\common.ps1's state resolver was
         one of those sites. Section A. Section A5 is the end-to-end case: it
         runs the real SessionStart hook in a real child process with
         CLAUDE_PLUGIN_DATA cleared and CLAUDE_CONFIG_DIR pointed at a scratch
         tree, and asserts the ledger lands there and that NOTHING is written
         under the profile.

    #60  self_health probe 2 could not fail. It asserted that every declared
         module "resolves to a real boolean" by testing the RETURN of
         Test-LwgModule, which is a [bool] on every one of its exit paths by
         construction - so the predicate was unsatisfiable for every input and
         the probe reported a pass for every config.json, including the
         malformed ones it read as though it were checking for them. Probe 2
         feeds $selfcheck.ok, which feeds Get-LwgSessionMode, which is the mode
         word the whole plugin is presented through. Section B.

    #106 the state-writable probe APPENDED one timestamp to selfcheck.probe on
         every SessionStart, and nothing in the tree ever rotated, truncated or
         read that file. It was the only file the plugin wrote with no bound of
         any kind, inside a plugin whose log_rotation module reports itself as
         capping the logs. Section C.

    #8   marketplace detection probed ~\.claude\plugins\repos, a directory that
         does not exist on a live Claude Code install. Real installs live under
         plugins\cache\<marketplace>\<plugin>\<version>\ and are recorded in
         plugins\installed_plugins.json. Section D covers the shared resolver
         this suite's sibling batches will call; the two CALL SITES
         (bin\lwg-setup.ps1 and statusline\statusline.ps1) are not touched here
         and the defect stays open in both until they are.

  THE SANDBOX

  Every child process gets its own environment block - USERPROFILE pointed at a
  scratch profile, CLAUDE_PLUGIN_ROOT / CLAUDE_PLUGIN_DATA / CLAUDE_CONFIG_DIR
  removed unless the case sets them. This process's own environment is NEVER
  mutated, so a case cannot leak into the next one and nothing here can reach
  the operator's own .claude directory. That is not tidiness: the defect in
  section A is precisely "writes into the operator's real profile", and a suite
  proving it must not do it.

  Everything is built under [IO.Path]::GetTempPath() with a fresh GUID, because
  tests\doc_claims.ps1 runs every sibling suite in parallel.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$script:Results = @()
$script:Pass    = 0
$script:Aborted = $null
$script:Work    = $null

$script:RepoRoot = Split-Path -Parent $PSScriptRoot

function Say { param([string]$Text) Write-Output $Text }

function Add-Case {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    $script:Results += [pscustomobject]@{ Name = $Name; Ok = $Ok; Detail = $Detail }
    if ($Ok) {
        $script:Pass++
        Say ("  PASS  {0}" -f $Name)
    } else {
        Say ("  FAIL  {0}" -f $Name)
        if ($Detail) { foreach ($l in ($Detail -split "`n")) { Say ("        {0}" -f $l) } }
    }
}

function Abort-Suite { param([string]$Why) throw $Why }

# --- child process ---------------------------------------------------------
function Invoke-Child {
    <#
      Run one PowerShell script in a child process with an environment block
      this suite controls completely, and read its stdout back as UTF-8.

      $EnvSet is applied to the CHILD's block only. A $null value REMOVES the
      variable, which is how a case says "this machine does not have it set" -
      an empty string is not the same thing and Get-LwgStateDirInfo's own
      IsNullOrWhiteSpace test would read them alike, so both are exercised
      through this one door rather than assumed equivalent.
    #>
    param(
        [string]$ScriptPath,
        [hashtable]$EnvSet = @{},
        [string]$Stdin = '',
        [string]$WorkDir = ''
    )

    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName               = 'powershell'
    $psi.Arguments              = '-NoProfile -ExecutionPolicy Bypass -File "' + $ScriptPath + '"'
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $psi.StandardErrorEncoding  = New-Object Text.UTF8Encoding($false)
    if ($WorkDir) { $psi.WorkingDirectory = $WorkDir }

    # Cleared for EVERY case unless the case names them. Anything inherited here
    # would decide the answer instead of the code under test.
    foreach ($v in @('CLAUDE_PLUGIN_ROOT', 'CLAUDE_PLUGIN_DATA', 'CLAUDE_CONFIG_DIR')) {
        if ($psi.EnvironmentVariables.ContainsKey($v)) { [void]$psi.EnvironmentVariables.Remove($v) }
    }
    foreach ($k in $EnvSet.Keys) {
        if ($null -eq $EnvSet[$k]) {
            if ($psi.EnvironmentVariables.ContainsKey($k)) { [void]$psi.EnvironmentVariables.Remove($k) }
        } else {
            $psi.EnvironmentVariables[$k] = [string]$EnvSet[$k]
        }
    }

    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Stdin)
    $out = ''; $err = ''; $code = 255
    $p = [Diagnostics.Process]::Start($psi)
    try {
        $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $p.StandardInput.BaseStream.Flush()
        $p.StandardInput.Close()
        $out = $p.StandardOutput.ReadToEnd()
        $err = $p.StandardError.ReadToEnd()
        $p.WaitForExit()
        $code = $p.ExitCode
    } finally { $p.Dispose() }
    return @{ code = $code; out = $out; err = $err }
}

# --- fixtures --------------------------------------------------------------
function New-Dir {
    param([string]$Path)
    [void][IO.Directory]::CreateDirectory($Path)
    return $Path
}

function New-PluginTree {
    <#
      A copy of the parts of the repository lib\session_start.ps1 needs: lib\,
      config.json and .claude-plugin\. A COPY and not the tree itself, so a case
      can hand it a malformed config.json without touching the working tree.
    #>
    param([string]$Root, [string]$ConfigJson = '')

    New-Dir $Root | Out-Null
    Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'lib') -Destination (Join-Path $Root 'lib') -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $script:RepoRoot '.claude-plugin') -Destination (Join-Path $Root '.claude-plugin') -Recurse -Force
    # IsNullOrEmpty and not `$null -eq`: a [string] parameter defaulted to $null
    # binds as '', so the $null test never fires and every case that meant "the
    # SHIPPED config" would silently get an EMPTY one - which Get-LwgConfig
    # correctly reads as unparseable and replaces with the built-in defaults.
    # The control case would then have failed for a reason not in the tree.
    if ([string]::IsNullOrEmpty($ConfigJson)) {
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'config.json') -Destination (Join-Path $Root 'config.json') -Force
    } else {
        [IO.File]::WriteAllText((Join-Path $Root 'config.json'), $ConfigJson, [Text.UTF8Encoding]::new($false))
    }
    return $Root
}

function New-Probe {
    <#
      A one-shot script that dot-sources the plugin's common.ps1 and prints ONE
      compressed JSON object. Written into the case's own tree and run through
      Invoke-Child, so a resolver is exercised in a fresh process with the
      case's environment - never in this one, where a memoised answer from a
      previous case would decide it.
    #>
    param([string]$Root, [string]$Name, [string]$Body)

    $path = Join-Path $Root "$Name.ps1"
    $text = @"
`$ErrorActionPreference = 'Continue'
`$o = [ordered]@{}
try {
    . (Join-Path '$($Root -replace "'","''")' 'lib\common.ps1')
$Body
} catch {
    `$o['error'] = `$_.Exception.Message
}
[Console]::Out.Write((`$o | ConvertTo-Json -Depth 6 -Compress))
"@
    [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
    return $path
}

function Read-Json {
    param([hashtable]$Res, [string]$What)
    $t = [string]$Res.out
    if ([string]::IsNullOrWhiteSpace($t)) {
        return @{ ok = $false; why = "$What printed nothing (exit $($Res.code)). stderr: $($Res.err)" }
    }
    try { return @{ ok = $true; obj = ($t | ConvertFrom-Json) } }
    catch { return @{ ok = $false; why = "$What printed something that is not JSON: $t" } }
}

function New-Payload {
    param([string]$Cwd, [string]$Session = 'sess-state-resolution')
    return (@{ session_id = $Session; cwd = $Cwd; source = 'startup' } | ConvertTo-Json -Compress)
}

function Get-LedgerRecords {
    <# Every lw-watchtower.jsonl record under a directory tree, parsed. #>
    param([string]$UnderDir)
    $recs = @()
    if (-not (Test-Path -LiteralPath $UnderDir)) { return $recs }
    foreach ($f in (Get-ChildItem -LiteralPath $UnderDir -Recurse -Filter 'lw-watchtower.jsonl' -File -ErrorAction SilentlyContinue)) {
        foreach ($l in (Get-Content -LiteralPath $f.FullName)) {
            if ([string]::IsNullOrWhiteSpace($l)) { continue }
            try { $recs += ($l | ConvertFrom-Json) } catch { }
        }
    }
    return $recs
}

# =========================================================================
# SECTION A - #146, CLAUDE_CONFIG_DIR
# =========================================================================

function Test-A1-ClaudeHomeHonoursTheVariable {
    $root = New-PluginTree (Join-Path $script:Work 'a1')
    $cfgDir = New-Dir (Join-Path $script:Work 'a1-config')
    $prof   = New-Dir (Join-Path $script:Work 'a1-profile')

    $probe = New-Probe -Root $root -Name 'probe' -Body @"
    `$o['home']   = (Get-LwgClaudeHome)
    `$i = Get-LwgClaudeHomeInfo
    `$o['source'] = `$i.source
"@
    $r = Invoke-Child -ScriptPath $probe -EnvSet @{ USERPROFILE = $prof; CLAUDE_CONFIG_DIR = $cfgDir }
    $j = Read-Json $r 'the CLAUDE_CONFIG_DIR probe'
    if (-not $j.ok) { Add-Case 'A1 Get-LwgClaudeHome honours CLAUDE_CONFIG_DIR' $false $j.why; return }
    $o = $j.obj
    if ($o.error) {
        Add-Case 'A1 Get-LwgClaudeHome honours CLAUDE_CONFIG_DIR' $false `
            ("REGRESSION (#146): the resolver is not there at all - $($o.error). CLAUDE_CONFIG_DIR is honoured by nothing.")
        return
    }
    $ok = ([string]$o.home -eq $cfgDir) -and ([string]$o.source -eq 'env')
    Add-Case 'A1 Get-LwgClaudeHome honours CLAUDE_CONFIG_DIR' $ok `
        ("expected [$cfgDir] source 'env', got [$($o.home)] source '$($o.source)'")
}

function Test-A2-ClaudeHomeFallsBackToTheProfile {
    $root = New-PluginTree (Join-Path $script:Work 'a2')
    $prof = New-Dir (Join-Path $script:Work 'a2-profile')

    $probe = New-Probe -Root $root -Name 'probe' -Body @"
    `$o['home']   = (Get-LwgClaudeHome)
    `$o['source'] = (Get-LwgClaudeHomeInfo).source
"@
    $r = Invoke-Child -ScriptPath $probe -EnvSet @{ USERPROFILE = $prof; CLAUDE_CONFIG_DIR = $null }
    $j = Read-Json $r 'the unset-variable probe'
    if (-not $j.ok) { Add-Case 'A2 unset CLAUDE_CONFIG_DIR falls back to <profile>\.claude' $false $j.why; return }
    $o = $j.obj
    if ($o.error) { Add-Case 'A2 unset CLAUDE_CONFIG_DIR falls back to <profile>\.claude' $false "REGRESSION (#146): $($o.error)"; return }
    $want = [IO.Path]::Combine($prof, '.claude')
    $ok = ([string]$o.home -eq $want) -and ([string]$o.source -eq 'profile')
    Add-Case 'A2 unset CLAUDE_CONFIG_DIR falls back to <profile>\.claude' $ok `
        ("expected [$want] source 'profile', got [$($o.home)] source '$($o.source)'")
}

function Test-A3-ClaudeHomeSettlesTheThreeAwkwardValues {
    <#
      The three cases #146 asks to be settled AT THE RESOLVER rather than left
      for each caller to get differently wrong: a trailing separator, a relative
      value, and a value naming a directory that does not exist.
    #>
    $root = New-PluginTree (Join-Path $script:Work 'a3')
    $prof = New-Dir (Join-Path $script:Work 'a3-profile')
    $base = New-Dir (Join-Path $script:Work 'a3-config')
    $missing = Join-Path $script:Work 'a3-does-not-exist'

    $probe = New-Probe -Root $root -Name 'probe' -Body @"
    `$o['home'] = (Get-LwgClaudeHome)
    `$i = Get-LwgClaudeHomeInfo
    `$o['source'] = `$i.source
    `$o['exists'] = `$i.exists
"@

    # trailing separator
    $r1 = Invoke-Child -ScriptPath $probe -EnvSet @{ USERPROFILE = $prof; CLAUDE_CONFIG_DIR = ($base + '\') }
    $j1 = Read-Json $r1 'the trailing-separator probe'
    # relative, resolved against the child's working directory
    $r2 = Invoke-Child -ScriptPath $probe -EnvSet @{ USERPROFILE = $prof; CLAUDE_CONFIG_DIR = '.\a3-config' } -WorkDir $script:Work
    $j2 = Read-Json $r2 'the relative-value probe'
    # set, but naming nothing
    $r3 = Invoke-Child -ScriptPath $probe -EnvSet @{ USERPROFILE = $prof; CLAUDE_CONFIG_DIR = $missing }
    $j3 = Read-Json $r3 'the missing-directory probe'

    foreach ($j in @($j1, $j2, $j3)) {
        if (-not $j.ok) { Add-Case 'A3 trailing separator, relative value and missing directory are settled at the resolver' $false $j.why; return }
        if ($j.obj.error) { Add-Case 'A3 trailing separator, relative value and missing directory are settled at the resolver' $false "REGRESSION (#146): $($j.obj.error)"; return }
    }

    $problems = @()
    if ([string]$j1.obj.home -ne $base) { $problems += "trailing separator: expected [$base], got [$($j1.obj.home)]" }
    if ([string]$j2.obj.home -ne $base) { $problems += "relative value: expected [$base], got [$($j2.obj.home)]" }
    if ([string]$j3.obj.home -ne $missing) { $problems += "missing directory: expected it returned AS GIVEN [$missing], got [$($j3.obj.home)]" }
    if ($j3.obj.exists -ne $false) { $problems += "missing directory: exists should be false so the caller can say so, got [$($j3.obj.exists)]" }
    if ([string]$j3.obj.source -ne 'env') { $problems += "missing directory: source should stay 'env' - falling back to the profile is the defect, not the fix - got '$($j3.obj.source)'" }

    Add-Case 'A3 trailing separator, relative value and missing directory are settled at the resolver' ($problems.Count -eq 0) ($problems -join "`n")
}

function Test-A4-PluginDataOutranksConfigDir {
    <#
      PRECEDENCE. CLAUDE_PLUGIN_DATA names the exact directory Claude Code hands
      a hook; CLAUDE_CONFIG_DIR names the tree one would be DERIVED from. The
      more specific signal has to win, or a hook and a non-hook caller on the
      same machine resolve two different ledgers.
    #>
    $root = New-PluginTree (Join-Path $script:Work 'a4')
    $prof = New-Dir (Join-Path $script:Work 'a4-profile')
    $cfgDir = New-Dir (Join-Path $script:Work 'a4-config')
    $data   = New-Dir (Join-Path $script:Work 'a4-data')
    # A candidate under the config dir too, so the case would resolve THERE if
    # the precedence were the other way round rather than merely finding nothing.
    New-Dir ([IO.Path]::Combine($cfgDir, 'plugins\data\lw-watchtower-fixture')) | Out-Null

    $probe = New-Probe -Root $root -Name 'probe' -Body @"
    `$i = Get-LwgStateDirInfo
    `$o['path'] = `$i.path
    `$o['source'] = `$i.source
"@
    $r = Invoke-Child -ScriptPath $probe -EnvSet @{ USERPROFILE = $prof; CLAUDE_CONFIG_DIR = $cfgDir; CLAUDE_PLUGIN_DATA = $data }
    $j = Read-Json $r 'the precedence probe'
    if (-not $j.ok) { Add-Case 'A4 CLAUDE_PLUGIN_DATA outranks CLAUDE_CONFIG_DIR' $false $j.why; return }
    if ($j.obj.error) { Add-Case 'A4 CLAUDE_PLUGIN_DATA outranks CLAUDE_CONFIG_DIR' $false "REGRESSION (#146): $($j.obj.error)"; return }
    $ok = ([string]$j.obj.path -eq $data) -and ([string]$j.obj.source -eq 'env')
    Add-Case 'A4 CLAUDE_PLUGIN_DATA outranks CLAUDE_CONFIG_DIR' $ok `
        ("expected [$data] source 'env', got [$($j.obj.path)] source '$($j.obj.source)'")
}

function Test-A5-SessionStartWritesUnderTheConfigDir {
    <#
      THE END-TO-END CASE, and the one that describes the real failure. The
      REAL SessionStart hook, in a REAL child process, with CLAUDE_PLUGIN_DATA
      cleared - the state every non-hook caller is in - and CLAUDE_CONFIG_DIR
      pointed at a scratch tree that already holds the suffixed data directory
      Claude Code would have created.

      Two assertions, and the second is the one that names the damage: the
      ledger lands under CLAUDE_CONFIG_DIR, and NOTHING is written under the
      profile. Before the fix the second fails - the record goes to
      <profile>\.claude\plugins\data, which on a real machine is the operator's
      own directory.
    #>
    $root   = New-PluginTree (Join-Path $script:Work 'a5')
    $prof   = New-Dir (Join-Path $script:Work 'a5-profile')
    $cfgDir = New-Dir (Join-Path $script:Work 'a5-config')
    $live   = New-Dir ([IO.Path]::Combine($cfgDir, 'plugins\data\lw-watchtower-fixture'))
    # The profile has the same shape, so the case cannot pass merely because the
    # wrong tree was unwritable.
    New-Dir ([IO.Path]::Combine($prof, '.claude\plugins\data\lw-watchtower-fixture')) | Out-Null

    $hook = Join-Path $root 'lib\session_start.ps1'
    $r = Invoke-Child -ScriptPath $hook -Stdin (New-Payload $root) -WorkDir $root `
         -EnvSet @{ USERPROFILE = $prof; CLAUDE_CONFIG_DIR = $cfgDir; CLAUDE_PLUGIN_DATA = $null; CLAUDE_PLUGIN_ROOT = $root }

    $underConfig  = @(Get-LedgerRecords ([IO.Path]::Combine($cfgDir, 'plugins\data')))
    $underProfile = @(Get-LedgerRecords ([IO.Path]::Combine($prof, '.claude')))

    $problems = @()
    if ($r.code -ne 0) { $problems += "the hook exited $($r.code); it must always exit 0. stderr: $($r.err)" }
    if ($underConfig.Count -eq 0) {
        $problems += "no SessionStart record landed under CLAUDE_CONFIG_DIR ($live)"
    }
    if ($underProfile.Count -gt 0) {
        $problems += ("REGRESSION (#146): $($underProfile.Count) record(s) were written under the PROFILE at " +
                      [IO.Path]::Combine($prof, '.claude\plugins\data') +
                      " while CLAUDE_CONFIG_DIR named another tree. On a real machine that is the operator's own .claude directory, written to by an install that reported success.")
    }
    Add-Case 'A5 SessionStart writes its ledger under CLAUDE_CONFIG_DIR and nothing under the profile' ($problems.Count -eq 0) ($problems -join "`n")
}

# =========================================================================
# SECTION B - #60, self_health probe 2
# =========================================================================

function Invoke-SessionStartCase {
    <#
      Run the real hook against a scratch plugin tree carrying $ConfigJson, with
      its own isolated data directory, and hand back the parsed SessionStart
      record plus the hook's own stdout envelope.
    #>
    param([string]$Name, [string]$ConfigJson = '')

    $root = New-PluginTree (Join-Path $script:Work $Name) -ConfigJson $ConfigJson
    $prof = New-Dir (Join-Path $script:Work "$Name-profile")
    $data = New-Dir (Join-Path $script:Work "$Name-data")
    $hook = Join-Path $root 'lib\session_start.ps1'

    $r = Invoke-Child -ScriptPath $hook -Stdin (New-Payload $root) -WorkDir $root `
         -EnvSet @{ USERPROFILE = $prof; CLAUDE_PLUGIN_DATA = $data; CLAUDE_PLUGIN_ROOT = $root }

    $envelope = $null
    try { $envelope = $r.out | ConvertFrom-Json } catch { }
    $recs = @(Get-LedgerRecords $data)
    $rec  = @($recs | Where-Object { $_.event -eq 'SessionStart' })
    return @{
        code     = $r.code
        err      = $r.err
        raw      = $r.out
        envelope = $envelope
        record   = $(if ($rec.Count -gt 0) { $rec[-1] } else { $null })
        records  = $recs
        data     = $data
        root     = $root
    }
}

function Test-B1-AStringValuedModuleFlagDegradesTheSelfCheck {
    $cfg = @'
{
  "version": "0.4.0",
  "modules": { "docs_coupling": "false" },
  "repos": {},
  "thresholds": {
    "ratelimit": { "warn_pct": 88, "land_all_pct": 92 },
    "context":   { "warn_pct": 75, "critical_pct": 90 }
  }
}
'@
    $c = Invoke-SessionStartCase -Name 'b1' -ConfigJson $cfg
    if ($null -eq $c.record) {
        Add-Case 'B1 "docs_coupling": "false" degrades the self-check' $false "no SessionStart record was written. exit $($c.code), stderr: $($c.err)"
        return
    }
    $problems = @()
    if ($c.record.selfcheck.modules_resolved -ne $false) {
        $problems += ('REGRESSION (#60): modules_resolved is [' + $c.record.selfcheck.modules_resolved +
                      ']. "docs_coupling": "false" is what an operator writes when they mean OFF; [bool] on a ' +
                      'non-empty string is $true in PowerShell, so the flag was IGNORED and the module left RUNNING - ' +
                      'and the one probe whose job is "every declared module resolves" reported a pass.')
    }
    if ([string]$c.record.mode -ne 'degraded') {
        $problems += "mode is '$($c.record.mode)', expected 'degraded' - a failed probe must reach the mode word"
    }
    if (($c.record.failures -join ' ') -notmatch 'docs_coupling') {
        $problems += "no failure named docs_coupling: [$($c.record.failures -join '; ')]"
    }
    Add-Case 'B1 "docs_coupling": "false" degrades the self-check' ($problems.Count -eq 0) ($problems -join "`n")
}

function Test-B2-ASwitchBackedFlagIsCheckedToo {
    <#
      delegate_gate has NO `modules` key by design - its flag is
      interaction.delegate. A probe that read only the `modules` block would
      walk straight past the flag that arms the only gate this plugin ships,
      which is the value #60's own worked example turns on.
    #>
    $cfg = @'
{
  "version": "0.4.0",
  "modules": {},
  "interaction": { "delegate": "false" },
  "repos": {},
  "thresholds": {
    "ratelimit": { "warn_pct": 88, "land_all_pct": 92 },
    "context":   { "warn_pct": 75, "critical_pct": 90 }
  }
}
'@
    $c = Invoke-SessionStartCase -Name 'b2' -ConfigJson $cfg
    if ($null -eq $c.record) {
        Add-Case 'B2 a non-boolean at a switch-backed key degrades the self-check' $false "no SessionStart record was written. exit $($c.code), stderr: $($c.err)"
        return
    }
    $problems = @()
    if ($c.record.selfcheck.modules_resolved -ne $false) {
        $problems += ('REGRESSION (#60): modules_resolved is [' + $c.record.selfcheck.modules_resolved +
                      '] for "interaction": { "delegate": "false" } - the key that arms the only gate this plugin ships.')
    }
    if (($c.record.failures -join ' ') -notmatch 'delegate') {
        $problems += "no failure named the delegate flag: [$($c.record.failures -join '; ')]"
    }
    Add-Case 'B2 a non-boolean at a switch-backed key degrades the self-check' ($problems.Count -eq 0) ($problems -join "`n")
}

function Test-B3-JsonNullIsNotABoolean {
    <#
      `"git_hygiene": null` is one of the four malformed shapes #60 names. It
      matters separately from the string case because the obvious repair -
      `if ($null -ne $raw -and $raw -isnot [bool])` - passes it.
    #>
    $cfg = @'
{
  "version": "0.4.0",
  "modules": { "git_hygiene": null },
  "repos": {},
  "thresholds": {
    "ratelimit": { "warn_pct": 88, "land_all_pct": 92 },
    "context":   { "warn_pct": 75, "critical_pct": 90 }
  }
}
'@
    $c = Invoke-SessionStartCase -Name 'b3' -ConfigJson $cfg
    if ($null -eq $c.record) {
        Add-Case 'B3 "git_hygiene": null is not a boolean either' $false "no SessionStart record was written. exit $($c.code), stderr: $($c.err)"
        return
    }
    $ok = ($c.record.selfcheck.modules_resolved -eq $false) -and (($c.record.failures -join ' ') -match 'git_hygiene')
    Add-Case 'B3 "git_hygiene": null is not a boolean either' $ok `
        ("modules_resolved [$($c.record.selfcheck.modules_resolved)], failures [$($c.record.failures -join '; ')]")
}

function Test-B4-TheShippedConfigStillPasses {
    <#
      The other half of #60, and the half a careless fix breaks: a probe that
      can fail must still PASS on the config this repository ships. Without
      this, "make it fail" and "make it always fail" are indistinguishable.
    #>
    $c = Invoke-SessionStartCase -Name 'b4'
    if ($null -eq $c.record) {
        Add-Case 'B4 the shipped config.json still resolves clean' $false "no SessionStart record was written. exit $($c.code), stderr: $($c.err)"
        return
    }
    $problems = @()
    if ($c.record.selfcheck.modules_resolved -ne $true) {
        $problems += "modules_resolved is [$($c.record.selfcheck.modules_resolved)] on the SHIPPED config.json - failures: [$($c.record.failures -join '; ')]"
    }
    if ([string]$c.record.mode -eq 'degraded') {
        $problems += "mode is 'degraded' on the shipped config.json: [$($c.record.failures -join '; ')]"
    }
    Add-Case 'B4 the shipped config.json still resolves clean' ($problems.Count -eq 0) ($problems -join "`n")
}

# =========================================================================
# SECTION C - #106, the unbounded probe file
# =========================================================================

function Test-C1-SelfcheckProbeDoesNotGrow {
    $root = New-PluginTree (Join-Path $script:Work 'c1')
    $prof = New-Dir (Join-Path $script:Work 'c1-profile')
    $data = New-Dir (Join-Path $script:Work 'c1-data')
    $hook = Join-Path $root 'lib\session_start.ps1'

    $states = @()
    for ($i = 0; $i -lt 3; $i++) {
        $r = Invoke-Child -ScriptPath $hook -Stdin (New-Payload $root) -WorkDir $root `
             -EnvSet @{ USERPROFILE = $prof; CLAUDE_PLUGIN_DATA = $data; CLAUDE_PLUGIN_ROOT = $root }
        $states += $r.code
    }

    $probeFile = Join-Path $data 'selfcheck.probe'
    $problems = @()
    if (-not (Test-Path -LiteralPath $probeFile)) {
        $problems += "no selfcheck.probe was written at all, so the state-writable probe proved nothing"
    } else {
        $lines = @(Get-Content -LiteralPath $probeFile | Where-Object { $_ -ne '' })
        if ($lines.Count -ne 1) {
            $problems += ("REGRESSION (#106): selfcheck.probe holds $($lines.Count) line(s) after 3 SessionStart events. " +
                          "It is appended to on every start, resume, clear and compact and nothing in the tree ever " +
                          "rotates, truncates or READS it - the only file this plugin writes with no bound at all, " +
                          "inside a plugin whose log_rotation module reports itself as capping the logs.")
        }
    }
    # The probe's observable contract is unchanged: it still proves the dir is writable.
    $recs = @(Get-LedgerRecords $data | Where-Object { $_.event -eq 'SessionStart' })
    if ($recs.Count -eq 0) { $problems += 'no SessionStart record was written' }
    else {
        foreach ($rec in $recs) {
            if ($rec.selfcheck.state_writable -ne $true) { $problems += "state_writable is [$($rec.selfcheck.state_writable)] - the probe must still prove what it claims" }
        }
    }
    Add-Case 'C1 selfcheck.probe holds one line after three SessionStart events, and still proves the dir writable' ($problems.Count -eq 0) ($problems -join "`n")
}

# =========================================================================
# SECTION D - #8, where a marketplace install actually lives
# =========================================================================

function Invoke-MarketplaceProbe {
    param([string]$Name, [string]$ClaudeHome)
    $root = New-PluginTree (Join-Path $script:Work $Name)
    $prof = New-Dir (Join-Path $script:Work "$Name-profile")
    $probe = New-Probe -Root $root -Name 'probe' -Body @"
    `$i = Get-LwgMarketplaceInstall
    `$o['installed'] = `$i.installed
    `$o['source']    = `$i.source
    `$o['paths']     = @(`$i.paths)
    `$o['scopes']    = @(`$i.scopes)
    `$o['probed']    = @(`$i.probed)
"@
    $r = Invoke-Child -ScriptPath $probe -EnvSet @{ USERPROFILE = $prof; CLAUDE_CONFIG_DIR = $ClaudeHome }
    return (Read-Json $r "the marketplace probe ($Name)")
}

function Test-D1-InstalledPluginsJsonIsRead {
    $home_ = New-Dir (Join-Path $script:Work 'd1-home')
    $inst  = New-Dir ([IO.Path]::Combine($home_, 'plugins\cache\OZ-Marketplace\lw-watchtower\0.4.0'))
    New-Dir ([IO.Path]::Combine($inst, '.claude-plugin')) | Out-Null
    # THE REAL SHAPE, read off a live install rather than guessed: a schema
    # `version` beside a `plugins` map, NOT a flat map of `<plugin>@<marketplace>`
    # keys at the top level. A resolver reading the top level as the map matches
    # nothing here and falls silently through to the cache walk, which still
    # reports installed = $true - so a fixture with the flat shape would pass a
    # resolver that is wrong on every real machine.
    $j = @{
        version = 2
        plugins = @{
            'lw-watchtower@OZ-Marketplace' = @(
                @{ scope = 'user'; installPath = $inst; version = '0.4.0' }
            )
            'static-analysis@trailofbits' = @(
                @{ scope = 'project'; projectPath = 'C:\somewhere\else'
                   installPath = ([IO.Path]::Combine($home_, 'plugins\cache\trailofbits\static-analysis\1.2.1')); version = '1.2.1' }
            )
        }
    } | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText([IO.Path]::Combine($home_, 'plugins\installed_plugins.json'), $j, [Text.UTF8Encoding]::new($false))

    $res = Invoke-MarketplaceProbe -Name 'd1' -ClaudeHome $home_
    if (-not $res.ok) { Add-Case 'D1 installed_plugins.json names the resolved installPath' $false $res.why; return }
    $o = $res.obj
    if ($o.error) {
        Add-Case 'D1 installed_plugins.json names the resolved installPath' $false `
            ("REGRESSION (#8): there is no shared marketplace resolver - $($o.error). The constant was spelled twice, " +
             "in bin\lwg-setup.ps1 and statusline\statusline.ps1, and was wrong in both.")
        return
    }
    $problems = @()
    if ($o.installed -ne $true)                  { $problems += "installed is [$($o.installed)], expected true" }
    if ([string]$o.source -ne 'installed_plugins') { $problems += "source is '$($o.source)', expected 'installed_plugins' - the CLI's own record is the strongest answer available" }
    if (@($o.paths) -notcontains $inst)          { $problems += "paths [$(@($o.paths) -join '; ')] does not carry the recorded installPath [$inst]" }
    # The scope is half of what makes this record worth reading rather than the
    # cache walk: it is what distinguishes a project-scoped install from a
    # user-scoped one, and it exists nowhere on disk except here.
    if (@($o.scopes) -notcontains 'user')        { $problems += "scopes [$(@($o.scopes) -join '; ')] does not carry the recorded scope 'user'" }
    if (@($o.paths).Count -ne 1)                 { $problems += "paths carries $(@($o.paths).Count) entr(ies); the other plugin in the fixture must not be matched" }
    Add-Case 'D1 installed_plugins.json names the resolved installPath' ($problems.Count -eq 0) ($problems -join "`n")
}

function Test-D2-TheCacheLayoutIsWalked {
    <#
      The fallback when installed_plugins.json is absent or unreadable. The
      nesting is cache\<marketplace>\<plugin>\<version>\ - THREE levels below
      cache, not one below a `repos` directory that does not exist.
    #>
    $home_ = New-Dir (Join-Path $script:Work 'd2-home')
    $inst  = New-Dir ([IO.Path]::Combine($home_, 'plugins\cache\OZ-Marketplace\lw-watchtower\655b7d9c5431'))
    New-Dir ([IO.Path]::Combine($home_, 'plugins\cache\caveman\caveman\655b7d9c5431')) | Out-Null

    $res = Invoke-MarketplaceProbe -Name 'd2' -ClaudeHome $home_
    if (-not $res.ok) { Add-Case 'D2 the cache\<marketplace>\<plugin>\<version> layout is walked' $false $res.why; return }
    $o = $res.obj
    if ($o.error) { Add-Case 'D2 the cache\<marketplace>\<plugin>\<version> layout is walked' $false "REGRESSION (#8): $($o.error)"; return }
    $problems = @()
    if ($o.installed -ne $true)     { $problems += "installed is [$($o.installed)], expected true" }
    if ([string]$o.source -ne 'cache') { $problems += "source is '$($o.source)', expected 'cache'" }
    if (@($o.paths) -notcontains $inst) { $problems += "paths [$(@($o.paths) -join '; ')] does not carry [$inst]" }
    # It must match on the PLUGIN NAME, not count any directory under cache.
    if (@($o.paths) -match 'caveman') { $problems += "the walk matched another marketplace's plugin: [$(@($o.paths) -join '; ')]" }
    Add-Case 'D2 the cache\<marketplace>\<plugin>\<version> layout is walked' ($problems.Count -eq 0) ($problems -join "`n")
}

function Test-D3-AbsenceIsReportedAsAbsenceAndNotAsRepos {
    $home_ = New-Dir (Join-Path $script:Work 'd3-home')
    New-Dir ([IO.Path]::Combine($home_, 'plugins\cache')) | Out-Null

    $res = Invoke-MarketplaceProbe -Name 'd3' -ClaudeHome $home_
    if (-not $res.ok) { Add-Case 'D3 no marketplace install is reported as none, and plugins\repos is never probed' $false $res.why; return }
    $o = $res.obj
    if ($o.error) { Add-Case 'D3 no marketplace install is reported as none, and plugins\repos is never probed' $false "REGRESSION (#8): $($o.error)"; return }
    $problems = @()
    if ($o.installed -ne $false)  { $problems += "installed is [$($o.installed)], expected false" }
    if (@($o.paths).Count -ne 0)  { $problems += "paths is not empty: [$(@($o.paths) -join '; ')]" }
    if (@($o.probed).Count -eq 0) { $problems += 'probed is empty - a resolver that cannot say WHERE it looked cannot be distinguished from one that did not look' }
    foreach ($p in @($o.probed)) {
        if ([string]$p -match '(?i)plugins\\repos') {
            $problems += "REGRESSION (#8): it still probes [$p]. That directory does not exist on a live Claude Code install; marketplace installs live under plugins\cache\<marketplace>\<plugin>\<version>."
        }
    }
    Add-Case 'D3 no marketplace install is reported as none, and plugins\repos is never probed' ($problems.Count -eq 0) ($problems -join "`n")
}

# =========================================================================

Say ''
Say 'LW-WATCHTOWER state-resolution and platform suite'
Say '  A #146 CLAUDE_CONFIG_DIR   B #60 probe 2   C #106 selfcheck.probe'
Say '  D #8 marketplace layout'
Say ''

try {
    if (-not (Test-Path -LiteralPath (Join-Path $script:RepoRoot 'lib\common.ps1'))) {
        Abort-Suite "this file must sit in tests\ beside the repository it tests; lib\common.ps1 is not under $($script:RepoRoot)"
    }
    $script:Work = Join-Path ([IO.Path]::GetTempPath()) ("lwg-state-" + [guid]::NewGuid().ToString('N'))
    New-Dir $script:Work | Out-Null

    # The cases are DISCOVERED rather than listed. A second list of them is a
    # second thing to keep correct, and the failure mode of a case that is
    # written and never called is a suite that reports a clean pass over
    # coverage it does not have - the founding defect this repository exists to
    # catch, in its own test harness. Sorting on the name gives A1..A5, B1..B4,
    # C1, D1..D3, E1..E3, so section order is a property of the naming.
    $cases = @(Get-ChildItem function:\ | Where-Object { $_.Name -match '^Test-[A-Z]\d+-' } | Sort-Object Name)
    if ($cases.Count -eq 0) { Abort-Suite 'no case functions were discovered - the harness is broken, not the tree.' }
    foreach ($c in $cases) { & $c.Name }
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
# THE RESULT: AND EXIT: TOKENS ARE A CONTRACT, NOT DECORATION, and the literal
# `case(s)` is load-bearing: tests\doc_claims.ps1 decides which suites are
# BEHAVIOURAL by matching `N of M case(s)` in each suite's own output rather
# than from a list it is told.
if ($script:Aborted) {
    Write-Output "ABORTED: $($script:Aborted)"
    Write-Output "RESULT: $script:Pass of $total case(s) had run when it stopped. Nothing about state resolution was established."
    Write-Output 'EXIT: 2 (the resolvers were NOT exercised, which is not the same as passing)'
    exit 2
}
if ($total -eq 0) {
    Write-Output 'ABORTED: no case ran. An empty set is not a pass.'
    Write-Output 'RESULT: no case ran, so nothing about state resolution was established'
    Write-Output 'EXIT: 2 (zero cases run is an abort, never an empty-set pass)'
    exit 2
}
Write-Output ("RESULT: {0} of {1} case(s) passed." -f $script:Pass, $total)
if ($failed -gt 0) {
    Write-Output "$failed case(s) FAILED."
    Write-Output 'EXIT: 1 (at least one case failed - read the per-case lines above. A case reporting'
    Write-Output '         a record written under the PROFILE while CLAUDE_CONFIG_DIR named another'
    Write-Output '         tree means an install that reported success wrote into the operator''s own'
    Write-Output '         .claude directory.)'
    exit 1
}
# The sections that RAN are read off the results rather than spelled out here,
# so this line cannot claim coverage the file does not carry.
$ran = @($script:Results | ForEach-Object { $_.Name.Substring(0, 1) } | Select-Object -Unique | Sort-Object)
Write-Output ("EXIT: 0 (every case passed, across section(s) " + ($ran -join ', ') + " - the header says what each one pins)")
exit 0
