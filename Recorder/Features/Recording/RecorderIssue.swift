import SwiftUI

/// A problem shown in the Recorder's callout slot. Each names the problem and offers a fix plus a fallback.
enum RecorderIssue: String, CaseIterable, Sendable {
    case screenRecordingPermission
    case microphonePermission
    case sourceUnavailable
    case folderAccess
    case lowDiskSpace

    /// Whether the issue prevents video capture. Start stays disabled unless Audio Only is selected.
    var blocksVideoCapture: Bool {
        self == .screenRecordingPermission
    }

    var icon: VerbatimIcon {
        switch self {
        case .screenRecordingPermission: .lock
        case .microphonePermission: .microphoneOff
        case .sourceUnavailable: .window
        case .folderAccess: .folder
        case .lowDiskSpace: .drive
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .screenRecordingPermission: "Screen Recording access is off"
        case .microphonePermission: "Microphone access is off"
        case .sourceUnavailable: "“Zoom Meeting” is no longer available"
        case .folderAccess: "Can’t save to ~/Movies/Verbatim"
        case .lowDiskSpace: "Only 1.2 GB free on Macintosh HD"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .screenRecordingPermission:
            """
            Verbatim needs permission to capture your screen and system audio. Turn it on in System Settings → \
            Privacy & Security → Screen & System Audio Recording, then reopen Verbatim.
            """
        case .microphonePermission:
            "Your voice won’t be recorded. Allow Verbatim in System Settings → Privacy & Security → Microphone."
        case .sourceUnavailable:
            "The window was closed or its app quit. Choose another window or record the entire screen."
        case .folderAccess:
            "Verbatim no longer has access to this folder. Choose it again to grant access, or pick another location."
        case .lowDiskSpace:
            "That’s about 9 minutes at 1080p, 60 fps. Free up space or lower the quality before recording."
        }
    }

    var primaryActionTitle: LocalizedStringKey {
        switch self {
        case .screenRecordingPermission, .microphonePermission: "Open System Settings"
        case .sourceUnavailable: "Choose Window"
        case .folderAccess: "Choose Folder…"
        case .lowDiskSpace: "Open Storage Settings"
        }
    }

    var secondaryActionTitle: LocalizedStringKey {
        switch self {
        case .screenRecordingPermission: "Record Audio Only"
        case .microphonePermission: "Record Without Mic"
        case .sourceUnavailable: "Record Entire Screen"
        case .folderAccess: "Use Default Location"
        case .lowDiskSpace: "Switch to 720p"
        }
    }
}
