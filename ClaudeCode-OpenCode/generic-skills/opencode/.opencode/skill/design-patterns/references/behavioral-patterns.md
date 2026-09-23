# Behavioral Patterns

Patterns that take care of efficient communication and the assignment of responsibilities between objects. Source: [refactoring.guru/behavioral-patterns](https://refactoring.guru/design-patterns/behavioral-patterns).

## Chain of Responsibility
- **Intent**: Pass a request along a chain of handlers until one of them handles it.
- **Problem**: A request must be processed by one of several handlers, but the right one isn't known up front (e.g., event bubbling, request validation).
- **Structure**: Each `Handler` holds a reference to the next handler; it either handles the request or passes it along.
- **Use when**: Multiple objects can handle a request, and the handler is determined at runtime.

## Command
- **Intent**: Turn a request into a standalone object containing all the request's information.
- **Problem**: You need to queue, log, or undo operations, or decouple the sender from the receiver.
- **Structure**: A `Command` interface with `execute()`; concrete commands bind a receiver to an action; an `Invoker` triggers them.
- **Use when**: You need undo/redo, transactional behavior, or job queues.

## Iterator
- **Intent**: Traverse a collection without exposing its underlying representation.
- **Problem**: Different collection types (list, tree, graph) each need traversal; clients shouldn't depend on internals.
- **Structure**: An `Iterator` exposes `next()`/`has_next()`; the collection returns an iterator.
- **Python note**: Built-in via `__iter__`/`__next__` and the `for` loop. Don't re-implement — use the protocol.

## Mediator
- **Intent**: Reduce chaotic dependencies between objects by routing all communication through a central mediator.
- **Problem**: Many components talk directly to each other, producing a tangled web of dependencies.
- **Structure**: A `Mediator` object coordinates interactions; components only know the mediator, not each other.
- **Use when**: Many-to-many communication is getting out of hand (e.g., form widgets, chat rooms).

## Memento
- **Intent**: Capture and restore an object's internal state without violating encapsulation.
- **Problem**: You need snapshots/undo, but exposing internal state would break encapsulation.
- **Structure**: An `Originator` creates a `Memento` (opaque state snapshot); a `Caretaker` stores/restores them.
- **Use when**: Undo/rollback or checkpointing is required.

## Observer
- **Intent**: Define a one-to-many dependency so that when one object changes state, all its dependents are notified automatically.
- **Problem**: Many objects need to react to another object's changes without tight coupling.
- **Structure**: A `Publisher` maintains a list of `Subscriber`s and notifies them on change; subscribers register/unregister themselves.
- **Use when**: Event-driven updates (e.g., pub/sub, UI reacting to model changes).

## State
- **Intent**: Let an object alter its behavior when its internal state changes (appears to change class).
- **Problem**: An object's behavior is full of `if`/`switch` on its state, and state transitions are scattered.
- **Structure**: A `Context` holds a reference to a `State` object; each concrete state implements the behavior for that state and may transition the context to another state.
- **Use when**: An object has many states and state-specific behavior (e.g., a document Draft→Submitted→Approved). Good replacement for state-based conditionals.

## Strategy
- **Intent**: Define a family of algorithms, encapsulate each one, and make them interchangeable.
- **Problem**: You need to swap algorithms at runtime (sorting, payment, compression) without hardcoding.
- **Structure**: A `Context` delegates to a `Strategy` interface; concrete strategies implement the algorithm.
- **Use when**: Multiple variants of an algorithm, or a class has many conditional branches that differ only in their behavior.

```python
class PaymentStrategy:
    def pay(self, amount): raise NotImplementedError

class CardPayment(PaymentStrategy):
    def pay(self, amount): ...

class Checkout:
    def __init__(self, strategy): self.strategy = strategy
    def pay(self, amount): self.strategy.pay(amount)
```

## Template Method
- **Intent**: Define the skeleton of an algorithm, deferring some steps to subclasses.
- **Problem**: Several classes share an algorithm's structure but differ in specific steps.
- **Structure**: A base class defines a template method that calls abstract/overridable step methods; subclasses override the steps.
- **Use when**: You want to fix the algorithm's order but allow variation in steps. (Prefer over duplicating the skeleton.)

## Visitor
- **Intent**: Separate algorithms from the objects they operate on; add operations without changing element classes.
- **Problem**: You need to add many unrelated operations to a stable set of classes without polluting them.
- **Structure**: A `Visitor` declares a `visit()` per element type; elements accept a visitor (`element.accept(visitor)` → `visitor.visit(element)`).
- **Use when**: You have a stable class hierarchy and frequently need new operations on it (e.g., different exporters/analyzers).

## Choosing between behavioral patterns

| Need | Pattern |
|------|---------|
| Handler determined at runtime along a chain | Chain of Responsibility |
| Queue/undo/log operations as objects | Command |
| Traverse a collection | Iterator |
| Centralize many-to-many communication | Mediator |
| Snapshot/restore state | Memento |
| Notify dependents of change | Observer |
| Behavior depends on internal state | State |
| Swap algorithms at runtime | Strategy |
| Fixed skeleton, variable steps | Template Method |
| Add operations to a stable hierarchy | Visitor |

> Strategy vs State vs Template Method: all change behavior, but Strategy swaps a whole algorithm (client-chosen), State changes by internal state, Template Method fixes the skeleton with overridable steps.
