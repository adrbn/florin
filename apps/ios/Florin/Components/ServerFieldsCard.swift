import SwiftUI

/// The address, the token, and a way to check both — in the app's own clothes.
///
/// A sibling of `ServerFields`, which renders the same three things as `Form`
/// sections for the places that still use one. The fields, the probe and every
/// word of the failure messages are identical; only the surface differs.
struct ServerFieldsCard: View {
    @Binding var host: String
    @Binding var token: String
    @Binding var status: ServerStatus

    @FocusState private var focus: Field?

    private enum Field { case host, token }

    private var resolved: URL? { ServerStore.normalise(host) }

    var body: some View {
        VStack(spacing: 14) {
            field(title: "Adresse") {
                TextField(ServerStore.suggestedHost, text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($focus, equals: .host)
                    .submitLabel(.next)
                    .onSubmit { focus = .token }
                    .onChange(of: host) { _, _ in status = .unknown }
            }

            // The single most useful line on the screen: whatever the rules
            // decided, here is the exact URL that will be called.
            Group {
                if let resolved {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 10))
                        Text(resolved.absoluteString).monospaced()
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Florin.accent)
                } else {
                    Text("Par exemple 192.168.1.10:3000, florin.local, ou mon-serveur.ts.net:8443. Le port et le http:// sont facultatifs.")
                        .font(.system(size: 12))
                        .foregroundStyle(Florin.text3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 4)

            field(title: "Jeton d'API") {
                SecureField("Laisser vide pour l'app de bureau", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .token)
                    .submitLabel(.go)
                    .onChange(of: token) { _, _ in status = .unknown }
            }

            // Confirms *which* token is stored without revealing it — the
            // difference between "I pasted nothing" and "I pasted the wrong
            // one" is otherwise invisible.
            if let stored = FlorinAuth.token, !stored.isEmpty {
                Text("Enregistré : " + FlorinAuth.masked(stored))
                    .font(.system(size: 11.5))
                    .monospaced()
                    .foregroundStyle(Florin.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            Divider().overlay(Florin.text3.opacity(0.2))

            Button {
                Task { await test() }
            } label: {
                HStack(spacing: 8) {
                    if status == .checking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "bolt.horizontal")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text("Tester la connexion")
                        .font(.system(size: 14.5, weight: .medium))
                }
                .foregroundStyle(Florin.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .florinGlass(in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(resolved == nil || status == .checking)
            .opacity(resolved == nil ? 0.4 : 1)

            if status != .unknown, status != .checking {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(tone)
                    Text(message)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Florin.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(18)
        .florinSurface()
    }

    private func field<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: title)
            content()
                .font(.system(size: 16))
                .foregroundStyle(Florin.text)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Florin.surface2)
                )
        }
    }

    private func test() async {
        guard let resolved else { return }
        focus = nil
        FlorinAuth.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        status = .checking
        status = await ServerProbe.check(resolved)
    }

    private var symbol: String {
        switch status {
        case .ready: "checkmark.circle.fill"
        case .unknown, .checking: "circle"
        default: "exclamationmark.triangle.fill"
        }
    }

    private var tone: Color {
        switch status {
        case .ready: Florin.positive
        case .unknown, .checking: Florin.text3
        default: Florin.negative
        }
    }

    /// Every failure names its own fix. Same words as the Form version.
    private var message: String {
        switch status {
        case .unknown, .checking:
            ""
        case .unreachable(let host):
            "\(host) ne répond pas. Vérifiez l'adresse et le port, et que vous êtes bien sur le même réseau — ou sur le VPN si le serveur est derrière."
        case .notFlorin:
            "Quelque chose répond à cette adresse, mais ce n'est pas un Florin."
        case .tooOld:
            "Florin répond, mais cette version ne connaît pas encore l'API de l'app. Il faut déployer une version à jour sur le serveur."
        case .unauthorized:
            "Florin est à jour mais refuse ce jeton. Vérifiez FLORIN_API_TOKEN côté serveur."
        case .ready:
            "Connecté."
        }
    }
}
