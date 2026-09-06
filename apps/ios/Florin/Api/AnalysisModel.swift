import Foundation

struct MonthlyFlow: Decodable, Sendable, Identifiable {
    let month: String
    let income: Double
    let expense: Double
    let net: Double
    var id: String { month }
}

struct CategoryShare: Decodable, Sendable, Identifiable {
    let groupName: String
    let categoryName: String
    let emoji: String?
    let total: Double
    var id: String { "\(groupName)/\(categoryName)" }
}

struct CategorySeries: Decodable, Sendable {
    struct Row: Decodable, Sendable, Identifiable {
        let categoryId: String
        let categoryName: String
        let emoji: String?
        let monthly: [Double]
        let total: Double
        var id: String { categoryId }
    }
    let months: [String]
    let categories: [Row]
}

struct DailySpend: Decodable, Sendable, Identifiable {
    let date: String
    let amount: Double
    var id: String { date }
}

struct SubscriptionMatch: Decodable, Sendable, Identifiable {
    let payee: String
    let amount: Double
    let cadenceDays: Int
    let samples: Int
    let lastSeen: String
    let annualCost: Double
    let categoryName: String?
    var id: String { "\(payee)-\(amount)" }
}

struct AnalysisData: Decodable, Sendable {
    let flows: [MonthlyFlow]
    let categories: [CategoryShare]
    let categoryIds: [String: String]
    let categorySeries: CategorySeries
    let dailySpend: [DailySpend]
    let subscriptions: [SubscriptionMatch]
    let savings: SavingsRates
    let ageOfMoney: Double?
}

@MainActor
final class AnalysisModel: ObservableObject {
    @Published private(set) var data: AnalysisData?
    @Published private(set) var failure: String?
    @Published private(set) var loading = false

    private let base: URL

    init(base: URL) { self.base = base }

    /// Whether a square in the calendar can be opened.
    ///
    /// The day sheet reads the ledger directly; the server has no endpoint for
    /// a single day and the calendar is its only caller. On a server-backed
    /// install the squares stay inert rather than opening a sheet that would
    /// have nothing to put in it.
    var canOpenDays: Bool { base.scheme == "florin-local" }

    /// The rows behind one square, read when it is tapped rather than with the
    /// rest of the screen — thirty-five days of transactions is most of the
    /// ledger, and all but one of them will never be asked for.
    func day(_ key: String) -> DayDetail? {
        guard canOpenDays, let store = LocalStore.shared else { return nil }
        return try? LocalDay.detail(store: store, day: key)
    }

    func load() async {
        guard !loading else { return }
        loading = true
        do {
            if base.scheme == "florin-local" {
                guard let store = LocalStore.shared else {
                    throw FlorinError.rejected("Florin could not open its database on this device.")
                }
                data = try LocalAnalysis.data(store: store)
                failure = nil
                loading = false
                return
            }
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
            components?.path = "/api/v2/analysis"
            guard let url = components?.url else { throw FlorinError.unreachable(base.host ?? "?") }
            let (payload, response) = try await FlorinAuth.session.data(for: FlorinAuth.request(url))
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw FlorinError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            data = try JSONDecoder().decode(AnalysisData.self, from: payload)
            failure = nil
        } catch is CancellationError {
            // A pull-to-refresh the user let go of is not an outage.
        } catch {
            if (error as NSError).code != NSURLErrorCancelled {
                failure = error.localizedDescription
            }
        }
        loading = false
    }
}

/// "2026-08" → "août" in the app's language.
enum MonthLabel {
    static func short(_ month: String, locale: String) -> String {
        let parts = month.split(separator: "-")
        guard parts.count >= 2, let year = Int(parts[0]), let index = Int(parts[1]) else { return month }
        var components = DateComponents()
        components.year = year
        components.month = index
        components.day = 1
        guard let date = Calendar(identifier: .gregorian).date(from: components) else { return month }
        let f = DateFormatter()
        f.locale = Locale(identifier: locale)
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f.string(from: date)
    }

    /// "août 2026", for a headline that has room for it.
    static func long(_ month: String, locale: String) -> String {
        let parts = month.split(separator: "-")
        guard parts.count >= 2, let year = Int(parts[0]), let index = Int(parts[1]) else { return month }
        var components = DateComponents()
        components.year = year
        components.month = index
        components.day = 1
        guard let date = Calendar(identifier: .gregorian).date(from: components) else { return month }
        let f = DateFormatter()
        f.locale = Locale(identifier: locale)
        f.setLocalizedDateFormatFromTemplate("MMMMy")
        return f.string(from: date).capitalized
    }
}
