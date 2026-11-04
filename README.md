# Recorder

A native Swift 6 / SwiftUI macOS screen recorder. The Recorder window records screens, windows and audio with ScreenCaptureKit and AVFoundation, keeping microphone and system audio as separate tracks. The app also has the designed Library, Viewer and Settings windows (layout only, with simulated state), a Dock menu, menu bar recording indicator and app icon, and Swift Testing coverage. Real playback, a recordings library, transcription, embeddings, search, and processing workers are planned and are not implemented.

## Requirements

- Apple Silicon Mac running macOS 15 or later.
- Full Xcode 16 or later with Swift 6 and the macOS SDK. Verified versions are recorded in [verification](Docs/VERIFICATION.md).
- Homebrew for SwiftLint (and swift-format if missing from the selected toolchain).

Select your full Xcode installation using `xcode-select` if needed; accept its license and complete first launch. No development Team ID is committed.

## Documentation before coding

Before writing or changing code, read [AGENTS.md](AGENTS.md), this README, the [Software Architecture Guidelines](Docs/SOFTWARE_ARCHITECTURE_GUIDELINES.md), the [Project Architecture](Docs/ARCHITECTURE.md), the [Implementation Status](Docs/IMPLEMENTATION.md), and [Swift Code Style](Docs/CODE_STYLE.md). The guidelines define Lightweight Clean Architecture with MVVM; the project architecture records its application here and planned runtime behavior. Code style defines readability within individual files. Review relevant existing code and tests before implementation, and update documentation when behavior or architectural decisions change.

## Development

```sh
make setup
open Recorder.xcodeproj
make build
make test
make format
make lint
make format-check
make check
```

`make setup` checks Xcode and architecture, installs missing formatting/lint tools via Homebrew, and resolves packages. The checked-in `.xcodeproj` and shared Recorder scheme need no project generator. Build and test use `xcodebuild`, Debug, arm64, and signing disabled; products go into ignored `DerivedData/`. In Xcode select the Recorder scheme and My Mac, then Run. Use automatic signing with your own development team when signed development is needed. Distribution signing is not configured.

`make format` uses Apple's official swift-format. `make lint` runs strict SwiftLint source linting. The `unused_import` analyzer rule is configured; it additionally requires `swiftlint analyze --compiler-log-path <clean-xcodebuild-log>` because ordinary source linting cannot determine import usage. Format and lint before submitting changes.

## Dependencies

Swift Package Manager is configured directly in Xcode. Exact releases are pinned:

