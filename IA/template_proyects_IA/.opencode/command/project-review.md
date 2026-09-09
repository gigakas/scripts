---
description: Review changed code in this repo against this project's own conventions — plan-first, dead-code hygiene, layering, strict typing, changelog/commit workflow, single requirements checklist.
---

# Project rules review

Check the current diff (or the files the user points at) against the rules below. Report
violations with file:line, like `/code-review` findings — don't just narrate compliance.

> **Instantiate:** replace this file's project-specific placeholder rules (marked <…>) with the
> real ones once the project's architecture is set in `PLAN.md`, and rename the file from
> `project-*` to `<project>-*` in both `.opencode/command/` and `.claude/skills/` (keep them
> mirrored).

## Project rules

1. **Plan-first.** Flag implementation work that contradicts or bypasses `PLAN.md` — architecture
   and scope decisions change the plan first (approved), then the code.
2. **Dead-code hygiene.** Flag any new code added into a draft/duplicate file instead of the
   canonical one — files/folders named `Copy`, `OLD`, version-number prefixes, `Test`, `BackUp`
   are drafts in this workflow, not alternates to build on. Before treating any source file as
   "the real one," check the owning build file's exclusions. Flag large new blocks of
   commented-out code left "for reference" — git history is the record.
3. **Layering.** <Fill per project: which layer may call which, where data access lives, what the
   UI/entry layer may never contain.> Flag business/data logic appearing in the wrong layer.
4. **Strict typing, per project.** Flag new null-forgiving (`!`) uses or disable directives in
   nullability-enabled projects that aren't accompanied by a comment explaining why the null-check
   is actually unnecessary. <Fill per project: which projects/components have which typing
   settings.>
5. **Single requirements checklist.** Flag parallel to-do/checklist files being created — new work
   items become new requirement IDs in `audit/REQUIREMENTS.MD` (never-renumbered IDs,
   criticality-classified, tri-state checkboxes). Flag work closing a requirement that doesn't
   tick its checkbox / update its `Status` in the same commit.
6. **Changelog + signed commit.** Every approved change should have a matching fragment in
   `changelog.d/<AGENT>/` and a commit whose subject is prefixed with the agent tag (see root
   agent rules). Flag a change that's about to be committed without either, and any blind
   `git add -A`-style staging (it can fold in the other agent's work).
7. **English.** New code, comments, commit messages, and docs are in English (see the agent
   rules' "Language" section). Not retroactive — don't flag grandfathered content unless the
   change is rewriting it anyway.

## Notes

- For correctness bugs, simplification, and general code quality beyond these project-specific
  rules, also run the generic `/code-review` skill.
- Update this file and the mirrored `.claude/skills/project-review/SKILL.md` together whenever the
  rules change.

$ARGUMENTS
