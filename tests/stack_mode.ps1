#requires -version 5
<#
  LW-WATCHTOWER stack_mode regression suite - lib\stack_mode.ps1.

      powershell -NoProfile -ExecutionPolicy Bypass -File tests\stack_mode.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File tests\stack_mode.ps1 -Verbose

  ---------------------------------------------------------------------------
  WHY THIS FILE EXISTS AT ALL, WHEN THE STANDING RULE IS THAT tests\ TAKES NO
  NEW FILE
  ---------------------------------------------------------------------------
  It is the second half of a WAIVER granted once, by the owner, on 6 September
  2026 - ruling F5, recorded on #147. Two files are covered by that one ruling:
  tests\metrics_behaviour.ps1 (#165) and this one (#179), and the ruling's own
  words are that it is the only waiver in the release. The obligation that comes
  with it is discharged in the same commit as this file: every prose site that
  states how many files tests\ holds, and how many of them test behaviour, is
  restated here alongside it, and tests\doc_claims.ps1 derives both numbers from
  the tree and fails the build rather than letting either rot.

  ---------------------------------------------------------------------------
  WHAT IS UNDER TEST
  ---------------------------------------------------------------------------
  lib\stack_mode.ps1 resolves ONE working discipline for a session - PROTO or
  SHIP - and injects a POINTER to the ruleset for it. It is registered on two
  matcher-less events, SessionStart and SubagentStart, from one leaf.

  The claims these cases defend:

      THE MODE IS RESOLVED IN A STATED PRECEDENCE ORDER, one source answering
      and the rest standing down, so a session has exactly one mode and the two
      rulesets cannot both be in force at once.

      EVERY OFF IS SILENT - the module switched off, the mode resolved to off,
      a ruleset file the payload does not contain, and a config.json this hook
      cannot read that far. Silent means no envelope, no log and no state. On the
      happy path it writes nothing at all; its error path records one row, which
      no case here reaches and which is named rather than claimed away.

      THE POINTER IS HONEST ABOUT ITS OWN PAYLOAD. The SHIP ruleset is vendored
      as SKILL.md alone and names scripts, templates and references this plugin
      does not ship, against a Node runtime it does not have. The injected text
      says so, because the reader is a model that would otherwise try to run
      them - the "a shipped file asserts something exists which does not" class
      tests\payload_guard.ps1 exists for.

  ---------------------------------------------------------------------------
  RED-FIRST, AT BASELINE 315c461
  ---------------------------------------------------------------------------
  EVERY CASE BELOW IS RED AT BASELINE 315c461, and the run is recorded rather
  than asserted: RESULT: 0 of 15 case(s) passed, all fifteen naming their own
  assertion. lib\stack_mode.ps1 is not in that tree at all, so each case starts
  its own child process, gets nothing back and fails on its own terms - there is
  no shared setup failure standing in for fifteen verdicts. Measured by running
  this file against the branch tip with the script moved out of
  lw-watchtower\lib\, which is the state 315c461 is in.

  TWO OF THE FIFTEEN PASSED ON THE FIRST BASELINE RUN AND WERE WRONG TO. S9 and
  S14 asked only whether the child had produced any output, and at the baseline
  the interpreter's own "the argument to -File does not exist" text arrived as
  164 characters of it. Both now assert on the envelope, and Invoke-StackMode
  keeps the child's error stream out of the capture entirely - that note is on
  the helper, with what the redirect itself then cost.

  A cheap baseline is worth saying out loud rather than dressing up: these cases
  establish that the module does what it says once it exists. They are NOT
  evidence that any of them would have caught a subtle regression in an earlier
  version of it, because there was no earlier version.

  ---------------------------------------------------------------------------
  WHAT IS DELIBERATELY NOT COVERED, so a green run is not read as more
  ---------------------------------------------------------------------------
  * THE PERFORMANCE BUDGET. These cases assert on ANSWERS, not on milliseconds.
    The hook's own header carries the reasoning for the fast path; nothing here
    re-measures it, so a green run is no evidence the hook is still fast.
  * A LIVE SESSION. Nothing here starts one. Every run is the hook in a child
    process with the environment the CLI sets and a fixture payload on real
    stdin, which is a simulation and is recorded as one. Whether Claude Code
    actually merges this additionalContext into a worker's context is NOT
    MEASURED HERE and is named as unmeasured rather than assumed.
  * THE CONTENT OF THE TWO RULESETS. Every fixture writes an invented one-line
    file at each ruleset path. What the vendored ponytail and unlazy pages
    actually say is upstream's, is pinned by tests\payload_guard.ps1 and
    lw-watchtower\THIRD-PARTY-NOTICES.md, and has no case here.
  * Get-LwgRepo's slug resolution. One case proves a per-repo block ESCALATES
    and still lands on the right answer; the walk itself is covered where it
    lives.

  ---------------------------------------------------------------------------
  TEST SAFETY
  ---------------------------------------------------------------------------
  Every run redirects CLAUDE_PLUGIN_ROOT and CLAUDE_PLUGIN_DATA into a throwaway
  tree under the temp directory and restores both in a finally, so no case can
  read the operator's real config or write to the operator's real state
  directory. Nothing outside that tree is deleted; it is removed in a finally.

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
    # The PLUGIN PAYLOAD root - lw-watchtower\ under this file's parent, not the
    # repository root. Neither .github\workflows\ci.yml nor doc_claims' sibling
    # runner passes -Root, so this default is the only value it ever gets.
    [string]$Root
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Join-Path (Split-Path -Parent $PSScriptRoot) 'lw-watchtower' }

