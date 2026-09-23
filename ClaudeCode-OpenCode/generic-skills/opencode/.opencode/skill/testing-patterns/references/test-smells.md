# Test Smells

Anti-patterns in tests that make a suite slow, brittle, or meaningless — and how to fix them. Language-agnostic.

## Flaky tests

Pass and fail unpredictably. They erode trust in the whole suite.

**Causes & fixes:**
| Cause | Fix |
|-------|-----|
| Real time (`now()`, timeouts) | Inject a clock; freeze/pause time |
| Real network / external service | Fake or stub the dependency |
| Shared mutable state between tests | Fresh fixtures per test; isolate state |
| Concurrency / race conditions | Await deterministically; avoid real parallelism |
| Order dependence | Make each test self-contained |
| Randomness (unseeded) | Seed the generator, or assert on invariants |

## Fragile / overspecified tests

Break when production code changes for reasons unrelated to the test's intent.

- **Testing implementation details** (private methods, exact call sequences) → assert *behavior* instead.
- **Mocking too deep** → mock at the boundary only.
- **Snapshot/golden-file overuse** → prefer targeted assertions; review snapshots carefully.

## Slow tests

Drag down feedback loops so people stop running them.

- **Real databases/filesystem in unit tests** → use fakes; reserve real DB for integration tests.
- **`sleep()` / polling** → inject time, or use a signal/condition.
- **Unnecessary setup** → build only the fixtures this test needs.
- **Mark slow tests** → separate them from the fast unit suite.

## Tautological tests ("test the test")

Assert what the setup already guaranteed, so they can never fail meaningfully.

```
account = create_account(balance=0)
assert account.balance == 0        # tautological if constructor already sets 0
```

Fix: assert on a *behavior* or a *transition* (deposit changes balance; insufficient funds rejected).

## Obscure tests

Hard to tell what's being tested and why.

- **Vague names** (`test_1`, `test_process`) → name the behavior: `test_returns_zero_balance_for_new_account`.
- **Magic numbers** → name constants or use clearly derived values.
- **Long setup hidden in helpers** → keep the Arrange phase visible and minimal.

## Duplicated logic in tests

- Copy-pasted assertions across many tests → extract test helpers/factories.
- **But**: don't over-DRY — a little repetition in tests is clearer than a clever shared abstraction.

## Conditional / branched test logic

- `if`/loops inside a test make it a mini-program that itself needs testing. A test should be a straight line: Arrange → Act → Assert.

## Environment-dependent tests

- Rely on locale, timezone, file paths, OS, env vars → make them explicit (inject config) or set them in the test.

## Categorization to remember

| Category | Signal |
|----------|--------|
| **Fast** | runs in ms |
| **Independent** | no order/state coupling |
| **Repeatable** | deterministic |
| **Self-validating** | green/red without human judgment |
| **Timely** | written with the code |

## Fixing a smell vs. deleting the test

- A *flaky/overspecified* test can usually be fixed by changing the test.
- A *tautological* or *obscure* test that adds no signal should be rewritten or removed — a bad test is worse than no test.
