import Foundation

/// Guessing a category from the ledger's own past.
///
/// There are no rules to apply and no model to run: the account has none, and
/// the server it mirrors categorises the same way. The signal is the user's own
/// history — a payee filed the same way for months is filed that way again.
/// Everything happens on the device, against data already there.
///
/// The hard part is that bank labels are noisy in a specific way. The same
/// monthly direct debit arrives with a different reference number every time,
/// so the label never repeats verbatim, and the words that *do* repeat are
/// mostly the bank's own formatting — "PREL", "VIREMENT", "CARTE". Two ideas
/// carry the whole thing:
///
///  - Digits are dropped. A 25-digit mandate reference identifies the charge,
///    not the merchant, and keeping it makes every debit look unique.
///  - A word is weighted by how *concentrated* it is on one category, not by
///    how rare it is. Measured on the real ledger, "prel" appears in only 12
///    transactions and "orange" in 18 — by rarity alone the bank's prefix
///    outranks the merchant. Spread across four categories it tells you
///    nothing, and the weighting says so: 1.42 against 4.80.
///
/// Validated by holdout on 2 771 real transactions: at the applied threshold,
/// 71% of rows get a category and 89% of those are the one the user had chosen.
enum LocalCategoriser {
    struct Suggestion {
        let categoryId: String
        let confidence: Double
    }

    /// Applied from here. Below it the row is left uncategorised rather than
    /// guessed at: bank rows arrive in the review queue where they can be
    /// approved in bulk, so a wrong category is not merely unhelpful — it gets
    /// waved through and lands silently inside a budget.
    static let applyThreshold = 0.8

    // MARK: - The ledger's memory

    /// Everything the past can say, indexed once per run.
    ///
    /// Built once and reused across every row of a sync: rebuilding it per
    /// transaction would re-read the whole ledger each time.
    struct Memory {
        fileprivate let weights: [String: Double]
        fileprivate let rows: [Row]
        /// token → indices of rows holding it, so scoring only visits rows that
        /// can actually match instead of the whole ledger.
        fileprivate let postings: [String: [Int]]
        /// The word-only fingerprint of a label → how its past was filed.
        fileprivate let signatures: [String: [String: Int]]
        /// An exact amount, in cents → how rows of that amount were filed.
        fileprivate let amounts: [Int: [String: Int]]
        /// category id → the kind of the group holding it ("expense", "income").
        /// A guess that contradicts the sign of the row is not a weak guess,
        /// it is a wrong one — see `fits`.
        fileprivate let kinds: [String: String]
        /// Every credit already filed, stripped of its words — see `rhythm`.
        fileprivate let beats: [Beat]

        var isEmpty: Bool { rows.isEmpty }
    }

    fileprivate struct Row {
        let tokens: Set<String>
        let categoryId: String
        let amount: Double
        let accountId: String
    }

    /// A filed credit reduced to its shape: when, on what account, how much.
    fileprivate struct Beat {
        let month: String
        let day: Int
        let amount: Double
        let accountId: String
        let categoryId: String
    }

    /*
     * A category whose group runs the other way is not a candidate.
     *
     * The scoring is built entirely on words, and a person's own name is a
     * word like any other: a 500 € instant transfer to himself matched the
     * salary and refund rows that carry the same name and was filed under
     * "Gains additionnels" — an income category, on money going out. It looked
     * like a bad guess and was worse than that. A filed row leaves the
     * transfer detector (which only offers uncategorised rows), so the one
     * question worth asking about it was never asked, and the review queue
     * offered categories and nothing else. The sign is the one thing about a
     * transaction that is never ambiguous; nothing should be allowed to
     * contradict it.
     *
     * It runs one way only, though. Money leaving is never earnings, so an
     * income category is out of the question for a debit — but money arriving
     * is very often a *refund*, and a refund belongs with the purchase it
     * cancels: a shop's credit filed under "Vêtements" nets off the shirt that
     * was sent back, filed under "Gains additionnels" it counts as a month's
     * income and leaves the shirt at full price. Refusing every expense
     * category to a credit left the ledger's own answer unreachable and the
     * catch-all income category the only one that fitted.
     */
    fileprivate static func fits(_ categoryId: String, _ amount: Double, _ kinds: [String: String]) -> Bool {
        switch kinds[categoryId] {
        case "income": amount >= 0
        default: true
        }
    }

