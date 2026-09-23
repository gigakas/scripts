# Refactoring Techniques

Catalog of refactoring techniques grouped by purpose. Each entry: what it does and when to use it. Source: [refactoring.guru/techniques](https://refactoring.guru/refactoring/techniques).

## 1. Composing Methods

Simplify methods, remove code duplication, make them easier to understand.

- **Extract Method** — Move a fragment into a new method named by its intent. The most common refactoring. Use when a method is too long or needs explanatory comments.
- **Inline Method** — Replace a method call with its body when the method is as clear as its name. Reverse of Extract Method.
- **Extract Variable** — Put a complex expression's result in a self-explanatory variable. Use for long conditions/expressions.
- **Inline Temp** — Replace a temp variable that's just assigned from a simple expression with the expression itself.
- **Replace Temp with Query** — Replace a local variable holding a computed result with a method/query. Use to avoid passing temps around and to enable reuse.
- **Split Temporary Variable** — Use separate variables for different values assigned to the same temp (not loop accumulators). Use when a variable is reused for unrelated things.
- **Remove Assignments to Parameters** — Stop reassigning a function parameter; use a local variable instead.
- **Replace Method with Method Object** — Turn a long method with many locals into a class where locals become fields; then extract methods freely.
- **Substitute Algorithm** — Replace a method body with a clearer/cleaner algorithm.

## 2. Moving Features between Objects

Move functionality to the class where it belongs, hide implementation details, reduce coupling.

- **Move Method** — Move a method to the class it uses most. Use to fix Feature Envy.
- **Move Field** — Move a field to the class that uses it most.
- **Extract Class** — Split a class into two when part of its behavior/data can be separated. Use for Large Class / Divergent Change.
- **Inline Class** — Merge a class that does too little into the class that uses it. Use for Lazy Class.
- **Hide Delegate** — Add a wrapper method instead of exposing a delegate object (`a.getB().getC()` → `a.getC()`). Use to fix Message Chains.
- **Remove Middle Man** — When a class delegates too much, call the delegate directly. Reverse of Hide Delegate.
- **Introduce Foreign Method** — Add a standalone utility method that operates on a library object you can't modify. Use for Incomplete Library Class.
- **Introduce Local Extension** — Extend a library class via subclass or wrapper (composition) to add methods.

## 3. Organizing Data

Make working with data easier, replace primitives with richer objects, unify links.

- **Self Encapsulate Field** — Access a field through getters/setters rather than directly. Use when you need to control access.
- **Replace Data Value with Object** — Wrap a primitive field (e.g., a phone number) in a small class. Use for Primitive Obsession.
- **Change Value to Reference** — Replace many copies of an equal object with a single shared instance.
- **Change Reference to Value** — Replace shared objects with distinct copies when shared mutable state is a problem.
- **Replace Array with Object** — Replace an array/record used for heterogenous data with a class with named fields.
- **Duplicate Observed Data** — Copy data to a dedicated object (e.g., separate domain model from UI data).
- **Change Unidirectional Association to Bidirectional** — Add back-references when both sides need to navigate.
- **Change Bidirectional Association to Unidirectional** — Remove a back-reference that's no longer needed.
- **Replace Magic Number with Symbolic Constant** — Replace hard-coded literals with named constants.
- **Encapsulate Field** — Make public fields private and expose via accessors.
- **Encapsulate Collection** — Return a read-only view of a collection instead of the mutable collection itself.
- **Replace Type Code with Class** — Replace a type-code primitive with a small class.
- **Replace Type Code with Subclasses** — Replace a type code with a polymorphic subclass hierarchy.
- **Replace Type Code with State/Strategy** — Replace a type code with a State/Strategy object (when subclassing isn't possible).
- **Replace Subclass with Fields** — Remove subclasses whose only difference is a constant value; use a field instead.

## 4. Simplifying Conditional Expressions

Make conditionals easier to read and understand.

- **Decompose Conditional** — Extract the condition and each branch into named methods. Use when the "why" of a condition is unclear.
- **Consolidate Conditional Expression** — Merge multiple conditionals that lead to the same result into one.
- **Consolidate Duplicate Conditional Fragments** — Move identical code out of all branches to after the conditional.
- **Remove Control Flag** — Replace a boolean flag that controls a loop/break with `break`/`continue`/`return`.
- **Replace Nested Conditional with Guard Clauses** — Replace deep nesting with early `return`/`continue`/`raise` guards.
- **Replace Conditional with Polymorphism** — Replace type-based conditionals with polymorphic subclasses/strategy. Use for Switch Statements.
- **Introduce Null Object** — Replace `None`/null checks with a neutral object that does nothing. Use for repeated null checks.
- **Introduce Assertion** — Make assumptions explicit with an assertion at the top of a method.

## 5. Simplifying Method Calls

Make method interfaces simpler and easier to use.

- **Rename Method** — Give a method a name that says what it does.
- **Add Parameter** / **Remove Parameter** — Adjust the signature when the method needs more (or no longer needs) data.
- **Separate Query from Modifier** — Split a method that returns a value *and* changes state into two methods.
- **Parameterize Method** — Merge methods that do the same thing with different constants into one method with a parameter.
- **Replace Parameter with Explicit Methods** — Replace a method that switches on a parameter with separate named methods. Reverse of Parameterize Method.
- **Preserve Whole Object** — Pass the whole object instead of many of its fields.
- **Replace Parameter with Method Call** — Replace a parameter with a call to the method that can provide it (when the parameter is derivable).
- **Introduce Parameter Object** — Group parameters that naturally go together into a single object. Use for Long Parameter List / Data Clumps.
- **Remove Setting Method** — Make a field immutable by removing its setter (set via constructor only).
- **Hide Method** — Make an unused internal method private.
- **Replace Constructor with Factory Method** — Replace a constructor with a factory method for more control (caching, subclasses, clarity).
- **Replace Error Code with Exception** — Replace returned error codes with exceptions.
- **Replace Exception with Test** — Replace an exception thrown for control flow with an explicit condition check.

## 6. Dealing with Generalization

Move methods/fields up and down an inheritance hierarchy; add or remove classes.

- **Pull Up Field / Pull Up Method** — Move a field/method duplicated in subclasses to the superclass.
- **Pull Up Constructor Body** — Move common constructor logic to the superclass constructor.
- **Push Down Method / Push Down Field** — Move a method/field only used by some subclasses down to those subclasses.
- **Extract Subclass** — Create a subclass for a subset of features used only in some cases.
- **Extract Superclass** — Create a superclass for shared features of two classes.
- **Extract Interface** — Extract a common interface from a class so clients depend on the contract.
- **Collapse Hierarchy** — Merge a superclass/subclass that are too similar (or a subclass that's a Lazy Class).
- **Form Template Method** — Unify duplicated algorithm skeletons in subclasses into a template method with hooks.
- **Replace Inheritance with Delegation** — Replace a subclass with a separate object the class delegates to. Prefer composition. Use for Refused Bequest.
- **Replace Delegation with Inheritance** — Replace a delegating class with inheritance when the delegating class mirrors the whole interface.
