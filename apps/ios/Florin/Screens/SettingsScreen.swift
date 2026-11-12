import SwiftUI
import UniformTypeIdentifiers

/// Settings, as iOS does them.
///
/// The web settings page is a good web page — cards, custom toggles, a segmented
/// control — and that is exactly why it felt wrong in the app: on iOS this
/// screen is a grouped `Form`, with system toggles, a system picker and a
/// footer that explains rather than a caption that decorates. Nothing here is
/// styled; letting the platform draw it is the whole point.
struct SettingsScreen: View {
    /*
     * Owns its model rather than borrowing the tabs'.
     *
     * This screen used to be presented from inside MainTabs, which is exactly
     * the view that gets replaced when the data source changes — so switching
     * from the server to the device tore down the screen where that switch is
     * made, every time. It is presented above that now, and reads its own
     * overview: one extra fetch while settings is open, against a screen that
     * closes itself the moment you use it.
     */
    @StateObject private var model: OverviewModel

    init(base: URL, onClose: (() -> Void)? = nil) {
        _model = StateObject(wrappedValue: OverviewModel(base: base))
        self.onClose = onClose
    }
    let onClose: (() -> Void)?
    @EnvironmentObject private var server: ServerStore
    @ObservedObject private var privacy = Privacy.shared

    @AppStorage("florin.appearance") private var appearanceRaw = Appearance.dark.rawValue
    @AppStorage(FlorinPalette.key) private var paletteRaw = FlorinPalette.obsidian.rawValue
    @AppStorage(EdAccent.key) private var accentRaw = EdAccent.terracotta.rawValue
    @AppStorage(EdInks.key) private var inksRaw = EdInks.palette.rawValue
    /*
     * Gardé sur le disque, et pas en `@State`, pour une raison précise.
     *
     * La racine porte `.id("…-\(accentRaw)-\(inksRaw)")` : choisir un accent
     * reconstruit tout l'arbre, c'est ce qui fait que les jeux de jetons se
     * relisent. Un `@State` repartirait donc à zéro à CHAQUE pastille — le
     * panneau se refermerait sous le doigt à la première tape. Posé ici, il
     * traverse la reconstruction, et l'aperçu se regarde pendant qu'on
     * parcourt les trente teintes.
     */
    @AppStorage("florin.settings.accentOpen") private var accentOpen = false
    /// Les mêmes cartes écartées que l'accueil : l'aperçu montre SA pile.
    @AppStorage(HomeCards.key) private var hiddenCards = ""
    @State private var editingServer = false
    @State private var draftServer = ""
    @State private var draftToken = ""
    @State private var serverStatus: ServerStatus = .unknown
    @State private var changingLocale = false
    /// The release notes, re-opened from À propos.
    @State private var news: ReleaseNotes.Release?
    @AppStorage("florin.locale") private var chosenLocale = ""
    @AppStorage(Greeting.key) private var firstName = ""
    @AppStorage(AppLock.key) private var lockOn = false
    @AppStorage("florin.merchantLogos") private var logosOn = true

    private var t: Strings { model.overview?.t ?? .empty }
    @AppStorage("florin.notifications") private var notificationsOn = false
    @State private var readiness: BackgroundRefresh.Readiness?
    @State private var showingBanking = false
    @State private var showingCategories = false
    @State private var showingMerchants = false
    @State private var showingPlaces = false
    @State private var placesOn = LocalPlaces.enabled
    @State private var showingTrash = false
    @State private var showingWalletGuide = false
    @State private var showingSyncLog = false
    @State private var showingImport = false
    @State private var confirmingImport = false
    @State private var confirmingDemoExit = false
    /// Read once: the demo can only end from here, and ending it closes this.
    @State private var demoActive = LocalDemo.isActive
    @State private var showcase = LocalDemo.showcase
    @State private var demoFailure: String?
    /// La clé du service qui déchiffre les libellés de caisse. Vide = rien
    /// ne sort du téléphone.
    @State private var geminiKey = ""
    /// Où en est cette clé : une clé posée sans être essayée ne vaut pas une
    /// clé qui a répondu, et l'écran doit dire laquelle des deux on a.
    @State private var keyState: KeyState = .editing

    enum KeyState: Equatable {
        case editing
        case checking
        /// Le modèle que le service a accepté de nommer.
        case ready(String)
        case failed(String)
    }
    @AppStorage("florin.lastExport") private var lastExport = 0.0
    @State private var exported: URL?
    @State private var picking = false
    @State private var pendingRestore: (url: URL, summary: LocalBackup.Summary)?
    @StateObject private var banking = BankingFlow()
    @State private var task: TaskSheet.State?
    @AppStorage("florin.dataSource") private var sourceRaw = ""

    private var editorial: Bool { FlorinPalette.selected == .editorial }
    /// De combien le titre a été tiré vers le bas. Voir `edRoot`.
    @State private var pull: CGFloat = 0

    /*
     * Treize blocs à la file, ou six portes.
     *
     * Les réglages étaient une seule colonne de treize sections : la clé
     * d'API du lecteur de tickets se trouvait entre les catégories et
     * l'import, le choix du thème venait après les sauvegardes, et pour
     * changer de langue il fallait passer devant la démonstration, la source
     * des données, la banque, Apple Pay et les notifications. Rien n'était
     * caché — tout était simplement au même niveau, donc rien ne se trouvait.
     *
     * Les mêmes sections, derrière six portes nommées par ce qu'on y
     * cherche, chacune disant l'état où elle est. Aucune section n'a été
     * réécrite : ce qui change, c'est l'ordre et la profondeur.
     */
    private enum Page: String, Hashable, Identifiable {
        case data, bank, naming, look, discretion, about
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Backdrop(tint: TabRoute.settings.tint).ignoresSafeArea()

