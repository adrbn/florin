import Foundation

/*
 * Un achat payé en plusieurs fois.
 *
 * « 3 fois sans frais » est une opération à venir comme une autre, simplement
 * répétée : trois lignes prévues à un mois d'intervalle, que le rapprochement
 * bancaire éteint une par une quand la banque les prélève. Rien de neuf dans
 * la base, donc — les échéances sont des opérations `scheduled` ordinaires, et
 * c'est ce qui les fait apparaître dans la prévision du mois sans toucher au
 * solde, exactement comme un paiement présenté au terminal.
 *
 * Ce que le module apporte vraiment tient en une fonction : `annualRate`. Une
 * offre « 2,2 % de frais en 3 fois » n'est pas un crédit à 2,2 % — on
 * n'emprunte les deux tiers de la somme qu'un mois ou deux, si bien que le
 * coût ramené à l'année dépasse les 25 %. C'est le seul chiffre qui permette
 * de comparer une facilité de paiement à un découvert ou à un prêt, et c'est
 * précisément celui que les offres ne montrent pas.
 */
enum LocalInstalments {
    /// Au-delà, ce n'est plus une facilité de caisse mais un crédit, qui se
    /// suit comme tel (voir `LocalLoan`).
    static let maxCount = 24

    // MARK: - Le partage

    /*
     * Les centimes tombent sur la première échéance.
     *
     * 100 € en 3 fois ne se divise pas : c'est 33,34 puis 33,33 puis 33,33.
     * La première est celle qu'on paie en même temps que l'achat, donc la
     * seule qu'on puisse confronter au ticket de caisse — c'est là que
     * l'arrondi doit se voir, pas dans une échéance de dans deux mois dont
     * personne ne se souviendra qu'elle devait être différente.
     */
    static func split(_ total: Double, over count: Int) -> [Double] {
        let count = max(1, min(count, maxCount))
        let cents = Int((abs(total) * 100).rounded())
        guard count > 1 else { return [Double(cents) / 100] }
        let base = cents / count
        let extra = cents % count
        return (0..<count).map { Double(base + ($0 == 0 ? extra : 0)) / 100 }
    }

    /*
     * L'échéance qu'on vous a annoncée, et le centime qui ne tombe pas juste.
     *
     * Une offre en plusieurs fois annonce toujours sa mensualité avant qu'on
     * confirme, et c'est le seul chiffre dont on soit sûr — le partage, lui,
     * est une convention que chaque organisme applique à sa façon et que
     * personne ne publie. Deviner cette convention, ou la proposer dans une
     * liste d'enseignes, ce serait se tromper avec assurance ; on prend donc
     * le chiffre annoncé et on ne discute pas.
     *
     * Reste que N fois ce chiffre retombe rarement sur le prix exact : une
     * mensualité arrondie au centime supérieur dépasse l'achat d'un cheveu.
     * La dernière échéance absorbe l'écart — la dernière, et non la première
     * comme dans `split`, parce qu'ici la première est justement celle qui a
     * été annoncée et qu'on n'a aucune raison de la contredire.
     *
     * Mais seulement jusqu'à un centime par échéance. Au-delà, l'écart n'est
     * plus un arrondi : c'est le coût de l'offre, et le rattraper en douce
     * sur la dernière échéance effacerait précisément ce que `annualRate` est
     * là pour montrer. Une offre « 3 × 34,00 € » sur un achat de 100 € rend
     * 2 € de plus, et doit continuer de le dire.
     */
    static func quoted(_ each: Double, count: Int, total: Double) -> [Double] {
        let count = max(1, min(count, maxCount))
        let each = Int((abs(each) * 100).rounded())
        var all = Array(repeating: each, count: count)
        let drift = each * count - Int((abs(total) * 100).rounded())
        if count > 1, drift != 0, abs(drift) <= count {
            all[count - 1] -= drift
        }
        return all.map { Double($0) / 100 }
    }

