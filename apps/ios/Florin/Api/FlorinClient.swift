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
            return Strings.device(
                "v2.common.errorApiTooOld",
                "Ce serveur ne connaît pas l'API de l'app. Il faut y déployer une version à jour de Florin."
            )
        case .badStatus(401), .badStatus(403):
            return Strings.device(
                "v2.common.errorToken",
                "Le serveur refuse le jeton d'API. Vérifie-le dans Réglages."
            )
        case .badStatus(let code):
            return Strings.device("v2.common.errorStatus", "Le serveur a répondu {code}.", ["code": code])
        case .unreachable(let host):
            return Strings.device("v2.common.unreachable", "{host} ne répond pas.", ["host": host])
        case .rejected(let message): return message
        }
    }
}

/// Talks to the Florin server's read-only v2 feed — or to the device itself.
///
/// The client is the seam between the two. Everything above it takes a `base:
/// URL` and hands it around: the models, the screens, the sheets. Rather than
/// rewrite that whole chain to carry a source enum, a serverless install gets
/// a URL of its own — `florin-local://device` — and the client answers it from
/// the on-device ledger instead of the network.
///
/// The point is that nothing above this file can tell the difference, which is
/// the only way the port stays honest about looking identical: there is no
/// second set of screens to drift.
struct FlorinClient: Sendable {
    let base: URL

    /// The address of the ledger on this phone.
    static let localBase = URL(string: "florin-local://device")!

    var isLocal: Bool { base.scheme == "florin-local" }

    /// Carries the bearer token on the session rather than the request — see
    /// `FlorinAuth.session`.
    private var session: URLSession { FlorinAuth.session }

