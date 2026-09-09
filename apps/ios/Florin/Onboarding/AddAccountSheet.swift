import SwiftUI

/// Adding an account — from a bank, or by hand.
///
/// The dashboard's empty state offered "ajouter un compte à la main" and opened
/// the *transaction* sheet — a label and an action that had nothing to do with
/// each other. There was no add-account screen at all; this is it, and it asks
/// the same three things the onboarding does, because they are the same three
/// things.
///
/// It leads with the bank, because that was the second half of the same bug.
/// The "+" on Comptes only ever made an account by hand, and the only route to
/// a synced one was Réglages > Banque — a place nobody looks when the thing
/// they want is spelled "ajouter un compte", and one the empty state stops
/// offering the moment a first account exists. So the person with one account
/// and a bank to connect had to be told where to go. The manual form is still
/// right there underneath, unchanged and one scroll away, because it is the
/// route taken most often.
struct AddAccountSheet: View {
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    /// Bank sync writes into the device ledger; with a server the accounts come
    /// from there, so the route is hidden rather than offered and refused.
    @AppStorage("florin.dataSource") private var sourceRaw = ""
    @State private var connectingBank = false
    @State private var name = ""
    @State private var kind = AccountKind.checking
    @State private var balanceText = ""
    @State private var failure: String?
    @FocusState private var focus: Field?

    private enum Field { case name, balance }

    var body: some View {
        NavigationStack {
            ZStack {
                Backdrop(tint: TabRoute.accounts.tint).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        if sourceRaw != DataSource.server.rawValue {
                            bankRoute
                            manualHeading
                        } else {
                            Text(Strings.device("v2.account.manualHint", "Un compte que vous tenez vous-même."))
                                .font(.system(size: 14))
                                .foregroundStyle(Florin.text2)
                                .padding(.top, 8)
                        }

                        TextField("Compte courant", text: $name)
                            .font(.system(size: 17, weight: .medium))
                            .multilineTextAlignment(.center)
                            .focused($focus, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focus = .balance }
                            .padding(.vertical, 15)
                            .padding(.horizontal, 18)
                            .florinGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        HStack(spacing: 8) {
                            ForEach(AccountKind.allCases, id: \.self) { option in
                                let picked = option == kind
                                Button {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    kind = option
                                } label: {
                                    VStack(spacing: 5) {
                                        Text(option.emoji).font(.system(size: 19))
                                        Text(option.label)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(picked ? Florin.text : Florin.text3)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(picked ? Florin.accent.opacity(0.22) : .clear)
                                    )
                                    .florinGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        VStack(spacing: 4) {
                            Text(
                                kind == .loan
                                    ? Strings.device("v2.account.loanHint", "Combien reste-t-il à rembourser ?")
                                    : Strings.device("v2.account.balanceQuestion", "Combien y a-t-il dessus aujourd'hui ?")
                            )
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Florin.text3)

                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                TextField("0", text: $balanceText)
                                    .font(.system(size: 40, weight: .light))
                                    .monospacedDigit()
                                    .multilineTextAlignment(.center)
                                    .keyboardType(.numbersAndPunctuation)
                                    .focused($focus, equals: .balance)
                                    .fixedSize()
                                Text("€")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Florin.text3)
                            }
                        }
                        .padding(.top, 6)

                        Button(action: save) {
                            Text(Strings.device("v2.account.addAction", "Ajouter le compte"))
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(Florin.accent, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, Florin.gutter)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Nouveau compte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        /*
         * A cover, and it closes this sheet behind it.
         *
         * Connecting a bank ends with accounts that already exist, so returning
         * to a half-filled "nouveau compte" form would be asking the same
         * question twice.
         */
        .fullScreenCover(isPresented: $connectingBank) {
            BankingSettings(onConnected: {
                connectingBank = false
                onSaved()
                dismiss()
            })
        }
        .alert(
            "Nouveau compte",
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    /// The bank, offered as the first answer rather than a setting to go find.
    private var bankRoute: some View {
        Button { connectingBank = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "building.columns")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Florin.accent)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Strings.device("v2.empty.bankTitle", "Connecter ma banque"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Florin.text)
                    Text(Strings.device(
                        "v2.empty.bankBody",
                        "Comptes, soldes et opérations arrivent tout seuls. Environ deux minutes, une seule fois."
                    ))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Florin.text2)
                    .lineSpacing(1.5)
                    .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Florin.text3)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .florinGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    /// Two routes need a seam, or the form below reads as part of the card
    /// above it — as though naming an account were step two of connecting a
    /// bank.
    private var manualHeading: some View {
        // Not `Hairline`, which carries a leading gutter for list rows and
        // would draw the two halves of the seam at different lengths.
        HStack(spacing: 10) {
            rule
            Text(Strings.device("v2.account.orByHand", "ou à la main"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Florin.text3)
                .fixedSize()
            rule
        }
        .padding(.top, 2)
    }

    private var rule: some View {
        Rectangle().fill(Florin.text.opacity(0.09)).frame(height: 1)
    }

    private func save() {
        focus = nil
        do {
            try LocalOnboarding.createAccount(
                name: name.trimmingCharacters(in: .whitespaces),
                kind: kind,
                balance: OnboardingFlow.parse(balanceText)
            )
            onSaved()
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}
