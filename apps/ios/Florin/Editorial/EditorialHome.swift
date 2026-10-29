import SwiftUI

/*
 * Accueil, dans le langage Éditorial.
 *
 * Les mêmes chiffres que `OverviewScreen` — le même `OverviewModel`, les mêmes
 * requêtes — mais dits autrement : un salut en très grand, le patrimoine sous
 * sa pastille, sa courbe, et la pile de comptes où la carte du dessous est
 * celle qu'on regarde.
 *
 * Cet écran ne défile pas.
 *
 * C'est une contrainte, pas un oubli : un accueil est une réponse d'un coup
 * d'œil, et ce qui passe sous le pli n'est pas une réponse. La courbe ajoutée
 * sous le chiffre a fait passer les cartes sous la barre d'onglets — la
 * réponse n'est pas d'autoriser le défilement mais de faire tenir la page. Un
 * `ViewThatFits` essaie trois, puis deux, puis une carte : c'est le système qui
 * mesure, pas une addition de constantes qui serait fausse sur un autre
 * téléphone, à une autre taille de texte.
 *
 * Rien ici ne lit la base : tout vient du modèle que l'ancien écran lit déjà.
 */
struct EditorialHome: View {
    @ObservedObject var model: OverviewModel
    let onOpenSettings: () -> Void
    let onOpenAccounts: () -> Void

