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
    @State private var editingServer = false
    @State private var draftServer = ""
    @State private var draftToken = ""
    @State private var serverStatus: ServerStatus = .unknown
    @State private var changingLocale = false
    @AppStorage("florin.locale") private var chosenLocale = ""
    @AppStorage(AppLock.key) private var lockOn = false

    private var t: Strings { model.overview?.t ?? .empty }
    @AppStorage("florin.notifications") private var notificationsOn = false
    @State private var readiness: BackgroundRefresh.Readiness?
    @State private var showingBanking = false
    @State private var showingSyncLog = false
    @State private var showingImport = false
    @State private var confirmingImport = false
    @AppStorage("florin.lastExport") private var lastExport = 0.0
    @State private var exported: URL?
    @State private var picking = false
    @State private var pendingRestore: (url: URL, summary: LocalBackup.Summary)?
    @StateObject private var banking = BankingFlow()
    @State private var task: TaskSheet.State?
    @AppStorage("florin.dataSource") private var sourceRaw = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Backdrop(tint: TabRoute.settings.tint).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        sourceSection
                        bankSection
                        importSection
                        notificationsSection
                        backupSection
                        displaySection
                        privacySection
                        aboutSection
                    }
                    .padding(.horizontal, Florin.gutter)
                    .padding(.top, 10)
                    .padding(.bottom, 110)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(t("v2.settings.title", "Réglages"))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingBanking) { BankingSettings() }
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
                ToolbarItem(placement: .principal) { Wordmark(size: 17) }
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
                .tint(Florin.accent)
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
                .tint(Florin.accent)
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
            .tint(Florin.accent)
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
            choiceRow(
                t("v2.settings.language", "Langue"),
                symbol: "globe",
                selection: localeBinding,
                options: [("fr", "Français"), ("en", "English"), ("nl", "Nederlands")],
                busy: changingLocale
            )
        }
    }

    /// A row that states a choice and opens a menu to change it.
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

    private var sourceSection: some View {
        SettingsGroup(
            title: t("v2.settings.source", "Données"),
            footer: sourceBinding.wrappedValue.detail
        ) {
            /*
             * The choice owns what depends on it.
             *
             * A server address means nothing on the device ledger, and bank
             * setup means nothing on a server that runs its own. These were
             * three sibling sections — source, server, bank sync — so the
             * screen showed settings for a mode you were not in and left the
             * hierarchy to be guessed.
             */
            Picker("", selection: sourceBinding) {
                ForEach(DataSource.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Florin.gutter)
            .padding(.vertical, 12)

            Hairline()

            if sourceBinding.wrappedValue == .server {
                serverRows
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
                        .foregroundStyle(.black)
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
