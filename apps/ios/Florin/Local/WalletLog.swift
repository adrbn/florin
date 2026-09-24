import Foundation

/*
 * Ce que l'automatisation a tenté, qu'elle ait abouti ou non.
 *
 * L'action tourne app fermée, sans rien à l'écran : quand elle cesse de
 * fonctionner, l'ardoise reste simplement muette, et il ne reste plus qu'à
 * deviner. Deviner a coûté une soirée. Une ligne est donc écrite dès l'entrée
 * de l'action — avant toute validation, avant la base du grand livre — puis
 * close par son issue. Le montant et le marchand y sont conservés **tels que
 * Wallet les a donnés**, car c'est précisément ce qu'on ne voit jamais.
 *
 * Et l'absence de ligne dit quelque chose, elle aussi : si un paiement passe
 * sans qu'aucune tentative n'apparaisse, l'action n'a pas été lancée du tout —
 * la panne est alors du côté d'iOS, pas de Florin.
 */
enum WalletLog {
    /// Ce qu'on garde : de quoi couvrir plusieurs jours de paiements sans
    /// laisser la table grossir indéfiniment.
    static let keep = 60

    enum Outcome: String {
        /// Ouverte à l'entrée de l'action : si elle le reste, le processus a
        /// été tué avant la fin.
        case started
        case recorded
        case failed
    }

    struct Attempt: Identifiable {
        let id: String
        let startedAt: Date?
        let amountText: String
        let merchant: String
        let outcome: Outcome
        let detail: String?
    }

    /// Ouvre une tentative. Ne jette jamais : un journal qui empêche
    /// d'enregistrer un paiement serait pire que pas de journal.
    @discardableResult
    static func begin(store: LocalStore, amountText: String, merchant: String, card: String?) -> String {
        let id = UUID().uuidString
        try? store.database.run(
            """
            INSERT INTO wallet_attempts (id, started_at, amount_text, merchant, card, outcome)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            [
                .text(id), .text(stamp()), .text(amountText), .text(merchant),
                card.map { .text($0) } ?? .null, .text(Outcome.started.rawValue),
            ]
        )
        prune(store: store)
        return id
    }

    static func finish(store: LocalStore, id: String, outcome: Outcome, detail: String? = nil) {
        try? store.database.run(
            "UPDATE wallet_attempts SET outcome = ?, detail = ? WHERE id = ?",
            [.text(outcome.rawValue), detail.map { .text($0) } ?? .null, .text(id)]
        )
    }

    static func recent(store: LocalStore, limit: Int = 10) -> [Attempt] {
        let rows = (try? store.database.query(
            """
            SELECT id, started_at, amount_text, merchant, outcome, detail
            FROM wallet_attempts ORDER BY started_at DESC LIMIT \(max(1, limit))
            """
        )) ?? []
        return rows.compactMap { row in
            guard let id = row.string("id") else { return nil }
            return Attempt(
                id: id,
                startedAt: row.string("started_at").flatMap(date(from:)),
                amountText: row.string("amount_text") ?? "",
                merchant: row.string("merchant") ?? "",
                outcome: Outcome(rawValue: row.string("outcome") ?? "") ?? .started,
                detail: row.string("detail")
            )
        }
    }

    // MARK: - Heures

    /// L'heure locale, écrite comme le reste de la base la lit.
    private static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = .current
        return f.string(from: Date())
    }

    private static func date(from text: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = .current
        return f.date(from: text)
    }

    private static func prune(store: LocalStore) {
        try? store.database.run(
            """
            DELETE FROM wallet_attempts WHERE id NOT IN (
                SELECT id FROM wallet_attempts ORDER BY started_at DESC LIMIT \(keep)
            )
            """
        )
    }
}
