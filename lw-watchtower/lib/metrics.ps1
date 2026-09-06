#requires -version 5
<#
  LW-WATCHTOWER metrics - the pure functions the indexer is built from.

      . (Join-Path $PSScriptRoot '..\lib\metrics.ps1')

  DOT-SOURCED BY bin\lwg-metrics.ps1 AND BY NOTHING ELSE. No hook loads this
  file, no hook is registered for it, this slice adds no `modules.metrics` flag
  and no registry entry, and neither hooks\hooks.json nor $LwgModuleRegistry is
  touched. (The counts those two hold are stated once, in docs\modules.md, and
  are deliberately not restated here - a doc block that repeats a number it does
  not own is a number that goes stale where nothing checks it.) That is not an
  oversight: it is the shape the owner ruled on 6 September 2026. The
  first slice of #165 is R2 alone, the transcript indexer and the scoreboard, as
  a command, reading only files that already exist. The per-dispatch record is
  #166's row and the cost field attaches to it there, not here - a second
  per-dispatch ledger in one state directory is a defect by #165's own finding 6.

  WHY THE LOGIC IS IN lib\ AND NOT IN bin\lwg-metrics.ps1
  Because it has to be testable without a live session. Rule 18 of this lane
  forbids starting one, and #165's A1 - "usage is summed once per message.id" -
  is the single measurement that decides whether any number this module ever
  prints is true. tests\metrics_behaviour.ps1 dot-sources this file in a child
  process and drives these functions against hand-built fixtures; the command
  above stays a reader, a joiner and a renderer.

  ---------------------------------------------------------------------------
  WHAT IT READS, AND THE TWO REASONS THAT LIST IS SHORT
  ---------------------------------------------------------------------------
  Claude Code's own transcripts, under <configuration root>\projects, and this
  plugin's own health.jsonl in the state directory. Nothing else. No hook is
  added, no network call is made, and nothing is written anywhere.

  1. Everything R2 reads already exists on disk, so the answer covers a period
     that has already happened rather than starting from the day the code lands.
  2. Transcript retention is finite and the window slides daily, so a day not
     indexed is a day deleted. On the machine this was written on the oldest
     transcript was five days old.

  ---------------------------------------------------------------------------
  THE ONE MEASUREMENT EVERYTHING ELSE RESTS ON
  ---------------------------------------------------------------------------
  ONE API RESPONSE IS WRITTEN AS SEVERAL `assistant` LINES - one per content
  block - and every one of them repeats the IDENTICAL usage object under the
  same message.id and requestId. Summing per line overstates by roughly 2x.

  Measured over the whole local corpus on 2026-09-06, in Windows PowerShell 5.1:
  268 transcript files, 36,535 assistant lines carrying a usage block, 19,480
  distinct message.id. Not one id was ever seen carrying two different usage
  blocks. So: sum once per message.id, per file.

  The second measurement that shapes this file is that the totals do not fit in
  32 bits. That same corpus carries 4,479,419,249 cache-read tokens, against an
  [int]::MaxValue of 2,147,483,647. Every accumulator below is [long] from its
  first assignment, and the fixture in tests\metrics_behaviour.ps1 section A
  drives two 2,000,000,000 reads through it precisely so that a future [int]
  cannot creep back in unnoticed.

  ---------------------------------------------------------------------------
  THE FOUR CATEGORIES ARE KEPT APART, ALWAYS
  ---------------------------------------------------------------------------
  input_tokens, cache_read_input_tokens, cache_creation_input_tokens and
  output_tokens are reported separately, and the composite - their sum - is
  reported BESIDE them and never instead of them. On a real session the cache
  read dwarfs everything else by two or three orders of magnitude, so a single
  headline number is a cache-read number wearing a different label.

  output_tokens_details.thinking_tokens is reported beside output_tokens and is
  NOT added to the composite: it is a SUBSET of output_tokens, and adding it
  double-counts every reasoning token.

  ---------------------------------------------------------------------------
  MASKING IS A PROPERTY OF WHAT THIS FILE RETURNS, NOT OF WHAT THE CALLER PRINTS
  ---------------------------------------------------------------------------
  A transcript directory name is the working directory with its separators
  replaced, so it carries the operator's account name. This file therefore
  returns counts, token sums, model ids, session ids and repository slugs - and
  it never returns a transcript path or a directory name for rendering. The one
  place a working directory is read at all is `cwds`, which exists so the caller
  can hand it to Get-LwgRepoInfo and get a slug back; the path itself is not
  meant to be printed and the command above does not print it.
