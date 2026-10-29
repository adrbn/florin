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
     * Ce qui n'a pas encore eu lieu ne se range pas avec ce qui a eu lieu.
     *
     * Une banque publie un prélèvement plusieurs jours avant de le prendre,
     * et un achat en quatre fois connaît ses trois échéances suivantes le
     * jour même. Par date, tout cela arrive en tête — donc un « 30 octobre »
     * s'ouvrait au-dessus d'« Aujourd'hui » et poussait les vraies opérations
     * vers le bas. Elles sont déjà hors de tous les totaux ; elles sortent
     * aussi des journées, et se replient dans leur propre pli au-dessus.
     */
    private var upcoming: [Transaction] {
        model.rows.filter { $0.isUpcoming && !$0.isInstalment }
    }

    private var instalments: [Transaction] {
        model.rows.filter { $0.isScheduled && $0.isInstalment }
    }

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

    /// Les lignes regroupées par jour, dans l'ordre où elles arrivent — le
    /// serveur les rend déjà triées, donc ce découpage n'a rien à retrier.
    ///
    /// Les deux jambes d'un virement sont repliées en une : les voir toutes
    /// les deux, à une ligne d'écart et au signe près, ne dit rien de plus
    /// que la ligne unique et fait croire à deux mouvements.
    private var days: [(day: Date, rows: [Transaction])] {
        let announced = Set(upcoming.filter(\.isToCome).map(\.id))
            .union(instalments.map(\.id))
        var out: [(day: Date, rows: [Transaction])] = []
        for row in model.rows where !announced.contains(row.id) {
            let day = Calendar.current.startOfDay(for: row.day)
            if out.last?.day == day {
                out[out.count - 1].rows.append(row)
            } else {
                out.append((day, [row]))
            }
        }
        return out.map { ($0.day, TransferPairs.collapsed($0.rows)) }
    }

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
                waiting.edEnter()

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
                withAnimation(EdMotion.spring) { searching.toggle() }
                searchFocused = searching
                if !searching, !draft.isEmpty {
                    draft = ""
                    model.filter.search = ""
                    Task { await model.reload() }
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
        .overlay(alignment: .bottom) { EdRule() }
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
        if !upcoming.isEmpty || !schedules.isEmpty {
            VStack(spacing: 14) {
                if !upcoming.isEmpty {
                    fold(
                        title: t("v2.activity.upcomingCount", "{count} à venir",
                                 ["count": upcoming.count]),
                        total: upcoming.reduce(0) { $0 + $1.amount },
                        open: $upcomingOpen,
                        inverse: false
                    ) {
                        ForEach(upcoming) { tx in
                            EdRule()
                            Button { detail = tx } label: { row(tx) }
                                .buttonStyle(.edPress)
                                .transactionMenu(
                                    tx, t: t, locale: locale, currency: currency,
                                    canTransfer: !tx.isTransfer && tx.amount < 0
                                        && model.accounts.count > 1,
                                    request: $menuRequest,
                                    isLocalLedger: model.isLocalLedger
                                )
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
                        ForEach(schedules) { plan in
                            EdRule()
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                openPlan = plan
                            } label: { planRow(plan) }
                                .buttonStyle(.edPress)
                        }
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
             */
            .padding(.top, 14)
        }
    }

    private func fold<Content: View>(
        title: String, total: Double, open: Binding<Bool>, inverse: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(EdMotion.spring) { open.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 10) {
                    EdInk(text: title, size: 15)
                    Spacer(minLength: 8)
                    EdInk(
                        text: Money.string(
                            total, locale: locale, currency: currency,
                            decimals: false, signed: true
                        ),
                        size: 17, weight: .medium, money: true
                    )
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(inverse ? Florin.bg.opacity(0.7) : Florin.text2)
                        .rotationEffect(.degrees(open.wrappedValue ? 180 : 0))
                }
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.edPress)
            .modifier(EdFoldSkin(inverse: inverse))

            if open.wrappedValue {
                content().transition(.opacity)
            }
        }
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
        let face = logos.face(for: plan.payee)
        return HStack(spacing: 12) {
            Bubble(
                label: plan.categoryName ?? plan.payee,
                emoji: face?.emoji ?? plan.categoryEmoji,
                size: 38,
                logo: face?.logo
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(PayeeText.title(plan.payee, category: plan.categoryName))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Florin.text)
                    .lineLimit(1)
                Text(planSubtitle(plan))
                    .font(.system(size: 13))
                    .foregroundStyle(Florin.text2)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
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

    private func planSubtitle(_ plan: LocalInstalments.Schedule) -> String {
        let progress = t(
            "v2.instalments.paidOf", "{paid} sur {count} payées",
            ["paid": plan.paidCount, "count": plan.count]
        )
        guard let next = plan.next else { return progress }
        return progress + " · " + dayLabel(next.day)
    }

    // MARK: Les lignes

    private func rows(_ list: [Transaction]) -> some View {
        ForEach(list) { tx in
            EdRule()
            Button { detail = tx } label: { row(tx) }
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
        return PayeeText.title(tx.payee, category: tx.categoryName)
    }

    private func row(_ tx: Transaction) -> some View {
        HStack(spacing: 12) {
            // Un virement entre ses propres comptes n'a pas de marchand : le
            // « marchand », là, c'est soi.
            let face = tx.isTransfer ? nil : logos.face(for: tx.payee)
            Bubble(
                label: tx.categoryName ?? tx.payee,
                emoji: face?.emoji ?? tx.categoryEmoji,
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
