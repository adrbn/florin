import SwiftUI

/// Address and token, with a test that says what is actually wrong.
///
/// Shared by first-run setup and Settings so there is one place that knows how
/// to explain a failure. The three questions this answers, which the old single
/// field did not: do I type the port, do I type http or https, and — when it
/// still does not work — *why*.
struct ServerFields: View {
    @Binding var host: String
    @Binding var token: String
    @Binding var status: ServerStatus

    @FocusState private var focus: Field?

    private enum Field { case host, token }

    private var resolved: URL? { ServerStore.normalise(host) }

    var body: some View {
        Section {
            TextField(ServerStore.suggestedHost, text: $host)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .focused($focus, equals: .host)
                .submitLabel(.next)
                .onSubmit { focus = .token }
                .onChange(of: host) { _, _ in status = .unknown }
        } header: {
            Text("Adresse")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let resolved {
                    // The single most useful line on the screen: whatever the
                    // rules decided, here is the exact URL that will be called.
                    Label {
                        Text(resolved.absoluteString).monospaced()
                    } icon: {
                        Image(systemName: "arrow.turn.down.right")
                    }
                    .font(.system(size: 12))
                } else {
                    Text("Par exemple 192.168.1.10:3000, florin.local, ou mon-serveur.ts.net:8443.")
                }
                Text(
                    "Le port est facultatif, et http:// ou https:// aussi — Florin les déduit et te montre ci-dessus l'adresse exacte qu'il appellera."
                )
            }
        }

        Section {
            SecureField("Jeton d'API", text: $token)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .token)
                .submitLabel(.go)
                .onChange(of: token) { _, _ in status = .unknown }
        } header: {
            Text("Jeton")
        } footer: {
            Text(
                "Seulement pour un Florin web : la valeur de FLORIN_API_TOKEN sur ton serveur. L'app de bureau n'en demande pas — laisse vide."
            )
        }

        Section {
            Button {
                Task { await test() }
            } label: {
                HStack {
                    Text("Tester la connexion")
                    if status == .checking {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(resolved == nil || status == .checking)

            if status != .unknown, status != .checking {
                Label {
                    Text(message).font(.system(size: 13))
                } icon: {
                    Image(systemName: symbol).foregroundStyle(tone)
                }
            }
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
        case .ready: return "checkmark.circle.fill"
        case .unknown, .checking: return "circle"
        default: return "exclamationmark.triangle.fill"
        }
    }

    private var tone: Color {
        switch status {
        case .ready: return Florin.positive
        case .unknown, .checking: return Florin.text3
        default: return Florin.negative
        }
    }

    /// Every failure names its own fix.
    private var message: String {
        switch status {
        case .unknown, .checking:
            return ""
        case .unreachable(let host):
            return "\(host) ne répond pas. Vérifie l'adresse et le port, et que tu es bien sur le même réseau — ou sur le VPN si le serveur est derrière."
        case .notFlorin:
            return "Quelque chose répond à cette adresse, mais ce n'est pas un Florin."
        case .tooOld:
            return "Florin répond, mais cette version ne connaît pas encore l'API de l'app. Il faut déployer une version à jour sur le serveur."
        case .unauthorized:
            return "Florin est à jour mais refuse ce jeton. Vérifie FLORIN_API_TOKEN côté serveur."
        case .ready:
            return "Connecté."
        }
    }
}
