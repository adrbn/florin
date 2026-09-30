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
        calendar: Calendar = .current
    ) throws -> Int {
        let days = dates(from: first, count: instalments.count, calendar: calendar)
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
                upcoming: true
            ))
        }
        return instalments.count
    }

    // MARK: -

    /// Midi, comme toute opération saisie à la main : la date compte, l'heure
    /// non, et midi ne bascule pas de jour selon le fuseau.
    private static func noon(_ day: Date, _ calendar: Calendar) -> Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    private static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}
