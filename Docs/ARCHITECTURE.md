# Architecture

## Architectural policy

Follow [Software Architecture Guidelines](SOFTWARE_ARCHITECTURE_GUIDELINES.md): Lightweight Clean Architecture with MVVM for presentation. Those guidelines define dependency rules, responsibilities, dependency injection, state ownership, concurrency, errors, tests, and the agent workflow. This document applies them to Recorder as the target architecture; the implemented state is tracked separately in [Implementation Status](IMPLEMENTATION.md).

Presentation depends on Application and Domain; Application depends on Domain. Infrastructure implements core-owned contracts. Domain has no dependencies on the other layers, and Application must not depend on concrete infrastructure. App is the composition root that wires implementations through initializer injection. These are logical boundaries in one app target, not a requirement for additional modules, protocols for every type, or a DI framework.

## Current state

What exists in the code today (recording, windows, simulated state, App integration, models, tests) is described in [Implementation Status](IMPLEMENTATION.md). This document describes the target architecture; sections marked "planned" are intended future behavior, not current behavior. Recording capture, its lifecycle, media finalization, the recording library's SQLite persistence, media playback, speech, language and embedding model management, offline transcription, summaries, the search index and the MCP server that offers it to AI agents are implemented.

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
| ModelManager | Application service (implemented), generic over `InstallableModel`: the single owner of one kind of model's state. One instance for speech models, one for language models. Lists models, coordinates installs, selects a model, removes models and hands the model's location to its engine |
| ModelFileProviding | Application contract (implemented by `WhisperModelProvider` and `HubLanguageModelProvider`): one kind of model's files and their source, with framework types kept inside the adapter |
| ModelRegistryStore | Application contract (implemented by `JSONModelRegistryStore`): what was installed, for comparing with the disk |
| SettingsRepository, SummarySettingsRepository | Application contracts (implemented in UserDefaults): app preferences and the selected speech model; the selected language model and the summary settings customized per model |
| AppPreferences | Application state (implemented): the owner of app behavior preferences, observed by Settings, the menu bar item and the app delegate |
| TranscriptionService | Application contract (implemented by `WhisperTranscriptionService`): on-demand offline recognition of local media. Takes an already resolved model; knows nothing about jobs or storage |
| TranscriptRepository, ProcessingJobRepository | Application contracts (implemented by `SQLiteTranscriptRepository`): finished transcripts and the durable job queue |
| TranscriptFileStore | Application contract (implemented by `FileTranscriptStore`): the transcript files beside a recording's media |
| IndexingCoordinator | Application workflow (implemented): the single owner of indexing jobs: in-memory sequential queue after transcription and summaries, recording priority, catching up when the model changes |
| RecordingSearchService | Application service (implemented): hybrid search by meaning and words |
| RecordingKnowledgeService | Application service (implemented): what AI agents can read about recordings: listing, search with tag filters, details, summaries, transcript excerpts, tags. Read-only; the entry point for the MCP server |
| AgentServerController | Application state (implemented): the single owner of the MCP server's settings (on/off, port, token) and of whether it runs |
| AgentServerHosting | Application contract (implemented by `MCPHTTPServer`): listening on the loopback interface with a token |
| TextEmbedder, EmbeddingProvider | Application contracts: the boundary to swap embedding backends. `LocalEmbeddingProvider` leases an installed model, shares one loaded copy and loads it through `LocalEmbeddingRuntime` (implemented by `MLXEmbeddingRuntime`) |
| SearchIndexRepository | Application contract (implemented by `SQLiteSearchIndexRepository`): chunks, their FTS5 index and their vectors |
| ProcessingCoordinator | Application workflow (implemented): the single owner of transcription jobs: durable sequential queue, recording priority, cancellation, retries and recovery |
| SummaryCoordinator | Application workflow (implemented): the single owner of summary jobs: in-memory sequential queue, recording priority, waiting for transcription, cancellation |
| TranscriptSummarizer | Application logic (implemented): batching a transcript, notes on each batch, combining them; depends only on `TextGenerator` |
| TextGenerator, TextGenerationProvider | Application contracts: the boundary to swap language model backends. `LocalTextGenerationProvider` leases an installed model and loads it through `LocalTextGenerationRuntime` (implemented by `MLXTextGenerationRuntime`) |
| SummaryRepository | Application contract (implemented by `SQLiteSummaryRepository`): summaries and their parts |

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