$HookPath = Join-Path $Root 'lib\stack_mode.ps1'

# The module this hook is, spelled here exactly once and deliberately NOT read
# out of the script under test: a case that derives its subject from the
# specimen cannot notice the subject changing.
$ModuleName = 'stack_mode'

# The two ruleset paths the hook points at, relative to the plugin root. Spelled
# here for the same reason.
$ProtoRel = 'context\stack\ponytail.md'
$ShipRel  = 'context\stack\unlazy.md'

# The environment variable that outranks every other source.
$EnvName = 'CLAUDE_STACK_MODE'

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

function New-CaseRoot {
    <#
      A throwaway plugin root for one case:

        <work>\<tag>\root\context\stack\ponytail.md   the PROTO ruleset
        <work>\<tag>\root\context\stack\unlazy.md     the SHIP ruleset
        <work>\<tag>\data\                            the redirected state dir
        <work>\<tag>\cwd\                             a working directory to
                                                      hand the hook as `cwd`

      config.json is NOT written here - each case says what its config looks
      like, because the config is half the subject.

      -NoRulesets leaves context\stack\ empty, which is the fixture for "the
      pointer refuses to name a file this payload does not contain".
    #>
    param([string]$Tag, [switch]$NoRulesets)

    $dir  = Join-Path $script:Work $Tag
    $root = Join-Path $dir 'root'
    $st   = Join-Path $root 'context\stack'
    $data = Join-Path $dir 'data'
    $cwd  = Join-Path $dir 'cwd'
    foreach ($p in @($st, $data, $cwd)) { [void][IO.Directory]::CreateDirectory($p) }
    if (-not $NoRulesets) {
        $enc = [Text.UTF8Encoding]::new($false)
        [IO.File]::WriteAllText((Join-Path $root $ProtoRel), "lwg-stack-fixture-proto-ruleset`r`n", $enc)
        [IO.File]::WriteAllText((Join-Path $root $ShipRel),  "lwg-stack-fixture-ship-ruleset`r`n",  $enc)
    }
    return @{ dir = $dir; root = $root; data = $data; cwd = $cwd }
}

