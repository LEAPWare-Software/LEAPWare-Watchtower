#requires -version 5
<#
  LW-WATCHTOWER preference settings - delegate.

      powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-toggle.ps1 -Flag delegate
      powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-toggle.ps1 -Flag delegate on
      powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-toggle.ps1 -Flag delegate on -Scope repo

  Backs /lw-watchtower:delegate. It is the ONE flag left here, and the
  read/validate/write/report path is still written once rather than folded into
  the command prose, because this repo has already shipped the bug where a
  second copy of a rule drifted from the first (see Get-LwgSessionMode in
  lib/common.ps1, which was lifted out of session_start.ps1 for exactly that
  reason). The per-flag facts live in $script:LwgFlags below and nowhere else.

  IT WAS FIVE FLAGS, THEN THREE, AND IS NOW ONE.

  `ask` and `ask-inline` went on 30 JULY 2026 by an explicit owner decision,
  along with commands/ask.md, commands/ask-inline.md and the interaction.ask /
  interaction.ask_inline keys. Both had been ON by default since they shipped
  while enforcing nothing, and neither can be built: a Stop hook can refuse to
  end a turn but cannot stop prose that has already appeared and cannot detect a
  question that should have been asked and was not, and nothing can merge
  questions after they have been asked.

  `verbosity` and `plain` went with the whole output-style feature, along with
  commands/verbosity.md, commands/plain.md, the output-styles/ directory and
  config.json's `output_style` block. They wrote two keys that NOTHING in this
  plugin read. The style Claude Code actually applies is the `outputStyle` key
  in a settings file; this plugin never wrote that key and was right not to - a
  settings file is not part of it, and the /config picker already owns that
  value - so the two commands recorded a preference, printed an ACTIVATION block
  explaining that they had activated nothing, and sent the operator away to set
  the real thing by hand. A switch reported as a control while it controls
  nothing is the exact defect this plugin exists to catch, and it shipped two.

  ALL FOUR DEAD NAMES ARE WRITTEN WITHOUT A LEADING SLASH here and everywhere
  else in this file, and in what it prints. bin\lwg-doctor.ps1 scans this repo
  for /<plugin>:<name> and fails on one with no commands\<name>.md behind it -
  which is the right rule, because a live-looking reference to a command that no
  longer exists is a signpost to nothing.

  ONE FLAG IS STILL A TABLE. $script:LwgFlags below holds a single entry and
  keeps the shape it had at five, because the alternative is spreading
  `delegate`'s block, key, default and enforcement prose through the body of
  this script, where the next reader has to go and find them before they can
  change one of them.

  Exit codes - a caller reads these and nothing else:

      0  the state was reported, or the state was changed and reported
      2  the argument was not `on` or `off`, or the scope could not be used.
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
  commands\delegate.md states it as well, so it is a claim made in two places
  about a file on disk.

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

  The second false path was found by review on 3 August 2026, and NOTHING THAT
  SHIPS NOW REACHES IT - which is a different statement from fixed. The write
  completed and the REPORT printed after it threw: with USERPROFILE unset, the
  output-style ACTIVATION block built a settings path out of a variable this
  plugin does not own, and every throw in this file lands in one handler that
  exited 3 on a file it had just rewritten. That block went with the output
  styles, and no line left here reads the environment. The GUARD stays, and is
  the reason this paragraph is not simply deleted: the handler asks whether the
  write completed and was verified first, and exits 0 when it did, naming the
  reporting fault.

  NO DETERMINISTIC PATH REACHES THAT GUARD NOW, and it is kept anyway - the same
  standing the post-write read-back handler below has. It guards the CLASS of a
  report that throws over a file that was written, rather than the one line that
  used to do it; hardening that Join-Path would have left the next line free to
  reopen the hole, and the next line printed after a verified write is the one
  nobody has written yet. A class guard on a path nothing takes costs an exit
  code being right instead of wrong on the day someone adds one. See the catch
  at the bottom.

  THE ONE STATE STILL NOT COVERED, named rather than left to be discovered: if
  something else writes config.json AFTER this command's write and BEFORE its
  read-back, the read-back can disagree on a file that WAS changed, and the exit
  is 3. It is not put back automatically - restoring over another writer's file
  is the lost update the SHA check exists to prevent - and the message says
  which of the two states the file is in and where the backup is. Nothing
  deterministic reaches that state and no case in tests\toggle_behaviour.ps1
  constructs one. It is the only path on which exit 3 and "the bytes are as they
  were" can still disagree, and commands\delegate.md's exit-code lines describe
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

  WHAT THIS SCRIPT DOES, and says so on every run. `delegate` is ENFORCED, and
  it prints an ENFORCED block saying what it blocks. Since 30 July 2026
  interaction.delegate is the switch on delegate_gate - lib/gate_delegate.ps1, a
  PreToolUse hook that refuses Edit, Write, NotebookEdit, Bash and PowerShell
  for calls that did not come from a subagent. Turning it on from here really
  does block. Turning it OFF again from here does not work, because this command
  runs through Bash; the ENFORCED block says so, and says what to do instead.

  That block is printed by the SCRIPT rather than left to the command prose,
  because a switch that reports itself as wired when it is not - or as unwired
  when it is - is the exact defect this plugin exists to catch. There is no
  NOT WIRED counterpart left to print: the two flags that needed one were the
  output-style pair, and they are gone.

  WHY THE FLAG IS NOT IN config.json's `modules` BLOCK. `delegate` IS in the
  module registry, as delegate_gate: it is governance - it is the only gate - so
  it belongs in the banner count. What stayed OUT is its FLAG. The registry
  entry declares `switch = interaction.delegate` rather than taking a `modules`
  key, because two switches over one gate lets an operator turn it on here and
  have it silently do nothing. Get-LwgConfig also fails OPEN - a corrupt or
  unreadable config turns every `modules` flag ON - and arming a blocking gate
  off an unreadable file is the opposite of what this plugin argues for. The key
  is read through a Get-LwgModuleOption-shaped accessor that returns the
  built-in default when it is absent, so an unreadable config leaves the gate
  off rather than switching a blocking hook on by accident.
