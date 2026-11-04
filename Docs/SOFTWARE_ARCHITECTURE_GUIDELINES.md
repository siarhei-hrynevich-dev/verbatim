# Software Architecture Guidelines

## 1. Architectural Style

The application follows **Lightweight Clean Architecture with MVVM for the presentation layer**.

The goal is to maintain clear separation of responsibilities, testable business logic, and predictable dependency boundaries without introducing unnecessary abstractions.

The architecture consists of four logical layers:

1. Presentation
2. Application
3. Domain
4. Infrastructure

These are logical boundaries within a single application, not mandatory separate Swift modules or Xcode targets.

### Dependency Rule

Source-code dependencies must point toward the application core.

- Presentation depends on Application and Domain.
- Application depends on Domain.
- Infrastructure implements interfaces required by the Application or Domain layers.
- Domain must not depend on Presentation, Application, or Infrastructure.
- Application must not depend on concrete Infrastructure implementations.

The composition root is responsible for connecting concrete implementations to their abstractions.

Do not introduce direct dependencies between unrelated features.

---

## 2. Presentation — MVVM

Use SwiftUI with the Observation framework.

### Views

Views are responsible for:

- Rendering UI.
- Handling user interaction.
- Managing local presentation state.
- Displaying loading, success, and error states.

Views must not:

- Contain business rules.
- Access databases directly.
- Call filesystem APIs for business operations.
- Execute ML inference.
- Manage long-running application workflows.
- Instantiate infrastructure services.

### ViewModels

Use `@Observable` ViewModels when a feature requires nontrivial state management or asynchronous application operations.

ViewModels are responsible for:

- Exposing presentation state.
- Handling UI actions.
- Calling Application Services.
- Mapping domain results to presentation models.
- Managing UI-specific loading and error states.

ViewModels must not:

- Implement persistence.
- Interact directly with infrastructure frameworks.
- Own long-lived operations that must survive window closure.
- Contain domain business rules.
- Become general-purpose service containers.

Use `@MainActor` for UI-bound observable models.

Not every View requires a ViewModel. Simple reusable components should receive values and callbacks directly.

---

## 3. Application Layer

The Application Layer coordinates business workflows.

Use Application Services or Coordinators for operations involving multiple components, significant state transitions, or long-running processes.

Responsibilities include:

- Executing application use cases.
- Coordinating infrastructure operations.
- Enforcing workflow invariants.
- Managing long-lived application state.
- Handling cancellation and retries.
- Translating infrastructure failures into application-level results.

Application Services must not depend on SwiftUI or AppKit presentation components.

Avoid creating a separate UseCase class for every trivial operation.

Prefer cohesive services that represent meaningful application capabilities.

---

## 4. Domain Layer

The Domain Layer contains framework-independent application concepts.

It includes:

- Entities.
- Value objects.
- Domain enums.
- Business rules.
- State transition rules.
- Domain errors.
- Interfaces representing meaningful external dependencies.

Domain code must use plain Swift whenever possible.

Domain must not import:

- SwiftUI.
- AppKit.
- ScreenCaptureKit.
- WhisperKit.
- Core ML.
- SQLite libraries.

Prefer immutable value types.

Use `Sendable` for types crossing concurrency boundaries.

Domain models must not contain presentation formatting or database-specific fields unless these are genuine domain concepts.

---

## 5. Infrastructure Layer

Infrastructure contains implementations that interact with external systems and platform APIs.

Examples:

- ScreenCaptureKit adapters.
- Database repositories.
- Filesystem implementations.
- Audio/video processing.
- Machine learning providers.
- Operating system integrations.

Infrastructure implements contracts required by the application core.

Infrastructure must not contain UI-specific business logic.

Keep framework-specific types inside infrastructure boundaries whenever practical.

Convert external framework types into domain or application types before returning them to higher layers.

Do not wrap every framework API automatically. Create adapters where isolation, testing, lifecycle management, or replacement provides real value.

---

## 6. SOLID Principles

Apply SOLID pragmatically.

### Single Responsibility Principle

Every type should have one clear reason to change.

Avoid classes combining unrelated responsibilities such as:

- UI state and database access.
- Recording lifecycle and file indexing.
- Networking and presentation logic.
- Persistence and business validation.

Split responsibilities when they represent genuinely different reasons to change.

Do not split small cohesive types merely to reduce line count.

### Open/Closed Principle

Prefer extending behavior through composition rather than modifying large conditional structures.

Introduce protocols or polymorphism when multiple implementations or meaningful variation actually exist.

Avoid speculative extension points.

### Liskov Substitution Principle

Implementations of an abstraction must preserve the behavioral contract.

Do not introduce protocols whose implementations have incompatible semantics.

### Interface Segregation Principle

Prefer small, cohesive protocols.

Clients should depend only on operations they actually need.

Avoid large service interfaces containing unrelated methods.

### Dependency Inversion Principle

High-level application logic must not depend directly on low-level framework implementations.

Use abstractions at meaningful boundaries, especially for persistence, external libraries, hardware access, and long-running operations.

Do not create protocols for simple data structures or every internal helper.

---

## 7. Dependency Injection

Use constructor-based dependency injection.

A single Composition Root is responsible for creating application-wide dependencies.

Rules:

- Dependencies must be explicit.
- Avoid global mutable singletons.
- Avoid service locator patterns.
- Do not instantiate concrete infrastructure implementations inside ViewModels.
- Prefer initializer injection for required dependencies.
- Use SwiftUI Environment only where it fits presentation-level dependency propagation.

