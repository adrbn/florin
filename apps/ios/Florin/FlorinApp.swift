import SwiftUI
import WidgetKit

/// Florin for iPhone.
///
/// Florin's data lives on the user's own machine, so the app points at their
/// server rather than shipping a copy of it. The Aperçu tab is fully native —
/// SwiftUI, Swift Charts, real scroll physics — driven by the server's
/// `/api/v2/overview` feed. The remaining tabs render the v2 web surface in
/// chromeless mode (the server drops its own tab bar when it sees this app's
/// user agent) and are being replaced by native screens one at a time.
/*
 * Droit dans la main, libre une fois ouvert.
 *
 * Un livre de comptes couché sur un téléphone ordinaire ne gagne rien : les
 * écrans sont des colonnes de cartes, et la rotation ne ferait que les
 * écraser. Un iPhone Duo ouvert, lui, est un grand écran — il tourne avec
 * l'appareil comme n'importe quel grand écran, sinon l'app reste debout dans
 * un cadre couché.
 *
 * La règle est ici et non dans l'Info.plist parce qu'elle dépend de l'écran
 * du moment : la liste du plist vaut pour toute l'app, cette méthode est
 * posée à chaque fenêtre.
 */
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        window?.traitCollection.horizontalSizeClass == .regular ? .allButUpsideDown : .portrait
    }
}

