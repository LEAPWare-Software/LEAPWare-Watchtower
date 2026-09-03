#requires -version 5
<#
  LW-WATCHTOWER delegate_gate - the ONLY gate this plugin ships, and it is OFF by
  default.

  Registered in hooks/hooks.json as PreToolUse with matcher
  "Edit|Write|NotebookEdit|Bash|PowerShell":
      command: "powershell"
      args:    ["-NoProfile","-ExecutionPolicy","Bypass","-File",
                "${CLAUDE_PLUGIN_ROOT}/lib/gate_delegate.ps1"]

  PowerShell IS IN THAT MATCHER AND WAS NOT UNTIL 1 AUGUST 2026. The WHY lives
  here because hooks.json is JSON and cannot hold a comment. On Windows - the
  only platform this plugin supports - the CLI offers BOTH shell tools, and the
  matcher named one of them. With interaction.delegate ON, the main thread could
  run any command it liked by asking for the other shell, while /lw-watchtower:doctor
  printed "1 gate(s) LIVE: delegate_gate - it can refuse a tool call right now".
  Nothing in this script was wrong: it does not read tool_name to decide, so it
  would have refused that call correctly had it ever been handed it. The CLI
  never invoked it. A gate reporting healthy while doing nothing is the defect
  this plugin exists to prevent, and it was open on the shell this plugin is
  written in. tests/gate_delegate.ps1 section M is the regression case, and it
  is the only section of that suite that models the CLI's matcher selection
  rather than assuming it.

  THE MATCHER IS STILL AN ENUMERATION, and both reasons are load-bearing.
  Bounding it to the tools that can DO the work being pushed onto subagents
  keeps the unconditional cost below on a handful of calls per turn rather than
  on every Read and Grep in the session; and a matcher that also selected the
  Agent tool would refuse the dispatch this file's own deny text tells the
  operator to make, which is a session with no exit rather than an over-block.
  What an enumeration cannot cover is stated in docs/limitations.md rather than
  papered over: an mcp__* tool from a server the operator installed can write
  files and run commands, its name is not knowable from this tree, and it is
  not covered.

  WHAT IT DOES, in one sentence: when interaction.delegate is on, it refuses
  those five tools for a call that did not come from a subagent, so the chat
  session is reserved for talking to the operator and the work goes to workers.

  It has exactly one rule and no exceptions to it:

      delegate is on   AND   the payload carries no agent_id   ->  DENY
      anything else                                            ->  allow

  ---------------------------------------------------------------------------
  WHY IT TESTS agent_id AND MUST NEVER TEST agent_type
  ---------------------------------------------------------------------------
  The base hook input is

      { session_id, transcript_path, cwd, prompt_id?, permission_mode?,
        agent_id?, agent_type?, effort? }

  and both agent fields are optional on it. agent_id is populated only when the
  hook fires INSIDE a subagent, which is exactly the question this gate asks.

  agent_type is NOT that question, and reading it would invert the gate on the
  machine most likely to want it. A settings.json `agent` key names the role the
  MAIN CONVERSATION runs as - an orchestrator role, typically - so the main
  thread carries a non-empty agent_type. A gate matching on a non-empty
  agent_type would classify the main thread as a subagent and allow every single
  call it exists to refuse, while reporting itself as a live gate. That is the
  founding defect this plugin exists to catch, and it is one field name away, so
  it is written down here rather than left in a commit message.

  Nothing else about the caller is inspected. There is no allowlist, no
  "this one is safe", no exemption for any path, tool, command or file - the
  four failed fix attempts recorded in docs/gates-removed.md produced five
  bypasses between them and every one of them came from an exemption, while the
  rule that carried no exemption produced none.

  ---------------------------------------------------------------------------
  WHY IT DOES NOT READ tool_name
  ---------------------------------------------------------------------------
  Deliberately. The matcher in hooks/hooks.json is the ONE place the gated tool
  list lives. A second copy here would be a second thing to keep correct, and
  this repo has already shipped the bug where a duplicated rule drifted from its
  original. It also fixes the direction of any future mistake: widen the matcher
  and MORE is refused, which is loud and safe; a stale list in here would refuse
  LESS than the matcher declares, silently, which is a gate with a hole in it.

  ---------------------------------------------------------------------------
  HOW IT BLOCKS
  ---------------------------------------------------------------------------
  Both channels, on the same decision:

    * the reason on stderr, and exit 2. This is the load-bearing one. Only
      exit 2 blocks a PreToolUse call; exit 1 is a NON-blocking error and the
      tool runs anyway, so a gate that exits 1 has silently failed open. An
      exit code cannot be malformed, which is why it carries the weight.
    * the permissionDecision "deny" envelope on stdout, via
      Write-LwgDenyDecision. On this CLI build a nonzero exit makes stdout be
      ignored, so this is redundant here - it is emitted because the two
      channels fail open in different circumstances and emitting both can never
      turn a deny into an allow.

  A PreToolUse deny is honoured even under permissions.defaultMode
  "bypassPermissions", which is why this is a stronger layer than a deny rule
  for an operator who runs in that mode.

  ---------------------------------------------------------------------------
  WHAT FAILING SAFE MEANS HERE, PER PATH - and it is not one answer
  ---------------------------------------------------------------------------
    stdin empty, truncated or not JSON
        There is then no agent_id, so if delegate is on this DENIES. That is
        deliberate. The gate has to establish that a call came from a subagent
        before allowing it; input it could not read is not evidence of one, and
        treating unreadable input as "probably a worker" is how a gate is
        talked out of firing.

    config.json unreadable, or this script throws anywhere
        ALLOWS. The switch is off by default and a config we cannot read is no
        evidence that the operator turned it on. It is also the difference
        between a bad config being a nuisance and being a lockout: the file an
        operator needs to fix is one this gate would otherwise refuse to let
        the main thread edit.

  Those two are opposite directions on purpose. "Fail safe" is not a single
  polarity - it is "never allow a call while claiming to have checked it" and
  "never block on the strength of a switch we never actually read".

  ---------------------------------------------------------------------------
  THE OVER-BLOCKING THIS ACCEPTS, stated rather than left to be discovered
  ---------------------------------------------------------------------------
  With the gate on, /lw-watchtower:delegate off does NOT work from the main thread:
  that command runs its script through Bash, and Bash is one of the five tools
  refused. There is no exemption for it and there will not be one - an
  exemption for "the command that turns me off" is a named bypass, and a gate
  with one named bypass is a gate with an argument about which others deserve
  one. The two ways out are in the deny text itself: have a subagent run the
  command (its calls carry agent_id and are allowed), or edit
  interaction.delegate in config.json by hand outside the session.

  AND ONE MORE, WHICH TURNS ON A MATCHER RULE NOBODY HERE CAN OBSERVE. If the
  CLI matches the matcher UNANCHORED - a substring test rather than a whole-name
  one - then a tool whose NAME CONTAINS one of these five words is selected too,
  and this script, being tool-blind, would refuse it from the main thread. Names
  of the shape TodoWrite, BashOutput or KillBash are all caught that way, and
  not one of them can do the work this gate exists to push onto subagents.

  MEASURED RATHER THAN ASSUMED, 1 August 2026: over the tool surface this
  repository can actually evidence - the CLI's own tool list, its deferred-tool
  names, and the `tools:` line in agents/lw-orchestrator.md - the unanchored
  reading and the whole-name reading select THE SAME FIVE TOOLS and nothing
  else. So there is no over-block to report today. It is written down anyway,
  because that is a coincidence of the names that exist rather than a guarantee,
  and because it is NOT something adding PowerShell introduced: Write and Bash
  were already substrings of other plausible tool names before this line was
  touched. tests/gate_delegate.ps1's Test-LwgMatcherSelects is where both
  readings are spelled out, and section M asks each of its questions under
  whichever of the two makes its own answer sound under either.

  ---------------------------------------------------------------------------
  COST
  ---------------------------------------------------------------------------
  This runs before every Edit, Write, NotebookEdit, Bash and PowerShell call,
  SWITCHED ON OR OFF, because a hook registration cannot be made conditional.
  THE NUMBERS BELOW WERE NOT RE-MEASURED WHEN PowerShell JOINED THAT LIST, and
  they did not need to be: they are the per-call cost, and the fifth tool
  changes how many calls are charged, not what a call costs. Nothing in the code
  paths timed here reads tool_name before deciding. What DID change is the bill
  a session pays, by however much of its shell use goes through the second shell
  rather than the first - which is a property of the session, not a number this
  file can put in a table. Re-measured on
  one development machine when the fast path below landed. Both versions were
  timed IN THE SAME RUN, interleaved round by round against the same floor - the
  old one checked out of git into its own throwaway plugin root - because the
  earlier 253/585 pair was taken on a quieter machine and comparing across runs
  would have credited the fast path with the difference in machine load. 9 runs
  per row after a discarded warm-up round, wall clock including interpreter
  startup, `cmd` piping a payload into a fresh interpreter. Read these as ONE
  MACHINE'S MEDIANS, not as constants:

                                                  median   min-max   vs floor
      floor: `powershell -File` draining stdin     294 ms  278- 304          0
      before, switch off (shipped), main thread    652 ms  608- 719     358 ms
      AFTER,  switch off (shipped), main thread    436 ms  423- 510     142 ms
      before, switch off (shipped), subagent       630 ms  603- 717     336 ms
      AFTER,  switch off (shipped), subagent       426 ms  411- 512     132 ms
      before, switch ON, main thread (the deny)    743 ms  700- 891     449 ms
      AFTER,  switch ON, main thread (the deny)    868 ms  785-1064     574 ms

  So the operator who never arms the gate - every operator, by default - pays
  about 216 ms less per gated tool call, and this file's own work above a floor
  it does not control went from ~358 ms to ~142 ms.

  RE-MEASURED 31 JULY 2026, when the member-name matching below was fixed. Same
  method - 9 interleaved rounds after a discarded warm-up, the pre-fix file
  checked out of git into its own throwaway plugin root and timed against this
  one in the SAME run. The fix costs nothing at this resolution:

                                                  median   min-max
      floor: `powershell -File` draining stdin     299 ms  272- 385
      switch off (shipped), main thread - before   436 ms  414- 645
      switch off (shipped), main thread - AFTER    439 ms  404- 813
      switch ON, main thread (the deny) - before   856 ms  831-1131
      switch ON, main thread (the deny) - AFTER    838 ms  776-1033

  Both deltas are smaller than the spread within either row, so the table above
  stands rather than being restated. What the fix adds to the off path is one
  case-insensitive string compare per member name, one IndexOf per name for a
  backslash, and one IndexOf over the `repos` block - against a bill that is
  almost entirely interpreter startup and JIT.

  THE DENY PATH GOT SLOWER, and that is stated here rather than left out of the
  table. With the switch ON the fast path runs, fails to prove the switch off,
  and the slow path then does everything it always did - so an armed gate pays
  the fast path's ~90-125 ms on top (the two measurement runs disagreed by that
  much on this row; it is the noisiest of the seven). That is the right way
  round. The cost is charged to the operator who turned the gate on, on a call
  that is being blocked anyway, and it buys the default case a saving four
  times its size. These numbers are in docs/modules.md too rather than only
  here.

  WHERE THE REMAINING ~142 ms GOES, since the obvious next question is why a
  file read and a 524-character scan cost that much. It is not the scan: called
  three times in one process the first call took ~110 ms and the second and
  third took ~3 ms each. Almost all of it is one-time - PowerShell compiling the
  script block and the JIT reaching the .NET methods on first use - and it is
  the price of running any PowerShell at all on this path, not of anything this
  file does. Which is also why there is no point micro-tuning the scanner: the
  algorithm is already 3 ms of a 142 ms bill.

  ---------------------------------------------------------------------------
  THE FAST PATH - what it may conclude, and what it may never conclude
  ---------------------------------------------------------------------------
  The slow path below uses the shared readers - common.ps1, Read-LwgStdin,
  Get-LwgConfig - rather than the hand-rolled JSON scanning
  lib/subagent_start.ps1 uses to stay near its floor. That trade is unchanged
  and still deliberate: the scanner is a narrow duplicate of two functions, and
  a duplicate on a BLOCKING path can only fail by refusing too little.

  What changed is that the cost is no longer paid before the switch is read.
  There is now a fast path ABOVE the common.ps1 dot-source, and it is bound by
  three rules that are the whole reason it is allowed to exist:

    1. PROVE OFF, OR KEEP GOING. Its only affirmative conclusion is "the switch
       is provably off", which reaches the identical outcome the slow path
       reaches for an off switch - exit 0, silently. On ANY doubt at all - the
       file is missing, the read throws, the JSON is not a plain balanced
       object, the value is true or null or a string, a member name carries an
       escape this scanner will not decode, one wanted name appears twice, a
       per-repo block might mention this key, anything throws anywhere - it
       decides NOTHING and falls through to the slow path below, which is
       unchanged and still decides. "I could not find it" is doubt, not
       absence; see the section below that this rule was found to be violating.
    2. IT NEVER DENIES. It cannot exit 2 and it cannot write the envelope. A
       fast path that could block would be a second copy of the rule, and this
       repo has already shipped the bug where a duplicated rule drifted from
       its original.
    3. IT NEVER LOOKS AT THE CALLER. It does not read agent_id, it does not read
       agent_type, it does not read tool_name. It reads one boolean out of
       config.json and nothing else. "Allow because of who called" is not a
       conclusion available to it, so no exemption can be smuggled in here.

  Rule 1 is what makes the whole thing safe to be wrong ONLY for as long as
  every failure mode of the scanner really does land on "run the slow path".
  Read the next section before changing a line of it: the first version of this
  fast path had a failure mode that landed somewhere else, and the claim that a
  bug here "costs milliseconds, never a hole" was false for three shapes of
  config for as long as that version shipped.

  ---------------------------------------------------------------------------
  "I COULD NOT FIND IT" IS NOT "IT IS NOT THERE" - the rule this fast path got
  wrong once, written down here so it is not got wrong again
  ---------------------------------------------------------------------------
  The fast path reaches "provably off" through two findings about ABSENCE:
  there is no top-level `interaction` member, and there is no `repos` member
  that could override one. The first version drew both from a scanner that
  compared member names ORDINALLY against raw, still-escaped text - while the
  consumer those findings stand in for, Test-LwgFlag in lib/common.ps1,
  resolves the same names through PowerShell property access over the output of
  ConvertFrom-Json, which is CASE-INSENSITIVE and is handed every \uXXXX escape
  already decoded. Three shapes of config therefore read as delegate = TRUE to
  the gate's real logic and as "interaction is absent, so it is off" to the
  scanner, which exited 0 before the real logic ever ran:

      "Interaction": { "delegate": true }
      "Repos": { "<slug>": { "interaction": { "delegate": true } } }
      "\u0069nteraction": { "delegate": true }   (global AND per-repo)

  Every one of them was a silent ALLOW on a call the gate exists to refuse,
  while /lw-watchtower:doctor went on printing "1 gate(s) LIVE: delegate_gate - it
  can refuse a tool call right now", byte-identical to a gate that really was
  armed. That is a fail-open in the one file whose whole job is not to have
  one, and it happened for a single reason: a failure to FIND a member was
  allowed to be the affirmative conclusion that the member was ABSENT.

  THE RULE NOW, and it binds every line below:

      A finding about absence may be used ONLY when the scan that produced it
      abstained on everything it could not decode. Anything this scanner cannot
      resolve to a definite name is $null - I DO NOT KNOW - and $null falls
      through to the slow path. "Not found by me" is never "not there".

  Concretely, and each of these is load-bearing:

    * member names are compared OrdinalIgnoreCase. That is deliberately at
      least as permissive as the property access Test-LwgFlag performs, so the
      scanner cannot miss a member the slow path would find. A scanner that is
      STRICTER than its consumer is the whole defect.
    * a member name containing ANY backslash is undecodable to this scanner and
      the entire scan returns $null. No escape is decoded here, on purpose:
      abstaining costs a few hundred milliseconds on a config nobody writes,
      and decoding would be a second JSON reader on a blocking path - which is
      the duplicate this file already refuses to be.
    * two members whose names match the same wanted key - "interaction" and
      "Interaction" side by side - are a config this cannot claim to
      understand, not a value to pick one of, so the scan returns $null.
    * the `repos` span is never parsed into members at all, so the
      case-insensitive substring test for the word "interaction" is the only
      thing between a per-repo override and the fast exit. It is now joined by
      a test for the two characters \u anywhere in that span. \uXXXX is the
      ONLY JSON escape that can spell a letter - \" \\ \/ \b \f \n \r \t all
      decode to a quote, a backslash, a slash or a control character, none of
      which can respell a key - so it is the only way a member name in that
      block can hide from a substring test.

  None of the three costs the shipped config.json its fast exit: no member name
  in it carries a backslash, and its `repos` block holds one comment with no \u
  in it. A fresh install still takes the fast path.

  The one thing that is NOT reversible is stdin. A pipe is consumed exactly
  once, so the fast path drains it and hands the text to the slow path through
  Read-LwgStdin -Raw. That parameter exists for this and is used nowhere else.