Report a thrown error to the user instead of choosing another model: nothing switches or downloads on its own. The one automatic selection is the first model installed, when none is selected and no other model is installed. Resolving loads nothing. Load only for post-processing, never while recording; `ModelManager.isRecordingActive` reflects that. A file that imports both WhisperKit and `@testable Recorder` must write `Recorder.ModelManager`, because WhisperKit re-exports a type of the same name from ArgmaxCore; inside the app module the app's own wins.

**One lifecycle, several catalogs.** `ModelManager<Model: InstallableModel>` runs the lifecycle above for any kind of model; `SpeechModelManager` and `LanguageModelManager` are its two instances, each with its own catalog, provider, storage folder, registry file and selection store (`ModelSelectionStore`). What differs between kinds is behind the model type (`Resolved`, `sharedFilesKey` for files such as a shared tokenizer, the recommendation) and the provider. `EmbeddingModelManager` is the third instance.

## Summaries

**Language models.** `LanguageModelCatalog` lists MLX conversions on the Hugging Face Hub, each pinned to a commit, with the memory it needs, the context it is asked to use and its preset `SummarySettings`. `HubLanguageModelProvider` downloads them itself rather than through MLX's downloader, so the rules above hold: only on request, paused while recording, verified against the repository's SHA-256 hashes, recorded in `LanguageModels/model-registry.json`. `HubFileDownloader` writes each file as it arrives into `<file>.incomplete` and continues it with an HTTP range request, so progress is measured on disk and a paused multi-gigabyte file is not started over. Loading is from the model's folder alone (`LLMModelFactory.loadContainer(from:using:)` with a swift-transformers tokenizer read from that folder), so it cannot reach the network. A model whose memory need exceeds the Mac's is shown as not supported.

**Swapping the backend.** Summarization depends on `TextGenerator` (count tokens, generate a reply to messages with `TextGenerationParameters`) and gets one from a `TextGenerationProvider` per job. `LocalTextGenerationProvider` takes a lease from `LanguageModelManager` and loads the model through `MLXTextGenerationRuntime`, the only file importing MLX. A local server (an OpenAI-compatible endpoint) or a provider's API would be another `TextGenerator` and provider, with nothing to install; the summarizer, coordinator, storage and Viewer would not change.

**Batching.** `TranscriptSummarizer` turns segments into timestamped lines (labelled by source when there are several), counts their tokens with the model's tokenizer, and splits them into consecutive batches of `batchTokens` (`SummaryBatching`; a line over the budget gets a batch of its own). The model writes notes on each batch (map). The notes are combined into the summary (reduce); when together they exceed one batch, they are first condensed in groups, round after round, stopping if a round cannot group anything. Instructions are in English. Every stage is told to write only in the `SummaryLanguage` from Settings and to translate anything said in another language, because small models drift back to the language they read; the transcript's detected language plays no part, so recordings in any or several languages give summaries in one. `SummaryPreferences` owns the choice; until it is made it follows the Mac's preferred languages, falling back to English, and is not stored, so a change of the Mac's language still applies. The summary records the language it was written in, and the Viewer offers Summarize Again when that differs from the setting. Reasoning that a model writes anyway (`<think>`) is removed. The notes on each batch are stored as `SummaryPart`s with their time span and segment range: they are the units for later vector indexing.

**Jobs.** A new transcript is queued for a summary by itself when a language model is selected and installed; otherwise summaries are only asked for. `SummaryCoordinator` runs one summary at a time on the main actor, as `ProcessingCoordinator` does. A summary starts only while no transcription is queued or running (read under observation, so it starts by itself afterwards), so two models are not loaded for post-processing at once; a transcription asked for during a summary can still overlap it. `RecordingPriorityPolicy` stops it when a recording starts, without waiting, and it starts over afterwards; generation checks cancellation between tokens. The model is released after each summary. **Deviation:** summary jobs are kept in memory, not in the database: a summary is cheap to ask for again and leaves nothing half-done, so one interrupted by quitting is simply not resumed. The summary itself is stored in one transaction (migration 4: `summaries`, `summary_parts`), records the transcript's creation time so a newer transcript marks it out of date, and follows the recording's removal like a transcript does.

