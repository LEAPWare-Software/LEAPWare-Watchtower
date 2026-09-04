#requires -version 5
<#
  Shared plumbing for the four LIFECYCLE commands - /lw-watchtower:config, :resolve,
  :uninstall and :update.

      . (Join-Path $PSScriptRoot 'lwg-cmdlib.ps1')

  NOT a second lib/common.ps1, and deliberately not part of it. Everything here
  either edits a JSON file in place or spawns a child process, and lib/common.ps1
  was dot-sourced by both PreToolUse gates - a gate that can spawn a process is a
  gate that can hang the tool call it is meant to be guarding, which is the same
  reason lib/stop_advisories.ps1 keeps its own copy of the subprocess plumbing.
  Those two gates were removed on 30 July 2026 and delegate_gate replaced them
  as the only one later the same day, so the hazard is live and the separation
  is load-bearing rather than historical: lib/gate_delegate.ps1 dot-sources
  common.ps1 on the PreToolUse path, and common.ps1 still contains no subprocess
  helper at all. "The gate cannot shell out" is therefore a property of where
  the code lives rather than of anyone remembering not to. Merging this file
  back into common.ps1 would hand the blocking path a process spawner.
  This file is reachable only from bin/, i.e. only from a command the operator
  typed.

  Nothing here is dot-sourced by a hook. Nothing here throws at load time.

  THE JSON EDITOR IS SURGICAL, AND THAT IS THE POINT.
  config.json and ~/.claude/settings.json are files a human reads. A
  ConvertFrom-Json / ConvertTo-Json round-trip would reformat both of them
  wholesale, and on Windows PowerShell 5.1 ConvertTo-Json is backed by
  JavaScriptSerializer, which escapes < > ' and & into \u00xx - so every
  explanatory "$comment" in config.json would come back as unreadable soup and
  every glob in permissions.deny would change shape. So edits below are made as
  text, against a scanner that understands JSON structure well enough to find
  exactly one member, and every edit is re-parsed before it is allowed to be
  written.
#>

# --- a file hash that does not need Get-FileHash (#273) ----------------------
# THE LAST THREE CALL SITES IN THE PAYLOAD. The reasoning for this function is
# written once, in bin\lwg-doctor.ps1 beside its copy, and is not repeated here:
# Get-FileHash is a FUNCTION exported by Microsoft.PowerShell.Utility, not a
# compiled cmdlet, and Windows PowerShell 5.1 loses it whenever it inherits a
# PowerShell 7 PSModulePath - which is every script this plugin spawns for an
# operator who launched Claude Code from a pwsh terminal.
#
# WHY THIS FILE'S THREE SITES WERE THE WORST OF THE SEVEN, and why they were
# found last: all three sit inside a try/catch, so they never threw. They
# DEGRADED. Read-LwgTextFile returned ok = $false with the CommandNotFound
# message in .error, and every caller reported that as "config.json could not be
# read" - so /lw-watchtower:delegate and /lw-watchtower:config exited 3 on a
# correct install, and bin\lwg-uninstall.ps1 (which dot-sources this file)
# completed but reported `hooks`, `statusline-key` and `permissions-deny` as
# UNKNOWN because settings.json was never read. A loud failure gets traced; a
# quiet one gets recorded as a different bug, which is exactly what happened.
#
# ONE COPY SERVES THE TWO COMMANDS THAT HAD NOWHERE ELSE TO GET IT:
# bin\lwg-config.ps1 and bin\lwg-toggle.ps1 dot-source this file and had no
# helper of their own, and bin\lwg-toggle.ps1's read-back hash now resolves to
# this function. bin\lwg-uninstall.ps1 and bin\lwg-update.ps1 dot-source this
# file too and ALSO carry their own identical copy, defined earlier in the file
# than the dot-source - so this definition is the one in scope by the time
# either of them runs, with the same body and the same return. That duplication
# is left rather than tidied: removing it edits two scripts this change has no
# other reason to touch, and an identical function defined twice costs a reader
# a moment while deleting one costs a re-measurement. The doctor and setup load
# neither this file nor each other's - the note in bin\lwg-doctor.ps1 explains
# why there is no one home for all of them.
function Get-LwgFileSha256 {
    <#
      SHA256 of one file as uppercase hex, with no PowerShell module behind it.
      Throws what the file system throws, exactly as Get-FileHash did, so every
      caller's try/catch keeps its meaning - and the return is byte for byte
      what (Get-FileHash -Algorithm SHA256).Hash returned, so every comparison
      and every printed value is unchanged.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)

    # ABSOLUTE, ALWAYS. Every .NET call resolves a relative path against the
    # PROCESS working directory, which is wherever the operator ran this from
    # and not this tree.
    $full = [IO.Path]::GetFullPath($Path)
    $sha  = [System.Security.Cryptography.SHA256]::Create()
    try {
        # FileShare::ReadWrite because settings.json is rewritten by the CLI
        # underneath whatever is reading it. Get-FileHash opens the same way;
        # a narrower share would fail on files that used to hash fine.
        $fs = [IO.File]::Open($full, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try { $bytes = $sha.ComputeHash($fs) } finally { $fs.Dispose() }
    } finally { $sha.Dispose() }
    return [BitConverter]::ToString($bytes).Replace('-', '')
}

