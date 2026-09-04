# Contributing to LW-WATCHTOWER

**Reports yes, code by invitation.** Bug reports, questions and feature requests are welcome, and
every one gets a human reply within five working days — [SUPPORT.md](SUPPORT.md) says where each
goes. A pull request from outside the collaborator list is different: **open an issue first and wait
to be asked for the change.** That is not a closed door. Every change to this tree has to arrive with
a regression case proven to fail before the fix, and there is one maintainer and nobody to coach that
through review today; an unrequested pull request is closed with a pointer to this paragraph, not
reviewed. An invited one follows the rest of this page exactly — fork, branch, suites, pull
request — and gets the same checks a maintainer's does. Every rule below that says **[CI]** fails an
invited contributor's build exactly as it fails ours.

Thanks for looking. This project has three rules that matter more than the rest. Read them even if
you skip everything else:

1. [A regression test must fail before the fix](#a-regression-test-must-fail-before-the-fix).
   **Only its bookkeeping is enforced** — `.github/scripts/redfirst_annotations.ps1` holds the shape
   of a red-first annotation in CI and cannot re-run a baseline — so the rule itself is held by
   review, and held strictly.
2. [No local environment dependencies](#portability-no-local-environment-dependencies) — no account
   name, computer name, profile path or absolute interpreter path in a tracked file. **CI scans
   every tracked file and fails on a hit.** This one really will fail your build.
3. [No self-hosted runner, no `pull_request_target`, no
   secrets](#workflows-no-self-hosted-runner-no-pull_request_target-no-secrets) in any workflow.
   **CI parses every workflow file and fails on a hit.** So will this one, and this is the rule
   whose failure mode is somebody else's machine rather than your build.

### How each rule on this page is held

Rule 1 above says in bold that only its bookkeeping is enforced. A note of that kind was the only one
on this page for a long time, and singling one rule out that way tells a reader the others are
enforced. Six were not. So every rule below now carries one of three tags, and the tag is the claim:

| Tag | Means |
| --- | --- |
| **[CI]** | a check step fails the build on a hit. Nothing else counts as CI. |
| **[review]** | held by a human reading the diff. Real, and strictly held — but a green build says nothing about it. |
| **[CI, partly]** | something is checked and it is narrower than the rule. What exactly is checked is stated on the spot. |

A tag is not a promise that the rule is a good one, and **[review]** is not a lesser rule — rule 1 is
**[CI, partly]** at best and is the most important thing on this page. The tag answers one question
only: if you get this wrong, does the build tell you, or does a person?

**What CI has learned to enforce since these tags were written**, because a stale **[review]** is the
same overstatement in the other direction:

| Rule | Now held by |
| --- | --- |
| A pull request body carries `Refs #N` | **[CI]** — `.github/scripts/pr_issue_ref.ps1` |
| Every commit comes from an identity on the allowlist | **[CI]** — `.github/scripts/identity_scan.ps1` |
| A red-first annotation names a commit and a case that exists | **[CI, partly]** — `.github/scripts/redfirst_annotations.ps1`; the shape only, never the baseline |
| The five version-declaration sites agree with each other | **[CI]** — `.github/scripts/version_declarations.ps1`; the two tag-shaped rules report NOT CHECKED without a tag |
| No workflow grants `permissions:` wider than read | **[CI]** — `tests/workflow_guard.ps1`'s `permissions-write` rule |

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

**Found a credential in a log, or an installer that damaged a `settings.json`?** Do not open a
public issue. See [SECURITY.md](SECURITY.md). None of the three gates this plugin ships is a
**security control**: `delegate_gate` refuses main-thread work as a discipline and a subagent can do
everything it refuses by design, the two supervision gates hold a reporting discipline, and a way
past any of them is not a vulnerability.

---

## Development setup

### Requirements

| Requirement | Notes |
| --- | --- |
| Windows | Every hook is a Windows PowerShell script, the state directory is resolved against Windows paths, and the status line and installer both assume them. There is no portable path here and none is planned. |
| **Windows PowerShell 5.1** (`powershell.exe`) | Not `pwsh`. PowerShell 7 is a different binary with different `NativeCommandError` behaviour, and `lw-watchtower/hooks/hooks.json` registers a binary literally named `powershell`. |
| `git` | For the repo, and for `git_hygiene`. |
| `gh` | Optional. Only `git_hygiene`'s open-PR check uses it. |

No Node, no npm, no Python.

### The invited contributor's path starts with a fork

This is the step after your issue has been answered and the change has been asked for. It is first on
this page because of what it costs to discover last.

**You cannot push a branch to this repository.** The collaborator list is one account, so a change
cloned straight from upstream has nowhere to go and the pull request you are asked for at the end of
this page cannot be opened. An invitation does not change that — it is an invitation to open a pull
request from your fork, not push access. That is a cheap thing to find out first and an expensive one
to find out last, so it is the first step here rather than the last.

```powershell
gh repo fork LEAPWare-Software/LEAPWare-Watchtower --clone=false
```

or use the **Fork** button. Then clone **your fork** below instead of upstream, and keep upstream as
a second remote so you can rebase:

```powershell
git remote add upstream https://github.com/LEAPWare-Software/LEAPWare-Watchtower.git
git fetch upstream
```

Work on a branch, push it to your fork (`origin`), and open the pull request against
`LEAPWare-Software/LEAPWare-Watchtower`'s `main`. CI is fork-ready — `.github/workflows/ci.yml` declares
`permissions: contents: read`, uses no secrets, and runs on `pull_request` — so your PR gets the same
checks a maintainer's does.

### Getting a live clone

Clone, then junction it into your skills directory so the code you edit is the code that runs:

```powershell
# Wherever you keep your clones - nothing depends on this particular path.
$Repo = "$env:USERPROFILE\src\leapware-watchtower"

git clone https://github.com/<your-fork>/LEAPWare-Watchtower.git $Repo

# CREATE THE PARENT FIRST. mklink does not, and on a machine that has never
# installed a skill this directory does not exist. The failure is
# "The system cannot find the path specified.", which names the mklink call
# rather than the missing folder, so it reads as a permissions problem and is
# not one. docs/install.md has carried this line and this warning since the
# junction route was written; this page dropped it.
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.claude\skills" | Out-Null

cmd /c mklink /J "$env:USERPROFILE\.claude\skills\lw-watchtower" "$Repo\lw-watchtower"
```

**The target is `$Repo\lw-watchtower`, not `$Repo`, and getting that wrong gives you a
working-looking install of nothing.** Since 3 September 2026 (#236) the shipped payload is the
`lw-watchtower/` subtree — it is what holds `.claude-plugin/plugin.json` and `lib/`, and every hook
registration is written as `${CLAUDE_PLUGIN_ROOT}/lib/*.ps1`. Link the clone root instead and
`mklink` still prints `Junction created`, the session still starts, and every one of those paths
resolves one directory short of the file it names: no banner, no hooks, nothing refused and nothing
reported. See #242.

A junction needs no administrator rights. **Do not develop against a marketplace install** — it
copies the plugin root into an internal cache, so your edits do nothing until `claude plugin update`
and you will spend an afternoon debugging a stale copy. Details in [docs/install.md](docs/install.md).

Start a session and confirm the banner appears, then:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File lw-watchtower\bin\lwg-doctor.ps1
```

### Line endings

**Every blob in the index is LF. The working tree is not, and that is deliberate.**
`.gitattributes` sets `* text=auto eol=lf` and then `*.ps1 text eol=crlf`, so `.ps1` is *checked
out* CRLF and normalised back to LF on commit. `git ls-files --eol` shows the split: `i/lf` on every
tracked file without exception, `w/crlf` on most `.ps1`, and `w/lf` on the few whose working-tree
copy was last written by an editor rather than by a checkout. Both halves are correct, and neither
`.gitattributes` nor the index is lying about the other.

The practical consequence is that **an editor writing either ending is harmless** — git normalises
on the way in, so a CRLF save cannot land CRLF in a commit. What you must not do is normalise line
endings *across files you did not otherwise change*: it turns a two-line diff into a whole-file
rewrite and makes review impossible. Configure your editor to preserve what it finds; there is an
[`.editorconfig`](.editorconfig) that already says all of this.

`lw-watchtower/statusline/statusline.ps1` is pinned to `eol=lf` on purpose, so a fresh clone reproduces the
installed file byte for byte and a hash comparison against `~\.claude\statusline.ps1` keeps meaning
something.

### The `lwg` prefix stays, wholesale, and it no longer stands for anything

The product was renamed from `lw-gmhh` to `lw-watchtower` on 3 August 2026. **The internal `lwg` /
`Lwg` / `LWG` prefix was deliberately not renamed with it**, and this is the record of that decision
so nobody half-does it later. It is on seven `lw-watchtower/bin/lwg-*.ps1` scripts, on every function and script
variable in `lib/` (`Get-LwgStateDirInfo`, `$script:LwgVersion`, `Write-LwgEvent`), and on two
operator-visible strings.

**Renaming it partially would be worse than not renaming it**, so the rule is all or nothing, and
the choice is nothing. Four reasons, in the order they matter:

1. **It is not the product name.** `git grep -i gmhh` — the test the rename was held to — does not
   match `lwg` at all, so leaving it satisfies that criterion exactly as well as changing it would.
   What renaming it would buy is tidiness, against the costs below.
2. **Two of these strings are in the operator's files, not ours.** [`lw-watchtower/bin/lwg-setup.ps1`](lw-watchtower/bin/lwg-setup.ps1)
   writes its settings backups as `settings.json.lwg-<stamp>.bak` beside the target and enumerates
   `"<leaf>.lwg-*.bak"` to offer a rollback. Rename the prefix and every backup taken before the
   rename becomes invisible to the rollback that exists to restore it — a switch wired to nothing,
   on the one path an operator reaches for after a bad write.
3. **`DELETE-MY-LWG-LOGS` is typed by a human.** It is the confirmation token
   [`lw-watchtower/bin/lwg-uninstall.ps1`](lw-watchtower/bin/lwg-uninstall.ps1) requires before it will delete state. Changing a
   token that already appears in this tree's documentation and in an operator's shell history buys
   nothing and breaks the copy-paste.
4. **It is invisible from outside.** [`lw-watchtower/hooks/hooks.json`](lw-watchtower/hooks/hooks.json) registers
   `${CLAUDE_PLUGIN_ROOT}/lib/*.ps1` and never names `lw-watchtower/bin/`; commands reach the scripts through
   `/lw-watchtower:<name>`. No operator types `lwg` except in the two cases above.

**What it does NOT stand for, stated because a live acronym pointing at a dead name is worse than an
opaque one:** nothing. It was a contraction of the old product name; the tree never expanded it and
does not now. Read `lwg` as an arbitrary, stable prefix meaning "belongs to this plugin" — that is
all it has to mean, and it is what the six `lw-watchtower/agents/lw-*.md` role files mean too. (Five
of those files **used to** declare an `lw-class` frontmatter key. The module that read it was removed
on 2 September 2026, its classifier went with it, and the key was struck from every role file in the
same wave — `git grep -n lw-class -- 'lw-watchtower/agents/'` returns nothing. Nothing in this
release reads a role's class; [`docs/roles.md`](docs/roles.md) is the page that owns that fact. Do
not add the key to a new role, and do not write code that reads it.)

### Testing a hook by hand

A PowerShell pipe never reaches `[Console]::In`, so this does **not** work:

```powershell
Get-Content payload.json | powershell -File lw-watchtower\lib\post_edit.ps1   # WRONG - stdin is empty
```

Use `cmd` to build the pipe:

```powershell
cmd /c "type payload.json | powershell -NoProfile -ExecutionPolicy Bypass -File lw-watchtower\lib\post_edit.ps1"
echo $LASTEXITCODE
```

That is the only way to exercise a hook the way Claude Code actually does. It is how the suites below
drive `lw-watchtower/lib/gate_delegate.ps1`, `lw-watchtower/lib/stop_advisories.ps1` and `lw-watchtower/lib/supervisor.ps1`, and it is the only
way to exercise `lw-watchtower/lib/post_edit.ps1`, `lw-watchtower/lib/session_start.ps1` or `lw-watchtower/lib/subagent_start.ps1` **at all**,
because no suite reaches those three — see below.

---

## There is a test suite, and it is narrower than it sounds

`tests/` holds **fourteen files, and eleven of them test behaviour**, and every one of them runs in
the `fast-checks` CI job on every push and every PR:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\gate_delegate.ps1       # delegate_gate, 100 cases
powershell -NoProfile -ExecutionPolicy Bypass -File tests\supervision.ps1         # send_liveness_gate, completion_audit, orphan_watch, 66
powershell -NoProfile -ExecutionPolicy Bypass -File tests\setup_merge.ps1         # the installer's statusline + hooks merge, 203
powershell -NoProfile -ExecutionPolicy Bypass -File tests\stop_behaviour.ps1      # the two turn-end hooks, 120
powershell -NoProfile -ExecutionPolicy Bypass -File tests\uninstall_footprint.ps1 # the uninstaller's footprint and deletions, 38
powershell -NoProfile -ExecutionPolicy Bypass -File tests\config_behaviour.ps1    # the config command's write to the override, 56
powershell -NoProfile -ExecutionPolicy Bypass -File tests	oggle_behaviour.ps1    # the toggle's write to the override, 28
powershell -NoProfile -ExecutionPolicy Bypass -File tests\state_resolution.ps1    # the state-directory resolver, 37
powershell -NoProfile -ExecutionPolicy Bypass -File tests\doctor_behaviour.ps1    # the doctor's driven checks, 42
powershell -NoProfile -ExecutionPolicy Bypass -File tests\subagent_scan.ps1       # the SubagentStart fast path, 14
powershell -NoProfile -ExecutionPolicy Bypass -File tests\payload_guard.ps1       # every tracked file, as shipped payload, 22
powershell -NoProfile -ExecutionPolicy Bypass -File tests\workflow_guard.ps1      # every workflow file
powershell -NoProfile -ExecutionPolicy Bypass -File tests\portability_scan.ps1    # every tracked file
powershell -NoProfile -ExecutionPolicy Bypass -File tests\doc_claims.ps1          # every tracked page's counts
```

Three guards live under `.github/scripts/` rather than in `tests/`, because they assert nothing about
what this plugin does — they hold this repository's own process. CI runs each of them in its own
step, and you can run them locally the same way:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .github\scripts\redfirst_annotations.ps1         # the annotation shapes
powershell -NoProfile -ExecutionPolicy Bypass -File .github\scripts\redfirst_annotations.ps1 -Live   # over tests\*.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .github\scripts\version_declarations.ps1 -Live   # the five declaration sites
powershell -NoProfile -ExecutionPolicy Bypass -File .github\scripts\identity_scan.ps1                # the commit-identity allowlist
```

`.github\scripts\pr_issue_ref.ps1` is the fourth and takes a pull request body, so there is nothing
useful to run locally against; CI is where it fires.

The last three in that list assert **nothing about behaviour**: two check the contents of tracked
files and the third checks that the documentation's numbers match the tree. They all share one exit
contract: `0` passed, `1` a check failed, `2` the harness aborted and **nothing was checked**. There
is no "passed with a caveat" code, and a suite that ran zero cases exits `2`, never `0`.

**"Eleven of them test behaviour" is a classification, not a compliment, and one of the eleven is a
borderline case worth naming.** `tests/doc_claims.ps1` decides which suites are behavioural by
RUNNING each of them and reading what each says about itself: a suite that tallies `N of M case(s)`
is counted behavioural, one that tallies violations is a scan. `tests/payload_guard.ps1` reads
tracked files rather than running any of this plugin's code, but it reports cases, so the derived
count includes it. That is the guard observing the tree instead of being told about it — which is the
property the whole file exists for — and the honest reading of "eleven" is "eleven suites tally
cases", of which ten drive this plugin's code in a real process and one scans the payload.

**Two suites were deleted on 30 July 2026 and neither is coming back.**
`tests/gate_regression.ps1` — 233 cases over both `PreToolUse` gates — went with the
`destructive_gate` module it mostly covered, the `lw-watchtower:verify` command that ran it, and the
`gate-regression` CI job. `tests/deny_parity.ps1`, with `tests/fixtures/deny_canonical.txt` and
`tests/fixtures/settings_merge_input.json`, went the same day with `secret_scan` — the last gate — at
the owner's explicit instruction. `lw-watchtower/bin/lwg-setup.ps1` writes no `permissions.deny` rules
any more, so there is no table left for a parity test to compare against, and nothing here inspects a
shell command or a credential for a gate suite to cover.

**So for anything outside what those suites reach, nothing will catch you.** Say in the PR exactly
what you exercised and how, using the `cmd /c` recipe above, and do not describe a green CI run as
evidence about behaviour beyond what they establish.

### What went with `deny_parity.ps1`, and what came back

`tests/setup_merge.ps1` put the merge coverage back on **31 July 2026**, aimed at the `statusline`
section — the one section the installer still writes. It checks that `lw-watchtower/bin/lwg-setup.ps1`:

- leaves unrelated top-level keys in `settings.json` byte-identical, **and in their original order**;
- takes exactly one backup, holding the original bytes;
- refuses `apply` without a matching `BaseHash`, and refuses one that no longer matches;
- is idempotent — a second run adds nothing and does not touch the file;
- rolls back byte for byte.

**The `hooks` section joined it** when the install-mode detection was fixed. Setup had been looking
for a marketplace install in `~\.claude\plugins\repos`, which does not exist on a live Claude Code
install, so it classified one as *not discoverable* and wrote a second full copy of every hook
registration — with its own duplicate-firing warning suppressed, since the warning read the same
flag. The suite now plants the layout the CLI actually writes and asserts that the section plans
nothing, that forcing `-HookMode standalone` still warns, and that a registration of the same script
under a **different root** is recognised and reported rather than added beside. Five of those cases
are labelled `CONTROL` in the suite and pass before the fix they sit beside as well as after it, on
purpose. They do not share one baseline: four pass at `fd8d023`, and the relocated-cache one passes
only against the working tree as it stood immediately before its own fix, because neither file read
`CLAUDE_CODE_PLUGIN_CACHE_DIR` at `fd8d023`.

**The deny half is genuinely gone and is not outstanding work**: `Get-DenyGroups` no longer exists at
all — not as a function returning an empty table, which is what this page said until 3 September
2026 — so a test asserting that an empty table is still empty would have nothing to call, and would
report a pass on every run if it did. That is the false assurance this repo exists to refuse.

**What is still outstanding**, and matters if you touch the writer: the backup-collision suffix and
the post-write auto-restore are named as uncovered in the suite's own header, and no case anywhere
establishes that the CLI build *you* are running still writes the plugin layout the fixtures plant.
`permissions` writes nothing, so there is nothing there to merge-test. A PR that puts a case on any
of those is welcome.

---

## A regression test must fail before the fix

This is the rule that matters most here.

**A test that passes both before and after your change proves nothing.** It does not demonstrate that
the bug existed, it does not demonstrate that your fix addresses it, and it will not detect the bug
coming back — because it never detected it in the first place.

So, for every bug fix:

1. Write the case **first**.
2. Check it out against the parent commit, or stash your fix, and **run it**. It must **fail**.
3. Apply the fix. Run it again. It must **pass**.
4. Say both results in the PR, with the case ID.

**A worked example, because "prove it red" is the step people skip.** Suppose the defect is that
`delegate_gate` allows a `PowerShell` call from the main thread. You add a case to
`tests/gate_delegate.ps1` — the suite that owns that behaviour — then, from a throwaway clone rather
than your working tree, so nothing of your fix leaks into the baseline:

```powershell
git clone --no-hardlinks . ..\proof
git -C ..\proof checkout <parent sha>
copy tests\gate_delegate.ps1 ..\proof\tests\gate_delegate.ps1   # ONLY the test change
powershell -NoProfile -ExecutionPolicy Bypass -File ..\proof\tests\gate_delegate.ps1
```

That run must print your case's `[FAIL]` line and a non-zero `EXIT:`. Then run the same suite on your
branch and it must print `[ok]` for the same case id and `EXIT: 0`. Paste **both** whole, not a
summary of them, and name the parent sha you used. A case that cannot be made to fail at the parent —
because the code it tests did not exist there — is still a legitimate case, but say so in the PR
rather than implying a red run you did not get; `.github/scripts/redfirst_annotations.ps1` holds the
annotation's shape, and it cannot tell those two apart for you.

**If your fix is inside what one of the eleven behavioural suites covers, add the case to that
suite** — `delegate_gate`, the two supervision gates, the installer's `statusline` and `hooks` merge,
either turn-end hook, the uninstaller's state-data deletions, the state-directory resolver, the
doctor's driven checks, either command's write to `config.override.json`, the `SubagentStart` fast
path, or what the shipped payload discloses. Each already runs its cases through a real pipe into a
real child process, and each has a `Add-Result` shape to follow.

**If it is anywhere else, there is no harness to hang the case on**, and that is the honest state of
this repo rather than an exemption. The case then has to be a script you write and include, driven
through the `cmd /c` recipe above, run against the parent commit and against your fix, with both
outputs pasted. There is no `-Simulate` switch left anywhere to lean on: the one that existed was
`tests/deny_parity.ps1 -Simulate drop-rule`, and it went with the file.

### A worked example, for the case with no harness

This is the artefact `-Simulate` used to be. It is printed here rather than committed as a file, and
**that is the decision rather than an oversight**: a template under `tests\` is matched by the guard's
own `^tests/.+\.ps1$` derivation whatever directory you nest it in, so committing one would move the
file count in every page that states it, and the parallel runner would *execute* it — which for a
template that is meant to go red means the documentation-claim step goes red with it. A fenced block
creates no tracked file, so it does neither. Copy it to a throwaway name at the repository root, run
it, delete it; nothing is meant to survive the pull request except the two outputs you paste.

The subject below is `lw-watchtower/lib/post_edit.ps1`, chosen because it is one of the surfaces no
suite reaches — which is the case this section exists for. Substitute your own hook, your own payload
and your own assertion; the shape is what is being shown.

```powershell
# redfirst-postedit.ps1 - a standalone red-first case. NOT tracked, NOT under tests\.
#   Against the parent commit it must FAIL. Against your fix it must PASS.
#   Paste BOTH runs into the pull request. One run proves nothing.
$ErrorActionPreference = 'Stop'
$hook    = 'lw-watchtower\lib\post_edit.ps1'
$payload = Join-Path ([IO.Path]::GetTempPath()) ("redfirst-" + [guid]::NewGuid() + ".json")

# The payload the CLI would hand the hook. Keep it minimal: a case that needs
# six keys is a case about the fixture rather than about the behaviour.
@{
    hook_event_name = 'PostToolUse'
    tool_name       = 'Edit'
    tool_input      = @{ file_path = 'C:\some\repo\lw-watchtower\lib\common.ps1' }
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $payload -Encoding UTF8

# cmd builds the pipe, because a PowerShell pipe never reaches [Console]::In.
$out  = cmd /c "type `"$payload`" | powershell -NoProfile -ExecutionPolicy Bypass -File $hook 2>&1"
$code = $LASTEXITCODE
Remove-Item -LiteralPath $payload -Force -ErrorAction SilentlyContinue
$out = ($out | Out-String)

# ONE assertion, stated as the property rather than as the string. The detail
# line has to be enough to diagnose the failure without re-running anything,
# which means it carries what was actually seen and not just "expected true".
$ok = ($code -eq 0) -and ($out -match 'coupled')
Write-Output ("[{0}] the hook names the coupling it found, and exits 0 doing it" -f $(if ($ok) { 'PASS' } else { 'FAIL' }))
if (-not $ok) { Write-Output ("      exit was {0}; stdout was: {1}" -f $code, $out.Trim()) }

# The same two lines every suite here prints, because the checklist asks you to
# paste them and a case nobody can read the verdict of is not a case.
Write-Output ("RESULT: {0} of 1 case(s) passed" -f $(if ($ok) { 1 } else { 0 }))
Write-Output ("EXIT: {0}" -f $(if ($ok) { 0 } else { 1 }))
exit $(if ($ok) { 0 } else { 1 })
```

Run it against the parent commit first — `git stash`, or a second clone at `HEAD~1` — and only then
against your change:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File redfirst-postedit.ps1
```

**A case that passes on both trees is not a red-first case**, and neither is one you wrote after
watching the fix work. If it will not go red against the parent, say so in the pull request and say
why: "this could not be made to fail first, and here is what I did instead" is an answer this project
accepts. A green run presented as a red-first proof is not.

### Why this is written down

This project's allow/deny matrix was **67/67 green while five gate bypasses were open**. Every rule
in the table was correct. The bypasses did not defeat a rule — they defeated the tokenizer that
decides *where a rule is anchored*, so a single backslash-newline tore one command into two fragments
and neither fragment matched anything.

A rule table can be entirely correct and still be reachable around. The tests that earn their place
are the ones aimed at the reaching, not at the rules — and the only way to know a test is aimed at
the reaching is to watch it fail first.

Every one of the five bypass cases in the deleted suite was verified to be **ALLOWED** by the commit
immediately before its fix. New ones are held to the same standard, harness or no harness.

---

## Portability: no local environment dependencies

The second rule that will fail your build.

**Nothing true only of your machine may go into a tracked file.** No account name, no computer name,
no user-profile path, no absolute interpreter or tool path, no private folder hierarchy, no
hardcoded install location. Run it before you push — about two seconds:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\portability_scan.ps1
```

`0` is clean, `1` means a violation and names the `file:line`, `2` means the scan aborted and
checked nothing. The same script runs in the `fast-checks` CI job, so a hit fails the build.

| Instead of | Write |
| --- | --- |
| A hardcoded plugin root | `${CLAUDE_PLUGIN_ROOT}`, else `$PSScriptRoot` and walk up |
| A path under your profile | `$env:USERPROFILE` with `Join-Path` |
| An absolute interpreter path | Name the requirement; resolve the binary from `PATH` |
| Your clone location | A `$Repo` variable with a neutral default |
| Your account or computer name | Nothing. Neither is ever needed. |

**If the scan fires, fix the file.** Adding an allowlist entry is correct only when the match is
genuinely portable — a deliberate sentinel, a reader placeholder, a universal Windows root named as
a deny-rule target — and every entry must state its reason on the entry. An entry without a reason
will be sent back.

This is enforced rather than merely written down because it has already shipped three times: a
status line that rendered *not installed* forever on any other machine, one laptop's machine facts
injected verbatim into every subagent, and a security module whose agent-name arrays matched nothing
on a fresh install while reporting healthy. Full detail, the allowlist policy, and the portable
alternatives: [docs/portability.md](docs/portability.md).

---

## Workflows: no self-hosted runner, no `pull_request_target`, no secrets

The third rule that will fail your build, and the only one whose failure mode is not confined to this
repository.

**No workflow file may reach a runner GitHub does not host, use the `pull_request_target` trigger,
use a secret, or grant itself `permissions:` wider than read.** Run it before you push — under a
second:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\workflow_guard.ps1
```

`0` is clean, `1` means a hit and names the `file:line` with the rule it broke, `2` means the guard
aborted and checked nothing. The same script runs in the `fast-checks` CI job, so a hit fails the
build. Full rule table, and what it does *not* cover:
[Testing and CI](docs/testing.md#the-workflow-guard).

| Do not write | Why |
| --- | --- |
| `runs-on: self-hosted`, a label array containing it, or a bare custom label | there are self-hosted runners registered on the maintainer's machine. A workflow that reaches one gives whoever can trigger it code execution on real hardware — its filesystem, its credentials, its network. This is the worst thing in this repository and it is one line. |
| `runs-on:` with a `group:` | the pool's membership is repository configuration no tracked file can show, and it can change without a commit |
| `runs-on: ${{ matrix.x }}` where a matrix value is not a hosted image | the same runner, reached in a place reviewers do not look |
| `on: pull_request_target` | it runs the base branch's workflow with a read-write token and this repository's secrets while an untrusted author controls the head |
| `${{ secrets.* }}`, or `secrets: inherit` | nothing here needs a credential. The checks parse files and run local scripts. |
| a job-level `uses:` calling a workflow in another repository | it picks its own runners and its own steps, in a file nothing here can read |
| a `permissions:` grant wider than read, at workflow level or at job level, including the `write-all` scalar shorthand | a token that can write is a token that can push, tag or publish from a workflow an outside contributor can trigger |

**The guard parses; it does not grep**, so reformatting does not get you past it, and a construct it
cannot parse is reported as a violation rather than skipped. If it fires, **fix the workflow.** Its
allowlist holds **two entries**, both belonging to `release.yml`: `release-publish-token` for the
`${{ secrets.GITHUB_TOKEN }}` its publish step reads, and `release-publish-grant` for the job-level
`contents: write` that token runs under. They are separate entries so that dropping either does not
quietly widen the other, and `secrets.GITHUB_TOKEN` is still not pre-approved anywhere else: an entry
written before a concrete step needs it is an entry written without a reason. Adding one means
stating the specific need, on the entry, in the PR.

**What the permissions rule does not cover: the absence of a `permissions:` block.** The rule holds a
block that exists to read-scoped values; a workflow declaring none at all inherits the repository's
default workflow permissions, which is repository configuration this scan cannot read. Requiring the
block is a policy preference, and the exit-1 contract is reserved for real violations.

This is enforced rather than written down because the check that came before it was a rule requiring
`ci.yml` to *contain the string* `self-hosted` — which **a comment satisfied**, and which would have
gone on reporting a verified protection while the runner it was named after was introduced.

### Three things in `ci.yml` that look wrong and are not

The [checklist](#checklist) below invites you to edit `.github/workflows/ci.yml`. Three properties of
that file are deliberate, and each one's failure mode is worse than the tidiness it refuses. All
three are stated in comments **inside** the file, at the point of edit — they are repeated here
because a comment is only read by somebody already editing the line it sits on.

- **There is no path filter, and adding one is a regression.** A filter sits on the trigger, not on a
  job, so a match skips the *entire* workflow. `paths-ignore: ['**.md']` was there until 31 July
  2026, and the portability scan reads **every tracked file including `.md`** — a machine-specific
  path turns up in prose more often than in code. Worse on `pull_request`: a filtered workflow there
  makes the required status check **never report**, so a docs-only PR waits forever on a check that
  cannot arrive.
- **Do not rename the job or its display name.** The job id is `fast-checks` and its display name is
  `Fast checks (JSON + PowerShell parse)`. A required status check on `main` is matched by that
  **name**, so renaming it silently stops satisfying the requirement — the build goes green and the
  protection stops applying. The display name is already narrower than what the job does; that is
  known and is not a reason to change it. Rename it only together with the branch-protection setting.
- **One broken suite produces two red steps.** `tests/doc_claims.ps1` re-runs every sibling suite in
  `tests/` to read the tallies they print about themselves — it prints how many it ran, so no count
  is transcribed here to go stale — and exits `2` if any of them exits nonzero.
  So breaking any one of them fails that suite's own step *and* the documentation-claim step, and the
  second failure is not a second defect. Read the first one.

---

## What a good PR looks like

### Scope

- **One change per PR.** **[review]** A fix, or a feature, or a refactor — not two of them.
- **Do not reformat code you are not otherwise changing.** **[review]** Nothing in CI compares diff
  size or line endings; a whole-file rewrite passes every check here. See
  [line endings](#line-endings).
- If the change is large or architectural, open an issue first so we can agree the shape before you
  write it.

### Accuracy — the house rule

This project's entire thesis is that a control which overstates itself is worse than no control.
That applies to your PR description and to any documentation you touch:

- **Never document a command, flag or behaviour that does not exist.** If you are unsure, check, and
  if it does not exist, leave it out.
- **Every number in the docs must come from a file you read or a measurement you took.** Say which.
- **Do not claim coverage you do not have.** Exactly eleven behavioural suites exist in this
  repository, and between them they reach three gates, three writers, one deleter, one resolver, the
  doctor's driven checks, one hook's fast path, the shipped payload, and some but not all of what
  observes — so unless your change lands inside one of those, "tested" means an assertion you wrote
  and included. "Verified by inspection" is a legitimate and welcome statement — write that instead,
  exactly as the existing docs do.
- **A count you write down is checked by a machine.** `tests/doc_claims.ps1` derives the real number
  of test files, behavioural suites, per-suite cases, CI check steps, doctor checks, commands and
  modules from the tree at run time, and fails the build when a tracked page disagrees. If a sentence
  you are editing is a record of what was true on a date — a changelog entry, a UAT observation — put
  `doc-claims:ignore` inside an HTML comment on that line or the one above it, and leave the number
  alone. The same token with `-file` appended, in an HTML comment, exempts a whole file. **Fix the
  sentence rather than reaching for a marker**, and never edit that guard to make a number pass.
- **Do not report a non-zero exit as a pass.** Not `4`, not `2`, not `3`.
- If you could not verify something, say so rather than implying you did.

### Checklist

Before you open the PR:

- [ ] Every file in `tests\` exits `0`. Paste the `RESULT:` and `EXIT:` lines from each. If you did
      not run them all, say which you skipped and what that leaves unverified — `2` is an abort and
      is not a pass.
- [ ] For a bug fix, a check that **fails** against the parent commit and passes here, with both
      results stated — including what you had to write to make that demonstrable.
- [ ] `powershell -File lw-watchtower\bin\lwg-doctor.ps1` was run and every non-`PASS` row is
      explained. **Expect exit `1`, not `0` or `2`**, and do not treat that as a reason not to open
      the pull request: `statusline` FAILS until you have copied the status line into your profile,
      and `state-dir` FAILS on a clone that is not junction-installed — both are findings about your
      machine rather than about your change. Say which rows you got and why each is expected. Exit
      `2` is warnings only, `3` is "could not complete" and is not a verdict at all.
- [ ] If this is the first commit on `main` after a tag, the declared version has moved off that tag
      — all five sites — and `CHANGELOG.md` has a section to put your entry in. See
      [Versions and releases](#versions-and-releases). CI checks that the five sites agree with each
      other on every push and pull request; it **cannot** check them against a tag, because it checks
      out without tag refs, so that half reports NOT CHECKED there.
- [ ] `powershell -File .github\scripts\redfirst_annotations.ps1 -Live` exits `0`, and
      `powershell -File .github\scripts\version_declarations.ps1 -Live` exits `0`. CI runs both, each
      after its own fixture pass, and a fixture failure fails the step before the tree is read.
- [ ] Every `.json` you touched still parses. CI checks every tracked `.json` with `git ls-files`, so
      a new one is covered the moment it is tracked.
- [ ] Every `.ps1` you touched parses:
      `[System.Management.Automation.Language.Parser]::ParseFile(...)`. CI does this too.
- [ ] Line endings unchanged for anything you did not otherwise edit.
- [ ] Documentation updated in the same PR if behaviour changed — `docs_coupling` will notice if it
      is not, and so will a reviewer.
- [ ] `powershell -File tests\portability_scan.ps1` exits `0`. No personal paths, usernames, tokens
      or machine names in the diff — see [Portability](#portability-no-local-environment-dependencies).
      CI runs this and a hit fails the build. If you added an allowlist entry, say why in the PR.
- [ ] If you touched anything under `.github\workflows\`, `powershell -File tests\workflow_guard.ps1`
      exits `0` — see
      [Workflows](#workflows-no-self-hosted-runner-no-pull_request_target-no-secrets). CI runs this
      and a hit fails the build. An allowlist entry needs its reason stated in the PR, and
      `secrets.GITHUB_TOKEN` is not exempt by default.
- [ ] The pull request body carries `Refs #N` for every issue it touches, and **never** `Closes #N` —
      `.github\scripts\pr_issue_ref.ps1` runs in CI and refuses a body without a reference.

### Adding or changing a module

Modules are declared in **two** places and they must agree:

1. `$LwgModuleRegistry` in [`lw-watchtower/lib/common.ps1`](lw-watchtower/lib/common.ps1) — the **source of truth**. It records
   kind (`gate` or `observe`), status (`implemented` or `planned`), the file carrying the behaviour,
   and the caveats.
2. `modules` in [`lw-watchtower/config.json`](lw-watchtower/config.json) — the flag. There is no
   second list in `$status` to keep in step with it any more; `$LwgModuleRegistry` is the
   authoritative one and `config-registry` holds the two together.

`/lw-watchtower:doctor`'s `config-registry` check fails when they disagree: a flag with no registry entry
is a switch wired to nothing, and a registry entry with no flag is a module nobody can turn off.

Three further requirements:

- **The flag must actually gate the behaviour**, with zero side effects when off — no log record, no
  state written, no subprocess, no file opened. **[review]**, and this is the gap that should worry
  you most: `config-registry` checks that the flag *exists*, and nothing anywhere checks that turning
  it off changes what the module does. Two modules here have already shipped as switches wired to
  nothing; that is the defect this plugin exists to catch, and the check for it is a person.
- **Only `implemented` counts as coverage.** The banner counts the registry, never the flags. If the
  data your module needs does not reach a hook, do not add the entry at all — write the evidence up
  in [`docs/modules.md`](docs/modules.md) instead, the way `ratelimit_escalation` and `cost_tracking`
  are recorded under *Attempted and blocked*. Both were carried as `planned` entries with
  `blocked = $true` until 30 July 2026 and then removed: the record is what stops a re-attempt, while
  a permanent placeholder in a switchboard only invites someone to switch it on. The `planned` and
  `blocked` machinery is kept for a module that is genuinely on its way.
- **`gate` means it can block.** If it warns, it is `observe`, however important it is. Calling an
  advisory a gate inflates the gate count, which is the same overstatement as counting an unbuilt
  module as coverage. **Exactly three modules in the registry are `kind = 'gate'` today —
  `delegate_gate` and `send_liveness_gate`, both registered on `PreToolUse` in
  `lw-watchtower/hooks/hooks.json`, and `completion_audit` on `Stop` and `SubagentStop`; all three
  ship switched off** — so a new `gate` is the **fourth** one, and needs the hook registration to go
  with it, not just the word. `config.json` records no live-gate count at all —
  `Get-LwgActiveGates` answers that from the registry and the switches — so a new gate needs no
  number updated anywhere, only its registry entry and its switch. Read
  [Gates were removed deliberately](docs/gates-removed.md) before you write one: it records what the
  four failed fix attempts on the last gate taught, and what a new attempt has to do differently.
  A gate's switch also lives outside the `modules` block, in `interaction` or `supervision`, and
  deliberately so: `Get-LwgConfig` fails **open**, and a corrupt config must never arm something that
  blocks.

### Adding a hook

- Register it in [`lw-watchtower/hooks/hooks.json`](lw-watchtower/hooks/hooks.json) in **exec form** (`command` + `args`), never
  `shell: "powershell"` — `pwsh` may be absent and the shell form mangles Windows paths.
  **[CI, partly]**: exec form is asserted for a **few specific registrations only** — each suite
  that drives a hook pins the registration it drives, and no rule reads the file as a whole. A new
  registration in shell form is caught by nobody.
- **Every hook exits 0 — with one deliberate exception, and getting it the wrong way round is how
  you ship a gate that blocks nothing.** A broken governance layer must never break a session, so
  every *observing* hook exits 0 whatever it found. A `PreToolUse` **denial** is the exception: the
  reason goes to **stderr** and the hook **exits 2**. Only exit 2 blocks a `PreToolUse` call.
  **Exit 1 is a non-blocking error and the tool runs anyway**, so a gate that computes a correct
  denial and exits 1 — or 0 — has silently failed open while every reporting surface still counts it
  as a live gate. `lw-watchtower/lib/gate_delegate.ps1` writes a stdout envelope as well, first, and its header
  records that the envelope is redundant on this CLI build because a nonzero exit makes stdout be
  dropped; the exit code is the load-bearing channel because an exit code cannot be malformed. Read
  `lw-watchtower/lib/gate_delegate.ps1`'s header before writing a `PreToolUse` hook — it is the only one in this
  tree and it is the worked example.
- Budget for it. **[review]** — no check here measures a hook, and CI's job timeout is not
  one: a hook costing an extra half-second per event fails nothing. (That timeout was ten minutes
  until 3 August 2026 and is thirty now, raised because the suites themselves outgrew it — which
  makes it an even worse proxy for a hook's cost, not a better one.) Turn-end and per-dispatch costs
  are measured, not assumed — see
  [docs/architecture.md](docs/architecture.md#turn-end-cost). A fresh Windows PowerShell 5.1 process
  costs ~250–280 ms before your code runs, and `ConvertFrom-Json`'s first call costs another
  141–182 ms. **A hook registration cannot be made conditional**, so a hook you add is paid for by
  every user on every matching event, including the ones who switch your module off.
- Same-event hooks run **in parallel**, so an event costs the max of its hooks, not the sum.

### Commits

All three below are **[review]**. There is no commit-message hook and no `commitlint`, and nothing
reads a commit *message* — the history complies because people have been careful, which is a fact
about discipline and not about enforcement. One commit property **is** enforced:
`.github/scripts/identity_scan.ps1` runs in CI and fails the build on a commit whose author or
committer identity is not on the allowlist. **[CI]**, and it says nothing about what the message
contains.

- Write the *why* in the body, not just the *what*. The existing history is the model: state the
  defect, the evidence, and what was measured rather than assumed.
- One logical change per commit where you reasonably can.
- If you used an AI assistant, keep its trailers. The existing history uses
  `Co-Authored-By:` and `Claude-Session:`.

---

## Versions and releases

### `main` must never declare a version a tag has already published

This is the rule, and it is not a style preference. A version identifier exists to tell one tree
from another. When `main` declares the same number as a published tag, it stops doing that — and
this project found out how expensive that is by doing it.

Between `v0.3.0` and the commit that wrote this section, `main` moved 12 commits and +5322/-489
lines while all five declaration sites still read `0.3.0`. Two of those commits changed how an
**existing `config.json` is interpreted**: `"interaction": { "delegate": "false" }` armed the only
gate this plugin ships at the tag and is ignored on `main`. So one number named two trees that
behaved differently on the same input, and nothing anywhere could tell a reporter which one they
were running.

**The manifests being byte-identical between the tag and `main` is the defect, not a defence.**

So: the moment a commit lands on `main` after a tag, the declared version is already wrong. Bump it
in the same pass, to the next number the change deserves — not at release time, when whoever is
cutting the release has to reconstruct which trees shipped as what.

### The five declaration sites, and the two kinds of `0.3.0` in this tree

A **declaration** is a field a machine reads. There are five, and they move together:

| Site | What reads it |
| --- | --- |
| `lw-watchtower/.claude-plugin/plugin.json` | Claude Code's plugin loader |
| `.claude-plugin/marketplace.json` | the marketplace entry for `lw-watchtower`; this one stays at the repository root, because it is the file the CLI reads to add the marketplace at all |
| `lw-watchtower/config.json` | the config's own `version` key |
| `lw-watchtower/lib/common.ps1` — `$script:LwgVersion` | the banner and every command that prints a version |
| `lw-watchtower/lib/session_start.ps1` — `$version` | the pre-`common.ps1` fallback banner, used when startup fails before the config loads |

Everything else that mentions a version is a **citation of a tag**, and citations do not move.
`adversarial UAT against v0.3.0`, `## [0.3.0] — 2026-07-31`, `lw-watchtower/bin/lwg-setup.ps1`'s note
about what changed in a release — all of those name the tested tree and are correct at `0.3.0` forever.
Rewriting one would be falsifying a record. **Getting this distinction wrong in either direction is
the failure mode**: bump a citation and you have destroyed history; leave a declaration and you have
shipped two trees under one name.

Prose *about* the current version — "the manifests declare `0.3.0`", or a sample banner showing what
a session prints — is a third category, and it is the one with no machine behind it. Sweep it by
hand at release. The table further down records what the `0.4.0` pass swept and the one page it
deliberately did not, so the next release starts from a known position rather than from a grep.

### What the machine checks, and what it does not

`tests/doc_claims.ps1` derives the declared version from all five sites and fails the build on two
rules:

- **`version-declarations-agree`** — all five state the same thing. This catches the half-finished
  bump, which is what happens when someone edits `plugin.json` and stops.
- **`version-not-a-published-tag`** — the declared version is not one `git tag -l` already lists.
  This is the rule this section exists for.

Two holes, both real, both stated rather than left to be discovered:

- **The tag-shaped half does not run in CI yet, and the reason is no longer the checkout depth.**
  Both workflows check out with `fetch-depth: 0`, so tag refs are visible; the pinned action is
  `actions/checkout` v7.0.1 by digest, not `@v4` at depth 1, and that sentence stood here after both
  facts had stopped being true. The rule reports **NOT CHECKED** because this repository has
  published **no tag at all** — `git tag -l` printing nothing is not evidence that nothing was
  tagged, so it declines rather than passing vacuously. It starts checking on the first tag push,
  with no change to any file. The agreement half does run: since 3 September 2026 a `Version declarations` step
  invokes `.github/scripts/version_declarations.ps1 -Live` on every push and pull request and fails
  the build when the five sites disagree with each other, and `release.yml` invokes the same guard
  with `-Tag` on a tag, which is the only caller that has one to ask with. Both callers run the
  guard's fixtures first and refuse to trust a live answer from a guard whose own rules did not fire.
  Run it on an ordinary clone, which includes the release pass, for the half CI declines.
- **It reads declarations, not prose.** A page saying "the manifests declare `0.3.0`" is invisible to
  it, deliberately — a pattern loose enough to catch that also catches every tag citation above, and
  no machine here can tell those apart. The `0.4.0` pass swept `README.md`, `docs/faq.md` and
  `docs/modules.md` — six sample banners and the "what version is this" answer — by hand. **One is
  left, deliberately:**

  | Where | What it says | Why it is still there |
  | --- | --- | --- |
  | `.github/notes/HANDOFF.md` | "the version string reads `0.3.0` everywhere that declares it" | The page is titled *Handoff — 31 July 2026 (v0.3.0 release)*. That sentence is a **record** of the day, and correcting a record falsifies it. Everything under `.github/notes/` is that kind of page. |

  **Decide record-or-claim for every one of these before you edit it**, because getting it wrong
  destroys history as easily as leaving it ships a lie. `SECURITY.md`'s *Supported versions* section
  was rewritten on 3 September 2026 for the same reason in reverse: it said `v0.3.0` was this
  repository's only tag, and this repository has never carried that tag at all.

### Cutting a release

1. Write the `CHANGELOG.md` entry **from `git log <lasttag>..HEAD`**, read in full. If a change
   alters how an existing `config.json` is interpreted, it is **BREAKING**, it gets a minor bump at
   minimum pre-1.0, and the entry names the exact config value that changes meaning and what an
   operator should check. A behaviour change on a file the operator already wrote is not a patch.
   **Date the heading in the same edit** — `## [0.4.0] — unreleased` becomes `## [0.4.0] — <date>`.
   `release.yml` refuses to publish while it reads `unreleased`, so forgetting this stops the release
   rather than shipping a wrong one; it is written here so it is done before the tag rather than
   discovered by a failed workflow after it.
2. Run `powershell -File tests\doc_claims.ps1` from a clone **with tags**, and confirm the
   `version-not-a-published-tag` line is not `NOT CHECKED`.
3. Tag, publish, and then **bump the declaration sites again on `main` in the next commit** — because
   from the instant the tag exists, `main` declaring that number is the defect described above.
4. The documented marketplace install route resolves the **default branch**, not the tag. It always
   will; there is no ref key in play. Do not write release notes that imply otherwise, and see
   [docs/install.md](docs/install.md) for the wording that tells a consumer the truth.
5. `v0.4.0` will be the **first tag this repository serves**. `v0.3.0` was tagged on a predecessor
   repository whose history this one does not carry, so step 2 has nothing to compare against until
   `v0.4.0` exists, and no page here should offer a reader an earlier tree to check out.

---

## Reporting issues

[SUPPORT.md](SUPPORT.md) is the front door and says which route each kind of report takes; what
follows is what this page adds for someone who has read it.

- **Bugs and false positives:** use the bug template. Include the exact command or path, your Claude
  Code version, Windows version and `$PSVersionTable.PSVersion`, and the relevant lines from the
  plugin log in the state dir. Find the state dir with `/lw-watchtower:doctor` — it prints the resolved
  path and whether it is the live one. "It did not stop something" is not a bug: nothing here stops
  anything.
- **Feature requests:** say what you want the plugin to *observe or block*, and — importantly —
  whether the data it would need actually reaches a hook. Two modules here are permanently blocked
  for exactly that reason.
- **Credential leaks, and damage to a `settings.json`:** [SECURITY.md](SECURITY.md), not a public
  issue. If the private advisory page is not available to you, the
  [Request a private channel](.github/ISSUE_TEMPLATE/private_channel_request.yml) form is the
  fallback and is the only one — blank issues are disabled here.

### The labels this repository defines

An issue form declares its labels in its own front matter, and **GitHub silently applies none of a
label it cannot resolve**. That is not a visible failure: the form accepts the submission, tells the
reporter it succeeded, and the issue arrives unlabelled and outside every triage query written to
find it. It happened here — `.github/ISSUE_TEMPLATE/security.yml` declared `security-process`, which
has never existed on this repository or its predecessor.

So this table is the roster a form may declare from, and `tests/doc_claims.ps1` fails the build if a
form declares anything not on it.

| Label | For |
| --- | --- |
| `bug` | something behaves differently from what the documentation says |
| `enhancement` | a feature request |
| `docs` | a documentation defect or gap |
| `documentation` | GitHub's default; `docs` is the one used here |
| `security` | a security-sensitive finding or a precondition of one |
| `test-coverage` | a surface that ships with no automated test |
| `unverifiable` | cannot be settled by any check available here |
| `blocked-on-owner` | needs an action only the repository owner can take |
| `dependencies`, `github_actions` | applied by Dependabot |
| `duplicate`, `good first issue`, `help wanted`, `invalid`, `question`, `wontfix` | GitHub's defaults, kept |

**What that check is and is not.** It compares two *tracked declarations* — this table and the issue
forms — exactly as the version rule compares the five declaration sites to each other. It does **not**
call GitHub, because no suite here uses the network or a credential, so it cannot tell you that a
label on this table still exists on the repository. Keeping the table true is a `gh label list` away
and is a person's job.

## Licence

By contributing you agree that your contributions are licensed under
[Apache-2.0](LICENSE), the licence of this project.