**Settings.** `SummaryPreferences` owns them: a model uses its preset until the user customizes it; customizing starts from the preset, edits are clamped to valid ranges and to the model's context, and resetting forgets the custom copy, so a better preset in a later version applies.

## Transcription

`ProcessingCoordinator` is created in App and outlives every window. It runs on the main actor and changes state before any suspension, so a duplicate request is rejected by state; inference runs off the main actor in `WhisperTranscriptionService`, an actor. `TranscriptionJob.State` in Domain states which transitions exist: `pending → preparing → transcribing → saving → completed`, with `failed` and `cancelled`, and running jobs can return to `pending`. There is one job per recording, so retrying and re-transcribing reuse it.

A job's steps are: check the model against the disk through `ModelManager` and take a lease, open the media through `LibraryService`, check disk space, recognize, assemble the result with `Transcript.assembled`, store it in one transaction, write the files, and only then complete. Nothing before the transaction changes anything, which is what makes stopping and restarting safe at any point.

**Why not `transcribe(audioPath:)`.** It reads through `AVAudioFile`, which sees one track of a QuickTime file and assumes audio is contiguous from zero. `RecordingAudioReader` instead decodes each track with `AVAssetReader` to 16 kHz mono, positioned by presentation time, and `SpeechChunker` applies the same rules as WhisperKit's incremental loading, with its public `VADAudioChunker`, before calling `transcribe(audioArray:)` for each chunk. This keeps memory bounded as incremental loading would, and writes no intermediate files. This is a deliberate deviation from preferring WhisperKit's incremental API, which is `AVAudioFile`-only.

**Timeline.** Times are on the file's own timeline, which is the one `AVPlayer` plays. A track starting late is stored with an empty edit and decodes as silence from time 0. Chunks of digital silence are skipped and leading silence trimmed, because Whisper tends to begin its first segment at the start of what it is given, and word timestamps are on for the same reason. Tracks are transcribed independently and merged by `Transcript.assembled`. Tracks are told apart by the names the Recorder gives them; a file without those names is transcribed as one mix, labeled Unknown.

**Recognition quality.** Decoding uses WhisperKit's temperature fallback with explicit thresholds, so a window that fails them is decoded again at a higher temperature instead of keeping repeated or invented text; segments with a high no-speech probability and a low average log probability, and known subtitle credits ("Субтитры создавал…"), are dropped afterwards. Chunks without sustained sound are not run at all (`SpeechChunk.isSilent`: fewer than a few tenths of a second of 50 ms windows above -50 dBFS RMS), because an idle microphone's hum and clicks make Whisper write words such as "Thank you." with high confidence, which no probability threshold catches. With automatic language, it is detected once per track from its first three stretches of speech and then fixed, because a short chunk detected alone is easily taken for another language. WhisperKit reports only the language it picked for a chunk, with that pick's log-probability, so each stretch votes for its language with the probability weighted by its length; adding the log-probabilities instead made the language picked by fewer stretches win, and Russian speech with English terms was then decoded as English, which Whisper does by translating. **Tried and removed:** giving each chunk the end of the previous chunk's text as `promptTokens`. On a real recording with background music it dropped whole phrases and stretched segments over the next ones, which broke alignment with the audio.

**Recording priority.** `RecordingPriorityPolicy` calls `setRecordingActive`, which stops the running job and holds the queue from when a recording starts preparing until its media is safe. It never waits for inference, so capture cannot be delayed by it. The job returns to `pending`, the model is released as soon as inference returns, and the job restarts from the beginning when the recording ends. Task cancellation is checked between chunks and windows, and the decoder's callback ends its token loop early, but a running Core ML prediction or model load cannot be interrupted: until it returns, inference and capture can overlap briefly. Loading can take minutes the first time Core ML compiles a model.

