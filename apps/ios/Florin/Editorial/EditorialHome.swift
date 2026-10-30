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
    /// Noter une opération depuis les quatre gestes. `income` dit laquelle
    /// des deux : la feuille s'ouvre sur « reçu » ou sur « dépense ».
    @State private var addingTx = false
    @State private var income = false
    /// Les comptes écartés de la pile, choisis compte par compte dans
    /// Comptes. Voir `HomeCards`.
    @AppStorage(HomeCards.key) private var hiddenCards = ""
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
    /// La carte mise en avant.
    ///
    /// Dans une pile, une carte est à moitié couverte par la suivante : on
    /// lit son nom, rarement son montant. Un premier appui la fait passer
    /// devant et se soulever — on la voit en entier. Le second l'ouvre.
    /// Deux appuis, parce qu'un seul demanderait de choisir entre lire et
    /// ouvrir.
    @State private var raised: String?
    /// Le compte qu'on ouvre. Une carte mène à SON relevé — elle ouvrait
    /// l'onglet Comptes, c'est-à-dire la liste de tous.
    @State private var drill: ActivityRoute?
    /// Ce que le premier écran a déjà rendu de sa marge du bas. Voir
    /// `EdFirstScreenTop`.
    @State private var lift: CGFloat = 0
    /// Où le haut du premier écran se trouve au repos — l'origine dont `lift`
    /// est la distance.
    @State private var top0: CGFloat?
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
                // Un appui sur l'onglet déjà ouvert dépile d'abord.
                .onReceive(
                    NotificationCenter.default.publisher(for: .florinTabReselected)
                ) { note in
                    guard note.object as? TabRoute == .overview, drill != nil else { return }
                    drill = nil
                }
                .navigationDestination(item: $drill) { target in
                    AccountDetailScreen(model: model, route: target)
                        .toolbar(.hidden, for: .navigationBar)
                        .edSwipeBack { drill = nil }
                }
        }
    }

    private var page: some View {
        ScrollView {
            if let data = model.overview {
                VStack(alignment: .leading, spacing: 0) {
                    /*
                     * Le premier écran, à la hauteur de l'écran.
                     *
                     * Le salut, le chiffre, la courbe et la pile tiennent
                     * dans la fenêtre sans défiler : c'est ce qu'on voit en
                     * ouvrant l'app, et on n'a rien à faire pour le voir.
                     * Ce qui suit se lit en descendant.
                     */
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        .id(edTopAnchor)
                        // Chaque bloc du premier écran sort de la vue pour son
                        // propre compte : le chiffre, la courbe et la ligne des
                        // comptes ne partent pas d'un seul tenant.
                        netWorth(data).edEnter()
                        curve(data).edEnter()
                        accountsHeading(data).edEnter()
                        /*
                         * La pile prend ce qui reste, et elle le LIT.
                         *
                         * Elle le calculait : fenêtre moins le haut, moins la
                         * capsule, moins les tranches. Trois mesures à tenir
                         * d'accord, et la dernière carte passait sous la barre
                         * dès que l'une bougeait d'un point. Ici le
                         * `GeometryReader` reçoit l'espace que la disposition
                         * lui a laissé — il n'y a plus de somme à faire juste,
                         * donc plus de somme à faire fausse.
                         *
                         * Elle vit de nouveau DANS le défilement : elle en
                         * était sortie pour garder le toucher de l'appui long
                         * qui déplaçait une carte, et ce geste a été retiré.
                         * Un appui simple ne dispute rien au défilement, et
                         * une pile posée en surimpression ne saurait pas où se
                         * dessiner dès que la page descend.
                         */
                        GeometryReader { g in
                            stack(data, room: g.size)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    /*
                     * L'écart se referme en descendant, et s'arrête à l'écart
                     * du dessous.
                     *
                     * Au repos il vaut `breathe` : la capsule flotte devant, et
                     * les quatre gestes doivent rester CACHÉS derrière elle —
                     * sinon on voit dépasser le haut de quatre tuiles qui ne
                     * font pas partie du premier écran. Dès qu'on descend, la
                     * capsule n'est plus devant eux et ces points deviennent un
                     * trou : ils se rendent au fil du doigt.
                     *
                     * Mais pas jusqu'à zéro. Les gestes ont 44 pt sous eux
                     * avant « Ce mois-ci » ; ils en gardent donc 44 au-dessus,
                     * et la rangée se pose au milieu de son blanc au lieu
                     * d'être collée à la dernière carte.
                     *
                     * Les deux mesures vont ensemble : le cadre perd `lift`
                     * (c'est lui qui fait remonter la suite — un
                     * `containerRelativeFrame` FIXE la hauteur, rogner la seule
                     * marge ne rendrait la place qu'à la pile) et la marge perd
                     * `lift` aussi, pour que la pile garde sa hauteur.
                     */
                    .padding(.bottom, Self.breathe - lift)
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(
                                key: EdFirstScreenTop.self,
                                value: -g.frame(in: .named(Self.space)).minY
                            )
                        }
                    )
                    .containerRelativeFrame(.vertical, alignment: .top) { height, _ in
                        height - lift
                    }

                    // MARK: Ce qui se lit en descendant

                    EdActions(
                        t: t,
                        syncing: model.syncing,
                        canSync: data.bankSyncConfigured,
                        onExpense: { income = false; addingTx = true },
                        onIncome: { income = true; addingTx = true },
                        onSync: { Task { await model.sync(confirmCurrent: false) } },
                        onAccounts: onOpenAccounts
                    )
                    // Pas d'`edEnter` sur cette rangée : elle se rapproche des
                    // cartes au fil du défilement (voir `lift`), et un bloc
                    // qui apparaît en fondu cache le mouvement qu'il fait.
                    .padding(.bottom, 44)

                    EdMonthSplit(data: data)
                        .edEnter()
                        .padding(.bottom, 44)

                    EdMonthEnd(data: data)
                        .edEnter()
                        .padding(.bottom, 44)

                    EdAllocation(data: data)
                        .edEnter()
                        .padding(.bottom, 44)

                    EdSavings(data: data)
                        .edEnter()
                }
                .padding(.horizontal, Ed.gutter)
                .padding(.bottom, 104)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(Florin.text3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
            }
        }
        .coordinateSpace(name: Self.space)
        /*
         * L'écart se referme point par point, depuis là où il commence.
         *
         * `y` était pris pour la distance parcourue, alors que c'est une
         * position : selon ce que la zone sûre ajoute au-dessus, elle ne part
         * pas de zéro, et il fallait défiler soixante points pour rien avant
         * que l'écart ne commence à bouger — on ne voyait donc PAS la rangée
         * se rapprocher des cartes. La première valeur lue devient l'origine,
         * et le reste est un déplacement.
         *
         * Par pas de six points : assez fin pour qu'on le lise comme un
         * mouvement, assez gros pour ne pas refaire la page à chaque image.
         */
        .onPreferenceChange(EdFirstScreenTop.self) { y in
            let origin = top0 ?? y
            if top0 == nil { top0 = y }
            let next = min(Self.maxLift, max(0, ((y - origin) / 6).rounded() * 6))
            if next != lift { lift = next }
        }
        // Une opération notée depuis l'accueil doit se voir dans le
        // patrimoine et les cartes, pas seulement dans Activité.
        .reloadsOnLedgerChange { await model.load(showSpinner: false) }
        .edRewind(.overview, chrome: chrome)
        .scrollIndicators(.hidden)
        .edPlainEdges()
        // Le contenu tient parfois tout entier dans l'écran, et un `ScrollView`
        // qui ne rebondit pas n'offre pas de tirer-pour-rafraîchir : sans ça le
        // geste n'existe que les jours où l'on a beaucoup de comptes.
        .scrollBounceBehavior(.always, axes: .vertical)
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
        .sheet(isPresented: $addingTx) {
            if let data = model.overview {
                AddTransactionSheet(
                    accounts: data.accounts,
                    categories: data.categories,
                    localeTag: data.localeTag,
                    currency: data.currency,
                    t: t,
                    submit: { try await model.add($0) },
                    onTransfer: { try await model.addTransfer($0) },
                    onInstalments: { try await model.addInstalments($0) },
                    isLocalLedger: local,
                    presetIncome: income
                )
                .edSheet()
            }
        }
    }

    // MARK: Le bandeau

    /*
     * Le salut EST le bandeau.
     *
     * Il était en dessous, en très grand, et le bandeau au-dessus de lui ne
     * portait que deux boutons : une rangée de 44 pt dont la gauche était
     * vide, pour cent points de haut avant le premier mot de la page. Le
     * salut vient donc à la hauteur des deux gestes, au corps qui tient sur
     * leur ligne — ce sont eux qui sont fixés, c'est lui qui se range.
     *
     * Et il s'arrête avant eux : la rangée lui laisse le vide à DROITE, qui
     * est ce qui dit qu'un bloc de texte est aligné à gauche.
     */
    private var header: some View {
        EdHeader(alignment: .top) {
            // Deux lignes plutôt qu'une réduite : « Bonsoir » tient à côté des
            // boutons, le prénom passe dessous. Réduit pour tenir sur une
            // seule, le salut devenait illisible et le prénom s'effaçait en
            // trois points — c'est le prénom qu'on lit, pas la formule.
            /*
             * Cinquante-deux : la taille de la référence, pas celle qui
             * restait après avoir tout payé.
             *
             * Trente-huit était un compromis tenu par le mauvais bout — on
             * s'arrêtait là où la pile cessait de tenir cinq cartes avec ses
             * anciennes mesures. Or l'accordéon est fait pour ça : c'est la
             * TRANCHE qui se serre, et trente-quatre points n'étaient pas son
             * minimum, juste sa valeur d'alors. À vingt-huit, une bande
             * montre encore un nom et un montant de quinze points avec cinq
             * points d'air de chaque côté.
             *
             * Le compte, à 241 points de place restante : plancher de la
             * carte de tête (128) plus quatre tranches de 28 fait 240. Cinq
             * cartes, comme avant, avec un salut de quatorze points plus
             * grand. La carte de tête, elle, ne cède rien : c'est la seule
             * qu'on lit en entier.
             */
            Text(Greeting.line(t, name: firstName))
                .font(.system(size: 52, weight: .medium))
                .kerning(Ed.tracking(52, 0.04))
                .foregroundStyle(Florin.text)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 10)
                .padding(.trailing, 8)
        } trailing: {
            HStack(spacing: 0) {
                EdIconButton(
                    symbol: "arrow.trianglehead.2.clockwise",
                    label: t("v2.common.refresh", "Actualiser"),
                    spinning: model.syncing
                ) {
                    Task { await model.sync(confirmCurrent: false) }
                }
                .disabled(model.syncing || !(model.overview?.bankSyncConfigured ?? false))
                EdIconButton(
                    symbol: Ed.settingsSymbol,
                    label: t("v2.settings.title", "Réglages"),
                    action: onOpenSettings
                )
            }
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
                HStack(spacing: 10) {
                    EdPill(text: scrubbed.map { dayLabel($0.day, data) }
                        ?? (showNet
                            ? t("v2.overview.netWorth", "Patrimoine")
                            : t("v2.overview.gross", "Brut")))
                    /*
                     * Le rideau se tire sur le chiffre, pas dans un menu.
                     *
                     * Masquer les montants vivait dans Réglages et dans une
                     * secousse du téléphone. Le geste qu'on cherche quand
                     * quelqu'un se penche est à l'endroit qu'on veut couvrir :
                     * ici, à côté du grand nombre.
                     */
                    EdEye()
                    Spacer(minLength: 0)
                }
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
                PrivateText(t("v2.overview.debt", "Dettes") + " " + Money.string(
                    data.netWorth.liability, locale: data.localeTag,
                    currency: data.currency, decimals: false
                ))
                .foregroundStyle(Florin.text2)
            } else if !data.recent.isEmpty, showSaving, scrubbed == nil, let kept {
                arrow(kept >= 0).hiddenWhenPrivate()
                PrivateText(Money.string(
                    abs(kept), locale: data.localeTag, currency: data.currency,
                    decimals: abs(kept) < 1000
                ))
                .monospacedDigit()
                .fontWeight(.semibold)
                .foregroundStyle(kept >= 0 ? Florin.positive : Florin.negative)
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
                arrow(move >= 0).hiddenWhenPrivate()
                PrivateText(Money.string(
                    abs(move), locale: data.localeTag, currency: data.currency,
                    decimals: abs(move) < 1000
                ))
                .monospacedDigit()
                .fontWeight(.semibold)
                .foregroundStyle(move >= 0 ? Florin.positive : Florin.negative)
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

    /// Tous les comptes vivants, dans l'ordre de la base.
    ///
    /// `display_order` est ce que la base trie déjà. Réagencer la pile au
    /// doigt a été retiré : une carte de pile fait la hauteur d'une carte
    /// entière et n'en montre qu'un bandeau, donc la déplacer sortait son
    /// corps de sa cachette — il n'y avait pas de façon de le dessiner qui
    /// reste lisible. L'ordre se change dans Comptes.
    private func cards(_ data: Overview) -> [Account] {
        let hidden = HomeCards.hidden(hiddenCards)
        return data.accounts.filter {
            !$0.isArchived && $0.isIncludedInNetWorth && !hidden.contains($0.id)
        }
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
        .padding(.top, 10)
        .padding(.bottom, 10)
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
    /// Ce que le premier écran laisse sous la pile : la capsule flotte à
    /// 28 pt du bas sur 60 pt de haut, et les quatre gestes restent cachés
    /// derrière elle tant qu'on n'a pas descendu.
    private static let breathe: CGFloat = 104
    /// Jusqu'où cet écart se referme : `breathe` moins les 44 pt que les
    /// quatre gestes gardent sous eux, pour qu'il y en ait autant des deux
    /// côtés une fois la page descendue.
    private static let maxLift: CGFloat = breathe - 44
    private static let space = "edHome"
    private static let step: CGFloat = 44
    /// Le pas serré. En dessous, le nom et le montant n'ont plus de ligne
    /// lisible où tenir — c'est un plancher, pas une préférence.
    ///
    /// Il était à 30, et 30 moins les 18 pt que la carte prend en haut laisse
    /// 12 pt à du texte de 15 : à six cartes, les noms se touchaient. Le
    /// plancher est ce qu'il faut au bandeau, pas ce qui fait entrer une carte
    /// de plus.
    private static let tightStep: CGFloat = 28
    private static let shownAtMost = 8
    /*
     * Ce qu'il faut à la carte menée, compté ligne par ligne.
     *
     * C'était 108, et le visage en demande davantage : la bande du haut
     * (44 pt sur la carte menée), puis 31 de montant, 3 de barre, 15 de
     * légende, leurs deux écarts de 10 et 14 de marge basse. Une carte à qui
     * l'on donne trente points de moins que ce qu'elle dessine ne rogne pas
     * une ligne proprement — elle écrase les écarts et pose le montant sur sa
     * barre. Le plancher dit maintenant la vérité, et c'est la place AU-DESSUS
     * qui a été rendue pour qu'il tienne.
     */
    private static let minCard: CGFloat = 128

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
        guard room.height > 0 else { return Array(all.prefix(3)) }
        // Au pas serré, parce que c'est jusque-là que la pile sait se tasser.
        let slices = Int(((room.height - Self.minCard) / Self.tightStep).rounded(.down))
        let count = max(1, min(Self.shownAtMost, slices + 1))
        return Array(all.prefix(count))
    }

    /*
     * Une couleur par compte, et jamais deux fois la même.
     *
     * `seriesColor` hache l'identifiant sur huit teintes : à six comptes, deux
     * tombent sur la même plus d'une fois sur deux — PEA et LEP étaient tous
     * les deux jaunes, l'un sur l'autre, et la pile n'avait plus que cinq
     * cartes à l'œil. Le hachage reste le premier choix, parce que c'est lui
     * qui rend la couleur stable et la même que sur le web ; un compte qui
     * trouve sa place prise passe au rang suivant.
     *
     * Décidée sur l'ordre de la BASE, pas sur l'ordre affiché : mettre une
     * carte en avant réordonne la pile, et une couleur qui suivrait cet ordre
     * changerait à chaque appui.
     */
    private func palette(_ all: [Account]) -> [String: Color] {
        let count = Florin.series.count
        var taken = Set<Int>()
        var out: [String: Color] = [:]
        for account in all {
            var rank = Florin.seriesIndex(for: account.id)
            var tries = 0
            while taken.contains(rank), tries < count {
                rank = (rank + 1) % count
                tries += 1
            }
            taken.insert(rank)
            out[account.id] = Florin.series[rank]
        }
        return out
    }

    /// Sous dix euros, les centimes font la phrase : 1,50 € arrondi à 2 € se
    /// lit comme un tiers de plus qu'il n'y a, et la part en pourcentage suit.
    private func cardMoney(_ value: Double, _ data: Overview) -> String {
        Money.string(
            value, locale: data.localeTag, currency: data.currency,
            decimals: abs(value) < 10
        )
    }

    @ViewBuilder
    private func stack(_ data: Overview, room: CGSize) -> some View {
        /*
         * La carte qu'on choisit vient au premier plan — à la place.
         *
         * Passer simplement devant ne voulait rien dire : elle recouvrait
         * ses voisines sans que la pile en tienne compte, et on ne savait
         * plus où elle était. Elle prend donc le créneau du bas, celui de la
         * carte ouverte, et les autres se resserrent derrière. Les créneaux
         * sont des décalages et l'identité des cartes ne change pas : le
         * ressort fait glisser chacune jusqu'au sien, personne ne clignote.
         */
        let all = cards(data)
        let tints = palette(all)
        let shown = promoted(fitting(all, room: room))
        let plan = layout(count: shown.count, room: room)
        let height = plan.height
        let step = plan.step
        if !shown.isEmpty {
            // La carte menée est la dernière : posée le plus bas, donc tout en
            // haut de l'ordre d'empilement. L'ordre du `ZStack` le dit déjà,
            // sauf pour celle qu'on met en avant.
            ZStack(alignment: .top) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, account in
                    card(
                        account, data,
                        tint: tints[account.id] ?? Florin.seriesColor(for: account.id),
                        lead: index == shown.count - 1,
                        height: height, band: step
                    )
                    .offset(y: CGFloat(index) * step)
                    /*
                     * Celle qu'on met en avant passe devant.
                     *
                     * C'est tout l'objet du premier appui : une carte prise
                     * entre deux autres ne montre qu'un bandeau, et le
                     * montant est justement au bout de ce bandeau. Devant,
                     * elle se lit en entier — et redescend dès qu'on en
                     * touche une autre.
                     */
                    .zIndex(Double(index))
                }
            }
            .frame(
                height: height + CGFloat(shown.count - 1) * step,
                alignment: .top
            )
            /*
             * La pile ne s'efface pas en descendant.
             *
             * `edEnter` éteint ce qui sort du défilement, et c'est juste pour
             * un titre ou un chiffre : une ligne s'en va au lieu d'être
             * coupée. Sur des cartes de couleur, la même règle donne une pile
             * de plus en plus transparente dès les premiers points de
             * défilement — on croit l'app en train de se perdre. Les bords du
             * système suffisent ici : la pile s'en va, elle ne se dissout pas.
             */
            .animation(EdMotion.spring, value: shown.map(\.id))
            /*
             * Le bas de la pile ne descend jamais.
             *
             * Tout ce qui est au-dessus — le salut, le chiffre, la courbe —
             * peut grandir : ça réduit la place laissée ici, et `layout`
             * resserre les tranches pour la remplir exactement. Mais quand il
             * y a du mou (peu de comptes, carte à sa hauteur idéale), la pile
             * était posée en HAUT de ce qui restait, donc sa dernière carte
             * suivait le salut vers le bas. Calée en bas, la ligne du bas du
             * premier écran est la même quelle que soit la taille du titre :
             * l'accordéon se plie par le haut.
             */
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    /// La carte choisie en dernier, c'est-à-dire devant.
    ///
    /// Le bas de la pile est le premier plan : c'est le créneau de la carte
    /// ouverte, la seule qui montre autre chose qu'un bandeau.
    private func promoted(_ shown: [Account]) -> [Account] {
        guard let raised, let from = shown.firstIndex(where: { $0.id == raised })
        else { return shown }
        var next = shown
        next.append(next.remove(at: from))
        return next
    }

    /*
     * La hauteur d'une carte et l'écart entre deux, décidés ensemble.
     *
     * La place totale est donnée : c'est celle que trois cartes occupent au
     * pas de repos, et elle ne bouge pas quand on en ajoute. Ce sont les
     * cartes qui se resserrent, jusqu'au pas plancher, et seulement ensuite
     * la carte de devant qui rapetisse.
     *
     * Dans cet ordre, parce que resserrer ne coûte que du vide : le bandeau
     * d'une carte repliée reste lisible tant qu'il a ses trente points,
     * alors que rogner la carte de devant lui prend son chiffre.
     */
    private func layout(count: Int, room: CGSize) -> (height: CGFloat, step: CGFloat) {
        let ideal = (room.width > 0 ? room.width : 361) / 1.6
        guard room.height > 0 else { return (ideal, Self.step) }
        guard count > 1 else {
            return (max(Self.minCard, min(ideal, room.height)), Self.step)
        }
        let gaps = CGFloat(count - 1)
        // Au repos d'abord : si tout tient à 44 pt, rien ne change.
        let roomy = min(ideal, room.height - gaps * Self.step)
        if roomy >= Self.minCard { return (roomy, Self.step) }
        let height = max(Self.minCard, min(ideal, room.height - gaps * Self.tightStep))
        return (height, max(Self.tightStep, (room.height - height) / gaps))
    }

    @ViewBuilder
    private func card(
        _ account: Account, _ data: Overview,
        tint: Color, lead: Bool, height: CGFloat, band: CGFloat
    ) -> some View {
        /*
         * Deux appuis, et aucun geste tenu.
         *
         * Le déplacement au doigt a été retiré : il n'y avait pas de façon
         * de dessiner une carte qu'on déplace qui reste lisible, et il se
         * disputait de toute façon le toucher avec l'ouverture et le
         * balayage d'onglet. Le balayage de la vue redevient donc ce qu'il
         * est partout ailleurs.
         */
        face(account, data, tint: tint, lead: lead, open: lead, band: band)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: Ed.smallCard, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Ed.smallCard, style: .continuous))
            .onTapGesture {
                // Devant, on ouvre. Derrière, on vient devant.
                guard lead else {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    withAnimation(EdMotion.spring) { raised = account.id }
                    return
                }
                UISelectionFeedbackGenerator().selectionChanged()
                drill = ActivityRoute(accountId: account.id, title: account.name)
            }
            // Celle qui vient d'arriver devant porte une ombre le temps du
            // trajet : c'est ce qui dit qu'elle passe par-dessus les autres
            // plutôt que de se glisser entre elles.
            .shadow(
                color: .black.opacity(lead && raised == account.id ? 0.32 : 0),
                radius: lead && raised == account.id ? 20 : 0,
                y: lead && raised == account.id ? 12 : 0
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
        _ account: Account, _ data: Overview,
        tint: Color, lead: Bool, open: Bool, band: CGFloat
    ) -> some View {
        let ink: Color = Florin.readable(on: tint)
        let total = max(abs(data.netWorth.gross), 1)
        let share = Int((abs(account.displayValue) / total * 100).rounded())

        return VStack(alignment: .leading, spacing: 0) {
            /*
             * Le nom et le montant au MILIEU de la bande visible.
             *
             * D'une carte repliée on ne voit qu'une tranche : du haut de la
             * carte jusqu'au haut de la suivante, soit `band`. La rangée se
             * posait sous une marge de 14 pt et se centrait sur ce qui restait
             * — donc sept points trop bas, sur chacune des cartes sauf la
             * dernière. Elle prend maintenant la bande entière et se centre
             * dedans, ce qui est la même chose que de dire : au milieu de ce
             * qu'on voit.
             */
            HStack(alignment: .firstTextBaseline) {
                Text(account.name)
                    .font(.system(size: 15))
                    .lineLimit(1)
                Spacer(minLength: 8)
                // Sur la carte ouverte, le montant est écrit en grand juste
                // dessous : l'écrire deux fois sur la même carte ne dit rien
                // de plus et pousse le nom contre le bord.
                if !open {
                    PrivateText(cardMoney(account.displayValue, data))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                }
            }
            .frame(height: band, alignment: .center)

            VStack(alignment: .leading, spacing: 10) {
                Spacer(minLength: 0)
                /*
                 * LE MONTANT DE CE COMPTE, pas celui d'un autre.
                 *
                 * Il écrivait `data.allocation.cash` — l'épargne liquide de
                 * tout le patrimoine. Donc les six cartes affichaient le même
                 * grand nombre, et celui-ci ne correspondait à aucune d'elles.
                 *
                 * Il est aussi descendu contre sa barre : en haut de la carte,
                 * il laissait entre lui et elle un trou qui grandissait avec
                 * la carte.
                 */
                PrivateText(cardMoney(account.displayValue, data))
                .font(.system(size: 26, weight: .medium))
                .monospacedDigit()
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
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Ed.smallCard, style: .continuous)
                .fill(tint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Ed.smallCard, style: .continuous)
                .strokeBorder(
                    ink.opacity(0.14), lineWidth: 1
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

/// De combien le premier écran est sorti par le haut.
private struct EdFirstScreenTop: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
