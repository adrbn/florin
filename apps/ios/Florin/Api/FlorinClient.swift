import Foundation

enum FlorinError: LocalizedError {
    case badStatus(Int)
    case unreachable(String)
    case rejected(String)

    var errorDescription: String? {
        switch self {
        /*
         * Name the fix, not the status code.
         *
         * "Le serveur a répondu 404" is true and useless: the two codes this
         * app actually meets in the wild each have one cause and one remedy —
         * a server predating the app's API, or a token it will not accept.
         */
        case .badStatus(404):
            return "Ce serveur ne connaît pas l'API de l'app. Il faut y déployer une version à jour de Florin."
        case .badStatus(401), .badStatus(403):
            return "Le serveur refuse le jeton d'API. Vérifie-le dans Réglages."
        case .badStatus(let code): return "Le serveur a répondu \(code)."
        case .unreachable(let host): return "\(host) ne répond pas."
        case .rejected(let message): return message
        }
    }
}

/// Talks to the Florin server's read-only v2 feed.
struct FlorinClient: Sendable {
    let base: URL

    private var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        // A self-hosted box on the LAN should fail fast rather than spin: the
        // user is standing in front of it and knows whether it is on.
        config.timeoutIntervalForRequest = 12
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    private func endpoint(_ path: String) throws -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.path = path
        guard let url = components?.url else { throw FlorinError.unreachable(base.host ?? "?") }
        return url
    }

    func add(_ tx: NewTransaction) async throws {
        var request = FlorinAuth.request(try endpoint("/api/v2/transactions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(tx)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FlorinError.badStatus(0) }
        guard (200..<300).contains(http.statusCode) else {
            // The route reports validation failures as {"error": "..."}; surface
            // that rather than a bare status the user cannot act on.
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw message.map { FlorinError.rejected($0) } ?? FlorinError.badStatus(http.statusCode)
        }
    }

    struct SyncResult: Decodable, Sendable {
        let ok: Bool
        let connectionsSynced: Int
        let accountsSynced: Int
        let transactionsInserted: Int
        let error: String?
    }

    func sync() async throws -> SyncResult {
        var request = FlorinAuth.request(try endpoint("/api/v2/sync"))
        request.httpMethod = "POST"
        // A PSD2 round trip walks every account at the bank; it is not a
        // 12-second operation.
        request.timeoutInterval = 90

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FlorinError.badStatus(0) }
        guard (200..<300).contains(http.statusCode) else { throw FlorinError.badStatus(http.statusCode) }
        let result = try JSONDecoder().decode(SyncResult.self, from: data)
        if let message = result.error, !result.ok { throw FlorinError.rejected(message) }
        return result
    }

    func overview() async throws -> Overview {
        // `base` points at the v2 page (…/m); the feed sits beside it.
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.path = "/api/v2/overview"
        guard let url = components?.url else { throw FlorinError.unreachable(base.host ?? "?") }

        do {
            let (data, response) = try await session.data(for: FlorinAuth.request(url))
            guard let http = response as? HTTPURLResponse else { throw FlorinError.badStatus(0) }
            guard (200..<300).contains(http.statusCode) else { throw FlorinError.badStatus(http.statusCode) }
            return try JSONDecoder().decode(Overview.self, from: data)
        } catch let error as FlorinError {
            throw error
        } catch let error as DecodingError {
            throw error
        } catch {
            throw FlorinError.unreachable(base.host ?? "?")
        }
    }
}

@MainActor
final class OverviewModel: ObservableObject {
    enum State {
        case loading
        case loaded(Overview)
        case failed(String)
    }

    @Published private(set) var state: State = .loading

    /// The last successful payload, kept across a refresh so the add sheet and
    /// the toolbar do not blink out while the screen reloads.
    var overview: Overview? {
        if case .loaded(let data) = state { return data }
        return nil
    }

    private let client: FlorinClient
    /// Needed by pushed web screens hosted inside this tab's stack.
    let base: URL

    init(base: URL) {
        self.base = base
        client = FlorinClient(base: base)
    }

    /// Sync on every reopen, as asked — with a two-minute floor.
    ///
    /// Worth knowing what this trades away: PSD2 caps unattended pulls per
    /// consent (Enable Banking's limit is a handful a day), and the desktop
    /// scheduler deliberately waits six hours for that reason. The floor exists
    /// so app-switching a dozen times in a minute cannot burn the quota, but a
    /// day of normal use will now spend far more of it than before. If the bank
    /// starts refusing, this is the number to raise.
    static let autoSyncInterval: TimeInterval = 2 * 60

    @Published private(set) var syncing = false
    @Published var toast: ToastMessage?

    private var lastSyncAttempt: Date {
        get { Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "florin.lastSyncAttempt")) }
        set { UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: "florin.lastSyncAttempt") }
    }

    func add(_ tx: NewTransaction) async throws {
        try await client.add(tx)
        await load(showSpinner: false)
    }

    /// Called when the app comes to the foreground. Refreshes the figures every
    /// time — that is free — but only reaches out to the banks when the last
    /// attempt is stale.
    func onForeground() async {
        await load(showSpinner: overview == nil)
        if Date().timeIntervalSince(lastSyncAttempt) > Self.autoSyncInterval {
            // Announce only when it actually brought something back: a pill on
            // every single app open saying "à jour" is nagging, not informing.
            await sync(announce: false, announceOnlyIfNew: true)
        }
    }

    func sync(announce: Bool = true, announceOnlyIfNew: Bool = false) async {
        guard !syncing else { return }
        syncing = true
        // Stamp before the call, not after: a failing bank must not turn into a
        // retry on every single foreground.
        lastSyncAttempt = Date()
        do {
            let result = try await client.sync()
            await load(showSpinner: false)
            let inserted = result.transactionsInserted
            if announce || (announceOnlyIfNew && inserted > 0) {
                toast = ToastMessage(
                    text: inserted > 0
                        ? overview?.t(
                            "v2.overview.syncInserted", "{count} nouvelles opérations",
                            ["count": inserted]
                        ) ?? "+\(inserted)"
                        : overview?.t("v2.overview.synced", "À jour") ?? "À jour",
                    kind: inserted > 0 ? .success : .neutral
                )
            }
        } catch {
            /*
             * Pull-to-refresh runs inside a task SwiftUI cancels the moment the
             * gesture settles, so a perfectly normal refresh was ending in a
             * red pill reading "Annulé". A cancellation is not a failure the
             * user needs told about — the next foreground will sync anyway.
             */
            if announce, !isCancellation(error) {
                toast = ToastMessage(text: error.localizedDescription, kind: .failure)
            }
        }
        syncing = false
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    func load(showSpinner: Bool = true) async {
        if showSpinner, case .loaded = state {} else if showSpinner { state = .loading }
        do {
            let data = try await client.overview()
            state = .loaded(data)
        } catch {
            // Same reasoning as sync: a cancelled read is not an outage, and
            // replacing a loaded screen with "Florin est injoignable" because
            // the user let go of a pull is a lie.
            if !isCancellation(error) { state = .failed(error.localizedDescription) }
        }
    }
}
