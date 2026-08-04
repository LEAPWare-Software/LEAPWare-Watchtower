#requires -version 5
<#
  LW-WATCHTOWER checklist - the plan, with every tick backed by something checkable.

      powershell -NoProfile -ExecutionPolicy Bypass -File bin\lwg-checklist.ps1

  Backs /lw-watchtower:checklist. The logic lives here rather than in the command's
  prose for the same reason lwg-doctor.ps1 does: a checklist a model fills in by
  reading instructions is a checklist that reports whatever the model infers, and
  an item ticked because somebody said so is precisely the defect this plugin
  exists to catch, in report form.

  NOTHING HERE MAY INVENT PROGRESS. Every state comes from bin\lwg-evidence.ps1
  running a probe - a commit reachable from a ref, a file on disk with expected
  content, a program's exit code, a CI conclusion via gh. There is deliberately
  no code path from "a record says this was done" to DONE.

  FIVE STATES, and the fifth is the point:

      DONE         a probe passed. The evidence is printed with it.
      IN PROGRESS  part of a required set exists, or a separate progress probe
                   passed, or CI says the run is still going.
      NOT STARTED  a probe RAN and found the thing absent.
      BLOCKED      a prerequisite item is not done, named; or checklist.json
                   declares a blocker, which is marked DECLARED because it is a
                   claim rather than an observation.
      UNVERIFIED   the probe could not run at all - no gh, no network, no git, no
                   automatable evidence. NOT a synonym for incomplete. An
                   unverified item may well be finished; this command simply has
                   no right to say either way.

  A DONE row that carries a caveat is marked `[x*]` rather than `[x]`, and its
  section heading says how many it holds. The state is unchanged and the caveat
  text is unchanged - both were always printed. What was missing is that a reader
  scanning the tick column never reached the caveat, so a section headed with a
  goal its own items say was not met read as met. The glyph is presentation, and
  it is the only thing here that is: no evidence rule and no state depends on it.

  Exit codes:

      0  the checklist rendered
      3  it could not be produced at all

  There is no exit code for "items are outstanding". This command reports; it
  does not judge. /lw-watchtower:doctor is the one that fails.
#>

$ErrorActionPreference = 'Stop'

# Everything printed is ASCII. A status report is the last thing that should
# depend on the console's encoding being right.
$Marks = @{
    'DONE'        = '[x]'
    'IN PROGRESS' = '[~]'
    'NOT STARTED' = '[ ]'
    'BLOCKED'     = '[!]'
    'UNVERIFIED'  = '[?]'
}

# A DONE row whose own caveat limits what the tick proves gets its own glyph.
# Every mark is padded to this width so the columns do not move between rows.
$MarkQualified = '[x*]'
$MarkWidth     = 4

