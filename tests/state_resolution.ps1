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

  THE ONE IT PINS

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

Say ''
Say 'LW-WATCHTOWER state-resolution and platform suite'
Say '  A #146 CLAUDE_CONFIG_DIR'
Say ''
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
