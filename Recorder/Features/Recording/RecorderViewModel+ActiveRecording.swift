import Foundation

/// What the Recording state shows: the settings the recording started with, not whatever the controls hold.
extension RecorderViewModel {
    private var activeRecording: RecordingCoordinator.ActiveRecording? {
        coordinator.activeRecording
    }

    var activeCaptureMode: CaptureMode {
        activeRecording?.configuration.target?.mode ?? captureMode
    }

    var activeSourceName: String {
        activeRecording?.sourceName ?? makeConfiguration().sourceName
    }

    var activeVideoSummary: String {
        let quality = activeRecording?.configuration.quality ?? quality
        let frameRate = activeRecording?.configuration.frameRate ?? frameRate
        return "\(quality.rawValue) · \(frameRate.rawValue) fps"
    }

    var activeMicrophoneName: String {
        activeRecording?.configuration.microphone?.name ?? selectedMicrophone?.name ?? ""
    }

    var isMicrophoneActive: Bool {
        activeRecording?.isMicrophoneActive ?? isMicrophoneEnabled
    }

    var isSystemAudioActive: Bool {
        activeRecording?.isSystemAudioActive ?? isSystemAudioEnabled
    }
}
