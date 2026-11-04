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
| Infrastructure | `FileRecordingStore`, `UserDefaultsRecordingPreferencesStore`, `SystemCapturePermissions`, `WorkspaceSystemActions` | Files and metadata, preferences, permissions, System Settings and Finder. |

`AppComposition` wires these together; `AppDelegate` holds the result, so a recording continues with every window closed.

**Lifecycle.** `idle → preparing → recording → stopping → finalizing → idle`, with `failed` reachable from `preparing`, `stopping` and `finalizing`. Transitions are checked by `RecordingState.allowsTransition(to:)` and happen on the main actor before any suspension, so duplicate requests are rejected by state. A recording is reported as saved only after its file closes and `MediaValidator` confirms it is playable. Quitting during a recording waits for finalization.

**Capture.** Up to three independent producers deliver to one `CaptureSampleSink`, an actor running on the serial queue that capture callbacks use, which keeps samples in order without a task per sample:

- A video `SCStream` for a display or window, with no audio.
- A separate system audio `SCStream` on a display filter excluding nothing, so every mode records all applications' audio (excluding Verbatim's own).
- An `AVCaptureSession` for the microphone, which is why microphone-only recording needs no Screen Recording access. Its timestamps are converted to the host clock used by ScreenCaptureKit.

`MediaFileWriter` writes HEVC video and AAC audio with `AVAssetWriter`. Microphone (mono) and system audio (stereo) stay separate, named tracks. Pausing excludes the paused interval from the output timeline.

**Resolution.** 720p and 1080p fit a 1280×720 or 1920×1080 box, keep the source's aspect ratio and never upscale; Native keeps the source's physical pixels. ScreenCaptureKit sizes are in points and are multiplied by the filter's `pointPixelScale`.

**Files.** Each recording gets a new folder `yyyy-MM-dd_HHmmss_<uuid>/` holding `recording.mov` and `recording.json`, under the recordings folder: `~/Movies/Verbatim` by default (through the Movies entitlement) or a folder chosen from the footer's context menu or a callout (through a security-scoped bookmark). Audio-only recordings are also QuickTime files, because MPEG-4 audio files lose the track names that identify each source. Files are written in fragments, so an interrupted recording remains recoverable. A folder is removed only if nothing was written to it. When finalization fails, the files stay and `recording.json` is marked `incomplete`.

**Metadata.** `recording.json` is a sidecar beside the media, behind the `RecordingRepository` contract. It stands in for the planned SQLite persistence, which does not exist yet. No recovery or Library reads these files yet.

**Automatic transcription.** No processing queue exists, so no job is created. The toggle is persisted, and each recording's metadata stores `transcriptionRequested` with status `pending` or `ready`. When a queue exists, schedule from `RecordingCoordinator.saveCompleted`, after the media is safe.

**Live levels.** While recording, the session reports levels. In the Ready state, `LevelPreviewController` runs audio capture only while the setup screen is showing in the active app, and only for sources that are enabled and already permitted. macOS shows its microphone and screen recording indicators during that time.

**Sources going away.** A display or microphone that disconnects keeps its remembered selection and is selected again when it returns. A closed window is detected from its stream stopping and by a 2-second availability check. While recording, losing the video source or the only remaining source ends the recording and saves what was captured; losing one audio source continues with the rest and is reported afterwards.

**Permissions.** Nothing prompts at launch. Screen Recording is requested when starting a recording that needs it or when choosing Window mode; Microphone when starting or when turning the microphone on. Denial shows a callout with a System Settings button and a fallback.

## Windows (layout only)

Library, Viewer and Settings are layout only and run on simulated state. Each feature has a `Preview` directory with fixed sample data and a scenario type that selects it.

- **Recorder design scenarios.** `RecorderPreviewScenario` and `RecorderPreviewState` still show the Recorder's design states with sample data, for SwiftUI previews and review. They never touch capture and do not change saved preferences.
- **Library.** `LibraryViewModel` filters, sorts, searches and removes sample recordings from `Features/Library/Preview`, selectable through `LibraryPreviewScenario`. `SimulatedLibrarySearch` stands in for full-text and semantic search. Navigation, Finder and processing actions are injected closures (`LibraryWindowActions`) that App leaves unconnected. `LibraryItem` is a presentation model; it should be mapped from Domain recordings once persistence exists.
- **Viewer.** `ViewerViewModel` with simulated playback and transcript, following the same pattern with its own `Preview` scenarios.
- **Settings.** `SettingsViewModel` with simulated downloads owned by a cancellable task that runs while the window is open, following the same pattern with its own `Preview` scenarios.

Real downloads will need Application services that outlive windows; the current simulations do not. The Settings window's recordings location is still simulated and is not connected to the Recorder's folder.

## App integration

App holds the AppKit integration:

- `AppComposition` creates the recording services and the Recorder view model.
- `AppDelegate` holds the Recorder view model and builds the Dock menu and quit confirmation.
- `RecordingIndicators` observes recording state to show the menu bar item and Dock badge.
- `WindowNavigator` lets those AppKit menus open SwiftUI windows.
- The Debug menu lives in `App/DebugCommands.swift`.
- Dock activation reopens the Recorder window. The Dock menu, menu bar item and quit confirmation act on the real recording.
- The app is a regular Dock application with the SwiftUI App lifecycle; no `LSUIElement` agent mode or custom Dock UI is configured.

## Shared UI

Shared design tokens and reusable controls live in `Shared/Design` and `Shared/Components`.

## Models and dependencies

Recording is a Codable, Sendable metadata value with an identifier, creation date, nonblank title, finite nonnegative duration, and processing status. `RecordingMetadata` adds its files, sources and completion. Reading stored metadata will need to validate untrusted data; synthesized Codable currently provides round trips only.

The app target links WhisperKit and SQLiteVecStore but does not instantiate either.

## Tests

Swift Testing suites in `RecorderTests` cover:

- `Recording` validation and status serialization (`RecordingTests`).
- Package imports (`DependencySmokeTests`).
- The recording lifecycle with controllable services: transitions, invalid requests, permission, disk and capture failures, finalization and metadata failures, interruptions (`RecordingCoordinatorTests`, `RecordingCoordinatorFailureTests`).
- Configuration validation, resolution and aspect ratio, disk space rules, level scale, folder naming (`RecordingConfigurationTests`).
- Preferences and file storage against real defaults and a temporary folder (`RecordingStorageTests`).
- The real writer and validator on synthetic samples, needing no hardware: track layout and names, pause timeline, ordering, unusable output (`MediaFileWriterTests`).
- The live Recorder view model and sources going away (`RecorderViewModelLiveTests`).
- Presentation logic of the Recorder's design scenarios and the Library, Viewer and Settings view models against their simulated data (`RecorderViewModelTests`, `LibraryViewModelTests`, `ViewerViewModelTests`, `SettingsViewModelTests`).
- Dock and menu bar menu construction (`RecordingMenusTests`).

## Not implemented yet

No production database, models, processing workers, recovery of interrupted recordings, or real player exists yet. The Library, Viewer and Settings windows are designed layouts driven by simulated data; the Library does not list real recordings. Everything described in [ARCHITECTURE.md](ARCHITECTURE.md) as planned is intended future behavior.
