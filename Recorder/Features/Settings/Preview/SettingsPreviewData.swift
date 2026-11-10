import Foundation
import Synchronization

/// Sample dependencies for reviewing the Settings design: the real view models and `ModelManager` running on simulated
/// downloads and fixed figures. Nothing here touches the network, the disk, login items or saved preferences.
@MainActor
extension SettingsViewModel.Dependencies {
    static func preview(for scenario: SettingsPreviewScenario) -> Self {
        let installedIDs = scenario == .noModels ? [] : SimulatedModelProvider.sampleInstalledIDs
        let repository = PreviewSettingsRepository(selectedModelID: installedIDs.last)
        let modelManager = ModelManager(
            provider: SimulatedModelProvider(installedIDs: installedIDs),
            registryStore: PreviewModelRegistryStore(installedIDs: installedIDs),
            settings: repository
        )
        if scenario == .models {
            modelManager.download("openai_whisper-small")
        }
        let languageInstalledIDs = scenario == .noModels ? [] : [SimulatedHubModels.languageInstalledID]
        let summarySettings = PreviewSummarySettingsRepository(selectedModelID: languageInstalledIDs.last)
        let languageModelManager = LanguageModelManager(
            catalog: LanguageModelCatalog.curated,
            provider: SimulatedHubModelProvider(
                catalog: LanguageModelCatalog.curated,
                sizes: SimulatedHubModels.languageSizes,
                installedIDs: languageInstalledIDs
            ),
            registryStore: PreviewModelRegistryStore(
                installations: languageInstalledIDs,
                sizes: SimulatedHubModels.languageSizes
            ),
            selection: summarySettings
        )
        return Self(
            preferences: AppPreferences(repository: repository),
            loginItem: PreviewLoginItem(),
            recordingsStorage: PreviewRecordingsStorage(),
            systemActions: PreviewSystemActions(),
            modelManager: modelManager,
            languageModelManager: languageModelManager,
            embeddingModelManager: previewEmbeddingModels(for: scenario),
            summaryPreferences: SummaryPreferences(repository: summarySettings),
            metadata: AppMetadata(version: "1.2.0", build: "142"),
            chooseRecordingsFolder: { _ in }
        )
    }

    private static func previewEmbeddingModels(for scenario: SettingsPreviewScenario) -> EmbeddingModelManager {
        let installedIDs = scenario == .noModels ? [] : [SimulatedHubModels.embeddingInstalledID]
        return EmbeddingModelManager(
            catalog: EmbeddingModelCatalog.curated,
            provider: SimulatedHubModelProvider(
                catalog: EmbeddingModelCatalog.curated,
                sizes: SimulatedHubModels.embeddingSizes,
                installedIDs: installedIDs
            ),
            registryStore: PreviewModelRegistryStore(
                installations: installedIDs,
                sizes: SimulatedHubModels.embeddingSizes
            ),
            selection: PreviewSummarySettingsRepository(selectedModelID: installedIDs.last)
        )
    }
}

extension SettingsViewModel {
    /// For SwiftUI previews.
    static func preview(_ scenario: SettingsPreviewScenario) -> SettingsViewModel {
        SettingsViewModel(dependencies: .preview(for: .general), previewScenario: scenario)
    }
}

/// Pretends to download and verify. Sizes are the repository's real ones, rounded, so the layout sees realistic values.
private struct SimulatedModelProvider: SpeechModelProviding {
    static let sampleInstalledIDs = ["openai_whisper-base", "openai_whisper-large-v3-v20240930_turbo"]
    static let sampleSizes: [SpeechModel.ID: Int64] = [
        "openai_whisper-tiny": 79_000_000,
        "openai_whisper-base": 150_000_000,
        "openai_whisper-small": 490_000_000,
        "openai_whisper-large-v3-v20240930_turbo": 1_640_000_000
    ]

    let installedIDs: [SpeechModel.ID]
    let storageLocation = URL(filePath: "/tmp/verbatim-settings-preview", directoryHint: .isDirectory)

    func supportedModelIDs() -> Set<SpeechModel.ID> {
        Set(SpeechModelCatalog.curated.map(\.id))
    }

    func fetchSupportedModelIDs() async -> Set<SpeechModel.ID> {
        supportedModelIDs()
    }

    func fetchArtifact(of model: SpeechModel) async throws -> ModelArtifact {
        Self.artifact(of: model.id)
    }

    func availableCapacity() async throws -> Int64 {
        214_000_000_000
    }

