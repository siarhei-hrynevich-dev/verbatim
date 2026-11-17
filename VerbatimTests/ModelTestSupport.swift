import Foundation
import Synchronization

@testable import Verbatim

/// A controllable stand-in for WhisperKit and the disk. Downloads wait at a gate when asked to, so tests can observe
/// the states in between and request things during them.
final class FakeModelProvider: SpeechModelProviding {
    struct State {
        var supportedIDs: Set<SpeechModel.ID>
        var artifactError: ModelManagementError?
        var downloadError: (any Error)?
        var verifyErrors: [ModelVerificationDepth: ModelManagementError] = [:]
        var removeError: ModelManagementError?
        var availableBytes: Int64 = 1_000_000_000_000
        var filesOnDisk: Set<SpeechModel.ID> = []
        var partialBytes: [SpeechModel.ID: Int64] = [:]
        var holdsDownloads = false
        var gates: [SpeechModel.ID: AsyncStream<Void>.Continuation] = [:]
        var downloadCalls: [SpeechModel.ID] = []
        var verifyCalls: [(id: SpeechModel.ID, depth: ModelVerificationDepth)] = []
        var removals: [(id: SpeechModel.ID, includingTokenizer: Bool)] = []
        var catalogFetchCount = 0
    }

    let storageLocation = URL(filePath: "/models", directoryHint: .isDirectory)
    let state: Mutex<State>

    init(supportedIDs: Set<SpeechModel.ID> = Set(ModelFixtures.catalog.map(\.id))) {
        state = Mutex(State(supportedIDs: supportedIDs))
    }

    func update(_ change: (inout State) -> Void) {
        state.withLock { change(&$0) }
    }

    func read<Value: Sendable>(_ value: (State) -> Value) -> Value {
        state.withLock { value($0) }
    }

    /// Lets a held download finish.
    func releaseDownload(of id: SpeechModel.ID) {
        state.withLock { $0.gates.removeValue(forKey: id) }?.finish()
    }

    func supportedModelIDs() -> Set<SpeechModel.ID> {
        read(\.supportedIDs)
    }

    func fetchSupportedModelIDs() async -> Set<SpeechModel.ID> {
        update { $0.catalogFetchCount += 1 }
        return read(\.supportedIDs)
    }

    func fetchArtifact(of model: SpeechModel) async throws -> ModelArtifact {
        if let error = read(\.artifactError) {
            throw error
        }
        return ModelFixtures.artifact
    }

    func availableCapacity() async throws -> Int64 {
        read(\.availableBytes)
    }

    func download(
        _ model: SpeechModel,
        artifact: ModelArtifact,
        onProgress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        update {
            $0.downloadCalls.append(model.id)
            $0.partialBytes[model.id, default: 0] += 1
        }
        onProgress(ModelDownloadProgress(completedBytes: artifact.totalBytes / 2, totalBytes: artifact.totalBytes))
        if read(\.holdsDownloads) {
            let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
            update { $0.gates[model.id] = continuation }
            for await _ in stream {}
            try Task.checkCancellation()
        }
        if let error = state.withLock({ $0.downloadError }) {
            throw error
        }
        update { $0.filesOnDisk.insert(model.id) }
    }

    func verify(
        _ model: SpeechModel,
        against artifact: ModelArtifact,
        depth: ModelVerificationDepth
    ) async throws -> Int64 {
        try Task.checkCancellation()
        update { $0.verifyCalls.append((model.id, depth)) }
        if let error = read({ $0.verifyErrors[depth] }) {
            throw error
        }
        guard read({ $0.filesOnDisk.contains(model.id) }) else {
            throw ModelManagementError.verificationFailed(detail: "missing")
        }
        return artifact.totalBytes
    }

    func inspect(_ model: SpeechModel) async -> ModelDiskInspection {
        let partial = read { $0.partialBytes[model.id] ?? 0 }
        return ModelDiskInspection(
            hasFiles: read { $0.filesOnDisk.contains(model.id) } || partial > 0,
            bytes: partial
        )
    }

    func removeFiles(of model: SpeechModel, includingSharedFiles: Bool) async throws {
        update { $0.removals.append((model.id, includingSharedFiles)) }
        if let error = read(\.removeError) {
            throw error
        }
        update {
            $0.filesOnDisk.remove(model.id)
            $0.partialBytes[model.id] = nil
        }
    }

    func resolve(_ model: SpeechModel) -> ResolvedSpeechModel {
        ResolvedSpeechModel(
            id: model.id,
            modelFolder: storageLocation.appending(path: model.id),
            tokenizerBase: storageLocation
        )
    }

