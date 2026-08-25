import SwiftUI

/// Real filters, on a sheet.
///
/// The button in the corner used to focus the search field, which is not a
/// filter — it is the same search that was already one tap away. A ledger of
/// two thousand rows needs to be cut by account, by category, by direction and
/// by period, and every one of those already exists in the query layer: this
/// sheet is a face for options `/m/transactions` has always accepted.
struct FilterSheet: View {
    @Binding var filter: TxFilter
    let accounts: [Account]
    let categories: [Category]
    let t: Strings
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: TxFilter

    init(
        filter: Binding<TxFilter>,
        accounts: [Account],
        categories: [Category],
        t: Strings,
        onApply: @escaping () -> Void
    ) {
        _filter = filter
        self.accounts = accounts
        self.categories = categories
        self.t = t
        self.onApply = onApply
        _draft = State(initialValue: filter.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(t("v2.add.account", "Compte"), selection: accountBinding) {
                        Text(t("v2.filters.allAccounts", "Tous les comptes")).tag("")
                        ForEach(accounts.filter { !$0.isArchived }) { Text($0.name).tag($0.id) }
                    }
                    Picker(t("v2.add.category", "Catégorie"), selection: categoryBinding) {
                        Text(t("v2.filters.allCategories", "Toutes les catégories")).tag("")
                        Text(t("v2.common.uncategorized", "Sans catégorie")).tag(NONE)
                        ForEach(categories) { category in
                            Text("\(category.emoji.map { $0 + " " } ?? "")\(category.name)")
                                .tag(category.id)
                        }
                    }
                }

                Section {
                    Picker(t("v2.filters.direction", "Sens"), selection: $draft.direction) {
                        Text(t("v2.activity.all", "Tout")).tag(TxFilter.Direction.all)
                        Text(t("v2.activity.expenses", "Dépenses")).tag(TxFilter.Direction.expense)
                        Text(t("v2.activity.income", "Entrées")).tag(TxFilter.Direction.income)
                    }
                    .pickerStyle(.segmented)

                    Toggle(t("v2.filters.excludeTransfers", "Masquer les virements internes"),
                           isOn: $draft.excludeTransfers)
                    Toggle(t("v2.review.title", "À vérifier seulement"), isOn: $draft.needsReview)
                } header: {
                    Text(t("v2.filters.what", "Quoi"))
                }

                Section {
                    Toggle(t("v2.filters.period", "Période"), isOn: periodBinding)
                    if draft.from != nil || draft.to != nil {
                        DatePicker(
                            t("v2.filters.from", "Du"),
                            selection: fromBinding,
                            displayedComponents: .date
                        )
                        DatePicker(
                            t("v2.filters.to", "Au"),
                            selection: toBinding,
                            displayedComponents: .date
                        )
                    }
                } footer: {
                    Text(
                        t(
                            "v2.filters.periodHint",
                            "Les deux bornes sont incluses."
                        )
                    )
                }

                Section {
                    Button(t("v2.filters.reset", "Tout réinitialiser"), role: .destructive) {
                        // Search is not a filter and lives in its own field —
                        // wiping it here would clear something the user can see
                        // and did not touch.
                        let search = draft.search
                        draft = TxFilter()
                        draft.search = search
                    }
                    .disabled(!draft.isFiltered)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Backdrop(tint: TabRoute.activity.tint))
            .navigationTitle(t("v2.filters.title", "Filtres"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.cancel", "Annuler")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("v2.filters.apply", "Appliquer")) {
                        filter = draft
                        onApply()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    /// Sentinel for "has no category at all", which is a filter in its own
    /// right and the reason the review queue exists.
    private let NONE = "__none__"

    private var accountBinding: Binding<String> {
        Binding(get: { draft.accountId ?? "" }, set: { draft.accountId = $0.isEmpty ? nil : $0 })
    }

    private var categoryBinding: Binding<String> {
        Binding(get: { draft.categoryId ?? "" }, set: { draft.categoryId = $0.isEmpty ? nil : $0 })
    }

    private var periodBinding: Binding<Bool> {
        Binding(
            get: { draft.from != nil || draft.to != nil },
            set: { on in
                if on {
                    let now = Date()
                    draft.from = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
                    draft.to = now
                } else {
                    draft.from = nil
                    draft.to = nil
                }
            }
        )
    }

    private var fromBinding: Binding<Date> {
        Binding(get: { draft.from ?? Date() }, set: { draft.from = $0 })
    }

    private var toBinding: Binding<Date> {
        Binding(get: { draft.to ?? Date() }, set: { draft.to = $0 })
    }
}
