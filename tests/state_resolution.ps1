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
  pins - and, since sections F and G were added, around the surfaces of that
  hook which running it three times still left unasserted.

  EXECUTION IS NOT COVERAGE, and sections F and G exist because of it. When this
  file landed, #177's headline claim - "lib\session_start.ps1 is executed by no
  test" - stopped being true, and the issue was deliberately NOT closed on that:
  the hook was being run nine times by a suite that read two of its five
  self-check probes, one of its six mode words, and nothing at all off the
  envelope it prints. A file can be run repeatedly by cases that assert nothing
  about the branches that matter. Sections F and G are the rest of it: the four
  probes with no assertion anywhere in tests\, the five mode words section B
  left unpinned, the banner (#144) and the additionalContext envelope.

  THE FIVE IT PINS

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

    #132 nothing checked the operating system or the Claude Code build, and the
         module registry recorded no dependency between a module and the hook
         events it needs, so nothing could even ask the question. Section E.

  AND THE TWO COVERAGE GAPS, which are not defects in the tree but absences in
  this file, and are marked as such because a green run over them says only that
  the behaviour is now WATCHED:

    #177 the probes config_from_file, thresholds_live, payload_session and
         payload_cwd had zero hits across all of tests\, and the mode ladder had
         one of its six words asserted. Section F.

    #144 the SessionStart banner was asserted by nothing. A silent banner, a
         blank one, or any of the three self-reported failure strings the file
         can emit would have failed no build. Section G, with the envelope.

  AND THE THREE ADDED ON 4 SEPTEMBER 2026, all found by driving the shipped
  default install rather than by reading it:

    #268 Get-LwgConfig tested `$null -ne $cfg.modules` to decide whether
         config.json was a config at all, and $false is not $null - so
         {"modules":false} was accepted as a good one, the operator's override
         was merged over it and the blocking gate came up ARMED off seventeen
         bytes. Section I asserts on the banner's gate count, because the
         consequence that matters is a lockout.

    #266 the model-visible context printed its remainder count TWICE - "The
         other 4: 4 (...)" - on the shipped configuration, because the label
         states the total and the single clause under it opens with its own
         count. G5 could not catch it: G5 asserts the four are NAMED, and they
         were. Case G8.

    #269 every hook decoded its stdin through [Console]::In, whose encoding is
         the CONSOLE's input code page and not the payload's, so one non-ASCII
         character anywhere in cwd was mojibaked into the audit trail and made
         `repo` resolve to null. Section H, and see its header for why the
         assertion is on the ledger rather than on the hook's stdout.

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

# THE NAME IS $PayloadRoot AND NOT $RepoRoot, because every path composed off
# it below is a PAYLOAD path - lib\, .claude-plugin\, config.json, hooks\hooks.json
# - and the payload moved under lw-watchtower/ while tests\ stayed at the
# repository root. A variable called RepoRoot pointing at a subdirectory of the
# repository is a name that lies to the next reader, and this suite has enough
# roots in it already.
$script:PayloadRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'lw-watchtower'

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

      -NoConsoleWindow SETS CreateNoWindow, WHICH IS NOT COSMETIC HERE. Claude
      Code is a Node host and spawns every hook with `windowsHide: true`, i.e.
      CREATE_NO_WINDOW, so the child gets its OWN console at the system's OEM
      code page instead of inheriting the terminal's. That decides
      [Console]::InputEncoding inside the child, and therefore what
      [Console]::In makes of a UTF-8 payload. Without this switch a child
      inherits whatever the suite is running under, so a developer whose
      terminal happens to sit at 65001 would run H1 against an encoding the
      product never sees and read a vacuous pass as coverage. Measured on this
      machine: inherited console 65001 -> the payload decodes correctly;
      CreateNoWindow -> IBM437, and every non-ASCII byte is mojibaked.
    #>
    param(
        [string]$ScriptPath,
        [hashtable]$EnvSet = @{},
        [string]$Stdin = '',
        [string]$WorkDir = '',
        [switch]$NoConsoleWindow
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
    $psi.CreateNoWindow         = [bool]$NoConsoleWindow
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
    Copy-Item -LiteralPath (Join-Path $script:PayloadRoot 'lib') -Destination (Join-Path $Root 'lib') -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $script:PayloadRoot '.claude-plugin') -Destination (Join-Path $Root '.claude-plugin') -Recurse -Force
    # IsNullOrEmpty and not `$null -eq`: a [string] parameter defaulted to $null
    # binds as '', so the $null test never fires and every case that meant "the
    # SHIPPED config" would silently get an EMPTY one - which Get-LwgConfig
    # correctly reads as unparseable and replaces with the built-in defaults.
    # The control case would then have failed for a reason not in the tree.
    if ([string]::IsNullOrEmpty($ConfigJson)) {
        Copy-Item -LiteralPath (Join-Path $script:PayloadRoot 'config.json') -Destination (Join-Path $Root 'config.json') -Force
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
    <#
      Every lw-watchtower.jsonl record under a directory tree, parsed.

      READ AS UTF-8 EXPLICITLY, and it used to be Get-Content with no -Encoding.
      lib/common.ps1's Add-LwgLine writes these files through
      [IO.File]::AppendAllText with a UTF8Encoding($false) - no BOM - and
      Windows PowerShell 5.1's Get-Content reads a BOM-less file at the system
      ANSI code page. Every record this suite had ever read was pure ASCII, so
      the two agreed and nothing showed; the moment a case put a non-ASCII cwd
      in the ledger (H1) the reader turned it into CP1252 mojibake and reported
      the PRODUCT as broken while the product was correct. A harness that
      mis-decodes the evidence cannot tell a fixed defect from a live one, in
      either direction - it is the same defect as #269 one layer out, and it was
      found by fixing #269.
    #>
    param([string]$UnderDir)
    $recs = @()
    if (-not (Test-Path -LiteralPath $UnderDir)) { return $recs }
    foreach ($f in (Get-ChildItem -LiteralPath $UnderDir -Recurse -Filter 'lw-watchtower.jsonl' -File -ErrorAction SilentlyContinue)) {
        foreach ($l in ([IO.File]::ReadAllLines($f.FullName, [Text.UTF8Encoding]::new($false)))) {
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

      -PayloadJson OVERRIDES the stdin the hook is given. It defaults to empty,
      which keeps New-Payload's well-formed record, so every case written before
      it existed is unchanged. Sections F and G need it because two of the five
      self-check probes read the PAYLOAD - payload_session and payload_cwd - and
      a helper that can only ever hand over a complete one cannot make either of
      them fail. An empty string is not usable as "no payload": Invoke-Child
      would write zero bytes and the difference between that and a payload
      carrying neither key is a difference in what is being tested, so the case
      passes the object it means.
    #>
    param([string]$Name, [string]$ConfigJson = '', [string]$PayloadJson = '', [string]$OverrideJson = '',
          [switch]$NoConsoleWindow)

    $root = New-PluginTree (Join-Path $script:Work $Name) -ConfigJson $ConfigJson
    $prof = New-Dir (Join-Path $script:Work "$Name-profile")
    $data = New-Dir (Join-Path $script:Work "$Name-data")
    $hook = Join-Path $root 'lib\session_start.ps1'

    # -OverrideJson seeds config.override.json in the state directory, which is
    # where the configuring commands write and what Get-LwgConfig merges over
    # the shipped defaults. Section I needs it: the question there is whether a
    # config.json that is not a config can have an OPERATOR OVERRIDE merged onto
    # it, and that is not askable without one on disk.
    if (-not [string]::IsNullOrEmpty($OverrideJson)) {
        [IO.File]::WriteAllText([IO.Path]::Combine($data, 'config.override.json'), $OverrideJson, [Text.UTF8Encoding]::new($false))
    }

    $stdin = $(if ([string]::IsNullOrEmpty($PayloadJson)) { New-Payload $root } else { $PayloadJson })
    $r = Invoke-Child -ScriptPath $hook -Stdin $stdin -WorkDir $root -NoConsoleWindow:$NoConsoleWindow `
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

      THE `modules` BLOCK CARRIES ONE KEY AND IT USED TO BE EMPTY (#268). This
      case is about a non-boolean at a SWITCH-BACKED key, and `modules` was `{}`
      only because it was not the subject. Since #268 an empty `modules` object
      is not a config Get-LwgConfig will merge an override onto - a destroyed
      file wearing the right brackets - so `{}` here would have made this case
      test the config-shape boundary instead of the probe. One real declaration
      moves it back off that boundary and changes nothing it asserts. The
      boundary itself is pinned by its own cases in tests/config_behaviour.ps1.
    #>
    $cfg = @'
{
  "version": "0.4.0",
  "modules": { "git_hygiene": true },
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
# SECTION E - #132, the platform and the hook events
# =========================================================================

function Test-E1-TheSessionRecordNamesItsPlatform {
    $c = Invoke-SessionStartCase -Name 'e1'
    if ($null -eq $c.record) {
        Add-Case 'E1 the SessionStart record names the platform it ran on' $false "no SessionStart record was written. exit $($c.code), stderr: $($c.err)"
        return
    }
    $plat = $c.record.platform
    $problems = @()
    if ($null -eq $plat) {
        $problems += ('REGRESSION (#132): the record carries no platform at all. Nothing in this plugin checked the ' +
                      'operating system or the Claude Code build, so a session on a machine the hook events were ' +
                      'never read out of leaves no evidence of what it ran on.')
    } else {
        if ([string]::IsNullOrWhiteSpace([string]$plat.os))          { $problems += 'platform.os is empty' }
        if ($plat.supported -isnot [bool])                            { $problems += "platform.supported is [$($plat.supported)], expected a real boolean" }
        if ([string]::IsNullOrWhiteSpace([string]$plat.ps_version))   { $problems += 'platform.ps_version is empty' }
        if (-not ($c.record.PSObject.Properties['platform']))         { $problems += 'platform is not a member of the record' }
        # The build the events were read out of has to be recorded somewhere a
        # machine can read, not only in a table cell on the install page.
        if ([string]::IsNullOrWhiteSpace([string]$plat.verified_build)) {
            $problems += 'platform.verified_build is empty - the Claude Code build the hook events were read out of is stated in prose on docs/install.md and nowhere a check can reach'
        }
    }
    Add-Case 'E1 the SessionStart record names the platform it ran on' ($problems.Count -eq 0) ($problems -join "`n")
}

function Test-E2-TheRegistryDeclaresItsHookEvents {
    <#
      #132's core: three of the eight events this plugin registers on were read
      out of one specific binary, and NOTHING relates a module to the events it
      needs - so nothing can say which modules go inert on a build that lacks
      them. The map has to exist before any check can use it, and it has to
      agree with hooks/hooks.json or it is a second thing to keep correct.
    #>
    $probeRoot = New-PluginTree (Join-Path $script:Work 'e2')
    $prof = New-Dir (Join-Path $script:Work 'e2-profile')
    $data = New-Dir (Join-Path $script:Work 'e2-data')
    $probe = New-Probe -Root $probeRoot -Name 'probe' -Body @"
    `$m = [ordered]@{}
    foreach (`$k in `$script:LwgModuleRegistry.Keys) {
        `$m[`$k] = @(`$script:LwgModuleRegistry[`$k].events)
    }
    `$o['events'] = `$m
    `$o['implemented'] = @(Get-LwgImplementedModules)
"@
    $r = Invoke-Child -ScriptPath $probe -EnvSet @{ USERPROFILE = $prof; CLAUDE_PLUGIN_DATA = $data }
    $j = Read-Json $r 'the registry-events probe'
    if (-not $j.ok) { Add-Case 'E2 every implemented module declares the hook events it depends on, and every one is registered' $false $j.why; return }
    if ($j.obj.error) { Add-Case 'E2 every implemented module declares the hook events it depends on, and every one is registered' $false "REGRESSION (#132): $($j.obj.error)"; return }

    $hooksPath = Join-Path $script:PayloadRoot 'hooks\hooks.json'
    if (-not (Test-Path -LiteralPath $hooksPath)) { Abort-Suite "missing $hooksPath" }
    $registered = @((Get-Content -Raw -LiteralPath $hooksPath | ConvertFrom-Json).hooks.PSObject.Properties.Name)
    if ($registered.Count -eq 0) { Abort-Suite 'hooks/hooks.json registers no events - the parse is broken, not the tree.' }

    $problems = @()
    foreach ($m in @($j.obj.implemented)) {
        # An absent `events` field round-trips through @() and JSON as a
        # one-element array holding $null, so emptiness is tested on the
        # CONTENT rather than on the count.
        $declared = @($j.obj.events.$m | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($declared.Count -eq 0) {
            $problems += ("REGRESSION (#132): '$m' is implemented and declares no hook events, so nothing can tell " +
                          'whether the build it is running on carries the events it needs.')
            continue
        }
        foreach ($e in $declared) {
            if ($registered -notcontains $e) {
                $problems += "'$m' declares event '$e', which hooks/hooks.json does not register - the map has drifted from the registrations"
            }
        }
    }
    Add-Case 'E2 every implemented module declares the hook events it depends on, and every one is registered' ($problems.Count -eq 0) ($problems -join "`n")
}

function Test-E3-ThePlatformAnswerHasOneHome {
    <#
      One resolver, so bin\lwg-doctor.ps1's platform and build rows - which are
      #132's suggested fixes 1 and 3, and which live in a file this batch does
      not own - are built on the same answer the hook records rather than on a
      second copy of it.
    #>
    $root = New-PluginTree (Join-Path $script:Work 'e3')
    $prof = New-Dir (Join-Path $script:Work 'e3-profile')
    $data = New-Dir (Join-Path $script:Work 'e3-data')
    $probe = New-Probe -Root $root -Name 'probe' -Body @"
    `$p = Get-LwgPlatformInfo
    `$o['os']             = `$p.os
    `$o['supported']      = `$p.supported
    `$o['is_bool']        = (`$p.supported -is [bool])
    `$o['ps_version']     = `$p.ps_version
    `$o['verified_build'] = `$p.verified_build
    `$o['claude_version'] = `$p.claude_version
"@
    $r = Invoke-Child -ScriptPath $probe -EnvSet @{ USERPROFILE = $prof; CLAUDE_PLUGIN_DATA = $data; CLAUDE_CODE_VERSION = '2.0.9' }
    $j = Read-Json $r 'the platform probe'
    if (-not $j.ok) { Add-Case 'E3 the OS and the Claude Code build have one resolver' $false $j.why; return }
    $o = $j.obj
    if ($o.error) {
        Add-Case 'E3 the OS and the Claude Code build have one resolver' $false `
            ("REGRESSION (#132): $($o.error). A repository-wide search for IsWindows, OSVersion.Platform, " +
             "'claude --version' and CLAUDE_CODE_VERSION across bin\, lib\ and statusline\ returned nothing.")
        return
    }
    $problems = @()
    if ($o.is_bool -ne $true)                     { $problems += "supported is not a [bool]: [$($o.supported)]" }
    if ([string]::IsNullOrWhiteSpace([string]$o.os)) { $problems += 'os is empty' }
    if ([string]$o.verified_build -ne '2.1.220')  { $problems += "verified_build is '$($o.verified_build)', expected the 2.1.220 build docs/install.md names as the one the events were read out of" }
    if ([string]$o.claude_version -ne '2.0.9')    { $problems += "claude_version is '$($o.claude_version)' - CLAUDE_CODE_VERSION was set to 2.0.9 in the child and must be read rather than guessed at" }
    if ([string]::IsNullOrWhiteSpace([string]$o.ps_version)) { $problems += 'ps_version is empty' }
    Add-Case 'E3 the OS and the Claude Code build have one resolver' ($problems.Count -eq 0) ($problems -join "`n")
}

function Test-E4-NoRegistryNoteContradictsTheRegistrysOwnGateCount {
    <#
      #249. $LwgModuleRegistry is this project's single source of truth for the
      module list: bin\lwg-doctor.ps1 reads it, the SessionStart banner reads
      it, and every page under docs\ is written from it. Its note for
      delegate_gate opened "THE ONLY GATE THIS PLUGIN SHIPS" while three
      entries in the same hashtable declared kind = 'gate', and that is the
      drift the single-source arrangement exists to prevent. It propagated
      exactly as you would expect - docs\modules.md, docs\architecture.md and
      docs\gates-removed.md all said "the one gate" because this note said it.

      THIS IS NOT A STRING PIN AND IT IS NOT A SELF-COMPARISON. Both halves
      come out of the registry and they are DIFFERENT FIELDS: the count is
      taken from `kind`, the claim is read out of the prose in `note`. So
      rewording the sentence around the same claim does not get past it, and
      adding a fourth gate without touching any note cannot break it.

      RED AT 09b20be, where delegate_gate's note opens "THE ONLY GATE THIS
      PLUGIN SHIPS" and three entries in the same table declare kind = 'gate':
      32 of 33, this case the only failure.

      WHAT IT DOES NOT CATCH, said rather than left to be found: a note that
      asserts exclusivity in words this pattern does not spell. The pattern is
      the four English shapes for "there is one of these" next to the word
      gate; a note that says it some fifth way is not caught. That is the
      honest limit of matching prose, and it is still the class rather than the
      one sentence #249 was filed about.
    #>
    $probeRoot = New-PluginTree (Join-Path $script:Work 'e4')
    $prof = New-Dir (Join-Path $script:Work 'e4-profile')
    $data = New-Dir (Join-Path $script:Work 'e4-data')
    $probe = New-Probe -Root $probeRoot -Name 'probe' -Body @"
    `$m = [ordered]@{}
    foreach (`$k in `$script:LwgModuleRegistry.Keys) {
        `$m[`$k] = [ordered]@{
            kind = [string]`$script:LwgModuleRegistry[`$k].kind
            note = [string]`$script:LwgModuleRegistry[`$k].note
        }
    }
    `$o['registry'] = `$m
"@
    $name = 'E4 no registry note claims an exclusivity the registry''s own kind field contradicts (#249)'
    $r = Invoke-Child -ScriptPath $probe -EnvSet @{ USERPROFILE = $prof; CLAUDE_PLUGIN_DATA = $data }
    $j = Read-Json $r 'the registry-note probe'
    if (-not $j.ok) { Add-Case $name $false $j.why; return }
    if ($j.obj.error) { Add-Case $name $false "REGRESSION (#249): $($j.obj.error)"; return }

    $entries = @()
    foreach ($p in $j.obj.registry.PSObject.Properties) {
        $entries += [pscustomobject]@{
            name = $p.Name
            kind = [string]$p.Value.kind
            note = [string]$p.Value.note
        }
    }

    # THE FLOOR, and it is the whole reason this case is not vacuous. A probe
    # that returned an empty table, or a registry whose notes were all blank,
    # would satisfy "no note claims exclusivity" without reading anything. Both
    # are asserted before the claim is, so the case fails loudly rather than
    # passing on an absence.
    $noted = @($entries | Where-Object { -not [string]::IsNullOrWhiteSpace($_.note) })
    if ($entries.Count -lt 2 -or $noted.Count -lt 1) {
        Add-Case $name $false ("the registry probe returned {0} entr(ies), {1} of them carrying a note - too few to have read the table at all, so nothing about its prose was established" -f $entries.Count, $noted.Count)
        return
    }

    $gates = @($entries | Where-Object { $_.kind -eq 'gate' })
    # The four English shapes for "there is one of these", beside the word the
    # count is over. Matched against `note`; counted from `kind`.
    $claim = '(?i)\b(?:only|sole|single)\s+gate\b|\bthe\s+one\s+gate\b|\bgate\s+(?:that\s+)?this\s+plugin\s+ships\b'

    $offenders = @()
    foreach ($e in $noted) {
        $m = [regex]::Match($e.note, $claim)
        if ($m.Success) {
            $offenders += ("{0}'s note claims exclusivity - it says [{1}] - and {2} entr(ies) in the same table declare kind = 'gate': {3}" -f `
                $e.name, $m.Value, $gates.Count, (($gates | ForEach-Object { $_.name }) -join ', '))
        }
    }

    # One gate and a note saying so is not a contradiction, and this case must
    # not pretend otherwise: the assertion is only owed when the count exceeds
    # one. The count is printed either way so a run that stopped being able to
    # fail says so in its own output rather than going quietly green.
    $ok = ($gates.Count -le 1) -or ($offenders.Count -eq 0)
    $why = if ($gates.Count -le 1) {
        ("{0} entr(ies) declare kind = 'gate', so an exclusivity claim would be TRUE and nothing is asserted about the notes. This case is dormant, not passing." -f $gates.Count)
    } else {
        ($offenders -join "`n")
    }
    Add-Case $name $ok $why
}

# =========================================================================
# SECTION F - #177, the four unasserted probes and the mode ladder
#
# #177's headline - "lib\session_start.ps1 is executed by no test" - stopped
# being true when this file landed, and the re-scoping comment on that issue is
# the reason it stayed open anyway: EXECUTION IS NOT COVERAGE. Sections A, B and
# C run the hook nine times between them and assert two of its five self-check
# probes and one of the six words its mode ladder can produce. The rest was run
# and looked at by nothing.
#
# WHAT THIS SECTION ADDS, and it is the list the issue was re-scoped to:
#
#   the probes config_from_file, thresholds_live, payload_session and
#   payload_cwd, none of which appeared anywhere in tests\ - F1 asserts all four
#   are recorded and true on the config this repository ships, and F2, F3 and F4
#   each drive ONE of them false from a different direction, so a probe that
#   answered a constant would be caught by whichever case it disagreed with.
#
#   the mode ladder. Get-LwgSessionMode has six answers and section B pinned one
#   of them, 'degraded'. F5 to F9 pin the other five - observe-only, unverified,
#   partial, enforcing, inert - each from a config that makes that answer the
#   only correct one, and each asserting the word in the LEDGER RECORD and in
#   the BANNER, because a ladder that resolved correctly and printed something
#   else would be the same lie one step later. #177 names four of these five;
#   'inert' is here because the ladder is a total function over the same three
#   inputs and leaving one answer unpinned is how the next one drifts.
#
# THE FIXTURE CONFIGS ARE WRITTEN OUT IN FULL rather than patched from the
# shipped one, because the counts each case asserts are read off the config it
# was given. A fixture that inherited anything would make those numbers a
# statement about config.json instead of about the ladder.
#
# THE COUNTS ARE CONCRETE - 7/11, 11/11, 0 gates, 3 gates - and not recomputed
# from the registry inside the case. Deriving them here would mean the case and
# the code under test share a mistake; a registry change that moves them is
# meant to bring this file with it, and that is the test working rather than
# failing.
# =========================================================================

# The three self-reported failure banners lib\session_start.ps1 can emit, by the
# fragment of each that is stable under a version bump. Located by reading the
# file, not by line number - #144's own comments record all three line numbers
# moving once already.
$script:BannerFailures = @(
    'startup failed, see log'          # the initial value, still standing if the try block never completed
    '(governance not loaded)'          # the catch block
    'output serialisation failed'      # the last-resort hand-built envelope
)

function Get-BannerFailure {
    <# Which of the three failure banners this text is, or '' for none. #>
    param([string]$Banner)
    foreach ($f in $script:BannerFailures) { if ([string]$Banner -like "*$f*") { return $f } }
    return ''
}

function Test-BannerMode {
    <#
      Does the banner end on this mode word? The word is the LAST thing on the
      line except for an optional parenthetical, so anchoring on that is what
      separates "the banner names the mode" from "the mode word appears
      somewhere in the banner", which a module name could satisfy.
    #>
    param([string]$Banner, [string]$Mode)
    return ([string]$Banner -match ([regex]::Escape($Mode) + '\s*(\(|$)'))
}

function Invoke-ModeCase {
    <#
      One mode-ladder case: run the hook against $ConfigJson and assert the mode
      word in the ledger record AND in the banner, plus the module and gate
      counts the banner prints. Every assertion is reported through one
      Add-Case, because they are one claim about one run.
    #>
    param([string]$Name, [string]$CaseName, [string]$ConfigJson,
          [string]$Mode, [string]$Counts, [string]$Gates, [string]$Split = '')

    $c = Invoke-SessionStartCase -Name $Name -ConfigJson $ConfigJson
    if ($null -eq $c.record) {
        Add-Case $CaseName $false "no SessionStart record was written. exit $($c.code), stderr: $($c.err)"
        return
    }
    $banner = [string]$c.envelope.systemMessage
    $problems = @()
    if ([string]$c.record.mode -ne $Mode) {
        $problems += "the ledger record says mode '$($c.record.mode)', expected '$Mode'. failures: [$($c.record.failures -join '; ')]"
    }
    if (-not (Test-BannerMode $banner $Mode)) {
        $problems += "the BANNER does not end on '$Mode': [$banner]"
    }
    $f = Get-BannerFailure $banner
    if ($f -ne '') { $problems += "the banner is the self-reported failure string '$f': [$banner]" }
    if ($banner -notmatch [regex]::Escape($Counts)) {
        $problems += "the banner does not say '$Counts': [$banner]"
    }
    if ($banner -notmatch [regex]::Escape($Gates)) {
        $problems += "the banner does not say '$Gates': [$banner]"
    }
    if ($Split -ne '' -and $banner -notmatch [regex]::Escape($Split)) {
        $problems += "the banner does not account for the remainder with '$Split': [$banner]"
    }
    if ($c.code -ne 0) { $problems += "the hook exited $($c.code); it must always exit 0. stderr: $($c.err)" }
    Add-Case $CaseName ($problems.Count -eq 0) ($problems -join "`n")
}

function Test-F1-TheFourUnassertedProbesAreRecordedAndPass {
    <#
      The control for F2 to F4, and the case that closes the "0 hits in tests\"
      row on its own: all four probes are WRITTEN to the record and all four are
      true on the config this repository ships. Without it, "make the probe able
      to fail" and "make it always fail" are indistinguishable - the same
      argument B4 makes for probe 2.
    #>
    $c = Invoke-SessionStartCase -Name 'f1'
    if ($null -eq $c.record) {
        Add-Case 'F1 config_from_file, thresholds_live, payload_session and payload_cwd are recorded and pass on the shipped config' $false `
            "no SessionStart record was written. exit $($c.code), stderr: $($c.err)"
        return
    }
    $sc = $c.record.selfcheck
    $problems = @()
    if ($sc.ran -ne $true) { $problems += "selfcheck.ran is [$($sc.ran)] - self_health is ON in the shipped config.json, so every probe below should have run" }
    foreach ($probe in @('config_from_file', 'thresholds_live', 'payload_session', 'payload_cwd')) {
        $p = $sc.PSObject.Properties[$probe]
        if ($null -eq $p) {
            $problems += "selfcheck.$probe is ABSENT from the record - the probe wrote no result at all, so nothing downstream could tell 'not checked' from 'checked and fine'"
        } elseif ($p.Value -ne $true) {
            $problems += "selfcheck.$probe is [$($p.Value)] on the shipped config.json. failures: [$($c.record.failures -join '; ')]"
        }
    }
    if ($sc.ok -ne $true) { $problems += "selfcheck.ok is [$($sc.ok)] on the shipped config.json: [$($c.record.failures -join '; ')]" }
    Add-Case 'F1 config_from_file, thresholds_live, payload_session and payload_cwd are recorded and pass on the shipped config' `
        ($problems.Count -eq 0) ($problems -join "`n")
}

function Test-F2-AConfigThatDoesNotParseFailsConfigFromFile {
    <#
      Get-LwgConfig FAILS OPEN - a config.json it cannot read is silently
      replaced by the built-in defaults and governance stays on. That is the
      right polarity and it is also why this probe exists: the session then runs
      on settings the operator never wrote, and config_from_file is the only
      thing that says so. It is the one probe whose failure is invisible in
      every other output.
    #>
    $c = Invoke-SessionStartCase -Name 'f2' -ConfigJson "{ this is not JSON, and Get-LwgConfig will fall back"
    if ($null -eq $c.record) {
        Add-Case 'F2 an unreadable config.json fails config_from_file and degrades the session' $false `
            "no SessionStart record was written. exit $($c.code), stderr: $($c.err)"
        return
    }
    $problems = @()
    if ($c.record.selfcheck.config_from_file -ne $false) {
        $problems += ("config_from_file is [$($c.record.selfcheck.config_from_file)] for a config.json that does not parse. " +
                      "The session is running on built-in defaults and reporting the operator's own configuration.")
    }
    if (($c.record.failures -join ' ') -notmatch 'config\.json unreadable') {
        $problems += "no failure names the unreadable config: [$($c.record.failures -join '; ')]"
    }
    if ([string]$c.record.mode -ne 'degraded') {
        $problems += "mode is '$($c.record.mode)', expected 'degraded' - a failed probe must reach the mode word"
    }
    Add-Case 'F2 an unreadable config.json fails config_from_file and degrades the session' ($problems.Count -eq 0) ($problems -join "`n")
}

function Test-F3-AConfigWithNoThresholdsFailsThresholdsLive {
    <#
      A config that PARSES and carries a modules block - so config_from_file is
      true - and no thresholds at all. Both halves are asserted: the case would
      be satisfied by a probe that simply mirrored config_from_file if it only
      looked at thresholds_live.

      THE MODULES BLOCK CARRIES ONE KEY AND IT USED TO BE EMPTY (#268). The
      subject here is the absence of THRESHOLDS, and `"modules": {}` sat on a
      boundary that has since moved: an empty modules object is no longer a
      config this plugin will merge an operator override onto, because
      {"modules":{}} declares nothing and every module then resolves through the
      absent-key default - which is how a seventeen-byte file came to arm a
      blocking gate. Written this way the case asserts what it always meant,
      and config_from_file is true for the reason its own comment gives.
    #>
    $cfg = @'
{
  "version": "0.4.0",
  "modules": { "git_hygiene": true },
  "repos": {}
}
'@
    $c = Invoke-SessionStartCase -Name 'f3' -ConfigJson $cfg
    if ($null -eq $c.record) {
        Add-Case 'F3 a config with no thresholds fails thresholds_live and nothing else' $false `
            "no SessionStart record was written. exit $($c.code), stderr: $($c.err)"
        return
    }
    $problems = @()
    if ($c.record.selfcheck.thresholds_live -ne $false) {
        $problems += ("thresholds_live is [$($c.record.selfcheck.thresholds_live)] for a config declaring no thresholds. " +
                      "The pressure monitors then compare against a hardcoded guess and nothing says so.")
    }
    if ($c.record.selfcheck.config_from_file -ne $true) {
        $problems += "config_from_file is [$($c.record.selfcheck.config_from_file)] for a config.json that parses and carries a modules block"
    }
    if (($c.record.failures -join ' ') -notmatch 'thresholds') {
        $problems += "no failure names the thresholds: [$($c.record.failures -join '; ')]"
    }
    if ([string]$c.record.mode -ne 'degraded') {
        $problems += "mode is '$($c.record.mode)', expected 'degraded'"
    }
    Add-Case 'F3 a config with no thresholds fails thresholds_live and nothing else' ($problems.Count -eq 0) ($problems -join "`n")
}

function Test-F4-APayloadMissingSessionAndCwdFailsBothPayloadProbes {
    <#
      The two probes that read the HOOK PAYLOAD rather than the config. A
      session_id of $null means nothing downstream can correlate a record with
      the session that produced it, which is why the file calls it a real
      failure rather than cosmetic - and until this case the claim rested on the
      comment alone.

      The payload is a well-formed JSON object carrying NEITHER key, not an
      empty stdin: an absent payload is a different input and would exercise
      Read-LwgStdin instead of these two probes.
    #>
    $c = Invoke-SessionStartCase -Name 'f4' -PayloadJson '{"source":"startup"}'
    if ($null -eq $c.record) {
        Add-Case 'F4 a payload with no session_id and no cwd fails both payload probes' $false `
            "no SessionStart record was written. exit $($c.code), stderr: $($c.err)"
        return
    }
    $problems = @()
    if ($c.record.selfcheck.payload_session -ne $false) {
        $problems += "payload_session is [$($c.record.selfcheck.payload_session)] for a payload carrying no session_id"
    }
    if ($c.record.selfcheck.payload_cwd -ne $false) {
        $problems += "payload_cwd is [$($c.record.selfcheck.payload_cwd)] for a payload carrying no cwd"
    }
    $f = ($c.record.failures -join ' ')
    if ($f -notmatch 'session_id')      { $problems += "no failure names session_id: [$f]" }
    if ($f -notmatch 'payload\.cwd')    { $problems += "no failure names payload.cwd: [$f]" }
    if ([string]$c.record.mode -ne 'degraded') {
        $problems += "mode is '$($c.record.mode)', expected 'degraded'"
    }
    Add-Case 'F4 a payload with no session_id and no cwd fails both payload probes' ($problems.Count -eq 0) ($problems -join "`n")
}

function Test-F5-TheShippedConfigIsObserveOnly {
    <#
      The word the shipped plugin actually reports, and the one an operator sees
      most: seven of eleven modules run, no gate is armed, so nothing can block
      anything. '(4 off)' is asserted with it because the parenthetical is what
      stops 7/11 being read as coverage - the four are built and switched off,
      not unwritten.
    #>
    Invoke-ModeCase -Name 'f5' -CaseName 'F5 the shipped config.json reports mode observe-only, 7/11 modules and 0 gates' `
        -ConfigJson '' -Mode 'observe-only' -Counts '7/11 modules' -Gates '0 gates' -Split '(4 off)'
}

function Test-F6-SelfHealthOffIsUnverified {
    <#
      self_health off. Six modules still run, so the session is not inert - and
      the ladder must NOT report observe-only, partial or enforcing, because all
      three assert in this plugin's own documentation that the self-check
      passed. Nothing checked anything this session and the word has to say so.
    #>
    $cfg = @'
{
  "version": "0.4.0",
  "modules": {
    "failure_capture": true,
    "context_pressure": true,
    "self_health": false,
    "log_rotation": true,
    "docs_coupling": true,
    "git_hygiene": true,
    "context_injection": true
  },
  "repos": {},
  "thresholds": {
    "ratelimit": { "warn_pct": 88, "land_all_pct": 92 },
    "context":   { "warn_pct": 75, "critical_pct": 90 }
  }
}
'@
    Invoke-ModeCase -Name 'f6' -CaseName 'F6 self_health off reports mode unverified, never a word that implies a check passed' `
        -ConfigJson $cfg -Mode 'unverified' -Counts '6/11 modules' -Gates '0 gates' -Split '(5 off)'
}

function Test-F7-OneLiveGateIsPartial {
    <#
      interaction.delegate on arms delegate_gate, the one gate an operator can
      turn on with a shipped command. Eight modules of eleven then run with one
      gate live, which is 'partial' and not 'enforcing': three implemented
      modules are still switched off and the word has to carry that.

      '1 gate' singular is asserted deliberately - the banner picks the word off
      the count, and a plural on one gate is the kind of detail that is only
      ever noticed by a reader who then distrusts the rest of the line.
    #>
    $cfg = @'
{
  "version": "0.4.0",
  "modules": {
    "failure_capture": true,
    "context_pressure": true,
    "self_health": true,
    "log_rotation": true,
    "docs_coupling": true,
    "git_hygiene": true,
    "context_injection": true
  },
  "interaction": { "delegate": true },
  "repos": {},
  "thresholds": {
    "ratelimit": { "warn_pct": 88, "land_all_pct": 92 },
    "context":   { "warn_pct": 75, "critical_pct": 90 }
  }
}
'@
    Invoke-ModeCase -Name 'f7' -CaseName 'F7 one live gate with modules still off reports mode partial and 1 gate' `
        -ConfigJson $cfg -Mode 'partial' -Counts '8/11 modules' -Gates '1 gate' -Split '(3 off)'
}

function Test-F8-EverythingOnIsEnforcing {
    <#
      Every implemented module on and all three gates armed. This is the only
      configuration in which 'enforcing' is honest, and it is also the one case
      in which the banner has no parenthetical to add: on THIS fixture nothing
      is planned and nothing is off, so the count and the total are the same
      number and there is no remainder to account for. That branch is asserted
      here by its absence - an '(0 planned)' or '(0 off)' would be noise
      standing where a real caveat belongs.

      SAID OF THIS FIXTURE AND OF NOTHING ELSE. On the config this repository
      SHIPS, four modules are built and switched off, so the banner does carry
      a parenthetical and F5 asserts it - tests\gate_delegate.ps1's N3 sweep
      exists to fail any tracked line that says otherwise, and it is right to,
      because a reader who took the sentence for a general one would conclude
      that delegate_gate is either armed or not counted as implemented, and
      both are wrong about the one component here that can refuse a call.
    #>
    $cfg = @'
{
  "version": "0.4.0",
  "modules": {
    "failure_capture": true,
    "context_pressure": true,
    "self_health": true,
    "log_rotation": true,
    "docs_coupling": true,
    "git_hygiene": true,
    "context_injection": true
  },
  "interaction": { "delegate": true },
  "supervision": {
    "send_liveness": true,
    "completion_audit": true,
    "orphan_watch": true
  },
  "repos": {},
  "thresholds": {
    "ratelimit": { "warn_pct": 88, "land_all_pct": 92 },
    "context":   { "warn_pct": 75, "critical_pct": 90 }
  }
}
'@
    $c = Invoke-SessionStartCase -Name 'f8' -ConfigJson $cfg
    if ($null -eq $c.record) {
        Add-Case 'F8 every implemented module on and three gates armed reports mode enforcing, with no parenthetical' $false `
            "no SessionStart record was written. exit $($c.code), stderr: $($c.err)"
        return
    }
    $banner = [string]$c.envelope.systemMessage
    $problems = @()
    if ([string]$c.record.mode -ne 'enforcing') { $problems += "the ledger record says mode '$($c.record.mode)', expected 'enforcing'. failures: [$($c.record.failures -join '; ')]" }
    if (-not (Test-BannerMode $banner 'enforcing')) { $problems += "the BANNER does not end on 'enforcing': [$banner]" }
    if ($banner -notmatch '11/11 modules') { $problems += "the banner does not say '11/11 modules': [$banner]" }
    if ($banner -notmatch '3 gates')              { $problems += "the banner does not say '3 gates': [$banner]" }
    if ($banner -match '\d+/\d+ modules \w+\s*\(') { $problems += "the banner prints a parenthetical on a config with nothing planned and nothing off: [$banner]" }
    $f = Get-BannerFailure $banner
    if ($f -ne '') { $problems += "the banner is the self-reported failure string '$f': [$banner]" }
    Add-Case 'F8 every implemented module on and three gates armed reports mode enforcing, with no parenthetical' `
        ($problems.Count -eq 0) ($problems -join "`n")
}

function Test-F9-NothingRunningIsInert {
    <#
      The last rung. Every module in the `modules` block off - self_health among
      them - and no switch-backed module armed, so nothing is running at all.
      'inert' rather than 'unverified' because with an active count of zero
      "nothing is running" is the stronger and completely verifiable statement,
      and the ladder prefers it. #177 names four words; this is the fifth, and
      an unpinned rung on a total function is where the next drift lands.
    #>
    $cfg = @'
{
  "version": "0.4.0",
  "modules": {
    "failure_capture": false,
    "context_pressure": false,
    "self_health": false,
    "log_rotation": false,
    "docs_coupling": false,
    "git_hygiene": false,
    "context_injection": false
  },
  "repos": {},
  "thresholds": {
    "ratelimit": { "warn_pct": 88, "land_all_pct": 92 },
    "context":   { "warn_pct": 75, "critical_pct": 90 }
  }
}
'@
    Invoke-ModeCase -Name 'f9' -CaseName 'F9 nothing enabled at all reports mode inert, 0/11 modules and 0 gates' `
        -ConfigJson $cfg -Mode 'inert' -Counts '0/11 modules' -Gates '0 gates' -Split '(11 off)'
}

# =========================================================================
# SECTION G - #144, the banner, and #177's additionalContext envelope
#
# THE BANNER (#144). lib\session_start.ps1 emits one line every session sees,
# and no test had ever read it. A silent banner, a blank banner, or any of the
# THREE self-reported failure strings the file can emit would have failed no
# build. The three are located by their text and not by line number: #144 cited
# :22 / :158 / :227, the second and third have since moved to :228 and :307, and
# a third string at :324 - 'output serialisation failed', written straight to
# the console when the envelope will not serialise - was not in the issue at all
# and is the one a "not either failure string" assertion would sail past.
#
# THE ENVELOPE (#177). Invoke-SessionStartCase has parsed the hook's stdout into
# $envelope since this file landed and no case had read a field off it.
# additionalContext is the only model-visible output this plugin produces at
# session start and it is paid for on every session, so what it says is a
# behavioural claim like any other: it must describe what is RUNNING. G5 to G7
# assert the three statements it makes that can be wrong in the expensive
# direction - the module roster, the gate sentence, and the one that says the
# self-check did not run.
#
# G3 IS THE ONE THAT CANNOT BE FAKED BY A CONSTANT. A banner hardcoded to a
# plausible string passes G1, G2 and G4; it fails G3, which requires the banner
# to carry the reason THIS degraded session degraded.
#
# G2 CARRIES ONE MORE THING AND IT IS NOT COVERAGE: #132's banner word. Every
# other case in sections F and G is green at 4342980 and is offered as coverage;
# G2 is red there, because the banner called its count 'active' when the count
# is a statement about config.json and the registry. Read its comment.
# =========================================================================

function Test-G1-TheBannerIsEmittedAndIsNotAFailureString {
    $c = Invoke-SessionStartCase -Name 'g1'
    $banner = [string]$c.envelope.systemMessage
    $problems = @()
    if ($null -eq $c.envelope) { $problems += "the hook printed nothing that parses as JSON. exit $($c.code), stdout: [$($c.raw)], stderr: $($c.err)" }
    if ([string]::IsNullOrWhiteSpace($banner)) {
        $problems += "systemMessage is empty. A silent banner is indistinguishable from a plugin that is not installed, and until this case it would have failed no build. Raw stdout: [$($c.raw)]"
    }
    $f = Get-BannerFailure $banner
    if ($f -ne '') {
        $problems += ("the banner is the self-reported failure string '$f': [$banner]. " +
                      "The hook exits 0 on every path, so this reaches the operator as an ordinary session.")
    }
    if ($banner -notmatch '^LW-WATCHTOWER v\d') { $problems += "the banner does not open with 'LW-WATCHTOWER v<version>': [$banner]" }
    if ($c.code -ne 0) { $problems += "the hook exited $($c.code); it must always exit 0. stderr: $($c.err)" }
    Add-Case 'G1 the SessionStart banner is emitted, non-empty, and is none of the three failure strings' ($problems.Count -eq 0) ($problems -join "`n")
}

function Test-G2-TheBannerNumbersAreTheOnesTheConfigImplies {
    <#
      A banner that is present and well-formed can still be wrong about every
      number on it. On the shipped config the answer is 7 of 11 enabled, four
      built and switched off, no gate live, observe-only - and the last of those
      is asserted here as well as in F5 on purpose: F5 pins the ladder's ANSWER,
      this pins that the banner PRINTS the answer it was given.

      AND THE NOUN (#132). THIS IS THE ONE CASE IN SECTIONS F AND G THAT IS RED
      AT 4342980, and it is red for a defect rather than for a coverage gap: the
      banner said 'N/M modules ACTIVE' there. $activeCount comes from
      Get-LwgActiveModules, whose own docstring says the count is "enabled by
      config AND backed by code" - the registry and config.json, and nothing
      that was observed to happen. 'Active' reads as "these ran". Three of the
      eight events hooks/hooks.json registers on were read out of one specific
      binary and are simply inert on a build that does not carry them, while
      this line goes on counting the module, so the word claimed an observation
      the plugin has never had, in the one line every session reads.

      The other five mode cases assert the FRACTION and not the noun - '7/11
      modules' - deliberately. They are coverage and are green at that commit,
      and folding the wording defect into all six would have made five green
      cases look like five red ones and lost which change did what.

      BOTH DIRECTIONS. Asserting 'enabled' alone would pass on a banner that
      printed both words; the absence of 'active' is the half that says the
      overstatement is gone rather than merely joined.
    #>
    $c = Invoke-SessionStartCase -Name 'g2'
    $banner = [string]$c.envelope.systemMessage
    $problems = @()
    foreach ($want in @('7/11 modules enabled', '(4 off)', '0 gates', 'observe-only')) {
        if ($banner -notmatch [regex]::Escape($want)) { $problems += "the banner does not say '$want'" }
    }
    if ($banner -match 'modules active') {
        $problems += ("REGRESSION (#132): the banner says 'modules active'. The count is Get-LwgActiveModules', " +
                      "which is enabled-by-config AND backed-by-code - a statement about the registry, not about " +
                      "anything that was observed to fire. Nothing in this plugin knows whether a registered hook " +
                      "ran at all, so 'active' claims an observation it does not have.")
    }
    if ($null -ne $c.record -and [string]$c.record.mode -ne 'observe-only') {
        $problems += "the ledger record says mode '$($c.record.mode)' while the banner was asked for 'observe-only' - the two come from one variable and must not be able to disagree"
    }
    if ($problems.Count -gt 0) { $problems += "banner: [$banner]" }
    Add-Case 'G2 the banner prints the count, the remainder, the gate count and the mode - and calls the count ENABLED, not active (#132)' ($problems.Count -eq 0) ($problems -join "`n")
}

function Test-G3-ADegradedSessionStillGetsARealBannerCarryingTheReason {
    <#
      The failure path that is NOT one of the three failure strings: the hook
      completed, a probe failed, and the banner has to say which. 'degraded'
      alone tells a reader something is missing and not what, so the file
      appends the first failure - and that append is the thing a constant banner
      cannot fake.
    #>
    $c = Invoke-SessionStartCase -Name 'g3' -ConfigJson "{ deliberately unparseable"
    $banner = [string]$c.envelope.systemMessage
    $problems = @()
    $f = Get-BannerFailure $banner
    if ($f -ne '') { $problems += "the banner is the self-reported failure string '$f' - an unreadable config.json must degrade the session, not break the hook: [$banner]" }
    if (-not (Test-BannerMode $banner 'degraded')) { $problems += "the banner does not report mode 'degraded': [$banner]" }
    if ($banner -notmatch 'config\.json unreadable') {
        $problems += "the banner reports a degraded session without naming what failed, so the operator is told something is wrong and not what: [$banner]"
    }
    if ($c.code -ne 0) { $problems += "the hook exited $($c.code); it must always exit 0. stderr: $($c.err)" }
    Add-Case 'G3 a degraded session still gets a real banner, carrying the reason it degraded' ($problems.Count -eq 0) ($problems -join "`n")
}

function Test-G4-TheEnvelopeIsTheSessionStartShape {
    $c = Invoke-SessionStartCase -Name 'g4'
    $problems = @()
    if ($null -eq $c.envelope) {
        Add-Case 'G4 the hook emits the SessionStart hookSpecificOutput envelope' $false `
            "the hook printed nothing that parses as JSON. exit $($c.code), stdout: [$($c.raw)], stderr: $($c.err)"
        return
    }
    $hso = $c.envelope.hookSpecificOutput
    if ($null -eq $hso) { $problems += 'there is no hookSpecificOutput object, so Claude Code is handed no context at all' }
    else {
        if ([string]$hso.hookEventName -ne 'SessionStart') { $problems += "hookSpecificOutput.hookEventName is '$($hso.hookEventName)', expected 'SessionStart'" }
        if ([string]::IsNullOrWhiteSpace([string]$hso.additionalContext)) {
            $problems += 'additionalContext is empty - it is the only model-visible output this plugin produces at session start and it is paid for on every session'
        }
    }
    if ($c.envelope.suppressOutput -ne $true) { $problems += "suppressOutput is [$($c.envelope.suppressOutput)], expected true - the banner is the user-visible half and the envelope must not be printed beside it" }
    Add-Case 'G4 the hook emits the SessionStart hookSpecificOutput envelope' ($problems.Count -eq 0) ($problems -join "`n")
}

function Test-G5-AdditionalContextDescribesWhatIsRunning {
    <#
      The roster and the gate sentence, on the shipped config. Every active
      module is named because the sentence claims to name them; the four that
      are built and switched off are accounted for because an unexplained gap in
      a coverage report is the same defect as an overstated one; and the gate
      sentence must say no gate is LIVE rather than that none exists, since
      three do and are simply off.
    #>
    $c = Invoke-SessionStartCase -Name 'g5'
    $ctx = [string]$c.envelope.hookSpecificOutput.additionalContext
    $problems = @()
    foreach ($want in @('mode observe-only', 'Running (7/11)', 'No gate is live')) {
        if ($ctx -notmatch [regex]::Escape($want)) { $problems += "additionalContext does not say '$want'" }
    }
    foreach ($m in @('failure_capture', 'context_pressure', 'self_health', 'log_rotation', 'docs_coupling', 'git_hygiene', 'context_injection')) {
        if ($ctx -notmatch [regex]::Escape($m)) { $problems += "additionalContext does not name the active module '$m'" }
    }
    foreach ($m in @('send_liveness_gate', 'completion_audit', 'orphan_watch', 'delegate_gate')) {
        if ($ctx -notmatch [regex]::Escape($m)) { $problems += "additionalContext does not account for '$m', which is built and switched OFF - a reader totting up the names comes up short with no account of the remainder" }
    }
    if ($ctx -match 'can BLOCK a tool call') { $problems += 'additionalContext claims a gate can block on a config where none is armed' }
    if ($problems.Count -gt 0) { $problems += "additionalContext: [$ctx]" }
    Add-Case 'G5 additionalContext names every active module, accounts for the rest, and says no gate is live' ($problems.Count -eq 0) ($problems -join "`n")
}

function Test-G6-AdditionalContextNamesALiveGate {
    <#
      The other direction, and the expensive one. Telling the model nothing is
      blocked while a gate is enforcing teaches it to distrust a guardrail that
      works, which is the same class of lie as counting an unbuilt module as
      coverage pointing the other way.
    #>
    $cfg = @'
{
  "version": "0.4.0",
  "modules": {
    "failure_capture": true,
    "context_pressure": true,
    "self_health": true,
    "log_rotation": true,
    "docs_coupling": true,
    "git_hygiene": true,
    "context_injection": true
  },
  "interaction": { "delegate": true },
  "repos": {},
  "thresholds": {
    "ratelimit": { "warn_pct": 88, "land_all_pct": 92 },
    "context":   { "warn_pct": 75, "critical_pct": 90 }
  }
}
'@
    $c = Invoke-SessionStartCase -Name 'g6' -ConfigJson $cfg
    $ctx = [string]$c.envelope.hookSpecificOutput.additionalContext
    $problems = @()
    if ($ctx -match 'No gate is live') { $problems += 'additionalContext says no gate is live on a config where interaction.delegate arms delegate_gate' }
    if ($ctx -notmatch 'delegate_gate')                 { $problems += 'additionalContext does not name the live gate' }
    if ($ctx -notmatch 'can BLOCK a tool call outright') { $problems += 'additionalContext does not say the live gate can block a tool call' }
    if ($ctx -notmatch [regex]::Escape('mode partial'))  { $problems += "additionalContext does not carry the mode word 'partial'" }
    if ($problems.Count -gt 0) { $problems += "additionalContext: [$ctx]" }
    Add-Case 'G6 additionalContext names the live gate and says it can block, when one is armed' ($problems.Count -eq 0) ($problems -join "`n")
}

function Test-G7-AdditionalContextSaysTheSelfCheckDidNotRun {
    <#
      Three states, not two. A model told nothing at all about the self-check
      would reasonably assume it passed, which is exactly the assumption this
      plugin exists to refuse - so with self_health off the context has to say
      in words that none of what it just listed was verified.
    #>
    $cfg = @'
{
  "version": "0.4.0",
  "modules": {
    "failure_capture": true,
    "context_pressure": true,
    "self_health": false,
    "log_rotation": true,
    "docs_coupling": true,
    "git_hygiene": true,
    "context_injection": true
  },
  "repos": {},
  "thresholds": {
    "ratelimit": { "warn_pct": 88, "land_all_pct": 92 },
    "context":   { "warn_pct": 75, "critical_pct": 90 }
  }
}
'@
    $c = Invoke-SessionStartCase -Name 'g7' -ConfigJson $cfg
    $ctx    = [string]$c.envelope.hookSpecificOutput.additionalContext
    $banner = [string]$c.envelope.systemMessage
    $problems = @()
    if ($ctx -notmatch 'Self-check did NOT run') { $problems += 'additionalContext does not say the self-check did not run' }
    if ($ctx -notmatch 'not what has been proven to work') {
        $problems += 'additionalContext does not say that what it listed is what config.json DECLARES rather than what was proven'
    }
    if ($ctx -match 'Self-check DEGRADED') { $problems += 'additionalContext reports a DEGRADED self-check for one that never ran - "did not run" is not "failed"' }
    if ($banner -notmatch 'self_health off') { $problems += "the banner does not say the omission is deliberate: [$banner]" }
    if ($problems.Count -gt 0) { $problems += "additionalContext: [$ctx]" }
    Add-Case 'G7 additionalContext says the self-check did NOT run, rather than reporting it passed or failed' ($problems.Count -eq 0) ($problems -join "`n")
}

function Test-G8-AdditionalContextDoesNotPrintItsRemainderCountTwice {
    <#
      #266. The remainder sentence is assembled from a label carrying the total
      and one clause per non-empty bucket, and each clause opens with ITS OWN
      count. On the SHIPPED configuration exactly one bucket is non-empty - four
      modules built and switched off - so the two numbers were the same number
      and the sentence came out

          The other 4: 4 (send_liveness_gate, completion_audit, orphan_watch,
          delegate_gate) built but switched OFF in config.json.

      Every fact in it is true, which is why this is the low-severity end of the
      shelf and why no other case here catches it: G5 asserts that all four are
      NAMED, and they are. What is wrong is the sentence, and the sentence is
      injected into the model's context on every single session start, under a
      heading in docs/architecture.md that reads "The plugin never overstates
      itself".

      THE ASSERTION IS ON THE SHAPE AND NOT ON A FIXED STRING. `The other N: N (`
      with the same N twice is the defect; a backreference says exactly that and
      keeps working when the counts move, which they do every time a module
      lands. The second half - that all four are still named and the total is
      still right - is what stops a "fix" that simply deleted the numbers from
      passing.

      RED-FIRST: this case FAILS at 6aebcd6, where lib/session_start.ps1 emits
      the label and the clause unconditionally.

      TWO BUCKETS ARE DELIBERATELY NOT ASSERTED HERE. The colon form is correct
      whenever the remainder is split across buckets, and reaching that state
      needs a config.json that leaves a module both unbuilt and switched off -
      a fixture about the registry rather than about this sentence.
    #>
    $c = Invoke-SessionStartCase -Name 'g8'
    $ctx = [string]$c.envelope.hookSpecificOutput.additionalContext
    $problems = @()
    if ([string]::IsNullOrWhiteSpace($ctx)) {
        Add-Case 'G8 additionalContext states its remainder count ONCE, not twice (#266)' $false `
            "additionalContext is empty. exit $($c.code), stdout: [$($c.raw)], stderr: $($c.err)"
        return
    }
    $m = [regex]::Match($ctx, 'The other (\d+): \1 \(')
    if ($m.Success) {
        $problems += ("REGRESSION (#266): additionalContext renders '" + $m.Value + "' - the remainder count is " +
                      "printed as the label AND again as the head of the only clause under it. One bucket accounts " +
                      "for the whole remainder on the shipped configuration, so this is what every default install " +
                      "puts in front of the model on every session start.")
    }
    if ($ctx -notmatch 'The other 4\b') {
        $problems += "additionalContext does not account for the four remaining modules with the number 4 at all - the count must still be stated, just not twice"
    }
    foreach ($mod in @('send_liveness_gate', 'completion_audit', 'orphan_watch', 'delegate_gate')) {
        if ($ctx -notmatch [regex]::Escape($mod)) { $problems += "additionalContext no longer names '$mod' among the modules that are built and switched off" }
    }
    if ($ctx -notmatch 'built but switched OFF in config\.json') {
        $problems += 'additionalContext no longer says the remainder is built but switched off, so a reader is left with a number and no account of it'
    }
    if ($problems.Count -gt 0) { $problems += "additionalContext: [$ctx]" }
    Add-Case 'G8 additionalContext states its remainder count ONCE, not twice (#266)' ($problems.Count -eq 0) ($problems -join "`n")
}

# =========================================================================
# SECTION H - #269, the payload is UTF-8 and nothing here decoded it as UTF-8
#
# Every hook read its stdin through [Console]::In, which is built from
# [Console]::InputEncoding - the CONSOLE's input code page. Claude Code spawns
# hooks from a Node host with windowsHide: true, so the child gets its own
# console at the system OEM page (IBM437 on this machine, measured), while the
# payload on the pipe is UTF-8 with no BOM. Every non-ASCII byte therefore
# arrived mojibaked: `cwd` named a directory that does not exist, so
# Get-LwgRepoInfo's walk found no .git, `repo` resolved to null, every `repos`
# entry in config.json fell through to the global default, and the event log -
# the thing this plugin exists to produce - recorded a path that never existed,
# on every record, for the life of the install. Nothing reported a fault: the
# session still said `partial`, the gate still said live, the self-check still
# passed, because payload.cwd was non-EMPTY and that is all probe 4 asks.
#
# THE REPOSITORY ALREADY KNEW. statusline/statusline.ps1:52-86 states this
# defect, about this exact spawn shape, and fixes it - and the reasoning was
# applied to one file out of the ten that read a payload.
#
# WHY THIS IS ONE CASE AND NOT FOUR, AND WHAT IS THEREFORE UNPINNED. There are
# four stdin readers: Read-LwgStdin in lib/common.ps1, which every hook that
# dot-sources it uses, and three scripts that must drain the pipe before
# common.ps1 exists - lib/gate_delegate.ps1, lib/gate_send.ps1 and
# lib/subagent_start.ps1. This suite owns the SessionStart hook, so H1 pins the
# SHARED reader and nothing else.
#
# The three pre-common.ps1 drains are FIXED AND UNPINNED. No case anywhere
# asserts on them, and that is stated here rather than left to be assumed,
# because a header claiming coverage that does not exist is the defect this
# whole file was written about. Their sibling cases belong in
# tests/gate_delegate.ps1, tests/subagent_scan.ps1 and tests/payload_guard.ps1,
# and were not added in the branch that fixed them: each of those suites
# publishes a case count that tracked pages state, and moving one would have
# failed the documentation-claims guard on a number that branch could not edit.
# The measurement and the exact cases are written on #269.
#
# WHAT IT ASSERTS AND WHY THAT ONE. The recorded cwd, read off
# lw-watchtower.jsonl on DISK, byte for byte against the fixture. Not the hook's
# stdout: the child writes stdout through [Console]::Out at the same code page
# it read stdin at, and the harness decodes stdout as UTF-8, so a CP437 decode
# followed by a CP437 encode CANCELS OUT and the mojibake is invisible on that
# channel. Measured - the same run whose ledger record read
# "hello w<U+251C><U+2562>rld" returned "hello w<U+00F6>rld" on stdout. The
# ledger is written through [IO.File]::AppendAllText with an explicit UTF8
# encoding, so it is the one surface where what the hook UNDERSTOOD is visible.
# =========================================================================

function Test-H1-ANonAsciiCwdSurvivesTheHooksStdinByteForByte {
    <#
      RED-FIRST: this case FAILS at 6aebcd6, where lib/common.ps1's
      Read-LwgStdin reads [Console]::In.ReadToEnd(). Measured there: the
      fixture cwd "...\hello w<U+00F6>rld <U+65E5><U+672C>" was recorded as
      "...\hello w<U+251C><U+2562>rld <U+00B5><U+00F9><U+00D1>..." - a CP437
      decode of the UTF-8 bytes, exactly the transformation
      statusline/statusline.ps1's header describes.

      THE FIXTURE IS A REAL DIRECTORY, created here. It does not have to be for
      the assertion to hold - the record carries what the hook read, existing or
      not - but a fixture path that could not exist would leave a reader unsure
      whether the defect is about decoding or about a missing directory, and it
      is about decoding.

      -NoConsoleWindow is load-bearing and Invoke-Child's header says why: it is
      what makes the child's console code page the OEM one Claude Code's own
      spawn produces, instead of whatever terminal the suite happens to be run
      from. Without it this case can pass at the baseline on a machine whose
      terminal sits at 65001, which is a vacuous green.
    #>
    # Built from code points rather than typed, so the assertion cannot be
    # defeated by this file being saved in the wrong encoding one day - which is
    # the very class of defect under test.
    $leaf = 'hello w' + [char]0x00F6 + 'rld ' + [char]0x65E5 + [char]0x672C
    $cwd  = Join-Path $script:Work $leaf
    New-Dir $cwd | Out-Null

    $payload = (@{ session_id = 'h1-utf8'; cwd = $cwd; source = 'startup' } | ConvertTo-Json -Compress)
    $c = Invoke-SessionStartCase -Name 'h1' -PayloadJson $payload -NoConsoleWindow

    if ($null -eq $c.record) {
        Add-Case 'H1 a non-ASCII cwd survives the hook''s stdin byte for byte (#269)' $false `
            "no SessionStart record was written, so nothing about the payload could be read. exit $($c.code), stderr: $($c.err)"
        return
    }

    $got = [string]$c.record.cwd
    $problems = @()
    if ($got -cne $cwd) {
        $hex = { param($s) (([int[]][char[]]$s) | ForEach-Object { $_.ToString('X4') }) -join ' ' }
        $problems += ("REGRESSION (#269): the ledger records cwd as [$got], not [$cwd]. The payload is written to " +
                      "the pipe as UTF-8 with no BOM; a reader built from [Console]::InputEncoding decodes it at " +
                      "the console's code page instead, so cwd names a directory that does not exist, " +
                      "Get-LwgRepoInfo finds no .git, repo resolves to null and every repos entry in config.json " +
                      "applies to nothing - silently, on every record.")
        $problems += ("recorded: " + (& $hex $got))
        $problems += ("expected: " + (& $hex $cwd))
    }
    if ($c.code -ne 0) { $problems += "the hook exited $($c.code); it must always exit 0. stderr: $($c.err)" }
    Add-Case 'H1 a non-ASCII cwd survives the hook''s stdin byte for byte (#269)' ($problems.Count -eq 0) ($problems -join "`n")
}

# =========================================================================
# SECTION I - #268, a config.json that parses and is not a config must not be
# able to arm a gate through the operator's override
#
# Get-LwgConfig decided whether config.json was good enough to merge an override
# onto with `$null -ne $cfg.modules`, and in PowerShell $false, 0, '', @() and
# 'yes' are every one of them non-$null. So {"modules":false} - seventeen bytes,
# no thresholds, no `interaction` block, none of the shipped defaults - was
# accepted as a GOOD config, the operator's override was merged over it, and
# delegate_gate came up ARMED. The self-check in the same process reported the
# config degraded and the banner reported the gate live anyway.
#
# WHY THE ASSERTION IS ON THE BANNER'S GATE COUNT. The consequence that matters
# is a LOCKOUT: with delegate_gate armed the main thread cannot call Bash, so it
# cannot run the command that would switch the gate off, and the operator's way
# out is hand-editing JSON. docs/configuration.md's "a corrupt config leaves the
# gate off" and docs/modules.md's "it keeps a bad config a nuisance rather than
# a lockout" are both statements about this number. This suite already drives
# the hook that prints it (F5 to F9), so the polarity is observable here without
# a second harness.
#
# I2 IS NOT DECORATION. Without it, a Get-LwgConfig that had simply stopped
# merging overrides at all would pass I1 - green because nothing works, which is
# the shape of pass this file's header calls execution without coverage.
# =========================================================================

function Test-I1-AMangledConfigCannotArmAGateThroughTheOverride {
    <#
      RED-FIRST: this case FAILS at 6aebcd6, where the banner over the same two
      files reads `1 gate` and `partial`, and gate_delegate exits 2 on the next
      main-thread call. Measured there on {"modules":false}, {"modules":0},
      {"modules":"yes"}, {"modules":[]} and {"modules":{}} alike.
    #>
    $c = Invoke-SessionStartCase -Name 'i1' -ConfigJson '{"modules":false}' `
                                 -OverrideJson '{"interaction":{"delegate":true}}'
    $banner = [string]$c.envelope.systemMessage
    $problems = @()
    if ([string]::IsNullOrWhiteSpace($banner)) {
        Add-Case 'I1 a config.json that is not a config cannot arm a gate through the override (#268)' $false `
            "the hook printed no banner. exit $($c.code), stdout: [$($c.raw)], stderr: $($c.err)"
        return
    }
    if ($banner -notmatch '0 gates') {
        $problems += ("REGRESSION (#268): the banner reports a live gate over a config.json of seventeen bytes. " +
                      "`$false is not `$null, so the null guard read it as a whole config and merged the operator's " +
                      "override over it. With delegate_gate armed the main thread cannot call Bash, so it cannot run " +
                      "the command that would switch the gate off - the lockout docs/modules.md says a bad config " +
                      "cannot cause.")
    }
    if ($null -ne $c.record -and $c.record.selfcheck.config_from_file -ne $false) {
        $problems += "config_from_file is [$($c.record.selfcheck.config_from_file)] for a document that is not a config, so the session would not report the damage either"
    }
    if ($c.code -ne 0) { $problems += "the hook exited $($c.code); it must always exit 0. stderr: $($c.err)" }
    if ($problems.Count -gt 0) { $problems += "banner: [$banner]" }
    Add-Case 'I1 a config.json that is not a config cannot arm a gate through the override (#268)' ($problems.Count -eq 0) ($problems -join "`n")
}

function Test-I2-TheSameOverrideOverTheShippedConfigDoesArmTheGate {
    <#
      The control for I1, and the only thing that stops it passing on a plugin
      that has stopped reading overrides. Same override, same hook, the SHIPPED
      config.json underneath it: one gate, mode partial.
    #>
    $c = Invoke-SessionStartCase -Name 'i2' -OverrideJson '{"interaction":{"delegate":true}}'
    $banner = [string]$c.envelope.systemMessage
    $problems = @()
    if ($banner -notmatch '1 gate\b') {
        $problems += ("the override does not arm the gate over the SHIPPED config.json either, so I1 beside this " +
                      "case establishes nothing: a Get-LwgConfig that had stopped merging overrides at all would " +
                      "pass it.")
    }
    if (-not (Test-BannerMode $banner 'partial')) { $problems += "the banner does not report mode 'partial' with one gate live" }
    if ($problems.Count -gt 0) { $problems += "banner: [$banner]" }
    Add-Case 'I2 CONTROL: the same override over the SHIPPED config.json does arm the gate (#268)' ($problems.Count -eq 0) ($problems -join "`n")
}

# =========================================================================

Say ''
Say 'LW-WATCHTOWER state-resolution and platform suite'
Say '  A #146 CLAUDE_CONFIG_DIR   B #60 probe 2   C #106 selfcheck.probe'
Say '  D #8 marketplace layout    E #132 platform and hook events, #249 the registry''s own prose'
Say '  F #177 the four unasserted probes and the mode ladder'
Say '  G #144 the banner   #177 the additionalContext envelope   #266 its remainder count'
Say '  H #269 the payload is UTF-8 and [Console]::In decoded it at the console''s code page'
Say '  I #268 a config.json that parses and is not a config cannot arm a gate'
Say ''

try {
    if (-not (Test-Path -LiteralPath (Join-Path $script:PayloadRoot 'lib\common.ps1'))) {
        Abort-Suite "this file must sit in tests\ beside the repository it tests; lw-watchtower\lib\common.ps1 is not under $($script:PayloadRoot)"
    }
    $script:Work = Join-Path ([IO.Path]::GetTempPath()) ("lwg-state-" + [guid]::NewGuid().ToString('N'))
    New-Dir $script:Work | Out-Null

    # The cases are DISCOVERED rather than listed. A second list of them is a
    # second thing to keep correct, and the failure mode of a case that is
    # written and never called is a suite that reports a clean pass over
    # coverage it does not have - the founding defect this repository exists to
    # catch, in its own test harness. Sorting on the name gives A1..A5, B1..B4,
    # C1, D1..D3, E1..E4, F1..F9, G1..G8, H1, I1..I2, so section order is a property of
    # the naming. IT IS A STRING SORT: F10 would come before F2, so a section stops
    # at nine cases and the next one takes a new letter. That costs nothing
    # except readability of the run, which is the only thing the order decides.
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
