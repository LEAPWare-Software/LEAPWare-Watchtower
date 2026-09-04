# Support for LW-WATCHTOWER

A Windows-only Claude Code plugin maintained by one account, [@LEAPWare-HQ](https://github.com/LEAPWare-HQ),
which is also the support owner. This page says where to ask, what to include, and what you get back.

## The promise

A human replies within **five working days**. A reply is not a fix: it tells you whether your report
reproduced, how it was classed, and whether and when it will be worked. Nothing on this page promises
a fix or a date.

## Where to file

One route per kind, and the route is the whole instruction.

- **A question** — *how do I, is this expected, which switch* — goes to
  [Discussions › Q&A](https://github.com/LEAPWare-Software/LEAPWare-Watchtower/discussions/categories/q-a).
  Blank issues are disabled, so a question filed as an issue meets a form it cannot honestly complete.
- **A bug** goes through the **Bug report** form at
  [issues › new](https://github.com/LEAPWare-Software/LEAPWare-Watchtower/issues/new/choose). Read
  [docs/modules.md](docs/modules.md) first if the report is that something was not stopped: most of
  the registry observes and can block nothing at all, and every gate ships switched off.
- **A feature request** goes through the **Feature request** form, same chooser.
- **A vulnerability** — a credential reaching this plugin's logs, state, status line or injected
  context, or the installer or uninstaller damaging `settings.json` — goes through **private
  vulnerability reporting** as [SECURITY.md](SECURITY.md) describes, and **never** through a public
  issue or a Discussion. `SECURITY.md` owns that path entirely; this page only points at it.
- **Not supported channels:** email, direct messages, social media. A report there gets no reply and
  no timer.

## What to include

The bug form asks for these; a Discussion should carry them too.

- The version line from the session-start banner.
- The Claude Code version.
- Your Windows version and `$PSVersionTable.PSVersion`.
- The whole output of `/lw-watchtower:doctor`, uncut.
- Which event or command was running.
- What you expected and what you saw.
- Every `lw-watchtower/config.json` flag you changed from its default, and the contents of
  `config.override.json` in the state directory if one exists — that file is where
  `/lw-watchtower:config` and `/lw-watchtower:delegate` write, and it wins over the shipped defaults.

**Redact credentials before pasting a log.** If one is in a log this plugin wrote, that is a security
report, not a support request — see [SECURITY.md](SECURITY.md).

## What you get back

- A human reply inside five working days.
- A `sev:` label and a milestone if it is accepted as a defect.
- The issue is the only tracker and the only place the answer lives. Nothing is promised in a
  Discussion that is not written on an issue.
- A closed issue names its closure class: fixed with a case, does not reproduce, documented
  limitation, or removed.

## Pull requests are not a support route

Code is by invitation — open an issue first. [CONTRIBUTING.md](CONTRIBUTING.md) says why, and says
what an invited contributor's pull request has to carry.

## Scope

Windows and Windows PowerShell 5.1 only, and this is not a security boundary. Read the README's
[What this does NOT do](README.md#what-this-does-not-do) before filing.
