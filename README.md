# Verbatim

**A private screen recorder for macOS that transcribes, summarizes and searches your recordings on your Mac.**

[![CI](https://github.com/siarhei-hrynevich/verbatim/actions/workflows/ci.yml/badge.svg)](https://github.com/siarhei-hrynevich/verbatim/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/siarhei-hrynevich/verbatim)](https://github.com/siarhei-hrynevich/verbatim/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform: macOS 15+ on Apple Silicon](https://img.shields.io/badge/platform-macOS%2015%2B%20%C2%B7%20Apple%20Silicon-lightgrey.svg)](#requirements)

Verbatim is a native Swift and SwiftUI app. It records your screen, a window or just audio, keeps every recording in a local library, and turns what was said into transcripts, summaries and a search index with models that run on your Mac. AI agents on the same Mac can search and read your recordings through a read-only MCP server, if you turn it on.

## Features

- **Recording.** Record a display, a single window or audio only, with the microphone and system audio kept as separate tracks. Pause and resume, choose 720p, 1080p or native resolution, and keep recording with every window closed; a menu bar item and Dock badge show that a recording is running.
- **Library.** Every finished recording is listed with its date, duration and processing status. Rename, tag, sort, and search by title or date; show files in Finder, remove entries or move recordings to the Trash. Recordings moved in Finder are followed, and missing ones can be located again.
- **Viewer.** Play video and audio-only recordings with seeking, speed, volume and full screen. The transcript follows playback, and selecting a line or a summary part plays from there.
- **Offline transcription.** Whisper models run on your Mac through WhisperKit, automatically when a recording ends or on request. Transcripts are saved beside the recording as TXT, SRT and JSON.
- **Local summaries.** A local language model (Qwen3, run with MLX) summarizes each transcript in the language you choose, keeps notes for each part, and suggests a title for recordings you have not named.
- **Search index.** Transcripts and summaries are indexed by words (SQLite FTS5) and by meaning, with a multilingual embedding model, so a question in one language finds speech in another.
- **MCP server for AI agents.** An optional, read-only, local Model Context Protocol server lets agents such as Claude Code search your recordings and read summaries and transcripts, citing links that open the Viewer at the right moment.

A search window inside the app is not built yet; today the index is searched by AI agents through the MCP server. See [Implementation Status](Docs/IMPLEMENTATION.md) for exactly what is built.

## Privacy

- Recordings, transcripts, summaries and the search index stay on your Mac. Transcription, summaries and search run locally; nothing is sent to a server.
- Verbatim ships with no AI models. A model is downloaded from the Hugging Face Hub only when you ask for it in Settings, and works offline once installed. No model loads or runs while you are recording.
- The MCP server is off by default. When you turn it on, it listens only on `127.0.0.1` and requires an access token. What an agent reads through it goes to the model that agent uses, which may be a cloud service; that is outside Verbatim's control.

See the [Security Policy](SECURITY.md) for the full security model.

## Screenshots

Screenshots are coming. The expected images are listed in [Docs/Images](Docs/Images/README.md).

<!--
![The Recorder window](Docs/Images/recorder.png)
![The Library window](Docs/Images/library.png)
![The Viewer with a transcript](Docs/Images/viewer.png)
![Settings › AI Models](Docs/Images/settings.png)
-->

## Requirements

- A Mac with Apple Silicon (M1 or later).
- macOS 15 Sequoia or later.
- Disk space and memory for the models you choose. Settings shows each model's size; the largest summary model needs about 17 GB of disk and 32 GB of memory.

## Install

1. Download the latest `Verbatim` zip or DMG from [GitHub Releases](https://github.com/siarhei-hrynevich/verbatim/releases/latest). Download Verbatim only from this repository's Releases page.
2. Verify the download against the SHA-256 checksum published with the release:

   ```sh
   shasum -a 256 ~/Downloads/<downloaded file>
   ```

   The printed hash must match the one on the release page exactly.
3. Open the zip or DMG and move **Verbatim** to your Applications folder.

### First launch

Release builds are **not signed with an Apple Developer ID and not notarized**, so macOS Gatekeeper blocks the first launch. On macOS 15:

1. Open Verbatim from Applications. macOS says it cannot verify the app; choose **Done**.
2. Open **System Settings › Privacy & Security**, scroll to **Security**, and choose **Open Anyway** next to the message about Verbatim. Confirm with your password if asked.
3. Open Verbatim again and choose **Open Anyway**.

Alternatively, remove the quarantine attribute in Terminal after moving the app to Applications:

```sh
xattr -dr com.apple.quarantine /Applications/Verbatim.app
```

Do this only for a download whose checksum you have verified. Building from source is the other way to run Verbatim without Gatekeeper warnings.

## Getting started

1. **Make a first recording.** The Recorder opens at launch. Choose a screen, a window or audio only, turn the microphone and system audio on or off, and choose **Start Recording**. macOS asks for Screen Recording and Microphone access the first time a recording needs them. Recordings are saved to `~/Movies/Verbatim`; right-click the folder line at the bottom of the Recorder to choose another folder.
2. **Install a speech model.** Open **Settings › AI Models** (⌘,) and download a model under **Speech Recognition**; Verbatim suggests one for your Mac. The first model you install is selected. With **Transcribe when recording ends** on in the Recorder, new recordings are transcribed automatically; otherwise choose Transcribe in the Library or Generate Transcript in the Viewer.
3. **Optionally add summaries and search.** In the same tab, download a model under **Summaries** to summarize new transcripts, and one under **Semantic Search** to search by meaning. Choose the transcription and summary languages under **Processing**.
4. **Open the Library** with the Recorder's **Library** button or the Dock menu to browse, play and manage recordings. In the Viewer, switch the side panel between **Transcript** and **Summary**.

Models download only when you ask, pause while you record, and keep working offline once installed.

## Connecting AI agents

Turn on **Settings › Agents › Allow AI Agents to Read Recordings** to let agents and chats on this Mac search and read your recordings over the Model Context Protocol. The server listens on `http://127.0.0.1:47823/mcp` only (the port can be changed there), runs only while Verbatim runs, and refuses requests without the access token shown in the same tab. **New Token…** replaces the token. The server is read-only: agents can search, list recordings and tags, and read summaries and transcripts, and nothing else. Answers cite `verbatim://recording/<id>?t=<seconds>` links, which open the Viewer at that moment.

For Claude Code, choose **Copy Command** and run it:

```sh
claude mcp add --transport http verbatim http://127.0.0.1:47823/mcp --header "Authorization: Bearer <token>"
```

Other agents and editors that support MCP over HTTP with a custom header take the `mcpServers` entry from **Copy Configuration**. The tools are `search_recordings`, `list_recordings`, `get_recording`, `get_summary`, `get_transcript` and `list_tags`; details are in [Architecture](Docs/ARCHITECTURE.md#mcp-server).

What an agent reads goes to the model it uses, which may be a cloud service.

## Build from source

You need an Apple Silicon Mac with macOS 15 or later, full Xcode 26 or later with the Metal Toolchain component, and Homebrew.

```sh
git clone https://github.com/siarhei-hrynevich/verbatim.git
cd verbatim
make setup   # checks Xcode, installs SwiftLint and swift-format, resolves packages
make check   # format-check, lint, Xcode build and tests
```

Then open `Verbatim.xcodeproj`, select the Verbatim scheme and My Mac, and Run. The [Development guide](Docs/DEVELOPMENT.md) covers the toolchain, make targets, signing, dependencies, project layout and the optional end-to-end tests with real models.

## Contributing

Bug reports, ideas and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md) first. Changes are recorded in the [Changelog](CHANGELOG.md).

## Security

Please report vulnerabilities privately, as described in the [Security Policy](SECURITY.md), not in a public issue.

## License

Verbatim is released under the [MIT License](LICENSE). Third-party packages and the models it can download have their own licenses, listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and in **Settings › About › Open-Source Licenses**.

## Acknowledgements

Verbatim is built on:

- [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) by Argmax, for on-device speech recognition with OpenAI's [Whisper](https://github.com/openai/whisper) models.
- [MLX Swift](https://github.com/ml-explore/mlx-swift) and [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm), for running language and embedding models on Apple Silicon.
- [swift-transformers](https://github.com/huggingface/swift-transformers) by Hugging Face, for tokenizers.
- [SQLiteVecKit](https://github.com/carlosypunto/SQLiteVecKit) and [sqlite-vec](https://github.com/asg017/sqlite-vec).
- [Qwen3](https://huggingface.co/Qwen) models for summaries and [Multilingual E5](https://huggingface.co/intfloat/multilingual-e5-small) models for semantic search.
- Apple's ScreenCaptureKit, AVFoundation, Core ML and SwiftUI.
