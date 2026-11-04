import Foundation
import Observation
import os

/// Presentation state of the Recorder window: the settings being edited and how the coordinator's recording state
/// reads on screen. The recording itself belongs to `RecordingCoordinator`, so it continues without this window.
@MainActor
@Observable
final class RecorderViewModel {
    enum Phase: Equatable {
        case ready
        case preparing
        case recording(RecordingClock)
        case finishing(RecordingClock)
    }

    enum Status {
        case ready
        case needsAttention
        case preparing
        case recording
        case paused
        case finishing
    }

    /// The services the Recorder window works with, created by the composition root.
    struct Dependencies {
        let coordinator: RecordingCoordinator
        let sourceProvider: any CaptureSourceProviding
        let levelPreviewEngine: any CaptureEngine
        let permissions: any CapturePermissions
        let storage: any RecordingDestinationStore
        let preferencesStore: any RecordingPreferencesStore
        let systemActions: any SystemActions
    }

    /// Set by design-review scenarios; never during real capture.
    var preview = RecorderPreviewState()

    let selection: RecorderSourceSelection
    let levelPreview: LevelPreviewController

    private(set) var location: RecordingLocation?
    /// A problem from a user action outside a recording, such as a folder that could not be used.
    var actionIssue: RecorderIssue?
    var sourceDiscoveryIssue: RecorderIssue?
    var hasLoadedSources = false
    /// macOS only answers this when asked, so it is kept here for the callout to update when it changes.
    var isMicrophoneAccessDenied = false
    var isChoosingFolder = false

    var captureMode: CaptureMode { didSet { settingsDidChange(reloadsSources: true) } }
    var isMicrophoneEnabled: Bool { didSet { microphoneEnabledDidChange() } }
    var isSystemAudioEnabled: Bool { didSet { settingsDidChange() } }
    var quality: VideoQuality { didSet { savePreferences() } }
    var frameRate: FrameRate { didSet { savePreferences() } }
    var transcribesWhenFinished: Bool { didSet { savePreferences() } }