    /*
     * L'échéancier dit tel qu'il est.
     *
     * Le récapitulatif multipliait la première échéance par leur nombre —
     * « 3 × 33,34 € » en face de « 100,00 € », alors que trois fois 33,34
     * font 100,02. La première est justement celle qui porte les centimes de
     * l'arrondi : la phrase se contredisait dès qu'un montant ne se divisait
     * pas, c'est-à-dire presque toujours.
     *
     * Les échéances égales qui se suivent se regroupent, les autres se
     * nomment. « 3 × 33,33 € » quand ça tombe juste, « 33,34 € + 2 × 33,33 € »
     * quand les centimes ouvrent la marche, « 2 × 33,33 € + 33,34 € » quand
     * ils la ferment — sans qu'aucun de ces cas soit traité à part.
     */
    static func describe(_ amounts: [Double], money: (Double) -> String) -> String {
        var parts: [String] = []
        var index = 0
        while index < amounts.count {
            var run = 1
            while index + run < amounts.count,
                  abs(amounts[index + run] - amounts[index]) < 0.005 { run += 1 }
            let each = money(amounts[index])
            parts.append(run == 1 ? each : "\(run) × \(each)")
            index += run
        }
        return parts.joined(separator: " + ")
    }

    /// Les frais d'une offre énoncée « N × M € » : ce qu'on rend en plus de
    /// ce qu'on a acheté.
    static func fees(purchase: Double, instalments: [Double]) -> Double {
        round2(instalments.reduce(0, +) - abs(purchase))
    }

    // MARK: - Le coût réel

    /*
     * Le taux annuel équivalent de l'offre.
     *
     * On résout le taux mensuel `i` qui annule la valeur actuelle nette :
     * l'achat d'un côté, les échéances actualisées de l'autre, la première à
     * l'instant zéro puisqu'elle est payée à la caisse et n'est donc jamais
     * prêtée. Le résultat est ramené à l'année par composition, comme un TAEG.
     *
     * La valeur actuelle nette décroît avec le taux : au taux nul elle vaut
     * les frais, positive dès qu'il y en a, et tend vers le seul premier
     * versement quand le taux s'envole. Une dichotomie suffit donc, et vaut
     * mieux qu'un Newton qui diverge sur les offres courtes.
     *
     * Sans frais, le taux est nul — et non « indéfini » : prêter à zéro est
     * une réponse, pas une absence de réponse.
     */
    static func annualRate(purchase: Double, instalments: [Double]) -> Double? {
        let purchase = abs(purchase)
        guard purchase > 0, instalments.count > 1,
              instalments.allSatisfy({ $0 >= 0 }) else { return nil }
        let due = instalments.reduce(0, +)
        guard due > purchase + 0.005 else { return 0 }
        func netPresentValue(at monthly: Double) -> Double {
            instalments.enumerated().reduce(-purchase) { total, instalment in
                total + instalment.element / pow(1 + monthly, Double(instalment.offset))
            }
        }
        var low = 0.0
        var high = 1.0
        while netPresentValue(at: high) > 0 && high < 1_000 { high *= 2 }
        guard netPresentValue(at: high) <= 0 else { return nil }
        for _ in 0..<200 {
            let middle = (low + high) / 2
            if netPresentValue(at: middle) > 0 { low = middle } else { high = middle }
        }
        let monthly = (low + high) / 2
        return pow(1 + monthly, 12) - 1
    }

    // MARK: - Les dates

    /// La première échéance le jour de l'achat, les suivantes de mois en mois.
    /// Un 31 janvier donne un 28 février : le calendrier ramène au dernier
    /// jour du mois plutôt que de déborder sur le suivant.
    static func dates(from first: Date, count: Int, calendar: Calendar = .current) -> [Date] {
        (0..<max(1, count)).map {
            calendar.date(byAdding: .month, value: $0, to: first) ?? first
        }
    }

    // MARK: - L'écriture

