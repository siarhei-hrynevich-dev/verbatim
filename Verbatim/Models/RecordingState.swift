import Foundation

/// Why a recording could not start or could not be finished. Associated strings keep the underlying error for
/// diagnostics and the names the user recognizes; user-facing wording belongs to Presentation.
enum RecordingFailure: Error, Equatable, Sendable {
    case noCaptureSourceSelected
    case noEnabledSource
    case displayUnavailable(name: String)
    case windowUnavailable(name: String)
    case microphoneUnavailable(name: String)
    case screenCaptureDenied
    case microphoneDenied
    case destinationUnavailable(path: String, detail: String)
    case insufficientDiskSpace(availableBytes: Int64)
    case initializationFailed(detail: String)
    /// Capture ended before anything was written, so there is no media to keep.
    case noMediaCaptured
    /// The media could not be closed or failed validation. Whatever was written stays at `directoryPath`.
    case finalizationFailed(detail: String, directoryPath: String)
}

/// The recording lifecycle. Only `RecordingCoordinator` advances it, through `allowsTransition(to:)`.
enum RecordingState: Equatable, Sendable {
    case idle
    case preparing
    case recording(RecordingClock)
    case stopping(RecordingClock)
    case finalizing(RecordingClock)
    case failed(RecordingFailure)

    var acceptsStart: Bool {
        switch self {
        case .idle, .failed: true
        case .preparing, .recording, .stopping, .finalizing: false
        }
    }

    var acceptsStop: Bool {
        if case .recording = self {
            return true
        }
        return false
    }

    /// Whether work is underway that quitting the app would interrupt.
    var isBusy: Bool {
        switch self {
        case .idle, .failed: false
        case .preparing, .recording, .stopping, .finalizing: true
        }
    }

    func allowsTransition(to next: RecordingState) -> Bool {
        switch (self, next) {
        case (.idle, .preparing), (.failed, .preparing), (.failed, .idle),
            (.preparing, .recording), (.preparing, .failed),
            (.recording, .recording), (.recording, .stopping),
            (.stopping, .finalizing), (.stopping, .failed),
            (.finalizing, .idle), (.finalizing, .failed):
            true
        default:
            false
        }
    }
}
