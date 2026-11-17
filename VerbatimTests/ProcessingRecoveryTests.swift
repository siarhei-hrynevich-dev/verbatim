import Foundation
import Testing

@testable import Verbatim

/// Restarts, and recording taking priority.
@MainActor
struct ProcessingRecoveryTests {
    private func started() async throws -> ProcessingTestEnvironment {
        let environment = try ProcessingTestEnvironment()
        await environment.coordinator.start()
        return environment
    }

    // MARK: - Restarting

    @Test func aJobInterruptedByTheAppEndingRestartsFromTheBeginning() async throws {
        let first = try ProcessingTestEnvironment()
        let recording = try await first.addRecording()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        try await first.store.saveJob(
            TranscriptionJob(
                recordingID: recording.id,
                state: .transcribing,
                queuedAt: date,
                updatedAt: date,
                attempts: 1
            )
        )

        let next = try first.relaunched()
        await next.coordinator.start()
        await next.coordinator.waitUntilSettled()

        #expect(next.coordinator.job(for: recording.id)?.state == .completed)
        #expect(next.coordinator.job(for: recording.id)?.attempts == 2)
        #expect(next.transcription.read(\.requests).count == 1)
    }

    @Test func queuedJobsAndFailuresSurviveARestart() async throws {
        let first = try await started()
        let failed = try await first.addRecording()
        first.models.failure = .noModelSelected
        first.coordinator.enqueue(failed.id)
        await first.coordinator.waitUntilSettled()

        let next = try first.relaunched()
        await next.coordinator.start()

        #expect(next.coordinator.job(for: failed.id)?.state == .failed)
        #expect(next.coordinator.job(for: failed.id)?.failure == .noModelSelected)
        #expect(next.transcription.read(\.requests).isEmpty)
    }

    @Test func aTranscriptIsStillThereAfterARestart() async throws {
        let first = try await started()
        let recording = try await first.addRecording()
        first.coordinator.enqueue(recording.id)
        await first.coordinator.waitUntilSettled()

        let next = try first.relaunched()
        await next.coordinator.start()

        #expect(try await next.coordinator.transcript(for: recording.id)?.segments.map(\.text) == ["Hello there."])
        #expect(next.transcription.read(\.requests).isEmpty)
    }

    @Test func startingLoadsNoModelWhenThereIsNothingToDo() async throws {
        let environment = try await started()

        #expect(environment.transcription.read(\.requests).isEmpty)
        #expect(environment.models.prepareCount == 0)
    }

    // MARK: - Recording priority

    @Test func nothingStartsWhileRecording() async throws {
        let environment = try await started()
        let recording = try await environment.addRecording()

        environment.coordinator.setRecordingActive(true)
        environment.coordinator.enqueue(recording.id)
        await environment.coordinator.waitUntilSettled()

        #expect(environment.coordinator.job(for: recording.id)?.state == .pending)
        #expect(environment.transcription.read(\.requests).isEmpty)

        environment.coordinator.setRecordingActive(false)
        await environment.coordinator.waitUntilSettled()
        #expect(environment.coordinator.job(for: recording.id)?.state == .completed)
    }

    @Test func recordingStopsTheRunningJobAndFreesTheModelThenItStartsOver() async throws {
        let environment = try await started()
        let recording = try await environment.addRecording()
        environment.transcription.update { $0.holdsCalls = true }
        environment.coordinator.enqueue(recording.id)
        try await environment.waitUntilHeld()

        environment.coordinator.setRecordingActive(true)
        await environment.coordinator.waitUntilSettled()

        #expect(environment.coordinator.job(for: recording.id)?.state == .pending)
        #expect(environment.transcription.read(\.releaseCount) == 1)
        #expect(try await environment.store.transcript(for: recording.id) == nil)

        environment.coordinator.setRecordingActive(false)
        await environment.coordinator.waitUntilSettled()

        #expect(environment.coordinator.job(for: recording.id)?.state == .completed)
        #expect(environment.transcription.read(\.requests).count == 2)
    }

