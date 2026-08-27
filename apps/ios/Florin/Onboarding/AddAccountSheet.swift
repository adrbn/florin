import SwiftUI

/// Creating an account by hand.
///
/// The dashboard's empty state offered "ajouter un compte à la main" and opened
/// the *transaction* sheet — a label and an action that had nothing to do with
/// each other. There was no add-account screen at all; this is it, and it asks
/// the same three things the onboarding does, because they are the same three
/// things.
struct AddAccountSheet: View {
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
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
                        Text(Strings.device("v2.account.manualHint", "Un compte que vous tenez vous-même."))
                            .font(.system(size: 14))
                            .foregroundStyle(Florin.text2)
                            .padding(.top, 8)

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
        .alert(
            "Nouveau compte",
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
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
