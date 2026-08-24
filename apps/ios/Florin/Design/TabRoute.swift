import Foundation

/// Which native tab owns a given Florin path.
///
/// The web surface is free to link anywhere — a category bar opens filtered
/// transactions, a KPI tile opens the plan. Inside a native shell those links
/// must move the *tab bar*, not just the web view underneath it: a page that
/// changes while the selected tab stays put leaves the user having to find
/// their way back by hand. So every cross-tab link is intercepted, cancelled,
/// and replayed as a native tab switch.
enum TabRoute: Int, CaseIterable, Identifiable {
    case overview
    case accounts
    case plan
    case activity
    case analysis
    case settings

    var id: Int { rawValue }

    /// What the bar shows, in order.
    ///
    /// Réglages is deliberately not among them: it is opened from the avatar in
    /// the top-left of every screen, and a settings tab in a five-slot bar
    /// spends a fifth of the app's primary navigation on something you touch
    /// twice a year. Plan takes the freed slot, in the middle, because it is
    /// the screen this app is actually for.
    static let tabs: [TabRoute] = [.overview, .accounts, .plan, .activity, .analysis]

    var rootPath: String {
        switch self {
        case .overview: return "/m"
        case .accounts: return "/m/accounts"
        case .plan: return "/m/plan"
        case .activity: return "/m/transactions"
        case .analysis: return "/m/reflect"
        case .settings: return "/m/settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .accounts: return "wallet.bifold"
        case .plan: return "chart.pie"
        case .activity: return "arrow.left.arrow.right"
        case .analysis: return "chart.xyaxis.line"
        case .settings: return "gearshape"
        }
    }

    var titleKey: (String, String) {
        switch self {
        case .overview: return ("v2.nav.overview", "Aperçu")
        case .accounts: return ("v2.nav.accounts", "Comptes")
        case .plan: return ("v2.profile.plan", "Plan")
        case .activity: return ("v2.nav.activity", "Activité")
        case .analysis: return ("v2.nav.analysis", "Analyse")
        case .settings: return ("v2.settings.title", "Réglages")
        }
    }

    /// The tab that owns `path`, or nil when no tab does.
    ///
    /// Review, Categories and Tools deliberately return nil: they have no tab
    /// of their own, so they open as a push inside whichever tab the user is
    /// already in rather than hijacking an unrelated one.
    static func owning(path: String) -> TabRoute? {
        let clean = path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
        if clean == "/m" || clean.isEmpty || clean == "/" { return .overview }
        if clean.hasPrefix("/m/accounts") { return .accounts }
        if clean.hasPrefix("/m/plan") { return .plan }
        if clean.hasPrefix("/m/transactions") { return .activity }
        if clean.hasPrefix("/m/reflect") { return .analysis }
        if clean.hasPrefix("/m/settings") { return .settings }
        return nil
    }
}
