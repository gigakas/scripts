# Test Doubles

Test doubles replace real dependencies so a unit can be tested in isolation. Language-agnostic concepts; tooling varies per language.

## The five doubles

### Dummy
- An object passed around but never actually used; exists only to satisfy a signature.
- **Use**: fill a required parameter whose value is irrelevant to this test.

### Stub
- Returns a hard-coded (canned) value when called. No logic, no verification.
- **Use**: feed a fixed input to the code under test (e.g., "the service returns success").
- **Verification style**: *state* — assert the outcome of the unit, not the call.

### Spy
- Wraps a real object and records calls (arguments, call count) while still doing the real work.
- **Use**: assert that a certain method was invoked, without replacing behavior.

### Mock
- Pre-programmed with expectations: returns canned values *and* verifies how it was called (method, arguments, order).
- **Use**: *interaction* verification — "this collaborator was called with these arguments".
- **Caution**: the strictest and most brittle double; overuse couples tests to implementation.

### Fake
- A real, working implementation with shortcuts (in-memory DB, stub HTTP server, in-memory file system).
- **Use**: replace a heavyweight dependency with something functionally equivalent and fast.
- **Benefit**: tests stay readable and behavior-focused; great for integration-style tests.

## How to choose

```
Does the test care about the dependency's calls?        → Mock / Spy
Does the test just need a value from the dependency?    → Stub
Does the test need realistic behavior without the cost? → Fake
Is the dependency irrelevant to this test?              → Dummy
```

Rule of thumb: **stub queries, mock commands** (in the CQS sense) — stub things that return data, mock things that produce side effects.

## When NOT to use doubles

- Don't mock the class you're testing.
- Don't mock third-party code you don't own — wrap it behind your own interface/port first.
- Don't mock value objects or simple data — just build a real instance.
- Don't mock when a real fake (or the real thing in an integration test) is cheap and more meaningful.

## Per-language tooling

| Language | Mock/stub framework | Notable features |
|----------|---------------------|------------------|
| Python | `unittest.mock` (stdlib), `pytest-mock` | `Mock`, `MagicMock`, `patch`, auto-speccing |
| JavaScript/TS | Jest, Vitest, Sinon | `jest.fn()`, `jest.mock()`, spies, timers |
| Java | Mockito, EasyMock | `mock()`, `when().thenReturn()`, `verify()` |
| C# | Moq, NSubstitute, FakeItEasy | LINQ-to-Mocks, `It.IsAny<T>()` |
| Go | `gomock`, `testify/mock` | generated mocks via `mockgen` |
| Ruby | RSpec Mocks, Mocha | `allow().to receive`, `expect().to receive` |
| Rust | `mockall`, `mockito` | derive-based mocks, `#[automock]` |
| PHP | PHPUnit mocks, Mockery | `createMock`, `shouldReceive` |

## Python example (concepts translate to any language)

```python
from unittest.mock import Mock, patch

# Stub: the payment gateway always approves
gateway = Mock()
gateway.charge.return_value = {"status": "ok"}

service = Checkout(gateway)
result = service.pay(order, amount=100)

assert result == "success"          # state verification
gateway.charge.assert_called_once() # interaction verification
```

## Guardrails

- **One mock per test is a smell** — if you mock 5 collaborators, you're testing wiring, not behavior.
- **Verify behavior, not mechanics** — assert what happened, not how many times an internal helper ran.
- **Keep doubles at the boundary** — replace I/O and external services, not your own small classes.
- **Reset doubles between tests** — shared mock state causes order-dependent failures.
