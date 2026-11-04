import Foundation

/// What a design-review scenario overrides in the Recorder window. It only changes what is shown: no capture,
/// permission or storage service is involved while a scenario is active.
struct RecorderPreviewState {
    var isActive = false
    var phase: RecorderViewModel.Phase?
    var issue: RecorderIssue?
    var savedRecordingTitle: String?
    var storageSummary: String?
    var pausedTranscriptionTitle: String?
}

extension RecorderViewModel {
    /// A view model that shows `scenario`, for SwiftUI previews and tests of presentation states.
    convenience init(scenario: RecorderPreviewScenario = .idle) {
        let services = PreviewRecorderServices()
        let coordinator = RecordingCoordinator(
            engine: services,
            permissions: services,
            destinations: services,
            repository: services
        )
        self.init(
            dependencies: Dependencies(
                coordinator: coordinator,
                sourceProvider: services,
                levelPreviewEngine: services,
                permissions: services,
                storage: services,
                preferencesStore: services,
                systemActions: services
            )
        )
        apply(scenario)
    }

    /// Shows a design state with sample data. The Ready state on a live view model returns to real data.
    func apply(_ scenario: RecorderPreviewScenario, at date: Date = .now) {
        guard !isCaptureBusy else {
            return
        }
        let sample = RecorderPreviewData.sample
        preview = RecorderPreviewState(
            isActive: true,
            phase: nil,
            issue: scenario.issue,
            savedRecordingTitle: scenario == .saved ? sample.savedRecordingTitle : nil,
            storageSummary: sample.storageSummary,
            pausedTranscriptionTitle: sample.pausedTranscriptionTitle
        )
        selection.showSamples(sample)
        captureMode = scenario == .picker ? .window : .screen
        if scenario == .recording {
            preview.phase = .recording(RecordingClock(startedAt: date.addingTimeInterval(-Self.sampleElapsedSeconds)))
        }
    }

    /// Leaves design review and goes back to live data.
    func endPreview() {
        restoreSavedSettings()
        preview = RecorderPreviewState()
        Task {
            await refresh()
        }
    }

    /// The design shows a recording that has been running for 12:34.
    private static let sampleElapsedSeconds: TimeInterval = 754
}

/// Stands in for every service behind SwiftUI previews and design scenarios. Starting “records” nothing and writes
/// nothing; the live app is composed from the real services instead.
private final class PreviewRecorderServices: Sendable {}

extension PreviewRecorderServices: CaptureEngine, CaptureSourceProviding, CapturePermissions {
    func availableSources() async throws -> CaptureSources {
        let sample = RecorderPreviewData.sample
        return CaptureSources(displays: sample.displays, windows: sample.windows)
    }

    func availableMicrophones() async -> [Microphone] {
        RecorderPreviewData.sample.microphones
    }

    func windowThumbnails(for windowIDs: [CaptureWindow.ID]) async -> [CaptureWindow.ID: Data] {
        [:]
    }

    func startSession(configuration: RecordingConfiguration, outputURL: URL) async throws -> any CaptureSession {
        throw RecordingFailure.initializationFailed(detail: "Design previews do not capture.")
    }

    func startLevelPreview(microphone: Microphone?, capturesSystemAudio: Bool) async throws -> any CaptureSession {
        throw RecordingFailure.initializationFailed(detail: "Design previews do not capture.")
    }

    func hasScreenCaptureAccess() -> Bool { true }
    func requestScreenCaptureAccess() async -> Bool { true }
    func microphoneAccess() -> MicrophoneAccess { .granted }
    func requestMicrophoneAccess() async -> Bool { true }
}

extension PreviewRecorderServices: RecordingDestinationStore, RecordingRepository {
    func currentLocation() async -> RecordingLocation {
        RecordingLocation(
            url: URL(fileURLWithPath: "/"),
            displayPath: RecorderPreviewData.sample.recordingsFolderPath,
            availableBytes: 214_000_000_000,
            isAccessible: true
        )
    }

    func prepareDestination(id: UUID, createdAt: Date) async throws -> RecordingDestination {
        throw RecordingFailure.initializationFailed(detail: "Design previews do not capture.")
    }

    func discardIfEmpty(_ destination: RecordingDestination) async -> Bool { false }
    func useFolder(_ url: URL) async throws {}
    func useDefaultFolder() async {}
    func save(_ metadata: RecordingMetadata, in destination: RecordingDestination) async throws {}
}

extension PreviewRecorderServices: RecordingPreferencesStore, SystemActions {
    func load() -> RecordingPreferences { RecordingPreferences() }
    func save(_ preferences: RecordingPreferences) {}
    func open(_ pane: SystemSettingsPane) async {}
    func openInFinder(_ url: URL) async {}
}
