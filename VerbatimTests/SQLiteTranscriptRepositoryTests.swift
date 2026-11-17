import Foundation
import Testing

@testable import Verbatim

/// Against real temporary databases.
struct SQLiteTranscriptRepositoryTests {
    let environment: LibraryTestEnvironment
    let recordings: SQLiteRecordingRepository
    let store: SQLiteTranscriptRepository

    init() throws {
        environment = try LibraryTestEnvironment()
        recordings = environment.makeRepository()
        store = SQLiteTranscriptRepository(databaseURL: environment.databaseURL)
    }

    private func addedRecording() async throws -> LibraryRecording {
        let recording = try environment.makeRecording()
        try await recordings.insert(recording)
        return recording
    }

    private func transcript(of id: UUID, words: [String], model: String = "tiny") -> Transcript {
        Transcript.assembled(
            recordingID: id,
            provenance: .init(
                modelID: model,
                modelVersion: "1",
                language: "en",
                createdAt: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            speech: words.enumerated().map { index, word in
                RecognizedSpeech(
                    startTime: Double(index),
                    endTime: Double(index) + 0.5,
                    text: word,
                    source: index % 2 == 0 ? .microphone : .systemAudio
                )
            },
            mediaDuration: 100
        )
    }

    private func job(of id: UUID, _ state: TranscriptionJob.State) -> TranscriptionJob {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        return TranscriptionJob(recordingID: id, state: state, queuedAt: date, updatedAt: date)
    }

    // MARK: - Transcripts

    @Test func aTranscriptComesBackAsItWasStoredAndInOrder() async throws {
        let recording = try await addedRecording()
        let stored = transcript(of: recording.id, words: ["one", "two", "three", "four"])

        try await store.replaceTranscript(stored)

        #expect(try await store.transcript(for: recording.id) == stored)
        #expect(try await store.transcript(for: UUID()) == nil)
    }

    @Test func aTranscriptIsReadableByANewConnectionAfterARestart() async throws {
        let recording = try await addedRecording()
        let stored = transcript(of: recording.id, words: ["kept"])
        try await store.replaceTranscript(stored)

        let reopened = SQLiteTranscriptRepository(databaseURL: environment.databaseURL)

        #expect(try await reopened.transcript(for: recording.id) == stored)
    }

    @Test func replacingSwapsTheWholeTranscript() async throws {
        let recording = try await addedRecording()
        try await store.replaceTranscript(transcript(of: recording.id, words: ["old", "older", "oldest"]))
        let replacement = transcript(of: recording.id, words: ["new"], model: "base")

        try await store.replaceTranscript(replacement)

        #expect(try await store.transcript(for: recording.id) == replacement)
    }

    @Test func aFailedReplacementLeavesThePreviousTranscriptWhole() async throws {
        let recording = try await addedRecording()
        let original = transcript(of: recording.id, words: ["keep", "these", "words"])
        try await store.replaceTranscript(original)
        let duplicateID = UUID()
        let segments = [0.0, 1.0].compactMap {
            TranscriptSegment(
                id: duplicateID,
                recordingID: recording.id,
                startTime: $0,
                endTime: $0 + 1,
                text: "clash",
                source: .microphone
            )
        }
        let broken = Transcript(
            recordingID: recording.id,
            modelID: "base",
            modelVersion: nil,
            language: nil,
            createdAt: .now,
            segments: segments
        )

        await #expect(throws: LibraryError.self) {
            try await store.replaceTranscript(broken)
        }

        #expect(try await store.transcript(for: recording.id) == original)
    }

