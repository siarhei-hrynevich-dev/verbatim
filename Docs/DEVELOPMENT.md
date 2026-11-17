# Development

How to build, test and work on Verbatim. For what the app does, see the [README](../README.md); for the rules every change follows, see [AGENTS.md](../AGENTS.md) and [CONTRIBUTING.md](../CONTRIBUTING.md).

## Overview

Verbatim is a native Swift 6 / SwiftUI macOS screen recorder. The Recorder window records screens, windows and audio with ScreenCaptureKit and AVFoundation, keeping microphone and system audio as separate tracks. The Library window tracks finished recordings in a local SQLite database: history, renaming, title and date search, sorting, tags, Finder actions, removal, deletion to the Trash, and missing-file handling. The Viewer window plays recordings with AVFoundation and AVKit: video and audio-only, with seeking, volume, speed, full screen, Finder actions and recovery from missing or damaged files. The Settings window manages local models: browse, download, verify, select and remove them.

Recordings are transcribed offline with the selected Whisper model, automatically when a recording ends or on request, through a durable queue that always gives way to recording; transcripts show in the Viewer in step with playback and are saved beside the media as TXT, SRT and JSON. A local language model, downloaded and selected in Settings like the Whisper models and run with MLX, summarizes each new transcript, or one on request, in batches, keeping the notes on each part. Transcripts and summaries are then indexed for search: chunks with an FTS5 full-text index, and vectors from a local multilingual embedding model, for search by meaning and words, which a local MCP server offers to AI agents on this Mac when turned on in Settings. The app also has a Dock menu, menu bar recording indicator and app icon, and Swift Testing coverage.

What exists today, component by component, is in [Implementation Status](IMPLEMENTATION.md); the target design is in [Architecture](ARCHITECTURE.md).

## Requirements and toolchain

- Apple Silicon Mac running macOS 15 or later.
- Full Xcode 26 or later with Swift 6.2 and the macOS SDK, and its Metal Toolchain component, which MLX needs to compile its shaders (`make setup` installs it with `xcodebuild -downloadComponent MetalToolchain`).
- Homebrew for SwiftLint (and swift-format if missing from the selected toolchain).

Select your full Xcode installation using `xcode-select` if needed; accept its license and complete first launch. No development Team ID is committed.

## Documentation before coding

Before writing or changing code, read [AGENTS.md](../AGENTS.md), this document, the [Software Architecture Guidelines](SOFTWARE_ARCHITECTURE_GUIDELINES.md), the [Project Architecture](ARCHITECTURE.md), the [Implementation Status](IMPLEMENTATION.md), and [Swift Code Style](CODE_STYLE.md). The guidelines define Lightweight Clean Architecture with MVVM; the project architecture records its application here and planned runtime behavior. Code style defines readability within individual files. Review relevant existing code and tests before implementation, and update documentation when behavior or architectural decisions change.

## Make targets

```sh
make setup
open Verbatim.xcodeproj
make build
make test
make format
make lint
make format-check
make check
```

| Target | What it does |
| --- | --- |
| `make setup` | Checks Xcode and the architecture, installs missing SwiftLint and swift-format via Homebrew, installs the Metal Toolchain if missing, and resolves packages. |
| `make build` | Debug build for arm64 with `xcodebuild`, signing disabled. The default target. |
| `make test` | Runs the Swift Testing suites with `xcodebuild`, signing disabled. |
| `make format` | Formats `Verbatim` and `VerbatimTests` in place with swift-format. |
| `make format-check` | Checks formatting without changing files. |
| `make lint` | Strict SwiftLint source linting. |
| `make check` | `format-check`, `lint`, `build` and `test`, in that order. |

The checked-in `.xcodeproj` and shared Verbatim scheme need no project generator. Build and test use `xcodebuild`, Debug, arm64, and signing disabled; products go into ignored `DerivedData/`. In Xcode select the Verbatim scheme and My Mac, then Run.

## Continuous integration

[`.github/workflows/ci.yml`](../.github/workflows/ci.yml) runs on every pull request, on pushes to `main`, and on demand. It uses GitHub's arm64 `macos-26` runner with Xcode 26.3 selected explicitly (Swift 6.2, the toolchain the sources are formatted and built with), and runs the same targets as `make check`: `make setup`, then `make format-check`, `make lint`, `make build` and `make test`. Swift package checkouts are cached by the hash of `Package.resolved`. When a step fails, the build and test logs and the `.xcresult` bundle from `DerivedData/Logs` are uploaded as a workflow artifact.

