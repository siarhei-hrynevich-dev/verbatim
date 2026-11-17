import CryptoKit
import Foundation

/// The model storage folder and its layout, which WhisperKit's downloader owns and this type only reads and prunes:
///
///     <root>/models/argmaxinc/whisperkit-coreml/<variant>/…   model files
///     <root>/models/argmaxinc/whisperkit-coreml/.cache/huggingface/download/<variant>/…   partials, file metadata
///     <root>/models/<tokenizer repository>/…   tokenizer, possibly shared
///
/// Paths are only ever derived from a validated identifier under the root. Nothing read from persisted metadata is
/// ever deleted, and no folder above a model's own is removed.
struct ModelFileStore: Sendable {
    let root: URL
    let repository: String

    // MARK: - Layout

    /// Where a model's files are, without checking that they exist.
    func modelFolder(of model: SpeechModel) throws -> URL {
        try folder(relativeTo: repositoryFolder(), identifier: model.id)
    }

    private func repositoryFolder() -> URL {
        root.appending(path: "models", directoryHint: .isDirectory)
            .appending(path: repository, directoryHint: .isDirectory)
    }

    private func partialFilesFolder(of model: SpeechModel) throws -> URL {
        let download = repositoryFolder().appending(path: ".cache/huggingface/download", directoryHint: .isDirectory)
        return try folder(relativeTo: download, identifier: model.id)
    }

    private func tokenizerFolder(of model: SpeechModel) throws -> URL {
        // A repository is `owner/name`: exactly two validated components.
        let components = model.tokenizerRepository.split(separator: "/", omittingEmptySubsequences: false).map(
            String.init
        )
        guard components.count == 2, components.allSatisfy(Self.isSafeIdentifier) else {
            throw ModelManagementError.modelUnavailable
        }
        return root.appending(path: "models/\(components[0])/\(components[1])", directoryHint: .isDirectory)
    }

    private func folder(relativeTo parent: URL, identifier: String) throws -> URL {
        guard Self.isSafeIdentifier(identifier) else {
            throw ModelManagementError.modelUnavailable
        }
        return parent.appending(path: identifier, directoryHint: .isDirectory)
    }

    /// Letters, digits and `-_.`, and not made of dots alone, so it cannot name anything but a direct child.
    static func isSafeIdentifier(_ identifier: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return !identifier.isEmpty
            && identifier.unicodeScalars.allSatisfy(allowed.contains)
            && identifier.contains { $0 != "." }
    }

