import SwiftUI

/// What should happen to the transactions before a category disappears.
///
/// Deleting a category that has history is three different decisions wearing
/// one word. The screen used to make one of them silently — archiving — and
/// describe it in a confirmation whose button said "Supprimer". The user found
/// out what had happened after choosing, in language for an action they had
/// not asked for.
///
/// So the question is asked, once, and only when it is a real question: an
/// unused category is simply deleted. Each option states its consequence in
/// the same breath as its name, because that consequence is the whole choice.
struct CategoryRemovalSheet: View {
    let category: PlanCategory
    let count: Int
    /// Where the transactions could go instead — the plan's other envelopes.
    let candidates: [PlanCategory]
    let t: Strings
    let onChoose: (LocalCategories.Removal) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 8) {
                        Text(category.emoji ?? "•").font(.system(size: 34))
                        Text(category.name)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Florin.text)
                        Text(
                            t("v2.plan.removeLead", "{count} opérations sont classées ici.",
                              ["count": count])
                        )
                        .font(.system(size: 13.5))
                        .foregroundStyle(Florin.text2)
                        .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 10) {
                        if !candidates.isEmpty {
                            choice(
                                symbol: "arrow.turn.down.right",
                                title: t("v2.plan.removeMove", "Les déplacer ailleurs"),
                                detail: t(
                                    "v2.plan.removeMoveHint",
                                    "Vous choisissez la catégorie qui les reprend, puis celle-ci est supprimée."
                                ),
                                tone: Florin.accent
                            ) { picking = true }
                        }

                        choice(
                            symbol: "eye.slash",
                            title: t("v2.plan.removeArchive", "La retirer du plan"),
                            detail: t(
                                "v2.plan.removeArchiveHint",
                                "Les opérations gardent son nom et les graphiques restent lisibles. Elle disparaît du plan et des menus."
                            ),
                            tone: Florin.text2
                        ) { choose(.archive) }

                        choice(
                            symbol: "trash",
                            title: t("v2.plan.removeDetach", "Les laisser sans catégorie"),
                            detail: t(
                                "v2.plan.removeDetachHint",
                                "Elles repassent dans « À vérifier » pour être reclassées. Leur classement actuel est perdu."
                            ),
                            tone: Florin.negative
                        ) { choose(.detach) }
                    }
                    .padding(.horizontal, Florin.gutter)
                    .padding(.bottom, 12)
                }
            }
            .background(Florin.bg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.cancel", "Annuler")) { dismiss() }
                }
            }
            .sheet(isPresented: $picking) {
                CategoryTargetPicker(candidates: candidates, t: t) { target in
                    picking = false
                    choose(.reassign(to: target))
                }
            }
        }
        .presentationDetents([.height(470), .large])
        .presentationDragIndicator(.visible)
    }

    private func choose(_ how: LocalCategories.Removal) {
        Task {
            await onChoose(how)
            dismiss()
        }
    }

    private func choice(
        symbol: String, title: String, detail: String, tone: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        }) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(tone)
                    .frame(width: 26)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Florin.text)
                    Text(detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Florin.text2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .florinSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Which envelope takes the transactions over.
private struct CategoryTargetPicker: View {
    let candidates: [PlanCategory]
    let t: Strings
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                RowGroup {
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Hairline() }
                        HStack(spacing: 12) {
                            Text(item.emoji ?? "•").font(.system(size: 20))
                            Text(item.name)
                                .font(.system(size: 15))
                                .foregroundStyle(Florin.text)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            UISelectionFeedbackGenerator().selectionChanged()
                            onPick(item.id)
                        }
                    }
                }
                .padding(.horizontal, Florin.gutter)
                .padding(.top, 8)
            }
            .background(Florin.bg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(t("v2.plan.removeMoveTitle", "Reprendre les opérations"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Florin.text)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.cancel", "Annuler")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
