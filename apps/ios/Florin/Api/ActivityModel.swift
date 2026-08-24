import Foundation

/// Filters the Activité tab can apply, mirroring `/m/transactions`' search
/// params one for one so a filter behaves the same in the app and the browser.
struct TxFilter: Equatable, Sendable {
    var search = ""
    var direction: Direction = .all
    var needsReview = false
    var accountId: String?
    var categoryId: String?

    enum Direction: String, CaseIterable, Sendable { case all, expense, income }

    var query: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            items.append(URLQueryItem(name: "q", value: search.trimmingCharacters(in: .whitespaces)))
        }
        if direction != .all { items.append(URLQueryItem(name: "direction", value: direction.rawValue)) }
        if needsReview { items.append(URLQueryItem(name: "needsReview", value: "1")) }
        if let accountId { items.append(URLQueryItem(name: "accountId", value: accountId)) }
        if let categoryId { items.append(URLQueryItem(name: "categoryId", value: categoryId)) }
        return items
    }
}

struct TransactionPage: Decodable, Sendable {
    let total: Int
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

    func patch(_ id: String, _ patch: TxPatch) async throws {
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
    @Published var filter = TxFilter()
    @Published private(set) var rows: [Transaction] = []
    @Published private(set) var total = 0
    @Published private(set) var reviewCount = 0
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var categories: [Category] = []
    @Published private(set) var loading = false
    @Published private(set) var failure: String?
    @Published var toast: ToastMessage?

    private let client: FlorinClient
    private var reachedEnd = false
    /// Generation counter: a page that arrives after the filter changed is
    /// stale and must not be appended, or typing in the search field shuffles
    /// results from two different queries together.
    private var generation = 0

    init(base: URL) { client = FlorinClient(base: base) }

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
            reviewCount = page.reviewCount
            accounts = page.accounts
            categories = page.categories
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
        } catch {
            reachedEnd = true
        }
        if token == generation { loading = false }
    }

    func apply(_ patch: TxPatch, to id: String, t: Strings) async {
        do {
            try await client.patch(id, patch)
            if patch.approve == true { reviewCount = max(0, reviewCount - 1) }
            await refreshRow(id)
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
