---
name: testing-patterns
description: Write clean, reliable, maintainable tests. Covers test structure (Arrange-Act-Assert), FIRST principles, test doubles (mock/stub/fake/spy/dummy), test smells, and coverage. Language-agnostic.
---

# Testing Patterns

How to structure tests and keep them fast, isolated, and meaningful — in any language.

## When to use

- Writing new tests and want them clean from the start
- Tests are flaky, slow, or brittle and need diagnosis
- Deciding how to isolate a unit from its dependencies (test doubles)
- Reviewing test quality and coverage

## Test structure: Arrange / Act / Assert

Keep every test in three clearly separated phases (also called Given / When / Then):

```
# Arrange — set up fixtures and dependencies
# Act     — perform the single action under test
# Assert  — verify the outcome
```

Only one logical action per test. If you need multiple "acts", you probably need multiple tests.

## FIRST principles

A good test is:

| Letter | Principle | Meaning |
|--------|-----------|---------|
| F | **Fast** | Runs in milliseconds so the whole suite stays quick |
| I | **Independent** | No reliance on order or other tests' side effects |
| R | **Repeatable** | Same result every run (no time/network/randomness) |
| S | **Self-validating** | Passes/fails on its own — no manual inspection |
| T | **Timely** | Written close to the code (ideally before, via TDD) |

## Test doubles

When a unit depends on something slow, external, or hard to trigger, replace the dependency with a *test double*. Choose the right kind — see [references/test-doubles.md](references/test-doubles.md).

Quick taxonomy:

| Double | What it does | Typical use |
|--------|--------------|-------------|
| **Dummy** | Passed but never used | Fill a required parameter |
| **Stub** | Returns a canned value | Provide a fixed input |
| **Spy** | Records calls, returns real result | Assert "was it called?" |
| **Mock** | Returns canned value + verifies expectations | Assert "called with these args?" |
| **Fake** | Working but simplified implementation | In-memory DB, stub server |

Prefer stubs/fakes for *state* verification and mocks for *interaction* verification. Don't mock types you don't own (e.g., third-party libraries) — wrap them instead.

## Test smells

Common signs of problem tests — see [references/test-smells.md](references/test-smells.md) for the full list. The most damaging:

- **Flaky** — passes and fails unpredictably (time, order, network, concurrency).
- **Fragile / overspecified** — breaks when production code changes for reasons unrelated to the test's intent.
- **Slow** — drags the suite down and discourages running tests.
- **Tautological / "test the test"** — asserts what the setup already guaranteed.
- **Obscure** — hard to tell what's being tested and why.

## Coverage: what to measure

- Coverage tells you what is **not** tested; it does **not** tell you the tests are good.
- Aim for meaningful behavioral coverage of logic and branches, not a magic number.
- Prioritize high-risk paths (validation, money/security, edge cases) over trivial getters.

## References

- [references/test-doubles.md](references/test-doubles.md) — the five doubles, when to use them, per-language tooling
- [references/test-smells.md](references/test-smells.md) — catalogue of test anti-patterns and fixes

## Guardrails

- **Isolate tests** — a test must not depend on another test's data or order.
- **Never hit real external systems** — network, clock, filesystem, DB (unless it's an integration test).
- **Mock the boundary, not the internals** — replace external I/O, not your own small classes.
- **One behavior per test** — more than a few assertions usually means split the test.
- **Keep asserts meaningful** — assert outcomes, not that a line executed.

## Common Mistakes

| Mistake | Why It Fails | Fix |
|---------|--------------|-----|
| Mocking the wrong layer | Tests lock in implementation details | Mock at the external boundary only |
| Overusing mocks | Tests pass while real code is broken | Prefer stubs/fakes; add integration tests |
| Asserting setup, not behavior | Tautological tests give false confidence | Assert a real outcome of the action |
| Non-deterministic tests | Flaky CI, lost trust in the suite | Inject clock/randomness; avoid real time/network |
| Tests sharing mutable state | Order-dependent failures | Fresh fixtures per test |
