# Screenshots

Images for the [README](../../README.md). None are committed yet; the README keeps their image tags commented out until the files exist.

## Expected files

| File | Shows |
| --- | --- |
| `recorder.png` | The Recorder window ready to record a display, with the microphone and system audio on and their level meters. |
| `library.png` | The Library window with several recordings in different states (Ready, Transcribing with progress, Not Transcribed) and a few tags in the sidebar. |
| `viewer.png` | The Viewer playing a video recording, with the transcript panel following playback. |
| `settings.png` | Settings › AI Models with one speech model installed and selected, and the Summaries and Semantic Search catalogs. |

Optional extras, if they help: `viewer-summary.png` (the Summary panel) and `agents.png` (Settings › Agents with the server running and the token hidden).

## Light and dark

Provide each image in both appearances, with a `-dark` suffix for the dark one (`recorder.png` and `recorder-dark.png`). The README can then show the right one with a `<picture>` element:

```html
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Docs/Images/recorder-dark.png">
  <img src="Docs/Images/recorder.png" alt="The Recorder window" width="640">
</picture>
```

## How to capture

- Capture a single window with its shadow (⇧⌘4, then Space, then click the window) on a Retina display, so images are at 2× scale.
- Keep the window at its default size; resize larger windows to about 1280 × 800 points or less. Images are shown at up to 640–800 points wide.
- Use the system accent color unless a design review asks otherwise, and English as the system language.
- Use PNG, and run the files through a lossless optimizer (for example `oxipng` or ImageOptim) to keep each under about 1 MB.
- **No personal data.** Use the design states with sample data (`-RecorderPreviewScenario`, `-LibraryPreviewScenario`, `-ViewerPreviewScenario`, `-SettingsPreviewScenario`; see [Development](../DEVELOPMENT.md#windows-and-design-states)) or recordings made for the purpose. Never show real recordings, transcripts, file paths with your user name, or an MCP access token.
