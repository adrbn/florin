import SwiftUI

/// Where the user points the app at their own Florin.
///
/// It was a stock grey `Form` — system headers, system footers, system
/// separators — bolted onto an app that draws everything else itself. It is
/// the very first screen for anyone arriving with a server, and it looked like
/// a settings page from a different application. Same fields, same probe, same
/// wording; the app's own ground, glass and type.
struct SetupView: View {
    @EnvironmentObject private var server: ServerStore
    @Environment(\.dismiss) private var dismiss

    let isFirstRun: Bool
    /// The same preference RootView reads to decide which store to mount —
    /// writing it here is what lets this screen hand the app back to itself.
    @AppStorage("florin.dataSource") private var source = ""
    @State private var draft = ""
    @State private var token = ""
    @State private var status: ServerStatus = .unknown

    private var preview: URL? { ServerStore.normalise(draft) }

    var body: some View {
        ZStack {
            Backdrop(tint: TabRoute.accounts.tint).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    header

                    ServerFieldsCard(host: $draft, token: $token, status: $status)
                        .padding(.horizontal, Florin.gutter)

                    Button(action: save) {
                        Text(isFirstRun ? "Ouvrir Florin" : "Enregistrer")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Florin.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(preview == nil)
                    .opacity(preview == nil ? 0.4 : 1)
                    .padding(.horizontal, Florin.gutter)

                    /*
                     * A way out of the first run.
                     *
                     * The close button below is drawn only when this screen is
                     * pushed from settings; on a first run there was none, and
                     * the one remaining button stays disabled until an address
                     * parses. Anyone who picked "I already have a server" by
                     * mistake — or who reinstalled and landed here because the
                     * stored preference outlived the container — was left on a
                     * screen with no server, no way back and no way forward,
                     * and deleting the app was the only exit. The ledger lives
                     * on the phone in that mode, so this is also the button
                     * that reaches it.
                     */
                    if isFirstRun {
                        Button {
                            source = DataSource.device.rawValue
                        } label: {
                            Text(Strings.device("v2.setup.useDevice", "Utiliser cet appareil"))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Florin.accent)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 7) {
                        Image(systemName: "lock.fill").font(.system(size: 11, weight: .semibold))
                        Text(Strings.device("v2.setup.privacy", "Rien ne quitte votre réseau : l'app affiche votre propre serveur."))
                            .font(.system(size: 12.5))
                    }
                    .foregroundStyle(Florin.text3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 30)
                }
                .padding(.top, isFirstRun ? 40 : 18)
            }
            .scrollDismissesKeyboard(.interactively)

            if !isFirstRun {
                VStack {
                    HStack {
                        Spacer()
                        CircleButton(symbol: "xmark", size: 40) { dismiss() }
                            .padding(.trailing, Florin.gutter)
                            .padding(.top, 6)
                    }
                    Spacer()
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            draft = server.rawURL.isEmpty ? ServerStore.suggestedHost : server.rawURL
            token = server.apiToken
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "externaldrive.badge.wifi")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Florin.accent)
                .padding(.bottom, 2)

            Text(isFirstRun ? Strings.device("v2.setup.title", "Votre serveur Florin") : "Serveur")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Florin.text)

            Text(Strings.device("v2.setup.hostHint", "L'adresse de votre instance, sur votre réseau."))
                .font(.system(size: 14))
                .foregroundStyle(Florin.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
        }
    }

    private func save() {
        server.apply(draft)
        FlorinAuth.token = token.trimmingCharacters(in: .whitespaces)
        if !isFirstRun { dismiss() }
    }
}
