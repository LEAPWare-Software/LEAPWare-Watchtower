#requires -version 5
<#
  LW-WATCHTOWER setup - the guided installer.

      powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-setup.ps1 -Step detect

  Backs /lw-watchtower:setup. EVERY decision this installer makes lives in this file.
  The command file is prose that tells a model which of these steps to run, in
  what order, and to paste the output verbatim - it contains no rules, no paths
  and no JSON, because an installer a model performs by interpreting a document
  installs whatever the model inferred that day.

  WHY THIS EXISTS AT ALL

  A Claude Code plugin cannot do two things it needs done, and both were
  confirmed rather than assumed:

      statusLine         a settings.json key. No manifest field, and no hook
                         event renders a line
      any postinstall    there is no install-time hook of any kind

  So the plugin ships everything it can, and this command performs the rest from
  inside a session that has tool access.

  A THIRD SECTION IS GONE. There was a `permissions` section, which stopped
  installing anything on 30 July 2026 when the deny table was emptied with the
  two gates; it could only ever report "nothing to add", so it was removed
  outright rather than left as a section an operator is asked to say yes to.
  This installer writes no permissions.deny rules and has none to write. Rules
  already in the operator's settings.json are still REPORTED by -Step detect,
  and still never touched.

  THE TWO SECTIONS ARE CONFIRMED SEPARATELY, ALWAYS

  statusLine and hooks are two different powers over the operator's machine, and
  one "yes" must never buy both. -Step diff shows exactly one section; -Step
  apply writes exactly one section. There is no -Section all, deliberately.

  STEPS

      detect     look at the machine and report. Writes nothing, ever.
                 Also prints the questions to put to the operator, in the words
                 to put them in, so the wording is not improvised per session.
      diff       show the exact change one section would make, and print the
                 BASEHASH the file was read at. Writes nothing, ever.
      apply      write one section. Requires the BASEHASH that diff printed.
      rollback   restore the newest backup this command took.
      doctor     run bin\lwg-doctor.ps1 and report its real verdict.

  EXIT CODES - a caller reads these and nothing else.

      0  the step completed, and nothing needs the operator's attention
      1  the step completed and found a FAULT (the doctor failed; or a write
         landed and the result was not what was promised)
      2  the step completed with a caveat the operator must read
      3  the step could not be completed at all - what was printed is a
         fragment, not a result
      4  CONCURRENT MODIFICATION - the settings file changed between the diff
         that was approved and this write. settings.json was NOT written.
         The check is made before the section's first write of any kind, so on
         every ordinary run nothing at all was written and the report says so
         in those words. It is made a SECOND time inside Save-Settings, which
         catches a file that moved DURING the run - after the section's file
         copies had already landed. On that path the report names every file
         that did land and the .bak beside it, and does not claim they were
         not written. This used to say "NOTHING was written" unconditionally,
         and it was false on exactly that path.
      5  REFUSED - a precondition failed (the target does not parse, no
         BASEHASH, an unknown section). NOTHING was written.

  4 and 5 are separate from 3 because "I stopped on purpose" and "I fell over"
  are different statements, and an installer that collapses them will eventually
  be retried by something that reads 3 as transient.

  SANDBOXING

  -SettingsPath redirects every settings read and write, and everything else -
  the state directory, the status-line target, the agent directory - hangs off
  $env:USERPROFILE. Setting both points the whole installer at a scratch tree,
  which is how it is tested. Nothing here reaches outside those two roots.
#>

# [CmdletBinding()] IS LOAD-BEARING HERE, NOT DECORATION. Without it
# PowerShell binds an unrecognised -Something as a POSITIONAL argument and discards
# it in silence, so a single mistyped character changed what this installer did with
# no signal at all: `-DryRunn` performed a real 15 KB write to settings.json and
# exited 0 - the operator asked to see the write and got the write - and
# `-StatusLineModee skip` silently installed the default `copy` instead. Measured in
# the v0.3.0 UAT; see docs/uat-report.md. With it, an unknown parameter is a binding
# error before a line of this script runs and nothing is written. Every caller in
# this repo passes named parameters only, so nothing legitimate is refused by it.
[CmdletBinding()]
param(
    [ValidateSet('detect', 'diff', 'apply', 'rollback', 'doctor')]
    [string]$Step = 'detect',

    # Exactly one section per diff/apply. There is no 'all'.
    [ValidateSet('', 'statusline', 'hooks')]
    [string]$Section = '',

    # Defaults to <USERPROFILE>\.claude\settings.json. Override to sandbox.
    [string]$SettingsPath = '',

    # With -Step apply: do everything except the write, including the merge and
    # the validation of the merged result. Prints what WOULD have been written.
    [switch]$DryRun,

    # The sha256 that -Step diff printed. apply refuses without it, and refuses
    # when it no longer matches the file on disk. For a file that does not exist
    # yet the value is the literal 'none', which diff prints too.
    [string]$BaseHash = '',

    # --- the operator's answers, one per feature group ---------------------
    # Every one has a recommended default and every one is a real choice; none
    # of them is inferred from the machine.
    # -DestructiveGate and -SecretGate USED TO SIT HERE and are gone. Both gates
    # were removed on 30 July 2026; the parameters outlived them by validating
    # answers to questions about features that no longer exist. Because this
    # script is [CmdletBinding()], passing either one is now a BINDING ERROR
    # before a line of it runs rather than a silently discarded positional - a
    # caller still spelling them is told, and nothing is written.
    [ValidateSet('yes', 'no')][string]$Advisories      = 'yes',
    [ValidateSet('yes', 'no')][string]$AgentRoles      = 'yes',

    # auto = whatever detection recommends. See the 'hooks' section.
    [ValidateSet('auto', 'plugin', 'standalone')][string]$HookMode = 'auto',

    [ValidateSet('copy', 'junction', 'skip')][string]$StatusLineMode = 'copy',

    # -Step rollback: a specific backup. Default is the newest one.
    [string]$BackupPath = ''
)

$ErrorActionPreference = 'Stop'

# Everything printed is ASCII. Setup may well be run on the machine where the
# console encoding is what is wrong.
#
# Every Invoke-* step below WRITES its report and SETS $script:Exit. None of
# them returns its code down the pipeline: a function that both writes output
# and returns a number returns the output too, and `exit (Invoke-Thing)` would
# then be handed an array instead of a code.
$script:PluginRoot = Split-Path -Parent $PSScriptRoot
$script:Exit       = 0
$script:Caveats    = New-Object System.Collections.ArrayList

function Add-Caveat { param([string]$Text) [void]$script:Caveats.Add($Text) }

# ===========================================================================
# THE DENY RULE TABLE IS GONE, AND SO IS THE SECTION THAT WROTE IT
# ===========================================================================
# This installer once authored 181 permissions.deny rules in six groups and
# merged them into the operator's settings.json behind their own yes. All six
# groups were removed on 30 July 2026 at the owner's instruction - the four
# destructive groups with the command gate, the two secret groups with the
# secret gate - and Get-DenyGroups was left returning an empty table.
#
# WHAT WAS DELETED HERE, AND WHY IT COULD BE. With that table empty,
# New-PermissionsPlan returned at its `$rules.Count -eq 0` branch on every
# possible run: the union merge, the per-group listing and the matcher guard
# (Assert-EffectiveMatchers) could not execute, and the section could only ever
# print "nothing to add". A section an operator is asked to say yes to, which
# cannot do anything whatever they answer, is a consent screen for nothing. So
# the whole permissions section went - the plan builder, the four table
# functions behind it, and the -Section value that reached them.
#
# WHAT THAT DOES NOT MEAN. This plugin does not protect credential files or
# destructive commands at any layer, and it did not before this deletion
# either; both hooks were deleted in July 2026 and both rule sets with them.
# Nothing changed about what the operator is protected from. What changed is
# that setup no longer asks.
#
# RULES ALREADY IN THE OPERATOR'S FILE ARE STILL REPORTED AND STILL NEVER
# TOUCHED. Get-InertRules below is live: Write-DetectionReport calls it under
# -Step detect to name deny rules that cannot match anything, which is the one
# true thing this installer still has to say about permissions.deny. It never
# removes, reorders or rewrites a rule, including the 181 it used to add.
#
# RESTORING THE SECTION MEANS RESTORING ALL OF IT - the table, the group
# selection, the matcher guard, the union merge and a -Section value - which is
# the same statement docs/gates-removed.md makes about the gates themselves.

function Get-InertRules {
    <# Rules in the operator's OWN file that cannot match. Reported, never touched. #>
    param([string[]]$Rules)
    return , @($Rules | Where-Object { $_ -like 'Write(*' -or $_ -like 'NotebookEdit(*' })
}

# ===========================================================================
# JSON I/O
# ===========================================================================
# Get-Content -Raw is NOT used anywhere in this file. In PowerShell 5.1 it
# decodes with the console codepage, so a settings.json holding one non-ASCII
# character round-trips to mojibake - measured, not assumed. Every read is
# [IO.File]::ReadAllText with UTF8 named explicitly, and every write is
# UTF8Encoding($false), so no BOM is introduced either.

function Get-Sha256 {
    param([byte[]]$Bytes)
    if ($null -eq $Bytes) { return 'none' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $sha.Dispose() }
}

function Read-SettingsFile {
    <#
      Returns @{ path; exists; bytes; raw; hash; obj; parses; error; hadBom }.
      Never throws: a settings file that does not parse is a FINDING, and one
      this installer must survive in order to refuse politely.
    #>
    param([string]$Path)
    $r = @{ path = $Path; exists = $false; bytes = $null; raw = ''; hash = 'none'
            obj = $null; parses = $false; error = ''; hadBom = $false }
    try {
        if (-not [IO.File]::Exists($Path)) { return $r }
        $r.exists = $true
        $r.bytes  = [IO.File]::ReadAllBytes($Path)
        $r.hash   = Get-Sha256 -Bytes $r.bytes
        $txt      = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
        if ($txt.Length -gt 0 -and $txt[0] -eq [char]0xFEFF) { $r.hadBom = $true; $txt = $txt.TrimStart([char]0xFEFF) }
        $r.raw    = $txt
        $r.obj    = $txt | ConvertFrom-Json
        if ($null -eq $r.obj) { $r.error = 'the file parsed to nothing'; return $r }
        $r.parses = $true
    } catch {
        $r.error = $_.Exception.Message
    }
    return $r
}

function ConvertTo-CanonicalJson {
    param($Obj)
    return (ConvertTo-Json -InputObject $Obj -Depth 40)
}

