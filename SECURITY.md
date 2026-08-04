# Security policy

## Reporting a vulnerability

**Do not open a public issue for a security report.**

Use **GitHub's private vulnerability reporting** on this repository:

> **Security** tab → **Report a vulnerability**

That opens a private advisory visible only to you and the maintainers. It is the preferred channel
because it needs no email address, keeps the report out of public view while it is being fixed, and
gives us a place to coordinate a fix and a disclosure with you.

If that tab is not available to you — you are signed out, or private vulnerability reporting is not
enabled on this repository, in which case `/security/advisories/new` returns 404 for everyone — use
the **[Request a private channel](.github/ISSUE_TEMPLATE/private_channel_request.yml)** issue form.
It asks for a channel and **no details whatsoever**, and its two required boxes are both true for
someone in that position. A maintainer (`@LEAPWare-HQ`, the role account that owns this repository —
see [`.github/CODEOWNERS`](.github/CODEOWNERS)) will open a private advisory and invite you to it.

**That form is the fallback, and "open a public issue" is not.** Until 3 August 2026 this page and
`.github/ISSUE_TEMPLATE/security.yml` both told a reporter to open a public issue with a fixed
one-line body. There was no such route: `.github/ISSUE_TEMPLATE/config.yml` disables blank issues,
and each of the three forms that remained required ticking a box a vulnerability reporter would have
been asserting falsely — *"this is not a security issue"* on the bug report, *"this is a question
about the process, not a report"* on the security form. The documented escape hatch ended in a
closed door on the one page where a wrong turn is expensive.

No personal email address is published for security reports, and none should be used for one.

### What to include

- What the issue is, in one or two sentences.
- The exact command, path, file content or payload that triggers it — verbatim, not paraphrased.
- Which module or file you believe is involved (`lib/common.ps1`, `lib/supervisor.ps1`, …).
- Your Claude Code version, Windows version and `$PSVersionTable.PSVersion`.
- What you expected to happen instead.

A working proof of concept is welcome. Please do not run one against a repository you do not own.

## Response expectations

This project is maintained by a very small team. These are commitments, not aspirations, and we
would rather state modest ones and meet them:

| Stage | Target |
| --- | --- |
| Acknowledgement that the report was received | **5 business days** |
| An initial assessment — in scope or not, and a rough severity | **10 business days** |
| A fix, or a written decision not to fix with the reasoning | **90 days** from acknowledgement |

If a report goes unacknowledged past those windows, you are free to disclose publicly. We would
appreciate a heads-up first, but you do not owe us one.

We will credit you in the advisory and the [CHANGELOG](CHANGELOG.md) unless you ask us not to.

## Supported versions

Pre-1.0. **`v0.3.0` is tagged** — the first and so far only tag this project has had — and
**only the current `main` branch is supported.** Fixes land on `main`; there are no backports and no
maintained release branches, so a tag is a marker of what was released and **not** a line that will
receive a security fix. If you are running `v0.3.0`, move to `main` to get one.

| Version | Supported |
| --- | --- |
| `main` | ✅ |
| `v0.3.0` and any other tag | ❌ — released, not maintained |
| anything else | ❌ |

## Scope

This is a governance plugin for Claude Code. It runs as a set of PowerShell hooks on the operator's
own machine, with the operator's own privileges. That shapes what a vulnerability *is* here.

**THERE IS NO SECURITY GATE TO BYPASS.** Both security gates were removed at the owner's explicit
instruction on 30 July 2026 — `destructive_gate` first, then `secret_scan`, which was the last one —
and this plugin installs no `permissions.deny` rules. It cannot refuse a force push, a hard reset, a
history rewrite, a recursive delete, a `.git` write, a write to a credential file, or a write
carrying a live token. **None of that is a vulnerability here — it is a decision.** Please do not
report any of it.

**One `PreToolUse` gate does ship, and it is not a security control either.** `delegate_gate`
refuses `Edit`, `Write`, `NotebookEdit`, `Bash` and `PowerShell` on the main conversation when
`interaction.delegate` is on, and it **ships off**. It exists to keep the chat session for talking to
the operator, not to defend a boundary: it reads no path, no command and no content — only the
presence of `agent_id`, plus `tool_name` after the fact to word its refusal — and the operator
it refuses can turn it off by editing one key. Getting a call past it is a **bug report**, not a
vulnerability report — open a public issue. What remains in scope is narrower, and real.

