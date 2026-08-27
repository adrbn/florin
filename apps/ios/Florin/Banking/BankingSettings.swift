import SwiftUI

/// Setting up bank sync, in three numbered steps.
///
/// The desktop version of this screen was rewritten once already for exactly
/// this reason: the shortest path is not the clearest one. Someone doing this
/// has never heard of a JWT and should not have to — the steps are "make a
/// key", "register it", "paste the id back", and each one says what it is for.
struct BankingSettings: View {
    /// Called once a bank is genuinely connected. Onboarding uses it to finish;
    /// opened from settings there is nothing to finish, so it is optional.
    var onConnected: (() -> Void)?

    @StateObject private var flow = BankingFlow()
    @Environment(\.dismiss) private var dismiss

    @State private var appId = ""
    @State private var publicKey: String?
    @State private var hasKey = BankingKey.exists
    @State private var confirmingRegenerate = false
    @State private var copied = false
    @State private var banks: [Aspsp] = []
    @State private var searching = false
    @State private var query = ""
    @State private var country = "FR"

    /// Reads the stored value, not the typed one: the whole point of the bug
    /// above was a screen that claimed to be ready on the strength of a
    /// variable nothing had persisted.
    private var configured: Bool { hasKey && BankingFlow.isConfigured }

    var body: some View {
        ZStack {
            Backdrop(tint: TabRoute.accounts.tint).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    header

                    /*
                     * One thing at a time.
                     *
                     * The setup steps used to reappear above the bank picker:
                     * their condition included `banks.isEmpty`, so the moment
                     * the list arrived the whole three-step tutorial came back
                     * and the picker was pushed below it. Nobody choosing their
                     * bank needs to be told again how to make a key.
                     */
                    if !banks.isEmpty || searching {
                        bankList
                    } else if configured {
                        ready
                    } else {
                        step(1, "Créer une clé", done: hasKey) { keyStep }
                        step(2, "Enregistrer l'application", done: !appId.isEmpty) { registerStep }
                        step(3, "Coller l'identifiant", done: !appId.isEmpty) { appIdStep }
                    }
                }
                .padding(.horizontal, Florin.gutter)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack {
                HStack {
                    Spacer()
                    CircleButton(symbol: "xmark", size: 40) { dismiss() }
                        .padding(.trailing, Florin.gutter)
                        .padding(.top, 6)
                }
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        // Only a sheet when it is one. Presented full screen during onboarding,
        // these would fight the cover.
        .presentationDetents(onConnected == nil ? [.medium, .large] : [.large])
        .presentationDragIndicator(onConnected == nil ? .visible : .hidden)
        .task {
            if let store = LocalStore.shared { appId = BankingFlow.appId(store) ?? "" }
        }
        .onChange(of: flow.connected) { _, connected in
            if connected { onConnected?() }
        }
        .alert(
            "Remplacer la clé ?",
            isPresented: $confirmingRegenerate
        ) {
            Button("Remplacer", role: .destructive) { makeKey() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Enable Banking ne permet pas de changer le certificat d'une application existante : il faudra en créer une nouvelle et recoller son identifiant ici. La synchro actuelle s'arrêtera.")
        }
        .alert(
            "Synchro bancaire",
            isPresented: Binding(
                get: { flow.failure != nil },
                set: { if !$0 { flow.failure = nil } }
            )
        ) {
            Button("OK", role: .cancel) { flow.failure = nil }
        } message: {
            Text(flow.failure ?? "")
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "building.columns")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Florin.accent)
            Text("Connecter votre banque")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Florin.text)
            Text("Une seule fois, environ 2 minutes. Vos identifiants bancaires ne passent jamais par Florin — vous vous connectez chez votre banque.")
                .font(.system(size: 13.5))
                .foregroundStyle(Florin.text2)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        // Clear of the close button, and of the sheet's own grabber: a title
        // that starts right under the top edge reads as clipped.
        .padding(.top, 54)
        .padding(.bottom, 6)
    }

