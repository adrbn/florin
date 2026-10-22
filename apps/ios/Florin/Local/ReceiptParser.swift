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
 * est donc écrite pour se compléter sans rien casser — et elle n'est pas
 * seule : le ticket se vérifie par son arithmétique (voir `keeping`), et la
 * somme des articles est confrontée au montant de l'opération (voir
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
        // Italien — la caisse romaine imprime les mêmes lignes dans sa langue.
        "TOTALE", "TOTALE COMPLESSIVO", "TOTALE EURO", "SUBTOTALE", "IMPONIBILE",
        "IVA", "DI CUI IVA", "TOTALE IVA", "IMPORTO", "IMPORTO PAGATO",
        "PAGAMENTO", "PAGAMENTO ELETTRONICO", "CONTANTI", "RESTO", "BANCOMAT",
        "CARTA", "CARTA CREDITO", "CARTA DI CREDITO", "NON RISCOSSO",
        // Anglais.
        "SUBTOTAL", "SUB TOTAL", "TOTAL DUE", "AMOUNT DUE", "BALANCE DUE",
        "AMOUNT PAID", "PAID", "CASH", "CHANGE", "CARD", "CREDIT CARD",
        "DEBIT CARD", "TAX", "SALES TAX", "VAT", "CHANGE DUE",
        // Espagnol.
        "TOTAL A PAGAR", "IMPORTE", "EFECTIVO", "CAMBIO", "TARJETA",
    ]

    /// Le prix en fin de ligne, éventuellement précédé d'un signe et suivi du
    /// code de TVA que les caisses collent au montant (« 3,49 A », « 2.00 € »).
    ///
    /// L'espace autour de la virgule n'est pas une coquetterie : une caisse
    /// thermique espace ses caractères, et la reconnaissance rend « 6, 50 »
    /// aussi souvent que « 6,50 ». Sans cette tolérance la ligne n'a pas de
    /// prix du tout, et l'article qu'elle chiffrait disparaît.
    private static let price = try? NSRegularExpression(
        pattern: #"(-?\s?\d{1,6}\s?[.,]\s?\d{2})\s*(?:[A-Za-z€]{1,4})?\s*$"#
    )

    /*
     * Un ticket ne tient pas toujours sur une ligne par article.
     *
     * Une caisse italienne imprime le nom sur une ligne et « 10 % 6,50 » sur
     * la suivante ; un prix seul sous un nom seul est la même phrase coupée en
     * deux, et pris ligne par ligne les deux moitiés sont jetées — c'est ce
     * qui faisait lire d'un ticket de trois plats ses seules lignes de total.
     *
     * Le recollage ne regarde qu'une ligne en arrière : la dernière qui
     * portait un nom sans prix. Tout le reste — une ligne de total, un prix
     * déjà rattaché, une ligne de quantité « 2 X 4,80 » — l'efface, ce qui
     * interdit à un prix de se rattacher à un nom dont une autre ligne le
     * sépare.
     */
    static func items(from lines: [String], total: Double? = nil) -> [Item] {
        var items: [Item] = []
        var pending: String?
        for line in lines {
            switch read(line) {
            case let .purchase(item):
                items.append(item)
                pending = nil
            case let .priceAlone(amount):
                if let name = pending, !isNotAPurchase(name) {
                    items.append(Item(label: name, amount: amount))
                }
                pending = nil
            case let .nameAlone(name):
                pending = name
            case .quantity, .noise:
                // « 2 X 4,80 » dit le prix d'une pièce, pas celui de la ligne,
                // et « 10% » seul ne dit rien du tout : le nom reste en
                // attente du prix qui vient après. Une caisse italienne pose
                // le taux sur sa propre ligne, et ces lignes-là effaçaient le
                // plat dont elles annonçaient le prix.
                break
            case .summary:
                // Un récapitulatif chiffré, lui, clôt ce qui précède : le nom
                // resté sans prix n'en aura plus.
                pending = nil
            }
        }
        guard let total else { return items }
        return keeping(items, against: abs(total))
    }

    /// Un centime près : ces montants viennent d'une lecture de photo, pas
    /// d'un calcul.
    private static let cent = 0.005

    /*
     * Le récapitulatif reconnu par le calcul, dans une langue qu'on ignore.
     *
     * La liste de mots ne connaîtra jamais toutes les caisses du monde, mais
     * un ticket se vérifie lui-même : une ligne qui répète la somme des
     * lignes au-dessus d'elle, ou qui répète le montant débité, n'est pas un
     * article — aucun ticket ne vend deux fois ce qu'il vient de vendre.
     *
     * Ressembler à un récapitulatif ne suffit pas, sinon « pain 2,00 ; lait
     * 1,50 ; thé 3,50 » perdrait son thé. Il faut aussi que l'écart au
     * montant débité *y gagne* : c'est lui l'arbitre, il vient de la banque.
     * Quand la lecture est incomplète — la somme reste sous le débit —
     * écarter une ligne n'améliore rien, et tout est gardé.
     */
    private static func keeping(_ items: [Item], against total: Double) -> [Item] {
        var kept: [Item] = []
        var sum = 0.0
        for item in items {
            let repeats = abs(item.amount - sum) <= cent || abs(item.amount - total) <= cent
            let closer = abs(sum - total) < abs(sum + item.amount - total)
            if kept.count >= 2, repeats, closer { continue }
            kept.append(item)
            sum += item.amount
        }
        return kept
    }

    static func item(from rawLine: String) -> Item? {
        if case let .purchase(item) = read(rawLine) { return item }
        return nil
    }

    /// Ce qu'une ligne porte : les deux moitiés d'un achat, une seule, ou rien.
    enum Line: Equatable {
        case purchase(Item)
        case priceAlone(Double)
        case nameAlone(String)
        /// « 2 X 4,80 » : le prix d'une pièce, que la ligne suivante multiplie.
        case quantity
        /// Un total, une TVA, un moyen de paiement : chiffré, mais pas acheté.
        case summary
        /// Ni nom ni prix — un taux seul, une étoile, un trait de séparation.
        case noise
    }

    static func read(_ rawLine: String) -> Line {
        let line = rawLine
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !line.isEmpty, let price else { return .noise }
        let range = NSRange(line.startIndex..., in: line)
        guard let hit = price.firstMatch(in: line, range: range),
              let found = Range(hit.range(at: 1), in: line),
              let whole = Range(hit.range, in: line),
              let amount = number(String(line[found]))
        else { return name(of: line) }

        let head = String(line[line.startIndex..<whole.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        if head.range(of: #"^\d{1,3}\s*[xX*]$"#, options: .regularExpression) != nil {
            return .quantity
        }
        let label = clean(head)
        // Un nom d'une lettre n'apprend rien ; un prix que seul son taux de TVA
        // précède appartient au nom de la ligne du dessus.
        guard label.count >= 2, label.contains(where: \.isLetter) else {
            return .priceAlone(amount)
        }
        guard !isNotAPurchase(label) else { return .summary }
        return .purchase(Item(label: label, amount: amount))
    }

    private static func name(of line: String) -> Line {
        let label = clean(line)
        guard label.count >= 2, label.contains(where: \.isLetter) else { return .noise }
        return .nameAlone(label)
    }

    /// Le nom tel qu'on veut le relire : sans le code article que la caisse
    /// met en tête (« 008 RAVIOLI » ) ni le taux de TVA qu'elle colle en queue
    /// (« ACQUA 10% »). Un « 2 x Yaourt » garde son compte : trois chiffres au
    /// moins pour un code, et toujours suivi de son nom.
    private static func clean(_ raw: String) -> String {
        let junk = CharacterSet(charactersIn: " .·…:*xX")
        var label = raw.trimmingCharacters(in: junk)
        for pattern in [itemCode, vatRate] {
            guard let pattern else { continue }
            label = pattern.stringByReplacingMatches(
                in: label, range: NSRange(label.startIndex..., in: label), withTemplate: ""
            )
        }
        label = label.trimmingCharacters(in: junk)
        // Les caisses encadrent l'article de leurs propres lettres : le type de
        // ligne devant, la classe de TVA derrière. Une lettre seule n'est un
        // mot dans aucune des langues qu'un ticket écrit.
        var words = label.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        if words.count > 1, words[0].count == 1, words[0].first?.isLetter == true {
            words.removeFirst()
        }
        if words.count > 1, words.last?.count == 1, words.last?.first?.isLetter == true {
            words.removeLast()
        }
        return words.joined(separator: " ")
    }

    private static let itemCode = try? NSRegularExpression(pattern: #"^\d{3,5}\s+(?=\S*\p{L})"#)
    private static let vatRate = try? NSRegularExpression(pattern: #"\s*\d{1,2}([.,]\d{1,2})?\s*%$"#)

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

    /*
     * Ce qui annonce un récapitulatif, par sa tête de ligne.
     *
     * Le libellé entier ne suffit pas, et un vrai ticket le montre en trois
     * façons : la caisse ajoute sa précision (« TOTALE COMPLESSIVO »), elle
     * colle le moyen de paiement derrière deux points (« Pagamento
     * elettronico: VISA »), et la reconnaissance se trompe d'une lettre
     * (« TOTALE CONPLESSTVO »). Dans les trois cas la *tête* tient, et c'est
     * elle qu'on compare.
     *
     * Par mots entiers, jamais par caractères : « TOTALEMENT BIO » commence
     * par les lettres de « TOTAL » et reste un achat. Et seulement des têtes
     * sans ambiguïté — « CARTE » n'en est pas une, « CARTE POSTALE » s'achète,
     * donc elle reste dans la liste exacte au-dessus.
     */
    private static let summaryHeads: [String] = [
        "TOTAL", "SOUS TOTAL", "SOUSTOTAL", "NET A PAYER", "A PAYER", "MONTANT",
        "DONT", "RENDU", "NB ARTICLES", "NOMBRE ARTICLES",
        "TOTALE", "SUBTOTALE", "PARZIALE", "T PARZIALE", "IMPORTO", "PAGAMENTO",
        "DI CUI", "HAI RISPARMIATO", "RESTO", "CONTANTI", "NON RISCOSSO",
        "SUBTOTAL", "SUB TOTAL", "AMOUNT", "BALANCE", "CHANGE", "YOU SAVED",
        "IMPORTE", "EFECTIVO", "CAMBIO",
    ]

    private static func isNotAPurchase(_ label: String) -> Bool {
        let folded = fold(label)
        if folded.isEmpty { return true }
        if notPurchases.contains(folded) { return true }
        return summaryHeads.contains { folded == $0 || folded.hasPrefix($0 + " ") }
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
