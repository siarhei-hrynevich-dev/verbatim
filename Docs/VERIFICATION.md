# Verification

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
