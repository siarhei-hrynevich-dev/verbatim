import Foundation

/// What AI agents can learn about recordings: listing them, searching them, and reading their summaries and
/// transcripts. Read-only: nothing here changes the Library or starts any work.
///
/// The entry point for the MCP server, which only translates between this and the protocol. Search itself belongs to
/// `RecordingSearchService`, which this resolves filters for.
@MainActor
final class RecordingKnowledgeService {
    struct Dependencies {
        let recordings: any RecordingRepository
        let transcripts: any TranscriptRepository
        let summaries: any SummaryRepository
        let index: any SearchIndexRepository
        let search: RecordingSearchService
        /// The jobs the coordinators hold for a recording right now.
        let activity: @MainActor (UUID) -> RecordingActivity
    }

    static let maximumListLimit = 100
    static let maximumSearchLimit = 50

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    // MARK: - Reading

    /// Throws `RecordingKnowledgeError`.
    func listRecordings(_ request: RecordingListRequest) async throws -> RecordingListPage {
        let tagIDs = try await resolveTags(request.filter.tagNames)
        let title = request.titleText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = RecordingQuery(
            captureModes: request.captureModes,
            createdSince: request.filter.createdFrom,
            search: title.flatMap { $0.isEmpty ? nil : RecordingQuery.Search(text: $0) },
            sortOrder: request.sortOrder
        )
        // The repository filters by one tag and an open-ended date; the rest is applied here, which is cheap at the
        // size of a personal library.
        let matching = try await storage { try await dependencies.recordings.fetch(matching: query) }
            .filter { recording in
                request.filter.createdBefore.map { recording.recording.createdAt < $0 } ?? true
            }
            .filter { recording in
                tagIDs.map { !recording.tagIDs.isDisjoint(with: $0) } ?? true
            }
        let offset = max(request.offset, 0)
        let limit = min(max(request.limit, 1), Self.maximumListLimit)
        let page = matching.dropFirst(offset).prefix(limit)
        let tags = try await allTags()
        var overviews: [RecordingOverview] = []
        for recording in page {
            overviews.append(try await overview(of: recording, tags: tags))
        }
        let end = offset + page.count
        return RecordingListPage(
            recordings: overviews,
            totalCount: matching.count,
            nextOffset: end < matching.count ? end : nil
        )
    }

    /// Throws `RecordingKnowledgeError`.
    func details(of recordingID: UUID) async throws -> RecordingDetails {
        let recording = try await existingRecording(recordingID)
        let transcript = try await storage { try await dependencies.transcripts.transcript(for: recordingID) }
        let summary = try await storage { try await dependencies.summaries.summary(for: recordingID) }
        let overview = try await overview(of: recording, tags: allTags(), hasSummary: summary != nil)
        return RecordingDetails(
            overview: overview,
            transcript: transcript.map { transcript in
                RecordingDetails.TranscriptInfo(
                    language: transcript.language,
                    modelID: transcript.modelID,
                    createdAt: transcript.createdAt,
                    segmentCount: transcript.segments.count,
                    sources: TranscriptSource.allCases.filter { source in
                        transcript.segments.contains { $0.source == source }
                    }
                )
            },
            summary: summary.map { summary in
                RecordingDetails.SummaryInfo(
                    language: summary.language,
                    modelID: summary.modelID,
                    createdAt: summary.createdAt,
                    isCurrent: transcript.map(summary.isCurrent(for:)) ?? false,
                    partCount: summary.parts.count
                )
            }
        )
    }

    /// Throws `RecordingKnowledgeError.summaryUnavailable` with where the summary stands when there is none yet.
    func summary(of recordingID: UUID) async throws -> RecordingSummary {
        let recording = try await existingRecording(recordingID)
        guard let summary = try await storage({ try await dependencies.summaries.summary(for: recordingID) }) else {
            let status = try await overview(of: recording, tags: [], hasSummary: false).pipeline.summary
            throw RecordingKnowledgeError.summaryUnavailable(recordingID, status: status)
        }
        let transcript = try await storage { try await dependencies.transcripts.transcript(for: recordingID) }
        return RecordingSummary(
            recording: recording,
            summary: summary,
            isCurrent: transcript.map(summary.isCurrent(for:)) ?? false
        )
    }

