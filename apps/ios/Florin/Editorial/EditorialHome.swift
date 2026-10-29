import SwiftUI

/*
 * Accueil, dans le langage Éditorial.
 *
 * Les mêmes chiffres que `OverviewScreen` — le même `OverviewModel`, les mêmes
 * requêtes — mais dits autrement : un salut en très grand, le patrimoine sous
 * sa pastille, sa courbe, et la pile de comptes où la carte du dessous est
 * celle qu'on regarde.
 *
 * La page ne défile pas, et pourtant on tire pour rafraîchir.
 *
 * Les deux vont ensemble : c'est un `ScrollView` dont le contenu tient tout
 * entier dans l'écran. Il n'y a donc rien à faire défiler, mais le rebond
 * existe — et le rebond est ce que `refreshable` écoute. Interdire le
 * défilement pour de bon (`scrollDisabled`) emporterait le geste avec lui.
 *
 * « Tenir dans l'écran » n'est pas une espérance : la pile mesure la place
 * qui lui reste et s'y taille. Voir `stack`.
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
    /// La carte sous le doigt. Elle se soulève, les autres s'effacent.
    @State private var touched: String?
    /// Ce que mesurent les deux lecteurs de géométrie : la hauteur de tout ce
    /// qui précède la pile, et celle de la fenêtre. La pile prend la
    /// différence — c'est ce qui garantit qu'il n'y a jamais à défiler.
    @State private var chromeHeight: CGFloat = 0
    @State private var viewport: CGSize = .zero
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Greeting.key) private var firstName = ""

    private var t: Strings { model.overview?.t ?? .empty }
    private var local: Bool { model.base.scheme == "florin-local" }

    var body: some View {
        ScrollView {
            if let data = model.overview {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        EdHero(text: Greeting.line(t, name: firstName), oneLine: true)
                            .padding(.top, 14)
                        netWorth(data)
                        curve(data)
                        accountsHeading(data)
                    }
                    .background(
                        GeometryReader { chrome in
                            Color.clear.preference(
                                key: EdChromeHeight.self, value: chrome.size.height
                            )
                        }
                    )
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
        // Le fond mesure la fenêtre : l'arrière-plan d'un `ScrollView` a la
        // taille de ce qu'on en voit, jamais celle de son contenu.
        .background(
            GeometryReader { window in
                Florin.bg.preference(key: EdViewport.self, value: window.size)
            }
        )
        .onPreferenceChange(EdChromeHeight.self) { chromeHeight = $0 }
        .onPreferenceChange(EdViewport.self) { viewport = $0 }
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
     * La pile, comme un portefeuille.
     *
     * Le tiroir à fondu réglait la hauteur en créant deux défauts : une carte
     * tranchée en deux par le haut du tiroir, et un défilement vertical de
     * plus sur une page qui en avait déjà un. Des tranches serrées n'ont ni
     * l'un ni l'autre — mais elles ont une contrainte dure, et c'est elle qui
     * fixe tout le reste.
     *
     * UNE TRANCHE FAIT 44 PT, le minimum d'une cible tactile. Apple Wallet
     * s'autorise moins, parce qu'y toucher OUVRE la pile : rater sa carte n'y
     * coûte rien, on retape. Ici un appui navigue, donc rater coûte un
     * mauvais compte — la tranche ne peut pas descendre sous le doigt.
     *
     * De là tombe le nombre. Le pas est fixé par le doigt, la hauteur par un
     * écran qui ne défile pas : quatre cartes est ce qui reste, pas un choix
     * de goût. Les autres sont à un appui, sur la ligne qui suit la pile.
     */
    private static let step: CGFloat = 44
    private static let shownAtMost = 4

    @ViewBuilder
    private func stack(_ data: Overview) -> some View {
        let all = cards(data)
        let shown = Array(all.prefix(Self.shownAtMost))
        let rest = all.count - shown.count
        let height = cardHeight(stacked: shown.count, rest: rest > 0)
        if !shown.isEmpty {
            // La carte menée est la dernière : posée le plus bas, donc tout en
            // haut de l'ordre d'empilement. L'ordre du `ZStack` le dit déjà,
            // sauf pour celle qu'on tient, qui doit passer devant toutes.
            ZStack(alignment: .top) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, account in
                    card(
                        account, data,
                        rank: index, lead: index == shown.count - 1, height: height
                    )
                    .offset(y: CGFloat(index) * Self.step)
                    .zIndex(dragging == account.id ? 1000 : Double(index))
                }
            }
            .frame(
                height: height + CGFloat(shown.count - 1) * Self.step,
                alignment: .top
            )
            .animation(EdMotion.spring, value: shown.map(\.id))

            if rest > 0 { more(rest) }
        }
    }

    /*
     * La hauteur d'une carte, qui est le seul réglage de toute la page.
     *
     * Au format d'une carte bancaire (1,6) quand la place le permet, et sinon
     * exactement ce qui reste : fenêtre moins le haut, moins les tranches des
     * cartes repliées, moins la place de la capsule. Tant qu'une mesure
     * manque on prend l'idéal — un écran de plus ou de moins pendant la
     * première passe de calcul, puis plus jamais.
     */
    private func cardHeight(stacked: Int, rest: Bool) -> CGFloat {
        let width = (viewport.width > 0 ? viewport.width : 393) - 2 * Ed.gutter
        let ideal = width / 1.6
        guard viewport.height > 0, chromeHeight > 0 else { return ideal }
        let free = viewport.height
            - chromeHeight
            - CGFloat(stacked - 1) * Self.step
            - (rest ? 44 : 0)
            - 104
        // Jamais moins que ce qu'il faut pour écrire un nom et un montant.
        return max(150, min(ideal, free))
    }

    @ViewBuilder
    private func card(
        _ account: Account, _ data: Overview, rank: Int, lead: Bool, height: CGFloat
    ) -> some View {
        let lifted = touched == account.id || dragging == account.id
        Button(action: onOpenAccounts) {
            face(account, data, rank: rank, lead: lead, open: lifted || lead)
                .frame(height: height)
        }
        /*
         * L'appui se lit sur le style, pas sur un geste.
         *
         * Un `DragGesture(minimumDistance: 0)` sur la carte dirait la même
         * chose et volerait le tirer-pour-rafraîchir dès que le doigt commence
         * sur une carte. `isPressed` d'un `ButtonStyle` s'annule tout seul
         * quand le défilement prend la main : c'est le seul signal d'appui qui
         * ne se batte avec rien.
         */
        .buttonStyle(EdLift { pressed in touched = pressed ? account.id : nil })
        .offset(y: lifted ? -14 : 0)
        .scaleEffect(lifted ? 1.02 : 1)
        // Celle qu'on tient reste pleine, les autres reculent : c'est ce
        // recul qui dit « celle-là », plus sûrement que le soulèvement seul.
        .opacity(touched == nil || lifted ? 1 : 0.55)
        .animation(EdMotion.spring, value: lifted)
        .animation(EdMotion.spring, value: touched)
        .modifier(
            EdReorder(
                enabled: local,
                id: account.id,
                step: Self.step,
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

    /*
     * Le visage d'une carte.
     *
     * Le nom et le montant tiennent dans les 44 pt du haut — la seule bande
     * qu'on voit d'une carte repliée. Le reste n'apparaît que sur la carte
     * menée, ou sur celle qu'on soulève.
     */
    private func face(
        _ account: Account, _ data: Overview, rank: Int, lead: Bool, open: Bool
    ) -> some View {
        // Blanc, puis inverse : deux cartes voisines ne se confondent jamais.
        let inverse = !lead && rank % 2 == 1
        let ink: Color = lead ? Florin.onAccent : (inverse ? Florin.bg : Florin.text)
        let total = max(abs(data.netWorth.gross), 1)
        let share = Int((abs(account.displayValue) / total * 100).rounded())

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
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
            .frame(height: Self.step - 18, alignment: .center)

            VStack(alignment: .leading, spacing: 10) {
                if lead {
                    Text(Money.string(
                        data.allocation.cash, locale: data.localeTag,
                        currency: data.currency, decimals: false
                    ))
                    .font(.system(size: 26, weight: .medium))
                    .monospacedDigit()
                    .hiddenWhenPrivate()
                }
                Spacer(minLength: 0)
                EdShare(share: share, ink: ink)
                HStack(spacing: 8) {
                    Text("\(share)%")
                        .monospacedDigit()
                    Text(lead
                        ? syncLine(data)
                        : (account.isSynced == true
                            ? t("v2.accounts.synced", "Synchronisé")
                            : t("v2.accounts.manual", "Saisie manuelle")))
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 12))
                .opacity(0.85)
            }
            .opacity(open ? 1 : 0)
            .animation(EdMotion.spring, value: open)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Ed.smallCard, style: .continuous)
                .fill(lead ? Florin.accent : (inverse ? Florin.text : Florin.surface))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Ed.smallCard, style: .continuous)
                .strokeBorder(
                    Florin.text.opacity(lead || inverse ? 0 : 0.10), lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(open && !lead ? 0.18 : 0), radius: 18, y: 10)
    }

    /// Ce que la pile ne montre pas. La hauteur du doigt, pas celle du texte.
    private func more(_ count: Int) -> some View {
        Button(action: onOpenAccounts) {
            HStack(spacing: 6) {
                Text(t("v2.overview.moreAccounts", "+{count} autres", [
                    "count": "\(count)",
                ]))
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 13))
            .foregroundStyle(Florin.text2)
            .frame(height: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.edPress)
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

/// La hauteur de tout ce qui précède la pile, et celle de la fenêtre. Deux
/// mesures, deux clés : la pile prend ce que l'une laisse à l'autre.
private struct EdChromeHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct EdViewport: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// Un style qui ne fait rien d'autre que dire quand on appuie. La carte, elle,
/// se soulève depuis l'état — et pas en se rétrécissant comme `EdPress`, qui
/// dirait l'inverse de ce qu'on veut montrer.
private struct EdLift: ButtonStyle {
    let onPress: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in onPress(pressed) }
    }
}

/// La part du patrimoine, de la couleur de l'encre de la carte : sur fond
/// accent comme sur fond blanc, une barre qui emprunte le texte est lisible.
private struct EdShare: View {
    let share: Int
    let ink: Color

    var body: some View {
        GeometryReader { bar in
            ZStack(alignment: .leading) {
                Capsule().fill(ink.opacity(0.22))
                Capsule()
                    .fill(ink)
                    .frame(width: bar.size.width * min(max(CGFloat(share) / 100, 0.01), 1))
            }
        }
        .frame(height: 3)
    }
}
