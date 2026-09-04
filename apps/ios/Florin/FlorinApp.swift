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

    init() {
        /*
         * Open the on-device ledger at launch, and say so.
         *
         * Nothing reads from it yet — the app is still a thin client and every
         * figure on screen still comes from the server. This runs so that the
         * store's schema migration is exercised on a real device on every
         * build, rather than being discovered to be broken on the day a query
         * finally depends on it. When a port lands, the failure it prevents is
         * already behind us.
         */
        LocalStore.probeAtLaunch()
        // Registered before the first frame, as iOS requires: a handler added
        // later is never called, and the app is simply never woken again.
        BackgroundRefresh.register()
        BackgroundRefresh.schedule()
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(server)
                /*
                 * The language chosen in settings has to reach UIKit too.
                 *
                 * Florin draws its own text from its own string tables, so
                 * picking English in settings turned every label English —
                 * except the controls it does not draw itself. The date picker
                 * on the add-transaction sheet is SwiftUI's, and SwiftUI asks
                 * the environment, which nobody had set, so it fell through to
                 * the handset's language: "4 sept. 2026" sitting under Payee,
                 * Account and Category on an otherwise English screen.
                 */
                .environment(\.locale, Locale(identifier: Strings.tag(for: Strings.preferredShortLocale)))
        }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the foreground is the moment a backup is most likely to
            // run, and the moment the ledger is guaranteed to be idle. Folding
            // the write-ahead log back in here is what makes including the
            // database in backups safe — see LocalStore.checkpoint.
            if phase != .active {
                LocalStore.checkpoint()
                // Locked before the snapshot iOS takes for the app switcher,
                // not when someone comes back — otherwise the ledger is
                // legible in the switcher to anyone holding the phone.
                AppLock.shared.willResignActive()
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var server: ServerStore
    @ObservedObject private var lock = AppLock.shared
    /// Dark by default. Florin is a night-table app and the Obsidian palette
    /// was designed dark-first; following the system would hand most users the
    /// light theme they never asked for.
    @AppStorage("florin.appearance") private var appearanceRaw = Appearance.dark.rawValue
    @State private var showingSetup = false
    @State private var splashing = true
    @State private var wantsServerForm = false
    /*
     * Which books are open, chosen rather than inferred.
     *
     * It defaulted to whichever happened to be configured, so the first launch
     * after a server was set could not be talked out of it, and someone using
     * the device ledger had to erase their server address to get there. The
     * default still follows what exists — a configured server means that is
     * what you were using — but from then on it is a setting.
     */
    @AppStorage("florin.dataSource") private var sourceRaw = ""
    /// True once the source has been changed in this session, so the rebuild
    /// lands back in settings rather than on the dashboard.
    @State private var switchedSource = false
    @State private var showingSettings = false

    /// Whichever ledger is on screen, for the screens presented above it.
    private var currentBase: URL {
        source == .server ? (server.resolvedURL ?? FlorinClient.localBase) : FlorinClient.localBase
    }
    /// Changed when onboarding finishes, purely to re-evaluate the branch
    /// above — `LocalOnboarding.isComplete` reads the database, which SwiftUI
    /// has no way to observe on its own.
    @State private var onboarded = UUID()
    /// Bank setup, presented as the last step of onboarding rather than as a
    /// settings screen — nothing behind it is worth seeing yet.
    @State private var connectingBank = false

    private var appearance: Appearance { Appearance(rawValue: appearanceRaw) ?? .dark }

    /// Where to land after the tree is rebuilt: settings if that is where the
    /// user was when they changed something that rebuilds it.
    private var landingTab: TabRoute { switchedSource ? .settings : .overview }

    /// Falls back to whatever is actually configured, so an existing install
    /// keeps reading its server without being asked.
    private var source: DataSource {
        if let stored = DataSource(rawValue: sourceRaw) { return stored }
        return server.resolvedURL != nil ? .server : .device
    }

    var body: some View {
        ZStack {
            Group {
                if source == .server, let url = server.resolvedURL {
                    MainTabs(
                        base: url,
                        initialTab: landingTab,
                        onRequestSettings: { showingSettings = true }
                    )
                    .id(server.reloadToken)
                } else if source == .server {
                    SetupView(isFirstRun: true)
                } else if LocalOnboarding.isComplete {
                    // Same tabs, same screens — reading the phone instead of a
                    // server. See `FlorinClient.localBase`.
                    MainTabs(
                        base: FlorinClient.localBase,
                        initialTab: landingTab,
                        onRequestSettings: { showingSettings = true }
                    )
                    .id(onboarded)
                } else if wantsServerForm {
                    /*
                     * The form, for people who came looking for it.
                     *
                     * It used to be the front door: a fresh install was asked
                     * for a URL and a token before the app had said what it
                     * was. Someone who has never run Florin anywhere has no
                     * server and no way to guess that they were supposed to.
                     * It stays one tap from the welcome screen, and it is what
                     * you get back to once onboarding is behind you.
                     */
                    SetupView(isFirstRun: true)
                } else {
                    OnboardingFlow(
                        onFinish: { onboarded = UUID() },
                        onUseServer: { wantsServerForm = true },
                        onNeedsBank: { connectingBank = true }
                    )
                }
            }
            .id(onboarded)
            .onChange(of: sourceRaw) { _, _ in switchedSource = true }

            // Zero-sized, but it owns the responder chain so a shake reaches
            // us without swizzling UIWindow.
            ShakeDetector().frame(width: 0, height: 0).allowsHitTesting(false)

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
        .onReceive(NotificationCenter.default.publisher(for: .florinShake)) { _ in
            Privacy.shared.toggle()
        }
        /*
         * Presented here, above the view that the source switch replaces.
         *
         * It used to be a cover inside MainTabs — the very thing rebuilt when
         * the data source changes — so switching from the server to the device
         * closed the screen where that switch is made. Every time.
         */
        .fullScreenCover(isPresented: $showingSettings) {
            SettingsScreen(base: currentBase, onClose: { showingSettings = false })
                .environmentObject(server)
        }
        /*
         * Full screen, not a sheet.
         *
         * As a half-height sheet it left the settings — or worse, a dashboard
         * of zeros — visible behind it, which made a required step look
         * optional and the app look unfinished. Onboarding is not finished
         * until a bank is actually connected, so this covers everything until
         * it is.
         */
        .fullScreenCover(isPresented: $connectingBank) {
            BankingSettings(onConnected: {
                try? LocalOnboarding.markComplete()
                connectingBank = false
                onboarded = UUID()
            })
        }
        /*
         * Above the covers, not beside them.
         *
         * Settings and the bank setup are full-screen covers; a lock presented
         * as one more of them would sit behind whichever was already up. As an
         * overlay on the root it covers the covers, which is the only place a
         * lock can honestly be.
         */
        .overlay {
            if lock.locked {
                LockScreen()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: lock.locked)
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
    @State private var selection: TabRoute
    @State private var paths: [TabRoute: String] = [:]
    @State private var adding = false

    /*
     * Which tab to land on, so a source switch does not throw you out.
     *
     * Changing between the server and the device replaces this whole view —
     * different ledger, different model — and the selection went back to the
     * dashboard. Since that switch is *made* in settings, it closed the screen
     * the user was working in, mid-thought. Carrying the tab across keeps them
     * where they were.
     */
    init(base: URL, initialTab: TabRoute = .overview, onRequestSettings: @escaping () -> Void) {
        self.base = base
        self.onRequestSettings = onRequestSettings
        _selection = State(initialValue: initialTab)
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
    /// Distinguishes one arrival from the next; see `route(to:path:)`.
    @State private var routeNonce = 0

    private func openSettings() {
        UISelectionFeedbackGenerator().selectionChanged()
        onRequestSettings()
    }

    /*
     * Arriving somewhere is not the same as going back to it.
     *
     * The destination screen is rebuilt when its path changes, which is how a
     * deep link lands on the right filter. But tapping a transaction on Aperçu
     * asks for the plain list, and if the tab was already showing that path —
     * left on "À vérifier" from an earlier visit — nothing changed, so nothing
     * reset and the tap appeared to go to the wrong place.
     *
     * A nonce makes every routed arrival a distinct destination, so the screen
     * starts from what the link asked for. Switching tabs with the tab bar does
     * not come through here, and keeps its state as it should.
     */
    private func route(to tab: TabRoute, path: String) {
        guard tab != .settings else { return openSettings() }
        routeNonce &+= 1
        paths[tab] = path.contains("#") ? path : "\(path)#\(routeNonce)"
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

                AccountsScreen(
                    model: model, route: route, onOpenSettings: openSettings,
                    // "/m/accounts/<id>#<nonce>" — the id is what the link was
                    // about, and the nonce only makes each arrival distinct.
                    openAccountId: paths[.accounts]
                        .flatMap { $0.split(separator: "#").first.map(String.init) }
                        .flatMap { path in
                            path.hasPrefix("/m/accounts/")
                                ? String(path.dropFirst("/m/accounts/".count))
                                : nil
                        }
                        .flatMap { $0.isEmpty ? nil : $0 }
                )
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
        // Settings is presented by RootView — see there.
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
