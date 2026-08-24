import SwiftUI

/// Florin for iPhone.
///
/// Florin's data lives on the user's own machine, so the app points at their
/// server rather than shipping a copy of it. The Aperçu tab is fully native —
/// SwiftUI, Swift Charts, real scroll physics — driven by the server's
/// `/api/v2/overview` feed. The remaining tabs render the v2 web surface in
/// chromeless mode (the server drops its own tab bar when it sees this app's
/// user agent) and are being replaced by native screens one at a time.
@main
struct FlorinApp: App {
    @StateObject private var server = ServerStore()

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(server)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var server: ServerStore
    /// Dark by default. Florin is a night-table app and the Obsidian palette
    /// was designed dark-first; following the system would hand most users the
    /// light theme they never asked for.
    @AppStorage("florin.appearance") private var appearanceRaw = Appearance.dark.rawValue
    @State private var showingSetup = false
    @State private var splashing = true

    private var appearance: Appearance { Appearance(rawValue: appearanceRaw) ?? .dark }

    var body: some View {
        ZStack {
            Group {
                if let url = server.resolvedURL {
                    MainTabs(base: url, onRequestSettings: { showingSetup = true })
                        .id(server.reloadToken)
                } else {
                    SetupView(isFirstRun: true)
                }
            }

            // Over the top rather than before it, so the feed is already
            // loading behind the animation instead of starting after it.
            if splashing {
                SplashView {
                    withAnimation(.easeOut(duration: 0.42)) { splashing = false }
                }
                .zIndex(10)
            }
        }
        .tint(Florin.accent)
        .preferredColorScheme(appearance.colorScheme)
        .sheet(isPresented: $showingSetup) {
            SetupView(isFirstRun: false).environmentObject(server)
        }
    }
}

struct MainTabs: View {
    let base: URL
    let onRequestSettings: () -> Void
    @StateObject private var model: OverviewModel
    @StateObject private var chrome = ChromeState()
    @Environment(\.colorScheme) private var colorScheme

    /// Which tab is selected, and what each web tab is currently showing.
    /// A cross-tab link writes both at once, so the bar and the content move
    /// together instead of the page sliding out from under the selection.
    @State private var selection: TabRoute = .overview
    @State private var paths: [TabRoute: String] = [:]
    @State private var adding = false
    @State private var showingSettings = false

    init(base: URL, onRequestSettings: @escaping () -> Void) {
        self.base = base
        self.onRequestSettings = onRequestSettings
        _model = StateObject(wrappedValue: OverviewModel(base: base))
    }

    private var t: Strings { model.overview?.t ?? .empty }

    /*
     * Settings is a cover, not a tab — and that is not only a design choice.
     *
     * A `TabView` with six children is a `UITabBarController` with six items,
     * and UIKit puts everything past the fifth inside its "More" controller,
     * which is a *navigation* controller. That is where the stray back chevron
     * on the Analyse tab came from: Analyse and Réglages were tabs five and six,
     * living inside More, so UIKit drew its navigation bar over our own header
     * and pushed the screen sixty points down. Proved it by replacing the whole
     * Analyse tab with a flat colour — the chevron stayed.
     *
     * Five tabs is the hard ceiling. Réglages was the one to lose its slot: it
     * is opened from the avatar on every screen and touched twice a year.
     */
    private func openSettings() {
        UISelectionFeedbackGenerator().selectionChanged()
        showingSettings = true
    }

    private func route(to tab: TabRoute, path: String) {
        guard tab != .settings else { return openSettings() }
        paths[tab] = path
        chrome.reset()
        withAnimation(.snappy(duration: 0.22)) { selection = tab }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
                OverviewScreen(model: model, chrome: chrome, route: route)
                    .hideSystemTabBar()
                    .tag(TabRoute.overview)

                AccountsScreen(model: model, route: route, onOpenSettings: openSettings)
                    .hideSystemTabBar()
                    .tag(TabRoute.accounts)

                ActivityScreen(
                    overview: model,
                    route: route,
                    onOpenSettings: openSettings,
                    startNeedsReview: paths[.activity]?.contains("needsReview") == true
                )
                .id(paths[.activity] ?? TabRoute.activity.rootPath)
                .hideSystemTabBar()
                .tag(TabRoute.activity)

                PlanScreen(overview: model, route: route, onOpenSettings: openSettings)
                    .hideSystemTabBar()
                    .tag(TabRoute.plan)

                AnalysisScreen(overview: model, route: route, onOpenSettings: openSettings)
                    .hideSystemTabBar()
                    .tag(TabRoute.analysis)
            }
            // The system bar is replaced, not decorated: it cannot be centred
            // when minimised and it has no long-press. TabView still owns tab
            // state and lazy loading.
            .ignoresSafeArea(.keyboard)

