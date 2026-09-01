import SwiftUI

/// Comptes, natively.
///
/// Same shape as the dashboard — coloured ground, a small top row, a centred
/// headline, labelled bubbles, then content — because the two screens are two
/// views of one number and looked like two products when only one of them had
/// it. Accounts are grouped by kind rather than listed flat: "what have I got"
/// is a question about cash, savings, investments and debt, and a single column
/// of eight rows answers it far worse than four short ones.
struct AccountsScreen: View {
    @ObservedObject var model: OverviewModel
    var route: (TabRoute, String) -> Void = { _, _ in }
    var onOpenSettings: () -> Void = {}
    /*
     * The account a link asked for.
     *
     * Tapping a row under "Vos comptes" on the dashboard switched to this tab
     * and stopped there, leaving the person to find in a list the very thing
     * they had just pointed at. The path already carried the id; nothing read
     * it.
     */
    var openAccountId: String?

    @Environment(\.colorScheme) private var colorScheme
    @State private var drill: ActivityRoute?
    @State private var showNet = true
    @State private var addingAccount = false
    @State private var renaming: Account?
    @State private var deleting: Account?

    /// `.device` and not `.empty`: the alerts and the header can be on screen
    /// before the first feed lands, and an empty table renders the inline French.
    private var t: Strings { model.overview?.t ?? .device }

