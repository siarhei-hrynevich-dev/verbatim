import Foundation
import Testing

@testable import Verbatim

/// Requests and capture events that do not end in a clean recording.
@MainActor
struct RecordingCoordinatorFailureTests {
    private let fixtures = RecordingCoordinatorTests()

    private func makeCoordinator(
        session: FakeCaptureSession = FakeCaptureSession(finalizeResult: .success(TestFixtures.media)),
        permissions: FakePermissions = FakePermissions()
    ) -> (RecordingCoordinator, FakeRecordingServices) {
        fixtures.makeCoordinator(session: session, permissions: permissions)
    }

    private func startRecording(_ coordinator: RecordingCoordinator) async {
        await fixtures.startRecording(coordinator)
    }

    // MARK: - Start failures

    @Test func invalidConfigurationFailsWithoutStartingCapture() async {
        let (coordinator, services) = makeCoordinator()

        coordinator.requestStart(
            TestFixtures.configuration(target: .audioOnly, microphone: nil, capturesSystemAudio: false)
        )
        await coordinator.waitUntilSettled()

        #expect(coordinator.state == .failed(.noEnabledSource))
        #expect(await services.startCount == 0)
    }

    @Test func deniedScreenCaptureFailsWithAnActionableReason() async {
        let (coordinator, services) = makeCoordinator(permissions: FakePermissions(screenCaptureGranted: false))

        await startRecording(coordinator)

        #expect(coordinator.state == .failed(.screenCaptureDenied))
        #expect(await services.startCount == 0)
    }

    @Test func microphoneOnlyRecordingDoesNotNeedScreenCapture() async {
        let (coordinator, services) = makeCoordinator(permissions: FakePermissions(screenCaptureGranted: false))

        coordinator.requestStart(TestFixtures.configuration(target: .audioOnly, capturesSystemAudio: false))
        await coordinator.waitUntilSettled()

        #expect(await services.startCount == 1)
    }

    @Test func undeterminedMicrophoneAccessIsRequested() async {
        let denied = FakePermissions(microphone: .notDetermined, microphoneRequestResult: false)
        let (deniedCoordinator, _) = makeCoordinator(permissions: denied)
        await startRecording(deniedCoordinator)
        #expect(deniedCoordinator.state == .failed(.microphoneDenied))

        let (allowedCoordinator, services) = makeCoordinator(
            permissions: FakePermissions(microphone: .notDetermined, microphoneRequestResult: true)
        )
        await startRecording(allowedCoordinator)
        #expect(await services.startCount == 1)
    }

    @Test func insufficientDiskSpaceFailsBeforeCreatingAnything() async {
        let (coordinator, services) = makeCoordinator()
        await services.configure(availableBytes: 1_000)

        await startRecording(coordinator)

        #expect(coordinator.state == .failed(.insufficientDiskSpace(availableBytes: 1_000)))
        #expect(await services.startCount == 0)
    }

    @Test func unusableFolderIsReportedAsSuch() async {
        let failure = RecordingFailure.destinationUnavailable(path: "~/Movies/Verbatim", detail: "denied")
        let (coordinator, services) = makeCoordinator()
        await services.configure(prepareError: failure)

        await startRecording(coordinator)

        #expect(coordinator.state == .failed(failure))
    }

    @Test func captureInitializationFailureRemovesTheEmptyFolder() async {
        let (coordinator, services) = makeCoordinator()
        await services.configure(startResult: .failure(RecordingFailure.windowUnavailable(name: "Agenda")))

        await startRecording(coordinator)

        #expect(coordinator.state == .failed(.windowUnavailable(name: "Agenda")))
        #expect(await services.discardedDestinations.count == 1)
    }

    @Test func aFailedStartCanBeRetried() async {
        let (coordinator, services) = makeCoordinator()
        await services.configure(startResult: .failure(TestError.failed))
        await startRecording(coordinator)
        guard case .failed(.initializationFailed) = coordinator.state else {
            Issue.record("Expected an initialization failure, got \(coordinator.state)")
            return
        }

        await services.configure(
            startResult: .success(FakeCaptureSession(finalizeResult: .success(TestFixtures.media)))
        )
        await startRecording(coordinator)

        guard case .recording = coordinator.state else {
            Issue.record("Expected recording, got \(coordinator.state)")
            return
        }
    }

    // MARK: - Finalization failures

