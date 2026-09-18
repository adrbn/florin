import SwiftUI

/// What repeats, and what it costs a year.
///
/// The radar finds the charges; this is where they are read. It was a list of
/// bank labels — "DE Telecom SA REF : 98765432…", truncated mid-reference, over a
/// grey repeat icon repeated seven times — which is the raw material of the
/// answer rather than the answer. Three things make it one:
///
///  - The merchant's own face, the same one the transaction lists draw.
///  - The name it is known by, the bank's rail and its reference taken off,
///    or the name the reader has given it.
///  - When the next one is due, rather than the ISO date of the last.
///
/// And a tap opens the merchant sheet, so a subscription with no logo and a
/// shouted name is two taps from having both — everywhere in the app, not just
/// here.
struct SubscriptionsSection: View {
    let subscriptions: [SubscriptionMatch]
    let locale: String
    let currency: String
    let t: Strings

    @State private var naming: NamedMerchant?

    /// The merchant sheet's inputs, carried together so `sheet(item:)` has
    /// something to key on.
    private struct NamedMerchant: Identifiable {
        let key: String
        let label: String
        var id: String { key }
    }

    private var sorted: [SubscriptionMatch] {
        subscriptions.sorted { $0.annualCost > $1.annualCost }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            if sorted.isEmpty {
                empty
            } else {
                list
            }
        }
        .sheet(item: $naming) { merchant in
            MerchantNameSheet(key: merchant.key, bankLabel: merchant.label, t: t)
        }
    }

    // MARK: - The list

    private var list: some View {
        let monthly = sorted.reduce(0) { $0 + $1.annualCost } / 12
        return ScreenSection(
            title: t("v2.analysis.tab.subs", "Abonnements"),
            trailing: Money.string(monthly, locale: locale, currency: currency, decimals: false)
                + " " + t("v2.analysis.perMonthShort", "par mois")
        ) {
            VStack(alignment: .leading, spacing: 8) {
                RowGroup {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, sub in
                        if index > 0 { Hairline() }
                        SubscriptionRow(
                            sub: sub, locale: locale, currency: currency, t: t,
                            cadence: cadence(sub), when: when(sub),
                            open: { naming = merchant(sub) }
                        )
                    }
                }
                Text(t("v2.analysis.subsRenameHint",
                       "Touchez un abonnement pour lui donner son nom et son logo."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Florin.text3)
                    .padding(.horizontal, 2)
            }
            .padding(.horizontal, Florin.gutter)
        }
    }

    private var empty: some View {
        FlorinCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(t("v2.analysis.subsEmpty", "Aucun abonnement détecté"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Florin.text)
                Text(
                    t(
                        "v2.analysis.subsEmptyWhy",
                        "Florin cherche un même bénéficiaire, au même montant, au moins trois fois, à un rythme régulier — toutes les 4 semaines environ ou toutes les semaines — sur les 6 derniers mois. Les achats ponctuels, et les montants qui changent à chaque fois, n'en font pas partie."
                    )
                )
                .font(.system(size: 12.5))
                .foregroundStyle(Florin.text2)
            }
        }
        .padding(.horizontal, Florin.gutter)
    }

    private func merchant(_ sub: SubscriptionMatch) -> NamedMerchant {
        NamedMerchant(key: MerchantNames.key(sub.payee), label: PayeeText.clean(sub.payee))
    }

    // MARK: - Words for a rhythm and a date

    /// "tous les 32 j" is technically right and useless; people think in
    /// months, weeks and years.
    private func cadence(_ sub: SubscriptionMatch) -> String {
        switch sub.cadenceDays {
        case 25...35: return t("v2.analysis.monthly", "Mensuel")
        case 6...8: return t("v2.analysis.weekly", "Hebdomadaire")
        case 12...16: return t("v2.analysis.biweekly", "Toutes les 2 semaines")
        case 85...95: return t("v2.analysis.quarterly", "Trimestriel")
        case 350...380: return t("v2.analysis.yearly", "Annuel")
        default: return t("v2.analysis.every", "Tous les {count} j", ["count": sub.cadenceDays])
        }
    }

    /*
     * When the next one is due, and only the last one when that has passed.
     *
     * The date printed here was the ISO day the radar reports, unparsed — the
     * two ISO8601 readers it went through both refuse "2026-09-04", so every
     * row read "Mensuel · 2026-09-04". Past the last charge plus its cadence,
     * the subscription is either late or over, and saying "prochain le 4
     * septembre" about a day that is gone is worse than saying nothing.
     */
    private func when(_ sub: SubscriptionMatch) -> String {
        guard let last = LocalQueries.dayFormatter.date(from: String(sub.lastSeen.prefix(10)))
        else { return "" }
        let calendar = Calendar(identifier: .gregorian)
        let due = calendar.date(byAdding: .day, value: sub.cadenceDays, to: last) ?? last
        let today = calendar.startOfDay(for: Date())
        return due >= today
            ? t("v2.analysis.nextDue", "prochain le {date}",
                ["date": DayLabel.string(due, locale: locale, t: t)])
            : t("v2.analysis.lastSeen", "vu {date}",
                ["date": DayLabel.string(last, locale: locale, t: t)])
    }
}

/// One subscription: its face, its name, its beat, its price.
///
/// Its own view so that it can watch the two stores that decide what a
/// merchant looks like — a name given from the sheet this row opens is on the
/// row before the sheet has finished closing.
private struct SubscriptionRow: View {
    let sub: SubscriptionMatch
    let locale: String
    let currency: String
    let t: Strings
    let cadence: String
    let when: String
    let open: () -> Void

    @ObservedObject private var names = MerchantNames.shared
    @ObservedObject private var logos = MerchantLogos.shared

    var body: some View {
        let key = MerchantNames.key(sub.payee)
        let face = logos.face(forKey: key)
        Button(action: open) {
            HStack(spacing: 12) {
                Bubble(
                    label: names.name(forKey: key) ?? sub.payee,
                    emoji: face?.emoji,
                    systemImage: face == nil ? "repeat" : nil,
                    logo: face?.logo
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(PayeeText.merchant(sub.payee))
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Florin.text)
                        .lineLimit(1)
                    Text(when.isEmpty ? cadence : cadence + " · " + when)
                        .font(.system(size: 12))
                        .foregroundStyle(Florin.text2)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    AmountText(value: -abs(sub.amount), locale: locale,
                               currency: currency, tone: .negative)
                    Text(
                        Money.string(sub.annualCost, locale: locale,
                                     currency: currency, decimals: false)
                            + "/" + t("v2.common.year", "an")
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(Florin.text3)
                    .hiddenWhenPrivate()
                }
            }
            .padding(.horizontal, Florin.gutter)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
