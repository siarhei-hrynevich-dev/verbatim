import Foundation
import Testing

@testable import Verbatim

/// The indexing queue on a real database, with a fake embedding model.
@MainActor
struct IndexingCoordinatorTests {
    let search: SearchTestEnvironment
    let embeddings = FakeEmbeddingProvider()
    let postProcessing = FakePostProcessingState()
    let coordinator: IndexingCoordinator

    init() throws {
        search = try SearchTestEnvironment()
        let postProcessing = postProcessing
        coordinator = IndexingCoordinator(
            dependencies: IndexingCoordinator.Dependencies(
                transcripts: search.transcripts,
                summaries: search.summaries,
                index: search.index,
                embeddings: embeddings,
                isPostProcessingBusy: { postProcessing.isBusy }
            )
        )
    }

    private func settle() async {
        await coordinator.waitUntilSettled()
    }

    private func pendingCount(of transcript: Transcript) async throws -> Int {
        try await search.index.pendingEmbeddings(for: transcript.recordingID, in: FakeTextEmbedder.space).count
    }

    @Test func aTranscriptIsChunkedAndEmbedded() async throws {
        let transcript = try await search.addRecording(lines: SearchFixtures.planning)

        coordinator.enqueue(transcript.recordingID)
        await settle()

        #expect(coordinator.job(for: transcript.recordingID) == nil)
        #expect(coordinator.revision == 1)
        #expect(try await pendingCount(of: transcript) == 0)
        #expect(embeddings.acquired == 1)
        #expect(embeddings.released == 1)
    }

    @Test func indexingWaitsForTranscriptionAndSummaries() async throws {
        let transcript = try await search.addRecording(lines: SearchFixtures.planning)
        postProcessing.isBusy = true

        coordinator.enqueue(transcript.recordingID)
        await settle()
        #expect(coordinator.job(for: transcript.recordingID)?.state == .queued)

        postProcessing.isBusy = false
        for _ in 0..<200 where coordinator.hasActiveJobs {
            try await Task.sleep(for: .milliseconds(5))
            await settle()
        }

        #expect(coordinator.job(for: transcript.recordingID) == nil)
        #expect(embeddings.embedder.embeddedTexts.count == 1)
    }

    @Test func withoutAModelWordsAreIndexedAndVectorsFollowOnceOneIsReady() async throws {
        embeddings.readySpace = nil
        let transcript = try await search.addRecording(lines: SearchFixtures.planning)
        await coordinator.start()
        await settle()

        let lexical = try await search.index.chunksMatching("релиз", filter: RecordingSearchFilter(), limit: 5)
        #expect(lexical.count == 1)
        #expect(embeddings.acquired == 0)

        embeddings.readySpace = FakeTextEmbedder.space
        for _ in 0..<200 where embeddings.acquired == 0 || coordinator.hasActiveJobs {
            try await Task.sleep(for: .milliseconds(10))
            await settle()
        }

        #expect(try await pendingCount(of: transcript) == 0)
    }

    @Test func aSummaryIsIndexedWithoutEmbeddingTheTranscriptAgain() async throws {
        let transcript = try await search.addRecording(lines: SearchFixtures.planning)
        coordinator.enqueue(transcript.recordingID)
        await settle()

        try await search.summaries.replaceSummary(
            SearchFixtures.summary(of: transcript, text: "Релиз переносится", parts: ["- Ошибка микрофона"])
        )
        coordinator.enqueue(transcript.recordingID)
        await settle()

        #expect(embeddings.embedder.embeddedTexts.suffix(2) == ["Релиз переносится", "- Ошибка микрофона"])
        #expect(embeddings.embedder.embeddedTexts.count == 3)
    }

    @Test func recordingStopsTheJobAndItContinuesAfterwards() async throws {
        embeddings.embedder = FakeTextEmbedder(delay: .milliseconds(50))
        let lines = (0..<40).map { "Фраза \($0) о работе над релизом и тестировании сборки." }
        let transcript = try await search.addRecording(lines: lines)
        coordinator.enqueue(transcript.recordingID)
        for _ in 0..<200 where embeddings.embedder.embeddedTexts.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }

        coordinator.setRecordingActive(true)
        await settle()
        #expect(coordinator.job(for: transcript.recordingID)?.state == .queued)
        #expect(embeddings.isRecordingActive)
        let embeddedBefore = embeddings.embedder.embeddedTexts.count

        coordinator.setRecordingActive(false)
        await settle()

