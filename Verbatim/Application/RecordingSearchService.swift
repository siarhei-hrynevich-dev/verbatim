import Foundation
import os

/// Finds places in recordings that answer a query: by meaning through the embedding model, and by words through the
/// full-text index, combined by rank. The entry point for anything that searches recordings, such as an MCP server
/// for AI agents on this Mac.
///
/// Search by words always runs. Search by meaning needs the selected embedding model, which is loaded on demand and
/// shared with indexing, and is skipped while recording; the result says whether it ran and why not.
@MainActor
final class RecordingSearchService {
    private let index: any SearchIndexRepository
    private let embeddings: any EmbeddingProvider

    init(index: any SearchIndexRepository, embeddings: any EmbeddingProvider) {
        self.index = index
        self.embeddings = embeddings
    }

    /// Throws `LibraryError` when the index cannot be read. A failure of the model only leaves meaning out.
    func search(_ query: RecordingSearchQuery) async throws -> RecordingSearchResult {
        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, query.limit > 0 else {
            return RecordingSearchResult(hits: [], semanticStatus: .noModel)
        }
        // Fusion works on ranks, so each search contributes more candidates than are returned.
        let candidateLimit = max(query.limit * Self.candidatesPerResult, Self.minimumCandidates)
        let lexical = try await index.chunksMatching(text, filter: query.filter, limit: candidateLimit)
        let (semantic, status) = try await semanticMatches(of: text, filter: query.filter, limit: candidateLimit)

        let fused = SearchRanking.fused([.lexical: lexical, .semantic: semantic])
        // Some chunks may belong to a recording removed meanwhile; a few spare ones keep the count.
        let considered = fused.prefix(query.limit * 2)
        let records = try await index.records(for: considered.map(\.chunkID))
        let similarities = Dictionary(uniqueKeysWithValues: semantic.map { ($0.chunkID, $0.score) })
        let hits = considered.compactMap { candidate -> RecordingSearchHit? in
            guard let record = records[candidate.chunkID] else {
                return nil
            }
            return RecordingSearchHit(
                record: record,
                relevance: candidate.relevance,
                matches: candidate.matches,
                similarity: similarities[candidate.chunkID]
            )
        }
        return RecordingSearchResult(hits: Array(hits.prefix(query.limit)), semanticStatus: status)
    }

    /// The nearest chunks by meaning, or none with the reason. Only cancellation and index failures are thrown.
    private func semanticMatches(
        of text: String,
        filter: RecordingSearchFilter,
        limit: Int
    ) async throws -> ([ScoredChunk], SemanticSearchStatus) {
        guard !embeddings.isRecordingActive else {
            return ([], .pausedForRecording)
        }
        if embeddings.readySpace == nil {
            await embeddings.prepareForUse()
        }
        let session: EmbeddingSession
        do {
            session = try await embeddings.acquireEmbedder()
        } catch {
            return ([], try Self.status(after: error, isRecordingActive: embeddings.isRecordingActive))
        }
        defer { embeddings.release(sessionID: session.id) }
        let vector: [Float]
        do {
            guard let embedded = try await session.embedder.embed([text], as: .query).first else {
                return ([], .failed(detail: "The model returned no vector"))
            }
            vector = embedded
        } catch {
            return ([], try Self.status(after: error, isRecordingActive: embeddings.isRecordingActive))
        }
        let nearest = try await index.nearestChunks(to: vector, in: session.space, filter: filter, limit: limit)
        return (nearest, .used(session.space))
    }

    private static func status(after error: any Error, isRecordingActive: Bool) throws -> SemanticSearchStatus {
        if error is CancellationError {
            guard isRecordingActive else {
                throw error
            }
            return .pausedForRecording
        }
        switch IndexingFailure(error) {
        case .noModelSelected:
            return .noModel
        case .modelUnavailable(let id):
            return .modelUnavailable(id)
        case let failure:
            logger.error("Search by meaning failed: \(String(describing: failure), privacy: .public)")
            return .failed(detail: String(describing: failure))
        }
    }

    private static let candidatesPerResult = 4
    private static let minimumCandidates = 40
    private static let logger = Logger(category: "Search")
}
