import Foundation
import os

/// Summaries and their parts in the application's SQLite database, on a connection of their own.
actor SQLiteSummaryRepository: SummaryRepository {
    private let databaseURL: URL
    private var openDatabase: SQLiteDatabase?

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    func summary(for recordingID: UUID) throws -> TranscriptSummary? {
        try perform { database in
            let key = SQLiteDatabase.Value.text(recordingID.uuidString)
            guard
                let row = try database.query("SELECT * FROM summaries WHERE recording_id = ?", bindings: [key]).first,
                let modelID = row.text("model_id"),
                let text = row.text("text"),
                let transcriptCreatedAt = row.integer("transcript_created_at"),
                let createdAt = row.integer("created_at")
            else {
                return nil
            }
            let parts = try database.query(
                "SELECT * FROM summary_parts WHERE recording_id = ? ORDER BY position",
                bindings: [key]
            )
            return TranscriptSummary(
                recordingID: recordingID,
                modelID: modelID,
                language: row.text("language"),
                transcriptCreatedAt: Self.date(fromMilliseconds: transcriptCreatedAt),
                createdAt: Self.date(fromMilliseconds: createdAt),
                text: text,
                parts: parts.compactMap(Self.part(from:))
            )
        }
    }

    func replaceSummary(_ summary: TranscriptSummary) throws {
        try perform { database in
            try database.transaction {
                let key = SQLiteDatabase.Value.text(summary.recordingID.uuidString)
                let owners = try database.query("SELECT 1 AS found FROM recordings WHERE id = ?", bindings: [key])
                guard !owners.isEmpty else {
                    throw LibraryError.recordingNotFound
                }
                try database.execute("DELETE FROM summaries WHERE recording_id = ?", bindings: [key])
                try Self.insertHeader(of: summary, in: database)
                for part in summary.parts {
                    try Self.insert(part, of: summary.recordingID, in: database)
                }
            }
        }
    }

    func deleteSummary(for recordingID: UUID) throws {
        try perform { database in
            try database.execute(
                "DELETE FROM summaries WHERE recording_id = ?",
                bindings: [.text(recordingID.uuidString)]
            )
        }
    }

    func purgeOrphans() throws {
        try perform { database in
            try database.execute("DELETE FROM summaries WHERE recording_id NOT IN (SELECT id FROM recordings)")
        }
    }

    // MARK: - Rows

    private static func insertHeader(of summary: TranscriptSummary, in database: SQLiteDatabase) throws {
        try database.execute(
            """
            INSERT INTO summaries (recording_id, model_id, language, transcript_created_at, created_at, text)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(summary.recordingID.uuidString),
                .text(summary.modelID),
                summary.language.map(SQLiteDatabase.Value.text) ?? .null,
                .integer(milliseconds(since: summary.transcriptCreatedAt)),
                .integer(milliseconds(since: summary.createdAt)),
                .text(summary.text)
            ]
        )
    }

    private static func insert(_ part: SummaryPart, of recordingID: UUID, in database: SQLiteDatabase) throws {
        try database.execute(
            """
            INSERT INTO summary_parts (
                recording_id, position, start_time, end_time, first_segment, last_segment, text
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(recordingID.uuidString),
                .integer(Int64(part.position)),
                .real(part.startTime),
                .real(part.endTime),
                .integer(Int64(part.firstSegment)),
                .integer(Int64(part.lastSegment)),
                .text(part.text)
            ]
        )
    }

    /// Rows come from a file on disk; one that cannot describe a part is logged and skipped.
    private static func part(from row: SQLiteDatabase.Row) -> SummaryPart? {
        guard let position = row.integer("position"),
            let start = row.real("start_time"),
            let end = row.real("end_time"),
            let first = row.integer("first_segment"),
            let last = row.integer("last_segment"),
            let text = row.text("text")
        else {
            logger.error("Skipped an unreadable summary part")
            return nil
        }
        return SummaryPart(
            position: Int(position),
            startTime: start,
            endTime: end,
            firstSegment: Int(first),
            lastSegment: Int(last),
            text: text
        )
    }

    // MARK: - Connection

    private func perform<Result>(_ body: (SQLiteDatabase) throws -> Result) throws -> Result {
        let database = try connection()
        do {
            return try body(database)
        } catch let error as LibraryError {
            throw error
        } catch let failure as SQLiteDatabase.Failure {
            Self.logger.error("A summary statement failed with code \(failure.code)")
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

    private static func milliseconds(since date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    private static func date(fromMilliseconds milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    private static let logger = Logger(category: "Summaries")
}
