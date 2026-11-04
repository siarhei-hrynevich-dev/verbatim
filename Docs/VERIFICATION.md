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
