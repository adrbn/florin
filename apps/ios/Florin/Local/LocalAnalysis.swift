import Foundation

/// Analyse, computed on the device.
///
/// Six views of the same ledger: the monthly flows, where the money went by
/// category, how those categories moved month to month, the daily spend, the
/// subscriptions radar, and the savings rates.
enum LocalAnalysis {
    /// The calendar draws five whole weeks, so the day-by-day window has to
    /// cover five whole weeks. It asked for thirty days while the grid drew
    /// thirty-five, and the five squares that fell off the end were not drawn
    /// as unknown — they were drawn as days on which nothing had been spent.
    static let calendarWindow = 35

    /// Twelve finished months, and the one the ledger is inside.
    ///
    /// The headline over this tab and the net line inside it only mean
    /// anything over months that are over, and the running month is drawn
    /// beside them as what has happened so far. Asking for twelve would have
    /// left eleven to count, and a headline that says eleven months every
    /// month of the year explains nothing.
    static let flowMonths = 13

    static func data(store: LocalStore) throws -> AnalysisData {
        let db = store.database
        let months = recentMonths(12)
        // One pass. The shares and the id lookup are two halves of the same
        // answer, and this is the heaviest query on the screen.
        let breakdown = try categoryShares(db, days: 30)
        // And one pass for the calendar: its squares are the sum of its slices
        // by construction, so a filtered total and an unfiltered one cannot
        // come to disagree about what a day was worth.
        let slices = try dailySlices(db, days: calendarWindow)

        return AnalysisData(
            flows: try flows(db, months: recentMonths(flowMonths)),
            categories: breakdown.shares,
            categoryIds: breakdown.ids,
            categorySeries: try categorySeries(db, months: months),
            dailySpend: dailyTotals(slices),
            subscriptions: try subscriptions(db),
            savings: try LocalQueries.savingsRates(db),
            ageOfMoney: nil,
            dailySlices: slices,
            spendCategories: try spendCategories(db)
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
        let shares = rows.map { row -> CategoryShare in
            CategoryShare(
                groupName: row.string("group_name") ?? "",
                categoryName: row.string("name") ?? "",
                emoji: row.string("emoji"),
                total: round2(-(row.double("total") ?? 0))
            )
        }
        return (shares, try categoryIds(db))
    }

    /*
     * Every category, keyed the way the screen asks for it.
     *
     * A share identifies itself as "Groupe/Nom" — the pair, because two groups
     * may hold a category of the same name. This map was built from the
     * breakdown rows and keyed on the bare name, so every lookup missed, the
     * guard returned, and tapping a category on Analyse did nothing at all.
     *
     * Built from the category list rather than from the rows, as the server
     * does: a category with nothing spent in the last thirty days still
     * appears in the trends below, and tapping it has to work there too.
     */
    static func categoryIds(_ db: SQLiteDatabase) throws -> [String: String] {
        var ids: [String: String] = [:]
        for row in try db.query(
            """
            SELECT c.id AS id, c.name AS name, g.name AS group_name
            FROM categories c
            JOIN category_groups g ON g.id = c.group_id
            WHERE c.is_archived = 0
            """
        ) {
            guard let id = row.string("id"),
                  let name = row.string("name"),
                  let group = row.string("group_name")
            else { continue }
            ids["\(group)/\(name)"] = id
        }
        return ids
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

    /*
     * A day, split by category.
     *
     * The same predicate as `categoryShares` — cleared, booked, not a transfer,
     * on a live account, in an expense category — because the calendar and the
     * category bars are two renderings of one definition of "spent". Rows are
     * kept at their signed value rather than filtered on `amount < 0`: a refund
     * belongs to the day it lands on, and a square that ignored it would say
     * the money left twice.
     */
    static func dailySlices(_ db: SQLiteDatabase, days: Int) throws -> [DailySlice] {
        let calendar = Calendar(identifier: .gregorian)
        guard let start = calendar.date(byAdding: .day, value: -days, to: Date()) else { return [] }
        let rows = try db.query(
            """
            SELECT substr(t.occurred_at, 1, 10) AS day, c.id AS category_id,
                   coalesce(sum(t.amount), 0) AS total
            FROM transactions t
            JOIN accounts a ON a.id = t.account_id
            JOIN categories c ON c.id = t.category_id
            JOIN category_groups g ON g.id = c.group_id
            WHERE t.deleted_at IS NULL AND t.status = 'cleared' AND t.is_pending = 0 AND substr(t.occurred_at, 1, 10) <= date('now')
              AND t.transfer_pair_id IS NULL AND a.is_archived = 0
              AND g.kind = 'expense' AND t.occurred_at >= ?
            GROUP BY 1, 2 ORDER BY 1
            """,
            [.text(LocalQueries.dayFormatter.string(from: start))]
        )
        return rows.compactMap { row in
            guard let day = row.string("day"), let category = row.string("category_id")
            else { return nil }
            return DailySlice(
                date: day, categoryId: category, amount: round2(-(row.double("total") ?? 0))
            )
        }
    }

    /// The squares, summed from their own slices.
    static func dailyTotals(_ slices: [DailySlice]) -> [DailySpend] {
        var byDay: [String: Double] = [:]
        for slice in slices { byDay[slice.date, default: 0] += slice.amount }
        return byDay
            .map { DailySpend(date: $0.key, amount: round2($0.value)) }
            .sorted { $0.date < $1.date }
    }

    /// The categories the calendar can be cut by: every live expense category,
    /// in the order Catégories shows them, whether or not it saw any spending
    /// in the window — a filter whose list changes shape week to week is not a
    /// filter anyone can learn.
    static func spendCategories(_ db: SQLiteDatabase) throws -> [SpendCategory] {
        try db.query(
            """
            SELECT c.id AS id, c.name AS name, c.emoji AS emoji,
                   g.name AS group_name, c.is_fixed AS is_fixed
            FROM categories c
            JOIN category_groups g ON g.id = c.group_id
            WHERE c.is_archived = 0 AND g.kind = 'expense'
            ORDER BY g.display_order, g.name, c.display_order, c.name
            """
        ).compactMap { row in
            guard let id = row.string("id"), let name = row.string("name") else { return nil }
            return SpendCategory(
                id: id,
                name: name,
                emoji: row.string("emoji"),
                groupName: row.string("group_name") ?? "",
                isFixed: (row.int("is_fixed") ?? 0) == 1
            )
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