    static func remember(store: LocalStore) throws -> Memory {
        var kinds: [String: String] = [:]
        for row in try store.database.query(
            "SELECT c.id, g.kind FROM categories c JOIN category_groups g ON g.id = c.group_id"
        ) {
            if let id = row.string("id"), let kind = row.string("kind") { kinds[id] = kind }
        }

        let rows = try store.database.query(
            """
            SELECT payee, category_id, amount, account_id
            FROM transactions
            WHERE category_id IS NOT NULL AND deleted_at IS NULL AND payee IS NOT NULL
            ORDER BY occurred_at DESC LIMIT 8000
            """
        )

        var entries: [Row] = []
        var frequency: [String: Int] = [:]
        var spread: [String: [String: Int]] = [:]
        var signatures: [String: [String: Int]] = [:]
        var amounts: [Int: [String: Int]] = [:]
        var postings: [String: [Int]] = [:]

        for row in rows {
            guard let payee = row.string("payee"),
                  let categoryId = row.string("category_id")
            else { continue }
            let tokens = Self.tokens(of: payee)
            guard !tokens.isEmpty else { continue }

            let index = entries.count
            entries.append(
                Row(
                    tokens: tokens,
                    categoryId: categoryId,
                    amount: row.double("amount") ?? 0,
                    accountId: row.string("account_id") ?? ""
                )
            )
            signatures[signature(of: tokens), default: [:]][categoryId, default: 0] += 1
            amounts[cents(row.double("amount") ?? 0), default: [:]][categoryId, default: 0] += 1
            for token in tokens {
                frequency[token, default: 0] += 1
                spread[token, default: [:]][categoryId, default: 0] += 1
                postings[token, default: []].append(index)
            }
        }

        let total = max(entries.count, 1)
        var weights: [String: Double] = [:]
        weights.reserveCapacity(frequency.count)
        for (token, count) in frequency {
            let categories = spread[token] ?? [:]
            let seen = categories.values.reduce(0, +)
            var entropy = 0.0
            for value in categories.values where value > 0 {
                let share = Double(value) / Double(seen)
                entropy -= share * log(share)
            }
            // One category → concentration 1. Evenly spread over many → 0.
            let concentration = categories.count > 1
                ? 1 - entropy / log(Double(categories.count))
                : 1.0
            let rarity = log(1 + Double(total) / Double(1 + count))
            weights[token] = rarity * (0.15 + 0.85 * concentration)
        }

        /*
         * Credits only, and every one of them.
         *
         * A row whose label tokenises to nothing never reaches `entries`, and
         * a label made of an account number very nearly is nothing — which is
         * exactly the row `rhythm` exists for. So the beats are read on their
         * own, from the date and the amount, which no bank can garble.
         */
        var beats: [Beat] = []
        for row in try store.database.query(
            """
            SELECT substr(occurred_at, 1, 10) AS day, amount, account_id, category_id
            FROM transactions
            WHERE category_id IS NOT NULL AND deleted_at IS NULL AND amount > 0
            ORDER BY occurred_at DESC LIMIT 4000
            """
        ) {
            guard let day = row.string("day"), day.count >= 10,
                  let categoryId = row.string("category_id"),
                  let accountId = row.string("account_id"),
                  let amount = row.double("amount"),
                  let number = Int(day.dropFirst(8).prefix(2))
            else { continue }
            beats.append(
                Beat(
                    month: String(day.prefix(7)), day: number,
                    amount: amount, accountId: accountId, categoryId: categoryId
                )
            )
        }

        return Memory(
            weights: weights, rows: entries, postings: postings,
            signatures: signatures, amounts: amounts, kinds: kinds, beats: beats
        )
    }

    // MARK: - Asking

    static func suggest(
        _ memory: Memory, payee: String, amount: Double, accountId: String,
        date: String = ""
    ) -> Suggestion? {
        let spoken = fromWords(memory, payee: payee, amount: amount, accountId: accountId)
        if let spoken, spoken.confidence >= applyThreshold { return spoken }
        let beaten = rhythm(memory, date: date, amount: amount, accountId: accountId)
        return beaten ?? spoken
    }

    /*
     * The same credit, month after month, whatever the bank calls it today.
     *
     * A salary is announced by the bank under one label and booked under
     * another; some months it arrives as nothing but an account number and a
     * surname. The words then have no answer, or worse: a person's own name
     * runs through every transfer they ever made, so the scoring picks the
     * income category that name happens to be most common in. The one thing
     * that does not move is the shape — same account, same size, same week of
     * the month — and a credit that has kept that shape for four months
     * running, filed the same way every time, is not a guess.
     *
     * Kept deliberately narrow. Measured over the whole ledger this fires on
     * twelve rows and gets twelve right; loosened to debits it drops to
     * two thirds, because a great many purchases repeat at the same price
     * without being the same thing at all. So: credits, a tight band, a
     * unanimous past, and only ever after the words have failed.
     */
    static let rhythmBand = 0.05
    static let rhythmMonths = 4
    static let rhythmDays = 5

