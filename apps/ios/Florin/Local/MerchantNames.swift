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
        fold(merchantWords(payee))
    }

    /*
     * Nommer un abonnement, pas le rail qui l'encaisse.
     *
     * Un intermédiaire de paiement encaisse pour quelqu'un d'autre : le
     * relevé ne porte que son nom à lui. Sur des dizaines de prélèvements d'un
     * même intermédiaire, un seul montant est l'abonnement qu'on veut nommer :
     * renommer le marchand mentirait sur tous les autres, et un nom faux ne
     * se voit pas alors qu'un nom manquant se voit.
     *
     * Un abonnement porte donc sa propre clé : le marchand ET le montant au
     * centime. Le signe la rend étrangère aux clés de marchand — aucun
     * libellé nettoyé ne commence par « § » — y compris à la règle de
     * troncature de `resolve`, qui ne compare que des préfixes.
     *
     * Ce qu'on y perd, et qui se voit : un abonnement dont le prix change
     * reprend le nom de son marchand, le temps qu'on le renomme.
     */
    static let seriesSign = "§"

    static func seriesKey(_ payee: String, amount: Double) -> String {
        "\(seriesSign)\(cents(amount)) \(key(payee))"
    }

    /// Le marchand et le montant que porte une clé de série, si c'en est une.
    static func series(of key: String) -> (merchant: String, cents: Int)? {
        guard key.hasPrefix(seriesSign) else { return nil }
        let rest = key.dropFirst()
        guard let space = rest.firstIndex(of: " "),
              let cents = Int(rest[..<space]), !rest[rest.index(after: space)...].isEmpty
        else { return nil }
        return (String(rest[rest.index(after: space)...]), cents)
    }

    static func cents(_ amount: Double) -> Int { Int((abs(amount) * 100).rounded()) }

    /// The same trimming, with the bank's own casing left on: what `key` is
    /// computed from, and what a screen shows when no name has been given.
    static func merchantWords(_ payee: String) -> String {
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

        words = withoutPaperwork(words)

        var trimmed = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        while let last = trimmed.last, " ,;-".contains(last) { trimmed.removeLast() }
        return trimmed.isEmpty ? PayeeText.clean(payee) : trimmed
    }

    /*
     * Ce que l'immatriculation ajoute au nom, et qui n'est pas le nom.
     *
     * Une fois le rail retiré et la référence coupée, il reste ce que le
     * marchand a déclaré au registre du commerce : « Le Comptoir S.a, l. et
     * Cie S.c.a, », « Télécom SA », « Loueur SRL ». Personne ne dit ça. Et la
     * caisse ajoute souvent son propre numéro — « Supermarché 1357 » — ou le
     * masque de la carte collé au nom — « Cartepay**4321* ».
     *
     * Trois coupes, et seulement trois, chacune bornée parce qu'un nom perdu
     * ne se voit pas alors qu'un nom bizarre se voit :
     *
     *   - la forme juridique, jamais en tête (un marchand peut s'appeler « SA »)
     *   - l'initiale ponctuée, pas avant le troisième mot : « Le Comptoir
     *     Grenier S, » est de la paperasse, « Paypartage A, Jeanne D » est un
     *     bénéficiaire
     *   - le numéro de caisse à trois chiffres ou plus, sauf une année, parce
     *     que « Le Comptoir 1971 » et « Cotisation Février 2026 » disent
     *     quelque chose
     *
     * Un nombre d'un ou deux chiffres reste : « Le Comptoir 87 » est peut-être
     * le nom de l'enseigne, et on n'a aucun moyen de le savoir.
     */
    private static func withoutPaperwork(_ words: [String]) -> [String] {
        var words = words
        for (index, word) in words.enumerated() {
            if index > 0, legalForms.contains(fold(word.filter { !punctuation.contains($0) })) {
                words = Array(words[..<index])
                break
            }
            if index >= 2, word.range(of: #"^[A-Za-z]{1,2}[.,;]+$"#, options: .regularExpression) != nil {
                words = Array(words[..<index])
                break
            }
        }
        while words.count > 1, let last = words.last, isStoreCode(last) {
            words.removeLast()
        }
        if let last = words.last,
           let mask = last.range(of: #"\*+[\d*]*$"#, options: .regularExpression),
           mask.lowerBound != last.startIndex {
            words[words.count - 1] = String(last[..<mask.lowerBound])
        }
        return words
    }

    /// La forme juridique telle qu'elle s'écrit une fois la ponctuation ôtée :
    /// « S.a, », « S.r.l. » et « Srl » se lisent tous pareil.
    private static let legalForms: Set<String> = [
        "sa", "sarl", "sas", "srl", "spa", "sca", "sc", "bv", "nv",
        "gmbh", "ltd", "llc", "inc", "plc", "ag", "cie", "kg",
    ]

    /// « S.a, » et « Srl » doivent se lire pareil : la ponctuation part du
    /// mot entier, pas seulement de ses bords.
    private static let punctuation: Set<Character> = [".", ",", ";", "(", ")"]

    /// Le numéro que la caisse ajoute — mais pas une année, qui fait partie
    /// du nom (« Le Comptoir 1971 ») ou le date (« Cotisation Février 2026 »).
    private static func isStoreCode(_ word: String) -> Bool {
        guard word.count >= 3, word.allSatisfy(\.isNumber) else { return false }
        if word.count == 4, let year = Int(word), (1900...2100).contains(year) { return false }
        return true
    }

    /// Ce qui reste du rail une fois le premier mot retiré.
    private static let joiners: Set<String> = ["instantane", "de", "du", "des", "d'"]

    /// Un mot qui porte une référence plutôt qu'un nom.
    private static func isReference(_ word: String) -> Bool {
        // Le deux-points seul ne survit pas au repli, qui ôte la ponctuation.
        if word == ":" { return true }
        if ["ref", "ident", "mandat"].contains(fold(word)) { return true }
        return word.filter(\.isNumber).count >= 5
    }

    /*
     * Deux caisses qui ponctuent différemment ne font pas deux marchands.
     *
     * Le relevé écrit « PAS COMMERCIA », Wallet transmet « P.a.s. Commerciale
     * Ita » : même boutique, mais les points faisaient deux clés étrangères
     * l'une à l'autre, hors de portée même de la règle de troncature, qui ne
     * compare que des préfixes. Le marchand renommé une fois sous le libellé
     * de la banque redevenait anonyme sous celui d'Apple Pay.
     *
     * La ponctuation part donc de la clé, comme elle partait déjà du mot
     * quand il fallait reconnaître « S.a, » et « Srl ». Elle reste intacte à
     * l'affichage, qui passe par `merchantWords`.
     */
    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { !punctuation.contains($0) }
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    // MARK: - Lecture

    /// Le nom donné à ce marchand, s'il en a un.
    func name(for payee: String) -> String? {
        name(forKey: Self.key(payee))
    }

    /// Le nom donné à une clé déjà calculée.
    func name(forKey key: String) -> String? {
        Self.resolve(key, in: table())
    }

    /*
     * La banque tronque le commerçant, Apple Pay non.
     *
     * Le relevé ne garde que les premiers caractères du nom — « SumUp *LE
     * COMPTO » — là où Wallet transmet « SumUp *LE COMPTOIR SARL ». Une boutique,
     * deux libellés, donc deux clés : il fallait la renommer deux fois, et
     * l'oubli laissait la moitié de son historique sous le nom du terminal
     * de paiement.
     *
     * Une clé qui est le préfixe exact d'une autre est précisément ce que
     * produit une troncature. Le plancher évite qu'un mot court fasse
     * autorité sur tout ce qui commence pareil, et la clé exacte l'emporte
     * toujours : nommer « Chez Rosa » ne renomme pas « Chez Rosa Traiteur »
     * si celui-ci porte déjà son propre nom. À égalité, la clé la plus
     * longue gagne — c'est la plus précise.
     */
    static let truncationFloor = 8

    static func resolve(_ key: String, in table: [String: String]) -> String? {
        guard !key.isEmpty else { return nil }
        if let exact = table[key] { return exact }

        /*
         * Saisir le nom qu'on lit est une façon de dire « c'est lui ».
         *
         * Le relevé porte « ACHAT CB ONE*boutique c 07.10.26 USD … » ; la
         * boutique a été renommée une fois, et c'est ce nom-là qu'on voit
         * partout. Le même achat saisi à la main se tape donc sous ce nom —
         * et produisait un parfait inconnu : deux clés sans une lettre en
         * commun, deux têtes, deux marchands dans l'analyse.
         *
         * C'est déjà la règle qui relie deux libellés nommés pareil (voir
         * `keysSharing(nameOf:)`) ; elle ne s'appliquait pas au libellé qui
         * EST le nom, faute d'avoir un nom à lui. Le plus petit nom l'emporte
         * à égalité de pli, pour que la réponse ne dépende pas de l'ordre du
         * dictionnaire.
         */
        if let given = table.values.filter({ fold($0) == key }).min() { return given }

        guard key.count >= truncationFloor else { return nil }
        var best: (key: String, name: String)?
        for (other, name) in table where other.count >= truncationFloor {
            guard other.hasPrefix(key) || key.hasPrefix(other) else { continue }
            if best == nil || other.count > best!.key.count { best = (other, name) }
        }
        return best?.name
    }

    /// Deux libellés qui désignent le même marchand — la même règle que
    /// `resolve`, pour compter les opérations qu'un renommage atteindra.
    static func sameMerchant(_ a: String, _ b: String) -> Bool {
        if a == b { return !a.isEmpty }
        guard a.count >= truncationFloor, b.count >= truncationFloor else { return false }
        return a.hasPrefix(b) || b.hasPrefix(a)
    }

    /// Tous les marchands renommés, par ordre alphabétique du nom donné.
    func all() -> [(key: String, name: String)] {
        table()
            .map { (key: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /*
     * Combien d'opérations ce nom atteindra.
     *
     * La clé se calcule en Swift, pas en SQL, donc on la calcule une fois par
     * libellé distinct plutôt qu'une fois par ligne : trois mille opérations
     * tiennent en quelques centaines de libellés. Une clé de série ajoute le
     * montant au regroupement, et ne compte que les opérations de ce
     * montant-là.
     */
    func usage(ofKey key: String) -> Int {
        let series = Self.series(of: key)
        let merchant = series?.merchant ?? key
        guard let store = LocalStore.shared,
              let rows = try? store.database.query(
                  """
                  SELECT payee, amount, count(*) AS n FROM transactions
                  WHERE deleted_at IS NULL GROUP BY payee, amount
                  """
              ) else { return 0 }
        return rows.reduce(0) { total, row in
            guard let payee = row.string("payee"),
                  Self.sameMerchant(Self.key(payee), merchant) else { return total }
            if let cents = series?.cents, cents != Self.cents(row.double("amount") ?? 0) {
                return total
            }
            return total + (row.int("n") ?? 0)
        }
    }

    /*
     * Les autres libellés que leur propriétaire a nommés pareil.
     *
     * Une boutique encaisse sous sa raison sociale, et on la saisit à la main
     * sous le nom qu'on lui donne : deux libellés qui n'ont pas une lettre en
     * commun, donc deux clés étrangères l'une à l'autre. Rien dans les données
     * ne les rapproche — sauf le nom qu'on leur a donné à toutes les deux, qui
     * est précisément la façon dont on dit « c'est le même ».
     *
     * Ce lien ne vaut que par le nom : il se défait en renommant, et il ne
     * déborde pas sur la catégorie ni sur le rapprochement des doublons, qui
     * ne se décident pas sur un nom d'affichage.
     */
    func keysSharingName(with key: String) -> [String] {
        Self.keysSharing(nameOf: key, in: table())
    }

    /// Le nom se résout comme partout ailleurs — une clé tronquée porte le
    /// nom de sa voisine — sinon le libellé que la banque a coupé n'aurait
    /// pas de nom, donc pas de jumeau, donc pas de tête.
    static func keysSharing(nameOf key: String, in names: [String: String]) -> [String] {
        guard let name = resolve(key, in: names).map(fold), !name.isEmpty else { return [] }
        return names.compactMap { other, given in
            other != key && fold(given) == name ? other : nil
        }
    }

    /*
     * Les noms déjà donnés à des libellés voisins.
     *
     * Un même commerçant arrive sous deux libellés que rien ne rapproche — la
     * raison sociale au terminal de paiement, l'enseigne sur Apple Pay, le nom
     * qu'on tape à la main. Renommé une fois, il reste anonyme sous les
     * autres, et c'est en tapant son nom qu'on a le plus besoin de savoir
     * qu'il en a déjà un : le reprendre au caractère près est précisément ce
     * qui réunit les deux (voir `keysSharing(nameOf:)`), là où une majuscule
     * de travers fabrique un second marchand.
     *
     * Voisin veut dire : les deux portent un même mot, dans la clé ou dans le
     * nom donné. Quatre lettres au moins, sinon « sas » et « paris »
     * rapprocheraient la moitié du relevé.
     */
    static let neighbourWord = 4

    func neighbours(of key: String) -> [String] {
        Self.neighbours(of: key, in: table())
    }

    static func neighbours(
        of key: String, in table: [String: String], limit: Int = 5
    ) -> [String] {
        let mine = words(of: series(of: key)?.merchant ?? key)
        guard !mine.isEmpty else { return [] }
        // Le nom en place n'est pas une proposition : il est déjà dans le champ.
        let current = resolve(key, in: table).map(fold)
        var scored: [(name: String, shared: Int)] = []
        for (other, name) in table where other != key && !other.hasPrefix(seriesSign) {
            guard fold(name) != current else { continue }
            let shared = mine.intersection(words(of: other).union(words(of: name))).count
            guard shared > 0 else { continue }
            scored.append((name, shared))
        }
        var seen = Set<String>()
        return scored
            .sorted {
                $0.shared != $1.shared
                    ? $0.shared > $1.shared
                    : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            .compactMap { seen.insert(fold($0.name)).inserted ? $0.name : nil }
            .prefix(limit)
            .map { $0 }
    }

    /// Les mots d'un libellé qui peuvent désigner un marchand : repliés, et
    /// assez longs pour vouloir dire quelque chose.
    private static func words(of text: String) -> Set<String> {
        Set(fold(text).split(separator: " ").map(String.init))
            .filter { $0.count >= neighbourWord }
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
