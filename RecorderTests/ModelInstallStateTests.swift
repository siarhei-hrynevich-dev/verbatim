import Foundation
import Testing

@testable import Recorder

struct ModelInstallStateTests {
    @Test func installingCanOnlyFinishByVerifying() {
        let progress = ModelInstallState.downloading(nil)

        #expect(progress.allowsTransition(to: .verifying))
        #expect(!progress.allowsTransition(to: .installed(sizeBytes: 1)))
        #expect(!ModelInstallState.notInstalled.allowsTransition(to: .verifying))
    }

    @Test func busyStatesRejectAnotherDownload() {
        #expect(!ModelInstallState.downloading(nil).acceptsDownload)
        #expect(!ModelInstallState.waitingForRecording(nil).acceptsDownload)
        #expect(!ModelInstallState.verifying.acceptsDownload)
        #expect(!ModelInstallState.removing.acceptsDownload)
        #expect(!ModelInstallState.installed(sizeBytes: 1).acceptsDownload)
        #expect(ModelInstallState.notInstalled.acceptsDownload)
        #expect(ModelInstallState.failed(.noNetwork).acceptsDownload)
    }

    @Test func progressIsClampedAndSafeWithoutATotal() {
        #expect(ModelDownloadProgress(completedBytes: 5, totalBytes: 0).fraction == 0)
        #expect(ModelDownloadProgress(completedBytes: 20, totalBytes: 10).fraction == 1)
        #expect(ModelDownloadProgress(completedBytes: 5, totalBytes: 10).fraction == 0.5)
    }

    @Test func requiredSpaceCountsOnlyWhatIsMissingPlusAMargin() {
        let artifact = ModelArtifact(files: [.init(path: "a", sizeBytes: 1_000_000_000, sha256: nil)])

        #expect(artifact.requiredFreeBytes(alreadyDownloaded: 0) == 1_500_000_000)
        #expect(artifact.requiredFreeBytes(alreadyDownloaded: 400_000_000) == 1_100_000_000)
        #expect(artifact.requiredFreeBytes(alreadyDownloaded: 2_000_000_000) == 500_000_000)
    }

    @Test func recommendationPrefersTurboThenSmallThenAnythingSupported() {
        let catalog = SpeechModelCatalog.curated
        let turbo = "openai_whisper-large-v3-v20240930_turbo"
        let small = "openai_whisper-small"
        let tiny = "openai_whisper-tiny"

        #expect(SpeechModelCatalog.recommended(from: catalog, supportedIDs: Set(catalog.map(\.id)))?.id == turbo)
        #expect(SpeechModelCatalog.recommended(from: catalog, supportedIDs: [small, tiny])?.id == small)
        #expect(SpeechModelCatalog.recommended(from: catalog, supportedIDs: [tiny])?.id == tiny)
        #expect(SpeechModelCatalog.recommended(from: catalog, supportedIDs: []) == nil)
    }
}
