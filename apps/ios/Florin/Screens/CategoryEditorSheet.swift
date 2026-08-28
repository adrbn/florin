import SwiftUI

/// What the user is about to shape: a new envelope, or an existing one.
struct CategoryDraft: Identifiable {
    let groupId: String
    let groupName: String
    var category: PlanCategory?

    var id: String { category?.id ?? "new:\(groupId)" }
}

/// Naming an envelope.
///
/// Three decisions and no more: what it is called, what it looks like in a
/// list of thirty, and whether it is a bill that arrives whether or not you
/// budget for it. Anything else — the amount, the group, the order — is
/// decided elsewhere or has a sane default, and a form that asks for it all at
/// once is a form people abandon.
struct CategoryEditorSheet: View {
    let draft: CategoryDraft
    let t: Strings
    let onSave: (String, String, Bool) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var emoji: String
    @State private var isFixed: Bool
    @State private var saving = false
    @FocusState private var focused: Bool

    /// A short palette beats a full emoji keyboard here: it is one tap instead
    /// of a search, and it keeps the list visually coherent instead of turning
    /// it into whatever each person's recents happened to hold.
    private static let palette = [
        "🛒", "🍽️", "🚗", "🏠", "💡", "📱", "🚌", "⛽️", "🏥", "💊",
        "👕", "🎬", "🎁", "✈️", "🏋️", "📚", "🐾", "☕️", "🍺", "💇",
        "🧾", "🛡️", "💳", "🎓", "🔧", "🌱", "🎵", "💼", "🧸", "❓",
    ]

    init(draft: CategoryDraft, t: Strings, onSave: @escaping (String, String, Bool) async -> Void) {
        self.draft = draft
        self.t = t
        self.onSave = onSave
        _name = State(initialValue: draft.category?.name ?? "")
        _emoji = State(initialValue: draft.category?.emoji ?? "🧾")
        _isFixed = State(initialValue: draft.category?.isFixed ?? false)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 10) {
                        Text(emoji).font(.system(size: 40))
                        TextField(
                            t("v2.plan.categoryNamePlaceholder", "Nom de la catégorie"),
                            text: $name
                        )
                        .font(.system(size: 20, weight: .medium))
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.sentences)
                        .focused($focused)
                        Text(draft.groupName)
                            .font(.system(size: 12))
                            .foregroundStyle(Florin.text3)
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
                                    emoji = candidate
                                } label: {
                                    Text(candidate)
                                        .font(.system(size: 20))
                                        .frame(width: 32, height: 32)
                                        .background(
                                            Circle().fill(
                                                emoji == candidate
                                                    ? Florin.accent.opacity(0.18) : .clear
                                            )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Florin.gutter)
                    }

                    Toggle(isOn: $isFixed) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t("v2.plan.categoryFixed", "Charge fixe"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Florin.text)
                            Text(
                                t(
                                    "v2.plan.categoryFixedHint",
                                    "Un montant qui tombe chaque mois : loyer, abonnement, assurance."
                                )
                            )
                            .font(.system(size: 12))
                            .foregroundStyle(Florin.text2)
                        }
                    }
                    .tint(Florin.accent)
                    .padding(.horizontal, Florin.gutter)
                    .padding(.bottom, 10)
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
                        saving = true
                        Task {
                            await onSave(trimmed, emoji, isFixed)
                            dismiss()
                        }
                    }
                    .disabled(trimmed.isEmpty || saving)
                }
            }
            /*
             * No keyboard on open.
             *
             * A new category needs a name, which argued for raising the
             * keyboard — but the sheet is 430 points tall and two thirds of it
             * are the emoji grid and the fixed-charge toggle. A full keyboard
             * puts both out of reach the moment it opens, hiding two of the
             * three decisions this sheet exists to take. The account editor is
             * the same shape and declines the same shortcut.
             */
        }
        .presentationDetents([.height(430), .large])
        .presentationDragIndicator(.visible)
    }
}
