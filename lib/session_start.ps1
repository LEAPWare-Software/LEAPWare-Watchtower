#requires -version 5
<#
  LW-WATCHTOWER SessionStart hook.

  Invoked from hooks/hooks.json in exec form:
      command: "powershell"
      args:    ["-NoProfile","-ExecutionPolicy","Bypass","-File","${CLAUDE_PLUGIN_ROOT}/lib/session_start.ps1"]

  Reads the hook JSON on stdin, resolves which governance modules are live for
  this session, runs a behavioural self-check, and emits the standing rules as
  additionalContext plus a one-line user-visible banner as systemMessage.

  ALWAYS exits 0. A broken governance layer must never break a session.
#>

$ErrorActionPreference = 'Stop'

# Banner uses a middot; without this the console encoding can mangle it.
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$version   = '0.4.0'
$banner    = "LW-WATCHTOWER v$version - startup failed, see log"
$context   = $null
$payload   = [pscustomobject]@{}
$selfcheck = @{}

try {
    . (Join-Path $PSScriptRoot 'common.ps1')

    $payload = Read-LwgStdin
    $cfg     = Get-LwgConfig
    $repo    = Get-LwgRepo $payload

    # --- what is genuinely running -----------------------------------------
    # Counting config.json's flags reports every switched-on module as active,
    # including the two that have no code. The registry in common.ps1 is the
    # source of truth, so the numbers below are enabled AND implemented, never
    # enabled alone.
    $enabled     = @(Get-LwgEnabledModules -Config $cfg -Repo $repo)
    $active      = @(Get-LwgActiveModules  -Config $cfg -Repo $repo)
    $activeGates = @(Get-LwgActiveGates    -Config $cfg -Repo $repo)
    $planned     = @(Get-LwgPlannedModules)
    $implemented = @(Get-LwgImplementedModules)

    $activeCount  = $active.Count
    $gateCount    = $activeGates.Count
    $plannedCount = $planned.Count
    $totalCount   = $script:LwgModules.Count
    # Implemented but switched off - the only bucket the two counts above miss.
    $offCount     = $implemented.Count - $activeCount

    # --- behavioural self-check --------------------------------------------
    # Sibling-project incident #700: "the files exist" is not evidence a monitor can fire.
    # Each probe below asserts a real value comes back, not a null or a default
    # standing in for one. Anything that fails downgrades the session to
    # 'degraded' and is written to the log with the reason.
    #
    # GATED ON ITS OWN FLAG, like every other module. It used to run
    # unconditionally, which made self_health a switch wired to nothing - the
    # same defect this plugin exists to catch, sitting inside the module whose
    # whole job is to catch it. With the flag off NO probe runs, and `ran` is
    # recorded false so nothing downstream can mistake "not checked" for
    # "checked and fine". `ok` is deliberately left $null in that case: an
    # absent result must not be readable as either a pass or a failure.
    $selfHealthOn      = Test-LwgModule -Name 'self_health' -Config $cfg -Repo $repo
    $selfcheck.ran     = $selfHealthOn
    $selfcheck.ok      = $null
    $failures          = @()

    if ($selfHealthOn) {
        # 1. config.json was genuinely parsed, not silently replaced by fallbacks.
        $selfcheck.config_from_file = ($cfg._source -eq 'file')
        if (-not $selfcheck.config_from_file) { $failures += 'config.json unreadable (running on built-in defaults)' }

        # 2. Every declared module resolves to the boolean the operator WROTE.
        #
        # THIS PROBE COULD NOT FAIL, and it is worth saying why rather than
        # quietly replacing it. It read
        #
        #     $v = Test-LwgModule -Name $m -Config $cfg -Repo $repo
        #     if ($v -isnot [bool]) { $unresolved += $m }
        #
        # and Test-LwgModule returns a [bool] on every one of its three exit
        # paths by construction - $enabled starts as the literal $true and is
        # only ever reassigned from an explicit [bool] cast, and the
        # switch-backed exit returns Test-LwgFlag, whose own value is
        # initialised from a [bool]-TYPED parameter. The predicate was
        # unsatisfiable for every possible input, so the probe reported a pass
        # for every config.json - including the malformed ones it read as though
        # it were checking for them. A check wired to nothing, reporting itself
        # as coverage, inside the module whose whole job is to catch checks
        # wired to nothing. And it fed $selfcheck.ok, which feeds
        # Get-LwgSessionMode, which is the mode word the banner, the
        # model-visible context and /lw-watchtower:doctor all quote.
        #
        # The observable failure was never a bad return TYPE. It is a
        # CONFIGURED VALUE THAT WAS DISCARDED: `"docs_coupling": "false"` is
        # what an operator writes when they mean off, [bool] on a non-empty
        # string is $true in PowerShell, and the fix for THAT - ignore the
        # non-boolean, log it through Write-LwgInvalidFlag, carry on as if the
        # scope had said nothing - is precisely what put the evidence out of
        # this probe's reach. So it now reads the RAW config, at all four
        # scopes, through Get-LwgUnresolvedFlags. It fails on a config in which
        # a declared module did not resolve to what the operator wrote, and it
        # passes on the config this repository ships - which is the behaviour
        # this probe's own comment and docs/modules.md § "Five probes" have
        # always described.
        #
        # Test-LwgModule is still CALLED for every module, and that is not
        # decoration: "eleven resolutions complete without throwing" is the one
        # thing the old probe genuinely established, on the SessionStart path
        # ahead of every hook that depends on it, and dropping it to make room
        # for the new assertion would trade one piece of evidence for another
        # rather than adding one.
        $unresolved = @()
        foreach ($m in $script:LwgModules) {
            $v = Test-LwgModule -Name $m -Config $cfg -Repo $repo
            if ($v -isnot [bool]) { $unresolved += "$m did not resolve to a boolean" }
        }
        $unresolved += @(Get-LwgUnresolvedFlags -Config $cfg -Repo $repo)
        $selfcheck.modules_resolved = ($unresolved.Count -eq 0)
        if ($unresolved.Count -gt 0) {
            $failures += "not a boolean, so it is not a setting - IGNORED, and the module kept its default: $($unresolved -join ', ')"
        }

        # 3. Thresholds yield numbers, so the pressure monitors have something to
        #    compare against rather than falling through to a hardcoded guess.
        $ctxWarn = Get-LwgThreshold -Config $cfg -Group 'context'   -Key 'warn_pct'     -Default $null
        $rlWarn  = Get-LwgThreshold -Config $cfg -Group 'ratelimit' -Key 'warn_pct'     -Default $null
        $selfcheck.thresholds_live = (($ctxWarn -as [int]) -gt 0 -and ($rlWarn -as [int]) -gt 0)
        if (-not $selfcheck.thresholds_live) { $failures += 'thresholds missing or non-numeric' }

        # 4. The payload carries the fields later modules key off. A session_id of
        #    $null means nothing downstream can correlate, so it is a real failure,
        #    not cosmetic. (Absent repo is normal outside a repo - not a failure.)
        $selfcheck.payload_session = -not [string]::IsNullOrWhiteSpace([string]$payload.session_id)
        $selfcheck.payload_cwd     = -not [string]::IsNullOrWhiteSpace([string]$payload.cwd)
        if (-not $selfcheck.payload_session) { $failures += 'payload.session_id empty' }
        if (-not $selfcheck.payload_cwd)     { $failures += 'payload.cwd empty' }

        # 5. State dir is actually writable - proves the log-backed modules can
        #    record, rather than assuming because the directory exists.
        #
        #    -Replace, NOT an append. This fires on every SessionStart - start,
        #    resume, clear and compact - and nothing in the tree rotates,
        #    truncates or READS selfcheck.probe: Invoke-LwgRotate has exactly
        #    one call site and it is passed health.jsonl. It was the only file
        #    this plugin wrote with no bound of any kind, growing by 29 bytes a
        #    session forever, inside a plugin whose log_rotation module reports
        #    itself as capping the logs - an operator reading that module list
        #    would reasonably take it to mean the state files are bounded, and
        #    one of them was not.
        #
        #    The probe's observable contract is unchanged. What it proves is
        #    that the write SUCCEEDED, and the last result is the only one with
        #    any meaning, so the file is now 29 bytes forever and still proves
        #    exactly what it claims to. Rotating it instead would have put a
        #    rotation call on the SessionStart path for a file nobody reads;
        #    writing and deleting a temp file instead would have left
        #    docs/configuration.md's "no selfcheck.probe is written" describing
        #    the wrong thing, since that sentence is about self_health being
        #    OFF.
        $selfcheck.state_writable = (Add-LwgLine -FileName 'selfcheck.probe' -Replace -Line ((Get-Date).ToUniversalTime().ToString('o')))
        if (-not $selfcheck.state_writable) { $failures += 'state dir not writable' }

        $selfcheck.ok = ($failures.Count -eq 0)
    }

    # --- mode ---------------------------------------------------------------
    # The ladder itself lives in common.ps1 (Get-LwgSessionMode) because
    # /lw-watchtower:doctor has to report the same word off the same rules. The mode
    # is the headline of everything this plugin says about itself, so a second
    # copy that drifted would be the loudest lie available to it. Every reason
    # the order is what it is is documented at the function.
    $mode = Get-LwgSessionMode -ActiveCount $activeCount -GateCount $gateCount `
                               -ImplementedCount $implemented.Count `
                               -SelfHealthOn $selfHealthOn -SelfCheckOk $selfcheck.ok

    # --- the trip ledger was opened here -------------------------------------
    # REMOVED 30 JULY 2026 WITH THE LEDGER ITSELF. This branch called
    # Initialize-LwgTripLedger when the live gate count was above zero. It had
    # been dead since the gates went earlier the same day - $activeGates is
    # empty, so it never ran - and it was kept for a while on the argument that
    # it would be correct again the moment a gate came back.
    #
    # That argument died with lib/trips.ps1: there is no Initialize-LwgTripLedger
    # to call any more, so the branch could only have been a dot-source of a file
    # that is not there. A future gate has to bring the ledger back with it, and
    # this is one of the few lines it must restore - see docs/gates-removed.md.
    #
    # One property worth carrying forward if it is: it only ever created a ledger
    # that did NOT already exist. SessionStart fires again on resume, clear and
    # compact, and wiping the ledger on those would clear real outstanding trips
    # on an event that means nothing about them.

    Write-LwgEvent -Event 'SessionStart' -Payload $payload -Extra @{
        source          = $payload.source
        modules_active  = $activeCount
        modules_planned = $plannedCount
        modules_enabled = $enabled.Count
        modules_of      = $totalCount
        gates_on        = $gateCount
        mode            = $mode
        selfcheck       = $selfcheck
        failures        = $failures
    } | Out-Null

    $dot      = [char]0x00B7
    $gateWord = if ($gateCount -eq 1) { 'gate' } else { 'gates' }
    # "active" means implemented AND enabled. Whatever the total holds that is
    # NOT active is stated in the same breath, so the total can never be read as
    # coverage. When both counts are zero the parenthetical is dropped rather
    # than printed as "(0 planned)": active and total are then the same number
    # and there is no remainder to account for, so the phrase would be noise
    # standing where a real caveat used to be. Every non-zero case still prints.
    $splitParts = @()
    if ($plannedCount -gt 0) { $splitParts += "$plannedCount planned" }
    if ($offCount -gt 0)     { $splitParts += "$offCount off" }
    $split    = $(if ($splitParts.Count -gt 0) { ' (' + ($splitParts -join ', ') + ')' } else { '' })
    $banner   = "LW-WATCHTOWER v$version $dot $activeCount/$totalCount modules active$split $dot $gateCount $gateWord $dot $mode"
    # The mode word alone is not enough here. 'unverified' tells a reader that
    # something is missing but not what, and the one thing they need to know is
    # that the omission is deliberate rather than a fault.
    if     (-not $selfHealthOn)      { $banner += " (self_health off - nothing was checked)" }
    elseif ($failures.Count -gt 0)   { $banner += " (" + ($failures[0]) + ")" }

    # additionalContext is model-visible and paid for on every session. It must
    # describe what is running, not what is aspired to - telling the model a
    # rule is enforced when no code enforces it is worse than saying nothing.
    # Keep it under ~70 words.
    $activeList = if ($activeCount -gt 0) { $active -join ', ' } else { 'none' }
    # "no code yet" understates the two blocked modules: their data reaches no
    # hook, so they are not waiting to be written - they cannot be. Saying
    # otherwise would leave the model expecting coverage that will never arrive.
    $blocked  = @(Get-LwgBlockedModules)
    $unbuilt  = $plannedCount - $blocked.Count
    # Implemented but switched off is a THIRD bucket, and it has to be named.
    # The sentence used to read "the other N are not: ..." with N = the planned
    # count, which was correct only while every implemented module was on. With
    # any module deliberately off, active + planned no longer reaches the total,
    # so a reader totting up the names comes up short with no account of the
    # remainder. An unexplained gap in a coverage report is the same defect as an
    # overstated one; it just fails quietly instead of loudly.
    $offList = @()
    foreach ($m in $implemented) { if ($active -notcontains $m) { $offList += $m } }

    $rest = @()
    if ($blocked.Count -gt 0) {
        $rest += "$($blocked.Count) ($($blocked -join ', ')) CANNOT be built - the data they need reaches no hook"
    }
    if ($unbuilt -gt 0)       { $rest += "$unbuilt declared in config.json but unwritten" }
    if ($offList.Count -gt 0) { $rest += "$($offList.Count) ($($offList -join ', ')) built but switched OFF in config.json" }

    $lines = @(
        "LW-WATCHTOWER v$version, mode $mode."
        "Running ($activeCount/$totalCount): $activeList."
    )
    if ($rest.Count -gt 0) {
        $restCount = $totalCount - $activeCount
        $lines += "The other $($restCount): " + ($rest -join '; ') + "."
    }
    # The gate sentence is derived, never hardcoded. Saying "nothing is blocked"
    # while a gate is enforcing is the same class of lie as counting an unbuilt
    # module as coverage - it just points the other way, and it would teach the
    # model to distrust a guardrail that works.
    if ($gateCount -eq 0) {
        # "No gate is LIVE" rather than "no gate exists". One does exist -
        # delegate_gate - and it is simply switched off. Telling the model it
        # does not exist is how an operator who later turns it on gets told
        # their refused call must be a bug in the plugin.
        $lines += "No gate is live, so nothing is blocked or scanned automatically."
        $lines += "Treat this session as unguarded and verify irreversible actions yourself."
    } else {
        $lines += "Live $($gateWord): $($activeGates -join ', ') - these can BLOCK a tool call outright."
        $lines += "Nothing else is checked, so keep verifying irreversible actions yourself."
    }
    $context = $lines -join ' '
    # Three states, not two. "Did not run" is not "passed", and it is not
    # "failed" either - a model told nothing at all would reasonably assume the
    # first, which is exactly the assumption this plugin exists to refuse.
    if (-not $selfHealthOn) {
        $context += " Self-check did NOT run (self_health is off), so none of the above was verified this session - it is what config.json and the module registry DECLARE, not what has been proven to work."
    } elseif (-not $selfcheck.ok) {
        $context += " Self-check DEGRADED ($($failures -join '; ')) - even the above may not fire."
    }

} catch {
    $msg = $_.Exception.Message
    $banner = "LW-WATCHTOWER v$version - ERROR: $msg (governance not loaded)"
    $context = "LW-WATCHTOWER v$version failed to load ($msg). No governance modules are active this session; apply extra caution with destructive and irreversible actions."
    try { Write-LwgEvent -Event 'SessionStartError' -Payload $payload -Extra @{ error = $msg } | Out-Null } catch { }
}

try {
    $out = [ordered]@{
        hookSpecificOutput = [ordered]@{
            hookEventName     = 'SessionStart'
            additionalContext = $context
        }
        systemMessage  = $banner
        suppressOutput = $true
    }
    [Console]::Out.Write((($out | ConvertTo-Json -Depth 6 -Compress)))
} catch {
    # Last resort: a hand-built minimal envelope so the session still sees something.
    [Console]::Out.Write('{"systemMessage":"LW-WATCHTOWER v' + $version + ' - output serialisation failed","suppressOutput":true}')
}

exit 0
