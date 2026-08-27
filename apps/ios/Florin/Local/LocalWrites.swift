import Foundation

/// The ledger's filtered reads and its writes, on the device.
///
/// The list, the edits and the deletes that Activité performs — the same
/// shapes the v2 routes return and accept, so `ActivityModel` cannot tell
/// which side answered.
enum LocalLedger {
    // MARK: - Reading a page

    static func page(
        store: LocalStore,
        filter: TxFilter,
        offset: Int,
        limit: Int
    ) throws -> TransactionPage {
        let db = store.database
        var clauses = ["t.deleted_at IS NULL"]
        var values: [SQLiteValue] = []

        if !filter.search.trimmingCharacters(in: .whitespaces).isEmpty {
            // Matched on the normalized payee as well as the raw one: bank
            // labels carry case and punctuation nobody types.
            clauses.append("(lower(t.payee) LIKE ? OR t.normalized_payee LIKE ? OR lower(coalesce(t.memo,'')) LIKE ?)")
            let needle = "%" + filter.search.lowercased().trimmingCharacters(in: .whitespaces) + "%"
            values.append(contentsOf: [.text(needle), .text(needle), .text(needle)])
        }
        switch filter.direction {
        case .expense: clauses.append("t.amount < 0")
        case .income: clauses.append("t.amount > 0")
        case .all: break
        }
        if filter.needsReview {
            clauses.append(
                """
                t.needs_review = 1 AND t.is_pending = 0
                AND substr(t.occurred_at, 1, 10) <= date('now')
                """
            )
        }
        if filter.excludeTransfers { clauses.append("t.transfer_pair_id IS NULL") }
        if let accountId = filter.accountId {
            clauses.append("t.account_id = ?")
            values.append(.text(accountId))
        }
        if let categoryId = filter.categoryId {
            clauses.append("t.category_id = ?")
            values.append(.text(categoryId))
        }
        if let from = filter.from {
            clauses.append("t.occurred_at >= ?")
            values.append(.text(TxFilter.day(from)))
        }
        if let to = filter.to {
            // Inclusive of that whole day, or a same-day from/to pair selects
            // nothing at all.
            clauses.append("t.occurred_at <= ?")
            values.append(.text(TxFilter.day(to) + "T23:59:59Z"))
        }
        let whereClause = clauses.joined(separator: " AND ")

        let total = try db.scalar(
            "SELECT count(*) FROM transactions t WHERE \(whereClause)", values
        )?.int ?? 0

        let rows = try db.query(
            """
            SELECT t.id, t.occurred_at, t.amount, t.payee, t.memo,
                   c.name AS category_name, c.emoji AS category_emoji,
                   a.name AS account_name, t.transfer_pair_id,
                   t.needs_review, t.is_pending, t.status
            FROM transactions t
            LEFT JOIN categories c ON c.id = t.category_id
            LEFT JOIN accounts a ON a.id = t.account_id
            WHERE \(whereClause)
            ORDER BY t.occurred_at DESC, t.id DESC
            LIMIT ? OFFSET ?
            """,
            values + [.integer(Int64(limit)), .integer(Int64(offset))]
        )

        return TransactionPage(
            total: total,
            reviewCount: try db.scalar(
                """
                SELECT count(*) FROM transactions
                WHERE needs_review = 1 AND deleted_at IS NULL AND is_pending = 0
                  AND substr(occurred_at, 1, 10) <= date('now')
                """
            )?.int ?? 0,
            transactions: rows.map(transaction(from:)),
            accounts: try LocalQueries.readAccounts(db),
            categories: try LocalQueries.readCategories(db)
        )
    }

    static func transaction(from row: SQLiteRow) -> Transaction {
        Transaction(
            id: row.string("id") ?? "",
            date: row.string("occurred_at") ?? "",
            amount: row.double("amount") ?? 0,
            payee: row.string("payee") ?? "",
            memo: row.string("memo"),
            categoryName: row.string("category_name"),
            categoryEmoji: row.string("category_emoji"),
            accountName: row.string("account_name") ?? "",
            isTransfer: !row["transfer_pair_id"].isNull,
            needsReview: row.bool("needs_review"),
            isPending: row.bool("is_pending"),
            isScheduled: row.string("status") == "scheduled"
        )
    }

    // MARK: - Writing