**Recovery.** A job found running at launch restarts from the beginning; chunk-level resume is not attempted. A failed or cancelled job leaves the media and any earlier transcript untouched.

**Test host.** Unit tests run inside `Recorder.app`, which runs `AppDelegate`. Anything that touches user data at launch must stay out of tests, as `processing.start()` does through `isHostingTests`.

## Search index

The goal is that an AI agent on this Mac can answer questions about recordings: find the moments that talk about something, in any language, then read the summary or the transcript around them. Everything runs and stays on this Mac.

**Pipeline.** Recording → transcription → summary → indexing, each step queued by the one before: `ProcessingCoordinator.onTranscriptStored` queues a summary (when a language model is ready) and indexing; `SummaryCoordinator.onSummaryStored` queues indexing again. `IndexingCoordinator` waits while transcription or a summary is queued or running (read under observation, like summaries waiting for transcription), so it runs last and never loads its model beside another post-processing model. `RecordingPriorityPolicy` stops it when a recording starts, and the embedding model is unloaded then. **Deviation:** indexing jobs are kept in memory, like summary jobs; the index itself records what it was made from, which is what makes this safe (see Recovery).

**Schema (migration 5).** Derived data only: everything can be rebuilt from `transcripts`, `transcript_segments`, `summaries` and `summary_parts`.

| Table | Purpose |
| --- | --- |
| `search_chunks` | The unit search finds and returns: `id` (AUTOINCREMENT, never reused, so an identifier handed to an agent keeps naming the same text or nothing), `recording_id`, `kind` (`transcript`, `summary`, `summary_part`), `position`, `start_time`/`end_time` and `first_segment`/`last_segment` where the text sits on the timeline, `text`. Unique per (`recording_id`, `kind`, `position`). |
| `search_chunks_fts` | FTS5 external-content index of `search_chunks.text` (`unicode61`, diacritics removed), kept in step by triggers on insert, update and delete. |
| `embedding_spaces` | One row per (`model_id`, `revision`, `dimensions`): what vectors were made with. Vectors of different spaces are never compared. |
| `chunk_embeddings` | (`space_id`, `chunk_id`) → `vector`: `dimensions` little-endian Float32 values, normalized to length 1, so a dot product is the cosine similarity. Cascades from both the chunk and the space. |
| `search_index_state` | Per recording, the `created_at` of the transcript and summary its chunks were made from. |

Chunks do not depend on the embedding model, which is why words are searchable without one and why switching models only adds vectors in a new space (the old space is then deleted). Like transcripts, chunks refer to `recordings.id` without a foreign key, so removing a recording can be undone; every query joins `recordings`, so a removed recording is never found, and `purgeOrphans` clears its index at the next launch.

**Chunking.** `SearchChunker` groups consecutive transcript segments up to 1,000 characters and 90 seconds, repeating the last segment at the start of the next chunk so speech on a boundary is found whole. Sizes are in characters rather than tokens so that chunks do not depend on a model; 1,000 characters stay well inside the 512 tokens of the E5 models. The summary is split into pieces of whole lines, and the notes on each batch become `summary_part` chunks with their time span. A changed transcript or summary replaces only its own kinds of chunks, in one transaction; their vectors go with them by cascade.

**Embedding.** `EmbeddingModel` is a third `ModelManager` instance with its own catalog, folder (`Verbatim/EmbeddingModels`), registry and selection, downloaded by the same Hub provider as language models (`HubModelProvider` and `HubModelFileStore`, generic over `HubHostedModel`). `MLXEmbeddingRuntime` loads it with `MLXEmbedders` from its folder alone, and embeds one text at a time (no padding, so mean pooling is exact), with the `query: `/`passage: ` prefixes E5 expects, cutting text over 512 tokens. `LocalEmbeddingProvider` shares one loaded copy between indexing and search, keeps it for a minute after its last session so an agent's follow-up questions do not reload it, and unloads it when recording starts. Vectors are stored eight at a time, so an interrupted job continues where it stopped.

