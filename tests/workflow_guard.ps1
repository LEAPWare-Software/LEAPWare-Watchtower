#requires -version 5
<#
  LW-WATCHTOWER workflow guard.

      powershell -NoProfile -ExecutionPolicy Bypass -File tests\workflow_guard.ps1

  WHY THIS FILE EXISTS

  A GitHub Actions workflow is the one tracked file in this repository that can
  execute arbitrary code on a machine nobody is watching. Three ways in, in
  descending order of how badly they end:

    * A SELF-HOSTED RUNNER. There are self-hosted runners registered on the
      maintainer's own machine. A workflow that names one - directly, through a
      runner group, or through a matrix value - hands anyone who can trigger
      that workflow code execution on hardware that is not a disposable VM. On
      a public or forkable repository the person who can trigger it is a
      stranger. This is the highest-severity item on the plan and it is the
      reason this file exists.
    * The `pull_request_target` TRIGGER. It runs the BASE branch's workflow
      with a read-write token and repository secrets, in the context of a pull
      request whose contents an untrusted author controls. Checking out and
      running the head ref under it is the canonical GitHub Actions
      privilege-escalation bug.
    * SECRETS. Nothing in this workflow needs a credential. Every secret
      reference that exists is a secret that can be printed, and one reachable
      from an untrusted trigger or a self-hosted runner is a secret already
      lost.

  WHAT IT REPLACED, AND WHY THAT MATTERED

  The evidence rule for this check used to be "the file .github\workflows\ci.yml
  CONTAINS THE STRING self-hosted". A comment satisfied it. So did the word
  appearing inside a workflow that actually used a self-hosted runner - the rule
  passed either way, and would have gone on passing while the thing it was
  named after was introduced. That is the precise class of control this project
  exists to refuse: one that reports a verified protection and checks nothing.

  HOW IT WORKS - IT PARSES, IT DOES NOT GREP

  Every file under .github\workflows\ is PARSED into a tree by the small YAML
  reader below - block mappings, block sequences, flow collections, quoted
  scalars and block scalars - and the rules are asked about the STRUCTURE:
  which key, in which job, holding which value, on which line. A grep-only
  check is defeated by reformatting; `runs-on:` written as a label array, as a
  `group:` mapping, or as a matrix reference is the same runner and three
  different lines of text.

  WHERE IT FALLS BACK TO TEXT, STATED RATHER THAN GLOSSED. Two rules also run a
  raw line sweep on top of the structural walk, and both sweeps are deliberately
  the conservative half of the rule:

    * `${{ secrets.* }}` is swept over every physical line, because an
      expression is a use of a secret wherever it is written and no structural
      position makes it safe.
    * `pull_request_target` is swept for as a token, so naming it in an `if:`
      or a comment-free expression is caught even where it is not the trigger
      key itself.

  Both sweeps skip COMMENT text, and that is the one place this check is
  deliberately not conservative: a comment cannot run, cannot read a secret and
  cannot select a runner. Comment lines inside a `run:` block scalar are NOT
  comments in this sense - they are script - so they are swept in full.

  ANYTHING THIS FILE CANNOT PARSE, OR CANNOT RESOLVE, IS A FAILURE. A YAML
  construct the reader does not implement, a `runs-on:` expression that does not
  resolve to a known GitHub-hosted label, a job with no determinable runner at
  all: each is reported and each fails the build. An unverifiable workflow is
  never reported as a clean one.

  PARSE-ONLY COVERAGE OF THE REST OF .github\

  The YAML files in .github\ that are not workflows - dependabot.yml and the
  issue-template files - are read by GitHub at run time and were read by nothing
  here. No count is given for them on purpose: it is a directory somebody adds a
  file to, and a number in this comment would be one more thing to go stale.
  The JSON step in ci.yml globs *.json, the PowerShell step globs *.ps1, and this file's
  enumeration was rooted at .github\workflows\, so a syntax error in any of the
  five reached main with a green build. One of the two failure modes is silent
  by design: an invalid dependabot.yml makes Dependabot simply stop running,
  with no build failure, no banner and no notification - and a broken issue form
  is discovered by a stranger who cannot file.

  So -AlsoParse defaults to .github\ (minus the workflow directory, already
  covered above), every .yml and .yaml under it is put through the same reader,
  and a file that does not parse is reported as `unparseable` and fails the
  build exactly as a workflow would. It reuses the reader rather than adding a
  dependency.

  PARSING IS NOT SCHEMA VALIDATION, and the difference is the whole limit of
  this. It catches a list item indented out of its sequence, an unclosed flow
  collection, a tab where YAML wants spaces. It does NOT catch a `type:` value
  GitHub does not recognise, a required key left out, or a `schedule:` cron
  GitHub rejects - those parse perfectly and are wrong. The rules are NOT
  applied to these files either: a `secrets:` key in an issue form means
  something else entirely, so reporting one would be a false positive.

  PROVED TO FIRE, WHICH IT HAD NEVER BEEN

  Until 3 August 2026 nothing in this repository ran this file against a
  workflow that violates any of its rules. checklist.json's P6-workflow-guard
  probe, the CI step and every invocation in CONTRIBUTING.md ran it over
  .github\workflows\ on a clean tree, where the expected answer is 0. So the
  branch that FIRES had no evidence behind it, on the rule this project's own
  documentation ranks highest-consequence and describes in four places as
  something that fails the build. That is the same standing the evidence rule
  this file REPLACED had: observed to pass, on a tree with nothing to find.

  -SelfTest closes that. It writes one deliberately violating workflow per rule
  into a throwaway directory under the temp root, re-invokes this file in a
  child process with -WorkflowDir pointed at it, and asserts the rule fired on
  the file and line it was planted on. It also asserts the two ends of the exit
  contract that no live run reaches: a clean fixture directory exits 0, and an
  empty or absent directory exits 2 rather than reporting an empty set as clean.
  Nothing real is touched; the fixtures are invented workflow files in a GUID
  directory, are never registered with GitHub and are deleted afterwards.

  WHAT -SelfTest ESTABLISHES, EXACTLY. Each rule fires on ONE shape of input.
  That is not the same as the rule being correct in general: the matrix branch
  is proved on a list of literal labels and NOT on an include: entry or a
  fromJSON, and the runner-label branch is proved on one unknown label and not
  on the whole space of spellings. A rule demonstrated to fire once is a floor.

  WHAT IT DOES NOT COVER, so nobody reads more into a green run than is there:

    * Composite actions (.github\actions\**\action.yml) and any action pulled
      from another repository. `uses: owner/repo@ref` runs code this scan never
      sees. THE DIGEST PIN LANDED for the one action this repository uses - see
      the comment above `- name: Check out` in ci.yml - but it is a property of
      that one line and NOT a rule here: a bare tag is a policy preference and
      this file's exit-1 contract is reserved for real violations. Nothing here
      checks that any `uses:` is pinned, and nothing here checks
      persist-credentials either.
    * Workflows on other branches. This scans the working tree it is run in.
    * SCHEMA of anything. The parse-only pass above establishes that a file is
      YAML, never that it is a valid issue form or a valid Dependabot config.
    * Everything a workflow can do that is not one of the rules below.

  EXIT CODES - a CI job reads these and nothing else.

      0  every workflow file parsed and no rule fired
      1  at least one hit, or at least one file that could not be parsed
      2  the scan ABORTED; the workflows were NOT checked, which is not the
         same as passing. An enumeration returning zero files is an abort,
         never an empty-set pass.

  No network. No writes of any kind. It opens workflow files for reading and
  prints.
