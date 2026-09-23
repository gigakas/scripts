# File Responsibility & Size Rules (per language)

Heuristics to detect when a file or function has outgrown its responsibility (Large Class / Long Method) and to prevent files from growing past an allowed size. Source of the underlying smells: [refactoring.guru — Large Class / Long Method](https://refactoring.guru/).

These are **review triggers, not quality targets**. They flag files worth inspecting; the real criterion is cohesion and single responsibility, not line count.

## Two-tier model

| Tier | Meaning | Action |
|------|---------|--------|
| **Review threshold** (soft) | Exceeded → the file/function may have too many responsibilities | Inspect and split if warranted |
| **Hard limit** (hard) | Must not be exceeded | Split the file, or get explicit developer authorization |

## How to count

- **File LOC**: total physical lines in the file.
- **Function LOC**: lines inside the function, excluding blank lines and comment-only lines.
- **Cyclomatic complexity**: number of independent paths (1 base + 1 per `if`/`for`/`while`/`case`/`&&`/`||`/`catch`).

## Rules by language

| Language | File LOC (review) | File LOC (hard) | Function LOC (review) | Complexity (review) |
|----------|------------------:|----------------:|----------------------:|--------------------:|
| Python | 300 | 500 | 50 | 10 |
| JavaScript | 300 | 500 | 50 | 10 |
| TypeScript | 300 | 500 | 50 | 10 |
| Ruby | 300 | 500 | 50 | 10 |
| Java | 400 | 700 | 60 | 10 |
| C# | 400 | 700 | 60 | 10 |
| PHP | 400 | 700 | 60 | 10 |
| Kotlin | 400 | 700 | 60 | 10 |
| Swift | 400 | 700 | 60 | 10 |
| Rust | 400 | 700 | 60 | 10 |
| Go | 500 | 800 | 80 | 10 |
| C / C++ | 500 | 800 | 80 | 15 |

Verbose languages (Java, C#, Go, C/C++) get higher thresholds because idiomatic code carries more boilerplate; concise languages (Python, Ruby, JS) get lower ones.

## Review triggers

Review a file's responsibility when **any** of these is true:

- File LOC exceeds the review threshold.
- Any single function LOC exceeds the review threshold.
- Cyclomatic complexity of a function exceeds the review threshold.
- The file has many unrelated methods, fields, or imports (a "god file" even under the LOC limit).
- The file is modified for many unrelated reasons (Divergent Change).

## How to attack the problem

| Symptom | Refactoring |
|---------|-------------|
| File too large / many responsibilities | Extract Class, Move Method, Move Field, Extract Module |
| Function too long | Extract Method, Replace Temp with Query, Decompose Conditional |
| High complexity | Extract Method, Replace Conditional with Polymorphism, Replace Nested Conditional with Guard Clauses |
| Switch/if on type | Replace Conditional with Polymorphism |
| Duplicated logic across files | Pull Up Method / Extract Method into a shared module |

See the `refactoring` skill's `techniques.md` for the full catalogue.

## Preventing growth (hard limit)

- **Do not add code that pushes a file past its hard limit.**
- When approaching the limit, split the file or extract a class/module instead of appending.
- If you *must* exceed it, treat it as an **exception**:

### Exception process (developer-authorized)

1. Only the developer can authorize exceeding a hard limit.
2. Document the exception: file, reason, who authorized, date — as a comment at the top of the file and in the changelog/audit (see `code-audit` and `multi-agent-changelog`).
3. Prefer splitting over the exception; request authorization only when splitting would clearly hurt (e.g., a single generated mapping, a tightly-coupled parser table).

## Exempt files

Thresholds do **not** apply to generated or data files where line count is mechanical, not design:

- Generated code (protobuf/gRPC, OpenAPI clients, ORM models, migrations)
- Machine-generated asset/manifest files (lockfiles, minified bundles, `.csv`/`.json` data)
- Third-party vendored code (should not be hand-edited anyway)

These still count toward repo hygiene, but their size is not a responsibility signal.

## Guardrails

- **Thresholds are triggers, not goals** — never split a cohesive 350-line file just to get under 300.
- **Split by responsibility**, not by arbitrary line count — the result must have a clearer reason-to-change, not just smaller numbers.
- **Keep the metric consistent** across the codebase and across audit passes (see `code-audit`).
- **Verbosity is a language property** — don't hold a Go file to a Python threshold.
