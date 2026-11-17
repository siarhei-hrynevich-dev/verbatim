import Foundation

/// What the tools return, in the shape agents read: snake_case keys, dates in ISO 8601 with the Mac's offset, times in
/// seconds with a clock label, and a `verbatim://` link wherever a moment can be opened.
enum MCPToolOutput {
    struct Processing: Encodable {
        let transcript: String
        let summary: String
        let index: String
    }

    struct Recording: Encodable {
        let id: String
        let title: String
        let recordedAt: Date
        let duration: Double
        let durationLabel: String
        let type: String
        let tags: [String]
        let processing: Processing
        let link: String
    }

    struct RecordingList: Encodable {
        let now: Date
        let totalCount: Int
        let nextCursor: String?
        let recordings: [Recording]
    }

    struct TranscriptInfo: Encodable {
        let language: String?
        let model: String
        let createdAt: Date
        let segmentCount: Int
        let speakers: [String]
    }

    struct SummaryInfo: Encodable {
        let language: String?
        let model: String
        let createdAt: Date
        let isCurrent: Bool
        let partCount: Int
    }

    struct Details: Encodable {
        let recording: Recording
        let transcript: TranscriptInfo?
        let summary: SummaryInfo?
    }

    struct Hit: Encodable {
        let chunkID: Int64
        let recordingID: String
        let recordingTitle: String
        let recordedAt: Date
        let source: String
        let start: Double?
        let end: Double?
        let startLabel: String?
        let firstSegment: Int?
        let lastSegment: Int?
        let text: String
        let matchedBy: [String]
        let similarity: Double?
        let link: String
    }

    struct Search: Encodable {
        let now: Date
        let semanticSearch: String
        let semanticSearchNote: String?
        let hits: [Hit]
    }

    struct SummaryPart: Encodable {
        let start: Double
        let end: Double
        let startLabel: String
        let endLabel: String
        let firstSegment: Int
        let lastSegment: Int
        let text: String
        let link: String
    }

    struct Summary: Encodable {
        let recordingID: String
        let recordingTitle: String
        let language: String?
        let model: String
        let createdAt: Date
        let isCurrent: Bool
        let text: String
        let parts: [SummaryPart]
    }

    struct Line: Encodable {
        let index: Int
        let start: Double
        let end: Double
        let startLabel: String
        let speaker: String
        let text: String
    }

    struct Transcript: Encodable {
        let recordingID: String
        let recordingTitle: String
        let language: String?
        let totalSegments: Int
        let segments: [Line]
        let truncated: Bool
        let nextFrom: Double?
        let link: String?
    }

    struct Tag: Encodable {
        let name: String
        let color: String
        let recordingCount: Int
    }

    struct Tags: Encodable {
        let tags: [Tag]
    }
}

// MARK: - Mapping

extension MCPToolOutput {
    static func recording(_ overview: RecordingOverview) -> Recording {
        let recording = overview.recording
        return Recording(
            id: recording.id.uuidString,
            title: recording.recording.title,
            recordedAt: recording.recording.createdAt,
            duration: seconds(recording.recording.duration),
            durationLabel: clockLabel(recording.recording.duration),
            type: recording.captureMode.capturesVideo ? "video" : "audio",
            tags: overview.tags.map(\.name),
            processing: Processing(
                transcript: overview.pipeline.transcript.rawValue,
                summary: overview.pipeline.summary.rawValue,
                index: overview.pipeline.index.rawValue
            ),
            link: RecordingLink(recordingID: recording.id).url.absoluteString
        )
    }

    static func details(_ details: RecordingDetails) -> Details {
        Details(
            recording: recording(details.overview),
            transcript: details.transcript.map { info in
                TranscriptInfo(
                    language: info.language,
                    model: info.modelID,
                    createdAt: info.createdAt,
                    segmentCount: info.segmentCount,
                    speakers: info.sources.map(speaker)
                )
            },
            summary: details.summary.map { info in
                SummaryInfo(
                    language: info.language,
                    model: info.modelID,
                    createdAt: info.createdAt,
                    isCurrent: info.isCurrent,
                    partCount: info.partCount
                )
            }
        )
    }

    static func search(_ result: RecordingSearchResult, now: Date) -> Search {
        Search(
            now: now,
            semanticSearch: semanticStatus(result.semanticStatus),
            semanticSearchNote: semanticNote(result.semanticStatus),
            hits: result.hits.map(hit)
        )
    }