function Invoke-StackMode {
    <#
      One real child run of lib\stack_mode.ps1 against a case root.

      -Config writes config.json VERBATIM, without ConvertTo-Json, for the same
      reason tests\subagent_scan.ps1 does: the subject is the text of the file,
      and a helper that round-tripped through the JSON writer could not express
      a config that does not parse. Omitting -Config leaves the root with no
      config.json at all, which is one of the fixtures.

      PRESENCE IS TESTED WITH $PSBoundParameters AND NOT AGAINST $null.
      PowerShell gives an unpassed [string] parameter the value '' - never $null
      - so `if ($null -ne $Config)` is always true and a case meaning "no file"
      silently gets a zero-byte one instead.

      -Override writes config.override.json into the redirected state directory.
      -Cwd overrides the payload's working directory; the default is the case
      root's own cwd\ folder. -NoPayload sends text that is not JSON at all.
      -Env sets CLAUDE_STACK_MODE for this run alone.

      Returns @{ code; out } where `out` is the whole stdout joined into one
      string, so a case can assert on a silence by its length.
    #>
    param(
        [Parameter(Mandatory = $true)][hashtable]$Tree,
        [string]$HookEvent = 'SessionStart',
        [string]$Config,
        [string]$Override,
        [string]$Cwd,
        [string]$Env,
        [string]$RawPayload,
        [switch]$NoPayload
    )

    $cfgPath = Join-Path $Tree.root 'config.json'
    if ($PSBoundParameters.ContainsKey('Config')) {
        [IO.File]::WriteAllText($cfgPath, $Config, [Text.UTF8Encoding]::new($false))
    } elseif ([IO.File]::Exists($cfgPath)) {
        [IO.File]::Delete($cfgPath)
    }

    $ovPath = Join-Path $Tree.data 'config.override.json'
    if ($PSBoundParameters.ContainsKey('Override')) {
        [IO.File]::WriteAllText($ovPath, $Override, [Text.UTF8Encoding]::new($false))
    } elseif ([IO.File]::Exists($ovPath)) {
        [IO.File]::Delete($ovPath)
    }

    $useCwd = if ($PSBoundParameters.ContainsKey('Cwd')) { $Cwd } else { [string]$Tree.cwd }
    $stdin  = if ($NoPayload) { 'this is not json' }
              elseif ($PSBoundParameters.ContainsKey('RawPayload')) { $RawPayload }
              else { '{"session_id":"lwg-stack-fixture","cwd":' + (ConvertTo-Json -InputObject $useCwd) + '}' }

    $saveRoot = $env:CLAUDE_PLUGIN_ROOT
    $saveData = $env:CLAUDE_PLUGIN_DATA
    $saveMode = [Environment]::GetEnvironmentVariable($EnvName)
    # $ErrorActionPreference IS LOWERED FOR THE CHILD CALL ALONE, and it has to
    # be. Under 'Stop' a native command whose error stream is REDIRECTED turns
    # anything it writes there into a terminating error in this process - so the
    # redirect below, added to keep the child's stderr out of the capture, made
    # the first case that hit it abort the whole suite instead of failing. Two
    # bugs cancelling would have been worse than either: the baseline then read
    # "0 of 0 case(s)" at 315c461, an abort wearing a red-first proof's clothes.
    $saveEap  = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $env:CLAUDE_PLUGIN_ROOT = $Tree.root
        $env:CLAUDE_PLUGIN_DATA = $Tree.data
        if ($PSBoundParameters.ContainsKey('Env')) {
            [Environment]::SetEnvironmentVariable($EnvName, $Env)
        } else {
            [Environment]::SetEnvironmentVariable($EnvName, $null)
        }
        # STDERR IS DISCARDED AND THAT IS A CORRECTION, NOT A CONVENIENCE.
        # Without the redirect the child's error stream lands in this capture,
        # and at the red-first baseline 315c461 - where the hook is not in the tree at
        # all - the interpreter's own "the argument to -File does not exist"
        # text arrived as 164 characters of stdout. Two cases whose subject is
        # an ENVELOPE were written against that length and PASSED at the
        # baseline, which is the vacuous-case shape this repository keeps
        # finding in itself. Both now assert on the envelope; this redirect is
        # the other half of the fix. What the hook was told is carried by its
        # EXIT CODE, which every case that can read one does read.
        $lines = $stdin | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $HookPath -HookEvent $HookEvent 2>$null
        $code  = if ($null -eq $LASTEXITCODE) { 255 } else { $LASTEXITCODE }
        return @{ code = $code; out = (@($lines) -join '') }
    } finally {
        $ErrorActionPreference = $saveEap
        if ($null -eq $saveRoot) {
            Remove-Item -LiteralPath 'Env:\CLAUDE_PLUGIN_ROOT' -ErrorAction SilentlyContinue
        } else { $env:CLAUDE_PLUGIN_ROOT = $saveRoot }
        if ($null -eq $saveData) {
            Remove-Item -LiteralPath 'Env:\CLAUDE_PLUGIN_DATA' -ErrorAction SilentlyContinue
        } else { $env:CLAUDE_PLUGIN_DATA = $saveData }
        [Environment]::SetEnvironmentVariable($EnvName, $saveMode)
    }
}

function New-Config {
    <#
      A config.json holding the `modules` block and, optionally, this module's
      `module_config` block. Hand-written rather than serialised, so a case can
      say exactly what the file looks like.
    #>
    param(
        [object]$Enabled = $true,
        [string[]]$ShipRoots,
        [string[]]$ProtoRoots,
        [string]$Default,
        [string]$Repos
    )
    $flag = if ($null -eq $Enabled) { '' } else { '"' + $ModuleName + '": ' + $(if ([bool]$Enabled) { 'true' } else { 'false' }) + ',' }
    $mc = @()
    if ($PSBoundParameters.ContainsKey('ShipRoots'))  { $mc += '"ship_roots": ['  + (($ShipRoots  | ForEach-Object { ConvertTo-Json -InputObject $_ }) -join ', ') + ']' }
    if ($PSBoundParameters.ContainsKey('ProtoRoots')) { $mc += '"proto_roots": [' + (($ProtoRoots | ForEach-Object { ConvertTo-Json -InputObject $_ }) -join ', ') + ']' }
    if ($PSBoundParameters.ContainsKey('Default'))    { $mc += '"default": ' + (ConvertTo-Json -InputObject $Default) }
    $reposBlock = if ($PSBoundParameters.ContainsKey('Repos')) { '"repos": ' + $Repos + ',' } else { '' }
    return @"
{
  $reposBlock
  "modules": { $flag "self_health": true },
  "module_config": { "$ModuleName": { $($mc -join ', ') } }
}
"@
}

function Get-Context {
    <# The decoded additionalContext out of one envelope, or '' when there is none. #>
    param([string]$Out)
    if ([string]::IsNullOrWhiteSpace($Out)) { return '' }
    try {
        $o = $Out | ConvertFrom-Json
        return [string]$o.hookSpecificOutput.additionalContext
    } catch { return '' }
}

# ---------------------------------------------------------------------------
# CASES
# ---------------------------------------------------------------------------

