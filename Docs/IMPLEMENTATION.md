# Implementation Status

This document describes what exists in the code today. Target architecture, layer rules, service boundaries and planned runtime behavior are in [ARCHITECTURE.md](ARCHITECTURE.md); keep the two separate. Update this file when implemented behavior changes, and move a capability out of "Not implemented yet" only when it actually exists.

## Platform

Recorder is a macOS 15+, arm64, Swift 6 application with a SwiftUI App lifecycle, a visible Dock icon, and the Recorder window.

## Recording (implemented)

The Recorder window records for real. Screen, window and audio-only recording, pause and resume, permissions, file storage and preference restoration work; see [verification](VERIFICATION.md) for what has and has not been exercised on hardware.

| Layer | Component | Responsibility |
| --- | --- | --- |
| Presentation | `RecorderViewModel`, `RecorderSourceSelection`, `LevelPreviewController` | Settings being edited, available sources and selection, Ready-state meters, callouts. |
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

**Automatic transcription.** No processing queue exists, so no job is created. The toggle is persisted, and each recording's metadata stores `transcriptionRequested` with the neutral status `recorded`. When a queue exists, schedule from `RecordingCoordinator.saveCompleted`, after the media is safe.

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

**Search and sort.** Search looks across the library, like the design's, at titles and at dates such as `today`, `2026-11`, `Nov 4`. Filtering, sorting and sidebar counts are database queries. Newest, Oldest, Name and Duration come from the toolbar menu.

**Status.** Every new recording is stored as `recorded`, shown as “Recorded”, with no Transcribe or Retry offered and no place in the Processing section, because no processing exists.

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

**Transcript panel.** A real recording shows “No transcript available”, since nothing produces transcripts yet. No lines, waveforms or processing controls are simulated for one. Copy and Export stay disabled.

**Full screen.** The whole window enters native full screen, including the transcript panel.

## Speech models (implemented)

The AI Models tab downloads, verifies, selects and removes Whisper models. Nothing transcribes with them yet.

| Layer | Component | Responsibility |
| --- | --- | --- |
| Presentation | `ModelSettingsView`, `SpeechModelRow`, `ModelSettingsViewModel`, `ModelIssue` | The catalog, states, actions, confirmation, error wording. No file or network work. |
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

## Settings window (implemented)

| Layer | Component | Responsibility |
| --- | --- | --- |
| Presentation | `SettingsViewModel`, the tab views | Tab state, bindings, storage figures, version. |
| Application | `AppPreferences`, `ModelContracts` | The single owner of preferences; `SettingsRepository`, `LoginItemControlling`, `RecordingsStorageProviding`. |
| Infrastructure | `UserDefaultsSettingsRepository`, `SMAppServiceLoginItem` | Persistence and the system's login item. |

**General.** Launch at Login uses `SMAppService`, and the system stays the source of truth: its state is read back, and approval pending in System Settings is shown with a button to get there. Show Menu Bar Icon controls the item shown while recording; the Dock badge stays. The Dock click opens the Recorder or the Library, and a recording always brings back the Recorder. Choosing Quit makes closing the Recorder window quit the app, waiting for any recording to be stopped and saved.

**Storage.** The recordings folder and its free space, the number and size of tracked recordings, and the space models use, all real. Change… goes through `RecorderViewModel`, as the Recorder's footer does, so both show the same folder and existing recordings stay where they are.

**About.** Version and build from the bundle. The licenses list names what the app actually ships, and each row opens its published text.

**Semantic Search.** A static section saying it isn't available yet: no embedding model is installed and no index is built.

**Left out because nothing backs them yet.** Notify When Processing Finishes, Transcription Language, Postpone on Battery Power, Check for Updates and its automatic toggle, moving existing recordings, Preview Cache, Search Index and Missing Recordings figures. They return as their features do.

## Windows (design scenarios)

The Viewer and the Library keep design scenarios on simulated state beside the real windows. Each feature has a `Preview` directory with fixed sample data and a scenario type that selects it.

- **Recorder design scenarios.** `RecorderPreviewScenario` and `RecorderPreviewState` still show the Recorder's design states with sample data, for SwiftUI previews and review. They never touch capture and do not change saved preferences.
- **Library scenarios.** With a `LibraryPreviewScenario`, `LibraryViewModel` filters, sorts, searches and removes sample recordings from `Features/Library/Preview` and touches nothing on disk. `SimulatedLibrarySearch` stands in for full-text and semantic search. Opening a sample recording goes to the Viewer's simulated state.
- **Viewer scenarios.** With a `ViewerPreviewScenario`, `ViewerViewModel` runs a simulated clock over sample transcripts and draws sample frames and waveforms, and touches neither media nor the Library, following the same pattern.
- **Settings scenarios.** Unlike the others, `SettingsViewModel` has no preview branches: a scenario swaps its dependencies for `SettingsViewModel.Dependencies.preview(for:)`, which runs the real `ModelManager` on a simulated provider, with in-memory preferences and fixed storage figures. It touches nothing on disk or the network, and **Live** in the Debug menu swaps back.

## App integration

App holds the AppKit integration:

- `AppComposition` creates the recording, library, playback and model services, preferences, the Recorder, Library, Viewer and Settings view models, and the Viewer's video surface.
- `AppDelegate` holds those, builds the Dock menu and quit confirmation, compares models with the disk at launch (no download or loading), and acts on the Dock click and window close preferences.
- `RecordingIndicators` observes recording state and the menu bar preference to show the menu bar item and Dock badge.
- `WindowNavigator` lets those AppKit menus open SwiftUI windows.
- The Debug menu lives in `App/DebugCommands.swift`.
- Dock activation reopens the Recorder window, or the Library if chosen in Settings. The Dock menu, menu bar item and quit confirmation act on the real recording.
- The app is a regular Dock application with the SwiftUI App lifecycle; no `LSUIElement` agent mode or custom Dock UI is configured.

## Shared UI

Shared design tokens and reusable controls live in `Shared/Design` and `Shared/Components`.

## Models and dependencies

Recording is a Codable, Sendable metadata value with an identifier, creation date, nonblank title, finite nonnegative duration, and processing status. `RecordingMetadata` adds its files, sources and completion, and `LibraryRecording` adds its media reference and size. Database rows are validated when read; the sidecar is not read, and its synthesized Codable provides round trips only.

The app target links WhisperKit and SQLiteVecStore but does not instantiate either: `WhisperModelProvider` uses only WhisperKit's static model APIs and its Hub client. The Library uses the system `SQLite3` directly.

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

## Not implemented yet

No transcription, embedding models, processing workers, transcripts or recovery of interrupted recordings exist yet. Speech models can be installed but nothing uses them. Recordings made before the Library existed, and any whose entry could not be stored, are not listed: nothing imports existing files or reads sidecars, so Add Existing Files… is hidden. Everything described in [ARCHITECTURE.md](ARCHITECTURE.md) as planned is intended future behavior.
