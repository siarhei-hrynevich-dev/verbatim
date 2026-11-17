import Foundation
import Testing

@testable import Verbatim

/// Against real temporary databases, with the full-text index of the system SQLite.
struct SQLiteSearchIndexRepositoryTests {
    let search: SearchTestEnvironment
    let space = FakeTextEmbedder.space

    init() throws {
        search = try SearchTestEnvironment()
    }

    private var index: SQLiteSearchIndexRepository {
        search.index
    }

    /// Chunks the transcript as indexing does, and gives every chunk its fake vector.
    private func indexed(_ transcript: Transcript, embedding: Bool = true) async throws {
        try await index.replaceChunks(
            SearchChunker.chunks(of: transcript),
            ofKinds: [.transcript],
            for: transcript.recordingID,
            state: SearchIndexState(transcriptCreatedAt: transcript.createdAt)
        )
        guard embedding else {
            return
        }
        let pending = try await index.pendingEmbeddings(for: transcript.recordingID, in: space)
        let vectors = pending.map { FakeTextEmbedder.vector(for: $0.text, dimensions: space.dimensions) }
        try await index.storeEmbeddings(
            Dictionary(uniqueKeysWithValues: zip(pending.map(\.chunkID), vectors)),
            in: space
        )
    }

    @Test func aNewTranscriptOrSummaryMakesTheRecordingOutdated() async throws {
        let transcript = try await search.addRecording(lines: SearchFixtures.planning)
        #expect(try await index.recordingsWithOutdatedChunks() == [transcript.recordingID])

        try await indexed(transcript, embedding: false)
        #expect(try await index.recordingsWithOutdatedChunks().isEmpty)

        try await search.summaries.replaceSummary(SearchFixtures.summary(of: transcript, text: "Итоги"))
        #expect(try await index.recordingsWithOutdatedChunks() == [transcript.recordingID])
    }

    @Test func wordsAreFoundByPrefixInAnyLanguage() async throws {
        let planning = try await search.addRecording(title: "Планёрка", lines: SearchFixtures.planning)
        let budget = try await search.addRecording(title: "Budget", lines: SearchFixtures.budget)
        try await indexed(planning, embedding: false)
        try await indexed(budget, embedding: false)

        let russian = try await index.chunksMatching("микрофон", filter: RecordingSearchFilter(), limit: 10)
        let english = try await index.chunksMatching("invoice", filter: RecordingSearchFilter(), limit: 10)
        let records = try await index.records(for: (russian + english).map(\.chunkID))

        #expect(russian.count == 1)
        #expect(english.count == 1)
        #expect(records[russian[0].chunkID]?.recordingTitle == "Планёрка")
        #expect(records[english[0].chunkID]?.chunk.recordingID == budget.recordingID)
    }

    @Test func nearestChunksRespectTheFilter() async throws {
        let planning = try await search.addRecording(
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            lines: SearchFixtures.planning
        )
        let budget = try await search.addRecording(
            createdAt: Date(timeIntervalSince1970: 1_900_000_000),
            lines: SearchFixtures.budget
        )
        try await indexed(planning)
        try await indexed(budget)
        let query = FakeTextEmbedder.vector(for: "marketing budget", dimensions: space.dimensions)

        let everywhere = try await index.nearestChunks(to: query, in: space, filter: RecordingSearchFilter(), limit: 5)
        let earlier = try await index.nearestChunks(
            to: query,
            in: space,
            filter: RecordingSearchFilter(createdBefore: Date(timeIntervalSince1970: 1_850_000_000)),
            limit: 5
        )
        let records = try await index.records(for: everywhere.map(\.chunkID) + earlier.map(\.chunkID))

        #expect(records[everywhere[0].chunkID]?.chunk.recordingID == budget.recordingID)
        #expect(earlier.allSatisfy { records[$0.chunkID]?.chunk.recordingID == planning.recordingID })
    }

