import SwiftUI

/*
 * Activité, dans le langage Éditorial.
 *
 * La maquette coupe la liste par jours et met le plus récent en titre : « Hier »
 * en 64 pt, son solde juste à côté, puis les lignes séparées par des filets.
 * C'est une lecture, pas un tableau — d'où l'absence de cartes, et le montant
 * dans une pastille plutôt que collé à droite.
 *
 * Les données et les gestes sont ceux de `TransactionList` : même
 * `ActivityModel`, même feuille de détail, même feuille de filtres.
 */
struct EditorialActivity: View {
    @ObservedObject var overview: OverviewModel
    var onOpenSettings: () -> Void = {}
    @ObservedObject var chrome: ChromeState
    var startNeedsReview = false

    @StateObject private var model: ActivityModel
    @State private var detail: Transaction?
    @State private var filtering = false
    @State private var upcomingOpen = false
    @State private var instalmentsOpen = false
    @State private var reviewOpen = false
    @State private var searching = false
    /// L'échéancier dont on regarde le détail — comme sur Obsidienne.
    @State private var openPlan: LocalInstalments.Schedule?
    /*
     * Ce qu'un appui long sur une ligne a demandé — voir `TransactionMenu`.
     *
     * L'écran classique l'avait, le nôtre pas : vérifier, catégoriser,
     * renommer, rembourser, joindre un ticket demandaient tous d'ouvrir la
     * feuille de détail d'abord. Le menu est partagé, et les actions qu'il
     * déclenche aussi — ni l'un ni l'autre n'est réécrit ici.
     */
    @State private var menuRequest: TxActionRequest?
    @State private var draft = ""
    @FocusState private var searchFocused: Bool
    /// Les têtes de marchands. `Bubble` sait déjà se tenir en Éditorial —
    /// un cercle au filet, pas d'emoji, mais le logo gardé : il dit
    /// *lequel* avant d'être lu. L'observation sert au rafraîchissement,
    /// une icône arrivant longtemps après la ligne.
    @ObservedObject private var logos = MerchantLogos.shared

    init(
        overview: OverviewModel,
        onOpenSettings: @escaping () -> Void = {},
        startNeedsReview: Bool = false,
        chrome: ChromeState
    ) {
        self.overview = overview
        self.onOpenSettings = onOpenSettings
        self.startNeedsReview = startNeedsReview
        self.chrome = chrome
        _model = StateObject(wrappedValue: ActivityModel(base: overview.base))
    }

    private var t: Strings { overview.overview?.t ?? .device }
    private var locale: String { overview.overview?.localeTag ?? "fr-FR" }
    private var currency: String { overview.overview?.currency ?? "EUR" }

    /*
     * Le pli compte des ACHATS, pas des mensualités.
     *
     * Il listait les échéances à plat : les quatre d'un voyage mêlées aux
     * quatre d'un manteau, et « 8 en plusieurs fois » là où il y a deux
     * achats. On se souvient de l'achat, pas de sa troisième mensualité —
     * c'est le raisonnement d'Obsidienne, et c'est le même modèle qui sert.
     */
    private var schedules: [LocalInstalments.Schedule] {
        model.schedules.filter { !$0.isOver && $0.matches(model.filter) }
    }

