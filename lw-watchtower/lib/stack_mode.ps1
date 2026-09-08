#requires -version 5
<#
  LW-WATCHTOWER stack_mode - ONE working discipline per session, injected as a
  POINTER to the ruleset rather than as the ruleset.

  Registered TWICE in hooks/hooks.json, in exec form, with -HookEvent:
      SessionStart   the parent reads it once
      SubagentStart  every worker reads it per dispatch, because CLAUDE.md is
                     snapshotted at PARENT-SESSION start and a worker dispatched
                     later would otherwise read a stale mode

  THIS HEADER IS SHORT ON PURPOSE, and that is a measurement rather than a
  style. Windows PowerShell 5.1 tokenises a whole script before it runs a
  statement, so prose here is charged ON EVERY DISPATCH: ~10 ms of slice 0's
  18 ms was comment text. The long account of this module - the precedence
  ladder, what each mode asserts, what it deliberately does not do - is in
  docs/modules.md, which costs nothing to run.

  THE FIVE CONSTRAINTS INHERITED FROM lib/subagent_start.ps1, whose header
  carries the measurements: no dot-sourcing common.ps1 and no JSON engine on the
  hot path (ConvertFrom-Json costs 141-182 ms in a fresh process); a hand-built
  envelope with deliberately NO `decision`, `continue` or `stopReason` field, so
  this cannot interfere with a session or a dispatch by construction rather than
  by intent; OFF MEANS SILENT - no envelope, no log, no state, nothing written
  anywhere by any path in this file; the payload path is DERIVED and never
  literal; and the two events emit DIFFERENT hookEventName values, which is why
  the file takes -HookEvent.

  WHAT IT COSTS, one machine's medians, 25 interleaved rounds against a floor
  script that only exits 0, leg order reversed on alternate iterations and one
  warm-up sweep discarded: floor 296 ms, this hook 471 ms on SessionStart and
  464 ms on SubagentStart, lib/subagent_start.ps1 435 ms for comparison. So
  ~170 ms is this script's own work, against the precedent's ~140 ms, and it
  does one thing more - three depth-aware span scans of a ~31 KB config.json
  rather than two, plus the mode resolution. Read those as three figures with
  a run-to-run spread of tens of milliseconds, not as three significant digits.
  docs/modules.md carries the per-stage breakdown.

  WHERE IT DEPARTS FROM THAT PRECEDENT, stated here because it is the one thing
  a reader would otherwise assume wrongly. context_injection injects invariant
  text and therefore fails OPEN on a config it cannot read. This module injects
  an ASSERTION ABOUT THE OPERATOR'S ENVIRONMENT, and a mode announced from a
  config that could not be read is a guess wearing a verdict's clothes - the
  "reported 0 orphans unconditionally for its entire life" shape recorded at
  lib/supervisor.ps1. So: a config.json that is absent, unreadable, or holds no
  root `modules` object produces SILENCE. Inside a config that DOES parse that
  far, an absent `stack_mode` key still reads as ON, exactly like every other
  module.
#>

[CmdletBinding()]
param(
    # Which registration is calling. The envelope's hookEventName is mandatory
    # and event-specific, so one script serving two events must be told which.
    # The default is the SessionStart half; hooks/hooks.json passes both
    # explicitly and nothing here relies on the default.
    [string]$HookEvent = 'SessionStart'
)

$ErrorActionPreference = 'Stop'

$LwgModuleName = 'stack_mode'

# The two rulesets, relative to the payload root. They live under context/ and
# NOT under skills/, by owner ruling: the CLI auto-registers every
# skills/*/SKILL.md as model-invocable, and this module governs INJECTION, not
# availability. Nothing else in this tree reads these two files.
$LwgProtoRel = 'context\stack\ponytail.md'
$LwgShipRel  = 'context\stack\unlazy.md'

# The marker file an operator drops in a working directory to pin one tree's
# mode. Read from the payload's cwd only - never walked up for, because a marker
# found three directories above the work would govern sibling trees that never
# opted in.
$LwgMarkerName = '.stackmode'

# The environment variable that outranks everything. proto | ship | off.
$LwgEnvName = 'CLAUDE_STACK_MODE'

# The three answers. Anything else read from any source is not an answer and
# falls through to the next source rather than raising.
$LwgModes = @('proto', 'ship', 'off')

