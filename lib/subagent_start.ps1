#requires -version 5
<#
  LW-WATCHTOWER context_injection module - the SubagentStart hook.

  Invoked from hooks/hooks.json in exec form:
      command: "powershell"
      args:    ["-NoProfile","-ExecutionPolicy","Bypass","-File",
                "${CLAUDE_PLUGIN_ROOT}/lib/subagent_start.ps1"]

  THE PROBLEM THIS SOLVES
  Claude Code snapshots CLAUDE.md into a subagent's context when the PARENT
  SESSION starts, not when the subagent is dispatched. An instruction added
  mid-session therefore never reaches a worker dispatched later that same
  session. That is not theoretical: a security classifier here refused a
  legitimate edit because its snapshot of CLAUDE.md predated the instruction
  authorising it.

  SubagentStart fires once per dispatch, so anything it emits is current by
  construction. This hook reads context/worker_facts.md - live, every time -
  followed by context/worker_facts.local.md if that optional, gitignored,
  per-machine file exists, and hands the two as one additionalContext block.

  THE SCHEMA, VERIFIED RATHER THAN ASSUMED
  Checked against the claude-code 2.1.220 binary, not only the published docs,
  because shipping a hook that cannot fire is the defect this plugin exists to
  catch:

    - 'SubagentStart' is in the CLI's hook event registry, alongside
      SessionStart and SubagentStop, and has its own executeSubagentStartHooks
      entry point.
    - The output validator accepts, for this event, exactly
        v.object({ hookEventName: v.literal("SubagentStart"),
                   additionalContext: v.string().optional() })
      so additionalContext is the ONE field that carries injected text.
      continue / suppressOutput / stopReason / systemMessage remain common
      top-level fields shared by every event.
    - The consumer collects every hook's additionalContext and pushes it into
      the SUBAGENT's own message list as
        { type:"hook_additional_context", hookName:"SubagentStart", ... }
      before the worker's first turn - the identical code path SessionStart
      already uses, which this plugin has relied on since Phase 1.
    - The event cannot block. Exit 2 renders stderr as a hook-error notice in
      the subagent's transcript and the dispatch proceeds regardless, so this
      script has no way to stop a dispatch even if it wanted one.

  WHY NOTHING HERE IS DOT-SOURCED, AND WHY THERE IS NO CMDLET ON THIS PATH
  This runs on EVERY dispatch, so its cost is paid by every worker in every
  session. Measured on this machine, interleaved rounds, wall clock including
  interpreter startup:

      bare `exit 0` after draining stdin             ~275-300 ms  (the floor)
      dot-source common.ps1 + Read-LwgStdin
        + Get-LwgConfig + Test-LwgModule              ~634 ms

  So the flag is read out of config.json by direct string scanning and the
  envelope is written by hand. Profiling the first draft in-process then found
  that the remaining cost was not data work either - it was PowerShell loading
  cmdlet modules and stepping character loops:

      New-Object       first call in a fresh process   ~92 ms
      Test-Path        first call in a fresh process   ~40 ms
      ConvertFrom-Json first call in a fresh process  ~141-182 ms
      char-by-char loop, per 371 chars                 ~13 ms

  Hence the rules this file follows and must keep following:

    * NO cmdlets on the fast path. [IO.File]::Exists rather than Test-Path,
      [IO.Path]::Combine rather than Join-Path, [IO.Path]::GetDirectoryName
      rather than Split-Path, no New-Object anywhere.
    * NO character loops. Brace matching jumps between interesting characters
      with String.IndexOfAny; escaping is a chain of ordinal String.Replace.
      The exact character-by-character escaper is still here and still correct,
      but it is reached only by text the file's own contract said would not
      appear.
    * NO JSON engine. ConvertFrom-Json / ConvertTo-Json are the single most
      expensive thing a fresh PowerShell 5.1 process can touch.

  That is a deliberate, narrow duplication of Get-LwgConfig + Test-LwgModule,
  and it is bounded by the escalation rule below rather than being left free to
  drift from them.

  PER-REPO OVERRIDES STILL WORK, EXACTLY
  The fast scan answers only the GLOBAL flag. If config.json's `repos` block
  carries an override for this module - which the shipped config does not -
  the script escalates to the real thing: dot-source common.ps1, parse the
  payload, resolve the slug, ask Test-LwgModule. An operator who configures an
  override pays the full cost; nobody else does. The alternative, silently
  applying a per-repo override globally, is the class of quiet wrongness this
  plugin exists to remove.

  ALWAYS exits 0. A governance layer that cannot inject a note must never be
  able to fail a dispatch.
