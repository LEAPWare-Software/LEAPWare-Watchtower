---
name: lw-handoff
description: "Land the work that is in flight and write a handoff another session can resume from, before a context or rate-limit wall ends the turn for you. Start it when the LW-WATCHTOWER transition ladder says amber or red, or by name at any time."
when_to_use: "The transition ladder has reported amber or red, or the operator has asked for a handoff. Also correct before any deliberate session change - a compaction, a machine change, or a lockout you can see coming."
---

<!--
  Shipped by the LW-WATCHTOWER plugin. THIS FILE IS OVERWRITTEN ON PLUGIN UPDATE -
  do not hand-edit it in place. To change it, copy it to ~/.claude/skills/ (or the
  project's .claude/skills/) and edit the copy; a user or project file of the same
  name shadows this one. See docs/roles.md.

  ORIGINAL WORK. This procedure was written for this plugin. Nothing in it is
  copied, adapted or derived from any other party's handoff skill.

  HOUSE STYLE for anyone adding tool keys to a skill in this directory: the
  spelling is kebab-case - `allowed-tools` and `disallowed-tools`, the CLI's own
  documented form. `disallowedTools` is the normalized alias and is what the
  plugin's `agents/` pages use; do not carry that spelling into `skills/`.
  Decision recorded on #168, 2026-09-06.

  This file declares NO tool keys. The procedure below uses whatever the session
  already carries, and an allowlist naming a subset could not be verified from
  inside this repository - no lane here is permitted a live session. A tool
  allowlist that has never been exercised is a claim, not a control.
-->

# Handoff

Invoked as `/lw-watchtower:lw-handoff`, or started by the model when the transition ladder
reports amber or red at a turn end.

**What this is for.** A session ends whether or not you are ready: the context window fills, a
5-hour limit closes, a 7-day limit closes. The failure is not the ending. The failure is ending
with work that exists only in this transcript - a branch nobody pushed, a decision nobody wrote
down, a next step only you knew. This procedure converts what is in your head into artifacts on
disk and in the tracker, in an order that finishes even if you are cut off part-way through.

**Order matters, and it is the order below.** Each step is durable before the next begins. If the
turn ends after step 2, step 2's work survives.

---

## Step 1 - Stop taking on work

Start nothing new. Dispatch no new agents. Do not begin a refactor, a new file, or an
investigation whose answer you will not have time to use.

If work is already running, let it finish where finishing is close. Where it is not, treat it as
unfinished in step 3 and say so.

## Step 2 - Land what can be landed

For every repository you have touched this session, in this order:

1. `git status --porcelain=v2 --branch` - know what is uncommitted and what branch you are on.
2. Commit the work that is coherent. A commit that does one thing and says so is worth more than
   a tidy tree.
3. Push. **An unpushed commit is not landed.** A branch that exists only on this machine is lost
   with this machine.
4. Anything that cannot be committed - a broken build, a half-applied refactor - is named in
   step 3 rather than committed to hide it.

Never force-push and never rewrite history here. A handoff is not the moment to be clever with
git.

## Step 3 - Write the handoff package

Write it to a file the next session can find, and say where. Four sections, all four required.

### 1. Work in flight

Every effort that is running or unfinished, one line each: what it is, where it is, what state it
is in.

> **Read this before you fill the section in.** The plugin cannot tell you what agents are
> running. Nothing records a dispatch - `SubagentStart` writes no record and only `SubagentStop`
> is logged - so a running agent is invisible to every part of this product. An empty in-flight
> section means *nothing was observable*, never *nothing is running*.
>
> So this section is **written from your own knowledge of this turn**, not read off a file. If
> you dispatched an agent and never saw it return, that is a line here. If you do not know
> whether something is still running, that is a line here too, said as unknown.

### 2. The commit and branch every note describes

For each repository: the branch name and the SHA your notes are true of. A note that says "the
parser is fixed" is worthless without the commit it is true of - the next session will read it
against a different tree.

Include the remote you pushed to. Say plainly if anything is unpushed.

### 3. Next actions, in order

Numbered, ordered, and each one small enough to start cold. "Continue the refactor" is not a next
action. "Rename `Get-Foo` to `Get-Bar` in `lib/foo.ps1` and re-run `tests/foo.ps1`" is.

Put the blockers first, and for each blocker say what would unblock it.

### 4. What you are not sure of

Every assumption you did not verify, every result you did not re-measure, every claim you are
carrying on trust. This is the section that a rushed handoff drops, and it is the one that costs
the next session the most.

---

## Step 4 - Record it where a new session will look

A file on disk is not a handoff if nobody opens it. Put the package, or a link to it, where this
project's next session will actually read it - the tracker issue the work belongs to is usually
that place. Say which issue, by number.

Do not open a new issue to hold a handoff. Comment on the one the work belongs to.

## Step 5 - Say what you did

One short message to the operator: what landed, what did not, where the package is, and the one
thing you would do first on resuming.

---

## Rules that apply to every step

- **Never overstate.** "Pushed to `origin/lane/x` at `abc1234`" is a fact. "Everything is
  committed" is a claim you must have checked. If you did not check it, say you did not.
- **Never invent a measurement.** A number you did not take is written as *not measured*.
- **Mask what identifies a machine or a person.** Paths in a handoff are written as
  `<clone-root>/path/to/file`, accounts as `<operator>`, and machines as `<hostname>`. A handoff
  is read by people who are not you, on machines that are not this one.
- **A queued message is not a delivered one.** If you sent something to another agent and did not
  see a reply, that is work in flight, not work done.

## What this procedure does not do

- It does not schedule anything. Nothing in this plugin can wake a session up, and a handoff
  written for a 7-day lockout is a handoff a human or a new session has to pick up by hand.
- It does not audit itself. An adversarial check of the package is a later addition; today the
  package is as good as the care you took writing it.
- It does not block the turn from ending. The ladder warns; it does not refuse.
