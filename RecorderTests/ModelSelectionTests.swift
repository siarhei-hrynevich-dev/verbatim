import Foundation
import Testing

@testable import Recorder

@MainActor
struct ModelSelectionTests {
    private let id = ModelFixtures.tiny.id

    @Test func selectionOfAnInstalledModelPersistsAcrossRestart() async throws {
        let harness = ModelManagerHarness()
        try await harness.install(id)

        try harness.manager.select(id)

        #expect(harness.settings.loadSelectedModelID() == id)
        let next = await harness.relaunched()
        #expect(next.manager.selectedModelID == id)
        #expect(next.manager.selectionStatus == .ready(ModelFixtures.tiny))
    }

    @Test func modelThatIsNotInstalledCannotBeSelected() async {
        let harness = ModelManagerHarness()
        await harness.manager.reconcile()

        #expect(throws: ModelManagementError.modelNotInstalled) {
            try harness.manager.select(id)
        }
        #expect(harness.settings.loadSelectedModelID() == nil)
    }

    @Test func noSelectedModelDownloadsNothing() async throws {
        let harness = ModelManagerHarness()
        await harness.manager.reconcile()
        await harness.manager.refreshCatalog()

        #expect(harness.manager.selectionStatus == .none)
        #expect(harness.provider.read(\.downloadCalls).isEmpty)
        #expect(throws: ModelManagementError.noModelSelected) {
            try harness.manager.resolveSelectedModel()
        }
    }

    @Test func firstInstalledModelIsSelectedAndStaysAfterRestart() async throws {
        let harness = ModelManagerHarness()
        await harness.manager.reconcile()

        try await harness.install(id)

        #expect(harness.manager.selectionStatus == .ready(ModelFixtures.tiny))
        #expect(harness.settings.loadSelectedModelID() == id)
        let next = await harness.relaunched()
        #expect(next.manager.selectedModelID == id)
    }

    @Test func startingADownloadSelectsNothingUntilItIsInstalled() async throws {
        let harness = ModelManagerHarness()
        harness.provider.update { $0.holdsDownloads = true }

        harness.manager.download(id)
        try await harness.waitForGate(of: id)
        #expect(harness.manager.selectedModelID == nil)

        harness.provider.releaseDownload(of: id)
        try await harness.waitForState(of: id) { $0.isInstalled }
        #expect(harness.manager.selectedModelID == id)
    }

    @Test func failedInstallSelectsNothing() async throws {
        let harness = ModelManagerHarness()
        harness.provider.update { $0.downloadError = ModelManagementError.noNetwork }

        harness.manager.download(id)
        try await harness.waitForState(of: id) { $0 == .failed(.noNetwork) }

        #expect(harness.manager.selectedModelID == nil)
    }

    @Test func laterInstallsLeaveTheSelectionAlone() async throws {
        let harness = ModelManagerHarness()
        try await harness.install(id)

        try await harness.install(ModelFixtures.large.id)

        #expect(harness.manager.selectedModelID == id)
    }

    @Test func installingDoesNotReplaceAnUnavailableSelection() async throws {
        let harness = ModelManagerHarness()
        try await harness.install(id)
        harness.provider.update { $0.filesOnDisk = [] }
        await harness.manager.reconcile()

        try await harness.install(ModelFixtures.large.id)

        #expect(harness.manager.selectedModelID == id)
        #expect(harness.manager.selectionStatus == .unavailable(ModelFixtures.tiny))
    }

    @Test func installingDoesNotFillAnEmptySelectionWhileOtherModelsAreInstalled() async throws {
        let harness = ModelManagerHarness()
        try await harness.install(id)
        try await harness.install(ModelFixtures.large.id)
        try await harness.manager.remove(id)
        #expect(harness.manager.selectedModelID == nil)

        try await harness.install(ModelFixtures.largeTurbo.id)

        #expect(harness.manager.selectedModelID == nil)
    }

    @Test func reinstallingAfterRemovingTheOnlyModelSelectsItAgain() async throws {
        let harness = ModelManagerHarness()
        try await harness.install(id)
        try await harness.manager.remove(id)
        #expect(harness.manager.selectedModelID == nil)

        try await harness.install(ModelFixtures.large.id)

        #expect(harness.manager.selectedModelID == ModelFixtures.large.id)
    }

    @Test func resolvingGivesIdentifierAndLocationOfTheSelectedModel() async throws {
        let harness = ModelManagerHarness()
        try await harness.install(id)
        try harness.manager.select(id)

        let resolved = try harness.manager.resolveSelectedModel()

        #expect(resolved.id == id)
        #expect(resolved.modelFolder.path(percentEncoded: false).hasSuffix(id))
    }
}