    func download(
        _ model: SpeechModel,
        artifact: ModelArtifact,
        onProgress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        let steps: Int64 = 150
        for step in 0...steps {
            try await Task.sleep(for: .milliseconds(200))
            let completed = artifact.totalBytes * step / steps
            onProgress(ModelDownloadProgress(completedBytes: completed, totalBytes: artifact.totalBytes))
        }
    }

    func verify(
        _ model: SpeechModel,
        against artifact: ModelArtifact,
        depth: ModelVerificationDepth
    ) async throws -> Int64 {
        if depth == .full {
            try await Task.sleep(for: .seconds(2))
        }
        return artifact.totalBytes
    }

    func inspect(_ model: SpeechModel) async -> ModelDiskInspection {
        let isInstalled = installedIDs.contains(model.id)
        return ModelDiskInspection(hasFiles: isInstalled, bytes: isInstalled ? Self.sampleSizes[model.id] ?? 0 : 0)
    }

    func removeFiles(of model: SpeechModel, includingSharedFiles: Bool) async throws {}

    func resolve(_ model: SpeechModel) -> ResolvedSpeechModel {
        ResolvedSpeechModel(id: model.id, modelFolder: storageLocation, tokenizerBase: storageLocation)
    }

    func diskUsage() async -> Int64 {
        installedIDs.reduce(0) { $0 + (Self.sampleSizes[$1] ?? 0) }
    }

    static func artifact(of id: SpeechModel.ID) -> ModelArtifact {
        SimulatedArtifacts.artifact(of: id, sizes: sampleSizes)
    }
}

private final class PreviewModelRegistryStore: ModelRegistryStore {
    private let registry: ModelRegistry

    convenience init(installedIDs: [SpeechModel.ID]) {
        self.init(installations: installedIDs, sizes: SimulatedModelProvider.sampleSizes)
    }

    init(installations installedIDs: [String], sizes: [String: Int64]) {
        var registry = ModelRegistry(artifactSizes: sizes)
        for id in installedIDs {
            registry.installations[id] = ModelInstallation(
                installedAt: .distantPast,
                artifact: SimulatedArtifacts.artifact(of: id, sizes: sizes)
            )
        }
        self.registry = registry
    }

    func load() async throws -> ModelRegistry {
        registry
    }

    func save(_ registry: ModelRegistry) async throws {}
}

private final class PreviewSettingsRepository: SettingsRepository {
    private let selectedModelID: Mutex<SpeechModel.ID?>
    private let settings = Mutex(AppSettings())

    init(selectedModelID: SpeechModel.ID?) {
        self.selectedModelID = Mutex(selectedModelID)
    }

    func loadSettings() -> AppSettings {
        settings.withLock { $0 }
    }

    func saveSettings(_ settings: AppSettings) {
        self.settings.withLock { $0 = settings }
    }

    func loadSelectedModelID() -> SpeechModel.ID? {
        selectedModelID.withLock { $0 }
    }

    func saveSelectedModelID(_ id: SpeechModel.ID?) {
        selectedModelID.withLock { $0 = id }
    }
}

private final class PreviewLoginItem: LoginItemControlling {
    private let current = Mutex(LoginItemStatus.enabled)

    func status() -> LoginItemStatus {
        current.withLock { $0 }
    }

    func setEnabled(_ isEnabled: Bool) throws {
        current.withLock { $0 = isEnabled ? .enabled : .disabled }
    }
}

private struct PreviewRecordingsStorage: RecordingsStorageProviding {
    func recordingsStorage() async throws -> RecordingsStorage {
        RecordingsStorage(
            location: RecordingLocation(
                url: URL(filePath: "/tmp/verbatim-settings-preview", directoryHint: .isDirectory),
                displayPath: "~/Movies/Verbatim",
                availableBytes: 214_000_000_000,
                isAccessible: true
            ),
            recordingCount: 48,
            usedBytes: 38_200_000_000
        )
    }
}

private struct PreviewSystemActions: SystemActions {
    func open(_ pane: SystemSettingsPane) async {}
    func openInFinder(_ url: URL) async {}
    func revealInFinder(_ url: URL) async {}
    func openFile(_ url: URL) async -> Bool { false }
}

private enum SimulatedArtifacts {
    static func artifact(of id: String, sizes: [String: Int64]) -> ModelArtifact {
        ModelArtifact(files: [ModelArtifact.File(path: "sample/\(id)", sizeBytes: sizes[id] ?? 0, sha256: nil)])
    }
}
