import Foundation

/*
 * Le meilleur candidat, même quand il n'est pas assez sûr pour être appliqué.
 *
 * `LocalCategoriser` ne classe qu'au-dessus de 0,80 et se tait en dessous, et
 * il a raison de se taire : une catégorie fausse passe ensuite en revue
 * groupée et se glisse en silence dans un budget. Mais se taire, c'est aussi
 * jeter ce qu'il avait trouvé. Mesuré sur un grand livre réel, un restaurant
 * vu une fois à l'étranger a marqué 0,69 pour la bonne catégorie et n'a rien
 * affiché du tout : le moteur savait, et la personne a quand même dû chercher
 * dans soixante catégories.
 *
 * Alors on ne l'applique toujours pas — on le propose. Une proposition ne
 * coûte aucune justesse, puisqu'elle attend un geste ; elle ne fait que mettre
 * en tête de liste ce que la liste contenait déjà.
 */
enum CategoryHint {
    /// En dessous, le candidat n'est plus une idée : c'est un tirage au sort.
    /// Le meilleur score des lignes qu'on voulait aider tourne autour de 0,7 ;
    /// celles qui ne ressemblent à rien tombent sous 0,4.
    static let floor = 0.35

    /*
     * La mémoire se relit, mais pas à chaque ouverture.
     *
     * La construire lit jusqu'à huit mille lignes du grand livre, ce qu'on ne
     * peut pas payer chaque fois qu'un sélecteur s'ouvre — classer dix
     * opérations d'affilée est précisément l'usage. Elle est donc gardée le
     * temps d'une session de classement, et pas plus : ce qui vient d'être
     * classé doit compter pour la suivante.
     */
    static let freshness: TimeInterval = 60

    private nonisolated(unsafe) static var cached: (memory: LocalCategoriser.Memory, at: Date)?
    private static let lock = NSLock()

    /// Oublie ce que le grand livre disait — après un import, une restauration
    /// ou une suppression en masse, il ne dit plus la même chose.
    static func invalidate() {
        lock.lock()
        cached = nil
        lock.unlock()
    }

    private static func memory(_ store: LocalStore) -> LocalCategoriser.Memory? {
        lock.lock()
        defer { lock.unlock() }
        if let cached, Date().timeIntervalSince(cached.at) < freshness { return cached.memory }
        guard let built = try? LocalCategoriser.remember(store: store), !built.isEmpty else {
            return nil
        }
        cached = (built, Date())
        return built
    }

    /// Ce qu'une mémoire donnée propose : le candidat du catégoriseur, gardé
    /// seulement s'il vaut mieux qu'un tirage au sort. Sans état ni cache —
    /// c'est la règle elle-même, et c'est elle que les tests interrogent.
    static func suggest(
        _ memory: LocalCategoriser.Memory,
        payee: String, amount: Double, accountId: String, date: String = ""
    ) -> LocalCategoriser.Suggestion? {
        guard let hit = LocalCategoriser.suggest(
            memory, payee: payee, amount: amount, accountId: accountId, date: date
        ), hit.confidence >= floor else { return nil }
        return hit
    }

    /// La même question posée au grand livre de l'appareil.
    static func suggest(
        payee: String, amount: Double, accountId: String, date: String
    ) -> LocalCategoriser.Suggestion? {
        guard let store = LocalStore.shared, let memory = memory(store) else { return nil }
        return suggest(memory, payee: payee, amount: amount, accountId: accountId, date: date)
    }

    /*
     * Rien à proposer à qui a déjà répondu.
     *
     * Une ligne classée porte une décision, et une ligne volontairement laissée
     * sans catégorie en porte une aussi — c'est ce que dit déjà `backfill`, qui
     * ne revient jamais sur une ligne approuvée. Ici la règle est plus simple
     * parce que le sélecteur est ouvert exprès : on ne propose que lorsque la
     * case est vide, et on ne propose jamais la catégorie déjà en place.
     */
    static func category(for tx: Transaction, in categories: [Category]) -> Category? {
        guard tx.categoryId == nil, tx.categoryName == nil, !tx.isTransfer else { return nil }
        guard let hit = suggest(
            payee: tx.payee,
            amount: tx.amount,
            accountId: tx.accountId ?? "",
            date: String(tx.date.prefix(10))
        ) else { return nil }
        return categories.first { $0.id == hit.categoryId }
    }
}
