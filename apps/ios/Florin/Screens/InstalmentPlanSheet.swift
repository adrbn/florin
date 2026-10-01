import SwiftUI

/*
 * Un achat en plusieurs fois, vu comme un achat.
 *
 * L'écran listait les échéances à plat : quatre lignes à un mois d'intervalle,
 * et celles de deux achats différents mêlées au même niveau, si bien qu'un
 * voyage et un flacon de parfum se répondaient en alternance. Le pli disait
 * « 10 opérations » — ce qui est vrai de la base et faux de la vie : il y avait
 * trois achats.
 *
 * Une ligne par échéancier, donc, et le détail derrière. La ligne répond à ce
 * qu'on se demande en passant — chez qui, combien il reste, quand tombe la
 * prochaine — et la sheet à ce qu'on vient vérifier : le prix d'achat, les
 * frais s'il y en a, chaque échéance avec sa date et son sort.
 */
struct InstalmentPlanRow: View {
    let plan: LocalInstalments.Schedule
    let locale: String
    let currency: String
    var t: Strings = .empty

    /// Observés pour la même raison que dans `TransactionRowView` : une
    /// enseigne renommée depuis sa fiche se renomme ici sans rechargement.
    @ObservedObject private var names = MerchantNames.shared
    @ObservedObject private var logos = MerchantLogos.shared

    private var title: String { PayeeText.title(plan.payee, category: plan.categoryName) }

    var body: some View {
        HStack(spacing: 12) {
            let face = logos.face(for: plan.payee)
            Bubble(
                label: plan.categoryName ?? plan.payee,
                emoji: face?.emoji ?? plan.categoryEmoji,
                logo: face?.logo
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Florin.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Florin.text2)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                AmountText(
                    value: plan.remaining, locale: locale, currency: currency,
                    tone: .neutral
                )
                InstalmentProgress(count: plan.count, paid: plan.paidCount)
            }
        }
        .padding(.horizontal, Florin.gutter)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    /// Où en est l'échéancier, et quand tombe la suite. Le nombre payé passe
    /// avant la date parce que c'est lui qui dit si l'achat est derrière soi.
    private var subtitle: String {
        let progress = t(
            "v2.instalments.paidOf", "{paid} sur {count} payées",
            ["paid": plan.paidCount, "count": plan.count]
        )
        guard let next = plan.next else { return progress }
        return progress + " · " + DayLabel.string(next.day, locale: locale, t: t)
    }
}

/*
 * Où en est l'échéancier, sans chiffre.
 *
 * Des pastilles tant qu'on peut les compter d'un coup d'œil — quatre
 * remplies sur six se lisent sans lire — et une barre au-delà, où elles ne
 * seraient plus qu'un damier. Dix échéances ne se comptent pas à la pastille.
 */
struct InstalmentProgress: View {
    let count: Int
    let paid: Int
    var width: CGFloat = 54

    private var fraction: Double {
        guard count > 0 else { return 0 }
        return min(1, max(0, Double(paid) / Double(count)))
    }

    var body: some View {
        if count <= 6 {
            HStack(spacing: 3) {
                ForEach(0..<max(1, count), id: \.self) { index in
                    Capsule()
                        .fill(index < paid ? Florin.accent : Florin.text.opacity(0.14))
                        .frame(height: 3)
                }
            }
            .frame(width: width)
        } else {
            ZStack(alignment: .leading) {
                Capsule().fill(Florin.text.opacity(0.14))
                Capsule().fill(Florin.accent).frame(width: width * fraction)
            }
            .frame(width: width, height: 3)
        }
    }
}

// MARK: - Le détail

struct InstalmentPlanSheet: View {
    let plan: LocalInstalments.Schedule
    let locale: String
    let currency: String
    let t: Strings

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var logos = MerchantLogos.shared

    private var title: String { PayeeText.title(plan.payee, category: plan.categoryName) }