function Test-ProtoOnAProtoPath {
    <#
      S1. A working directory under a configured proto root resolves PROTO, and
      the pointer names the PROTO ruleset in the fixture root rather than
      anything in the operator's real install.
    #>
    $t = New-CaseRoot -Tag 's1'
    $r = Invoke-StackMode -Tree $t -Config (New-Config -ProtoRoots @($t.cwd) -ShipRoots @('C:\no\such\ship\root'))
    $ctx = Get-Context $r.out
    Add-Result 'S1 a cwd under a configured proto root resolves PROTO and points at the proto ruleset' `
        ($r.code -eq 0 -and $ctx -match 'stack mode: PROTO' -and $ctx.Contains((Join-Path $t.root $ProtoRel)) -and $ctx -notmatch 'stack mode: SHIP') `
        ("exit $($r.code); additionalContext was [$ctx]. Expected the word PROTO and the fixture path " +
         "$(Join-Path $t.root $ProtoRel). A mode resolved from a path root is the ordinary case - it is what an " +
         "operator gets without setting anything per session.")
}

function Test-ShipOnAShipPath {
    <#
      S2. The same, for SHIP - and the SHIP pointer must carry the sentence that
      says its own ruleset names files this payload does not ship, against a
      runtime this plugin does not have. That sentence is a standing obligation
      recorded on #179, not a nicety: without it every SHIP worker is handed
      `node <skill-dir>/scripts/gate-check.mjs` and cannot run it.
    #>
    $t = New-CaseRoot -Tag 's2'
    $r = Invoke-StackMode -Tree $t -Config (New-Config -ShipRoots @($t.cwd) -ProtoRoots @('C:\no\such\proto\root'))
    $ctx = Get-Context $r.out
    $warns = ($ctx -match '(?i)not\s+in\s+this\s+payload') -and ($ctx -match '(?i)no\s+Node\s+runtime') -and $ctx.Contains('gate-check.mjs')
    Add-Result 'S2 a cwd under a configured ship root resolves SHIP, and the pointer says the node scripts do not ship' `
        ($r.code -eq 0 -and $ctx -match 'stack mode: SHIP' -and $ctx.Contains((Join-Path $t.root $ShipRel)) -and $warns) `
        ("exit $($r.code); additionalContext was [$ctx]. Expected the word SHIP, the fixture path " +
         "$(Join-Path $t.root $ShipRel), and a sentence naming gate-check.mjs as absent and this plugin as " +
         "carrying no Node runtime. A pointer that hands a worker instructions it cannot follow is the defect " +
         "this module was ordered to prevent.")
}

function Test-TheMarkerOutranksTheConfiguredRoots {
    <#
      S3. A .stackmode marker in the working directory beats the path roots, and
      the comment lines above the word are dropped rather than read as the
      answer. The roots here say PROTO; the marker says ship.
    #>
    $t = New-CaseRoot -Tag 's3'
    [IO.File]::WriteAllText((Join-Path $t.cwd '.stackmode'),
                            "# this tree is being released, not explored`r`n`r`nship`r`n",
                            [Text.UTF8Encoding]::new($false))
    $r = Invoke-StackMode -Tree $t -Config (New-Config -ProtoRoots @($t.cwd))
    $ctx = Get-Context $r.out
    Add-Result 'S3 a .stackmode marker in the working directory outranks a configured proto root' `
        ($r.code -eq 0 -and $ctx -match 'stack mode: SHIP' -and $ctx -match '(?i)marker in the working directory') `
        ("exit $($r.code); additionalContext was [$ctx]. The configured root says proto and the marker says ship, " +
         "so SHIP is the answer and the source must name the marker. If PROTO came back the precedence ladder is " +
         "inverted and a per-tree opt-in is unreachable.")
}

function Test-TheEnvironmentOutranksTheMarker {
    <#
      S4. CLAUDE_STACK_MODE beats everything below it. Set to proto here against
      a marker AND a ship root that both say ship, so nothing but the
      environment can produce the answer.
    #>
    $t = New-CaseRoot -Tag 's4'
    [IO.File]::WriteAllText((Join-Path $t.cwd '.stackmode'), "ship`r`n", [Text.UTF8Encoding]::new($false))
    $r = Invoke-StackMode -Tree $t -Config (New-Config -ShipRoots @($t.cwd)) -Env 'proto'
    $ctx = Get-Context $r.out
    Add-Result 'S4 CLAUDE_STACK_MODE outranks both the marker and the configured roots' `
        ($r.code -eq 0 -and $ctx -match 'stack mode: PROTO' -and $ctx -match "(?i)$EnvName environment variable") `
        ("exit $($r.code); additionalContext was [$ctx]. Both file sources say ship and the environment says proto, " +
         "so PROTO is the answer and the source must name the variable.")
}

