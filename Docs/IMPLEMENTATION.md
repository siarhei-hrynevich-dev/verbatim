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

## Windows (layout only)

Settings is layout only and runs on simulated state, as do the design scenarios of the Viewer and the Library. Each feature has a `Preview` directory with fixed sample data and a scenario type that selects it.

- **Recorder design scenarios.** `RecorderPreviewScenario` and `RecorderPreviewState` still show the Recorder's design states with sample data, for SwiftUI previews and review. They never touch capture and do not change saved preferences.
- **Library scenarios.** With a `LibraryPreviewScenario`, `LibraryViewModel` filters, sorts, searches and removes sample recordings from `Features/Library/Preview` and touches nothing on disk. `SimulatedLibrarySearch` stands in for full-text and semantic search. Opening a sample recording goes to the Viewer's simulated state.
- **Viewer scenarios.** With a `ViewerPreviewScenario`, `ViewerViewModel` runs a simulated clock over sample transcripts and draws sample frames and waveforms, and touches neither media nor the Library, following the same pattern.
- **Settings.** `SettingsViewModel` with simulated downloads owned by a cancellable task that runs while the window is open, following the same pattern with its own `Preview` scenarios.

Real downloads will need Application services that outlive windows; the current simulations do not. The Settings window's recordings location is still simulated and is not connected to the Recorder's folder.

## App integration

App holds the AppKit integration:

- `AppComposition` creates the recording, library and playback services, the Recorder, Library and Viewer view models, and the Viewer's video surface.
- `AppDelegate` holds those and builds the Dock menu and quit confirmation.
- `RecordingIndicators` observes recording state to show the menu bar item and Dock badge.
- `WindowNavigator` lets those AppKit menus open SwiftUI windows.
- The Debug menu lives in `App/DebugCommands.swift`.
- Dock activation reopens the Recorder window. The Dock menu, menu bar item and quit confirmation act on the real recording.
- The app is a regular Dock application with the SwiftUI App lifecycle; no `LSUIElement` agent mode or custom Dock UI is configured.

## Shared UI

Shared design tokens and reusable controls live in `Shared/Design` and `Shared/Components`.

## Models and dependencies

Recording is a Codable, Sendable metadata value with an identifier, creation date, nonblank title, finite nonnegative duration, and processing status. `RecordingMetadata` adds its files, sources and completion, and `LibraryRecording` adds its media reference and size. Database rows are validated when read; the sidecar is not read, and its synthesized Codable provides round trips only.

The app target links WhisperKit and SQLiteVecStore but does not instantiate either. The Library uses the system `SQLite3` directly.

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
- Presentation logic of the Recorder's design scenarios and the Library, Viewer and Settings view models against their simulated data (`RecorderViewModelTests`, `LibraryViewModelTests`, `ViewerViewModelTests`, `SettingsViewModelTests`).
- Dock and menu bar menu construction (`RecordingMenusTests`).

## Not implemented yet

No models, processing workers, transcripts or recovery of interrupted recordings exist yet. The Settings window is a designed layout driven by simulated data, as are the Viewer's design scenarios. Recordings made before the Library existed, and any whose entry could not be stored, are not listed: nothing imports existing files or reads sidecars, so Add Existing Files… is hidden. The Settings window's storage figures are still samples. Everything described in [ARCHITECTURE.md](ARCHITECTURE.md) as planned is intended future behavior.
