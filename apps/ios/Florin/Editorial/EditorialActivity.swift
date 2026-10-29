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
                .id(edTopAnchor)
                if searching { searchField }
                EdPill(
                    text: t("v2.activity.title", "Activité") + " · "
                        + t("v2.activity.count", "{count} opérations", ["count": model.total])
                )
                .padding(.top, 18)

                waiting

                if let first = days.first {
                    hero(first)
                }

                ForEach(Array(days.enumerated()), id: \.element.day) { index, section in
                    if index > 0 {
                        EdSection(text: dayLabel(section.day))
                            .padding(.top, 34)
                            .padding(.bottom, 6)
                            .edEnter()
                    }
                    rows(section.rows)
                }

                footer
            }
            .padding(.horizontal, Ed.gutter)
            .padding(.top, 10)
            .padding(.bottom, 120)
        }
        .edRewind(.activity, chrome: chrome)
        .scrollIndicators(.hidden)
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
                    symbol: "person.crop.circle",
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

    private func hero(_ section: (day: Date, rows: [Transaction])) -> some View {
        let net = section.rows.reduce(0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 10) {
            EdHero(text: dayLabel(section.day))
            Text(Money.string(
                net, locale: locale, currency: currency, decimals: false, signed: true
            ))
            .font(.system(size: 20, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(net < 0 ? Florin.text2 : Florin.text)
            .edNumeric(net)
        }
        .padding(.top, 14)
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

    /// Deux plis, repliés par défaut : ce qui vient de la banque, et ce qu'on
    /// a soi-même étalé en plusieurs fois. Ils comptent leur total et leur
    /// nombre sans déplier, ce qui est presque toujours tout ce qu'on venait
    /// y lire.
    @ViewBuilder
    private var waiting: some View {
        if !upcoming.isEmpty || !instalments.isEmpty {
            VStack(spacing: 10) {
                if !upcoming.isEmpty {
                    fold(
                        title: t("v2.activity.upcomingCount", "{count} à venir",
                                 ["count": upcoming.count]),
                        rows: upcoming,
                        open: $upcomingOpen,
                        inverse: false
                    )
                }
                if !instalments.isEmpty {
                    fold(
                        title: t("v2.activity.instalmentPlanCount",
                                 "{count} en plusieurs fois",
                                 ["count": instalments.count]),
                        rows: instalments,
                        open: $instalmentsOpen,
                        inverse: true
                    )
                }
            }
            .padding(.top, 22)
        }
    }

    private func fold(
        title: String, rows: [Transaction], open: Binding<Bool>, inverse: Bool
    ) -> some View {
        let total = rows.reduce(0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(EdMotion.spring) { open.wrappedValue.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        EdInk(text: title, size: 13, dim: true)
                        EdInk(
                            text: Money.string(
                                total, locale: locale, currency: currency,
                                decimals: false, signed: true
                            ),
                            size: 22, weight: .medium
                        )
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(inverse ? Florin.bg : Florin.text2)
                        .rotationEffect(.degrees(open.wrappedValue ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.edPress)

            if open.wrappedValue {
                ForEach(rows) { tx in
                    Rectangle()
                        .fill((inverse ? Florin.bg : Florin.text).opacity(0.12))
                        .frame(height: 1)
                        .padding(.top, 10)
                    Button { detail = tx } label: { foldedRow(tx, inverse: inverse) }
                        .buttonStyle(.edPress)
                        .transactionMenu(
                            tx, t: t, locale: locale, currency: currency,
                            canTransfer: !tx.isTransfer && tx.amount < 0
                                && model.accounts.count > 1,
                            request: $menuRequest,
                            isLocalLedger: model.isLocalLedger
                        )
                        .buttonStyle(.edPress)
                }
                .transition(.opacity)
            }
        }
        .modifier(EdFoldSkin(inverse: inverse))
    }

    private func foldedRow(_ tx: Transaction, inverse: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                EdInk(text: title(tx), size: 15, weight: .medium)
                    .lineLimit(1)
                EdInk(text: dayLabel(tx.day), size: 12, dim: true)
            }
            Spacer(minLength: 8)
            EdInk(
                text: Money.string(
                    tx.amount, locale: locale, currency: currency, signed: true
                ),
                size: 15, weight: .medium
            )
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
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
             * Aucune couleur sur un montant.
             *
             * L'accent était donné aux entrées, ce qui mettait en alerte le
             * remboursement de huit euros et laissait en blanc le loyer. Dans
             * ce thème l'orange ne veut dire qu'une chose — quelque chose
             * demande une décision — et une rentrée d'argent n'en demande
             * aucune. Le signe suffit à dire le sens.
             */
            EdAmountPill(
                text: Money.string(
                    tx.amount, locale: locale, currency: currency, signed: true
                )
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
