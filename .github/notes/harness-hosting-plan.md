<!-- doc-claims:ignore-file — this is a PLAN. Every count and file path below a "Target"
     heading is a forward-declaration of intent, NOT evidence that any code exists.
     Nothing in this document is implemented at the time of its commit. Per the
     conventions of this repository, a name declared ahead of its code must say so:
     this whole file says so. tests/doc_claims.ps1 must read nothing here. -->

# Harness Hosting Plan — LEAPWare Claude Code Stack inside lw-watchtower

**Status:** PLAN ONLY. Approved direction by Founder decision (2026-09-02): ONE plugin —
the harness merges into lw-watchtower itself. No second plugin, no second marketplace
entry. This document records the full target design so implementation can proceed in a
dedicated session without re-deriving any of it. **No file other than this one and its
tracking issue changes under this commit.**

---

## 1. What is being hosted

The validated LEAPWare Claude Code harness (Windows 11 native), simulated end-to-end on
Ubuntu 24.04 and artifact-verified for `win_amd64` / Windows binaries on 2026-09-02:

| Layer | Component | Version verified | Delivery |
|---|---|---|---|
| Core | Claude Code | 2.1.258 | system (installer) |
| Observability | ccusage | 20.0.20 | on-demand `npx ccusage` |
| Terminal | RTK (Bash-tool rewrite hook) | 0.47.0 | system binary + global hook |
| Security | gitleaks | 8.30.1 | system binary |
| Security | semgrep (native win_amd64 wheel) | 1.176.0 | pipx |
| Behavior | vibesec, task-observer, unlazy, grill-me, ponytail skills | — | **plugin (this repo)** |
| Behavior | lw-handoff (original, replaces unlicensable upstream) | — | **plugin (this repo)** |
| Mode logic | stack_mode dispatcher (proto/ship ruleset injection) | tested (node PoC) | **plugin module (this repo)** |
| Docs MCP | Context7 | 4.0.4 | **plugin `.mcp.json` (this repo)** |
| Compression | headroom-ai[proxy] | 0.37.0 | pipx; launch = `headroom wrap claude` |
| Orchestration | herdr | 0.8.2 | system binary (Windows build = experimental tier) |
| Plugins | Superpowers | official marketplace | in-session install, unchanged |

**Banned permanently:** Omniroute (CVE-2026-49352; MITM design), Deepseek harness,
Openmontage. **Reserve bench (install only on proven need):** Serena MCP (repos >1k
files), claude-code-router, Firecrawl MCP.

## 2. Split of responsibilities

- **The plugin carries behavior:** skills, the stack_mode module, MCP declaration,
  commands. Versioned, junction-loaded, updated with the repo.
- **`bin/` carries the binary bootstrap:** a new `bin/lwg-harness.ps1` following the
  existing `lwg-*` conventions installs/updates RTK, gitleaks, semgrep, headroom, herdr
  into `%USERPROFILE%\.local\bin` and runs `rtk init -g`. Plugins cannot touch PATH,
  winget, or pipx — a script must.
- **Nothing here re-adds command, path, or credential inspection.** The owner's
  30 July 2026 removals stand. Secret and static scanning live OUTSIDE the plugin
  (gitleaks, semgrep, vibesec skill) and are installed by the bootstrap script, not by
  any hook. This plan adds no gate and no permissions.deny rule.

## 3. Target: the `stack_mode` module

New module registered per this repo's conventions:

- **Registry entry** in `lib/common.ps1` `$LwgModuleRegistry`: `kind = 'observe'`
  (it injects context; it can never block), `impl = 'lib/stack_mode.ps1'`, flag is a
  plain `modules` key (`"stack_mode": true`) — fail-open is correct for an injector:
  an unreadable config injects nothing and exits 0.
- **Hook registrations** in `hooks/hooks.json`: `SessionStart` and `SubagentStart`,
  both invoking `lib/stack_mode.ps1 -HookEvent <event>` via `powershell` (PS 5.1,
  matching every other registration). SubagentStart matters: CLAUDE.md snapshots at
  parent-session start, so per-dispatch injection is the only way a worker gets the
  current mode — same rationale as context_injection.
- **Behavior:** resolves PROTO vs SHIP per session — precedence: `CLAUDE_STACK_MODE`
  env (`proto|ship|off`) → `.stackmode` marker file in cwd → path roots from
  `module_config.stack_mode` (`ship_roots`, `proto_roots`) → `default` (proto).
  PROTO injects `skills/ponytail/SKILL.md`; SHIP injects `skills/unlazy/SKILL.md`;
  OFF emits nothing. Output: `hookSpecificOutput.additionalContext` with a one-line
  mode banner. This makes ponytail/unlazy collision structurally impossible (one mode
  per session) and eliminates all per-repo installs — Unlazy's project-scoped
  `install-hooks.mjs` is never run; its Stop hook is deliberately NOT adopted (this
  repo's Stop surface already carries three registrations and the module stays
  observe-only).