    private var ready: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Florin.positive)
                Text("Prêt à connecter une banque")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Florin.text)
                Spacer()
            }

            Button {
                Task { await loadBanks() }
            } label: {
                Text("Choisir ma banque")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Florin.accent, in: Capsule())
            }
            .buttonStyle(.plain)

            if ProcessInfo.processInfo.environment["FLORIN_BANKING_SELFTEST"] == "1" {
                Button("Tester l'ouverture") {
                    Task { await flow.probePresentation() }
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Florin.warn)
            }

            Button("Refaire la configuration") {
                withAnimation { banks = []; appId = "" }
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Florin.text3)
        }
        .padding(18)
        .florinSurface()
    }

    private func step<Content: View>(
        _ number: Int,
        _ title: String,
        done: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(done ? Florin.positive : Florin.surface3)
                        .frame(width: 24, height: 24)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.black)
                    } else {
                        Text("\(number)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Florin.text2)
                    }
                }
                Text(title)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(Florin.text)
                Spacer()
            }
            content()
        }
        .padding(18)
        .florinSurface()
    }

    @ViewBuilder
    private var keyStep: some View {
        Text("Florin crée une clé qui reste sur ce téléphone. Seul le certificat public en sort — c'est lui qu'Enable Banking demande, et il ne pourra plus être changé ensuite.")
            .font(.system(size: 13))
            .foregroundStyle(Florin.text2)

        if let publicKey {
            Text(publicKey)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Florin.text3)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Florin.surface2)
                )

            Button {
                UIPasteboard.general.string = publicKey
                copied = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                Label(
                    copied ? "Certificat copié" : "Copier le certificat",
                    systemImage: copied ? "checkmark" : "doc.on.doc"
                )
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Florin.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .florinGlass(in: Capsule())
            }
            .buttonStyle(.plain)
        }

        Button {
            if hasKey { confirmingRegenerate = true } else { makeKey() }
        } label: {
            Text(hasKey ? "Régénérer la clé" : "Créer la clé")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(hasKey ? Florin.text3 : .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(hasKey ? Color.clear : Florin.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var registerStep: some View {
        Text("Créez une application chez Enable Banking en choisissant « Generate outside the browser », collez-y le certificat, et indiquez cette adresse de redirection — recopiée exactement. Pensez ensuite à activer l'application depuis la console :")
            .font(.system(size: 13))
            .foregroundStyle(Florin.text2)

        HStack(spacing: 8) {
            Text(BankingFlow.redirectURL)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Florin.accent)
            Spacer()
            Button {
                UIPasteboard.general.string = BankingFlow.redirectURL
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                Image(systemName: "doc.on.doc").font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Florin.text2)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Florin.surface2))

        Link(destination: URL(string: "https://enablebanking.com/cp")!) {
            Label("Ouvrir Enable Banking", systemImage: "arrow.up.right.square")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Florin.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .florinGlass(in: Capsule())
        }
    }

    @ViewBuilder
    private var appIdStep: some View {
        Text("L'identifiant de l'application que vous venez de créer.")
            .font(.system(size: 13))
            .foregroundStyle(Florin.text2)

        TextField("00000000-0000-0000-0000-000000000000", text: storedAppId)
            .font(.system(size: 14, design: .monospaced))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Florin.surface2))
    }

    /*
     * Writes on set, rather than from an .onChange on the field.
     *
     * The field lived inside the step-3 card, which disappears the instant the
     * id becomes non-empty — `configured` flips and the whole step list is
     * replaced by the "ready" card. SwiftUI tore the field down in the same
     * update that changed its value, so the .onChange never ran: the screen
     * said ready while the database had nothing, and the first API call failed
     * with "not set up yet".
     *
     * A binding that writes as part of the assignment cannot be outrun by the
     * view being removed.
     */
    private var storedAppId: Binding<String> {
        Binding(
            get: { appId },
            set: { value in
                appId = value
                guard let store = LocalStore.shared else {
                    flow.failure = "Florin n'a pas pu ouvrir sa base sur cet appareil."
                    return
                }
                do {
                    try BankingFlow.setAppId(store, value)
                } catch {
                    flow.failure = error.localizedDescription
                }
            }
        )
    }

    @ViewBuilder
    private var bankList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Eyebrow(text: "Votre banque")
                Spacer()
                if flow.busy || searching {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        withAnimation { banks = []; query = "" }
                    } label: {
                        Text("Retour")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Florin.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let step = flow.step {
                Text(step)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Florin.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            TextField("Rechercher", text: $query)
                .font(.system(size: 15))
                .padding(.vertical, 11)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Florin.surface2)
                )

            let matches = query.isEmpty
                ? banks
                : banks.filter { $0.name.localizedCaseInsensitiveContains(query) }

            ForEach(matches.prefix(40)) { bank in
                /*
                 * A tap gesture, not a Button.
                 *
                 * Wrapped in a Button these rows never fired — the same thing
                 * that happened to Plan's category rows in the same kind of
                 * stack, while buttons elsewhere on the screen worked. An
                 * explicit content shape with a tap on it is unambiguous and
                 * does fire.
                 */
                HStack {
                    Text(bank.name)
                        .font(.system(size: 15))
                        .foregroundStyle(Florin.text)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Florin.text3)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !flow.busy else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    Task { await flow.connect(to: bank) }
                }
                .opacity(flow.busy ? 0.4 : 1)

                if bank.id != matches.prefix(40).last?.id { Hairline() }
            }
        }
        .padding(18)
        .florinSurface()
    }

    // MARK: - Doing

    private func makeKey() {
        do {
            try BankingKey.generate()
            // A new key means every signature the cached token carries is
            // worthless.
            EnableBanking.forgetToken()
            // The console takes a certificate, not a bare public key — its own
            // instructions are `openssl req -x509`, and an SPKI key pasted into
            // that field is rejected.
            publicKey = try BankingKey.certificatePEM()
            hasKey = true
            copied = false
        } catch {
            flow.failure = error.localizedDescription
        }
    }

    private func loadBanks() async {
        searching = true
        banks = await flow.banks(country: country)
        searching = false
    }
}
