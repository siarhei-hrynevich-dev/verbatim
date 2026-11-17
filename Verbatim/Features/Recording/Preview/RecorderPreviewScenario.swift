import Foundation

/// Recorder states that can be shown without real capture, matching section “01 Recorder” of the design.
/// Real recordings do not go through these.
///
/// Select one at launch with `-RecorderPreviewScenario <rawValue>` (for example in the scheme's arguments),
/// from the Debug menu in Debug builds, or in SwiftUI previews.
enum RecorderPreviewScenario: String, CaseIterable, Identifiable, Sendable {
    case idle
    case picker
    case recording
    case permission
    case microphone = "mic"
    case source
    case folder
    case disk
    case saved

    static let launchArgumentKey = "RecorderPreviewScenario"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .idle: "Ready"
        case .picker: "Window Source"
        case .recording: "Recording"
        case .permission: "Screen Recording Permission Off"
        case .microphone: "Microphone Access Off"
        case .source: "Window Unavailable"
        case .folder: "Folder Access Lost"
        case .disk: "Low Disk Space"
        case .saved: "Recording Saved"
        }
    }

    var issue: RecorderIssue? {
        switch self {
        case .permission: .screenRecordingPermission
        case .microphone: .microphonePermission
        case .source: .windowUnavailable(name: "Zoom Meeting")
        case .folder: .folderAccess(path: RecorderPreviewData.sample.recordingsFolderPath)
        case .disk: .lowDiskSpace(freeBytes: 1_200_000_000, minutesRemaining: 9, settings: "1080p, 60 fps")
        case .idle, .picker, .recording, .saved: nil
        }
    }

    /// Reads the scenario from launch arguments, which `UserDefaults` exposes in its argument domain.
    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> RecorderPreviewScenario? {
        defaults.string(forKey: launchArgumentKey).map { RecorderPreviewScenario(rawValue: $0) ?? .idle }
    }
}
