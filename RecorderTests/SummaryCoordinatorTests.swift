import Foundation
import Observation
import Testing

@testable import Recorder

/// The summary queue on real temporary databases, with generation replaced.
@MainActor
struct SummaryCoordinatorTests {
    let environment: LibraryTestEnvironment
    let transcripts: SQLiteTranscriptRepository
    let summaries: SQLiteSummaryRepository
    let provider = FakeTextGenerationProvider()
    let transcription = TranscriptionActivity()
    let coordinator: SummaryCoordinator

    init() throws {
        environment = try LibraryTestEnvironment()
        transcripts = SQLiteTranscriptRepository(databaseURL: environment.databaseURL)
        summaries = SQLiteSummaryRepository(databaseURL: environment.databaseURL)
        let activity = transcription
        coordinator = SummaryCoordinator(
            dependencies: SummaryCoordinator.Dependencies(
                transcripts: transcripts,
                summaries: summaries,
                generation: provider,
                isTranscriptionBusy: { activity.isBusy },
                language: { SummaryLanguage.english },
                now: { Date(timeIntervalSince1970: 1_900_000_000) }
            )
        )
    }

    private func transcribedRecording(lines: Int = 3) async throws -> UUID {
        let recording = try environment.makeRecording()
        try await environment.makeRepository().insert(recording)
        try await transcripts.replaceTranscript(SummaryFixtures.transcript(of: recording.id, lines: lines))
        return recording.id
    }

    private func wait(until condition: () -> Bool) async throws {
        for _ in 0..<2_000 where !condition() {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }

    @Test func theModelsTitleIsOfferedOnceTheSummaryIsStored() async throws {
        let id = try await transcribedRecording()
        var offered: [(UUID, String)] = []
        let coordinator = SummaryCoordinator(
            dependencies: SummaryCoordinator.Dependencies(
                transcripts: transcripts,
                summaries: summaries,
                generation: provider,
                isTranscriptionBusy: { false },
                language: { SummaryLanguage.english },
                applyGeneratedTitle: { offered.append(($0, $1)) }
            )
        )

        coordinator.enqueue(id)
        await coordinator.waitUntilSettled()

        #expect(offered.map(\.0) == [id])
        #expect(offered.first?.1.hasPrefix("summary") == true)
        #expect(try await coordinator.summary(for: id) != nil)
    }

    @Test func aSummaryIsStoredWithItsPartsAndTheJobGoes() async throws {
        let id = try await transcribedRecording()

        coordinator.enqueue(id)
        await coordinator.waitUntilSettled()

        let stored = try #require(try await coordinator.summary(for: id))
        #expect(stored.text.hasPrefix("summary"))
        #expect(stored.modelID == "fake-model")
        // The transcript is in Russian; the summary follows Settings.
        #expect(stored.language == "en")
        #expect(stored.transcriptCreatedAt == SummaryFixtures.createdAt)
        #expect(!stored.parts.isEmpty)
        #expect(coordinator.job(for: id) == nil)
        #expect(coordinator.revision == 1)
        #expect(provider.acquired == 1 && provider.released == 1)
    }

    @Test func noTranscriptFailsWithoutLoadingAModel() async throws {
        let recording = try environment.makeRecording()
        try await environment.makeRepository().insert(recording)

        coordinator.enqueue(recording.id)
        await coordinator.waitUntilSettled()

        #expect(coordinator.job(for: recording.id)?.state == .failed(.noTranscript))
        #expect(provider.acquired == 0)
        coordinator.dismissFailure(of: recording.id)
        #expect(coordinator.job(for: recording.id) == nil)
    }

    @Test func aMissingModelIsReportedAsSuch() async throws {
        let id = try await transcribedRecording()
        provider.acquireFailure = SummaryFailure.noModelSelected

        coordinator.enqueue(id)
        await coordinator.waitUntilSettled()

        #expect(coordinator.job(for: id)?.state == .failed(.noModelSelected))
        #expect(provider.released == 0)
    }

    @Test func aRecordingStopsTheSummaryWhichStartsOverAfterwards() async throws {
        let id = try await transcribedRecording()
        provider.generator.update { $0.holds = true }

        coordinator.enqueue(id)
        try await wait { provider.generator.isHeld }
        coordinator.setRecordingActive(true)
        provider.generator.releaseHold()
        await coordinator.waitUntilSettled()

        #expect(coordinator.job(for: id)?.state == .queued)
        #expect(provider.released == 1)
        #expect(try await coordinator.summary(for: id) == nil)

        coordinator.setRecordingActive(false)
        await coordinator.waitUntilSettled()
        #expect(try await coordinator.summary(for: id) != nil)
    }

    @Test func summariesWaitForTranscriptionToFinish() async throws {
        let id = try await transcribedRecording()
        transcription.isBusy = true

        coordinator.enqueue(id)
        #expect(coordinator.job(for: id)?.state == .queued)
        #expect(coordinator.active == nil)

        transcription.isBusy = false
        try await wait { coordinator.job(for: id) == nil }
        await coordinator.waitUntilSettled()
        #expect(try await coordinator.summary(for: id) != nil)
    }

    @Test func cancellingLeavesTheEarlierSummaryAlone() async throws {
        let id = try await transcribedRecording()
        coordinator.enqueue(id)
        await coordinator.waitUntilSettled()
        let first = try await coordinator.summary(for: id)
        provider.generator.update { $0.holds = true }

        coordinator.enqueue(id)
        try await wait { provider.generator.isHeld }
        coordinator.cancel(id)
        provider.generator.releaseHold()
        await coordinator.waitUntilSettled()

        #expect(coordinator.job(for: id) == nil)
        #expect(try await coordinator.summary(for: id) == first)
    }

    @Test func aRequestForARunningSummaryIsIgnored() async throws {
        let id = try await transcribedRecording()
        provider.generator.update { $0.holds = true }

        coordinator.enqueue(id)
        try await wait { provider.generator.isHeld }
        coordinator.enqueue(id)
        provider.generator.releaseHold()
        await coordinator.waitUntilSettled()

        #expect(provider.acquired == 1)
    }

    @Test func deletingARecordingDeletesItsSummary() async throws {
        let id = try await transcribedRecording()
        coordinator.enqueue(id)
        await coordinator.waitUntilSettled()

        coordinator.recordingRemoved(id, permanently: true)

        var attempts = 0
        while try await coordinator.summary(for: id) != nil, attempts < 2_000 {
            attempts += 1
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(try await coordinator.summary(for: id) == nil)
    }

    @Test func aNewTranscriptIsSummarizedOnlyWithAModelReady() async throws {
        let id = try await transcribedRecording()
        provider.hasUsableModel = false

        coordinator.enqueueIfModelReady(id)
        #expect(coordinator.job(for: id) == nil)

        provider.hasUsableModel = true
        coordinator.enqueueIfModelReady(id)
        #expect(coordinator.hasActiveJobs)
        await coordinator.waitUntilSettled()
        #expect(try await coordinator.summary(for: id) != nil)
    }

    @Test func storingASummaryTellsWhatFollows() async throws {
        let id = try await transcribedRecording()
        var stored: [UUID] = []
        coordinator.onSummaryStored = { stored.append($0) }

        coordinator.enqueue(id)
        await coordinator.waitUntilSettled()

        #expect(stored == [id])
    }
}

/// Stands in for transcription's observable busy state.
@MainActor
@Observable
final class TranscriptionActivity {
    var isBusy = false
}