- **Implementation language:** PowerShell 5.1 port of the tested node PoC
  (recommended, pending Founder confirmation — see §7). No dot-sourcing of
  common.ps1 on the hot path, per the context_injection precedent (634 ms measured
  cost of dot-source + JSON parse vs 273 ms floor).
- **Config:** `module_config.stack_mode` block with `ship_roots`, `proto_roots`,
  `default`, and both `$status.implemented` and `modules` updated in the same change.
- **Tests:** `tests/stack_mode.ps1` — fire PROTO on proto path, SHIP on ship path,
  marker override, env override, OFF silence, corrupt-config silence.

## 4. Target: vendored skills and licensing

Skills land under `skills/` at plugin root with a new `THIRD-PARTY-NOTICES.md`:

| Skill | Upstream | License | Action |
|---|---|---|---|
| vibesec | BehiSecc/VibeSec-Skill | Apache-2.0 | vendor + notice (same license as this repo) |
| unlazy | Leonxlnx/unlazy | MIT | vendor SKILL.md only + notice |
| ponytail | dietrichgebert/ponytail | MIT | vendor skills/ponytail/SKILL.md only + notice |
| grill-me | mattpocock/skills | MIT | vendor SKILL.md only + notice |
| task-observer | rebelytics/one-skill-to-rule-them-all | **CC BY 4.0** | vendor + mandatory attribution (Eoghan Henn / rebelytics.com) |
| handoff | ykdojo/claude-code-tips | **All Rights Reserved — CANNOT vendor** | replace with original `lw-handoff` SKILL.md written from scratch |

This repo is public; the notices file is therefore mandatory, and vendored copies
freeze — a small upstream-sync script (`bin/lwg-harness-sync.ps1`) is in scope.

## 5. Target: honest-count updates (the part that must not be skipped)

Merging one module changes numbers this repo asserts in prose, and the repo's own
rule is that a stated count must be true:

- Module registry: 13 → 14 names; observe modules 10 → 11 (`stack_mode`).
- Hook registrations: 13 → 15 (SessionStart +1, SubagentStart +1).
- `plugin.json` and `marketplace.json` descriptions restated with the new counts.
- `config.json` `$status.implemented` gains `stack_mode`; `planned` stays empty;
  `gates_live` stays 0 — this plan arms nothing.
- SessionStart banner counts follow from the registry with no extra edit.
- `bin/lwg-doctor.ps1` config-registry parity must pass; the doctor is the acceptance
  gate for the whole merge.

## 6. Versioning and changelog

`0.4.0` is declared and unreleased; per this repo's rule (main must never declare a
version a tag has published), the merge lands as entries in the open `[0.4.0]`
CHANGELOG section — no version bump unless `v0.4.0` is tagged before implementation
begins, in which case the merge declares `0.5.0`.

## 7. Open Founder decisions (blocking implementation start)

1. **Repo visibility.** LEAPWare-Watchtower is currently the account's only public
   repo. Vendoring proceeds either (a) public with full notices, or (b) repo flipped
   private. Plan assumes (a) until decided.
2. **stack_mode language.** PS 5.1 port (recommended; zero new runtime deps,
   consistent with the repo) vs. keeping the tested node script (adds a node
   dependency to a repo that currently has none).

## 8. Implementation phases (each independently committable, doctor-green)

1. `THIRD-PARTY-NOTICES.md` + `skills/` (6 dirs incl. original lw-handoff) — inert
   until the module exists.
2. `lib/stack_mode.ps1` + registry entry + config flag + hooks.json + tests +
   docs/modules.md section + count restatements — one commit, doctor-green.
3. `.mcp.json` (Context7) + docs note on the ~4-plugins/2-MCPs context budget.
4. `bin/lwg-harness.ps1` bootstrap + `bin/lwg-harness-sync.ps1` + docs/install.md
   section.
5. CHANGELOG entries under `[0.4.0]`; UAT: fresh Windows 11 machine, marketplace add →
   plugin install → bootstrap → verify RTK hook fires, both mode banners, subagent
   injection, doctor pass.

## 9. Conflict-scan record (basis for this plan)

Scanned 2026-09-02 against hooks/hooks.json and config.json at then-current main:
no hard conflicts. SessionStart/SubagentStart additions are additive; RTK's PreToolUse
Bash rewrite coexists with delegate_gate in both switch states; the harness adds zero
Stop hooks; the security layers are disjoint by construction (this plugin inspects no
command, path, or credential — gitleaks/semgrep/vibesec cover exactly what was removed
30 July 2026, from outside the hook system). One correction the merge delivers: the
node PoC injected rulesets on the main thread only; SubagentStart registration closes
that gap for workers.