# The only characters brace matching has to stop on - see the same constant in
# lib/subagent_start.ps1, from which these three scanners are ported.
$LwgScanChars = [char[]]@('"', '{', '}', '[', ']', '\')

# Control characters the Replace chain in ConvertTo-LwgJsonString does not
# cover. \b \f \n \r \t are handled directly and are absent from this list.
$LwgOddControls = [char[]]@(
    0, 1, 2, 3, 4, 5, 6, 7, 11, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
    25, 26, 27, 28, 29, 30, 31, 127
)

# stdin is drained but NOT parsed on the fast path. The raw text is kept because
# a pipe is consumed exactly once and the escalation cannot read it again.
$LwgStdinRaw = ''

function Get-LwgRootLocal {
    <#
      Plugin root. Same rule as Get-LwgPluginRoot in common.ps1, duplicated
      rather than dot-sourced, and written with [IO.Directory]::Exists /
      [IO.Path]::GetDirectoryName so two path operations do not drag in a cmdlet
      module. DERIVED, never literal: a literal install path trips
      tests/portability_scan.ps1's plugin-install-path rule.
    #>
    if ($env:CLAUDE_PLUGIN_ROOT -and [System.IO.Directory]::Exists($env:CLAUDE_PLUGIN_ROOT)) {
        return $env:CLAUDE_PLUGIN_ROOT
    }
    return [System.IO.Path]::GetDirectoryName($PSScriptRoot)
}

function Get-LwgJsonObjectSpan {
    <#
      The character span of the OBJECT value of member "$Key" at DEPTH 1 of
      $Text, as a HASHTABLE @{ start; end } - end exclusive - or $null.

      A hashtable deliberately: PowerShell enumerates a returned collection but
      not a returned hashtable. Get-LwgRepoInfo in common.ps1 carries the long
      version of that trap.

      Ported from lib/subagent_start.ps1, where the depth rule is a fix rather
      than a flourish: without it the scan returned config.json's per-repo
      `modules` block as the global one and answered the wrong question.

      BRACKETS MOVE NO DEPTH HERE. They are in the jump set only so an array
      value is stepped over cleanly; object depth is braces alone, which is what
      the member rule below is stated in terms of.
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
            # Inside a string a backslash escapes the next character, quote
            # included - skip both, or \" reads as the end of the string.
            if ($ch -eq '\') { $p += 2; continue }
            if ($ch -eq '"') { $end = $p; break }
            $p++
        }
        if ($end -lt 0) { return $null }

        if ($depth -eq 1 -and ($end - $k - 1) -eq $Key.Length -and
            [string]::CompareOrdinal($Text, ($k + 1), $Key, 0, $Key.Length) -eq 0) {
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
        # Not the member, or its value is not an object. A string cannot move
        # the depth, so carry on from after it.
        $k = $end + 1
    }
    return $null
}

function Get-LwgJsonBool {
    <#
      $true / $false for member "$Key" wherever it appears in $Text with a
      literal boolean value, or $null when it appears nowhere with one.

      $null is a THIRD answer and the caller treats it as one: absent is not
      false. A bare name in an array is not followed by a colon and so never
      matches, which is why the colon is looked for rather than just the name.
    #>
    param([string]$Text, [string]$Key)

    if ([string]::IsNullOrEmpty($Text) -or [string]::IsNullOrEmpty($Key)) { return $null }

    $needle = '"' + $Key + '"'
    $i = $Text.IndexOf($needle, [StringComparison]::Ordinal)
    while ($i -ge 0) {
        $after = $i + $needle.Length
        $colon = $Text.IndexOf(':', $after)
        if ($colon -ge 0 -and $Text.Substring($after, ($colon - $after)).Trim().Length -eq 0) {
            $tail = $Text.Substring(($colon + 1), [Math]::Min(16, ($Text.Length - $colon - 1))).TrimStart()
            # A STRING value beginning 'true' cannot match: TrimStart leaves its
            # opening quote in front of it.
            if ($tail.StartsWith('true',  [StringComparison]::Ordinal)) { return $true }
            if ($tail.StartsWith('false', [StringComparison]::Ordinal)) { return $false }
        }
        $i = $Text.IndexOf($needle, $i + 1, [StringComparison]::Ordinal)
    }
    return $null
}

function Get-LwgJsonStringLiteral {
    <#
      The DECODED value of the JSON string literal that begins at $Start in
      $Text (which must be its opening quote), plus the index just past its
      closing quote, as @{ value; next } - or $null if it is unterminated.

      Decoding is CHECKED rather than assumed: a literal with no backslash IS
      its value and comes back from one Substring; only an escaped one pays for
      the loop. A Windows path in a `cwd` is the ordinary escaped case.
    #>
    param([string]$Text, [int]$Start)

    $len  = $Text.Length
    $v    = $Start + 1
    $vend = -1
    while ($v -ge 0 -and $v -lt $len) {
        $v = $Text.IndexOfAny($script:LwgScanChars, $v)
        if ($v -lt 0) { break }
        $cv = $Text[$v]
        if ($cv -eq '\') { $v += 2; continue }
        if ($cv -eq '"') { $vend = $v; break }
        # A brace or a bracket inside a string moves nothing and ends nothing.
        $v++
    }
    if ($vend -lt 0) { return $null }

    $lit = $Text.Substring(($Start + 1), ($vend - $Start - 1))
    if ($lit.IndexOf('\') -lt 0) { return @{ value = $lit; next = ($vend + 1) } }

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
                # A decoder, not a validator. Kept verbatim; nothing downstream
                # re-emits it.
                [void]$sb.Append('\u')
            }
        }
        else { [void]$sb.Append('\'); [void]$sb.Append($e) }
    }
    return @{ value = $sb.ToString(); next = ($vend + 1) }
}

function Get-LwgJsonMemberStart {
    <#
      The index of the first character of the VALUE of member "$Key" at DEPTH 1
      of $Text, or -1. Whitespace between the colon and the value is skipped, so
      the caller reads the value's opening character and decides what it is.

      One walker serving both a string member and an array member, because the
      only thing that differs between them is what the caller does at the index
      this returns.

      IT DOES NOT STEP OVER AN ARRAY VALUE, AND THE CONSEQUENCE IS MEASURED
      RATHER THAN LEFT TO BE FOUND. Brackets move no depth here, so a STRING
      ELEMENT inside a depth-1 array is compared against $Key like any member
      name. A payload of the shape

          {"tools":["cwd"],"cwd":"C:\\real\\dir"}

      therefore stops on the array element, finds no colon after it, and returns
      -1 - which is the "the member is here and its value is unreadable" answer
      the branch below already gives. So the worst case is DEGRADED, never
      WRONG: the caller gets no cwd and the mode falls through to the next
      source, and the decoy's text is never returned as a cwd. Checked, in the
      shapes that matter - an array BEFORE the member with no collision resolves
      correctly, an array after it resolves correctly, and a same-named member
      nested one level deeper is correctly ignored in favour of the depth-1 one.
      tests/stack_mode.ps1's S15 pins the degradation.

      Stepping over array values properly would mean a bracket-depth counter
      beside the brace one, on a per-dispatch hook, to improve an outcome that
      is already a documented fall-through. It is not done, and this is the
      note rather than the code.
    #>
    param([string]$Text, [string]$Key)

    if ([string]::IsNullOrEmpty($Text) -or [string]::IsNullOrEmpty($Key)) { return -1 }

    $len   = $Text.Length
    $depth = 0
    $k     = 0
    while ($k -ge 0 -and $k -lt $len) {
        $k = $Text.IndexOfAny($script:LwgScanChars, $k)
        if ($k -lt 0) { break }
        $c = $Text[$k]
        if ($c -eq '{') { $depth++; $k++; continue }
        if ($c -eq '}') { $depth--; $k++; continue }
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
        if ($end -lt 0) { return -1 }

        if ($depth -eq 1 -and ($end - $k - 1) -eq $Key.Length -and
            [string]::CompareOrdinal($Text, ($k + 1), $Key, 0, $Key.Length) -eq 0) {
            $colon = $Text.IndexOf(':', $end + 1)
            if ($colon -ge 0 -and $Text.Substring(($end + 1), ($colon - $end - 1)).Trim().Length -eq 0) {
                $q = $colon + 1
                while ($q -lt $len -and [char]::IsWhiteSpace($Text[$q])) { $q++ }
                if ($q -lt $len) { return $q }
            }
            # The member is here and its value is unreadable. That is an answer,
            # not a reason to keep looking.
            return -1
        }
        $k = $end + 1
    }
    return -1
}

function Get-LwgJsonString {
    <# The decoded string value of member "$Key" at depth 1 of $Text, or $null. #>
    param([string]$Text, [string]$Key)
    $at = Get-LwgJsonMemberStart -Text $Text -Key $Key
    if ($at -lt 0 -or $Text[$at] -ne '"') { return $null }
    $lit = Get-LwgJsonStringLiteral -Text $Text -Start $at
    if ($null -eq $lit) { return $null }
    return $lit.value
}

function Get-LwgJsonStringArray {
    <#
      The decoded string elements of the ARRAY member "$Key" at depth 1 of
      $Text, as a hashtable @{ items = @(...) } - or $null when the member is
      absent or its value is not an array.

      A HASHTABLE for the same reason Get-LwgJsonObjectSpan returns one: an
      empty array returned bare is unrolled away by PowerShell and would be
      indistinguishable from "no such member", which is exactly the distinction
      the caller needs. `"ship_roots": []` means the operator declared no ship
      roots; an absent key means they declared nothing at all.

      NON-STRING ELEMENTS ARE SKIPPED, not fatal: this reads a list of path
      prefixes, and a number in it is a typo the operator can see rather than a
      reason to refuse to resolve the session's mode.
    #>
    param([string]$Text, [string]$Key)

    $at = Get-LwgJsonMemberStart -Text $Text -Key $Key
    if ($at -lt 0 -or $Text[$at] -ne '[') { return $null }

    # ::new() AND NOT New-Object, WHICH WAS MEASURED RATHER THAN PREFERRED.
    # New-Object is a cmdlet, and its first use in a fresh process loads
    # Microsoft.PowerShell.Utility. One line, measured on one machine, 25
    # interleaved rounds against a floor script that only exits 0:
    #
    #     New-Object here   median 530 ms   mode-resolution leg ~84 ms
    #     ::new() here      median 468 ms   mode-resolution leg ~60 ms
    #
    # So the cmdlet cost ~60 ms of the whole run for one object, and the leg is
    # ~60 ms even without it - most of what remains is PowerShell compiling the
    # seven functions this leg calls for the first time, which is a cost of
    # having the functions and not of calling them twice.
    # lib/subagent_start.ps1's header states the no-cmdlet rule; this is a
    # measurement of what breaking it costs.
    $items = [System.Collections.ArrayList]::new()
    $len   = $Text.Length
    $i     = $at + 1
    while ($i -lt $len) {
        $ch = $Text[$i]
        if ($ch -eq ']') { return @{ items = @($items.ToArray()) } }
        if ($ch -eq '"') {
            $lit = Get-LwgJsonStringLiteral -Text $Text -Start $i
            if ($null -eq $lit) { return $null }
            [void]$items.Add([string]$lit.value)
            $i = $lit.next
            continue
        }
        # A nested array or object inside a list of path prefixes is not
        # something this reader has an answer for, and guessing past it could
        # swallow the closing bracket.
        if ($ch -eq '[' -or $ch -eq '{') { return $null }
        $i++
    }
    return $null
}

function ConvertTo-LwgJsonString {
    <#
      One JSON string literal, quotes included, built by hand. ConvertTo-Json
      would be correct and would cost the same first-use warm-up as
      ConvertFrom-Json, which is the whole reason this script is fast.

      TWO paths, and the fast one is not the trusting one: a UTF-8 byte count
      that differs from the character count proves a character above U+007F, and
      IndexOfAny finds the controls the Replace chain does not cover. Either
      sends the string to the exact escaper, which emits \uXXXX for everything
      outside printable ASCII - so the output is pure ASCII whatever the payload
      and whatever the console code page.
    #>
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return '""' }

    $needsExact = ($Text.Length -ne [System.Text.Encoding]::UTF8.GetByteCount($Text)) -or
                  ($Text.IndexOfAny($script:LwgOddControls) -ge 0)

    if (-not $needsExact) {
        # Backslash FIRST: escaping it afterwards would double-escape the
        # backslashes the other replacements introduce.
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

function ConvertTo-LwgModeWord {
    <#
      One of proto | ship | off, or '' when $Raw is not one of them.

      NOT AN ERROR. Every source that can carry a mode is operator-written, and
      an unrecognised value falls through to the next source rather than raising
      - a typo in an environment variable must not cost the session its mode
      entirely, and it must certainly not stop the hook.
    #>
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return '' }
    $w = $Raw.Trim().ToLowerInvariant()
    if ($script:LwgModes -contains $w) { return $w }
    return ''
}

function Test-LwgUnderRoot {
    <#
      Is $Path inside $Root, or $Root itself?

      SEGMENT-AWARE, and that is the whole reason this is a function rather than
      a StartsWith at the call site: 'C:\work\api' must not be read as inside
      'C:\work\ap'. Both sides are normalised to backslashes and stripped of
      trailing separators first, and the comparison is
      OrdinalIgnoreCase because Windows paths are case-insensitive.

      NOTHING IS RESOLVED OR PROBED. No Resolve-Path, no GetFullPath, no
      Test-Path: this runs before anything is injected, on every dispatch, and a
      path probe's worst case is its normal case. A root written with a trailing
      slash, or with forward slashes, still matches; a relative root, a UNC
      spelling of a mapped drive, or a junction pointing at the same tree does
      not, and that limit is stated in docs/modules.md rather than papered over.
    #>
    param([string]$Path, [string]$Root)

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
    $p = $Path.Trim().Replace('/', '\').TrimEnd('\')
    $r = $Root.Trim().Replace('/', '\').TrimEnd('\')
    if ($r.Length -eq 0 -or $p.Length -lt $r.Length) { return $false }
    if ([string]::Compare($p, 0, $r, 0, $r.Length, [StringComparison]::OrdinalIgnoreCase) -ne 0) { return $false }
    if ($p.Length -eq $r.Length) { return $true }
    return ($p[$r.Length] -eq '\')
}

function Get-LwgMarkerMode {
    <#
      The mode written in $Dir\.stackmode, or '' when there is no such file, it
      cannot be read, or it says nothing this module recognises.

      The file contract, the same one context/worker_facts.md uses: blank lines
      and lines whose first non-space character is '#' are dropped; the FIRST
      remaining line is the answer. So an operator can explain the choice in the
      file above the word that makes it.
    #>
    param([string]$Dir)

    if ([string]::IsNullOrWhiteSpace($Dir)) { return '' }
    try {
        $path = [System.IO.Path]::Combine($Dir, $script:LwgMarkerName)
        if (-not [System.IO.File]::Exists($path)) { return '' }
        $raw = [System.IO.File]::ReadAllText($path)
        if ([string]::IsNullOrWhiteSpace($raw)) { return '' }
        # .Split on a char rather than -split "`r?`n": the latter is a regex,
        # and first use of the regex engine in a fresh process costs more than
        # everything else this script does put together.
        foreach ($line in $raw.Split([char]10)) {
            $t = $line.TrimEnd([char]13).Trim()
            if ($t.Length -eq 0)     { continue }
            if ($t[0] -eq [char]'#') { continue }
            return (ConvertTo-LwgModeWord -Raw $t)
        }
    } catch { }
    return ''
}

function Get-LwgStackPointer {
    <#
      The text handed to the model for $Mode, or '' when the ruleset that text
      would point at is not in this payload.

      A POINTER AND NOT THE PAGE - owner ruling, 6 September 2026. A full
      SKILL.md does not fit inside the ceiling lib/subagent_start.ps1 applies to
      injected context, and a session that reads the ruleset off disk reads the
      CURRENT one rather than a copy frozen into a hook.

      THE FILE IS PROBED BEFORE IT IS NAMED. A pointer to a page that is not
      there is the defect this module was built to prevent, so an absent ruleset
      produces silence rather than an instruction the reader cannot follow.

      THE SHIP POINTER SAYS WHAT IS MISSING FROM ITS OWN RULESET, and that is a
      standing obligation rather than a nicety. Only unlazy's SKILL.md is
      vendored here - its scripts, templates, references and agents are not, and
      this plugin ships no Node runtime - so a worker told to read that page
      without being told that would be handed instructions it cannot execute.
    #>
    param([string]$Mode, [string]$Root, [string]$Source)

    $rel = if ($Mode -eq 'ship') { $script:LwgShipRel } else { $script:LwgProtoRel }
    $abs = [System.IO.Path]::Combine($Root, $rel)
    if (-not [System.IO.File]::Exists($abs)) { return '' }

    if ($Mode -eq 'ship') {
        return @(
            "LW-WATCHTOWER stack mode: SHIP (resolved from $Source).",
            'Completion discipline governs this session. Before starting substantial work, read',
            "  $abs",
            'and follow it: write the acceptance gates before executing, decompose the work with',
            'the Depth Tree, and re-verify the evidence before reporting anything done.',
            'READ THAT FILE AS A METHOD, NOT AS COMMANDS. Only its SKILL.md is vendored into this',
            'plugin. The scripts, templates, references and agents it names - gate-check.mjs,',
            'gate-lint.mjs, install-hooks.mjs, gates-leaf.md, PLAN.md, gates-node.md and every',
            'references page - are NOT in this payload, and this plugin ships no Node runtime, so',
            'the node invocations in it cannot be run here. Write the gate ledger yourself and',
            'check each gate yourself.',
            'This is a pointer, not the ruleset. Read the file; do not act on this summary alone.'
        ) -join "`n"
    }

    return @(
        "LW-WATCHTOWER stack mode: PROTO (resolved from $Source).",
        'Prototyping discipline governs this session. Before writing code, read',
        "  $abs",
        'and follow it: the laziest solution that actually works. Question whether the task needs',
        'to exist at all, reach for the standard library before custom code and for native',
        'platform features before a dependency, and prefer one line to fifty.',
        'This is a pointer, not the ruleset. Read the file; do not act on this summary alone.'
    ) -join "`n"
}

try {
    # 1. Drain stdin. Unparsed on the fast path - parsing it would cost the
    #    141-182 ms ConvertFrom-Json warm-up for one field. Decoded as UTF-8
    #    explicitly and NOT through [Console]::In, whose encoding is the
    #    console's input code page and not the payload's, so a cwd carrying one
    #    non-ASCII byte would arrive mojibaked.
    try {
        $LwgStdinReader = [IO.StreamReader]::new([Console]::OpenStandardInput(), [Text.UTF8Encoding]::new($false), $true)
        try { $LwgStdinRaw = $LwgStdinReader.ReadToEnd() } finally { $LwgStdinReader.Dispose() }
    } catch { $LwgStdinRaw = '' }

    $root    = Get-LwgRootLocal
    $cfgPath = [System.IO.Path]::Combine($root, 'config.json')

    $rawCfg = ''
    try {
        if ([System.IO.File]::Exists($cfgPath)) { $rawCfg = [System.IO.File]::ReadAllText($cfgPath) }
    } catch { $rawCfg = '' }

    # 2. THE FLAG, AND THE ONE PLACE THIS MODULE DOES NOT FAIL OPEN.
    #    See the header. No readable root `modules` object means nothing
    #    answered, and a mode announced on the strength of nothing is a guess.
    #    Inside a config that parses this far, an absent key is still ON.
    if ([string]::IsNullOrWhiteSpace($rawCfg)) { exit 0 }
    $modSpan = Get-LwgJsonObjectSpan -Text $rawCfg -Key 'modules'
    if ($null -eq $modSpan) { exit 0 }

    $modText = $rawCfg.Substring($modSpan.start, ($modSpan.end - $modSpan.start))
    $enabled = $true
    $v = Get-LwgJsonBool -Text $modText -Key $LwgModuleName
    if ($null -ne $v) { $enabled = [bool]$v }

    # The tuning block, read once. $null here is not "no such block" - it is
    # "this document said nothing about it", and the override below may still.
    $optText  = ''
    $mcSpan   = Get-LwgJsonObjectSpan -Text $rawCfg -Key 'module_config'
    if ($null -ne $mcSpan) {
        $mcText = $rawCfg.Substring($mcSpan.start, ($mcSpan.end - $mcSpan.start))
        $smSpan = Get-LwgJsonObjectSpan -Text $mcText -Key $LwgModuleName
        if ($null -ne $smSpan) { $optText = $mcText.Substring($smSpan.start, ($smSpan.end - $smSpan.start)) }
    }

    # 3. THE OPERATOR OVERRIDE - #11. config.json is the SHIPPED DEFAULTS;
    #    an operator's own choice goes to config.override.json under the state
    #    directory, which Get-LwgConfig merges over them. A hook that read the
    #    defaults alone would go on injecting while the banner, the doctor and
    #    the config command all reported the module off - the silent no-op this
    #    plugin exists to catch, and the exact bug #11 fixed in the sibling hook.
    #
    #    THREE THINGS SEND IT TO THE SLOW PATH INSTEAD OF ANSWERING, each a
    #    place where this scanner and ConvertFrom-Json could disagree: the state
    #    directory not being named in the environment, so the override cannot be
    #    found without common.ps1's ranked discovery; an override whose top
    #    level is not a JSON object, which Get-LwgConfig discards outright; and
    #    the two characters \u anywhere in it, since \uXXXX is the only JSON
    #    escape that can spell a letter and so a member name this scanner cannot
    #    see. A `repos` block naming this module is the fourth - only the slug
    #    can resolve it, and this path never parses one.
    $escalate = $false
    if ([string]::IsNullOrWhiteSpace($env:CLAUDE_PLUGIN_DATA)) {
        $escalate = $true
    } else {
        $ovPath = [System.IO.Path]::Combine($env:CLAUDE_PLUGIN_DATA, 'config.override.json')
        $ovText = ''
        try {
            if ([System.IO.File]::Exists($ovPath)) { $ovText = [System.IO.File]::ReadAllText($ovPath) }
        } catch { $ovText = '' }

        # An EMPTY override is not an override: Get-LwgConfig reports it as such
        # and merges nothing, so the defaults above stand.
        if (-not [string]::IsNullOrWhiteSpace($ovText)) {
            $ovOpen = $ovText.IndexOf('{')
            if ($ovOpen -lt 0 -or
                $ovText.Substring(0, $ovOpen).Trim().Length -ne 0 -or
                $ovText.IndexOf('\u', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $escalate = $true
            } else {
                $ovMod = Get-LwgJsonObjectSpan -Text $ovText -Key 'modules'
                if ($null -ne $ovMod) {
                    $ovModText = $ovText.Substring($ovMod.start, ($ovMod.end - $ovMod.start))
                    $ovVal = Get-LwgJsonBool -Text $ovModText -Key $LwgModuleName
                    if ($null -ne $ovVal) { $enabled = [bool]$ovVal }
                }
                $ovMc = Get-LwgJsonObjectSpan -Text $ovText -Key 'module_config'
                if ($null -ne $ovMc) {
                    $ovMcText = $ovText.Substring($ovMc.start, ($ovMc.end - $ovMc.start))
                    $ovSm = Get-LwgJsonObjectSpan -Text $ovMcText -Key $LwgModuleName
                    # THE MEMBER-BY-MEMBER MERGE Get-LwgConfig performs is not
                    # reproduced here, and this escalates rather than
                    # approximating it: an override that tunes this module is
                    # something an operator wrote by hand, so it is rare, and
                    # getting it subtly wrong would be a mode resolved from half
                    # of two documents.
                    if ($null -ne $ovSm) { $escalate = $true }
                }
                $ovRepos = Get-LwgJsonObjectSpan -Text $ovText -Key 'repos'
                if ($null -ne $ovRepos) {
                    $ovReposText = $ovText.Substring($ovRepos.start, ($ovRepos.end - $ovRepos.start))
                    if ($null -ne (Get-LwgJsonBool -Text $ovReposText -Key $LwgModuleName)) { $escalate = $true }
                }
            }
        }
    }

    # The same `repos` rule over the DEFAULTS, for the same reason.
    $repoSpan = Get-LwgJsonObjectSpan -Text $rawCfg -Key 'repos'
    if ($null -ne $repoSpan) {
        $repoText = $rawCfg.Substring($repoSpan.start, ($repoSpan.end - $repoSpan.start))
        if ($null -ne (Get-LwgJsonBool -Text $repoText -Key $LwgModuleName)) { $escalate = $true }
    }

    # 4. Mode resolution, in precedence order. Each source either ANSWERS or
    #    falls through; nothing below is consulted once one has answered, so the
    #    session has exactly one mode and ponytail and unlazy cannot collide.
    $mode   = ''
    $source = ''

    # 4a. The environment. Outranks everything because it is the only source a
    #     caller can set for one session without editing a tracked file.
    #     Read with [Environment]::GetEnvironmentVariable and not through the
    #     Env: drive: the provider path needs a cmdlet, and an absent variable
    #     read that way is an error to be suppressed rather than an empty string.
    $mode = ConvertTo-LwgModeWord -Raw ([string][Environment]::GetEnvironmentVariable($LwgEnvName))
    if ($mode) { $source = "the $LwgEnvName environment variable" }

    # The cwd, needed by both remaining sources. Read from the payload at depth
    # 1 - a nested member would name something other than the session's working
    # directory. A payload that is not JSON, or carries no cwd, simply leaves
    # both of those sources with nothing to say.
    $cwd = ''
    if (-not $mode) {
        $at = Get-LwgJsonMemberStart -Text $LwgStdinRaw -Key 'cwd'
        if ($at -ge 0 -and $LwgStdinRaw[$at] -eq '"') {
            $lit = Get-LwgJsonStringLiteral -Text $LwgStdinRaw -Start $at
            if ($null -ne $lit) { $cwd = [string]$lit.value }
        }
    }

    # 4b. The marker file in the working directory itself.
    if (-not $mode) {
        $mode = Get-LwgMarkerMode -Dir $cwd
        if ($mode) { $source = "a $LwgMarkerName marker in the working directory" }
    }

    if (-not $escalate -and -not $mode -and $optText) {
        # 4c. The configured path roots. SHIP IS TESTED FIRST AND WINS A TIE,
        #     deliberately: where an operator has nested a ship root inside a
        #     proto root, or listed the same tree twice, the stricter discipline
        #     is the safer thing to be wrong about.
        $shipRoots  = Get-LwgJsonStringArray -Text $optText -Key 'ship_roots'
        $protoRoots = Get-LwgJsonStringArray -Text $optText -Key 'proto_roots'
        if ($cwd -and $null -ne $shipRoots) {
            foreach ($r in $shipRoots.items) {
                if (Test-LwgUnderRoot -Path $cwd -Root $r) { $mode = 'ship'; $source = 'a configured ship root'; break }
            }
        }
        if (-not $mode -and $cwd -and $null -ne $protoRoots) {
            foreach ($r in $protoRoots.items) {
                if (Test-LwgUnderRoot -Path $cwd -Root $r) { $mode = 'proto'; $source = 'a configured proto root'; break }
            }
        }
        # 4d. The configured default for everything else.
        if (-not $mode) {
            $mode = ConvertTo-LwgModeWord -Raw ([string](Get-LwgJsonString -Text $optText -Key 'default'))
            if ($mode) { $source = 'the configured default' }
        }
    }

    if ($escalate) {
        # THE EXACT ANSWER, AT FULL PRICE. Reached only where the fast scan has
        # proved it cannot answer - see step 3. It costs a dot-source and a
        # ConvertFrom-Json, which is most of this script's budget, and it is
        # paid by the operator who wrote the override that made it necessary.
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
        $enabled = Test-LwgModule -Name $LwgModuleName -Config $cfg -Repo $repo
        if (-not $mode) {
            $shipR = @(Get-LwgModuleOption -Config $cfg -Module $LwgModuleName -Key 'ship_roots'  -Default @())
            $proR  = @(Get-LwgModuleOption -Config $cfg -Module $LwgModuleName -Key 'proto_roots' -Default @())
            foreach ($r in $shipR) {
                if (Test-LwgUnderRoot -Path $cwd -Root ([string]$r)) { $mode = 'ship'; $source = 'a configured ship root'; break }
            }
            if (-not $mode) {
                foreach ($r in $proR) {
                    if (Test-LwgUnderRoot -Path $cwd -Root ([string]$r)) { $mode = 'proto'; $source = 'a configured proto root'; break }
                }
            }
            if (-not $mode) {
                $mode = ConvertTo-LwgModeWord -Raw ([string](Get-LwgModuleOption -Config $cfg -Module $LwgModuleName -Key 'default' -Default ''))
                if ($mode) { $source = 'the configured default' }
            }
        }
    }

    # 4e. The built-in answer. PROTO, because a session nobody has said anything
    #     about is more likely to be exploration than a release, and because the
    #     cost of being wrong in this direction is a note the model can ignore
    #     rather than a discipline it was told to skip.
    if (-not $mode) { $mode = 'proto'; $source = 'this module''s built-in default' }

    # 5. OFF MEANS SILENT, both kinds of off: the module switched off, and the
    #    mode resolved to off. No envelope, no log, no state, nothing written.
    if (-not $enabled)   { exit 0 }
    if ($mode -eq 'off') { exit 0 }

    $text = Get-LwgStackPointer -Mode $mode -Root $root -Source $source
    if ([string]::IsNullOrWhiteSpace($text)) { exit 0 }

    # 6. The envelope, hand-built. hookEventName is mandatory - the CLI rejects
    #    the whole output without it - and is the EVENT THIS REGISTRATION SERVES,
    #    which is why -HookEvent exists. There is deliberately no `decision`,
    #    `continue` or `stopReason` field, so this cannot interfere with a
    #    session or a dispatch by construction rather than by intent.
    [Console]::Out.Write('{"hookSpecificOutput":{"hookEventName":' +
                         (ConvertTo-LwgJsonString -Text $HookEvent) +
                         ',"additionalContext":' +
                         (ConvertTo-LwgJsonString -Text $text) +
                         '},"suppressOutput":true}')

} catch {
    # Never break a session or a dispatch. The error record dot-sources
    # common.ps1 and pays a ConvertTo-Json warm-up, which is why it is on the
    # error path alone and nowhere near the happy one.
    try {
        . ([System.IO.Path]::Combine($PSScriptRoot, 'common.ps1'))
        Write-LwgEvent -Event 'StackModeError' -Extra @{
            module = 'stack_mode'; error = $_.Exception.Message } | Out-Null
    } catch { }
}

exit 0
