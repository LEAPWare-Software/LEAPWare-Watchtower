# LW-WATCHTOWER

**WINDOWS ONLY.** This plugin requires Windows PowerShell 5.1. Every one of the
hook registrations in `hooks/hooks.json` invokes a binary literally named
`powershell`, which does not exist on macOS or Linux. PowerShell 7 (`pwsh`) is
not a substitute, and the reason is that name and not the language level: every
script here declares `#requires -version 5`, which PowerShell 7 satisfies, so a
reader who tries it finds the scripts run and the hooks never fire.

This directory is the plugin payload — the subtree
`.claude-plugin/marketplace.json` declares as its `source`, and the only part of
the repository that is copied to your machine when you install. It is not the
whole project.

## Where everything else is

The documentation, the test suites, the changelog and the contribution guide all
live in the repository and are **not** copied here, so a relative link out of
this directory does not resolve on your machine. They are on the web:

- **Repository** — <https://github.com/LEAPWare-Software/LEAPWare-Watchtower>
- **Documentation** — <https://leapware-software.github.io/LEAPWare-Watchtower/>

Read the **Limitations** page before any other. It is the consolidated account
of what this plugin does not do, cannot do, and does not check, and everything
this project claims rests on being accurate about that.

## Licence

Apache-2.0. `LICENSE` beside this file is a byte-identical copy of the
repository's, kept here because this subtree is what is distributed and the
licence has to travel with it. A test asserts the two are identical, so they
cannot drift.