    /// Reads segments in order until `maximumCharacters` of text, always returning at least one when the window has
    /// any. Throws `RecordingKnowledgeError`.
    func transcript(
        of recordingID: UUID,
        window: TranscriptWindow,
        maximumCharacters: Int
    ) async throws -> TranscriptExcerpt {
        let recording = try await existingRecording(recordingID)
        let span = try await timeSpan(of: window, in: recordingID)
        guard let transcript = try await storage({ try await dependencies.transcripts.transcript(for: recordingID) })
        else {
            let status = try await overview(of: recording, tags: []).pipeline.transcript
            throw RecordingKnowledgeError.transcriptUnavailable(recordingID, status: status)
        }
        let inWindow = transcript.segments.enumerated().filter { _, segment in
            span.contains(segment.startTime)
        }
        var lines: [TranscriptExcerpt.Line] = []
        var characters = 0
        var continuesFrom: TimeInterval?
        for (index, segment) in inWindow {
            if !lines.isEmpty, characters + segment.text.count > maximumCharacters {
                continuesFrom = segment.startTime
                break
            }
            lines.append(TranscriptExcerpt.Line(index: index, segment: segment))
            characters += segment.text.count
        }
        return TranscriptExcerpt(
            recording: recording,
            language: transcript.language,
            lines: lines,
            totalSegmentCount: transcript.segments.count,
            continuesFrom: continuesFrom
        )
    }

    /// Searches by meaning and words within the filter. Throws `RecordingKnowledgeError`.
    func search(
        _ text: String,
        filter: RecordingKnowledgeFilter,
        recordingIDs: Set<UUID>?,
        kinds: Set<SearchChunkKind>?,
        limit: Int
    ) async throws -> RecordingSearchResult {
        let tagIDs = try await resolveTags(filter.tagNames)
        let query = RecordingSearchQuery(
            text: text,
            filter: RecordingSearchFilter(
                recordingIDs: recordingIDs,
                createdFrom: filter.createdFrom,
                createdBefore: filter.createdBefore,
                tagIDs: tagIDs,
                kinds: kinds
            ),
            limit: min(max(limit, 1), Self.maximumSearchLimit)
        )
        return try await storage { try await dependencies.search.search(query) }
    }

    /// Every tag with the number of recordings carrying it, in the order the Library shows them.
    func tagUsage() async throws -> [TagUsage] {
        var usage: [TagUsage] = []
        for tag in try await allTags() {
            let count = try await storage {
                try await dependencies.recordings.count(matching: RecordingQuery(tagID: tag.id))
            }
            usage.append(TagUsage(tag: tag, recordingCount: count))
        }
        return usage
    }

    // MARK: - Helpers

    private func existingRecording(_ id: UUID) async throws -> LibraryRecording {
        guard let recording = try await storage({ try await dependencies.recordings.fetch(id: id) }) else {
            throw RecordingKnowledgeError.recordingNotFound(id)
        }
        return recording
    }

    private func allTags() async throws -> [RecordingTag] {
        try await storage { try await dependencies.recordings.fetchTags() }
    }

    /// `nil` for no names, which allows every recording. Throws `unknownTags` naming those that match no tag.
    private func resolveTags(_ names: [String]) async throws -> Set<UUID>? {
        guard !names.isEmpty else {
            return nil
        }
        let tags = try await allTags()
        var ids: Set<UUID> = []
        var unknown: [String] = []
        for name in names {
            if let tag = tags.first(where: { Self.sameName($0.name, name) }) {
                ids.insert(tag.id)
            } else {
                unknown.append(name)
            }
        }
        guard unknown.isEmpty else {
            throw RecordingKnowledgeError.unknownTags(unknown, available: tags.map(\.name))
        }
        return ids
    }

