import SwiftUI

/*
 * Accueil, dans le langage Éditorial.
 *
 * Les mêmes chiffres que `OverviewScreen` — le même `OverviewModel`, les mêmes
 * requêtes — mais dits autrement : un salut en très grand, le patrimoine sous
 * sa pastille, sa courbe, et la pile de comptes où la carte du dessous est
 * celle qu'on regarde.
 *
 * La page défile, et c'est un retour en arrière assumé.
 *
 * Elle avait été figée pour qu'un accueil tienne d'un coup d'œil, et ce que
 * ça coûtait s'est vu tout de suite : trois comptes sur six, le reste réduit
 * à « +3 autres », et aucun tirer-pour-rafraîchir puisque rien ne défilait.
 * Le haut — salut, chiffre, courbe — tient toujours au-dessus du pli ; les
 * comptes continuent dessous, tous, et c'est le défilement qui les porte.
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
    /// La ligne sous le chiffre répond à deux questions ; celle-ci dit
    /// laquelle — même bascule que sur Obsidienne.
    @State private var showSaving = false
    /// L'ordre posé à la main, le temps que la base se relise.
    @State private var order: [String] = []
    @State private var dragging: String?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Greeting.key) private var firstName = ""

    private var t: Strings { model.overview?.t ?? .empty }
    private var local: Bool { model.base.scheme == "florin-local" }

    var body: some View {
        ScrollView {
            if let data = model.overview {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    EdHero(text: Greeting.line(t, name: firstName), oneLine: true)
                        .padding(.top, 14)
                    netWorth(data)
                    curve(data)
                    accountsHeading(data)
                    stack(data)
                }
                .padding(.horizontal, Ed.gutter)
                // La capsule flotte à 28 pt du bas sur 60 pt de haut : le
                // contenu s'arrête au-dessus, sans quoi la dernière carte
                // passe dessous.
                .padding(.bottom, 104)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(Florin.text3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
            }
        }
        .scrollIndicators(.hidden)
        // Le contenu tient parfois tout entier dans l'écran, et un `ScrollView`
        // qui ne rebondit pas n'offre pas de tirer-pour-rafraîchir : sans ça le
        // geste n'existe que les jours où l'on a beaucoup de comptes.
        .scrollBounceBehavior(.always, axes: .vertical)
        .refreshable { await model.load(showSpinner: false) }
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

    // MARK: Le bandeau

    /// Posé un peu plus bas que la barre d'état : collé en haut, le trait du
    /// menu se lisait comme une partie de l'encoche.
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
        .padding(.top, 18)
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
                    // Pas de chiffres qui roulent sous le doigt : la date
                    // change soixante fois par seconde et l'animation,
                    // relancée à chaque fois, ne finit jamais — c'est elle
                    // qu'on voit tourner au lieu du montant.
                    value: scrubbed == nil ? live : nil
                )
                delta(data)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.edPress)
        .padding(.top, 22)
    }

    /*
     * La ligne sous le chiffre — la même logique qu'Obsidienne, pas une autre.
     *
     * Elle disait « +358,82 € · 30 jours », ce qui n'était ni la mesure de
     * l'autre écran ni une fenêtre que quoi que ce soit calcule : trente
     * jours glissants n'existent nulle part dans le grand livre. Les trois
     * cas sont donc repris tels quels :
     *
     *   — en brut, les dettes, puisque c'est ce que le brut cache ;
     *   — sinon, ce qu'on garde ce mois-ci contre le même jour du mois
     *     dernier, si le registre sait le dire, et un appui bascule ;
     *   — sinon la variation du dernier mois COMPLET, nommé, parce qu'une
     *     légende qui tait le mois invite à le lire comme celui-ci.
     *
     * Sous le doigt, c'est l'écart depuis le premier point de la fenêtre et le
     * jour touché qui s'écrit.
     */
    @ViewBuilder
    private func delta(_ data: Overview) -> some View {
        let points = series(data)
        let first = points.first?.balance ?? data.netWorth.net
        let move = scrubbed.map { $0.balance - first }
            ?? (data.netWorth.net - (data.netWorth.netMonthAgo ?? data.netWorth.net))
        let kept = data.leftToSpend.savedThisMonthToDate

        HStack(spacing: 6) {
            if !showNet, scrubbed == nil {
                Text(t("v2.overview.debt", "Dettes") + " " + Money.string(
                    data.netWorth.liability, locale: data.localeTag,
                    currency: data.currency, decimals: false
                ))
                .foregroundStyle(Florin.text2)
                .hiddenWhenPrivate()
            } else if !data.recent.isEmpty, showSaving, scrubbed == nil, let kept {
                arrow(kept >= 0)
                Text(Money.string(
                    abs(kept), locale: data.localeTag, currency: data.currency,
                    decimals: abs(kept) < 1000
                ))
                .monospacedDigit()
                .foregroundStyle(kept >= 0 ? Florin.positive : Florin.negative)
                .hiddenWhenPrivate()
                Text(data.leftToSpend.savedPrevMonthToDate.map {
                    t("v2.overview.keptVsLastMonth", "vs {prev} ({date})", [
                        "prev": Money.string(
                            $0, locale: data.localeTag,
                            currency: data.currency, decimals: false
                        ),
                        "date": sameDayLastMonth(data),
                    ])
                } ?? t("v2.overview.keptThisMonth", "ce mois-ci"))
                .foregroundStyle(Florin.text2)
            } else if !data.recent.isEmpty {
                arrow(move >= 0)
                Text(Money.string(
                    abs(move), locale: data.localeTag, currency: data.currency,
                    decimals: abs(move) < 1000
                ))
                .monospacedDigit()
                .foregroundStyle(move >= 0 ? Florin.positive : Florin.negative)
                .hiddenWhenPrivate()
                Text(scrubbed.map { dayLabel($0.day, data) }
                    ?? t("v2.overview.inMonth", "en {month}", [
                        "month": MonthLabel.short(
                            LocalQueries.lastCompleteMonth(), locale: data.localeTag
                        ),
                    ]))
                    .foregroundStyle(Florin.text2)
            }
        }
        .font(.system(size: 15))
        .frame(height: 20)
        // La bascule a sa propre cible, à l'intérieur de celle du chiffre :
        // deux questions, deux appuis, sans que le grand nombre perde le sien.
        .contentShape(Rectangle())
        .onTapGesture {
            guard scrubbed == nil, showNet, kept != nil else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(EdMotion.spring) { showSaving.toggle() }
        }
    }

    private func arrow(_ up: Bool) -> some View {
        Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
            .font(.system(size: 9))
            .foregroundStyle(up ? Florin.positive : Florin.negative)
    }

    private func sameDayLastMonth(_ data: Overview) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        let f = DateFormatter()
        f.locale = Locale(identifier: data.localeTag)
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f.string(from: date)
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
     * voir `NetWorthChart` : un simple balayage reste donc au défilement.
     * Les pointillés de prévision sont écartés : c'est l'accueil, pas l'analyse.
     */
    private func series(_ data: Overview) -> [PatrimonyPoint] {
        Array(
            (showNet ? (data.netSeries ?? data.series) : (data.grossSeries ?? data.series))
                .filter { $0.projected != true }
                .suffix(200)
        )
    }

    @ViewBuilder
    private func curve(_ data: Overview) -> some View {
        let points = series(data)
        if points.count > 2 {
            NetWorthChart(
                points: points,
                height: 88,
                selection: $scrubbed,
                animationKey: showNet ? "net" : "gross",
                tint: Florin.text
            )
            .padding(.top, 16)
            .padding(.bottom, 10)
        }
    }

    // MARK: Les comptes

    /// Tous les comptes vivants, dans l'ordre posé à la main.
    ///
    /// `display_order` est ce que la base trie déjà ; l'ordre local ne sert
    /// qu'entre le lâcher de la carte et la relecture qui suit.
    private func cards(_ data: Overview) -> [Account] {
        let live = data.accounts.filter { !$0.isArchived && $0.isIncludedInNetWorth }
        guard !order.isEmpty else { return live }
        let byId = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })
        let placed = order.compactMap { byId[$0] }
        // Un compte apparu depuis le glissement reste visible, à la fin.
        return placed + live.filter { !order.contains($0.id) }
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
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    /*
     * La pile, dans un tiroir.
     *
     * Toutes les cartes à plat, c'était six boîtes trapues empilées sur une
     * page qui n'en tient pas six — la dernière passait sous la barre et le
     * chevauchement, étalé, ne ressemblait plus à une pile mais à une liste
     * mal cadrée.
     *
     * Le tiroir rend la forme d'origine : des cartes qui se recouvrent, dont
     * on ne voit que la tranche, et celle du bas ouverte. Ce qui ne tient pas
     * dans sa hauteur n'est pas supprimé, il défile — le tiroir s'ouvre sur
     * le bas, donc la carte ouverte est là d'emblée et les autres remontent
     * en se fondant dans le haut.
     *
     * Le `zIndex` compte à l'endroit, sauf la carte tenue qui passe au-dessus
     * de toutes : sinon on la voit glisser SOUS la pile qu'elle traverse.
     */
    @ViewBuilder
    private func stack(_ data: Overview) -> some View {
        let shown = cards(data)
        if !shown.isEmpty {
            ScrollView {
                VStack(spacing: -Self.overlap) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, account in
                        card(account, data, rank: index, last: index == shown.count - 1)
                            .zIndex(dragging == account.id ? 1000 : Double(index))
                    }
                }
                .animation(EdMotion.spring, value: shown.map(\.id))
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(dragging != nil)
            // Ouvert sur le bas : la carte dépliée est ce qu'on vient voir.
            .defaultScrollAnchor(.bottom)
            .frame(height: drawerHeight(shown.count))
            /*
             * Un fondu, pas une coupe.
             *
             * Le haut du tiroir tranche au milieu d'une carte — un bord net y
             * ressemble à un défaut d'affichage. Le dégradé dit « ça continue
             * au-dessus », ce qui est précisément l'information.
             */
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.16),
                        .init(color: .black, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
    }

    /// Le chevauchement, et le pas du glissement : les deux sont le même
    /// nombre, et les séparer fait sauter la carte d'un cran de trop.
    private static let overlap: CGFloat = 18
    private static let foldedHeight: CGFloat = 70

    /// Trois cartes au plus dans le tiroir — au-delà, la page a mieux à faire
    /// de sa hauteur, et le reste est à un doigt de défilement.
    private func drawerHeight(_ count: Int) -> CGFloat {
        let folds = CGFloat(min(count, 3) - 1)
        return folds * (Self.foldedHeight - Self.overlap) + 126
    }

    @ViewBuilder
    private func card(
        _ account: Account, _ data: Overview, rank: Int, last: Bool
    ) -> some View {
        let held = dragging == account.id
        Button(action: onOpenAccounts) {
            if last {
                expanded(account, data)
            } else {
                folded(account, data, rank: rank)
            }
        }
        .buttonStyle(.edPress)
        .scaleEffect(held ? 1.03 : 1)
        .animation(EdMotion.spring, value: held)
        .modifier(
            EdReorder(
                enabled: local,
                id: account.id,
                step: Self.foldedHeight - Self.overlap,
                dragging: $dragging,
                order: Binding(
                    get: { cards(data).map(\.id) },
                    set: { next in
                        order = next
                        let byId = Dictionary(
                            uniqueKeysWithValues: data.accounts.map { ($0.id, $0) }
                        )
                        AccountsLogic.reorder(next.compactMap { byId[$0] })
                    }
                )
            )
        )
    }

    /// Une carte repliée : le nom et le solde, le reste sous la suivante.
    private func folded(_ account: Account, _ data: Overview, rank: Int) -> some View {
        // Blanc, puis inverse : la maquette fait alterner les remplissages
        // pour que deux cartes voisines ne se confondent jamais.
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
            .hiddenWhenPrivate()
        }
        .foregroundStyle(inverse ? Florin.bg : Florin.text)
        .padding(.horizontal, 18)
        .padding(.top, 15)
        .frame(maxWidth: .infinity, minHeight: Self.foldedHeight, alignment: .top)
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

    /// La carte du bas, ouverte : c'est elle qui porte les liquidités et
    /// l'heure de la dernière synchronisation.
    private func expanded(_ account: Account, _ data: Overview) -> some View {
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
                .hiddenWhenPrivate()
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
                    .hiddenWhenPrivate()
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
        /*
         * Jamais « dans 0 s ».
         *
         * L'horodatage vient du serveur ; à la seconde où la synchro finit il
         * peut tomber une fraction DANS L'AVENIR, et le formateur, lui, dit
         * alors « dans 0 s ». On le recule d'une minute : le pire affichage
         * devient « il y a 1 min », qui est vrai à la minute près.
         */
        let moment = min(synced, Date().addingTimeInterval(-60))
        return relative.localizedString(for: moment, relativeTo: Date())
    }
}

