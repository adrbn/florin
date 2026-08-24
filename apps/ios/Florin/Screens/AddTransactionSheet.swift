import SwiftUI

/// Record a transaction from the phone.
///
/// The amount is the hero of this sheet, so it gets hero treatment: large,
/// centred, and focused on open. `.decimalPad` is deliberate — `.numberPad`
/// has no separator key, which is exactly the key you need to type 12,40.
struct AddTransactionSheet: View {
    let data: Overview
    let submit: (NewTransaction) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    private var t: Strings { data.t }
    @FocusState private var amountFocused: Bool

    @State private var isExpense = true
    @State private var amount = ""
    @State private var payee = ""
    @State private var accountId = ""
    @State private var categoryId = ""
    @State private var date = Date()
    @State private var memo = ""
    @State private var saving = false
    @State private var errorMessage: String?

    private var usableAccounts: [Account] {
        data.accounts.filter { !$0.isArchived && !$0.isLoan }
    }

    private var magnitude: Double {
        Double(amount.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")) ?? 0
    }

    private var isValid: Bool {
        magnitude > 0 && !payee.trimmingCharacters(in: .whitespaces).isEmpty && !accountId.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("", selection: $isExpense) {
                        Text(t("v2.add.expense", "Dépense")).tag(true)
                        Text(t("v2.add.income", "Entrée")).tag(false)
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Spacer()
                        TextField("0", text: $amount)
                            .keyboardType(.decimalPad)
                            .focused($amountFocused)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 44, weight: .light))
                            .monospacedDigit()
                            .foregroundStyle(isExpense ? Florin.text : Florin.positive)
                            .frame(maxWidth: 220)
                        Text(Money.currencySymbol(locale: data.localeTag, currency: data.currency))
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(Florin.text3)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField(t("v2.add.payee", "Bénéficiaire"), text: $payee)
                        .textInputAutocapitalization(.words)

                    Picker(t("v2.add.account", "Compte"), selection: $accountId) {
                        ForEach(usableAccounts) { Text($0.name).tag($0.id) }
                    }

                    Picker(t("v2.add.category", "Catégorie"), selection: $categoryId) {
                        Text(t("v2.common.uncategorized", "Sans catégorie")).tag("")
                        ForEach(data.categories) { category in
                            Text("\(category.emoji.map { $0 + " " } ?? "")\(category.name)")
                                .tag(category.id)
                        }
                    }

                    DatePicker(t("v2.add.date", "Date"), selection: $date, displayedComponents: .date)
                }

                Section {
                    TextField(t("v2.add.memo", "Note"), text: $memo, axis: .vertical)
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(Florin.negative)
                    }
                }
            }
            .navigationTitle(t("v2.add.title", "Ajouter"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.cancel", "Annuler")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "…" : t("v2.common.save", "Enregistrer"), action: save)
                        .disabled(!isValid || saving)
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            if accountId.isEmpty { accountId = usableAccounts.first?.id ?? "" }
            amountFocused = true
        }
    }

    private func save() {
        guard isValid, !saving else { return }
        saving = true
        errorMessage = nil
        let trimmedMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                try await submit(
                    NewTransaction(
                        accountId: accountId,
                        // Expenses are stored negative. The toggle is the only
                        // place anyone should have to think about the sign.
                        amount: isExpense ? -abs(magnitude) : abs(magnitude),
                        payee: payee.trimmingCharacters(in: .whitespaces),
                        occurredAt: ISO8601DateFormatter.florinNoFraction.string(from: noonOn(date)),
                        memo: trimmedMemo.isEmpty ? nil : trimmedMemo,
                        categoryId: categoryId.isEmpty ? nil : categoryId
                    )
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            saving = false
        }
    }

    /// Book at midday so a timezone shift can never move a transaction to the
    /// day before, which would silently land it in the wrong month.
    private func noonOn(_ day: Date) -> Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }
}
