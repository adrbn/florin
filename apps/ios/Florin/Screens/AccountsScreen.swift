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

    @Environment(\.colorScheme) private var colorScheme
    @State private var drill: ActivityRoute?
    @State private var showNet = true

    private var t: Strings { model.overview?.t ?? .empty }

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
    }

    private func loaded(_ data: Overview) -> some View {
        TabScaffold(tint: TabRoute.accounts.tint, refresh: { await model.sync() }) {
            TopBar(onProfile: onOpenSettings) {
                Text(t("v2.nav.accounts", "Comptes"))
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
            } trailing: {
                CircleButton(symbol: "arrow.trianglehead.2.clockwise", size: 44) {
                    Task { await model.sync() }
                }
                .disabled(model.syncing || !data.bankSyncConfigured)
                .opacity(model.syncing ? 0.5 : 1)
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
                            Button {
                                drill = ActivityRoute(accountId: account.id, title: account.name)
                            } label: {
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
                            }
                            .buttonStyle(.plain)
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
            ("v2.accounts.group.cash", "Comptes courants", ["checking", "cash"]),
            ("v2.accounts.group.savings", "Épargne", ["savings"]),
            ("v2.accounts.group.invest", "Investissements", ["broker_cash", "broker_portfolio"]),
            ("v2.accounts.group.debt", "Crédits", ["loan"]),
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
            t: model.overview?.t ?? .empty,
            preset: route,
            heroValue: account?.displayValue,
            heroCaption: account.flatMap { a in
                a.institution?.isEmpty == false ? a.institution : a.name
            } ?? route.title,
            showsBack: true
        )
    }
}