**Search.** `RecordingSearchService` runs two searches for four times the requested number of results: FTS5 with BM25 over the query's words as quoted prefixes, and exact nearest neighbors of the query's vector. Both apply the same filter (recordings, creation dates, tags, chunk kinds) in SQL. They are combined by reciprocal rank fusion (k = 60), because BM25 and cosine scores are not comparable while ranks are, and a chunk found by both rises. A hit carries the chunk with its time span and segment range, its recording's title and date, how it matched and its similarity. While recording, or without a ready model, only words are searched, and the result's `semanticStatus` says so.

**Why exact search in memory.** **Deviation** from the planned sqlite-vec index: `vec0` is also an exact scan, fixes the dimension in its table definition, and would need the extension registered on the app's own connections, which SQLiteVecKit does not export. `SQLiteSearchIndexRepository` instead loads the selected space's vectors once into a `VectorMatrix` and scores them with one `vDSP_mmul`; the cache is dropped on any write. At 384 dimensions an hour of speech is about 60 chunks: a thousand hours are about 90 MB and score in milliseconds. Approximate search can be added behind the same contract if libraries grow far beyond that.

**Recovery.** At launch, and whenever the ready model changes, `IndexingCoordinator` queues recordings whose transcript or summary is newer than `search_index_state`, and recordings with chunks lacking a vector in the selected space.

### MCP server

A Model Context Protocol server inside the app, so that AI agents and chats on this Mac can search and read recordings. It runs while the app runs and the user has turned it on in Settings › Agents; it is off by default.

**Layers.** `RecordingKnowledgeService` (Application) holds the use cases and knows nothing of the protocol. `MCPToolbox`, `MCPEndpoint`, `MCPHTTPServer` and `LocalHTTPServer` (Infrastructure, `AgentServer/`) translate between it and MCP. `AgentServerController` (Application, created in App) owns the settings and the lifecycle; `AgentSettingsViewModel` presents them. Changes take effect in order, each waiting for the last, so a quick toggle ends in the state last asked for. A new token on the same port is taken without closing the port.

**Transport.** Streamable HTTP at `http://127.0.0.1:<port>/mcp`, port 47823 by default. Each POST carries one JSON-RPC message (or a batch) and gets one `application/json` response; notifications get 202. The server keeps no sessions and offers no event stream, which the protocol allows, so GET and DELETE get 405. Protocol versions 2025-11-25, 2025-06-18, 2025-03-26 and 2024-11-05 are accepted; `initialize` answers with the client's version when known, else the newest. **Deviation:** no MCP SDK or server package is used: four JSON-RPC methods (`initialize`, `ping`, `tools/list`, `tools/call`) over a small HTTP/1.1 reader on Network.framework need no dependency, where an SDK would also need an HTTP server package. Bodies must state their length (no chunked encoding), up to 4 MiB; at most 32 connections are open.

**Security.** Only `127.0.0.1` is bound. Every request needs `Authorization: Bearer <token>` (32 random bytes, compared in constant time), a `Host` of `127.0.0.1` or `localhost` with the port, and no `Origin` other than those, which stops web pages, including through DNS rebinding. The token is made at first launch, stored in the app's defaults (beside the library it protects), shown and replaced in Settings. The `com.apple.security.network.server` entitlement allows listening in the sandbox. Tests never start the server, because they run inside the app (`isHostingTests`).

**Tools.** All read-only, annotated as such, with results as `structuredContent` and the same JSON as text:

| Tool | Backed by |
| --- | --- |
| `search_recordings(query, from?, to?, tags?, recording_ids?, sources?, limit?)` | `RecordingSearchService.search` with tag names resolved: hits with chunk id, recording id, title, date, source, time span, segment range, text, how matched, similarity and link, plus whether meaning was used |
| `list_recordings(from?, to?, tags?, title?, type?, sort?, limit?, cursor?)` | The `recordings` repository: title, date, length, type, tags, and transcript, summary and index status from storage and the coordinators' jobs; with `now` |
| `get_recording(recording_id)` | The same, with what the transcript (language, speakers, size) and summary (language, whether current) are |
| `get_summary(recording_id)` | `SummaryRepository`: the summary and its timed parts |
| `get_transcript(recording_id, around_chunk_id? \| from?/to?, context_seconds?, max_characters?)` | `TranscriptRepository`: segments starting in a window, cut at a character budget with `next_from` |
| `list_tags()` | Tags with their recording counts |