    /*
     * Les quatre listes que lit le corps sont RANGÉES, pas recalculées.
     *
     * Elles étaient calculées ici, donc refaites à chaque évaluation du
     * corps — et le corps est réévalué pour les cinq pages du pagineur à
     * chaque changement d'état, visible ou pas. Voir `ActivityModel.regroup`.
     */
    private var upcoming: [Transaction] { model.upcoming }
    private var instalments: [Transaction] { model.instalments }
    private var pending: [Transaction] { model.pending }
    private var days: [(day: Date, rows: [Transaction])] { model.days }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                .edEnter()
                .id(edTopAnchor)
                if searching { searchField.edEnter() }
                // La pastille « Activité · 3 223 opérations » occupait une
                // ligne pour dire le nom de l'onglet qu'on vient d'ouvrir et
                // un nombre dont on ne fait rien.
                narrowing.edEnter()
                /*
                 * Les volets d'attente se fondent ligne par ligne.
                 *
                 * `edEnter()` était posé sur `waiting`, donc sur les TROIS
                 * volets d'un bloc. Un `edEnter` n'est à pleine opacité que
                 * quand la vue qui le porte tient entièrement dans le cadre :
                 * « 21 en prévision » dépliées font le double de l'écran, le
                 * bloc n'était donc JAMAIS entier, donc jamais franc. On
                 * voyait « en prévision », « en plusieurs fois » et « à
                 * vérifier » à demi transparents ensemble, s'éclaircissant en
                 * défilant puis s'effaçant nettement avant d'avoir quitté
                 * l'écran. Même piège que `ScreenSection` et que les groupes
                 * de comptes : le fondu se prend sur ce qui est plus court que
                 * le cadre — ici chaque ligne, comme dans `rows(_:)`, et les
                 * en-têtes de volet se fondent déjà seuls par `EdInk`.
                 */
                waiting

                if let first = days.first {
                    // Le haut de la liste sort de la vue comme le reste : il
                    // n'avait pas le décalage, donc il se coupait net là où
                    // les lignes se fondent.
                    hero(first).edEnter()
                }

                ForEach(Array(days.enumerated()), id: \.element.day) { index, section in
                    if index > 0 {
                        EdSection(text: dayLabel(section.day))
                            .padding(.top, 34)
                            .padding(.bottom, 6)
                            .edEnter()
                    }
                    rows(section.rows)
                    dayTotal(section.rows)
                }

