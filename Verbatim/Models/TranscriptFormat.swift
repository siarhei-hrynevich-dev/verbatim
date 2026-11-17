import Foundation

/// The transcript file formats. Each is rendered from a stored transcript alone, so files can be regenerated at any
/// time and hold nothing that the database does not.
enum TranscriptFormat: String, CaseIterable, Sendable {
    case text = "txt"
    case subtitles = "srt"
    case json

    var fileName: String {
        "transcript.\(rawValue)"
    }

    func rendered(_ transcript: Transcript) throws -> Data {
        switch self {
        case .text: Data(Self.text(for: transcript).utf8)
        case .subtitles: Data(Self.subtitles(for: transcript).utf8)
        case .json: try Self.json(for: transcript)
        }
    }

    // MARK: - TXT

    /// One line per segment: `[00:01:02] You: Hello.`
    private static func text(for transcript: Transcript) -> String {
        transcript.segments
            .map { segment in
                let time = "[\(clockTime(segment.startTime))]"
                let label = segment.source.exportLabel.map { "\($0): " } ?? ""
                return "\(time) \(label)\(singleLine(segment.text))\n"
            }
            .joined()
    }

    // MARK: - SRT

    /// Cues keep the transcript's chronological order and each segment's own times. Where sources overlap, their cues
    /// overlap too, which SRT allows and players show stacked, and a label tells them apart; nothing is merged or
    /// retimed, so the same transcript always gives the same file.
    private static func subtitles(for transcript: Transcript) -> String {
        let hasSeveralSources = Set(transcript.segments.map(\.source)).count > 1
        return transcript.segments.enumerated()
            .map { index, segment in
                let end = max(milliseconds(segment.endTime), milliseconds(segment.startTime) + 1)
                let label = hasSeveralSources ? segment.source.exportLabel.map { "[\($0)] " } ?? "" : ""
                return """
                    \(index + 1)
                    \(subtitleTime(milliseconds(segment.startTime))) --> \(subtitleTime(end))
                    \(label)\(singleLine(segment.text))


                    """
            }
            .joined()
    }

    // MARK: - JSON

    private static func json(for transcript: Transcript) throws -> Data {
        let document = TranscriptDocument(
            formatVersion: 1,
            recordingID: transcript.recordingID,
            model: TranscriptDocument.Model(id: transcript.modelID, version: transcript.modelVersion),
            language: transcript.language,
            createdAt: transcript.createdAt,
            segments: transcript.segments.map {
                TranscriptDocument.Segment(
                    id: $0.id,
                    start: $0.startTime,
                    end: $0.endTime,
                    text: $0.text,
                    source: $0.source
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    // MARK: - Formatting

    /// A blank line would end an SRT cue early, and a line break would split a TXT entry.
    private static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    private static func milliseconds(_ seconds: TimeInterval) -> Int {
        Int((seconds * 1_000).rounded())
    }

    private static func clockTime(_ seconds: TimeInterval) -> String {
        let total = milliseconds(seconds) / 1_000
        return String(format: "%02d:%02d:%02d", total / 3_600, total / 60 % 60, total % 60)
    }

    /// `00:01:02,500`, as SRT requires.
    private static func subtitleTime(_ milliseconds: Int) -> String {
        let seconds = milliseconds / 1_000
        return String(
            format: "%02d:%02d:%02d,%03d",
            seconds / 3_600,
            seconds / 60 % 60,
            seconds % 60,
            milliseconds % 1_000
        )
    }
}

extension TranscriptSource {
    /// Files are not localized, so that they read the same wherever they are opened. `nil` when there's nothing to say.
    fileprivate var exportLabel: String? {
        switch self {
        case .microphone: "You"
        case .systemAudio: "System Audio"
        case .unknown: nil
        }
    }
}

/// The JSON file: everything needed to use the transcript without this app, namely times, sources and which model
/// produced it.
private struct TranscriptDocument: Codable {
    struct Model: Codable {
        let id: String
        let version: String?
    }

    struct Segment: Codable {
        let id: UUID
        let start: TimeInterval
        let end: TimeInterval
        let text: String
        let source: TranscriptSource
    }

    let formatVersion: Int
    let recordingID: UUID
    let model: Model
    let language: String?
    let createdAt: Date
    let segments: [Segment]
}
