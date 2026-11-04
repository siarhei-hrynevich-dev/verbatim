import Foundation

/// Fixed sample content for design-review scenarios and SwiftUI previews. Real recordings never use it.
struct RecorderPreviewData: Sendable {
    let displays: [CaptureDisplay]
    let windows: [CaptureWindow]
    let microphones: [Microphone]
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
        microphones: [Microphone(id: "built-in-mic", name: "MacBook Pro Microphone")],
        storageSummary: "~/Movies/Verbatim · 214 GB free",
        recordingsFolderPath: "~/Movies/Verbatim",
        savedRecordingTitle: "Recording Nov 3, 11:42",
        pausedTranscriptionTitle: "Weekly Team Sync"
    )
}
