#requires -version 5
<#
  LW-WATCHTOWER SubagentStart hook - TWO modules, in one process, on purpose.

    context_injection   reads context/worker_facts.md and hands it to the worker
                        as hookSpecificOutput.additionalContext. This file's
                        original and principal job, and everything below about
                        cost was written for it.
    failure_capture     appends ONE line to health.jsonl per dispatch: the START
                        half of the dispatch record whose STOP half
                        lib/supervisor.ps1:814-819 has always written. It is an
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

  That is a deliberate, narrow duplication of Get-LwgConfig + Test-LwgModule,
  and it is bounded by the escalation rule below rather than being left free to
  drift from them.

  THE DISPATCH RECORD - AND THE ARGUMENT THIS HEADER USED TO MAKE AGAINST IT
  Until 6 September 2026 this file wrote NOTHING on its happy path, and said so
  in four places. The reasoning was sound and is not deleted: a log write here
  meant dot-sourcing lib/common.ps1 and a ConvertTo-Json warm-up per worker,
  which is most of the budget the rules above exist to keep. What changed is
  that the write does neither.

  WHAT IS WRITTEN, and it is one line:

      {"ts":"<ISO-8601 o>","event":"SubagentStart","session":"<session_id>",
       "agent_id":"...","agent_type":"..."}

  appended to health.jsonl in the state directory. That is New-Record's envelope
  (lib/supervisor.ps1:184-192) and not a new set of field names, because FOUR
  readers already parse that shape - supervisor.ps1:392, gate_send.ps1:330,
  Get-LwgHealthRecords in common.ps1, statusline/statusline.ps1:942. `ts` IS the
  dispatch time; there is deliberately no second timestamp under a second name
  in a file whose readers sort on ts.

  WHY IT IS HERE AT ALL. SubagentStart is the only event that fires when an
  agent is dispatched, and nothing recorded that fact. The STOP half has always
  been written (supervisor.ps1:814-819); the START half is what turns "an agent
  finished" into "an agent was dispatched and has not finished", which is the
  field #168's ladder, #165's cost row and #316 all need. lib/supervisor.ps1:645
  records what shipping the reader first looks like: a check read a roster file
  nothing ever wrote and reported "0 orphans" unconditionally for its entire
  life. Writer first.

  WHAT IT COSTS, and this is the whole of the argument the paragraph above used
  to make. No dot-source, no cmdlet, no JSON engine, and no second parse:

    * The flag is failure_capture, read from the `modules` span this file has
      ALREADY extracted for its own module - a second IndexOf walk over a
      substring, not a second scan of the file. The override is read from the
      $ovMod span the same way, and the `repos` spans are checked for that name
      exactly as they are for this one, so the two flags escalate under the same
      rule rather than one of them guessing.
    * The three fields come out of the stdin text the script already drained,
      through Get-LwgJsonStringValue below - the same IndexOfAny jump loop as
      the two scanners above it, at depth 1 only. stdin is still not parsed.
    * The timestamp is [DateTime]::UtcNow.ToString('o'). Get-Date is a cmdlet.
    * The append is [IO.File]::AppendAllText with a UTF8Encoding($false), which
      is what Add-LwgLine does at common.ps1:2111-2113, with that function's
      20/40/60/80/100 ms retry ladder spelled as [Threading.Thread]::Sleep -
      Start-Sleep is a cmdlet. Concurrent hooks race on this file by design and
      an append must not throw.

  MEASURED, AND THE MEASUREMENT DOES NOT SAY WHAT THE FIRST DRAFT ASSUMED.
  To this file's own standard at the override note below - interleaved rounds,
  leg order varied so no leg holds a privileged position, one warm-up sweep
  discarded, the real shipped config.json in every leg, and every run checked to
  have actually injected AND to have written or not written the row its leg
  should - plus one thing that note did not have: a NULL CONTROL leg running the
  BASELINE hook a second time, so the added cost is read against what the
  instrument reports for a difference known to be zero.

  A difference of medians could not resolve this at all. At 25 and 100 rounds
  the baseline leg's own median sat 18 ms from a second baseline leg doing
  identical work, so a 10 ms signal was inside the instrument's error. What is
  reported below is the MEDIAN OF PER-ROUND DIFFERENCES: the legs run back to
  back within a round, so machine load moves all of them together.

  96 rounds, three independent runs of the whole thing:

      B - A   the row, added cost          +20.5   +20.9   +17.0  ms
      D - A   with the flag switched off    +9.4   +11.7    +7.8  ms
      C - A   NULL CONTROL, must be ~0      +3.0    -1.5    +0.5  ms

  SO THE ROW COSTS ABOUT 19 ms PER DISPATCH, not the "a few milliseconds" this
  section was drafted to say. That is over the ~10 ms this slice was given as
  its budget, it is stated here rather than rounded, and it is what the pull
  request carries to the owner. Component profiling in a fresh PowerShell 5.1
  process accounts for roughly half of it and no more:

      [DateTime]::UtcNow.ToString('o')   first call   ~4.0 ms
      [IO.File]::AppendAllText           first call   ~1.9 ms
      [IO.Directory]::Exists             first call   ~1.3 ms
      [Text.Encoding]::UTF8.GetByteCount first call   ~1.2 ms  (the injection
                                                      below would have paid this
                                                      anyway - net zero)

  The remainder is the cost of the file being larger: a padded copy of the
  baseline carrying 400 lines of PURE COMMENT and no code at all measured about
  12 ms slower than the baseline on the same instrument. Windows PowerShell 5.1
  tokenises the whole file before it runs a statement, so prose in this file is
  not free the way prose in every other file here is. That is a fact about this
  file that was not written down anywhere before 6 September 2026, and it bounds
  how much of the reasoning above can live here rather than in docs/modules.md.

  cwd IS DELIBERATELY OMITTED, AND THAT OMISSION IS LOAD BEARING - state it,
  do not gloss it. lib/supervisor.ps1 puts every payload-derived field through
  ConvertTo-SafeField, which routes through Get-LwgRedacted and therefore
  through the REGEX ENGINE. This path cannot pay for that: see the note in
  Get-LwgWorkerFacts below - first use of the regex engine in a fresh process
  costs more than everything else this script does put together. So the row
  carries only fields that need no redaction, and cwd - the one field here
  carrying the operator name and the clone root (masking rule 15) - is not
  written at all. THE LIMIT THAT LEAVES: this row is NOT redacted. A credential
  pasted into an agent_type or a session id would reach health.jsonl unmasked.
  Every field is truncated at 200 characters, which bounds the size of that
  exposure and does not remove it. If a field is ever added here that could
  carry free text, it needs the redaction this path cannot afford, and that is
  the point at which this decision has to be re-argued rather than extended.

  AND IT IS GATED ON A MODULE THIS FILE IS NOT. failure_capture off means no
  row, and context_injection off does NOT mean no row - the write sits ABOVE
  this file's own early exit. tests/subagent_scan.ps1 carries a case for each
  of those two directions, because coupling them either way would switch off a
  module the operator never touched.

  WHAT IT COSTS THE READERS, recorded here and in docs/limitations.md rather
  than discovered: each dispatch now contributes TWO records to health.jsonl
  instead of one, so the status line's 300-record window
  (statusline/statusline.ps1:885) and Invoke-LwgRotate's 500-line carry-forward
  (common.ps1:2198) both reach HALF as far back in dispatch-heavy sessions. The
  start row is INERT - it falls through every fault arm of every reader and can
  never RAISE a count - so what is lost is depth of history, not accuracy.

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
# row is an addition to failure_capture, so it is gated on failure_capture's own
# flag and on nothing else. Spelled here once rather than at the three places
# that read it.
$LwgLedgerModule = 'failure_capture'