# --- JSON structural scanner ------------------------------------------------
# Enough JSON to LOCATE a member. Not a parser: it never builds a value, it only
# answers "where in this text does that member live". String state and nesting
# depth are tracked, so a key name that also appears inside a comment string or
# inside a nested object cannot be matched by accident - config.json contains
# every module name twice over inside $status.implemented, and a naive IndexOf
# would happily edit one of those.

function Get-LwgJsonSpan {
    <#
      Index of the bracket matching the one at $Open, or -1 when the text is
      unbalanced. $Open must be the index of a '{' or '['.
    #>
    param([string]$Text, [int]$Open)

    if ($Open -lt 0 -or $Open -ge $Text.Length) { return -1 }
    $close = if ($Text[$Open] -eq '{') { '}' } elseif ($Text[$Open] -eq '[') { ']' } else { $null }
    if ($null -eq $close) { return -1 }

    $depth = 0
    $i = $Open
    while ($i -lt $Text.Length) {
        $c = $Text[$i]
        if ($c -eq '"') { $i = Get-LwgJsonStringEnd -Text $Text -Start $i; continue }
        if ($c -eq '{' -or $c -eq '[') { $depth++ }
        elseif ($c -eq '}' -or $c -eq ']') {
            $depth--
            if ($depth -eq 0) { return $i }
        }
        $i++
    }
    return -1
}

