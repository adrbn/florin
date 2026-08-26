import Foundation
import SQLite3

/// A thin, honest wrapper over the SQLite that ships with iOS.
///
/// No package dependency on purpose. The ledger this app is growing towards
/// holding is the user's own money, and a serverless build should not be able
/// to fail because a third-party package failed to resolve. `libsqlite3` is
/// part of the platform, it is the same engine the desktop app already stores
/// this schema in, and the surface we need from it is small.
///
/// Everything here is deliberately narrow: open, migrate, read rows, write in a
/// transaction. It is not an ORM and should not become one — the queries this
/// app needs are aggregates that read better as SQL than as a fluent builder.
final class SQLiteDatabase {
    /// SQLite's own "destructor" sentinel: copy the bytes rather than borrow
    /// them. Swift string storage does not outlive the bind call otherwise.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "florin.sqlite")

    enum Failure: LocalizedError {
        case open(String)
        case prepare(String, sql: String)
        case step(String, sql: String)

        var errorDescription: String? {
            switch self {
            case let .open(message): return "SQLite could not open the database: \(message)"
            case let .prepare(message, sql): return "SQLite could not prepare \(sql): \(message)"
            case let .step(message, sql): return "SQLite failed running \(sql): \(message)"
            }
        }
    }

    init(path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let opened = db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close_v2(db)
            throw Failure.open(message)
        }
        handle = opened
        /*
         * WAL and a busy timeout, set once at open.
         *
         * A background sync writing while the UI reads is the normal case here,
         * not the exception, and the rollback journal serialises those into
         * visible stalls. The timeout means a concurrent writer waits rather
         * than immediately returning SQLITE_BUSY to a view that has no sensible
         * way to recover from it.
         */
        try exec("PRAGMA journal_mode = WAL")
        try exec("PRAGMA busy_timeout = 5000")
        try exec("PRAGMA foreign_keys = ON")
    }

    deinit { sqlite3_close_v2(handle) }

    private func message() -> String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "no database"
    }

    // MARK: - Writing

    /// Run one or more statements for their effect.
    func exec(_ sql: String) throws {
        try queue.sync {
            var error: UnsafeMutablePointer<CChar>?
            guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
                let text = error.map { String(cString: $0) } ?? message()
                sqlite3_free(error)
                throw Failure.step(text, sql: sql)
            }
        }
    }

    /// Run one statement with bound values.
    func run(_ sql: String, _ values: [SQLiteValue] = []) throws {
        try queue.sync {
            let statement = try prepare(sql, values)
            defer { sqlite3_finalize(statement) }
            let code = sqlite3_step(statement)
            guard code == SQLITE_DONE || code == SQLITE_ROW else {
                throw Failure.step(message(), sql: sql)
            }
        }
    }

    /// Run `body` inside a transaction, rolling back if it throws.
    ///
    /// Seeding and sync both write many rows that only make sense together —
    /// a half-applied ledger is worse than none.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try exec("COMMIT")
            return value
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    // MARK: - Reading

    /// Read every row, each as a column-name-keyed dictionary.
    func query(_ sql: String, _ values: [SQLiteValue] = []) throws -> [SQLiteRow] {
        try queue.sync {
            let statement = try prepare(sql, values)
            defer { sqlite3_finalize(statement) }

            let columnCount = Int(sqlite3_column_count(statement))
            let names = (0..<columnCount).map { String(cString: sqlite3_column_name(statement, Int32($0))) }

            var rows: [SQLiteRow] = []
            while true {
                let code = sqlite3_step(statement)
                if code == SQLITE_DONE { break }
                guard code == SQLITE_ROW else { throw Failure.step(message(), sql: sql) }

                var columns: [String: SQLiteValue] = [:]
                for index in 0..<columnCount {
                    columns[names[index]] = value(of: statement, at: Int32(index))
                }
                rows.append(SQLiteRow(columns: columns))
            }
            return rows
        }
    }

    /// Read a single scalar, or nil when the query returned no rows.
    func scalar(_ sql: String, _ values: [SQLiteValue] = []) throws -> SQLiteValue? {
        try query(sql, values).first?.columns.first?.value
    }

    // MARK: - Plumbing

    private func prepare(_ sql: String, _ values: [SQLiteValue]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Failure.prepare(message(), sql: sql)
        }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .null:
                sqlite3_bind_null(statement, index)
            case let .integer(number):
                sqlite3_bind_int64(statement, index, number)
            case let .real(number):
                sqlite3_bind_double(statement, index, number)
            case let .text(string):
                sqlite3_bind_text(statement, index, string, -1, Self.transient)
            case let .blob(data):
                _ = data.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(data.count), Self.transient)
                }
            }
        }
        return statement
    }

    private func value(of statement: OpaquePointer?, at index: Int32) -> SQLiteValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_NULL:
            return .null
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_BLOB:
            guard let bytes = sqlite3_column_blob(statement, index) else { return .null }
            let count = Int(sqlite3_column_bytes(statement, index))
            return .blob(Data(bytes: bytes, count: count))
        default:
            guard let text = sqlite3_column_text(statement, index) else { return .null }
            return .text(String(cString: text))
        }
    }
}
