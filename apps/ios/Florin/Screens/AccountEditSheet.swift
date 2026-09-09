import SwiftUI

/// Naming an account, giving it a face, and saying what is on it.
///
/// The name alone was editable, through a bare system alert that wrote its SQL
/// from inside the view. But a list of accounts is scanned by icon long before
/// it is read: a bank imports "CCP" with whatever glyph its kind implies, and
/// the one place that could correct it offered a text field and nothing else.
///
/// The balance joined it rather than living behind a menu of its own. Editing
/// an account is one thought — "this is what it is called and this is what is
/// on it" — and splitting it across two entries made the second one a thing to
/// go and find. `balance` is nil where the figure is not ours to state: a bank
/// account the bank keeps, a broker whose value comes from its holdings.
struct AccountEditSheet: View {
    let account: Account
    let t: Strings
    /// The current balance, when this account's is editable at all.
    var balance: Double?
    let onSave: (String, String, Double?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var icon: String
    @State private var amount: String
    @State private var contentHeight: CGFloat = 0
    @FocusState private var focused: Bool

    /// A short palette beats the emoji keyboard: one tap instead of a search,
    /// and the list keeps a family resemblance instead of becoming whatever
    /// each person's recents happened to hold.
    private static let palette = [
        "🏦", "💳", "💰", "🐷", "📈", "🎓", "🏠", "💶", "🪙", "🧾",
        "🛡️", "🚗", "✈️", "👛", "💼", "🔐", "📊", "🌱", "⭐️", "❓",
    ]

    init(
        account: Account, t: Strings, balance: Double? = nil,
        onSave: @escaping (String, String, Double?) async -> Void
    ) {
        self.account = account
        self.t = t
        self.balance = balance
        self.onSave = onSave
        _name = State(initialValue: account.name)
        _icon = State(initialValue: account.displayIcon ?? "🏦")
        _amount = State(initialValue: balance.map { Self.plain($0) } ?? "")
    }

    /// « 410,00 » et non « 410.00 » : le champ se relit comme le reste de
    /// l'app l'écrit, et l'analyseur accepte les deux séparateurs de toute
    /// façon.
    private static func plain(_ value: Double) -> String {
        let f = NumberFormatter()
        f.locale = .current
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    /// The figure typed, or nil when it has not moved — so saving a rename
    /// never writes an adjustment of zero.
    private var newBalance: Double? {
        guard let balance else { return nil }
        let typed = OnboardingFlow.parse(amount)
        return abs(typed - balance) < 0.005 ? nil : typed
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        Text(icon).font(.system(size: 40))
                        TextField(t("v2.accounts.name", "Nom du compte"), text: $name)
                            .font(.system(size: 20, weight: .medium))
                            .multilineTextAlignment(.center)
                            .textInputAutocapitalization(.words)
                            .focused($focused)
                        if let institution = account.institution {
                            Text(institution)
                                .font(.system(size: 12))
                                .foregroundStyle(Florin.text3)
                        }
                    }
                    .padding(.top, 8)

                    if balance != nil {
                        VStack(spacing: 5) {
                            Eyebrow(text: t("v2.account.balance", "Solde"))
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                TextField("0", text: $amount)
                                    .font(.system(size: 30, weight: .light))
                                    .monospacedDigit()
                                    .multilineTextAlignment(.center)
                                    .keyboardType(.numbersAndPunctuation)
                                    .fixedSize()
                                Text("€").font(.system(size: 16)).foregroundStyle(Florin.text3)
                            }
                            /*
                             * Dit avant, pas après.
                             *
                             * L'écart s'écrit comme une opération datée
                             * d'aujourd'hui. C'est le bon mécanisme — un solde
                             * qui bouge sans trace est ce qui rend un grand
                             * livre inexplicable — mais il faut le savoir en
                             * appuyant, pas le découvrir dans l'historique.
                             */
                            if let delta = newBalance.map({ $0 - (balance ?? 0) }) {
                                Text(t(
                                    "v2.balance.willWrite",
                                    "Une opération d'ajustement de {amount} sera ajoutée.",
                                    ["amount": Money.string(
                                        delta, locale: "fr-FR", currency: "EUR",
                                        decimals: true, signed: true
                                    )]
                                ))
                                .font(.system(size: 12))
                                .foregroundStyle(Florin.text2)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Florin.gutter)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: t("v2.plan.categoryIcon", "Icône"))
                            .padding(.horizontal, Florin.gutter)
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 10),
                            spacing: 8
                        ) {
                            ForEach(Self.palette, id: \.self) { candidate in
                                Button {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    icon = candidate
                                } label: {
                                    Text(candidate)
                                        .font(.system(size: 20))
                                        .frame(width: 32, height: 32)
                                        .background(
                                            Circle().fill(
                                                icon == candidate
                                                    ? Florin.accent.opacity(0.20) : .clear
                                            )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Florin.gutter)
                    }
                    .padding(.bottom, 12)
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: SheetContentHeight.self, value: proxy.size.height
                        )
                    }
                )
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.cancel", "Annuler")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("v2.common.save", "Enregistrer")) {
                        Task { await onSave(trimmed, icon, newBalance); dismiss() }
                    }
                    .disabled(trimmed.isEmpty)
                }
            }
        }
        .onPreferenceChange(SheetContentHeight.self) { contentHeight = $0 }
        /*
         * Le fond appartient à la feuille, pas à son contenu.
         *
         * Il était posé sur le ScrollView, qui s'arrête où le contenu s'arrête :
         * sous la grille d'icônes, la feuille devenait transparente et on lisait
         * l'écran du dessous. `presentationBackground` peint toute la surface
         * présentée, jusqu'au bord inférieur.
         */
        .presentationBackground { Backdrop(tint: Florin.sheetTint, floor: true) }
        // Mesurée plutôt que devinée : 500 points étaient une constante qui
        // laissait un tiers de vide dès que le compte n'avait pas d'institution
        // à afficher.
        .presentationDetents([.height(min(contentHeight + 88, 720)), .large])
        .presentationDragIndicator(.visible)
    }
}