function Get-LwgJsonStringEnd {
    <#
      Index just PAST the string literal that starts at $Start (which must be its
      opening quote). Backslash escapes are honoured, so a \" inside the string
      does not end it. Returns $Text.Length for an unterminated string, which
      makes every caller run off the end and fail rather than loop.
    #>
    param([string]$Text, [int]$Start)

    $i = $Start + 1
    while ($i -lt $Text.Length) {
        $c = $Text[$i]
        if ($c -eq '\') { $i += 2; continue }
        if ($c -eq '"') { return $i + 1 }
        $i++
    }
    return $Text.Length
}

function Find-LwgJsonMember {
    <#
      Locate one member of the object whose opening '{' is at $ObjStart. Returns
      a HASHTABLE (so it survives the function boundary un-enumerated, like every
      other structure-returning helper in this repo):

        @{ found; key_start; key_end; value_start; value_end; member_end; empty }

        key_start     index of the member name's opening quote
        value_start   index of the first character of the value
        value_end     index just PAST the last character of the value
        member_end    same as value_end; kept separate so a caller removing a
                      member has an obvious name for the end of what it cuts
        empty         $true when the object has no members at all

      Only members at the object's OWN depth are considered. Matching is
      case-sensitive, because JSON member names are.
    #>
    param([string]$Text, [int]$ObjStart, [string]$Key)

    $r = @{ found = $false; key_start = -1; key_end = -1; value_start = -1; value_end = -1; member_end = -1; empty = $true }
    if ($ObjStart -lt 0 -or $ObjStart -ge $Text.Length -or $Text[$ObjStart] -ne '{') { return $r }

    $depth = 0
    $i = $ObjStart
    while ($i -lt $Text.Length) {
        $c = $Text[$i]

        if ($c -eq '"') {
            $strEnd = Get-LwgJsonStringEnd -Text $Text -Start $i
            if ($depth -eq 1) {
                # A string at the object's own depth is a member NAME only when a
                # colon follows it. Anything else is a value and must be skipped.
                $j = $strEnd
                while ($j -lt $Text.Length -and [char]::IsWhiteSpace($Text[$j])) { $j++ }
                if ($j -lt $Text.Length -and $Text[$j] -eq ':') {
                    $r.empty = $false
                    $name = $Text.Substring($i + 1, $strEnd - $i - 2)
                    if ($name -ceq $Key) {
                        $v = $j + 1
                        while ($v -lt $Text.Length -and [char]::IsWhiteSpace($Text[$v])) { $v++ }
                        $end = Get-LwgJsonValueEnd -Text $Text -Start $v
                        if ($end -gt $v) {
                            $r.found = $true
                            $r.key_start = $i; $r.key_end = $strEnd
                            $r.value_start = $v; $r.value_end = $end; $r.member_end = $end
                            return $r
                        }
                    }
                }
            }
            $i = $strEnd
            continue
        }

        if ($c -eq '{' -or $c -eq '[') { $depth++; $i++; continue }
        if ($c -eq '}' -or $c -eq ']') {
            $depth--
            if ($depth -eq 0) { return $r }
            $i++; continue
        }
        $i++
    }
    return $r
}

function Get-LwgJsonValueEnd {
    <#
      Index just past the value beginning at $Start. Objects and arrays are
      matched bracket for bracket; strings run to their closing quote; anything
      else (a number, true, false, null) runs to the first comma or closing
      bracket at its own level. -1 when the value is malformed.
    #>
    param([string]$Text, [int]$Start)

    if ($Start -lt 0 -or $Start -ge $Text.Length) { return -1 }
    $c = $Text[$Start]
    if ($c -eq '{' -or $c -eq '[') {
        $close = Get-LwgJsonSpan -Text $Text -Open $Start
        if ($close -lt 0) { return -1 }
        return $close + 1
    }
    if ($c -eq '"') { return (Get-LwgJsonStringEnd -Text $Text -Start $Start) }

    $i = $Start
    while ($i -lt $Text.Length) {
        $ch = $Text[$i]
        if ($ch -eq ',' -or $ch -eq '}' -or $ch -eq ']') { break }
        $i++
    }
    # Trailing whitespace belongs to the file's formatting, not to the value.
    while ($i -gt $Start -and [char]::IsWhiteSpace($Text[$i - 1])) { $i-- }
    return $i
}

function Get-LwgJsonMemberPath {
    <#
      Walk a chain of member names from the root object and return the innermost
      member's location, as Find-LwgJsonMember does, plus `parent_start` - the
      index of the '{' that CONTAINS it, which is what an insert needs.

        Get-LwgJsonMemberPath -Text $t -Path @('modules', 'git_hygiene')

      `found` is $false as soon as any step is missing; `depth_found` says how
      many steps did resolve, so a caller can tell "no such module" from "no
      modules block at all".
    #>
    param([string]$Text, [string[]]$Path)

    $r = @{ found = $false; depth_found = 0; parent_start = -1
            key_start = -1; value_start = -1; value_end = -1; member_end = -1; empty = $true }

    $objStart = $Text.IndexOf('{')
    if ($objStart -lt 0) { return $r }

    for ($k = 0; $k -lt $Path.Count; $k++) {
        $m = Find-LwgJsonMember -Text $Text -ObjStart $objStart -Key $Path[$k]
        if (-not $m.found) {
            $r.parent_start = $objStart
            $r.empty = $m.empty
            return $r
        }
        $r.depth_found = $k + 1
        if ($k -eq $Path.Count - 1) {
            $r.found = $true
            $r.parent_start = $objStart
            $r.key_start = $m.key_start
            $r.value_start = $m.value_start
            $r.value_end = $m.value_end
            $r.member_end = $m.member_end
            $r.empty = $m.empty
            return $r
        }
        if ($Text[$m.value_start] -ne '{') { return $r }   # a leaf where an object was expected
        $objStart = $m.value_start
    }
    return $r
}

function Add-LwgJsonMember {
    <#
      Insert $Fragment (a complete `"name": value` pair, possibly multi-line) as
      the FIRST member of the object whose '{' is at $ObjStart. Returns the new
      text, or '' if the object could not be located.

      First rather than last on purpose: appending means finding the last member
      and adding a comma to a line this script did not write, which is one more
      way to damage a file it does not own. Inserting at the front only ever adds
      a comma to text it has just produced itself.
    #>
    param([string]$Text, [int]$ObjStart, [string]$Fragment, [string]$Indent)

    if ($ObjStart -lt 0 -or $ObjStart -ge $Text.Length -or $Text[$ObjStart] -ne '{') { return '' }
    $nl = Get-LwgJsonNewline -Text $Text
    if ([string]::IsNullOrEmpty($Indent)) { $Indent = (Get-LwgJsonIndent -Text $Text -Index $ObjStart) + '  ' }

    # An object with no members takes no comma; one with members needs the
    # separator between the new first member and the old one.
    $probe = Find-LwgJsonMember -Text $Text -ObjStart $ObjStart -Key ([guid]::NewGuid().ToString())
    $sep = if ($probe.empty) { '' } else { ',' }

    $body = ($Fragment -split "`r?`n" | ForEach-Object { $Indent + $_ }) -join $nl
    return $Text.Substring(0, $ObjStart + 1) + $nl + $body + $sep + $Text.Substring($ObjStart + 1)
}

function Remove-LwgJsonMember {
    <#
      Cut one member out of the object whose '{' is at $ObjStart, together with
      the line it sits on and whichever comma separated it from its neighbours.
      Returns @{ ok; text; removed } - `removed` is the exact text taken out, so
      a caller can print what it did rather than assert it.
    #>
    param([string]$Text, [int]$ObjStart, [string]$Key)

    $r = @{ ok = $false; text = $Text; removed = '' }
    $m = Find-LwgJsonMember -Text $Text -ObjStart $ObjStart -Key $Key
    if (-not $m.found) { return $r }

    $start = $m.key_start
    $end   = $m.member_end

    # Forward to a separating comma, if this was not the last member.
    $f = $end
    while ($f -lt $Text.Length -and [char]::IsWhiteSpace($Text[$f])) { $f++ }
    if ($f -lt $Text.Length -and $Text[$f] -eq ',') { $end = $f + 1 }
    else {
        # Last member: the comma that needs to go is the one BEFORE it.
        $b = $start
        while ($b -gt 0 -and [char]::IsWhiteSpace($Text[$b - 1])) { $b-- }
        if ($b -gt 0 -and $Text[$b - 1] -eq ',') { $start = $b - 1 }
    }

    # Take the whole line when the member had one to itself, so removal does not
    # leave a blank line behind.
    $ls = $start
    while ($ls -gt 0 -and $Text[$ls - 1] -ne "`n") { $ls-- }
    if ([string]::IsNullOrWhiteSpace($Text.Substring($ls, $start - $ls))) {
        $start = $ls
        if ($start -gt 0 -and $Text[$start - 1] -eq "`n") {
            $start--
            if ($start -gt 0 -and $Text[$start - 1] -eq "`r") { $start-- }
        }
    }

    $r.removed = $Text.Substring($start, $end - $start).Trim()
    $r.text = $Text.Substring(0, $start) + $Text.Substring($end)
    $r.ok = $true
    return $r
}

function Get-LwgJsonIndent {
    <#
      The literal indentation of the line the character at $Index sits on. Used
      so an inserted member lines up with its siblings instead of announcing
      itself as machine-written.
    #>
    param([string]$Text, [int]$Index)

    $i = $Index
    while ($i -gt 0 -and $Text[$i - 1] -ne "`n") { $i-- }
    $ws = ''
    while ($i -lt $Text.Length -and ($Text[$i] -eq ' ' -or $Text[$i] -eq "`t")) { $ws += $Text[$i]; $i++ }
    return $ws
}

function Get-LwgJsonNewline {
    <# The line ending the file already uses. Never impose a different one. #>
    param([string]$Text)
    if ($Text.Contains("`r`n")) { return "`r`n" }
    return "`n"
}

function Test-LwgJsonParses {
    <#
      Would this text load as JSON? The last gate before anything is written.
      A surgical edit that produced invalid JSON would take config.json out of
      service entirely - Get-LwgConfig would silently fall back to built-in
      defaults, every operator ON/OFF choice would be ignored, and nothing would
      report an error. So no caller here writes without asking this first.
    #>
    param([string]$Text)
    try { $null = ($Text | ConvertFrom-Json -ErrorAction Stop); return $true } catch { return $false }
}

# --- file read / write ------------------------------------------------------

function Read-LwgTextFile {
    <#
      Read a text file and remember enough about it to write it back unchanged
      in every respect but the edit. Returns:

        @{ ok; text; bom; sha; bytes; error }

      `bom` records whether the file carried a UTF-8 byte-order mark, because
      settings.json written by another tool does carry one and dropping it is a
      silent change to a file this script does not own.
    #>
    param([string]$Path)

    $r = @{ ok = $false; text = ''; bom = $false; sha = ''; bytes = 0; error = '' }
    try {
        $raw = [IO.File]::ReadAllBytes($Path)
        $r.bytes = $raw.Length
        $off = 0
        if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) { $r.bom = $true; $off = 3 }
        $r.text = [Text.UTF8Encoding]::new($false).GetString($raw, $off, $raw.Length - $off)
        $r.sha = Get-LwgFileSha256 -Path $Path
        $r.ok = $true
    } catch { $r.error = $_.Exception.Message }
    return $r
}