    @Test func startingARecordingNeverWaitsForInferenceThatWillNotStop() async throws {
        let environment = try await started()
        let recording = try await environment.addRecording()
        environment.transcription.update {
            $0.holdsCalls = true
            $0.ignoresCancellation = true
        }
        environment.coordinator.enqueue(recording.id)
        try await environment.waitUntilHeld()

        // Returns at once, with inference still running: this call is synchronous, so it cannot have waited for it.
        environment.coordinator.setRecordingActive(true)
        #expect(environment.transcription.read(\.runningCount) == 1)

        environment.transcription.releaseCalls()
        await environment.coordinator.waitUntilSettled()
        #expect(environment.coordinator.job(for: recording.id)?.state == .pending)
        #expect(try await environment.store.transcript(for: recording.id) == nil)
    }

    @Test func aRecordingEndingBeforeInferenceStopsDoesNotRunTwoJobsAtOnce() async throws {
        let environment = try await started()
        let recording = try await environment.addRecording()
        environment.transcription.update {
            $0.holdsCalls = true
            $0.ignoresCancellation = true
        }
        environment.coordinator.enqueue(recording.id)
        try await environment.waitUntilHeld()

        environment.coordinator.setRecordingActive(true)
        environment.coordinator.setRecordingActive(false)
        environment.transcription.releaseCalls()
        try await environment.wait { environment.coordinator.job(for: recording.id)?.state == .completed }
        await environment.coordinator.waitUntilSettled()

        #expect(environment.transcription.read(\.peakRunningCount) == 1)
    }

    @Test func aFinishedRecordingWithTheOptionOnIsQueuedOnlyAfterItsMediaIsSafe() async throws {
        let environment = try await started()
        let session = FakeCaptureSession(finalizeResult: .success(TestFixtures.media))
        let services = FakeRecordingServices(session: session)
        let coordinator = RecordingCoordinator(
            engine: services,
            permissions: FakePermissions(),
            destinations: services,
            metadataStore: services,
            library: services,
            transcriptionScheduler: environment.coordinator
        )
        environment.coordinator.setRecordingActive(true)

        coordinator.requestStart(TestFixtures.configuration(transcribes: true))
        await coordinator.waitUntilSettled()
        #expect(environment.coordinator.jobs.isEmpty)
        coordinator.requestStop()
        await coordinator.waitUntilSettled()

        let id = try #require(await services.libraryEntries.first?.recording.id)
        #expect(environment.coordinator.job(for: id)?.state == .pending)
    }

    @Test func aFinishedRecordingWithTheOptionOffIsNotQueued() async throws {
        let environment = try await started()
        let session = FakeCaptureSession(finalizeResult: .success(TestFixtures.media))
        let services = FakeRecordingServices(session: session)
        let coordinator = RecordingCoordinator(
            engine: services,
            permissions: FakePermissions(),
            destinations: services,
            metadataStore: services,
            library: services,
            transcriptionScheduler: environment.coordinator
        )

        coordinator.requestStart(TestFixtures.configuration(transcribes: false))
        await coordinator.waitUntilSettled()
        coordinator.requestStop()
        await coordinator.waitUntilSettled()

        #expect(environment.coordinator.jobs.isEmpty)
    }

    @Test func aFinishedVideoWithNoSoundIsNotQueued() async throws {
        let environment = try await started()
        let session = FakeCaptureSession(
            finalizeResult: .success(
                CapturedMedia(duration: 12, fileSizeBytes: 4_096, hasVideo: true, audioSources: [])
            )
        )
        let services = FakeRecordingServices(session: session)
        let coordinator = RecordingCoordinator(
            engine: services,
            permissions: FakePermissions(),
            destinations: services,
            metadataStore: services,
            library: services,
            transcriptionScheduler: environment.coordinator
        )

        coordinator.requestStart(TestFixtures.configuration(transcribes: true))
        await coordinator.waitUntilSettled()
        coordinator.requestStop()
        await coordinator.waitUntilSettled()

        #expect(environment.coordinator.jobs.isEmpty)
    }
}
