import Foundation

/// Narrows a search to some recordings. Every condition given must hold; an empty filter allows everything.
struct RecordingSearchFilter: Equatable, Sendable {
    var recordingIDs: Set<UUID>?
    /// Recordings made at or after this moment.
    var createdFrom: Date?
    /// Recordings made before this moment.
    var createdBefore: Date?
    /// Recordings with at least one of these tags.
    var tagIDs: Set<UUID>?
    var kinds: Set<SearchChunkKind>?

    var isEmpty: Bool {
        self == RecordingSearchFilter()
    }
}

/// A question asked of the recordings, in words: a phrase to look up or a question in natural language.
struct RecordingSearchQuery: Equatable, Sendable {
    var text: String
    var filter = RecordingSearchFilter()
    var limit = 10
}

/// How a result was found. Both means the words and the meaning agreed, which ranks it higher.
enum SearchMatch: Hashable, Sendable {
    /// Its meaning is close to the query's, by embedding vectors.
    case semantic
    /// It contains words of the query, by the full-text index.
    case lexical
}

/// A chunk scored by one kind of search, best first.
struct ScoredChunk: Equatable, Sendable {
    let chunkID: Int64
    /// Cosine similarity for semantic search, from -1 to 1; the BM25 rank for lexical search, lower being better.
    let score: Double
}

/// A stored chunk with what a result shows of its recording.
struct SearchChunkRecord: Equatable, Sendable {
    let chunkID: Int64
    let chunk: SearchChunk
    let recordingTitle: String
    let recordingCreatedAt: Date
}

/// One place in one recording that answers a query.
struct RecordingSearchHit: Identifiable, Equatable, Sendable {
    let record: SearchChunkRecord
    /// Reciprocal rank fusion of the searches that found it: only the order matters, not the scale.
    let relevance: Double
    let matches: Set<SearchMatch>
    /// The cosine similarity to the query, when semantic search found it.
    let similarity: Double?

    var id: Int64 {
        record.chunkID
    }
}

/// Why search by meaning was or was not part of a result. Search by words always is.
enum SemanticSearchStatus: Equatable, Sendable {
    case used(EmbeddingSpace)
    case noModel
    /// The selected model's files are missing or damaged.
    case modelUnavailable(EmbeddingModel.ID)
    /// No model is loaded while recording.
    case pausedForRecording
    case failed(detail: String)
}

struct RecordingSearchResult: Equatable, Sendable {
    let hits: [RecordingSearchHit]
    let semanticStatus: SemanticSearchStatus
}

/// Combines ranked lists from different searches by reciprocal rank fusion: each list adds `1 / (k + rank)` for each of
/// its chunks. Scores of different kinds of search are not comparable, while their ranks are.
enum SearchRanking {
    struct Fused: Equatable, Sendable {
        let chunkID: Int64
        let relevance: Double
        let matches: Set<SearchMatch>
    }

    /// 60 is the constant of the original method: it keeps a top result of one list from outweighing agreement.
    static let fusionConstant = 60.0

    static func fused(_ lists: [SearchMatch: [ScoredChunk]]) -> [Fused] {
        var relevance: [Int64: Double] = [:]
        var matches: [Int64: Set<SearchMatch>] = [:]
        for (match, chunks) in lists {
            for (rank, chunk) in chunks.enumerated() {
                relevance[chunk.chunkID, default: 0] += 1 / (fusionConstant + Double(rank + 1))
                matches[chunk.chunkID, default: []].insert(match)
            }
        }
        return
            relevance
            .map { Fused(chunkID: $0.key, relevance: $0.value, matches: matches[$0.key] ?? []) }
            .sorted { ($0.relevance, $1.chunkID) > ($1.relevance, $0.chunkID) }
    }
}

/// Why indexing a recording failed. Stopping on request is not a failure. User-facing wording belongs to Presentation.
enum IndexingFailure: Error, Equatable, Sendable {
    case noModelSelected
    case modelUnavailable(EmbeddingModel.ID)
    case modelLoadFailed(detail: String)
    case embeddingFailed(detail: String)
    case persistenceFailed(detail: String)

    /// Translates what the steps of indexing can throw. Cancellation has to be handled before this.
    init(_ error: any Error) {
        switch error {
        case let failure as IndexingFailure:
            self = failure
        case ModelManagementError.noModelSelected:
            self = .noModelSelected
        case ModelManagementError.selectedModelUnavailable(let id):
            self = .modelUnavailable(id)
        case let error as LibraryError:
            self = .persistenceFailed(detail: String(describing: error))
        default:
            self = .embeddingFailed(detail: error.localizedDescription)
        }
    }
}

/// Indexing one recording for search, while it is queued or running. Jobs live in memory only: the index records what
/// it was made from, so whatever is missing or out of date is found and queued again at launch.
struct IndexingJob: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case queued
        case chunking
        /// Embedding chunk `completed + 1` of `total`.
        case embedding(completed: Int, total: Int)
        case failed(IndexingFailure)

        var isActive: Bool {
            if case .failed = self {
                return false
            }
            return true
        }
    }

    let recordingID: UUID
    var state: State
    var queuedAt: Date
}
