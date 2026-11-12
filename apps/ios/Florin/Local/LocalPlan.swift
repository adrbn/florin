import Foundation

/// The envelope budget, computed on the device.
///
/// A faithful port of `getMonthPlanQuery`, including the parts that look like
/// details and are not:
///
///  - spending is `-signed(amount)`, not `abs(amount)`, so a refund booked into
///    an expense category *reduces* that category rather than adding to it;
///  - `spent` sums across every account, which is why a loan mirror must never
///    carry a category — it holds the opposite sign to the payment it reflects
///    and would cancel the very spending it mirrors;
///  - empty groups survive, because a group you have not funded yet still has
///    to be visible to be funded;
///  - a group's overspent count only counts categories that were actually
///    given money. Spending in an unfunded category is not an overspend, it is
///    an unassigned expense, and conflating them made the badge shout about
///    envelopes nobody had opened.
enum LocalPlan {
    static func month(store: LocalStore, year: Int, month: Int) throws -> MonthPlan {
        let db = store.database
        let key = String(format: "%04d-%02d", year, month)

        // Every expense group, including the ones with nothing in them.
        let groupRows = try db.query(
            """
            SELECT id, name, color FROM category_groups
            WHERE kind = 'expense' ORDER BY display_order, name
            """
        )

        let categoryRows = try db.query(
            """
            SELECT c.id AS id, c.name AS name, c.emoji AS emoji, c.is_fixed AS is_fixed,
                   g.id AS group_id
            FROM categories c
            JOIN category_groups g ON g.id = c.group_id
            WHERE c.is_archived = 0 AND g.kind = 'expense'
            ORDER BY g.display_order, g.name, c.display_order, c.name
            """
        )

        // Assigned amounts and notes for this month.
        var assigned: [String: Double] = [:]
        var notes: [String: String] = [:]
        var totalAssigned = 0.0
        for row in try db.query(
            "SELECT category_id, assigned, note FROM monthly_budgets WHERE year = ? AND month = ?",
            [.integer(Int64(year)), .integer(Int64(month))]
        ) {
            guard let id = row.string("category_id") else { continue }
            let value = row.double("assigned") ?? 0
            assigned[id] = value
            totalAssigned += value
            if let note = row.string("note") { notes[id] = note }
        }

        // Spending per category, and the month's income.
        var spent: [String: Double] = [:]
        var income = 0.0
        for row in try db.query(
            """
            SELECT t.category_id AS id, t.amount AS amount, g.kind AS kind
            FROM transactions t
            JOIN categories c ON c.id = t.category_id
            JOIN category_groups g ON g.id = c.group_id
            /*
             * Comptabilisé ou simplement présenté : la somme est retenue dans
             * les deux cas, et le total du mois la compte (voir
             * `LocalQueries.sum`). Le filtre portait sur l'attente, si bien
             * qu'une enveloppe affichait moins dépensé que le tableau de
             * bord. `status` écarte ce qui reste une prévision — saisie à la
             * main, ou devinée du Wallet.
             */
            \(spendingFilter)
              AND substr(t.occurred_at, 1, 7) = ?
            """,
            [.text(key)]
        ) {
            guard let id = row.string("id") else { continue }
            let amount = row.double("amount") ?? 0
            if row.string("kind") == "income" {
                income += amount
            } else {
                spent[id, default: 0] -= amount
            }
        }

        let carried = try carryover(db, before: key)

        var groups: [PlanGroup] = []
        for groupRow in groupRows {
            guard let groupId = groupRow.string("id") else { continue }
            let members = categoryRows
                .filter { $0.string("group_id") == groupId }
                .map { row -> PlanCategory in
                    let id = row.string("id") ?? ""
                    let given = assigned[id] ?? 0
                    let used = round2(spent[id] ?? 0)
                    let opening = carried.opening[id] ?? 0
                    return PlanCategory(
                        id: id,
                        name: row.string("name") ?? "",
                        emoji: row.string("emoji"),
                        assigned: given,
                        spent: used,
                        available: round2(opening + given - used),
                        note: notes[id],
                        isFixed: (row.int("is_fixed") ?? 0) == 1,
                        carried: opening
                    )
                }

            let groupAssigned = members.reduce(0) { $0 + $1.assigned }
            let groupSpent = round2(members.reduce(0) { $0 + $1.spent })
            /*
             * Le total d'un poste est la somme de ses enveloppes, rien d'autre.
             *
             * Il valait « réparti moins dépensé » du mois seul, donc il
             * ignorait le report — et un poste annonçait quatre-vingts euros
             * au-dessus d'enveloppes qui en portaient sept cents. Le chiffre
             * du haut contredisait les pastilles du dessous, et c'est le
             * chiffre du haut qu'on lit en premier.
             */
            let groupAvailable = round2(members.reduce(0) { $0 + $1.available })
            groups.append(
                PlanGroup(
                    id: groupId,
                    name: groupRow.string("name") ?? "",
                    kind: "expense",
                    color: groupRow.string("color"),
                    categories: members,
                    assigned: groupAssigned,
                    spent: groupSpent,
                    available: groupAvailable,
                    overspentCount: members.filter { $0.assigned > 0 && $0.available < 0 }.count
                )
            )
        }

        /*
         * A month still running is planned against what it will bring in.
         *
         * `income` is what has landed, and a salary lands around the 27th — so
         * for twenty-six days of every month the plan was measured against a
         * figure that had nothing to do with it, announcing "sur 0 € de
         * revenus" and calling an ordinary plan an overspend.
         *
         * The median of the six complete months before it is the estimate:
         * robust where a mean is not, since one month carrying a 500 € cheque
         * should not raise what the next is expected to earn. A month that is
         * over keeps its own figure — there is nothing left to estimate.
         */
        var expected = round2(income)
        var estimated = false
        if key >= LocalQueries.monthFormatter.string(from: Date()) {
            let typical = try typicalIncome(db, before: key)
            if typical > expected {
                expected = typical
                estimated = true
            }
        }

        return MonthPlan(
            year: year,
            month: month,
            groups: groups,
            income: round2(income),
            expectedIncome: expected,
            incomeIsEstimated: estimated,
            totalAssigned: round2(totalAssigned),
            readyToAssign: round2(expected - totalAssigned - carried.absorbed),
            overspentCount: groups.reduce(0) { $0 + $1.overspentCount },
            absorbed: carried.absorbed
        )
    }