    @Test func finalizationFailureKeepsTheFilesAndMarksThemIncomplete() async throws {
        let session = FakeCaptureSession(finalizeResult: .failure(TestError.failed))
        let (coordinator, services) = makeCoordinator(session: session)
        await services.configure(isFolderEmpty: false)
        await startRecording(coordinator)

        coordinator.requestStop()
        await coordinator.waitUntilSettled()

        guard case .failed(.finalizationFailed(_, let directoryPath)) = coordinator.state else {
            Issue.record("Expected a finalization failure, got \(coordinator.state)")
            return
        }
        #expect(directoryPath.hasPrefix("/tmp/Verbatim/"))
        #expect(coordinator.lastOutcome == nil)
        #expect(coordinator.activeRecording == nil)
        let saved = try #require(await services.savedMetadata.first)
        #expect(saved.completion == .incomplete)
    }

    @Test func nothingCapturedRemovesTheFolderAndSavesNothing() async {
        let session = FakeCaptureSession(finalizeResult: .failure(RecordingFailure.noMediaCaptured))
        let (coordinator, services) = makeCoordinator(session: session)
        await startRecording(coordinator)

        coordinator.requestStop()
        await coordinator.waitUntilSettled()

        #expect(coordinator.state == .failed(.noMediaCaptured))
        #expect(await services.savedMetadata.isEmpty)
    }

    @Test func metadataFailureKeepsTheRecordingAndReportsIt() async {
        let session = FakeCaptureSession(finalizeResult: .success(TestFixtures.media))
        let (coordinator, services) = makeCoordinator(session: session)
        await services.configure(saveError: TestError.failed)
        await startRecording(coordinator)

        coordinator.requestStop()
        await coordinator.waitUntilSettled()

        #expect(coordinator.state == .idle)
        #expect(coordinator.lastOutcome?.metadataErrorDetail != nil)
        #expect(await services.discardedDestinations.isEmpty)
    }

    // MARK: - Interruptions

    private func waitForRecordingToEnd(_ coordinator: RecordingCoordinator) async {
        while case .recording = coordinator.state {
            await Task.yield()
        }
        await coordinator.waitUntilSettled()
    }

    @Test func losingTheVideoSourceSavesWhatWasCaptured() async {
        let session = FakeCaptureSession(finalizeResult: .success(TestFixtures.media))
        let (coordinator, _) = makeCoordinator(session: session)
        await startRecording(coordinator)

        session.eventsContinuation.yield(.videoSourceLost)
        await waitForRecordingToEnd(coordinator)

        #expect(coordinator.state == .idle)
        #expect(coordinator.lastOutcome?.interruptions == [.sourceLost(name: "Studio Display")])
    }

    @Test func losingTheMicrophoneKeepsVideoRecording() async {
        let session = FakeCaptureSession(finalizeResult: .success(TestFixtures.media))
        let (coordinator, _) = makeCoordinator(session: session)
        await startRecording(coordinator)

        session.eventsContinuation.yield(.microphoneLost)
        while coordinator.activeRecording?.isMicrophoneActive == true {
            await Task.yield()
        }

        guard case .recording = coordinator.state else {
            Issue.record("Expected recording to continue, got \(coordinator.state)")
            return
        }

        coordinator.requestStop()
        await coordinator.waitUntilSettled()
        #expect(coordinator.lastOutcome?.interruptions == [.microphoneLost(name: "USB Microphone")])
    }

    @Test func losingTheOnlySourceEndsTheRecording() async {
        let session = FakeCaptureSession(finalizeResult: .success(TestFixtures.media))
        let (coordinator, _) = makeCoordinator(session: session)
        coordinator.requestStart(TestFixtures.configuration(target: .audioOnly, capturesSystemAudio: false))
        await coordinator.waitUntilSettled()

        session.eventsContinuation.yield(.microphoneLost)
        await waitForRecordingToEnd(coordinator)

        #expect(coordinator.state == .idle)
        #expect(coordinator.lastOutcome?.interruptions == [.microphoneLost(name: "USB Microphone")])
    }

    @Test func levelsUpdateWhileRecordingAndResetAfterwards() async {
        let session = FakeCaptureSession(finalizeResult: .success(TestFixtures.media))
        let (coordinator, _) = makeCoordinator(session: session)
        await startRecording(coordinator)

        session.eventsContinuation.yield(.levels(AudioLevels(microphone: 0.5, systemAudio: 0.25)))
        while coordinator.levels == .silent {
            await Task.yield()
        }
        #expect(coordinator.levels.microphone == 0.5)

        coordinator.requestStop()
        await coordinator.waitUntilSettled()
        #expect(coordinator.levels == .silent)
    }
}
