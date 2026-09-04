#requires -version 5
<#
  LW-WATCHTOWER uninstall - remove this plugin's footprint, and say what it left.

      powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-uninstall.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-uninstall.ps1 -RemoveStatusLine -Apply

  Backs /lw-watchtower:uninstall. DRY RUN IS THE DEFAULT. Without -Apply this reads
  and prints and changes nothing at all, which is the only mode an operator can
  safely be talked into running by a model.

  WHAT IT WILL NOT DO, EVER

    * It will not delete logs or state. health.jsonl and lw-watchtower.jsonl are the
      evidence of everything this plugin recorded - including whatever made you
      want to uninstall it. They are reported, with their paths and sizes, and
      left where they are unless you pass -RemoveData AND the confirmation token.
      On a machine installed before the 3 August 2026 rename the event log is
      lw-gmhh.jsonl in an lw-gmhh* directory; that directory is swept and
      reported too, marked LEGACY, so an uninstall does not walk past it. See
      $script:LwgLegacyDataNames below.
    * It will not remove the directory junction. Removing a junction with the
      wrong verb deletes the TARGET's contents, which here is the git clone; the
      exact command that does it safely is printed instead.
    * It will not silently hand-edit ~/.claude/settings.json. That file is
      rewritten by the CLI underneath whatever is reading it - observed mid-edit
      on this machine - so every write here re-reads it, compares a SHA256 taken
      at plan time, and aborts rather than clobber a concurrent change. A backup
      is taken first, and existing backups are listed so a restore is possible.
    * It will not remove permissions.deny entries unless asked with
      -RemovePermissions. Those rules are the layer that CANNOT fail open: they
      are evaluated by the CLI itself, before and regardless of any hook, so
      removing them is a bigger change than removing this plugin.

  WHAT IT CANNOT KNOW is printed on every run. A footprint report that omits its
  own blind spots reads as a complete one.

  Exit codes:

      0  the dry run completed, or every requested removal was made
      1  REFUSED - a guard was not satisfied; NOTHING AT ALL was written. This
         is the whole-run refusal: a wrong -ConfirmToken, an unreadable
         settings.json, a backup that does not parse, -RestoreSettings passed
         together with a removal flag.
      2  something this script was ASKED to remove was not removed - either the
         removal failed, or this script DECLINED that one thing while doing the
         rest (a state-data directory that is a reparse point, a directory the
         ownership test would not attribute, a statusline.ps1 whose settings.json
         key half did not complete), or this script could not work out where the
         thing is.
         The second half is why this is not "-Apply ran and something failed":
         `-RemoveData` against a state-data location that will not resolve is a
         request this script cannot answer, and answering it with exit 0 is how
         it once told an operator a deletion had succeeded while every file
         survived. That case exits 2 in the dry run too.
      3  this script could not complete
#>

param(
    # Perform the removals. Without it nothing is written, moved or deleted.
    [switch]$Apply,

    # Opt-in removals. Nothing is removed that is not named here.
    [switch]$RemoveStatusLine,
    [switch]$RemovePermissions,
    [switch]$RemoveData,

    # -RemoveStatusLine + -RemovePermissions. Deliberately does NOT include data.
    [switch]$All,

    # Required, literally, alongside -RemoveData.
    [string]$ConfirmToken,

    # Restore settings.json from a named backup instead of editing it. Preferred
    # when a backup predates the install, and refused without -Apply.
    [string]$RestoreSettings,

    # Test overrides. These are how the removal paths are exercised without
    # touching this machine.
    [string]$SettingsPath,
    [string]$ClaudeHome,

    # The DISCOVERY ROOT the sibling sweep in section 5 lists, and only that.
    # It deliberately does NOT override where the live state dir is: that comes
    # from Get-LwgStateDirInfo, which honours CLAUDE_PLUGIN_DATA first, and a
    # second way to answer that question is what this script got wrong.
    [string]$DataRoot
)

$ErrorActionPreference = 'Stop'

$script:Plan   = New-Object System.Collections.ArrayList
$script:Left   = New-Object System.Collections.ArrayList
$script:Failed = 0
$script:Done   = 0

function Add-PlanRow {
    <#
      One row of the plan. `action` is what -Apply would do; 'report only' means
      this script will not touch it whatever flags are passed.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$State,
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter(Mandatory = $true)][string]$Detail
    )
    [void]$script:Plan.Add([pscustomobject]@{ Id = $Id; State = $State; Action = $Action; Detail = $Detail })
}

function Add-Left {
    param([string]$What, [string]$Why)
    [void]$script:Left.Add([pscustomobject]@{ What = $What; Why = $Why })
}

$script:DataSeen    = @{}
$script:DataTargets = New-Object System.Collections.ArrayList

function Add-DataTarget {
    <#
      One candidate state-data directory, with the reason it is a candidate.

      Deduped case-insensitively on the full path, keeping the FIRST reason -
      which is the strongest, because section 5 adds the resolver's answer
      before it sweeps for siblings. `Why` is printed in the footprint, so the
      report says not only what it would delete but how it came to believe that
      directory is this plugin's.

      Existence is recorded at add time for the report and re-checked at delete
      time, because the plan and the deletion are seconds apart and a footprint
      that promises to remove something already gone is not a true one.

      `Source` is the resolver's source name for the resolved target and 'sweep'
      for a swept sibling. Test-DataTargetRefusal reads it, because the two
      arrive with completely different amounts of attribution behind them.
    #>
    param([string]$Path, [string]$Why, [string]$Source = 'sweep')

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $full = $Path
    try { $full = [IO.Path]::GetFullPath($Path) } catch { }
    $key = $full.TrimEnd('\', '/').ToLowerInvariant()
    if ($script:DataSeen.ContainsKey($key)) { return }
    $script:DataSeen[$key] = $true

    $exists = $false
    try { $exists = [IO.Directory]::Exists($full) } catch { }
    [void]$script:DataTargets.Add([pscustomobject]@{ Path = $full; Why = $Why; Exists = $exists; Source = $Source; Refusal = '' })
}

function Test-DataTargetRefusal {
    <#
      Should this directory be excluded from -RemoveData? Returns the reason, or
      ''. THIS IS THE ONLY OWNERSHIP TEST ON THE ONE PATH IN THIS SCRIPT THAT
      DELETES RECURSIVELY, and until 3 August 2026 there was none at all.

      $env:CLAUDE_PLUGIN_DATA reached `Remove-Item -Recurse -Force` verbatim:
      lib\common.ps1 returns it unvalidated and unnormalised ahead of every
      name-based branch, and nothing between that return and the delete compared
      the leaf to the plugin name, looked for a file this plugin writes, or
      refused an ancestor of anything. The sibling sweep ten lines away IS
      name-constrained - the asymmetry was between the ENUMERATION path and the
      RESOLUTION path, not a decision anybody took.

      TWO RULES, and they are deliberately different in scope.

      1. PROTECTED PATHS - applied to EVERY source. A candidate that IS, or
         CONTAINS, the plugin clone / the settings directory / $ClaudeHome / the
         user profile is refused. This costs nothing on the name-constrained
         paths and it closes the catastrophic instance however the path arrived:
         this script's own remediation text tells an operator to take the state
         dir the doctor prints and set CLAUDE_PLUGIN_DATA to it, and the parent
         of that - which is what -DataRoot takes, so the two are easy to
         transpose - is every installed plugin's state; one level above that is
         settings.json, projects, todos and history.

         Note the direction: the question is "is the PROTECTED path under the
         CANDIDATE", not the reverse. Test-LwgPathUnder returns true on equality,
         so equal-to counts as contains, which is the case that matters.

      2. AN OWNERSHIP SIGNAL - applied to the 'env' source ONLY, because that is
         the only source not constrained by construction ('discovered' and
         'bare' are both built as <root>\<name>...). A non-empty directory that
         holds none of the files this plugin writes AND whose leaf is not
         <name> or <name>-* is refused.

         EMPTY IS STILL A TARGET, and that is a decision rather than an
         oversight. The declared contract of CLAUDE_PLUGIN_DATA is "this IS my
         state dir" and it is honoured that way by the status line, the healer
         and every module; an operator who names an empty directory has told
         this plugin the directory is its own, and removing it loses nothing.
         Content is the predicate rather than the leaf name because a bare
         name rule would break the legitimate redirect - pointing the data dir
         at D:\lwg-state is exactly what the variable is for.

      WHAT THIS DOES NOT CLOSE: a directory holding this plugin's files AND
      another plugin's is deleted whole. There is no per-file removal here and
      adding one would be a different script.
    #>
    param([string]$Path, [string]$Source, [string]$Name, [string[]]$Protected, [string[]]$OwnFiles)

    foreach ($prot in $Protected) {
        if ([string]::IsNullOrWhiteSpace($prot)) { continue }
        if (Test-LwgPathUnder -Path $prot -Root $Path) {
            return "REFUSED - this directory is, or contains, $prot. Deleting it recursively would take that with it, and no state-data location is worth that"
        }
    }

    if ($Source -ne 'env') { return '' }

    $leaf = ''
    try { $leaf = Split-Path -Leaf $Path } catch { }
    if ($leaf -eq $Name -or $leaf -like "$Name-*") { return '' }

    $files = @()
    try { $files = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop) } catch { return '' }
    if ($files.Count -eq 0) { return '' }
    foreach ($f in $files) {
        foreach ($pat in $OwnFiles) { if ($f.Name -like $pat) { return '' } }
    }
    return ("REFUSED - CLAUDE_PLUGIN_DATA names this directory, but its leaf is neither '$Name' nor '$Name-*' and it holds none of the files this plugin writes (" + ($OwnFiles -join ', ') + "). It holds $($files.Count) other item(s), so it is somebody's data and this script will not delete it on the strength of one environment variable")
}

function Get-PluginHookLeaves {
    <#
      The .ps1 LEAF NAMES this plugin registers, lower-cased, as a hashtable used
      as a set. Read out of hooks/hooks.json rather than spelled out here, so a
      hook added to that file is recognised by this script the day it lands.

      WHY A LEAF AND NOT A PATH. A hand-added registration is written on the
      machine that wrote it, against the root that machine had. The root is
      exactly the thing that varies between that machine and the one running the
      uninstaller - a second clone, a moved clone, a colleague's path in a shared
      settings.json - and it is the reason the root-shaped needle this scan used
      to carry was load-bearing for nobody. bin/lwg-setup.ps1's Get-HookIdentity
      keys a registration on the same thing for the same reason.

      WHAT IT COSTS, stated rather than glossed: a script of somebody else's that
      happens to be called supervisor.ps1 is attributed to this plugin. Nothing
      on disk distinguishes them. That is why the match REASON travels with every
      hit and is printed - the operator is told which signal fired, and a
      leaf-only hit says so in as many words instead of being presented as
      certainty.
    #>
    param([string]$PluginRoot)

    $leaves = @{}
    try {
        $hj = Join-Path $PluginRoot 'hooks\hooks.json'
        if (Test-Path -LiteralPath $hj) {
            $raw = Get-Content -LiteralPath $hj -Raw
            foreach ($m in [regex]::Matches($raw, '(?i)[^\\/"'':\s]+\.ps1')) {
                $leaves[$m.Value.ToLowerInvariant()] = $true
            }
        }
    } catch { }
    return $leaves
}