    /*
     * Les échéances entrent comme des opérations à venir.
     *
     * Elles portent donc la même source que celles-là, et ce n'est pas un
     * abus : c'est ce qui les rend visibles au rapprochement, qui n'apparie
     * que cette source-là. La banque prélève, `LocalWallet.settle` retire
     * l'échéance et garde sa catégorie. Un paiement en trois fois se solde
     * ainsi tout seul, sans que rien ne surveille un solde restant dû.
     */
    @discardableResult
    static func record(
        store: LocalStore, accountId: String, payee: String, memo: String?,
        categoryId: String?, from first: Date, instalments: [Double],
        purchase: Double? = nil, calendar: Calendar = .current
    ) throws -> Int {
        let days = dates(from: first, count: instalments.count, calendar: calendar)
        // Ce qui fait de ces N lignes un échéancier plutôt que N opérations
        // qui se ressemblent.
        let plan = UUID().uuidString
        /*
         * Le prix d'achat, écrit une fois pour l'échéancier entier.
         *
         * Sans prix donné, c'est la somme des échéances : « sans frais », la
         * seule hypothèse que le grand livre atteste. Voir
         * `LocalStore.priceOlderPlansAtWhatTheyCharged`.
         */
        try store.database.run(
            "INSERT OR REPLACE INTO instalment_plans (id, purchase, purchased_on) VALUES (?, ?, ?)",
            [
                .text(plan),
                .real(round2(abs(purchase ?? instalments.reduce(0, +)))),
                .text(String(ISO8601DateFormatter.florinNoFraction.string(
                    from: noon(days.first ?? first, calendar)
                ).prefix(10))),
            ]
        )
        for (index, amount) in instalments.enumerated() {
            let note = Strings.device(
                "v2.instalments.memo", "En {count} fois ({index}/{count})",
                ["count": "\(instalments.count)", "index": "\(index + 1)"]
            )
            try LocalWallet.recordUpcoming(store: store, NewTransaction(
                accountId: accountId,
                amount: -abs(amount),
                payee: payee,
                occurredAt: ISO8601DateFormatter.florinNoFraction.string(
                    from: noon(days[index], calendar)
                ),
                memo: memo.flatMap { $0.isEmpty ? nil : "\($0) · \(note)" } ?? note,
                categoryId: categoryId,
                upcoming: true,
                instalmentPlanId: plan
            ))
        }
        return instalments.count
    }

    // MARK: - La lecture

    /*
     * Un échéancier tel qu'on le regarde : un achat, pas N opérations.
     *
     * L'écran listait les échéances à plat — quatre lignes identiques à un
     * mois d'intervalle, et celles de deux achats différents mêlées au même
     * niveau. Or personne ne pense « j'ai quatre opérations à venir » : on
     * pense « il me reste trois échéances chez untel ». Le regroupement est
     * donc la vue, et l'échéance le détail.
     *
     * Tout se déduit des lignes, ce qui est volontaire : rien à tenir à jour,
     * rien qui puisse mentir. Une échéance prélevée est une ligne de la banque
     * (`status = 'cleared'`), une échéance à venir est annoncée
     * (`'scheduled'`) — le plan se remplit de lui-même au fil des
     * prélèvements, sans compteur à incrémenter.
     */
    struct Schedule: Identifiable, Sendable {
        let id: String
        /// Le prix affiché à l'achat, positif.
        let purchase: Double
        let purchasedOn: Date?
        /// Les échéances dans l'ordre des dates, payées puis à venir.
        let instalments: [Transaction]

        /// L'enseigne, prise sur la première échéance : renommer une ligne
        /// renomme donc l'échéancier, ce qui est le comportement attendu.
        var payee: String { instalments.first?.payee ?? "" }
        var accountName: String { instalments.first?.accountName ?? "" }
        var categoryName: String? { instalments.first?.categoryName }
        var categoryEmoji: String? { instalments.first?.categoryEmoji }
        var accountId: String? { instalments.first?.accountId }

        var count: Int { instalments.count }
        /*
         * Payée veut dire prélevée, pas « sa date est passée ».
         *
         * `isUpcoming` répond à une question de date, et c'est ce qu'il faut
         * pour une liste d'opérations. Un échéancier, lui, n'avance que quand
         * la banque débite : au 4 octobre à 00:00, la mensualité du 4 passait
         * en « payée » sans qu'un centime ait bougé, et le reste à payer
         * fondait d'autant. Une échéance reste donc à venir tant qu'elle est
         * annoncée — `settle` l'éteint en transportant le plan sur le vrai
         * débit, et c'est ce débit qui la compte comme payée.
         */
        var due: [Transaction] { instalments.filter(\.isScheduled) }
        var settled: [Transaction] { instalments.filter { !$0.isScheduled } }
        var paidCount: Int { settled.count }

        /// Ce que l'échéancier prélève en tout — frais compris, donc pas
        /// forcément le prix d'achat.
        var total: Double { LocalInstalments.round2(settled.sum + due.sum) }
        var paid: Double { LocalInstalments.round2(settled.sum) }
        var remaining: Double { LocalInstalments.round2(due.sum) }
        /// Ce qu'on rend en plus de ce qu'on a acheté.
        var fees: Double { LocalInstalments.round2(total - purchase) }
        var isFree: Bool { abs(fees) < 0.005 }
        var annualRate: Double? {
            LocalInstalments.annualRate(
                purchase: purchase, instalments: instalments.map { abs($0.amount) }
            )
        }

        /// La prochaine échéance à tomber, s'il en reste.
        var next: Transaction? { due.first }
        var isOver: Bool { due.isEmpty }

