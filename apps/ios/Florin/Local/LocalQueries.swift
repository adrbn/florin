import Foundation

/// The dashboard, computed on the device.
///
/// This is the first screen's worth of arithmetic moved off the server. It
/// returns the exact `Overview` the API returns, so every view, every model
/// and every formatter above it is untouched — the app cannot tell which
/// source it is reading, which is the only way a port like this stays honest
/// about looking identical.
///
/// What is *not* here yet is stated rather than faked: the savings rates, the
/// spending forecast and the goal are the densest parts of `dashboard.ts` and
/// they are ported next. Until then they come back empty, which is also the
/// truthful answer for a ledger that has one account and no history.
enum LocalQueries {
    static func overview(store: LocalStore, locale: String) throws -> Overview {
        let db = store.database
        let short = shortLocale(locale)

        let accounts = try readAccounts(db)
        let categories = try readCategories(db)
        let recent = try readTransactions(db, limit: 12)

        let gross = accounts
            .filter { $0.isIncludedInNetWorth && !$0.isLoan }
            .reduce(0) { $0 + $1.total }
        let liability = accounts
            .filter { $0.isIncludedInNetWorth && $0.isLoan }
            .reduce(0) { $0 + abs($1.debt ?? $1.total) }

        let series = try netWorthSeries(db, accounts: accounts)
        /*
         * The point *before* the last one, not the first one.
         *
         * `netWorthSeries` returns oldest-first, so `series.first` is twelve
         * months back — which made the hero print a year of change under the
         * words "sur un mois". Caught by arithmetic, not by reading: with one
         * salary in each of two months the screen said +4429 where the month
         * actually moved +2339, and 4429 is exactly the twelve-month total.
         */
        let monthAgo = series.count > 1 ? series[series.count - 2].balance : nil

        return Overview(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            locale: short,
            strings: try strings(for: short),
            lastSyncedAt: nil,
            bankSyncConfigured: false,
            currency: "EUR",
            netWorth: NetWorth(
                gross: round2(gross),
                liability: round2(liability),
                net: round2(gross - liability),
                netMonthAgo: monthAgo.map(round2)
            ),
            monthlyTrend: round2((gross - liability) - (monthAgo ?? (gross - liability))),
            series: series,
            grossSeries: nil,
            netSeries: nil,
            leftToSpend: try leftToSpend(db),
            burnThisMonth: try burn(db, monthsBack: 0),
            burnAvg6: try burnAverage(db, months: 6),
            savings: SavingsRates(threeMonth: nil, sixMonth: nil, twelveMonth: nil),
            allocation: allocation(accounts),
            goal: nil,
            reviewCount: try db.scalar(
                "SELECT count(*) FROM transactions WHERE needs_review = 1 AND deleted_at IS NULL"
            )?.int ?? 0,
            incomeIsEstimated: false,
            accounts: accounts,
            categories: categories,
            recent: recent
        )
    }

    // MARK: - Accounts

    static func readAccounts(_ db: SQLiteDatabase) throws -> [Account] {
        try db.query(
            """
            SELECT id, name, kind, institution, current_balance, market_value,
                   opening_balance, is_included_in_net_worth, is_archived, display_icon
            FROM accounts
            WHERE is_archived = 0
            ORDER BY display_order, name
            """
        ).map { row in
            let balance = row.double("current_balance") ?? 0
            let market = row.double("market_value") ?? 0
            let kind = row.string("kind") ?? "checking"
            // A broker's worth is its market value when it has one; a plain
            // account's is its balance. Adding them would double-count.
            let total = kind == "broker_portfolio" && market != 0 ? market : balance
            return Account(
                id: row.string("id") ?? UUID().uuidString,
                name: row.string("name") ?? "",
                kind: kind,
                institution: row.string("institution"),
                balance: round2(balance),
                marketValue: round2(market),
                total: round2(total),
                netContribution: round2(row.double("opening_balance") ?? 0),
                debt: kind == "loan" ? round2(abs(balance)) : nil,
                isIncludedInNetWorth: row.bool("is_included_in_net_worth"),
                isArchived: row.bool("is_archived"),
                displayIcon: row.string("display_icon")
            )
        }
    }

    static func readCategories(_ db: SQLiteDatabase) throws -> [Category] {
        try db.query(
            """
            SELECT c.id, c.name, c.emoji, g.kind AS group_kind, g.name AS group_name
            FROM categories c
            JOIN category_groups g ON g.id = c.group_id
            WHERE c.is_archived = 0
            ORDER BY g.display_order, c.display_order, c.name
            """
        ).map { row in
            Category(
                id: row.string("id") ?? "",
                name: row.string("name") ?? "",
                emoji: row.string("emoji"),
                groupName: row.string("group_name") ?? ""
            )
        }
    }

    // MARK: - Transactions

