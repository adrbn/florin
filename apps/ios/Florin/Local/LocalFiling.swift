import Foundation

/*
 * Classer un marchand, pas une opération.
 *
 * Un grand livre de trois mille lignes ne se classe pas à la main, et il n'a
 * pas à l'être : il tient en trois cent cinquante marchands, dont les trente
 * premiers portent les deux tiers des lignes. La décision « la boulangerie
 * du coin, c'est un repas » est la même mille fois ; la prendre mille fois
 * est le défaut, pas la quantité de travail.
 *
 * Le regroupement passe par `MerchantNames.key`, la clé qui sert déjà partout
 * ailleurs — au nom affiché, au logo, à la carte. Une clé propre à cet écran
 * rangerait sous deux entrées ce que le reste de l'app montre comme un seul
 * marchand, et le classement ne tiendrait plus.
 */
enum LocalFiling {
    /// Un marchand, ce qu'il pèse, et où ses opérations sont rangées.
    struct Tally: Identifiable, Sendable {
        let key: String
        let name: String
        let count: Int
        let total: Double
        /// La catégorie de ses opérations, si elles sont toutes d'accord.
        let categoryId: String?
        let categoryName: String?
        /// Combien de ses opérations n'ont pas de catégorie du tout.
        let unfiled: Int
        /// Vrai quand ses opérations sont réparties sur plusieurs catégories.
        let mixed: Bool

        var id: String { key }
    }

    /*
     * Ce que pèse chaque marchand, du plus lourd au plus léger.
     *
     * Trié par NOMBRE d'opérations et non par montant : on vient ici pour
     * cesser de reclasser la même chose, et c'est la répétition qui fatigue,
     * pas la somme. Un loyer annuel de six mille euros est une ligne ; le
     * café du matin en est trois cents.
     *
     * Les virements sont écartés : ils n'ont pas de catégorie par
     * construction, et les proposer au classement ferait croire à un oubli.
     */
    static func tallies(store: LocalStore) throws -> [Tally] {
        let rows = try store.database.query(
            """
            SELECT t.payee AS payee, t.amount AS amount, t.category_id AS category_id,
                   c.name AS category_name
            FROM transactions t
            LEFT JOIN categories c ON c.id = t.category_id
            WHERE t.deleted_at IS NULL AND t.transfer_pair_id IS NULL
            """
        )

        struct Bucket {
            var count = 0
            var total = 0.0
            var unfiled = 0
            var categories: [String: (name: String, count: Int)] = [:]
        }

        // La clé se calcule en Swift : une fois par libellé distinct plutôt
        // qu'une fois par ligne, comme `MerchantNames.usage(ofKey:)`.
        var keyOf: [String: String] = [:]
        var buckets: [String: Bucket] = [:]
        for row in rows {
            guard let payee = row.string("payee") else { continue }
            let key: String
            if let known = keyOf[payee] {
                key = known
            } else {
                key = MerchantNames.key(payee)
                keyOf[payee] = key
            }
            guard !key.isEmpty else { continue }

            var bucket = buckets[key] ?? Bucket()
            bucket.count += 1
            bucket.total += row.double("amount") ?? 0
            if let id = row.string("category_id") {
                let name = row.string("category_name") ?? ""
                let seen = bucket.categories[id] ?? (name, 0)
                bucket.categories[id] = (seen.name, seen.count + 1)
            } else {
                bucket.unfiled += 1
            }
            buckets[key] = bucket
        }

        let names = MerchantNames.shared
        return buckets.map { key, bucket in
            // Mélangé si deux catégories se partagent le marchand ; une
            // catégorie plus des lignes non classées n'est pas un mélange,
            // c'est un classement inachevé.
            let filed = bucket.categories
            let dominant = filed.max { $0.value.count < $1.value.count }
            return Tally(
                key: key,
                name: names.name(forKey: key) ?? key.uppercased(),
                count: bucket.count,
                total: bucket.total,
                categoryId: filed.count == 1 ? dominant?.key : nil,
                categoryName: filed.count == 1 ? dominant?.value.name : nil,
                unfiled: bucket.unfiled,
                mixed: filed.count > 1
            )
        }
        .sorted {
            $0.count == $1.count ? abs($0.total) > abs($1.total) : $0.count > $1.count
        }
    }

    /*
     * Ranger toutes les opérations d'un marchand d'un coup.
     *
     * La clé se recalcule ligne à ligne plutôt que de poser un `LIKE` sur le
     * libellé : deux libellés d'un même marchand n'ont pas forcément un
     * fragment commun — la banque tronque, Apple Pay non — et c'est
     * précisément ce que la clé sait rapprocher.
     *
     * Une ligne classée ici n'a plus rien à vérifier : `needs_review` tombe.
     * Les virements sont épargnés, comme au dénombrement.
     */
    @discardableResult
    static func file(store: LocalStore, key: String, categoryId: String) throws -> Int {
        let rows = try store.database.query(
            """
            SELECT id, payee FROM transactions
            WHERE deleted_at IS NULL AND transfer_pair_id IS NULL
            """
        )
        var keyOf: [String: String] = [:]
        var targets: [String] = []
        for row in rows {
            guard let id = row.string("id"), let payee = row.string("payee") else { continue }
            let computed: String
            if let known = keyOf[payee] {
                computed = known
            } else {
                computed = MerchantNames.key(payee)
                keyOf[payee] = computed
            }
            if computed == key { targets.append(id) }
        }
        guard !targets.isEmpty else { return 0 }

        try store.database.transaction {
            for id in targets {
                try store.database.run(
                    """
                    UPDATE transactions
                    SET category_id = ?, needs_review = 0, updated_at = datetime('now')
                    WHERE id = ?
                    """,
                    [.text(categoryId), .text(id)]
                )
            }
        }
        return targets.count
    }
}
