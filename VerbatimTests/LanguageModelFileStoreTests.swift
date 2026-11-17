import CryptoKit
import Foundation
import Testing

@testable import Verbatim

/// The language model storage folder, on a real temporary folder.
struct LanguageModelFileStoreTests {
    let root: URL
    let store: LanguageModelFileStore
    let model = LanguageModelCatalog.curated[0]

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "LanguageModels-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = LanguageModelFileStore(root: root)
    }

    /// Writes the files of a loadable model and returns the matching artifact.
    private func writeModel(weights: Data = Data(repeating: 7, count: 2_048)) throws -> ModelArtifact {
        let contents: [String: Data] = [
            "config.json": Data("{}".utf8),
            "tokenizer.json": Data("{\"model\":{}}".utf8),
            "tokenizer_config.json": Data("{}".utf8),
            "model.safetensors": weights
        ]
        let folder = root.appending(path: model.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var files: [ModelArtifact.File] = []
        for (name, data) in contents.sorted(by: { $0.key < $1.key }) {
            try data.write(to: folder.appending(path: name))
            let hash =
                name.hasSuffix(".safetensors")
                ? SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() : nil
            files.append(ModelArtifact.File(path: "\(model.id)/\(name)", sizeBytes: Int64(data.count), sha256: hash))
        }
        return ModelArtifact(files: files)
    }

    @Test(arguments: [
        ("config.json", true), ("model-00001-of-00002.safetensors", true), ("chat_template.jinja", true),
        ("merges.txt", true), ("tokenizer.model", true), ("README.md", false), (".gitattributes", false),
        ("images/logo.png", false)
    ])
    func onlyWhatLoadingNeedsIsDownloaded(path: String, isNeeded: Bool) {
        #expect(HubModelFiles.isNeeded(path) == isNeeded)
    }

    @Test func aCompleteModelVerifies() throws {
        let artifact = try writeModel()

        let size = try store.verify(model, against: artifact, depth: .full)

        #expect(size > 0)
        #expect(store.inspect(model).hasFiles)
    }

    @Test func changedWeightsFailTheFullCheckButNotTheQuickOne() throws {
        let artifact = try writeModel()
        try Data(repeating: 9, count: 2_048).write(to: root.appending(path: "\(model.id)/model.safetensors"))

        #expect(throws: Never.self) { try store.verify(model, against: artifact, depth: .quick) }
        #expect(throws: ModelManagementError.self) { try store.verify(model, against: artifact, depth: .full) }
    }

    @Test func aTruncatedFileOrAManifestWithoutTheTokenizerFails() throws {
        let artifact = try writeModel()
        try Data(repeating: 7, count: 10).write(to: root.appending(path: "\(model.id)/model.safetensors"))
        #expect(throws: ModelManagementError.self) { try store.verify(model, against: artifact, depth: .quick) }

        let withoutTokenizer = ModelArtifact(files: artifact.files.filter { !$0.path.hasSuffix("/tokenizer.json") })
        #expect(throws: ModelManagementError.self) {
            try store.verify(model, against: withoutTokenizer, depth: .quick)
        }
    }

    @Test(arguments: [
        "../escape.json", "other-model/config.json", "\(LanguageModelCatalog.curated[0].id)/../x", "/abs"
    ])
    func listedPathsMustStayInsideTheModelFolder(path: String) {
        #expect(throws: ModelManagementError.self) { try store.file(atRelativePath: path, of: model) }
    }

    @Test func removingTakesOnlyTheModelsOwnFolder() throws {
        _ = try writeModel()
        let neighbor = root.appending(path: "model-registry.json")
        try Data("{}".utf8).write(to: neighbor)

        try store.removeFiles(of: model)
        try store.removeFiles(of: model)

        #expect(!store.inspect(model).hasFiles)
        #expect(FileManager.default.fileExists(atPath: neighbor.path(percentEncoded: false)))
    }

    @Test func partialFilesSitBesideTheirDestination() {
        let destination = root.appending(path: "\(model.id)/model.safetensors")

        #expect(
            HubModelFiles.partialFile(for: destination).lastPathComponent == "model.safetensors.incomplete"
        )
    }
}
