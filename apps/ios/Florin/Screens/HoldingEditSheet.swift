import SwiftUI
import UIKit

/*
 * Corriger une ligne de titres, ou l'effacer.
 *
 * Un achat se saisissait et ne se reprenait jamais : la ligne ne connaissait
 * que l'addition. Une quantité tapée de travers — une capture d'écran mal lue,
 * un zéro de trop — restait, et le seul recours était de vivre avec un
 * portefeuille faux.
 *
 * Les trois chiffres sont séparés exprès. La quantité et le cours disent ce
 * qu'on détient et à combien il se négocie ; le versé dit ce qui est
 * réellement parti du compte. Corriger les deux premiers ne touche pas aux
 * liquidités — l'argent est bien parti, c'est le décompte qui était faux.
 * Effacer la ligne les rend, parce qu'on vient de dire que l'achat n'a jamais
 * eu lieu.
 */
struct HoldingEditSheet: View {
    let holding: Holding
    let locale: String
    let currency: String
    let t: Strings
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var quantity: String
    @State private var price: String
    @State private var basis: String
    @State private var removing = false

    init(
        holding: Holding, locale: String, currency: String, t: Strings,
        onSaved: @escaping () async -> Void
    ) {
        self.holding = holding
        self.locale = locale
        self.currency = currency
        self.t = t
        self.onSaved = onSaved
        _label = State(initialValue: holding.label)
        _quantity = State(initialValue: Self.plain(holding.quantity, digits: 4))
        _price = State(initialValue: holding.lastPrice.map { Self.plain($0, digits: 4) } ?? "")
        _basis = State(initialValue: Self.plain(holding.costBasis, digits: 2))
    }

    /// Les zéros de queue en moins : « 12,5 » et non « 12,5000 ».
    private static func plain(_ value: Double, digits: Int) -> String {
        let f = NumberFormatter()
        f.locale = .current
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    private var trimmed: String { label.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    TextField(t("v2.buy.asset", "Titre"), text: $label)
                        .font(.system(size: 19, weight: .medium))
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)

                    field(t("v2.buy.quantity", "Quantité"), $quantity)
                    field(t("v2.buy.unitPrice", "Prix unitaire"), $price)
                    field(t("v2.tools.contributed", "Versé"), $basis)

                    Text(t(
                        "v2.holding.editHint",
                        "La quantité et le cours disent ce que tu détiens. Le versé est l'argent réellement sorti du compte : le corriger ne déplace aucune liquidité."
                    ))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Florin.text3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Florin.gutter)

                    Button(role: .destructive) { removing = true } label: {
                        Text(t("v2.holding.remove", "Supprimer cette ligne"))
                            .font(.system(size: 14, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                Florin.negative.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .foregroundStyle(Florin.negative)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Florin.gutter)
                    .padding(.bottom, 14)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.cancel", "Annuler")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("v2.common.save", "Enregistrer")) { save() }
                        .disabled(trimmed.isEmpty)
                }
            }
            .confirmationDialog(
                t("v2.holding.removeAsk", "Supprimer cette ligne ?"),
                isPresented: $removing, titleVisibility: .visible
            ) {
                Button(t("v2.common.delete", "Supprimer"), role: .destructive) { remove() }
            } message: {
                Text(t(
                    "v2.holding.removeHint",
                    "Le versé retourne aux liquidités du compte, comme si l'achat n'avait pas eu lieu."
                ))
            }
        }
        .presentationBackground { Backdrop(tint: Florin.sheetTint, floor: true) }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        VStack(spacing: 4) {
            Eyebrow(text: title)
            TextField("0", text: text)
                .font(.system(size: 26, weight: .light))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .keyboardType(.decimalPad)
        }
    }

    private func save() {
        guard let store = LocalStore.shared else { return }
        try? LocalHoldings.update(
            store: store, holdingId: holding.id, label: trimmed,
            quantity: OnboardingFlow.parse(quantity),
            unitPrice: OnboardingFlow.parse(price),
            costBasis: OnboardingFlow.parse(basis)
        )
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task { await onSaved() }
        dismiss()
    }

    private func remove() {
        guard let store = LocalStore.shared else { return }
        try? LocalHoldings.remove(store: store, holdingId: holding.id)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task { await onSaved() }
        dismiss()
    }
}
