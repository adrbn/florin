import SwiftUI

/// The first thing a new install sees.
///
/// Until now that was the server form: a URL field and a token field, on an
/// app that had not yet said what it was. Someone who has never run Florin
/// anywhere was asked for an address before being told why. This replaces that
/// as the front door and keeps the form behind a link, for the people who
/// already know they have a server.
///
/// It is deliberately three steps and no more. Onboarding earns its keep by
/// getting out of the way — the categories are already seeded, the language
/// comes from the device, and everything else is a decision better made later
/// with real numbers on screen than upfront in the abstract.
struct OnboardingFlow: View {
    /// Called once the local ledger has an account and is worth opening.
    let onFinish: () -> Void
    /// The escape hatch to the old server form.
    let onUseServer: () -> Void
    /// Hands off to the bank setup, which is what finishes this path.
    let onNeedsBank: () -> Void

    @State private var step = 0
    @State private var path: StartPath?
    @State private var name = ""
    @State private var kind = AccountKind.checking
    @State private var balanceText = ""
    @State private var saving = false
    @State private var failure: String?
    @FocusState private var focus: Field?

    private enum Field { case name, balance }

    /*
     * How the money gets in, asked before anything is asked about it.
     *
     * The first version went straight to "name your account, type its
     * balance" — which is the wrong question for anyone who is about to
     * connect a bank, because the bank supplies both and would contradict the
     * answer within the minute. A starting balance is only ever a real
     * question on the manual path, so it is only asked there.
     */
    enum StartPath {
        case bank
        case manual
    }

    /// The ground shifts colour as you advance — the same per-section tinting
    /// the tab bar does, used here to make three steps feel like a journey
    /// rather than three identical pages.
    private var tint: Color {
        switch step {
        case 0: TabRoute.overview.tint
        case 1, 2: TabRoute.accounts.tint
        default: TabRoute.plan.tint
        }
    }

    /// Three pages on the bank path, four on the manual one — the account
    /// form only exists where it means something.
    /*
     * Four pages by hand, two with a bank.
     *
     * The bank path used to end on its own "c'est prêt" page, which declared
     * the setup finished before a single account existed — and dropped the
     * user on a dashboard of zeros. There is nothing to confirm before the
     * bank has been connected, so the fork is where that path ends.
     */
    private var lastStep: Int { path == .manual ? 3 : 2 }

    /// The page that asks to be allowed to speak, on the path where it would
    /// have something to say.
    private var isNotifyStep: Bool { step == 2 && path == .bank }

    var body: some View {
        ZStack {
            Backdrop(tint: tint).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                Group {
                    switch step {
                    case 0: welcome
                    case 1: fork
                    case 2 where path == .manual: account
                    case 2: notify
                    default: ready
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer(minLength: 0)

                dots
                    .padding(.bottom, 18)

                primaryAction
                    .padding(.horizontal, Florin.gutter)
                    .padding(.bottom, 10)

                secondaryAction
                    .frame(height: 30)
                    .padding(.bottom, 18)
            }
        }
        .animation(.snappy(duration: 0.32), value: step)
        .animation(.snappy(duration: 0.32), value: tint)
        .preferredColorScheme(.dark)
        .alert(
            Strings.device("v2.onboard.title", "Onboarding"),
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 18) {
            /*
             * The same coin the splash just flicked, at rest.
             *
             * Cutting from an animated mark straight to a text page throws away
             * the one moment the app has already earned. Landing on the settled
             * coin reads as the end of that gesture rather than the start of a
             * different screen.
             */
            Image("CoinFace")
                .resizable()
                .scaledToFit()
                .frame(width: 74, height: 74)
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
                .padding(.bottom, 4)

            Text("Florin")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Florin.text)

            Text(Strings.device("v2.onboard.tagline", "Vos comptes, votre budget, votre patrimoine — sur votre téléphone, et nulle part ailleurs."))
                .font(.system(size: 16))
                .foregroundStyle(Florin.text2)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 34)

            HStack(spacing: 8) {
                Image(systemName: "lock.fill").font(.system(size: 11, weight: .semibold))
                Text(Strings.device("v2.onboard.noAccount", "Aucun compte à créer. Aucune donnée envoyée."))
                    .font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(Florin.text3)
            .padding(.top, 4)
        }
    }

