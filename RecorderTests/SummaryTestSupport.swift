import Foundation
import Synchronization

@testable import Recorder

/// A language model stand-in: tokens are words, and replies are written from the request, so tests can see which
/// stage asked. Generation can be held at a gate, to observe and interrupt a running summary.
final class FakeTextGenerator: TextGenerator {
    struct State {
        var requests: [[TextGenerationMessage]] = []
        var parameters: [TextGenerationParameters] = []
        var failure: (any Error)?
        var replyPrefix = ""
        var holds = false
        var failOnTitle = false
        var gate: AsyncStream<Void>.Continuation?
    }

    let state = Mutex(State())

    func update(_ change: (inout State) -> Void) {
        state.withLock { change(&$0) }
    }

    func read<Value: Sendable>(_ value: (State) -> Value) -> Value {
        state.withLock { value($0) }
    }

    var isHeld: Bool {
        read { $0.gate != nil }
    }

    func releaseHold() {
        let gate = state.withLock { state in
            state.holds = false
            defer { state.gate = nil }
            return state.gate
        }
        gate?.finish()
    }

    func tokenCount(of text: String) async throws -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    func generate(_ messages: [TextGenerationMessage], parameters: TextGenerationParameters) async throws -> String {
        update {
            $0.requests.append(messages)
            $0.parameters.append(parameters)
        }
        if read(\.holds) {
            let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
            update { $0.gate = continuation }
            for await _ in stream {}
            try Task.checkCancellation()
        }
        if read(\.failOnTitle), messages.first?.content.hasPrefix("You name") == true {
            throw URLError(.timedOut)
        }
        if let failure = read(\.failure) {
            throw failure
        }
        let system = messages.first?.content ?? ""
        let stage =
            system.hasPrefix("You take notes") ? "notes" : system.hasPrefix("You condense") ? "condensed" : "summary"
        return "\(read(\.replyPrefix))\(stage) \(read(\.requests).count)"
    }
}

/// Hands out a `FakeTextGenerator`, or fails as told, and counts what was taken and given back.
@MainActor
final class FakeTextGenerationProvider: TextGenerationProvider {
    let generator = FakeTextGenerator()
    var settings = LanguageModelCatalog.curated[1].preset
    var acquireFailure: (any Error)?
    var hasUsableModel = true
    private(set) var acquired = 0
    private(set) var released = 0

    func prepareForUse() async {}

    func acquireGenerator() async throws -> TextGenerationSession {
        if let acquireFailure {
            throw acquireFailure
        }
        acquired += 1
        return TextGenerationSession(id: UUID(), modelID: "fake-model", settings: settings, generator: generator)
    }

    func release(sessionID: UUID) async {
        released += 1
    }
}

/// Language model files that only exist in memory.
final class FakeLanguageModelProvider: ModelFileProviding {
    let storageLocation = URL(filePath: "/language-models", directoryHint: .isDirectory)
    let filesOnDisk = Mutex<Set<LanguageModel.ID>>([])
    let supportedIDs: Set<LanguageModel.ID>

    init(supportedIDs: Set<LanguageModel.ID> = Set(LanguageModelCatalog.curated.map(\.id))) {
        self.supportedIDs = supportedIDs
    }

    func supportedModelIDs() -> Set<LanguageModel.ID> {
        supportedIDs
    }

    func fetchSupportedModelIDs() async -> Set<LanguageModel.ID> {
        supportedIDs
    }

    func fetchArtifact(of model: LanguageModel) async throws -> ModelArtifact {
        ModelArtifact(files: [ModelArtifact.File(path: "\(model.id)/model.safetensors", sizeBytes: 100, sha256: nil)])
    }

    func availableCapacity() async throws -> Int64 {
        1_000_000_000_000
    }

    func download(
        _ model: LanguageModel,
        artifact: ModelArtifact,
        onProgress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        _ = filesOnDisk.withLock { $0.insert(model.id) }
    }

