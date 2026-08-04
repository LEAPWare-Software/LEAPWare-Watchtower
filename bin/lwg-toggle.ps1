#requires -version 5
<#
  LW-WATCHTOWER preference settings - verbosity, plain, delegate.

      powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-toggle.ps1 -Flag verbosity
      powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-toggle.ps1 -Flag verbosity brief
      powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-toggle.ps1 -Flag delegate on -Scope repo

  Backs /lw-watchtower:verbosity, :plain and :delegate. The three commands share ONE
  script on purpose. They differ only in which key they write and in which
  sentence they print about enforcement; three copies of the
  read/validate/write/report path would be three things to keep correct, and
  this repo has already shipped the bug where a second copy of a rule drifted
  from the first (see Get-LwgSessionMode in lib/common.ps1, which was lifted
  out of session_start.ps1 for exactly that reason). The per-flag facts live in
  $script:LwgFlags below and nowhere else.

  IT WAS FIVE FLAGS UNTIL 30 JULY 2026. `ask` and `ask-inline` were removed
  that day by an explicit owner decision, along with commands/ask.md,
  commands/ask-inline.md and the interaction.ask / interaction.ask_inline keys.
  Both had been ON by default since they shipped while enforcing nothing, and
  neither can be built: a Stop hook can refuse to end a turn but cannot stop
  prose that has already appeared and cannot detect a question that should have
  been asked and was not, and nothing can merge questions after they have been
  asked. Those two names are written here WITHOUT a leading slash, for the same
  reason the dead verbosity names below are - see the paragraph on
  bin\lwg-doctor.ps1.

  TWO AXES, AND THEY ARE DIFFERENT SHAPES. `plain` and `delegate` are booleans
  and take `on` or `off`. `verbosity` is a LEVEL and takes one of `brief`,
  `default` or `verbose` by name, because the key it writes -
  output_style.verbosity - holds exactly one of those three.

  VERBOSITY WAS TWO COMMANDS AND IS NOW ONE. lw-watchtower:brief and lw-watchtower:verbose
  both wrote this single key, so `on` claimed it and `off` released it back to
  `default` only when the command being turned off was the one holding it -
  which meant `brief off` while the key read `verbose` wrote nothing at all,
  correctly and confusingly. Two switches over one three-value setting is a
  surface that describes a model which is not there. The level is now set by
  name, and the name is the value written.

  Those two dead names are written WITHOUT their leading slash here and
  everywhere else in this file, and in what it prints. bin\lwg-doctor.ps1 scans
  this repo for /<plugin>:<name> and fails on one with no commands\<name>.md
  behind it - which is the right rule, because a live-looking reference to a
  command that no longer exists is a signpost to nothing.

  It is still ONE key rather than two booleans, and that part was never about
  taste: a per-repo override is merged KEY BY KEY, so `brief` could have been
  true globally while `verbose` was true for one repo, and no write-time rule
  inside this script could have prevented it. Exclusivity enforced at write time
  is a rule that holds only where the writer runs; one key holding one value
  cannot contradict itself at any scope, under any hand edit, in any merge.

  A value that key cannot hold is NAMED as unrecognised rather than coerced, and
  so is the dead `output_style.brief` boolean `verbosity` replaced. Both are
  reported and neither is rewritten: this script does not delete or migrate a key
  during what the operator asked to be a read. A stale key nobody mentions is a
  preference that stops working in silence, which is the one failure a switch
  that reports its own state has no excuse for.

  Exit codes - a caller reads these and nothing else:

      0  the state was reported, or the state was changed and reported
      2  the argument was not one this flag accepts - `on`/`off` for a boolean,
         a level name for `verbosity` - or the scope could not be used.
         Nothing was written. Usage was printed.
      3  the toggle could not complete - config.json could not be read, could
         not be written, would not have parsed afterwards, or was refused
         because it is not the file this command read. Nothing was written;
         whatever is printed above is a fragment, not a result.

  2 is separate from 3 deliberately: "you asked for something I do not accept"
  and "I could not do the thing you asked" are different statements, and a
  caller that collapses them cannot tell a typo from a broken config.

  EXIT 3 MEANS THE BYTES ARE AS THEY WERE, on every path this file reaches
  deterministically, and until 3 August 2026 that was false on two of them.
  commands\delegate.md, commands\plain.md and commands\verbosity.md all state it
  as well, so it is a claim made in four places about a file on disk.

  The first false path: a config.json that is valid JSON but carries no
  top-level `modules` block made Get-LwgConfig fall back to the built-in
  defaults (lib\common.ps1:452), so the value written here read back as the
  default, the read-back check threw, and this script wrote the file and THEN
  exited 3. Three things now hold that invariant up, in this order:

    1. a write is REFUSED outright when Get-LwgConfig is on built-in defaults -
       the same refusal bin\lwg-config.ps1:262-269 already makes, for the same
       reason, in nearly the same words. Nothing is written and the message
       names which of the two states the file is in: it does not parse, or it
       parses and has no `modules` block.
    2. the edited TEXT is resolved through this file's own accessors BEFORE the
       write, so an edit that would not read back is refused with the file
       untouched rather than discovered afterwards.
    3. the write goes through Save-LwgTextFile, so a copy of the file as it was
       exists before anything is replaced, and its path is printed.

  The second false path, found by review on 3 August 2026 and NOT introduced by
  the three fixes above - `-Flag plain on` with USERPROFILE unset wrote the file
  and exited 3 at fd8d023 and at 19bb85d as well. The write was fine; the REPORT
  after it threw, because the ACTIVATION block builds a settings path out of an
  environment variable this plugin does not own, and every throw in this file
  lands in one handler that exits 3. The handler now asks whether the write
  completed and was verified first, and exits 0 when it did, naming the
  reporting fault. See the catch at the bottom.

  THE ONE STATE STILL NOT COVERED, named rather than left to be discovered: if
  something else writes config.json AFTER this command's write and BEFORE its
  read-back, the read-back can disagree on a file that WAS changed, and the exit
  is 3. It is not put back automatically - restoring over another writer's file
  is the lost update the SHA check exists to prevent - and the message says
  which of the two states the file is in and where the backup is. Nothing
  deterministic reaches that state and no case in tests\toggle_behaviour.ps1
  constructs one. It is the only path on which exit 3 and "the bytes are as they
  were" can still disagree, and the three commands\*.md exit-code lines describe
  it not at all.

  A READ IS NOT A WRITE. Running with no argument on a broken config.json still
  reports, and still says the state shown is the built-in fallback - refusing to
  answer "what is this set to" would be a worse answer than the fallback.

  THE WRITE ITSELF GOES THROUGH bin\lwg-cmdlib.ps1, which this file dot-sources
  for Read-LwgTextFile and Save-LwgTextFile and nothing else. It was a bare
  [IO.File]::WriteAllText until 3 August 2026: no backup, no check that the file
  on disk was still the one that had been read, and a hardcoded no-BOM encoding
  that silently stripped a byte-order mark another tool had written. The four
  lifecycle commands had all three; this one edits the same file and did not.
  Dot-sourcing cmdlib here does not violate its quarantine rule
  (bin\lwg-cmdlib.ps1:8-21): nothing on a hook path may reach a process spawner,
  and this file is a bin\ command an operator typed.

  A PARSER MESSAGE IS NEVER INTERPOLATED WHOLE. Windows PowerShell 5.1's
  ConvertFrom-Json embeds its entire input in its error text - measured at 33,228
  characters for a 33,175-byte config.json - so every parser message that reaches
  the operator here goes through Get-LwgBriefParseError first.

  WHAT THIS SCRIPT DOES NOT DO, and says so on every run:

  * It does NOT activate an output style. The three verbosity levels and
    `plain` are delivered by the files in output-styles/, and the style Claude
    Code actually applies is the `outputStyle` key in a settings file. This script
    does not write that key - see the ACTIVATION block it prints - because a
    settings file is not part of this plugin and writing one behind the CLI's
    back would be a second source of truth for a value the /config picker
    already owns correctly.
  * `delegate` is the ONE flag here that is enforced, and it prints an ENFORCED
    block rather than a NOT WIRED one. Since 30 July 2026 interaction.delegate
    is the switch on delegate_gate - lib/gate_delegate.ps1, a PreToolUse hook
    that refuses Edit, Write, NotebookEdit, Bash and PowerShell for calls that
    did not come from a subagent. Turning it on from here really does block. Turning it OFF
    again from here does not work, because this command runs through Bash; the
    ENFORCED block says so, and says what to do instead.

  Both of those are printed by the script rather than left to the command
  prose, because a switch that reports itself as wired when it is not - or as
  unwired when it is - is the exact defect this plugin exists to catch.

  WHY NOT $LwgModuleRegistry, AND THE ONE EXCEPTION. `verbosity` and `plain` are
  deliberately absent from the module registry and from config.json's `modules`
  block and must stay absent. Get-LwgConfig fails OPEN - a corrupt or unreadable
  config turns every module ON - which is the right polarity for a guardrail and
  the wrong one for a preference: it would silently switch verbosity to `brief`
  and rewrite every answer. And the banner's n/10 counts governance coverage; an
  answer-formatting preference is not governance. So they live in their own
  `output_style` block, read with a Get-LwgModuleOption-shaped accessor that
  returns the built-in default when the key is absent.

  `delegate` is different and is IN the registry, as delegate_gate. It is
  governance - it is the only gate - so it belongs in the count. What stayed
  out is its FLAG: the registry entry declares `switch = interaction.delegate`
  rather than taking a `modules` key, because two switches over one gate lets an
  operator turn it on here and have it silently do nothing. The key is still
  read through the same accessor shape, so an unreadable config leaves the gate
  off rather than switching a blocking hook on by accident.
