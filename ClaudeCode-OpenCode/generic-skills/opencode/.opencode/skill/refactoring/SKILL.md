---
name: refactoring
description: Systematically improve existing code without changing behavior. Use when cleaning up code, removing code smells, simplifying methods/conditionals/classes, or restructuring code to be easier to read and maintain. Source: https://refactoring.guru
---

# Refactoring

Refactoring is a systematic process of improving code **without creating new functionality**. It transforms messy code into clean, simple design. Source: [refactoring.guru](https://refactoring.guru).

## When to use

- Cleaning up code you or someone else just wrote (before/after adding a feature)
- Removing a code smell (see [references/code-smells.md](references/code-smells.md))
- Reducing technical debt during a task that touches the same code
- Preparing code for an upcoming change (make the change easy first)
- Reviewing code and suggesting structural improvements

## Core principles

1. **Preserve behavior.** Refactoring must not change what the code does. Tests are your safety net.
2. **Small steps.** Apply one refactoring at a time and run tests after each step.
3. **No new features.** Keep refactoring and feature work in separate commits/changes.
4. **Motivate each change.** Every technique has trade-offs; don't apply them mechanically.

## Procedure

### 0) Establish a safety net

```bash
# Before touching anything, confirm the tests pass
pytest .          # Python / Frappe
# or
bench --site <site> run-tests --app <app>
```

If no test covers the area, add one that locks in current behavior *before* refactoring.

### 1) Identify the smell

Look for the code smells catalogued in [references/code-smells.md](references/code-smells.md). The smell determines the treatment.

### 2) Choose the smallest applicable technique

See [references/techniques.md](references/techniques.md) for the full catalogue. Typical entry points:

| Situation | Technique |
|-----------|-----------|
| Method too long | Extract Method |
| Class doing too much | Extract Class |
| Duplicate code | Extract Method / Pull Up Method |
| Long parameter list | Introduce Parameter Object |
| Nested conditions | Replace Nested Conditional with Guard Clauses |
| `if/elif` on type | Replace Conditional with Polymorphism |
| Magic numbers | Replace Magic Number with Symbolic Constant |
| Class that only delegates | Remove Middle Man / Inline Class |
| Method obsessed with another object's data | Move Method |

### 3) Apply in small, testable steps

For each step:
1. Make the mechanical change.
2. Run the tests.
3. If red, undo the step (the change altered behavior or the test was wrong).
4. Commit or checkpoint only when green.

### 4) Verify no behavior changed

```bash
pytest .          # full suite green
git diff          # review: no logic removed, only structure
```

## Failure modes / debugging

- **Tests break after a refactor**: You changed behavior. Revert the step and re-apply more narrowly, or the test depended on a private implementation detail.
- **Refactoring becomes a rewrite**: Stop. Rewrites are not refactoring — split the work and keep each step behavior-preserving.
- **No tests exist**: Write characterization tests first; refactoring without tests is dangerous.

## Guardrails

- **Never refactor and add features in the same change** — review and rollback become impossible.
- **One technique at a time** — compound refactors hide which step broke behavior.
- **Run tests after every step**, not at the end.
- **Don't refactor speculative or dead code you don't own** without tests.

## Common Mistakes

| Mistake | Why It Fails | Fix |
|---------|--------------|-----|
| Refactoring without tests | No way to detect behavior changes | Add characterization tests first |
| Changing behavior "while I'm here" | Turns a safe refactor into a risky rewrite | Separate feature work from refactoring |
| Applying techniques mechanically | Adds indirection with no benefit | Only refactor when a smell or upcoming change justifies it |
| Big-bang refactor | Hard to isolate what broke | Small, testable steps, commit green |
| Ignoring the smell behind the smell | Treating symptoms, not cause | Fix the root cause (e.g., extract the class, don't just rename) |

## References

- [references/code-smells.md](references/code-smells.md) — 23 smells in 6 groups, with signs and treatments
- [references/techniques.md](references/techniques.md) — 60+ refactoring techniques in 6 groups
- [references/file-responsibility-rules.md](references/file-responsibility-rules.md) — per-language file/function size and complexity thresholds (review triggers + hard limits)