    /// A manifest path is untrusted text: it must stay inside the root.
    private func file(atRelativePath path: String) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.hasPrefix("/"), !components.isEmpty, !components.contains(where: { $0 == ".." || $0.isEmpty })
        else {
            throw ModelManagementError.verificationFailed(detail: "Unsafe path in the model manifest")
        }
        return root.appending(path: path, directoryHint: .notDirectory)
    }

    // MARK: - Preparing

    /// Creates the folder, and keeps downloadable weights out of backups.
    func prepareStorage() throws {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var folder = root
            try folder.setResourceValues(values)
        } catch {
            throw ModelErrorTranslator.translate(error)
        }
    }

    /// Space available for a download, measured on the volume of the nearest folder that exists.
    func availableCapacity() throws -> Int64 {
        var url = root
        while !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)), url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
        }
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage ?? 0
        } catch {
            throw ModelErrorTranslator.translate(error)
        }
    }

    // MARK: - Verifying

    /// Checks every expected file without loading anything. Returns the space the model occupies.
    func verify(_ model: SpeechModel, against artifact: ModelArtifact, depth: ModelVerificationDepth) throws -> Int64 {
        try verifyLayout(of: model, in: artifact)
        for expected in artifact.files {
            try Task.checkCancellation()
            let url = try file(atRelativePath: expected.path)
            try verifySize(of: url, expected: expected)
            if depth == .full, let sha256 = expected.sha256 {
                try verifyHash(of: url, expected: sha256)
            }
        }
        return try usedBytes(of: model)
    }

    /// The files WhisperKit requires to load offline, so a truncated or changed manifest cannot pass as complete.
    private func verifyLayout(of model: SpeechModel, in artifact: ModelArtifact) throws {
        let paths = artifact.files.map(\.path)
        for component in Self.requiredModelComponents {
            guard paths.contains(where: { $0.contains("/\(model.id)/\(component).mlmodelc/") }) else {
                throw ModelManagementError.verificationFailed(detail: "\(component) is missing from the model")
            }
        }
        let tokenizerPrefix = "models/\(model.tokenizerRepository)/"
        guard paths.contains(tokenizerPrefix + Self.tokenizerFile) else {
            throw ModelManagementError.verificationFailed(detail: "The tokenizer is missing from the model")
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
                chunk = try handle.read(upToCount: Self.hashChunkBytes) ?? Data()
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

    /// Whether anything of the model itself is on disk. A tokenizer alone may belong to another model.
    func inspect(_ model: SpeechModel) -> ModelDiskInspection {
        guard let folders = try? [modelFolder(of: model), partialFilesFolder(of: model)] else {
            return .empty
        }
        let sizes = folders.map(Self.contentSize(of:))
        let hasFiles = sizes.contains { $0.fileCount > 0 }
        return ModelDiskInspection(hasFiles: hasFiles, bytes: sizes.reduce(0) { $0 + $1.logicalBytes })
    }

    /// Bytes received so far, including partial files, which is what makes progress proportional to data rather than
    /// to the number of files.
    func downloadedBytes(of model: SpeechModel) -> Int64 {
        let tokenizerBytes = (try? tokenizerFolder(of: model)).map { Self.contentSize(of: $0).logicalBytes } ?? 0
        return inspect(model).bytes + tokenizerBytes
    }

    private func usedBytes(of model: SpeechModel) throws -> Int64 {
        let folders = try [modelFolder(of: model), partialFilesFolder(of: model), tokenizerFolder(of: model)]
        return folders.reduce(0) { $0 + Self.contentSize(of: $1).allocatedBytes }
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

    /// Removes the model's folder and partial files, and its tokenizer only when told it is not shared. Other models,
    /// the repository's own files and everything outside the root stay. Absent files are not a failure.
    func removeFiles(of model: SpeechModel, includingTokenizer: Bool) throws {
        var folders = [try modelFolder(of: model), try partialFilesFolder(of: model)]
        if includingTokenizer {
            folders.append(try tokenizerFolder(of: model))
        }
        for folder in folders where FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) {
            do {
                try FileManager.default.removeItem(at: folder)
            } catch {
                throw ModelManagementError.removalFailed(detail: error.localizedDescription)
            }
        }
    }

    func resolve(_ model: SpeechModel) -> ResolvedSpeechModel {
        ResolvedSpeechModel(
            id: model.id,
            modelFolder: repositoryFolder().appending(path: model.id, directoryHint: .isDirectory),
            tokenizerBase: root
        )
    }

    // MARK: - Constants

    /// The tokenizer's files, as WhisperKit's own tokenizer loader requests them.
    static let tokenizerFiles = ["config.json", "tokenizer_config.json", "tokenizer.json"]
    private static let tokenizerFile = "tokenizer.json"
    private static let requiredModelComponents = ["MelSpectrogram", "AudioEncoder", "TextDecoder"]
    private static let hashChunkBytes = 4 * 1024 * 1024
}

/// Turns failures from Foundation, URLSession and the downloader into the app's own vocabulary.
enum ModelErrorTranslator {
    static func translate(_ error: any Error) -> any Error {
        if error is ModelManagementError || error is CancellationError {
            return error
        }
        if let urlError = error as? URLError {
            return translate(urlError)
        }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return translateCocoa(code: CocoaError.Code(rawValue: nsError.code), error: error)
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ENOSPC) {
            return ModelManagementError.insufficientDiskSpace(requiredBytes: 0, availableBytes: 0)
        }
        return ModelManagementError.downloadFailed(detail: error.localizedDescription)
    }

    private static func translate(_ error: URLError) -> any Error {
        switch error.code {
        case .cancelled:
            CancellationError()
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
            .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed, .secureConnectionFailed:
            ModelManagementError.noNetwork
        default:
            ModelManagementError.downloadFailed(detail: error.localizedDescription)
        }
    }

    private static func translateCocoa(code: CocoaError.Code, error: any Error) -> any Error {
        switch code {
        case .fileWriteOutOfSpace:
            ModelManagementError.insufficientDiskSpace(requiredBytes: 0, availableBytes: 0)
        case .fileReadNoPermission, .fileWriteNoPermission, .fileWriteVolumeReadOnly:
            ModelManagementError.storageAccessDenied(detail: error.localizedDescription)
        default:
            ModelManagementError.downloadFailed(detail: error.localizedDescription)
        }
    }
}
