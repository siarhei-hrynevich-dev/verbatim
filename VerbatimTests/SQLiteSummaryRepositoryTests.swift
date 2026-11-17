import Foundation
import Testing

@testable import Verbatim

/// Against real temporary databases.
struct SQLiteSummaryRepositoryTests {
    let environment: LibraryTestEnvironment
    let recordings: SQLiteRecordingRepository
    let store: SQLiteSummaryRepository

    init() throws {
        environment = try LibraryTestEnvironment()
        recordings = environment.makeRepository()
        store = SQLiteSummaryRepository(databaseURL: environment.databaseURL)
    }

    private func addedRecording() async throws -> UUID {
        let recording = try environment.makeRecording()
        try await recordings.insert(recording)
        return recording.id
    }

    private func summary(of id: UUID, text: String = "Overview", parts: Int = 2) -> TranscriptSummary {
        TranscriptSummary(
            recordingID: id,
            modelID: "qwen3-4b-instruct-2507-4bit",
            language: "ru",
            transcriptCreatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            createdAt: Date(timeIntervalSince1970: 1_800_000_100),
            text: text,
            parts: (0..<parts).map { index in
                SummaryPart(
                    position: index,
                    startTime: Double(index) * 60,
                    endTime: Double(index) * 60 + 59.5,
                    firstSegment: index * 10,
                    lastSegment: index * 10 + 9,
                    text: "- point \(index)"
                )
            }
        )
    }

    @Test func aSummaryComesBackAsItWasStored() async throws {
        let id = try await addedRecording()
        let stored = summary(of: id)

        try await store.replaceSummary(stored)

        #expect(try await store.summary(for: id) == stored)
        #expect(try await store.summary(for: UUID()) == nil)
    }

    @Test func replacingASummaryReplacesItsPartsToo() async throws {
        let id = try await addedRecording()
        try await store.replaceSummary(summary(of: id, parts: 3))

        let replacement = summary(of: id, text: "Again", parts: 1)
        try await store.replaceSummary(replacement)

        #expect(try await store.summary(for: id) == replacement)
    }

    @Test func aSummaryNeedsItsRecording() async throws {
        await #expect(throws: LibraryError.recordingNotFound) {
            try await store.replaceSummary(summary(of: UUID()))
        }
    }

    @Test func deletingAndPurgingForgetSummaries() async throws {
        let kept = try await addedRecording()
        let removed = try await addedRecording()
        try await store.replaceSummary(summary(of: kept))
        try await store.replaceSummary(summary(of: removed))

        try await recordings.delete(id: removed)
        #expect(try await store.summary(for: removed) != nil)
        try await store.purgeOrphans()
        #expect(try await store.summary(for: removed) == nil)

        try await store.deleteSummary(for: kept)
        #expect(try await store.summary(for: kept) == nil)
    }
}
