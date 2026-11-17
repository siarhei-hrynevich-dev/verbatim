import Foundation
import Testing

@testable import Verbatim

/// Real summaries with an MLX model on this Mac. Off unless asked for, because ordinary tests need no models.
///
///     TEST_RUNNER_RECORDER_E2E_LANGUAGE_MODELS="$HOME/Library/Application Support/Verbatim/LanguageModels" make test
///
/// The folder is laid out as `LanguageModelFileStore` lays it out. `TEST_RUNNER_RECORDER_E2E_LANGUAGE_MODEL_ID` picks
/// the model (Qwen3 1.7B by default). With `TEST_RUNNER_RECORDER_E2E_DOWNLOAD=1`, the model is first downloaded and
/// verified through the app's own downloader, which needs the network; otherwise nothing is downloaded.
@Suite(.enabled(if: SummaryEndToEndConfiguration.isConfigured), .serialized)
struct SummaryEndToEndTests {
    private let configuration = SummaryEndToEndConfiguration()

    @Test func theAppsDownloaderInstallsAVerifiedModel() async throws {
        try #require(configuration.downloads, "Set TEST_RUNNER_RECORDER_E2E_DOWNLOAD=1 to download")
        let provider = HubLanguageModelProvider(storageLocation: configuration.root)
        let model = try configuration.model()

        let artifact = try await provider.fetchArtifact(of: model)
        try await provider.download(model, artifact: artifact) { _ in }
        let size = try await provider.verify(model, against: artifact, depth: .full)

        #expect(size >= artifact.totalBytes)
    }

    @Test func aRussianTranscriptIsSummarizedInRussian() async throws {
        let model = try configuration.model()
        let provider = HubLanguageModelProvider(storageLocation: configuration.root)
        let runtime = MLXTextGenerationRuntime()
        let generator = try await runtime.loadGenerator(for: provider.resolve(model))
        var settings = model.preset
        settings.batchTokens = 120
        let summarizer = TranscriptSummarizer(
            generator: generator,
            settings: settings,
            language: SummaryFixtures.russian
        )

        let output = try await summarizer.summarize(Self.meeting()) { _ in }
        await runtime.releaseMemory()

        #expect(output.parts.count > 1)
        #expect(!output.text.isEmpty)
        #expect(!output.text.contains("<think>"))
        #expect(output.text.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) })
        print("Summary:\n\(output.text)\n\nParts:\n\(output.parts.map(\.text).joined(separator: "\n---\n"))")
    }

    private static func meeting() -> Transcript {
        let lines = [
            "Добрый день, начинаем планёрку по релизу приложения.",
            "Сборка для тестирования будет готова в среду.",
            "Анна проверит запись экрана на мониторах с высоким разрешением.",
            "Нужно исправить ошибку с пропадающим звуком микрофона.",
            "Сергей возьмёт эту ошибку и закончит до четверга.",
            "Релиз переносим на следующий понедельник.",
            "Бюджет на рекламу остаётся прежним, сто тысяч рублей.",
            "Следующая встреча в пятницу в десять утра."
        ]
        let speech = lines.enumerated().map { index, text in
            RecognizedSpeech(
                startTime: Double(index) * 20,
                endTime: Double(index) * 20 + 15,
                text: text,
                source: .microphone
            )
        }
        return Transcript.assembled(
            recordingID: UUID(),
            provenance: .init(modelID: "e2e", modelVersion: nil, language: "ru", createdAt: .now),
            speech: speech,
            mediaDuration: 200
        )
    }
}

struct SummaryEndToEndConfiguration {
    static var isConfigured: Bool {
        ProcessInfo.processInfo.environment["RECORDER_E2E_LANGUAGE_MODELS"] != nil
    }

    var root: URL {
        URL(filePath: ProcessInfo.processInfo.environment["RECORDER_E2E_LANGUAGE_MODELS"] ?? "/nonexistent")
    }

    var downloads: Bool {
        ProcessInfo.processInfo.environment["RECORDER_E2E_DOWNLOAD"] == "1"
    }

    func model() throws -> LanguageModel {
        let id = ProcessInfo.processInfo.environment["RECORDER_E2E_LANGUAGE_MODEL_ID"] ?? "qwen3-1.7b-4bit"
        return try #require(LanguageModelCatalog.curated.first { $0.id == id })
    }
}