function Test-OffIsSilent {
    <#
      S5. THREE OFFS, ONE SILENCE, and each is checked separately because they
      are three different mechanisms that must not be assumed to share a code
      path: the mode resolved to off, the module switched off in config.json,
      and the module switched off in the operator's config.override.json.

      SILENT MEANS SILENT - no envelope, no systemMessage, no partial output.
      The positive control is in the same case: the identical fixture with
      nothing switched off DOES inject, so a silence produced by a broken hook
      cannot pass as a silence produced by the switch.
    #>
    $t = New-CaseRoot -Tag 's5'
    $cfgOn  = New-Config -Default 'ship'
    $cfgOff = New-Config -Enabled $false -Default 'ship'

    $control = Invoke-StackMode -Tree $t -Config $cfgOn
    $byMode  = Invoke-StackMode -Tree $t -Config $cfgOn -Env 'off'
    $byFlag  = Invoke-StackMode -Tree $t -Config $cfgOff
    $byOv    = Invoke-StackMode -Tree $t -Config $cfgOn -Override ('{"modules":{"' + $ModuleName + '":false}}')

    $ok = $control.code -eq 0 -and $control.out.Length -gt 0 -and
          $byMode.code -eq 0 -and $byMode.out.Length -eq 0 -and
          $byFlag.code -eq 0 -and $byFlag.out.Length -eq 0 -and
          $byOv.code   -eq 0 -and $byOv.out.Length   -eq 0
    Add-Result 'S5 off is silent three ways - the resolved mode, the config flag, and the operator override' `
        $ok `
        ("control exit $($control.code) with $($control.out.Length) char(s) - it must inject; " +
         "mode=off exit $($byMode.code) with $($byMode.out.Length); " +
         "config flag false exit $($byFlag.code) with $($byFlag.out.Length); " +
         "config.override.json false exit $($byOv.code) with $($byOv.out.Length). " +
         "The override arm is #11's defect in this module: a hook that read config.json alone would go on " +
         "injecting while the banner, the doctor and the config command all reported it off.")
}

function Test-AConfigThatDoesNotParseIsSilent {
    <#
      S6. THE ONE PLACE THIS MODULE DOES NOT FAIL OPEN, and the case exists to
      pin the departure rather than to let it be discovered.

      context_injection injects invariant text and so treats an unreadable
      config as "every module on". This module injects an ASSERTION ABOUT THE
      OPERATOR'S ENVIRONMENT, and a mode announced from a config nothing could
      read is a guess wearing a verdict's clothes.

      THREE SHAPES, and the third is the one that matters: a config.json that is
      absent, one that is not JSON at all, and one that IS valid JSON but has no
      root `modules` object - the last is what a hand-edit that drops a brace
      leaves behind, and it is the shape a scanner could most easily read past.

      THE FOURTH ARM IS THE POSITIVE CONTROL AND IT IS THE POINT: a config that
      parses and simply does not MENTION this module still injects. Absent is
      not false, exactly as it is for every other module - the departure above
      is about a document that could not be read, not about a missing key.
    #>
    $t = New-CaseRoot -Tag 's6'
    $absent  = Invoke-StackMode -Tree $t
    $garbage = Invoke-StackMode -Tree $t -Config 'this file is not json at all'
    $noMod   = Invoke-StackMode -Tree $t -Config '{ "version": "x", "supervision": { "orphan_watch": false } }'
    $noKey   = Invoke-StackMode -Tree $t -Config '{ "modules": { "self_health": true } }'

    $ok = $absent.code  -eq 0 -and $absent.out.Length  -eq 0 -and
          $garbage.code -eq 0 -and $garbage.out.Length -eq 0 -and
          $noMod.code   -eq 0 -and $noMod.out.Length   -eq 0 -and
          $noKey.code   -eq 0 -and $noKey.out.Length   -gt 0
    Add-Result 'S6 a config.json this hook cannot read is silent, but a config missing only this key still injects' `
        $ok `
        ("no config.json: exit $($absent.code), $($absent.out.Length) char(s); " +
         "not JSON: exit $($garbage.code), $($garbage.out.Length); " +
         "valid JSON with no modules block: exit $($noMod.code), $($noMod.out.Length); " +
         "valid JSON, modules block, this key absent: exit $($noKey.code), $($noKey.out.Length) - this last one " +
         "MUST inject, or the module has quietly stopped failing open on the ordinary case as well.")
}

function Test-EachRegistrationEmitsItsOwnEventName {
    <#
      S7. ONE LEAF, TWO EVENTS. hookEventName is mandatory and event-specific,
      so the two registrations must not emit each other's. This is what
      -HookEvent is for and the only case that can tell it is wired up.
    #>
    $t = New-CaseRoot -Tag 's7'
    $cfg = New-Config -Default 'proto'
    $ss  = Invoke-StackMode -Tree $t -Config $cfg -HookEvent 'SessionStart'
    $sa  = Invoke-StackMode -Tree $t -Config $cfg -HookEvent 'SubagentStart'
    $ok = $ss.out -match '"hookEventName":"SessionStart"' -and
          $sa.out -match '"hookEventName":"SubagentStart"'
    Add-Result 'S7 one leaf serving two events emits the event name of the registration that called it' `
        $ok `
        ("SessionStart run said [$($ss.out)]; SubagentStart run said [$($sa.out)]. A registration emitting the " +
         "other event's name has its whole envelope rejected by the CLI, and the injection silently does nothing.")
}

