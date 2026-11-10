import Foundation
import OSLog
import WhisperKit

/// The WhisperKit adapter for model files. It uses only WhisperKit's static model APIs and its Hub client: no
/// `WhisperKit` instance is ever created, so nothing is compiled or loaded into memory.
///
/// WhisperKit's downloader owns the layout inside the storage folder, and later loading finds files there without
/// copies. See `ModelFileStore`.
struct WhisperModelProvider: SpeechModelProviding {
    let storageLocation: URL

    private let files: ModelFileStore
    private let manifests: HubModelManifestClient

    init(storageLocation: URL) {
        self.storageLocation = storageLocation
        files = ModelFileStore(root: storageLocation, repository: Self.repository)
        manifests = HubModelManifestClient(repository: Self.repository, endpoint: Constants.defaultRemoteEndpoint)
    }

    /// Application Support, inside the container when sandboxed. Never the app bundle, and never the Documents folder
    /// WhisperKit would otherwise default to.
    static func defaultStorageLocation() -> URL {
        URL.applicationSupportDirectory.appending(path: "Verbatim/Models", directoryHint: .isDirectory)
    }

    func supportedModelIDs() -> Set<SpeechModel.ID> {
        Set(WhisperKit.recommendedModels().supported)
    }

    /// WhisperKit falls back to its built-in table when the repository cannot be reached.
    func fetchSupportedModelIDs() async -> Set<SpeechModel.ID> {
        do {
            return Set(try await WhisperKit.fetchAvailableModels(downloadBase: storageLocation))
        } catch {
            Self.logger.notice("Could not fetch available models: \(String(describing: error))")
            return supportedModelIDs()
        }
    }

    func fetchArtifact(of model: SpeechModel) async throws -> ModelArtifact {
        try await manifests.artifact(of: model)
    }

    func availableCapacity() async throws -> Int64 {
        try files.availableCapacity()
    }

    /// Already complete files are kept and partial ones continue where they stopped, which WhisperKit's downloader
    /// does by itself. Cancelling the calling task stops it and leaves partial files in place.
    func download(
        _ model: SpeechModel,
        artifact: ModelArtifact,
        onProgress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        try files.prepareStorage()
        let measuring = Task { [files] in
            while !Task.isCancelled {
                let completedBytes = files.downloadedBytes(of: model)
                onProgress(ModelDownloadProgress(completedBytes: completedBytes, totalBytes: artifact.totalBytes))
                try? await Task.sleep(for: Self.progressInterval)
            }
        }
        defer { measuring.cancel() }
        do {
            _ = try await WhisperKit.download(variant: model.id, downloadBase: storageLocation, from: Self.repository)
            try Task.checkCancellation()
            // Loading fetches a missing tokenizer from the network, so it has to be here for offline use.
            _ = try await HubApiWrapper(downloadBase: storageLocation).snapshot(
                from: HubApiWrapper.Repo(id: model.tokenizerRepository),
                matching: ModelFileStore.tokenizerFiles
            )
        } catch {
            throw ModelErrorTranslator.translate(error)
        }
    }

    func verify(
        _ model: SpeechModel,
        against artifact: ModelArtifact,
        depth: ModelVerificationDepth
    ) async throws -> Int64 {
        try files.verify(model, against: artifact, depth: depth)
    }

    func inspect(_ model: SpeechModel) async -> ModelDiskInspection {
        files.inspect(model)
    }

    func removeFiles(of model: SpeechModel, includingSharedFiles: Bool) async throws {
        try files.removeFiles(of: model, includingTokenizer: includingSharedFiles)
    }

    func resolve(_ model: SpeechModel) -> ResolvedSpeechModel {
        files.resolve(model)
    }

    func diskUsage() async -> Int64 {
        files.totalUsedBytes()
    }

    static let repository = "argmaxinc/whisperkit-coreml"
    private static let progressInterval = Duration.milliseconds(250)
    private static let logger = Logger(subsystem: "dev.local.Recorder", category: "Models")
}
