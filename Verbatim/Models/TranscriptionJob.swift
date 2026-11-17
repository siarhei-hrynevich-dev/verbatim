import Foundation

/// The durable record of transcribing one recording. There is at most one per recording, which is what rules out
/// duplicate work; retrying or re-transcribing reuses it.
struct TranscriptionJob: Identifiable, Equatable, Sendable {
    enum State: String, CaseIterable, Sendable {
        case pending
        /// Checking the model and media, and loading the model.
        case preparing
        case transcribing
        case saving
        case completed
        case failed
        case cancelled

        /// Queued or running: asking again does nothing.
        var isActive: Bool {
            switch self {
            case .pending, .preparing, .transcribing, .saving: true
            case .completed, .failed, .cancelled: false
            }
        }

        /// Running jobs go back to `pending` when a recording takes priority, or when a restart finds them unfinished.
        func allowsTransition(to next: State) -> Bool {
            switch (self, next) {
            case (.pending, .preparing), (.pending, .failed), (.pending, .cancelled):
                true
            case (.preparing, .transcribing), (.preparing, .saving), (.preparing, .pending), (.preparing, .failed),
                (.preparing, .cancelled):
                true
            case (.transcribing, .saving), (.transcribing, .pending), (.transcribing, .failed),
                (.transcribing, .cancelled):
                true
            case (.saving, .completed), (.saving, .pending), (.saving, .failed), (.saving, .cancelled):
                true
            case (.completed, .pending), (.failed, .pending), (.cancelled, .pending):
                true
            default:
                false
            }
        }

        /// What the Library's status column stores for this state. A stopped job leaves the recording as it was: with
        /// its transcript if it has one, since only a finished replacement ever touches that.
        func recordingStatus(hasTranscript: Bool) -> Recording.ProcessingStatus {
            switch self {
            case .pending: .pending
            case .preparing, .transcribing, .saving: .transcribing
            case .completed: .ready
            case .failed: .failed
            case .cancelled: hasTranscript ? .ready : .recorded
            }
        }
    }

    let recordingID: UUID
    var state: State
    /// When the job joined the queue, which decides its turn. Keeps its place when a recording interrupts it.
    var queuedAt: Date
    var updatedAt: Date
    /// How many times it has started running, for diagnosis.
    var attempts = 0
    /// The model of the latest attempt, known once that attempt has resolved one.
    var modelID: SpeechModel.ID?
    var failure: TranscriptionFailure?
    /// The transcript is saved, but its files beside the media could not be written. They can be exported again.
    var exportFailureDetail: String?

    var id: UUID {
        recordingID
    }
}

/// Why transcribing failed. Stopping on request is not a failure: that is `CancellationError` and the `cancelled`
/// state. The media is never touched by any of these. User-facing wording belongs to Presentation.
enum TranscriptionFailure: Error, Equatable, Codable, Sendable {
    case noModelSelected
    /// Selected, but its files are missing or damaged.
    case modelUnavailable(SpeechModel.ID)
    case modelLoadFailed(detail: String)
    case mediaUnavailable(MediaAvailability)
    case recordingNotFound
    /// The file holds no audio that could be read, such as a video recorded without sound.
    case noAudio
    case unsupportedAudio(detail: String)
    case audioExtractionFailed(detail: String)
    case recognitionFailed(detail: String)
    case insufficientDiskSpace(requiredBytes: Int64, availableBytes: Int64)
    case persistenceFailed(detail: String)

    /// Translates what the steps of a job can throw. Cancellation has to be handled before this.
    init(_ error: any Error) {
        switch error {
        case let failure as TranscriptionFailure:
            self = failure
        case ModelManagementError.noModelSelected:
            self = .noModelSelected
        case ModelManagementError.selectedModelUnavailable(let id):
            self = .modelUnavailable(id)
        case LibraryError.recordingNotFound:
            self = .recordingNotFound
        case LibraryError.mediaUnavailable(let availability):
            self = .mediaUnavailable(availability)
        case let error as LibraryError:
            self = .persistenceFailed(detail: String(describing: error))
        default:
            self = .recognitionFailed(detail: error.localizedDescription)
        }
    }
}

/// How far a running job has come, as measured by the recognizer.
enum TranscriptionUpdate: Equatable, Sendable {
    case loadingModel
    /// The share of the recording's audio finished, from 0 to 1.
    case processingAudio(fraction: Double)
}
