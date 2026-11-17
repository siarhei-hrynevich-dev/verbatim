import Foundation
import os

/// The search index in the application's SQLite database, on a connection of its own. Chunks and their full-text index
/// are written in one transaction; vectors are kept in a table by embedding space and searched in memory.
actor SQLiteSearchIndexRepository: SearchIndexRepository {
    private let databaseURL: URL
    private var openDatabase: SQLiteDatabase?
    /// The vectors of the space searched last, loaded on the first search and dropped with any change to the index.
    var cachedMatrix: (space: EmbeddingSpace, matrix: VectorMatrix)?

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    // MARK: - Chunks

    func indexState(for recordingID: UUID) throws -> SearchIndexState {
        try perform { database in
            let rows = try database.query(
                "SELECT * FROM search_index_state WHERE recording_id = ?",
                bindings: [.text(recordingID.uuidString)]
            )
            guard let row = rows.first else {
                return .empty
            }
            return SearchIndexState(
                transcriptCreatedAt: row.integer("transcript_created_at").map(Self.date(fromMilliseconds:)),
                summaryCreatedAt: row.integer("summary_created_at").map(Self.date(fromMilliseconds:))
            )
        }
    }

    /// `IS NOT` treats two absent values as equal, so a recording with neither a transcript nor chunks is up to date.
    func recordingsWithOutdatedChunks() throws -> [UUID] {
        try perform { database in
            try database.query(
                """
                SELECT r.id AS recording_id FROM recordings r
                LEFT JOIN transcripts t ON t.recording_id = r.id
                LEFT JOIN summaries s ON s.recording_id = r.id
                LEFT JOIN search_index_state i ON i.recording_id = r.id
                WHERE t.created_at IS NOT i.transcript_created_at OR s.created_at IS NOT i.summary_created_at
                ORDER BY r.created_at DESC
                """
            )
            .compactMap(Self.recordingID(from:))
        }
    }

    func replaceChunks(
        _ chunks: [SearchChunk],
        ofKinds kinds: Set<SearchChunkKind>,
        for recordingID: UUID,
        state: SearchIndexState
    ) throws {
        try perform { database in
            try database.transaction {
                let key = SQLiteDatabase.Value.text(recordingID.uuidString)
                let owners = try database.query("SELECT 1 AS found FROM recordings WHERE id = ?", bindings: [key])
                guard !owners.isEmpty else {
                    throw LibraryError.recordingNotFound
                }
                let kindList = kinds.sorted { $0.rawValue < $1.rawValue }
                let kindPlaceholders = Self.placeholders(kindList.count)
                try database.execute(
                    "DELETE FROM search_chunks WHERE recording_id = ? AND kind IN (\(kindPlaceholders))",
                    bindings: [key] + kindList.map { .text($0.rawValue) }
                )
                for chunk in chunks where kinds.contains(chunk.kind) {
                    try Self.insert(chunk, in: database)
                }
                try Self.saveState(state, of: recordingID, in: database)
            }
        }
        cachedMatrix = nil
    }

    func deleteIndex(for recordingID: UUID) throws {
        try perform { database in
            try database.transaction {
                let key = SQLiteDatabase.Value.text(recordingID.uuidString)
                try database.execute("DELETE FROM search_chunks WHERE recording_id = ?", bindings: [key])
                try database.execute("DELETE FROM search_index_state WHERE recording_id = ?", bindings: [key])
            }
        }
        cachedMatrix = nil
    }

    func purgeOrphans() throws {
        try perform { database in
            try database.transaction {
                try database.execute(
                    "DELETE FROM search_chunks WHERE recording_id NOT IN (SELECT id FROM recordings)"
                )
                try database.execute(
                    "DELETE FROM search_index_state WHERE recording_id NOT IN (SELECT id FROM recordings)"
                )
            }
        }
        cachedMatrix = nil
    }

    // MARK: - Vectors

    func pendingEmbeddings(for recordingID: UUID, in space: EmbeddingSpace) throws -> [PendingEmbedding] {
        try perform { database in
            let spaceID = try Self.spaceID(of: space, in: database, creating: false) ?? -1
            return try database.query(
                """
                SELECT c.id, c.text FROM search_chunks c
                WHERE c.recording_id = ? AND NOT EXISTS (
                    SELECT 1 FROM chunk_embeddings e WHERE e.chunk_id = c.id AND e.space_id = ?
                )
                ORDER BY c.kind, c.position
                """,
                bindings: [.text(recordingID.uuidString), .integer(spaceID)]
            )
            .compactMap { row in
                guard let id = row.integer("id"), let text = row.text("text") else {
                    return nil
                }
                return PendingEmbedding(chunkID: id, text: text)
            }
        }
    }

    func recordingsWithPendingEmbeddings(in space: EmbeddingSpace) throws -> [UUID] {
        try perform { database in
            let spaceID = try Self.spaceID(of: space, in: database, creating: false) ?? -1
            return try database.query(
                """
                SELECT c.recording_id FROM search_chunks c
                JOIN recordings r ON r.id = c.recording_id
                WHERE NOT EXISTS (SELECT 1 FROM chunk_embeddings e WHERE e.chunk_id = c.id AND e.space_id = ?)
                GROUP BY c.recording_id
                ORDER BY MAX(r.created_at) DESC
                """,
                bindings: [.integer(spaceID)]
            )
            .compactMap(Self.recordingID(from:))
        }
    }

    /// The insert selects the chunk, so a vector whose chunk was replaced since it was read is quietly not stored.
    func storeEmbeddings(_ vectors: [Int64: [Float]], in space: EmbeddingSpace) throws {
        guard !vectors.isEmpty else {
            return
        }
        try perform { database in
            try database.transaction {
                guard let spaceID = try Self.spaceID(of: space, in: database, creating: true) else {
                    return
                }
                for (chunkID, vector) in vectors.sorted(by: { $0.key < $1.key }) {
                    guard vector.count == space.dimensions else {
                        throw LibraryError.persistenceFailed(detail: "A vector does not match its embedding space")
                    }
                    try database.execute(
                        """
                        INSERT OR REPLACE INTO chunk_embeddings (space_id, chunk_id, vector)
                        SELECT ?, id, ? FROM search_chunks WHERE id = ?
                        """,
                        bindings: [.integer(spaceID), .blob(VectorMatrix.blob(from: vector)), .integer(chunkID)]
                    )
                }
            }
        }
        cachedMatrix = nil
    }

    func removeEmbeddings(outside space: EmbeddingSpace) throws {
        try perform { database in
            try database.execute(
                "DELETE FROM embedding_spaces WHERE NOT (model_id = ? AND revision = ? AND dimensions = ?)",
                bindings: [.text(space.modelID), .text(space.revision), .integer(Int64(space.dimensions))]
            )
        }
        if cachedMatrix?.space != space {
            cachedMatrix = nil
        }
    }

    // MARK: - Rows

    private static func insert(_ chunk: SearchChunk, in database: SQLiteDatabase) throws {
        try database.execute(
            """
            INSERT INTO search_chunks (
                recording_id, kind, position, start_time, end_time, first_segment, last_segment, text
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(chunk.recordingID.uuidString),
                .text(chunk.kind.rawValue),
                .integer(Int64(chunk.position)),
                chunk.timeSpan.map { .real($0.lowerBound) } ?? .null,
                chunk.timeSpan.map { .real($0.upperBound) } ?? .null,
                chunk.segments.map { .integer(Int64($0.lowerBound)) } ?? .null,
                chunk.segments.map { .integer(Int64($0.upperBound)) } ?? .null,
                .text(chunk.text)
            ]
        )
    }

    private static func saveState(_ state: SearchIndexState, of recordingID: UUID, in database: SQLiteDatabase) throws {
        try database.execute(
            """
            INSERT INTO search_index_state (recording_id, transcript_created_at, summary_created_at, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT (recording_id) DO UPDATE SET
                transcript_created_at = excluded.transcript_created_at,
                summary_created_at = excluded.summary_created_at,
                updated_at = excluded.updated_at
            """,
            bindings: [
                .text(recordingID.uuidString),
                state.transcriptCreatedAt.map { .integer(milliseconds(since: $0)) } ?? .null,
                state.summaryCreatedAt.map { .integer(milliseconds(since: $0)) } ?? .null,
                .integer(milliseconds(since: .now))
            ]
        )
    }

    static func spaceID(of space: EmbeddingSpace, in database: SQLiteDatabase, creating: Bool) throws -> Int64? {
        let bindings: [SQLiteDatabase.Value] = [
            .text(space.modelID), .text(space.revision), .integer(Int64(space.dimensions))
        ]
        let select = "SELECT id FROM embedding_spaces WHERE model_id = ? AND revision = ? AND dimensions = ?"
        if let id = try database.query(select, bindings: bindings).first?.integer("id") {
            return id
        }
        guard creating else {
            return nil
        }
        try database.execute(
            "INSERT INTO embedding_spaces (model_id, revision, dimensions, created_at) VALUES (?, ?, ?, ?)",
            bindings: bindings + [.integer(milliseconds(since: .now))]
        )
        return try database.query(select, bindings: bindings).first?.integer("id")
    }

    static func recordingID(from row: SQLiteDatabase.Row) -> UUID? {
        row.text("recording_id").flatMap(UUID.init(uuidString:))
    }

    static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    // MARK: - Connection

    func perform<Result>(_ body: (SQLiteDatabase) throws -> Result) throws -> Result {
        let database = try connection()
        do {
            return try body(database)
        } catch let error as LibraryError {
            throw error
        } catch let failure as SQLiteDatabase.Failure {
            Self.logger.error("A search index statement failed with code \(failure.code)")
            throw LibraryError.persistenceFailed(detail: failure.message)
        }
    }

    private func connection() throws -> SQLiteDatabase {
        if let openDatabase {
            return openDatabase
        }
        let database = try LibrarySchema.open(at: databaseURL)
        openDatabase = database
        return database
    }

    static func milliseconds(since date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    static func date(fromMilliseconds milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    static let logger = Logger(category: "Search")
}