#>
[CmdletBinding()]
param(
    # Repo root. Defaults to this file's parent, which is correct for a run from
    # anywhere as long as the file stays in tests\.
    [string]$Root,

    # The directory to scan. Defaults to .github\workflows under $Root. It is a
    # parameter so the guard can be pointed at a scratch copy holding injected
    # violations, which is how it is proved to catch anything at all - never
    # point it at anything you would mind being read.
    [string]$WorkflowDir,

    # Directories whose YAML is PARSED but NOT held to the nine rules. Defaults
    # to .github under $Root, minus the workflow directory already scanned. See
    # PARSE-ONLY COVERAGE in the header. Pass an empty array to turn it off.
    [string[]]$AlsoParse,

    # Drive this file against fixtures built to violate each rule, in a child
    # process, and assert it reports them. See PROVED TO FIRE in the header.
    # Not part of the normal scan and never run by it.
    [switch]$SelfTest,

    # Print the parsed shape of every file. For debugging the reader itself.
    [switch]$ShowTree
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
if ([string]::IsNullOrWhiteSpace($WorkflowDir)) {
    $WorkflowDir = Join-Path $Root '.github\workflows'
}

# ===========================================================================
# DETECTION RULES
#
#   id    short name used in the report and in allowlist scoping
#   name  what the rule is looking for, printed beside every hit
#   why   what it costs when this reaches main
# ===========================================================================
$Rules = @(
    @{
        id   = 'self-hosted-runner'
        name = 'a job that runs on a runner GitHub does not host'
        why  = 'a self-hosted runner is somebody''s real machine. A workflow that reaches one gives every person who can trigger that workflow code execution on it, with that machine''s filesystem, its credentials and its network. This rule does NOT look for the literal label self-hosted: it holds runs-on to a list of KNOWN GitHub-hosted labels and reports everything else, because a bare custom label like my-build-box is a self-hosted runner that never spells it out. A GitHub-hosted larger runner also carries an org-chosen label and is indistinguishable from here, so it is reported too - allowlist it with a reason if you genuinely have one.'
    }
    @{
        id   = 'runner-group'
        name = 'a runs-on group: selecting a runner by group rather than by label'
        why  = 'a runner group is a pool this scan cannot see into. Its membership is repository configuration, not a tracked file, so nothing in this tree can establish that the pool holds no self-hosted machine - and the pool can be changed without touching any file this scan reads.'
    }
    @{
        id   = 'runner-unresolvable'
        name = 'a runner this scan cannot pin to a known hosted image'
        why  = 'runs-on holds an expression that does not resolve here - a matrix key that is not declared, a vars./inputs./needs. reference, a fromJSON, or nothing at all - so the runner is decided somewhere this file cannot read. A runner that cannot be established is not a runner that has been cleared: it fails, by design.'
    }
    @{
        id   = 'matrix-self-hosted'
        name = 'a self-hosted runner reached indirectly through a matrix value'
        why  = 'runs-on: ${{ matrix.os }} is one line and says nothing. The label it resolves to is in the strategy block, and a single extra entry in a matrix list is the smallest possible diff that puts a job on somebody''s laptop.'
    }
    @{
        id   = 'pull-request-target'
        name = 'the pull_request_target trigger'
        why  = 'it runs the BASE branch''s workflow with a read-write token and this repository''s secrets, while the pull request''s author controls the head. Any checkout of the head ref under it, or any step that reads a file from it, is remote code execution with the repository''s own credentials.'
    }
    @{
        id   = 'secrets-expression'
        name = 'a ${{ secrets.* }} expression'
        why  = 'every secret reference is a secret that a step can print, a dependency can read, and a self-hosted runner can persist. This workflow needs none: the checks parse files and run local scripts. Adding one is a decision that needs stating, not a line that slips into a diff.'
    }
    @{
        id   = 'secrets-key'
        name = 'a secrets: key - a reusable-workflow call or an on.workflow_call declaration'
        why  = 'secrets: inherit hands the WHOLE secret store to a called workflow in one word, and an on.workflow_call.secrets block declares credentials this workflow expects to be handed. Both are secrets usage that carries no ${{ }} to grep for.'
    }
    @{
        id   = 'external-reusable-workflow'
        name = 'a job calling a reusable workflow from another repository'
        why  = 'the called workflow chooses its own runners and its own steps, in a file this scan cannot read and whose contents can change under a mutable ref. It is the indirect route to a self-hosted runner that leaves no trace in this repository at all. A LOCAL call - ./.github/workflows/x.yml - is fine and is not reported, because that file is scanned here too.'
    }
    @{
        id   = 'unparseable'
        name = 'a workflow file this scan could not parse or could not understand'
        why  = 'a file that did not parse was not checked. Reporting it as clean would be the empty-set pass this repository has been bitten by before, so it fails instead. If the construct is legitimate YAML that the reader below does not implement, extend the reader - do not exempt the file.'
    }
)

# ===========================================================================
# ALLOWLIST - ONE ENTRY, ADDED THE DAY A STEP NEEDED IT.
#
# It was empty from the day this file was written until 3 September 2026, and
# the schema sat here alone so that a future exemption would have a place to go
# and a shape to take rather than being invented under pressure.
#
#   id     name used in the report
#   rules  which detection rules it may excuse. '*' means any.
#   files  workflow file names it applies to, matched against the path relative
#          to the scanned directory with forward slashes. '*' means anywhere.
#   kind   which predicate decides it:
#            match-text  the matched text
#            line-text   the whole line the match sits on
#   test   the regex the predicate applies
#   why    one line, stating why this is legitimate rather than tolerated
#
# THE TWO KINDS ARE THE SAME PREDICATE TODAY, and that is recorded rather than
# left for whoever writes the second entry to discover. Add-LwgHit is handed the
# MATCHED text and never the line it sits on, so `line-text` currently applies
# its regex to exactly what `match-text` would. Making them differ means passing
# the raw line down to every call site, which is a change to a scanner nobody
# needed yet; until then, write `match-text`, which is the one that says what
# actually happens.
#
# THE POLICY, which matters more than the schema, and which the entry below was
# written to obey rather than to escape. `secrets.GITHUB_TOKEN` is the obvious
# candidate and it is still NOT pre-approved: the automatic token is a
# credential, and an entry added before a concrete step needs it is an entry
# nobody will re-read. Justify the specific use, on the entry, at the moment it
# is needed - and if the justification is "the scanner is annoying", fix the
# workflow.
#
# WHAT CHANGED ON 3 SEPTEMBER 2026. The premise of the old refusal was that this
# repository's workflow needs no credential: ci.yml's steps parse files and run
# local scripts, and its `permissions:` block already grants what they need. That
# is still exactly true of ci.yml, which reaches no secret and is covered by no
# entry here. It is not true of release.yml, which publishes a GitHub Release -
# a write to the repository through the API, with no spelling that needs no
# token. The alternative was `${{ github.token }}`: the same credential under a
# name this file does not sweep for, which would have left the exit-0 line saying
# no workflow reaches a secret while one did. A scanner that reports a
# protection it has stopped checking is the thing the header above says this
# file exists to refuse, so the honest spelling is in the workflow and the
# exemption is here, scoped to one rule, one file and one expression.
# ===========================================================================
$AllowList = @(
    @{
        id    = 'release-publish-token'
        rules = @('secrets-expression')
        files = @('release.yml')
        kind  = 'match-text'
        # Anchored, so it excuses the automatic per-run token and nothing else.
        # A second secret in that file - or this one under a different name -
        # is a violation and stays one.
        test  = '^\$\{\{\s*secrets\.GITHUB_TOKEN\s*\}\}$'
        why   = 'release.yml publishes a GitHub Release through the API, which no token-free spelling can do. It is the automatic per-run token, it is bound to the env: of the single publishing step, that step is gated on every check above it and on the ref being a tag, and its grant is the job-level contents: write beside it. Nothing else in this repository is handed a credential.'
    }
)

# ===========================================================================
# KNOWN GITHUB-HOSTED RUNNER LABELS
#
# The allowlist for runs-on, and the reason this rule is not a search for the
# string "self-hosted". A label that is not on this list is reported. That
# deliberately includes a label which is perfectly legitimate but new: adding a
# runner image here is a one-line, reviewable change, whereas the alternative -
# a rule that only catches runners polite enough to say `self-hosted` - catches
# nothing that matters.
#
# Qualifier labels (linux, x64, arm64 and friends) are absent on purpose. They
# only ever appear ALONGSIDE self-hosted in a label array, so leaving them out
# means such an array is reported once per label rather than once - noisier,
# and never wrong.
# ===========================================================================
$HostedRunners = @(
    'ubuntu-latest', 'ubuntu-24.04', 'ubuntu-22.04', 'ubuntu-20.04'
    'ubuntu-24.04-arm', 'ubuntu-22.04-arm'
    'windows-latest', 'windows-2025', 'windows-2022', 'windows-2019', 'windows-11-arm'
    'macos-latest', 'macos-15', 'macos-14', 'macos-13'
    'macos-latest-large', 'macos-15-large', 'macos-14-large', 'macos-13-large'
    'macos-latest-xlarge', 'macos-15-xlarge', 'macos-14-xlarge'
)
$HostedSet = @{}
foreach ($h in $HostedRunners) { $HostedSet[$h] = $true }

# ---------------------------------------------------------------------------
# SCALAR HELPERS
# ---------------------------------------------------------------------------

function Get-LwgIndent {
    <# Leading spaces. A leading TAB is not indentation in YAML and is reported
       by the caller rather than silently counted. #>
    param([string]$Text)
    $i = 0
    while ($i -lt $Text.Length -and $Text[$i] -eq ' ') { $i++ }
    return $i
}

function Remove-LwgYamlComment {
    <#
      Everything before an unquoted `#` that begins a comment - one at the start
      of the line, or one preceded by whitespace. Quote tracking matters: a `#`
      inside 'single' or "double" quotes is content. NEVER applied to a line
      inside a block scalar, where `#` is script, not a comment.
    #>
    param([string]$Text)
    $inS = $false; $inD = $false
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($inS) { if ($c -eq "'") { $inS = $false }; continue }
        if ($inD) {
            if ($c -eq '\') { $i++; continue }
            if ($c -eq '"') { $inD = $false }
            continue
        }
        if ($c -eq "'") { $inS = $true; continue }
        if ($c -eq '"') { $inD = $true; continue }
        if ($c -eq '#' -and ($i -eq 0 -or $Text[$i - 1] -eq ' ' -or $Text[$i - 1] -eq "`t")) {
            return $Text.Substring(0, $i)
        }
    }
    return $Text
}

function Expand-LwgScalar {
    <# A YAML scalar with its quotes removed. #>
    param([string]$Text)
    $t = $Text.Trim()
    if ($t.Length -ge 2 -and $t[0] -eq "'" -and $t[$t.Length - 1] -eq "'") {
        return $t.Substring(1, $t.Length - 2).Replace("''", "'")
    }
    if ($t.Length -ge 2 -and $t[0] -eq '"' -and $t[$t.Length - 1] -eq '"') {
        return $t.Substring(1, $t.Length - 2).Replace('\"', '"')
    }
    return $t
}

function Split-LwgKeyValue {
    <#
      Splits `key: value` at the first `:` that is followed by a space or ends
      the line, is outside quotes, and is outside any flow collection. Returns
      $null when the line is not a mapping entry - which is how `run: echo a: b`
      splits after `run` and not after `a`, and how a bare scalar or a flow
      sequence is recognised as a value rather than mistaken for a key.
    #>
    param([string]$Body)
    $depth = 0; $inS = $false; $inD = $false
    for ($i = 0; $i -lt $Body.Length; $i++) {
        $c = $Body[$i]
        if ($inS) { if ($c -eq "'") { $inS = $false }; continue }
        if ($inD) {
            if ($c -eq '\') { $i++; continue }
            if ($c -eq '"') { $inD = $false }
            continue
        }
        if ($c -eq "'") { $inS = $true; continue }
        if ($c -eq '"') { $inD = $true; continue }
        if ($c -eq '[' -or $c -eq '{') { $depth++; continue }
        if ($c -eq ']' -or $c -eq '}') { $depth--; continue }
        if ($c -eq ':' -and $depth -eq 0 -and ($i -eq ($Body.Length - 1) -or $Body[$i + 1] -eq ' ')) {
            $k = $Body.Substring(0, $i).Trim()
            if ($k -eq '') { return $null }
            $v = ''
            if ($i -lt ($Body.Length - 1)) { $v = $Body.Substring($i + 1).Trim() }
            return @{ key = $k; value = $v }
        }
    }
    return $null
}

function Split-LwgFlowItems {
    <# Top-level comma split of a flow collection body, quotes and nesting respected. #>
    param([string]$Body)
    $items = New-Object System.Collections.ArrayList
    $depth = 0; $inS = $false; $inD = $false; $start = 0
    for ($i = 0; $i -lt $Body.Length; $i++) {
        $c = $Body[$i]
        if ($inS) { if ($c -eq "'") { $inS = $false }; continue }
        if ($inD) {
            if ($c -eq '\') { $i++; continue }
            if ($c -eq '"') { $inD = $false }
            continue
        }
        if ($c -eq "'") { $inS = $true; continue }
        if ($c -eq '"') { $inD = $true; continue }
        if ($c -eq '[' -or $c -eq '{') { $depth++; continue }
        if ($c -eq ']' -or $c -eq '}') { $depth--; continue }
        if ($c -eq ',' -and $depth -eq 0) {
            [void]$items.Add($Body.Substring($start, $i - $start))
            $start = $i + 1
        }
    }
    [void]$items.Add($Body.Substring($start))
    return @($items | Where-Object { $_.Trim() -ne '' })
}

# ---------------------------------------------------------------------------
# THE YAML READER
#
# A recursive-descent reader over the subset GitHub Actions actually accepts.
# State is script-scoped rather than passed by [ref] because Windows PowerShell
# 5.1 makes [ref] parameters on nested calls more error-prone than the scoping.
#
# Node shapes, all hashtables:
#   @{ t='map';    line; entries=@(@{ key; keyLine; value }) }
#   @{ t='seq';    line; items=@(node) }
#   @{ t='scalar'; line; value; raw }
#   @{ t='block';  line; lines=@(@{ n; text }) }     a | or > block scalar
#
# What it deliberately does NOT implement, each reported as `unparseable`
# rather than guessed at: anchors and aliases (&a / *a), merge keys (<<),
# multiple documents (---), and tab indentation. GitHub Actions rejects the
# first three outright, so a file using one is broken before this scan sees it.
#
# A DUPLICATE KEY IN ONE MAPPING IS ALSO `unparseable`, and it is a REFUSAL
# rather than a gap - see Add-LwgKeyOnce. The lookups below return the first
# entry for a key, so a mapping holding a key twice is one this reader cannot
# resolve; reporting it clean would be reporting on a file it did not fully
# read. That is not a hypothetical: a second `runs-on:` hid `self-hosted` from
# every rule, and a second `jobs:` hid a whole job, both measured against this
# guard before the check existed.
# ---------------------------------------------------------------------------

$script:PLines = @()
$script:PIdx = 0
$script:PErr = $null

function Add-LwgParseError {
    param([int]$Line, [string]$Message)
    [void]$script:PErr.Add(@{ line = $Line; msg = $Message })
}

function Add-LwgKeyOnce {
    <#
      A DUPLICATE KEY IN ONE MAPPING IS A PARSE ERROR, AND THAT IS THE ONLY
      HONEST ANSWER TO IT.

      Get-LwgMapValue and Get-LwgMapEntry walk `entries` and return the FIRST
      match. Before this, a mapping carrying the same key twice was parsed in
      full, stored in full, and then half-discarded at every lookup - so a job
      written

          runs-on: ubuntu-latest
          runs-on: self-hosted

      was reported `RESULT: 0 violation(s)`, `EXIT: 0`, with no parse error and
      no warning, for a tracked file whose text says `self-hosted`. CI then
      printed `workflow guard: PASS` and checklist.json rendered
      P6-workflow-guard DONE. The same thing one level up hid an entire second
      `jobs:` block. Measured against the unmodified guard, both.

      RETURNING THE LAST MATCH INSTEAD WOULD NOT BE A FIX. It moves which of
      the two values is invisible - the duplicate `jobs:` case would then hide
      a violation in the FIRST block rather than the second - and it invents an
      answer to a question the file does not answer. Whether GitHub Actions
      itself honours the first or the last is deliberately not claimed here and
      is not what this rests on: the guard must not report zero violations
      about a file it did not fully read. A contradictory file is REFUSED, and
      `unparseable` already fails the build, so every rule benefits at once
      without a tenth rule or a second exit code.

      SCOPED TO ONE MAPPING. $Seen is created per mapping, never script-wide:
      every job declares `runs-on:` and every step declares `run:`, so a check
      with a longer memory would condemn every workflow ever written, this
      repository's own ci.yml first.

      CASE-INSENSITIVE, DELIBERATELY, and it is the conservative direction
      rather than the correct-YAML one. YAML keys are case-sensitive, so
      `runs-on:` and `Runs-On:` are two different keys to GitHub. But `-eq` in
      the two lookups above is case-INSENSITIVE, so this reader cannot tell
      them apart and would hand back whichever came first for either spelling.
      A PowerShell hashtable is case-insensitive for string keys and therefore
      matches the lookups exactly: what is refused here is precisely the set of
      files the lookups cannot resolve. Narrowing this to ordinal without also
      fixing both lookups would put the two back out of step and reopen the
      hole for one spelling.

      THAT IS NOT LEFT AS AN ARGUMENT. The self-test's `dup-runs-on-case`
      fixture is the pin for it: swapping this set for an ordinal comparer was
      measured to leave every case green while `runs-on:` followed by
      `Runs-On: self-hosted` went back to exit 0. A property defended only in a
      comment is certified by nothing, which is the finding this file was fixed
      for in the first place.

      THE PRICE, STATED RATHER THAN DISCOVERED. Case-insensitivity is strictly
      conservative, so it refuses a file GitHub would accept: an `env:` block
      holding `Foo: 1` and `foo: 2` declares two genuinely distinct variables,
      and this reports it as a duplicate. That is the intended direction - the
      lookups cannot tell those two apart either, so the tree this reader built
      does not represent the file - and it costs nothing on this repository,
      where there are zero instances. Refusing a file that is fine is a build
      failure someone reads; passing a file that hides a self-hosted runner is
      not.
    #>
    param($Seen, $Key, [int]$Line)
    $k = [string]$Key
    if ($Seen.ContainsKey($k)) {
        Add-LwgParseError -Line $Line -Message (
            "duplicate key '$k' in one mapping - already declared on line $($Seen[$k]). " +
            'A key held twice means two values were parsed and every lookup can see only one of them, ' +
            'so this file cannot be read as written. It is refused rather than half-read.')
        return
    }
    $Seen[$k] = $Line
}

function Skip-LwgBlank {
    while ($script:PIdx -lt $script:PLines.Count -and $script:PLines[$script:PIdx].empty) { $script:PIdx++ }
}

function Test-LwgSeqMarker {
    param([string]$Body)
    return ($Body -eq '-' -or $Body.StartsWith('- '))
}

function ConvertTo-LwgInline {
    <# A value written on one line: a flow sequence, a flow mapping, or a scalar. #>
    param([string]$Text, [int]$Line)
    $t = $Text.Trim()
    if ($t -eq '') { return $null }

    if ($t.StartsWith('&') -or $t.StartsWith('*')) {
        Add-LwgParseError -Line $Line -Message "YAML anchor or alias '$t' - GitHub Actions does not support them and this reader does not resolve them"
        return @{ t = 'scalar'; line = $Line; value = $t; raw = $t }
    }

    if ($t.StartsWith('[')) {
        $close = $t.LastIndexOf(']')
        if ($close -lt 0) {
            Add-LwgParseError -Line $Line -Message 'flow sequence is not closed on its line - multi-line flow collections are not supported'
            return @{ t = 'scalar'; line = $Line; value = $t; raw = $t }
        }
        $items = @()
        foreach ($p in (Split-LwgFlowItems $t.Substring(1, $close - 1))) {
            $items += ,(ConvertTo-LwgInline -Text $p -Line $Line)
        }
        return @{ t = 'seq'; line = $Line; items = @($items | Where-Object { $null -ne $_ }) }
    }

    if ($t.StartsWith('{')) {
        $close = $t.LastIndexOf('}')
        if ($close -lt 0) {
            Add-LwgParseError -Line $Line -Message 'flow mapping is not closed on its line - multi-line flow collections are not supported'
            return @{ t = 'scalar'; line = $Line; value = $t; raw = $t }
        }
        $entries = @()
        # A flow mapping builds `entries` exactly as a block mapping does and is
        # read back through the same first-match lookups, so it is blind in the
        # same way: `runs-on: {group: hosted, group: self-hosted}` is one line
        # with two values and one of them invisible. Same refusal, same reason.
        $seenFlow = @{}
        foreach ($p in (Split-LwgFlowItems $t.Substring(1, $close - 1))) {
            $kv = Split-LwgKeyValue $p.Trim()
            if ($null -eq $kv) {
                $fk = (Expand-LwgScalar $p)
                Add-LwgKeyOnce -Seen $seenFlow -Key $fk -Line $Line
                $entries += ,@{ key = $fk; keyLine = $Line; value = $null }
            } else {
                $fk = (Expand-LwgScalar $kv.key)
                Add-LwgKeyOnce -Seen $seenFlow -Key $fk -Line $Line
                $entries += ,@{ key = $fk; keyLine = $Line
                                value = (ConvertTo-LwgInline -Text $kv.value -Line $Line) }
            }
        }
        return @{ t = 'map'; line = $Line; entries = @($entries) }
    }

    return @{ t = 'scalar'; line = $Line; value = (Expand-LwgScalar $t); raw = $t }
}

function Read-LwgBlockScalar {
    <#
      A `|` or `>` block: every following line that is blank or indented deeper
      than the KEY, taken raw. Raw is the point - the lines are shell or
      PowerShell script, and a `#` in them is a comment in that language, not
      in YAML. Each keeps its own physical line number so a hit inside a 40-line
      run: block reports the line it is actually on.
    #>
    param([int]$ParentIndent, [int]$KeyLine)
    $out = New-Object System.Collections.ArrayList
    while ($script:PIdx -lt $script:PLines.Count) {
        $r = $script:PLines[$script:PIdx]
        if (-not $r.rawEmpty -and $r.rawIndent -le $ParentIndent) { break }
        $r.inBlock = $true
        if (-not $r.rawEmpty) { [void]$out.Add(@{ n = $r.n; text = $r.raw }) }
        $script:PIdx++
    }
    return @{ t = 'block'; line = $KeyLine; lines = @($out) }
}

function Read-LwgNode {
    param([int]$MinIndent)
    Skip-LwgBlank
    if ($script:PIdx -ge $script:PLines.Count) { return $null }
    $r = $script:PLines[$script:PIdx]
    if ($r.indent -lt $MinIndent) { return $null }
    if (Test-LwgSeqMarker $r.body) { return Read-LwgSeq -Indent $r.indent }
    if ($null -ne (Split-LwgKeyValue $r.body)) { return Read-LwgMap -Indent $r.indent }
    $script:PIdx++
    return (ConvertTo-LwgInline -Text $r.body -Line $r.n)
}

function Read-LwgMap {
    param([int]$Indent)
    $entries = New-Object System.Collections.ArrayList
    $firstLine = 0
    # Per mapping, never script-scoped - see Add-LwgKeyOnce. A nested map gets
    # its own, because this function recurses through Read-LwgNode.
    $seenKeys = @{}
    while ($true) {
        Skip-LwgBlank
        if ($script:PIdx -ge $script:PLines.Count) { break }
        $r = $script:PLines[$script:PIdx]
        if ($r.indent -ne $Indent) { break }
        if (Test-LwgSeqMarker $r.body) { break }

        $kv = Split-LwgKeyValue $r.body
        if ($null -eq $kv) { break }
        if ($firstLine -eq 0) { $firstLine = $r.n }

        $key = Expand-LwgScalar $kv.key
        if ($key -eq '<<') {
            Add-LwgParseError -Line $r.n -Message 'YAML merge key (<<) - GitHub Actions does not support it and this reader does not resolve it'
        }
        $keyLine = $r.n
        Add-LwgKeyOnce -Seen $seenKeys -Key $key -Line $keyLine
        $val = $kv.value
        $script:PIdx++

        $value = $null
        if ($val -match '^[|>][+\-]?[0-9]*\s*$') {
            $value = Read-LwgBlockScalar -ParentIndent $Indent -KeyLine $keyLine
        } elseif ($val -ne '') {
            $value = ConvertTo-LwgInline -Text $val -Line $keyLine
        } else {
            Skip-LwgBlank
            if ($script:PIdx -lt $script:PLines.Count) {
                $peek = $script:PLines[$script:PIdx]
                if ($peek.indent -gt $Indent) {
                    $value = Read-LwgNode -MinIndent $peek.indent
                } elseif ($peek.indent -eq $Indent -and (Test-LwgSeqMarker $peek.body)) {
                    # A block sequence may sit at its parent key's own indent.
                    $value = Read-LwgSeq -Indent $Indent
                }
            }
        }
        [void]$entries.Add(@{ key = $key; keyLine = $keyLine; value = $value })
    }
    return @{ t = 'map'; line = $firstLine; entries = @($entries) }
}

function Read-LwgSeq {
    param([int]$Indent)
    $items = New-Object System.Collections.ArrayList
    $firstLine = 0
    while ($true) {
        Skip-LwgBlank
        if ($script:PIdx -ge $script:PLines.Count) { break }
        $r = $script:PLines[$script:PIdx]
        if ($r.indent -ne $Indent) { break }
        if (-not (Test-LwgSeqMarker $r.body)) { break }
        if ($firstLine -eq 0) { $firstLine = $r.n }

        $rest = ''
        if ($r.body.Length -gt 1) { $rest = $r.body.Substring(1) }

        if ($rest.Trim() -eq '') {
            $script:PIdx++
            [void]$items.Add((Read-LwgNode -MinIndent ($Indent + 1)))
        } else {
            # `- name: X` continues as a block starting at the column the value
            # begins in, so the sibling keys under it belong to the same item.
            # The record is rewritten in place and re-read from that column.
            $lead = Get-LwgIndent $rest
            $r.indent = $Indent + 1 + $lead
            $r.body = $rest.Trim()
            [void]$items.Add((Read-LwgNode -MinIndent $r.indent))
        }
    }
    return @{ t = 'seq'; line = $firstLine; items = @($items) }
}

function Read-LwgYaml {
    <# Parses one file's raw lines. Returns @{ root; errors; lines }. #>
    param([string[]]$RawLines)

    $recs = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $RawLines.Count; $i++) {
        $raw = $RawLines[$i]
        $stripped = (Remove-LwgYamlComment $raw).TrimEnd()
        $rawTrimEnd = $raw.TrimEnd()
        [void]$recs.Add([pscustomobject]@{
            n         = $i + 1
            raw       = $rawTrimEnd
            rawIndent = (Get-LwgIndent $rawTrimEnd)
            rawEmpty  = ($rawTrimEnd.Trim() -eq '')
            indent    = (Get-LwgIndent $stripped)
            body      = $stripped.Trim()
            empty     = ($stripped.Trim() -eq '')
            inBlock   = $false
        })
    }

    $script:PLines = @($recs)
    $script:PIdx = 0
    $script:PErr = New-Object System.Collections.ArrayList

    foreach ($r in $script:PLines) {
        if (-not $r.empty) {
            $head = $r.body
            if ($r.raw -match '^ *\t') {
                Add-LwgParseError -Line $r.n -Message 'tab used for indentation - YAML forbids it'
            }
            if ($head -eq '---' -or $head -eq '...') {
                Add-LwgParseError -Line $r.n -Message 'document marker - a multi-document workflow file is not supported by GitHub Actions or by this reader'
            }
        }
    }

    $root = $null
    if ($script:PLines.Count -gt 0) {
        $root = Read-LwgNode -MinIndent 0
        Skip-LwgBlank
        if ($script:PIdx -lt $script:PLines.Count) {
            $r = $script:PLines[$script:PIdx]
            Add-LwgParseError -Line $r.n -Message "content after the end of the document could not be parsed - check the indentation of '$($r.body)'"
        }
    }
    if ($null -eq $root) {
        Add-LwgParseError -Line 1 -Message 'the file holds no YAML document - an empty workflow file is a broken one'
    }

    return @{ root = $root; errors = @($script:PErr); lines = @($script:PLines) }
}

# ---------------------------------------------------------------------------
# TREE HELPERS
# ---------------------------------------------------------------------------

function Get-LwgMapValue {
    param($Node, [string]$Key)
    if ($null -eq $Node -or $Node.t -ne 'map') { return $null }
    foreach ($e in $Node.entries) { if ($e.key -eq $Key) { return $e.value } }
    return $null
}

function Get-LwgMapEntry {
    param($Node, [string]$Key)
    if ($null -eq $Node -or $Node.t -ne 'map') { return $null }
    foreach ($e in $Node.entries) { if ($e.key -eq $Key) { return $e } }
    return $null
}

function Get-LwgScalars {
    <#
      Every scalar under a node, flattened, each with the line it sits on.

      EVERY CALL SITE WRAPS THIS IN @(). PowerShell unrolls a one-element array
      on return, so a single scalar comes back as the bare hashtable - and
      .Count on a hashtable is its KEY COUNT, not 1, so an unwrapped
      `if ($x.Count -gt 0) { $x[0].line }` silently reads 2 and then indexes
      nothing. That defect reported a runner group at line 0 with its name
      missing before it was caught.
    #>
    param($Node)
    $out = @()
    if ($null -eq $Node) { return $out }
    switch ($Node.t) {
        'scalar' { $out += ,@{ text = $Node.value; line = $Node.line } }
        'block'  { foreach ($l in $Node.lines) { $out += ,@{ text = $l.text.Trim(); line = $l.n } } }
        'seq'    { foreach ($i in $Node.items) { $out += (Get-LwgScalars $i) } }
        'map'    { foreach ($e in $Node.entries) { $out += (Get-LwgScalars $e.value) } }
    }
    return $out
}

function Get-LwgMatrixValues {
    <#
      The declared values of one matrix key: the key's own list, plus anything
      an `include:` entry sets for it. `exclude:` is ignored on purpose -
      excluding a combination never removes a label from the pool of values a
      runs-on expression can take, and treating it as though it did would be
      the one direction of error this scan must not make.
    #>
    param($MatrixNode, [string]$VarName)
    $out = @()
    if ($null -eq $MatrixNode -or $MatrixNode.t -ne 'map') { return $out }
    foreach ($e in $MatrixNode.entries) {
        if ($e.key -eq $VarName) { $out += (Get-LwgScalars $e.value) }
        elseif ($e.key -eq 'include' -and $null -ne $e.value -and $e.value.t -eq 'seq') {
            foreach ($item in $e.value.items) {
                $v = Get-LwgMapValue -Node $item -Key $VarName
                if ($null -ne $v) { $out += (Get-LwgScalars $v) }
            }
        }
    }
    return $out
}

# ===========================================================================
# MAIN
# ===========================================================================

$sw = [Diagnostics.Stopwatch]::StartNew()
$hits = New-Object System.Collections.ArrayList
$seen = @{}
$allowedHits = New-Object System.Collections.ArrayList
$allowCount = @{}
foreach ($a in $AllowList) { $allowCount[$a.id] = 0 }
$scanned = 0
# Files put through the reader but NOT held to the rules - see PARSE-ONLY
# COVERAGE. Counted and reported separately so a reader of the summary line
# cannot mistake "parsed" for "checked".
$parsedOnly = 0
$aborted = ''

function Add-LwgHit {
    param([string]$File, [int]$Line, [string]$Text, [string]$Rule)
    $t = ([string]$Text).Trim()
    if ($t.Length -gt 140) { $t = $t.Substring(0, 137) + '...' }
    $dedupe = "$File|$Line|$Rule|$t"
    if ($seen.ContainsKey($dedupe)) { return }
    $seen[$dedupe] = $true

    $ruleDef = $Rules | Where-Object { $_.id -eq $Rule } | Select-Object -First 1
    foreach ($a in $AllowList) {
        if (($a.rules -notcontains '*') -and ($a.rules -notcontains $Rule)) { continue }
        $scoped = $false
        foreach ($g in $a.files) { if ($g -eq '*' -or $File -like $g) { $scoped = $true; break } }
        if (-not $scoped) { continue }
        $hit = $false
        switch ($a.kind) {
            'match-text' { $hit = ($t -match $a.test) }
            'line-text'  { $hit = ($t -match $a.test) }
            default      { throw "allowlist entry '$($a.id)' declares kind '$($a.kind)', which is not one of match-text / line-text" }
        }
        if ($hit) {
            $allowCount[$a.id]++
            [void]$allowedHits.Add([pscustomobject]@{ file = $File; line = $Line; text = $t; rule = $Rule; allowId = $a.id })
            return
        }
    }
    [void]$hits.Add([pscustomobject]@{
        file = $File; line = $Line; text = $t; rule = $Rule
        ruleName = $(if ($ruleDef) { $ruleDef.name } else { $Rule })
    })
}

function Test-LwgRunnerLabel {
    <#
      One runs-on label, resolved as far as this file can resolve it. `$Via`
      says how it was reached so a matrix hit reports as a matrix hit.
    #>
    param([string]$File, [string]$Label, [int]$Line, [string]$Via)
    $l = ([string]$Label).Trim()
    if ($l -eq '') {
        Add-LwgHit -File $File -Line $Line -Text '(empty runs-on label)' -Rule 'runner-unresolvable'
        return
    }
    $rule = $(if ($Via -eq 'matrix') { 'matrix-self-hosted' } else { 'self-hosted-runner' })
    if ($l -match '\$\{\{') {
        Add-LwgHit -File $File -Line $Line -Text $l -Rule 'runner-unresolvable'
        return
    }
    if ($HostedSet.ContainsKey($l.ToLowerInvariant())) { return }
    Add-LwgHit -File $File -Line $Line -Text $l -Rule $rule
}

function Test-LwgRunsOn {
    param([string]$File, $Node, $JobNode, [int]$JobLine)
    if ($null -eq $Node) {
        Add-LwgHit -File $File -Line $JobLine -Text '(job declares no runs-on and calls no reusable workflow)' -Rule 'runner-unresolvable'
        return
    }

    if ($Node.t -eq 'map') {
        # runs-on: { group: ..., labels: [...] }
        $grp = Get-LwgMapEntry -Node $Node -Key 'group'
        if ($null -ne $grp) {
            $gs = @(Get-LwgScalars $grp.value)
            $txt = $(if ($gs.Count -gt 0) { "group: $($gs[0].text)" } else { 'group:' })
            $ln = $(if ($gs.Count -gt 0) { $gs[0].line } else { $grp.keyLine })
            Add-LwgHit -File $File -Line $ln -Text $txt -Rule 'runner-group'
        }
        $lbl = Get-LwgMapEntry -Node $Node -Key 'labels'
        if ($null -ne $lbl) {
            foreach ($s in @(Get-LwgScalars $lbl.value)) {
                Test-LwgRunnerLabel -File $File -Label $s.text -Line $s.line -Via 'labels'
            }
        }
        if ($null -eq $grp -and $null -eq $lbl) {
            Add-LwgHit -File $File -Line $Node.line -Text '(runs-on mapping declares neither group nor labels)' -Rule 'runner-unresolvable'
        }
        return
    }

    $scalars = @(Get-LwgScalars $Node)
    if ($scalars.Count -eq 0) {
        Add-LwgHit -File $File -Line $JobLine -Text '(runs-on is empty)' -Rule 'runner-unresolvable'
        return
    }

    $matrix = Get-LwgMapValue -Node (Get-LwgMapValue -Node $JobNode -Key 'strategy') -Key 'matrix'
    foreach ($s in $scalars) {
        $txt = ([string]$s.text).Trim()
        $m = [regex]::Match($txt, '^\$\{\{\s*matrix\.([A-Za-z_][A-Za-z0-9_\-]*)\s*\}\}$')
        if ($m.Success) {
            $var = $m.Groups[1].Value
            $vals = @(Get-LwgMatrixValues -MatrixNode $matrix -VarName $var)
            if ($vals.Count -eq 0) {
                Add-LwgHit -File $File -Line $s.line -Text "$txt (matrix.$var declares no values this scan can read)" -Rule 'runner-unresolvable'
                continue
            }
            foreach ($v in $vals) {
                Test-LwgRunnerLabel -File $File -Label $v.text -Line $v.line -Via 'matrix'
            }
            continue
        }
        Test-LwgRunnerLabel -File $File -Label $txt -Line $s.line -Via 'direct'
    }
}

function Test-LwgSecretsKeys {
    <# Any map key literally named `secrets`, anywhere in the tree. #>
    param([string]$File, $Node)
    if ($null -eq $Node) { return }
    if ($Node.t -eq 'map') {
        foreach ($e in $Node.entries) {
            if ($e.key -eq 'secrets') {
                $detail = 'secrets:'
                $vs = @(Get-LwgScalars $e.value)
                if ($vs.Count -gt 0 -and $vs[0].line -eq $e.keyLine) { $detail = "secrets: $($vs[0].text)" }
                Add-LwgHit -File $File -Line $e.keyLine -Text $detail -Rule 'secrets-key'
            }
            Test-LwgSecretsKeys -File $File -Node $e.value
        }
    } elseif ($Node.t -eq 'seq') {
        foreach ($i in $Node.items) { Test-LwgSecretsKeys -File $File -Node $i }
    }
}

function Test-LwgTriggers {
    # $Doc, not $Root: the script parameter $Root is [string]-typed, and
    # PowerShell variable names are case-insensitive, so a node assigned to
    # anything spelled $root is silently stringified into
    # "System.Collections.Hashtable" and every lookup on it returns nothing.
    param([string]$File, $Doc)
    # `on` is parsed as the literal key here. A YAML 1.1 loader would fold it to
    # the boolean true, so both spellings are looked up rather than assumed.
    foreach ($k in @('on', 'true', 'True')) {
        $node = Get-LwgMapValue -Node $Doc -Key $k
        if ($null -eq $node) { continue }
        if ($node.t -eq 'map') {
            foreach ($e in $node.entries) {
                if ($e.key -eq 'pull_request_target') {
                    # The reported text is the bare token in all three places
                    # this can be found - trigger key, trigger list, raw sweep -
                    # so one occurrence dedupes to one line in the report
                    # instead of appearing twice with two spellings.
                    Add-LwgHit -File $File -Line $e.keyLine -Text 'pull_request_target' -Rule 'pull-request-target'
                }
            }
        }
        foreach ($s in @(Get-LwgScalars $node)) {
            if ($s.text -eq 'pull_request_target') {
                Add-LwgHit -File $File -Line $s.line -Text 'pull_request_target' -Rule 'pull-request-target'
            }
        }
    }
}

# ===========================================================================
# SELF-TEST
#
# Drives THIS FILE, in a real child process, against fixtures written to
# violate each rule. See PROVED TO FIRE in the header for why it exists and,
# more importantly, for the exact limit of what it establishes.
#
# TEST SAFETY. Every fixture is an invented workflow file written into one
# fresh GUID directory under [IO.Path]::GetTempPath(). No command in any of
# them is real, none is ever registered with GitHub, and the only directory
# anything here deletes is the one it created seconds earlier. It runs no
# destructive command and nothing elevated.
#
# It is behind a switch and the normal scan never reaches it. That is not
# tidiness: tests\doc_claims.ps1 decides which suites are BEHAVIOURAL by
# running each tests\*.ps1 with NO ARGUMENTS and matching `N of M case(s)` in
# the output. If this ran by default, this file would start reporting a case
# tally, the derived behavioural count would go from five to six, and every
# page in the tree stating five would fail.
# ===========================================================================
if ($SelfTest) {
    $self = $PSCommandPath
    $fx   = Join-Path ([IO.Path]::GetTempPath()) ("lwg-wfguard-selftest-" + [guid]::NewGuid().ToString('N'))

    function Add-LwgCase {
        param([string]$Name, [bool]$Ok, [string]$Why)
        $script:SelfResults += [pscustomobject]@{ Name = $Name; Ok = $Ok; Why = $Why }
        if ($Ok) { "  ok    $Name" } else { "  FAIL  $Name"; "        $Why" }
    }
    $script:SelfResults = @()

    function Invoke-LwgGuard {
        <# This file, in a child process, over one directory. Returns its
           stdout and its exit code. stderr is deliberately not merged: in
           Windows PowerShell 5.1 that wraps native stderr in
           NativeCommandError records and corrupts the result. #>
        # -AlsoParse is deliberately NOT passed. powershell.exe -File takes its
        # arguments as strings, so there is no way to hand it an empty array -
        # `-AlsoParse @()` arrives as a missing argument and the child dies
        # before it prints anything, which is how this was found. It does not
        # need to be passed: -WorkflowDir is not the default here, and the
        # default-resolution block below turns the .github pass off whenever
        # that is true, because this is fixture mode and .github is not the
        # subject then.
        param([string]$Dir)
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $self -WorkflowDir $Dir
        return [pscustomobject]@{ Out = ($out -join "`n"); Code = $(if ($null -eq $LASTEXITCODE) { 255 } else { $LASTEXITCODE }) }
    }

    # One fixture per rule. `expect` is the rule id the fixture is planted to
    # provoke; the case asserts THAT id is reported against THAT file, not
    # merely that something was.
    $fixtures = @(
        @{ file = 'r1-self-hosted.yml';  expect = 'self-hosted-runner'
           body = "name: fixture self hosted`non:`n  workflow_dispatch:`njobs:`n  build:`n    runs-on: [self-hosted, windows]`n    steps:`n      - name: Nothing`n        run: Write-Output fixture`n" }
        @{ file = 'r2-runner-group.yml'; expect = 'runner-group'
           body = "name: fixture runner group`non:`n  workflow_dispatch:`njobs:`n  build:`n    runs-on:`n      group: an-invented-pool`n    steps:`n      - name: Nothing`n        run: Write-Output fixture`n" }
        @{ file = 'r3-unresolvable.yml'; expect = 'runner-unresolvable'
           body = "name: fixture unresolvable`non:`n  workflow_dispatch:`njobs:`n  build:`n    runs-on: `${{ vars.INVENTED_RUNNER_LABEL }}`n    steps:`n      - name: Nothing`n        run: Write-Output fixture`n" }
        @{ file = 'r4-matrix.yml';       expect = 'matrix-self-hosted'
           body = "name: fixture matrix`non:`n  workflow_dispatch:`njobs:`n  build:`n    strategy:`n      matrix:`n        os: [windows-latest, an-invented-build-box]`n    runs-on: `${{ matrix.os }}`n    steps:`n      - name: Nothing`n        run: Write-Output fixture`n" }
        @{ file = 'r5-pr-target.yml';    expect = 'pull-request-target'
           body = "name: fixture pr target`non:`n  pull_request_target:`n    branches: [main]`njobs:`n  build:`n    runs-on: windows-latest`n    steps:`n      - name: Nothing`n        run: Write-Output fixture`n" }
        @{ file = 'r6-secret-expr.yml';  expect = 'secrets-expression'
           body = "name: fixture secret expression`non:`n  workflow_dispatch:`njobs:`n  build:`n    runs-on: windows-latest`n    steps:`n      - name: Nothing`n        env:`n          INVENTED: `${{ secrets.AN_INVENTED_TOKEN }}`n        run: Write-Output fixture`n" }
        @{ file = 'r7-secrets-key.yml';  expect = 'secrets-key'
           body = "name: fixture secrets key`non:`n  workflow_call:`n    secrets:`n      AN_INVENTED_TOKEN:`n        required: true`njobs:`n  build:`n    runs-on: windows-latest`n    steps:`n      - name: Nothing`n        run: Write-Output fixture`n" }
        @{ file = 'r8-external.yml';     expect = 'external-reusable-workflow'
           body = "name: fixture external reusable`non:`n  workflow_dispatch:`njobs:`n  call:`n    uses: an-invented-owner/an-invented-repo/.github/workflows/build.yml@main`n" }
        @{ file = 'r9-unparseable.yml';  expect = 'unparseable'
           body = "- this document is a sequence, not the mapping a workflow has to be`n" }
        # A DUPLICATE KEY IS A CONTRADICTION, AND THE READER MUST REFUSE IT
        # RATHER THAN PICK A HALF. Get-LwgMapValue and Get-LwgMapEntry return
        # the FIRST entry for a key, so before this was a parse error a second
        # `runs-on:` was parsed, stored, and then never looked at: the whole
        # rule set ran against the first value and reported the file clean
        # while its text said `self-hosted`. Returning the LAST entry instead
        # would not fix it - it would move which half is invisible, which is
        # why the fix is in the parser and not in the lookup.
        @{ file = 'r10-dup-runs-on.yml'; expect = 'unparseable'
           body = "name: fixture duplicate runs-on`non:`n  workflow_dispatch:`njobs:`n  build:`n    runs-on: ubuntu-latest`n    runs-on: self-hosted`n    steps:`n      - name: Nothing`n        run: Write-Output fixture`n" }
        # The same defect one level up: a second top-level `jobs:` hid an
        # ENTIRE job, self-hosted runner and all, behind a benign first one.
        @{ file = 'r11-dup-jobs.yml';    expect = 'unparseable'
           body = "name: fixture duplicate jobs`non:`n  workflow_dispatch:`njobs:`n  build:`n    runs-on: ubuntu-latest`n    steps:`n      - name: Nothing`n        run: Write-Output fixture`njobs:`n  build:`n    runs-on: self-hosted`n    steps:`n      - name: Nothing`n        run: Write-Output pwned`n" }
    )

    try {
        $null = New-Item -ItemType Directory -Path $fx -Force

        # --- the clean end of the contract, first --------------------------
        # A directory holding one valid workflow must exit 0. Without this case
        # a guard that reported every file as a violation would pass every case
        # below and still be useless.
        $clean = Join-Path $fx 'clean'
        $null = New-Item -ItemType Directory -Path $clean -Force
        Set-Content -LiteralPath (Join-Path $clean 'ok.yml') -Encoding ASCII -Value `
            "name: fixture clean`non:`n  workflow_dispatch:`njobs:`n  build:`n    runs-on: windows-latest`n    steps:`n      - name: Nothing`n        run: Write-Output fixture`n"
        $r = Invoke-LwgGuard -Dir $clean
        Add-LwgCase 'a clean fixture directory exits 0' ($r.Code -eq 0) `
            "expected exit 0, got $($r.Code). A guard that reports a clean workflow as a violation would satisfy every case below."
        Add-LwgCase 'a clean fixture directory reports zero violations' ($r.Out -match 'RESULT: 0 violation\(s\)') `
            "expected a RESULT line reporting 0 violations, got: $($r.Out)"

        # --- one violating fixture per rule --------------------------------
        $dirty = Join-Path $fx 'dirty'
        $null = New-Item -ItemType Directory -Path $dirty -Force
        foreach ($f in $fixtures) {
            Set-Content -LiteralPath (Join-Path $dirty $f.file) -Encoding ASCII -Value $f.body
        }
        $r = Invoke-LwgGuard -Dir $dirty
        Add-LwgCase 'a directory of violating fixtures exits 1' ($r.Code -eq 1) `
            "expected exit 1, got $($r.Code). Output: $($r.Out)"
        foreach ($f in $fixtures) {
            # Asserted on the FILE AND THE RULE together. `$($f.file)` alone
            # would pass if the file were reported under some other rule, which
            # is the shape of vacuous case this repository keeps finding in
            # itself - a hit that proves something fired but not that the right
            # thing did.
            $ok = ($r.Out -match ([regex]::Escape($f.file) + ':\d+:[^\r\n]*- ' + [regex]::Escape($f.expect) + ':'))
            Add-LwgCase ("rule {0} fires on {1}" -f $f.expect, $f.file) $ok `
                "no line reported $($f.file) under rule $($f.expect). Output: $($r.Out)"
        }

        # --- the duplicate key, ALONE in its own directory -----------------
        # The two fixtures above ride in $dirty alongside nine others that
        # already force exit 1, so `rule unparseable fires on r10` proves the
        # rule fired but NOT that this file alone would have failed the build.
        # That is the whole finding: a repository whose only workflow carries a
        # duplicate `runs-on:` was reported as `RESULT: 0 violation(s)`,
        # `EXIT: 0`, with no parse error and no warning, while its text said
        # `self-hosted`. CI printed `workflow guard: PASS` for it. So each
        # shape is also run on its own, and the assertion is the exit code the
        # build reads plus the file-and-rule line that says why.
        $dupPairs = @(
            @{ dir = 'dup-runs-on'; file = 'only.yml'; key = 'runs-on'
               what = 'a lone workflow whose job declares runs-on: twice, the second self-hosted'
               body = "name: only`non:`n  workflow_dispatch:`njobs:`n  build:`n    runs-on: ubuntu-latest`n    runs-on: self-hosted`n    steps:`n      - name: Nothing`n        run: Write-Output fixture`n" }
            @{ dir = 'dup-jobs'; file = 'only.yml'; key = 'jobs'
               what = 'a lone workflow with two top-level jobs: blocks, the second self-hosted'
               body = "name: only`non:`n  workflow_dispatch:`njobs:`n  build:`n    runs-on: ubuntu-latest`n    steps:`n      - name: Nothing`n        run: Write-Output fixture`njobs:`n  build:`n    runs-on: self-hosted`n    steps:`n      - name: Nothing`n        run: Write-Output pwned`n" }
            # THE SPELLING THAT DIFFERS ONLY IN CASE, AND IT IS HERE BECAUSE
            # THE ARGUMENT FOR IT WAS ONCE ONLY AN ARGUMENT. Add-LwgKeyOnce
            # explains at length why its seen-set must be case-INSENSITIVE:
            # `-eq` in Get-LwgMapValue and Get-LwgMapEntry is case-insensitive,
            # so `runs-on:` and `Runs-On:` are one key to every lookup and the
            # first one found wins. That reasoning was prose and nothing
            # certified it. Measured: swapping the seen-set for an ORDINAL
            # comparer left the suite reporting every case passed, while
            #
            #     runs-on: ubuntu-latest
            #     Runs-On: self-hosted
            #
            # went back to `RESULT: 0 violation(s)`, `EXIT: 0` - #137's exact
            # bypass, one capital letter apart, behind a green build. A
            # property asserted in a comment and pinned by no case is the
            # defect this whole file is about. This row is the pin.
            @{ dir = 'dup-runs-on-case'; file = 'only.yml'; key = 'Runs-On'
               what = 'a lone workflow declaring runs-on: then Runs-On: self-hosted, differing only in case'
               body = "name: only`non:`n  workflow_dispatch:`njobs:`n  build:`n    runs-on: ubuntu-latest`n    Runs-On: self-hosted`n    steps:`n      - name: Nothing`n        run: Write-Output fixture`n" }
        )
        foreach ($d in $dupPairs) {
            $dd = Join-Path $fx $d.dir
            $null = New-Item -ItemType Directory -Path $dd -Force
            Set-Content -LiteralPath (Join-Path $dd $d.file) -Encoding ASCII -Value $d.body
            $r = Invoke-LwgGuard -Dir $dd
            Add-LwgCase ("{0} exits 1" -f $d.what) ($r.Code -eq 1) `
                ("expected exit 1, got $($r.Code). A duplicate key means the reader stored two values and every lookup can only see one of them, so the file was NOT fully read - reporting it clean is the false assurance this guard exists to refuse. Output: $($r.Out)")
            # Paired with the exit code on purpose. `exit 1` alone is satisfied
            # by any rule firing for any reason; this pins the rule AND names
            # the duplicated key, so a fix that fails the file for some other
            # reason cannot pass this row.
            $named = ($r.Out -match ([regex]::Escape($d.file) + ':\d+:[^\r\n]*' + [regex]::Escape($d.key) + '[^\r\n]*- unparseable:'))
            Add-LwgCase ("{0} is reported as unparseable, naming the duplicated key" -f $d.what) $named `
                ("no line reported $($d.file) under rule unparseable naming '$($d.key)'. Output: $($r.Out)")
        }

        # --- the other arm: a repeated key in DIFFERENT mappings is legal ---
        # The paired half of the two cases above, and it is not decoration. The
        # duplicate check has to be scoped to the one mapping being built: every
        # job declares `runs-on:` and `steps:`, and every step declares `name:`
        # and `run:`, so a check that remembered keys across siblings would
        # condemn every workflow in existence - including this repository's own
        # ci.yml. Without this row, "make everything unparseable" passes both
        # cases above.
        $legit = Join-Path $fx 'repeated-keys-ok'
        $null = New-Item -ItemType Directory -Path $legit -Force
        Set-Content -LiteralPath (Join-Path $legit 'ok.yml') -Encoding ASCII -Value `
            "name: fixture repeated keys in sibling mappings`non:`n  workflow_dispatch:`njobs:`n  one:`n    runs-on: windows-latest`n    steps:`n      - name: Nothing`n        run: Write-Output fixture`n      - name: Nothing`n        run: Write-Output fixture`n  two:`n    runs-on: windows-latest`n    steps:`n      - name: Nothing`n        run: Write-Output fixture`n"
        $r = Invoke-LwgGuard -Dir $legit
        Add-LwgCase 'two jobs each declaring runs-on:, and repeated step keys, still exit 0' ($r.Code -eq 0) `
            "expected exit 0, got $($r.Code). The duplicate-key check must be scoped to one mapping; a key repeated in SIBLING mappings is ordinary YAML and every workflow does it. Output: $($r.Out)"
        Add-LwgCase 'two jobs each declaring runs-on: report zero violations' ($r.Out -match 'RESULT: 0 violation\(s\)') `
            "expected a RESULT line reporting 0 violations, got: $($r.Out)"

        # --- the abort end of the contract ---------------------------------
        # Both of these are exit 2 and NEITHER is reachable from a live run, so
        # the only evidence they behave is here. An enumeration returning zero
        # files is an abort, never an empty-set pass.
        $empty = Join-Path $fx 'empty'
        $null = New-Item -ItemType Directory -Path $empty -Force
        $r = Invoke-LwgGuard -Dir $empty
        Add-LwgCase 'an empty directory aborts with exit 2, not a clean 0' ($r.Code -eq 2) `
            "expected exit 2, got $($r.Code). Zero files scanned is an abort, never an empty-set pass."
        $r = Invoke-LwgGuard -Dir (Join-Path $fx 'does-not-exist')
        Add-LwgCase 'a missing directory aborts with exit 2' ($r.Code -eq 2) `
            "expected exit 2, got $($r.Code)."
    } catch {
        ''
        "ABORTED: $($_.Exception.Message)  [line $($_.InvocationInfo.ScriptLineNumber)]"
        'RESULT: the self-test did not complete, so nothing about this guard was established'
        'EXIT: 2 (the rules were NOT proved to fire, which is not the same as passing)'
        if (Test-Path -LiteralPath $fx) { Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue }
        exit 2
    }
    if (Test-Path -LiteralPath $fx) { Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue }

    $total = $script:SelfResults.Count
    $pass  = @($script:SelfResults | Where-Object { $_.Ok }).Count
    ''
    if ($total -eq 0) {
        'RESULT: no case ran, so nothing about this guard was established'
        'EXIT: 2 (zero cases run is an abort, never an empty-set pass)'
        exit 2
    }
    "RESULT: $pass of $total case(s) passed."
    if ($pass -ne $total) {
        "EXIT: 1 (a rule this guard advertises did not fire on input planted to trip it,"
        "         or the exit contract did not hold. A rule that cannot fire is a comment.)"
        exit 1
    }
    'EXIT: 0 (every rule fired on the shape planted for it, a clean directory exited 0,'
    '         and an empty or absent directory aborted with 2 rather than passing)'
    exit 0
}

if ($null -eq $AlsoParse) {
    # Default: the rest of .github\, which GitHub reads at run time and which
    # nothing in this repository parsed. Skipped when -WorkflowDir was pointed
    # somewhere else, because that is fixture mode and .github is not the
    # subject then.
    $defaultWorkflowDir = Join-Path $Root '.github\workflows'
    if ($WorkflowDir -eq $defaultWorkflowDir) { $AlsoParse = @((Join-Path $Root '.github')) }
    else { $AlsoParse = @() }
}

try {
    'LW-WATCHTOWER workflow guard'
    "  repo      : $Root"
    "  workflows : $WorkflowDir"
    "  rules     : $($Rules.Count)   allowlist entries: $($AllowList.Count)"

    if (-not (Test-Path -LiteralPath $WorkflowDir -PathType Container)) {
        throw "$WorkflowDir does not exist - the workflow directory could not be enumerated, so nothing was checked"
    }

    # Enumerated by globbing the directory. NEVER a hardcoded list: a hardcoded
    # list is how CI's JSON step once validated three files by hand and missed a
    # fourth that was added later, and a workflow file added after this line was
    # written is exactly the file this guard is for. Recursive on purpose -
    # GitHub only runs the top level, but a file parked in a subdirectory is
    # still one commit away from running.
    $files = @(
        Get-ChildItem -LiteralPath $WorkflowDir -Recurse -File |
            Where-Object { $_.Extension -eq '.yml' -or $_.Extension -eq '.yaml' } |
            Sort-Object FullName
    )
    if ($files.Count -eq 0) {
        throw "no .yml or .yaml file found under $WorkflowDir - the enumeration is broken, or the workflows are gone; either way nothing was checked"
    }
    "  files     : $($files.Count)"
    ''

    foreach ($f in $files) {
        $rel = $f.FullName.Substring($WorkflowDir.Length).TrimStart('\', '/') -replace '\\', '/'
        $raw = [IO.File]::ReadAllText($f.FullName)
        $rawLines = ($raw.TrimStart([char]0xFEFF)) -split "`r`n|`n|`r"
        $parsed = Read-LwgYaml -RawLines $rawLines
        $scanned++

        foreach ($e in $parsed.errors) {
            Add-LwgHit -File $rel -Line $e.line -Text $e.msg -Rule 'unparseable'
        }

        # $doc, never $root - see the note on Test-LwgTriggers.
        $doc = $parsed.root
        if ($null -eq $doc -or $doc.t -ne 'map') {
            if ($null -ne $doc) {
                Add-LwgHit -File $rel -Line 1 -Text 'the document is not a mapping - a workflow file must be one' -Rule 'unparseable'
            }
        } else {
            # ---- triggers ----
            Test-LwgTriggers -File $rel -Doc $doc

            # ---- secrets: keys, anywhere ----
            Test-LwgSecretsKeys -File $rel -Node $doc

            # ---- jobs ----
            $jobs = Get-LwgMapValue -Node $doc -Key 'jobs'
            if ($null -eq $jobs) {
                Add-LwgHit -File $rel -Line 1 -Text 'the workflow declares no jobs: block' -Rule 'unparseable'
            } elseif ($jobs.t -ne 'map') {
                Add-LwgHit -File $rel -Line $jobs.line -Text 'jobs: is not a mapping of job ids' -Rule 'unparseable'
            } else {
                foreach ($je in $jobs.entries) {
                    $job = $je.value
                    if ($null -eq $job -or $job.t -ne 'map') {
                        Add-LwgHit -File $rel -Line $je.keyLine -Text "job '$($je.key)' has no readable body" -Rule 'unparseable'
                        continue
                    }
                    $usesEntry = Get-LwgMapEntry -Node $job -Key 'uses'
                    $runsOn = Get-LwgMapEntry -Node $job -Key 'runs-on'

                    if ($null -ne $usesEntry) {
                        # A JOB-level uses: is a reusable-workflow call - not a
                        # step's action. The tree tells them apart; a text scan
                        # could not.
                        $us = @(Get-LwgScalars $usesEntry.value)
                        $target = $(if ($us.Count -gt 0) { $us[0].text } else { '' })
                        $line = $(if ($us.Count -gt 0) { $us[0].line } else { $usesEntry.keyLine })
                        if ($target -like './*') {
                            $leaf = Split-Path -Leaf ($target -replace '/', '\')
                            $known = @($files | Where-Object { $_.Name -eq $leaf })
                            if ($known.Count -eq 0) {
                                Add-LwgHit -File $rel -Line $line -Text "$target (local reusable workflow not found in the scanned set)" -Rule 'external-reusable-workflow'
                            }
                        } else {
                            Add-LwgHit -File $rel -Line $line -Text $target -Rule 'external-reusable-workflow'
                        }
                        # A caller job legitimately has no runs-on. Only report a
                        # runs-on it does declare.
                        if ($null -ne $runsOn) {
                            Test-LwgRunsOn -File $rel -Node $runsOn.value -JobNode $job -JobLine $je.keyLine
                        }
                    } else {
                        Test-LwgRunsOn -File $rel -Node $(if ($runsOn) { $runsOn.value } else { $null }) -JobNode $job -JobLine $je.keyLine
                    }
                }
            }
        }

        # ---- raw line sweeps ----
        # Deliberately textual, and deliberately on top of the structural walk
        # rather than instead of it. See the header: a secret expression is a use
        # wherever it appears, and naming pull_request_target anywhere is a
        # workflow built around that trigger. Comment text is skipped, except
        # inside a block scalar where a `#` line is script rather than a comment.
        foreach ($r in $parsed.lines) {
            $text = $(if ($r.inBlock) { $r.raw } else { $r.body })
            if ([string]::IsNullOrWhiteSpace($text)) { continue }

            foreach ($m in [regex]::Matches($text, '\$\{\{(?:[^}]|\}(?!\}))*\}\}')) {
                if ($m.Value -match '(?<![A-Za-z0-9_.])secrets\s*[.\[]' -or
                    $m.Value -match '(?<![A-Za-z0-9_.])secrets(?![A-Za-z0-9_.])') {
                    Add-LwgHit -File $rel -Line $r.n -Text $m.Value -Rule 'secrets-expression'
                }
            }
            # The token sweep covers YAML values that are not the trigger key
            # itself - an `if:` on github.event_name is the realistic one - and
            # deliberately does NOT cover block-scalar lines. A workflow's
            # `on:` block is the only thing that can select a trigger; the same
            # word inside a run: script is a string in a shell command, and
            # THIS repository's own CI step names it while explaining what the
            # guard refuses. Skipping script here costs nothing, because the
            # structural check on `on:` above is the one that decides.
            if (-not $r.inBlock -and $text -match 'pull_request_target') {
                Add-LwgHit -File $rel -Line $r.n -Text 'pull_request_target' -Rule 'pull-request-target'
            }
        }

        if ($ShowTree) {
            "  parsed $rel : $(($parsed.lines | Where-Object { -not $_.empty }).Count) significant line(s), $($parsed.errors.Count) parse error(s)"
        }
    }

    # ---- the rest of .github\, PARSED ONLY ----------------------------------
    # dependabot.yml and the four ISSUE_TEMPLATE files are read by GitHub and
    # were read by nothing here. See PARSE-ONLY COVERAGE in the header for what
    # this buys and, more to the point, what it does not: parsing is not schema
    # validation, and the nine rules are deliberately NOT applied - a `secrets:`
    # key in an issue form means something else entirely.
    #
    # An empty enumeration here is NOT an abort, and that is the one asymmetry
    # with the workflow directory above. A repository with no dependabot.yml and
    # no issue templates is a normal repository; a repository whose
    # .github\workflows\ enumerated to nothing has either lost its workflows or
    # has a broken glob, and neither may be reported as clean.
    foreach ($extra in @($AlsoParse)) {
        if ([string]::IsNullOrWhiteSpace($extra)) { continue }
        if (-not (Test-Path -LiteralPath $extra -PathType Container)) { continue }
        $extraFiles = @(
            Get-ChildItem -LiteralPath $extra -Recurse -File |
                Where-Object { $_.Extension -eq '.yml' -or $_.Extension -eq '.yaml' } |
                Where-Object { $_.FullName -notlike (Join-Path $WorkflowDir '*') } |
                Sort-Object FullName
        )
        foreach ($f in $extraFiles) {
            $rel = $f.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'
            $raw = [IO.File]::ReadAllText($f.FullName)
            $rawLines = ($raw.TrimStart([char]0xFEFF)) -split "`r`n|`n|`r"
            $parsed = Read-LwgYaml -RawLines $rawLines
            $parsedOnly++
            foreach ($e in $parsed.errors) {
                Add-LwgHit -File $rel -Line $e.line -Text $e.msg -Rule 'unparseable'
            }
            if ($null -eq $parsed.root) {
                Add-LwgHit -File $rel -Line 1 -Text 'the file parsed to nothing at all' -Rule 'unparseable'
            }
        }
    }
} catch {
    $aborted = "$($_.Exception.Message)  [line $($_.InvocationInfo.ScriptLineNumber)]"
}

$sw.Stop()

if ($aborted) {
    ''
    '==========================================================================='
    "ABORTED: $aborted"
    'EXIT: 2 (the workflows were NOT checked, which is not the same as passing)'
    exit 2
}

if ($allowedHits.Count -gt 0) {
    "ALLOWLISTED - matched a rule, and carries a stated reason ($($allowedHits.Count)):"
    foreach ($a in $AllowList) {
        "  {0,4}  {1,-28}  {2}" -f $allowCount[$a.id], $a.id, $a.why
    }
    foreach ($h in $allowedHits) {
        "  {0}:{1}: {2}  - {3}  [allowed by {4}]" -f $h.file, $h.line, $h.text, $h.rule, $h.allowId
    }
    ''
}

if ($hits.Count -gt 0) {
    "VIOLATIONS - a workflow reaches something it must not ($($hits.Count)):"
    ''
    foreach ($v in ($hits | Sort-Object file, line, rule)) {
        "  {0}:{1}: {2}  - {3}: {4}" -f $v.file, $v.line, $v.text, $v.rule, $v.ruleName
    }
    ''
    'The rule each one broke, and what it costs:'
    foreach ($g in ($hits | Group-Object rule)) {
        $r = $Rules | Where-Object { $_.id -eq $g.Name } | Select-Object -First 1
        ''
        "  $($g.Name) ($($g.Count)) - $($r.name)"
        foreach ($w in ($r.why -split '(?<=\.) (?=[A-Z$`])')) { "      $($w.Trim())" }
    }
    ''
}

'==========================================================================='
"scanned $scanned workflow file(s) in $([int]$sw.Elapsed.TotalMilliseconds) ms" +
    $(if ($parsedOnly -gt 0) { ", parsed $parsedOnly more file(s) under .github without applying the rules" } else { '' })
"RESULT: $($hits.Count) violation(s), $($allowedHits.Count) allowlisted"

if ($hits.Count -gt 0) {
    'EXIT: 1 (a workflow names a runner GitHub does not host, uses'
    '         pull_request_target, reaches a secret, or could not be parsed.'
    '         Fix the workflow. Do NOT add an allowlist entry unless the use is'
    '         genuinely necessary, and if it is, state the reason on the entry.)'
    exit 1
}
# THE EXIT-0 LINE MUST NOT OVERSTATE WHAT HELD. It read "no workflow ... reaches
# a secret" unconditionally, which was true for as long as the allowlist was
# empty and became a false sentence printed by a security scanner the moment an
# entry excused a real hit. An exempted use is still a use; the exemption is a
# reason, not an absence.
if ($allowedHits.Count -gt 0) {
    "EXIT: 0 (no workflow names a non-hosted runner or uses pull_request_target; $($allowedHits.Count) rule hit(s) are excused by an allowlist entry and are listed above with the reason)"
} else {
    'EXIT: 0 (no workflow names a non-hosted runner, uses pull_request_target, or reaches a secret)'
}
exit 0
