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
    /// Taken when the form was opened from the welcome screen: the way back to
    /// it. RootView shows this form for as long as it was asked for, so
    /// switching the source alone left the same screen on display.
    var onUseDevice: (() -> Void)? = nil
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
                        Text(isFirstRun
                            ? Strings.device("v2.setup.open", "Ouvrir Florin")
                            : Strings.device("v2.common.save", "Enregistrer"))
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
                    /*
                     * A button, not a footnote.
                     *
                     * It was a line of small text under the disabled primary,
                     * and App Review — with no server, reasonably — did not
                     * find it and reported the app as unusable. It is the
                     * answer for everyone who has no server, so it is drawn
                     * like one.
                     */
                    if isFirstRun {
                        Button {
                            source = DataSource.device.rawValue
                            onUseDevice?()
                        } label: {
                            Text(Strings.device("v2.setup.noServer", "Je n'ai pas de serveur"))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Florin.text)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .florinGlass(in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, Florin.gutter)
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

            Text(isFirstRun
                ? Strings.device("v2.setup.title", "Votre serveur Florin")
                : Strings.device("v2.setup.server", "Serveur"))
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
