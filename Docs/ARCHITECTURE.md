# Architecture

## Architectural policy

Follow [Software Architecture Guidelines](SOFTWARE_ARCHITECTURE_GUIDELINES.md): Lightweight Clean Architecture with MVVM for presentation. Those guidelines define dependency rules, responsibilities, dependency injection, state ownership, concurrency, errors, tests, and the agent workflow. This document applies them to Recorder as the target architecture; the implemented state is tracked separately in [Implementation Status](IMPLEMENTATION.md).

Presentation depends on Application and Domain; Application depends on Domain. Infrastructure implements core-owned contracts. Domain has no dependencies on the other layers, and Application must not depend on concrete infrastructure. App is the composition root that wires implementations through initializer injection. These are logical boundaries in one app target, not a requirement for additional modules, protocols for every type, or a DI framework.

## Current state

What exists in the code today (recording, windows, simulated state, App integration, models, tests) is described in [Implementation Status](IMPLEMENTATION.md). This document describes the target architecture; sections marked "planned" are intended future behavior, not current behavior. Recording capture, its lifecycle, media finalization, the recording library's SQLite persistence, media playback, speech model management and offline transcription are implemented; embeddings and vector indexes are not.

## Feature and service boundaries (planned)

Organize presentation under `Features/Recording`, `Features/Library`, `Features/Viewer` (the player, named after its design section), and `Features/Settings` as each feature is built. Use layer-based `Application`, `Domain`, and `Infrastructure` directories for the core and adapters. Keep composition and lifecycle integration in App and truly reused views/extensions in Shared. Avoid empty placeholder files and speculative abstractions.

The `Recorder/Models` types belong logically to Domain; that location remains valid. `RecorderViewModel` receives capture, permission and storage state through injected Application contracts. Move relevant files when real feature work makes it useful, updating Xcode target membership; no immediate restructuring is required. New workflow code belongs in Application and framework adapters in Infrastructure rather than a generic Services directory. Application-wide dependencies are created in App and injected explicitly.

Use `@MainActor @Observable` ViewModels for nontrivial presentation state and asynchronous application actions. Simple views can receive values and callbacks directly. Views and ViewModels must not instantiate infrastructure or own workflows that must survive window closure.

Services will own these responsibilities:

| Component | Responsibility |
| --- | --- |
| RecordingCoordinator | Application workflow (implemented): the recording lifecycle and the single source of truth for an active recording |
| Capture (`ScreenCaptureEngine`, `CaptureSourceDiscovery`) | Infrastructure adapters (implemented): source discovery, ScreenCaptureKit and microphone capture, media finalization |
| LibraryService | Application service (implemented): library use cases, and the rules connecting database entries to files; its `revision` tells the Library window to reload |
| RecordingRepository | Application contract (implemented by `SQLiteRecordingRepository`): the `recordings` table |
| RecordingFileStore | Application contract (implemented by `LocalRecordingFileStore`): file availability, bookmarks, Finder, the Trash |
| RecordingMetadataStore | Application contract (implemented by `FileRecordingStore`): the `recording.json` sidecar, a snapshot taken when a recording finishes |
| PlaybackService | Application contract (implemented by `AVPlaybackService`): one media file at a time, its timeline, and what happens to it. Knows nothing about recordings or transcripts |
| ModelManager | Application service (implemented): the single owner of speech model state. Lists models, coordinates installs, selects a model, removes models and hands the model's location to transcription |
| SpeechModelProviding | Application contract (implemented by `WhisperModelProvider`): model files and their source, with WhisperKit types kept inside the adapter |
| ModelRegistryStore | Application contract (implemented by `JSONModelRegistryStore`): what was installed, for comparing with the disk |
| SettingsRepository | Application contract (implemented by `UserDefaultsSettingsRepository`): app preferences and the selected model |
| AppPreferences | Application state (implemented): the owner of app behavior preferences, observed by Settings, the menu bar item and the app delegate |
| TranscriptionService | Application contract (implemented by `WhisperTranscriptionService`): on-demand offline recognition of local media. Takes an already resolved model; knows nothing about jobs or storage |
| TranscriptRepository, ProcessingJobRepository | Application contracts (implemented by `SQLiteTranscriptRepository`): finished transcripts and the durable job queue |
| TranscriptFileStore | Application contract (implemented by `FileTranscriptStore`): the transcript files beside a recording's media |
| EmbeddingService | Infrastructure adapter: on-demand Core ML inference, model load/unload, replaceable embedding implementation |
| PersistenceService | Infrastructure implementation: FTS5 and sqlite-vec indexes, in the application database or beside it |
| ProcessingCoordinator | Application workflow (implemented): the single owner of transcription jobs: durable sequential queue, recording priority, cancellation, retries and recovery |

Application services orchestrate capture and processing through meaningful contracts owned by Application or Domain; infrastructure implements those contracts and keeps framework-specific types inside adapters. Domain owns business validation and state transition rules. Introduce protocols when an actual architectural boundary, substitution, or testing need appears. Native frameworks come from the SDK; import ScreenCaptureKit, AVFoundation, AVKit, CoreMedia, CoreAudio, CoreML, Accelerate, and AppKit only where required.

