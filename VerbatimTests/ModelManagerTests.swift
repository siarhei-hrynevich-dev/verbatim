import Foundation
import Testing

@testable import Verbatim

@MainActor
struct ModelInstallationTests {
    private let id = ModelFixtures.tiny.id

    @Test func installingPassesThroughDownloadingAndVerifyingToInstalled() async throws {
        let harness = ModelManagerHarness()
        harness.provider.update { $0.holdsDownloads = true }

        harness.manager.download(id)
        guard case .downloading = harness.manager.state(of: id) else {
            Issue.record("A download should start immediately")
            return
        }

        try await harness.waitForGate(of: id)
        try await harness.waitForState(of: id) {
            if case .downloading(let progress?) = $0 {
                return progress.fraction == 0.5
            }
            return false
        }

        harness.provider.releaseDownload(of: id)
        try await harness.waitForState(of: id) { $0.isInstalled }

        #expect(harness.provider.read { $0.verifyCalls.map(\.depth) } == [.full])
        let saved = await harness.registryStore.registry
        #expect(
            saved.installations[id]
                == ModelInstallation(
                    installedAt: Date(timeIntervalSince1970: 2_000),
                    artifact: ModelFixtures.artifact
                )
        )
    }

    @Test func startingADownloadIsNotAnInstallation() async throws {
        let harness = ModelManagerHarness()
        harness.provider.update { $0.holdsDownloads = true }

        harness.manager.download(id)
        try await harness.waitForGate(of: id)

        #expect(!harness.manager.state(of: id).isInstalled)
        #expect(await harness.registryStore.registry.installations.isEmpty)
        harness.provider.releaseDownload(of: id)
        try await harness.waitForState(of: id) { $0.isInstalled }
    }

    @Test func duplicateRequestsDownloadOnce() async throws {
        let harness = ModelManagerHarness()
        harness.provider.update { $0.holdsDownloads = true }

        harness.manager.download(id)
        harness.manager.download(id)
        try await harness.waitForGate(of: id)
        harness.manager.download(id)

        harness.provider.releaseDownload(of: id)
        try await harness.waitForState(of: id) { $0.isInstalled }
        harness.manager.download(id)

        #expect(harness.provider.read(\.downloadCalls) == [id])
        #expect(harness.manager.state(of: id).isInstalled)
    }

    @Test func failedDownloadReportsAndKeepsPartialFilesForRetry() async throws {
        let harness = ModelManagerHarness()
        harness.provider.update { $0.downloadError = ModelManagementError.noNetwork }

        harness.manager.download(id)
        try await harness.waitForState(of: id) { $0 == .failed(.noNetwork) }

        #expect(harness.provider.read(\.removals).isEmpty)
        #expect(await harness.registryStore.registry.installations.isEmpty)

        harness.provider.update { $0.downloadError = nil }
        harness.manager.download(id)
        try await harness.waitForState(of: id) { $0.isInstalled }
    }

    @Test func unexpectedDownloadErrorsBecomeFailuresToo() async throws {
        let harness = ModelManagerHarness()
        harness.provider.update { $0.downloadError = URLError(.badServerResponse) }

        harness.manager.download(id)

        try await harness.waitForState(of: id) {
            if case .failed(.downloadFailed) = $0 {
                return true
            }
            return false
        }
    }

    @Test func unavailableModelFailsWithoutDownloading() async throws {
        let harness = ModelManagerHarness()
        harness.provider.update { $0.artifactError = .modelUnavailable }

        harness.manager.download(id)

        try await harness.waitForState(of: id) { $0 == .failed(.modelUnavailable) }
        #expect(harness.provider.read(\.downloadCalls).isEmpty)
    }

    @Test func modelUnsupportedByThisMacIsRefused() {
        let provider = FakeModelProvider(supportedIDs: [ModelFixtures.large.id])
        let harness = ModelManagerHarness(provider: provider)

        harness.manager.download(id)

        #expect(harness.manager.state(of: id) == .failed(.unsupportedOnThisMac))
        #expect(harness.provider.read(\.downloadCalls).isEmpty)
    }

    @Test func insufficientDiskSpaceStopsBeforeDownloading() async throws {
        let harness = ModelManagerHarness()
        harness.provider.update { $0.availableBytes = 1_000 }

        harness.manager.download(id)

        try await harness.waitForState(of: id) {
            if case .failed(.insufficientDiskSpace(_, let available)) = $0 {
                return available == 1_000
            }
            return false
        }
        #expect(harness.provider.read(\.downloadCalls).isEmpty)
    }

    @Test func failedVerificationDiscardsFilesAndIsNotInstalled() async throws {
        let harness = ModelManagerHarness()
        harness.provider.update { $0.verifyErrors[.full] = .verificationFailed(detail: "hash") }

        harness.manager.download(id)

        try await harness.waitForState(of: id) { $0 == .failed(.verificationFailed(detail: "hash")) }
        #expect(harness.provider.read { $0.removals.map(\.id) } == [id])
        #expect(await harness.registryStore.registry.installations.isEmpty)
    }

    @Test func cancellingRemovesPartialFilesAndAllowsDownloadingAgain() async throws {
        let harness = ModelManagerHarness()
        harness.provider.update { $0.holdsDownloads = true }
        harness.manager.download(id)
        try await harness.waitForGate(of: id)

        harness.manager.cancelDownload(id)
        #expect(harness.manager.state(of: id) == .notInstalled)
        harness.provider.releaseDownload(of: id)
        try await harness.waitForFile { $0.removals.map(\.id) == [id] }

        harness.provider.update { $0.holdsDownloads = false }
        harness.manager.download(id)
        try await harness.waitForState(of: id) { $0.isInstalled }
        #expect(harness.provider.read(\.downloadCalls).count == 2)
    }

    @Test func downloadingImmediatelyAfterCancellingWaitsForTheCancelledOne() async throws {
        let harness = ModelManagerHarness()
        harness.provider.update { $0.holdsDownloads = true }
        harness.manager.download(id)
        try await harness.waitForGate(of: id)

        harness.manager.cancelDownload(id)
        harness.manager.download(id)
        harness.provider.update { $0.holdsDownloads = false }
        #expect(harness.provider.read(\.downloadCalls).count == 1)

        harness.provider.releaseDownload(of: id)
        try await harness.waitForState(of: id) { $0.isInstalled }
        #expect(harness.provider.read(\.downloadCalls).count == 2)
    }

    @Test func recordingPausesAnInstallAndItContinuesAfterwards() async throws {
        let harness = ModelManagerHarness()
        harness.provider.update { $0.holdsDownloads = true }
        harness.manager.download(id)
        try await harness.waitForGate(of: id)

        harness.manager.setRecordingActive(true)
        guard case .waitingForRecording = harness.manager.state(of: id) else {
            Issue.record("Recording should hold back the install")
            return
        }
        harness.provider.releaseDownload(of: id)
        try await Task.sleep(for: .milliseconds(30))
        #expect(harness.provider.read(\.removals).isEmpty, "Partial files are kept to continue later")
        guard case .waitingForRecording = harness.manager.state(of: id) else {
            Issue.record("The stopped download must not change the waiting state")
            return
        }

        harness.provider.update { $0.holdsDownloads = false }
        harness.manager.setRecordingActive(false)
        try await harness.waitForState(of: id) { $0.isInstalled }
        #expect(harness.provider.read(\.downloadCalls).count == 2)
    }

    @Test func nothingStartsDuringARecording() async throws {
        let harness = ModelManagerHarness()
        harness.manager.setRecordingActive(true)

        harness.manager.download(id)
        try await Task.sleep(for: .milliseconds(30))

        #expect(harness.manager.state(of: id) == .waitingForRecording(nil))
        #expect(harness.provider.read(\.downloadCalls).isEmpty)

        harness.manager.cancelDownload(id)
        #expect(harness.manager.state(of: id) == .notInstalled)
        harness.manager.setRecordingActive(false)
        try await Task.sleep(for: .milliseconds(30))
        #expect(harness.provider.read(\.downloadCalls).isEmpty)
    }

    @Test func downloadingRightAfterCancellingAPausedInstallWaitsForItsCleanup() async throws {
        let harness = ModelManagerHarness()
        harness.provider.update { $0.partialBytes[id] = 10 }
        harness.manager.setRecordingActive(true)
        harness.manager.download(id)

        harness.manager.cancelDownload(id)
        harness.manager.setRecordingActive(false)
        harness.manager.download(id)

        try await harness.waitForState(of: id) { $0.isInstalled }
        #expect(harness.provider.read { $0.removals.map(\.id) } == [id])
        #expect(harness.provider.read { $0.filesOnDisk.contains(id) }, "Cleanup must not remove the new files")
    }

    @Test func catalogIsNotFetchedDuringARecording() async {
        let harness = ModelManagerHarness()
        harness.manager.setRecordingActive(true)

        await harness.manager.refreshCatalog()

        #expect(harness.provider.read(\.catalogFetchCount) == 0)
    }
}