Do not introduce a third-party dependency injection framework without a demonstrated need.

---

## 8. State Management

Follow the **Single Source of Truth** principle.

Each piece of mutable application state must have one clearly defined owner.

Examples:

- View-local state belongs to the View.
- Presentation state belongs to the ViewModel.
- Long-lived workflow state belongs to an Application Service or Coordinator.
- Persisted data belongs to the relevant repository/storage boundary.

Do not duplicate authoritative state across multiple ViewModels.

Other components should observe or derive state rather than maintaining independent mutable copies.

State transitions should be explicit and validated.

Prefer enums for mutually exclusive states instead of multiple Boolean flags.

---

## 9. Swift Concurrency

Use Swift 6 strict concurrency.

Preferred mechanisms:

- `async/await`
- Actors
- Structured tasks
- `@MainActor`
- `AsyncSequence`
- Cooperative cancellation

Rules:

- UI state must be updated on the main actor.
- Mutable shared state must have explicit isolation.
- Avoid unstructured background tasks without lifecycle ownership.
- Do not use `Task.detached` by default.
- Do not use `@unchecked Sendable` to silence compiler errors.
- Do not use `DispatchQueue.main.async` as the default state-management mechanism.
- Do not block the main actor with I/O or heavy computation.
- Treat actor reentrancy as a potential source of invalid state transitions.
- Define ownership and cancellation semantics for long-running tasks.

Use callback adapters when integrating legacy framework APIs, but preserve their threading and isolation requirements.

---

## 10. Error Handling

Errors must be explicit and actionable.

Rules:

- Do not silently swallow errors.
- Avoid force-unwraps and force-try.
- Use typed errors where meaningful.
- Translate infrastructure errors at architectural boundaries.
- Keep user-facing error formatting in the Presentation Layer.
- Preserve underlying error information for diagnostics.
- Handle cancellation separately from ordinary failures.

Avoid returning optional values to represent unrelated error conditions.

---

## 11. Testing

Architecture must support testing without running the full application.

### Domain tests

Test business rules, validation, state transitions, and pure transformations.

### Application tests

Test workflows using controlled dependencies or test implementations of infrastructure interfaces.

### Infrastructure tests

Test real database operations, filesystem behavior, framework adapters, and integration boundaries where feasible.

### Presentation tests

Test important ViewModel behavior and state transitions.

Rules:

- Prefer behavioral tests over implementation-detail tests.
- Avoid unnecessary mocks.
- Use simple in-memory implementations where appropriate.
- Do not require hardware access for ordinary unit tests.
- Keep tests deterministic.

---

## 12. Code Organization

Use a hybrid organizational approach:

**Feature-based structure for Presentation.**

**Layer-based structure for Application, Domain, and Infrastructure.**

Example:

```text
App/
Features/
  Recording/
  Library/
  Player/
  Settings/
Application/
Domain/
Infrastructure/
Shared/
```

Rules:

- Group code by responsibility, not merely by file type.
- Keep feature-specific UI components within their feature.
- Move components to Shared only when actually reused.
- Avoid circular dependencies.
- Avoid large generic `Utils` directories.
- Create new modules only when there is a concrete benefit.
- Do not generate empty abstractions for future functionality.

---

## 13. General Engineering Principles

Follow:

- DRY — avoid unnecessary duplication.
- KISS — prefer the simplest correct implementation.
- YAGNI — do not implement speculative functionality.
- Composition over inheritance.
- Explicit dependencies over hidden dependencies.
- Clear ownership over shared mutable state.
- Small cohesive interfaces.
- Readability over cleverness.
- Testability without excessive mocking.

Avoid:

- God objects.
- Massive ViewModels.
- Deep inheritance hierarchies.
- Premature generic abstractions.
- Unnecessary design patterns.
- Business logic inside SwiftUI Views.
- Global mutable application state.
- Framework types leaking across architectural boundaries without justification.

---

## 14. Rules for AI Coding Agents

Before implementing any feature:

1. Identify the responsible architectural layer.
2. Identify existing components that should own the behavior.
3. Reuse existing patterns where appropriate.
4. Define new interfaces only when they represent meaningful boundaries.
5. Determine state ownership.
6. Determine concurrency isolation.
7. Determine error-handling behavior.
8. Add appropriate tests.

During implementation:

- Follow the dependency rule.
- Keep changes focused.
- Preserve established architecture.
- Avoid introducing unrelated refactors.
- Do not add dependencies without justification.
- Do not invent abstractions for hypothetical future requirements.
- Keep public interfaces minimal.
- Document significant architectural decisions.

After implementation:

- Run formatting.
- Run linting.
- Build the application.
- Run relevant tests.
- Verify architectural boundaries were preserved.
- Report deviations from architectural guidelines.

If a requested implementation conflicts with these rules, prefer the simplest compliant design.

If a rule must be violated for technical reasons, document the reason rather than silently bypassing it.

---

## 15. Architectural Philosophy

This project follows **pragmatic Clean Architecture**, not maximalist Clean Architecture.

Architectural boundaries exist to reduce coupling, improve testability, and make future changes safer.

They are not an excuse to introduce unnecessary layers, protocols, factories, managers, coordinators, or boilerplate.

**The preferred solution is the simplest implementation that preserves clear responsibilities, explicit dependencies, concurrency safety, and testability.**
