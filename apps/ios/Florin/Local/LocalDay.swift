import Foundation

/// One day of the ledger, for the sheet behind a calendar square.
///
/// The headline figure has to be the same number the square was coloured with,
/// or tapping a dark cell and reading a different total makes the grid look
/// broken. `spent` therefore repeats `LocalAnalysis.dailySpend`'s predicate
/// exactly — cleared, settled, not a transfer, on a live account, in an expense
/// group — and the breakdown under it is that same sum cut by category.
///
/// The list below is deliberately wider: everything that touched the ledger
/// that day, income and transfers included. Someone who opens a day wants to
/// know what happened, not to see the subset that happens to feed one metric.
/// Amounts are signed, so the rows that sit outside the headline are legible as
/// such rather than silently missing.
struct DayDetail: Sendable {
    struct CategorySlice: Sendable, Identifiable {
        let id: String
        let name: String
        let emoji: String?
        let amount: Double
    }

    /// `yyyy-MM-dd`.
    let day: String
    /// Positive when money left, matching the calendar square.
    let spent: Double
    let categories: [CategorySlice]
    let transactions: [Transaction]

    var isEmpty: Bool { transactions.isEmpty }
}

enum LocalDay {
    /// Its own rather than shared: the two callers that already round do it
    /// privately, and a day's figures should not start depending on either.
    private static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }

    /// Everything the sheet needs, in three queries against one day.
    static func detail(store: LocalStore, day: String) throws -> DayDetail {
        let db = store.database
        return DayDetail(
            day: day,
            spent: try spent(db, day: day),
            categories: try categories(db, day: day),
            transactions: try transactions(db, day: day)
        )
    }

    // MARK: - The headline

    /*
     * The predicate is copied from LocalAnalysis.dailySpend rather than shared,
     * because the two answer different questions that happen to agree: one
     * colours a grid over thirty days, the other explains a single square. If
     * the grid's definition of spending changes, this should be changed with
     * it deliberately — a shared helper would move it silently and the sheet
     * would stop matching without anyone noticing.
     */
    private static func spent(_ db: SQLiteDatabase, day: String) throws -> Double {
        let total = try db.scalar(
            """
            SELECT coalesce(sum(t.amount), 0)
            FROM transactions t
            JOIN accounts a ON a.id = t.account_id
            JOIN categories c ON c.id = t.category_id
            JOIN category_groups g ON g.id = c.group_id
            WHERE t.deleted_at IS NULL AND t.status = 'cleared' AND t.is_pending = 0
              AND t.transfer_pair_id IS NULL AND a.is_archived = 0
              AND g.kind = 'expense' AND substr(t.occurred_at, 1, 10) = ?
            """,
            [.text(day)]
        )?.double ?? 0
        return round2(-total)
    }

    // MARK: - Where it went

    private static func categories(
        _ db: SQLiteDatabase, day: String
    ) throws -> [DayDetail.CategorySlice] {
        try db.query(
            """
            SELECT c.id, c.name, c.emoji, coalesce(sum(t.amount), 0) AS total
            FROM transactions t
            JOIN accounts a ON a.id = t.account_id
            JOIN categories c ON c.id = t.category_id
            JOIN category_groups g ON g.id = c.group_id
            WHERE t.deleted_at IS NULL AND t.status = 'cleared' AND t.is_pending = 0
              AND t.transfer_pair_id IS NULL AND a.is_archived = 0
              AND g.kind = 'expense' AND substr(t.occurred_at, 1, 10) = ?
            GROUP BY c.id, c.name, c.emoji
            ORDER BY total ASC
            """,
            [.text(day)]
        ).compactMap { row in
            let amount = round2(-(row.double("total") ?? 0))
            guard amount > 0 else { return nil }
            return DayDetail.CategorySlice(
                id: row.string("id") ?? "",
                name: row.string("name") ?? "",
                emoji: row.string("emoji"),
                amount: amount
            )
        }
    }

    // MARK: - What happened

    private static func transactions(
        _ db: SQLiteDatabase, day: String
    ) throws -> [Transaction] {
        try db.query(
            """
            SELECT t.id, t.occurred_at, t.amount, t.payee, t.memo,
                   c.name AS category_name, c.emoji AS category_emoji,
                   a.name AS account_name, t.transfer_pair_id,
                   t.needs_review, t.is_pending, t.status
            FROM transactions t
            LEFT JOIN categories c ON c.id = t.category_id
            LEFT JOIN accounts a ON a.id = t.account_id
            WHERE t.deleted_at IS NULL AND substr(t.occurred_at, 1, 10) = ?
            ORDER BY abs(t.amount) DESC, t.id
            """,
            [.text(day)]
        ).map { row in
            Transaction(
                id: row.string("id") ?? "",
                date: row.string("occurred_at") ?? "",
                amount: round2(row.double("amount") ?? 0),
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
    }
}
