import Foundation
import SQLite3

/// A connection to one SQLite database, with parameterized statements only.
///
/// This uses the system SQLite directly, the same library SQLiteVecKit links. `VectorStore` cannot serve as the
/// connection for app tables: it freezes an embedding dimension into the file on creation, and no embedding model has
/// been chosen. Its vector tables can later live in this file or beside it.
///
/// Not safe to share between threads; it belongs to the actor that created it.
final class SQLiteDatabase {
    enum Value: Equatable {
        case integer(Int64)
        case real(Double)
        case text(String)
        case blob(Data)
        case null
    }

    struct Failure: Error, Equatable {
        let code: Int32
        let message: String

        var isConstraintViolation: Bool {
            code & 0xFF == SQLITE_CONSTRAINT
        }
    }

    /// One result row, by column name. Accessors return `nil` for `NULL` or a value of another type.
    struct Row {
        fileprivate let values: [String: Value]

        func integer(_ column: String) -> Int64? {
            guard case .integer(let value)? = values[column] else {
                return nil
            }
            return value
        }

        func real(_ column: String) -> Double? {
            switch values[column] {
            case .real(let value)?: value
            case .integer(let value)?: Double(value)
            default: nil
            }
        }

        func text(_ column: String) -> String? {
            guard case .text(let value)? = values[column] else {
                return nil
            }
            return value
        }

        func blob(_ column: String) -> Data? {
            guard case .blob(let value)? = values[column] else {
                return nil
            }
            return value
        }
    }

    private let handle: OpaquePointer

    init(url: URL) throws {
        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let code = sqlite3_open_v2(url.path(percentEncoded: false), &connection, flags, nil)
        guard code == SQLITE_OK, let connection else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open the database"
            sqlite3_close_v2(connection)
            throw Failure(code: code, message: message)
        }
        handle = connection
        sqlite3_busy_timeout(handle, Self.busyTimeoutMilliseconds)
        try executeScript("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;")
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    /// Runs statements that take no parameters, such as a schema change.
    func executeScript(_ sql: String) throws {
        let code = sqlite3_exec(handle, sql, nil, nil, nil)
        guard code == SQLITE_OK else {
            throw lastFailure(code: code)
        }
    }

    /// Returns the number of rows changed.
    @discardableResult
    func execute(_ sql: String, bindings: [Value] = []) throws -> Int {
        let statement = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }
        let code = sqlite3_step(statement)
        guard code == SQLITE_DONE || code == SQLITE_ROW else {
            throw lastFailure(code: code)
        }
        return Int(sqlite3_changes(handle))
    }

    func query(_ sql: String, bindings: [Value] = []) throws -> [Row] {
        let statement = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }
        var rows: [Row] = []
        while true {
            let code = sqlite3_step(statement)
            guard code != SQLITE_DONE else {
                return rows
            }
            guard code == SQLITE_ROW else {
                throw lastFailure(code: code)
            }
            rows.append(Self.row(from: statement))
        }
    }

    /// Commits when `body` returns; rolls back when it throws.
    func transaction(_ body: () throws -> Void) throws {
        try executeScript("BEGIN IMMEDIATE")
        do {
            try body()
            try executeScript("COMMIT")
        } catch {
            sqlite3_exec(handle, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }

    private func prepare(_ sql: String, bindings: [Value]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard code == SQLITE_OK else {
            throw lastFailure(code: code)
        }
        for (index, value) in bindings.enumerated() {
            let bindCode = Self.bind(value, at: Int32(index + 1), in: statement)
            guard bindCode == SQLITE_OK else {
                let failure = lastFailure(code: bindCode)
                sqlite3_finalize(statement)
                throw failure
            }
        }
        return statement
    }

    private static func bind(_ value: Value, at index: Int32, in statement: OpaquePointer?) -> Int32 {
        switch value {
        case .integer(let integer):
            sqlite3_bind_int64(statement, index, integer)
        case .real(let real):
            sqlite3_bind_double(statement, index, real)
        case .text(let text):
            sqlite3_bind_text(statement, index, text, -1, transientDestructor)
        case .blob(let data):
            data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), transientDestructor)
            }
        case .null:
            sqlite3_bind_null(statement, index)
        }
    }

    private static func row(from statement: OpaquePointer?) -> Row {
        var values: [String: Value] = [:]
        for column in 0..<sqlite3_column_count(statement) {
            let name = String(cString: sqlite3_column_name(statement, column))
            values[name] = value(of: statement, at: column)
        }
        return Row(values: values)
    }

    private static func value(of statement: OpaquePointer?, at column: Int32) -> Value {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, column))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, column))
        case SQLITE_TEXT:
            guard let text = sqlite3_column_text(statement, column) else {
                return .null
            }
            return .text(String(cString: text))
        case SQLITE_BLOB:
            guard let bytes = sqlite3_column_blob(statement, column) else {
                return .blob(Data())
            }
            return .blob(Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column))))
        default:
            return .null
        }
    }

    private func lastFailure(code: Int32) -> Failure {
        Failure(code: code, message: String(cString: sqlite3_errmsg(handle)))
    }

    private static let busyTimeoutMilliseconds: Int32 = 2_000
    /// Tells SQLite to copy bound text and blobs, whose memory is only valid during the bind call.
    private static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