    /// Assigning is an upsert: one budget row per (year, month, category).
    /// A month that has budgets, and how many — for offering something to copy.
    struct PlanSource: Identifiable, Equatable {
        var year: Int
        var month: Int
        var categories: Int
        var total: Double
        var id: String { "\(year)-\(month)" }
    }

    /// The months worth copying from, newest first.
    static func sourceMonths(_ db: SQLiteDatabase, excluding: (year: Int, month: Int)) throws -> [PlanSource] {
        try db.query(
            """
            SELECT year, month, count(*) AS n, coalesce(sum(assigned), 0) AS total
            FROM monthly_budgets
            WHERE assigned > 0 AND NOT (year = ? AND month = ?)
            GROUP BY year, month
            ORDER BY year DESC, month DESC
            LIMIT 12
            """,
            [.integer(Int64(excluding.year)), .integer(Int64(excluding.month))]
        ).map {
            PlanSource(
                year: $0.int("year") ?? 0, month: $0.int("month") ?? 0,
                categories: $0.int("n") ?? 0, total: $0.double("total") ?? 0
            )
        }
    }

    /*
     * Last month's plan, brought forward.
     *
     * A budget is mostly the same month after month — the rent does not move,
     * the groceries barely — so starting an empty month by retyping twenty
     * amounts is work the ledger already knows the answer to.
     *
     * Only categories with nothing assigned are filled. Copying over a figure
     * someone has already set this month would undo a deliberate decision to
     * answer a question they did not ask.
     */
    @discardableResult
    static func copyPlan(
        store: LocalStore, from source: (year: Int, month: Int), to target: (year: Int, month: Int)
    ) throws -> Int {
        var copied = 0
        try store.database.transaction {
            let rows = try store.database.query(
                """
                SELECT b.category_id, b.assigned FROM monthly_budgets b
                JOIN categories c ON c.id = b.category_id AND c.is_archived = 0
                WHERE b.year = ? AND b.month = ? AND b.assigned > 0
                """,
                [.integer(Int64(source.year)), .integer(Int64(source.month))]
            )
            for row in rows {
                guard let category = row.string("category_id") else { continue }
                let existing = try store.database.scalar(
                    """
                    SELECT assigned FROM monthly_budgets
                    WHERE year = ? AND month = ? AND category_id = ?
                    """,
                    [.integer(Int64(target.year)), .integer(Int64(target.month)), .text(category)]
                )?.double
                guard (existing ?? 0) == 0 else { continue }
                try assign(
                    store: store, year: target.year, month: target.month,
                    categoryId: category, amount: row.double("assigned") ?? 0
                )
                copied += 1
            }
        }
        return copied
    }

