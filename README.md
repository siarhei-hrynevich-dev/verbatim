# Recorder

A native Swift 6 / SwiftUI macOS screen recorder foundation. Initialization includes a normal Dock app with one placeholder window, validated recording metadata, and Swift Testing coverage. Capture, playback, library UI, transcription, embeddings, search, and processing workers are planned and are not implemented.

## Requirements

- Apple Silicon Mac running macOS 15 or later.
- Full Xcode 16 or later with Swift 6 and the macOS SDK. Verified versions are recorded in [verification](Docs/VERIFICATION.md).
- Homebrew for SwiftLint (and swift-format if missing from the selected toolchain).

Select your full Xcode installation using `xcode-select` if needed; accept its license and complete first launch. No development Team ID is committed.

## Documentation before coding

Before writing or changing code, read [AGENTS.md](AGENTS.md), this README, the [Software Architecture Guidelines](Docs/SOFTWARE_ARCHITECTURE_GUIDELINES.md), the [Project Architecture](Docs/ARCHITECTURE.md), and [Swift Code Style](Docs/CODE_STYLE.md). The guidelines define Lightweight Clean Architecture with MVVM; the project architecture records its application here and planned runtime behavior. Code style defines readability within individual files. Review relevant existing code and tests before implementation, and update documentation when behavior or architectural decisions change.

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

- `Recorder/App`: minimal presentation.
- `Recorder/Models`: value types and validation.
- `Recorder/Resources`: asset catalog and future app resources.
- `RecorderTests`: Swift Testing model and dependency smoke tests.
- [Software Architecture Guidelines](Docs/SOFTWARE_ARCHITECTURE_GUIDELINES.md): layer responsibilities, dependency rules, MVVM, injection, state, concurrency, and testing.
- [Architecture](Docs/ARCHITECTURE.md): current scaffold, planned layers and service boundaries, runtime constraints, permissions, and storage.
- [Swift Code Style](Docs/CODE_STYLE.md): file layout, naming, functions, control flow, comments, and review checklist.
- [AGENTS.md](AGENTS.md): shared coding rules.

Add feature directories for Presentation and Application, Domain, and Infrastructure directories when they contain real code. Recorder/Models currently holds the initial domain value type. The placeholder window intentionally has no final design or recording controls.
