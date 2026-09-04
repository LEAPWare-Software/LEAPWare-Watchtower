#requires -version 5
<#
  LW-WATCHTOWER update - fetch what is new, say what it would change, then check the
  plugin still works.

      powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-update.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-update.ps1 -Apply

  Backs /lw-watchtower:update. Without -Apply it fetches and reports and merges
  nothing; -Apply runs `git pull --ff-only`. The plugin is loaded through a
  directory junction, so `git pull` IS the update mechanism - there is no
  install step to re-run and no cache to refresh.

  WHAT IT REFUSES TO DO

    * It will not pull over uncommitted work. No stash, no reset, no checkout -
      it says the tree is dirty and stops. An update command that quietly moves
      somebody's changes is worse than no update command.
    * It will not merge. --ff-only or nothing: a merge commit made by a tool
      nobody was watching is a change to history that nobody chose.
    * It will not call a failed or timed-out git command a clean result. Every
      subprocess here is bounded and its failure is reported as UNKNOWN.

  WHAT NEEDS RE-APPROVAL AFTERWARDS is the part a plain `git pull` does not tell
  you, and it is why this exists rather than a one-line instruction to pull:

    hooks/hooks.json          hook commands are read at SESSION START. A changed
                              registration does not take effect until the next
                              session, and a NEW command may prompt for approval.
    config.json               module flags travel with the repo. A pull can turn
                              a module on or off underneath you; the exact flag
                              differences are printed.
    statusline/statusline.ps1 the installed status line is a COPY at
                              ~/.claude/statusline.ps1. git does not update it,
                              nothing on this machine compares them, and a pull
                              silently leaves the live one stale.
    commands/                 a new slash command appears only in a new session.
                              output-styles/ was named here too until that
                              directory was deleted; there is no style to report.

  Exit codes:

      0  up to date, or updated cleanly, with nothing needing attention
      1  REFUSED - dirty tree, detached HEAD, no upstream, or -Offline together
         with -Apply; nothing was changed
      2  finished, with caveats - something needs re-approval, a check could not
         be made (no network, no git, doctor warnings), the doctor FAILED on a
         tree this run did not change, or a pull was killed mid-operation and
         the tree state is UNKNOWN
      3  this script could not complete
      4  the doctor FAILED after a pull THIS RUN ACTUALLY MADE. It is gated on
         the pull because "after the update" is a claim about causation, and it
         used to be selected from the doctor's code alone - so a check-only run
         and a refused run both returned it.
#>

param(
    # Actually pull. Without it this fetches and reports only.
    [switch]$Apply,

    # Do not touch the network at all. Everything network-derived then reports
    # UNKNOWN rather than being quietly skipped.
    #
    # IT IS REFUSED TOGETHER WITH -Apply, rather than silently broken by it:
    # `git pull` fetches, so -Apply cannot honour this flag. Section 5 says so
    # and merges nothing. Until 3 August 2026 $Offline was consulted in exactly
    # one place - the reporting fetch - and section 5 never looked at it.
    [switch]$Offline,

    # Skip the post-update health check.
    [switch]$SkipDoctor,

    [int]$TimeoutMs = 8000,

    # Test override for the checkout to operate on.
    [string]$Root
)

$ErrorActionPreference = 'Stop'

$script:Rows  = New-Object System.Collections.ArrayList
$script:Warn  = 0
$script:Fail  = 0

function Add-Row {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][ValidateSet('OK', 'WARN', 'FAIL', 'INFO')][string]$Status,
        [Parameter(Mandatory = $true)][string]$Detail
    )
    if ($Status -eq 'WARN') { $script:Warn++ }
    if ($Status -eq 'FAIL') { $script:Fail++ }
    [void]$script:Rows.Add([pscustomobject]@{ Id = $Id; Status = $Status; Detail = $Detail })
}

