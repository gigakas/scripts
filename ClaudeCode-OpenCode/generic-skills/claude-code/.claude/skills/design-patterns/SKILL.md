---
name: design-patterns
description: Apply the classic Gang of Four design patterns to structure code. Use when choosing how to organize classes/objects for creation, composition, or communication, or when a design smell (rigid, fragile, immobile code) calls for a known solution. Source: https://refactoring.guru
---

# Design Patterns

Design patterns are typical solutions to common problems in software design. Each is a blueprint you customize to solve a particular design problem. Source: [refactoring.guru](https://refactoring.guru).

## When to use

- Choosing how to organize classes and objects for a new feature
- A design keeps feeling rigid/fragile and you recognize the shape of a known problem
- Communicating intent — patterns give your team a shared vocabulary
- Reviewing code and spotting an opportunity to simplify with a proven structure

## Core principles

1. **Patterns are blueprints, not code** — adapt the structure to your language and problem.
2. **Solve a real problem** — don't introduce a pattern speculatively (see Speculative Generality in the refactoring skill).
3. **Prefer composition over inheritance** where a pattern offers both.
4. **Match intent, not structure** — patterns are grouped by *intent*, so identify the problem first, then the pattern.

## Classification (by intent)

| Group | Intent | Patterns |
|-------|--------|----------|
| **Creational** | Object creation mechanisms — increase flexibility and reuse of existing code | Factory Method, Abstract Factory, Builder, Prototype, Singleton |
| **Structural** | How to assemble objects and classes into larger structures, keeping them flexible and efficient | Adapter, Bridge, Composite, Decorator, Facade, Flyweight, Proxy |
| **Behavioral** | Efficient communication and responsibility assignment between objects | Chain of Responsibility, Command, Iterator, Mediator, Memento, Observer, State, Strategy, Template Method, Visitor |

## Procedure

### 0) Diagnose the problem, then pick the pattern

Ask what you're really trying to do:

| You want to… | Pattern |
|--------------|---------|
| Choose which class to instantiate at runtime, defer to subclasses | Factory Method |
| Create families of related objects without depending on concrete classes | Abstract Factory |
| Construct complex objects step by step | Builder |
| Clone existing objects (avoid costly re-initialization) | Prototype |
| Ensure a single instance of a class | Singleton |
| Make incompatible interfaces work together | Adapter |
| Separate abstraction from implementation so both vary independently | Bridge |
| Treat individual objects and compositions uniformly (tree structures) | Composite |
| Add responsibilities to objects dynamically without subclassing | Decorator |
| Provide a simplified interface to a complex subsystem | Facade |
| Share many small objects to save memory | Flyweight |
| Control access to an object (lazy, remote, protected, logging) | Proxy |
| Pass a request along a chain of handlers until one handles it | Chain of Responsibility |
| Turn a request into an object (queue, log, undo) | Command |
| Traverse a collection without exposing its structure | Iterator |
| Reduce direct coupling between many objects via a central coordinator | Mediator |
| Save/restore an object's state (undo, snapshots) | Memento |
| Notify many objects of a state change | Observer |
| Change behavior when an object's internal state changes | State |
| Swap algorithms at runtime | Strategy |
| Define the skeleton of an algorithm, let subclasses fill steps | Template Method |
| Add operations to objects without modifying their classes | Visitor |

### 1) Confirm it fits your language

Some patterns are partially built into Python (e.g., `Iterable`/`__iter__` covers Iterator; decorators, context managers, and modules often replace Singleton or Proxy). Don't force a pattern the language already provides.

### 2) Sketch the participants

Identify roles (e.g., Context + Strategy, Publisher + Subscribers) and map them onto existing classes before writing code.

### 3) Implement the structure, then verify

Keep each pattern's responsibilities clear and run the relevant tests.

## References

- [references/creational-patterns.md](references/creational-patterns.md) — Factory Method, Abstract Factory, Builder, Prototype, Singleton
- [references/structural-patterns.md](references/structural-patterns.md) — Adapter, Bridge, Composite, Decorator, Facade, Flyweight, Proxy
- [references/behavioral-patterns.md](references/behavioral-patterns.md) — Chain of Responsibility, Command, Iterator, Mediator, Memento, Observer, State, Strategy, Template Method, Visitor

## Guardrails

- **Don't add patterns speculatively** — a pattern with no problem is speculative generality.
- **Prefer the simplest structure** that solves the problem; patterns add indirection.
- **Prefer composition over inheritance** (Strategy, Decorator, Composite, Bridge all lean this way).
- **Reuse language primitives** before re-implementing a pattern.

## Common Mistakes

| Mistake | Why It Fails | Fix |
|---------|--------------|-----|
| Pattern without a problem | Unneeded indirection, harder to read | Only apply when a real design problem exists |
| Matching by structure, not intent | Wrong pattern for the job | Diagnose intent first, then choose |
| Forcing a pattern the language provides | Reinventing the wheel | Use `__iter__`, decorators, context managers, etc. |
| Singleton used as a global variable | Hidden state, hard to test | Prefer dependency injection / module-level state |
| Deep pattern nesting | Over-engineering | Compose patterns sparingly |