### In scope

- **A secret leaked by the plugin itself.** This is now the highest-value report this project can
  receive. Any path by which a credential or token reaches `health.jsonl`, `lw-watchtower.jsonl`, the
  status line, a `systemMessage`, `advisory-<sessionkey>.json` in the state directory, or a
  subagent's injected context. That fourth destination was missing from this list until 3 August
  2026, and it is the one a real defect used: `mission_drift` writes the anchors it derives from the
  operator's prompt there, and quotes up to four of them back. `Get-LwgRedacted` in
  `lib/common.ps1` is the only control standing between payload text and those destinations, and
  **a shape it does not catch is a real finding**. The plugin reads transcripts, hook payloads and
  edited paths, so it handles material that may carry secrets even though it no longer scans for
  them.

  **This page used to say that helper existed "so this cannot happen". That was an overstatement,
  and it was wrong in a way that had already shipped.** Until 3 August 2026 its generic rule
  required a key name to be followed *immediately* by a colon or an equals sign, so a single quote
  defeated it — and `lib/supervisor.ps1` manufactured the quoted form itself, piping every
  non-scalar payload field through `ConvertTo-Json -Compress` before handing the string to the
  redaction. `{"api_key":"…"}`, `{"token":"…"}`, `Authorization: Bearer …` and
  `export SECRET_VALUE=…` all went through untouched, into `health.jsonl` and — on the
  `PostToolUseFailure` path — into the stderr that `asyncRewake` injects into the live session.
  Eleven regression cases came with **that** fix — this is not the suite's total for the helper, and
  more were added on 3 August; see the bullet below. The split matters: **nine are unit cases on the
  helper, of which seven were confirmed to fail at the commit before the fix and two cannot fail
  there and say so in their own failure message** — one pins idempotency across the new shapes, the
  other is the blast-radius guard that an ordinary health record is left alone. The remaining two
  (`C9`) drive `lib/supervisor.ps1` end to end in a child process and were both confirmed red. So:
  nine of eleven proven red, and the two that were not are marked as such in the suite rather than
  counted as proof.

  **Seven further cases landed on 3 August 2026** for the defects listed under *"That rewrite was not
  a one-way trade"* and in the two bullets about `Bearer` values and PEM bodies. Four are unit cases
  in section A and three are `B19`, which drives `lib/stop_advisories.ps1` end to end. **Six of the
  seven were confirmed red first**; the seventh is `B19`'s anti-vacuity guard and says so in its own
  failure message. Their baseline is stated per case and it is **not** uniform. All six were proven
  red against the working tree immediately before this fix. Against `fd8d023` they were **measured**,
  not assumed, by putting the same specimens through all three copies of `lib/common.ps1`: the
  `Bearer`, array and PEM cases go red there as well, and **the newline case passes there** — the
  rule `fd8d023` shipped crossed a newline and the rule that replaced it stopped doing so, so that
  case is a regression against the 3 August rewrite alone. Calling it an `fd8d023` regression would
  have been false in the direction that flatters this fix.

  **That rewrite was not a one-way trade, and saying so was the same defect again.** The rule it
  replaced used `\s*[:=]\s*(\S{6,})`, which crossed a newline and ran through punctuation. Eight
  shapes it *had* masked stopped being masked on 3 August 2026 and were published as pure gain —
  including `token:` followed by a newline and its value, which is **reachable**: `ConvertTo-Json`
  turns a real newline into `\n`, so a multi-line `error.stderr` arrives in exactly that form and the
  credential went into `health.jsonl` in the clear where the older rule had masked it. Two of the
  eight (both newline spellings) are closed as of the same date; the other six are the value-class
  exclusions listed below and are a boundary, not a to-do. The cost of closing the two is stated
  rather than hidden: the false positive the narrowing was written to remove is back, so `token:` at
  the end of a line will take the next line's first word when that word is six or more characters.

  **What it catches, stated so the boundary is checkable rather than assumed:**

  - the five vendor shapes in `$script:LwgSecretPatterns` (GitHub token, GitHub PAT, AWS key id,
    PEM private key, Slack token), anywhere in the text, with no key name needed;
  - a named key and its value — bare (`api_key: v`), JSON-quoted (`{"api_key":"v"}`),
    escaped-JSON (`{\"api_key\":\"v\"}`), as the **first element of a JSON array**
    (`{"api_key":["v"]}`), with a newline between key and value in either the raw or the
    `ConvertTo-Json` escaped spelling, or with the name extended around the keyword
    (`SECRET_VALUE=v`, `x-api-key: v`). The keyword list is short on purpose: `password`,
    `passwd`, `passphrase`, `secret`, `token`, `credential`, `api_key`, `private_key`,
    `access_key`, `signing_key`, `encryption_key`;
  - an `Authorization` or `Proxy-Authorization` header, with or without a
    `Bearer` / `Basic` / `Digest` / `Token` / `ApiKey` scheme word — **including a value that itself
    begins with one of those words** (`Authorization: Bearer token-9f3a…`). That last clause is not
    decoration: this bullet claimed the whole header shape from 3 August 2026 while the guard that
    keeps the rule idempotent ended in `\b`, which disqualified any value merely *starting* with a
    scheme word and made the rule match **nowhere** in such a string. A hyphen was all it took. It is
    pinned by a case in `tests/stop_behaviour.ps1` that was confirmed red first;
  - a **PEM private key block**, `BEGIN` line through `END` line, when both are present and within
    4096 characters of each other;
  - a password in a URL's userinfo (`https://user:pw@host`), which `git` and `gh` print into
    stderr on nearly every failure.

  **What it still does not catch. Each of these is a real shape, and each is in scope as a report:**

  - **a value under six characters** — the floor exists so ordinary prose is not shredded;
  - **a value containing a quote, comma, semicolon, brace, bracket or backslash** — the match stops
    there, and if what precedes the stop is under six characters nothing is masked at all. Those
    characters are excluded so that masking inside a JSON string leaves the structure intact and so
    that the `[REDACTED]` marker can never be re-matched on a second pass. These are the six shapes
    the pre-3-August rule *did* mask, so for them this helper is a **step back**, not forward;
  - **a PEM body whose `END` line is missing or more than 4096 characters away**, or a body pasted
    with no `BEGIN` line at all. The complete block is caught; a truncated one still loses only its
    `BEGIN` line;
  - **a credential anywhere but the head of an array** — `{"api_key":["v"]}` is caught,
    `{"api_key":["xy","v"]}` is not, and the whole record comes back untouched. The rule anchors on
    the key name and only the first element follows it;
  - **a credential with no name and no vendor prefix** — a bare token on its own line, or one named
    by a word not in the list above (`cookie`, `signature`, `otp`);
  - **a scheme word with no header name** — `-H "bearer <jwt>"` with no `Authorization:` in front
    of it. The header rule anchors on the header name deliberately, because `bearer` alone is too
    common a word to key on;
  - **a credential split across two fields**, or assembled from pieces.

  It fails toward **over-**redaction: `token_count: 123456` is now masked, which loses evidence.
  That direction is the deliberate one — a masked field costs a reader some context, an unmasked
  one costs a credential. Two consequences of that are worth naming because they are not merely
  "some context": `&` is not excluded from the value class, so
  `GET /v1/x?api_key=…&page=2` loses every parameter after the credential; and a **numeric** JSON
  field becomes `{"tokens_used":[REDACTED]}`, which is not valid JSON. So masking does *not* always
  leave the record in the shape it arrived in, and the claim that it did has been removed from
  `lib/common.ps1` rather than left standing.
