import Foundation
import Testing

@testable import Recorder

/// Failing, cancelling, replacing a transcript, and recordings leaving the Library.
@MainActor
struct ProcessingFailureTests {
    let environment: ProcessingTestEnvironment

    init() async throws {
        environment = try ProcessingTestEnvironment()
        await environment.coordinator.start()
    }

    private var coordinator: ProcessingCoordinator {
        environment.coordinator
    }

    private var fake: FakeTranscriptionService {
        environment.transcription
    }

    // MARK: - Failures

    @Test func aFailedJobKeepsTheMediaAndCanBeRetried() async throws {
        let recording = try await environment.addRecording()
        let mediaBefore = try Data(contentsOf: recording.media.url)
        fake.update { $0.failures = [TranscriptionFailure.recognitionFailed(detail: "model error")] }

        coordinator.enqueue(recording.id)
        await coordinator.waitUntilSettled()

        #expect(coordinator.job(for: recording.id)?.failure == .recognitionFailed(detail: "model error"))
        #expect(try Data(contentsOf: recording.media.url) == mediaBefore)
        #expect(try await environment.store.transcript(for: recording.id) == nil)

        coordinator.enqueue(recording.id)
        await coordinator.waitUntilSettled()

        #expect(coordinator.job(for: recording.id)?.state == .completed)
        #expect(coordinator.job(for: recording.id)?.attempts == 2)
    }

    @Test func aMissingFileIsReported() async throws {
        let recording = try await environment.addRecording()
        try FileManager.default.removeItem(at: recording.media.url)

        coordinator.enqueue(recording.id)
        await coordinator.waitUntilSettled()

        #expect(coordinator.job(for: recording.id)?.failure == .mediaUnavailable(.missing))
    }

    @Test func aFullDiskIsReportedBeforeAnyWork() async throws {
        let full = try ProcessingTestEnvironment(files: ConfigurableFileStore(availableBytes: 10))
        await full.coordinator.start()
        let recording = try await full.addRecording()

        full.coordinator.enqueue(recording.id)
        await full.coordinator.waitUntilSettled()

        guard case .insufficientDiskSpace = full.coordinator.job(for: recording.id)?.failure else {
            Issue.record("Expected a disk space failure")
            return
        }
        #expect(full.transcription.read(\.requests).isEmpty)
    }

    @Test func filesThatCannotBeWrittenDoNotCostTheTranscript() async throws {
        let unwritable = try ProcessingTestEnvironment(files: ConfigurableFileStore(writeError: TestError.failed))
        await unwritable.coordinator.start()
        let recording = try await unwritable.addRecording()

        unwritable.coordinator.enqueue(recording.id)
        await unwritable.coordinator.waitUntilSettled()

        let job = try #require(unwritable.coordinator.job(for: recording.id))
        #expect(job.state == .completed)
        #expect(job.exportFailureDetail != nil)
        #expect(try await unwritable.store.transcript(for: recording.id) != nil)
    }

    @Test func aRecordingThatIsNotInTheLibraryLeavesNoJob() async throws {
        let id = UUID()

        coordinator.enqueue(id)
        await coordinator.waitUntilSettled()

        #expect(coordinator.job(for: id) == nil)
        #expect(try await environment.store.allJobs().isEmpty)
    }

    // MARK: - Cancelling

    @Test func cancellingARunningJobStoresNothing() async throws {
        let recording = try await environment.addRecording()
        fake.update { $0.holdsCalls = true }

        coordinator.enqueue(recording.id)
        try await environment.waitUntilHeld()
        coordinator.cancel(recording.id)
        await coordinator.waitUntilSettled()

        #expect(coordinator.job(for: recording.id)?.state == .cancelled)
        #expect(try await environment.store.transcript(for: recording.id) == nil)
        let stored = try await environment.library.makeRepository().fetch(id: recording.id)
        #expect(stored?.recording.processingStatus == .recorded)
        #expect(environment.models.leasesHeld == 0)
    }

    @Test func cancellingAQueuedJobTakesItOutOfTheQueue() async throws {
        let first = try await environment.addRecording()
        let second = try await environment.addRecording()
        fake.update { $0.holdsCalls = true }
        coordinator.enqueue(first.id)
        try await environment.waitUntilHeld()
        coordinator.enqueue(second.id)

        coordinator.cancel(second.id)
        fake.releaseCalls()
        await coordinator.waitUntilSettled()

        #expect(coordinator.job(for: second.id)?.state == .cancelled)
        #expect(fake.read(\.requests).count == 1)
    }

