import Foundation
import os

/// Transcripts and the job queue in the application's SQLite database, on a connection of their own.
///
/// One actor serves both contracts because a job's state and the recording status it decides are written together,
/// and the status depends on whether a transcript exists.
actor SQLiteTranscriptRepository: TranscriptRepository, ProcessingJobRepository {
    private let databaseURL: URL
    private var openDatabase: SQLiteDatabase?

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    // MARK: - TranscriptRepository

    func transcript(for recordingID: UUID) throws -> Transcript? {
        try perform { database in
            let key = SQLiteDatabase.Value.text(Self.key(for: recordingID))
            guard
                let row = try database.query("SELECT * FROM transcripts WHERE recording_id = ?", bindings: [key]).first,
                let modelID = row.text("model_id"),
                let createdAt = row.integer("created_at")
            else {
                return nil
            }
            let rows = try database.query(
                "SELECT * FROM transcript_segments WHERE recording_id = ? ORDER BY position",
                bindings: [key]
            )
            return Transcript(
                recordingID: recordingID,
                modelID: modelID,
                modelVersion: row.text("model_version"),
                language: row.text("language"),
                createdAt: Self.date(fromMilliseconds: createdAt),
                segments: rows.compactMap { Self.segment(from: $0, of: recordingID) }
            )
        }
    }

    func replaceTranscript(_ transcript: Transcript) throws {
        try perform { database in
            try database.transaction {
                let key = SQLiteDatabase.Value.text(Self.key(for: transcript.recordingID))
                let owners = try database.query("SELECT 1 AS found FROM recordings WHERE id = ?", bindings: [key])
                guard !owners.isEmpty else {
                    throw LibraryError.recordingNotFound
                }
                try database.execute("DELETE FROM transcripts WHERE recording_id = ?", bindings: [key])
                try Self.insertHeader(of: transcript, in: database)
                for (position, segment) in transcript.segments.enumerated() {
                    try Self.insert(segment, at: position, in: database)
                }
            }
        }
    }

    func deleteTranscript(for recordingID: UUID) throws {
        try perform { database in
            try database.execute(
                "DELETE FROM transcripts WHERE recording_id = ?",
                bindings: [.text(Self.key(for: recordingID))]
            )
        }
    }

    // MARK: - ProcessingJobRepository

    func allJobs() throws -> [TranscriptionJob] {
        try perform { database in
            try database.query("SELECT * FROM processing_jobs ORDER BY queued_at").compactMap(Self.job(from:))
        }
    }

    func saveJob(_ job: TranscriptionJob) throws {
        try perform { database in
            try database.transaction {
                try Self.upsert(job, in: database)
                try Self.updateRecordingStatus(for: job, in: database)
            }
        }
    }

    func deleteJob(for recordingID: UUID) throws {
        try perform { database in
            try database.execute(
                "DELETE FROM processing_jobs WHERE recording_id = ?",
                bindings: [.text(Self.key(for: recordingID))]
            )
        }
    }

    func purgeOrphans() throws {
        try perform { database in
            try database.transaction {
                try database.executeScript(
                    """
                    DELETE FROM processing_jobs WHERE recording_id NOT IN (SELECT id FROM recordings);
                    DELETE FROM transcripts WHERE recording_id NOT IN (SELECT id FROM recordings);
                    """
                )
            }
        }
    }

    // MARK: - Writing

    private static func insertHeader(of transcript: Transcript, in database: SQLiteDatabase) throws {
        try database.execute(
            """
            INSERT INTO transcripts (recording_id, model_id, model_version, language, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(key(for: transcript.recordingID)),
                .text(transcript.modelID),
                optional(transcript.modelVersion),
                optional(transcript.language),
                .integer(milliseconds(since: transcript.createdAt))
            ]
        )
    }

    private static func insert(_ segment: TranscriptSegment, at position: Int, in database: SQLiteDatabase) throws {
        try database.execute(
            """
            INSERT INTO transcript_segments (id, recording_id, position, start_time, end_time, text, source)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(key(for: segment.id)),
                .text(key(for: segment.recordingID)),
                .integer(Int64(position)),
                .real(segment.startTime),
                .real(segment.endTime),
                .text(segment.text),
                .text(segment.source.rawValue)
            ]
        )
    }

    private static func upsert(_ job: TranscriptionJob, in database: SQLiteDatabase) throws {
        try database.execute(
            """
            INSERT OR REPLACE INTO processing_jobs (
                recording_id, state, queued_at, updated_at, attempts, model_id, failure, export_failure
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(key(for: job.recordingID)),
                .text(job.state.rawValue),
                .integer(milliseconds(since: job.queuedAt)),
                .integer(milliseconds(since: job.updatedAt)),
                .integer(Int64(job.attempts)),
                optional(job.modelID),
                optional(try encoded(job.failure)),
                optional(job.exportFailureDetail)
            ]
        )
    }

    private static func updateRecordingStatus(for job: TranscriptionJob, in database: SQLiteDatabase) throws {
        let key = SQLiteDatabase.Value.text(key(for: job.recordingID))
        let stored = try database.query("SELECT 1 AS found FROM transcripts WHERE recording_id = ?", bindings: [key])
        let status = job.state.recordingStatus(hasTranscript: !stored.isEmpty)
        try database.execute(
            "UPDATE recordings SET processing_status = ? WHERE id = ?",
            bindings: [.text(status.rawValue), key]
        )
    }

    private static func encoded(_ failure: TranscriptionFailure?) throws -> String? {
        guard let failure else {
            return nil
        }
        return String(bytes: try JSONEncoder().encode(failure), encoding: .utf8)
    }

    // MARK: - Reading

    /// Rows come from a file on disk, so they are validated like any stored input. A segment or job that cannot be
    /// understood is logged and skipped.
    private static func segment(from row: SQLiteDatabase.Row, of recordingID: UUID) -> TranscriptSegment? {
        guard let id = row.text("id").flatMap(UUID.init(uuidString:)),
            let start = row.real("start_time"),
            let end = row.real("end_time"),
            let text = row.text("text"),
            let segment = TranscriptSegment(
                id: id,
                recordingID: recordingID,
                startTime: start,
                endTime: end,
                text: text,
                source: row.text("source").flatMap(TranscriptSource.init(rawValue:)) ?? .unknown
            )
        else {
            logger.error("Skipped an unreadable transcript segment")
            return nil
        }
        return segment
    }

    private static func job(from row: SQLiteDatabase.Row) -> TranscriptionJob? {
        guard let recordingID = row.text("recording_id").flatMap(UUID.init(uuidString:)),
            let state = row.text("state").flatMap(TranscriptionJob.State.init(rawValue:)),
            let queuedAt = row.integer("queued_at"),
            let updatedAt = row.integer("updated_at")
        else {
            logger.error("Skipped an unreadable transcription job")
            return nil
        }
        return TranscriptionJob(
            recordingID: recordingID,
            state: state,
            queuedAt: date(fromMilliseconds: queuedAt),
            updatedAt: date(fromMilliseconds: updatedAt),
            attempts: Int(row.integer("attempts") ?? 0),
            modelID: row.text("model_id"),
            failure: failure(in: row, state: state),
            exportFailureDetail: row.text("export_failure")
        )
    }

    /// A failure this version cannot read, as after downgrading, still counts as one.
    private static func failure(in row: SQLiteDatabase.Row, state: TranscriptionJob.State) -> TranscriptionFailure? {
        guard let stored = row.text("failure") else {
            return state == .failed ? .recognitionFailed(detail: "") : nil
        }
        do {
            return try JSONDecoder().decode(TranscriptionFailure.self, from: Data(stored.utf8))
        } catch {
            logger.error("Could not read a stored transcription failure: \(String(describing: error))")
            return .recognitionFailed(detail: "")
        }
    }

    // MARK: - Connection

    private func perform<Result>(_ body: (SQLiteDatabase) throws -> Result) throws -> Result {
        let database = try connection()
        do {
            return try body(database)
        } catch let error as LibraryError {
            throw error
        } catch let failure as SQLiteDatabase.Failure {
            Self.logger.error("A transcript statement failed with code \(failure.code)")
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

    private static func optional(_ text: String?) -> SQLiteDatabase.Value {
        text.map(SQLiteDatabase.Value.text) ?? .null
    }

    private static func key(for id: UUID) -> String {
        id.uuidString
    }

    private static func milliseconds(since date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    private static func date(fromMilliseconds milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    private static let logger = Logger(subsystem: "dev.local.Recorder", category: "Transcription")
}
