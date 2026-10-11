import Foundation

/*
 * La confirmation d'un ordre, lue sur une capture d'écran.
 *
 * Un achat de titres demande trois chiffres, et le courtier les affiche tous
 * les trois sur un seul écran — après quoi ils deviennent remarquablement
 * difficiles à retrouver : l'historique d'un ordre exécuté est enterré sous
 * plusieurs niveaux, quand il est consultable. La capture faite au moment de
 * l'achat, elle, est dans la pellicule.
 *
 * La lecture ne suppose aucune mise en page : elle cherche, ligne par ligne,
 * un mot connu suivi d'un nombre. Les mots des trois langues dans lesquelles
 * ces applications s'affichent, parce qu'un courtier allemand traduit mal et
 * tard. Ce qui n'est pas reconnu n'est pas deviné — le champ reste vide et
 * se tape à la main, ce qui est exactement la situation d'avant.
 */
enum OrderSlip {
    struct Order: Equatable {
        var quantity: Double?
        var unitPrice: Double?
        var total: Double?

        var isEmpty: Bool { quantity == nil && unitPrice == nil && total == nil }
    }

    /// Le nombre en fin de ligne, avec autant de décimales qu'il en porte :
    /// un montant en a deux, une quantité fractionnée beaucoup plus.
    private static let trailing = try? NSRegularExpression(
        pattern: #"(-?\d[\d  .]*[.,]\d+)\s*(?:€|EUR)?\s*$"#
    )

    /// Les frais ne sont pas le total, et le total n'est pas le cours. L'ordre
    /// compte : « montant total » porte les deux mots, et c'est un total.
    private static let ignored = ["FRAIS", "COMMISSION", "GEBUHR", "FEE", "TAXE"]
    private static let totals = ["TOTAL", "MONTANT", "INVESTI", "GESAMT", "BETRAG", "SOMME"]
    private static let prices = ["PRIX", "COURS", "PRICE", "KURS", "ANTEILSPREIS"]
    private static let quantities = ["QUANTIT", "PARTS", "TITRES", "NOMBRE", "SHARES", "ANZAHL", "STUCK", "STÜCK"]

    static func read(_ lines: [String]) -> Order {
        var order = Order()
        for line in lines {
            guard let (label, value) = trailingNumber(in: line) else { continue }
            let folded = fold(label)
            guard !folded.isEmpty, !ignored.contains(where: folded.contains) else { continue }

            if totals.contains(where: folded.contains) {
                order.total = order.total ?? value
            } else if prices.contains(where: folded.contains) {
                order.unitPrice = order.unitPrice ?? value
            } else if quantities.contains(where: folded.contains) {
                order.quantity = order.quantity ?? value
            }
        }
        return order
    }

    private static func trailingNumber(in rawLine: String) -> (String, Double)? {
        let line = rawLine
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !line.isEmpty, let trailing else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let hit = trailing.firstMatch(in: line, range: range),
              let found = Range(hit.range(at: 1), in: line),
              let whole = Range(hit.range, in: line),
              let value = ReceiptParser.number(String(line[found]))
        else { return nil }
        return (String(line[line.startIndex..<whole.lowerBound]), value)
    }

    private static func fold(_ label: String) -> String {
        label.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .uppercased()
    }
}
