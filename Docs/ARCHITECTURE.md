# Architecture

## Architectural policy

Follow [Software Architecture Guidelines](SOFTWARE_ARCHITECTURE_GUIDELINES.md): Lightweight Clean Architecture with MVVM for presentation. Those guidelines define dependency rules, responsibilities, dependency injection, state ownership, concurrency, errors, tests, and the agent workflow. This document applies them to Recorder as the target architecture; the implemented state is tracked separately in [Implementation Status](IMPLEMENTATION.md).

Presentation depends on Application and Domain; Application depends on Domain. Infrastructure implements core-owned contracts. Domain has no dependencies on the other layers, and Application must not depend on concrete infrastructure. App is the composition root that wires implementations through initializer injection. These are logical boundaries in one app target, not a requirement for additional modules, protocols for every type, or a DI framework.

## Current state

What exists in the code today (windows, simulated state, App integration, models, tests) is described in [Implementation Status](IMPLEMENTATION.md). This document describes the target architecture; sections marked "planned" are intended future behavior, not current behavior.

## Feature and service boundaries (planned)

Organize presentation under `Features/Recording`, `Features/Library`, `Features/Player`, and `Features/Settings` as each feature is built. Use layer-based `Application`, `Domain`, and `Infrastructure` directories for the core and adapters. Keep composition and lifecycle integration in App and truly reused views/extensions in Shared. Avoid empty placeholder files and speculative abstractions.

The current `Recorder/Models` types (`Recording`, capture source vocabulary) belong logically to Domain; their location remains valid for the scaffold. When capture is implemented, `RecorderViewModel` should receive capture, permission and storage state through injected Application services instead of `RecorderPreviewData`. Move relevant files when real feature work makes it useful, updating Xcode target membership; no immediate restructuring is required. New workflow code belongs in Application and framework adapters in Infrastructure rather than a generic Services directory. Application-wide dependencies are created in App and injected explicitly.

Use `@MainActor @Observable` ViewModels for nontrivial presentation state and asynchronous application actions. Simple views can receive values and callbacks directly. Views and ViewModels must not instantiate infrastructure or own workflows that must survive window closure.

Services will own these responsibilities:

| Component | Responsibility |
| --- | --- |
| CaptureService | Infrastructure adapter: ScreenCaptureKit session, screen/window/system audio and microphone capture, media finalization |
| TranscriptionService | Infrastructure adapter: on-demand offline WhisperKit processing and timestamped transcript segments |
| EmbeddingService | Infrastructure adapter: on-demand Core ML inference, model load/unload, replaceable embedding implementation |
| PersistenceService | Infrastructure implementation: SQLite metadata, file references, transcript segments, FTS5 and sqlite-vec indexes |
| ProcessingCoordinator | Application workflow: durable sequential jobs, resource arbitration, cancellation, retries and recovery through core contracts |

Application services orchestrate capture and processing through meaningful contracts owned by Application or Domain; infrastructure implements those contracts and keeps framework-specific types inside adapters. Domain owns business validation and state transition rules. Introduce protocols when an actual architectural boundary, substitution, or testing need appears. Native frameworks come from the SDK; import ScreenCaptureKit, AVFoundation, AVKit, CoreMedia, CoreAudio, CoreML, Accelerate, and AppKit only where required.

## Recording and processing lifecycles (planned)

Recording performance takes priority. Before capture starts, cancel or suspend heavy post-processing and release AI model resources. During active recording, WhisperKit and embedding models must remain unloaded; vector indexing and heavy background jobs must not start. Resource arbitration belongs in the coordinator, with an explicit state transition that prevents races between recording and processing.

After recording stops:

1. Finalize and close the media file successfully.
2. Persist recording metadata and a durable processing job.
3. Load WhisperKit on demand and transcribe.
4. Persist timestamped transcript segments.
5. Unload transcription resources, load the embedding model, and generate embeddings.
6. Update the vector index and full-text index transactionally.
7. Mark the recording ready and release model resources.

Checkpoints and idempotent stage writes must make interrupted jobs resumable or safely retryable. A failed or cancelled job must preserve the original media and expose actionable errors. Recover unfinished work on a later launch; a window closing must not cancel active recording.

## Storage and models (planned)

Use the sandbox Application Support directory for SQLite metadata and durable jobs, with SQLiteVecStore providing sqlite-vec and FTS5. Store media separately and reference it by stable identifiers/URLs; use security-scoped bookmarks for user-selected folders outside the container. Coordinate schema migrations, transactions, and filesystem failure recovery before production persistence is introduced. No database is initialized in this scaffold.

The intended initial embedding model is multilingual-e5-small, likely converted to Core ML. Download or install one model only when the feature is explicitly used; no weights are bundled at initialization. Load on demand after capture ends, unload when idle or recording starts, and isolate inference behind an implementation that can later be replaced. Persist model identity, version, dimensions, and normalization policy with the index so a replacement triggers a safe reindex. WhisperKit likewise runs exclusively in post-processing and never initializes at startup.

## Concurrency and SwiftUI (planned)

Use async/await, structured tasks and task groups where appropriate. Actors own isolated mutable capture, persistence, and processing state. Keep cross-isolation values Sendable. Propagate cancellation and typed errors; do not silence Swift 6 diagnostics with unchecked Sendable. UI-bound observable state uses `@MainActor` and `@Observable`; views use `@State` for local state and focus on presentation and interaction. Do not put business logic in views or use main-queue dispatch as the standard UI update mechanism.

## Lifecycle and native interaction (planned)

Keep SwiftUI App lifecycle and a regular Dock application. Add an AppKit delegate only where native integration requires it. Dock activation reopens the Recorder window; the Dock menu, menu bar item and quit confirmation should be driven by real recording state once capture exists. Recording must continue with closed windows, which depends on real capture and belongs to later work. Do not introduce LSUIElement agent mode or custom Dock UI.

## Sandbox and contextual permissions

App Sandbox is enabled. Audio-input and user-selected read/write entitlements prepare for microphone and folder access; the microphone usage description is present. These entitlements do not grant Screen Recording authorization. Screen and system audio capture authorization must be handled through macOS capture APIs. Microphone authorization is separate. Request each permission when the corresponding feature is used, never all at startup. Persist folder access with security-scoped bookmarks, balance access start/stop, and handle stale bookmarks and denied or revoked permissions. Do not disable the sandbox to bypass permissions. A signed app will be needed to validate sandbox/TCC behavior when capture is implemented; unsigned build verification does not validate permissions.