@main
struct FlorinApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var server = ServerStore()

    init() {
        /*
         * Ranger le grand livre, sans retenir le premier frame.
         *
         * Lancé ici pour partir le plus tôt possible, mais sur un fil à lui :
         * la première lecture de l'aperçu l'attend, pas l'écran de lancement.
         * Voir `LocalStore.launchPass`.
         */
        _ = LocalStore.launchPass
        // Registered before the first frame, as iOS requires: a handler added
        // later is never called, and the app is simply never woken again.
        BackgroundRefresh.register()
        BackgroundRefresh.schedule()
    }

    @Environment(\.scenePhase) private var scenePhase

    /// Read here, not used here: touching the preference in this scope is what
    /// makes the scene body re-evaluate when settings writes a new language.
    @AppStorage("florin.locale") private var chosenLocale = ""

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
                /*
                 * Remount the tree when the language changes.
                 *
                 * changeLocale writes the preference and clears the string
                 * cache, but a view that has already rendered keeps the text it
                 * was built with — so picking English turned Settings English
                 * and left the five tabs behind it in French until something
                 * happened to rebuild them. Closing and reopening Settings was
                 * enough, which is what made it look intermittent rather than
                 * broken. Reading the preference here is what makes this scene
                 * re-evaluate at all; the id is what discards the stale tree.
                 */
                .id(chosenLocale)
                .overlay { OrientationRefresher() }
        }
        .onChange(of: scenePhase) { _, phase in
            /*
             * Revenir dans l'app suffit à rattraper un paiement.
             *
             * Le filet est relu à l'ouverture de la base, ce qui ne se produit
             * qu'une fois par processus : un paiement fait pendant que Florin
             * dort en arrière-plan n'aurait été repris qu'au prochain
             * démarrage à froid, c'est-à-dire un jour au hasard. Le fichier
             * est presque toujours vide, et le lire ne coûte rien.
             */
            /*
             * Et surtout pas sur le fil principal au lancement.
             *
             * `LocalStore.shared` OUVRE la base la première fois. Appelé ici,
             * au passage en premier plan qui suit immédiatement le lancement,
             * il le faisait sur le fil principal pendant que la passe de
             * lancement écrivait : la pièce se figeait en plein tour, parce
             * que c'est le fil qui la dessine. La passe rend la main, et
             * seulement après on vide la boîte.
             */
            if phase == .active {
                Task {
                    await LocalStore.settled()
                    if let store = LocalStore.shared { WalletInbox.drain(store: store) }
                }
            }
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

/*
 * Replier le Duo doit reposer la question.
 *
 * UIKit garde les orientations qu'on lui a données la dernière fois : un
 * Duo refermé alors qu'il était couché laisserait son petit écran en
 * paysage, c'est-à-dire l'app en travers dans la main. Le changement de
 * classe de taille est le moment exact où la réponse change.
 */
private struct OrientationRefresher: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onChange(of: sizeClass) {
                for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                    scene.keyWindow?.rootViewController?
                        .setNeedsUpdateOfSupportedInterfaceOrientations()
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
    /*
     * Le thème, qui n'est pas l'apparence.
     *
     * Les jetons de `Florin` sont des couleurs dynamiques : leur fonction de
     * résolution relit la palette au rendu. Mais SwiftUI ne sait pas qu'une
     * variable globale a changé — rien ne se repeindrait. D'où la clé
     * d'identité plus bas : changer de thème reconstruit l'arbre, ce qui est
     * exactement ce qu'il faut pour un geste rare et volontaire, et ce qui
     * évite d'avoir à faire observer la palette par cent vues.
     */
    @AppStorage(FlorinPalette.key) private var paletteRaw = FlorinPalette.obsidian.rawValue
    /// Lu ici pour la même raison que la palette : c'est ce qui fait
    /// reconstruire l'arbre quand l'accent change.
    @AppStorage(EdAccent.key) private var accentRaw = EdAccent.terracotta.rawValue
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
    /*
     * Rien ne touche la base avant que la pièce ne tourne.
     *
     * MESURÉ sur le téléphone : `root-body` à 63 ms, `onboarding-read` à
     * 2694 ms. Le compte des comptes est une ligne ; ce qui dure, c'est
     * l'ouverture du fichier pendant que la passe de lancement y écrit ses
     * douze réparations. Et comme ce test est DANS le corps de la vue, le
     * premier rendu l'attendait : deux secondes et demie d'écran noir avant
     * même l'écran de lancement.
     *
     * Le corps rend donc du vide tant que la passe n'a pas rendu la main, et
     * l'écran de lancement, lui, est déjà là pour le couvrir.
     */
    @State private var ledgerReady = false

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
    /*
     * The last version whose notes were *read*, not merely scheduled.
     *
     * The key changed with the bug below: the first build marked the version
     * as seen at the moment the sheet was asked for, so the one launch where
     * the presentation was swallowed burned the flag for good and the notes
     * could never appear again. Anyone who ran that build has a stale mark
     * under the old key; this one starts empty for them, which is right —
     * they never saw the sheet.
     */
    @AppStorage("florin.whatsNew.read") private var seenVersion = ""
    @State private var news: ReleaseNotes.Release?

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
        return ZStack {
            Group {
                if !ledgerReady {
                    // Le temps que la base se range : voir `ledgerReady`.
                    Color.clear
                } else if source == .server, let url = server.resolvedURL {
                    MainTabs(
                        base: url,
                        initialTab: landingTab,
                        onRequestSettings: { showingSettings = true }
                    )
                    .id("\(server.reloadToken)-\(landingTab.rawValue)")
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
                    .id("\(onboarded)-\(landingTab.rawValue)")
                } else if LocalStore.shared == nil {
                    /*
                     * Pas de comptes *et* pas de base : ce n'est pas un
                     * premier lancement, c'est un fichier illisible pour
                     * l'instant. `isComplete` répond zéro dans les deux cas,
                     * et l'onboarding tombait donc par-dessus un grand livre
                     * entier. Celui-ci ne propose rien d'autre que réessayer.
                     */
                    LedgerUnavailable(onRetry: { onboarded = UUID() })
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
                    SetupView(isFirstRun: true, onUseDevice: { wantsServerForm = false })
                } else {
                    OnboardingFlow(
                        onFinish: { onboarded = UUID() },
                        onUseServer: { wantsServerForm = true },
                        onNeedsBank: { connectingBank = true }
                    )
                }
            }
            .id("\(onboarded)-\(paletteRaw)-\(accentRaw)")
            .onChange(of: sourceRaw) { _, _ in switchedSource = true }
            .onChange(of: paletteRaw) { _, chosen in
                // Le réglage écrit déjà la palette ; ceci rattrape le cas où
                // elle a changé ailleurs (une restauration, un autre écran).
                FlorinPalette.use(FlorinPalette(rawValue: chosen) ?? .obsidian)
                WidgetCenter.shared.reloadAllTimelines()
            }
            .onChange(of: accentRaw) { _, chosen in
                EdAccent.use(EdAccent(rawValue: chosen) ?? .terracotta)
                WidgetCenter.shared.reloadAllTimelines()
            }

            // Zero-sized, but it owns the responder chain so a shake reaches
            // us without swizzling UIWindow.
            ShakeDetector().frame(width: 0, height: 0).allowsHitTesting(false)

            // Over the top rather than before it, so the feed is already
            // loading behind the animation instead of starting after it.
            if splashing {
                SplashView {
                    withAnimation(.easeOut(duration: 0.3)) { splashing = false }
                }
                .zIndex(10)
            }
        }
        .tint(Florin.control)
        .preferredColorScheme(appearance.colorScheme)
        .task {
            await LocalStore.settled()
            ledgerReady = true
        }
        .onAppear {
            // The path monitor takes a moment to report; started at launch it
            // has an answer by the time the first fetch asks for one.
            Reachability.begin()
            markFreshInstallUpToDate()
        }
        .onReceive(NotificationCenter.default.publisher(for: .florinShake)) { _ in
            Privacy.shared.toggle()
        }
        // Back to the welcome once the demo ledger is gone: no account left
        // means the onboarding branch is the one RootView now picks.
        .onReceive(NotificationCenter.default.publisher(for: .florinLedgerErased)) { _ in
            showingSettings = false
            onboarded = UUID()
        }
        /*
         * Presented here, above the view that the source switch replaces.
         *
         * It used to be a cover inside MainTabs — the very thing rebuilt when
         * the data source changes — so switching from the server to the device
         * closed the screen where that switch is made. Every time.
         */
        /*
         * Tout l'écran, et le geste quand même.
         *
         * En feuille, le grand cran laisse voir la page du dessous en haut :
         * les réglages sont une page, pas une carte posée sur une autre. En
         * `fullScreenCover`, l'écran est entier mais le balayage vers le bas
         * s'en va avec la feuille — et la seule sortie redevient une croix.
         * Donc les deux : le plein écran ici, et le geste rendu à la main sur
         * le titre de la page (voir `SettingsScreen.edRoot`).
         *
         * Posée ici, et pas dans `MainTabs` : c'est `MainTabs` qu'on
         * reconstruit quand la source des données change, et cet écran est
         * justement celui où on en change.
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
        /*
         * After the splash, and never over the lock: a sheet outranks both an
         * overlay and a cover, so the only thing keeping it in its place is
         * when it is asked for.
         *
         * Asked for *after* the splash has finished fading, too. Presented
         * into the middle of that transition, UIKit drops it on the floor —
         * the binding is set, no sheet appears, and the next launch is a
         * launch like any other.
         */
        .onChange(of: splashing) { _, _ in considerNews(after: 0.45) }
        .onChange(of: lock.locked) { _, _ in considerNews(after: 0.3) }
        .sheet(item: $news, onDismiss: { seenVersion = ReleaseNotes.current }) { release in
            WhatsNewSheet(release: release, t: Strings.device)
        }
    }

    /// Shown once per version, to someone who already had a ledger.
    ///
    /// The version is marked as read when the sheet is dismissed, not here: a
    /// presentation that never happened must not count as one, or the notes
    /// are lost for that version and the reader never learns what changed.
    private func considerNews(after delay: TimeInterval) {
        guard !splashing, !lock.locked, news == nil else { return }
        let ready = source == .server ? server.resolvedURL != nil : LocalOnboarding.isComplete
        guard ready, ReleaseNotes.pending(seen: seenVersion, hasLedger: ready) != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard !splashing, !lock.locked, news == nil else { return }
            news = ReleaseNotes.pending(seen: seenVersion, hasLedger: ready)
        }
    }

    /*
     * A first launch has nothing to be told about.
     *
     * `ReleaseNotes.pending` refuses an empty ledger for exactly this reason,
     * but the ledger stops being empty the moment onboarding writes an
     * account — and onboarding is the first thing a new install does. So the
     * notes for 1.3.6 would open over the dashboard of someone who has never
     * seen 1.3.5, listing changes to a calendar they have not looked at once.
     *
     * The distinction can only be drawn here, before anything is set up:
     * nothing in the database and no server means this install begins at this
     * version, and begins up to date. An upgrade has one or the other and is
     * left alone, so it still gets its notes.
     */
    private func markFreshInstallUpToDate() {
        guard seenVersion.isEmpty, !LocalOnboarding.hasSeenWelcome, server.resolvedURL == nil
        else { return }
        seenVersion = ReleaseNotes.current
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
     * De combien la page qui ARRIVE est encore décalée.
     *
     * Posé sur le `TabView` entier, le décalage valait aussi pour la page qui
     * s'en va : elle sautait de cent points du côté opposé au doigt, d'un
     * coup, et c'est ce saut qu'on lisait — le balayage avait l'air de partir
     * à l'envers. Une page qui s'en va ne bouge pas : elle s'efface. Seule
     * celle qui entre vient du bord.
     */
    @State private var slide: CGFloat = 0

    /// Le décalage du moment — le doigt qui pousse, ou la page qui arrive —
    /// et pour la page affichée seulement.
    private func entering(_ tab: TabRoute) -> CGFloat { tab == selection ? slide : 0 }

    /*
     * Le thème choisit aussi la mise en page.
     *
     * « Éditorial » n'est pas qu'une palette : c'est une autre grammaire
     * d'écran — titres de 64 pt, filets au lieu de cartes, capsule flottante.
     * La lier au thème évite un second réglage à expliquer, et surtout ne
     * supprime rien : les quatre autres thèmes gardent l'app telle quelle.
     *
     * Rien à observer ici : `RootView` reconstruit tout l'arbre sur
     * changement de palette (voir son `.id`), donc la bascule est déjà vue.
     */
    private var editorial: Bool { FlorinPalette.selected == .editorial }

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

    /*
     * Retaper l'onglet où l'on est : retour à son accueil.
     *
     * Un onglet laissé sur un lien profond — « À vérifier », un compte
     * ouvert — n'est pas à son accueil même s'il est déjà en haut. On efface
     * donc d'abord ce que le lien avait demandé, puis `BackToTop` ferme ce
     * qui est posé par-dessus et remonte.
     */
    /*
     * La loupe d'Aperçu : l'onglet, puis le clavier.
     *
     * Aucun chemin n'est écrit — ce n'est pas un lien profond, et un chemin
     * change l'identité d'Activité, donc la reconstruit. On remet d'abord
     * l'onglet à son accueil si un lien l'avait emmené ailleurs.
     *
     * La demande part après la bascule : l'onglet peut n'avoir jamais été
     * ouvert (TabView ne construit que ce qu'on regarde), et un champ qui
     * n'existe pas encore ne prend pas le clavier.
     */
    private func focusSearch() {
        if paths[.activity] != nil { paths[.activity] = nil }
        chrome.reset()
        withAnimation(.snappy(duration: 0.22)) { selection = .activity }
        UISelectionFeedbackGenerator().selectionChanged()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            NotificationCenter.default.post(name: .florinFocusSearch, object: nil)
        }
    }

    private func backHome() {
        if paths[selection] != nil { paths[selection] = nil }
        BackToTop.run()
    }

    /// L'écran Comptes d'origine, avec le compte qu'un lien a demandé :
    /// « /m/accounts/<id>#<nonce> » — l'id est ce que le lien visait, le nonce
    /// ne sert qu'à rendre chaque arrivée distincte.
    private var classicAccounts: some View {
        AccountsScreen(
            model: model, route: route, onOpenSettings: openSettings,
            openAccountId: paths[.accounts]
                .flatMap { $0.split(separator: "#").first.map(String.init) }
                .flatMap { path in
                    path.hasPrefix("/m/accounts/")
                        ? String(path.dropFirst("/m/accounts/".count))
                        : nil
                }
                .flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            /*
             * Un balayage dépile avant de changer d'onglet.
             *
             * Deux fausses pistes avant celle-ci. `scrollDisabled` ne touche
             * pas le balayage d'un `TabView` en style page. Et lui retirer le
             * style quand un relevé s'ouvre marchait — mais changer un
             * `tabViewStyle` à chaud reconstruit le `TabView` entier, donc
             * les cinq pages : c'était l'à-coup qu'on sentait au balayage.
             *
             * Le style ne bouge plus. C'est la sélection qui refuse de
             * changer tant qu'un relevé est posé par-dessus : le balayage
             * part, ne trouve pas d'onglet où aller, et rend la main au
             * retour arrière de la pile.
             */
            TabView(selection: Binding(
                get: { selection },
                set: { next in
                    guard !chrome.detailOpen else { return }
                    selection = next
                }
            )) {
                Group {
                    if editorial {
                        EditorialHome(
                            model: model,
                            onOpenSettings: openSettings,
                            onOpenAccounts: { route(to: .accounts, path: TabRoute.accounts.rootPath) },
                            chrome: chrome
                        )
                    } else {
                        OverviewScreen(
                            model: model, chrome: chrome, route: route, onSearch: focusSearch
                        )
                    }
                }
                .hideSystemTabBar()
                .offset(x: entering(.overview))
                .tag(TabRoute.overview)

                Group {
                    if editorial {
                        EditorialAccounts(
                            model: model,
                            onOpenSettings: openSettings,
                            chrome: chrome
                        )
                    } else {
                        classicAccounts
                    }
                }
                .hideSystemTabBar()
                .offset(x: entering(.accounts))
                .tag(TabRoute.accounts)

                Group {
                    if editorial {
                        EditorialPlan(
                            overview: model, route: route,
                            onOpenSettings: openSettings, chrome: chrome
                        )
                    } else {
                        PlanScreen(overview: model, route: route, onOpenSettings: openSettings)
                    }
                }
                .hideSystemTabBar()
                .offset(x: entering(.plan))
                .tag(TabRoute.plan)

                Group {
                    if editorial {
                        EditorialActivity(
                            overview: model,
                            onOpenSettings: openSettings,
                            startNeedsReview: paths[.activity]?.contains("needsReview") == true,
                            chrome: chrome
                        )
                    } else {
                        ActivityScreen(
                            overview: model,
                            route: route,
                            onOpenSettings: openSettings,
                            startNeedsReview: paths[.activity]?.contains("needsReview") == true
                        )
                    }
                }
                .id(paths[.activity] ?? TabRoute.activity.rootPath)
                .hideSystemTabBar()
                .offset(x: entering(.activity))
                .tag(TabRoute.activity)

                AnalysisScreen(overview: model, route: route, onOpenSettings: openSettings)
                    .hideSystemTabBar()
                    .offset(x: entering(.analysis))
                    .tag(TabRoute.analysis)
            }
            // The system bar is replaced, not decorated: it cannot be centred
            // when minimised and it has no long-press. TabView still owns tab
            // state and lazy loading.
            .ignoresSafeArea(.keyboard)
            /*
             * Le balayage change d'onglet, mais pas le style page.
             *
             * `.page` faisait suivre le contenu sous le doigt, et c'était le
             * meilleur des deux. Seulement il héberge chaque onglet dans son
             * propre pagineur : le `ScrollView` de la page n'est plus celui
             * que l'effet de bord d'iOS 26 regarde, donc les deux bords
             * cessaient de fondre et il ne restait que le fond coupé net —
             * la bande claire en haut comme en bas.
             *
             * Le geste revient sans lui : `edSwipe` lit le balayage et pose
             * la sélection. Le contenu ne suit plus le doigt, il arrive à la
             * fin du geste — c'est le prix des bords, et les bords valent
             * plus cher. Il se tait quand un écran est poussé par-dessus :
             * un balayage dépile d'abord ce qui est posé dessus.
             */
            /*
             * La page suit le doigt, puis l'autre arrive par le même côté.
             *
             * Sans le style page, `TabView` fond d'un onglet à l'autre : le
             * balayage se termine et l'écran change sur place. Et tant que
             * rien ne bougeait avant le relevé du doigt, le geste n'avait pas
             * de réponse — c'est ce silence qu'on prenait pour de la lenteur.
             *
             * Donc les deux moitiés que le style page nous refuse, à la main :
             * la page courante se décale sous le doigt (`track`, amorti au
             * tiers — un pouce de doigt n'est pas un pouce d'écran, et un
             * pagineur freine pareil), et au relevé la nouvelle entre du côté
             * d'où le doigt venait. Au bout de la liste, la résistance monte
             * sans céder : la page frémit et revient.
             */
            .edSwipe(
                edTabOrder, selection: Binding(
                    get: { selection },
                    set: { next in
                        guard !chrome.detailOpen else { return }
                        let here = edTabOrder.firstIndex(of: selection) ?? 0
                        let there = edTabOrder.firstIndex(of: next) ?? 0
                        /*
                         * Le décalage est POSÉ sans animation, et rendu
                         * ensuite.
                         *
                         * `edSwipe` appelle ce bloc à l'intérieur de son
                         * propre `withAnimation` : poser 64 puis demander 0
                         * dans la même transaction, c'est demander une
                         * animation de 0 à 0 — SwiftUI n'a jamais affiché le
                         * 64, et rien ne bougeait. Il faut une image rendue à
                         * 64 avant de rappeler la page au centre.
                         */
                        // `Transaction` tout court est l'opération du grand
                        // livre : ici c'est bien celle de SwiftUI.
                        var instant = SwiftUI.Transaction(animation: nil)
                        instant.disablesAnimations = true
                        withTransaction(instant) {
                            slide = there > here ? 72 : -72
                            selection = next
                        }
                        DispatchQueue.main.async {
                            withAnimation(EdMotion.spring) { slide = 0 }
                        }
                    }
                ),
                enabled: editorial && !chrome.detailOpen,
                track: { dx in
                    guard let dx else {
                        withAnimation(EdMotion.spring) { slide = 0 }
                        return
                    }
                    // Un bout de liste ne cède pas : un dixième du geste, pour
                    // dire qu'il n'y a rien derrière.
                    let here = edTabOrder.firstIndex(of: selection) ?? 0
                    let wall = dx < 0 ? here == edTabOrder.count - 1 : here == 0
                    let pull = min(abs(dx), 260) * (wall ? 0.1 : 0.34)
                    var instant = SwiftUI.Transaction(animation: nil)
                    instant.disablesAnimations = true
                    withTransaction(instant) { slide = dx < 0 ? -pull : pull }
                }
            )

            // Content dissolves into the bottom of the screen rather than
            // running on under the bar and out through the home indicator.
            // En éditorial le masque de `EdPlainEdges` efface déjà le bas.
            if !editorial {
                BottomScrim()
                    .opacity(chrome.sheetOpen ? 0 : 1)
                    .animation(.easeOut(duration: 0.2), value: chrome.sheetOpen)
            }

            if editorial {
                // Pas de voile sous la capsule : la direction éditoriale
                // n'admet aucun dégradé, et le contenu se réserve lui-même
                // les 120 pt du bas.
                /*
                 * Les arrondis de la capsule suivent ceux de l'écran.
                 *
                 * Six items de 46 font une capsule de 292 points de large,
                 * donc une cinquantaine de marge de chaque côté ; elle était
                 * à 62 du bas (34 de zone sûre plus 28). Les deux écarts
                 * n'étaient pas les mêmes, et un coin de 30 de rayon posé
                 * dans un coin d'écran de 55 ne peut les épouser que si
                 * l'écart est égal sur les deux axes. Seize points au lieu de
                 * vingt-huit mettent le bas à cinquante, comme les côtés.
                 */
                /*
                 * Appuyer sur l'onglet déjà ouvert fait quelque chose.
                 *
                 * Écrire la même valeur dans l'état ne déclenche rien, donc
                 * l'appui tombait dans le vide. On l'intercepte : l'écran
                 * concerné dépile s'il a de quoi dépiler, et remonte en haut
                 * sinon — la convention d'iOS, que l'app ne suivait pas
                 * parce que sa barre n'est pas celle du système.
                 */
                EdTabBar(
                    selection: Binding(
                        get: { selection },
                        set: { next in
                            guard next != selection else {
                                NotificationCenter.default.post(
                                    name: .florinTabReselected, object: next
                                )
                                return
                            }
                            selection = next
                        }
                    ),
                    t: t,
                    onAdd: { adding = true }
                )
                    .padding(.bottom, 16)
                    .opacity(chrome.sheetOpen ? 0 : 1)
                    .animation(.easeOut(duration: 0.2), value: chrome.sheetOpen)
            } else {
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
        }
        .onChange(of: selection) { previous, _ in
            chrome.reset()
            // L'onglet quitté se rembobine — voir `EdRewind`.
            chrome.left = previous
        }
        /*
         * Retaper l'onglet où l'on est : retour à son accueil.
         *
         * Un onglet laissé sur un lien profond — « À vérifier », un compte
         * ouvert — n'est pas à son accueil même s'il est en haut. On efface
         * donc d'abord ce que le lien avait demandé, puis `BackToTop` ferme
         * ce qui est posé par-dessus et remonte.
         */
        .onChange(of: chrome.homeTaps) { _, _ in backHome() }
        /*
         * « + » est dans la capsule, donc la feuille est ici.
         *
         * En style d'origine c'est Aperçu qui la présente, depuis son propre
         * bouton ; ici le geste appartient à la coquille, qui est la seule à
         * rester en place quand l'onglet change.
         */
        .sheet(isPresented: $adding) {
            if let data = model.overview {
                AddTransactionSheet(
                    accounts: data.accounts,
                    categories: data.categories,
                    localeTag: data.localeTag,
                    currency: data.currency,
                    t: data.t,
                    submit: { try await model.add($0) },
                    onTransfer: { try await model.addTransfer($0) },
                    onInstalments: { try await model.addInstalments($0) },
                    isLocalLedger: model.base.scheme == "florin-local"
                )
                .edSheet()
            }
        }
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

