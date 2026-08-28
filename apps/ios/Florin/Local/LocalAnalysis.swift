import Foundation

/// Analyse, computed on the device.
///
/// Six views of the same ledger: the monthly flows, where the money went by
/// category, how those categories moved month to month, the daily spend, the
/// subscriptions radar, and the savings rates.
enum LocalAnalysis {
    static func data(store: LocalStore) throws -> AnalysisData {
        let db = store.database
        let months = recentMonths(12)
        // One pass. The shares and the id lookup are two halves of the same
        // answer, and this is the heaviest query on the screen.
        let breakdown = try categoryShares(db, days: 30)

        return AnalysisData(
            flows: try flows(db, months: months),
            categories: breakdown.shares,
            categoryIds: breakdown.ids,
            categorySeries: try categorySeries(db, months: months),
            dailySpend: try dailySpend(db, days: 30),
            subscriptions: try subscriptions(db),
            savings: try LocalQueries.savingsRates(db),
            ageOfMoney: nil
        )
    }

    // MARK: - Flows

    static func flows(_ db: SQLiteDatabase, months: [String]) throws -> [MonthlyFlow] {
        let rows = try db.query(
            """
            SELECT substr(t.occurred_at, 1, 7) AS month,
                   coalesce(sum(CASE WHEN g.kind = 'income' THEN t.amount ELSE 0 END), 0) AS income,
                   coalesce(sum(CASE WHEN g.kind = 'expense' THEN t.amount ELSE 0 END), 0) AS expense
            FROM transactions t
            JOIN accounts a ON a.id = t.account_id
            LEFT JOIN categories c ON c.id = t.category_id
            LEFT JOIN category_groups g ON g.id = c.group_id
            WHERE t.deleted_at IS NULL AND t.status = 'cleared' AND t.is_pending = 0 AND substr(t.occurred_at, 1, 10) <= date('now')
              AND t.transfer_pair_id IS NULL AND a.is_archived = 0
              AND substr(t.occurred_at, 1, 7) >= ?
            GROUP BY 1
            """,
            [.text(months.first ?? "")]
        )
        var byMonth: [String: (income: Double, expense: Double)] = [:]
        for row in rows {
            guard let month = row.string("month") else { continue }
            byMonth[month] = (row.double("income") ?? 0, -(row.double("expense") ?? 0))
        }
        // Every month in the window, including the silent ones — a gap in the
        // chart is information, a missing bar is just a shorter chart.
        return months.map { month in
            let entry = byMonth[month] ?? (0, 0)
            return MonthlyFlow(
                month: month,
                income: round2(entry.income),
                expense: round2(entry.expense),
                net: round2(entry.income - entry.expense)
            )
        }
    }

    // MARK: - Where it went

    /*
     * The window the screen names, not a different one.
     *
     * This asked for six calendar months while the tile above it said
     * "Dépensé sur 30 jours", so the headline read 18 101 € for a month in
     * which 2 184 € had been spent, and every category bar was a half-year
     * total wearing a 30-day label. The server's own endpoint asks for 30
     * days; local mode has to ask for the same thing or the two renderings
     * are not the same app.
     *
     * Rows are excluded one by one on `amount < 0`, as the server does, rather
     * than by the sign of a category's sum: a refund inside a category should
     * not be able to hide the spending it sits next to.
     */
    static func categoryShares(
        _ db: SQLiteDatabase,
        days: Int
    ) throws -> (shares: [CategoryShare], ids: [String: String]) {
        let rows = try db.query(
            """
            SELECT c.id AS id, c.name AS name, c.emoji AS emoji, g.name AS group_name,
                   coalesce(sum(t.amount), 0) AS total
            FROM transactions t
            JOIN accounts a ON a.id = t.account_id
            JOIN categories c ON c.id = t.category_id
            JOIN category_groups g ON g.id = c.group_id
            WHERE t.deleted_at IS NULL AND t.status = 'cleared' AND t.is_pending = 0 AND substr(t.occurred_at, 1, 10) <= date('now')
              AND t.transfer_pair_id IS NULL AND a.is_archived = 0
              AND g.kind = 'expense' AND t.amount < 0
              AND substr(t.occurred_at, 1, 10) >= date('now', ?)
            GROUP BY c.id, c.name, c.emoji, g.name
            ORDER BY sum(t.amount) ASC
            """,
            [.text("-\(days) days")]
        )
        var ids: [String: String] = [:]
        let shares = rows.map { row -> CategoryShare in
            let name = row.string("name") ?? ""
            ids[name] = row.string("id") ?? ""
            return CategoryShare(
                groupName: row.string("group_name") ?? "",
                categoryName: name,
                emoji: row.string("emoji"),
                total: round2(-(row.double("total") ?? 0))
            )
        }
        return (shares, ids)
    }

    // MARK: - Month to month

    static func categorySeries(_ db: SQLiteDatabase, months: [String]) throws -> CategorySeries {
        let rows = try db.query(
            """
            SELECT c.id AS id, c.name AS name, c.emoji AS emoji,
                   substr(t.occurred_at, 1, 7) AS month,
                   coalesce(sum(t.amount), 0) AS total
            FROM transactions t
            JOIN accounts a ON a.id = t.account_id
            JOIN categories c ON c.id = t.category_id
            JOIN category_groups g ON g.id = c.group_id
            WHERE t.deleted_at IS NULL AND t.status = 'cleared' AND t.is_pending = 0 AND substr(t.occurred_at, 1, 10) <= date('now')
              AND t.transfer_pair_id IS NULL AND a.is_archived = 0
              AND g.kind = 'expense' AND substr(t.occurred_at, 1, 7) >= ?
            GROUP BY c.id, month
            """,
            [.text(months.first ?? "")]
        )

        var byCategory: [String: (name: String, emoji: String?, monthly: [String: Double])] = [:]
        for row in rows {
            guard let id = row.string("id"), let month = row.string("month") else { continue }
            var entry = byCategory[id] ?? (row.string("name") ?? "", row.string("emoji"), [:])
            entry.monthly[month] = -(row.double("total") ?? 0)
            byCategory[id] = entry
        }

        let series = byCategory.map { id, entry -> CategorySeries.Row in
            let monthly = months.map { round2(entry.monthly[$0] ?? 0) }
            return CategorySeries.Row(
                categoryId: id,
                categoryName: entry.name,
                emoji: entry.emoji,
                monthly: monthly,
                total: round2(monthly.reduce(0, +))
            )
        }
        .sorted { $0.total > $1.total }

        return CategorySeries(months: months, categories: series)
    }

