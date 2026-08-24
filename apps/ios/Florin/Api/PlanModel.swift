import Foundation

struct PlanCategory: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let emoji: String?
    let assigned: Double
    let spent: Double
    let available: Double
    let note: String?
}

struct PlanGroup: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let kind: String
    let color: String?
    let categories: [PlanCategory]
    let assigned: Double
    let spent: Double
    let available: Double
    let overspentCount: Int
}

struct MonthPlan: Decodable, Sendable {
    let year: Int
    let month: Int
    let groups: [PlanGroup]
    let income: Double
    let totalAssigned: Double
    let readyToAssign: Double
    let overspentCount: Int

    var key: String { String(format: "%04d-%02d", year, month) }
}

@MainActor
final class PlanModel: ObservableObject {
    @Published private(set) var plan: MonthPlan?
    @Published private(set) var loading = false
    @Published private(set) var failure: String?
    @Published var toast: ToastMessage?
    /// Which month is on screen, as `yyyy-MM`.
    @Published var month: String = {
        let now = Date()
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: now)
        return String(format: "%04d-%02d", c.year ?? 2026, c.month ?? 1)
    }()

    private let base: URL

    init(base: URL) { self.base = base }

    func load() async {
        loading = true
        do {
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
            components?.path = "/api/v2/plan"
            components?.queryItems = [URLQueryItem(name: "month", value: month)]
            guard let url = components?.url else { throw FlorinError.unreachable(base.host ?? "?") }
            let (data, response) = try await URLSession.shared.data(for: FlorinAuth.request(url))
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw FlorinError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            plan = try JSONDecoder().decode(MonthPlan.self, from: data)
            failure = nil
        } catch is CancellationError {
        } catch {
            if (error as NSError).code != NSURLErrorCancelled { failure = error.localizedDescription }
        }
        loading = false
    }

    /// Move to the previous or next month. Steps through the calendar rather
    /// than adding 30 days, or December + 1 lands in December.
    func step(_ delta: Int) {
        let parts = month.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = 1
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components),
              let moved = calendar.date(byAdding: .month, value: delta, to: date) else { return }
        let next = calendar.dateComponents([.year, .month], from: moved)
        month = String(format: "%04d-%02d", next.year ?? parts[0], next.month ?? parts[1])
        Task { await load() }
    }

    func assign(_ amount: Double, to categoryId: String) async {
        guard let plan else { return }
        do {
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
            components?.path = "/api/v2/plan"
            guard let url = components?.url else { throw FlorinError.unreachable(base.host ?? "?") }
            var request = FlorinAuth.request(url)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "year": plan.year,
                "month": plan.month,
                "categoryId": categoryId,
                "amount": amount,
            ])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                throw message.map { FlorinError.rejected($0) }
                    ?? FlorinError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            await load()
        } catch {
            toast = ToastMessage(text: error.localizedDescription, kind: .failure)
        }
    }
}
