import Foundation

/// Fixed sample content for the layout-only Recorder. Capture, permissions, storage and processing are not
/// implemented yet; this stands in for what those services will provide.
struct RecorderPreviewData: Sendable {
    let displays: [CaptureDisplay]
    let windows: [CaptureWindow]
    let microphones: [String]
    let storageSummary: String
    let recordingsFolderPath: String
    let savedRecordingTitle: String
    let pausedTranscriptionTitle: String

    static let sample = RecorderPreviewData(
        displays: [
            CaptureDisplay(id: "built-in", name: "Built-in Display", pixelWidth: 3024, pixelHeight: 1964),
            CaptureDisplay(id: "lg-ultrafine", name: "LG UltraFine", pixelWidth: 3840, pixelHeight: 2160)
        ],
        windows: [
            CaptureWindow(id: "zoom", appName: "Zoom", title: "Zoom Meeting"),
            CaptureWindow(id: "safari", appName: "Safari", title: "Linear — Sprint 14"),
            CaptureWindow(id: "xcode", appName: "Xcode", title: "RecorderView.swift"),
            CaptureWindow(id: "figma", appName: "Figma", title: "Recorder v3"),
            CaptureWindow(id: "notes", appName: "Notes", title: "Architecture agenda"),
            CaptureWindow(id: "terminal", appName: "Terminal", title: "zsh — 120×40")
        ],
        microphones: ["MacBook Pro Microphone"],
        storageSummary: "~/Movies/Verbatim · 214 GB free",
        recordingsFolderPath: "~/Movies/Verbatim",
        savedRecordingTitle: "Recording Nov 3, 11:42",
        pausedTranscriptionTitle: "Weekly Team Sync"
    )
}
