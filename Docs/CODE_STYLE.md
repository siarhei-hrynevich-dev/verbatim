# Swift Code Style

These rules make an individual Swift file easy to scan, understand, and change. Read them before writing or changing code, together with the [architecture guidelines](SOFTWARE_ARCHITECTURE_GUIDELINES.md). Architecture defines responsibilities between components; this document defines how to express those responsibilities inside a file.

## Formatting and tooling

- Use 4 spaces, no tabs, and a preferred line length of 120 characters.
- Let Apple's `swift-format` control braces, whitespace, line wrapping, argument layout, trailing commas, and import ordering. Do not manually align declarations with extra spaces.
- Keep opening braces on the declaration or control-flow line. Do not use semicolons to combine statements.
- Separate declarations and distinct steps with a single blank line. Do not add empty lines between every statement.
- Use the committed [.swift-format](../.swift-format) and [.swiftlint.yml](../.swiftlint.yml). Run `make format`, `make format-check`, and `make lint` for Swift changes.
- Formatting rules are enforced by tooling; naming, cohesion, declaration order, and clarity also require review. Passing lint does not establish readability.

## File scope and declaration order

Prefer one primary type per file, with a matching filename such as `Recording.swift`. Small nested types and tightly related private helpers may stay beside it. Do not create a separate file for every small enum or split a cohesive type merely to reduce line count.

Use this default reading order, omitting sections that are unnecessary:

1. Required imports.
2. A short type documentation comment when its purpose or contract needs explanation.
3. Type attributes and the primary declaration.
4. Small nested types that define the type's vocabulary, such as state or errors.
5. Stored properties: injected dependencies, externally readable state, then private implementation state.
6. Initializers.
7. The main interface: `body` for a View, actions for a ViewModel, operations for a service.
8. Supporting computed properties and private helpers, in the order the main flow uses them.
9. Focused extensions and file-private supporting types.

Keep related declarations together when that improves the reading order. An extension may group a protocol conformance or a substantial cohesive concern. Do not move every method into an extension or scatter a type's core behavior across files. Use `Type+Concern.swift` only when a real separation makes navigation easier.

Use `// MARK: - ...` sparingly in longer files for meaningful groups such as lifecycle or actions. Short files need no section banners, and empty sections are not allowed. Delete obsolete and commented-out code rather than keeping it as a second implementation.

## Names that explain intent

- Use `UpperCamelCase` for types and protocols; `lowerCamelCase` for properties, functions, parameters, and enum cases.
- Name values after their meaning: `recording`, `outputURL`, `duration`, `pendingJobs`. Avoid `data`, `item`, `temp`, or `result` when a more specific name clarifies the operation.
- Use verbs for actions (`cancelProcessing()`) and nouns for values (`processingStatus`). Boolean names should read as predicates: `isRecording`, `hasTranscript`, `canRetry`.
- Choose argument labels so a call reads clearly: `save(recording:to:)`. Do not repeat information already clear from the type or surrounding API.
- Preserve common technical terms such as `id`, `URL`, and `UUID`; avoid unexplained abbreviations and type prefixes.
- Include units in names when the type does not express them, such as `retryDelaySeconds` or `sampleRateHz`.
- Avoid negative Boolean names and double negation. Use explicit enum states when several flags represent mutually exclusive conditions.

## Properties, access, and initialization

Use `let` unless mutation is required. Give state the narrowest practical access: implementation details are `private`; observable state can use `private(set)` when only its owner should mutate it. Use `fileprivate` only for cooperation within the file that actually requires it. Do not mark declarations `public` inside the app without an API boundary that needs it.

Use inferred types when the initializer makes the type obvious. Add annotations when they explain units, optionality, collection contents, or an otherwise ambiguous expression. Avoid annotations that only repeat an explicit constructor.

Inject required dependencies through initializers and keep their declarations together. Validate invariants before assigning initialized state. Avoid hidden work in property initializers or getters: I/O, model loading, task creation, and persistence writes need explicit operations. Computed properties should be cheap and free of surprising side effects.

## Functions and control flow

A function should express one coherent operation at a consistent level of detail. Prefer a main flow that can be read from top to bottom, with named helpers for substantial validation, transformation, or side effects. Extract a helper when its name explains a meaningful step or it removes real duplication; avoid chains of tiny forwarding functions that force readers to jump around.

Use early exits for invalid input and unavailable prerequisites. Use `if` for ordinary branching and `switch` for distinct enum states. Avoid deeply nested conditionals, nested ternaries, and closures containing several unrelated operations. Prefer an explicit loop when iteration includes state changes, error handling, or several side effects. Use `map`, `filter`, and similar operations for clear transformations; break long chains into named intermediate values.

