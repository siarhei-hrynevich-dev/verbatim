import SwiftUI

/// A problem shown in the Recorder's callout slot. Each names the problem and offers a fix plus a fallback.
enum RecorderIssue: Equatable, Sendable {
    case screenRecordingPermission
    case microphonePermission
    case windowUnavailable(name: String)
    case displayUnavailable(name: String)
    case microphoneUnavailable(name: String)
    case noAudioSource
    case folderAccess(path: String)
    case lowDiskSpace(freeBytes: Int64, minutesRemaining: Int, settings: String)
    case insufficientDiskSpace(freeBytes: Int64)
    case sourcesUnavailable(detail: String)
    case recordingFailed(detail: String)
    case nothingRecorded
    case finalizationFailed(detail: String, directoryPath: String)
    /// The recording was saved, but something cut it short or removed a source.
    case recordingInterrupted(description: String)
    case metadataNotSaved(detail: String)

    /// Whether the issue prevents starting. Screen Recording access only matters if the recording needs it.
    func blocksStart(requiresScreenCapture: Bool) -> Bool {
        switch self {
        case .screenRecordingPermission:
            requiresScreenCapture
        case .microphonePermission, .windowUnavailable, .microphoneUnavailable, .noAudioSource, .folderAccess,
            .insufficientDiskSpace:
            true
        case .displayUnavailable, .lowDiskSpace, .sourcesUnavailable, .recordingFailed, .nothingRecorded,
            .finalizationFailed, .recordingInterrupted, .metadataNotSaved:
            false
        }
    }

    var icon: VerbatimIcon {
        switch self {
        case .screenRecordingPermission: .lock
        case .microphonePermission, .microphoneUnavailable, .noAudioSource: .microphoneOff
        case .windowUnavailable: .window
        case .displayUnavailable: .monitor
        case .folderAccess: .folder
        case .lowDiskSpace, .insufficientDiskSpace: .drive
        case .sourcesUnavailable, .recordingFailed, .nothingRecorded, .finalizationFailed, .recordingInterrupted,
            .metadataNotSaved:
            .alert
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .screenRecordingPermission: "Screen Recording access is off"
        case .microphonePermission: "Microphone access is off"
        case .windowUnavailable(let name): "“\(name)” is no longer available"
        case .displayUnavailable(let name): "“\(name)” was disconnected"
        case .microphoneUnavailable(let name):
            name.isEmpty ? "No microphone is available" : "“\(name)” is not available"
        case .noAudioSource: "Nothing to record"
        case .folderAccess(let path): "Can’t save to \(path)"
        case .lowDiskSpace(let freeBytes, _, _), .insufficientDiskSpace(let freeBytes):
            "Only \(Self.formattedBytes(freeBytes)) free"
        case .sourcesUnavailable: "Couldn’t list screens and windows"
        case .recordingFailed: "Recording couldn’t start"
        case .nothingRecorded: "Nothing was recorded"
        case .finalizationFailed: "The recording couldn’t be finished"
        case .recordingInterrupted: "The recording was interrupted"
        case .metadataNotSaved: "The recording’s details weren’t saved"
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
        case .windowUnavailable:
            "The window was closed or its app quit. Choose another window or record the entire screen."
        case .displayUnavailable:
            "Reconnect it, or record the main display instead."
        case .microphoneUnavailable:
            "Connect a microphone, use the default input, or record without one."
        case .noAudioSource:
            "Audio Only needs the microphone or system audio. Turn one of them on."
        case .folderAccess:
            "Verbatim no longer has access to this folder. Choose it again to grant access, or pick another location."
        case .lowDiskSpace(_, let minutesRemaining, let settings):
            """
            That’s about \(minutesRemaining) minutes at \(settings). Free up space or lower the quality before \
            recording.
            """
        case .insufficientDiskSpace:
            "That’s not enough to record safely. Free up space or choose a folder on another disk."
        case .sourcesUnavailable(let detail), .recordingFailed(let detail):
            "\(detail)"
        case .nothingRecorded:
            "Capture stopped before any audio or video arrived, so no file was kept."
        case .finalizationFailed(let detail, let directoryPath):
            "\(detail) What was captured is kept in \(directoryPath)."
        case .recordingInterrupted(let description):
            "\(description) What was captured until then is saved."
        case .metadataNotSaved(let detail):
            "The media file is safe, but it may not appear in the Library. \(detail)"
        }
    }

    var primaryActionTitle: LocalizedStringKey {
        switch self {
        case .screenRecordingPermission, .microphonePermission: "Open System Settings"
        case .windowUnavailable: "Choose Window"
        case .displayUnavailable: "Use Main Display"
        case .microphoneUnavailable: "Use Default Input"
        case .noAudioSource: "Turn On Microphone"
        case .folderAccess: "Choose Folder…"
        case .lowDiskSpace, .insufficientDiskSpace: "Open Storage Settings"
        case .sourcesUnavailable, .recordingFailed, .nothingRecorded: "Try Again"
        case .finalizationFailed, .recordingInterrupted, .metadataNotSaved: "Show in Finder"
        }
    }

