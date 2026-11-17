import Foundation

/// Asks the Hugging Face Hub which files make up a model. WhisperKit's public API exposes names but not sizes or
/// hashes, and those are what make the disk space check, byte-accurate progress and verification possible. Language
/// models use the same listing, at a pinned commit.
struct HubModelManifestClient: Sendable {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let repository: String
    let endpoint: String
    private let fetch: Fetch

    init(
        repository: String = "",
        endpoint: String,
        fetch: @escaping Fetch = HubModelManifestClient.fetchOverNetwork
    ) {
        self.repository = repository
        self.endpoint = endpoint
        self.fetch = fetch
    }

    /// The model's own files plus its tokenizer's, with paths relative to the storage folder.
    func artifact(of model: SpeechModel) async throws -> ModelArtifact {
        let modelEntries = try await entries(in: repository, folder: model.id).filter {
            $0.path.hasPrefix("\(model.id)/")
        }
        guard !modelEntries.isEmpty else {
            throw ModelManagementError.modelUnavailable
        }
        let tokenizerEntries = try await entries(in: model.tokenizerRepository, folder: nil).filter {
            ModelFileStore.tokenizerFiles.contains($0.path)
        }
        return ModelArtifact(
            files: Self.files(from: modelEntries, repository: repository)
                + Self.files(from: tokenizerEntries, repository: model.tokenizerRepository)
        )
    }

    /// The files of a whole repository at a commit that `isIncluded` accepts, with paths under `folder` in the storage
    /// folder.
    func artifact(
        ofRepository repository: String,
        revision: String,
        into folder: String,
        isIncluded: (String) -> Bool
    ) async throws -> ModelArtifact {
        let entries = try await entries(in: repository, folder: nil, revision: revision).filter { isIncluded($0.path) }
        guard !entries.isEmpty else {
            throw ModelManagementError.modelUnavailable
        }
        return ModelArtifact(
            files: entries.map { entry in
                ModelArtifact.File(path: "\(folder)/\(entry.path)", sizeBytes: entry.size, sha256: entry.lfs?.oid)
            }
        )
    }

    private func entries(
        in repository: String,
        folder: String?,
        revision: String = "main"
    ) async throws -> [HubTreeEntry] {
        guard var url = URL(string: endpoint) else {
            throw ModelManagementError.downloadFailed(detail: "Invalid repository address: \(endpoint)")
        }
        url.append(path: "api/models/\(repository)/tree/\(revision)", directoryHint: .notDirectory)
        if let folder {
            url.append(component: folder, directoryHint: .notDirectory)
        }
        url.append(queryItems: [URLQueryItem(name: "recursive", value: "true")])
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.timeoutSeconds
        do {
            let (data, response) = try await fetch(request)
            try Self.validate(response)
            return try JSONDecoder().decode([HubTreeEntry].self, from: data).filter { $0.type == "file" }
        } catch let error as DecodingError {
            throw ModelManagementError.downloadFailed(detail: "Unexpected repository listing: \(error)")
        } catch {
            throw ModelErrorTranslator.translate(error)
        }
    }

    private static func validate(_ response: URLResponse) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) else {
            return
        }
        if status == 404 {
            throw ModelManagementError.modelUnavailable
        }
        throw ModelManagementError.downloadFailed(detail: "The repository answered with HTTP \(status)")
    }

    private static func files(from entries: [HubTreeEntry], repository: String) -> [ModelArtifact.File] {
        entries.map { entry in
            ModelArtifact.File(
                path: "models/\(repository)/\(entry.path)",
                sizeBytes: entry.size,
                sha256: entry.lfs?.oid
            )
        }
    }

    @Sendable
    static func fetchOverNetwork(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }

    /// Ephemeral: these listings are small, and must be current rather than cached.
    private static let session = URLSession(configuration: .ephemeral)

    private static let timeoutSeconds: TimeInterval = 15
}

/// One item of the Hub's repository listing. `lfs` is present for large files, and its `oid` is their SHA-256.
private struct HubTreeEntry: Decodable {
    struct LargeFile: Decodable {
        let oid: String
    }

    let type: String
    let path: String
    let size: Int64
    let lfs: LargeFile?
}
