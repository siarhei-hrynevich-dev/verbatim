# Implementation Status

This document describes what exists in the code today. Target architecture, layer rules, service boundaries and planned runtime behavior are in [ARCHITECTURE.md](ARCHITECTURE.md); keep the two separate. Update this file when implemented behavior changes, and move a capability out of "Not implemented yet" only when it actually exists.

## Platform

Recorder is a macOS 15+, arm64, Swift 6 application with a SwiftUI App lifecycle, a visible Dock icon, and the Recorder window.

## Recording (implemented)

The Recorder window records for real. Screen, window and audio-only recording, pause and resume, permissions, file storage and preference restoration work; see [verification](VERIFICATION.md) for what has and has not been exercised on hardware.

| Layer | Component | Responsibility |
| --- | --- | --- |
| Presentation | `RecorderViewModel`, `RecorderSourceSelection`, `LevelPreviewController` | Settings being edited, available sources and selection, Ready-state meters (on demand, via Check Sound), callouts. |
| Application | `RecordingCoordinator`, `RecordingPreflight`, `RecordingContracts` | The lifecycle (single source of truth, created by App), checks before starting, and the interfaces Infrastructure implements. |
| Domain | `Recorder/Models` | `RecordingState` transition rules, `RecordingFailure`, `RecordingConfiguration` validation, output size and disk space rules, file naming, metadata. |
| Infrastructure | `ScreenCaptureEngine`, `LiveCaptureSession`, `CaptureSampleSink`, `MediaFileWriter`, `MicrophoneCapture`, `CaptureSourceDiscovery` | Capture and media output. |
| Infrastructure | `FileRecordingStore`, `UserDefaultsRecordingPreferencesStore`, `SystemCapturePermissions`, `WorkspaceSystemActions` | Files and the sidecar, preferences, permissions, System Settings and Finder. |

`AppComposition` wires these together; `AppDelegate` holds the result, so a recording continues with every window closed.

**Lifecycle.** `idle → preparing → recording → stopping → finalizing → idle`, with `failed` reachable from `preparing`, `stopping` and `finalizing`. Transitions are checked by `RecordingState.allowsTransition(to:)` and happen on the main actor before any suspension, so duplicate requests are rejected by state. A recording is reported as saved only after its file closes and `MediaValidator` confirms it is playable. Quitting during a recording waits for finalization.

**Capture.** Up to three independent producers deliver to one `CaptureSampleSink`, an actor running on the serial queue that capture callbacks use, which keeps samples in order without a task per sample:

- A video `SCStream` for a display or window, with no audio.
- A separate system audio `SCStream` on a display filter excluding nothing, so every mode records all applications' audio (excluding Verbatim's own).
- An `AVCaptureSession` for the microphone, which is why microphone-only recording needs no Screen Recording access. Its timestamps are converted to the host clock used by ScreenCaptureKit.

`MediaFileWriter` writes HEVC video and AAC audio with `AVAssetWriter`. Microphone (mono) and system audio (stereo) stay separate, named tracks. Pausing excludes the paused interval from the output timeline.

**Resolution.** 720p and 1080p fit a 1280×720 or 1920×1080 box, keep the source's aspect ratio and never upscale; Native keeps the source's physical pixels. ScreenCaptureKit sizes are in points and are multiplied by the filter's `pointPixelScale`.

**Files.** Each recording gets a new folder `yyyy-MM-dd_HHmmss_<uuid>/` holding `recording.mov` and `recording.json`, under the recordings folder: `~/Movies/Verbatim` by default (through the Movies entitlement) or a folder chosen from the footer's context menu or a callout (through a security-scoped bookmark). Audio-only recordings are also QuickTime files, because MPEG-4 audio files lose the track names that identify each source. Files are written in fragments, so an interrupted recording remains recoverable. A folder is removed only if nothing was written to it. When finalization fails, the files stay and `recording.json` is marked `incomplete`.

**Metadata.** `recording.json` is a sidecar beside the media, behind the `RecordingMetadataStore` contract: a snapshot from when the recording finished, including a note when it did not finish. Nothing reads it yet, and renaming does not update it. The Library's database is the source of truth.

**Automatic transcription.** The toggle is captured in the recording's configuration and stored as `transcriptionRequested`. `RecordingCoordinator.saveCompleted` queues a job once the media is safe and has its Library entry, unless the recording has no audio.

**Live levels.** While recording, the session reports levels. In the Ready state, `LevelPreviewController` runs audio capture only while the setup screen is showing in the active app, and only for sources that are enabled and already permitted. macOS shows its microphone and screen recording indicators during that time.

**Sources going away.** A display or microphone that disconnects keeps its remembered selection and is selected again when it returns. A closed window is detected from its stream stopping and by a 2-second availability check. While recording, losing the video source or the only remaining source ends the recording and saves what was captured; losing one audio source continues with the rest and is reported afterwards.

**Permissions.** Nothing prompts at launch. Screen Recording is requested when starting a recording that needs it or when choosing Window mode; Microphone when starting or when turning the microphone on. Denial shows a callout with a System Settings button and a fallback.

## Recording library (implemented)

| Layer | Component | Responsibility |
| --- | --- | --- |
| Presentation | `LibraryViewModel` and extensions, `LibraryItem`, `LibraryIssue` | What the window shows, user actions, mapping recordings to rows, and error wording. |
| Application | `LibraryService`, `LibraryContracts` | Use cases and their rules; `revision` advances on every change. |
| Domain | `LibraryRecording`, `RecordingQuery`, `RecordingDateSearch`, `LibraryError`, `RecordingFileLayout` | The tracked recording (wrapping `Recording`), queries, reading search text as dates, typed failures, which folders are app-owned. |
| Infrastructure | `SQLiteDatabase`, `LibrarySchema`, `SQLiteRecordingRepository` | The connection, versioned migrations, and the `recordings` table. |
| Infrastructure | `LocalRecordingFileStore`, `MediaFileAccess`, `VideoThumbnailProvider` | Availability, bookmarks, Finder and the Trash; one still per video, cached in memory and in Caches. |

