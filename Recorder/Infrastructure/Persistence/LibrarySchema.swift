import Foundation

/// One step of the database schema. Versions are stored in `PRAGMA user_version`.
struct SQLiteMigration {
    let version: Int
    let sql: String
}

/// The application database's schema, one migration per version. Add a migration for a change; never edit a released
/// one. Transcripts, processing jobs and vector indexes will get their own tables, referring to `recordings.id`.
enum LibrarySchema {
    static let migrations = [
        SQLiteMigration(
            version: 1,
            sql: """
                CREATE TABLE recordings (
                    id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL,
                    title_key TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    duration REAL NOT NULL DEFAULT 0,
                    recording_type TEXT NOT NULL,
                    media_path TEXT NOT NULL UNIQUE,
                    media_bookmark BLOB,
                    file_size INTEGER NOT NULL DEFAULT 0,
                    processing_status TEXT NOT NULL,
                    updated_at INTEGER NOT NULL
                );
                CREATE INDEX recordings_created_at ON recordings (created_at);
                CREATE INDEX recordings_title_key ON recordings (title_key);
                CREATE INDEX recordings_duration ON recordings (duration);
                """
        )
    ]

    /// Brings the database up to the latest version, each step in its own transaction, so a failed step leaves the
    /// database at the last good version. A database from a newer app is rejected rather than changed.
    static func migrate(_ database: SQLiteDatabase, using migrations: [SQLiteMigration] = migrations) throws {
        let current = try database.query("PRAGMA user_version").first?.integer("user_version") ?? 0
        let latest = migrations.map(\.version).max() ?? 0
        guard current <= latest else {
            throw LibraryError.databaseFromNewerVersion
        }
        for migration in migrations.sorted(by: { $0.version < $1.version }) where migration.version > current {
            try database.transaction {
                try database.executeScript(migration.sql)
                try database.executeScript("PRAGMA user_version = \(migration.version)")
            }
        }
    }
}
