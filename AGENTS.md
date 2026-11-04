# Coding instructions

- Target native macOS 15+ on Apple Silicon, Swift 6 with complete strict concurrency.
- Preserve standard macOS window, Dock, menu, keyboard, and accessibility conventions.
- Use SwiftUI presentation, @Observable UI state isolated with @MainActor, and @State for local view state. Keep business logic outside views.
- Prefer async/await and structured tasks; actors own mutable service state. Respect cancellation and Sendable boundaries. Do not default to DispatchQueue.main.async or use @unchecked Sendable without a documented necessity.
- Organize real code by feature under Features, services under Services, domain values under Models, and genuinely reused code under Shared. Add directories only as needed; include files in the correct Xcode target.
- Propagate actionable errors. Never silently discard failures. Avoid forced unwraps and force-try unless an invariant is justified in a nearby comment.
- Avoid unnecessary dependencies, fake service methods, premature protocols and abstractions.
- Never load WhisperKit or embedding models, run vector indexing, or start heavy processing while recording. Models load only on demand for post-processing. Do not introduce automatic model downloads at startup.
- Keep App Sandbox enabled and permissions contextual. Do not commit signing team identifiers, secrets, runtime databases, recordings, transcripts, or model weights.
- Manage dependencies through Xcode SwiftPM references and commit Package.resolved. Link only the needed library products.
- Use Swift Testing for meaningful domain and integration smoke tests. Tests must work without models, network, capture permissions, microphones, or personal files.
- Run `make format` and `make lint` for changes; `make check` runs format-check, lint, Xcode build, and tests. Run `make setup` for prerequisites and package resolution.
- Validate the native application with xcodebuild, never only swift build. Report failures and environment blockers accurately. Do not claim a successful launch without checking it.
- Read Docs/ARCHITECTURE.md before adding capture or processing behavior. Keep planned and implemented behavior distinct in documentation.
