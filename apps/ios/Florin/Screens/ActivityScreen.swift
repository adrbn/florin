import SwiftUI

/// Activité, natively — and the review queue with it.
///
/// There is no separate "à vérifier" screen because there is no separate list:
/// the queue is this list with one filter on, exactly as the web surface models
/// it. One screen means one set of gestures, one detail sheet and one place for
/// a bug to live.
struct ActivityScreen: View {
    @ObservedObject var overview: OverviewModel
    var route: (TabRoute, String) -> Void = { _, _ in }
    var onOpenSettings: () -> Void = {}
    /// Set by a link from elsewhere in the app ("À vérifier" on the dashboard).
    var startNeedsReview = false

    var body: some View {
        TransactionList(
            base: overview.base,
            tint: TabRoute.activity.tint,
            title: (overview.overview?.t ?? .empty)("v2.nav.activity", "Activité"),
            locale: overview.overview?.localeTag ?? "fr-FR",
            currency: overview.overview?.currency ?? "EUR",
            t: overview.overview?.t ?? .empty,
            startNeedsReview: startNeedsReview,
            onProfile: onOpenSettings
        )
    }
}

/// The list itself, reused by Activité and by an account's ledger.
struct TransactionList<Banner: View>: View {
    let base: URL
    let tint: Color
    let title: String
    let locale: String
    let currency: String
    let t: Strings
    var preset: ActivityRoute?
    var heroValue: Double?
    var heroCaption: String?
    var startNeedsReview = false
    var showsBack = false
    var onProfile: () -> Void = {}
    /// Optional block between the hero and the filters — a portfolio summary on
    /// a broker account, nothing at all everywhere else.
    @ViewBuilder var banner: Banner

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ActivityModel
    @State private var draft = ""
    @State private var detail: Transaction?
    @State private var filtering = false
    /// Non-nil while picking rows to approve in one go.
    @State private var selection: Set<String>?
    @FocusState private var searchFocused: Bool

    init(
        base: URL,
        tint: Color,
        title: String,
        locale: String,
        currency: String,
        t: Strings,
        preset: ActivityRoute? = nil,
        heroValue: Double? = nil,
        heroCaption: String? = nil,
        startNeedsReview: Bool = false,
        showsBack: Bool = false,
        onProfile: @escaping () -> Void = {},
        @ViewBuilder banner: () -> Banner = { EmptyView() }
    ) {
        self.base = base
        self.tint = tint
        self.title = title
        self.locale = locale
        self.currency = currency
        self.t = t
        self.preset = preset
        self.heroValue = heroValue
        self.heroCaption = heroCaption
        self.startNeedsReview = startNeedsReview
        self.showsBack = showsBack
        self.onProfile = onProfile
        self.banner = banner()
        _model = StateObject(wrappedValue: ActivityModel(base: base))
    }

    private enum Scope: Hashable { case all, expense, income, review }

    private var scope: Binding<Scope> {
        Binding(
            get: {
                if model.filter.needsReview { return .review }
                switch model.filter.direction {
                case .expense: return .expense
                case .income: return .income
                case .all: return .all
                }
            },
            set: { next in
                var filter = model.filter
                filter.needsReview = next == .review
                filter.direction = next == .expense ? .expense : (next == .income ? .income : .all)
                model.filter = filter
                Task { await model.reload() }
            }
        )
    }