    @State private var addingAccount = false
    /// Net ou brut : le chiffre bascule au doigt, comme sur l'écran Comptes.
    @State private var showNet = true
    /// Le point sous le doigt sur la courbe. Tant qu'il y en a un, le chiffre
    /// du haut dit ce jour-là plutôt qu'aujourd'hui.
    @State private var scrubbed: PatrimonyPoint?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Greeting.key) private var firstName = ""

    private var t: Strings { model.overview?.t ?? .empty }

    var body: some View {
        Group {
            if let data = model.overview {
                ViewThatFits(in: .vertical) {
                    page(data, cards: 3)
                    page(data, cards: 2)
                    page(data, cards: 1)
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(Florin.text3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Florin.bg)
        /*
         * C'est l'écran qui demande les chiffres, pas le modèle qui s'éveille.
         *
         * `OverviewModel` ne charge rien tout seul : `OverviewScreen` l'appelait
         * ici, et l'écran éditorial s'est installé à sa place sans reprendre le
         * geste — d'où un « Bonjour » suivi d'un rond qui tourne pour toujours.
         * Le retour d'arrière-plan compte aussi : c'est le moment où les
         * chiffres ont le plus de chances d'être périmés.
         */
        .task { await model.onForeground() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.onForeground() } }
        }
        .sheet(isPresented: $addingAccount) {
            AddAccountSheet(t: t, onSaved: { Task { await model.load() } })
                .edSheet()
        }
    }

    /// La page entière avec un nombre de cartes donné — `ViewThatFits` garde
    /// la première version qui tient.
    private func page(_ data: Overview, cards count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            EdHero(text: Greeting.line(t, name: firstName), oneLine: true)
                .padding(.top, 14)
            netWorth(data)
            curve(data)
            Spacer(minLength: 12)
            accountsHeading(data)
            stack(data, count: count)
        }
        .padding(.horizontal, Ed.gutter)
        .padding(.top, 10)
        // La capsule flotte à 28 pt du bas sur 60 pt de haut : le contenu
        // s'arrête au-dessus, sans quoi la dernière carte passe dessous.
        .padding(.bottom, 104)
        .frame(maxHeight: .infinity, alignment: .top)
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
            EdIconButton(
                symbol: "arrow.trianglehead.2.clockwise",
                label: t("v2.common.refresh", "Actualiser"),
                spinning: model.syncing
            ) {
                Task { await model.sync(confirmCurrent: false) }
            }
            .disabled(model.syncing || !(model.overview?.bankSyncConfigured ?? false))
            .padding(.trailing, -10)
        }
    }

    // MARK: Le patrimoine

    /*
     * Un chiffre qui répond à deux questions et à une date.
     *
     * Au doigt il passe du net au brut — la même bascule que l'écran Comptes,
     * parce que c'est la même question posée au même endroit. Et tant qu'un
     * point de la courbe est tenu, il dit ce jour-là : lire une courbe sans
     * pouvoir en nommer un point revient à regarder une forme.
     */
    private func netWorth(_ data: Overview) -> some View {
        let live = scrubbed?.balance
            ?? (showNet ? data.netWorth.net : data.netWorth.gross)
        return Button {
            guard scrubbed == nil else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(EdMotion.spring) { showNet.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                EdPill(text: scrubbed.map { dayLabel($0.day, data) }
                    ?? (showNet
                        ? t("v2.overview.netWorth", "Patrimoine")
                        : t("v2.overview.gross", "Brut")))
                EdAmount(
                    text: Money.string(
                        live, locale: data.localeTag, currency: data.currency
                    ),
                    value: live
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.edPress)
        .padding(.top, 22)
    }

    private func dayLabel(_ day: Date, _ data: Overview) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: data.localeTag)
        f.setLocalizedDateFormatFromTemplate("d MMM y")
        return f.string(from: day)
    }

    /*
     * La courbe, sous le chiffre, et on peut la toucher.
     *
     * Le scrub passe par `chartXSelection` et démarre sur un appui maintenu —
     * voir `NetWorthChart` : un simple balayage reste donc au swipe d'onglet.
     * Les pointillés de prévision sont écartés : c'est l'accueil, pas l'analyse.
     */
    @ViewBuilder
    private func curve(_ data: Overview) -> some View {
        let points = Array(
            (showNet ? (data.netSeries ?? data.series) : (data.grossSeries ?? data.series))
                .filter { $0.projected != true }
                .suffix(200)
        )
        if points.count > 2 {
            NetWorthChart(
                points: points,
                height: 88,
                selection: $scrubbed,
                animationKey: showNet ? "net" : "gross",
                tint: Florin.text
            )
            .padding(.top, 16)
        }
    }

    // MARK: Les comptes

    /// Ce que la pile montre : les comptes vivants, le plus gros en dernier —
    /// c'est la carte du dessous qui s'ouvre, donc celle qu'on voit en entier.
    private func cards(_ data: Overview, count: Int) -> [Account] {
        Array(
            data.accounts
                .filter { !$0.isArchived && $0.isIncludedInNetWorth }
                .sorted { $0.displayValue < $1.displayValue }
                .suffix(count)
        )
    }

    /*
     * Une seule fois le mot « Comptes ».
     *
     * La pastille et le titre disaient la même chose l'un sous l'autre, à deux
     * corps différents, et mangeaient soixante points pour le répéter. Reste la
     * pastille, qui porte le compte, et le bouton qui ajoute.
     */
    private func accountsHeading(_ data: Overview) -> some View {
        let live = data.accounts.filter { !$0.isArchived }.count
        return HStack(alignment: .center, spacing: 8) {
            EdPill(text: t("v2.nav.accounts", "Comptes") + " · \(live)")
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
            .buttonStyle(.edPress)
        }
        .padding(.bottom, 12)
    }

    /*
     * La pile.
     *
     * Chaque carte remonte de 18 pt sur la précédente : on voit la tranche des
     * comptes du dessus et la carte du dessous en entier. Le `zIndex` compte à
     * rebours parce qu'en SwiftUI la dernière vue d'un `VStack` est déjà au
     * sommet — sans ça le chevauchement se ferait dans le mauvais sens et la
     * carte ouverte passerait sous celles qu'elle doit couvrir.
     *
     * La pile ne montre jamais tous les comptes : elle en montre autant que la
     * page en tient, et la carte ouverte dit combien restent derrière. Les voir
     * tous est le travail de l'écran Comptes, où l'on arrive en touchant
     * n'importe laquelle.
     */
    @ViewBuilder
    private func stack(_ data: Overview, count: Int) -> some View {
        let shown = cards(data, count: count)
        let hidden = data.accounts.filter { !$0.isArchived && $0.isIncludedInNetWorth }.count
            - shown.count
        if !shown.isEmpty {
            VStack(spacing: -18) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, account in
                    let last = index == shown.count - 1
                    Button(action: onOpenAccounts) {
                        if last {
                            expanded(account, data, more: hidden)
                        } else {
                            folded(account, data, rank: index)
                        }
                    }
                    .buttonStyle(.edPress)
                    .zIndex(Double(index))
                }
            }
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
        .padding(.top, 15)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .top)
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

    /// La carte du bas, ouverte : c'est elle qui porte les liquidités, l'heure
    /// de la dernière synchronisation, et le nombre de comptes qu'on ne voit
    /// pas — sans quoi une pile de trois sur huit comptes ment par omission.
    private func expanded(
        _ account: Account, _ data: Overview, more: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
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
                VStack(alignment: .trailing, spacing: 2) {
                    if more > 0 {
                        Text(t("v2.overview.moreAccounts", "+{count} autres",
                               ["count": more]))
                            .font(.system(size: 12, weight: .medium))
                    }
                    Text(syncLine(data))
                        .font(.system(size: 12))
                        .opacity(0.85)
                }
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
