import Foundation
import SwiftUI

/// Filters the Activité tab can apply, mirroring `/m/transactions`' search
/// params one for one so a filter behaves the same in the app and the browser.
struct TxFilter: Equatable, Sendable {
    var search = ""
    var direction: Direction = .all
    var needsReview = false
    var excludeTransfers = false
    var accountId: String?
    var categoryId: String?
    var from: Date?
    var to: Date?

    enum Direction: String, CaseIterable, Sendable { case all, expense, income }

    /// The route takes plain `yyyy-MM-dd`; sending an ISO datetime would make
    /// a same-day from/to pair an empty window.
    static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: date)
    }

    /// Anything narrowing the ledger beyond the free-text search, which has its
    /// own visible field and its own affordance for clearing.
    var isFiltered: Bool {
        direction != .all || needsReview || excludeTransfers
            || accountId != nil || categoryId != nil || from != nil || to != nil
    }

    /// How many chips' worth of narrowing is on, for the badge on the button.
    var activeCount: Int {
        var n = 0
        if direction != .all { n += 1 }
        if needsReview { n += 1 }
        if excludeTransfers { n += 1 }
        if accountId != nil { n += 1 }
        if categoryId != nil { n += 1 }
        if from != nil || to != nil { n += 1 }
        return n
    }

    var query: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            items.append(URLQueryItem(name: "q", value: search.trimmingCharacters(in: .whitespaces)))
        }
        if direction != .all { items.append(URLQueryItem(name: "direction", value: direction.rawValue)) }
        if needsReview { items.append(URLQueryItem(name: "needsReview", value: "1")) }
        if excludeTransfers { items.append(URLQueryItem(name: "excludeTransfers", value: "1")) }
        if let accountId { items.append(URLQueryItem(name: "accountId", value: accountId)) }
        if let categoryId { items.append(URLQueryItem(name: "categoryId", value: categoryId)) }
        if let from { items.append(URLQueryItem(name: "from", value: Self.day(from))) }
        if let to { items.append(URLQueryItem(name: "to", value: Self.day(to))) }
        return items
    }
}

struct TransactionPage: Decodable, Sendable {
    let total: Int
    /*
     * Ce que pèsent les lignes comptées, et pas seulement celles chargées.
     *
     * La liste se pagine : additionner `transactions` donnerait le total de
     * la première page, ce qui est faux et ne se voit pas. La somme vient
     * donc de la même requête que le compte, sur le même filtre.
     *
     * Optionnelle : la route v2 du serveur ne la rend pas, et son absence
     * doit se lire « inconnue » plutôt que « zéro ».
     */
    var sum: Double?
    let reviewCount: Int
    let transactions: [Transaction]
    let accounts: [Account]
    let categories: [Category]
}

/// One edit to a transaction. Every field is optional; the route applies only
/// what is present, in the order edit → categorise → approve.
struct TxPatch: Encodable, Sendable {
    var categoryId: String??
    var approve: Bool?
    var payee: String?
    var memo: String??
    var amount: Double?
    var occurredAt: String?
    /*
     * Device ledger only, and never encoded — like `NewTransaction.upcoming`.
     *
     * Moving a row to another account and putting it back under "en prévision"
     * are both writes the device performs itself. The server's PATCH accepts
     * neither, and its schema drops keys it does not know rather than
     * refusing them: encoded, they would look like they had been applied. The
     * sheet offers them only where they work.
     */
    var accountId: String?
    var upcoming: Bool?

    enum CodingKeys: String, CodingKey {
        case categoryId, approve, payee, memo, amount, occurredAt
    }

    /// Hand-rolled so `categoryId: .some(nil)` encodes as JSON null — clearing a
    /// category — while an absent one stays absent. `encodeIfPresent` collapses
    /// both cases to "omit", which would make un-categorising impossible.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let categoryId { try c.encode(categoryId, forKey: .categoryId) }
        try c.encodeIfPresent(approve, forKey: .approve)
        try c.encodeIfPresent(payee, forKey: .payee)
        if let memo { try c.encode(memo, forKey: .memo) }
        try c.encodeIfPresent(amount, forKey: .amount)
        try c.encodeIfPresent(occurredAt, forKey: .occurredAt)
    }
}

