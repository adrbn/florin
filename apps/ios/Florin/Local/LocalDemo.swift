import Foundation

/// A fictional ledger, for looking around before committing anything.
///
/// Florin has no accounts to sign into, so there is no demo login to hand
/// anyone — and a fresh install is empty until a bank is connected or a
/// balance typed in. Whoever wants to see what the app does with fourteen
/// months of history (App Review among them) had nothing to look at without
/// first handing over their own money. This fills the device's ledger with
/// invented accounts and transactions, and takes them away again on request.
///
/// The figures are the ones the App Store screenshots were made from
/// (`AppStore/seed-demo-ledger.py`), generated from a fixed seed so every run
/// shows the same month. Nothing here is anyone's real money.
enum LocalDemo {
    /// Set in `settings` while the ledger on screen is this one.
    static let marker = "demo_ledger"

    static var isActive: Bool { isActive(in: LocalStore.shared) }

    static func isActive(in store: LocalStore?) -> Bool {
        guard let store,
              let value = try? store.database.scalar(
                  "SELECT count(*) FROM settings WHERE key = ?", [.text(marker)]
              ) else { return false }
        return (value.int ?? 0) > 0
    }

    // MARK: - Filling

    static func seed(into store: LocalStore? = LocalStore.shared) throws {
        guard let store else { throw LocalOnboarding.Failure.noStore }
        let db = store.database
        let categories = try roles(db)
        var random = SeededRandom(seed: 11)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = calendar.startOfDay(for: Date())
        let dayToday = calendar.component(.day, from: today)

        func iso(_ date: Date) -> String {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02dT00:00:00Z", parts.year!, parts.month!, parts.day!)
        }

        let checking = UUID().uuidString
        let savings = UUID().uuidString
        let broker = UUID().uuidString
        let loan = UUID().uuidString

        struct Row {
            let account: String; let day: Date; let amount: Double; let payee: String
            let role: Role?; let review: Bool; var pair: String? = nil
        }
        var rows: [Row] = []

        let groceries = ["MONOPRIX", "CARREFOUR MARKET", "LA BOULANGERIE", "PRIMEURS DU MARCHÉ", "BIOCOOP"]
        let outings = ["LE PETIT COMPTOIR", "CAFÉ DES ARTS", "CINÉMA LE VOX", "PIZZERIA NAPOLI"]
        let transport = ["SNCF CONNECT", "NAVIGO", "TOTALENERGIES", "VÉLIB"]

        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
        /// The oldest instalment written — the loan starts there, so the
        /// schedule and the payments on file agree.
        var firstInstalment = thisMonth
        for back in 0..<14 {
            let month = calendar.date(byAdding: .month, value: -back, to: thisMonth)!
            let lastDay = calendar.range(of: .day, in: .month, for: month)!.count
            // The current month stops at today: nothing is booked in the future.
            let latest = back == 0 ? dayToday : lastDay
            func on(_ day: Int) -> Date? {
                let clamped = min(day, lastDay)
                guard clamped <= latest else { return nil }
                return calendar.date(byAdding: .day, value: clamped - 1, to: month)
            }
            func add(_ day: Int, _ amount: Double, _ payee: String, _ role: Role) {
                guard let date = on(day) else { return }
                rows.append(Row(account: checking, day: date, amount: amount, payee: payee, role: role, review: false))
            }

            add(27, 2740 + Double(13 - back) * 12, "VIREMENT SALAIRE", .wages)
            add(3, -880, "LOYER RÉSIDENCE", .rent)
            add(5, -34.90, "ABONNEMENT MOBILE", .subscriptions)
            add(5, -12.99, "STREAMING", .subscriptions)
            add(8, -41.20, "ASSURANCE HABITATION", .insurance)
            add(15, -300, "VIREMENT ÉPARGNE", .savings)
            /*
             * The instalment is a transfer to the loan, not a spending row:
             * the remaining capital counts paired rows on the loan account,
             * and a plain debit left the demo loan owing all 12 000 €.
             */
            if let date = on(lastDay) {
                let pair = UUID().uuidString
                rows.append(Row(account: checking, day: date, amount: -141.20,
                                payee: "PRÉLÈVEMENT PRÊT ÉTUDIANT", role: nil, review: false, pair: pair))
                rows.append(Row(account: loan, day: date, amount: 141.20,
                                payee: "PRÉLÈVEMENT PRÊT ÉTUDIANT", role: nil, review: false, pair: pair))
                firstInstalment = date
            }

            for _ in 0..<random.int(7...10) {
                add(random.int(1...latest), -random.amount(9...68), random.pick(groceries), .groceries)
            }
            for _ in 0..<random.int(3...6) {
                add(random.int(1...latest), -random.amount(11...46), random.pick(outings), .diningOut)
            }
            for _ in 0..<random.int(2...4) {
                add(random.int(1...latest), -random.amount(4...58), random.pick(transport), .transport)
            }
        }
        // Two waiting to be looked at, so the review queue has something in it.
        for (daysAgo, amount, payee) in [(1, -23.40, "FNAC"), (2, -64.00, "DÉCATHLON")] {
            rows.append(Row(
                account: checking,
                day: calendar.date(byAdding: .day, value: -daysAgo, to: today)!,
                amount: amount, payee: payee, role: nil, review: true
            ))
        }

        let loanStart = firstInstalment

        try db.transaction {
            let accounts: [(String, String, String, String, Double, Int)] = [
                (checking, "Compte courant", "checking", "Banque", 2418.63, 0),
                (savings, "Livret A", "savings", "Banque", 7650.00, 1),
                (broker, "PEA", "broker_portfolio", "Courtier", 25.95, 2),
                (loan, "Prêt étudiant", "loan", "Banque", -6420.18, 3),
            ]
            for (id, name, kind, institution, balance, order) in accounts {
                try db.run(
                    """
                    INSERT INTO accounts (id, name, kind, institution, currency,
                        current_balance, opening_balance, display_order)
                    VALUES (?, ?, ?, ?, 'EUR', ?, ?, ?)
                    """,
                    [.text(id), .text(name), .text(kind), .text(institution),
                     .real(balance), .real(balance), .integer(Int64(order))]
                )
            }
            try db.run(
                """
                UPDATE accounts SET loan_original_principal = 12000, loan_interest_rate = 0.031,
                    loan_start_date = ?, loan_term_months = 96, loan_monthly_payment = 141.20
                WHERE id = ?
                """,
                [.text(String(iso(loanStart).prefix(10))), .text(loan)]
            )

            for row in rows {
                try db.run(
                    """
                    INSERT INTO transactions (id, account_id, occurred_at, amount, payee,
                        normalized_payee, category_id, source, status, needs_review,
                        transfer_pair_id)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 'manual', 'cleared', ?, ?)
                    """,
                    [.text(UUID().uuidString), .text(row.account), .text(iso(row.day)),
                     .real(row.amount), .text(row.payee), .text(row.payee.lowercased()),
                     row.role.flatMap { categories[$0] }.map { .text($0) } ?? .null,
                     .integer(row.review ? 1 : 0),
                     row.pair.map { .text($0) } ?? .null]
                )
            }

            // The balance stated above is the truth; the opening absorbs the
            // history — the same invariant every other write keeps.
            try db.run(
                """
                UPDATE accounts SET opening_balance = round(current_balance - coalesce((
                    SELECT sum(amount) FROM transactions
                    WHERE account_id = accounts.id AND deleted_at IS NULL), 0), 2)
                WHERE id IN (?, ?)
                """,
                [.text(checking), .text(savings)]
            )

            let parts = calendar.dateComponents([.year, .month], from: today)
            let plan: [(Role, Double)] = [
                (.rent, 880), (.subscriptions, 50), (.insurance, 45), (.groceries, 400),
                (.transport, 90), (.diningOut, 180), (.savings, 450), (.clothes, 60),
                (.travel, 150), (.gifts, 40),
            ]
            for (role, assigned) in plan {
                guard let category = categories[role] else { continue }
                try db.run(
                    "INSERT OR REPLACE INTO monthly_budgets (id, year, month, category_id, assigned) VALUES (?, ?, ?, ?, ?)",
                    [.text(UUID().uuidString), .integer(Int64(parts.year!)), .integer(Int64(parts.month!)), .text(category), .real(assigned)]
                )
            }

            for (label, symbol, quantity, cost, price) in [
                ("MSCI World", "CW8", 32.0, 8588.80, 312.55),
                ("S&P 500", "ESE", 9.0, 1063.80, 134.80),
            ] {
                try db.run(
                    """
                    INSERT INTO holdings (id, account_id, label, quote_symbol, quantity,
                        cost_basis, last_price, currency)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 'EUR')
                    """,
                    [.text(UUID().uuidString), .text(broker), .text(label), .text(symbol),
                     .real(quantity), .real(cost), .real(price)]
                )
            }
            try LocalHoldings.revalue(store, accountId: broker)

            try db.run(
                "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                [.text(marker), .text(ISO8601DateFormatter().string(from: Date()))]
            )
            try db.run(
                "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                [.text(LocalOnboarding.marker), .text(ISO8601DateFormatter().string(from: Date()))]
            )
        }
    }