    var body: some View {
        TabScaffold(tint: tint, refresh: { await model.reload() }) {
            header
            if let heroValue {
                HeroBlock(
                    caption: heroCaption ?? title,
                    value: heroValue,
                    locale: locale,
                    currency: currency,
                    size: 48
                )
                .padding(.bottom, 2)
            }
            // `Banner` is `EmptyView` on every screen but a broker account, and
            // an empty card is a stray rectangle.
            if Banner.self != EmptyView.self {
                FlorinCard { banner }
                    .padding(.horizontal, Florin.gutter)
            }
            ChipBar(options: chips, selection: scope)
            summary
            list
        }
        /*
         * A floating pill, clear of the tab bar.
         *
         * A full-width bar pinned to the bottom is the obvious shape, and it
         * cannot work here: the shell draws its tab bar above every tab's
         * content, so the bar rendered *behind* it and its material ghosted
         * through the glass. Sitting the controls above that zone sidesteps
         * z-order entirely — and it still has to say how many, because
         * "Valider 7" is a different decision from "Valider 1".
         */
        .overlay(alignment: .bottom) {
            if let picked = selection {
                HStack(spacing: 10) {
                    Button {
                        selection = picked.count == pending.count ? [] : Set(pending.map(\.id))
                    } label: {
                        Text(
                            picked.count == pending.count
                                ? t("v2.review.selectNone", "Aucune")
                                : t("v2.review.selectAll", "Tout")
                        )
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Florin.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .florinGlass(in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        let ids = Array(picked)
                        withAnimation(.snappy(duration: 0.2)) { selection = nil }
                        Task { await model.approve(ids, t: t) }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                            Text(
                                t("v2.review.approveCount", "Valider {count}",
                                  ["count": picked.count])
                            )
                            .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Florin.positive, in: Capsule())
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 5)
                    }
                    .buttonStyle(.plain)
                    .disabled(picked.isEmpty)
                    .opacity(picked.isEmpty ? 0.4 : 1)
                }
                .padding(.bottom, 104)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
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
        }
        .task {
            if startNeedsReview { model.filter.needsReview = true }
            if let preset {
                model.filter.accountId = preset.accountId
                model.filter.categoryId = preset.categoryId
            }
            if model.rows.isEmpty { await model.reload() }
        }
        .sheet(item: $detail) { tx in
            TransactionDetailSheet(
                tx: tx,
                categories: model.categories,
                locale: locale,
                currency: currency,
                t: t,
                onPatch: { patch in await model.apply(patch, to: tx.id, t: t) },
                onDelete: { await model.delete(tx.id, t: t) }
            )
        }
        .florinToast($model.toast)
    }

    // MARK: - Pieces

    private var chips: [(value: Scope, label: String, badge: Int)] {
        [
            (.all, t("v2.activity.all", "Tout"), 0),
            (.expense, t("v2.activity.expenses", "Dépenses"), 0),
            (.income, t("v2.activity.income", "Entrées"), 0),
            (.review, t("v2.review.title", "À vérifier"), model.reviewCount),
        ]
    }

    private var header: some View {
        TopBar(onProfile: { showsBack ? dismiss() : onProfile() }, back: showsBack) {
            searchField
        } trailing: {
            /*
             * The corner is the filters, and stays the filters.
             *
             * It briefly held the "select rows" affordance instead, which made
             * the one control on the screen change meaning depending on whether
             * the queue happened to be empty — the filter button has to be
             * where it always is. Selecting is entered from the queue's own
             * header, next to the thing it acts on. While picking, the corner
             * is the way out.
             */
            if selection != nil {
                CircleButton(symbol: "xmark", size: 44) {
                    withAnimation(.snappy(duration: 0.2)) { selection = nil }
                }
            } else {
                filterButton
            }
        }
        .padding(.bottom, heroValue == nil ? 14 : 24)
    }

