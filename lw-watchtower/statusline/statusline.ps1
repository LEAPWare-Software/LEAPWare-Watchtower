#requires -version 5
# LWG-STATUSLINE-IDENTITY v1
#
# PROVENANCE MARKER. THE FORMAT IS: the exact token LWG-STATUSLINE-IDENTITY,
# followed by a version word, on a comment line inside the FIRST 4096 BYTES of
# this file. The token is what is matched; the version word is for a human and
# nothing parses it.
#
# WHO READS IT: bin\lwg-doctor.ps1, check 7, and nothing else today. That check
# pulls whatever .ps1 is wired into settings.json's statusLine.command and used
# to hash-compare it against this file with no test of whose file it was, so a
# status line the operator wrote themselves was diagnosed as a stale copy of
# this one and the printed remedy was to overwrite it. The marker is how the
# check now establishes provenance BEFORE it diagnoses drift. bin\lwg-uninstall.ps1
# needs the same answer before it removes anything and does not read this yet -
# see issue #17.
#
# WHY THE TOKEN DOES NOT CARRY THE PRODUCT NAME. This plugin was renamed from
# lw-gmhh to lw-watchtower on 3 August 2026. A marker spelling the product would
# have moved with that rename, and every copy already installed on a machine
# would have stopped being recognisable as ours - which is the same "not our
# file" answer the marker exists to make trustworthy. LWG is the file prefix
# every script in this repo already carries and it survived the rename.
#
# DO NOT REMOVE IT FROM AN INSTALLED COPY. A copy of this file with this line
# deleted is, correctly, not identifiable as this plugin's status line, and the
# doctor will report it as somebody else's.
#
# WHAT IT IS NOT: IT IS FORGEABLE, AND THAT IS A LIMIT AND NOT AN OVERSIGHT.
# Any file carrying this string in its first 4096 bytes is taken to be this
# plugin's status line, and would then be told it has drifted and to re-copy
# over itself. A content token cannot be made unforgeable and this one does not
# try. It answers one question - "was this file derived from ours, or is it an
# unrelated status line that simply happens to be wired up" - and that is the
# question the doctor was getting wrong on every machine that had its own
# status line. It is not a signature and proves nothing against a file that
# copied this comment.
#
# Claude Code status line. All percentages are USED.
#
#   row 1  model  HH  ORC  ctx  5h  7d  #branch  PR#  owner/repo
#   row 2  advisories - printed ONLY when something is actually wrong
#
# Everything on row 1 except HH and owner/repo comes from the stdin payload.
# Those two read small local files. No process is ever spawned: this renders on
# every assistant message and on every refreshInterval tick, and a nonzero exit or
# empty stdout blanks the whole line.

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

# THE PAYLOAD IS DECODED AS UTF-8 EXPLICITLY, and deliberately NOT through
# [Console]::In.
#
# [Console]::In is built from [Console]::InputEncoding, which is the console's
# INPUT code page - IBM437 in a `powershell -File` child with stdin redirected
# from a pipe, measured on this machine, and never 65001 - while Claude Code
# writes this payload as UTF-8. Read through it, every non-ASCII byte arrives
# mojibaked: the model name, the branch, the worktree name, the agent name, and
# the half that is not cosmetic - workspace.current_dir, which then names a path
# that does not exist, so GitDir finds no .git and the owner/repo segment
# degrades to the dim leaf name. That dim leaf is ALSO what a cwd outside any
# repo renders, so the two states are indistinguishable on the row.
#
# This is the same defect the health-log reader 250 lines below already found
# and fixed for itself - see TailWindow's note on Get-Content and ANSI - and the
# reasoning was never applied to this file's own stdin.
#
# WHY NOT [Console]::InputEncoding = UTF8. It works, but it throws when no
# console is attached and it must be set before the first read because the
# reader is cached, so it is two failure modes to get right instead of none.
# Opening the raw stream avoids both. detectEncodingFromByteOrderMarks is $true
# so that a UTF-8 BOM is CONSUMED by the reader rather than handed to the '{'
# test below - a BOM decoded through cp437 makes the first character U+2229, the
# test fails, this script exits 0 having printed nothing, and the header above
# records what that costs: an empty stdout blanks the whole row, silently, with
# no signal that the script ran at all.
#
# The explicit U+FEFF strip stays anyway. It costs nothing and it covers the
# case the StreamReader's detection does not - a BOM that is not at byte 0 -
# and .Trim() never removed it, because U+FEFF is not whitespace under .NET 4.
$raw = ''
try {
    $sr = New-Object IO.StreamReader([Console]::OpenStandardInput(), (New-Object Text.UTF8Encoding($false)), $true)
    try { $raw = $sr.ReadToEnd() } finally { $sr.Dispose() }
} catch { $raw = '' }
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
$raw = $raw.Trim().TrimStart([char]0xFEFF).Trim()
# only a JSON object is a payload; a bare scalar or array is garbage on stdin
if ($raw.Length -eq 0 -or $raw[0] -ne '{') { exit 0 }
try { $d = $raw | ConvertFrom-Json } catch { exit 0 }
if ($null -eq $d) { exit 0 }

$E = [char]27
function Paint([int]$c, [string]$t) { "$E[${c}m$t$E[0m" }

# The colour of a percentage on row 1. FOUR bands at 50/75/90, and they are
# deliberately NOT the two configured thresholds: config.json's ratelimit and
# context blocks carry two numbers per axis and this carries three edges, so
# they do not map onto each other. config.json says which is which, and that
# comment was corrected on 3 August 2026 - it used to tell the operator these
# two numbers drove "the status line's colouring", which they never did.
#
# Callers pass the ALREADY-ROUNDED value. See Whole below: the number that is
# printed and the number that is compared have to be the same number.
function Heat([double]$used) {
    if ($used -ge 90) { 91 } elseif ($used -ge 75) { 33 } elseif ($used -ge 50) { 93 } else { 32 }
}

# ROUND ONCE, THEN COMPARE AND PRINT THE SAME NUMBER.
#
# Every percentage on this row is displayed with '{0:0}%' and every threshold
# test used to be made against the raw double, so the two disagreed over the
# half-unit below each edge: ctx 89.6 printed "90%" - the number config.json
# calls critical_pct - in the YELLOW of the band below, next to the sub-critical
# "plan for compaction" advisory, which quoted "90%" back at the operator. The
# reverse case costs more: 91.5 on a rate limit prints "92%", which config.json
# defines as land_all_pct, beside an advisory that says "approaching limit".
#
# AwayFromZero rather than the default: '{0:0}' is banker's rounding, so 74.5
# printed 74 and 75.5 printed 76. That was a second inconsistency and it is
# gone with the same call. What this does NOT do is remove the boundary itself -
# a value that rounds up ACROSS an edge now moves the colour and the advisory
# with it, which is the point, but 89.6 is still reported as 90 and the raw
# figure is still not shown anywhere.
function Whole([double]$v) { return [Math]::Round($v, [MidpointRounding]::AwayFromZero) }

# A number that came from OUTSIDE this process - config.json, or the stdin
# payload. THREE outcomes, not two:
#
#   $null      absent. Nothing was supplied, and the built-in or the '--' glyph
#              is the correct answer.
#   [double]   usable.
#   'bad'      present and unusable. NOT the same fact as absent, and this file's
#              own glyph doctrine ("EVERY STATE HAS ITS OWN SHAPE", see the HH
#              table) says it must not render as one.
#
# Every one of these was a bare [double] cast until 3 August 2026, under
# $ErrorActionPreference = 'SilentlyContinue'. A failed cast in an assignment
# under that preference does not stop the script and does not print: the
# assignment simply does not happen. So a payload percentage that would not
# parse rendered as a GREEN '%' with no digits in front of it AND suppressed the
# advisory that would otherwise have fired - a false all-clear reached from the
# numeric side, which is the mirror of the one the HH glyph table exists to
# prevent. A configured threshold that would not parse was replaced by the
# built-in in silence.
#
# A JSON number arrives from ConvertFrom-Json already typed, so it is taken
# directly - [string] on a double under a comma-decimal culture would spell it
# "89,6" and then fail an invariant parse, which would be this same defect
# introduced by the fix for it. Only a STRING is parsed, and as invariant,
# because JSON's number grammar is invariant.
function AsNum($v) {
    if ($null -eq $v) { return $null }
    if ($v -is [double] -or $v -is [single] -or $v -is [decimal] -or
        $v -is [int]    -or $v -is [long]   -or $v -is [int16]   -or
        $v -is [byte]   -or $v -is [uint32] -or $v -is [uint64]) { return [double]$v }
    $s = [string]$v
    if ([string]::IsNullOrWhiteSpace($s)) { return 'bad' }
    $n = 0.0
    if ([double]::TryParse($s, [Globalization.NumberStyles]::Float,
                           [Globalization.CultureInfo]::InvariantCulture, [ref]$n)) { return $n }
    return 'bad'
}
$EPOCH = [datetime]::SpecifyKind([datetime]'1970-01-01T00:00:00', 'Utc')