    static func readTransactions(
        _ db: SQLiteDatabase,
        limit: Int,
        offset: Int = 0
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
            WHERE t.deleted_at IS NULL
            ORDER BY t.occurred_at DESC, t.id DESC
            LIMIT ? OFFSET ?
            """,
            [.integer(Int64(limit)), .integer(Int64(offset))]
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

    // MARK: - Money over time

    /// Net worth at the end of each of the last twelve months.
    ///
    /// Walked backwards from today's balances rather than forwards from zero:
    /// the opening balance a manual user typed is the truth about now, and
    /// history is what the transactions since then say about how we got here.
    /// Summing transactions forwards would show a ledger that starts at nothing
    /// and climbs, which is not what happened.
    static func netWorthSeries(
        _ db: SQLiteDatabase,
        accounts: [Account]
    ) throws -> [PatrimonyPoint] {
        let today = accounts
            .filter(\.isIncludedInNetWorth)
            .reduce(0) { $0 + ($1.isLoan ? -abs($1.debt ?? $1.total) : $1.total) }

        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        var points: [PatrimonyPoint] = []
        var running = today

        for monthsBack in 0..<12 {
            guard let end = calendar.date(byAdding: .month, value: -monthsBack, to: now),
                  let monthEnd = endOfMonth(end, calendar: calendar)
            else { continue }
            let label = Self.dayFormatter.string(from: min(monthEnd, now))
            points.append(PatrimonyPoint(date: label, balance: round2(running), projected: false))

            // Undo that month to reach the month before it.
            let moved = try db.scalar(
                """
                SELECT coalesce(sum(amount), 0) FROM transactions
                WHERE deleted_at IS NULL AND status = 'cleared'
                  AND substr(occurred_at, 1, 7) = ?
                """,
                [.text(String(label.prefix(7)))]
            )?.double ?? 0
            running -= moved
        }
        return points.reversed()
    }

    // MARK: - This month

    static func leftToSpend(_ db: SQLiteDatabase) throws -> LeftToSpend {
        let month = Self.monthFormatter.string(from: Date())
        let income = try sum(db, month: month, kind: "income")
        let spent = try sum(db, month: month, kind: "expense")
        let fixed = try sum(db, month: month, kind: "expense", fixedOnly: true)

        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let days = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let elapsed = calendar.component(.day, from: now)
        let remaining = max(0, days - elapsed)
        let left = income - spent

        return LeftToSpend(
            salaryCategoryName: nil,
            monthIncome: round2(income),
            monthSpent: round2(spent),
            monthSpentFixed: round2(fixed),
            expectedMonthlySpend: round2(spent),
            leftToSpend: round2(left),
            dailyAvgSpent: elapsed > 0 ? round2(spent / Double(elapsed)) : 0,
            dailyBudgetRemaining: remaining > 0 ? round2(left / Double(remaining)) : nil,
            daysElapsed: elapsed,
            daysRemaining: remaining
        )
    }

    static func burn(_ db: SQLiteDatabase, monthsBack: Int) throws -> Double {
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(byAdding: .month, value: -monthsBack, to: Date())
        else { return 0 }
        return round2(try sum(db, month: Self.monthFormatter.string(from: date), kind: "expense"))
    }

    /// Complete months only — the month in progress has its spending booked but
    /// not its income, and averaging it in drags the figure down for no reason
    /// other than the date.
    static func burnAverage(_ db: SQLiteDatabase, months: Int) throws -> Double {
        var total = 0.0
        for offset in 1...months { total += try burn(db, monthsBack: offset) }
        return round2(total / Double(months))
    }

    private static func sum(
        _ db: SQLiteDatabase,
        month: String,
        kind: String,
        fixedOnly: Bool = false
    ) throws -> Double {
        let fixedClause = fixedOnly ? "AND c.is_fixed = 1" : ""
        let value = try db.scalar(
            """
            SELECT coalesce(sum(t.amount), 0)
            FROM transactions t
            JOIN categories c ON c.id = t.category_id
            JOIN category_groups g ON g.id = c.group_id
            WHERE t.deleted_at IS NULL AND t.status = 'cleared'
              AND substr(t.occurred_at, 1, 7) = ?
              AND g.kind = ? \(fixedClause)
            """,
            [.text(month), .text(kind)]
        )?.double ?? 0
        // Expenses are stored negative; spending is the positive of that, the
        // same convention the plan uses.
        return kind == "expense" ? -value : value
    }

    static func allocation(_ accounts: [Account]) -> Allocation {
        var cash = 0.0
        var invested = 0.0
        var loans = 0.0
        for account in accounts where account.isIncludedInNetWorth {
            switch account.kind {
            case "loan": loans += abs(account.debt ?? account.total)
            case "broker_portfolio": invested += account.total
            default: cash += account.total
            }
        }
        return Allocation(cash: round2(cash), invested: round2(invested), loans: round2(loans))
    }

    // MARK: - Bits

    static func strings(for locale: String) throws -> [String: String] {
        guard let url = Bundle.main.url(forResource: "Strings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let all = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        else { return [:] }
        return all[locale] ?? all["en"] ?? [:]
    }

    static func shortLocale(_ locale: String) -> String {
        let lower = locale.lowercased()
        for candidate in ["fr", "nl"] where lower.hasPrefix(candidate) { return candidate }
        return "en"
    }

    private static func endOfMonth(_ date: Date, calendar: Calendar) -> Date? {
        guard let start = calendar.date(
            from: calendar.dateComponents([.year, .month], from: date)
        ) else { return nil }
        return calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)
    }

    private static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    nonisolated(unsafe) static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    nonisolated(unsafe) static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
