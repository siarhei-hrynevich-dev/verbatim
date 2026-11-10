import Foundation
import Synchronization

/// Pretends to download and verify Hub models, language or embedding, for reviewing the Settings design. Sizes are the
/// repositories' real ones, rounded. Nothing touches the network or the disk.
struct SimulatedHubModelProvider<Model: HubHostedModel>: ModelFileProviding {
    let catalog: [Model]
    let sizes: [Model.ID: Int64]
    let installedIDs: [Model.ID]
    let storageLocation = URL(filePath: "/tmp/verbatim-settings-preview", directoryHint: .isDirectory)

    func supportedModelIDs() -> Set<Model.ID> {
        Set(catalog.map(\.id))
    }

    func fetchSupportedModelIDs() async -> Set<Model.ID> {
        supportedModelIDs()
    }

    func fetchArtifact(of model: Model) async throws -> ModelArtifact {
        ModelArtifact(files: [ModelArtifact.File(path: model.id, sizeBytes: sizes[model.id] ?? 0, sha256: nil)])
    }

    func availableCapacity() async throws -> Int64 {
        214_000_000_000
    }

    func download(
        _ model: Model,
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

    func verify(_ model: Model, against artifact: ModelArtifact, depth: ModelVerificationDepth) async throws -> Int64 {
        artifact.totalBytes
    }

    func inspect(_ model: Model) async -> ModelDiskInspection {
        let isInstalled = installedIDs.contains(model.id)
        return ModelDiskInspection(hasFiles: isInstalled, bytes: isInstalled ? sizes[model.id] ?? 0 : 0)
    }

    func removeFiles(of model: Model, includingSharedFiles: Bool) async throws {}

    func resolve(_ model: Model) -> Model.Resolved {
        model.resolved(in: storageLocation)
    }

    func diskUsage() async -> Int64 {
        installedIDs.reduce(0) { $0 + (sizes[$1] ?? 0) }
    }
}

/// Sample figures for the simulated catalogs.
enum SimulatedHubModels {
    static let languageInstalledID = "qwen3-4b-instruct-2507-4bit"
    static let languageSizes: [LanguageModel.ID: Int64] = [
        "qwen3-1.7b-4bit": 980_000_000,
        "qwen3-4b-instruct-2507-4bit": 2_280_000_000,
        "qwen3-30b-a3b-instruct-2507-4bit": 17_200_000_000
    ]
    static let embeddingInstalledID = "multilingual-e5-small"
    static let embeddingSizes: [EmbeddingModel.ID: Int64] = [
        "multilingual-e5-small": 494_000_000,
        "multilingual-e5-base": 1_140_000_000
    ]
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
