import Foundation
import Testing

@testable import Recorder

/// The live view model, on top of a real coordinator and controllable services.
@MainActor
struct RecorderViewModelLiveTests {
    private struct Environment {
        let viewModel: RecorderViewModel
        let coordinator: RecordingCoordinator
        let services: FakeRecordingServices
        let preferences: InMemoryPreferencesStore
    }

    private static let otherDisplay = CaptureDisplay(
        id: "display-2",
        name: "Built-in",
        pixelWidth: 3024,
        pixelHeight: 1964
    )

    private func makeEnvironment(
        preferences: RecordingPreferences = RecordingPreferences(),
        permissions: FakePermissions = FakePermissions(),
        displays: [CaptureDisplay] = [TestFixtures.display, otherDisplay],
        windows: [CaptureWindow] = [TestFixtures.window],
        microphones: [Microphone] = [TestFixtures.microphone]
    ) -> Environment {
        let services = FakeRecordingServices(session: FakeCaptureSession(finalizeResult: .success(TestFixtures.media)))
        let coordinator = RecordingCoordinator(
            engine: services,
            permissions: permissions,
            destinations: services,
            metadataStore: services,
            library: services
        )
        let store = InMemoryPreferencesStore(preferences)
        let viewModel = RecorderViewModel(
            dependencies: RecorderViewModel.Dependencies(
                coordinator: coordinator,
                sourceProvider: FakeSourceProvider(
                    sources: CaptureSources(displays: displays, windows: windows),
                    microphones: microphones
                ),
                levelPreviewEngine: services,
                permissions: permissions,
                storage: services,
                preferencesStore: store,
                systemActions: NoSystemActions()
            )
        )
        return Environment(viewModel: viewModel, coordinator: coordinator, services: services, preferences: store)
    }

    @Test func restoresSavedPreferences() async {
        let saved = RecordingPreferences(
            captureMode: .audioOnly,
            displayID: Self.otherDisplay.id,
            microphoneID: TestFixtures.microphone.id,
            isMicrophoneEnabled: false,
            isSystemAudioEnabled: true,
            quality: .native,
            frameRate: .fps30,
            transcribesWhenFinished: false
        )
        let viewModel = makeEnvironment(preferences: saved).viewModel

        await viewModel.refresh()

        #expect(viewModel.captureMode == .audioOnly)
        #expect(viewModel.selectedDisplay == Self.otherDisplay)
        #expect(!viewModel.isMicrophoneEnabled)
        #expect(viewModel.quality == .native)
        #expect(viewModel.frameRate == .fps30)
        #expect(!viewModel.transcribesWhenFinished)
    }

    @Test func savesEveryChange() {
        let environment = makeEnvironment()

        environment.viewModel.quality = .hd720
        environment.viewModel.frameRate = .fps30
        environment.viewModel.isSystemAudioEnabled = false
        environment.viewModel.transcribesWhenFinished = false
        environment.viewModel.selection.selectedDisplayID = Self.otherDisplay.id

        #expect(environment.preferences.preferences.quality == .hd720)
        #expect(environment.preferences.preferences.frameRate == .fps30)
        #expect(!environment.preferences.preferences.isSystemAudioEnabled)
        #expect(!environment.preferences.preferences.transcribesWhenFinished)
        #expect(environment.preferences.preferences.displayID == Self.otherDisplay.id)
    }

    @Test func scenariosDoNotOverwriteSavedPreferences() {
        let environment = makeEnvironment(preferences: RecordingPreferences(quality: .native))

        environment.viewModel.apply(.picker)

        #expect(environment.preferences.preferences.quality == .native)
        #expect(environment.preferences.preferences.captureMode == .screen)
    }

    @Test func startsCaptureWithTheChosenSettings() async throws {
        let environment = makeEnvironment(preferences: RecordingPreferences(displayID: Self.otherDisplay.id))
        await environment.viewModel.refresh()
        environment.viewModel.quality = .hd720
        environment.viewModel.frameRate = .fps30

        environment.viewModel.startRecording()
        #expect(environment.viewModel.phase == .preparing)
        #expect(environment.viewModel.status == .preparing)
        #expect(!environment.viewModel.canStartRecording)
        await environment.coordinator.waitUntilSettled()

        guard case .recording = environment.viewModel.phase else {
            Issue.record("Expected recording, got \(environment.viewModel.phase)")
            return
        }
        let configuration = try #require(await environment.services.startedConfigurations.first)
        #expect(configuration.target == .display(Self.otherDisplay))
        #expect(configuration.microphone == TestFixtures.microphone)
        #expect(configuration.quality == .hd720)
        #expect(configuration.frameRate == .fps30)
    }