function Save-LwgTextFile {
    <#
      Write $Text to $Path, but only if the file on disk is still exactly the one
      that was read. Returns @{ ok; reason; backup; sha }.

      THE HASH CHECK IS NOT CEREMONY. The Claude Code CLI rewrites
      ~/.claude/settings.json underneath whatever is reading it - observed
      mid-edit on this machine on 2026-07-28 - and several agents can be editing
      it at once. Read-modify-write without this check silently discards whatever
      landed in between, which for a permissions file means silently restoring
      rules somebody had just deliberately removed. A refusal here is a correct
      outcome, not a failure: re-read and re-plan.

      A backup is taken FIRST, next to the original, and its path is returned so
      the caller can print it. Nothing is deleted, ever.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$ExpectedSha,
        [bool]$Bom = $false,
        [string]$BackupTag = 'lwg'
    )

    $r = @{ ok = $false; reason = ''; backup = ''; sha = '' }
    try {
        if (-not (Test-Path -LiteralPath $Path)) { $r.reason = "gone: $Path no longer exists"; return $r }
        $now = Get-LwgFileSha256 -Path $Path
        if ($now -ne $ExpectedSha) {
            $r.reason = "CHANGED UNDER US: $Path was modified between the plan and the write (expected SHA256 $($ExpectedSha.Substring(0,12))..., found $($now.Substring(0,12))...). Nothing was written."
            return $r
        }

        $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
        $bak = "$Path.$BackupTag-$stamp.bak"
        Copy-Item -LiteralPath $Path -Destination $bak -ErrorAction Stop
        $r.backup = $bak

        $enc = [Text.UTF8Encoding]::new($Bom)
        [IO.File]::WriteAllText($Path, $Text, $enc)
        $r.sha = Get-LwgFileSha256 -Path $Path
        $r.ok = $true
    } catch { $r.reason = $_.Exception.Message }
    return $r
}

