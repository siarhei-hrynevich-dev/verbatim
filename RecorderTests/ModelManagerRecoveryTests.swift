import Foundation
import Testing

@testable import Recorder

/// What happens across restarts, and when the disk no longer matches what was recorded.
@MainActor
struct ModelReconciliationTests {
    private let id = ModelFixtures.tiny.id

    private func harness(
        installed ids: [SpeechModel.ID],
        filesOnDisk: Set<SpeechModel.ID>,
        selectedModelID: SpeechModel.ID? = nil
    ) -> ModelManagerHarness {
        var registry = ModelRegistry()
        for id in ids {
            registry.installations[id] = ModelFixtures.installation()
        }
        let provider = FakeModelProvider()
        provider.update { $0.filesOnDisk = filesOnDisk }
        return ModelManagerHarness(
            provider: provider,
            registryStore: InMemoryModelRegistryStore(registry: registry),
            settings: InMemorySettingsRepository(selectedModelID: selectedModelID)
        )
    }

    @Test func installedModelsAreRestoredUsingQuickChecksAlone() async throws {
        let harness = harness(installed: [id], filesOnDisk: [id])

        await harness.manager.reconcile()

        #expect(harness.manager.state(of: id) == .installed(sizeBytes: ModelFixtures.artifact.totalBytes))
        #expect(harness.provider.read { $0.verifyCalls.map(\.depth) } == [.quick])
        #expect(harness.provider.read(\.downloadCalls).isEmpty)
    }

    @Test func aCancelledCallerCannotMakeHealthyFilesLookDamaged() async throws {
        let harness = harness(installed: [id], filesOnDisk: [id])

        let window = Task { await harness.manager.reconcile() }
        window.cancel()
        await window.value

        #expect(harness.manager.state(of: id).isInstalled)
    }

    @Test func installedStateSurvivesARealInstallAndRestart() async throws {
        let first = ModelManagerHarness()
        try await first.install(id)

        let second = await first.relaunched()

        #expect(second.manager.state(of: id).isInstalled)
    }

    @Test func modelRemovedExternallyBecomesNotInstalledAndIsForgotten() async throws {
        let harness = harness(installed: [id], filesOnDisk: [])

        await harness.manager.reconcile()

        #expect(harness.manager.state(of: id) == .notInstalled)
        #expect(await harness.registryStore.registry.installations[id] == nil)
        #expect(harness.provider.read(\.downloadCalls).isEmpty)
    }

