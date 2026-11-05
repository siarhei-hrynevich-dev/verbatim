# Verification

## Transcription

Checked on 2026-11-04 on macOS 15 (Darwin 24.6.0, Mac16,12) with Xcode 26.3, in addition to `make check`.

**Real recognition**, with `WhisperEndToEndTests` driving the real coordinator, database, Library, file store, decoder, `WhisperKit` and `AVPlaybackService` in a temporary folder, using a copy of an installed Tiny model and speech from `say` written to QuickTime files with the Recorder's named tracks:

- A speech recording became the expected text, language `en`, with no special tokens, and all three files. New objects on the same disk read the same transcript without a model. A Viewer on the real player showed the lines, and selecting one landed on its start and highlighted it. Re-transcribing replaced it.
- Two tracks, the second starting 8 s later, kept their sources, and the same words came out 8.000 s apart (0.020 s and 8.020 s).
- Speech after 6 s of quiet noise started at 6.000 s. This and the previous check found that without word timestamps and silence trimming a first segment starts at 0.
- About 90 s of repeated speech across chunks: chronological, no overlaps within the source, every repeat heard once.
- Two hours of audio: 7,192 s in 446 s, about 16 times real time on Tiny, with 986 segments. Memory rose from 89 MB to a peak of 216 MB.
- An explicit language, a model folder with no files (`modelUnavailable`), and cancelling followed by another run.

**The running app**, an unsigned Debug build with a temporary home folder holding a copy of a real library: it launched, the database had the new tables, recordings stayed `recorded`, no job started and no model was loaded.

Found along the way and fixed:

- Two connections opening a new database at once failed with “database is locked”, because switching to WAL ignores the busy timeout. Opening is now serialized, and the test passed 25 times in a row.
- Test runs host the real app, so resuming the queue at launch opened the real library in tests. It now stays shut in a test host, confirmed by the file's hash and timestamps across a full test run.
- Whisper's first segment could start seconds before the speech, as above.

### Not verified

- **Clicking through the windows.** Nothing in this session could operate the UI. Transcribe, Retry, Re-transcribe, Cancel, the Export save panel, copying, the language menu, scrolling to pause following, and how the states look have not been used by hand. The same operations ran beneath the views as described above.
- **A recording made with real capture through to a transcript.** Files came from a test writer with the same track layout, and the job scheduling from a finished recording ran with faked capture. Real microphone and system audio, with their real timing differences, have not been through it.
- **Recording priority with real hardware**, meaning how long a running prediction overlaps with capture. Stopping and restarting were tested with the engine replaced.
- **A signed, sandboxed build**, including Core ML loading models from the container and writing files into a custom recordings folder.
- **Models other than Tiny.** Large v3 Turbo has not been run. Whether it reports word timestamps decides how exact its segment starts are.
- **Real multilingual speech.** Only synthetic English was used. Detecting another language and code-switching have not been checked.

## Settings and speech models

Checked on 2026-11-04 on macOS 15 (Darwin 24.6.0, Mac16,12) with Xcode 26.3 and Swift 6.2.4, in addition to `make check` (415 tests, repeated four times without a failure).

**Real components against the real Hugging Face Hub**, with an uncommitted test driving `ModelManager`, `WhisperModelProvider` and the JSON registry in a temporary folder, using Tiny, and Base for interruption:

- Catalog: WhisperKit reports all four models supported on this Mac. Sizes from the Hub, with tokenizer: Tiny 79 MB, Base 149 MB, Small 489 MB, Large v3 Turbo 1.64 GB. `openai_whisper-medium` is in the repository but in no supported list of WhisperKit 1.1.1.
- Download: 28 increasing byte-based progress samples, then verifying, then installed. Files laid out as documented.
- A real network failure on an earlier attempt (timeouts, then offline) ended as `failed(.noNetwork)` and kept partial files.
- Recording priority: pausing stopped writing, with partial bytes unchanged over time, and resuming continued past them.
- Cancel: the transfer stopped, and the model's files, partial files and tokenizer were gone.
- Restart, as new manager objects on the same disk and defaults: the model stayed installed, and the selection stayed selected.
- The transcription contract: `WhisperKit` loaded the model and tokenizer from the resolved paths with downloads off and an unreachable Hub endpoint, confirming offline use. That load was only this check; the app never does it.
- A truncated `tokenizer.json` was detected on restart as damaged, with the selected model shown as unavailable.
- Removal: the model's files and tokenizer went, and the selection cleared. `config.json` and the registry stayed.

