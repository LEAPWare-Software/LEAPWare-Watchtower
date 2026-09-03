#requires -version 5
<#
  LW-WATCHTOWER shared helpers.

  Dot-sourced by every module script:
      . (Join-Path $PSScriptRoot 'common.ps1')

  Nothing in here may throw at load time and nothing may call exit - the caller
  owns the exit code, and a broken governance layer must never break a session.
#>

# --- canonical module registry --------------------------------------------
# THE single source of truth for what this plugin actually does. config.json
# carries the operator's ON/OFF intent; this table carries reality.
#
# A `true` flag in config.json is a forward-declaration, NOT evidence that code
# exists. Counting those flags is how a monitor ends up reporting every declared
# module as active while some of them are empty names - the exact failure class
# this plugin exists to catch. So status is derived here from the code itself: a
# module is 'implemented' only if a hook actually invokes it and it does
# observable work. Everything else is 'planned'.
#
#   kind    'gate'    can BLOCK an action    'observe'  advisory only
#   status  'implemented' | 'planned'
#   impl    the file that carries the behaviour, $null when there is none
#   events  the hook events this module DEPENDS ON, every one of them a key in
#           hooks/hooks.json. Until 3 September 2026 nothing in this tree
#           related a module to the events it needs, which is why nothing could
#           notice the failure this field exists to make noticeable: three of
#           the eight events registered - SubagentStart, PostToolUseFailure and
#           StopFailure - were read out of the 2.1.220 binary, docs/install.md
#           says in prose that older builds may not carry all of them, and on
#           such a build those registrations are simply inert. The failure mode
#           of an inert hook is SILENCE, indistinguishable from a session in
#           which nothing went wrong - while the banner goes on counting
#           failure_capture and context_injection among the active modules,
#           because it counts the REGISTRY and not observed behaviour.
#           THIS IS THE MAP, NOT THE CHECK. The checks that consume it - a
#           build WARN and a per-event "observed on this machine at least once"
#           row - belong in bin/lwg-doctor.ps1, which already proves that
#           SessionStart genuinely fires by reading the event log, and that
#           file is not this batch's to edit. A banner that reported observed
#           firing per module cannot be built from the current ledger either:
#           the `event` field in lw-watchtower.jsonl carries a SEMANTIC record
#           name (DocsCoupling, GateDeny, ContextPressure), not the hook event,
#           and most modules write nothing at all on the quiet path - so
#           "never observed" would be unreadable from "nothing to report".
#           Making it derivable needs a per-event observation record on every
#           hook path, which spans five files this batch does not own.
#   blocked $true when the module CANNOT be built as specified, not merely has
#           not been - the data it needs reaches no hook. 'Planned' covers both
#           cases and understates this one, so the two are distinguished here
#           and the distinction is what SessionStart tells the model.
#           NO ENTRY CARRIES IT TODAY: ratelimit_escalation and cost_tracking
#           were the only two, and both were removed on 30 July 2026 at the
#           owner's instruction rather than left as switches nothing can honour.
#           The field, Get-LwgBlockedModules and every reader of it are KEPT, so
#           a future entry can state the distinction without reinventing it. Why
#           those two cannot be built is in docs/modules.md, "Attempted and
#           blocked" - read it before adding either name back.
#   note    caveats a reader needs; surfaced in docs/modules.md
#   switch  OPTIONAL. Where this module's on/off flag lives when it is NOT a key
#           in config.json's `modules` block: @{ block; key; default }, read at
#           config.<block>.<key> with a per-repo override at
#           repos[slug].<block>.<key>. An entry declaring one is EXCLUDED from
#           the `modules` parity rule below, because by design it has no
#           `modules` key. FOUR entries use it today - delegate_gate, whose
#           switch is interaction.delegate, the key /lw-watchtower:delegate writes,
#           and the three supervision modules (send_liveness_gate,
#           completion_audit, orphan_watch), whose switches live in the
#           `supervision` block and all default OFF.
#           WHY IT EXISTS AT ALL: the alternative was a second flag,
#           modules.delegate_gate, alongside interaction.delegate. Two switches
#           over one gate means an operator can turn the gate "on" with the
#           command and have it silently do nothing because the other flag is
#           false - a switch wired to nothing, which is the founding defect this
#           plugin exists to catch. One switch, declared here, and
#           bin/lwg-doctor.ps1 asserts the declared key is really in config.json.
#
# Order is the order modules are reported in. The NAME list must stay identical
# to config.json's `modules` keys, EXCEPT for entries that declare a `switch` of
# their own - drift anywhere else silently mis-reports coverage, and
# bin/lwg-doctor.ps1's config-registry check enforces both halves.
# ELEVEN entries, all 'implemented'. Eight are kind 'observe'; delegate_gate,
# send_liveness_gate and completion_audit are kind 'gate' and are the only
# things in this plugin that can block anything. All three gates - and
# orphan_watch, the eighth observer - declare their own `switch` and SHIP OFF.
$script:LwgModuleRegistry = [ordered]@{
    failure_capture      = @{ kind = 'observe'; status = 'implemented'; impl = 'lib/supervisor.ps1'
                              events = @('SessionStart', 'PostToolUseFailure', 'SubagentStop', 'Stop', 'StopFailure')
                              note = 'Five hook events, gated on the flag; exits 2 to alert the orchestrator.' }
    context_pressure     = @{ kind = 'observe'; status = 'implemented'; impl = 'lib/stop_advisories.ps1'
                              events = @('Stop')
                              note = 'context_window is NOT in any hook payload. Occupancy is recomputed from the transcript''s last assistant usage block using the CLI''s own formula. The context window SIZE is not observable, so it is resolved from config/observation and the percentage is suppressed outright when the size is not trustworthy.' }
    self_health          = @{ kind = 'observe'; status = 'implemented'; impl = 'lib/session_start.ps1'
                              events = @('SessionStart')
                              note = 'The SessionStart self-check. Switching it off skips every probe, and the session then reports mode "unverified" rather than any word that implies it was validated - an unrun check must never read as a passed one.' }
    log_rotation         = @{ kind = 'observe'; status = 'implemented'; impl = 'lib/common.ps1 (Invoke-LwgRotate), called from lib/supervisor.ps1'
                              events = @('SessionStart', 'PostToolUseFailure', 'SubagentStop', 'Stop', 'StopFailure')
                              note = 'Runs on its own flag alone. The call sits ABOVE the failure_capture gate in supervisor.ps1, so switching failure capture off stops the writes to health.jsonl but never the cap on its size. A rotation that cannot complete now writes a RotateFailed event to lw-watchtower.jsonl and leaves every archive generation intact - it used to destroy one and report nothing.' }
    docs_coupling        = @{ kind = 'observe'; status = 'implemented'; impl = 'lib/post_edit.ps1, lib/stop_advisories.ps1'
                              events = @('PostToolUse', 'Stop')
                              note = 'PostToolUse records edited paths; Stop compares them. Only files edited THROUGH Edit/Write/NotebookEdit are seen - a file changed by a shell command is invisible.' }
    git_hygiene          = @{ kind = 'observe'; status = 'implemented'; impl = 'lib/stop_advisories.ps1'
                              events = @('Stop')
                              note = 'ADVISORY on Stop - it warns and never blocks. The only module allowed to spawn a subprocess, and it only does so at turn end, inside a repo, with a hard timeout. A git command that fails or times out is reported as UNKNOWN, never as a clean tree. The open-PR check is the one network call, is skipped unless there is unpushed work on a non-default branch, and is skipped loudly when gh is missing or slow.' }
    context_injection    = @{ kind = 'observe'; status = 'implemented'; impl = 'lib/subagent_start.ps1'
                              events = @('SubagentStart')
                              note = 'SubagentStart, once per dispatch. Injects context/worker_facts.md as hookSpecificOutput.additionalContext, because CLAUDE.md is snapshotted into a subagent at PARENT-SESSION start and a mid-session edit never reaches a worker dispatched afterwards. The file is read live on every dispatch, so what a worker gets is current by construction. Deliberately does NOT dot-source this file on its fast path: that plus one ConvertFrom-Json measured 634 ms against a 273 ms interpreter floor, on a hook that every worker in every session pays for.' }
    send_liveness_gate   = @{ kind = 'gate'; status = 'implemented'; impl = 'lib/gate_send.ps1'
                              events = @('PreToolUse')
                              switch = @{ block = 'supervision'; key = 'send_liveness'; default = $false }
                              note = 'OFF BY DEFAULT. PreToolUse on SendMessage: when supervision.send_liveness is on it refuses a send whose recipient it can prove is DEAD MID-FLIGHT - a subagent transcript exists for this session, no SubagentStop record was ever written for it, and the transcript has not been written for stale_minutes (default 15). Built from a measured failure: an orchestrator SendMessage was queued to an agent dead for 28m45s, the "Message queued for delivery" ack was read as done, and the user was told work was complete that never happened. The gate DENIES on positive evidence of death and on an unresolvable recipient; it ABSTAINS (allows, logged) where the evidence layer cannot support a verdict - a `name@team` recipient, or a session health.jsonl has never recorded. Its switch is supervision.send_liveness, NOT a `modules` key, for the same reason as delegate_gate: Get-LwgConfig fails OPEN and a corrupt config must not arm a blocking gate. Requires failure_capture to have been writing SubagentStop records; without them a completed agent is indistinguishable from a dead one and the gate abstains rather than guesses.' }
    completion_audit     = @{ kind = 'gate'; status = 'implemented'; impl = 'lib/gate_stop.ps1'
                              events = @('Stop', 'SubagentStop')
                              switch = @{ block = 'supervision'; key = 'completion_audit'; default = $false }
                              note = 'OFF BY DEFAULT. A turn-end gate, registered on BOTH Stop and SubagentStop and WITHOUT asyncRewake on either, so its exit 2 BLOCKS the turn end. It sat on Stop ALONE until 11 August 2026, and because subagents and teammates emit SubagentStop and never Stop it fired for no worker at all in that period. The two registrations are NOT interchangeable, which is why the file takes a -HookEvent argument: on SubagentStop the payload''s transcript_path is the PARENT''S transcript and the subagent''s own is agent_transcript_path, so a gate reading the former would block a worker for what the ORCHESTRATOR said - in a delegate pattern the common case, not an edge one, and reproduced as a real exit 2 against the pre-fix code. Subagent mode also LIFTS the sidechain skip, because every record of a real subagent transcript carries isSidechain:true and skipping them would leave the gate armed and auditing nothing, and it uses a local turn-boundary test rather than Get-LwgPromptText, whose sidechain rejection was built for mission_drift - a module since removed - and is correctly KEPT in Stop mode. An absent agent_transcript_path degrades to a silent no-op and NEVER falls back to the parent. When supervision.completion_audit is on it refuses to let a turn end whose final assistant text asserts completed work while the turn''s LAST tool action was SendMessage - queued-for-delivery is not delivery and not completion, and nothing after the send could have established anything. It fires ONCE per turn end: on the continuation stop_hook_active is true and it stands down, per the same loop-guard contract every Stop hook here honours - so it forces one round of verification, it cannot force honesty. The claim detection is a REGEX over prose and is stated as such: past-tense completion verbs, suppressed by hedging vocabulary. It will miss claims phrased outside its list and it can misread quoted text; the enumeration is in the file header and in docs/modules.md.' }
    orphan_watch         = @{ kind = 'observe'; status = 'implemented'; impl = 'lib/supervisor.ps1'
                              events = @('Stop', 'SubagentStop')
                              switch = @{ block = 'supervision'; key = 'orphan_watch'; default = $false }
                              note = 'OFF BY DEFAULT. At Stop, reconciles the session''s subagent TRANSCRIPTS against its SubagentStop records in health.jsonl: a transcript with no stop record that has not been written for stale_minutes (default 15) is an ORPHAN - an agent killed mid-flight, which produces NO record anywhere (Get-FailedTasks counts only failed/killed BACKGROUND TASKS in the Stop payload, and a killed subagent appears in that list not at all; a cross-check found FOUR orphans against a health log with zero PostToolUseFailure records in 1,175 entries). Alerts through the supervisor''s existing exit-2 asyncRewake path, deduped per agent through alerted.json. RUNS INSIDE lib/supervisor.ps1 BELOW THE failure_capture GATE, and that coupling is correct rather than convenient: SubagentStop records are what failure_capture writes, and reconciling against records nothing was writing would call every finished agent an orphan. failure_capture off = orphan_watch inert, and the doctor''s module roster counts it from the same registry entry either way - that roster is what is left of the status command, which is deleted.' }
    delegate_gate        = @{ kind = 'gate'; status = 'implemented'; impl = 'lib/gate_delegate.ps1'
                              events = @('PreToolUse')
                              switch = @{ block = 'interaction'; key = 'delegate'; default = $false }
                              note = 'THE ONLY GATE THIS PLUGIN SHIPS, AND IT IS OFF BY DEFAULT. PreToolUse on Edit|Write|NotebookEdit|Bash|PowerShell: when interaction.delegate is on it refuses those five tools for calls that are NOT from a subagent, so the chat session is reserved for talking to the operator and the work goes to workers. Its switch is interaction.delegate - the key /lw-watchtower:delegate writes - and NOT a `modules` key; see the `switch` field above for why one flag rather than two. It decides "subagent" by the PRESENCE of agent_id in the payload and deliberately never looks at agent_type: a settings.json `agent` key gives the MAIN THREAD a non-empty agent_type, so a gate matching on that would read the main thread as a subagent and fail open on exactly the calls it exists to refuse. It carries no exemption, no allowlist and no safety determination of any kind, and nothing it DECIDES consults tool_name, because the matcher in hooks/hooks.json is the single place the tool list lives. It does read payload.tool_name, once, AFTER the decision to refuse, purely to name the refused tool in the message - a payload carrying none is refused identically with the text falling back to "this tool". That is spelled out rather than glossed as "it does not even read tool_name", which is what this note said until 3 August 2026 and is not true of lib/gate_delegate.ps1. Over-blocking it accepts, stated rather than left to be found: with it on, /lw-watchtower:delegate off cannot turn it off from the main thread, because that command runs through Bash. The deny text names the two ways out. COST: the hook runs on all five tools whether the switch is on or off - the figures below were not re-measured when PowerShell joined the matcher on 1 August 2026, since adding a tool changes how many calls are charged rather than what a call costs. That is true NOW and was not true when it was written: both hook-identity functions in bin/lwg-setup.ps1 key on the matcher STRING, so widening it made every v0.3.0 registration unrecognisable and setup added a SECOND PreToolUse group beside it - two gate runs per call, on a machine whose operator never armed the switch. $script:LwgSupersededMatchers in that file now maps the old spelling to the current one, and tests/setup_merge.ps1 pins both that the gate ends up registered exactly once and that the stale matcher is reported rather than silently accepted. See docs/limitations.md. With the switch OFF it is ~436 ms against a ~294 ms interpreter floor - one machine''s medians, so ~142 ms of it is the gate''s own work, paid by an operator who never turns it on. That was ~652 ms until a raw-text fast path landed on 31 July 2026. With the switch ON it is ~868 ms, SLOWER than before, because the fast path runs, fails to prove the switch off, and the slow path then does everything it always did - that cost falls on the operator who armed the gate, on a call being blocked anyway. See docs/modules.md for the run.' }
}

# Both derived from the registry so there is only one list to keep correct.
$script:LwgModules = @($script:LwgModuleRegistry.Keys)

# The subset whose on/off flag is NOT a `modules` key - see the `switch` field.
# Named here rather than re-derived at each call site: the doctor's parity check
# and the built-in fallback config both have to agree on which names are exempt
# from the `modules` block, and two copies of that answer is one too many.
$script:LwgSwitchModules = @()
foreach ($k in $script:LwgModuleRegistry.Keys) {
    if ($null -ne $script:LwgModuleRegistry[$k].switch) { $script:LwgSwitchModules += $k }
}

# Gates are the subset that can BLOCK an action rather than merely observe it.
# This is the DECLARED set - membership says nothing about whether the gate is
# switched ON. Use Get-LwgActiveGates for the count a banner may honestly show.
#
# IT HOLDS THREE NAMES: delegate_gate (30 July 2026, added after a period with
# none at all - destructive_gate and then secret_scan were removed earlier that
# day at the owner's instruction), and send_liveness_gate + completion_audit
# (1 August 2026, built from the measured queued-message-reported-as-done
# failure). All three SHIP SWITCHED OFF. The loop below is kept rather than
# replaced with a literal because the registry stays the single source of the
# answer - set kind = 'gate' on an entry and the count, the mode word and the
# banner all follow on their own.
$script:LwgGates = @()
foreach ($k in $script:LwgModuleRegistry.Keys) {
    if ($script:LwgModuleRegistry[$k].kind -eq 'gate') { $script:LwgGates += $k }
}

$script:LwgVersion = '0.4.0'

# The Claude Code build the eight hook events in hooks/hooks.json were read out
# of. docs/install.md states it in a table cell, in prose, and NOTHING acted on
# it: no check anywhere in bin/, lib/ or statusline/ read the OS or the CLI
# build - a repository-wide search for IsWindows, OSVersion.Platform,
# `claude --version` and CLAUDE_CODE_VERSION returned nothing at all. A number
# only a person can read is not a number a check can use, so it is spelled here
# once and bin/lwg-doctor.ps1's build row - which belongs to another batch -
# can compare against it rather than carry a second copy.
$script:LwgVerifiedBuild = '2.1.220'

$script:LwgPlatformInfo = $null

function Get-LwgPlatformInfo {
    <#
      The machine and the CLI build this is running on. Returns a HASHTABLE:

        @{ os; is_windows; supported; ps_version; ps_edition;
           claude_version; verified_build; build_known }

        supported       $false on anything but Windows. hooks/hooks.json invokes
                        `powershell` by that name in all thirteen registrations
                        and every path composed here is NTFS-shaped, so a
                        non-Windows machine is a silent non-install rather than
                        a degraded one. .claude-plugin/plugin.json opens with
                        "WINDOWS ONLY" and nothing enforced it.
        claude_version  $env:CLAUDE_CODE_VERSION when the CLI sets it, $null
                        otherwise - and $null is reported as $null. Shelling out
                        to `claude --version` was rejected: this is called from
                        a SessionStart hook, and a subprocess on a hook path to
                        learn a string is the cost this plugin refuses
                        everywhere else. A caller that needs the build and does
                        not have it must say it does not have it, which is what
                        build_known is for.
        build_known     whether claude_version was actually observed. Three
                        states, not two: an unread version must not render as
                        "read, and it matched".

      Memoised; -Refresh re-runs it. Never throws.
    #>
    param([switch]$Refresh)

    if (-not $Refresh -and $null -ne $script:LwgPlatformInfo) { return $script:LwgPlatformInfo }

    $info = @{
        os = 'unknown'; is_windows = $false; supported = $false
        ps_version = ''; ps_edition = ''
        claude_version = $null; verified_build = $script:LwgVerifiedBuild; build_known = $false
    }
    try {
        # [Environment]::OSVersion.Platform and NOT the automatic $IsWindows:
        # that variable does not exist in Windows PowerShell 5.1, which is the
        # only interpreter hooks/hooks.json ever invokes, so reading it there
        # yields $null and a plugin that cannot tell where it is running.
        $p = ''
        try { $p = [string][Environment]::OSVersion.Platform } catch { }
        $info.is_windows = ($p -like 'Win*')
        $info.os = $(if ($info.is_windows) { 'windows' }
                     elseif ($p -eq 'Unix') { 'unix' }
                     elseif ([string]::IsNullOrWhiteSpace($p)) { 'unknown' }
                     else { $p.ToLowerInvariant() })
        $info.supported = $info.is_windows
        try { $info.ps_version = [string]$PSVersionTable.PSVersion } catch { }
        try { $info.ps_edition = [string]$PSVersionTable.PSEdition } catch { }
        if (-not [string]::IsNullOrWhiteSpace($env:CLAUDE_CODE_VERSION)) {
            $info.claude_version = [string]$env:CLAUDE_CODE_VERSION
            $info.build_known    = $true
        }
    } catch { }

    $script:LwgPlatformInfo = $info
    return $info
}

function Get-LwgPluginRoot {
    <# Plugin root = the parent of lib/. CLAUDE_PLUGIN_ROOT when Claude Code sets it. #>
    if ($env:CLAUDE_PLUGIN_ROOT -and (Test-Path $env:CLAUDE_PLUGIN_ROOT)) { return $env:CLAUDE_PLUGIN_ROOT }
    return (Split-Path -Parent $PSScriptRoot)
}