    @Test func recordingOutlivesTheSetupScreen() async {
        let environment = makeEnvironment()
        await environment.viewModel.refresh()
        environment.viewModel.startRecording()
        await environment.coordinator.waitUntilSettled()

        environment.viewModel.setSetupVisible(false)

        guard case .recording = environment.viewModel.phase else {
            Issue.record("Expected recording to continue, got \(environment.viewModel.phase)")
            return
        }
    }

    @Test func savedNoticeAppearsOnlyAfterFinalization() async {
        let environment = makeEnvironment()
        await environment.viewModel.refresh()
        environment.viewModel.startRecording()
        await environment.coordinator.waitUntilSettled()

        environment.viewModel.stopRecording()
        guard case .finishing = environment.viewModel.phase else {
            Issue.record("Expected finishing, got \(environment.viewModel.phase)")
            return
        }
        #expect(environment.viewModel.status == .finishing)
        #expect(environment.viewModel.savedRecordingTitle == nil)

        await environment.coordinator.waitUntilSettled()
        #expect(environment.viewModel.phase == .ready)
        #expect(environment.viewModel.savedRecordingTitle != nil)
    }

    @Test func deniedPermissionShowsTheIssueAndOffersMicrophoneOnlyRecording() async {
        let environment = makeEnvironment(permissions: FakePermissions(screenCaptureGranted: false))
        await environment.viewModel.refresh()

        environment.viewModel.startRecording()
        await environment.coordinator.waitUntilSettled()
        #expect(environment.viewModel.issue == .screenRecordingPermission)
        #expect(!environment.viewModel.canStartRecording)

        environment.viewModel.performIssueSecondaryAction()

        #expect(environment.viewModel.captureMode == .audioOnly)
        #expect(!environment.viewModel.isSystemAudioEnabled)
        #expect(environment.viewModel.isMicrophoneEnabled)
        #expect(environment.viewModel.canStartRecording)

        environment.viewModel.startRecording()
        await environment.coordinator.waitUntilSettled()
        #expect(await environment.services.startCount == 1)
    }

    @Test func deniedMicrophoneIsShownBeforeStartingAndCanBeTurnedOff() async {
        let environment = makeEnvironment(permissions: FakePermissions(microphone: .denied))
        await environment.viewModel.refresh()

        #expect(environment.viewModel.issue == .microphonePermission)
        #expect(!environment.viewModel.canStartRecording)

        environment.viewModel.performIssueSecondaryAction()

        #expect(!environment.viewModel.isMicrophoneEnabled)
        #expect(environment.viewModel.issue == nil)
        #expect(environment.viewModel.canStartRecording)
    }

    @Test func audioOnlyWithoutSourcesCannotStart() async {
        let environment = makeEnvironment(
            preferences: RecordingPreferences(
                captureMode: .audioOnly,
                isMicrophoneEnabled: false,
                isSystemAudioEnabled: false
            )
        )
        await environment.viewModel.refresh()

        #expect(environment.viewModel.issue == .noAudioSource)
        #expect(!environment.viewModel.canStartRecording)

        environment.viewModel.performIssuePrimaryAction()

        #expect(environment.viewModel.isMicrophoneEnabled)
        #expect(environment.viewModel.issue == nil)
    }

    @Test func lowDiskWarnsAndSwitchesQuality() async {
        let environment = makeEnvironment()
        await environment.services.configure(availableBytes: 600_000_000)
        await environment.viewModel.refresh()

        guard case .lowDiskSpace = environment.viewModel.issue else {
            Issue.record("Expected a low disk warning, got \(String(describing: environment.viewModel.issue))")
            return
        }
        #expect(environment.viewModel.canStartRecording)

        environment.viewModel.performIssueSecondaryAction()

        #expect(environment.viewModel.quality == .hd720)
    }

    @Test func storageSummaryShowsTheLocationAndFreeSpace() async {
        let viewModel = makeEnvironment().viewModel

        await viewModel.refresh()

        #expect(viewModel.storageSummary.hasPrefix("~/Movies/Verbatim · "))
        #expect(viewModel.storageSummary.hasSuffix(" free"))
    }

    @Test func aSavedWindowIsFoundAgainByAppAndTitle() async {
        let saved = RecordingPreferences(
            captureMode: .window,
            windowID: "old-id",
            windowBundleIdentifier: TestFixtures.window.bundleIdentifier,
            windowTitle: TestFixtures.window.title
        )
        let viewModel = makeEnvironment(preferences: saved).viewModel

        await viewModel.refresh()

        #expect(viewModel.selectedWindow == TestFixtures.window)
        #expect(viewModel.issue == nil)
    }
}

