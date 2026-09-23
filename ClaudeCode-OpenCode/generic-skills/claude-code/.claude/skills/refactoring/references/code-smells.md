# Code Smells

Code smells are indicators of problems that can be addressed during refactoring. They are easy to spot and fix, but may be symptoms of a deeper issue. Source: [refactoring.guru/smells](https://refactoring.guru/refactoring/smells).

## 1. Bloaters

Bloaters are code, methods and classes that have grown to gargantuan proportions and are hard to work with.

### Long Method
- **Signs**: Method longer than ~10 lines; needs comments to explain parts; multiple levels of nesting.
- **Treatment**: Extract Method, Replace Temp with Query, Introduce Parameter Object, Replace Method with Method Object.
- **Benefit**: Each extracted piece is self-documenting; easier to reuse and test.

### Large Class
- **Signs**: Class with many fields/methods/responsibilities (God Object).
- **Treatment**: Extract Class, Extract Subclass, Extract Interface.
- **Benefit**: Single responsibility; easier to understand and change.

### Primitive Obsession
- **Signs**: Using primitives (str/int/float) instead of small objects for simple domains (money, ranges, phone numbers); constants for type codes.
- **Treatment**: Replace Data Value with Object, Replace Type Code with Class/Subclasses/State-Strategy, Extract Class, Introduce Parameter Object, Replace Array with Object.
- **Benefit**: Type safety, validation in one place, richer behavior.

### Long Parameter List
- **Signs**: More than 3–4 parameters.
- **Treatment**: Introduce Parameter Object, Preserve Whole Object, Replace Parameter with Method Call.
- **Benefit**: Readable calls; fewer ordering mistakes.

### Data Clumps
- **Signs**: The same group of fields appears together in multiple places (e.g., `start_date` + `end_date`, or `x` + `y`).
- **Treatment**: Extract Class, Introduce Parameter Object, Preserve Whole Object.
- **Benefit**: One concept, one class; reduces duplication.

## 2. Object-Orientation Abusers

Incomplete or incorrect application of object-oriented principles.

### Switch Statements
- **Signs**: Complex `switch`/`if-elif` on type or field; the same switch repeated across the codebase.
- **Treatment**: Replace Conditional with Polymorphism, Replace Type Code with Subclasses/State-Strategy, Replace Parameter with Explicit Methods, Introduce Null Object.
- **Note**: A switch on a *single* method is often fine; it's a smell when it spreads and must change in many places.

### Temporary Field
- **Signs**: A field that only has a value in specific circumstances; otherwise empty.
- **Treatment**: Extract Class, Introduce Null Object.
- **Benefit**: No mystery state; clearer object lifecycle.

### Refused Bequest
- **Signs**: A subclass uses only a fraction of inherited methods/fields; inheritance forced for code reuse.
- **Treatment**: Replace Inheritance with Delegation, remove unused fields/methods.
- **Benefit**: Prefer composition over forced inheritance.

### Alternative Classes with Different Interfaces
- **Signs**: Two classes do the same thing but have different method names.
- **Treatment**: Rename Method, Move Method, Extract Superclass.
- **Benefit**: Interchangeable classes; unified interface.

## 3. Change Preventers

These make changing one thing force you to change many others.

### Divergent Change
- **Signs**: One class is modified for many unrelated reasons.
- **Treatment**: Extract Class (split so each change targets one class).
- **Benefit**: Single responsibility; fewer merge conflicts.

### Shotgun Surgery
- **Signs**: Making any change requires small edits in many different classes.
- **Treatment**: Move Method, Move Field, Inline Class (consolidate the scattered logic).
- **Benefit**: Change lives in one place.

### Parallel Inheritance Hierarchies
- **Signs**: Every time you subclass in one hierarchy, you must create a subclass in another (e.g., class per page + class per handler).
- **Treatment**: Move Method/Field, collapse one hierarchy, or let one class reference the other.
- **Benefit**: One hierarchy to extend instead of two.

## 4. Dispensables

Something whose absence would make the code cleaner.

### Comments
- **Signs**: Comments that explain *what* the code does (vs. *why*), or comments that have drifted from the code.
- **Treatment**: Extract Method, Extract Variable, Rename Method, Introduce Assertion.
- **Benefit**: Self-documenting code; comments reserved for "why", not "what".

### Duplicate Code
- **Signs**: Identical or near-identical code in multiple places.
- **Treatment**: Extract Method, Pull Up Method, Form Template Method.
- **Benefit**: One place to fix; less drift.

### Lazy Class
- **Signs**: A class that does almost nothing; not worth maintaining.
- **Treatment**: Inline Class, Collapse Hierarchy.
- **Benefit**: Fewer moving parts.

### Data Class
- **Signs**: A class with only fields and trivial getters/setters, and no real behavior; other classes manipulate its data.
- **Treatment**: Move Method (pull behavior onto the data class), Encapsulate Collection.
- **Benefit**: Behavior and data live together.

### Dead Code
- **Signs**: Unused variables, parameters, methods, classes, or branches that can never execute.
- **Treatment**: Remove them; Remove Parameter.
- **Benefit**: Less code to read and maintain.

### Speculative Generality
- **Signs**: Unused abstractions, parameters, hooks, or "for the future" code that no one uses.
- **Treatment**: Collapse Hierarchy, Inline Class, Remove Parameter, Rename Method.
- **Benefit**: Simpler code; YAGNI.

## 5. Couplers

These contribute to excessive coupling between classes, or show what happens when coupling is replaced by excessive delegation.

### Feature Envy
- **Signs**: A method accesses another class's data more than its own.
- **Treatment**: Move Method, Extract Method, Move Field.
- **Benefit**: Methods live next to the data they use.

### Inappropriate Intimacy
- **Signs**: One class pokes into the private fields of another.
- **Treatment**: Move Method, Move Field, Hide Delegate, Replace Inheritance with Delegation.
- **Benefit**: Encapsulation restored.

### Message Chains
- **Signs**: `a.b().c().d()` — the client walks a chain of calls to reach data.
- **Treatment**: Hide Delegate, Extract Method, Move Method.
- **Benefit**: Client depends on one method, not the whole chain.

### Middle Man
- **Signs**: A class that does nothing but delegate to another.
- **Treatment**: Remove Middle Man, Inline Method, Replace Delegation with Inheritance.
- **Note**: The opposite smell of Message Chains — some delegation is fine; too much is noise.

## 6. Other Smells

### Incomplete Library Class
- **Signs**: The library (or framework) lacks a method you need, but you can't modify it.
- **Treatment**: Introduce Foreign Method, Introduce Local Extension.
- **Benefit**: Extend third-party code without forking it.