    static func add(store: LocalStore, _ tx: NewTransaction) throws {
        try store.database.transaction {
            try store.database.run(
                """
                INSERT INTO transactions
                    (id, account_id, occurred_at, amount, currency, payee,
                     normalized_payee, memo, category_id, source, status, needs_review)
                VALUES (?, ?, ?, ?, 'EUR', ?, ?, ?, ?, 'manual', 'cleared', 0)
                """,
                [
                    .text(UUID().uuidString), .text(tx.accountId), .text(tx.occurredAt),
                    .real(tx.amount), .text(tx.payee), .text(normalize(tx.payee)),
                    tx.memo.map { SQLiteValue.text($0) } ?? .null,
                    tx.categoryId.map { SQLiteValue.text($0) } ?? .null,
                ]
            )
            try recomputeBalance(store, accountId: tx.accountId)
        }
    }

    static func approve(store: LocalStore, ids: [String]) throws {
        guard !ids.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        try store.database.run(
            """
            UPDATE transactions SET needs_review = 0, updated_at = datetime('now')
            WHERE id IN (\(placeholders))
            """,
            ids.map { SQLiteValue.text($0) }
        )
    }

    static func patch(store: LocalStore, id: String, _ patch: TxPatch) throws {
        var sets: [String] = []
        var values: [SQLiteValue] = []
        /*
         * The double optional carries three states, and all three matter.
         *
         * `.none` means the field was not part of this edit; `.some(nil)` means
         * clear it. Collapsing them would make un-categorising a row
         * impossible — the same reason the encoder is hand-rolled.
         */
        if let categoryId = patch.categoryId {
            sets.append("category_id = ?")
            values.append(categoryId.map { SQLiteValue.text($0) } ?? .null)
        }
        if let approve = patch.approve {
            sets.append("needs_review = ?")
            values.append(.integer(approve ? 0 : 1))
        }
        if let payee = patch.payee {
            sets.append("payee = ?")
            sets.append("normalized_payee = ?")
            values.append(.text(payee))
            values.append(.text(normalize(payee)))
        }
        if let memo = patch.memo {
            sets.append("memo = ?")
            values.append(memo.map { SQLiteValue.text($0) } ?? .null)
        }
        if let amount = patch.amount {
            sets.append("amount = ?")
            values.append(.real(amount))
        }
        if let occurredAt = patch.occurredAt {
            sets.append("occurred_at = ?")
            values.append(.text(occurredAt))
        }
        guard !sets.isEmpty else { return }
        sets.append("updated_at = datetime('now')")

        try store.database.transaction {
            try store.database.run(
                "UPDATE transactions SET \(sets.joined(separator: ", ")) WHERE id = ?",
                values + [.text(id)]
            )
            try recomputeAffectedBalance(store, transactionId: id)
        }
    }

    /// A soft delete, like every other surface: the row stays so a sync that
    /// re-fetches it from the bank does not resurrect it as new.
    static func delete(store: LocalStore, id: String) throws {
        try store.database.transaction {
            try store.database.run(
                "UPDATE transactions SET deleted_at = datetime('now') WHERE id = ?",
                [.text(id)]
            )
            try recomputeAffectedBalance(store, transactionId: id)
        }
    }

    // MARK: - Keeping balances true

    private static func recomputeAffectedBalance(_ store: LocalStore, transactionId: String) throws {
        guard let accountId = try store.database.scalar(
            "SELECT account_id FROM transactions WHERE id = ?", [.text(transactionId)]
        )?.string else { return }
        try recomputeBalance(store, accountId: accountId)
    }

    /*
     * Opening balance plus every cleared row, recomputed rather than nudged.
     *
     * Adjusting the stored balance by each delta drifts: one failed write, one
     * edit applied twice, and the number on the front screen is quietly wrong
     * with nothing to compare it against. Scheduled rows are excluded because
     * they have not happened — they belong to the forecast, not the balance.
     */
    private static func recomputeBalance(_ store: LocalStore, accountId: String) throws {
        let opening = try store.database.scalar(
            "SELECT opening_balance FROM accounts WHERE id = ?", [.text(accountId)]
        )?.double ?? 0
        let moved = try store.database.scalar(
            """
            SELECT coalesce(sum(amount), 0) FROM transactions
            WHERE account_id = ? AND deleted_at IS NULL AND status = 'cleared'
            """,
            [.text(accountId)]
        )?.double ?? 0
        try store.database.run(
            "UPDATE accounts SET current_balance = ?, updated_at = datetime('now') WHERE id = ?",
            [.real(((opening + moved) * 100).rounded() / 100), .text(accountId)]
        )
    }

    /// Lowercased, unaccented, punctuation-free — the same shape the other
    /// surfaces store so a rule written on one matches on the other.
    static func normalize(_ payee: String) -> String {
        payee
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