function Get-PropValue {
    param($Obj, [string]$Name)
    if ($null -eq $Obj) { return $null }
    $p = $Obj.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Set-PropValue {
    <#
      Assign IN PLACE when the property already exists. Add-Member -Force removes
      the property and re-appends it, which silently moves the key to the end of
      the file - so replacing permissions.deny reordered the whole permissions
      block, and a reader diffing the result saw a change that was not one.
      Only a genuinely new key is appended.
    #>
    param($Obj, [string]$Name, $Value)
    $p = $Obj.PSObject.Properties[$Name]
    if ($null -ne $p) { $p.Value = $Value }
    else { Add-Member -InputObject $Obj -NotePropertyName $Name -NotePropertyValue $Value -Force }
}

function Get-PropArray {
    <#
      The value of a property that is meant to be a JSON array, AS a real array.
      Never @($v) on the raw value: when the property is absent that is @($null),
      a one-element array holding $null, and the null is then merrily written
      back into the file as a member of the array. Every hooks event array grew a
      leading `null` that way, and permissions.deny grew an empty rule.
      A missing property returns an empty array, which is what it means.
    #>
    param($Obj, [string]$Name)
    $v = Get-PropValue -Obj $Obj -Name $Name
    if ($null -eq $v) { return , @() }
    return , @(@($v) | Where-Object { $null -ne $_ })
}

function Copy-JsonObject {
    <# A deep copy through the serialiser, so building a merge can never mutate
       the object the "before" comparison is taken from. #>
    param($Obj)
    if ($null -eq $Obj) { return $null }
    return ((ConvertTo-Json -InputObject $Obj -Depth 40) | ConvertFrom-Json)
}

function Compare-UnrelatedKeys {
    <#
      Every top-level key EXCEPT the one being touched, compared by its
      compressed JSON serialisation - byte equality of the value, not a loose
      "looks about the same". Returns @{ checked; changed; dropped }.
    #>
    param($Before, $After, [string]$Touched)
    $res = @{ checked = 0; changed = @(); dropped = @() }
    if ($null -eq $Before) { return $res }
    foreach ($p in $Before.PSObject.Properties) {
        if ($p.Name -eq $Touched) { continue }
        $res.checked++
        $a = $After.PSObject.Properties[$p.Name]
        if ($null -eq $a) { $res.dropped += $p.Name; continue }
        $sb = ConvertTo-Json -InputObject $p.Value -Depth 40 -Compress
        $sa = ConvertTo-Json -InputObject $a.Value -Depth 40 -Compress
        if ($sb -ne $sa) { $res.changed += $p.Name }
    }
    return $res
}

function Format-BaseHashMismatch {
    <# The one sentence that describes a concurrency refusal, so the two places
       that can decide one word it identically. #>
    param([string]$Actual, [string]$Expected)
    return "the file on disk is now sha256 $Actual; the approved diff was taken at $Expected"
}

function Get-BaseHashMismatch {
    <#
      The concurrency check as a QUESTION, answerable before anything has been
      written. Returns '' when the file on disk is still the one the approved
      diff was taken from, and the sentence to print when it is not.

      WHY IT IS NOT ONLY INSIDE Save-Settings, WHICH STILL MAKES IT ITSELF. It
      used to be, and Invoke-Apply performs the section's non-settings writes -
      the status-line file copy - BEFORE calling this function's other caller,
      for the reason stated at that loop. So a run that refused on this check
      had already replaced the operator's own statusline.ps1 and then printed
      'CONCURRENT MODIFICATION - NOTHING WAS WRITTEN.' with exit 4, which the
      header defines as "NOTHING was written". Measured, not reasoned about.

      The check is now made twice on purpose: once by Invoke-Apply before its
      first write of any kind, and again here. Save-Settings is the only writer
      of settings.json in this file, and a writer whose safety holds only when
      its caller remembered to ask first is not safe.

      IT IS STILL A CHECK AND NOT A LOCK, which is worth saying because two
      reads of the same file cannot be made into one: another process can
      rewrite settings.json in the window between this answer and the write it
      guards. Windows offers no atomic compare-and-swap on a file, and this
      installer does not hold the file open across the operator's decision -
      it prints a diff, waits for a human, and comes back. The check closes the
      minutes-long window that matters and cannot close the millisecond one.
    #>
    param([string]$Path, [string]$ExpectHash)
    $cur = Read-SettingsFile -Path $Path
    if ($cur.hash -eq $ExpectHash) { return '' }
    return (Format-BaseHashMismatch -Actual $cur.hash -Expected $ExpectHash)
}

function Save-Settings {
    <#
      The only writer of settings.json in this file. In order:

        1. re-read the file and compare its sha256 to $ExpectHash. A mismatch
           means something rewrote it since the diff the operator approved - the
           CLI does rewrite settings.json itself, observed mid-edit - so this
           returns concurrent=$true and writes NOTHING. Invoke-Apply asks the
           same question before its first write of any kind; see
           Get-BaseHashMismatch for why both.
        2. serialise the merged object and check it parses back.
        3. if the result is byte-identical to what is already there, stop. No
           backup, no write, no timestamp change.
        4. back the current file up.
        5. write the whole result to a temp file in the same directory FIRST, so
           a volume with no room for it fails before the target is opened, then
           copy that file over the target.
        6. re-read what landed. If it does not parse, restore the backup at once
           and report a fault.

      STEP 5 IS NOT AN ATOMIC REPLACE, AND THIS DOCSTRING USED TO SAY IT WAS.
      It read "so a half-written settings.json is not a state that exists",
      which [IO.File]::Copy does not deliver: Copy opens the destination and
      streams the source into it, so a process killed part-way through, or a
      volume that fills part-way through, leaves settings.json truncated to a
      valid-JSON prefix. That is why step 6 exists and is load bearing.

      THE ATOMIC CALL WAS MEASURED AND REJECTED, and the measurement is recorded
      here so the decision can be argued with rather than rediscovered.
      [IO.File]::Replace is atomic on NTFS, and under Windows PowerShell 5.1
      against a destination another process holds open with FileShare.ReadWrite:

          Copy    -> succeeds
          Replace -> throws "being used by another process"

      An indexer, an anti-virus scan, a backup agent or a second Claude Code
      session holding that handle is ordinary and transient. Switching would
      trade a rare truncation on a killed process for a routine refusal to
      install, so this keeps Copy and states the gap instead of promising it
      away. What remains open is exactly that: an interrupted copy can truncate
      settings.json, step 6 detects it, and the restore at step 6 uses the same
      non-atomic call and can therefore fail for the same reason - it now
      reports WHY when it does, rather than swallowing it.

      Returns a hashtable and never throws for an expected failure.
    #>
    param([string]$Path, $Obj, [string]$ExpectHash, [switch]$WhatIfOnly)

    $out = @{ ok = $false; concurrent = $false; wrote = $false; backup = ''
              bytes = 0; error = ''; restored = $false; unchanged = $false }

    $cur = Read-SettingsFile -Path $Path
    if ($cur.hash -ne $ExpectHash) {
        $out.concurrent = $true
        $out.error = Format-BaseHashMismatch -Actual $cur.hash -Expected $ExpectHash
        return $out
    }

    $json = ConvertTo-CanonicalJson -Obj $Obj
    try { $null = $json | ConvertFrom-Json } catch {
        $out.error = "the merged result does not parse as JSON, so it was not written: $($_.Exception.Message)"
        return $out
    }

    $enc   = New-Object System.Text.UTF8Encoding($false)
    $bytes = $enc.GetBytes($json)
    $out.bytes = $bytes.Length

    if ($cur.exists -and $cur.hash -eq (Get-Sha256 -Bytes $bytes)) {
        $out.ok = $true; $out.unchanged = $true
        return $out
    }

    if ($WhatIfOnly) { $out.ok = $true; return $out }

    try {
        $dir = Split-Path -Parent $Path
        if ($dir -and -not [IO.Directory]::Exists($dir)) { [void][IO.Directory]::CreateDirectory($dir) }

        if ($cur.exists) {
            $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
            $bk    = "$Path.lwg-$stamp.bak"
            $n     = 1
            while ([IO.File]::Exists($bk)) { $bk = "$Path.lwg-$stamp-$n.bak"; $n++ }
            [IO.File]::WriteAllBytes($bk, $cur.bytes)
            $out.backup = $bk
        }

        # THE STAGING FILE IS REMOVED IN A finally, NOT AS THE LAST STATEMENT OF
        # THE SUCCESS PATH. It was the line after the Copy, and Copy is the one
        # statement in this block touching a file this process does not own - so
        # it is the statement most likely to throw, and every throw skipped the
        # Delete permanently. What it left is a settings.json.lwg-tmp-<guid>
        # holding a full copy of the operator's ENTIRE settings, their own keys
        # and not just this plugin's slice, sitting in their config directory.
        # Reproduced by setting the read-only attribute on settings.json.
        #
        # NOTHING IN THIS PLUGIN EVER REMOVED ONE, which is what made an
        # accumulating artefact out of a failed write: Invoke-Rollback enumerates
        # "$leaf.lwg-*.bak" and the tmp name carries no .bak suffix, and neither
        # bin\lwg-uninstall.ps1 nor bin\lwg-doctor.ps1 knows the name at all.
        #
        # WHAT THIS DOES NOT CLOSE, because it is not in this file: a tmp file
        # left by a build from before this change is still on disk and still
        # nothing deletes it. -Step detect now NAMES any it finds beside the
        # target - see Write-DetectionReport - so the operator can remove them
        # themselves. Teaching bin\lwg-uninstall.ps1's footprint report about
        # them is a change to that file and has not been made.
        $tmp = "$Path.lwg-tmp-$([Guid]::NewGuid().ToString('N'))"
        try {
            [IO.File]::WriteAllBytes($tmp, $bytes)
            [IO.File]::Copy($tmp, $Path, $true)
            $out.wrote = $true
        } finally {
            if ([IO.File]::Exists($tmp)) { try { [IO.File]::Delete($tmp) } catch { } }
        }
    } catch {
        $out.error = "the write failed: $($_.Exception.Message)"
        return $out
    }

    $after = Read-SettingsFile -Path $Path
    if (-not $after.parses) {
        # THE RESTORE'S OWN FAILURE IS REPORTED, NOT SWALLOWED. This catch was
        # empty, so a rollback that did not work left $out.restored false and the
        # caller printed "A backup exists at ..." - honest, and silent about the
        # fact that putting it back had just been tried and had failed. Under the
        # conditions that truncate a write in the first place - a full volume, a
        # lock, a killed process - this Copy is subject to the identical failure,
        # so the reason is the one thing the operator needs and the one thing
        # that was being discarded.
        $why = ''
        if ($out.backup -and [IO.File]::Exists($out.backup)) {
            try { [IO.File]::Copy($out.backup, $Path, $true); $out.restored = $true }
            catch { $why = " The backup at $($out.backup) could NOT be put back either: $($_.Exception.Message)" }
        } elseif ($out.backup) {
            $why = " The backup this run took at $($out.backup) is no longer there, so nothing could be put back."
        } else {
            $why = ' There was no settings file here before this run, so there is no backup to put back.'
        }
        $out.error = "what landed on disk does not parse: $($after.error)$why"
        return $out
    }

    $out.ok = $true
    return $out
}

# ===========================================================================
# DETECTION
# ===========================================================================

# THE CONFIGURATION ROOT, RESOLVED ONCE FOR THIS PROCESS.
#
# Every path this installer writes used to be composed from $env:USERPROFILE and
# a literal `.claude`. CLAUDE_CONFIG_DIR relocates that directory, so on a
# machine that sets it this command wrote statusLine and hooks into a
# settings.json the CLI does not read AND REPORTED SUCCESS - the worst of the
# five failure modes #146 lists, because an install that fails loudly can be
# fixed and one that is attested cannot.
#
# lib\common.ps1's Get-LwgClaudeHomeInfo is the single resolver; the precedence
# (explicit parameter, then CLAUDE_PLUGIN_DATA for the data dir only, then
# CLAUDE_CONFIG_DIR, then the profile) and the three awkward values are argued
# there and only applied here. -SettingsPath still beats all of it, which is the
# first rule of that precedence and the seam tests\setup_merge.ps1 drives.
#
# NOTHING FALLS BACK WHEN THE RESOLVED DIRECTORY IS MISSING. `exists` is
# reported - see Write-DetectionReport - and a missing directory is created by
# the write, exactly as it always was under the profile default.
$script:ClaudeHomeInfo = $null
function Get-ClaudeHomeInfoOnce {
    if ($null -eq $script:ClaudeHomeInfo) {
        $i = $null
        try { $i = Get-LwgClaudeHomeInfo } catch { }
        if ($null -eq $i) { $i = @{ path = $null; source = 'unresolved'; exists = $false; raw = $null } }
        $script:ClaudeHomeInfo = $i
    }
    return $script:ClaudeHomeInfo
}

function Get-ClaudeHomePath {
    <# The configuration root as a string. Throws NOTHING and returns $null on a
       machine with neither CLAUDE_CONFIG_DIR nor USERPROFILE; every caller below
       is written to survive that rather than to Join-Path onto nothing. #>
    return (Get-ClaudeHomeInfoOnce).path
}

function Join-ClaudeHome {
    <# <configuration root>\<tail>, or $null when there is no root. Used instead
       of [IO.Path]::Combine at every site that used to spell the profile and
       `.claude` itself. #>
    param([string]$Tail)
    $h = Get-ClaudeHomePath
    if ([string]::IsNullOrWhiteSpace($h)) { return $null }
    return [IO.Path]::Combine($h, $Tail)
}

function Get-DefaultSettingsPath {
    $p = Join-ClaudeHome 'settings.json'
    if ($null -eq $p) {
        # NEITHER CLAUDE_CONFIG_DIR NOR USERPROFILE HOLDS ANYTHING. This threw
        # before too - [IO.Path]::Combine($null, ...) raises
        # ArgumentNullException - and MAIN's catch turned that into "setup could
        # not complete: Value cannot be null", which names nothing an operator
        # can act on. The exit code is the same 3; the sentence is now the
        # actual condition. Composing onto an empty string instead would write
        # settings.json into the current directory, which is a write nobody
        # asked for and the one outcome worse than refusing.
        throw 'no configuration directory could be resolved: neither CLAUDE_CONFIG_DIR nor USERPROFILE holds a value. Pass -SettingsPath to name the file outright.'
    }
    return $p
}

function Get-PluginNameSafe {
    $n = ''
    try { $n = Get-LwgPluginName } catch { }
    if ([string]::IsNullOrWhiteSpace($n)) { $n = 'lw-watchtower' }
    return $n
}

function Get-Detection {
    <# Everything the installer knows about this machine, gathered once. #>
    $d = @{}
    $d.os          = try { (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption } catch { [string][Environment]::OSVersion.VersionString }
    $d.psVersion   = $PSVersionTable.PSVersion.ToString()
    $d.pluginRoot  = $script:PluginRoot
    $d.pluginName  = Get-PluginNameSafe
    $d.userProfile = $env:USERPROFILE
    # THE CONFIGURATION ROOT AND HOW IT WAS ARRIVED AT, both carried, because
    # the report prints both. A root is not enough on its own: "C:\cfg" tells an
    # operator nothing about whether this command agrees with their CLI, and
    # "C:\cfg, from CLAUDE_CONFIG_DIR" tells them exactly where to look when it
    # does not. $d.userProfile stays - it is the profile itself, which the report
    # also names, and it is no longer where any path below comes from.
    $chi                 = Get-ClaudeHomeInfoOnce
    $d.claudeHome        = $chi.path
    $d.claudeHomeSource  = $chi.source
    $d.claudeHomeExists  = $chi.exists
    $d.claudeHomeRaw     = $chi.raw

    # --- how is the plugin reaching Claude Code? ---------------------------
    # A junction under a skills dir is auto-discovered; a marketplace install is
    # a copy the CLI writes into its own tree. They are different sources, and
    # running both fires every hook twice - which is the whole reason this
    # question is asked at all, since the answer decides whether the hooks
    # section writes a second full set of registrations.
    #
    # THE PROBE FOR THE MARKETPLACE CASE USED TO BE WRONG, and the way it was
    # wrong made it fail SILENTLY and in the expensive direction. It looked in
    # ~\.claude\plugins\repos, a directory that does not exist on a live Claude
    # Code install and never did - "plugins/repos" appears ZERO times in the
    # 2.1.x CLI binary. So a marketplace-installed plugin was classified NOT
    # DISCOVERABLE, HookMode auto resolved to 'standalone', and setup wrote a
    # second full copy of every registration into settings.json with its own
    # duplicate-firing warning suppressed - because the warning is keyed on the
    # same flag. Eight hook events, each firing twice: two SessionStart banners,
    # two sets of turn-end advisories, two log records per event.
    #
    # statusline\statusline.ps1 carried the SAME wrong assumption in
    # LwgPluginRoots and was fixed in the same change. One defect, two files.
    $d.skillLink   = Join-ClaudeHome "skills\$($d.pluginName)"
    $d.skillExists = [IO.Directory]::Exists($d.skillLink)
    $d.skillIsLink = $false
    $d.skillTarget = ''
    if ($d.skillExists) {
        try {
            $di = New-Object IO.DirectoryInfo($d.skillLink)
            $d.skillIsLink = (($di.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
            $t = $null
            try { $t = (Get-Item -LiteralPath $d.skillLink -Force).Target } catch { }
            if ($t -is [array]) { $t = @($t)[0] }
            if ($t) { $d.skillTarget = [string]$t }
        } catch { }
    }
    # WHAT IS ASKED, IN ORDER OF HOW DIRECTLY IT ANSWERS THE QUESTION. Every
    # source that fires appends a sentence to $d.discoveryEvidence, and the
    # detection report prints those sentences rather than a bare verdict: a
    # verdict this section gets wrong is a verdict that silently doubles every
    # hook, so the operator is shown the BASIS and can contradict it.
    $d.pluginsDir          = ''
    $d.marketplaceInstalls = @()   # install roots found on disk
    $d.registryInstalls    = @()   # what the CLI's own registry says is installed
    $d.discoveryEvidence   = @()

    $norm = {
        param($p)
        if ([string]::IsNullOrWhiteSpace($p)) { return '' }
        $s = [string]$p
        try { $s = [IO.Path]::GetFullPath($s) } catch { }
        return $s.TrimEnd('\', '/').ToLowerInvariant()
    }

    if ($d.skillExists) {
        $d.discoveryEvidence += "a skills entry exists at $($d.skillLink)"
    }

    # (1) THE CLI ITSELF, when setup is running as a plugin command. Claude Code
    #     defines CLAUDE_PLUGIN_ROOT only for a hook or command it is invoking
    #     FROM a plugin, so finding it set and pointing at this very tree is not
    #     evidence about a layout - it is the CLI saying it loaded this checkout
    #     as a plugin. Nothing beats that, and nothing about it can go stale.
    #
    #     It is compared against $script:PluginRoot rather than merely tested
    #     for presence: another plugin's hook could have exported it, and
    #     "some plugin is loaded" is not the question.
    if ($env:CLAUDE_PLUGIN_ROOT) {
        if ((& $norm $env:CLAUDE_PLUGIN_ROOT) -eq (& $norm $script:PluginRoot)) {
            $d.discoveryEvidence += "Claude Code invoked this command with CLAUDE_PLUGIN_ROOT set to this tree, so it is loaded as a plugin right now"
        }
    }

    # (2) THE CLI'S OWN REGISTRY. installed_plugins.json is where Claude Code
    #     records what it installed and where it put it, keyed '<plugin>@<mkt>'.
    #     Reading it is layout-independent: if the cache moves in a later build,
    #     the registry still names the plugin and still carries installPath.
    #
    #     Both schema versions are handled by NOT depending on the schema. v2
    #     maps each key to an array of install records; a v1 file predates that
    #     and the CLI converts it in place. Either way the KEY is the plugin id,
    #     so the key is what is matched, and installPath is picked up from
    #     whatever shape the value turns out to be rather than asserted.
    #
    #     CLAUDE_CODE_PLUGIN_CACHE_DIR relocates the whole plugins directory -
    #     the CLI reads that variable first and so does this.
    $d.pluginsDir = if ($env:CLAUDE_CODE_PLUGIN_CACHE_DIR) { [string]$env:CLAUDE_CODE_PLUGIN_CACHE_DIR }
                    else { Join-ClaudeHome 'plugins' }
    try {
        $reg = [IO.Path]::Combine($d.pluginsDir, 'installed_plugins.json')
        if ([IO.File]::Exists($reg)) {
            $rj  = ([IO.File]::ReadAllText($reg, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF)) | ConvertFrom-Json
            $map = if ($null -ne $rj -and $null -ne $rj.plugins) { $rj.plugins } else { $rj }
            if ($null -ne $map) {
                foreach ($pr in $map.PSObject.Properties) {
                    $id = [string]$pr.Name
                    if (($id -split '@')[0] -ne $d.pluginName) { continue }
                    foreach ($rec in @($pr.Value)) {
                        $ip = $null; $sc = $null; $pp = $null
                        try { $ip = $rec.installPath } catch { }
                        try { $sc = $rec.scope       } catch { }
                        try { $pp = $rec.projectPath } catch { }
                        $d.registryInstalls += [pscustomobject]@{
                            id    = $id
                            path  = [string]$ip
                            scope = [string]$sc
                            proj  = [string]$pp
                        }
                    }
                }
            }
        }
    } catch { }
    # THE SCOPE IS CARRIED INTO THE SENTENCE, and this is not decoration.
    # installed_plugins.json records scope 'user' OR scope 'project' with a
    # projectPath, and a project-scoped install writes into exactly the same
    # plugins\cache\... tree as a user-scoped one. So an install that belongs to
    # a DIFFERENT repository is indistinguishable from one that loads here, both
    # to the registry branch above and to the on-disk glob below.
    #
    # THAT IS AN OPEN GAP AND IT IS THE INVERSE OF THE DEFECT THIS BLOCK WAS
    # REWRITTEN TO CLOSE. If the only install on the machine is project-scoped to
    # somewhere else, nothing loads here, $d.discovered is nevertheless true, and
    # the hooks section declines to wire anything - silently leaving the operator
    # with no hooks at all, where the old bug at least left them with two of
    # everything. What is NOT done about it, deliberately: the verdict is not
    # narrowed on a projectPath comparison. Setup runs from wherever the session
    # is, that is not necessarily the project the settings file will be used
    # from, and a verdict narrowed on a guess would be a second wrong answer
    # dressed as a fix. The projectPath is PRINTED instead, on the same line as
    # the claim, so the one person who can tell can tell.
    foreach ($r in $d.registryInstalls) {
        $where = if ($r.path) { $r.path } else { 'no installPath recorded' }
        $scope = if ($r.scope -eq 'project') {
                     "scope 'project' for $(if ($r.proj) { $r.proj } else { 'an unrecorded project' }) - it does NOT load anywhere else"
                 } elseif ($r.scope) { "scope '$($r.scope)'" }
                 else { 'no scope recorded' }
        $d.discoveryEvidence += "the CLI's own installed_plugins.json lists '$($r.id)' at $where, $scope"
        if ($r.path -and [IO.Directory]::Exists($r.path)) { $d.marketplaceInstalls += $r.path }
    }

    # (3) THE LAYOUT ON DISK, for the case where the registry is absent or
    #     unreadable - and as the check that survives a registry format change.
    #     Read off this machine's own tree and out of the CLI binary, not
    #     guessed:
    #
    #       plugins\cache\<marketplace>\<plugin>\<version>   the install root
    #       plugins\marketplaces\<marketplace>              the source checkout
    #
    #     Both are globbed on the plugin NAME, never on a literal path, for the
    #     reason lib\common.ps1 gives about the data directory: the id in that
    #     name has changed once already.
    #
    #     plugins\repos IS STILL SCANNED. It answers on no machine anyone has
    #     seen, but a build that lays things out differently must not blind this
    #     probe a second time, and a directory that does not exist costs one
    #     failed enumeration. It is now scanned FOR THIS PLUGIN'S NAME, which is
    #     a narrowing: the old code counted ANY directory under repos as an
    #     install of this plugin, so one unrelated marketplace plugin would have
    #     answered yes. That was wrong in the opposite direction and is a second
    #     defect closed by the same rewrite.
    $globDirs = {
        param($base, $pattern)
        $found = @()
        try { $found = @([IO.Directory]::GetDirectories($base, $pattern)) } catch { }
        return $found
    }
    $onDisk = @()
    # GUARDED ON A RESOLVED BASE. $d.pluginsDir is now derived from the
    # configuration root, which is $null on a machine holding neither
    # CLAUDE_CONFIG_DIR nor USERPROFILE; [IO.Path]::Combine($null, 'cache')
    # throws, and it would throw HERE, outside $globDirs' own try, taking the
    # whole detect run down over a probe that had nothing to look at anyway.
    # Skipping the scan leaves $d.discoveryEvidence empty, which is the honest
    # answer - and the report says the root is unresolved on the line above it.
    if (-not [string]::IsNullOrWhiteSpace($d.pluginsDir)) {
        foreach ($mk in @(& $globDirs ([IO.Path]::Combine($d.pluginsDir, 'cache')) '*')) {
            foreach ($pl in @(& $globDirs $mk ($d.pluginName + '*'))) {
                $onDisk += @(& $globDirs $pl '*')
            }
        }
        foreach ($mk in @(& $globDirs ([IO.Path]::Combine($d.pluginsDir, 'marketplaces')) '*')) {
            $onDisk += @(& $globDirs $mk ($d.pluginName + '*'))
            $onDisk += @(& $globDirs ([IO.Path]::Combine($mk, 'plugins')) ($d.pluginName + '*'))
        }
        $legacy = [IO.Path]::Combine($d.pluginsDir, 'repos')
        $onDisk += @(& $globDirs $legacy ($d.pluginName + '*'))
        foreach ($mk in @(& $globDirs $legacy '*')) {
            $onDisk += @(& $globDirs $mk ($d.pluginName + '*'))
        }
    }

    $seen = @{}
    foreach ($p in $d.marketplaceInstalls) { $seen[(& $norm $p)] = $true }
    foreach ($p in $onDisk) {
        $k = & $norm $p
        if ($seen.ContainsKey($k)) { continue }
        $seen[$k] = $true
        $d.marketplaceInstalls += $p
        $d.discoveryEvidence   += "a marketplace install is on disk at $p"
    }

    $d.discovered = ($d.discoveryEvidence.Count -gt 0)

    # --- the state directory, and how ambiguous it is ----------------------
    $d.stateInfo       = $null
    $d.stateCandidates = @()
    $d.bareStateDir    = Join-ClaudeHome "plugins\data\$($d.pluginName)"
    try {
        $d.stateInfo = Get-LwgStateDirInfo -Refresh
        $root = Join-ClaudeHome 'plugins\data'
        if ($root -and [IO.Directory]::Exists($root)) {
            foreach ($c in [IO.Directory]::GetDirectories($root, ($d.pluginName + '*'))) {
                $t = [datetime]::MinValue
                try { $t = [IO.Directory]::GetLastWriteTimeUtc($c) } catch { }
                $d.stateCandidates += [pscustomobject]@{ path = $c; mtimeUtc = $t }
            }
        }
    } catch { }

    # --- the status line ---------------------------------------------------
    $d.repoStatusLine      = [IO.Path]::Combine($script:PluginRoot, 'statusline\statusline.ps1')
    $d.repoStatusLineOk    = [IO.File]::Exists($d.repoStatusLine)
    $d.installedStatusLine = Join-ClaudeHome 'statusline.ps1'
    $d.installedOk         = ($null -ne $d.installedStatusLine) -and [IO.File]::Exists($d.installedStatusLine)
    $d.statusLineDrift     = 'n/a'
    if ($d.repoStatusLineOk -and $d.installedOk) {
        try {
            $a = (Get-FileHash -LiteralPath $d.installedStatusLine -Algorithm SHA256).Hash
            $b = (Get-FileHash -LiteralPath $d.repoStatusLine      -Algorithm SHA256).Hash
            $d.statusLineDrift = if ($a -eq $b) { 'identical' } else { 'DIFFERENT' }
        } catch { $d.statusLineDrift = 'could not be compared' }
    }

    # --- the agent roles the HH segment depends on -------------------------
    # Report-only. This command never writes an agent file.
    #
    # This block used to probe six hard-coded hq-* names under ~\.claude\agents
    # and say "this plugin does not ship them". BOTH halves were wrong once
    # agents\ landed: the plugin ships lw-* roles and shipped no role under that
    # older spelling, so on a fresh machine setup reported six missing files
    # that were never going to be there - then told the operator to write them
    # by hand. The roles are now ENUMERATED from the plugin's own agents\
    # directory rather than listed here, so adding or retiring one needs no
    # edit to this file and setup cannot go stale against the tree again.
    #
    # Each is then resolved the way Claude Code resolves it, minus the scope
    # setup cannot see: project (.claude\agents) is per-repo and invisible from
    # here, so the two scopes reported are the user directory - which SHADOWS
    # the shipped file entirely, replacement rather than merge - and the
    # plugin's own agents\. Found in either is present.
    $d.agentDir       = Join-ClaudeHome 'agents'
    $d.pluginAgentDir = [IO.Path]::Combine($script:PluginRoot, 'agents')
    $d.shippedAgents  = @()
    $d.agents         = @()
    try {
        if ([IO.Directory]::Exists($d.pluginAgentDir)) {
            $d.shippedAgents = @(
                [IO.Directory]::GetFiles($d.pluginAgentDir, '*.md') |
                    ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) } |
                    Sort-Object
            )
        }
    } catch { }
    foreach ($a in $d.shippedAgents) {
        # $d.agentDir is $null when no configuration root resolved; the user
        # scope simply does not exist then, and the plugin's own copy is the
        # only answer. Combining onto $null would throw here instead.
        $userPath   = if ([string]::IsNullOrWhiteSpace($d.agentDir)) { '' } else { [IO.Path]::Combine($d.agentDir, "$a.md") }
        $pluginPath = [IO.Path]::Combine($d.pluginAgentDir, "$a.md")
        if ([IO.File]::Exists($userPath)) {
            $d.agents += [pscustomobject]@{ name = $a; present = $true; scope = 'user'; path = $userPath }
        } elseif ([IO.File]::Exists($pluginPath)) {
            $d.agents += [pscustomobject]@{ name = $a; present = $true; scope = 'plugin'; path = $pluginPath }
        } else {
            $d.agents += [pscustomobject]@{ name = $a; present = $false; scope = ''; path = $pluginPath }
        }
    }

    # The HEALER probe, spelled exactly as statusline\statusline.ps1 spells it,
    # so what setup says about the health segment is derived from the same rule
    # the segment applies rather than from a second opinion about it. The
    # personal hq- spelling was a later candidate here until 31 July 2026, when
    # the rename left no such file anywhere and both probes dropped it together.
    $d.healerPath = ''
    foreach ($c in @(
        [IO.Path]::Combine($d.pluginAgentDir, 'lw-healer.md'),
        [IO.Path]::Combine($d.agentDir,       'lw-healer.md')
    )) {
        if ([IO.File]::Exists($c)) { $d.healerPath = $c; break }
    }

    # --- config.json, read only --------------------------------------------
    $d.config = $null
    try { $d.config = Get-LwgConfig } catch { }

    return $d
}

function Write-DetectionReport {
    param($D, $Settings)

    Write-Output 'LW-WATCHTOWER setup - detection. NOTHING was written by this step.'
    Write-Output ''
    Write-Output 'MACHINE'
    Write-Output ("  operating system   : {0}" -f $D.os)
    Write-Output ("  PowerShell         : {0}" -f $D.psVersion)
    Write-Output ("  user profile       : {0}" -f $D.userProfile)
    # THE CONFIGURATION ROOT, NAMED WITH ITS SOURCE, ON EVERY RUN.
    #
    # Not decoration and not symmetry with the line above it. Every path this
    # command writes hangs off this one directory, and until 3 September 2026 it
    # was composed from the profile and a literal `.claude` - so on a machine
    # that sets CLAUDE_CONFIG_DIR the installer wrote its statusLine and its
    # hooks into a settings.json the CLI does not read, and then REPORTED
    # SUCCESS. A report that does not name the root cannot be argued with: the
    # operator sees a green install and has nowhere to look. `from
    # CLAUDE_CONFIG_DIR` versus `from the user profile` is the whole difference,
    # and "does not exist yet" is said out loud rather than resolved away,
    # because a resolver that fell back to the profile on a missing directory
    # would reinstate the entire defect on exactly the machine that set the
    # variable.
    $chSrc = switch ([string]$D.claudeHomeSource) {
        'env'     { "from CLAUDE_CONFIG_DIR = $($D.claudeHomeRaw)" }
        'profile' { 'from the user profile - CLAUDE_CONFIG_DIR is not set' }
        default   { 'UNRESOLVED - neither CLAUDE_CONFIG_DIR nor USERPROFILE holds a value' }
    }
    if ([string]::IsNullOrWhiteSpace($D.claudeHome)) {
        Write-Output ("  config directory   : {0}" -f $chSrc)
        Write-Output '                       Every path below is composed from this directory, so nothing'
        Write-Output '                       below could be resolved. Pass -SettingsPath to name the file.'
    } else {
        $chEx = if ($D.claudeHomeExists) { '' } else { '  [DOES NOT EXIST YET]' }
        Write-Output ("  config directory   : {0}{1}" -f $D.claudeHome, $chEx)
        Write-Output ("                       {0}" -f $chSrc)
    }
    Write-Output ''
    Write-Output 'THIS PLUGIN'
    Write-Output ("  plugin root        : {0}" -f $D.pluginRoot)
    Write-Output ("  plugin name        : {0}" -f $D.pluginName)
    if ($D.skillExists) {
        $kind = if ($D.skillIsLink) { 'junction/link' } else { 'a real directory, NOT a link' }
        Write-Output ("  skills entry       : {0} [{1}]" -f $D.skillLink, $kind)
        if ($D.skillTarget) { Write-Output ("                       -> {0}" -f $D.skillTarget) }
    } else {
        Write-Output ("  skills entry       : none at {0}" -f $D.skillLink)
    }
    if ($D.marketplaceInstalls.Count -gt 0) {
        Write-Output ("  marketplace install: {0}" -f ($D.marketplaceInstalls -join ', '))
    } else {
        Write-Output '  marketplace install: none'
    }
    # THE BASIS, NOT JUST THE VERDICT. This one line decides whether the hooks
    # section writes a full second set of registrations, and it was wrong for
    # the entire life of the marketplace probe without saying anything an
    # operator could have argued with. Every source that answered is named.
    if ($D.discovered) {
        Write-Output '  how it loads       : Claude Code can auto-discover it, so the plugin supplies its own hooks'
        foreach ($e in $D.discoveryEvidence) { Write-Output ("    evidence         : {0}" -f $e) }
        Write-Output '    NOTE             : two things this cannot tell, and both would make the verdict above'
        Write-Output '                       WRONG IN THE SAME DIRECTION - it would say the plugin loads when'
        Write-Output '                       nothing does, and this section would then wire up nothing at all.'
        Write-Output '                       (1) ENABLED vs INSTALLED. Loading needs an enabledPlugins entry in'
        Write-Output '                       a settings file, and project scope is invisible from here.'
        Write-Output '                       (2) WHICH PROJECT. A project-scoped install sits in exactly the same'
        Write-Output '                       cache tree as a user-scoped one; if a line above says scope'
        Write-Output '                       ''project'' for a directory that is not yours, that install does not'
        Write-Output '                       load here and should not be counted. Setup does not guess either'
        Write-Output '                       way - it prints what it found and leaves the reading to you.'
    } else {
        Write-Output '  how it loads       : NOT DISCOVERABLE - no junction under a skills directory, nothing in'
        Write-Output ("                       {0}, and the CLI's own registry" -f $D.pluginsDir)
        Write-Output '                       does not list it, so not one of its hooks fires'
        Add-Caveat 'the plugin is not discoverable by Claude Code, so none of its hooks fire at all'
    }
    Write-Output ''
    Write-Output 'STATE DIRECTORY (where every log line goes)'
    if ($null -eq $D.stateInfo) {
        Write-Output '  could not be resolved at all - lib\common.ps1 did not answer'
        Add-Caveat 'the state directory could not be resolved'
    } else {
        $si = $D.stateInfo
        Write-Output ("  resolved to        : {0}" -f $si.path)
        Write-Output ("  how                : source '{0}', resolved={1}" -f $si.source, $si.resolved)
        if (-not $si.resolved) {
            Write-Output '  MEANING            : that path is a GUESS. The live plugin writes somewhere else, and'
            Write-Output '                       everything written there is lost while every writer reports success.'
            Add-Caveat "the state directory is UNRESOLVED (source '$($si.source)') - logs are going somewhere the live plugin never reads"
        }
    }
    if ($D.stateCandidates.Count -gt 0) {
        Write-Output ("  candidates seen    : {0}" -f $D.stateCandidates.Count)
        foreach ($c in ($D.stateCandidates | Sort-Object -Property mtimeUtc -Descending)) {
            $mark = if ($null -ne $D.stateInfo -and $c.path -eq $D.stateInfo.path) { '  <== chosen' } else { '' }
            Write-Output ("    {0}  (last written {1:yyyy-MM-dd HH:mm} UTC){2}" -f $c.path, $c.mtimeUtc, $mark)
        }
        $suffixed = @($D.stateCandidates | Where-Object { $_.path -ne $D.bareStateDir })
        if ($suffixed.Count -gt 1) {
            Write-Output ''
            Write-Output ("  AMBIGUOUS. {0} suffixed data directories exist, which means this plugin has been" -f $suffixed.Count)
            Write-Output '  installed from more than one source. The one marked above is simply the most'
            Write-Output '  recently written; the others still hold history, and NOTHING merges or moves them.'
            Write-Output '  Setup does not choose for you and deletes nothing. If the wrong one is chosen,'
            Write-Output '  remove the install you no longer use and run detection again.'
            Add-Caveat "$($suffixed.Count) suffixed state directories exist - the plugin is installed from more than one source and its history is split across them"
        }
    }
    Write-Output ''
    Write-Output 'SETTINGS FILE (the file this command would change)'
    Write-Output ("  path               : {0}" -f $Settings.path)
    if (-not $Settings.exists) {
        Write-Output '  status             : does not exist yet - setup would create it'
    } elseif (-not $Settings.parses) {
        Write-Output ("  status             : EXISTS BUT DOES NOT PARSE - {0}" -f $Settings.error)
        Write-Output '  MEANING            : setup will REFUSE to write to it. Overwriting a settings file'
        Write-Output '                       nobody can read is how an operator loses every other setting in it.'
        Add-Caveat 'the settings file does not parse - no section can be written until that is fixed'
    } else {
        $perms = Get-PropValue -Obj $Settings.obj -Name 'permissions'
        $deny  = Get-PropArray -Obj $perms -Name 'deny'
        $sl    = Get-PropValue -Obj $Settings.obj -Name 'statusLine'
        $hk    = Get-PropValue -Obj $Settings.obj -Name 'hooks'
        $hkEv  = if ($null -eq $hk) { @() } else { @($hk.PSObject.Properties.Name) }
        Write-Output ("  status             : exists, parses, {0} bytes, sha256 {1}" -f $Settings.bytes.Length, $Settings.hash)
        if ($Settings.hadBom) { Write-Output '                       (it carries a UTF-8 BOM; setup writes without one)' }
        Write-Output ("  top-level keys     : {0}" -f (@($Settings.obj.PSObject.Properties.Name) -join ', '))
        Write-Output ("  permissions.deny   : {0} rule(s)" -f $deny.Count)
        if ($null -eq $sl) { Write-Output '  statusLine         : not set' }
        else               { Write-Output ("  statusLine         : set -> {0}" -f $sl.command) }
        if ($hkEv.Count -eq 0) { Write-Output '  hooks              : none' }
        else                   { Write-Output ("  hooks              : {0} event(s): {1}" -f $hkEv.Count, ($hkEv -join ', ')) }

        $inert = Get-InertRules -Rules $deny
        if ($inert.Count -gt 0) {
            Write-Output ''
            Write-Output ("  {0} EXISTING DENY RULE(S) CANNOT MATCH ANYTHING." -f $inert.Count)
            Write-Output '  Claude Code applies only Edit(<path>) rules to file paths. Write(...) and'
            Write-Output '  NotebookEdit(...) rules load, sit in the file looking like protection, and match'
            Write-Output '  nothing - the CLI warns about it at every launch.'
            foreach ($r in ($inert | Select-Object -First 25)) { Write-Output ("    INERT  {0}" -f $r) }
            if ($inert.Count -gt 25) { Write-Output ("    ... and {0} more" -f ($inert.Count - 25)) }
            Write-Output '  SETUP DOES NOT TOUCH THESE. It never removes or rewrites a rule it did not write,'
            Write-Output '  and every rule it adds is already in the effective form.'
            Add-Caveat "$($inert.Count) existing deny rule(s) use an inert matcher and protect nothing"
        }

        if ($deny.Count -eq 0 -and $null -eq $sl -and $hkEv.Count -eq 0) {
            Write-Output '  install looks      : FRESH - none of this is configured yet'
        } else {
            Write-Output '  install looks      : EXISTING - some of this is already configured, and setup adds only'
            Write-Output '                       what is missing'
        }
    }

    # STAGING FILES A FAILED WRITE LEFT BEHIND. Save-Settings stages the new
    # settings.json in "<target>.lwg-tmp-<guid>" beside the target, and until
    # 3 August 2026 it deleted that file only on the success path - so every
    # failed write left one, and NOTHING in this plugin removed it: rollback
    # enumerates "<leaf>.lwg-*.bak" and this name has no .bak suffix, and neither
    # the uninstaller nor the doctor knows the name. Each one holds a full copy
    # of the operator's ENTIRE settings, not this plugin's slice of them.
    #
    # OUTSIDE the parses/exists branches above, because an orphan is beside a
    # settings file that does not parse and beside one that is not there at all -
    # a write that failed on its very first attempt leaves both states.
    #
    # NAMED AND NOT REMOVED. -Step detect writes nothing, ever, and that is the
    # only promise this step makes. The name is unambiguous - it is this
    # installer's and nobody else writes it - so the operator can delete them.
    $orphans = @()
    try {
        $sdir  = Split-Path -Parent $Settings.path
        $sleaf = Split-Path -Leaf   $Settings.path
        if ($sdir -and [IO.Directory]::Exists($sdir)) {
            $orphans = @([IO.Directory]::GetFiles($sdir, "$sleaf.lwg-tmp-*"))
        }
    } catch { }
    if ($orphans.Count -gt 0) {
        Write-Output ''
        Write-Output ("  {0} STAGING FILE(S) FROM A FAILED WRITE are sitting beside that file." -f $orphans.Count)
        Write-Output '  Each holds a full copy of your ENTIRE settings, written by this installer when a'
        Write-Output '  write failed part-way. Nothing here deletes them - not rollback, not uninstall,'
        Write-Output '  not the doctor - so they are yours to remove once you are satisfied the real'
        Write-Output '  settings.json is intact.'
        foreach ($o in ($orphans | Sort-Object | Select-Object -First 25)) { Write-Output ("    ORPHAN  {0}" -f $o) }
        if ($orphans.Count -gt 25) { Write-Output ("    ... and {0} more" -f ($orphans.Count - 25)) }
        Add-Caveat "$($orphans.Count) staging file(s) from a failed settings write are beside $($Settings.path) and nothing in this plugin removes them"
    }

    Write-Output ''
    Write-Output 'STATUS LINE'
    if ($D.repoStatusLineOk) { Write-Output ("  tracked original   : {0}" -f $D.repoStatusLine) }
    else                     { Write-Output ("  tracked original   : MISSING at {0}" -f $D.repoStatusLine) }
    if ($D.installedOk) { Write-Output ("  installed copy     : {0}" -f $D.installedStatusLine) }
    else                { Write-Output ("  installed copy     : none at {0}" -f $D.installedStatusLine) }
    Write-Output ("  copy vs original   : {0}" -f $D.statusLineDrift)
    if ($D.statusLineDrift -eq 'DIFFERENT') {
        Add-Caveat 'the installed status line differs from the tracked original - one of the two is stale, and nothing else on this machine compares them'
    }
    Write-Output ''
    if ($AgentRoles -eq 'no') {
        Write-Output 'AGENT ROLES - declined, not checked.'
    } else {
        Write-Output 'AGENT ROLES (report only - setup never writes an agent file)'
        Write-Output ("  shipped in         : {0}" -f $D.pluginAgentDir)
        if ($D.agents.Count -eq 0) {
            Write-Output '  NONE FOUND. This plugin ships its roles in that directory, so an empty or'
            Write-Output '  absent one is an INCOMPLETE INSTALL rather than a personal file you forgot to'
            Write-Output '  write. Re-clone or re-copy the plugin; setup will not invent a role file - one'
            Write-Output '  with made-up contents is worse than a missing one.'
            Add-Caveat "no agent role files were found in $($D.pluginAgentDir) - the plugin ships them there, so this install is incomplete"
        } else {
            $missing  = @($D.agents | Where-Object { -not $_.present })
            $shadowed = @($D.agents | Where-Object { $_.scope -eq 'user' })
            foreach ($a in $D.agents) {
                if     ($a.scope -eq 'plugin') { Write-Output ("  present   {0}  (from the plugin)" -f $a.name) }
                elseif ($a.scope -eq 'user')   { Write-Output ("  present   {0}  (SHADOWED by {1})" -f $a.name, $a.path) }
                else                           { Write-Output ("  MISSING   {0}" -f $a.name) }
            }
            if ($shadowed.Count -gt 0) {
                Write-Output ("  {0} role(s) are shadowed by a file in {1}. A file of the same name" -f $shadowed.Count, $D.agentDir)
                Write-Output '  REPLACES the shipped one outright - it is not merged - so the shadowing file'
                Write-Output '  has to be complete on its own. That is the supported way to customise a role,'
                Write-Output '  and it is only a problem if it was not meant.'
            }
            if ($missing.Count -gt 0) {
                Write-Output ("  {0} of the files listed in that directory could not then be read back." -f $missing.Count)
                Add-Caveat "$($missing.Count) agent role file(s) enumerated in $($D.pluginAgentDir) could not be read"
            }
        }
        if ($D.healerPath) {
            # The STATUS LINE'S probe order, which is not the harness's role
            # resolution order: the probe asks only whether a healer role file
            # exists anywhere it looks, and stops at the first hit. A user-scope
            # copy is reported as a shadow above, not here.
            Write-Output ("  healer probe hits  : {0}" -f $D.healerPath)
        } else {
            Write-Output '  healer probe hits  : NOTHING'
            Write-Output '  The status line paints the health segment purple when it can find no healer'
            Write-Output '  role at all, and the supervisor then has nothing to hand a failure to. It'
            Write-Output '  probes the plugin''s own agents\lw-healer.md first, so an absent one is a broken'
            Write-Output '  install and not a missing personal file.'
            Add-Caveat 'no healer role file was found - the health segment will render purple'
        }
    }
    Write-Output ''
    Write-Output 'MODULE SWITCHBOARD (config.json - setup does NOT edit it)'
    if ($null -eq $D.config) {
        Write-Output '  could not be read'
    } else {
        if ($D.config._source -eq 'file') { Write-Output '  source             : config.json' }
        else {
            Write-Output '  source             : BUILT-IN DEFAULTS - config.json is unreadable, so every ON/OFF'
            Write-Output '                       choice in it is being ignored'
            Add-Caveat 'config.json is unreadable, so the plugin is running on built-in defaults'
        }
        Write-Output ("  file               : {0}" -f ([IO.Path]::Combine($D.pluginRoot, 'config.json')))
        Write-Output '  To turn a module on or off, edit that file. Setup deliberately does not: it is a'
        Write-Output '  tracked file in a git working tree, and writing to it would dirty the repo.'
    }
}

function Write-Questions {
    param($D)
    $hookRec = if ($D.discovered) { 'plugin' } else { 'standalone' }

    Write-Output ''
    Write-Output '==========================================================================='
    Write-Output 'QUESTIONS TO PUT TO THE OPERATOR'
    Write-Output '==========================================================================='
    Write-Output 'Ask these one at a time, in this order, in these words. Where a question has a'
    Write-Output 'recommended answer, the recommendation is safe to accept.'
    Write-Output ''
    Write-Output 'TWO QUESTIONS USED TO COME FIRST AND ARE GONE, not renumbered away silently:'
    Write-Output 'one about stopping commands that destroy work, one about keeping passwords and'
    Write-Output 'keys out of the chat. Both halves of each were removed on 30 July 2026 at the'
    Write-Output 'owner`s instruction - the hooks that inspected commands and writes, and the six'
    Write-Output 'permissions.deny groups - so both answers had stopped doing anything and the'
    Write-Output 'parameters that carried them are gone too. NOTHING in this plugin refuses a'
    Write-Output 'destructive command or keeps a credential out of a file or out of the chat. If'
    Write-Output 'the operator asks about either, say that plainly; do not put it as a question.'
    Write-Output ''
    Write-Output '  Q1  END-OF-TURN WARNINGS                                 recommended: YES'
    Write-Output '      "Shall I switch on the warnings that appear when Claude finishes a reply -'
    Write-Output '       the conversation getting close to full, work that was never checked,'
    Write-Output '       documentation left behind by a code change, uncommitted changes sitting in'
    Write-Output '       a repository? They only ever warn. They never stop anything."'
    Write-Output '      -> pass  -Advisories yes   or   -Advisories no'
    Write-Output ''
    Write-Output '  Q2  THE HEALTH INDICATOR AT THE BOTTOM OF THE WINDOW     recommended: copy'
    Write-Output '      "Shall I switch on the small health indicator at the bottom of the Claude'
    Write-Output '       Code window? It turns red when something went wrong in this session.'
    Write-Output '       There are two ways to set it up:'
    Write-Output '         copy     - put a copy of the file in your home folder. Keeps working'
    Write-Output '                    even if this project folder is moved or renamed, but the copy'
    Write-Output '                    can fall behind the original and nothing tells you when it'
    Write-Output '                    has.'
    Write-Output '         junction - point at the file inside the project instead. It can never'
    Write-Output '                    fall behind, but the indicator disappears if the project'
    Write-Output '                    folder is moved, renamed, or is part-way through a git'
    Write-Output '                    operation.'
    Write-Output '         skip     - leave the bottom of the window alone."'
    Write-Output '      -> pass  -StatusLineMode copy | junction | skip'
    Write-Output ''
    Write-Output ("  Q3  HOW THE GOVERNANCE RUNS                              recommended: {0}" -f $hookRec)
    if ($D.discovered) {
        Write-Output '      "Claude Code has already found this plugin, so it will run its own checks'
        Write-Output '       with no further setup. Answer plugin unless you have been told otherwise:'
        Write-Output '       answering standalone would wire a SECOND copy into your settings and every'
        Write-Output '       check would then run twice."'
    } else {
        Write-Output '      "Claude Code has NOT found this plugin, so none of its checks are running.'
        Write-Output '       Answer standalone and I will wire them into your settings directly, using'
        Write-Output '       full paths. Answer plugin only if you are about to install it properly'
        Write-Output '       instead."'
    }
    Write-Output '      -> pass  -HookMode plugin | standalone'
    Write-Output ''
    Write-Output '  Q4  HELPER ROLES                                         recommended: YES'
    Write-Output '      "Shall I check that the helper roles the health indicator depends on are'
    Write-Output '       present? This only looks and reports - it writes nothing at all."'
    Write-Output '      -> pass  -AgentRoles yes   or   -AgentRoles no'
    Write-Output ''
    Write-Output 'THEN, ONE SECTION AT A TIME AND ONE YES EACH:'
    Write-Output '  1. -Step diff -Section statusline    then apply, only if the operator agrees'
    Write-Output '  2. -Step diff -Section hooks         then apply, only if the operator agrees'
    Write-Output '  3. -Step doctor'
    Write-Output ''
    Write-Output 'A no to any one section leaves that section untouched and does not cancel the'
    Write-Output 'others. Every apply is preceded by its own diff and its own yes. Add -DryRun to'
    Write-Output 'an apply to do everything except the write.'
}

# ===========================================================================
# SECTION PLANNING - one function per section, each returning the same shape
# ===========================================================================
# @{ ok; title; blurb; lines; merged; changes; warnings; extraActions }
#
#   merged        the whole settings object as it would be AFTER this section
#   changes       how many things would change; 0 means there is nothing to do
#   extraActions  writes OUTSIDE settings.json belonging to this section (the
#                 status-line file copy). Shown in the same diff and covered by
#                 the same single yes for that section - never by another's.
#
# None of these writes output. They build a plan; the step functions print it.

function New-StatusLinePlan {
    param($Settings, $D)
    $p = @{ ok = $true; title = 'statusLine'; lines = @(); changes = 0
            merged = $null; warnings = @(); extraActions = @(); blurb = @() }

    # WHAT THIS PARAGRAPH IS FOR, AND THE SENTENCE THAT WAS TAKEN OUT OF IT.
    # This is what an operator reads while deciding whether to wire the status
    # line up at all, so an overstatement here does not merely mislead - it buys
    # a yes. Until 3 September 2026 the last line called the status line "this
    # plugin's only visible indicator: unwired, the plugin runs and shows
    # nothing", and two other channels are visible on every session, both going
    # to the operator rather than to the model:
    #
    #   lib\session_start.ps1  the SessionStart banner, emitted as systemMessage
    #   lib\common.ps1         every turn-end advisory, on the same channel
    #
    # So "shows nothing" was false. What is TRUE, and is the honest reason to
    # say yes, is that the status line is the only CONTINUOUS one: the other two
    # speak once at the start of a session and once at the end of a turn, and
    # between them there is nothing on screen. Covered by tests\setup_merge.ps1
    # section 27, which asserts both that the old sentence is gone and that the
    # two other channels are named.
    $p.blurb = @(
        'statusLine is a settings.json key. A plugin cannot supply one - there is no',
        'manifest field for it and no hook event renders a line - which is half the reason',
        'this installer exists. It renders the HH health segment, and it is this plugin''s',
        'only CONTINUOUS indicator - not its only visible one. Unwired, you still get the',
        'banner at session start and an advisory at the end of a turn; what you lose is',
        'everything in between, which is where a fault first shows.'
    )

    $obj = if ($Settings.parses) { Copy-JsonObject -Obj $Settings.obj } else { [pscustomobject]@{} }
    if ($null -eq $obj) { $obj = [pscustomobject]@{} }
    $p.merged = $obj

    if ($StatusLineMode -eq 'skip') {
        $p.lines = @('Declined (-StatusLineMode skip). This section would change nothing.')
        return $p
    }

    if (-not $D.repoStatusLineOk) {
        $p.ok = $false
        $p.lines = @("REFUSING: the tracked status line is missing at $($D.repoStatusLine).",
                     'There is nothing to install and nothing to point at.')
        return $p
    }

    $l = New-Object System.Collections.ArrayList

    if ($StatusLineMode -eq 'copy') {
        $target = $D.installedStatusLine
        [void]$l.Add('MODE: copy')
        [void]$l.Add('  A copy of the tracked file goes into your home folder, and the setting points at')
        [void]$l.Add('  the copy.')
        [void]$l.Add('  TRADE-OFF: the indicator keeps working if this project folder is moved, renamed,')
        [void]$l.Add('  or is part-way through a git operation. But the copy and the original are then')
        [void]$l.Add('  two independent files and NOTHING on this machine compares them automatically -')
        [void]$l.Add('  edit either and the other is silently stale, including the case that costs most,')
        [void]$l.Add('  a fix made to the live copy and overwritten the next time this is run.')
        [void]$l.Add('  /lw-watchtower:doctor is what detects that drift, afterwards.')
        [void]$l.Add('')
        if ($D.installedOk -and $D.statusLineDrift -eq 'identical') {
            [void]$l.Add("  ACTION 1  none - the copy at $target is already identical to the original.")
        } else {
            $verb = if ($D.installedOk) { 'OVERWRITE (it currently DIFFERS from the original; the old one is kept as a .bak beside it)' } else { 'create' }
            [void]$l.Add("  ACTION 1  $verb")
            [void]$l.Add("            file  $target")
            [void]$l.Add("            from  $($D.repoStatusLine)")
            $p.extraActions += @{ kind = 'copyfile'; from = $D.repoStatusLine; to = $target; existed = $D.installedOk }
            $p.changes++
        }
    } else {
        # THE TRADE-OFF THIS MODE OFFERS IS A PROPERTY OF THIS MACHINE, AND
        # DETECTION ALREADY RESOLVED IT. Get-Detection reads the reparse-point
        # attribute of ~\.claude\skills\<plugin> into $D.skillIsLink, and
        # -Step detect prints the answer as 'junction/link' or 'a real
        # directory, NOT a link'. This section asked for none of it and stated
        # the LINK trade-off unconditionally - "the indicator can never fall
        # behind the original, because there is only one file" - which is the
        # single reason an operator picks this mode over copy.
        #
        # THAT SENTENCE IS FALSE WHEN THE SKILLS ENTRY IS AN ORDINARY
        # DIRECTORY. A marketplace install, a hand-copied plugin folder, a
        # restore from backup media that turned a link into its contents: any
        # of them leaves a COPY of the plugin under skills, the wiring below
        # points at the copy's statusline.ps1, and that file drifts from the
        # tracked original exactly as copy mode's does. Same wiring, opposite
        # promise - and the run making the promise had already printed the
        # fact that contradicts it.
        #
        # NO NEW PROBE IS MADE HERE. The three branches are the three states
        # $D.skillExists and $D.skillIsLink already distinguish, and the third
        # one matters: skillIsLink is $false for a real directory AND for no
        # skills entry at all, so a two-way test would tell an operator with
        # nothing installed that they have a copy.
        $target = [IO.Path]::Combine($D.skillLink, 'statusline\statusline.ps1')
        [void]$l.Add('MODE: junction')
        if ($D.skillExists -and $D.skillIsLink) {
            [void]$l.Add('  Nothing is copied. The setting points straight at the file inside the project,')
            [void]$l.Add('  through the skills-directory link.')
            [void]$l.Add("  ON THIS MACHINE $($D.skillLink) IS a link,")
            if ($D.skillTarget) { [void]$l.Add("  pointing at $($D.skillTarget),") }
            [void]$l.Add('  so the trade-off below is the one you are choosing.')
            [void]$l.Add('  TRADE-OFF: the indicator can never fall behind the original, because there is')
            [void]$l.Add('  only one file. But it breaks the moment that link is gone - a new machine where')
            [void]$l.Add('  the link was never created, a folder that was moved or renamed, a checkout')
            [void]$l.Add('  part-way through a rebase - and a status-line command that fails blanks the')
            [void]$l.Add('  whole row rather than showing an error.')
        } elseif ($D.skillExists) {
            [void]$l.Add('  Nothing is copied by this section. The setting points at the statusline.ps1')
            [void]$l.Add('  under the skills directory.')
            [void]$l.Add("  ON THIS MACHINE $($D.skillLink)")
            [void]$l.Add('  is a REAL DIRECTORY, NOT a link, so THIS MODE DOES NOT GIVE YOU THE THING IT')
            [void]$l.Add('  IS CHOSEN FOR: a directory is a COPY of this plugin and not a second name for')
            [void]$l.Add('  this checkout, so the file wired up below and the tracked original are two')
            [void]$l.Add('  independent files that drift exactly as copy mode''s do - without copy mode''s')
            [void]$l.Add('  check, because the drift line this installer prints compares')
            [void]$l.Add("  $($D.installedStatusLine) against the original,")
            [void]$l.Add('  and that is a different file again.')
            [void]$l.Add('  TRADE-OFF: you get copy mode''s drift AND junction mode''s fragility - it still')
            [void]$l.Add('  breaks if that directory is moved, renamed or removed, and a status-line')
            [void]$l.Add('  command that fails blanks the whole row rather than showing an error.')
            $p.warnings += "-StatusLineMode junction was asked for, but $($D.skillLink) is a REAL DIRECTORY on this machine and not a link. The file this would wire up is a SECOND copy that can silently fall behind the tracked original at $($D.repoStatusLine) - the one property this mode is chosen for does not hold here. Replace that directory with a junction, or choose -StatusLineMode copy and get the drift check that comes with it."
        } else {
            [void]$l.Add('  Nothing is copied. The setting points at a path under the skills directory.')
            [void]$l.Add("  ON THIS MACHINE there is no skills entry at $($D.skillLink)")
            [void]$l.Add('  at all, so whether the indicator can fall behind the original is not settled')
            [void]$l.Add('  yet: a link put there later cannot drift, a copied directory can. Until')
            [void]$l.Add('  something is there the row is blank.')
            [void]$l.Add('  TRADE-OFF: it breaks whenever that path is gone - a new machine where the link')
            [void]$l.Add('  was never created, a folder that was moved or renamed, a checkout part-way')
            [void]$l.Add('  through a rebase - and a status-line command that fails blanks the whole row')
            [void]$l.Add('  rather than showing an error.')
        }
        [void]$l.Add('')
        [void]$l.Add('  ACTION 1  none - nothing is copied in this mode.')
        if (-not [IO.File]::Exists($target)) {
            $p.warnings += "the junction path $target does not exist right now, so wiring it would blank the status-line row until that link is created."
        }
    }

    $cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $target.Replace('\', '/') + '"'
    $cur = Get-PropValue -Obj $obj -Name 'statusLine'

    # An existing refreshInterval is the operator's own tuning and is kept.
    $refresh = 120
    if ($null -ne $cur) {
        $ri = Get-PropValue -Obj $cur -Name 'refreshInterval'
        if ($null -ne $ri) { $refresh = $ri }
    }
    $new = [pscustomobject]@{ type = 'command'; command = $cmd; refreshInterval = $refresh }

    $curJson = if ($null -eq $cur) { '(not set)' } else { ConvertTo-CanonicalJson -Obj $cur }
    $newJson = ConvertTo-CanonicalJson -Obj $new

    [void]$l.Add('')
    [void]$l.Add('  ACTION 2  set the statusLine key in the settings file')
    [void]$l.Add('')
    [void]$l.Add('  BEFORE:')
    foreach ($x in ($curJson -split "`n")) { [void]$l.Add('    ' + $x.TrimEnd()) }
    [void]$l.Add('  AFTER:')
    foreach ($x in ($newJson -split "`n")) { [void]$l.Add('    ' + $x.TrimEnd()) }

    if ($curJson -ne $newJson) {
        Set-PropValue -Obj $obj -Name 'statusLine' -Value $new
        $p.changes++
        if ($null -ne $cur) {
            $p.warnings += 'a statusLine is already configured and would be REPLACED by the value above. The previous value is printed in full, and the whole file is backed up before the write.'
        }
    } else {
        [void]$l.Add('')
        [void]$l.Add('  Identical - the settings key needs no change.')
    }

    $p.lines = @($l.ToArray())
    return $p
}

function Get-HookScriptPaths {
    <#
      Every .ps1 path anywhere inside a hook group, in sorted order. Normalised
      to forward slashes and lower case by default, because that is what makes
      two spellings of one path compare equal.

      -Raw returns them EXACTLY as they appear in the file. That is for REPORTING
      only, and it is a distinction worth the switch: a report that hands the
      operator a lower-cased, slash-flipped path and then tells them to go and
      edit that entry has handed them a string their own search will not find.
      Never compare -Raw output; never print the normalised output.

      WALKED rather than read out of a known field, because hooks.json spells the
      script into an `args` ARRAY today and a `command` string is an equally
      legal shape. A reader that knows one shape silently misses the other, and
      missing it here means failing to recognise a registration that is already
      present - which is an extra copy of a hook, not a missing feature.

      EXTRACTED FROM the string rather than TESTED against the whole of it, and
      that changed on 3 August 2026 because the docstring above was claiming a
      shape-independence the code did not have. It matched `\.ps1$` against the
      ENTIRE string, so a `command` string was recognised in exactly one
      spelling - the one where the path is the last thing on the line. Both of
      the realistic spellings failed, and the failure is the consequence this
      docstring names:

          "...\lib\session_start.ps1"              quoted, which a path
                                                   containing a space forces
          ...\lib\supervisor.ps1 -HookEvent Stop   trailing argument, which
                                                   THIS PLUGIN'S OWN
                                                   supervisor registration needs

      Measured against the old spelling with an already-registered other-root
      SessionStart hook planted in each: the args-array form reported ALREADY
      REGISTERED FROM ANOTHER ROOT and applied 1 registration; both of the above
      reported nothing and applied 2. The command-string form is the canonical
      settings.json spelling, so the miss was on the MORE likely shape.

      The alternation takes a double-quoted path first, then a single-quoted
      one, then a bare run of non-space characters - so a path with a space in
      it survives when it is quoted, which is the only way it can legally be
      written on a command line anyway. A bare path containing a space is not
      recoverable and is not pretended to be.
    #>
    param($Group, [switch]$Raw)
    $paths = New-Object System.Collections.ArrayList
    $stack = New-Object System.Collections.Stack
    $stack.Push($Group)
    while ($stack.Count -gt 0) {
        $n = $stack.Pop()
        if ($null -eq $n) { continue }
        if ($n -is [string]) {
            foreach ($mm in [regex]::Matches([string]$n, '"([^"]+\.ps1)"|''([^'']+\.ps1)''|([^\s"'']+\.ps1)')) {
                $v = if     ($mm.Groups[1].Success) { $mm.Groups[1].Value }
                     elseif ($mm.Groups[2].Success) { $mm.Groups[2].Value }
                     else                           { $mm.Groups[3].Value }
                if ($Raw) { [void]$paths.Add([string]$v) }
                else      { [void]$paths.Add($v.Replace('\', '/').ToLowerInvariant()) }
            }
            continue
        }
        if ($n -is [System.Management.Automation.PSCustomObject]) {
            foreach ($pr in $n.PSObject.Properties) { $stack.Push($pr.Value) }
            continue
        }
        if ($n -is [System.Collections.IEnumerable]) { foreach ($i in $n) { $stack.Push($i) } }
    }
    return , @(@($paths.ToArray()) | Sort-Object)
}

# MATCHER SPELLINGS THIS PLUGIN HAS SHIPPED AND NO LONGER WRITES, mapped to what
# it writes now. Both identity functions below key on the matcher string, so
# WIDENING A MATCHER IN A RELEASE SILENTLY MAKES EVERY EXISTING REGISTRATION OF
# THAT HOOK UNRECOGNISABLE and setup adds a second one beside it. That is not
# hypothetical: v0.3.0 is a tagged, published release which registered
# lib/gate_delegate.ps1 on 'Edit|Write|NotebookEdit|Bash', and `PowerShell`
# joined that matcher on 1 August 2026 to close a shell-swap bypass. Measured on
# a machine whose hooks live in settings.json, the two runs differing ONLY in
# that token: without this table setup reported '10 registration(s) would be
# ADDED' and the merged value carried BOTH matchers pointing at the SAME
# absolute gate_delegate.ps1; with it, 9 and one entry. Two live registrations
# of the ONE hook that can block a tool call means two gate runs per call and
# two deny envelopes per refusal.
#
# WHY A TABLE AND NOT A LOOSER COMPARISON. Anything fuzzy - subset, sorted
# token overlap - would also collapse two hooks that are genuinely different,
# and Get-HookIdentity's whole job is to avoid a false 'already registered'
# against somebody else's plugin. An explicit list of spellings THIS repo has
# actually published is checkable against `git show <tag>:hooks/hooks.json`.
#
# THE MAINTENANCE COST IS REAL AND IS NOT DESIGNED AWAY: the next matcher
# change needs another entry here, in the same commit, or it reintroduces the
# duplicate. Nothing detects a missing entry automatically.
$script:LwgSupersededMatchers = @{
    # v0.3.0 -> v0.4.0, delegate gate. See git show v0.3.0:hooks/hooks.json.
    'edit|write|notebookedit|bash' = 'Edit|Write|NotebookEdit|Bash|PowerShell'
}

function Get-HookMatcherKey {
    <#
      The matcher a group should be COMPARED under: its own string, unless it is
      a spelling this plugin has superseded, in which case the current spelling.
      Comparison only - nothing is ever WRITTEN from this, so a stale matcher in
      settings.json stays exactly as the operator's file has it and is reported
      rather than rewritten.
    #>
    param([string]$Matcher)
    $k = ([string]$Matcher).ToLowerInvariant()
    if ($script:LwgSupersededMatchers.ContainsKey($k)) { return $script:LwgSupersededMatchers[$k] }
    return [string]$Matcher
}

function Get-HookSignature {
    <#
      The EXACT identity of a hook GROUP, so a second run recognises what the
      first one wrote. Deliberately NOT the whole serialised group: a timeout the
      operator tuned afterwards would then read as a different hook and get
      installed a second time. The matcher plus the scripts it runs is what makes
      two groups the same hook.

      This is identity FOR THIS ROOT. Two checkouts of the same plugin produce
      two different signatures, which is correct for "have I already written
      exactly this" and wrong for "is this hook already wired up at all" - see
      Get-HookIdentity, which answers the second question.

      "EXACT" IS NOT EXACT ABOUT THE MATCHER, and that is deliberate - see
      $script:LwgSupersededMatchers above. A matcher this plugin used to ship is
      compared as the one it ships now, so an upgrade recognises the entry it
      wrote last time instead of adding a second. The literal string is NOT lost:
      New-HooksPlan compares it separately and warns when it is stale, because
      recognising an old registration and leaving it in place silently would mean
      the tools added to the matcher stay ungated.
    #>
    param($Group)
    $m = Get-HookMatcherKey -Matcher ([string](Get-PropValue -Obj $Group -Name 'matcher'))
    return ($m + '|' + ((Get-HookScriptPaths -Group $Group) -join ';'))
}

function Get-HookIdentity {
    <#
      The ROOT-INDEPENDENT identity of a hook group: the matcher plus the LEAF
      names of the scripts it runs.

      WHY THIS EXISTS. Get-HookSignature above is built from ABSOLUTE paths,
      because ${CLAUDE_PLUGIN_ROOT} is substituted before the comparison is made.
      So a registration this installer wrote from ANOTHER checkout - a second
      clone, a colleague's path in a settings file that came in with a dotfiles
      repo - is invisible to it and gets added a second time, and both copies
      then fire. RENAMING OR MOVING THE FOLDER REACHES THE SAME STATE from one
      checkout: the registration on disk names the old path, nothing matches it,
      and setup writes a second one beside it. Every hook then runs twice, which
      is the exact failure the hooks section exists to avoid.

      The matcher is kept in the key. Within one event this plugin never
      registers two groups with the same matcher and the same script leaves -
      SessionStart is session_start.ps1 + supervisor.ps1, Stop is supervisor.ps1
      + stop_advisories.ps1 - so leaf names do not collapse two distinct
      registrations into one.

      WHAT IT COSTS, named rather than left to be found: a DIFFERENT plugin that
      happens to register a script with the same leaf name on the same matcher
      reads as "already registered", and setup declines to add ours and says so.
      That is a false report, not a false write - it never removes anything and
      it never stays quiet about it - and the operator can see both entries in
      the file the report names.

      WHAT IT DOES NOT FIX, because a signature over settings.json cannot: a
      registration supplied by the PLUGIN ITSELF out of hooks/hooks.json is not
      in settings.json at all, so no comparison here can see it. Only detection
      can - see Get-Detection.

      THE MATCHER GOES THROUGH Get-HookMatcherKey for the same reason it does in
      Get-HookSignature. Without that, this function's whole purpose failed for
      exactly the hook it mattered most for: on an upgrade that widened the
      delegate gate's matcher, session_start.ps1 from a moved root was correctly
      caught while the GATE group - same file, same run, same moved root - was
      added a second time, because its matcher had changed and this key had not
      been told the two spellings are one hook.
    #>
    param($Group)
    $m     = Get-HookMatcherKey -Matcher ([string](Get-PropValue -Obj $Group -Name 'matcher'))
    $leaves = @(Get-HookScriptPaths -Group $Group | ForEach-Object { ($_ -split '/')[-1] })
    return ($m + '|' + ((@($leaves) | Sort-Object) -join ';'))
}

function New-HooksPlan {
    param($Settings, $D)
    $p = @{ ok = $true; title = 'hooks'; lines = @(); changes = 0
            merged = $null; warnings = @(); extraActions = @(); blurb = @() }

    $mode = $HookMode
    if ($mode -eq 'auto') { $mode = if ($D.discovered) { 'plugin' } else { 'standalone' } }

    $p.blurb = @(
        'hooks in settings.json is the FALLBACK wiring. When Claude Code can discover this',
        'plugin, the plugin registers its own hooks and this section must stay empty - two',
        'registrations of the same script make every check run twice. When the plugin',
        'cannot be discovered, nothing runs at all, and this is how it gets wired in.'
    )

    $obj = if ($Settings.parses) { Copy-JsonObject -Obj $Settings.obj } else { [pscustomobject]@{} }
    if ($null -eq $obj) { $obj = [pscustomobject]@{} }
    $p.merged = $obj

    if ($mode -eq 'plugin') {
        $l = New-Object System.Collections.ArrayList
        [void]$l.Add('MODE: plugin  (the plugin registers its own hooks)')
        [void]$l.Add('')
        if ($D.discovered) {
            [void]$l.Add("Claude Code can discover the plugin at $($D.pluginRoot), so every hook event it")
            [void]$l.Add('declares is already registered by hooks/hooks.json. Nothing belongs here.')
        } else {
            [void]$l.Add("WARNING: 'plugin' was chosen, but nothing on this machine can discover the plugin -")
            [void]$l.Add('there is no junction under a skills directory and no marketplace install. NOTHING IS')
            [void]$l.Add('RUNNING. Either create the junction, or run this section again with')
            [void]$l.Add('-HookMode standalone.')
            $p.warnings += "hook mode 'plugin' was chosen but the plugin is not discoverable, so no hook of this plugin fires at all."
        }
        [void]$l.Add('')
        [void]$l.Add('This section would change nothing.')
        $p.lines = @($l.ToArray())
        return $p
    }

    # --- standalone ---------------------------------------------------------
    $hooksJson = [IO.Path]::Combine($D.pluginRoot, 'hooks\hooks.json')
    if (-not [IO.File]::Exists($hooksJson)) {
        $p.ok = $false
        $p.lines = @("REFUSING: $hooksJson is missing, so there is nothing to take the registrations from.")
        return $p
    }
    $src = $null
    try { $src = ([IO.File]::ReadAllText($hooksJson, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF)) | ConvertFrom-Json }
    catch {
        $p.ok = $false
        $p.lines = @("REFUSING: $hooksJson does not parse: $($_.Exception.Message)")
        return $p
    }
    if ($null -eq $src -or $null -eq $src.hooks) {
        $p.ok = $false
        $p.lines = @("REFUSING: $hooksJson has no 'hooks' object, so it registers nothing to copy.")
        return $p
    }

    # THE SUBSTITUTED VALUE, DERIVED ONCE AND USED BY BOTH THE DISCLOSURE BELOW
    # AND THE SUBSTITUTION ITSELF. They were two expressions eight lines apart
    # and only the substitution carried .Replace('\','/'), so this section - whose
    # whole pitch is that it re-spells nothing and discloses its ONE deviation
    # from hooks.json - printed that deviation in a spelling that does not occur
    # in the file it writes. An operator grepping the result for the string they
    # were shown, or hand-writing a matching entry from it, was working from a
    # string that is not there.
    $rootForJson = $D.pluginRoot.Replace('\', '/')

    $l = New-Object System.Collections.ArrayList
    [void]$l.Add('MODE: standalone  (the hook scripts are wired into settings.json by full path)')
    [void]$l.Add('')
    [void]$l.Add("Registrations are read from $hooksJson and are not re-spelled here, so this cannot")
    [void]$l.Add('drift from what the plugin itself would register. The only substitution is')
    [void]$l.Add("`${CLAUDE_PLUGIN_ROOT} -> $rootForJson, because that variable is defined for a")
    [void]$l.Add('plugin and not for settings.json. The FORWARD slashes are deliberate and are the')
    [void]$l.Add('exact characters written: they need no JSON escaping and PowerShell accepts them')
    [void]$l.Add('as a path on Windows. Changing them back to backslashes by hand is not required')
    [void]$l.Add('and is one more thing that can be got wrong.')
    [void]$l.Add('')
    if ($D.discovered) {
        [void]$l.Add('  ###################################################################')
        [void]$l.Add('  #  WARNING - DUPLICATE FIRING                                     #')
        [void]$l.Add('  #  Claude Code can ALREADY discover this plugin, so it already     #')
        [void]$l.Add('  #  registers these same hooks. Writing them here as well makes     #')
        [void]$l.Add('  #  every one of them run TWICE per event: two banners, two sets    #')
        [void]$l.Add('  #  of advisories, two log lines per record. Say no to this         #')
        [void]$l.Add('  #  section unless you are deliberately removing the plugin install.#')
        [void]$l.Add('  ###################################################################')
        [void]$l.Add('')
        # The BASIS for that warning, not just the warning. This box was
        # suppressed on every marketplace install until the detection probe was
        # fixed, so it now shows what it is arguing from and can be contradicted.
        [void]$l.Add('  it is discoverable because:')
        foreach ($e in $D.discoveryEvidence) { [void]$l.Add('    - ' + $e) }
        [void]$l.Add('')
        $p.warnings += 'the plugin is ALREADY discoverable, so these registrations would duplicate the plugin''s own and every hook would fire twice.'
    }

    # Which registrations the answers keep, and what each row on the consent
    # screen says. A hook is identified by the script it runs, so this cannot
    # drift from hooks.json either.
    #
    # gate_delegate.ps1 WAS MISSING FROM THIS MAP and was the only row of the ten
    # that rendered as '(unrecognised)  declared in hooks.json' - the one
    # component in this plugin that can refuse a tool call, on the one hook class
    # that can refuse one, unnamed on the single screen where a stranger consents
    # to it. Nothing was misconfigured by it: the registration itself was always
    # correct. The defect was the description, on the surface whose only job is
    # to describe.
    $keepReason = [ordered]@{
        'session_start.ps1'   = 'always - the banner and the self-check'
        'supervisor.ps1'      = 'always - failure capture and log rotation'
        'subagent_start.ps1'  = 'always - hands current facts to every worker'
        'post_edit.ps1'       = 'records edited paths for the end-of-turn warnings'
        'stop_advisories.ps1' = 'the end-of-turn warnings'
        'gate_delegate.ps1'   = 'refuses Edit/Write/NotebookEdit/Bash/PowerShell off the main thread - SHIPS SWITCHED OFF'
        'gate_send.ps1'       = 'refuses a SendMessage to a subagent it can prove is dead - SHIPS SWITCHED OFF'
        'gate_stop.ps1'       = 'refuses a turn end that claims completed work resting on a queued message - SHIPS SWITCHED OFF'
    }

    $hooksObj = Get-PropValue -Obj $obj -Name 'hooks'
    if ($null -eq $hooksObj) { $hooksObj = [pscustomobject]@{} }

    $addedDesc = New-Object System.Collections.ArrayList
    $skipped   = New-Object System.Collections.ArrayList

    foreach ($ev in $src.hooks.PSObject.Properties) {
        $eventName    = $ev.Name
        $existing     = Get-PropArray -Obj $hooksObj -Name $eventName
        $existingSigs = @($existing | ForEach-Object { Get-HookSignature -Group $_ })
        # Root-independent identity -> the paths the group actually runs, so the
        # report can NAME the other root rather than just assert one exists.
        # The paths are appended ONE AT A TIME, deliberately. Get-HookScriptPaths
        # returns its array behind a unary comma so an empty result survives the
        # return, and `$acc += @(that)` then appends the ARRAY as a single
        # element - which reaches the operator as the literal 'System.Object[]'
        # where a path should be. Measured, not assumed: that is what the report
        # printed before this loop was written out longhand.
        # THE LITERAL MATCHERS OF THE EXISTING GROUPS, AND HOW MANY THERE ARE,
        # kept beside the identity keys because those keys deliberately collapse
        # a superseded spelling into the current one (see
        # $script:LwgSupersededMatchers). Recognising an old registration is what
        # stops a NEW duplicate; NOT SAYING SO would trade that duplicate for
        # something quieter and worse - the tools added to the matcher would stay
        # ungated while setup reported the hook present.
        #
        # KEYED BY IDENTITY AND NOT BY SIGNATURE, and the count is kept, because
        # of the population this table actually serves: a machine that already
        # ran setup after the matcher widened has BOTH groups in its file
        # already, and that is the state the broken code CREATED. An earlier
        # version of this looked up one matcher per key, first-wins, and produced
        # an order-dependent report - with the current-matcher group written
        # first it printed a bare 'already registered in this file' and said
        # nothing at all about the stale group still firing beside it. Measured,
        # by seeding the same two groups in both orders. Collecting every matcher
        # under one identity is what makes the report say the same thing either
        # way, and the count is what lets it name a duplicate this installer did
        # not write and cannot remove.
        $existingByIdent = @{}
        foreach ($g in $existing) {
            $gi = Get-HookIdentity -Group $g
            if (-not $existingByIdent.ContainsKey($gi)) {
                $existingByIdent[$gi] = @{ count = 0; matchers = New-Object System.Collections.ArrayList }
            }
            $existingByIdent[$gi].count++
            $gm = [string](Get-PropValue -Obj $g -Name 'matcher')
            if (-not $existingByIdent[$gi].matchers.Contains($gm)) { [void]$existingByIdent[$gi].matchers.Add($gm) }
        }
        $existingIds  = @{}
        foreach ($g in $existing) {
            $gid = Get-HookIdentity -Group $g
            if (-not $existingIds.ContainsKey($gid)) { $existingIds[$gid] = @() }
            # -Raw: this list is only ever PRINTED, and it is printed so the
            # operator can find the entry in their own file.
            foreach ($sp in (Get-HookScriptPaths -Group $g -Raw)) { $existingIds[$gid] += [string]$sp }
        }
        $newList      = New-Object System.Collections.ArrayList
        foreach ($g in $existing) { [void]$newList.Add($g) }

        foreach ($group in @($ev.Value)) {
            # Substitute the plugin root through a full round trip, so the source
            # object is never mutated.
            $txt   = ConvertTo-Json -InputObject $group -Depth 40 -Compress
            $txt   = $txt.Replace('${CLAUDE_PLUGIN_ROOT}', $rootForJson)
            $subst = $txt | ConvertFrom-Json

            $sig  = Get-HookSignature -Group $subst
            $name = '(unrecognised)'
            foreach ($k in $keepReason.Keys) { if ($sig.Contains($k.ToLowerInvariant())) { $name = $k; break } }

            # A SILENT DEFAULT IS WHAT PRODUCED THE MISSING GATE ROW. '(unrecognised)'
            # plus 'declared in hooks.json' is a blank the operator is asked to
            # fill in for themselves, and the next hook added to hooks.json without
            # an entry above reproduces it exactly. So the fall-through says so on
            # the consent screen instead of reading as an ordinary row.
            #
            # A WARNING AND NOT A REFUSAL: the registration is whatever hooks.json
            # declares and is written unaltered either way. What is missing is this
            # file's description of it, which is a defect in this file and not a
            # reason to decline to wire up a hook the plugin ships.
            if ($name -eq '(unrecognised)') {
                $p.warnings += ($eventName + ' - a registration in ' + $hooksJson + ' runs a script this installer has no plain-language description for, so its row below reads (unrecognised). It is still written exactly as hooks.json declares it. This is a gap in bin\lwg-setup.ps1''s $keepReason table, not a fault in the registration - but it means one row of this consent screen tells you nothing about what it does.')
            }

            $keep = $true
            # NO GATE ANSWER KEEPS OR DROPS A HOOK, because there is no gate
            # answer. Both hooks that used to be governed by one were deleted on
            # 30 July 2026 - lib/gate_bash.ps1 with the destructive_gate module,
            # lib/gate_write.ps1 with secret_scan - and the two parameters that
            # selected them were deleted from this file afterwards, once they
            # governed nothing at either layer. hooks.json DOES register a
            # PreToolUse hook again - lib/gate_delegate.ps1, added 30 July 2026 -
            # and this loop deliberately has NO answer that drops it. That is not an
            # oversight: the gate is switched by interaction.delegate and ships
            # OFF, so registering it always installs no behaviour, whereas an
            # install-time question would leave an operator who later ran
            # /lw-watchtower:delegate on with a switch wired to a hook that was never
            # registered - a switch wired to nothing, in the installer.
            # -Advisories is the only answer left that changes what is registered.
            if     ($name -eq 'stop_advisories.ps1') { $keep = ($Advisories -eq 'yes') }
            elseif ($name -eq 'post_edit.ps1')       { $keep = ($Advisories -eq 'yes') }

            # The matcher this plugin would write NOW, for the stale-spelling
            # comparison below. Read off $subst rather than restated here, so it
            # cannot drift from hooks.json.
            $wantMatcher = [string](Get-PropValue -Obj $subst -Name 'matcher')

            # THE MATCHER REPORT, computed once and used by both "already there"
            # branches below, because the two questions it answers are true or
            # false independently of WHICH branch recognised the group: is one of
            # the spellings in this file one we no longer write, and is this hook
            # registered more than once. $ident is the aliased key, so both
            # spellings of one hook land on it.
            $ident   = Get-HookIdentity -Group $subst
            $identRec = $existingByIdent[$ident]
            $staleMatchers = @()
            $dupCount      = 0
            if ($null -ne $identRec) {
                $dupCount      = [int]$identRec.count
                $staleMatchers = @(@($identRec.matchers) | Where-Object { $_ -ne $wantMatcher })
            }
            $matcherNotes = New-Object System.Collections.ArrayList
            if ($staleMatchers.Count -gt 0) {
                $sm = (@($staleMatchers | ForEach-Object { "'$_'" }) -join ', ')
                [void]$matcherNotes.Add("$eventName / $name is registered in this file on a SUPERSEDED matcher this plugin no longer writes ($sm); it writes '$wantMatcher'. Nothing was rewritten - this installer does not edit entries it did not write on this run. THE TOOLS PRESENT IN THE NEW MATCHER AND ABSENT FROM THE OLD ONE ARE NOT HOOKED AT ALL until you change that entry by hand. Edit the 'matcher' of that group in settings.json to read '$wantMatcher'.")
            }
            if ($dupCount -gt 1) {
                # DETECTED, NOT REPAIRED, and the difference is stated because
                # this is the one place an operator could reasonably expect a
                # repair. The installer never removes, so a duplicate a previous
                # run wrote stays until they delete one themselves.
                [void]$matcherNotes.Add("$eventName / $name is registered $dupCount TIMES in this file, running the same script each time - so it fires $dupCount times per event. This installer never removes a registration, so it cannot repair that: delete all but one of those groups yourself, keeping the one whose matcher reads '$wantMatcher'.")
            }

            if (-not $keep) { [void]$skipped.Add("$eventName / $name - declined by the answers given"); continue }
            if ($existingSigs -contains $sig) {
                $tail = ''
                if ($staleMatchers.Count -gt 0) { $tail += ", but also on a SUPERSEDED matcher: " + ((@($staleMatchers | ForEach-Object { "'$_'" })) -join ', ') }
                if ($dupCount -gt 1)            { $tail += " - and registered $dupCount TIMES" }
                [void]$skipped.Add("$eventName / $name - already registered in this file$tail")
                foreach ($n in $matcherNotes) { $p.warnings += $n }
                continue
            }

            # THE SAME SCRIPT, REGISTERED FROM A DIFFERENT ROOT. Adding beside it
            # makes that hook fire twice, so it is not added. REMOVING the other
            # entry is also not on the table: this installer never removes, and
            # the other root may be the one the operator actually wants to run -
            # it could be a live second checkout, or the path this very install
            # used to sit at before the folder was renamed. Setup cannot tell
            # those apart and does not try. It reports, names both paths, and
            # leaves the decision where it belongs.
            #
            # THE COST OF THAT CHOICE, stated: a registration pointing at a
            # checkout that has been DELETED is also left alone, so setup will
            # not repair a dead entry. It will keep saying so on every run, which
            # is the visible failure rather than the silent one.
            if ($existingIds.ContainsKey($ident)) {
                $where = (@($existingIds[$ident] | Sort-Object -Unique) -join ', ')
                $rootTail = ''
                if ($staleMatchers.Count -gt 0) { $rootTail += ' - and on a SUPERSEDED matcher: ' + ((@($staleMatchers | ForEach-Object { "'$_'" })) -join ', ') }
                if ($dupCount -gt 1)            { $rootTail += " - and registered $dupCount TIMES" }
                [void]$skipped.Add("$eventName / $name - ALREADY REGISTERED FROM ANOTHER ROOT: $where$rootTail")
                $p.warnings += "$eventName / $name is already registered in this file, running the same script from a DIFFERENT root ($where). Nothing was added beside it - two registrations of one script fire it twice - and nothing was removed. Decide which root should run it and edit that entry yourself."
                # A MOVED ROOT, A SUPERSEDED MATCHER AND AN EXISTING DUPLICATE
                # can all be true at once, and each is reported separately
                # because each has a different fix: which checkout should run
                # this, which tools are hooked at all, and how many copies fire.
                foreach ($n in $matcherNotes) { $p.warnings += $n }
                continue
            }

            [void]$newList.Add($subst)
            $why = if ($keepReason.Contains($name)) { $keepReason[$name] } else { 'declared in hooks.json' }
            [void]$addedDesc.Add("  + $($eventName.PadRight(20)) $($name.PadRight(22)) $why")
            $p.changes++
        }

        if ($newList.Count -gt 0) { Set-PropValue -Obj $hooksObj -Name $eventName -Value ([object[]]$newList.ToArray()) }
    }

    Set-PropValue -Obj $obj -Name 'hooks' -Value $hooksObj
    $p.merged = $obj

    if ($addedDesc.Count -eq 0) {
        [void]$l.Add('Nothing to add - every registration the answers selected is already in this file.')
    } else {
        [void]$l.Add("$($addedDesc.Count) registration(s) would be ADDED:")
        foreach ($x in $addedDesc) { [void]$l.Add($x) }
    }
    if ($skipped.Count -gt 0) {
        [void]$l.Add('')
        [void]$l.Add('not added:')
        foreach ($x in $skipped) { [void]$l.Add("  - $x") }
    }
    [void]$l.Add('')
    [void]$l.Add('the complete hooks value after the change:')
    foreach ($x in ((ConvertTo-CanonicalJson -Obj $hooksObj) -split "`n")) { [void]$l.Add('  ' + $x.TrimEnd()) }

    $p.lines = @($l.ToArray())
    return $p
}

function Get-SectionPlan {
    param([string]$Name, $Settings, $D)
    switch ($Name) {
        'statusline'  { return (New-StatusLinePlan  -Settings $Settings -D $D) }
        'hooks'       { return (New-HooksPlan       -Settings $Settings -D $D) }
    }
    return $null
}

function Get-TouchedKey {
    param([string]$Name)
    switch ($Name) {
        'statusline'  { return 'statusLine' }
        'hooks'       { return 'hooks' }
    }
    return ''
}

function Get-AnswerArgs {
    return ("-Advisories {0} -AgentRoles {1} -HookMode {2} -StatusLineMode {3}" -f `
        $Advisories, $AgentRoles, $HookMode, $StatusLineMode)
}

# ===========================================================================
# STEPS - each writes its report and sets $script:Exit. None returns a code.
# ===========================================================================

function Write-ConcurrentRefusal {
    <#
      The exit-4 report, in one place because it is reachable from two and the
      two are NOT the same statement. Before the section's non-settings writes
      have run, nothing at all has been written and the headline says so. After
      they have, the headline that used to be printed - 'NOTHING WAS WRITTEN' -
      was false about a file the operator may have written themselves, so this
      one names every file that did land and says the refusal does not undo them.

      $AlreadyWritten IS THE LIST OF FILES, not a boolean, because the operator's
      next question is which file and the answer has to be on the same screen.

      WHAT IT COVERS, precisely, so the list is not read as more than it is: the
      files Invoke-Apply's own extraActions loop copied on THIS run. It is not an
      audit of the machine. A section that ever grows a write of some other kind,
      or a write made anywhere but that loop, is absent from it until it is added
      there too.
    #>
    param([string]$Detail, [string[]]$AlreadyWritten = @())

    Write-Output ''
    if ($AlreadyWritten.Count -eq 0) {
        Write-Output 'CONCURRENT MODIFICATION - NOTHING WAS WRITTEN.'
    } else {
        Write-Output 'CONCURRENT MODIFICATION - settings.json WAS NOT WRITTEN.'
        Write-Output '  BUT THIS RUN HAD ALREADY WRITTEN THE FILE(S) BELOW before the change was'
        Write-Output '  detected, and refusing does not undo them:'
        foreach ($f in $AlreadyWritten) { Write-Output ("    {0}" -f $f) }
        Write-Output '  Each one that replaced an existing file has a .lwg-<stamp>.bak beside it, named'
        Write-Output '  above; -Step rollback restores settings.json only and never these.'
    }
    Write-Output ("  {0}" -f $Detail)
    Write-Output '  Something rewrote the settings file between the diff that was approved and this'
    Write-Output '  write. Claude Code rewrites settings.json itself, and another session or another'
    Write-Output '  agent may be editing it right now. Merging onto a file the operator never saw'
    Write-Output '  would silently discard whatever that change was.'
    Write-Output '  Run -Step diff again, show the operator the NEW diff, and ask again.'
}

function Invoke-Diff {
    param($Settings, $D, [string]$Name)

    $order = @{ statusline = 1; hooks = 2 }
    Write-Output '==========================================================================='
    Write-Output ("SECTION {0} of 2   {1}" -f $order[$Name], $Name)
    Write-Output '==========================================================================='
    Write-Output ("target file : {0}" -f $Settings.path)
    if (-not $Settings.exists) {
        Write-Output 'file state  : does not exist - it would be created'
    } elseif ($Settings.parses) {
        Write-Output ("file state  : exists and parses, {0} bytes" -f $Settings.bytes.Length)
    } else {
        Write-Output ("file state  : EXISTS BUT DOES NOT PARSE - {0}" -f $Settings.error)
    }
    Write-Output ("BASEHASH: {0}" -f $Settings.hash)
    Write-Output '   (pass that back as -BaseHash on the apply. If anything rewrites the file in'
    Write-Output '    between - and the CLI rewrites it itself - the write is refused.)'
    Write-Output ''

    if ($Settings.exists -and -not $Settings.parses) {
        Write-Output 'REFUSED: this settings file does not parse, so nothing can be merged into it'
        Write-Output 'safely. Fix or restore that file first. Setup will not overwrite a settings file'
        Write-Output 'it cannot read - that is exactly how every other setting in it gets lost.'
        Write-Output 'The other section cannot be applied either, for the same reason.'
        $script:Exit = 5
        return
    }

    $plan = Get-SectionPlan -Name $Name -Settings $Settings -D $D
    if ($null -eq $plan) { Write-Output "unknown section '$Name'"; $script:Exit = 5; return }

    foreach ($b in $plan.blurb) { Write-Output $b }
    Write-Output ''
    Write-Output '--- WHAT WOULD CHANGE -----------------------------------------------------'
    foreach ($x in $plan.lines) { Write-Output $x }

    if ($plan.warnings.Count -gt 0) {
        Write-Output ''
        Write-Output '--- READ BEFORE SAYING YES ------------------------------------------------'
        foreach ($w in $plan.warnings) { Write-Output ('  ! ' + $w) }
    }

    if (-not $plan.ok) {
        Write-Output ''
        Write-Output 'This section CANNOT be applied, for the reason above. The other section is'
        Write-Output 'unaffected - carry on with it.'
        $script:Exit = 2
        return
    }

    Write-Output ''
    Write-Output '--- WHAT WOULD NOT CHANGE -------------------------------------------------'
    if ($Settings.parses -and $null -ne $plan.merged) {
        $cmp = Compare-UnrelatedKeys -Before $Settings.obj -After $plan.merged -Touched (Get-TouchedKey -Name $Name)
        if ($cmp.changed.Count -eq 0 -and $cmp.dropped.Count -eq 0) {
            Write-Output ("  {0} other top-level key(s) compared value-by-value: all unchanged" -f $cmp.checked)
        } else {
            Write-Output ("  {0} other top-level key(s) compared value-by-value" -f $cmp.checked)
            Write-Output ("  CHANGED: {0}   DROPPED: {1}" -f ($cmp.changed -join ', '), ($cmp.dropped -join ', '))
            Write-Output '  That is a BUG in this installer. Do NOT approve this section.'
            $script:Exit = 1
            return
        }
    } else {
        Write-Output '  (nothing to preserve - the file is being created)'
    }
    Write-Output '  No other section is touched. statusLine and hooks are written'
    Write-Output '  one at a time, each behind its own yes.'
    Write-Output ''
    Write-Output 'FORMATTING NOTE, so it is not a surprise afterwards: applying re-serialises the'
    Write-Output 'whole file. Indentation becomes PowerShell''s four spaces, and the characters'
    Write-Output '< > & '' are written as \u003c \u003e \u0026 \u0027. Every VALUE is unchanged and'
    Write-Output 'the file is backed up first, but the byte layout of untouched sections does move.'
    Write-Output ''
    if ($plan.changes -eq 0) {
        Write-Output 'NOTHING TO DO. This section is already in the state requested; applying it now'
        Write-Output 'would write nothing and would not even take a backup.'
    } else {
        Write-Output ("TO APPLY ({0} change(s)), and ONLY if the operator has said yes to THIS section:" -f $plan.changes)
        Write-Output ''
        Write-Output ("  ... -File bin\lwg-setup.ps1 -Step apply -Section {0} -BaseHash {1} {2}" -f $Name, $Settings.hash, (Get-AnswerArgs))
        Write-Output ''
        Write-Output '  Add -DryRun to that line to do everything except the write.'
    }
    $script:Exit = 0
}

function Invoke-Apply {
    param($Settings, $D, [string]$Name)

    if ([string]::IsNullOrWhiteSpace($BaseHash)) {
        Write-Output 'REFUSED: -BaseHash was not supplied.'
        Write-Output 'apply writes only against the exact file state a diff was shown for. Run'
        Write-Output ("  -Step diff -Section {0}" -f $Name)
        Write-Output 'first, show the operator that diff, and pass back the BASEHASH it printed.'
        Write-Output 'NOTHING WAS WRITTEN.'
        $script:Exit = 5
        return
    }

    if ($Settings.exists -and -not $Settings.parses) {
        Write-Output ("REFUSED: {0} does not parse - {1}" -f $Settings.path, $Settings.error)
        Write-Output 'Setup will not overwrite a settings file it cannot read. NOTHING WAS WRITTEN.'
        $script:Exit = 5
        return
    }

    $plan = Get-SectionPlan -Name $Name -Settings $Settings -D $D
    if ($null -eq $plan) { Write-Output "unknown section '$Name'. NOTHING WAS WRITTEN."; $script:Exit = 5; return }
    if (-not $plan.ok) {
        Write-Output 'REFUSED: this section cannot be applied.'
        foreach ($x in $plan.lines) { Write-Output $x }
        Write-Output 'NOTHING WAS WRITTEN. The other sections are unaffected.'
        $script:Exit = 5
        return
    }

    Write-Output ("APPLY  section '{0}'   target {1}" -f $plan.title, $Settings.path)
    if ($DryRun) { Write-Output 'DRY RUN - nothing will be written by this invocation.' }
    Write-Output ''

    # THE PLAN'S WARNINGS ARE REPRINTED HERE. They used to appear on the diff
    # only, which was survivable while every warning meant "think again before
    # you say yes". It stopped being survivable when a plan gained a warning that
    # explains why it is changing NOTHING: a hook already registered from another
    # root is left alone and reported, and if every hook in the section is in that
    # state the run falls into the no-change branch below and would otherwise
    # print 'Already in the state requested' - which is false. It is not in the
    # state requested; it is in a state this installer declined to change.
    if ($plan.warnings.Count -gt 0) {
        Write-Output '--- READ THIS ------------------------------------------------------------'
        foreach ($w in $plan.warnings) { Write-Output ('  ! ' + $w) }
        Write-Output ''
    }

    if ($plan.changes -eq 0) {
        if ($plan.warnings.Count -gt 0) {
            Write-Output 'NOTHING WAS WRITTEN, and this is NOT the same as "already in the state you asked'
            Write-Output 'for" - read the line(s) above. Something is registered that this installer will'
            Write-Output 'not add beside and will not remove. No backup taken, the file is untouched down'
            Write-Output 'to its timestamp.'
        } else {
            Write-Output 'Already in the state requested. No backup taken, no write performed, the file is'
            Write-Output 'untouched down to its timestamp. This is what running setup a second time does.'
        }
        $script:Exit = 0
        return
    }

    # THE CONCURRENCY REFUSAL IS DECIDED HERE, BEFORE THE FIRST WRITE OF ANY
    # KIND, and it used to be decided inside Save-Settings - which runs AFTER the
    # extraActions loop below, for the good reason stated at that loop. The
    # result was a run that replaced the operator's own ~\.claude\statusline.ps1,
    # printed BACKUP and COPIED for it, and then printed
    # 'CONCURRENT MODIFICATION - NOTHING WAS WRITTEN.' and exited 4 - a code this
    # file's own header defines as "NOTHING was written". Measured in a sandbox,
    # not reasoned about: the copy landed and the headline denied it.
    #
    # Hoisting it keeps the 'files first' ordering intact for every run that
    # proceeds, which is what that ordering is for: a settings key must never
    # point at a file that is not there yet. It only removes the case where the
    # run was never going to proceed at all.
    #
    # -DryRun REACHES THIS TOO, deliberately. A dry run against a file that has
    # moved on cannot tell the operator what the real apply would do, so it is
    # the same refusal and the same 4.
    $stale = Get-BaseHashMismatch -Path $Settings.path -ExpectHash $BaseHash
    if ($stale) {
        Write-ConcurrentRefusal -Detail $stale
        $script:Exit = 4
        return
    }

    # Files outside settings.json belonging to this section, done first so a
    # settings key is never pointed at a file that is not there yet.
    #
    # WHAT LANDED IS RECORDED AS IT LANDS. Every later refusal in this function
    # has to be able to say which files this run had already replaced, because
    # none of them is undone by refusing and one of them may be a file the
    # operator wrote themselves.
    $landed = New-Object System.Collections.ArrayList
    foreach ($a in $plan.extraActions) {
        if ($a.kind -ne 'copyfile') { continue }
        if ($DryRun) {
            Write-Output ("WOULD COPY  {0}" -f $a.from)
            Write-Output ("        ->  {0}" -f $a.to)
            continue
        }
        try {
            $dir = Split-Path -Parent $a.to
            if ($dir -and -not [IO.Directory]::Exists($dir)) { [void][IO.Directory]::CreateDirectory($dir) }
            $bk = ''
            if ($a.existed -and [IO.File]::Exists($a.to)) {
                $bk = "$($a.to).lwg-$((Get-Date).ToString('yyyyMMdd-HHmmss')).bak"
                [IO.File]::Copy($a.to, $bk, $true)
                Write-Output ("BACKUP      {0}" -f $bk)
            }
            [IO.File]::Copy($a.from, $a.to, $true)
            Write-Output ("COPIED      {0}" -f $a.to)
            # AFTER the copy, never before: a file this run failed to write is
            # not a file this run wrote, and a refusal that lists it would be
            # wrong in the direction that sends the operator looking for a
            # backup of something that was never touched.
            if ($bk) { [void]$landed.Add("$($a.to)   (the file it replaced is at $bk)") }
            else     { [void]$landed.Add("$($a.to)   (created by this run; there was nothing here before)") }
        } catch {
            Write-Output ("COPY FAILED {0}: {1}" -f $a.to, $_.Exception.Message)
            Write-Output 'Carrying on with the settings key so the rest of the section is not lost. The'
            Write-Output 'status line will not render until that file exists.'
            Add-Caveat "the status-line file could not be copied to $($a.to)"
        }
    }

    $res = Save-Settings -Path $Settings.path -Obj $plan.merged -ExpectHash $BaseHash -WhatIfOnly:$DryRun

    # STILL HERE, AND STILL REACHABLE. The check hoisted above closes the window
    # that spans the extraActions loop; this one closes the window that spans the
    # loop itself, which takes real time on a slow volume. Reaching this branch
    # now means something rewrote the file DURING this run rather than before it,
    # and the status-line copy above may then have landed - so this message no
    # longer claims that nothing at all was written, only that settings.json was
    # not, which is the part it can vouch for.
    if ($res.concurrent) {
        Write-ConcurrentRefusal -Detail $res.error -AlreadyWritten @($landed.ToArray())
        $script:Exit = 4
        return
    }
    if (-not $res.ok) {
        Write-Output ''
        Write-Output ("FAILED: {0}" -f $res.error)
        if ($res.restored)   { Write-Output ("  The backup at {0} was restored automatically." -f $res.backup) }
        elseif ($res.backup) { Write-Output ("  A backup exists at {0}." -f $res.backup) }
        # THE SAME DISCLOSURE AS THE EXIT-4 PATH, for the same reason. This
        # branch never claimed nothing was written, so it was the weaker instance
        # of the same silence - but an operator reading FAILED still has no way
        # of knowing their own statusline.ps1 was replaced two lines earlier.
        if ($landed.Count -gt 0) {
            Write-Output '  THIS RUN HAD ALREADY WRITTEN THE FILE(S) BELOW, and the failure does not undo'
            Write-Output '  them. -Step rollback restores settings.json only and never these:'
            foreach ($f in $landed) { Write-Output ("    {0}" -f $f) }
        }
        $script:Exit = 1
        return
    }
    if ($res.unchanged) {
        Write-Output 'The merged result is byte-identical to what is already on disk. Nothing written.'
        $script:Exit = 0
        return
    }
    if ($DryRun) {
        Write-Output ''
        Write-Output ("DRY RUN COMPLETE. The merge was built and validated; it would have written {0} bytes." -f $res.bytes)
        Write-Output 'No backup was taken and the file was not touched.'
        $script:Exit = 0
        return
    }

    $after = Read-SettingsFile -Path $Settings.path
    $cmp   = Compare-UnrelatedKeys -Before $Settings.obj -After $after.obj -Touched (Get-TouchedKey -Name $Name)

    Write-Output ''
    if ($res.backup) { Write-Output ("BACKUP   : {0}" -f $res.backup) }
    else             { Write-Output 'BACKUP   : none - the file did not exist before this' }
    Write-Output ("WROTE    : {0} bytes; re-read from disk and it parses" -f $res.bytes)
    Write-Output ("CHANGED  : {0} thing(s) in section '{1}'" -f $plan.changes, $plan.title)
    if ($cmp.changed.Count -eq 0 -and $cmp.dropped.Count -eq 0) {
        Write-Output ("PRESERVED: {0} other top-level key(s), compared value-by-value: all unchanged" -f $cmp.checked)
    } else {
        Write-Output ("PRESERVED: {0} other top-level key(s) compared" -f $cmp.checked)
        Write-Output ("  CHANGED: {0}   DROPPED: {1}" -f ($cmp.changed -join ', '), ($cmp.dropped -join ', '))
        Write-Output '  A key that should not have moved has moved. Roll this back:'
        Write-Output ("  ... -File bin\lwg-setup.ps1 -Step rollback -SettingsPath `"{0}`"" -f $Settings.path)
        $script:Exit = 1
        return
    }
    Write-Output ("NEW HASH : {0}" -f $after.hash)
    Write-Output ''
    Write-Output 'THE WAY BACK, if this turns out to be wrong:'
    Write-Output ("  ... -File bin\lwg-setup.ps1 -Step rollback -SettingsPath `"{0}`"" -f $Settings.path)
    Write-Output '  which restores the backup named above. Setup never deletes a backup.'
    $script:Exit = 0
}

function Invoke-Rollback {
    param($Settings)
    $path = $Settings.path
    $dir  = Split-Path -Parent $path
    $leaf = Split-Path -Leaf   $path

    Write-Output ("ROLLBACK  target {0}" -f $path)
    Write-Output ''

    $all = @()
    try { $all = @([IO.Directory]::GetFiles($dir, "$leaf.lwg-*.bak")) } catch { }
    # A pre-rollback safety copy is not something to roll back TO; offering it
    # would let repeated rollbacks walk forwards again.
    $all = @($all | Where-Object { $_ -notlike '*.lwg-prerollback-*' })

    if ($all.Count -eq 0 -and [string]::IsNullOrWhiteSpace($BackupPath)) {
        Write-Output 'No backup taken by this command was found beside that file, so there is nothing to'
        Write-Output 'restore. Setup only ever restores a backup IT took; it will not guess that some'
        Write-Output 'other .bak file is the right one.'
        $script:Exit = 5
        return
    }

    if ($all.Count -gt 0) {
        Write-Output 'backups this command has taken, newest first:'
        foreach ($b in ($all | Sort-Object -Descending)) {
            $sz = 0
            try { $sz = (New-Object IO.FileInfo($b)).Length } catch { }
            Write-Output ("  {0}  ({1} bytes)" -f $b, $sz)
        }
        Write-Output ''
    }

    $pick = $BackupPath
    if ([string]::IsNullOrWhiteSpace($pick)) { $pick = @($all | Sort-Object -Descending)[0] }
    if (-not [IO.File]::Exists($pick)) {
        Write-Output ("REFUSED: {0} does not exist. NOTHING WAS RESTORED." -f $pick)
        $script:Exit = 5
        return
    }

    $bk = Read-SettingsFile -Path $pick
    if (-not $bk.parses) {
        Write-Output ("REFUSED: the backup {0} does not itself parse - {1}" -f $pick, $bk.error)
        Write-Output 'Restoring an unreadable file over a readable one makes things worse, so nothing'
        Write-Output 'was restored.'
        $script:Exit = 5
        return
    }

    if ($DryRun) {
        Write-Output ("DRY RUN: would restore {0} ({1} bytes) over {2}" -f $pick, $bk.bytes.Length, $path)
        $script:Exit = 0
        return
    }

    try {
        $cur = Read-SettingsFile -Path $path
        if ($cur.exists) {
            $pre = "$path.lwg-prerollback-$((Get-Date).ToString('yyyyMMdd-HHmmss')).bak"
            [IO.File]::WriteAllBytes($pre, $cur.bytes)
            Write-Output ("kept the current file first : {0}" -f $pre)
        }
        [IO.File]::Copy($pick, $path, $true)
    } catch {
        Write-Output ("FAILED: {0}" -f $_.Exception.Message)
        $script:Exit = 1
        return
    }

    $after = Read-SettingsFile -Path $path
    if (-not $after.parses) {
        Write-Output ("RESTORED, but the result does not parse: {0}" -f $after.error)
        $script:Exit = 1
        return
    }
    Write-Output ("RESTORED : {0}" -f $pick)
    Write-Output ("       -> {0}" -f $path)
    Write-Output ("   sha256  {0}" -f $after.hash)
    Write-Output 'Rolling back does NOT undo the status-line file copy; that has its own .bak beside it.'
    $script:Exit = 0
}

function Invoke-Doctor {
    $doc = [IO.Path]::Combine($script:PluginRoot, 'bin\lwg-doctor.ps1')
    Write-Output '==========================================================================='
    Write-Output 'FINAL CHECK - bin\lwg-doctor.ps1'
    Write-Output '==========================================================================='
    Write-Output 'Setup that cannot fail is not setup. This is the part that is allowed to say no.'
    Write-Output ''
    if (-not [IO.File]::Exists($doc)) {
        Write-Output ("the doctor is missing at {0}, so setup CANNOT tell you whether any of this" -f $doc)
        Write-Output 'worked. Do not read that as success.'
        $script:Exit = 3
        return
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $doc
    $code = $LASTEXITCODE
    Write-Output ''
    Write-Output '---------------------------------------------------------------------------'
    if ($null -eq $code) {
        Write-Output 'the doctor returned no exit code, so its verdict is unknown. Setup cannot report'
        Write-Output 'a result it did not get.'
        $script:Exit = 3
        return
    }
    switch ($code) {
        0 { Write-Output 'SETUP RESULT: PASS - the doctor found no faults.' }
        1 { Write-Output 'SETUP RESULT: FAIL - the doctor found at least one fault, named above. Setup'
            Write-Output '              finished AND the thing it set up is not healthy. Both are true at'
            Write-Output '              once and neither cancels the other.' }
        2 { Write-Output 'SETUP RESULT: PASS WITH CAVEATS - no fault, but the doctor raised the warnings'
            Write-Output '              printed above. Read them; they are not noise.' }
        3 { Write-Output 'SETUP RESULT: UNKNOWN - the doctor did not complete, so nothing was verified.' }
        default { Write-Output ("SETUP RESULT: UNKNOWN - the doctor returned {0}, which is not one of its four codes." -f $code) }
    }
    $script:Exit = $code
}

# ===========================================================================
# MAIN
# ===========================================================================

try {
    . ([IO.Path]::Combine($script:PluginRoot, 'lib\common.ps1'))

    if ([string]::IsNullOrWhiteSpace($SettingsPath)) { $SettingsPath = Get-DefaultSettingsPath }
    $settings = Read-SettingsFile -Path $SettingsPath

    switch ($Step) {

        'doctor'   { Invoke-Doctor }

        'rollback' { Invoke-Rollback -Settings $settings }

        'detect'   {
            $D = Get-Detection
            Write-DetectionReport -D $D -Settings $settings
            Write-Questions -D $D
            if ($script:Caveats.Count -gt 0) {
                Write-Output ''
                Write-Output '--- THINGS THAT ARE ALREADY WRONG -----------------------------------------'
                foreach ($c in $script:Caveats) { Write-Output ('  ! ' + $c) }
                Write-Output '  Setup can still run. None of the above is fixed by running it.'
                $script:Exit = 2
            } else {
                $script:Exit = 0
            }
        }

        default {
            if ([string]::IsNullOrWhiteSpace($Section)) {
                Write-Output ("-Step {0} needs -Section statusline|hooks." -f $Step)
                Write-Output 'There is no -Section all: the two are confirmed separately, always.'
                $script:Exit = 5
            } else {
                $D = Get-Detection
                if ($Step -eq 'diff') { Invoke-Diff  -Settings $settings -D $D -Name $Section }
                else                  { Invoke-Apply -Settings $settings -D $D -Name $Section }
            }
        }
    }

} catch {
    Write-Output ("LW-WATCHTOWER setup could not complete: {0}" -f $_.Exception.Message)
    Write-Output ("  at line {0}: {1}" -f $_.InvocationInfo.ScriptLineNumber, $_.InvocationInfo.Line.Trim())
    Write-Output 'Whatever was printed above is a fragment of a run, not the result of one. If this'
    Write-Output 'happened during -Step apply, look at the file and at the newest .lwg-*.bak beside'
    Write-Output 'it before running anything again.'
    $script:Exit = 3
}

exit $script:Exit
