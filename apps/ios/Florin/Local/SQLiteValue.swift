import Foundation

/// One SQLite column value, in the five storage classes the engine has.
///
/// Money is the reason this is an enum rather than `Any`. Amounts live in this
/// schema as text, not as floats — the desktop and web stores both write them
/// as decimal strings so that 0.1 + 0.2 is a question SQLite never has to
/// answer. Reading a column has to preserve that distinction, so a caller can
/// ask for `decimal` and get exact arithmetic rather than a rounded double.
enum SQLiteValue: Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
}

extension SQLiteValue {
    var isNull: Bool { self == .null }

    var string: String? {
        switch self {
        case let .text(value): return value
        case let .integer(value): return String(value)
        case let .real(value): return String(value)
        case .blob, .null: return nil
        }
    }

    var int: Int? {
        switch self {
        case let .integer(value): return Int(value)
        case let .real(value): return Int(value)
        case let .text(value): return Int(value)
        case .blob, .null: return nil
        }
    }

    var bool: Bool? {
        guard let int else { return nil }
        return int != 0
    }

    var double: Double? {
        switch self {
        case let .real(value): return value
        case let .integer(value): return Double(value)
        case let .text(value): return Double(value)
        case .blob, .null: return nil
        }
    }

    /// The exact value of a money column.
    ///
    /// Amounts are stored as decimal strings; `Decimal(string:)` keeps them
    /// exact where `Double` would not. Summing a year of 135.91 instalments as
    /// doubles drifts, and this app exists to tell someone what they actually
    /// have.
    var decimal: Decimal? {
        switch self {
        case let .text(value): return Decimal(string: value)
        case let .integer(value): return Decimal(value)
        case let .real(value): return Decimal(value)
        case .blob, .null: return nil
        }
    }

    var data: Data? {
        if case let .blob(value) = self { return value }
        return nil
    }
}

/// One row, keyed by column name.
struct SQLiteRow {
    let columns: [String: SQLiteValue]

    subscript(column: String) -> SQLiteValue { columns[column] ?? .null }

    func string(_ column: String) -> String? { self[column].string }
    func int(_ column: String) -> Int? { self[column].int }
    func bool(_ column: String) -> Bool { self[column].bool ?? false }
    func double(_ column: String) -> Double? { self[column].double }
    func decimal(_ column: String) -> Decimal? { self[column].decimal }
    func data(_ column: String) -> Data? { self[column].data }

    /// Dates are ISO-8601 strings in this schema, the way Drizzle writes them
    /// into SQLite — never epoch numbers. Parsing them anywhere else invites
    /// the two representations to diverge.
    func date(_ column: String) -> Date? {
        guard let raw = string(column) else { return nil }
        return SQLiteRow.isoFormatter.date(from: raw) ?? SQLiteRow.plainFormatter.date(from: raw)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
