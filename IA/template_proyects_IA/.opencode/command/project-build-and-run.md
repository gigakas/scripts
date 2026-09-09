---
description: Build and/or run this solution, reporting compile errors grouped by project/file.
---

# Build & Run

Run these from the repo root (where `CLAUDE.md`/`AGENTS.md` live).

> **Instantiate:** replace the commands below with this project's real ones — they were defined in
> `PLAN.md`'s verification strategy and live in the agent rules' "Commands" section. Keep this
> command file and the mirrored `.claude/skills/` file in sync with that section.

## Build

```powershell
# <the full-solution build command from the agent rules' "Commands" section>
```

<Notes on any build quirks: components needing a special toolchain, codegen steps, or known
environmental failure modes (file locks, marks-of-the-web) — and the exact remedy for each.>

## Run

<Which components are meant to run standalone from the terminal, their exact run commands, any
prerequisites (config files, DBs, seed data) and where they must be present, and what normal
output looks like so a quiet-but-working process isn't mistaken for a hang.>

## Reporting results

- On success, state which projects built (or ran) — don't dump the full build output.
- On failure, extract just the error lines, group them by project/file, and show file:line for
  each. Don't paste the raw verbose build log.
- If components build independently, report a failing component's status separately from the rest —
  one component failing is not a signal to re-check everything else.

$ARGUMENTS
