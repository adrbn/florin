import SwiftUI

/// Record a transaction from the phone.
///
/// The amount is the hero of this sheet, so it gets hero treatment: large,
/// centred, and focused on open. `.decimalPad` is deliberate — `.numberPad`
/// has no separator key, which is exactly the key you need to type 12,40.
struct AddTransactionSheet: View {
    let data: Overview
    let submit: (NewTransaction) async throws -> Void
    var onTransfer: (NewTransfer) async throws -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    private var t: Strings { data.t }
    @FocusState private var amountFocused: Bool

    /*
     * Three things a row can be, not two.
     *
     * Without a transfer, moving money to savings has to be entered as an
     * expense that is not one — it shrinks the account it left, never fills
     * the account it reached, and lands in a budget as spending. The sign
     * toggle was the whole vocabulary; this adds the third word.
     */
    private enum Kind { case expense, income, transfer }
    @State private var kind: Kind = .expense
    @State private var toAccountId = ""
    private var isExpense: Bool { kind == .expense }
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
        guard magnitude > 0, !accountId.isEmpty else { return false }
        // A transfer needs a destination rather than a payee: the two account
        // names are the description, and asking for one as well would be
        // asking the user to name something they have already chosen twice.
        if kind == .transfer { return !toAccountId.isEmpty && toAccountId != accountId }
        return !payee.trimmingCharacters(in: .whitespaces).isEmpty
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
            .background(Backdrop(tint: Florin.sheetTint, floor: true))
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
            directionChip(t("v2.add.expense", "Dépense"), kind: .expense, tint: Florin.negative)
            directionChip(t("v2.add.income", "Entrée"), kind: .income, tint: Florin.positive)
            directionChip(t("v2.add.transfer", "Virement"), kind: .transfer, tint: Florin.accent)
        }
        .padding(.horizontal, Florin.gutter)
    }

    private func directionChip(_ label: String, kind target: Kind, tint: Color) -> some View {
        let active = kind == target
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy(duration: 0.2)) { kind = target }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: target == .expense ? "arrow.down.left"
                        : target == .income ? "arrow.up.right" : "arrow.left.arrow.right")
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
            Text(kind == .income ? "+" : "−")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(
                    kind == .income ? Florin.positive
                        : kind == .transfer ? Florin.accent : Florin.negative
                )
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
            // A transfer has no payee: the two account names describe it, and
            // asking for one as well is asking the user to name something they
            // are about to choose twice.
            if kind != .transfer {
                HStack(spacing: 13) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Florin.accent.opacity(0.85))
                        .frame(width: 22)
                    TextField(t("v2.add.payee", "Bénéficiaire"), text: $payee)
                        .textInputAutocapitalization(.words)
                        .font(.system(size: 15.5, weight: .medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 15)

                Hairline()
            }

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

            if kind == .transfer {
                Hairline()
                pickerRow(
                    symbol: "arrow.down.right",
                    label: t("v2.add.toAccount", "Vers")
                ) {
                    Menu {
                        Picker("", selection: $toAccountId) {
                            ForEach(usableAccounts.filter { $0.id != accountId }) {
                                Text($0.name).tag($0.id)
                            }
                        }
                    } label: {
                        menuValue(
                            usableAccounts.first { $0.id == toAccountId }?.name
                                ?? t("v2.add.pickAccount", "Choisir")
                        )
                    }
                }
            }

            Hairline()

            // A transfer has no payee and no category: the two account names
            // describe it, and money moved between them is not spending to
            // classify.
            if kind != .transfer {
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
            }

            Hairline()

            pickerRow(symbol: "calendar", label: t("v2.add.date", "Date")) {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .labelsHidden()
            }

            Hairline()

            HStack(spacing: 13) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Florin.accent.opacity(0.85))
                    .frame(width: 22)
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
        /*
         * The value carries the weight, and says it can be changed.
         *
         * Label and value were the same size in the same direction, so a row
         * read as a sentence rather than as a choice. The value is now the
         * heavier of the two and sits in a chip you can see is a target — the
         * date already had one, and the rest looked inert beside it.
         */
        HStack(spacing: 5) {
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .bold))
                .opacity(0.7)
        }
        .foregroundStyle(Florin.accent)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Florin.accent.opacity(0.14), in: Capsule())
        .frame(maxWidth: 200, alignment: .trailing)
    }

    private func pickerRow<Content: View>(
        symbol: String,
        label: String,
        @ViewBuilder control: () -> Content
    ) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Florin.accent.opacity(0.85))
                .frame(width: 22)
            // The label is the quieter half: what matters on each row is the
            // value, which is also the thing you tap.
            Text(label)
                .font(.system(size: 14.5))
                .foregroundStyle(Florin.text2)
            Spacer(minLength: 10)
            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func save() {
        guard isValid, !saving else { return }
        saving = true
        errorMessage = nil
        let trimmedMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                if kind == .transfer {
                    try await onTransfer(
                        NewTransfer(
                            fromAccountId: accountId,
                            toAccountId: toAccountId,
                            amount: abs(magnitude),
                            occurredAt: ISO8601DateFormatter.florinNoFraction.string(from: noonOn(date)),
                            memo: trimmedMemo.isEmpty ? nil : trimmedMemo
                        )
                    )
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                    saving = false
                    return
                }
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
