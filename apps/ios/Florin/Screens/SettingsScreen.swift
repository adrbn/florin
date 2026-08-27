import SwiftUI

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

    private var t: Strings { model.overview?.t ?? .empty }
    @State private var showingBanking = false
    @State private var importing = false
    @State private var confirmingImport = false
    @State private var importProgress = 0
    @AppStorage("florin.dataSource") private var sourceRaw = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Backdrop(tint: TabRoute.settings.tint).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        sourceSection
                        appearanceSection
                        privacySection
                        languageSection
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
            /*
             * Destructive, so it says so before doing it.
             *
             * The import replaces this device's ledger rather than merging
             * into it, which is the only way it can be correct — but that is
             * not something to discover afterwards from a net worth that
             * doubled.
             */
            .alert("Remplacer les données locales ?", isPresented: $confirmingImport) {
                Button("Remplacer", role: .destructive) {
                    Task { await importFromServer() }
                }
                Button(t("v2.common.cancel", "Annuler"), role: .cancel) {}
            } message: {
                Text("Les comptes, opérations et catégories de cet appareil seront effacés et remplacés par ceux du serveur. La connexion bancaire de ce téléphone sera retirée — le serveur s'en charge déjà.")
            }
            .toolbar {
                ToolbarItem(placement: .principal) { Wordmark(size: 17) }
                if let onClose {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(t("v2.common.close", "Fermer"), action: onClose)
                    }
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var languageSection: some View {
        SettingsGroup(
            title: t("v2.settings.language", "Langue"),
            footer: "S'applique au téléphone comme aux écrans web de l'app."
        ) {
            Picker("", selection: localeBinding) {
                Text("Français").tag("fr")
                Text("English").tag("en")
                Text("Nederlands").tag("nl")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(changingLocale || model.overview == nil)
            .padding(.horizontal, Florin.gutter)
            .padding(.vertical, 12)
        }
    }

    private var privacySection: some View {
        SettingsGroup(
            title: t("v2.settings.discretion", "Discrétion"),
            footer: "Secouez le téléphone pour masquer ou réafficher tous les montants, ou maintenez le chiffre principal. Ça cache, ça ne verrouille pas : quiconque tient le téléphone peut le rouvrir."
        ) {
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

    private var appearanceSection: some View {
        SettingsGroup(
            title: "Apparence",
            footer: "Le thème s'applique aussi aux écrans web de l'app, pas seulement aux natifs."
        ) {
            Picker("", selection: $appearanceRaw) {
                ForEach(Appearance.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Florin.gutter)
            .padding(.vertical, 12)
        }
    }

    /*
     * Which books are open, at the top, before anything else.
     *
     * Nothing below this matters until it is answered: a server address is
     * meaningless on the device ledger, and bank setup is meaningless on a
     * server that does its own. It used to be inferred from whether an address
     * happened to be filled in, so switching meant erasing a text field and
     * there was no way to keep a server configured while working locally.
     */
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
            } else {
                deviceRows
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

    @ViewBuilder
    private var deviceRows: some View {
        SettingsRow(
            label: t("v2.settings.banking", "Synchronisation bancaire"),
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
         * Bringing a server's ledger onto the phone.
         *
         * Re-fetching from the bank was the wrong answer to "I want my history
         * here": a bank exposes what its consent allows, while the server holds
         * everything ever recorded — the manual rows, the categories and the
         * accounts that never came from a bank at all. Only offered when there
         * is a server to read.
         */
        if server.resolvedURL != nil {
            Hairline()
            SettingsRow(
                label: importing
                    ? "Import en cours… \(importProgress) opérations"
                    : "Importer depuis mon serveur",
                symbol: "square.and.arrow.down",
                action: importing ? nil : { confirmingImport = true }
            ) {
                if importing { ProgressView().controlSize(.small) }
            }
            .disabled(importing)
        }
    }

    private func importFromServer() async {
        guard let url = server.resolvedURL, let store = LocalStore.shared else { return }
        importing = true
        importProgress = 0
        do {
            let result = try await ServerImport.run(from: url, into: store) { progress in
                Task { @MainActor in importProgress = progress.transactions }
            }
            importing = false
            model.toast = ToastMessage(
                text: "\(result.transactions) opérations importées",
                kind: .success
            )
            await model.load(showSpinner: false)
        } catch {
            importing = false
            model.toast = ToastMessage(text: error.localizedDescription, kind: .failure)
        }
    }

    @ViewBuilder
    private var lastSyncRow: some View {
        if let last = model.overview?.lastSynced {
            Hairline()
            SettingsRow(label: t("v2.account.lastSync", "Dernière synchro"), symbol: "clock") {
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
            label: t("v2.add.sync", "Synchroniser les banques"),
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
    private var aboutSection: some View {
        VStack(spacing: 24) {
            SettingsGroup(
                title: t("v2.settings.about", "À propos"),
                footer: "Florin est libre et auto-hébergé, sous licence AGPL-3.0."
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
            }

            SettingsGroup(
                footer: "Le code, les tickets et les versions sont publics. Un café aide à les écrire."
            ) {
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
            get: { model.overview?.locale ?? "fr" },
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
        guard let base = server.resolvedURL else { return }
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
