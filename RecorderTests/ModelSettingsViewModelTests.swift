import Foundation
import Testing

@testable import Recorder

@MainActor
struct ModelSettingsViewModelTests {
    private let tiny = ModelFixtures.tiny
    private let large = ModelFixtures.large

    private func makeViewModel(_ harness: ModelManagerHarness) -> ModelSettingsViewModel<SpeechModel> {
        ModelSettingsViewModel(manager: harness.manager, systemActions: FakeSystemActions())
    }

    @Test func rowsFollowTheManager() async throws {
        let harness = ModelManagerHarness()
        let viewModel = makeViewModel(harness)
        #expect(viewModel.rows.map(\.state) == [.notInstalled, .notInstalled, .notInstalled])

        try await harness.install(tiny.id)
        try harness.manager.select(tiny.id)

        let row = try #require(viewModel.rows.first)
        #expect(row.isSelected)
        #expect(row.state.isInstalled)
        #expect(row.sizeBytes == ModelFixtures.artifact.totalBytes)
    }

    @Test func noModelsOfferARecommendationWithoutDownloadingIt() async {
        let harness = ModelManagerHarness()
        let viewModel = makeViewModel(harness)

        await viewModel.refresh()

        #expect(viewModel.notice == .noModelInstalled(recommended: tiny))
        #expect(harness.provider.read(\.downloadCalls).isEmpty)
    }

    @Test func noticeWaitsForTheFirstCheckOfTheDisk() {
        let viewModel = makeViewModel(ModelManagerHarness())

        #expect(viewModel.notice == nil)
    }

    @Test func installedWithoutSelectionAsksToChooseOne() async throws {
        let harness = ModelManagerHarness()
        let viewModel = makeViewModel(harness)
        try await harness.install(tiny.id)
        try await harness.install(large.id)
        try await harness.manager.remove(tiny.id)
        await viewModel.refresh()

        #expect(viewModel.notice == .noModelSelected)

        viewModel.select(large.id)
        #expect(viewModel.notice == nil)
    }

    @Test func missingSelectionWarnsAndWaitsForTheUser() async throws {
        let harness = ModelManagerHarness()
        let viewModel = makeViewModel(harness)
        try await harness.install(tiny.id)
        try await harness.install(large.id)
        viewModel.select(tiny.id)

        harness.provider.update { $0.filesOnDisk.remove(tiny.id) }
        await viewModel.refresh()

        #expect(viewModel.notice == .selectedModelUnavailable(tiny))
        #expect(harness.manager.selectedModelID == tiny.id)
        #expect(harness.provider.read(\.downloadCalls).count == 2)
    }

    @Test func selectingAnUnavailableModelExplainsWhy() {
        let viewModel = makeViewModel(ModelManagerHarness())

        viewModel.select(tiny.id)

        #expect(viewModel.actionIssue == ModelIssue(ModelManagementError.modelNotInstalled))
    }

    @Test func removalAsksFirstAndStatesWhatItFrees() async throws {
        let harness = ModelManagerHarness()
        let viewModel = makeViewModel(harness)
        try await harness.install(tiny.id)
        viewModel.select(tiny.id)

        viewModel.requestRemoval(of: tiny.id)

        let request = try #require(viewModel.removalRequest)
        #expect(request.reclaimedBytes == ModelFixtures.artifact.totalBytes)
        #expect(request.isSelected)
        #expect(harness.manager.state(of: tiny.id).isInstalled)

        viewModel.confirmRemoval()
        try await harness.waitForState(of: tiny.id) { $0 == .notInstalled }
        #expect(viewModel.removalRequest == nil)
        #expect(harness.manager.selectedModelID == nil)
    }

    @Test func cancellingRemovalLeavesTheModel() async throws {
        let harness = ModelManagerHarness()
        let viewModel = makeViewModel(harness)
        try await harness.install(tiny.id)

        viewModel.requestRemoval(of: tiny.id)
        viewModel.cancelRemoval()

        #expect(viewModel.removalRequest == nil)
        #expect(harness.provider.read(\.removals).isEmpty)
    }

    @Test func removalFailureIsShown() async throws {
        let harness = ModelManagerHarness()
        let viewModel = makeViewModel(harness)
        try await harness.install(tiny.id)
        harness.provider.update { $0.removeError = .removalFailed(detail: "busy") }

        viewModel.requestRemoval(of: tiny.id)
        viewModel.confirmRemoval()
        for _ in 0..<500 where viewModel.actionIssue == nil {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(viewModel.actionIssue == ModelIssue(ModelManagementError.removalFailed(detail: "busy")))
    }

    @Test func failedDownloadsAreDiscardedWithoutAQuestion() async throws {
        let harness = ModelManagerHarness()
        let viewModel = makeViewModel(harness)
        harness.provider.update { $0.downloadError = ModelManagementError.noNetwork }
        viewModel.download(tiny.id)
        try await harness.waitForState(of: tiny.id) { $0 == .failed(.noNetwork) }

        viewModel.requestRemoval(of: tiny.id)

        #expect(viewModel.removalRequest == nil)
        try await harness.waitForState(of: tiny.id) { $0 == .notInstalled }
    }

    @Test func unusedModelsAreInstalledOnesThatAreNotSelected() async throws {
        let harness = ModelManagerHarness()
        let viewModel = makeViewModel(harness)
        try await harness.install(tiny.id)
        try await harness.install(large.id)
        viewModel.select(tiny.id)

        #expect(viewModel.unusedModels.map(\.id) == [large.id])
    }

    @Test(
        arguments: [
            ModelManagementError.noNetwork,
            .downloadFailed(detail: "Oops."),
            .insufficientDiskSpace(requiredBytes: 1_000_000_000, availableBytes: 1),
            .insufficientDiskSpace(requiredBytes: 0, availableBytes: 0),
            .modelUnavailable,
            .unsupportedOnThisMac,
            .verificationFailed(detail: "x"),
            .interruptedDownload,
            .damagedInstallation,
            .storageAccessDenied(detail: "x"),
            .removalFailed(detail: "x"),
            .modelInUse,
            .modelNotInstalled,
            .noModelSelected,
            .selectedModelUnavailable("x")
        ]
    )
    func everyFailureExplainsItself(error: ModelManagementError) {
        let issue = ModelIssue(error)

        #expect(!issue.title.isEmpty)
        #expect(!issue.message.isEmpty)
    }

    @Test func requiredSpaceReachesTheMessage() {
        let issue = ModelIssue(
            ModelManagementError.insufficientDiskSpace(requiredBytes: 2_000_000_000, availableBytes: 1)
        )

        #expect(issue.message.contains(SettingsFormat.size(bytes: 2_000_000_000)))
    }
}

/// Finder and System Settings, recorded rather than opened.
actor FakeSystemActionsLog {
    var opened: [URL] = []
    var panes: [SystemSettingsPane] = []
    func record(_ url: URL) { opened.append(url) }
    func record(_ pane: SystemSettingsPane) { panes.append(pane) }
}

struct FakeSystemActions: SystemActions {
    let log = FakeSystemActionsLog()

    func open(_ pane: SystemSettingsPane) async { await log.record(pane) }
    func openInFinder(_ url: URL) async { await log.record(url) }
    func revealInFinder(_ url: URL) async {}
    func openFile(_ url: URL) async -> Bool { true }
}