#>

$ErrorActionPreference = 'Stop'

# ===========================================================================
# FAST PATH. Everything from here to "SLOW PATH" runs before common.ps1 is
# loaded and can only ever decide "the switch is provably off". See "THE FAST
# PATH" in the header for the three rules it is bound by.
# ===========================================================================

# stdin is drained HERE, first, and kept. A pipe is consumed exactly once, so
# the slow path cannot read it again - it is handed this text through
# Read-LwgStdin -Raw. Draining is unconditional: it happens whether or not the
# fast path reaches a conclusion, so the writer at the other end is never left
# holding an unread pipe on the strength of a decision made after it.
# lib/subagent_start.ps1 drains for the same reason and records the same note.
$LwgRawStdin = ''
try { $LwgRawStdin = [Console]::In.ReadToEnd() } catch { $LwgRawStdin = '' }

# The only characters JSON structure can hide behind. Everything between two of
# them is skipped by a native IndexOfAny rather than stepped over in PowerShell.
$LwgFastScanChars = [char[]]@('"', '{', '}', '\')

function Get-LwgFastJsonMembers {
    <#
      The TOP-LEVEL members named in $Keys of the JSON object that begins at
      $Start, as a HASHTABLE

          name -> @{ colon = <index of that member's ':'>
                     start = <index of its value's '{', or -1>
                     end   = <index just past its value's '}', or -1> }

      A hashtable, deliberately: PowerShell enumerates a returned collection but
      not a returned hashtable, and the unrolling trap has shipped three times in
      this repo already.

      start/end are filled ONLY when the member's value is an object. A member
      present with any other kind of value is in the table with start = -1, which
      is how the caller tells "repos exists and I could not read it" apart from
      "repos is absent" - two inputs that must not get the same answer.

      $null means I DO NOT KNOW, and every caller must treat it as that rather
      than as "absent". It is returned for anything that is not a plain balanced
      object: braces that do not balance, a string still open at the end, a
      trailing backslash, a backslash outside a string, a MEMBER NAME CARRYING
      ANY ESCAPE, a second member whose name matches one already in $Keys, or
      anything but whitespace after the closing brace.

      NAMES ARE MATCHED OrdinalIgnoreCase AND AN ESCAPED NAME ABSTAINS. Both
      are the fix for a shipped fail-open and both are explained at length in
      this file's header under "I COULD NOT FIND IT" IS NOT "IT IS NOT THERE".
      In one line: this scanner stands in for PowerShell property access over
      ConvertFrom-Json output, which is case-insensitive and sees decoded
      escapes, so a name this scanner declines to match must be a name that
      consumer could not have matched either - and where it cannot be sure, it
      returns $null.

      DEPTH TRACKING IS LOAD-BEARING - it is not tidiness. Without it

          {"junk":{"interaction":{"delegate":false}},"interaction":{"delegate":true}}

      reads as switched off and the gate never fires. That is a fail-open, in the
      one file whose entire job is not to have one. A string is a member NAME
      only when it closes at depth 1 and the next non-whitespace character is a
      colon; a nested one closes at depth 2 and is never seen.

      STRING AWARENESS is load-bearing for the same reason, and the reason is
      narrower than it first looks - so it is written down exactly. config.json
      is more prose than data: its $comment fields run to whole paragraphs,
      contain braces, and one of them contains the literal text
      \"delegate\": true as an example. Inside a JSON string every quote is
      ESCAPED, so a needle anchored on an unescaped quote - "delegate" followed
      by a colon - cannot match inside one at all; that much comes free. What
      does not come free is a reader that looks for the bare WORD and takes the
      next literal after the next colon, which is the shape a hand-rolled reader
      actually tends to take, and which reads that comment as the setting.
      tests/gate_delegate.ps1 case I3c is the sentinel for it: a comment saying
      the switch is off over a switch that is really on.

      The scan JUMPS between " { } and \ with String.IndexOfAny instead of
      stepping character by character: about 60 native calls over a 30 KB
      config.json rather than 30,000 PowerShell loop iterations, which is the
      difference between a few milliseconds and more than the whole saving. Same
      technique, and the same reason, as Get-LwgJsonObjectSpan in
      lib/subagent_start.ps1.
    #>
    param([string]$Text, [int]$Start, [string[]]$Keys)

    $found     = @{}
    $depth     = 0
    $inStr     = $false
    $strAt     = -1
    $pendKey   = $null      # a wanted member whose value has not begun yet
    $pendColon = -1
    $openKey   = $null      # a wanted member whose object value we are inside
    $openAt    = -1
    $len = $Text.Length
    $k   = $Start

    while ($k -ge 0 -and $k -lt $len) {
        $k = $Text.IndexOfAny($script:LwgFastScanChars, $k)
        # Out of structural characters with the object still open: unbalanced.
        if ($k -lt 0) { return $null }
        $c = $Text[$k]

        if ($inStr) {
            if ($c -eq '\') {
                # An escape consumes the next character, including a quote -
                # skip both, or \" reads as the end of the string.
                if ($k + 2 -gt $len) { return $null }   # trailing backslash
                $k += 2
                continue
            }
            if ($c -eq '"') {
                $inStr = $false
                if ($depth -eq 1) {
                    # Only a string that closes at depth 1 can be a top-level
                    # member name, and only if a colon follows it. A VALUE
                    # string also closes at depth 1 - it is followed by ',' or
                    # '}', which is exactly what this tells apart.
                    $j = $k + 1
                    while ($j -lt $len -and [char]::IsWhiteSpace($Text[$j])) { $j++ }
                    if ($j -lt $len -and $Text[$j] -eq ':') {
                        $name = $Text.Substring(($strAt + 1), ($k - $strAt - 1))
                        # RAW text, escapes and all. A name carrying one is a
                        # name this scanner cannot decode, and a name it cannot
                        # decode must not be reported as "none of $Keys" - the
                        # slow path is handed "\u0069nteraction" already
                        # decoded to `interaction` by ConvertFrom-Json. Abstain
                        # for the whole scan rather than for this member: a
                        # member skipped here would still leave the caller
                        # concluding something about what it did not see.
                        if ($name.IndexOf('\', [StringComparison]::Ordinal) -ge 0) { return $null }
                        foreach ($want in $Keys) {
                            # OrdinalIgnoreCase, NOT Ordinal. JSON member names
                            # are case-sensitive; the consumer this stands in
                            # for is not. Test-LwgFlag reads `interaction` and
                            # `delegate` through PowerShell property access,
                            # which matches "Interaction" and "DELEGATE" - so
                            # an Ordinal compare here made those spellings
                            # invisible to the scanner while the gate still saw
                            # them, and the scanner then proved the switch off
                            # while it was on.
                            if ([string]::Equals($name, $want, [StringComparison]::OrdinalIgnoreCase)) {
                                # A second member matching the same wanted name
                                # is a config this cannot claim to understand,
                                # not a value to pick one of.
                                if ($found.ContainsKey($want)) { return $null }
                                $found[$want] = @{ colon = $j; start = -1; end = -1 }
                                $pendKey   = $want
                                $pendColon = $j
                            }
                        }
                    }
                }
                $k++
                continue
            }
            # A brace inside a string is text.
            $k++
            continue
        }

        if ($c -eq '"') { $inStr = $true; $strAt = $k; $k++; continue }
        # A backslash outside a string is not JSON at all.
        if ($c -eq '\') { return $null }

        if ($c -eq '{') {
            # This brace is the value of a wanted member only if nothing but
            # whitespace stands between its colon and here. That check is what
            # keeps a stale $pendKey - a wanted member whose value turned out to
            # be a string or a number - from claiming some later object.
            if ($depth -eq 1 -and $null -ne $pendKey -and $pendColon -ge 0 -and
                $Text.Substring(($pendColon + 1), ($k - $pendColon - 1)).Trim().Length -eq 0) {
                $openKey = $pendKey
                $openAt  = $k
            }
            $pendKey = $null
            $depth++
            $k++
            continue
        }

        if ($c -eq '}') {
            $depth--
            if ($depth -lt 0) { return $null }
            if ($depth -eq 1 -and $null -ne $openKey) {
                $found[$openKey].start = $openAt
                $found[$openKey].end   = $k + 1
                $openKey = $null
            }
            if ($depth -eq 0) {
                if ($Text.Substring($k + 1).Trim().Length -ne 0) { return $null }
                return $found
            }
            $k++
            continue
        }
    }
    return $null
}

function Test-LwgFastDelegateOff {
    <#
      $true ONLY when config.json proves interaction.delegate is off and proves
      no per-repo block could turn it on. $false means "I did not establish
      that", which is not "it is on" - it is the instruction to run the slow
      path, and it is the answer to every doubt.

      THE REPOS RULE IS DELIBERATELY OVER-CONSERVATIVE, and it is what keeps
      this honest. The slow path resolves the switch through Test-LwgModule,
      which reads the global and then lets repos[slug].interaction.delegate
      override it - and the slug comes from the payload's cwd, which this fast
      path never parses. So it does not try to resolve the repo at all. Instead:

          no top-level `repos` member                -> nothing can override
          `repos` object containing NEITHER the word
          "interaction" anywhere, case-insensitively,
          NOR the two characters \u anywhere      -> nothing can override
          anything else                              -> fall through

      A substring test is the wrong instrument for reading a value and the right
      one for this question, because the only way it can be wrong is by finding
      the word in a comment and falling through - which costs a few hundred
      milliseconds and decides nothing. tests/gate_delegate.ps1 case H is the
      sentinel: a repo override that arms the gate must still DENY, and it does
      because "interaction" is in that block.

      THE \u CLAUSE IS THE FIX FOR A SHIPPED FAIL-OPEN and is not
      belt-and-braces. This span is never parsed into members, so the substring
      test is the ONLY thing between a per-repo override and the fast exit, and

          "repos": { "<slug>": { "\u0069nteraction": { "delegate": true } } }

      contains no such word while ConvertFrom-Json hands the slow path a member
      called `interaction` - so the fast path proved the switch off over a
      config that arms the gate. \uXXXX is the ONLY JSON escape that can
      spell a letter (see the header), so its two opening characters anywhere in
      this span are enough to make this abstain, and nothing in here has to
      decode anything.

      The shipped config's `repos` block holds one $comment which contains
      neither the word nor \u - its escapes are all \" - so a fresh
      install takes the fast exit. If that comment is ever reworded to mention
      interactions, or given a \u escape, this returns $false and the gate
      simply costs what it used to.
    #>

    $rootDir = $null
    if ($env:CLAUDE_PLUGIN_ROOT -and [System.IO.Directory]::Exists($env:CLAUDE_PLUGIN_ROOT)) {
        $rootDir = $env:CLAUDE_PLUGIN_ROOT
    } else {
        # Same rule as Get-LwgPluginRoot in common.ps1, written with
        # [IO.Path]/[IO.Directory] because Test-Path and Split-Path would drag
        # in a cmdlet module for two path operations - which is most of what
        # this fast path exists to avoid.
        $rootDir = [System.IO.Path]::GetDirectoryName($PSScriptRoot)
    }
    if ([string]::IsNullOrWhiteSpace($rootDir)) { return $false }

    $cfgPath = [System.IO.Path]::Combine($rootDir, 'config.json')
    if (-not [System.IO.File]::Exists($cfgPath)) { return $false }

    $text = [System.IO.File]::ReadAllText($cfgPath)
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }

    $open = $text.IndexOf('{')
    if ($open -lt 0) { return $false }
    if ($text.Substring(0, $open).Trim().Length -ne 0) { return $false }

    $root = Get-LwgFastJsonMembers -Text $text -Start $open -Keys @('interaction', 'repos')
    if ($null -eq $root) { return $false }

    # --- could a per-repo block turn it on? --------------------------------
    # The absent case - no `repos` member at all, so nothing can override - is
    # the OTHER conclusion about absence this function draws, and it rests on
    # the same property as the one below it: $root accounts for every top-level
    # member matching a wanted name, case-insensitively, or it is $null.
    if ($root.ContainsKey('repos')) {
        $rp = $root['repos']
        if ($rp.start -lt 0) { return $false }   # present, and not an object
        $reposText = $text.Substring($rp.start, ($rp.end - $rp.start))
        if ($reposText.IndexOf('interaction', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $false
        }
        # ...and the same question asked of a key this substring test cannot
        # see. Nothing in this span is parsed, so an escaped spelling of
        # `interaction` would slip past the line above; \uXXXX is the only
        # JSON escape that can spell a letter, so its presence anywhere here -
        # in a name, in a value, in a comment - means abstain. See the docstring
        # above and the header.
        if ($reposText.IndexOf('\u', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $false
        }
    }

    # --- the global ---------------------------------------------------------
    # An absent `interaction` member is the built-in default, which is off:
    # Test-LwgFlag returns the registry default, and the delegate_gate entry
    # declares that default as $false.
    #
    # THIS IS A CONCLUSION ABOUT ABSENCE, and it is only sound because the scan
    # that produced it abstained on every name it could not decode - see "I
    # COULD NOT FIND IT" IS NOT "IT IS NOT THERE" in the header. $root is either
    # a complete account of the top-level members named in $Keys or it is
    # $null; there is deliberately no third state in which a member was skipped.
    if (-not $root.ContainsKey('interaction')) { return $true }

    $ia = $root['interaction']
    if ($ia.start -lt 0) { return $false }       # present, and not an object

    $span   = $text.Substring($ia.start, ($ia.end - $ia.start))
    $inside = Get-LwgFastJsonMembers -Text $span -Start 0 -Keys @('delegate')
    if ($null -eq $inside) { return $false }
    # An `interaction` block with no `delegate` in it is NOT read as "off" -
    # this one absence is already answered with doubt, and stays that way. An
    # absent member here means the global default applies, which is off, but
    # establishing that would need this scanner to be sure the block holds no
    # spelling of the key it missed, and it is cheaper to fall through.
    if (-not $inside.ContainsKey('delegate')) { return $false }

    # 16 characters is more than enough to see past any whitespace to the
    # literal. TrimStart leaves a STRING value's opening quote in front, so
    # "delegate": "true" and "delegate": "false" match neither literal and both
    # fall through - which is now also what the slow path concludes about them,
    # since Test-LwgFlag stopped coercing a non-boolean value (see M5 there).
    # Ordinal on the literal, deliberately: `false` is the only spelling JSON
    # has, and `False` is not a config this may claim to have understood.
    $colon = $inside['delegate'].colon
    $tail  = $span.Substring(($colon + 1), [Math]::Min(16, ($span.Length - $colon - 1))).TrimStart()
    if ($tail.StartsWith('false', [StringComparison]::Ordinal)) { return $true }
    return $false
}

# The only affirmative outcome, and it is byte-identical to what the slow path
# does with an off switch: exit 0, in silence. Anything thrown anywhere inside
# is swallowed - not logged, because the logger has not been loaded yet, and
# because the consequence of swallowing it is that the slow path runs and logs
# whatever it finds.
try {
    if (Test-LwgFastDelegateOff) { exit 0 }
} catch { }

# ===========================================================================
# SLOW PATH. Unchanged, and it still decides everything the fast path did not.
# ===========================================================================

# Declared before the try so the catch can still log against it.
$payload = [pscustomobject]@{}

try {
    . (Join-Path $PSScriptRoot 'common.ps1')
} catch {
    # Without the shared readers this script cannot read the switch, and a gate
    # that cannot read its own switch must not act on a guess. Allow, silently:
    # there is no logger either, since that is what failed to load.
    exit 0
}

try {
    # -Raw, not a second read: the fast path above already drained the pipe and
    # a pipe is consumed exactly once. Passing '' when the drain failed is the
    # same input the old unconditional read produced in that case.
    $payload = Read-LwgStdin -Raw $LwgRawStdin
    $cfg     = Get-LwgConfig
    $repo    = Get-LwgRepo $payload

    # --- the switch --------------------------------------------------------
    # interaction.delegate, global then per-repo, default OFF. Resolved through
    # Test-LwgModule so that this gate and /lw-watchtower:doctor cannot disagree about
    # whether it is live: the registry entry names the key, and both go through
    # the same function to read it.
    if (-not (Test-LwgModule -Name 'delegate_gate' -Config $cfg -Repo $repo)) { exit 0 }

    # --- the one rule ------------------------------------------------------
    # PRESENCE of agent_id, and nothing else. See the header for why agent_type
    # is not consulted and must not be.
    $agentId = ''
    try { $agentId = [string]$payload.agent_id } catch { $agentId = '' }
    if (-not [string]::IsNullOrWhiteSpace($agentId)) { exit 0 }

    # --- deny ---------------------------------------------------------------
    $toolName = ''
    try { $toolName = [string]$payload.tool_name } catch { $toolName = '' }
    if ([string]::IsNullOrWhiteSpace($toolName)) { $toolName = 'this tool' }

    $reason = @(
        "LW-WATCHTOWER delegate_gate: $toolName was called from the main conversation, and"
        'delegate-only mode is ON (interaction.delegate in config.json). The chat session is'
        'reserved for talking to the operator; the work goes to subagents.'
        ''
        'Dispatch a subagent with the Agent tool and have IT make this call. A worker cannot'
        'see this conversation, so restate the context, the absolute paths, the definition of'
        'done and the prohibitions in the dispatch.'
        ''
        'To turn this off: have a subagent run /lw-watchtower:delegate off, or edit'
        'interaction.delegate to false in config.json by hand. It cannot be turned off from'
        'the main thread, because that command runs through Bash and Bash is refused here.'
        'There is deliberately no exemption for it.'
    ) -join ' '

    # Logged before either channel is written, so a denial is on record even if
    # the envelope or the exit path is what goes wrong. No tool_input is
    # recorded: this gate does not need the payload to make its decision, so
    # copying it into the log would move data for nothing.
    try {
        Write-LwgEvent -Event 'GateDeny' -Payload $payload -Extra @{
            gate = 'delegate_gate'; tool = $toolName; rule = 'main-thread-mutation'
        } | Out-Null
    } catch { }

    # Channel 2 (redundant on this build - see the header and
    # Write-LwgDenyDecision). Written first because exit ends the process.
    try { Write-LwgDenyDecision -Reason $reason | Out-Null } catch { }

    # Channel 1, load-bearing. stderr, then exit 2. NOT exit 1: exit 1 is a
    # non-blocking error and the tool call proceeds.
    [Console]::Error.Write($reason)
    exit 2

} catch {
    # Anything unexpected ALLOWS - see "what failing safe means here". The one
    # thing that must not happen is a silent failure, so it is logged.
    try {
        Write-LwgEvent -Event 'GateError' -Payload $payload -Extra @{
            gate  = 'delegate_gate'
            error = (Get-LwgRedacted -Text ([string]$_.Exception.Message) -MaxLength 200)
            where = 'lib/gate_delegate.ps1'
        } | Out-Null
    } catch { }
    exit 0
}