#>

$ErrorActionPreference = 'Stop'

$LwgModuleName = 'context_injection'

# TWO files, in this order, and the second one is OPTIONAL.
#
#   worker_facts.md         tracked. Ships to every install, so it may only
#                           state what is true on every install.
#   worker_facts.local.md   gitignored, per machine. Absent by default; when it
#                           is absent NOTHING is said about it - no error, no
#                           warning, no log line, no placeholder in the injected
#                           text. Its content is appended AFTER the invariants,
#                           under the same comment rules and the same ceiling.
#
# The split exists because this hook injects the same bytes into every worker on
# every machine. One laptop's interpreter path shipped in the tracked file is a
# false statement everywhere else, asserted with the authority of a governance
# layer - the founding defect this plugin exists to catch.
#
# Nothing here PROBES for a machine fact instead. Measured in a fresh PowerShell
# 5.1 process: Get-Command costs ~9-25 ms when it finds its target and
# 600-1360 ms when it does not, because a miss walks the whole PATH and the
# module autoload cache. A probe exists to detect absence, so its worst case is
# its normal case, and one miss alone would cost twice this script's entire
# budget. The .local.md file carries those facts instead.
$LwgFactsRel      = 'context\worker_facts.md'
$LwgFactsLocalRel = 'context\worker_facts.local.md'

# A worker handed a wall of standing rules reads none of it. worker_facts.md is
# documented as "under 80 words"; this is the backstop for the day somebody
# pastes an essay into it, so one bad edit degrades the note rather than every
# dispatch in every session.
$LwgMaxChars = 2000

