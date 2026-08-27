import Charts
import SwiftUI

/// Analyse, natively.
///
/// Four views of the same year, on chips rather than in one long scroll: where
/// the money went, what is changing, income against spending, and what renews
/// on its own. Each is a different question and stacking all four made a screen
/// nobody reached the bottom of.
struct AnalysisScreen: View {
    @ObservedObject var overview: OverviewModel
    var route: (TabRoute, String) -> Void = { _, _ in }
    var onOpenSettings: () -> Void = {}

    @StateObject private var model: AnalysisModel
    @State private var tab: Tab = .where_
    @State private var drill: ActivityRoute?
    @State private var pickedMonth: MonthlyFlow?
    @State private var expanded: String?

    init(
        overview: OverviewModel,
        route: @escaping (TabRoute, String) -> Void = { _, _ in },
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.overview = overview
        self.route = route
        self.onOpenSettings = onOpenSettings
        _model = StateObject(wrappedValue: AnalysisModel(base: overview.base))
    }

    private enum Tab: Hashable { case where_, trends, flows, subs }

    private var t: Strings { overview.overview?.t ?? .device }
    private var locale: String { overview.overview?.localeTag ?? "fr-FR" }
    private var currency: String { overview.overview?.currency ?? "EUR" }

    var body: some View {
        TabScaffold(tint: TabRoute.analysis.tint, refresh: { await model.load() }) {
            TopBar(onProfile: onOpenSettings) {
                    Text(t("v2.analysis.title", "Analyse"))
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                } trailing: {
                    CircleButton(symbol: "arrow.left.arrow.right", size: 44) {
                        route(.activity, TabRoute.activity.rootPath)
                    }
                }
                .padding(.bottom, 24)

            hero
            ChipBar(options: chips, selection: tabBinding)
            content
        }
        .fullScreenCover(item: $drill) { target in
            AccountDetailScreen(model: overview, route: target)
        }
        .task { if model.data == nil { await model.load() } }
    }

    private var tabBinding: Binding<Tab> {
        Binding(
            get: { tab },
            set: { next in
                pickedMonth = nil
                expanded = nil
                tab = next
            }
        )
    }

    private var chips: [(value: Tab, label: String, badge: Int)] {
        [
            (.where_, t("v2.analysis.tab.overview", "Où"), 0),
            (.trends, t("v2.analysis.tab.trends", "Tendances"), 0),
            (.flows, t("v2.analysis.tab.flows", "Flux"), 0),
            (.subs, t("v2.analysis.tab.subs", "Abonnements"), 0),
        ]
    }

