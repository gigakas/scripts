# AGENTS.md

This file provides guidance to AI coding agents working in this repository. It mirrors `CLAUDE.md`
(Claude Code's equivalent file) — keep both in sync when either changes.

> **Project placeholders to fill when instantiating:** "What this is", "Commands", "Architecture",
> and anything marked <…>. Everything else is the standard methodology — keep it.

## Language

Everything written in this repo — code, comments, commit messages, `CHANGELOG.md`/`changelog.d/`
fragments, and this file — is in English, regardless of what language the user writes to you in
during a session.

## Plan first

No implementation work starts until `PLAN.md` exists and is approved. Architecture and scope
decisions are made in the plan first, then implemented. If work is requested that contradicts the
plan, update the plan and get it approved before coding.

## What this is

<One paragraph: what the product is, the problem it solves, and its main user-facing surface.>

## Commands

<Exact build/run/test commands from the repo root, including any project-specific tooling
quirks. These were defined in PLAN.md's verification strategy; keep them current here.>

## Architecture

<A short summary: components and responsibilities, process topology, data stores, configuration
hierarchy. Enough for an agent to know which project a change belongs in.>

## Code quality

- **Layering.** Each layer talks only to its declared neighbors; data access lives behind its own
  types, not inline in UI or orchestration code. New cross-cutting behavior slots into the
  existing patterns, not as a special case bolted onto the largest type.
- **Dead-code hygiene.** Abandoned drafts are deleted, not left behind under variant names
  (`Copy`, `OLD`, numbered prefixes, `BUTTA`, `Test`, `BackUp`). Check the build files before
  assuming a source file is actually part of the build. Git history is the record — don't keep
  commented-out code as "history", and don't add more of it.
- **Simple factoring.** Small, focused types and methods; prefer the simplest design that works.
  Watch the size of the types that everything routes through — they are where complexity
  accumulates first.
- **Strict typing.** Respect each project's existing nullability/typing settings; don't add
  null-forgiving uses or disable directives without a comment proving the check is unnecessary.

## Agent coordination (AC ↔ OC)

This repo may be worked on by two agents — **AC** (Claude Code) and **OC** (OpenCode) — possibly
at the same time. Avoid stepping on each other.

- **Before non-trivial work:** check recent git log and both `changelog.d/AC/` and
  `changelog.d/OC/` for in-flight fragments, and read this file's project-state section; keep
  that section current as part of finishing a task.
- **File territories.** Prefer work that touches new files or files the other agent isn't
  reaching for; coordinate in a changelog fragment before both touching the same area.
- **Never commit the other agent's work.** Before staging, diff what actually changed
  (`git status`/`git diff`); stage only the files/hunks you authored. Never `git add -A`/blind-
  stage the whole tree.
- **Attribution.** Commit subjects are prefixed `[AC]`/`[OC]`; changelog fragments live in
  `changelog.d/AC/`/`changelog.d/OC/`. Never edit the other agent's fragment folder. No
  `Co-Authored-By:` (or similar AI-assistant) trailers — the prefix is the attribution.

## Changelog & commit workflow

1. Add a fragment to your own `changelog.d/<AGENT>/` folder (naming and entry format:
   `changelog.d/README.md`). Never edit `CHANGELOG.md` or the other agent's folder directly.
2. Commit the code change together with its fragment in the same commit, subject prefixed with
   your agent tag.
3. **Commit once the change is tested and working** — build green (and, where that's the only
   real way to verify, a manual run check). Never commit speculative or known-broken work without
   saying so explicitly.
4. **Consolidate immediately, per finished task:** fold your fragment into `CHANGELOG.md` under
   `[Unreleased]` (one dated entry, prefixed with your agent tag, carrying agent/datetime/affected
   files) and delete the fragment.

## Audits & production requirements

Project audits are recorded in `audit/` at the repo root:

- `audit/AUDIT.MD` — the audit log. Every audit appends one **revision entry**: date, agent,
  scope, the quality score (model defined at the top of that file), and the **delta** vs the
  previous revision (score change + requirement IDs closed/opened). Never rewrite past revision
  entries.
- `audit/REQUIREMENTS.MD` — the stable catalog of production requirements, one per
  never-renumbered ID, classified by criticality (`Blocker` → `Critical` → `Major` → `Minor` →
  `Enhancement`). It is also the repo's **single task checklist**: every requirement is a checkbox
  item (`[ ]` pending, `[x]` completed, `Status: In progress` for in-process). Audits reference
  these IDs; work that closes a requirement ticks its checkbox and updates its `Status` in the
  same commit as the code. Don't create parallel to-do/checklist files — new tasks become new IDs
  here.

When either agent runs an audit:

1. Append a revision entry to `audit/AUDIT.MD` per its template — never edit earlier revisions.
2. New findings become new requirements in `REQUIREMENTS.MD` with the next free ID at their
   criticality. Never renumber or recycle IDs; obsolete requirements keep their ID with a note.
3. Compute the score with `AUDIT.MD`'s model and record the delta against the previous revision.
4. Detailed per-finding reports, when wanted, live as dated files in the same folder; the revision
   entry links to them.
