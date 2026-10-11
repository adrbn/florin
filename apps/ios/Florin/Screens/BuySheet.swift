import UIKit
import PhotosUI
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
    @State private var lines: [(id: String, label: String, lastPrice: Double?)] = []
    /// nil until loaded; "" means a new line, whose name is typed below.
    @State private var holdingId: String?
    @State private var newLabel = ""
    @State private var quantityText = ""
    @State private var priceText = ""
    @State private var totalText = ""
    @State private var failure: String?
    /// La capture de la confirmation d'ordre, en cours de lecture.
    @State private var shot: PhotosPickerItem?
    @State private var reading = false
    @FocusState private var focus: Field?

    private enum Field { case label, quantity, price, total }

    private var price: Double { OnboardingFlow.parse(priceText) }

    /*
     * Ce qu'on n'a pas saisi se déduit du reste.
     *
     * La feuille demandait la quantité, le prix unitaire et le total : trois
     * chiffres, dont deux qu'il faut aller chercher dans l'historique du
     * courtier — à supposer qu'on l'y trouve. Or un achat se décide dans
     * l'autre sens : on place une somme, et le nombre de parts en découle.
     *
     * Le montant payé est donc la question, et le dernier cours connu de la
     * ligne — que le grand livre garde déjà — donne la quantité. L'inverse
     * marche aussi : la quantité saisie donne le total. Et quand les trois
     * sont connus, rien n'est déduit du tout, parce que `quantité × cours` et
     * le montant réellement débité diffèrent de quelques centimes et que
     * c'est le second qui a bougé le compte.
     *
     * Chaque champ ne lit que ce qui a été *tapé*, jamais la valeur déduite
     * de l'autre : sans quoi les deux se définiraient l'un par l'autre.
     */
    private var quantity: Double {
        if !quantityText.isEmpty { return OnboardingFlow.parse(quantityText) }
        guard price > 0 else { return 0 }
        // Au millième de part : les courtiers fractionnent, et arrondir au
        // titre entier ferait mentir la valeur du portefeuille.
        return (OnboardingFlow.parse(totalText) / price * 1000).rounded() / 1000
    }

    private var total: Double {
        if !totalText.isEmpty { return OnboardingFlow.parse(totalText) }
        return (OnboardingFlow.parse(quantityText) * price * 100).rounded() / 100
    }

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
                    slip
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
            fillPrice()
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
                    choice(held.label, picked: holdingId == held.id) {
                        holdingId = held.id
                        priceText = ""
                        fillPrice()
                    }
                }
                if !lines.isEmpty { Hairline() }
                choice(t("v2.buy.newLine", "Nouveau titre"), picked: holdingId == nil) {
                    holdingId = nil
                    priceText = ""
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
                field(t("v2.buy.total", "Total payé"), text: totalBinding, field: .total, unit: "€")
                Hairline()
                field(t("v2.buy.unitPrice", "Prix unitaire"), text: $priceText, field: .price, unit: "€")
                Hairline()
                field(
                    t("v2.buy.quantity", "Quantité"), text: quantityBinding,
                    field: .quantity, unit: nil
                )
            }
            Text(t(
                "v2.buy.derivedHint",
                "Le cours est celui du dernier achat enregistré. Corrige-le, ou saisis directement la quantité si tu as la confirmation du courtier."
            ))
            .font(.system(size: 12))
            .foregroundStyle(Florin.text3)
            .padding(.horizontal, 4)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Chacun montre la valeur déduite tant qu'on ne l'a pas contredite, et
    /// la saisie fait basculer le sens du calcul.
    private var totalBinding: Binding<String> {
        Binding(
            get: { totalText.isEmpty ? (total > 0 ? String(format: "%.2f", total) : "") : totalText },
            set: { totalText = $0 }
        )
    }

    private var quantityBinding: Binding<String> {
        Binding(
            get: { quantityText.isEmpty ? (quantity > 0 ? trim(quantity) : "") : quantityText },
            set: { quantityText = $0 }
        )
    }

    /// Le cours de la ligne choisie, pour que la quantité se déduise sans
    /// qu'on ait à aller le chercher. Jamais par-dessus un cours déjà tapé.
    private func fillPrice() {
        guard priceText.isEmpty else { return }
        guard let id = holdingId,
              let last = lines.first(where: { $0.id == id })?.lastPrice, last > 0
        else { return }
        priceText = String(format: "%.4f", last)
            .replacingOccurrences(of: "0000", with: "00")
    }

    /*
     * Les trois chiffres, lus sur la capture plutôt que recopiés.
     *
     * Le courtier les affiche tous les trois au moment de l'achat, et devient
     * avare ensuite. Une capture d'écran faite là, dans la pellicule, est la
     * seule copie facile de l'ordre — et la reconnaissance de texte sait la
     * lire (voir `OrderSlip`). Ce qu'elle ne reconnaît pas reste à taper :
     * aucun chiffre n'est deviné.
     */
    private var slip: some View {
        PhotosPicker(selection: $shot, matching: .images, photoLibrary: .shared()) {
            HStack(spacing: 8) {
                if reading {
                    ProgressView()
                } else {
                    Image(systemName: "text.viewfinder").font(.system(size: 15))
                }
                Text(t("v2.buy.readSlip", "Lire une capture de l'ordre"))
                    .font(.system(size: 14.5, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .florinGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Florin.accent)
        .disabled(reading)
        .onChange(of: shot) { _, item in
            guard let item else { return }
            read(item)
        }
    }

    private func read(_ item: PhotosPickerItem) {
        reading = true
        Task {
            defer { reading = false; shot = nil }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else { return }
            let lines = (try? ReceiptOCR.lines(from: image)) ?? []
            let order = OrderSlip.read(lines)
            guard !order.isEmpty else {
                failure = t(
                    "v2.buy.slipUnread",
                    "Rien de lisible sur cette image. Les chiffres restent à saisir."
                )
                return
            }
            if let value = order.unitPrice { priceText = String(format: "%.4f", value) }
            if let value = order.quantity { quantityText = trim(value) }
            if let value = order.total { totalText = String(format: "%.2f", value) }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
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
                .keyboardType(.decimalPad)
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
