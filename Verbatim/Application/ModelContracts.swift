import Foundation

/// One kind of model's files and their source. Failures are `ModelManagementError`, or `CancellationError` once
/// cancelled. Nothing here loads a model into memory.
protocol ModelFileProviding<Model>: Sendable {
    associatedtype Model: InstallableModel

    /// The folder that holds every model file of this kind, for showing it in Finder.
    var storageLocation: URL { get }

    /// What this Mac supports, without network or disk access.
    func supportedModelIDs() -> Set<Model.ID>
    /// The same, updated from the repository when it can be reached.
    func fetchSupportedModelIDs() async -> Set<Model.ID>
    /// Asks the repository which files a model consists of.
    func fetchArtifact(of model: Model) async throws -> ModelArtifact
    func availableCapacity() async throws -> Int64

    /// Downloads whatever is still missing, along with anything else needed to use the model offline. Finishing does
    /// not mean the result is usable; that is what `verify` is for.
    func download(
        _ model: Model,
        artifact: ModelArtifact,
        onProgress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws
    /// Compares the disk with an artifact, and returns the space the model occupies.
    func verify(_ model: Model, against artifact: ModelArtifact, depth: ModelVerificationDepth) async throws -> Int64
    func inspect(_ model: Model) async -> ModelDiskInspection
    /// Removes a model's own files, complete or partial. Files shared with other models stay unless asked for.
    func removeFiles(of model: Model, includingSharedFiles: Bool) async throws
    func resolve(_ model: Model) -> Model.Resolved
    /// The total space used in the storage folder, in bytes.
    func diskUsage() async -> Int64
}

/// Speech model files: WhisperKit's repository and layout, implemented by `WhisperModelProvider`.
protocol SpeechModelProviding: ModelFileProviding where Model == SpeechModel {}

/// Keeps the model registry across launches. A missing registry is an empty one.
protocol ModelRegistryStore: Sendable {
    func load() async throws -> ModelRegistry
    func save(_ registry: ModelRegistry) async throws
}

/// Remembers which model of one kind is selected.
protocol ModelSelectionStore: Sendable {
    func loadSelectedModelID() -> String?
    func saveSelectedModelID(_ id: String?)
}

/// Persists user choices made in Settings, and the selected speech model.
protocol SettingsRepository: ModelSelectionStore {
    func loadSettings() -> AppSettings
    func saveSettings(_ settings: AppSettings)
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