/// How sources going away reads in the Recorder, with provider contents changing between refreshes.
@MainActor
struct RecorderSourceLossTests {
    private actor ChangingSourceProvider: CaptureSourceProviding {
        var sources: CaptureSources
        var microphones: [Microphone]

        init(sources: CaptureSources, microphones: [Microphone]) {
            self.sources = sources
            self.microphones = microphones
        }

        func update(sources: CaptureSources? = nil, microphones: [Microphone]? = nil) {
            self.sources = sources ?? self.sources
            self.microphones = microphones ?? self.microphones
        }

        func availableSources() -> CaptureSources { sources }
        func availableMicrophones() -> [Microphone] { microphones }
        func windowThumbnails(for windowIDs: [CaptureWindow.ID]) -> [CaptureWindow.ID: Data] { [:] }
    }

    private static let builtIn = CaptureDisplay(id: "built-in", name: "Built-in", pixelWidth: 3024, pixelHeight: 1964)

    private func makeViewModel(
        preferences: RecordingPreferences,
        provider: ChangingSourceProvider
    ) -> RecorderViewModel {
        let services = FakeRecordingServices(session: FakeCaptureSession(finalizeResult: .success(TestFixtures.media)))
        return RecorderViewModel(
            dependencies: RecorderViewModel.Dependencies(
                coordinator: RecordingCoordinator(
                    engine: services,
                    permissions: FakePermissions(),
                    destinations: services,
                    metadataStore: services,
                    library: services
                ),
                sourceProvider: provider,
                levelPreviewEngine: services,
                permissions: FakePermissions(),
                storage: services,
                preferencesStore: InMemoryPreferencesStore(preferences),
                systemActions: NoSystemActions()
            )
        )
    }

    @Test func aDisconnectedDisplayIsReportedAndRestoredOnReconnection() async {
        let both = CaptureSources(displays: [TestFixtures.display, Self.builtIn])
        let provider = ChangingSourceProvider(sources: both, microphones: [TestFixtures.microphone])
        let viewModel = makeViewModel(
            preferences: RecordingPreferences(displayID: TestFixtures.display.id),
            provider: provider
        )
        await viewModel.refresh()
        #expect(viewModel.selectedDisplay == TestFixtures.display)

        await provider.update(sources: CaptureSources(displays: [Self.builtIn]))
        await viewModel.refresh()
        #expect(viewModel.issue == .displayUnavailable(name: TestFixtures.display.name))
        #expect(viewModel.selectedDisplay == Self.builtIn)

        await provider.update(sources: both)
        await viewModel.refresh()
        #expect(viewModel.issue == nil)
        #expect(viewModel.selectedDisplay == TestFixtures.display)
    }

    @Test func aClosedWindowBlocksStartUntilResolved() async {
        let other = CaptureWindow(id: "7", appName: "Safari", title: "Docs", bundleIdentifier: "com.apple.Safari")
        let provider = ChangingSourceProvider(
            sources: CaptureSources(displays: [Self.builtIn], windows: [TestFixtures.window, other]),
            microphones: [TestFixtures.microphone]
        )
        let viewModel = makeViewModel(
            preferences: RecordingPreferences(captureMode: .window, windowID: TestFixtures.window.id),
            provider: provider
        )
        await viewModel.refresh()
        #expect(viewModel.selectedWindow == TestFixtures.window)

        await provider.update(sources: CaptureSources(displays: [Self.builtIn], windows: [other]))
        await viewModel.refresh()
        #expect(viewModel.issue == .windowUnavailable(name: TestFixtures.window.title))
        #expect(!viewModel.canStartRecording)

        viewModel.performIssuePrimaryAction()
        #expect(viewModel.issue == nil)
        #expect(viewModel.selectedWindow == other)
        #expect(viewModel.canStartRecording)
    }

    @Test func aRemovedMicrophoneIsReportedAndCanBeTurnedOff() async {
        let provider = ChangingSourceProvider(
            sources: CaptureSources(displays: [Self.builtIn]),
            microphones: [TestFixtures.microphone]
        )
        let viewModel = makeViewModel(
            preferences: RecordingPreferences(microphoneID: TestFixtures.microphone.id),
            provider: provider
        )
        await viewModel.refresh()

        await provider.update(microphones: [])
        await viewModel.refresh()
        #expect(viewModel.issue == .microphoneUnavailable(name: TestFixtures.microphone.name))
        #expect(!viewModel.canStartRecording)

        viewModel.performIssueSecondaryAction()
        #expect(!viewModel.isMicrophoneEnabled)
        #expect(viewModel.issue == nil)
        #expect(viewModel.canStartRecording)
    }
}
