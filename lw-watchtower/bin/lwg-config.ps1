#requires -version 5
<#
  LW-WATCHTOWER config - switch a governance module on or off, globally or for one repo.

      powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-config.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-config.ps1 -Module git_hygiene -Off
      powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-config.ps1 -Module git_hygiene -Off -Apply

  Backs /lw-watchtower:config. The logic is here rather than in the command's prose
  because a model asked to "edit config.json" edits config.json, and what this
  file mostly does is REFUSE to.

  TWO REFUSALS ARE THE POINT OF IT.

  1. It will not enable a module that is declared but not implemented. Setting
     such a name to true produces a config that reads as more coverage than
     exists, and every reader downstream - the banner, /lw-watchtower:doctor, the
     operator - then has to know which names are real. That is the exact defect
     this plugin exists to catch, so the switch that would create it is closed.
     Every name in the registry is implemented as of 30 July 2026, so this
     refusal currently fires for nothing; it stands because it is what keeps the
     next declared-ahead-of-its-code name from being counted as coverage.
  2. It will not write when config.json is unreadable. Get-LwgConfig fails OPEN
     to built-in defaults, so a corrupt file still yields a running plugin; a
     write on top of that would replace the operator's real settings with the
     defaults' shape and destroy the evidence of what went wrong.

  -Repo IS CANONICALISED ONCE, BEFORE ANY OF THAT. Both a module name and a repo
  slug are matched case-SENSITIVELY by the JSON editor at the bottom of this file
  and case-INSENSITIVELY by every reader of the result, and each half of that
  mismatch shipped a false report: a wrong-case module name was diagnosed as
  config.json having drifted from the registry (#92), and a wrong-case or
  wrong-SHAPE -Repo produced "nothing to clear" over a live override and a
  "verified" write under a key no hook can ever match (#91). One block near the
  top settles the slug - reduced to the shape lib/common.ps1's Get-LwgRepoInfo
  hands a hook, then spelt the way config.json already spells it - so that
  everything after it looks up, writes, clears and verifies the same key.

  WHAT THAT BLOCK STILL CANNOT PROVE IS SAID OUT LOUD rather than left to the
  exit-2 check, which cannot see it. A slug of the right shape that matches no
  key in the file may simply be the wrong repository - a transposition has both
  properties - and the read-back below re-resolves the key this run just wrote,
  so it agrees with anything. When -Repo names a repository the working
  directory does not resolve to, the report says so under UNVERIFIED SCOPE and
  names -ThisRepo, which DERIVES the slug instead of trusting it. It is not a
  refusal: overriding a repository you are not standing in is legitimate, and
  this command cannot tell that apart from a typo.

  Nothing is written without -Apply, and the explanation of what a change means
  is printed BEFORE the write in both modes - so the preview run and the applied
  run say the same words in the same order, and the operator sees the reasoning
  either way.

  Exit codes:

      0  did what was asked (a listing, a preview, or a completed write)
      1  REFUSED - the request cannot be honoured, and the reason is printed
      2  the write was made and did NOT take effect - a real fault, see below
      3  this script could not complete

  2 exists because a config editor that reports success without changing the
  effective value is the same silent no-op the rest of this plugin hunts. After
  every write the file is re-read from disk and the module is re-resolved through
  Test-LwgModule, i.e. through the same code path a hook uses. If that does not
  agree with what was asked for, this exits 2 and says so.
#>

param(
    # The module to change. Omit for a read-only listing of every module's state.
    [string]$Module,

    # Exactly one of these when -Module is given. -Clear removes a per-repo
    # override so the module falls back to the global default.
    [switch]$On,
    [switch]$Off,
    [switch]$Clear,

    # Scope. Default is global; -Repo <owner/name> or -ThisRepo scopes the change
    # to one repository's `repos` block.
    [string]$Repo,
    [switch]$ThisRepo,

    # Write. Without it nothing on disk is touched.
    [switch]$Apply,

    # Point at a copy of the SHIPPED DEFAULTS instead of the live config.json -
    # used by the tests. It no longer redirects the WRITE and cannot: since #11
    # this command writes config.override.json under the state directory, which
    # is resolved from CLAUDE_PLUGIN_DATA and not from here. Redirect that
    # variable to move the write; redirect this to change what the write is
    # merged over.
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

$script:Exit = 0

function Write-Refusal {
    param([string[]]$Lines)
    Write-Output ''
    Write-Output 'REFUSED - nothing was written.'
    foreach ($l in $Lines) { Write-Output "  $l" }
    $script:Exit = 1
}

function Get-LwgConfigRepoShape {
    <#
      -Repo, reduced to the shape a hook actually produces - or the reason it
      cannot be. Returns @{ ok; slug; why }, a HASHTABLE so it survives the
      function boundary un-enumerated like every other structure in this repo.

      THIS IS HALF OF THE ANSWER TO #91, and the half that has to come first.
      A per-repo override is keyed by the slug lib/common.ps1's Get-LwgRepoInfo
      hands a hook: it takes the origin remote's URL, matches one of exactly two
      forms, and emits "<owner>/<name>" with any .git suffix and trailing slash
      already gone. That is the ONLY shape any reader ever asks `repos` for, so
      a key of any other shape is not an override at all - it is a member no
      hook can ever match, written and then "verified" against itself by the
      exit-2 check, which resolves it through the same PowerShell property
      lookup that just wrote it and so agrees with anything.

      The two reductions below are the SAME expressions Get-LwgRepoInfo uses, so
      a remote URL pasted at -Repo lands on the identical slug the hook would
      have computed from that remote. Anything that is not two slash-separated
      segments after reduction is refused rather than guessed at: this command
      does not get to invent a key shape.

      REDUCING rather than refusing a URL or a .git suffix is a decision, not an
      accident. A hook can never produce a slug ending in .git - both regexes
      strip it unconditionally - so `owner/name.git` is never the key that would
      be read, and the operator who typed it meant the repository, not a key
      nothing looks up.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Value)

    $r = @{ ok = $false; slug = ''; why = '' }
    $v = "$Value".Trim()
    if ([string]::IsNullOrWhiteSpace($v)) { $r.why = 'it is empty'; return $r }

    if ($v -match '^[^@/]+@[^:/]+:(?<o>[^/]+)/(?<r>.+?)(\.git)?/?$') {
        # SSH scp-style: git@github.com:owner/repo.git
        $v = "$($Matches.o)/$($Matches.r)"
    }
    elseif ($v -match '^[A-Za-z][A-Za-z0-9+.\-]*://(?:[^/@]+@)?[^/]+/(?<o>[^/]+)/(?<r>.+?)(\.git)?/?$') {
        # Any URL form: https://, ssh://, git://, with or without a user@.
        $v = "$($Matches.o)/$($Matches.r)"
    }
    else {
        $v = $v.TrimEnd('/')
        if ($v -match '\.git$') { $v = $v.Substring(0, $v.Length - 4) }
    }

    if ($v -notmatch '^[^/\\:\s]+/[^/\\:\s]+$') {
        $r.why = "it reduces to '$v', which is not <owner>/<name> - one slash, two non-empty segments, no whitespace, backslash or colon"
        return $r
    }
    $r.ok = $true
    $r.slug = $v
    return $r
}

try {
    $pluginRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $pluginRoot 'lib\common.ps1')
    . (Join-Path $PSScriptRoot 'lwg-cmdlib.ps1')

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $pluginRoot 'config.json' }

    # --- WHAT IS READ AND WHAT IS WRITTEN ARE TWO FILES - #11 ----------------
    # config.json is the SHIPPED DEFAULTS and this command no longer writes it.
    # It is tracked and inside the plugin's own git working tree, so every write
    # left the checkout dirty and made /lw-watchtower:update refuse to pull for
    # good. The operator's choice goes to config.override.json under the state
    # directory, which Get-LwgConfig merges over the defaults - so the exit-2
    # read-back below still resolves the same document a hook resolves, which is
    # the property that makes it a verification rather than a tautology.
    $baseFile = Read-LwgTextFile -Path $ConfigPath
    if (-not $baseFile.ok) {
        Write-Output "LW-WATCHTOWER config"
        Write-Refusal @("cannot read $ConfigPath - $($baseFile.error)")
        exit $script:Exit
    }
    $cfg = Get-LwgConfig -Path $ConfigPath
    $onDefaults = ($cfg._source -ne 'file')

    $ovPath = Get-LwgConfigOverridePath
    if ([string]::IsNullOrWhiteSpace($ovPath)) {
        Write-Output 'LW-WATCHTOWER config'
        Write-Refusal @(
            'the state directory could not be resolved, so there is nowhere to record a setting.',
            'Operator settings live in config.override.json under $CLAUDE_PLUGIN_DATA (or',
            '~/.claude/plugins/data/lw-watchtower*/); config.json in the plugin root is the shipped',
            'defaults and this command does not write it.'
        )
        exit $script:Exit
    }
    # WHETHER $ovPath IS EVEN THE FILE A HOOK READS - #270. Resolved once, here,
    # because both the listing above and the write refusal below have to say the
    # same thing about it, and Get-LwgStateDirSplit's answer is $false for every
    # hook by construction (they take the env branch and never rank).
    $sdSplit = Get-LwgStateDirSplit

    # ABSENT IS A STATE, NOT AN ERROR. A machine that has never been configured
    # has no override, and a writer that assumes its target exists exits 3 on
    # every fresh install - the measurement that killed route 2a on #11. So an
    # absent file reads as the empty object it means, and the file itself is
    # created at the write and nowhere earlier: see the seed beside
    # Save-LwgTextFile below.
    $file = if ([IO.File]::Exists($ovPath)) { Read-LwgTextFile -Path $ovPath } `
            else { @{ ok = $true; text = '{}'; bom = $false; sha = ''; bytes = 0; error = '' } }
    if (-not $file.ok) {
        Write-Output 'LW-WATCHTOWER config'
        Write-Refusal @("cannot read $ovPath - $($file.error)")
        exit $script:Exit
    }

    # Scope resolution happens before anything is printed, because the whole
    # report is scoped by it.
    $repoNote = ''
    if ($ThisRepo) {
        $here = (Get-LwgRepoInfo -Path (Get-Location).Path)
        if ([string]::IsNullOrWhiteSpace($here.slug)) {
            Write-Output 'LW-WATCHTOWER config'
            Write-Refusal @(
                "-ThisRepo was passed but $((Get-Location).Path) resolves to no origin remote slug.",
                'A per-repo override is keyed by the "owner/name" of the origin remote; without one there is no key to write.',
                'Pass -Repo <owner/name> explicitly, or make the change globally.'
            )
            exit $script:Exit
        }
        if (-not [string]::IsNullOrWhiteSpace($Repo) -and $Repo -ne $here.slug) {
            Write-Output 'LW-WATCHTOWER config'
            Write-Refusal @("-Repo '$Repo' and -ThisRepo ('$($here.slug)') disagree; pass one of them.")
            exit $script:Exit
        }
        $Repo = $here.slug
        $repoNote = " (resolved from $((Get-Location).Path))"
    }

    # --- -Repo, canonicalised ONCE - #91 -------------------------------------
    # EVERYTHING BELOW LOOKS THE REPO UP, WRITES IT, CLEARS IT OR VERIFIES IT,
    # and until this block existed each of those did it on the string as typed.
    # Two facts about this file make that a defect rather than an untidiness:
    #
    #   * the WRITER matches JSON member names with -ceq, because JSON names are
    #     case-sensitive (bin\lwg-cmdlib.ps1:128), while every READER - the
    #     listing's OVERRIDE column, Test-LwgModule, the exit-2 verification -
    #     resolves repos.<slug> by PowerShell property lookup, which is not. On
    #     a config.json holding "Owner/Name", -Repo owner/name therefore reads
    #     as a LIVE override and writes as a MISSING one: -Clear prints
    #     "Nothing to clear" and exits 0 over an override this same command's
    #     own table has just printed, and an -On/-Off adds a SECOND key that
    #     only half of this plugin can see.
    #   * the shape was never checked at all, so -Repo https://github.com/o/n.git
    #     wrote exactly that as a `repos` key. No hook can produce that slug -
    #     Get-LwgRepoInfo emits owner/name - so nothing would ever read it, and
    #     the exit-2 verification could not tell: it re-resolves through the
    #     same case-insensitive property lookup, using the same bad key, and
    #     finds what was just written. A write nothing will honour, reported as
    #     verified, is the silent no-op this whole command exists to refuse.
    #
    # So it is settled HERE, once, before the header is printed and before any
    # of those four things happen. -ThisRepo has already resolved above, and its
    # slug goes through the same reconciliation: a hook-shaped slug still has to
    # be spelt the way the file spells it.
    if (-not [string]::IsNullOrWhiteSpace($Repo)) {
        $shape = Get-LwgConfigRepoShape -Value $Repo
        if (-not $shape.ok) {
            Write-Output 'LW-WATCHTOWER config'
            Write-Refusal @(
                "-Repo '$Repo' is not the shape a hook produces: $($shape.why).",
                'A per-repo override is keyed by the "owner/name" of the origin remote - the slug lib/common.ps1''s',
                'Get-LwgRepoInfo computes for every hook from the working directory. A `repos` key of any other shape',
                'is not an override: it would be written, verified against itself, and read by nothing, which is the',
                'silent no-op this command refuses everywhere else.',
                'Pass -Repo owner/name (a remote URL is accepted and reduced), or -ThisRepo inside the repository.'
            )
            exit $script:Exit
        }
        if ($shape.slug -cne $Repo) { $repoNote += " (reduced from '$Repo')" }
        $Repo = $shape.slug

        # Reconciled against the keys ALREADY in the file, so the writer's -ceq
        # finds the same member every reader resolves. The file's spelling wins:
        # this command edits a file it does not own, and renaming an operator's
        # key is not a change it was asked to make.
        #
        # There is deliberately no branch for two `repos` keys differing only in
        # case. Windows PowerShell 5.1's ConvertFrom-Json REFUSES such a file
        # outright ("contains the duplicated keys"), so Get-LwgConfig falls back
        # to defaults and the BUILT-IN DEFAULTS refusal below catches it first.
        $repoKeys = @()
        try {
            if ($null -ne $cfg.repos) { $repoKeys = @($cfg.repos.PSObject.Properties | ForEach-Object { $_.Name }) }
        } catch { }
        $twin = @($repoKeys | Where-Object { $_ -ieq $Repo -and $_ -cne $Repo })
        if ($twin.Count -eq 1) {
            $repoNote += " (matched the existing repos key `"$($twin[0])`")"
            $Repo = $twin[0]
        }

        # --- and what NONE of the above can prove - #91 ----------------------
        # The shape check refuses a slug no hook could produce; the
        # reconciliation makes the writer and the readers agree on WHICH key.
        # Neither can say the key is one a hook will ever ASK for. 'owner/nmae'
        # has the right shape, matches nothing already in the file, and is
        # written and then "verified" by the exit-2 read-back at the bottom of
        # this file - which re-resolves the same key it just wrote, through the
        # same case-insensitive property lookup, and therefore agrees with
        # anything. #91 calls that verification structurally blind, and it is.
        #
        # -ThisRepo is not blind: it DERIVES the slug from the working directory
        # through the very Get-LwgRepoInfo a hook calls, so its key is one some
        # hook asks for by construction. So the question this asks is whether
        # the slug in hand is the one this working directory resolves to - true
        # for -ThisRepo by definition, and true for a -Repo typed inside the
        # repository it names.
        #
        # NOT A REFUSAL. Writing an override for a repository you are not
        # standing in is a legitimate thing to do - a second machine, a script,
        # a repo you are about to clone - and nothing here can tell that apart
        # from a typo. What is owed is the difference between CHECKED and TAKEN
        # ON TRUST, said once, in the block the preview prints too, where the
        # operator can still stop.
        $repoProven = $ThisRepo
        $hereSlug   = ''
        if (-not $repoProven) {
            try { $hereSlug = "$((Get-LwgRepoInfo -Path (Get-Location).Path).slug)" } catch { $hereSlug = '' }
            if (-not [string]::IsNullOrWhiteSpace($hereSlug) -and $hereSlug -ieq $Repo) { $repoProven = $true }
        }
    }

    $scope = if ([string]::IsNullOrWhiteSpace($Repo)) { 'global' } else { "repo $Repo" }

    Write-Output "LW-WATCHTOWER config v$($script:LwgVersion) - $ConfigPath"
    # WHICH FILES THE VALUES CAME FROM, BOTH OF THEM - #11. The table below is
    # resolved through Get-LwgConfig, which merges the override over these
    # defaults, so naming only config.json would credit every operator setting
    # to a file that does not hold it. An override that exists and cannot be
    # read is named too, because its values are being DISCARDED and a listing
    # that quietly showed the defaults instead would be the silent no-op this
    # command exists to refuse.
    $ovNote = if ("$($cfg._override_error)" -ne '') { "   override: IGNORED - $ovPath $($cfg._override_error)" }
              elseif ("$($cfg._override)" -ne '')   { "   override: $($cfg._override)" }
              elseif ($sdSplit.ambiguous)           { '   override: none IN THE DIRECTORY THIS RUN RESOLVED - see the note below' }
              else                                   { '   override: none - these are the shipped defaults' }
    Write-Output ("  source: {0}{3}   scope: {1}{2}" -f `
        $(if ($onDefaults) { 'BUILT-IN DEFAULTS (config.json is unreadable or invalid)' } else { 'config.json' }), $scope, $repoNote, $ovNote)
    # "override: none - these are the shipped defaults" over an armed gate is
    # half of #270: with two candidate directories this command read the one it
    # ranked highest, and the operator's real override was in the other. The
    # 'none' branch above is the one that had to change wording, because the
    # other two name a file and this one asserts an absence.
    # Only on the LISTING. A -Module run reaches the refusal below, which carries
    # the same block, and printing it twice in one run of a command whose whole
    # subject is saying things once, accurately, would be its own small joke.
    if ($sdSplit.ambiguous -and [string]::IsNullOrWhiteSpace($Module)) {
        Write-Output ''
        foreach ($l in $sdSplit.lines) { Write-Output ("  {0}" -f $l) }
    }

    $implemented = @(Get-LwgImplementedModules)
    $planned     = @(Get-LwgPlannedModules)
    $blocked     = @(Get-LwgBlockedModules)

    # --- what this command may NOT switch --------------------------------------
    # A module whose registry entry declares its own `switch` is flagged from
    # somewhere other than the `modules` block, and this command only ever writes
    # `modules.<name>`. Offering one here would write a key that Test-LwgModule
    # never reads - a switch wired to nothing, which is the exact defect this
    # plugin exists to catch, shipped by the command whose whole job is switches.
    # They are LISTED, so the operator can see the module and its real state, and
    # REFUSED for writing, with the command that does own the flag named.
    $ownSwitch = @($script:LwgSwitchModules)
    $switchable = @($script:LwgModules | Where-Object { $ownSwitch -notcontains $_ })

    # --- listing -------------------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($Module)) {
        Write-Output ''
        Write-Output '  MODULE                 KIND     BUILT        GLOBAL  OVERRIDE  EFFECTIVE'
        Write-Output '  ---------------------- -------- ------------ ------- --------- ---------'
        foreach ($m in @($script:LwgModules)) {
            $e = $script:LwgModuleRegistry[$m]
            $built = if ($e.blocked -eq $true) { 'BLOCKED' } elseif ($e.status -eq 'implemented') { 'yes' } else { 'no' }
            $g = Test-LwgModule -Name $m -Config $cfg
            $ov = '-'
            try {
                $v = $cfg.repos.$Repo.modules.$m
                # Format-LwgFlagState, not a bare [bool]: Test-LwgModule on the
                # very next line IGNORES a non-boolean override, so rendering it
                # as 'on' here would print an override the resolver does not
                # apply - the reporter and the reader disagreeing about one
                # value, in one table, two columns apart.
                if (-not [string]::IsNullOrWhiteSpace($Repo) -and $null -ne $v) { $ov = Format-LwgFlagState $v }
            } catch { }
            $eff = Test-LwgModule -Name $m -Config $cfg -Repo $Repo
            Write-Output ('  {0} {1} {2} {3} {4} {5}' -f `
                $m.PadRight(22), $e.kind.PadRight(8), $built.PadRight(12), `
                $(if ($g) { 'on' } else { 'off' }).PadRight(7), $ov.PadRight(9), `
                $(if ($eff) { 'on' } else { 'off' }))
        }
        Write-Output ''
        Write-Output '  EFFECTIVE is the flag a hook will read. It is still only an INTENTION:'
        Write-Output "  a module whose BUILT column is 'no' or 'BLOCKED' does nothing whatever its flag says."
        if ($ownSwitch.Count -gt 0) {
            Write-Output ''
            Write-Output "  NOT SWITCHABLE HERE ($($ownSwitch.Count)) - flagged from outside the ``modules`` block,"
            Write-Output '  and this command only writes modules.<name>. The state above is correct; the write is not'
            Write-Output '  ours to make.'
            foreach ($m in $ownSwitch) {
                $sw = $script:LwgModuleRegistry[$m].switch
                Write-Output ("    {0} - switch is {1}.{2}; use /lw-watchtower:{2} instead" -f $m, $sw.block, $sw.key)
            }
        }
        if ($planned.Count -gt 0) {
            Write-Output ''
            Write-Output "  Cannot be enabled here ($($planned.Count) declared but not implemented):"
            foreach ($p in $planned) {
                $why = if ($blocked -contains $p) { 'BLOCKED - the data it needs reaches no hook, so it will not be built as specified' } else { 'not written yet' }
                Write-Output "    $p - $why"
            }
        }
        Write-Output ''
        Write-Output '  To change one:  -Module <name> -On|-Off [-Repo owner/name | -ThisRepo] [-Apply]'
        Write-Output '  Without -Apply the effect is explained and nothing is written.'
        exit 0
    }

    # --- validate the request ------------------------------------------------
    $known = @($script:LwgModules)
    # -cnotcontains, NOT -notcontains - #92. PowerShell's -contains family is
    # case-INSENSITIVE, so the refusal below - whose own hint says "Module names
    # are case-sensitive" - was unreachable for the only input it describes.
    # 'Git_Hygiene' passed this gate, passed the registry lookup (an ordered
    # hashtable is case-insensitive too), printed a full plan under WHAT THIS
    # DOES, and then died in the JSON editor, which matches with -ceq: config.json
    # "has no modules.Git_Hygiene member ... its `modules` block has drifted from
    # the registry", pointing the operator at a doctor that reports healthy. A
    # typo reported as file drift. Without -Apply it was worse - PREVIEW ONLY and
    # exit 0, a change promised that could never be made.
    if ($known -cnotcontains $Module) {
        # Case-insensitive near-miss, because 'Git_Hygiene' is a typo and not a
        # request to invent a module.
        $near = @($known | Where-Object { $_ -ieq $Module })
        $hint = if ($near.Count -gt 0) { "did you mean '$($near[0])'? Module names are case-sensitive." } else { "known modules: $($known -join ', ')" }
        Write-Refusal @("'$Module' is not a module in the registry (lib/common.ps1, the source of truth).", $hint,
                        'A flag for a name the registry has never heard of is a switch wired to nothing, so it will not be created.')
        exit $script:Exit
    }

    # A real module, but not one whose flag lives where this command writes. This
    # sits AFTER the unknown-name check so a typo still reads as a typo, and
    # BEFORE anything is validated or written, so no path here can produce a
    # modules.<name> key that nothing reads.
    if ($ownSwitch -contains $Module) {
        $sw = $script:LwgModuleRegistry[$Module].switch
        Write-Refusal @(
            "'$Module' is a real module, but its flag is $($sw.block).$($sw.key) - NOT a key in the ``modules`` block.",
            "This command only ever writes modules.<name>. Writing modules.$Module here would create a flag that",
            'Test-LwgModule never reads: the module would carry two switches, one of them dead, and turning the dead',
            'one would look like it worked and change nothing.',
            '',
            "Use /lw-watchtower:$($sw.key) instead - it writes the key that is actually read, and states what the change does.",
            "Its current effective state is shown in the table printed by this command with no -Module argument."
        )
        exit $script:Exit
    }

    # --- REMOVED 4 September 2026: the context_injection refusal - #11 --------
    # There used to be a block here refusing `-Module context_injection -On/-Off`
    # outright. It is recorded rather than simply deleted, because the reason it
    # existed is the rule this command still enforces everywhere else and the
    # next person to add a module with its own reader needs to recognise it.
    #
    # WHY IT WAS HERE. lib/subagent_start.ps1 - the SubagentStart hook that
    # context_injection IS - read <pluginRoot>\config.json directly, by raw text
    # scan, and reached Get-LwgConfig only for a per-repo override. A flag
    # written to config.override.json was therefore honoured by the banner, by
    # /lw-watchtower:doctor and by this command's own read-back, and IGNORED by
    # the one reader the flag exists to switch: a write reported as verified and
    # honoured by nothing. That is the silent no-op this command refuses.
    #
    # WHY IT IS GONE. The hook reads the override. It runs its own two scanners
    # over config.override.json and escalates to Get-LwgConfig for every shape
    # they cannot read, so the two readers now agree and a write here takes
    # effect. The refusal outlived its reason by one wave only because the case
    # pinning it lived in a file another lane owned; both move here together.
    #
    # THE RULE ITSELF IS NOT REMOVED. A module whose hook reads config.json
    # behind Get-LwgConfig's back still must not be written by this command -
    # see the `switch` refusal above, which is the same principle for flags that
    # live outside the `modules` block. What changed is that no module in the
    # registry is in that state today.

    $n = @($On, $Off, $Clear | Where-Object { $_ }).Count
    if ($n -ne 1) {
        Write-Refusal @('pass exactly one of -On, -Off or -Clear.',
                        '-Clear removes a per-repo override so the module falls back to the global default; it needs -Repo or -ThisRepo.')
        exit $script:Exit
    }
    if ($Clear -and [string]::IsNullOrWhiteSpace($Repo)) {
        Write-Refusal @('-Clear removes a PER-REPO override and so needs -Repo <owner/name> or -ThisRepo.',
                        'There is nothing to clear globally: every module has a global flag, and the way to change it is -On or -Off.')
        exit $script:Exit
    }

    $entry  = $script:LwgModuleRegistry[$Module]
    $isImpl = ($entry.status -eq 'implemented')

    # THE REFUSAL. Enabling a name with no code behind it manufactures coverage
    # that does not exist.
    if ($On -and -not $isImpl) {
        $lines = @()
        if ($entry.blocked -eq $true) {
            $lines += "'$Module' is BLOCKED, not merely unbuilt: the data it needs reaches no hook, so it cannot be built as specified and no flag will make it run."
        } else {
            $lines += "'$Module' is declared in config.json but NOT IMPLEMENTED - there is no code behind the name, so setting it true would report coverage that does not exist."
        }
        $lines += "registry entry: kind '$($entry.kind)', status '$($entry.status)', impl $(if ($entry.impl) { $entry.impl } else { 'none' })"
        $lines += ''
        $lines += "The modules that cannot be enabled, and why ($($planned.Count) of $($known.Count)):"
        foreach ($p in $planned) {
            $why = if ($blocked -contains $p) { 'BLOCKED - no hook receives its data; it will not be built as specified' } else { 'not written yet' }
            $lines += "  $p - $why"
        }
        $lines += ''
        $enableHere = @($implemented | Where-Object { $switchable -contains $_ })
        $lines += "Enable-able HERE are the $($enableHere.Count) implemented modules whose flag is a ``modules`` key: $($enableHere -join ', ')"
        Write-Refusal $lines
        exit $script:Exit
    }

    if ($onDefaults) {
        Write-Refusal @(
            "$ConfigPath does not parse, so the plugin is running on BUILT-IN DEFAULTS and every operator ON/OFF choice is already being ignored.",
            'An override is merged over those defaults, not over a file nobody could read, so a write now would be recorded and then resolved against a config that is not the one you meant.',
            'Fix the JSON first - /lw-watchtower:doctor names this as the config-registry check.'
        )
        exit $script:Exit
    }

    # THE SAME REFUSAL FOR THE FILE THIS COMMAND ACTUALLY WRITES - #11. An
    # override that exists and does not parse is IGNORED by Get-LwgConfig, on
    # purpose, so a half-written settings file can neither arm a gate nor take
    # the plugin down. That makes it exactly the state a write must not land on:
    # the operator's real choices are in there, this command cannot read them
    # back, and replacing the text would destroy the evidence of what broke.
    if ("$($cfg._override_error)" -ne '') {
        Write-Refusal @(
            "$ovPath exists but $($cfg._override_error), so every operator ON/OFF choice recorded in it is already being ignored.",
            'Writing here would replace text this command cannot read back, and would destroy whatever else that file was holding.',
            "Fix or delete $ovPath and run this again. Deleting it is safe: it holds only overrides, and everything falls back to the shipped defaults without it."
        )
        exit $script:Exit
    }

    # AND THE REFUSAL FOR NOT KNOWING WHICH FILE A HOOK READS - #270. Two
    # lw-watchtower* directories under plugins\data - a marketplace install
    # beside what --plugin-dir produces - and this command, which is spawned
    # through Bash and is NOT handed $CLAUDE_PLUGIN_DATA, ranks them by most
    # recent write while every hook is simply told which one to use. The two can
    # differ, and then a write here is recorded, verified against itself, and
    # read by nobody: the same silent no-op every other refusal in this file
    # exists to prevent, arrived at through the directory rather than through
    # the key. bin\lwg-toggle.ps1 refuses the same condition in the same words.
    if ($sdSplit.ambiguous) {
        Write-Refusal (@(
            'this command cannot tell which config.override.json a hook reads, so it will not write one.',
            ''
        ) + $sdSplit.lines + @(
            '',
            'With CLAUDE_PLUGIN_DATA set, this command and every hook resolve the same directory by',
            'construction and this refusal cannot arise.'
        ))
        exit $script:Exit
    }

    # --- the effect, stated before anything is written -----------------------
    $want    = [bool]$On
    $curGlob = Test-LwgModule -Name $Module -Config $cfg
    $curEff  = Test-LwgModule -Name $Module -Config $cfg -Repo $Repo
    $curOv   = $null
    try { if (-not [string]::IsNullOrWhiteSpace($Repo)) { $curOv = $cfg.repos.$Repo.modules.$Module } } catch { }

    $action =
        if ($Clear)                                   { "remove the per-repo override for '$Module' on $Repo" }
        elseif ([string]::IsNullOrWhiteSpace($Repo))  { "set the GLOBAL flag for '$Module' to $($want.ToString().ToLower())" }
        else                                          { "set the $Repo override for '$Module' to $($want.ToString().ToLower())" }

    $newEff = if ($Clear) { $curGlob } else { $want }

    Write-Output ''
    Write-Output "WHAT THIS DOES: $action."
    Write-Output ''
    Write-Output "  module     $Module  (kind '$($entry.kind)', $(if ($isImpl) { "implemented in $($entry.impl)" } else { 'NOT implemented' }))"
    Write-Output "  now        global $(if ($curGlob) { 'on' } else { 'off' }); $(if ([string]::IsNullOrWhiteSpace($Repo)) { 'no repo scope' } elseif ($null -eq $curOv) { "no override for $Repo" } else { "override for $Repo is $(Format-LwgFlagState $curOv)$(if ($curOv -isnot [bool]) { ' (not a boolean, so it is not an override and the global stands)' })" }); effective $(if ($curEff) { 'on' } else { 'off' })"
    Write-Output "  after      effective $(if ($newEff) { 'on' } else { 'off' })$(if (-not [string]::IsNullOrWhiteSpace($Repo)) { " in $Repo only - every other repo is unaffected" })"
    Write-Output ''

    if ($newEff -eq $curEff) {
        Write-Output '  EFFECT: none. The effective value is already what you asked for.'
    } elseif (-not $isImpl) {
        Write-Output '  EFFECT: nothing observable. This module has no code behind it, so neither value changes any behaviour;'
        Write-Output '          the flag is recorded and read by nothing.'
    } else {
        if ($newEff) {
            Write-Output "  EFFECT: $($entry.impl) starts doing its work again on the next session."
        } else {
            Write-Output "  EFFECT: $($entry.impl) stops doing its work. The hook still fires and still costs a process;"
            Write-Output '          it returns early. Switching a module off does not unregister anything.'
        }
        Write-Output "  NOTE:   $($entry.note)"
    }

    # The two facts an operator most needs before turning something off, and the
    # two this plugin has already documented as easy to get wrong.
    if ($script:LwgGates -contains $Module -and -not $newEff) {
        Write-Output ''
        Write-Output '  THIS IS A GATE. Switching it off here disables the hook that EXPLAINS a denial.'
        Write-Output '  It does NOT touch permissions.deny in ~/.claude/settings.json, which is the layer'
        Write-Output '  that cannot fail open and which blocks the same commands by itself. If you mean to'
        Write-Output '  remove those too, that is a separate, deliberate edit - see /lw-watchtower:uninstall.'
    }
    if ($Module -eq 'self_health' -and -not $newEff) {
        Write-Output ''
        Write-Output "  The SessionStart self-check will not run at all, and the session will then report mode"
        Write-Output "  'unverified' rather than 'enforcing' or 'partial' - an unrun check must never read as a"
        Write-Output '  passed one. Nothing about the next session will have been verified.'
    }

    # Counts, and the one word the banner will use. The self-check cannot be run
    # from here, so its result is stated as an assumption rather than asserted.
    if ($isImpl -and $newEff -ne $curEff) {
        $activeNow = @(Get-LwgActiveModules -Config $cfg -Repo $Repo)
        $gatesNow  = @(Get-LwgActiveGates   -Config $cfg -Repo $Repo)
        $activeAfter = if ($newEff) { $activeNow.Count + 1 } else { $activeNow.Count - 1 }
        $gatesAfter  = if ($script:LwgGates -contains $Module) { if ($newEff) { $gatesNow.Count + 1 } else { $gatesNow.Count - 1 } } else { $gatesNow.Count }
        $selfAfter   = if ($Module -eq 'self_health') { $newEff } else { (Test-LwgModule -Name 'self_health' -Config $cfg -Repo $Repo) }
        $modeNow   = Get-LwgSessionMode -ActiveCount $activeNow.Count -GateCount $gatesNow.Count -ImplementedCount $implemented.Count -SelfHealthOn (Test-LwgModule -Name 'self_health' -Config $cfg -Repo $Repo) -SelfCheckOk $true
        $modeAfter = Get-LwgSessionMode -ActiveCount $activeAfter    -GateCount $gatesAfter    -ImplementedCount $implemented.Count -SelfHealthOn $selfAfter -SelfCheckOk $true
        Write-Output ''
        Write-Output ("  COUNTS: active {0} -> {1} of {2}; live gates {3} -> {4}; mode '{5}' -> '{6}'" -f `
            $activeNow.Count, $activeAfter, @($script:LwgModules).Count, $gatesNow.Count, $gatesAfter, $modeNow, $modeAfter)
        Write-Output "  (the mode assumes the SessionStart self-check passes; this script cannot run it)"
    }

    Write-Output ''
    Write-Output '  WHEN: hooks resolve the config on every invocation, so a change lands on the next hook'
    Write-Output '        event. The SessionStart banner and the mode word are computed once per session'
    Write-Output '        and will keep reporting the old ones until a new session starts.'

    # The one thing the canonicalisation above CANNOT establish - #91. Printed
    # here rather than at the write so the preview run and the applied run say
    # the same words in the same order, which is this file's own promise and is
    # asserted by tests\config_behaviour.ps1.
    if (-not [string]::IsNullOrWhiteSpace($Repo) -and -not $repoProven) {
        Write-Output ''
        Write-Output "  UNVERIFIED SCOPE: nothing here checks that `"$Repo`" is a repository you work in."
        if ([string]::IsNullOrWhiteSpace($hereSlug)) {
            Write-Output "        $((Get-Location).Path) resolves to no origin remote, so there is nothing to compare it with."
        } else {
            Write-Output "        $((Get-Location).Path) resolves to '$hereSlug', which is a different repository."
        }
        Write-Output '        The slug is the right SHAPE and is spelt the way config.json spells it, and neither of'
        Write-Output '        those can catch a slug that is simply the wrong repository - a transposition has both.'
        Write-Output '        The read-back after the write cannot catch it either: it re-resolves the key this run'
        Write-Output '        just wrote, so it agrees with anything. Run this from inside the repository with'
        Write-Output '        -ThisRepo to have the slug DERIVED from its origin remote rather than taken on trust.'
    }

    if (-not $Apply) {
        Write-Output ''
        Write-Output 'PREVIEW ONLY - nothing was written. Re-run the same command with -Apply to make the change.'
        exit 0
    }

    # --- the edit ------------------------------------------------------------
    $text = $file.text
    $new  = $null
    $what = ''
    $lit  = $want.ToString().ToLower()

    if ([string]::IsNullOrWhiteSpace($Repo)) {
        # AN ABSENT MEMBER IS THE NORMAL CASE NOW, not a drifted config - #11.
        # This used to refuse when modules.<name> was missing, because the file
        # it edited was config.json, where the config-registry check guarantees
        # the key exists. The override starts EMPTY and gains only what an
        # operator has actually set, so the member is created here exactly as
        # the repo-scoped branch below has always created its own.
        $m = Get-LwgJsonMemberPath -Text $text -Path @('modules', $Module)
        if ($m.found) {
            $old = $text.Substring($m.value_start, $m.value_end - $m.value_start)
            $new = $text.Substring(0, $m.value_start) + $lit + $text.Substring($m.value_end)
            $what = "modules.$Module : $old -> $lit"
        } else {
            $modsM = Get-LwgJsonMemberPath -Text $text -Path @('modules')
            if ($modsM.found -and $text[$modsM.value_start] -eq '{') {
                $new  = Add-LwgJsonMember -Text $text -ObjStart $modsM.value_start -Fragment ("`"$Module`": $lit")
                $what = "modules: added `"$Module`": $lit"
            } else {
                $rootM = $text.IndexOf('{')
                if ($rootM -lt 0) {
                    Write-Refusal @("$ovPath holds no JSON object to write into.")
                    exit $script:Exit
                }
                $new  = Add-LwgJsonMember -Text $text -ObjStart $rootM -Fragment ("`"modules`": { `"$Module`": $lit }")
                $what = "added modules { `"$Module`": $lit }"
            }
        }
    }
    else {
        # CREATED IF ABSENT, same reasoning as the global branch above: the
        # override document starts empty, so it carries no `repos` object until
        # this command puts one there.
        $reposM = Get-LwgJsonMemberPath -Text $text -Path @('repos')
        if (-not $reposM.found -or $text[$reposM.value_start] -ne '{') {
            if ($Clear) {
                Write-Output ''
                Write-Output "  Nothing to clear: $ovPath records no per-repo override at all, so '$Module' already falls through to the global default."
                exit 0
            }
            $rootR = $text.IndexOf('{')
            if ($rootR -lt 0) {
                Write-Refusal @("$ovPath holds no JSON object to write into.")
                exit $script:Exit
            }
            $text   = Add-LwgJsonMember -Text $text -ObjStart $rootR -Fragment '"repos": {}'
            $reposM = Get-LwgJsonMemberPath -Text $text -Path @('repos')
            if (-not $reposM.found -or $text[$reposM.value_start] -ne '{') {
                Write-Refusal @("a repos object could not be created in $ovPath; nothing was written.")
                exit $script:Exit
            }
        }
        $repoObj = Find-LwgJsonMember -Text $text -ObjStart $reposM.value_start -Key $Repo

        if ($Clear) {
            if (-not $repoObj.found) {
                Write-Output ''
                Write-Output "  Nothing to clear: $ovPath has no `"$Repo`" entry, so '$Module' already falls through to the global default."
                exit 0
            }
            $modsM = Find-LwgJsonMember -Text $text -ObjStart $repoObj.value_start -Key 'modules'
            if (-not $modsM.found -or -not (Find-LwgJsonMember -Text $text -ObjStart $modsM.value_start -Key $Module).found) {
                Write-Output ''
                Write-Output "  Nothing to clear: `"$Repo`" carries no override for '$Module'."
                exit 0
            }
            $cut = Remove-LwgJsonMember -Text $text -ObjStart $modsM.value_start -Key $Module
            if (-not $cut.ok) { Write-Refusal @('the override could not be located for removal.'); exit $script:Exit }
            $new = $cut.text
            $what = "repos.`"$Repo`".modules: removed $($cut.removed)"
        }
        elseif ($repoObj.found) {
            $modsM = Find-LwgJsonMember -Text $text -ObjStart $repoObj.value_start -Key 'modules'
            if ($modsM.found -and $text[$modsM.value_start] -eq '{') {
                $flag = Find-LwgJsonMember -Text $text -ObjStart $modsM.value_start -Key $Module
                if ($flag.found) {
                    $old = $text.Substring($flag.value_start, $flag.value_end - $flag.value_start)
                    $new = $text.Substring(0, $flag.value_start) + $lit + $text.Substring($flag.value_end)
                    $what = "repos.`"$Repo`".modules.$Module : $old -> $lit"
                } else {
                    $new = Add-LwgJsonMember -Text $text -ObjStart $modsM.value_start -Fragment ("`"$Module`": $lit")
                    $what = "repos.`"$Repo`".modules: added `"$Module`": $lit"
                }
            } else {
                $new = Add-LwgJsonMember -Text $text -ObjStart $repoObj.value_start -Fragment ("`"modules`": { `"$Module`": $lit }")
                $what = "repos.`"$Repo`": added modules { `"$Module`": $lit }"
            }
        }
        else {
            $frag = "`"$Repo`": {" + "`n" + "  `"modules`": {" + "`n" + "    `"$Module`": $lit" + "`n" + '  }' + "`n" + '}'
            $new = Add-LwgJsonMember -Text $text -ObjStart $reposM.value_start -Fragment $frag
            $what = "repos: added `"$Repo`" with modules.$Module = $lit"
        }
    }

    if ([string]::IsNullOrWhiteSpace($new)) {
        Write-Refusal @("the edit could not be constructed; $ovPath was not touched.")
        exit $script:Exit
    }
    if ($new -eq $text) {
        Write-Output ''
        Write-Output '  No textual change was needed - the file already says exactly this.'
        exit 0
    }
    # The last gate before the write. A surgical edit that produced invalid JSON
    # would take config.json out of service silently: Get-LwgConfig fails open to
    # defaults and nothing would report an error.
    if (-not (Test-LwgJsonParses -Text $new)) {
        Write-Refusal @("the edited text does not parse as JSON, so it was NOT written. This is a bug in this script; $ovPath is untouched.")
        exit $script:Exit
    }

    # THE SEED, HERE AND NOWHERE EARLIER. Every refusal above must leave the
    # disk exactly as it found it, and creating an empty override on a run that
    # then prints "REFUSED - nothing was written" would make that sentence false
    # about a file which did not exist a moment before. The bytes written are
    # '{}' - the same text $new was built from - so the SHA read back belongs to
    # them, and Save-LwgTextFile's changed-under-us check still means what it
    # says.
    if (-not [IO.File]::Exists($ovPath)) {
        [void](Get-LwgStateDir)
        [IO.File]::WriteAllText($ovPath, '{}', [Text.UTF8Encoding]::new($false))
        $file = Read-LwgTextFile -Path $ovPath
        if (-not $file.ok) {
            Write-Refusal @("$ovPath could not be created or read back - $($file.error)")
            exit $script:Exit
        }
    }
    $save = Save-LwgTextFile -Path $ovPath -Text $new -ExpectedSha $file.sha -Bom $file.bom -BackupTag 'lwg-config'
    if (-not $save.ok) {
        Write-Refusal @("the write did not happen: $($save.reason)")
        exit $script:Exit
    }

    Write-Output ''
    Write-Output 'WRITTEN.'
    Write-Output "  change:  $what"
    Write-Output "  backup:  $($save.backup)"

    # --- prove it took ------------------------------------------------------
    # Re-read from disk and re-resolve through the same helper a hook calls. An
    # editor that reports success without changing the effective value is the
    # silent no-op this plugin exists to catch, so the claim is checked rather
    # than assumed.
    $after = Get-LwgConfig -Path $ConfigPath
    if ($after._source -ne 'file') {
        Write-Output ''
        Write-Output "FAULT: after the write, $ConfigPath no longer parses. The backup above is the file as it was."
        exit 2
    }
    $eff = Test-LwgModule -Name $Module -Config $after -Repo $Repo
    Write-Output "  verify:  re-read from disk; Test-LwgModule('$Module'$(if ($Repo) { ", repo $Repo" })) now returns $(if ($eff) { 'on' } else { 'off' })"
    # What that line does NOT say, said - #91. Under an unproven -Repo the
    # read-back resolves the key this run just wrote and so cannot disagree with
    # it; leaving 'verify:' as the last word would present a tautology as a
    # check. The UNVERIFIED SCOPE block above has already explained it, so this
    # is one line and a pointer, not the explanation again.
    if (-not [string]::IsNullOrWhiteSpace($Repo) -and -not $repoProven) {
        Write-Output "           (that resolves the key this run wrote; it does not show any hook asks for `"$Repo`" - see UNVERIFIED SCOPE above)"
    }
    if ($eff -ne $newEff) {
        Write-Output ''
        Write-Output "FAULT: the file was written but the EFFECTIVE value is $(if ($eff) { 'on' } else { 'off' }), not the $(if ($newEff) { 'on' } else { 'off' }) that was asked for."
        Write-Output '       Do not treat this as done. The backup above is the file as it was.'
        exit 2
    }
    exit 0

} catch {
    Write-Output ''
    Write-Output "LW-WATCHTOWER config could not complete: $($_.Exception.Message)"
    Write-Output 'Nothing above should be read as a description of what the configuration now contains.'
    exit 3
}