function Test-ThePointerRefusesToNameAFileThatIsNotThere {
    <#
      S8. The payload without the rulesets. Pointing a model at a page that is
      not in the payload is precisely the defect this module was built to
      prevent, so an absent ruleset produces silence - not a pointer, and not an
      apology.

      Its positive control is the same fixture with the files present.
    #>
    $bare = New-CaseRoot -Tag 's8a' -NoRulesets
    $full = New-CaseRoot -Tag 's8b'
    $cfg  = New-Config -Default 'ship'
    $rb = Invoke-StackMode -Tree $bare -Config $cfg
    $rf = Invoke-StackMode -Tree $full -Config $cfg
    Add-Result 'S8 a ruleset the payload does not contain produces silence rather than a pointer to nothing' `
        ($rb.code -eq 0 -and $rb.out.Length -eq 0 -and $rf.code -eq 0 -and $rf.out.Length -gt 0) `
        ("with no context\stack\ files: exit $($rb.code), $($rb.out.Length) char(s) - must be zero; " +
         "with them: exit $($rf.code), $($rf.out.Length) char(s) - must not be. A pointer naming a file nobody " +
         "shipped sends its reader to something that is not there, which is what payload_guard rule 6 exists for.")
}

function Test-TheEnvelopeCannotInterfereWithTheSession {
    <#
      S9. The envelope carries additionalContext and suppressOutput and NOTHING
      that could stop, redirect or block anything. `decision`, `continue` and
      `stopReason` are absent BY CONSTRUCTION rather than by intent, and a case
      is what makes that a property rather than a claim in a comment.
    #>
    $t = New-CaseRoot -Tag 's9'
    $r = Invoke-StackMode -Tree $t -Config (New-Config -Default 'ship')
    $bad = @('decision', 'continue', 'stopReason', 'systemMessage', 'permissionDecision') |
           Where-Object { $r.out -match ('"' + $_ + '"') }
    # THE POSITIVE HALF IS THE ENVELOPE AND NOT ITS LENGTH. Written against a
    # length, this case passed at the red-first baseline 315c461 on 164 characters of
    # interpreter error text - see Invoke-StackMode.
    Add-Result 'S9 the envelope carries no decision, continue or stopReason field' `
        ($r.code -eq 0 -and $r.out -match '"hookSpecificOutput"' -and $bad.Count -eq 0) `
        ("the envelope was [$($r.out)]" + $(if ($bad.Count) { "; it carries " + ($bad -join ', ') } else { '' }) +
         ". An injector that can also deny is a gate nobody declared, and this plugin's declared gates are the " +
         "only things in it allowed to block.")
}

function Test-ShipWinsWhereTheRootsOverlap {
    <#
      S10. A ship root nested inside a proto root. Both match; SHIP wins,
      because where an operator's own lists disagree the stricter discipline is
      the safer thing to be wrong about - and because a tie resolved by list
      order would depend on which key came first in a file people hand-edit,
      which is the defect Get-LwgJsonObjectSpan's depth rule exists for.
    #>
    $t = New-CaseRoot -Tag 's10'
    $r = Invoke-StackMode -Tree $t -Config (New-Config -ProtoRoots @($t.dir) -ShipRoots @($t.cwd))
    $ctx = Get-Context $r.out
    Add-Result 'S10 where a ship root is nested inside a proto root, SHIP wins and the tie is not order-dependent' `
        ($r.code -eq 0 -and $ctx -match 'stack mode: SHIP') `
        ("exit $($r.code); additionalContext was [$ctx]. proto_roots holds $($t.dir), ship_roots holds $($t.cwd), " +
         "and the working directory is under both.")
}

function Test-APrefixThatIsNotASegmentDoesNotMatch {
    <#
      S11. 'C:\work\api' is not inside 'C:\work\ap'. A StartsWith comparison
      says it is, and would put a whole neighbouring tree into the wrong mode
      with nothing anywhere reporting it. The case pairs the near-miss with the
      exact parent so a matcher that simply never matches cannot pass it.
    #>
    $t = New-CaseRoot -Tag 's11'
    $near = [string]$t.cwd + 'x'
    [void][IO.Directory]::CreateDirectory($near)
    $miss = Invoke-StackMode -Tree $t -Config (New-Config -ShipRoots @($t.cwd) -Default 'proto') -Cwd $near
    $hit  = Invoke-StackMode -Tree $t -Config (New-Config -ShipRoots @($t.cwd) -Default 'proto') -Cwd $t.cwd
    $mCtx = Get-Context $miss.out
    $hCtx = Get-Context $hit.out
    Add-Result 'S11 a root is matched on a whole path segment, so a sibling directory sharing a prefix is not inside it' `
        ($mCtx -match 'stack mode: PROTO' -and $hCtx -match 'stack mode: SHIP') `
        ("cwd $near against ship root $($t.cwd) gave [$mCtx] and must be PROTO; the root itself gave [$hCtx] and " +
         "must be SHIP. A prefix comparison that ignores the separator puts a neighbouring tree into a discipline " +
         "nobody chose for it.")
}

