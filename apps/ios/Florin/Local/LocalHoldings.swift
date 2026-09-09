import Foundation

/// Writes an account can take about itself, rather than about its rows.
///
/// Two things were possible only when an account was created and never again:
/// saying what is on it, and saying what it bought. Both are the whole point of
/// the accounts Florin does not sync — a Livret A that pays interest once a
/// year, a PEA that buys the same tracker every month — so both left their
/// owner watching a figure they could see was stale with no way to say so.
enum LocalHoldings {
    enum Failure: LocalizedError {
        case missing
        case notABroker

        var errorDescription: String? {
            switch self {
            case .missing: Strings.device("v2.account.gone", "Ce compte n'existe plus.")
            case .notABroker:
                Strings.device("v2.buy.notABroker", "Ce compte ne détient pas de titres.")
            }
        }
    }

    // MARK: - Saying what is on an account

    /*
     * Une opération d'ajustement, pas un point de départ déplacé en silence.
     *
     * La première version corrigeait `opening_balance` sans rien écrire. Le
     * calcul était juste et l'app restait muette : le solde bougeait, et rien
     * dans l'historique ne disait pourquoi — exactement le défaut qui a coûté
     * une soirée à comprendre où étaient passés cinq cents euros.
     *
     * L'écart s'écrit donc comme une ligne datée d'aujourd'hui, dans le genre
     * de groupe `adjustment`. Ce genre existe pour ça : le calcul des dépenses
     * ne retient que les montants négatifs des groupes `expense`, et celui des
     * entrées que les positifs des groupes `income`. Un ajustement n'est ni
     * l'un ni l'autre — il apparaît dans le compte, se lit dans l'historique,
     * et ne fausse aucun total.
     *
     * C'est le « rapprochement » de YNAB : on dit à l'app ce que la banque
     * affiche, elle écrit la différence plutôt que de la faire disparaître.
     */
    static func setBalance(store: LocalStore, accountId: String, to target: Double) throws {
        let row = try store.database.query(
            "SELECT kind, current_balance FROM accounts WHERE id = ?", [.text(accountId)]
        ).first
        guard let row, let kind = row.string("kind") else { throw Failure.missing }
        guard kind != "broker_portfolio" else { throw Failure.notABroker }

        let current = row.double("current_balance") ?? 0
        let delta = round((target - current) * 100) / 100
        guard delta != 0 else { return }

        let category = try adjustmentCategory(store)
        let label = Strings.device("v2.balance.adjustment", "Ajustement de solde")
        try store.database.transaction {
            try store.database.run(
                """
                INSERT INTO transactions
                    (id, account_id, occurred_at, amount, currency, payee, normalized_payee,
                     category_id, source, status, needs_review, is_pending)
                VALUES (?, ?, date('now'), ?, 'EUR', ?, ?, ?, 'manual', 'cleared', 0, 0)
                """,
                [
                    .text(UUID().uuidString), .text(accountId), .real(delta),
                    .text(label), .text(LocalLedger.normalize(label)), .text(category),
                ]
            )
            /*
             * Le point de départ est recalé sur le solde annoncé, pas l'inverse.
             *
             * La première version faisait `solde = ouverture + Σ lignes`, ce qui
             * suppose que l'historique du compte est complet. Sur un compte
             * repris d'un autre grand livre il ne l'est pas : le Livret A porte
             * quatorze lignes pour deux ans, et cette somme valait −1 000 € face
             * à un solde réel de 250 €. Corriger de +1 € l'a donc fait tomber à
             * −200,00 €. Le calcul était juste ; sa prémisse était fausse.
             *
             * L'annoncé fait foi — c'est son propriétaire qui vient de le lire
             * sur son relevé — et l'ouverture absorbe la part que Florin n'a
             * jamais vue. L'invariant `ouverture + Σ = solde` se retrouve vrai,
             * donc `recomputeBalance` peut repasser derrière sans rien casser :
             * jusqu'ici, une simple opération ajoutée sur ce compte l'aurait
             * précipité au même endroit.
             */
            let moved = try store.database.scalar(
                """
                SELECT coalesce(sum(amount), 0) FROM transactions
                WHERE account_id = ? AND deleted_at IS NULL AND status = 'cleared'
                """,
                [.text(accountId)]
            )?.double ?? 0
            let settled = round(target * 100) / 100
            try store.database.run(
                """
                UPDATE accounts SET current_balance = ?, opening_balance = ?,
                       updated_at = datetime('now')
                WHERE id = ?
                """,
                [
                    .real(settled),
                    .real(round((settled - moved) * 100) / 100),
                    .text(accountId),
                ]
            )
        }
    }

