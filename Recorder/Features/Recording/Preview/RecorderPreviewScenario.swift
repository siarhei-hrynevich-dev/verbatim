import Foundation

/// Recorder states that can be shown without real capture, matching section “01 Recorder” of the design.
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
        case .source: .sourceUnavailable
        case .folder: .folderAccess
        case .disk: .lowDiskSpace
        case .idle, .picker, .recording, .saved: nil
        }
    }

    /// Reads the scenario from launch arguments, which `UserDefaults` exposes in its argument domain.
    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> RecorderPreviewScenario {
        guard let rawValue = defaults.string(forKey: launchArgumentKey) else {
            return .idle
        }
        return RecorderPreviewScenario(rawValue: rawValue) ?? .idle
    }
}
