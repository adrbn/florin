import Foundation

/// Le même format que le grand livre écrit — `yyyy-MM-dd`, hors fuseau.
enum Dates {
    static let iso: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

/*
 * Ce qu'on vous rend sur une dépense que vous avez avancée.
 *
 * Une addition partagée arrive en deux morceaux qui ne se ressemblent pas :
 * la dépense entière un soir, et quelques jours plus tard un virement d'un
 * prénom. Rien ne dit que les deux lignes parlent de la même soirée, et six
 * mois après, « +30 d'Angelina » ne veut plus rien dire.
 *
 * Le lien est porté par la RENTRÉE et désigne la dépense : une addition peut
 * être remboursée par trois personnes, l'inverse n'arrive pas. Une colonne
 * suffit donc, et il n'y a pas de table de jointure à tenir.
 *
 * Il ne déplace pas un centime. Ranger le remboursement dans la catégorie de
 * la dépense suffit déjà à ce que le poste se solde net — c'est ce que le
 * lien PROPOSE de faire au moment où on l'établit, pas ce qu'il recalcule
 * derrière. Un lien qui retirerait aussi la somme compterait deux fois.
 */
enum LocalReimbursements {
    /// Une ligne du lien, réduite à ce qu'un écran en montre.
    struct Entry: Identifiable, Sendable {
        let id: String
        let payee: String
        let amount: Double
        let day: Date
        /// De quoi dessiner la même pastille que partout ailleurs : la teinte
        /// vient de la catégorie, pas du marchand.
        var category: String?
        var emoji: String?
        /*
         * Annoncée, pas encaissée.
         *
         * « Attendre un remboursement » écrit une ligne au statut
         * `scheduled` : elle porte le montant entier, et elle est là le jour
         * même. Sans ce drapeau, une dépense dont on attend encore tout
         * l'argent se lisait « Remboursé » — la fiche affirmait un
         * mouvement qui n'a pas eu lieu.
         */
        var pending = false

        /// Arrivée pour de bon : comptabilisée, et pas datée en avant.
        var settled: Bool { !pending && day <= Date() }
    }

    /// Ce qu'on a rendu sur cette dépense, la plus récente d'abord.
    static func on(store: LocalStore, expense id: String) throws -> [Entry] {
        try store.database.query(
            """
            SELECT t.id, t.payee, t.amount, substr(t.occurred_at, 1, 10) AS day,
                   t.is_pending AS is_pending,
                   c.name AS category, c.emoji AS emoji
            FROM transactions t
            LEFT JOIN categories c ON c.id = t.category_id
            WHERE t.reimburses_tx_id = ? AND t.deleted_at IS NULL
            ORDER BY t.occurred_at DESC
            """,
            [.text(id)]
        ).compactMap(entry)
    }

    /*
     * La dépense que cette rentrée désigne — relue du grand livre.
     *
     * Et non prise sur la `Transaction` qu'un écran tient en mémoire. Une
     * fiche est ouverte AVANT qu'on y pose le lien : sa colonne vaut encore
     * `nil`, et c'est elle qu'on relisait après le choix. Le lien était bien
     * écrit, la catégorie bien recopiée, et l'écran continuait d'afficher
     * « Lier une dépense » — donc choisir « ne faisait rien ».
     *
     * On part de l'identifiant de la rentrée, qui lui ne bouge pas, et la
     * jointure va chercher l'état du moment.
     */
    static func linked(store: LocalStore, income id: String) throws -> Entry? {
        try store.database.query(
            """
            SELECT e.id, e.payee, e.amount, substr(e.occurred_at, 1, 10) AS day,
                   c.name AS category, c.emoji AS emoji
            FROM transactions i
            JOIN transactions e ON e.id = i.reimburses_tx_id
            LEFT JOIN categories c ON c.id = e.category_id
            WHERE i.id = ? AND e.deleted_at IS NULL
            """,
            [.text(id)]
        ).compactMap(entry).first
    }

    /*
     * Les dépenses qu'on peut désigner, et pas toutes.
     *
     * Remonter tout le grand livre donnerait une liste où l'on cherche au
     * lieu de reconnaître. Ce qu'on se fait rembourser est récent — on avance
     * l'argent, on le récupère dans la quinzaine — et c'est forcément une
     * dépense d'au moins le montant rendu : personne ne vous rend trente
     * euros sur une addition de douze.
     *
     * Quatre-vingt-dix jours en arrière à partir du jour de la rentrée, et
     * quelques-uns en avant, parce que la banque publie les deux lignes dans
     * l'ordre qu'elle veut.
     */
    static func candidates(
        store: LocalStore, for income: Transaction, search: String
    ) throws -> [Entry] {
        let day = String(income.date.prefix(10))
        let words = search.split(whereSeparator: \.isWhitespace).map {
            "%" + LocalLedger.normalize(String($0)).lowercased() + "%"
        }
        let filter = words.map { _ in
            "AND (lower(t.normalized_payee) LIKE ? OR lower(COALESCE(t.memo,'')) LIKE ?)"
        }.joined(separator: " ")
        var values: [SQLiteValue] = [
            .real(-abs(income.amount)), .text(day), .text(day), .text(income.id),
        ]
        for word in words { values.append(.text(word)); values.append(.text(word)) }
        return try store.database.query(
            """
            SELECT t.id, t.payee, t.amount, substr(t.occurred_at, 1, 10) AS day,
                   c.name AS category, c.emoji AS emoji
            FROM transactions t
            LEFT JOIN categories c ON c.id = t.category_id
            WHERE t.deleted_at IS NULL AND t.amount <= ?
              AND t.transfer_pair_id IS NULL
              AND julianday(substr(t.occurred_at, 1, 10)) BETWEEN julianday(?) - 90
                                                              AND julianday(?) + 7
              AND t.id <> ?
              \(filter)
            ORDER BY t.occurred_at DESC
            LIMIT 40
            """,
            values
        ).compactMap(entry)
    }

