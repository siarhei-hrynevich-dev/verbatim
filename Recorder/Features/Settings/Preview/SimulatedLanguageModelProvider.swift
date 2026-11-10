import Foundation
import Synchronization

/// Pretends to download and verify language models, for reviewing the Settings design. Sizes are the repositories'
/// real ones, rounded. Nothing touches the network or the disk.
struct SimulatedLanguageModelProvider: ModelFileProviding {
    static let sampleInstalledID = "qwen3-4b-instruct-2507-4bit"
    static let sampleSizes: [LanguageModel.ID: Int64] = [
        "qwen3-1.7b-4bit": 980_000_000,
        "qwen3-4b-instruct-2507-4bit": 2_280_000_000,
        "qwen3-30b-a3b-instruct-2507-4bit": 17_200_000_000
    ]

    let installedIDs: [LanguageModel.ID]
    let storageLocation = URL(filePath: "/tmp/verbatim-settings-preview", directoryHint: .isDirectory)

    func supportedModelIDs() -> Set<LanguageModel.ID> {
        Set(LanguageModelCatalog.curated.map(\.id))
    }

    func fetchSupportedModelIDs() async -> Set<LanguageModel.ID> {
        supportedModelIDs()
    }

    func fetchArtifact(of model: LanguageModel) async throws -> ModelArtifact {
        ModelArtifact(
            files: [ModelArtifact.File(path: model.id, sizeBytes: Self.sampleSizes[model.id] ?? 0, sha256: nil)]
        )
    }

    func availableCapacity() async throws -> Int64 {
        214_000_000_000
    }

    func download(
        _ model: LanguageModel,
        artifact: ModelArtifact,
        onProgress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        let steps: Int64 = 150
        for step in 0...steps {
            try await Task.sleep(for: .milliseconds(200))
            onProgress(
                ModelDownloadProgress(
                    completedBytes: artifact.totalBytes * step / steps,
                    totalBytes: artifact.totalBytes
                )
            )
        }
    }

    func verify(
        _ model: LanguageModel,
        against artifact: ModelArtifact,
        depth: ModelVerificationDepth
    ) async throws -> Int64 {
        artifact.totalBytes
    }

    func inspect(_ model: LanguageModel) async -> ModelDiskInspection {
        let isInstalled = installedIDs.contains(model.id)
        return ModelDiskInspection(hasFiles: isInstalled, bytes: isInstalled ? Self.sampleSizes[model.id] ?? 0 : 0)
    }

    func removeFiles(of model: LanguageModel, includingSharedFiles: Bool) async throws {}

    func resolve(_ model: LanguageModel) -> ResolvedLanguageModel {
        ResolvedLanguageModel(id: model.id, folder: storageLocation, disablesThinking: model.disablesThinking)
    }

    func diskUsage() async -> Int64 {
        installedIDs.reduce(0) { $0 + (Self.sampleSizes[$1] ?? 0) }
    }
}

/// Summary settings kept in memory for design review, leaving the real ones untouched.
final class PreviewSummarySettingsRepository: SummarySettingsRepository {
    private let selectedModelID: Mutex<String?>
    private let customSettings = Mutex<[LanguageModel.ID: SummarySettings]>([:])
    private let languageCode = Mutex<String?>(nil)

    init(selectedModelID: String?) {
        self.selectedModelID = Mutex(selectedModelID)
    }

    func loadSelectedModelID() -> String? {
        selectedModelID.withLock { $0 }
    }

    func saveSelectedModelID(_ id: String?) {
        selectedModelID.withLock { $0 = id }
    }

    func loadLanguageCode() -> String? {
        languageCode.withLock { $0 }
    }

    func saveLanguageCode(_ code: String) {
        languageCode.withLock { $0 = code }
    }

    func loadCustomSettings() -> [LanguageModel.ID: SummarySettings] {
        customSettings.withLock { $0 }
    }

    func saveCustomSettings(_ settings: [LanguageModel.ID: SummarySettings]) {
        customSettings.withLock { $0 = settings }
    }
}
