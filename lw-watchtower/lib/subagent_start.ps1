#requires -version 5
<#
  LW-WATCHTOWER SubagentStart hook - TWO modules, in one process, on purpose.

    context_injection   reads context/worker_facts.md and hands it to the worker
                        as hookSpecificOutput.additionalContext. This file's
                        original and principal job, and everything below about
                        cost was written for it.
    failure_capture     appends ONE line to health.jsonl per dispatch: the START
                        half of the dispatch record whose STOP half
                        lib/supervisor.ps1:825-830 has always written. It is an
                        ADDITION to that module, not a module of its own - no
                        registry entry, no `modules` key, no state file, no
                        rotation wiring and no hooks/hooks.json edit. See THE
                        DISPATCH RECORD below.

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
    * NO PROSE THAT CAN LIVE SOMEWHERE ELSE. 5.1 compiles the WHOLE file before
      running a statement, so comments HERE cost ms per dispatch as comments in
      no other file in this plugin do - ~10 of the row's 18 ms, measured below
      by a leg that writes no row. Long form goes to docs/modules.md.

  That is a deliberate, narrow duplication of Get-LwgConfig + Test-LwgModule,
  and it is bounded by the escalation rule below rather than being left free to
  drift from them.

  THE DISPATCH RECORD - AND THE ARGUMENT THIS HEADER USED TO MAKE AGAINST IT
  Until 6 September 2026 this file wrote NOTHING on its happy path and said so
  in four places. The reasoning was sound: a log write here meant dot-sourcing
  common.ps1 and a ConvertTo-Json warm-up per worker. What changed is that this
  write does neither. THE LONG FORM - why the row exists, what it unblocks, what
  it costs the readers - is in docs/modules.md under failure_capture, because
  prose in THIS file is not free: see the measurement below.

  ONE LINE, appended to health.jsonl in the state directory:

      {"ts":"<ISO-8601 o>","event":"SubagentStart","session":"<session_id>",
       "agent_id":"...","agent_type":"..."}

  That is New-Record's envelope (lib/supervisor.ps1:195-203), not a new set of
  names, because four readers already parse that shape - supervisor.ps1:403,
  gate_send.ps1:330, Get-LwgHealthRecords, statusline/statusline.ps1:942. `ts`
  IS the dispatch time; no second timestamp under a second name in a file whose
  readers sort on ts. The STOP half has always been written at
  supervisor.ps1:825-830; this is the START half.

  IT STAYS ON THE FAST PATH. The flag is failure_capture, read from the
  `modules` span this file has ALREADY extracted for its own module - an IndexOf
  walk over a substring, not a second scan; the override and both `repos` spans
  are asked for that name the same way, so the two flags escalate under one
  rule. The three fields come out of the stdin text already drained, through
  Get-LwgJsonStringValue below. [DateTime]::UtcNow, not Get-Date.
  [IO.File]::AppendAllText with a BOM-less UTF8Encoding, as Add-LwgLine does at
  common.ps1:2111-2113, with that function's 20/40/60/80/100 ms ladder spelled
  as [Threading.Thread]::Sleep. No dot-source, no cmdlet, no JSON engine.

  cwd IS DELIBERATELY OMITTED AND THAT OMISSION IS LOAD BEARING. supervisor.ps1
  redacts every payload field through Get-LwgRedacted, which is the REGEX
  ENGINE, and this path cannot pay for it - see Get-LwgWorkerFacts below. So the
  row carries only fields that need no redaction, and cwd, the one field here
  holding an operator name and a clone root, is not written. THE LIMIT THAT
  LEAVES, stated rather than glossed: THIS ROW IS NOT REDACTED. A credential
  pasted into an agent_type or a session id reaches health.jsonl unmasked. The
  200-character cap bounds that exposure and does not remove it. A field added
  here that could carry free text needs redaction this path cannot afford, and
  that is where this decision is re-argued rather than extended.

  IT IS GATED ON A MODULE THIS FILE IS NOT. failure_capture off means no row;
  context_injection off does NOT - the write sits ABOVE this file's own early
  exit. tests/subagent_scan.ps1 has a case for each direction.

  MEASURED, AND THE MEASUREMENT DID NOT SAY WHAT THE FIRST DRAFT ASSUMED.
  The override note below sets this file's standard - interleaved rounds, leg
  order varied, one warm-up sweep discarded, the real shipped config.json in
  every leg, every run checked to have actually injected and to have written or
  not written its row. Two things are added to it here. A NULL CONTROL leg runs
  the BASELINE hook a second time, so an added cost is read against what the
  instrument reports for a difference known to be zero. And the statistic is the
  MEDIAN OF PER-ROUND DIFFERENCES rather than a difference of medians: at 25 and
  100 rounds the baseline leg's own median sat 18 ms from a second baseline leg
  doing identical work, so a 10 ms question was inside the instrument's error.

  Four legs, every leg carrying a same-size config.override.json so the override
  READ is not charged to the leg that needs it. 96 rounds per run, two runs
  after the prose in this header was cut back:

      B - A   the row, added cost          +18.0   +18.5  ms
      D - A   the same file, flag OFF       +6.8    +5.0  ms
      C - A   NULL CONTROL, must be ~0      +4.2    +0.3  ms

  SO THE ROW COSTS ABOUT 18 ms PER DISPATCH. Slice 0's budget was ~10 ms, so the
  design was re-argued rather than absorbed, and ON 6 SEPTEMBER 2026 THE 18 ms WAS
  ACCEPTED. Three reasons, none of them "it is small": the ~10 ms budget was a
  guess made before anyone had measured what a timestamp costs on this path, and a
  measurement beats a guess; ~10 of the 18 is the INTERPRETER, not the design, so no
  rewrite of the row removes it; and 18 ms is ~4% of this hook's own 430-580 ms. The
  alternative was not a cheaper row - it was NO START ROW FROM THIS EVENT AT ALL,
  which is a decision about whether the feature exists. The number stays stated
  rather than rounded. Where it goes, from component profiling in a fresh
  PowerShell 5.1 process:

      [DateTime]::UtcNow.ToString('o')   first call   ~4.0 ms  irreducible -
                                                      Get-Date costs 145-220 ms,
                                                      and Ticks.ToString() costs
                                                      the same as 'o' does
      [IO.File]::AppendAllText           first call   ~1.9 ms  the write itself
      [Text.Encoding]::UTF8.GetByteCount first call   ~1.2 ms  the injection
                                                      below would have paid this
                                                      anyway - net zero

  and the remaining ~6 ms is the file being LONGER AT ALL, which is what the
  flag-OFF leg measures: it writes no row and still costs ~6 ms, because
  PowerShell 5.1 tokenises and compiles the WHOLE file before running a
  statement. Prose in THIS file is charged per dispatch in a way prose in every
  other file in this plugin is not. That is a fact about this file nothing wrote
  down before 6 September 2026; it is why the long form of this section is in
  docs/modules.md, and it is a cost no rewrite of the row can remove.

  THE OPERATOR OVERRIDE IS READ TOO, AND THAT IS NEW - #11
  config.json is the SHIPPED DEFAULTS and nothing writes it any more. The
  operator's own ON/OFF choices go to config.override.json under the state
  directory, which Get-LwgConfig merges over the defaults for every other
  reader in this plugin. This hook read config.json ALONE until 3 September
  2026, so switching context_injection off did nothing to it while the banner,
  the doctor and the config command's own read-back all reported it off -
  which is why bin\lwg-config.ps1 refused to write this one module at all.
  The same two scanners are now run over the override, with no rules of their
  own, and the escalation below is what covers every shape they cannot read.
  Section 2 of the body carries the whole of that reasoning and its cost.

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

