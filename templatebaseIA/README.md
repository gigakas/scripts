# templatebaseIA — reusable project base

A generalized copy of the methodology this repo established, extracted so future projects can
start with it on day one. It bundles the four pillars that made this project manageable by two AI
agents (Claude Code = **AC**, OpenCode = **OC**) working the same tree:

1. **Plan first** — no implementation starts until a plan exists and is approved (`PLAN.md`).
2. **Single requirements checklist** — every task ever collected lives in one file
   (`audit/REQUIREMENTS.MD`) as stable-ID, criticality-classified checkbox items. No parallel
   to-do lists anywhere.
3. **Audit system** — periodic audits append one revision entry to `audit/AUDIT.MD` with a
   criticality-weighted quality score and the delta vs the previous revision. Never rewrite
   past revisions.
4. **Dual-agent workflow** — attribution ([AC]/[OC]), file territories, changelog fragments
   (`changelog.d/{AC,OC}/`) and immediate consolidation into `CHANGELOG.md`.

## Folder map

```
templatebaseIA/
  README.md                 <- this file: what it is + how to instantiate
  PLAN.md                   <- the plan-first rule + the plan template every new app starts from
  AGENTS.md                 <- generic agent rules (copy to the new repo root, mirror as CLAUDE.md)
  audit/
    AUDIT.MD                <- quality-score model + revision-log template (empty log)
    REQUIREMENTS.MD         <- single-checklist convention + 14 starter production requirements
  changelog.d/
    README.md               <- fragment workflow: naming, entry format, consolidation
  .claude/
    skills/project-review/SKILL.md
    skills/project-build-and-run/SKILL.md
  .opencode/
    command/project-review.md
    command/project-build-and-run.md
    .gitignore              <- keeps local opencode plugin tooling (node_modules etc.) out of git
```

The `.claude`/`.opencode` folders carry the two agent commands/skills, mirrored: `.claude` uses
`skills/<name>/SKILL.md` with `name`+`description` frontmatter; `.opencode` uses
`command/<name>.md` with `description` frontmatter plus `$ARGUMENTS` at the end. Both ship with
placeholders — fill them from `PLAN.md`'s verification strategy and layering decisions once made,
then rename `project-*` to `<project>-*`.

## Instantiating in a new project

1. **Plan before code.** Copy `PLAN.md` to the new repo root and fill it (goal, scope,
   architecture, phases, risks). No implementation work starts until it is approved — this is a
   hard rule, not a suggestion.
2. **Copy the agent setup.** Copy `AGENTS.md` to the repo root; mirror it as `CLAUDE.md` (the two
   must stay in sync whenever either changes). Fill the project-specific placeholders: what the
   project is, stack/language, build & run commands, architecture summary. Also copy `.claude/`
   and `.opencode/` into the new repo root, fill their placeholder rules/commands, and rename the
   `project-*` skills/commands to `<project>-*`.
3. **Copy the audit system.** Copy `audit/` as-is: `AUDIT.MD`'s score model works as-is; adjust
   the weights only if the project's criticality distribution demands it (keep Blocker heaviest).
   `REQUIREMENTS.MD` ships with 14 starter production requirements (tests, CI, secrets, data
   integrity, deployment, migrations, logging, health, config validation, API hardening,
   observability, releases, docs, injection-safe data access) — delete/adapt what doesn't apply
   to the new app, keeping their IDs, and let the first audit append project-specific ones after.
4. **Copy the changelog workflow.** Copy `changelog.d/README.md` and create the empty
   `changelog.d/AC/` and `changelog.d/OC/` folders; create an empty `CHANGELOG.md` with an
   `[Unreleased]` heading.
5. **First audit closes the loop.** The first audit appends Revision 1 to `audit/AUDIT.MD`
   (baseline score from the catalog's statuses) and seeds any project-specific findings as new
   requirement IDs.

Everything in here is deliberately project-agnostic; the only things to customize are the
placeholders in `AGENTS.md` and the applicability of starter requirements.