    var body: some View {
        Group {
            if let data = model.overview {
                loaded(data)
            } else {
                ZStack {
                    Backdrop(tint: TabRoute.accounts.tint)
                    ProgressView().controlSize(.large).tint(Florin.text3)
                }
            }
        }
        /*
         * A cover, not a push.
         *
         * These screens live inside a TabView, and a NavigationStack in each tab
         * brought its own navigation bar back on every pushed destination — on
         * iOS 26 that is a floating glass back button, which landed on top of
         * the screen's own header and shoved everything 60pt down. Hiding the
         * bar per screen did not hold. A cover has no chrome of its own, so the
         * screen is exactly what we draw, and its own header owns the way back.
         */
        .fullScreenCover(item: $drill) { target in
            AccountDetailScreen(model: model, route: target)
        }
        .task(id: openAccountId) {
            guard let openAccountId,
                  let account = model.overview?.accounts.first(where: { $0.id == openAccountId })
            else { return }
            drill = ActivityRoute(accountId: account.id, title: account.name)
        }
        .sheet(isPresented: $addingAccount) {
            AddAccountSheet(onSaved: { Task { await model.load(showSpinner: false) } })
        }
        .sheet(item: $renaming) { account in
            AccountEditSheet(account: account, t: t) { name, icon in
                await commitEdit(account, name: name, icon: icon)
            }
        }
        .alert(
            t("v2.accounts.deleteConfirm", "Supprimer ce compte ?"),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { account in
            Button(t("v2.common.delete", "Supprimer"), role: .destructive) {
                commitDelete(account)
            }
            Button(t("v2.common.cancel", "Annuler"), role: .cancel) { deleting = nil }
        } message: { account in
            // Says what goes with it: an account is rarely alone, and finding
            // out afterwards is not a discovery anyone enjoys.
            Text(t(
                "v2.accounts.deleteBody",
                "{name} et toutes ses opérations seront supprimés de cet appareil. Votre serveur et votre banque ne sont pas touchés.",
                ["name": account.name]
            ))
        }
    }

    private func commitEdit(_ account: Account, name: String, icon: String) async {
        guard let store = LocalStore.shared, !name.isEmpty else { return }
        try? store.database.run(
            "UPDATE accounts SET name = ?, display_icon = ?, updated_at = datetime('now') WHERE id = ?",
            [.text(name), .text(icon), .text(account.id)]
        )
        await model.load(showSpinner: false)
    }

    private func commitDelete(_ account: Account) {
        guard let store = LocalStore.shared else { return }
        deleting = nil
        /*
         * Gone, with its rows, in one transaction.
         *
         * Archiving would leave the transactions counting towards spending
         * while the account they belong to is invisible — a balance nobody can
         * point at. If someone asks for an account to be deleted, the honest
         * answer is that it is.
         */
        try? store.database.transaction {
            try store.database.run(
                "DELETE FROM transactions WHERE account_id = ?", [.text(account.id)]
            )
            try store.database.run("DELETE FROM accounts WHERE id = ?", [.text(account.id)])
        }
        Task { await model.load(showSpinner: false) }
    }

    private func loaded(_ data: Overview) -> some View {
        TabScaffold(tint: TabRoute.accounts.tint, refresh: { await model.refresh() }) {
            TopBar(onProfile: onOpenSettings, centersMiddle: true) {
                Text(t("v2.nav.accounts", "Comptes"))
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } trailing: {
                HStack(spacing: 8) {
                    /*
                     * Adding an account belongs on the accounts screen.
                     *
                     * The only route was the dashboard's empty state, which
                     * disappears the moment a first account exists — so anyone
                     * with one account and a second to add had nowhere to go.
                     *
                     * Device ledger only: with a server, accounts come from
                     * there and one invented here would live somewhere the
                     * server cannot see.
                     */
                    if model.base.scheme == "florin-local" {
                        CircleButton(symbol: "plus", size: 44) { addingAccount = true }
                            .accessibilityLabel(t("v2.accounts.add", "Ajouter un compte"))
                    }
                    /*
                     * It turns while it works.
                     *
                     * A bank round trip takes seconds and the button gave no
                     * sign of it — dimming reads as "disabled", not as "busy",
                     * so the only feedback was the numbers eventually changing.
                     */
                    CircleButton(
                        symbol: "arrow.trianglehead.2.clockwise",
                        size: 44,
                        spinning: model.syncing
                    ) {
                        Task { await model.sync() }
                    }
                    .disabled(model.syncing || !data.bankSyncConfigured)
                }
            }
            .padding(.bottom, 24)

            HeroBlock(
                caption: (showNet
                    ? t("v2.overview.netWorth", "Patrimoine")
                    : t("v2.overview.gross", "Brut")) + " · " + data.currency,
                value: showNet ? data.netWorth.net : data.netWorth.gross,
                locale: data.localeTag,
                currency: data.currency,
                onTap: { withAnimation(.easeInOut(duration: 0.18)) { showNet.toggle() } }
            ) {
                Text(
                    showNet
                        ? t("v2.accounts.count", "{count} comptes", ["count": visible(data).count])
                        : t("v2.overview.debt", "Dettes") + " "
                            + Money.string(data.netWorth.liability, locale: data.localeTag,
                                           currency: data.currency, decimals: false)
                )
                .font(.system(size: 14))
                .foregroundStyle(Florin.text2)
                // In gross mode this line prints the debt.
                .hiddenWhenPrivate()
            }

            // The same curve the dashboard draws, at a glance — this screen is
            // the other half of the same question and looked oddly numeric
            // without it.
            NetWorthChart(
                points: Array((showNet ? (data.netSeries ?? data.series) : (data.grossSeries ?? data.series)).suffix(200)),
                height: 96,
                selection: .constant(nil),
                animationKey: showNet ? "net" : "gross",
                tint: showNet ? Florin.accent : Florin.series[3]
            )
            .padding(.top, 4)
            .allowsHitTesting(false)

            /*
             * No action row here.
             *
             * Every one of the four bubbles that used to sit under this chart
             * — Activité, Répartition, Plan, Analyse — is a tab, one thumb
             * away at the bottom of the screen. They cost ~96pt to duplicate
             * the navigation, and removing them lifts the répartition and the
             * account list into the first screenful, which is what anyone opens
             * this tab to see.
             */
            allocation(data)

            ForEach(buckets(data), id: \.title) { group in
                ScreenSection(
                    title: group.title,
                    trailing: Money.string(group.total, locale: data.localeTag,
                                           currency: data.currency, decimals: false)
                ) {
                    RowGroup {
                        ForEach(Array(group.accounts.enumerated()), id: \.element.id) { index, account in
                            if index > 0 { Hairline() }
                            /*
                             * A tap gesture, so the long press can be heard.
                             *
                             * Wrapped in a Button, the press was consumed
                             * before the context menu ever saw it, so rename
                             * and delete simply never appeared. The same shape
                             * that made Plan's rows unresponsive, for the same
                             * reason: an explicit content shape is unambiguous.
                             */
                            VStack(spacing: 0) {
                                    HStack(spacing: 0) {
                                        AccountRowView(
                                            account: account,
                                            locale: data.localeTag,
                                            currency: data.currency
                                        )
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Florin.text3)
                                            .padding(.trailing, Florin.gutter)
                                    }
                                    ShareBar(
                                        share: assetTotal(data) > 0
                                            ? abs(account.displayValue) / assetTotal(data) : 0,
                                        tint: account.isLoan
                                            ? Florin.negative
                                            : Florin.seriesColor(for: account.name)
                                    )
                                    .padding(.horizontal, Florin.gutter)
                                    .padding(.bottom, 11)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                drill = ActivityRoute(
                                    accountId: account.id, title: account.name
                                )
                            }
                            /*
                             * Rename and delete, where the account is.
                             *
                             * A context menu rather than swipe actions: these
                             * rows are not in a List, so `.swipeActions` is
                             * inert on them — a gesture that silently does
                             * nothing, which this app has been bitten by
                             * before.
                             *
                             * Only on the device ledger. With a server the
                             * accounts belong to it, and renaming one here
                             * would be undone by the next refresh.
                             */
                            .contextMenu {
                                if model.base.scheme == "florin-local" {
                                    Button {
                                        renaming = account
                                                    } label: {
                                        Label(
                                            t("v2.accounts.rename", "Renommer"),
                                            systemImage: "pencil"
                                        )
                                    }
                                    Button(role: .destructive) {
                                        deleting = account
                                    } label: {
                                        Label(
                                            t("v2.common.delete", "Supprimer"),
                                            systemImage: "trash"
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Florin.gutter)
                }
            }
        }
    }

    /// The biggest single holding, so every bar is on the same scale — a bar
    /// normalised per row says nothing at all.
    private func assetTotal(_ data: Overview) -> Double {
        visible(data).map { abs($0.displayValue) }.max() ?? 0
    }

    private func allocation(_ data: Overview) -> some View {
        let slices: [(String, Double, Color)] = [
            (t("v2.overview.cash", "Liquidités"), data.allocation.cash, Florin.series[0]),
            (t("v2.overview.invested", "Investi"), data.allocation.invested, Florin.series[2]),
            (t("v2.overview.debt", "Dettes"), data.allocation.loans, Florin.negative),
        ].filter { $0.1 > 0 }
        let total = slices.reduce(0) { $0 + $1.1 }

        return Group {
            if total > 0 {
                ScreenSection(title: t("v2.overview.allocation", "Répartition")) {
                    FlorinCard {
                        AllocationCard(
                            slices: slices.map { (label: $0.0, value: $0.1, color: $0.2) },
                            center: Money.compact(data.netWorth.gross, locale: data.localeTag,
                                                  currency: data.currency),
                            caption: t("v2.overview.gross", "Brut"),
                            locale: data.localeTag,
                            currency: data.currency
                        )
                    }
                    .padding(.horizontal, Florin.gutter)
                }
            }
        }
    }

    private func visible(_ data: Overview) -> [Account] {
        data.accounts.filter { !$0.isArchived }
    }

    private struct Bucket {
        let title: String
        let accounts: [Account]
        var total: Double { accounts.reduce(0) { $0 + $1.displayValue } }
    }

    private func buckets(_ data: Overview) -> [Bucket] {
        let all = visible(data)
        let definitions: [(String, String, [String])] = [
            ("v2.accounts.group.checking", "Comptes courants", ["checking", "cash"]),
            ("v2.accounts.group.savings", "Épargne", ["savings"]),
            ("v2.accounts.group.broker", "Investissement", ["broker_cash", "broker_portfolio"]),
            ("v2.accounts.group.loan", "Emprunts", ["loan"]),
        ]
        var used = Set<String>()
        var out = definitions.compactMap { key, fallback, kinds -> Bucket? in
            let matched = all.filter { kinds.contains($0.kind) }
            guard !matched.isEmpty else { return nil }
            matched.forEach { used.insert($0.id) }
            return Bucket(title: t(key, fallback), accounts: matched)
        }
        // Anything the buckets do not name still has to appear — a kind added
        // to the schema later must not silently vanish from this screen.
        let rest = all.filter { !used.contains($0.id) }
        if !rest.isEmpty {
            out.append(Bucket(title: t("v2.accounts.group.other", "Autres"), accounts: rest))
        }
        return out
    }
}

/// A filtered ledger to open — one account's, or one category's.
struct ActivityRoute: Hashable, Identifiable {
    var accountId: String?
    var categoryId: String?
    var title: String

    var id: String { "\(accountId ?? "")|\(categoryId ?? "")|\(title)" }
}

/// One account: its balance, then its ledger.
///
/// Deliberately not the web account page. Everything that page adds beyond this
/// — holdings, editing, loan settings — is rare and belongs on a bigger screen;
/// what you actually open an account for on a phone is "what went through it".
struct AccountDetailScreen: View {
    @ObservedObject var model: OverviewModel
    let route: ActivityRoute

    @StateObject private var portfolio: PortfolioModel
    @State private var editingLoan = false

    init(model: OverviewModel, route: ActivityRoute) {
        self.model = model
        self.route = route
        _portfolio = StateObject(wrappedValue: PortfolioModel(base: model.base))
    }

    private var t: Strings { model.overview?.t ?? .device }

    private var account: Account? {
        guard let id = route.accountId else { return nil }
        return model.overview?.accounts.first { $0.id == id }
    }

    var body: some View {
        TransactionList(
            base: model.base,
            tint: TabRoute.accounts.tint,
            title: route.title,
            locale: model.overview?.localeTag ?? "fr-FR",
            currency: model.overview?.currency ?? "EUR",
            t: t,
            preset: route,
            heroValue: account?.displayValue,
            heroCaption: account.flatMap { a in
                a.institution?.isEmpty == false ? a.institution : a.name
            } ?? route.title,
            showsBack: true
        ) {
            portfolioBanner
            loanBanner
        }
        .task {
            guard let account, account.kind.hasPrefix("broker"), let id = route.accountId else { return }
            await portfolio.load(accountId: id)
        }
        .sheet(isPresented: $editingLoan) {
            if let account {
                LoanSettingsSheet(
                    account: account, t: t,
                    locale: model.overview?.localeTag ?? "fr-FR",
                    onSaved: { await model.load(showSpinner: false) }
                )
            }
        }
    }

    /*
     * A loan, and whether the app can follow it.
     *
     * The remaining debt cannot be recovered from the repayments: knowing that
     * 135,91 € leaves every month says nothing about how much was borrowed, at
     * what rate, or over how long. Without the contract the only figure
     * available is the total handed over — which is what this app used to show
     * and is very nearly the opposite of what is owed — so an unconfigured loan
     * says so rather than printing a number that looks like an answer.
     */
    @ViewBuilder
    private var loanBanner: some View {
        if let account, account.kind == "loan" {
            let configured = loanIsConfigured
            Button { editingLoan = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: configured ? "percent" : "exclamationmark.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(configured ? Florin.accent : Florin.warn)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(configured
                             ? t("v2.loan.title", "Votre prêt")
                             : t("v2.loan.setUp", "Renseignez votre prêt"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Florin.text)
                        Text(configured
                             ? t("v2.loan.configured", "Chaque mensualité réduit le capital restant dû.")
                             : t("v2.loan.setUpHint", "Capital, taux et durée — sans eux, le restant dû ne peut pas être calculé."))
                            .font(.system(size: 12))
                            .foregroundStyle(Florin.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Florin.text3)
                }
                // No surface of its own: the list already wraps this slot in a
                // card, and adding one drew a box inside a box.
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var loanIsConfigured: Bool {
        guard let account, let store = LocalStore.shared else { return false }
        return ((try? store.database.scalar(
            "SELECT loan_original_principal FROM accounts WHERE id = ?", [.text(account.id)]
        )?.double) as? Double ?? 0) ?? 0 > 0
    }

    /*
     * What the wrapper did, above its ledger.
     *
     * Opening a PEA to a list of "Ajustement −2 500,00 €" rows answers nothing:
     * those are the mechanical re-valuations, not the story.
     *
     * The euro figure leads and the percentage follows it. A ratio is the
     * honest way to compare two portfolios and the wrong way to feel one —
     * "+0,8 %" says nothing you can spend, and it is the same number whether
     * the wrapper holds three hundred euros or thirty thousand. The gain is
     * measured against everything paid in rather than against the invested
     * slice, because a PEA holds idle cash too and measuring only the invested
     * part flatters a wrapper that is half in cash.
     */
    @ViewBuilder
    private var portfolioBanner: some View {
        if let data = portfolio.payload {
            let v = data.valuation
            let locale = model.overview?.localeTag ?? "fr-FR"
            let currency = model.overview?.currency ?? "EUR"
            let up = v.marche >= 0

            VStack(spacing: 13) {
                VStack(spacing: 2) {
                    Text(t("v2.account.performance", "Plus-value"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Florin.text3)
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        AmountText(
                            value: v.marche, locale: locale, currency: currency,
                            decimals: false, signed: true, tone: .auto, size: 27, weight: .semibold
                        )
                        if let pct = v.performancePct {
                            Text(Money.percent(pct, locale: locale, digits: 1))
                                .font(.system(size: 14, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(up ? Florin.positive : Florin.negative)
                        }
                    }
                }

                HStack(spacing: 0) {
                    stat(t("v2.tools.contributed", "Versé"), v.verse, locale, currency)
                    stat(t("v2.account.marketValue", "Valeur"),
                         v.marketValue + v.cash, locale, currency)
                    if v.cash > 0.5 {
                        stat(t("v2.overview.cash", "Liquidités"), v.cash, locale, currency)
                    }
                }

                if !data.holdings.isEmpty {
                    Hairline()
                    VStack(spacing: 11) {
                        ForEach(data.holdings) { holding in
                            holdingRow(holding, locale: locale, currency: currency)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// One position: what it is, how much of it there is, and what it is worth.
    private func holdingRow(_ holding: Holding, locale: String, currency: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(holding.label)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Florin.text)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    /*
                     * Quantity and price, which the header cannot carry.
                     *
                     * With one position the value on the right repeats the
                     * total above it exactly; this is the line that says
                     * something the header does not.
                     */
                    Text(Money.quantity(holding.quantity, locale: locale))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Florin.text3)
                    if let price = holding.lastPrice {
                        Text("×")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Florin.text3)
                        Text(Money.string(price, locale: locale, currency: currency, decimals: true))
                            .font(.system(size: 11.5))
                            .foregroundStyle(holding.isStale ? Florin.warn : Florin.text3)
                        if holding.isStale {
                            // A quote older than two days describes a market
                            // that has opened and closed since.
                            Image(systemName: "clock.badge.exclamationmark")
                                .font(.system(size: 10))
                                .foregroundStyle(Florin.warn)
                        }
                    }
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                AmountText(
                    value: holding.marketValue, locale: locale,
                    currency: currency, decimals: false, size: 13.5
                )
                if let pct = holding.plusValuePct {
                    Text(Money.percent(pct, locale: locale, digits: 1))
                        .font(.system(size: 11.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(pct >= 0 ? Florin.positive : Florin.negative)
                }
            }
        }
    }

    private func stat(_ label: String, _ value: Double, _ locale: String, _ currency: String) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 11)).foregroundStyle(Florin.text3)
            AmountText(value: value, locale: locale, currency: currency, decimals: false, size: 14)
        }
        .frame(maxWidth: .infinity)
    }
}