# The log the row goes into. health.jsonl is what lib/supervisor.ps1 writes and
# what all four readers of this record shape read; it is ALREADY rotated from
# supervisor.ps1:634, above the failure_capture gate, so the 5 MB / 500-line
# discipline covers this writer for free and nothing is wired here for it.
$LwgLedgerLog = 'health.jsonl'

# The cap every payload-derived FIELD is truncated to before it reaches a log
# record. This is lib/common.ps1:2138's $script:LwgLogFieldMax REPEATED AS A
# LITERAL, for exactly the reason statusline/statusline.ps1:873-884 repeats
# common.ps1:2132's 8192: both files are on paths that deliberately dot-source
# nothing, so the constant cannot be reached by reference. IF ONE MOVES, BOTH
# MOVE. lib/supervisor.ps1 and lib/gate_delegate.ps1 reach the same number
# through $script:LwgLogFieldMax and must keep agreeing with this line.
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
      when there is no such member, when its value is not a string, or when
      $Text is not parseable that far.

      $null is a THIRD answer, exactly as it is for Get-LwgJsonBool above:
      'absent' is not 'empty'. The one caller writes no record at all when the
      fields that identify a dispatch come back $null, because a row naming no
      session and no agent is matched by no reader.

      WHY A THIRD SCANNER RATHER THAN ConvertFrom-Json. This reads the hook
      PAYLOAD, on the fast path, where the 141-182 ms first-use cost of the JSON
      engine is the whole thing this file exists to avoid. The file already had
      an object-SPAN scanner and a BOOL scanner and no string one; this is the
      same IndexOfAny jump loop as Get-LwgJsonObjectSpan, with the same
      string-aware brace matching and the same depth rule, and it is here rather
      than in lib/common.ps1 for the reason the header gives at length.

      DEPTH 1 ONLY, and that is the same lesson Get-LwgJsonObjectSpan's docstring
      records at length: a needle search at any depth returns whatever appears
      first in document order, and a hook payload nests - background_tasks and
      tool_input are objects that can carry members of their own. A start row
      built from a nested member would name something other than the dispatch.

      DECODING IS CHECKED, NOT ASSUMED, the same way ConvertTo-LwgJsonString
      checks its Replace chain. A literal with no backslash in it IS its own
      value and is returned by one Substring; only a literal carrying an escape
      pays for the exact character loop below. The decode has to happen before
      the value is re-escaped for our own record, or \n in a payload would be
      written as \\n; and it has to happen before truncation, or a cut could
      fall inside a \uXXXX and leave a half-escape in the record.
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
    #    TWO FLAGS ARE RESOLVED HERE AND NOT ONE - see THE DISPATCH RECORD in
    #    the header. $enabled is context_injection, this file's own module;
    #    $ledger is failure_capture, which gates the row alone. Each span is
    #    extracted ONCE and both names are read out of the same substring, so
    #    the second flag costs an IndexOf walk over text already in hand rather
    #    than a second scan of the file. Both fail OPEN, for the same reason.
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
        # ASKED FOR BOTH NAMES. The row is gated on failure_capture, so a
        # per-repo override on THAT name is a question this scan cannot answer
        # either, and answering it with the global value would write start rows
        # in a repo whose stop rows are switched off. One IndexOf over a span
        # already extracted, under the rule this file already had.
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
    #     VERBATIM when it is set, and that is "the branch every live hook
    #     takes" - so composing health.jsonl off it here is not a second
    #     resolution, it is the same one, and it costs nothing.
    #
    #     WHEN IT IS UNSET the answer is a RANKED DISCOVERY over the
    #     configuration root, with a tie-break on the newest write anywhere in
    #     each candidate. Spelling a cheaper version of that ranking here could
    #     pick a DIFFERENT directory from the one every other component uses and
    #     produce two health logs, each holding half a session. So this
    #     escalates on exactly that condition - the branch this file already had
    #     twenty lines above, for the identical reason about the override file -
    #     and takes the directory from Get-LwgStateDir, the one resolver.
    #
    #     It is set OUTSIDE the $modSpan test above because the row is written
    #     whether or not config.json carried a `modules` block: both flags fail
    #     open, so a machine with no readable config still records dispatches.
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
        # BOTH flags come from the slow path once it is being paid for. Leaving
        # the ledger's flag on the fast scan's answer here would mean the one
        # branch that exists to be exact was exact about one module out of two.
        $ledger  = Test-LwgModule -Name $LwgLedgerModule -Config $cfg -Repo $repo
        if ([string]::IsNullOrWhiteSpace($LwgStateDir)) {
            try { $LwgStateDir = Get-LwgStateDir } catch { $LwgStateDir = '' }
        }
    }

    # 3. THE DISPATCH RECORD - failure_capture's start row.
    #
    #    IT IS WRITTEN ABOVE THIS FILE'S OWN EARLY EXIT, deliberately. The row
    #    belongs to failure_capture; switching context_injection off must not
    #    switch off a module the operator never touched, which is the class of
    #    quiet wrongness this plugin exists to remove.
    #
    #    IT HAS ITS OWN try. A ledger that cannot write must cost the row and
    #    never the injection below it - falling into the outer catch would turn
    #    a failed append into a worker dispatched without its facts.
    #
    #    SESSION AND AGENT ARE BOTH REQUIRED. supervisor.ps1:392 keys on
    #    agent_id and every reader of this file filters on session; a row
    #    carrying neither is matched by nothing and is pure noise in a log whose
    #    depth this record already halves. A payload that is not JSON therefore
    #    writes nothing at all, and still exits 0.
    if ($ledger -and -not [string]::IsNullOrWhiteSpace($LwgStateDir)) {
        try {
            $sid = Get-LwgJsonStringValue -Text $LwgStdinRaw -Key 'session_id'
            $aid = Get-LwgJsonStringValue -Text $LwgStdinRaw -Key 'agent_id'
            if (-not [string]::IsNullOrWhiteSpace($sid) -and -not [string]::IsNullOrWhiteSpace($aid)) {
                # agent_type is NOT required: a dispatch with no subagent type
                # is still a dispatch, and an empty string is the honest record
                # of one. Absent and empty are written identically here because
                # no reader distinguishes them.
                $atype = Get-LwgJsonStringValue -Text $LwgStdinRaw -Key 'agent_type'
                if ($null -eq $atype) { $atype = '' }

                # The 200-character cap, applied AFTER decoding and BEFORE
                # escaping - see $LwgLogFieldMax above and the note in
                # Get-LwgJsonStringValue. This is a truncation and NOT a
                # redaction: this path cannot afford the regex engine, which is
                # why the row carries no cwd and no free-text field. The header
                # states that limit rather than glossing it.
                if ($sid.Length   -gt $LwgLogFieldMax) { $sid   = $sid.Substring(0, $LwgLogFieldMax) }
                if ($aid.Length   -gt $LwgLogFieldMax) { $aid   = $aid.Substring(0, $LwgLogFieldMax) }
                if ($atype.Length -gt $LwgLogFieldMax) { $atype = $atype.Substring(0, $LwgLogFieldMax) }

                # New-Record's envelope (supervisor.ps1:184-192), hand-built.
                # [DateTime]::UtcNow rather than Get-Date, which is a cmdlet;
                # 'o' is the round-trip format every reader of ts parses and is
                # culture-invariant by definition.
                $LwgLedgerLine = '{"ts":"' + [DateTime]::UtcNow.ToString('o') +
                                 '","event":"SubagentStart","session":' + (ConvertTo-LwgJsonString -Text $sid) +
                                 ',"agent_id":' + (ConvertTo-LwgJsonString -Text $aid) +
                                 ',"agent_type":' + (ConvertTo-LwgJsonString -Text $atype) + "}`n"

                # THE APPEND, as Add-LwgLine does it at common.ps1:2111-2113 -
                # AppendAllText with a UTF8Encoding that writes no BOM, because
                # every writer and every reader of this file is UTF-8 without
                # one. The retry ladder is that function's 20/40/60/80/100 ms,
                # spelled with [Threading.Thread]::Sleep because Start-Sleep is
                # a cmdlet: concurrent hooks race on this file BY DESIGN -
                # AppendAllText holds it FileShare.Read for the length of every
                # append - and a hook that threw here would be a dispatch that
                # failed over a log line.
                #
                # The directory is probed rather than created: on every live
                # path something has already created it (Get-LwgStateDir does,
                # and SessionStart runs before any dispatch), and an append into
                # a directory that does not exist would spend the whole 300 ms
                # ladder failing.
                if ([System.IO.Directory]::Exists($LwgStateDir)) {
                    $LwgLedgerPath = [System.IO.Path]::Combine($LwgStateDir, $LwgLedgerLog)
                    $LwgLedgerEnc  = [Text.UTF8Encoding]::new($false)
                    for ($LwgTry = 0; $LwgTry -lt 5; $LwgTry++) {
                        try {
                            [System.IO.File]::AppendAllText($LwgLedgerPath, $LwgLedgerLine, $LwgLedgerEnc)
                            break
                        } catch {
                            [System.Threading.Thread]::Sleep(20 * ($LwgTry + 1))
                        }
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