extension FlorinClient {
    func transactions(filter: TxFilter, offset: Int, limit: Int = 50) async throws -> TransactionPage {
        if isLocal {
            return try LocalLedger.page(
                store: try localStore(), filter: filter, offset: offset, limit: limit
            )
        }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.path = "/api/v2/transactions"
        components?.queryItems =
            filter.query + [
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        guard let url = components?.url else { throw FlorinError.unreachable(base.host ?? "?") }

        let (data, response) = try await FlorinAuth.session.data(for: FlorinAuth.request(url))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FlorinError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(TransactionPage.self, from: data)
    }

    func bulkApprove(_ ids: [String]) async throws {
        if isLocal { return try LocalLedger.approve(store: try localStore(), ids: ids) }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.path = "/api/v2/transactions/bulk"
        guard let url = components?.url else { throw FlorinError.unreachable(base.host ?? "?") }
        var request = FlorinAuth.request(url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["action": "approve", "ids": ids]
        )
        try await send(request)
    }

    func patch(_ id: String, _ patch: TxPatch) async throws {
        if isLocal { return try LocalLedger.patch(store: try localStore(), id: id, patch) }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.path = "/api/v2/transactions/\(id)"
        guard let url = components?.url else { throw FlorinError.unreachable(base.host ?? "?") }
        var request = FlorinAuth.request(url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(patch)
        try await send(request)
    }

    func delete(_ id: String) async throws {
        if isLocal { return try LocalLedger.delete(store: try localStore(), id: id) }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.path = "/api/v2/transactions/\(id)"
        guard let url = components?.url else { throw FlorinError.unreachable(base.host ?? "?") }
        var request = FlorinAuth.request(url)
        request.httpMethod = "DELETE"
        try await send(request)
    }

    private func send(_ request: URLRequest) async throws {
        let (data, response) = try await FlorinAuth.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FlorinError.badStatus(0) }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw message.map { FlorinError.rejected($0) } ?? FlorinError.badStatus(http.statusCode)
        }
    }
}

/// The Activité tab's list.
///
/// Paginated rather than all-at-once: the query layer caps a page at 100 and a
/// real ledger runs to thousands of rows, so the screen asks for the next fifty
/// when the last one appears. Edits are applied optimistically and reconciled
/// on the next page load — waiting a round trip to tick "vérifié" makes a queue
/// of thirty feel broken.
@MainActor
final class ActivityModel: ObservableObject {
    @Published var filter = TxFilter() {
        didSet {
            guard filter.needsReview != oldValue.needsReview else { return }
            regroup()
        }
    }
    @Published private(set) var rows: [Transaction] = [] { didSet { regroup() } }
    @Published private(set) var total = 0
    /// Ce que pèsent les lignes comptées. Inconnu contre un serveur, qui ne
    /// le rend pas — voir `TransactionPage.sum`.
    @Published private(set) var sum: Double?
    @Published private(set) var reviewCount = 0
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var categories: [Category] = []
    /// Les achats payés en plusieurs fois, regroupés par échéancier plutôt
    /// que listés échéance par échéance. Vides contre un serveur.
    @Published private(set) var schedules: [LocalInstalments.Schedule] = []
    @Published private(set) var loading = false
    @Published private(set) var failure: String?
    @Published var toast: ToastMessage?

    /*
     * Les lignes rangées comme l'écran les lit, calculées ICI.
     *
     * Elles étaient quatre propriétés calculées de la vue. Une propriété
     * calculée ne garde rien : chaque évaluation du corps refaisait trois
     * filtres sur les trois mille lignes, un début de journée par ligne et
     * l'appariement des virements — et `days` était lu deux fois par corps,
     * donc tout cela deux fois. Vingt millisecondes de fil principal l'unité.
     *
     * Or le corps est réévalué à chaque changement d'état de l'app, pour les
     * cinq pages montées du pagineur, visibles ou pas : un simple changement
     * d'onglet en déclenchait une demi-douzaine de tours. D'où les 300 ms
     * pendant lesquelles rien ne répondait.
     *
     * Le rangement ne dépend que des lignes et de la file à vérifier. Il est
     * donc fait une fois quand elles bougent, et le corps ne fait plus que
     * lire.
     */
    @Published private(set) var upcoming: [Transaction] = []
    @Published private(set) var instalments: [Transaction] = []
    @Published private(set) var pending: [Transaction] = []
    @Published private(set) var days: [(day: Date, rows: [Transaction])] = []

    private let client: FlorinClient
    private var reachedEnd = false
    /// Generation counter: a page that arrives after the filter changed is
    /// stale and must not be appended, or typing in the search field shuffles
    /// results from two different queries together.
    private var generation = 0

    init(base: URL) { client = FlorinClient(base: base) }

