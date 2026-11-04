import Foundation
import Observation
import os

/// Presentation state of the Settings window. The same code runs for real and for design review; only its
/// dependencies differ, which is why nothing here branches on a preview flag.
@MainActor
@Observable
final class SettingsViewModel {
    struct Dependencies {
        let preferences: AppPreferences
        let loginItem: any LoginItemControlling
        let recordingsStorage: any RecordingsStorageProviding
        let systemActions: any SystemActions
        let modelManager: ModelManager
        let metadata: AppMetadata
        /// Goes through the Recorder, which owns the recordings folder and shows it in its footer.
        let chooseRecordingsFolder: @MainActor (URL) async -> Void
    }

    var selectedTab: SettingsTab = .general
    var isShowingLicenses = false
    /// A failed General or Storage action.
    var issue: String?

    private(set) var models: ModelSettingsViewModel
    private(set) var loginItemStatus = LoginItemStatus.disabled
    /// `nil` until first read, or when it could not be read.
    private(set) var recordingsStorage: RecordingsStorage?

    private var dependencies: Dependencies
    @ObservationIgnored private let liveDependencies: Dependencies

    init(dependencies: Dependencies, previewScenario: SettingsPreviewScenario? = nil) {
        self.dependencies = dependencies
        liveDependencies = dependencies
        models = ModelSettingsViewModel(manager: dependencies.modelManager, systemActions: dependencies.systemActions)
        if let previewScenario {
            apply(previewScenario)
        }
    }

    // MARK: - General

    var launchesAtLogin: Bool {
        get { loginItemStatus != .disabled }
        set { setLaunchesAtLogin(newValue) }
    }

    var loginItemNote: String {
        loginItemStatus == .requiresApproval
            ? String(localized: "Waiting for your approval in System Settings › General › Login Items.")
            : String(localized: "Opens Verbatim when you log in to this Mac.")
    }

    var showsMenuBarIcon: Bool {
        get { dependencies.preferences.settings.showsMenuBarIcon }
        set { dependencies.preferences.update { $0.showsMenuBarIcon = newValue } }
    }

    var opensRecorderOnDockClick: Bool {
        get { dependencies.preferences.settings.opensRecorderOnDockClick }
        set { dependencies.preferences.update { $0.opensRecorderOnDockClick = newValue } }
    }

    var closeBehavior: CloseBehavior {
        get { dependencies.preferences.settings.closeBehavior }
        set { dependencies.preferences.update { $0.closeBehavior = newValue } }
    }

    var dockClickNote: String {
        opensRecorderOnDockClick
            ? String(localized: "Shows the Recorder, or the recording in progress.")
            : String(localized: "Opens the Library instead, unless a recording is in progress.")
    }

    /// Explains what closing the Recorder window does; it depends on whether the menu bar icon is shown.
    var closeBehaviorNote: String {
        switch closeBehavior {
        case .keepRunning where showsMenuBarIcon:
            String(
                localized:
                    "Verbatim stays in the Dock. A recording in progress continues, with its timer in the menu bar."
            )
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

    func refreshLoginItemStatus() {
        loginItemStatus = dependencies.loginItem.status()
    }

    private func setLaunchesAtLogin(_ isEnabled: Bool) {
        do {
            try dependencies.loginItem.setEnabled(isEnabled)
        } catch {
            Self.logger.error("Could not change the login item: \(String(describing: error))")
            issue = String(
                localized: "Verbatim couldn’t change whether it opens at login. \(error.localizedDescription)"
            )
        }
        refreshLoginItemStatus()
    }

    func openLoginItemSettings() {
        let systemActions = dependencies.systemActions
        Task {
            await systemActions.open(.loginItems)
        }
    }

    // MARK: - Storage

    var modelsBytes: Int64 {
        models.storageUsageBytes
    }

    var totalBytes: Int64 {
        (recordingsStorage?.usedBytes ?? 0) + modelsBytes
    }

    func refreshStorage() async {
        do {
            recordingsStorage = try await dependencies.recordingsStorage.recordingsStorage()
        } catch {
            Self.logger.error("Could not read recordings storage: \(String(describing: error))")
            issue = String(
                localized: "Verbatim couldn’t read how much space recordings use. \(error.localizedDescription)"
            )
        }
        await models.refresh()
    }

    func chooseRecordingsFolder(_ url: URL) {
        Task {
            await dependencies.chooseRecordingsFolder(url)
            await refreshStorage()
        }
    }

    func folderSelectionFailed(_ error: any Error) {
        Self.logger.error("Folder selection failed: \(String(describing: error))")
        issue = String(localized: "Verbatim couldn’t use that folder. \(error.localizedDescription)")
    }

    func showRecordingsInFinder() {
        guard let url = recordingsStorage?.location.url else {
            return
        }
        let systemActions = dependencies.systemActions
        Task {
            await systemActions.openInFinder(url)
        }
    }

    func showModels() {
        selectedTab = .models
    }

    func dismissIssue() {
        issue = nil
    }

    // MARK: - About

    var metadata: AppMetadata {
        dependencies.metadata
    }

    func showLicenses() {
        isShowingLicenses = true
    }

    func dismissLicenses() {
        isShowingLicenses = false
    }

    // MARK: - Preview scenarios

    /// Switches to sample data and simulated downloads, leaving real models and preferences untouched.
    func apply(_ scenario: SettingsPreviewScenario) {
        use(.preview(for: scenario))
        selectedTab = scenario.tab
        isShowingLicenses = scenario == .licenses
        if scenario == .removeModel {
            Task {
                await models.refresh()
                models.requestRemoval(of: SettingsPreviewScenario.sampleRemovedModelID)
            }
        }
    }

    /// Back to the real thing after a design scenario.
    func endPreview() {
        use(liveDependencies)
    }

    private func use(_ next: Dependencies) {
        dependencies = next
        models = ModelSettingsViewModel(manager: next.modelManager, systemActions: next.systemActions)
        recordingsStorage = nil
        refreshLoginItemStatus()
    }

    private static let logger = Logger(subsystem: "dev.local.Recorder", category: "Settings")
}
