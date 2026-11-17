import Foundation

/// Reading the index: nearest vectors, full-text matches and the chunks behind them. Every query joins `recordings`, so
/// chunks of a removed recording are never found, even while its removal can still be undone.
extension SQLiteSearchIndexRepository {
    func nearestChunks(
        to vector: [Float],
        in space: EmbeddingSpace,
        filter: RecordingSearchFilter,
        limit: Int
    ) throws -> [ScoredChunk] {
        let matrix = try matrix(of: space)
        let allowed = try perform { database in
            let condition = Self.condition(for: filter)
            return Set(
                try database.query(
                    """
                    SELECT c.id FROM search_chunks c JOIN recordings r ON r.id = c.recording_id
                    WHERE \(condition.sql)
                    """,
                    bindings: condition.bindings
                )
                .compactMap { $0.integer("id") }
            )
        }
        return matrix.nearest(to: vector, limit: limit, isAllowed: allowed.contains)
            .map { ScoredChunk(chunkID: $0.chunkID, score: Double($0.score)) }
    }

    func chunksMatching(_ text: String, filter: RecordingSearchFilter, limit: Int) throws -> [ScoredChunk] {
        guard let expression = Self.fullTextExpression(for: text) else {
            return []
        }
        return try perform { database in
            let condition = Self.condition(for: filter)
            return try database.query(
                """
                SELECT c.id, bm25(search_chunks_fts) AS rank
                FROM search_chunks_fts
                JOIN search_chunks c ON c.id = search_chunks_fts.rowid
                JOIN recordings r ON r.id = c.recording_id
                WHERE search_chunks_fts MATCH ? AND \(condition.sql)
                ORDER BY rank, c.id
                LIMIT ?
                """,
                bindings: [.text(expression)] + condition.bindings + [.integer(Int64(limit))]
            )
            .compactMap { row in
                guard let id = row.integer("id"), let rank = row.real("rank") else {
                    return nil
                }
                return ScoredChunk(chunkID: id, score: rank)
            }
        }
    }

    func records(for chunkIDs: [Int64]) throws -> [Int64: SearchChunkRecord] {
        guard !chunkIDs.isEmpty else {
            return [:]
        }
        return try perform { database in
            let rows = try database.query(
                """
                SELECT c.*, r.title AS recording_title, r.created_at AS recording_created_at
                FROM search_chunks c JOIN recordings r ON r.id = c.recording_id
                WHERE c.id IN (\(Self.placeholders(chunkIDs.count)))
                """,
                bindings: chunkIDs.map { .integer($0) }
            )
            var records: [Int64: SearchChunkRecord] = [:]
            for row in rows {
                if let record = Self.record(from: row) {
                    records[record.chunkID] = record
                }
            }
            return records
        }
    }

    // MARK: - Helpers

    private func matrix(of space: EmbeddingSpace) throws -> VectorMatrix {
        if let cachedMatrix, cachedMatrix.space == space {
            return cachedMatrix.matrix
        }
        let matrix = try perform { database in
            var matrix = VectorMatrix(dimensions: space.dimensions)
            guard let spaceID = try Self.spaceID(of: space, in: database, creating: false) else {
                return matrix
            }
            let rows = try database.query(
                "SELECT chunk_id, vector FROM chunk_embeddings WHERE space_id = ? ORDER BY chunk_id",
                bindings: [.integer(spaceID)]
            )
            for row in rows {
                guard let chunkID = row.integer("chunk_id"), let blob = row.blob("vector"),
                    let vector = VectorMatrix.vector(from: blob)
                else {
                    continue
                }
                matrix.append(chunkID: chunkID, vector: vector)
            }
            return matrix
        }
        cachedMatrix = (space, matrix)
        return matrix
    }

    /// Conditions on `c` (the chunk) and `r` (its recording). Always valid SQL, `1` when nothing narrows the search.
    private static func condition(
        for filter: RecordingSearchFilter
    ) -> (sql: String, bindings: [SQLiteDatabase.Value]) {
        var clauses = ["1"]
        var bindings: [SQLiteDatabase.Value] = []
        if let ids = filter.recordingIDs {
            clauses.append("c.recording_id IN (\(placeholders(ids.count)))")
            bindings += ids.map { .text($0.uuidString) }
        }
        if let createdFrom = filter.createdFrom {
            clauses.append("r.created_at >= ?")
            bindings.append(.integer(milliseconds(since: createdFrom)))
        }
        if let createdBefore = filter.createdBefore {
            clauses.append("r.created_at < ?")
            bindings.append(.integer(milliseconds(since: createdBefore)))
        }
        if let tagIDs = filter.tagIDs {
            clauses.append(
                """
                EXISTS (SELECT 1 FROM recording_tags rt WHERE rt.recording_id = r.id AND rt.tag_id IN (\
                \(placeholders(tagIDs.count))))
                """
            )
            bindings += tagIDs.map { .text($0.uuidString) }
        }
        if let kinds = filter.kinds {
            clauses.append("c.kind IN (\(placeholders(kinds.count)))")
            bindings += kinds.map { .text($0.rawValue) }
        }
        return (clauses.joined(separator: " AND "), bindings)
    }

    /// The query's words, each quoted so that nothing in them is read as FTS5 syntax, and matched as a prefix so that
    /// "deploy" finds "deployment". Any word may match; BM25 ranks chunks with more of them higher. `nil` without
    /// words.
    static func fullTextExpression(for text: String) -> String? {
        let words = text.lowercased()
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
        var seen: Set<String> = []
        let unique = words.filter { seen.insert($0).inserted }
        guard !unique.isEmpty else {
            return nil
        }
        return unique.map { "\"\($0)\"*" }.joined(separator: " OR ")
    }

    private static func record(from row: SQLiteDatabase.Row) -> SearchChunkRecord? {
        guard let chunkID = row.integer("id"),
            let recordingID = recordingID(from: row),
            let kind = row.text("kind").flatMap(SearchChunkKind.init(rawValue:)),
            let position = row.integer("position"),
            let text = row.text("text"),
            let title = row.text("recording_title"),
            let createdAt = row.integer("recording_created_at")
        else {
            logger.error("Skipped an unreadable search chunk")
            return nil
        }
        var timeSpan: ClosedRange<TimeInterval>?
        if let start = row.real("start_time"), let end = row.real("end_time"), end >= start {
            timeSpan = start...end
        }
        var segments: ClosedRange<Int>?
        if let first = row.integer("first_segment"), let last = row.integer("last_segment"), last >= first {
            segments = Int(first)...Int(last)
        }
        return SearchChunkRecord(
            chunkID: chunkID,
            chunk: SearchChunk(
                recordingID: recordingID,
                kind: kind,
                position: Int(position),
                timeSpan: timeSpan,
                segments: segments,
                text: text
            ),
            recordingTitle: title,
            recordingCreatedAt: date(fromMilliseconds: createdAt)
        )
    }
}
