import SwiftUI

/// Pick a category, or clear it.
///
/// Searchable because a real install has sixty of them across a dozen groups,
/// and scrolling to "Abonnements & services" past "Auto" and "Assurance" is the
/// slowest possible way to file one transaction.
struct CategoryPicker: View {
    let categories: [Category]
    let selected: String?
    let t: Strings
    let onPick: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var groups: [(name: String, items: [Category])] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matched = needle.isEmpty
            ? categories
            : categories.filter {
                $0.name.lowercased().contains(needle) || $0.groupName.lowercased().contains(needle)
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
                Section {
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
}

/// Edit date, amount, payee and memo.
struct TransactionEditor: View {
    let tx: Transaction
    let locale: String
    let currency: String
    let t: Strings
    let onSave: (TxPatch) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var payee: String
    @State private var memo: String
    @State private var amount: String
    @State private var date: Date
    @State private var saving = false

    init(
        tx: Transaction,
        locale: String,
        currency: String,
        t: Strings,
        onSave: @escaping (TxPatch) async -> Void
    ) {
        self.tx = tx
        self.locale = locale
        self.currency = currency
        self.t = t
        self.onSave = onSave
        _payee = State(initialValue: tx.payee)
        _memo = State(initialValue: tx.memo ?? "")
        // Typed as the locale writes it, so a French user edits "12,40".
        _amount = State(initialValue: Self.plain(tx.amount, locale: locale))
        _date = State(initialValue: tx.day)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(t("v2.add.payee", "Bénéficiaire"), text: $payee)
                    TextField(t("v2.add.amount", "Montant"), text: $amount)
                        .keyboardType(.numbersAndPunctuation)
                    DatePicker(
                        t("v2.add.date", "Date"),
                        selection: $date,
                        displayedComponents: .date
                    )
                } footer: {
                    Text(
                        t(
                            "v2.activity.editSignHint",
                            "Garde le signe : une dépense est négative."
                        )
                    )
                }

                Section {
                    TextField(t("v2.add.memo", "Note"), text: $memo, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Backdrop(tint: TabRoute.activity.tint))
            .navigationTitle(t("v2.common.edit", "Modifier"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.cancel", "Annuler")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("v2.common.save", "Enregistrer"), action: save)
                        .disabled(saving || parsedAmount == nil || payee.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var parsedAmount: Double? {
        Double(amount.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: ""))
    }

    private func save() {
        guard let value = parsedAmount else { return }
        saving = true
        Task {
            await onSave(
                TxPatch(
                    payee: payee.trimmingCharacters(in: .whitespaces),
                    memo: .some(memo.isEmpty ? nil : memo),
                    amount: value,
                    occurredAt: ISO8601DateFormatter.florin.string(from: date)
                )
            )
            saving = false
            dismiss()
        }
    }

    private static func plain(_ value: Double, locale: String) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: locale)
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }
}