    private static func rhythm(
        _ memory: Memory, date: String, amount: Double, accountId: String
    ) -> Suggestion? {
        guard amount > 0, date.count >= 10, !accountId.isEmpty else { return nil }
        let month = String(date.prefix(7))
        guard let day = Int(date.dropFirst(8).prefix(2)) else { return nil }

        // One vote per month: a month that paid twice does not count twice.
        var voted: [String: (categoryId: String, distance: Double)] = [:]
        for beat in memory.beats where beat.accountId == accountId && beat.month < month {
            let distance = abs(beat.amount - amount)
            guard distance <= rhythmBand * amount else { continue }
            let apart = abs(beat.day - day)
            guard min(apart, 31 - apart) <= rhythmDays else { continue }
            if let kept = voted[beat.month], kept.distance <= distance { continue }
            voted[beat.month] = (beat.categoryId, distance)
        }
        guard voted.count >= rhythmMonths else { return nil }

        let agreed = Set(voted.values.map(\.categoryId))
        guard agreed.count == 1, let categoryId = agreed.first,
              fits(categoryId, amount, memory.kinds)
        else { return nil }
        // Enough to file, never more certain than a label the ledger knows.
        return Suggestion(categoryId: categoryId, confidence: applyThreshold + 0.05)
    }

    private static func fromWords(
        _ memory: Memory, payee: String, amount: Double, accountId: String
    ) -> Suggestion? {
        let tokens = Self.tokens(of: payee)
        guard !tokens.isEmpty, !memory.isEmpty else { return nil }

        /*
         * The same label, ignoring its reference numbers.
         *
         * This is what catches a monthly subscription whose mandate reference
         * changes every time — the words are identical, so the past is a
         * direct answer and there is nothing to weigh.
         */
        if let past = memory.signatures[signature(of: tokens)]?
            .filter({ fits($0.key, amount, memory.kinds) }), !past.isEmpty {
            let ranked = past.sorted { $0.value > $1.value }
            let best = ranked[0]
            let runnerUp = ranked.count > 1 ? ranked[1].value : 0
            let share = Double(best.value) / Double(best.value + runnerUp)
            // One past example is a coincidence; a repeated one is a habit.
            let confidence = min(0.99, 0.62 + 0.1 * Double(min(best.value, 3)) + 0.07 * share)
            return Suggestion(categoryId: best.key, confidence: confidence)
        }

        /*
         * Words this ledger has never seen say nothing about it.
         *
         * Counting them as evidence *against* a match is what buried the real
         * case this was written for: the bank writes "Prel" where the ledger
         * holds "PRELEVEMENT", and that one unknown word was enough to sink a
         * charge whose merchant name matched eighteen past rows exactly.
         */
        let known = tokens.filter { memory.weights[$0] != nil }
        guard !known.isEmpty else { return nil }
        let mass = known.reduce(0.0) { $0 + (memory.weights[$1] ?? 0) }
        guard mass > 0 else { return nil }

        var visiting = Set<Int>()
        for token in known {
            for index in memory.postings[token] ?? [] { visiting.insert(index) }
        }
        guard !visiting.isEmpty else { return nil }

        var best: [String: Double] = [:]
        for index in visiting {
            let row = memory.rows[index]
            let shared = known.intersection(row.tokens)
            guard !shared.isEmpty, fits(row.categoryId, amount, memory.kinds) else { continue }
            var score = shared.reduce(0.0) { $0 + (memory.weights[$1] ?? 0) } / mass
            // A short label swallowed whole by a long one is a weaker match
            // than two labels that agree on most of their words.
            score *= 0.85 + 0.15 * (Double(shared.count) / Double(row.tokens.count))
            if amount != 0, row.amount != 0 {
                let ratio = abs(amount) / abs(row.amount)
                if abs(abs(amount) - abs(row.amount)) < 0.005 {
                    score *= 1.15
                } else if ratio >= 0.7, ratio <= 1.43 {
                    score *= 1.05
                }
            }
            if row.accountId == accountId { score *= 1.03 }
            if score > (best[row.categoryId] ?? 0) { best[row.categoryId] = score }
        }

        let ranked = best.sorted { $0.value > $1.value }
        guard let winner = ranked.first, winner.value > 0 else { return nil }
        let runnerUp = ranked.count > 1 ? ranked[1].value : 0
        // A strong match with an equally strong rival is a coin toss, and
        // deserves to be reported as one.
        let margin = (winner.value - runnerUp) / winner.value
        var confidence = min(0.99, winner.value * (0.6 + 0.4 * margin))

        /*
         * The same amount, to the cent, month after month.
         *
         * A recurring payment is not merely similar to its own past — it is
         * identical in the one field that never drifts. That is a different
         * kind of evidence from a matching name, and it rescues the case the
         * words cannot settle: a direct debit whose label is the user's own
         * bank, a phrase that appears across half the ledger.
         *
         * Only ever a promotion of the category the words already chose, so it
         * cannot invent one. Measured over five holdout draws it left
         * precision untouched at 86%, which is the whole reason it is a
         * separate signal and not a heavier thumb on the amount comparison —
         * that cost four points.
         */
        if amount != 0, let past = memory.amounts[cents(amount)] {
            let seen = past.values.reduce(0, +)
            if let dominant = past.max(by: { $0.value < $1.value }),
               seen >= 4,
               Double(dominant.value) / Double(seen) >= 0.85,
               dominant.key == winner.key {
                confidence = min(0.99, confidence + 0.3)
            }
        }

        return Suggestion(categoryId: winner.key, confidence: confidence)
    }