try {
    $pluginRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $pluginRoot 'lib\common.ps1')
    . (Join-Path $PSScriptRoot 'lwg-cmdlib.ps1')

    if ([string]::IsNullOrWhiteSpace($Root)) { $Root = $pluginRoot }

    # CLAUDE CODE'S CONFIGURATION DIRECTORY, RESOLVED ONCE FOR THIS RUN.
    #
    # The three paths this command composes - the skills junction it compares
    # $Root against, the live status line it hashes, and the re-approval note
    # that names it - were all built from $env:USERPROFILE and a literal
    # `.claude`. On a machine that sets CLAUDE_CONFIG_DIR, all three named a
    # directory the CLI does not use, so section 0 reported "no junction at ..."
    # about an install that is there, and the status-line row reported an
    # absence about a file that exists. lib\common.ps1's Get-LwgClaudeHomeInfo
    # is the resolver and the precedence is argued there.
    #
    # $null is possible - a machine with neither variable - and is carried as
    # $null rather than composed onto, so a row can say "could not be resolved"
    # instead of throwing over a path it invented.
    $homeInfo = $null
    try { $homeInfo = Get-LwgClaudeHomeInfo } catch { }
    if ($null -eq $homeInfo) { $homeInfo = @{ path = $null; source = 'unresolved'; exists = $false; raw = $null } }
    $claudeHome = [string]$homeInfo.path

    # ---------------------------------------------------------------------
    # WHICH FILE IS THE LIVE STATUS LINE? (#77)
    # ---------------------------------------------------------------------
    # THE ROW BELOW USED TO ASSUME THE ANSWER AND REPORT AN ABSENCE ABOUT IT.
    # Section 4's drift row and the re-approval note in Get-Needs both named
    # <config root>\statusline.ps1 - the target bin\lwg-setup.ps1 writes in its
    # DEFAULT copy mode - and nothing else. An operator whose status line is
    # wired through the skills junction, which is the other mode the installer
    # offers, therefore got:
    #
    #     [INFO] statusline   no ...\.claude\statusline.ps1 - the HH segment is
    #                         not installed on this machine
    #
    # about a status line that IS installed, IS this plugin's, and HAD drifted
    # from the repo copy. The one state the row exists to catch is the one state
    # it could not see, and the re-approval note told the operator to re-copy a
    # file that was not the live one.
    #
    # THE TARGET IS PULLED OUT OF settings.json, THE SAME WAY CHECK 7 OF
    # bin\lwg-doctor.ps1 PULLS IT OUT: the first token in statusLine.command
    # that ends in .ps1, quoted or bare. That check was already right about this
    # and this file was already wrong, which is two readers of one settings key
    # disagreeing about which file the operator is running - the divergence this
    # plugin is named for. The regex is spelled the same way deliberately; if it
    # changes there, it changes here.
    #
    # THE DEFAULT IS A FALLBACK, NOT THE ANSWER. It applies only when no
    # statusLine.command is set at all, and the row then says which of the two it
    # is talking about, because "the file you configured has drifted" and "the
    # file you would have configured is not there" are different sentences and
    # the operator acts on them differently.
    #
    # NOT A HEALTH CHECK. Whether the wired target is this plugin's file is
    # check 7's question and it answers it properly, with provenance before
    # drift. This row compares bytes and says what it compared.
    $slWired    = ''
    $slSource   = 'none'
    $slSettings = '<no configuration directory>'
    if (-not [string]::IsNullOrWhiteSpace($claudeHome)) {
        $slSettings = Join-Path $claudeHome 'settings.json'
        try {
            if (Test-Path -LiteralPath $slSettings) {
                # PS 5.1's Get-Content -Raw keeps a UTF-8 BOM, which
                # ConvertFrom-Json rejects. Settings files written by other tools
                # do carry one. Same TrimStart as check 7.
                $slRaw = (Get-Content -LiteralPath $slSettings -Raw -ErrorAction Stop).TrimStart([char]0xFEFF)
                $slCmd = [string](($slRaw | ConvertFrom-Json).statusLine.command)
                if (-not [string]::IsNullOrWhiteSpace($slCmd)) {
                    foreach ($tok in ([regex]::Matches($slCmd, '"([^"]+)"|(\S+)'))) {
                        $tv = if ($tok.Groups[1].Success) { $tok.Groups[1].Value } else { $tok.Groups[2].Value }
                        if ($tv -match '\.ps1$') { $slWired = $tv; $slSource = 'command'; break }
                    }
                    # A statusLine.command that names no .ps1 is a configured
                    # status line this row cannot identify. It is NOT the default
                    # case: falling back would compare a file the operator is
                    # demonstrably not running. Reported as its own state.
                    if ($slSource -ne 'command') { $slSource = 'unidentified'; $slWired = $slCmd }
                }
            }
        } catch {
            # A settings.json that will not parse is not evidence about the
            # status line either way, and section 4 is not the place that
            # reports it - check 7 is.
            $slSource = 'unreadable'
        }
    }

    function Git {
        param([string[]]$A, [int]$Ms = $TimeoutMs)
        return (Invoke-LwgCmdProcess -File 'git' -ProcArgs $A -WorkDir $Root -TimeoutMs $Ms)
    }

    # THE PATHS GIT PRINTS ARE REPO-ROOT-RELATIVE AND THE PAYLOAD IS NO LONGER AT
    # THE REPO ROOT. Every `git diff --name-only` below runs with -WorkDir $Root
    # and NO --relative, so git prints `lw-watchtower/hooks/hooks.json` where the
    # comparisons underneath were written against `hooks/hooks.json`.
    #
    # `git status --porcelain=v2` IS THE EXCEPTION AND IT IS MEASURED, not
    # assumed: it honours status.relativePaths, which defaults to true, so it
    # prints paths relative to -WorkDir - i.e. already payload-relative. The one
    # comparison against $dirtyPaths therefore does NOT take this prefix, and the
    # long version of that measurement is beside it. NOTHING GOES RED WHEN THAT STOPS
    # MATCHING: the operator simply stops being told that a hooks change needs a
    # new session, that the status-line copy is now stale, or that module flags
    # moved - the advisories just quietly stop. That is the failure this block
    # exists to prevent.
    #
    # DERIVED, NOT HARDCODED. A literal 'lw-watchtower/' here would be a tenth
    # place for the directory name to be wrong, and wrong on any tree that ever
    # renames it; --show-prefix asks the repository that is actually checked out.
    # It returns '' when $Root IS the repo root - the shape before the
    # restructure, and any future re-flattening - so the comparisons below are
    # correct in both.
    $script:PathPrefix = ''
    $spx = Git @('rev-parse', '--show-prefix')
    if ($spx.ok) {
        $script:PathPrefix = (($spx.out -split "`r?`n" | Where-Object { $_ }) -join '').Trim()
        if ($script:PathPrefix -and -not $script:PathPrefix.EndsWith('/')) { $script:PathPrefix += '/' }
    }

    Write-Output "LW-WATCHTOWER update v$($script:LwgVersion) - $(if ($Apply) { 'APPLY (git pull --ff-only)' } else { 'CHECK ONLY - nothing will be merged' })"
    Write-Output "  checkout: $Root"

    # ---------------------------------------------------------------------
    # 0. is this checkout even the one Claude Code loads?
    # ---------------------------------------------------------------------
    # A worktree is a real git checkout and pulls perfectly happily, and updating
    # one that the junction does not point at is an update nothing loads. Said
    # first, because it changes what every row below means.
    $name = Get-LwgPluginName
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'lw-watchtower' }
    $link = if ([string]::IsNullOrWhiteSpace($claudeHome)) { '' } else { Join-Path $claudeHome "skills\$name" }
    $linkTarget = ''
    try {
        $li = Get-Item -LiteralPath $link -Force -ErrorAction Stop
        $linkTarget = @($li.Target)[0]
    } catch { }
    # ARRIVING THROUGH THE JUNCTION IS THE INTENDED ROUTE, AND IT USED TO WARN.
    #
    # $Root is $PSScriptRoot's parent, which is NOT canonicalised through reparse
    # points, and the row compared it against the junction's TARGET as text.
    # Those two are different strings by definition - that is what a junction
    # is - so the route commands/update.md actually uses, where
    # CLAUDE_PLUGIN_ROOT is the junction path, produced a WARN saying this is not
    # the checkout Claude Code loads. It is the same directory. The WARN forces
    # exit 2 and commands/update.md told the model to report a correct, completed
    # update as landing in the wrong place.
    #
    # So the link path is tested FIRST, on its own: a $Root at or under $link is
    # the junction route and is right by construction, whatever Target says.
    #
    # WHAT IS STILL NOT RESOLVED, said here rather than left to be discovered:
    # any OTHER spelling of the same directory - a SUBST drive, an 8.3 short
    # name, a UNC path - still fails both tests. Deciding that needs file
    # IDENTITY (volume serial + file index), which needs a P/Invoke this script
    # does not carry, or a write into the operator's checkout, which a read-only
    # check must not make. That case now reports what it could not establish
    # instead of asserting the checkout is wrong.
    $viaLink = (-not [string]::IsNullOrWhiteSpace($link)) -and (Test-LwgPathUnder -Path $Root -Root $link)
    if ($viaLink) {
        Add-Row -Id 'loaded-copy' -Status 'OK' -Detail "this checkout was invoked through $link, which is the path Claude Code loads$(if ($linkTarget) { " (it points at $linkTarget)" } else { '' })"
    } elseif ([string]::IsNullOrWhiteSpace($link)) {
        Add-Row -Id 'loaded-copy' -Status 'INFO' -Detail 'no configuration directory could be resolved - neither CLAUDE_CONFIG_DIR nor USERPROFILE holds a value - so whether a skills junction exists was not established. This is not evidence that there is none.'
    } elseif ([string]::IsNullOrWhiteSpace($linkTarget)) {
        Add-Row -Id 'loaded-copy' -Status 'INFO' -Detail "no junction at $link - this checkout may or may not be what Claude Code loads; a marketplace install is a separate copy and is not updated by git"
    } elseif (Test-LwgPathUnder -Path $Root -Root $linkTarget) {
        Add-Row -Id 'loaded-copy' -Status 'OK' -Detail "$link -> $linkTarget, and this checkout is inside it"
    } else {
        Add-Row -Id 'loaded-copy' -Status 'WARN' -Detail "NOT RECONCILED: the junction $link points at $linkTarget, and this checkout is $Root. Neither is a prefix of the other. If they are different directories, updating here changes nothing Claude Code loads and you want $linkTarget instead. If they are the same directory under another spelling - a SUBST drive, an 8.3 name, a UNC path - this row cannot tell, and it is a false alarm. Compare them yourself before acting on it."
    }

    # ---------------------------------------------------------------------
    # 1. git, and a repo to work in
    # ---------------------------------------------------------------------
    $v = Git @('--version') 2000
    $why = Get-LwgToolReport -Tool 'git' -Result $v
    if ($why) {
        Add-Row -Id 'git' -Status 'FAIL' -Detail $why
        Write-Output ''
        foreach ($r in $script:Rows) { Write-Output ("  [{0}] {1}  {2}" -f $r.Status, $r.Id.PadRight(12), $r.Detail) }
        Write-Output ''
        Write-Output 'Nothing was fetched, compared or updated. Without git there is no update mechanism at all;'
        Write-Output 'this is not the same as being up to date.'
        exit 2
    }
    Add-Row -Id 'git' -Status 'OK' -Detail (($v.out -split "`r?`n")[0])

    $info = Get-LwgRepoInfo -Path $Root
    if (-not $info.gitdir) {
        Add-Row -Id 'repo' -Status 'FAIL' -Detail "$Root is not inside a git repository, so there is nothing to pull"
        Write-Output ''
        foreach ($r in $script:Rows) { Write-Output ("  [{0}] {1}  {2}" -f $r.Status, $r.Id.PadRight(12), $r.Detail) }
        exit 1
    }
    Add-Row -Id 'repo' -Status 'OK' -Detail "$($info.root)$(if ($info.slug) { " ($($info.slug))" } else { ' (no origin remote slug)' })"

    # ---------------------------------------------------------------------
    # 2. the working tree, before anything is fetched
    # ---------------------------------------------------------------------
    $st = Git @('status', '--porcelain=v2', '--branch')
    $why = Get-LwgToolReport -Tool 'git status' -Result $st
    if ($why) {
        Add-Row -Id 'worktree' -Status 'FAIL' -Detail "$why - UNKNOWN, and an unknown tree is not a clean one, so nothing will be pulled"
        Write-Output ''
        foreach ($r in $script:Rows) { Write-Output ("  [{0}] {1}  {2}" -f $r.Status, $r.Id.PadRight(12), $r.Detail) }
        exit 1
    }
    $branch = ''; $upstream = ''; $ahead = 0; $behind = 0; $dirty = 0; $detached = $false
    # THE PATHS, NOT JUST THE COUNT (#11).
    #
    # This loop counted non-`#` lines and threw the paths away, so the refusal
    # below read "N uncommitted change(s)" and named nothing. Two measured
    # consequences, both of which make an operator distrust the wrong thing:
    #
    #   * config.json IS TRACKED and /lw-watchtower:config and the toggle
    #     commands write into it, so arming a gate dirties the checkout and the
    #     next update refuses. The operator is told they have uncommitted work.
    #     They do not; the plugin wrote it. #11 is the fix for the WRITE and it
    #     needs a decision above this file (see its comment thread); naming the
    #     file is the half that belongs here, and #11's own "what done looks
    #     like" asks for it as the minimum.
    #   * a test suite that left something in the tree does the same thing -
    #     #214, measured today, where `? Microsoft/` from tests\setup_merge.ps1
    #     refused an update with "1 uncommitted change(s)".
    #
    # PORCELAIN v2 PATH POSITIONS: `1 <xy> ... <path>` and `2 <xy> ... <path><TAB><orig>`
    # for tracked entries, `u ...` for unmerged, `? <path>` for untracked. The
    # path is the LAST field in all of them except a rename, whose original path
    # follows a TAB - so the tab is split off first and the remainder taken from
    # the last space. Quoting is left exactly as git wrote it: a path git chose
    # to quote is a path with something in it worth seeing quoted.
    $dirtyPaths = @()
    foreach ($l in @($st.out -split "`r?`n")) {
        if ($l -like '# branch.head*')  { $branch = ($l -split ' ')[2]; if ($branch -eq '(detached)') { $detached = $true } ; continue }
        if ($l -like '# branch.upstream*') { $upstream = ($l -split ' ')[2]; continue }
        if ($l -like '# branch.ab*')    {
            $p = $l -split ' '
            # `# branch.ab +2 -5` - the signs are direction markers, not
            # magnitudes, and keeping the minus made `behind` negative and every
            # `-gt 0` test below silently false: an out-of-date checkout that
            # reported nothing incoming.
            $ahead  = [Math]::Abs([int]($p[2] -replace '[^0-9]', ''))
            $behind = [Math]::Abs([int]($p[3] -replace '[^0-9]', ''))
            continue
        }
        if ($l -and $l -notlike '#*') {
            $dirty++
            $head = ($l -split "`t")[0]
            $sp   = $head.LastIndexOf(' ')
            $p    = if ($sp -ge 0) { $head.Substring($sp + 1) } else { $head }
            if (-not [string]::IsNullOrWhiteSpace($p)) { $dirtyPaths += $p }
        }
    }
    if ($detached) {
        Add-Row -Id 'worktree' -Status 'FAIL' -Detail 'HEAD is detached. A pull here would move nothing you could name later; check out a branch first.'
    } elseif ($dirty -gt 0) {
        # NAMED, AND CAPPED. A tree with fifty changed files does not need fifty
        # paths on one row to make the point; it needs enough to recognise
        # whether the work is the operator's. The cap says how many it did not
        # print rather than trailing off.
        $shown = @($dirtyPaths | Select-Object -First 8)
        $more  = $dirtyPaths.Count - $shown.Count
        $list  = if ($shown.Count -gt 0) { ' ' + ($shown -join ', ') + $(if ($more -gt 0) { " (and $more more)" } else { '' }) } else { '' }
        # config.json IS STILL CALLED OUT BY NAME, AND THE SENTENCE NOW SAYS THE
        # OPPOSITE - #234.
        #
        # It landed in #220 saying this plugin had written the file: at that
        # time /lw-watchtower:config and the toggle commands did write it, so an
        # operator meeting a dirty checkout after arming a gate needed telling
        # that the change was not theirs. PR #229 moved every one of those
        # writes out of the repository - config.json is the SHIPPED DEFAULTS and
        # nothing in this tree writes it, operator settings go to
        # config.override.json under the state directory - and the sentence went
        # on saying it anyway. So the only way this file can be dirty today is
        # that a person edited it, and the row was telling that person their own
        # edit was probably the plugin's and "may not be yours to commit". An
        # operator who believed it would discard their own work as residue.
        #
        # A REPORT THAT STATES A MECHANISM THAT IS NO LONGER RUNNING is the
        # exact class of defect this plugin exists to catch, and it was pointed
        # at its own updater for a day. Worth the paragraph.
        #
        # NAMING THE PATH IS KEPT, because that half was always useful and is
        # escape route 2b on #11. What is replaced is the ATTRIBUTION, and the
        # useful half now runs the other way: this is the one file in a dirty
        # list that the operator can be told, positively, that no command in
        # this plugin touched.
        # AND THE PREFIX IS NOT APPLIED HERE, WHICH IS NOT AN OVERSIGHT. It was
        # applied here by PR #236 along with the eight comparisons that do need
        # it, and that made this sentence unreachable on the shape it was added
        # for. Measured, git 2.53.0, one repository, one dirty file at
        # `sub/config.json`:
        #
        #   git -C <repo>     status --porcelain=v2   ->  sub/config.json
        #   git -C <repo/sub> status --porcelain=v2   ->  config.json
        #   git -C <repo/sub> status --porcelain      ->  sub/config.json
        #   git -C <repo/sub> diff --name-only        ->  sub/config.json
        #
        # `status --porcelain=v2` honours status.relativePaths, which defaults
        # to true, so it prints paths relative to the CURRENT DIRECTORY - and
        # every call here passes -WorkDir $Root, which is the payload directory.
        # `--porcelain` (v1) forces the setting off, and `diff --name-only` is
        # repo-root-relative always, which is why $changed below DOES need the
        # prefix and $dirtyPaths does not. The comment at the derivation says
        # both are repo-root-relative; that half is wrong and this is the
        # correction.
        #
        # BOTH SPELLINGS ARE ACCEPTED rather than the bare one, because
        # status.relativePaths is an operator setting and a machine that has
        # turned it off gets the repo-root-relative form here. Testing for both
        # costs nothing and is right on either.
        $own = ''
        if ($dirtyPaths -contains 'config.json' -or
            $dirtyPaths -contains ($script:PathPrefix + 'config.json')) {
            $own = ' config.json is the SHIPPED DEFAULTS and no command in this plugin writes it - /lw-watchtower:config and the toggle commands write config.override.json under the state directory, outside this checkout. So this change is somebody''s edit in this repository, not plugin residue, and it is yours to keep or discard.'
        }
        Add-Row -Id 'worktree' -Status 'FAIL' -Detail "$dirty uncommitted change(s) on ${branch}:$list. This command does not stash, reset or check out anything - commit or set them aside first.$own"
    } else {
        Add-Row -Id 'worktree' -Status 'OK' -Detail "clean on $branch$(if ($upstream) { ", tracking $upstream" } else { ', with NO upstream' })"
    }
    if ([string]::IsNullOrWhiteSpace($upstream)) {
        Add-Row -Id 'upstream' -Status 'FAIL' -Detail "branch $branch tracks nothing, so there is no 'latest' to pull. Set one with: git branch --set-upstream-to origin/<branch>"
    }

    # ---------------------------------------------------------------------
    # 3. fetch - the one network call
    # ---------------------------------------------------------------------
    $fetched = $false
    if ($Offline) {
        Add-Row -Id 'fetch' -Status 'WARN' -Detail '-Offline: no fetch was made, so "behind" below is whatever the last fetch left and may be stale. This is not evidence of being up to date.'
    } elseif ([string]::IsNullOrWhiteSpace($upstream)) {
        Add-Row -Id 'fetch' -Status 'WARN' -Detail 'skipped - nothing to fetch from without an upstream'
    } else {
        $f = Git @('fetch', '--quiet') ([Math]::Max($TimeoutMs, 15000))
        $why = Get-LwgToolReport -Tool 'git fetch' -Result $f
        if ($why) {
            Add-Row -Id 'fetch' -Status 'WARN' -Detail "$why - UNKNOWN whether anything is new. Offline, or the remote is unreachable."
        } else {
            $fetched = $true
            Add-Row -Id 'fetch' -Status 'OK' -Detail "fetched from $upstream in $($f.ms) ms"
            $st2 = Git @('status', '--porcelain=v2', '--branch')
            if ($st2.ok) {
                foreach ($l in @($st2.out -split "`r?`n")) {
                    if ($l -like '# branch.ab*') {
                        $p = $l -split ' '
                        $ahead  = [Math]::Abs([int]($p[2] -replace '[^0-9]', ''))
                        $behind = [Math]::Abs([int]($p[3] -replace '[^0-9]', ''))
                    }
                }
            }
        }
    }
    Add-Row -Id 'position' -Status $(if ($behind -gt 0) { 'INFO' } else { 'OK' }) `
            -Detail "$behind commit(s) behind $upstream, $ahead ahead$(if ($behind -eq 0 -and $fetched) { ' - up to date' } elseif (-not $fetched) { ' (from a possibly stale fetch)' } else { '' })"

    # ---------------------------------------------------------------------
    # 4. what would change, and what that costs in re-approval
    # ---------------------------------------------------------------------
    # THREE DOTS, NOT TWO. `git diff HEAD..$upstream` is a TREE comparison: its
    # output is every file that differs between the two trees, which includes
    # every file changed only by the operator's own unpushed commits. That list
    # was labelled INCOMING FILES and fed to the re-approval logic, so a checkout
    # that was ahead as well as behind was told to expect a hook re-approval and
    # a module-flag change that were not coming - and $needs.Count forces exit 2.
    # `HEAD...$upstream` is merge-base to upstream, which is exactly "what is
    # arriving".
    #
    # THE AHEAD COUNT IS NAMED ON THIS ROW TOO. It was computed and printed only
    # in the `position` row, so nothing beside the incoming list told the reader
    # the branch had diverged at all - which is why the contamination was
    # invisible where it was read.
    $changed = @()
    if ($behind -gt 0 -and -not [string]::IsNullOrWhiteSpace($upstream)) {
        $d = Git @('diff', '--name-only', "HEAD...$upstream")
        $why = Get-LwgToolReport -Tool 'git diff' -Result $d
        if ($why) { Add-Row -Id 'changes' -Status 'WARN' -Detail "$why - cannot say what would change" }
        else {
            $changed = @($d.out -split "`r?`n" | Where-Object { $_ })
            Add-Row -Id 'changes' -Status 'INFO' -Detail "$($changed.Count) file(s) arriving from $upstream (merge-base..$upstream)$(if ($ahead -gt 0) { ", and this branch is $ahead commit(s) AHEAD - those files are not in this list" } else { '' })"
        }
    } else {
        Add-Row -Id 'changes' -Status 'OK' -Detail 'nothing incoming'
    }

    # The re-approval list, as a function of a file list, so it can be rebuilt
    # from what ACTUALLY LANDED after a pull rather than only from what was
    # predicted before one. See section 5.
    function Get-Needs {
        param([string[]]$Files)
        $n = @()
        if ($Files -contains ($script:PathPrefix + 'hooks/hooks.json')) {
            $n += 'hooks/hooks.json changes: hook registrations are read at SESSION START, so nothing takes effect until you start a new session - and a hook command that is new to this machine can prompt for approval before it runs.'
        }
        if ($Files -contains ($script:PathPrefix + '.claude-plugin/plugin.json')) {
            $n += '.claude-plugin/plugin.json changes: the plugin NAME is what the state directory is resolved from, so a rename moves every log to a new directory and leaves the old one behind. The manifest does NOT name a hooks file - hooks are registered in hooks/hooks.json, which is reported on its own line.'
        }
        if ($Files -contains ($script:PathPrefix + 'statusline/statusline.ps1')) {
            # THE SAME RESOLVED TARGET SECTION 4 USES (#77). This note named the
            # default copy target unconditionally, so on a machine whose status
            # line is wired through the skills junction it told the operator to
            # re-copy a file that is not the live one - and the row below then
            # reported that same file as absent. Two sentences about two
            # different files, neither of them the one being run.
            if ($slSource -eq 'command') {
                $n += "statusline/statusline.ps1 changes: the live status line on this machine is $slWired, which is what statusLine.command names in $slSettings. git does not touch it. Re-copy it after the pull or it stays stale, silently."
            } elseif ([string]::IsNullOrWhiteSpace($claudeHome)) {
                $n += 'statusline/statusline.ps1 changes: the live status line is a COPY that git does not touch, and no configuration directory could be resolved on this machine, so this note cannot name it. Find it in your settings.json statusLine.command and re-copy it after the pull.'
            } else {
                $n += "statusline/statusline.ps1 changes: no statusLine.command is set in $slSettings, so the live status line - if there is one - is the DEFAULT copy target $(Join-Path $claudeHome 'statusline.ps1'). git does not touch it. Re-copy it after the pull or it stays stale, silently."
            }
        }
        if ($Files -contains ($script:PathPrefix + 'config.json')) {
            $n += 'config.json changes: config.json is the SHIPPED DEFAULTS, so a pull can change what runs where you have not set the flag yourself. Your own settings are in config.override.json under the state directory, git does not touch that file, and it is merged over whatever arrives. The flag differences below are computed with your override applied to BOTH sides, so they are what will actually change.'
        }
        foreach ($c in $Files) {
            if ($c -like ($script:PathPrefix + 'commands/*')) { $n += "new or changed slash command ($c) - it appears in the next session, not this one"; break }
        }
        # THE output-styles/ BRANCH WENT WITH THE DIRECTORY. It could not fire on
        # any tree this command can be run against, and a branch that cannot fire
        # reads to the next maintainer as a covered case.
        # PLAIN, NOT `return , @($n)` - #222. The unary comma wraps
        # UNCONDITIONALLY, so what left this function was a ONE-ELEMENT array
        # holding the whole list, and the caller's own `@(...)` could not undo
        # it. Measured, both branches were wrong: empty needs rendered
        # "NEEDS RE-APPROVAL OR RE-INSTALL (1):" over a BLANK bullet, and three
        # needs rendered "(1):" over one bullet with all three space-joined by
        # $OFS in "    - $n". A block whose entire job is to ENUMERATE what an
        # operator must re-approve could not say "three things need your
        # attention", and nothing caught it: the block still rendered, the exit
        # code was unchanged, and the two assertions section 26 makes about it
        # are negative substring tests that the joining left true.
        #
        # `,` is the right idiom when a caller takes the value bare, because
        # PowerShell unrolls a returned collection - the trap this repo has
        # shipped three times as `return ,$on`, `return ,$tokens` and
        # `return $hashset` (lib/common.ps1:961-964). It is the WRONG idiom
        # here, because both call sites already wrap in `@(...)`, which is what
        # re-forms the array from the unrolled elements and yields an EMPTY
        # array for no needs.
        return @($n)
    }
    $needs = @(Get-Needs -Files $changed)

    # The config diff, spelled out: which flags, which way.
    if ($changed -contains ($script:PathPrefix + 'config.json') -and -not [string]::IsNullOrWhiteSpace($upstream)) {
        $show = Git @('show', "${upstream}:$($script:PathPrefix)config.json")
        if ($show.ok) {
            try {
                # BOTH SIDES CARRY THE OPERATOR'S OVERRIDE - #11. $mine comes
                # from Get-LwgConfig, which merges config.override.json over the
                # shipped defaults; $theirs is the raw incoming file. Comparing
                # one against the other would report every setting the operator
                # has made as a flag the PULL is about to move, which it is not:
                # the override is not in the repository and arrives with nothing.
                # Applying it to the incoming side too makes this row answer the
                # question it claims to - what will be different afterwards.
                $theirs = $show.out | ConvertFrom-Json
                $mine   = Get-LwgConfig -Path (Join-Path $Root 'config.json')
                try {
                    $ovp = Get-LwgConfigOverridePath
                    if (-not [string]::IsNullOrWhiteSpace($ovp) -and [IO.File]::Exists($ovp)) {
                        $ovt = [IO.File]::ReadAllText($ovp)
                        if (-not [string]::IsNullOrWhiteSpace($ovt)) {
                            $ovo = $ovt | ConvertFrom-Json
                            if ($ovo -is [System.Management.Automation.PSCustomObject]) {
                                $theirs = Merge-LwgConfigOverride -Base $theirs -Override $ovo
                            }
                        }
                    }
                } catch {
                    # An override that cannot be read is one Get-LwgConfig has
                    # already discarded from $mine, so both sides are then the
                    # bare documents and the comparison stays honest.
                }
                $diffs = @()
                # RESOLVED THE WAY A HOOK WILL RESOLVE IT, not by a bare [bool]
                # on the raw member. Two things were wrong with the cast: a
                # non-boolean read as `on` here while Test-LwgModule ignores it,
                # and an ABSENT key read as `off` while an unlisted module is
                # ENABLED - so this reported flag moves that are not moves, and
                # missed the ones that are. Test-LwgModule is the same rule and
                # the same logging helper, and it also answers correctly for the
                # modules whose flag lives outside the `modules` block.
                foreach ($m in @($script:LwgModules)) {
                    $a = Test-LwgModule -Name $m -Config $mine
                    $b = Test-LwgModule -Name $m -Config $theirs
                    if ($a -ne $b) { $diffs += "$m $(if ($a) { 'on' } else { 'off' }) -> $(if ($b) { 'on' } else { 'off' })" }
                }
                if ($diffs.Count -gt 0) { Add-Row -Id 'config-flags' -Status 'WARN' -Detail ($diffs -join '; ') }
                else { Add-Row -Id 'config-flags' -Status 'OK' -Detail 'config.json changed, but no module flag did' }
            } catch { Add-Row -Id 'config-flags' -Status 'WARN' -Detail "the incoming config.json could not be parsed for comparison: $($_.Exception.Message)" }
        } else {
            Add-Row -Id 'config-flags' -Status 'WARN' -Detail (Get-LwgToolReport -Tool "git show ${upstream}:$($script:PathPrefix)config.json" -Result $show)
        }
    }

    # The status-line copy, checked on every run and not only when it changed -
    # it can be stale from an update made weeks ago.
    $slRepo = Join-Path $Root 'statusline\statusline.ps1'
    # WHICH FILE, AND ON WHOSE SAY-SO. Resolved once at the top of the run - see
    # the block above section 0 - so this row and the re-approval note in
    # Get-Needs cannot name two different files.
    $slWhose = switch ($slSource) {
        'command' { "the file statusLine.command names in $slSettings" }
        default   { "the DEFAULT copy target - no statusLine.command is set, so this is where the installer's copy mode would have put it" }
    }
    if ($slSource -eq 'command') { $slLive = $slWired }
    elseif ([string]::IsNullOrWhiteSpace($claudeHome)) { $slLive = '' }
    else { $slLive = Join-Path $claudeHome 'statusline.ps1' }

    if ($slSource -eq 'unidentified') {
        Add-Row -Id 'statusline' -Status 'WARN' -Detail "statusLine.command is set but names no .ps1 this check could identify, so no file was compared: $slWired. The default copy target was NOT compared instead - it is not what this machine is running."
    } elseif ($slSource -eq 'unreadable') {
        Add-Row -Id 'statusline' -Status 'INFO' -Detail "$slSettings could not be read or parsed, so which file is the live status line was not established. This is not evidence that there is none; /lw-watchtower:doctor check 7 is where an unreadable settings file is reported."
    } elseif ([string]::IsNullOrWhiteSpace($slLive)) {
        Add-Row -Id 'statusline' -Status 'INFO' -Detail 'no configuration directory could be resolved, so the live status line was not looked for. This is not evidence that it is missing.'
    } elseif ((Test-Path -LiteralPath $slLive) -and (Test-Path -LiteralPath $slRepo)) {
        $a = (Get-FileHash -LiteralPath $slLive -Algorithm SHA256).Hash
        $b = (Get-FileHash -LiteralPath $slRepo -Algorithm SHA256).Hash
        if ($a -eq $b) { Add-Row -Id 'statusline' -Status 'OK' -Detail "$slLive is byte-identical to the repo copy ($slWhose)" }
        else {
            Add-Row -Id 'statusline' -Status 'WARN' -Detail "$slLive DIFFERS from statusline/statusline.ps1 - one of them is stale and nothing on this machine reconciles them ($slWhose)"
            $needs += "the installed status line differs from the repo copy. Copy-Item `"$slRepo`" `"$slLive`" makes the repo version live - check which way round you want it first, because a fix made to the live file is lost. That path is $slWhose."
        }
    } elseif (-not (Test-Path -LiteralPath $slLive)) {
        if ($slSource -eq 'command') {
            # A CONFIGURED TARGET THAT IS NOT THERE IS NOT "NOT INSTALLED". The
            # status line IS wired; the file it is wired to is gone, which
            # renders as no segments at all rather than as an absent segment.
            Add-Row -Id 'statusline' -Status 'WARN' -Detail "statusLine.command points at $slLive, which does not exist. The status line is CONFIGURED and BROKEN, which is not the same as not installed - it renders nothing at all."
        } else {
            Add-Row -Id 'statusline' -Status 'INFO' -Detail "no $slLive and no statusLine.command in $slSettings - the HH segment is not installed on this machine"
        }
    }

    # ---------------------------------------------------------------------
    # 5. pull
    # ---------------------------------------------------------------------
    $pulled     = $false
    $pullKilled = $false
    if ($Apply) {
        # -Offline AND -Apply IS REFUSED. `git pull` fetches, so the combination
        # is a documented promise not to touch the network next to a command that
        # does. Worse than the broken promise: the whole analysis above - the
        # incoming list and the re-approval block - was computed from the STALE
        # tracking ref, because -Offline skips the refreshing fetch at section 3,
        # and the in-pull fetch then fast-forwards to the live remote tip. So the
        # operator was handed a NEEDS RE-APPROVAL section that is authoritative
        # about a state that no longer exists, printed on the same page as
        # "[WARN] fetch -Offline: no fetch was made".
        #
        # A FAIL and not a WARN, because exit 1 - "REFUSED ... nothing was
        # changed" - is exactly what happened. The check-only -Offline run is
        # unaffected and still reports what the last fetch left.
        if ($Offline) {
            Add-Row -Id 'pull' -Status 'FAIL' -Detail 'REFUSED - -Offline forbids the network and `git pull` fetches, so the two flags cannot both be honoured. Nothing was merged. Re-run without -Offline, or without -Apply.'
        } elseif ($script:Fail -gt 0) {
            Add-Row -Id 'pull' -Status 'FAIL' -Detail 'REFUSED - a check above failed. Nothing was merged.'
        } elseif ($behind -eq 0) {
            Add-Row -Id 'pull' -Status 'OK' -Detail 'nothing to pull'
        } else {
            $p = Git @('pull', '--ff-only') ([Math]::Max($TimeoutMs, 20000))
            $why = Get-LwgToolReport -Tool 'git pull --ff-only' -Result $p
            if ($why) {
                # THE FOUR FAILURE STATES ARE FOUR DIFFERENT FACTS, AND NOT ONE
                # OF THEM IS A FACT ABOUT THE CHECKOUT.
                # Get-LwgToolReport distinguishes missing / timeout / nonzero /
                # error, and this row used to append to them two claims nothing
                # here had established: that the checkout is unchanged, and that
                # the cause is branch divergence. `nonzero` carried both and
                # missing/error carried the first. Neither survives the header's
                # own promise at lines 21-22.
                #
                #   * "nothing was merged" is not observed. `git pull` fetches
                #     and THEN merges, and a non-zero exit reported by git is a
                #     different fact from a checkout that did not move. On
                #     `timeout` the claim is not merely unproven, it is false in
                #     the ordinary case: Process.Kill() ends the git process
                #     this script started and not a child of it, so a
                #     post-merge hook that outlives the bound leaves a
                #     fast-forward already on disk with HEAD moved. A case in
                #     section 26 of tests\setup_merge.ps1 builds exactly that
                #     and reads HEAD before and after.
                #   * "the branches have diverged" is a guess. --ff-only refuses
                #     for other reasons too, and where divergence IS the reason
                #     git says so itself on stderr - which $why already prints.
                #   * "git never ran" was wrong for `error`, which comes from
                #     the plumbing AFTER Process.Start returned. Only `missing`
                #     means never started.
                #
                # So this row now reports what is established and nothing else:
                # git's own account, the state the pull failed in, and UNKNOWN.
                # The tree is not asserted about - it is ASKED about, with the
                # same command this script already runs twice; if that command
                # itself fails, THAT is the answer worth printing.
                $after = Git @('status', '--porcelain=v2', '--branch') 6000
                $state = if ($after.ok) {
                    $ab = @($after.out -split "`r?`n" | Where-Object { $_ -like '# branch.ab*' })
                    $dirtyNow = @($after.out -split "`r?`n" | Where-Object { $_ -and $_ -notlike '#*' }).Count
                    "git status now reports $(if ($ab.Count) { $ab[0].Trim() } else { 'no ahead/behind line' }) with $dirtyNow uncommitted change(s)"
                } else {
                    "git status could not be run afterwards either ($($after.state)) - if .git\index.lock is present, that is what to clear first"
                }
                # `timeout` alone earns a further sentence, and it is mechanism
                # rather than a claim about this tree: it says what the kill can
                # and cannot have undone, in the same hedged terms every clause
                # of it is actually known in.
                $killed = if ($p.state -eq 'timeout') {
                    ' Process.Kill() was sent to the git process this script started and to no child of it, so a fetch may have landed, a fast-forward may already be on disk, and .git\index.lock may have outlived the kill.'
                } else { '' }
                if ($p.state -eq 'timeout') { $pullKilled = $true }
                # No second "not clean" here: Get-LwgToolReport's own line
                # already ends in one on the timeout state, and a row that says
                # the same thing twice reads as two findings.
                Add-Row -Id 'pull' -Status 'FAIL' -Detail "$why - the pull FAILED in state '$($p.state)', so the state of the checkout is UNKNOWN: nothing here establishes what did or did not land. $state$killed"
            } else {
                $pulled = $true
                # git prints a file-by-file summary; the line that says what
                # actually happened to the branch is the one worth reporting.
                $lines = @($p.out -split "`r?`n" | Where-Object { $_ })
                $head = @($lines | Where-Object { $_ -match '^(Updating|Fast-forward|Already up to date)' })
                $detail = if ($head.Count -gt 0) { ($head -join ' / ') } elseif ($lines.Count -gt 0) { $lines[0] } else { 'pulled' }
                Add-Row -Id 'pull' -Status 'OK' -Detail "$detail ($($lines.Count) line(s) of git output)"

                # RE-DERIVED FROM WHAT ACTUALLY LANDED. Everything above was
                # computed before the merge, from a ref that a fetch has since
                # moved, and it was then PRINTED below the merge as though it
                # described it. ORIG_HEAD..HEAD is what this pull really brought.
                $post = Git @('diff', '--name-only', 'ORIG_HEAD..HEAD')
                if ($post.ok) {
                    $changed = @($post.out -split "`r?`n" | Where-Object { $_ })
                    $needs   = @(Get-Needs -Files $changed)
                    Add-Row -Id 'merged' -Status 'INFO' -Detail "$($changed.Count) file(s) actually changed by this pull (ORIG_HEAD..HEAD) - the list and the re-approval block below are rebuilt from these, not from the pre-pull comparison"
                } else {
                    Add-Row -Id 'merged' -Status 'WARN' -Detail "$(Get-LwgToolReport -Tool 'git diff ORIG_HEAD..HEAD' -Result $post) - so the file list and the re-approval block below are the PRE-PULL prediction and may not match what landed"
                }
            }
        }
    } else {
        Add-Row -Id 'pull' -Status 'INFO' -Detail $(if ($behind -gt 0) { "not pulled - re-run with -Apply to fast-forward $behind commit(s)" } else { 'nothing to pull' })
    }

    # ---------------------------------------------------------------------
    # 6. the doctor, on whatever is now on disk
    # ---------------------------------------------------------------------
    $doctorExit = $null
    $doctorOut = ''
    # The FAIL count as it stood BEFORE the doctor ran. Exit 1 means "REFUSED -
    # nothing was changed", which is a statement about this script's own
    # refusals; a doctor finding about the tree as it already stood is not one of
    # them and must not be reported as one. See the exit selection below.
    $failBeforeDoctor = $script:Fail
    if ($SkipDoctor) {
        Add-Row -Id 'doctor' -Status 'WARN' -Detail '-SkipDoctor: the plugin was NOT checked after this run'
    } else {
        $doc = Join-Path $Root 'bin\lwg-doctor.ps1'
        if (-not (Test-Path -LiteralPath $doc)) {
            Add-Row -Id 'doctor' -Status 'WARN' -Detail "no $doc to run"
        } else {
            $r = Invoke-LwgCmdProcess -File 'powershell' -ProcArgs @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $doc, '-Quiet') -WorkDir $Root -TimeoutMs 30000
            $doctorOut = $r.out
            if ($r.state -eq 'timeout' -or $r.state -eq 'missing' -or $r.state -eq 'error') {
                Add-Row -Id 'doctor' -Status 'WARN' -Detail (Get-LwgToolReport -Tool 'the doctor' -Result $r)
            } else {
                $doctorExit = $r.code
                switch ($r.code) {
                    0 { Add-Row -Id 'doctor' -Status 'OK'   -Detail 'every check passed' }
                    1 { Add-Row -Id 'doctor' -Status 'FAIL' -Detail 'the doctor FAILED - see its output below' }
                    2 { Add-Row -Id 'doctor' -Status 'WARN' -Detail 'the doctor passed with warnings - see its output below' }
                    3 { Add-Row -Id 'doctor' -Status 'WARN' -Detail 'the doctor could not complete, so the plugin is UNCHECKED rather than healthy' }
                    default { Add-Row -Id 'doctor' -Status 'WARN' -Detail "the doctor exited $($r.code), which is not a code it documents" }
                }
            }
        }
    }

    # --- report -------------------------------------------------------------
    Write-Output ''
    $w = 3; foreach ($r in $script:Rows) { if ($r.Id.Length -gt $w) { $w = $r.Id.Length } }
    foreach ($r in $script:Rows) { Write-Output ("  [{0}] {1}  {2}" -f $r.Status.PadRight(4), $r.Id.PadRight($w), $r.Detail) }

    if ($changed.Count -gt 0) {
        Write-Output ''
        Write-Output "  $(if ($pulled) { 'FILES THIS PULL MERGED' } else { 'INCOMING FILES' }) ($($changed.Count)):"
        foreach ($c in @($changed | Select-Object -First 25)) { Write-Output "    $c" }
        if ($changed.Count -gt 25) { Write-Output "    ... and $($changed.Count - 25) more" }
    }

    Write-Output ''
    if ($needs.Count -eq 0) {
        Write-Output '  NEEDS RE-APPROVAL OR RE-INSTALL: nothing found.'
    } else {
        Write-Output "  NEEDS RE-APPROVAL OR RE-INSTALL ($($needs.Count)):"
        foreach ($n in $needs) { Write-Output ''; Write-Output "    - $n" }
    }

    if ($doctorOut) {
        Write-Output ''
        Write-Output "  DOCTOR (exit $doctorExit):"
        foreach ($l in @($doctorOut -split "`r?`n")) { if ($l.Trim()) { Write-Output "    $l" } }
    }

    Write-Output ''
    Write-Output '  NOT covered here: whether the remote you fetched from is the one you think it is, whether'
    Write-Output '  another checkout of this repo is the one Claude Code loads, and anything a new session'
    Write-Output '  would have to start before it could be observed at all.'

    # EXIT 4 MEANS "the doctor failed after an update", SO IT NEEDS AN UPDATE.
    # It was selected from the doctor's exit code alone, above the refusal test,
    # so a check-only run, a run refused for a dirty tree and a run with nothing
    # to pull all returned 4 - and commands/update.md tells the model that 4
    # means the doctor failed after the update and to "not describe the update as
    # successful", which presupposes one. The doctor's verdict is real in every
    # one of those cases; it was the causal attribution that was manufactured.
    #
    # A killed pull is not a refusal either. Exit 1's documented meaning is
    # "nothing was changed", which nobody can say about a pull that was killed
    # mid-operation, so it takes exit 2 - "finished, with caveats" - and the row
    # says the tree state is UNKNOWN.
    if ($pulled -and $doctorExit -eq 1) { exit 4 }
    if ($failBeforeDoctor -gt 0 -and -not $pullKilled) { exit 1 }
    # Commits available and not taken is a caveat, not a clean bill: the checkout
    # is knowingly out of date and the caller must not read 0 as "nothing to do".
    # A doctor failure on a tree this run did not change lands here too: it is a
    # real finding, and it is not evidence about an update.
    if ($script:Warn -gt 0 -or $script:Fail -gt 0 -or $needs.Count -gt 0 -or ($behind -gt 0 -and -not $pulled)) { exit 2 }
    exit 0

} catch {
    Write-Output ''
    Write-Output "LW-WATCHTOWER update could not complete: $($_.Exception.Message)"
    Write-Output 'Do not read anything above as an up-to-date verdict.'
    exit 3
}