# --- bounded subprocess -----------------------------------------------------
# Same contract as lib/stop_advisories.ps1's helper and for the same reason: a
# caller must be able to tell "the tool said there is nothing wrong" from "the
# tool did not answer". `ok` is $true for state 'ok' and nothing else.

function Invoke-LwgCmdProcess {
    <#
      Run a program with a hard wall-clock bound. Returns:

        @{ ok; state; code; out; err; ms }

        ok       $true only for state 'ok'
        state    ok | nonzero | timeout | missing | error
        missing  the executable could not be started at all - not on PATH

      Output is drained asynchronously. The obvious shape, ReadToEnd() then
      WaitForExit($ms), deadlocks on a child that fills a pipe buffer, and
      WaitForExit($ms) alone deadlocks on a child that never exits, so neither
      of them bounds anything at all.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$File,
        [string[]]$ProcArgs = @(),
        [string]$WorkDir,
        [int]$TimeoutMs = 5000
    )

    $r = @{ ok = $false; state = 'error'; code = -1; out = ''; err = ''; ms = 0 }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $p = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $File
        # .NET Framework 4.x has no ProcessStartInfo.ArgumentList, so the
        # argument string is built by hand.
        $psi.Arguments = (@($ProcArgs | ForEach-Object {
            if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { [string]$_ }
        }) -join ' ')
        $psi.UseShellExecute        = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.RedirectStandardInput  = $true
        $psi.CreateNoWindow         = $true
        if (-not [string]::IsNullOrWhiteSpace($WorkDir)) { $psi.WorkingDirectory = $WorkDir }
        # Nothing here may ever wait on a human: a credential helper that decides
        # to prompt would otherwise sit there until the timeout kills it.
        $psi.EnvironmentVariables['GIT_TERMINAL_PROMPT']   = '0'
        $psi.EnvironmentVariables['GIT_OPTIONAL_LOCKS']    = '0'
        $psi.EnvironmentVariables['GCM_INTERACTIVE']       = 'never'
        $psi.EnvironmentVariables['GH_PROMPT_DISABLED']    = '1'
        $psi.EnvironmentVariables['GH_NO_UPDATE_NOTIFIER'] = '1'

        try { $p = [System.Diagnostics.Process]::Start($psi) }
        catch { $r.state = 'missing'; $r.err = $_.Exception.Message; return $r }
        if ($null -eq $p) { $r.state = 'missing'; return $r }

        try { $p.StandardInput.Close() } catch { }
        $so = $p.StandardOutput.ReadToEndAsync()
        $se = $p.StandardError.ReadToEndAsync()

        if ($p.WaitForExit($TimeoutMs)) {
            try { if ($so.Wait(500)) { $r.out = [string]$so.Result } } catch { }
            try { if ($se.Wait(500)) { $r.err = [string]$se.Result } } catch { }
            $r.code  = $p.ExitCode
            $r.ok    = ($r.code -eq 0)
            $r.state = if ($r.ok) { 'ok' } else { 'nonzero' }
        } else {
            $r.state = 'timeout'
            try { $p.Kill() } catch { }
        }
    } catch {
        $r.state = 'error'
        $r.err   = $_.Exception.Message
    } finally {
        $sw.Stop()
        $r.ms = [int]$sw.ElapsedMilliseconds
        if ($null -ne $p) { try { $p.Dispose() } catch { } }
    }
    return $r
}