# --- the Claude Code configuration directory -------------------------------
# CLAUDE_CONFIG_DIR relocates Claude Code's configuration directory away from
# ~/.claude. UNTIL THIS FUNCTION EXISTED, NOTHING IN THIS REPOSITORY READ IT.
# Every path in the plugin was composed from $env:USERPROFILE and a literal
# `.claude`, so on a machine where that variable is set the plugin installed
# to, read from, reported on and uninstalled from a directory the CLI does not
# use - and each component failed differently and silently while doing it: the
# installer wrote hooks into a settings.json nothing loads and reported success,
# the doctor health-checked that same unread file and reported green, the
# uninstaller reported a footprint from the wrong tree, and the status line
# rendered off a data root nothing had ever written to.
#
# THE PRECEDENCE, and why it is this way round:
#
#   1. An EXPLICIT PARAMETER - -ClaudeHome, -SettingsPath, -DataRoot on the
#      bin/ scripts - beats everything. It is the test seam, it is how the
#      removal paths are exercised without touching a real machine, and a
#      caller that names a path outright has said something no environment
#      variable should be able to overrule.
#   2. $env:CLAUDE_PLUGIN_DATA, for the DATA directory only. It names the exact
#      directory Claude Code handed this plugin's hook. CLAUDE_CONFIG_DIR names
#      a tree one would be DERIVED from, so the more specific signal wins; under
#      a hook the two agree by construction, and the only callers where they can
#      disagree are the three that are never given CLAUDE_PLUGIN_DATA at all
#      (statusline.ps1, an agent-run resolver, an out-of-harness test).
#   3. $env:CLAUDE_CONFIG_DIR - this function.
#   4. $env:USERPROFILE + `.claude`, the historical default.
#
# THE THREE AWKWARD VALUES ARE SETTLED HERE and not left for each caller to get
# differently wrong:
#
#   trailing separator   trimmed. `C:\cfg\` and `C:\cfg` must not resolve to two
#                        directories, and [IO.Path]::Combine on the first
#                        produces a doubled separator that string comparisons
#                        elsewhere then fail to match. A bare drive keeps its
#                        root separator - `C:` alone is a drive-RELATIVE path in
#                        Windows and means something else entirely.
#   relative value       made absolute with [IO.Path]::GetFullPath, which
#                        resolves against [Environment]::CurrentDirectory - the
#                        PROCESS working directory, not PowerShell's $PWD. A
#                        relative config dir is a misconfiguration either way;
#                        resolving it means the path this plugin reports is the
#                        path it used.
#   names nothing        RETURNED AS GIVEN, with exists = $false. Falling back
#                        to the profile because the named directory is missing
#                        would silently reinstate the whole defect on exactly
#                        the machine that set the variable - and it would do it
#                        at the moment the operator most needs to be told the
#                        directory is not there. `exists` is what a caller
#                        reports; it is not a reason to resolve somewhere else.
#
# An unset, empty or whitespace-only value is not a value: resolution continues
# to the profile, which is the same rule Test-LwgFlag applies to config.json.

$script:LwgClaudeHomeInfo = $null