- [argmax-oss-swift 1.1.1](https://github.com/argmaxinc/argmax-oss-swift/tree/v1.1.1): only the `WhisperKit` product.
- [SQLiteVecKit 0.1.1](https://github.com/carlosypunto/SQLiteVecKit/tree/0.1.1): `SQLiteVecStore` product.

Commit `Recorder.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` when updating packages. Initial resolution needs network access for package source; tests need no network, permissions, media, models, or databases. No AI model weights are bundled, downloaded, or loaded, and no database is opened on startup. Import smoke tests check the libraries without initializing engines.

Apple frameworks are supplied by the macOS SDK: ScreenCaptureKit, AVFoundation, AVKit, CoreMedia, CoreAudio, CoreML, Accelerate, and AppKit. Future features should import them where used; Swift autolinking handles framework linkage.

## Organization

- `Recorder/Features/Recording`: the Recorder window (views, `RecorderViewModel`) and, under `Preview`, the sample data and scenarios for reviewing its design states.
- `Recorder/Application`: `RecordingCoordinator`, which owns the recording lifecycle, and the contracts Infrastructure implements.
- `Recorder/Infrastructure`: capture and media output, recording files and metadata, preferences, permissions.
- `Recorder/Features/Library`: the Library window (views, `LibraryViewModel`) and, under `Preview`, its sample recordings, simulated search and scenarios.
- `Recorder/Features/Viewer` and `Recorder/Features/Settings`: the Viewer and Settings windows, each with view models and `Preview` sample data and scenarios.
- `Recorder/App`: the composition root (`AppComposition`) and AppKit integration: `AppDelegate` (Dock menu, quit confirmation, holder of the Recorder view model), `RecordingIndicators` (menu bar item and Dock badge while recording), `RecordingMenus`, `WindowNavigator` (opens SwiftUI windows from AppKit menus), and the Debug menu.
- `Recorder/Shared`: design tokens (colors, icons, focus ring) and reusable components such as buttons, switches, segmented controls, callout banners and level meters.
- `Recorder/Models`: value types and validation.
- `Recorder/Resources`: asset catalog and future app resources.
- `RecorderTests`: Swift Testing model and dependency smoke tests.
- [Software Architecture Guidelines](Docs/SOFTWARE_ARCHITECTURE_GUIDELINES.md): layer responsibilities, dependency rules, MVVM, injection, state, concurrency, and testing.
- [Architecture](Docs/ARCHITECTURE.md): target layers and service boundaries, runtime constraints, permissions, and storage.
- [Implementation Status](Docs/IMPLEMENTATION.md): what is implemented today and what is still simulated or missing.
- [Swift Code Style](Docs/CODE_STYLE.md): file layout, naming, functions, control flow, comments, and review checklist.
- [AGENTS.md](AGENTS.md): shared coding rules.

Add directories only when they contain real code. Recorder/Models holds the Domain types.

## Recording

Recordings go to `~/Movies/Verbatim` by default, one folder per recording: `2026-11-04_120000_<uuid>/recording.mov` and `recording.json`. Click the folder line at the bottom of the Recorder to open it in Finder, or right-click it to choose another folder. macOS asks for Screen Recording and Microphone access when a recording first needs them. To test permissions, run a build signed with your own development team; the unsigned builds from `make build` do not exercise the sandbox.

Details are in [Implementation Status](Docs/IMPLEMENTATION.md).

## Recorder window design states

The Recorder's “01 Recorder” design states can be reviewed with sample data and no capture. Choose a state with the launch argument `-RecorderPreviewScenario <state>` (Xcode: Product › Scheme › Edit Scheme › Arguments), from **Debug › Recorder State** in Debug builds, or in the SwiftUI previews of `RecorderWindowView`. **Debug › Recorder State › Live** returns to real capture. States: `idle`, `picker`, `recording`, `permission`, `mic`, `source`, `folder`, `disk`, `saved`. The window follows the system Light or Dark appearance and accent color.

## Library window preview states

The Library window implements the “02 Library” design without storage or processing: recordings, processing progress, search results, removal and deletion are simulated, Open Recording, Open Transcript and search moments open the Viewer, New Recording brings back the Recorder, and Finder actions are not connected yet. Choose a state with `-LibraryPreviewScenario <state>`, which also opens the window at launch, from **Debug › Library State** in Debug builds, or in the SwiftUI previews of `LibraryWindowView`. States: `list`, `processing`, `search`, `context`, `confirm`, `empty`. In the search field, try “maya”, “search” or “budget”.

Both windows follow the system appearance and accent color. To review the design's accent tweak, pass `-VerbatimAccent blue|indigo|teal|graphite` or use **Debug › Accent Color**; **Debug › Appearance** switches Light and Dark.

## Viewer window preview states

The Viewer implements the “03 Viewer” design without media: playback, waveforms, transcript, search matches and processing are simulated. Choose a state with `-ViewerPreviewScenario <state>`, which also opens the window at launch, from **Debug › Viewer State**, or in the SwiftUI previews of `ViewerWindowView`. States: `video`, `search`, `audio`, `processing`, `failed`, `unprocessed`. Space plays or pauses, Left and Right skip 15 s, Return or ⌘G steps through transcript matches, and ⌘[ returns to the Library.

## Dock and menu bar

The app has the design's icon (“04 Dock”). Clicking the Dock icon brings back the Recorder, never the Library; only the Recorder opens at launch. The Dock menu offers New Recording, Open Recorder, Recordings Library and Settings…; while recording it starts with the live timer and offers Stop Recording, and the Dock icon gets a red badge. While recording, a menu bar item shows a red dot and the elapsed time, with Pause/Resume, Stop, Open Recorder and Recordings Library. Quitting during a recording asks first (Stop and Quit or Keep Recording), and Stop and Quit waits until the file is finished. Try the look with `-RecorderPreviewScenario recording` or **Debug › Recorder State › Recording**; on a notched display with a full menu bar, macOS may hide the item.

## Settings window preview states

The Settings window implements the “05 Settings” design in the native Settings scene (⌘, or the Recorder's gear) without real models, storage or updates: downloads, model preparation, index building and the update check are simulated while the window is open, and storage figures are sample data. No model is downloaded or loaded. Choose a state with `-SettingsPreviewScenario <state>`, which also opens Settings at launch, from **Debug › Settings State**, or in the SwiftUI previews of `SettingsWindowView`. States: `general`, `models`, `removeModel`, `storage`, `moveRecordings`, `about`, `licenses`.

Keyboard: in the list, Up and Down move the selection, Return opens, Delete (or ⌘⌫) asks to delete, and Escape closes the actions menu. The menu takes focus when it opens (Up, Down, Return, Escape). Escape cancels the delete sheet, and Edit › Undo (⌘Z) restores a recording removed from the Library.
