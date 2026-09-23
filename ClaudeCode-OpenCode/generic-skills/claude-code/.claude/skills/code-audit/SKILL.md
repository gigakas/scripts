---
name: code-audit
description: Audit code quality and track improvements over time. Use to review a codebase, measure quality deltas across audit passes, and maintain a backlog of suggested improvements with importance levels. Language-agnostic.
---

# Code Audit

Systematically review code, measure quality **deltas across passes**, and track suggested improvements with an importance level.

## When to use

- Auditing the quality of a module, app, or repository
- Measuring the impact of refactoring across multiple passes
- Maintaining a backlog of improvement suggestions
- Reviewing code before or after a change (see `refactoring`, `solid-principles`)

## Files (project root)

| File | Purpose |
|------|---------|
| `auditory.md` | Audit history — one entry per pass, with measured deltas |
| `track_auditory.md` | Suggested improvements, each tagged with an importance level |

## Default language

**English**, unless the user asks otherwise.

## Agent identification (multi-agent)

The same rules apply to opencode and Claude Code — detect which agent you are and stamp each pass accordingly:

| Tool | ID |
|------|----|
| opencode | `OC` |
| Claude Code | `AC` |

Precedence: (1) runtime identity — opencode calls itself "opencode", Claude Code calls itself "Claude Code"; (2) env vars — `OPENCODE` set → `OC`, `CLAUDE_PROJECT_DIR`/`CLAUDE_CODE_ENTRYPOINT` set → `AC`; (3) on conflict, trust runtime identity.

## Measured metrics (deltas per pass)

For every pass, record the metrics before (previous) and after (current), and the **delta** between them:

| Metric | Meaning |
|--------|---------|
| Lines of code | Total LOC in scope |
| Cyclomatic complexity | Average (and max) complexity |
| Code smells | Count of smells found |
| Duplication | Percentage of duplicated code |
| Test coverage | Percentage covered by tests |

Use whatever subset applies to the language/project; you may add metrics (e.g., number of TODO/FIXME, lint errors) but keep them consistent across passes so deltas are comparable.

Per-language review thresholds for when a file/function's size or complexity signals a responsibility problem are in the `refactoring` skill: `references/file-responsibility-rules.md`.

## Importance scale

Used in `track_auditory.md`. Highest first:

| Level | Meaning |
|-------|---------|
| **Critical** | Bug risk, security, or data loss — must fix |
| **High** | Significant maintainability/performance issue — fix soon |
| **Medium** | Worth doing, non-urgent |
| **Low** | Cosmetic or nice-to-have |

## Procedure

### 0) Define scope

State clearly what is being audited (path/module), and pick the metric subset once — reuse it for every pass.

### 1) First pass — establish the baseline

- Measure the current metrics.
- Append a **Pass 1** entry to `auditory.md` (no delta yet).
- Add every finding as an improvement in `track_auditory.md`, tagged with an importance level.

### 2) Record findings

For each issue, add a row to `track_auditory.md` under **Open**: a short ID, the improvement, its importance, the area (file), and the pass where it was detected.

### 3) Subsequent passes — measure deltas

- Re-measure the same metrics.
- Append a new pass entry to `auditory.md` showing **Previous → Current → Delta**.
- Move resolved improvements in `track_auditory.md` from **Open** to **Resolved** (record the pass).

### 4) Keep both files in sync

Every improvement in `track_auditory.md` should map to an observed change reflected in `auditory.md` deltas. If a pass changed nothing, say so explicitly.

## File structures

### `auditory.md`

```
# Audit History

## Pass 1 — 2026-09-23 — OC
**Scope**: frappe-generic-skills/opencode/.opencode/skill/refactoring
**Objective**: baseline audit before refactoring
- Lines of code: 1240
- Avg cyclomatic complexity: 8.4
- Code smells: 23
- Duplication: 6%
- Test coverage: 62%

## Pass 2 — 2026-09-24 — OC
**Scope**: frappe-generic-skills/opencode/.opencode/skill/refactoring
**Objective**: after first refactoring round
| Metric | Previous | Current | Delta |
|--------|----------|---------|-------|
| Lines of code | 1240 | 1150 | -90 |
| Avg cyclomatic complexity | 8.4 | 7.1 | -1.3 |
| Code smells | 23 | 18 | -5 |
| Duplication | 6% | 4% | -2% |
| Test coverage | 62% | 70% | +8% |
```

### `track_auditory.md`

```
# Improvement Tracking

## Open

| ID | Improvement | Importance | Area | Detected |
|----|-------------|------------|------|----------|
| A-01 | Extract duplicated validation into a shared function | High | api/validators.py | Pass 1 |
| A-02 | Replace switch-on-type with polymorphism | Medium | core/handlers.py | Pass 1 |

## Resolved

| ID | Improvement | Importance | Resolved |
|----|-------------|------------|----------|
| A-03 | Remove dead code in legacy module | Critical | Pass 2 |
```

## Guardrails

- **Fix one metric set and stick to it** — changing metrics between passes makes deltas meaningless.
- **Baseline first** — pass 1 establishes the reference; deltas start at pass 2.
- **Tag importance honestly** — reserve `Critical` for real bug/security risk.
- **Keep improvements actionable** — an improvement must be specific enough to act on.
- **Attribute every pass to an agent** (`OC`/`AC`) in multi-agent work.
- **Write in English** by default.

## Common Mistakes

| Mistake | Why It Fails | Fix |
|---------|--------------|-----|
| Changing metrics between passes | Deltas are not comparable | Fix the metric set in pass 1 |
| No baseline | Can't measure improvement | Always record pass 1 as reference |
| Improvements without importance | Can't prioritize | Tag every item Critical/High/Medium/Low |
| Vague improvements | Backlog is unusable | Make each item specific and actionable |
| Forgetting to move items to Resolved | Backlog looks stale | Update status every pass |
| Over-measuring trivial metrics | Noise, not signal | Measure what matters for the project |
