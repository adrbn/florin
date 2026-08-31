import Foundation

struct PortfolioValuation: Codable, Sendable {
    let marketValue: Double
    let costBasis: Double
    let plusValue: Double
    let cash: Double
    /// Everything transferred into the wrapper, cleared.
    let verse: Double
    /// (marketValue + cash) − verse: the part the market made.
    let marche: Double

    /// Return on what was actually paid in.
    ///
    /// Not `plusValue / costBasis`: a PEA holds idle cash as well as positions,
    /// and measuring only the invested slice flatters a wrapper that is half in
    /// cash. Against total contributions it answers the question people
    /// actually ask — "is this worth more than what I put in".
    var performancePct: Double? {
        guard verse > 0 else { return nil }
        return marche / verse * 100
    }
}

struct Holding: Codable, Sendable, Identifiable {
    let id: String
    let label: String
    let quantity: Double
    let costBasis: Double
    let marketValue: Double
    let plusValue: Double
    let plusValuePct: Double?
    let lastPrice: Double?
    let isStale: Bool
}

struct PortfolioPayload: Codable, Sendable {
    let valuation: PortfolioValuation
    let holdings: [Holding]
}

@MainActor
final class PortfolioModel: ObservableObject {
    @Published private(set) var payload: PortfolioPayload?
    @Published private(set) var loading = false

    private let base: URL

    init(base: URL) { self.base = base }

    func load(accountId: String) async {
        guard !loading, payload == nil else { return }
        loading = true
        /*
         * The device computes it rather than asking for it.
         *
         * This went straight to HTTP, and on a device ledger the base address
         * is `florin-local://device` — a scheme URLSession cannot open. The
         * request failed, the `try?` swallowed it, and the banner simply never
         * appeared: an investment account on the phone showed a total and a
         * list of mechanical rows, with the figures that explain them missing.
         */
        if base.scheme == "florin-local" {
            if let store = LocalStore.shared {
                payload = try? LocalQueries.portfolio(store.database, accountId: accountId)
            }
            loading = false
            return
        }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.path = "/api/v2/accounts/\(accountId)/portfolio"
        if let url = components?.url,
           let (data, response) = try? await FlorinAuth.session.data(for: FlorinAuth.request(url)),
           let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
            payload = try? JSONDecoder().decode(PortfolioPayload.self, from: data)
        }
        loading = false
    }
}
