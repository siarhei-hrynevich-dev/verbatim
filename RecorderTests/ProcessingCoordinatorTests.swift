import Foundation
import Testing

@testable import Recorder

@MainActor
struct ProcessingCoordinatorTests {
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

    // MARK: - Lifecycle

    @Test func aJobGoesThroughToAStoredTranscriptAndFiles() async throws {
        let recording = try await environment.addRecording()

        coordinator.enqueue(recording.id)
        #expect(coordinator.job(for: recording.id)?.state.isActive == true)
        await coordinator.waitUntilSettled()

        let job = try #require(coordinator.job(for: recording.id))
        #expect(job.state == .completed)
        #expect(job.modelID == "openai_whisper-tiny")
        #expect(job.attempts == 1)
        let transcript = try #require(try await environment.store.transcript(for: recording.id))
        #expect(transcript.segments.map(\.text) == ["Hello there."])
        #expect(transcript.modelID == "openai_whisper-tiny")
        #expect(transcript.modelVersion == "test")
        #expect(transcript.language == "en")
        let folder = recording.media.url.deletingLastPathComponent()
        for name in RecordingFileLayout.transcriptFileNames {
            #expect(FileManager.default.fileExists(atPath: folder.appending(path: name).path(percentEncoded: false)))
        }
        let stored = try await environment.library.makeRepository().fetch(id: recording.id)
        #expect(stored?.recording.processingStatus == .ready)
        #expect(environment.models.leasesHeld == 0)
    }

    @Test func itReportsMeasuredProgressWhileRunning() async throws {
        let recording = try await environment.addRecording()
        fake.update { $0.holdsCalls = true }

        coordinator.enqueue(recording.id)
        try await environment.waitUntilHeld()
        try await environment.wait { coordinator.progress[recording.id] == 0.25 }

        #expect(coordinator.job(for: recording.id)?.state == .transcribing)
        fake.releaseCalls()
        await coordinator.waitUntilSettled()
        #expect(coordinator.progress[recording.id] == nil)
    }

    @Test func nothingIsReportedDoneUntilTheTranscriptIsStored() async throws {
        let recording = try await environment.addRecording()
        coordinator.enqueue(recording.id)
        await coordinator.waitUntilSettled()
        let completedStatus = try await environment.store.allJobs().first?.state

        #expect(completedStatus == .completed)
        #expect(try await environment.store.transcript(for: recording.id) != nil)
    }

    @Test func theSelectedLanguageReachesTheEngine() async throws {
        let german = try ProcessingTestEnvironment(language: .explicit(code: "de"))
        await german.coordinator.start()
        let recording = try await german.addRecording()

        german.coordinator.enqueue(recording.id)
        await german.coordinator.waitUntilSettled()

        #expect(german.transcription.read { $0.requests.first?.language } == .explicit(code: "de"))
    }

    // MARK: - Duplicates and order

    @Test func askingAgainWhileQueuedOrRunningDoesNothing() async throws {
        let recording = try await environment.addRecording()
        fake.update { $0.holdsCalls = true }

        coordinator.enqueue(recording.id)
        coordinator.enqueue(recording.id)
        try await environment.waitUntilHeld()
        coordinator.enqueue(recording.id)
        fake.releaseCalls()
        await coordinator.waitUntilSettled()

        #expect(fake.read(\.requests).count == 1)
    }

    @Test func oneJobRunsAtATimeInTheOrderAskedFor() async throws {
        let first = try await environment.addRecording(title: "First")
        let second = try await environment.addRecording(title: "Second")
        fake.update { $0.holdsCalls = true }

        coordinator.enqueue(first.id)
        try await environment.waitUntilHeld()
        coordinator.enqueue(second.id)
        #expect(coordinator.job(for: second.id)?.state == .pending)

        fake.releaseCalls()
        try await environment.wait { coordinator.job(for: second.id)?.state == .completed }
        await coordinator.waitUntilSettled()

        #expect(fake.read(\.peakRunningCount) == 1)
        #expect(fake.read { $0.requests.map(\.recordingID) } == [first.id, second.id])
        #expect(fake.read(\.releaseCount) == 1)
    }

    @Test func theModelIsReleasedWhenTheQueueRunsOut() async throws {
        let recording = try await environment.addRecording()

        coordinator.enqueue(recording.id)
        await coordinator.waitUntilSettled()

        #expect(fake.read(\.releaseCount) == 1)
    }

    // MARK: - Models

    @Test func noModelSelectedFailsWithoutRunningAndCanBeRetried() async throws {
        let recording = try await environment.addRecording()
        environment.models.failure = .noModelSelected

        coordinator.enqueue(recording.id)
        await coordinator.waitUntilSettled()

        #expect(coordinator.job(for: recording.id)?.state == .failed)
        #expect(coordinator.job(for: recording.id)?.failure == .noModelSelected)
        #expect(fake.read(\.requests).isEmpty)

        environment.models.failure = nil
        coordinator.enqueue(recording.id)
        await coordinator.waitUntilSettled()
        #expect(coordinator.job(for: recording.id)?.state == .completed)
        #expect(coordinator.job(for: recording.id)?.failure == nil)
    }

    @Test func anUnavailableModelIsReportedRatherThanReplaced() async throws {
        let recording = try await environment.addRecording()
        environment.models.failure = .selectedModelUnavailable("openai_whisper-small")

        coordinator.enqueue(recording.id)
        await coordinator.waitUntilSettled()

        #expect(coordinator.job(for: recording.id)?.failure == .modelUnavailable("openai_whisper-small"))
        #expect(fake.read(\.requests).isEmpty)
    }

    @Test func theRealModelManagerResolvesTheSelectedModelAndHoldsItWhileRunning() async throws {
        let harness = ModelManagerHarness()
        try await harness.install(ModelFixtures.tiny.id)
        let lease = try harness.manager.acquireSelectedModel()
        #expect(lease.model.id == ModelFixtures.tiny.id)

        await #expect(throws: ModelManagementError.modelInUse) {
            try await harness.manager.remove(ModelFixtures.tiny.id)
        }
        harness.manager.release(lease)
    }

    @Test func theRealModelManagerReportsNoSelectionAndMissingFiles() async throws {
        let harness = ModelManagerHarness()
        await harness.manager.prepareForUse()
        #expect(throws: ModelManagementError.noModelSelected) {
            try harness.manager.acquireSelectedModel()
        }

        try await harness.install(ModelFixtures.tiny.id)
        harness.provider.update {
            $0.verifyErrors[.quick] = .damagedInstallation
        }
        await harness.manager.prepareForUse()

        #expect(throws: ModelManagementError.selectedModelUnavailable(ModelFixtures.tiny.id)) {
            try harness.manager.acquireSelectedModel()
        }
        #expect(harness.provider.read(\.downloadCalls).count == 1)
    }
}