#>

[CmdletBinding()]
param(
    # Which preference. Not free text - an unknown name is a binding error
    # before any config is read, so a typo can never write a key nothing reads.
    [Parameter(Mandatory = $true)]
    [ValidateSet('delegate')]
    [string]$Flag,

    # `on`, `off`, or nothing at all to report the current state.
    # Deliberately NOT a ValidateSet: a rejected value must print this script's
    # own usage text and exit 2, not a PowerShell binding exception.
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
# default     the value when the key is absent. `delegate` defaults OFF, and
#             that is stronger than a preference: its on state arms the only
#             gate this plugin ships, and a blocking gate switched on by default
#             is the opposite of what this plugin argues for. Its default is
#             stated TWICE - here, and on the registry entry's `switch` field in
#             lib/common.ps1, which is what the gate itself reads. They must
#             agree; tests/gate_delegate.ps1 asserts the shipped config leaves
#             the gate off.
# wired       what this flag blocks and what that costs. Every flag left in this
#             table is enforced; the ones that were not are gone.
$script:LwgFlags = @{
    'delegate' = @{
        block   = 'interaction'; key = 'delegate'; default = $false
        summary = 'reserve the chat session for operator communication - all work goes to subagents'
        onText  = 'Do the work in subagents. The chat session is for talking to the operator: dispatch with the Agent tool and report back, rather than editing, running or building on the main thread. A worker cannot see this conversation, so every dispatch must restate the context, the absolute paths, the definition of done and the prohibitions.'
        offText = 'Work may be done directly on the main thread.'
        # What the gate refuses, and what refusing it costs. See the header.
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
      members are considered - a nested object is skipped whole, so `"delegate"`
      inside `repos` is never mistaken for `"delegate"` at the top level.

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
      `true` or `false`. Existing members are overwritten in place; missing ones
      are inserted as the first member of the deepest object that does exist,
      creating any intermediate objects on the way. Throws when the path runs
      into a member that is not an object - better a loud failure than a silent
      write into the wrong shape.

      $Leaf is a LITERAL rather than a typed value, and it stays that way now
      that only booleans are written. It carried the three-value string of the
      removed `verbosity` axis as well, so the parameter has already been the
      seam that let one writer serve two shapes; narrowing it to [bool] here
      would move that decision into this function and have to be undone by the
      next flag that is not one. Nothing this script passes needs escaping, so
      none is done.
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

function Get-LwgPrefGlobal {
    <#
      The global default for a flag, as a bool. Shaped like Get-LwgModuleOption:
      absent means the built-in default, never $null, so a stripped-down or
      missing config still yields a usable answer.

      This is where the fail-CLOSED polarity actually lives. Get-LwgConfig
      returns the built-in module defaults when config.json is unreadable, and
      those defaults carry no `interaction` block at all - so an unreadable
      config yields `delegate` OFF rather than arming a blocking gate.

      ONLY A REAL BOOLEAN IS A SETTING. This is Test-LwgFlag's rule
      (lib\common.ps1), and it is here because it MUST be the same rule -
      Test-LwgFlag is what the gate reads and this is what /lw-watchtower:delegate
      prints. While this line was a bare [bool] and Test-LwgFlag was not,
      `"delegate": "false"` made this command report ON for a config the gate
      read as OFF: a reporter that disagrees with the reader, which is the
      founding defect this plugin exists to catch, shipped inside the plugin
      itself.

      An ignored global leaves $Default, exactly as an absent one does, and the
      fact is logged through Write-LwgInvalidFlag - the same helper Test-LwgFlag
      uses, so one broken config produces one kind of record. The caller also
      NAMES it on screen, next to the state it is printing.
    #>
    param($Config, [string]$Block, [string]$Key, $Default)
    try {
        $v = $Config.$Block.$Key
        if ($null -ne $v) {
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

      A NON-BOOLEAN OVERRIDE RETURNS $null FOR THE SAME REASON, and $null here
      already means the right thing: the override is not applied and the global
      stands. That is precisely Test-LwgFlag's "ignored at that scope -
      resolution continues as if that level had said nothing", which matters
      most in the direction that costs something: a garbage per-repo override
      must NOT disarm a global `true` an operator did arm. Logged through
      Write-LwgInvalidFlag, and named on screen by the caller.
    #>
    param($Config, [string]$Repo, [string]$Block, [string]$Key)
    if ([string]::IsNullOrWhiteSpace($Repo)) { return $null }
    try {
        $o = $Config.repos.$Repo
        if ($null -eq $o) { return $null }
        $v = $o.$Block.$Key
        if ($null -ne $v) {
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
      Is this flag on, given the resolved value? The value IS the answer.

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
    if ($Value -is [bool]) { return $Value }
    Write-LwgInvalidFlag -Block ([string]$Spec.block) -Key ([string]$Spec.key) -Scope 'resolved' -Value $Value
    return [bool]$Spec.default
}

function Write-Wrapped {
    <#
      Print $Text at $Width, indented by $Indent, breaking on spaces only.
      A plain loop rather than a regex: the lookbehind-with-\G trick that does
      this in one expression is unreadable, and this text is read by an operator
      who has just armed a gate that will refuse their next edit.
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
    param([string]$FlagName, [string]$Bad)
    if ($null -ne $Bad -and $Bad -ne '') {
        Write-Output ("Not a value this command accepts: '{0}'" -f $Bad)
    }
    $c = "/lw-watchtower:$FlagName"
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

    # --- validate the argument BEFORE reading anything ---------------------
    # $want is $true/$false; $null means "no argument was given, report only".
    $want = $null
    $raw  = if ($null -eq $Value) { '' } else { $Value.Trim() }
    if ($raw -ne '') {
        switch ($raw.ToLowerInvariant()) {
            'on'  { $want = $true }
            'off' { $want = $false }
            default {
                Show-Usage -FlagName $Flag -Bad $raw
                exit 2
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
            $Flag, $(if ($raw) { $raw } else { 'on|off' }))
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

    $beforeGlobal = Get-LwgPrefGlobal -Config $cfg -Block $block -Key $key -Default $spec.default
    $beforeRepo   = Get-LwgPrefRepo   -Config $cfg -Repo $repo -Block $block -Key $key
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

        $leaf = if ($want) { 'true' } else { 'false' }
        if ($Scope -eq 'repo' -and $null -eq $beforeRepo) {
            $changeLine = ("repo override CREATED for {0}: {1}" -f $repo, $(if ($want) { 'on' } else { 'off' }))
        } elseif ($wasHere -eq $want) {
            $changeLine = ("no change - the {0} value was already {1}" -f $Scope, $(if ($want) { 'on' } else { 'off' }))
        } else {
            $changeLine = ("{0}: {1} -> {2}" -f $Scope, $(if ($wasHere) { 'on' } else { 'off' }), $(if ($want) { 'on' } else { 'off' }))
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
        $wouldGlobal = Get-LwgPrefGlobal -Config $parsed -Block $block -Key $key -Default $spec.default
        $wouldRepo   = Get-LwgPrefRepo   -Config $parsed -Repo $repo -Block $block -Key $key
        $wouldHere   = if ($Scope -eq 'repo') { $wouldRepo } else { $wouldGlobal }
        if ((Test-LwgFlagOn -Spec $spec -Value $wouldHere) -ne $want) {
            throw ("the edited text does not read back as {0} - so nothing was written" -f $(if ($want) { 'on' } else { 'off' }))
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
        $afterGlobal  = Get-LwgPrefGlobal -Config $cfg -Block $block -Key $key -Default $spec.default
        $afterRepo    = Get-LwgPrefRepo   -Config $cfg -Repo $repo -Block $block -Key $key
        $writtenHere  = if ($Scope -eq 'repo') { $afterRepo } else { $afterGlobal }
        $readBackBad  = ((Test-LwgFlagOn -Spec $spec -Value $writtenHere) -ne $want)
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
            $reads = if (Test-LwgFlagOn -Spec $spec -Value $writtenHere) { 'on' } else { 'off' }
            $asked = if ($want) { 'on' } else { 'off' }
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
    $afterEffOn = (Test-LwgFlagOn -Spec $spec -Value $afterEff)
    $shown = {
        param($v)
        if (Test-LwgFlagOn -Spec $spec -Value $v) { 'on' } else { 'off' }
    }

    # --- report -------------------------------------------------------------
    Write-Output ("{0} is {1}    ({2})" -f $Flag, $(if ($afterEffOn) { 'ON' } else { 'OFF' }), $spec.summary)
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
    Write-Output ("  effective here : {0}" -f $(if ($afterEffOn) { 'ON' } else { 'OFF' }))
    Write-Output ("  stored in      : {0} -> {1}.{2}" -f $cfgPath, $block, $key)
    if ($backup) {
        # Printed for the same reason /lw-watchtower:config prints it
        # (bin\lwg-config.ps1:443): a backup nobody is told about is not a
        # recovery mechanism. Nothing deletes these, ever.
        Write-Output ("  backup         : {0}   [the file as it was before this run]" -f $backup)
    }
    Write-Output ("  config source  : {0}" -f $(if ($cfg._source -eq 'file') { 'config.json' } else { 'BUILT-IN DEFAULTS - config.json is unreadable, so what you see is the fallback' }))

    # A value this script cannot read is NAMED, and that is not politeness. The
    # state printed above is the one the reader reaches - Test-LwgFlag in
    # lib\common.ps1 applies the same boolean-only rule - so without this block
    # an operator who wrote `"delegate": "false"` sees OFF, is told nothing, and
    # still has the string in their config for the next reader to disagree about.
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

    Write-Output ''
    Write-Output 'IN EFFECT FROM NOW ON, in this session:'
    Write-Output ''
    Write-Wrapped -Text $(if ($afterEff) { $spec.onText } else { $spec.offText }) -Indent '  '
    Write-Output ''
    # The heading is the first thing read, so a switch that prints ENFORCED
    # while enforcing nothing would be the loudest possible lie this command
    # could tell about itself. It is guarded on $spec.wired rather than printed
    # unconditionally: a flag added to the table with no `wired` block prints
    # NOTHING here, which is visibly wrong rather than quietly wrong. The
    # alternative heading, NOT WIRED, went with the two flags that needed it -
    # the output-style pair - and is deliberately not kept as dead prose: an
    # unwired switch has no business being in this table at all.
    if ($spec.wired) {
        Write-Output 'ENFORCED - what this switch actually blocks, and what that costs'
        Write-Output ''
        foreach ($line in @($spec.wired)) { Write-Output ("  {0}" -f $line) }
    }

    # The banner number DOES move for this one, and saying otherwise would make
    # the operator distrust the count when it changed under them. There is no
    # "not a governance module" counterpart any more: every flag left in this
    # table is one.
    #
    # The last line named a slash command that reported gates shipped against
    # gates live. It names the SessionStart banner instead, because that command
    # is being removed in the same pass this text is written in and a signpost
    # to a command that does not exist is what bin\lwg-doctor.ps1's `commands`
    # check fails on - see the header on the dead names.
    Write-Output ''
    Write-Output ("  A governance module. {0} is the switch on delegate_gate in the module" -f $Flag)
    Write-Output '  registry in lib/common.ps1 - kind "gate", the only one - so the banner counts it'
    Write-Output '  and the live-gate count moves with it. Its FLAG stays out of the "modules" block'
    Write-Output '  on purpose: one gate must have one switch, and Get-LwgConfig fails OPEN, which'
    Write-Output '  would arm a blocking hook off an unreadable config. The SessionStart banner'
    Write-Output '  reports gates shipped and gates live as separate numbers; start a new session,'
    Write-Output '  or read interaction.delegate in config.json, to see this land.'

    exit 0

} catch {
    if ($script:LwgVerified) {
        # THE WRITE HAPPENED AND WAS VERIFIED; WHAT FAILED IS THE REPORT AFTER IT.
        # Exit 3 here would state, in the words of this file's own table and of
        # commands\delegate.md, that config.json was not changed - and it was.
        # Until 3 August 2026 that is exactly what happened: with USERPROFILE
        # unset, `Join-Path $env:USERPROFILE '.claude\settings.json'` in the
        # output-style ACTIVATION block threw under $ErrorActionPreference='Stop'
        # and the toggle exited 3 on a file it had just rewritten. (That command
        # is named without its leading slash - see the header.)
        #
        # THE ACTIVATION BLOCK IS GONE AND THIS GUARD STAYS, because it was
        # never a patch on that Join-Path: it guards the CLASS of a report that
        # throws over a file that was written, and hardening one line would only
        # have left the next one to reopen the same hole.
        #
        # NOTHING DETERMINISTIC REACHES IT NOW, and that is stated rather than
        # dressed up: every line printed after $script:LwgVerified is set is a
        # Write-Output over values already resolved, and the two accessors that
        # could reach Write-LwgInvalidFlag ran BEFORE it was set and swallow
        # their own faults. The read-back handler above is kept on the same
        # terms. What a caller needs from the exit code is whether the file
        # changed; it did, so this is 0, and the reporting fault is named rather
        # than swallowed - by whichever report line reopens this, not by this one.
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
