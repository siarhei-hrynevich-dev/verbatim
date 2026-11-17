import Foundation
import Testing

@testable import Verbatim

/// The same model lifecycle as for speech, running on the language model catalog.
@MainActor
struct LanguageModelManagerTests {
    @Test func theFirstInstalledModelIsSelectedAndResolvesToItsFolder() async throws {
        let harness = LanguageModelHarness()
        await harness.manager.reconcile()
        let model = LanguageModelCatalog.curated[0]

        try await harness.install(model.id)

        #expect(harness.manager.selectionStatus == .ready(model))
        #expect(harness.settings.loadSelectedModelID() == model.id)
        let lease = try harness.manager.acquireSelectedModel()
        #expect(lease.model.folder.lastPathComponent == model.id)
        #expect(lease.model.disablesThinking == model.disablesThinking)

        await #expect(throws: ModelManagementError.modelInUse) { try await harness.manager.remove(model.id) }
        harness.manager.release(lease)
        try await harness.manager.remove(model.id)
        #expect(harness.manager.selectionStatus == .none)
    }

    @Test func modelsTooLargeForThisMacAreNotSupported() {
        let provider = HubLanguageModelProvider(
            storageLocation: FileManager.default.temporaryDirectory,
            physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
        )

        let supported = provider.supportedModelIDs()

        #expect(supported.contains("qwen3-4b-instruct-2507-4bit"))
        #expect(!supported.contains("qwen3-30b-a3b-instruct-2507-4bit"))
    }

    @Test func nothingSelectedFailsTheLeaseWithoutChoosingAModel() async {
        let harness = LanguageModelHarness()
        await harness.manager.reconcile()

        #expect(throws: ModelManagementError.noModelSelected) { try harness.manager.acquireSelectedModel() }
    }

    @Test func recordingHoldsLanguageModelDownloadsBack() async {
        let harness = LanguageModelHarness()
        await harness.manager.reconcile()
        harness.manager.setRecordingActive(true)

        harness.manager.download("qwen3-1.7b-4bit")

        #expect(harness.manager.state(of: "qwen3-1.7b-4bit") == .waitingForRecording(nil))
    }
}