    @Test func aRecordingThatLeftTheLibraryGetsNoTranscript() async throws {
        let stray = transcript(of: UUID(), words: ["lost"])

        await #expect(throws: LibraryError.recordingNotFound) {
            try await store.replaceTranscript(stray)
        }
    }

    @Test func recordingsKnowWhetherTheyHaveATranscript() async throws {
        let recording = try await addedRecording()
        #expect(try await recordings.fetch(id: recording.id)?.hasTranscript == false)

        try await store.replaceTranscript(transcript(of: recording.id, words: ["a"]))

        #expect(try await recordings.fetch(id: recording.id)?.hasTranscript == true)
        #expect(try await recordings.fetch(matching: RecordingQuery()).first?.hasTranscript == true)
    }

    // MARK: - Jobs

    @Test func aJobSurvivesARestartWithItsDetails() async throws {
        let recording = try await addedRecording()
        var stored = job(of: recording.id, .failed)
        stored.attempts = 2
        stored.modelID = "tiny"
        stored.failure = .mediaUnavailable(.missing)
        stored.exportFailureDetail = "read-only"

        try await store.saveJob(stored)
        let reopened = SQLiteTranscriptRepository(databaseURL: environment.databaseURL)

        #expect(try await reopened.allJobs() == [stored])
    }

    @Test func thereIsOneJobPerRecording() async throws {
        let recording = try await addedRecording()

        try await store.saveJob(job(of: recording.id, .pending))
        try await store.saveJob(job(of: recording.id, .transcribing))

        #expect(try await store.allJobs().map(\.state) == [.transcribing])
    }

    @Test func savingAJobUpdatesTheStatusTheLibraryQueries() async throws {
        let recording = try await addedRecording()

        try await store.saveJob(job(of: recording.id, .pending))
        var query = RecordingQuery()
        query.statuses = [.pending]
        #expect(try await recordings.count(matching: query) == 1)

        try await store.saveJob(job(of: recording.id, .failed))
        #expect(try await recordings.fetch(id: recording.id)?.recording.processingStatus == .failed)
    }

    @Test func cancellingLeavesARecordingWithATranscriptReady() async throws {
        let recording = try await addedRecording()
        try await store.replaceTranscript(transcript(of: recording.id, words: ["a"]))

        try await store.saveJob(job(of: recording.id, .cancelled))

        #expect(try await recordings.fetch(id: recording.id)?.recording.processingStatus == .ready)
    }

    @Test func purgingForgetsOnlyWhatBelongsToRecordingsNoLongerThere() async throws {
        let kept = try await addedRecording()
        let removed = try await addedRecording()
        for recording in [kept, removed] {
            try await store.replaceTranscript(transcript(of: recording.id, words: ["a", "b"]))
            try await store.saveJob(job(of: recording.id, .completed))
        }
        try await recordings.delete(id: removed.id)
        #expect(try await store.transcript(for: removed.id) != nil)

        try await store.purgeOrphans()

        #expect(try await store.transcript(for: removed.id) == nil)
        #expect(try await store.transcript(for: kept.id) != nil)
        #expect(try await store.allJobs().map(\.recordingID) == [kept.id])
    }

    // MARK: - Migration

    @Test func anExistingLibraryIsUpgradedWithItsRecordings() async throws {
        try FileManager.default.createDirectory(
            at: environment.databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let firstVersion = Array(LibrarySchema.migrations.prefix(1))
        let older = SQLiteRecordingRepository(databaseURL: environment.databaseURL, migrations: firstVersion)
        _ = try? await older.count(matching: RecordingQuery())
        let recording = try environment.makeRecording()
        let database = try SQLiteDatabase(url: environment.databaseURL)
        try LibrarySchema.migrate(database, using: firstVersion)
        try database.execute(
            """
            INSERT INTO recordings (id, title, title_key, created_at, recording_type, media_path, processing_status,
                updated_at)
            VALUES (?, 'Old', 'old', 1000, 'screen', ?, 'recorded', 1000)
            """,
            bindings: [.text(recording.id.uuidString), .text(recording.media.url.path(percentEncoded: false))]
        )

        let upgraded = try await recordings.fetch(id: recording.id)

        #expect(upgraded?.recording.title == "Old")
        #expect(upgraded?.hasTranscript == false)
        #expect(try await store.allJobs().isEmpty)
    }

    @Test func twoConnectionsOpeningANewDatabaseTogetherBothSucceed() async throws {
        async let first = recordings.count(matching: RecordingQuery())
        async let second = store.allJobs()

        #expect(try await first == 0)
        #expect(try await second.isEmpty)
    }
}