#>

# The floor a session's dominant main-thread model has to clear before the
# session is assigned to that model's cohort. #165 R6: "Sessions whose main
# thread is mixed with no model above 60 % are `mixed` and excluded."
$script:LwgMetricsCohortFloor = 0.6

# Lines that cannot be usage records are rejected on two substring tests before
# anything is parsed. ConvertFrom-Json dominates the cost of a scan - measured
# on this corpus, the prefilter is the difference between a command that answers
# in seconds and one that does not get run. The tail reader this repository
# already ships uses the same two marks for the same reason.
$script:LwgMetricsUsageMarks = @('*"usage"*', '*"assistant"*')

function Get-LwgMetricsModelBase {
    <#
      A model id with any trailing bracket tag removed, for COMPARISON only.

        'claude-opus-5[1m]'  ->  'claude-opus-5'
        'claude-opus-5'      ->  'claude-opus-5'
        $null / ''           ->  ''

      WHY THIS IS A FUNCTION AND NOT AN INLINE COMPARISON. Two reasons, both
      measured:

      1. toolUseResult.resolvedModel carries the entitlement tag -
         'claude-opus-5[1m]' - while the subagent's own message.model says
         'claude-opus-5'. Comparing the two unstripped reports EVERY dispatch as
         a requested/resolved disagreement, which would turn #165 R4's tier-up
         measurement into noise.
      2. '[' is a wildcard character in PowerShell's -like, so a caller reaching
         for -like on these strings gets a pattern rather than a literal. The
         comparison belongs behind a name where that cannot be got wrong.

      The tag is NEVER stripped from what is reported. The scoreboard prints the
      resolved model verbatim; only the comparison uses the base.
    #>
    param([AllowEmptyString()][AllowNull()][string]$Model)

    if ([string]::IsNullOrWhiteSpace($Model)) { return '' }
    $m = $Model.Trim()
    $i = $m.IndexOf('[')
    if ($i -gt 0) { return $m.Substring(0, $i) }
    return $m
}

function New-LwgMetricsBucket {
    <#
      A fresh token accumulator. EVERY FIELD IS [long] FROM ITS FIRST
      ASSIGNMENT - see the header: this machine's own corpus is already past
      [int]::MaxValue on cache_read, and an [int] accumulator does not round
      there, it wraps or throws.
    #>
    return @{
        input          = [long]0
        cache_read     = [long]0
        cache_creation = [long]0
        output         = [long]0
        thinking       = [long]0
        requests       = [long]0
    }
}

function Add-LwgMetricsUsage {
    <#
      Fold one request's usage object into a bucket. Every value is cast to
      [long] before it is added, because ConvertFrom-Json hands back Int32 for
      anything that fits in one and Int32 + Int32 overflows at 2.1 billion.

      An absent field contributes nothing rather than throwing: [long]$null is 0
      in PowerShell, and a usage object that omits a category is a normal thing
      (cache_read_input_tokens is absent on a cold request).
    #>
    param([hashtable]$Bucket, $Usage)

    if ($null -eq $Bucket -or $null -eq $Usage) { return }
    $Bucket.input          += [long]$Usage.input_tokens
    $Bucket.cache_read     += [long]$Usage.cache_read_input_tokens
    $Bucket.cache_creation += [long]$Usage.cache_creation_input_tokens
    $Bucket.output         += [long]$Usage.output_tokens
    $d = $Usage.output_tokens_details
    if ($null -ne $d) { $Bucket.thinking += [long]$d.thinking_tokens }
    $Bucket.requests += 1
}

function Get-LwgMetricsComposite {
    <#
      input + cache_read + cache_creation + output, as [long].

      thinking is deliberately absent: it is a subset of output. See the header.
    #>
    param([hashtable]$Bucket)
    if ($null -eq $Bucket) { return [long]0 }
    return ([long]$Bucket.input + [long]$Bucket.cache_read + [long]$Bucket.cache_creation + [long]$Bucket.output)
}

