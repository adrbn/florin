import Foundation
import OSLog

/// Copies a Florin server's ledger onto this device.
///
/// Refetching from the bank was the wrong answer to "I want my history here".
/// A bank exposes what its consent allows — months, sometimes a year — while
/// the server holds everything ever recorded, including the manual rows,
/// categories and accounts that never came from a bank at all. This reads that,
/// through the same v2 feed the app already uses, and writes it locally.
///
/// Idempotent: rows are keyed by their server id, so importing twice updates
/// rather than duplicates, and an interrupted run can simply be run again.
enum ServerImport {
    private static let log = Logger(subsystem: "com.adrbn.florin", category: "server-import")

    struct Progress {
        var accounts = 0
        var categories = 0
        var transactions = 0
    }

    /// Reads everything and writes it in one transaction, so a failure halfway
    /// leaves the device exactly as it was rather than half-populated.
    static func run(
        from base: URL,
        into store: LocalStore,
        onProgress: @escaping (Progress) -> Void = { _ in }
    ) async throws -> Progress {
        let client = FlorinClient(base: base)
        let overview = try await client.overview()

        var rows: [Transaction] = []
        var offset = 0
        let pageSize = 200
        var progress = Progress(
            accounts: overview.accounts.count,
            categories: overview.categories.count
        )
        onProgress(progress)

        while true {
            let page = try await client.transactions(
                filter: TxFilter(), offset: offset, limit: pageSize
            )
            rows.append(contentsOf: page.transactions)
            progress.transactions = rows.count
            onProgress(progress)

            if page.transactions.count < pageSize { break }
            offset += pageSize
            // A server with years of history should not be able to spin this
            // forever if the feed ever stops honouring offset.
            if offset > 100_000 { break }
        }

        try write(overview: overview, transactions: rows, into: store)
        log.notice("imported \(rows.count) transactions from \(base.host ?? "?", privacy: .public)")
        return progress
    }

    private static func write(
        overview: Overview,
        transactions: [Transaction],
        into store: LocalStore
    ) throws {
        let db = store.database
        try db.transaction {
            /*
             * Categories first, by name.
             *
             * The device has its own seeded categories with their own ids, and
             * the server's rows reference the server's. Matching on name lets
             * an import land on the categories already here instead of
             * doubling every one of them — and anything genuinely new is
             * added to a group of its own.
             */
            var groupIds: [String: String] = [:]
            for row in try db.query("SELECT id, name FROM category_groups") {
                if let name = row.string("name"), let id = row.string("id") {
                    groupIds[name] = id
                }
            }
            var categoryIds: [String: String] = [:]
            for row in try db.query("SELECT id, name FROM categories") {
                if let name = row.string("name"), let id = row.string("id") {
                    categoryIds[name.lowercased()] = id
                }
            }

            for category in overview.categories {
                if categoryIds[category.name.lowercased()] != nil { continue }
                let groupName = category.groupName.isEmpty ? "Autres" : category.groupName
                let groupId: String
                if let existing = groupIds[groupName] {
                    groupId = existing
                } else {
                    groupId = UUID().uuidString
                    try db.run(
                        """
                        INSERT INTO category_groups (id, name, kind, display_order)
                        VALUES (?, ?, 'expense',
                                (SELECT coalesce(max(display_order) + 1, 0) FROM category_groups))
                        """,
                        [.text(groupId), .text(groupName)]
                    )
                    groupIds[groupName] = groupId
                }
                let id = UUID().uuidString
                try db.run(
                    """
                    INSERT INTO categories (id, group_id, name, emoji, display_order)
                    VALUES (?, ?, ?, ?,
                            (SELECT coalesce(max(display_order) + 1, 0) FROM categories))
                    """,
                    [
                        .text(id), .text(groupId), .text(category.name),
                        category.emoji.map { SQLiteValue.text($0) } ?? .null,
                    ]
                )
                categoryIds[category.name.lowercased()] = id
            }

            // Accounts, keyed by the server's own id so a second import updates
            // the same rows.
            var accountIds: [String: String] = [:]
            for account in overview.accounts {
                let external = "server:\(account.id)"
                let existing = try db.scalar(
                    "SELECT id FROM accounts WHERE sync_external_id = ?", [.text(external)]
                )?.string
                let id = existing ?? UUID().uuidString
                if existing == nil {
                    try db.run(
                        """
                        INSERT INTO accounts
                            (id, name, kind, currency, current_balance, opening_balance,
                             sync_provider, sync_external_id, display_order)
                        VALUES (?, ?, ?, ?, ?, ?, 'server', ?,
                                (SELECT coalesce(max(display_order) + 1, 0) FROM accounts))
                        """,
                        [
                            .text(id), .text(account.name), .text(account.kind),
                            .text(overview.currency), .real(account.balance),
                            .real(account.netContribution), .text(external),
                        ]
                    )
                } else {
                    try db.run(
                        "UPDATE accounts SET name = ?, current_balance = ? WHERE id = ?",
                        [.text(account.name), .real(account.balance), .text(id)]
                    )
                }
                accountIds[account.name] = id
            }

            for transaction in transactions {
                let external = "server:\(transaction.id)"
                let already = try db.scalar(
                    "SELECT id FROM transactions WHERE source = 'server' AND external_id = ?",
                    [.text(external)]
                )?.string
                if already != nil { continue }

                try db.run(
                    """
                    INSERT INTO transactions
                        (id, account_id, occurred_at, amount, currency, payee,
                         normalized_payee, memo, category_id, source, external_id,
                         status, needs_review, is_pending)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'server', ?, ?, ?, ?)
                    """,
                    [
                        .text(UUID().uuidString),
                        accountIds[transaction.accountName].map { SQLiteValue.text($0) } ?? .null,
                        .text(transaction.date),
                        .real(transaction.amount),
                        .text(overview.currency),
                        .text(transaction.payee),
                        .text(LocalLedger.normalize(transaction.payee)),
                        transaction.memo.map { SQLiteValue.text($0) } ?? .null,
                        transaction.categoryName
                            .flatMap { categoryIds[$0.lowercased()] }
                            .map { SQLiteValue.text($0) } ?? .null,
                        .text(external),
                        .text(transaction.isScheduled ? "scheduled" : "cleared"),
                        .integer(transaction.needsReview ? 1 : 0),
                        .integer(transaction.isPending ? 1 : 0),
                    ]
                )
            }
        }
    }
}
