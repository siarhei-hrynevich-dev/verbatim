import Foundation

/// Whether text is a question asked of the index or content stored in it. Models of the E5 family are trained to see
/// each with its own prefix; asymmetric search works noticeably worse without them.
enum EmbeddingRole: Sendable {
    case query
    case passage
}

/// A model ready to turn text into vectors. The boundary indexing and search depend on: an MLX model on this Mac
/// today, and equally a local server or a provider's API.
protocol TextEmbedder: Sendable {
    /// One vector per text, in order, each of the space's length and normalized to length 1. Text longer than the model
    /// reads is cut. Throws `CancellationError` once cancelled, between texts.
    func embed(_ texts: [String], as role: EmbeddingRole) async throws -> [[Float]]
}

/// An embedder handed to one user of it, with the space its vectors belong to. Given back through its provider.
struct EmbeddingSession: Sendable {
    let id: UUID
    let space: EmbeddingSpace
    let embedder: any TextEmbedder
}

/// Where indexing and search get an embedder, and give it back. The model stays loaded for a short while after its last
/// session ends, so consecutive jobs and an agent's follow-up questions do not load it each time.
@MainActor
protocol EmbeddingProvider: AnyObject {
    /// The space of the selected model when it can be used now; `nil` otherwise. Observable, so waiting work can start
    /// once a model is installed and selected.
    var readySpace: EmbeddingSpace? { get }
    var isRecordingActive: Bool { get }
    /// Brings model state in line with the disk, so files removed since launch are noticed before they are needed.
    func prepareForUse() async
    /// Throws `IndexingFailure`, or `CancellationError`. Nothing is switched or downloaded.
    func acquireEmbedder() async throws -> EmbeddingSession
    func release(sessionID: UUID)
    /// While recording, nothing is loaded: the model goes as soon as its last session ends, and none is handed out.
    func setRecordingActive(_ isActive: Bool)
}

/// Loads installed embedding models into memory. Implemented with MLX.
protocol LocalEmbeddingRuntime: Sendable {
    /// Throws when the files cannot be loaded. Never downloads anything.
    func loadEmbedder(for model: ResolvedEmbeddingModel) async throws -> any TextEmbedder
    /// Returns memory the engine keeps cached after its models are gone. Safe to call with nothing loaded.
    func releaseMemory() async
}

/// A chunk that still needs a vector in some space.
struct PendingEmbedding: Equatable, Sendable {
    let chunkID: Int64
    let text: String
}

/// The search index: chunks of every recording's transcript and summary, their full-text index and their vectors. All
/// of it is derived from transcripts and summaries and can be made again. Throws `LibraryError`.
protocol SearchIndexRepository: Sendable {
    func indexState(for recordingID: UUID) async throws -> SearchIndexState
    /// Recordings whose transcript or summary is newer than their chunks, or whose chunks are left from content that is
    /// gone, among those still in the Library.
    func recordingsWithOutdatedChunks() async throws -> [UUID]
    /// Swaps in a recording's chunks of the given kinds and the state they were made from, in one transaction. The
    /// replaced chunks' vectors go with them. Throws `LibraryError.recordingNotFound` once it has left the Library.
    func replaceChunks(
        _ chunks: [SearchChunk],
        ofKinds kinds: Set<SearchChunkKind>,
        for recordingID: UUID,
        state: SearchIndexState
    ) async throws

    /// Chunks of the recording without a vector in the space, in order.
    func pendingEmbeddings(for recordingID: UUID, in space: EmbeddingSpace) async throws -> [PendingEmbedding]
    /// Recordings still in the Library with chunks that have no vector in the space.
    func recordingsWithPendingEmbeddings(in space: EmbeddingSpace) async throws -> [UUID]
    /// Stores vectors of chunks that still exist; one whose chunk was replaced meanwhile is dropped.
    func storeEmbeddings(_ vectors: [Int64: [Float]], in space: EmbeddingSpace) async throws
    /// Forgets the vectors of every other space, once a model is no longer selected.
    func removeEmbeddings(outside space: EmbeddingSpace) async throws

    /// The chunks closest in meaning to a normalized query vector, most similar first.
    func nearestChunks(
        to vector: [Float],
        in space: EmbeddingSpace,
        filter: RecordingSearchFilter,
        limit: Int
    ) async throws -> [ScoredChunk]
    /// The chunks that contain words of the query, best first. Words are matched as given and as prefixes.
    func chunksMatching(_ text: String, filter: RecordingSearchFilter, limit: Int) async throws -> [ScoredChunk]
    /// The chunks and what a result shows of their recordings. Chunks of recordings no longer in the Library are left
    /// out.
    func records(for chunkIDs: [Int64]) async throws -> [Int64: SearchChunkRecord]

    func deleteIndex(for recordingID: UUID) async throws
    /// Forgets the index of recordings no longer in the Library, which stays until then so that Undo brings it back.
    func purgeOrphans() async throws
}
