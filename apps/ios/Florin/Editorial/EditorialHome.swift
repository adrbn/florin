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
    @ObservedObject var chrome: ChromeState

    @State private var addingAccount = false
    /// Net ou brut : c'est un choix, pas un réglage d'usine. Il était
    /// repris à `true` à chaque ouverture de l'app, donc reposé à la main
    /// à chaque fois. Les deux écrans lisent la même clé, parce que c'est
    /// la même question posée deux fois.
    @AppStorage("florin.showNet") private var showNet = true
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
    /// Le compte qu'on ouvre. Une carte mène à SON relevé — elle ouvrait
    /// l'onglet Comptes, c'est-à-dire la liste de tous.
    @State private var drill: ActivityRoute?
    /// La place laissée à la pile, lue dans le défilement et rendue à la
    /// couche qui la dessine par-dessus. Voir `stackLayer`.
    @State private var room: CGRect = .zero
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Greeting.key) private var firstName = ""

    private var t: Strings { model.overview?.t ?? .empty }
    private var local: Bool { model.base.scheme == "florin-local" }

    var body: some View {
        NavigationStack {
            page
                .toolbar(.hidden, for: .navigationBar)
                .onChange(of: drill?.id) { _, open in chrome.detailOpen = open != nil }
                .onDisappear { chrome.detailOpen = false }
                .navigationDestination(item: $drill) { target in
                    AccountDetailScreen(model: model, route: target)
                        .toolbar(.hidden, for: .navigationBar)
                }
        }
    }

    /// Le nom de l'espace où la pile lit sa place. Le défilement le pose, le
    /// gabarit transparent s'y mesure, la couche s'y positionne.
    private static let space = "edHomeStack"

    private var page: some View {
        ScrollView {
            if let data = model.overview {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    .id(edTopAnchor)
                    EdHero(text: Greeting.line(t, name: firstName), oneLine: true)
                        .padding(.top, 14)
                    netWorth(data)
                    curve(data)
                    accountsHeading(data)
                    /*
                     * La pile prend ce qui reste, et elle le LIT.
                     *
                     * Elle le calculait : fenêtre moins le haut, moins la
                     * capsule, moins les tranches. Trois mesures à tenir
                     * d'accord, et la dernière carte passait sous la barre
                     * dès que l'une bougeait d'un point. Ici le `GeometryReader`
                     * reçoit l'espace que la disposition lui a laissé — il n'y
                     * a plus de somme à faire juste, donc plus de somme à
                     * faire fausse.
                     */
                    Color.clear
                        .frame(maxHeight: .infinity)
                        .overlay(
                            GeometryReader { g in
                                Color.clear.preference(
                                    key: EdStackRoom.self,
                                    value: g.frame(in: .named(Self.space))
                                )
                            }
                        )
                }
                .padding(.horizontal, Ed.gutter)
                // La capsule flotte à 28 pt du bas sur 60 pt de haut : le
                // contenu s'arrête au-dessus, sans quoi la dernière carte
                // passe dessous.
                .padding(.bottom, 104)
                // Le contenu fait exactement la hauteur de la fenêtre : rien
                // à faire défiler, et le rebond — donc le tirer-pour-
                // rafraîchir — reste entier.
                .containerRelativeFrame(.vertical)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(Florin.text3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
            }
        }
        .edRewind(.overview, chrome: chrome)
        .coordinateSpace(.named(Self.space))
        .onPreferenceChange(EdStackRoom.self) { room = $0 }
        /*
         * La pile se dessine PAR-DESSUS le défilement, pas dedans.
         *
         * Dedans, elle partageait chaque toucher avec le geste de
         * défilement : l'appui long aboutissait, puis le moindre mouvement
         * nourrissait les deux — la carte montait et la page élastiquait
         * sous elle. Couper le défilement à cet instant ne suffisait pas,
         * le geste était déjà engagé.
         *
         * Ici la pile n'est plus dans le défilement du tout. Un gabarit
         * transparent lui garde sa place au même endroit et dit où il est ;
         * la couche se pose exactement dessus. La disposition ne change pas
         * d'un point, et plus rien ne dispute le toucher à la carte.
         *
         * Ce qui se perd : tirer-pour-synchroniser en partant d'une carte.
         * Le haut de l'écran — le chiffre, la courbe — le porte toujours.
         */
        .overlay(alignment: .topLeading) { stackLayer }
        .scrollIndicators(.hidden)
        // Le contenu tient parfois tout entier dans l'écran, et un `ScrollView`
        // qui ne rebondit pas n'offre pas de tirer-pour-rafraîchir : sans ça le
        // geste n'existe que les jours où l'on a beaucoup de comptes.
        .scrollBounceBehavior(.always, axes: .vertical)
        /*
         * Pendant qu'on déplace une carte, la page ne bouge plus.
         *
         * Le rebond vertical reste armé — c'est lui qui porte le tirer-pour-
         * synchroniser — donc l'appui long aboutissait, puis le moindre
         * mouvement nourrissait les deux gestes à la fois : la carte montait
         * et la page élastiquait sous elle. Couper le défilement à l'instant
         * où l'appui aboutit arrive avant que le doigt n'ait bougé, donc
         * avant que le geste de défilement n'ait commencé ; il est annulé, et
         * seule la carte suit le doigt.
         */
        .scrollDisabled(dragging != nil)
        /*
         * Tirer demande à la banque, et le chiffre tourne en attendant.
         *
         * Ici on relisait la base locale : rien ne changeait, rien ne
         * bougeait, et le geste n'avait l'air de rien faire. Obsidienne
         * appelle `refresh()`, qui lance une vraie synchro sans l'attendre —
         * le ressort revient tout de suite et c'est le patrimoine qui porte
         * l'attente, ses chiffres roulant jusqu'à la réponse.
         */
        .refreshable { model.refresh() }
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
                // Les bobines tournent pendant la synchro et se posent une à
                // une — le même mécanisme qu'Obsidienne, dans la typographie
                // d'ici. Jamais sous le doigt : la date change soixante fois
                // par seconde et l'animation, relancée sans cesse, ne finit
                // jamais — c'est elle qu'on verrait tourner, pas le montant.
                SlotReels(
                    value: live, spinning: model.syncing && scrubbed == nil
                ) { rolling in
                    EdAmount(
                        text: Money.string(
                            rolling, locale: data.localeTag, currency: data.currency
                        )
                    )
                }
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
            // La pastille mène à la liste entière. Elle portait déjà le
            // compte ; une ligne « +2 autres » sous la pile disait la même
            // chose pour quarante-quatre points de hauteur, pris à la pile.
            Button(action: onOpenAccounts) {
                EdPill(text: t("v2.nav.accounts", "Comptes") + " · \(live) ›")
            }
            .buttonStyle(.edPress)
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
    /// Ce qu'il faut à la carte menée pour écrire son nom, son montant, sa
    /// part et l'heure de la synchro. En dessous, autant ne pas la déplier.
    private static let minCard: CGFloat = 130

    /*
     * Combien de cartes tiennent, et pas une de plus.
     *
     * C'était une constante — quatre — et un plancher de hauteur. Les deux
     * ensemble font une somme qui peut dépasser la place : quatre tranches de
     * 44 plus 150 de carte menée font 282, quand la courbe n'en laisse que
     * 213. Le plancher gagnait, et la dernière carte passait sous la capsule.
     *
     * Le nombre se déduit maintenant de la place : la menée à son minimum,
     * les autres à une tranche chacune. Ce qui ne tient pas n'est pas rogné,
     * il n'est pas montré — et la pastille du titre y mène.
     */
    private func fitting(_ all: [Account], room: CGSize) -> [Account] {
        guard room.height > 0 else { return Array(all.prefix(Self.shownAtMost)) }
        let slices = Int(((room.height - Self.minCard) / Self.step).rounded(.down))
        let count = max(1, min(Self.shownAtMost, slices + 1))
        return Array(all.prefix(count))
    }

    @ViewBuilder
    private var stackLayer: some View {
        if let data = model.overview, room.height > 0 {
            stack(data, room: room.size)
                .frame(width: room.width, height: room.height, alignment: .top)
                .offset(x: room.minX, y: room.minY)
        }
    }

    @ViewBuilder
    private func stack(_ data: Overview, room: CGSize) -> some View {
        let shown = fitting(cards(data), room: room)
        let height = cardHeight(room: room, stacked: shown.count)
        if !shown.isEmpty {
            // La carte menée est la dernière : posée le plus bas, donc tout en
            // haut de l'ordre d'empilement. L'ordre du `ZStack` le dit déjà,
            // sauf pour celle qu'on tient, qui passe devant.
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
        }
    }

    /// Au format d'une carte bancaire quand la place le permet, et sinon
    /// exactement ce qui reste. `fitting` a déjà garanti que ce reste tient.
    private func cardHeight(room: CGSize, stacked: Int) -> CGFloat {
        let ideal = (room.width > 0 ? room.width : 361) / 1.6
        guard room.height > 0 else { return ideal }
        return max(Self.minCard, min(ideal, room.height - CGFloat(stacked - 1) * Self.step))
    }

    @ViewBuilder
    private func card(
        _ account: Account, _ data: Overview, rank: Int, lead: Bool, height: CGFloat
    ) -> some View {
        let lifted = touched == account.id || dragging == account.id
        Button {
            drill = ActivityRoute(accountId: account.id, title: account.name)
        } label: {
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
                /*
                 * Prioritaire sur le bouton qu'elle habille.
                 *
                 * `.gesture` est examiné APRÈS les gestes de la vue qu'il
                 * enveloppe : le bouton voyait l'appui en premier et gardait
                 * la séquence. Un appui court échoue toujours ici avant 0,45 s
                 * et rend la main au bouton — le clic reste un clic.
                 */
                .highPriorityGesture(
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


/// Où la pile de cartes a le droit de se dessiner.
///
/// Elle vit hors du défilement pour garder ses gestes, mais sa place est
/// décidée par la disposition du défilement. Un gabarit transparent la mesure
/// là-bas et la passe ici ; la dernière mesure gagne, il n'y en a qu'une.
private struct EdStackRoom: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
