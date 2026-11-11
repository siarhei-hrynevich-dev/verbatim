import Foundation

/// A server that answers AI agents on this Mac. Implemented by the MCP server over HTTP.
protocol AgentServerHosting: Sendable {
    /// Starts listening on the loopback interface, accepting only requests with the token, and returns the port it
    /// listens on (the one asked for, or a free one for port 0). Throws `AgentServerFailure`. Already listening on
    /// the port, it only takes the new token; on another port, it stops listening there first.
    func start(port: Int, token: String) async throws -> Int
    /// Closes the port and every connection. Safe to call when stopped.
    func stop() async
}

/// Stores the server's settings, the token included.
protocol AgentServerSettingsRepository: Sendable {
    /// `nil` when nothing usable is stored yet, so a token has to be made.
    func loadSettings() -> AgentServerSettings?
    func saveSettings(_ settings: AgentServerSettings)
}

/// Post-processing jobs of one recording that are queued, running or failed, as their coordinators hold them.
struct RecordingActivity: Equatable, Sendable {
    var transcription: TranscriptionJob.State?
    var summary: SummaryJob.State?
    var indexing: IndexingJob.State?
}

/// Where one step after a recording stands, as an agent needs to know it.
enum PipelineStepStatus: String, Sendable {
    case ready
    case queued
    case running
    case failed
    /// Never done or asked for, as without a model selected.
    case none
}

/// Transcription, summary and search index of one recording.
struct RecordingPipelineStatus: Equatable, Sendable {
    let transcript: PipelineStepStatus
    let summary: PipelineStepStatus
    let index: PipelineStepStatus
}

/// A recording with what an agent sees about it in a list.
struct RecordingOverview: Equatable, Sendable {
    let recording: LibraryRecording
    /// In the order the Library shows them.
    let tags: [RecordingTag]
    let pipeline: RecordingPipelineStatus
}

/// Conditions shared by listing and searching. Every condition given must hold.
struct RecordingKnowledgeFilter: Equatable, Sendable {
    var createdFrom: Date?
    var createdBefore: Date?
    /// Recordings with at least one of these tags, by name, ignoring case and accents.
    var tagNames: [String] = []
}

struct RecordingListRequest: Equatable, Sendable {
    var filter = RecordingKnowledgeFilter()
    /// Matched against titles.
    var titleText: String?
    var captureModes: [CaptureMode] = []
    var sortOrder = RecordingSortOrder.newestFirst
    var offset = 0
    var limit = 20
}

struct RecordingListPage: Equatable, Sendable {
    let recordings: [RecordingOverview]
    let totalCount: Int
    /// Where the next page starts; `nil` on the last one.
    let nextOffset: Int?
}

/// A recording with what is known about its transcript and summary.
struct RecordingDetails: Equatable, Sendable {
    struct TranscriptInfo: Equatable, Sendable {
        let language: String?
        let modelID: SpeechModel.ID
        let createdAt: Date
        let segmentCount: Int
        let sources: [TranscriptSource]
    }

    struct SummaryInfo: Equatable, Sendable {
        let language: String?
        let modelID: LanguageModel.ID
        let createdAt: Date
        /// False when the transcript was made again after the summary.
        let isCurrent: Bool
        let partCount: Int
    }

    let overview: RecordingOverview
    let transcript: TranscriptInfo?
    let summary: SummaryInfo?
}

/// A recording's summary, and whether it still describes the current transcript.
struct RecordingSummary: Equatable, Sendable {
    let recording: LibraryRecording
    let summary: TranscriptSummary
    let isCurrent: Bool
}

/// Which part of a transcript to read.
enum TranscriptWindow: Equatable, Sendable {
    /// Segments starting within the range; an open end reaches the start or the end of the recording.
    case range(start: TimeInterval?, end: TimeInterval?)
    /// Segments around a search result, with some seconds of context on each side.
    case aroundChunk(Int64, contextSeconds: TimeInterval)
}

/// Consecutive segments of a transcript, cut to a size an agent can read.
struct TranscriptExcerpt: Equatable, Sendable {
    struct Line: Equatable, Sendable {
        /// The segment's position in the whole transcript, as search results give it.
        let index: Int
        let segment: TranscriptSegment
    }

    let recording: LibraryRecording
    let language: String?
    let lines: [Line]
    let totalSegmentCount: Int
    /// Where reading continues when the excerpt was cut short of its window; `nil` when nothing was left out.
    let continuesFrom: TimeInterval?
}

/// How many recordings carry a tag.
struct TagUsage: Equatable, Sendable {
    let tag: RecordingTag
    let recordingCount: Int
}

/// Why an agent's request could not be answered. Wording belongs to the adapter that answers the agent.
enum RecordingKnowledgeError: Error, Equatable, Sendable {
    case recordingNotFound(UUID)
    case unknownTags([String], available: [String])
    case transcriptUnavailable(UUID, status: PipelineStepStatus)
    case summaryUnavailable(UUID, status: PipelineStepStatus)
    case chunkNotFound(Int64)
    /// The search result belongs to another recording than the one asked about.
    case chunkInOtherRecording(Int64, recordingID: UUID)
    /// A search result for the whole summary, which has no place on the timeline.
    case chunkWithoutTime(Int64)
    case invalidTimeRange
    case storageFailed(detail: String)
}
