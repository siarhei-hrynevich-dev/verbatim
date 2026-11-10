import Foundation

/// What a vector was made with. Vectors are compared only within one space: another model, another revision of it or
/// another length makes vectors that mean nothing to each other, so changing the model means indexing again.
struct EmbeddingSpace: Hashable, Sendable {
    let modelID: EmbeddingModel.ID
    let revision: String
    let dimensions: Int
}

/// Where the text of a search chunk comes from. The raw value is what the database stores, so it must never change.
enum SearchChunkKind: String, CaseIterable, Hashable, Sendable {
    /// Consecutive transcript segments, with the time span they cover.
    case transcript
    /// The summary of the whole recording.
    case summary
    /// The notes on one batch of the transcript, with its time span.
    case summaryPart = "summary_part"
}

/// One unit of recorded content that search finds and returns: short enough for an embedding model to read whole, and
/// placed on the recording's timeline where it can be, so a result can open the recording at that moment.
struct SearchChunk: Equatable, Sendable {
    let recordingID: UUID
    let kind: SearchChunkKind
    /// Order among the recording's chunks of the same kind, from 0.
    let position: Int
    /// `nil` for the summary of the whole recording, which belongs to no moment.
    let timeSpan: ClosedRange<TimeInterval>?
    /// Positions of the first and last transcript segment covered, in the transcript's stored order.
    let segments: ClosedRange<Int>?
    let text: String
}

/// The versions of the content a recording's chunks were made from. A newer transcript or summary means its chunks are
/// made again; the index is derived data and can always be rebuilt from them.
struct SearchIndexState: Equatable, Sendable {
    var transcriptCreatedAt: Date?
    var summaryCreatedAt: Date?

    static let empty = SearchIndexState()
}

/// Splits a recording's transcript and summary into search chunks. Sizes are in characters rather than tokens, so the
/// chunks do not depend on which embedding model is installed, or on one being installed at all: full-text search uses
/// the same chunks, and switching models only makes vectors again.
enum SearchChunker {
    /// About 250 to 400 tokens in the vocabulary of the multilingual models, well inside the 512 they read.
    static let maxCharacters = 1_000
    /// Keeps a chunk to one moment of a conversation, so the time a result points to is close to what it says.
    static let maxDuration: TimeInterval = 90

    /// Consecutive segments up to the limits. The last segment of a chunk starts the next one too, so speech on a
    /// boundary is found whole; a segment over the limits gets a chunk of its own rather than being cut.
    static func chunks(of transcript: Transcript) -> [SearchChunk] {
        let segments = transcript.segments
        var chunks: [SearchChunk] = []
        var start = 0
        while start < segments.count {
            var end = start
            while end + 1 < segments.count, fits(segments[start...(end + 1)]) {
                end += 1
            }
            let covered = segments[start...end]
            let endTime = covered.map(\.endTime).max() ?? covered[start].endTime
            chunks.append(
                SearchChunk(
                    recordingID: transcript.recordingID,
                    kind: .transcript,
                    position: chunks.count,
                    timeSpan: covered[start].startTime...endTime,
                    segments: start...end,
                    text: covered.map(\.text).joined(separator: "\n")
                )
            )
            guard end + 1 < segments.count else {
                break
            }
            let overlapsNext = end > start && fits(segments[end...(end + 1)])
            start = overlapsNext ? end : end + 1
        }
        return chunks
    }

    /// The summary in pieces of whole lines, then the notes on each batch with the time span they cover.
    static func chunks(of summary: TranscriptSummary) -> [SearchChunk] {
        var chunks = pieces(of: summary.text).enumerated().map { position, text in
            SearchChunk(
                recordingID: summary.recordingID,
                kind: .summary,
                position: position,
                timeSpan: nil,
                segments: nil,
                text: text
            )
        }
        var position = 0
        for part in summary.parts {
            for text in pieces(of: part.text) {
                chunks.append(
                    SearchChunk(
                        recordingID: summary.recordingID,
                        kind: .summaryPart,
                        position: position,
                        timeSpan: part.startTime...max(part.startTime, part.endTime),
                        segments: part.firstSegment...max(part.firstSegment, part.lastSegment),
                        text: text
                    )
                )
                position += 1
            }
        }
        return chunks
    }

    private static func fits(_ segments: ArraySlice<TranscriptSegment>) -> Bool {
        guard let first = segments.first else {
            return true
        }
        let characters = segments.reduce(segments.count - 1) { $0 + $1.text.count }
        let end = segments.map(\.endTime).max() ?? first.endTime
        return characters <= maxCharacters && end - first.startTime <= maxDuration
    }

    /// Non-empty lines grouped up to the character limit. A line over the limit stays whole, as a piece of its own.
    private static func pieces(of text: String) -> [String] {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var pieces: [String] = []
        var current: [String] = []
        var characters = 0
        for line in lines {
            if !current.isEmpty, characters + 1 + line.count > maxCharacters {
                pieces.append(current.joined(separator: "\n"))
                current = []
                characters = 0
            }
            characters += current.isEmpty ? line.count : line.count + 1
            current.append(line)
        }
        if !current.isEmpty {
            pieces.append(current.joined(separator: "\n"))
        }
        return pieces
    }
}