    private func endpoint(_ path: String) throws -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.path = path
        guard let url = components?.url else { throw FlorinError.unreachable(base.host ?? "?") }
        return url
    }

    /// The device's ledger, or a readable reason there is not one.
    func localStore() throws -> LocalStore {
        guard let store = LocalStore.shared else {
            throw FlorinError.rejected(
                Strings.device("v2.common.errorNoDatabase", "Florin n'a pas pu ouvrir sa base de données sur cet appareil.")
            )
        }
        return store
    }

    /// Recording a movement between two of the user's own accounts.
    func addTransfer(_ move: NewTransfer) async throws {
        if isLocal { return try LocalLedger.addTransfer(store: try localStore(), move) }
        var request = FlorinAuth.request(try endpoint("/api/v2/transfers"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(move)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FlorinError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    /// Writing the far end of a movement the bank only showed one side of.
    func attachTransfer(_ txId: String, to accountId: String) async throws {
        if isLocal {
            return try LocalLedger.attachTransfer(
                store: try localStore(), txId: txId, toAccountId: accountId
            )
        }
        var request = FlorinAuth.request(try endpoint("/api/v2/transfers/attach"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["transactionId": txId, "accountId": accountId]
        )
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FlorinError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    /// Movements seen leaving but never seen landing. Empty against a server,
    /// which owns every account it syncs and pairs them itself.
    func danglingTransfers() throws -> [Transaction] {
        guard isLocal else { return [] }
        return try LocalQueries.danglingTransfers(try localStore().database)
    }

    func add(_ tx: NewTransaction) async throws {
        if isLocal { return try LocalLedger.add(store: try localStore(), tx) }
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
        /*
         * On the device, syncing is talking to the bank — not to a URL.
         *
         * Pull-to-refresh went straight to POST /api/v2/sync on a base of
         * `florin-local://device`, which URLSession cannot open at all: the
         * gesture answered "URL non gérée". Everything else had been routed
         * through this seam and this one call was missed.
         */
        if isLocal {
            let store = try localStore()
            // A portfolio's price is the half a local ledger cannot know, so a
            // refresh has to go and get it — otherwise a PEA sits at whatever
            // it was worth the day it was imported, looking live.
            await LocalPricing.refresh(store: store)
            let config = try BankingFlow.config(store)
            let result = try await BankingSync.run(store: store, config: config)
            return SyncResult(
                ok: result.failures.isEmpty,
                connectionsSynced: result.accounts > 0 ? 1 : 0,
                accountsSynced: result.accounts,
                transactionsInserted: result.inserted,
                error: result.failures.first
            )
        }

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

    /// The cache key for this base URL's overview feed. Keyed by host so
    /// pointing the app at a different server does not show the previous one's
    /// figures.
    var overviewKey: String { "overview-\(base.host ?? "?")" }

    func overview() async throws -> Overview {
        if isLocal {
            guard let store = LocalStore.shared else {
                throw FlorinError.rejected(
                Strings.device("v2.common.errorNoDatabase", "Florin n'a pas pu ouvrir sa base de données sur cet appareil.")
            )
            }
            return try LocalQueries.overview(store: store, locale: Strings.preferredShortLocale)
        }

        // `base` points at the v2 page (…/m); the feed sits beside it.
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.path = "/api/v2/overview"
        guard let url = components?.url else { throw FlorinError.unreachable(base.host ?? "?") }

        do {
            let (data, response) = try await session.data(for: FlorinAuth.request(url))
            guard let http = response as? HTTPURLResponse else { throw FlorinError.badStatus(0) }
            guard (200..<300).contains(http.statusCode) else { throw FlorinError.badStatus(http.statusCode) }
            let decoded = try JSONDecoder().decode(Overview.self, from: data)
            SnapshotCache.write(data, for: overviewKey)
            return decoded
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
    /// When the figures on screen were fetched, if they came from the cache
    /// rather than the server. Nil means live.
    @Published private(set) var staleSince: Date?

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

    func addTransfer(_ move: NewTransfer) async throws {
        try await client.addTransfer(move)
        await load(showSpinner: false)
    }

    /// Movements seen leaving but never seen landing — the far account is not
    /// one the bank syncs, so nothing ever credited it.
    var dangling: [Transaction] { (try? client.danglingTransfers()) ?? [] }

    func attachTransfer(_ txId: String, to accountId: String) async throws {
        try await client.attachTransfer(txId, to: accountId)
        await load(showSpinner: false)
    }

    /// Called when the app comes to the foreground. Refreshes the figures every
    /// time — that is free — but only reaches out to the banks when the last
    /// attempt is stale.
    /// Leave the home screen the two figures it shows. Silent when there is no
    /// shared container, which is every install signed with a free Apple ID.
    private func publishSnapshot() {
        guard let data = overview else { return }
        WidgetSnapshot.write(
            WidgetSnapshot(
                netWorth: data.netWorth.net,
                leftToSpend: data.leftToSpend.leftToSpend,
                daysRemaining: data.leftToSpend.daysRemaining,
                dailyBudget: data.leftToSpend.dailyBudgetRemaining,
                dailySpent: data.leftToSpend.dailyAvgSpent,
                currency: data.currency,
                locale: data.localeTag,
                /*
                 * The app's default, not the absence of a preference.
                 *
                 * @AppStorage keeps its default in memory: until someone opens
                 * the picker, UserDefaults holds nothing at all. Passing that
                 * nothing straight through told the widget to follow the phone
                 * while the app it belongs to was showing dark — the mismatch
                 * this field exists to prevent, on precisely the installs that
                 * never touched the setting.
                 */
                appearance: UserDefaults.standard.string(forKey: "florin.appearance")
                    ?? Appearance.dark.rawValue,
                updatedAt: Date()
            )
        )
    }

    func onForeground() async {
        await load(showSpinner: overview == nil)
        publishSnapshot()
        if Date().timeIntervalSince(lastSyncAttempt) > Self.autoSyncInterval {
            // Announce only when it actually brought something back: a pill on
            // every single app open saying "à jour" is nagging, not informing.
            await sync(announce: false, announceOnlyIfNew: true)
        }
    }

    /*
     * Pull-to-refresh, where the gesture cannot cut the work short.
     *
     * `.refreshable` runs its body in a task SwiftUI cancels once it is done
     * with the gesture, and a bank sync is not a thing that should stop because
     * a finger lifted. It did: the catch below silences cancellation so the
     * screen would stop reporting "Annulé" on a normal pull — which hid the
     * fact that the sync had been abandoned somewhere in the middle. That is
     * why pulling felt so much faster than the sync button beside it, which
     * runs in a task of its own and always finishes.
     *
     * Starting the work unstructured breaks the parent-child link: cancelling
     * this refresh no longer reaches the sync, and awaiting its result keeps
     * the spinner honest about how long the bank actually takes.
     */
    func refresh() async {
        let work = Task { await sync() }
        _ = await work.result
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
            publishSnapshot()
            let inserted = result.transactionsInserted
            if announce || (announceOnlyIfNew && inserted > 0) {
                toast = ToastMessage(
                    text: inserted > 0
                        ? overview?.t(
                            "v2.overview.syncInserted", "{count} nouvelles opérations",
                            ["count": inserted]
                        ) ?? "+\(inserted)"
                        : overview?.t("v2.overview.synced", "À jour")
                            ?? Strings.device("v2.overview.synced", "À jour"),
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
            staleSince = nil
            state = .loaded(data)
        } catch {
            // Same reasoning as sync: a cancelled read is not an outage, and
            // replacing a loaded screen with "Florin est injoignable" because
            // the user let go of a pull is a lie.
            guard !isCancellation(error) else { return }
            /*
             * Unreachable is not the same as having nothing to show.
             *
             * The last good payload is on disk; an hour-old balance beats an
             * error screen every time, as long as the screen says so. A bad
             * *response* — 401, 404 — is different: that is a configuration
             * problem the user has to fix, and quietly serving yesterday's
             * numbers would hide it.
             */
            let recoverable = (error as? FlorinError).map {
                if case .unreachable = $0 { return true } else { return false }
            } ?? true
            if recoverable, overview == nil,
               let cached = SnapshotCache.read(client.overviewKey),
               let data = try? JSONDecoder().decode(Overview.self, from: cached.data) {
                staleSince = cached.savedAt
                state = .loaded(data)
                return
            }
            if overview == nil { state = .failed(error.localizedDescription) }
        }
    }
}
