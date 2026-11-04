import Foundation

/// A recording as the Library lists it: one folder on disk with its media, transcript files and processing state.
struct LibraryItem: Identifiable, Equatable, Sendable {
    enum Kind: Sendable {
        case screen
        case audio
    }

    enum Status: Equatable, Sendable {
        case ready
        /// `progress` is a fraction from 0 to 1.
        case transcribing(progress: Double)
        /// `progress` is a fraction from 0 to 1.
        case indexing(progress: Double)
        /// Saved without a transcript, for example with auto-transcription off.
        case recorded
        case failed
        /// The recording folder is no longer where the Library expects it.
        case missing
    }

    let id: UUID
    let title: String
    let recordedAt: Date
    let duration: TimeInterval
    let sizeBytes: Int64
    let kind: Kind
    var status: Status
    /// The recording's folder inside the recordings folder, such as `2026-11-03 Architecture Review`.
    let folderName: String

    /// Every recording folder holds the media file and three transcript formats.
    var fileNames: [String] {
        [kind == .audio ? "recording.m4a" : "recording.mov", "transcript.txt", "transcript.srt", "transcript.json"]
    }

    var hasTranscript: Bool {
        switch status {
        case .ready, .indexing: true
        case .transcribing, .recorded, .failed, .missing: false
        }
    }

    /// Progress of the transcript or search index, while one is being built.
    var processingProgress: Double? {
        switch status {
        case .transcribing(let progress), .indexing(let progress): progress
        case .ready, .recorded, .failed, .missing: nil
        }
    }

    /// Whether transcription can be started: the recording has no transcript yet, or processing failed.
    var canStartProcessing: Bool {
        status == .recorded || status == .failed
    }
}
