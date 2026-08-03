#requires -version 5
<#
  LW-WATCHTOWER status - what is running, right now.

      powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-status.ps1

  Backs /lw-watchtower:status. This is the SessionStart banner, expanded: the same
  numbers off the same source of truth. Nothing here is recomputed by a second
  method - the module table comes from $LwgModuleRegistry in lib/common.ps1 and
  the counts come from the same Get-Lwg* helpers lib/session_start.ps1 calls, so
  the two can disagree only if the registry itself is wrong.

  Exit codes:

      0  the report printed
      3  the report could not be produced

  There is no exit code for "something is unhealthy". This command reports; it
  does not judge. /lw-watchtower:doctor is the one that fails.

  ONE THING HERE IS NOT LIVE. The mode word depends on whether the SessionStart
  self-check passed, and that is a fact about a SESSION - this script is not one
  and cannot run those probes. So the mode is derived from the newest
  SessionStart record in the event log and is reported WITH the age of that
  record. If no record exists, the mode prints as 'unknown' rather than being
  computed from config alone, because a mode computed without the self-check
  would silently claim a verification that never happened.
#>

param(
    # Print the summary lines only, without the per-module table.
    [switch]$Brief
)

$ErrorActionPreference = 'Stop'

try {
    $pluginRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $pluginRoot 'lib\common.ps1')

    $cfg  = Get-LwgConfig
    # Outside a hook there is no payload, so repo identity comes from the cwd -
    # which is what Get-LwgRepo does with a payload anyway. Per-repo overrides in
    # config.json therefore apply here exactly as they would in a session.
    $repo = (Get-LwgRepoInfo -Path (Get-Location).Path).slug

    $enabled     = @(Get-LwgEnabledModules     -Config $cfg -Repo $repo)
    $active      = @(Get-LwgActiveModules      -Config $cfg -Repo $repo)
    $activeGates = @(Get-LwgActiveGates        -Config $cfg -Repo $repo)
    $implemented = @(Get-LwgImplementedModules)
    $planned     = @(Get-LwgPlannedModules)
    $blocked     = @(Get-LwgBlockedModules)
    $all         = @($script:LwgModules)
    # TWO gate numbers, and collapsing them into one is the whole reason this
    # section exists. $shippedGates is what is DECLARED kind 'gate' in the
    # registry; $activeGates is what is switched on and can refuse a call right
    # now. Reporting only the first would claim protection that is switched off;
    # reporting only the second would hide that a gate exists at all, and an
    # operator cannot turn on a thing they were never told they have.
    $shippedGates = @($script:LwgGates)

    $offList = @($implemented | Where-Object { $active -notcontains $_ })

    # --- mode, and the evidence for it -------------------------------------
    $mode     = 'unknown'
    $modeNote = 'no SessionStart record found - the mode cannot be stated without one'
    $info     = Get-LwgStateDirInfo
    $log      = Join-Path $info.path 'lw-watchtower.jsonl'
    if (Test-Path -LiteralPath $log) {
        $rec = $null
        foreach ($line in @(Get-LwgTailLines -Path $log -Bytes 262144)) {
            try { $r = $line | ConvertFrom-Json } catch { continue }
            if ($r.event -eq 'SessionStart') { $rec = $r }
        }
        if ($null -ne $rec) {
            # Recomputed rather than read back from the record: the counts above
            # are live, the record's are historical, and the mode must describe
            # the config as it stands now. Only the two self-check facts - which
            # this script genuinely cannot observe - are taken from the log.
            $mode = Get-LwgSessionMode -ActiveCount $active.Count -GateCount $activeGates.Count `
                                       -ImplementedCount $implemented.Count `
                                       -SelfHealthOn ([bool]($rec.selfcheck.ran -eq $true)) `
                                       -SelfCheckOk $rec.selfcheck.ok
            $age = $null
            try { $age = ((Get-Date).ToUniversalTime() - ([datetime]$rec.ts).ToUniversalTime()) } catch { }
            $when = if ($null -ne $age) { "{0:N1} h ago" -f $age.TotalHours } else { $rec.ts }
            $modeNote = "self-check evidence from the SessionStart record written $when"
            if ($rec.selfcheck.ran -ne $true) { $modeNote += ' (the self-check did NOT run in that session)' }
        }
    }

    # --- report -------------------------------------------------------------
    Write-Output "LW-WATCHTOWER v$($script:LwgVersion) - mode $mode"
    Write-Output "  $($modeNote)"
    Write-Output ''
    # "declared implemented", NOT "backed by code", and the change is one of
    # accuracy rather than modesty. $active is `enabled in config` AND
    # `$LwgModuleRegistry says status = 'implemented'`. The second half is a
    # string literal in lib/common.ps1; nothing here opens a file. A module whose
    # implementation had been deleted, renamed or moved would still be counted
    # and still print BUILT: yes, so a parenthetical asserting "backed by code"
    # was making a claim about disk that nothing in this command - or, for a
    # module hooks.json does not name, anywhere in this plugin - had checked.
    # The GATES block below now says outright when a registry entry's path is
    # not on disk; the count is left as a count, honestly labelled.
    Write-Output ("  {0} of {1} modules ACTIVE (enabled in config AND declared implemented in the registry)" -f $active.Count, $all.Count)
    Write-Output ("  {0} gate(s) SHIPPED: {1}" -f $shippedGates.Count, $(if ($shippedGates.Count) { $shippedGates -join ', ' } else { 'none - this plugin has no blocking code at all' }))
    Write-Output ("  {0} gate(s) LIVE: {1}" -f $activeGates.Count, $(if ($activeGates.Count) { ($activeGates -join ', ') + ' - these can BLOCK a tool call outright' } else { 'none - nothing can be blocked right now' }))
    # The remainder line accounts for every module that is NOT active. When
    # there is no remainder it says so in one clause rather than printing three
    # zeroes, which reads as a form with nothing filled in rather than as a fact.
    if ($planned.Count -eq 0 -and $offList.Count -eq 0) {
        Write-Output "  0 planned and 0 switched off - every module in the registry is built and enabled"
    } else {
        Write-Output ("  {0} planned ({1} of which are BLOCKED and will not be built), {2} built but switched off" -f $planned.Count, $blocked.Count, $offList.Count)
    }
    Write-Output ("  config: {0}   repo: {1}   state: {2}" -f `
        $(if ($cfg._source -eq 'file') { 'config.json' } else { 'BUILT-IN DEFAULTS (config.json unreadable)' }), `
        $(if ($repo) { $repo } else { '(not in a repo)' }), `
        $(if ($info.resolved) { $info.path } else { "$($info.path) [UNRESOLVED - source '$($info.source)']" }))

    # --- the gates, one paragraph each --------------------------------------
    # Printed even in -Brief. The two counts above are numbers; this is the
    # sentence that stops "1 shipped, 0 live" being read as either "protected"
    # or "there is nothing here". Every fact in it is derived from the registry
    # entry and the live config, so a second gate added later appears here with
    # no edit to this block.
    if ($shippedGates.Count -gt 0) {
        Write-Output ''
        Write-Output '  GATES'
        foreach ($g in $shippedGates) {
            $e    = $script:LwgModuleRegistry[$g]
            $live = $activeGates -contains $g
            $sw   = $e.switch
            $where = if ($null -ne $sw) { "$($sw.block).$($sw.key)" } else { "modules.$g" }
            $dflt  = if ($null -ne $sw) { [bool]$sw.default } else { $true }

            # THE KEY PATH AND THE EFFECTIVE ANSWER ARE NO LONGER JOINED BY AN
            # `=`, and that is the whole of this change. This block used to print
            #
            #     switch  : interaction.delegate = false   (ships OFF BY DEFAULT)
            #
            # where the value beside the key was $live - the answer Test-LwgFlag
            # RESOLVED - spelled in JSON literals, so the line read as a
            # quotation of config.json and was not one. Only a real boolean is a
            # setting: a quoted "true" at that key is ignored by the resolver and
            # the built-in default stands, so the operator could open the file,
            # read `"delegate": "true"`, and have this command tell them
            # `interaction.delegate = false` with nothing on screen saying a
            # written value had been rejected. bin/lwg-config.ps1 already refused
            # to make that mistake, in a comment naming this exact hazard, and
            # this file did not call the helper it wrote for it.
            #
            # So three facts, on three lines: where the switch lives, what is
            # STORED there, and what it RESOLVED to. Format-LwgFlagState is the
            # same renderer /lw-watchtower:config uses, and it has the third word -
            # 'ignored' - that a bare boolean cannot express.
            #
            # WHAT THIS STILL DOES NOT DO: it does not say which SCOPE won. A
            # per-repo override that differs from the global is resolved
            # correctly and reported correctly, and the `in file` line below
            # shows the GLOBAL value only, so on that config the two lines
            # disagree with no explanation. Naming the winning scope is the next
            # step and is not taken here.
            #
            # THE FALLBACK PATH GETS ITS OWN SENTENCE, and it has to, or this
            # fix reproduces the defect it is fixing. Get-LwgConfig FAILS OPEN:
            # an unparseable config.json - or one with no `modules` block -
            # returns Get-LwgDefaultConfig, which carries no `interaction` block
            # at all. Reading $cfg for the stored value on that path yields
            # $null, and printing "not present" would be a second line that
            # reads as a quotation of the file and is not one. The file may well
            # hold a value; it was never read.
            $fromFile  = ($cfg._source -eq 'file')
            $storedRaw = $null
            if ($fromFile) {
                if ($null -ne $sw) {
                    try { $storedRaw = $cfg.($sw.block).($sw.key) } catch { $storedRaw = $null }
                } else {
                    try { $storedRaw = $cfg.modules.$g } catch { $storedRaw = $null }
                }
            }
            $storedText =
                if (-not $fromFile)                { 'NOT READ - config.json did not parse, so this is the built-in default and not the file. See the config: line above' }
                elseif ($null -eq $storedRaw)      { 'not present - the built-in default stands' }
                elseif ($storedRaw -isnot [bool])  { "'$storedRaw' - NOT A BOOLEAN, so it is IGNORED and the built-in default stands" }
                else                               { Format-LwgFlagState $storedRaw }

            Write-Output ("    {0}  {1}" -f $g, $(if ($live) { 'LIVE - it can refuse a tool call right now' } else { 'OFF - it refuses nothing' }))
            Write-Output ("      switch  : {0}   (ships {1})" -f $where, $(if ($dflt) { 'ON' } else { 'OFF BY DEFAULT' }))
            Write-Output ("      in file : {0}" -f $storedText)
            Write-Output ("      resolved: {0}" -f $(if ($live) { 'on' } else { 'off' }))

            # `code:` IS A REGISTRY STRING AND NOW SAYS SO WHEN THE FILE IS NOT
            # THERE. $e.impl is a display field: for delegate_gate it is a path,
            # for log_rotation it is 'lib/common.ps1 (Invoke-LwgRotate), called
            # from lib/supervisor.ps1'. Nothing read the disk, so a gate whose
            # implementation had been deleted still printed its file name under a
            # heading promising the switch would make it LIVE. This command
            # reports and does not judge, so the finding is stated on the line
            # rather than turned into a failure - /lw-watchtower:doctor is where a
            # missing file should become a FAIL row, and it does not check this
            # today either.
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
        Write-Output '    OFF BY DEFAULT IS THE SHIPPED STATE, not a fault and not something to fix'
        Write-Output '    silently. A gate that blocks work the operator did not ask to have blocked'
        Write-Output '    gets the whole plugin disabled, so nothing here arms itself. Turn one on and'
        Write-Output '    the LIVE count above moves with it, and so does the mode word.'
    }

    if (-not $Brief) {
        Write-Output ''
        # STATE is the only column that answers "is this doing anything". The
        # other three exist so that a reader can see WHY, because "off" and
        # "cannot be built" are different facts and a single column would
        # flatten them into the same silence.
        Write-Output '  MODULE                 KIND     BUILT        ENABLED  STATE'
        Write-Output '  ---------------------- -------- ------------ -------- -------------------------'
        foreach ($m in $all) {
            $e    = $script:LwgModuleRegistry[$m]
            $isOn = $enabled -contains $m
            $built = if ($e.blocked -eq $true) { 'BLOCKED' } elseif ($e.status -eq 'implemented') { 'yes' } else { 'no' }
            $state =
                if ($active -contains $m)  { 'ACTIVE' }
                elseif ($e.blocked -eq $true) { 'inert - no hook can supply its data' }
                elseif ($e.status -ne 'implemented') { 'inert - not written yet' }
                # A module switched from outside the `modules` block names the
                # key that actually holds it. "switched off in config" would send
                # a reader to a flag that is not there.
                elseif ($null -ne $e.switch) { "off - $($e.switch.block).$($e.switch.key) is false" }
                else { 'off - switched off in config' }
            Write-Output ('  {0} {1} {2} {3} {4}' -f `
                $m.PadRight(22), $e.kind.PadRight(8), $built.PadRight(12), `
                $(if ($isOn) { 'on' } else { 'off' }).PadRight(8), $state)
        }
        Write-Output ''
        Write-Output '  A flag set to on is an INTENTION. Only the STATE column reports behaviour:'
        Write-Output '  an enabled module with no code behind it is inert, and is counted nowhere'
        Write-Output '  as coverage.'
    }

    exit 0

} catch {
    Write-Output "LW-WATCHTOWER status could not be produced: $($_.Exception.Message)"
    Write-Output 'Nothing above should be read as a description of what is running.'
    exit 3
}