function Read-LwgMetricsTranscript {
    <#
      Index ONE transcript file. Returns a HASHTABLE - PowerShell enumerates a
      returned collection but not a returned hashtable, so this survives the
      function boundary intact:

        @{
          ok             the file was opened and read
          error          why not, when ok is $false
          bytes          [long] file length
          usage_lines    assistant lines carrying a usage block, synthetic excluded
          requests       DISTINCT message.id among those lines
          duplicates     usage_lines - requests, i.e. what a naive sum would
                         have counted twice
          synthetic      lines whose message.model is <synthetic>, excluded
          unparsable     lines that passed the prefilter and did not parse
          first_ts       earliest timestamp of a counted request, as written
          last_ts        latest
          sidechain      $true when every counted line carried isSidechain
          agent_ids      distinct agentId values seen
          session_ids    distinct sessionId values seen
          cwds           distinct cwd values seen - for Get-LwgRepoInfo, NOT for
                         printing; see the header on masking
          models         @{ '<model id>' = <bucket> }
          totals         one bucket over every model, plus `composite`
        }

      DEDUPE IS PER FILE, NOT GLOBAL. A message.id is unique within a
      conversation; keying the whole machine on it would let two sessions that
      happened to collide silently drop a request. The set is discarded when the
      file is done, which also keeps the memory cost proportional to one file
      rather than to the corpus.

      READS WITH [IO.File]::ReadLines, WHICH STREAMS. Get-Content on a 240 MB
      corpus in Windows PowerShell 5.1 is minutes; this is seconds. The path is
      made absolute first - every .NET call resolves a relative path against the
      PROCESS working directory, which is wherever the operator ran the command
      from and not this tree (Rule 16).
    #>
    param([Parameter(Mandatory = $true)][string]$Path)

    $r = @{
        ok = $false; error = $null; bytes = [long]0
        usage_lines = 0; requests = 0; duplicates = 0; synthetic = 0; unparsable = 0
        first_ts = $null; last_ts = $null; sidechain = $false
        agent_ids = @(); session_ids = @(); cwds = @()
        models = @{}; totals = (New-LwgMetricsBucket)
    }
    $r.totals['composite'] = [long]0

    $full = $null
    try { $full = [IO.Path]::GetFullPath($Path) } catch { $r.error = $_.Exception.Message; return $r }
    if (-not [IO.File]::Exists($full)) { $r.error = 'not a file'; return $r }

    $seen     = New-Object 'System.Collections.Generic.HashSet[string]'
    $agents   = New-Object 'System.Collections.Generic.HashSet[string]'
    $sessions = New-Object 'System.Collections.Generic.HashSet[string]'
    $cwds     = New-Object 'System.Collections.Generic.HashSet[string]'
    $mainSeen = $false
    $sideSeen = $false

    try {
        $r.bytes = [long](New-Object IO.FileInfo $full).Length
        foreach ($line in [IO.File]::ReadLines($full)) {
            $keep = $true
            foreach ($mark in $script:LwgMetricsUsageMarks) {
                if ($line -notlike $mark) { $keep = $false; break }
            }
            if (-not $keep) { continue }

            $rec = $null
            try { $rec = $line | ConvertFrom-Json -ErrorAction Stop } catch { $r.unparsable++; continue }
            if ($null -eq $rec -or $rec.type -ne 'assistant') { continue }
            $msg = $rec.message
            if ($null -eq $msg) { continue }
            $u = $msg.usage
            if ($null -eq $u) { continue }

            $model = [string]$msg.model
            # <synthetic> IS NOT A MODEL AND ITS USAGE IS NOT SPEND. 124 of them
            # are in this machine's own corpus. Counted so the report can say it
            # excluded them, never folded into a per-model row.
            if ($model -eq '<synthetic>') { $r.synthetic++; continue }

            $r.usage_lines++

            $id = [string]$msg.id
            if ([string]::IsNullOrWhiteSpace($id)) {
                # No message.id means no dedupe key. Counting it once is the only
                # honest option - dropping it would understate, and there is no
                # id for it to be a duplicate OF.
                $id = 'nomsgid:' + $r.usage_lines
            }
            if (-not $seen.Add($id)) { $r.duplicates++; continue }

            if ([string]::IsNullOrWhiteSpace($model)) { $model = 'unknown' }
            if (-not $r.models.ContainsKey($model)) { $r.models[$model] = New-LwgMetricsBucket }
            Add-LwgMetricsUsage -Bucket $r.models[$model] -Usage $u
            Add-LwgMetricsUsage -Bucket $r.totals        -Usage $u

            if ($rec.isSidechain -eq $true) { $sideSeen = $true } else { $mainSeen = $true }

            $ts = [string]$rec.timestamp
            if (-not [string]::IsNullOrWhiteSpace($ts)) {
                if ($null -eq $r.first_ts -or $ts -lt $r.first_ts) { $r.first_ts = $ts }
                if ($null -eq $r.last_ts  -or $ts -gt $r.last_ts)  { $r.last_ts  = $ts }
            }
            $a = [string]$rec.agentId
            if (-not [string]::IsNullOrWhiteSpace($a)) { [void]$agents.Add($a) }
            $s = [string]$rec.sessionId
            if (-not [string]::IsNullOrWhiteSpace($s)) { [void]$sessions.Add($s) }
            $c = [string]$rec.cwd
            if (-not [string]::IsNullOrWhiteSpace($c)) { [void]$cwds.Add($c) }
        }
        $r.ok = $true
    } catch {
        $r.error = $_.Exception.Message
        return $r
    }

    $r.requests    = $r.usage_lines - $r.duplicates
    $r.agent_ids   = @($agents)
    $r.session_ids = @($sessions)
    $r.cwds        = @($cwds)
    # A file is a sidechain file when every counted line said so. A main-thread
    # transcript that happens to be empty is neither, and is reported as neither.
    $r.sidechain   = ($sideSeen -and -not $mainSeen)
    $r.totals['composite'] = Get-LwgMetricsComposite -Bucket $r.totals
    return $r
}

