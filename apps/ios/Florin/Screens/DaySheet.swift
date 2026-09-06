import SwiftUI

/// One day, opened from its square in the calendar.
///
/// The grid could show that a Tuesday was dark and not what made it dark, which
/// is the one thing anyone looks at a heavy day to find out. The headline
/// repeats the square's own figure, the bars under it say which categories
/// carried it, and the list says which payees — three answers to the same
/// question at three depths, so the reader stops at whichever one satisfies
/// them.
struct DaySheet: View {
    let date: Date
    let locale: String
    let currency: String
    let t: Strings
    let load: (String) -> DayDetail?

    @Environment(\.dismiss) private var dismiss
    @State private var detail: DayDetail?
    @State private var loaded = false

    private var key: String { LocalQueries.dayFormatter.string(from: date) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    headline
                    if let detail, !detail.categories.isEmpty {
                        breakdown(detail)
                    }
                    if let detail, !detail.transactions.isEmpty {
                        movements(detail)
                    }
                    if loaded, detail?.isEmpty ?? true {
                        empty
                    }
                }
                .padding(.vertical, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Backdrop(tint: TabRoute.analysis.tint))
            .navigationTitle(DayLabel.string(date, locale: locale, t: t))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .accessibilityLabel(t("v2.common.close", "Fermer"))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
        .task {
            // The sheet is presented before the rows are read, so the title and
            // the backdrop are there immediately and only the figures arrive
            // late — a day with three hundred rows should not delay the sheet.
            detail = load(key)
            loaded = true
        }
    }

    // MARK: - What the square said

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: t("v2.day.spent", "Dépensé"))
            AmountText(
                value: -(detail?.spent ?? 0), locale: locale, currency: currency,
                decimals: true, tone: detail?.spent ?? 0 > 0 ? .negative : .muted,
                size: 34, weight: .light
            )
        }
        .padding(.horizontal, Florin.gutter)
    }

    // MARK: - Which categories carried it

    private func breakdown(_ detail: DayDetail) -> some View {
        let peak = detail.categories.map(\.amount).max() ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: t("v2.day.byCategory", "Par catégorie"))
                .padding(.horizontal, Florin.gutter)
            FlorinCard {
                VStack(spacing: 12) {
                    ForEach(Array(detail.categories.enumerated()), id: \.element.id) { index, slice in
                        if index > 0 { Hairline() }
                        categoryRow(slice, peak: peak)
                    }
                }
            }
            .padding(.horizontal, Florin.gutter)
        }
    }

    private func categoryRow(_ slice: DayDetail.CategorySlice, peak: Double) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 12) {
                Bubble(label: slice.name, emoji: slice.emoji)
                Text(slice.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Florin.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                AmountText(
                    value: slice.amount, locale: locale, currency: currency,
                    decimals: true, tone: .neutral
                )
            }
            /*
             * Against the day's own heaviest category, not against the day's
             * total. A day with one expense would otherwise draw a full-width
             * bar that says nothing, and a day with six would draw six stubs.
             */
            GeometryReader { proxy in
                let share = peak > 0 ? slice.amount / peak : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Florin.surface2)
                    Capsule()
                        .fill(TabRoute.analysis.tint.opacity(0.75))
                        .frame(width: max(3, proxy.size.width * share))
                }
            }
            .frame(height: 4)
        }
    }

    // MARK: - What actually happened

    private func movements(_ detail: DayDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: t("v2.day.movements", "Opérations"))
                .padding(.horizontal, Florin.gutter)
            FlorinCard {
                VStack(spacing: 12) {
                    ForEach(Array(detail.transactions.enumerated()), id: \.element.id) { index, tx in
                        if index > 0 { Hairline() }
                        TransactionRowView(
                            hideUpcomingChip: false, dateIsGiven: true, tx: tx,
                            locale: locale, currency: currency, t: t
                        )
                    }
                }
            }
            .padding(.horizontal, Florin.gutter)
            /*
             * Said once, under the list, rather than marking the rows that sit
             * outside the headline. Income and transfers are shown because the
             * question is what happened that day; the note explains why the
             * figures above do not add up to the rows below, which is the only
             * thing about it that could confuse.
             */
            if detail.transactions.contains(where: { $0.isTransfer || $0.amount > 0 }) {
                Text(t("v2.day.scopeNote",
                       "Le total ne compte que les dépenses : ni les entrées, ni les virements."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Florin.text2)
                    .padding(.horizontal, Florin.gutter)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 26))
                .foregroundStyle(Florin.text3)
            Text(t("v2.day.empty", "Rien ce jour-là."))
                .font(.system(size: 14))
                .foregroundStyle(Florin.text2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }
}
