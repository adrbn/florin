import SwiftUI

/*
 * The four numbers on the contract, and the category that pays it.
 *
 * A loan's remaining debt cannot be recovered from its repayments: knowing that
 * 135,91 € left every month says nothing about how much was borrowed, at what
 * rate, or over how long — and without those the only figure available is the
 * total handed over, which is what the app used to show and is very nearly the
 * opposite of what is owed.
 *
 * They came from a server until now, which is a strange thing to require of an
 * app whose whole point is holding its own ledger. They are on the loan's own
 * screen instead, four fields off a paper contract, plus the category whose
 * transactions are the instalments — the link that lets filing one move the
 * debt.
 */
struct LoanSettingsSheet: View {
    let account: Account
    let t: Strings
    let locale: String
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var principal = ""
    @State private var rate = ""
    @State private var months = ""
    @State private var payment = ""
    @State private var categoryId: String?
    @State private var categories: [Category] = []
    @State private var saving = false
    @FocusState private var focused: Field?

    private enum Field { case principal, rate, months, payment }

    var body: some View {
        ZStack {
            Backdrop(tint: Florin.sheetTint, floor: true).ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 18) {
                        preview

                        VStack(spacing: 0) {
                            field(t("v2.loan.principal", "Capital emprunté"),
                                  "10 000", $principal, .principal, .decimalPad)
                            Hairline()
                            field(t("v2.loan.rate", "Taux annuel"),
                                  "3,9 %", $rate, .rate, .decimalPad)
                            Hairline()
                            field(t("v2.loan.term", "Durée en mois"),
                                  "84", $months, .months, .numberPad)
                            Hairline()
                            field(t("v2.loan.payment", "Mensualité"),
                                  "135,91", $payment, .payment, .decimalPad)
                        }
                        .florinSurface()

                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow(text: t("v2.loan.category", "Catégorie des mensualités"))
                            Menu {
                                Button(t("v2.loan.noCategory", "Aucune")) { categoryId = nil }
                                ForEach(categories) { category in
                                    Button(category.name) { categoryId = category.id }
                                }
                            } label: {
                                HStack {
                                    Text(categories.first { $0.id == categoryId }?.name
                                         ?? t("v2.loan.noCategory", "Aucune"))
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(Florin.text)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Florin.text3)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 13)
                                .florinGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            Text(t(
                                "v2.loan.categoryHint",
                                "Classer une opération ici la retire du capital restant dû."
                            ))
                            .font(.system(size: 12))
                            .foregroundStyle(Florin.text3)
                        }
                    }
                    .padding(.horizontal, Florin.gutter)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)

                Button { save() } label: {
                    HStack(spacing: 8) {
                        if saving { ProgressView().tint(.black) }
                        Text(t("v2.common.save", "Enregistrer"))
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Florin.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(saving)
                .padding(.horizontal, Florin.gutter)
                .padding(.bottom, 12)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
        .preferredColorScheme(.dark)
        .task { load() }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Florin.text2)
                    .frame(width: 30, height: 30)
                    .florinGlass(in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            Spacer()
            Text(t("v2.loan.title", "Votre prêt"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Florin.text)
            Spacer()
            Color.clear.frame(width: 30, height: 30)
        }
        .padding(.horizontal, Florin.gutter)
        // Clear of the drag indicator, which sits in the first twenty points
        // and left the title looking pinned to the edge of the sheet.
        .padding(.top, 26)
        .padding(.bottom, 12)
    }

    /*
     * The answer, before it is saved.
     *
     * Four numbers off a contract produce a fifth that the person can check
     * against their bank's own statement — which is the only way to know the
     * rate was entered as 3,9 and not 0,039, or the term in months and not
     * years. Wrong inputs make a plausible figure; a wrong figure next to a
     * statement does not survive.
     */
    @ViewBuilder
    private var preview: some View {
        let liability = computed
        VStack(spacing: 3) {
            Text(t("v2.loan.remaining", "Capital restant dû"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Florin.text3)
            if let liability {
                AmountText(
                    value: liability.remainingDebt, locale: locale, currency: "EUR",
                    decimals: false, size: 30, weight: .semibold
                )
                Text(t(
                    "v2.loan.afterPayments", "après {count} mensualités",
                    ["count": paymentsMade]
                ))
                .font(.system(size: 12))
                .foregroundStyle(Florin.text2)
            } else {
                Text("—")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Florin.text3)
            }
        }
        .padding(.top, 4)
    }

    private var paymentsMade: Int {
        guard let store = LocalStore.shared else { return 0 }
        return ((try? store.database.scalar(
            """
            SELECT count(*) FROM transactions
            WHERE account_id = ? AND transfer_pair_id IS NOT NULL AND deleted_at IS NULL
            """,
            [.text(account.id)]
        )?.int) as? Int ?? 0) ?? 0
    }

    private var computed: LocalLoan.Liability? {
        guard let p = LocalImport.number(principal), p > 0,
              let m = LocalImport.number(payment), m > 0
        else { return nil }
        return LocalLoan.liability(
            principal: p,
            // Entered the way it is written on the contract — 3,9 — and stored
            // the way the arithmetic wants it.
            annualRate: (LocalImport.number(rate) ?? 0) / 100,
            termMonths: Int(months) ?? 0,
            monthlyPayment: m,
            paymentsMade: paymentsMade
        )
    }

    private func field(
        _ label: String, _ placeholder: String, _ text: Binding<String>,
        _ which: Field, _ keyboard: UIKeyboardType
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Florin.text)
            Spacer(minLength: 8)
            TextField(placeholder, text: text)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Florin.text)
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboard)
                .focused($focused, equals: which)
                .frame(maxWidth: 150)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    private func load() {
        guard let store = LocalStore.shared else { return }
        categories = (try? LocalQueries.readCategories(store.database)) ?? []
        if let row = try? store.database.query(
            """
            SELECT loan_original_principal, loan_interest_rate, loan_term_months,
                   loan_monthly_payment
            FROM accounts WHERE id = ?
            """,
            [.text(account.id)]
        ).first {
            if let v = row.double("loan_original_principal"), v > 0 { principal = trimmed(v) }
            if let v = row.double("loan_interest_rate"), v > 0 { rate = trimmed(v * 100) }
            if let v = row.int("loan_term_months"), v > 0 { months = String(v) }
            if let v = row.double("loan_monthly_payment"), v > 0 { payment = trimmed(v) }
        }
        categoryId = try? store.database.scalar(
            "SELECT id FROM categories WHERE linked_loan_account_id = ? LIMIT 1",
            [.text(account.id)]
        )?.string
    }

    private func trimmed(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }

    private func save() {
        guard let store = LocalStore.shared else { return }
        saving = true
        do {
            try store.database.transaction {
                try store.database.run(
                    """
                    UPDATE accounts
                    SET loan_original_principal = ?, loan_interest_rate = ?,
                        loan_term_months = ?, loan_monthly_payment = ?,
                        updated_at = datetime('now')
                    WHERE id = ?
                    """,
                    [
                        (LocalImport.number(principal)).map { SQLiteValue.real($0) } ?? .null,
                        (LocalImport.number(rate)).map { SQLiteValue.real($0 / 100) } ?? .null,
                        Int(months).map { SQLiteValue.integer(Int64($0)) } ?? .null,
                        (LocalImport.number(payment)).map { SQLiteValue.real($0) } ?? .null,
                        .text(account.id),
                    ]
                )
                // One category per loan: clear whatever pointed here before, so
                // switching does not leave two.
                try store.database.run(
                    "UPDATE categories SET linked_loan_account_id = NULL WHERE linked_loan_account_id = ?",
                    [.text(account.id)]
                )
                if let categoryId {
                    try store.database.run(
                        "UPDATE categories SET linked_loan_account_id = ? WHERE id = ?",
                        [.text(account.id), .text(categoryId)]
                    )
                }
            }
            // Instalments already filed get their counterpart now rather than
            // at the next launch.
            _ = try? LocalLedger.reconcileLoanMirrors(store: store)
        } catch {
            saving = false
            return
        }
        Task {
            await onSaved()
            saving = false
            dismiss()
        }
    }
}
