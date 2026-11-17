import Foundation

/// Model files from the Hugging Face Hub, at the commit each catalog entry pins: language models, and embedding models
/// alike. The app downloads them itself rather than through the MLX library, so a download happens only when the user
/// asks, pauses for recordings, is verified against the repository's hashes, and loading later finds everything on disk
/// without the network.
struct HubModelProvider<Model: HubHostedModel>: ModelFileProviding {
    let storageLocation: URL

    private let catalog: [Model]
    private let files: HubModelFileStore<Model>
    private let manifests: HubModelManifestClient
    private let downloader: HubFileDownloader
    private let physicalMemoryBytes: UInt64

    init(
        catalog: [Model],
        storageLocation: URL,
        endpoint: String = HubEndpoint.default,
        physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) {
        self.catalog = catalog
        self.storageLocation = storageLocation
        self.physicalMemoryBytes = physicalMemoryBytes
        files = HubModelFileStore(root: storageLocation)
        manifests = HubModelManifestClient(endpoint: endpoint)
        downloader = HubFileDownloader(endpoint: endpoint)
    }

    /// What fits this Mac's memory. Every catalog model runs on Apple Silicon otherwise.
    func supportedModelIDs() -> Set<Model.ID> {
        Set(catalog.filter { $0.minimumMemoryBytes <= physicalMemoryBytes }.map(\.id))
    }

    func fetchSupportedModelIDs() async -> Set<Model.ID> {
        supportedModelIDs()
    }

    func fetchArtifact(of model: Model) async throws -> ModelArtifact {
        try await manifests.artifact(
            ofRepository: model.repository,
            revision: model.revision,
            into: model.id,
            isIncluded: HubModelFiles.isNeeded
        )
    }

    func availableCapacity() async throws -> Int64 {
        try ModelFileStore(root: storageLocation, repository: "").availableCapacity()
    }

    /// One file at a time, measured on disk four times a second. Complete files are kept and partial ones continue.
    func download(
        _ model: Model,
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
        _ model: Model,
        against artifact: ModelArtifact,
        depth: ModelVerificationDepth
    ) async throws -> Int64 {
        try files.verify(model, against: artifact, depth: depth)
    }

    func inspect(_ model: Model) async -> ModelDiskInspection {
        files.inspect(model)
    }

    /// Hub models share no files.
    func removeFiles(of model: Model, includingSharedFiles: Bool) async throws {
        try files.removeFiles(of: model)
    }

    func resolve(_ model: Model) -> Model.Resolved {
        files.resolve(model)
    }

    func diskUsage() async -> Int64 {
        files.totalUsedBytes()
    }

    private static var progressInterval: Duration {
        .milliseconds(250)
    }
}

typealias HubLanguageModelProvider = HubModelProvider<LanguageModel>
typealias HubEmbeddingModelProvider = HubModelProvider<EmbeddingModel>

enum HubEndpoint {
    static let `default` = "https://huggingface.co"
}

extension HubModelProvider where Model == LanguageModel {
    init(
        storageLocation: URL,
        endpoint: String = HubEndpoint.default,
        physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) {
        self.init(
            catalog: LanguageModelCatalog.curated,
            storageLocation: storageLocation,
            endpoint: endpoint,
            physicalMemoryBytes: physicalMemoryBytes
        )
    }

    /// Application Support, inside the container when sandboxed, beside the speech models but in a folder of its own.
    static func defaultStorageLocation() -> URL {
        URL.applicationSupportDirectory.appending(path: "Verbatim/LanguageModels", directoryHint: .isDirectory)
    }
}

extension HubModelProvider where Model == EmbeddingModel {
    init(storageLocation: URL, endpoint: String = HubEndpoint.default) {
        self.init(catalog: EmbeddingModelCatalog.curated, storageLocation: storageLocation, endpoint: endpoint)
    }

    static func defaultStorageLocation() -> URL {
        URL.applicationSupportDirectory.appending(path: "Verbatim/EmbeddingModels", directoryHint: .isDirectory)
    }
}