function Get-LwgMetricsDispatch {
    <#
      Every `Agent` dispatch in ONE main-thread transcript, joined to its result.
      Returns an ARRAY of hashtables - always an array, even for none or one.

        @{
          tool_use_id      the assistant tool_use block's id
          subagent_type    input.subagent_type
          requested_model  input.model - 'opus' | 'sonnet' | 'haiku' | 'fable',
                           or $null when the dispatch inherits the caller's tier
          status           toolUseResult.status
          agent_id         toolUseResult.agentId, or .agent_id for a teammate
          resolved_model   toolUseResult.resolvedModel, VERBATIM, tag and all
          resolved_base    the same with the bracket tag stripped, for comparison
          ts               the tool_use line's timestamp
        }

      THE JOIN KEY, verified on real transcripts on 2026-09-06: the result sits
      on a `type:"user"` line whose message.content[] carries a `tool_result`
      block whose `tool_use_id` equals the assistant `tool_use` block's `id`.
      toolUseResult on that same line carries agentId, resolvedModel and status.

      WHAT THE LOCAL CORPUS DOES AND DOES NOT CONTAIN, so the caller can report
      the difference rather than assume it: 151 of the 153 Agent dispatches on
      this machine produced a result at all, and every one of those 151 carried
      status "async_launched". Neither "completed" - the only status that
      carries a `usage` object and a `totalTokens` to cross-check the transcript
      sum against - nor "teammate_spawned" appeared once. The branches for them
      are here because #165 documents them; nothing on this disk exercises them,
      and the scoreboard says so rather than implying a cross-check it never ran.

      input.description and input.prompt are read and DISCARDED. They are
      operator-written free text and can carry an absolute path; nothing
      downstream needs them, so they never leave this function.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)

    $rows = New-Object System.Collections.ArrayList
    $full = $null
    try { $full = [IO.Path]::GetFullPath($Path) } catch { return @() }
    if (-not [IO.File]::Exists($full)) { return @() }

    $uses    = New-Object System.Collections.ArrayList
    $results = @{}

    try {
        foreach ($line in [IO.File]::ReadLines($full)) {
            $isUse = ($line -like '*"Agent"*')
            $isRes = ($line -like '*"toolUseResult"*')
            if (-not $isUse -and -not $isRes) { continue }

            $rec = $null
            try { $rec = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            if ($null -eq $rec) { continue }

            $content = $null
            if ($null -ne $rec.message) { $content = $rec.message.content }

            if ($rec.type -eq 'assistant' -and $content -is [System.Collections.IEnumerable] -and $content -isnot [string]) {
                foreach ($b in $content) {
                    if ($null -eq $b) { continue }
                    if ($b.type -ne 'tool_use' -or $b.name -ne 'Agent') { continue }
                    $in = $b.input
                    [void]$uses.Add(@{
                        tool_use_id     = [string]$b.id
                        subagent_type   = $(if ($null -ne $in -and -not [string]::IsNullOrWhiteSpace([string]$in.subagent_type)) { [string]$in.subagent_type } else { $null })
                        requested_model = $(if ($null -ne $in -and -not [string]::IsNullOrWhiteSpace([string]$in.model)) { [string]$in.model } else { $null })
                        ts              = [string]$rec.timestamp
                    })
                }
            }

            $res = $rec.toolUseResult
            if ($null -eq $res) { continue }
            # The id the result belongs to lives on the tool_result block, not on
            # toolUseResult itself.
            if ($content -is [System.Collections.IEnumerable] -and $content -isnot [string]) {
                foreach ($b in $content) {
                    if ($null -eq $b -or $b.type -ne 'tool_result') { continue }
                    $tid = [string]$b.tool_use_id
                    if ([string]::IsNullOrWhiteSpace($tid)) { continue }
                    $results[$tid] = $res
                }
            }
        }
    } catch { return @() }

    foreach ($u in $uses) {
        $row = @{
            tool_use_id     = $u.tool_use_id
            subagent_type   = $u.subagent_type
            requested_model = $u.requested_model
            ts              = $u.ts
            status          = $null
            agent_id        = $null
            resolved_model  = $null
            resolved_base   = ''
        }
        $res = $null
        if ($u.tool_use_id -and $results.ContainsKey($u.tool_use_id)) { $res = $results[$u.tool_use_id] }
        if ($null -ne $res) {
            $row.status = $(if ([string]::IsNullOrWhiteSpace([string]$res.status)) { $null } else { [string]$res.status })
            $aid = [string]$res.agentId
            # teammate_spawned carries agent_id ('<name>@session-<hex>') and no
            # agentId. Neither shape appears on this machine; both are read.
            if ([string]::IsNullOrWhiteSpace($aid)) { $aid = [string]$res.agent_id }
            if (-not [string]::IsNullOrWhiteSpace($aid)) { $row.agent_id = $aid }
            $rm = [string]$res.resolvedModel
            if (-not [string]::IsNullOrWhiteSpace($rm)) {
                $row.resolved_model = $rm
                $row.resolved_base  = Get-LwgMetricsModelBase -Model $rm
            }
        }
        [void]$rows.Add($row)
    }

    # PLAIN @(), NOT `return ,@(...)`. The comma idiom this repository uses to
    # stop a returned collection being unrolled is right for a caller that
    # assigns the result bare; here it wraps the array in a second array and the
    # caller counts one dispatch where there were three. Every call site wraps
    # this in @() - which is what the doc block above promises by saying "always
    # an array" - so the unroll is the wanted behaviour and the comma is not.
    return @($rows)
}

