import SwiftUI

/// Matching what the bank exposes against what is already here.
///
/// Shown once, when a bank is connected to a device that already holds
/// accounts — typically one seeded from a Florin server. The bank calls the
/// account "MR ROBINO ADRIEN" and the server calls it "CCP"; only the person
/// looking at both knows they are the same thing, so they are asked rather
/// than guessed at.
struct BankMappingSheet: View {
    @State var accounts: [DiscoveredAccount]
    let candidates: [MappingCandidate]
    let locale: String
    let currency: String
    let onConfirm: ([DiscoveredAccount]) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Backdrop(tint: TabRoute.accounts.tint).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        Text(Strings.device(
                            "v2.connect.mappingLead",
                            "Votre banque expose {count} comptes. Dites à Florin s'ils existent déjà ici, pour qu'il continue leur historique au lieu d'en créer un double.",
                            ["count": accounts.count]
                        ))
                            .font(.system(size: 14))
                            .foregroundStyle(Florin.text2)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, 6)
                            .padding(.top, 6)

                        ForEach($accounts) { $account in
                            card(for: $account)
                        }

                        Button {
                            onConfirm(accounts)
                        } label: {
                            Text(Strings.device("v2.common.continue", "Continuer"))
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(Florin.accent, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, Florin.gutter)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(Strings.device("v2.connect.mappingTitle", "Vos comptes"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.device("v2.common.cancel", "Annuler"), action: onCancel)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func card(for account: Binding<DiscoveredAccount>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.wrappedValue.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Florin.text)
                    Text(account.wrappedValue.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Florin.text3)
                        .monospaced()
                }
                Spacer(minLength: 0)
                AmountText(
                    value: account.wrappedValue.balance, locale: locale,
                    currency: currency, decimals: false, tone: .neutral, size: 15
                )
            }

            Hairline()

            choice(
                account: account,
                target: nil,
                title: Strings.device("v2.connect.mappingNew", "Nouveau compte"),
                detail: Strings.device(
                    "v2.connect.mappingNewDetail",
                    "Florin le crée à part."
                )
            )

            ForEach(candidates) { candidate in
                choice(
                    account: account,
                    target: candidate.id,
                    title: candidate.name,
                    detail: Strings.device(
                        "v2.connect.mappingLink",
                        "Rattacher — l'historique déjà là est conservé."
                    )
                )
            }
        }
        .padding(16)
        .florinSurface()
    }

    private func choice(
        account: Binding<DiscoveredAccount>,
        target: String?,
        title: String,
        detail: String
    ) -> some View {
        let picked = account.wrappedValue.target == target
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            account.wrappedValue.target = target
        } label: {
            HStack(spacing: 11) {
                Image(systemName: picked ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(picked ? Florin.accent : Florin.text3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: picked ? .semibold : .regular))
                        .foregroundStyle(Florin.text)
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Florin.text3)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