    /// The headline follows the visible tab — a fixed figure over four different
    /// views would be describing the wrong one three times. On Flux it also
    /// follows the scrub, so dragging across the bars reads out that month.
    private var hero: some View {
        let data = model.data
        let (caption, value, sub): (String, Double, String) = {
            switch tab {
            case .where_:
                let total = data?.categories.reduce(0) { $0 + $1.total } ?? 0
                return (
                    t("v2.analysis.spent30", "Dépensé sur 30 jours"), total,
                    t("v2.analysis.categoriesCount", "{count} catégories",
                      ["count": data?.categories.count ?? 0])
                )
            case .trends:
                let rows = movers(data)
                let up = rows.filter { $0.delta > 0 }.count
                return (
                    t("v2.analysis.spent12", "Dépensé sur 12 mois"),
                    data?.categorySeries.categories.reduce(0) { $0 + $1.total } ?? 0,
                    t("v2.analysis.moversHint", "{count} catégories en hausse", ["count": up])
                )
            case .flows:
                if let month = pickedMonth {
                    return (
                        MonthLabel.long(month.month, locale: locale),
                        month.net,
                        Money.string(month.income, locale: locale, currency: currency, decimals: false)
                            + " − "
                            + Money.string(month.expense, locale: locale, currency: currency, decimals: false)
                    )
                }
                let net = data?.flows.reduce(0) { $0 + $1.net } ?? 0
                let months = data?.flows.count ?? 0
                return (
                    t("v2.analysis.netFlow", "Solde net sur 12 mois"), net,
                    months > 0
                        ? t("v2.analysis.perMonth", "{amount} par mois en moyenne",
                            ["amount": Money.string(net / Double(months), locale: locale,
                                                    currency: currency, decimals: false)])
                        : ""
                )
            case .subs:
                let annual = data?.subscriptions.reduce(0) { $0 + $1.annualCost } ?? 0
                return (
                    t("v2.analysis.subsAnnual", "Abonnements par an"), annual,
                    Money.string(annual / 12, locale: locale, currency: currency, decimals: false)
                        + " " + t("v2.analysis.perMonthShort", "par mois")
                )
            }
        }()

        return HeroBlock(
            caption: caption, value: value, locale: locale, currency: currency, size: 44
        ) {
            Text(sub)
                .font(.system(size: 13))
                .foregroundStyle(Florin.text2)
                .multilineTextAlignment(.center)
                // Some tabs put real amounts in this line.
                .hiddenWhenPrivate()
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var content: some View {
        if let data = model.data {
            switch tab {
            case .where_: whereTab(data)
            case .trends: trendsTab(data)
            case .flows: flowsTab(data)
            case .subs: subsTab(data)
            }
        } else if let failure = model.failure {
            VStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark").font(.system(size: 28))
                Text(failure).font(.system(size: 14)).multilineTextAlignment(.center)
                Button(t("v2.common.retry", "Réessayer")) { Task { await model.load() } }
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Florin.text2)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Florin.gutter)
            .padding(.vertical, 60)
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 60)
        }
    }

    // MARK: - Où

    private func whereTab(_ data: AnalysisData) -> some View {
        let ranked = data.categories.sorted { $0.total > $1.total }
        let total = ranked.reduce(0) { $0 + $1.total }
        let peak = ranked.first?.total ?? 1
        let byGroup = groupTotals(ranked)

        return VStack(alignment: .leading, spacing: 30) {
            if byGroup.count > 1 {
                ScreenSection(title: t("v2.analysis.byGroup", "Par poste")) {
                    FlorinCard {
                        AllocationCard(
                            slices: byGroup.map {
                                (label: $0.name, value: $0.total,
                                 color: Florin.seriesColor(for: $0.name))
                            },
                            center: Money.compact(total, locale: locale, currency: currency),
                            caption: t("v2.analysis.days30", "30 jours"),
                            locale: locale,
                            currency: currency
                        )
                    }
                    .padding(.horizontal, Florin.gutter)
                }
            }

            ScreenSection(
                title: t("v2.analysis.byCategory", "Par catégorie"),
                trailing: t("v2.analysis.tapToOpen", "touche pour ouvrir")
            ) {
                FlorinCard {
                    VStack(spacing: 15) {
                        ForEach(ranked.prefix(12)) { share in
                            Button {
                                guard let id = data.categoryIds[share.id] else { return }
                                UISelectionFeedbackGenerator().selectionChanged()
                                drill = ActivityRoute(categoryId: id, title: share.categoryName)
                            } label: {
                                RankBar(
                                    label: share.categoryName,
                                    emoji: share.emoji,
                                    value: share.total,
                                    peak: peak,
                                    share: total > 0 ? share.total / total : 0,
                                    locale: locale,
                                    currency: currency
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, Florin.gutter)
            }

            ScreenSection(
                title: t("v2.overview.savingsRate", "Taux d'épargne"),
                trailing: t("v2.analysis.completeMonths", "mois complets")
            ) {
                FlorinCard {
                    HStack {
                        rate("3", data.savings.threeMonth)
                        rate("6", data.savings.sixMonth)
                        rate("12", data.savings.twelveMonth)
                    }
                }
                .padding(.horizontal, Florin.gutter)
            }

            if let age = data.ageOfMoney {
                ScreenSection(title: t("v2.analysis.ageOfMoney", "Âge de l'argent")) {
                    FlorinCard {
                        HStack(alignment: .center, spacing: 14) {
                            Bubble(label: "age", systemImage: "hourglass", size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("\(Int(age.rounded()))")
                                        .font(.system(size: 30, weight: .light))
                                        .monospacedDigit()
                                        .foregroundStyle(Florin.text)
                                    Text(t("v2.common.days", "jours"))
                                        .font(.system(size: 14))
                                        .foregroundStyle(Florin.text2)
                                }
                                Text(
                                    t(
                                        "v2.analysis.ageOfMoneyHint",
                                        "Depuis combien de temps l'argent dépensé était là"
                                    )
                                )
                                .font(.system(size: 11.5))
                                .foregroundStyle(Florin.text3)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.horizontal, Florin.gutter)
                }
            }
        }
    }

    private func groupTotals(_ shares: [CategoryShare]) -> [(name: String, total: Double)] {
        var order: [String] = []
        var sums: [String: Double] = [:]
        for share in shares {
            if sums[share.groupName] == nil { order.append(share.groupName) }
            sums[share.groupName, default: 0] += share.total
        }
        return order
            .map { (name: $0, total: sums[$0] ?? 0) }
            .sorted { $0.total > $1.total }
    }

    private func rate(_ label: String, _ value: Double?) -> some View {
        VStack(spacing: 4) {
            Text(Money.percent(value, locale: locale, digits: 0))
                .font(.system(size: 22, weight: .light))
                .monospacedDigit()
                .foregroundStyle(
                    value == nil
                        ? Florin.text3
                        : ((value ?? 0) >= 0 ? Florin.positive : Florin.negative)
                )
            Text("\(label) " + t("v2.common.months", "mois"))
                .font(.system(size: 11.5))
                .foregroundStyle(Florin.text3)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tendances

    private struct Mover: Identifiable {
        let row: CategorySeries.Row
        /// Last complete month against the average of the ones before it, in %.
        let delta: Double
        let last: Double
        var id: String { row.id }
    }

    /// Ranked by how much a category moved, not by how big it is.
    ///
    /// "Loyer 929 €" is the largest line every single month and tells you
    /// nothing; "Transports +64 %" is the one worth a screen. The comparison
    /// drops the current month — it is incomplete, so it always looks like a
    /// collapse — and averages the rest of the window.
    private func movers(_ data: AnalysisData?) -> [Mover] {
        guard let data else { return [] }
        return data.categorySeries.categories.compactMap { row -> Mover? in
            let series = row.monthly.dropLast()
            guard series.count >= 3, let last = series.last else { return nil }
            let prior = series.dropLast()
            let average = prior.reduce(0, +) / Double(prior.count)
            guard average > 1 else { return nil }
            return Mover(row: row, delta: (last - average) / average * 100, last: last)
        }
        .sorted { abs($0.delta) > abs($1.delta) }
    }

    private func trendsTab(_ data: AnalysisData) -> some View {
        let months = data.categorySeries.months
        let ranked = movers(data)
        let others = data.categorySeries.categories
            .filter { row in !ranked.contains { $0.id == row.id } }
            .sorted { $0.total > $1.total }

        return VStack(alignment: .leading, spacing: 30) {
            if !ranked.isEmpty {
                ScreenSection(
                    title: t("v2.analysis.movers", "Ce qui bouge"),
                    trailing: t("v2.analysis.vsAverage", "vs moyenne")
                ) {
                    VStack(spacing: 10) {
                        ForEach(ranked.prefix(8)) { mover in
                            trendRow(
                                mover.row, months: months, delta: mover.delta,
                                categoryIds: data.categoryIds
                            )
                        }
                    }
                    .padding(.horizontal, Florin.gutter)
                }
            }

            if !others.isEmpty {
                ScreenSection(title: t("v2.analysis.stable", "Stable")) {
                    VStack(spacing: 10) {
                        ForEach(others.prefix(6)) { row in
                            trendRow(row, months: months, delta: nil, categoryIds: data.categoryIds)
                        }
                    }
                    .padding(.horizontal, Florin.gutter)
                }
            }
        }
    }

    /// A category's year, expandable.
    ///
    /// Collapsed it is a sparkbar wide enough to see a shape in; tapping opens
    /// the same twelve months at full width with labels, which is the only size
    /// at which "which month was that spike" is answerable.
    private func trendRow(
        _ row: CategorySeries.Row,
        months: [String],
        delta: Double?,
        categoryIds: [String: String]
    ) -> some View {
        let open = expanded == row.id
        let tint = Florin.seriesColor(for: row.categoryName)

        /*
         * Stacked, not strung out.
         *
         * The first version put the name, the total, a sparkline and a delta
         * chip on one line, and on a 393pt screen every one of them lost:
         * "Vêtements & beauté" truncated to "Vêtements…", "1 405 € · sur 12
         * mois" wrapped to two lines, and "426 %" broke across the chip. Giving
         * the row three short lines — identity, figure, shape — fits every
         * category name there is and makes the bars wide enough to read.
         */
        return VStack(spacing: 0) {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.snappy(duration: 0.28)) { expanded = open ? nil : row.id }
            } label: {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 10) {
                        Bubble(label: row.categoryName, emoji: row.emoji, size: 32)
                        Text(row.categoryName)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Florin.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 6)
                        DeltaChip(delta: delta)
                        Image(systemName: open ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Florin.text3)
                    }

                    HStack(spacing: 6) {
                        AmountText(
                            value: row.total, locale: locale, currency: currency,
                            decimals: false, size: 14
                        )
                        Text(t("v2.analysis.over12", "sur 12 mois"))
                            .font(.system(size: 12))
                            .foregroundStyle(Florin.text3)
                        Spacer(minLength: 0)
                    }

                    if !open {
                        SparkBars(values: row.monthly, tint: tint)
                            .frame(height: 30)
                    }
                }
                .padding(.horizontal, Florin.gutter)
                .padding(.vertical, 13)
            }
            .buttonStyle(.plain)

            if open {
                VStack(spacing: 12) {
                    CategoryYearChart(
                        months: months, values: row.monthly, tint: tint,
                        locale: locale, currency: currency
                    )
                    .frame(height: 130)

                    Button {
                        drill = ActivityRoute(categoryId: row.categoryId, title: row.categoryName)
                    } label: {
                        Text(t("v2.analysis.openCategory", "Voir les opérations"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Florin.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Florin.accent.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Florin.gutter)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .florinSurface()
    }

    // MARK: - Flux

    private func flowsTab(_ data: AnalysisData) -> some View {
        VStack(alignment: .leading, spacing: 30) {
            ScreenSection(
                title: t("v2.analysis.tab.flows", "Flux"),
                trailing: t("v2.analysis.scrubHint", "glisse sur le graphique")
            ) {
                FlorinCard {
                    VStack(spacing: 14) {
                        FlowChart(
                            flows: data.flows,
                            selection: $pickedMonth,
                            locale: locale,
                            currency: currency
                        )
                        .frame(height: 200)

                        HStack(spacing: 16) {
                            legend(t("v2.analysis.income", "Entrées"), Florin.positive)
                            legend(t("v2.analysis.expenses", "Dépenses"), Florin.negative)
                            legend(t("v2.analysis.net", "Net"), Florin.accent)
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, Florin.gutter)
            }

            ScreenSection(title: t("v2.analysis.monthByMonth", "Mois par mois")) {
                RowGroup {
                    HStack {
                        Text(t("v2.analysis.month", "Mois"))
                            .frame(width: 62, alignment: .leading)
                        Text(t("v2.analysis.income", "Entrées"))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(t("v2.analysis.expenses", "Dépenses"))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(t("v2.analysis.net", "Net"))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Florin.text3)
                    .padding(.horizontal, Florin.gutter)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    ForEach(Array(data.flows.reversed().enumerated()), id: \.element.id) { index, flow in
                        if index > 0 { Hairline() }
                        HStack {
                            Text(MonthLabel.short(flow.month, locale: locale).capitalized)
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(Florin.text)
                                .frame(width: 62, alignment: .leading)
                            AmountText(value: flow.income, locale: locale, currency: currency,
                                       decimals: false, tone: .positive, size: 13)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            AmountText(value: -flow.expense, locale: locale, currency: currency,
                                       decimals: false, tone: .negative, size: 13)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            AmountText(value: flow.net, locale: locale, currency: currency,
                                       decimals: false, signed: true, tone: .auto, size: 13,
                                       weight: .semibold)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.horizontal, Florin.gutter)
                        .padding(.vertical, 11)
                        .background(
                            pickedMonth?.id == flow.id
                                ? Florin.accent.opacity(0.10) : Color.clear
                        )
                    }
                }
                .padding(.horizontal, Florin.gutter)
            }
        }
    }

    private func legend(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 12, height: 4)
            Text(label).font(.system(size: 11.5)).foregroundStyle(Florin.text2)
        }
    }

    // MARK: - Abonnements

    private func subsTab(_ data: AnalysisData) -> some View {
        let sorted = data.subscriptions.sorted { $0.annualCost > $1.annualCost }
        let monthly = sorted.reduce(0) { $0 + $1.annualCost } / 12

        return VStack(alignment: .leading, spacing: 30) {
            if sorted.isEmpty {
                FlorinCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t("v2.analysis.subsEmpty", "Aucun abonnement détecté"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Florin.text)
                        Text(
                            t(
                                "v2.analysis.subsEmptyWhy",
                                "Florin cherche un même bénéficiaire, au même montant, au moins trois fois, toutes les 4 semaines environ ou toutes les semaines, sur les 6 derniers mois. Si ta banque colle une date ou un numéro de carte dans le libellé, chaque prélèvement compte comme un bénéficiaire différent et rien ne ressort."
                            )
                        )
                        .font(.system(size: 12.5))
                        .foregroundStyle(Florin.text2)
                    }
                }
                .padding(.horizontal, Florin.gutter)
            } else {
                ScreenSection(
                    title: t("v2.analysis.tab.subs", "Abonnements"),
                    trailing: Money.string(monthly, locale: locale, currency: currency, decimals: false)
                        + " / " + t("v2.analysis.perMonthShort", "par mois")
                ) {
                    RowGroup {
                        ForEach(Array(sorted.enumerated()), id: \.element.id) { index, sub in
                            if index > 0 { Hairline() }
                            HStack(spacing: 12) {
                                Bubble(label: sub.categoryName ?? sub.payee, systemImage: "repeat")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(PayeeText.humanize(sub.payee))
                                        .font(.system(size: 14.5, weight: .medium))
                                        .foregroundStyle(Florin.text)
                                        .lineLimit(1)
                                    Text(cadence(sub) + " · " + lastSeen(sub))
                                        .font(.system(size: 12))
                                        .foregroundStyle(Florin.text2)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 2) {
                                    AmountText(value: -abs(sub.amount), locale: locale,
                                               currency: currency, tone: .negative)
                                    Text(
                                        Money.string(sub.annualCost, locale: locale,
                                                     currency: currency, decimals: false)
                                            + "/" + t("v2.common.year", "an")
                                    )
                                    .font(.system(size: 11))
                                    .foregroundStyle(Florin.text3)
                                    .hiddenWhenPrivate()
                                }
                            }
                            .padding(.horizontal, Florin.gutter)
                            .padding(.vertical, 11)
                        }
                    }
                    .padding(.horizontal, Florin.gutter)
                }
            }
        }
    }

    /// "tous les 32 j" is technically right and useless; people think in
    /// months, weeks and years.
    private func cadence(_ sub: SubscriptionMatch) -> String {
        switch sub.cadenceDays {
        case 25...35: return t("v2.analysis.monthly", "Mensuel")
        case 6...8: return t("v2.analysis.weekly", "Hebdomadaire")
        case 12...16: return t("v2.analysis.biweekly", "Toutes les 2 semaines")
        case 85...95: return t("v2.analysis.quarterly", "Trimestriel")
        case 350...380: return t("v2.analysis.yearly", "Annuel")
        default: return t("v2.analysis.every", "Tous les {count} j", ["count": sub.cadenceDays])
        }
    }

    private func lastSeen(_ sub: SubscriptionMatch) -> String {
        let date = ISO8601DateFormatter.florin.date(from: sub.lastSeen)
            ?? ISO8601DateFormatter.florinNoFraction.date(from: sub.lastSeen)
        guard let date else { return sub.lastSeen.prefix(10).description }
        return t("v2.analysis.lastSeen", "vu {date}",
                 ["date": DayLabel.string(date, locale: locale, t: t)])
    }
}

// MARK: - Charts

/// Income against spending, with the net as a line over the top.
///
/// Grouped bars alone answer "did I earn more than I spent" only by eye; the
/// line makes it a shape. Scrubbing selects a month rather than showing a
/// tooltip, because the headline above is already the right place to read it.
struct FlowChart: View {
    let flows: [MonthlyFlow]
    @Binding var selection: MonthlyFlow?
    let locale: String
    let currency: String

    var body: some View {
        Chart {
            ForEach(flows) { flow in
                BarMark(
                    x: .value("Mois", MonthLabel.short(flow.month, locale: locale)),
                    y: .value("Montant", flow.income)
                )
                .position(by: .value("Sens", "in"))
                .foregroundStyle(Florin.positive.opacity(selection == nil || selection?.id == flow.id ? 0.95 : 0.3))
                .cornerRadius(3)

                BarMark(
                    x: .value("Mois", MonthLabel.short(flow.month, locale: locale)),
                    y: .value("Montant", flow.expense)
                )
                .position(by: .value("Sens", "out"))
                .foregroundStyle(Florin.negative.opacity(selection == nil || selection?.id == flow.id ? 0.9 : 0.28))
                .cornerRadius(3)

                LineMark(
                    x: .value("Mois", MonthLabel.short(flow.month, locale: locale)),
                    y: .value("Net", flow.net),
                    series: .value("Série", "net")
                )
                .foregroundStyle(Florin.accent)
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .interpolationMethod(.monotone)
            }

            if let selection {
                RuleMark(x: .value("Mois", MonthLabel.short(selection.month, locale: locale)))
                    .foregroundStyle(Florin.text.opacity(0.16))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Florin.text.opacity(0.06))
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(Money.compact(amount, locale: locale, currency: currency))
                            .font(.system(size: 9))
                            .foregroundStyle(Florin.text3)
                            .hiddenWhenPrivate()
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label)
                            .font(.system(size: 9))
                            .foregroundStyle(Florin.text3)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                guard let plot = proxy.plotFrame else { return }
                                let x = drag.location.x - geo[plot].origin.x
                                let width = geo[plot].width
                                guard width > 0, !flows.isEmpty else { return }
                                let index = min(
                                    flows.count - 1,
                                    max(0, Int(x / width * CGFloat(flows.count)))
                                )
                                if flows[index].id != selection?.id {
                                    selection = flows[index]
                                    UISelectionFeedbackGenerator().selectionChanged()
                                }
                            }
                            .onEnded { _ in selection = nil }
                    )
            }
        }
    }
}

