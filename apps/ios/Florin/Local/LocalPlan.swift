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
            WHERE t.deleted_at IS NULL AND t.is_pending = 0
              AND substr(t.occurred_at, 1, 10) <= date('now')
              AND substr(t.occurred_at, 1, 7) = ?
              /*
               * Not the other half of a transfer.
               *
               * The server's plan excludes these and the port did not, so a
               * transfer's inbound leg — if it carried a category — cancelled
               * the outbound one it mirrors. A loan repayment is exactly that
               * shape: 135,91 € leaves the current account and the same
               * amount lands against the debt.
               *
               * But excluding both legs is what reported "Réparti 136 €,
               * dépensé 0 €" for a bill paid every month without fail — the
               * real leg is paired too. Money the user filed under a category
               * is money they planned and watched leave, so it counts; only
               * outflows qualify, which keeps the mirror out for good.
               */
              AND (t.transfer_pair_id IS NULL
                   OR (t.category_id IS NOT NULL AND t.amount < 0))
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

        var groups: [PlanGroup] = []
        for groupRow in groupRows {
            guard let groupId = groupRow.string("id") else { continue }
            let members = categoryRows
                .filter { $0.string("group_id") == groupId }
                .map { row -> PlanCategory in
                    let id = row.string("id") ?? ""
                    let given = assigned[id] ?? 0
                    let used = round2(spent[id] ?? 0)
                    return PlanCategory(
                        id: id,
                        name: row.string("name") ?? "",
                        emoji: row.string("emoji"),
                        assigned: given,
                        spent: used,
                        available: round2(given - used),
                        note: notes[id],
                        isFixed: (row.int("is_fixed") ?? 0) == 1
                    )
                }

            let groupAssigned = members.reduce(0) { $0 + $1.assigned }
            let groupSpent = round2(members.reduce(0) { $0 + $1.spent })
            groups.append(
                PlanGroup(
                    id: groupId,
                    name: groupRow.string("name") ?? "",
                    kind: "expense",
                    color: groupRow.string("color"),
                    categories: members,
                    assigned: groupAssigned,
                    spent: groupSpent,
                    available: round2(groupAssigned - groupSpent),
                    overspentCount: members.filter { $0.assigned > 0 && $0.available < 0 }.count
                )
            )
        }

        return MonthPlan(
            year: year,
            month: month,
            groups: groups,
            income: round2(income),
            totalAssigned: round2(totalAssigned),
            readyToAssign: round2(income - totalAssigned),
            overspentCount: groups.reduce(0) { $0 + $1.overspentCount }
        )
    }

    /// Assigning is an upsert: one budget row per (year, month, category).
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

    private static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}