        /*
         * Le pli obéit au même filtre que la liste sous lui.
         *
         * Les échéanciers ne se paginent pas et ne passent donc pas par la
         * requête : ils arrivaient entiers, et « 5 paiements en plusieurs
         * fois » restait affiché au-dessus de quatre résultats de recherche
         * qui n'avaient rien à voir. Un pli qui répond à une question qu'on
         * n'a pas posée se lit comme un résultat.
         *
         * Les mêmes champs que la recherche SQL — le libellé de la banque, le
         * nom donné au marchand, les notes — et un échéancier tombe dès qu'une
         * de ses échéances répond, parce que c'est l'achat qu'on cherche.
         */
        func matches(_ filter: TxFilter) -> Bool {
            // Une échéance est une dépense annoncée : ni une entrée, ni une
            // ligne en attente de décision.
            if filter.direction == .income || filter.needsReview { return false }
            if let account = filter.accountId, accountId != account { return false }
            if let category = filter.categoryId,
               !instalments.contains(where: { $0.categoryId == category }) { return false }
            if let from = filter.from, !due.contains(where: { $0.day >= from }) { return false }
            if let to = filter.to, !due.contains(where: { $0.day <= to }) { return false }

            let needle = filter.search.trimmingCharacters(in: .whitespaces).lowercased()
            guard !needle.isEmpty else { return true }
            if payee.lowercased().contains(needle) { return true }
            if let given = MerchantNames.shared.name(for: payee)?.lowercased(),
               given.contains(needle) { return true }
            return instalments.contains { ($0.memo ?? "").lowercased().contains(needle) }
        }
    }

    /// Les échéanciers du grand livre, le plus pressé d'abord.
    ///
    /// Ordonnés sur la prochaine échéance — c'est la question que l'écran
    /// pose — et les échéanciers soldés à la fin, eux n'attendant plus rien.
    static func schedules(_ db: SQLiteDatabase) throws -> [Schedule] {
        let prices = try db.query("SELECT id, purchase, purchased_on FROM instalment_plans")
        var purchase: [String: (Double, String?)] = [:]
        for row in prices {
            guard let id = row.string("id") else { continue }
            purchase[id] = (row.double("purchase") ?? 0, row.string("purchased_on"))
        }
        let rows = try db.query(
            """
            SELECT t.id, t.occurred_at, t.amount, t.payee, t.memo,
                   c.name AS category_name, c.emoji AS category_emoji,
                   a.name AS account_name, t.transfer_pair_id,
                   t.needs_review, t.is_pending, t.status,
                   t.account_id, t.category_id, t.instalment_plan_id
            FROM transactions t
            LEFT JOIN categories c ON c.id = t.category_id
            LEFT JOIN accounts a ON a.id = t.account_id
            WHERE t.deleted_at IS NULL AND t.instalment_plan_id IS NOT NULL
            ORDER BY t.occurred_at
            """
        ).map(LocalLedger.transaction(from:))

        var order: [String] = []
        var grouped: [String: [Transaction]] = [:]
        for row in rows {
            guard let plan = row.instalmentPlanId else { continue }
            if grouped[plan] == nil { order.append(plan) }
            grouped[plan, default: []].append(row)
        }
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        return order.map { plan -> Schedule in
            let instalments = grouped[plan] ?? []
            let price = purchase[plan]
            return Schedule(
                id: plan,
                // Un plan sans prix enregistré — base reprise d'un autre
                // appareil, reprise qui n'a pas encore tourné — vaut ce qu'il
                // prélève, comme dans la reprise elle-même.
                purchase: price?.0 ?? round2(instalments.reduce(0) { $0 + abs($1.amount) }),
                purchasedOn: price?.1.flatMap { day.date(from: $0 + "T00:00:00Z") }
                    ?? instalments.first?.day,
                instalments: instalments
            )
        }
        .sorted {
            switch ($0.next?.day, $1.next?.day) {
            case let (left?, right?): return left < right
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return $0.payee < $1.payee
            }
        }
    }

    // MARK: -

    /// Midi, comme toute opération saisie à la main : la date compte, l'heure
    /// non, et midi ne bascule pas de jour selon le fuseau.
    private static func noon(_ day: Date, _ calendar: Calendar) -> Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    private static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}

private extension Array where Element == Transaction {
    /// La somme des échéances, positive : une dépense est négative au grand
    /// livre et un échéancier se lit en « ce qu'il reste à payer ».
    var sum: Double { reduce(0) { $0 + abs($1.amount) } }
}
