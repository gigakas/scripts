---
name: test-driven-development
description: Write tests before implementation in short red-green-refactor cycles. Use when building new features, fixing bugs (write a failing test first), or adding tests to legacy code without coverage. Language-agnostic.
---

# Test-Driven Development (TDD)

A discipline where you write a failing test first, make it pass with the minimal code, then refactor. TDD drives a clean, testable design and gives you a regression safety net for free.

## When to use

- Building a new feature or module from scratch
- Fixing a bug — first write a test that reproduces it, then fix
- Adding behavior to existing code (each new rule starts as a failing test)
- Legacy code with no tests — start with *characterization tests* (see below)

## Core principles

1. **Red → Green → Refactor.** Never write production code without a failing test.
2. **Smallest step.** Write just enough test to fail, just enough code to pass.
3. **Fast feedback.** Run only the relevant test (or a tight unit suite) while cycling.
4. **Test behavior, not implementation.** Assert outcomes, not internal calls.
5. **No new code is un-tested.** Coverage grows with every feature.

## Procedure

### The cycle

```
┌─────────────┐
│  RED        │  write ONE failing test that expresses a missing behavior
│             │  run it → confirm it fails for the RIGHT reason
└──────┬──────┘
       ▼
┌─────────────┐
│  GREEN      │  write the minimal code to make it pass (even if ugly)
│             │  run it → green
└──────┬──────┘
       ▼
┌─────────────┐
│  REFACTOR   │  clean up the code and the test, keep them green
│             │  run the whole suite → still green
└──────┬──────┘
       │  repeat
       ▼
```

### 0) Decide test granularity

- **Unit test**: a single function/class in isolation (fast, many of them).
- **Integration test**: a few components together, or the code + a real/fake dependency.
- Prefer unit tests for the cycle; integration tests confirm wiring.

### 1) RED — write the failing test

Express intent, not internals. Give the test a name that states the behavior:

```
test_returns_zero_balance_for_new_account()
test_rejects_payment_when_funds_are_insufficient()
```

Confirm the failure is *for the expected reason* (the behavior is missing), not a typo or import error.

### 2) GREEN — make it pass minimally

Write the simplest code that satisfies the test. It may hardcode, duplicate, or look naive — that's fine. Resist the urge to design ahead.

### 3) REFACTOR — clean up with confidence

Now remove duplication, extract methods, rename, apply design patterns — safely, because tests are green (see the `refactoring` skill).

### 4) Commit at green

Checkpoint after each red-green-refactor round so every commit is releasable.

## Characterization tests (legacy code)

When code has no tests, capture its *current* behavior before changing it:

1. Run the code, observe actual outputs for given inputs.
2. Encode those outputs as tests — they describe what the code *does*, not what it *should* do.
3. Now refactor/change safely; if a characterization test breaks, you changed behavior (possibly on purpose — then update the test).

## Which test to write first

| Situation | Start with |
|-----------|------------|
| New function | The simplest meaningful input/output |
| New feature | The "happy path" end-to-end of the feature |
| Bug fix | A test reproducing the exact bug |
| Validation/edge cases | The boundary that must be rejected |

## Guardrails

- **One behavior per test** — a test with many assertions hides failures.
- **Never skip the failing step** — if a test doesn't fail before the code, it isn't testing anything.
- **Don't test third-party code** — test your code, not the library.
- **Refactor only on green** — never refactor with failing tests.
- **Keep the cycle short** — minutes, not hours.

## Common Mistakes

| Mistake | Why It Fails | Fix |
|---------|--------------|-----|
| Writing code first, tests after | Tests only confirm what you wrote, not the requirement | Write the failing test first |
| Not seeing the test fail | False confidence in a tautological test | Run it before implementing; verify it fails for the right reason |
| Testing implementation details | Tests break on any refactor | Assert behavior/outcomes |
| Big steps in the cycle | Hard to isolate what's wrong | Smallest red/green step each time |
| Skipping refactor phase | Technical debt accumulates silently | Refactor every cycle, on green |
| No characterization tests on legacy code | Unsafe changes to unknown behavior | Encode current behavior first |
