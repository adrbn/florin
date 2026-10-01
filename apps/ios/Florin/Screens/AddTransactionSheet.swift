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
    var onInstalments: (InstalmentPlan) async throws -> Void = { _ in }
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
    /*
     * Un achat payé en plusieurs fois.
     *
     * `1` veut dire « pas de partage », et c'est le seul état où le reste de
     * la sheet se comporte comme avant. La mensualité reste vide tant qu'on ne
     * la corrige pas : vide, elle vaut le prix divisé, et c'est le cas sans
     * frais. La saisir est ce qui fait apparaître ce que l'offre coûte.
     */
    @State private var instalmentCount = 1
    @State private var instalmentEach = ""
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
        onInstalments: @escaping (InstalmentPlan) async throws -> Void = { _ in },
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
        self.onInstalments = onInstalments
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

    /*
     * Le partage ne s'offre que là où les échéances peuvent s'éteindre.
     *
     * Ce sont des opérations à venir, donc les mêmes conditions : le grand
     * livre de l'appareil, un compte que la banque synchronise, une dépense.
     * Modifier une ligne existante ne la partage pas — ce serait en créer
     * d'autres derrière le dos de quelqu'un qui croyait corriger un montant.
     */
    private var offersInstalments: Bool { offersUpcoming && !isEditing && kind == .expense }

    /// Ce qui sera prélevé chaque mois : le prix divisé, ou la mensualité
    /// telle qu'elle est écrite sur l'offre quand on l'a saisie.
    private var instalmentAmounts: [Double] {
        guard instalmentCount > 1, magnitude > 0 else { return [] }
        let typed = Double(
            instalmentEach.replacingOccurrences(of: ",", with: ".")
                .replacingOccurrences(of: " ", with: "")
        )
        guard let each = typed, each > 0 else {
            return LocalInstalments.split(magnitude, over: instalmentCount)
        }
        return LocalInstalments.quoted(each, count: instalmentCount, total: magnitude)
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

            if offersInstalments {
                instalmentRow
                Hairline()
            }

            // Une échéance est déjà une opération à venir : le proposer une
            // seconde fois laisserait croire qu'on peut partager sans l'être.
            if offersUpcoming && instalmentCount == 1 {
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
                if offersInstalments, instalmentCount > 1, !instalmentAmounts.isEmpty {
                    try await onInstalments(
                        InstalmentPlan(
                            accountId: accountId,
                            payee: payee.trimmingCharacters(in: .whitespaces),
                            purchase: abs(magnitude),
                            instalments: instalmentAmounts,
                            first: noonOn(date),
                            memo: trimmedMemo.isEmpty ? nil : trimmedMemo,
                            categoryId: categoryId.isEmpty ? nil : categoryId
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

    // MARK: - En plusieurs fois

    /// Les échéanciers qu'on rencontre : quatre fois sans frais est la forme
    /// la plus courante des facilités proposées à la caisse, trois fois celle
    /// des cartes bancaires, six et dix celles des enseignes.
    private static let instalmentChoices = [2, 3, 4, 6, 10]

    /// Celui qu'on obtient sans rien choisir, parce que c'est celui qu'on
    /// rencontre le plus souvent.
    private static let defaultInstalmentCount = 4

    /*
     * Un interrupteur, et le choix seulement une fois qu'il est mis.
     *
     * Six capsules posées en permanence sous la date donnaient un écran qui
     * pose une question que personne ne se pose : la plupart des dépenses se
     * paient en une fois, et le partage doit se demander, pas s'afficher. Le
     * nombre de fois reste la seule source de vérité — un « 1 » veut dire
     * éteint — pour qu'un interrupteur et un échéancier ne puissent jamais se
     * contredire.
     */
    private var splitting: Binding<Bool> {
        Binding(
            get: { instalmentCount > 1 },
            set: { on in
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.snappy(duration: 0.2)) {
                    instalmentCount = on ? Self.defaultInstalmentCount : 1
                    instalmentEach = ""
                }
            }
        )
    }

    /*
     * Le nombre de fois, la mensualité, et ce que ça coûte vraiment.
     *
     * Les mêmes capsules que le choix dépense/entrée/virement, parce que c'est
     * la même sorte de décision : un petit nombre de possibilités qu'on veut
     * voir toutes à la fois, et non une liste déroulante système qui cache
     * cinq choix derrière un chevron et ne ressemble à rien d'autre ici.
     *
     * La mensualité reste vide tant qu'il n'y a pas de frais : c'est le cas
     * d'un « quatre fois sans frais », et un champ prérempli inviterait à
     * corriger un chiffre déjà juste. La saisir est ce qui fait apparaître le
     * coût réel.
     */
    private var instalmentRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: splitting) {
                HStack(spacing: 13) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Florin.accent.opacity(0.85))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("v2.add.instalments", "En plusieurs fois"))
                            .font(.system(size: 14.5))
                            .foregroundStyle(Florin.text)
                        Text(t("v2.add.instalmentsHint", "Une échéance par mois, en prévision"))
                            .font(.system(size: 12))
                            .foregroundStyle(Florin.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .tint(Florin.accent)

            if instalmentCount > 1 {
                HStack(spacing: 8) {
                    ForEach(Self.instalmentChoices, id: \.self) { count in
                        instalmentChip(count)
                    }
                }
            }

            // Pas avant qu'il y ait un prix : à zéro, le récapitulatif
            // annonçait « 0 × 0,00 € », ce qui est faux et ce qu'on voit
            // forcément puisque le partage se choisit avant de taper le
            // montant aussi souvent qu'après.
            if instalmentCount > 1, !instalmentAmounts.isEmpty {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Text(t("v2.add.instalmentsEach", "Mensualité"))
                            .font(.system(size: 14))
                            .foregroundStyle(Florin.text2)
                        Spacer(minLength: 8)
                        TextField(
                            Self.plain(instalmentAmounts.first ?? 0, locale: localeTag),
                            text: $instalmentEach
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: 110)
                    }
                    Hairline()
                    instalmentTotals
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func instalmentChip(_ count: Int) -> some View {
        let active = instalmentCount == count
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy(duration: 0.2)) {
                instalmentCount = count
                // Changer d'échéancier rend caduque une mensualité saisie pour
                // le précédent : la garder afficherait un coût qui n'est celui
                // d'aucune des deux offres.
                instalmentEach = ""
            }
        } label: {
            Text("\(count)×")
                .font(.system(size: 14.5, weight: active ? .semibold : .medium))
                .lineLimit(1)
                // Six capsules sur la largeur d'un iPhone mini laissent
                // quarante-six points chacune : « Non » y tient, mais de peu,
                // et une langue plus longue n'y tiendrait pas.
                .minimumScaleFactor(0.8)
                .foregroundStyle(active ? Florin.accent : Florin.text2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(active ? Florin.accent.opacity(0.16) : Color.clear, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        active ? Florin.accent.opacity(0.5) : Florin.text.opacity(0.10),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    /*
     * Deux lignes : ce qu'on rend, et ce que ça coûte.
     *
     * La seconde est la raison d'être de tout le reste. « 2 % de frais en
     * trois fois » n'est pas un crédit à 2 % : un tiers est rendu tout de
     * suite et les deux autres ne sont empruntés qu'un mois et deux mois, si
     * bien que le taux annuel équivalent tourne autour de vingt-cinq pour
     * cent — l'ordre de grandeur d'un découvert. Il est teinté comme une
     * dépense au-delà de dix pour cent, parce qu'à ce niveau ce n'est plus une
     * facilité mais un crédit, et que personne ne lit un chiffre gris.
     */
    @ViewBuilder
    private var instalmentTotals: some View {
        let amounts = instalmentAmounts
        let due = amounts.reduce(0, +)
        let fees = LocalInstalments.fees(purchase: magnitude, instalments: amounts)
        let rate = LocalInstalments.annualRate(purchase: magnitude, instalments: amounts)
        VStack(spacing: 7) {
            HStack {
                Text(Self.shape(amounts, locale: localeTag, currency: currency))
                    .foregroundStyle(Florin.text2)
                Spacer(minLength: 8)
                Text(Money.string(due, locale: localeTag, currency: currency))
                    .foregroundStyle(Florin.text)
                    .fontWeight(.medium)
            }
            HStack {
                Text(t("v2.add.instalmentsFees", "Frais"))
                    .foregroundStyle(Florin.text2)
                Spacer(minLength: 8)
                if fees > 0.004, let rate, rate > 0 {
                    Text(
                        "\(Money.string(fees, locale: localeTag, currency: currency))  ·  "
                            + t("v2.add.instalmentsPerYear", "{rate} par an",
                                ["rate": Money.percent(rate, locale: localeTag)])
                    )
                    .foregroundStyle(rate > 0.10 ? Florin.negative : Florin.text)
                    .fontWeight(.medium)
                } else {
                    Text(t("v2.add.instalmentsNoFees", "Sans frais"))
                        .foregroundStyle(Florin.positive)
                        .fontWeight(.medium)
                }
            }
        }
        .font(.system(size: 13))
    }

    /// L'échéancier tel qu'il sera écrit, groupes d'échéances égales compris.
    private static func shape(_ amounts: [Double], locale: String, currency: String) -> String {
        LocalInstalments.describe(amounts) {
            Money.string($0, locale: locale, currency: currency)
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