function Get-LwgClaudeHomeInfo {
    <#
      Claude Code's configuration directory and HOW it was arrived at. Returns
      a HASHTABLE - the same shape and for the same reason as
      Get-LwgStateDirInfo, which see:

        @{ path; source; exists; raw }

        path    the directory to use. $null only when neither CLAUDE_CONFIG_DIR
                nor USERPROFILE holds anything, which is a machine with no home
                at all and is reported rather than guessed at.
        source  'env' | 'profile' | 'unresolved'
        exists  whether that directory is actually there. A caller that reports
                a root must be able to say "and it is not there".
        raw     the unnormalised CLAUDE_CONFIG_DIR value when source is 'env',
                so a report can show what the operator actually set.

      Memoised for the life of the process; -Refresh re-runs it. Never throws.
      No cmdlets: this file is dot-sourced by the blocking PreToolUse gate.
    #>
    param([switch]$Refresh)

    if (-not $Refresh -and $null -ne $script:LwgClaudeHomeInfo) { return $script:LwgClaudeHomeInfo }

    $info = @{ path = $null; source = 'unresolved'; exists = $false; raw = $null }
    try {
        $v = $env:CLAUDE_CONFIG_DIR
        if (-not [string]::IsNullOrWhiteSpace($v)) {
            $info.raw    = $v
            $info.source = 'env'
            $t = $v.Trim().TrimEnd([char[]]@('\', '/'))
            # `C:` is drive-relative, not the root of C:. Put the separator back.
            if ($t.Length -eq 2 -and $t[1] -eq ':') { $t = $t + '\' }
            if ($t.Length -gt 0) {
                try { $t = [IO.Path]::GetFullPath($t) } catch { }
                # GetFullPath leaves a trailing separator on a root only, which
                # is correct there and would be wrong anywhere else.
                if ($t.Length -gt 3) { $t = $t.TrimEnd([char[]]@('\', '/')) }
            }
            $info.path = $t
        }
        else {
            $p = $env:USERPROFILE
            if (-not [string]::IsNullOrWhiteSpace($p)) {
                $info.path   = [IO.Path]::Combine($p.TrimEnd([char[]]@('\', '/')), '.claude')
                $info.source = 'profile'
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($info.path)) {
            try { $info.exists = [IO.Directory]::Exists($info.path) } catch { }
        }
    } catch { }

    $script:LwgClaudeHomeInfo = $info
    return $info
}

function Get-LwgClaudeHome {
    <#
      The configuration directory as a plain path string - the form every path
      composition wants. Use Get-LwgClaudeHomeInfo when you need to REPORT which
      root was resolved and why, which /lw-watchtower:doctor and the uninstaller
      both must: a green health check on a directory nothing reads is worse than
      no check, because it converts a broken install into an attested one.
    #>
    return (Get-LwgClaudeHomeInfo).path
}

# --- state directory -------------------------------------------------------
# Mutable state lives in the data dir, never in the plugin root - the plugin
# root is a git working tree and writing to it would dirty the repo.
#
# CLAUDE_PLUGIN_DATA is authoritative and is what Claude Code hands a plugin
# HOOK. Three things that run this code are NOT hooks and are therefore never
# given it: statusline.ps1 (a settings.json command), lib/resolve.ps1 (run by an
# agent - agents get no plugin env either, verified), and any out-of-harness
# test run. All three took the fallback, and the fallback was a hardcoded
# `lw-watchtower`.
#
# That name is wrong. The plugin is auto-discovered out of the skills dir as
# `lw-watchtower@skills-dir`, so the data dir Claude Code actually creates and hands
# its hooks is `lw-watchtower-skills-dir`. Every fallback caller therefore read and
# wrote a directory the live plugin never touches, while believing it had
# succeeded - which is how the status line rendered unconditional green off an
# empty log, and how the healer wrote a `Resolved` marker into the wrong file
# for the wrong session and reported that HH was back to green.
#
# THE SELECTION RULE
#
#   1. $env:CLAUDE_PLUGIN_DATA wins outright when set. source 'env'.
#   2. Otherwise, look under <claude home>\plugins\data for directories named
#      <name> or <name>-*, where <name> is read from .claude-plugin/plugin.json
#      (see Get-LwgPluginName) rather than spelled out here, and <claude home>
#      comes from Get-LwgClaudeHome rather than from $env:USERPROFILE and a
#      literal `.claude`. That composition was hardcoded here until 3 September
#      2026 and it is why CLAUDE_CONFIG_DIR was honoured by nothing: step 1 is
#      the branch every live HOOK takes, so a relocated config directory only
#      ever broke the callers Claude Code does not hand CLAUDE_PLUGIN_DATA to -
#      the status line, an agent-run resolver, and every test - which is exactly
#      the population that then reported success against a directory nothing
#      writes. The precedence and the three awkward values are settled at
#      Get-LwgClaudeHomeInfo; see the block above it.
#   3. A SUFFIXED candidate (<name>-*) wins over the bare <name>. Claude Code
#      names a plugin's data dir <plugin-name>-<source-id>, and a plugin always
#      has a source, so the live dir is always suffixed. The bare name is not a
#      name Claude Code produces at all - it can only have been created by this
#      very fallback. source 'discovered'.
#   4. Several suffixed candidates - two installs of the same plugin from
#      different sources - are broken by most-recently-written, then by ordinal
#      name order so the result is deterministic even on identical timestamps.
#   5. No suffixed candidate: fall back to the bare path. source 'bare' if that
#      directory already exists, 'unresolved' if nothing matched at all. BOTH
#      report resolved = $false.
#
# Why the suffix test and not simply "most recently written":
# most-recently-written is defeated by exactly the bug it would be fixing. Out-
# of-harness runs keep taking this fallback and appending to the BARE dir, so
# the dead directory routinely carries the newer mtime - at the time of writing
# it did. Excluding the bare dir first is what makes mtime safe to use at all;
# it now only ever chooses between two REAL installs, never between a real one
# and the fallback's own leftovers. (statusline.ps1 has the same problem and
# solves it differently - it reads the union of every match and filters records
# by session id - because a reader can afford to read both and a writer cannot
# write to both.)
#
# Nothing is migrated, moved or deleted. The bare dir is simply no longer
# preferred; its contents stay where they are.
#
# THE SAME SENTENCE GOVERNS THE 3 AUGUST 2026 PRODUCT RENAME, and it is the
# reason this block still spells only ONE name. The plugin id went from
# `lw-gmhh` to `lw-watchtower`, and because step 2 reads that id out of
# plugin.json, the directory this resolves to moved with it. A machine that ran
# the old build keeps its `lw-gmhh*` directory and its `lw-gmhh.jsonl`, and
# NOTHING HERE READS OR WRITES THEM ANY MORE - not the resolver, not the status
# line, not the healer. That is deliberate rather than an oversight: a resolver
# that also matched a legacy name would be a writer with two directories it
# could pick between, which is the exact shape of the defect described three
# paragraphs up. The old name is resolved by exactly one component, and that
# component only READS: $script:LwgLegacyDataNames in bin\lwg-uninstall.ps1, so
# a removal reports the stranded directory instead of walking past it - and,
# stated because it is a widening of a destructive flag, -RemoveData reaches it
# too. (The string also appears in prose here and in the docs; what is true of
# exactly one place is the resolution.) What that costs an existing
# install is written out in full under `## [0.4.0]` in CHANGELOG.md; it is
# stated once there rather than paraphrased at each of the sites it touches.
#
# The plugin ID is only PARTLY derivable, which is why step 2 is a prefix match
# and not a lookup. plugin.json carries `name` and nothing else identifying -
# no source, no id. hooks.json only ever substitutes ${CLAUDE_PLUGIN_ROOT},
# which is the git checkout and carries no id in its path. The `@skills-dir`
# half exists on disk in exactly one place, ~/.claude.json's `pluginUsage` map,
# and that is a usage COUNTER keyed by whatever was last invoked, not a registry
# of installed plugins - resolving a write path from a 46 KB telemetry blob
# would be both a 150 ms JSON parse on the gate path and a guess wearing a
# source's clothes. So: the half that is derivable is derived, the half that is
# not is matched by prefix, and the caller is told which case it got.

$script:LwgPluginName   = $null
$script:LwgStateDirInfo = $null

function Get-LwgPluginName {
    <#
      This plugin's own name, out of .claude-plugin/plugin.json - the same file
      Claude Code reads. Memoised. Returns '' when it cannot be read, and the
      caller then falls back to the historical literal.

      Parsed by string index rather than ConvertFrom-Json deliberately. This is
      on the PreToolUse path, and the cmdlet's FIRST use in a fresh PowerShell
      5.1 process measured 159 ms on this machine against ~8 ms for
      ReadAllText. No regex either - the regex engine carries the same
      first-use cost, for a job two IndexOf calls already do.
    #>
    if ($null -ne $script:LwgPluginName) { return $script:LwgPluginName }

    $name = ''
    try {
        $p = [IO.Path]::Combine((Get-LwgPluginRoot), '.claude-plugin\plugin.json')
        if ([IO.File]::Exists($p)) {
            $txt = [IO.File]::ReadAllText($p)
            # `name` is the first key in the file; take the first string value
            # after it. A malformed file yields '' and the caller copes.
            $i = $txt.IndexOf('"name"')
            if ($i -ge 0) {
                $c = $txt.IndexOf(':', $i + 6)
                if ($c -ge 0) {
                    $a = $txt.IndexOf('"', $c + 1)
                    $b = if ($a -ge 0) { $txt.IndexOf('"', $a + 1) } else { -1 }
                    if ($b -gt $a) { $name = $txt.Substring($a + 1, $b - $a - 1) }
                }
            }
        }
        # It has to be usable as ONE directory name and as a search pattern.
        # Anything else - a separator, a wildcard, a drive colon - would either
        # throw out of [IO.Path]::Combine or turn the glob into a search of some
        # other directory, so it is discarded and the caller uses the literal.
        if ($name.IndexOfAny([char[]]@('\', '/', ':', '*', '?', '"', '<', '>', '|')) -ge 0) { $name = '' }
    } catch { }

    $script:LwgPluginName = $name
    return $name
}

# --- where a marketplace install actually lives ----------------------------
# TWO FILES PROBED ~\.claude\plugins\repos TO DECIDE THIS, AND THAT DIRECTORY
# DOES NOT EXIST. Measured on a live Claude Code install: plugins\ holds
# blocklist.json, cache, data, installed_plugins.json, known_marketplaces.json,
# marketplaces and plugin-catalog-cache.json - and no `repos`. Marketplace
# installs live under
#
#     plugins\cache\<marketplace>\<plugin>\<version-or-sha>\
#
# which is THREE levels below cache, not one below a directory that is never
# created, and plugins\installed_plugins.json records the resolved installPath
# outright, keyed `<plugin>@<marketplace>` and carrying the install `scope`.
#
# [IO.Directory]::Exists on a directory that is never created returns $false
# unconditionally, so the probe was not merely wrong, it was CONSTANT - and the
# boolean it produced drove five decisions at once in bin/lwg-setup.ps1: the
# "NOT DISCOVERABLE ... so not one of its hooks fires" report, the standalone
# recommendation, the standalone default under -HookMode auto, the second full
# copy of every hook registration written into settings.json, and - gated on
# the SAME boolean - the DUPLICATE-FIRING WARNING that exists to stop exactly
# that. The safeguard was disarmed by the identical bug that created the hazard.
# statusline/statusline.ps1 spelled the same constant and rendered purple `HH?`,
# documented as "not installed", on an installed and working plugin.
#
# THE CONSTANT IS SPELLED ONCE, HERE, because it was spelled twice and was wrong
# in both. The status line deliberately dot-sources nothing, for render cost, so
# if it must keep its own copy the two have to cross-reference each other in
# comment - that is stated in the issue and is a job for the batch that owns
# that file.
#
# THAT BATCH LANDED, AND THERE ARE THREE SPELLINGS, NOT TWO. Recorded here so
# this block is not read as the only one:
#
#   HERE  the resolver. The only spelling that reads
#       plugins\installed_plugins.json, the CLI's own record of what it
#       installed and where, so it is layout-independent and carries the install
#       SCOPE. For callers that can afford a dot-source.
#   bin\lwg-setup.ps1  Get-Detection  a SUPERSET: that registry read plus cache,
#       marketplaces, marketplaces\<mk>\plugins and legacy repos, each narrowed
#       to the plugin name, honouring CLAUDE_CODE_PLUGIN_CACHE_DIR, and emitting
#       a sentence of evidence per hit - because its verdict decides whether
#       setup writes a SECOND full set of hook registrations, and a verdict that
#       consequential has to be arguable. It is deliberately NOT routed through
#       this function: doing so would NARROW what the installer can see, which
#       is the inverse of the defect #8 is about.
#   statusline\statusline.ps1  LwgPluginRoots  candidate ROOTS rather than a
#       verdict, and no dot-source at all - it runs on every assistant message,
#       and that cost is measured in that file's LwgClaudeHome block.
#
# A change to the layout lands in all three. The layout itself is argued once,
# in the paragraphs above.
#
# THIS RESOLVER READS AND NEVER GUESSES. installed_plugins.json first, because
# it is the CLI's own record of the answer, it survives a layout change, and it
# carries the scope. The cache walk is the fallback for a machine whose record
# is missing or unreadable, and it matches on the PLUGIN NAME rather than
# counting any directory - counting is how a marketplace holding somebody else's
# plugin would read as an install of this one. `probed` comes back with the
# paths that were actually looked at, so a caller can say WHERE it looked:
# "I COULD NOT FIND IT" IS NOT "IT IS NOT THERE", which is a rule this project
# has already written down once, in lib/gate_delegate.ps1.

$script:LwgMarketplaceInfo = $null

function Get-LwgMarketplaceInstall {
    <#
      Is this plugin installed from a marketplace, and where? Returns a
      HASHTABLE:

        @{ installed; source; paths; scopes; probed; home }

        installed  $true only when a real install was IDENTIFIED
        source     'installed_plugins' | 'cache' | 'none' | 'unknown'
                   'unknown' means no configuration root could be resolved at
                   all, which is not the same as "no install" and must not be
                   reported as one
        paths      the resolved install root(s)
        scopes     the `scope` values installed_plugins.json recorded for them,
                   which distinguishes a project-scoped install from a user one
        probed     the paths this function actually looked at
        home       the configuration root it looked under

      Memoised; -Refresh re-runs it. Never throws. NOT on any hook fast path -
      its callers are the installer, the doctor and the status line - so a
      ConvertFrom-Json here costs nothing a gate pays for.
    #>
    param([switch]$Refresh)

    if (-not $Refresh -and $null -ne $script:LwgMarketplaceInfo) { return $script:LwgMarketplaceInfo }

    $info = @{ installed = $false; source = 'unknown'; paths = @(); scopes = @(); probed = @(); home = $null }
    try {
        $home_ = Get-LwgClaudeHome
        $info.home = $home_
        if ([string]::IsNullOrWhiteSpace($home_)) {
            $script:LwgMarketplaceInfo = $info
            return $info
        }

        $name = Get-LwgPluginName
        if ([string]::IsNullOrWhiteSpace($name)) { $name = 'lw-watchtower' }

        # 1. the CLI's own record.
        $reg = [IO.Path]::Combine($home_, 'plugins\installed_plugins.json')
        $info.probed += $reg
        $paths  = @()
        $scopes = @()
        try {
            if ([IO.File]::Exists($reg)) {
                $json = [IO.File]::ReadAllText($reg) | ConvertFrom-Json
                # THE MAP IS NESTED. Measured on a live install:
                #
                #     { "version": 2,
                #       "plugins": { "static-analysis@trailofbits": [ { scope,
                #                    projectPath, installPath, version, ... } ] } }
                #
                # so the plugin entries are under `plugins` and the top level
                # holds a schema version beside it. Reading the top level as the
                # map matches nothing - `version` and `plugins` are not
                # `<plugin>@<marketplace>` - and this function would then fall
                # silently through to the cache walk, reporting source 'cache'
                # on a machine whose CLI recorded the answer outright and losing
                # the `scope` that distinguishes a project install from a user
                # one. That is a resolver quietly taking its weaker branch,
                # which is the shape of the defect this whole function replaces.
                # The top level is still read when there is no `plugins` member,
                # so a file written to a schema this has not seen degrades to the
                # flat reading rather than to nothing.
                $map = $json
                try { if ($null -ne $json.PSObject.Properties['plugins']) { $map = $json.plugins } } catch { }
                foreach ($p in $map.PSObject.Properties) {
                    # `<plugin>@<marketplace>`. Split on the LAST '@' so a
                    # plugin name that carries one does not lose its tail.
                    $at = $p.Name.LastIndexOf('@')
                    $pn = if ($at -ge 0) { $p.Name.Substring(0, $at) } else { $p.Name }
                    if ($pn -ne $name) { continue }
                    foreach ($e in @($p.Value)) {
                        $ip = [string]$e.installPath
                        if ([string]::IsNullOrWhiteSpace($ip)) { continue }
                        $paths  += $ip
                        $scopes += [string]$e.scope
                    }
                }
            }
        } catch { }
        if ($paths.Count -gt 0) {
            $info.installed = $true; $info.source = 'installed_plugins'
            $info.paths = $paths; $info.scopes = $scopes
            $script:LwgMarketplaceInfo = $info
            return $info
        }

        # 2. the cache layout, as a fallback.
        $cache = [IO.Path]::Combine($home_, 'plugins\cache')
        $info.probed += $cache
        $found = @()
        try {
            if ([IO.Directory]::Exists($cache)) {
                foreach ($mkt in [IO.Directory]::GetDirectories($cache)) {
                    $pdir = [IO.Path]::Combine($mkt, $name)
                    if (-not [IO.Directory]::Exists($pdir)) { continue }
                    $vers = @()
                    try { $vers = @([IO.Directory]::GetDirectories($pdir)) } catch { }
                    # A version directory is the plugin ROOT. With none, the
                    # plugin directory itself is the best answer available and
                    # is reported rather than discarded.
                    if ($vers.Count -gt 0) { $found += $vers } else { $found += $pdir }
                }
            }
        } catch { }
        if ($found.Count -gt 0) {
            $info.installed = $true; $info.source = 'cache'; $info.paths = $found
        } else {
            $info.source = 'none'
        }
    } catch { }

    $script:LwgMarketplaceInfo = $info
    return $info
}

function Get-LwgStateDirInfo {
    <#
      Resolve the state dir and SAY HOW. Returns a HASHTABLE:

        @{ path; source; resolved; candidates }

        path        the directory to use (not created here - see Get-LwgStateDir)
        source      'env' | 'discovered' | 'bare' | 'unresolved'
        resolved    $true only for 'env' and 'discovered'; $false means the path
                    is a GUESS and may well be a directory nothing else writes to
        candidates  how many <name>* directories were seen
        home        the configuration root the search was made under, and
        home_source how that root was arrived at - 'env' (CLAUDE_CONFIG_DIR),
                    'profile', 'unresolved', or 'not-consulted' when
                    CLAUDE_PLUGIN_DATA answered outright and no config root was
                    needed. Both are ADDED KEYS: every existing reader takes
                    .path, .source, .resolved and .candidates by name, so this
                    widens the hashtable without moving anything in it. They are
                    here because a component that reports a resolved state
                    directory and cannot say which configuration root it came
                    from cannot tell a correct install from one pointed at a
                    tree nothing reads.

      The resolved flag exists because three separate failures this repo has
      already shipped were things reporting success while writing nowhere. A
      caller that cares - a monitor, the healer - can now tell "this is the live
      dir" from "this is where I would have looked".

      A hashtable, deliberately: PowerShell enumerates a returned collection but
      NOT a returned hashtable, so this survives the function boundary intact.

      Memoised for the life of the process; -Refresh re-runs the scan. Hooks are
      one-shot processes, so a mid-process change to CLAUDE_PLUGIN_DATA is not a
      case that arises outside the test suite. Never throws.
    #>
    param([switch]$Refresh)

    if (-not $Refresh -and $null -ne $script:LwgStateDirInfo) { return $script:LwgStateDirInfo }

    $info = @{ path = $null; source = 'unresolved'; resolved = $false; candidates = 0
               home = $null; home_source = 'not-consulted' }

    # 1. an explicit CLAUDE_PLUGIN_DATA is authoritative and ends the matter.
    #    The configuration root is deliberately NOT resolved on this branch: it
    #    is the branch every live hook takes, it would add a stat call to it,
    #    and 'not-consulted' is the true answer rather than a missing one.
    $env_ = $env:CLAUDE_PLUGIN_DATA
    if (-not [string]::IsNullOrWhiteSpace($env_)) {
        $info.path = $env_; $info.source = 'env'; $info.resolved = $true
        $script:LwgStateDirInfo = $info
        return $info
    }

    try {
        $name = Get-LwgPluginName
        # The historical literal, kept as a last resort ONLY - it is the base
        # name, never the suffixed one, so this is not a second brittle spelling
        # of the live directory.
        if ([string]::IsNullOrWhiteSpace($name)) { $name = 'lw-watchtower' }

        # [IO.Path]::Combine rather than Join-Path throughout: Join-Path is a
        # cmdlet, and three of them cost ~15-25 ms of the cold path measured
        # here, for string work a static does for free.
        # -Refresh carries THROUGH to the configuration root. A caller that
        # re-runs this scan after changing the environment - which is what
        # every -Refresh call site in tests/ is doing - would otherwise get a
        # fresh data-dir scan made under a stale config root.
        $homeInfo         = Get-LwgClaudeHomeInfo -Refresh:$Refresh
        $info.home        = $homeInfo.path
        $info.home_source = $homeInfo.source
        # Combine throws on a $null first argument rather than composing a
        # half-path, and the catch below is what turns that into 'unresolved'
        # with $info.path still $null - which is the honest answer on a machine
        # with neither CLAUDE_CONFIG_DIR nor USERPROFILE.
        $root = [IO.Path]::Combine($homeInfo.path, 'plugins\data')
        $bare = [IO.Path]::Combine($root, $name)
        $info.path = $bare   # the guess, until something better is found

        # [IO.Directory] rather than Get-ChildItem/Test-Path: the cmdlets pull in
        # the Management module on first use (~40 ms measured for Test-Path
        # alone) and this file is dot-sourced by the blocking gate.
        $cands = @()
        try { $cands = @([IO.Directory]::GetDirectories($root, ($name + '*'))) } catch { }
        $info.candidates = $cands.Count

        # Win32 wildcard matching can also hit 8.3 short names, so the prefix is
        # re-checked in managed code rather than trusted from the pattern. The
        # check is against the full path, not the leaf, so it needs no
        # [IO.Path]::GetFileName call per candidate - GetDirectories returns
        # paths rooted at $root, so "$bare-" is the same test on either.
        $pfx = $bare + '-'
        $suffixed = @()
        foreach ($d in $cands) {
            if ($d.StartsWith($pfx, [StringComparison]::OrdinalIgnoreCase)) { $suffixed += $d }
        }

        if ($suffixed.Count -eq 1) {
            # The overwhelmingly common case, and it costs no stat call at all.
            $info.path = $suffixed[0]; $info.source = 'discovered'; $info.resolved = $true
        }
        elseif ($suffixed.Count -gt 1) {
            # Rank by the newest write seen ANYWHERE in the candidate: its own
            # mtime, or any file it holds, whichever is later.
            #
            # The directory mtime alone is not that measure and ranking on it
            # was wrong. NTFS stamps a directory when an ENTRY is created,
            # renamed or removed - not when an existing file inside it is
            # appended to. The steady state of this ledger is appending to
            # lw-watchtower.jsonl and health.jsonl, both of which already exist, so
            # the live directory's own mtime freezes at whenever it last gained
            # a NEW file. A candidate nothing writes to, that happened to gain
            # one advisory-<id>.json an hour ago, then looks NEWER than the
            # directory sessions are appending to right now.
            #
            # Observed on this machine with three candidates present, minutes
            # apart and with no code change in between:
            #
            #   22:05  inline dir 21:38 / files 21:49  |  skills-dir dir 18:46 / files 22:04
            #          -> old rule picks inline; skills-dir is the live one (3297 uses vs 23)
            #   22:11  inline dir 22:09 / files 22:09  |  skills-dir dir 22:09 / files 22:11
            #          -> old rule picks skills-dir
            #
            # Same two directories, opposite answers, because one of them
            # happened to gain a file. A per-session ledger cannot claim
            # durability while the directory it resolves flips on that.
            #
            # This picks the most recently written; it does not merge. More
            # than one suffixed candidate means the ledger is ALREADY split
            # across install routes, and no rule local to this function can
            # undo that - trips written under one identity stay invisible to a
            # session resolving the other. $info.candidates is what tells a
            # caller the pick was made among several.
            #
            # EnumerateFiles carries LastWriteTimeUtc back from the Win32 find
            # data, so this is one directory scan per candidate and no per-file
            # stat: ~5 ms over the dir-mtime-only ranking, measured cold across
            # the two real candidates on this machine. It runs only in this
            # branch - the one-suffixed case above still costs nothing, and that
            # is the case on a healthy machine. Under a hook it costs nothing at
            # all, because Claude Code sets CLAUDE_PLUGIN_DATA and the env
            # branch returns before any filesystem work happens.
            $best = $null; $bestT = [datetime]::MinValue
            foreach ($d in $suffixed) {
                $t = [datetime]::MinValue
                try { $t = [IO.Directory]::GetLastWriteTimeUtc($d) } catch { }
                try {
                    foreach ($f in ([IO.DirectoryInfo]::new($d)).EnumerateFiles()) {
                        if ($f.LastWriteTimeUtc -gt $t) { $t = $f.LastWriteTimeUtc }
                    }
                } catch { }
                if ($null -eq $best -or $t -gt $bestT -or
                    ($t -eq $bestT -and [string]::CompareOrdinal($d, $best) -lt 0)) {
                    $best = $d; $bestT = $t
                }
            }
            $info.path = $best; $info.source = 'discovered'; $info.resolved = $true
        }
        elseif ([IO.Directory]::Exists($bare)) {
            # No suffixed sibling. The bare dir is all there is, so use it - but
            # it is still not a name Claude Code hands anyone, so it is reported
            # as unresolved rather than passed off as the live dir.
            $info.source = 'bare'
        }
    } catch {
        # Resolution must never throw on the gate path. Whatever was worked out
        # so far stands; if even $info.path is empty the caller gets $null and
        # Get-LwgStateDir degrades to returning it unchanged.
    }

    $script:LwgStateDirInfo = $info
    return $info
}

function Get-LwgStateDir {
    <#
      The state directory, created if absent. Returns a path string - the
      signature every existing call site depends on. Use Get-LwgStateDirInfo
      when you need to know whether that path is the live dir or a guess.
    #>
    $dir = (Get-LwgStateDirInfo).path
    if ([string]::IsNullOrWhiteSpace($dir)) { return $dir }
    # CreateDirectory is a no-op when the directory already exists, so this is
    # the whole of the old Test-Path/New-Item pair in one call and without
    # loading Management. Left OUT of the memoised resolution on purpose: the
    # original recreated the directory on every call, and a state dir deleted
    # mid-session must come back rather than silently swallow every later write.
    try { [void][IO.Directory]::CreateDirectory($dir) } catch { }
    return $dir
}

function Get-LwgDefaultConfig {
    <#
      Fail-open defaults: if config.json is missing or corrupt, every module is
      on. A module that declares its own `switch` is deliberately NOT given a
      flag here - it has no `modules` key by design, and inventing one would put
      a value in the fallback that Test-LwgModule never reads. Its own default
      lives on the registry entry, and for every entry that has a switch today
      that default is $false, so an unreadable config leaves the gates and
      orphan_watch OFF.
      That is the right polarity for a gate and it is not an accident: an
      operator whose config.json will not parse must not suddenly find the main
      thread unable to edit the file they need to fix.
    #>
    $mods = [ordered]@{}
    foreach ($m in $script:LwgModules) {
        if ($script:LwgSwitchModules -contains $m) { continue }
        $mods[$m] = $true
    }
    return [pscustomobject]@{
        version    = $script:LwgVersion
        modules    = [pscustomobject]$mods
        repos      = [pscustomobject]@{}
        thresholds = [pscustomobject]@{
            ratelimit = [pscustomobject]@{ warn_pct = 88; land_all_pct = 92 }
            context   = [pscustomobject]@{ warn_pct = 75; critical_pct = 90 }
        }
        _source    = 'defaults'
    }
}

function Get-LwgConfig {
    <#
      Loads config.json from the plugin root. Any failure falls back to the
      defaults above rather than disabling governance.
    #>
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path (Get-LwgPluginRoot) 'config.json'
    }
    try {
        if (Test-Path $Path) {
            $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $cfg = $raw | ConvertFrom-Json -ErrorAction Stop
                if ($null -ne $cfg -and $null -ne $cfg.modules) {
                    Add-Member -InputObject $cfg -NotePropertyName '_source' -NotePropertyValue 'file' -Force
                    return $cfg
                }
            }
        }
    } catch { }
    return (Get-LwgDefaultConfig)
}

# --- repo identity ---------------------------------------------------------
# `workspace` is a STATUS-LINE-ONLY field. It is assembled in exactly one place
# in the claude-code 2.1.220 binary - the status-line input builder - and the
# base hook input is only
#   {session_id, transcript_path, cwd, prompt_id?, permission_mode?,
#    agent_id?, agent_type?, effort?}
# plus per-event fields. Reading payload.workspace.repo in a hook therefore
# returned $null for EVERY hook, which silently made the entire `repos` block in
# config.json apply to nothing - including, at the time, the live PreToolUse
# gates - and stamped "repo":null on every log record.
#
# What every hook DOES carry is `cwd`, so identity is resolved from the working
# directory: walk up for .git, read the origin remote out of its config. Same
# logic ~/.claude/statusline.ps1 used before it was given workspace.repo
# directly.
#
# This runs on PreToolUse, so it is bounded and does NO network access: at most
# 12 Test-Path probes up the tree and one small config read, memoised per path
# for the life of the process. There is deliberately no subprocess helper in
# this file, so no gate can shell out to `git` on the blocking path.

$script:LwgRepoInfoCache = @{}
$script:LwgRepoWalkLimit = 12

function Get-LwgRepoInfo {
    <#
      Git identity for a directory. Returns a HASHTABLE:

        @{ gitdir; common; root; slug; remote_count }

        gitdir        the .git directory for $Path, or $null
        common        the SHARED git dir - differs from gitdir inside a linked
                      worktree, and it is the one that holds `config`
        root          the work-tree root (the directory that contained .git)
        slug          'owner/name' from the origin remote, else $null
        remote_count  how many remotes the config declares

      Every field is $null / 0 when $Path is not inside a repo. Never throws.

      A hashtable, deliberately: PowerShell enumerates a returned collection but
      NOT a returned hashtable, so this survives the function boundary intact.
      The same unrolling trap has shipped three times in this repo already -
      `return ,$on`, `return ,$tokens`, `return $hashset`.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Path)

    $info = @{ gitdir = $null; common = $null; root = $null; slug = $null; remote_count = 0 }
    if ([string]::IsNullOrWhiteSpace($Path)) { return $info }

    # Memoised per invocation. Windows paths are case-insensitive, so the key is
    # lowered - otherwise C:\Repo and c:\repo pay for the walk twice.
    $key = $Path.TrimEnd('\', '/').ToLowerInvariant()
    if ($script:LwgRepoInfoCache.ContainsKey($key)) { return $script:LwgRepoInfoCache[$key] }

    try {
        # --- walk up for .git, bounded -------------------------------------
        $dir = $Path
        for ($i = 0; $i -lt $script:LwgRepoWalkLimit -and -not [string]::IsNullOrWhiteSpace($dir); $i++) {
            $g = Join-Path $dir '.git'
            if (Test-Path -LiteralPath $g) {
                if (Test-Path -LiteralPath $g -PathType Leaf) {
                    # A FILE rather than a directory: a linked worktree or a
                    # submodule, holding `gitdir: <path>` (relative or absolute).
                    $g2 = $null
                    try {
                        $link = (Get-Content -LiteralPath $g -Raw -ErrorAction Stop).Trim()
                        if ($link -match '(?m)^gitdir:\s*(.+)$') {
                            $g2 = $Matches[1].Trim()
                            if (-not [IO.Path]::IsPathRooted($g2)) { $g2 = Join-Path $dir $g2 }
                        }
                    } catch { }
                    $g = $g2
                }
                if ($g) { $info.gitdir = $g; $info.root = $dir }
                break
            }
            $parent = Split-Path -Path $dir -Parent
            if ([string]::IsNullOrEmpty($parent) -or $parent -eq $dir) { break }
            $dir = $parent
        }

        if ($info.gitdir) {
            # --- the shared git dir ----------------------------------------
            # A linked worktree's own git dir has no `config`; it carries a
            # `commondir` pointer to the one that does. Without this, every
            # worktree would resolve to no remote and no slug.
            $common = $info.gitdir
            try {
                $cd = Join-Path $info.gitdir 'commondir'
                if (Test-Path -LiteralPath $cd -PathType Leaf) {
                    $c = (Get-Content -LiteralPath $cd -Raw -ErrorAction Stop).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($c)) {
                        if (-not [IO.Path]::IsPathRooted($c)) { $c = Join-Path $info.gitdir $c }
                        $common = [IO.Path]::GetFullPath($c)
                    }
                }
            } catch { }
            $info.common = $common

            # --- remotes ----------------------------------------------------
            $cfgPath = Join-Path $common 'config'
            if (Test-Path -LiteralPath $cfgPath -PathType Leaf) {
                $section = ''
                $urls    = @{}
                foreach ($line in @(Get-Content -LiteralPath $cfgPath -ErrorAction Stop)) {
                    $t = $line.Trim()
                    if ($t -match '^\[remote\s+"(.+)"\]$') { $section = $Matches[1]; continue }
                    if ($t -match '^\[')                   { $section = '';          continue }
                    if ($section -and $t -match '^url\s*=\s*(.+)$') { $urls[$section] = $Matches[1].Trim() }
                }
                $info.remote_count = $urls.Count

                if ($urls.Count -gt 0) {
                    $url = if ($urls.ContainsKey('origin')) { $urls['origin'] } else { $urls[@($urls.Keys)[0]] }
                    # SSH scp-style first: git@github.com:owner/repo.git
                    if ($url -match '^[^@/]+@[^:/]+:(?<o>[^/]+)/(?<r>.+?)(\.git)?/?$') {
                        $info.slug = "$($Matches.o)/$($Matches.r)"
                    }
                    # Then any URL form: https://, ssh://, git://, including a
                    # user@ prefix on the authority.
                    elseif ($url -match '^[A-Za-z][A-Za-z0-9+.\-]*://(?:[^/@]+@)?[^/]+/(?<o>[^/]+)/(?<r>.+?)(\.git)?/?$') {
                        $info.slug = "$($Matches.o)/$($Matches.r)"
                    }
                    # Anything else - a plain local path remote - has no slug.
                }
            }
        }
    } catch {
        # A repo we cannot read is reported as no repo, never as an exception:
        # this is on the PreToolUse path and a throw here would take a gate down.
        $info = @{ gitdir = $null; common = $null; root = $null; slug = $null; remote_count = 0 }
    }

    $script:LwgRepoInfoCache[$key] = $info
    return $info
}

function Get-LwgRepo {
    <#
      Repo slug ('owner/name') for a hook payload, or $null outside a repo.

      Resolved from payload.cwd (see the note above - payload.workspace does not
      exist in any hook event). payload.workspace.repo is still honoured if it is
      ever present, so a future CLI that does supply it wins over the walk, but
      nothing depends on that.

      Never throws. The slug is compared against config.json's `repos` keys by
      PowerShell property lookup, which is case-insensitive.
    #>
    param($Payload)

    if ($null -eq $Payload) { return $null }
    try {
        $ws = $Payload.workspace
        if ($null -ne $ws) {
            $repo = $ws.repo
            if ($repo -is [string]) {
                if (-not [string]::IsNullOrWhiteSpace($repo)) { return $repo.Trim() }
            } elseif ($null -ne $repo) {
                if ($repo.full_name)                { return [string]$repo.full_name }
                if ($repo.owner -and $repo.name)    { return "$($repo.owner)/$($repo.name)" }
            }
        }
        return (Get-LwgRepoInfo -Path ([string]$Payload.cwd)).slug
    } catch { }
    return $null
}

function Test-LwgFlag {
    <#
      A boolean read out of config.json from somewhere OTHER than the `modules`
      block: the global at config.<Block>.<Key>, then a per-repo override at
      repos[slug].<Block>.<Key>, then $Default when neither is present.

      This is the resolution rule for a module that declares its own `switch` in
      the registry, and it is deliberately the SAME shape - global, then repo,
      then built-in default - that bin/lwg-toggle.ps1 uses to report the
      effective value of a preference. The two must agree: a command that writes
      a key and a gate that reads it differently is a setting that silently does
      not take effect, which is the founding defect this plugin exists to catch.
      tests/gate_delegate.ps1 exercises the pair end to end for that reason.

      Never throws. Every lookup is guarded, so a config missing the block, the
      key, or the whole `repos` object yields $Default rather than an error on a
      path that a PreToolUse hook runs on.

      ONLY A REAL BOOLEAN IS A SETTING. Anything else at either scope is IGNORED
      at that scope - resolution continues as if that level had said nothing -
      and the fact is written to the event log as ConfigInvalidFlag rather than
      swallowed. This is not tidiness; it was a near-one-way lockout.

          "interaction": { "delegate": "false" }

      is what an operator writes when they mean off, and [bool] on a non-empty
      string is $true in PowerShell, so this line ARMED the only gate this
      plugin ships. The gate then refuses Edit, Write, NotebookEdit, Bash and
      PowerShell on the main thread - including the Bash call that
      /lw-watchtower:delegate off runs
      to turn it back off - so the way out is a hand edit of the file from
      outside the session, on a machine whose operator has just been told the
      gate is off. Every doc in this repo says the polarity avoids exactly that.

      IGNORED, NOT COERCED THE OTHER WAY, and the difference matters: an invalid
      value is not a vote for `false`, it is not a value at all. So a garbage
      per-repo override leaves a global `true` standing rather than silently
      disarming a gate the operator did arm, and a garbage global leaves
      $Default - which for every switch in the registry is the off state.

      IT IS NEVER SILENT. A setting that does not take effect and says nothing
      is the founding defect this plugin exists to catch, so the log line is
      part of the fix and not decoration. Writing it costs one appended line
      only when the config is already broken.

      THE RULE IS NOT LOCAL TO THIS FUNCTION, and it cannot be: a reader and a
      reporter that disagree about one value describe two different plugins.
      The same rule is applied by Test-LwgModule below, for the `modules` block
      this function deliberately does not read, and by Get-LwgPrefGlobal,
      Get-LwgPrefRepo and Test-LwgFlagOn in bin/lwg-toggle.ps1, which are what
      /lw-watchtower:delegate prints. All five log through Write-LwgInvalidFlag.
      bin/lwg-toggle.ps1 was outside the change that first landed this rule and
      spent that window reporting "on" for a config this function read as off -
      a reporter/reader divergence introduced by fixing one of the pair.
    #>
    param($Config, [string]$Repo, [string]$Block, [string]$Key, [bool]$Default)

    $v = $Default
    try {
        $g = $Config.$Block.$Key
        if ($null -ne $g) {
            if ($g -is [bool]) { $v = [bool]$g }
            else { Write-LwgInvalidFlag -Block $Block -Key $Key -Scope 'global' -Value $g }
        }
    } catch { }

    if (-not [string]::IsNullOrWhiteSpace($Repo)) {
        try {
            $o = $Config.repos.$Repo
            if ($null -ne $o) {
                $r = $o.$Block.$Key
                if ($null -ne $r) {
                    if ($r -is [bool]) { $v = [bool]$r }
                    else { Write-LwgInvalidFlag -Block $Block -Key $Key -Scope "repo:$Repo" -Value $r }
                }
            }
        } catch { }
    }
    return $v
}

function Write-LwgInvalidFlag {
    <#
      Record that a flag in config.json held something that is not a boolean and
      was therefore ignored. Never throws, and never reaches the operator's
      screen: this runs on the PreToolUse path, where anything written to stdout
      or stderr is read by the CLI as a hook decision.

      The value is recorded as its TYPE and its text, redacted and short. A
      config value is operator-authored and a flag block is not where a
      credential belongs, but Get-LwgRedacted costs nothing on a line that is
      only written when the config is already wrong.
    #>
    param([string]$Block, [string]$Key, [string]$Scope, $Value)

    try {
        $t = 'null'
        if ($null -ne $Value) { $t = $Value.GetType().Name }
        Write-LwgEvent -Event 'ConfigInvalidFlag' -Payload $null -Extra @{
            block = $Block
            key   = $Key
            scope = $Scope
            type  = $t
            value = (Get-LwgRedacted -Text ([string]$Value) -MaxLength 60)
            note  = 'not a boolean, so it is not a setting - ignored, and the resolution continued as if this scope said nothing'
        } | Out-Null
    } catch { }
}

function Test-LwgModule {
    <#
      Is module $Name enabled? Global default first, then a per-repo override
      from config.repos['owner/name'].modules. Unknown modules are treated as on.

      A module whose registry entry declares a `switch` is answered from THAT
      key instead - it has no `modules` flag by design, and reading one would be
      reading a flag nothing writes. See the `switch` field on the registry.

      ONLY A REAL BOOLEAN IS A SETTING HERE TOO, by the same rule and through
      the same logging helper as Test-LwgFlag above. It arrived here late, and
      the gap is worth naming rather than quietly closing: while this block
      still did a bare [bool],

          "modules": { "docs_coupling": "false" }

      ENABLED docs_coupling, because [bool] on a non-empty string is $true in
      PowerShell. Every doc in this repo tells an operator that a module they
      switched off is off.

      THE POLARITY OF "IGNORED" IS THE OPPOSITE ONE HERE, and that is not an
      inconsistency. A `modules` flag defaults ON - Get-LwgConfig fails open, an
      unlisted module is enabled - so a value that is ignored leaves the module
      RUNNING, where an ignored `switch` value leaves a gate OFF. The rule is
      the same in both places (a non-boolean is not a value at all, so the level
      that holds it is skipped); it is the built-in default underneath that
      differs, and it differs because an observing module failing open and a
      blocking gate failing closed are both the safe direction for what they do.

      IT ALSO PUTS THIS FUNCTION BACK IN AGREEMENT WITH lib/subagent_start.ps1,
      whose raw-text scan reads the same block. Get-LwgJsonBool there matches
      only a literal `true` or `false` - its own comment says a string that
      begins `true` cannot match, because TrimStart leaves the opening quote in
      front - so it already reported a string-valued flag as ABSENT, which for
      this block means enabled. The scanner was right and the parser was wrong.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        $Config,
        [string]$Repo
    )

    if ($null -eq $Config) { $Config = Get-LwgConfig }

    $sw = $null
    try { $sw = $script:LwgModuleRegistry[$Name].switch } catch { }
    if ($null -ne $sw) {
        # $sw.default is REGISTRY-derived, not config-derived - it is the
        # literal in $script:LwgModuleRegistry a few hundred lines above, not
        # anything an operator can write - so the boolean-only rule has nothing
        # to bite on and the cast stays.
        return (Test-LwgFlag -Config $Config -Repo $Repo `
                             -Block ([string]$sw.block) -Key ([string]$sw.key) `
                             -Default ([bool]$sw.default))
    }

    $enabled = $true
    try {
        $global = $Config.modules.$Name
        if ($null -ne $global) {
            if ($global -is [bool]) { $enabled = [bool]$global }
            else { Write-LwgInvalidFlag -Block 'modules' -Key $Name -Scope 'global' -Value $global }
        }
    } catch { }

    if (-not [string]::IsNullOrWhiteSpace($Repo)) {
        try {
            $over = $Config.repos.$Repo
            if ($null -ne $over -and $null -ne $over.modules) {
                $v = $over.modules.$Name
                if ($null -ne $v) {
                    if ($v -is [bool]) { $enabled = [bool]$v }
                    else { Write-LwgInvalidFlag -Block 'modules' -Key $Name -Scope "repo:$Repo" -Value $v }
                }
            }
        } catch { }
    }
    return $enabled
}

function Get-LwgRawFlagValue {
    <#
      The RAW value at $Object.$Name, and whether the member is there at all.
      Returns @{ present; value }.

      PRESENCE IS NOT "NOT NULL", and that distinction is the whole point of
      this helper. ConvertFrom-Json maps a JSON `null` onto $null, so
      `"git_hygiene": null` and an absent `git_hygiene` key are indistinguishable
      by a $null test - and they are not the same thing. The first is an
      operator writing something that is not a setting; the second is an
      operator saying nothing, which is a legitimate config and must stay
      silent. PSObject.Properties can tell them apart; a value comparison
      cannot.

      Never throws: an absent block, a $null object or a hashtable rather than a
      PSCustomObject all yield present = $false.
    #>
    param($Object, [string]$Name)

    if ($null -eq $Object) { return @{ present = $false; value = $null } }
    try {
        $p = $Object.PSObject.Properties[$Name]
        if ($null -ne $p) { return @{ present = $true; value = $p.Value } }
    } catch { }
    return @{ present = $false; value = $null }
}

function Get-LwgUnresolvedFlags {
    <#
      Every DECLARED module whose configured value is present in config.json but
      is not a real boolean, and was therefore IGNORED. Returns descriptive
      strings - `modules.docs_coupling (global, String)` - because a caller
      reporting this has to name the key the operator actually wrote, not the
      module the plugin resolved from it.

      WHY THIS EXISTS AS A SEPARATE FUNCTION FROM Test-LwgModule. Test-LwgModule
      answers "is it on", and it is careful to answer that with a [bool] on
      every one of its exit paths: a non-boolean at any scope is ignored, logged
      through Write-LwgInvalidFlag, and resolution continues as if that scope
      had said nothing. That is the right behaviour and it is what makes the
      question "did anything get ignored?" unanswerable from its return value -
      which is exactly how lib/session_start.ps1's probe 2 came to be a check
      that could not fail. The observable failure is not a bad return type, it
      is a CONFIGURED VALUE THAT WAS DISCARDED, and only the raw config can
      show that.

      IT COVERS ALL FOUR SCOPES, because a probe that read one of them would be
      a smaller version of the same defect:

        modules.<name>                       global, for a plain module
        <block>.<key>                        global, for a module declaring its
                                             own `switch` - delegate_gate and
                                             the three supervision modules have
                                             NO `modules` key by design, and a
                                             probe reading only that block would
                                             walk straight past the flag that
                                             arms the only gate this plugin
                                             ships
        repos.<slug>.modules.<name>          per-repo, plain
        repos.<slug>.<block>.<key>           per-repo, switch-backed

      Never throws. $Repo empty simply skips the two per-repo scopes.
    #>
    param($Config, [string]$Repo)

    if ($null -eq $Config) { $Config = Get-LwgConfig }
    $bad = @()

    $repoObj = $null
    if (-not [string]::IsNullOrWhiteSpace($Repo)) {
        try { $repoObj = $Config.repos.$Repo } catch { }
    }

    foreach ($m in $script:LwgModules) {
        $sw = $null
        try { $sw = $script:LwgModuleRegistry[$m].switch } catch { }
        if ($null -ne $sw) { $block = [string]$sw.block; $key = [string]$sw.key }
        else               { $block = 'modules';         $key = $m }

        $scopes = @()
        try { $scopes += ,@('global', $Config.$block) } catch { }
        if ($null -ne $repoObj) {
            try { $scopes += ,@("repo:$Repo", $repoObj.$block) } catch { }
        }

        foreach ($s in $scopes) {
            $raw = Get-LwgRawFlagValue -Object $s[1] -Name $key
            if (-not $raw.present) { continue }
            if ($raw.value -is [bool]) { continue }
            $t = 'null'
            if ($null -ne $raw.value) { try { $t = $raw.value.GetType().Name } catch { $t = 'unknown' } }
            $bad += ("{0}.{1} ({2}, {3})" -f $block, $key, $s[0], $t)
        }
    }
    return $bad
}

function Get-LwgEnabledModules {
    <#
      Names of every enabled module, in inventory order. Emitted as a normal
      stream - callers must wrap in @() so the zero- and one-module cases stay
      arrays.
    #>
    param($Config, [string]$Repo)

    if ($null -eq $Config) { $Config = Get-LwgConfig }
    $on = @()
    foreach ($m in $script:LwgModules) {
        if (Test-LwgModule -Name $m -Config $Config -Repo $Repo) { $on += $m }
    }
    return $on
}

function Get-LwgModuleStatus {
    <#
      'implemented', 'planned', or 'unknown' for a name not in the registry.
      Unknown deliberately does NOT fall back to 'implemented' - an unrecognised
      module has no code by definition.
    #>
    param([Parameter(Mandatory = $true)][string]$Name)

    try {
        $entry = $script:LwgModuleRegistry[$Name]
        if ($null -ne $entry -and $entry.status) { return [string]$entry.status }
    } catch { }
    return 'unknown'
}

function Test-LwgModuleImplemented {
    <# Does code exist for this module? Independent of whether it is enabled. #>
    param([Parameter(Mandatory = $true)][string]$Name)
    return ((Get-LwgModuleStatus -Name $Name) -eq 'implemented')
}

function Get-LwgImplementedModules {
    <# Every module with real code behind it, config ignored. #>
    $out = @()
    foreach ($m in $script:LwgModules) {
        if (Test-LwgModuleImplemented -Name $m) { $out += $m }
    }
    return $out
}

function Get-LwgPlannedModules {
    <# Declared but not built. These do nothing regardless of their flag. #>
    $out = @()
    foreach ($m in $script:LwgModules) {
        if (-not (Test-LwgModuleImplemented -Name $m)) { $out += $m }
    }
    return $out
}

function Get-LwgBlockedModules {
    <#
      The subset of planned modules that CANNOT be built as specified, because
      the data they need reaches no hook. Reported separately from 'planned' so
      that "not running" is never read as "not written yet" - a merely unbuilt
      module may still land, and a blocked one will not.
      RETURNS EMPTY as shipped: the only two entries that ever carried
      blocked = $true (ratelimit_escalation, cost_tracking) were removed on
      30 July 2026. This is kept, not deleted, so the distinction is available
      the next time a module has to be declared unbuildable rather than unbuilt.
      Emitted as a normal stream - wrap callers in @().
    #>
    $out = @()
    foreach ($m in $script:LwgModules) {
        try {
            $e = $script:LwgModuleRegistry[$m]
            if ($null -ne $e -and $e.blocked -eq $true) { $out += $m }
        } catch { }
    }
    return $out
}

function Get-LwgActiveModules {
    <#
      The only count a banner may honestly call "active": enabled by config AND
      backed by code. Enabled-but-planned is not active, it is a promise.
      Emitted as a normal stream - wrap callers in @().
    #>
    param($Config, [string]$Repo)

    if ($null -eq $Config) { $Config = Get-LwgConfig }
    $out = @()
    foreach ($m in $script:LwgModules) {
        if ((Test-LwgModuleImplemented -Name $m) -and
            (Test-LwgModule -Name $m -Config $Config -Repo $Repo)) { $out += $m }
    }
    return $out
}

function Get-LwgActiveGates {
    <#
      Gates that can actually block something right now: declared kind 'gate',
      backed by code, AND switched on. A gate that ships but is switched off
      counts ZERO here, and the banner must say 0 - "a gate exists" and "a gate
      is blocking" are different facts and the count reports only the second.
      $script:LwgGates is the other one; /lw-watchtower:doctor prints both.

      Three names can reach this list today - delegate_gate, send_liveness_gate
      and completion_audit - each only when its own switch is on, which none is
      by default.
    #>
    param($Config, [string]$Repo)

    $out = @()
    foreach ($m in @(Get-LwgActiveModules -Config $Config -Repo $Repo)) {
        if ($script:LwgGates -contains $m) { $out += $m }
    }
    return $out
}

function Get-LwgSessionMode {
    <#
      The one word a session is allowed to call itself. Lifted out of
      lib/session_start.ps1 in Phase 10 because /lw-watchtower:doctor has to report the
      same word and a second copy of this ladder is a second thing to keep
      correct - the mode is the headline, so a drifted copy would be the loudest
      possible lie the plugin could tell about itself.

        inert         nothing is running
        unverified    modules are loaded but the self-check never ran
        degraded      the self-check ran and something failed
        observe-only  modules run, but no gate can block anything
        partial       gates run, but some implemented module is switched off
        enforcing     every implemented module is on and at least one gate is live

      Order matters and is not alphabetical:

      'unverified' is its own word deliberately. 'enforcing', 'partial' and
      'observe-only' each assert, in this plugin's own documentation, that the
      self-check PASSED, and claiming that on the strength of a check that never
      happened is the same class of overstatement as counting an unbuilt module
      as coverage. 'degraded' would be the opposite overstatement - it says a
      probe failed, and none did. So nothing running at all is still 'inert',
      because that is the stronger and completely verifiable statement;
      otherwise the honest word is that governance is loaded but unverified.

      $SelfCheckOk is deliberately untyped and tested against $true rather than
      coerced. A caller reading the value back out of a log record can hand us
      $null for "the record does not say", and an absent result must read as
      'degraded' - not as a pass - because there is no evidence it passed.
    #>
    param(
        [int]$ActiveCount,
        [int]$GateCount,
        [int]$ImplementedCount,
        [bool]$SelfHealthOn,
        $SelfCheckOk
    )

    if     (-not $SelfHealthOn)                 { return $(if ($ActiveCount -eq 0) { 'inert' } else { 'unverified' }) }
    elseif ($SelfCheckOk -ne $true)             { return 'degraded' }
    elseif ($ActiveCount -eq 0)                 { return 'inert' }
    elseif ($GateCount -eq 0)                   { return 'observe-only' }
    elseif ($ActiveCount -lt $ImplementedCount) { return 'partial' }
    else                                        { return 'enforcing' }
}

function Get-LwgThreshold {
    <# Get-LwgThreshold -Config $c -Group 'context' -Key 'warn_pct' -Default 75 #>
    param($Config, [string]$Group, [string]$Key, $Default)

    try {
        $v = $Config.thresholds.$Group.$Key
        if ($null -ne $v) { return $v }
    } catch { }
    return $Default
}

function Get-LwgModuleOption {
    <#
      Per-module tuning out of config.json's `module_config` block:

          Get-LwgModuleOption -Config $c -Module 'docs_coupling' -Key 'doc_extensions' -Default @('.md')

      Distinct from `thresholds`, which is only the two numeric pressure groups.
      Returns $Default when the key is absent, so a stripped-down or missing
      config still yields working modules rather than empty lists.
    #>
    param($Config, [string]$Module, [string]$Key, $Default)

    try {
        $v = $Config.module_config.$Module.$Key
        if ($null -ne $v) { return $v }
    } catch { }
    return $Default
}

function Get-LwgModuleFlag {
    <#
      The BOOLEAN options out of `module_config`, under the same rule as
      Test-LwgFlag and Test-LwgModule: ONLY A REAL [bool] IS A SETTING.
      Anything else is not a value at all, so the key is treated as absent,
      $Default applies, and the fact is logged through Write-LwgInvalidFlag.

          Get-LwgModuleFlag -Config $c -Module 'git_hygiene' -Key 'use_gh' -Default $true

      WHY THIS EXISTS RATHER THAN A CAST AT THE CALL SITE. The call sites in
      lib/stop_advisories.ps1 did

          [bool](Get-LwgModuleOption ... -Default $true)

      and [bool] on a non-empty string is $true in PowerShell while [bool]''
      and [bool]0 are $false. So a `""` or a `0` written for one of these keys
      silently switched a suppressor OFF - and the module then warned about
      work it was built to excuse - on the strength of a quoting accident, with
      nothing anywhere saying so. That is the founding defect of this plugin
      arriving one layer below the block the rule already covered. The pair the
      defect was found on belonged to mission_drift, which is gone; the rule
      outlived it because it was never about that module.

      THE FLOOR UNDERNEATH IS THE CALLER'S $Default, not a fixed polarity. A
      `module_config` option is TUNING, not an on/off switch for the module -
      the module's own flag is `modules.<name>` and Test-LwgModule owns that -
      so "ignored" here means "tuned as shipped", which is the only direction
      that cannot be surprising. The current caller ships $true.

      Get-LwgModuleOption is left alone deliberately: most of what it returns is
      a number or a list, where this rule would be wrong. Only the boolean keys
      come through here.
    #>
    param($Config, [string]$Module, [string]$Key, [bool]$Default)

    $v = $null
    try { $v = $Config.module_config.$Module.$Key } catch { }
    if ($null -eq $v) { return $Default }
    if ($v -is [bool]) { return [bool]$v }

    Write-LwgInvalidFlag -Block "module_config.$Module" -Key $Key -Scope 'global' -Value $v
    return $Default
}

function Format-LwgFlagState {
    <#
      Render a RAW config value as the word an operator reads: 'on', 'off', or
      'ignored' when it is not a boolean.

      THIS IS THE REPORTING HALF OF THE SAME RULE, and it exists because the
      readers and the reporters diverging is the exact defect this plugin was
      built to catch. bin/lwg-config.ps1 rendered a per-repo override with a
      bare [bool], so `"docs_coupling": "false"` printed `on` in the OVERRIDE
      column while Test-LwgModule - two lines below, on the same value - ignored
      it. Whatever the report says, the third word has to exist: a value that is
      not a setting cannot honestly be shown as either setting.

      IT DOES NOT LOG. Every current caller resolves the SAME key through
      Test-LwgModule or Test-LwgFlag in the same breath, and those log through
      Write-LwgInvalidFlag already; logging here as well would put two records
      in the event log for one bad key. The rule is shared, the record is made
      once, by the reader.
    #>
    param($Value)

    if ($null -eq $Value)    { return '-' }
    if ($Value -isnot [bool]) { return 'ignored' }
    if ($Value)              { return 'on' }
    return 'off'
}

function Add-LwgLine {
    <#
      Append one line to a file under the state dir. Concurrent hooks race on
      these files, so retry briefly rather than throwing - pattern lifted from
      ~/.claude/health/supervisor.ps1 (20/40/60/80/100 ms).
      Returns $true on success, $false if all five attempts failed.

      -Replace REPLACES the file's contents with the one line instead of
      appending, keeping the same retry ladder and the same return contract.
      ONE CALLER USES IT, self_health's state-writable probe, and it is here
      rather than as a separate function because the retry ladder is the whole
      of this helper and a second copy of it is a second thing to keep correct.

      WHY THE PROBE NEEDED IT. That probe proves the state directory is writable
      by writing a timestamp, and it fires on every SessionStart - start,
      resume, clear and compact. Nothing in the tree rotates, truncates or READS
      selfcheck.probe: Invoke-LwgRotate has exactly one call site and it is
      passed health.jsonl. It was the only file this plugin wrote with no bound
      of any kind, inside a plugin whose log_rotation module reports itself as
      capping the logs. The file's entire value is in the RETURN of the write,
      and the LAST result is the only one with any meaning, so replacing is what
      the probe always meant - which is why this is a switch on the writer and
      not a rotation call added to the SessionStart path for a file nobody
      reads.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][string]$Line,
        [switch]$Replace
    )

    try {
        $path = Join-Path (Get-LwgStateDir) $FileName
        $text = $Line.TrimEnd("`r", "`n") + "`n"
        for ($i = 0; $i -lt 5; $i++) {
            try {
                if ($Replace) { [System.IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false)) }
                else          { [System.IO.File]::AppendAllText($path, $text, [Text.UTF8Encoding]::new($false)) }
                return $true
            } catch {
                Start-Sleep -Milliseconds (20 * ($i + 1))
            }
        }
    } catch { }
    return $false
}

# The longest single line this plugin will carry forward into a live log, or
# spend parse time on when reading one. A record written by any module in this
# repo runs to a couple of kilobytes at the very most - every payload-derived
# field is capped at $script:LwgLogFieldMax before it is serialised - so
# anything past this is not a record, it is a payload someone pasted into one.
#
# statusline\statusline.ps1 carries the SAME number as its own literal and says
# so, because it is a settings.json command that deliberately dot-sources
# nothing. If this changes, that changes with it.
$script:LwgMaxLogLineChars = 8192

# The cap every payload-derived FIELD is redacted and truncated to before it
# reaches a log record. Named here rather than left as Get-LwgRedacted's default
# so the writers that must agree on it - lib/supervisor.ps1 and lib/gate_delegate.ps1 -
# agree on it by reference.
$script:LwgLogFieldMax = 200

function Invoke-LwgRotate {
    <#
      Roll a state-dir log once it grows past $MaxBytes: health.jsonl.1 becomes
      .2, the live file becomes .1, and the live file is recreated carrying the
      last $KeepLines records forward.

      Carrying the tail forward is the point. The status line reads the last 300
      records of this file and counts outstanding faults from them; a plain
      move-and-truncate would blank HH the moment a rotation happened.
      $KeepLines must stay comfortably above 300.

      THE LIVE FILE IS MOVED FIRST, AND THAT ORDER IS THE WHOLE OF A FIX. The
      archives used to be shifted first. When the live log could not then be
      moved - which is not an exotic state but the ORDINARY one, because
      Add-LwgLine's AppendAllText holds the file FileShare.Read for the length of
      every append and concurrent hooks race on it by design - .2 had already
      been deleted and .1 had already been moved onto it, and no new .1 was ever
      produced. One whole archive generation was destroyed, and the function
      returned $false, wrote nothing to stderr and logged nothing, so the loss
      was invisible to everything including this file's own docstring. Nothing
      is deleted now until the live file has actually been taken out of the way.

      EVERY FAILURE IS REPORTED, through Write-LwgEvent into lw-watchtower.jsonl. That
      is deliberately the OTHER log: the file being rotated is by definition the
      one an append may not be able to reach, so a report written there would go
      missing in exactly the case worth reporting.

      ENCODING IS EXPLICIT ON BOTH SIDES. The tail used to be read with a bare
      Get-Content -Tail, which decodes ANSI in Windows PowerShell 5.1 while
      every writer here emits UTF-8 without a BOM. A record naming an accented
      path or holding a non-Latin script therefore came back mojibaked and was
      written back mojibaked: the rotation corrupted the records it exists to
      preserve, once per rotation, silently and irreversibly. The read is now
      Get-LwgTailLines, which decodes the bytes itself.

      THAT ALSO TAKES THE READ OFF Get-Content -Tail's COST CURVE, which is
      superlinear in LINE LENGTH rather than in file size: on one machine, a
      300-record file took 19 ms to tail clean, 9,032 ms with a single
      200,000-character record in it, and 80,014 ms with ten. This runs on a
      hook, so that was minutes of turn-end latency waiting to happen the first
      time a big line landed in a log about to roll.

      AN OVERSIZED RECORD IS NOT CARRIED FORWARD. The full record still exists
      in the .1 archive this call just made - nothing is lost - but the live
      file is what the status line parses on every single render, and carrying a
      200,000-character line into it made every future rotation preserve the
      poison for as long as the log lived.

      Never throws. A rotation that fails leaves the live log intact and
      oversized, which is strictly better than losing it - and now says so.

      Returns $true only when a rotation completed. $false is "nothing to do" OR
      "it failed"; the two are told apart by the event record, not by the
      return value, because every existing call site discards it.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [int]$MaxBytes     = 5242880,   # 5 MB - at ~450 B/record roughly 11k records
        [int]$KeepLines    = 500,
        [int]$Archives     = 2,
        [int]$MaxLineChars = 0          # 0 = take $script:LwgMaxLogLineChars
    )

    if ($MaxLineChars -le 0) { $MaxLineChars = $script:LwgMaxLogLineChars }

    $path = $null
    try {
        $path = Join-Path (Get-LwgStateDir) $FileName
        if (-not (Test-Path -LiteralPath $path)) { return $false }
        if ((Get-Item -LiteralPath $path -ErrorAction Stop).Length -lt $MaxBytes) { return $false }
    } catch { return $false }

    # Unique per attempt. A fixed name would let a second failed rotation
    # overwrite the generation a first one had staged and preserved.
    $stage = '{0}.rotating-{1}-{2}' -f $path, $PID, ([DateTime]::UtcNow.Ticks)

    try {
        # Read the tail BEFORE moving anything: if this comes back empty we abort
        # with the live log still in place rather than half-rotated.
        #
        # The byte window is $KeepLines records at the largest a record may be,
        # so it can always hold $KeepLines of them and never reads the head of a
        # file that may be megabytes long. Get-LwgTailLines opens
        # FileShare.ReadWrite, so a log another hook is mid-append to is still
        # readable.
        $window = $KeepLines * $MaxLineChars
        if ($window -lt 65536) { $window = 65536 }
        $tail = @(Get-LwgTailLines -Path $path -Bytes $window)
        if ($tail.Count -gt $KeepLines) {
            $tail = @($tail[($tail.Count - $KeepLines)..($tail.Count - 1)])
        }

        # We already know the file is at least $MaxBytes long, so an empty tail
        # is a failed read and never an empty file. Rotating on it would recreate
        # the live log with nothing in it and blank the health indicator - the
        # exact outcome carrying the tail forward exists to prevent.
        if ($tail.Count -eq 0) {
            Write-LwgEvent -Event 'RotateFailed' -Extra @{
                file  = $FileName
                stage = 'tail-read'
                note  = 'the tail of an oversized log read back empty, so nothing was rotated. The log is intact.'
            } | Out-Null
            return $false
        }

        $dropped = 0
        $keep = New-Object 'System.Collections.Generic.List[string]'
        foreach ($l in $tail) {
            if (([string]$l).Length -gt $MaxLineChars) { $dropped++; continue }
            [void]$keep.Add([string]$l)
        }
        $tail = $keep.ToArray()

        # 1. Take the live file out of the way. Everything destructive is below
        #    this line, and this is the step that fails under a held handle.
        try {
            Move-Item -LiteralPath $path -Destination $stage -Force -ErrorAction Stop
        } catch {
            Write-LwgEvent -Event 'RotateFailed' -Extra @{
                file    = $FileName
                stage   = 'live-move'
                dropped = $dropped
                error   = (Get-LwgRedacted -Text ([string]$_.Exception.Message) -MaxLength $script:LwgLogFieldMax)
                note    = 'the live log could not be moved aside, so no archive was touched. It is still oversized and every generation is intact.'
            } | Out-Null
            return $false
        }

        # 2. Recreate the live file IMMEDIATELY, before the archive shuffle: a
        #    writer that appends between these steps must land in the new file
        #    rather than recreate one this call is about to overwrite.
        $text = ''
        if ($tail.Count -gt 0) { $text = ($tail -join "`n") + "`n" }
        [System.IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))

        # 3. Shift the archives down - .1 becomes .2 - and let the oldest fall
        #    off. A failure here stops the shift rather than pushing past it:
        #    the staged generation stays on disk under its own name, so what is
        #    left is one extra file, never one fewer generation.
        $shifted = $true
        $why = ''
        for ($i = $Archives; $i -gt 1; $i--) {
            $newer = "$path.$($i - 1)"
            if (-not (Test-Path -LiteralPath $newer)) { continue }
            try {
                if (Test-Path -LiteralPath "$path.$i") {
                    Remove-Item -LiteralPath "$path.$i" -Force -ErrorAction Stop
                }
                Move-Item -LiteralPath $newer -Destination "$path.$i" -Force -ErrorAction Stop
            } catch { $shifted = $false; $why = [string]$_.Exception.Message; break }
        }

        if ($shifted) {
            try { Move-Item -LiteralPath $stage -Destination "$path.1" -Force -ErrorAction Stop }
            catch { $shifted = $false; $why = [string]$_.Exception.Message }
        }

        if (-not $shifted) {
            Write-LwgEvent -Event 'RotateFailed' -Extra @{
                file    = $FileName
                stage   = 'archive-shift'
                dropped = $dropped
                staged  = (Split-Path -Leaf $stage)
                error   = (Get-LwgRedacted -Text $why -MaxLength $script:LwgLogFieldMax)
                note    = 'the archive set could not be shifted. The rotated generation is on disk under the staged name and no generation was deleted; the leftover file is the signal.'
            } | Out-Null
            return $false
        }

        if ($dropped -gt 0) {
            Write-LwgEvent -Event 'RotateDroppedRecords' -Extra @{
                file    = $FileName
                dropped = $dropped
                max     = $MaxLineChars
                note    = 'records past the line cap were archived but NOT carried into the live log - the status line parses that file on every render.'
            } | Out-Null
        }
        return $true
    } catch {
        try {
            Write-LwgEvent -Event 'RotateFailed' -Extra @{
                file  = $FileName
                stage = 'unexpected'
                error = (Get-LwgRedacted -Text ([string]$_.Exception.Message) -MaxLength $script:LwgLogFieldMax)
            } | Out-Null
        } catch { }
    }
    return $false
}

function Write-LwgEvent {
    <# Append a JSONL record to lw-watchtower.jsonl in the state dir. Never throws. #>
    param(
        [Parameter(Mandatory = $true)][string]$Event,
        $Payload,
        [hashtable]$Extra
    )

    try {
        $rec = [ordered]@{
            ts      = (Get-Date).ToUniversalTime().ToString('o')
            v       = $script:LwgVersion
            event   = $Event
            session = $(if ($Payload) { $Payload.session_id } else { $null })
            cwd     = $(if ($Payload) { $Payload.cwd } else { $null })
            repo    = Get-LwgRepo $Payload
        }
        if ($Extra) { foreach ($k in $Extra.Keys) { $rec[$k] = $Extra[$k] } }
        return (Add-LwgLine -FileName 'lw-watchtower.jsonl' -Line (($rec | ConvertTo-Json -Depth 6 -Compress)))
    } catch { }
    return $false
}

# --- secret patterns -------------------------------------------------------
# These are now used for REDACTION ONLY. They fed the secret scanner in
# gate_write.ps1 until that gate was removed on 30 July 2026; nothing matches
# them against a pending write any more, so no credential is blocked by anything
# here. What remains is Get-LwgRedacted, which every module runs over anything it
# is about to write to the log or print in a report: a plugin that records a
# credential in its own audit trail has moved the secret, not contained it, and
# that hazard is unaffected by the loss of the gate.
#
# Each pattern is deliberately written so that THIS FILE does not match it: the
# literal text here is a character class, never a specimen. That was originally
# because the gate scanned edits to its own source and a self-matching pattern
# would have made the plugin unable to modify itself. It is kept because a
# specimen in a tracked file is a liability whether or not anything scans it.
$script:LwgSecretPatterns = @(
    @{ id = 'github_token'; re = '(?i)\bgh[pousr]_[A-Za-z0-9]{20,}' }
    @{ id = 'github_pat';   re = '(?i)\bgithub_pat_[A-Za-z0-9_]{22,}' }
    @{ id = 'aws_key_id';   re = '\b(?:AKIA|ASIA)[0-9A-Z]{16}\b' }
    # THE BODY IS CONSUMED, NOT JUST THE BEGIN LINE, and that changed on
    # 3 August 2026 because the old spelling was a redaction that redacted
    # nothing of value. It replaced the marker line and left every base64 byte
    # of the key standing behind it. Measured, verbatim, on the old pattern:
    #
    #     -----BEGIN RSA PRIVATE KEY-----\n<body>\n-----END RSA PRIVATE KEY-----
    #       ->  [REDACTED:private_key]\n<body>\n-----END RSA PRIVATE KEY-----
    #
    # That is not a theoretical loss. lib/stop_advisories.ps1 puts the
    # operator's typed prompt through Get-LwgRedacted and then hands the result
    # to Add-LwgMissionAnchors, which reads `/` as a PATH SEPARATOR - and `/` is
    # in the base64 alphabet. A pasted key's surviving body was therefore
    # PROMOTED to the anchor kind the advisory QUOTES BACK, so the key material
    # displaced the file the operator actually named out of the emitted
    # systemMessage. Both destinations, not just the state file.
    #
    # THE TRAILING GROUP IS OPTIONAL ON PURPOSE. If the END line is absent -
    # a truncated paste, a key cut off by max_scan_bytes - the group matches
    # empty and this degrades to exactly the old behaviour, the BEGIN line
    # alone. Making it mandatory would have meant a truncated key matching
    # NOTHING, which is strictly worse than the defect being fixed.
    #
    # BOUNDED AT 4096 rather than written `[\s\S]*?`, for the same reason the
    # separator below is bounded: this runs inside a hook on payload text a
    # crafted request controls. 4096 clears an RSA-4096 PEM body with room to
    # spare. Cost of the failure case measured rather than assumed - 200,000
    # characters after a BEGIN line with no END anywhere: 3 ms, against 10 ms
    # for the old pattern over the same input.
    #
    # STILL OPEN, named rather than left to be found: a PEM block whose END line
    # is more than 4096 characters away, and a body pasted with no BEGIN line at
    # all. Neither is caught here or anywhere else.
    @{ id = 'private_key';  re = '-----BEGIN(?:[A-Z ]+)?PRIVATE KEY-----' +
                                 '(?:[\s\S]{0,4096}?-----END(?:[A-Z ]+)?PRIVATE KEY-----)?' }
    @{ id = 'slack_token';  re = '(?i)\bxox[abprs]-[A-Za-z0-9-]{10,}' }
)

# --- generic key/value shapes ----------------------------------------------
# THE VENDOR PATTERNS ABOVE ARE A DIFFERENT LAYER AND ARE NOT TOUCHED BY THIS.
# They know what a credential LOOKS like; these know what a credential is CALLED.
# A GitHub token is caught by the list above wherever it appears, with no key
# name at all; anything issued by a vendor these five do not cover is caught
# only if it is written next to a word that names it. Both layers run, in that
# order, and the vendor layer runs first on purpose - see the ORDER note below.
#
# WHY THIS IS THREE RULES AND NOT ONE LONGER KEYWORD LIST. Until 3 August 2026
# it was one rule:
#
#     (?i)((?:password|passwd|api[-_]?key|secret|token)\s*[:=]\s*)(\S{6,})
#
# which required the key name to be IMMEDIATELY followed by a colon or an equals
# sign. A single quote defeated it, and so did an HTTP scheme word, and so did
# one more character of identifier. Measured against that rule, verbatim:
#
#     api_key: <value>                      -> api_key: [REDACTED]   caught
#     {"api_key": "<value>"}                -> unchanged              LEAKED
#     {"token":"<jwt>"}                     -> unchanged              LEAKED
#     Authorization: Bearer <value>         -> unchanged              LEAKED
#     export SECRET_VALUE=<value>           -> unchanged              LEAKED
#
# The second and third of those are not hypothetical shapes: lib/supervisor.ps1
# MANUFACTURES them. ConvertTo-SafeField pipes any non-scalar payload field
# through ConvertTo-Json -Compress and hands the resulting string to
# Get-LwgRedacted, so every quoted key in a hook payload arrived here in exactly
# the form the old rule could not see - and that string is written to
# health.jsonl and, on the PostToolUseFailure path, printed to stderr, which
# asyncRewake injects into the live session.
#
# THE ONE-LINE FIX IS WRONG AND WAS TRIED. Adding `authorization` and `bearer`
# to the keyword list above makes the keyword match and then lets the VALUE
# group capture the literal word `Bearer` - six characters, which clears the
# {6,} floor - and stop at the space after it. The output is
#
#     Authorization: [REDACTED] <value>
#
# with the token still standing in the log, and a green-looking [REDACTED] in
# front of it saying the opposite. A header therefore gets its own rule whose
# prefix CONSUMES the optional scheme word, so the value group starts after it.
#
# WHY THE VALUE CLASS IS A DENYLIST AND NOT `\S`. `\S` runs through a closing
# quote and a closing brace, so redacting inside a JSON string destroyed the
# rest of the structure. [^\s"',;{}\[\]\\] stops at whatever ended the value in
# the shape it was written in - quote, comma, brace - so a JSON record usually
# survives the substitution intact. USUALLY, NOT ALWAYS, and the two known
# exceptions are written down here because the sentence that stood here until
# 3 August 2026 - "the redacted text stays the shape it arrived as" - is
# falsified by both of them:
#
#     GET /v1/x?api_key=<value>&page=2  ->  GET /v1/x?api_key=[REDACTED]
#     {"tokens_used":1234567,...}       ->  {"tokens_used":[REDACTED],...}
#
# `&` is not in the denylist, so a query string loses every parameter after the
# credential; and a NUMERIC JSON field is replaced by a bare bracketed word,
# which is not valid JSON. `&` is deliberately not added: it would have to be
# excluded from url_userinfo's value class too, and a password containing `&`
# is commoner than a credential in a query string. Both are over-redaction -
# lost evidence, not a lost credential - which is the direction this function
# accepts, but neither is free and neither was disclosed before.
#
# Three of the exclusions carry more weight than tidiness:
#
#   `[` and `]` ARE WHAT KEEP THIS FUNCTION IDEMPOTENT. The replacement text is
#   `[REDACTED]`. If the value class admitted `[`, a second pass would match the
#   marker as a value and rewrite it, and idempotency is a PINNED property here:
#   a value is routinely redacted on the way into a log and again on the way out
#   of one. Excluding the brackets means the marker can never be re-matched.
#
#   `\` IS EXCLUDED FOR THE ESCAPED-JSON SHAPE. A payload field that is ITSELF a
#   JSON string comes back from ConvertTo-Json doubly escaped -
#   {"error":"{\"api_key\":\"<value>\"}"} - so the quote that ends the value is
#   preceded by a backslash. Admitting `\` would swallow it and leave a
#   malformed record; excluding it costs a value that genuinely contains a
#   backslash (a Windows path used as a password) and that trade is taken.
#
#   `,` and `;` are excluded so a compact JSON object or a shell `a=1;b=2` does
#   not have its remaining fields eaten by one match. The cost is a credential
#   that genuinely contains a comma, which is not redacted at all if the part
#   before the comma is under six characters. Named in SECURITY.md.
#
# WHY [ \t]{0,8} AND NOT \s*, in two parts. `\s` matches a NEWLINE, so `token:`
# at the end of one line would take the first word of the NEXT line as its
# value - a redaction of something that was never the credential. And two
# unbounded `\s*` either side of an optional quote is a quadratic backtracking
# shape; this function runs inside a hook, on payload text that a crafted
# request controls, and one such payload has already put 200,199 characters
# through here. Eight is past anything a real separator uses.
#
# THAT NARROWING WAS A STEP BACK AS WELL AS FORWARD, AND THE COST IS STATED
# HERE RATHER THAN LEFT IN THE DIFF. The rule it replaced used `\s*[:=]\s*(\S{6,})`,
# which CROSSED a newline and masked what followed. Eight shapes that the old
# rule masked stopped being masked when this one landed, and they were
# published as a pure gain. Measured, both rules, same specimens:
#
#     token:<LF>sk-live-...           old: token:[REDACTED]     new: unmasked
#     api_key: abc,def1234567890abc   old: api_key: [REDACTED]   new: unmasked
#     secret=a"bcdef1234567890abc     old: secret=[REDACTED]     new: unmasked
#         (and the same for a value carrying ; { } [ ] or \ after a short head)
#
# TWO OF THE EIGHT ARE CLOSED BELOW AND SIX ARE NOT. The two are the newline
# shapes, and they are the ones shown to be REACHABLE: lib/supervisor.ps1 pipes
# a payload field through ConvertTo-Json, which turns a real newline into the
# two characters backslash-n, so a multi-line `error.stderr` whose key ends a
# line arrives here as `token:\nsk-live-...`. The separator therefore admits
# CR and LF themselves AND the escaped spellings `\n`, `\r`, `\t`, all bounded
# at eight rather than written `\s*`, so the quadratic-backtracking argument
# above is untouched - measured at 1 ms over 100,000 characters followed by
# `api_key:` and fifty newlines.
#
# THE FALSE POSITIVE THAT NARROWING REMOVED THEREFORE COMES BACK, and it is a
# cost, not a free win: `token:` at the end of one line will take the next
# line's first word when that word is six or more characters with no excluded
# punctuation in it. That trade is taken deliberately - the other direction
# leaves a credential standing in health.jsonl, which the run above measured it
# doing. Pretty-printed JSON is covered as a side effect of the same change.
#
# ADMITTING THE REAL NEWLINE IS ALSO WHAT KEEPS THIS IDEMPOTENT, which is why
# the escaped forms alone were not enough. Get-LwgRedacted escapes a control
# character to a literal backslash-n AFTER redacting, so with only the escaped
# spelling admitted a raw multi-line value passed through pass 1 in the clear
# and was masked on pass 2 - the output changed between passes, which this file
# pins as a property. Both spellings admitted, both passes agree.
#
# THE SIX STILL OPEN are the value-class exclusions, listed in the docstring
# and in SECURITY.md. They cannot be closed by widening the class without
# undoing the JSON-structure and idempotency properties above, so they are a
# boundary, not a to-do.
#
# WHY THE OPENING BRACKET IS GUARDED BY A LOOKAHEAD. ConvertTo-Json -Compress
# manufactures ARRAYS as readily as scalars, and `{"api_key":["<value>"]}` was
# untouched: the separator's optional quote cannot match `[` and the value
# class excludes it, so the rule found no start position anywhere in the
# string. Admitting a bare `\[?` closes that shape AND BREAKS IDEMPOTENCY - it
# was tried, and `api_key: [REDACTED]` came back `api_key: [[REDACTED]]` on the
# second pass, because the bracket is consumed by the separator and `REDACTED`
# then clears the {6,} floor as an ordinary value. The bracket is therefore
# admitted ONLY when an opening quote follows it, which a JSON array of strings
# always has and the marker never does. Idempotency is pinned by case
# "the new shapes survive a second pass unchanged" in tests\stop_behaviour.ps1.
#
# WHY THE KEYWORD MAY BE FOLLOWED BY MORE IDENTIFIER. `SECRET_VALUE=` is the
# shape the old rule missed by one character: it anchored the separator to the
# end of the keyword, so a name that CONTAINED the keyword rather than ENDING
# with it did not match. [A-Za-z0-9_.-]{0,32} lets the name continue. THE COST
# IS OVER-REDACTION AND IT IS REAL: `token_count: 1234567` is now masked, and so
# is `secret_name: production`. That direction is the safe one - a masked field
# loses evidence, an unmasked one loses a credential - but it is a cost, not a
# free win, and it is why the keyword list below is deliberately short.
$script:LwgRedactValuePattern = '[^\s"'',;{}\[\]\\]{6,}'

# key, then optional closing quote, separator, optional array bracket, optional
# opening quote. The `\\?` before each quote is the escaped-JSON shape described
# above; `\\[nrt]` is the escaped-newline shape; the `(?=\\?["'])` on the
# bracket is what keeps the [REDACTED] marker unmatchable on a second pass.
$script:LwgRedactSepPattern = '(?:\\?["''])?[ \t]{0,8}(?::|=>?)(?:[ \t\r\n]|\\[nrt]){0,8}' +
                              '(?:\[(?:[ \t\r\n]|\\[nrt]){0,8}(?=\\?["'']))?' +
                              '(?:\\?["''])?(?:[ \t\r\n]|\\[nrt]){0,8}'

$script:LwgGenericSecretRules = @(
    # HEADER FIRST, because its value begins after a scheme word the generic
    # rule would hand back as the credential. The trailing negative lookahead is
    # what makes THIS rule idempotent: without it, `Authorization: Bearer
    # [REDACTED]` re-matches on a second pass with the optional scheme group
    # skipped and `Bearer` itself taken as the six-character value, so the output
    # changes between passes. The scheme word is left in the clear on purpose -
    # which scheme was used is evidence, and it is not the secret.
    #
    # THE LOOKAHEAD ENDED IN `\b` UNTIL 3 AUGUST 2026 AND THAT MADE THE RULE
    # MISS ITS OWN HEADLINE SHAPE. `\b` fires between a scheme word and ANY
    # non-word character, so a VALUE that merely BEGINS with one of the five
    # words disqualified itself, and because the scheme group is optional the
    # engine then retried with it skipped and disqualified the scheme word too.
    # The rule matched nowhere in the string. Measured against that spelling,
    # verbatim, while the docstring and SECURITY.md both claimed the shape was
    # covered:
    #
    #     Authorization: Bearer token-9f3a2b7c8d    -> unchanged   LEAKED
    #     Authorization: Bearer basic-auth-9f3a2b7c -> unchanged   LEAKED
    #     Authorization: basic-auth-9f3a2b7c        -> unchanged   LEAKED
    #
    # A hyphen after the word is all it took, and `token-...` is an ordinary way
    # for an issuer to prefix one. `(?:[ \t]|$)` in place of `\b` disqualifies a
    # scheme word only when it is ACTING as a scheme - followed by a separator,
    # or ending the text - which is the only case idempotency needed it for. The
    # three shapes above now mask, and `Authorization: Bearer [REDACTED]` and
    # `Authorization: [REDACTED]` are both fixed points over three passes.
    #
    # BOTH TOKENS BELOW COUNT A NEWLINE AS A SEPARATOR, and the first version of
    # this repair counted only space and tab. That reopened the exact failure
    # this rule was built to prevent, in a spelling the specimen matrix did not
    # reach: a scheme word that ENDS A LINE. With `[ \t]{1,8}` the scheme group
    # could not consume `bearer` + newline, so the engine skipped the group,
    # and with `(?:[ \t]|$)` the guard did not fire on a newline either, so
    # `bearer` itself was taken as the six-character value. Measured:
    #
    #     Authorization: bearer<LF><token>
    #       ->  Authorization: [REDACTED]<LF><token>
    #
    # A green-looking marker with the credential standing behind it, which the
    # note above calls worse than no redaction at all. Widening ONLY the guard
    # would have removed the false marker and left the credential; widening the
    # scheme group as well is what actually masks it. Both spellings of a
    # newline are admitted here for the same reason the separator admits both -
    # ConvertTo-Json delivers the escaped one.
    @{ id = 'auth_header'
       re = '(?i)((?:proxy-)?authorization' + $script:LwgRedactSepPattern +
            '(?:(?:bearer|basic|digest|token|apikey)(?:[ \t\r\n]|\\[nrt]){1,8})?)' +
            '(?!(?:bearer|basic|digest|token|apikey)(?:[ \t\r\n]|\\[nrt]|$))(' +
            $script:LwgRedactValuePattern + ')' }

    # THE KEYWORD LIST IS SHORT ON PURPOSE. Every entry is a word that names a
    # credential and almost nothing else; `key`, `auth`, `pwd` and `id` were all
    # considered and refused, because each of them appears constantly in the
    # ordinary prose this function is mostly handed - a failed task's stderr and
    # an exception message - and each would mask a field that is the evidence
    # somebody is reading the log for.
    @{ id = 'kv'
       re = '(?i)((?:password|passwd|passphrase|secret|token|credential|api[-_]?key' +
            '|private[-_]?key|access[-_]?key|signing[-_]?key|encryption[-_]?key)' +
            '[A-Za-z0-9_.-]{0,32}' + $script:LwgRedactSepPattern + ')(' +
            $script:LwgRedactValuePattern + ')' }

    # A CREDENTIAL WITH NO KEY NAME AT ALL, and the reason it is here rather than
    # left to the two above: git and gh print remote URLs into stderr on almost
    # every failure, and lib/stop_advisories.ps1 and bin/lwg-evidence.ps1 put
    # that stderr straight through this function. `https://<user>:<password>@host`
    # names the password nothing, so nothing above can see it. The lookahead for
    # `@` is what keeps `https://github.com/owner/repo` and `git@github.com:o/r`
    # untouched - neither has a colon-delimited userinfo followed by an at-sign.
    # Bounded at 256 so a long line with no `@` in it cannot be walked
    # repeatedly.
    @{ id = 'url_userinfo'
       re = '(?i)([a-z][a-z0-9+.-]{1,15}://[^\s/:@"''\\]{1,64}:)([^\s/@"''\\\[\]]{3,256})(?=@)' }
)

function Get-LwgRedacted {
    <#
      Mask anything that looks like a credential before it reaches the log.
      Returns the text with each hit replaced by [REDACTED:<id>]; never returns
      any part of the matched value. Also truncates, because a log line is
      evidence that something happened, not a copy of the payload.

      REDACT, THEN NEUTRALISE, THEN TRUNCATE, AND THE ORDER IS LOAD BEARING.
      Truncating first would leave the head of a credential standing in the
      field whenever the cap happened to fall inside one, which is the one
      outcome this function exists to prevent.

      THIS IS PARTIAL, AND THE BOUNDARY IS WRITTEN DOWN RATHER THAN IMPLIED.
      No regular expression covers every credential shape, and a redaction
      helper that reads as though it did is the overstatement this project was
      built to remove. What it catches, as of 3 August 2026:

        - the five vendor shapes in $script:LwgSecretPatterns, anywhere in the
          text, with no key name needed;
        - a named key and its value, bare (api_key: v), JSON-quoted
          ({"api_key":"v"}), escaped-JSON ({\"api_key\":\"v\"}), as the first
          element of a JSON array ({"api_key":["v"]}), with a newline between
          the key and the value in either the raw or the ConvertTo-Json escaped
          spelling (token:\nv), or with the name extended around the keyword
          (SECRET_VALUE=v, x-api-key: v);
        - an Authorization or Proxy-Authorization header, with or without a
          Bearer / Basic / Digest / Token / ApiKey scheme word, INCLUDING a
          value that itself begins with one of those words (Bearer token-...);
        - a password in a URL's userinfo (https://user:pw@host);
        - a PEM private key, BEGIN line through END line, when both are present
          and within 4096 characters of each other.

      WHAT IT STILL DOES NOT CATCH, each one a real shape rather than a
      theoretical one, and each one MEASURED rather than reasoned about:

        - A VALUE UNDER SIX CHARACTERS. The floor exists so ordinary prose is
          not shredded; a short credential passes.
        - A VALUE CONTAINING A QUOTE, COMMA, SEMICOLON, BRACE, BRACKET OR
          BACKSLASH. The match stops there, and if what came before is under
          six characters nothing is masked at all. See the value-class note
          above $script:LwgGenericSecretRules for why those are excluded - and
          note that the rule this one replaced DID mask these, so for these
          six shapes this helper is a step back from where it was on
          30 July 2026, not forward. That is stated in full in the separator
          note above and in SECURITY.md.
        - A PEM BODY WITH NO END LINE within 4096 characters, or pasted with no
          BEGIN line at all. The block form is caught; a truncated one loses
          only its BEGIN line, exactly as every PEM did before 3 August 2026.
        - A CREDENTIAL ANYWHERE BUT THE HEAD OF AN ARRAY. {"api_key":["v"]} is
          caught. {"api_key":["xy","v"]} is NOT - measured, the whole record
          comes back untouched, because the rule anchors on the key and the
          first element is what follows it. Nothing after the first element is
          reachable from the key name at all.
        - A CREDENTIAL WITH NO NAME AND NO VENDOR PREFIX - a bare token on its
          own line, or one named by a word not in the keyword list (`cookie`,
          `signature`, `otp`). Nothing here can tell it from an identifier.
        - A SCHEME WORD WITHOUT A HEADER NAME - `-H "bearer <jwt>"` with no
          `Authorization:` in front of it. The header rule anchors on the
          header name, deliberately, because `bearer` alone is too common a
          word to key on.
        - A CREDENTIAL SPLIT ACROSS TWO FIELDS, or one assembled from pieces.

      OVER-REDACTION IS THE FAILURE DIRECTION IT ACCEPTS. `token_count: 123456`
      is masked. That loses evidence, which is a cost; the other direction
      loses a credential, which is the defect.

      WHAT COMES OUT IS ONE LINE OF PRINTABLE TEXT. Both halves of that are a
      fix rather than tidiness, and both were found by testing this function
      for the first time.

      A CONTROL CHARACTER IS ESCAPED, NEVER PASSED THROUGH. This value is
      written as one field of one JSONL record and it is also PRINTED, a row at
      a time, into a fixed-column console report - bin\lwg-resolve.ps1 lays out
      `ts  event  xN  detail` and `detail` is this. The text inside it is a
      failed task's stderr or a config value: not hostile by assumption, but
      not authored by this plugin either. A newline in it therefore ends the
      row early and starts a second one, and a second row that looks exactly
      like a fault record is a fault record the operator never had. An ESC is
      worse - it reaches the terminal as an escape sequence and can repaint or
      erase what is already on it. LF, CR and TAB become \n, \r and \t; every
      other C0/C1 control and DEL becomes \xHH. The ambiguity with a literal
      backslash-n already in the text is accepted deliberately: a field that
      cannot forge a row is worth more than a field that round-trips.

      A CHARACTER IS NEVER CUT IN HALF. Anything outside the Basic Multilingual
      Plane - an emoji, an uncommon CJK ideograph - is TWO UTF-16 units in a
      .NET string, and Substring at the cap can land between them. What came
      out then was a lone high surrogate: not a character, not encodable as
      UTF-8 (the writer substitutes U+FFFD for it), and not valid JSON when
      PowerShell 5.1 serialises it as a bare \udXXX escape. The cut moves back
      one unit rather than splitting the pair, so an oversized value loses one
      more character and stays text. An unpaired surrogate that was already in
      the INPUT is replaced with U+FFFD for the same reason - it cannot be made
      whole, and it must not be handed onward.

      SURROUNDING WHITESPACE IS TRIMMED, and only because the escaping made it
      matter. Captured stderr almost always ends in a newline; escaping that
      first would put a visible \n at the end of nearly every message, and the
      callers that PRINT this - bin\lwg-evidence.ps1 builds a one-sentence
      checklist detail out of it - cannot take it off again, because they call
      Trim() and a literal backslash-n is not whitespace.

      IT IS IDEMPOTENT, and the tests pin that: the escapes, the [REDACTED]
      markers, the trim and the trailing ellipsis all survive a second pass
      unchanged, so a value redacted on the way into a log and redacted again
      on the way out of one is the same value.

      Never throws, and a failure returns the marker rather than the input. The
      one thing this function may not do on a bad day is hand back the payload
      it was given.
    #>
    param([string]$Text, [int]$MaxLength = 200)

    if ([string]::IsNullOrEmpty($Text)) { return '' }
    try {
        $out = $Text
        foreach ($p in $script:LwgSecretPatterns) {
            $out = [regex]::Replace($out, $p.re, "[REDACTED:$($p.id)]")
        }
        # Generic key/value shapes the vendor list does not cover, in the order
        # they are declared - header before generic, because a scheme word has
        # to be consumed by the prefix rather than captured as the value. See
        # the block above $script:LwgGenericSecretRules for why each exists.
        foreach ($g in $script:LwgGenericSecretRules) {
            $out = [regex]::Replace($out, $g.re, '$1[REDACTED]')
        }

        # Trimmed BEFORE the escaping, and that order is the whole of why the
        # trim is here at all. Captured stderr almost always ends in a newline,
        # and escaping it first would turn that into a visible \n at the end of
        # every message - which the callers that print this cannot remove,
        # because they Trim() the result and a literal backslash-n is not
        # whitespace. Surrounding whitespace is not evidence of anything.
        $out = $out.Trim()

        # One line, printable. \p{Cc} is the C0 and C1 controls and DEL - the
        # whole of what can end a row early or drive a terminal.
        $out = [regex]::Replace($out, '\p{Cc}', {
            param($m)
            $c = [int]$m.Value[0]
            switch ($c) {
                9       { '\t' }
                10      { '\n' }
                13      { '\r' }
                default { '\x{0:X2}' -f $c }
            }
        })

        # A surrogate with no partner is not a character in any encoding.
        $lone = [string][char]0xFFFD
        $out = [regex]::Replace($out, '[\uD800-\uDBFF](?![\uDC00-\uDFFF])', $lone)
        $out = [regex]::Replace($out, '(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]', $lone)

        if ($out.Length -gt $MaxLength) {
            # Back off one unit rather than cutting a surrogate pair in two.
            $cut = $MaxLength
            if ($cut -gt 0 -and [char]::IsHighSurrogate($out[$cut - 1])) { $cut-- }
            $out = $out.Substring(0, $cut) + '...'
        }
        return $out
    } catch { }
    return '[redaction failed]'
}

function Write-LwgDenyDecision {
    <#
      ONE CALLER: lib/gate_delegate.ps1. It had none between the removal of the
      last gate on 30 July 2026 and the arrival of delegate_gate later the same
      day, and was kept through that gap because the schema below was verified
      against a specific CLI build and getting it wrong is SILENT - a malformed
      envelope is ignored and the tool call proceeds, which is a gate that
      reports a block it did not perform.

      READ THIS BEFORE MAKING IT THE ONLY BLOCKING CHANNEL. Because a bad
      envelope fails OPEN, gate_delegate does not rely on it alone: it writes
      the same reason to stderr and exits 2 as well. On the build documented
      below those two are alternatives rather than a pair - a nonzero exit makes
      the CLI ignore stdout and read stderr - so under exit 2 this envelope is
      not what the operator reads. It is emitted anyway, and the reason is worth
      stating: the two channels fail open in DIFFERENT circumstances (a
      malformed envelope on one, an exit code a build does not honour on the
      other), and emitting both means no single one of those failures allows the
      call. Emitting both can never turn a deny into an allow, which is the only
      property that has to hold.

      Emit the PreToolUse deny envelope. Schema verified against the Claude Code
      hooks reference for 2.1.220:

          {"hookSpecificOutput":{"hookEventName":"PreToolUse",
                                 "permissionDecision":"deny",
                                 "permissionDecisionReason":"..."}}

      permissionDecision accepts allow | deny | ask | defer. On this build the
      CLI only parses stdout as JSON on exit 0; exit 2 makes it ignore stdout
      entirely and read stderr instead. So a caller that wants THIS envelope to
      be the thing that blocks must exit 0, and a caller that exits 2 is
      blocking by the exit code and emitting this as the redundant second
      channel described above. gate_delegate does the latter, on purpose.

      There is deliberately no matching allow helper. Emitting
      permissionDecision 'allow' would auto-approve the call and skip the
      permission prompt the operator would otherwise have seen, so a gate that
      finds nothing must stay silent and let the normal flow decide.
    #>
    param([Parameter(Mandatory = $true)][string]$Reason)

    try {
        $out = [ordered]@{
            hookSpecificOutput = [ordered]@{
                hookEventName            = 'PreToolUse'
                permissionDecision       = 'deny'
                permissionDecisionReason = $Reason
            }
        }
        [Console]::Out.Write((($out | ConvertTo-Json -Depth 5 -Compress)))
        return $true
    } catch { }
    return $false
}

function Split-LwgTokens {
    <#
      Split a command line into tokens, respecting single and double quotes.
      Quoted text becomes ONE token with the quotes stripped, which is the whole
      point: it is why `git commit -m "git push --force"` cannot trip the
      force-push rule. Pure string work - no shell is ever invoked.

      Emitted as a normal stream, like the other list-returning helpers here -
      callers must wrap in @(). Do NOT "fix" this to `return ,$tokens`: the
      comma operator returns a one-element array wrapping the token array, and
      @() then preserves that wrapper instead of unrolling it, so every caller
      sees Count 1 and no rule can ever match. That is a gate that silently
      passes everything.
    #>
    param([string]$Text)

    $tokens = @()
    $cur    = ''
    $has    = $false
    $quote  = $null

    if ([string]::IsNullOrEmpty($Text)) { return $tokens }

    foreach ($ch in $Text.ToCharArray()) {
        if ($null -ne $quote) {
            if ($ch -eq $quote) { $quote = $null } else { $cur += $ch }
            $has = $true
            continue
        }
        if ($ch -eq "'" -or $ch -eq '"') { $quote = $ch; $has = $true; continue }
        if ($ch -eq ' ' -or $ch -eq "`t") {
            if ($has) { $tokens += $cur; $cur = ''; $has = $false }
            continue
        }
        $cur += $ch
        $has  = $true
    }
    if ($has) { $tokens += $cur }
    return $tokens
}

function Test-LwgHasFlag {
    <#
      Is a flag present in a token list? -Long 'force' matches `--force` and
      `--force=x` but NOT `--force-with-lease`. -Short 'f' matches a bare `-f`
      and a cluster like `-fd`, but not `--follow-tags`.
    #>
    param([string[]]$Tokens, [string]$Long, [string]$Short)

    foreach ($t in $Tokens) {
        if ($Long) {
            if ($t -eq "--$Long")          { return $true }
            if ($t -like "--$Long=*")      { return $true }
        }
        if ($Short) {
            if ($t -match '^-[A-Za-z]+$' -and $t.Substring(1).Contains($Short)) { return $true }
        }
    }
    return $false
}

function Read-LwgStdin {
    <#
      Read the hook JSON from stdin. Returns an empty object for empty or
      unparseable input so callers never have to null-check the result.
      NOTE: a PowerShell object pipe does not reach [Console]::In - test with
      `cmd /c "type payload.json | powershell -File ..."`.

      -Raw parses text the CALLER already drained instead of reading stdin. A
      pipe is consumed exactly once, so a script that had to read stdin before
      this function was available - lib/gate_delegate.ps1 drains it above its
      fast path, before common.ps1 is even dot-sourced - cannot read it again
      and must hand the text over. Binding is tested with
      $PSBoundParameters.ContainsKey rather than by emptiness, because "the
      caller drained stdin and it was empty" and "nobody passed -Raw" are two
      different inputs and only the second one may go back to [Console]::In.
      Unbound, every existing caller behaves exactly as it did.

      The local is $text, NOT $raw: PowerShell variable names are
      case-INSENSITIVE, so a local $raw and the parameter $Raw would be one
      variable and the read would overwrite what the caller passed.
    #>
    param(
        [AllowNull()][AllowEmptyString()]
        [string]$Raw
    )

    $payload = $null
    $text = ''
    try {
        if ($PSBoundParameters.ContainsKey('Raw')) { $text = [string]$Raw }
        else { $text = [Console]::In.ReadToEnd() }
        if (-not [string]::IsNullOrWhiteSpace($text)) { $payload = $text | ConvertFrom-Json }
    } catch { $payload = $null }
    # Garbage that happens to be valid JSON ("null", "42", "[]") parses to a
    # non-object; normalise those to an empty object too.
    if ($null -eq $payload -or $payload -isnot [System.Management.Automation.PSCustomObject]) {
        $payload = [pscustomobject]@{}
    }
    return $payload
}

# --- advisory output -------------------------------------------------------
# Phase 5's five observe modules WARN. They must never stop a turn, and on Stop
# that is a live risk rather than a theoretical one: a Stop hook blocks the turn
# if it exits 2 without asyncRewake, or if it prints {"decision":"block"}.
#
# So the advisory envelope is deliberately the narrowest thing that reaches the
# user: exit 0, and a `systemMessage` with no `decision` field. Verified against
# the hook output schema in claude-code 2.1.220, where systemMessage is a common
# field on every event ("Warning message shown to the user") and blocking is
# expressed only by `decision` or a bare exit 2. Emitting no `decision` at all
# means this cannot block by construction, not merely by intent.

function Write-LwgAdvisory {
    <#
      Emit one user-visible advisory line and nothing else. Returns $true if the
      envelope reached stdout. Callers MUST still exit 0.
    #>
    # AllowEmptyString/AllowEmptyCollection are load-bearing, not decoration: a
    # Mandatory [string] parameter REJECTS an empty string with a binding
    # exception before the body ever runs, which turns a nothing-to-say call
    # into a logged error. Callers pass whatever the payload held.
    param(
        [AllowNull()][AllowEmptyCollection()][AllowEmptyString()]
        [string[]]$Messages
    )

    try {
        if ($null -eq $Messages) { return $false }
        $lines = @($Messages | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($lines.Count -eq 0) { return $false }
        $out = [ordered]@{
            systemMessage  = ($lines -join '  |  ')
            suppressOutput = $true
        }
        [Console]::Out.Write((($out | ConvertTo-Json -Depth 4 -Compress)))
        return $true
    } catch { }
    return $false
}

# --- per-session scratch ---------------------------------------------------

function Get-LwgSessionKey {
    <#
      A session id reduced to something safe to put in a file name. Claude Code
      sends a UUID, but nothing guarantees that, and a session id with a path
      separator in it would otherwise write outside the state dir.
    #>
    param([string]$SessionId)

    if ([string]::IsNullOrWhiteSpace($SessionId)) { return 'nosession' }
    $k = [regex]::Replace($SessionId, '[^A-Za-z0-9_-]', '_')
    if ($k.Length -gt 64) { $k = $k.Substring(0, 64) }
    return $k
}

function Read-LwgStateJson {
    <#
      Read a small JSON state file from the state dir into a hashtable. Missing,
      empty and corrupt all return an empty hashtable - state here is a cache of
      "what have I already said", never anything that must survive.
    #>
    param([Parameter(Mandatory = $true)][string]$FileName)

    $h = @{}
    try {
        $path = Join-Path (Get-LwgStateDir) $FileName
        if (-not (Test-Path -LiteralPath $path)) { return $h }
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return $h }
        $o = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $o) { return $h }
        foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = $p.Value }
    } catch { }
    return $h
}

function Write-LwgStateJson {
    <# Overwrite a small JSON state file. Never throws; returns $true on success. #>
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][hashtable]$Data
    )

    try {
        $path = Join-Path (Get-LwgStateDir) $FileName
        $json = ($Data | ConvertTo-Json -Depth 6 -Compress)
        [System.IO.File]::WriteAllText($path, $json, [Text.UTF8Encoding]::new($false))
        return $true
    } catch { }
    return $false
}

# --- transcript token accounting -------------------------------------------
# The ONLY route a hook has to context occupancy. Established by reading the
# claude-code 2.1.220 binary: the hook input schema is
#   {session_id, transcript_path, cwd, prompt_id?, permission_mode?,
#    agent_id?, agent_type?, effort?}
# plus per-event fields, and `context_window` / `cost` / `rate_limits` are built
# in exactly one place - the status-line input builder - which no hook sees.
# What every hook DOES get is transcript_path, and the transcript's assistant
# records carry the raw `message.usage` block the CLI itself divides by.

function Get-LwgTailLines {
    <#
      The last lines of a (possibly very large) text file, read by seeking to
      the final $Bytes and decoding only that.

      Get-Content -Tail does the same job but costs ~70 ms on a 2.5 MB
      transcript and grows with the file; this is a fixed ~2 ms because it never
      touches the head. On a hook that runs at every single turn end, against a
      transcript that only ever gets longer, that difference is the difference
      between a governance layer you keep and one you switch off.

      The first line of the window is DROPPED whenever the window did not start
      at byte 0, because seeking lands mid-line and a half-record is not a
      record. Emitted as a normal stream - callers must wrap in @().
    #>
    param(
        [AllowEmptyString()][AllowNull()][string]$Path,
        [int]$Bytes = 65536
    )

    $out = @()
    try {
        if ([string]::IsNullOrWhiteSpace($Path)) { return $out }
        $fi = Get-Item -LiteralPath $Path -ErrorAction Stop
        $len = $fi.Length
        if ($len -le 0) { return $out }

        $start = [Math]::Max(0, $len - $Bytes)
        $count = [int]($len - $start)

        $fs = $null
        $buf = New-Object byte[] $count
        try {
            $fs = [System.IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            [void]$fs.Seek($start, [IO.SeekOrigin]::Begin)
            $read = 0
            while ($read -lt $count) {
                $n = $fs.Read($buf, $read, $count - $read)
                if ($n -le 0) { break }
                $read += $n
            }
        } finally { if ($fs) { $fs.Dispose() } }

        $text = [Text.UTF8Encoding]::new($false).GetString($buf, 0, $read)
        # Get-Content strips a UTF-8 BOM; decoding bytes ourselves does not, and
        # a BOM left on the front of line 1 makes ConvertFrom-Json reject that
        # record. PS 5.1's Add-Content -Encoding utf8 writes one, so any log this
        # plugin inherited rather than wrote can carry it.
        if ($start -eq 0 -and $text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
        # .Split on a char, not `-split "`r?`n"`: the latter is a regex, and
        # first use of the regex engine in a fresh PowerShell process costs more
        # than the entire read it is splitting.
        $lines = $text.Split([char]10)
        # Seeking lands mid-line unless we started at the very beginning.
        $first = if ($start -gt 0) { 1 } else { 0 }
        $acc = New-Object 'System.Collections.Generic.List[string]'
        for ($i = $first; $i -lt $lines.Length; $i++) {
            $l = $lines[$i].TrimEnd([char]13)
            if ($l.Length -gt 0) { [void]$acc.Add($l) }
        }
        # Plain assignment then a plain `return`, deliberately - NOT `return
        # ,$acc`. The comma operator would wrap the collection so the caller's
        # @() preserved the wrapper and saw Count 1: the exact bug that made the
        # module counter report 1/12 and every Phase 4 deny rule never fire.
        # Callers want the LINES, so the output stream must unroll normally.
        $out = $acc.ToArray()
    } catch { }
    return $out
}

function Read-LwgAppendedLines {
    <#
      The COMPLETE lines a file has grown by since byte $Offset. Returns a
      HASHTABLE:

        @{ lines; offset; truncated; reset }

        lines      the new complete lines, oldest first (an array, so .Count works)
        offset     the byte offset to pass in next time - always just past the
                   last newline actually consumed, never mid-record
        truncated  more than $MaxBytes appeared at once, so the region was
                   SKIPPED rather than read; offset jumps to EOF and the caller
                   must treat its own picture as incomplete
        reset      the file was shorter than $Offset, i.e. replaced or truncated,
                   so reading restarted from 0

      This is what makes a per-turn transcript scan affordable: the cost is the
      size of ONE turn's growth, not the size of the transcript, so it does not
      creep upward as a session gets long.

      A partially written last record is deliberately left unconsumed - the
      offset stops at the final newline, so the next call picks that record up
      whole rather than parsing half of it and discarding it.

      A hashtable, so the result survives the function boundary un-enumerated -
      the same reason Get-LwgRepoInfo and Get-LwgDocRules return hashtables.
    #>
    param(
        [AllowEmptyString()][AllowNull()][string]$Path,
        [long]$Offset = 0,
        [int]$MaxBytes = 2097152
    )

    $r = @{ lines = @(); offset = $Offset; truncated = $false; reset = $false }
    try {
        if ([string]::IsNullOrWhiteSpace($Path)) { return $r }
        $len = [long](Get-Item -LiteralPath $Path -ErrorAction Stop).Length

        # A file SHORTER than where we left off is not the file we were reading -
        # a new session, a rotated log. Start again rather than seek past the end.
        if ($Offset -lt 0 -or $Offset -gt $len) { $Offset = 0; $r.reset = $true; $r.offset = 0 }

        $avail = $len - $Offset
        if ($avail -le 0) { $r.offset = $len; return $r }

        # Bounded on purpose. One turn that emitted an enormous tool result must
        # not turn turn-end into a multi-megabyte scan, so past the cap the
        # region is skipped and the caller is TOLD it was skipped. Silently
        # reading a prefix would leave the caller believing it had seen
        # everything, which is the failure mode this plugin exists to catch.
        if ($avail -gt $MaxBytes) { $r.offset = $len; $r.truncated = $true; return $r }

        $count = [int]$avail
        $buf   = New-Object byte[] $count
        $fs    = $null
        $read  = 0
        try {
            $fs = [System.IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            [void]$fs.Seek($Offset, [IO.SeekOrigin]::Begin)
            while ($read -lt $count) {
                $n = $fs.Read($buf, $read, $count - $read)
                if ($n -le 0) { break }
                $read += $n
            }
        } finally { if ($fs) { $fs.Dispose() } }

        # Everything after the last newline is a record still being written.
        $last = -1
        for ($i = $read - 1; $i -ge 0; $i--) { if ($buf[$i] -eq 10) { $last = $i; break } }
        if ($last -lt 0) { return $r }

        # Offsets always land immediately after a newline, so the window never
        # starts in the middle of a UTF-8 sequence and decoding is safe.
        $text = [Text.UTF8Encoding]::new($false).GetString($buf, 0, $last + 1)
        if ($Offset -eq 0 -and $text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }

        $acc = New-Object 'System.Collections.Generic.List[string]'
        foreach ($l in $text.Split([char]10)) {
            $t = $l.TrimEnd([char]13)
            if ($t.Length -gt 0) { [void]$acc.Add($t) }
        }
        $r.lines  = $acc.ToArray()
        $r.offset = $Offset + $last + 1
    } catch { }
    return $r
}

function Get-LwgTranscriptUsage {
    <#
      Token occupancy from the most recent assistant turn in a transcript.

      Returns a hashtable @{ model; input; cache_read; cache_creation; output;
      total_input } or $null when nothing usable was found. `total_input` is
      input + cache_creation + cache_read, which is exactly the numerator the
      CLI uses for context_window.used_percentage (verified against its own
      helper: used = round(total_input / window * 100), clamped to 0..100).

      Only the tail is read. This runs on Stop, i.e. at every turn end, and the
      transcript grows without bound - reading it whole would make the governance
      layer the slowest thing in the turn.
    #>
    # NOT Mandatory, and AllowEmptyString: a hook payload without a
    # transcript_path is a normal thing (garbage stdin, a synthetic event), and
    # a Mandatory [string] rejects '' with a binding exception before the body
    # runs - which would log an AdvisoryError every time instead of quietly
    # having nothing to say.
    param(
        [AllowEmptyString()][AllowNull()][string]$Path,
        [int]$Bytes = 65536
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
        if (-not (Test-Path -LiteralPath $Path)) { return $null }
        $size = (Get-Item -LiteralPath $Path -ErrorAction Stop).Length

        # A byte window rather than a line count, so the cost does not grow with
        # the transcript. 64 KB spans the last assistant turn in normal use; the
        # widening retry covers the case where one enormous tool result sits
        # between here and it. Widening only ever happens when the narrow window
        # found nothing, so the common path stays cheap.
        foreach ($window in @($Bytes, ($Bytes * 8), ($Bytes * 32))) {
            $lines = @(Get-LwgTailLines -Path $Path -Bytes $window)

            for ($i = $lines.Count - 1; $i -ge 0; $i--) {
                $line = $lines[$i]
                # Cheap reject before the expensive parse - most records are not
                # assistant turns and JSON parsing dominates the cost here.
                if ($line -notlike '*"usage"*') { continue }
                if ($line -notlike '*"assistant"*') { continue }

                $rec = $null
                try { $rec = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
                if ($null -eq $rec -or $rec.type -ne 'assistant') { continue }
                # Sidechain records are a subagent's turns, not the main thread's
                # context. Counting them would report a worker's occupancy as the
                # session's.
                if ($rec.isSidechain -eq $true) { continue }
                $u = $rec.message.usage
                if ($null -eq $u) { continue }

                # [int]$null is 0 in PowerShell, so an absent field contributes
                # nothing rather than throwing.
                $inp = [int]$u.input_tokens
                $cr  = [int]$u.cache_read_input_tokens
                $cc  = [int]$u.cache_creation_input_tokens
                $out = [int]$u.output_tokens

                return @{
                    model          = [string]$rec.message.model
                    input          = $inp
                    cache_read     = $cr
                    cache_creation = $cc
                    output         = $out
                    total_input    = ($inp + $cc + $cr)
                }
            }

            # The window already covered the whole file - widening cannot help.
            if ($window -ge $size) { break }
        }
    } catch { }
    return $null
}

# The CLI resolves a context window to exactly one of two values: 200_000, or
# 1_000_000 for a model tagged [1m] or flagged native-1m for this account. That
# choice depends on account entitlements the hook cannot see, so it is resolved
# here from three sources in descending order of trust, and every record says
# which one was used. A percentage whose denominator is a guess is worse than no
# percentage at all, so an untrusted denominator suppresses the advisory instead
# of colouring it.
$script:LwgContextWindowDefault  = 200000
$script:LwgContextWindowExtended = 1000000

function Get-LwgContextWindow {
    <#
      Resolve the context window for a model id.

      Returns @{ tokens = <int>; source = 'config'|'1m-tag'|'observed'|'default' }.

        config    an explicit entry in module_config.context_pressure.window_tokens
        1m-tag    the model id carries the [1m] suffix, which the CLI itself
                  reads as one million
        observed  this model has previously been seen holding more than 200k
                  tokens in a real turn, which is proof its window is the larger
                  of the two - self-correcting, and evidence rather than a guess
        default   none of the above; 200k, and treated as UNTRUSTED by the caller
    #>
    param([string]$Model, $Config, [hashtable]$Observed)

    $m = [string]$Model
    if ([string]::IsNullOrWhiteSpace($m)) {
        return @{ tokens = $script:LwgContextWindowDefault; source = 'default' }
    }

    try {
        $map = Get-LwgModuleOption -Config $Config -Module 'context_pressure' -Key 'window_tokens' -Default $null
        if ($null -ne $map) {
            $v = $map.$m
            if ($null -ne $v -and ([int]$v) -gt 0) {
                return @{ tokens = [int]$v; source = 'config' }
            }
        }
    } catch { }

    if ($m -match '\[1m\]') {
        return @{ tokens = $script:LwgContextWindowExtended; source = '1m-tag' }
    }

    try {
        if ($null -ne $Observed) {
            $seen = $Observed[$m]
            if ($null -ne $seen -and ([int]$seen) -gt $script:LwgContextWindowDefault) {
                return @{ tokens = $script:LwgContextWindowExtended; source = 'observed' }
            }
        }
    } catch { }

    return @{ tokens = $script:LwgContextWindowDefault; source = 'default' }
}

# --- edited-path classification --------------------------------------------
# docs_coupling asks one question - did source change while documentation did
# not - so a path is DOC, SOURCE, or NEITHER. Neither is the important bucket:
# lockfiles, JSON and data churn are not evidence that anything user-visible
# changed, and counting them as source is how this module would turn into noise.

$script:LwgDocExtensions = @('.md', '.mdx', '.markdown', '.expl', '.rst', '.adoc', '.txt')
$script:LwgDocNames      = @('readme', 'changelog', 'changes', 'history', 'contributing', 'license', 'notice')
$script:LwgDocDirs       = @('docs', 'doc', 'documentation')
$script:LwgSourceExtensions = @(
    '.ps1', '.psm1', '.psd1', '.py', '.js', '.jsx', '.mjs', '.cjs', '.ts', '.tsx',
    '.go', '.rs', '.java', '.kt', '.scala', '.cs', '.rb', '.php', '.swift',
    '.c', '.h', '.cc', '.cpp', '.hpp', '.m', '.mm', '.sh', '.bash', '.zsh',
    '.sql', '.vue', '.svelte', '.dart', '.ex', '.exs', '.lua', '.pl', '.r'
)

function Get-LwgDocRules {
    <#
      Resolve the docs_coupling classification lists ONCE, into HashSets.

      Built separately from Get-LwgPathClass because it used to be inline, and
      that made classification O(paths x 4 config lookups x linear -contains):
      400 calls cost 284 ms, which on a hook that runs at every turn end is not
      a micro-optimisation, it is the difference between shipping and not. The
      sets also make each lookup O(1) instead of a linear scan of 39 extensions.
    #>
    param($Config)

    # The sets are built INLINE, deliberately. A helper `function New-Set { ...
    # return $s }` reads better and is silently wrong: a HashSet is IEnumerable,
    # so `return` enumerates it and the caller gets back an Object[]. .Contains
    # then resolves against the array instead of the set, quietly loses the
    # case-insensitive comparer, and every classification degrades without a
    # single error. That is the same unrolling trap that has already shipped
    # twice in this repo, wearing a different hat - once making the module
    # counter report 1/12, once making every deny rule never fire.
    #
    # A hashtable is NOT enumerated on return, so wrapping the sets in one is
    # what makes them survive the function boundary intact. Get-LwgDocRules is
    # asserted on directly in the test suite for exactly this reason.
    $rules = @{
        doc_ext  = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        doc_dir  = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        doc_name = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        src_ext  = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    }
    foreach ($i in @(Get-LwgModuleOption -Config $Config -Module 'docs_coupling' -Key 'doc_extensions'    -Default $script:LwgDocExtensions))    { if ($null -ne $i) { [void]$rules.doc_ext.Add([string]$i) } }
    foreach ($i in @(Get-LwgModuleOption -Config $Config -Module 'docs_coupling' -Key 'doc_directories'   -Default $script:LwgDocDirs))          { if ($null -ne $i) { [void]$rules.doc_dir.Add([string]$i) } }
    foreach ($i in @(Get-LwgModuleOption -Config $Config -Module 'docs_coupling' -Key 'doc_names'         -Default $script:LwgDocNames))         { if ($null -ne $i) { [void]$rules.doc_name.Add([string]$i) } }
    foreach ($i in @(Get-LwgModuleOption -Config $Config -Module 'docs_coupling' -Key 'source_extensions' -Default $script:LwgSourceExtensions)) { if ($null -ne $i) { [void]$rules.src_ext.Add([string]$i) } }
    return $rules
}

function Get-LwgPathClass {
    <#
      'doc', 'source' or 'other' for one edited path. Doc wins over source, so a
      literate-programming file with a code extension under docs/ still counts as
      documentation.

      Pass -Rules from Get-LwgDocRules when classifying more than one path; the
      -Config fallback is a convenience for single calls and tests and rebuilds
      the rules every time.
    #>
    param([string]$Path, $Config, $Rules)

    if ([string]::IsNullOrWhiteSpace($Path)) { return 'other' }
    if ($null -eq $Rules) { $Rules = Get-LwgDocRules -Config $Config }

    # .NET Split with RemoveEmptyEntries rather than `Split('/') | Where-Object`:
    # a pipeline per path costs more than every set lookup below put together,
    # and this runs once per edited file at every turn end.
    $segs = $Path.Replace('\', '/').Split([char]'/', [StringSplitOptions]::RemoveEmptyEntries)
    if ($segs.Length -eq 0) { return 'other' }
    $leaf = $segs[$segs.Length - 1]

    $ext = ''
    $dot = $leaf.LastIndexOf('.')
    if ($dot -gt 0) { $ext = $leaf.Substring($dot) }
    $stem = if ($dot -gt 0) { $leaf.Substring(0, $dot) } else { $leaf }

    # A path SEGMENT, never a substring: 'docs' must not match 'src/docsify'.
    foreach ($s in $segs) { if ($Rules.doc_dir.Contains($s)) { return 'doc' } }
    if ($ext -ne '' -and $Rules.doc_ext.Contains($ext)) { return 'doc' }
    if ($Rules.doc_name.Contains($stem)) { return 'doc' }
    if ($ext -ne '' -and $Rules.src_ext.Contains($ext)) { return 'source' }
    return 'other'
}

# --- health-log reader -----------------------------------------------------

function Get-LwgHealthRecords {
    <#
      Parsed records from health.jsonl, newest last, optionally narrowed to one
      session. Emitted as a normal stream - callers MUST wrap in @(), exactly as
      with the other list-returning helpers here. Do NOT change this to
      `return ,$out`: the comma operator hands back a one-element array wrapping
      the list, @() then keeps that wrapper, and every caller sees Count 1. That
      mistake has already shipped twice in this repo - once making the module
      counter report 1/12, once making every deny rule silently never fire.
    #>
    param([string]$Session, [int]$Tail = 400, [string]$Event)

    $out = @()
    try {
        $path = Join-Path (Get-LwgStateDir) 'health.jsonl'
        if (-not (Test-Path -LiteralPath $path)) { return $out }
        $lines = @(Get-LwgTailLines -Path $path -Bytes 524288)
        if ($lines.Count -gt $Tail) { $lines = @($lines[($lines.Count - $Tail)..($lines.Count - 1)]) }

        $hasSession = -not [string]::IsNullOrWhiteSpace($Session)
        $hasEvent   = -not [string]::IsNullOrWhiteSpace($Event)

        foreach ($line in $lines) {
            # Substring-reject before parsing. ConvertFrom-Json dominates the
            # cost here, and on a Stop hook most records are the wrong session
            # or the wrong event - in the live log, Stop records outnumber
            # SubagentStop two to one.
            #
            # These are PRE-filters only. The authoritative checks are the field
            # comparisons below, so a session id or event name that merely
            # appears somewhere else in the line is still rejected properly.
            if ($hasSession -and $line -notlike "*$Session*") { continue }
            if ($hasEvent   -and $line -notlike "*$Event*")   { continue }
            $r = $null
            try { $r = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            if ($null -eq $r) { continue }
            if ($hasSession -and ([string]$r.session) -ne $Session) { continue }
            if ($hasEvent   -and ([string]$r.event)   -ne $Event)   { continue }
            $out += $r
        }
    } catch { }
    return $out
}

# --- mission anchors --------------------------------------------------------
# NOTHING CALLS ANY OF THIS. Every function from here to Test-LwgMissionAccounted
# was built for mission_drift, and that module was removed; the helpers were
# left standing rather than deleted in the same pass, so read the present tense
# below as a description of code with no caller, not of live behaviour. The one
# exception is Get-LwgPromptText, which lib/gate_stop.ps1 still calls.
#
# mission_drift asked one question: is the work still serving anything the user
# actually asked for? Answering it needs a record of what was asked, and the
# cheapest honest source is the transcript - every hook receives
# transcript_path, and the user's typed prompts are in it as plain records.
#
# WHY NOT A UserPromptSubmit HOOK. That is the obvious place to capture a
# mission and it was rejected on cost. Each registered hook is its own
# PowerShell 5.1 process - a measured 284 ms floor - and that process is spawned
# whether or not the module is switched on, because a hook registration cannot
# be made conditional. A module that ships default-off would then be charging
# every prompt 284 ms for nothing. Reading the transcript incrementally instead
# costs a few milliseconds inside a process that already exists, and costs
# exactly zero when the flag is off.
#
# The anchors are deliberately CRUDE and the matching is deliberately GENEROUS:
# every ambiguous case is resolved towards "this work is accounted for", because
# the failure this module must not have is warning at someone who is doing
# exactly what they were asked.

# Segments that appear in almost every absolute path on Windows and therefore
# distinguish nothing. Matching on these would make every edit look accounted
# for, which is the safe direction but a useless one.
$script:LwgMissionStopSegments = @(
    'users', 'home', 'documents', 'desktop', 'downloads', 'appdata', 'local',
    'locallow', 'roaming', 'tmp', 'temp', 'var', 'opt', 'mnt', 'srv', 'programdata'
)

# Instruction vocabulary. These are the words a prompt is made of rather than
# the things a prompt is about, so they must never anchor anything.
$script:LwgMissionStopWords = @(
    'about', 'after', 'again', 'against', 'also', 'always', 'another', 'anything',
    'because', 'been', 'before', 'being', 'below', 'better', 'build', 'change',
    'changes', 'check', 'code', 'could', 'default', 'does', 'doing', 'done',
    'dont', 'down', 'each', 'else', 'every', 'exactly', 'file', 'files', 'first',
    'fix', 'from', 'give', 'good', 'have', 'here', 'into', 'just', 'keep', 'know',
    'last', 'like', 'line', 'lines', 'made', 'make', 'making', 'many', 'more',
    'most', 'must', 'need', 'needs', 'never', 'next', 'niceties', 'note', 'only',
    'other', 'over', 'please', 'read', 'really', 'right', 'same', 'says', 'should',
    'show', 'similar', 'since', 'some', 'still', 'such', 'sure', 'take', 'test',
    'tests', 'than', 'that', 'them', 'then', 'there', 'these', 'they', 'thing',
    'things', 'think', 'this', 'those', 'through', 'time', 'told', 'update',
    'used', 'using', 'very', 'want', 'well', 'were', 'what', 'when', 'where',
    'which', 'while', 'will', 'with', 'without', 'work', 'would', 'write', 'your'
)

function Get-LwgPromptText {
    <#
      The text of a TYPED USER PROMPT from one parsed transcript record, or
      $null for anything that is not one.

      Everything ambiguous returns $null. A tool result is also a record of
      type 'user', and a subagent's prompts are the orchestrator's words rather
      than the operator's, so both are rejected - anchoring on either would let
      the plugin's own output feed back into its own drift assessment.
    #>
    param($Record)

    try {
        if ($null -eq $Record) { return $null }
        if ([string]$Record.type -ne 'user') { return $null }
        if ($Record.isSidechain -eq $true)   { return $null }
        # Present only on tool-result records, which are the other thing that
        # arrives wearing role 'user'.
        if ($null -ne $Record.toolUseResult) { return $null }

        $c = $Record.message.content
        if ($null -eq $c) { return $null }
        if ($c -is [string]) { return $c }

        $parts = @()
        foreach ($b in @($c)) {
            if ($b -is [string]) { $parts += $b; continue }
            if ($null -ne $b.tool_use_id) { return $null }
            if ([string]$b.type -eq 'text' -and $b.text) { $parts += [string]$b.text }
        }
        if ($parts.Count -eq 0) { return $null }
        return ($parts -join ' ')
    } catch { }
    return $null
}

function New-LwgMissionAnchors {
    <#
      An empty anchor set: @{ paths; words; count }, both HashSets.

      A hashtable wrapper, and not for tidiness - a HashSet is IEnumerable, so
      returning one bare makes PowerShell enumerate it and hand the caller an
      Object[] with no comparer. The same unrolling trap has shipped three times
      in this repo; Get-LwgDocRules carries the long version of this note.
    #>
    return @{
        paths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        words = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        total = 0
    }
}

# Token separators, as character codes rather than a literal string. PowerShell
# 5.1 reads a BOM-less .ps1 as ANSI, so a curly quote typed into this file would
# decode differently on another machine's code page; the rest of this repo is
# deliberately pure ASCII for the same reason. 0x2018-0x201D are the curly
# quotes a prompt pasted out of a document will actually contain.
$script:LwgMissionSeparators = [char[]]@(
    32, 9, 13, 10, 44, 59, 33, 63, 40, 41, 91, 93, 123, 125, 60, 62, 124, 42, 61,
    34, 39, 96, 0x2018, 0x2019, 0x201C, 0x201D
)

function Get-LwgMissionScope {
    <#
      The path segments that carry no information for THIS session, as a
      HashSet: the universal ones above, plus every segment at or above the
      workspace's parent.

      That second half is what makes matching work at all here. Prompts in this
      environment routinely paste absolute paths, and every absolute path on
      this machine shares 'c:', 'users', the account name and the HQ folders. If
      those counted, one pasted path would make every edit anywhere on the disk
      look accounted for and the module could never fire. Segments from the
      workspace directory DOWN are kept, because those are the ones that
      actually say where the work is.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Root)

    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($s in $script:LwgMissionStopSegments) { [void]$set.Add($s) }
    try {
        if (-not [string]::IsNullOrWhiteSpace($Root)) {
            $parent = Split-Path -Path $Root.TrimEnd('\', '/') -Parent
            if (-not [string]::IsNullOrWhiteSpace($parent)) {
                foreach ($seg in $parent.Replace('\', '/').Split([char]'/', [StringSplitOptions]::RemoveEmptyEntries)) {
                    [void]$set.Add($seg)
                }
            }
        }
    } catch { }
    return @{ stop = $set }
}

function Get-LwgPathSegments {
    <#
      The distinguishing pieces of one path: each segment, plus the stem of the
      leaf, lowercased, minus anything in $Scope.stop, drive letters and
      fragments shorter than three characters.

      Emitted as a normal stream - callers must wrap in @(), like every other
      list-returning helper in this file.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Path, $Scope)

    $out = @()
    if ([string]::IsNullOrWhiteSpace($Path)) { return $out }
    try {
        $stop = $(if ($null -ne $Scope) { $Scope.stop } else { $null })
        $segs = $Path.Replace('\', '/').Split([char]'/', [StringSplitOptions]::RemoveEmptyEntries)
        foreach ($raw in $segs) {
            $s = $raw.Trim().ToLowerInvariant()
            if ($s.Length -lt 3)      { continue }
            if ($s -match '^[a-z]:$') { continue }
            if ($null -ne $stop -and $stop.Contains($s)) { continue }
            $out += $s
            $dot = $s.LastIndexOf('.')
            if ($dot -ge 3) {
                $stem = $s.Substring(0, $dot)
                if ($stem.Length -ge 3) { $out += $stem }
            }
        }
    } catch { }
    return $out
}

function Add-LwgMissionAnchors {
    <#
      Fold one prompt into an anchor set, in place. Returns the number of PATH
      anchors the prompt contributed, which is the number that decides whether
      the module has any basis to speak at all.

      Two kinds of anchor, and the difference matters:

        paths  concrete things the user named - a path, or a bare filename with
               an extension. Only these give the module standing: with no path
               anchor anywhere in the session it has no idea what the work was
               supposed to touch and stays silent.
        words  ordinary words of four or more letters. These can only ever
               EXCUSE a file, never accuse one, so a loose word match is
               harmless - it suppresses a warning, and suppression is the safe
               direction.
    #>
    param([string]$Text, $Anchors, $Scope, [int]$MaxAnchors = 400)

    $added = 0
    if ([string]::IsNullOrWhiteSpace($Text) -or $null -eq $Anchors) { return $added }
    try {
        # Injected wrappers are not the user speaking. A system-reminder or the
        # stdout of a slash command would otherwise contribute anchors the user
        # never wrote - including, in this plugin's case, its own advisory text.
        #
        # Guarded on a plain IndexOf, and the three block forms share ONE
        # alternation, because a prompt with no angle bracket in it is the
        # common case and .NET compiles each distinct pattern on first use -
        # about 15 ms each in a fresh process, on a hook that runs at every turn
        # end. Four unconditional Replace calls cost more than everything else
        # this function does put together.
        $clean = $Text
        if ($clean.IndexOf([char]'<') -ge 0) {
            $clean = [regex]::Replace($clean, '(?s)<(system-reminder|local-command-stdout|local-command-stderr)>.*?</\1>', ' ')
            $clean = [regex]::Replace($clean, '<[^>\r\n]{1,60}>', ' ')
        }

        foreach ($tok in $clean.Split($script:LwgMissionSeparators, [StringSplitOptions]::RemoveEmptyEntries)) {
            if ($Anchors.total -ge $MaxAnchors) { break }
            $t = $tok.Trim().Trim('.', ':', '-', '_')
            if ($t.Length -lt 3) { continue }

            # --- THE REDACTOR'S OWN MARKER IS NOT SOMETHING ANYONE NAMED -----
            # '[' and ']' are separators here, so a value that Get-LwgRedacted
            # masked upstream arrives as the bare token REDACTED - which matches
            # the ordinary-word pattern below and is in no stop list. Measured
            # before this line existed: the word set came back holding
            # 'redacted', a word no prompt contained, written to
            # advisory-<sessionkey>.json and standing ready to EXCUSE any file
            # whose stem happens to be 'redacted'.
            #
            # Ordinal and case-sensitive, matching how the marker is emitted, so
            # a prompt that genuinely discusses "redacted output" in lower case
            # still anchors. The prefix form covers '[REDACTED:<id>]' too, whose
            # inner token would not match the word pattern anyway - it is here so
            # that the rule does not depend on that accident.
            if ($t.StartsWith('REDACTED', [StringComparison]::Ordinal)) { continue }

            # --- SHAPE FILTER: A CREDENTIAL IS NOT A NAME --------------------
            # WHY THIS EXISTS WHEN THE PROMPT IS ALREADY REDACTED. The caller in
            # lib\stop_advisories.ps1 puts the whole prompt through
            # Get-LwgRedacted before it reaches here, and that is the right
            # place - it is the only point where the sentence is still intact.
            # But that helper works from an ENUMERATED pattern list plus a
            # keyword list, and it says so in its own header: a credential in a
            # shape nobody enumerated, with no key name in front of it, arrives
            # at this loop untouched.
            #
            # AND TOKENISING IS NOT REDACTION. What arrives untouched does not
            # merely survive. '/' is in the base64 alphabet and this function
            # reads '/' as a PATH SEPARATOR, so key material is PROMOTED into
            # the path set - the anchor kind the advisory QUOTES BACK in its
            # systemMessage - displacing the file the operator actually named.
            # Measured at 19bb85d on the prompt in issue #5: one AWS secret
            # access key contributed three path anchors and took two of the four
            # quoted slots.
            #
            # BY SHAPE, NEVER BY VENDOR. A vendor list is what already failed
            # here; adding a sixth prefix to it would fix the shapes someone
            # thought of and nothing else. The question asked instead is the
            # module's own question: could this token plausibly NAME something -
            # a file, a directory, or a word?
            #
            # IT DECOMPOSES THE TOKEN RATHER THAN JUDGING IT WHOLE, and that is
            # a CORRECTION of the first version of this filter rather than a
            # refinement of it. That version tested the token as one string and
            # exempted anything containing ':' or '@', on the reasoning that a
            # drive letter or a URL is a shape it is not competent to judge.
            # MEASURED, that exemption was a hole wide enough to drive issue #5's
            # own specimen through:
            #
            #   this presigned url 403s: https://s3.example.com/wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY - why?
            #
            # One ':' in the scheme waved the whole token past the filter, and
            # the advisory rendered "you named: bpxrficyexamplekey, https:,
            # k7mdeng, s3.example". A 'C:/' prefix did the same. The exemption
            # also turned out to be protecting almost nothing - of fourteen
            # ':'/'@' tokens checked, thirteen survive the rest of the filter
            # without it - so it is gone rather than patched.
            #
            # WHAT REPLACES IT. The token is split on '/' AND '\', each segment
            # is classified, and only a MAXIMAL RUN of consecutive
            # credential-shaped segments is dropped - the surviving segments are
            # rejoined and go on to anchor normally. That is why the URL above
            # keeps 'https:' and 's3.example.com' and loses only the three
            # segments that are the key. Judging the token whole cannot do this:
            # 'https' and 'example' are word-like, so a whole-token test reads
            # the entire URL as a name and keeps the key with it.
            #
            # A SEGMENT IS CREDENTIAL-SHAPED when it is 3 characters or more,
            # contains a capital, is not a short all-caps acronym (API, DTO,
            # HTTP), does not match the filename pattern used below, and carries
            # no run of five or more lowercase letters containing a vowel. That
            # last clause is the discriminator: real names are made of WORDS -
            # getUserAuthenticationToken has 'uthentication',
            # HTTPServerConnectionPool has 'onnection', workspace has all of
            # itself. Base64 does not; measured, the AWS specimen's longest
            # lowercase run is 3 and the JWT specimen's is 2.
            #
            # A RUN IS DROPPED only when the concatenation is at least
            # $minShape characters, is genuinely mixed case - two or more of
            # each - and is itself free of a word-like lowercase run. The
            # mixed-case clause is what saves docs/CONFIGURATION/DEPLOYMENT,
            # whose two SCREAMING_CASE segments concatenate to 23 characters of
            # pure capitals.
            #
            # ONE THRESHOLD, USED TWICE, and deliberately a variable rather than
            # two literals: the cheap integer gate on the whole token and the
            # test on the run have to move together, or lowering one silently
            # leaves the other pinning nothing.
            #
            # MEASURED AGAINST REAL PATHS, because the cost direction here is
            # the module going permanently silent. Every tracked path in this
            # repository, in all three spellings a prompt actually pastes
            # (relative, absolute with '/', absolute with '\'), plus a
            # hand-built corpus of CamelCase-heavy .NET, Java, PHP, Swift and
            # React paths - 296 tokens - was run through this function twice,
            # once with the filter live and once with $minShape raised past
            # every input, and the two anchor sets DIFFER ON EXACTLY ONE TOKEN:
            # the AppData/Local/Temp case named at the bottom of this block.
            # That is the false-positive rate, measured rather than asserted.
            #
            # WHAT THIS DOES NOT CATCH, and each one is measured rather than
            # reasoned about, because a filter that reads as though it were
            # complete is the overstatement this repository exists to remove:
            #
            #   * A SINGLE-CASE TOKEN. The run test requires both cases present,
            #     so a 32-character lowercase hex API key and an ALL-CAPS key are
            #     both untouched. That is not a gap issue #5 enumerates - the
            #     issue text does not mention hex at all; the claim lives in
            #     lib\stop_advisories.ps1 and is unverified there. It is stated
            #     here because it is true of THIS code, not because a document
            #     says so.
            #   * A RANDOM KEY THAT HAPPENS TO CONTAIN A WORD-LIKE RUN, which is
            #     a RATE rather than an absolute. MEASURED by driving this
            #     function over 10,000 random strings per length per alphabet and
            #     counting how many left an anchor that is part of the string:
            #
            #                        base64 (A-Za-z0-9+/)   alnum-62 (A-Za-z0-9)
            #         length 20           11.9%                    8.4%
            #         length 32           11.6%                   13.7%
            #         length 40           12.7%                   16.5%
            #
            #     ALNUM-62 IS THE WORSE NUMBER AT 32 AND 40 AND IS THE ONE TO
            #     PLAN AGAINST: without '+' and '/' the characters are letters
            #     more often, so a five-letter lowercase run turns up more often.
            #     Its rate RISES with length - 8.4 to 16.5 - where base64's is
            #     flat; a longer key is not a safer one. Roughly one random
            #     40-character alphanumeric key in six still gets through.
            #
            #     AND THIS IS NOT AN IMPROVEMENT ON WHAT IT REPLACED. The
            #     whole-token filter measured 12.9% at base64 length 40 against
            #     this one's 12.7%, which is the same number. Decomposing the
            #     token closed the URL bypass and made the two path separators
            #     agree; it did not make the entropy test better, and nothing
            #     here should be read as claiming it did.
            #   * A CREDENTIAL SHORTER THAN $minShape, or one carried in a token
            #     shorter than that. The floor is what buys the false-positive
            #     margin above and it cuts both ways.
            #   * A RUN OF LEGITIMATE CamelCase DIRECTORY SEGMENTS that reaches
            #     $minShape characters with no word-like lowercase run in any of
            #     them. Measured on the corpora above this did not occur, but
            #     <profile>/AppData/Local/Temp/XYZAbcDefGhi is a real shape
            #     that loses its tail - three of those four segments are in
            #     $script:LwgMissionStopSegments and were being discarded anyway,
            #     so the cost there is one generated directory name.
            $minShape = 20
            if ($t.Length -ge $minShape) {
                $segs = $t.Split([char[]]@('/', '\'), [StringSplitOptions]::RemoveEmptyEntries)
                $n    = $segs.Count
                if ($n -gt 0) {
                    $cred = New-Object 'bool[]' $n
                    for ($si = 0; $si -lt $n; $si++) {
                        $s = $segs[$si]
                        # A one- or two-character segment CONTINUES a run rather
                        # than breaking it. It names nothing on its own and
                        # Get-LwgPathSegments discards it anyway, but as a run
                        # BREAK it was splitting key material into pieces that
                        # each fell under the floor: measured, a 20-character
                        # base64 run leaked 17.8% of the time while these broke
                        # runs and 11.9% once they stopped. A drive letter is the
                        # visible case and it costs nothing - 'C:' is discarded
                        # downstream whether this drops it or not.
                        if ($s.Length -lt 3)                { $cred[$si] = $true; continue }
                        if ($s -cnotmatch '[A-Z]')          { continue }
                        if ($s -cmatch '^[A-Z0-9]{1,5}$')   { continue }
                        if ($s -match '^[A-Za-z0-9_+\-][\w.+\-]*\.[A-Za-z][A-Za-z0-9]{0,5}$') { continue }
                        $sw = $false
                        foreach ($m in [regex]::Matches($s, '[a-z]{5,}')) {
                            if ($m.Value -match '[aeiouy]') { $sw = $true; break }
                        }
                        if (-not $sw) { $cred[$si] = $true }
                    }

                    $drop = New-Object 'bool[]' $n
                    $si = 0
                    while ($si -lt $n) {
                        if (-not $cred[$si]) { $si++; continue }
                        $sj = $si
                        while ($sj -lt $n -and $cred[$sj]) { $sj++ }
                        # Rejoined WITH the separator, for two reasons that both
                        # bite. Length: a run has to be measured as it appears
                        # in the prompt, and dropping the separators shortened
                        # every multi-segment run below the floor - measured on
                        # 10,000 random 20-character base64 strings, leakage was
                        # 31.6% joined bare and 17.8% joined this way. Word-runs:
                        # concatenating 'abc' and 'de' manufactures a
                        # five-letter lowercase run that never existed and
                        # rescues the credential that contains it.
                        $joined = ($segs[$si..($sj - 1)] -join '/')
                        if ($joined.Length -ge $minShape -and
                            $joined -cmatch '[A-Z][^A-Z]*[A-Z]' -and
                            $joined -cmatch '[a-z][^a-z]*[a-z]') {
                            $jw = $false
                            foreach ($m in [regex]::Matches($joined, '[a-z]{5,}')) {
                                if ($m.Value -match '[aeiouy]') { $jw = $true; break }
                            }
                            if (-not $jw) { for ($sk = $si; $sk -lt $sj; $sk++) { $drop[$sk] = $true } }
                        }
                        $si = $sj
                    }

                    $anyDrop = $false
                    foreach ($d in $drop) { if ($d) { $anyDrop = $true; break } }
                    if ($anyDrop) {
                        $keptSegs = @()
                        for ($sk = 0; $sk -lt $n; $sk++) { if (-not $drop[$sk]) { $keptSegs += $segs[$sk] } }
                        $t = ($keptSegs -join '/')
                        if ($t.Length -lt 3) { continue }
                    }
                }
            }

            $isPath = ($t.Contains('/') -or $t.Contains('\'))
            # The dot test is a guard, not a shortcut. Without it the filename
            # pattern is compiled the first time any ordinary word reaches this
            # line - about 12 ms in a fresh process, on a hook that runs at every
            # turn end - and a prompt is mostly ordinary words. With it, a prompt
            # that names no file never builds the pattern at all.
            if (-not $isPath -and $t.Length -ge 4 -and $t.IndexOf([char]'.') -gt 0) {
                # A bare filename: stem, dot, ALPHABETIC extension. The extension
                # must start with a letter so that '0.2.0' and 'v1.4' are version
                # numbers rather than files.
                $isPath = ($t -match '^[A-Za-z0-9_+\-][\w.+\-]*\.[A-Za-z][A-Za-z0-9]{0,5}$')
            }

            if ($isPath) {
                foreach ($seg in @(Get-LwgPathSegments -Path $t -Scope $Scope)) {
                    if ($Anchors.paths.Add($seg)) { $Anchors.total++; $added++ }
                }
                continue
            }

            if ($t -match '^[A-Za-z][A-Za-z0-9]{3,}$') {
                $w = $t.ToLowerInvariant()
                if ($script:LwgMissionStopWords -contains $w) { continue }
                if ($Anchors.words.Add($w)) { $Anchors.total++ }
            }
        }
    } catch { }
    return $added
}

function Test-LwgMissionAccounted {
    <#
      Does this edited path relate to anything the user named? True on ANY
      overlap - one shared directory segment, one shared filename stem, or a
      stem that matches an ordinary word from a prompt.

      Deliberately generous. Every near-miss resolved this way is a warning not
      shown, and a warning not shown costs a little recall; the opposite error
      costs the module its credibility and then it gets switched off.
    #>
    param([string]$Path, $Anchors, $Scope)

    if ($null -eq $Anchors) { return $true }
    try {
        foreach ($seg in @(Get-LwgPathSegments -Path $Path -Scope $Scope)) {
            if ($Anchors.paths.Contains($seg)) { return $true }
            if ($Anchors.words.Contains($seg)) { return $true }
        }
    } catch { return $true }
    return $false
}

function Test-LwgPathUnder {
    <#
      Is $Path inside directory $Root? Compared as whole path segments, so
      C:\repo-two is NOT under C:\repo. Purely textual - no disk access, because
      this runs at turn end over every edited path.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Path,
          [AllowEmptyString()][AllowNull()][string]$Root)

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
    try {
        $p = $Path.Replace('\', '/').TrimEnd('/')
        $r = $Root.Replace('\', '/').TrimEnd('/')
        if ($p.Equals($r, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        return $p.StartsWith($r + '/', [StringComparison]::OrdinalIgnoreCase)
    } catch { }
    return $false
}