        #expect(coordinator.job(for: transcript.recordingID) == nil)
        #expect(try await pendingCount(of: transcript) == 0)
        #expect(embeddedBefore < embeddings.embedder.embeddedTexts.count)
    }

    @Test func aFailedModelLeavesTheChunksAndReportsTheFailure() async throws {
        embeddings.embedder.failNext(with: IndexingFailure.modelLoadFailed(detail: "broken"))
        let transcript = try await search.addRecording(lines: SearchFixtures.planning)

        coordinator.enqueue(transcript.recordingID)
        await settle()

        #expect(coordinator.job(for: transcript.recordingID)?.state == .failed(.modelLoadFailed(detail: "broken")))
        #expect(try await search.index.chunksMatching("релиз", filter: RecordingSearchFilter(), limit: 5).count == 1)
    }

    @Test func aPermanentlyRemovedRecordingLosesItsIndex() async throws {
        let transcript = try await search.addRecording(lines: SearchFixtures.planning)
        coordinator.enqueue(transcript.recordingID)
        await settle()

        coordinator.recordingRemoved(transcript.recordingID, permanently: true)
        var attempts = 0
        while try await search.index.indexState(for: transcript.recordingID) != .empty, attempts < 200 {
            try await Task.sleep(for: .milliseconds(5))
            attempts += 1
        }

        #expect(try await search.index.indexState(for: transcript.recordingID) == .empty)
    }
}

/// Searching by meaning and by words together.
@MainActor
struct RecordingSearchServiceTests {
    let search: SearchTestEnvironment
    let embeddings = FakeEmbeddingProvider()
    let service: RecordingSearchService

    init() throws {
        search = try SearchTestEnvironment()
        service = RecordingSearchService(index: search.index, embeddings: embeddings)
    }

    private func indexAll(_ transcripts: [Transcript]) async throws {
        let coordinator = IndexingCoordinator(
            dependencies: IndexingCoordinator.Dependencies(
                transcripts: search.transcripts,
                summaries: search.summaries,
                index: search.index,
                embeddings: embeddings,
                isPostProcessingBusy: { false }
            )
        )
        for transcript in transcripts {
            coordinator.enqueue(transcript.recordingID)
        }
        await coordinator.waitUntilSettled()
    }

    @Test func resultsPointToTheRecordingAndTheMoment() async throws {
        let planning = try await search.addRecording(title: "Планёрка", lines: SearchFixtures.planning)
        let budget = try await search.addRecording(title: "Budget", lines: SearchFixtures.budget)
        try await indexAll([planning, budget])

        let result = try await service.search(RecordingSearchQuery(text: "marketing budget", limit: 3))

        let best = try #require(result.hits.first)
        #expect(result.semanticStatus == .used(FakeTextEmbedder.space))
        #expect(best.record.recordingTitle == "Budget")
        #expect(best.record.chunk.timeSpan?.lowerBound == 0)
        #expect(best.matches == [.semantic, .lexical])
        #expect(best.similarity != nil)
        #expect(embeddings.embedder.embeddedTexts.last == "marketing budget")
    }

    @Test func withoutAModelWordsAreStillFound() async throws {
        let planning = try await search.addRecording(lines: SearchFixtures.planning)
        try await indexAll([planning])
        embeddings.readySpace = nil

        let result = try await service.search(RecordingSearchQuery(text: "микрофона"))

        #expect(result.semanticStatus == .noModel)
        #expect(result.hits.map(\.matches) == [[.lexical]])
    }

    @Test func whileRecordingNoModelIsUsed() async throws {
        let planning = try await search.addRecording(lines: SearchFixtures.planning)
        try await indexAll([planning])
        embeddings.setRecordingActive(true)
        let acquired = embeddings.acquired

        let result = try await service.search(RecordingSearchQuery(text: "релиз"))

        #expect(result.semanticStatus == .pausedForRecording)
        #expect(embeddings.acquired == acquired)
        #expect(result.hits.count == 1)
    }

    @Test func theFilterLimitsResultsToTheRecordingsAskedFor() async throws {
        let planning = try await search.addRecording(lines: SearchFixtures.planning)
        let budget = try await search.addRecording(lines: SearchFixtures.budget)
        try await indexAll([planning, budget])

        let result = try await service.search(
            RecordingSearchQuery(
                text: "marketing budget",
                filter: RecordingSearchFilter(recordingIDs: [planning.recordingID])
            )
        )

        #expect(result.hits.allSatisfy { $0.record.chunk.recordingID == planning.recordingID })
    }
}
