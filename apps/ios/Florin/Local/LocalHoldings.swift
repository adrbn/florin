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
             * repris d'un autre grand livre il ne l'est pas : un livret porte
             * quelques lignes pour deux ans, dont la somme est loin du solde
             * réel. Corriger ce solde d'un euro l'a donc fait passer sous zéro. Le calcul était juste ; sa prémisse était fausse.
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

        let lineId = purchase.holdingId ?? UUID().uuidString
        /// Le prix affiché avant cet achat, pour que l'annulation rende la
        /// ligne telle qu'elle était et non telle que cet achat l'a laissée.
        let before = purchase.holdingId.flatMap { id in
            try? store.database.scalar(
                "SELECT last_price FROM holdings WHERE id = ?", [.text(id)]
            )?.double
        }

        try store.database.transaction {
            if purchase.holdingId != nil {
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
                        .real(purchase.unitPrice), .text(lineId),
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
                        .text(lineId), .text(accountId), .text(purchase.label),
                        .real(purchase.quantity), .real(purchase.total),
                        .real(purchase.unitPrice),
                    ]
                )
            }

            /*
             * La trace de l'achat, qui n'est pas une opération du grand livre.
             *
             * Sans elle il ne restait de l'achat qu'un cumul : une ligne de
             * titres gonflée et des liquidités en moins, rien qui dise qu'un
             * geste a eu lieu, donc rien à défaire. Une saisie de travers se
             * corrigeait à la main, en retranchant soi-même des parts qu'on
             * n'avait jamais vues écrites nulle part.
             *
             * Elle ne va pas dans `transactions` — voir la note ci-dessus : ce
             * serait une dépense de cinq cents euros qui n'a pas eu lieu. Elle
             * reste à côté, lue par le bandeau du portefeuille, et `undo` la
             * rejoue à l'envers.
             */
            try store.database.run(
                """
                INSERT INTO holding_purchases
                    (id, account_id, holding_id, label, quantity, unit_price,
                     total, previous_price, opened_line)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(UUID().uuidString), .text(accountId), .text(lineId),
                    .text(purchase.label), .real(purchase.quantity),
                    .real(purchase.unitPrice), .real(purchase.total),
                    before.map { SQLiteValue.real($0) } ?? .null,
                    .integer(purchase.holdingId == nil ? 1 : 0),
                ]
            )

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

    // MARK: - Défaire un achat

    struct Recorded: Identifiable {
        let id: String
        let holdingId: String
        let label: String
        let quantity: Double
        let unitPrice: Double
        let total: Double
        let recordedAt: Date
    }

    /// Les achats saisis sur ce compte, le dernier d'abord.
    static func purchases(store: LocalStore, accountId: String) throws -> [Recorded] {
        try store.database.query(
            """
            SELECT id, holding_id, label, quantity, unit_price, total, recorded_at
            FROM holding_purchases WHERE account_id = ?
            ORDER BY recorded_at DESC, rowid DESC
            """,
            [.text(accountId)]
        ).compactMap { row in
            guard let id = row.string("id"), let holdingId = row.string("holding_id"),
                  let label = row.string("label")
            else { return nil }
            return Recorded(
                id: id, holdingId: holdingId, label: label,
                quantity: row.double("quantity") ?? 0,
                unitPrice: row.double("unit_price") ?? 0,
                total: row.double("total") ?? 0,
                recordedAt: Timestamp.parse(row.string("recorded_at")) ?? Date()
            )
        }
    }

    /*
     * L'achat rejoué à l'envers : les parts partent, l'argent revient.
     *
     * Trois cas, et le premier est celui qui compte. Si cet achat avait ouvert
     * la ligne et qu'aucun autre ne s'y rattache, la ligne disparaît — la
     * laisser à zéro part afficherait un titre qu'on ne détient pas. Sinon on
     * retranche. Et le dernier prix connu n'est remis à celui d'avant que si
     * cet achat est le plus récent de sa ligne : un achat plus tardif a depuis
     * dit le prix du marché, et le ressusciter serait une régression du cours.
     */
    static func undo(store: LocalStore, purchaseId: String) throws {
        guard let row = try store.database.query(
            """
            SELECT account_id, holding_id, quantity, total, previous_price, opened_line
            FROM holding_purchases WHERE id = ?
            """,
            [.text(purchaseId)]
        ).first,
            let accountId = row.string("account_id"),
            let holdingId = row.string("holding_id")
        else { throw Failure.missing }

        let quantity = row.double("quantity") ?? 0
        let total = row.double("total") ?? 0
        let siblings = try store.database.scalar(
            "SELECT count(*) FROM holding_purchases WHERE holding_id = ? AND id <> ?",
            [.text(holdingId), .text(purchaseId)]
        )?.double ?? 0
        /// Par `rowid` et non par date : deux achats saisis dans la même
        /// seconde portent le même horodatage, et « lequel est le plus
        /// récent » n'a alors plus de réponse.
        let newer = try store.database.scalar(
            """
            SELECT count(*) FROM holding_purchases
            WHERE holding_id = ?
              AND rowid > (SELECT rowid FROM holding_purchases WHERE id = ?)
            """,
            [.text(holdingId), .text(purchaseId)]
        )?.double ?? 0

        try store.database.transaction {
            if siblings == 0, (row.double("opened_line") ?? 0) == 1 {
                try store.database.run(
                    "DELETE FROM holdings WHERE id = ?", [.text(holdingId)]
                )
            } else if newer == 0, let before = row.double("previous_price") {
                try store.database.run(
                    """
                    UPDATE holdings
                    SET quantity = quantity - ?, cost_basis = cost_basis - ?,
                        last_price = ?, updated_at = datetime('now')
                    WHERE id = ?
                    """,
                    [.real(quantity), .real(total), .real(before), .text(holdingId)]
                )
            } else {
                try store.database.run(
                    """
                    UPDATE holdings
                    SET quantity = quantity - ?, cost_basis = cost_basis - ?,
                        updated_at = datetime('now')
                    WHERE id = ?
                    """,
                    [.real(quantity), .real(total), .text(holdingId)]
                )
            }
            try store.database.run(
                """
                UPDATE accounts
                SET current_balance = round((current_balance + ?) * 100) / 100.0,
                    updated_at = datetime('now')
                WHERE id = ?
                """,
                [.real(total), .text(accountId)]
            )
            try store.database.run(
                "DELETE FROM holding_purchases WHERE id = ?", [.text(purchaseId)]
            )
            try revalue(store, accountId: accountId)
        }
    }

    // MARK: - Corriger une ligne de titres

    /*
     * Une ligne de titres se corrige, et se supprime.
     *
     * Les achats d'avant `holding_purchases` n'ont pas laissé de trace : il
     * n'y a rien à annuler pour eux, et pourtant c'est exactement là que les
     * erreurs se sont accumulées. Plus généralement une ligne était en
     * écriture seule — on pouvait y ajouter des parts et jamais en retirer,
     * ni corriger une quantité, ni effacer une ligne ouverte par méprise.
     *
     * Les trois chiffres sont distincts et le restent : la quantité, le cours,
     * et le versé. Corriger une quantité ne touche pas au versé — l'argent est
     * réellement parti, c'est la quantité qui était fausse — donc rien ne
     * bouge du côté des liquidités. Supprimer la ligne, si : le versé revient,
     * puisqu'on vient de dire que cet achat n'a jamais eu lieu.
     */
    static func update(
        store: LocalStore, holdingId: String, label: String,
        quantity: Double, unitPrice: Double, costBasis: Double
    ) throws {
        guard let accountId = try store.database.scalar(
            "SELECT account_id FROM holdings WHERE id = ?", [.text(holdingId)]
        )?.string else { throw Failure.missing }

        try store.database.transaction {
            try store.database.run(
                """
                UPDATE holdings
                SET label = ?, quantity = ?, cost_basis = ?, last_price = ?,
                    last_price_at = datetime('now'), updated_at = datetime('now')
                WHERE id = ?
                """,
                [
                    .text(label), .real(quantity), .real(round(costBasis * 100) / 100),
                    .real(unitPrice), .text(holdingId),
                ]
            )
            try revalue(store, accountId: accountId)
        }
    }

    /// La ligne disparaît et le versé retourne aux liquidités, avec les achats
    /// qui s'y rattachaient : il n'y a plus rien à leur défaire.
    static func remove(store: LocalStore, holdingId: String) throws {
        guard let row = try store.database.query(
            "SELECT account_id, cost_basis FROM holdings WHERE id = ?", [.text(holdingId)]
        ).first, let accountId = row.string("account_id") else { throw Failure.missing }
        let basis = row.double("cost_basis") ?? 0

        try store.database.transaction {
            try store.database.run("DELETE FROM holdings WHERE id = ?", [.text(holdingId)])
            try store.database.run(
                "DELETE FROM holding_purchases WHERE holding_id = ?", [.text(holdingId)]
            )
            try store.database.run(
                """
                UPDATE accounts
                SET current_balance = round((current_balance + ?) * 100) / 100.0,
                    updated_at = datetime('now')
                WHERE id = ?
                """,
                [.real(basis), .text(accountId)]
            )
            try revalue(store, accountId: accountId)
        }
    }

    // MARK: - Les liquidités qui ont déjà quitté l'enveloppe

    struct CashOut: Identifiable {
        /// L'opération candidate, celle qu'il suffit d'apparier.
        let id: String
        let accountName: String
        let amount: Double
        let day: Date
    }

    /*
     * Le virement de retour, retrouvé plutôt que redemandé.
     *
     * Après un achat il reste des miettes : la part qu'on n'a pas pu investir.
     * Elles ont deux fins possibles — attendre le prochain achat, ou repartir
     * sur le compte courant. Dans le second cas la banque a déjà vu l'argent
     * arriver, et Florin affiche pourtant toujours ces liquidités dans
     * l'enveloppe : l'entrée est là, elle n'est simplement rattachée à rien.
     *
     * Plutôt qu'un formulaire de plus, on cherche l'entrée qui colle : le
     * montant des liquidités qui dorment ici, à cinq centimes près, sur un
     * autre compte, non appariée, depuis le dernier achat. C'est une
     * proposition et pas une conclusion — l'appariement reste un geste, et il
     * passe par `LocalWrites.attachTransfer`, qui sait déjà sortir l'argent du
     * courtier.
     */
    static func repatriation(
        store: LocalStore, accountId: String, cash: Double
    ) throws -> CashOut? {
        guard cash > 0.5 else { return nil }
        let fromPurchase = try store.database.scalar(
            "SELECT max(date(recorded_at)) FROM holding_purchases WHERE account_id = ?",
            [.text(accountId)]
        )?.string
        // Le dernier achat, ou à défaut la dernière fois qu'une ligne a bougé :
        // les achats d'avant cette table n'ont pas laissé de trace.
        let fromHolding = try store.database.scalar(
            """
            SELECT max(date(coalesce(last_price_at, created_at)))
            FROM holdings WHERE account_id = ?
            """,
            [.text(accountId)]
        )?.string
        guard let since = [fromPurchase, fromHolding].compactMap({ $0 }).max(),
              !since.isEmpty
        else { return nil }

        guard let row = try store.database.query(
            """
            SELECT t.id, t.amount, t.occurred_at, a.name AS account_name
            FROM transactions t JOIN accounts a ON a.id = t.account_id
            WHERE t.deleted_at IS NULL AND t.transfer_pair_id IS NULL
              AND t.account_id <> ? AND t.amount > 0
              AND abs(t.amount - ?) <= 0.05
              AND date(t.occurred_at) >= ?
            ORDER BY t.occurred_at DESC LIMIT 1
            """,
            [.text(accountId), .real(cash), .text(since)]
        ).first, let id = row.string("id") else { return nil }

        return CashOut(
            id: id,
            accountName: row.string("account_name") ?? "",
            amount: row.double("amount") ?? 0,
            day: Timestamp.parse(row.string("occurred_at")) ?? Date()
        )
    }

    /// The lines an account already holds, for the purchase form's picker.
    ///
    /// Avec le dernier prix connu, qui n'est pas un ornement : c'est lui qui
    /// permet au formulaire de déduire la quantité du montant payé, le seul
    /// des trois chiffres dont l'acheteur dispose à coup sûr.
    static func lines(
        store: LocalStore, accountId: String
    ) throws -> [(id: String, label: String, lastPrice: Double?)] {
        try store.database.query(
            "SELECT id, label, last_price FROM holdings WHERE account_id = ? ORDER BY label",
            [.text(accountId)]
        ).compactMap { row in
            guard let id = row.string("id"), let label = row.string("label") else { return nil }
            return (id, label, row.double("last_price"))
        }
    }
}
