import Foundation
import Testing

@testable import Recorder

/// What agents read about recordings, on a real database.
@MainActor
struct RecordingKnowledgeServiceTests {
    let environment: KnowledgeTestEnvironment

    init() throws {
        environment = try KnowledgeTestEnvironment()
    }

    private var knowledge: RecordingKnowledgeService {
        environment.knowledge
    }

    private static let november3 = Date(timeIntervalSince1970: 1_793_700_000)
    private static let november5 = Date(timeIntervalSince1970: 1_793_872_800)

    // MARK: - Listing

    @Test func listingFiltersByDateTagAndTypeAndPages() async throws {
        let team = try await environment.addTag("Team")
        let early = try await environment.addRecording(title: "Early", createdAt: Self.november3, lines: nil)
        let tagged = try await environment.addRecording(
            title: "Standup",
            createdAt: Self.november5,
            tags: [team.id],
            lines: SearchFixtures.planning
        )
        _ = try await environment.addRecording(
            title: "Voice memo",
            createdAt: Self.november5,
            mode: .audioOnly,
            lines: nil
        )

        let fromNov4 = try await knowledge.listRecordings(
            RecordingListRequest(
                filter: RecordingKnowledgeFilter(createdFrom: Self.november3.addingTimeInterval(3_600))
            )
        )
        let beforeNov4 = try await knowledge.listRecordings(
            RecordingListRequest(
                filter: RecordingKnowledgeFilter(createdBefore: Self.november3.addingTimeInterval(3_600))
            )
        )
        let byTag = try await knowledge.listRecordings(
            RecordingListRequest(filter: RecordingKnowledgeFilter(tagNames: ["team"]))
        )
        let audio = try await knowledge.listRecordings(RecordingListRequest(captureModes: [.audioOnly]))
        let firstPage = try await knowledge.listRecordings(RecordingListRequest(sortOrder: .oldestFirst, limit: 2))

        #expect(fromNov4.totalCount == 2)
        #expect(beforeNov4.recordings.map(\.recording.id) == [early.id])
        #expect(byTag.recordings.map(\.recording.id) == [tagged.id])
        #expect(byTag.recordings.first?.tags == [team])
        #expect(audio.recordings.map(\.recording.recording.title) == ["Voice memo"])
        #expect(firstPage.recordings.count == 2)
        #expect(firstPage.nextOffset == 2)
        #expect(firstPage.recordings.first?.recording.id == early.id)
    }

