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
    /*
     * Parents before children, because foreign keys are checked per row.
     *
     * Categories come after accounts, not before: a category can point at a
     * loan account it mirrors, and inserting it first fails the constraint on
     * exactly the ledgers that have one.
     */
    private static let tables = [
        "category_groups", "accounts", "categories", "transactions",
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
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withFullDate]
        let name = "Florin-\(stamp.string(from: Date())).sqlite"
        /*
         * Documents, not the temporary directory.
         *
         * A file written to tmp exists for as long as the share sheet is open
         * and then iOS may take it back — which is fine if the person routes it
         * somewhere in that moment, and a silent loss if they do not. Documents
         * is listed in Files under "Florin" (see UIFileSharingEnabled), so the
         * copy stays somewhere they can open it, mail it later, or hand it to
         * the restore picker on the next phone.
         */
        let folder = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let destination = folder.appendingPathComponent(name)
        // One export on file, not a year of them: each is the whole ledger, and
        // the older ones are strictly worse copies of the same thing.
        for old in (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        )) ?? [] where old.lastPathComponent.hasPrefix("Florin-")
            && old.pathExtension == "sqlite" {
            try? FileManager.default.removeItem(at: old)
        }
        try? FileManager.default.removeItem(at: destination)
        /*
         * VACUUM INTO, not a file copy.
         *
         * Copying the file produced something unreadable, and the reason is in
         * the header: the live database runs in WAL mode, and a WAL database
         * cannot be opened read-only without writing a -shm beside it. A copy
         * carried that mode with it, so the app could not so much as count the
         * rows in its own backup — and neither could anything the user opened
         * it with.
         *
         * VACUUM INTO writes a fresh database in the default journal mode from
         * a consistent read, which is both the readable answer and the compact
         * one: no free pages, no log to fold in first.
         */
        try store.database.run("VACUUM INTO ?", [.text(destination.path)])
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
     * Replace, because merging two ledgers cannot be made to work.
     *
     * The gentler reading was tried first: put every row back by id, keep
     * whatever the destination already had. It fails on the very case it
     * exists for. Two installs each seed their own starting categories, the
     * group named "Dépenses" is UNIQUE by name, and so the copy's group is
     * refused as a duplicate — after which every category pointing at it has
     * nowhere to land and the whole restore rolls back. The same logical
     * category exists twice under two identifiers, and nothing keyed on
     * identifiers can tell that.
     *
     * So a restore restores: the copied tables are emptied and rewritten from
     * the file, and what comes out is the ledger as it stood when the file was
     * written. That is what the word means everywhere else, and it is what
     * someone moving to a new phone is asking for. The ledger being replaced
     * is written to a file of its own first, so a restore aimed at the wrong
     * phone is a mistake that can be walked back.
     */
    static func restore(from url: URL, into store: LocalStore) throws -> Summary {
        /*
         * Work from a copy the app owns.
         *
         * The picked file can be anywhere the document browser reaches — iCloud
         * Drive, a read-only volume, another app's container — and it is only
         * reachable while the security-scoped access is held. ATTACH wants to
         * open it for writing and holds it open for the length of the restore,
         * which is a set of assumptions none of those places honour. Copying it
         * into the app's own temporary directory first makes every one of them
         * moot.
         */
        let scoped = url.startAccessingSecurityScopedResource()
        let local = FileManager.default.temporaryDirectory
            .appendingPathComponent("restore-\(UUID().uuidString).sqlite")
        do {
            try? FileManager.default.removeItem(at: local)
            try FileManager.default.copyItem(at: url, to: local)
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            throw error
        }
        if scoped { url.stopAccessingSecurityScopedResource() }
        defer { try? FileManager.default.removeItem(at: local) }

        guard inspect(local) != nil else { throw Failure.notALedger }

        // The ledger about to be overwritten, kept where it can be found again.
        let safety = store.url.deletingLastPathComponent()
            .appendingPathComponent("florin-before-restore.sqlite")
        try? FileManager.default.removeItem(at: safety)
        try? store.database.run("VACUUM INTO ?", [.text(safety.path)])

        // ATTACH rather than swapping files underneath a live connection: the
        // store is open for the whole life of the app and has no way to be
        // handed a new one.
        try store.database.run("ATTACH DATABASE ? AS backup", [.text(local.path)])
        defer { try? store.database.exec("DETACH DATABASE backup") }

        let copied = Set(tables)
        try store.database.transaction {
            /*
             * Hold the constraints until the end.
             *
             * Emptying and refilling nine tables that reference each other has
             * no ordering that is valid at every step — a category points at
             * the account it mirrors, an account is pointed at by everything.
             * Deferring the checks to the commit means the ledger only has to
             * be consistent once it is whole, which is the only moment it can
             * be.
             */
            try store.database.exec("PRAGMA defer_foreign_keys = ON")
            for table in tables.reversed() {
                try store.database.exec("DELETE FROM main.\(table)")
            }
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

                /*
                 * References to tables the copy does not carry.
                 *
                 * An account names the bank connection it syncs through, and
                 * connections are deliberately left out — a session restored
                 * onto another phone is a dead session. Carried across as-is
                 * the reference points at nothing, the constraint fails, and
                 * the whole restore rolls back. Kept when the destination
                 * happens to know that connection, dropped when it does not.
                 */
                var expressions = [String: String]()
                for fk in try store.database.query("PRAGMA main.foreign_key_list(\(table))") {
                    guard let parent = fk.string("table"), !copied.contains(parent),
                          let column = fk.string("from") else { continue }
                    expressions[column] =
                        "CASE WHEN \(column) IN (SELECT id FROM main.\(parent)) "
                        + "THEN \(column) ELSE NULL END"
                }

                let list = shared.joined(separator: ", ")
                let values = shared.map { expressions[$0] ?? $0 }.joined(separator: ", ")
                try store.database.exec(
                    "INSERT INTO main.\(table) (\(list)) SELECT \(values) FROM backup.\(table)"
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
