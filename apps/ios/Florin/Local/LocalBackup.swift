import Foundation
import OSLog

/*
 * A copy of the ledger the user can hold in their hand.
 *
 * The database is included in the iPhone's iCloud backup, which is the right
 * safety net and a completely invisible one: iOS tells an app neither whether
 * backups are switched on nor when the last one ran, and gives it no way to
 * ask for one. An indicator built on that would be a green light wired to
 * nothing.
 *
 * So the app offers the backup it can actually account for — a file, written
 * when asked, with a date it can show, that the user can put wherever they
 * keep things and read back in later. Between the two, one covers losing the
 * phone and the other covers everything else.
 */
enum LocalBackup {
    private static let log = Logger(subsystem: "com.adrbn.florin", category: "backup")

    /// What a ledger holds, for showing before and after.
    struct Summary: Equatable {
        var transactions = 0
        var accounts = 0
        var categories = 0
        var earliest: String?
        var latest: String?
    }

    /// The tables a copy carries.
    ///
    /// Not `settings`, which holds the banking key path and the schema version,
    /// and not `bank_connections`: a session restored from an old copy is a
    /// dead session, and sync would fail in a way that looks like a broken app
    /// rather than an expired consent. Everything a person entered is here.
    private static let tables = [
        "category_groups", "categories", "accounts", "transactions",
        "holdings", "monthly_budgets", "categorization_rules",
        "recurring_rules", "balance_snapshots",
    ]

    // MARK: - Writing one

    /// A settled copy in the temporary directory, ready for the share sheet.
    ///
    /// Checkpointed first: a copy taken while the write-ahead log holds pages
    /// the main file has not seen is a copy missing the newest rows. After a
    /// TRUNCATE checkpoint the log is empty and the one file is the whole
    /// ledger, so there is nothing else to carry.
    static func export(from store: LocalStore) throws -> URL {
        try store.database.exec("PRAGMA wal_checkpoint(TRUNCATE)")
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withFullDate]
        let name = "Florin-\(stamp.string(from: Date())).sqlite"
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: store.url, to: destination)
        return destination
    }

    // MARK: - Reading one back

    /// What is in a candidate file, or nil if it is not a Florin ledger.
    ///
    /// Opened read-only, because the user may well have picked the wrong file
    /// and a stray journal written beside someone's photo library is a rude
    /// way to say so.
    static func inspect(_ url: URL) -> Summary? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let db = try? SQLiteDatabase(path: url.path, readOnly: true) else { return nil }
        guard let ok = try? db.scalar(
            "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'transactions'"
        )?.int, ok == 1 else { return nil }
        return summary(of: db)
    }

    static func summary(of db: SQLiteDatabase) -> Summary {
        var out = Summary()
        out.transactions = (try? db.scalar(
            "SELECT count(*) FROM transactions WHERE deleted_at IS NULL"
        )?.int) as? Int ?? 0
        out.accounts = (try? db.scalar("SELECT count(*) FROM accounts")?.int) as? Int ?? 0
        out.categories = (try? db.scalar("SELECT count(*) FROM categories")?.int) as? Int ?? 0
        if let row = try? db.query(
            "SELECT min(occurred_at) a, max(occurred_at) b FROM transactions WHERE deleted_at IS NULL"
        ).first {
            out.earliest = row.string("a")
            out.latest = row.string("b")
        }
        return out
    }

    /*
     * Merge, never replace.
     *
     * A restore that emptied the tables first would be the more literal reading
     * of the word, and it would mean a person who backed up in June and then
     * spent July on their phone loses July to get June back. Row for row by id
     * is the safe reading: everything in the copy is put back, everything added
     * since stays, and running it twice changes nothing the second time.
     *
     * This is why the copy is not the whole answer on its own — a row deleted
     * on purpose comes back with it. iCloud's own restore is the one that
     * returns the ledger exactly as it stood.
     */
    static func restore(from url: URL, into store: LocalStore) throws -> Summary {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard inspect(url) != nil else { throw Failure.notALedger }

        // ATTACH rather than swapping files underneath a live connection: the
        // store is open for the whole life of the app and has no way to be
        // handed a new one.
        try store.database.run("ATTACH DATABASE ? AS backup", [.text(url.path)])
        defer { try? store.database.exec("DETACH DATABASE backup") }

        try store.database.transaction {
            for table in tables {
                let exists = try store.database.scalar(
                    "SELECT count(*) FROM backup.sqlite_master WHERE type='table' AND name = ?",
                    [.text(table)]
                )?.int ?? 0
                guard exists == 1 else { continue }
                // Column by column, from the copy's own list: a file written by
                // an older build is missing columns this one has, and naming
                // them beats INSERT SELECT * and its silent shift by one.
                let columns = try store.database.query("PRAGMA backup.table_info(\(table))")
                    .compactMap { $0.string("name") }
                let mine = Set(try store.database.query("PRAGMA main.table_info(\(table))")
                    .compactMap { $0.string("name") })
                let shared = columns.filter { mine.contains($0) }
                guard !shared.isEmpty else { continue }
                let list = shared.joined(separator: ", ")
                try store.database.exec(
                    "INSERT OR REPLACE INTO main.\(table) (\(list)) SELECT \(list) FROM backup.\(table)"
                )
            }
        }

        let after = summary(of: store.database)
        log.notice("restored — \(after.transactions, privacy: .public) transactions on file")
        return after
    }

    enum Failure: LocalizedError {
        case notALedger
        var errorDescription: String? {
            switch self {
            case .notALedger: "Ce fichier n'est pas une sauvegarde Florin."
            }
        }
    }
}
