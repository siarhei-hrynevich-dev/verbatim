import Foundation
import Observation
import Synchronization

@testable import Recorder

/// A deterministic stand-in for an embedding model: each word adds to a few dimensions picked from its first letters,
/// so texts sharing words, or words with a shared stem, point the same way. Counts what it was asked to embed.
final class FakeTextEmbedder: TextEmbedder {
    static let space = EmbeddingSpace(modelID: "fake-embedder", revision: "1", dimensions: 32)

    let space: EmbeddingSpace
    private let embedded = Mutex<[(String, EmbeddingRole)]>([])
    private let failure = Mutex<(any Error)?>(nil)
    /// Waits this long before each text, so a job can be caught running.
    let delay: Duration

    init(space: EmbeddingSpace = FakeTextEmbedder.space, delay: Duration = .zero) {
        self.space = space
        self.delay = delay
    }

    var embeddedTexts: [String] {
        embedded.withLock { $0.map(\.0) }
    }

    func failNext(with error: any Error) {
        failure.withLock { $0 = error }
    }

    func embed(_ texts: [String], as role: EmbeddingRole) async throws -> [[Float]] {
        if let error = failure.withLock({ value in
            defer { value = nil }
            return value
        }) {
            throw error
        }
        var vectors: [[Float]] = []
        for text in texts {
            if delay > .zero {
                try await Task.sleep(for: delay)
            }
            try Task.checkCancellation()
            embedded.withLock { $0.append((text, role)) }
            vectors.append(Self.vector(for: text, dimensions: space.dimensions))
        }
        return vectors
    }

    static func vector(for text: String, dimensions: Int) -> [Float] {
        var vector = [Float](repeating: 0, count: dimensions)
        let words = text.lowercased().split { !($0.isLetter || $0.isNumber) }
        for word in words where word.count > 2 {
            let stem = word.prefix(5)
            let hash = stem.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value }
            vector[Int(hash % UInt32(dimensions))] += 1
        }
        let length = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard length > 0 else {
            vector[0] = 1
            return vector
        }
        return vector.map { $0 / length }
    }
}

/// Hands out a `FakeTextEmbedder` when a model is "ready", and counts sessions.
@MainActor
@Observable
final class FakeEmbeddingProvider: EmbeddingProvider {
    var readySpace: EmbeddingSpace? = FakeTextEmbedder.space
    private(set) var isRecordingActive = false
    @ObservationIgnored var embedder = FakeTextEmbedder()
    @ObservationIgnored private(set) var acquired = 0
    @ObservationIgnored private(set) var released = 0

    func prepareForUse() async {}

    func acquireEmbedder() async throws -> EmbeddingSession {
        guard !isRecordingActive else {
            throw CancellationError()
        }
        guard readySpace != nil else {
            throw IndexingFailure.noModelSelected
        }
        acquired += 1
        return EmbeddingSession(id: UUID(), space: embedder.space, embedder: embedder)
    }

    func release(sessionID: UUID) {
        released += 1
    }

    func setRecordingActive(_ isActive: Bool) {
        isRecordingActive = isActive
    }
}

/// Whether transcription or summaries are busy, as a test sets it.
@MainActor
@Observable
final class FakePostProcessingState {
    var isBusy = false
}

enum SearchFixtures {
    static func transcript(
        of recordingID: UUID,
        lines: [String],
        secondsPerLine: TimeInterval = 20,
        createdAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> Transcript {
        let speech = lines.enumerated().map { index, text in
            RecognizedSpeech(
                startTime: Double(index) * secondsPerLine,
                endTime: Double(index) * secondsPerLine + secondsPerLine - 1,
                text: text,
                source: .microphone
            )
        }
        return Transcript.assembled(
            recordingID: recordingID,
            provenance: .init(modelID: "test", modelVersion: nil, language: "ru", createdAt: createdAt),
            speech: speech,
            mediaDuration: Double(lines.count) * secondsPerLine
        )
    }

    static func summary(
        of transcript: Transcript,
        text: String,
        parts: [String] = [],
        createdAt: Date = Date(timeIntervalSince1970: 1_800_000_500)
    ) -> TranscriptSummary {
        TranscriptSummary(
            recordingID: transcript.recordingID,
            modelID: "qwen3-4b-instruct-2507-4bit",
            language: "ru",
            transcriptCreatedAt: transcript.createdAt,
            createdAt: createdAt,
            text: text,
            parts: parts.enumerated().map { index, text in
                SummaryPart(
                    position: index,
                    startTime: Double(index) * 60,
                    endTime: Double(index) * 60 + 59,
                    firstSegment: index * 3,
                    lastSegment: index * 3 + 2,
                    text: text
                )
            }
        )
    }

    static let planning = [
        "Добрый день, начинаем планёрку по релизу приложения.",
        "Сборка для тестирования будет готова в среду.",
        "Анна проверит запись экрана на мониторах с высоким разрешением.",
        "Сергей исправит ошибку с пропадающим звуком микрофона до четверга."
    ]

    static let budget = [
        "The marketing budget stays at one hundred thousand.",
        "We will hire two designers next quarter.",
        "Invoices are paid on the first of every month."
    ]
}

/// A Library database with real repositories over it, for search and indexing tests.
struct SearchTestEnvironment {
    let environment: LibraryTestEnvironment
    let recordings: SQLiteRecordingRepository
    let transcripts: SQLiteTranscriptRepository
    let summaries: SQLiteSummaryRepository
    let index: SQLiteSearchIndexRepository

    init() throws {
        environment = try LibraryTestEnvironment()
        recordings = environment.makeRepository()
        transcripts = SQLiteTranscriptRepository(databaseURL: environment.databaseURL)
        summaries = SQLiteSummaryRepository(databaseURL: environment.databaseURL)
        index = SQLiteSearchIndexRepository(databaseURL: environment.databaseURL)
    }

    /// A recording in the Library with a stored transcript of the lines.
    func addRecording(
        title: String = "Demo",
        createdAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
        lines: [String]
    ) async throws -> Transcript {
        let recording = try environment.makeRecording(title: title, createdAt: createdAt)
        try await recordings.insert(recording)
        let transcript = SearchFixtures.transcript(of: recording.id, lines: lines)
        try await transcripts.replaceTranscript(transcript)
        return transcript
    }
}

extension EmbeddingModelManager {
    /// A manager with nothing installed, on simulated files.
    static func empty() -> EmbeddingModelManager {
        EmbeddingModelManager(
            catalog: EmbeddingModelCatalog.curated,
            provider: SimulatedHubModelProvider(catalog: EmbeddingModelCatalog.curated, sizes: [:], installedIDs: []),
            registryStore: InMemoryModelRegistryStore(),
            selection: InMemorySummarySettingsRepository()
        )
    }
}