function Test-AnUnparseablePayloadStillExitsZero {
    <#
      S12. stdin that is not JSON. The cwd is then unknown, so the marker and
      the roots have nothing to say and the configured default answers - and the
      hook still exits 0, because nothing this module can fail at is worth
      failing a session or a dispatch over.
    #>
    $t = New-CaseRoot -Tag 's12'
    $r = Invoke-StackMode -Tree $t -Config (New-Config -ShipRoots @($t.cwd) -Default 'proto') -NoPayload
    $ctx = Get-Context $r.out
    Add-Result 'S12 a payload that is not JSON leaves the path sources with nothing to say and still exits 0' `
        ($r.code -eq 0 -and $ctx -match 'stack mode: PROTO' -and $ctx -match '(?i)configured default') `
        ("exit $($r.code); additionalContext was [$ctx]. With no readable cwd the ship root cannot match, so the " +
         "configured default is the answer and the source must say so rather than naming a root it never tested.")
}

function Test-APerRepoOverrideEscalatesAndStillResolves {
    <#
      S13. A `repos` block naming this module cannot be resolved by the fast
      scan - only the origin slug can answer it - so the hook escalates to
      common.ps1 and the exact answer. The case cannot see WHICH path ran; what
      it pins is that the escalation lands on the right answer rather than
      throwing, which is the failure that would otherwise reach a live session.

      The payload here has no repository, so Test-LwgModule falls back to the
      global flag - which is false. Silence is the correct answer, and the
      positive control beside it is the identical fixture with the flag true.
    #>
    $t = New-CaseRoot -Tag 's13'
    $repos = '{ "acme/example": { "modules": { "' + $ModuleName + '": true } } }'
    $off = Invoke-StackMode -Tree $t -Config (New-Config -Enabled $false -Default 'proto' -Repos $repos)
    $on  = Invoke-StackMode -Tree $t -Config (New-Config -Enabled $true  -Default 'proto' -Repos $repos)
    Add-Result 'S13 a per-repo block escalates to the exact resolver and still lands on the global flag it is given' `
        ($off.code -eq 0 -and $off.out.Length -eq 0 -and $on.code -eq 0 -and $on.out.Length -gt 0) `
        ("global flag false with a repos block: exit $($off.code), $($off.out.Length) char(s); " +
         "global flag true: exit $($on.code), $($on.out.Length) char(s). The dispatch has no repository, so the " +
         "slow path must answer with the global value rather than with the per-repo one.")
}

function Test-NothingIsWrittenAnywhere {
    <#
      S14. "It writes nothing" is a claim, so it is checked - ON THE HAPPY PATH,
      which is the whole of what this case can see. The state directory
      is handed to the hook and must come back EMPTY: no log, no state file, no
      marker of its own. The fixture root is checked too - a hook that cached a
      resolution beside the config would dirty the plugin's own git tree, which
      is the defect config.json's own $comment records the override existing to
      fix.

      WHAT THIS CASE CANNOT SEE, AND THE CLAIM IS NARROWED TO MATCH. The hook's
      ERROR path records a StackModeError row through Write-LwgEvent, which
      resolves the state directory through Get-LwgStateDir and therefore
      CREATES it. Every run here hands the child an EXISTING state directory -
      see TEST SAFETY - so no case reaches that branch, and this one asserts
      about the happy path rather than about the module.
    #>
    $t = New-CaseRoot -Tag 's14'
    $r = Invoke-StackMode -Tree $t -Config (New-Config -Default 'ship')
    $left = @(Get-ChildItem -LiteralPath $t.data -Recurse -Force -ErrorAction SilentlyContinue |
              ForEach-Object { $_.FullName })
    $rootFiles = @(Get-ChildItem -LiteralPath $t.root -Recurse -File -Force -ErrorAction SilentlyContinue |
                   ForEach-Object { $_.Name } | Sort-Object -Unique)
    $expected = @('config.json', 'ponytail.md', 'unlazy.md')
    $extra = @($rootFiles | Where-Object { $expected -notcontains $_ })
    # AGAIN THE ENVELOPE AND NOT ITS LENGTH: a case whose positive control is
    # "it ran" must be able to tell running from failing to start.
    Add-Result 'S14 on the happy path the hook writes nothing - not to the state directory, and not into the plugin tree' `
        ($r.code -eq 0 -and $r.out -match '"hookSpecificOutput"' -and $left.Count -eq 0 -and $extra.Count -eq 0) `
        ("it injected $($r.out.Length) char(s), so it ran; the state directory holds [" + ($left -join ', ') +
         "] and must be empty; the plugin root gained [" + ($extra -join ', ') + "] and must gain nothing.")
}