@MainActor
struct ModelRemovalTests {
    private let id = ModelFixtures.tiny.id

    @Test func removingFreesFilesAndRegistry() async throws {
        let harness = ModelManagerHarness()
        try await harness.install(id)

        try await harness.manager.remove(id)

        #expect(harness.manager.state(of: id) == .notInstalled)
        #expect(harness.provider.read { $0.filesOnDisk.isEmpty })
        #expect(await harness.registryStore.registry.installations[id] == nil)
    }

    @Test func removingTheSelectedModelClearsItWithoutSelectingAnother() async throws {
        let harness = ModelManagerHarness()
        try await harness.install(id)
        try await harness.install(ModelFixtures.large.id)
        try harness.manager.select(id)

        try await harness.manager.remove(id)

        #expect(harness.manager.selectedModelID == nil)
        #expect(harness.settings.loadSelectedModelID() == nil)
        #expect(harness.manager.selectionStatus == .none)
    }

    @Test func modelInUseCannotBeRemovedUntilReleased() async throws {
        let harness = ModelManagerHarness()
        try await harness.install(id)
        try harness.manager.select(id)
        let lease = try harness.manager.acquireSelectedModel()

        await #expect(throws: ModelManagementError.modelInUse) {
            try await harness.manager.remove(id)
        }
        #expect(harness.manager.state(of: id).isInstalled)

        harness.manager.release(lease)
        try await harness.manager.remove(id)
        #expect(harness.manager.state(of: id) == .notInstalled)
    }

    @Test func failedRemovalKeepsTheInstallationAndReports() async throws {
        let harness = ModelManagerHarness()
        try await harness.install(id)
        harness.provider.update { $0.removeError = .removalFailed(detail: "busy") }

        await #expect(throws: ModelManagementError.removalFailed(detail: "busy")) {
            try await harness.manager.remove(id)
        }

        #expect(harness.manager.state(of: id).isInstalled)
        #expect(await harness.registryStore.registry.installations[id] != nil)
    }

    @Test func removingSomethingNotInstalledIsRefused() async {
        let harness = ModelManagerHarness()

        await #expect(throws: ModelManagementError.modelNotInstalled) {
            try await harness.manager.remove(id)
        }
    }

    @Test func sharedTokenizerStaysUntilItsLastModelGoes() async throws {
        let harness = ModelManagerHarness()
        try await harness.install(ModelFixtures.large.id)
        try await harness.install(ModelFixtures.largeTurbo.id)

        try await harness.manager.remove(ModelFixtures.large.id)
        #expect(harness.provider.read { $0.removals.last?.includingTokenizer } == false)

        try await harness.manager.remove(ModelFixtures.largeTurbo.id)
        #expect(harness.provider.read { $0.removals.last?.includingTokenizer } == true)
    }

    @Test func unsharedTokenizerGoesWithItsModel() async throws {
        let harness = ModelManagerHarness()
        try await harness.install(id)

        try await harness.manager.remove(id)

        #expect(harness.provider.read { $0.removals.last?.includingTokenizer } == true)
    }
}
