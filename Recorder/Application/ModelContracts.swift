import Foundation

/// Speech model files and their source. Failures are `ModelManagementError`, or `CancellationError` once cancelled.
/// Nothing here loads a model into memory.
protocol SpeechModelProviding: Sendable {
    /// The folder that holds every model file, for showing it in Finder.
    var storageLocation: URL { get }

    /// What this Mac supports according to the table built into the model library. No network or disk access.
    func supportedModelIDs() -> Set<SpeechModel.ID>
    /// The same, updated from the repository when it can be reached.
    func fetchSupportedModelIDs() async -> Set<SpeechModel.ID>
    /// Asks the repository which files a model consists of.
    func fetchArtifact(of model: SpeechModel) async throws -> ModelArtifact
    func availableCapacity() async throws -> Int64

    /// Downloads whatever is still missing, along with the tokenizer needed to use the model offline. Finishing does
    /// not mean the result is usable; that is what `verify` is for.
    func download(
        _ model: SpeechModel,
        artifact: ModelArtifact,
        onProgress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws
    /// Compares the disk with an artifact, and returns the space the model occupies.
    func verify(
        _ model: SpeechModel,
        against artifact: ModelArtifact,
        depth: ModelVerificationDepth
    ) async throws -> Int64
    func inspect(_ model: SpeechModel) async -> ModelDiskInspection
    /// Removes a model's own files, complete or partial. A shared tokenizer stays unless asked for.
    func removeFiles(of model: SpeechModel, includingTokenizer: Bool) async throws
    func resolve(_ model: SpeechModel) -> ResolvedSpeechModel
    /// The total space used in the storage folder, in bytes.
    func diskUsage() async -> Int64
}

/// Keeps the model registry across launches. A missing registry is an empty one.
protocol ModelRegistryStore: Sendable {
    func load() async throws -> ModelRegistry
    func save(_ registry: ModelRegistry) async throws
}

/// Persists user choices made in Settings.
protocol SettingsRepository: Sendable {
    func loadSettings() -> AppSettings
    func saveSettings(_ settings: AppSettings)
    func loadSelectedModelID() -> SpeechModel.ID?
    func saveSelectedModelID(_ id: SpeechModel.ID?)
}

/// Whether the app opens at login.
protocol LoginItemControlling: Sendable {
    func status() -> LoginItemStatus
    func setEnabled(_ isEnabled: Bool) throws
}

/// The recordings folder and what is in it.
struct RecordingsStorage: Equatable, Sendable {
    let location: RecordingLocation
    let recordingCount: Int
    let usedBytes: Int64
}

protocol RecordingsStorageProviding: Sendable {
    func recordingsStorage() async throws -> RecordingsStorage
}
