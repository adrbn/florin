import SwiftUI

/// One transaction, in a real sheet.
///
/// This replaces the web popup that misbehaved inside the native shell: an HTML
/// bottom sheet has to re-implement detents, drag-to-dismiss, scroll locking and
/// keyboard avoidance, and each of those was a separate bug. A `presentationDetents`
/// sheet gets all four from the OS, and the native tab bar no longer has to be
/// told to move out of its way.
struct TransactionDetailSheet: View {
    let tx: Transaction
    let categories: [Category]
    let locale: String
    let currency: String
    let t: Strings
    let onPatch: (TxPatch) async -> Void
    let onDelete: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var working = false
    @State private var contentHeight: CGFloat = 0
    @State private var filing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    summary
                    actions
                }
                .padding(.top, 8)
                .padding(.bottom, 20)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: SheetContentHeight.self, value: proxy.size.height
                        )
                    }
                )
            }
            .onPreferenceChange(SheetContentHeight.self) { contentHeight = $0 }
            .scrollBounceBehavior(.basedOnSize)
            .background(Backdrop(tint: TabRoute.activity.tint))
            .navigationTitle(PayeeText.humanize(tx.payee))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // A glyph, not the word. "Fermer" in a toolbar draws a
                    // capsule wide enough to read as the sheet's main action,
                    // which is the one thing it is not.
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .accessibilityLabel(t("v2.common.close", "Fermer"))
                }
            }
        }
        /*
         * As tall as it needs to be.
         *
         * A medium detent is half the screen whatever the sheet contains, so a
         * transaction with four actions had its last one — the red delete —
         * cut through the middle, and one with two left a void underneath. The
         * height is the content's, plus the navigation bar and the home
         * indicator; `.large` stays available for a long memo.
         */
        .presentationDetents([.height(min(contentHeight + 64, 720)), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
        .sheet(isPresented: $picking) {
            CategoryPicker(
                categories: categories,
                selected: tx.categoryName,
                t: t
            ) { id in
                run { await onPatch(TxPatch(categoryId: .some(id))) }
            }
        }
        .sheet(isPresented: $filing) {
            ReviewCategorySheet(
                transactions: [tx],
                categories: categories,
                locale: locale,
                currency: currency,
                t: t,
                onAssign: { _, categoryId in
                    await onPatch(TxPatch(categoryId: .some(categoryId)))
                },
                onFinish: {
                    filing = false
                    run { await onPatch(TxPatch(approve: true)) }
                }
            )
        }
        .sheet(isPresented: $editing) {
            TransactionEditor(tx: tx, locale: locale, currency: currency, t: t) { patch in
                await onPatch(patch)
            }
        }
        .confirmationDialog(
            t("v2.activity.deleteConfirm", "Supprimer cette opération ?"),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button(t("v2.common.delete", "Supprimer"), role: .destructive) {
                Task {
                    await onDelete()
                    dismiss()
                }
            }
            Button(t("v2.common.cancel", "Annuler"), role: .cancel) {}
        }
    }

    private var summary: some View {
        VStack(spacing: 12) {
            AmountText(
                value: tx.amount, locale: locale, currency: currency,
                signed: true, tone: .auto, size: 40, weight: .light
            )

            Text(fullDate)
                .font(.system(size: 14))
                .foregroundStyle(Florin.text2)

            // Wrapping, not a single scrolling row: three chips at 15pt run off
            // a 393pt screen the moment a category name is longer than "Courses".
            FlowRow(spacing: 8) {
                Pill(text: tx.accountName)
                Pill(
                    text: ((tx.categoryEmoji.map { $0 + " " } ?? "")
                        + (tx.categoryName ?? t("v2.common.uncategorized", "Sans catégorie"))),
                    tone: tx.categoryName == nil ? Florin.text3 : Florin.accent
                )
                if tx.needsReview {
                    Pill(text: t("v2.activity.needsReview", "À vérifier"), tone: Florin.negative)
                }
                if tx.isTransfer {
                    Pill(text: t("v2.activity.transfer", "Virement interne"))
                }
            }
            .padding(.horizontal, Florin.gutter)

            if let memo = tx.memo, !memo.isEmpty {
                Text(memo)
                    .font(.system(size: 13))
                    .foregroundStyle(Florin.text2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Florin.gutter)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if tx.needsReview {
                SheetAction(
                    label: t("v2.review.approve", "Vérifié"),
                    symbol: "checkmark",
                    prominent: true
                ) {
                    // Nothing leaves the queue uncategorised without that being
                    // a decision. A transfer is the exception: it has no
                    // category by design.
                    if tx.categoryName == nil && !tx.isTransfer {
                        filing = true
                    } else {
                        run { await onPatch(TxPatch(approve: true)) }
                    }
                }
            }
            SheetAction(label: t("v2.review.categorize", "Catégoriser"), symbol: "tag") {
                picking = true
            }
            SheetAction(label: t("v2.common.edit", "Modifier"), symbol: "pencil") {
                editing = true
            }
            SheetAction(
                label: t("v2.common.delete", "Supprimer"),
                symbol: "trash",
                destructive: true
            ) {
                confirmingDelete = true
            }
        }
        .padding(.horizontal, Florin.gutter)
        .disabled(working)
        .opacity(working ? 0.5 : 1)
    }

    private var fullDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: locale)
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMMy")
        return f.string(from: tx.day)
    }

    private func run(_ work: @escaping () async -> Void) {
        working = true
        Task {
            await work()
            working = false
            dismiss()
        }
    }
}

/// A full-width action in a sheet. Prominent is the one the screen is *for* —
/// on a review row that is "Vérifié", which is why it is the tinted one and the
/// destructive action is not.
struct SheetAction: View {
    let label: String
    let symbol: String
    var prominent = false
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                Text(label).font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(
                prominent ? Color.black : (destructive ? Florin.negative : Florin.text)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                prominent
                    ? AnyShapeStyle(Florin.accent)
                    : AnyShapeStyle(
                        destructive ? Florin.negative.opacity(0.12) : Florin.surface2
                    ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Chips that wrap. `Layout` rather than a wrapped `HStack` so a long category
/// name pushes the next chip down instead of off the screen.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var rows: [[(LayoutSubview, CGSize)]] = [[]]
        var x: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.width, x > 0 {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append((view, size))
            x += size.width + spacing
        }
        var y = bounds.minY
        for row in rows {
            let rowWidth = row.reduce(0) { $0 + $1.1.width } + spacing * CGFloat(max(0, row.count - 1))
            var cursor = bounds.minX + (bounds.width - rowWidth) / 2
            let height = row.map(\.1.height).max() ?? 0
            for (view, size) in row {
                view.place(
                    at: CGPoint(x: cursor, y: y + (height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                cursor += size.width + spacing
            }
            y += height + spacing
        }
    }
}


/// The measured height of a sheet's content, for sizing its detent.
private struct SheetContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
