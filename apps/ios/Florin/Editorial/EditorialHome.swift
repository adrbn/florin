import SwiftUI

/*
 * Accueil, dans le langage Éditorial.
 *
 * Les mêmes chiffres que `OverviewScreen` — le même `OverviewModel`, les mêmes
 * requêtes — mais dits autrement : un salut en très grand, le patrimoine net
 * sous sa pastille, et la pile de comptes où la carte du dessous est celle
 * qu'on regarde.
 *
 * Rien ici ne lit la base : tout vient du modèle que l'ancien écran lit déjà.
 * C'est ce qui permet aux deux de coexister sans dupliquer une requête.
 */
struct EditorialHome: View {
    @ObservedObject var model: OverviewModel
    let onOpenSettings: () -> Void
    let onOpenAccounts: () -> Void

    @State private var addingAccount = false

    private var t: Strings { model.overview?.t ?? .empty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                EdHero(text: t("v2.overview.morning", "Bonjour"))
                    .padding(.top, 18)
                netWorth
                accountsHeading
                stack
            }
            .padding(.horizontal, Ed.gutter)
            .padding(.top, 10)
            // La capsule flotte à 28 pt du bas sur 60 pt de haut : le contenu
            // s'arrête au-dessus, sans quoi la dernière carte passe dessous.
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(Florin.bg)
        .refreshable { await model.load() }
        .sheet(isPresented: $addingAccount) {
            AddAccountSheet(onSaved: { Task { await model.load() } })
        }
    }

    // MARK: Le bandeau

    private var header: some View {
        EdHeader {
            EdIconButton(
                symbol: "line.3.horizontal",
                label: t("v2.settings.title", "Réglages"),
                action: onOpenSettings
            )
        } trailing: {
            Button(action: onOpenSettings) {
                Circle()
                    .fill(Florin.text)
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Florin.bg)
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(t("v2.settings.title", "Réglages")))
        }
    }

    // MARK: Le patrimoine

    @ViewBuilder
    private var netWorth: some View {
        if let data = model.overview {
            VStack(alignment: .leading, spacing: 8) {
                EdPill(text: t("v2.overview.netWorth", "Patrimoine"))
                EdAmount(
                    text: Money.string(
                        data.netWorth.net, locale: data.localeTag, currency: data.currency
                    )
                )
                Text(
                    Money.string(
                        data.monthlyTrend, locale: data.localeTag, currency: data.currency,
                        signed: true
                    ) + " · " + t("v2.analysis.days30", "30 jours")
                )
                .font(.system(size: 15))
                .foregroundStyle(Florin.text2)
            }
            .padding(.top, 28)
        } else {
            ProgressView()
                .controlSize(.large)
                .tint(Florin.text3)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        }
    }

    // MARK: Les comptes

    /// Ce que la pile montre : les comptes vivants, le plus gros en dernier —
    /// c'est la carte du dessous qui s'ouvre, donc celle qu'on voit en entier.
    private var cards: [Account] {
        (model.overview?.accounts ?? [])
            .filter { !$0.isArchived && $0.isIncludedInNetWorth }
            .sorted { $0.displayValue < $1.displayValue }
            .suffix(3)
    }

    @ViewBuilder
    private var accountsHeading: some View {
        if let data = model.overview, !data.accounts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                EdPill(text: t("v2.nav.accounts", "Comptes"))
                HStack(alignment: .lastTextBaseline) {
                    EdSection(
                        text: t("v2.accounts.title", "Mes comptes"),
                        trailing: "(\(data.accounts.filter { !$0.isArchived }.count))"
                    )
                    Spacer(minLength: 8)
                    Button { addingAccount = true } label: {
                        HStack(spacing: 6) {
                            Text(t("v2.nav.add", "Ajouter"))
                                .font(.system(size: 13))
                                .foregroundStyle(Florin.text)
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Florin.onAccent)
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(Florin.accent))
                        }
                        .padding(.leading, 12)
                        .padding(.trailing, 6)
                        .frame(height: 32)
                        .overlay(Capsule().strokeBorder(Florin.text.opacity(0.28), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 28)
        }
    }

    /*
     * La pile.
     *
     * Chaque carte remonte de 18 pt sur la précédente : on voit la tranche des
     * comptes du dessus et la carte du dessous en entier. Le `zIndex` compte à
     * rebours parce qu'en SwiftUI la dernière vue d'un `VStack` est déjà au
     * sommet — sans ça le chevauchement se ferait dans le mauvais sens et la
     * carte ouverte passerait sous celles qu'elle doit couvrir.
     */
    @ViewBuilder
    private var stack: some View {
        if let data = model.overview, !cards.isEmpty {
            VStack(spacing: -18) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, account in
                    let last = index == cards.count - 1
                    Button(action: onOpenAccounts) {
                        if last {
                            expanded(account, data)
                        } else {
                            folded(account, data, rank: index)
                        }
                    }
                    .buttonStyle(.plain)
                    .zIndex(Double(index))
                }
            }
            .padding(.top, 18)
        }
    }

    /// Une carte repliée : le nom et le solde, le reste sous la suivante.
    private func folded(_ account: Account, _ data: Overview, rank: Int) -> some View {
        // Blanc, puis inverse, puis gris : la maquette fait tourner trois
        // remplissages pour que deux cartes voisines ne se confondent jamais.
        let inverse = rank % 2 == 1
        return HStack {
            Text(account.name)
                .font(.system(size: 15))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(Money.string(
                account.displayValue, locale: data.localeTag, currency: data.currency,
                decimals: false
            ))
            .font(.system(size: 15, weight: .semibold))
            .monospacedDigit()
        }
        .foregroundStyle(inverse ? Florin.bg : Florin.text)
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .top)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: Ed.smallCard, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: Ed.smallCard,
                style: .continuous
            )
            .fill(inverse ? Florin.text : Florin.surface)
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: Ed.smallCard, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: Ed.smallCard,
                style: .continuous
            )
            .strokeBorder(Florin.text.opacity(inverse ? 0 : 0.10), lineWidth: 1)
        )
    }

    /// La carte du bas, ouverte : c'est elle qui porte le total et l'heure de
    /// la dernière synchronisation.
    private func expanded(_ account: Account, _ data: Overview) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text(account.name)
                    .font(.system(size: 15))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(Money.string(
                    account.displayValue, locale: data.localeTag, currency: data.currency,
                    decimals: false
                ))
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("v2.overview.cash", "Liquidités"))
                        .font(.system(size: 12))
                        .opacity(0.85)
                    Text(Money.string(
                        data.allocation.cash, locale: data.localeTag,
                        currency: data.currency, decimals: false
                    ))
                    .font(.system(size: 20, weight: .medium))
                    .monospacedDigit()
                }
                Spacer(minLength: 8)
                Text(syncLine(data))
                    .font(.system(size: 12))
                    .opacity(0.85)
            }
        }
        .foregroundStyle(Florin.onAccent)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Ed.smallCard, style: .continuous)
                .fill(Florin.accent)
        )
    }

    private func syncLine(_ data: Overview) -> String {
        guard let synced = data.lastSynced else {
            return t("v2.overview.neverSynced", "Jamais synchronisé")
        }
        let relative = RelativeDateTimeFormatter()
        relative.locale = Locale(identifier: data.localeTag)
        relative.unitsStyle = .short
        return relative.localizedString(for: synced, relativeTo: Date())
    }
}