/// One category's twelve months, at full width with labels.
struct CategoryYearChart: View {
    let months: [String]
    let values: [Double]
    let tint: Color
    let locale: String
    let currency: String

    private var points: [(month: String, value: Double)] {
        zip(months, values).map { ($0, $1) }
    }

    var body: some View {
        Chart(Array(points.enumerated()), id: \.offset) { _, point in
            BarMark(
                x: .value("Mois", MonthLabel.short(point.month, locale: locale)),
                y: .value("Montant", point.value)
            )
            .foregroundStyle(tint)
            .cornerRadius(4)
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Florin.text.opacity(0.06))
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(Money.compact(amount, locale: locale, currency: currency))
                            .font(.system(size: 9))
                            .foregroundStyle(Florin.text3)
                            .hiddenWhenPrivate()
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label).font(.system(size: 8.5)).foregroundStyle(Florin.text3)
                    }
                }
            }
        }
    }
}

/// A labelled bar, sized against the biggest in the set.
///
/// Normalising per row — which the first web version did — made a 1 013 € month
/// look identical to a 3 787 € one. A shared peak is the only honest scale.
struct RankBar: View {
    let label: String
    var emoji: String?
    let value: Double
    let peak: Double
    var share: Double = 0
    let locale: String
    let currency: String

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                if let emoji, !emoji.isEmpty { Text(emoji).font(.system(size: 13)) }
                Text(label)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Florin.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if share > 0 {
                    Text("\(Int((share * 100).rounded()))%")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(Florin.text3)
                }
                AmountText(value: value, locale: locale, currency: currency, decimals: false, size: 13)
                    .frame(minWidth: 62, alignment: .trailing)
            }
            GeometryReader { geo in
                let width = peak > 0 ? max(3, geo.size.width * value / peak) : 3
                ZStack(alignment: .leading) {
                    Capsule().fill(Florin.text.opacity(0.06))
                    Capsule().fill(Florin.seriesColor(for: label)).frame(width: width)
                }
            }
            .frame(height: 6)
        }
    }
}

