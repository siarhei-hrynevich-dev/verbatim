# Architecture

## Implemented foundation

Recorder is a macOS 15+, arm64, Swift 6 application with a SwiftUI App lifecycle, visible Dock icon, and a minimal placeholder window. The app target links WhisperKit and SQLiteVecStore but does not instantiate either. Recording is a Codable, Sendable metadata value with an identifier, creation date, nonblank title, finite nonnegative duration, and processing status. Tests cover validation, status serialization, and package imports. Persistence decoding will need to validate untrusted stored data; synthesized Codable currently provides round trips only.

No capture engine, permission prompts, production database, models, workers, repositories, player, or designed feature UI exists yet. Everything below describes intended future behavior.

## Feature and service boundaries (planned)

Organize presentation under `Features/Recording`, `Features/Library`, `Features/Player`, and `Features/Settings` as each feature is built. Keep composition and lifecycle integration in App, domain values in Models, and truly reused views/extensions in Shared. Avoid empty placeholder files and speculative abstractions.

Services will own these responsibilities:

| Service | Responsibility |
| --- | --- |
| CaptureService | ScreenCaptureKit session, screen/window/system audio and microphone capture, media finalization |
| TranscriptionService | On-demand offline WhisperKit processing and timestamped transcript segments |
| EmbeddingService | On-demand Core ML inference, model load/unload, replaceable embedding implementation |
| PersistenceService | SQLite metadata, file references, transcript segments, FTS5 and sqlite-vec indexes |
| ProcessingCoordinator | Durable sequential jobs, resource arbitration, cancellation, retries and recovery |

Introduce protocols when an actual substitution or testing need appears. Native frameworks come from the SDK; import ScreenCaptureKit, AVFoundation, AVKit, CoreMedia, CoreAudio, CoreML, Accelerate, and AppKit only where required.

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

Keep SwiftUI App lifecycle and a regular Dock application. Add an AppKit delegate only where native integration requires it. Dock activation should reopen the recording window; a later Dock menu may offer New Recording, Open Recorder, and Recordings Library. Recording indicators, recording continuation with closed windows, and optional Menu Bar controls belong to later work. No LSUIElement agent mode or custom Dock UI is configured.

## Sandbox and contextual permissions

App Sandbox is enabled. Audio-input and user-selected read/write entitlements prepare for microphone and folder access; the microphone usage description is present. These entitlements do not grant Screen Recording authorization. Screen and system audio capture authorization must be handled through macOS capture APIs. Microphone authorization is separate. Request each permission when the corresponding feature is used, never all at startup. Persist folder access with security-scoped bookmarks, balance access start/stop, and handle stale bookmarks and denied or revoked permissions. Do not disable the sandbox to bypass permissions. A signed app will be needed to validate sandbox/TCC behavior when capture is implemented; unsigned build verification does not validate permissions.
