# PLAN.md — the plan comes first

**Rule: no implementation work starts on any app until this plan exists and is approved.** Not a
skeleton, not "we'll figure it out as we go" — the sections below filled in with real decisions.
The plan is the contract the implementation is audited against; changes to it are made here
first, then in code. (For multi-phase projects, this file can live at `docs/plan/PLAN.md` and
point to per-phase documents — but the initial plan is always written before the first commit of
application code.)

## Plan template — fill every section

### 1. Objective

One paragraph: what this app does, for whom, and what "done for production" means. If you cannot
write this in five sentences, the scope is not understood yet.

### 2. Scope

- **In scope:** capabilities the first usable version must have.
- **Out of scope:** explicitly listed things this version will NOT do (this list is what keeps
  the project from drifting; put nice-to-haves in the requirements catalog as Enhancement
  instead of silently absorbing them).

### 3. Architecture overview

Components, their responsibilities, how they communicate (process topology, protocols, data
stores), and the layering rule each layer must respect (what may call what, and what lives where).
If a component boundary is undecided, write the options here and mark it as an open decision —
don't leave it implicit.

### 4. Data & configuration

- Data stores used and what each holds; schema ownership (which component owns which table).
- Configuration sources (files, env, DB) and their hierarchy/priority.
- Secrets: where they live at runtime, and the guarantee that none are committed.

### 5. Requirements mapping

Initial entries (or the plan to seed them) in `audit/REQUIREMENTS.MD` — the catalog is the
project's single task checklist. The plan does not duplicate the catalog; it references IDs and
adds what's missing for this app's specific domain.

### 6. Phases / milestones

Ordered, each with a verifiable outcome ("service starts and answers a health ping", not
"backend work"). Small enough that each phase lands as a small set of commits.

### 7. Risks & open decisions

Known unknowns, external dependencies, and decisions needed from the owner (each with a
recommended option). Anything here that blocks a phase must be resolved before that phase starts.

### 8. Verification strategy

How correctness will be checked: what gets automated tests, what gets manual verification, and
the exact commands to build/run everything (written down here first — these become the
`Commands` section of `AGENTS.md`).
