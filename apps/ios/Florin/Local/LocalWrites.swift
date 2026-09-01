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

    /*
     * Two rows, one pair id.
     *
     * A transfer is not a transaction with a special flag — it is a movement
     * with two ends, and writing it as two paired rows is what lets every
     * existing query answer correctly without learning anything new: spending
     * skips paired legs, the plan skips them unless the far side is a debt,
     * and both balances move.
     *
     * On an account the bank also syncs, this leg is provisional: the real one
     * arrives with its own reference and absorbs it, exactly as a settled
     * charge absorbs the authorisation it replaces.
     */
    static func addTransfer(store: LocalStore, _ move: NewTransfer) throws {
        guard move.fromAccountId != move.toAccountId else {
            throw TransferFailure.sameAccount
        }
        let amount = abs(move.amount)
        guard amount > 0 else { throw TransferFailure.noAmount }

        let pair = UUID().uuidString
        let names = try store.database.query(
            "SELECT id, name FROM accounts WHERE id IN (?, ?)",
            [.text(move.fromAccountId), .text(move.toAccountId)]
        )
        func name(_ id: String) -> String {
            names.first { $0.string("id") == id }?.string("name") ?? "?"
        }

        try store.database.transaction {
            for (account, value, label) in [
                (move.fromAccountId, -amount, "Transfer to \(name(move.toAccountId))"),
                (move.toAccountId, amount, "Transfer from \(name(move.fromAccountId))"),
            ] {
                try store.database.run(
                    """
                    INSERT INTO transactions
                        (id, account_id, occurred_at, amount, currency, payee,
                         normalized_payee, memo, transfer_pair_id, source, status, needs_review)
                    VALUES (?, ?, ?, ?, 'EUR', ?, ?, ?, ?, 'manual', 'cleared', 0)
                    """,
                    [
                        .text(UUID().uuidString), .text(account), .text(move.occurredAt),
                        .real(value), .text(label), .text(normalize(label)),
                        move.memo.map { SQLiteValue.text($0) } ?? .null, .text(pair),
                    ]
                )
                try recomputeBalance(store, accountId: account)
            }
        }
    }

    /*
     * The other end of a movement the bank only showed one side of.
     *
     * Only the current account is bank-synced, so money sent to a savings
     * account leaves the ledger and never arrives: the balance falls, nothing
     * rises, and the net worth reports a loss that did not happen. This writes
     * the missing leg and pairs the two.
     */
    static func attachTransfer(store: LocalStore, txId: String, toAccountId: String) throws {
        let row = try store.database.query(
            "SELECT account_id, occurred_at, amount, payee FROM transactions WHERE id = ?",
            [.text(txId)]
        ).first
        guard let row, let source = row.string("account_id"),
              let day = row.string("occurred_at"), let amount = row.double("amount")
        else { throw TransferFailure.missing }
        guard source != toAccountId else { throw TransferFailure.sameAccount }

        let pair = UUID().uuidString
        let label = try store.database.scalar(
            "SELECT name FROM accounts WHERE id = ?", [.text(source)]
        )?.string ?? "?"

        /*
         * Adopt the landing if it is already there.
         *
         * The chosen account may already hold this movement — entered by hand
         * while the bank was still catching up, or synced in its own right.
         * Writing the mirror regardless would credit the money twice and
         * inflate the account by the whole amount. So look for an unpaired row
         * of the opposite sign within a few days first, and if one exists,
         * pair the two rows that already describe the truth.
         */
        let existing = try store.database.query(
            """
            SELECT id FROM transactions
            WHERE account_id = ? AND deleted_at IS NULL AND transfer_pair_id IS NULL
              AND abs(amount + ?) < 0.005
              AND abs(julianday(occurred_at) - julianday(?)) <= 5
            ORDER BY abs(julianday(occurred_at) - julianday(?)) LIMIT 1
            """,
            [.text(toAccountId), .real(amount), .text(day), .text(day)]
        ).first?.string("id")

        if let existing {
            try store.database.transaction {
                try store.database.run(
                    """
                    UPDATE transactions SET transfer_pair_id = ?, category_id = NULL,
                           needs_review = 0, updated_at = datetime('now')
                    WHERE id IN (?, ?)
                    """,
                    [.text(pair), .text(txId), .text(existing)]
                )
            }
            return
        }

        try store.database.transaction {
            try store.database.run(
                "UPDATE transactions SET transfer_pair_id = ?, updated_at = datetime('now') WHERE id = ?",
                [.text(pair), .text(txId)]
            )
            let mirror = amount < 0 ? "Transfer from \(label)" : "Transfer to \(label)"
            try store.database.run(
                """
                INSERT INTO transactions
                    (id, account_id, occurred_at, amount, currency, payee,
                     normalized_payee, transfer_pair_id, source, status, needs_review)
                VALUES (?, ?, ?, ?, 'EUR', ?, ?, ?, 'manual', 'cleared', 0)
                """,
                [
                    .text(UUID().uuidString), .text(toAccountId), .text(day),
                    .real(-amount), .text(mirror), .text(normalize(mirror)), .text(pair),
                ]
            )
            try recomputeBalance(store, accountId: toAccountId)
        }
    }

    enum TransferFailure: LocalizedError {
        case sameAccount, noAmount, missing
        var errorDescription: String? {
            switch self {
            case .sameAccount: "Choisissez deux comptes différents."
            case .noAmount: "Indiquez un montant."
            case .missing: "Cette opération n'existe plus."
            }
        }
    }

    /*
     * A statement, written into the ledger.
     *
     * Imported rows land in the review queue rather than straight into the
     * totals. They come from a file the app cannot check — a wrong column, a
     * date read the other way round, the same statement imported twice — and
     * the queue is exactly the place where a person looks at a row before it
     * counts. The categoriser gets its pass at them like anything else.
     */
    static func importRows(
        store: LocalStore, accountId: String, rows: [LocalImport.Row]
    ) throws -> (inserted: Int, skipped: Int) {
        var inserted = 0
        var skipped = 0
        try store.database.transaction {
            for row in rows {
                /*
                 * Already here?
                 *
                 * Statements overlap: the file downloaded in March covers
                 * February too, and importing both is the normal thing to do.
                 * Same account, same day, same amount, same label is the same
                 * operation — there is no identifier in a CSV to do better,
                 * and a bank does not post the identical line twice in a day.
                 */
                let existing = try store.database.scalar(
                    """
                    SELECT count(*) FROM transactions
                    WHERE account_id = ? AND deleted_at IS NULL
                      AND substr(occurred_at, 1, 10) = ?
                      AND abs(amount - ?) < 0.005
                      AND normalized_payee = ?
                    """,
                    [
                        .text(accountId), .text(row.day), .real(row.amount),
                        .text(normalize(row.payee)),
                    ]
                )?.int ?? 0
                guard existing == 0 else { skipped += 1; continue }

                try store.database.run(
                    """
                    INSERT INTO transactions
                        (id, account_id, occurred_at, amount, currency, payee,
                         normalized_payee, memo, source, status, needs_review)
                    VALUES (?, ?, ?, ?, 'EUR', ?, ?, ?, 'import', 'cleared', 1)
                    """,
                    [
                        .text(UUID().uuidString), .text(accountId), .text(row.day),
                        .real(row.amount), .text(row.payee),
                        .text(normalize(row.payee)),
                        row.memo.map { SQLiteValue.text($0) } ?? .null,
                    ]
                )
                inserted += 1
            }
            try recomputeBalance(store, accountId: accountId)
        }
        if inserted > 0 { _ = try? LocalCategoriser.backfill(store: store) }
        return (inserted, skipped)
    }

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
            try syncLoanMirror(store, transactionId: id)
        }
    }

    /*
     * A repayment has two sides, and the phone only ever wrote one.
     *
     * Filing the monthly instalment under the category that mirrors a loan is
     * what tells the ledger the debt moved. On the server that writes a
     * counterpart row on the loan account and the remaining debt advances one
     * step down the amortisation schedule. On the device nothing happened at
     * all: the money left the current account and the loan sat exactly where it
     * was, so a repayment read as pure consumption and every month widened the
     * gap.
     *
     * The mirror deliberately carries no category. The plan sums spending by
     * category across every account, so a categorised counterpart would cancel
     * the very instalment it represents — 136 € out, 136 € in, nothing spent.
     */
    /*
     * Instalments already filed, from before there was a mirror to write.
     *
     * `backfill` only looks at rows with no category, so a repayment the
     * categoriser filed last month is invisible to it for ever. Those are
     * precisely the ones missing their counterpart — on this ledger, twenty-six
     * repayments on the current account against twenty-four on the loan.
     *
     * Cheap when there is nothing to do: one indexed lookup that finds no rows.
     */
    /*
     * Instalments paid twice, taken back.
     *
     * A catch-up that matched on pair ids wrote a second counterpart for every
     * repayment on an imported ledger, because there the two legs of a transfer
     * carry different ids. The loan then read fifty-three instalments where
     * there were twenty-six, and the remaining debt roughly halved.
     *
     * One repayment per calendar month is the rule the schedule assumes, so
     * anything beyond the first in a month is the mistake. The oldest row is
     * kept — it is the one that came from the server, with the real date.
     */
    @discardableResult
    static func dropDuplicateLoanMirrors(store: LocalStore) throws -> Int {
        let extra = try store.database.query(
            """
            SELECT m.id FROM transactions m
            JOIN accounts a ON a.id = m.account_id AND a.kind = 'loan'
            WHERE m.deleted_at IS NULL
              AND EXISTS (
                SELECT 1 FROM transactions k
                WHERE k.account_id = m.account_id AND k.deleted_at IS NULL
                  AND abs(k.amount - m.amount) < 0.005
                  AND abs(julianday(k.occurred_at) - julianday(m.occurred_at)) <= 5
                  AND (k.created_at < m.created_at
                       OR (k.created_at = m.created_at AND k.id < m.id))
              )
            """
        ).compactMap { $0.string("id") }
        guard !extra.isEmpty else { return 0 }
        try store.database.transaction {
            for id in extra {
                try store.database.run("DELETE FROM transactions WHERE id = ?", [.text(id)])
            }
        }
        return extra.count
    }

    @discardableResult
    static func reconcileLoanMirrors(store: LocalStore) throws -> Int {
        let orphans = try store.database.query(
            """
            SELECT t.id FROM transactions t
            JOIN categories c ON c.id = t.category_id
            WHERE c.linked_loan_account_id IS NOT NULL
              AND t.deleted_at IS NULL
              /*
               * Matched on what the row IS, not on a shared identifier.
               *
               * A ledger imported from a server has the two legs of a transfer
               * under different pair ids — the import mints one per leg — so
               * asking "does a row share my pair id" answers no for every
               * repayment that already has a counterpart, and the catch-up
               * writes a second one. That turned twenty-six instalments into
               * fifty-three and halved the debt.
               *
               * Same loan, same day, opposite amount is the same repayment
               * whatever either row calls its pair.
               */
              AND NOT EXISTS (
                SELECT 1 FROM transactions m
                WHERE m.account_id = c.linked_loan_account_id
                  AND m.deleted_at IS NULL
                  AND abs(m.amount + t.amount) < 0.005
                  AND abs(julianday(m.occurred_at) - julianday(t.occurred_at)) <= 5
              )
            """
        ).compactMap { $0.string("id") }

        /*
         * The instalment, recognised by its amount.
         *
         * Waiting to be told which category means "this is the loan" is a lot
         * of ceremony for a debit that is the same to the cent every month and
         * already has its amount written on the loan. So a payment matching the
         * contract's mensualité exactly, leaving a cash account, is treated as
         * one — no category needed, nothing to configure beyond the contract
         * itself.
         *
         * Two guards keep it honest. The match is to the cent, not
         * approximate: an ordinary purchase of 135,91 € is possible and a
         * purchase of 135,90 € is not this. And one per calendar month per
         * loan, so a coincidence in a month already accounted for is ignored
         * rather than paying the loan twice.
         */
        let detected = try store.database.query(
            """
            SELECT t.id FROM transactions t
            JOIN accounts a ON a.id = t.account_id
            JOIN accounts loan ON loan.kind = 'loan' AND loan.loan_monthly_payment > 0
            WHERE t.deleted_at IS NULL AND a.kind <> 'loan'
              AND t.amount < 0
              AND abs(abs(t.amount) - loan.loan_monthly_payment) < 0.005
              /*
               * A window, because a month boundary is not one.
               *
               * "One counterpart per calendar month" looked like the rule and
               * is not: a debit taken on the 30th of April is the May
               * instalment, and the bank dates the two sides differently often
               * enough that they land either side of a month end. The guard
               * then saw no counterpart in "the same month" and wrote a second
               * one — which is how twenty-six repayments became twenty-eight.
               *
               * Five days around the payment is what a bank's own posting
               * spread looks like, and no two instalments of the same loan are
               * that close together.
               */
              AND NOT EXISTS (
                SELECT 1 FROM transactions m
                WHERE m.account_id = loan.id AND m.deleted_at IS NULL
                  AND abs(m.amount + t.amount) < 0.005
                  AND abs(julianday(m.occurred_at) - julianday(t.occurred_at)) <= 5
              )
            GROUP BY t.id
            """
        ).compactMap { $0.string("id") }

        let all = Array(Set(orphans + detected))
        guard !all.isEmpty else { return 0 }
        try store.database.transaction {
            for id in all {
                try syncLoanMirror(store, transactionId: id)
            }
        }
        return all.count
    }

    static func syncLoanMirror(_ store: LocalStore, transactionId id: String) throws {
        let row = try store.database.query(
            """
            SELECT t.amount, t.occurred_at, t.payee, t.transfer_pair_id,
                   t.category_id, c.linked_loan_account_id AS loan_id
            FROM transactions t
            LEFT JOIN categories c ON c.id = t.category_id
            WHERE t.id = ?
            """,
            [.text(id)]
        ).first
        guard let row else { return }
        /*
         * A category, when there is one, is a decision. The amount is a guess.
         *
         * So the guess only runs where nothing has been decided: an unfiled
         * debit matching the contract's mensualité to the cent is the
         * instalment, and needs no setting. But filing that same row under
         * Courses says plainly that it is not — and must take the counterpart
         * away rather than being overruled by the arithmetic.
         */
        var loanId = row.string("loan_id")
        if loanId == nil, row.string("category_id") == nil,
           let amount = row.double("amount"), amount < 0 {
            loanId = try store.database.scalar(
                """
                SELECT id FROM accounts
                WHERE kind = 'loan' AND loan_monthly_payment > 0
                  AND abs(loan_monthly_payment - ?) < 0.005
                LIMIT 1
                """,
                [.real(abs(amount))]
            )?.string
        }

        /*
         * Re-filed elsewhere, so the old counterpart has to go.
         *
         * Without this, moving a payment out of the loan category leaves its
         * mirror behind and the debt keeps the step it should give back.
         */
        let existing = try store.database.query(
            """
            SELECT m.id, m.account_id FROM transactions m
            JOIN accounts a ON a.id = m.account_id
            WHERE m.transfer_pair_id = (SELECT transfer_pair_id FROM transactions WHERE id = ?)
              AND m.id <> ? AND a.kind = 'loan' AND m.deleted_at IS NULL
            """,
            [.text(id), .text(id)]
        ).first

        if let existing, existing.string("account_id") != loanId {
            try store.database.run(
                "DELETE FROM transactions WHERE id = ?", [.text(existing.string("id") ?? "")]
            )
            try store.database.run(
                "UPDATE transactions SET transfer_pair_id = NULL WHERE id = ?", [.text(id)]
            )
            if let account = existing.string("account_id") {
                try recomputeBalance(store, accountId: account)
            }
        }

        guard let loanId, existing?.string("account_id") != loanId else {
            if let loanId { try recomputeBalance(store, accountId: loanId) }
            return
        }

        let amount = row.double("amount") ?? 0
        let pair = row.string("transfer_pair_id") ?? UUID().uuidString
        let label = "↳ \(row.string("payee") ?? "")"
        try store.database.run(
            "UPDATE transactions SET transfer_pair_id = ? WHERE id = ?",
            [.text(pair), .text(id)]
        )
        try store.database.run(
            """
            INSERT INTO transactions
                (id, account_id, occurred_at, amount, currency, payee, normalized_payee,
                 category_id, source, status, needs_review, transfer_pair_id)
            VALUES (?, ?, ?, ?, 'EUR', ?, ?, NULL, 'manual', 'cleared', 0, ?)
            """,
            [
                .text(UUID().uuidString), .text(loanId),
                .text(row.string("occurred_at") ?? ""), .real(-amount),
                .text(label), .text(normalize(label)), .text(pair),
            ]
        )
        try recomputeBalance(store, accountId: loanId)
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