**The running app**, an unsigned Debug build with a temporary home folder: launching creates no model files and downloads nothing. Settings opens at 620 pt. General shows real values, and AI Models shows the empty state from the real manager. Quitting works. The other tabs, in light appearance with sample data, were checked as rendered images.

Found along the way and fixed:

- A view's cancelled `.task` could cancel a disk check and mark healthy files as damaged. The checks now run in tasks the manager owns.
- The install outcome could overtake its last phase event, which the state transition rules caught as an invalid `downloading → installed`.
- A model removed externally stayed in the registry when its state was already `notInstalled`.

### Not verified

- **Clicking through Settings.** The session's screen was locked, so pointer and Accessibility actions could not reach windows, and only menu items worked. Download, Select, Remove, tab switching and alerts have not been used by hand in the running app; the same operations ran beneath the views as described above, and the view models have tests.
- **Launch at Login, the Dock click, closing the Recorder with Quit selected, and hiding the menu bar item.** These depend on AppKit or the system and need a person. `SMAppService` also needs a signed build.
- **The sandbox.** Builds here are unsigned. The `network.client` entitlement is present, but downloading and the container location need a signed build.
- **Large v3 Turbo, Small and Base installs.** Only Tiny was installed in full. An M1 Mac, where Turbo shows as unsupported, was not available.
- **Disk full and denied storage on a real volume.** Covered by tests through error translation and controllable failures.

## Player

Checked on 2026-11-04 on macOS 15 (Darwin 24.6.0) with Xcode 26.3 and Swift 6.2.4, in addition to `make check`. The real app, in an unsigned Debug build and so outside the sandbox, ran against a temporary home folder holding a test database and copies of real recordings. It was driven with Accessibility actions and posted mouse events, and observed through window captures and `lsof`.

Confirmed in the running app, on real recordings made by the app:

- Opening from the Library by keyboard; video with the correct aspect ratio and letterboxing, including after resizing.
- Play, pause, position bar click, drag, ±15 s, speed against the timer visible in the frames, mute and volume control state, and replay after the end.
- While dragging, the thumb and frame stay put against playback's own updates, and playback resumes on release.
- A stored duration of 50 s against media of 46 s: the Viewer used the media's.
- Audio-only: title, two tracks reported, play, pause, seek, Space.
- Native full screen entered from the control and left again, returning to the previous size. This found that the window could not enter full screen as an auxiliary window.
- Missing and damaged files show their explanations and actions; the Locate File sheet opens and cancels.
- Show in Finder selects the file, and Open Folder opens its folder. The More menu lists its actions, with the transcript's disabled when no file exists.
- `lsof` shows the media open only while its session lasts: switching to another recording held only the new file, failures and Back held none.
- The nothing-open state, from the Window menu.

Found by the integration tests and fixed: `publisher(for: \.status).values` drops a status change arriving between iterations, which could leave a load waiting forever.

### Not verified

- **Hearing it.** Nothing listened to the output. Both audio tracks are confirmed enabled with no selection group, on real files and in tests, which is what makes `AVPlayer` mix them. Volume and mute were confirmed as control state, and reach the player through calls covered by tests.
- **The sandbox.** Bookmark-scoped playback outside the Movies folder, and a denied file, need a signed build. Both are covered only as far as `MediaFileAccess` and error translation go in tests.
- **Very long recordings.** The longest file played was 47 s. Scrubbing logic for long files is tested with a controllable player, not with a real hour-long file.
- **A located file end to end through the panel.** The sheet was opened and cancelled; choosing a file is covered by view model tests against real files.
- **Show Transcript in Finder in the running app**, since no recording has a transcript file. It is covered by tests against real files.
- **A system-cancelled drag**, which is handled but was not provoked.
- **An unexplained close.** The Viewer window closed once between test steps, with the process healthy. It did not recur during the rest of the session, and no code closes it except Back, so it may have been closed from outside. The cause was not established.