# THE SECOND MODULE IN THIS FILE - see THE DISPATCH RECORD in the header. The
# row is an addition to failure_capture and gated on its flag alone.
$LwgLedgerModule = 'failure_capture'

# Where the row goes. ALREADY rotated from supervisor.ps1:645, above the
# failure_capture gate, so the 5 MB / 500-line discipline covers this writer for
# free and nothing is wired here for it.
$LwgLedgerLog = 'health.jsonl'

# The cap every payload-derived FIELD is truncated to. This is common.ps1:2138's
# $script:LwgLogFieldMax REPEATED AS A LITERAL, for the reason
# statusline/statusline.ps1:873-884 repeats common.ps1:2132's 8192 - both files
# dot-source nothing. IF ONE MOVES, BOTH MOVE.
$LwgLogFieldMax = 200

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

function Get-LwgJsonStringValue {
    <#
      The DECODED string value of member "$Key" at DEPTH 1 of $Text, or $null
      when there is no such member, its value is not a string, or $Text is not
      parseable that far. $null is a THIRD answer, as it is for Get-LwgJsonBool:
      the one caller writes no record at all when the fields that identify a
      dispatch come back $null.

      The same IndexOfAny jump loop, string-aware brace matching and depth rule
      as Get-LwgJsonObjectSpan above, over the hook PAYLOAD rather than over
      config.json, and here rather than in common.ps1 for the reason the header
      gives. DEPTH 1 ONLY: a payload nests, and a row built from a nested member
      would name something other than the dispatch - Get-LwgJsonObjectSpan's
      docstring records what that cost the first time.

      DECODING IS CHECKED, NOT ASSUMED, as ConvertTo-LwgJsonString checks its
      Replace chain: a literal with no backslash IS its value and comes back
      from one Substring; only an escaped one pays for the loop. It must decode
      BEFORE the value is re-escaped for our record, or \n would be written as
      \\n, and before truncation, or a cut could fall inside a \uXXXX.
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
        # Outside a string a backslash is not meaningful JSON - ONE character.
        if ($c -ne '"') { $k++; continue }

        $p   = $k + 1
        $end = -1
        while ($p -ge 0 -and $p -lt $len) {
            $p = $Text.IndexOfAny($script:LwgScanChars, $p)
            if ($p -lt 0) { break }
            $ch = $Text[$p]
            if ($ch -eq '\') { $p += 2; continue }
            if ($ch -eq '"') { $end = $p; break }
            $p++
        }
        # An unterminated string is not JSON and there is nothing to be said
        # about a member of it.
        if ($end -lt 0) { return $null }

        if ($depth -eq 1 -and ($end - $k - 1) -eq $Key.Length -and
            [string]::CompareOrdinal($Text, ($k + 1), $Key, 0, $Key.Length) -eq 0) {
            $colon = $Text.IndexOf(':', $end + 1)
            if ($colon -ge 0 -and $Text.Substring(($end + 1), ($colon - $end - 1)).Trim().Length -eq 0) {
                $q = $Text.IndexOf('"', $colon + 1)
                # Only whitespace may stand between the colon and the opening
                # quote. A number, an object, an array or null therefore falls
                # through to $null rather than being read as a string.
                if ($q -ge 0 -and $Text.Substring(($colon + 1), ($q - $colon - 1)).Trim().Length -eq 0) {
                    $v    = $q + 1
                    $vend = -1
                    while ($v -ge 0 -and $v -lt $len) {
                        $v = $Text.IndexOfAny($script:LwgScanChars, $v)
                        if ($v -lt 0) { break }
                        $cv = $Text[$v]
                        if ($cv -eq '\') { $v += 2; continue }
                        if ($cv -eq '"') { $vend = $v; break }
                        # A brace inside a string moves no depth and ends nothing.
                        $v++
                    }
                    if ($vend -lt 0) { return $null }
                    $lit = $Text.Substring(($q + 1), ($vend - $q - 1))
                    if ($lit.IndexOf('\') -lt 0) { return $lit }

                    # THE RARE PATH. A payload field carrying an escape - a
                    # Windows path in a cwd is the ordinary case - is decoded
                    # exactly, character by character. This is the same trade
                    # ConvertTo-LwgJsonString makes in the other direction: the
                    # loop is correct and is reached only by text the fast check
                    # proved it had to be reached by.
                    $sb = [System.Text.StringBuilder]::new()
                    $i  = 0
                    while ($i -lt $lit.Length) {
                        $lc = $lit[$i]
                        if ($lc -ne '\') { [void]$sb.Append($lc); $i++; continue }
                        $i++
                        if ($i -ge $lit.Length) { break }
                        $e = $lit[$i]; $i++
                        if     ($e -eq '"') { [void]$sb.Append('"') }
                        elseif ($e -eq '\') { [void]$sb.Append('\') }
                        elseif ($e -eq '/') { [void]$sb.Append('/') }
                        elseif ($e -eq 'b') { [void]$sb.Append([char]8) }
                        elseif ($e -eq 'f') { [void]$sb.Append([char]12) }
                        elseif ($e -eq 'n') { [void]$sb.Append([char]10) }
                        elseif ($e -eq 'r') { [void]$sb.Append([char]13) }
                        elseif ($e -eq 't') { [void]$sb.Append([char]9) }
                        elseif ($e -eq 'u' -and ($i + 4) -le $lit.Length) {
                            $code = 0
                            if ([int]::TryParse($lit.Substring($i, 4),
                                                [Globalization.NumberStyles]::HexNumber,
                                                [Globalization.CultureInfo]::InvariantCulture,
                                                [ref]$code)) {
                                [void]$sb.Append([char]$code); $i += 4
                            } else {
                                # Not a hex quad. Kept verbatim rather than
                                # dropped: this is a decoder, not a validator,
                                # and ConvertTo-LwgJsonString re-escapes
                                # whatever comes out of it.
                                [void]$sb.Append('\u')
                            }
                        }
                        else { [void]$sb.Append('\'); [void]$sb.Append($e) }
                    }
                    return $sb.ToString()
                }
            }
            # The member is here and its value is not a string. That is an
            # answer, not a reason to keep looking.
            return $null
        }
        # Not the member. Carry on from after the string - the depth is
        # unchanged, because a string cannot move it.
        $k = $end + 1
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
    #
    #    DECODED AS UTF-8 EXPLICITLY, and deliberately NOT through
    #    [Console]::In, whose encoding is the CONSOLE's input code page and not
    #    the payload's - so an agent name or a cwd carrying one non-ASCII byte
    #    arrives mojibaked. ::new() and the type accelerators rather than
    #    New-Object, because this is the no-cmdlet fast path the header
    #    describes. lib/common.ps1's Read-LwgStdinText is the same three lines
    #    with the full reasoning; this file drains before it is dot-sourced.
    try {
        $LwgStdinReader = [IO.StreamReader]::new([Console]::OpenStandardInput(), [Text.UTF8Encoding]::new($false), $true)
        try { $LwgStdinRaw = $LwgStdinReader.ReadToEnd() } finally { $LwgStdinReader.Dispose() }
    } catch { $LwgStdinRaw = '' }

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
    #
    #    TWO FLAGS, NOT ONE. $enabled is context_injection; $ledger is
    #    failure_capture, which gates the row alone. Each span is extracted ONCE
    #    and both names read out of the same substring. Both fail OPEN.
    $enabled  = $true
    $ledger   = $true
    $escalate = $false
    $rawCfg   = ''
    try {
        if ([System.IO.File]::Exists($cfgPath)) { $rawCfg = [System.IO.File]::ReadAllText($cfgPath) }
    } catch { $rawCfg = '' }

    if (-not [string]::IsNullOrWhiteSpace($rawCfg)) {
        $modSpan = Get-LwgJsonObjectSpan -Text $rawCfg -Key 'modules'
        if ($null -ne $modSpan) {
            $modText = $rawCfg.Substring($modSpan.start, ($modSpan.end - $modSpan.start))
            $v = Get-LwgJsonBool -Text $modText -Key $LwgModuleName
            if ($null -ne $v) { $enabled = [bool]$v }
            $lv = Get-LwgJsonBool -Text $modText -Key $LwgLedgerModule
            if ($null -ne $lv) { $ledger = [bool]$lv }
        }
        # A per-repo override anywhere under `repos` means the fast scan cannot
        # answer the question - only the slug can. Escalate rather than guess.
        #
        # ASKED FOR BOTH NAMES: answering failure_capture's per-repo override
        # with the global value would write start rows in a repo whose stop rows
        # are switched off. One IndexOf over a span already extracted.
        $repoSpan = Get-LwgJsonObjectSpan -Text $rawCfg -Key 'repos'
        if ($null -ne $repoSpan) {
            $repoText = $rawCfg.Substring($repoSpan.start, ($repoSpan.end - $repoSpan.start))
            $o = Get-LwgJsonBool -Text $repoText -Key $LwgModuleName
            if ($null -ne $o) { $escalate = $true }
            $lo = Get-LwgJsonBool -Text $repoText -Key $LwgLedgerModule
            if ($null -ne $lo) { $escalate = $true }
        }

        # --- AND THE OPERATOR OVERRIDE - #11 --------------------------------
        # config.json is the SHIPPED DEFAULTS. Since 3 September 2026 the
        # configuring commands write config.override.json under the state
        # directory instead, and Get-LwgConfig - which everything else in this
        # plugin resolves through - merges it over them. UNTIL THIS BLOCK THIS
        # HOOK READ config.json ALONE, so an operator who switched
        # context_injection off got a flag that the banner, the doctor and the
        # config command's own read-back all reported as off while this hook
        # went on injecting into every dispatch. That is the silent no-op the
        # whole plugin exists to catch, and bin\lwg-config.ps1 REFUSED to write
        # this one module rather than ship it - see the refusal there, which
        # names this file.
        #
        # THE SAME TWO SCANNERS, over the second document, and no rule of their
        # own: the override's `modules` block is merged over the defaults member
        # by member, so a value found here REPLACES the one above and an absent
        # one leaves it standing - which is exactly what Get-LwgJsonBool
        # returning $null already means. lib\gate_delegate.ps1 made the same
        # decision for the same reason on the same day.
        #
        # WHAT IT COSTS. One environment read and one File.Exists on a fresh
        # install, where the file does not exist - so the fast exit is untouched
        # by anything an operator has not done. On a configured machine it is
        # one more small ReadAllText - the shipped override is tens of bytes,
        # against config.json's ~29 KB - and two more runs of the span scanner
        # over it. MEASURED, not asserted - 25 interleaved rounds against the
        # hook at c39e782 and the hook here, leg order reversed on alternate
        # iterations, one warm-up sweep discarded, the real shipped config.json
        # in every leg, and every run checked to have actually INJECTED so a
        # silent leg cannot look fast:
        #
        #     c39e782, reads config.json alone            min 384 ms  median 411 ms
        #     here, fresh install (no override file)      min 385 ms  median 440 ms
        #     here, configured (override present)         min 382 ms  median 432 ms
        #
        #     added on a fresh install    =  +1 ms
        #     added on a configured box   =  -2 ms   (negative, i.e. noise)
        #
        # Read those as "under 5 ms and inside this machine's run-to-run
        # spread", never as three significant figures: the configured leg does
        # strictly more work than the fresh one and came out marginally faster,
        # which is what noise looks like. The shape of the cost is what the
        # numbers confirm rather than establish - one env read and one failed
        # stat on a fresh install, plus one ReadAllText of a 47-byte file and
        # two span scans over it on a configured one.
        #
        # Nothing here dot-sources common.ps1 and no cmdlet is called on this
        # path; the escalation below is unchanged and still costs what it did.
        #
        # THREE THINGS SEND IT TO THE SLOW PATH INSTEAD OF ANSWERING, and each
        # of them is a place where this scanner and ConvertFrom-Json could
        # disagree:
        #
        #   * CLAUDE_PLUGIN_DATA unset. Get-LwgStateDirInfo can still DISCOVER
        #     the directory from the configuration root, and spelling that
        #     resolution a second time here is the duplication this repo has
        #     already had to fix once. Under a live hook the variable is set -
        #     it is the branch every hook takes - so this costs the fast exit
        #     only where no hook is running.
        #   * anything before the opening brace, or no brace at all. An override
        #     whose top level is not a JSON object is DISCARDED by Get-LwgConfig
        #     outright, and `[{"modules":{...}}]` would otherwise be read here
        #     as a global flag.
        #   * the two characters \u anywhere in it. \uXXXX is the only JSON
        #     escape that can spell a letter, so `"modules"` is a member
        #     ConvertFrom-Json sees and this scanner cannot. The gate carries
        #     the long version of this note.
        #
        # AND THE `repos` RULE IS THE SAME ONE AS ABOVE: a per-repo override in
        # the override document can only be resolved with the slug, which this
        # path never parses, so it escalates rather than guessing.
        #
        # ONLY WHEN config.json ITSELF CARRIED A `modules` BLOCK. Get-LwgConfig
        # merges the override over the DEFAULTS, and when those could not be
        # read there is nothing to merge onto - it discards the override too and
        # returns the built-in fallback. $modSpan is the cheap proxy for the
        # condition it uses, so the two agree about that state as well.
        if ($null -ne $modSpan) {
            if ([string]::IsNullOrWhiteSpace($env:CLAUDE_PLUGIN_DATA)) {
                $escalate = $true
            } else {
                $ovPath = [System.IO.Path]::Combine($env:CLAUDE_PLUGIN_DATA, 'config.override.json')
                $ovText = ''
                try {
                    if ([System.IO.File]::Exists($ovPath)) { $ovText = [System.IO.File]::ReadAllText($ovPath) }
                } catch { $ovText = '' }

                # An EMPTY override is not an override: Get-LwgConfig reports it
                # as such and merges nothing, so the defaults above stand.
                if (-not [string]::IsNullOrWhiteSpace($ovText)) {
                    $ovOpen = $ovText.IndexOf('{')
                    if ($ovOpen -lt 0 -or
                        $ovText.Substring(0, $ovOpen).Trim().Length -ne 0 -or
                        $ovText.IndexOf('\u', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        $escalate = $true
                    } else {
                        $ovMod = Get-LwgJsonObjectSpan -Text $ovText -Key 'modules'
                        if ($null -ne $ovMod) {
                            # BOTH names out of the ONE span, as above.
                            $ovModText = $ovText.Substring($ovMod.start, ($ovMod.end - $ovMod.start))
                            $ovVal = Get-LwgJsonBool -Text $ovModText -Key $LwgModuleName
                            if ($null -ne $ovVal) { $enabled = [bool]$ovVal }
                            $ovLedgerVal = Get-LwgJsonBool -Text $ovModText -Key $LwgLedgerModule
                            if ($null -ne $ovLedgerVal) { $ledger = [bool]$ovLedgerVal }
                        }
                        $ovRepos = Get-LwgJsonObjectSpan -Text $ovText -Key 'repos'
                        if ($null -ne $ovRepos) {
                            $ovReposText = $ovText.Substring($ovRepos.start, ($ovRepos.end - $ovRepos.start))
                            $ovRepoVal = Get-LwgJsonBool -Text $ovReposText -Key $LwgModuleName
                            if ($null -ne $ovRepoVal) { $escalate = $true }
                            $ovRepoLedgerVal = Get-LwgJsonBool -Text $ovReposText -Key $LwgLedgerModule
                            if ($null -ne $ovRepoLedgerVal) { $escalate = $true }
                        }
                    }
                }
            }
        }
    }

    # 2b. THE STATE DIRECTORY, AND IT IS NEVER GUESSED.
    #     Get-LwgStateDirInfo (common.ps1:766) returns CLAUDE_PLUGIN_DATA
    #     VERBATIM when it is set - "the branch every live hook takes" - so
    #     composing health.jsonl off it here is the same resolution, not a
    #     second one. UNSET, the answer is a RANKED DISCOVERY over the
    #     configuration root, and a cheaper spelling of that ranking here could
    #     pick a different directory and produce two health logs. So it
    #     escalates on that condition - the branch this file already had twenty
    #     lines above - and takes Get-LwgStateDir, the one resolver.
    #
    #     OUTSIDE the $modSpan test, because both flags fail open: a machine
    #     with no readable config still records dispatches.
    $LwgStateDir = $env:CLAUDE_PLUGIN_DATA
    if ([string]::IsNullOrWhiteSpace($LwgStateDir)) { $LwgStateDir = ''; $escalate = $true }

    if ($escalate) {
        # The exact answer, at full price. Reached only when an operator has
        # actually written a per-repo override for one of these two modules, or
        # when the state directory has to be discovered rather than read.
        . ([System.IO.Path]::Combine($PSScriptRoot, 'common.ps1'))
        $payload = [pscustomobject]@{}
        try {
            if (-not [string]::IsNullOrWhiteSpace($LwgStdinRaw)) {
                $p = $LwgStdinRaw | ConvertFrom-Json
                if ($p -is [System.Management.Automation.PSCustomObject]) { $payload = $p }
            }
        } catch { }
        $cfg     = Get-LwgConfig
        $repo    = Get-LwgRepo $payload
        $enabled = Test-LwgModule -Name $LwgModuleName   -Config $cfg -Repo $repo
        # BOTH flags, once the slow path is being paid for: the branch that
        # exists to be exact must not be exact about one module out of two.
        $ledger  = Test-LwgModule -Name $LwgLedgerModule -Config $cfg -Repo $repo
        if ([string]::IsNullOrWhiteSpace($LwgStateDir)) {
            try { $LwgStateDir = Get-LwgStateDir } catch { $LwgStateDir = '' }
        }
    }

    # 3. THE DISPATCH RECORD - failure_capture's start row. See the header.
    #
    #    ABOVE THIS FILE'S OWN EARLY EXIT, deliberately: the row belongs to
    #    failure_capture, and switching context_injection off must not switch
    #    off a module the operator never touched.
    #
    #    ITS OWN try, so a ledger that cannot write costs the row and never the
    #    injection below it.
    #
    #    SESSION AND AGENT ARE BOTH REQUIRED - supervisor.ps1:403 keys on
    #    agent_id and every reader filters on session, so a row carrying neither
    #    is matched by nothing. A payload that is not JSON writes nothing and
    #    still exits 0. agent_type is NOT required: a dispatch with no subagent
    #    type is still a dispatch and '' is the honest record of one.
    if ($ledger -and -not [string]::IsNullOrWhiteSpace($LwgStateDir)) {
        try {
            $sid = Get-LwgJsonStringValue -Text $LwgStdinRaw -Key 'session_id'
            $aid = Get-LwgJsonStringValue -Text $LwgStdinRaw -Key 'agent_id'
            if (-not [string]::IsNullOrWhiteSpace($sid) -and -not [string]::IsNullOrWhiteSpace($aid)) {
                $atype = Get-LwgJsonStringValue -Text $LwgStdinRaw -Key 'agent_type'
                if ($null -eq $atype) { $atype = '' }

                # The 200-character cap, AFTER decoding and BEFORE escaping - see
                # $LwgLogFieldMax above. A truncation, NOT a redaction; the header
                # states that limit rather than glossing it.
                if ($sid.Length   -gt $LwgLogFieldMax) { $sid   = $sid.Substring(0, $LwgLogFieldMax) }
                if ($aid.Length   -gt $LwgLogFieldMax) { $aid   = $aid.Substring(0, $LwgLogFieldMax) }
                if ($atype.Length -gt $LwgLogFieldMax) { $atype = $atype.Substring(0, $LwgLogFieldMax) }

                $LwgLedgerLine = '{"ts":"' + [DateTime]::UtcNow.ToString('o') +
                                 '","event":"SubagentStart","session":' + (ConvertTo-LwgJsonString -Text $sid) +
                                 ',"agent_id":' + (ConvertTo-LwgJsonString -Text $aid) +
                                 ',"agent_type":' + (ConvertTo-LwgJsonString -Text $atype) + "}`n"

                # THE APPEND, as Add-LwgLine does it at common.ps1:2111-2113.
                # Concurrent hooks race on this file BY DESIGN - AppendAllText
                # holds it FileShare.Read for the length of every append - so the
                # ladder is that function's, and a hook that threw here would be
                # a dispatch that failed over a log line.
                #
                # THE DIRECTORY IS PROBED ONLY ON FAILURE. [IO.Directory]::Exists
                # costs ~1.3 ms on its first call in a fresh process and would be
                # paid on every dispatch to guard a state no live path is in -
                # Get-LwgStateDir creates the directory and SessionStart runs
                # before any dispatch. Asking after the first exception instead
                # keeps the 300 ms ladder from being spent on a directory that
                # is not there, and costs nothing when it is.
                $LwgLedgerPath = [System.IO.Path]::Combine($LwgStateDir, $LwgLedgerLog)
                $LwgLedgerEnc  = [Text.UTF8Encoding]::new($false)
                for ($LwgTry = 0; $LwgTry -lt 5; $LwgTry++) {
                    try {
                        [System.IO.File]::AppendAllText($LwgLedgerPath, $LwgLedgerLine, $LwgLedgerEnc)
                        break
                    } catch {
                        if (-not [System.IO.Directory]::Exists($LwgStateDir)) { break }
                        [System.Threading.Thread]::Sleep(20 * ($LwgTry + 1))
                    }
                }
            }
        } catch { }
    }

    # 4. context_injection off means SILENT. No envelope, no state written -
    #    and, since 6 September 2026, no bearing on the record above, which is
    #    failure_capture's and was already written.
    if (-not $enabled) { exit 0 }

    $facts = Get-LwgWorkerFacts -Path @($factsPath, $factsLocal)
    if ([string]::IsNullOrWhiteSpace($facts)) { exit 0 }

    # 5. The envelope, hand-built. hookEventName is mandatory - the CLI rejects
    #    the whole output without it - and there is deliberately no `decision`,
    #    `continue` or `stopReason` field, so this cannot interfere with a
    #    dispatch by construction rather than by intent.
    [Console]::Out.Write('{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":' +
                         (ConvertTo-LwgJsonString -Text $facts) +
                         '},"suppressOutput":true}')

} catch {
    # Never break a dispatch. THIS log write - the ERROR record, into
    # lw-watchtower.jsonl - is still on the error path alone, and for the reason
    # it always was: it dot-sources common.ps1 and pays a ConvertTo-Json warm-up,
    # which is most of the budget this script exists to keep. The dispatch record
    # added on 6 September 2026 is a different write to a different file and buys
    # its way onto the happy path by doing neither - see THE DISPATCH RECORD in
    # the header, and note that it has its own catch and cannot arrive here.
    try {
        . ([System.IO.Path]::Combine($PSScriptRoot, 'common.ps1'))
        Write-LwgEvent -Event 'SubagentStartError' -Extra @{
            module = 'context_injection'; error = $_.Exception.Message } | Out-Null
    } catch { }
}

exit 0
