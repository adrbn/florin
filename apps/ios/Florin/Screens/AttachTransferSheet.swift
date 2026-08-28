import SwiftUI

/// Where money went, when the bank only showed it leaving.
///
/// Only the current account is bank-synced. Money sent to a savings account is
/// therefore seen departing and never seen landing: the balance falls, nothing
/// rises, and the net worth reports a loss that never happened — a step the
/// patrimony curve then keeps for good.
///
/// The app cannot infer the destination; the bank's own label says "VIREMENT"
/// and nothing more. So it asks, once, naming the amount and the date so the
/// answer takes a second. Everything offered here is already excluded from
/// spending by the same heuristic that found it, so answering can only make
/// the ledger truer — never less.
struct AttachTransferSheet: View {
    let transaction: Transaction
    let accounts: [Account]
    let locale: String
    let currency: String
    let t: Strings
    let onAttach: (String) async -> Void
    let onSpending: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    private var candidates: [Account] {
        accounts.filter { $0.name != transaction.accountName }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.left.arrow.right.circle")
                            .font(.system(size: 30))
                            .foregroundStyle(Florin.accent)
                        AmountText(
                            value: transaction.amount, locale: locale, currency: currency,
                            decimals: true, signed: true, tone: .auto, size: 32, weight: .light
                        )
                        Text(
                            t(
                                "v2.attach.lead", "Sorti de {account} le {date}",
                                [
                                    "account": transaction.accountName ?? "—",
                                    "date": DayLabel.string(
                                        transaction.day, locale: locale, t: t
                                    ),
                                ]
                            )
                        )
                        .font(.system(size: 13.5))
                        .foregroundStyle(Florin.text2)
                        .multilineTextAlignment(.center)
                    }
                    .padding(.top, 6)

                    Text(t("v2.attach.question", "Où est allé cet argent ?"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Florin.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Florin.gutter)

                    RowGroup {
                        ForEach(Array(candidates.enumerated()), id: \.element.id) { index, account in
                            if index > 0 { Hairline() }
                            HStack(spacing: 12) {
                                Text(account.displayIcon ?? "🏦").font(.system(size: 19))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(account.name)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(Florin.text)
                                    if let institution = account.institution {
                                        Text(institution)
                                            .font(.system(size: 12))
                                            .foregroundStyle(Florin.text3)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Florin.text3)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard !working else { return }
                                working = true
                                UISelectionFeedbackGenerator().selectionChanged()
                                Task { await onAttach(account.id); dismiss() }
                            }
                        }
                    }
                    .padding(.horizontal, Florin.gutter)

                    /*
                     * The escape hatch matters as much as the list.
                     *
                     * Not every outgoing transfer is a movement between the
                     * user's own accounts — rent paid by standing order looks
                     * identical to the bank. Offering only accounts would push
                     * someone into a wrong answer, and a wrong pairing is worse
                     * than none: it invents money in an account that never got
                     * it.
                     */
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        onSpending()
                        dismiss()
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: "tag")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Florin.text2)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("v2.attach.spending", "C'était une dépense"))
                                    .font(.system(size: 14.5, weight: .medium))
                                    .foregroundStyle(Florin.text)
                                Text(
                                    t(
                                        "v2.attach.spendingHint",
                                        "Elle rejoint « À vérifier » pour être classée."
                                    )
                                )
                                .font(.system(size: 12))
                                .foregroundStyle(Florin.text2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .florinSurface()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Florin.gutter)
                    .padding(.bottom, 14)
                }
            }
            .background(Backdrop(tint: Florin.sheetTint, floor: true))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.later", "Plus tard")) { dismiss() }
                }
            }
        }
        .presentationDetents([.height(470), .large])
        .presentationDragIndicator(.visible)
    }
}