## Recording library

Verified on November 4, 2026, on an Apple Silicon Mac running macOS 15.7.7 with Xcode 26.3.

`make check` passed: format-check, strict SwiftLint (0 violations across 141 files), native Xcode build, and 228 Swift Testing tests in 33 suites.

### Real capture, Finder and Trash

A scratch harness outside the repository compiled the production `Recorder/Models`, `Recorder/Application` and `Recorder/Infrastructure` sources, with its home folder redirected so that its database stayed out of the real one. Test files were deleted afterwards.

| Case | Result |
| --- | --- |
| Three short display recordings through the real coordinator | Each appeared in the Library with no metadata error: type, duration, size, `recorded` status, bookmark |
| Rename | Title changed; media file untouched |
| Thumbnail | JPEG generated from the real recording |
| Show in Finder, Open Folder, Open Recording, Open Recordings Folder | Returned without error, through real `NSWorkspace`; the windows themselves were not inspected |
| Remove from Library | Entry gone; file still on disk |
| Delete Recording | Whole folder found in the real `~/.Trash`; entry gone |
| New service and repository on the same database | History intact |
| Media renamed on disk | Followed through its bookmark; stored path updated |
| Media deleted on disk | Reported missing; entry kept |

### App Sandbox

A second harness, ad-hoc signed with `Recorder.entitlements` in a minimal app bundle, ran under the real sandbox without capture. The database was created in the app's container. In `~/Movies/Verbatim` it created a stand-in recording, made a security-scoped bookmark, inspected the folder, revealed the file and moved the folder to the real Trash, removing the entry.

### The built app

A scratch copy of the Debug build ran on the harness's database. The Library window showed the real entries, a real video thumbnail, type labels, section counts, and a missing recording with Locate…, in the existing design. Nothing was reported in its log.

### Not verified

- **Library interactions through the UI.** The rename and delete sheets, the actions menu, the sort menu, typing in search, the Locate panel and Undo were not clicked through. Their view model and service paths are covered by tests.
- **A recording started from the app's own window**, for the reason given below under Recorder functionality.
- **Custom recordings folders under the sandbox**, including reaching a recording through its bookmark after switching folders, and Locate with a real open panel's security scope.
- **Unmounted volumes on real hardware**; the path check is covered by a test with a nonexistent volume.
- **Performance with a very large history**; queries are indexed, but no large data set was measured.

## Recorder functionality

Verified on November 4, 2026, on an Apple Silicon Mac running macOS 15.7.7 with Xcode 26.3, one internal Retina display and one external display.

`make check` passed: format-check, strict SwiftLint (0 violations across 118 files), native Xcode build, and 140 Swift Testing tests in 26 suites.

### Real capture

A scratch harness outside the repository compiled the production `Recorder/Models`, `Recorder/Application` and `Recorder/Infrastructure` sources and drove the real `RecordingCoordinator`, `ScreenCaptureEngine` and `FileRecordingStore` from a shell that already held Screen Recording and Microphone access. Files were inspected with AVFoundation for structure only, and deleted afterwards.

| Case | Result |
| --- | --- |
| Display, 1080p, 30 fps, microphone and system audio, 2 s pause | Playable; 1660×1080 from a 2940×1912 source; `Microphone` (mono) and `System Audio` (stereo) tracks; 6.1 s of media from about 8 s of wall time |
| Display, Native, 60 fps, no audio | Playable; 2940×1912, the display's physical pixels |
| Window, 720p, 30 fps, system audio | Playable; 1280×708, about 29 fps |
| Audio only: both sources, microphone only, system audio only | Playable; the expected named tracks and no video |
| Window closed while recording | Detected in about 0.1 s; recording saved and reported as interrupted |
| Window closed between discovery and start | Failed with `windowUnavailable` |
| Live levels | Microphone meter moved; system audio meter read 0 in silence and 0.28 while a sound played |
| Discovery | Both displays named with native sizes; windows; JPEG thumbnails; microphones |

The built app launched as a regular Dock application, showed real displays, microphone and free space without any permission prompt, and quit normally. Screenshots of the `recording` and `permission` design states matched the existing layout.

### Not verified

