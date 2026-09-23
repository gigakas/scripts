# Structural Patterns

Patterns that explain how to assemble objects and classes into larger structures while keeping them flexible and efficient. Source: [refactoring.guru/structural-patterns](https://refactoring.guru/design-patterns/structural-patterns).

## Adapter
- **Intent**: Let objects with incompatible interfaces work together.
- **Problem**: You need to use an existing class, but its interface doesn't match what the rest of your code expects.
- **Structure**: A wrapper (`Adapter`) implements the target interface and delegates calls to the wrapped object (composition), or inherits from both (multiple inheritance).
- **Use when**: Integrating a third-party library or legacy code without changing it.

```python
class SquarePeg: ...
class RoundHole:
    def fits(self, peg): return peg.radius <= self.radius

class SquarePegAdapter:   # adapts SquarePeg to fit RoundHole
    def __init__(self, peg): self.peg = peg
    @property
    def radius(self): return self.peg.width * 0.7071
```

## Bridge
- **Intent**: Separate an abstraction from its implementation so both can vary independently.
- **Problem**: Combining multiple orthogonal dimensions (e.g., Shape × Color, or Device × OS) via inheritance explodes into a class per combination.
- **Structure**: The abstraction holds a reference to an implementation interface; concrete implementations are swapped at runtime. Two independent hierarchies.
- **Use when**: You have two orthogonal dimensions of variation and want to avoid a class explosion.

## Composite
- **Intent**: Compose objects into tree structures to represent part-whole hierarchies; let clients treat individual objects and compositions uniformly.
- **Problem**: Code must treat both a single object and a group of objects the same way (e.g., a file and a folder).
- **Structure**: A common `Component` interface; `Leaf` and `Composite` (which holds children) both implement it. Operations recurse over children.
- **Use when**: You have a recursive tree structure and want uniform treatment.

## Decorator
- **Intent**: Attach additional responsibilities to an object dynamically, without modifying its class or creating subclasses.
- **Problem**: You need to add optional behaviors (logging, caching, filtering) in many combinations — subclassing explodes.
- **Structure**: A `Decorator` wraps a component, implements the same interface, and adds behavior before/after delegating.
- **Use when**: Responsibilities should be addable/removable at runtime; avoids a rigid class hierarchy.
- **Python note**: Python decorators (`@decorator`) are a related but distinct mechanism (wrapping functions).

## Facade
- **Intent**: Provide a simplified interface to a complex subsystem.
- **Problem**: Client code is coupled to many subsystem classes and their dependencies.
- **Structure**: A `Facade` class exposes a small set of convenient methods and delegates to the subsystem behind it.
- **Use when**: You want a simple entry point over a complex library or set of services.

## Flyweight
- **Intent**: Share common state among many similar objects to save memory.
- **Problem**: A program needs a huge number of near-identical objects (characters in a document, particles).
- **Structure**: Split state into *intrinsic* (shared, immutable) and *extrinsic* (context-dependent); store intrinsic state in a shared flyweight factory.
- **Use when**: Memory is constrained and many objects share substantial identical state.

## Proxy
- **Intent**: Provide a substitute for another object to control access to it.
- **Problem**: You need lazy initialization, access control, logging, or remote access to an object without changing it.
- **Structure**: A `Proxy` implements the same interface as the real subject and controls when/how to call it.
- **Variants**: Virtual (lazy), Protection (access control), Remote, Logging/Caching proxy.
- **Use when**: You need to intercept access to an object transparently.

## Choosing between structural patterns

| Need | Pattern |
|------|---------|
| Reconcile incompatible interfaces | Adapter |
| Two independent dimensions of variation | Bridge |
| Uniform tree/part-whole treatment | Composite |
| Add responsibilities dynamically | Decorator |
| Simple entry point to a subsystem | Facade |
| Save memory with shared state | Flyweight |
| Control/transparent access to an object | Proxy |

> Adapter vs Bridge vs Decorator vs Proxy: all wrap an object, but differ by *intent* — Adapter reconciles interfaces, Bridge separates dimensions, Decorator adds behavior, Proxy controls access.