    // MARK: - Emptying

    /// Takes the invented ledger away and leaves the categories, so the next
    /// start — real this time — begins where a fresh install would.
    static func erase(from store: LocalStore? = LocalStore.shared) throws {
        guard let store else { return }
        let db = store.database
        try db.transaction {
            try db.exec("PRAGMA defer_foreign_keys = ON")
            for table in [
                "transactions", "holdings", "monthly_budgets", "balance_snapshots",
                "recurring_rules", "categorization_rules", "payee_aliases", "merchant_marks", "accounts",
            ] {
                try db.exec("DELETE FROM \(table)")
            }
            try db.run("DELETE FROM settings WHERE key = ?", [.text(marker)])
        }
        MerchantNames.shared.invalidate()
        Task { @MainActor in MerchantLogos.shared.invalidate() }
    }

    // MARK: - Finding the categories

    /// What each invented row is, independent of the language the categories
    /// were seeded in.
    enum Role: CaseIterable {
        case wages, rent, insurance, subscriptions, groceries, transport
        case diningOut, travel, gifts, clothes, savings

        /// Position in `SeedCategories.json`, which is the same in every
        /// language: group, then category.
        var slot: (Int, Int) {
            switch self {
            case .wages: (0, 0)
            case .rent: (1, 0)
            case .insurance: (1, 1)
            case .subscriptions: (1, 2)
            case .groceries: (2, 0)
            case .transport: (2, 1)
            case .diningOut: (3, 0)
            case .travel: (3, 1)
            case .gifts: (3, 2)
            case .clothes: (3, 3)
            case .savings: (4, 0)
            }
        }
    }

