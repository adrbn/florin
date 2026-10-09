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

    /// Préchauffer, pour qui sait déjà qu'il va demander : la feuille de
    /// saisie interroge à la troisième lettre du bénéficiaire, et payer là la
    /// relecture de huit mille lignes se verrait au clavier.
    static func warm() async {
        guard let store = LocalStore.shared else { return }
        await Task.detached(priority: .userInitiated) { _ = memory(store) }.value
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
     * Les trois réponses plausibles, au lieu d'une seule pré-remplie.
     *
     * Une valeur déjà posée se lit comme une décision, et quand elle est
     * fausse il faut rouvrir soixante catégories pour la défaire. Trois
     * pastilles disent l'inverse : voilà ce que je crois, voilà les deux
     * autres, dis-moi. Le même plancher s'applique — un quatrième candidat à
     * 0,1 n'est pas une idée.
     */
    static func shortlist(
        _ memory: LocalCategoriser.Memory,
        payee: String, amount: Double, accountId: String, date: String = "",
        limit: Int = 3
    ) -> [LocalCategoriser.Suggestion] {
        let ranked = LocalCategoriser.shortlist(
            memory, payee: payee, amount: amount, accountId: accountId, date: date
        )
        return Array(ranked.filter { $0.confidence >= floor }.prefix(limit))
    }

    /// La même question posée au grand livre de l'appareil, rendue en
    /// catégories que l'écran peut afficher.
    static func shortlist(
        payee: String, amount: Double, accountId: String, date: String,
        in categories: [Category], limit: Int = 3
    ) -> [Category] {
        guard let store = LocalStore.shared, let memory = memory(store) else { return [] }
        return shortlist(
            memory, payee: payee, amount: amount, accountId: accountId,
            date: date, limit: limit
        )
        .compactMap { hit in categories.first { $0.id == hit.categoryId } }
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
    static func categories(
        for tx: Transaction, in categories: [Category], limit: Int = 3
    ) -> [Category] {
        guard tx.categoryId == nil, tx.categoryName == nil, !tx.isTransfer else { return [] }
        return shortlist(
            payee: tx.payee,
            amount: tx.amount,
            accountId: tx.accountId ?? "",
            date: String(tx.date.prefix(10)),
            in: categories,
            limit: limit
        )
    }
}