For example, a validation step can state the invariant directly:

```swift
let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
guard !trimmedTitle.isEmpty else {
    throw ValidationError.emptyTitle
}
guard duration.isFinite, duration >= 0 else {
    throw ValidationError.invalidDuration
}
```

Keep each condition understandable on its own. Name a complex predicate when the name adds meaning, rather than extracting every Boolean expression. Use exhaustive switches for app-owned enums when adding a case should require reviewing callers; use fallback cases when the external API requires forward compatibility.

Name repeated or unexplained constants near their use or at the owning type. Explain units and the reason for non-obvious thresholds. Do not introduce a global constants container for unrelated values.

SwiftLint currently warns at 50 function-body lines and 400 file lines, and reports errors at 80 and 600 respectively. Line length warns at 120 and errors at 160. These are review signals, not target sizes: `make lint` passes `--strict` to SwiftLint, so warnings also fail the check. Simplify or split by responsibility instead of hiding long implementations in extensions or disabling rules to pass.

## Optionals and errors

- Unwrap optionals with `guard let` or `if let` where the value becomes necessary. Use optional chaining when absence is expected and needs no separate handling.
- Use `??` only when the fallback has a valid domain meaning. Do not replace missing required data with an empty string, zero, or a random identifier to hide a failure.
- Avoid force unwraps, force-try, and implicitly unwrapped optionals. An unavoidable framework requirement or proven invariant needs a nearby justification.
- Use `throws` or an explicit result for failures that callers must handle. Reserve optional returns for meaningful absence.
- Catch errors where recovery, translation, or presentation is possible. Do not use empty `catch` blocks or `try?` to discard meaningful failures. Keep cancellation distinct from ordinary failure.
- Keep diagnostics useful without putting user-facing error wording into domain types or logging private recording content.

## Concurrency visible in the file

Place `@MainActor` or actor isolation on the declaration that owns the state so readers can see the boundary. Keep `async` and `throws` on the operation that performs asynchronous or fallible work; do not hide it behind a fire-and-forget helper.

Every long-running task must have a visible owner and a defined cancellation/lifetime policy. Keep task handles near the state they control when handles are needed. At each `await` that separates validation from mutation, consider whether actor reentrancy could invalidate the assumptions. Capture only what a closure needs; use weak captures when lifetime semantics require them, rather than mechanically adding `[weak self]` everywhere.

Do not add `Task.detached`, `@unchecked Sendable`, blocking waits, or main-queue dispatch to work around unclear isolation. Follow the project's [concurrency requirements](SOFTWARE_ARCHITECTURE_GUIDELINES.md).

## SwiftUI readability

Keep `body` focused on the visible hierarchy. Extract a named view or private view property when it identifies a meaningful region, simplifies conditional rendering, or has its own inputs and interactions. Do not fragment a short hierarchy into one-line helpers for every control.

Keep modifier chains beside the view they modify. Modifier order can change layout and behavior; do not reorder modifiers merely to alphabetize them. Keep event closures short and route nontrivial actions through the ViewModel or application boundary. Use `@State` for local presentation state and `@MainActor @Observable` models for nontrivial presentation behavior, as required by the architecture.

## Comments and documentation

Write comments and identifiers in English, consistent with the existing source. Comments should explain a constraint, invariant, workaround, or decision that the code alone does not reveal. Do not narrate obvious statements or leave comments that contradict the implementation.

Use `///` for non-obvious type and API contracts. Document units, side effects, errors, isolation, or cancellation semantics when callers need that information. Avoid boilerplate documentation for every private helper. Give TODOs a specific missing behavior and an issue reference when one exists; do not leave vague reminders or speculative plans in source files.

## Tests and final file review

Name tests after observable behavior. Arrange inputs, perform the operation, and assert results in a clear reading order; blank lines are usually enough without repetitive section comments. Prefer deterministic values and parameterized cases for the same behavior over elaborate test helpers.

Before finishing a Swift change, check:

- The file has one understandable purpose and the main flow is easy to find.
- Names explain intent, units, and state without requiring implementation details.
- Visibility, mutation, dependencies, and concurrency ownership are explicit.
- Conditions, failure paths, and cancellation behavior are readable.
- Helpers and comments add meaning rather than navigation overhead.
- Formatting and lint pass, relevant tests cover behavior, and the change respects the architecture.

Apply these rules to touched code without unrelated style rewrites. If a technical constraint requires an exception, document the reason and keep it local.
