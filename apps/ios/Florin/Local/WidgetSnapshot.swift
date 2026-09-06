import Foundation
import WidgetKit

/*
 * Two numbers, left where the widget can find them.
 *
 * The obvious way to feed a widget is to let it open the ledger — which means
 * moving the database into a shared container, and moving a live WAL database
 * that holds someone's only copy of their financial life is a risk taken for
 * two figures. A widget does not need the ledger. It needs what the ledger
 * currently says.
 *
 * So the app writes a small file when it knows something new, and the widget
 * reads it. The database never moves, nothing is opened by two processes at
 * once, and an install with no shared container — every sideloaded one, since
 * App Groups need a paid team — simply has no snapshot and a widget that says
 * so, rather than a widget quietly showing zero.
 */
struct WidgetSnapshot: Codable {
    var netWorth: Double
    /// What it was a month ago, so the other face can say which way it moved.
    /// A figure that only moves once a month says nothing on its own; the
    /// direction is the whole reason to look.
    var netMonthAgo: Double?
    var leftToSpend: Double?
    /// How long it has to last, and what that allows a day — the two figures
    /// that turn a number into an answer.
    var daysRemaining: Int?
    var dailyBudget: Double?
    /// The pace actually kept so far this month. Above the budget means the
    /// month ends short, and that is the only thing worth glancing at.
    var dailySpent: Double?
    var currency: String
    var locale: String
    /// The appearance the app is actually showing — `dark`, `light`, or nil for
    /// "follow the phone".
    ///
    /// A widget cannot read the app's choice: the setting lives in the app's
    /// UserDefaults and an extension has its own, so the tile followed iOS
    /// while the app beside it followed its owner. Someone running iOS in light
    /// with Florin set to dark got a pale widget under a dark app, which is the
    /// one comparison a home screen makes for you.
    var appearance: String?
    var updatedAt: Date

    static let group = "group.com.adrbn.florin"

    static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("widget.json")
    }

    static func read() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Called wherever the figures are refreshed. Cheap, and silent when there
    /// is no container: that is the normal state on a free-team install, not an
    /// error worth surfacing.
    static func write(_ snapshot: WidgetSnapshot) {
        guard let url, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
