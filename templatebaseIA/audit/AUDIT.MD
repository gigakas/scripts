# AUDIT.MD — audit revision log

Chronological log of project audits. Each audit gets one revision entry here; the requirements an
audit produces or closes live in [`REQUIREMENTS.MD`](REQUIREMENTS.MD) (same folder) under stable
IDs. Never rewrite past revision entries — a correction is a new revision entry.

## Quality score model

The score (0–100) measures how much of the production-requirements catalog is closed, weighted by
criticality:

| Criticality | Weight per requirement |
|-------------|------------------------|
| Blocker | 20 |
| Critical | 10 |
| Major | 5 |
| Minor | 2 |
| Enhancement | 1 |

```
score = round(100 × Σ(weight of Done) / Σ(weight of all requirements))
```

- `In progress` requirements count as half their weight; `Open` count zero.
- **⛔ flag:** while any Blocker requirement is `Open`/`In progress`, the score is reported with
  the ⛔ marker — the product is not production-ready regardless of the number.
- Every revision entry records the score, the **delta** vs the previous revision (score change and
  which requirement IDs were closed/opened), so progress between audits is explicit.

## Revision log template

```
### Revision N — YYYY-MM-DD
- Auditor: [OC]/[AC]/human · Scope: <projects/areas audited> · <link to detailed report, if any>
- Score: <n>/100 (⛔ if open Blockers) · Delta: <±points vs previous, IDs closed/opened>
- Summary: <one short paragraph — verdict and the audit's most important conclusions>
```

No revisions yet. Revision 1 comes from the first audit after instantiation: it records the
baseline score computed from `REQUIREMENTS.MD`'s statuses and links the detailed report, if one
is written.
