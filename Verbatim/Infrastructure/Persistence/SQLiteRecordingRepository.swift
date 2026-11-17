import Foundation
import os

/// Recording metadata in the application's SQLite database. Media is only ever referenced, never stored here.
///
/// The database opens on first use, so launching does no database work, and a failed open is retried by the next
/// operation. A database that cannot be opened or migrated is left in place: it is reported, never recreated.
actor SQLiteRecordingRepository: RecordingRepository {
    private let databaseURL: URL
    private let migrations: [SQLiteMigration]
    private let now: @Sendable () -> Date
    private var openDatabase: SQLiteDatabase?

    init(
        databaseURL: URL,
        migrations: [SQLiteMigration] = LibrarySchema.migrations,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.databaseURL = databaseURL
        self.migrations = migrations
        self.now = now
    }

    /// `Application Support/Verbatim/Library.sqlite`, inside the app's container when sandboxed.
    static func defaultDatabaseURL() -> URL {
        URL.applicationSupportDirectory.appending(path: "Verbatim/Library.sqlite", directoryHint: .notDirectory)
    }

    // MARK: - RecordingRepository

    func insert(_ recording: LibraryRecording) throws {
        try perform { database in
            try database.transaction {
                try insertRow(of: recording, into: database)
                try writeTags(recording.tagIDs, of: recording.id, in: database)
            }
        }
    }

    private func insertRow(of recording: LibraryRecording, into database: SQLiteDatabase) throws {
        _ = try database.execute(
            """
            INSERT INTO recordings (
                id, title, title_key, created_at, duration, recording_type, media_path, media_bookmark, file_size,
                processing_status, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(Self.key(for: recording.id)),
                .text(recording.recording.title),
                .text(Self.searchKey(for: recording.recording.title)),
                .integer(Self.milliseconds(since: recording.recording.createdAt)),
                .real(recording.recording.duration),
                .text(recording.captureMode.rawValue),
                .text(recording.media.url.path(percentEncoded: false)),
                recording.media.bookmark.map(SQLiteDatabase.Value.blob) ?? .null,
                .integer(recording.fileSizeBytes),
                .text(recording.recording.processingStatus.rawValue),
                .integer(Self.milliseconds(since: now()))
            ]
        )
    }

    func fetch(id: UUID) throws -> LibraryRecording? {
        try perform { database in
            try database.query("\(Self.selection) WHERE id = ?", bindings: [.text(Self.key(for: id))])
                .compactMap(Self.recording(from:))
                .first
        }
    }

    func fetch(matching query: RecordingQuery) throws -> [LibraryRecording] {
        let (condition, bindings) = Self.condition(for: query)
        return try perform { database in
            try database.query(
                "\(Self.selection) \(condition) ORDER BY \(Self.ordering(for: query.sortOrder))",
                bindings: bindings
            )
            .compactMap(Self.recording(from:))
        }
    }

    func count(matching query: RecordingQuery) throws -> Int {
        let (condition, bindings) = Self.condition(for: query)
        return try perform { database in
            let rows = try database.query("SELECT COUNT(*) AS total FROM recordings \(condition)", bindings: bindings)
            return Int(rows.first?.integer("total") ?? 0)
        }
    }

    func totalFileSize() throws -> Int64 {
        try perform { database in
            try database.query("SELECT COALESCE(SUM(file_size), 0) AS total FROM recordings").first?.integer("total")
                ?? 0
        }
    }

    func updateTitle(id: UUID, title: String) throws {
        try requireChange {
            try $0.execute(
                "UPDATE recordings SET title = ?, title_key = ?, updated_at = ? WHERE id = ?",
                bindings: [
                    .text(title),
                    .text(Self.searchKey(for: title)),
                    .integer(Self.milliseconds(since: now())),
                    .text(Self.key(for: id))
                ]
            )
        }
    }

    func updateTags(id: UUID, tagIDs: Set<UUID>) throws {
        try perform { database in
            try database.transaction {
                let exists = try database.query(
                    "SELECT 1 AS found FROM recordings WHERE id = ?",
                    bindings: [.text(Self.key(for: id))]
                )
                guard !exists.isEmpty else {
                    throw LibraryError.recordingNotFound
                }
                try writeTags(tagIDs, of: id, in: database)
            }
        }
    }

    /// Throws `tagNotFound` before changing anything when a tag does not exist.
    private func writeTags(_ tagIDs: Set<UUID>, of id: UUID, in database: SQLiteDatabase) throws {
        let keys = tagIDs.map(Self.key(for:)).sorted()
        if !keys.isEmpty {
            let known = try database.query(
                "SELECT COUNT(*) AS total FROM tags WHERE id IN (\(Self.placeholders(keys.count)))",
                bindings: keys.map { .text($0) }
            )
            guard Int(known.first?.integer("total") ?? 0) == keys.count else {
                throw LibraryError.tagNotFound
            }
        }
        try database.execute("DELETE FROM recording_tags WHERE recording_id = ?", bindings: [.text(Self.key(for: id))])
        for key in keys {
            try database.execute(
                "INSERT INTO recording_tags (recording_id, tag_id) VALUES (?, ?)",
                bindings: [.text(Self.key(for: id)), .text(key)]
            )
        }
    }

    func fetchTags() throws -> [RecordingTag] {
        try perform { database in
            try database.query("SELECT id, name, color FROM tags ORDER BY position, name_key").compactMap { row in
                guard let id = row.text("id").flatMap(UUID.init(uuidString:)), let name = row.text("name"),
                    let color = row.text("color").flatMap(TagColor.init(rawValue:))
                else {
                    Self.logger.error("Skipped an unreadable tag")
                    return nil
                }
                return RecordingTag(id: id, name: name, color: color)
            }
        }
    }

    func insertTag(_ tag: RecordingTag) throws {
        try performOnTag { database in
            try database.execute(
                """
                INSERT INTO tags (id, name, name_key, color, position)
                VALUES (?, ?, ?, ?, (SELECT COALESCE(MAX(position) + 1, 0) FROM tags))
                """,
                bindings: [
                    .text(Self.key(for: tag.id)), .text(tag.name), .text(Self.searchKey(for: tag.name)),
                    .text(tag.color.rawValue)
                ]
            )
        }
    }

    func updateTag(_ tag: RecordingTag) throws {
        let changed = try performOnTag { database in
            try database.execute(
                "UPDATE tags SET name = ?, name_key = ?, color = ? WHERE id = ?",
                bindings: [
                    .text(tag.name), .text(Self.searchKey(for: tag.name)), .text(tag.color.rawValue),
                    .text(Self.key(for: tag.id))
                ]
            )
        }
        guard changed > 0 else {
            throw LibraryError.tagNotFound
        }
    }

    func deleteTag(id: UUID) throws {
        let changed = try perform { database in
            try database.execute("DELETE FROM tags WHERE id = ?", bindings: [.text(Self.key(for: id))])
        }
        guard changed > 0 else {
            throw LibraryError.tagNotFound
        }
    }

    /// A tag's name is unique, so a constraint violation here means the name is taken.
    @discardableResult
    private func performOnTag(_ body: (SQLiteDatabase) throws -> Int) throws -> Int {
        do {
            return try perform(body)
        } catch LibraryError.alreadyInLibrary {
            throw LibraryError.duplicateTagName
        }
    }

    func update(_ recording: LibraryRecording) throws {
        try requireChange {
            try $0.execute(
                """
                UPDATE recordings SET title = ?, title_key = ?, duration = ?, media_path = ?, media_bookmark = ?,
                    file_size = ?, processing_status = ?, updated_at = ?
                WHERE id = ?
                """,
                bindings: [
                    .text(recording.recording.title),
                    .text(Self.searchKey(for: recording.recording.title)),
                    .real(recording.recording.duration),
                    .text(recording.media.url.path(percentEncoded: false)),
                    recording.media.bookmark.map(SQLiteDatabase.Value.blob) ?? .null,
                    .integer(recording.fileSizeBytes),
                    .text(recording.recording.processingStatus.rawValue),
                    .integer(Self.milliseconds(since: now())),
                    .text(Self.key(for: recording.id))
                ]
            )
        }
    }

    func delete(id: UUID) throws {
        try requireChange {
            try $0.execute("DELETE FROM recordings WHERE id = ?", bindings: [.text(Self.key(for: id))])
        }
    }

    // MARK: - Connection

    private func perform<Result>(_ body: (SQLiteDatabase) throws -> Result) throws -> Result {
        let database = try connection()
        do {
            return try body(database)
        } catch let failure as SQLiteDatabase.Failure where failure.isConstraintViolation {
            throw LibraryError.alreadyInLibrary
        } catch let failure as SQLiteDatabase.Failure {
            Self.logger.error("A database statement failed with code \(failure.code)")
            throw LibraryError.persistenceFailed(detail: failure.message)
        }
    }

    private func requireChange(_ statement: (SQLiteDatabase) throws -> Int) throws {
        let changedRows = try perform(statement)
        guard changedRows > 0 else {
            throw LibraryError.recordingNotFound
        }
    }

    private func connection() throws -> SQLiteDatabase {
        if let openDatabase {
            return openDatabase
        }
        let database = try LibrarySchema.open(at: databaseURL, using: migrations)
        openDatabase = database
        return database
    }

}

// MARK: - Mapping and queries

extension SQLiteRecordingRepository {

    /// Rows come from a file on disk, so they are validated like any stored input. A row that cannot describe a
    /// recording is logged and skipped so that it does not take the whole library down.
    private static func recording(from row: SQLiteDatabase.Row) -> LibraryRecording? {
        guard let id = row.text("id").flatMap(UUID.init(uuidString:)),
            let title = row.text("title"),
            let createdAt = row.integer("created_at"),
            let captureMode = row.text("recording_type").flatMap(CaptureMode.init(rawValue:)),
            let path = row.text("media_path"),
            !path.isEmpty
        else {
            logger.error("Skipped an unreadable Library entry")
            return nil
        }
        do {
            let recording = try Recording(
                id: id,
                title: title,
                createdAt: Date(timeIntervalSince1970: Double(createdAt) / 1_000),
                duration: row.real("duration") ?? 0,
                processingStatus: processingStatus(in: row)
            )
            return LibraryRecording(
                recording: recording,
                captureMode: captureMode,
                media: MediaReference(url: URL(fileURLWithPath: path), bookmark: row.blob("media_bookmark")),
                fileSizeBytes: row.integer("file_size") ?? 0,
                hasTranscript: row.integer("has_transcript") == 1,
                tagIDs: Self.tagIDs(in: row)
            )
        } catch {
            logger.error("Skipped an invalid Library entry: \(String(describing: error))")
            return nil
        }
    }

    /// A status this version does not know, as after downgrading, reads as the neutral one rather than losing the
    /// entry.
    private static func processingStatus(in row: SQLiteDatabase.Row) -> Recording.ProcessingStatus {
        row.text("processing_status").flatMap(Recording.ProcessingStatus.init(rawValue:)) ?? .recorded
    }

    private static func tagIDs(in row: SQLiteDatabase.Row) -> Set<UUID> {
        Set((row.text("tag_ids") ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    private static func condition(for query: RecordingQuery) -> (sql: String, bindings: [SQLiteDatabase.Value]) {
        var clauses: [String] = []
        var bindings: [SQLiteDatabase.Value] = []
        if !query.captureModes.isEmpty {
            clauses.append("recording_type IN (\(placeholders(query.captureModes.count)))")
            bindings += query.captureModes.map { .text($0.rawValue) }
        }
        if !query.statuses.isEmpty {
            clauses.append("processing_status IN (\(placeholders(query.statuses.count)))")
            bindings += query.statuses.map { .text($0.rawValue) }
        }
        if let tagID = query.tagID {
            clauses.append("EXISTS (SELECT 1 FROM recording_tags WHERE recording_id = recordings.id AND tag_id = ?)")
            bindings.append(.text(key(for: tagID)))
        }
        if let createdSince = query.createdSince {
            clauses.append("created_at >= ?")
            bindings.append(.integer(milliseconds(since: createdSince)))
        }
        if let search = query.search {
            var searchClause = #"title_key LIKE ? ESCAPE '\'"#
            bindings.append(.text("%\(escapedForLike(searchKey(for: search.text)))%"))
            if let interval = search.recordedDuring {
                searchClause += " OR (created_at >= ? AND created_at < ?)"
                bindings.append(.integer(milliseconds(since: interval.start)))
                bindings.append(.integer(milliseconds(since: interval.end)))
            }
            clauses.append("(\(searchClause))")
        }
        return (clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND "), bindings)
    }

    private static func ordering(for sortOrder: RecordingSortOrder) -> String {
        switch sortOrder {
        case .newestFirst: "created_at DESC"
        case .oldestFirst: "created_at ASC"
        case .name: "title_key ASC, created_at DESC"
        case .duration: "duration DESC, created_at DESC"
        }
    }

    private static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    private static func escapedForLike(_ text: String) -> String {
        text.replacingOccurrences(of: #"\"#, with: #"\\"#)
            .replacingOccurrences(of: "%", with: #"\%"#)
            .replacingOccurrences(of: "_", with: #"\_"#)
    }

    /// SQLite compares only ASCII without regard to case, so non-Latin titles are searched and sorted through a key
    /// folded here.
    private static func searchKey(for text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    private static func key(for id: UUID) -> String {
        id.uuidString
    }

    private static func milliseconds(since date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    private static let selection = """
        SELECT *, EXISTS (SELECT 1 FROM transcripts WHERE recording_id = recordings.id) AS has_transcript,
            (SELECT GROUP_CONCAT(tag_id) FROM recording_tags WHERE recording_id = recordings.id) AS tag_ids
        FROM recordings
        """

    private static let logger = Logger(category: "Library")
}
