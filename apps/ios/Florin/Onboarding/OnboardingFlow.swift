import SwiftUI
import UniformTypeIdentifiers

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
    @State private var picking = false
    @State private var importing = false
    @State private var failure: String?
    /// How far the current page has been dragged sideways, in points — the
    /// live value of a swipe, before it is either committed or sprung back.
    @State private var drag: CGFloat = 0
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
        /*
         * Coming back, rather than starting.
         *
         * Restore lived only in Settings, which a fresh install cannot reach
         * without first inventing an account or connecting a bank — so the one
         * person who needs it most, someone holding a new phone and a file with
         * their whole ledger in it, was the one person made to build a decoy
         * first. It belongs on the screen that asks how you want to begin,
         * because for them that is the answer.
         */
        case restore
        /*
         * Neither the bank nor by hand.
         *
         * A great many accounts are not reachable over PSD2 — every French
         * livret, most of them — and typing a year of a savings account back in
         * is not a thing anyone does. The statement is a download away, and
         * offering it only from settings meant discovering it after already
         * having decided the app could not hold that account.
         */
        case importFile
    }

    /*
     * What is on screen, named — rather than counted.
     *
     * The step is a number because the dots and the swipe need it to be one,
     * but every place that asked "which page is this" was reading that number
     * *and* the path, and every one of them had to be revisited whenever a
     * page was inserted. Deriving the page once, here, is why splitting the
     * account form in two touched one function instead of six.
     */
    private enum Page { case welcome, fork, identity, balance, notify, ready }

    private var page: Page {
        let form = path == .manual || path == .importFile
        switch step {
        case 0: return .welcome
        case 1: return .fork
        case 2: return form ? .identity : .notify
        case 3: return form ? .balance : .ready
        default: return .ready
        }
    }

    /// The ground shifts colour as you advance — the same per-section tinting
    /// the tab bar does, used here to make the steps feel like a journey
    /// rather than identical pages.
    private var tint: Color {
        switch page {
        case .welcome: TabRoute.overview.tint
        case .fork, .identity, .balance, .notify: TabRoute.accounts.tint
        case .ready: TabRoute.plan.tint
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
    /*
     * The account form is two pages, not one.
     *
     * Name, kind and opening balance were stacked on a single screen, and the
     * balance — the only figure on it that ends up in the ledger — was the
     * runt at the bottom: a caption over a field, under a row of buttons,
     * with none of the sectioning the rest of the flow has. It reads as
     * filler rather than a question. A question this consequential gets the
     * screen the other questions get.
     */
    private var lastStep: Int {
        switch path {
        case .manual: 4
        case .restore: 1
        // The account the statement lands in, and then the file.
        case .importFile: 3
        default: 2
        }
    }

    /// The page that asks to be allowed to speak, on the path where it would
    /// have something to say.
    private var isNotifyStep: Bool { page == .notify && path == .bank }

    var body: some View {
        ZStack {
            Backdrop(tint: tint).ignoresSafeArea()

            VStack(spacing: 0) {
                /*
                 * The body of the page, and the whole of it is draggable.
                 *
                 * `Color.clear` takes the place the two Spacers used to — it
                 * is greedy the same way, still centres what sits on top of
                 * it, and gives the swipe a target the size of the page
                 * rather than the size of the sentence on it.
                 */
                ZStack {
                    Color.clear

                    Group {
                        switch page {
                        case .welcome: welcome
                        case .fork: fork
                        case .identity: identity
                        case .balance: balance
                        case .notify: notify
                        case .ready: ready
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }
                .contentShape(Rectangle())
                .offset(x: drag)
                .gesture(swipe)

                dots
                    .padding(.bottom, 18)

                primaryAction
                    .padding(.horizontal, Florin.gutter)
                    .padding(.bottom, 10)

                // At least a line, and as tall as the welcome's two actions.
                secondaryAction
                    .frame(minHeight: 30)

                backAction
                    .frame(height: 30)
                    .padding(.bottom, 10)
            }
        }
        .sheet(isPresented: $importing, onDismiss: { onFinish() }) {
            ImportSheet(
                t: .device,
                locale: Strings.device.localeTag,
                currency: "EUR",
                onDone: {}
            )
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.data]) { result in
            guard case let .success(url) = result, let store = LocalStore.shared else { return }
            saving = true
            Task {
                do {
                    _ = try LocalBackup.restore(from: url, into: store)
                    saving = false
                    onFinish()
                } catch {
                    saving = false
                    failure = error.localizedDescription
                }
            }
        }
        .onChange(of: step) { _, _ in
            /*
             * The page that asks for one number opens with the keypad up.
             *
             * Arriving on a screen whose entire purpose is a figure and having
             * to tap the figure first is a step that exists only because
             * nobody removed it. The identity page is left alone: its field
             * already carries a usable placeholder, and raising a keyboard
             * over the four kinds would hide half the question.
             */
            focus = page == .balance ? .balance : nil
        }
        .animation(Self.pageMotion, value: step)
        .animation(Self.pageMotion, value: tint)
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

            /*
             * Five starts do not fit every screen.
             *
             * Centred when they fit; scrolling when they do not, rather than
             * pushing the question up under the status bar and truncating the
             * last choice — which is what an iPad in iPhone mode showed.
             */
            ViewThatFits(in: .vertical) {
                startChoices
                ScrollView {
                    startChoices.padding(.vertical, 4)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
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

    private var startChoices: some View {
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
            choice(
                .importFile,
                emoji: "📄",
                title: Strings.device("v2.onboard.importTitle", "Importer un relevé"),
                detail: Strings.device("v2.onboard.importDetail", "Le fichier CSV ou OFX téléchargé chez votre banque.")
            )
            choice(
                .restore,
                emoji: "📦",
                title: Strings.device("v2.onboard.restoreTitle", "J'ai une sauvegarde"),
                detail: Strings.device("v2.onboard.restoreDetail", "Reprenez tout depuis un fichier exporté d'un autre téléphone.")
            )
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
        .buttonStyle(PressScale())
    }

    /*
     * Who the account is, on one page.
     *
     * Name and kind are the same question asked twice — what is this thing —
     * so they belong together, and nothing else belongs with them.
     */
    private var identity: some View {
        VStack(spacing: 18) {
            Text(Strings.device("v2.onboard.firstAccount", "Votre premier compte"))
                .font(.system(size: 26, weight: .semibold))
                // Large text reads too loose at its default tracking; the
                // bigger it is, the more it wants pulling in.
                .tracking(-0.4)
                .foregroundStyle(Florin.text)
                .multilineTextAlignment(.center)

            Text(Strings.device("v2.onboard.firstAccountHint", "Celui que vous regardez en premier le matin."))
                .font(.system(size: 14))
                .foregroundStyle(Florin.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            TextField(Strings.device("v2.onboard.accountPlaceholder", "Compte courant"), text: $name)
                .font(.system(size: 17, weight: .medium))
                .multilineTextAlignment(.center)
                .focused($focus, equals: .name)
                .submitLabel(.next)
                .onSubmit { advance() }
                .padding(.vertical, 15)
                .padding(.horizontal, 18)
                .florinGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, Florin.gutter)
                .padding(.top, 2)

            kindPicker
        }
    }

    /*
     * The one figure that lands in the ledger, given the screen.
     *
     * It is asked after the name rather than beside it because it is a
     * different kind of question: the name is a label, this is money, and the
     * answer decides what every number in the app says on the first morning.
     * Naming the account above the field keeps the two pages one thought.
     */
    private var balance: some View {
        VStack(spacing: 16) {
            HStack(spacing: 7) {
                Text(kind.emoji).font(.system(size: 14))
                Text(accountLabel)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Florin.text3)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .florinGlass(in: Capsule())

            Text(Strings.device("v2.account.balanceQuestion", "Combien y a-t-il dessus aujourd'hui ?"))
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(Florin.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 26)

            /*
             * Sized to the text so the number and its symbol stay centred as
             * a unit at every length — the same trick the assign sheet uses,
             * and for the same reason: a right-aligned field made the one
             * thing the screen is about drift as you typed.
             */
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("0", text: $balanceText)
                    .font(.system(size: 46, weight: .light))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .keyboardType(.numbersAndPunctuation)
                    .focused($focus, equals: .balance)
                    .fixedSize()
                Text("€")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Florin.text3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .florinGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, Florin.gutter)
            .padding(.top, 2)

            // Nobody knows their balance to the cent standing in a queue, and
            // being asked as though they should is what makes a person quit a
            // setup. Saying it costs a line.
            Text(Strings.device("v2.onboard.balanceHint", "À peu près suffit — vous corrigerez quand vous voudrez."))
                .font(.system(size: 12.5))
                .foregroundStyle(Florin.text3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    /// What the account will be called once written — the typed name, or the
    /// kind's own word, which is what `createFirstAccount` falls back to.
    private var accountLabel: String {
        let typed = name.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? kind.label : typed
    }

    /*
     * Four boxes the same size, which they were not.
     *
     * They were four columns of a single row, each sized by its own label, and
     * every language has one kind whose word is longer than the rest —
     * "Compte courant" wrapped to two lines while "Épargne" stayed on one, so
     * one box stood taller than its neighbours and the row looked broken. Two
     * columns give the longest of them — "Cuenta corriente", in Spanish — the
     * width to stay on one line, and a fixed height makes the four identical
     * whatever the word does: nothing about the layout is left to the
     * translation.
     */
    private var kindPicker: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            ForEach(AccountKind.allCases, id: \.self) { option in
                let picked = option == kind
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.snappy(duration: 0.22)) { kind = option }
                } label: {
                    VStack(spacing: 7) {
                        Text(option.emoji).font(.system(size: 22))
                        Text(option.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(picked ? Florin.text : Florin.text2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                    .frame(height: 74)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(picked ? Florin.accent.opacity(0.22) : .clear)
                    )
                    .florinGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(PressScale())
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

    // MARK: - Moving between pages

    /*
     * One spring for every page change, whatever caused it.
     *
     * Tapping "Continuer" and flicking the page are the same movement seen
     * from two sides, and a different curve for each is the kind of seam that
     * is felt before it is noticed. No bounce: nothing here was thrown, and
     * overshoot on a page that simply advanced reads as slack.
     */
    static let pageMotion = Animation.spring(response: 0.38, dampingFraction: 1)

    /*
     * The pages answer the finger.
     *
     * Five screens with a "Continuer" at the bottom is a slideshow with a
     * remote control; every other stack of cards on this phone can be pushed
     * with a thumb, and expecting that here and finding nothing is a small
     * dead spot in the one part of the app that has to feel alive. The page
     * tracks the finger one-to-one while it is held, resists at the ends
     * instead of stopping dead, and commits on where the flick was *going* —
     * iOS's own projection of it — rather than on how far it happened to
     * travel.
     *
     * Only between pages, never off the end of one: a swipe will not connect
     * a bank, write an account or open a file picker. Those are decisions,
     * and decisions are taken with a deliberate press.
     */
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                let dx = value.translation.width
                let free = dx < 0 ? canSwipeForward : canSwipeBack
                drag = free ? dx : Self.resisted(dx)
            }
            .onEnded { value in
                let projected = value.predictedEndTranslation.width
                let threshold = UIScreen.main.bounds.width * 0.3
                withAnimation(Self.pageMotion) {
                    if projected < -threshold, canSwipeForward {
                        focus = nil
                        step += 1
                    } else if projected > threshold, canSwipeBack {
                        goBack()
                    }
                    drag = 0
                }
            }
    }

    /// Forward, but never off the end: the last page of a path is a commitment
    /// — an account written, a bank connected, a file picked — and those are
    /// only ever taken by pressing the button that names them.
    private var canSwipeForward: Bool { step < lastStep && canAdvance }

    private var canSwipeBack: Bool { step > 0 }

    /// The further past the end it is pulled, the less it follows — Apple's
    /// own rubber band, so an edge reads as "there is nothing more here"
    /// rather than as a frozen screen.
    private static func resisted(_ offset: CGFloat) -> CGFloat {
        let dimension = UIScreen.main.bounds.width
        let constant: CGFloat = 0.55
        return (offset * dimension * constant) / (dimension + constant * abs(offset))
    }

    private func goBack() {
        focus = nil
        // Back into the fork resets the choice, so the next screen is the
        // question rather than the answer already given.
        if step == 1 { path = nil }
        step -= 1
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
                    path == .importFile && step == lastStep
                        ? Strings.device("v2.onboard.importPick", "Choisir le relevé")
                        : path == .restore && step == 1
                        ? Strings.device("v2.onboard.restorePick", "Choisir le fichier")

                        : isNotifyStep
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
        .buttonStyle(PressScale())
        .disabled(saving || !canAdvance)
        .opacity(canAdvance ? 1 : 0.4)
    }

    /// Nothing to continue to until the fork has been answered — advancing
    /// with no path chosen used to land on the closing page having skipped
    /// the only question that decides what the app does next.
    private var canAdvance: Bool { step != 1 || path != nil }

    /*
     * A way back, which there was not.
     *
     * Past the welcome screen both controls moved forward — on the bank step
     * the primary asked for notifications and the secondary said "plus tard",
     * and both went to the bank setup. Someone who picked the wrong option, or
     * who reached the bank screen and discovered they could not use it, had no
     * route to the other choices: the only exit was force-quitting the app,
     * which nothing on screen suggested.
     */
    @ViewBuilder
    private var backAction: some View {
        if step > 0 {
            Button {
                withAnimation(Self.pageMotion) { goBack() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text(Strings.device("v2.common.back", "Retour"))
                        .font(.system(size: 13.5, weight: .medium))
                }
                .foregroundStyle(Florin.text3)
                .padding(8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

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
            VStack(spacing: 16) {
                /*
                 * Looking around first, from the first screen.
                 *
                 * Every other start asks for something real — a bank, a
                 * balance, a file. Someone deciding whether Florin is worth
                 * their money, App Review included, gets a ledger of invented
                 * accounts instead, and takes it away again from Settings. It
                 * sits here rather than fifth in the list of starts, where it
                 * fell below the fold and nobody would have scrolled to it.
                 */
                Button(action: startDemo) {
                    Text(Strings.device("v2.onboard.demoTitle", "Essayer la démo"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Florin.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .florinGlass(in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(saving)
                .padding(.horizontal, Florin.gutter)

                Button(action: onUseServer) {
                    Text(Strings.device("v2.onboard.haveServer", "J'ai déjà un serveur Florin"))
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Florin.text3)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Doing the thing

    private func advance() {
        focus = nil
        guard step == lastStep else {
            withAnimation(Self.pageMotion) { step += 1 }
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
        if path == .restore {
            picking = true
            return
        }

        if path == .importFile {
            // The account first: a statement has to land somewhere, and the
            // balance is the one figure the file does not carry.
            saving = true
            do {
                try LocalOnboarding.createFirstAccount(
                    name: name.trimmingCharacters(in: .whitespaces),
                    kind: kind,
                    balance: Self.parse(balanceText)
                )
                saving = false
                importing = true
            } catch {
                saving = false
                failure = error.localizedDescription
            }
            return
        }
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

    /// Fills the ledger with the invented one and opens it.
    private func startDemo() {
        saving = true
        do {
            try LocalDemo.seed()
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

/*
 * Something happens the instant a finger lands.
 *
 * `.buttonStyle(.plain)` is how every control on these screens kept its own
 * look, and it also threw away the only feedback a button gives before it is
 * released: on the biggest, most-pressed control in the app — "Continuer" —
 * nothing at all moved until the page changed. The dip is small enough to
 * read as the surface giving, and it is on touch-down, not on the tap, which
 * is the whole point.
 */
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 1), value: configuration.isPressed)
    }
}
