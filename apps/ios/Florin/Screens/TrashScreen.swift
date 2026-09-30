import SwiftUI

/*
 * Ce qu'on a jeté, et qu'on peut reprendre.
 *
 * Supprimer ne demande plus confirmation : l'alerte coûtait un geste à chaque
 * fois pour se prémunir d'un accident rare, et d'un accident qui ne détruit
 * rien — la suppression est douce partout dans Florin, la ligne reste dans la
 * base avec sa date de mise à l'écart. Réparer vaut mieux que barrer la route.
 *
 * Trente jours, et rien n'est jamais effacé pour de bon : c'est une fenêtre
 * d'affichage, pas une purge. Effacer réellement ressusciterait ce qu'on
 * croyait jeté, puisqu'une ligne bancaire supprimée puis oubliée revient
 * neuve à la synchro suivante.
 */
struct TrashScreen: View {
    let t: Strings
    let locale: String
    let currency: String
    /// Le grand livre a changé : l'écran qui a ouvert la corbeille se recharge.
    var onChange: () async -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var rows: [Transaction] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Backdrop(tint: TabRoute.settings.tint).ignoresSafeArea()

                if rows.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "trash")
                            .font(.system(size: 28))
                            .foregroundStyle(Florin.text3)
                        Text(t(
                            "v2.trash.empty",
                            "Rien de supprimé ces trente derniers jours."
                        ))
                        .font(.system(size: 15))
                        .foregroundStyle(Florin.text2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(t(
                                "v2.trash.hint",
                                "Les suppressions des trente derniers jours. Rien n'est effacé pour de bon."
                            ))
                            .font(.system(size: 13))
                            .foregroundStyle(Florin.text3)
                            .padding(.horizontal, Florin.gutter)

                            RowGroup {
                                ForEach(Array(rows.enumerated()), id: \.element.id) { index, tx in
                                    if index > 0 { Hairline() }
                                    entry(tx)
                                }
                            }
                            .padding(.horizontal, Florin.gutter)
                        }
                        .padding(.vertical, 14)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .navigationTitle(t("v2.trash.title", "Corbeille"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.close", "Fermer")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
        .task { reload() }
    }

    private func entry(_ tx: Transaction) -> some View {
        HStack(spacing: 8) {
            TransactionRowView(
                hideUpcomingChip: true,
                tx: tx, locale: locale, currency: currency, t: t
            )
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                try? LocalLedger.restore(store: LocalStore.shared!, id: tx.id)
                withAnimation(.snappy(duration: 0.22)) { reload() }
                Task { await onChange() }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Florin.accent)
                    .frame(width: 34, height: 34)
                    .background(Florin.accent.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("v2.trash.restore", "Restaurer"))
            .padding(.trailing, Florin.gutter)
        }
    }

    private func reload() {
        guard let db = LocalStore.shared?.database else { return }
        rows = (try? LocalLedger.deletedRecently(db)) ?? []
    }
}