            // Content dissolves into the bottom of the screen rather than
            // running on under the bar and out through the home indicator.
            BottomScrim()
                .opacity(chrome.sheetOpen ? 0 : 1)
                .animation(.easeOut(duration: 0.2), value: chrome.sheetOpen)

            FloatingTabBar(
                selection: $selection,
                chrome: chrome,
                title: { tab in
                    let (key, fallback) = tab.titleKey
                    return t(key, fallback)
                },
                reviewCount: model.overview?.reviewCount ?? 0
            )
        }
        .onChange(of: selection) { _, _ in chrome.reset() }
        .fullScreenCover(isPresented: $showingSettings) {
            SettingsScreen(model: model, onClose: { showingSettings = false })
        }
        .sheet(isPresented: $adding) {
            if let data = model.overview {
                AddTransactionSheet(data: data) { try await model.add($0) }
            }
        }
        .florinToast($model.toast)
    }

}

/// One web-backed tab, inside the native shell and inside its own navigation
/// stack so a Plan or Review link can push rather than replace.
struct WebTab: View {
    let base: URL
    let tab: TabRoute
    let path: String
    let appearance: ColorScheme
    @ObservedObject var chrome: ChromeState
    let onRequestSettings: () -> Void
    let onCrossTab: (TabRoute, String) -> Void

    @State private var pushed: [String] = []

    var body: some View {
        NavigationStack(path: $pushed) {
            WebScreen(
                base: base,
                path: path,
                homeTab: tab,
                appearance: appearance,
                chrome: chrome,
                onRequestSettings: onRequestSettings,
                onCrossTab: onCrossTab,
                onPush: { pushed.append($0) }
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { target in
                WebScreen(
                    base: base,
                    path: target,
                    // A pushed screen owns no tab, so links out of it push
                    // again instead of yanking the tab bar sideways.
                    homeTab: nil,
                    appearance: appearance,
                    chrome: chrome,
                    onRequestSettings: onRequestSettings,
                    onCrossTab: onCrossTab,
                    onPush: { pushed.append($0) }
                )
            }
        }
        // Returning to a tab should show that tab, not wherever a link left it.
        .onChange(of: path) { _, _ in pushed.removeAll() }
    }
}

struct WebScreen: View {
    let base: URL
    let path: String
    let homeTab: TabRoute?
    let appearance: ColorScheme
    @ObservedObject var chrome: ChromeState
    let onRequestSettings: () -> Void
    let onCrossTab: (TabRoute, String) -> Void
    let onPush: (String) -> Void

    @State private var loading = true

    private var url: URL {
        URL(string: path, relativeTo: base)?.absoluteURL ?? base
    }

    var body: some View {
        ZStack {
            // The same coloured ground the native screens stand on. The web
            // view is transparent in chromeless mode, so a page rendered here
            // sits on the app's gradient rather than on its own flat slab —
            // without it, half the tabs looked like a different product.
            Backdrop(tint: (homeTab ?? .overview).tint)
            WebContainer(
                url: url,
                onRequestSettings: onRequestSettings,
                onCrossTab: onCrossTab,
                onPush: onPush,
                homeTab: homeTab,
                isLoading: $loading,
                appearance: appearance,
                onScroll: { chrome.scrolled(to: $0) },
                onSheet: { chrome.setSheetOpen($0) }
            )
            .ignoresSafeArea(edges: .top)
            .opacity(loading ? 0 : 1)

            // A tab switch that lands on a white rectangle for a second reads
            // as a broken app. Hold the canvas and show that something is
            // happening until the page has actually painted.
            if loading {
                ProgressView()
                    .controlSize(.large)
                    .tint(Florin.text3)
            }
        }
        .animation(.easeOut(duration: 0.18), value: loading)
        .id(path)
    }
}


extension View {
    /// Hide the system tab bar.
    ///
    /// `.toolbar(.hidden, for: .tabBar)` has to be applied to the *content of a
    /// tab*, not to the TabView: on the TabView it is silently ignored, which
    /// left an empty system bar rendering its own glass capsule underneath the
    /// custom one — two stacked bars.
    func hideSystemTabBar() -> some View {
        toolbar(.hidden, for: .tabBar)
    }
}