    func diskUsage() async -> Int64 {
        read { Int64($0.filesOnDisk.count) } * ModelFixtures.artifact.totalBytes
    }
}

actor InMemoryModelRegistryStore: ModelRegistryStore {
    private(set) var registry: ModelRegistry
    private var loadError: ModelManagementError?
    private var saveError: ModelManagementError?

    init(registry: ModelRegistry = ModelRegistry()) {
        self.registry = registry
    }

    func failLoading(with error: ModelManagementError?) {
        loadError = error
    }

    func failSaving(with error: ModelManagementError?) {
        saveError = error
    }

    func load() throws -> ModelRegistry {
        if let loadError {
            throw loadError
        }
        return registry
    }

    func save(_ registry: ModelRegistry) throws {
        if let saveError {
            throw saveError
        }
        self.registry = registry
    }
}

final class InMemorySettingsRepository: SettingsRepository {
    private let settings = Mutex(AppSettings())
    private let selectedModelID: Mutex<SpeechModel.ID?>

    init(selectedModelID: SpeechModel.ID? = nil) {
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

enum ModelFixtures {
    static let tiny = SpeechModel(
        id: "tiny-model",
        name: "Tiny",
        summary: "Small.",
        languageSupport: "Multilingual",
        tokenizerRepository: "openai/whisper-tiny"
    )
    static let large = SpeechModel(
        id: "large-model",
        name: "Large",
        summary: "Big.",
        languageSupport: "Multilingual",
        tokenizerRepository: "openai/whisper-large"
    )
    /// Shares a tokenizer with `large`, as Large v3 and its Turbo variant do.
    static let largeTurbo = SpeechModel(
        id: "large-turbo-model",
        name: "Large Turbo",
        summary: "Big and quick.",
        languageSupport: "Multilingual",
        tokenizerRepository: "openai/whisper-large"
    )
    static let catalog = [tiny, large, largeTurbo]

    static let artifact = ModelArtifact(
        files: [ModelArtifact.File(path: "models/file.bin", sizeBytes: 1_000_000, sha256: nil)]
    )

    static func installation() -> ModelInstallation {
        ModelInstallation(installedAt: Date(timeIntervalSince1970: 1_000), artifact: artifact)
    }
}

/// Everything a `ModelManager` needs, kept together so a test can look behind it, or start a "new launch" on the same
/// provider and stores.
@MainActor
struct ModelManagerHarness {
    let provider: FakeModelProvider
    let registryStore: InMemoryModelRegistryStore
    let settings: InMemorySettingsRepository
    let manager: SpeechModelManager

    init(
        provider: FakeModelProvider = FakeModelProvider(),
        registryStore: InMemoryModelRegistryStore = InMemoryModelRegistryStore(),
        settings: InMemorySettingsRepository = InMemorySettingsRepository()
    ) {
        self.provider = provider
        self.registryStore = registryStore
        self.settings = settings
        manager = ModelManager(
            catalog: ModelFixtures.catalog,
            provider: provider,
            registryStore: registryStore,
            settings: settings,
            now: { Date(timeIntervalSince1970: 2_000) }
        )
    }

    /// A restart: state is rebuilt from the same disk and stores.
    func relaunched() async -> ModelManagerHarness {
        let next = ModelManagerHarness(provider: provider, registryStore: registryStore, settings: settings)
        await next.manager.reconcile()
        return next
    }

    /// Waits for a model to settle in a state, failing rather than hanging if it never does.
    func waitForState(
        of id: SpeechModel.ID,
        until condition: (ModelInstallState) -> Bool
    ) async throws {
        for _ in 0..<2_000 {
            if condition(manager.state(of: id)) {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw ModelTestTimeout(state: manager.state(of: id))
    }

    /// Installs a model through the real flow and waits for it.
    func install(_ id: SpeechModel.ID) async throws {
        manager.download(id)
        try await waitForState(of: id) { $0.isInstalled }
        try await waitForFile { $0.filesOnDisk.contains(id) }
    }

    /// Waits until the fake's download for a model is held at its gate.
    func waitForGate(of id: SpeechModel.ID) async throws {
        try await waitForFile { $0.gates[id] != nil }
    }

    func waitForFile(_ condition: (FakeModelProvider.State) -> Bool) async throws {
        for _ in 0..<2_000 {
            if provider.state.withLock({ condition($0) }) {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw ModelTestTimeout(state: nil)
    }
}

struct ModelTestTimeout: Error {
    let state: ModelInstallState?
}
