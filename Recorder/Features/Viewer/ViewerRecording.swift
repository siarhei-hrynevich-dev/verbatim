import Foundation

/// A recording as the Viewer shows it: the Library entry, its transcript and the transcript's processing state.
struct ViewerRecording: Equatable, Sendable {
    enum TranscriptState: Equatable, Sendable {
        case ready
        /// `progress` is a fraction from 0 to 1.
        case processing(progress: Double)
        /// Processing stopped `stoppedAt` seconds into the recording; the media itself is intact.
        case failed(stoppedAt: TimeInterval)
        /// No transcript exists yet.
        case notProcessed
        /// No transcript exists and nothing is connected that can make one.
        case unavailable
    }

    let item: LibraryItem
    var transcript: [TranscriptLine]
    var transcriptState: TranscriptState
    var language: String

    var hasTranscript: Bool {
        transcriptState == .ready
    }

    /// The length of audio the transcript covers, which the waveform tracks are drawn across.
    var waveformSpan: TimeInterval {
        guard let last = transcript.last else {
            return item.duration
        }
        return min(item.duration, last.start + 20)
    }
}

/// One timestamped line of a transcript.
struct TranscriptLine: Identifiable, Equatable, Sendable {
    enum Speaker: Sendable {
        /// The microphone track.
        case you
        case systemAudio
        /// The tracks could not be told apart.
        case unknown
    }

    let id: Int
    let start: TimeInterval
    let speaker: Speaker
    let text: String
}

extension TranscriptLine.Speaker {
    var label: String {
        switch self {
        case .you: String(localized: "You")
        case .systemAudio: String(localized: "System Audio")
        case .unknown: String(localized: "Unknown")
        }
    }

    init(_ source: TranscriptSource) {
        switch source {
        case .microphone: self = .you
        case .systemAudio: self = .systemAudio
        case .unknown: self = .unknown
        }
    }
}

/// What a real recording's transcription is doing right now, whether or not a transcript exists meanwhile.
enum ViewerTranscriptActivity: Equatable, Sendable {
    enum Stage: Equatable, Sendable {
        case preparingModel
        /// `progress` is measured, from 0 to 1.
        case processingAudio(progress: Double?)
        case savingTranscript
    }

    case queued
    case running(Stage)
    /// Asked to stop, and on its way to a point where it can.
    case stopping
    case failed(TranscriptionIssue)
}