/*
 * Tenir une carte, la déplacer, la lâcher ailleurs.
 *
 * Pas `List` et son `onMove` : cette pile se chevauche, et une liste refait
 * des lignes séparées. Pas `draggable`/`dropDestination` non plus — ils
 * passent par le presse-papiers du système et montrent un aperçu gris qui
 * n'est pas la carte.
 *
 * Un appui maintenu d'une demi-seconde PUIS un glissement : la séquence est
 * ce qui permet au défilement de garder tous les balayages ordinaires. La
 * place visée se déduit de la distance parcourue divisée par la hauteur d'un
 * cran — on ne mesure pas les autres cartes, on sait de combien elles sont
 * décalées.
 */
private struct EdReorder: ViewModifier {
    let enabled: Bool
    let id: String
    /// Le pas de la pile : la hauteur d'une carte repliée moins son
    /// chevauchement. Il vient de l'appelant, qui pose les deux.
    let step: CGFloat
    @Binding var dragging: String?
    @Binding var order: [String]

    @State private var shift: CGSize = .zero

    func body(content: Content) -> some View {
        if enabled {
            content
                .offset(shift)
                .gesture(
                    LongPressGesture(minimumDuration: 0.45)
                        .sequenced(before: DragGesture(coordinateSpace: .local))
                        .onChanged { value in
                            guard case let .second(true, drag?) = value else {
                                if dragging != id { haptic() }
                                dragging = id
                                return
                            }
                            shift = CGSize(width: 0, height: drag.translation.height)
                        }
                        .onEnded { _ in
                            move(by: Int((shift.height / step).rounded()))
                            shift = .zero
                            dragging = nil
                        }
                )
        } else {
            content
        }
    }

    private func haptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func move(by steps: Int) {
        guard steps != 0, let from = order.firstIndex(of: id) else { return }
        let to = min(max(from + steps, 0), order.count - 1)
        guard to != from else { return }
        var next = order
        next.remove(at: from)
        next.insert(id, at: to)
        UISelectionFeedbackGenerator().selectionChanged()
        order = next
    }
}