    @Test func tagsNarrowTheSearch() async throws {
        let tagged = try await search.addRecording(lines: SearchFixtures.planning)
        let untagged = try await search.addRecording(lines: SearchFixtures.planning)
        try await search.recordings.updateTags(id: tagged.recordingID, tagIDs: [RecordingTag.defaults[0].id])
        try await indexed(tagged)
        try await indexed(untagged)
        let filter = RecordingSearchFilter(tagIDs: [RecordingTag.defaults[0].id])

        let lexical = try await index.chunksMatching("релиз", filter: filter, limit: 10)
        let records = try await index.records(for: lexical.map(\.chunkID))

        #expect(lexical.count == 1)
        #expect(records.values.map(\.chunk.recordingID) == [tagged.recordingID])
    }

    @Test func replacingChunksDropsTheirVectorsAndKeepsOtherKinds() async throws {
        let transcript = try await search.addRecording(lines: SearchFixtures.planning)
        try await indexed(transcript)
        let summary = SearchFixtures.summary(of: transcript, text: "Итоги планёрки", parts: ["- Сборка в среду"])
        try await index.replaceChunks(
            SearchChunker.chunks(of: summary),
            ofKinds: [.summary, .summaryPart],
            for: transcript.recordingID,
            state: SearchIndexState(transcriptCreatedAt: transcript.createdAt, summaryCreatedAt: summary.createdAt)
        )

        let pending = try await index.pendingEmbeddings(for: transcript.recordingID, in: space)

        #expect(pending.map(\.text) == ["Итоги планёрки", "- Сборка в среду"])
        #expect(try await index.recordingsWithPendingEmbeddings(in: space) == [transcript.recordingID])
        #expect(
            try await index.indexState(for: transcript.recordingID)
                == SearchIndexState(transcriptCreatedAt: transcript.createdAt, summaryCreatedAt: summary.createdAt)
        )
    }

    @Test func aVectorForAReplacedChunkIsNotStored() async throws {
        let transcript = try await search.addRecording(lines: SearchFixtures.planning)
        try await indexed(transcript, embedding: false)
        let stale = try await index.pendingEmbeddings(for: transcript.recordingID, in: space)
        try await indexed(transcript, embedding: false)

        try await index.storeEmbeddings([stale[0].chunkID: [Float](repeating: 0.1, count: 32)], in: space)

        #expect(try await index.pendingEmbeddings(for: transcript.recordingID, in: space).count == stale.count)
    }

    @Test func anotherModelsVectorsAreForgotten() async throws {
        let transcript = try await search.addRecording(lines: SearchFixtures.planning)
        try await indexed(transcript)
        let next = EmbeddingSpace(modelID: "next", revision: "1", dimensions: 32)

        try await index.removeEmbeddings(outside: next)

        #expect(try await index.recordingsWithPendingEmbeddings(in: space) == [transcript.recordingID])
        #expect(try await index.recordingsWithPendingEmbeddings(in: next) == [transcript.recordingID])
    }

    @Test func aRemovedRecordingIsNotFoundAndIsPurgedLater() async throws {
        let transcript = try await search.addRecording(lines: SearchFixtures.planning)
        try await indexed(transcript)
        try await search.recordings.delete(id: transcript.recordingID)

        let lexical = try await index.chunksMatching("релиз", filter: RecordingSearchFilter(), limit: 10)
        let query = FakeTextEmbedder.vector(for: "релиз", dimensions: space.dimensions)
        let semantic = try await index.nearestChunks(to: query, in: space, filter: RecordingSearchFilter(), limit: 5)
        try await index.purgeOrphans()

        #expect(lexical.isEmpty)
        #expect(semantic.isEmpty)
        #expect(try await index.indexState(for: transcript.recordingID) == .empty)
    }

    @Test func chunksOfARecordingNoLongerInTheLibraryAreNotStored() async throws {
        let transcript = SearchFixtures.transcript(of: UUID(), lines: SearchFixtures.planning)

        await #expect(throws: LibraryError.recordingNotFound) {
            try await index.replaceChunks(
                SearchChunker.chunks(of: transcript),
                ofKinds: [.transcript],
                for: transcript.recordingID,
                state: .empty
            )
        }
    }
}
