import Foundation
import os

/// One step of the database schema. Versions are stored in `PRAGMA user_version`.
struct SQLiteMigration {
    let version: Int
    let sql: String
}

/// The application database's schema, one migration per version. Add a migration for a change; never edit a released
/// one. Vector indexes will get their own tables, referring to `recordings.id`.
///
/// `transcripts` and `processing_jobs` refer to `recordings.id` without a foreign key: removing a recording from the
/// Library can be undone, which must bring its transcript back. `purgeOrphans` clears them once it no longer can.
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
        ),
        SQLiteMigration(
            version: 2,
            sql: """
                CREATE TABLE transcripts (
                    recording_id TEXT PRIMARY KEY NOT NULL,
                    model_id TEXT NOT NULL,
                    model_version TEXT,
                    language TEXT,
                    created_at INTEGER NOT NULL
                );
                CREATE TABLE transcript_segments (
                    id TEXT PRIMARY KEY NOT NULL,
                    recording_id TEXT NOT NULL REFERENCES transcripts (recording_id) ON DELETE CASCADE,
                    position INTEGER NOT NULL,
                    start_time REAL NOT NULL CHECK (start_time >= 0),
                    end_time REAL NOT NULL CHECK (end_time >= start_time),
                    text TEXT NOT NULL,
                    source TEXT NOT NULL,
                    UNIQUE (recording_id, position)
                );
                CREATE TABLE processing_jobs (
                    recording_id TEXT PRIMARY KEY NOT NULL,
                    state TEXT NOT NULL,
                    queued_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    attempts INTEGER NOT NULL DEFAULT 0,
                    model_id TEXT,
                    failure TEXT,
                    export_failure TEXT
                );
                """
        )
    ]

    /// Opens the database file and brings it up to date. A database that cannot be opened or migrated is left in place
    /// and reported, never recreated. Each repository holds its own connection; WAL lets them work side by side.
    ///
    /// One at a time, because switching a new file to WAL fails with “database is locked” if another connection is
    /// doing the same, without waiting for the busy timeout. Opening takes milliseconds, so the wait costs nothing.
    static func open(at url: URL, using migrations: [SQLiteMigration] = migrations) throws -> SQLiteDatabase {
        try openingLock.withLock {
            try openWithoutWaiting(at: url, using: migrations)
        }
    }

    private static func openWithoutWaiting(at url: URL, using migrations: [SQLiteMigration]) throws -> SQLiteDatabase {
        let database: SQLiteDatabase
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            database = try SQLiteDatabase(url: url)
        } catch {
            logger.error("Could not open the Library database: \(String(describing: error))")
            throw LibraryError.databaseUnavailable(detail: detail(of: error))
        }
        do {
            try migrate(database, using: migrations)
        } catch let error as LibraryError {
            throw error
        } catch {
            logger.error("Could not migrate the Library database: \(String(describing: error))")
            throw LibraryError.databaseMigrationFailed(detail: detail(of: error))
        }
        return database
    }

    /// Brings the database up to the latest version, each step in its own transaction, so a failed step leaves the
    /// database at the last good version. A database from a newer app is rejected rather than changed.
    static func migrate(_ database: SQLiteDatabase, using migrations: [SQLiteMigration] = migrations) throws {
        let latest = migrations.map(\.version).max() ?? 0
        guard try version(of: database) <= latest else {
            throw LibraryError.databaseFromNewerVersion
        }
        for migration in migrations.sorted(by: { $0.version < $1.version }) {
            try database.transaction {
                // Read inside the transaction: another connection may have applied this step a moment ago.
                guard try version(of: database) < migration.version else {
                    return
                }
                try database.executeScript(migration.sql)
                try database.executeScript("PRAGMA user_version = \(migration.version)")
            }
        }
    }

    private static func version(of database: SQLiteDatabase) throws -> Int {
        Int(try database.query("PRAGMA user_version").first?.integer("user_version") ?? 0)
    }

    private static func detail(of error: any Error) -> String {
        (error as? SQLiteDatabase.Failure)?.message ?? error.localizedDescription
    }

    private static let openingLock = NSLock()
    private static let logger = Logger(subsystem: "dev.local.Recorder", category: "Library")
}
