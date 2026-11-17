import CryptoKit
import Foundation
import Testing

@testable import Verbatim

/// The real file boundary against a temporary folder laid out as WhisperKit's downloader leaves it.
struct ModelFileStoreTests {
    private let root: URL
    private let store: ModelFileStore
    private let repository = "argmaxinc/whisperkit-coreml"
    private let model = ModelFixtures.tiny

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "ModelFileStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = ModelFileStore(root: root, repository: repository)
    }

    @discardableResult
    private func write(_ path: String, contents: String = "x") throws -> URL {
        let url = root.appending(path: path, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appending(path: path).path(percentEncoded: false))
    }

    /// A complete installation on disk, and the artifact describing it.
    private func installModel() throws -> ModelArtifact {
        var files: [ModelArtifact.File] = []
        for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let path = "models/\(repository)/\(model.id)/\(component).mlmodelc/weights/weight.bin"
            try write(path, contents: "weights-\(component)")
            let contents = Data("weights-\(component)".utf8)
            files.append(
                .init(
                    path: path,
                    sizeBytes: Int64(contents.count),
                    sha256: SHA256.hash(data: contents).map { String(format: "%02x", $0) }.joined()
                )
            )
        }
        let tokenizerPath = "models/\(model.tokenizerRepository)/tokenizer.json"
        try write(tokenizerPath, contents: "{}")
        files.append(.init(path: tokenizerPath, sizeBytes: 2, sha256: nil))
        try write("models/\(repository)/.cache/huggingface/download/\(model.id)/weight.bin.metadata")
        return ModelArtifact(files: files)
    }

    // MARK: - Verifying

    @Test(arguments: [ModelVerificationDepth.quick, .full])
    func completeInstallationVerifies(depth: ModelVerificationDepth) throws {
        let artifact = try installModel()

        let usedBytes = try store.verify(model, against: artifact, depth: depth)

        #expect(usedBytes > 0)
    }

    @Test func missingFileFailsVerification() throws {
        let artifact = try installModel()
        let path = "models/\(repository)/\(model.id)/TextDecoder.mlmodelc/weights/weight.bin"
        try FileManager.default.removeItem(at: root.appending(path: path))

        #expect(throws: ModelManagementError.self) {
            try store.verify(model, against: artifact, depth: .quick)
        }
    }

    @Test func truncatedFileFailsEvenTheQuickCheck() throws {
        let artifact = try installModel()
        try write("models/\(repository)/\(model.id)/TextDecoder.mlmodelc/weights/weight.bin", contents: "short")

        #expect(throws: ModelManagementError.self) {
            try store.verify(model, against: artifact, depth: .quick)
        }
    }

    @Test func corruptedFileOfTheRightSizeFailsOnlyTheFullCheck() throws {
        let artifact = try installModel()
        let path = "models/\(repository)/\(model.id)/TextDecoder.mlmodelc/weights/weight.bin"
        try write(path, contents: String(repeating: "z", count: "weights-TextDecoder".count))

        _ = try store.verify(model, against: artifact, depth: .quick)
        #expect(throws: ModelManagementError.self) {
            try store.verify(model, against: artifact, depth: .full)
        }
    }

    @Test func manifestWithoutARequiredComponentFailsVerification() throws {
        let artifact = try installModel()
        let partial = ModelArtifact(files: artifact.files.filter { !$0.path.contains("AudioEncoder") })

        #expect(throws: ModelManagementError.self) {
            try store.verify(model, against: partial, depth: .quick)
        }
    }

    @Test func manifestWithoutATokenizerFailsVerification() throws {
        let artifact = try installModel()
        let partial = ModelArtifact(files: artifact.files.filter { !$0.path.hasSuffix("tokenizer.json") })

        #expect(throws: ModelManagementError.self) {
            try store.verify(model, against: partial, depth: .quick)
        }
    }

    @Test(arguments: ["../outside.bin", "/etc/passwd", "models/../../outside.bin"])
    func manifestPathsCannotLeaveStorage(path: String) throws {
        let artifact = try installModel()
        let hostile = ModelArtifact(files: artifact.files + [.init(path: path, sizeBytes: 1, sha256: nil)])

        #expect(throws: ModelManagementError.verificationFailed(detail: "Unsafe path in the model manifest")) {
            try store.verify(model, against: hostile, depth: .quick)
        }
    }

    // MARK: - Inspecting

    @Test func nothingOnDiskInspectsAsEmpty() {
        #expect(store.inspect(model) == .empty)
    }

    @Test func partialFilesCountAsFiles() throws {
        try write(
            "models/\(repository)/.cache/huggingface/download/\(model.id)/weight.bin.abc.incomplete",
            contents: "12345"
        )

        let inspection = store.inspect(model)

        #expect(inspection.hasFiles)
        #expect(inspection.bytes == 5)
    }

    @Test func aTokenizerAloneIsNotAModel() throws {
        try write("models/\(model.tokenizerRepository)/tokenizer.json")

        #expect(!store.inspect(model).hasFiles)
    }

    @Test func downloadedBytesIncludeTheTokenizer() throws {
        try write("models/\(repository)/\(model.id)/file.bin", contents: "1234")
        try write("models/\(model.tokenizerRepository)/tokenizer.json", contents: "12")

        #expect(store.downloadedBytes(of: model) == 6)
    }

    // MARK: - Removing

    @Test func removalTakesOnlyThisModelsFiles() throws {
        _ = try installModel()
        try write("models/\(repository)/other-model/file.bin")
        try write("models/\(repository)/.cache/huggingface/download/other-model/file.bin.metadata")
        try write("models/\(repository)/config.json")
        try write("model-registry.json")
        try write("unrelated/recording.mov")

        try store.removeFiles(of: model, includingTokenizer: true)

        #expect(!exists("models/\(repository)/\(model.id)"))
        #expect(!exists("models/\(repository)/.cache/huggingface/download/\(model.id)"))
        #expect(!exists("models/\(model.tokenizerRepository)"))
        #expect(exists("models/\(repository)/other-model/file.bin"))
        #expect(exists("models/\(repository)/.cache/huggingface/download/other-model/file.bin.metadata"))
        #expect(exists("models/\(repository)/config.json"))
        #expect(exists("model-registry.json"))
        #expect(exists("unrelated/recording.mov"))
    }

    @Test func removalCanKeepASharedTokenizer() throws {
        _ = try installModel()

        try store.removeFiles(of: model, includingTokenizer: false)

        #expect(!exists("models/\(repository)/\(model.id)"))
        #expect(exists("models/\(model.tokenizerRepository)/tokenizer.json"))
    }

    @Test func removingWhatIsAbsentSucceeds() throws {
        try store.removeFiles(of: model, includingTokenizer: true)
    }

    @Test(arguments: ["..", "../..", "../outside", "a/b", "", ".", "/etc", "x\u{0}y"])
    func hostileIdentifiersCannotDeleteAnything(id: String) throws {
        try write("outside/file.bin")
        let hostile = SpeechModel(
            id: id,
            name: "Bad",
            summary: "",
            languageSupport: "",
            tokenizerRepository: "openai/whisper-tiny"
        )

        #expect(throws: ModelManagementError.modelUnavailable) {
            try store.removeFiles(of: hostile, includingTokenizer: true)
        }
        #expect(exists("outside/file.bin"))
    }

    @Test(arguments: ["../..", "openai/../..", "openai", "/", "a/b/c"])
    func hostileTokenizerRepositoriesCannotDeleteAnything(repository: String) throws {
        try write("models/openai/whisper-tiny/tokenizer.json")
        let hostile = SpeechModel(
            id: "good-id",
            name: "Bad",
            summary: "",
            languageSupport: "",
            tokenizerRepository: repository
        )

        #expect(throws: ModelManagementError.modelUnavailable) {
            try store.removeFiles(of: hostile, includingTokenizer: true)
        }
        #expect(exists("models/openai/whisper-tiny/tokenizer.json"))
    }

    // MARK: - Measuring and preparing

    @Test func totalUsageCountsEverythingInStorage() throws {
        try write("models/file.bin", contents: String(repeating: "x", count: 100_000))

        #expect(store.totalUsedBytes() >= 100_000)
    }

    @Test func capacityIsMeasuredEvenBeforeTheFolderExists() throws {
        let missing = ModelFileStore(root: root.appending(path: "not/yet/here"), repository: repository)

        #expect(try missing.availableCapacity() > 0)
    }

    @Test func preparingCreatesStorageExcludedFromBackup() throws {
        let fresh = ModelFileStore(root: root.appending(path: "fresh/Models"), repository: repository)

        try fresh.prepareStorage()

        let values = try fresh.root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func resolvedLocationMatchesWhereFilesAre() throws {
        let artifact = try installModel()

        let resolved = store.resolve(model)

        let contents = try FileManager.default.contentsOfDirectory(
            atPath: resolved.modelFolder.path(percentEncoded: false)
        )
        #expect(contents.count == 3)
        #expect(resolved.tokenizerBase == root)
        #expect(artifact.files.contains { $0.path.hasSuffix("tokenizer.json") })
    }
}