To reproduce a CI run locally, select Xcode 26.3 and run:

```sh
make setup
make check
```

When moving to a newer Xcode, update `XCODE_VERSION` in the workflow in the same change, and run `make format` with that Xcode's swift-format.

## Signing

Use automatic signing with your own development team when signed development is needed, and do not commit it. Distribution signing is not configured: release builds are not signed with a Developer ID and not notarized. The unsigned builds from `make build` do not exercise the sandbox, so test permissions with a build signed with your own development team.

## Formatting and linting

`make format` uses Apple's official swift-format. `make lint` runs strict SwiftLint source linting. The `unused_import` analyzer rule is configured; it additionally requires `swiftlint analyze --compiler-log-path <clean-xcodebuild-log>` because ordinary source linting cannot determine import usage. Format and lint before submitting changes.

## Dependencies

Swift Package Manager is configured directly in Xcode. Exact releases are pinned:

- [argmax-oss-swift 1.1.1](https://github.com/argmaxinc/argmax-oss-swift/tree/v1.1.1): only the `WhisperKit` product.
- [SQLiteVecKit 0.1.1](https://github.com/carlosypunto/SQLiteVecKit/tree/0.1.1): `SQLiteVecStore` product.
- [mlx-swift-lm 3.31.4](https://github.com/ml-explore/mlx-swift-lm/tree/3.31.4): `MLXLLM`, `MLXEmbedders` and `MLXLMCommon`, and [mlx-swift 0.31.4](https://github.com/ml-explore/mlx-swift/tree/0.31.4): `MLX`, for running language and embedding models. Later releases need Swift tools 6.3.
- [swift-transformers 1.4.0](https://github.com/huggingface/swift-transformers/tree/1.4.0): `Tokenizers`, which reads a language model's tokenizer from its folder.

Commit `Verbatim.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` when updating packages, and update [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) and the in-app list in `ThirdPartyLicense.shipped` (`Verbatim/Features/Settings/SettingsOptions.swift`) to match. Initial resolution needs network access for package source; tests need no network, permissions, or models, and use only temporary databases, files and media they create. No AI model weights are bundled, and they are downloaded only when the user asks in Settings. Models load only for the work that needs them and are released when their queue runs out. At launch the transcription queue reads its jobs from the Library's database, which is otherwise opened on first use. It uses the system `SQLite3`, the library SQLiteVecKit also links; `VectorStore` itself is not used, because it freezes an embedding dimension into the database file. Vectors are stored as BLOBs in the app's own tables and searched in memory; see [Architecture](ARCHITECTURE.md#search-index). Import smoke tests check the libraries without initializing engines.

Apple frameworks are supplied by the macOS SDK: ScreenCaptureKit, AVFoundation, AVKit, CoreMedia, CoreAudio, CoreML, Accelerate, and AppKit. Future features should import them where used; Swift autolinking handles framework linkage.

## Project organization

- `Verbatim/Features/Recording`: the Recorder window (views, `RecorderViewModel`) and, under `Preview`, the sample data and scenarios for reviewing its design states.
- `Verbatim/Application`: `RecordingCoordinator`, which owns the recording lifecycle, `RecordingKnowledgeService` and `AgentServerController`, which own what AI agents can read and the MCP server, `LibraryService`, which owns the library's use cases, `ModelManager`, which owns the state of one kind of model (speech, language or embedding), `ProcessingCoordinator`, which owns the transcription queue, `SummaryCoordinator` and `TranscriptSummarizer`, which own summaries, `IndexingCoordinator` and `RecordingSearchService`, which own the search index and searching it, `AppPreferences` and `SummaryPreferences`, and the contracts Infrastructure implements, including `PlaybackService`, `ModelFileProviding`, `TranscriptionService`, `TextGenerator`, `TextEmbedder` and `SearchIndexRepository`.
- `Verbatim/Infrastructure`: capture and media output, playback, the SQLite database, recording files and thumbnails, the WhisperKit adapters (`SpeechModels`, `Transcription`), Hugging Face model downloads for language and embedding models (`LanguageModels`), the MLX adapters (`Summarization`, `Embeddings`), the search index (`Persistence`), the MCP server (`AgentServer`), preferences, permissions, login item.
- `Verbatim/Features/Library`: the Library window (views, `LibraryViewModel`) and, under `Preview`, its sample recordings, simulated search and scenarios.
- `Verbatim/Features/Viewer`: the Viewer window, the app's player (views, `ViewerViewModel`) and, under `Preview`, its sample data and scenarios.
- `Verbatim/Features/Settings`: the Settings window (views, `SettingsViewModel`, `ModelSettingsViewModel`) and, under `Preview`, sample dependencies with simulated downloads, and scenarios.
- `Verbatim/App`: the composition root (`AppComposition`) and AppKit integration: `AppDelegate` (Dock menu, quit confirmation, holder of the Recorder view model), `RecordingIndicators` (menu bar item and Dock badge while recording), `RecordingMenus`, `WindowNavigator` (opens SwiftUI windows from AppKit menus), and the Debug menu.
- `Verbatim/Shared`: design tokens (colors, icons, focus ring) and reusable components such as buttons, switches, segmented controls, callout banners and level meters, and `AppIdentity`, which reads the bundle identifier (set only in the build settings) for log subsystems and queue labels.
- `Verbatim/Models`: value types and validation.
- `Verbatim/Resources`: asset catalog and future app resources.
- `VerbatimTests`: Swift Testing model and dependency smoke tests.
- [Software Architecture Guidelines](SOFTWARE_ARCHITECTURE_GUIDELINES.md): layer responsibilities, dependency rules, MVVM, injection, state, concurrency, and testing.
- [Architecture](ARCHITECTURE.md): target layers and service boundaries, runtime constraints, permissions, and storage.
- [Implementation Status](IMPLEMENTATION.md): what is implemented today and what is still simulated or missing.
- [Swift Code Style](CODE_STYLE.md): file layout, naming, functions, control flow, comments, and review checklist.
- [AGENTS.md](../AGENTS.md): shared coding rules.

Add directories only when they contain real code. Verbatim/Models holds the Domain types.

## Recording

Recordings go to `~/Movies/Verbatim` by default, one folder per recording: `2026-11-04_120000_<uuid>/recording.mov` and `recording.json`. Click the folder line at the bottom of the Recorder to open it in Finder, or right-click it to choose another folder. macOS asks for Screen Recording and Microphone access when a recording first needs them. To test permissions, run a build signed with your own development team; the unsigned builds from `make build` do not exercise the sandbox.

Details are in [Implementation Status](IMPLEMENTATION.md#recording-implemented).

## Transcription

With **Transcribe when recording ends** on, a finished recording joins the queue once its media is safe. Otherwise use Transcribe in the Library or Generate Transcript in the Viewer; Retry and Re-transcribe appear as they apply. Transcription uses the model selected in Settings › AI Models › Speech Recognition and the Transcription Language chosen in Settings › AI Models › Processing, automatic by default. Nothing is downloaded for it, and if no usable model is selected, the recording shows why with a way to Settings. Starting a recording stops the running job, which starts over when the recording ends. Details are in [Implementation Status](IMPLEMENTATION.md#transcription-implemented).

## Summaries

A new transcript is summarized by itself when a summary model is installed and selected. In the Viewer, switch the side panel to **Summary** and choose Summarize. The model selected in Settings › AI Models › Summaries reads the transcript in batches, writes notes on each, and combines them into a short summary in the Summary Language chosen in Settings › AI Models › Processing, whatever language was spoken (by default the Mac's own when it is offered, otherwise English); the notes on each part are kept, with the time span they cover, and selecting a part's time plays from there. After the summary, the model suggests a title, which replaces the recording's generated default title only, never one you typed. Nothing is downloaded for it, and summaries stop while recording and wait for transcription. Settings › AI Models › Summary Settings uses each model's recommended values; turn on Customize Settings to change batch sizes and sampling, and Reset to Recommended to go back. Details are in [Implementation Status](IMPLEMENTATION.md#summaries-implemented).

## Search index

After each transcript, and after each summary, the recording is indexed for search: its text is split into chunks with a full-text index, and the embedding model selected in Settings › AI Models › Semantic Search adds a vector to each chunk, for search by meaning across languages. Words are indexed without a model; installing one later gives every recording its vectors. Indexing stops while recording and waits for transcription and summaries. Nothing in the app's windows searches the index yet; AI agents do, through the MCP server below. Details are in [Implementation Status](IMPLEMENTATION.md#search-index-implemented).

## MCP server for AI agents

Turn on **Settings › Agents › Allow AI Agents to Read Recordings** to let agents and chats on this Mac search and read your recordings over the Model Context Protocol. The server listens on `http://127.0.0.1:47823/mcp` only (the port can be changed there) and refuses requests without the access token shown in the same tab. It is read-only: agents can search, list recordings and tags, and read summaries and transcripts, and nothing else. Answers cite `verbatim://recording/<id>?t=<seconds>` links, which open the Viewer at that moment. What an agent reads goes to the model it uses, which may be a cloud service. Connecting an agent is described in the [README](../README.md#connecting-ai-agents); the tools and request checks are in [Architecture](ARCHITECTURE.md#mcp-server), and what is verified in [Implementation Status](IMPLEMENTATION.md#mcp-server-implemented).

The app starts the server at launch when it is turned on, but never while tests run, because tests host the real app.

## Tests

Tests use Swift Testing and live in `VerbatimTests`. They need no models, network, capture permissions, microphones or personal files; they use temporary databases, files and media they create. The test host is the real app, so any work the app would otherwise start at launch must be guarded. [Implementation Status](IMPLEMENTATION.md#tests) lists what each suite covers.

### End-to-end tests with real models

Ordinary tests use no models. Optional end-to-end tests run real models on this Mac; each is off unless its environment variable is set. `xcodebuild` passes variables prefixed with `TEST_RUNNER_` to the tests without the prefix.

| Variable | Used by | Meaning |
| --- | --- | --- |
| `TEST_RUNNER_RECORDER_E2E_MODELS` | `WhisperEndToEndTests` | Folder holding installed Whisper models, such as the app's own. Nothing is downloaded. |
| `TEST_RUNNER_RECORDER_E2E_SPEECH` | `WhisperEndToEndTests` | Audio file to transcribe. |
| `TEST_RUNNER_RECORDER_E2E_MODEL_ID` | `WhisperEndToEndTests` | Whisper model to use (Tiny by default). |
| `TEST_RUNNER_RECORDER_E2E_LONG_MINUTES` | `WhisperEndToEndTests` | Adds a recording of that many minutes, reporting speed and peak memory. |
| `TEST_RUNNER_RECORDER_E2E_LANGUAGE_MODELS` | `SummaryEndToEndTests` | Folder for language models. |
| `TEST_RUNNER_RECORDER_E2E_LANGUAGE_MODEL_ID` | `SummaryEndToEndTests` | Another catalog language model. |
| `TEST_RUNNER_RECORDER_E2E_EMBEDDING_MODELS` | `EmbeddingEndToEndTests` | Folder for embedding models. |
| `TEST_RUNNER_RECORDER_E2E_EMBEDDING_MODEL_ID` | `EmbeddingEndToEndTests` | Another catalog embedding model. |
| `TEST_RUNNER_RECORDER_E2E_DOWNLOAD` | `SummaryEndToEndTests`, `EmbeddingEndToEndTests` | `1` downloads the model first through the app's own downloader; without it nothing is downloaded and the folder must already hold the model. |

**Transcription.** Runs real recognition against a model already on this Mac, which downloads nothing and writes only to a temporary folder:

```sh
say -o /tmp/speech.aiff "Hello, this is a test of offline transcription."
TEST_RUNNER_RECORDER_E2E_MODELS="$HOME/Library/Application Support/Verbatim/Models" \
TEST_RUNNER_RECORDER_E2E_SPEECH=/tmp/speech.aiff make test
```

**Summaries.** Runs a real language model, downloading it first through the app's own downloader (about 1 GB for the default Qwen3 1.7B):

```sh
TEST_RUNNER_RECORDER_E2E_LANGUAGE_MODELS=/tmp/language-models TEST_RUNNER_RECORDER_E2E_DOWNLOAD=1 make test
```

**Search index.** Runs a real embedding model, downloading it first through the app's own downloader (about 490 MB for the default Multilingual E5 Small):

```sh
TEST_RUNNER_RECORDER_E2E_EMBEDDING_MODELS=/tmp/embedding-models TEST_RUNNER_RECORDER_E2E_DOWNLOAD=1 make test
```

Do not make these tests required.

## Windows and design states

Each window keeps its design states, from the design sections “01 Recorder” to “05 Settings”, on sample data beside the real window. Choose a state with a launch argument (Xcode: Product › Scheme › Edit Scheme › Arguments), from the **Debug** menu in Debug builds, where **Live** returns to the real window, or in the SwiftUI previews of the window's view. All windows follow the system Light or Dark appearance and accent color. To review the design's accent tweak, pass `-VerbatimAccent blue|indigo|teal|graphite` or use **Debug › Accent Color**; **Debug › Appearance** switches Light and Dark.

### Recorder window

The Recorder's “01 Recorder” design states can be reviewed with sample data and no capture. Choose a state with the launch argument `-RecorderPreviewScenario <state>`, from **Debug › Recorder State** in Debug builds, or in the SwiftUI previews of `RecorderWindowView`. **Debug › Recorder State › Live** returns to real capture. States: `idle`, `picker`, `recording`, `permission`, `mic`, `source`, `folder`, `disk`, `saved`.

### Library window

Finished recordings appear in the Library automatically. Metadata lives in `Library.sqlite` under Application Support; media stays where it was recorded. Open Recording plays it in the Viewer. Remove from Library keeps the files; Delete Recording moves them to the Trash. Files moved in Finder are followed through their bookmarks; files that cannot be found show as missing and offer Locate… and Remove from Library. Details are in [Implementation Status](IMPLEMENTATION.md#recording-library-implemented).

The “02 Library” design states remain available with sample data that touches nothing on disk, where processing, transcript search results and the Viewer they open are simulated. Choose a state with `-LibraryPreviewScenario <state>`, which also opens the window at launch, from **Debug › Library State** in Debug builds (**Live** returns to the real library), or in the SwiftUI previews of `LibraryWindowView`. States: `list`, `processing`, `search`, `context`, `confirm`, `empty`. In the search field, try “maya”, “search” or “budget”.

Keyboard: in the Library list, Up and Down move the selection, Return opens, ⌘R shows in Finder, ⌥⌘R opens the folder, Delete (or ⌘⌫) asks to delete, and Escape closes the actions menu. The menu takes focus when it opens (Up, Down, Return, Escape). Escape cancels the delete sheet, and Edit › Undo (⌘Z) restores a recording removed from the Library.

### Viewer window

Opening a recording from the Library plays it in the Viewer. It starts paused. Space plays or pauses, Left and Right skip 15 s (5 s while the position bar has focus), and ⌘[ returns to the Library, which closes the Viewer and ends playback. A file that is missing or can't be played offers Locate File…, Try Again or Show in Finder as they apply. Details are in [Implementation Status](IMPLEMENTATION.md#player-implemented).

The “03 Viewer” design states remain available with sample data and no media: playback, waveforms, transcript, search matches and processing are simulated. Choose a state with `-ViewerPreviewScenario <state>`, which also opens the window at launch, from **Debug › Viewer State** (**Live** returns to real recordings), or in the SwiftUI previews of `ViewerWindowView`. States: `video`, `search`, `audio`, `processing`, `failed`, `unprocessed`. In those states, Return or ⌘G also steps through transcript matches.

### Dock and menu bar

The app has the design's icon (“04 Dock”). Clicking the Dock icon brings back the Recorder, or the Library if that is what you chose in Settings; only the Recorder opens at launch. The Dock menu offers New Recording, Open Recorder, Recordings Library and Settings…; while recording it starts with the live timer and offers Stop Recording, and the Dock icon gets a red badge. While recording, a menu bar item (unless turned off in Settings) shows a red dot and the elapsed time, with Pause/Resume, Stop, Open Recorder and Recordings Library. Quitting during a recording asks first (Stop and Quit or Keep Recording), and Stop and Quit waits until the file is finished. Try the look with `-RecorderPreviewScenario recording` or **Debug › Recorder State › Recording**; on a notched display with a full menu bar, macOS may hide the item.

### Settings window

Open it with ⌘,, the Recorder's gear or the Dock menu. **General** holds Launch at Login, the menu bar icon, the Dock click and what closing the Recorder does. **AI Models** lists the Whisper (Speech Recognition), Summaries and Semantic Search models to download, select and remove, the transcription and summary languages, and the summary settings. **Agents** turns on the MCP server and shows how to connect agents. **Storage** shows the recordings folder and the space recordings and models use. **About** shows the real version and build, a link to the source code, and the open-source licenses. Controls for things that don't exist yet, such as notifications and update checks, are left out rather than shown doing nothing. Details are in [Implementation Status](IMPLEMENTATION.md#settings-window-implemented).

Models live in `~/Library/Application Support/Verbatim/Models`, `…/Verbatim/LanguageModels` and `…/Verbatim/EmbeddingModels` (inside the container when sandboxed). They download only when you ask, keep working offline once installed, and are never loaded into memory by Settings. A running download pauses while you record and continues afterwards.

The “05 Settings” design states remain available with sample data and simulated downloads that touch nothing on disk. Choose a state with `-SettingsPreviewScenario <state>`, which also opens Settings at launch, from **Debug › Settings State** (**Live** returns to the real thing), or in the SwiftUI previews of `SettingsWindowView`. States: `general`, `models`, `removeModel`, `noModels`, `agents`, `storage`, `about`, `licenses`.