- **Damage to an operator's `settings.json`.** `bin/lwg-setup.ps1` and `bin/lwg-uninstall.ps1` are
  the only things here that write it. A merge that drops, reorders or corrupts a key the operator
  owns, a backup that does not hold the original bytes, a rollback that does not restore, or a
  `permissions.deny` rule mis-attributed to this plugin and removed when it was the operator's own —
  all real findings. **`tests/setup_merge.ps1` covers the merge again**: the harness that covered it
  end to end was deleted with `secret_scan`, and this one was written against the sections the
  installer still writes. The byte-level writer properties are established on `statusline`; the
  `hooks` section is covered for what it **decides** — that an existing marketplace install is seen,
  and that a registration of the same script under another root is reported rather than duplicated —
  and only **inherits** the writer properties, since both go through the same `Save-Settings` path.
  `bin/lwg-uninstall.ps1`'s `settings.json` edits have no case at all, and reports against any of
  that are especially valuable.
- **Code execution through plugin data.** If a crafted `config.json`, `context/worker_facts.md`,
  transcript, or hook payload can cause a hook to execute attacker-controlled code, that is in scope
  even though those files are normally operator-controlled.
- **A write outside the resolved state directory.** Anything that induces a hook to read or write a
  path outside the plugin's data dir — a session id that escapes `Get-LwgSessionKey`, for instance.
