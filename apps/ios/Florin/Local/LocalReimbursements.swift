import Foundation

/// Le même format que le grand livre écrit — `yyyy-MM-dd`, hors fuseau.
enum Dates {
    nonisolated(unsafe) static let iso: DateFormatter = {
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
    }

    /// Ce qu'on a rendu sur cette dépense, la plus récente d'abord.
    static func on(store: LocalStore, expense id: String) throws -> [Entry] {
        try store.database.query(
            """
            SELECT id, payee, amount, substr(occurred_at, 1, 10) AS day
            FROM transactions
            WHERE reimburses_tx_id = ? AND deleted_at IS NULL
            ORDER BY occurred_at DESC
            """,
            [.text(id)]
        ).compactMap(entry)
    }

    /// La dépense que cette rentrée rembourse, si elle en désigne une.
    static func expense(store: LocalStore, of id: String) throws -> Entry? {
        try store.database.query(
            """
            SELECT id, payee, amount, substr(occurred_at, 1, 10) AS day
            FROM transactions WHERE id = ? AND deleted_at IS NULL
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
            "AND (lower(normalized_payee) LIKE ? OR lower(COALESCE(memo,'')) LIKE ?)"
        }.joined(separator: " ")
        var values: [SQLiteValue] = [
            .real(-abs(income.amount)), .text(day), .text(day), .text(income.id),
        ]
        for word in words { values.append(.text(word)); values.append(.text(word)) }
        return try store.database.query(
            """
            SELECT id, payee, amount, substr(occurred_at, 1, 10) AS day
            FROM transactions
            WHERE deleted_at IS NULL AND amount <= ?
              AND transfer_pair_id IS NULL
              AND julianday(substr(occurred_at, 1, 10)) BETWEEN julianday(?) - 90
                                                            AND julianday(?) + 7
              AND id <> ?
              \(filter)
            ORDER BY occurred_at DESC
            LIMIT 40
            """,
            values
        ).compactMap(entry)
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
            day: Dates.iso.date(from: day) ?? .distantPast
        )
    }
}
