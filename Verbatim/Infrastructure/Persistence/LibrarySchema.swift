import Foundation
import os

/// One step of the database schema. Versions are stored in `PRAGMA user_version`.
struct SQLiteMigration {
    let version: Int
    let sql: String
}

/// The application database's schema, one migration per version. Add a migration for a change; never edit a released
/// one.
///
/// `transcripts`, `processing_jobs`, `summaries` and the search index refer to `recordings.id` without a foreign key:
/// removing a recording from the Library can be undone, which must bring its transcript and summary back.
/// `purgeOrphans` clears them once it no longer can. `summary_parts` keep the time span and segments each part covers,
/// which search chunks of the kind `summary_part` repeat.
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
        ),
        SQLiteMigration(
            version: 3,
            sql: """
                CREATE TABLE tags (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    name_key TEXT NOT NULL UNIQUE,
                    color TEXT NOT NULL,
                    position INTEGER NOT NULL
                );
                CREATE TABLE recording_tags (
                    recording_id TEXT NOT NULL REFERENCES recordings (id) ON DELETE CASCADE,
                    tag_id TEXT NOT NULL REFERENCES tags (id) ON DELETE CASCADE,
                    PRIMARY KEY (recording_id, tag_id)
                );
                CREATE INDEX recording_tags_tag_id ON recording_tags (tag_id);
                INSERT INTO tags (id, name, name_key, color, position) VALUES
                    ('6F1D2A40-0000-4000-8000-000000000001', 'work', 'work', 'blue', 0),
                    ('6F1D2A40-0000-4000-8000-000000000002', 'personal', 'personal', 'green', 1);
                """
        ),
        SQLiteMigration(
            version: 4,
            sql: """
                CREATE TABLE summaries (
                    recording_id TEXT PRIMARY KEY NOT NULL,
                    model_id TEXT NOT NULL,
                    language TEXT,
                    transcript_created_at INTEGER NOT NULL,
                    created_at INTEGER NOT NULL,
                    text TEXT NOT NULL
                );
                CREATE TABLE summary_parts (
                    recording_id TEXT NOT NULL REFERENCES summaries (recording_id) ON DELETE CASCADE,
                    position INTEGER NOT NULL,
                    start_time REAL NOT NULL CHECK (start_time >= 0),
                    end_time REAL NOT NULL CHECK (end_time >= start_time),
                    first_segment INTEGER NOT NULL,
                    last_segment INTEGER NOT NULL CHECK (last_segment >= first_segment),
                    text TEXT NOT NULL,
                    PRIMARY KEY (recording_id, position)
                );
                """
        ),
        SQLiteMigration(version: 5, sql: searchIndexSQL)
    ]

    /// The search index: chunks of transcripts and summaries (`search_chunks`), their full-text index
    /// (`search_chunks_fts`, kept in step by triggers), and their vectors by embedding space (`chunk_embeddings`).
    ///
    /// Chunks do not depend on the embedding model, so words can be searched without one, and a new model only adds
    /// vectors in a space of its own. A vector is a BLOB of `dimensions` little-endian Float32 values, normalized to
    /// length 1 so that a dot product is the cosine similarity. Chunk identifiers come from AUTOINCREMENT and are never
    /// reused, so a result handed to an agent keeps naming the same text or nothing. `search_index_state` records what
    /// each recording's chunks were made from. Like transcripts, chunks refer to `recordings.id` without a foreign key.
    private static let searchIndexSQL = """
        CREATE TABLE search_index_state (
            recording_id TEXT PRIMARY KEY NOT NULL,
            transcript_created_at INTEGER,
            summary_created_at INTEGER,
            updated_at INTEGER NOT NULL
        );
        CREATE TABLE search_chunks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            recording_id TEXT NOT NULL,
            kind TEXT NOT NULL CHECK (kind IN ('transcript', 'summary', 'summary_part')),
            position INTEGER NOT NULL CHECK (position >= 0),
            start_time REAL CHECK (start_time >= 0),
            end_time REAL CHECK (end_time >= start_time),
            first_segment INTEGER,
            last_segment INTEGER CHECK (last_segment >= first_segment),
            text TEXT NOT NULL,
            UNIQUE (recording_id, kind, position)
        );
        CREATE VIRTUAL TABLE search_chunks_fts USING fts5 (
            text,
            content = 'search_chunks',
            content_rowid = 'id',
            tokenize = 'unicode61 remove_diacritics 2'
        );
        CREATE TRIGGER search_chunks_after_insert AFTER INSERT ON search_chunks BEGIN
            INSERT INTO search_chunks_fts (rowid, text) VALUES (new.id, new.text);
        END;
        CREATE TRIGGER search_chunks_after_delete AFTER DELETE ON search_chunks BEGIN
            INSERT INTO search_chunks_fts (search_chunks_fts, rowid, text) VALUES ('delete', old.id, old.text);
        END;
        CREATE TRIGGER search_chunks_after_update AFTER UPDATE OF text ON search_chunks BEGIN
            INSERT INTO search_chunks_fts (search_chunks_fts, rowid, text) VALUES ('delete', old.id, old.text);
            INSERT INTO search_chunks_fts (rowid, text) VALUES (new.id, new.text);
        END;
        CREATE TABLE embedding_spaces (
            id INTEGER PRIMARY KEY,
            model_id TEXT NOT NULL,
            revision TEXT NOT NULL,
            dimensions INTEGER NOT NULL CHECK (dimensions > 0),
            created_at INTEGER NOT NULL,
            UNIQUE (model_id, revision, dimensions)
        );
        CREATE TABLE chunk_embeddings (
            space_id INTEGER NOT NULL REFERENCES embedding_spaces (id) ON DELETE CASCADE,
            chunk_id INTEGER NOT NULL REFERENCES search_chunks (id) ON DELETE CASCADE,
            vector BLOB NOT NULL,
            PRIMARY KEY (space_id, chunk_id)
        ) WITHOUT ROWID;
        CREATE INDEX chunk_embeddings_chunk_id ON chunk_embeddings (chunk_id);
        """

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
    private static let logger = Logger(category: "Library")
}
