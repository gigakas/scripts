# Creational Patterns

Patterns that provide object creation mechanisms, increasing flexibility and reuse. Source: [refactoring.guru/creational-patterns](https://refactoring.guru/design-patterns/creational-patterns).

## Factory Method
- **Intent**: Provide an interface for creating an object, but let subclasses decide which class to instantiate. Defer instantiation to subclasses.
- **Problem**: You don't know (at compile time) the exact type of object your code should create; creation depends on runtime info.
- **Structure**: A `Creator` class declares an abstract `factory_method()`; concrete creators override it to return different products. Client code calls the factory method instead of `new ConcreteProduct()`.
- **Use when**: The exact type isn't known until runtime; you want to centralize object creation or provide users a way to extend components.

```python
class Transport:
    def deliver(self): ...

class Truck(Transport): ...
class Ship(Transport): ...

class Logistics:
    def create_transport(self):
        raise NotImplementedError

    def plan_delivery(self):
        t = self.create_transport()
        return t.deliver()

class RoadLogistics(Logistics):
    def create_transport(self):
        return Truck()
```

## Abstract Factory
- **Intent**: Create *families* of related objects without specifying their concrete classes.
- **Problem**: Your code must work with families of related objects, but shouldn't depend on their concrete classes (e.g., UI widgets per OS/theme).
- **Structure**: An abstract factory interface declares a creation method per product type; concrete factories produce a consistent family. Client works only through the abstract interfaces.
- **Use when**: A system must be independent of how its products are created/composed, and multiple families must be used together.

## Builder
- **Intent**: Construct complex objects step by step; the same construction process can create different representations.
- **Problem**: An object has many optional parts or a complicated constructor (telescoping constructors).
- **Structure**: A `Director` (optional) defines the build order; a `Builder` interface declares `build_part()` steps; `ConcreteBuilder` implements them and exposes the `get_result()` product.
- **Use when**: You need different representations from the same construction, or want to assemble an object incrementally.

```python
class QueryBuilder:
    def select(self, *cols): ...   # returns self
    def where(self, cond): ...
    def limit(self, n): ...
    def build(self): ...

q = QueryBuilder().select("name").where("age > 18").limit(10).build()
```

## Prototype
- **Intent**: Copy existing objects without depending on their classes (clone).
- **Problem**: Creating an object is expensive or its class isn't known, but you have an instance you can copy.
- **Structure**: A `Prototype` interface declares `clone()`; concrete prototypes implement copying (shallow or deep).
- **Use when**: Object creation is costly, or you want to avoid subclass hierarchies of factories.

```python
import copy
copy.deepcopy(existing)   # Python's built-in mechanism
```

## Singleton
- **Intent**: Ensure a class has only one instance and provide a global access point to it.
- **Problem**: Shared resource (database connection pool, config) needs a single instance.
- **Structure**: A class with a private/static accessor that lazily creates the one instance.
- **Use when**: Exactly one instance must exist and be globally accessible.
- **Python note**: Often better to use a module-level object, or a class-level cached instance, and inject it rather than using a global accessor (easier to test).

```python
class _Config: ...
config = _Config()   # module-level singleton
```

## Choosing between creational patterns

| Need | Pattern |
|------|---------|
| Defer concrete class choice to subclasses | Factory Method |
| Create families of related objects | Abstract Factory |
| Build a complex object step by step | Builder |
| Clone an existing object | Prototype |
| Exactly one shared instance | Singleton |