    @Test func selectedModelGoneShowsAsUnavailableWithoutSwitchingOrDownloading() async throws {
        let other = ModelFixtures.large.id
        let harness = harness(installed: [id, other], filesOnDisk: [other], selectedModelID: id)

        await harness.manager.reconcile()

        #expect(harness.manager.selectionStatus == .unavailable(ModelFixtures.tiny))
        #expect(harness.manager.selectedModelID == id)
        #expect(harness.provider.read(\.downloadCalls).isEmpty)
        #expect(throws: ModelManagementError.selectedModelUnavailable(id)) {
            try harness.manager.resolveSelectedModel()
        }
    }

    @Test func modelRemovedWhileRunningIsNoticedOnTheNextCheck() async throws {
        let harness = ModelManagerHarness()
        try await harness.install(id)
        try harness.manager.select(id)

        harness.provider.update { $0.filesOnDisk = [] }
        await harness.manager.reconcile()

        #expect(harness.manager.selectionStatus == .unavailable(ModelFixtures.tiny))
    }

    @Test func missingOrChangedFilesAreDamageAndRepairStartsOver() async throws {
        let harness = harness(installed: [id], filesOnDisk: [id])
        harness.provider.update {
            $0.verifyErrors[.quick] = .verificationFailed(detail: "size")
            $0.partialBytes[id] = 10
        }

        await harness.manager.reconcile()
        #expect(harness.manager.state(of: id) == .failed(.damagedInstallation))

        harness.provider.update { $0.verifyErrors = [:] }
        harness.manager.download(id)
        try await harness.waitForState(of: id) { $0.isInstalled }

        // The downloader would keep a damaged file whose metadata looks current, so it has to go first.
        #expect(harness.provider.read { $0.removals.first?.id } == id)
    }

    @Test func storageAccessProblemsAreReportedWithoutForgettingTheModel() async throws {
        let harness = harness(installed: [id], filesOnDisk: [id])
        harness.provider.update { $0.verifyErrors[.quick] = .storageAccessDenied(detail: "denied") }

        await harness.manager.reconcile()

        #expect(harness.manager.state(of: id) == .failed(.storageAccessDenied(detail: "denied")))
        #expect(await harness.registryStore.registry.installations[id] != nil)
    }

    @Test func restartDuringDownloadShowsAnInterruptedDownloadThatCanContinue() async throws {
        let first = ModelManagerHarness()
        first.provider.update { $0.holdsDownloads = true }
        first.manager.download(id)
        try await first.waitForGate(of: id)

        first.provider.update { $0.holdsDownloads = false }
        let second = await first.relaunched()

        #expect(second.manager.state(of: id) == .failed(.interruptedDownload))
        second.manager.download(id)
        try await second.waitForState(of: id) { $0.isInstalled }
        first.provider.releaseDownload(of: id)
    }

    @Test func interruptedPartialFilesCanBeDiscarded() async throws {
        let harness = ModelManagerHarness()
        harness.provider.update { $0.partialBytes[id] = 10 }
        await harness.manager.reconcile()

        try await harness.manager.remove(id)

        #expect(harness.manager.state(of: id) == .notInstalled)
        #expect(harness.provider.read { $0.partialBytes[id] } == nil)
    }

    @Test func reportedFailureSurvivesAnotherCheck() async throws {
        let harness = ModelManagerHarness()
        harness.provider.update { $0.downloadError = ModelManagementError.noNetwork }
        harness.manager.download(id)
        try await harness.waitForState(of: id) { $0 == .failed(.noNetwork) }

        await harness.manager.reconcile()

        #expect(harness.manager.state(of: id) == .failed(.noNetwork))
    }

    @Test func checkingDoesNotDisturbARunningDownload() async throws {
        let harness = ModelManagerHarness()
        harness.provider.update { $0.holdsDownloads = true }
        harness.manager.download(id)
        try await harness.waitForGate(of: id)

        await harness.manager.reconcile()

        guard case .downloading = harness.manager.state(of: id) else {
            Issue.record("A check must leave a running download alone")
            return
        }
        harness.provider.releaseDownload(of: id)
        try await harness.waitForState(of: id) { $0.isInstalled }
    }

    @Test func unreadableRegistryIsReportedAndNothingCrashes() async throws {
        let harness = harness(installed: [], filesOnDisk: [])
        await harness.registryStore.failLoading(with: .storageAccessDenied(detail: "denied"))

        await harness.manager.reconcile()

        #expect(harness.manager.storageFailure == .storageAccessDenied(detail: "denied"))
        #expect(harness.manager.hasReconciled)
    }
}

@MainActor
struct ModelCatalogTests {
    @Test func offlineRefreshKeepsSavedSizesAndInstalledModels() async throws {
        let id = ModelFixtures.tiny.id
        var registry = ModelRegistry()
        registry.installations[id] = ModelFixtures.installation()
        registry.artifactSizes[ModelFixtures.large.id] = 123
        let provider = FakeModelProvider()
        provider.update {
            $0.filesOnDisk = [id]
            $0.artifactError = .noNetwork
        }
        let harness = ModelManagerHarness(
            provider: provider,
            registryStore: InMemoryModelRegistryStore(registry: registry)
        )

        await harness.manager.reconcile()
        await harness.manager.refreshCatalog()

        #expect(harness.manager.isCatalogOutdated)
        #expect(harness.manager.state(of: id).isInstalled)
        #expect(harness.manager.sizeBytes(of: ModelFixtures.large.id) == 123)
    }

    @Test func successfulRefreshSavesSizesForOfflineUseAndHappensOnce() async throws {
        let harness = ModelManagerHarness()

        await harness.manager.refreshCatalog()
        await harness.manager.refreshCatalog()

        #expect(harness.provider.read(\.catalogFetchCount) == 1)
        #expect(!harness.manager.isCatalogOutdated)
        #expect(harness.manager.sizeBytes(of: ModelFixtures.tiny.id) == ModelFixtures.artifact.totalBytes)
        let next = await harness.relaunched()
        #expect(next.manager.sizeBytes(of: ModelFixtures.tiny.id) == ModelFixtures.artifact.totalBytes)
    }

    @Test func refreshCanMarkAModelUnsupported() async {
        let harness = ModelManagerHarness()
        harness.provider.update { $0.supportedIDs = [ModelFixtures.tiny.id] }

        await harness.manager.refreshCatalog()

        #expect(harness.manager.supportedModelIDs == [ModelFixtures.tiny.id])
    }
}
