import SwiftUI

/// Recording a purchase on an investment account.
///
/// The app could show a portfolio and never let anyone add to one. A monthly
/// DCA — the whole reason a PEA exists — had to be written into the database by
/// hand, which is a thing exactly one person on earth could do for this app and
/// not the person it is for. Three fields, and they are the three the broker's
/// own confirmation screen prints: how many, at what price, and what left the
/// account.
struct BuySheet: View {
    let account: Account
    let locale: String
    let currency: String
    let t: Strings
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var lines: [(id: String, label: String)] = []
    /// nil until loaded; "" means a new line, whose name is typed below.
    @State private var holdingId: String?
    @State private var newLabel = ""
    @State private var quantityText = ""
    @State private var priceText = ""
    @State private var totalText = ""
    /// True once the total has been typed over, so the derived value stops
    /// overwriting a figure someone entered on purpose.
    @State private var totalEdited = false
    @State private var failure: String?
    @FocusState private var focus: Field?

    private enum Field { case label, quantity, price, total }

    private var quantity: Double { OnboardingFlow.parse(quantityText) }
    private var price: Double { OnboardingFlow.parse(priceText) }
    private var derivedTotal: Double { (quantity * price * 100).rounded() / 100 }
    private var total: Double { totalEdited ? OnboardingFlow.parse(totalText) : derivedTotal }

    private var label: String {
        holdingId.flatMap { id in lines.first { $0.id == id }?.label }
            ?? newLabel.trimmingCharacters(in: .whitespaces)
    }

    private var isValid: Bool {
        quantity > 0 && price > 0 && total > 0 && !label.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    line
                    figures
                    summary
                    action
                }
                .padding(.horizontal, Florin.gutter)
                .padding(.top, 8)
                .padding(.bottom, 36)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(t("v2.buy.title", "Enregistrer un achat"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.cancel", "Annuler")) { dismiss() }
                }
            }
        }
        // Le fond appartient à la feuille : posé sur le contenu, il
        // s'arrêtait où le contenu s'arrête et laissait voir l'écran du
        // dessous sous la dernière ligne.
        .presentationBackground { Backdrop(tint: TabRoute.accounts.tint, floor: true) }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            guard let store = LocalStore.shared else { return }
            lines = (try? LocalHoldings.lines(store: store, accountId: account.id)) ?? []
            // The line bought last month is nearly always the line bought this
            // month; a picker that starts on "nouvelle ligne" would invite a
            // duplicate of the tracker already held.
            holdingId = lines.first?.id
        }
        .alert(
            t("v2.buy.title", "Enregistrer un achat"),
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    // MARK: - Which line

    private var line: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: t("v2.buy.asset", "Titre"))
            RowGroup {
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, held in
                    if index > 0 { Hairline() }
                    choice(held.label, picked: holdingId == held.id) { holdingId = held.id }
                }
                if !lines.isEmpty { Hairline() }
                choice(t("v2.buy.newLine", "Nouveau titre"), picked: holdingId == nil) {
                    holdingId = nil
                    focus = .label
                }
            }
            if holdingId == nil {
                TextField(t("v2.buy.assetName", "Nom du titre"), text: $newLabel)
                    .font(.system(size: 16))
                    .focused($focus, equals: .label)
                    .padding(.vertical, 13)
                    .padding(.horizontal, 16)
                    .florinGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func choice(_ text: String, picked: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: picked ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(picked ? Florin.accent : Florin.text3)
                Text(text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Florin.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - How many, at what price

    private var figures: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: t("v2.buy.order", "Ordre"))
            RowGroup {
                field(t("v2.buy.quantity", "Quantité"), text: $quantityText, field: .quantity, unit: nil)
                Hairline()
                field(t("v2.buy.unitPrice", "Prix unitaire"), text: $priceText, field: .price, unit: "€")
                Hairline()
                field(t("v2.buy.total", "Total payé"), text: totalBinding, field: .total, unit: "€")
            }
        }
    }

    /// Follows the order until it is contradicted. A broker rounds the unit
    /// price it prints, so 80 × 6,19 lands a few cents from the 496,43 € it
    /// actually took — and the figure that matters is the one that left.
    private var totalBinding: Binding<String> {
        Binding(
            get: {
                if totalEdited { return totalText }
                return derivedTotal > 0 ? String(format: "%.2f", derivedTotal) : ""
            },
            set: { totalEdited = true; totalText = $0 }
        )
    }

    private func field(
        _ label: String, text: Binding<String>, field target: Field, unit: String?
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Florin.text2)
            Spacer(minLength: 8)
            TextField("0", text: text)
                .font(.system(size: 17, weight: .medium))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .keyboardType(.numbersAndPunctuation)
                .focused($focus, equals: target)
                .frame(maxWidth: 140)
            if let unit {
                Text(unit).font(.system(size: 14)).foregroundStyle(Florin.text3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    // MARK: - What it does to the account

    @ViewBuilder
    private var summary: some View {
        if isValid {
            VStack(alignment: .leading, spacing: 6) {
                Text(t("v2.buy.effect", "Ce que ça change"))
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Florin.text)
                Text(t(
                    "v2.buy.effectBody",
                    "{label} : {quantity} titres de plus. Les liquidités du compte baissent de {total}. Aucune dépense n'est enregistrée — l'argent change de forme, il ne sort pas.",
                    [
                        "label": label,
                        "quantity": trim(quantity),
                        "total": Money.string(total, locale: locale, currency: currency),
                    ]
                ))
                .font(.system(size: 12.5))
                .foregroundStyle(Florin.text2)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .florinSurface()
        }
    }

    private var action: some View {
        Button(action: save) {
            Text(t("v2.buy.save", "Enregistrer l'achat"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Florin.accent, in: Capsule())
                .opacity(isValid ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!isValid)
    }

    /// 80 rather than 80,0 — but 0,5 keeps its half.
    private func trim(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%g", value)
    }

    private func save() {
        focus = nil
        guard let store = LocalStore.shared, isValid else { return }
        do {
            try LocalHoldings.record(
                store: store,
                accountId: account.id,
                purchase: LocalHoldings.Purchase(
                    holdingId: holdingId,
                    label: label,
                    quantity: quantity,
                    unitPrice: price,
                    total: total
                )
            )
            Task { await onSaved(); dismiss() }
        } catch {
            failure = error.localizedDescription
        }
    }
}
