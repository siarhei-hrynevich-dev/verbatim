import Foundation
import Synchronization

@testable import Verbatim

/// Records what the controller asks of the server, and fails a start when told to.
final class FakeAgentServerHost: AgentServerHosting {
    struct Start: Equatable {
        let port: Int
        let token: String
    }

    private struct Log {
        var starts: [Start] = []
        var stops = 0
        var failure: AgentServerFailure?
        var isRunning = false
    }

    private let state = Mutex(Log())

    var starts: [Start] {
        state.withLock { $0.starts }
    }

    var stops: Int {
        state.withLock { $0.stops }
    }

    var isRunning: Bool {
        state.withLock { $0.isRunning }
    }

    func failNextStart(with failure: AgentServerFailure) {
        state.withLock { $0.failure = failure }
    }

    func start(port: Int, token: String) async throws -> Int {
        try state.withLock { state in
            state.starts.append(Start(port: port, token: token))
            if let failure = state.failure {
                state.failure = nil
                throw failure
            }
            state.isRunning = true
        }
        return port
    }

    func stop() async {
        state.withLock { state in
            state.stops += 1
            state.isRunning = false
        }
    }
}

final class InMemoryAgentServerSettingsRepository: AgentServerSettingsRepository {
    private let stored: Mutex<AgentServerSettings?>

    init(_ settings: AgentServerSettings? = nil) {
        stored = Mutex(settings)
    }

    var settings: AgentServerSettings? {
        stored.withLock { $0 }
    }

    func loadSettings() -> AgentServerSettings? {
        stored.withLock { $0 }
    }

    func saveSettings(_ settings: AgentServerSettings) {
        stored.withLock { $0 = settings }
    }
}

@MainActor
final class ActivityBoard {
    var jobs: [UUID: RecordingActivity] = [:]
}

/// A real Library database, indexed with the fake embedding model, behind the service agents read through.
@MainActor
final class KnowledgeTestEnvironment {
    let search: SearchTestEnvironment
    let embeddings = FakeEmbeddingProvider()
    /// What the coordinators would report for each recording; tests set it.
    let activity = ActivityBoard()
    let knowledge: RecordingKnowledgeService

    init() throws {
        search = try SearchTestEnvironment()
        let activity = activity
        knowledge = RecordingKnowledgeService(
            dependencies: RecordingKnowledgeService.Dependencies(
                recordings: search.recordings,
                transcripts: search.transcripts,
                summaries: search.summaries,
                index: search.index,
                search: RecordingSearchService(index: search.index, embeddings: embeddings),
                activity: { id in activity.jobs[id] ?? RecordingActivity() }
            )
        )
    }

    /// A recording with a transcript of the lines, made at the given time, optionally tagged.
    func addRecording(
        title: String,
        createdAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
        mode: CaptureMode = .screen,
        tags: Set<UUID> = [],
        lines: [String]?
    ) async throws -> LibraryRecording {
        var recording = try search.environment.makeRecording(title: title, createdAt: createdAt, mode: mode)
        recording.tagIDs = tags
        try await search.recordings.insert(recording)
        if let lines {
            try await search.transcripts.replaceTranscript(SearchFixtures.transcript(of: recording.id, lines: lines))
        }
        return recording
    }

    func addTag(_ name: String) async throws -> RecordingTag {
        let tag = RecordingTag(id: UUID(), name: name, color: .orange)
        try await search.recordings.insertTag(tag)
        return tag
    }

    /// Chunks and vectors for the recordings, as the indexing queue makes them.
    func index(_ ids: [UUID]) async {
        let coordinator = IndexingCoordinator(
            dependencies: IndexingCoordinator.Dependencies(
                transcripts: search.transcripts,
                summaries: search.summaries,
                index: search.index,
                embeddings: embeddings,
                isPostProcessingBusy: { false }
            )
        )
        for id in ids {
            coordinator.enqueue(id)
        }
        await coordinator.waitUntilSettled()
    }
}
