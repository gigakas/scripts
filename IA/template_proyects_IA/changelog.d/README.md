# changelog.d — per-agent change fragments

`CHANGELOG.md` is the human-readable log. This folder is the **write target for agents** — it
exists so Claude Code (AC) and OpenCode (OC) can log changes at the same time without both editing
`CHANGELOG.md` and hitting merge collisions.

## Layout

- `AC/` — fragments written by Claude Code.
- `OC/` — fragments written by OpenCode.

Each agent only ever writes inside its own subfolder. Never edit the other agent's folder or
`CHANGELOG.md` directly from an automated change.

## Workflow (for agents)

After a code change is approved by the user, **before** committing:

1. Add one fragment file to your own subfolder (`AC/` or `OC/`), named:
   `YYYYMMDDTHHMMSSZ-short-slug.md` (UTC timestamp + short kebab-case slug), e.g.
   `20260101T120000Z-fix-parser-null-handling.md`.
2. Fragment content: a short summary line of what changed and why, plus bullets for details if
   useful. No frontmatter needed.
3. Commit the code change together with its fragment file in the same commit (subject prefixed
   with your agent tag — see the agent rules file).

## Consolidation (immediate, per finished task)

Fold your fragment into `CHANGELOG.md` **as soon as the task is done** (build green) — do not let
fragments pile up for a later bulk edit:

1. Add a dated entry under `[Unreleased]` in `CHANGELOG.md`, prefixed with your agent tag (`[AC]`
   / `[OC]`), merging into today's date heading if one already exists (the heading is the entry's
   actual calendar date — see the entry format below, not whichever date happened to be at the
   top of the file).
2. Delete your fragment file from your own subfolder.
3. Only touch your own agent's entries and fragments — never `[AC]`↔`[OC]` the other way. This is
   what stops the two agents from colliding on a single `CHANGELOG.md` merge at the end of a big
   batch.

Consolidation is a required part of finishing a task, not an optional cleanup.

## Entry format (required fields)

Every `CHANGELOG.md` entry is a three-part block: the agent tag on its own line, a
datetime+explanation line, then one indented line per affected file:

```
- **[AC]**
  **<ISO-8601 datetime with offset>:** <explanation>
  - **<Edit type>:** `path/one.ext`
  - **<Edit type>:** `path/two.ext`
```

- **Agent** — `[AC]`/`[OC]` on its own bullet line.
- **Datetime** — the actual moment of the change, in ISO 8601 with a UTC offset (e.g.
  `2026-01-01T12:00:00+00:00`). Use "now" at consolidation time — since consolidation happens
  immediately after the change is tested and working, that's effectively the commit's own
  timestamp.
- **Explanation** — same line as the datetime, after the colon: what changed and why, with enough
  detail that another agent (or a human) can act on it without re-reading the diff.
- **Edit type / file** — one indented sub-bullet per file the change actually touches,
  `git diff --name-status`'s own classification: `Added`, `Modified`, `Deleted`, or `Renamed`.
  Exclude the changelog fragment file itself (that's bookkeeping for this same entry, not a file
  "affected" by the change) — everything else counts, including doc/config files. An entry with no
  files outside `changelog.d/` gets a single `- **(none):** no files outside changelog.d/` line.