    @ObservationIgnored let dependencies: Dependencies
    /// Refreshes sources while the setup screen is on-screen. Cancelled when it goes away.
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored var isSetupVisible = false

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        let preferences = dependencies.preferencesStore.load()
        selection = RecorderSourceSelection(preferences: preferences)
        levelPreview = LevelPreviewController(engine: dependencies.levelPreviewEngine)
        captureMode = preferences.captureMode
        isMicrophoneEnabled = preferences.isMicrophoneEnabled
        isSystemAudioEnabled = preferences.isSystemAudioEnabled
        quality = preferences.quality
        frameRate = preferences.frameRate
        transcribesWhenFinished = preferences.transcribesWhenFinished
        selection.onUserSelection = { [weak self] in
            self?.settingsDidChange()
        }
    }

    var coordinator: RecordingCoordinator {
        dependencies.coordinator
    }

    // MARK: - State

    var phase: Phase {
        if let previewPhase = preview.phase {
            return previewPhase
        }
        switch coordinator.state {
        case .idle, .failed: return .ready
        case .preparing: return .preparing
        case .recording(let clock): return .recording(clock)
        case .stopping(let clock), .finalizing(let clock): return .finishing(clock)
        }
    }

    var status: Status {
        switch phase {
        case .ready: issue == nil ? .ready : .needsAttention
        case .preparing: .preparing
        case .recording(let clock): clock.isPaused ? .paused : .recording
        case .finishing: .finishing
        }
    }

    var canStartRecording: Bool {
        guard phase == .ready else {
            return false
        }
        let requiresScreenCapture = captureMode.capturesVideo || isSystemAudioEnabled
        return !(issue?.blocksStart(requiresScreenCapture: requiresScreenCapture) ?? false)
    }

    var selectedDisplay: CaptureDisplay? {
        selection.selectedDisplay
    }

    var selectedWindow: CaptureWindow? {
        selection.selectedWindow
    }

    var selectedMicrophone: Microphone? {
        selection.selectedMicrophone
    }

    var savedRecordingTitle: String? {
        preview.savedRecordingTitle ?? coordinator.lastOutcome?.metadata.recording.title
    }

    var isCaptureBusy: Bool {
        coordinator.state.isBusy
    }

    func litSegments(for source: AudioSourceKind) -> Int {
        let levels = coordinator.activeRecording == nil ? levelPreview.levels : coordinator.levels
        let level = source == .microphone ? levels.microphone : levels.systemAudio
        return Int((level * Double(LevelMeter.segmentCount)).rounded())
    }

    /// `~/Movies/Verbatim · 214 GB free`.
    var storageSummary: String {
        if let summary = preview.storageSummary {
            return summary
        }
        guard let location else {
            return ""
        }
        let free = RecorderIssue.formattedBytes(location.availableBytes)
        return String(localized: "\(location.displayPath) · \(free) free")
    }

    var recordingsFolderPath: String {
        preview.storageSummary == nil ? location?.displayPath ?? "" : RecorderPreviewData.sample.recordingsFolderPath
    }

    // MARK: - Recording

    func startRecording(at date: Date = .now) {
        guard canStartRecording else {
            return
        }
        if preview.isActive {
            preview.savedRecordingTitle = nil
            preview.phase = .recording(RecordingClock(startedAt: date))
            return
        }
        actionIssue = nil
        levelPreview.stop()
        coordinator.requestStart(makeConfiguration())
    }

    func togglePause(at date: Date = .now) {
        guard case .recording(var clock) = preview.phase else {
            coordinator.togglePause()
            return
        }
        if clock.isPaused {
            clock.resume(at: date)
        } else {
            clock.pause(at: date)
        }
        preview.phase = .recording(clock)
    }

    func stopRecording() {
        guard case .recording = preview.phase else {
            coordinator.requestStop()
            return
        }
        preview.phase = nil
        preview.savedRecordingTitle = RecorderPreviewData.sample.savedRecordingTitle
    }

    /// Ends any recording and waits until its media is safe, for quitting.
    func stopAndWait() async {
        await coordinator.stopAndWait()
    }

    func makeConfiguration() -> RecordingConfiguration {
        let target: CaptureTarget? =
            switch captureMode {
            case .screen: selectedDisplay.map(CaptureTarget.display)
            case .window: selectedWindow.map(CaptureTarget.window)
            case .audioOnly: .audioOnly
            }
        return RecordingConfiguration(
            target: target,
            microphone: isMicrophoneEnabled ? selectedMicrophone : nil,
            capturesSystemAudio: isSystemAudioEnabled,
            quality: quality,
            frameRate: frameRate,
            transcribesWhenFinished: transcribesWhenFinished
        )
    }

    // MARK: - Folder

    func openRecordingsFolder() {
        guard let url = location?.url else {
            return
        }
        reveal(url)
    }

    func reveal(_ url: URL) {
        let systemActions = dependencies.systemActions
        Task {
            await systemActions.openInFinder(url)
        }
    }

    func chooseFolder(_ url: URL) {
        clearIssue()
        Task {
            do {
                try await dependencies.storage.useFolder(url)
            } catch {
                Self.logger.error("Could not use the chosen folder: \(String(describing: error))")
                actionIssue = .folderAccess(path: url.path(percentEncoded: false))
            }
            location = await dependencies.storage.currentLocation()
        }
    }

    func folderSelectionFailed(_ error: any Error) {
        Self.logger.error("Folder selection failed: \(String(describing: error))")
        actionIssue = .folderAccess(path: recordingsFolderPath)
    }

    func useDefaultFolder() {
        clearIssue()
        Task {
            await dependencies.storage.useDefaultFolder()
            location = await dependencies.storage.currentLocation()
        }
    }

    // MARK: - Setup screen lifetime

    /// Sources and meters are live only while the setup screen is showing in the active app, so nothing listens to
    /// the microphone or system audio behind the user's back.
    func setSetupVisible(_ isVisible: Bool) {
        isSetupVisible = isVisible
        refreshTask?.cancel()
        refreshTask = nil
        guard isVisible else {
            levelPreview.stop()
            return
        }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do {
                    try await Task.sleep(for: Self.refreshInterval)
                } catch {
                    return
                }
            }
        }
    }

    /// Reloads sources, storage and whatever depends on permissions. Never prompts.
    func refresh() async {
        guard !preview.isActive else {
            return
        }
        let provider = dependencies.sourceProvider
        let microphones = await provider.availableMicrophones()
        do {
            let sources = try await provider.availableSources()
            selection.update(sources: sources, microphones: microphones, captureMode: captureMode)
            sourceDiscoveryIssue = nil
        } catch {
            Self.logger.error("Could not list capture sources: \(String(describing: error))")
            sourceDiscoveryIssue = .sourcesUnavailable(detail: error.localizedDescription)
        }
        hasLoadedSources = true
        isMicrophoneAccessDenied = dependencies.permissions.microphoneAccess() == .denied
        location = await dependencies.storage.currentLocation()
        clearFailureThatNoLongerApplies()
        if captureMode == .window, !selection.windowsWithoutThumbnail.isEmpty {
            selection.addThumbnails(await provider.windowThumbnails(for: selection.windowsWithoutThumbnail))
        }
        updateLevelPreview()
    }

    private static let refreshInterval = Duration.seconds(3)
    private static let logger = Logger(subsystem: "dev.local.Recorder", category: "Recorder")
}