    /*
     * Le remboursement qu'on peut deviner tout seul.
     *
     * Un remboursement de marchand arrive sous un libellé qui ne nomme
     * personne — « CREDIT CARTE BANCAIRE » — parce que c'est le RAIL qui est
     * nommé, pas l'enseigne. Il n'y a donc rien à reconnaître dans les mots,
     * et le classeur, qui ne travaille que sur eux, passe forcément à côté :
     * un retour de marchand restait sans nom, sans catégorie, et c'est à la
     * main qu'on lui apprenait d'où il venait.
     *
     * Le montant, lui, dit tout. Un retour rend exactement ce qu'on a payé,
     * et le payer puis le reprendre au centime près est un hasard qui
     * n'arrive pas deux fois dans un trimestre. Le lien est donc posé quand
     * UNE SEULE dépense correspond : deux candidates, et on ne devine pas —
     * se tromper de dépense, ce serait solder la mauvaise enveloppe.
     *
     * Posé, pas validé : la ligne reste dans la file à vérifier, qui montre
     * désormais ce qu'on lui propose. La fiche, elle, dit « Remboursement de
     * … » comme pour un lien fait à la main, puisque c'est le même lien.
     *
     * Les centimes sont comparés en entiers. Deux nombres à virgule égaux au
     * centième ne sont pas égaux en machine, et une comparaison directe
     * aurait raté une correspondance sur deux sans jamais le dire.
     */
    @discardableResult
    static func propose(store: LocalStore) throws -> Int {
        let credits = try store.database.query(
            """
            SELECT t.id, t.amount, substr(t.occurred_at, 1, 10) AS day, t.category_id
            FROM transactions t
            JOIN accounts a ON a.id = t.account_id
            WHERE t.deleted_at IS NULL AND t.amount > 0
              AND t.reimburses_tx_id IS NULL
              AND t.transfer_pair_id IS NULL
              AND a.kind <> 'loan'
              /*
               * Seulement ce sur quoi personne ne s'est prononcé — la même
               * règle que `LocalCategoriser.backfill` : une rentrée approuvée
               * telle quelle est une décision, pas un oubli à rattraper.
               */
              AND (t.needs_review = 1 OR t.is_pending = 1)
            ORDER BY t.occurred_at DESC LIMIT 200
            """
        )
        guard !credits.isEmpty else { return 0 }

        var linked = 0
        try store.database.transaction {
            for credit in credits {
                guard let id = credit.string("id"),
                      let amount = credit.double("amount"),
                      let day = credit.string("day")
                else { continue }
                let cents = Int64((amount * 100).rounded())
                guard cents > 0 else { continue }

                let matches = try store.database.query(
                    """
                    SELECT e.id, e.category_id
                    FROM transactions e
                    JOIN accounts a ON a.id = e.account_id
                    WHERE e.deleted_at IS NULL
                      AND CAST(round(-e.amount * 100) AS INTEGER) = ?
                      AND e.transfer_pair_id IS NULL
                      AND a.kind <> 'loan'
                      AND e.id <> ?
                      AND julianday(substr(e.occurred_at, 1, 10))
                          BETWEEN julianday(?) - 90 AND julianday(?) + 7
                      -- Une dépense déjà rendue ne se rend pas deux fois.
                      AND NOT EXISTS (
                          SELECT 1 FROM transactions r
                          WHERE r.reimburses_tx_id = e.id AND r.deleted_at IS NULL
                      )
                    LIMIT 2
                    """,
                    [.integer(cents), .text(id), .text(day), .text(day)]
                )
                guard matches.count == 1, let expense = matches[0].string("id") else { continue }

                try store.database.run(
                    """
                    UPDATE transactions SET reimburses_tx_id = ?, updated_at = datetime('now')
                    WHERE id = ? AND reimburses_tx_id IS NULL
                    """,
                    [.text(expense), .text(id)]
                )
                /*
                 * Et la catégorie de la dépense, pour que le poste se solde
                 * net — c'est ce que le lien propose quand on l'établit à la
                 * main. Jamais par-dessus un classement existant.
                 */
                if credit.string("category_id") == nil,
                   let category = matches[0].string("category_id") {
                    try store.database.run(
                        """
                        UPDATE transactions SET category_id = ?, updated_at = datetime('now')
                        WHERE id = ? AND category_id IS NULL
                        """,
                        [.text(category), .text(id)]
                    )
                }
                linked += 1
            }
        }
        return linked
    }

    /// Lier une rentrée à une dépense, ou défaire le lien avec `nil`.
    static func link(store: LocalStore, income: String, to expense: String?) throws {
        try store.database.run(
            """
            UPDATE transactions SET reimburses_tx_id = ?, updated_at = datetime('now')
            WHERE id = ?
            """,
            [expense.map { SQLiteValue.text($0) } ?? .null, .text(income)]
        )
    }

    private static func entry(_ row: SQLiteRow) -> Entry? {
        guard let id = row.string("id"), let amount = row.double("amount"),
              let day = row.string("day") else { return nil }
        return Entry(
            id: id, payee: row.string("payee") ?? "", amount: amount,
            day: Dates.iso.date(from: day) ?? .distantPast,
            category: row.string("category"), emoji: row.string("emoji"),
            pending: row.bool("is_pending")
        )
    }
}