function Get-LwgToolReport {
    <#
      One line describing why an external tool produced no answer, in the words
      the caller should print. Returns '' when the call succeeded, so
      `if ($msg) { ... }` reads as "it did not answer".

      Exists so that no command in bin/ can quietly treat a missing tool as a
      clean result - the failure this repo has already fixed three times.
    #>
    param([string]$Tool, $Result)

    if ($null -eq $Result) { return "$Tool did not run" }
    switch ([string]$Result.state) {
        'ok'      { return '' }
        'missing' { return "$Tool is NOT INSTALLED or not on PATH - this check could not be made at all, which is not the same as it passing" }
        'timeout' { return "$Tool did not answer within the timeout ($($Result.ms) ms) and was killed - UNKNOWN, not clean" }
        'nonzero' { return "$Tool exited $($Result.code): $((([string]$Result.err).Trim() -split "`n")[0])" }
        default   { return "$Tool could not be run: $($Result.err)" }
    }
}

# --- shared presentation ----------------------------------------------------

function Format-LwgBytes {
    param([long]$N)
    if ($N -ge 1048576) { return ('{0:N1} MB' -f ($N / 1048576.0)) }
    if ($N -ge 1024)    { return ('{0:N0} KB' -f ($N / 1024.0)) }
    return "$N B"
}
