# Changelog

All notable changes to Verbatim are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). From 0.1.0 on, entries are written by [release-please](https://github.com/googleapis/release-please) from the [Conventional Commits](https://www.conventionalcommits.org/) merged since the previous release, in its release pull request; changes not yet released are listed there. Do not add an Unreleased section: release-please inserts each new version above the newest one in this file.

## [0.1.0](https://github.com/siarhei-hrynevich-dev/verbatim/releases/tag/v0.1.0) (2026-11-17)

The first public release. Builds are for Apple Silicon Macs running macOS 15 or later, and are not signed with a Developer ID or notarized.

### Added

- **Recorder.** Records a display, a single window or audio only with ScreenCaptureKit and AVFoundation, as HEVC video with the microphone and system audio in separate AAC tracks. Pause and resume, 720p, 1080p or native resolution, live level meters, contextual Screen Recording and Microphone permissions, and handling of displays, windows and microphones that go away. Each recording is saved in its own folder under `~/Movies/Verbatim` or a folder you choose, written in fragments so an interrupted recording stays recoverable.
- **Library.** Finished recordings are tracked in a local SQLite database, with renaming, search by title and date, sorting, Finder-like colored tags, Finder actions, Remove from Library with Undo, Delete Recording to the Trash, and following or locating moved and missing files.
- **Viewer.** Plays video and audio-only recordings with seeking, speed, volume, full screen and keyboard control, and explains missing or damaged files with ways to recover.
- **Speech models.** Settings › AI Models downloads, verifies, selects and removes Whisper models (Tiny, Base, Small, Large v3 Turbo) for WhisperKit. Downloads resume, pause while recording, and never start on their own.
- **Offline transcription.** A durable queue transcribes recordings with the selected Whisper model, automatically when a recording ends or on request, and always gives way to recording. Automatic language detection per track, transcripts in step with playback in the Viewer, and TXT, SRT and JSON files beside the media.
- **Summaries.** Local Qwen3 language models run with MLX summarize transcripts in batches into the language you choose, keep notes for each part with its time span, and suggest a title that replaces only a generated default title. Summary settings can be customized per model.
- **Search index.** Transcripts and summaries are split into chunks with an SQLite FTS5 full-text index and vectors from a local Multilingual E5 embedding model, for hybrid search by words and meaning across languages.
- **MCP server for AI agents.** An optional, read-only Model Context Protocol server on `127.0.0.1` with a bearer token lets agents search recordings and read summaries, transcripts and tags, citing `verbatim://` links that open the Viewer at the right moment. Settings › Agents copies a ready command for Claude Code or a configuration for other agents.
- **macOS integration.** Dock menu, menu bar recording indicator with elapsed time, Dock badge, quit confirmation during a recording, Launch at Login, and Settings for General, AI Models, Agents, Storage and About, with the open-source licenses of everything the app ships.
- **Project.** MIT license, third-party notices, contributing guide, code of conduct, security policy, and issue and pull request templates.
