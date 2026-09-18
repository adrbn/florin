import SwiftUI

/// Record a transaction from the phone — or change one already recorded.
///
/// The amount is the hero of this sheet, so it gets hero treatment: large,
/// centred, and focused on open. `.decimalPad` is deliberate — `.numberPad`
/// has no separator key, which is exactly the key you need to type 12,40.
///
/// One sheet, two verbs. Editing used to be a `Form` of four fields — payee,
/// amount, date, note — in the system's grey slabs: a different screen, in a
/// different material, offering less than the screen that had created the row.
/// Everything chosen when adding was then unchangeable. The sign was typed as
/// a minus in front of the amount, the account and the category were simply
/// absent, and "en prévision" could be switched on at birth and never off —
/// so a payment entered ahead of the bank stayed out of the balance for good.
/// Two sheets could not be kept in step; there is no longer a second one.
struct AddTransactionSheet: View {
    let accounts: [Account]
    let categories: [Category]
    let localeTag: String
    let currency: String
    let t: Strings
    var submit: (NewTransaction) async throws -> Void = { _ in }
    var onTransfer: (NewTransfer) async throws -> Void = { _ in }
    /// Changing a row rather than creating one. Everything below reads the
    /// same; only the title and what `save` calls differ.
    var editing: Transaction?
    var onPatch: (TxPatch) async -> Void = { _ in }
    /// The account the sheet was opened from, when it was opened from one.
    /// Without it the only entry point was the dashboard, which always started
    /// on the first account in the list — so adding a row to anything else
    /// meant knowing to open a menu three rows down.
    var presetAccountId: String?
    /// The device's own ledger. Only there can a row wait for the bank, and
    /// only there can an edit move a row to another account: the server's
    /// PATCH knows neither verb and drops what it does not recognise.
    var isLocalLedger = false

    @Environment(\.dismiss) private var dismiss
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
    @State private var kind: Kind
    @State private var toAccountId = ""
    private var isExpense: Bool { kind == .expense }
    @State private var amount: String
    @State private var payee: String
    @State private var accountId: String
    @State private var categoryId: String
    @State private var date: Date
    @State private var memo: String
    @State private var upcoming: Bool
    @State private var saving = false
    @State private var errorMessage: String?

    init(
        accounts: [Account],
        categories: [Category],
        localeTag: String,
        currency: String,
        t: Strings,
        submit: @escaping (NewTransaction) async throws -> Void = { _ in },
        onTransfer: @escaping (NewTransfer) async throws -> Void = { _ in },
        editing: Transaction? = nil,
        onPatch: @escaping (TxPatch) async -> Void = { _ in },
        presetAccountId: String? = nil,
        isLocalLedger: Bool = false
    ) {
        self.accounts = accounts
        self.categories = categories
        self.localeTag = localeTag
        self.currency = currency
        self.t = t
        self.submit = submit
        self.onTransfer = onTransfer
        self.editing = editing
        self.onPatch = onPatch
        self.presetAccountId = presetAccountId
        self.isLocalLedger = isLocalLedger

        _kind = State(initialValue: (editing?.amount ?? -1) < 0 ? .expense : .income)
        // Typed as the locale writes it, so a French reader edits "12,40" —
        // and unsigned, because the sign is the chips above it.
        _amount = State(
            initialValue: editing.map { Self.plain(abs($0.amount), locale: localeTag) } ?? ""
        )
        _payee = State(initialValue: editing?.payee ?? "")
        _accountId = State(initialValue: editing?.accountId ?? "")
        _categoryId = State(initialValue: editing?.categoryId ?? "")
        _date = State(initialValue: editing?.day ?? Date())
        _memo = State(initialValue: editing?.memo ?? "")
        _upcoming = State(initialValue: editing?.isPending ?? false)
    }

    private var isEditing: Bool { editing != nil }

    private var usableAccounts: [Account] {
        accounts.filter {
            // A loan is repaid, not spent from — except that the row being
            // edited may already sit on one, and a picker that cannot show
            // where the row *is* would move it somewhere else on save.
            !$0.isArchived && (!$0.isLoan || $0.id == editing?.accountId)
        }
    }

    /*
     * Only an account the bank syncs: elsewhere nothing would ever come to
     * replace the row, and it would wait under "upcoming" forever.
     *
     * A row already waiting is the exception, and the reason this switch had
     * to become editable at all. Whatever made it upcoming — a tap Wallet
     * saw, an account since disconnected — the way out has to be on the sheet
     * that edits it, or the row stays out of the balance with no way to say
     * it has landed.
     */
    private var offersUpcoming: Bool {
        guard isLocalLedger, kind != .transfer, editing?.isTransfer != true else { return false }
        if editing?.isPending == true { return true }
        return usableAccounts.first { $0.id == accountId }?.isSynced == true
    }