                if editorial { edRoot } else { legacyScroll }
            }
            .navigationDestination(for: Page.self) { page in
                edPage(page)
            }
            .navigationTitle(t("v2.settings.title", "Réglages"))
            .navigationBarTitleDisplayMode(.inline)
            /*
             * En éditorial, la racine n'a pas de barre.
             *
             * `edRoot` écrit « Réglages » en très grand : la barre répétait le
             * mot en 17 pt — et pire, elle portait la marque « Florin », qui
             * n'est pas le titre de cette page. Les pages poussées gardent la
             * leur, pour le chevron de retour.
             */
            .toolbar(editorial ? .hidden : .visible, for: .navigationBar)
            .sheet(isPresented: $showingBanking) { BankingSettings() }
            .sheet(isPresented: $showingCategories) { CategoriesScreen(t: t) }
            .sheet(isPresented: $showingMerchants) { MerchantsScreen(t: t) }
            .sheet(isPresented: $showingPlaces) {
                PlacesScreen(
                    locale: model.overview?.localeTag ?? "fr-FR",
                    currency: model.overview?.currency ?? "EUR",
                    t: t
                )
            }
            .sheet(isPresented: $showingTrash) {
                TrashScreen(
                    t: t,
                    locale: model.overview?.localeTag ?? "fr-FR",
                    currency: model.overview?.currency ?? "EUR",
                    onChange: { await model.load(showSpinner: false) }
                )
            }
            .sheet(isPresented: $showingWalletGuide) { WalletGuideSheet(t: t) }
            .sheet(item: $news) { release in WhatsNewSheet(release: release, t: t) }
            .sheet(isPresented: $showingSyncLog) {
                SyncLogScreen(t: t, locale: model.overview?.localeTag ?? "fr-FR")
            }
            .sheet(isPresented: $showingImport) {
                ImportSheet(
                    t: t,
                    locale: model.overview?.localeTag ?? "fr-FR",
                    currency: model.overview?.currency ?? "EUR",
                    onDone: { await model.load(showSpinner: false) }
                )
            }
            /*
             * A cover, so nothing behind it can be touched mid-write.
             *
             * The import used to report itself by rewriting a settings row —
             * turning a list of settings into a progress bar, and saying
             * nothing at all at the end. A job that rewrites every account and
             * every transaction should hold the screen while it does, and say
             * what it did when it stops.
             */
            .fullScreenCover(isPresented: Binding(
                get: { task != nil },
                set: { if !$0 { task = nil } }
            )) {
                if let state = task {
                    TaskSheet(
                        title: t("v2.settings.importTitle", "Import depuis votre serveur"),
                        state: state
                    ) {
                        var succeeded = false
                        if case .success = state { succeeded = true }
                        task = nil
                        // Land where the result is — the dashboard, not the
                        // settings screen the job was started from.
                        if succeeded { onClose?() }
                    }
                }
            }
            .sheet(isPresented: Binding(
                get: { banking.mapping != nil },
                set: { if !$0 { banking.mapping = nil } }
            )) {
                if let found = banking.mapping {
                    BankMappingSheet(
                        accounts: found,
                        candidates: banking.candidates,
                        locale: model.overview?.localeTag ?? "fr-FR",
                        currency: model.overview?.currency ?? "EUR",
                        onConfirm: { answers in
                            Task {
                                await banking.confirmMapping(answers)
                                await model.load(showSpinner: false)
                            }
                        },
                        onCancel: { banking.mapping = nil }
                    )
                }
            }
            /*
             * Destructive, so it says so before doing it.
             *
             * The import replaces this device's ledger rather than merging
             * into it, which is the only way it can be correct — but that is
             * not something to discover afterwards from a net worth that
             * doubled.
             */
            .alert(
                t("v2.settings.importConfirm", "Remplacer les données locales ?"),
                isPresented: $confirmingImport
            ) {
                Button(t("v2.settings.importReplace", "Remplacer"), role: .destructive) {
                    Task { await importFromServer() }
                }
                Button(t("v2.common.cancel", "Annuler"), role: .cancel) {}
            } message: {
                Text(t(
                    "v2.settings.importConfirmBody",
                    "Les comptes, opérations et catégories de cet appareil seront effacés et remplacés par ceux du serveur. Votre connexion bancaire est conservée."
                ))
            }
            // The system share sheet, so the copy lands wherever the person
            // already keeps things — Fichiers, iCloud Drive, a mail to
            // themselves — rather than in a folder only this app knows about.
            .sheet(isPresented: Binding(
                get: { exported != nil },
                set: { if !$0 { exported = nil } }
            )) {
                if let exported { ShareSheet(items: [exported]) }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.data]) { result in
                guard case let .success(url) = result else { return }
                guard let summary = LocalBackup.inspect(url) else {
                    task = .failure(LocalBackup.Failure.notALedger.localizedDescription)
                    return
                }
                pendingRestore = (url, summary)
            }
            /*
             * What is in the file, before it goes in.
             *
             * A restore replaces the ledger, so what the file holds is what
             * the phone will hold. "23 opérations" where two thousand were
             * expected is how someone finds out they picked last year's copy,
             * and that has to be seen before the tap, not after.
             */
            .alert(
                t("v2.settings.restoreConfirm", "Restaurer cette sauvegarde ?"),
                isPresented: Binding(
                    get: { pendingRestore != nil },
                    set: { if !$0 { pendingRestore = nil } }
                )
            ) {
                Button(t("v2.settings.restoreAction", "Restaurer"), role: .destructive) {
                    if let url = pendingRestore?.url { Task { await restore(url) } }
                    pendingRestore = nil
                }
                Button(t("v2.common.cancel", "Annuler"), role: .cancel) { pendingRestore = nil }
            } message: {
                Text(t(
                    "v2.settings.restoreConfirmBody",
                    "Ce fichier contient {transactions} opérations et {accounts} comptes. Il remplace ce qui est sur ce téléphone — le grand livre actuel est d'abord mis de côté dans un fichier.",
                    [
                        "transactions": pendingRestore?.summary.transactions ?? 0,
                        "accounts": pendingRestore?.summary.accounts ?? 0,
                    ]
                ))
            }
            .toolbar {
                if !editorial {
                    ToolbarItem(placement: .principal) { Wordmark(size: 17) }
                }
                if let onClose {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(t("v2.common.close", "Fermer"), action: onClose)
                    }
                }
            }
            /*
             * Actually read the feed this screen owns.
             *
             * The model was built and never asked to load, so `overview` stayed
             * nil for the life of the screen. Two things followed, and both
             * looked like separate bugs: the language picker is disabled while
             * the payload is missing, so it sat permanently greyed out and no
             * tap on it did anything — and every `t(...)` here fell through to
             * its hard-coded French, so the screen stayed French whatever
             * language had been chosen.
             */
            .task {
                await model.load(showSpinner: false)
                readiness = await BackgroundRefresh.readiness()
            }
        }
    }

    private var legacyScroll: some View {
        ScrollView {
            VStack(spacing: 24) {
                demoSection
                sourceSection
                bankSection
                walletSection
                receiptsSection
                categoriesSection
                importSection
                notificationsSection
                backupSection
                displaySection
                privacySection
                serverEntrySection
                aboutSection
            }
            .padding(.horizontal, Florin.gutter)
            .padding(.top, 10)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - L'éditorial : six portes

    private var edRoot: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    EdHero(text: t("v2.settings.title", "Réglages"), size: 44)
                    Spacer(minLength: 8)
                    if let onClose {
                        EdIconButton(
                            symbol: "xmark", label: t("v2.common.close", "Fermer"),
                            action: onClose
                        )
                        .padding(.trailing, -10)
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 14)
                /*
                 * On tire le TITRE vers le bas pour fermer.
                 *
                 * L'écran est posé en plein écran, pas en feuille : il prend
                 * toute la fenêtre, et perd du même coup le glissement qu'une
                 * feuille offre gratuitement. Le geste est rendu ici plutôt
                 * que sur la page entière, parce que sur la page il
                 * disputerait le toucher au défilement — le titre, lui, ne
                 * défile rien.
                 */
                .contentShape(Rectangle())
                /*
                 * Coordonnées GLOBALES, et c'est tout le correctif.
                 *
                 * Le geste déplace la vue à laquelle il est attaché. En repère
                 * local il mesure donc dans un repère qu'il fait bouger : le
                 * doigt descend de dix points, la vue descend de dix points,
                 * le doigt est revenu à sa place dans le repère, la
                 * translation retombe à zéro, la vue remonte — et ça repart.
                 * La vue tremblait à la fréquence d'affichage. Le repère de
                 * l'écran, lui, ne bouge pas.
                 */
                .gesture(
                    DragGesture(coordinateSpace: .global)
                        .onChanged { move in pull = max(0, move.translation.height) }
                        .onEnded { move in
                            let far = move.translation.height > 110
                                || move.predictedEndTranslation.height > 240
                            withAnimation(EdMotion.spring) { pull = 0 }
                            if far { onClose?() }
                        }
                )

                edDoor(.data, "tray.full", t("v2.settings.data", "Données"), dataState)
                EdRule()
                edDoor(.bank, "building.columns", t("v2.settings.bank", "Banque"), bankState)
                EdRule()
                edDoor(.naming, "tag", t("v2.settings.naming", "Catégories et marchands"), nil)
                EdRule()
                /*
                 * La porte dit ce qu'il y a derrière, pas son rayon.
                 *
                 * « Apparence · Éditorial » se lit comme le sombre/clair et
                 * rien d'autre : le choix de la couleur d'accent, qui est le
                 * réglage le plus amusant de l'app, était invisible depuis
                 * l'accueil des réglages. Le nom de l'accent dans le
                 * sous-titre suffit à dire qu'il se choisit quelque part.
                 */
                edDoor(
                    .look, "paintbrush", t("v2.settings.appearance", "Apparence"),
                    paletteRaw == FlorinPalette.editorial.rawValue
                        ? "\(FlorinPalette.selected.name) · \(EdAccent.selected.name)"
                        : FlorinPalette.selected.name
                )
                EdRule()
                edDoor(
                    .discretion, "eye.slash", t("v2.settings.discretion", "Discrétion"),
                    privacy.hidden ? t("v2.settings.hideAmounts", "Masquer les montants") : nil
                )
                EdRule()
                edDoor(.about, "info.circle", t("v2.settings.about", "À propos"), Self.version)
            }
            .padding(.horizontal, Ed.gutter)
            .padding(.bottom, 60)
        }
        .offset(y: pull)
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    /*
     * Une porte dit où elle mène ET ce qu'on y a laissé.
     *
     * « Banque » seul oblige à entrer pour savoir si la connexion tient ;
     * « Banque — Configurée » répond depuis le seuil. C'est la seule chose
     * qu'un menu à deux niveaux doit rendre : la réponse sans le détour.
     */
    private func edDoor(
        _ page: Page, _ symbol: String, _ title: String, _ state: String?
    ) -> some View {
        NavigationLink(value: page) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Florin.text2)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17))
                        .foregroundStyle(Florin.text)
                    if let state {
                        Text(state)
                            .font(.system(size: 13))
                            .foregroundStyle(Florin.text3)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Florin.text3)
            }
            /*
             * La même hauteur pour les six, qu'elles aient un état ou non.
             *
             * La ligne se taillait sur son contenu : deux lignes de texte pour
             * « Données » ou « Banque », une seule pour « Catégories » et pour
             * « Discrétion » quand rien n'est masqué — dix-huit points de
             * moins, visibles immédiatement dans une colonne de six filets
             * censés battre la mesure. La hauteur est celle de la ligne la
             * plus haute, et c'est le texte qui se centre dedans.
             */
            .frame(height: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(.edPress)
    }

    private var dataState: String {
        model.base.scheme == "florin-local"
            ? t("v2.settings.sourceDevice", "Sur l'appareil")
            : (model.base.host ?? t("v2.settings.sourceServer", "Serveur"))
    }

    private var bankState: String {
        BankingFlow.isConfigured
            ? t("v2.settings.bankingReady", "Configurée")
            : t("v2.settings.bankingMissing", "Non configurée")
    }

    /// Derrière chaque porte, les sections d'origine — dans l'ordre où on en
    /// a besoin, et plus dans celui où elles ont été écrites.
    @ViewBuilder
    private func edPage(_ page: Page) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                switch page {
                case .data:
                    sourceSection
                    serverEntrySection
                    importSection
                    backupSection
                    demoSection
                case .bank:
                    bankSection
                    notificationsSection
                    walletSection
                case .naming:
                    categoriesSection
                    receiptsSection
                case .look:
                    displaySection
                case .discretion:
                    privacySection
                case .about:
                    aboutSection
                }
            }
            .padding(.horizontal, Florin.gutter)
            .padding(.top, 10)
            .padding(.bottom, 80)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Backdrop(tint: TabRoute.settings.tint).ignoresSafeArea())
        .navigationTitle(edPageTitle(page))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func edPageTitle(_ page: Page) -> String {
        switch page {
        case .data: return t("v2.settings.data", "Données")
        case .bank: return t("v2.settings.bank", "Banque")
        case .naming: return t("v2.settings.naming", "Catégories et marchands")
        case .look: return t("v2.settings.appearance", "Apparence")
        case .discretion: return t("v2.settings.discretion", "Discrétion")
        case .about: return t("v2.settings.about", "À propos")
        }
    }

    // MARK: - Sections

    /*
     * Asked for where it means something.
     *
     * A permission prompt on first launch is a question about a thing the app
     * has not done yet, and the answer is usually no. Here it sits beside the
     * bank connection it depends on, off until someone turns it on.
     */
    @ViewBuilder
    private var notificationsSection: some View {
        if model.base.scheme == "florin-local" {
            SettingsGroup(
                title: t("v2.settings.notifications", "Notifications"),
                footer: readiness.map { state -> String in
                    if !state.notificationsAllowed && notificationsOn {
                        return t(
                            "v2.settings.notifyBlocked",
                            "Les notifications sont refusées pour Florin dans les réglages d'iOS."
                        )
                    }
                    if !state.backgroundAllowed {
                        return t(
                            "v2.settings.backgroundOff",
                            "L'actualisation en arrière-plan est désactivée pour Florin dans les réglages d'iOS — Florin ne pourra pas interroger votre banque tout seul."
                        )
                    }
                    return t(
                        "v2.settings.notificationsHint",
                        "Florin interroge votre banque le matin et vous dit ce qui est arrivé pendant la nuit."
                    )
                } ?? t(
                    "v2.settings.notificationsHint",
                    "Florin interroge votre banque le matin et vous dit ce qui est arrivé pendant la nuit."
                )
            ) {
                Toggle(isOn: Binding(
                    get: { notificationsOn },
                    set: { wanted in
                        guard wanted else { notificationsOn = false; return }
                        Task {
                            notificationsOn = await BackgroundRefresh.requestPermission()
                            if notificationsOn { BackgroundRefresh.schedule() }
                        }
                    }
                )) {
                    HStack(spacing: 11) {
                        Image(systemName: "bell")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Florin.accent)
                            .frame(width: 20)
                        Text(t("v2.settings.notifications", "Notifications"))
                            .font(.system(size: 15.5))
                            .foregroundStyle(Florin.text)
                    }
                }
                .tint(Florin.control)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    /*
     * Sauvegarde.
     *
     * iCloud's own backup carries the ledger now, and that is the one that
     * matters — but it is invisible from in here: iOS will not tell an app
     * whether backups are on, when the last one ran, or let it ask for one. So
     * this says what is true and offers the copy the app can actually stand
     * behind, with a date it earned rather than a status light wired to
     * nothing.
     */
    @ViewBuilder
    private var backupSection: some View {
        if model.base.scheme == "florin-local" {
            SettingsGroup(
                title: t("v2.settings.backup", "Sauvegarde"),
                footer: t(
                    "v2.settings.backupHint",
                    "Vos données sont incluses dans la sauvegarde iCloud de votre iPhone. iOS n'indique pas aux apps quand elle a lieu."
                )
            ) {
                SettingsRow(
                    label: t("v2.settings.exportCopy", "Exporter une copie"),
                    symbol: "square.and.arrow.up",
                    action: exportCopy
                ) {
                    if lastExport > 0 {
                        Text(
                            Date(timeIntervalSince1970: lastExport),
                            format: .relative(presentation: .named)
                        )
                        .font(.system(size: 14))
                        .foregroundStyle(Florin.text2)
                    }
                }
                Hairline()
                SettingsRow(
                    label: t("v2.settings.restoreCopy", "Restaurer une copie"),
                    symbol: "square.and.arrow.down",
                    action: { picking = true }
                )
            }
        }
    }

    private func exportCopy() {
        guard let store = LocalStore.shared else { return }
        do {
            exported = try LocalBackup.export(from: store)
            lastExport = Date().timeIntervalSince1970
        } catch {
            task = .failure(error.localizedDescription)
        }
    }

    /// Restore, once the user has seen what is in the file they picked.
    private func restore(_ url: URL) async {
        guard let store = LocalStore.shared else { return }
        task = .running(t("v2.settings.restoring", "Restauration…"))
        do {
            let after = try LocalBackup.restore(from: url, into: store)
            await model.load(showSpinner: false)
            task = .success(
                title: t("v2.settings.restoreDone", "Sauvegarde restaurée"),
                detail: t(
                    "v2.settings.restoreSummary",
                    "Votre grand livre compte maintenant {transactions} opérations et {accounts} comptes — exactement ce que contenait le fichier.",
                    ["transactions": after.transactions, "accounts": after.accounts]
                )
            )
        } catch {
            task = .failure(error.localizedDescription)
        }
    }

    private var privacySection: some View {
        SettingsGroup(
            title: t("v2.settings.discretion", "Discrétion"),
            footer: t(
                "v2.settings.discretionHint",
                "Le verrou demande votre visage à chaque ouverture. Secouer le téléphone masque les montants ou les réaffiche — ça cache, ça ne verrouille pas."
            )
        ) {
            if let method = AppLock.biometryName {
                Toggle(isOn: Binding(
                    get: { lockOn },
                    set: { on in
                        lockOn = on
                        AppLock.shared.set(on)
                    }
                )) {
                    HStack(spacing: 11) {
                        Image(systemName: "faceid")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Florin.accent)
                            .frame(width: 20)
                        Text(t(
                            "v2.settings.lock", "Verrouiller avec {method}",
                            ["method": method]
                        ))
                        .font(.system(size: 15.5))
                        .foregroundStyle(Florin.text)
                    }
                }
                .tint(Florin.control)
                .padding(.horizontal, Florin.gutter)
                .padding(.vertical, 11)
                Hairline()
            }

            Toggle(
                isOn: Binding(get: { privacy.hidden }, set: { privacy.set($0) })
            ) {
                HStack(spacing: 11) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Florin.accent)
                        .frame(width: 20)
                    Text(t("v2.settings.hideAmounts", "Masquer les montants"))
                        .font(.system(size: 15.5))
                        .foregroundStyle(Florin.text)
                }
            }
            .tint(Florin.control)
            .padding(.horizontal, Florin.gutter)
            .padding(.vertical, 11)
        }
    }

    /*
     * How it looks, in one card.
     *
     * Theme and language were two segmented controls in two titled, footered
     * cards, 24 points apart — the same widget twice, 215 points of screen for
     * two choices, and both footers explaining that the setting also applies to
     * "les écrans web de l'app", which is a fact about how this is built rather
     * than anything the person needs. Two rows with their value on the right,
     * the way the system does it.
     */
    private var displaySection: some View {
        SettingsGroup(title: t("v2.settings.display", "Affichage")) {
            nameRow
            Hairline()
            choiceRow(
                t("v2.settings.appearance", "Apparence"),
                symbol: "circle.lefthalf.filled",
                selection: $appearanceRaw,
                options: [
                    (Appearance.dark.rawValue, t("v2.settings.dark", "Sombre")),
                    (Appearance.light.rawValue, t("v2.settings.light", "Clair")),
                    (Appearance.system.rawValue, t("v2.settings.system", "Système")),
                ]
            )
            Hairline()
            themeRow
            if paletteRaw == FlorinPalette.editorial.rawValue {
                Hairline()
                accentRow
            }
            Hairline()
            choiceRow(
                t("v2.settings.language", "Langue"),
                symbol: "globe",
                selection: localeBinding,
                options: [
                    ("fr", "Français"), ("en", "English"), ("nl", "Nederlands"),
                    ("it", "Italiano"), ("es", "Español"), ("ca", "Català"), ("de", "Deutsch"),
                    ("pt", "Português"), ("tr", "Türkçe"),
                ],
                busy: changingLocale
            )
        }
    }

    /// A row that states a choice and opens a menu to change it.
    /*
     * Les thèmes se montrent, ils ne se lisent pas.
     *
     * Un menu déroulant aurait suffi à les énumérer, et n'aurait rien dit :
     * « Sépia » ne décrit pas une couleur à quelqu'un qui ne l'a pas vue. Une
     * pastille par thème — le fond, une carte dessus, l'accent — et le choix
     * se fait sur ce qu'on verra.
     *
     * Le thème ne remplace pas l'apparence juste au-dessus : il la complète.
     * Papier en clair est du noir sur blanc, Papier en sombre du blanc sur
     * noir. Les deux réglages se composent.
     */
    private var themeRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Florin.text2)
                    .frame(width: 22)
                Text(t("v2.settings.theme", "Thème"))
                    .font(.system(size: 16))
                    .foregroundStyle(Florin.text)
                Spacer(minLength: 0)
            }
            /*
             * Deux familles, pas cinq couleurs.
             *
             * Les cinq thèmes se suivaient dans une seule rangée, sous cinq
             * aperçus qui se ressemblaient : le choix se lisait comme « quelle
             * teinte », alors que quatre d'entre eux sont la même mise en page
             * dans quatre fonds et que le cinquième est une autre maison —
             * pas de cartes, pas d'emoji, du type et des filets.
             *
             * Deux groupes nommés, et l'aperçu de chacun dessine ce qu'il
             * fait (voir `ThemeSwatch`). Un intitulé coûte deux lignes et
             * évite d'avoir à essayer les cinq pour comprendre.
             */
            themeFamily(t("v2.settings.themeClassic", "Classique"))
            HStack(spacing: 8) {
                ForEach(FlorinPalette.allCases.filter { $0 != .editorial }) { choice in
                    themeSwatch(choice)
                }
            }
            .padding(.leading, 33)

            themeFamily(t("v2.settings.themeMinimal", "Minimaliste"))
                .padding(.top, 6)
            HStack(spacing: 10) {
                themeSwatch(.editorial)
                    .frame(width: 72)
                Text(t("v2.settings.themeMinimalHint",
                       "Ni cartes ni emoji : du texte, des filets, une seule couleur."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Florin.text3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.leading, 33)

            /*
             * L'accent, et seulement là où il se voit.
             *
             * Les quatre autres thèmes posent de la couleur partout : un
             * réglage d'accent y changerait une teinte parmi dix. Éditorial
             * n'en a qu'une, sur le héros et l'alerte — c'est le seul où
             * choisir veut dire quelque chose, donc le seul qui le propose.
             */
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    /*
     * L'accent : une ligne repliée, pas un quart d'écran déroulé.
     *
     * La carte « Affichage » empilait, d'un coup et sans qu'on l'ait demandé,
     * trente pastilles, deux gélules, une phrase d'explication et un aperçu
     * à quatre bandes — sous trois autres réglages. Sept contrôles dans une
     * carte : on ne lit plus, on balaie.
     *
     * Repliée, la ligne dit l'essentiel — le nom de la teinte et un rond de
     * cette teinte — et c'est tout ce qu'on vient vérifier neuf fois sur dix.
     * Dépliée, elle montre exactement ce qu'elle montrait avant.
     */
    @ViewBuilder
    private var accentRow: some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) { accentOpen.toggle() }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "drop")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Florin.text2)
                    .frame(width: 22)
                Text(t("v2.settings.accent", "Couleur d'accent"))
                    .font(.system(size: 16))
                    .foregroundStyle(Florin.text)
                Spacer(minLength: 8)
                Circle()
                    .fill(Florin.accent)
                    .frame(width: 15, height: 15)
                Text(EdAccent.selected.name)
                    .font(.system(size: 15))
                    .foregroundStyle(Florin.text2)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Florin.text3)
                    .rotationEffect(.degrees(accentOpen ? 180 : 0))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if accentOpen {
            VStack(alignment: .leading, spacing: 12) {
                /*
                 * Une grille, parce qu'une rangée ne tient plus.
                 *
                 * Six pastilles tenaient sur une ligne ; trente, non — et les
                 * faire défiler horizontalement cacherait la moitié du choix
                 * derrière un geste que rien n'annonce.
                 */
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 40), spacing: 10)],
                    alignment: .leading, spacing: 12
                ) {
                    ForEach(EdAccent.allCases) { choice in
                        accentSwatch(choice)
                    }
                }
                inksRow
                inksHint
                accentPreview
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    /*
     * Palette ou dégradé — deux gestes, pas une amélioration de l'autre.
     *
     * Huit teintes franches disent huit catégories ; une encre diluée huit
     * fois dit un thème. Le premier se lit mieux d'un coup d'œil, le second
     * se tient mieux. On ne tranche pas pour quelqu'un d'autre.
     */
    private var inksRow: some View {
        HStack(spacing: 6) {
            ForEach(EdInks.allCases) { choice in
                let chosen = choice.rawValue == inksRaw
                Button {
                    guard !chosen else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    EdInks.use(choice)
                    inksRaw = choice.rawValue
                } label: {
                    Text(inkName(choice))
                        .font(.system(size: 13, weight: chosen ? .semibold : .regular))
                        .foregroundStyle(chosen ? Florin.bg : Florin.text2)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(
                            Capsule().fill(chosen ? Florin.text : Florin.surface2)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    /*
     * Ce que le mot « Palette » ne dit pas.
     *
     * La grille d'accents est juste au-dessus, donc on lit « Palette » comme
     * « la palette que je viens de choisir » — et on attend que les cartes
     * changent de couleur. Elles ne changent pas : en palette, les huit
     * encres sont un jeu FIXE, et l'accent ne touche que les boutons. Les
     * deux mots nomment la forme du jeu (plusieurs couleurs / une seule
     * déclinée), pas qui le décide. Une ligne le dit, plutôt que de laisser
     * trente pastilles promettre ce qu'un mode ne fait pas.
     */
    private var inksHint: some View {
        Text(EdInks.selected == .gradient
            ? t("v2.settings.inks.gradientHint",
                "Les cartes prennent huit nuances de la couleur choisie.")
            : t("v2.settings.inks.paletteHint",
                "Les cartes gardent huit couleurs fixes ; l'accent ne touche que les boutons."))
            .font(.system(size: 12.5))
            .foregroundStyle(Florin.text3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func inkName(_ choice: EdInks) -> String {
        switch choice {
        case .palette: return t("v2.settings.inks.palette", "Palette")
        case .gradient: return t("v2.settings.inks.gradient", "Dégradé")
        }
    }

    /*
     * L'aperçu, montré là où on choisit.
     *
     * Choisir une couleur et devoir fermer les réglages pour savoir à quoi
     * elle ressemble, c'est un aller-retour par pastille — trente pastilles,
     * trente allers-retours. Quatre bandes suffisent à dire ce que l'accent
     * fait : la plus dense, la plus pâle, et deux crans entre.
     *
     * Rien à brancher pour que ça suive : les jetons de `Florin.series`
     * relisent la palette au rendu, et la racine de l'app porte déjà
     * `.id(accentRaw)`. Appuyer sur une pastille reconstruit l'arbre, donc
     * l'aperçu avec.
     */
    private var accentPreview: some View {
        VStack(alignment: .leading, spacing: 9) {
            inkBands
            // Le bouton, pour que l'aperçu montre aussi ce que l'accent fait
            // hors des cartes : le héros, et le creux derrière lui.
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text(t("v2.nav.add", "Ajouter"))
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Florin.onAccent)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(Capsule().fill(Florin.accent))

                Capsule()
                    .fill(Florin.accent.opacity(0.18))
                    .frame(width: 34, height: 22)
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Florin.surface)
        )
    }

    /*
     * Les quatre premières cartes de l'accueil, pas quatre rangs au hasard.
     *
     * L'aperçu prenait les rangs 0, 2, 4 et 6 de la série avec des montants
     * inventés. Il a la forme de la pile de l'accueil, donc il se lit comme
     * une promesse — et la promesse était fausse : l'accueil attribue ses
     * rangs par compte (un choix à la main, sinon le hachage de
     * l'identifiant), si bien qu'aucune des quatre bandes ne tombait sur la
     * carte en face. Choisir une pastille, voir quatre couleurs, puis en
     * trouver quatre autres chez soi : c'est pire que pas d'aperçu.
     *
     * Il passe donc par `HomeCards.palette`, exactement comme l'accueil, et
     * sur les mêmes comptes retenus. Les montants inventés ne servent plus
     * que quand il n'y a pas encore de compte.
     */
    private var inkBands: some View {
        let hidden = HomeCards.hidden(hiddenCards)
        let all = (model.overview?.accounts ?? []).filter {
            !$0.isArchived && $0.isIncludedInNetWorth && !hidden.contains($0.id)
        }
        let tints = HomeCards.palette(all)
        let shown = Array(all.prefix(4))
        return VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, account in
                band(
                    tone: tints[account.id] ?? Florin.seriesColor(for: account.id),
                    name: account.name,
                    value: account.displayValue
                )
            }
            if shown.isEmpty {
                ForEach(Array([0, 2, 4, 6].enumerated()), id: \.element) { index, rank in
                    band(tone: Florin.series[rank], name: "", value: Self.sample[index])
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func band(tone: Color, name: String, value: Double) -> some View {
        let ink = Florin.readable(on: tone)
        return HStack(spacing: 6) {
            Circle()
                .fill(ink.opacity(0.55))
                .frame(width: 5, height: 5)
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(Money.compact(
                value,
                locale: model.overview?.localeTag ?? "fr-FR",
                currency: model.overview?.currency ?? "EUR"
            ))
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .frame(maxWidth: .infinity)
        .background(tone)
    }

    /// Des montants inventés, pour l'installation qui n'a pas encore de compte.
    private static let sample: [Double] = [2140, 860, 415, 95]

    private func accentSwatch(_ choice: EdAccent) -> some View {
        let chosen = choice.rawValue == accentRaw
        return Button {
            guard !chosen else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            EdAccent.use(choice)
            accentRaw = choice.rawValue
        } label: {
            Circle()
                .fill(choice.tone.color)
                .frame(width: 30, height: 30)
                .overlay(
                    Circle().strokeBorder(
                        chosen ? Florin.text : Florin.text.opacity(0.14),
                        lineWidth: chosen ? 2 : 1
                    )
                    .padding(-3)
                )
                .accessibilityLabel(Text(choice.name))
        }
        .buttonStyle(.plain)
    }

    /// L'intitulé d'une famille de thèmes — voir `themeRow`.
    private func themeFamily(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Florin.text3)
            .padding(.leading, 33)
    }

    private func themeSwatch(_ choice: FlorinPalette) -> some View {
        ThemeSwatch(choice: choice, chosen: choice.rawValue == paletteRaw) {
            FlorinPalette.use(choice)
            paletteRaw = choice.rawValue
        }
    }

    /*
     * Le prénom, pour que l'accueil puisse dire bonjour à quelqu'un.
     *
     * Un champ dans la ligne, pas un écran à lui : c'est un mot, il se tape où
     * on le lit. Vide est une réponse valable — l'accueil dit alors « Bonjour »
     * tout court, comme avant.
     */
    private var nameRow: some View {
        SettingsRow(label: t("v2.settings.firstName", "Votre prénom"), symbol: "person") {
            TextField(
                t("v2.settings.firstNameHint", "Sert à vous saluer sur l'accueil."),
                text: $firstName,
                prompt: Text(verbatim: "—").foregroundStyle(Florin.text3)
            )
            .labelsHidden()
            .font(.system(size: 15))
            .foregroundStyle(Florin.text2)
            .multilineTextAlignment(.trailing)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .frame(maxWidth: 170)
        }
    }

    private func choiceRow(
        _ label: String,
        symbol: String,
        selection: Binding<String>,
        options: [(String, String)],
        busy: Bool = false
    ) -> some View {
        SettingsRow(label: label, symbol: symbol) {
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Menu {
                    ForEach(options, id: \.0) { value, title in
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            selection.wrappedValue = value
                        } label: {
                            if value == selection.wrappedValue {
                                Label(title, systemImage: "checkmark")
                            } else {
                                Text(title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(options.first { $0.0 == selection.wrappedValue }?.1 ?? "")
                            .font(.system(size: 15))
                            .foregroundStyle(Florin.text2)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Florin.text3)
                    }
                    .contentShape(Rectangle())
                }
            }
        }
    }

    /// Vrai quand basculer veut dire quelque chose : un serveur est configuré,
    /// ou l'app en lit déjà un.
    private var serverIsRelevant: Bool {
        sourceBinding.wrappedValue == .server || server.resolvedURL != nil
    }

    @ViewBuilder
    private var sourceSection: some View {
        /*
         * Le sélecteur n'est pas dans une carte, et c'est délibéré.
         *
         * `SettingsGroup` pose une surface autour de son contenu, et un
         * `Picker` segmenté dessine déjà la sienne : deux boîtes emboîtées,
         * dont l'intérieure était la seule à répondre au doigt. Les lignes du
         * serveur, elles, gardent la leur — ce sont des lignes de réglage
         * comme les autres.
         *
         * Le choix commande ce qui en dépend : une adresse de serveur ne veut
         * rien dire sur le grand livre local, et la configuration bancaire ne
         * veut rien dire sur un serveur qui fait la sienne.
         */
        if serverIsRelevant {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: t("v2.settings.source", "Données"))
                    .padding(.horizontal, 4)

                Picker("", selection: sourceBinding) {
                    ForEach(DataSource.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(sourceBinding.wrappedValue.detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Florin.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)

                if sourceBinding.wrappedValue == .server {
                    SettingsGroup { serverRows }
                        .padding(.top, 4)
                }
            }
        }
    }

    /*
     * Une porte, pas un carrefour.
     *
     * Le choix « mon serveur / cet appareil » était la toute première chose de
     * l'écran. Quelqu'un qui vient d'installer Florin y rencontrait une
     * question qu'il ne peut pas comprendre avant tout le reste — et le
     * mauvais côté mène à un formulaire réclamant une URL et un jeton d'API.
     *
     * « Cet appareil » est le défaut, et c'est ce que la fiche App Store
     * promet : rien à commander. Une commande ne sert qu'à en partir, donc
     * elle vit en bas, sous forme d'une ligne, et ne devient un sélecteur que
     * le jour où un serveur existe — c'est-à-dire le jour où basculer a un
     * sens.
     */
    @ViewBuilder
    private var serverEntrySection: some View {
        if !serverIsRelevant {
            SettingsGroup(footer: DataSource.server.detail) {
                SettingsRow(
                    label: t("v2.settings.useServer", "Utiliser mon serveur Florin"),
                    symbol: "network",
                    action: { sourceBinding.wrappedValue = .server }
                )
            }
        }
    }

    /*
     * One card was doing three jobs.
     *
     * Where the ledger lives, how the bank reaches it and how a file gets in
     * were eight rows in a single stack under one heading — a list you read to
     * the end to find out what was in it. They are three things, and the person
     * looking for one of them is not looking for the other two.
     */
    /// Apple Pay payments recorded as they happen — a Shortcuts automation,
    /// explained. Device ledger only: the action refuses a server's.
    @ViewBuilder
    private var walletSection: some View {
        if sourceBinding.wrappedValue != .server {
            SettingsGroup(
                title: "Apple Pay",
                footer: t("v2.wallet.settingsFooter", "Ajoute vos paiements Apple Pay aux opérations à venir.")
            ) {
                SettingsRow(
                    label: t("v2.wallet.guide.title", "Paiements Apple Pay"),
                    symbol: "wave.3.right",
                    action: { showingWalletGuide = true }
                )
            }
        }
    }

    @ViewBuilder
    private var bankSection: some View {
        if sourceBinding.wrappedValue != .server {
            SettingsGroup(title: t("v2.settings.bank", "Banque")) {
                SettingsRow(
                    label: t("v2.settings.bankConnection", "Connexion bancaire"),
                    symbol: "building.columns",
                    action: { showingBanking = true }
                ) {
                    SettingsValue(
                        text: BankingFlow.isConfigured
                            ? t("v2.settings.bankingReady", "Configurée")
                            : t("v2.settings.bankingMissing", "Non configurée")
                    )
                }
                lastSyncRow
                if BankingFlow.isConfigured { syncRow }

                /*
                 * Re-attaching, without asking the bank again.
                 *
                 * A connection can outlive the pairing that told it which local
                 * account it feeds. Left alone the next sync finds no match and
                 * creates a second account for the same money. This re-reads the
                 * existing session and asks again; no consent is spent.
                 */
                if flowHasConnection {
                    Hairline()
                    SettingsRow(
                        label: t("v2.settings.remapAccounts", "Rattacher les comptes"),
                        symbol: "link",
                        action: { Task { await remapAccounts() } }
                    )
                    Hairline()
                    SettingsRow(
                        label: t("v2.synclog.title", "Journal de synchronisation"),
                        symbol: "list.bullet.rectangle",
                        action: { showingSyncLog = true }
                    )
                }
            }
        }
    }

    /*
     * Un écran complet, pas un renvoi.
     *
     * Cette ligne menait à l'onglet Plan, où les catégories se créaient par un
     * « + » minuscule au bout d'un groupe et se supprimaient par un appui long.
     * Des gestes qu'il faut déjà connaître pour les trouver, sur un écran où
     * l'on vient répartir un budget — pas tenir une nomenclature.
     *
     * Le Plan garde les siens : c'est là qu'on donne un montant. Ici chaque
     * geste porte son nom, et c'est la même base des deux côtés.
     */
    /*
     * Les marchands vivent ici avec les catégories : deux façons de dire ce
     * qu'est une opération. Ils restent visibles face à un serveur, parce que
     * les noms donnés sont gardés sur le téléphone et s'appliquent quelle que
     * soit la source — les catégories, elles, appartiennent au serveur.
     */
    /*
     * De quoi lire ce que la caisse a abrégé.
     *
     * Une caisse imprime sur vingt-quatre caractères : « AUR PROV VALP DOP »
     * est un provolone, et aucune règle écrite d'avance ne le devinera. Lire
     * le ticket — découper les lignes, en tirer les prix — se fait sur
     * l'appareil et n'a besoin de personne ; comprendre les articles demande
     * une connaissance du monde, donc un service. Il est donc facultatif, et
     * tant que ce champ est vide le téléphone ne parle à personne.
     *
     * Ce qui sort, quand une clé est posée : les libellés et le nom du
     * commerçant. Jamais la photo, jamais les montants, jamais le reste du
     * grand livre. Et chaque réponse est gardée, donc un article ne se
     * demande qu'une fois.
     */
    private var receiptsSection: some View {
        SettingsGroup(
            title: t("v2.settings.receipts", "Tickets de caisse"),
            footer: t(
                "v2.settings.receiptsHint",
                "Clé gratuite sur aistudio.google.com. Seuls les libellés et le nom du commerçant sortent du téléphone."
            )
        ) {
            if case let .ready(model) = keyState, !geminiKey.isEmpty {
                SettingsRow(
                    label: t("v2.settings.keyActive", "Clé active"),
                    symbol: "checkmark.seal.fill"
                ) {
                    Button(t("v2.common.edit", "Modifier")) {
                        keyState = .editing
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Florin.accent)
                }
                // Le nom du modèle est la preuve que la clé a vraiment répondu,
                // et le seul renseignement utile si elle cesse de marcher.
                Text(model)
                    .font(.system(size: 12))
                    .monospaced()
                    .foregroundStyle(Florin.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Florin.gutter)
                    .padding(.bottom, 12)
            } else {
                HStack(spacing: 11) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Florin.text3)
                        .frame(width: 20)
                    SecureField(
                        t("v2.settings.geminiKey", "Clé d'API Gemini"), text: $geminiKey
                    )
                    .font(.system(size: 15.5))
                    .foregroundStyle(Florin.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { validateKey() }

                    if keyState == .checking {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(t("v2.common.validate", "Valider")) { validateKey() }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(
                                geminiKey.isEmpty ? Florin.text3 : Florin.accent
                            )
                            .disabled(geminiKey.isEmpty)
                    }
                }
                .padding(.horizontal, Florin.gutter)
                .padding(.vertical, 13)

                if case let .failed(message) = keyState {
                    Text(message)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Florin.negative)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Florin.gutter)
                        .padding(.bottom, 12)
                }
            }
        }
        .task {
            guard let store = LocalStore.shared else { return }
            geminiKey = ProductNames.apiKey(store: store) ?? ""
            // Une clé déjà rangée a forcément été validée pour l'être : on la
            // croit sur parole plutôt que de rappeler le service à l'ouverture
            // de l'écran.
            keyState = geminiKey.isEmpty
                ? .editing
                : .ready(ProductNames.model(store: store))
        }
    }

    /*
     * Valider, c'est demander au service — pas regarder la forme de la clé.
     *
     * La liste des modèles coûte zéro quota et répond la seule chose qui
     * compte : cette clé ouvre-t-elle quelque chose, et quoi. Le nom retenu
     * est gardé du même coup, ce qui évite au premier ticket de découvrir
     * tout seul que le modèle écrit en dur n'existe plus.
     */
    private func validateKey() {
        let key = geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, let store = LocalStore.shared else { return }
        keyState = .checking
        Task {
            do {
                let model = try await ProductNames.availableModel(apiKey: key)
                try ProductNames.setAPIKey(store: store, key)
                try ProductNames.setModel(store: store, model)
                geminiKey = key
                keyState = .ready(model)
            } catch {
                keyState = .failed(
                    error.localizedDescription.isEmpty
                        ? t("v2.settings.keyRefused", "Clé refusée.")
                        : error.localizedDescription
                )
            }
        }
    }

    private var categoriesSection: some View {
        let local = sourceBinding.wrappedValue != .server
        return SettingsGroup(
            title: t("v2.settings.naming", "Catégories et marchands"),
            footer: (local
                ? t(
                    "v2.settings.categoriesHint",
                    "Créez, renommez et supprimez vos catégories. Les montants du mois se répartissent dans l'onglet Plan."
                ) + " "
                : "")
                + t(
                    "v2.settings.merchantsHint",
                    "Touchez le nom d'une opération pour renommer son marchand."
                )
                + " " + t(
                    "v2.settings.logosHint",
                    "Les logos viennent directement du site de chaque marchand."
                )
        ) {
            if local {
                SettingsRow(
                    label: t("v2.settings.manageCategories", "Gérer les catégories"),
                    symbol: "tag",
                    action: { showingCategories = true }
                )
                Hairline()
            }
            SettingsRow(
                label: t("v2.merchants.title", "Marchands renommés"),
                symbol: "storefront",
                action: { showingMerchants = true }
            )
            Hairline()
            /*
             * Le réglage d'abord, la carte ensuite.
             *
             * La carte n'a de points que si le réglage est allumé, et
             * l'allumer sans savoir ce qu'il fait serait exactement ce que
             * l'app promet de ne pas faire. L'interrupteur demande
             * l'autorisation système au moment où on le bascule — pas plus
             * tôt, parce qu'une question posée sans raison se refuse.
             */
            Toggle(isOn: Binding(
                get: { placesOn },
                set: { on in
                    placesOn = on
                    LocalPlaces.setEnabled(on)
                    if on { Task { _ = await PlaceFinder().fix() } }
                }
            )) {
                HStack(spacing: 11) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Florin.accent)
                        .frame(width: 20)
                    Text(t("v2.settings.places", "Lieux des marchands"))
                        .font(.system(size: 15.5))
                        .foregroundStyle(Florin.text)
                }
            }
            .tint(Florin.control)
            .padding(.horizontal, Florin.gutter)
            .padding(.vertical, 11)
            if placesOn {
                Hairline()
                SettingsRow(
                    label: t("v2.places.title", "Carte des marchands"),
                    symbol: "map",
                    action: { showingPlaces = true }
                )
            }
            Hairline()
            if local {
                SettingsRow(
                    label: t("v2.trash.title", "Corbeille"),
                    symbol: "trash",
                    action: { showingTrash = true }
                )
                Hairline()
            }
            Toggle(isOn: Binding(
                get: { logosOn },
                set: { on in
                    logosOn = on
                    MerchantLogos.shared.setEnabled(on)
                }
            )) {
                HStack(spacing: 11) {
                    Image(systemName: "photo")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Florin.accent)
                        .frame(width: 20)
                    Text(t("v2.settings.logos", "Logos des marchands"))
                        .font(.system(size: 15.5))
                        .foregroundStyle(Florin.text)
                }
            }
            .tint(Florin.control)
            .padding(.horizontal, Florin.gutter)
            .padding(.vertical, 11)
        }
    }

    /*
     * Le grand livre inventé, et la sortie quand on y est.
     *
     * Deux démonstrations cohabitent, et elles n'ont pas le même danger.
     *
     * Celle de l'onboarding remplit le grand livre de l'appareil : elle ne
     * s'adresse qu'à une installation neuve, et en sortir efface tout — d'où
     * la confirmation et le rouge.
     *
     * Celle-ci ouvre un autre fichier. Les comptes et l'argent de la personne
     * ne sont ni lus ni écrits tant qu'elle est allumée, et l'éteindre les
     * retrouve intacts. C'est elle qu'on tend à quelqu'un par-dessus la table,
     * donc c'est un interrupteur et non un bouton à confirmer.
     */
    @ViewBuilder
    private var demoSection: some View {
        if sourceBinding.wrappedValue != .server {
            SettingsGroup(
                title: t("v2.demo.title", "Démonstration"),
                footer: showcase
                    ? t(
                        "v2.demo.showcaseOn",
                        "Vous regardez un grand livre inventé. Vos comptes sont intacts : éteignez pour les retrouver."
                    )
                    : t(
                        "v2.demo.showcaseHint",
                        "Des comptes et des opérations inventés, dans un fichier séparé — pour montrer l'app sans montrer votre argent. Vos données ne sont ni lues ni modifiées."
                    )
            ) {
                Toggle(isOn: Binding(
                    get: { showcase },
                    set: { on in
                        demoFailure = LocalDemo.setShowcase(
                            on, locale: Locale.current.identifier
                        )?.localizedDescription
                        showcase = LocalDemo.showcase
                        demoActive = LocalDemo.isActive
                        NotificationCenter.default.post(
                            name: .florinLedgerErased, object: nil
                        )
                    }
                )) {
                    HStack(spacing: 11) {
                        Image(systemName: "theatermasks")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Florin.accent)
                            .frame(width: 20)
                        Text(t("v2.demo.showcase", "Mode démonstration"))
                            .font(.system(size: 15.5))
                            .foregroundStyle(Florin.text)
                    }
                }
                .tint(Florin.control)
                .padding(.horizontal, Florin.gutter)
                .padding(.vertical, 11)

                if let demoFailure {
                    Hairline()
                    Text(demoFailure)
                        .font(.system(size: 13))
                        .foregroundStyle(Florin.negative)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Florin.gutter)
                        .padding(.vertical, 11)
                }

                // L'autre démo — celle qui vit dans le vrai fichier.
                if demoActive, !showcase {
                    Hairline()
                    SettingsRow(
                        label: t("v2.demo.exit", "Quitter la démo"),
                        symbol: "xmark.circle",
                        action: { confirmingDemoExit = true },
                        destructive: true
                    )
                }
            }
            .alert(
                t("v2.demo.exitConfirm", "Effacer les données de démonstration ?"),
                isPresented: $confirmingDemoExit
            ) {
                Button(t("v2.demo.exit", "Quitter la démo"), role: .destructive) {
                    try? LocalDemo.erase()
                    NotificationCenter.default.post(name: .florinLedgerErased, object: nil)
                }
                Button(t("v2.common.cancel", "Annuler"), role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private var importSection: some View {
        if sourceBinding.wrappedValue != .server {
            SettingsGroup(
                title: t("v2.settings.bringIn", "Importer"),
                footer: t(
                    "v2.settings.bringInHint",
                    "Pour les comptes que votre banque ne synchronise pas."
                )
            ) {
                SettingsRow(
                    label: t("v2.import.title", "Importer un relevé"),
                    symbol: "doc.text",
                    action: { showingImport = true }
                )
                if server.resolvedURL != nil {
                    Hairline()
                    SettingsRow(
                        label: t("v2.settings.importFromServer", "Importer depuis le serveur"),
                        symbol: "square.and.arrow.down",
                        action: { confirmingImport = true }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var serverRows: some View {
        if editingServer {
            VStack(spacing: 14) {
                ServerFieldsCard(bare: true, host: $draftServer, token: $draftToken, status: $serverStatus)
                HStack(spacing: 10) {
                    Button(t("v2.common.cancel", "Annuler")) {
                        editingServer = false
                        serverStatus = .unknown
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Florin.text2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .florinGlass(in: Capsule())

                    Button(t("v2.common.save", "Enregistrer"), action: commitServer)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Florin.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Florin.accent, in: Capsule())
                        .opacity(ServerStore.normalise(draftServer) == nil ? 0.4 : 1)
                        .disabled(ServerStore.normalise(draftServer) == nil)
                }
                .buttonStyle(.plain)
            }
            .padding(Florin.gutter)
        } else {
            SettingsRow(label: t("v2.settings.serverHost", "Adresse"), symbol: "network") {
                SettingsValue(text: server.resolvedURL?.host ?? "—", monospaced: true)
            }
            Hairline()
            SettingsRow(
                label: t("v2.common.edit", "Modifier"),
                symbol: "pencil",
                action: {
                    draftServer = server.rawURL
                    draftToken = server.apiToken
                    serverStatus = .unknown
                    editingServer = true
                }
            )
            lastSyncRow
            syncRow
        }
    }

    /// True when a bank session exists on this device.
    private var flowHasConnection: Bool {
        guard let store = LocalStore.shared else { return false }
        guard let value = try? store.database.scalar(
            "SELECT count(*) FROM bank_connections WHERE status = 'active'"
        ) else { return false }
        return (value.int ?? 0) > 0
    }

    private func remapAccounts() async {
        await banking.remap()
    }

    private func importFromServer() async {
        guard let url = server.resolvedURL, let store = LocalStore.shared else { return }
        // Resolved once, up front: the progress closure runs off the main actor,
        // and `Strings` is a value it can carry where the view cannot follow.
        let strings = t
        task = .running(strings("v2.settings.importReading", "Lecture de votre serveur…"))
        do {
            let result = try await ServerImport.run(from: url, into: store) { progress in
                Task { @MainActor in
                    task = .running(
                        strings("v2.activity.count", "{count} opérations", ["count": progress.transactions])
                    )
                }
            }
            await model.load(showSpinner: false)
            task = .success(
                title: t("v2.settings.importDone", "Import terminé"),
                detail: t(
                    "v2.settings.importSummary",
                    "{transactions} opérations, {accounts} comptes et {categories} catégories sont maintenant sur ce téléphone.",
                    [
                        "transactions": result.transactions,
                        "accounts": result.accounts,
                        "categories": result.categories,
                    ]
                )
            )
        } catch {
            task = .failure(error.localizedDescription)
        }
    }

    @ViewBuilder
    private var lastSyncRow: some View {
        if let last = model.overview?.lastSynced {
            Hairline()
            SettingsRow(label: t("v2.account.lastSync", "Dernière synchronisation"), symbol: "clock") {
                Text(last, format: .relative(presentation: .named))
                    .font(.system(size: 15))
                    .foregroundStyle(Florin.text2)
            }
        }
    }

    @ViewBuilder
    private var syncRow: some View {
        Hairline()
        SettingsRow(
            label: t("v2.add.sync", "Synchroniser maintenant"),
            symbol: "arrow.trianglehead.2.clockwise",
            action: { Task { await model.sync() } }
        ) {
            if model.syncing { ProgressView().controlSize(.small) }
        }
        .disabled(model.syncing)
        .opacity(model.syncing ? 0.5 : 1)
    }

    private var sourceBinding: Binding<DataSource> {
        Binding(
            get: {
                DataSource(rawValue: sourceRaw)
                    ?? (server.resolvedURL != nil ? .server : .device)
            },
            set: { value in
                UISelectionFeedbackGenerator().selectionChanged()
                sourceRaw = value.rawValue
            }
        )
    }

    /// Who made this, which build you are running, and where to go next.
    ///
    /// The old version of this was one line reading "Version 1.0.0" and a raw
    /// ISO date. A build number matters the moment two TestFlight builds share
    /// a marketing version, and the two links are the only outbound anything in
    /// the app — so they are real buttons with the projects' own marks rather
    /// than blue text.
    @ViewBuilder
    /*
     * One list, not two cards.
     *
     * Version, the data date and the two links were split across two surfaces
     * 24 points apart, the second with no title of its own — so it read as an
     * orphan rather than as the rest of the section above it. They are one
     * list: what this is, and where it comes from.
     *
     * Its footer used to explain that the code is public, under two rows that
     * already say GitHub and Ko-fi. The licence is the part nobody can guess.
     */
    private var aboutSection: some View {
        SettingsGroup(
            title: t("v2.settings.about", "À propos"),
            footer: t("v2.settings.aboutHint", "Florin est un logiciel libre, sous licence AGPL-3.0.")
        ) {
            SettingsRow(label: t("v2.settings.appVersion", "Version"), symbol: "app.badge") {
                SettingsValue(text: Self.version, monospaced: true)
            }
            // The notes are shown once, on the launch after an update, and
            // then only findable here — which is where someone goes looking
            // for "what changed" a week later.
            if let latest = ReleaseNotes.all.first {
                Hairline()
                SettingsRow(
                    label: t("v2.news.title", "Ce qui est nouveau"),
                    symbol: "sparkles",
                    action: { news = latest }
                )
            }
            if let generated = model.overview?.generatedAt {
                Hairline()
                SettingsRow(label: t("v2.settings.dataDate", "Données au"), symbol: "calendar") {
                    SettingsValue(text: String(generated.prefix(10)), monospaced: true)
                }
            }

            Hairline()

            BrandLink(
                path: Brand.github,
                title: "GitHub",
                subtitle: "adrbn/florin",
                tint: Color(red: 0.09, green: 0.11, blue: 0.13),
                markColor: .white,
                url: URL(string: "https://github.com/adrbn/florin")!
            )
            .padding(.horizontal, Florin.gutter)
            .padding(.vertical, 6)

            Hairline()

            BrandLink(
                path: Brand.kofi,
                title: "Ko-fi",
                subtitle: "adrbn",
                // Ko-fi's own brand red.
                tint: Color(red: 1.0, green: 0.35, blue: 0.35),
                markColor: .white,
                url: URL(string: "https://ko-fi.com/adrbn")!
            )
            .padding(.horizontal, Florin.gutter)
            .padding(.vertical, 6)
        }
    }

    /// "1.2.51 (14)" — marketing version plus build, because two builds of the
    /// same version are otherwise indistinguishable from this screen.
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        guard let build = info?["CFBundleVersion"] as? String, build != short else { return short }
        return "\(short) (\(build))"
    }

    // MARK: - Actions

    private var localeBinding: Binding<String> {
        Binding(
            get: { model.overview?.locale ?? Strings.preferredShortLocale },
            set: { next in
                /*
                 * Only write once the payload has actually arrived. Before it
                 * does, `get` returns a placeholder that does not match the
                 * server, and SwiftUI reconciling the Picker against its tags
                 * can fire `set` on its own — silently changing the language of
                 * the whole deployment, browser included, without anyone
                 * touching the control.
                 */
                guard let current = model.overview?.locale, next != current else { return }
                Task { await changeLocale(to: next) }
            }
        )
    }

    private func commitServer() {
        guard ServerStore.normalise(draftServer) != nil else { return }
        server.apiToken = draftToken
        server.apply(draftServer)
        editingServer = false
        serverStatus = .unknown
    }

    /// The locale is a server-side cookie shared with the browser, so switching
    /// it here also switches the web tabs — one setting, not two.
    private func changeLocale(to locale: String) async {
        /*
         * On the device, the language is a local preference.
         *
         * This began and ended with a POST to the server, which on a phone
         * holding its own ledger is a request to nowhere: the guard returned
         * immediately and the picker sat there doing nothing, looking disabled
         * because its own value never moved. The device writes its choice and
         * reloads; a server, if there is one, is still told so the web screens
         * follow.
         */
        chosenLocale = locale
        Strings.forget()
        guard let base = server.resolvedURL else {
            await model.load(showSpinner: false)
            return
        }
        changingLocale = true
        let body = try? JSONSerialization.data(withJSONObject: ["locale": locale])
        for path in ServerStore.localeEndpoints {
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
            components?.path = path
            guard let url = components?.url else { continue }
            var request = FlorinAuth.request(url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            if let (_, response) = try? await FlorinAuth.session.data(for: request),
               let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode) {
                break
            }
        }
        await model.load(showSpinner: false)
        changingLocale = false
    }
}