    @Test func unknownTagsAreNamedWithTheOnesThatExist() async throws {
        _ = try await environment.addTag("Clients")

        await #expect(
            throws: RecordingKnowledgeError.unknownTags(["Sales"], available: ["work", "personal", "Clients"])
        ) {
            try await knowledge.listRecordings(
                RecordingListRequest(filter: RecordingKnowledgeFilter(tagNames: ["clients", "Sales"]))
            )
        }
    }

    @Test func thePipelineShowsStoredResultsAndRunningJobs() async throws {
        let done = try await environment.addRecording(title: "Done", lines: SearchFixtures.budget)
        let fresh = try await environment.addRecording(title: "Fresh", lines: nil)
        await environment.index([done.id])
        environment.activity.jobs[fresh.id] = RecordingActivity(transcription: .transcribing)
        environment.activity.jobs[done.id] = RecordingActivity(summary: .queued)

        let doneDetails = try await knowledge.details(of: done.id)
        let freshDetails = try await knowledge.details(of: fresh.id)

        #expect(
            doneDetails.overview.pipeline
                == RecordingPipelineStatus(transcript: .ready, summary: .queued, index: .ready)
        )
        #expect(
            freshDetails.overview.pipeline
                == RecordingPipelineStatus(transcript: .running, summary: .none, index: .none)
        )
        #expect(doneDetails.transcript?.segmentCount == SearchFixtures.budget.count)
        #expect(doneDetails.transcript?.sources == [.microphone])
        #expect(freshDetails.transcript == nil)
    }

    // MARK: - Summaries

    @Test func aSummaryIsReturnedWithWhetherItIsCurrent() async throws {
        let recording = try await environment.addRecording(title: "Planning", lines: SearchFixtures.planning)
        let transcript = try #require(try await environment.search.transcripts.transcript(for: recording.id))
        try await environment.search.summaries.replaceSummary(
            SearchFixtures.summary(of: transcript, text: "Release planning", parts: ["Build on Wednesday"])
        )

        let found = try await knowledge.summary(of: recording.id)

        #expect(found.summary.text == "Release planning")
        #expect(found.isCurrent)
        #expect(found.summary.parts.count == 1)
    }

    @Test func aMissingSummarySaysWhereItStands() async throws {
        let recording = try await environment.addRecording(title: "Planning", lines: SearchFixtures.planning)
        environment.activity.jobs[recording.id] = RecordingActivity(summary: .combining)

        await #expect(throws: RecordingKnowledgeError.summaryUnavailable(recording.id, status: .running)) {
            try await knowledge.summary(of: recording.id)
        }
        await #expect(throws: RecordingKnowledgeError.recordingNotFound(Self.unknownID)) {
            try await knowledge.summary(of: Self.unknownID)
        }
    }

    private static let unknownID = UUID()

    // MARK: - Transcripts

    @Test func aRangeReturnsTheSegmentsStartingInIt() async throws {
        let recording = try await environment.addRecording(title: "Planning", lines: SearchFixtures.planning)

        let excerpt = try await knowledge.transcript(
            of: recording.id,
            window: .range(start: 20, end: 60),
            maximumCharacters: 10_000
        )

        #expect(excerpt.lines.map(\.index) == [1, 2])
        #expect(excerpt.lines.first?.segment.text == SearchFixtures.planning[1])
        #expect(excerpt.continuesFrom == nil)
        #expect(excerpt.totalSegmentCount == 4)
    }

    @Test func aLongRangeIsCutAndSaysWhereToContinue() async throws {
        let recording = try await environment.addRecording(title: "Planning", lines: SearchFixtures.planning)

        let excerpt = try await knowledge.transcript(
            of: recording.id,
            window: .range(start: nil, end: nil),
            maximumCharacters: 80
        )

        #expect(excerpt.lines.count == 1)
        #expect(excerpt.continuesFrom == 20)
    }

    @Test func aSearchResultIsReadWithItsContext() async throws {
        let recording = try await environment.addRecording(title: "Planning", lines: SearchFixtures.planning)
        await environment.index([recording.id])
        let hit = try #require(
            try await knowledge.search(
                "микрофона",
                filter: RecordingKnowledgeFilter(),
                recordingIDs: nil,
                kinds: [.transcript],
                limit: 1
            ).hits.first
        )

        let excerpt = try await knowledge.transcript(
            of: recording.id,
            window: .aroundChunk(hit.record.chunkID, contextSeconds: 0),
            maximumCharacters: 10_000
        )
        let other = try await environment.addRecording(title: "Other", lines: SearchFixtures.budget)

        #expect(excerpt.lines.map(\.segment.text).contains(SearchFixtures.planning[3]))
        await #expect(
            throws: RecordingKnowledgeError.chunkInOtherRecording(hit.record.chunkID, recordingID: recording.id)
        ) {
            try await knowledge.transcript(
                of: other.id,
                window: .aroundChunk(hit.record.chunkID, contextSeconds: 0),
                maximumCharacters: 100
            )
        }
    }

    @Test func aRecordingWithoutTranscriptOrAnInvalidRangeIsExplained() async throws {
        let recording = try await environment.addRecording(title: "Silent", lines: nil)

        await #expect(throws: RecordingKnowledgeError.transcriptUnavailable(recording.id, status: .none)) {
            try await knowledge.transcript(
                of: recording.id,
                window: .range(start: nil, end: nil),
                maximumCharacters: 100
            )
        }
        await #expect(throws: RecordingKnowledgeError.invalidTimeRange) {
            try await knowledge.transcript(of: recording.id, window: .range(start: 30, end: 10), maximumCharacters: 100)
        }
    }

    // MARK: - Search and tags

    @Test func searchFollowsTagFilters() async throws {
        let finance = try await environment.addTag("Finance")
        let budget = try await environment.addRecording(
            title: "Budget",
            tags: [finance.id],
            lines: SearchFixtures.budget
        )
        let planning = try await environment.addRecording(title: "Planning", lines: SearchFixtures.planning)
        await environment.index([budget.id, planning.id])

        let result = try await knowledge.search(
            "budget designers",
            filter: RecordingKnowledgeFilter(tagNames: ["finance"]),
            recordingIDs: nil,
            kinds: nil,
            limit: 5
        )

        #expect(!result.hits.isEmpty)
        #expect(result.hits.allSatisfy { $0.record.chunk.recordingID == budget.id })
    }

    @Test func tagsAreCountedByRecording() async throws {
        let finance = try await environment.addTag("Finance")
        _ = try await environment.addRecording(title: "A", tags: [finance.id], lines: nil)
        _ = try await environment.addRecording(title: "B", tags: [finance.id], lines: nil)

        let usage = try await knowledge.tagUsage()

        #expect(usage.map(\.tag.name) == ["work", "personal", "Finance"])
        #expect(usage.last?.recordingCount == 2)
    }
}