    /// Moving a row between accounts is a device-ledger write; see
    /// `isLocalLedger`. Creating one always chooses an account.
    private var offersAccount: Bool { !isEditing || isLocalLedger }

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
            .navigationTitle(
                isEditing ? t("v2.common.edit", "Modifier") : t("v2.add.title", "Ajouter")
            )
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
            if accountId.isEmpty {
                accountId = presetAccountId
                    ?? usableAccounts.first { $0.name == editing?.accountName }?.id
                    ?? usableAccounts.first?.id ?? ""
            }
            if isEditing, categoryId.isEmpty {
                // A server row carries the category's name and not its id.
                categoryId = categories.first { $0.name == editing?.categoryName }?.id ?? ""
            }
            // Not on a transfer: there the two accounts are the decision and
            // the amount follows, so a keypad sitting over both pickers is in
            // the way rather than ahead of you. Nor when editing: the figure
            // is already right far more often than not, and a keypad over the
            // rest of the sheet hides what was actually opened to change.
            amountFocused = kind != .transfer && !isEditing
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
            /*
             * Not when editing.
             *
             * Turning a recorded row into a transfer is pairing it with the
             * account the money reached, which this sheet does not ask about —
             * "Catégoriser" does, and it is the right place: a transfer is the
             * answer to "what was this", not a third sign.
             */
            if !isEditing {
                directionChip(t("v2.add.transfer", "Virement"), kind: .transfer, tint: Florin.accent)
            }
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
            Text(Money.currencySymbol(locale: localeTag, currency: currency))
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

            if offersAccount {
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
                            ?? editing?.accountName
                            ?? t("v2.add.account", "Compte")
                    )
                }
            }
                Hairline()
            }

            if kind == .transfer {
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
                Hairline()
            }

            // A transfer has no payee and no category: the two account names
            // describe it, and money moved between them is not spending to
            // classify.
            if kind != .transfer {
            pickerRow(symbol: "tag", label: t("v2.add.category", "Catégorie")) {
                Menu {
                    Picker("", selection: $categoryId) {
                        Text(t("v2.common.uncategorized", "Sans catégorie")).tag("")
                        ForEach(categories) { category in
                            Text("\(category.emoji.map { $0 + " " } ?? "")\(category.name)")
                                .tag(category.id)
                        }
                    }
                } label: {
                    let selected = categories.first { $0.id == categoryId }
                    menuValue(
                        selected.map { "\($0.emoji.map { $0 + " " } ?? "")\($0.name)" }
                            ?? t("v2.common.uncategorized", "Sans catégorie")
                    )
                }
            }
                Hairline()
            }

            pickerRow(symbol: "calendar", label: t("v2.add.date", "Date")) {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .labelsHidden()
            }

            Hairline()

            if offersUpcoming {
                Toggle(isOn: $upcoming) {
                    HStack(spacing: 13) {
                        Image(systemName: "clock")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Florin.accent.opacity(0.85))
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t("v2.wallet.guide.flowUpcoming", "En prévision"))
                                .font(.system(size: 14.5))
                                .foregroundStyle(Florin.text)
                            Text(t("v2.add.upcomingHint", "Jusqu'à ce que la banque l'enregistre"))
                                .font(.system(size: 12))
                                .foregroundStyle(Florin.text3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .tint(Florin.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Hairline()
            }

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

        if let editing {
            Task {
                await onPatch(
                    TxPatch(
                        categoryId: .some(categoryId.isEmpty ? nil : categoryId),
                        payee: payee.trimmingCharacters(in: .whitespaces),
                        memo: .some(trimmedMemo.isEmpty ? nil : trimmedMemo),
                        amount: isExpense ? -abs(magnitude) : abs(magnitude),
                        occurredAt: ISO8601DateFormatter.florinNoFraction
                            .string(from: noonOn(date)),
                        // Sent only when it moved, and only where it means
                        // something: see `offersAccount` and `offersUpcoming`.
                        accountId: offersAccount && accountId != editing.accountId
                            ? accountId : nil,
                        upcoming: offersUpcoming && upcoming != editing.isPending
                            ? upcoming : nil
                    )
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                saving = false
                dismiss()
            }
            return
        }

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
                        categoryId: categoryId.isEmpty ? nil : categoryId,
                        upcoming: upcoming && offersUpcoming
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

    /// An amount the way the reader's locale writes it, and no grouping — a
    /// space between the thousands is a character the decimal pad cannot type.
    private static func plain(_ value: Double, locale: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: locale)
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
