import SwiftUI

/// Naming an account, and giving it a face.
///
/// The name alone was editable, through a bare system alert that wrote its SQL
/// from inside the view. But a list of accounts is scanned by icon long before
/// it is read: a bank imports "CCP" with whatever glyph its kind implies, and
/// the one place that could correct it offered a text field and nothing else.
struct AccountEditSheet: View {
    let account: Account
    let t: Strings
    let onSave: (String, String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var icon: String
    @FocusState private var focused: Bool

    /// A short palette beats the emoji keyboard: one tap instead of a search,
    /// and the list keeps a family resemblance instead of becoming whatever
    /// each person's recents happened to hold.
    private static let palette = [
        "🏦", "💳", "💰", "🐷", "📈", "🎓", "🏠", "💶", "🪙", "🧾",
        "🛡️", "🚗", "✈️", "👛", "💼", "🔐", "📊", "🌱", "⭐️", "❓",
    ]

    init(account: Account, t: Strings, onSave: @escaping (String, String) async -> Void) {
        self.account = account
        self.t = t
        self.onSave = onSave
        _name = State(initialValue: account.name)
        _icon = State(initialValue: account.displayIcon ?? "🏦")
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
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Backdrop(tint: Florin.sheetTint, floor: true))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.cancel", "Annuler")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("v2.common.save", "Enregistrer")) {
                        Task { await onSave(trimmed, icon); dismiss() }
                    }
                    .disabled(trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.height(380), .large])
        .presentationDragIndicator(.visible)
    }
}
