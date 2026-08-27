import Foundation

/// Guessing a category from the ledger's own history.
///
/// A port of the server's similarity layer. There are no rules to apply — the
/// account has none — so the signal is the user's own past: a payee that has
/// been filed the same way nine times is filed that way again. Everything runs
/// on data already on the device; no network, no model, nothing to train.
///
/// Two paths, in order:
///
///  1. The same normalised payee. Dominant in real bank data — "ORANGE" bills
///     every month with the same string — and the modal category across those
///     rows is the answer.
///  2. Token overlap, when nothing matches exactly. Capped below the exact
///     path so a fuzzy hit can never outrank a clean one.
enum LocalCategoriser {
    struct Suggestion {
        let categoryId: String
        /// 0…1. Applied automatically from 0.8; below that it is left alone
        /// rather than guessed at, because a wrong category is worse than
        /// none — it lands silently in a budget.
        let confidence: Double
    }

    static func suggest(
        store: LocalStore,
        payee: String,
        amount: Double,
        accountId: String
    ) throws -> Suggestion? {
        let normalized = LocalLedger.normalize(payee)
        guard !normalized.isEmpty else { return nil }

        // 1. Exact payee.
        let exact = try store.database.query(
            """
            SELECT category_id, count(*) AS hits
            FROM transactions
            WHERE normalized_payee = ? AND category_id IS NOT NULL
              AND deleted_at IS NULL
            GROUP BY category_id ORDER BY hits DESC LIMIT 2
            """,
            [.text(normalized)]
        )
        if let best = exact.first, let id = best.string("category_id") {
            let hits = best.int("hits") ?? 1
            let runnerUp = exact.count > 1 ? (exact[1].int("hits") ?? 0) : 0
            // One past row is a coincidence; a clear majority is a habit.
            let share = Double(hits) / Double(hits + runnerUp)
            let confidence = min(0.98, 0.6 + 0.1 * Double(min(hits, 3)) + 0.1 * share)
            return Suggestion(categoryId: id, confidence: confidence)
        }

        // 2. Token overlap against payees sharing the longest word.
        let words = normalized.split(separator: " ").map(String.init).filter { $0.count >= 3 }
        guard let anchor = words.max(by: { $0.count < $1.count }) else { return nil }

        let pool = try store.database.query(
            """
            SELECT normalized_payee, category_id, count(*) AS hits
            FROM transactions
            WHERE category_id IS NOT NULL AND deleted_at IS NULL
              AND normalized_payee LIKE ?
            GROUP BY normalized_payee, category_id
            ORDER BY hits DESC LIMIT 60
            """,
            [.text("%\(anchor)%")]
        )

        let candidate = Set(words)
        var bestScore = 0.0
        var bestId: String?
        for row in pool {
            guard let id = row.string("category_id"),
                  let other = row.string("normalized_payee")
            else { continue }
            let otherWords = Set(
                other.split(separator: " ").map(String.init).filter { $0.count >= 3 }
            )
            guard !otherWords.isEmpty else { continue }
            let overlap = Double(candidate.intersection(otherWords).count)
            let union = Double(candidate.union(otherWords).count)
            guard union > 0 else { continue }
            // Jaccard, capped so it stays under any exact-payee hit.
            let score = min(0.85, overlap / union)
            if score > bestScore {
                bestScore = score
                bestId = id
            }
        }
        guard let bestId, bestScore >= 0.5 else { return nil }
        return Suggestion(categoryId: bestId, confidence: bestScore)
    }

    /// Fills in every uncategorised row this ledger can be confident about.
    ///
    /// Run after a sync so rows that arrived before their neighbours were
    /// filed still get their answer — including the upcoming ones, which is
    /// the point: seeing what a debit *is* before it lands is most of why
    /// anyone looks at them.
    @discardableResult
    static func backfill(store: LocalStore, limit: Int = 500) throws -> Int {
        let rows = try store.database.query(
            """
            SELECT id, payee, amount, account_id
            FROM transactions
            WHERE category_id IS NULL AND deleted_at IS NULL
            ORDER BY occurred_at DESC LIMIT ?
            """,
            [.integer(Int64(limit))]
        )

        var filled = 0
        for row in rows {
            guard let id = row.string("id"),
                  let payee = row.string("payee"),
                  let accountId = row.string("account_id")
            else { continue }
            guard let hit = try suggest(
                store: store,
                payee: payee,
                amount: row.double("amount") ?? 0,
                accountId: accountId
            ), hit.confidence >= 0.8 else { continue }

            try store.database.run(
                "UPDATE transactions SET category_id = ?, updated_at = datetime('now') WHERE id = ?",
                [.text(hit.categoryId), .text(id)]
            )
            filled += 1
        }
        return filled
    }
}