## Playback

`ViewerViewModel` owns one playback session: from opening a recording by its identifier until the next one opens, the window closes or playback fails. It reads metadata and opens the media through `LibraryService`, which stays the only owner of both, and plays through `PlaybackService`, which keeps `AVPlayer` inside Infrastructure. `PlaybackState` in Domain states which transitions exist. App injects the one view tied to the concrete player, `AVPlayerSurface`, so that Presentation has no AVFoundation dependency.

The contract's callback and `AVPlayer` are main-actor bound because the player drives on-screen rendering. A transcript needs nothing further from the engine: `PlaybackEvent.timeChanged`, `currentTime` and `seek(to:precision:)` are its timeline, and the engine stays independent of WhisperKit and transcript storage. `position` changes many times a second, so the transcript panel reads `activeLineIndex` instead, a binary search over the lines written only when the active line changes.

## Speech models

`ModelManager` is created in App and outlives every window, so a download continues with Settings closed. `ModelSettingsViewModel` only maps its state and forwards actions. `ModelFileWorkflow` holds the stateless steps; `ModelManager` keeps all state and runs on the main actor, while the work happens off it in `WhisperModelProvider`. **No code here creates a `WhisperKit` instance**: it uses only static APIs and the Hub client, so managing models never compiles or loads one.

`ModelInstallState` in Domain states which transitions exist: `notInstalled → downloading → verifying → installed`, with `waitingForRecording` while a recording holds an install back, `failed` for anything that needs the user, and `removing`. A state change happens on the main actor before any suspension, so a duplicate request is rejected by state. Starting a download is never treated as installing: only verified files reach `installed`.

The disk is the authority. `model-registry.json` beside the models states what was installed, and every launch compares it with the files. Paths to delete are derived from a validated catalog identifier, never read from that file.

The **recording priority policy** is `RecordingPriorityPolicy`: from when a recording starts preparing until its media is safe, running installs stop, keeping their partial files, new ones wait, and no catalog refresh starts. They continue by themselves afterwards.

### Integration contract for TranscriptionService

```swift
let lease = try modelManager.acquireSelectedModel()   // Throws .noModelSelected or .selectedModelUnavailable(id)
defer { modelManager.release(lease) }                // Until then, the model cannot be removed
let config = WhisperKitConfig(
    modelFolder: lease.model.modelFolder.path(percentEncoded: false),
    tokenizerFolder: lease.model.tokenizerBase,
    download: false
)
```

Report a thrown error to the user instead of choosing another model: nothing switches or downloads on its own. The one automatic selection is the first model installed, when none is selected and no other model is installed. Resolving loads nothing. Load only for post-processing, never while recording; `ModelManager.isRecordingActive` reflects that. A file that imports both WhisperKit and `@testable Recorder` must write `Recorder.ModelManager`, because WhisperKit re-exports a type of the same name from ArgmaxCore; inside the app module the app's own wins. Embedding models will be a separate catalog when they exist; nothing generic was added for them in advance.

## Transcription

`ProcessingCoordinator` is created in App and outlives every window. It runs on the main actor and changes state before any suspension, so a duplicate request is rejected by state; inference runs off the main actor in `WhisperTranscriptionService`, an actor. `TranscriptionJob.State` in Domain states which transitions exist: `pending → preparing → transcribing → saving → completed`, with `failed` and `cancelled`, and running jobs can return to `pending`. There is one job per recording, so retrying and re-transcribing reuse it.

A job's steps are: check the model against the disk through `ModelManager` and take a lease, open the media through `LibraryService`, check disk space, recognize, assemble the result with `Transcript.assembled`, store it in one transaction, write the files, and only then complete. Nothing before the transaction changes anything, which is what makes stopping and restarting safe at any point.

**Why not `transcribe(audioPath:)`.** It reads through `AVAudioFile`, which sees one track of a QuickTime file and assumes audio is contiguous from zero. `RecordingAudioReader` instead decodes each track with `AVAssetReader` to 16 kHz mono, positioned by presentation time, and `SpeechChunker` applies the same rules as WhisperKit's incremental loading, with its public `VADAudioChunker`, before calling `transcribe(audioArray:)` for each chunk. This keeps memory bounded as incremental loading would, and writes no intermediate files. This is a deliberate deviation from preferring WhisperKit's incremental API, which is `AVAudioFile`-only.

**Timeline.** Times are on the file's own timeline, which is the one `AVPlayer` plays. A track starting late is stored with an empty edit and decodes as silence from time 0. Chunks of digital silence are skipped and leading silence trimmed, because Whisper tends to begin its first segment at the start of what it is given, and word timestamps are on for the same reason. Tracks are transcribed independently and merged by `Transcript.assembled`. Tracks are told apart by the names the Recorder gives them; a file without those names is transcribed as one mix, labeled Unknown.