    static func assign(
        store: LocalStore,
        year: Int,
        month: Int,
        categoryId: String,
        amount: Double
    ) throws {
        let existing = try store.database.scalar(
            "SELECT id FROM monthly_budgets WHERE year = ? AND month = ? AND category_id = ?",
            [.integer(Int64(year)), .integer(Int64(month)), .text(categoryId)]
        )?.string

        if let existing {
            try store.database.run(
                "UPDATE monthly_budgets SET assigned = ?, updated_at = datetime('now') WHERE id = ?",
                [.real(amount), .text(existing)]
            )
        } else {
            try store.database.run(
                """
                INSERT INTO monthly_budgets (id, year, month, category_id, assigned)
                VALUES (?, ?, ?, ?, ?)
                """,
                [
                    .text(UUID().uuidString), .integer(Int64(year)),
                    .integer(Int64(month)), .text(categoryId), .real(amount),
                ]
            )
        }
    }

    /*
     * Ce qui compte comme dépensé, écrit une fois.
     *
     * Le mois courant et le report lisent les mêmes opérations : si les deux
     * filtres vivaient côte à côte, l'un finirait par compter ce que l'autre
     * écarte, et une enveloppe afficherait un report qui ne colle pas à la
     * somme des mois qui le composent. Le mois à retenir reste à l'appelant.
     */
    static let spendingFilter = """
            WHERE t.deleted_at IS NULL AND t.status = 'cleared'
              AND substr(t.occurred_at, 1, 10) <= date('now')
              /*
               * Not the other half of a transfer.
               *
               * The server's plan excludes these and the port did not, so a
               * transfer's inbound leg — if it carried a category — cancelled
               * the outbound one it mirrors. A loan repayment is exactly that
               * shape: 165,13 € leaves the current account and the same
               * amount lands against the debt.
               *
               * But excluding both legs is what reported "Réparti 136 €,
               * dépensé 0 €" for a bill paid every month without fail — the
               * real leg is paired too.
               *
               * What decides is the account on the other side, and then
               * the filing. Settling a debt is a bill you budget for, and so
               * is paying yourself: a standing transfer to savings or to a
               * portfolio is the most deliberate outflow of the month, and
               * the plan described it as nothing at all. Leaving it out of
               * what remains to assign promised money that was already
               * spoken for, every single month.
               *
               * So a transfer whose other leg is a debt, a savings account
               * or a portfolio MAY be budgeted; the category on it is what
               * says that it is. Leave one unfiled and it stays invisible,
               * exactly as before — nothing already recorded changes
               * meaning. Only outflows qualify, so the leg landing in the
               * portfolio can never count as well, and a transfer between
               * two current accounts still never does.
               */
              AND (t.transfer_pair_id IS NULL
                   OR (t.amount < 0 AND EXISTS (
                     SELECT 1 FROM transactions p
                     JOIN accounts pa ON pa.id = p.account_id
                     WHERE p.transfer_pair_id = t.transfer_pair_id
                       AND p.id <> t.id AND p.deleted_at IS NULL
                       AND pa.kind IN ('loan', 'savings', 'broker_portfolio'))))
    """

    /*
     * Ce qui reste dans l'enveloppe en entrant dans le mois.
     *
     * Sans report, « disponible » valait assigné moins dépensé du mois seul,
     * et chaque 1er du mois remettait tout à zéro. Une enveloppe ne pouvait
     * donc pas servir à mettre de côté : soixante euros par mois dans Voyages
     * ne faisaient jamais quatre cent quatre-vingts euros au départ, le mois
     * du voyage était forcément un dépassement, et les sept mois sans voyage
     * s'évaporaient. Le plan ne décrivait que les dépenses mensuelles
     * régulières — les seules qu'on connaît déjà par cœur.
     *
     * UN NÉGATIF NE SE REPORTE PAS. C'est la règle de YNAB et ce n'est pas un
     * adoucissement : un dépassement est une dette envers le mois suivant
     * tout entier, pas envers cette enveloppe-là. La reporter en négatif
     * condamnerait la catégorie à rester rouge des mois durant pour un
     * débordement unique — sur ce grand livre, huit catégories sur dix-neuf
     * ouvraient dans le rouge, Transports à moins neuf cent onze euros. Le
     * dépassement est rendu à part, par `absorbed`, et retranché de ce qu'il
     * reste à répartir : sans cela le report ne montrerait que les bonnes
     * nouvelles.
     *
     * Le report part du PREMIER MOIS BUDGÉTÉ, pas de la première opération.
     * Les dépenses d'avant n'ont jamais eu d'enveloppe à vider ; les compter
     * ferait porter à la première enveloppe toute une vie de dépenses.
     */
    struct Carryover {
        /// Ce que chaque catégorie apporte en entrant dans le mois.
        var opening: [String: Double] = [:]
        /// Les dépassements du dernier mois clos, à solder sur celui-ci.
        var absorbed: Double = 0
    }

