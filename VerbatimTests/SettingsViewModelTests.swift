import Foundation
import Synchronization
import Testing

@testable import Verbatim

@MainActor
struct SettingsViewModelTests {
    private func makeViewModel(
        repository: InMemorySettingsRepository = InMemorySettingsRepository(),
        loginItem: FakeLoginItem = FakeLoginItem(),
        systemActions: FakeSystemActions = FakeSystemActions(),
        chooseFolder: @escaping @MainActor (URL) async -> Void = { _ in }
    ) -> SettingsViewModel {
        SettingsViewModel(
            dependencies: SettingsViewModel.Dependencies(
                preferences: AppPreferences(repository: repository),
                loginItem: loginItem,
                recordingsStorage: FakeRecordingsStorage(),
                systemActions: systemActions,
                modelManager: ModelManagerHarness(settings: repository).manager,
                languageModelManager: LanguageModelHarness().manager,
                embeddingModelManager: .empty(),
                summaryPreferences: SummaryPreferences(repository: InMemorySummarySettingsRepository()),
                agentServer: AgentServerController(
                    host: FakeAgentServerHost(),
                    repository: InMemoryAgentServerSettingsRepository()
                ),
                metadata: AppMetadata(version: "0.1.0", build: "7"),
                chooseRecordingsFolder: chooseFolder
            )
        )
    }

    @Test func closeNoteFollowsTheMenuBarSetting() {
        let viewModel = makeViewModel()
        #expect(viewModel.closeBehaviorNote.contains("menu bar"))

        viewModel.showsMenuBarIcon = false
        #expect(viewModel.closeBehaviorNote.hasPrefix("Verbatim stays in the Dock."))
        #expect(!viewModel.closeBehaviorNote.contains("menu bar"))

        viewModel.closeBehavior = .quit
        #expect(viewModel.closeBehaviorNote.hasPrefix("Verbatim quits when the window closes."))
    }