# --- Claude Code's configuration directory ---------------------------------
# CLAUDE_CONFIG_DIR relocates it away from ~/.claude. Until 3 September 2026
# NOTHING in this repository read it, so on a machine that sets it this file
# read a data root nothing had ever been written to and rendered off an empty
# log - which, for an indicator whose entire job is to say whether the plugin is
# healthy, is the false green it exists to prevent.
#
# THIS IS A SECOND COPY OF lib\common.ps1's Get-LwgClaudeHomeInfo, AND THAT IS
# DELIBERATE. This script is a settings.json `statusLine.command`: it runs as a
# fresh powershell.exe on every assistant message, and its cost is paid by the
# operator on every one of them. Dot-sourcing lib\common.ps1 was measured on
# this branch rather than guessed - seven runs of `powershell -NoProfile
# -Command ". lib\common.ps1"` against seven runs of `-Command "1"`, median
# delta 66 ms, for a 3537-line file of which this needs eleven. 66 ms per
# rendered message to avoid twenty lines of duplication is the wrong trade, and
# "the status line dot-sources nothing" is a standing property of this file
# rather than an oversight.
#
# THE PRICE OF THE COPY IS THAT THE TWO MUST BE KEPT IN STEP, so they
# cross-reference each other by name: lib\common.ps1's block above
# Get-LwgClaudeHomeInfo says the status line keeps its own copy and why, and
# this comment says where the original is. The PRECEDENCE and the three awkward
# values - trailing separator, relative value, a directory that is not there -
# are argued in full there and only applied here. Two rules matter to a reader
# of this file:
#
#   * an unset, empty or whitespace-only CLAUDE_CONFIG_DIR is NOT a value, and
#     resolution continues to the profile;
#   * a CLAUDE_CONFIG_DIR naming a directory that does not exist is returned AS
#     GIVEN. Falling back to the profile then would silently reinstate the whole
#     defect on exactly the machine that set the variable.
#
# CLAUDE_PLUGIN_DATA still wins for the DATA directory specifically - see
# LwgDataDirs, which leads with it - because it names the exact directory rather
# than a tree one is derived from. Same order as lib\common.ps1.
function LwgClaudeHome {
    $v = $env:CLAUDE_CONFIG_DIR
    if (-not [string]::IsNullOrWhiteSpace($v)) {
        $t = $v.Trim().TrimEnd([char[]]@('\', '/'))
        # `C:` alone is a drive-RELATIVE path in Windows and means something
        # else entirely, so a bare drive keeps its root separator.
        if ($t.Length -eq 2 -and $t[1] -eq ':') { $t = $t + '\' }
        if ($t.Length -gt 0) {
            try { $t = [IO.Path]::GetFullPath($t) } catch { }
            if ($t.Length -gt 3) { $t = $t.TrimEnd([char[]]@('\', '/')) }
        }
        return $t
    }
    $p = $env:USERPROFILE
    if ([string]::IsNullOrWhiteSpace($p)) { return $null }
    return [IO.Path]::Combine($p.TrimEnd([char[]]@('\', '/')), '.claude')
}

# Resolved ONCE. Every path below that used to be composed from
# $env:USERPROFILE and a literal `.claude` hangs off this instead. $null is
# possible - a machine with neither variable - and every consumer below is
# written to survive it rather than to compose a path onto nothing, which is how
# bin\lwg-toggle.ps1 exited 3 on a file it had just successfully written.
$claudeHome = LwgClaudeHome

# Every LW-WATCHTOWER plugin data dir, newest first.
#
# The plugin is auto-discovered out of the skills dir as 'lw-watchtower@skills-dir', so
# the data dir Claude Code hands its hooks is 'lw-watchtower-skills-dir' - NOT the bare
# 'lw-watchtower' that Get-LwgStateDir falls back to when CLAUDE_PLUGIN_DATA is unset.
# This script is a settings.json command, not a plugin hook, so it is NEVER given
# CLAUDE_PLUGIN_DATA and always took that fallback: it read a dir the live plugin
# had stopped writing to, and reported healthy off an empty file. So the name is
# matched with a glob, never a literal - the next plugin-id change renames the
# dir again, and a second hardcoded name would blind this indicator a second
# time in exactly the same way.
#
# Every match is READ, not just the newest. Picking one winner needs a freshness
# rule and the cheap ones are all wrong under load: right now the STALE bare dir
# holds the most recently written log of the two, because a test run with no
# CLAUDE_PLUGIN_DATA set is appending gate records to it. Everything downstream
# is filtered to the current session anyway, so a record from the wrong dir is
# discarded on its session id rather than on a guess about which dir is live. A
# union cannot pick the wrong dir at all. Newest-first only decides tie-break
# order; it never excludes anything.
#
# WHAT THE UNION COSTS, corrected on 3 August 2026. This used to say "one extra
# tail read per render", which was true of the two-directory case it was written
# in and is not a bound. HealthSeg reads EVERY directory this returns, and each
# one costs a seek-and-decode of up to $maxBytes (1 MB) plus up to $keep (300)
# ConvertFrom-Json calls. The count is unbounded by construction: the glob is
# what the paragraph above argues it must be, every plugin-id change adds a
# directory permanently, and nothing prunes - the stale one is still being
# written to, which is the whole reason it is still read. So the honest number
# is "one bounded tail read and up to 300 parses PER MATCHING DIRECTORY, and the
# directory count grows by one on every plugin-id change". Capping it is not
# proposed here: a cap re-introduces exactly the wrong-dir risk the paragraph
# above argues against, and the cost is still small beside the ~178 ms the first
# Get-ChildItem in this function already pays.
function LwgDataDirs {
    $dirs = @()
    # an explicit CLAUDE_PLUGIN_DATA is authoritative, so it leads the list
    if ($env:CLAUDE_PLUGIN_DATA) { $dirs += [string]$env:CLAUDE_PLUGIN_DATA }
    try {
        # $claudeHome, not $env:USERPROFILE + '.claude' - see LwgClaudeHome. A
        # $null home makes Join-Path throw, which this catch already absorbs
        # into "no directories", the same answer a missing root gives.
        $root = Join-Path $claudeHome 'plugins\data'
        foreach ($c in @(Get-ChildItem -LiteralPath $root -Directory -Filter 'lw-watchtower*' -ErrorAction Stop |
                         Sort-Object LastWriteTime -Descending)) { $dirs += $c.FullName }
    } catch {}
    $seen = @{}; $out = @()
    foreach ($p in $dirs) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $k = ([string]$p).TrimEnd('\').ToLowerInvariant()
        if ($seen.ContainsKey($k)) { continue }
        $seen[$k] = $true; $out += $p
    }
    return $out
}
$gmDataDirs = @(LwgDataDirs)

# THE SIGNAL BRIDGE. This process is the ONLY one on the machine that receives
# rate_limits and context_window, and until now it rendered them and threw them
# away.
#
# WHY THAT MATTERS, and why this is not a re-attempt of a blocked module.
# docs/modules.md records ratelimit_escalation and cost_tracking as unbuildable:
# verified against the claude-code 2.1.220 binary across all 31 hook events,
# rate_limits / context_window / cost are assembled in exactly ONE place - the
# status-line input builder - and NO HOOK EVENT CARRIES ANY OF THEM. That record
# stands and nothing here disturbs it. No hook reads rate_limits after this
# change either. What changes is only that the one process which already has the
# data writes it down, so that something else can read a FILE. The blocked names
# stay out of the modules block; see #168 section 0. (That specification was
# published under docs/ until the payload restructure; it is attached to #168
# in full and is no longer a page, so it is cited by issue rather than by a
# link this file would be the last reader of.)
#
# WRITTEN TO EVERY DATA DIR, NOT ONE, and that is a correction to the spec rather
# than an embellishment of it. section 3.1 names a single path,
# $CLAUDE_PLUGIN_DATA/signals/ratelimit.json. But this file is a settings.json
# command and NOT a plugin hook, so it is never given CLAUDE_PLUGIN_DATA at all -
# the comment above LwgDataDirs records that exact fallback having once made this
# script read a directory the live plugin had stopped writing to. The CONSUMERS
# of this file are hooks, and they DO get the variable. A single literal path
# would therefore split producer from consumer on precisely the machines the
# union above exists to survive. Writing to all of them cannot pick the wrong
# one, and it is the same argument LwgDataDirs already makes for reading.
#
# THE TEMP NAME CARRIES THE PID. section 3.1 says write to .tmp then Move-Item
# -Force, and a FIXED .tmp name reintroduces the very tear it is there to
# prevent: every concurrent session runs its own copy of this script against the
# same directory, so two processes would write one temp file and one of them
# would publish the other's half-written bytes.
#
# NOTHING HERE MAY REACH THE PIPELINE. The header of this file is explicit that a
# nonzero exit or empty stdout blanks the whole row, so every statement below is
# void-cast or assigned, and the whole function is wrapped so that a failed write
# costs the operator nothing. A status line that vanishes because a monitoring
# write failed would be a worse defect than the one this closes.
#
# ABSENT IS ABSENT. A field the CLI did not supply is OMITTED, never written as 0
# or null - a reader must be able to tell "not supplied" from "the value is 0".
# That is the Get-LwgRepo / payload.workspace.repo defect docs/modules.md
# records, and it is not repeated one directory over. AsNum answers three ways,
# not two: $null absent, [double] usable, 'bad' present-and-unparseable. The row
# already renders the third as a purple '??' rather than a green figure, so
# collapsing it into "absent" here would throw away a distinction this file
# argues for 600 lines above. An unparseable field is omitted AND named in
# `unparsed`, so a consumer can tell "the CLI said nothing" from "the CLI said
# something I could not read".
#
# NOT WRITTEN: cost. The spec's section 9 puts dollars out of scope - token
# counts only - and this file has never read $d.cost. Persisting it would make
# this the first reader of a field the whole modules record calls a dead end.
#
# AND NOT READ EITHER, WHICH IS THE PART NOTHING IN THIS TREE RECORDED UNTIL
# 4 SEPTEMBER 2026 - #78 item 2. THE COST BLOCK IS DELIVERED TO THIS PROCESS ON
# EVERY RENDER AND IS DROPPED ON PURPOSE. This is the only process on the
# machine that receives it: the census in docs\limitations.md, taken against the
# status-line reference on 2 September 2026, lists cost.* beside model.*,
# context_window.*, prompt_cache.*, rate_limits.* and the rest as what the
# status-line input carries, and docs\modules.md's ratelimit_escalation /
# cost_tracking entry records that no hook event carries any of the three. So
# "unavailable" was never the reason, and a reader of this file who found
# rate_limits read and cost absent could reasonably have concluded it was.
#
# The reason is a decision: dollars are out of scope for this plugin, taken with
# the spec and not revisited here. It is written down because a DELIBERATE drop
# and an OVERSIGHT are indistinguishable from the code - the field is simply
# never named - and the same silence about the GM segment is what the tombstone
# 750 lines below exists to break. No case pins this: the assertion would be
# about a field this file does not mention, which is not a thing a test can see.
function WriteSignal {
    param($Payload, [string[]]$Dirs)

    try {
        $sig = [ordered]@{ schema = 1 }

        # InvariantCulture, and the same reasoning as Stamp further down: a
        # timestamp formatted under whatever culture the machine happens to run
        # is not a timestamp another process can parse. Consumers treat a stale
        # file as no signal at all, so this field is mandatory - if it cannot be
        # produced, nothing is written.
        $sig.written_utc = ([datetime]::UtcNow).ToString(
            "yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)

        $sid = [string]$Payload.session_id
        if (-not [string]::IsNullOrWhiteSpace($sid)) { $sig.session_id = $sid }

        $unparsed = @()

        # resets_at is passed through VERBATIM and deliberately not through
        # ResetTime. That helper converts to LOCAL time for display; baking this
        # machine's offset into a file another process reads would make the
        # value wrong the moment it is read anywhere else.
        foreach ($w in @(
            @{ key = 'five_hour'; lim = $Payload.rate_limits.five_hour },
            @{ key = 'seven_day'; lim = $Payload.rate_limits.seven_day }
        )) {
            if ($null -eq $w.lim) { continue }
            $n = AsNum $w.lim.used_percentage
            if ($null -eq $n) { continue }
            if ($n -isnot [double]) { $unparsed += "$($w.key).used_percentage"; continue }
            $block = [ordered]@{ used_percentage = $n }
            if ($null -ne $w.lim.resets_at) { $block.resets_at = $w.lim.resets_at }
            $sig[$w.key] = $block
        }

        $cw = AsNum $Payload.context_window.used_percentage
        if ($null -ne $cw) {
            if ($cw -is [double]) { $sig.context_window = [ordered]@{ used_percentage = $cw } }
            else                  { $unparsed += 'context_window.used_percentage' }
        }

        # Omitted entirely when empty: an always-present empty array reads as a
        # field the writer forgot to fill in.
        if ($unparsed.Count -gt 0) { $sig.unparsed = $unparsed }

        $json = ($sig | ConvertTo-Json -Depth 5 -Compress)

        # LwgDataDirs ENUMERATES existing directories and creates none, so before
        # this plugin's first hook run there is nothing to write to. The bare
        # fallback is created for that case only, and it is self-correcting: any
        # consumer holding CLAUDE_PLUGIN_DATA has a directory Get-LwgStateDir
        # made, which the union picks up on the next render.
        $targets = @($Dirs)
        if ($targets.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($claudeHome)) {
            $targets = @([IO.Path]::Combine($claudeHome, 'plugins\data', 'lw-watchtower'))
        }

        foreach ($dir in $targets) {
            try {
                $sigDir = [IO.Path]::Combine($dir, 'signals')
                [void][IO.Directory]::CreateDirectory($sigDir)
                $final = [IO.Path]::Combine($sigDir, 'ratelimit.json')
                $tmp   = [IO.Path]::Combine($sigDir, "ratelimit.json.$PID.tmp")
                [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
                Move-Item -LiteralPath $tmp -Destination $final -Force -ErrorAction Stop
            } catch {
                # One unwritable directory must not cost the others, and none of
                # them may cost the row.
                try { if ($tmp -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } } catch { }
            }
        }
    } catch { }
}

# Every LW-WATCHTOWER plugin ROOT, in the order the presence probes below try them.
#
# The same argument as LwgDataDirs, applied to the code instead of the state: a
# hardcoded install path blinds an indicator permanently and silently on any
# machine laid out differently. This is worked on from more than one laptop and
# the checkout does not live in the same place on all of them, so the root is
# DERIVED - never a literal folder hierarchy and never a literal junction name.
#
#   1. CLAUDE_PLUGIN_ROOT when Claude Code set it. Free to test, authoritative
#      when present, absent for a settings.json command like this one.
#   2. This script's own parent. statusline/ sits directly under the plugin
#      root, so a run from the checkout or through the skills junction resolves
#      the root exactly, wherever the clone happens to be. For the INSTALLED
#      copy at ~/.claude/statusline.ps1 it resolves to the PROFILE instead.
#      That used to be dismissed here as costing nothing, "because every
#      candidate is only ever used via Test-Path". THAT WAS FALSE, and it was
#      false about the function two screens down: GmConfig OPENS a candidate's
#      config.json, so %USERPROFILE%\config.json - a file belonging to whatever
#      else put one there - was read as this plugin's configuration, ahead of
#      the real install, on every render of the installed copy. GmConfig now
#      requires a plugin marker beside the file and a config shaped like this
#      plugin's; the profile candidate is still enumerated here, because the
#      presence probes in HealthSeg genuinely do only Test-Path it, and
#      dropping candidates is how this indicator has been blinded twice.
#      THE RULE THIS LEAVES: a new consumer of $gmPluginRoots must not assume
#      every entry is a plugin root. They are candidates.
#   3. ~/.claude/skills/lw-watchtower* - the junction install. GLOBBED, for the reason
#      given at LwgDataDirs: the id in that name has already changed once, and
#      a second hardcoded spelling of it would go stale in the same way.
#   4. The MARKETPLACE install, which matches none of the above and which this
#      function spent its whole life looking for in a directory that does not
#      exist. See the next paragraph - it is the defect this block was rewritten
#      to close, and it is the same wrong assumption bin/lwg-setup.ps1 was
#      making at the same time, so the two were fixed together.
#
# WHERE A MARKETPLACE INSTALL ACTUALLY LIVES. Candidate 4 used to be
# ~/.claude/plugins/repos, matched at the repo directory and one level inside
# it. There is no such directory on a live Claude Code install: the string
# "plugins/repos" appears ZERO times in the 2.1.x CLI binary, while
# "marketplaces" appears 86 times, "known_marketplaces" 16 and
# "installed_plugins" 8. What the CLI actually writes, read out of that binary
# and off this machine's own ~/.claude tree rather than guessed:
#
#     ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>
#         The installed plugin ROOT - the path installed_plugins.json records
#         as installPath, and the directory the runtime drops its .in_use
#         marker into. <version> is a declared version or a commit sha. Every
#         segment is the id with anything outside [A-Za-z0-9-_] replaced by
#         '-', which is why a name glob is safe there and a literal is not.
#     ~/.claude/plugins/marketplaces/<marketplace>
#         The marketplace repo CHECKOUT, recorded as installLocation in
#         known_marketplaces.json. This is the SOURCE, not necessarily what
#         gets loaded, but a plugin can sit inside it.
#
# So on a marketplace install NO root resolved at all, and both things that
# depend on one failed silently and in the worst available direction: HealthSeg
# rendered purple 'HH?' - NOT INSTALLED - about a plugin that was installed and
# working, and GmConfig returned $null so the operator's configured thresholds
# were quietly replaced by the built-in numbers further down this file. An
# indicator that reports "not installed" about a working install is the same
# class of defect as one that reports "healthy" about nothing.
#
# ~/.claude/plugins/repos IS STILL SCANNED, deliberately. The two layouts above
# are what this machine's CLI writes today; they are read out of a binary, not
# out of a published contract, and a build that lays them out differently must
# not blind this segment for a third time. A directory that does not exist
# costs one failed enumeration, so keeping the legacy candidate is nearly free
# and dropping it could only ever lose an install.
#
# WHAT IS STILL NOT MATCHED, stated rather than left to be discovered: a
# single-plugin marketplace sourced from its repo ROOT, where the checkout
# directory under marketplaces/ carries the MARKETPLACE's name and not the
# plugin's. No name glob can find that, and the structural probe that could -
# "does it contain lib/supervisor.ps1" - would also admit somebody else's
# plugin into GmConfig's search, which reads the FIRST config.json it finds. It
# does not need to be matched WHEN THE CACHE PATH RESOLVES, because the CLI
# loads the plugin from there and that path IS matched. That qualifier was
# missing until 3 August 2026 and the unqualified version was false in exactly
# the case the rest of this comment was written to fix.
#
# WHERE ELSE THIS LAYOUT IS SPELLED, AND WHY THERE ARE THREE (#8). The constant
# was wrong in two files at once because it was written out twice; it is now
# written out THREE times and they must be kept in step, so each names the
# others:
#
#   lib\common.ps1  Get-LwgMarketplaceInstall  the resolver, and the only one
#       that reads plugins\installed_plugins.json - the CLI's own record of what
#       it installed and where. Layout-independent, and it carries the install
#       SCOPE. Used by callers that can afford a dot-source and a
#       ConvertFrom-Json.
#   bin\lwg-setup.ps1  Get-Detection  a SUPERSET of both: registry first, then
#       cache, marketplaces, marketplaces\<mk>\plugins and legacy repos, each
#       narrowed to this plugin's name, with a sentence of evidence per hit
#       because its verdict decides whether a second set of hook registrations
#       is written.
#   HERE  candidate ROOTS rather than a verdict, because a reader can afford to
#       enumerate and filter where a writer cannot, and because this file
#       dot-sources nothing - see LwgClaudeHome for that measurement.
#
# A change to the layout has to land in all three. The layout itself is argued
# once, in lib\common.ps1's block above Get-LwgMarketplaceInstall.
#
# THE BASE OF THOSE PATHS IS NOT ALWAYS ~\.claude\plugins. CLAUDE_CODE_PLUGIN_CACHE_DIR
# relocates the whole plugins directory; the CLI reads it, and bin\lwg-setup.ps1
# reads it too - Get-Detection has honoured it since the detection probe was
# rewritten. This file did not, so the two halves of one repair disagreed on
# the same machine: with the install under a relocated cache, setup printed
# 'marketplace install: <relocated path>' and 'Claude Code can auto-discover
# it', while this segment rendered the purple NOT-INSTALLED glyph and GmConfig
# returned $null - silently replacing the operator's configured thresholds with
# the built-in numbers further down. Those are precisely the two symptoms the
# rewrite claimed to close, alive on a SUPPORTED relocation with no layout
# change at all.
#
# The variable is read the same way Get-Detection reads it - value if set,
# ~\.claude\plugins otherwise - and the default base is STILL scanned when it
# is set, because a machine can carry an older install at the default location
# and losing it is the failure this whole comment is about.
#
# Every candidate is kept rather than the first one that looks plausible, for
# the same reason LwgDataDirs keeps every match: the probes below take the first
# path that EXISTS, so a wrong guess earlier in the list costs a Test-Path, and
# a missing candidate costs the indicator.
#
# COST, measured on this machine rather than assumed, because this file renders
# on every assistant message. The two new scans use [IO.Directory] statics
# rather than Get-ChildItem - same answer, no provider dispatch and no PSObject
# per entry. Over 9 runs against 4 cache marketplaces and 7 marketplace
# checkouts: median 4.2 ms for the static spelling, 5.3 ms for the
# Get-ChildItem spelling of the same walk. Both are noise beside the ~178 ms
# the first Get-ChildItem in LwgDataDirs already pays.
function LwgPluginRoots {
    $roots = @()
    if ($env:CLAUDE_PLUGIN_ROOT) { $roots += [string]$env:CLAUDE_PLUGIN_ROOT }
    if ($PSScriptRoot) { $roots += [string](Split-Path -Parent $PSScriptRoot) }

    $glob = {
        param($base)
        $found = @()
        try {
            foreach ($c in @(Get-ChildItem -LiteralPath $base -Directory -Filter 'lw-watchtower*' -ErrorAction Stop |
                             Sort-Object LastWriteTime -Descending)) { $found += $c.FullName }
        } catch {}
        return $found
    }

    # Subdirectory paths matching a pattern, newest first, never throwing. A
    # missing base directory is the NORMAL case here - most machines have
    # neither of these trees - so it returns empty rather than raising.
    $dirs = {
        param($base, $pattern)
        $found = @()
        try {
            $found = @([IO.Directory]::GetDirectories($base, $pattern) |
                       Sort-Object -Property @{ Expression = { [IO.Directory]::GetLastWriteTimeUtc($_) } } -Descending)
        } catch {}
        return $found
    }

    # THE CONFIGURATION ROOT, not the profile - see LwgClaudeHome. Both the
    # skills directory and the plugins base live under it, and both moved with
    # it on a machine that sets CLAUDE_CONFIG_DIR while this file went on
    # looking under ~\.claude and finding nothing.
    $cfgHome = $claudeHome
    if (-not [string]::IsNullOrWhiteSpace($cfgHome)) {
        $roots += @(& $glob (Join-Path $cfgHome 'skills'))
    }

    # EVERY PLUGINS BASE TO SCAN, in the same order of authority Get-Detection
    # uses: the relocated one if CLAUDE_CODE_PLUGIN_CACHE_DIR names it, then the
    # default. BOTH, never one instead of the other - a machine that sets the
    # variable today may still carry an install written under the default base,
    # and dropping that candidate is the failure this file already had once.
    # Deduplicated, because setting the variable TO the default path is legal
    # and would otherwise scan everything twice on every assistant message.
    $bases = New-Object System.Collections.ArrayList
    if ($env:CLAUDE_CODE_PLUGIN_CACHE_DIR) { [void]$bases.Add([string]$env:CLAUDE_CODE_PLUGIN_CACHE_DIR) }
    if (-not [string]::IsNullOrWhiteSpace($cfgHome)) { [void]$bases.Add((Join-Path $cfgHome 'plugins')) }
    $baseSeen = @{}
    $pluginBases = @()
    foreach ($b in $bases) {
        $k = ([string]$b).TrimEnd('\', '/').ToLowerInvariant()
        if ($k -and -not $baseSeen.ContainsKey($k)) { $baseSeen[$k] = $true; $pluginBases += [string]$b }
    }

    foreach ($base in $pluginBases) {
        # cache/<marketplace>/lw-watchtower*/<version> - the installed root, and the one
        # the runtime actually loads. The version segment is NOT globbed on a name:
        # it is a version or a commit sha, and matching it on anything narrower
        # would be inventing a format the CLI never promised. Newest first, so the
        # most recently installed version leads when two are cached.
        foreach ($mk in @(& $dirs (Join-Path $base 'cache') '*')) {
            foreach ($pl in @(& $dirs $mk 'lw-watchtower*')) {
                $roots += @(& $dirs $pl '*')
            }
        }

        # marketplaces/<marketplace>/... - the repo checkout. The plugin may sit
        # directly inside it or under plugins/, which is where a multi-plugin
        # marketplace puts them.
        foreach ($mk in @(& $dirs (Join-Path $base 'marketplaces') '*')) {
            $roots += @(& $dirs $mk 'lw-watchtower*')
            $roots += @(& $dirs (Join-Path $mk 'plugins') 'lw-watchtower*')
        }

        # LEGACY, and still scanned - see the note above.
        $repos = Join-Path $base 'repos'
        $roots += @(& $glob $repos)
        try {
            foreach ($m in @(Get-ChildItem -LiteralPath $repos -Directory -ErrorAction Stop)) {
                $roots += @(& $glob $m.FullName)
            }
        } catch {}
    }

    $seen = @{}; $out = @()
    foreach ($p in $roots) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $k = ([string]$p).TrimEnd('\').ToLowerInvariant()
        if ($seen.ContainsKey($k)) { continue }
        $seen[$k] = $true; $out += $p
    }
    return $out
}
$gmPluginRoots = @(LwgPluginRoots)

# Health & Healing indicator.
#   green  HH   = supervisor installed, records read for this session, no faults
#   red    HHn  = one or more faults this session (count appended)
#   purple HH?  = supervisor or healer agent NOT FOUND among the candidate roots
#                 this file could resolve, so nothing can be determined at all
#
#                 "NOT FOUND" IS NOT "NOT INSTALLED", and this table said the
#                 second for both (#8). It was not a wording slip: on a
#                 marketplace install every root probe missed, this glyph
#                 rendered, and the table told the reader the plugin was not
#                 installed on a machine where it was installed and writing
#                 records. The probes below can only report what they resolved -
#                 CLAUDE_PLUGIN_ROOT, this script's parent, the skills glob, the
#                 plugins cache and marketplaces trees - and a root laid out
#                 somewhere none of them look is invisible to them, not absent.
#                 lib/gate_delegate.ps1 wrote this rule down first: "I COULD NOT
#                 FIND IT" IS NOT "IT IS NOT THERE".
#   purple HHx  = a log EXISTS and could not be read
#   dim    HH-  = nothing could be attributed to a session (unknown)
#   any    ...! = at least one log line was too large to read and was SKIPPED,
#                 so the glyph in front of it is drawn from less than the whole
#                 log. Colour is unchanged: the '!' is a completeness marker,
#                 not a fault, and inventing a fault out of an unreadable line
#                 would be the mirror of the false green it exists to prevent.
#
# EVERY STATE HAS ITS OWN SHAPE, and that is a rule rather than a preference:
# this repo's own principle is that nothing may be distinguished by COLOUR
# ALONE - a reader with a monochrome terminal, a colour vision deficiency or a
# log scraper sees the glyph and nothing else. Both purple states used to render
# a bare 'HH', character-for-character identical to the green all-clear, so on
# any such reader "the health system is not installed" and "this session is
# clean" were the same string. '?' and 'x' are what separate them now.
#
# Green and dim are DIFFERENT FACTS and the trailing '-' is what separates them,
# not the colour alone. Green means the logs were read and this session is clean.
# Dim means nothing about this session was found to read. An indicator that says
# "healthy" when it read nothing is worse than no indicator, so no-data gets its
# own glyph - dim, because an absence of evidence is not a fault and must not be
# alarming, but never the same shape as an all-clear.
#
# '?' AND 'x' ARE BOTH PURPLE AND MEAN DIFFERENT THINGS. '?' is "the machinery
# that would answer this question is absent" - nothing was read because there
# was nothing to read from. 'x' is "the machinery is here, a log is here, and it
# would not open" - which is a stronger statement and a more actionable one. It
# is also distinct from the trailing '!': '!' means some of the log was skipped
# and a verdict was still reached, 'x' means no verdict was reachable.
#
# Everything below the presence probes is scoped to the CURRENT session. The
# logs are shared append-only files that every session and
# every test run writes into, so a record that cannot be attributed to this
# session says nothing about this session. This filter used to be SKIPPED when
# the session id was falsy, which counted every fault in the 300-line tail of
# both logs and rendered a bogus red count. An unattributable record must never
# light the alarm and must never be read as health either, so no session id means
# DIM (unknown) - never red, never green.
#
# Phase 2 moved the supervisor into the LW-WATCHTOWER plugin. The presence probes take
# the first path that exists (every plugin root from LwgPluginRoots, then the
# pre-migration ~/.claude/health) so HH does not flip purple when the old copy is
# retired, and does not flip purple on a laptop whose install is a marketplace
# copy rather than a skills junction.
#
# The HEALER probe names agents/lw-healer.md, because that is the file this
# plugin actually ships. It once named a personal hq- spelling that existed in
# no install of the plugin, so on a clean machine with the plugin fully working
# and installed correctly HH rendered purple "not installed" permanently. The
# compatibility candidates for that spelling were removed on 31 July 2026, when
# the rename made it a name that no longer exists anywhere; a machine still
# holding a role file under the old name renders HH purple until it is renamed.
#
# The LOG, by contrast, is the UNION of every log that exists, not the first one.
# During the migration the locations can each hold part of the picture -
# whichever supervisor is bound writes to its own file - and reading only one of
# them renders HH green while a real unresolved fault sits in the other. A false
# green is the one failure mode this indicator must never have, so all of them
# are read and merged in timestamp order. Merging also used to let a Resolved
# marker written to one log clear a fault recorded in the other; nothing writes
# that marker any more - see the counting loop below - so the merge now exists
# for the union and for the cross-writer dedup alone.

# The last $keep usable lines of a log, read by seeking to the final $maxBytes
# and decoding only that as UTF-8. Returns a HASHTABLE - @{ lines; oversize;
# failed } - because PowerShell enumerates a returned collection and would
# unroll a bare pair away.
#
#   lines     the usable records, oldest first, at most $keep of them
#   oversize  how many lines were past $maxLine and were NOT returned
#   failed    the file exists and could not be read at all
#
# FileShare.ReadWrite, deliberately: this log is appended to by hooks while the
# status line renders, and a reader that will not share is a reader that
# intermittently reports nothing.
#
# The first line of the window is DROPPED whenever the window did not start at
# byte 0, because seeking lands mid-line and half a record is not a record. Same
# rule, and the same BOM handling, as Get-LwgTailLines in lib/common.ps1.
function TailWindow([string]$path, [int]$maxBytes, [int]$maxLine, [int]$keep) {
    $res = @{ lines = @(); oversize = 0; failed = $false }
    try {
        $fs = $null
        $buf = $null
        $read = 0
        $start = 0
        try {
            $fs = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            $len = $fs.Length
            if ($len -le 0) { return $res }
            $take = [int][Math]::Min([long]$maxBytes, $len)
            $start = $len - $take
            $buf = New-Object byte[] $take
            [void]$fs.Seek($start, [IO.SeekOrigin]::Begin)
            while ($read -lt $take) {
                $n = $fs.Read($buf, $read, $take - $read)
                if ($n -le 0) { break }
                $read += $n
            }
        } finally { if ($fs) { $fs.Dispose() } }

        $text = [Text.UTF8Encoding]::new($false).GetString($buf, 0, $read)
        # Get-Content strips a UTF-8 BOM; decoding bytes ourselves does not, and
        # a BOM on the front of line 1 makes ConvertFrom-Json reject that record.
        if ($start -eq 0 -and $text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
        # .Split on a char rather than -split: the latter is a regex, and the
        # first use of the regex engine in a fresh process costs more than the
        # read it is splitting.
        $all = $text.Split([char]10)
        $from = if ($start -gt 0) { 1 } else { 0 }

        $acc = New-Object 'System.Collections.Generic.List[string]'
        for ($i = $from; $i -lt $all.Length; $i++) {
            $l = $all[$i].TrimEnd([char]13)
            if ($l.Length -eq 0) { continue }
            if ($l.Length -gt $maxLine) { $res.oversize++; continue }
            [void]$acc.Add($l)
        }
        if ($acc.Count -gt $keep) { $res.lines = $acc.GetRange($acc.Count - $keep, $keep).ToArray() }
        else { $res.lines = $acc.ToArray() }
    } catch { $res.failed = $true }
    return $res
}

function HealthSeg($sessionId) {
    # The LEGACY ~/.claude/health tree below is composed off the resolved
    # configuration root, not off $env:USERPROFILE - see LwgClaudeHome. It is
    # allowed to be $null on a machine with no home at all, and every use of it
    # here is guarded rather than composed onto nothing.
    $home_ = $claudeHome
    # -LiteralPath, and it is load-bearing rather than tidiness. Every candidate
    # here is DERIVED - from $PSScriptRoot, from a glob over the plugins tree,
    # from $env:CLAUDE_PLUGIN_DATA - so it can carry any character a machine
    # allows. Without -LiteralPath the path is a WILDCARD PATTERN: a single '['
    # anywhere in it makes it a character class, the pattern matches nothing,
    # and Test-Path returns $false for a file that is on disk. Measured: an
    # existing config.json under a directory named with '[uat]' reads $false
    # bare and $true with -LiteralPath. A path Windows itself produces when a
    # folder is copied ('repo [2]') is enough. The false negative here renders
    # the purple HH? - NOT INSTALLED - about a working install.
    $first = {
        param($candidates)
        foreach ($p in $candidates) { if ($p -and (Test-Path -LiteralPath $p)) { return $p } }
        return $null
    }

    $supervisors = @()
    $healers     = @()
    foreach ($r in $gmPluginRoots) {
        $supervisors += (Join-Path $r 'lib\supervisor.ps1')
        $healers     += (Join-Path $r 'agents\lw-healer.md')
    }
    if (-not [string]::IsNullOrWhiteSpace($home_)) {
        $supervisors += (Join-Path $home_ 'health\supervisor.ps1')
        $healers     += (Join-Path $home_ 'agents\lw-healer.md')
    }

    $script = & $first $supervisors
    $healer = & $first $healers

    # 'HH?' and not a bare 'HH': see the glyph table. Purple alone cannot carry
    # this, because purple alone is invisible to a reader who has no colour.
    if (-not $script -or -not $healer) { return (Paint 35 'HH?') }

    $sid = [string]$sessionId
    if ([string]::IsNullOrWhiteSpace($sid)) { return (Paint 90 'HH-') }

    $logs = @()
    foreach ($dir in $gmDataDirs) { $logs += (Join-Path $dir 'health.jsonl') }
    if (-not [string]::IsNullOrWhiteSpace($home_)) { $logs += (Join-Path $home_ 'health\health.jsonl') }

    # THE READ IS BOUNDED, and both bounds are defensive on purpose: this file
    # reads logs it does not write, including logs written by an older copy of
    # the plugin and logs already on disk before the writer was capped.
    #
    # WHY NOT Get-Content -Tail, which is what this used to be. Its cost is
    # superlinear in LINE LENGTH, not in file size, and it is where essentially
    # the whole render went. Measured on this machine against a 300-record log:
    #
    #   oversized records | file size | Get-Content -Tail 300 | this reader
    #   0                 |    30.9 KB|                 19 ms |        1-3 ms
    #   1                 |   230.9 KB|              9,032 ms |        1-3 ms
    #   10                |     2.0 MB|             80,014 ms |        1-3 ms
    #
    # Whole-render medians over 5 runs each were 1,280 / 10,649 / 105,988 ms.
    # Filtering the lines AFTER the read fixed nothing, because the read had
    # already happened: the guard has to be in the read itself. This is the same
    # seek-and-decode reader as Get-LwgTailLines in lib/common.ps1, inlined
    # because this script is a settings.json command and deliberately
    # dot-sources nothing - see the header.
    #
    # It also fixes the encoding. Get-Content with no -Encoding reads ANSI in
    # Windows PowerShell 5.1 while every writer emits UTF-8, so a record naming
    # an accented path arrived mojibaked and its session id, if it held anything
    # outside ASCII, stopped matching.
    #
    # $maxBytes bounds the WINDOW: 1 MB holds 300 records several times over,
    # since every field a record carries is capped at 200 characters by
    # lib/supervisor.ps1 and a whole record runs to a couple of kilobytes.
    # $maxLine bounds one RECORD, and 8192 is lib/common.ps1's
    # $script:LwgMaxLogLineChars repeated as a literal. If one moves, both move.
    #
    # An oversized line is SKIPPED, not truncated-then-parsed: truncated JSON
    # does not parse, so "truncate and carry on" is skipping it with extra
    # steps. What must not happen is skipping it in SILENCE - a skipped record
    # could have been a fault, and a fault dropped on the floor renders green,
    # which is the one failure mode this indicator must never have. So skips are
    # counted and shown as a trailing '!': HH! / HH3! / HH-! all mean "and
    # something in the log was too large to read".
    $maxBytes = 1048576
    $maxLine  = 8192
    $keep     = 300
    $oversize = 0

    $records = @()
    foreach ($log in $logs) {
        # -LiteralPath, for the reason given at $first above: $log is built from
        # a data directory this process did not choose, and a bracket in it
        # makes the log invisible rather than absent.
        if (-not (Test-Path -LiteralPath $log)) { continue }
        $w = TailWindow $log $maxBytes $maxLine $keep
        # Parity with the -ErrorAction Stop this replaced: a log that exists and
        # cannot be read is not evidence of health and never renders as such.
        if ($w.failed) { return (Paint 35 'HHx') }
        $oversize += [int]$w.oversize
        foreach ($line in $w.lines) {
            try { $r = $line | ConvertFrom-Json } catch { continue }
            if ([string]$r.session -ne $sid) { continue }
            # which file it came from - the cross-writer dedup below needs it
            $records += ($r | Add-Member -NotePropertyName _src -NotePropertyValue $log -Force -PassThru)
        }
    }

    # Counted across every log, including records belonging to other sessions:
    # the session filter runs AFTER the parse, so an unreadable line cannot be
    # attributed to a session at all and "not mine" is not something that can be
    # established about it.
    $mark = if ($oversize -gt 0) { '!' } else { '' }

    # NOT green. Zero records is "nothing was found to read about this session",
    # which is not the same fact as "this session is clean" and must not look
    # like it. See the glyph table above.
    if ($records.Count -eq 0) { return (Paint 90 ('HH-' + $mark)) }

    $faults = 0
    # The newest Stop record's failed_tasks, carried rather than accumulated -
    # see the Stop arm below for why. Zero until a Stop record is seen. Nothing
    # resets it mid-session: it is a gauge, so the next Stop record overwrites
    # it, and until one arrives the last sample stands.
    $gauge  = 0
    # Tracked separately from $faults because it is a PEAK rather than a
    # running total - see the orphans branch below.
    $orphanPeak = 0
    # A union over the logs double-counts the migration window, when two bound
    # supervisors each saw one event and each wrote it into their OWN file:
    # session b484f1f6 holds an identical StopFailure pair 0.29s apart across two
    # logs and would otherwise render HH4 for 2 real faults.
    #
    # The dedup is therefore deliberately CROSS-FILE ONLY. Two matching records
    # in the SAME file are two events that writer genuinely recorded, and
    # collapsing them undercounts: session 42c716ab has two authentication_failed
    # StopFailures 0.11s apart in one log, and a same-file dedup silently turned
    # its real 5 into 4. Different file + within 2s + identical in everything but
    # the timestamp is the only combination that means "one event seen twice" -
    # the duplicate writers fire milliseconds apart, whereas the genuine repeats
    # in these logs are seconds to hours apart.
    $seenAt = @{}
    # ISO-8601 'o' timestamps sort correctly as plain strings, and every writer
    # uses that format, so this restores a single chronological stream.
    foreach ($r in ($records | Sort-Object { [string]$_.ts })) {
        $key = @($r.event, $r.tool_use_id, $r.agent_id, $r.error, $r.cwd, $r.description) -join '|'
        $when = [datetime]::MinValue
        if ([datetime]::TryParse([string]$r.ts, [ref]$when)) {
            $prev = $seenAt[$key]
            if ($prev -and $prev.src -ne $r._src -and ($when - $prev.at).Duration().TotalSeconds -lt 2) { continue }
            $seenAt[$key] = @{ at = $when; src = $r._src }
        }
        # THERE IS NO Resolved ARM, and its absence is the whole reason this
        # comment exists. One used to sit here and zero all three counters, so
        # red meant OUTSTANDING faults rather than faults ever seen. The only
        # writers of that record were bin/lwg-resolve.ps1 and lib/resolve.ps1,
        # both deleted, so the branch became unreachable code that read as a
        # live clearing mechanism. What it cost to remove is stated rather than
        # glossed: a log written BEFORE the deletion may still hold Resolved
        # records, and faults this reader once cleared on those sessions now
        # count. Such a record falls through every arm below untouched - it
        # carries no supervisor_error, no failed_tasks and no orphans - so it
        # is inert, never an error, and never a fault of its own.
        if ($r.supervisor_error) { $faults++; continue }
        if ($r.event -eq 'PostToolUseFailure' -and -not $r.is_interrupt) { $faults++; continue }
        # Stop.failed_tasks IS A GAUGE, NOT AN EVENT, so it is carried and not
        # accumulated. lib/supervisor.ps1 writes one Stop record at EVERY turn
        # end holding the number of background tasks that are in a failed/killed
        # state AT THAT MOMENT, and it writes it before its own alerted.json
        # dedupe - so the dedupe suppresses the repeated ALERT and never the
        # repeated RECORD. Summing that field counted one dead task once per
        # turn: HH1, then HH2, then HH3, for the rest of the session, with
        # nothing about the machine having got worse in between. The remedy the
        # operator is pointed at zeroes the count, and the number then came back
        # one higher on the next turn.
        #
        # The three arms around this one stay '++' because each of their records
        # IS one event that happened once.
        #
        # WHAT THIS DOES NOT FIX, and it is the reason to want failed_task_ids on
        # the record: two tasks failing in the same turn read as 2, which is
        # right, but a SECOND task failing three turns after the first while the
        # first is still outstanding also reads as 2 only because the writer
        # re-sampled - this reader cannot tell "the same task again" from
        # "another task", because the record carries a count and no ids. That
        # distinction is unreachable from here and needs the writer
        # (lib/supervisor.ps1) to name the tasks. bin/lwg-resolve.ps1:136 read
        # this field as a gauge while this file and bin/lwg-sitrep.ps1 did not,
        # and three readers of one log disagreeing about one number is the
        # divergence this plugin is named for. Those two readers are deleted;
        # this one is the last of the three and still reads it as a gauge.
        #
        # Records already on disk need no migration: the field always MEANT the
        # current count, and it is now read as one.
        # NO `continue` ON THE Stop ARM, deliberately. A Stop record carries
        # failed_tasks AND orphans in the SAME record, so continuing past this
        # line skipped the orphan branch below whenever both were non-zero - a
        # turn that lost a background task and a subagent reported only the
        # background task. Falling through costs nothing on every other record
        # shape: a record with no orphans field reads [int]$null = 0 and leaves
        # the peak untouched.
        if ($r.event -eq 'Stop') { $gauge = [int]$r.failed_tasks }
        if ($r.event -eq 'StopFailure') { $faults++; continue }
        # An agent that DIES MID-FLIGHT reaches none of the branches above: no
        # PostToolUseFailure, no StopFailure, and it never appears in
        # background_tasks, so failed_tasks stays 0. The only record of it is the
        # `orphans` count the supervisor's reconciliation writes - and until this
        # branch existed nothing read it, so on 10 August 2026 the supervisor
        # correctly detected two dead agents, correctly alerted, and HH STAYED
        # GREEN throughout.
        #
        # PEAK, NOT SUM, and that is load-bearing. An orphan stays orphaned, so
        # every later Stop and SubagentStop re-reports the SAME standing count;
        # adding them would inflate HH without bound. A peak counts each standing
        # death once. The honest limit, and it is larger now than it was: the
        # peak only ever rises within a session, so two orphans followed by one
        # new one still read 2, and NOTHING lowers it - the marker that used to
        # is gone with its writers. It over-reports rather than under-reports,
        # which is the correct direction for a fault indicator.
        #
        # READ `orphans_new` WHERE IT EXISTS, NOT `orphans`. An orphan is
        # STANDING - the dead transcript stays on disk - so `orphans` carries the
        # same count at every later trigger. Taking a peak of THAT was what made
        # a cleared HH turn red again on the next SubagentStop seconds later,
        # back when clearing existed at all. `orphans` is still read as a
        # fallback for records written before `orphans_new` existed - without it,
        # upgrading would silently green out a log that legitimately reads red.
        $o = if ($null -ne $r.orphans_new) { [int]$r.orphans_new } else { [int]$r.orphans }
        if ($o -gt $orphanPeak) { $orphanPeak = $o }
    }
    # the newest Stop's gauge, added once, plus the peak standing orphan count
    $faults += $gauge
    $faults += $orphanPeak

    if ($faults -gt 0) { return (Paint 91 ("HH" + $faults + $mark)) }
    return (Paint 32 ('HH' + $mark))
}

# LW-WATCHTOWER config. Read-only, and read from whichever plugin root actually
# resolves - see LwgPluginRoots, which covers the junction install, the
# marketplace install and a checkout wherever it happens to live.
#
# The fallback used to be one author's private folder hierarchy spelled out in
# full. On any machine whose clone is somewhere else BOTH candidates missed and
# this returned $null. Its one remaining caller is the threshold block down in
# the assembly section, which then quietly uses its built-in numbers - so a
# private path here would have meant every machine but one silently ignoring the
# configured thresholds, which is the failure mode this whole file is written
# against.
#
# Returns $null when nothing is readable - callers must treat that as "unknown",
# never as "healthy".
#
# THIS FUNCTION OPENS A FILE, WHICH IS WHY IT CANNOT TAKE THE FIRST CANDIDATE IT
# CAN PARSE. The candidate list from LwgPluginRoots includes this script's own
# parent directory, and for the INSTALLED copy at ~/.claude/statusline.ps1 that
# parent is the PROFILE ROOT - so %USERPROFILE%\config.json, a file belonging to
# some other tool entirely, used to be read, parsed and used as this plugin's
# configuration, ahead of the real install. It only had to be valid JSON. A
# stranger's config with no thresholds block yielded a non-null $cfg, every
# `if ($cfg.thresholds...)` below was false, all four built-ins stood, and
# nothing anywhere said which file had been read; a stranger's config that
# happened to carry a `thresholds` key set the operator's warning levels from
# it. The candidate-list comment above LwgPluginRoots dismissed the profile
# candidate on the grounds that "every candidate is only ever used via
# Test-Path", which was false about this function and has been corrected there.
#
# TWO TESTS, AND NEITHER IS PROOF OF OWNERSHIP - stated plainly because the
# temptation is to read them as one. (1) A plugin MARKER must sit beside the
# file, so a bare directory that merely happens to contain a config.json cannot
# win: the profile root has neither .claude-plugin\plugin.json nor
# lib\supervisor.ps1, and that alone removes the case above. (2) The parsed
# object must carry a `modules` or a `thresholds` member, which is the shape of
# this plugin's config. Another plugin's root satisfying (1) and shipping a
# config.json with a `modules` key would still be accepted - that is not
# reachable through this candidate list today, and it is a heuristic rather
# than an identity check either way.
#
# Test-Path takes -LiteralPath here for the same reason as the probes in
# HealthSeg: a bracket in a derived path makes the file invisible, and the
# Get-Content immediately below already had it while the guard in front of it
# did not, so the correct read was gated on an incorrect test.
function GmConfig {
    foreach ($r in $gmPluginRoots) {
        $marked = (Test-Path -LiteralPath (Join-Path $r '.claude-plugin\plugin.json')) -or
                  (Test-Path -LiteralPath (Join-Path $r 'lib\supervisor.ps1'))
        if (-not $marked) { continue }
        $p = Join-Path $r 'config.json'
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $o = $null
        try { $o = ((Get-Content -LiteralPath $p -Raw -ErrorAction Stop) | ConvertFrom-Json) } catch { continue }
        if ($null -eq $o) { continue }
        if ($null -eq $o.PSObject.Properties['modules'] -and
            $null -eq $o.PSObject.Properties['thresholds']) { continue }
        return $o
    }
    return $null
}

# --- the GM segment, and the trip ledger it read: BOTH REMOVED --------------
# GM rendered this plugin's own governance state, and its only live input was
# the per-session trip ledger trips-<sessionkey>.json. Both gates were removed
# on 30 July 2026, so nothing could write a trip; the ledger FILES themselves
# were removed the same day, backed up first, by an explicit owner decision.
#
# The segment was deleted rather than left standing, because by then it could
# report exactly one thing. GmState returned early on "no ledger found", so with
# no ledger anywhere on disk the only reachable state was 'none' and the only
# reachable glyph was the dim 'GM-'. An indicator that can only ever render one
# value is the permanently uninformative indicator this whole file is written
# against - the same defect as the 25-line log tail GM once used, arrived at
# from the other side. HealthSeg still reports faults; nothing else was lost.
#
# RE-ADDING A GATE MEANS REBUILDING THE LEDGER. lib/trips.ps1 is gone too, so
# the format, the writer there and the reader here all have to come back
# together - see docs/gates-removed.md, which is the record of what that costs.

# resets_at is unix-epoch seconds (header path) or ISO-8601 (cache path); returns local DateTime
function ResetTime($v) {
    if ($null -eq $v) { return $null }
    if ($v -is [string]) {
        if ($v -match '^\d+(\.\d+)?$') { return $EPOCH.AddSeconds([double]$v).ToLocalTime() }
        $dt = [datetime]::MinValue
        # INVARIANT, and RoundtripKind. The value on this branch is ISO-8601
        # written by the CLI, so parsing it under whatever culture the machine
        # happens to run is the same class of defect as formatting under one -
        # see Stamp. RoundtripKind is what preserves the offset the string
        # carries instead of flattening it, so a 'Z' stamp converts rather than
        # being read as a local wall clock.
        if ([datetime]::TryParse($v, [Globalization.CultureInfo]::InvariantCulture,
                                 [Globalization.DateTimeStyles]::RoundtripKind, [ref]$dt)) { return $dt.ToLocalTime() }
        return $null
    }
    return $EPOCH.AddSeconds([double]$v).ToLocalTime()
}

# "2h34m" / "45m" / "3d4h" - Floor, because [int] rounds in PowerShell
function Duration([datetime]$when) {
    $t = $when - (Get-Date)
    if ($t.TotalSeconds -le 0) { return 'now' }
    if ($t.TotalDays  -ge 1) { return ('{0}d{1}h'   -f [int][Math]::Floor($t.TotalDays),  $t.Hours) }
    if ($t.TotalHours -ge 1) { return ('{0}h{1:00}m' -f [int][Math]::Floor($t.TotalHours), $t.Minutes) }
    return ('{0}m' -f [int][Math]::Floor($t.TotalMinutes))
}

# Ago() - "4h ago" from an ISO-8601 stamp - lived here. Its only caller was the
# outstanding-trip advisory row, and it went with the GM segment above.

# "07/31 3pm" / "07/31 3:45pm"
#
# INVARIANT CULTURE, AND THE SEPARATORS ARE ESCAPED. Both are load-bearing on a
# non-English Windows, and this is the one segment on the row whose whole job is
# to say WHEN a limit resets.
#
#   * 'tt' resolves to the CURRENT culture's AM/PM designator, and the .Replace
#     fixup below only fires when that string is literally 'AM' or 'PM'. Under
#     Windows PowerShell 5.1 - the interpreter this file declares and the one
#     bin/lwg-setup.ps1 and docs/install.md both wire the status line to - 48
#     specific cultures have an EMPTY designator. Measured on this machine:
#     de-DE, sv-SE and nl-NL render '07.31 3:45' with nothing after it, so the
#     reset time is ambiguous by twelve hours. ja-JP renders '3:45<PM in
#     Japanese>' where this code believes it wrote 'pm'. (A .NET 5+/ICU
#     enumeration reports zero such cultures, which is why this was previously
#     ruled out; 5.1 is the runtime that matters here.)
#   * '/' and ':' inside a CUSTOM format string are not literals. They are the
#     culture's date and time separators, which is why six of the eight cultures
#     measured moved the date separator to '.' or '-'.
#
# Quoting them makes them literal and the invariant culture makes 'tt' English,
# after which the fixup is sound. The 12-hour clock is kept rather than switched
# to 24-hour: the format is documented above and on the row, and changing it is
# a display decision rather than a correctness one.
function Stamp([datetime]$when) {
    $fmt = if ($when.Minute -eq 0) { "MM'/'dd htt" } else { "MM'/'dd h':'mmtt" }
    ($when.ToString($fmt, [Globalization.CultureInfo]::InvariantCulture)).Replace('AM', 'am').Replace('PM', 'pm')
}

# $mode: 'in' = time until reset, 'at' = wall-clock reset time
#
# THREE STATES, and they are three different shapes:
#   '5h --'  absent   - no rate-limit block, or no used_percentage in it
#   '5h 42%' usable
#   '5h ??'  present and UNUSABLE - purple, the same colour the HH? glyph uses
#            for "the answer could not be determined". This was a green bare '%'
#            with no digits until 3 August 2026, which is the false all-clear
#            the HH glyph table is written against, reached from the numeric
#            side. See AsNum.
function Pct([string]$label, $lim, [string]$mode) {
    if ($null -eq $lim) { return (Paint 90 "$label --") }
    $n = AsNum $lim.used_percentage
    if ($null -eq $n)      { return (Paint 90 "$label --") }
    if ($n -isnot [double]) { return ((Paint 90 "$label ") + (Paint 35 '??')) }
    $u = Whole $n
    $s = (Paint 90 "$label ") + (Paint (Heat $u) ('{0:0}%' -f $u))
    $r = ResetTime $lim.resets_at
    if ($r) {
        $txt = if ($mode -eq 'at') { Stamp $r } else { Duration $r }
        $s += Paint 90 " ($txt)"
    }
    return $s
}

# Orchestrator mode: green when the main thread is delegation-only, dim when not.
function OrcSeg($agentName) {
    if ($agentName -match '^(lw-)?orchestrator$') { return (Paint 32 'ORC') }
    if ($agentName) { return (Paint 33 ('@' + $agentName)) }
    return (Paint 90 'ORC')
}

# Branch / worktree. '#' is the marker - plain ASCII, renders in every console.
# git_worktree is a path, so its leaf is used; Split-Path on a bare name is a
# no-op and never touches the filesystem.
function BranchSeg($payload) {
    $b = $null
    if ($payload.worktree.branch) { $b = [string]$payload.worktree.branch }
    elseif ($payload.workspace.git_worktree) {
        try { $b = Split-Path ([string]$payload.workspace.git_worktree) -Leaf } catch { $b = $null }
    }
    if ([string]::IsNullOrWhiteSpace($b)) { return $null }
    $s = Paint 94 ('#' + $b)
    if ($payload.worktree.name) { $s += Paint 90 (' [wt:' + $payload.worktree.name + ']') }
    return $s
}

# Open PR for this branch. Omitted entirely when the payload has no pr block.
function PrSeg($pr) {
    if ($null -eq $pr -or $null -eq $pr.number) { return $null }
    $s = Paint 95 ('PR#' + $pr.number)
    $st = ([string]$pr.review_state).ToUpper()
    if ($st) {
        if     ($st -match 'APPROVED')        { $s += Paint 32 ' ok' }
        elseif ($st -match 'CHANGES')         { $s += Paint 91 ' chg' }
        elseif ($st -match 'REVIEW_REQUIRED') { $s += Paint 33 ' rev' }
        elseif ($st -match 'DISMISSED')       { $s += Paint 33 ' dis' }
        elseif ($st -match 'COMMENTED')       { $s += Paint 90 ' cmt' }
        else                                  { $s += Paint 90 (' ' + $st.ToLower()) }
    }
    return $s
}

# walk up from $start to the .git dir, return its path
function GitDir([string]$start) {
    $dir = $start
    for ($i = 0; $i -lt 12 -and $dir; $i++) {
        $g = Join-Path $dir '.git'
        if (Test-Path -LiteralPath $g) {
            # a worktree/submodule has a .git FILE holding "gitdir: <path>"
            #
            # -Encoding UTF8, for the reason TailWindow gives about the health
            # log: Get-Content with no -Encoding reads ANSI in Windows
            # PowerShell 5.1 (Windows-1252 here) and git writes this file as
            # UTF-8. The value is a FILESYSTEM PATH, so on a profile with an
            # accented user name the decoded path does not exist, GitDir returns
            # a directory whose config fails the Test-Path below, RepoSlug
            # returns $null, and the row falls back to the dim leaf name - which
            # is also what a cwd outside any repo renders, so the failure is
            # indistinguishable from the normal case. In a worktree or submodule
            # this is the only read there is. -Encoding UTF8 also strips a BOM.
            if (Test-Path -LiteralPath $g -PathType Leaf) {
                $link = (Get-Content -LiteralPath $g -Raw -Encoding UTF8).Trim()
                if ($link -match '^gitdir:\s*(.+)$') {
                    $g = $Matches[1].Trim()
                    if (-not [IO.Path]::IsPathRooted($g)) { $g = Join-Path $dir $g }
                }
            }
            return $g
        }
        $parent = Split-Path $dir -Parent
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

# owner/repo from the origin remote (or the first remote if origin is absent).
#
# The payload's workspace.repo block is spread in conditionally and is absent in
# ordinary sessions, so the slug cannot be taken from it alone - relying on the
# payload silently drops the org and leaves the segment as a dim bare directory
# name. Parsing .git/config is a couple of small file reads, no subprocess, and
# it is what actually resolves in practice.
function RepoSlug([string]$start) {
    if ([string]::IsNullOrWhiteSpace($start)) { return $null }
    $g = GitDir $start
    if (-not $g) { return $null }
    $cfgFile = Join-Path $g 'config'
    if (-not (Test-Path -LiteralPath $cfgFile)) { return $null }

    # -Encoding UTF8 for the same reason as the .git read in GitDir above. This
    # half is the cosmetic one - a GitHub owner or repo name cannot carry a
    # non-ASCII character, so it bites on a self-hosted remote or a local-path
    # remote - and it also stops a BOM left by another tool defeating the
    # '^\[remote' match on line 1.
    $section = ''; $urls = @{}
    foreach ($line in (Get-Content -LiteralPath $cfgFile -Encoding UTF8)) {
        $t = $line.Trim()
        if ($t -match '^\[remote\s+"(.+)"\]$') { $section = $Matches[1]; continue }
        if ($t -match '^\[')                   { $section = '';          continue }
        if ($section -and $t -match '^url\s*=\s*(.+)$') { $urls[$section] = $Matches[1].Trim() }
    }
    if (-not $urls.Count) { return $null }

    $url = if ($urls.ContainsKey('origin')) { $urls['origin'] } else { $urls[@($urls.Keys)[0]] }
    # SSH: git@host:owner/repo.git
    if ($url -match '^[^@]+@[^:]+:(?<o>[^/]+)/(?<r>.+?)(\.git)?/?$') { return "$($Matches.o)/$($Matches.r)" }
    # HTTPS: https://host/owner/repo.git
    if ($url -match '^[a-zA-Z]+://[^/]+/(?<o>[^/]+)/(?<r>.+?)(\.git)?/?$') { return "$($Matches.o)/$($Matches.r)" }
    return $null
}

# ---------------------------------------------------------------- assembly ---

$cfg = GmConfig

# LW-WATCHTOWER thresholds, with built-in fallbacks when NO CONFIG COULD BE
# IDENTIFIED AT ALL - which is a wider set of states than "unreadable", and the
# wording mattered.
#
# This line used to say "when the config is unreadable" and #8 is the issue that
# proves it false. On a marketplace install $gmPluginRoots came back EMPTY,
# GmConfig's loop never ran, and $cfg was $null - so every configured threshold
# was replaced by a built-in while the operator's config.json sat on disk
# perfectly readable and was never looked for. The comment described the one
# cause that was not happening. GmConfig returns $null for four different
# reasons and only one of them is a read failure:
#
#   no candidate root resolved       the state #8 is about
#   no config.json beside a root     nothing to read
#   the file does not parse          genuinely unreadable
#   it parses but is not ours        no `modules`, no `thresholds` - see
#                                    GmConfig's header on the profile-root
#                                    config.json belonging to another tool
#
# ALL FOUR ARE NOW SAID OUT LOUD on the advisory row, because #8's whole
# complaint about this block is that the substitution was SILENT. An operator
# who set thresholds.ratelimit.warn_pct to 70 and is being warned at 88 has no
# way to discover it from a status line that renders as though nothing were
# wrong.
#
# PRESENCE, NOT TRUTHINESS, and a checked parse. These four reads were bare
# `if ($cfg.thresholds...)` guards followed by a bare [double] cast, and each
# half dropped a legitimate configuration silently:
#
#   * `if` is a truthiness test in PowerShell, so a configured 0 is FALSY and
#     was discarded. 0 means "warn always" and it was the one value an operator
#     could not set. AsNum returning $null is now the only thing that means
#     absent.
#   * a non-numeric value - "80%" is the obvious thing to type in a file whose
#     key is named _pct - failed the cast under SilentlyContinue, so the
#     assignment did not happen, the built-in stood, and nothing anywhere said
#     so. The operator believed they were warned at 80 and were warned at 88.
#
# A rejected value is now NAMED on the advisory row. That is the only channel
# this file has; /lw-watchtower:doctor's config-registry check still reads nothing
# under `thresholds`, so a bad threshold is invisible to the doctor and this
# does not change that.
$T = @{ rl_warn = 88.0; rl_land = 92.0; ctx_warn = 75.0; ctx_crit = 90.0 }
$Tbad = @()
if ($cfg) {
    foreach ($k in @(
        @{ n = 'rl_warn';  v = $cfg.thresholds.ratelimit.warn_pct;     s = 'ratelimit.warn_pct' },
        @{ n = 'rl_land';  v = $cfg.thresholds.ratelimit.land_all_pct; s = 'ratelimit.land_all_pct' },
        @{ n = 'ctx_warn'; v = $cfg.thresholds.context.warn_pct;       s = 'context.warn_pct' },
        @{ n = 'ctx_crit'; v = $cfg.thresholds.context.critical_pct;   s = 'context.critical_pct' }
    )) {
        $p = AsNum $k.v
        if ($null -eq $p)     { continue }          # absent: the built-in is the right answer
        if ($p -is [double])  { $T[$k.n] = $p; continue }
        $Tbad += $k.s                               # present and unusable: say so
    }
}

# Persist before rendering. The order is deliberate: the write is wrapped so it
# cannot throw, and doing it first means a signal is recorded even if a later
# segment fails. It emits nothing - see WriteSignal's header on why a monitoring
# write must never be able to blank the row.
WriteSignal -Payload $d -Dirs $gmDataDirs

$model = if ($d.model.display_name) { $d.model.display_name } else { 'Claude' }
$ctx   = AsNum $d.context_window.used_percentage

$out = @()
$out += Paint 96 $model
$out += HealthSeg $d.session_id
$out += OrcSeg $d.agent.name
# $ctx is AsNum's three-way answer: $null absent, [double] usable, 'bad'
# present-and-unparseable. The third renders '??' in the same purple Pct uses,
# and never the green bare '%' it used to.
if ($null -eq $ctx)      { $out += Paint 90 'ctx --' }
elseif ($ctx -isnot [double]) { $out += (Paint 90 'ctx ') + (Paint 35 '??') }
else {
    $ctxWhole = Whole $ctx
    $out += (Paint 90 'ctx ') + (Paint (Heat $ctxWhole) ('{0:0}%' -f $ctxWhole))
}
$out += Pct '5h' $d.rate_limits.five_hour 'in'
$out += Pct '7d' $d.rate_limits.seven_day 'at'
$s = BranchSeg $d;                   if ($s) { $out += $s }
$s = PrSeg $d.pr;                    if ($s) { $out += $s }

# owner/repo. The payload block is cheapest but is only spread in conditionally,
# so .git/config is parsed whenever it is missing. A real slug is green; the dim
# bare directory name is the last resort, for a cwd that is not in a repo at all.
$dir = if ($d.workspace.current_dir) { $d.workspace.current_dir } else { $d.cwd }
$slug = $null
if ($d.workspace.repo.owner -and $d.workspace.repo.name) {
    $slug = "$($d.workspace.repo.owner)/$($d.workspace.repo.name)"
} elseif ($dir) {
    $slug = RepoSlug ([string]$dir)
}
if ($slug) { $out += Paint 92 $slug }
elseif ($dir) {
    try { $leaf = Split-Path ([string]$dir) -Leaf } catch { $leaf = $null }
    if ($leaf) { $out += Paint 90 $leaf }
}

# ---------------------------------------------------------------- advisories --
# Row 2 exists only when there is something to say. No advisories, no second row.

# EVERY COMPARISON HERE IS AGAINST THE ROUNDED VALUE, which is the number row 1
# printed and the number this row quotes back. They were made against the raw
# double while both rows printed '{0:0}', so ctx 89.6 printed "90%" - the figure
# config.json calls critical_pct - in yellow, beside "plan for compaction". See
# Whole.
#
# A percentage that arrived and would NOT parse gets its own advisory rather
# than silence. Under the old bare cast the value failed the $null guard's
# purpose entirely: the guard was passed, the cast failed under
# SilentlyContinue, $u stayed $null, and `$null -ge 92` and `$null -ge 88` are
# both false - so an unreadable rate limit produced a green segment on row 1 and
# NO second row at all, which is the state this row uses to mean nothing is
# wrong.
$adv = @()
if ($null -ne $ctx) {
    if ($ctx -isnot [double]) { $adv += Paint 35 'ctx ?? - the payload figure would not parse' }
    else {
        $c = Whole $ctx
        if     ($c -ge $T.ctx_crit) { $adv += Paint 91 ('ctx {0:0}% CRITICAL - compact or hand off' -f $c) }
        elseif ($c -ge $T.ctx_warn) { $adv += Paint 33 ('ctx {0:0}% - plan for compaction' -f $c) }
    }
}
foreach ($rl in @(@{ n = '5h'; v = $d.rate_limits.five_hour }, @{ n = '7d'; v = $d.rate_limits.seven_day })) {
    if ($null -eq $rl.v) { continue }
    $n = AsNum $rl.v.used_percentage
    if ($null -eq $n) { continue }
    if ($n -isnot [double]) { $adv += Paint 35 ('{0} ?? - the payload figure would not parse' -f $rl.n); continue }
    $u = Whole $n
    if     ($u -ge $T.rl_land) { $adv += Paint 91 ('{0} {1:0}% - land all work' -f $rl.n, $u) }
    elseif ($u -ge $T.rl_warn) { $adv += Paint 33 ('{0} {1:0}% - approaching limit' -f $rl.n, $u) }
}
# A configured threshold that was read and could not be used. The built-in is in
# force and the operator is told which key was ignored - the alternative is the
# silent substitution this block used to make.
if ($Tbad.Count) {
    $adv += Paint 35 ('config thresholds.' + ($Tbad -join ', thresholds.') + ' is not a number - built-in in force')
}
# NO CONFIG AT ALL IS ALSO A SUBSTITUTION, AND IT WAS THE SILENT ONE (#8).
#
# The row above covers a value that was read and could not be used. It said
# nothing about the case where the file was never found - which is the case #8
# is actually about: on a marketplace install every plugin root probe missed,
# GmConfig returned $null, and all four built-ins stood while the operator's
# config.json sat on disk unread. Every threshold silently wrong, on every
# render, for the whole session.
#
# ONE ROW, NOT FOUR. Naming each threshold would be four advisories saying the
# same thing. What the operator needs is that NOTHING they configured is in
# force, and that is one fact.
#
# IT DOES NOT FIRE ON A HEALTHY MACHINE. GmConfig finds config.json beside any
# candidate root carrying a plugin marker, which every real install has - a
# junction, a marketplace cache root, a checkout. This row appearing means the
# thresholds on screen are not the thresholds in the file, which is exactly when
# an operator should be told.
if ($null -eq $cfg) {
    $adv += Paint 35 'no lw-watchtower config.json could be identified - all four built-in thresholds in force'
}
# The outstanding-trip advisory row was here. It named what was refused and where
# to go about it, and it was the row that had to survive a scrolling log. Nothing
# can be refused now and no ledger is left to read, so it says nothing and is
# gone; the GM tombstone above carries the reasoning.

$out -join (Paint 90 '  ')
if ($adv.Count) { (Paint 90 '! ') + ($adv -join (Paint 90 '  ')) }