    @Test func anEngineThatFinishesAfterBeingCancelledStillStoresNothing() async throws {
        let recording = try await environment.addRecording()
        fake.update {
            $0.holdsCalls = true
            $0.ignoresCancellation = true
        }

        coordinator.enqueue(recording.id)
        try await environment.waitUntilHeld()
        coordinator.cancel(recording.id)
        #expect(coordinator.isStopping(recording.id))
        fake.releaseCalls()
        await coordinator.waitUntilSettled()

        #expect(coordinator.job(for: recording.id)?.state == .cancelled)
        #expect(try await environment.store.transcript(for: recording.id) == nil)
        #expect(!coordinator.isStopping(recording.id))
    }

    // MARK: - Re-transcribing

    @Test func reTranscribingKeepsTheOldTranscriptUntilTheNewOneIsComplete() async throws {
        let recording = try await environment.addRecording()
        coordinator.enqueue(recording.id)
        await coordinator.waitUntilSettled()
        let original = try await environment.store.transcript(for: recording.id)
        fake.update {
            $0.holdsCalls = true
            $0.output = TranscriptionOutput(
                speech: [RecognizedSpeech(startTime: 0, endTime: 1, text: "Better.", source: .microphone)],
                language: "en",
                modelVersion: "test",
                mediaDuration: 60
            )
        }

        coordinator.enqueue(recording.id)
        try await environment.waitUntilHeld()
        #expect(try await environment.store.transcript(for: recording.id) == original)
        fake.releaseCalls()
        await coordinator.waitUntilSettled()

        let replaced = try await environment.store.transcript(for: recording.id)
        #expect(replaced?.segments.map(\.text) == ["Better."])
    }

    @Test func aFailedReTranscriptionLeavesTheOldTranscript() async throws {
        let recording = try await environment.addRecording()
        coordinator.enqueue(recording.id)
        await coordinator.waitUntilSettled()
        let original = try await environment.store.transcript(for: recording.id)
        fake.update { $0.failures = [TranscriptionFailure.recognitionFailed(detail: "x")] }

        coordinator.enqueue(recording.id)
        await coordinator.waitUntilSettled()

        #expect(coordinator.job(for: recording.id)?.state == .failed)
        #expect(try await environment.store.transcript(for: recording.id) == original)
        let stored = try await environment.library.makeRepository().fetch(id: recording.id)
        #expect(stored?.hasTranscript == true)
    }

    // MARK: - Leaving the Library

    @Test func removingARecordingStopsItsJobAndUndoBringsTheTranscriptBack() async throws {
        let recording = try await environment.addRecording()
        coordinator.enqueue(recording.id)
        await coordinator.waitUntilSettled()
        let original = try await environment.store.transcript(for: recording.id)

        let removed = try await environment.service.removeFromLibrary(recording.id)
        #expect(coordinator.job(for: recording.id) == nil)
        await coordinator.waitUntilSettled()
        try await environment.service.restore(removed)

        #expect(try await environment.store.transcript(for: recording.id) == original)
    }

    @Test func removingWhileRunningStoresNothingAndRestoringDoesNotLookQueued() async throws {
        let recording = try await environment.addRecording()
        fake.update { $0.holdsCalls = true }
        coordinator.enqueue(recording.id)
        try await environment.waitUntilHeld()
        let repository = environment.library.makeRepository()
        for _ in 0..<2_000
        where try await repository.fetch(id: recording.id)?.recording.processingStatus != .transcribing {
            try await Task.sleep(for: .milliseconds(5))
        }

        let removed = try await environment.service.removeFromLibrary(recording.id)
        await coordinator.waitUntilSettled()
        #expect(try await environment.store.transcript(for: recording.id) == nil)

        try await environment.service.restore(removed)
        let stored = try await environment.library.makeRepository().fetch(id: recording.id)
        #expect(stored?.recording.processingStatus == .recorded)
    }

    @Test func deletingARecordingForgetsItsTranscript() async throws {
        let recording = try await environment.addRecording()
        coordinator.enqueue(recording.id)
        await coordinator.waitUntilSettled()

        _ = try await environment.service.delete(recording.id)
        await coordinator.waitUntilSettled()

        #expect(try await environment.store.transcript(for: recording.id) == nil)
    }
}
