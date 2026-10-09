import SwiftUI

/// Pick a category, or clear it, or say it was never spending at all.
///
/// Searchable because a real install has sixty of them across a dozen groups,
/// and scrolling to "Abonnements & services" past "Auto" and "Assurance" is the
/// slowest possible way to file one transaction.
///
/// "Virement interne" lives here rather than beside Modifier and Supprimer,
/// where it first landed. Those are things you do *to* a row; this is an answer
/// to the question the row is asking — the same question every category below
/// it answers, and the right one when the honest answer is "none of them, the
/// money only changed accounts".
struct CategoryPicker: View {
    let categories: [Category]
    let selected: String?
    let t: Strings
    let onPick: (String?) -> Void
    /// Absent when the row cannot be a transfer — one already paired, or an
    /// incoming one, whose far end this flow does not know how to word.
    var onTransfer: (() -> Void)?
    /*
     * Ce que le grand livre propose, quand il n'est pas assez sûr pour le
     * faire lui-même.
     *
     * Jamais appliqué : proposé, en tête, et validé d'une tape. Le catégoriseur
     * se tait sous 0,80 pour ne pas classer de travers — mais ce qu'il avait
     * trouvé reste souvent la bonne réponse, et le chercher dans soixante
     * catégories quand il l'avait sous la main est du travail rendu à la main.
     *
     * Trois, pas une. Le premier est le plus probable et le dit ; les deux
     * suivants sont les noms que le moteur tenait en main derrière lui, et le
     * bon y est souvent quand ce n'est pas le premier.
     */
    var hints: [Category] = []

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var groups: [(name: String, items: [Category])] {
        // « cafe » doit trouver « Café » : on tape vite et sans accent, et un
        // sélecteur qui répond « aucun résultat » à un mot qui est à l'écran
        // se lit comme une catégorie absente.
        let needle = Self.fold(query)
        let matched = needle.isEmpty
            ? categories
            : categories.filter {
                Self.fold($0.name).contains(needle) || Self.fold($0.groupName).contains(needle)
            }
        var order: [String] = []
        var buckets: [String: [Category]] = [:]
        for category in matched {
            if buckets[category.groupName] == nil { order.append(category.groupName) }
            buckets[category.groupName, default: []].append(category)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !hints.isEmpty, selected == nil, query.isEmpty {
                    Section {
                        ForEach(Array(hints.enumerated()), id: \.element.id) { index, hint in
                            Button {
                                onPick(hint.id)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Text(hint.emoji ?? "•").frame(width: 22)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(hint.name).foregroundStyle(Florin.text)
                                        if index == 0 {
                                            Text(t("v2.category.hint", "Florin pense que c'est ça"))
                                                .font(.system(size: 12))
                                                .foregroundStyle(Florin.text2)
                                        } else {
                                            Text(hint.groupName)
                                                .font(.system(size: 12))
                                                .foregroundStyle(Florin.text3)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    if index == 0 {
                                        Image(systemName: "sparkles")
                                            .foregroundStyle(Florin.accent)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    if let onTransfer {
                        Button {
                            onTransfer()
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.left.arrow.right")
                                    .foregroundStyle(Florin.accent)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t("v2.activity.transfer", "Virement interne"))
                                        .foregroundStyle(Florin.text)
                                    Text(t(
                                        "v2.activity.transferHint",
                                        "L'argent a changé de compte : ni dépense, ni entrée."
                                    ))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Florin.text2)
                                }
                                Spacer()
                            }
                        }
                    }
                    Button {
                        onPick(nil)
                        dismiss()
                    } label: {
                        Label(
                            t("v2.common.uncategorized", "Sans catégorie"),
                            systemImage: "minus.circle"
                        )
                        .foregroundStyle(Florin.text2)
                    }
                }

                ForEach(groups, id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.items) { category in
                            Button {
                                onPick(category.id)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Text(category.emoji ?? "•").frame(width: 22)
                                    Text(category.name).foregroundStyle(Florin.text)
                                    Spacer()
                                    if category.name == selected {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Florin.accent)
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Backdrop(tint: TabRoute.activity.tint))
            .searchable(text: $query, prompt: t("v2.common.search", "Rechercher"))
            .navigationTitle(t("v2.review.categorize", "Catégoriser"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.cancel", "Annuler")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    /// Minuscules, sans accent : ce qu'on compare quand on cherche un mot.
    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
