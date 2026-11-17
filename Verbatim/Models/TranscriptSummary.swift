import Foundation

/// Notes on one consecutive batch of a transcript. They are kept with the summary, with the time span and segment
/// positions they cover, so that later work such as semantic search can index a recording by its parts.
struct SummaryPart: Equatable, Codable, Sendable {
    /// Order within the summary, from 0.
    let position: Int
    let startTime: TimeInterval
    let endTime: TimeInterval
    /// Positions of the first and last transcript segment in the batch, in the transcript's stored order.
    let firstSegment: Int
    let lastSegment: Int
    let text: String
}

/// A finished summary of a recording's transcript. One exists per recording, and only complete ones are stored.
struct TranscriptSummary: Equatable, Sendable {
    let recordingID: UUID
    let modelID: LanguageModel.ID
    /// The code of the language the summary is written in, as chosen in Settings when it was made. `nil` only for
    /// summaries stored without one.
    let language: String?
    /// When the summarized transcript was made. A transcript made later means the summary is out of date.
    let transcriptCreatedAt: Date
    let createdAt: Date
    let text: String
    let parts: [SummaryPart]

    func isCurrent(for transcript: Transcript) -> Bool {
        abs(transcript.createdAt.timeIntervalSince(transcriptCreatedAt)) < 0.001
    }
}

/// Why a summary could not be made. Stopping on request is not a failure. User-facing wording belongs to Presentation.
enum SummaryFailure: Error, Equatable, Sendable {
    case noModelSelected
    /// Selected, but its files are missing or damaged.
    case modelUnavailable(LanguageModel.ID)
    case modelLoadFailed(detail: String)
    case noTranscript
    /// The transcript holds no speech to summarize.
    case emptyTranscript
    case generationFailed(detail: String)
    case persistenceFailed(detail: String)

    /// Translates what the steps of a summary can throw. Cancellation has to be handled before this.
    init(_ error: any Error) {
        switch error {
        case let failure as SummaryFailure:
            self = failure
        case ModelManagementError.noModelSelected:
            self = .noModelSelected
        case ModelManagementError.selectedModelUnavailable(let id):
            self = .modelUnavailable(id)
        case let error as LibraryError:
            self = .persistenceFailed(detail: String(describing: error))
        default:
            self = .generationFailed(detail: error.localizedDescription)
        }
    }
}

/// Summarizing one recording, while it is queued or running. Jobs live in memory only: one interrupted by the app
/// quitting is asked for again, and a finished one leaves nothing but its summary.
struct SummaryJob: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case queued
        case loadingModel
        /// Writing notes on batch `completed + 1` of `total`.
        case summarizingParts(completed: Int, total: Int)
        case combining
        case saving
        case failed(SummaryFailure)

        var isActive: Bool {
            if case .failed = self {
                return false
            }
            return true
        }
    }

    let recordingID: UUID
    var state: State
    var queuedAt: Date
}

/// Splits consecutive items into batches that fit a token budget, keeping their order. An item larger than the budget
/// gets a batch of its own rather than being cut, since a sentence split in two summarizes worse than a long batch.
enum SummaryBatching {
    static func batches(tokenCounts: [Int], limit: Int) -> [Range<Int>] {
        var batches: [Range<Int>] = []
        var start = 0
        var total = 0
        for (index, count) in tokenCounts.enumerated() {
            if index > start, total + count > limit {
                batches.append(start..<index)
                start = index
                total = 0
            }
            total += count
        }
        if start < tokenCounts.count {
            batches.append(start..<tokenCounts.count)
        }
        return batches
    }
}
