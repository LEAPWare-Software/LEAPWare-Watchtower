#requires -version 5
<#
  LW-WATCHTOWER metrics - the transcript indexer and the scoreboard.

      powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-metrics.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-metrics.ps1 -All
      powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-metrics.ps1 -All -Json

  Backs /lw-watchtower:metrics.

  ---------------------------------------------------------------------------
  WHY THIS EXISTS, IN THE OWNER'S OWN WORDS
  ---------------------------------------------------------------------------
  The question was "what do I gain", and the honest answer was that nobody had
  measured it. THE PLUGIN CANNOT CURRENTLY PROVE IT SAVES ANYONE ANYTHING. This
  command is what makes that answerable. It reads the transcripts Claude Code
  has already written and reports how much work left the main thread, what it
  cost in tokens, and - the one that matters, because the whole responsiveness
  design assumes it - WHETHER DELEGATION IS HAPPENING AT ALL.

  ---------------------------------------------------------------------------
  WHAT THIS IS NOT, AND WHY EVERY OTHER COLUMN SAYS NOT DETERMINED
  ---------------------------------------------------------------------------
  This is slice 1 of #165 and it is R2 alone, by the owner's ruling of
  6 September 2026: the indexer and the scoreboard, as a command, reading only
  files that already exist.

      no hook is added            the per-dispatch record is #166's row and the
                                  cost field attaches to it there. A second
                                  per-dispatch ledger in one state directory is
                                  a defect by #165's own finding 6
      no module flag              no `modules` key, no registry entry, and no
                                  hook registration. hooks\hooks.json and
                                  $LwgModuleRegistry are not touched, and their
                                  counts are stated in docs\modules.md rather
                                  than restated here
      no METRICS.md               R9 writes into the operator's repository from a
                                  turn-end hook. It is the last and riskiest part
      no decision rule            R8's STAY/REVERT/EXTEND verdict needs the meter
                                  history and the LCAP rounds this slice has no
                                  source for
      no dollars, ever            R11 is explicit, and it is not softened here

  SO EVERY COLUMN WITH NO SOURCE PRINTS `NOT DETERMINED`. That is a requirement,
  not a fallback. A scoreboard that invents a number is worse than one that says
  it cannot tell, and the rule this plugin has carried since the sitrep command
  that first wrote it was deleted is that unknown is never reported as fine.

  ---------------------------------------------------------------------------
  IT WRITES NOTHING, ANYWHERE
  ---------------------------------------------------------------------------
  No state file, no index cache, no ledger, no marker, nothing in the operator's
  repository. #165 R2.7 specifies a metrics-index.json cache so a second run is
  seconds; it is deliberately NOT in this slice. A cache is a file the
  uninstaller has to know about, the footprint suite has to seed, and the
  operator has to be told about - and the whole local corpus scans in seconds
  already. The scan time is printed on every run so the case for a cache can be
  made from a measurement rather than from an assumption.

  ---------------------------------------------------------------------------
  MASKING
  ---------------------------------------------------------------------------
  A transcript directory name is a working directory with its separators
  replaced, so it carries the operator's account name. NO PATH AND NO DIRECTORY
  NAME FROM THE CORPUS IS EVER PRINTED. The projects root is named by the
  variable that resolved it, not by its value, so the operator can tell which
  tree was read without the path itself landing in whatever the output is pasted
  into. tests\metrics_behaviour.ps1 section S3 is the only thing that guards
  this, and it guards the output rather than the source.

  ---------------------------------------------------------------------------
  EXIT CODES - a caller reads these and nothing else
  ---------------------------------------------------------------------------
      0  a report was produced. An empty corpus is a report: "I looked and there
         was nothing" is a measurement
      3  no report could be produced - the configuration root could not be
         resolved, or the projects directory is not there. The lwg-status
         convention: "I could not look" is not "I looked and it was fine"
#>

