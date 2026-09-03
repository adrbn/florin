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