# The only characters brace matching has to stop on. Everything between them is
# skipped by a native IndexOfAny rather than stepped over in PowerShell.
$LwgScanChars = [char[]]@('"', '{', '}', '\')

# Control characters that the Replace chain in ConvertTo-LwgJsonString does NOT
# cover. Their presence is what sends a string to the exact escaper; \b \f \n
# \r \t are handled directly and are deliberately absent from this list.
$LwgOddControls = [char[]]@(
    0, 1, 2, 3, 4, 5, 6, 7, 11, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
    25, 26, 27, 28, 29, 30, 31, 127
)

# stdin is drained but NOT parsed on the fast path - parsing it would cost the
# 141-182 ms ConvertFrom-Json warm-up for fields this script does not need. The
# raw text is kept because the escalation path cannot read stdin again: a pipe
# is consumed exactly once.
$LwgStdinRaw = ''

function Get-LwgRootLocal {
    <#
      Plugin root. Same rule as Get-LwgPluginRoot in common.ps1, deliberately
      duplicated rather than dot-sourced - see the header - and written with
      [IO.Directory]::Exists / [IO.Path]::GetDirectoryName because Test-Path and
      Split-Path would drag in a cmdlet module for two path operations.
    #>
    if ($env:CLAUDE_PLUGIN_ROOT -and [System.IO.Directory]::Exists($env:CLAUDE_PLUGIN_ROOT)) {
        return $env:CLAUDE_PLUGIN_ROOT
    }
    return [System.IO.Path]::GetDirectoryName($PSScriptRoot)
}

function Get-LwgJsonObjectSpan {
    <#
      The character span of the OBJECT value of member "$Key" in $Text, as a
      HASHTABLE @{ start; end } - end exclusive - or $null when there is no such
      member or its value is not an object.

      A hashtable, deliberately: PowerShell enumerates a returned collection but
      not a returned hashtable. The same unrolling trap has shipped three times
      in this repo already; Get-LwgRepoInfo in common.ps1 carries the long
      version of that note.

      Brace matching is STRING-AWARE. config.json is more prose than data - the
      $comment fields run to whole paragraphs and contain both braces and
      escaped quotes - so a naive depth counter would unbalance on the first one
      and silently return the wrong region.

      The scan JUMPS between " { } and \ with String.IndexOfAny instead of
      stepping character by character. On config.json that is about 60 native
      calls rather than several thousand PowerShell loop iterations, and it is
      the difference between ~2 ms and ~70 ms on a hook that runs per dispatch.

      ONLY A MEMBER OF THE ROOT OBJECT MATCHES, and until 3 August 2026 there was
      no notion of depth here at all. The needle search was a bare
      $Text.IndexOf('"modules"'), so the FIRST occurrence in DOCUMENT ORDER won
      at ANY nesting level - and config.json's `repos` block is documented to
      hold per-repo `modules` objects. Measured, by running the real hook against
      a config.json holding

          { "repos": { "<a repo>": { "modules": { "docs_coupling": false } } },
            "modules": { "context_injection": false } }

      the scan returned the PER-REPO block as the global one, found no
      context_injection in it, kept its fail-open default of $true and injected
      into every dispatch while the module was switched off. The escalation two
      dozen lines below cannot save that: it fires only when the `repos` span
      names THIS module, and this one names a different one. The same bytes in
      the shipped key order answered correctly, which is the whole defect - a
      raw-text scanner whose correctness depended on which of two sibling keys
      came first in a file the $comment invites operators to hand-edit, with
      nothing anywhere asserting that order.

      Depth is now carried by the SAME jump loop that was already there rather
      than by a second pass: braces outside strings move it, and a member name is
      a candidate only while it stands at depth 1. The cost is real and is
      measured rather than waved at: every string in the file is now walked to
      its closing quote instead of being jumped past by a single IndexOf for the
      needle. Both versions were AST-extracted unmodified and run against this
      repository's own config.json (33,175 chars) under Windows PowerShell 5.1,
      200 calls in a warmed process:

          -Key 'modules'   before  0.168 ms/call     after  0.764 ms/call

      Both return the identical span on that file - start 12519, end 12774 -
      as do both for 'repos'. Half a millisecond against a budget the header
      above sets in tens of milliseconds, to stop the scan silently answering
      about the wrong object.

      A note on the escape at the top of the loop: OUTSIDE a string a backslash
      is not meaningful JSON and advances by ONE. Skipping two there - which is
      right inside a string, where a backslash escapes the next character - could
      step over a brace and corrupt the depth count, which is the one thing this
      function now depends on.
    #>
    param([string]$Text, [string]$Key)

    if ([string]::IsNullOrEmpty($Text) -or [string]::IsNullOrEmpty($Key)) { return $null }

    $len   = $Text.Length
    $depth = 0
    $k     = 0
    while ($k -ge 0 -and $k -lt $len) {
        $k = $Text.IndexOfAny($script:LwgScanChars, $k)
        if ($k -lt 0) { break }
        $c = $Text[$k]
        if ($c -eq '{') { $depth++; $k++; continue }
        if ($c -eq '}') { $depth--; $k++; continue }
        # A backslash outside a string is not meaningful JSON - ONE character.
        if ($c -ne '"') { $k++; continue }

        # A string starts here. Find its end with the same jumping, so the whole
        # of a $comment paragraph costs one IndexOfAny per interesting character
        # in it rather than one loop body per character.
        $p   = $k + 1
        $end = -1
        while ($p -ge 0 -and $p -lt $len) {
            $p = $Text.IndexOfAny($script:LwgScanChars, $p)
            if ($p -lt 0) { break }
            $ch = $Text[$p]
            # Inside a string a backslash escapes the next character, including
            # a quote - skip both, or \" would be read as the end of the string.
            if ($ch -eq '\') { $p += 2; continue }
            if ($ch -eq '"') { $end = $p; break }
            $p++
        }
        # An unterminated string is not JSON and there is nothing to be said
        # about a member of it.
        if ($end -lt 0) { return $null }

        if ($depth -eq 1 -and ($end - $k - 1) -eq $Key.Length -and
            [string]::CompareOrdinal($Text, ($k + 1), $Key, 0, $Key.Length) -eq 0) {
            # Whitespace is skipped with Substring().Trim() rather than a
            # character-stepping while loop. Both are correct; only one of them
            # costs PowerShell a loop body to compile, and compilation - not the
            # work - is what this script's budget is actually spent on.
            $colon = $Text.IndexOf(':', $end + 1)
            if ($colon -ge 0 -and $Text.Substring(($end + 1), ($colon - $end - 1)).Trim().Length -eq 0) {
                $j = $Text.IndexOf('{', $colon + 1)
                if ($j -ge 0 -and $Text.Substring(($colon + 1), ($j - $colon - 1)).Trim().Length -eq 0) {
                    $d     = 0
                    $inStr = $false
                    $m     = $j
                    while ($m -ge 0 -and $m -lt $len) {
                        $m = $Text.IndexOfAny($script:LwgScanChars, $m)
                        if ($m -lt 0) { break }
                        $cc = $Text[$m]
                        if ($inStr) {
                            if ($cc -eq '\') { $m += 2; continue }
                            if ($cc -eq '"') { $inStr = $false }
                            $m++
                            continue
                        }
                        if ($cc -eq '"') { $inStr = $true; $m++; continue }
                        if ($cc -eq '{') { $d++;           $m++; continue }
                        if ($cc -eq '}') {
                            $d--
                            if ($d -le 0) { return @{ start = $j; end = ($m + 1) } }
                            $m++
                            continue
                        }
                        $m++
                    }
                    return $null
                }
            }
        }
        # Not the member, or its value is not an object. Carry on from after the
        # string - the depth is unchanged, because a string cannot move it.
        $k = $end + 1
    }
    return $null
}

function Get-LwgJsonBool {
    <#
      $true / $false for member "$Key" wherever it appears in $Text with a
      literal boolean value, or $null when it appears nowhere with one.

      $null is a THIRD answer and callers must treat it as such: 'absent' is not
      'false'. Test-LwgModule reads an absent module as enabled, and this has to
      agree with it.

      A bare name in an array - config.json lists every module name under
      $status.implemented - is not followed by a colon and therefore never
      matches. Looking for the colon rather than just the name is the whole
      reason that is safe.
    #>
    param([string]$Text, [string]$Key)

    if ([string]::IsNullOrEmpty($Text) -or [string]::IsNullOrEmpty($Key)) { return $null }

    $needle = '"' + $Key + '"'
    $i = $Text.IndexOf($needle, [StringComparison]::Ordinal)
    while ($i -ge 0) {
        $after = $i + $needle.Length
        $colon = $Text.IndexOf(':', $after)
        if ($colon -ge 0 -and $Text.Substring($after, ($colon - $after)).Trim().Length -eq 0) {
            # 16 characters is more than enough to see past any whitespace to
            # the literal, and bounds the Substring on a 12 KB config file.
            $tail = $Text.Substring(($colon + 1), [Math]::Min(16, ($Text.Length - $colon - 1))).TrimStart()
            # A STRING value that happens to begin 'true' cannot match: TrimStart
            # leaves its opening quote in front.
            if ($tail.StartsWith('true',  [StringComparison]::Ordinal)) { return $true }
            if ($tail.StartsWith('false', [StringComparison]::Ordinal)) { return $false }
        }
        $i = $Text.IndexOf($needle, $i + 1, [StringComparison]::Ordinal)
    }
    return $null
}

function ConvertTo-LwgJsonString {
    <#
      One JSON string literal, quotes included, built by hand. ConvertTo-Json
      would do this correctly and would cost the same first-use warm-up as
      ConvertFrom-Json, which is the whole reason this script is fast.

      TWO paths, and the fast one is not the trusting one. worker_facts.md is
      documented as plain ASCII, so the common case is a chain of ordinal
      String.Replace calls - about 3 ms. Whether that was actually enough is
      then CHECKED rather than assumed: a UTF-8 byte count that differs from the
      character count proves a character above U+007F is present, and
      IndexOfAny finds the control characters the chain does not cover. Either
      one sends the string to the exact character-by-character escaper below,
      which emits \uXXXX for everything outside printable ASCII.

      So the output is pure ASCII whatever the facts file and whatever the
      console code page, and the fast path can never quietly emit broken JSON.
    #>
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return '""' }

    $needsExact = ($Text.Length -ne [System.Text.Encoding]::UTF8.GetByteCount($Text)) -or
                  ($Text.IndexOfAny($script:LwgOddControls) -ge 0)

    if (-not $needsExact) {
        # Backslash FIRST: escaping it after the others would double-escape the
        # backslashes they just introduced.
        return '"' + $Text.Replace('\', '\\').
                           Replace('"', '\"').
                           Replace([string][char]8,  '\b').
                           Replace([string][char]12, '\f').
                           Replace("`r", '\r').
                           Replace("`n", '\n').
                           Replace("`t", '\t') + '"'
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('"')
    foreach ($ch in $Text.ToCharArray()) {
        $c = [int]$ch
        if     ($ch -eq '"')  { [void]$sb.Append('\"') }
        elseif ($ch -eq '\')  { [void]$sb.Append('\\') }
        elseif ($c  -eq 8)    { [void]$sb.Append('\b') }
        elseif ($c  -eq 9)    { [void]$sb.Append('\t') }
        elseif ($c  -eq 10)   { [void]$sb.Append('\n') }
        elseif ($c  -eq 12)   { [void]$sb.Append('\f') }
        elseif ($c  -eq 13)   { [void]$sb.Append('\r') }
        elseif ($c  -lt 32 -or $c -gt 126) { [void]$sb.AppendFormat('\u{0:x4}', $c) }
        else                  { [void]$sb.Append($ch) }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Get-LwgWorkerFacts {
    <#
      The text to inject, or '' when there is nothing to say.

      $Path is a LIST, read in order, and a path that does not exist is skipped
      in silence - that is what makes worker_facts.local.md optional rather than
      a second thing every install has to create. Each file is read inside its
      own try, so an unreadable local file costs its own lines and not the
      invariants as well.

      The file contract, stated in the files themselves and in README: a line
      whose first non-space character is '#' is a comment and is dropped, blank
      lines are dropped, every other line is injected verbatim. That keeps the
      editing instructions - which are long, and need to be - out of the thing
      every worker pays for.

      The ceiling is applied ONCE, to the joined result, because it is a bound on
      what a worker is handed rather than a bound on either file: a per-file
      ceiling would let two files inside it add up to a block over it.
    #>
    param([string[]]$Path)

    $keep = @()
    foreach ($p in $Path) {
        try {
            if ([string]::IsNullOrWhiteSpace($p))       { continue }
            if (-not [System.IO.File]::Exists($p))      { continue }
            # ReadAllText(path) is UTF-8 with BOM detection, so a file saved by
            # PS 5.1's `-Encoding utf8` does not arrive with a BOM glued to line 1.
            $raw = [System.IO.File]::ReadAllText($p)
            if ([string]::IsNullOrWhiteSpace($raw)) { continue }

            # .Split on a char rather than -split "`r?`n": the latter is a regex,
            # and first use of the regex engine in a fresh process costs more than
            # everything else this script does put together.
            foreach ($line in $raw.Split([char]10)) {
                $l = $line.TrimEnd([char]13).TrimEnd()
                $t = $l.TrimStart()
                if ($t.Length -eq 0)     { continue }
                if ($t[0] -eq [char]'#') { continue }
                $keep += $l
            }
        } catch { }
    }
    if ($keep.Count -eq 0) { return '' }

    try {
        $text = ($keep -join "`n")
        if ($text.Length -gt $script:LwgMaxChars) {
            # Cut at a line boundary, never mid-sentence: a truncated fact that
            # still reads like a complete one is worse than a missing one.
            $cut = $text.LastIndexOf("`n", ($script:LwgMaxChars - 1))
            if ($cut -lt 1) { $cut = $script:LwgMaxChars }
            $text = $text.Substring(0, $cut) + "`n(worker facts truncated - keep them under 80 words)"
        }
        return $text
    } catch { }
    return ''
}

try {
    # 1. Drain stdin. Unparsed - see the header. Keeping the pipe empty also
    #    means the CLI's writer never blocks on a hook that ignored it.
    try { $LwgStdinRaw = [Console]::In.ReadToEnd() } catch { $LwgStdinRaw = '' }

    $root       = Get-LwgRootLocal
    $cfgPath    = [System.IO.Path]::Combine($root, 'config.json')
    $factsPath  = [System.IO.Path]::Combine($root, $LwgFactsRel)
    # Not probed for here. [IO.File]::Exists inside Get-LwgWorkerFacts answers
    # it, and on the overwhelmingly common path - no local file - that is one
    # failed stat and no cmdlet.
    $factsLocal = [System.IO.Path]::Combine($root, $LwgFactsLocalRel)

    # 2. Resolve the flag.
    #    Fail-open at every step, matching Get-LwgConfig and Test-LwgModule: a
    #    missing or unreadable config leaves every module ON, and a module the
    #    config does not mention is ON. A governance layer that switches itself
    #    off because it could not read its own settings is the failure mode.
    $enabled  = $true
    $escalate = $false
    $rawCfg   = ''
    try {
        if ([System.IO.File]::Exists($cfgPath)) { $rawCfg = [System.IO.File]::ReadAllText($cfgPath) }
    } catch { $rawCfg = '' }

    if (-not [string]::IsNullOrWhiteSpace($rawCfg)) {
        $modSpan = Get-LwgJsonObjectSpan -Text $rawCfg -Key 'modules'
        if ($null -ne $modSpan) {
            $v = Get-LwgJsonBool -Text $rawCfg.Substring($modSpan.start, ($modSpan.end - $modSpan.start)) -Key $LwgModuleName
            if ($null -ne $v) { $enabled = [bool]$v }
        }
        # A per-repo override anywhere under `repos` means the fast scan cannot
        # answer the question - only the slug can. Escalate rather than guess.
        $repoSpan = Get-LwgJsonObjectSpan -Text $rawCfg -Key 'repos'
        if ($null -ne $repoSpan) {
            $o = Get-LwgJsonBool -Text $rawCfg.Substring($repoSpan.start, ($repoSpan.end - $repoSpan.start)) -Key $LwgModuleName
            if ($null -ne $o) { $escalate = $true }
        }
    }

    if ($escalate) {
        # The exact answer, at full price. Reached only when an operator has
        # actually written a per-repo override for this module.
        . ([System.IO.Path]::Combine($PSScriptRoot, 'common.ps1'))
        $payload = [pscustomobject]@{}
        try {
            if (-not [string]::IsNullOrWhiteSpace($LwgStdinRaw)) {
                $p = $LwgStdinRaw | ConvertFrom-Json
                if ($p -is [System.Management.Automation.PSCustomObject]) { $payload = $p }
            }
        } catch { }
        $cfg     = Get-LwgConfig
        $enabled = Test-LwgModule -Name $LwgModuleName -Config $cfg -Repo (Get-LwgRepo $payload)
    }

    # 3. Off means SILENT. No envelope, no log line, no state written.
    if (-not $enabled) { exit 0 }

    $facts = Get-LwgWorkerFacts -Path @($factsPath, $factsLocal)
    if ([string]::IsNullOrWhiteSpace($facts)) { exit 0 }

    # 4. The envelope, hand-built. hookEventName is mandatory - the CLI rejects
    #    the whole output without it - and there is deliberately no `decision`,
    #    `continue` or `stopReason` field, so this cannot interfere with a
    #    dispatch by construction rather than by intent.
    [Console]::Out.Write('{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":' +
                         (ConvertTo-LwgJsonString -Text $facts) +
                         '},"suppressOutput":true}')

} catch {
    # Never break a dispatch. The log write is on the ERROR path only: doing it
    # on every dispatch would mean dot-sourcing common.ps1 and a ConvertTo-Json
    # warm-up per worker, which is most of the budget this script exists to keep.
    try {
        . ([System.IO.Path]::Combine($PSScriptRoot, 'common.ps1'))
        Write-LwgEvent -Event 'SubagentStartError' -Extra @{
            module = 'context_injection'; error = $_.Exception.Message } | Out-Null
    } catch { }
}

exit 0