param(
    # Report across every project on this machine rather than the one the
    # command was run from. Without it the report is scoped to the repository
    # slug of the current directory; when that cannot be resolved the command
    # says so and falls back to every project, because a scope nobody can name
    # is not a scope.
    [switch]$All,

    # The same figures as one JSON object and nothing else, for a reader that is
    # not a person. The scaled columns in the text report are for legibility;
    # this is where the exact integers are.
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

# Everything printed below is ASCII, for the reason bin\lwg-doctor.ps1 gives:
# this may well be the thing you run when the console encoding is what is broken.
$script:Lines = New-Object System.Collections.ArrayList
$script:Notes = New-Object System.Collections.ArrayList

function Say { param([string]$Text = '') [void]$script:Lines.Add($Text) }
function Note { param([string]$Text) [void]$script:Notes.Add($Text) }

function Get-Median {
    <#
      The median of a list of [long], as a [double]. An empty list has no
      median and returns $null - which the caller renders as NOT DETERMINED
      rather than as zero.
    #>
    param([long[]]$Values)
    $v = @($Values | Sort-Object)
    if ($v.Count -eq 0) { return $null }
    if ($v.Count % 2 -eq 1) { return [double]$v[[int](($v.Count - 1) / 2)] }
    return ([double]$v[($v.Count / 2) - 1] + [double]$v[$v.Count / 2]) / 2.0
}

function Format-Median {
    param($Value)
    if ($null -eq $Value) { return 'NOT DETERMINED' }
    return (Format-LwgMetricsTokens -Value ([long][math]::Round($Value)))
}

function Get-TierFamily {
    <#
      The model family a requested tier alias names.

      #165 R4 compares the tier a dispatch ASKED for against the model that
      actually ran it. The alias is a tier name ('opus'), the resolved id is a
      model ('claude-opus-5[1m]'), and the comparison is only meaningful at the
      family level: 'claude-opus-5' and 'claude-opus-4-8' are both opus, and a
      point release is not a routing decision anybody made.

      An alias this does not know returns $null and the dispatch is counted as
      neither agreeing nor disagreeing - a new tier name must not silently
      become a disagreement on every dispatch that uses it.
    #>
    param([AllowNull()][string]$Alias)
    switch -Regex ($Alias) {
        '^(?i)opus$'   { return 'claude-opus' }
        '^(?i)sonnet$' { return 'claude-sonnet' }
        '^(?i)haiku$'  { return 'claude-haiku' }
        '^(?i)fable$'  { return 'claude-fable' }
        default        { return $null }
    }
}

$sw = [Diagnostics.Stopwatch]::StartNew()

# ---------------------------------------------------------------------------
# RESOLVE - and refuse to report rather than report on nothing
# ---------------------------------------------------------------------------
try {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\common.ps1')
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\metrics.ps1')
} catch {
    [Console]::Error.WriteLine('lw-watchtower metrics: the plugin library could not be loaded: ' + $_.Exception.Message)
    exit 3
}

$root = Get-LwgMetricsProjectsRoot
if ([string]::IsNullOrWhiteSpace([string]$root.path)) {
    Write-Output 'LW-WATCHTOWER METRICS'
    Write-Output ''
    Write-Output 'COULD NOT LOOK. Claude Code''s configuration root could not be resolved from'
    Write-Output 'CLAUDE_CONFIG_DIR or from the user profile, so there is no transcript directory'
    Write-Output 'to index. Nothing below this line is a measurement, because nothing was measured.'
    Write-Output ''
    Write-Output 'EXIT: 3'
    exit 3
}
if (-not $root.exists) {
    Write-Output 'LW-WATCHTOWER METRICS'
    Write-Output ''
    Write-Output ('COULD NOT LOOK. The transcript directory ' + $root.label + ' is not there.')
    Write-Output 'That is not the same as an empty one: this command has no corpus to read, so it'
    Write-Output 'reports nothing rather than reporting zero.'
    Write-Output ''
    Write-Output 'EXIT: 3'
    exit 3
}

# ---------------------------------------------------------------------------
# INDEX
# ---------------------------------------------------------------------------
$files = Get-LwgMetricsTranscriptFiles -Root ([string]$root.path)

$sessions   = @{}   # session id -> record
$unreadable = 0
$totLines   = 0
$totReq     = 0
$totDup     = 0
$totSynth   = 0
$totBytes   = [long]0
$firstTs    = $null
$lastTs     = $null
$modelTotals = @{}
$mainTotals  = New-LwgMetricsBucket
$subTotals   = New-LwgMetricsBucket

function Get-SessionRecord {
    param([string]$Id)
    if (-not $sessions.ContainsKey($Id)) {
        $sessions[$Id] = @{
            id            = $Id
            slug          = $null
            slug_resolved = $false
            cwd           = $null
            main          = (New-LwgMetricsBucket)
            sub           = (New-LwgMetricsBucket)
            main_models   = @{}
            dispatches    = @()
            sub_files     = 0
            sub_agent_ids = (New-Object 'System.Collections.Generic.HashSet[string]')
        }
    }
    return $sessions[$Id]
}

function Merge-Bucket {
    param([hashtable]$Into, [hashtable]$From)
    $Into.input          += [long]$From.input
    $Into.cache_read     += [long]$From.cache_read
    $Into.cache_creation += [long]$From.cache_creation
    $Into.output         += [long]$From.output
    $Into.thinking       += [long]$From.thinking
    $Into.requests       += [long]$From.requests
}

function Add-FileToTotals {
    param([hashtable]$Summary)
    foreach ($m in $Summary.models.Keys) {
        if (-not $modelTotals.ContainsKey($m)) { $modelTotals[$m] = New-LwgMetricsBucket }
        Merge-Bucket -Into $modelTotals[$m] -From $Summary.models[$m]
    }
}

foreach ($f in $files.sessions) {
    $s = Read-LwgMetricsTranscript -Path $f.path
    if (-not $s.ok) { $unreadable++; continue }
    $totBytes += $s.bytes
    $totLines += $s.usage_lines
    $totReq   += $s.requests
    $totDup   += $s.duplicates
    $totSynth += $s.synthetic
    if ($s.first_ts -and ($null -eq $firstTs -or $s.first_ts -lt $firstTs)) { $firstTs = $s.first_ts }
    if ($s.last_ts  -and ($null -eq $lastTs  -or $s.last_ts  -gt $lastTs))  { $lastTs  = $s.last_ts }

    $rec = Get-SessionRecord -Id $f.session
    Merge-Bucket -Into $rec.main -From $s.totals
    Merge-Bucket -Into $mainTotals -From $s.totals
    foreach ($m in $s.models.Keys) {
        if (-not $rec.main_models.ContainsKey($m)) { $rec.main_models[$m] = [long]0 }
        $rec.main_models[$m] += [long]$s.models[$m].requests
    }
    Add-FileToTotals -Summary $s
    if ($null -eq $rec.cwd -and @($s.cwds).Count -gt 0) { $rec.cwd = @($s.cwds)[0] }

    $rec.dispatches = @(Get-LwgMetricsDispatch -Path $f.path)
}

foreach ($f in $files.subagents) {
    $s = Read-LwgMetricsTranscript -Path $f.path
    if (-not $s.ok) { $unreadable++; continue }
    $totBytes += $s.bytes
    $totLines += $s.usage_lines
    $totReq   += $s.requests
    $totDup   += $s.duplicates
    $totSynth += $s.synthetic
    if ($s.first_ts -and ($null -eq $firstTs -or $s.first_ts -lt $firstTs)) { $firstTs = $s.first_ts }
    if ($s.last_ts  -and ($null -eq $lastTs  -or $s.last_ts  -gt $lastTs))  { $lastTs  = $s.last_ts }

    $rec = Get-SessionRecord -Id $f.session
    Merge-Bucket -Into $rec.sub -From $s.totals
    Merge-Bucket -Into $subTotals -From $s.totals
    Add-FileToTotals -Summary $s
    $rec.sub_files++
    # The agent id is in the FILE NAME - agent-<hex>.jsonl - and that is the key
    # toolUseResult.agentId joins on. Reading it from the name rather than from
    # the lines means an empty subagent transcript is still attributable.
    $aid = $f.name
    if ($aid -like 'agent-*') { $aid = $aid.Substring(6) }
    if (-not [string]::IsNullOrWhiteSpace($aid)) { [void]$rec.sub_agent_ids.Add($aid) }
    foreach ($a in $s.agent_ids) { [void]$rec.sub_agent_ids.Add($a) }
}

# --- project slugs, resolved from the cwd and NEVER printed as a path -------
foreach ($id in @($sessions.Keys)) {
    $rec = $sessions[$id]
    if ([string]::IsNullOrWhiteSpace([string]$rec.cwd)) { continue }
    try {
        $info = Get-LwgRepoInfo -Path ([string]$rec.cwd)
        if (-not [string]::IsNullOrWhiteSpace([string]$info.slug)) {
            $rec.slug = [string]$info.slug
            $rec.slug_resolved = $true
        }
    } catch { }
}

# --- scope -----------------------------------------------------------------
$scopeSlug  = $null
$scopeLabel = 'every project on this machine'
if (-not $All) {
    try {
        $here = Get-LwgRepoInfo -Path ((Get-Location).Path)
        if (-not [string]::IsNullOrWhiteSpace([string]$here.slug)) { $scopeSlug = [string]$here.slug }
    } catch { }
    if ($scopeSlug) {
        $scopeLabel = $scopeSlug
    } else {
        Note 'the current directory resolves to no repository, so the report is not scoped to one project. Re-run inside a repository, or pass -All to say so on purpose.'
    }
}

$selected = @()
foreach ($id in @($sessions.Keys)) {
    $rec = $sessions[$id]
    if ($scopeSlug -and $rec.slug -ne $scopeSlug) { continue }
    $selected += $rec
}

# ---------------------------------------------------------------------------
# AGGREGATE
# ---------------------------------------------------------------------------
$selMain = New-LwgMetricsBucket
$selSub  = New-LwgMetricsBucket
$dispatchCount   = 0
$attributed      = 0
$tierDisagree    = 0
$tierRequested   = 0
$tierInherited   = 0
$withDispatch    = 0
$withoutDispatch = 0
$subFilesSel     = 0
$statusSeen      = @{}
$cohortOf        = @{}

foreach ($rec in $selected) {
    Merge-Bucket -Into $selMain -From $rec.main
    Merge-Bucket -Into $selSub  -From $rec.sub
    $subFilesSel += $rec.sub_files

    $d = @($rec.dispatches)
    $dispatchCount += $d.Count
    if ($d.Count -gt 0) { $withDispatch++ } else { $withoutDispatch++ }

    foreach ($row in $d) {
        $st = [string]$row.status
        if ([string]::IsNullOrWhiteSpace($st)) { $st = 'no result line' }
        if (-not $statusSeen.ContainsKey($st)) { $statusSeen[$st] = 0 }
        $statusSeen[$st]++

        if ($row.agent_id -and $rec.sub_agent_ids.Contains([string]$row.agent_id)) { $attributed++ }

        if ([string]::IsNullOrWhiteSpace([string]$row.requested_model)) {
            $tierInherited++
        } else {
            $tierRequested++
            $fam = Get-TierFamily -Alias ([string]$row.requested_model)
            if ($fam -and $row.resolved_base -and ([string]$row.resolved_base) -notlike ($fam + '*')) { $tierDisagree++ }
        }
    }

    $cohortOf[$rec.id] = Get-LwgMetricsCohort -Models $rec.main_models
}

# Subagent transcripts in the selected sessions that no dispatch in the same
# session claims. On a real corpus this is large and it is not an error: nested
# children and workflow steps are launched by a subagent, so the Agent tool_use
# that started them is not in the MAIN transcript at all.
$claimed = 0
foreach ($rec in $selected) {
    $ids = @($rec.dispatches | ForEach-Object { [string]$_.agent_id } | Where-Object { $_ })
    foreach ($a in $rec.sub_agent_ids) { if ($ids -contains $a) { $claimed++ } }
}
$unattributedTranscripts = $subFilesSel - $claimed
if ($unattributedTranscripts -lt 0) { $unattributedTranscripts = 0 }

$selMainComposite = Get-LwgMetricsComposite -Bucket $selMain
$selSubComposite  = Get-LwgMetricsComposite -Bucket $selSub
$selComposite     = $selMainComposite + $selSubComposite
$selOutput        = [long]$selMain.output + [long]$selSub.output

# --- cohorts ---------------------------------------------------------------
$cohortRows = @{}
foreach ($rec in $selected) {
    $c = [string]$cohortOf[$rec.id].cohort
    if (-not $cohortRows.ContainsKey($c)) { $cohortRows[$c] = @{ sessions = 0; composite = @(); output = @(); dispatches = @() } }
    $cohortRows[$c].sessions++
    $cohortRows[$c].composite += [long]((Get-LwgMetricsComposite -Bucket $rec.main) + (Get-LwgMetricsComposite -Bucket $rec.sub))
    $cohortRows[$c].output    += [long]([long]$rec.main.output + [long]$rec.sub.output)
    $cohortRows[$c].dispatches += [long]@($rec.dispatches).Count
}

# --- this plugin's own ledger, as a cross-check ----------------------------
# Get-LwgStateDirInfo AND NOT Get-LwgStateDir, AND THAT IS THE WHOLE OF "IT
# WRITES NOTHING". Get-LwgStateDir CREATES the directory it resolves - a
# CreateDirectory call kept deliberately outside its memoisation so that a state
# dir deleted mid-session comes back for the hooks that write to it. This command
# writes nothing and must therefore never call it: on a machine where
# CLAUDE_PLUGIN_DATA is unset the resolution falls through to the unsuffixed
# fallback name, and a READ-ONLY report would have created an empty
# <data>\lw-watchtower on the operator's disk - which is not where the live
# plugin writes, and which bin\lwg-doctor.ps1's state-dir check correctly reports
# as a FAIL whose text says it "can only have been created by this plugin's own
# fallback". This report would have manufactured that fault and then not been the
# thing blamed for it. Get-LwgStateDirInfo resolves and creates nothing.
$health = @{ present = $false }
try { $health = Get-LwgMetricsHealthSummary -StateDir ([string](Get-LwgStateDirInfo).path) } catch { }

$sw.Stop()

# ---------------------------------------------------------------------------
# THE COLUMNS THIS SLICE HAS NO SOURCE FOR
#
# Stated once, in one table, so that adding a source later is one edit and so
# that nothing can quietly become a zero. Every one of these prints, on every
# run, whether or not there is a corpus.
# ---------------------------------------------------------------------------
$undetermined = @(
    @{ section = 'ORCHESTRATION'; label = 'tier-up reruns (marked / inferred)'; why = 'R4 - no agent emits the LW-TIERUP-OF marker yet, and an inferred tier-up is not the same measurement' },
    @{ section = 'ORCHESTRATION'; label = 'failed dispatches';                  why = 'R4 - the join to health.jsonl PostToolUseFailure rows is not built in this slice' },
    @{ section = 'ORCHESTRATION'; label = 'per-dispatch token cost';            why = 'R1 - #166 owns the dispatch row and the cost field attaches to it there; this slice adds no hook' },
    @{ section = 'QUALITY';       label = 'LCAP rounds to clean';               why = 'R5 - no reviewer emits the LCAP-ROUND trailer yet, so no round has ever been recorded' },
    @{ section = 'QUALITY';       label = 'findings by severity';               why = 'R5 - same trailer' },
    @{ section = 'QUALITY';       label = 'gate-2 leak rate';                   why = 'R5 - needs a clean Gate 1 round and a Gate 2 round on the same target' },
    @{ section = 'QUALITY';       label = 'post-merge defects';                 why = 'R5.6 - needs gh timeline calls, and this slice makes no network call at all' },
    @{ section = 'BUCKET';        label = 'usage meter';                        why = 'R3 - the 5h and 7d percentages are overwritten on every status-line render and no history exists' },
    @{ section = 'BUCKET';        label = 'tokens per percent';                 why = 'R3 - calibration needs consecutive meter snapshots, and there are none' },
    @{ section = 'BUCKET';        label = 'landings';                           why = 'R6 - landing detection is not built in this slice' },
    @{ section = 'BUCKET';        label = 'tokens per landing';                 why = 'R6 - every figure here is therefore PER SESSION, and is labelled so' },
    @{ section = 'VERDICT';       label = 'VERDICT (STAY / REVERT / EXTEND / INSUFFICIENT)'; why = 'R8 - the decision rule needs the meter history and the LCAP rounds above' }
)

function Write-Undetermined {
    param([string]$Section)
    foreach ($u in $undetermined) {
        if ($u.section -ne $Section) { continue }
        Say ('  {0,-46} NOT DETERMINED  ({1})' -f $u.label, $u.why)
    }
}

# ---------------------------------------------------------------------------
# JSON
# ---------------------------------------------------------------------------
if ($Json) {
    $obj = [ordered]@{
        slice   = 'R2 - transcript index and scoreboard'
        scope   = $scopeLabel
        index   = [ordered]@{
            projects_root_label  = $root.label
            projects_root_source = $root.source
            session_transcripts  = @($files.sessions).Count
            subagent_transcripts = @($files.subagents).Count
            unclassified         = @($files.other).Count
            unreadable           = $unreadable
            bytes                = $totBytes
            usage_lines          = $totLines
            requests             = $totReq
            duplicates_discarded = $totDup
            synthetic_excluded   = $totSynth
            earliest             = $firstTs
            latest               = $lastTs
            scan_ms              = [int]$sw.Elapsed.TotalMilliseconds
        }
        delegation = [ordered]@{
            sessions                  = @($selected).Count
            sessions_with_dispatch    = $withDispatch
            sessions_without_dispatch = $withoutDispatch
            subagent_transcripts      = $subFilesSel
        }
        work_split = [ordered]@{
            main = [ordered]@{
                input = $selMain.input; cache_read = $selMain.cache_read
                cache_creation = $selMain.cache_creation; output = $selMain.output
                thinking = $selMain.thinking; requests = $selMain.requests
                composite = $selMainComposite
            }
            subagent = [ordered]@{
                input = $selSub.input; cache_read = $selSub.cache_read
                cache_creation = $selSub.cache_creation; output = $selSub.output
                thinking = $selSub.thinking; requests = $selSub.requests
                composite = $selSubComposite
            }
            subagent_composite_share = (Format-LwgMetricsShare -Part $selSubComposite -Whole $selComposite)
            subagent_output_share    = (Format-LwgMetricsShare -Part ([long]$selSub.output) -Whole $selOutput)
        }
        orchestration = [ordered]@{
            dispatches               = $dispatchCount
            attributed               = $attributed
            unattributed_transcripts = $unattributedTranscripts
            tier_requested           = $tierRequested
            tier_inherited           = $tierInherited
            tier_disagreements       = $tierDisagree
            statuses                 = $statusSeen
        }
        totals = [ordered]@{
            input = ([long]$selMain.input + [long]$selSub.input)
            cache_read = ([long]$selMain.cache_read + [long]$selSub.cache_read)
            cache_creation = ([long]$selMain.cache_creation + [long]$selSub.cache_creation)
            output = $selOutput
            thinking = ([long]$selMain.thinking + [long]$selSub.thinking)
            composite = $selComposite
        }
        health_cross_check = $health
        not_determined     = @($undetermined | ForEach-Object { [ordered]@{ section = $_.section; label = $_.label; why = $_.why } })
        notes              = @($script:Notes)
    }
    Write-Output ($obj | ConvertTo-Json -Depth 8 -Compress)
    exit 0
}

# ---------------------------------------------------------------------------
# THE SCOREBOARD
# ---------------------------------------------------------------------------
$utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mmZ', [Globalization.CultureInfo]::InvariantCulture)

Say ('LW-WATCHTOWER METRICS   scope: {0}   {1}' -f $scopeLabel, $utc)
Say 'slice 1 of #165 - R2 only: the transcript index and the scoreboard, reading files that'
Say 'already exist. No hook, no ledger, no written file, no decision rule, and no dollars.'
Say '[V] this process measured it   [R] read from a record   NOT DETERMINED is never a zero'
Say ''

Say 'INDEX'
Say ('  {0,-34} {1}  (source: {2}) [V]' -f 'projects root', $root.label, $root.source)
Say ('  {0,-34} {1}  ({2} session, {3} subagent, {4} unclassified) [V]' -f 'transcript files',
    (Format-LwgMetricsCount -Value ([long](@($files.sessions).Count + @($files.subagents).Count + @($files.other).Count))),
    (Format-LwgMetricsCount -Value ([long]@($files.sessions).Count)),
    (Format-LwgMetricsCount -Value ([long]@($files.subagents).Count)),
    (Format-LwgMetricsCount -Value ([long]@($files.other).Count)))
Say ('  {0,-34} {1} [V]' -f 'bytes read', (Format-LwgMetricsTokens -Value $totBytes))
Say ('  {0,-34} {1} ms [V]' -f 'scan time', [int]$sw.Elapsed.TotalMilliseconds)
Say ('  {0,-34} {1} [V]' -f 'assistant lines carrying usage', (Format-LwgMetricsCount -Value ([long]$totLines)))
Say ('  {0,-34} {1} [V]' -f 'distinct requests (message.id)', (Format-LwgMetricsCount -Value ([long]$totReq)))
Say ('  {0,-34} {1}  ({2} of the lines) [V]' -f 'duplicate lines discarded',
    (Format-LwgMetricsCount -Value ([long]$totDup)), (Format-LwgMetricsShare -Part ([long]$totDup) -Whole ([long]$totLines)))
Say ('  {0,-34} {1} [V]' -f 'synthetic lines excluded', (Format-LwgMetricsCount -Value ([long]$totSynth)))
Say ('  {0,-34} {1} [V]' -f 'files that would not read', (Format-LwgMetricsCount -Value ([long]$unreadable)))
Say ('  {0,-34} {1} .. {2} [R]' -f 'earliest / latest request',
    $(if ($firstTs) { $firstTs.Substring(0, [math]::Min(10, $firstTs.Length)) } else { 'NOT DETERMINED' }),
    $(if ($lastTs)  { $lastTs.Substring(0, [math]::Min(10, $lastTs.Length)) }  else { 'NOT DETERMINED' }))
Say ''
Say '  Summed ONCE per message.id. One API response is written as several assistant lines,'
Say '  each repeating the identical usage block; a per-line sum overstates by roughly 2x.'
Say ''

Say 'DELEGATION - is work leaving the main thread at all'
Say ('  {0,-34} {1} [V]' -f 'sessions in scope', (Format-LwgMetricsCount -Value ([long]@($selected).Count)))
Say ('  {0,-34} {1} [V]' -f '  of them, delegating', (Format-LwgMetricsCount -Value ([long]$withDispatch)))
Say ('  {0,-34} {1} [V]  the main thread worked alone' -f '  of them, delegating nothing', (Format-LwgMetricsCount -Value ([long]$withoutDispatch)))
Say ('  {0,-34} {1} [R]' -f 'dispatches (Agent tool_use)', (Format-LwgMetricsCount -Value ([long]$dispatchCount)))
Say ('  {0,-34} {1} [V]' -f 'subagent transcripts on disk', (Format-LwgMetricsCount -Value ([long]$subFilesSel)))
Say ('  {0,-34} {1} [V]' -f 'dispatches joined to a transcript', (Format-LwgMetricsCount -Value ([long]$attributed)))
Say ('  {0,-34} {1} [V]  nested children and workflow steps' -f 'transcripts no dispatch claims', (Format-LwgMetricsCount -Value ([long]$unattributedTranscripts)))
if ($health.present) {
    Say ('  {0,-34} {1} SubagentStop row(s) over {2} session(s) [R]' -f 'health.jsonl says',
        (Format-LwgMetricsCount -Value ([long]$health.subagent_stop)), (Format-LwgMetricsCount -Value ([long]$health.sessions)))
} else {
    Say ('  {0,-34} NOT DETERMINED  (health.jsonl is not in the state directory - this plugin has not run here)' -f 'health.jsonl cross-check')
    Note 'health.jsonl is absent, so the hook-era dispatch count could not be compared with the transcripts. That is not zero dispatches; it is no second opinion.'
}
Say ''

Say 'WORK SPLIT - main thread against subagents, per session in scope'
Say ('  {0,-22} {1,16} {2,16} {3,18}' -f '', 'main thread', 'subagents', 'subagent share')
Say ('  {0,-22} {1,16} {2,16} {3,18}' -f 'composite',
    (Format-LwgMetricsTokens -Value $selMainComposite), (Format-LwgMetricsTokens -Value $selSubComposite),
    (Format-LwgMetricsShare -Part $selSubComposite -Whole $selComposite))
Say ('  {0,-22} {1,16} {2,16} {3,18}' -f 'output',
    (Format-LwgMetricsTokens -Value ([long]$selMain.output)), (Format-LwgMetricsTokens -Value ([long]$selSub.output)),
    (Format-LwgMetricsShare -Part ([long]$selSub.output) -Whole $selOutput))
Say ('  {0,-22} {1,16} {2,16} {3,18}' -f 'cache read',
    (Format-LwgMetricsTokens -Value ([long]$selMain.cache_read)), (Format-LwgMetricsTokens -Value ([long]$selSub.cache_read)),
    (Format-LwgMetricsShare -Part ([long]$selSub.cache_read) -Whole ([long]$selMain.cache_read + [long]$selSub.cache_read)))
Say ('  {0,-22} {1,16} {2,16} {3,18}' -f 'cache creation',
    (Format-LwgMetricsTokens -Value ([long]$selMain.cache_creation)), (Format-LwgMetricsTokens -Value ([long]$selSub.cache_creation)),
    (Format-LwgMetricsShare -Part ([long]$selSub.cache_creation) -Whole ([long]$selMain.cache_creation + [long]$selSub.cache_creation)))
Say ('  {0,-22} {1,16} {2,16} {3,18}' -f 'fresh input',
    (Format-LwgMetricsTokens -Value ([long]$selMain.input)), (Format-LwgMetricsTokens -Value ([long]$selSub.input)),
    (Format-LwgMetricsShare -Part ([long]$selSub.input) -Whole ([long]$selMain.input + [long]$selSub.input)))
Say ('  {0,-22} {1,16} {2,16} {3,18}' -f 'requests',
    (Format-LwgMetricsCount -Value ([long]$selMain.requests)), (Format-LwgMetricsCount -Value ([long]$selSub.requests)),
    (Format-LwgMetricsShare -Part ([long]$selSub.requests) -Whole ([long]$selMain.requests + [long]$selSub.requests)))
Say ''
Say '  BOTH SHARES ARE SHOWN AND NEITHER IS THE ANSWER ALONE. The composite is dominated by'
Say '  cache reads by two or three orders of magnitude, so the two diverge widely - a session'
Say '  can be 20 % subagent by composite and 60 % by output. #165 R4 requires both.'
Say ''

Say 'BY MODEL - deduplicated requests, the four categories never merged'
Say ('  {0,-30} {1,10} {2,12} {3,14} {4,14} {5,12} {6,12}' -f 'model', 'requests', 'input', 'cache create', 'cache read', 'output', 'composite')
$modelKeys = @($modelTotals.Keys | Sort-Object { -[long]$modelTotals[$_].requests })
if ($modelKeys.Count -eq 0) {
    Say '  (no assistant line carrying a usage block was found in the corpus)'
} else {
    foreach ($m in $modelKeys) {
        $b = $modelTotals[$m]
        Say ('  {0,-30} {1,10} {2,12} {3,14} {4,14} {5,12} {6,12}' -f $m,
            (Format-LwgMetricsCount -Value ([long]$b.requests)),
            (Format-LwgMetricsTokens -Value ([long]$b.input)),
            (Format-LwgMetricsTokens -Value ([long]$b.cache_creation)),
            (Format-LwgMetricsTokens -Value ([long]$b.cache_read)),
            (Format-LwgMetricsTokens -Value ([long]$b.output)),
            (Format-LwgMetricsTokens -Value (Get-LwgMetricsComposite -Bucket $b)))
    }
}
Say ''
Say '  This table is the whole corpus, not the scope, so a model that only ever runs as a'
Say '  subagent is visible. It is a count of requests, not of dispatches.'
Say ''

Say 'COHORT - assigned per session from the dominant main-thread model (#165 R6), never from a date'
Say ('  {0,-30} {1,9} {2,20} {3,20} {4,12}' -f 'cohort', 'sessions', 'composite/session', 'output/session', 'dispatches')
if ($cohortRows.Keys.Count -eq 0) {
    Say '  (no session in scope)'
} else {
    foreach ($c in @($cohortRows.Keys | Sort-Object)) {
        $r = $cohortRows[$c]
        Say ('  {0,-30} {1,9} {2,20} {3,20} {4,12}' -f $c,
            (Format-LwgMetricsCount -Value ([long]$r.sessions)),
            (Format-Median -Value (Get-Median -Values ([long[]]$r.composite))),
            (Format-Median -Value (Get-Median -Values ([long[]]$r.output))),
            (Format-Median -Value (Get-Median -Values ([long[]]$r.dispatches))))
    }
}
Say ''
Say '  MEDIANS ARE PER SESSION, NOT PER LANDING, and that is a real difference rather than a'
Say '  rename. #165 compares cohorts per landing; landing detection is R6 and is not in this'
Say '  slice, so no ratio here is the R_total or R_out the decision rule reads.'
Say '  `mixed` is a session no model held 60 % of. `unknown` is a session with no'
Say '  main-thread assistant line at all. They are different and are not merged.'
Say ''

Say 'ORCHESTRATION'
Say ('  {0,-46} {1} [R]' -f 'dispatches (Agent tool_use)', (Format-LwgMetricsCount -Value ([long]$dispatchCount)))
Say ('  {0,-46} {1} [V]' -f 'joined to a subagent transcript', (Format-LwgMetricsCount -Value ([long]$attributed)))
Say ('  {0,-46} {1} [V]' -f 'transcripts no dispatch claims', (Format-LwgMetricsCount -Value ([long]$unattributedTranscripts)))
Say ('  {0,-46} {1} [R]' -f 'dispatches naming a tier', (Format-LwgMetricsCount -Value ([long]$tierRequested)))
Say ('  {0,-46} {1} [R]  they inherit the caller''s tier' -f 'dispatches naming none', (Format-LwgMetricsCount -Value ([long]$tierInherited)))
Say ('  {0,-46} {1} [V]  asked for one family, ran another' -f 'requested / resolved disagreements', (Format-LwgMetricsCount -Value ([long]$tierDisagree)))
if ($statusSeen.Keys.Count -gt 0) {
    foreach ($st in @($statusSeen.Keys | Sort-Object)) {
        Say ('  {0,-46} {1} [R]' -f ('dispatch results with status ' + $st), (Format-LwgMetricsCount -Value ([long]$statusSeen[$st])))
    }
}
Write-Undetermined -Section 'ORCHESTRATION'
Say ''

Say 'QUALITY'
Write-Undetermined -Section 'QUALITY'
Say '  Nothing on this machine has ever recorded an LCAP round. #165 R5 adds one line to the'
Say '  reviewer''s final message; until an agent emits it, every figure here stays unknown and'
Say '  is reported as unknown rather than as a clean sheet.'
Say ''

Say 'BUCKET'
Write-Undetermined -Section 'BUCKET'
Say '  The 5-hour and 7-day meters are the only thing the operator''s subscription actually'
Say '  charges against, and no file on this machine keeps a history of them. Until R3 writes'
Say '  one, tokens cannot be converted into a share of either bucket at all.'
Say ''

Say 'VERDICT'
Write-Undetermined -Section 'VERDICT'
Say '  The decision rule is #165 R8. It reads a token ratio, a rounds-to-clean median, a'
Say '  gate-2 leak rate and a post-merge defect rate, three of which are NOT DETERMINED above.'
Say '  Printing a verdict from one of four inputs would be the exact failure this whole issue'
Say '  was opened about: a keep-or-revert decision made on impression, wearing a number.'
Say ''

Say 'COULD NOT DETERMINE'
foreach ($u in $undetermined) { Say ('  - {0}: {1}' -f $u.label, $u.why) }
if ($unreadable -gt 0) {
    Say ('  - {0} transcript file(s) could not be read and contribute nothing to any figure above' -f $unreadable)
}
if (-not ($statusSeen.ContainsKey('completed'))) {
    Say '  - transcript sums were not cross-checked against a tool result: only a `completed` Agent'
    Say '    result carries usage and totalTokens, and no dispatch in this corpus has that status'
}
$unresolvedSlugs = @($selected | Where-Object { -not $_.slug_resolved }).Count
if ($unresolvedSlugs -gt 0) {
    Say ('  - {0} session(s) could not be attributed to a repository: the working directory they ran' -f $unresolvedSlugs)
    Say '    in no longer resolves to a git remote, so they are in the totals and in no project'
}
Say '  - usage this machine cannot see: another device, a browser session, and the advisor tool.'
Say '    Assistant lines carry an advisorModel field and no advisor usage at all, so every token'
Say '    figure above is a FLOOR rather than a total'
Say '  - transcript retention is finite and the window slides daily, so a cohort older than the'
Say '    earliest date in the INDEX block is not missing from this report - it is gone from the disk'
foreach ($n in $script:Notes) { Say ('  - {0}' -f $n) }
Say ''

foreach ($l in $script:Lines) { Write-Output $l }
Write-Output 'EXIT: 0'
exit 0
