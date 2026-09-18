import Foundation

struct MonthlyFlow: Decodable, Sendable, Identifiable {
    let month: String
    let income: Double
    let expense: Double
    let net: Double
    var id: String { month }

    /// The month the ledger is still inside.
    ///
    /// Its bars are honest — they are what has happened so far — but its *net*
    /// is not comparable with a month that is over: a salary paid on the 27th
    /// is missing from every day before it, so on the 18th the month reads as
    /// three weeks of spending against almost no income. Plotted on the same
    /// line as eleven finished months it drew a cliff every month, and dragged
    /// the axis down with it until the finished months were a flat ribbon.
    ///
    /// Derived here rather than sent: the server's twelve months end on the
    /// same running month, so both modes mark the same bar.
    var isRunning: Bool { month == MonthlyFlow.runningMonth }

    static var runningMonth: String { LocalQueries.monthFormatter.string(from: Date()) }
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

/// One day, one category — the breakdown behind a calendar square.
///
/// The grid only ever needed a total per day, but a filter needs to know what
/// the total is made of, and re-reading the ledger on every change of the
/// filter would be asking the database a question the screen already has the
/// answer to.
struct DailySlice: Decodable, Sendable, Identifiable {
    let date: String
    let categoryId: String
    /// Positive when money left, like `DailySpend`.
    let amount: Double
    var id: String { "\(date)/\(categoryId)" }
}

/// A category the calendar can be filtered by.
struct SpendCategory: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let emoji: String?
    let groupName: String
    /// Set on the category itself, in Catégories. Rent, insurance and
    /// subscriptions carry it out of the box, which is what makes "hors
    /// charges fixes" a preset rather than a list of names in the code.
    let isFixed: Bool
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
    /*
     * Both are local-only, and optional for that reason.
     *
     * The server's `/api/v2/analysis` sends neither, and a synthesised decoder
     * reads a missing optional as nil rather than failing — so a server-backed
     * install keeps working and simply has no filter to open, exactly as it
     * already has no day sheet to open.
     */
    let dailySlices: [DailySlice]?
    let spendCategories: [SpendCategory]?
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
    func day(_ key: String, excluding hidden: Set<String>) -> DayDetail? {
        guard canOpenDays, let store = LocalStore.shared else { return nil }
        return try? LocalDay.detail(store: store, day: key, excluding: hidden)
    }

    /// Whether the calendar can be cut by category: the breakdown is computed
    /// on the device and the server feed does not carry it.
    var canFilterDays: Bool {
        guard let categories = data?.spendCategories else { return false }
        return !categories.isEmpty
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

    /// The month after "2026-12" is "2027-01".
    static func next(_ month: String) -> String {
        let parts = month.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return month }
        let index = parts[1] + 1
        return index > 12
            ? String(format: "%04d-01", parts[0] + 1)
            : String(format: "%04d-%02d", parts[0], index)
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
