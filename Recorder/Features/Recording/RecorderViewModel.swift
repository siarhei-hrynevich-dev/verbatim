import Foundation
import Observation

/// Presentation state of the Recorder window.
///
/// This is a layout-only implementation: starting, pausing and stopping only change local state, and issue
/// actions simulate their fix or fallback. No capture, permission, storage or processing service is involved yet.
@MainActor
@Observable
final class RecorderViewModel {
    enum Phase: Equatable {
        case ready
        case recording(RecordingClock)
    }

    enum Status {
        case ready
        case needsAttention
        case recording
        case paused
    }

    let sources: RecorderPreviewData

    private(set) var phase: Phase = .ready
    private(set) var issue: RecorderIssue?
    private(set) var hasSavedRecording = false

    var captureMode: CaptureMode = .screen
    var selectedDisplayID: CaptureDisplay.ID
    var selectedWindowID: CaptureWindow.ID
    var selectedMicrophone: String
    var isMicrophoneEnabled = true
    var isSystemAudioEnabled = true
    var quality: VideoQuality = .hd1080
    var frameRate: FrameRate = .fps60
    var transcribesWhenFinished = true

    init(sources: RecorderPreviewData = .sample, scenario: RecorderPreviewScenario = .idle) {
        self.sources = sources
        selectedDisplayID = sources.displays.first?.id ?? ""
        selectedWindowID = sources.windows.first?.id ?? ""
        selectedMicrophone = sources.microphones.first ?? ""
        apply(scenario)
    }

    var status: Status {
        if case .recording(let clock) = phase {
            return clock.isPaused ? .paused : .recording
        }
        return issue == nil ? .ready : .needsAttention
    }

    var canStartRecording: Bool {
        guard let issue, issue.blocksVideoCapture else {
            return true
        }
        return !captureMode.capturesVideo
    }

    var selectedDisplay: CaptureDisplay? {
        sources.displays.first { $0.id == selectedDisplayID }
    }

    var selectedWindow: CaptureWindow? {
        sources.windows.first { $0.id == selectedWindowID }
    }

    // MARK: - Recording

    func startRecording(at date: Date = .now) {
        guard phase == .ready, canStartRecording else {
            return
        }
        hasSavedRecording = false
        phase = .recording(RecordingClock(startedAt: date))
    }

    func togglePause(at date: Date = .now) {
        guard case .recording(var clock) = phase else {
            return
        }
        if clock.isPaused {
            clock.resume(at: date)
        } else {
            clock.pause(at: date)
        }
        phase = .recording(clock)
    }

    func stopRecording() {
        guard case .recording = phase else {
            return
        }
        phase = .ready
        hasSavedRecording = true
    }

    // MARK: - Issues

    /// Simulates the issue's fix, as if the user resolved it in System Settings or a picker.
    func performIssuePrimaryAction() {
        guard let issue else {
            return
        }
        if issue == .sourceUnavailable {
            captureMode = .window
        }
        self.issue = nil
    }

    /// Applies the issue's fallback. Record Audio Only keeps the permission callout visible but re-enables Start.
    func performIssueSecondaryAction() {
        switch issue {
        case .screenRecordingPermission:
            captureMode = .audioOnly
            return
        case .microphonePermission:
            isMicrophoneEnabled = false
        case .sourceUnavailable:
            captureMode = .screen
        case .lowDiskSpace:
            quality = .hd720
        case .folderAccess, nil:
            break
        }
        issue = nil
    }

    // MARK: - Preview scenarios

    func apply(_ scenario: RecorderPreviewScenario, at date: Date = .now) {
        captureMode = scenario == .picker ? .window : .screen
        issue = scenario.issue
        hasSavedRecording = scenario == .saved
        phase = .ready
        if scenario == .recording {
            phase = .recording(RecordingClock(startedAt: date.addingTimeInterval(-Self.sampleElapsedSeconds)))
        }
    }

    /// The design shows a recording that has been running for 12:34.
    private static let sampleElapsedSeconds: TimeInterval = 754
}