/// Twelve months as bars, at thumbnail size. Bars rather than a line: at 26pt
/// tall a line through twelve monthly totals is noise, while bars still read
/// as "one big month, the rest flat".
struct SparkBars: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let peak = values.max() ?? 1
            let gap: CGFloat = 1.5
            let width = max(1.5, (geo.size.width - gap * CGFloat(max(0, values.count - 1)))
                / CGFloat(max(1, values.count)))
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    // A Capsule whose width exceeds its height stops being a
                    // bar and becomes an oval — which is what a low month looked
                    // like. A small fixed radius keeps them reading as bars at
                    // every height.
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint.opacity(index == values.count - 1 ? 1 : 0.55))
                        .frame(
                            width: width,
                            height: max(2, geo.size.height * CGFloat(peak > 0 ? value / peak : 0))
                        )
                }
            }
            .frame(height: geo.size.height, alignment: .bottom)
        }
    }
}

/// Percent change, coloured for spending — up is bad in this column.
struct DeltaChip: View {
    let delta: Double?

    var body: some View {
        if let delta, abs(delta) >= 5 {
            HStack(spacing: 2) {
                Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 8, weight: .bold))
                Text("\(Int(abs(delta).rounded()))%")
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(delta > 0 ? Florin.negative : Florin.positive)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                (delta > 0 ? Florin.negative : Florin.positive).opacity(0.14),
                in: Capsule()
            )
        } else {
            EmptyView()
        }
    }
}
