#requires -version 5
<#
  LW-WATCHTOWER docs_coupling module - the recording half.

  Invoked from hooks/hooks.json in exec form:
      command: "powershell"
      args:    ["-NoProfile","-ExecutionPolicy","Bypass","-File",
                "${CLAUDE_PLUGIN_ROOT}/lib/post_edit.ps1"]
      matcher: "Write|Edit|NotebookEdit"

  PostToolUse, so it observes an edit that already happened. It cannot block
  anything and is not trying to: it appends the edited path to a per-session
  list, and lib/stop_advisories.ps1 reads that list at turn end to ask whether
  source changed while documentation did not.

  Why a hook rather than reading the transcript at Stop: the transcript does
  carry every tool call, but it grows without bound and Stop runs at every turn
  end. Appending one line here is O(1) per edit; re-scanning a 3 MB transcript
  every turn is not.

  ALWAYS exits 0 and never writes to stdout. A PostToolUse hook that emits an
  unexpected envelope, or exits nonzero, injects noise into a turn that has
  already succeeded.
#>

$ErrorActionPreference = 'Stop'

try {
    . (Join-Path $PSScriptRoot 'common.ps1')

    $payload = Read-LwgStdin
    $cfg     = Get-LwgConfig
    $repo    = Get-LwgRepo $payload

    # --- module gate -------------------------------------------------------
    # Flag off means zero side effects: no file is created, nothing is appended,
    # and the Stop half then finds no list and stays silent too.
    #
    # ONE module reads this list, and the gate names it. It used to be a
    # two-term `-or`, because mission_drift read the same list and gating on
    # docs_coupling alone would have made it silently inert for anyone who had
    # switched docs_coupling off - a module that looks enabled and observes
    # nothing, which is the exact defect this plugin exists to catch. That
    # module is gone; the widened gate went with it rather than being left as a
    # disjunction with one arm, which would read as though a second reader
    # still existed.
    if (-not (Test-LwgModule -Name 'docs_coupling' -Config $cfg -Repo $repo)) { exit 0 }

    # Write and Edit report tool_input.file_path; NotebookEdit reports
    # notebook_path. Anything else is not an edit we can attribute to a file.
    $path = [string]$payload.tool_input.file_path
    if ([string]::IsNullOrWhiteSpace($path)) { $path = [string]$payload.tool_input.notebook_path }
    if ([string]::IsNullOrWhiteSpace($path)) { exit 0 }

    $file = 'edits-' + (Get-LwgSessionKey -SessionId ([string]$payload.session_id)) + '.txt'

    # Bound the list. A long session can touch the same file hundreds of times
    # and the Stop half only needs the DISTINCT set, so past this cap the extra
    # lines buy nothing and only cost read time at every turn end.
    #
    # IT USED TO STOP RECORDING HERE, WHICH IS A DIFFERENT THING FROM BOUNDING.
    # The check was `if (size -gt 262144) { exit 0 }`, so past the cap NO further
    # edit in that session was ever recorded. The premise in the paragraph above
    # is true of a REPEAT edit to a file already in the list and false of a file
    # edited for the first time after the cap - and a size check cannot tell the
    # two apart. What it produced was a reading module observing nothing while
    # reporting active: docs_coupling kept warning that "no documentation did"
    # about a session that had spent an hour editing documentation, because no
    # doc path could be recorded any more. That is the exact defect the gate
    # comment 20 lines above names as the reason this hook records at all.
    #
    # SO IT ROLLS, and it rolls through Invoke-LwgRotate rather than a bespoke
    # read-modify-write here. That function already has the properties this
    # needs and they were expensive to get: the live file is moved aside FIRST
    # and recreated immediately, so a concurrent hook's append lands in the new
    # file rather than in a generation about to be overwritten; nothing is
    # deleted until the live file has actually moved; every failure is reported
    # into lw-watchtower.jsonl instead of returning silently. A second copy of that
    # logic in this file is how two copies drift apart.
    #
    # THE COST IS THE SAME ONE supervisor.ps1 ARGUES FOR ITS OWN CALL: under the
    # cap this is one Test-Path plus one Get-Item length compare and returns
    # immediately, which is every run but one in several thousand.
    #
    # WHAT IT LEAVES BEHIND, named rather than discovered later: one archive
    # generation, `edits-<key>.txt.1`, for any session that reaches the cap.
    # Nothing reads it and nothing prunes it - see the state-directory note in
    # docs/modules.md. Archiving rather than discarding is the deliberate half;
    # the absence of a sweep is not, and is tracked separately.
    try {
        # -MaxLineChars IS ABOVE THE WRITE CAP BELOW, DELIBERATELY, and the two
        # numbers have to be read together. Invoke-LwgRotate DROPS any line
        # longer than MaxLineChars from the live file - archived, never carried
        # forward - so a value smaller than what the append admits would create
        # a window of paths that are recorded and then silently discarded at the
        # first roll. Get-LwgRedacted at 1024 emits at most 1027 characters
        # (measured: the cut marker is three), so 1100 is above everything this
        # hook can write and nothing it admits can be dropped here.
        if (Invoke-LwgRotate -FileName $file -MaxBytes 262144 -KeepLines 2000 -Archives 1 -MaxLineChars 1100) {
            Write-LwgEvent -Event 'EditListRolled' -Payload $payload -Extra @{
                module = 'docs_coupling'
                file   = $file
                note   = 'the per-session edit list passed 256 KB and was rolled; the oldest entries are in the .1 archive and are no longer read at turn end'
            } | Out-Null
        }
    } catch { }

    # BOUND THE LINE, NOT ONLY THE FILE. The cap above is on the file's size and
    # the check runs BEFORE the append, so a file at 100 bytes admitted an
    # append of any length - and $path is `tool_input.file_path` straight off
    # the payload, with Add-LwgLine imposing no bound of its own. One oversized
    # value did three things: it occupied most of the 256 KB tail window the
    # Stop half reads, displacing the real edit history docs_coupling reads while
    # leaving the file under the cap so the picture stayed wrong rather than
    # obviously broken; it went into the `sample` field of a DocsCoupling record
    # in a log that does not rotate; and it reached the operator's systemMessage
    # whole, because `Split-Path -Leaf` returns the entire string when there is
    # no path separator in it.
    #
    # Get-LwgRedacted is the same helper lib/supervisor.ps1 routes its
    # payload-derived fields through, at the same kind of choke point and for
    # the reason recorded there: a field bounded because it was written, not
    # because whoever added it remembered. Redaction is not decoration on a
    # path - a path can carry a token in a URL-shaped segment or a temp file
    # named after a credential - and it leaves an ordinary Windows path exactly
    # as it was; measured on this tree against paths with spaces, with a profile
    # directory and with `api_key` as a directory name, all unchanged.
    #
    # WHAT THE CAP COSTS, and it is not nothing. A truncated path loses its
    # TAIL, which is where the extension is, so Get-LwgPathClass reads it as
    # 'other' rather than 'source' or 'doc' and docs_coupling stops counting it.
    # That is a new blind spot traded for a bounded one, and the size is chosen
    # around it: MAX_PATH is 260 and 1024 is well past any path a real edit tool
    # produces even with long-path support on, so the trade bites only on values
    # that were never a path. It is listed in docs/modules.md with the other
    # blind spots rather than left here.
    #
    # This is the WRITE side only. lib/stop_advisories.ps1 bounds the samples it
    # puts in a record and an advisory independently, because the reader must
    # not depend on the writer having been fixed.
    Add-LwgLine -FileName $file -Line (Get-LwgRedacted -Text ($path.Replace("`r", ' ').Replace("`n", ' ')) -MaxLength 1024) | Out-Null

} catch {
    # Never break a session, and never let a governance failure surface as a
    # tool failure. Record it and exit clean.
    try { Write-LwgEvent -Event 'AdvisoryError' -Payload $payload -Extra @{
        module = 'docs_coupling'; phase = 'record'; error = $_.Exception.Message } | Out-Null
    } catch { }
}

exit 0
