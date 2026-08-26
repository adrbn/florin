import AuthenticationServices
import Foundation
import OSLog

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
    /*
     * What the flow is doing, on screen.
     *
     * Tapping a bank did nothing at all: no page, no error, no log I could
     * reach — a physical device needs root to collect logs, so the usual way
     * of telling "the tap never landed" from "the request failed silently" was
     * closed. This puts that distinction where it can actually be read.
     */
    @Published private(set) var step: String?

    /*
     * Where the bank sends the user back.
     *
     * An https URL, not a custom scheme: Enable Banking's console rejects
     * anything else outright — "uses unsupported scheme" — so `florin://`
     * never had a chance, whatever Info.plist said.
     *
     * So it is a universal link. iOS checks once, at install, that this host
     * publishes an apple-app-site-association naming this app, and from then
     * on hands the URL to Florin instead of opening a browser. The file is
     * static and lives in `apps/site`; it is never in the critical path of a
     * sync.
     *
     * This host, the Associated Domains entitlement and the redirect URI
     * registered with Enable Banking all have to say the same thing. When they
     * disagree the bank refuses before showing a sign-in page, and its error
     * does not say which of the three is wrong.
     */
    /// `florin.pages.dev` was already taken globally; Cloudflare assigned this
    /// one. It is now part of the app's identity — changing it breaks universal
    /// links for every install that already exists, not just new ones.
    static let redirectHost = "florin-cpe.pages.dev"
    private static let redirectPath = "/banking/callback"
    static var redirectURL: String { "https://\(redirectHost)\(redirectPath)" }

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
    /// When the current attempt began, to tell a refusal from a decision.
    private var startedAt = Date()
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
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        try store.database.run(
            "INSERT OR REPLACE INTO settings (key, value) VALUES ('eb_app_id', ?)",
            [.text(trimmed)]
        )
        // Read it back. A write that silently does not stick is what put the
        // screen and the database out of step in the first place, and the cost
        // of noticing is one query.
        guard appId(store) == (trimmed.isEmpty ? nil : trimmed) else {
            throw EnableBanking.Failure.rejected(
                "L'identifiant n'a pas pu être enregistré sur cet appareil."
            )
        }
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
    private static let log = Logger(subsystem: "com.adrbn.florin", category: "banking-flow")

    func connect(to aspsp: Aspsp) async {
        // Loud on purpose: the failure that matters here is the one where
        // nothing at all happens, which leaves no error to read.
        Self.log.notice("connect tapped: \(aspsp.name, privacy: .public)")
        step = "1/4 · touche reçue"
        guard let store = LocalStore.shared else {
            failure = "Florin n'a pas pu ouvrir sa base sur cet appareil."
            return
        }
        busy = true
        defer { busy = false }

        do {
            let config = try Self.config(store)
            startedAt = Date()
            step = "2/4 · demande d'autorisation"
            let nonce = UUID().uuidString
            pendingNonce = nonce

            // Ninety days is Enable Banking's usual ceiling for personal
            // consent; asking for more is refused outright by some banks.
            let validUntil = Calendar(identifier: .gregorian)
                .date(byAdding: .day, value: 90, to: Date()) ?? Date()

            let start = try await EnableBanking.startAuth(
                config, aspsp: aspsp, state: nonce, validUntil: validUntil
            )
            Self.log.notice("auth url received, presenting")
            step = "3/4 · ouverture de la banque"
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

            step = "4/4 · récupération des comptes"
            let session = try await EnableBanking.createSession(config, code: code)
            try save(session, aspsp: aspsp, store: store)
            try await BankingSync.run(store: store, config: config)
            step = nil
        } catch {
            step = nil
            /*
             * A cancellation is only a cancellation if a person had time to
             * make one.
             *
             * iOS reports its own refusals as `.canceledLogin` too, and this
             * swallowed them: the associated domain was not configured, the
             * session was killed in under a second, and the code returned
             * quietly — leaving the step counter frozen at "3/4" with nothing
             * to read. The real error said exactly what was wrong and nobody
             * ever saw it.
             */
            let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
            if cancelled, Date().timeIntervalSince(startedAt) > 1.5 { return }
            failure = error.localizedDescription
        }
    }

    /// Opens the auth browser against a URL of our own, with no bank and no
    /// Enable Banking involved, so a failure to *present* can be told apart
    /// from a failure to authenticate. Debug builds only.
    func probePresentation() async {
        step = "test · ouverture"
        do {
            let url = URL(string: "https://\(Self.redirectHost)/")!
            _ = try await present(url)
            step = "test · revenu"
        } catch {
            step = nil
            failure = "test : \(error.localizedDescription)"
        }
    }

    private func present(_ url: URL) async throws -> URL {
        guard Self.currentAnchor() != nil else {
            throw EnableBanking.Failure.rejected(
                "Florin n'a pas trouvé de fenêtre pour afficher la page de la banque."
            )
        }
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .https(host: Self.redirectHost, path: Self.redirectPath)
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

            /*
             * `start()` returns a Bool, and ignoring it is a silent hang.
             *
             * When it refuses — most often because the associated domain has
             * not been verified on this device yet, so iOS will not accept an
             * https callback — the completion handler is never called and the
             * continuation is never resumed. The app simply stops, with no
             * error to show and nothing in the log. That is exactly what
             * tapping a bank did.
             */
            step = "3/4 · ouverture de la banque…"
            guard session.start() else {
                Self.log.error("ASWebAuthenticationSession refused to start")
                continuation.resume(throwing: EnableBanking.Failure.rejected(
                    """
                    iOS a refusé d'ouvrir la page de la banque. Le lien de                     redirection (\(Self.redirectHost)) n'est pas encore validé                     sur cet appareil — réessayez dans une minute, en gardant le                     téléphone connecté à Internet.
                    """
                ))
                return
            }
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
    /*
     * A window that is actually on screen.
     *
     * This used to fall back to `ASPresentationAnchor()` — a freshly made
     * UIWindow with no scene and no frame. iOS accepts it, `start()` returns
     * true, and then nothing happens: the sheet is presented onto a window
     * nobody can see, the completion handler is never called, and the flow
     * stops dead with no error. That is exactly what tapping a bank did after
     * reaching "3/4".
     *
     * So: the foreground-active scene first, and only then any window scene.
     * If there is genuinely nothing to present on, that is worth knowing, and
     * `connect` turns it into a message rather than a hang.
     */
    static func currentAnchor() -> ASPresentationAnchor? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return active?.keyWindow ?? active?.windows.first
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        Self.currentAnchor() ?? ASPresentationAnchor()
    }
}
