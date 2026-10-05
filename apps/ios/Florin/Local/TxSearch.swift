import Foundation

/*
 * Ce qu'un mot tapé veut dire.
 *
 * La page lit la base en SQL et l'échéancier tient en mémoire : deux chemins,
 * une seule idée de ce que « chercher » veut dire, sinon la même frappe donne
 * deux pages différentes selon qui a répondu.
 */
enum TxSearch {
    /// Les mots d'une recherche. Tous doivent se retrouver, l'ordre ne compte pas.
    static func tokens(_ query: String) -> [String] {
        query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /*
     * La fourchette de montants qu'un nombre tapé désigne.
     *
     * Avec des centimes, c'est le centime exact — « 8,50 » ne veut dire que
     * 8,50. Sans, c'est l'euro entier : on se souvient d'« environ huit
     * euros », pas de « huit euros zéro zéro », et exiger le second ne
     * trouverait presque jamais rien.
     *
     * Le signe est ignoré : le montant cherché est celui qu'on a payé.
     */
    static func amountRange(_ token: String) -> (low: Double, high: Double)? {
        let text = token
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "€", with: "")
        guard let value = Double(text), value >= 0, value < 1_000_000 else { return nil }
        guard let dot = text.firstIndex(of: "."), text.index(after: dot) != text.endIndex else {
            return (value, value + 1)
        }
        return (value - 0.005, value + 0.005)
    }

    /// Le même examen, sur ce qu'on a déjà en mémoire. Un nombre cherche un
    /// montant ou un mot entier, jamais un fragment — voir `LocalLedger`.
    static func matches(_ token: String, texts: [String?], amount: Double?) -> Bool {
        if let range = amountRange(token) {
            if let amount, abs(amount) >= range.low, abs(amount) < range.high { return true }
            return texts.contains { text in
                (text ?? "").lowercased().split(whereSeparator: \.isWhitespace).contains(token[...])
            }
        }
        return texts.contains { ($0 ?? "").lowercased().contains(token) }
    }
}
