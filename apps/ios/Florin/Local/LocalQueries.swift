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
         * A month ago by the calendar, not by counting backwards in the array.
         *
         * This took the second-to-last point, which was right when the series
         * held one point per month and became "yesterday" the moment it held
         * one per day — so the hero printed 0,00 EUR of monthly change under a
         * ledger that had plainly moved. The index means nothing; the date is
         * the only thing that does.
         */
        let monthAgo = try Self.netMonthAgo(db, currentNet: gross - liability)

        return Overview(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            locale: short,
            strings: try strings(for: short),
            lastSyncedAt: nil,
            // Hardcoded false, which disabled every sync control on the
            // device ledger — including the refresh button on Comptes, which
            // simply did nothing when tapped.
            bankSyncConfigured: BankingFlow.isConfigured,
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
            savings: try savingsRates(db),
            allocation: allocation(accounts),
            goal: nil,
            reviewCount: try db.scalar(
                // Upcoming rows are not in the queue, so they are not in
                // its count either — a badge promising two decisions that
                // cannot be made is worse than no badge.
                """
                SELECT count(*) FROM transactions
                WHERE needs_review = 1 AND deleted_at IS NULL AND is_pending = 0
                  AND substr(occurred_at, 1, 10) <= date('now')
                """
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
                   opening_balance, is_included_in_net_worth, is_archived, display_icon,
                   sync_provider
            FROM accounts
            WHERE is_archived = 0
            ORDER BY display_order, name
            """
        ).map { row in
            let balance = row.double("current_balance") ?? 0
            let market = row.double("market_value") ?? 0
            let kind = row.string("kind") ?? "checking"
            /*
             * A broker is its holdings *plus* the cash sitting beside them.
             *
             * Taking the market value alone dropped the un-invested balance —
             * forty cents on the PEA, which is small until you are reconciling
             * against a server to the cent and cannot find it.
             */
            let total = kind == "broker_portfolio" ? balance + market : balance
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
                displayIcon: row.string("display_icon"),
                isSynced: row.string("sync_provider") == "enable_banking"
            )
        }
    }

    /*
     * The wealth change over the last COMPLETE calendar month.
     *
     * Comparing today against this date last month is arithmetically sound and,
     * on a real ledger, close to meaningless: a salary lands on a drifting date
     * — the 24th, the 26th, the 29th — so a fixed one-month window catches one
     * payday, two, or none. Measured day by day on this account the same figure
     * read +519 € on 25 July, −2 457 € on the 26th, +647 € on the 29th. Three
     * thousand euros of swing in four days, with nothing having happened. Today
     * it reads +4 073 € because the window happens to hold two salaries.
     *
     * A complete calendar month holds exactly one, whichever day it falls on.
     * The same ledger then reads +541, +672, +442, −20, +703, +482 — which is
     * what the month actually was.
     *
     * The same rule the savings rates already follow, for the same reason: the
     * month in progress has its spending but not yet its income.
     *
     * Adjustment rows stay out — a balance reconciliation moves an account
     * without being wealth earned or spent.
     *
     * Returns nil when the ledger does not reach back to that month, so the
     * hero says nothing rather than comparing against a month it never saw.
     */
    static func netMonthAgo(_ db: SQLiteDatabase, currentNet: Double) throws -> Double? {
        let month = Self.lastCompleteMonth()
        let oldest = try db.scalar(
            """
            SELECT min(substr(t.occurred_at, 1, 7))
            FROM transactions t
            JOIN accounts a ON a.id = t.account_id
            WHERE t.deleted_at IS NULL AND t.transfer_pair_id IS NULL
              AND a.is_archived = 0 AND a.is_included_in_net_worth = 1
              AND a.kind <> 'loan' AND t.status = 'cleared'
            """
        )?.string
        guard let oldest, oldest <= month else { return nil }

        let delta = try db.scalar(
            """
            SELECT coalesce(sum(t.amount), 0)
            FROM transactions t
            JOIN accounts a ON a.id = t.account_id
            LEFT JOIN categories c ON c.id = t.category_id
            LEFT JOIN category_groups g ON g.id = c.group_id
            WHERE t.deleted_at IS NULL AND t.transfer_pair_id IS NULL
              AND a.is_archived = 0 AND a.is_included_in_net_worth = 1
              AND a.kind <> 'loan' AND t.status = 'cleared'
              AND substr(t.occurred_at, 1, 7) = ?
              AND (g.kind IS NULL OR g.kind <> 'adjustment')
            """,
            [.text(month)]
        )?.double ?? 0

        return currentNet - delta
    }

    /// The month before this one, as `yyyy-MM`.
    static func lastCompleteMonth() -> String {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        return monthFormatter.string(from: date)
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
                groupName: row.string("group_name") ?? "",
                groupKind: row.string("group_kind")
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

        /*
         * A point a day, not a point a month.
         *
         * Twelve monthly points drew a smooth curve that hid every salary and
         * every rent — the shape of the year rather than the shape of the
         * money. The server returns four hundred daily points and the sawtooth
         * *is* the information: you can see the month being lived.
         *
         * Walked backwards from today's balances: what an account holds now is
         * the one figure that is certainly true, and the transactions say how
         * it got there. Summing forwards from zero would draw a ledger that
         * starts at nothing, which is not what happened.
         */
        let moves = try db.query(
            """
            SELECT substr(t.occurred_at, 1, 10) AS day, coalesce(sum(t.amount), 0) AS total
            FROM transactions t
            JOIN accounts a ON a.id = t.account_id
            LEFT JOIN categories c ON c.id = t.category_id
            LEFT JOIN category_groups g ON g.id = c.group_id
            WHERE t.deleted_at IS NULL AND t.status = 'cleared'
              -- The same exclusions the server applies, for the same reason.
              -- Without them the line grew a vertical spike on 29 June: a 2700
              -- transfer to LIVRET A whose other leg is not a transaction here,
              -- so the day read as 2700 of wealth vanishing and returning. The
              -- server's own comment calls it a phantom step.
              AND t.transfer_pair_id IS NULL
              AND a.is_archived = 0 AND a.is_included_in_net_worth = 1
              AND a.kind <> 'loan'
              -- Pending rows are authorisations, not money that has moved:
              -- the amount can still change and the bank has not booked them.
              -- They stay visible in the lists, marked, and out of every total.
              AND t.is_pending = 0 AND substr(t.occurred_at, 1, 10) <= date('now')
              AND (g.kind IS NULL OR g.kind <> 'adjustment')
            GROUP BY 1 ORDER BY 1
            """
        )
        var byDay: [String: Double] = [:]
        for row in moves {
            guard let day = row.string("day") else { continue }
            byDay[day] = row.double("total") ?? 0
        }

        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        guard let earliestText = moves.first?.string("day"),
              let earliest = dayFormatter.date(from: earliestText)
        else {
            return [PatrimonyPoint(date: dayFormatter.string(from: now),
                                   balance: round2(today), projected: false)]
        }

        // Two years at most: beyond that the line is a wall of pixels and the
        // chart has range buttons for the rest.
        let floor = calendar.date(byAdding: .day, value: -730, to: now) ?? earliest
        let start = max(earliest, floor)

        var points: [PatrimonyPoint] = []
        var running = today
        var cursor = calendar.startOfDay(for: now)
        let first = calendar.startOfDay(for: start)

        while cursor >= first {
            let label = dayFormatter.string(from: cursor)
            points.append(PatrimonyPoint(date: label, balance: round2(running), projected: false))
            // Undo this day to reach the one before it.
            running -= byDay[label] ?? 0
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return points.reversed()
    }

    // MARK: - This month

    /// Anything smaller than this is not somebody's salary.
    private static let salaryMinAmount = 500.0

    /*
     * The ceiling is the salary, and the salary is the *recurring* one.
     *
     * This ranking is not a detail. On the server it once picked the category
     * of the single most recent income over 500, which let a one-off 500 EUR
     * cheque booked to a side-income category outrank a 2998 EUR monthly wage
     * and collapse the whole month's margin. Distinct months with a hit is the
     * discriminator; the total is the tie-break for someone with one month of
     * history. Only income-kind categories qualify, or a large inbound
     * transfer booked as an adjustment becomes "salary" and fakes the month.
     */
    static func salaryCategory(_ db: SQLiteDatabase) throws -> (id: String, name: String)? {
        let since = Self.dayFormatter.string(
            from: Calendar(identifier: .gregorian)
                .date(byAdding: .day, value: -90, to: Date()) ?? Date()
        )
        let rows = try db.query(
            """
            SELECT t.category_id AS id, c.name AS name
            FROM transactions t
            JOIN accounts a ON a.id = t.account_id
            JOIN categories c ON c.id = t.category_id
            JOIN category_groups g ON g.id = c.group_id
            WHERE t.deleted_at IS NULL AND t.status = 'cleared'
              AND t.occurred_at >= ? AND t.amount >= ?
              AND t.transfer_pair_id IS NULL
              AND a.is_archived = 0 AND g.kind = 'income'
            GROUP BY t.category_id, c.name
            ORDER BY count(DISTINCT substr(t.occurred_at, 1, 7)) DESC,
                     coalesce(sum(t.amount), 0) DESC,
                     max(t.occurred_at) DESC
            LIMIT 1
            """,
            [.text(since), .real(salaryMinAmount)]
        )
        guard let row = rows.first, let id = row.string("id"), let name = row.string("name")
        else { return nil }
        return (id, name)
    }

    static func leftToSpend(_ db: SQLiteDatabase) throws -> LeftToSpend {
        let month = Self.monthFormatter.string(from: Date())
        let salary = try salaryCategory(db)

        var income = 0.0
        if let salary {
            /*
             * This month's salary, or the last month that saw one.
             *
             * Early in the month nothing has landed yet — wages arrive on the
             * 25th to 28th — and a ceiling of zero would tell someone they have
             * nothing to spend on the 3rd. Falling back to the most recent
             * month that did see a hit keeps the figure meaningful.
             */
            let rows = try db.query(
                """
                SELECT substr(t.occurred_at, 1, 7) AS month,
                       coalesce(sum(t.amount), 0) AS total
                FROM transactions t
                JOIN accounts a ON a.id = t.account_id
                WHERE t.deleted_at IS NULL AND t.status = 'cleared'
                  AND t.category_id = ? AND t.amount > 0
                  AND t.transfer_pair_id IS NULL AND a.is_archived = 0
                GROUP BY 1 ORDER BY 1 DESC
                """,
                [.text(salary.id)]
            )
            let current = rows.first { $0.string("month") == month }
            income = (current ?? rows.first)?.double("total") ?? 0
        }

        /*
         * Everything that came in, not only the paycheck.
         *
         * The ceiling was the salary category alone, so a month's other income
         * — a refund, a gift, side work, anything filed under a second income
         * category — did not exist for "left to spend" or the projected
         * margin. On this ledger that discarded 1 176 € across six months and
         * made every month read poorer than it was.
         *
         * The salary keeps its own treatment because of when it lands: early
         * in the month, with the payslip still a fortnight away, a ceiling of
         * zero would say there is nothing to spend, so it falls back to the
         * last month that saw one. The rest is simply this month's.
         */
        income += try db.scalar(
            """
            SELECT coalesce(sum(t.amount), 0)
            FROM transactions t
            JOIN accounts a ON a.id = t.account_id
            JOIN categories c ON c.id = t.category_id
            JOIN category_groups g ON g.id = c.group_id
            WHERE t.deleted_at IS NULL AND t.status = 'cleared' AND t.is_pending = 0
              AND substr(t.occurred_at, 1, 10) <= date('now')
              AND substr(t.occurred_at, 1, 7) = ?
              AND g.kind = 'income' AND t.amount > 0
              AND t.transfer_pair_id IS NULL AND a.is_archived = 0
              AND (? IS NULL OR t.category_id <> ?)
            """,
            [
                .text(month),
                salary.map { SQLiteValue.text($0.id) } ?? .null,
                salary.map { SQLiteValue.text($0.id) } ?? .null,
            ]
        )?.double ?? 0

        // Gross, so "spent so far" reads what actually went out and a single
        // reimbursement cannot zero it early in the month.
        let spent = try sum(db, month: month, kind: "expense")
        let fixed = try sum(db, month: month, kind: "expense", fixedOnly: true)

        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let days = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let elapsed = calendar.component(.day, from: now)
        let remaining = max(0, days - elapsed)
        let left = income - spent

        return LeftToSpend(
            salaryCategoryName: salary?.name,
            monthIncome: round2(income),
            monthSpent: round2(spent),
            monthSpentFixed: round2(fixed),
            expectedMonthlySpend: try burnAverage(db, months: 6),
            expectedMonthlyFixed: try burnAverage(db, months: 6, fixedOnly: true),
            leftToSpend: round2(left),
            dailyAvgSpent: elapsed > 0 ? round2(spent / Double(elapsed)) : 0,
            dailyBudgetRemaining: salary != nil && remaining > 0
                ? round2(left / Double(remaining))
                : nil,
            daysElapsed: elapsed,
            daysRemaining: remaining
        )
    }

    /*
     * Complete calendar months only.
     *
     * The month in progress skews the ratio hard in whichever direction payday
     * falls: its spending is already booked while a salary paid on the 25th is
     * not. On real data that read −3% over three months against +6% and +17%
     * over six and twelve, where the same broken month is diluted.
     */
    static func savingsRates(_ db: SQLiteDatabase) throws -> SavingsRates {
        func rate(months: Int) throws -> Double? {
            let calendar = Calendar(identifier: .gregorian)
            let now = Date()
            guard let firstDay = calendar.date(byAdding: .month, value: -months, to: now),
                  let start = calendar.date(
                      from: calendar.dateComponents([.year, .month], from: firstDay)
                  ),
                  let lastMonth = calendar.date(byAdding: .month, value: -1, to: now),
                  let end = endOfMonth(lastMonth, calendar: calendar)
            else { return nil }

            let rows = try db.query(
                """
                SELECT
                  coalesce(sum(CASE WHEN g.kind = 'income' THEN t.amount ELSE 0 END), 0) AS income,
                  coalesce(sum(CASE WHEN g.kind = 'expense' THEN t.amount ELSE 0 END), 0) AS net
                FROM transactions t
                JOIN accounts a ON a.id = t.account_id
                LEFT JOIN categories c ON c.id = t.category_id
                LEFT JOIN category_groups g ON g.id = c.group_id
                WHERE t.deleted_at IS NULL AND t.status = 'cleared' AND t.is_pending = 0 AND substr(t.occurred_at, 1, 10) <= date('now')
                  AND t.occurred_at >= ? AND t.occurred_at <= ?
                  AND t.transfer_pair_id IS NULL AND a.is_archived = 0
                """,
                [
                    .text(Self.dayFormatter.string(from: start)),
                    .text(Self.dayFormatter.string(from: end) + "T23:59:59Z"),
                ]
            )
            let income = rows.first?.double("income") ?? 0
            // Net the categorised expense groups rather than only the negatives:
            // a positive booked into an expense category — a friend repaying
            // their share — offsets that category's outflow. Counting only
            // negatives inflated expenses and crushed the rate.
            let net = rows.first?.double("net") ?? 0
            guard income > 0 else { return nil }
            return round2(((income + net) / income) * 100)
        }

        return SavingsRates(
            threeMonth: try rate(months: 3),
            sixMonth: try rate(months: 6),
            twelveMonth: try rate(months: 12)
        )
    }

    static func burn(
        _ db: SQLiteDatabase, monthsBack: Int, fixedOnly: Bool = false
    ) throws -> Double {
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(byAdding: .month, value: -monthsBack, to: Date())
        else { return 0 }
        return round2(try sum(
            db, month: Self.monthFormatter.string(from: date),
            kind: "expense", fixedOnly: fixedOnly
        ))
    }

    /// Complete months only — the month in progress has its spending booked but
    /// not its income, and averaging it in drags the figure down for no reason
    /// other than the date.
    /// Complete months only — the current one is the thing this average
    /// exists to stand in for.
    static func burnAverage(
        _ db: SQLiteDatabase, months: Int, fixedOnly: Bool = false
    ) throws -> Double {
        var total = 0.0
        for offset in 1...months {
            total += try burn(db, monthsBack: offset, fixedOnly: fixedOnly)
        }
        return round2(total / Double(months))
    }

    /*
     * What went out this month, the way the server counts it.
     *
     * This joined categories INNER and summed every amount, which quietly
     * changed the figure in two ways the comment above it claimed it did not.
     *
     * Uncategorised debits vanished entirely — an inner join drops them —
     * although they are money that left. And positive rows inside expense
     * categories netted off the total, so a refund erased the spending it was
     * refunding: on a real month the phone read 1 974 € where the server read
     * 2 400 €, and every figure built on it — the forecast, the projected
     * margin, what is left to spend — was 426 € too kind.
     *
     * Gross means outflows only. Refunds show up where they belong, in the
     * net figures, not by rewriting what a month cost.
     *
     * `fixedOnly` keeps the net convention the server uses for it, since only
     * a categorised row can be marked fixed and refunds against a bill really
     * do reduce that bill.
     */
    private static func sum(
        _ db: SQLiteDatabase,
        month: String,
        kind: String,
        fixedOnly: Bool = false
    ) throws -> Double {
        guard kind == "expense" else {
            let value = try db.scalar(
                """
                SELECT coalesce(sum(t.amount), 0)
                FROM transactions t
                JOIN accounts a ON a.id = t.account_id
                JOIN categories c ON c.id = t.category_id
                JOIN category_groups g ON g.id = c.group_id
                WHERE t.deleted_at IS NULL AND t.status = 'cleared' AND t.is_pending = 0
                  AND substr(t.occurred_at, 1, 10) <= date('now')
                  AND substr(t.occurred_at, 1, 7) = ? AND g.kind = ?
                  AND t.transfer_pair_id IS NULL AND a.is_archived = 0
                """,
                [.text(month), .text(kind)]
            )?.double ?? 0
            return value
        }

        let amount = fixedOnly ? Self.netBurnCase : Self.grossBurnCase
        let fixedClause = fixedOnly ? "AND c.is_fixed = 1" : ""
        let value = try db.scalar(
            """
            SELECT coalesce(sum(\(amount)), 0)
            FROM transactions t
            JOIN accounts a ON a.id = t.account_id
            LEFT JOIN categories c ON c.id = t.category_id
            LEFT JOIN category_groups g ON g.id = c.group_id
            WHERE t.deleted_at IS NULL AND t.status = 'cleared' AND t.is_pending = 0
              AND substr(t.occurred_at, 1, 10) <= date('now')
              AND substr(t.occurred_at, 1, 7) = ?
              AND t.transfer_pair_id IS NULL AND a.is_archived = 0 \(fixedClause)
            """,
            [.text(month)]
        )?.double ?? 0
        // A month that took in more than it spent has burnt nothing, not a
        // negative amount.
        return value >= 0 ? 0 : abs(value)
    }

    /*
     * Money that left, ignoring refunds. An uncategorised debit still counts —
     * it is money gone, whatever it was for — unless it looks like a transfer
     * between the user's own accounts, which is money moved, not spent.
     */
    private static let grossBurnCase = """
        CASE
          WHEN \(uncategorisedTransfer) THEN 0
          WHEN t.amount < 0 AND (g.kind IS NULL OR g.kind = 'expense') THEN t.amount
          ELSE 0
        END
        """

    /// The same, with refunds inside expense categories netted back off.
    private static let netBurnCase = """
        CASE
          WHEN \(uncategorisedTransfer) THEN 0
          WHEN t.amount < 0 AND (g.kind IS NULL OR g.kind = 'expense') THEN t.amount
          WHEN t.amount > 0 AND g.kind = 'expense' THEN t.amount
          ELSE 0
        END
        """

    /*
     * An outgoing transfer nobody has classified.
     *
     * Banks label a self-transfer differently per country and language, so the
     * server matches a list of prefixes; the same list, kept in step. Only
     * uncategorised rows are caught — filing one under a real category is the
     * user overriding the guess, and that has to win.
     */
    private static let uncategorisedTransfer = """
        ((upper(t.payee) LIKE 'VIREMENT %' OR upper(t.payee) LIKE 'VIR %'
          OR upper(t.payee) LIKE 'UBERWEISUNG %' OR upper(t.payee) LIKE 'UEBERWEISUNG %'
          OR upper(t.payee) LIKE 'TRANSFER %' OR upper(t.payee) LIKE 'TRANSFERENCIA %'
          OR upper(t.payee) LIKE 'BONIFICO %' OR upper(t.payee) LIKE 'SEPA %')
         AND t.category_id IS NULL)
        """

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

    /// The last point on or before `daysBack` days ago — the series can have
    /// gaps, and the nearest earlier day is the honest comparison.
    static func point(in series: [PatrimonyPoint], daysBack: Int) -> PatrimonyPoint? {
        let calendar = Calendar(identifier: .gregorian)
        guard let target = calendar.date(byAdding: .day, value: -daysBack, to: Date())
        else { return series.first }
        let label = dayFormatter.string(from: target)
        return series.last { $0.date <= label } ?? series.first
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