    private var fork: some View {
        VStack(spacing: 18) {
            Text(Strings.device("v2.onboard.howStart", "Comment voulez-vous commencer ?"))
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(Florin.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            VStack(spacing: 10) {
                choice(
                    .bank,
                    emoji: "🏛️",
                    title: Strings.device("v2.onboard.bankTitle", "Connecter ma banque"),
                    detail: Strings.device("v2.onboard.bankDetail", "Vos comptes, vos soldes et vos opérations arrivent tout seuls.")
                )
                choice(
                    .manual,
                    emoji: "✍️",
                    title: Strings.device("v2.onboard.manualTitle", "Saisir mes comptes"),
                    detail: Strings.device("v2.onboard.manualDetail", "Vous entrez ce que vous avez, et vous ajoutez vos opérations vous-même.")
                )
            }
            .padding(.horizontal, Florin.gutter)
            .padding(.top, 4)

            if path == .bank {
                /*
                 * Said here rather than discovered two screens later.
                 *
                 * Connecting a bank still goes through a Florin server: the
                 * on-device version of that flow — the key in the Keychain, the
                 * signed request, the bank's own sign-in — is not built yet.
                 * Offering the choice and staying quiet about what it needs
                 * would be the kind of promise that turns into a dead end.
                 */
                Text(Strings.device("v2.onboard.bankPrivacy", "Vos comptes se connectent depuis ce téléphone. Rien ne transite par un serveur."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Florin.text3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .transition(.opacity)
            }
        }
    }

    private func choice(
        _ value: StartPath,
        emoji: String,
        title: String,
        detail: String
    ) -> some View {
        let picked = path == value
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy(duration: 0.22)) { path = value }
        } label: {
            HStack(spacing: 14) {
                Text(emoji).font(.system(size: 26))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Florin.text)
                    Text(detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Florin.text2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(picked ? Florin.accent : Florin.text3)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(picked ? Florin.accent.opacity(0.18) : .clear)
            )
            .florinGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var account: some View {
        VStack(spacing: 20) {
            Text(Strings.device("v2.onboard.firstAccount", "Votre premier compte"))
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Florin.text)

            Text(Strings.device("v2.onboard.firstAccountHint", "Celui que vous regardez en premier le matin."))
                .font(.system(size: 14))
                .foregroundStyle(Florin.text2)

            TextField(Strings.device("v2.onboard.accountPlaceholder", "Compte courant"), text: $name)
                .font(.system(size: 17, weight: .medium))
                .multilineTextAlignment(.center)
                .focused($focus, equals: .name)
                .submitLabel(.next)
                .onSubmit { focus = .balance }
                .padding(.vertical, 15)
                .padding(.horizontal, 18)
                .florinGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, Florin.gutter)
                .padding(.top, 4)

            kindPicker

            VStack(spacing: 4) {
                Text(Strings.device("v2.account.balanceQuestion", "Combien y a-t-il dessus aujourd'hui ?"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Florin.text3)

                /*
                 * Sized to the text so the number and its symbol stay centred
                 * as a unit at every length — the same trick the assign sheet
                 * uses, and for the same reason: a right-aligned field made the
                 * one thing the screen is about drift as you typed.
                 */
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TextField("0", text: $balanceText)
                        .font(.system(size: 40, weight: .light))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .keyboardType(.numbersAndPunctuation)
                        .focused($focus, equals: .balance)
                        .fixedSize()
                    Text("€")
                        .font(.system(size: 20))
                        .foregroundStyle(Florin.text3)
                }
            }
            .padding(.top, 6)
        }
    }

    private var kindPicker: some View {
        HStack(spacing: 8) {
            ForEach(AccountKind.allCases, id: \.self) { option in
                let picked = option == kind
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    kind = option
                } label: {
                    VStack(spacing: 5) {
                        Text(option.emoji).font(.system(size: 19))
                        Text(option.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(picked ? Florin.text : Florin.text3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(picked ? Florin.accent.opacity(0.22) : .clear)
                    )
                    .florinGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Florin.gutter)
    }

    /*
     * Asked once, and asked here.
     *
     * iOS puts this prompt to a person exactly once in the life of an install:
     * decline it and the only way back is Settings, which nobody finds. So the
     * system dialog is never raised on arrival — this page makes the case
     * first, and only the button that means yes goes on to summon it. Saying
     * "plus tard" here costs nothing and leaves the real prompt unspent.
     *
     * Only on the bank path. With no bank connected there is nothing to
     * announce, and asking to send what does not exist spends the one prompt
     * on nothing.
     */
    private var notify: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.badge")
                .font(.system(size: 46))
                .foregroundStyle(Florin.accent)

            Text(Strings.device("v2.onboard.notifyTitle", "Vous tenir au courant ?"))
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(Florin.text)
                .multilineTextAlignment(.center)

            Text(Strings.device(
                "v2.onboard.notifyBody",
                "Florin interroge votre banque quelques fois par jour et vous envoie un résumé de ce qui est arrivé — un seul message, pas un par opération. Vous pourrez changer d'avis dans les réglages."
            ))
                .font(.system(size: 15))
                .foregroundStyle(Florin.text2)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 32)
        }
    }

    private var ready: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Florin.positive)