- **The recording flow through the app's own UI.** Pressing Start in the built app would prompt for access under its own identity; no signed build was available. Clicks, Dock and menu bar actions while really recording, and the running-window behavior after closing the window, are covered only by unit tests on the view model and coordinator.
- **Sandbox and TCC behavior.** `make build` is unsigned, so the sandbox, the Movies entitlement, security-scoped bookmarks and the permission prompts have not run for real.
- **Hardware events.** Unplugging a display or microphone was not performed; the handling is covered with test doubles.
- **Disk full during a recording**, and recordings longer than a few seconds.

### Observations

- One early harness run was killed by its 120-second limit without output, because its stdout was buffered, so where it stalled is unknown. It did not recur in the following 5 runs, with all output visible. A stalled ScreenCaptureKit call would leave the Recorder in Preparing or Saving, with no timeout. Worth watching in real use.
- In one run ScreenCaptureKit returned no displays on its first call. Discovery now falls back to CoreGraphics, starting retries briefly, and a recording that needs system audio fails explicitly instead of losing it silently.

# Initialization verification

Verified on November 3, 2026, on an Apple Silicon Mac.

## Toolchain

- Xcode 26.3 (17C529), selected through xcode-select.
- Apple Swift 6.2.4 (swiftlang-6.2.4.1.4); app and tests use Swift 6 language mode with complete strict concurrency.
- Apple swift-format 6.2.3 from the Xcode toolchain.
- SwiftLint 0.65.1, installed through Homebrew.
- macOS deployment target 15.0, arm64.

## Dependency resolution

`make setup` succeeded. Exact Xcode SwiftPM references and Package.resolved record:

| Package | Resolved version | Selected product |
| --- | --- | --- |
| argmax-oss-swift | 1.1.1 | WhisperKit |
| SQLiteVecKit | 0.1.1 | SQLiteVecStore |
| swift-argument-parser | 1.8.2 | Transitive package resolution only |

Both selected products are linked to the application and test targets. Dependency smoke tests import the modules and exercise lightweight decoding options and a distance metric without creating WhisperKit or a database. No SpeakerKit, TTSKit, Argmax umbrella, or CLI product is selected.

## Results

- `make check`: passed, including format-check, strict SwiftLint, native Xcode build and tests.
- `make build`: passed using xcodebuild, Debug, arm64, signing disabled.
- `make test`: passed; 6 Swift Testing tests in 2 suites, with parameterized status and invalid-duration cases.
- `make format-check`: passed using the committed official swift-format configuration.
- `make lint`: passed; zero violations across 5 Swift files.
- `swiftlint analyze --strict --compiler-log-path /tmp/recorder-compiler.log`: passed; zero violations, including unused-import analysis, using the initial build and test compiler logs.
- Native launch: NSWorkspace opened the built app; NSRunningApplication reported a running regular Dock application, and CoreGraphics reported an on-screen layer-zero window owned by its process. The verification instance was then terminated.
- Project and entitlement property lists passed `plutil -lint`.
- Git initialized locally; no remote, commit, or push created. Package.resolved is not ignored.

No AI weights were downloaded or loaded. Startup only constructs the placeholder SwiftUI window. No permission prompts, capture devices, databases, transcription, or embedding inference were used. Package source downloads are separate from model weights.

## Diagnostics and limits

The first lint attempt found no violations but failed while writing SwiftLint's default cache inside the restricted environment. The Makefile now uses `--no-cache`, and strict lint passes. Git initialization initially required sandbox escalation and subsequently succeeded. The initial asset-catalog warning was fixed by removing unused generated accent/icon settings.

Xcode emits device build-number diagnostics and an App Intents metadata-extraction warning because the app has no AppIntents dependency. Neither prevents the build or tests. Signing-disabled verification does not establish sandbox enforcement or future TCC permission behavior; those must be tested with a signed app when capture is implemented. Release/distribution signing and actual recording behavior remain outside this initialization task. No remaining initialization blocker was found.

Temporary command logs are in `/tmp/recorder-{setup,build,test,check,analyze,launch-final}.log`; Xcode test result bundles are under ignored `DerivedData/Logs/Test/`. These are local verification artifacts, not repository inputs.