    private var filterButton: some View {
        ZStack(alignment: .topTrailing) {
            CircleButton(symbol: "line.3.horizontal.decrease", size: 44) { filtering = true }
            if model.filter.activeCount > 0 {
                Text("\(model.filter.activeCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Florin.accent, in: Capsule())
                    .offset(x: 3, y: -2)
            }
        }
        .accessibilityLabel(t("v2.filters.title", "Filtres"))
    }

    /// A real text field, not a button that opens one.
    ///
    /// The web surface put search behind a sheet, which on a phone means two
    /// taps and a layer of chrome before you can type a merchant's name — the
    /// single most common thing anyone does on a ledger.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Florin.text3)
            TextField(t("v2.common.search", "Rechercher"), text: $draft)
                .font(.system(size: 15))
                .foregroundStyle(Florin.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit { commitSearch(draft) }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .florinGlass(in: Capsule())
        // Debounced: firing a query per keystroke over a LAN server means the
        // list flickers through four intermediate result sets on the way to
        // "carrefour".
        .onChange(of: draft) { _, value in
            Task {
                try? await Task.sleep(for: .milliseconds(320))
                guard value == draft, value != model.filter.search else { return }
                commitSearch(value)
            }
        }
    }

    private func commitSearch(_ value: String) {
        model.filter.search = value
        Task { await model.reload() }
    }

    private var summary: some View {
        HStack {
            Text(t("v2.activity.count", "{count} opérations", ["count": model.total]))
            Spacer()
            if model.loading { ProgressView().controlSize(.mini) }
        }
        .font(.system(size: 12))
        .foregroundStyle(Florin.text3)
        .padding(.horizontal, Florin.gutter)
    }

    @ViewBuilder
    private var list: some View {
        if let failure = model.failure, model.rows.isEmpty {
            emptyState(symbol: "wifi.exclamationmark", text: failure)
        } else if model.rows.isEmpty && !model.loading {
            emptyState(symbol: "tray", text: t("v2.activity.empty", "Aucune opération"))
        } else {
            VStack(alignment: .leading, spacing: 22) {
                /*
                 * The queue floats to the top of its own section.
                 *
                 * Interleaved by date, four rows needing a decision sat between
                 * twenty that did not, and the only thing distinguishing them
                 * was a caption. Anything asking for an action belongs in one
                 * place at the top — the rows are excluded from the day groups
                 * below so nothing is listed twice.
                 */
                if !pending.isEmpty, !model.filter.needsReview {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Eyebrow(text: t("v2.review.title", "À vérifier"))
                            Text("\(pending.count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Florin.warn, in: Capsule())
                            Spacer()
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                withAnimation(.snappy(duration: 0.2)) { selection = [] }
                            } label: {
                                Text(t("v2.review.selectMany", "Sélectionner"))
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(Florin.accent)
                            }
                            .buttonStyle(.plain)

                            Text("·")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Florin.text3)

                            Button {
                                scope.wrappedValue = .review
                            } label: {
                                Text(t("v2.common.seeAll", "Tout voir"))
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(Florin.accent)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, Florin.gutter)

                        RowGroup {
                            ForEach(Array(pending.enumerated()), id: \.element.id) { index, tx in
                                if index > 0 { Hairline() }
                                row(tx)
                            }
                        }
                        .padding(.horizontal, Florin.gutter)
                    }
                }

                ForEach(days, id: \.key) { day in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Eyebrow(text: DayLabel.string(day.date, locale: locale, t: t))
                            Spacer()
                            AmountText(
                                value: day.total, locale: locale, currency: currency,
                                decimals: false, signed: true, tone: .muted, size: 11.5,
                                weight: .semibold
                            )
                        }
                        .padding(.horizontal, Florin.gutter)

                        RowGroup {
                            ForEach(Array(day.rows.enumerated()), id: \.element.id) { index, tx in
                                if index > 0 { Hairline() }
                                row(tx)
                            }
                        }
                        .padding(.horizontal, Florin.gutter)
                    }
                }

                if model.hasMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .task { await model.loadMore() }
                }
            }
        }
    }

    private func row(_ tx: Transaction) -> some View {
        let picking = selection != nil && tx.needsReview
        let picked = selection?.contains(tx.id) == true

        return Button {
            guard picking else { return detail = tx }
            UISelectionFeedbackGenerator().selectionChanged()
            if picked { selection?.remove(tx.id) } else { selection?.insert(tx.id) }
        } label: {
            TransactionRowView(tx: tx, locale: locale, currency: currency, t: t)
                /*
                 * A wash, and nothing else.
                 *
                 * The rows needing a decision now sit in their own pinned
                 * section with a counted header, so the row itself no longer
                 * has to shout — the amber chip beside the amount is enough to
                 * carry the state once the grouping has done the sorting. An
                 * edge bar on top of that was a third signal for one fact.
                 */
                .background(tx.needsReview ? Florin.warn.opacity(0.08) : Color.clear)
                .overlay(alignment: .leading) {
                    // Only rows that can be approved get a box; the others stay
                    // exactly as they were so the list does not reflow.
                    if picking {
                        Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(picked ? Florin.positive : Florin.text3)
                            .padding(.leading, 14)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.leading, picking ? 34 : 0)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: picking)
    }

    private func emptyState(symbol: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(Florin.text3)
            Text(text).font(.system(size: 14)).foregroundStyle(Florin.text2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private struct Day {
        let key: String
        let date: Date
        let rows: [Transaction]
        var total: Double { rows.reduce(0) { $0 + $1.amount } }
    }

    /// Grouped on the *local* day, not the ISO string's date part: a
    /// transaction booked at 23:30 UTC belongs to tomorrow in Paris, and
    /// grouping on the prefix produced two separate "Hier" headings.
    /// Rows awaiting a decision, newest first. Capped: the pinned section is a
    /// prompt, not the whole queue — "Tout voir" opens the filter for the rest.
    private var pending: [Transaction] {
        Array(model.rows.filter(\.needsReview).prefix(6))
    }

    private var days: [Day] {
        var order: [String] = []
        var buckets: [String: [Transaction]] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let pinned = Set(pending.map(\.id))
        for tx in model.rows where !(pinned.contains(tx.id) && !model.filter.needsReview) {
            let key = formatter.string(from: tx.day)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(tx)
        }
        return order.compactMap { key in
            guard let rows = buckets[key], let first = rows.first else { return nil }
            return Day(key: key, date: first.day, rows: rows)
        }
    }
}