function Get-LwgMetricsCohort {
    <#
      Which cohort ONE session belongs to, from its main-thread model counts.

        -Models  @{ '<model id>' = <requests> }

      Returns @{ cohort; share; total }.

      #165 R6: the cohort is assigned PER SESSION from the dominant main-thread
      model, and a session with no model above 60 % is `mixed` and excluded from
      every comparison. A session with no main-thread assistant line at all is
      `unknown` - which is not the same as `mixed`, and is not reported as one.

      The baseline is derived here at index time and is NEVER a date range.
      #165's finding 5 is the reason: the main thread ran different models on
      different days of the same week, so any comparison keyed on dates mixes
      cohorts and proves nothing.
    #>
    param([hashtable]$Models, [double]$MinShare = -1)

    if ($MinShare -lt 0) { $MinShare = $script:LwgMetricsCohortFloor }

    $total = [long]0
    $best  = $null
    $bestN = [long]0
    $tied  = $false
    if ($null -ne $Models) {
        foreach ($k in $Models.Keys) {
            if ($k -eq '<synthetic>') { continue }
            $n = [long]$Models[$k]
            if ($n -le 0) { continue }
            $total += $n
            if ($n -gt $bestN) { $best = $k; $bestN = $n; $tied = $false }
            elseif ($n -eq $bestN) { $tied = $true }
        }
    }

    if ($total -le 0) { return @{ cohort = 'unknown'; share = 0.0; total = [long]0 } }
    $share = [double]$bestN / [double]$total
    if ($tied -or $share -lt $MinShare) { return @{ cohort = 'mixed'; share = $share; total = $total } }
    return @{ cohort = $best; share = $share; total = $total }
}