    private static func hit(_ hit: RecordingSearchHit) -> Hit {
        let chunk = hit.record.chunk
        let span = chunk.timeSpan
        return Hit(
            chunkID: hit.record.chunkID,
            recordingID: chunk.recordingID.uuidString,
            recordingTitle: hit.record.recordingTitle,
            recordedAt: hit.record.recordingCreatedAt,
            source: chunk.kind.rawValue,
            start: span.map { seconds($0.lowerBound) },
            end: span.map { seconds($0.upperBound) },
            startLabel: span.map { clockLabel($0.lowerBound) },
            firstSegment: chunk.segments?.lowerBound,
            lastSegment: chunk.segments?.upperBound,
            text: chunk.text,
            matchedBy: [SearchMatch.semantic, .lexical].filter(hit.matches.contains).map(matchName),
            similarity: hit.similarity.map { ($0 * 1_000).rounded() / 1_000 },
            link: RecordingLink(recordingID: chunk.recordingID, time: span?.lowerBound).url.absoluteString
        )
    }

    static func summary(_ found: RecordingSummary) -> Summary {
        let summary = found.summary
        return Summary(
            recordingID: found.recording.id.uuidString,
            recordingTitle: found.recording.recording.title,
            language: summary.language,
            model: summary.modelID,
            createdAt: summary.createdAt,
            isCurrent: found.isCurrent,
            text: summary.text,
            parts: summary.parts.map { part in
                SummaryPart(
                    start: seconds(part.startTime),
                    end: seconds(part.endTime),
                    startLabel: clockLabel(part.startTime),
                    endLabel: clockLabel(part.endTime),
                    firstSegment: part.firstSegment,
                    lastSegment: part.lastSegment,
                    text: part.text,
                    link: RecordingLink(recordingID: found.recording.id, time: part.startTime).url.absoluteString
                )
            }
        )
    }

    static func transcript(_ excerpt: TranscriptExcerpt) -> Transcript {
        let firstStart = excerpt.lines.first?.segment.startTime
        return Transcript(
            recordingID: excerpt.recording.id.uuidString,
            recordingTitle: excerpt.recording.recording.title,
            language: excerpt.language,
            totalSegments: excerpt.totalSegmentCount,
            segments: excerpt.lines.map { line in
                Line(
                    index: line.index,
                    start: seconds(line.segment.startTime),
                    end: seconds(line.segment.endTime),
                    startLabel: clockLabel(line.segment.startTime),
                    speaker: speaker(line.segment.source),
                    text: line.segment.text
                )
            },
            truncated: excerpt.continuesFrom != nil,
            nextFrom: excerpt.continuesFrom.map(seconds),
            link: firstStart.map { RecordingLink(recordingID: excerpt.recording.id, time: $0).url.absoluteString }
        )
    }

    static func tags(_ usage: [TagUsage]) -> Tags {
        Tags(
            tags: usage.map { Tag(name: $0.tag.name, color: $0.tag.color.rawValue, recordingCount: $0.recordingCount) }
        )
    }

    // MARK: Values

    static func speaker(_ source: TranscriptSource) -> String {
        switch source {
        case .microphone: "microphone"
        case .systemAudio: "system_audio"
        case .unknown: "unknown"
        }
    }

    private static func matchName(_ match: SearchMatch) -> String {
        switch match {
        case .semantic: "meaning"
        case .lexical: "words"
        }
    }

    private static func semanticStatus(_ status: SemanticSearchStatus) -> String {
        switch status {
        case .used: "used"
        case .noModel: "no_model"
        case .modelUnavailable: "model_unavailable"
        case .pausedForRecording: "paused_for_recording"
        case .failed: "failed"
        }
    }

    private static func semanticNote(_ status: SemanticSearchStatus) -> String? {
        switch status {
        case .used:
            nil
        case .noModel:
            "Only words were matched: no semantic search model is selected in Verbatim › Settings › AI Models."
        case .modelUnavailable:
            "Only words were matched: the semantic search model's files are missing; repair it in Verbatim › Settings."
        case .pausedForRecording:
            "Only words were matched: a recording is in progress, and no model is loaded while recording."
        case .failed(let detail):
            "Only words were matched: search by meaning failed (\(detail))."
        }
    }

    /// Tenths of a second are as precise as transcripts are.
    static func seconds(_ value: TimeInterval) -> Double {
        (value * 10).rounded() / 10
    }

    static func clockLabel(_ value: TimeInterval) -> String {
        let total = Int(max(value, 0).rounded(.down))
        return String(format: "%02d:%02d:%02d", total / 3_600, total / 60 % 60, total % 60)
    }
}
