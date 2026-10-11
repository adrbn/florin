import Foundation

/*
 * Ce qu'un ticket de caisse dit, ligne par ligne.
 *
 * « 39 € chez Le Comptoir » est ce que la banque sait, et c'est tout ce que
 * le grand livre savait. Le ticket, lui, porte le détail — et c'est le détail
 * qu'on cherche six mois plus tard : pas « 39 € de courses » mais « le vin à
 * 8,90 ». Reconnaître le texte est la partie qu'Apple fait ; décider quelles
 * lignes sont des achats est celle qui reste.
 *
 * Le découpage ne demande rien d'intelligent. Un article est une ligne qui
 * finit par un prix, et le reste de la ligne est son nom. Ce qui demande du
 * soin, c'est tout ce qui finit par un prix *sans* être un achat : le total,
 * la TVA, le rendu de monnaie, le moyen de paiement. Ceux-là doublent la
 * facture si on les laisse passer.
 *
 * La liste des mots à écarter est forcément incomplète : chaque enseigne
 * imprime ses tickets comme elle l'entend, et il n'existe pas de norme. Elle
 * est donc écrite pour se compléter sans rien casser — et surtout, la somme
 * des articles est confrontée au montant de l'opération (voir
 * `LocalReceipts.unexplained`), qui lui est sûr. C'est cet écart, et non une
 * confiance dans cette liste, qui dit si la lecture a réussi.
 */
enum ReceiptParser {
    struct Item: Equatable {
        let label: String
        let amount: Double
    }

    /*
     * Ni un achat ni un prix : ce qui termine quand même par un nombre.
     *
     * Comparé au nom de la ligne *une fois* ses chiffres de queue retirés —
     * « TVA 20% » devient « TVA » — et comparé en entier, jamais par
     * inclusion : « CARTE » écarterait « CARTE POSTALE », qui est un achat.
     */
    private static let notPurchases: Set<String> = [
        "TOTAL", "TOTAL EUR", "TOTAL TTC", "TOTAL HT", "SOUS TOTAL", "SOUSTOTAL",
        "TOTAL ARTICLES", "NB ARTICLES", "ARTICLES", "NOMBRE ARTICLES",
        "NET A PAYER", "A PAYER", "MONTANT", "MONTANT DU", "SOMME", "SOMME DUE",
        "CB", "CARTE", "CARTE BANCAIRE", "CB EMV", "SANS CONTACT", "ESPECE",
        "ESPECES", "CHEQUE", "TICKET RESTAURANT", "TITRE RESTAURANT",
        "RENDU", "RENDU MONNAIE", "MONNAIE", "RECU", "VERSE",
        "TVA", "DONT TVA", "TOTAL TVA", "HT", "TTC", "TAUX",
        "ARRONDI", "SOLDE", "POINTS", "FIDELITE", "CUMUL", "ECO PART",
        "SIRET", "TEL", "CAISSE", "VENDEUR", "DATE", "HEURE", "EUR",
    ]

    /// Le prix en fin de ligne, éventuellement précédé d'un signe et suivi du
    /// code de TVA que les caisses collent au montant (« 3,49 A », « 2.00 € »).
    private static let price = try? NSRegularExpression(
        pattern: #"(-?\s?\d{1,6}[.,]\d{2})\s*(?:[A-Za-z€]{1,4})?\s*$"#
    )

    static func items(from lines: [String]) -> [Item] {
        lines.compactMap(item(from:))
    }

    static func item(from rawLine: String) -> Item? {
        let line = rawLine
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !line.isEmpty, let price else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let hit = price.firstMatch(in: line, range: range),
              let found = Range(hit.range(at: 1), in: line),
              let whole = Range(hit.range, in: line)
        else { return nil }

        let amount = number(String(line[found]))
        guard let amount else { return nil }

        let label = String(line[line.startIndex..<whole.lowerBound])
            .trimmingCharacters(in: CharacterSet(charactersIn: " .·…:*xX"))
        // Un prix tout seul n'apprend rien, et un nom d'une lettre non plus.
        guard label.count >= 2, label.contains(where: \.isLetter) else { return nil }
        guard !isNotAPurchase(label) else { return nil }
        return Item(label: label, amount: amount)
    }

    /// Majuscules sans accent, et sans les chiffres ni les symboles de queue —
    /// c'est sous cette forme que la liste ci-dessus est écrite.
    static func fold(_ label: String) -> String {
        let bare = label
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .uppercased()
        let kept = bare.map { $0.isLetter || $0.isNumber || $0 == " " ? $0 : " " }
        let trimmed = String(kept)
            .split(whereSeparator: \.isWhitespace)
            .filter { $0.contains(where: \.isLetter) }
            .joined(separator: " ")
        return trimmed
    }

    private static func isNotAPurchase(_ label: String) -> Bool {
        let folded = fold(label)
        if folded.isEmpty { return true }
        // « DONT TVA », « DONT ECO-PART » : une ventilation du total, pas un achat.
        if folded.hasPrefix("DONT ") { return true }
        return notPurchases.contains(folded)
    }

    /// « 1 234,56 », « 1.234,56 », « -3.49 » : le séparateur décimal est le
    /// dernier des deux, et tout ce qui le précède ne sépare que des milliers.
    static func number(_ text: String) -> Double? {
        let compact = text.replacingOccurrences(of: " ", with: "")
        guard let cut = compact.lastIndex(where: { $0 == "," || $0 == "." }) else {
            return Double(compact)
        }
        let whole = compact[compact.startIndex..<cut].filter { $0.isNumber || $0 == "-" }
        let cents = compact[compact.index(after: cut)...].filter(\.isNumber)
        return Double("\(whole).\(cents)")
    }
}
