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
    /// The square being read. A wrapper because `sheet(item:)` wants identity
    /// and a Date has none of its own.
    @State private var openDay: OpenDay?
    @State private var tab: Tab = .where_
    @State private var drill: ActivityRoute?
    @State private var pickedMonth: MonthlyFlow?
    @State private var expanded: String?
    /*
     * The calendar's filter, and it lives here rather than in storage.
     *
     * It is a lens, not a preference: a grid quietly missing its rent three
     * weeks after it was taken out would be read as a bug, not as a setting.
     * It survives a tab switch and a refresh, and it is gone with the app.
     */
    @State private var hidden: Set<String> = []
    @State private var filtering = false
    /// The square under the finger, while it is being scrubbed.
    @State private var scrub: Int?
    /// The grid's own width, which is what turns a touch into a square.
    @State private var gridWidth: CGFloat = 0
    /// The month the calendar is showing, "" until the feed says which months
    /// there are — see `shownMonth`.
    @State private var calendarMonth = ""

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

    private enum Tab: Hashable { case where_, trends, flows, calendar, subs }

    private var t: Strings { overview.overview?.t ?? .device }
    private var locale: String { overview.overview?.localeTag ?? "fr-FR" }
    private var currency: String { overview.overview?.currency ?? "EUR" }

    var body: some View {
        TabScaffold(tint: TabRoute.analysis.tint, refresh: { await model.load() }) {
            TopBar(onProfile: onOpenSettings, centersMiddle: true) {
                    Text(t("v2.analysis.title", "Analyse"))
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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
        .sheet(item: $openDay) { open in
            DaySheet(
                date: open.date, locale: locale, currency: currency, t: t,
                // The filter goes with it: a square that says 96 € because the
                // rent is out has to open onto a day that says 96 € too.
                scope: hidden.isEmpty
                    ? nil
                    : CalendarFilterLabel.short(
                        hidden: hidden,
                        categories: model.data?.spendCategories ?? [],
                        t: t
                    ),
                load: { model.day($0, excluding: hidden) }
            )
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
            (.calendar, t("v2.analysis.tab.calendar", "Calendrier"), 0),
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
                        MonthLabel.long(month.month, locale: locale)
                            + (month.isRunning
                               ? " · " + t("v2.analysis.running", "en cours") : ""),
                        month.net,
                        Money.string(month.income, locale: locale, currency: currency, decimals: false)
                            + " − "
                            + Money.string(month.expense, locale: locale, currency: currency, decimals: false)
                    )
                }
                // Months that are over. Counting the running one turned a year
                // of saving into a smaller number every time the salary was a
                // week away, and the average it divided by said twelve.
                let settled = (data?.flows ?? []).filter { !$0.isRunning }
                let net = settled.reduce(0) { $0 + $1.net }
                return (
                    t("v2.analysis.netFlowN", "Solde net sur {count} mois",
                      ["count": settled.count]),
                    net,
                    settled.isEmpty
                        ? ""
                        : t("v2.analysis.perMonth", "{amount} par mois en moyenne",
                            ["amount": Money.string(net / Double(settled.count), locale: locale,
                                                    currency: currency, decimals: false)])
                )
            case .calendar:
                // The month on screen, so the headline counts the same days
                // and the same categories the grid under it is drawing.
                let byDay = data.map(filteredDays) ?? [:]
                let month = shownMonth(calendarMonths(byDay))
                let days = monthCells(byDay, month: month).compactMap { $0 }.filter { !$0.future }
                let spent = days.reduce(0) { $0 + $1.amount }
                let active = days.filter { $0.amount > 0 }.count
                let window = t("v2.analysis.spentMonth", "Dépensé en {month}",
                               ["month": MonthLabel.long(month, locale: locale)])
                return (
                    hidden.isEmpty
                        ? window
                        : t("v2.calendar.heroScope", "{window} · {filter}",
                            ["window": window,
                             "filter": CalendarFilterLabel.short(
                                hidden: hidden, categories: data?.spendCategories ?? [], t: t)]),
                    spent,
                    active > 0
                        ? t("v2.analysis.perActiveDay", "{amount} les jours de dépense",
                            ["amount": Money.string(spent / Double(active), locale: locale,
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
            case .calendar: calendarTab(data)
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

                        if let running = data.flows.last, running.isRunning {
                            Text(t("v2.analysis.runningNote",
                                   "{month} en cours : les barres s'arrêtent à aujourd'hui, la courbe et la moyenne ne comptent que les mois terminés.",
                                   ["month": MonthLabel.long(running.month, locale: locale)]))
                                .font(.system(size: 11.5))
                                .foregroundStyle(Florin.text3)
                                .frame(maxWidth: .infinity, alignment: .leading)
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

                    ForEach(Array(monthRows(data).enumerated()), id: \.element.flow.id) { index, entry in
                        // The window covers two years, and "Sept." sits twice
                        // in the same column — thirteen rows apart, with no
                        // way to tell which one is this year's.
                        if let year = entry.year {
                            if index > 0 { Hairline() }
                            Text(year)
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(0.6)
                                .foregroundStyle(Florin.text3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Florin.gutter)
                                .padding(.top, index > 0 ? 14 : 2)
                                .padding(.bottom, 6)
                        } else if index > 0 {
                            Hairline()
                        }
                        let flow = entry.flow
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(MonthLabel.short(flow.month, locale: locale).capitalized)
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(Florin.text)
                                if flow.isRunning {
                                    Text(t("v2.analysis.running", "en cours"))
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .tracking(0.3)
                                        .foregroundStyle(Florin.accent)
                                        .lineLimit(1)
                                        .fixedSize()
                                }
                            }
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

    /// The table's rows, each carrying the year when it is not the year of
    /// the row above it.
    private func monthRows(_ data: AnalysisData) -> [(flow: MonthlyFlow, year: String?)] {
        var previous: String?
        return data.flows.reversed().map { flow in
            let year = String(flow.month.prefix(4))
            defer { previous = year }
            return (flow, year == previous ? nil : year)
        }
    }

    private func legend(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 12, height: 4)
            Text(label).font(.system(size: 11.5)).foregroundStyle(Florin.text2)
        }
    }

    // MARK: - Calendrier

    /*
     * A month of spending, one square per day — and every month the ledger
     * holds, a swipe apart.
     *
     * It drew a rolling five weeks, week-aligned rather than by month, because
     * that is the window the query returned. Which meant the one question a
     * calendar is for — "what did I spend on the 14th", "which month was the
     * heavy one" — could only be asked about the last five weeks, and the grid
     * straddled two month names without printing either. Now the squares are a
     * real month, the header says which, and the past is a swipe to the left
     * for as far back as there are transactions.
     *
     * The shades are cut over the whole history rather than per month, so the
     * same colour means the same money in March as in September; a scale that
     * renormalised on every swipe would make a quiet month look like a heavy
     * one.
     */
    private func calendarTab(_ data: AnalysisData) -> some View {
        let byDay = filteredDays(data)
        let months = calendarMonths(byDay)
        let month = shownMonth(months)
        let cells = monthCells(byDay, month: month).compactMap { $0 }.filter { !$0.future }
        let cuts = heatCuts(Array(byDay.values))
        let quiet = cells.filter { $0.amount <= 0 }.count
        let heaviest = cells.max { $0.amount < $1.amount }
        let total = cells.reduce(0) { $0 + max(0, $1.amount) }

        return VStack(alignment: .leading, spacing: 30) {
            VStack(alignment: .leading, spacing: 12) {
                calendarHeader(data)

                FlorinCard {
                    VStack(alignment: .leading, spacing: 10) {
                        monthBar(months, month: month, total: total)
                        weekdayRow
                        monthPages(byDay, months: months, cuts: cuts)
                        legend
                    }
                }
                .padding(.horizontal, Florin.gutter)
            }

            if let heaviest, heaviest.amount > 0 {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: t("v2.analysis.busiestDay", "Jour le plus lourd"))
                        .padding(.horizontal, Florin.gutter)
                    FlorinCard {
                        HStack {
                            Text(DayLabel.string(heaviest.date, locale: locale, t: t))
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            AmountText(value: -heaviest.amount, locale: locale,
                                       currency: currency, decimals: false, signed: false)
                        }
                    }
                    .padding(.horizontal, Florin.gutter)
                    if quiet > 0 {
                        Text(t("v2.analysis.quietDays", "{count} jours sans dépense",
                               ["count": quiet]))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Florin.text2)
                            .padding(.horizontal, Florin.gutter)
                    }
                }
            }
        }
        .sheet(isPresented: $filtering) {
            CalendarFilterSheet(
                categories: data.spendCategories ?? [],
                totals: categoryTotals(data),
                locale: locale,
                currency: currency,
                t: t,
                hidden: $hidden
            )
        }
    }

    /// The title of the grid, and the one control that changes what it counts.
    ///
    /// Beside the thing it filters rather than up in the top bar: the filter
    /// belongs to this one view of the ledger and not to the four others on the
    /// same screen, and a control that only works on one tab has no business
    /// sitting in the chrome that spans all five. It also says what it is set
    /// to, so a total that looks wrong explains itself where it is read.
    private func calendarHeader(_ data: AnalysisData) -> some View {
        HStack(spacing: 10) {
            Eyebrow(text: t("v2.analysis.calendarCaption", "Dépenses par jour"))
            Spacer(minLength: 4)
            if model.canFilterDays {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    filtering = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 11, weight: .semibold))
                        Text(
                            CalendarFilterLabel.short(
                                hidden: hidden, categories: data.spendCategories ?? [], t: t
                            )
                        )
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    }
                    .foregroundStyle(hidden.isEmpty ? Florin.text2 : Florin.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        hidden.isEmpty ? Florin.text.opacity(0.06) : Florin.accent.opacity(0.16),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t("v2.calendar.filterTitle", "Ce que compte le calendrier"))
            }
        }
        .padding(.horizontal, Florin.gutter)
    }

    /// Which month is on screen, what it cost, and the two ways to leave it.
    ///
    /// The arrows are there for the reader who never discovers the swipe, and
    /// because the last month of the ledger has no square to swipe onto.
    private func monthBar(_ months: [String], month: String, total: Double) -> some View {
        let index = months.firstIndex(of: month) ?? months.count - 1
        return HStack(spacing: 6) {
            monthStep("chevron.left", to: index > 0 ? months[index - 1] : nil)
            Text(MonthLabel.long(month, locale: locale))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Florin.text)
                .contentTransition(.numericText())
            monthStep("chevron.right", to: index < months.count - 1 ? months[index + 1] : nil)
            Spacer(minLength: 6)
            Text(Money.string(total, locale: locale, currency: currency, decimals: false))
                .font(.system(size: 14, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Florin.text2)
                .hiddenWhenPrivate()
        }
    }

    private func monthStep(_ symbol: String, to month: String?) -> some View {
        Button {
            guard let month else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy(duration: 0.22)) { calendarMonth = month }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(month == nil ? Florin.text3.opacity(0.4) : Florin.text2)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(month == nil)
    }

    /// One grid per month, swiped between.
    ///
    /// A page view has to be told its height — its pages are laid out on top of
    /// each other — so every month draws six rows whether it needs six or five.
    /// A grid that changed height with the month would shunt the legend and
    /// everything under it up and down on every swipe.
    private func monthPages(_ byDay: [String: Double], months: [String], cuts: [Double]) -> some View {
        let width = gridWidth > 0 ? gridWidth : Self.estimatedGridWidth()
        let side = Self.cellSide(width)
        return TabView(selection: monthSelection(months)) {
            ForEach(months, id: \.self) { key in
                grid(monthCells(byDay, month: key), cuts: cuts)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .tag(key)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: side * CGFloat(Self.gridRows) + Self.cellGap * CGFloat(Self.gridRows - 1))
    }

    private var weekdayRow: some View {
        HStack(spacing: Self.cellGap) {
            ForEach(Self.weekdayInitials(locale), id: \.self) { initial in
                Text(initial)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Florin.text3)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// The squares, plus the card that reads one out under the finger.
    private func grid(_ cells: [DayCell?], cuts: [Double]) -> some View {
        VStack(spacing: Self.cellGap) {
            ForEach(0..<Self.gridRows, id: \.self) { week in
                HStack(spacing: Self.cellGap) {
                    ForEach(0..<7, id: \.self) { column in
                        let index = week * 7 + column
                        if let cell = cells[index] {
                            dayCell(
                                cell,
                                level: heatLevel(cell.amount, cuts: cuts),
                                reading: scrub == index
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { open(cell) }
                        } else {
                            // The days of the month before and the month after,
                            // which belong to their own grids.
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.width, initial: true) { _, width in
                        gridWidth = width
                    }
            }
        }
        .overlay(alignment: .topLeading) { readout(cells) }
        .gesture(scrubGesture(cells))
    }

    /*
     * Hold, then drag, to read a day out.
     *
     * The web shows this on hover; a phone has no hover, and a plain drag is
     * not free here — the grid sits inside the screen's scroll view and inside
     * a page view, and a `DragGesture(minimumDistance: 0)` on it wins over
     * both, so neither the page could be scrolled nor the month swiped by a
     * thumb that happened to land on the calendar. Sequencing it behind a short
     * press leaves a flick to the scroll view, a sideways swipe to the months,
     * a tap to the day sheet, and the hold to the reading — which is also how
     * iOS scrubs a chart anywhere else.
     */
    private func scrubGesture(_ cells: [DayCell?]) -> some Gesture {
        LongPressGesture(minimumDuration: 0.18)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { phase in
                guard case .second(true, let drag) = phase, let drag else { return }
                guard let index = cellIndex(at: drag.location), index < cells.count,
                      cells[index] != nil
                else { return }
                if scrub != index {
                    UISelectionFeedbackGenerator().selectionChanged()
                    scrub = index
                }
            }
            .onEnded { _ in scrub = nil }
    }

    /// Which square is under a point in the grid.
    ///
    /// Clamped rather than nil at the edges: a thumb that slides a few points
    /// past the last column is still reading Sunday, and letting the card
    /// vanish there would make the gesture feel broken at exactly the moment it
    /// is being learned.
    private func cellIndex(at point: CGPoint) -> Int? {
        let side = Self.cellSide(gridWidth)
        guard side > 0 else { return nil }
        let pitch = side + Self.cellGap
        let column = min(6, max(0, Int((point.x / pitch).rounded(.down))))
        let row = min(Self.gridRows - 1, max(0, Int((point.y / pitch).rounded(.down))))
        return row * 7 + column
    }

    private func open(_ cell: DayCell) {
        guard model.canOpenDays, !cell.future else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        openDay = OpenDay(date: cell.date)
    }

    // MARK: - The card over the square

    private static let calloutDateSize: CGFloat = 11.5
    private static let calloutAmountSize: CGFloat = 15
    private static let calloutHeight: CGFloat = 46

    @ViewBuilder
    private func readout(_ cells: [DayCell?]) -> some View {
        if let index = scrub, index < cells.count, gridWidth > 0, let cell = cells[index] {
            let day = DayLabel.string(cell.date, locale: locale, t: t)
            let amount = Money.string(cell.amount, locale: locale, currency: currency, decimals: true)
            let width = Self.calloutWidth(day: day, amount: amount)
            let side = Self.cellSide(gridWidth)
            let pitch = side + Self.cellGap
            let row = CGFloat(index / 7)
            let centre = CGFloat(index % 7) * pitch + side / 2

            callout(day: day, amount: amount, spent: cell.amount > 0)
                .frame(width: width, height: Self.calloutHeight)
                .offset(
                    // Kept inside the card on both sides, and flipped under the
                    // square for the top row, where there is nothing above it.
                    x: min(max(centre - width / 2, 0), max(0, gridWidth - width)),
                    y: row > 0
                        ? row * pitch - Self.calloutHeight - 5
                        : pitch + 5
                )
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    private func callout(day: String, amount: String, spent: Bool) -> some View {
        VStack(spacing: 1) {
            Text(day)
                .font(.system(size: Self.calloutDateSize, weight: .medium))
                .foregroundStyle(Florin.text2)
            Text(spent ? amount : t("v2.analysis.noSpend", "Rien"))
                .font(.system(size: Self.calloutAmountSize, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Florin.text)
                .hiddenWhenPrivate()
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Florin.surface3, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Florin.text.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }

    /*
     * Measured from the font rather than read back from the layout.
     *
     * The card has to be centred over a square *before* it is drawn. A width
     * measured by a `GeometryReader` arrives on the next pass, which on a
     * gesture that changes the text every few points shows up as a card
     * sliding a frame behind the finger. The two strings and their two fonts
     * are known here, so the width is too.
     */
    private static func calloutWidth(day: String, amount: String) -> CGFloat {
        let top = textWidth(day, size: calloutDateSize, weight: .medium)
        let bottom = textWidth(amount, size: calloutAmountSize, weight: .semibold)
        return min(200, max(top, bottom).rounded(.up) + 24)
    }

    private static func textWidth(_ text: String, size: CGFloat, weight: UIFont.Weight) -> CGFloat {
        (text as NSString)
            .size(withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight)])
            .width
    }

    // MARK: - What the grid is made of

    /// A square: the day it stands for, and what was spent on it under the
    /// filter in force.
    private struct DayCell {
        let date: Date
        let key: String
        let amount: Double
        let future: Bool
    }

    /// Six rows, always: five weeks fit most months, six are needed when the
    /// 1st falls late in the week, and a grid whose height depends on the month
    /// would shift the page under the reader on every swipe.
    private static let gridRows = 6
    private static let cellGap: CGFloat = 6

    private static func cellSide(_ width: CGFloat) -> CGFloat {
        max(0, (width - cellGap * 6) / 7)
    }

    /// Only for the first frame, before the grid has been measured: the card's
    /// content width, from the screen and the insets it sits in.
    private static func estimatedGridWidth() -> CGFloat {
        max(0, UIScreen.main.bounds.width - Florin.gutter * 2 - 32)
    }

    /// Every month from the oldest day the feed carries to this one.
    ///
    /// Continuous rather than the months that happen to hold a transaction: a
    /// month with nothing in it is an answer, and skipping it would make the
    /// swipe jump a year without saying so.
    private func calendarMonths(_ byDay: [String: Double]) -> [String] {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.startOfDay(for: Date())
        let thisMonth = LocalQueries.monthFormatter.string(from: now)
        guard let oldest = byDay.keys.min()?.prefix(7), oldest < thisMonth else { return [thisMonth] }

        var months: [String] = []
        var cursor = String(oldest)
        while cursor < thisMonth, months.count < 12 * LocalAnalysis.calendarYears {
            months.append(cursor)
            cursor = MonthLabel.next(cursor)
        }
        months.append(thisMonth)
        return months
    }

    /// The page view's selection, which cannot be left holding a month the
    /// feed does not have — it would quietly show the oldest one instead.
    private func monthSelection(_ months: [String]) -> Binding<String> {
        Binding(get: { shownMonth(months) }, set: { calendarMonth = $0 })
    }

    /// The month on screen, corrected when the feed no longer holds it — a
    /// filter that hides everything, or a reload that arrives while the reader
    /// is three years back.
    private func shownMonth(_ months: [String]) -> String {
        months.contains(calendarMonth) ? calendarMonth : (months.last ?? "")
    }

    /// One month, laid out Monday-first, with the slots before the 1st and
    /// after the last left empty.
    private func monthCells(_ byDay: [String: Double], month: String) -> [DayCell?] {
        let calendar = Calendar(identifier: .gregorian)
        let parts = month.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2,
              let first = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: 1)),
              let length = calendar.range(of: .day, in: .month, for: first)?.count
        else { return Array(repeating: nil, count: Self.gridRows * 7) }

        let today = calendar.startOfDay(for: Date())
        // `weekday` is 1 on Sunday; the grid starts on Monday.
        let lead = (calendar.component(.weekday, from: first) + 5) % 7
        return (0..<(Self.gridRows * 7)).map { slot in
            let day = slot - lead
            guard day >= 0, day < length,
                  let date = calendar.date(byAdding: .day, value: day, to: first)
            else { return nil }
            let key = LocalQueries.dayFormatter.string(from: date)
            return DayCell(date: date, key: key, amount: byDay[key] ?? 0, future: date > today)
        }
    }

    /// What each day was worth: the feed's own totals, or the slices behind
    /// them re-added without the categories the reader has taken out.
    private func filteredDays(_ data: AnalysisData) -> [String: Double] {
        guard !hidden.isEmpty, let slices = data.dailySlices else {
            return Dictionary(data.dailySpend.map { ($0.date, $0.amount) }) { $1 }
        }
        var byDay: [String: Double] = [:]
        for slice in slices where !hidden.contains(slice.categoryId) {
            byDay[slice.date, default: 0] += slice.amount
        }
        return byDay
    }

    /// What each category was worth over the window — the figures the filter
    /// sheet orders and prices itself by.
    private func categoryTotals(_ data: AnalysisData) -> [String: Double] {
        var totals: [String: Double] = [:]
        for slice in data.dailySlices ?? [] {
            totals[slice.categoryId, default: 0] += slice.amount
        }
        return totals
    }

    // MARK: - The scale

    /*
     * Five buckets by rank, not a ramp on the amount.
     *
     * A single 900 € rent day sets the top of any amount-based scale, and the
     * fortnight of 10–40 € days underneath it then differ by two percent of
     * that — every one of them the same faint wash, which is the version of
     * this grid that says nothing. Ranking the days instead spends the five
     * shades on the middle of the distribution, where the differences a reader
     * can act on actually are. The web has drawn it this way for a year.
     *
     * The shades mix towards the accent rather than the tab's own teal: the
     * ground behind this screen *is* that teal, and a teal square on a teal
     * page is a square you have to look for.
     */
    private static let heatLevels = 5

    private func heatCuts(_ amounts: [Double]) -> [Double] {
        let spent = amounts.filter { $0 > 0 }.sorted()
        guard !spent.isEmpty else { return [] }
        return (1..<Self.heatLevels).map {
            spent[min(spent.count - 1, spent.count * $0 / Self.heatLevels)]
        }
    }

    private func heatLevel(_ amount: Double, cuts: [Double]) -> Int {
        guard amount > 0 else { return 0 }
        return min(Self.heatLevels, 1 + cuts.filter { amount > $0 }.count)
    }

    private static func heatShade(_ level: Int) -> Color {
        guard level > 0 else { return Florin.surface2 }
        return Florin.mix(Florin.surface2, Florin.accent, [0, 0.20, 0.39, 0.58, 0.78, 1.0][level])
    }

    private func dayCell(_ cell: DayCell, level: Int, reading: Bool) -> some View {
        let calendar = Calendar(identifier: .gregorian)
        let isToday = calendar.isDateInToday(cell.date)
        let fill = cell.future ? Florin.surface2.opacity(0.35) : Self.heatShade(level)
        let ring = reading ? Florin.text : (isToday ? Florin.text.opacity(0.55) : .clear)
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(fill)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(ring, lineWidth: reading ? 2 : 1.5)
            )
            .overlay(dayNumber(cell, level: level))
            .scaleEffect(reading ? 1.06 : 1)
            .animation(.snappy(duration: 0.14), value: reading)
            .accessibilityLabel(
                Self.cellLabel(cell.date, cell.amount, locale: locale, currency: currency, t: t)
            )
    }

    private static func cellLabel(
        _ date: Date, _ amount: Double, locale: String, currency: String, t: Strings
    ) -> String {
        let day = DayLabel.string(date, locale: locale, t: t)
        let money = Money.string(amount, locale: locale, currency: currency, decimals: false)
        return day + ", " + money
    }

    private func dayNumber(_ cell: DayCell, level: Int) -> some View {
        let day = Calendar(identifier: .gregorian).component(.day, from: cell.date)
        // White once the square is dark enough to swallow grey, as on the web.
        let tone: Color = level >= 4 ? Color.white.opacity(0.92) : Florin.text3
        return Text(String(day))
            .font(.system(size: 10.5, weight: level >= 4 ? .medium : .regular))
            .monospacedDigit()
            .foregroundStyle(tone)
            .opacity(cell.future ? 0.3 : 1)
    }

    /// Five shades and what they mean, which is all a ranked scale can honestly
    /// say — the old legend printed the window's largest day at the end of a
    /// square-root ramp, so every swatch between the two ends was a number it
    /// did not stand for.
    private var legend: some View {
        HStack(spacing: 5) {
            Text(t("v2.common.less", "Moins"))
                .font(.system(size: 10)).foregroundStyle(Florin.text3)
            ForEach(0...Self.heatLevels, id: \.self) { level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Self.heatShade(level))
                    .frame(width: 13, height: 9)
            }
            Text(t("v2.common.more", "Plus"))
                .font(.system(size: 10)).foregroundStyle(Florin.text3)
            Spacer(minLength: 6)
            if model.canOpenDays {
                Text(t("v2.calendar.scrubHint", "maintiens pour lire"))
                    .font(.system(size: 10))
                    .foregroundStyle(Florin.text3)
                    .lineLimit(1)
            }
        }
    }

    /// Monday-first initials in the reader's own language.
    private static func weekdayInitials(_ locale: String) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale)
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        // `veryShortStandaloneWeekdaySymbols` starts on Sunday; the grid starts
        // on Monday, and repeated initials are why each carries its index.
        return (1...7).map { symbols[$0 % 7] }
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
                                "Florin cherche un même bénéficiaire, au même montant, au moins trois fois, à un rythme régulier — toutes les 4 semaines environ ou toutes les semaines — sur les 6 derniers mois. Les achats ponctuels, et les montants qui changent à chaque fois, n'en font pas partie."
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
    /// Le mois sous le doigt, tel que Swift Charts le rapporte.
    @State private var touched: String?

    /// Pleine encre pour le mois sous le doigt, atténuée pour les autres, et
    /// plus pâle encore pour le mois en cours — qui n'est pas fini.
    private func ink(_ flow: MonthlyFlow, _ full: Double) -> Double {
        let picked = selection == nil || selection?.id == flow.id ? 1.0 : 0.32
        return full * picked * (flow.isRunning ? 0.5 : 1)
    }

    var body: some View {
        Chart {
            ForEach(flows) { flow in
                BarMark(
                    x: .value("Mois", flow.month),
                    y: .value("Montant", flow.income)
                )
                .position(by: .value("Sens", "in"))
                .foregroundStyle(Florin.positive.opacity(ink(flow, 0.95)))
                .cornerRadius(3)

                BarMark(
                    x: .value("Mois", flow.month),
                    y: .value("Montant", flow.expense)
                )
                .position(by: .value("Sens", "out"))
                .foregroundStyle(Florin.negative.opacity(ink(flow, 0.9)))
                .cornerRadius(3)

                /*
                 * The net line stops at the last month that is over.
                 *
                 * A month is only half-paid until the salary lands, so the
                 * running month's net is a trough that has nothing to do with
                 * how the money went: it plunged off the bottom of the chart
                 * on the 18th, took the y-axis down to −2 k with it, and
                 * flattened the twelve real months into a ribbon. Its bars
                 * stay — spending to date is worth seeing — and the pale ink
                 * plus the note under the card say why they are shorter.
                 */
                if !flow.isRunning {
                    LineMark(
                        x: .value("Mois", flow.month),
                        y: .value("Net", flow.net),
                        series: .value("Série", "net")
                    )
                    .foregroundStyle(Florin.accent)
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .interpolationMethod(.monotone)
                }
            }

            if let selection {
                RuleMark(x: .value("Mois", selection.month))
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
                    if let key = value.as(String.self) {
                        /*
                         * The axis is keyed on "2026-09" and printed as
                         * "sept.", because thirteen months span two years and
                         * two Septembers printed the same collapsed into one
                         * column: the oldest month was drawn on top of the
                         * newest, and scrubbing either one selected the wrong
                         * one. The year is written under the first column and
                         * under each January, where it changes.
                         */
                        VStack(spacing: 0) {
                            Text(MonthLabel.short(key, locale: locale))
                            if key == flows.first?.month || key.hasSuffix("-01") {
                                Text(key.prefix(4))
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(Florin.text3.opacity(0.7))
                            }
                        }
                        .font(.system(size: 9))
                        .foregroundStyle(Florin.text3)
                    }
                }
            }
        }
        // Même correction que la courbe de l'Aperçu : un `DragGesture` sur un
        // graphique posé dans une liste confisque le doigt et prive l'écran de
        // son tirer-pour-rafraîchir. `chartXSelection` laisse le système
        // arbitrer — appui maintenu pour scruter, balayage pour défiler.
        .chartXSelection(value: $touched)
        .onChange(of: touched) { _, key in
            guard let key else { selection = nil; return }
            let hit = flows.first { $0.month == key }
            if hit?.id != selection?.id {
                selection = hit
                UISelectionFeedbackGenerator().selectionChanged()
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

/// A tapped square, given identity so `sheet(item:)` will carry it. The date
/// alone cannot: two equal dates are the same value, and SwiftUI needs to tell
/// one presentation from the next.
private struct OpenDay: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSince1970 }
}
