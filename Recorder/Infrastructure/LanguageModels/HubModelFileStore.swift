import CryptoKit
import Foundation

/// The storage folder of one kind of Hugging Face model, language or embedding, which this app owns entirely:
///
///     <root>/model-registry.json            what was installed
///     <root>/<model id>/…                    a model's files, as its repository has them
///     <root>/<model id>/….incomplete         a file still downloading, continued from its length
///
/// A model's folder is derived from its validated catalog identifier, and paths from a repository listing must stay
/// inside it. Nothing outside a model's own folder is ever removed.
struct HubModelFileStore<Model: HubHostedModel>: Sendable {
    let root: URL

    // MARK: - Layout

    func folder(of model: Model) throws -> URL {
        guard ModelFileStore.isSafeIdentifier(model.id) else {
            throw ModelManagementError.modelUnavailable
        }
        return root.appending(path: model.id, directoryHint: .isDirectory)
    }

    /// A listed path is untrusted text: it must name a file inside the model's folder.
    func file(atRelativePath path: String, of model: Model) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count >= 2, components[0] == model.id,
            !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
        else {
            throw ModelManagementError.verificationFailed(detail: "Unsafe path in the model manifest")
        }
        return try folder(of: model).appending(path: components.dropFirst().joined(separator: "/"))
    }

    // MARK: - Preparing

    /// Creates the folder, and keeps downloadable weights out of backups.
    func prepareStorage(for model: Model) throws {
        do {
            try FileManager.default.createDirectory(at: try folder(of: model), withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var folder = root
            try folder.setResourceValues(values)
        } catch {
            throw ModelErrorTranslator.translate(error)
        }
    }

    // MARK: - Verifying

    /// Checks every expected file, and that a model can be loaded from them. Returns the space the model occupies.
    func verify(
        _ model: Model,
        against artifact: ModelArtifact,
        depth: ModelVerificationDepth
    ) throws -> Int64 {
        try verifyLayout(of: model, in: artifact)
        for expected in artifact.files {
            try Task.checkCancellation()
            let url = try file(atRelativePath: expected.path, of: model)
            try verifySize(of: url, expected: expected)
            if depth == .full, let sha256 = expected.sha256 {
                try verifyHash(of: url, expected: sha256)
            }
        }
        return Self.contentSize(of: try folder(of: model)).allocatedBytes
    }

    private func verifyLayout(of model: Model, in artifact: ModelArtifact) throws {
        let names = Set(artifact.files.map { ($0.path as NSString).lastPathComponent })
        for required in HubModelFiles.requiredFiles where !names.contains(required) {
            throw ModelManagementError.verificationFailed(detail: "\(required) is missing from the model")
        }
        guard names.contains(where: { $0.hasSuffix(".safetensors") }) else {
            throw ModelManagementError.verificationFailed(detail: "The model has no weights")
        }
    }

    private func verifySize(of url: URL, expected: ModelArtifact.File) throws {
        let actual: Int64
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
            actual = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        } catch CocoaError.fileReadNoSuchFile {
            throw ModelManagementError.verificationFailed(detail: "\(expected.path) is missing")
        } catch {
            throw ModelErrorTranslator.translate(error)
        }
        guard actual == expected.sizeBytes else {
            throw ModelManagementError.verificationFailed(
                detail: "\(expected.path) is \(actual) bytes instead of \(expected.sizeBytes)"
            )
        }
    }

    private func verifyHash(of url: URL, expected: String) throws {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw ModelErrorTranslator.translate(error)
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: HubModelFiles.hashChunkBytes) ?? Data()
            } catch {
                throw ModelErrorTranslator.translate(error)
            }
            guard !chunk.isEmpty else {
                break
            }
            hasher.update(data: chunk)
        }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == expected else {
            throw ModelManagementError.verificationFailed(detail: "\(url.lastPathComponent) failed its integrity check")
        }
    }

    // MARK: - Measuring

    func inspect(_ model: Model) -> ModelDiskInspection {
        guard let folder = try? folder(of: model) else {
            return .empty
        }
        let size = Self.contentSize(of: folder)
        return ModelDiskInspection(hasFiles: size.fileCount > 0, bytes: size.logicalBytes)
    }

    func totalUsedBytes() -> Int64 {
        Self.contentSize(of: root).allocatedBytes
    }

    private struct ContentSize {
        var fileCount = 0
        var logicalBytes: Int64 = 0
        var allocatedBytes: Int64 = 0
    }

    private static func contentSize(of folder: URL) -> ContentSize {
        var size = ContentSize()
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey]
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys)) else {
            return size
        }
        for case let url as URL in files {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else {
                continue
            }
            size.fileCount += 1
            size.logicalBytes += Int64(values.fileSize ?? 0)
            size.allocatedBytes += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return size
    }

    // MARK: - Removing

    /// Removes the model's folder, complete and partial files alike. An absent folder is not a failure.
    func removeFiles(of model: Model) throws {
        let folder = try folder(of: model)
        guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: folder)
        } catch {
            throw ModelManagementError.removalFailed(detail: error.localizedDescription)
        }
    }

    func resolve(_ model: Model) -> Model.Resolved {
        model.resolved(in: root.appending(path: model.id, directoryHint: .isDirectory))
    }

}

typealias LanguageModelFileStore = HubModelFileStore<LanguageModel>

/// The rules every Hub model folder follows, whatever kind of model it holds.
enum HubModelFiles {
    static let partialSuffix = ".incomplete"
    static let requiredFiles = ["config.json", "tokenizer.json", "tokenizer_config.json"]
    static let hashChunkBytes = 4 * 1024 * 1024
    private static let poolingFolder = "1_Pooling"
    private static let neededExtensions: Set<String> = ["json", "safetensors", "jinja", "txt", "model", "tiktoken"]

    static func partialFile(for file: URL) -> URL {
        file.deletingLastPathComponent().appending(path: file.lastPathComponent + partialSuffix)
    }

    /// The repository files a model needs to load offline: configuration, weights, tokenizer and chat template, at the
    /// top of the repository, and the pooling configuration of a sentence-transformers model. Folders of other formats,
    /// such as ONNX, hold files with the same names and are left out.
    static func isNeeded(_ repositoryPath: String) -> Bool {
        let components = repositoryPath.split(separator: "/")
        guard let name = components.last, !name.hasPrefix(".") else {
            return false
        }
        guard components.count == 1 || (components.count == 2 && components[0] == poolingFolder) else {
            return false
        }
        return neededExtensions.contains((String(name) as NSString).pathExtension)
    }
}