#>

[CmdletBinding()]
param(
    # Which preference. Not free text - an unknown name is a binding error
    # before any config is read, so a typo can never write a key nothing reads.
    [Parameter(Mandatory = $true)]
    [ValidateSet('verbosity', 'plain', 'delegate')]
    [string]$Flag,

    # For a boolean flag: `on`, `off`, or nothing at all to report the current
    # state. For `verbosity`: `brief`, `default`, `verbose`, or nothing at all.
    # Deliberately NOT a ValidateSet: what is accepted depends on the flag, and
    # a rejected value must print this script's own usage text and exit 2, not
    # a PowerShell binding exception.
    [Parameter(Position = 0)]
    [AllowEmptyString()][AllowNull()]
    [string]$Value,

    # `global` writes the default for every repo; `repo` writes an override
    # under repos['owner/name'] that applies here and nowhere else.
    [ValidateSet('global', 'repo')]
    [string]$Scope = 'global',

    # Point at a copy instead of the live config - used by the tests, and the
    # only way to exercise the write path without changing this machine. Same
    # parameter, same wording and same purpose as bin\lwg-config.ps1:66-67;
    # tests\toggle_behaviour.ps1 drives a copied tree rather than this seam for
    # its regression cases, because a copied tree also runs against the commit
    # the defects were filed against.
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

# --- what the handler at the bottom is allowed to say about the file --------
# Set on the write path, read by the catch-all. They are script-scoped rather
# than local because the handler runs outside the scope that sets them, and a
# handler that cannot tell "written" from "not written" can only guess - which
# is how a documented "nothing was written" exit 3 came to be printed over a
# file that had just been rewritten.
$script:LwgWrote    = $false   # Save-LwgTextFile completed
$script:LwgVerified = $false   # ...and the file on disk reads back as asked
$script:LwgBackup   = ''       # the copy taken before that write

# Everything printed below is ASCII. These commands are the ones an operator
# reaches for when the session is already behaving oddly.

# --- the per-flag facts, in one place -------------------------------------
# block/key   where the value lives in config.json. `key` is underscored even
#             where the command name is hyphenated: `$cfg.interaction.ask-inline`
#             is a subtraction in PowerShell, and a config key you cannot read
#             with ordinary property access is a trap for the next reader.
# axis        'bool' - the key is this flag's own true/false and the argument
#             is `on` or `off`.
#             'level' - the key holds one of `levels` by name and the argument
#             IS that name. There is no on/off for a level: the three values
#             are mutually exclusive by construction, which is the whole reason
#             this is one key rather than two booleans. See the header.
# levels      'level' axis only. The accepted names, in the order the usage
#             text prints them, each with the sentence the report shows beside
#             it. The keys here and $script:LwgVerbosityValues are the same
#             three names; the list below is checked against it at load.
# default     the value when the key is absent. The verbosity axis defaults to
#             `default` - the level at which it does nothing - and `plain` and
#             `delegate` default OFF, because their on state changes behaviour
#             the operator did not ask for. For `delegate` that is stronger than
#             a preference: it arms the only gate this plugin ships, and a
#             blocking gate switched on by default is the opposite of what this
#             plugin argues for. Its default is stated TWICE - here, and on the
#             registry entry's `switch` field in lib/common.ps1, which is what
#             the gate itself reads. They must agree; tests/gate_delegate.ps1
#             asserts the shipped config leaves the gate off.
# wired       for a flag that IS enforced: what it blocks and what that costs.
# notWired    for a flag that is not: why the switch is a request, not a
#             control. A flag carries one or the other, never both.
$script:LwgFlags = @{
    'verbosity' = @{
        block   = 'output_style'; key = 'verbosity'; kind = 'style'
        axis    = 'level'; default = 'default'
        summary = 'how much an answer carries - one key, one of three levels, never two at once'
        levels  = [ordered]@{
            'brief'   = 'terse answers - a 150-word ceiling on prose, first sentence answers the question'
            'default' = 'neither ceiling nor expansion - the built-in voice, and this axis switched off'
            'verbose' = 'expansive answers - reasoning, rejected alternatives and evidence shown in full'
        }
    }
    'plain' = @{
        block   = 'output_style'; key = 'plain'; default = $false; kind = 'style'
        axis    = 'bool'
        summary = 'plain English - no unexplained tooling jargon, acronyms expanded on first use'
    }
    'delegate' = @{
        block   = 'interaction'; key = 'delegate'; default = $false; kind = 'interaction'; axis = 'bool'
        summary = 'reserve the chat session for operator communication - all work goes to subagents'
        onText  = 'Do the work in subagents. The chat session is for talking to the operator: dispatch with the Agent tool and report back, rather than editing, running or building on the main thread. A worker cannot see this conversation, so every dispatch must restate the context, the absolute paths, the definition of done and the prohibitions.'
        offText = 'Work may be done directly on the main thread.'
        # Not `notWired` - this is the one switch in this file that IS wired, and
        # the block is named for what it now has to say instead: what the gate
        # refuses, and what refusing it costs. See the header.
        wired = @(
            'delegate IS enforced, and it is the only thing in this plugin that is. Turning it on'
            'arms delegate_gate - lib/gate_delegate.ps1, a PreToolUse hook on'
            'Edit|Write|NotebookEdit|Bash|PowerShell - which REFUSES those five tools for any call that did'
            'not come from a subagent. The refusal is a real block: PreToolUse deny is honoured'
            'even under permissions.defaultMode "bypassPermissions". A subagent is identified by'
            'the presence of agent_id in the hook payload, never by agent_type, because a'
            'settings.json `agent` key gives the MAIN thread a non-empty agent_type.'
            ''
            'WHAT TURNING IT ON COSTS, and it is not reversible from here: with the gate armed,'
            '/lw-watchtower:delegate off will NOT work from the main thread. This command runs through'
            'Bash, and Bash is one of the five tools refused - so is PowerShell, so switching shell'
            'is not a way round it either. There is deliberately no exemption'
            'for it - an exemption for "the command that turns me off" is a named bypass. The two'
            'ways back are to have a SUBAGENT run /lw-watchtower:delegate off, or to set'
            'interaction.delegate to false in config.json by hand.'
            ''
            'What it still does NOT do: it does not check that a dispatch was any good, and it'
            'refuses nothing a subagent does. Delegation is enforced; delegating well is not.'
        )
    }
}

# --- a JSON text editor, not a JSON round-trip -----------------------------
# config.json is edited SURGICALLY: the file's bytes are preserved except for
# the one value being changed, or the one member being inserted.
#
# The obvious alternative - ConvertFrom-Json, poke the object, ConvertTo-Json -
# is unusable here, and quietly so. PowerShell 5.1's serialiser escapes an
# apostrophe to the six characters backslash-u-0027 and an angle bracket to
# backslash-u-003c, and this config.json is roughly 60 % explanatory prose in
# its "$comment" keys, full of both - 126 apostrophes at the time of writing.
# A single toggle would have rewritten every comment in the file into escape
# sequences and produced a whole-file diff for a one-word change. It also
# reformats everything it touches, which would put the operator's own layout at
# the mercy of a preference command.
#
# So the helpers below walk the text. They are string-aware (a brace inside a
# quoted comment is not a brace) and escape-aware (a backslash-escaped quote
# does not end a string). They do NOT validate JSON. Instead the caller parses
# the RESULT with ConvertFrom-Json and only then writes the file, so a bad edit
# leaves config.json untouched rather than needing to be undone. That matters
# more here than anywhere else in this repo: Get-LwgConfig fails OPEN, so a
# config.json this command corrupted would switch every module on.

function Get-JsonWsEnd {
    <# First index at or after $i that is not JSON whitespace. #>
    param([string]$s, [int]$i)
    while ($i -lt $s.Length) {
        $c = $s[$i]
        if ($c -ne ' ' -and $c -ne "`t" -and $c -ne "`n" -and $c -ne "`r") { break }
        $i++
    }
    return $i
}

function Get-JsonStringEnd {
    <#
      $i is the index of an opening quote. Returns the index just AFTER the
      closing quote, or -1 if the string is unterminated. A backslash escapes
      the next character, so \" is consumed rather than treated as the end.
    #>
    param([string]$s, [int]$i)
    $i++
    while ($i -lt $s.Length) {
        $c = $s[$i]
        if ($c -eq '\') { $i += 2; continue }
        if ($c -eq '"') { return $i + 1 }
        $i++
    }
    return -1
}

function Get-JsonValueEnd {
    <#
      $i is the index of the first character of a value. Returns the index just
      after it, or -1 when the value never closes.

      For an object or an array this counts only the matching bracket kind and
      skips quoted strings wholesale, which is what makes a `{` inside a comment
      harmless. For a bare token - a number, true, false, null - the value ends
      at the first comma, closing bracket or whitespace.
    #>
    param([string]$s, [int]$i)
    if ($i -lt 0 -or $i -ge $s.Length) { return -1 }
    $c = $s[$i]
    if ($c -eq '"') { return (Get-JsonStringEnd -s $s -i $i) }
    if ($c -eq '{' -or $c -eq '[') {
        $open  = $c
        $close = if ($c -eq '{') { '}' } else { ']' }
        $depth = 0
        while ($i -lt $s.Length) {
            $ch = $s[$i]
            if ($ch -eq '"') {
                $i = Get-JsonStringEnd -s $s -i $i
                if ($i -lt 0) { return -1 }
                continue
            }
            if     ($ch -eq $open)  { $depth++ }
            elseif ($ch -eq $close) { $depth--; if ($depth -eq 0) { return $i + 1 } }
            $i++
        }
        return -1
    }
    while ($i -lt $s.Length) {
        $ch = $s[$i]
        if ($ch -eq ',' -or $ch -eq '}' -or $ch -eq ']' -or
            $ch -eq ' ' -or $ch -eq "`t" -or $ch -eq "`n" -or $ch -eq "`r") { break }
        $i++
    }
    return $i
}

function Find-JsonMember {
    <#
      Find a member of the object whose opening brace is at $objStart. Returns

          @{ keyStart; keyEnd; valStart; valEnd }

      or $null when the object has no such member. Only that object's OWN
      members are considered - a nested object is skipped whole, so `"verbosity"`
      inside `repos` is never mistaken for `"verbosity"` at the top level.

      A hashtable, deliberately: PowerShell enumerates a returned collection but
      NOT a returned hashtable. Names are compared with -eq, which is
      case-insensitive for strings, matching how config.json says its `repos`
      keys are matched.
    #>
    param([string]$s, [int]$objStart, [string]$key)

    $i = $objStart + 1
    while ($true) {
        $i = Get-JsonWsEnd -s $s -i $i
        if ($i -ge $s.Length) { return $null }
        $c = $s[$i]
        if ($c -eq '}') { return $null }
        if ($c -eq ',') { $i++; continue }
        if ($c -ne '"') { return $null }

        $ks = $i
        $ke = Get-JsonStringEnd -s $s -i $i
        if ($ke -lt 0) { return $null }
        $name = $s.Substring($ks + 1, $ke - $ks - 2)

        $i = Get-JsonWsEnd -s $s -i $ke
        if ($i -ge $s.Length -or $s[$i] -ne ':') { return $null }
        $i = Get-JsonWsEnd -s $s -i ($i + 1)

        $vs = $i
        $ve = Get-JsonValueEnd -s $s -i $i
        if ($ve -lt 0) { return $null }
        if ($name -eq $key) {
            return @{ keyStart = $ks; keyEnd = $ke; valStart = $vs; valEnd = $ve }
        }
        $i = $ve
    }
}

function Get-JsonLineIndent {
    <# The leading spaces of the line that $idx sits on. #>
    param([string]$s, [int]$idx)
    if ($idx -le 0) { return '' }
    $nl = $s.LastIndexOf([char]10, [Math]::Min($idx, $s.Length - 1))
    $start = if ($nl -lt 0) { 0 } else { $nl + 1 }
    $n = 0
    while (($start + $n) -lt $s.Length -and $s[$start + $n] -eq ' ') { $n++ }
    return (' ' * $n)
}

function New-JsonNestedMember {
    <#
      Build the literal text for a member that does not exist yet, nesting one
      object per remaining path segment:

          @('interaction','ask'), 'true'  ->  "interaction": {
                                                "ask": true
                                              }
    #>
    param([string[]]$Path, [string]$Leaf, [string]$Indent, [string]$NewLine)

    if ($Path.Count -eq 1) { return '"' + $Path[0] + '": ' + $Leaf }
    $child = $Indent + '  '
    $inner = New-JsonNestedMember -Path @($Path[1..($Path.Count - 1)]) -Leaf $Leaf -Indent $child -NewLine $NewLine
    return '"' + $Path[0] + '": {' + $NewLine + $child + $inner + $NewLine + $Indent + '}'
}

function Set-JsonLiteralAtPath {
    <#
      Return $Raw with the value at $Path replaced by the JSON literal $Leaf -
      `true`, `false`, or a quoted string such as `"brief"`. Existing members
      are overwritten in place; missing ones are inserted as the first member of
      the deepest object that does exist, creating any intermediate objects on
      the way. Throws when the path runs into a member that is not an object -
      better a loud failure than a silent write into the wrong shape.

      $Leaf is a literal rather than a typed value because this file writes two
      kinds - the booleans of `plain`, `ask`, `ask_inline` and `delegate`, and
      the three-value string of `verbosity`. The caller builds the literal; the
      only strings this script ever passes are the three names in
      $script:LwgVerbosityValues, so no escaping is needed and none is done.
    #>
    param([string]$Raw, [string[]]$Path, [string]$Leaf)

    $nl = if ($Raw.Contains("`r`n")) { "`r`n" } else { "`n" }

    $root = $Raw.IndexOf('{')
    if ($root -lt 0) { throw 'no root object' }

    $objStart = $root
    $depth    = 0
    while ($depth -lt $Path.Count) {
        $m = Find-JsonMember -s $Raw -objStart $objStart -key $Path[$depth]
        if ($null -eq $m) { break }
        if ($depth -eq ($Path.Count - 1)) {
            return $Raw.Substring(0, $m.valStart) + $Leaf + $Raw.Substring($m.valEnd)
        }
        if ($Raw[$m.valStart] -ne '{') { throw "`"$($Path[$depth])`" is not an object" }
        $objStart = $m.valStart
        $depth++
    }

    $remaining = @($Path[$depth..($Path.Count - 1)])
    $outer  = Get-JsonLineIndent -s $Raw -idx $objStart
    $indent = $outer + '  '
    $lit    = New-JsonNestedMember -Path $remaining -Leaf $Leaf -Indent $indent -NewLine $nl

    # An empty object has no member to put a comma before, and its closing brace
    # has to move to its own line.
    $after = Get-JsonWsEnd -s $Raw -i ($objStart + 1)
    if ($after -lt $Raw.Length -and $Raw[$after] -eq '}') {
        return $Raw.Substring(0, $objStart + 1) + $nl + $indent + $lit + $nl + $outer + $Raw.Substring($after)
    }
    return $Raw.Substring(0, $objStart + 1) + $nl + $indent + $lit + ',' + $Raw.Substring($objStart + 1)
}

# --- reading the current state --------------------------------------------

# The only three values output_style.verbosity may hold. Anything else in the
# file is a hand edit this script does not understand, and it is REPORTED as
# unrecognised rather than coerced into one of these - silently reading an
# unknown value as `default` would tell the operator their setting is off when
# the file plainly says something else.
#
# DERIVED from the flag table rather than written out again. The accepted
# arguments, the accepted file values and the levels the usage text lists are
# the same three names, and a second copy of that list is a second thing to keep
# correct - which is the drift this whole script was collapsed into one file to
# avoid. The insertion order of that [ordered] table is the order printed here.
$script:LwgVerbosityValues = @($script:LwgFlags['verbosity'].levels.Keys)

# The boolean this axis used before $script:LwgVerbosityValues replaced it.
# Nothing reads it. It is named here so the report can say it is being ignored -
# a dead key left unmentioned is a preference that stops working quietly, which
# is worse than one that never worked.
$script:LwgLegacyVerbosityKey = 'brief'

function ConvertTo-LwgVerbosity {
    <#
      Normalise a raw config value to one of $script:LwgVerbosityValues, or
      return $null when it is present and unrecognised. An absent value is the
      caller's problem, not this function's.
    #>
    param($Raw)
    $s = ([string]$Raw).Trim().ToLowerInvariant()
    if ($script:LwgVerbosityValues -contains $s) { return $s }
    return $null
}

function Get-LwgPrefGlobal {
    <#
      The global default for a flag, as a bool for a 'bool' axis and as one of
      the three verbosity names for a 'level' axis. Shaped like
      Get-LwgModuleOption: absent means the built-in default, never $null, so a
      stripped-down or missing config still yields a usable answer.

      This is where the fail-CLOSED polarity actually lives. Get-LwgConfig
      returns the built-in module defaults when config.json is unreadable, and
      those defaults contain no `output_style` block at all - so an unreadable
      config yields verbosity `default`, which is neither brief nor verbose,
      rather than switching one of them on.

      An unrecognised verbosity string also falls back to $Default here, and
      the caller prints a line naming the value it could not read. Falling back
      quietly is what would make this dishonest; falling back loudly is just
      what a reader has to do with a value it does not know.

      A BOOL AXIS NOW APPLIES THE SAME RULE TO THE SAME EFFECT: only a real
      boolean is a setting. This is Test-LwgFlag's rule (lib\common.ps1), and it
      is here because it MUST be the same rule - Test-LwgFlag is what the gate
      reads and this is what /lw-watchtower:delegate prints. While this line was a
      bare [bool] and Test-LwgFlag was not, `"delegate": "false"` made this
      command report ON for a config the gate read as OFF: a reporter that
      disagrees with the reader, which is the founding defect this plugin
      exists to catch, shipped inside the plugin itself.

      An ignored global leaves $Default, exactly as an absent one does, and the
      fact is logged through Write-LwgInvalidFlag - the same helper Test-LwgFlag
      uses, so one broken config produces one kind of record. The caller also
      NAMES it on screen, next to the state it is printing.
    #>
    param($Config, [string]$Block, [string]$Key, $Default, [string]$Axis = 'bool')
    try {
        $v = $Config.$Block.$Key
        if ($null -ne $v) {
            if ($Axis -eq 'level') {
                $n = ConvertTo-LwgVerbosity -Raw $v
                if ($null -ne $n) { return $n }
                return $Default
            }
            if ($v -is [bool]) { return $v }
            Write-LwgInvalidFlag -Block $Block -Key $Key -Scope 'global' -Value $v
            return $Default
        }
    } catch { }
    return $Default
}

function Get-LwgPrefRepo {
    <#
      The per-repo override, or $null when this repo does not override the flag.
      $null is a THIRD state and is reported as one: "no override" and
      "overridden to the same value the global already has" look identical in
      the effective value and are different facts about the config.

      An unrecognised verbosity override also returns $null - the override
      cannot be applied - and the caller names it.

      A NON-BOOLEAN OVERRIDE ON A BOOL AXIS RETURNS $null FOR THE SAME REASON,
      and $null here already means the right thing: the override is not applied
      and the global stands. That is precisely Test-LwgFlag's "ignored at that
      scope - resolution continues as if that level had said nothing", which
      matters most in the direction that costs something: a garbage per-repo
      override must NOT disarm a global `true` an operator did arm. Logged
      through Write-LwgInvalidFlag, and named on screen by the caller.
    #>
    param($Config, [string]$Repo, [string]$Block, [string]$Key, [string]$Axis = 'bool')
    if ([string]::IsNullOrWhiteSpace($Repo)) { return $null }
    try {
        $o = $Config.repos.$Repo
        if ($null -eq $o) { return $null }
        $v = $o.$Block.$Key
        if ($null -ne $v) {
            if ($Axis -eq 'level') { return (ConvertTo-LwgVerbosity -Raw $v) }
            if ($v -is [bool]) { return $v }
            Write-LwgInvalidFlag -Block $Block -Key $Key -Scope "repo:$Repo" -Value $v
            return $null
        }
    } catch { }
    return $null
}

function Get-LwgPrefRaw {
    <#
      The value as it literally appears in config.json at the given scope, or
      $null when the key is absent. Used ONLY to name a value that could not be
      read, so the operator is told what is actually in the file rather than
      what this script fell back to.
    #>
    param($Config, [string]$Repo, [string]$Block, [string]$Key, [string]$Scope)
    try {
        $o = if ($Scope -eq 'repo') {
            if ([string]::IsNullOrWhiteSpace($Repo)) { $null } else { $Config.repos.$Repo }
        } else { $Config }
        if ($null -eq $o) { return $null }
        return $o.$Block.$Key
    } catch { }
    return $null
}

function Test-LwgFlagOn {
    <#
      Is this flag on, given the axis value? A 'bool' axis only - the value IS
      the answer. A level has no on/off and is deliberately not squeezed into
      one: `default` is the level at which this axis does nothing, and calling
      that "off" would make `brief` and `verbose` both read as "on", which is
      the two-switch surface this command was merged to stop describing.

      THE LAST GUARD RATHER THAN THE FIRST. Get-LwgPrefGlobal and
      Get-LwgPrefRepo above have already applied the boolean-only rule, so on
      every path through this script $Value arrives as a real boolean and this
      branch never fires. It is here because this function is the one that
      turns a value into the word the operator READS - "delegate is ON" - and a
      bare [bool] at the last step would hand `on` back for a string however
      carefully the two readers above rejected it. A rule enforced at three of
      four steps is a rule with one way through it.

      $Spec.default rather than $false: the default is the flag's own, stated
      once in $script:LwgFlags, and for `delegate` it agrees with the registry's
      switch default that lib/common.ps1 hands Test-LwgFlag - which is what
      makes the answer printed here the answer the gate reaches.
    #>
    param($Spec, $Value)
    if ($Spec.axis -eq 'level') { throw 'Test-LwgFlagOn does not apply to a level axis' }
    if ($Value -is [bool]) { return $Value }
    Write-LwgInvalidFlag -Block ([string]$Spec.block) -Key ([string]$Spec.key) -Scope 'resolved' -Value $Value
    return [bool]$Spec.default
}

function Get-OutputStyleSetting {
    <#
      Read the `outputStyle` key out of a settings file WITHOUT writing it.
      Returns @{ path; state; value } where state is one of 'set', 'unset',
      'absent' or 'unreadable'. 'unreadable' is never collapsed into 'unset':
      a settings file we could not parse is not a settings file that says
      nothing.
    #>
    param([string]$Path)
    $r = @{ path = $Path; state = 'absent'; value = '' }
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $r }
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { $r.state = 'unset'; return $r }
        $o = $raw | ConvertFrom-Json -ErrorAction Stop
        $v = $o.outputStyle
        if ($null -ne $v -and -not [string]::IsNullOrWhiteSpace([string]$v)) {
            $r.state = 'set'; $r.value = [string]$v
        } else {
            $r.state = 'unset'
        }
    } catch { $r.state = 'unreadable' }
    return $r
}

function Write-Wrapped {
    <#
      Print $Text at $Width, indented by $Indent, breaking on spaces only.
      A plain loop rather than a regex: the lookbehind-with-\G trick that does
      this in one expression is unreadable, and one of the two flags this prints
      for is the one that asks for plain language.
    #>
    param([string]$Text, [string]$Indent = '  ', [int]$Width = 84)
    $line = ''
    foreach ($w in @($Text -split ' ' | Where-Object { $_ -ne '' })) {
        if ($line -eq '') { $line = $w }
        elseif (($line.Length + 1 + $w.Length) -le $Width) { $line = $line + ' ' + $w }
        else { Write-Output ($Indent + $line); $line = $w }
    }
    if ($line -ne '') { Write-Output ($Indent + $line) }
}

function Get-LwgBriefParseError {
    <#
      A parser message the operator can read, out of one that may be the whole
      file. Windows PowerShell 5.1's ConvertFrom-Json puts its ENTIRE input into
      the exception message - 33,228 characters for a 33,175-byte config.json,
      measured on this machine on 3 August 2026 - and this script used to
      interpolate that straight into the line it printed.

      First line, then a hard character bound, because a minified file has no
      first line. The same shape as the one already used for subprocess stderr
      in bin\lwg-cmdlib.ps1:505.
    #>
    param([string]$Message, [int]$MaxLength = 160)
    $s = ([string]$Message) -replace "`r", ''
    $s = (($s -split "`n") | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1)
    if ($null -eq $s) { return 'no message' }
    $s = $s.Trim()
    if ($s.Length -gt $MaxLength) { return ($s.Substring(0, $MaxLength) + ' ...') }
    return $s
}

function Write-LwgToggleRefusal {
    <#
      A refusal, in the shape /lw-watchtower:config prints one
      (bin\lwg-config.ps1:74-80). It is a separate voice from the catch-all at
      the bottom of this file on purpose: a refusal is a decision this command
      made and can explain, and "could not complete" is what is left when it
      cannot. Both exit 3 and both leave config.json exactly as it was.
    #>
    param([string[]]$Lines)
    Write-Output ''
    Write-Output 'REFUSED - nothing was written.'
    foreach ($l in $Lines) { Write-Output "  $l" }
}

function Show-Usage {
    param([string]$FlagName, [string]$Bad, [string]$Axis = 'bool')
    if ($null -ne $Bad -and $Bad -ne '') {
        Write-Output ("Not a value this command accepts: '{0}'" -f $Bad)
    }
    $c = "/lw-watchtower:$FlagName"
    if ($Axis -eq 'level') {
        $spec = $script:LwgFlags[$FlagName]
        $w    = $c.Length + 14
        Write-Output ''
        Write-Output ('Usage:  ' + $c.PadRight($w) + 'report the current level, change nothing')
        foreach ($lv in @($spec.levels.Keys)) {
            Write-Output ('        ' + ($c + ' ' + $lv).PadRight($w) + $spec.levels[$lv])
        }
        Write-Output ('        ' + ($c + ' brief repo').PadRight($w) + 'set the level for THIS repository only')
        Write-Output ''
        Write-Output ('Only {0} are accepted. `on`, `off`, `short`, `long` and' -f (($script:LwgVerbosityValues | ForEach-Object { "``$_``" }) -join ', '))
        Write-Output '`terse` are all rejected on purpose. This is a level rather than a switch -'
        Write-Output 'one key holds one of the three - and a command that guesses which level you'
        Write-Output 'meant is a command you cannot be sure you set. Nothing was written.'
        Write-Output ''
        Write-Output 'Directly:'
        Write-Output ("  powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-toggle.ps1 -Flag {0} [{1}] [-Scope global|repo]" -f $FlagName, ($script:LwgVerbosityValues -join '|'))
        return
    }
    $w = $c.Length + 12
    Write-Output ''
    Write-Output ('Usage:  ' + $c.PadRight($w)              + 'report the current state, change nothing')
    Write-Output ('        ' + ($c + ' on').PadRight($w)    + 'turn it on for every repository')
    Write-Output ('        ' + ($c + ' off').PadRight($w)   + 'turn it off for every repository')
    Write-Output ('        ' + ($c + ' on repo').PadRight($w) + 'turn it on for THIS repository only')
    Write-Output ''
    Write-Output 'Only `on` and `off` are accepted. `true`, `1`, `yes` and `enable` are all'
    Write-Output 'rejected on purpose: a toggle that guesses what you meant is a toggle you'
    Write-Output 'cannot be sure you set. Nothing was written.'
    Write-Output ''
    Write-Output 'Directly:'
    Write-Output ("  powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-toggle.ps1 -Flag {0} [on|off] [-Scope global|repo]" -f $FlagName)
}

# --- main -------------------------------------------------------------------

try {
    $pluginRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $pluginRoot 'lib\common.ps1')
    # Read-LwgTextFile and Save-LwgTextFile, and nothing else from it. See the
    # header for why a bin\ command may reach this file and a hook may not.
    . (Join-Path $PSScriptRoot 'lwg-cmdlib.ps1')

    $spec  = $script:LwgFlags[$Flag]
    $block = $spec.block
    $key   = $spec.key
    $axis  = if ($spec.axis) { [string]$spec.axis } else { 'bool' }

    # --- validate the argument BEFORE reading anything ---------------------
    # $want is $true/$false on a bool axis and one of the three level names on a
    # level axis; $null on either means "no argument was given, report only".
    $want = $null
    $raw  = if ($null -eq $Value) { '' } else { $Value.Trim() }
    if ($raw -ne '') {
        if ($axis -eq 'level') {
            # ConvertTo-LwgVerbosity is the SAME normaliser used to read the
            # file, so an argument this command accepts and a config value it
            # honours can never be two different sets.
            $want = ConvertTo-LwgVerbosity -Raw $raw
            if ($null -eq $want) {
                Show-Usage -FlagName $Flag -Bad $raw -Axis $axis
                exit 2
            }
        }
        else {
            switch ($raw.ToLowerInvariant()) {
                'on'  { $want = $true }
                'off' { $want = $false }
                default {
                    Show-Usage -FlagName $Flag -Bad $raw -Axis $axis
                    exit 2
                }
            }
        }
    }

    $cfgPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) { Join-Path $pluginRoot 'config.json' } else { $ConfigPath }
    $cfg     = Get-LwgConfig -Path $cfgPath
    # The TEXT, its SHA and whether it carries a BOM, captured together and
    # here - before anything else this script does can take time - so that the
    # SHA handed to Save-LwgTextFile is the state of the file at the moment its
    # content was read, and a change made after that is caught rather than
    # overwritten. A read is not a write, so a failure to read is only fatal
    # when a write was asked for; the report path below still works off
    # Get-LwgConfig's fallback and says that is what it is doing.
    $file = Read-LwgTextFile -Path $cfgPath

    # Outside a hook there is no payload, so repo identity comes from the cwd -
    # which is what Get-LwgRepo does with a payload anyway.
    $repoInfo = Get-LwgRepoInfo -Path (Get-Location).Path
    $repo     = $repoInfo.slug

    if ($Scope -eq 'repo' -and [string]::IsNullOrWhiteSpace($repo)) {
        Write-Output 'This directory is not inside a git repository with a recognised origin remote,'
        Write-Output 'so there is no `owner/name` slug to key a per-repo override on. Nothing was written.'
        Write-Output ''
        Write-Output ("  cwd     : {0}" -f (Get-Location).Path)
        Write-Output ("  git dir : {0}" -f $(if ($repoInfo.gitdir) { $repoInfo.gitdir } else { 'none found within 12 levels' }))
        Write-Output ("  remotes : {0}" -f $repoInfo.remote_count)
        Write-Output ''
        Write-Output ("Use /lw-watchtower:{0} {1} without the word 'repo' to set the global default instead." -f `
            $Flag, $(if ($raw) { $raw } elseif ($axis -eq 'level') { ($script:LwgVerbosityValues -join '|') } else { 'on|off' }))
        exit 2
    }

    # --- refuse to write on top of a config this command cannot read back ----
    # Get-LwgConfig fails OPEN: an unreadable, unparseable or modules-less
    # config.json returns the built-in defaults (lib\common.ps1:447-459), and
    # every operator ON/OFF choice in that file is ALREADY being ignored. Two
    # things follow, and this script used to do neither.
    #
    # Writing here would edit text this command cannot read back - which is
    # exactly what produced the write-then-exit-3 path: the value landed on disk,
    # the re-read returned the defaults again, and the read-back check threw.
    # /lw-watchtower:config refuses the same input at bin\lwg-config.ps1:262-269
    # and the two commands must not disagree about what a broken config.json
    # means.
    #
    # And the cause is NAMED. Blaming the edit for a file that was already broken
    # sends the operator to report a bug in a command that did nothing wrong, and
    # the parser message that would have been quoted at them is the whole file.
    # `does not parse` and `parses but has no modules block` are different
    # states with the same fallback, so the message says which one it found.
    if ($null -ne $want -and $cfg._source -ne 'file') {
        $why = 'could not be loaded'
        if (-not $file.ok) {
            $why = ("could not be read - {0}" -f (Get-LwgBriefParseError -Message $file.error))
        }
        elseif ([string]::IsNullOrWhiteSpace($file.text)) {
            $why = 'is empty'
        }
        else {
            try {
                $probe = $file.text | ConvertFrom-Json -ErrorAction Stop
                if ($null -eq $probe) {
                    $why = 'holds no JSON object'
                } elseif ($null -eq $probe.modules) {
                    $why = 'parses, but has no top-level "modules" block - which is what Get-LwgConfig requires before it will use the file at all (lib\common.ps1:452)'
                }
            } catch {
                $why = ("does not parse - {0}" -f (Get-LwgBriefParseError -Message $_.Exception.Message))
            }
        }
        Write-LwgToggleRefusal @(
            ("{0} {1}," -f $cfgPath, $why),
            'so the plugin is running on BUILT-IN DEFAULTS and every operator ON/OFF choice in that file is already being ignored.',
            'Writing here would edit text this command cannot read back, and would destroy the evidence of what broke.',
            'Fix the JSON first - /lw-watchtower:doctor names this as the config-registry check.',
            '',
            ("Run /lw-watchtower:{0} with no argument to see what is in effect while it is broken." -f $Flag)
        )
        exit 3
    }

    $beforeGlobal = Get-LwgPrefGlobal -Config $cfg -Block $block -Key $key -Default $spec.default -Axis $axis
    $beforeRepo   = Get-LwgPrefRepo   -Config $cfg -Repo $repo -Block $block -Key $key -Axis $axis
    $beforeEff    = if ($null -ne $beforeRepo) { $beforeRepo } else { $beforeGlobal }

    # --- write, if we were asked to ----------------------------------------
    $changeLine = 'nothing was written - no value was given, so this is a report only'
    $leaf       = ''
    # Set by the write below. Named here so the report block can print it on
    # every path without knowing which one it came down.
    $backup     = ''
    if ($null -ne $want) {
        $path = if ($Scope -eq 'repo') { @('repos', $repo, $block, $key) } else { @($block, $key) }
        $wasHere = if ($Scope -eq 'repo') { $beforeRepo } else { $beforeGlobal }

        if ($axis -eq 'level') {
            # The argument IS the value, so there is no case in which the write
            # has to be skipped: setting the level to the one already held
            # rewrites the same three characters, and a repo override asked for
            # explicitly is created even when it matches the global.
            #
            # `wasHere` for a repo scope falls back to the global when there is
            # no override, because that is the level that actually applies here
            # and it is what the operator is changing FROM.
            $stateHere = if ($Scope -eq 'repo' -and $null -eq $beforeRepo) { $beforeGlobal } else { $wasHere }
            $leaf      = '"' + $want + '"'

            if ($Scope -eq 'repo' -and $null -eq $beforeRepo) {
                $changeLine = ("repo override CREATED for {0}: verbosity = '{1}'  (was '{2}', inherited from the global default)" -f $repo, $want, $stateHere)
            } elseif ([string]$stateHere -eq [string]$want) {
                $changeLine = ("no change - the {0} verbosity was already '{1}'" -f $Scope, $want)
            } else {
                $changeLine = ("{0}: verbosity '{1}' -> '{2}'" -f $Scope, $stateHere, $want)
            }
        }
        else {
            $leaf = if ($want) { 'true' } else { 'false' }
            if ($Scope -eq 'repo' -and $null -eq $beforeRepo) {
                $changeLine = ("repo override CREATED for {0}: {1}" -f $repo, $(if ($want) { 'on' } else { 'off' }))
            } elseif ($wasHere -eq $want) {
                $changeLine = ("no change - the {0} value was already {1}" -f $Scope, $(if ($want) { 'on' } else { 'off' }))
            } else {
                $changeLine = ("{0}: {1} -> {2}" -f $Scope, $(if ($wasHere) { 'on' } else { 'off' }), $(if ($want) { 'on' } else { 'off' }))
            }
        }

        # The text that was read at the top, with the SHA and the BOM flag that
        # belong to it. Not a second ReadAllText: two reads are two states, and
        # the one that matters is the one the SHA describes.
        if (-not $file.ok) { throw ("config.json could not be read ({0}); nothing was written" -f (Get-LwgBriefParseError -Message $file.error)) }
        $original = $file.text
        $updated  = Set-JsonLiteralAtPath -Raw $original -Path $path -Leaf $leaf

        # The file is only replaced if the NEW text parses. A preference command
        # that can corrupt config.json would take both live gates down with it,
        # because Get-LwgConfig fails open and every module would switch on.
        #
        # This message may now blame the edit, and could not before: the refusal
        # above has already established that $original parsed and carried a
        # `modules` block, so text that does not parse is this command's doing.
        # The parser message is still bounded - see Get-LwgBriefParseError.
        $parsed = $null
        try { $parsed = $updated | ConvertFrom-Json -ErrorAction Stop }
        catch { throw ("the edit this command made would not parse ({0}); the file was left untouched, and config.json parsed before the edit, so this is a fault in this script rather than in the file" -f (Get-LwgBriefParseError -Message $_.Exception.Message)) }

        # --- prove the edit reads back BEFORE it is written ------------------
        # The check that used to run after the write, run against the TEXT
        # instead. Get-LwgConfig's own rule first - a file with no `modules` is
        # not used at all - then this script's own accessors, which are what the
        # report below and the gate itself read. A refusal here costs nothing;
        # the same disagreement discovered after the write is what made a
        # documented "nothing was written" exit 3 untrue.
        if ($null -eq $parsed.modules) {
            throw 'the edit would leave config.json without a top-level "modules" block, so every reader would fall back to the built-in defaults and this setting would be ignored; nothing was written'
        }
        $wouldGlobal = Get-LwgPrefGlobal -Config $parsed -Block $block -Key $key -Default $spec.default -Axis $axis
        $wouldRepo   = Get-LwgPrefRepo   -Config $parsed -Repo $repo -Block $block -Key $key -Axis $axis
        $wouldHere   = if ($Scope -eq 'repo') { $wouldRepo } else { $wouldGlobal }
        if ($axis -eq 'level') {
            if ([string]$wouldHere -ne [string]$want) {
                throw "the edited text does not read back as '$want' - it reads as '$wouldHere' - so nothing was written"
            }
        }
        else {
            if ((Test-LwgFlagOn -Spec $spec -Value $wouldHere) -ne $want) {
                throw ("the edited text does not read back as {0} - so nothing was written" -f $(if ($want) { 'on' } else { 'off' }))
            }
        }

        # --- the write -------------------------------------------------------
        # Through Save-LwgTextFile, which takes a backup FIRST, refuses if the
        # file on disk is no longer the one that was read, and writes with the
        # BOM the file already had. See the header, and bin\lwg-cmdlib.ps1:362-406.
        $backup = ''
        $wroteSha = ''
        if ($updated -ne $original) {
            $save = Save-LwgTextFile -Path $cfgPath -Text $updated -ExpectedSha $file.sha -Bom $file.bom -BackupTag 'lwg-toggle'
            if (-not $save.ok) {
                # A refusal, not a failure. CHANGED UNDER US means somebody
                # else's write landed between this command's read and this line,
                # and replacing the file would discard it silently.
                Write-LwgToggleRefusal @(
                    ("the write did not happen: {0}" -f $save.reason),
                    'Nothing was discarded and config.json is as whoever wrote it last left it.',
                    ("Run /lw-watchtower:{0} with no argument to see the state now, then decide again." -f $Flag)
                )
                exit 3
            }
            $backup   = $save.backup
            $wroteSha = $save.sha
            # Read by the handler at the bottom of this file, which has to know
            # whether the bytes moved before it can say anything true about them.
            $script:LwgWrote  = $true
            $script:LwgBackup = $save.backup
        }

        # Re-read from disk rather than trusting the in-memory edit: the value
        # reported below is then the value a hook would actually load. The text
        # was already resolved above, so this can only disagree if the bytes on
        # disk are no longer the ones this command wrote.
        $cfg          = Get-LwgConfig -Path $cfgPath
        $afterGlobal  = Get-LwgPrefGlobal -Config $cfg -Block $block -Key $key -Default $spec.default -Axis $axis
        $afterRepo    = Get-LwgPrefRepo   -Config $cfg -Repo $repo -Block $block -Key $key -Axis $axis
        $writtenHere  = if ($Scope -eq 'repo') { $afterRepo } else { $afterGlobal }
        $readBackBad  = if ($axis -eq 'level') {
            ([string]$writtenHere -ne [string]$want)
        } else {
            ((Test-LwgFlagOn -Spec $spec -Value $writtenHere) -ne $want)
        }
        if ($readBackBad) {
            # WHAT THIS DOES NOT DO, AND WHY THERE IS NO AUTOMATIC ROLLBACK.
            # A restore-from-backup lived here for one day, on 3 August 2026, and
            # was removed the same day: with the pre-write resolution above in
            # place, the only way these bytes can fail to read back is that they
            # are no longer the bytes this command wrote - and putting the backup
            # on top of somebody else's write is exactly the lost update the SHA
            # check exists to prevent. A restore that can only fire when firing
            # it would be wrong is a switch wired to nothing, and no case in
            # tests\toggle_behaviour.ps1 could reach it. So this branch REPORTS
            # instead: whether the file on disk is still the one this command
            # wrote, and where the copy taken before the write is.
            $stillOurs = $false
            if ($backup) {
                try { $stillOurs = ((Get-FileHash -LiteralPath $cfgPath -Algorithm SHA256).Hash -eq $wroteSha) } catch { $stillOurs = $false }
            }
            $tail = if (-not $backup) {
                'nothing was written'
            } elseif ($stillOurs) {
                "config.json WAS written by this command and still holds those bytes; the copy taken before the write is at $backup, and restoring it by hand is a one-line copy"
            } else {
                "config.json WAS written by this command and has been written again by something else since; the copy taken before this command's write is at $backup"
            }
            $reads = if ($axis -eq 'level') { "'$writtenHere'" } else { $(if (Test-LwgFlagOn -Spec $spec -Value $writtenHere) { 'on' } else { 'off' }) }
            $asked = if ($axis -eq 'level') { "'$want'" } else { $(if ($want) { 'on' } else { 'off' }) }
            throw "$Flag reads back as $reads rather than $asked after the write; $tail"
        }
        # The write happened AND the file on disk resolves to what was asked for.
        # Anything that throws after this point is a fault in the REPORTING, and
        # the handler at the bottom must not call that "nothing was written".
        $script:LwgVerified = $true
    } else {
        $afterGlobal = $beforeGlobal
        $afterRepo   = $beforeRepo
    }

    $afterEff   = if ($null -ne $afterRepo) { $afterRepo } else { $afterGlobal }
    $afterEffOn = if ($axis -eq 'level') { $null } else { (Test-LwgFlagOn -Spec $spec -Value $afterEff) }
    # A level prints as the name it holds. There is no on/off column for it, and
    # inventing one would put `brief` and `verbose` both in an "on" state - the
    # two-switch fiction this command exists to have stopped telling.
    $shown = {
        param($v)
        if ($axis -eq 'level') { ("'{0}'" -f $v) }
        else { if (Test-LwgFlagOn -Spec $spec -Value $v) { 'on' } else { 'off' } }
    }

    # --- report -------------------------------------------------------------
    if ($axis -eq 'level') {
        Write-Output ("{0} is '{1}'    ({2})" -f $Flag, $afterEff, $spec.levels[[string]$afterEff])
    } else {
        Write-Output ("{0} is {1}    ({2})" -f $Flag, $(if ($afterEffOn) { 'ON' } else { 'OFF' }), $spec.summary)
    }
    Write-Output ''
    Write-Output ("  changed        : {0}" -f $changeLine)
    Write-Output ("  global default : {0}" -f (& $shown $afterGlobal))
    Write-Output ("  repo override  : {0}   [{1}]" -f `
        $(if ($null -eq $afterRepo) { 'none - falls through to the global default' } else { (& $shown $afterRepo) + ' - overrides the global default here' }), `
        $(if ($repo) { $repo } else { 'not in a recognised repo; per-repo overrides cannot apply' }))
    if ($null -ne $afterRepo) {
        # There is no argument that DELETES an override, and there should not
        # be: the accepted values and "nothing at all" are all an operator
        # types, and a verb that removes a key is one more thing to get wrong.
        # Say where the entry is instead.
        Write-Output '                   to drop the override and follow the global default again,'
        Write-Output ("                   delete repos[`"{0}`"] from config.json by hand" -f $repo)
    }
    Write-Output ("  effective here : {0}" -f $(if ($axis -eq 'level') { "'$afterEff'" } elseif ($afterEffOn) { 'ON' } else { 'OFF' }))
    Write-Output ("  stored in      : {0} -> {1}.{2}" -f $cfgPath, $block, $key)
    if ($backup) {
        # Printed for the same reason /lw-watchtower:config prints it
        # (bin\lwg-config.ps1:443): a backup nobody is told about is not a
        # recovery mechanism. Nothing deletes these, ever.
        Write-Output ("  backup         : {0}   [the file as it was before this run]" -f $backup)
    }
    Write-Output ("  config source  : {0}" -f $(if ($cfg._source -eq 'file') { 'config.json' } else { 'BUILT-IN DEFAULTS - config.json is unreadable, so what you see is the fallback' }))

    # A value this script cannot read is NAMED, on either axis, and on a bool
    # axis that is not politeness. The state printed above is the one the reader
    # reaches - Test-LwgFlag in lib\common.ps1 applies the same boolean-only
    # rule - so without this block an operator who wrote `"delegate": "false"`
    # sees OFF, is told nothing, and still has the string in their config for
    # the next reader to disagree about. The level axis prints its own,
    # differently worded version further down; the two are separate because a
    # level's unreadable value is a NAME nobody recognises and a boolean's is a
    # TYPE that is not a boolean, and one sentence covering both would say
    # neither.
    if ($axis -ne 'level') {
        foreach ($sc in @('global', 'repo')) {
            $rawBool = Get-LwgPrefRaw -Config $cfg -Repo $repo -Block $block -Key $key -Scope $sc
            if ($null -eq $rawBool -or $rawBool -is [bool]) { continue }
            $where = if ($sc -eq 'repo') { ('repos["{0}"].{1}.{2}' -f $repo, $block, $key) } else { ('{0}.{1}' -f $block, $key) }
            Write-Output ''
            Write-Output ("  NOT A BOOLEAN at the {0} scope: {1} is '{2}', a {3} rather than true or false." -f `
                $sc, $where, $rawBool, $rawBool.GetType().Name)
            Write-Output '  It is being IGNORED, not honoured, and not read as false either - a value that'
            Write-Output '  is not a boolean is not a setting, so that scope is skipped entirely and the'
            Write-Output ("  state above is what applies. The same rule is what {0} itself reads." -f $Flag)
            Write-Output ("  Run ``/lw-watchtower:{0} on`` or ``/lw-watchtower:{0} off`` to overwrite it." -f $Flag)
        }
    }

    if ($axis -eq 'level') {
        # One key, three levels. Said on every run, because the operator who
        # reads "brief" here has to know what the other two names are and that
        # holding one means not holding the others.
        Write-Output ''
        Write-Output ("  ONE KEY, THREE LEVELS. {0}.{1} holds exactly one of {2}," -f $block, $key, ($script:LwgVerbosityValues -join ', '))
        Write-Output '  so a level is never "on" alongside another - setting one is unsetting the rest,'
        Write-Output '  and `default` is the level at which this axis does nothing.'
        Write-Output ''
        # No leading slash on the two dead names - see the header.
        Write-Output '  THIS WAS TWO COMMANDS UNTIL NOW. lw-watchtower:brief and lw-watchtower:verbose wrote this'
        Write-Output '  same key, so `brief off` while the key read `verbose` correctly wrote nothing at'
        Write-Output '  all and had to explain why every time. Two switches over one three-value setting'
        Write-Output '  describe a model that is not there. The level is now named directly.'
        Write-Output '  It is still one key rather than two booleans because a per-repo override is'
        Write-Output '  merged key by key - two keys could have been set at different scopes and'
        Write-Output '  contradicted each other with no writer present to stop it.'

        # A value nobody here understands is named, never coerced quietly.
        foreach ($sc in @('global', 'repo')) {
            $rawVal = Get-LwgPrefRaw -Config $cfg -Repo $repo -Block $block -Key $key -Scope $sc
            if ($null -eq $rawVal) { continue }
            if ($null -ne (ConvertTo-LwgVerbosity -Raw $rawVal)) { continue }
            Write-Output ''
            Write-Output ("  UNRECOGNISED VALUE at the {0} scope: {1}.{2} is '{3}', which is not one of" -f $sc, $block, $key, $rawVal)
            Write-Output ("  {0}. It is being IGNORED, not honoured - the state above is what applies." -f ($script:LwgVerbosityValues -join ', '))
            Write-Output '  Fix it by hand, or run this command with a level name to overwrite it.'
        }

        # A value this script cannot read is named above; a KEY it no longer
        # reads has to be named too, and for the same reason. `output_style.brief`
        # was this axis's old boolean before the three-value key replaced it.
        # Nothing reads it now, so an operator who set it under the old schema
        # keeps a file that plainly states a preference and a plugin that plainly
        # ignores it - the exact silence the block above exists to break.
        #
        # It is REPORTED, never rewritten. Deleting a key on someone's behalf
        # while they asked only to read a setting is a worse surprise than the
        # stale key, and migrating it would have to guess whether `false` meant
        # `default` or `verbose`. The operator is told the one command that sets
        # the live key and left to remove the dead one.
        foreach ($sc in @('global', 'repo')) {
            $legacy = Get-LwgPrefRaw -Config $cfg -Repo $repo -Block $block -Key $script:LwgLegacyVerbosityKey -Scope $sc
            if ($null -eq $legacy) { continue }
            # Name the key by its full path, because "delete output_style.brief"
            # sends a reader to the wrong place when the stale copy is the one
            # nested under a repo override.
            $where = if ($sc -eq 'repo') {
                ('repos["{0}"].{1}.{2}' -f $repo, $block, $script:LwgLegacyVerbosityKey)
            } else {
                ('{0}.{1}' -f $block, $script:LwgLegacyVerbosityKey)
            }
            Write-Output ''
            Write-Output ("  OBSOLETE KEY at the {0} scope: {1} is '{2}', and that key was replaced by" -f $sc, $where, $legacy)
            Write-Output ("  {0}.{1}. It is being IGNORED, not honoured - the state above is what applies." -f $block, $key)
            Write-Output ("  Run ``/lw-watchtower:{0} brief`` or ``/lw-watchtower:{0} verbose`` to set the preference again," -f $Flag)
            Write-Output ("  then delete {0} from config.json by hand - this command will not touch it." -f $where)
        }
    }

    if ($spec.kind -eq 'style') {
        # --- what the operator still has to do themselves -------------------
        # Two independent axes - verbosity (three values) and plain (two) - and
        # `outputStyle` is a single string, so the six combinations map onto
        # five shipped files plus the built-in Default. The mapping is computed
        # here and nowhere else; the command prose is told to print what this
        # works out rather than to work it out itself.
        $sVerb = $script:LwgFlags['verbosity']
        $gVerb = Get-LwgPrefGlobal -Config $cfg -Block $sVerb.block -Key $sVerb.key -Default $sVerb.default -Axis 'level'
        $rVerb = Get-LwgPrefRepo   -Config $cfg -Repo $repo -Block $sVerb.block -Key $sVerb.key -Axis 'level'
        $effVerb = if ($null -ne $rVerb) { $rVerb } else { $gVerb }

        $sPlain = $script:LwgFlags['plain']
        $gPlain = Get-LwgPrefGlobal -Config $cfg -Block $sPlain.block -Key $sPlain.key -Default $sPlain.default -Axis 'bool'
        $rPlain = Get-LwgPrefRepo   -Config $cfg -Repo $repo -Block $sPlain.block -Key $sPlain.key -Axis 'bool'
        $effPlain = if ($null -ne $rPlain) { $rPlain } else { $gPlain }

        $target = switch ("$effVerb/$effPlain") {
            'brief/True'    { 'lw-watchtower-brief-plain' }
            'brief/False'   { 'lw-watchtower-brief' }
            'verbose/True'  { 'lw-watchtower-verbose-plain' }
            'verbose/False' { 'lw-watchtower-verbose' }
            'default/True'  { 'lw-watchtower-plain' }
            default         { '' }
        }

        $styleFile = if ($target) { Join-Path $pluginRoot ("output-styles\{0}.md" -f $target) } else { '' }
        $styleOk   = if ($target) { Test-Path -LiteralPath $styleFile -PathType Leaf } else { $true }

        # Read-only. Nothing here writes a settings file - see the header.
        $projRoot = if ($repoInfo.root) { $repoInfo.root } else { (Get-Location).Path }
        $probes = @(
            (Get-OutputStyleSetting -Path (Join-Path $projRoot '.claude\settings.local.json'))
            (Get-OutputStyleSetting -Path (Join-Path $projRoot '.claude\settings.json'))
            (Get-OutputStyleSetting -Path (Join-Path $env:USERPROFILE '.claude\settings.json'))
        )
        $live = $null
        foreach ($p in $probes) { if ($p.state -eq 'set') { $live = $p; break } }

        Write-Output ''
        Write-Output 'ACTIVATION - this command did NOT activate anything'
        Write-Output ''
        Write-Output ("  preferences here        : verbosity '{0}', plain {1}" -f $effVerb, $(if ($effPlain) { 'on' } else { 'off' }))
        Write-Output ("  preference now asks for : {0}" -f $(if ($target) { $target } else { 'Default (the built-in style - verbosity `default` and plain off)' }))
        if ($target) {
            Write-Output ("  style file              : {0}  [{1}]" -f $styleFile, $(if ($styleOk) { 'present' } else { 'MISSING - the style cannot load' }))
        }
        Write-Output ("  outputStyle in settings : {0}" -f `
            $(if ($null -ne $live) { "'$($live.value)'  (from $($live.path))" } else { 'not set in any settings file checked' }))
        foreach ($p in $probes) {
            Write-Output ("      {0,-11} {1}" -f $p.state, $p.path)
        }
        Write-Output ''
        Write-Output '  The style Claude Code applies is the `outputStyle` key in a settings file,'
        Write-Output '  and this command does not write it. Two reasons, both deliberate:'
        Write-Output '  a settings file is not part of this plugin, and the /config picker already'
        Write-Output '  owns that value and writes whatever string the installed plugin actually'
        Write-Output '  needs - a string this repo has NOT confirmed against a live install, since'
        Write-Output '  a plugin-supplied style may or may not be namespaced in that value.'
        Write-Output ''
        Write-Output '  To activate:  run /config, choose Output style, pick the entry above.'
        Write-Output '                Then /clear, or start a new session.'
        Write-Output ''
        Write-Output '  IT WILL NOT TAKE EFFECT IN THIS SESSION. An output style is read into the'
        Write-Output '  system prompt once, at session start. Changing it mid-session changes'
        Write-Output '  nothing until the prompt is rebuilt, and /clear discards the conversation.'
        Write-Output '  (/output-style was removed in Claude Code 2.1.91 - /config is the route.)'
        Write-Output ''
        Write-Output '  Output styles also reach the MAIN CONVERSATION ONLY. A subagent runs its'
        Write-Output '  own system prompt, so every dispatched worker answers in its own voice'
        Write-Output '  regardless of this setting.'
    }
    else {
        Write-Output ''
        Write-Output 'IN EFFECT FROM NOW ON, in this session:'
        Write-Output ''
        Write-Wrapped -Text $(if ($afterEff) { $spec.onText } else { $spec.offText }) -Indent '  '
        Write-Output ''
        # Two headings over one block, chosen by which key the flag carries. The
        # heading is the first thing read, so a wired switch printing NOT WIRED -
        # or an unwired one printing ENFORCED - would be the loudest possible lie
        # this command could tell about itself. There is no default: a flag
        # carrying neither key prints nothing, which is visibly wrong rather than
        # quietly wrong.
        if ($spec.wired) {
            Write-Output 'ENFORCED - what this switch actually blocks, and what that costs'
            Write-Output ''
            foreach ($line in @($spec.wired)) { Write-Output ("  {0}" -f $line) }
        }
        elseif ($spec.notWired) {
            Write-Output 'NOT WIRED - read this before treating the line above as a control'
            Write-Output ''
            foreach ($line in @($spec.notWired)) { Write-Output ("  {0}" -f $line) }
        }
    }

    Write-Output ''
    if ($spec.wired) {
        # The banner number DOES move for this one, and saying otherwise would
        # make the operator distrust the count when it changed under them.
        Write-Output ("  A governance module. {0} is the switch on delegate_gate in the module" -f $Flag)
        Write-Output '  registry in lib/common.ps1 - kind "gate", the only one - so the banner counts it'
        Write-Output '  and the live-gate count moves with it. Its FLAG stays out of the "modules" block'
        Write-Output '  on purpose: one gate must have one switch, and Get-LwgConfig fails OPEN, which'
        Write-Output '  would arm a blocking hook off an unreadable config. Read the state back with'
        Write-Output '  /lw-watchtower:status, which reports gates shipped and gates live as separate numbers.'
    } else {
        Write-Output ("  Not a governance module. {0} is absent from the module registry in" -f $Flag)
        Write-Output '  lib/common.ps1 and from the "modules" block of config.json on purpose, so it'
        Write-Output '  does not appear in the banner n/10 count and does not inherit the fail-OPEN'
        Write-Output '  behaviour of Get-LwgConfig. The module count is unchanged by this command.'
    }

    exit 0

} catch {
    if ($script:LwgVerified) {
        # THE WRITE HAPPENED AND WAS VERIFIED; WHAT FAILED IS THE REPORT AFTER IT.
        # Exit 3 here would state, in the words of this file's own table and of
        # all three command documents, that config.json was not changed - and it
        # was. Until 3 August 2026 that is exactly what happened: with
        # USERPROFILE unset, `Join-Path $env:USERPROFILE '.claude\settings.json'`
        # in the ACTIVATION block threw under $ErrorActionPreference='Stop' and
        # /lw-watchtower:plain exited 3 on a file it had just rewritten.
        #
        # The class is guarded rather than that one line, and deliberately: the
        # report reads a settings file whose path comes from an environment this
        # plugin does not own, and hardening one Join-Path leaves the next
        # environment-fed line to reopen the same hole. What a caller needs from
        # the exit code is whether the file changed; it did, so this is 0, and
        # the reporting fault is named rather than swallowed.
        Write-Output ''
        Write-Output ("The {0} change WAS MADE: config.json was written and re-read from disk, and it" -f $Flag)
        Write-Output 'holds the value that was asked for. The exit code is 0 because the file changed.'
        Write-Output ("What failed is the report printed after the write: {0}" -f (Get-LwgBriefParseError -Message $_.Exception.Message))
        if ($script:LwgBackup) { Write-Output ("The copy taken before the write is at {0}" -f $script:LwgBackup) }
        Write-Output ("Anything above this line is incomplete rather than wrong. Run /lw-watchtower:{0}" -f $Flag)
        Write-Output 'with no argument for the state; nothing needs to be run again.'
        exit 0
    }
    Write-Output ("The {0} command could not complete: {1}" -f $Flag, $_.Exception.Message)
    Write-Output 'Nothing above should be read as the current state. config.json is as it was'
    Write-Output 'unless a line above says otherwise in as many words - every check that can'
    Write-Output 'refuse runs before the write, and the one place that cannot says which of the'
    Write-Output 'two states the file is in.'
    exit 3
}
