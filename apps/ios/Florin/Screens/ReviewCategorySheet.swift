import SwiftUI

/*
 * The question asked before the answer is filed away.
 *
 * Validating a transaction is saying "yes, this is right" — and a transaction
 * with no category is not right yet. Once validated it leaves the queue, and
 * nothing ever asks again: it silently stops counting towards any budget, and
 * the spending it represents disappears from every total that matters. The
 * damage is invisible, which is what makes it worth a step.
 *
 * So the ones that are missing a category are put back in front of the person
 * one at a time, with the whole list of categories a thumb away. Filing one
 * moves to the next. Skipping is allowed — some things genuinely have no
 * category, and a wall that cannot be walked past is worse than the problem —
 * but it has to be chosen rather than happen by default.
 */
struct ReviewCategorySheet: View {
    let transactions: [Transaction]
    let categories: [Category]
    let locale: String
    let currency: String
    let t: Strings
    /// Files one transaction. Awaited, so the next card only appears once the
    /// previous one is actually written.
    let onAssign: (String, String) async -> Void
    /// Everything has been filed or deliberately left alone.
    let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var working = false
    /*
     * The guess the app already made and threw away.
     *
     * `LocalCategoriser.suggest` runs on every incoming row and only writes
     * itself above 0.8 confidence — below that the row lands here and the guess
     * is discarded, which is the wrong end to lose it. It was not certain
     * enough to file unattended; it is easily good enough to offer to someone
     * who is standing right here deciding.
     *
     * Read once: it is a scan of the filed history, not something to redo per
     * card.
     */
    @State private var memory: LocalCategoriser.Memory?

    private var current: Transaction? {
        index < transactions.count ? transactions[index] : nil
    }

    private var groups: [(name: String, items: [Category])] {
        var order: [String] = []
        var buckets: [String: [Category]] = [:]
        for category in categories {
            if buckets[category.groupName] == nil { order.append(category.groupName) }
            buckets[category.groupName, default: []].append(category)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    var body: some View {
        ZStack {
            Backdrop(tint: Florin.sheetTint, floor: true).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if let tx = current {
                    card(tx)
                    picker
                }
                footer
            }
        }
        .task {
            guard let store = LocalStore.shared else { return }
            memory = try? LocalCategoriser.remember(store: store)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Florin.text2)
                    .frame(width: 30, height: 30)
                    .florinGlass(in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("v2.common.close", "Fermer"))

            Spacer()

            // Where you are in the batch. One transaction does not need a
            // score, and five without one feels endless.
            if transactions.count > 1 {
                Text(t(
                    "v2.review.progress", "{index} sur {total}",
                    ["index": min(index + 1, transactions.count), "total": transactions.count]
                ))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Florin.text3)
                .monospacedDigit()
            }
        }
        .padding(.horizontal, Florin.gutter)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private func card(_ tx: Transaction) -> some View {
        VStack(spacing: 6) {
            AmountText(
                value: tx.amount, locale: locale, currency: currency,
                signed: true, tone: .auto, size: 34, weight: .light
            )
            Text(PayeeText.humanize(tx.payee))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Florin.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text("\(dayLabel(tx.day)) · \(tx.accountName)")
                .font(.system(size: 12.5))
                .foregroundStyle(Florin.text3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, Florin.gutter)
        .id(tx.id)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    /// What the ledger thinks this is, when it has an opinion.
    private var suggestion: Category? {
        guard let memory, let tx = current,
              let hit = LocalCategoriser.suggest(
                  memory, payee: tx.payee, amount: tx.amount, accountId: ""
              )
        else { return nil }
        return categories.first { $0.id == hit.categoryId }
    }

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let hint = suggestion {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: t("v2.review.suggestion", "Sans doute"))
                        chip(hint, prominent: true)
                    }
                }
                ForEach(groups, id: \.name) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: group.name)
                        FlowRow(spacing: 8) {
                            ForEach(group.items) { category in
                                chip(category)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Florin.gutter)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .disabled(working)
        .opacity(working ? 0.5 : 1)
    }

    private func chip(_ category: Category, prominent: Bool = false) -> some View {
        Button {
            guard let tx = current, !working else { return }
            working = true
            UISelectionFeedbackGenerator().selectionChanged()
            Task {
                await onAssign(tx.id, category.id)
                working = false
                advance()
            }
        } label: {
            HStack(spacing: 6) {
                Text(category.emoji ?? "•").font(.system(size: 14))
                Text(category.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Florin.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, prominent ? 16 : 12)
            .padding(.vertical, prominent ? 12 : 9)
            .background(
                prominent ? Florin.accent.opacity(0.22) : .clear, in: Capsule()
            )
            .florinGlass(in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                advance()
            } label: {
                Text(t("v2.review.skipOne", "Passer celle-ci"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Florin.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .florinGlass(in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(working)

            Button {
                onFinish()
                dismiss()
            } label: {
                Text(t("v2.review.approveAnyway", "Valider sans catégoriser"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Florin.text3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Florin.gutter)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private func advance() {
        withAnimation(.snappy(duration: 0.22)) { index += 1 }
        guard index >= transactions.count else { return }
        onFinish()
        dismiss()
    }

    private func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: locale)
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f.string(from: date)
    }
}
