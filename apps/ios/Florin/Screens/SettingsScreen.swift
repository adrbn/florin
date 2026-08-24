import SwiftUI

/// Settings, as iOS does them.
///
/// The web settings page is a good web page — cards, custom toggles, a segmented
/// control — and that is exactly why it felt wrong in the app: on iOS this
/// screen is a grouped `Form`, with system toggles, a system picker and a
/// footer that explains rather than a caption that decorates. Nothing here is
/// styled; letting the platform draw it is the whole point.
struct SettingsScreen: View {
    @ObservedObject var model: OverviewModel
    var onClose: (() -> Void)?
    @EnvironmentObject private var server: ServerStore

    @AppStorage("florin.appearance") private var appearanceRaw = Appearance.dark.rawValue
    @State private var editingServer = false
    @State private var draftServer = ""
    @State private var draftToken = ""
    @State private var serverStatus: ServerStatus = .unknown
    @State private var changingLocale = false

    private var t: Strings { model.overview?.t ?? .empty }

    var body: some View {
        NavigationStack {
            ZStack {
                Backdrop(tint: TabRoute.settings.tint)
                Form {
                    appearanceSection
                    serverSection
                    languageSection
                    syncSection
                    aboutSection
                }
                // Let the section's own ground show the app's colour instead of
                // the grey slab a Form paints by default: it is the one thing
                // that stops this screen looking like it belongs to a different
                // app than the dashboard.
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(t("v2.settings.title", "Réglages"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Wordmark(size: 17) }
                if let onClose {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(t("v2.common.close", "Fermer"), action: onClose)
                    }
                }
            }
            .safeAreaPadding(.bottom, 96)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var serverSection: some View {
        if editingServer {
            // The same fields and the same diagnosis as first-run setup, rather
            // than a bare text box that can only say "saved".
            ServerFields(host: $draftServer, token: $draftToken, status: $serverStatus)
            Section {
                Button(t("v2.common.save", "Enregistrer"), action: commitServer)
                    .disabled(ServerStore.normalise(draftServer) == nil)
                Button(t("v2.common.cancel", "Annuler"), role: .cancel) {
                    editingServer = false
                    serverStatus = .unknown
                }
            }
        } else {
            Section {
                LabeledContent(t("v2.settings.serverHost", "Serveur")) {
                    Text(server.resolvedURL?.host ?? "—")
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
                Button(t("v2.common.edit", "Modifier")) {
                    draftServer = server.rawURL
                    draftToken = server.apiToken
                    serverStatus = .unknown
                    editingServer = true
                }
            } footer: {
                Text("Florin lit ton propre serveur. Rien ne quitte ton réseau.")
            }
        }
    }

    private var languageSection: some View {
        Section {
            Picker(t("v2.settings.language", "Langue"), selection: localeBinding) {
                Text("Français").tag("fr")
                Text("English").tag("en")
                Text("Nederlands").tag("nl")
            }
            .disabled(changingLocale || model.overview == nil)
        } footer: {
            Text("Change la langue de Florin, sur le téléphone comme dans le navigateur.")
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("Apparence", selection: $appearanceRaw) {
                ForEach(Appearance.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            Text("Apparence")
        } footer: {
            Text("Le thème s'applique aussi aux écrans web de l'app, pas seulement aux natifs.")
        }
    }

    private var syncSection: some View {
        Section {
            LabeledContent(t("v2.settings.banking", "Synchronisation bancaire")) {
                Text(
                    model.overview?.bankSyncConfigured == true
                        ? t("v2.settings.bankingReady", "Configurée")
                        : t("v2.settings.bankingMissing", "Non configurée")
                )
                .foregroundStyle(.secondary)
            }

            if let last = model.overview?.lastSynced {
                LabeledContent(t("v2.account.lastSync", "Dernière synchro")) {
                    Text(last, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                Task { await model.sync() }
            } label: {
                HStack {
                    Text(t("v2.add.sync", "Synchroniser les banques"))
                    if model.syncing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(model.syncing || model.overview?.bankSyncConfigured != true)
        } footer: {
            Text(
                "Florin se synchronise tout seul à l'ouverture, au maximum toutes les 6 heures — la limite que ta banque tolère pour un accès non supervisé."
            )
        }
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
        Section {
            LabeledContent(t("v2.settings.appVersion", "Version")) {
                Text(Self.version)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let generated = model.overview?.generatedAt {
                LabeledContent(t("v2.settings.dataDate", "Données au")) {
                    Text(generated.prefix(10)).foregroundStyle(.secondary).monospaced()
                }
            }
        } header: {
            Text(t("v2.settings.about", "À propos"))
        } footer: {
            Text(
                "Florin est libre et auto-hébergé, sous licence AGPL-3.0. Tes données restent sur ton serveur."
            )
        }

        Section {
            BrandLink(
                path: Brand.github,
                title: "GitHub",
                subtitle: "adrbn/florin",
                tint: Color(red: 0.09, green: 0.11, blue: 0.13),
                markColor: .white,
                url: URL(string: "https://github.com/adrbn/florin")!
            )
            BrandLink(
                path: Brand.kofi,
                title: "Ko-fi",
                subtitle: "adrbn",
                // Ko-fi's own brand red.
                tint: Color(red: 1.0, green: 0.35, blue: 0.35),
                markColor: .white,
                url: URL(string: "https://ko-fi.com/adrbn")!
            )
        } footer: {
            Text("Le code, les tickets et les versions sont publics. Un café aide à les écrire.")
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
            if let (_, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode) {
                break
            }
        }
        await model.load(showSpinner: false)
        changingLocale = false
    }
}
