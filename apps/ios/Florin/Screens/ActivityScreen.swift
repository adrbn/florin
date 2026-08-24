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
    @State private var searching = false
    @State private var draft = ""
    @State private var detail: Transaction?
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
            CircleButton(
                symbol: draft.isEmpty ? "line.3.horizontal.decrease" : "xmark",
                size: 44
            ) {
                if draft.isEmpty {
                    searchFocused = true
                } else {
                    draft = ""
                    commitSearch("")
                }
            }
        }
        .padding(.bottom, heroValue == nil ? 14 : 24)
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
        Button { detail = tx } label: {
            TransactionRowView(tx: tx, locale: locale, currency: currency, t: t)
                .background(
                    tx.needsReview ? Florin.negative.opacity(0.06) : Color.clear
                )
        }
        .buttonStyle(.plain)
        // Native swipe actions rather than a hand-rolled drag: they come with
        // the system's rubber-banding, full-swipe and VoiceOver rotor, none of
        // which the web version could have.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await model.delete(tx.id, t: t) }
            } label: {
                Label(t("v2.common.delete", "Supprimer"), systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if tx.needsReview {
                Button {
                    Task { await model.apply(TxPatch(approve: true), to: tx.id, t: t) }
                } label: {
                    Label(t("v2.review.approve", "Vérifié"), systemImage: "checkmark")
                }
                .tint(Florin.positive)
            }
        }
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
    private var days: [Day] {
        var order: [String] = []
        var buckets: [String: [Transaction]] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        for tx in model.rows {
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