function Get-LwgMetricsProjectsRoot {
    <#
      Where Claude Code keeps its transcripts, and HOW that was arrived at.

      Returns @{ path; source; exists; label }.

        path    <configuration root>\projects, or $null when the configuration
                root itself could not be resolved
        source  'env' | 'profile' | 'unresolved', from Get-LwgClaudeHomeInfo
        exists  whether that directory is actually there
        label   how the report NAMES it - the variable that resolved it, never
                its value. See the header on masking: the directory names under
                it are working directories with their separators replaced, so
                they carry the operator's account name, and a report that prints
                the root invites the whole tree into whatever the output is
                pasted into.

      Resolution is Get-LwgClaudeHomeInfo's and is not re-implemented here:
      CLAUDE_CONFIG_DIR first, then the profile. That is also the seam
      tests\metrics_behaviour.ps1 drives - pointing the variable at a scratch
      tree is the real resolution path with a different answer, not a test-only
      branch, so this command grows no parameter that exists only for a test.
    #>
    $home_ = Get-LwgClaudeHomeInfo
    $out = @{ path = $null; source = [string]$home_.source; exists = $false; label = '(unresolved)' }
    if ([string]::IsNullOrWhiteSpace([string]$home_.path)) { return $out }

    $out.path = [IO.Path]::Combine([string]$home_.path, 'projects')
    try { $out.exists = [IO.Directory]::Exists($out.path) } catch { }
    if ($out.source -eq 'env') { $out.label = '$env:CLAUDE_CONFIG_DIR\projects' }
    else                       { $out.label = '%USERPROFILE%\.claude\projects' }
    return $out
}