    private struct SeedGroup: Decodable {
        struct Category: Decodable { let name: String }
        let categories: [Category]
    }

    /// Role → category id, matching the name in any of the shipped languages.
    private static func roles(_ db: SQLiteDatabase) throws -> [Role: String] {
        guard let url = Bundle.main.url(forResource: "SeedCategories", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let template = try? JSONDecoder().decode([String: [SeedGroup]].self, from: data)
        else { return [:] }

        var ids: [String: String] = [:]
        for row in try db.query("SELECT id, name FROM categories WHERE is_archived = 0") {
            if let id = row.string("id"), let name = row.string("name") { ids[name] = id }
        }

        var found: [Role: String] = [:]
        for role in Role.allCases {
            let (group, index) = role.slot
            for groups in template.values {
                guard groups.indices.contains(group),
                      groups[group].categories.indices.contains(index),
                      let id = ids[groups[group].categories[index].name] else { continue }
                found[role] = id
                break
            }
        }
        return found
    }
}

/// A small deterministic generator, so the demo shows the same month every
/// time rather than a new shuffle on each install.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }

    mutating func amount(_ range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) / Double(1 << 53)
        return ((range.lowerBound + unit * (range.upperBound - range.lowerBound)) * 100).rounded() / 100
    }

    mutating func pick(_ items: [String]) -> String {
        items[int(0...(items.count - 1))]
    }
}
