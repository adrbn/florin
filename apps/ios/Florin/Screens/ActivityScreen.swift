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
            /*
             * Approving here has to reach Aperçu too.
             *
             * Each tab holds its own copy of the ledger, so rows cleared on
             * this screen went on showing their amber chip on the dashboard —
             * the same transaction, reviewed in one place and still pending in
             * another. The overview is refetched quietly, without the spinner,
             * so the tab is already correct by the time it is opened.
             */
            onLedgerChanged: { await overview.load(showSpinner: false) },
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
    /// Called after anything that changes a row's stored state, so screens
    /// holding their own copy of the ledger can refetch.
    var onLedgerChanged: () async -> Void = {}
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
    @State private var upcomingExpanded = false
    @FocusState private var searchFocused: Bool

    init(
        base: URL,
        tint: Color,
        title: String,
        locale: String,
        currency: String,
        t: Strings,
        onLedgerChanged: @escaping () async -> Void = {},
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
        self.onLedgerChanged = onLedgerChanged
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Florin.text)
                        .frame(width: 104, height: 54)
                        .florinGlass(in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        let ids = Array(picked)
                        withAnimation(.snappy(duration: 0.2)) { selection = nil }
                        Task {
                            await model.approve(ids, t: t)
                            await onLedgerChanged()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                            Text(
                                t("v2.review.approveCount", "Valider {count}",
                                  ["count": picked.count])
                            )
                            .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        // Takes the rest of the row: it is the action, and a
                        // thumb reaching the bottom of the screen should not
                        // have to aim.
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Florin.positive, in: Capsule())
                        .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
                    }
                    .buttonStyle(.plain)
                    .disabled(picked.isEmpty)
                    .opacity(picked.isEmpty ? 0.4 : 1)
                }
                .padding(.horizontal, Florin.gutter)
                // Right on top of the tab bar: the two together read as one
                // control zone, and it keeps the list visible above them.
                .padding(.bottom, 86)
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
                onPatch: { patch in
                    await model.apply(patch, to: tx.id, t: t)
                    await onLedgerChanged()
                },
                onDelete: {
                    await model.delete(tx.id, t: t)
                    await onLedgerChanged()
                }
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
                /*
                 * What has not happened yet, folded away above what has.
                 *
                 * These are dated in the future — a bank publishes a direct
                 * debit days before taking it — so by date they land at the
                 * very top of the list, ahead of everything real. They are
                 * already out of every total; this keeps them out of the way
                 * without hiding them.
                 */
                if !upcoming.isEmpty {
                    UpcomingGroup(
                        transactions: upcoming,
                        locale: locale,
                        currency: currency,
                        t: t,
                        expanded: $upcomingExpanded
                    ) { tx in
                        row(tx)
                    }
                    .padding(.horizontal, Florin.gutter)
                }

                if !pending.isEmpty, !model.filter.needsReview {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Eyebrow(text: t("v2.review.title", "À vérifier"))
                            // The ledger's count, not this page's — they differ
                            // until every page is loaded, and the smaller of
                            // the two is the misleading one.
                            Text("\(max(model.reviewCount, pending.count))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Florin.warn, in: Capsule())
                            Spacer()
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                // The same control has to be the way out, or it
                                // sits there repeating an instruction the user
                                // has already followed.
                                withAnimation(.snappy(duration: 0.2)) {
                                    selection = selection == nil ? [] : nil
                                }
                            } label: {
                                Text(
                                    selection == nil
                                        ? t("v2.review.selectMany", "Sélectionner")
                                        : t("v2.review.selectDone", "Désélectionner")
                                )
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

                        RowGroup(tint: Florin.warn.opacity(0.09)) {
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
                 * The row paints nothing.
                 *
                 * A tint on the row sat inside the card's clip as a second
                 * rounded shape with its own apparent radius, and the two never
                 * agreed. The queue's card carries the colour now — one shape,
                 * one radius, by construction. The amber chip beside the amount
                 * still marks a lone review row inside an untinted day group.
                 *
                 * Padding first, overlay second: the other way round the tick
                 * aligns to the content's own leading edge and lands on top of
                 * the category bubble instead of in the gutter just opened.
                 */
                .padding(.leading, picking ? 38 : 0)
                .overlay(alignment: .leading) {
                    if picking {
                        Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 21))
                            .foregroundStyle(picked ? Florin.positive : Florin.text3)
                            .padding(.leading, 16)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
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
    /// Every loaded row awaiting a decision, newest first.
    ///
    /// Deliberately uncapped. It was capped at six on the theory that the
    /// section is a prompt rather than the queue itself, and that was wrong on
    /// its own terms: the header said nine, the list showed six, and approving
    /// three left it still showing six. A queue you cannot see the end of is
    /// not a queue. What the page has not fetched yet is what "Tout voir" is
    /// for.
    private var pending: [Transaction] {
        model.rows.filter { $0.needsReview && !$0.isUpcoming }
    }

    /// Announced, not yet booked. Kept out of the queue and the day groups.
    private var upcoming: [Transaction] {
        model.rows.filter(\.isUpcoming)
    }

    private var days: [Day] {
        var order: [String] = []
        var buckets: [String: [Transaction]] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let pinned = Set(pending.map(\.id))
        // Upcoming rows have their own group above; listing them again here
        // would put tomorrow's direct debit twice on the same screen.
        let announced = Set(upcoming.map(\.id))
        for tx in model.rows
        where !(pinned.contains(tx.id) && !model.filter.needsReview)
            && !announced.contains(tx.id) {
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