    private static func sameName(_ first: String, _ second: String) -> Bool {
        first.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare(
                second.trimmingCharacters(in: .whitespacesAndNewlines),
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
    }

    /// The time range a window covers on the recording's timeline.
    private func timeSpan(of window: TranscriptWindow, in recordingID: UUID) async throws -> Range<TimeInterval> {
        switch window {
        case let .range(start, end):
            let lower = start ?? 0
            let upper = end ?? .infinity
            guard lower.isFinite, lower >= 0, !upper.isNaN, upper > lower else {
                throw RecordingKnowledgeError.invalidTimeRange
            }
            return lower..<upper
        case let .aroundChunk(chunkID, contextSeconds):
            let records = try await storage { try await dependencies.index.records(for: [chunkID]) }
            guard let chunk = records[chunkID]?.chunk else {
                throw RecordingKnowledgeError.chunkNotFound(chunkID)
            }
            guard chunk.recordingID == recordingID else {
                throw RecordingKnowledgeError.chunkInOtherRecording(chunkID, recordingID: chunk.recordingID)
            }
            guard let span = chunk.timeSpan else {
                throw RecordingKnowledgeError.chunkWithoutTime(chunkID)
            }
            let context = contextSeconds.isFinite ? max(contextSeconds, 0) : 0
            // The chunk's own segments start within its span; the end is open by a hair so the last one is included.
            return max(span.lowerBound - context, 0)..<(span.upperBound + context + 0.001)
        }
    }

    private func overview(
        of recording: LibraryRecording,
        tags: [RecordingTag],
        hasSummary knownSummary: Bool? = nil
    ) async throws -> RecordingOverview {
        let id = recording.id
        let hasSummary: Bool
        if let knownSummary {
            hasSummary = knownSummary
        } else {
            hasSummary = try await storage { try await dependencies.summaries.summary(for: id) } != nil
        }
        let indexState = try await storage { try await dependencies.index.indexState(for: id) }
        return RecordingOverview(
            recording: recording,
            tags: tags.filter { recording.tagIDs.contains($0.id) },
            pipeline: RecordingPipeline.status(
                of: recording,
                activity: dependencies.activity(id),
                hasSummary: hasSummary,
                isIndexed: indexState.transcriptCreatedAt != nil
            )
        )
    }

    /// Runs a read, translating storage failures; cancellation and this service's own errors pass through.
    private func storage<Value>(_ read: () async throws -> Value) async throws -> Value {
        do {
            return try await read()
        } catch let error as RecordingKnowledgeError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RecordingKnowledgeError.storageFailed(detail: String(describing: error))
        }
    }
}

/// How the steps after a recording stand, from the jobs held now and what is stored.
enum RecordingPipeline {
    static func status(
        of recording: LibraryRecording,
        activity: RecordingActivity,
        hasSummary: Bool,
        isIndexed: Bool
    ) -> RecordingPipelineStatus {
        RecordingPipelineStatus(
            transcript: transcriptStatus(of: recording, job: activity.transcription),
            summary: summaryStatus(job: activity.summary, hasSummary: hasSummary),
            index: indexStatus(job: activity.indexing, isIndexed: isIndexed)
        )
    }

    private static func transcriptStatus(
        of recording: LibraryRecording,
        job: TranscriptionJob.State?
    ) -> PipelineStepStatus {
        switch job {
        case .pending: return .queued
        case .preparing, .transcribing, .saving: return .running
        case .completed, .failed, .cancelled, nil: break
        }
        // A failed re-transcription keeps the earlier transcript.
        if recording.hasTranscript {
            return .ready
        }
        switch recording.recording.processingStatus {
        case .recorded: return .none
        case .pending: return .queued
        case .transcribing, .indexing: return .running
        case .ready: return .ready
        case .failed: return .failed
        }
    }

    private static func summaryStatus(job: SummaryJob.State?, hasSummary: Bool) -> PipelineStepStatus {
        switch job {
        case .queued: .queued
        case .loadingModel, .summarizingParts, .combining, .saving: .running
        case .failed: hasSummary ? .ready : .failed
        case nil: hasSummary ? .ready : .none
        }
    }

    private static func indexStatus(job: IndexingJob.State?, isIndexed: Bool) -> PipelineStepStatus {
        switch job {
        case .queued: .queued
        case .chunking, .embedding: .running
        case .failed: isIndexed ? .ready : .failed
        case nil: isIndexed ? .ready : .none
        }
    }
}