function Get-LwgMetricsTranscriptFiles {
    <#
      Every transcript under a projects root, classified. Returns a hashtable:

        @{ sessions = @(...); subagents = @(...); other = @(...) }

      each entry @{ path; slug_dir; session; name }.

        <root>\<slug>\<sessionId>.jsonl                       a session
        <root>\<slug>\<sessionId>\subagents\agent-*.jsonl     a dispatch
        <root>\<slug>\<sessionId>\subagents\workflows\wf_*\agent-*.jsonl
                                                              a workflow child

      RECURSES, AND THE RECURSION IS LOAD-BEARING. Workflow children sit one
      directory deeper than a plain dispatch; nine such directories were on the
      machine this was written on. A flat enumeration drops them silently, and
      the delegation figure - the one thing the operator actually asked for -
      then comes out low with nothing to say that it did.

      `slug_dir` is the DIRECTORY NAME, kept only so a file can be grouped with
      its session. It is never returned for printing.
    #>
    param([Parameter(Mandatory = $true)][string]$Root)

    $out = @{ sessions = @(); subagents = @(); other = @() }
    $full = $null
    try { $full = [IO.Path]::GetFullPath($Root) } catch { return $out }
    if (-not [IO.Directory]::Exists($full)) { return $out }

    $sessions  = New-Object System.Collections.ArrayList
    $subagents = New-Object System.Collections.ArrayList
    $other     = New-Object System.Collections.ArrayList

    $files = @()
    try { $files = [IO.Directory]::GetFiles($full, '*.jsonl', [IO.SearchOption]::AllDirectories) } catch { return $out }

    foreach ($f in $files) {
        $name = [IO.Path]::GetFileNameWithoutExtension($f)
        $dir  = [IO.Path]::GetDirectoryName($f)
        $rel  = $f.Substring($full.Length).TrimStart([char[]]@('\', '/'))
        $parts = $rel -split '[\\/]'

        if ($parts.Count -eq 2) {
            # <slug>\<sessionId>.jsonl
            [void]$sessions.Add(@{ path = $f; slug_dir = $parts[0]; session = $name; name = $name })
            continue
        }
        if ($parts.Count -ge 4 -and $parts[2] -eq 'subagents' -and $name -like 'agent-*') {
            # <slug>\<sessionId>\subagents\...\agent-*.jsonl - any depth below
            # `subagents`, which is what covers workflows\wf_<id>\.
            [void]$subagents.Add(@{ path = $f; slug_dir = $parts[0]; session = $parts[1]; name = $name })
            continue
        }
        [void]$other.Add(@{ path = $f; slug_dir = $parts[0]; session = $null; name = $name })
    }

    $out.sessions  = @($sessions)
    $out.subagents = @($subagents)
    $out.other     = @($other)
    return $out
}

function Get-LwgMetricsHealthSummary {
    <#
      What this plugin's OWN ledger says about dispatches, for a cross-check
      against what the transcripts say. Returns

        @{ present; rows; subagent_stop; sessions; error }

      `present` is $false when health.jsonl is not there - which is the state on
      a machine where the plugin has never run - and the caller reports that as
      NOT DETERMINED rather than as zero dispatches. "I looked and there was
      nothing" and "I could not look" are different statements.

      READ DIRECTLY RATHER THAN THROUGH Get-LwgHealthRecords, deliberately. That
      helper applies a 400-row tail limit every other caller depends on, and
      #165 R4 asks for a parameter to lift it. Adding one is an edit to
      lib\common.ps1 - a shared file with its own suite coupling - for a
      cross-check this slice reports and does not act on. The parameter belongs
      with the slice that needs it.
    #>
    param([Parameter(Mandatory = $true)][string]$StateDir)

    $out = @{ present = $false; rows = 0; subagent_stop = 0; sessions = 0; error = $null }
    if ([string]::IsNullOrWhiteSpace($StateDir)) { return $out }

    $path = $null
    try { $path = [IO.Path]::Combine([IO.Path]::GetFullPath($StateDir), 'health.jsonl') } catch { return $out }
    if (-not [IO.File]::Exists($path)) { return $out }
    $out.present = $true

    $sessions = New-Object 'System.Collections.Generic.HashSet[string]'
    try {
        foreach ($line in [IO.File]::ReadLines($path)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $out.rows++
            if ($line -notlike '*SubagentStop*') { continue }
            $rec = $null
            try { $rec = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            if ($null -eq $rec -or [string]$rec.event -ne 'SubagentStop') { continue }
            $out.subagent_stop++
            $s = [string]$rec.session
            if (-not [string]::IsNullOrWhiteSpace($s)) { [void]$sessions.Add($s) }
        }
    } catch { $out.error = $_.Exception.Message }
    $out.sessions = $sessions.Count
    return $out
}

function Format-LwgMetricsCount {
    <#
      A count with thousands separators, in the INVARIANT culture. Windows
      PowerShell 5.1 formats numbers in the operator's culture by default, and a
      report whose digit grouping changes with a regional setting is a report two
      people cannot compare.
    #>
    param([long]$Value)
    return $Value.ToString('N0', [Globalization.CultureInfo]::InvariantCulture)
}

function Format-LwgMetricsTokens {
    <#
      A token count, scaled. Invariant culture, same reason as above.

      Scaled and not raw because the numbers are enormous - billions of
      cache-read tokens is a normal week - and a column of raw digits is a
      column nobody reads. The exact figures are in -Json for anyone who needs
      them, so nothing is lost, only made legible.
    #>
    param([long]$Value)
    $ci = [Globalization.CultureInfo]::InvariantCulture
    if ($Value -ge 1000000000) { return ([double]$Value / 1000000000).ToString('N2', $ci) + ' G' }
    if ($Value -ge 1000000)    { return ([double]$Value / 1000000).ToString('N2', $ci)    + ' M' }
    if ($Value -ge 1000)       { return ([double]$Value / 1000).ToString('N1', $ci)       + ' k' }
    return $Value.ToString('N0', $ci)
}

function Format-LwgMetricsShare {
    <#
      Part over whole as a percentage, or the words NOT DETERMINED when the
      whole is zero.

      A share with a zero denominator is not zero per cent; it is a question with
      no answer, and this plugin's standing rule - the one the deleted sitrep
      command carried and #311 restated as the plugin's own - is that unknown is
      never reported as fine.
    #>
    param([long]$Part, [long]$Whole)
    if ($Whole -le 0) { return 'NOT DETERMINED' }
    $pct = 100.0 * [double]$Part / [double]$Whole
    return $pct.ToString('N1', [Globalization.CultureInfo]::InvariantCulture) + ' %'
}
