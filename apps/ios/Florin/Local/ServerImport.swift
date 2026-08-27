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

    /*
     * The server replaces the device's ledger; it does not merge into it.
     *
     * Merging was the first attempt and it was wrong in a way that showed up
     * immediately: the bank had already put its transactions here through
     * Enable Banking, the server brought the same ones again under its own
     * ids, and net worth jumped by the size of the overlap. There is no key
     * that reliably matches a row imported twice through two different paths.
     *
     * A server that holds everything is the authority, so importing takes its
     * copy whole — including dropping this device's own bank connection, since
     * the server already syncs that bank and leaving both would put the
     * duplicates straight back on the next refresh.
     */
    static func run(
        from base: URL,
        into store: LocalStore,
        onProgress: @escaping (Progress) -> Void = { _ in }
    ) async throws -> Progress {
        let client = FlorinClient(base: base)
        let overview = try await client.overview()

        var rows: [Transaction] = []
        var offset = 0
        /*
         * The server caps a page at 100 whatever is asked for.
         *
         * This requested 200 and stopped as soon as a page came back "short" —
         * which the very first one was, at 100. The import would have taken
         * exactly one page of a 2834-row ledger and reported success. The
         * server sends the true `total`, so that is what decides when to stop;
         * a page smaller than requested proves nothing.
         */
        let pageSize = 100
        var progress = Progress(
            accounts: overview.accounts.count,
            categories: overview.categories.count
        )
        onProgress(progress)

        var total = Int.max
        while rows.count < total {
            let page = try await client.transactions(
                filter: TxFilter(), offset: offset, limit: pageSize
            )
            total = page.total
            // An empty page is the only honest end: it means the server has
            // nothing more at this offset, whatever the count claimed.
            if page.transactions.isEmpty { break }

            rows.append(contentsOf: page.transactions)
            progress.transactions = rows.count
            onProgress(progress)
            offset += page.transactions.count
        }

        /*
         * The plan, month by month, because that is how the feed serves it.
         *
         * `monthly_budgets` was being cleared and never refilled, so an import
         * arrived with every envelope empty — the one part of the app whose
         * whole content is hand-entered, silently dropped. There is no bulk
         * endpoint, so the months are walked: two years back, and three
         * forward for anything already planned ahead.
         */
        var budgets: [(year: Int, month: Int, categoryName: String, assigned: Double, note: String?)] = []
        let calendar = Calendar(identifier: .gregorian)
        for offset in -24...3 {
            guard let date = calendar.date(byAdding: .month, value: offset, to: Date()) else { continue }
            let parts = calendar.dateComponents([.year, .month], from: date)
            guard let year = parts.year, let month = parts.month else { continue }
            guard let plan = try? await self.plan(base: base, year: year, month: month) else { continue }
            for group in plan.groups {
                for category in group.categories where category.assigned != 0 || category.note != nil {
                    budgets.append(
                        (year, month, category.name, category.assigned, category.note)
                    )
                }
            }
        }

        try write(overview: overview, transactions: rows, budgets: budgets, into: store)
        log.notice("imported \(rows.count) transactions from \(base.host ?? "?", privacy: .public)")
        return progress
    }

    private static func plan(base: URL, year: Int, month: Int) async throws -> MonthPlan {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.path = "/api/v2/plan"
        components?.queryItems = [
            URLQueryItem(name: "month", value: String(format: "%04d-%02d", year, month))
        ]
        guard let url = components?.url else { throw FlorinError.unreachable(base.host ?? "?") }
        let (data, response) = try await FlorinAuth.session.data(for: FlorinAuth.request(url))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FlorinError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(MonthPlan.self, from: data)
    }

    private static func write(
        overview: Overview,
        transactions: [Transaction],
        budgets: [(year: Int, month: Int, categoryName: String, assigned: Double, note: String?)],
        into store: LocalStore
    ) throws {
        let db = store.database
        try db.transaction {
            // Everything the server is about to supply, cleared first. Inside
            // the same transaction, so a failure leaves the device untouched
            // rather than empty.
            try db.run("DELETE FROM transactions")
            try db.run("DELETE FROM monthly_budgets")
            try db.run("DELETE FROM accounts")
            try db.run("DELETE FROM bank_connections")
            try db.run("DELETE FROM categories")
            try db.run("DELETE FROM category_groups")
            // Categories first: transactions reference them, and the server's
            // ids mean nothing here, so they are rebuilt and matched by name.
            var groupIds: [String: String] = [:]
            var categoryIds: [String: String] = [:]

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
                /*
                 * A balance is not always what an account is worth.
                 *
                 * Copying `balance` alone lost two things and both showed up in
                 * the headline figure: a broker's cash balance is near zero
                 * while its holdings are the account (PEA read 0.40 instead of
                 * 3491.22), and a loan's balance is what has been repaid while
                 * the debt is what is still owed (3543.41 instead of 7185.62).
                 * Together they put net worth out by 151.39 — close enough to
                 * look plausible, which is the dangerous kind of wrong.
                 *
                 * A loan is stored negative because that is how this ledger
                 * reads debt back out.
                 */
                let stored = account.isLoan
                    ? -(account.debt ?? abs(account.balance))
                    : account.balance
                try db.run(
                    """
                    INSERT OR REPLACE INTO accounts
                        (id, name, kind, currency, current_balance, opening_balance,
                         market_value, is_included_in_net_worth,
                         sync_provider, sync_external_id, display_order)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'server', ?,
                            (SELECT coalesce(max(display_order) + 1, 0) FROM accounts))
                    """,
                    [
                        .text(id), .text(account.name), .text(account.kind),
                        .text(overview.currency), .real(stored),
                        .real(account.netContribution),
                        .real(account.marketValue),
                        .integer(account.isIncludedInNetWorth ? 1 : 0),
                        .text(external),
                    ]
                )
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

            for budget in budgets {
                guard let categoryId = categoryIds[budget.categoryName.lowercased()] else { continue }
                try db.run(
                    """
                    INSERT INTO monthly_budgets (id, year, month, category_id, assigned, note)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    [
                        .text(UUID().uuidString), .integer(Int64(budget.year)),
                        .integer(Int64(budget.month)), .text(categoryId),
                        .real(budget.assigned),
                        budget.note.map { SQLiteValue.text($0) } ?? .null,
                    ]
                )
            }
        }
    }
}