function Get-HookRefReason {
    <#
      WHY this hook command belongs to this plugin, or '' when nothing says it
      does. Strongest signal first, and the string it returns is printed to the
      operator - so it has to name the evidence, not assert the conclusion.
    #>
    param([string]$Text, [string]$RootNorm, [string]$NameNorm, [hashtable]$Leaves)

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }

    # ONE SPELLING FOR COMPARISON. A registration may be written with either
    # slash and in any case; bin/lwg-setup.ps1 writes forward slashes and the
    # operator's own editor writes whatever they typed. .Contains is ordinal and
    # is deliberately not -like: a path holding [ or ] is a wildcard to -like and
    # a plain character to this.
    $norm = $Text.Replace('\', '/').ToLowerInvariant()

    if ($RootNorm -ne '' -and $norm.Contains($RootNorm)) {
        return 'its command names this clone directly'
    }
    if ($Text.Contains('CLAUDE_PLUGIN_ROOT')) {
        return 'its command still carries an unsubstituted CLAUDE_PLUGIN_ROOT, which only this plugin''s own hooks.json spells'
    }
    if ($NameNorm -ne '' -and $norm.Contains($NameNorm)) {
        return "its command names '$NameNorm'"
    }
    if ($null -ne $Leaves -and $Leaves.Count -gt 0) {
        # The same three legal spellings bin/lwg-setup.ps1's Get-HookScriptPaths
        # reads: a double-quoted path (which a path containing a space forces), a
        # single-quoted one, and a bare run of non-space characters (which is
        # what a trailing argument like -HookEvent Stop leaves behind).
        #
        # (?i) IS LOAD-BEARING AND WAS MISSING UNTIL 3 AUGUST 2026. Windows file
        # names are case-insensitive, so `Supervisor.PS1` and `supervisor.ps1`
        # name the same file and either spelling can be what an operator - or
        # another tool - actually wrote into settings.json. Measured in
        # isolation without it:
        #
        #     powershell -File "C:\some\other\lib\Supervisor.PS1"   0 matches
        #     powershell -File "C:\some\other\lib\supervisor.ps1"   1 match
        #
        # so a live registration in the first spelling was reported as 0
        # reference(s) - this scan's founding defect surviving in narrow form.
        # Get-PluginHookLeaves already compiled its own extraction with (?i) and
        # the leaf set is a PowerShell hashtable, whose comparer is
        # case-insensitive, so this line was the only case-sensitive step in the
        # chain.
        foreach ($mm in [regex]::Matches($Text, '(?i)"([^"]+\.ps1)"|''([^'']+\.ps1)''|([^\s"'']+\.ps1)')) {
            $v = if     ($mm.Groups[1].Success) { $mm.Groups[1].Value }
                 elseif ($mm.Groups[2].Success) { $mm.Groups[2].Value }
                 else                           { $mm.Groups[3].Value }
            $leaf = @($v.Replace('\', '/').Split('/'))[-1].ToLowerInvariant()
            if ($Leaves.ContainsKey($leaf)) {
                return "it runs $leaf, one of the scripts this plugin ships, from a path that is not this clone"
            }
        }
    }
    return ''
}

function Get-SettingsHookRefs {
    <#
      Every hook COMMAND ENTRY under settings.json's `hooks` that names this
      plugin, as objects @{ Command; Why }.

      WHAT A REFERENCE IS, DEFINED ONCE AND HERE: one object under `hooks`
      carrying a `command` member. That is one registration and it fires once
      per matching event. Two identical registrations are two references,
      because both of them fire.

      THE OBJECT IS WALKED, NOT SERIALISED, and that is the fix rather than an
      implementation preference. This scan used to run ConvertTo-Json over the
      block and match needles against the text, which put three escaping regimes
      - a .NET replacement string, a JSON escape, and a -like wildcard - into one
      expression. The plugin-root needle came out with FOUR backslashes per
      separator where ConvertTo-Json emits TWO and could not match anything, ever.
      Working on the DESERIALISED strings, a path is just a path.

      BOTH SHAPES OF PATH ARE READ, and the sentence is narrower than it was on
      purpose. hooks.json spells the script into an `args` ARRAY; a hand-added
      settings.json entry almost always puts it in the `command` STRING. Both
      are matched - but `args` is only ever appended to a `command` that is
      already present, so an entry carrying args and NO command matches nothing.
      That is not a gap: `"type": "command"` requires `command`, so an args-only
      entry is not a registration the CLI would run either. What would be a
      defect is missing the args of a real entry, and that is what is covered -
      a reader that knew only the command string would tell an operator that a
      registration copied out of hooks.json does not exist.
    #>
    param($Hooks, [string]$Name, [string]$PluginRoot, [hashtable]$Leaves)

    $hits = New-Object System.Collections.ArrayList
    if ($null -eq $Hooks) { return $hits }

    $rootNorm = ''
    if (-not [string]::IsNullOrWhiteSpace($PluginRoot)) {
        $rootNorm = $PluginRoot.Replace('\', '/').TrimEnd('/').ToLowerInvariant()
    }
    $nameNorm = ''
    if (-not [string]::IsNullOrWhiteSpace($Name)) { $nameNorm = $Name.ToLowerInvariant() }

    # A QUEUE, NOT A STACK, AND THAT IS THE OPERATOR'S DOING. What this returns
    # is printed under LEFT BEHIND as a list for somebody to work through against
    # their own settings.json. A depth-first stack hands it to them in reverse
    # document order; breadth-first walks the events in the order they are
    # written in the file. Nothing else here depends on the order.
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue($Hooks)
    while ($queue.Count -gt 0) {
        $n = $queue.Dequeue()
        if ($null -eq $n) { continue }
        # A string is IEnumerable under .NET, so it has to be turned away before
        # the collection test or every command would be walked character by
        # character.
        if ($n -is [string] -or $n -is [ValueType]) { continue }
        if ($n -is [System.Collections.IEnumerable]) {
            foreach ($i in $n) { $queue.Enqueue($i) }
            continue
        }

        $props = @()
        try { $props = @($n.PSObject.Properties) } catch { continue }

        $cmd = $null
        foreach ($p in $props) { if ($p.Name -eq 'command') { $cmd = $p.Value } }
        if ($null -ne $cmd) {
            $text = [string]$cmd
            foreach ($p in $props) {
                if ($p.Name -eq 'args' -and $null -ne $p.Value) {
                    $text += ' ' + ((@($p.Value) | ForEach-Object { [string]$_ }) -join ' ')
                }
            }
            $why = Get-HookRefReason -Text $text -RootNorm $rootNorm -NameNorm $nameNorm -Leaves $Leaves
            if ($why -ne '') { [void]$hits.Add([pscustomobject]@{ Command = $text.Trim(); Why = $why }) }
            # A registration is a leaf. Descending into it would count its own
            # fields as further registrations.
            continue
        }
        foreach ($p in $props) { $queue.Enqueue($p.Value) }
    }
    return $hits
}

function Test-MirroredDeny {
    <#
      Is this permissions.deny entry one of the rules bin/lwg-setup.ps1 writes?
      Returns the family name, or ''.

      Matched by FAMILY rather than against a copied list of literals, which is
      what makes this function still work now that there is no list at all.

      THE INSTALLER NOW WRITES NOTHING. Get-DenyGroups in bin/lwg-setup.ps1 is
      empty: the four destructive groups went on 30 July 2026 with the command
      gate, and the two secret groups - 48 rules - went the same day with
      secret_scan, the last gate. So on a machine installed today none of the
      families below can be present.

      EVERY FAMILY IS KEPT ANYWAY, and this is now the whole point of the
      function rather than a footnote to it. A machine set up before those dates
      still HAS the rules in its own settings.json, the CLI still evaluates them,
      and nothing else can attribute them. An uninstaller that could not see them
      would report a clean removal while leaving up to 181 rules behind. This is
      the only code left in the repo that knows what those rules looked like.

      AND THAT SENTENCE IS NOW CHECKABLE, which it was not until 3 August 2026.
      tests\fixtures\deny_canonical.txt is the 181 rules as bin\lwg-setup.ps1
      emitted them at ef993bc, restored to the tree from that commit, and
      tests\uninstall_footprint.ps1 drives all 181 through this function via a
      real settings.json and requires 181 of 181. It had been 177 of 181 since
      the day the rules and this matcher were written three commits apart: the
      four +refspec rules below had no family, so `-RemovePermissions` left them
      in place AND the LEFT BEHIND block told the operator, in writing, that
      this plugin had not put them there.
    #>
    param([string]$Entry)

    $m = [regex]::Match($Entry, '^(?<tool>[A-Za-z]+)\((?<body>.*)\)$')
    if (-not $m.Success) { return '' }
    $tool = $m.Groups['tool'].Value
    $body = $m.Groups['body'].Value

    if ($tool -eq 'Bash' -or $tool -eq 'PowerShell') {
        if ($body -match '^git push\b.*(--f|-f\b)')                       { return 'git push --force' }
        # A SECOND git-push family, because the first one is a FLAG rule and a
        # force push does not need a flag. A refspec beginning with `+` -
        # `git push origin +main` - rewrites remote history carrying neither
        # --force nor -f, which is why bin\lwg-setup.ps1 enumerated those four
        # rules separately and said so in its `why` string. The flag rule above
        # cannot see them.
        #
        # The narrower regex is wrong and would leave this half open: measured
        # under Windows PowerShell 5.1, '^git push\b.*\s\+' (whitespace before
        # the +) matches `git push * +*` but NOT `git push*+*`, recovering 2 of
        # the 4. No other rule among the 181 in tests\fixtures\deny_canonical.txt
        # contains a literal '+', so the wide form adds no false attribution -
        # that is measured by the fixture, not assumed.
        if ($body -match '^git push\b.*\+')                               { return 'git push --force' }
        if ($body -match '^git reset\b.*--h')                             { return 'git reset --hard' }
        if ($body -match '^git clean\b.*(--f|-f)')                        { return 'git clean --force' }
        if ($body -match '^git rebase\b.*--ro')                           { return 'git rebase --root' }
        if ($body -match '^git (filter-branch|filter-repo)|^git-filter-repo|^git reflog expire') { return 'history rewrite' }
        if ($body -match '^git remote (set-url|add)')                     { return 'remote redirect' }
        if ($body -match '^gh repo (delete|archive|edit)')                { return 'gh destructive' }
        if ($body -match '^gh api\b.*(-X DELETE|--method DELETE)')        { return 'gh destructive' }
        if ($body -match '^(rm|Remove-Item)\b')                           { return 'recursive delete' }
        if ($body -match '^(eval|\\rm|\\git|\\gh)\b')                     { return 'shell bypass' }
        if ($body -match '\.env')                                         { return 'credential read' }
        return ''
    }
    if ($tool -eq 'Edit' -or $tool -eq 'Read' -or $tool -eq 'Write') {
        if ($body -match '(?i)(\.git/|GIT~|ENV~|\.env|\.pem|\.key|id_rsa|id_dsa|id_ecdsa|id_ed25519|\.npmrc|hosts\.yml|\.credentials\.json)') { return 'credential path' }
        return ''
    }
    return ''
}

try {
    $pluginRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $pluginRoot 'lib\common.ps1')
    . (Join-Path $PSScriptRoot 'lwg-cmdlib.ps1')

    if ($All) { $RemoveStatusLine = $true; $RemovePermissions = $true }
    # THE DEFAULT IS NOW RESOLVED, NOT COMPOSED. -ClaudeHome still beats it -
    # that is the first rule of the precedence argued in lib\common.ps1, and it
    # is the seam every case in tests\uninstall_footprint.ps1 drives - but when
    # it is not given the root comes from Get-LwgClaudeHomeInfo, which reads
    # CLAUDE_CONFIG_DIR. Until 3 September 2026 this line was
    # `Join-Path $env:USERPROFILE '.claude'`, so on a machine that relocated the
    # configuration directory this script reported a footprint from a tree the
    # CLI does not use and, with -Apply, removed nothing while saying it had.
    # This file's header promises that what it cannot know is printed on every
    # run, because a footprint report that omits its own blind spots reads as a
    # complete one. A footprint report of the WRONG TREE reads as a clean
    # machine, which is worse.
    $script:LwgHomeInfo  = $null
    try { $script:LwgHomeInfo = Get-LwgClaudeHomeInfo } catch { }
    if ($null -eq $script:LwgHomeInfo) { $script:LwgHomeInfo = @{ path = $null; source = 'unresolved'; exists = $false; raw = $null } }
    $script:LwgHomeGiven = (-not [string]::IsNullOrWhiteSpace($ClaudeHome))
    if (-not $script:LwgHomeGiven) {
        if ([string]::IsNullOrWhiteSpace($script:LwgHomeInfo.path)) {
            throw 'no configuration directory could be resolved: -ClaudeHome was not given and neither CLAUDE_CONFIG_DIR nor USERPROFILE holds a value. Nothing was read and nothing was removed.'
        }
        $ClaudeHome = $script:LwgHomeInfo.path
    }
    if ([string]::IsNullOrWhiteSpace($SettingsPath)) { $SettingsPath = Join-Path $ClaudeHome 'settings.json' }

    $name = Get-LwgPluginName
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'lw-watchtower' }

    # EVERY NAME THIS PLUGIN HAS EVER SHIPPED ITS STATE UNDER, AND THIS LIST
    # LIVES HERE RATHER THAN IN lib\common.ps1 ON PURPOSE.
    #
    # The product was renamed from lw-gmhh to lw-watchtower on 3 August 2026.
    # The state directory is not an independent choice: Claude Code names it
    # <plugin-name>-<source-id> from .claude-plugin\plugin.json, and every reader
    # in this tree derives it through Get-LwgPluginName. So renaming the plugin
    # id MOVED the state directory, and a machine that ran the old build still
    # has ~\.claude\plugins\data\lw-gmhh* sitting there with its event log in it.
    #
    # NOTHING MIGRATES IT. lib\common.ps1 states "Nothing is migrated, moved or
    # deleted" about the state dir and that stays true; a rename is not a reason
    # to start writing into a directory on the strength of its name.
    #
    # An uninstaller that only swept the CURRENT name would then report a clean
    # removal over a directory it never looked at - the same shape as the defect
    # recorded in the section-5 comment below, where this script reported
    # `state-data absent` while five live files sat in a redirected data dir.
    #
    # THAT IS TRUE OF ONE BRANCH AND NOT THE OTHER, and the distinction is worth
    # keeping because overstating it here would be the same fault as the bug.
    # With any <name>* directory present - the ordinary state after an upgrade -
    # resolution succeeds, the state-data row lists that directory alone, and
    # -RemoveData -ConfirmToken deletes exactly what it listed and reports
    # success while the legacy directory sits unmentioned beside it. THAT is the
    # false success. With NO <name>* directory present, nothing resolves and
    # nothing is swept, so the row already fell through to UNRESOLVED / CANNOT
    # REPORT and said in as many words that its silence is not evidence of
    # absence - wrong about where, never claiming a removal. The sweep improves
    # both cases; only the first was ever dishonest.
    #
    # WHAT IT COSTS: -RemoveData now reaches the legacy directory too. The
    # keeping rules are untouched - state is still kept unless the flag AND the
    # token are passed - but the SET the flag acts on is larger than it was, and
    # a destructive flag quietly growing what it reaches is the same defect as an
    # overstated claim. It is in the header, in CHANGELOG.md and in every row the
    # sweep produces, which say LEGACY in their Why so an operator can tell a
    # live directory from a stranded one before typing the token.
    #
    # THE LIST IS A READER'S, AND THE PLACEMENT IS WHAT KEEPS IT ONE: it is
    # declared in this file and referenced only in this file, and no write path
    # dot-sources this script - so nothing that appends a record can resolve
    # through it. (It is not sealed: this script dot-sources lib\common.ps1, so
    # the two share a script scope and a function there COULD see the variable.
    # None does, and that is the claim - not that the language prevents it.)
    # Putting the list in lib\common.ps1 beside Get-LwgStateDirInfo would put it
    # one typo away from being a second spelling the WRITE path resolves to,
    # which is exactly the class of bug the state-dir rule was rewritten to
    # close.
    $script:LwgLegacyDataNames = @('lw-gmhh')

    # Resolved HERE, before anything is printed, so the header can state the
    # state-data location beside the settings path. Section 5 uses this same
    # object; the helper memoises, so this costs one resolution, not two.
    $stateInfo = @{ path = $null; source = 'unresolved'; resolved = $false; candidates = 0 }
    try { $stateInfo = Get-LwgStateDirInfo } catch { }

    Write-Output "LW-WATCHTOWER uninstall v$($script:LwgVersion) - $(if ($Apply) { 'APPLY' } else { 'DRY RUN (default)' })"
    Write-Output "  plugin root:  $pluginRoot"
    Write-Output "  settings:     $SettingsPath"
    Write-Output ("  state data:   {0} (source '{1}', resolved {2})" -f `
        $(if ([string]::IsNullOrWhiteSpace([string]$stateInfo.path)) { '<none worked out>' } else { $stateInfo.path }), `
        $stateInfo.source, $stateInfo.resolved)
    if (-not $Apply) { Write-Output '  Nothing below is written, moved or deleted in this mode.' }

    # ---------------------------------------------------------------------
    # 1. the junction - the whole install, and the one thing not removed here
    # ---------------------------------------------------------------------
    $link = Join-Path $ClaudeHome "skills\$name"
    $linkItem = $null
    try { $linkItem = Get-Item -LiteralPath $link -Force -ErrorAction Stop } catch { }
    if ($null -eq $linkItem) {
        Add-PlanRow -Id 'junction' -State 'absent' -Action 'nothing to do' -Detail "$link does not exist - this plugin is not loaded from a skills-dir junction on this machine"
    } else {
        $tgt = ''
        try { $tgt = @($linkItem.Target) -join ', ' } catch { }
        Add-PlanRow -Id 'junction' -State 'PRESENT' -Action 'REPORT ONLY - will not remove' `
                  -Detail "$link -> $tgt. This IS the install: removing it deregisters every hook, command and output style in one step."
        # THE HAZARD BELOW IS STATED AS A PROPERTY OF SOME WINDOWS POWERSHELL
        # BUILDS, NOT OF THIS ONE, and that is a correction made on 3 August
        # 2026 rather than a softening. Measured on 5.1.26100.8875:
        # `Remove-Item -Recurse -Force` on a junction removed the LINK and left
        # the target's contents intact, in both shapes (the junction itself, and
        # a junction nested under the directory being removed). So the sentence
        # is kept - a refusal that only holds on builds where the hazard was
        # measured is a refusal that got lucky - but it is not evidence this
        # build does it, and the state-data block further down refuses reparse
        # points for a DIFFERENT and locally measured reason: on this build the
        # delete removes the link, reports `deleted`, and every file on the
        # other side survives.
        Add-Left -What "the junction $link" `
                 -Why  ("this script will not delete it. Remove-Item -Recurse on a junction has deleted the TARGET's contents on some Windows PowerShell builds - not measured on this one, where it removes the link and leaves the target - and the target here is the git clone. Either way the safe verb is:  cmd /c rmdir `"$link`"  - which removes the link only.")
    }

    # ---------------------------------------------------------------------
    # 2. hooks
    # ---------------------------------------------------------------------
    # The plugin's own hooks live in hooks/hooks.json INSIDE the plugin and are
    # registered by discovery, not by settings.json. Removing the junction is
    # what unregisters them. settings.json is still checked, because a hand-added
    # entry pointing at these scripts would survive the junction's removal and
    # then fail on every event.
    $settings = $null
    $settingsErr = ''
    # TWO DIFFERENT ANSWERS THAT $settingsErr ALONE CANNOT TELL APART, and the
    # rows below need both. "There is no settings.json" is a FINDING: there is
    # then definitely no statusLine key and definitely no permissions.deny
    # entry, and `absent` is the true word. "There is one and I could not read
    # or parse it" is the absence of a finding, and `absent` there is a claim
    # about a file that was never inspected. $settingsMissing separates them,
    # and $settingsUnread below is the one the UNKNOWN rows and the write
    # refusal key on - not $settingsErr, which is set in both cases.
    $settingsMissing = $false
    if (Test-Path -LiteralPath $SettingsPath) {
        $settings = Read-LwgTextFile -Path $SettingsPath
        if (-not $settings.ok) { $settingsErr = $settings.error }
    } else {
        $settingsMissing = $true
        $settingsErr = 'no settings file at that path'
    }

    # PARSED ONCE, HERE, AND A PARSE FAILURE IS RECORDED RATHER THAN SWALLOWED.
    # Until 3 August 2026 this file parsed $settings.text three separate times -
    # for hooks, for statusLine, for permissions.deny - each inside its own empty
    # `catch { }`. A settings.json that READS but does not PARSE (a trailing
    # comma, a // line comment and a /* */ block comment each throw here; all
    # three measured under this machine's Windows PowerShell 5.1) therefore left
    # $settingsErr empty, which suppressed the NOTE: disclosure further down, and
    # left every one of those rows asserting `absent` about a file it had not
    # read. A hand-annotated settings.json reaches that with no race window at
    # all. One parse, one recorded error, and the rows below say UNKNOWN.
    $settingsObj = $null
    if ($null -ne $settings -and $settings.ok) {
        try { $settingsObj = $settings.text | ConvertFrom-Json -ErrorAction Stop }
        catch { $settingsErr = "the file was read but does not parse as JSON: $($_.Exception.Message)" }
    }
    # THE FILE IS THERE AND THIS RUN DOES NOT KNOW WHAT IS IN IT. Everything
    # that must not assert `absent`, and the refusal to write, key on this
    # rather than on $settingsErr.
    $settingsUnread = ($settingsErr -ne '') -and (-not $settingsMissing)

    # THREE DEFECTS LIVED IN THE FIVE LINES THIS REPLACED, and all three are
    # named here because the row below prints a NUMBER and a zero from a broken
    # scan reads exactly like a zero from a clean file.
    #
    #   1. The plugin-root needle was ($pluginRoot -replace '\\', '\\\\'). In a
    #      .NET replacement string a backslash is literal - there is no escape
    #      processing - so that produced FOUR backslashes per separator where
    #      ConvertTo-Json emits TWO. Measured under Windows PowerShell 5.1:
    #      needle `C:\\\\repos\\\\governance` (25 chars) against JSON
    #      `C:\\repos\\governance` (21 chars), -like False. It could not match
    #      any settings.json that has ever been written.
    #   2. `$hookRefs++` ran at most once per needle over a three-element array,
    #      so it counted needle KINDS with a ceiling of 3 however many entries
    #      existed - and the row printed it as a count of references.
    #   3. Nothing carried a hit into LEFT BEHIND, so the one thing this scan
    #      exists to warn about was the one thing the operator was never told.
    #
    # The escaping regime is GONE rather than corrected. Get-SettingsHookRefs
    # walks the deserialised object, where a path is a path; the definition of a
    # `reference` lives in its docstring and nowhere else.
    $hookHits = @()
    if ($null -ne $settingsObj) {
        try {
            $hookHits = @(Get-SettingsHookRefs -Hooks $settingsObj.hooks -Name $name `
                                               -PluginRoot $pluginRoot `
                                               -Leaves (Get-PluginHookLeaves -PluginRoot $pluginRoot))
        } catch { }
    }
    $hookRefs = $hookHits.Count
    $hookCount = 0
    try {
        $hj = Join-Path $pluginRoot 'hooks\hooks.json'
        if (Test-Path -LiteralPath $hj) {
            $h = (Get-Content -LiteralPath $hj -Raw | ConvertFrom-Json)
            $hookCount = @($h.hooks.PSObject.Properties.Name).Count
        }
    } catch { }
    # `0 reference(s)` ABOUT A FILE THIS RUN NEVER INSPECTED is an assertion, not
    # a finding - the same untruth as the phantom permissions.deny entry this
    # script used to report, wearing the opposite sign. $settingsUnread is the
    # flag that separates "there is no settings.json", which really does hold no
    # hook entries, from "there is one and I could not read it".
    if ($settingsUnread) {
        $hookDetail = "declared in hooks/hooks.json inside the plugin, not in settings.json. settings.json could not be read or parsed ($settingsErr), so it was NOT inspected for hook entries naming this plugin."
    } else {
        $hookDetail = "declared in hooks/hooks.json inside the plugin, not in settings.json. settings.json holds $hookRefs reference(s) to this plugin under `hooks`."
        if ($hookRefs -gt 0) { $hookDetail += ' Every one of them is listed under LEFT BEHIND.' }
    }
    Add-PlanRow -Id 'hooks' -State "$hookCount event(s)" -Action 'removed WITH the junction' -Detail $hookDetail

    # THE ORDER IS THE WARNING. Section 1 above prints the exact
    # `cmd /c rmdir "<link>"` that removes the junction, and an operator reads
    # this report top to bottom before running it. Once the junction is gone, a
    # settings.json entry pointing into the clone fires on every event of every
    # session and finds nothing - so this has to be in front of them BEFORE that
    # command, not discoverable afterwards in docs/install.md.
    if ($hookRefs -gt 0) {
        $shown  = @($hookHits | Select-Object -First 12)
        $listed = @($shown | ForEach-Object { "`n        - $($_.Command)`n          ($($_.Why))" }) -join ''
        $more   = if ($hookRefs -gt $shown.Count) { "`n        ... and $($hookRefs - $shown.Count) more of the same shape." } else { '' }
        Add-Left -What "$hookRefs settings.json hook registration(s) naming this plugin" `
                 -Why ("this script never edits the hooks block of settings.json, so they are all still there in $SettingsPath. REMOVE THEM BEFORE you remove the junction - after it is gone they fire on every event of every session pointing at a script that is no longer loaded, and a hook that fails on every event is worse than the plugin was." +
                       $listed + $more +
                       "`n        A registration recognised only by its SCRIPT LEAF NAME - the reason says so - may belong to a different checkout of this plugin, or to a script of your own that shares the name. Read it before you delete it.")
    } elseif ($settingsUnread) {
        Add-Left -What 'the settings.json hook registration(s), however many there are' `
                 -Why "settings.json could not be read or parsed ($settingsErr), so it was never inspected for hook entries naming this plugin. Any that are there survive the junction's removal and then fail on every event."
    }

    # ---------------------------------------------------------------------
    # 3. status line - a settings.json key AND a copied file
    # ---------------------------------------------------------------------
    # Two halves that must go together. The key without the file renders an error
    # on every message and blanks the whole row; the file without the key is dead
    # weight. So they are one decision, taken with -RemoveStatusLine.
    $slFile = Join-Path $ClaudeHome 'statusline.ps1'
    $slKey = $null
    $slTarget = ''
    if ($null -ne $settingsObj) {
        $st = $settingsObj.statusLine
        if ($null -ne $st -and -not [string]::IsNullOrWhiteSpace([string]$st.command)) {
            $slKey = [string]$st.command
            foreach ($tok in ([regex]::Matches($slKey, '"([^"]+)"|(\S+)'))) {
                $t = if ($tok.Groups[1].Success) { $tok.Groups[1].Value } else { $tok.Groups[2].Value }
                if ($t -match '\.ps1$') { $slTarget = $t; break }
            }
        }
    }

    # ATTRIBUTED ON THE LEAF THE INSTALLER WRITES, NOT ON THE DIRECTORY IT SITS
    # IN. This test was "anywhere under $ClaudeHome or anywhere under the clone"
    # until 3 August 2026, and the first half of that is the operator's entire
    # Claude Code configuration directory - third-party status lines are
    # routinely kept there. An operator with their own ~/.claude/ccusage.ps1 was
    # told in the plan that it "renders the HH/GM segments", and `-All -Apply`   <!-- doc-claims:ignore -->
    # removed the key. The key was recoverable from the backup; the sentence
    # that talked them into it was not true when they read it. That quotation is
    # VERBATIM and is deliberately left as it was: the row now says "the HH
    # segment" because GM was deleted on 30 July 2026, and correcting a record of
    # what an operator was actually shown would be falsifying the record. The
    # marker is the same one tests/doc_claims.ps1 uses on a frozen sentence.
    #
    # bin\lwg-setup.ps1 writes exactly two spellings - the copy at
    # $ClaudeHome\statusline.ps1 (:983, and `copy` is the DEFAULT mode) and the
    # junction route's $ClaudeHome\skills\<name>\statusline\statusline.ps1
    # (:1005) - so those two, plus anything inside the clone, are the whole of
    # what this plugin can have installed. Everything else takes the REPORT ONLY
    # path that was already written for it.
    #
    # NOT closed by this: a target that IS one of those two paths but was put
    # there by somebody else is still attributed to this plugin. Nothing on disk
    # distinguishes them, and this script does not keep an install manifest.
    $slIsOurs = $false
    $slWhy    = ''
    if (-not [string]::IsNullOrWhiteSpace($slTarget)) {
        try {
            $slFull   = [IO.Path]::GetFullPath($slTarget)
            $slCopy   = [IO.Path]::GetFullPath($slFile)
            $slSkills = [IO.Path]::GetFullPath((Join-Path $ClaudeHome "skills\$name"))
            $slRoot   = [IO.Path]::GetFullPath($pluginRoot)
            if     ($slFull.Equals($slCopy, [StringComparison]::OrdinalIgnoreCase)) { $slIsOurs = $true; $slWhy = "it IS the copy this installer writes at $slCopy" }
            elseif (Test-LwgPathUnder -Path $slFull -Root $slSkills)                { $slIsOurs = $true; $slWhy = "it is inside the skills junction this installer creates at $slSkills" }
            elseif (Test-LwgPathUnder -Path $slFull -Root $slRoot)                  { $slIsOurs = $true; $slWhy = "it is inside this plugin's own clone at $slRoot" }
        } catch { }
    }
    if ($settingsUnread) {
        # NOT 'absent'. The key was not read, so nothing is known about it - the
        # same distinction the state-data block turns on, applied here.
        Add-PlanRow -Id 'statusline-key' -State 'UNKNOWN' -Action 'CANNOT REPORT - settings.json was not read' `
                  -Detail "$SettingsPath could not be read or parsed ($settingsErr), so whether it declares a statusLine.command is unknown. This is not a report that there is none."
        Add-Left -What 'the statusLine key in settings.json, if there is one' -Why "settings.json could not be read or parsed ($settingsErr), so it was neither inspected nor edited"
    } elseif ($null -eq $slKey) {
        Add-PlanRow -Id 'statusline-key' -State 'absent' -Action 'nothing to do' -Detail "$SettingsPath has no statusLine.command"
    } elseif (-not $slIsOurs) {
        Add-PlanRow -Id 'statusline-key' -State 'PRESENT' -Action 'REPORT ONLY - not attributable' `
                  -Detail "statusLine.command points at $slTarget, which is none of the paths this installer writes ($slFile, $ClaudeHome\skills\$name\..., or inside $pluginRoot). It is somebody else's status line and is left alone."
        Add-Left -What 'the statusLine key in settings.json' -Why "it points at $slTarget, which this plugin did not install"
    } else {
        Add-PlanRow -Id 'statusline-key' -State 'PRESENT' -Action $(if ($RemoveStatusLine) { 'REMOVE the statusLine key' } else { 'kept - pass -RemoveStatusLine' }) `
                  -Detail "runs $slTarget, attributed because $slWhy. That it renders the HH segment is inferred from the path, not from reading the file."
    }

    $slHash = ''
    $repoSl = Join-Path $pluginRoot 'statusline\statusline.ps1'
    if (Test-Path -LiteralPath $slFile) {
        $a = (Get-FileHash -LiteralPath $slFile -Algorithm SHA256).Hash
        $drift = 'no repo copy to compare against'
        if (Test-Path -LiteralPath $repoSl) {
            $b = (Get-FileHash -LiteralPath $repoSl -Algorithm SHA256).Hash
            $drift = if ($a -eq $b) { 'byte-identical to statusline/statusline.ps1 in the repo' } else { 'DIFFERS from statusline/statusline.ps1 - it has been edited in place, and deleting it loses that edit' }
        }
        $slHash = $a
        Add-PlanRow -Id 'statusline-file' -State 'PRESENT' -Action $(if ($RemoveStatusLine) { 'DELETE the installed copy - ONLY IF the key half succeeds' } else { 'kept - pass -RemoveStatusLine' }) `
                  -Detail "$slFile ($drift). Per the pairing rule above, this copy is deleted only in a run where the statusLine key was removed, or was read and found absent, or was read and found to be somebody else's. If the key edit is skipped or fails, this file is kept and said so."
    } else {
        Add-PlanRow -Id 'statusline-file' -State 'absent' -Action 'nothing to do' -Detail "$slFile does not exist"
    }

    # ---------------------------------------------------------------------
    # 4. permissions.deny - the rules bin/lwg-setup.ps1 writes
    # ---------------------------------------------------------------------
    $denyAll = @()
    $denyOurs = @()
    $denyFam = @{}
    if ($null -ne $settingsObj) {
        $p = $settingsObj.permissions
        # THE NULL FILTER IS NOT DEFENSIVE PADDING. @($x.deny) where the `deny`
        # key does not exist yields a ONE-ELEMENT ARRAY CONTAINING $null under
        # Windows PowerShell 5.1, not an empty array - measured, for a $null
        # parent AND for a permissions object that simply has no deny key. So
        # every settings.json without a deny list, which is most of them and ALL
        # of them installed after 30 July 2026 because the installer writes no
        # rules at all, counted one entry that does not exist: the honest
        # `absent` row below was unreachable, the footprint printed
        # `0 of 1 attributable`, and LEFT BEHIND opened with "1 other
        # permissions.deny entries ... they were not put there by it" about
        # nothing. Nothing was ever written on that path - $denyOurs stayed
        # empty, so the apply guard was false - but the operator went looking in
        # settings.json for an entry that was not there.
        $denyAll = @(@($p.deny) | Where-Object { $null -ne $_ })
        foreach ($d in $denyAll) {
            $fam = Test-MirroredDeny -Entry ([string]$d)
            if ($fam) { $denyOurs += [string]$d; $denyFam[$fam] = [int]$denyFam[$fam] + 1 }
        }
    }
    if ($settingsUnread) {
        Add-PlanRow -Id 'permissions-deny' -State 'UNKNOWN' -Action 'CANNOT REPORT - settings.json was not read' `
                  -Detail "$SettingsPath could not be read or parsed ($settingsErr), so how many permissions.deny entries it declares is unknown. This is not a report that there are none."
        Add-Left -What 'the permissions.deny entries, however many there are' -Why "settings.json could not be read or parsed ($settingsErr), so they were neither counted nor removed"
    } elseif ($denyAll.Count -eq 0) {
        Add-PlanRow -Id 'permissions-deny' -State 'absent' -Action 'nothing to do' -Detail 'settings.json declares no permissions.deny entries'
    } else {
        $fams = @($denyFam.Keys | Sort-Object | ForEach-Object { "$_ x$($denyFam[$_])" }) -join ', '
        Add-PlanRow -Id 'permissions-deny' -State "$($denyOurs.Count) of $($denyAll.Count) attributable" `
                  -Action $(if ($RemovePermissions) { "REMOVE $($denyOurs.Count) entries" } else { 'kept - pass -RemovePermissions' }) `
                  -Detail "families: $fams"
        if (-not $RemovePermissions) {
            Add-Left -What "$($denyOurs.Count) permissions.deny entries" `
                     -Why 'they are the layer that CANNOT fail open - the CLI evaluates them itself, before and regardless of any hook. Any destructive-family rules found here predate 30 July 2026, when both the command gate and the destructive deny groups were removed; this installer would not write them today, and nothing in this plugin refuses a destructive command any more. They are kept unless -RemovePermissions says otherwise, because removing them removes the last thing on this machine that would refuse a force push.'
        }
        $others = $denyAll.Count - $denyOurs.Count
        if ($others -gt 0) {
            Add-Left -What "$others other permissions.deny entries" -Why 'they match none of the families this plugin mirrors, so they were not put there by it and are never touched'
        }
    }

    # ---------------------------------------------------------------------
    # 5. state and logs - never removed by default
    # ---------------------------------------------------------------------
    # WHERE THIS LOOKS IS NOT A LITERAL, AND WAS ONE UNTIL 31 JULY 2026.
    #
    # This block hardcoded ~\.claude\plugins\data and never read
    # CLAUDE_PLUGIN_DATA - the variable lib\common.ps1 calls "authoritative and
    # ends the matter", the one Claude Code hands every hook, and the one the
    # doctor, the status line, the healer and every module resolve through.
    # With the data dir redirected, /lw-watchtower:doctor reported the state dir
    # (source 'env') holding five live files while THIS script reported
    # `state-data absent`, and `-RemoveData -ConfirmToken DELETE-MY-LWG-LOGS`
    # then printed `APPLIED: 0 change(s), 0 failure(s)` and exited 0 with all
    # five files still on disk. An operator typed a destructive confirmation
    # token, was told it had worked, and nothing had been deleted. That is a
    # switch wired to nothing wearing a success message - the founding defect
    # this plugin exists to catch, shipped by this plugin.
    #
    # Resolution therefore goes through Get-LwgStateDirInfo and nowhere else.
    # The logic is not restated here; it is CALLED, so a change to the rule
    # reaches this script the way it reaches everything else. It returns
    # `source` and `resolved` alongside the path, and those two fields are what
    # let the rows below say "I could not work out where to look" rather than
    # the far more dangerous "absent".
    #
    # The discovery root is still swept for SIBLINGS afterwards, and the reason
    # is a property of resolution itself rather than of any one caller:
    # Get-LwgStateDirInfo names the ONE directory that is live, and a footprint
    # has to name the dead ones too or removal leaves them behind. That sweep is
    # enumeration, not resolution - it can only add directories to the report,
    # never decide which is live.
    #
    # This paragraph used to justify the sweep by pointing at a second script
    # that built the same union. That script was deleted in wave 1, and a
    # comment that explains live behaviour by reference to a file which is not
    # in the payload sends the next reader looking for it. The reason stands on
    # its own and is stated on its own.
    #
    # $stateInfo is the resolution done at the top of this run, printed in the
    # header - one resolution, one answer, no second opinion down here.
    $srcWhy = switch ([string]$stateInfo.source) {
        'env'        { 'CLAUDE_PLUGIN_DATA is set, which is authoritative and is what Claude Code hands this plugin''s hooks' }
        'discovered' { "discovered under the data root as '$name*', $($stateInfo.candidates) candidate(s) seen" }
        'bare'       { 'the unsuffixed fallback name. Claude Code always names a data dir <name>-<source-id>, so this one can only have been created by this plugin''s own fallback - the live plugin may well be writing somewhere else' }
        default      { 'NOT RESOLVED - this is only where the resolver would have looked' }
    }
    if ($stateInfo.source -ne 'unresolved') {
        Add-DataTarget -Path ([string]$stateInfo.path) -Why "resolved, source '$($stateInfo.source)': $srcWhy" -Source ([string]$stateInfo.source)
    }

    # -DataRoot beats it; otherwise it hangs off $ClaudeHome, which is either
    # what -ClaudeHome named or what Get-LwgClaudeHomeInfo resolved. It was
    # `Join-Path $env:USERPROFILE '.claude\plugins\data'`, which meant the sweep
    # for sibling and legacy state directories ran in the profile even when the
    # rest of this run had been pointed somewhere else - the two halves of one
    # footprint describing two different machines.
    $dataRoot  = if ([string]::IsNullOrWhiteSpace($DataRoot)) { Join-Path $ClaudeHome 'plugins\data' } else { $DataRoot }
    $sweepNote = ''
    if (-not (Test-Path -LiteralPath $dataRoot -PathType Container)) {
        $sweepNote = "the data root $dataRoot does not exist, so there were no siblings to sweep"
    } else {
        try {
            foreach ($pat in @(@($name) + $script:LwgLegacyDataNames)) {
                foreach ($d in @(Get-ChildItem -LiteralPath $dataRoot -Directory -Filter "$pat*" -ErrorAction Stop)) {
                    $legacy = ($pat -ne $name)
                    Add-DataTarget -Path $d.FullName -Why $(if ($legacy) {
                        "swept from $dataRoot as '$pat*' - a LEGACY name this plugin shipped under before the rename to '$name'. Nothing writes here any more; it is reported so that removal does not leave it behind"
                    } else {
                        "swept from $dataRoot as '$pat*'"
                    })
                }
            }
        } catch {
            $sweepNote = "the data root $dataRoot could NOT be listed ($($_.Exception.Message)), so any sibling directory there is unreported"
        }
    }

    # THE OWNERSHIP TEST, applied here rather than at add time so that a refused
    # directory is still REPORTED. A refusal an operator cannot see is a silent
    # drop, and this file names that shape at the state-data comment above as
    # the founding defect. The protected list is built here because these four
    # are the paths this particular run is working against - the clone it was
    # launched from, the settings file it was pointed at, the profile it was
    # given - not a global constant.
    $protectedPaths = @(
        $pluginRoot,
        (Split-Path -Parent $SettingsPath),
        $ClaudeHome,
        $env:USERPROFILE
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
        $q = $_; try { $q = [IO.Path]::GetFullPath($_) } catch { }; $q
    }
    # Invented-free: these are the real file names this plugin writes into its
    # state directory, and doctor.probe is written by /lw-watchtower:doctor.
    #
    # THE LEGACY EVENT-LOG NAMES ARE IN THIS LIST FOR ONE REASON, and it is the
    # ownership test below rather than the sweep above. That test only fires on
    # source 'env', and 'env' is exactly the route this script's own remediation
    # text sends an operator down: run the doctor, take the state dir it prints,
    # set CLAUDE_PLUGIN_DATA to it. An operator on a pre-rename install who does
    # that lands on ...\data\lw-gmhh, whose leaf is neither '<name>' nor
    # '<name>-*' and which holds only lw-gmhh.jsonl - so without this entry the
    # directory would be REFUSED as somebody else's data, and the operator would
    # be told their own log file was not this plugin's. It only ever widens what
    # can be recognised as ours; nothing here decides to delete anything.
    $ownStateFiles = @("$name.jsonl", 'health.jsonl', 'advisory-*.json', 'doctor.probe') +
                     @($script:LwgLegacyDataNames | ForEach-Object { "$_.jsonl" })

    foreach ($t in $script:DataTargets) {
        if (-not $t.Exists) { continue }
        $t.Refusal = Test-DataTargetRefusal -Path $t.Path -Source $t.Source -Name $name `
                                            -Protected $protectedPaths -OwnFiles $ownStateFiles
    }

    # Only directories that are really there AND were not refused are candidates
    # for deletion. A resolved path that does not exist is reported, never
    # promised; a refused one is reported and named, never quietly dropped.
    $dataDirs    = @($script:DataTargets | Where-Object { $_.Exists -and -not $_.Refusal })
    $dataRefused = @($script:DataTargets | Where-Object { $_.Exists -and $_.Refusal })
    $dataGhosts  = @($script:DataTargets | Where-Object { -not $_.Exists })

    $totalBytes  = 0
    $sizeUnknown = 0
    foreach ($d in $dataDirs) {
        try { $totalBytes += (@(Get-ChildItem -LiteralPath $d.Path -File -Recurse -ErrorAction Stop) | Measure-Object Length -Sum).Sum }
        catch { $sizeUnknown++ }
    }

    # THE DISTINCTION THE WHOLE BLOCK TURNS ON. "I looked and there is nothing"
    # and "I could not work out where to look" produce the same empty list and
    # mean opposite things, and collapsing them is what produced the exit-0
    # no-op above. A location is locatable if something was actually found, or
    # if the resolver resolved - in which case an empty result really is empty.
    $dataLocatable = ($dataDirs.Count -gt 0) -or [bool]$stateInfo.resolved

    $extra = ''
    if ($sweepNote)          { $extra += " ($sweepNote)" }
    if ($dataGhosts.Count)   { $extra += ' | reported but NOT present, so nothing to delete: ' + ((@($dataGhosts | ForEach-Object { "$($_.Path) [$($_.Why)]" })) -join '; ') }
    if ($sizeUnknown -gt 0)  { $extra += " | $sizeUnknown directory(ies) could not be measured, so the size above is a FLOOR" }

    # A row of its own rather than a footnote on the state-data row, because a
    # refusal is a thing this script decided, not a thing it observed.
    if ($dataRefused.Count -gt 0) {
        Add-PlanRow -Id 'state-data-refused' -State "$($dataRefused.Count) dir(s)" -Action 'REFUSED - never deleted, whatever flags are passed' `
                  -Detail ((@($dataRefused | ForEach-Object { "$($_.Path) [$($_.Why)] $($_.Refusal)" }) -join '; '))
        foreach ($t in $dataRefused) {
            Add-Left -What "the directory $($t.Path)" -Why $t.Refusal
        }
    }

    if ($dataDirs.Count -gt 0) {
        $ok = ($RemoveData -and $ConfirmToken -eq 'DELETE-MY-LWG-LOGS')
        Add-PlanRow -Id 'state-data' -State "$($dataDirs.Count) dir(s), $(Format-LwgBytes $totalBytes)" `
                  -Action $(if ($ok) { 'DELETE - confirmed' } elseif ($RemoveData) { 'REFUSED - wrong or missing -ConfirmToken' } else { 'kept - this is evidence' }) `
                  -Detail ((@($dataDirs | ForEach-Object { "$($_.Path) [$($_.Why)]" }) -join '; ') + $extra)
        if (-not $ok) {
            Add-Left -What "$($dataDirs.Count) data directories ($(Format-LwgBytes $totalBytes))" `
                     -Why 'health.jsonl and lw-watchtower.jsonl are the record of every fault, gate trip and advisory this plugin saw, including whatever prompted the uninstall. Deleting them needs -RemoveData -ConfirmToken DELETE-MY-LWG-LOGS.'
        }
    }
    elseif ($dataRefused.Count -gt 0) {
        # Not 'absent' and not 'nothing to do'. Everything that was found was
        # refused, so there is nothing this script WILL remove - which is a very
        # different sentence from there being nothing to remove.
        Add-PlanRow -Id 'state-data' -State 'none removable' -Action 'nothing this script will delete' `
                  -Detail ("every directory found was refused - see the state-data-refused row. The state-data location resolved to $($stateInfo.path) - $srcWhy." + $extra)
    }
    elseif ($dataLocatable) {
        Add-PlanRow -Id 'state-data' -State 'absent' -Action 'nothing to do' `
                  -Detail ("the state-data location RESOLVED to $($stateInfo.path) - $srcWhy - and no directory this plugin owns exists there or under $dataRoot. This row means there is nothing, not that nothing was looked for." + $extra)
    }
    else {
        # Never 'absent'. Absent is a finding; this is the absence of a finding.
        Add-PlanRow -Id 'state-data' -State 'UNRESOLVED' `
                  -Action $(if ($RemoveData) { 'CANNOT ACT - the location is unknown' } else { 'CANNOT REPORT - the location is unknown' }) `
                  -Detail ("Get-LwgStateDirInfo returned source '$($stateInfo.source)', resolved $($stateInfo.resolved), $($stateInfo.candidates) candidate(s), and nothing under $dataRoot matches '$name*' or any legacy name ($(($script:LwgLegacyDataNames | ForEach-Object { "'$_*'" }) -join ', ')). CLAUDE_PLUGIN_DATA is not set in this shell, so there is no authoritative answer either. This is NOT a report that there is no state data - run /lw-watchtower:doctor, which prints the state dir it resolves, and pass that directory as CLAUDE_PLUGIN_DATA or -DataRoot." + $extra)
        Add-Left -What 'the state-data directories, wherever they are' `
                 -Why  'this script could not resolve the state-data location at all, so it can neither list nor remove them. Nothing here should be read as evidence that there are none - see the state-data row for the two ways to pin the location.'
    }

    # ---------------------------------------------------------------------
    # 6. the clone itself
    # ---------------------------------------------------------------------
    # Never removed. It is a git working tree that may hold unpushed work, so the
    # only useful thing to do is say whether it does - and if git cannot answer,
    # say that rather than imply the tree is clean.
    $gitReport = 'not a git repo'
    $repoInfo = Get-LwgRepoInfo -Path $pluginRoot
    if ($repoInfo.gitdir) {
        $g = Invoke-LwgCmdProcess -File 'git' -ProcArgs @('status', '--porcelain=v2', '--branch') -WorkDir $pluginRoot -TimeoutMs 4000
        $why = Get-LwgToolReport -Tool 'git status' -Result $g
        if ($why) {
            $gitReport = "UNKNOWN - $why"
        } else {
            $lines = @($g.out -split "`r?`n" | Where-Object { $_ -and $_ -notlike '#*' })
            $branch = ''
            foreach ($l in @($g.out -split "`r?`n")) { if ($l -like '# branch.head*') { $branch = ($l -split ' ')[2] } }
            $gitReport = if ($lines.Count -eq 0) { "clean on branch $branch" } else { "$($lines.Count) uncommitted change(s) on branch $branch - deleting this clone would lose them" }
        }
    }
    Add-PlanRow -Id 'plugin-clone' -State 'PRESENT' -Action 'REPORT ONLY - never removed' -Detail "$pluginRoot ($gitReport)"
    Add-Left -What "the clone at $pluginRoot" -Why 'it is source code and possibly unpushed work. Removing the junction unloads the plugin; deleting the clone is a separate decision that is yours.'

    # ---------------------------------------------------------------------
    # 7. backups available for a restore
    # ---------------------------------------------------------------------
    $baks = @()
    try {
        $sdir = Split-Path -Parent $SettingsPath
        $sname = Split-Path -Leaf $SettingsPath
        $baks = @(Get-ChildItem -LiteralPath $sdir -File -Filter "$sname*.bak" -ErrorAction Stop | Sort-Object LastWriteTime -Descending)
    } catch { }
    if ($baks.Count -gt 0) {
        Add-PlanRow -Id 'settings-backups' -State "$($baks.Count) found" -Action 'available for -RestoreSettings' `
                  -Detail (@($baks | Select-Object -First 4 | ForEach-Object { "$($_.Name) ($($_.LastWriteTime.ToString('yyyy-MM-dd HH:mm')), $(Format-LwgBytes $_.Length))" }) -join '; ')
    } else {
        Add-PlanRow -Id 'settings-backups' -State 'none' -Action 'n/a' -Detail "no $((Split-Path -Leaf $SettingsPath))*.bak next to the settings file"
    }

    # --- the plan -----------------------------------------------------------
    Write-Output ''
    $w = 3; foreach ($r in $script:Plan) { if ($r.Id.Length -gt $w) { $w = $r.Id.Length } }
    $ws = 3; foreach ($r in $script:Plan) { if ($r.State.Length -gt $ws) { $ws = $r.State.Length } }
    Write-Output '  FOOTPRINT'
    Write-Output ''
    foreach ($r in $script:Plan) {
        Write-Output ("  {0}  {1}  {2}" -f $r.Id.PadRight($w), $r.State.PadRight($ws), $r.Action)
        Write-Output ("  {0}  {1}" -f ''.PadRight($w), $r.Detail)
    }

    if ($settingsUnread) {
        Write-Output ''
        Write-Output "  NOTE: settings.json could not be read ($settingsErr), so every settings-based row above is"
        Write-Output '  UNKNOWN rather than absent. Nothing there was inspected.'
    } elseif ($settingsMissing) {
        Write-Output ''
        Write-Output "  NOTE: there is no file at $SettingsPath. That is a finding, not a gap: the settings-based"
        Write-Output '  rows above say absent because the file that would declare those keys does not exist.'
    }

    # --- restore path -------------------------------------------------------
    # EVERY PATH OUT OF THIS BRANCH IS AN `exit`, so the dry-run block below it
    # and the apply block below that are unreachable once -RestoreSettings is
    # set. That is the right shape for an escape hatch - one question, answered,
    # leave - but until 3 August 2026 nothing said so to an operator who asked
    # for two modes at once. `-RestoreSettings <bak> -Apply -RemoveData
    # -ConfirmToken DELETE-MY-LWG-LOGS` restored the file, printed RESTORED and
    # exited 0 - the code the header at the top defines as "every requested
    # removal was made" - with the removal never attempted and never mentioned.
    # The dry-run form was worse in a different way: it exited 0 at the DRY RUN
    # line, walking around the -RemoveData/unlocatable guard further down whose
    # exit-2 behaviour tests\uninstall_footprint.ps1 exists to assert.
    #
    # Refused rather than performed-then-fallen-through, which is the smaller
    # change and the one this file has precedent for: every other dropped
    # request here is loud. It is also the correct answer on the merits - a
    # restore puts back the very statusLine key and deny entries a removal in
    # the same run would be taking out, so the two orders give two different
    # results and neither is obviously the one that was meant.
    if (-not [string]::IsNullOrWhiteSpace($RestoreSettings)) {
        $alsoAsked = @()
        if ($RemoveStatusLine)  { $alsoAsked += '-RemoveStatusLine' }
        if ($RemovePermissions) { $alsoAsked += '-RemovePermissions' }
        if ($RemoveData)        { $alsoAsked += '-RemoveData' }
        if ($All)               { $alsoAsked += '-All' }
        if ($alsoAsked.Count -gt 0) {
            Write-Output ''
            Write-Output ("  REFUSED - -RestoreSettings was passed together with " + ($alsoAsked -join ', ') + '.')
            Write-Output '    A restore and a removal are two runs. The restore would put back what the removal is about'
            Write-Output '    to take out, and this script will not guess at the order you meant. Nothing was written.'
            Write-Output '    Run the restore on its own first, read the footprint it prints, then run the removal.'
            exit 1
        }
        Write-Output ''
        Write-Output "  RESTORE: $RestoreSettings -> $SettingsPath"
        if (-not (Test-Path -LiteralPath $RestoreSettings)) {
            Write-Output '  REFUSED - that backup does not exist. Nothing was written.'
            exit 1
        }
        $bak = Read-LwgTextFile -Path $RestoreSettings
        if (-not $bak.ok -or -not (Test-LwgJsonParses -Text $bak.text)) {
            Write-Output '  REFUSED - that backup does not parse as JSON. Restoring it would leave you with no settings at all.'
            exit 1
        }
        # State the difference rather than assert equivalence. A backup taken
        # before the install may also predate unrelated changes made since, and
        # restoring it silently reverts those too.
        try {
            $b = $bak.text | ConvertFrom-Json
            $c = $settingsObj
            # Same null filter as section 4, and for the same measured reason:
            # @($x.deny) on an object with no `deny` key is a one-element array
            # holding $null, so both of the two lines the text below tells the
            # operator to read before -Apply reported one entry for a file that
            # declares none - on both sides of the comparison.
            Write-Output ("    backup:  {0} deny entr(ies), statusLine {1}" -f @(@($b.permissions.deny) | Where-Object { $null -ne $_ }).Count, $(if ($b.statusLine) { 'present' } else { 'absent' }))
            if ($null -ne $c) {
                Write-Output ("    current: {0} deny entr(ies), statusLine {1}" -f @(@($c.permissions.deny) | Where-Object { $null -ne $_ }).Count, $(if ($c.statusLine) { 'present' } else { 'absent' }))
            } else {
                Write-Output "    current: $(if ($settingsMissing) { 'THERE IS NO FILE AT THAT PATH' } else { "NOT READ ($settingsErr)" }), so there is no line to compare the backup against."
            }
            Write-Output '    A restore reverts EVERY difference, not only the ones this plugin made. Read those two lines before -Apply.'
        } catch { }
        if (-not $Apply) {
            Write-Output '  DRY RUN - nothing was written. Add -Apply to restore.'
            exit 0
        }

        # THE CASE A RESTORE IS ACTUALLY FOR, and the one that did not work.
        # -RestoreSettings exists because settings.json has been damaged, and
        # when it is ABSENT $settings is $null, when it is UNREADABLE
        # $settings.sha is ''. Both were passed straight to Save-LwgTextFile's
        # [Parameter(Mandatory)][string]$ExpectedSha, which rejects $null and ''
        # alike AT BIND TIME with "because it is an empty string" - so the outer
        # catch printed a message naming an internal parameter and exited 3,
        # with nothing restored. Split into the three cases it really has.
        if (-not (Test-Path -LiteralPath $SettingsPath)) {
            # Nothing to hash, nothing to back up, nothing to clobber, so the
            # concurrent-change check has no subject. FileMode.CreateNew rather
            # than WriteAllText: it is atomic, so a settings.json created by the
            # CLI between the Test-Path above and this line makes the open throw
            # instead of being silently overwritten. That is the same guarantee
            # Save-LwgTextFile gives, obtained the way it is available here.
            try {
                $fs = [IO.File]::Open($SettingsPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try {
                    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($bak.text)
                    $fs.Write($bytes, 0, $bytes.Length)
                } finally { $fs.Dispose() }
            } catch {
                Write-Output "  FAILED - $SettingsPath did not exist and could not be created: $($_.Exception.Message)"
                Write-Output '    If it exists now, another process created it while this ran. Re-run to re-plan.'
                exit 2
            }
            Write-Output "  RESTORED. $SettingsPath did not exist, so it was CREATED from the backup - there was no"
            Write-Output '    previous file to compare against, no concurrent-change check was possible, and no'
            Write-Output '    pre-restore backup was taken because there was nothing to back up. Written without a'
            Write-Output '    byte-order mark; if the file this replaces had one, re-add it by hand.'
            exit 0
        }
        if ($null -eq $settings -or -not $settings.ok) {
            # The file is THERE and could not be read. Overwriting it would
            # destroy content this script never saw, which is the one thing the
            # header promises it will never do. NOT CLOSED by this branch: the
            # operator still cannot restore over an unreadable settings.json
            # through this script - they are told why and what to do instead,
            # which is the honest half of the fix, not the whole of it.
            Write-Output "  REFUSED - $SettingsPath exists but could not be read ($settingsErr)."
            Write-Output '    Restoring over it would overwrite a file this script never saw the contents of. Move it'
            Write-Output '    aside by hand (whatever is holding it open must be closed first), then re-run this: with'
            Write-Output '    no file there, the restore creates one from the backup. Nothing was written.'
            exit 1
        }
        $save = Save-LwgTextFile -Path $SettingsPath -Text $bak.text -ExpectedSha $settings.sha -Bom $settings.bom -BackupTag 'lwg-preRestore'
        if (-not $save.ok) { Write-Output "  FAILED - $($save.reason)"; exit 2 }
        Write-Output "  RESTORED. The file as it was before this restore: $($save.backup)"
        exit 0
    }

    # --- apply --------------------------------------------------------------
    if (-not $Apply) {
        Write-Output ''
        Write-Output '  DRY RUN - nothing above was written, moved or deleted.'
        Write-Output '  To act, re-run with -Apply plus the specific opt-in flags:'
        Write-Output '    -RemoveStatusLine    remove the statusLine key AND the installed statusline.ps1'
        Write-Output '    -RemovePermissions   remove the attributable permissions.deny entries'
        Write-Output '    -RemoveData          delete the log/state directories (needs -ConfirmToken DELETE-MY-LWG-LOGS)'
        Write-Output '    -All                 the first two. Never the third.'

        # A dry run that was ASKED about the data and cannot say where it is has
        # not completed, and must not exit 0. "Add -Apply and it will work" is
        # exactly the sentence that would be false here.
        if ($RemoveData -and -not $dataLocatable) {
            Write-Output ''
            Write-Output '  -RemoveData was requested, and this run could NOT establish where the state data lives.'
            Write-Output '  Re-running with -Apply would delete nothing and would have nothing to report - see the'
            Write-Output '  state-data row above for how to pin the location. Exiting 2 rather than 0, because an'
            Write-Output '  unanswerable question is not a clean dry run.'
            $script:Failed++
        }
    }
    else {
        # THE STATUS-LINE KEY DECISION, TRACKED, because the file half below
        # depends on it. $slKeySettled means this run knows what the key is:
        # either it was removed, or it was READ and found absent, or it was READ
        # and found to be somebody else's. It is deliberately NOT "no error
        # happened" - a settings.json that could not be read leaves it false.
        $slKeySettled = $false
        $slKeyWhyNot  = ''
        if ($settingsUnread) {
            $slKeyWhyNot = "settings.json could not be read or parsed ($settingsErr), so whether it declares a statusLine key pointing at that file is unknown"
        } elseif ($null -eq $slKey -or -not $slIsOurs) {
            $slKeySettled = $true
        }

        $wantSettingsEdit = ($RemoveStatusLine -and $null -ne $slKey -and $slIsOurs) -or ($RemovePermissions -and $denyOurs.Count -gt 0)

        # THE GUARD THAT COULD NOT FIRE. This test used to sit INSIDE
        # `if ($wantSettingsEdit)`, and both operands of $wantSettingsEdit are
        # assigned only when the settings read succeeded - so on the one failure
        # it guards against, $wantSettingsEdit was false and the refusal was
        # unreachable dead code. `-All -Apply` against an unreadable
        # settings.json therefore skipped the whole settings section, fell
        # through to the statusline-file deletion, deleted ~/.claude/statusline.
        # ps1, printed `APPLIED: 1 change(s), 0 failure(s)` and exited 0 - with
        # the statusLine key still there, pointing at a file that no longer
        # exists, which per the pairing note in section 3 renders an error on
        # every message and blanks the whole row. Hoisted out so it can fire.
        if (($RemoveStatusLine -or $RemovePermissions) -and $settingsUnread) {
            Write-Output ''
            Write-Output "  REFUSED - settings.json could not be read or parsed ($settingsErr), so it will not be"
            Write-Output '    written, and nothing that pairs with it will be removed either. Nothing was changed.'
            exit 1
        }

        if ($wantSettingsEdit) {
            if ($null -eq $settings -or -not $settings.ok) {
                Write-Output ''
                Write-Output "  REFUSED - settings.json could not be read ($settingsErr), so it will not be written."
                exit 1
            }

            # RE-READ IMMEDIATELY BEFORE PLANNING THE EDIT. The plan above was
            # built from a read that is now seconds old, and this file is
            # rewritten by the CLI from under its readers.
            $fresh = Read-LwgTextFile -Path $SettingsPath
            if (-not $fresh.ok) { Write-Output "  REFUSED - re-read of $SettingsPath failed: $($fresh.error)"; exit 1 }
            if ($fresh.sha -ne $settings.sha) {
                Write-Output ''
                Write-Output '  REFUSED - settings.json changed between the plan above and this write.'
                Write-Output "    planned against SHA256 $($settings.sha.Substring(0,12))..., found $($fresh.sha.Substring(0,12))..."
                Write-Output '    Another process is editing it. Re-run to re-plan against what it says now.'
                exit 1
            }

            $text = $fresh.text
            $changes = @()

            if ($RemoveStatusLine -and $null -ne $slKey -and $slIsOurs) {
                $rootObj = $text.IndexOf('{')
                $cut = Remove-LwgJsonMember -Text $text -ObjStart $rootObj -Key 'statusLine'
                if ($cut.ok) { $text = $cut.text; $changes += 'statusLine key removed' }
                else {
                    Write-Output '  could not locate the statusLine member for removal'
                    $slKeyWhyNot = 'the statusLine member could not be located in the file for removal'
                    $script:Failed++
                }
            }

            if ($RemovePermissions -and $denyOurs.Count -gt 0) {
                $m = Get-LwgJsonMemberPath -Text $text -Path @('permissions', 'deny')
                if (-not $m.found -or $text[$m.value_start] -ne '[') {
                    Write-Output '  could not locate permissions.deny as an array'; $script:Failed++
                } else {
                    $close = Get-LwgJsonSpan -Text $text -Open $m.value_start
                    $inner = $text.Substring($m.value_start + 1, $close - $m.value_start - 1)
                    $lines = @($inner -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                    # One entry per line is the shape this file has and the shape
                    # this edit assumes. If it is not, the assumption is wrong and
                    # the edit does not happen - a mangled permissions file is a
                    # far worse outcome than an incomplete uninstall.
                    if ($lines.Count -ne $denyAll.Count) {
                        Write-Output "  REFUSED - permissions.deny holds $($denyAll.Count) entries across $($lines.Count) non-blank lines, so it is not one-entry-per-line."
                        Write-Output '    This edit only handles that shape. Nothing was written; edit the file by hand.'
                        exit 1
                    }
                    $keep = @()
                    for ($i = 0; $i -lt $lines.Count; $i++) {
                        if (Test-MirroredDeny -Entry ([string]$denyAll[$i])) { continue }
                        $keep += ($lines[$i].TrimEnd().TrimEnd(','))
                    }
                    $nl = Get-LwgJsonNewline -Text $text
                    $body = if ($keep.Count -eq 0) { '' } else { $nl + (($keep -join ",$nl")) + $nl + (Get-LwgJsonIndent -Text $text -Index $m.value_start) }
                    $text = $text.Substring(0, $m.value_start + 1) + $body + $text.Substring($close)
                    $changes += "$($denyOurs.Count) permissions.deny entries removed, $($keep.Count) kept"
                }
            }

            if ($changes.Count -gt 0) {
                if (-not (Test-LwgJsonParses -Text $text)) {
                    Write-Output ''
                    Write-Output '  REFUSED - the edited settings.json does not parse. It was NOT written. This is a bug in this script.'
                    exit 1
                }
                $save = Save-LwgTextFile -Path $SettingsPath -Text $text -ExpectedSha $fresh.sha -Bom $fresh.bom -BackupTag 'lwg-uninstall'
                if (-not $save.ok) {
                    Write-Output ''
                    Write-Output "  settings.json NOT written: $($save.reason)"
                    $script:Failed++
                } else {
                    Write-Output ''
                    Write-Output "  settings.json written. Backup: $($save.backup)"
                    foreach ($c in $changes) { Write-Output "    $c"; $script:Done++ }
                }
            }
        }

        # THE OTHER HALF OF THE SAME DECISION, and until 3 August 2026 it was not
        # gated on the first one at all. Section 3 states the invariant - "the
        # key without the file renders an error on every message and blanks the
        # whole row; the file without the key is dead weight, so they are one
        # decision" - and the line 553 dry-run text promises "-RemoveStatusLine
        # remove the statusLine key AND the installed statusline.ps1". But the
        # key half was gated on attribution, on a successful re-read, on a SHA
        # match, on the JSON surgery succeeding and on the save succeeding, and
        # the file half was gated on -RemoveStatusLine and Test-Path. Any one of
        # those five failing deleted the file and left the key. Save-LwgTextFile
        # returning CHANGED UNDER US is the likeliest: its own docstring calls
        # that "a correct outcome, not a failure: re-read and re-plan" - but the
        # re-plan then runs against a world the failed run already mutated.
        #
        # So the deletion now asks the same question the key edit answered.
        # $slKeyRemoved is deliberately "the edit was planned AND the file was
        # written", not "the edit was planned": Save-LwgTextFile returning
        # not-ok leaves $changes carrying an entry for a change that never
        # reached disk, and reading $changes alone would call that a removal.
        $slKeyRemoved = ($changes -contains 'statusLine key removed') -and ($null -ne $save) -and $save.ok
        if ($slKeyRemoved) {
            $slKeySettled = $true
        } elseif ($changes -contains 'statusLine key removed') {
            $slKeySettled = $false
            $slKeyWhyNot  = "settings.json was not written ($($save.reason)), so the statusLine key is still there"
        }

        if ($RemoveStatusLine -and (Test-Path -LiteralPath $slFile)) {
            if (-not $slKeySettled) {
                Write-Output ''
                Write-Output "  KEPT $slFile - the statusLine key half of this removal did not complete."
                Write-Output "    $slKeyWhyNot."
                Write-Output '    Deleting the file while the key survives would leave the key pointing at nothing, which'
                Write-Output '    renders an error on every message and blanks the whole status row. Both halves or neither.'
                # Counted as a failure because -RemoveStatusLine asked for this
                # file and it was not removed. Per the exit-code contract at the
                # top of this file that is exit 2, not exit 0.
                $script:Failed++
                Add-Left -What "the installed status line $slFile" -Why "$slKeyWhyNot, and this script will not delete the file without the key"
            } else {
                try {
                    $keep = "$slFile.lwg-uninstall-$((Get-Date).ToString('yyyyMMdd-HHmmss')).bak"
                    Copy-Item -LiteralPath $slFile -Destination $keep -ErrorAction Stop
                    Remove-Item -LiteralPath $slFile -Force -ErrorAction Stop
                    Write-Output "  deleted $slFile (a copy was kept at $keep)"
                    $script:Done++
                } catch {
                    Write-Output "  could NOT delete $slFile - $($_.Exception.Message)"
                    $script:Failed++
                }
            }
        }

        # AND THE INVERSE, which had no Add-Left of its own either. Add-Left is
        # called for the junction, the non-attributable key, permissions, data
        # and the clone; a statusLine key this run was ASKED to remove and did
        # not remove was the one thing the script's own honesty mechanism did
        # not name. No $script:Failed++ here on purpose - every path that
        # reaches this with the key surviving has already counted it once (the
        # "could not locate the statusLine member" and "settings.json NOT
        # written" branches above) or exited 1 before getting here, and counting
        # one un-removed key as two failures is its own small overstatement.
        if ($RemoveStatusLine -and $null -ne $slKey -and $slIsOurs -and -not $slKeyRemoved) {
            Add-Left -What 'the statusLine key in settings.json' -Why "-RemoveStatusLine asked for it and it is still there: $(if ($slKeyWhyNot) { $slKeyWhyNot } else { 'the settings edit did not complete' })"
        }

        if ($RemoveData) {
            if ($ConfirmToken -ne 'DELETE-MY-LWG-LOGS') {
                Write-Output ''
                Write-Output '  REFUSED - -RemoveData needs -ConfirmToken DELETE-MY-LWG-LOGS, typed exactly.'
                Write-Output '    These directories are the only record of what this plugin observed. Nothing was deleted.'
                exit 1
            }
            # An empty list is two different answers and they get two different
            # exit codes. This is the whole of the defect fixed on 31 July 2026:
            # the branch below used to be absent, so "I never found out where to
            # look" fell through to APPLIED: 0 change(s), 0 failure(s) and exit 0.
            # Reported before the empty-list branch below, because "everything
            # found was refused" is a third answer and must not be read as
            # either of the other two. Each refused directory is counted as a
            # failure: -RemoveData asked for it and it was not removed.
            foreach ($t in $dataRefused) {
                Write-Output ''
                Write-Output "  $($t.Refusal)"
                Write-Output "    path: $($t.Path)"
                Write-Output '    NOTHING IN IT WAS DELETED.'
                $script:Failed++
            }

            if ($dataDirs.Count -eq 0 -and $dataRefused.Count -gt 0) {
                Write-Output ''
                Write-Output '  Every state-data directory this run found was refused above, so nothing was deleted. That is'
                Write-Output '  not a report that there was nothing to delete.'
            }
            elseif ($dataDirs.Count -eq 0) {
                Write-Output ''
                if ($dataLocatable) {
                    Write-Output "  nothing to delete. The state-data location resolved to $($stateInfo.path) (source '$($stateInfo.source)')"
                    Write-Output '  and holds no directory belonging to this plugin. That is an answer, arrived at by resolving the'
                    Write-Output '  location - not by failing to find it.'
                } else {
                    Write-Output '  FAILED - -RemoveData was requested and this script could not work out WHERE the state data lives.'
                    Write-Output "    Get-LwgStateDirInfo returned source '$($stateInfo.source)', resolved $($stateInfo.resolved); nothing under"
                    Write-Output "    $dataRoot matches '$name*'; CLAUDE_PLUGIN_DATA is not set in this shell."
                    Write-Output '    NOTHING WAS DELETED, and this is not a report that there was nothing to delete. Run'
                    Write-Output '    /lw-watchtower:doctor, take the state dir it prints, and set CLAUDE_PLUGIN_DATA to it (or pass'
                    Write-Output '    -DataRoot) before running this again.'
                    $script:Failed++
                }
            }

            foreach ($d in $dataDirs) {
                # Re-checked rather than trusted from the plan: the footprint was
                # printed seconds ago and this script promises that what it said
                # it would remove is what it removed.
                if (-not [IO.Directory]::Exists($d.Path)) {
                    Write-Output "  $($d.Path) is no longer there. It went between the plan above and this write, so this"
                    Write-Output '    script did not remove it and does not count it as a change it made.'
                    continue
                }
                # A REPARSE POINT IS NOT A DIRECTORY THIS SCRIPT CAN DELETE
                # HONESTLY, and it is checked before anything else here because
                # every line after it would describe the wrong filesystem.
                #
                # MEASURED, on Windows PowerShell 5.1.26100.8875, this machine,
                # 3 August 2026, both shapes - the state dir IS a junction, and
                # the state dir CONTAINS one: `Remove-Item -Recurse -Force`
                # removed the link and left the target's contents untouched. It
                # did not delete through it. So the hazard section 1 states at
                # the `Add-Left` for the skills junction did NOT reproduce here,
                # and this block does not claim it did.
                #
                # What reproduces is the mirror image, and it is this script's
                # own founding defect: the link goes, [IO.Directory]::Exists is
                # then false, and the run prints `deleted <path>`, counts a
                # change and exits 0 - while every log file on the other side of
                # the junction is still there. An operator who redirected state
                # off the system drive with `mklink /J` (the pattern this
                # plugin's own install page teaches, and the reason to redirect
                # is that the state dir accumulates jsonl indefinitely) types
                # DELETE-MY-LWG-LOGS, is told the logs are gone, and they are
                # not. That is a switch wired to the wrong thing wearing a
                # success message.
                #
                # Refused rather than followed, matching the precedent set for
                # the skills junction: this script prints the one command that
                # removes a link and only a link, and lets the operator decide
                # about the target. Refusing is also the version-independent
                # answer - the delete-through behaviour is a real property of
                # some Windows PowerShell builds even though it is not this
                # one's, and a script that only refuses on the builds where it
                # measured the hazard is a script that got lucky.
                $isReparse = $false
                $linkTgt   = ''
                try {
                    $di = New-Object IO.DirectoryInfo($d.Path)
                    $isReparse = (($di.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
                } catch { }
                if ($isReparse) {
                    try { $linkTgt = @((Get-Item -LiteralPath $d.Path -Force -ErrorAction Stop).Target) -join ', ' } catch { }
                    Write-Output "  REFUSED to delete $($d.Path) - it is a reparse point (a junction or symlink)$(if ($linkTgt) { " pointing at $linkTgt" } else { '' })."
                    Write-Output '    Removing it would remove the LINK. Whatever this plugin wrote lives on the other side and'
                    Write-Output '    would survive, so reporting it as deleted would be false. Delete the target yourself if'
                    Write-Output "    that is what you want, then:  cmd /c rmdir `"$($d.Path)`"  - which removes the link only."
                    # Counted as a failure: -RemoveData asked for this directory
                    # and it was not removed. Exit 2 per the contract at the top.
                    $script:Failed++
                    Add-Left -What "the state-data directory $($d.Path)" `
                             -Why "it is a reparse point$(if ($linkTgt) { " pointing at $linkTgt" } else { '' }), so deleting it would delete the link and leave the files. This script will not report that as a deletion."
                    continue
                }

                # FINGERPRINTED BEFORE AND AFTER, because `Remove-Item -Recurse`
                # deletes children as it walks and throws on the FIRST one it
                # cannot remove. Measured on this machine: a directory of five
                # files with one held open by another process lost the other
                # four and then threw. Until 3 August 2026 the catch below
                # printed `could NOT delete <path>` for that, which an operator
                # reads as "my logs are intact" - and the evidence the header
                # calls "the record of every fault, gate trip and advisory this
                # plugin saw, including whatever prompted the uninstall" was
                # four fifths destroyed.
                $before = @()
                $beforeKnown = $false
                try {
                    $before = @(Get-ChildItem -LiteralPath $d.Path -File -Recurse -Force -ErrorAction Stop | ForEach-Object { $_.FullName })
                    $beforeKnown = $true
                } catch { }

                $threw = ''
                try { Remove-Item -LiteralPath $d.Path -Recurse -Force -ErrorAction Stop }
                catch { $threw = $_.Exception.Message }

                # VERIFIED, not assumed, and verified on CONTENTS rather than on
                # existence. Existence alone had the inverse error too:
                # Get-LwgStateDir calls [IO.Directory]::CreateDirectory on EVERY
                # hook invocation, so a hook firing between the remove and the
                # check recreated the directory and a completely successful
                # deletion was reported as "the remove reported no error but the
                # directory is still there", $script:Failed++, exit 2.
                if (-not [IO.Directory]::Exists($d.Path)) {
                    Write-Output ("  deleted $($d.Path)" + $(if ($beforeKnown) { " ($($before.Count) file(s))" } else { '' }))
                    $script:Done++
                    continue
                }

                $after = @()
                $afterKnown = $false
                try {
                    $after = @(Get-ChildItem -LiteralPath $d.Path -File -Recurse -Force -ErrorAction Stop | ForEach-Object { $_.FullName })
                    $afterKnown = $true
                } catch { }

                if ($afterKnown -and $after.Count -eq 0) {
                    # Still there and EMPTY. Nothing this plugin recorded
                    # survives, so this is a removal that worked - the directory
                    # standing is either this plugin recreating its own state
                    # dir or an rmdir that could not unlink the folder itself.
                    Write-Output ("  deleted the contents of $($d.Path)" + $(if ($beforeKnown) { " ($($before.Count) file(s))" } else { '' }) + " - the directory itself is still there and is EMPTY.")
                    Write-Output '    Either a hook recreated it (this plugin creates its own state dir on every invocation) or'
                    Write-Output '    the folder could not be unlinked. Nothing this plugin wrote survives, so it is counted as'
                    Write-Output '    a removal that worked.'
                    if ($threw) { Write-Output "    The remove also reported: $threw" }
                    $script:Done++
                    continue
                }

                # Still there and still holding files. That is a failure, and
                # the message carries which half rather than only that there was
                # a problem.
                if ($beforeKnown -and $afterKnown) {
                    $wentCount = $before.Count - $after.Count
                    $names = @($after | ForEach-Object { Split-Path -Leaf $_ } | Select-Object -First 5) -join ', '
                    Write-Output "  PARTIALLY deleted $($d.Path) - $wentCount of $($before.Count) file(s) removed, $($after.Count) still there: $names$(if ($after.Count -gt 5) { ', ...' } else { '' })"
                    Write-Output '    THE REMOVED FILES ARE GONE. Do not read this as "nothing happened".'
                } elseif ($afterKnown) {
                    Write-Output "  could NOT fully delete $($d.Path) - $($after.Count) file(s) are still there, and this script could not list the directory before the attempt, so it cannot say how many went"
                } else {
                    Write-Output "  could NOT delete $($d.Path) - it is still there and could not be listed afterwards, so what remains in it is unknown"
                }
                if ($threw) { Write-Output "    The remove reported: $threw" }
                $script:Failed++
            }
        }

        Write-Output ''
        Write-Output "  APPLIED: $($script:Done) change(s), $($script:Failed) failure(s)."
    }

    # --- what is left, and why ----------------------------------------------
    Write-Output ''
    Write-Output '  LEFT BEHIND'
    Write-Output ''
    foreach ($l in $script:Left) {
        Write-Output "    $($l.What)"
        Write-Output "      $($l.Why)"
    }

    Write-Output ''
    Write-Output '  AND WHAT THIS SCRIPT CANNOT SEE'
    Write-Output ''
    Write-Output '    ~/.claude.json holds a pluginUsage counter naming this plugin. It is a 46 KB telemetry'
    Write-Output '    blob, not a registry, and editing it to remove a counter risks a file the CLI depends on'
    Write-Output '    for far more than this. Left alone deliberately.'
    Write-Output '    A MARKETPLACE install (lw-watchtower@<marketplace>) is a separate copy in the CLI cache with its'
    Write-Output '    own data dir. This script only knows about the junction and the data dirs listed above;'
    Write-Output '    use /plugin uninstall for that one.'
    Write-Output '    Other machines, other clones, and any settings.json outside the path printed at the top.'
    Write-Output '    ~/.claude/health/ is the operator own health supervisor, not part of this plugin, and is'
    Write-Output '    never touched here - even though the status line merges its log with this one.'
    # THIS BLIND SPOT WAS RETIRED ON 3 SEPTEMBER 2026 AND ITS ENTRY IS KEPT.
    #
    # It used to read "Nothing in this plugin reads CLAUDE_CONFIG_DIR, so this
    # script does not either rather than honour it in one place and not the
    # rest" - a deliberately-taken position, correct on the day it was written
    # and FALSE the moment lib\common.ps1 grew Get-LwgClaudeHomeInfo and this
    # file started calling it. The entry stays because the operator still needs
    # to know WHICH root the rows above describe and how it was chosen: a
    # footprint is a claim about a directory, and a claim about a directory that
    # does not name it is not checkable. What was a blind spot is now a
    # DISCLOSURE, which is why it is still printed on every run.
    $chSrc = switch ([string]$script:LwgHomeInfo.source) {
        'env'     { "CLAUDE_CONFIG_DIR = $($script:LwgHomeInfo.raw)" }
        'profile' { 'the user profile - CLAUDE_CONFIG_DIR is not set' }
        default   { 'nothing - neither CLAUDE_CONFIG_DIR nor USERPROFILE held a value' }
    }
    if ($script:LwgHomeGiven) {
        Write-Output ("    THE CONFIG DIRECTORY THESE ROWS DESCRIBE is $ClaudeHome, because -ClaudeHome named it.")
        Write-Output ("    An explicit path beats everything, so CLAUDE_CONFIG_DIR was NOT consulted for it; had it")
        Write-Output ("    been, it would have resolved $chSrc.")
    } else {
        Write-Output ("    THE CONFIG DIRECTORY THESE ROWS DESCRIBE is $ClaudeHome, resolved from $chSrc.")
        Write-Output ('    Every row above that is not state data hangs off it - the junction, the copied status')
        Write-Output ('    line, settings.json and its backups. This script now READS CLAUDE_CONFIG_DIR through the')
        Write-Output ('    same resolver the rest of the plugin uses; before 3 September 2026 nothing did, and a')
        Write-Output ('    machine that set it got a footprint of a directory nobody was using. If the root above')
        Write-Output ('    is still not the one your CLI loads, pass -ClaudeHome and -SettingsPath.')
    }
    Write-Output '    The state data is NOT affected by any of this - it is resolved through CLAUDE_PLUGIN_DATA'
    Write-Output '    and the shared resolver, in that order.'
    Write-Output '    WHAT IS INSIDE A STATE-DATA DIRECTORY. -RemoveData deletes the directory whole. If one of'
    Write-Output '    them holds another tool''s files as well as this plugin''s, those go too - the ownership test'
    Write-Output '    runs per DIRECTORY, never per file, and there is no per-file removal here.'
    Write-Output '    permissions.deny entries are attributed BY FAMILY, not from a stored list of what was'
    Write-Output '    installed, because no such list exists. A rule you added yourself that happens to look'
    Write-Output '    like one of the mirrored families will be counted as this plugin. That is why removing'
    Write-Output '    them is opt-in, backed up first, and printed before it happens.'
    Write-Output '    If you run this through an agent, the removals are ordinary file operations and nothing'
    Write-Output '    this plugin ships inspects what they would do: the one PreToolUse hook it registers,'
    Write-Output '    delegate_gate, looks only at whether the CALLER was a subagent, and it is off by default.'
    Write-Output '    Two things CAN still stop you. The CLI evaluating permissions.deny against the COMMAND'
    Write-Output '    LINE you typed - report any such denial verbatim; do not reword the command into a shape'
    Write-Output '    that slips past it. And delegate_gate itself, if interaction.delegate is on and you are'
    Write-Output '    on the main thread: run this from a subagent, or set that key to false by hand first.'

    if ($script:Failed -gt 0) { exit 2 }
    exit 0

} catch {
    Write-Output ''
    Write-Output "LW-WATCHTOWER uninstall could not complete: $($_.Exception.Message)"
    Write-Output 'Do not read anything above as a complete footprint, and do not assume nothing was changed:'
    Write-Output 'check the APPLIED line if there was one.'
    exit 3
}