    var body: some View {
        NavigationStack {
            ZStack {
                Backdrop(tint: TabRoute.activity.tint).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        summary
                        schedule
                    }
                    .padding(.horizontal, Florin.gutter)
                    .padding(.vertical, 14)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationTitle(t("v2.instalments.planTitle", "Paiement en plusieurs fois"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.close", "Fermer")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: -

    private var header: some View {
        HStack(spacing: 14) {
            let face = logos.face(for: plan.payee)
            Bubble(
                label: plan.categoryName ?? plan.payee,
                emoji: face?.emoji ?? plan.categoryEmoji,
                size: 52,
                logo: face?.logo
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Florin.text)
                    .lineLimit(2)
                Text(
                    t("v2.instalments.paidOf", "{paid} sur {count} payées",
                      ["paid": plan.paidCount, "count": plan.count])
                    + " · " + plan.accountName
                )
                .font(.system(size: 13))
                .foregroundStyle(Florin.text2)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    /*
     * Ce que l'achat a coûté, et ce qu'il reste à en payer.
     *
     * Le prix d'achat figure en premier parce que c'est lui qu'on reconnaît —
     * le ticket, le panier — et les frais juste après, puisque la seule chose
     * qu'on cherche à savoir d'une facilité de paiement est si elle en a. Sans
     * frais, le taux annuel n'a rien à dire et ne s'affiche pas ; avec, il
     * dit ce que l'offre coûte vraiment (voir `LocalInstalments.annualRate`).
     */
    private var summary: some View {
        RowGroup {
            line(t("v2.instalments.purchase", "Montant de l'achat"), plan.purchase)
            Hairline()
            HStack {
                Text(t("v2.add.instalmentsFees", "Frais"))
                    .font(.system(size: 15))
                    .foregroundStyle(Florin.text)
                Spacer(minLength: 8)
                if plan.isFree {
                    SettingsValue(text: t("v2.add.instalmentsNoFees", "Sans frais"))
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        let rate = plan.annualRate
                        AmountText(
                            value: plan.fees, locale: locale, currency: currency,
                            // Rouge au-delà de dix pour cent, comme dans la
                            // sheet d'ajout : à ce niveau ce n'est plus une
                            // facilité de caisse mais un crédit.
                            tone: (rate ?? 0) > 0.10 ? .negative : .neutral
                        )
                        if let rate, rate > 0 {
                            Text(t("v2.add.instalmentsPerYear", "{rate} par an",
                                   ["rate": Money.percent(rate, locale: locale)]))
                                .font(.system(size: 11.5))
                                .foregroundStyle(Florin.text3)
                        }
                    }
                }
            }
            .padding(.horizontal, Florin.gutter)
            .padding(.vertical, 12)
            Hairline()
            line(t("v2.instalments.paidTotal", "Déjà payé"), plan.paid)
            Hairline()
            line(
                t("v2.instalments.remainingTotal", "Reste à payer"), plan.remaining,
                tone: plan.isOver ? .muted : .neutral, strong: !plan.isOver
            )
        }
    }

    private func line(
        _ label: String, _ value: Double,
        tone: AmountText.Tone = .neutral, strong: Bool = false
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Florin.text)
            Spacer(minLength: 8)
            AmountText(
                value: value, locale: locale, currency: currency, tone: tone,
                weight: strong ? .semibold : .medium
            )
        }
        .padding(.horizontal, Florin.gutter)
        .padding(.vertical, 12)
    }

    /*
     * L'échéancier, dans l'ordre où il tombe.
     *
     * Chaque ligne porte son rang — « 2 / 4 » — parce que c'est ainsi qu'une
     * offre en parle, et son sort : prélevée, ou à venir. La prochaine est
     * mise en avant, les passées s'effacent : on ne relit pas une échéance
     * payée, on vérifie celle qui vient.
     */
    private var schedule: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: t("v2.instalments.schedule", "Échéances"))
            RowGroup {
                /*
                 * Lues, pas ouvertes.
                 *
                 * Une échéance est une opération du grand livre et se modifie
                 * là où on modifie une opération — dans la liste, par sa
                 * fiche. Lui donner un chevron ici obligerait à refermer cette
                 * sheet pour en ouvrir une autre dans la même image, ce que
                 * SwiftUI escamote une fois sur deux ; et l'échéancier est
                 * fait pour être relu, pas retouché.
                 */
                ForEach(Array(plan.instalments.enumerated()), id: \.element.id) { index, tx in
                    if index > 0 { Hairline() }
                    step(tx, rank: index + 1)
                }
            }
        }
    }

    private func step(_ tx: Transaction, rank: Int) -> some View {
        let isNext = tx.id == plan.next?.id
        return HStack(spacing: 12) {
            Text("\(rank) / \(plan.count)")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tx.isUpcoming ? Florin.text2 : Florin.text3)
                .frame(width: 42, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(DayLabel.string(tx.day, locale: locale, t: t))
                    .font(.system(size: 14.5, weight: isNext ? .semibold : .medium))
                    .foregroundStyle(Florin.text)
                Text(
                    tx.isUpcoming
                        ? t("v2.activity.scheduled", "Prévu")
                        : t("v2.instalments.settled", "Prélevée")
                )
                .font(.system(size: 12))
                .foregroundStyle(tx.isUpcoming ? Florin.accent : Florin.text3)
            }
            Spacer(minLength: 8)
            AmountText(
                value: abs(tx.amount), locale: locale, currency: currency,
                tone: tx.isUpcoming ? .neutral : .muted
            )
        }
        .padding(.horizontal, Florin.gutter)
        .padding(.vertical, 12)
        .background(isNext ? Florin.accent.opacity(0.07) : .clear)
    }
}
