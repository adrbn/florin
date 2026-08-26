import AuthenticationServices
import Foundation

/// Connecting a bank, from the phone.
///
/// The desktop build sends the user to their bank in the system browser and
/// catches the redirect on a local HTTPS server it runs on port 3847. A phone
/// cannot run a server, and would not want to: `ASWebAuthenticationSession`
/// exists for exactly this shape — it presents the bank's own sign-in in a
/// sandboxed browser that shares no cookies with the app, and hands the
/// redirect straight back.
@MainActor
final class BankingFlow: NSObject, ObservableObject {
    @Published private(set) var busy = false
    @Published var failure: String?

    /// Where the bank sends the user back. This exact string has to be
    /// registered as a redirect URI in the Enable Banking console, and the
    /// scheme has to be declared in Info.plist — the two must agree or the
    /// bank refuses the request before the user ever sees a sign-in page.
    static let redirectURL = "florin://banking/callback"
    private static let scheme = "florin"

    /*
     * The nonce stays in memory, and is never transmitted.
     *
     * The server builds an HMAC-signed state because it is stateless: the
     * request that starts the flow and the one that finishes it are different
     * processes, so the state has to carry its own proof. Here one object owns
     * both ends of the flow, so it can simply remember what it sent and
     * compare. Nothing to sign, nothing to leak, and a callback that did not
     * come from the auth we started cannot match.
     */
    private var pendingNonce: String?
    private var session: ASWebAuthenticationSession?

    // MARK: - Configuration

    /// The Enable Banking application id, kept beside the ledger.
    static func appId(_ store: LocalStore) -> String? {
        guard let value = try? store.database.scalar(
            "SELECT value FROM settings WHERE key = 'eb_app_id'"
        ), let text = value.string, !text.isEmpty else { return nil }
        return text
    }

    static func setAppId(_ store: LocalStore, _ value: String) throws {
        try store.database.run(
            "INSERT OR REPLACE INTO settings (key, value) VALUES ('eb_app_id', ?)",
            [.text(value.trimmingCharacters(in: .whitespacesAndNewlines))]
        )
        // The cached JWT carries the old id in `kid`; keeping it would sign
        // requests as an application that no longer matches.
        EnableBanking.forgetToken()
    }

    static func config(_ store: LocalStore) throws -> EnableBanking.Config {
        guard let appId = appId(store) else { throw EnableBanking.Failure.notConfigured }
        return EnableBanking.Config(appId: appId, redirectURL: redirectURL)
    }

    static var isConfigured: Bool {
        guard let store = LocalStore.shared else { return false }
        return appId(store) != nil && BankingKey.exists
    }

    // MARK: - Listing banks

    func banks(country: String) async -> [Aspsp] {
        guard let store = LocalStore.shared else { return [] }
        do {
            let config = try Self.config(store)
            return try await EnableBanking.aspsps(config, country: country).aspsps
        } catch {
            failure = error.localizedDescription
            return []
        }
    }

    // MARK: - Connecting

    /// Send the user to their bank, then turn the code they come back with
    /// into a session and a set of accounts.
    func connect(to aspsp: Aspsp) async {
        guard let store = LocalStore.shared else { return }
        busy = true
        defer { busy = false }

        do {
            let config = try Self.config(store)
            let nonce = UUID().uuidString
            pendingNonce = nonce

            // Ninety days is Enable Banking's usual ceiling for personal
            // consent; asking for more is refused outright by some banks.
            let validUntil = Calendar(identifier: .gregorian)
                .date(byAdding: .day, value: 90, to: Date()) ?? Date()

            let start = try await EnableBanking.startAuth(
                config, aspsp: aspsp, state: nonce, validUntil: validUntil
            )
            guard let authURL = URL(string: start.url) else { throw EnableBanking.Failure.malformed }

            let callback = try await present(authURL)
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let returned = items.first { $0.name == "state" }?.value
            guard let code = items.first(where: { $0.name == "code" })?.value else {
                // The bank says no by sending an error back, not by failing to
                // redirect — surfacing its own words beats a generic failure.
                let message = items.first { $0.name == "error" }?.value
                throw EnableBanking.Failure.http(0, message ?? "")
            }
            guard returned == nonce else { throw EnableBanking.Failure.malformed }
            pendingNonce = nil

            let session = try await EnableBanking.createSession(config, code: code)
            try save(session, aspsp: aspsp, store: store)
            try await BankingSync.run(store: store, config: config)
        } catch {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
            failure = error.localizedDescription
        }
    }

    private func present(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: Self.scheme
            ) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: error ?? EnableBanking.Failure.malformed)
                }
            }
            session.presentationContextProvider = self
            /*
             * A private session, deliberately.
             *
             * Sharing Safari's cookies would let a bank recognise a session the
             * user opened for something else, and would leave this one behind
             * afterwards. Bank consent should start and end here.
             */
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            session.start()
        }
    }

    private func save(_ session: SessionResponse, aspsp: Aspsp, store: LocalStore) throws {
        guard let sessionId = session.sessionId else { throw EnableBanking.Failure.malformed }
        try store.database.run(
            """
            INSERT OR REPLACE INTO bank_connections
                (id, provider, session_id, aspsp_name, aspsp_country, status, valid_until)
            VALUES (?, 'enable_banking', ?, ?, ?, 'active', ?)
            """,
            [
                .text(UUID().uuidString), .text(sessionId),
                .text(aspsp.name), .text(aspsp.country),
                .text(session.accessValidUntil ?? ""),
            ]
        )
    }
}

extension BankingFlow: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}