    /*
     * Ce qui n'a pas encore eu lieu ne se range pas avec ce qui a eu lieu.
     *
     * Une banque publie un prélèvement plusieurs jours avant de le prendre,
     * et un achat en quatre fois connaît ses trois échéances suivantes le
     * jour même. Par date, tout cela arrive en tête — donc un « 30 octobre »
     * s'ouvrait au-dessus d'« Aujourd'hui » et poussait les vraies opérations
     * vers le bas. Elles sont déjà hors de tous les totaux ; elles sortent
     * aussi des journées, et se replient dans leur propre pli au-dessus.
     *
     * La file d'attente sort aussi de sa journée : la voir ici ET là ferait
     * croire à deux opérations. Elle se replie dans son pli, sauf quand c'est
     * précisément elle qu'on a demandé à voir.
     *
     * Les deux jambes d'un virement sont repliées en une : les voir toutes
     * les deux, à une ligne d'écart et au signe près, ne dit rien de plus que
     * la ligne unique et fait croire à deux mouvements.
     */
    private func regroup() {
        upcoming = rows.filter { $0.isUpcoming && !$0.isInstalment }
        instalments = rows.filter { $0.isScheduled && $0.isInstalment }
        pending = filter.needsReview
            ? [] : rows.filter { $0.needsReview && !$0.isUpcoming }

        var announced = Set(upcoming.lazy.filter(\.isToCome).map(\.id))
        announced.formUnion(instalments.lazy.map(\.id))
        announced.formUnion(pending.lazy.map(\.id))

        days = ActivityModel.grouped(rows, excluding: announced)
    }

    /*
     * Un jour, un groupe — et pas un par tranche consécutive.
     *
     * Le découpage suivait l'ordre d'arrivée et ouvrait un groupe chaque fois
     * que la journée changeait, en pariant que la requête les rend déjà
     * rangées. Elle les range sur `substr(occurred_at, 1, 10)`, du texte lu
     * en TU ; l'écran, lui, les range sur la journée LOCALE. Une ligne
     * horodatée à 23 h TU appartient au lendemain ici et arrive pourtant au
     * milieu de la veille : le pari tombe, et « Aujourd'hui » s'ouvre deux
     * fois.
     *
     * Deux sections de même identité dans un même `ForEach`, SwiftUI ne sait
     * pas les rendre — d'où les blocs blancs, les sections qui se répètent au
     * défilement, et les lignes qu'on cherchait en vain dans la première
     * journée alors qu'elles attendaient dans la seconde.
     *
     * Le rangement fait donc foi : on classe par journée, puis on trie.
     */
    nonisolated static func grouped(
        _ rows: [Transaction], excluding announced: Set<String>
    ) -> [(day: Date, rows: [Transaction])] {
        // `Calendar.current` rend une COPIE à chaque lecture : la prendre
        // dans la boucle, c'est trois mille calendriers pour trois mille
        // lignes.
        let calendar = Calendar.current
        var buckets: [Date: [Transaction]] = [:]
        for row in rows where !announced.contains(row.id) {
            buckets[calendar.startOfDay(for: row.day), default: []].append(row)
        }
        return buckets.keys.sorted(by: >).map {
            ($0, TransferPairs.collapsed(buckets[$0] ?? []))
        }
    }

    /// The phone's own books. The edit sheet asks: two of its rows are writes
    /// only the device performs — see `TxPatch.accountId`.
    var isLocalLedger: Bool { client.isLocal }

    var hasMore: Bool { !reachedEnd && !rows.isEmpty }

    func reload() async {
        generation += 1
        let token = generation
        reachedEnd = false
        loading = true
        failure = nil
        do {
            let page = try await client.transactions(filter: filter, offset: 0)
            guard token == generation else { return }
            rows = page.transactions
            total = page.total
            sum = page.sum
            reviewCount = page.reviewCount
            accounts = page.accounts
            categories = page.categories
            // Les échéanciers ne se paginent pas : ils tiennent en quelques
            // achats, et un plan à moitié chargé ne dit rien de juste.
            schedules = (try? client.instalmentPlans()) ?? []
            reachedEnd = page.transactions.count >= page.total
        } catch {
            guard token == generation else { return }
            failure = error.localizedDescription
        }
        if token == generation { loading = false }
    }

    func loadMore() async {
        guard !loading, !reachedEnd else { return }
        let token = generation
        loading = true
        do {
            let page = try await client.transactions(filter: filter, offset: rows.count)
            guard token == generation else { return }
            if page.transactions.isEmpty {
                reachedEnd = true
            } else {
                // The list is a set, not a stream: a row inserted at the top
                // between two pages would otherwise arrive twice.
                let known = Set(rows.map(\.id))
                rows.append(contentsOf: page.transactions.filter { !known.contains($0.id) })
                reachedEnd = rows.count >= page.total
            }
            total = page.total
            sum = page.sum
        } catch {
            reachedEnd = true
        }
        if token == generation { loading = false }
    }

    /// Pairs a row with the account the money reached. The ledger writes the
    /// far leg — or adopts one already sitting there — so the whole list is
    /// reloaded rather than one row patched.
    func attachTransfer(_ txId: String, to accountId: String, t: Strings) async {
        do {
            try await client.attachTransfer(txId, to: accountId)
            await reload()
        } catch {
            toast = ToastMessage(text: error.localizedDescription, kind: .failure)
        }
    }

