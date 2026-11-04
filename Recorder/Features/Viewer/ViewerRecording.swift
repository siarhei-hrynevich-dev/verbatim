import Foundation

/// A recording as the Viewer shows it: the Library entry, its transcript and the transcript's processing state.
struct ViewerRecording: Equatable, Sendable {
    enum TranscriptState: Equatable, Sendable {
        case ready
        /// `progress` is a fraction from 0 to 1.
        case processing(progress: Double)
        /// Processing stopped `stoppedAt` seconds into the recording; the media itself is intact.
        case failed(stoppedAt: TimeInterval)
        /// Recorded with automatic transcription off.
        case notProcessed
        /// No transcript exists and nothing can make one yet: the state of every real recording so far.
        case unavailable
    }

    let item: LibraryItem
    let transcript: [TranscriptLine]
    var transcriptState: TranscriptState
    let language: String

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
        }
    }
}