**Database.** `Application Support/Verbatim/Library.sqlite`, opened on first use, in WAL mode. Schema version 1 has one table, `recordings`: `id`, `title`, `title_key`, `created_at` (milliseconds), `duration`, `recording_type`, `media_path` (unique), `media_bookmark`, `file_size`, `processing_status`, `updated_at`, with indexes for each sort order. `title_key` is the case- and accent-folded title, because SQLite folds only ASCII. `PRAGMA user_version` tracks the schema; each migration runs in its own transaction. A database that is unreadable, fails to migrate or comes from a newer version is reported and never recreated. A row that cannot describe a recording is logged and skipped.

**Finalization.** After the media closes and validates, `RecordingCoordinator.saveCompleted` writes the sidecar and calls `LibraryService.addFinishedRecording`, independently. The service checks the file exists, reads its size, makes a bookmark and inserts the entry, on the main actor's lifecycle task and never from capture callbacks. If storing fails, the media stays and the Recorder shows its “details weren’t saved” callout. Unfinished recordings get no entry.

**Updates.** The window runs `reload()` from `.task(id: reloadKey)`, which changes with the service's revision, the section, sort order and search text, and when the window becomes key. A closed window does no work. Rows appear first; file availability is checked afterward on the file store's actor, so an unreachable volume cannot hold up the list.

**Finding files.** The stored path is tried first. Failing that, the bookmark follows a file moved or renamed in Finder and the stored path is updated; a file found in the Trash counts as missing. Anything unreachable stays listed as missing, with the reason (not found, drive not connected, no access), and offers Locate… and Remove from Library while actions needing the media are disabled. Locate File checks that the chosen file is playable and has the same kind of content, then repoints the same entry; a file another entry uses is refused.

**Remove and delete.** Remove from Library deletes only the entry and thumbnail, and offers Undo. Delete Recording moves files to the Trash first and removes the entry only afterward. A whole folder is trashed only if its name carries this recording's identifier and it holds nothing but the media and known derived files. Otherwise only those known files go, and only the media when the folder is not app-owned. Failing to trash the media leaves everything as it was; related files left behind are reported.

**Access.** Recordings in `~/Movies/Verbatim` are reached through the Movies entitlement, and those in the current custom folder through its bookmark. Each media file also has its own security-scoped bookmark, opened only around each operation, for reaching it after the recordings folder changes. That bookmark covers the file alone, so deleting such a recording moves only the media and leaves its sidecar.

**Tags.** Like Finder's, a tag has a name and one of seven colors (`RecordingTag`, `TagColor`), and a recording can carry any number of them. A new library has two, `work` (blue) and `personal` (green), written by migration 3 and kept in step with `RecordingTag.defaults` by a test; they can be edited or deleted like any other and are not restored. Tags live in `tags` (names unique ignoring case and accents, shown in creation order) and `recording_tags`, which cascades with both sides, so deleting a tag only unlinks it. A recording holds tag identifiers (`LibraryRecording.tagIDs`), which makes rename and recolor apply everywhere, and an undone removal brings its tags back. `LibraryService` creates, edits and deletes tags and sets a recording's tags. In the Library, the sidebar's Tags section lists them with counts and filters by one; its + button and each tag's context menu (Edit Tag…, Delete Tag…) manage them. The recording's context menu lists every tag with a checkmark and toggles it with the mouse (not by keyboard), and the list shows a recording's tags beside its title.

**Search and sort.** Search looks across the library, like the design's, at titles and at dates such as `today`, `2026-11`, `Nov 4`. Filtering, sorting and sidebar counts are database queries. Newest, Oldest, Name and Duration come from the toolbar menu.

