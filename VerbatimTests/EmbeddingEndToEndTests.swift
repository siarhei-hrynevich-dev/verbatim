import Foundation
import Testing

@testable import Verbatim

/// Real vectors with an MLX embedding model on this Mac. Off unless asked for, because ordinary tests need no models.
///
///     TEST_RUNNER_RECORDER_E2E_EMBEDDING_MODELS="$HOME/Library/Application Support/Verbatim/EmbeddingModels" make test
///
/// The folder is laid out as `HubModelFileStore` lays it out. `TEST_RUNNER_RECORDER_E2E_EMBEDDING_MODEL_ID` picks the
/// model (Multilingual E5 Small by default). With `TEST_RUNNER_RECORDER_E2E_DOWNLOAD=1`, the model is first downloaded
/// and verified through the app's own downloader, which needs the network; otherwise nothing is downloaded.
@Suite(.enabled(if: EmbeddingEndToEndConfiguration.isConfigured), .serialized)
struct EmbeddingEndToEndTests {
    private let configuration = EmbeddingEndToEndConfiguration()

    @Test func theAppsDownloaderInstallsAVerifiedModel() async throws {
        try #require(configuration.downloads, "Set TEST_RUNNER_RECORDER_E2E_DOWNLOAD=1 to download")
        let provider = HubEmbeddingModelProvider(storageLocation: configuration.root)
        let model = try configuration.model()

        let artifact = try await provider.fetchArtifact(of: model)
        try await provider.download(model, artifact: artifact) { _ in }
        let size = try await provider.verify(model, against: artifact, depth: .full)

        #expect(artifact.files.allSatisfy { !$0.path.contains("/onnx/") && !$0.path.contains("/openvino/") })
        #expect(artifact.files.contains { $0.path.hasSuffix("1_Pooling/config.json") })
        #expect(size >= artifact.totalBytes)
    }

    @Test func aQuestionFindsTheAnswerAcrossLanguages() async throws {
        let model = try configuration.model()
        let runtime = MLXEmbeddingRuntime()
        let embedder = try await runtime.loadEmbedder(
            for: HubEmbeddingModelProvider(storageLocation: configuration.root).resolve(model)
        )
        let passages = [
            "Сергей исправит ошибку с пропадающим звуком микрофона до четверга.",
            "Бюджет на рекламу остаётся прежним, сто тысяч рублей.",
            "We will hire two designers next quarter."
        ]

        let documents = try await embedder.embed(passages, as: .passage)
        let questions = try await embedder.embed(
            ["Who fixes the microphone bug?", "Сколько денег на маркетинг?", "Когда наймём дизайнеров?"],
            as: .query
        )
        await runtime.releaseMemory()

        #expect(documents.allSatisfy { $0.count == model.dimensions })
        #expect(documents.allSatisfy { abs(sqrt($0.reduce(0) { $0 + $1 * $1 }) - 1) < 0.001 })
        for (expected, question) in questions.enumerated() {
            let similarities = documents.map { zip($0, question).reduce(Float(0)) { $0 + $1.0 * $1.1 } }
            print("Question \(expected): \(similarities)")
            #expect(similarities.firstIndex(of: similarities.max() ?? 0) == expected)
        }
    }
}

struct EmbeddingEndToEndConfiguration {
    static var isConfigured: Bool {
        ProcessInfo.processInfo.environment["RECORDER_E2E_EMBEDDING_MODELS"] != nil
    }

    var root: URL {
        URL(filePath: ProcessInfo.processInfo.environment["RECORDER_E2E_EMBEDDING_MODELS"] ?? "/nonexistent")
    }

    var downloads: Bool {
        ProcessInfo.processInfo.environment["RECORDER_E2E_DOWNLOAD"] == "1"
    }

    func model() throws -> EmbeddingModel {
        let id = ProcessInfo.processInfo.environment["RECORDER_E2E_EMBEDDING_MODEL_ID"] ?? "multilingual-e5-small"
        return try #require(EmbeddingModelCatalog.curated.first { $0.id == id })
    }
}