    func verify(
        _ model: LanguageModel,
        against artifact: ModelArtifact,
        depth: ModelVerificationDepth
    ) async throws -> Int64 {
        guard filesOnDisk.withLock({ $0.contains(model.id) }) else {
            throw ModelManagementError.verificationFailed(detail: "missing")
        }
        return artifact.totalBytes
    }

    func inspect(_ model: LanguageModel) async -> ModelDiskInspection {
        let hasFiles = filesOnDisk.withLock { $0.contains(model.id) }
        return ModelDiskInspection(hasFiles: hasFiles, bytes: hasFiles ? 100 : 0)
    }

    func removeFiles(of model: LanguageModel, includingSharedFiles: Bool) async throws {
        _ = filesOnDisk.withLock { $0.remove(model.id) }
    }

    func resolve(_ model: LanguageModel) -> ResolvedLanguageModel {
        ResolvedLanguageModel(
            id: model.id,
            folder: storageLocation.appending(path: model.id),
            disablesThinking: model.disablesThinking
        )
    }

    func diskUsage() async -> Int64 {
        Int64(filesOnDisk.withLock { $0.count }) * 100
    }
}

final class InMemorySummarySettingsRepository: SummarySettingsRepository {
    private let selectedModelID = Mutex<String?>(nil)
    private let customSettings = Mutex<[LanguageModel.ID: SummarySettings]>([:])
    private let languageCode = Mutex<String?>(nil)

    func loadSelectedModelID() -> String? {
        selectedModelID.withLock { $0 }
    }

    func saveSelectedModelID(_ id: String?) {
        selectedModelID.withLock { $0 = id }
    }

    func loadLanguageCode() -> String? {
        languageCode.withLock { $0 }
    }

    func saveLanguageCode(_ code: String) {
        languageCode.withLock { $0 = code }
    }

    func loadCustomSettings() -> [LanguageModel.ID: SummarySettings] {
        customSettings.withLock { $0 }
    }

    func saveCustomSettings(_ settings: [LanguageModel.ID: SummarySettings]) {
        customSettings.withLock { $0 = settings }
    }
}

/// A language model manager on fake files, and the stores behind it.
@MainActor
struct LanguageModelHarness {
    let provider = FakeLanguageModelProvider()
    let settings = InMemorySummarySettingsRepository()
    let manager: LanguageModelManager

    init() {
        manager = LanguageModelManager(
            catalog: LanguageModelCatalog.curated,
            provider: provider,
            registryStore: InMemoryModelRegistryStore(),
            selection: settings
        )
    }

    func install(_ id: LanguageModel.ID) async throws {
        manager.download(id)
        for _ in 0..<2_000 where !manager.state(of: id).isInstalled {
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

enum SummaryFixtures {
    // Russian is in the supported list, which `SummaryDomainTests` checks.
    // swiftlint:disable:next force_unwrapping
    static let russian = SummaryLanguage(code: "ru")!
    static let createdAt = Date(timeIntervalSince1970: 1_800_000_000)

    /// Lines of `wordsPerLine` words, ten seconds apart, alternating sources.
    static func transcript(of id: UUID, lines: Int, wordsPerLine: Int = 10, language: String? = "ru") -> Transcript {
        var speech: [RecognizedSpeech] = []
        for index in 0..<lines {
            let start = Double(index) * 10
            let words = Array(repeating: "word\(index)", count: wordsPerLine).joined(separator: " ")
            let source: TranscriptSource = index.isMultiple(of: 2) ? .microphone : .systemAudio
            speech.append(RecognizedSpeech(startTime: start, endTime: start + 5, text: words, source: source))
        }
        let provenance = Transcript.Provenance(
            modelID: "tiny",
            modelVersion: "1",
            language: language,
            createdAt: createdAt
        )
        return Transcript.assembled(
            recordingID: id,
            provenance: provenance,
            speech: speech,
            mediaDuration: Double(lines) * 10 + 10
        )
    }

    static func settings(batchTokens: Int) -> SummarySettings {
        var settings = LanguageModelCatalog.curated[1].preset
        settings.batchTokens = batchTokens
        return settings
    }
}