**Status.** Every new recording is stored as `recorded`, shown as “Not Transcribed”. The status column then follows its transcription job; see [Transcription](#transcription-implemented).

## Player (implemented)

The Viewer window plays recordings from the Library. The player is shared by video and audio-only recordings; only what is drawn differs.

| Layer | Component | Responsibility |
| --- | --- | --- |
| Presentation | `ViewerViewModel` and extensions, `ViewerIssue`, `ViewerLiveMedia`, `ViewerControlHUD` | The open recording, playback state, seeking, error wording, controls. |
| Application | `PlaybackContracts`, `LibraryService` | The `PlaybackService` contract; metadata, media access, Finder and locating, as for the Library window. |
| Domain | `Playback` | `PlaybackState` and its transitions, `PlaybackFailure`, `PlaybackEvent`, `PlaybackMediaInfo`, `PlaybackTimeline` rules. |
| Infrastructure | `AVPlaybackService`, `AVPlayerSurface` | `AVPlayer`, its observers and error translation; AVKit rendering. |

**Opening.** The Library passes a recording's identifier. Metadata shows first, so a recording that can't play is still identified; then the media is opened with `LibraryService.openMedia(of:)`, which holds any security-scoped access until the session ends, and loaded into the player. A recording starts paused. Opening another first cancels the load, seek and observers of the last one, unloads it and clears its details, so at most one item ever exists.

**State.** `idle → loading → ready → playing ⇄ paused → ended`, with `failed` reachable from anything loaded or loading. A seek moves `ready` and `ended` to `paused`. Everything else the views need derives from this.

**Formats.** The Recorder writes QuickTime files with HEVC video and up to two AAC tracks; audio-only recordings have no video track. Both audio tracks are enabled with no selection group, so `AVPlayer` mixes the microphone and system audio. The picture or audio view follows what the file holds, not the recording's stored type.

**Duration.** Controls and the toolbar use the media's own duration once loaded, and the stored one until then. A difference over one second is logged. The stored value is not rewritten; Locate File is what updates it. The Library's list therefore keeps showing the stored value.

**Timeline.** Time reports arrive every 0.1 s and redraw only the position bar and clock. Seeks run one at a time and only the newest target is kept, so a long drag queues nothing. While dragging or seeking the player's reports are ignored, which keeps the thumb still. Dragging holds playback, uses approximate seeks and ends with an exact one, then resumes if it was playing. Seeks are clamped to the recording; non-numbers are refused.

**End of playback.** `ended` shows a replay button, which plays from the start. Seeking back pauses there, and Play resumes.

**Closing.** Closing the window or going back to the Library, which closes it, unloads the media, removes observers, cancels asynchronous work and closes file access. Opening it from the Window menu then shows that nothing is open. Renaming or removing the recording in the Library updates the open Viewer or ends its playback.

**Errors.** Missing file, disconnected drive, denied access, unsupported format, damaged media and failures during loading or playback each show their own explanation in place of the media, with Locate File…, Try Again or Show in Finder as they apply. Locate File uses the same validation as the Library. A failed seek or Finder action shows an alert and leaves playback alone. Details go to OSLog under the `Playback` category.

**Finder.** Show Recording in Finder, Open Recording Folder and Show Transcript in Finder go through `LibraryService`. The last is enabled only when a transcript file exists beside the media.

**Transcript panel.** Shows the stored transcript; see [Transcription](#transcription-implemented). No waveforms are drawn for real recordings.

**Full screen.** The whole window enters native full screen, including the transcript panel.

## Speech models (implemented)

The AI Models tab downloads, verifies, selects and removes Whisper models, and chooses the transcription language. Since summaries, `ModelManager` is generic and the same lifecycle also serves language models; see [Summaries](#summaries-implemented).

| Layer | Component | Responsibility |
| --- | --- | --- |
| Presentation | `ModelSettingsView`, `ModelCatalogSection`, `ModelCatalogRow`, `ModelSettingsViewModel`, `ModelIssue` | The catalog, states, actions, confirmation, error wording. No file or network work. |
| Application | `ModelManager` (with `+Installing`), `ModelFileWorkflow`, `RecordingPriorityPolicy`, `ModelContracts` | State and its transitions, the install steps, holding work back while recording, the interfaces below. |
| Domain | `SpeechModel` | The catalog, `ModelInstallState` and its transitions, `ModelManagementError`, the registry, the resolved model and lease. |
| Infrastructure | `WhisperModelProvider`, `ModelFileStore`, `HubModelManifestClient`, `JSONModelRegistryStore` | WhisperKit calls, the storage layout, the repository's file listings, the registry file. |

**Catalog.** Tiny, Base, Small and Large v3 Turbo, with the exact variant names WhisperKit uses. Medium is deliberately absent: the repository has it, but WhisperKit 1.1.1 lists it as supported on no Mac. `WhisperKit.recommendedModels()` decides what this Mac supports, without network or disk, so M1 Macs show Turbo as not supported. `WhisperKit.fetchAvailableModels` updates that when Settings opens. Sizes aren't hardcoded: they come from the Hub's tree API, because WhisperKit exposes names but not sizes, and are saved in the registry, so the catalog works offline. A failed refresh changes nothing about installed models and shows a note. WhisperKit's own default for a Mac may be outside this catalog, so the recommendation is Turbo where supported and otherwise Small, and is only ever an offer.

**Storage.** WhisperKit's downloader owns this layout under the `downloadBase` the app gives it, and later loading finds the files there, so nothing is copied:

```text
~/Library/Application Support/Verbatim/Models/          (in the container when sandboxed; excluded from backups)
  model-registry.json                                   what was installed, and known sizes
  models/argmaxinc/whisperkit-coreml/
    <variant>/                                          model files
    .cache/huggingface/download/<variant>/              *.metadata and partial *.incomplete files
    config.json                                         support table, written by fetchAvailableModels
  models/openai/whisper-<size>/                         tokenizer, shared by models of the same size
```

**Installing.** `download(_:)` checks state, so duplicates are ignored. Then: list the files; check disk space for what is still missing plus a 500 MB margin; download with `WhisperKit.download`; fetch the tokenizer with `HubApiWrapper`, because WhisperKit otherwise fetches it from the network on first load, which would break offline use; verify every file's size and each large file's SHA-256, plus that the three Core ML components and `tokenizer.json` are present; record it. Only then is it `installed`.

**Progress.** Measured from bytes on disk, including partial files, four times a second. WhisperKit's own `Progress` weighs every file equally, so a 59 MB `weight.bin` and a 243-byte file would count the same. The downloader writes in chunks of 10 MiB, so progress moves in steps of up to that.

**Stopping.** Cancelling is reliable and stops the transfer; it removes the model's files, and its tokenizer when no other model uses it. A failed download keeps its partial files, and Retry continues them with HTTP range requests. A failed verification discards the files, because the downloader would otherwise trust them. An install starting right after a cancel waits for the first to finish, as both would use the same files.

**Restarting.** At launch, and when Settings comes forward, the registry is compared with the disk, using existence and sizes only. Files missing entirely mean the model was removed: it is forgotten. Some missing or changed means `failed(.damagedInstallation)`, and Retry starts it over, since a damaged file can look current to the downloader. Files without a record mean a download never finished: `failed(.interruptedDownload)`, and Retry continues, confirming complete files without downloading them again. An unreadable registry counts as empty, with the same result. This check runs in a task the manager owns, so a window closing can't cancel it halfway.

**Selected model.** The first model to finish installing is selected when none is selected and no other model is installed. Otherwise only an installed, verified model can be selected, by the user. Persisted in `UserDefaults` as `settings.selectedModelID`. Nothing is loaded by selecting. When it becomes unavailable, it stays selected and a warning offers Repair or another installed model. Removing it clears the selection, and an existing installed model is never chosen on the user's behalf; if none remains, the next one installed is selected. The contract for transcription is in [ARCHITECTURE.md](ARCHITECTURE.md#integration-contract-for-transcriptionservice).

**Removing.** Installed models ask first, stating the space freed; leftovers of a failed download go straight away. A model held by a `ModelLease` can't be removed. Only the model's own folder and partial files go, plus its tokenizer when unshared, and recordings and transcripts are never involved. A failure leaves the state as the disk then says.

**Recording.** `RecordingPriorityPolicy` stops running installs when a recording starts preparing, keeping their partial files, and they continue when it ends. A download requested during a recording waits, shown as Paused. A catalog refresh doesn't start. The launch check only reads metadata.

**Errors.** `ModelManagementError` names each case: no network, failed download, insufficient disk, unavailable or unsupported model, failed verification, interrupted download, damaged installation, denied storage, failed removal, model in use, and an absent or unavailable selection. `ModelIssue` words them, and rows offer Retry and removing what was downloaded. Details go to OSLog under the `Models` category. No state stays in Downloading after a failure, and none survives a restart.

**Limits.** Progress steps as described above. A download doesn't continue while the app isn't running, though it resumes on Retry. Large v3 Turbo is unavailable on M1, where WhisperKit lists only compressed Large variants not in this catalog.

## Transcription (implemented)

Offline transcription of recordings with an installed Whisper model. The design is in [ARCHITECTURE.md](ARCHITECTURE.md#transcription).

| Layer | Component | Responsibility |
| --- | --- | --- |
| Presentation | `ViewerViewModel+Transcript`, `ViewerTranscriptStatusView`, `ViewerTranscriptPanel`, `LibraryItem`, `LibraryContextMenu`, `TranscriptionIssue` | Showing transcripts and job state, actions, error wording. |
| Application | `ProcessingCoordinator` (with `+Running`), `TranscriptionContracts` | The queue and its state, one job's steps, the interfaces below. |
| Domain | `Transcript`, `TranscriptionJob`, `TranscriptFormat` | Segments and their validation and order, job states, failures, TXT, SRT and JSON. |
| Infrastructure | `WhisperTranscriptionService`, `RecordingAudioReader`, `SpeechChunker` | WhisperKit, decoding tracks, chunk boundaries. |
| Infrastructure | `SQLiteTranscriptRepository`, `FileTranscriptStore` | Tables and transcript files. |

**Starting.** Automatically as above, or manually: Transcribe, Retry Transcription and Re-transcribe in the Library, and Generate Transcript, Retry and Re-transcribe in the Viewer, from the transcript panel or the More menu. A request for a recording already queued or running is ignored. Jobs run one at a time in the order asked for.

**Model and language.** The model selected in Settings, resolved when a job starts, after comparing models with the disk. It is held by a lease until the job ends, so it can't be removed meanwhile. Nothing is downloaded or switched: no usable model fails the job with a way to Settings. The language comes from Settings › AI Models and defaults to Automatic, which settles each track's language from its first stretches of speech and switches a chunk to another language only when it is clearly spoken in it (see Architecture › Recognition quality); the transcript records the language heard for longest.

**Storage.** Schema version 2 adds `transcripts` (one per recording: model, model version, language, date), `transcript_segments` (position, start, end, text, source) and `processing_jobs` (state, attempts, model, failure). A transcript row exists only when complete, so its status is the job's. The model version is WhisperKit's variant name, such as `tiny`; the variant identifier in `model_id` carries the rest, since WhisperKit reports no revision. Replacing a transcript and saving a job are each one transaction, and saving a job also updates `recordings.processing_status`, which the Library's queries use.

**Files.** `transcript.txt`, `transcript.srt` and `transcript.json` go beside the media, each written atomically, and are rendered from the stored transcript alone. In SRT, overlapping sources give overlapping cues in chronological order, labeled when there is more than one source, so the same transcript always gives the same file. A file that can't be written, as when access covers only the media, doesn't fail the job: the Viewer says so, and Export as… saves the same content anywhere.

**Progress.** Audio finished out of all audio to transcribe, across tracks, which moves about every 30 seconds of audio. Preparing and saving are shown as stages without a percentage. Nothing is estimated from elapsed time.

**Library.** Status shows Not Transcribed, Pending, Transcribing with progress, Ready or Failed with the reason in a tooltip, and updates without reloading by hand: state changes advance `revision`, and progress joins the stored status in the view model. The Processing section lists queued, running and failed recordings. A failed re-transcription shows Failed while the earlier transcript stays available. Once a recording is Ready, the same column follows the steps after it, which live in memory only: Summarizing and Indexing with progress, or Summary queued and Indexing queued. While a step runs, the number of the step shows next to its progress bar (`1/3` transcript, `2/3` summary, `3/3` search index). A step without a model selected is skipped. Summary and indexing failures are shown in the Viewer and Settings, not in the row.

**Viewer.** Lines show the start time, source and text. Playback highlights the last line started; the panel redraws only when that changes, and rows are lazy. Selecting a line seeks to its start. Scrolling by hand pauses following, and Follow Playback resumes it. Without lines, the panel shows the job's real state, with Cancel, Retry or Generate Transcript. While a replacement runs or after it fails, a banner sits above the existing lines. Copy and Export work from the stored transcript. An open recording picks up a new transcript when its job completes.

**Removing.** Remove from Library stops any job, and the transcript stays until the next launch, so Undo brings it back. Delete Recording also forgets the transcript at once, and its files go to the Trash with the recording.

**Errors.** `TranscriptionFailure` names no model selected, model unavailable, model load failure, missing media, no audio, unsupported audio, decoding failure, recognition failure, insufficient disk space and persistence failure. `TranscriptionIssue` words them. Original media is never touched. Details go to OSLog under the `Transcription` category, and transcript text is never logged; WhisperKit's own logging is off.

**Limits.** Speech played through speakers can be picked up by the microphone too, and then appears under both sources, because no echo cancellation is applied. A hole inside a track, as after audio is dropped during capture, is closed up by the AAC encoder when recording: the file has no record of it, and picture and sound can differ there, as they do in playback. Stopping waits for the current prediction, and a model load can't be stopped at all. A restart begins the job again. WhisperKit does not decode audio shorter than a second.

## Summaries (implemented)

Summaries of transcripts written by a local language model. The design is in [ARCHITECTURE.md](ARCHITECTURE.md#summaries).

| Layer | Component | Responsibility |
| --- | --- | --- |
| Presentation | `ViewerSummaryPanel`, `ViewerSidePanel`, `ViewerViewModel+Summary`, `SummaryIssue`; `ModelCatalogSection`, `ModelCatalogRow`, `SummarySettingsSection`, `SummarySettingsViewModel` | The Viewer's Summary panel; the Summaries catalog and Summary Settings in Settings › AI Models. |
| Application | `SummaryCoordinator` (with `+Running`), `TranscriptSummarizer`, `SummaryPrompts`, `SummaryPreferences`, `LocalTextGenerationProvider`, `SummaryContracts`, `ModelManager<LanguageModel>` | The queue, batching and combining, prompts, settings, leasing and loading a model, the backend boundary. |
| Domain | `LanguageModel`, `LanguageModelCatalog`, `SummarySettings`, `TranscriptSummary`, `SummaryPart`, `SummaryJob`, `SummaryFailure`, `SummaryBatching`, `InstallableModel` | The catalog and presets, settings ranges, results, job states, failures, batch splitting. |
| Infrastructure | `HubModelProvider<LanguageModel>`, `HubFileDownloader`, `HubModelFileStore<LanguageModel>`, `MLXTextGenerationRuntime`, `TransformersTokenizerLoader`, `SQLiteSummaryRepository`, `UserDefaultsSummarySettingsRepository` | Downloads, storage layout and verification, MLX, tables, settings. |

**Catalog.** Qwen3 1.7B (about 1 GB, 8 GB of memory), Qwen3 4B Instruct 2507 (about 2.3 GB, recommended) and Qwen3 30B-A3B Instruct 2507 (about 17 GB, 32 GB of memory), the 4-bit MLX conversions from `mlx-community`, Apache 2.0, each pinned to a commit. Gemma 3 and Qwen3.5 are left out: their repositories hold vision-language configurations, and loading them as text models was not verified. Qwen3 1.7B is a hybrid reasoning model and is asked not to reason (`enable_thinking: false`).

**Storage.** `~/Library/Application Support/Verbatim/LanguageModels/<model id>/`, excluded from backups, with `model-registry.json` beside the models. Only what loading needs is downloaded: JSON, safetensors, Jinja templates, merges and tokenizer models, not READMEs. Verification checks sizes, SHA-256 of the weights after a download, and that configuration, tokenizer and weights are present.

**Installing and selecting.** As for speech models, through the same `ModelManager`: progress from bytes on disk, pausing for recordings, cancelling, retrying, repairing, the first installed model selected. A partial file continues from its length. Selection is stored as `summaries.selectedModelID`.

**Settings.** Summary Settings shows the selected model's settings behind Customize Settings, off by default, which uses the model's preset. On, it offers batch size, notes per batch and summary length in tokens, temperature, top P, top K and repetition penalty, and Reset to Recommended. Values are clamped to their ranges and the batch to the model's context. Custom settings are stored per model as JSON in `summaries.customSettings`; an unreadable value resets to the preset.

**Language.** Settings › AI Models › Processing › Summary Language chooses the language of every summary, independent of the transcription language and of what was spoken. It defaults to the first of the Mac's preferred languages that is offered, otherwise English, and is stored as `summaries.language` once chosen. A stored summary written in another language than the current setting is marked in the Viewer, with Summarize Again.

**Summarizing.** A transcript that has just been stored is summarized automatically when a language model is selected and installed (`SummaryCoordinator.enqueueIfModelReady`); without one nothing happens and nothing downloads. Summarize in the Viewer's Summary panel queues the open recording. Batching and combining are described in Architecture. Progress shows the part being read, then combining and saving; Cancel stops at the next token. Failures (no model, unavailable model, load failure, no transcript, no speech, generation, saving) are worded by `SummaryIssue`, with Open Settings when Settings has to change. A summary older than the transcript is marked, with Summarize Again.

**Storage of results.** Schema version 4 adds `summaries` (model, language, transcript creation time, date, text) and `summary_parts` (position, span, first and last segment, notes). Replacing is one transaction. Removing a recording keeps its summary until the next launch, so Undo brings it back; deleting it deletes the summary.

**Viewer.** The side panel switches between Transcript and Summary. The summary renders inline Markdown and can be selected and copied, with each part's notes below; selecting a part's time plays from there.

**Limits.** Jobs are not kept across launches. A transcription asked for while a summary runs can overlap it in memory. The models' quality on a given language is not checked by the app. Prompt editing is not offered. Summaries are not written as files beside the media and are not exported. A real-model check is opt-in (`SummaryEndToEndTests`, see the README).

## Search index (implemented)

Every recording's transcript and summary are indexed for search by meaning and by words. The design and the schema are in [ARCHITECTURE.md](ARCHITECTURE.md#search-index).

| Layer | Component | Responsibility |
| --- | --- | --- |
| Presentation | `ModelCatalogSection` with `ModelSettingsViewModel<EmbeddingModel>` | The Semantic Search catalog in Settings › AI Models. |
| Application | `IndexingCoordinator` (with `+Running`), `RecordingSearchService`, `LocalEmbeddingProvider`, `SearchContracts`, `ModelManager<EmbeddingModel>` | The indexing queue, hybrid search, sharing one loaded model, the boundaries to embedding backends and the index. |
| Domain | `EmbeddingModel`, `EmbeddingModelCatalog`, `EmbeddingSpace`, `SearchChunk`, `SearchChunker`, `SearchIndexState`, `RecordingSearchQuery`/`Filter`/`Hit`/`Result`, `SearchRanking`, `IndexingJob`, `IndexingFailure`, `HubHostedModel` | Models and their vector spaces, chunking, search values, rank fusion, job states, failures. |
| Infrastructure | `SQLiteSearchIndexRepository` (with `+Search`), `VectorMatrix`, `MLXEmbeddingRuntime`, `HubModelProvider<EmbeddingModel>`, `UserDefaultsEmbeddingSelectionStore` | Tables, FTS5 and exact vector search, MLX inference, downloads, the selection. |

**Pipeline.** When a transcript is stored, `ProcessingCoordinator.onTranscriptStored` queues a summary (if a language model is ready) and indexing; when a summary is stored, `SummaryCoordinator.onSummaryStored` queues indexing again. Indexing waits while transcription or a summary is queued or running, so in practice it runs last, and never alongside another post-processing model. A job makes chunks again only for whichever of the transcript and summary changed, then embeds the chunks that have no vector in the selected model's space, eight at a time, storing each batch.

**Catalog.** Multilingual E5 Small (384 dimensions, about 470 MB, recommended) and Multilingual E5 Base (768 dimensions, about 1.1 GB), from `intfloat`, MIT, each pinned to a commit and loaded with `MLXEmbedders`. Both read 100 languages, so a question in English finds Russian speech. Queries and passages get the `query: ` and `passage: ` prefixes the models were trained with; vectors are mean-pooled and normalized. Stored in `Verbatim/EmbeddingModels/<model id>/`; only top-level files and `1_Pooling/config.json` are downloaded, not the ONNX and OpenVINO copies. Selection is stored as `search.selectedModelID`.

**Without a model.** Chunks and the full-text index are built anyway, so words are searchable. Once a model is installed and selected, `IndexingCoordinator` notices the ready space under observation and queues every recording that lacks vectors in it; vectors of other models are deleted.

**Search.** `RecordingSearchService.search` runs FTS5 (words as quoted prefixes, BM25) and, unless recording, the query's vector against the in-memory matrix of the selected space, each for four times the requested results, combines them by reciprocal rank fusion and returns chunks with their recording's title, date, kind, time span and segment range, how each was matched and its cosine similarity. Filters: recordings, creation dates, tags, chunk kinds. Its `semanticStatus` says whether meaning was used and why not. The model stays loaded for a minute after its last use and goes at once when a recording starts.

**Recovery.** Jobs live in memory. At launch, and when the model changes, `search_index_state` and missing vectors show what to queue again. A recording that leaves the Library keeps its index until the next launch, or loses it at once when deleted to the Trash, like a transcript.

**Limits.** No window searches the index yet; AI agents do, through the [MCP server](#mcp-server-implemented). Index progress is not shown in Settings. Search is exact rather than approximate, which is fast enough for thousands of hours. A real-model check is opt-in (`EmbeddingEndToEndTests`, see the README).

## MCP server (implemented)

AI agents and chats on this Mac can search and read recordings through a Model Context Protocol server inside the app. The design is in [ARCHITECTURE.md](ARCHITECTURE.md#mcp-server).

| Layer | Component | Responsibility |
| --- | --- | --- |
| Presentation | `AgentSettingsView`, `AgentSettingsViewModel` | Settings › Agents: turning it on, status, port, token, what to paste into an agent. |
| Application | `RecordingKnowledgeService`, `RecordingPipeline`, `AgentServerController`, `AgentContracts` | Read-only use cases for agents, where each recording's steps stand, the server's settings and lifecycle, the hosting and settings contracts. |
| Domain | `AgentServerSettings`, `AgentServerState`, `AgentServerFailure`, `RecordingLink` | Port range, token format and generation, states, failures, `verbatim://` links. |
| Infrastructure | `MCPHTTPServer`, `LocalHTTPServer`, `HTTPRequestParser`, `MCPEndpoint`, `MCPToolbox`, `MCPToolOutput`, `JSONValue`, `UserDefaultsAgentServerRepository` | Listening on the loopback interface, HTTP/1.1, the protocol and its checks, the tools and their results, settings in defaults. |

**Turning it on.** Settings › Agents › Allow AI Agents to Read Recordings, off by default. The server then listens on `http://127.0.0.1:47823/mcp` (the port can be changed) at every launch until turned off. Status shows Off, Starting…, Running or why it is not running (port in use, not permitted, other), with Try Again. A port outside 1024–65535 is refused in place.

**Connecting.** The same tab shows the address and the token (hidden until Show), each with a copy button; Copy Command gives `claude mcp add --transport http verbatim <address> --header "Authorization: Bearer <token>"` for Claude Code, and Copy Configuration an `mcpServers` entry with `type: http`, the address and the header for other agents. New Token… replaces the token after confirmation; agents using the old one are refused from the next request.

**Tools.** `search_recordings`, `list_recordings`, `get_recording`, `get_summary`, `get_transcript` and `list_tags`, read-only, as listed in Architecture. Search results, summary parts and transcript excerpts carry `verbatim://recording/<id>?t=<seconds>` links; opening one shows the Viewer at that second, also when it launches the app.

**Limits.** Runs only while the app runs. No MCP resources, prompts or event streams, and nothing can be changed or started through it. Request bodies must state their length; chunked uploads are refused with 501. Verified with Swift tests over a real loopback port; no particular agent's client has been verified, and an agent needs MCP over HTTP with a custom header to connect.

## Settings window (implemented)

| Layer | Component | Responsibility |
| --- | --- | --- |
| Presentation | `SettingsViewModel`, the tab views | Tab state, bindings, storage figures, version. |
| Application | `AppPreferences`, `ModelContracts` | The single owner of preferences; `SettingsRepository`, `LoginItemControlling`, `RecordingsStorageProviding`. |
| Infrastructure | `UserDefaultsSettingsRepository`, `SMAppServiceLoginItem` | Persistence and the system's login item. |

**General.** Launch at Login uses `SMAppService`, and the system stays the source of truth: its state is read back, and approval pending in System Settings is shown with a button to get there. Show Menu Bar Icon controls the item shown while recording; the Dock badge stays. The Dock click opens the Recorder or the Library, and a recording always brings back the Recorder. Choosing Quit makes closing the Recorder window quit the app, waiting for any recording to be stopped and saved.

**Storage.** The recordings folder and its free space, the number and size of tracked recordings, and the space models use, all real. Change… goes through `RecorderViewModel`, as the Recorder's footer does, so both show the same folder and existing recordings stay where they are.

**About.** Version and build from the bundle. The licenses list names what the app actually ships, and each row opens its published text.

**Semantic Search.** The embedding model catalog, with the same download, select and remove actions as the other catalogs. See [Search index](#search-index-implemented).

**Agents.** The MCP server's switch, status, port, token and connection snippets. See [MCP server](#mcp-server-implemented).

**Left out because nothing backs them yet.** Notify When Processing Finishes, Postpone on Battery Power, Check for Updates and its automatic toggle, moving existing recordings, Preview Cache, Search Index size and Missing Recordings figures. They return as their features do.

## Windows (design scenarios)

The Viewer and the Library keep design scenarios on simulated state beside the real windows. Each feature has a `Preview` directory with fixed sample data and a scenario type that selects it.

- **Recorder design scenarios.** `RecorderPreviewScenario` and `RecorderPreviewState` still show the Recorder's design states with sample data, for SwiftUI previews and review. They never touch capture and do not change saved preferences.
- **Library scenarios.** With a `LibraryPreviewScenario`, `LibraryViewModel` filters, sorts, searches and removes sample recordings from `Features/Library/Preview` and touches nothing on disk. `SimulatedLibrarySearch` stands in for full-text and semantic search. Opening a sample recording goes to the Viewer's simulated state.
- **Viewer scenarios.** With a `ViewerPreviewScenario`, `ViewerViewModel` runs a simulated clock over sample transcripts and draws sample frames and waveforms, and touches neither media nor the Library, following the same pattern.
- **Settings scenarios.** Unlike the others, `SettingsViewModel` has no preview branches: a scenario swaps its dependencies for `SettingsViewModel.Dependencies.preview(for:)`, which runs the real `ModelManager` on a simulated provider, with in-memory preferences and fixed storage figures. It touches nothing on disk or the network, and **Live** in the Debug menu swaps back.

## App integration

App holds the AppKit integration:

- `AppComposition` creates the recording, library, playback and model services, preferences, the MCP server and its controller, the Recorder, Library, Viewer and Settings view models, and the Viewer's video surface.
- `AppDelegate` holds those, builds the Dock menu and quit confirmation, compares models with the disk at launch (no download or loading), starts the MCP server when it is turned on (never in tests), opens `verbatim://` links in the Viewer (`AppDelegate+Links`), and acts on the Dock click and window close preferences.
- `RecordingIndicators` observes recording state and the menu bar preference to show the menu bar item and Dock badge.
- `WindowNavigator` lets those AppKit menus open SwiftUI windows.
- The Debug menu lives in `App/DebugCommands.swift`.
- Dock activation reopens the Recorder window, or the Library if chosen in Settings. The Dock menu, menu bar item and quit confirmation act on the real recording.
- The app is a regular Dock application with the SwiftUI App lifecycle; no `LSUIElement` agent mode or custom Dock UI is configured.

## Shared UI

Shared design tokens and reusable controls live in `Shared/Design` and `Shared/Components`.

## Models and dependencies

Recording is a Codable, Sendable metadata value with an identifier, creation date, nonblank title, finite nonnegative duration, and processing status. `RecordingMetadata` adds its files, sources and completion, and `LibraryRecording` adds its media reference and size. Database rows are validated when read; the sidecar is not read, and its synthesized Codable provides round trips only.

The app target links WhisperKit, SQLiteVecStore, MLX, MLXLLM, MLXLMCommon, MLXEmbedders and Tokenizers. `WhisperModelProvider` uses only WhisperKit's static model APIs and its Hub client; `WhisperTranscriptionService` is the only thing that creates a `WhisperKit` instance, `MLXTextGenerationRuntime` and `MLXEmbeddingRuntime` the only things that load MLX models, and SQLiteVecStore is not instantiated. The Library uses the system `SQLite3` directly.

## Tests

Swift Testing suites in `RecorderTests` cover:

- `Recording` validation and status serialization (`RecordingTests`).
- Package imports (`DependencySmokeTests`).
- The recording lifecycle with controllable services: transitions, invalid requests, permission, disk and capture failures, finalization and metadata failures, interruptions (`RecordingCoordinatorTests`, `RecordingCoordinatorFailureTests`).
- Configuration validation, resolution and aspect ratio, disk space rules, level scale, folder naming (`RecordingConfigurationTests`).
- Preferences and file storage against real defaults and a temporary folder (`RecordingStorageTests`).
- The real writer and validator on synthetic samples, needing no hardware: track layout and names, pause timeline, ordering, unusable output (`MediaFileWriterTests`).
- The live Recorder view model and sources going away (`RecorderViewModelLiveTests`).
- The repository, migrations and date search against real temporary databases (`SQLiteRecordingRepositoryTests`).
- File availability, moved files, Trash ownership rules, replacement validation and thumbnails against real temporary files, with Finder and the Trash replaced (`LocalRecordingFileStoreTests`).
- Library use cases and finalization through the real coordinator with faked capture (`LibraryServiceTests`), and the live Library view model (`LibraryViewModelLiveTests`).
- Playback domain rules: state transitions, seek validation, duration handling and formatting, failure translation (`PlaybackModelTests`).
- The real player on media from the real writer, muted and without hardware: loading, both audio tracks, seeking, completion, replay, unloading, overtaken loads, unusable files, error translation; opening media through the real file store (`AVPlaybackServiceTests`).
- The live Viewer view model on a real Library with the player replaced: loading, errors, recovery, switching and cleanup (`ViewerPlaybackTests`), transport, scrubbing and completion (`ViewerTransportTests`), following the Library, the transcript panel and Finder (`ViewerLibraryIntegrationTests`).
- Presentation logic of the Recorder's design scenarios and the Library and Viewer view models against their simulated data (`RecorderViewModelTests`, `LibraryViewModelTests`, `ViewerViewModelTests`).
- Dock and menu bar menu construction (`RecordingMenusTests`).
- The model lifecycle with a controllable provider: transitions, success, failures, duplicates, cancelling, disk space, recording priority (`ModelManagerTests`); selection, including the first model being selected, and removal (`ModelSelectionTests`); restarts, external changes, damaged and interrupted files, the offline catalog (`ModelManagerRecoveryTests`); state rules and the recommendation (`ModelInstallStateTests`).
- The real file boundary on temporary folders laid out as WhisperKit's downloader leaves them: verification, hashes, partial files, what removal may touch, hostile identifiers and manifest paths; repository listings with the network replaced; error translation (`ModelFileStoreTests`).
- Settings persistence, the registry file, preferences and bundle metadata (`SettingsPersistenceTests`), the models tab (`ModelSettingsViewModelTests`) and the live Settings view model and its scenarios (`SettingsViewModelTests`).
- Transcript rules, job states and export formats (`TranscriptDomainTests`).
- Transcripts and jobs on real databases: atomic replacement, restarts, status, orphans, migration (`SQLiteTranscriptRepositoryTests`).
- The queue with inference replaced: lifecycle, duplicates, order, models (`ProcessingCoordinatorTests`), failures, cancelling, re-transcribing, leaving the Library (`ProcessingFailureTests`), restarts, recording priority, automatic queuing (`ProcessingRecoveryTests`).
- The real decoder and chunker on media written for the test: layout, offsets, silence, bounded blocks, chunk order (`RecordingAudioReaderTests`).
- The Viewer and Library on real jobs: display, highlight and seeking, following, export, status and actions (`TranscriptPresentationTests`).
- Real recognition with a model on this Mac, off unless asked for, as described in the [README](../README.md#transcription) (`WhisperEndToEndTests`).
- Summary rules: batching, settings ranges and presets, the catalog, out-of-date summaries, cleaning replies (`SummaryDomainTests`); batching and combining with generation replaced (`TranscriptSummarizerTests`); the queue on real databases: storing, failures, recording priority, waiting for transcription, cancelling, removal (`SummaryCoordinatorTests`); the tables (`SQLiteSummaryRepositoryTests`); presets, customizing, resetting, stored settings and the Settings view model (`SummarySettingsTests`); the language model folder on real files (`LanguageModelFileStoreTests`); the generic model lifecycle on the language catalog (`LanguageModelManagerTests`); a real model downloaded and run, off unless asked for (`SummaryEndToEndTests`); queuing a summary after transcription and telling indexing (`SummaryCoordinatorTests`).
- Search rules: chunking transcripts and summaries, rank fusion, full-text expressions, the vector matrix and its stored form (`SearchIndexDomainTests`); the index on real databases: outdated recordings, full-text search in Russian and English, nearest vectors with date and tag filters, replaced chunks and their vectors, other models' vectors, removed recordings (`SQLiteSearchIndexRepositoryTests`); the indexing queue with a fake embedder: chunking and embedding, waiting for transcription and summaries, catching up once a model is ready, summaries without embedding the transcript again, recording priority, failures, removal; and hybrid search with and without a model and while recording (`IndexingCoordinatorTests`); a real embedding model downloaded and run, off unless asked for (`EmbeddingEndToEndTests`).
- The MCP server: links, settings, tokens and the HTTP reader (`RecordingLinkTests`, `AgentServerSettingsTests`, `HTTPRequestParserTests`); what agents read on real databases: listing with filters and pages, unknown tags, where each step stands, summaries, transcript windows, cuts and reading around a search result, search by tag (`RecordingKnowledgeServiceTests`); the endpoint: token, host and origin checks, methods, version negotiation, notifications, errors and every tool's results (`MCPEndpointTests`); the controller with a fake host: first launch, on and off, quick changes, new port and token, failures and retry, stored settings, the Settings tab (`AgentServerControllerTests`); the real server on a free loopback port and a port in use (`MCPHTTPServerTests`).

## Not implemented yet

No search window over the index and no recovery of interrupted recordings exist yet. Summaries run only on local MLX models; no server or API backend exists. Recordings made before the Library existed, and any whose entry could not be stored, are not listed: nothing imports existing files or reads sidecars, so Add Existing Files… is hidden. Everything described in [ARCHITECTURE.md](ARCHITECTURE.md) as planned is intended future behavior.