struct HubModelManifestClientTests {
    private let model = ModelFixtures.tiny

    private func client(
        status: Int = 200,
        responses: @escaping @Sendable (URL) throws -> String
    ) -> HubModelManifestClient {
        HubModelManifestClient(repository: "argmaxinc/whisperkit-coreml", endpoint: "https://hub.example") { request in
            let url = try #require(request.url)
            let response = try #require(
                HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
            )
            return (Data(try responses(url).utf8), response)
        }
    }

    @Test func combinesModelAndTokenizerFilesWithHashesAndSizes() async throws {
        let model = model
        let client = client { url in
            if url.path().contains("whisperkit-coreml") {
                return """
                    [
                      {"type": "directory", "path": "\(model.id)/AudioEncoder.mlmodelc", "size": 0},
                      {"type": "file", "path": "\(model.id)/AudioEncoder.mlmodelc/weights/weight.bin", "size": 100,
                       "lfs": {"oid": "abc123", "size": 100, "pointerSize": 134}},
                      {"type": "file", "path": "\(model.id)/config.json", "size": 5}
                    ]
                    """
            }
            return """
                [
                  {"type": "file", "path": "tokenizer.json", "size": 7},
                  {"type": "file", "path": "tokenizer_config.json", "size": 3},
                  {"type": "file", "path": "flax_model.msgpack", "size": 999999}
                ]
                """
        }

        let artifact = try await client.artifact(of: model)

        #expect(artifact.totalBytes == 115)
        #expect(artifact.files.count == 4)
        #expect(
            artifact.files.first {
                $0.path == "models/argmaxinc/whisperkit-coreml/\(model.id)/AudioEncoder.mlmodelc/weights/weight.bin"
            }?.sha256 == "abc123"
        )
        #expect(artifact.files.contains { $0.path == "models/openai/whisper-tiny/tokenizer.json" })
        #expect(!artifact.files.contains { $0.path.contains("flax") })
    }

    @Test func missingModelIsUnavailable() async {
        let client = client(status: 404) { _ in "{}" }

        await #expect(throws: ModelManagementError.modelUnavailable) {
            try await client.artifact(of: model)
        }
    }

    @Test func emptyListingIsUnavailable() async {
        let client = client { _ in "[]" }

        await #expect(throws: ModelManagementError.modelUnavailable) {
            try await client.artifact(of: model)
        }
    }

    @Test func offlineIsReportedAsNoNetwork() async {
        let client = client { _ in throw URLError(.notConnectedToInternet) }

        await #expect(throws: ModelManagementError.noNetwork) {
            try await client.artifact(of: model)
        }
    }

    @Test func unexpectedResponseIsAFailureNotACrash() async {
        let client = client { _ in "not json" }

        await #expect(throws: ModelManagementError.self) {
            try await client.artifact(of: model)
        }
    }
}

struct ModelErrorTranslatorTests {
    @Test func cancellationStaysCancellation() {
        #expect(ModelErrorTranslator.translate(URLError(.cancelled)) is CancellationError)
        #expect(ModelErrorTranslator.translate(CancellationError()) is CancellationError)
    }

    @Test func diskFullIsReportedAsSuch() {
        let error = ModelErrorTranslator.translate(CocoaError(.fileWriteOutOfSpace))

        #expect(error as? ModelManagementError == .insufficientDiskSpace(requiredBytes: 0, availableBytes: 0))
    }

    @Test func permissionProblemsAreReportedAsSuch() {
        let error = ModelErrorTranslator.translate(CocoaError(.fileWriteNoPermission))

        guard case .storageAccessDenied = error as? ModelManagementError else {
            Issue.record("Expected a storage access failure, got \(error)")
            return
        }
    }

    @Test func alreadyTranslatedErrorsPassThrough() {
        let error = ModelErrorTranslator.translate(ModelManagementError.modelInUse)

        #expect(error as? ModelManagementError == .modelInUse)
    }
}
