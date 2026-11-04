import Foundation
import Observation

/// Presentation state of the Settings window.
///
/// This is a layout-only implementation: model downloads, index building and update checks are simulated by
/// `advanceSimulation()`, and storage figures come from fixed sample data. No model is downloaded or loaded, and
/// no file, login item or network service is touched.
@MainActor
@Observable
final class SettingsViewModel {
    /// Search index progress, as the Semantic Search section describes it.
    enum IndexStatus: Equatable {
        case off
        case waitingForModel
        case indexing(indexed: Int, total: Int)
        case upToDate
    }

    let data: SettingsPreviewData

    var selectedTab: SettingsTab = .general
    var sheet: SettingsSheet?

    var launchesAtLogin = true
    var showsMenuBarIcon = true
    var opensRecorderOnDockClick = true
    var notifiesWhenProcessingFinishes = true
    var closeBehavior: CloseBehavior = .keepRunning

    var isSemanticSearchEnabled = true
    var language: TranscriptionLanguage
    var postponesOnBattery = true
    var checksForUpdatesAutomatically = true

    var modelStates: [SpeechModel.ID: ModelInstallState] = [:]
    var defaultModelID: SpeechModel.ID
    var embeddingState: ModelInstallState = .installed
    var indexedRecordingCount = 0
    private(set) var location: StorageLocation
    private(set) var previewCacheMegabytes = 0
    var updateStatus: UpdateCheckStatus = .idle

    /// Simulation steps since the window opened; drives index and update-check timing.
    var tick = 0
    var updateCheckStartTick = 0

    init(data: SettingsPreviewData = .sample, scenario: SettingsPreviewScenario = .general) {
        self.data = data
        defaultModelID = data.defaultModelID
        language = data.languages[0]
        location = data.location
        apply(scenario)
    }

    // MARK: - General

    var dockClickNote: String {
        opensRecorderOnDockClick
            ? String(localized: "Shows the Recorder, or the recording in progress.")
            : String(localized: "Clicking the Dock icon opens the Library instead.")
    }

    /// Explains what closing the Recorder window does; it depends on whether the menu bar icon is shown.
    var closeBehaviorNote: String {
        switch closeBehavior {
        case .keepRunning where showsMenuBarIcon:
            String(localized: "Verbatim stays in the menu bar and Dock. A recording in progress continues.")
        case .keepRunning:
            String(localized: "Verbatim stays in the Dock. A recording in progress continues.")
        case .quit:
            String(
                localized: """
                    Verbatim quits when the window closes. If a recording is in progress, it keeps running until \
                    you stop it and the file is saved.
                    """
            )
        }
    }

    // MARK: - Storage

    var installedSpeechModels: [SpeechModel] {
        data.speechModels.filter { state(of: $0.id).isInstalled }
    }

    /// Installed speech models plus the embedding model.
    var modelsMegabytes: Int {
        let speech = installedSpeechModels.reduce(0) { $0 + $1.sizeMegabytes }
        return speech + (embeddingState.isInstalled ? data.embeddingSizeMegabytes : 0)
    }

    var cacheMegabytes: Int {
        previewCacheMegabytes + data.searchIndexMegabytes
    }

    var totalMegabytes: Int {
        data.recordingsMegabytes + modelsMegabytes + cacheMegabytes
    }

    /// Base is offered for cleanup while it is installed but not the default.
    var unusedSpeechModel: SpeechModel? {
        data.speechModels.first { $0.id == "base" && state(of: $0.id).isInstalled && $0.id != defaultModelID }
    }

    func clearPreviewCache() {
        previewCacheMegabytes = 0
    }

    func requestLocationChange() {
        sheet = .moveRecordings
    }

    /// Simulates saving new recordings to the chosen folder. With `movingRecordings`, the real implementation will
    /// copy and verify existing recordings before removing the originals.
    func changeLocation(movingRecordings: Bool) {
        location = data.proposedLocation
        sheet = nil
    }

    func showModels() {
        selectedTab = .models
    }

    // MARK: - About

    func checkForUpdates() {
        guard updateStatus != .checking else {
            return
        }
        updateStatus = .checking
        updateCheckStartTick = tick
    }

    func showLicenses() {
        sheet = .licenses
    }

    func dismissSheet() {
        sheet = nil
    }

    // MARK: - Preview scenarios

    func apply(_ scenario: SettingsPreviewScenario) {
        launchesAtLogin = true
        showsMenuBarIcon = true
        opensRecorderOnDockClick = true
        notifiesWhenProcessingFinishes = true
        closeBehavior = .keepRunning
        isSemanticSearchEnabled = true
        language = data.languages[0]
        postponesOnBattery = true
        checksForUpdatesAutomatically = true
        modelStates = data.initialModelStates
        defaultModelID = data.defaultModelID
        embeddingState = .installed
        indexedRecordingCount = Self.initialIndexedCount
        location = data.location
        previewCacheMegabytes = data.previewCacheMegabytes
        updateStatus = .idle
        tick = 0
        selectedTab = scenario.tab
        sheet = scenario.sheet
    }

    /// The design opens with two of the 48 recordings still being indexed.
    private static let initialIndexedCount = 46
}
