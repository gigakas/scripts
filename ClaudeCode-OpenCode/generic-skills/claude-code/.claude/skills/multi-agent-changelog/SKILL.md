---
name: multi-agent-changelog
description: Maintain a multi-agent changelog. Report changes incrementally to a per-agent file in changelog.d/ while working, then consolidate completed changes into the root changelog.md on task completion. Use for any task that modifies files. Language-agnostic.
---

# Multi-Agent Changelog

A convention so that several agents (opencode, Claude Code, or humans) working on the same project leave a single, consistent record of what changed and why.

Two artifacts:

1. **`changelog.d/`** — temporary, per-agent files written *incrementally while working*.
2. **`changelog.md`** (project root) — the consolidated, permanent log written *when the task is finished*.

## When to use

- Any task that creates, edits, or deletes files.
- Whenever you are one of several agents (or a human + agents) sharing a repository and need a traceable history.

## Default language

**English**, unless the user explicitly asks otherwise. Titles and descriptions go in English even if the conversation is in another language.

## Detect which agent you are

Every entry is stamped with the agent that did the work:

| Tool | ID |
|------|----|
| opencode | `OC` |
| Claude Code | `AC` |

The same rules apply to both tools — you must detect which one you are running under and use the matching ID. In order of precedence:

1. **Runtime identity (authoritative)** — your own system prompt / tool name: opencode identifies itself as "opencode", Claude Code as "Claude Code".
2. **Environment variables (confirmation)**:
   - `OPENCODE` set (e.g. `OPENCODE=1`) → `OC`
   - `CLAUDE_PROJECT_DIR` or `CLAUDE_CODE_ENTRYPOINT` set → `AC`
3. If the signals conflict or are missing, trust the runtime identity from step 1.

Detection snippet:

```bash
if [ -n "${CLAUDE_PROJECT_DIR:-}${CLAUDE_CODE_ENTRYPOINT:-}" ]; then
  echo "AC"   # Claude Code
elif [ -n "${OPENCODE:-}" ]; then
  echo "OC"   # opencode
else
  echo "unknown"
fi
```

## File locations

```
<project-root>/changelog.md                  # permanent, consolidated log
<project-root>/changelog.d/<datetime>-<AGENT>.md   # temporary, per-agent, per-task
```

## Temporary file name

`<datetime>-<AGENT>.md` where `<datetime>` is `YYYY-MM-DD_HHMMSS` (24h, zero-padded).

Examples:

```
changelog.d/2026-09-23_141530-OC.md
changelog.d/2026-09-23_091007-AC.md
```

## Procedure

### 0) At task start — create your temp file

Create `changelog.d/YYYY-MM-DD_HHMMSS-<AGENT>.md` and write the header + description:

```
YYYY-MM-DD -- Descriptive Title -- AGENT
Description of the task
```

- **Descriptive Title**: short imperative summary of the whole task (e.g., `Add design-patterns skill`).
- **Description of the task**: one or two lines explaining the intent and scope.
- You may refine both later, before consolidation.

### 1) While working — report changes incrementally

Each time you create or modify a file, append a line to your temp file:

```
YYYY-MM-DD HH:MM - <type> -- /relative/path/file-name
```

- `<type>`: the kind of job — `edit`, `write`, `create`, `delete`, `rename`, `move`.
- `/relative/path/file-name`: path relative to the project root (leading slash, forward slashes).
- Append immediately after each change so the record is never stale.

### 2) At task completion — consolidate into changelog.md

1. Finalize the title and description in your temp file.
2. Append the entry to `changelog.md` (newest entry at the top).
3. **Delete your temp file** from `changelog.d/` (it is a buffer, not a permanent record).

### 3) Clean up

- If `changelog.d/` becomes empty, you may leave the empty directory or remove it.
- Do not leave stale temp files behind after consolidating.

## Log entry structure

Each consolidated entry in `changelog.md` looks like this:

```
YYYY-MM-DD -- Descriptive Title -- AGENT
Description of the task
YYYY-MM-DD HH:MM - edit -- /relative/path/file-name
YYYY-MM-DD HH:MM - write -- /relative/path/file-name
```

Multiple change lines are allowed under a single header. Separate entries with a blank line.

### Full example

`changelog.d/2026-09-23_141530-OC.md` (temporary):

```
2026-09-23 -- Add design-patterns skill -- OC
Add a language-agnostic design-patterns skill with creational, structural and behavioral references.
2026-09-23 14:15 - write -- frappe-generic-skills/opencode/.opencode/skill/design-patterns/SKILL.md
2026-09-23 14:20 - write -- frappe-generic-skills/opencode/.opencode/skill/design-patterns/references/creational-patterns.md
2026-09-23 14:25 - write -- frappe-generic-skills/opencode/.opencode/skill/design-patterns/references/structural-patterns.md
2026-09-23 14:30 - write -- frappe-generic-skills/opencode/.opencode/skill/design-patterns/references/behavioral-patterns.md
```

After consolidation, that block is prepended to `changelog.md` and the temp file is deleted.

## Guardrails

- **One temp file per agent per task** — don't create a new file for every edit.
- **Append change lines as you go** — the temp file must reflect reality at all times.
- **Consolidate before finishing** — never leave work only in `changelog.d/`.
- **Delete the temp file after consolidating** — avoid duplicate/conflicting records.
- **Use relative paths from the project root**, not absolute or machine-specific paths.
- **Write in English** by default.

## Common Mistakes

| Mistake | Why It Fails | Fix |
|---------|--------------|-----|
| Skipping the temp file and writing directly to changelog.md | Concurrent agents overwrite each other | Write incrementally to changelog.d/, consolidate at the end |
| Forgetting to delete the temp file | Stale/duplicate entries | Delete the temp file after consolidating |
| Absolute paths | Not portable across machines/agents | Use paths relative to the project root |
| Wrong agent ID | History can't be attributed | Use `OC`/`AC` for the tool you run under |
| Non-English entries by default | Inconsistent history across agents | Default to English unless told otherwise |
| Vague title | Log is hard to scan | Use a short imperative title describing the task |
