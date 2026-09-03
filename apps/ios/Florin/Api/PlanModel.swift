import Foundation

struct PlanCategory: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let emoji: String?
    let assigned: Double
    let spent: Double
    let available: Double
    let note: String?
    /// A bill that arrives whether or not it was budgeted for. Absent from the
    /// server's plan feed, so optional: an edit sheet must not silently clear
    /// a flag it was never told about.
    var isFixed: Bool?
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
    /*
     * What the month is expected to bring in.
     *
     * A salary lands around the 27th, so for most of a month `income` is a
     * fraction of the truth and usually zero — the hero read "sur 0 € de
     * revenus" above a plan of 2 900 €, and called every assignment made
     * before payday an overspend. While the month is still running the
     * estimate is the median of the six complete months before it.
     *
     * Optional: a server that predates the field falls back to `income`.
     */
    var expectedIncome: Double?
    var incomeIsEstimated: Bool?
    let totalAssigned: Double
    let readyToAssign: Double
    let overspentCount: Int

    var key: String { String(format: "%04d-%02d", year, month) }

    /// What the hero counts against: the estimate while the month runs, what
    /// actually landed once it is over.
    var plannedAgainst: Double { expectedIncome ?? income }
    var isEstimated: Bool { incomeIsEstimated ?? false }
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
            if base.scheme == "florin-local" {
                let parts = month.split(separator: "-").compactMap { Int($0) }
                guard parts.count == 2, let store = LocalStore.shared else {
                    throw FlorinError.rejected("Florin could not open its database on this device.")
                }
                plan = try LocalPlan.month(store: store, year: parts[0], month: parts[1])
                failure = nil
                loading = false
                return
            }
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
            components?.path = "/api/v2/plan"
            components?.queryItems = [URLQueryItem(name: "month", value: month)]
            guard let url = components?.url else { throw FlorinError.unreachable(base.host ?? "?") }
            let (data, response) = try await FlorinAuth.session.data(for: FlorinAuth.request(url))
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

    /// Whether the envelopes themselves can be edited from here.
    ///
    /// On the device the ledger is the authority, so categories are created,
    /// renamed and retired in place. Pointed at a server they are that
    /// server's, edited there — the phone is a view of that ledger, not a
    /// second authority over it, and offering an edit that silently applies
    /// to nothing would be worse than not offering it.
    var canEditCategories: Bool { base.scheme == "florin-local" }

    private var store: LocalStore? { canEditCategories ? LocalStore.shared : nil }

    func addCategory(to groupId: String, name: String, emoji: String, isFixed: Bool) async {
        await mutate {
            guard let store = self.store else { return }
            try LocalCategories.create(
                store: store, groupId: groupId, name: name, emoji: emoji, isFixed: isFixed
            )
        }
    }

    func editCategory(_ id: String, name: String, emoji: String, isFixed: Bool) async {
        await mutate {
            guard let store = self.store else { return }
            try LocalCategories.update(
                store: store, id: id, name: name, emoji: emoji, isFixed: isFixed
            )
        }
    }

    /// How many transactions a category carries — the question that decides
    /// what deleting it can even mean.
    func categoryUsage(_ id: String) -> Int {
        guard let store else { return 0 }
        return (try? LocalCategories.usage(store: store, id: id)) ?? 0
    }

    func removeCategory(
        _ id: String, named name: String, how: LocalCategories.Removal, t: Strings
    ) async {
        await mutate {
            guard let store = self.store else { return }
            try LocalCategories.remove(store: store, id: id, how: how)
            // Say what actually happened. Announcing "supprimée" when a year of
            // history still carries the label is how people stop believing what
            // a screen tells them.
            let text: String
            switch how {
            case .reassign:
                text = t(
                    "v2.plan.categoryMoved",
                    "« {name} » supprimée, ses opérations déplacées.", ["name": name]
                )
            case .detach:
                text = t(
                    "v2.plan.categoryDetached",
                    "« {name} » supprimée. Ses opérations sont à reclasser.", ["name": name]
                )
            case .archive:
                text = t(
                    "v2.plan.categoryArchived",
                    "« {name} » retirée du plan. Ses opérations la gardent.", ["name": name]
                )
            }
            self.toast = ToastMessage(text: text, kind: .success)
        }
    }

    /// Every category edit ends the same way: apply, reload, or surface why not.
    private func mutate(_ work: @escaping () throws -> Void) async {
        do {
            try work()
            await load()
        } catch {
            toast = ToastMessage(text: error.localizedDescription, kind: .failure)
        }
    }

    /// True when the figures come from this device's own database, and a month
    /// can therefore be read in the time it takes to answer a gesture.
    var isLocal: Bool { base.scheme == "florin-local" }

    /// Move to the previous or next month. Steps through the calendar rather
    /// than adding 30 days, or December + 1 lands in December.
    func step(_ delta: Int) {
        guard moveMonth(delta) else { return }
        Task { await load() }
    }

    /*
     * The same step, awaited.
     *
     * A caller animating the change wants the next month already made when it
     * comes on screen. Firing the load and returning meant the page slid back
     * in still showing the month it had left, and whatever the new one added —
     * the card offering to copy a plan into an empty month, most visibly —
     * appeared halfway through the movement.
     */
    func stepAndLoad(_ delta: Int) async {
        guard moveMonth(delta) else { return }
        await load()
    }

    @discardableResult
    private func moveMonth(_ delta: Int) -> Bool {
        let parts = month.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return false }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = 1
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components),
              let moved = calendar.date(byAdding: .month, value: delta, to: date) else { return false }
        let next = calendar.dateComponents([.year, .month], from: moved)
        month = String(format: "%04d-%02d", next.year ?? parts[0], next.month ?? parts[1])
        return true
    }

    /// Months that carry a plan worth copying, newest first. Device only —
    /// the server has its own copy button on its own screen.
    var planSources: [LocalPlan.PlanSource] {
        guard base.scheme == "florin-local", let plan, let store = LocalStore.shared
        else { return [] }
        return (try? LocalPlan.sourceMonths(
            store.database, excluding: (plan.year, plan.month)
        )) ?? []
    }

    /// Bring another month's amounts into this one, leaving anything already
    /// set alone.
    func copyPlan(from source: LocalPlan.PlanSource) async {
        guard let plan, let store = LocalStore.shared else { return }
        _ = try? LocalPlan.copyPlan(
            store: store,
            from: (source.year, source.month),
            to: (plan.year, plan.month)
        )
        await load()
    }

    func assign(_ amount: Double, to categoryId: String) async {
        guard let plan else { return }
        do {
            if base.scheme == "florin-local" {
                guard let store = LocalStore.shared else {
                    throw FlorinError.rejected("Florin could not open its database on this device.")
                }
                try LocalPlan.assign(
                    store: store, year: plan.year, month: plan.month,
                    categoryId: categoryId, amount: amount
                )
                await load()
                return
            }
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
            let (data, response) = try await FlorinAuth.session.data(for: request)
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