    /// La catégorie d'ajustement du grand livre, créée si le classeur de départ
    /// ne l'avait pas — les tables semées ne connaissent que dépenses et
    /// entrées, et un ajustement n'est ni l'un ni l'autre.
    private static func adjustmentCategory(_ store: LocalStore) throws -> String {
        if let id = try store.database.scalar(
            """
            SELECT c.id FROM categories c JOIN category_groups g ON g.id = c.group_id
            WHERE g.kind = 'adjustment' AND c.is_archived = 0 LIMIT 1
            """
        )?.string { return id }

        let groupId = try store.database.scalar(
            "SELECT id FROM category_groups WHERE kind = 'adjustment' LIMIT 1"
        )?.string ?? {
            let fresh = UUID().uuidString
            try? store.database.run(
                """
                INSERT INTO category_groups (id, name, kind, display_order)
                VALUES (?, ?, 'adjustment',
                        (SELECT coalesce(max(display_order) + 1, 0) FROM category_groups))
                """,
                [.text(fresh), .text(Strings.device("v2.balance.adjustments", "Ajustements"))]
            )
            return fresh
        }()

        let categoryId = UUID().uuidString
        try store.database.run(
            "INSERT INTO categories (id, group_id, name, emoji) VALUES (?, ?, ?, '⚖️')",
            [
                .text(categoryId), .text(groupId),
                .text(Strings.device("v2.balance.adjustment", "Ajustement de solde")),
            ]
        )
        return categoryId
    }

    // MARK: - Saying what an account bought

    struct Purchase {
        /// An existing holding, or nil to open a new line.
        let holdingId: String?
        let label: String
        let quantity: Double
        /// What one share cost — the figure the broker prints beside the count.
        let unitPrice: Double
        /// What actually left the account, fees included. Kept separate from
        /// `quantity × unitPrice` because the two differ by cents: a broker
        /// rounds the price it displays and charges the price it got.
        let total: Double
    }

    /*
     * A purchase is a holding line and a cash movement, and not a transaction.
     *
     * Buying a tracker inside a PEA is not spending — the money did not leave
     * the patrimoine, it changed shape inside one account. Written as a row it
     * would be uncategorised and negative, which is the exact shape the burn
     * analysis counts as spending, and September would report five hundred
     * euros of expenses that never happened.
     *
     * So the record is the holding itself, which is what the account's
     * portfolio banner already reads and shows: quantity, cost basis, and the
     * price the last purchase was made at. The idle cash falls by what was
     * paid, the same way `moveBrokerCash` moves it when a transfer lands.
     */
    static func record(store: LocalStore, accountId: String, purchase: Purchase) throws {
        let kind = try store.database.scalar(
            "SELECT kind FROM accounts WHERE id = ?", [.text(accountId)]
        )?.string
        guard let kind else { throw Failure.missing }
        guard kind == "broker_portfolio" else { throw Failure.notABroker }

        try store.database.transaction {
            if let holdingId = purchase.holdingId {
                try store.database.run(
                    """
                    UPDATE holdings
                    SET quantity = quantity + ?, cost_basis = cost_basis + ?,
                        last_price = ?, last_price_at = datetime('now'),
                        updated_at = datetime('now')
                    WHERE id = ?
                    """,
                    [
                        .real(purchase.quantity), .real(purchase.total),
                        .real(purchase.unitPrice), .text(holdingId),
                    ]
                )
            } else {
                try store.database.run(
                    """
                    INSERT INTO holdings
                        (id, account_id, label, quantity, cost_basis, currency,
                         last_price, last_price_at)
                    VALUES (?, ?, ?, ?, ?, 'EUR', ?, datetime('now'))
                    """,
                    [
                        .text(UUID().uuidString), .text(accountId), .text(purchase.label),
                        .real(purchase.quantity), .real(purchase.total),
                        .real(purchase.unitPrice),
                    ]
                )
            }

            try store.database.run(
                """
                UPDATE accounts
                SET current_balance = round((current_balance - ?) * 100) / 100.0,
                    updated_at = datetime('now')
                WHERE id = ?
                """,
                [.real(purchase.total), .text(accountId)]
            )
            try revalue(store, accountId: accountId)
        }
    }

    /// The account's securities, priced at what each line was last worth. The
    /// portfolio banner derives its own totals the same way; this keeps the
    /// figure on the accounts list — which reads `market_value` — in step.
    static func revalue(_ store: LocalStore, accountId: String) throws {
        let value = try store.database.scalar(
            """
            SELECT coalesce(sum(quantity * coalesce(last_price, 0)), 0)
            FROM holdings WHERE account_id = ?
            """,
            [.text(accountId)]
        )?.double ?? 0
        try store.database.run(
            "UPDATE accounts SET market_value = ?, updated_at = datetime('now') WHERE id = ?",
            [.real(round(value * 100) / 100), .text(accountId)]
        )
    }

    /// The lines an account already holds, for the purchase form's picker.
    static func lines(store: LocalStore, accountId: String) throws -> [(id: String, label: String)] {
        try store.database.query(
            "SELECT id, label FROM holdings WHERE account_id = ? ORDER BY label",
            [.text(accountId)]
        ).compactMap { row in
            guard let id = row.string("id"), let label = row.string("label") else { return nil }
            return (id, label)
        }
    }
}
