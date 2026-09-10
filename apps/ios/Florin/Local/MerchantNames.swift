import Combine
import Foundation

/// Les noms qu'on donne aux marchands.
///
/// La banque écrit « ACHAT CB SARL LE COMPTOIR 07.09.26 EUR 4,10 CARTE NO 123
/// OC », et le nettoyage en tire « SARL LE Comptoir » — le nom de la société qui
/// encaisse, pas celui du lieu. Tout le monde a de ces marchands qu'il
/// reconnaît sous un autre nom : la boulangerie d'en bas, le café « Chez Marco ».
///
/// Le nom donné ne remplace pas le libellé de la banque, il se pose dessus à
/// l'affichage. Le libellé brut reste tel quel en base parce que la
/// déduplication et le catégoriseur s'appuient dessus. Et parce que c'est
/// l'affichage qui change, un renommage vaut pour tout l'historique d'un coup,
/// comme pour chaque opération que la synchro apportera ensuite.
final class MerchantNames: ObservableObject {
    static let shared = MerchantNames()

    /// Change à chaque renommage : une vue qui l'observe se redessine.
    @Published private(set) var revision = 0

    private let lock = NSLock()
    private var loaded: [String: String]?

    // MARK: - La clé

    /*
     * Ce qui ne change pas d'une opération à l'autre du même marchand.
     *
     * Le nettoyage de l'affichage retire déjà le rail (« ACHAT CB ») et coupe
     * à la date, ce qui suffit pour une carte. Un prélèvement ou un virement
     * n'a pas de date dans son libellé, mais une référence qui change à chaque
     * fois : « DE TELECOM SA REF : 9876543210987654321012345 ». On coupe donc
     * aussi au premier mot de référence ou à la première longue suite de
     * chiffres, et on retire le « DE » qu'a laissé le rail.
     *
     *   ACHAT CB SARL LE COMPTOIR 07.09.26 EUR 4,10 CARTE NO 123 → sarl le comptoir
     *   PRELEVEMENT DE TELECOM SA REF : 9876543210…            → telecom sa
     *   VIREMENT INSTANTANE DE PAYPAL 12345678901234567 …      → paypal
     */
    static func key(_ payee: String) -> String {
        var words = PayeeText.clean(payee).split(separator: " ").map(String.init)

        var dropped = 0
        while dropped < 3, words.count > 1, let head = words.first,
              joiners.contains(fold(head)) {
            words.removeFirst()
            dropped += 1
        }

        if let cut = words.firstIndex(where: isReference), cut > 0 {
            words = Array(words[..<cut])
        }

        return fold(words.joined(separator: " "))
    }

    /// Ce qui reste du rail une fois le premier mot retiré.
    private static let joiners: Set<String> = ["instantane", "de", "du", "des", "d'"]

    /// Un mot qui porte une référence plutôt qu'un nom.
    private static func isReference(_ word: String) -> Bool {
        if ["ref", "ref:", ":", "ident", "mandat"].contains(fold(word)) { return true }
        return word.filter(\.isNumber).count >= 5
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    // MARK: - Lecture

    /// Le nom donné à ce marchand, s'il en a un.
    func name(for payee: String) -> String? {
        let key = Self.key(payee)
        guard !key.isEmpty else { return nil }
        return table()[key]
    }

    /// Le nom donné à une clé déjà calculée.
    func name(forKey key: String) -> String? {
        table()[key]
    }

    /// Tous les marchands renommés, par ordre alphabétique du nom donné.
    func all() -> [(key: String, name: String)] {
        table()
            .map { (key: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /*
     * Combien d'opérations portent ce marchand.
     *
     * La clé se calcule en Swift, pas en SQL, donc on la calcule une fois par
     * libellé distinct plutôt qu'une fois par ligne : trois mille opérations
     * tiennent en quelques centaines de libellés.
     */
    func usage(ofKey key: String) -> Int {
        guard let store = LocalStore.shared,
              let rows = try? store.database.query(
                  """
                  SELECT payee, count(*) AS n FROM transactions
                  WHERE deleted_at IS NULL GROUP BY payee
                  """
              ) else { return 0 }
        return rows.reduce(0) { total, row in
            guard let payee = row.string("payee"), Self.key(payee) == key else { return total }
            return total + (row.int("n") ?? 0)
        }
    }

    private func table() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        if let loaded { return loaded }
        let read = Self.read()
        loaded = read
        return read
    }

    private static func read() -> [String: String] {
        guard let store = LocalStore.shared,
              let rows = try? store.database.query(
                  "SELECT match_key, display_name FROM payee_aliases"
              ) else { return [:] }
        var names: [String: String] = [:]
        for row in rows {
            guard let key = row.string("match_key"), let name = row.string("display_name") else { continue }
            names[key] = name
        }
        return names
    }

    // MARK: - Écriture

    /// Donne un nom à un marchand. Un nom vide lui rend celui de la banque.
    func rename(key: String, to name: String) throws {
        guard let store = LocalStore.shared, !key.isEmpty else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try store.database.run("DELETE FROM payee_aliases WHERE match_key = ?", [.text(key)])
        } else {
            try store.database.run(
                """
                INSERT INTO payee_aliases (id, match_key, display_name) VALUES (?, ?, ?)
                ON CONFLICT(match_key) DO UPDATE SET
                    display_name = excluded.display_name,
                    updated_at = datetime('now')
                """,
                [.text(UUID().uuidString), .text(key), .text(trimmed)]
            )
        }
        invalidate()
    }

    /// Relit la table au prochain affichage, et le fait savoir.
    func invalidate() {
        lock.lock()
        loaded = nil
        lock.unlock()
        if Thread.isMainThread {
            revision += 1
        } else {
            DispatchQueue.main.async { self.revision += 1 }
        }
    }
}