try {
    $pluginRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $pluginRoot 'lib\common.ps1')
    . (Join-Path $PSScriptRoot 'lwg-evidence.ps1')

    # --- the manifest -------------------------------------------------------
    # A missing or broken manifest is exit 3, never an empty checklist. "There is
    # nothing to report" and "I could not read what to report on" are different
    # statements, and an empty green checklist is the worst of the two.
    $manifestPath = Join-Path $pluginRoot 'checklist.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        Write-Output "LW-WATCHTOWER checklist could not be produced: no checklist.json at $manifestPath"
        Write-Output 'That file is the source of truth for the item list. Without it there is no checklist, and nothing above or below should be read as one.'
        exit 3
    }
    $manifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    $items    = @($manifest.items)
    if ($items.Count -eq 0) {
        Write-Output "LW-WATCHTOWER checklist could not be produced: checklist.json parsed but declares no items"
        exit 3
    }

    # --- resolve every item -------------------------------------------------
    $ctx  = New-LwgEvidenceContext -PluginRoot $pluginRoot
    $rows = @(Resolve-LwgChecklist -Ctx $ctx -Items $items)

    # --- render -------------------------------------------------------------
    $idW = 3
    foreach ($r in $rows) { if ($r.Id.Length -gt $idW) { $idW = $r.Id.Length } }
    # Detail sits at a FIXED shallow indent rather than aligned under the title.
    # Aligning it looked tidier and pushed every evidence line past 130 columns,
    # where a terminal wraps it wherever it likes and the citation stops being
    # readable - which defeats the only reason the citation is printed.
    $lead = '        '

    # Which DONE rows are qualified by a caveat, counted per section BEFORE the
    # first line is printed. Resolve-LwgChecklist populates Caveat only on DONE
    # rows, so a non-empty Caveat IS the qualification - no second rule to keep
    # in step with the first.
    $qualBySection = @{}
    $qualTotal     = 0
    foreach ($r in $rows) {
        if (-not [string]::IsNullOrWhiteSpace($r.Caveat)) {
            $s = [string]$r.Section
            if (-not $qualBySection.ContainsKey($s)) { $qualBySection[$s] = 0 }
            $qualBySection[$s] = $qualBySection[$s] + 1
            $qualTotal++
        }
    }

    $now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm')
    Write-Output "LW-WATCHTOWER checklist - $([string]$manifest.plan_version)"
    # WHOSE PLAN THIS IS, SAID FIRST AND SAID EVERY TIME.
    #
    # checklist.json is the LW-WATCHTOWER project's own release plan. The whole
    # repository root is the plugin payload - .claude-plugin/marketplace.json
    # declares "source": "./" and that form has no exclusion - so the manifest
    # ships to every consumer, and commands/checklist.md tells the model to print
    # this output verbatim. A stranger who installs the plugin and runs the
    # obvious-looking command therefore gets forty rows of somebody else's audit,
    # every one of them formatted exactly like a finding about their own tree.
    #
    # Nothing about that is fixed by wording, and this banner does not pretend
    # otherwise: it is a disclosure, not a boundary. It is printed unconditionally
    # - not only when the manifest looks foreign, because there is no way to tell
    # - and above the rows rather than below them, because a caveat under forty
    # lines of output is read after the reader has already drawn a conclusion.
    Write-Output '  THIS IS THE LW-WATCHTOWER PROJECT''S OWN RELEASE PLAN. IT IS NOT A REPORT ON YOUR'
    Write-Output '  REPOSITORY. Every row below is a claim about this plugin''s development, derived'
    Write-Output '  from this plugin''s own files - not from the repository you are working in, and not'
    Write-Output '  from anything you have done. Nothing here is an action for you.'
    Write-Output "  $($rows.Count) items from checklist.json (tracked); evidence gathered $now UTC"
    # Printed on every run, including runs with no qualified rows, for the same
    # reason the UNVERIFIED sentence below is: a legend a reader only ever sees
    # when it applies is a legend they read as an error the first time it appears.
    Write-Output '  [x*] = DONE with a caveat that limits what the tick proves. Read the caveat, not the tick.'

    $section = $null
    foreach ($r in $rows) {
        if ($r.Section -ne $section) {
            $section = $r.Section
            $q = 0
            if ($qualBySection.ContainsKey([string]$section)) { $q = $qualBySection[[string]$section] }
            Write-Output ''
            if ($q -gt 0) {
                # The heading states a goal; the items under it are the only
                # evidence for that goal. Saying so at the heading is the whole
                # fix - the caveats themselves were already here and unchanged.
                Write-Output ("  {0}   <- {1} QUALIFIED item(s) below; this heading is NOT established by them" -f $section, $q)
            } else {
                Write-Output "  $section"
            }
        }
        $mark = $Marks[$r.State]
        if (-not $mark) { $mark = '[?]' }
        if (-not [string]::IsNullOrWhiteSpace($r.Caveat)) { $mark = $MarkQualified }
        Write-Output ('  {0} {1} {2}  {3}' -f $mark.PadRight($MarkWidth), $r.State.PadRight(11), $r.Id.PadRight($idW), $r.Title)
        foreach ($l in (Format-LwgWrapped -Text $r.Detail -Indent $lead)) { Write-Output $l }
        if (-not [string]::IsNullOrWhiteSpace($r.Caveat)) {
            foreach ($l in (Format-LwgWrapped -Text ("does NOT prove: " + $r.Caveat) -Indent $lead)) { Write-Output $l }
        }
    }

    # --- counts -------------------------------------------------------------
    $c = @{}
    foreach ($k in @('DONE', 'IN PROGRESS', 'NOT STARTED', 'BLOCKED', 'UNVERIFIED')) {
        $c[$k] = @($rows | Where-Object { $_.State -eq $k }).Count
    }
    Write-Output ''
    Write-Output ('  {0} done   {1} in progress   {2} blocked   {3} UNVERIFIED   {4} not started   ({5} items)' -f `
        $c['DONE'], $c['IN PROGRESS'], $c['BLOCKED'], $c['UNVERIFIED'], $c['NOT STARTED'], $rows.Count)

    # How much of the DONE count is qualified, said next to the count itself.
    # A total that reads "22 done" while a fifth of those rows carry a caveat is
    # the same misreading the glyph fixes, one line further down the report.
    Write-Output ("  {0} of those {1} DONE item(s) are QUALIFIED [x*]: the probe passed AND the caveat printed" -f $qualTotal, $c['DONE'])
    Write-Output '  beneath it limits what passing proves. A qualified tick is not the section heading met.'

    # The one sentence this report exists to prevent being misread. Printed on
    # every run, including runs where the count is zero, because a reader who
    # only ever sees it when it is non-zero learns to read it as an error.
    Write-Output "  UNVERIFIED is a third state, not a quieter 'not started': $($c['UNVERIFIED']) item(s) above"
    Write-Output '  could not be checked at all, and may or may not be finished. Do not count them either way.'

    # --- staleness of the source of truth -----------------------------------
    # WHERE THE PLAN PATH COMES FROM, AND WHY IT IS NO LONGER IN THE MANIFEST.
    #
    # checklist.json used to carry the plan file's literal path - directory AND
    # file name - under one user profile. That file is untracked and ships with
    # nothing, so the name was of no use to any reader; but the manifest ships to
    # every consumer, and this command printed the path on every run, so the name
    # reached the screen of everyone who installed the plugin. That is disclosure
    # with no beneficiary, which is the cheapest kind to remove.
    #
    # The capability it served did NOT go with it. `source_plan.path_env` names an
    # environment variable; the operator who actually holds the plan sets it on
    # that machine and drift is measured there exactly as before. Everywhere else
    # the variable is unset, the path is empty, and Measure-LwgPlanDrift returns
    # available=false with a reason - which is precisely what this command already
    # printed on every machine but one. The honest report of a gap is not the gap
    # being closed, and it was never claimed to be; see the manifest's own note.
    #
    # `path` is still read as a fallback so a maintainer-only checkout that wants
    # the literal back has a place to put it without a code change.
    $planEnv  = [string]$manifest.source_plan.path_env
    $planPath = ''
    if (-not [string]::IsNullOrWhiteSpace($planEnv)) {
        $planPath = [string][Environment]::GetEnvironmentVariable($planEnv)
    }
    if ([string]::IsNullOrWhiteSpace($planPath)) { $planPath = [string]$manifest.source_plan.path }

    $drift = Measure-LwgPlanDrift -PlanPath $planPath -Items $items
    Write-Output ''
    Write-Output '  SOURCE OF TRUTH: checklist.json, tracked in this repo. It is transcribed BY HAND from'
    if ([string]::IsNullOrWhiteSpace($planPath)) {
        Write-Output '  a plan file that is NOT tracked and does not ship. Its path is deliberately not'
        if (-not [string]::IsNullOrWhiteSpace($planEnv)) {
            Write-Output "  recorded in the manifest - set `$env:$planEnv on the machine that holds the plan"
            Write-Output '  to make drift measurable there.'
        } else {
            Write-Output '  recorded in the manifest, so drift cannot be measured from here.'
        }
    } else {
        Write-Output "  the plan at $planPath, which is not tracked and does not ship."
    }
    if (-not $drift.available) {
        Write-Output "  STALENESS NOT MEASURED: $($drift.why)."
        Write-Output '  So an item added to the plan and never transcribed here would be missing from the list'
        Write-Output '  above, and nothing on this machine can tell you that it is.'
    } else {
        $declared = [int]$manifest.source_plan.checkbox_count
        Write-Output ("  STALENESS MEASURED against the plan: {0} checkbox(es) across {1} section(s) today, against {2} recorded at transcription." -f `
            $drift.checkboxes, $drift.sections, $declared)
        if ($drift.checkboxes -ne $declared) {
            Write-Output ("  DRIFT: the plan has changed by {0} checkbox(es) since checklist.json was written. Items may be missing from this report." -f `
                ($drift.checkboxes - $declared))
        }
        if ($drift.missing.Count -gt 0) {
            Write-Output "  DRIFT: $($drift.missing.Count) plan section(s) have checkboxes but NO item here covers them:"
            foreach ($m in $drift.missing) { Write-Output "    - $m" }
        }
        if ($drift.checkboxes -eq $declared -and $drift.missing.Count -eq 0) {
            Write-Output '  No section drift: every plan section carrying a checkbox is represented above.'
        }
    }
    Write-Output '  A loosely written evidence rule is NOT detectable by any of this, which is why every'
    Write-Output '  DONE row prints the evidence it rests on - judge the rule, do not trust the tick.'

    exit 0

} catch {
    Write-Output "LW-WATCHTOWER checklist could not be produced: $($_.Exception.Message)"
    Write-Output 'Nothing above should be read as the state of the plan.'
    exit 3
}
