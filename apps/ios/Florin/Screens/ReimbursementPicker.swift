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
 *
 * La mise en page est celle des autres feuilles qui proposent un choix
 * (`AttachTransferSheet`) : un en-tête qui rappelle de quelle somme on parle,
 * puis des lignes d'opération comme partout ailleurs — pastille, nom, jour,
 * montant. Une `List` brute laissait un écran gris à filets système au milieu
 * d'une app qui n'en a nulle part.
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
    @StateObject private var logos = MerchantLogos.shared
    @State private var search = ""
    @State private var rows: [LocalReimbursements.Entry] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if rows.isEmpty {
                        Text(t("v2.reimburse.empty",
                               "Aucune dépense d'au moins ce montant ces trois derniers mois."))
                            .font(.system(size: 14))
                            .foregroundStyle(Florin.text3)
                            .padding(.horizontal, Florin.gutter)
                    } else {
                        RowGroup {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                if index > 0 { Hairline() }
                                Button { pick(row) } label: { line(row) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Florin.gutter)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Florin.bg)
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
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task(id: search) { load() }
    }

    /*
     * De quelle somme on parle, avant la liste.
     *
     * La feuille s'ouvre sur quarante lignes de dépenses : sans rappel, on a
     * déjà oublié qu'on place trente euros et pas trois cents. Le montant,
     * d'où il vient, et la seule chose que choisir va faire d'autre que lier.
     */
    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            AmountText(
                value: income.amount, locale: locale, currency: currency,
                decimals: true, signed: true, tone: .auto, size: 30, weight: .light
            )
            Text(PayeeText.title(income.payee, category: income.categoryName))
                .font(.system(size: 14))
                .foregroundStyle(Florin.text2)
                .lineLimit(1)
            Text(t("v2.reimburse.hint",
                   "La rentrée prendra la catégorie de la dépense choisie."))
                .font(.system(size: 12.5))
                .foregroundStyle(Florin.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
        }
        .padding(.horizontal, Florin.gutter)
    }

    private func line(_ row: LocalReimbursements.Entry) -> some View {
        let face = logos.face(for: row.payee)
        return HStack(spacing: 12) {
            Bubble(
                label: row.category ?? row.payee, name: row.payee,
                chosen: face?.emoji, emoji: row.emoji, logo: face?.logo
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(PayeeText.title(row.payee, category: row.category))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Florin.text)
                    .lineLimit(1)
                Text(DayLabel.string(row.day, locale: locale, t: t))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Florin.text2)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Money.string(row.amount, locale: locale, currency: currency))
                .font(.system(size: 15, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Florin.text)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
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
