import Foundation

/// Language model files from the Hugging Face Hub, at the commit each catalog entry pins. The app downloads them itself
/// rather than through the MLX library, so a download happens only when the user asks, pauses for recordings, is
/// verified against the repository's hashes, and loading later finds everything on disk without the network.
struct HubLanguageModelProvider: ModelFileProviding {
    let storageLocation: URL

    private let files: LanguageModelFileStore
    private let manifests: HubModelManifestClient
    private let downloader: HubFileDownloader
    private let physicalMemoryBytes: UInt64

    init(
        storageLocation: URL,
        endpoint: String = HubLanguageModelProvider.defaultEndpoint,
        physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) {
        self.storageLocation = storageLocation
        self.physicalMemoryBytes = physicalMemoryBytes
        files = LanguageModelFileStore(root: storageLocation)
        manifests = HubModelManifestClient(endpoint: endpoint)
        downloader = HubFileDownloader(endpoint: endpoint)
    }

    /// Application Support, inside the container when sandboxed, beside the speech models but in a folder of its own.
    static func defaultStorageLocation() -> URL {
        URL.applicationSupportDirectory.appending(path: "Verbatim/LanguageModels", directoryHint: .isDirectory)
    }

    static let defaultEndpoint = "https://huggingface.co"

    /// What fits this Mac's memory. Every catalog model runs on Apple Silicon otherwise.
    func supportedModelIDs() -> Set<LanguageModel.ID> {
        Set(LanguageModelCatalog.curated.filter { $0.minimumMemoryBytes <= physicalMemoryBytes }.map(\.id))
    }

    func fetchSupportedModelIDs() async -> Set<LanguageModel.ID> {
        supportedModelIDs()
    }

    func fetchArtifact(of model: LanguageModel) async throws -> ModelArtifact {
        try await manifests.artifact(
            ofRepository: model.repository,
            revision: model.revision,
            into: model.id,
            isIncluded: LanguageModelFileStore.isNeeded
        )
    }

    func availableCapacity() async throws -> Int64 {
        try ModelFileStore(root: storageLocation, repository: "").availableCapacity()
    }

    /// One file at a time, measured on disk four times a second. Complete files are kept and partial ones continue.
    func download(
        _ model: LanguageModel,
        artifact: ModelArtifact,
        onProgress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        try files.prepareStorage(for: model)
        let measuring = Task { [files] in
            while !Task.isCancelled {
                let completedBytes = files.inspect(model).bytes
                onProgress(ModelDownloadProgress(completedBytes: completedBytes, totalBytes: artifact.totalBytes))
                try? await Task.sleep(for: Self.progressInterval)
            }
        }
        defer { measuring.cancel() }
        for file in artifact.files {
            try Task.checkCancellation()
            let destination = try files.file(atRelativePath: file.path, of: model)
            do {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            } catch {
                throw ModelErrorTranslator.translate(error)
            }
            try await downloader.download(
                String(file.path.dropFirst(model.id.count + 1)),
                of: model.repository,
                revision: model.revision,
                to: destination,
                expectedBytes: file.sizeBytes
            )
        }
    }

    func verify(
        _ model: LanguageModel,
        against artifact: ModelArtifact,
        depth: ModelVerificationDepth
    ) async throws -> Int64 {
        try files.verify(model, against: artifact, depth: depth)
    }

    func inspect(_ model: LanguageModel) async -> ModelDiskInspection {
        files.inspect(model)
    }

    /// Language models share no files.
    func removeFiles(of model: LanguageModel, includingSharedFiles: Bool) async throws {
        try files.removeFiles(of: model)
    }

    func resolve(_ model: LanguageModel) -> ResolvedLanguageModel {
        files.resolve(model)
    }

    func diskUsage() async -> Int64 {
        files.totalUsedBytes()
    }

    private static let progressInterval = Duration.milliseconds(250)
}