    var secondaryActionTitle: LocalizedStringKey {
        switch self {
        case .screenRecordingPermission: "Record Audio Only"
        case .microphonePermission, .microphoneUnavailable: "Record Without Mic"
        case .windowUnavailable: "Record Entire Screen"
        case .displayUnavailable: "Record Audio Only"
        case .noAudioSource: "Turn On System Audio"
        case .folderAccess: "Use Default Location"
        case .lowDiskSpace: "Switch to 720p"
        case .insufficientDiskSpace: "Choose Folder…"
        case .sourcesUnavailable, .recordingFailed, .nothingRecorded, .finalizationFailed, .recordingInterrupted,
            .metadataNotSaved:
            "Dismiss"
        }
    }

    static func formattedBytes(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}

/// What pressing one of a callout's buttons changes.
struct RecorderIssueAction: Equatable {
    enum Effect: Equatable {
        case openSettings(SystemSettingsPane)
        case selectAvailableWindow
        case selectMainDisplay
        case selectDefaultMicrophone
        case chooseFolder
        case useDefaultFolder
        case retryRecording
        case reloadSources
        case revealRecording
    }

    var captureMode: CaptureMode?
    var isMicrophoneEnabled: Bool?
    var isSystemAudioEnabled: Bool?
    var quality: VideoQuality?
    var effect: Effect?
    /// Whether the callout goes away, rather than waiting for the user to fix the problem elsewhere.
    var isResolving = true
}

extension RecorderIssue {
    var primaryAction: RecorderIssueAction {
        switch self {
        case .screenRecordingPermission: .init(effect: .openSettings(.screenRecording), isResolving: false)
        case .microphonePermission: .init(effect: .openSettings(.microphone), isResolving: false)
        case .windowUnavailable: .init(captureMode: .window, effect: .selectAvailableWindow)
        case .displayUnavailable: .init(effect: .selectMainDisplay)
        case .microphoneUnavailable: .init(effect: .selectDefaultMicrophone)
        case .noAudioSource: .init(isMicrophoneEnabled: true)
        case .folderAccess: .init(effect: .chooseFolder, isResolving: false)
        case .lowDiskSpace, .insufficientDiskSpace: .init(effect: .openSettings(.storage), isResolving: false)
        case .sourcesUnavailable: .init(effect: .reloadSources)
        case .recordingFailed, .nothingRecorded: .init(effect: .retryRecording)
        case .finalizationFailed, .recordingInterrupted, .metadataNotSaved:
            .init(effect: .revealRecording, isResolving: false)
        }
    }

    var secondaryAction: RecorderIssueAction {
        switch self {
        case .screenRecordingPermission:
            // System audio needs the same access, so only the microphone remains. The callout stays, as a reminder
            // of what is missing and how to get it back.
            .init(captureMode: .audioOnly, isMicrophoneEnabled: true, isSystemAudioEnabled: false, isResolving: false)
        case .microphonePermission, .microphoneUnavailable: .init(isMicrophoneEnabled: false)
        case .windowUnavailable: .init(captureMode: .screen)
        case .displayUnavailable: .init(captureMode: .audioOnly)
        case .noAudioSource: .init(isSystemAudioEnabled: true)
        case .folderAccess: .init(effect: .useDefaultFolder)
        case .lowDiskSpace: .init(quality: .hd720)
        case .insufficientDiskSpace: .init(effect: .chooseFolder, isResolving: false)
        case .sourcesUnavailable, .recordingFailed, .nothingRecorded, .finalizationFailed, .recordingInterrupted,
            .metadataNotSaved:
            .init()
        }
    }

    /// The issue that presents what happened to a finished recording, if anything did.
    init?(_ outcome: RecordingOutcome) {
        if let interruption = outcome.interruptions.first {
            self = .recordingInterrupted(description: Self.description(of: interruption))
        } else if let detail = outcome.metadataErrorDetail {
            self = .metadataNotSaved(detail: detail)
        } else {
            return nil
        }
    }

    private static func description(of interruption: RecordingInterruption) -> String {
        switch interruption {
        case .sourceLost(let name): String(localized: "“\(name)” stopped being available.")
        case .microphoneLost(let name): String(localized: "The microphone “\(name)” was removed.")
        case .systemAudioLost(let detail): String(localized: "System audio stopped: \(detail)")
        case .writeFailed(let detail): String(localized: "Writing to disk failed: \(detail)")
        }
    }
}

extension RecordingFailure {
    /// The callout that presents this failure.
    var presentedIssue: RecorderIssue {
        switch self {
        case .noCaptureSourceSelected: .windowUnavailable(name: String(localized: "The selected source"))
        case .noEnabledSource: .noAudioSource
        case .displayUnavailable(let name): .displayUnavailable(name: name)
        case .windowUnavailable(let name): .windowUnavailable(name: name)
        case .microphoneUnavailable(let name): .microphoneUnavailable(name: name)
        case .screenCaptureDenied: .screenRecordingPermission
        case .microphoneDenied: .microphonePermission
        case .destinationUnavailable(let path, _): .folderAccess(path: path)
        case .insufficientDiskSpace(let availableBytes): .insufficientDiskSpace(freeBytes: availableBytes)
        case .initializationFailed(let detail): .recordingFailed(detail: detail)
        case .noMediaCaptured: .nothingRecorded
        case .finalizationFailed(let detail, let directoryPath):
            .finalizationFailed(detail: detail, directoryPath: directoryPath)
        }
    }
}