Dates in arguments are what the Library's date search reads (`2026-11-04`, `2026-11`, `today`) or ISO 8601 date-times; a date covers its whole day, month or year. Results give dates in ISO 8601 with the Mac's offset and times in seconds with an `hh:mm:ss` label. A mistake the agent can correct comes back as a tool error that says how (unknown id, tag or argument, no transcript yet and why). The agent's own model does the answering; the server only finds and returns text. Queries while recording still answer, by words only.

**Links.** Results carry `verbatim://recording/<id>?t=<seconds>` (`RecordingLink`), which agents are told to cite. The app declares the scheme (`Recorder/Info.plist`, merged into the generated one), and `AppDelegate` opens such a link in the Viewer at that second, queuing the Viewer until the first window has appeared when a link launches the app.

## Storage and models (planned)

Recording metadata is implemented: the sandbox Application Support directory holds `Verbatim/Library.sqlite`, opened through the system `SQLite3` with versioned migrations (`LibrarySchema`). **Deviation:** app tables do not go through SQLiteVecStore, whose `VectorStore` freezes an embedding dimension into the file at creation, before any embedding model is chosen, and offers no migrations for app tables. The search index lives in the same file, in app-owned tables (see [Search index](#search-index)). New tables should be added as new migrations and refer to `recordings.id`. Transcripts and jobs do so without a foreign key, because removing a recording can be undone and must bring its transcript back; `purgeOrphans` clears them at the next launch, and deleting to the Trash clears them at once. Repositories hold separate connections to the file, opened one at a time. Media is stored separately and referenced by stable identifier, path and security-scoped bookmark.

The embedding models are multilingual-e5-small and -base, run with MLX rather than Core ML, so they share the download, verification and loading path of the language models. Like speech models they download only when the user asks, with no weights bundled; they load on demand after capture ends and unload when idle or when recording starts. Model identity, revision and dimensions are stored with the vectors (`embedding_spaces`), so a replacement triggers a reindex. WhisperKit likewise runs exclusively in post-processing and never initializes at startup.

## Concurrency and SwiftUI (planned)

Use async/await, structured tasks and task groups where appropriate. Actors own isolated mutable capture, persistence, and processing state. Keep cross-isolation values Sendable. Propagate cancellation and typed errors; do not silence Swift 6 diagnostics with unchecked Sendable. UI-bound observable state uses `@MainActor` and `@Observable`; views use `@State` for local state and focus on presentation and interaction. Do not put business logic in views or use main-queue dispatch as the standard UI update mechanism.

## Lifecycle and native interaction (planned)

Keep SwiftUI App lifecycle and a regular Dock application. Add an AppKit delegate only where native integration requires it. Dock activation reopens the Recorder window, or the Library if the user chose that in Settings, except during a recording; the Dock menu, menu bar item and quit confirmation are driven by the real recording state, and recording continues with closed windows. The Viewer's scene has the `principal` window manager role, because auxiliary windows cannot enter full screen. Do not introduce LSUIElement agent mode or custom Dock UI.

## Sandbox and contextual permissions

App Sandbox is enabled. Audio-input, Movies folder, user-selected read/write and app-scoped bookmark entitlements cover the microphone and recording folders; the microphone usage description is present. The outgoing network entitlement exists for downloading speech and language models from the Hugging Face Hub, and only when the user asks. The incoming network entitlement exists for the MCP server, which listens on the loopback interface only, and only when the user turns it on. These entitlements do not grant Screen Recording authorization. Screen and system audio capture authorization must be handled through macOS capture APIs. Microphone authorization is separate. Request each permission when the corresponding feature is used, never all at startup. Persist folder access with security-scoped bookmarks, balance access start/stop, and handle stale bookmarks and denied or revoked permissions. Do not disable the sandbox to bypass permissions. A signed app is needed to validate sandbox/TCC behavior; unsigned build verification does not validate permissions.