                footer.edEnter()
            }
            .padding(.horizontal, Ed.gutter)
            .padding(.top, 10)
            .padding(.bottom, 120)
        }
        .edRewind(.activity, chrome: chrome)
        .onReceive(
            NotificationCenter.default.publisher(for: .florinTabReselected)
        ) { note in
            guard note.object as? TabRoute == .activity else { return }
            closeSearch()
        }
        .scrollIndicators(.hidden)
        .edPlainEdges()
        .background(Florin.bg)
        .refreshable { await model.reload() }
        .task {
            if startNeedsReview { model.filter.needsReview = true }
            if model.rows.isEmpty { await model.reload() }
        }
        .reloadsOnLedgerChange { await model.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .florinFocusSearch)) { _ in
            withAnimation(EdMotion.spring) { searching = true }
            searchFocused = true
        }
        /*
         * Le voile du système assombrit sans flouter, et il n'est pas
         * remplaçable : c'est donc l'écran DESSOUS qu'on floute. Le contenu
         * de la feuille vit hors de cette hiérarchie, il reste net.
         */
        .blur(radius: detail != nil ? 7 : 0)
        // C'est le voile du système qui assombrit, et il n'est pas
        // débrayable : un blanc par-dessus le flou le compense, pour un
        // dépoli plutôt qu'une pièce éteinte.
        .overlay(
            Color.white.opacity(detail != nil ? 0.16 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        )
        .animation(.easeOut(duration: 0.28), value: detail != nil)
        .sheet(item: $detail) { tx in
            TransactionDetailSheet(
                tx: tx,
                categories: model.categories,
                accounts: model.accounts,
                locale: locale,
                currency: currency,
                t: t,
                onPatch: { patch in
                    await model.apply(patch, to: tx.id, t: t)
                    await overview.load(showSpinner: false)
                },
                onDelete: {
                    await model.delete(tx.id, t: t)
                    await overview.load(showSpinner: false)
                },
                onAttachTransfer: { accountId in
                    await model.attachTransfer(tx.id, to: accountId, t: t)
                    await overview.load(showSpinner: false)
                },
                isLocalLedger: model.isLocalLedger
            )
            .edSheet()
        }
        .sheet(item: $openPlan) { plan in
            InstalmentPlanSheet(
                plan: plan, locale: locale, currency: currency, t: t
            ) {
                Task {
                    await model.reload()
                    await overview.load(showSpinner: false)
                }
            }
            .edSheet()
        }
        .sheet(isPresented: $filtering) {
            FilterSheet(
                filter: $model.filter,
                accounts: model.accounts,
                categories: model.categories,
                t: t
            ) {
                Task { await model.reload() }
            }
            .edSheet()
        }
        .transactionActions(
            request: $menuRequest,
            categories: model.categories,
            accounts: model.accounts,
            locale: locale,
            currency: currency,
            t: t,
            onPatch: { tx, patch in
                await model.apply(patch, to: tx.id, t: t)
                await overview.load(showSpinner: false)
            },
            onDelete: { tx in
                await model.delete(tx.id, t: t)
                await overview.load(showSpinner: false)
            },
            onAttach: { tx, accountId in
                await model.attachTransfer(tx.id, to: accountId, t: t)
                await overview.load(showSpinner: false)
            },
            onRefunded: {
                await model.reload()
                await overview.load(showSpinner: false)
            },
            isLocalLedger: model.isLocalLedger
        )
        .florinToast($model.toast)
    }

    // MARK: Le bandeau

    private var header: some View {
        EdHeader {
            EdIconButton(
                symbol: "magnifyingglass",
                label: t("v2.common.search", "Rechercher")
            ) {
                if searching {
                    closeSearch()
                } else {
                    withAnimation(EdMotion.spring) { searching = true }
                    searchFocused = true
                }
            }
        } trailing: {
            HStack(spacing: 0) {
                EdIconButton(
                    // Un point sur la loupe des filtres : on doit voir qu'une
                    // liste est tronquée sans avoir à ouvrir la feuille.
                    symbol: model.filter.isFiltered
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease",
                    label: t("v2.activity.filters", "Filtres")
                ) { filtering = true }
                EdIconButton(
                    symbol: Ed.settingsSymbol,
                    label: t("v2.settings.title", "Réglages"),
                    action: onOpenSettings
                )
            }
        }
    }

    /*
     * Refermer la recherche rend la liste entière.
     *
     * Deux gestes veulent dire la même chose — retaper la loupe, et retaper
     * l'onglet où l'on est déjà. Le second ne faisait que remonter en haut :
     * on revenait sur Activité, on la trouvait remontée mais toujours
     * réduite à « Amaz », et rien à l'écran ne disait pourquoi il manquait
     * trois mois d'opérations.
     */
    private func closeSearch() {
        guard searching || !draft.isEmpty else { return }
        withAnimation(EdMotion.spring) { searching = false }
        searchFocused = false
        guard !draft.isEmpty else { return }
        draft = ""
        model.filter.search = ""
        Task { await model.reload() }
    }

    private var searchField: some View {
        TextField(
            t("v2.activity.searchPlaceholder", "Bénéficiaire, note…"),
            text: $draft
        )
        .font(.system(size: 17))
        .foregroundStyle(Florin.text)
        .focused($searchFocused)
        .submitLabel(.search)
        .autocorrectionDisabled()
        .padding(.vertical, 12)
        // La place de la croix, et seulement quand elle est là : sans ça un
        // libellé long passe dessous.
        .padding(.trailing, draft.isEmpty ? 0 : 30)
        .overlay(alignment: .bottom) { EdRule() }
        /*
         * La croix efface la recherche sans la refermer.
         *
         * `TextField` n'en a pas : c'est `clearButtonMode`, qui appartient à
         * UIKit. Sans elle, vider le champ se fait lettre par lettre, ou en
         * refermant la recherche — ce qui n'est pas la même intention que
         * « chercher autre chose ». Le clavier reste donc, et le curseur
         * aussi.
         */
        .overlay(alignment: .trailing) {
            if !draft.isEmpty {
                Button {
                    draft = ""
                    model.filter.search = ""
                    searchFocused = true
                    Task { await model.reload() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Florin.text3)
                        .frame(width: 30, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t("v2.common.clear", "Effacer"))
                .transition(.opacity)
            }
        }
        .animation(EdMotion.spring, value: draft.isEmpty)
        .padding(.top, 10)
        .transition(.opacity.combined(with: .move(edge: .top)))
        // Une frappe par lettre ferait une requête par lettre : on attend que
        // le doigt s'arrête.
        .task(id: draft) {
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled, model.filter.search != draft else { return }
            model.filter.search = draft
            await model.reload()
        }
    }

    // MARK: Le jour en titre

    /*
     * Le total du jour, sur la ligne du jour.
     *
     * Il vivait sous le titre, en 20 pt et en gris : à cet endroit-là, posé
     * seul entre un mot de 64 pt et la première ligne, il se lisait comme le
     * début de la liste. Sur la même ligne de base que le titre, petit et
     * teinté, il est ce qu'il est — une légende de la journée. Le même
     * chiffre revient en pied de journée, dans la colonne des montants, où
     * on le cherche quand on a fini de lire. Voir `dayTotal`.
     */
    /*
     * Le jour s'annonce, il ne se compte pas deux fois.
     *
     * Le net de la journée était écrit à droite du nom du jour ET en pied de
     * la liste. Le même nombre, deux fois, à deux styles : en haut il se lit
     * avant les lignes qui le composent, donc il ne veut rien dire encore.
     * En pied, il clôt. Seul le pied reste.
     */
    private func hero(_ section: (day: Date, rows: [Transaction])) -> some View {
        EdHero(text: dayLabel(section.day))
            /*
             * Le même écart qu'entre un total de journée et le jour suivant.
             *
             * Celui-là vaut 34 pt (voir `EdSection` plus bas), mais une ligne
             * de 64 pt porte déjà une quinzaine de points de blanc au-dessus
             * de ses majuscules contre huit pour une de 34 : on rend la
             * différence, sinon le même nombre ne donne pas le même œil.
             */
            .padding(.top, hasWaiting ? 26 : 10)
    }

    private var hasWaiting: Bool { !upcoming.isEmpty || !schedules.isEmpty }

    /// Le total d'une journée, en pied, dans la colonne des montants.
    @ViewBuilder
    private func dayTotal(_ list: [Transaction]) -> some View {
        let net = list.reduce(0) { $0 + $1.amount }
        EdRule()
        HStack(spacing: 12) {
            Text(t("v2.activity.dayTotal", "Total du jour"))
                .font(.system(size: 13))
                .foregroundStyle(Florin.text3)
            Spacer(minLength: 8)
            EdAmountPill(
                text: Money.string(
                    net, locale: locale, currency: currency,
                    decimals: false, signed: true
                ),
                tone: EdMoney.tone(net)
            )
        }
        .frame(minHeight: 48)
        .edEnter()
    }

    /// « Aujourd'hui », « Hier », puis la date écrite. Un libellé relatif ne
    /// sert que tant qu'il reste plus court à lire que la date elle-même.
    private func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return t("v2.common.today", "Aujourd'hui") }
        if calendar.isDateInYesterday(day) { return t("v2.common.yesterday", "Hier") }
        let f = DateFormatter()
        f.locale = Locale(identifier: locale)
        f.setLocalizedDateFormatFromTemplate(
            calendar.isDate(day, equalTo: .now, toGranularity: .year) ? "dMMMM" : "dMMMMy"
        )
        return f.string(from: day)
    }

    // MARK: Ce qui réduit la liste

    /*
     * Un filtre qui ne se voit pas est une impasse.
     *
     * « Tout voir » sous la file à vérifier posait `needsReview` et rien
     * d'autre ne bougeait à l'écran : pas de titre, pas de retour, et les
     * trois plis — à venir, en plusieurs fois, à vérifier — disparaissaient
     * d'un coup, puisque chacun s'efface sous ce filtre. On se retrouvait
     * dans une liste rétrécie sans savoir où, ni comment en sortir ; la seule
     * issue était le point sur l'entonnoir, puis la feuille, puis
     * « réinitialiser ».
     *
     * Chaque réduction active s'écrit donc ici, et chaque pastille est son
     * propre bouton d'annulation. Pas la recherche : le champ a déjà sa croix.
     */
    @ViewBuilder
    private var narrowing: some View {
        let items = narrowingChips
        if !items.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.label) { chip in
                        Button {
                            edOpen {
                                UISelectionFeedbackGenerator().selectionChanged()
                                chip.clear()
                                Task { await model.reload() }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(chip.label)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .opacity(0.65)
                            }
                            .foregroundStyle(Florin.text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .overlay {
                                Capsule().strokeBorder(Florin.text.opacity(0.28), lineWidth: 1)
                            }
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.edPress)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .edHoldsSwipe()
            .padding(.top, 12)
        }
    }

    /// Une pastille par réduction, avec le geste qui la défait. Les libellés
    /// sont ceux de la feuille de filtres — un même réglage ne porte pas deux
    /// noms selon l'écran où on le lit.
    private var narrowingChips: [(label: String, clear: () -> Void)] {
        var out: [(String, () -> Void)] = []
        switch model.filter.direction {
        case .all: break
        case .expense:
            out.append((t("v2.activity.expenses", "Dépenses"), { model.filter.direction = .all }))
        case .income:
            out.append((t("v2.activity.income", "Entrées"), { model.filter.direction = .all }))
        }
        if model.filter.needsReview {
            out.append((
                t("v2.activity.needsReview", "À vérifier"),
                { model.filter.needsReview = false }
            ))
        }
        if model.filter.excludeTransfers {
            out.append((
                t("v2.filters.excludeTransfers", "Masquer les virements internes"),
                { model.filter.excludeTransfers = false }
            ))
        }
        if let id = model.filter.accountId {
            let name = model.accounts.first { $0.id == id }?.name
                ?? t("v2.add.account", "Compte")
            out.append((name, { model.filter.accountId = nil }))
        }
        if let id = model.filter.categoryId {
            let name = model.categories.first { $0.id == id }?.name
                ?? t("v2.common.uncategorized", "Sans catégorie")
            out.append((name, { model.filter.categoryId = nil }))
        }
        if model.filter.from != nil || model.filter.to != nil {
            out.append((
                t("v2.filters.period", "Période"),
                {
                    model.filter.from = nil
                    model.filter.to = nil
                }
            ))
        }
        return out.map { (label: $0.0, clear: $0.1) }
    }

    // MARK: Ce qui attend

    /*
     * Deux plis, repliés par défaut, et une seule ligne chacun.
     *
     * Ils prenaient deux lignes — un libellé au-dessus de son montant — soit
     * presque cent points pour annoncer deux choses qu'on lit d'un coup
     * d'œil, et qui repoussaient « Aujourd'hui » hors de l'écran. Le libellé
     * à gauche, le montant à droite : la même ligne, la moitié de la hauteur.
     *
     * Ce qui s'ouvre dessous n'est plus dans la carte. Une liste posée sur
     * l'accent demandait son propre jeu de couleurs — d'où des lignes qui ne
     * ressemblaient à rien d'autre dans l'app. La carte ne porte donc que
     * l'en-tête, et le contenu se déroule sur la page, dans les lignes de la
     * liste : vignette, nom, catégorie dessous, montant en pastille.
     */
    @ViewBuilder
    private var waiting: some View {
        if !upcoming.isEmpty || !schedules.isEmpty || !pending.isEmpty {
            VStack(spacing: 14) {
                if !upcoming.isEmpty {
                    fold(
                        title: t("v2.activity.upcomingCount", "{count} à venir",
                                 ["count": upcoming.count]),
                        total: upcoming.reduce(0) { $0 + $1.amount },
                        open: $upcomingOpen,
                        inverse: false
                    ) {
                        ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, tx in
                            // Pas de filet sous l'en-tête : il déborde de la
                            // pastille des deux côtés et la trahit.
                            if index > 0 { EdRule() }
                            Button { edOpen { detail = tx } } label: { row(tx) }
                                .buttonStyle(.edPress)
                                .transactionMenu(
                                    tx, t: t, locale: locale, currency: currency,
                                    canTransfer: !tx.isTransfer && tx.amount < 0
                                        && model.accounts.count > 1,
                                    request: $menuRequest,
                                    isLocalLedger: model.isLocalLedger
                                )
                                .edEnter()
                        }
                    }
                }
                if !schedules.isEmpty {
                    fold(
                        title: t("v2.activity.instalmentPlanCount",
                                 "{count} en plusieurs fois",
                                 ["count": schedules.count]),
                        total: -schedules.reduce(0) { $0 + $1.remaining },
                        open: $instalmentsOpen,
                        inverse: true
                    ) {
                        ForEach(Array(schedules.enumerated()), id: \.element.id) { index, plan in
                            if index > 0 { EdRule() }
                            Button {
                                edOpen {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    openPlan = plan
                                }
                            } label: { planRow(plan) }
                                .buttonStyle(.edPress)
                                .edEnter()
                        }
                    }
                }
                if !pending.isEmpty {
                    fold(
                        title: t("v2.review.toCheckCount", "{count} à vérifier",
                                 // Le compte du registre, pas celui de la
                                 // page : ils diffèrent tant que tout n'est
                                 // pas chargé, et le plus petit ment.
                                 ["count": max(model.reviewCount, pending.count)]),
                        total: pending.reduce(0) { $0 + $1.amount },
                        open: $reviewOpen,
                        inverse: false
                    ) {
                        ForEach(Array(pending.enumerated()), id: \.element.id) { index, tx in
                            if index > 0 { EdRule() }
                            Button { edOpen { detail = tx } } label: { row(tx) }
                                .buttonStyle(.edPress)
                                .transactionMenu(
                                    tx, t: t, locale: locale, currency: currency,
                                    canTransfer: !tx.isTransfer && tx.amount < 0
                                        && model.accounts.count > 1,
                                    request: $menuRequest,
                                    isLocalLedger: model.isLocalLedger
                                )
                                .edEnter()
                        }
                        EdRule()
                        HStack {
                            Spacer()
                            Button {
                                edOpen {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    model.filter.needsReview = true
                                    // Sans rechargement, le pli disparaissait
                                    // et la liste dessous restait entière :
                                    // « Tout voir » enlevait la file au lieu
                                    // de l'ouvrir.
                                    Task { await model.reload() }
                                }
                            } label: {
                                Text(t("v2.common.seeAll", "Tout voir"))
                                    .underline()
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Florin.text)
                            }
                            .buttonStyle(.edPress)
                        }
                        .padding(.top, 14)
                        .edEnter()
                    }
                }
            }
            /*
             * Le même écart des deux côtés des deux volets.
             *
             * Il y avait 26 pt avant eux (4 au point d'appel, 22 ici) et 4
             * après : la rangée des volets était collée au jour qui la suit et
             * décollée du bandeau qui la précède. Les deux font maintenant 14,
             * et c'est le héros qui rend les siens — voir `hero`, dont la
             * ligne de 64 pt porte déjà une quinzaine de points de blanc
             * au-dessus de ses majuscules.
             *
             * Dessous, l'écart doit être plus grand que celui qui sépare deux
             * volets : la première journée de la liste est la seule sans
             * en-tête — `EdSection` ne s'écrit qu'à partir de la deuxième —
             * donc ses lignes touchaient le dernier volet et se lisaient
             * comme son contenu.
             */
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
    }

    /// Voir `EdFold`. La fiche d'un compte porte les deux mêmes volets, et
    /// c'est le même volet — pas un second dessiné pareil.
    private func fold<Content: View>(
        title: String, total: Double, open: Binding<Bool>, inverse: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        EdFold(
            title: title, total: total, locale: locale, currency: currency,
            open: open, inverse: inverse, content: content
        )
    }

    /*
     * Une ligne par achat étalé.
     *
     * Elle dit ce qu'on se demande en passant — chez qui, combien il reste,
     * où en est l'échéancier — et la feuille derrière dit le reste. Les
     * pastilles d'avancement sont celles d'Obsidienne : quatre sur six se
     * comptent sans se lire.
     */
    private func planRow(_ plan: LocalInstalments.Schedule) -> some View {
        // Sa tete est celle de l'ACHAT, pas celle du rail qui l'encaisse.
        // Le nom le demandait deja au plan ; la tete, non. Ca ne se voyait
        // pas tant que le beneficiaire etait le marchand — un achat chez
        // La Boutique est libelle « La Boutique » — et ca sautait aux yeux des
        // qu'il ne l'etait plus : un achat encaisse par un intermediaire
        // s'affichait sous le nom qu'on lui avait donne et le logo de
        // l'intermediaire, cote a cote dans la meme rangee.
        let face = logos.face(for: plan.payee, plan: plan.id)
        return HStack(spacing: 12) {
            Bubble(
                label: plan.categoryName ?? plan.payee,
                name: plan.payee,
                chosen: face?.emoji,
                emoji: plan.categoryEmoji,
                size: 38,
                logo: face?.logo
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(PayeeText.title(plan.payee, category: plan.categoryName, plan: plan.id))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Florin.text)
                    .lineLimit(1)
                Text(planSubtitle(plan))
                    .font(.system(size: 13))
                    .foregroundStyle(Florin.text2)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                EdAmountPill(
                    text: Money.string(
                        -plan.remaining, locale: locale, currency: currency, signed: true
                    ),
                    tone: EdMoney.minus
                )
                InstalmentProgress(count: plan.count, paid: plan.paidCount)
                    .hiddenWhenPrivate()
            }
        }
        .frame(minHeight: 62)
        .contentShape(Rectangle())
    }

    /*
     * Deux chiffres et une date, et aucun mot à tronquer.
     *
     * « 2 sur 4 payées · 29 novembre » ne tient pas dans la colonne qui reste
     * à gauche de la pastille de montant : la ligne rendait « 2 sur 4 pay… »
     * ou « … 9 n… », c'est-à-dire un compte illisible et une date qui n'en
     * est plus une. Or ces deux faits sont des nombres : « 2/4 » se lit d'un
     * coup d'œil et ne se coupe pas, et la date en chiffres fait cinq signes
     * là où son nom en faisait douze.
     */
    private func planSubtitle(_ plan: LocalInstalments.Schedule) -> String {
        let progress = "\(plan.paidCount)/\(plan.count)"
        guard let next = plan.next else { return progress }
        return progress + " · " + Self.shortDay.string(from: next.day)
    }

    /// « 29/11 » — le gabarit est localisé, donc l'ordre jour/mois suit la
    /// langue sans qu'on écrive deux formats.
    private static let shortDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("ddMM")
        return formatter
    }()

    // MARK: Les lignes

    private func rows(_ list: [Transaction]) -> some View {
        ForEach(list) { tx in
            EdRule()
            Button { edOpen { detail = tx } } label: { row(tx) }
                .buttonStyle(.edPress)
                .transactionMenu(
                    tx, t: t, locale: locale, currency: currency,
                    canTransfer: !tx.isTransfer && tx.amount < 0 && model.accounts.count > 1,
                    request: $menuRequest,
                    isLocalLedger: model.isLocalLedger
                )
                .buttonStyle(.edPress)
                .edEnter()
        }
    }

    /*
     * Le nom d'une ligne n'est pas ce que la banque a écrit.
     *
     * « PREL DE ORANGE SA 16321… » est un libellé de rail : un préfixe, une
     * référence de mandat, une date de capture. L'app sait déjà en tirer un
     * nom — et surtout, elle sait lequel on lui a donné soi-même, puisque
     * renommer un marchand est une fonction de Florin. Écrire `tx.payee`
     * jetait les deux : les renommages n'apparaissaient nulle part, et la
     * liste montrait des références tronquées.
     *
     * `PayeeText.title` est exactement ce que l'ancienne liste appelle, donc
     * les deux styles disent la même chose du même marchand.
     */
    private func title(_ tx: Transaction) -> String {
        if tx.payee.isEmpty { return t("v2.activity.unnamedPayee", "Opération") }
        if tx.isPairedTransfer, !tx.isPairedRepayment {
            return t("v2.common.ownTransfer", "Virement")
        }
        return PayeeText.title(tx.payee, category: tx.categoryName, plan: tx.instalmentPlanId)
    }

    private func row(_ tx: Transaction) -> some View {
        HStack(spacing: 12) {
            // Un virement entre ses propres comptes n'a pas de marchand : le
            // « marchand », là, c'est soi.
            let face = tx.isTransfer ? nil : logos.face(for: tx.payee, plan: tx.instalmentPlanId)
            Bubble(
                label: tx.categoryName ?? tx.payee,
                name: tx.payee,
                chosen: face?.emoji,
                emoji: tx.categoryEmoji,
                systemImage: tx.isDebtRepayment
                    ? "arrow.down.right"
                    : (tx.isTransfer ? "arrow.left.arrow.right" : nil),
                size: 38,
                logo: face?.logo
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(title(tx))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Florin.text)
                    .lineLimit(1)
                Text(subtitle(tx))
                    .font(.system(size: 13))
                    // Une ligne à classer se signale par l'accent : c'est la
                    // seule chose de cette liste qui demande quelque chose.
                    .foregroundStyle(tx.needsReview ? Florin.accent : Florin.text2)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            /*
             * Rouge dehors, vert dedans — et jamais l'accent.
             *
             * La pastille était noire quoi qu'il arrive, au prétexte que le
             * signe disait le sens : il le dit, à condition de le lire. Dans
             * une liste qu'on parcourt, une rentrée doit sauter aux yeux sans
             * être lue. Ce ne sont pas pour autant les encres de l'accent —
             * voir `EdMoney` : l'orange reste réservé à ce qui demande une
             * décision.
             */
            EdAmountPill(
                text: Money.string(
                    tx.amount, locale: locale, currency: currency, signed: true
                ),
                tone: EdMoney.tone(tx.amount)
            )
        }
        .frame(minHeight: 62)
        .contentShape(Rectangle())
    }

    private func subtitle(_ tx: Transaction) -> String {
        if tx.needsReview { return t("v2.activity.needsReview", "À catégoriser") }
        if tx.isTransfer { return t("v2.activity.transfer", "Virement interne") }
        let category = tx.categoryName ?? tx.accountName
        return tx.isPending
            ? category + " · " + t("v2.activity.pending", "En attente")
            : category
    }

    // MARK: Le bas de liste

    /// La page suivante se demande quand le bas arrive à l'écran, pas par un
    /// bouton : une liste qu'on fait défiler n'a pas à être cliquée pour
    /// continuer.
    @ViewBuilder
    private var footer: some View {
        if model.rows.isEmpty, !model.loading {
            VStack(alignment: .leading, spacing: 6) {
                EdSection(text: t("v2.activity.empty", "Aucune opération"))
                Text(t("v2.activity.emptyHint", "Changez les filtres ou synchronisez."))
                    .font(.system(size: 15))
                    .foregroundStyle(Florin.text2)
            }
            .padding(.top, 40)
        } else if model.rows.count < model.total {
            EdRule()
            ProgressView()
                .tint(Florin.text3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .task { await model.loadMore() }
        } else {
            EdRule()
        }
    }
}
