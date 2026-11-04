import SwiftUI

/*
 * Désigner la dépense qu'une rentrée rembourse.
 *
 * On ne cherche pas, on reconnaît : la liste part des dépenses récentes d'au
 * moins le montant rendu (voir `LocalReimbursements.candidates`), la plus
 * récente d'abord. Le champ ne sert qu'à écarter, pas à trouver.
 *
 * Choisir fait DEUX choses, et la seconde est le vrai intérêt : le lien,
 * et la catégorie de la dépense recopiée sur la rentrée. C'est elle qui fait
 * que le poste se solde net — trente euros rendus sur une addition rangée en
 * « Sorties » ne valent rien s'ils atterrissent en « Courses ».
 */
struct ReimbursementPicker: View {
    let income: Transaction
    let t: Strings
    let locale: String
    let currency: String
    /// Vrai quand la rentrée désigne déjà une dépense : il y a alors de quoi
    /// défaire, et pas seulement de quoi choisir.
    var linked: Bool
    /// Rappelé après coup : la feuille dessous affiche encore l'ancien lien.
    var onPick: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var rows: [LocalReimbursements.Entry] = []

    var body: some View {
        NavigationStack {
            List {
                if rows.isEmpty {
                    Text(t("v2.reimburse.empty", "Aucune dépense d'au moins ce montant ces trois derniers mois."))
                        .font(.system(size: 14))
                        .foregroundStyle(Florin.text3)
                        .listRowBackground(Color.clear)
                }
                ForEach(rows) { row in
                    Button { pick(row) } label: { line(row) }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .searchable(text: $search, prompt: t("v2.common.search", "Rechercher"))
            .navigationTitle(t("v2.reimburse.title", "Quelle dépense ?"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.cancel", "Annuler")) { dismiss() }
                }
                if linked {
                    ToolbarItem(placement: .primaryAction) {
                        Button(t("v2.reimburse.unlink", "Détacher"), role: .destructive) {
                            guard let store = LocalStore.shared else { return }
                            try? LocalReimbursements.link(
                                store: store, income: income.id, to: nil
                            )
                            onPick()
                            dismiss()
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(t("v2.reimburse.hint", "La rentrée prendra la catégorie de la dépense choisie."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Florin.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Florin.gutter)
                    .padding(.vertical, 10)
                    .background(Florin.bg)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task(id: search) { load() }
    }

    private func line(_ row: LocalReimbursements.Entry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(PayeeText.title(row.payee, category: nil))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Florin.text)
                    .lineLimit(1)
                Text(DayLabel.string(row.day, locale: locale, t: t))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Florin.text3)
            }
            Spacer(minLength: 8)
            Text(Money.string(row.amount, locale: locale, currency: currency))
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Florin.text2)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func load() {
        guard let store = LocalStore.shared else { return }
        rows = (try? LocalReimbursements.candidates(store: store, for: income, search: search)) ?? []
    }

    private func pick(_ row: LocalReimbursements.Entry) {
        guard let store = LocalStore.shared else { return }
        try? LocalReimbursements.link(store: store, income: income.id, to: row.id)
        // La catégorie de la dépense, parce que c'est elle qui fait que le
        // poste se solde net. Réversible d'une tape, comme tout le reste.
        let category = try? store.database.query(
            "SELECT category_id FROM transactions WHERE id = ?", [.text(row.id)]
        ).first?.string("category_id")
        if let category = category ?? nil {
            try? LocalLedger.patch(store: store, id: income.id, TxPatch(categoryId: category))
        }
        onPick()
        dismiss()
    }
}