    /// Amounts are compared as whole cents so that floating point cannot make
    /// two identical debits look different.
    private static func cents(_ amount: Double) -> Int {
        Int((abs(amount) * 100).rounded())
    }

    // MARK: - Applying

    /// Names every row the app brought in and the user has not yet filed.
    ///
    /// The test is whether the user has passed judgement on the row, not where
    /// it came from. Anything still in the review queue, still pending, or
    /// dated ahead is unfiled by definition; a row they approved is left
    /// exactly as they left it, uncategorised included, because that was a
    /// decision and not an omission to correct. Rows added by hand are
    /// approved as they are written, so they are never touched.
    ///
    /// This used to also require `source = 'enable_banking'`, which quietly
    /// excluded the rows most in need of it: a ledger imported from the
    /// server is written with source `server`, so after an import every
    /// upcoming debit stayed unnamed and had to be filed by hand.
    @discardableResult
    static func backfill(store: LocalStore) throws -> Int {
        let pending = try store.database.query(
            """
            SELECT id, payee, amount, account_id, occurred_at
            FROM transactions
            WHERE category_id IS NULL AND deleted_at IS NULL
              AND (needs_review = 1 OR is_pending = 1
                   OR substr(occurred_at, 1, 10) > date('now'))
            ORDER BY occurred_at DESC LIMIT 1000
            """
        )
        guard !pending.isEmpty else { return 0 }

        let memory = try remember(store: store)
        guard !memory.isEmpty else { return 0 }

        var filled = 0
        try store.database.transaction {
            for row in pending {
                guard let id = row.string("id"), let payee = row.string("payee") else { continue }
                guard let hit = suggest(
                    memory,
                    payee: payee,
                    amount: row.double("amount") ?? 0,
                    accountId: row.string("account_id") ?? "",
                    date: String((row.string("occurred_at") ?? "").prefix(10))
                ), hit.confidence >= applyThreshold else { continue }

                try store.database.run(
                    """
                    UPDATE transactions
                    SET category_id = ?, updated_at = datetime('now')
                    WHERE id = ? AND category_id IS NULL
                    """,
                    [.text(hit.categoryId), .text(id)]
                )
                /*
                 * A loan repayment filed by the machine is still a repayment.
                 *
                 * The mirror was written from the categorise path only, which
                 * is the one a person takes. A monthly instalment is the most
                 * recognisable payee in a ledger, so the categoriser files it
                 * unattended above its threshold and the row never went that
                 * way — the debt stayed put for exactly the payments most
                 * likely to be automatic.
                 */
                try LocalLedger.syncLoanMirror(store, transactionId: id)
                filled += 1
            }
        }
        return filled
    }

    // MARK: - Words

    /// Letter-bearing words of three characters or more.
    ///
    /// Digits are dropped wholesale. A mandate reference, a card number or an
    /// embedded date changes on every charge, so keeping them makes each one
    /// look like a payee never seen before — which is exactly what happened.
    static func tokens(of payee: String) -> Set<String> {
        var out = Set<String>()
        let folded = payee.folding(
            options: [.diacriticInsensitive, .caseInsensitive], locale: nil
        )
        for piece in folded.components(separatedBy: CharacterSet.alphanumerics.inverted) {
            guard piece.count >= 3, !piece.allSatisfy(\.isNumber) else { continue }
            out.insert(piece)
        }
        return out
    }

    private static func signature(of tokens: Set<String>) -> String {
        tokens.sorted().joined(separator: " ")
    }
}
