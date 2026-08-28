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
    @State private var redirectCopied = false
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
                        step(1, hasKey
                                ? Strings.device("v2.connect.stepKeyDone", "Clé créée")
                                : Strings.device("v2.connect.stepKey", "Créer une clé"),
                             hasKey ? .done : .now,
                             // Collapsing step one hid the only way back to it.
                             // A key can only be replaced by making a new
                             // application, so this stays reachable — quietly.
                             trailing: hasKey
                                ? {
                                    AnyView(
                                        Button(Strings.device("v2.connect.regenerateKey", "Régénérer la clé")) {
                                            confirmingRegenerate = true
                                        }
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(Florin.text3)
                                        .buttonStyle(.plain)
                                    )
                                }
                                : nil) { keyStep }
                        step(2, Strings.device("v2.connect.stepRegister", "Enregistrer l'application"),
                             hasKey ? .now : .later) { registerStep }
                        step(3, Strings.device("v2.connect.stepAppId", "Coller l'App ID"),
                             hasKey ? .now : .later) { appIdStep }
                    }
                }
                .padding(.horizontal, Florin.gutter)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)

        }
        /*
         * Above the content, and clear of the sheet's grabber.
         *
         * It sat six points from the top inside the stack, which on a sheet is
         * where the drag indicator lives — the handle took the touch and the
         * button never fired. An overlay with real clearance and an explicit
         * z-order puts it back in reach.
         */
        .overlay(alignment: .topTrailing) {
            CircleButton(symbol: "xmark", size: 40) { dismiss() }
                .padding(.trailing, Florin.gutter)
                .padding(.top, onConnected == nil ? 26 : 14)
                .zIndex(2)
        }
        .preferredColorScheme(.dark)
        /*
         * Full height, always.
         *
         * From settings this opened at the medium detent — half a screen for a
         * three-step setup, so the first thing anyone had to do was drag the
         * sheet up before they could read step two. The steps are short enough
         * to fit now; what they need is the room.
         */
        .presentationDetents([.large])
        .presentationDragIndicator(onConnected == nil ? .visible : .hidden)
        .task {
            if let store = LocalStore.shared { appId = BankingFlow.appId(store) ?? "" }
        }
        .onChange(of: flow.connected) { _, connected in
            guard connected else { return }
            /*
             * A finished connection leaves the picker.
             *
             * Confirming the account mapping dropped the user back on the list
             * of banks — the list was still in state, so the view had nothing
             * else to show. Connecting a bank ends by returning to the app,
             * not by offering to connect another.
             */
            banks = []
            query = ""
            if let onConnected {
                onConnected()
            } else {
                dismiss()
            }
        }
        // Presented rather than inlined: it is a decision that blocks the
        // connection, not another step in a list.
        .sheet(isPresented: Binding(
            get: { flow.mapping != nil },
            set: { if !$0 { flow.mapping = nil } }
        )) {
            if let found = flow.mapping {
                BankMappingSheet(
                    accounts: found,
                    candidates: flow.candidates,
                    locale: "fr-FR",
                    currency: "EUR",
                    onConfirm: { answers in
                        Task { await flow.confirmMapping(answers) }
                    },
                    onCancel: { flow.mapping = nil }
                )
            }
        }
        .alert(
            Strings.device("v2.connect.replaceKeyTitle", "Remplacer la clé ?"),
            isPresented: $confirmingRegenerate
        ) {
            Button(Strings.device("v2.common.replace", "Remplacer"), role: .destructive) { makeKey() }
            Button(Strings.device("v2.common.cancel", "Annuler"), role: .cancel) {}
        } message: {
            Text(Strings.device(
                "v2.connect.replaceKeyBody",
                "Enable Banking ne permet pas de changer le certificat d'une application existante : il faudra en créer une nouvelle et recoller son identifiant ici. La synchro actuelle s'arrêtera."
            ))
        }
        .alert(
            Strings.device("v2.settings.banking", "Synchronisation bancaire"),
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
            Text(Strings.device("v2.connect.setupTitle", "Connecter votre banque"))
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Florin.text)
            /*
             * One line, not three.
             *
             * The lead used to spend three lines on reassurance — how long it
             * takes, that credentials never reach Florin, that you sign in at
             * your bank. All true, and all of it pushing the first actual step
             * off the screen. What someone needs before they start is that this
             * happens once and that their bank keeps their password; the rest
             * is discovered by doing it.
             */
            Text(Strings.device(
                "v2.connect.setupLead",
                "Configuration unique. Vos identifiants restent chez votre banque."
            ))
                .font(.system(size: 13.5))
                .foregroundStyle(Florin.text2)
                .multilineTextAlignment(.center)
        }
        // Clear of the close button, and of the sheet's own grabber: a title
        // that starts right under the top edge reads as clipped.
        .padding(.top, 54)
        .padding(.bottom, 2)
    }

    private var ready: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Florin.positive)
                Text(Strings.device("v2.connect.ready", "Prêt à connecter une banque"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Florin.text)
                Spacer()
            }

            Button {
                Task { await loadBanks() }
            } label: {
                Text(Strings.device("v2.connect.chooseBank", "Choisir ma banque"))
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

            Button(Strings.device("v2.connect.redoSetup", "Refaire la configuration")) {
                withAnimation { banks = []; appId = "" }
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Florin.text3)
        }
        .padding(18)
        .florinSurface()
    }

    /*
     * A step that is finished takes one line.
     *
     * All three used to stand open at once, each with its own paragraph, and
     * only ever one of them was actionable — so the screen was three times the
     * height it needed to be and the thing you were meant to do next was
     * usually below the fold. Done steps keep their place in the list, because
     * seeing what is behind you is how you know where you are, but they keep it
     * in a single line.
     */
    /// Behind you, in front of you, or the one to do.
    enum StepState { case done, now, later }

    private func step<Content: View>(
        _ number: Int,
        _ title: String,
        _ state: StepState,
        trailing: (() -> AnyView)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let open = state == .now
        return VStack(alignment: .leading, spacing: open ? 12 : 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(state == .done ? Florin.positive : Florin.surface3)
                        .frame(width: 24, height: 24)
                    if state == .done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.black)
                    } else {
                        Text("\(number)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(state == .now ? Florin.text2 : Florin.text3)
                    }
                }
                Text(title)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(open ? Florin.text : Florin.text2)
                Spacer()
                if let trailing { trailing() }
            }
            if open { content() }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, open ? 18 : 14)
        .florinSurface()
        .opacity(state == .later ? 0.5 : 1)
    }

    /*
     * One sentence and one button.
     *
     * The dump of the certificate and the button to copy it used to live here,
     * which is a step too early: nothing is done with the certificate until the
     * Enable Banking form is open, and by then this card has collapsed. They
     * have moved to step 2, beside the field they are pasted into.
     */
    @ViewBuilder
    private var keyStep: some View {
        Text(Strings.device(
            "v2.connect.keyHint",
            "La clé reste sur cet iPhone. Seul le certificat public est partagé."
        ))
            .font(.system(size: 13))
            .foregroundStyle(Florin.text2)

        Button { makeKey() } label: {
            Text(Strings.device("v2.connect.createKey", "Créer la clé"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Florin.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /*
     * The order in which it is actually lived.
     *
     * The instructions said "paste the certificate" before anything had said
     * where, and the door to that somewhere — Ouvrir Enable Banking — sat at
     * the very bottom, after four things you were told to do there. So you read
     * a list of pastes with no idea what you were pasting into, and found the
     * destination last.
     *
     * It runs the way the two minutes run instead: this happens on a website,
     * here are the two things to take with you, here is what to do once you
     * arrive, and now the door. The last thing read before leaving is the
     * recipe for the other side, which is the thing most likely to be needed
     * from memory.
     */
    @ViewBuilder
    private var registerStep: some View {
        Text(Strings.device(
            "v2.connect.registerLead",
            "Créez une application sur le site d'Enable Banking. Ces deux valeurs vous seront demandées."
        ))
            .font(.system(size: 13))
            .foregroundStyle(Florin.text2)

        Button {
            UIPasteboard.general.string = publicKey ?? (try? BankingKey.certificatePEM()) ?? ""
            copied = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13))
                    .foregroundStyle(copied ? Florin.positive : Florin.text2)
                Text(copied
                    ? Strings.device("v2.connect.certCopied", "Certificat copié")
                    : Strings.device("v2.connect.copyCert", "Copier le certificat"))
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Florin.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Florin.surface2))
        }
        .buttonStyle(.plain)

        Button {
            UIPasteboard.general.string = BankingFlow.redirectURL
            redirectCopied = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: redirectCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13))
                    .foregroundStyle(redirectCopied ? Florin.positive : Florin.text2)
                // Shown, not just copied: Enable Banking rejects a redirect that
                // differs by a character, so being able to compare it against
                // what is in the form is worth the width it takes.
                Text(BankingFlow.redirectURL)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Florin.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Florin.surface2))
        }
        .buttonStyle(.plain)

        Text(Strings.device("v2.connect.registerThere", "Sur le site :"))
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(Florin.text3)
            .padding(.top, 2)

        /*
         * Production, said first and said plainly.
         *
         * Enable Banking's form opens on Sandbox, and a Sandbox application
         * reaches only banks' simulators — invented accounts, invented
         * transactions, all of it plausible. No French retail bank is even in
         * that list, and the environment cannot be changed afterwards: getting
         * it wrong means starting the registration over.
         */
        instruction(Strings.device(
            "v2.connect.registerEnv",
            "Choisissez « Production », pas « Sandbox »."
        ))
        instruction(Strings.device(
            "v2.connect.registerPick",
            "Choisissez « Generate outside the browser »."
        ))
        instruction(Strings.device(
            "v2.connect.registerPaste",
            "Collez le certificat et l'adresse de redirection."
        ))
        /*
         * Linking one account is not linking your accounts.
         *
         * An individual activates a production application by linking accounts
         * rather than signing a contract, and the API then returns only what
         * was linked — everything else is stripped, silently, with the
         * authorisation still reported as successful. Someone who links their
         * current account and stops gets exactly one account in Florin and no
         * indication that the others were dropped rather than absent.
         */
        instruction(Strings.device(
            "v2.connect.registerActivate",
            "Activez l'application en liant vos comptes. Liez tous ceux que vous voulez voir dans Florin."
        ))

        Link(destination: URL(string: "https://enablebanking.com/cp")!) {
            Label(Strings.device("v2.connect.openEnableBanking", "Ouvrir Enable Banking"), systemImage: "arrow.up.right.square")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Florin.accent, in: Capsule())
        }
        .padding(.top, 2)
    }

    /// One instruction, marked as one thing to do.
    private func instruction(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(Florin.text3)
                .frame(width: 4, height: 4)
                .offset(y: -3)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Florin.text2)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var appIdStep: some View {
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
                    flow.failure = Strings.device(
                        "v2.connect.noLocalStore",
                        "Florin n'a pas pu ouvrir sa base sur cet appareil."
                    )
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
                Eyebrow(text: Strings.device("v2.connect.yourBank", "Votre banque"))
                Spacer()
                if flow.busy || searching {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        withAnimation { banks = []; query = "" }
                    } label: {
                        Text(Strings.device("v2.a11y.back", "Retour"))
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

            TextField(Strings.device("v2.common.search", "Rechercher"), text: $query)
                .font(.system(size: 15))
                .padding(.vertical, 11)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Florin.surface2)
                )

            /*
             * Alphabetical, and by the rules of the reader's language.
             *
             * Enable Banking returns them in whatever order it pleases, which
             * put N26 above La Banque Postale and made the list feel random.
             * `localizedStandardCompare` also sorts "Crédit" and "Credit"
             * together, which a plain `<` does not.
             */
            let matches = (query.isEmpty
                ? banks
                : banks.filter { $0.name.localizedCaseInsensitiveContains(query) })
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

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
                HStack(spacing: 12) {
                    BankLogo(bank: bank)
                    Text(bank.name)
                        .font(.system(size: 15.5))
                        .foregroundStyle(Florin.text)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Florin.text3)
                }
                .padding(.vertical, 10)
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