    // MARK: - Day by day

    static func dailySpend(_ db: SQLiteDatabase, days: Int) throws -> [DailySpend] {
        let calendar = Calendar(identifier: .gregorian)
        guard let start = calendar.date(byAdding: .day, value: -days, to: Date()) else { return [] }
        let rows = try db.query(
            """
            SELECT substr(t.occurred_at, 1, 10) AS day, coalesce(sum(t.amount), 0) AS total
            FROM transactions t
            JOIN accounts a ON a.id = t.account_id
            JOIN categories c ON c.id = t.category_id
            JOIN category_groups g ON g.id = c.group_id
            WHERE t.deleted_at IS NULL AND t.status = 'cleared' AND t.is_pending = 0 AND substr(t.occurred_at, 1, 10) <= date('now')
              AND t.transfer_pair_id IS NULL AND a.is_archived = 0
              AND g.kind = 'expense' AND t.occurred_at >= ?
            GROUP BY 1 ORDER BY 1
            """,
            [.text(LocalQueries.dayFormatter.string(from: start))]
        )
        return rows.compactMap { row in
            guard let day = row.string("day") else { return nil }
            return DailySpend(date: day, amount: round2(-(row.double("total") ?? 0)))
        }
    }

    // MARK: - Subscriptions radar

    /*
     * Payees that repeat at roughly the same amount on a roughly regular beat.
     *
     * Monthly is 28±7 days and weekly 7±2, and a group needs three samples
     * before it counts — two payments to the same shop is a coincidence, not a
     * subscription. Amounts are matched within 5%, because a subscription that
     * changed price is still that subscription.
     */
    static func subscriptions(_ db: SQLiteDatabase) throws -> [SubscriptionMatch] {
        let calendar = Calendar(identifier: .gregorian)
        guard let start = calendar.date(byAdding: .day, value: -180, to: Date()) else { return [] }

        let rows = try db.query(
            """
            SELECT t.normalized_payee AS key, t.payee AS payee, t.amount AS amount,
                   substr(t.occurred_at, 1, 10) AS day, c.name AS category
            FROM transactions t
            JOIN accounts a ON a.id = t.account_id
            LEFT JOIN categories c ON c.id = t.category_id
            WHERE t.deleted_at IS NULL AND t.status = 'cleared' AND t.is_pending = 0 AND substr(t.occurred_at, 1, 10) <= date('now')
              AND t.amount < 0 AND t.transfer_pair_id IS NULL
              AND a.is_archived = 0 AND t.occurred_at >= ?
            ORDER BY t.occurred_at
            """,
            [.text(LocalQueries.dayFormatter.string(from: start))]
        )

        struct Sample { let amount: Double; let day: Date; let payee: String; let category: String? }
        var byPayee: [String: [Sample]] = [:]
        for row in rows {
            guard let key = row.string("key"), !key.isEmpty,
                  let dayText = row.string("day"),
                  let day = LocalQueries.dayFormatter.date(from: dayText)
            else { continue }
            byPayee[key, default: []].append(
                Sample(
                    amount: abs(row.double("amount") ?? 0),
                    day: day,
                    payee: row.string("payee") ?? key,
                    category: row.string("category")
                )
            )
        }

        var matches: [SubscriptionMatch] = []
        for (_, samples) in byPayee where samples.count >= 3 {
            let median = samples.map(\.amount).sorted()[samples.count / 2]
            let alike = samples.filter { abs($0.amount - median) <= median * 0.05 }
            guard alike.count >= 3 else { continue }

            let days = alike.map(\.day).sorted()
            let gaps = zip(days, days.dropFirst()).map {
                Calendar(identifier: .gregorian)
                    .dateComponents([.day], from: $0, to: $1).day ?? 0
            }
            guard !gaps.isEmpty else { continue }
            let cadence = gaps.reduce(0, +) / gaps.count

            let isMonthly = abs(cadence - 28) <= 7
            let isWeekly = abs(cadence - 7) <= 2
            guard isMonthly || isWeekly else { continue }

            matches.append(
                SubscriptionMatch(
                    payee: alike.last?.payee ?? "",
                    amount: round2(median),
                    cadenceDays: cadence,
                    samples: alike.count,
                    lastSeen: LocalQueries.dayFormatter.string(from: days.last ?? Date()),
                    annualCost: round2(median * (isWeekly ? 52 : 12)),
                    categoryName: alike.last?.category
                )
            )
        }
        return matches.sorted { $0.annualCost > $1.annualCost }
    }

    // MARK: - Bits

    static func recentMonths(_ count: Int) -> [String] {
        (0..<count).reversed().compactMap { monthKey(monthsBack: $0) }
    }

    static func monthKey(monthsBack: Int) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(byAdding: .month, value: -monthsBack, to: Date()) ?? Date()
        return LocalQueries.monthFormatter.string(from: date)
    }

    private static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}