    @Test func preferencesAreSavedThroughTheRepository() {
        let repository = InMemorySettingsRepository()
        let viewModel = makeViewModel(repository: repository)

        viewModel.showsMenuBarIcon = false
        viewModel.opensRecorderOnDockClick = false
        viewModel.closeBehavior = .quit

        #expect(
            repository.loadSettings()
                == AppSettings(showsMenuBarIcon: false, opensRecorderOnDockClick: false, closeBehavior: .quit)
        )
    }

    @Test func loginItemStateComesFromTheSystem() {
        let loginItem = FakeLoginItem()
        let viewModel = makeViewModel(loginItem: loginItem)
        viewModel.refreshLoginItemStatus()
        #expect(!viewModel.launchesAtLogin)

        viewModel.launchesAtLogin = true
        #expect(viewModel.launchesAtLogin)
        #expect(loginItem.current.withLock { $0 } == .enabled)

        viewModel.launchesAtLogin = false
        #expect(!viewModel.launchesAtLogin)
    }

    @Test func loginItemThatNeedsApprovalSaysSo() {
        let loginItem = FakeLoginItem()
        loginItem.current.withLock { $0 = .requiresApproval }
        let viewModel = makeViewModel(loginItem: loginItem)

        viewModel.refreshLoginItemStatus()

        #expect(viewModel.launchesAtLogin)
        #expect(viewModel.loginItemNote.contains("System Settings"))
    }

    @Test func failingToChangeTheLoginItemKeepsTheRealStateAndReports() {
        let loginItem = FakeLoginItem()
        loginItem.shouldFail.withLock { $0 = true }
        let viewModel = makeViewModel(loginItem: loginItem)

        viewModel.launchesAtLogin = true

        #expect(!viewModel.launchesAtLogin)
        #expect(viewModel.issue != nil)
    }

    @Test func storageComesFromTheRecordingsAndTheModels() async {
        let viewModel = makeViewModel()

        await viewModel.refreshStorage()

        #expect(viewModel.recordingsStorage?.recordingCount == 3)
        #expect(viewModel.totalBytes == 5_000)
    }

    @Test func choosingAFolderGoesThroughTheRecorderAndRefreshes() async throws {
        let chosen = Mutex<URL?>(nil)
        let viewModel = makeViewModel(chooseFolder: { url in chosen.withLock { $0 = url } })
        let folder = URL(filePath: "/tmp/elsewhere", directoryHint: .isDirectory)

        viewModel.chooseRecordingsFolder(folder)
        for _ in 0..<500 where viewModel.recordingsStorage == nil {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(chosen.withLock { $0 } == folder)
        #expect(viewModel.recordingsStorage != nil)
    }

    @Test func aboutShowsTheInjectedMetadata() {
        #expect(makeViewModel().metadata == AppMetadata(version: "0.1.0", build: "7"))
    }

    @Test func licensesOpenAndClose() {
        let viewModel = makeViewModel()

        viewModel.showLicenses()
        #expect(viewModel.isShowingLicenses)

        viewModel.dismissLicenses()
        #expect(!viewModel.isShowingLicenses)
    }

    @Test func shippedLicensesAllLinkToTheirText() {
        #expect(ThirdPartyLicense.shipped.allSatisfy { $0.url != nil })
        #expect(ThirdPartyLicense.noticesURL?.lastPathComponent == "THIRD_PARTY_NOTICES.md")
    }

    @Test func shippedLicensesHaveUniqueNames() {
        let names = ThirdPartyLicense.shipped.map(\.name)
        #expect(Set(names).count == names.count)
    }

    @Test func shippedLicensesOmitPackagesThatAreOnlyResolved() {
        let names = Set(ThirdPartyLicense.shipped.map(\.name))
        #expect(names.isDisjoint(with: ["swift-argument-parser", "swift-asn1", "swift-syntax"]))
        #expect(names.isSuperset(of: ["sqlite-vec", "MLX", "swift-jinja", "Multilingual E5 models"]))
    }

    // MARK: - Design scenarios

    @Test(arguments: [
        (SettingsPreviewScenario.general, SettingsTab.general, false),
        (.models, .models, false),
        (.removeModel, .models, false),
        (.noModels, .models, false),
        (.storage, .storage, false),
        (.about, .about, false),
        (.licenses, .about, true)
    ])
    func scenariosSelectTabAndSheet(scenario: SettingsPreviewScenario, tab: SettingsTab, showsLicenses: Bool) {
        let viewModel = SettingsViewModel.preview(scenario)

        #expect(viewModel.selectedTab == tab)
        #expect(viewModel.isShowingLicenses == showsLicenses)
    }

    @Test func removeModelScenarioAsksAboutBase() async throws {
        let viewModel = SettingsViewModel.preview(.removeModel)

        for _ in 0..<500 where viewModel.models.removalRequest == nil {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(viewModel.models.removalRequest?.model.id == SettingsPreviewScenario.sampleRemovedModelID)
    }

    @Test func modelsScenarioSimulatesADownloadOnSampleModels() async {
        let viewModel = SettingsViewModel.preview(.models)

        await viewModel.models.refresh()

        let states = viewModel.models.rows.map(\.state)
        #expect(states.contains { $0.isInstalled })
        #expect(states.contains { $0.isInstalling })
    }

    @Test func noModelsScenarioShowsTheEmptyState() async {
        let viewModel = SettingsViewModel.preview(.noModels)

        await viewModel.models.refresh()

        guard case .noModelInstalled = viewModel.models.notice else {
            Issue.record("Expected the empty state")
            return
        }
    }

    @Test func endingAPreviewReturnsToRealDependencies() {
        let repository = InMemorySettingsRepository()
        let viewModel = makeViewModel(repository: repository)
        viewModel.showsMenuBarIcon = false

        viewModel.apply(.general)
        #expect(viewModel.showsMenuBarIcon)
        viewModel.showsMenuBarIcon = true
        viewModel.closeBehavior = .quit
        #expect(repository.loadSettings().closeBehavior == .keepRunning, "Scenarios must not touch saved preferences")

        viewModel.endPreview()
        #expect(!viewModel.showsMenuBarIcon)
    }
}

struct SettingsFormatTests {
    @Test(arguments: [(Int64(75_000_000), "75 MB"), (570_000_000, "570 MB"), (0, "0 MB")])
    func formatsMegabytes(bytes: Int64, expected: String) {
        #expect(SettingsFormat.size(bytes: bytes) == expected)
    }

    @Test func formatsGigabytesWithOneDecimal() {
        #expect(SettingsFormat.size(bytes: 1_638_000_000).hasSuffix(" GB"))
        #expect(SettingsFormat.size(bytes: 1_638_000_000).hasPrefix("1"))
    }

    @Test func downloadCaptionShowsBytesOfTotal() {
        let caption = SettingsFormat.downloadCaption(
            ModelDownloadProgress(completedBytes: 570_000_000, totalBytes: 800_000_000)
        )

        #expect(caption == "570 MB of 800 MB")
    }

    @Test func downloadCaptionNeverExceedsTheTotal() {
        let caption = SettingsFormat.downloadCaption(
            ModelDownloadProgress(completedBytes: 900_000_000, totalBytes: 800_000_000)
        )

        #expect(caption == "800 MB of 800 MB")
    }
}

struct SettingsPreviewScenarioTests {
    @Test func readsScenarioFromDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "SettingsPreviewScenarioTests"))
        defer { defaults.removePersistentDomain(forName: "SettingsPreviewScenarioTests") }

        #expect(SettingsPreviewScenario.fromLaunchArguments(defaults) == nil)

        defaults.set("licenses", forKey: SettingsPreviewScenario.launchArgumentKey)
        #expect(SettingsPreviewScenario.fromLaunchArguments(defaults) == .licenses)
    }
}

final class FakeLoginItem: LoginItemControlling {
    let current = Mutex(LoginItemStatus.disabled)
    let shouldFail = Mutex(false)

    func status() -> LoginItemStatus {
        current.withLock { $0 }
    }

    func setEnabled(_ isEnabled: Bool) throws {
        if shouldFail.withLock({ $0 }) {
            throw CocoaError(.featureUnsupported)
        }
        current.withLock { $0 = isEnabled ? .enabled : .disabled }
    }
}

struct FakeRecordingsStorage: RecordingsStorageProviding {
    func recordingsStorage() async throws -> RecordingsStorage {
        RecordingsStorage(
            location: RecordingLocation(
                url: URL(filePath: "/tmp/recordings", directoryHint: .isDirectory),
                displayPath: "~/Movies/Verbatim",
                availableBytes: 1_000_000,
                isAccessible: true
            ),
            recordingCount: 3,
            usedBytes: 5_000
        )
    }
}