    static func carryover(_ db: SQLiteDatabase, before key: String) throws -> Carryover {
        guard let first = try db.scalar(
            "SELECT min(printf('%04d-%02d', year, month)) FROM monthly_budgets"
        )?.string, first < key else { return Carryover() }

        var assigned: [String: [String: Double]] = [:]
        for row in try db.query(
            """
            SELECT category_id AS id, printf('%04d-%02d', year, month) AS k, assigned
            FROM monthly_budgets WHERE printf('%04d-%02d', year, month) < ?
            """,
            [.text(key)]
        ) {
            guard let id = row.string("id"), let k = row.string("k") else { continue }
            assigned[id, default: [:]][k] = row.double("assigned") ?? 0
        }

        var spent: [String: [String: Double]] = [:]
        for row in try db.query(
            """
            SELECT t.category_id AS id, substr(t.occurred_at, 1, 7) AS k,
                   sum(t.amount) AS total
            FROM transactions t
            JOIN categories c ON c.id = t.category_id
            JOIN category_groups g ON g.id = c.group_id
            \(spendingFilter)
              AND g.kind = 'expense'
              AND substr(t.occurred_at, 1, 7) >= ?
              AND substr(t.occurred_at, 1, 7) < ?
            GROUP BY t.category_id, substr(t.occurred_at, 1, 7)
            """,
            [.text(first), .text(key)]
        ) {
            guard let id = row.string("id"), let k = row.string("k") else { continue }
            spent[id, default: [:]][k] = -(row.double("total") ?? 0)
        }

        // Les mois se parcourent dans l'ordre : un report est une somme qui
        // bute sur zéro, et une somme qui bute ne se calcule pas en bloc.
        var months = Set(assigned.values.flatMap(\.keys))
        months.formUnion(spent.values.flatMap(\.keys))
        let ordered = months.filter { $0 >= first && $0 < key }.sorted()

        let previous = ordered.last

        var result = Carryover()
        for id in Set(assigned.keys).union(spent.keys) {
            var balance = 0.0
            for month in ordered {
                balance += (assigned[id]?[month] ?? 0) - (spent[id]?[month] ?? 0)
                if balance < 0 {
                    // Seul le mois qui précède immédiatement se solde ici :
                    // les plus anciens l'ont déjà été, en leur temps.
                    if month == previous { result.absorbed += -balance }
                    balance = 0
                }
            }
            if balance != 0 { result.opening[id] = round2(balance) }
        }
        result.absorbed = round2(result.absorbed)
        return result
    }

    private static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }

    /*
     * The middle month of the six before this one, months with no income left
     * out — a ledger that starts mid-history should not be told it earns
     * nothing every other month. The median rather than the mean, so one
     * month carrying a cheque or a tax refund does not raise the estimate.
     */
    private static func typicalIncome(_ db: SQLiteDatabase, before key: String) throws -> Double {
        let totals = try db.query(
            """
            SELECT substr(t.occurred_at, 1, 7) AS month, sum(t.amount) AS total
            FROM transactions t
            JOIN categories c ON c.id = t.category_id
            JOIN category_groups g ON g.id = c.group_id
            WHERE t.deleted_at IS NULL AND g.kind = 'income' AND t.amount > 0
              AND t.transfer_pair_id IS NULL
              AND substr(t.occurred_at, 1, 7) >= strftime('%Y-%m', date(? || '-01', '-6 months'))
              AND substr(t.occurred_at, 1, 7) < ?
            GROUP BY month
            """,
            [.text(key), .text(key)]
        ).compactMap { $0.double("total") }.filter { $0 > 0 }.sorted()

        guard !totals.isEmpty else { return 0 }
        let middle = totals.count / 2
        return round2(
            totals.count % 2 == 1
                ? totals[middle]
                : (totals[middle - 1] + totals[middle]) / 2
        )
    }

}
