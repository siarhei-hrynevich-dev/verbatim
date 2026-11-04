import Foundation
import Testing

@testable import Recorder

@MainActor
struct RecordingCoordinatorTests {
    func makeCoordinator(
        session: FakeCaptureSession = FakeCaptureSession(finalizeResult: .success(TestFixtures.media)),
        permissions: FakePermissions = FakePermissions()
    ) -> (RecordingCoordinator, FakeRecordingServices) {
        let services = FakeRecordingServices(session: session)
        let coordinator = RecordingCoordinator(
            engine: services,
            permissions: permissions,
            destinations: services,
            metadataStore: services,
            library: services
        )
        return (coordinator, services)
    }

    func startRecording(_ coordinator: RecordingCoordinator) async {
        coordinator.requestStart(TestFixtures.configuration())
        await coordinator.waitUntilSettled()
    }

    // MARK: - Transitions

    @Test func goesThroughTheFullLifecycle() async throws {
        let session = FakeCaptureSession(finalizeResult: .success(TestFixtures.media))
        let (coordinator, services) = makeCoordinator(session: session)
        #expect(coordinator.state == .idle)

        coordinator.requestStart(TestFixtures.configuration())
        #expect(coordinator.state == .preparing)

        await coordinator.waitUntilSettled()
        guard case .recording = coordinator.state else {
            Issue.record("Expected recording, got \(coordinator.state)")
            return
        }
        #expect(coordinator.activeRecording?.sourceName == "Studio Display")

        coordinator.requestStop()
        guard case .stopping = coordinator.state else {
            Issue.record("Expected stopping, got \(coordinator.state)")
            return
        }

        await coordinator.waitUntilSettled()
        #expect(coordinator.state == .idle)
        #expect(coordinator.activeRecording == nil)
        #expect(await session.stopCount == 1)
        #expect(await session.finalizeCount == 1)
        let saved = try #require(await services.savedMetadata.first)
        #expect(saved.completion == .complete)
        #expect(saved.recording.duration == 12)
        #expect(saved.audioSources == [.microphone, .systemAudio])
        #expect(coordinator.lastOutcome?.metadata == saved)
    }

    @Test func reportsNothingBeforeFinalizationCompletes() async throws {
        let session = FakeCaptureSession(finalizeResult: .success(TestFixtures.media), holdsFinalization: true)
        let (coordinator, services) = makeCoordinator(session: session)
        await startRecording(coordinator)

        coordinator.requestStop()
        while await session.finalizeCount == 0 {
            await Task.yield()
        }

        guard case .finalizing = coordinator.state else {
            Issue.record("Expected finalizing, got \(coordinator.state)")
            return
        }
        #expect(coordinator.lastOutcome == nil)
        #expect(await services.savedMetadata.isEmpty)

        await session.releaseFinalization()
        await coordinator.waitUntilSettled()
        #expect(coordinator.state == .idle)
        #expect(coordinator.lastOutcome != nil)
    }

    @Test(arguments: [
        (RecordingState.idle, RecordingState.preparing, true),
        (.failed(.noEnabledSource), .preparing, true),
        (.failed(.noEnabledSource), .idle, true),
        (.preparing, .failed(.noEnabledSource), true),
        (.finalizing(RecordingClock(startedAt: .distantPast)), .idle, true),
        (.idle, .recording(RecordingClock(startedAt: .distantPast)), false),
        (.idle, .stopping(RecordingClock(startedAt: .distantPast)), false),
        (.preparing, .idle, false),
        (.preparing, .preparing, false),
        (.recording(RecordingClock(startedAt: .distantPast)), .idle, false),
        (.stopping(RecordingClock(startedAt: .distantPast)), .idle, false)
    ])
    func allowsOnlyDefinedTransitions(from: RecordingState, to next: RecordingState, isAllowed: Bool) {
        #expect(from.allowsTransition(to: next) == isAllowed)
    }

    // MARK: - Invalid requests

    @Test func duplicateStartsCreateOneRecording() async {
        let (coordinator, services) = makeCoordinator()

        coordinator.requestStart(TestFixtures.configuration())
        coordinator.requestStart(TestFixtures.configuration())
        await coordinator.waitUntilSettled()
        coordinator.requestStart(TestFixtures.configuration())
        await coordinator.waitUntilSettled()

        #expect(await services.startCount == 1)
    }

    @Test func stopWithoutARecordingDoesNothing() async {
        let (coordinator, services) = makeCoordinator()

        coordinator.requestStop()
        await coordinator.waitUntilSettled()

        #expect(coordinator.state == .idle)
        #expect(await services.savedMetadata.isEmpty)
    }

    @Test func secondStopFinalizesOnce() async {
        let session = FakeCaptureSession(finalizeResult: .success(TestFixtures.media))
        let (coordinator, _) = makeCoordinator(session: session)
        await startRecording(coordinator)

        coordinator.requestStop()
        coordinator.requestStop()
        await coordinator.waitUntilSettled()

        #expect(await session.finalizeCount == 1)
    }

    @Test func pauseAndResumeReachTheSessionInOrderAndStopTheClock() async {
        let session = FakeCaptureSession(finalizeResult: .success(TestFixtures.media))
        let (coordinator, _) = makeCoordinator(session: session)
        await startRecording(coordinator)

        coordinator.togglePause()
        guard case .recording(let clock) = coordinator.state else {
            Issue.record("Expected recording")
            return
        }
        #expect(clock.isPaused)
        coordinator.togglePause()

        coordinator.requestStop()
        await coordinator.waitUntilSettled()

        #expect(await session.pauseCalls == [true, false])
    }

    // MARK: - Transcription preference

    @Test(arguments: [
        true, false
    ])
    func storesTheTranscriptionRequestWithANeutralStatus(isRequested: Bool) async throws {
        let (coordinator, services) = makeCoordinator()
        coordinator.requestStart(TestFixtures.configuration(transcribes: isRequested))
        await coordinator.waitUntilSettled()

        coordinator.requestStop()
        await coordinator.waitUntilSettled()

        let saved = try #require(await services.savedMetadata.first)
        #expect(saved.transcriptionRequested == isRequested)
        #expect(saved.recording.processingStatus == .recorded)
    }
}