- **Anything the documentation claims and the code does not do**, where the gap is
  security-relevant. Overstated coverage is the defect this project was built to remove; a
  documented control that does not exist is a vulnerability here, not a doc bug. Given that this
  plugin has just removed all of its enforcement, a doc still promising enforcement is exactly this.

### Out of scope

These are not vulnerabilities in this project.

- **That anything at all runs.** See the notice above. No command, path or file content is inspected
  before a tool call, because there is no hook that could inspect one.
- **The absence of `permissions.deny` rules.** This plugin no longer writes any. Rules already in
  your `~/.claude/settings.json` are yours; setup never removes them, and only
  `/lw-watchtower:uninstall -Apply -RemovePermissions` will, on request.
- **Advisories failing open.** Every remaining module observes and warns. One that errors, times out
  or stays silent lets the turn finish, by design. A *silent* failure that also suppresses the
  health record of itself is in scope; a warning that simply did not fire is not.
- **Anything requiring the attacker to already have write access to the plugin root, your
  `settings.json`, or your `~/.claude/` directory.** At that point they can disable the plugin
  outright; there is nothing to defend.
- **Anything the operator can do to their own machine on purpose.** What is left here observes an
  agent's mistakes and an operator's slips after the fact; it never guarded against the operator,
  and it no longer guards against anything.
- **Vulnerabilities in Claude Code, PowerShell, `git` or `gh` themselves.** Report those upstream.
  We will help you work out where, if you are unsure.
- **Missing hardening with no demonstrated impact** — a scanner finding with no path to an effect.
- **The advisory modules failing to warn.** They are advisory by construction and are documented as
  such; a missed warning is a bug report, not a security report.
- **Output styles not being honoured.** They are system-prompt requests. Nothing can block assistant
  text before you see it, and [we say so](docs/output-styles.md#what-these-cannot-do).

## Disclosure

We prefer coordinated disclosure. Once a fix is on `main`, we will publish a GitHub Security
Advisory describing the issue, the affected behaviour, and the commit that fixed it — including a
check that **fails against the commit before the fix**. A finding without such a check is not
considered closed. Nine suites in this repo establish a behaviour, and between them they reach the
one gate (`tests/gate_delegate.ps1`), the installer's `statusline` merge and `hooks` decisions
(`tests/setup_merge.ps1`),
the two turn-end hooks (`tests/stop_behaviour.ps1`), the uninstaller's state-data deletions
(`tests/uninstall_footprint.ps1`), the evidence engine (`tests/evidence_states.ps1`), two of the
doctor's nine checks (`tests/doctor_behaviour.ps1`), the toggle's write to `config.json`
(`tests/toggle_behaviour.ps1`), the `SubagentStart` fast path (`tests/subagent_scan.ps1`) and what
the shipped payload discloses (`tests/payload_guard.ps1`). The 233-case
gate suite went with `destructive_gate` and the `permissions.deny` parity harness went with
`secret_scan`, and **nothing replaced what either covered** — nothing here inspects a command, a path
or a credential to have a harness for. So unless your finding lands inside one of those five, closing
a report means writing a check, not reusing one.

## What this plugin does not protect

Stated here so a security reader does not have to infer it:

- It is not a sandbox, not a permission system and not an audit log you can rely on in an adversarial
  setting. The logs are local JSONL files with no integrity protection.
- It runs with your privileges. It cannot stop anything a process with your privileges is determined
  to do.
- **It registers exactly one `PreToolUse` hook, and it makes no safety determination.** That is
  `delegate_gate`, described in full above: it can express a denial to the CLI, and the only thing it
  ever asks is whether the call came from a subagent. It ships off. **Every other hook here** runs at
  session start, after a tool has already succeeded, or at turn end — by the time any of those sees
  anything, the thing has happened. So there is still no hook on this machine that inspects a
  command, a path or a file's content before it runs, which is the fact this bullet is for.
- The one layer that could not fail open — `permissions.deny`, which the CLI evaluates itself before
  any hook runs — is no longer written by this plugin. If you want it, write it yourself.
