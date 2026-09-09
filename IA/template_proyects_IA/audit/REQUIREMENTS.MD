# Production requirements catalog

Single source of truth for what this product still needs before (and after) it can be called
production-ready, and the repo's **single, unique checklist for every task collected over time** —
don't create parallel to-do/checklist files elsewhere; a new work item is a new requirement ID
here. Every requirement has a **stable ID that never changes**: audits (`AUDIT.MD`, same folder)
reference these IDs when recording deltas, and the quality score is computed from the statuses
here.

## How this file works

- Every requirement doubles as a checklist item (GitHub task-list syntax). Tri-state convention:
  `- [ ]` = pending (`Status: Open`), `- [ ]` with `Status: In progress` = in process,
  `- [x]` = completed (`Status: Done`). Tick the checkbox and update the **Status** in the same
  commit as the code change (plus the usual `changelog.d/` fragment).
- When an audit produces a new requirement, add it here with the next free ID in its criticality
  level. **Never renumber or recycle IDs** — a requirement that becomes irrelevant keeps its ID
  with a strikethrough note.
- One requirement per line of work; keep entries short enough to scan, detailed enough to act on
  without re-reading the audit that spawned them.

## Criticality levels

Levels run from critical to non-critical (deliberately *not* "L1/L2"-style tier labels):

| Level | Meaning |
|-------|---------|
| **Blocker** | Data-loss/corruption, security, or crash risk; must be fixed before production |
| **Critical** | Required for reliable production operation; only painful workarounds exist |
| **Major** | Maintainability/observability debt that should be scheduled, not ignored |
| **Minor** | Robustness/quality improvement, low production risk |
| **Enhancement** | Polish; no production risk |

IDs use the level initial: `R-B-xx` (Blocker), `R-C-xx` (Critical), `R-M-xx` (Major),
`R-N-xx` (Mi**n**or), `R-E-xx` (Enhancement).

The catalog below ships pre-seeded with 14 **starter** requirements that apply to essentially any
app (extracted from a real project's first audit). At instantiation, delete/adapt the ones that
don't apply — keeping their IDs — and let the first audit append project-specific ones with the
next free IDs at each level.

## Blocker

- [ ] **R-B-01** — Injection-safe data access. No string-concatenated SQL from user-controlled
  input anywhere; parameterized queries and validated identifiers only. Status: Open · Origin: base template
- [ ] **R-B-02** — Secrets protection. No hardcoded credentials; secrets are protected at rest
  (DPAPI/vault/secret manager) and verifiably absent from the repo and seed data. Status: Open · Origin: base template
- [ ] **R-B-03** — Data integrity under failure. A failed operation never leaves partial or
  corrupted data: transactional semantics, rollback on error, and safe re-runs (idempotency)
  where operations repeat. Status: Open · Origin: base template
- [ ] **R-B-04** — Unattended error containment. Automated/background work that fails must fail
  its own unit with a logged error — never silently (empty catch), and never taking down the
  whole service loop. Status: Open · Origin: base template

## Critical

- [ ] **R-C-01** — Automated tests for the core domain logic. A test project exists from the
  start; the pipeline spine (inputs → processing → outputs) is covered. Status: Open · Origin: base template
- [ ] **R-C-02** — CI pipeline. Full-solution build (and tests, once R-C-01 exists) on every
  push, so "it builds clean" stops depending on one machine. Status: Open · Origin: base template
- [ ] **R-C-03** — Production deployment story. Installation, config placement, and provisioning
  that don't depend on dev-only scripts. Status: Open · Origin: base template
- [ ] **R-C-04** — Data-store upgrade path. Schema versioning/migration between releases;
  existing deployments upgrade automatically or with a documented step. Status: Open · Origin: base template
- [ ] **R-C-05** — Operational logging policy. Rotation/retention for file logs and an
  unhandled-exception/crash policy (what gets logged, where, what restarts). Status: Open · Origin: base template
- [ ] **R-C-06** — Service health endpoint. A heartbeat/health check consumable by external
  monitoring. Status: Open · Origin: base template

## Major

- [ ] **R-M-01** — Startup configuration validation. Fail fast with clear messages on malformed
  config at startup, instead of failing mid-operation later. Status: Open · Origin: base template
- [ ] **R-M-02** — API/RPC surface hardening. Documented/enforced binding scope (e.g.
  localhost-only unless proven otherwise), an explicit allow-list of actions, and request
  timeouts. Status: Open · Origin: base template
- [ ] **R-M-03** — Operational observability. Per-unit success/failure counts and durations,
  queryable from the product's own UI/console. Status: Open · Origin: base template

## Minor

*(none yet — project-specific findings land here from the first audit)*

## Enhancement

- [ ] **R-E-01** — Release & versioning scheme. Version numbers, tags, installer/pipeline —
  define when the first thing actually ships, not speculatively before.
  Status: Open · Origin: base template
- [ ] **R-E-02** — Documentation set. Operator guide (configuration, schedules, operations) and
  an architecture/onboarding doc for new developers. Status: Open · Origin: base template
