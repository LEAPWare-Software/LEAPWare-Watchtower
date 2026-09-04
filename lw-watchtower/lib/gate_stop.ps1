#requires -version 5
<#
  LW-WATCHTOWER completion_audit - a turn-end gate against asserting completion on
  the strength of a queued message. OFF by default; its switch is
  supervision.completion_audit.

  Registered in hooks/hooks.json TWICE, both deliberately WITHOUT asyncRewake:
  as a THIRD Stop entry, and as a SECOND SubagentStop entry carrying
  -HookEvent SubagentStop. Exit 2 without asyncRewake BLOCKS the turn end and
  feeds stderr back to the model, on BOTH events - verified by captured payload
  on CLI 2.1.227. That is the intent here, and it is the exact opposite of the
  supervisor's entries, whose asyncRewake turns their exit 2 into an alert.
  lib/stop_advisories.ps1's "THESE ARE ADVISORIES. THEY MUST NEVER BLOCK"
  contract is why this is a separate script rather than a sixth module in that
  one: that file promises to exit 0 on every path, and a blocking module inside
  it would falsify its header. Stop hooks run CONCURRENTLY, so the extra
  process adds (max of hooks, not sum) roughly nothing to turn-end wall time
  while stop_advisories is the slower one.

  ---------------------------------------------------------------------------
  TWO MODES, AND WHY A REGISTRATION-ONLY CHANGE WOULD HAVE BEEN WRONG
  ---------------------------------------------------------------------------
  Subagents and teammates emit SubagentStop, NOT Stop - measured in health.jsonl,
  where the SAME agent stops more than once, which makes it a PER-TURN event.
  Until 11 August 2026 this gate was registered under Stop alone, so it fired
  for no subagent and no teammate at all. Registering the file unchanged under
  SubagentStop would have been WORSE THAN THE GAP, for two measured reasons:

  1. ON SubagentStop, transcript_path IS THE PARENT'S TRANSCRIPT. The subagent's
     own is agent_transcript_path. Reading transcript_path there would audit the
     ORCHESTRATOR's turn state whenever any subagent stopped - and in a delegate
     pattern the parent's last tool being SendMessage plus a completion claim is
     the COMMON case, so it would have falsely blocked a subagent because of
     what the PARENT said.
  2. EVERY record in a real subagent transcript is isSidechain:true (measured
     118 of 118 in one live transcript). The sidechain skip below is
     unconditional in Stop mode, so pointed at agent_transcript_path with that
     skip left in place the gate would have been a SILENT NO-OP - armed,
     auditing nothing.

  So the mode changes three things and nothing else:
    * WHICH transcript is read - agent_transcript_path, and an empty value
      degrades to a silent no-op rather than falling back to the parent's;
    * the sidechain skip is LIFTED, because in a subagent transcript sidechain
      records are the ONLY records;
    * the turn boundary uses the local Get-LwgSubagentTurnStart rather than
      Get-LwgPromptText.

  WHY A LOCAL TURN-BOUNDARY TEST. Get-LwgPromptText rejects sidechain records
  for a reason specific to mission_drift: a subagent's prompts are the
  orchestrator's words, and anchoring a MISSION on them would let the plugin's
  own output feed back into its own drift assessment. That is about WHOSE WORDS
  ANCHOR A MISSION. completion_audit anchors nothing on prompt content - it
  needs only a DELIMITER for where the turn starts, so authorship is
  irrelevant. Hence the rejection is correctly dropped here and correctly KEPT
  in Stop mode, where Get-LwgPromptText is still called unchanged.

  Subagent transcripts ARE multi-turn: across 24 transcripts of one session most
  carry 2 plain-string user records, several 3, three 4. The initial brief and
  each re-wake are structurally identical to a typed operator prompt (role user,
  string content, no toolUseResult, no tool_use_id block), so the shape test
  transfers unmodified. One addition is needed: a user record whose text is
  WHOLLY a <system-reminder> wrapper is an injection, not a turn start, and one
  such record was measured in a live subagent transcript. A false reset can only
  SILENCE this gate, never fire it, so both readings are safe - the rejection is
  there for correctness, not for safety.

  MODE IS DECIDED BY EITHER SIGNAL, AND THAT ASYMMETRY IS DELIBERATE. Subagent
  mode is taken when the -HookEvent argument OR the payload's hook_event_name
  says SubagentStop. The two failure directions are not equally bad: running
  subagent mode during a Stop reads an absent agent_transcript_path and exits 0
  (fail-open, gate silent), while running Stop mode during a SubagentStop audits
  the parent and FALSELY BLOCKS. Requiring both signals to be wrong before the
  dangerous direction is reachable is the point.

  PINNED TO CLI 2.1.227. agent_transcript_path, the blocking behaviour of exit 2
  on SubagentStop, and stop_hook_active on that payload are all observed facts
  about that build, not documented contracts. RE-CHECK AFTER A CLI UPGRADE.

  ---------------------------------------------------------------------------
  THE MEASURED FAILURE THIS EXISTS FOR
  ---------------------------------------------------------------------------
  1 August 2026: the orchestrator issued SendMessage at 13:20:12.391Z and told
  the user "Added to the handoff." at 13:20:15.851Z - 3.46 seconds later, with
  NO tool call in between. The message was queued to an agent that had been
  dead for 28 minutes; the file was never touched. The assertion rested on a
  "Message queued for delivery" acknowledgement and on nothing else.

  ---------------------------------------------------------------------------
  THE RULE, exactly
  ---------------------------------------------------------------------------
  Reading the tail of this session's transcript, take the CURRENT TURN - every
  record after the last typed user prompt (Get-LwgPromptText's definition; tool
  results and sidechain records are not prompts). The turn end is REFUSED when
  ALL of these hold:

    1. the turn contains at least one tool_use, and the LAST tool_use in it is
       SendMessage - so nothing after the send could have established anything;
    2. assistant text FOLLOWS that SendMessage (same record or later);
    3. the final assistant text of the turn matches the completion-claim
       vocabulary (past-tense completion verbs - added, updated, fixed, done,
       committed, ...);
    4. and it does NOT match the hedging vocabulary (will, once, queued,
       dispatched, asked, awaiting, in progress, ...) - a reply that says the
       work was HANDED OFF is the honest sentence this gate exists to demand,
       and must never be refused.

  The refusal text tells the model what evidence would make the same claim
  honest: read the artifact the claim is about, or wait for the recipient's
  completion notification, then assert.

  IT FIRES AT MOST ONCE PER TURN END. On the continuation the payload carries
  stop_hook_active, and this script - like every Stop hook in this plugin -
  stands down on it, or a model that repeats the claim would loop forever.
  Consequence, stated plainly: this gate can force ONE round of verification;
  it cannot force honesty. A model that re-asserts the same claim without
  verifying, on the continuation, ends the turn.

  ---------------------------------------------------------------------------
  WHAT THIS IS AND IS NOT - the honest half of the design
  ---------------------------------------------------------------------------
  Detecting "asserted completion" in prose is a REGEX, and a regex over
  language is the weakest kind of rule this plugin ships. It is shipped anyway
  because the alternative - nothing - is what allowed the measured failure,
  and because the trigger is guarded by three STRUCTURAL conditions (a tool_use
  happened, it was SendMessage, it was last) that are not prose. Enumerated:

  FALSE NEGATIVES - it will stay silent when it should not:
    * a claim phrased outside the verb list ("the handoff now reflects it");
    * a claim in a turn whose last tool call is anything but SendMessage -
      including a cosmetic Read of an unrelated file after the send;
    * a hedge word anywhere in a message that also asserts completion
      ("dispatched the fix and updated the doc" is suppressed by
      "dispatched");
    * the continuation after a block (stop_hook_active), by design;
    * a claim made in an EARLIER turn and merely not repeated.
  FALSE POSITIVES - it can refuse an honest sentence:
    * completion verbs describing OLD, already-verified work in a turn that
      happens to end with a SendMessage ("I fixed X earlier; now asking the
      reviewer to look" - "asking" hedges this one, but not every phrasing);
    * quoted text - the model quoting a file that contains "added".
  A refusal costs one continuation in which the model states its evidence or
  rephrases honestly; the block text says exactly that.

  Errors ALLOW (exit 0, logged GateError): a broken audit must never pin a
  session shut, and the switch defaults OFF anyway.
#>

param(
    # 'Stop' (default, so the existing Stop registration is byte-for-byte
    # unaffected by this parameter existing) or 'SubagentStop'.
    [string]$HookEvent = 'Stop'
)

$ErrorActionPreference = 'Stop'

$payload = [pscustomobject]@{}

function Get-LwgSubagentTurnStart {
    <#
      The text of a turn-starting user record inside a SUBAGENT transcript, or
      $null for anything that is not one.

      Get-LwgPromptText's shape test with the isSidechain rejection REMOVED and
      a system-reminder rejection ADDED - see the header for why each. It is
      local to this file rather than a switch on the shared helper because
      mission_drift depends on that rejection and must not inherit this one.
    #>
    param($Record)

    try {
        if ($null -eq $Record) { return $null }
        if ([string]$Record.type -ne 'user') { return $null }
        # Present only on tool-result records, which are the other thing that
        # arrives wearing role 'user'. isSidechain is NOT tested: in a subagent
        # transcript every record carries it.
        if ($null -ne $Record.toolUseResult) { return $null }

        $c = $Record.message.content
        if ($null -eq $c) { return $null }

        $text = $null
        if ($c -is [string]) {
            $text = $c
        } else {
            $parts = @()
            foreach ($b in @($c)) {
                if ($b -is [string]) { $parts += $b; continue }
                if ($null -ne $b.tool_use_id) { return $null }
                if ([string]$b.type -eq 'text' -and $b.text) { $parts += [string]$b.text }
            }
            if ($parts.Count -eq 0) { return $null }
            $text = ($parts -join ' ')
        }
        if ($null -eq $text) { return $null }

        # A record that is WHOLLY system-reminder wrapping is an injection, not
        # a turn start. Strip every wrapper and see whether anything is left,
        # which handles several wrappers and trailing prose correctly where a
        # startswith/endswith test would not.
        $stripped = [regex]::Replace($text, '(?is)<system-reminder>.*?</system-reminder>', '')
        if ([string]::IsNullOrWhiteSpace($stripped)) { return $null }

        return $text
    } catch { }
    return $null
}

try {
    . (Join-Path $PSScriptRoot 'common.ps1')
} catch { exit 0 }

# The two vocabularies, named once. Claim group 1 is the verb the refusal
# quotes back, which is what makes the block text debuggable.
$script:LwgClaimRegex = '(?i)\b(added|updated|edited|fixed|wrote|written|rewrote|created|committed|pushed|renamed|deleted|removed|implemented|deployed|completed?|finished|handled|resolved|restored|landed|merged|saved|applied|done)\b'
$script:LwgHedgeRegex = '(?i)\b(will|going to|once|when (it|the|they)|after (it|the|they)|queued|dispatch(ed|ing)?|sent|sending|asked|asking|assigned|delegated?|delegating|working on|in progress|under\s?way|awaiting|waiting|not yet|pending|kicked off|started|spawn(ed|ing)?|hand(ed|ing) (it |this )?off|should|might|attempt)\b'

try {
    $payload = Read-LwgStdin
    if ($payload.stop_hook_active) { exit 0 }   # loop guard - one block, ever, per turn end

    $cfg  = Get-LwgConfig
    $repo = Get-LwgRepo $payload
    if (-not (Test-LwgModule -Name 'completion_audit' -Config $cfg -Repo $repo)) { exit 0 }

    # EITHER signal puts us in subagent mode; see the header for why the
    # asymmetry is deliberate rather than sloppy.
    $evtArg = ''
    try { $evtArg = [string]$HookEvent } catch { }
    $evtPay = ''
    try { $evtPay = [string]$payload.hook_event_name } catch { }
    $isSubagent = ($evtArg -eq 'SubagentStop') -or ($evtPay -eq 'SubagentStop')

    if ($isSubagent) {
        # NEVER fall back to transcript_path here: on SubagentStop that is the
        # PARENT's transcript, and auditing it would block this subagent for
        # what the orchestrator said. An absent value degrades to a silent
        # no-op, which is the only safe degradation available.
        $tp = [string]$payload.agent_transcript_path
    } else {
        $tp = [string]$payload.transcript_path
    }
    if ([string]::IsNullOrWhiteSpace($tp)) { exit 0 }

    # The tail is enough: the CURRENT turn is by definition at the end of the
    # file, and a turn bigger than this window is judged on its visible tail -
    # if the window opens mid-turn the "last user prompt" is simply not seen,
    # turn state stays open from the window's first record, and the structural
    # conditions still apply to what is there. 768 KB covers every turn
    # observed in the live logs by an order of magnitude.
    $lines = @(Get-LwgTailLines -Path $tp -Bytes 786432)
    if ($lines.Count -eq 0) { exit 0 }

    $seq          = 0
    $lastToolName = ''
    $lastToolSeq  = -1
    $lastText     = ''
    $lastTextSeq  = -1
    $parsed       = 0

    foreach ($line in $lines) {
        if ($parsed -ge 800) { break }
        if ($line.Length -gt 262144) { continue }
        # Substring-reject before the JSON engine: only user records (a prompt
        # resets the turn) and assistant records (tools and text) matter.
        $isU = ($line -like '*"type":"user"*')
        $isA = ($line -like '*"type":"assistant"*')
        if (-not ($isU -or $isA)) { continue }
        # In Stop mode a sidechain record is some other agent's turn. In
        # subagent mode it is EVERY record of the transcript we were pointed at,
        # so skipping it would audit nothing at all.
        if ((-not $isSubagent) -and ($line -like '*"isSidechain":true*')) { continue }

        $rec = $null
        try { $rec = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        if ($null -eq $rec) { continue }
        $parsed++

        if ($isU) {
            # A TYPED prompt starts a new turn; a tool result does not. Stop
            # mode keeps calling Get-LwgPromptText UNCHANGED - the Stop path is
            # the only completion gate that fires today and a regression there
            # is worse than the gap this file closes.
            $start = if ($isSubagent) { Get-LwgSubagentTurnStart -Record $rec }
                     else             { Get-LwgPromptText        -Record $rec }
            if ($null -ne $start) {
                $lastToolName = ''; $lastToolSeq = -1; $lastText = ''; $lastTextSeq = -1
            }
            continue
        }

        if ([string]$rec.type -ne 'assistant') { continue }
        $content = $null
        try { $content = $rec.message.content } catch { continue }
        if ($null -eq $content) { continue }
        foreach ($b in @($content)) {
            $seq++
            $bt = ''
            try { $bt = [string]$b.type } catch { continue }
            if ($bt -eq 'tool_use') {
                $lastToolName = [string]$b.name
                $lastToolSeq  = $seq
            } elseif ($bt -eq 'text') {
                $t = [string]$b.text
                if (-not [string]::IsNullOrWhiteSpace($t)) { $lastText = $t; $lastTextSeq = $seq }
            }
        }
    }

    # --- the four conditions, in the order the header states them -----------
    if ($lastToolSeq -lt 0)                                        { exit 0 }   # no tool ran
    if ($lastToolName -ne 'SendMessage')                           { exit 0 }   # evidence-gathering followed the send
    if ($lastTextSeq -lt $lastToolSeq)                             { exit 0 }   # nothing was asserted after it
    $m = [regex]::Match($lastText, $script:LwgClaimRegex)
    if (-not $m.Success)                                           { exit 0 }   # no completion claim
    if ([regex]::IsMatch($lastText, $script:LwgHedgeRegex))        { exit 0 }   # honestly hedged

    $verb = $m.Groups[1].Value

    $reason = @(
        "LW-WATCHTOWER completion_audit: this turn's final message asserts completed work ('$verb')"
        'but the LAST tool action of the turn was SendMessage. A queued message is not'
        'delivery, delivery is not execution, and nothing after the send could have'
        'established anything - this exact pattern once reported a file edited that was'
        'never touched, to a recipient dead for 28 minutes. Before ending the turn: VERIFY'
        'the claim (Read the file or output it is about, or wait for the recipient agent''s'
        'completion notification), then restate it on evidence - or rephrase honestly as'
        '"handed off, not yet done". This gate fires once; the continuation will not be'
        'blocked, so what you say next is on the record.'
    ) -join ' '

    try {
        Write-LwgEvent -Event 'GateDeny' -Payload $payload -Extra @{
            gate = 'completion_audit'; rule = 'claim-after-queued-send'
            mode = $(if ($isSubagent) { 'SubagentStop' } else { 'Stop' })
            verb = $verb
            text = (Get-LwgRedacted -Text $lastText -MaxLength $script:LwgLogFieldMax)
        } | Out-Null
    } catch { }

    # Both blocking channels, same rationale as the PreToolUse gates: they fail
    # open in different circumstances, and emitting both can never turn a block
    # into a pass. The Stop-hook stdout schema is {"decision":"block","reason"}.
    try {
        $env0 = [ordered]@{ decision = 'block'; reason = $reason }
        [Console]::Out.Write(($env0 | ConvertTo-Json -Depth 3 -Compress))
    } catch { }
    [Console]::Error.Write($reason)
    exit 2

} catch {
    try {
        Write-LwgEvent -Event 'GateError' -Payload $payload -Extra @{
            gate  = 'completion_audit'
            error = (Get-LwgRedacted -Text ([string]$_.Exception.Message) -MaxLength 200)
            where = 'lib/gate_stop.ps1'
        } | Out-Null
    } catch { }
    exit 0
}
