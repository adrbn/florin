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
            ScrollView {
                VStack(spacing: 20) {
                    direction
                    figure
                    fields
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(Florin.negative)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Florin.gutter)
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Backdrop(tint: TabRoute.overview.tint))
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
        .presentationBackground(.clear)
        .onAppear {
            if accountId.isEmpty { accountId = usableAccounts.first?.id ?? "" }
            amountFocused = true
        }
    }

    /*
     * Two glass chips, not a system segmented control.
     *
     * The sign is the single most consequential choice on this sheet — get it
     * wrong and the figure lands on the wrong side of every total — so it is
     * the first thing on screen, at a size you cannot mis-tap, in the same
     * material as the rest of the app rather than a grey slab that belonged to
     * the Form this sheet used to be.
     */
    private var direction: some View {
        HStack(spacing: 10) {
            directionChip(t("v2.add.expense", "Dépense"), expense: true, tint: Florin.negative)
            directionChip(t("v2.add.income", "Entrée"), expense: false, tint: Florin.positive)
        }
        .padding(.horizontal, Florin.gutter)
    }

    private func directionChip(_ label: String, expense: Bool, tint: Color) -> some View {
        let active = isExpense == expense
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy(duration: 0.2)) { isExpense = expense }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: expense ? "arrow.down.left" : "arrow.up.right")
                    .font(.system(size: 13, weight: .bold))
                Text(label).font(.system(size: 15, weight: active ? .semibold : .medium))
            }
            .foregroundStyle(active ? tint : Florin.text2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                active ? tint.opacity(0.16) : Color.clear,
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    active ? tint.opacity(0.5) : Florin.text.opacity(0.10),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }

    /// Centred at every length, sign in front of it, so what you are recording
    /// is legible at a glance before you commit it.
    private var figure: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(isExpense ? "−" : "+")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(isExpense ? Florin.negative : Florin.positive)
                .opacity(magnitude > 0 ? 1 : 0.25)
            TextField("0", text: $amount)
                .keyboardType(.decimalPad)
                .focused($amountFocused)
                .multilineTextAlignment(.center)
                .font(.system(size: 52, weight: .light))
                .monospacedDigit()
                .foregroundStyle(Florin.text)
                .fixedSize()
            Text(Money.currencySymbol(locale: data.localeTag, currency: data.currency))
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Florin.text3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var fields: some View {
        RowGroup {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(Florin.text3)
                    .frame(width: 24)
                TextField(t("v2.add.payee", "Bénéficiaire"), text: $payee)
                    .textInputAutocapitalization(.words)
                    .font(.system(size: 16))
            }
            .padding(.horizontal, Florin.gutter)
            .padding(.vertical, 14)

            Hairline()

            pickerRow(
                symbol: "building.columns",
                label: t("v2.add.account", "Compte")
            ) {
                /*
                 * A Menu, not a Picker.
                 *
                 * `.pickerStyle(.menu)` renders its current value as a Text
                 * that wraps, and "Sans catégorie" promptly took two lines and
                 * pushed itself over the Date row below. A Menu lets the label
                 * be ours, so it can be held to one line and truncated like any
                 * other value in a row.
                 */
                Menu {
                    Picker("", selection: $accountId) {
                        ForEach(usableAccounts) { Text($0.name).tag($0.id) }
                    }
                } label: {
                    menuValue(
                        usableAccounts.first { $0.id == accountId }?.name
                            ?? t("v2.add.account", "Compte")
                    )
                }
            }

            Hairline()

            pickerRow(symbol: "tag", label: t("v2.add.category", "Catégorie")) {
                Menu {
                    Picker("", selection: $categoryId) {
                        Text(t("v2.common.uncategorized", "Sans catégorie")).tag("")
                        ForEach(data.categories) { category in
                            Text("\(category.emoji.map { $0 + " " } ?? "")\(category.name)")
                                .tag(category.id)
                        }
                    }
                } label: {
                    let selected = data.categories.first { $0.id == categoryId }
                    menuValue(
                        selected.map { "\($0.emoji.map { $0 + " " } ?? "")\($0.name)" }
                            ?? t("v2.common.uncategorized", "Sans catégorie")
                    )
                }
            }

            Hairline()

            pickerRow(symbol: "calendar", label: t("v2.add.date", "Date")) {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .labelsHidden()
            }

            Hairline()

            HStack(spacing: 12) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 16))
                    .foregroundStyle(Florin.text3)
                    .frame(width: 24)
                TextField(t("v2.add.memo", "Note"), text: $memo, axis: .vertical)
                    .font(.system(size: 16))
                    .lineLimit(1...3)
            }
            .padding(.horizontal, Florin.gutter)
            .padding(.vertical, 14)
        }
        .padding(.horizontal, Florin.gutter)
    }

    /// One line, truncated, with the chevron the row would have had anyway.
    private func menuValue(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 16))
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Florin.accent)
        .frame(maxWidth: 190, alignment: .trailing)
    }

    private func pickerRow<Content: View>(
        symbol: String,
        label: String,
        @ViewBuilder control: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(Florin.text3)
                .frame(width: 24)
            Text(label).font(.system(size: 16)).foregroundStyle(Florin.text)
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, Florin.gutter)
        .padding(.vertical, 8)
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
