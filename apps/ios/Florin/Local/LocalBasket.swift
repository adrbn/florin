import Foundation

/*
 * Le panier : ce qu'il y a DANS les dépenses, pas seulement combien.
 *
 * Une catégorie dit « Alimentation, 412 € ». Un ticket de caisse dit du
 * poulet, deux yaourts et une lessive. Les lignes sont déjà là — découpées
 * par `ReceiptParser`, nommées par `ProductNames` — et personne ne les
 * additionnait : elles ne servaient qu'à relire un ticket une fois.
 *
 * Trois questions, et rien d'autre :
 *  - ce qui pèse, par famille de produit, parce qu'une famille s'additionne
 *    et qu'un mot libre ne s'additionne pas ;
 *  - ce qui a changé de prix, pour les produits achetés plus d'une fois ;
 *  - ce qui revient, par nombre d'achats.
 *
 * Et une quatrième, qui n'est pas une analyse mais une honnêteté : quelle
 * PART des dépenses ces tickets expliquent. Deux tickets par mois sur
 * cinquante opérations, c'est 8 % du mois — un écran qui ne le dit pas
 * laisserait croire que le panier EST le budget.
 *
 * Le rapprochement libellé → produit se fait ici, en Swift, avec la même
 * `ProductNames.key` que l'écriture : un repliage d'accents en SQL et un
 * autre en Swift finiraient par ne plus se rencontrer. Quelques centaines de
 * lignes de ticket, c'est une passe de rien.
 */
enum LocalBasket {
    struct Family: Identifiable, Sendable {
        let name: String
        let total: Double
        let count: Int
        var id: String { name }
    }

    struct Product: Identifiable, Sendable {
        let name: String
        let family: String?
        /// Le nombre de LIGNES, soit le nombre de fois où il est passé en
        /// caisse — deux pots sur un même ticket sont deux achats.
        let count: Int
        let total: Double
        let first: Double
        let last: Double
        let firstDay: String
        let lastDay: String
        /// Le nombre de jours différents où il a été acheté : c'est lui qui
        /// autorise à parler de prix « dans le temps ».
        let days: Int
        var id: String { name }
        var change: Double { first > 0.005 ? (last - first) / first : 0 }
    }

    struct Data: Sendable {
        let items: Int
        let receipts: Int
        /// La somme des lignes de ticket.
        let detailed: Double
        /// Ce qui est sorti sur la même période, tout compris.
        let spent: Double
        let families: [Family]
        /// Tous les produits, du plus cher au moins cher.
        let products: [Product]
        /// Ceux dont le prix a bougé, de la plus forte hausse à la plus forte
        /// baisse.
        let movers: [Product]
        /// Les mots de catégorie qui n'ont pas encore de famille.
        let unsortedWords: Int

        var coverage: Double { spent > 0.005 ? detailed / spent : 0 }
        var isEmpty: Bool { items == 0 }
    }

    /// Douze mois : la même fenêtre que les tendances au-dessus, et assez
    /// pour qu'un prix ait eu le temps de bouger.
    static let months = 12

    static func data(store: LocalStore) throws -> Data {
        let db = store.database
        let since = (LocalAnalysis.recentMonths(months).first ?? "2000-01") + "-01"

        let lines = try db.query(
            """
            SELECT i.label AS label, i.amount AS amount, i.receipt_id AS receipt,
                   substr(t.occurred_at, 1, 10) AS day
            FROM receipt_items i
            JOIN transactions t ON t.id = i.transaction_id
            WHERE t.deleted_at IS NULL AND substr(t.occurred_at, 1, 10) >= ?
            ORDER BY substr(t.occurred_at, 1, 10), i.line_no
            """,
            [.text(since)]
        )
        // Le même prédicat que les parts par catégorie : « dépensé » veut dire
        // la même chose d'un onglet à l'autre, sinon la part est fausse.
        let spent = try db.scalar(
            """
            SELECT coalesce(-sum(t.amount), 0) FROM transactions t
            JOIN accounts a ON a.id = t.account_id
            JOIN categories c ON c.id = t.category_id
            JOIN category_groups g ON g.id = c.group_id
            WHERE t.deleted_at IS NULL AND substr(t.occurred_at, 1, 10) <= date('now')
              AND t.transfer_pair_id IS NULL AND a.is_archived = 0
              AND g.kind = 'expense' AND substr(t.occurred_at, 1, 10) >= ?
            """,
            [.text(since)]
        )?.double ?? 0

        let names = try ProductNames.known(
            store: store, labels: lines.compactMap { $0.string("label") }
        )

        var byProduct: [String: (family: String?, amounts: [(day: String, amount: Double)])] = [:]
        var byFamily: [String: (total: Double, count: Int)] = [:]
        var receipts = Set<String>()
        var detailed = 0.0
        var items = 0

        for row in lines {
            guard let label = row.string("label"), let amount = row.double("amount"),
                  let day = row.string("day")
            else { continue }
            let reading = names[ProductNames.key(label)]
            // Sans lecture, le libellé de caisse fait l'affaire : l'écran se
            // remplit avant que le modèle soit passé, il est juste moins beau.
            let name = reading?.name ?? label
            let family = reading?.family
            items += 1
            detailed += amount
            if let receipt = row.string("receipt") { receipts.insert(receipt) }

            var entry = byProduct[name] ?? (family, [])
            // Une famille connue ne se perd pas parce qu'une ligne plus
            // ancienne du même produit n'en avait pas encore.
            entry.family = entry.family ?? family
            entry.amounts.append((day, amount))
            byProduct[name] = entry

            let key = family ?? unsortedFamily
            let bucket = byFamily[key] ?? (0, 0)
            byFamily[key] = (bucket.total + amount, bucket.count + 1)
        }

        let products = byProduct.map { name, entry -> Product in
            let sorted = entry.amounts.sorted { $0.day < $1.day }
            return Product(
                name: name,
                family: entry.family,
                count: sorted.count,
                total: round2(sorted.reduce(0) { $0 + $1.amount }),
                first: round2(sorted.first?.amount ?? 0),
                last: round2(sorted.last?.amount ?? 0),
                firstDay: sorted.first?.day ?? "",
                lastDay: sorted.last?.day ?? "",
                days: Set(sorted.map(\.day)).count
            )
        }

        /*
         * Un prix qui a bougé, et pas un panier qui a changé de taille.
         *
         * Deux achats le MÊME jour sont deux unités, pas une évolution : il
         * faut deux jours différents. Et sous 5 % d'écart il n'y a rien à
         * lire — une ligne de caisse porte parfois un poids, donc le prix
         * d'un fromage à la coupe n'est pas tout à fait le même d'une fois
         * sur l'autre sans que personne ne l'ait augmenté.
         */
        let movers = products
            .filter { $0.days >= 2 && abs($0.change) >= 0.05 }
            .sorted { $0.change > $1.change }

        return Data(
            items: items,
            receipts: receipts.count,
            detailed: round2(detailed),
            spent: round2(spent),
            families: byFamily
                .map { Family(name: $0.key, total: round2($0.value.total), count: $0.value.count) }
                .sorted { $0.total > $1.total },
            products: products.sorted { $0.total > $1.total },
            movers: movers,
            unsortedWords: ProductNames.unsorted(store: store).count
        )
    }

    /// La clé des articles dont la famille n'est pas encore connue — un nom de
    /// famille réservé, pas une famille.
    static let unsortedFamily = "__none__"

    private static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}
