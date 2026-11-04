# Implementation Status

This document describes what exists in the code today. Target architecture, layer rules, service boundaries and planned runtime behavior are in [ARCHITECTURE.md](ARCHITECTURE.md); keep the two separate. Update this file when implemented behavior changes, and move a capability out of "Not implemented yet" only when it actually exists.

## Platform

Recorder is a macOS 15+, arm64, Swift 6 application with a SwiftUI App lifecycle, a visible Dock icon, and the Recorder window.

## Windows (layout only)

All windows are layout only and run on simulated state. Each feature has a `Preview` directory with fixed sample data and a scenario type that selects it.

- **Recorder.** `RecorderViewModel` holds presentation state and simulates recording, issues and audio levels from sample data in `Features/Recording/Preview`, selectable through `RecorderPreviewScenario`. It performs no capture, permission checks, storage or processing.
- **Library.** `LibraryViewModel` filters, sorts, searches and removes sample recordings from `Features/Library/Preview`, selectable through `LibraryPreviewScenario`. `SimulatedLibrarySearch` stands in for full-text and semantic search. Navigation, Finder and processing actions are injected closures (`LibraryWindowActions`) that App leaves unconnected. `LibraryItem` is a presentation model; it should be mapped from Domain recordings once persistence exists.
- **Viewer.** `ViewerViewModel` with simulated playback and transcript, following the same pattern with its own `Preview` scenarios.
- **Settings.** `SettingsViewModel` with simulated downloads owned by a cancellable task that runs while the window is open, following the same pattern with its own `Preview` scenarios.

Real downloads and recording will need Application services that outlive windows; the current simulations do not.

## App integration

App holds the AppKit integration:

- `AppDelegate` owns the Recorder view model and builds the Dock menu and quit confirmation.
- `RecordingIndicators` observes recording state to show the menu bar item and Dock badge.
- `WindowNavigator` lets those AppKit menus open SwiftUI windows.
- The Debug menu lives in `App/DebugCommands.swift`.
- Dock activation reopens the Recorder window. The Dock menu, menu bar item and quit confirmation work against the simulated Recorder state.
- The app is a regular Dock application with the SwiftUI App lifecycle; no `LSUIElement` agent mode or custom Dock UI is configured.

## Shared UI

Shared design tokens and reusable controls live in `Shared/Design` and `Shared/Components`.

## Models and dependencies

Recording is a Codable, Sendable metadata value with an identifier, creation date, nonblank title, finite nonnegative duration, and processing status. Persistence decoding will need to validate untrusted stored data; synthesized Codable currently provides round trips only.

The app target links WhisperKit and SQLiteVecStore but does not instantiate either.

## Tests

Swift Testing suites in `RecorderTests` cover:

- `Recording` validation and status serialization (`RecordingTests`).
- Package imports (`DependencySmokeTests`).
- Presentation logic of the Recorder, Library, Viewer and Settings view models against their simulated data (`RecorderViewModelTests`, `LibraryViewModelTests`, `ViewerViewModelTests`, `SettingsViewModelTests`).
- Dock and menu bar menu construction (`RecordingMenusTests`).

## Not implemented yet

No capture engine, permission prompts, production database, models, workers, repositories, or real player exists yet. The Recorder, Library, Viewer and Settings windows are designed layouts driven by simulated data, not connected to real functionality. Everything described in [ARCHITECTURE.md](ARCHITECTURE.md) as planned is intended future behavior.
