# Coding instructions

## Required reading before writing code

Before creating or changing code, read:

1. [Development](Docs/DEVELOPMENT.md) for setup, toolchain, commands, dependencies, project organization and end-to-end tests, and [README.md](README.md) for the product overview.
2. [Software Architecture Guidelines](Docs/SOFTWARE_ARCHITECTURE_GUIDELINES.md) for the required Lightweight Clean Architecture and MVVM rules.
3. [Project Architecture](Docs/ARCHITECTURE.md) for project-specific boundaries, recording constraints, model lifecycle, and permissions, and [Implementation Status](Docs/IMPLEMENTATION.md) for what is actually built.
4. [Swift Code Style](Docs/CODE_STYLE.md) for file organization, naming, readable control flow, comments, and formatting conventions.
5. Existing code, tests, and any documentation relevant to the requested change.

Do this before the first code edit in each task, including fixes and refactors. Do not rely only on remembered rules. If a required document is missing, inspect the available project documentation and report the gap before implementing behavior that depends on it.

Before implementation, identify the owning layer and existing component, dependency direction, state owner, concurrency isolation, error/cancellation behavior, and appropriate tests. Introduce interfaces only at meaningful boundaries. Keep application-wide composition in App; never construct infrastructure in views or ViewModels.

After code changes, run formatting, linting, the Xcode build, and relevant tests (`make check` for the complete configured checks). Review architectural boundaries, update affected documentation, and report any justified deviations. For documentation-only changes, verify links, consistency, and the diff; application builds are not required.

The guidelines define general architecture policy; ARCHITECTURE.md describes its application here. Keep them consistent. User instructions take precedence; document necessary technical deviations rather than silently bypassing rules.

## Implementation rules

- Target native macOS 15+ on Apple Silicon, Swift 6 with complete strict concurrency.
- Preserve standard macOS window, Dock, menu, keyboard, and accessibility conventions.
- Use SwiftUI presentation, @Observable UI state isolated with @MainActor, and @State for local view state. Keep business logic outside views.
- Prefer async/await and structured tasks; actors own mutable service state. Respect cancellation and Sendable boundaries. Do not default to DispatchQueue.main.async or use @unchecked Sendable without a documented necessity.
- Use feature-based Presentation under Features and layer-based Application, Domain, and Infrastructure. App owns the composition root; Shared contains genuinely reused code. Verbatim/Models is the existing Domain location; migrate affected files deliberately when needed, without unrelated refactors. Add directories only for real code and include files in the correct Xcode target.
- Propagate actionable errors. Never silently discard failures. Avoid forced unwraps and force-try unless an invariant is justified in a nearby comment.
- Avoid unnecessary dependencies, fake service methods, premature protocols and abstractions.
- Never load WhisperKit or embedding models, run vector indexing, or start heavy processing while recording. Models load only on demand for post-processing. Do not introduce automatic model downloads at startup.
- Keep App Sandbox enabled and permissions contextual. Do not commit signing team identifiers, secrets, runtime databases, recordings, transcripts, or model weights.
- Manage dependencies through Xcode SwiftPM references and commit Package.resolved. Link only the needed library products.
- Use Swift Testing for meaningful domain and integration smoke tests. Tests must work without models, network, capture permissions, microphones, or personal files.
- Run `make format` and `make lint` for changes; `make check` runs format-check, lint, Xcode build, and tests. Run `make setup` for prerequisites and package resolution.
- Validate the native application with xcodebuild, never only swift build. Report failures and environment blockers accurately. Do not claim a successful launch without checking it.
- Keep planned and implemented behavior distinct in documentation. Preserve inward dependencies: Presentation → Application/Domain, Application → Domain, Infrastructure → core contracts. Domain must not depend on UI, capture, ML, or SQLite frameworks.