function Test-ADecoyArrayElementDegradesRatherThanMisreads {
    <#
      S15. THE cwd READER DOES NOT STEP OVER AN ARRAY VALUE, and this case
      exists because the limit was found by reading the port rather than by a
      failure - the ONE thing worth pinning about a limit is which side of
      degraded-versus-wrong it falls on.

      Brackets move no brace depth in Get-LwgJsonMemberStart, so a STRING
      ELEMENT inside a depth-1 array is compared against the key like a member
      name. A payload shaped

          {"tools":["cwd"],"cwd":"<the real one>"}

      stops on the array element, finds no colon after it, and answers "no cwd".

      SO THE WORST CASE IS DEGRADED, NEVER WRONG: the ship root cannot match a
      cwd the hook never read, the configured default answers instead, and the
      decoy's own text is never returned as a working directory. The control is
      the SAME payload with the array moved AFTER the member, which must resolve
      SHIP off the root - so a hook that simply never reads cwd at all cannot
      pass this case.
    #>
    $t = New-CaseRoot -Tag 's15'
    $cwdJson = ConvertTo-Json -InputObject ([string]$t.cwd)
    $decoy   = '{"session_id":"lwg-stack-fixture","tools":["cwd"],"cwd":' + $cwdJson + '}'
    $clean   = '{"session_id":"lwg-stack-fixture","cwd":' + $cwdJson + ',"tools":["cwd"]}'
    $cfg = New-Config -ShipRoots @($t.cwd) -Default 'proto'
    $rd = Invoke-StackMode -Tree $t -Config $cfg -RawPayload $decoy
    $rc = Invoke-StackMode -Tree $t -Config $cfg -RawPayload $clean
    $dCtx = Get-Context $rd.out
    $cCtx = Get-Context $rc.out
    Add-Result 'S15 an array element that spells the cwd key degrades to the configured default and never to the decoy' `
        ($rd.code -eq 0 -and $dCtx -match 'stack mode: PROTO' -and $dCtx -match '(?i)configured default' -and
         $rc.code -eq 0 -and $cCtx -match 'stack mode: SHIP') `
        ("with the array BEFORE the member: exit $($rd.code), [$dCtx] - must be PROTO from the configured default, " +
         "because the ship root cannot match a cwd that was never read; with the array AFTER it: exit $($rc.code), " +
         "[$cCtx] - must be SHIP, which is what proves the reader reads cwd at all. If the first arm came back SHIP " +
         "the walker resolved a working directory out of an array element, which would be wrong rather than degraded.")
}

# ---------------------------------------------------------------------------
# RUN
# ---------------------------------------------------------------------------

Write-Output '==========================================================================='
Write-Output 'LW-WATCHTOWER stack_mode suite'
Write-Output "  hook      : $HookPath"
Write-Output ''

try {
    # NO "IS THE HOOK THERE" PRE-CHECK, DELIBERATELY. Throwing here would turn
    # the baseline into ONE abort with zero cases run, and the red-first claim
    # in the header would then be about a setup failure rather than about any
    # case. Without it each case runs its own child process, gets nothing back,
    # and fails on its own assertion - which is what was measured at 315c461.
    $script:Work = Join-Path ([IO.Path]::GetTempPath()) ("lwg-stack-test-" + [Guid]::NewGuid().ToString('N').Substring(0, 10))
    [void][IO.Directory]::CreateDirectory($script:Work)

    Test-ProtoOnAProtoPath
    Test-ShipOnAShipPath
    Test-TheMarkerOutranksTheConfiguredRoots
    Test-TheEnvironmentOutranksTheMarker
    Test-OffIsSilent
    Test-AConfigThatDoesNotParseIsSilent
    Test-EachRegistrationEmitsItsOwnEventName
    Test-ThePointerRefusesToNameAFileThatIsNotThere
    Test-TheEnvelopeCannotInterfereWithTheSession
    Test-ShipWinsWhereTheRootsOverlap
    Test-APrefixThatIsNotASegmentDoesNotMatch
    Test-AnUnparseablePayloadStillExitsZero
    Test-APerRepoOverrideEscalatesAndStillResolves
    Test-NothingIsWrittenAnywhere
    Test-ADecoyArrayElementDegradesRatherThanMisreads
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
    Write-Output "RESULT: $script:Pass of $total case(s) had run when it stopped. Nothing about stack_mode was established."
    Write-Output 'EXIT: 2 (the hook was NOT exercised, which is not the same as passing)'
    exit 2
}
if ($total -eq 0) {
    Write-Output 'ABORTED: no case ran. An empty set is not a pass.'
    Write-Output 'RESULT: no case ran, so nothing about stack_mode was established'
    Write-Output 'EXIT: 2 (zero cases run is an abort, never an empty-set pass)'
    exit 2
}
Write-Output ("RESULT: {0} of {1} case(s) passed." -f $script:Pass, $total)
if ($failed -gt 0) {
    Write-Output "$failed case(s) FAILED."
    Write-Output 'EXIT: 1 (at least one case failed - read the per-case lines above. A case reporting'
    Write-Output '         an injection where a switch is off means the hook runs while every'
    Write-Output '         reporting surface says it does not.)'
    exit 1
}
Write-Output 'EXIT: 0 (every case passed - the precedence ladder answers from one source at a'
Write-Output '         time, every off is silent, the pointer refuses to name a file this payload'
Write-Output '         does not hold, the SHIP pointer says its own node scripts are absent, and'
Write-Output '         the hook writes nothing anywhere. This is a simulation: no live session'
Write-Output '         was started, so whether the CLI merges this context is NOT MEASURED here.)'
exit 0