    func apply(_ patch: TxPatch, to id: String, t: Strings) async {
        /*
         * A verdict leaves the queue as it is given.
         *
         * Waiting for the round trip meant the row sat there looking exactly
         * as it had before, and the queue only emptied on the next pull. The
         * row is marked here, animated, and the server merely confirms it —
         * the same optimism `approve(_:t:)` already applies in bulk.
         */
        var optimistic = false
        if patch.approve == true, let index = rows.firstIndex(where: { $0.id == id }) {
            withAnimation(.snappy(duration: 0.28)) {
                // Under the "à vérifier" filter the row no longer belongs to
                // the list at all; anywhere else it simply loses its badge and
                // rejoins its day.
                if filter.needsReview {
                    rows.remove(at: index)
                    total = max(0, total - 1)
                } else {
                    rows[index] = rows[index].approved()
                }
            }
            reviewCount = max(0, reviewCount - 1)
            optimistic = true
        }
        do {
            try await client.patch(id, patch)
            if patch.approve == true && !optimistic { reviewCount = max(0, reviewCount - 1) }
            await refreshRow(id)
        } catch {
            toast = ToastMessage(text: error.localizedDescription, kind: .failure)
            await reload()
        }
    }

    /// Approve several rows in one call.
    ///
    /// Optimistic on the rows already on screen: the queue is the one place
    /// where a round trip per row would be felt, because the whole point is
    /// clearing twenty of them in a gesture.
    func approve(_ ids: [String], t: Strings) async {
        guard !ids.isEmpty else { return }
        let marked = Set(ids)
        withAnimation(.snappy(duration: 0.28)) {
            if filter.needsReview {
                rows.removeAll { marked.contains($0.id) }
                total = max(0, total - ids.count)
            } else {
                for index in rows.indices where marked.contains(rows[index].id) {
                    rows[index] = rows[index].approved()
                }
            }
        }
        reviewCount = max(0, reviewCount - ids.count)
        do {
            try await client.bulkApprove(ids)
            toast = ToastMessage(
                text: t("v2.review.approvedCount", "{count} opérations vérifiées", ["count": ids.count]),
                kind: .success
            )
        } catch {
            toast = ToastMessage(text: error.localizedDescription, kind: .failure)
            await reload()
        }
    }

    func delete(_ id: String, t: Strings) async {
        let removed = rows.first { $0.id == id }
        rows.removeAll { $0.id == id }
        total = max(0, total - 1)
        do {
            try await client.delete(id)
            toast = ToastMessage(text: t("v2.activity.deleted", "Opération supprimée"), kind: .success)
        } catch {
            if let removed { rows.append(removed) }
            toast = ToastMessage(text: error.localizedDescription, kind: .failure)
            await reload()
        }
    }

    /*
     * Supprimer en lot, comme on valide en lot.
     *
     * Même optimisme que `approve(_:t:)` : les lignes quittent l'écran tout de
     * suite, parce que le geste n'a d'intérêt que s'il est instantané. La
     * suppression reste DOUCE — la ligne garde sa place avec un `deleted_at`,
     * la corbeille la rend pendant trente jours, et une synchro qui la
     * repêche chez la banque ne la ressuscite pas comme une nouveauté.
     *
     * Une boucle, pas un appel de masse : il n'y a pas de route en lot côté
     * serveur, et on en supprime une poignée, pas mille.
     */
    func delete(_ ids: [String], t: Strings) async {
        guard !ids.isEmpty else { return }
        let marked = Set(ids)
        let removed = rows.filter { marked.contains($0.id) }
        withAnimation(.snappy(duration: 0.28)) {
            rows.removeAll { marked.contains($0.id) }
            total = max(0, total - ids.count)
        }
        reviewCount = max(0, reviewCount - removed.filter(\.needsReview).count)

        var failed = 0
        for id in ids {
            do { try await client.delete(id) } catch { failed += 1 }
        }
        if failed > 0 {
            toast = ToastMessage(
                text: t("v2.common.error", "Une erreur est survenue"), kind: .failure
            )
            await reload()
            return
        }
        toast = ToastMessage(
            text: ids.count == 1
                ? t("v2.activity.deleted", "Opération supprimée")
                : t("v2.review.deletedCount", "{count} opérations supprimées",
                    ["count": ids.count]),
            kind: .success
        )
    }

    /// Pull just the edited row back rather than the whole list: reloading
    /// thirty rows to reflect one category change loses the scroll position.
    private func refreshRow(_ id: String) async {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        do {
            var single = filter
            single.search = ""
            single.needsReview = false
            let page = try await client.transactions(filter: single, offset: 0, limit: 100)
            if let fresh = page.transactions.first(where: { $0.id == id }) {
                rows[index] = fresh
            }
            reviewCount = page.reviewCount
        } catch {
            // Non-fatal: the optimistic row stays until the next full reload.
        }
    }
}