            Text(Strings.device("v2.onboard.ready", "C'est prêt"))
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Florin.text)

            /*
             * Say who did it.
             *
             * This read "vos catégories sont en place" — announcing as settled
             * something the app had chosen on its own, without asking. Naming
             * Florin as the one that picked them, and saying they can be
             * changed, is the difference between a summary and a claim.
             */
            Text(
                path == .bank
                    ? Strings.device(
                        "v2.onboard.readyBank",
                        "Florin a préparé quelques catégories courantes — à vous de les changer. Il reste à connecter votre banque, dans les réglages."
                    )
                    : Strings.device(
                        "v2.onboard.readyManual",
                        "Florin a préparé quelques catégories courantes — à vous de les changer. Vous pouvez ajouter vos opérations dès maintenant."
                    )
            )
                .font(.system(size: 15))
                .foregroundStyle(Florin.text2)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Chrome

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0...lastStep, id: \.self) { index in
                Capsule()
                    .fill(index == step ? Florin.text : Florin.text3.opacity(0.4))
                    .frame(width: index == step ? 18 : 6, height: 6)
            }
        }
        .animation(.snappy(duration: 0.28), value: step)
    }

    private var primaryAction: some View {
        Button {
            advance()
        } label: {
            HStack(spacing: 8) {
                if saving { ProgressView().tint(.black) }
                Text(
                    isNotifyStep
                        ? Strings.device("v2.onboard.notifyEnable", "Me tenir au courant")
                        : step == lastStep
                            ? (path == .bank
                                ? Strings.device("v2.onboard.bankTitle", "Connecter ma banque")
                                : Strings.device("v2.onboarding.start", "Commencer"))
                            : Strings.device("v2.onboard.continue", "Continuer")
                )
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Florin.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(saving || !canAdvance)
        .opacity(canAdvance ? 1 : 0.4)
    }

    /// Nothing to continue to until the fork has been answered — advancing
    /// with no path chosen used to land on the closing page having skipped
    /// the only question that decides what the app does next.
    private var canAdvance: Bool { step != 1 || path != nil }

    @ViewBuilder
    private var secondaryAction: some View {
        if isNotifyStep {
            Button {
                // Straight on, without raising the system prompt: an unanswered
                // permission can still be granted later, a declined one is a
                // trip to Settings nobody makes.
                onNeedsBank()
            } label: {
                Text(Strings.device("v2.onboard.notifyLater", "Plus tard"))
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Florin.text3)
            }
            .buttonStyle(.plain)
        } else if step == 0 {
            Button(action: onUseServer) {
                Text(Strings.device("v2.onboard.haveServer", "J'ai déjà un serveur Florin"))
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Florin.text3)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Doing the thing

    private func advance() {
        focus = nil
        guard step == lastStep else {
            withAnimation { step += 1 }
            return
        }
        /*
         * The bank path finishes here, on the device.
         *
         * It used to hand off to the server form, because when this screen was
         * written connecting a bank from the phone did not exist yet. It does
         * now — key, certificate, consent and sync all run here — so sending
         * someone to set up a server to reach it was leftover wiring, and it
         * contradicted the sentence two screens earlier promising the phone
         * and nowhere else.
         *
         * Nothing is written: accounts and balances come from the bank.
         */
        if path == .bank {
            saving = true
            Task {
                let granted = await BackgroundRefresh.requestPermission()
                UserDefaults.standard.set(granted, forKey: "florin.notifications")
                if granted { BackgroundRefresh.schedule() }
                saving = false
                onNeedsBank()
            }
            return
        }
        saving = true
        do {
            try LocalOnboarding.createFirstAccount(
                name: name.trimmingCharacters(in: .whitespaces),
                kind: kind,
                balance: Self.parse(balanceText)
            )
            saving = false
            onFinish()
        } catch {
            saving = false
            failure = error.localizedDescription
        }
    }

    /// Accepts what people actually type: a comma or a dot, spaces in the
    /// thousands, a currency symbol left in by habit.
    static func parse(_ text: String) -> Double {
        let cleaned = text
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." || $0 == "-" }
        return Double(cleaned) ?? 0
    }
}
