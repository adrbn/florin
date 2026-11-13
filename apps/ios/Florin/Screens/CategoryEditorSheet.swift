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
/// budget for it. « À quoi elle ressemble » tient en deux : l'icône et la
/// teinte — la seconde n'était le choix de personne jusqu'ici, un hachage du
/// nom, donc stable sans être voulu (voir `CategoryTints`). Anything else — the amount, the group, the order — is
/// decided elsewhere or has a sane default, and a form that asks for it all at
/// once is a form people abandon.
struct CategoryEditorSheet: View {
    let draft: CategoryDraft
    let t: Strings
    let onSave: (String, String, Bool, Int?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var emoji: String
    @State private var isFixed: Bool
    /// Le rang de teinte choisi, `nil` pour l'automatique. Écrit tout de
    /// suite — comme la pile de cartes d'accueil, où rien ne se valide : une
    /// couleur se juge en la voyant, pas après un aller-retour.
    @State private var slot: Int?
    @State private var saving = false
    @FocusState private var focused: Bool

    /// A short palette beats a full emoji keyboard here: it is one tap instead
    /// of a search, and it keeps the list visually coherent instead of turning
    /// it into whatever each person's recents happened to hold.
    private static let palette = [
        "🛒", "🍽️", "🚗", "🏠", "💡", "📱", "🚌", "⛽️", "🏥", "💊",
        "👕", "🎬", "🎁", "✈️", "🏋️", "📚", "🐾", "☕️", "🍺", "💇",
        "🧾", "☂️", "💳", "🎓", "🔧", "🌱", "🎵", "💼", "🧸", "❓",
    ]

    init(
        draft: CategoryDraft, t: Strings,
        onSave: @escaping (String, String, Bool, Int?) async -> Void
    ) {
        self.draft = draft
        self.t = t
        self.onSave = onSave
        _name = State(initialValue: draft.category?.name ?? "")
        _emoji = State(initialValue: draft.category?.emoji ?? "🧾")
        _isFixed = State(initialValue: draft.category?.isFixed ?? false)
        _slot = State(initialValue: draft.category.flatMap { CategoryTints.shared.slot(forId: $0.id) })
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /*
     * Les huit teintes de la série, plus le retour à l'automatique.
     *
     * Les mêmes huit que les comptes, et le même rang écrit en base : une
     * couleur n'est pas un code hexadécimal ici, c'est une place dans la
     * palette du thème, donc elle le suit au lieu de jurer avec lui.
     *
     * Une catégorie qu'on vient de créer n'a pas encore d'identifiant : son
     * rang attend l'enregistrement, et part avec lui.
     */
    private var colours: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: t("v2.plan.categoryColor", "Couleur"))
                .padding(.horizontal, Florin.gutter)
            HStack(spacing: 10) {
                ForEach(0 ..< Florin.series.count, id: \.self) { candidate in
                    swatch(fill: Florin.series[candidate], picked: slot == candidate) {
                        slot = candidate
                    }
                }
                // L'automatique n'est pas une couleur : il n'en montre donc
                // aucune.
                swatch(
                    fill: Florin.text.opacity(0.10), picked: slot == nil,
                    label: t("v2.ed.cards.auto", "Automatique")
                ) {
                    slot = nil
                }
            }
            .padding(.horizontal, Florin.gutter)
        }
    }

    private func swatch(
        fill: Color, picked: Bool, label: String? = nil, tap: @escaping () -> Void
    ) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            tap()
        } label: {
            Circle()
                .fill(fill)
                .frame(width: 26, height: 26)
                .overlay(
                    Circle().strokeBorder(
                        picked ? Florin.text : Florin.text.opacity(0.18),
                        lineWidth: picked ? 2 : 1
                    )
                )
                .overlay {
                    if label != nil {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Florin.text2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label ?? ""))
    }

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

                    colours

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
                    .tint(Florin.control)
                    .padding(.horizontal, Florin.gutter)
                    .padding(.bottom, 10)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.cancel", "Annuler")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("v2.common.save", "Enregistrer")) {
                        saving = true
                        Task {
                            await onSave(trimmed, emoji, isFixed, slot)
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
        // Le fond appartient à la feuille : posé sur le contenu, il
        // s'arrêtait où le contenu s'arrête et laissait voir l'écran du
        // dessous sous la dernière ligne.
        .presentationBackground { Backdrop(tint: Florin.sheetTint, floor: true) }
        .presentationDetents([.height(430), .large])
        .presentationDragIndicator(.visible)
    }
}