**Recognition quality.** Decoding uses WhisperKit's temperature fallback with explicit thresholds, so a window that fails them is decoded again at a higher temperature instead of keeping repeated or invented text; segments with a high no-speech probability and a low average log probability, and known subtitle credits ("Субтитры создавал…"), are dropped afterwards. Chunks without sustained sound are not run at all (`SpeechChunk.isSilent`: fewer than a few tenths of a second of 50 ms windows above -50 dBFS RMS), because an idle microphone's hum and clicks make Whisper write words such as "Thank you." with high confidence, which no probability threshold catches. With automatic language, it is detected once per track from its first three stretches of speech (averaged probabilities) and then fixed, because a short chunk detected alone is easily taken for another language. **Tried and removed:** giving each chunk the end of the previous chunk's text as `promptTokens`. On a real recording with background music it dropped whole phrases and stretched segments over the next ones, which broke alignment with the audio.

**Recording priority.** `RecordingPriorityPolicy` calls `setRecordingActive`, which stops the running job and holds the queue from when a recording starts preparing until its media is safe. It never waits for inference, so capture cannot be delayed by it. The job returns to `pending`, the model is released as soon as inference returns, and the job restarts from the beginning when the recording ends. Task cancellation is checked between chunks and windows, and the decoder's callback ends its token loop early, but a running Core ML prediction or model load cannot be interrupted: until it returns, inference and capture can overlap briefly. Loading can take minutes the first time Core ML compiles a model.

**Recovery.** A job found running at launch restarts from the beginning; chunk-level resume is not attempted. A failed or cancelled job leaves the media and any earlier transcript untouched.

**Test host.** Unit tests run inside `Recorder.app`, which runs `AppDelegate`. Anything that touches user data at launch must stay out of tests, as `processing.start()` does through `isHostingTests`.

## Embedding lifecycle (planned)

During active recording, embedding models must remain unloaded, and vector indexing must not start. After a transcript is stored: unload transcription resources, load the embedding model, generate embeddings, update the vector and full-text indexes transactionally, and release model resources.

## Storage and models (planned)

Recording metadata is implemented: the sandbox Application Support directory holds `Verbatim/Library.sqlite`, opened through the system `SQLite3` with versioned migrations (`LibrarySchema`). **Deviation:** app tables do not go through SQLiteVecStore, whose `VectorStore` freezes an embedding dimension into the file at creation, before any embedding model is chosen, and offers no migrations for app tables. SQLiteVecStore remains planned for sqlite-vec and FTS5, and its tables can share this file or sit beside it. New tables should be added as new migrations and refer to `recordings.id`. Transcripts and jobs do so without a foreign key, because removing a recording can be undone and must bring its transcript back; `purgeOrphans` clears them at the next launch, and deleting to the Trash clears them at once. Repositories hold separate connections to the file, opened one at a time. Media is stored separately and referenced by stable identifier, path and security-scoped bookmark.

The intended initial embedding model is multilingual-e5-small, likely converted to Core ML. Speech models are handled as described under [Speech models](#speech-models), and embedding models will follow the same rule: download or install one model only when the feature is explicitly used, with no weights bundled. Load on demand after capture ends, unload when idle or recording starts, and isolate inference behind an implementation that can later be replaced. Persist model identity, version, dimensions, and normalization policy with the index so a replacement triggers a safe reindex. WhisperKit likewise runs exclusively in post-processing and never initializes at startup.

## Concurrency and SwiftUI (planned)

Use async/await, structured tasks and task groups where appropriate. Actors own isolated mutable capture, persistence, and processing state. Keep cross-isolation values Sendable. Propagate cancellation and typed errors; do not silence Swift 6 diagnostics with unchecked Sendable. UI-bound observable state uses `@MainActor` and `@Observable`; views use `@State` for local state and focus on presentation and interaction. Do not put business logic in views or use main-queue dispatch as the standard UI update mechanism.

## Lifecycle and native interaction (planned)

Keep SwiftUI App lifecycle and a regular Dock application. Add an AppKit delegate only where native integration requires it. Dock activation reopens the Recorder window, or the Library if the user chose that in Settings, except during a recording; the Dock menu, menu bar item and quit confirmation are driven by the real recording state, and recording continues with closed windows. The Viewer's scene has the `principal` window manager role, because auxiliary windows cannot enter full screen. Do not introduce LSUIElement agent mode or custom Dock UI.

## Sandbox and contextual permissions

App Sandbox is enabled. Audio-input, Movies folder, user-selected read/write and app-scoped bookmark entitlements cover the microphone and recording folders; the microphone usage description is present. The outgoing network entitlement exists for downloading models from the Hugging Face Hub, and only when the user asks. These entitlements do not grant Screen Recording authorization. Screen and system audio capture authorization must be handled through macOS capture APIs. Microphone authorization is separate. Request each permission when the corresponding feature is used, never all at startup. Persist folder access with security-scoped bookmarks, balance access start/stop, and handle stale bookmarks and denied or revoked permissions. Do not disable the sandbox to bypass permissions. A signed app is needed to validate sandbox/TCC behavior; unsigned build verification does not validate permissions.
