import SwiftUI

/// The dashboard, natively.
///
/// Same numbers as the browser — they come from the same `queries.*` calls over
/// `/api/v2/overview` — but every pixel here is SwiftUI: real scroll physics, a
/// Swift Charts hero with haptic scrub, and a large title that collapses into
/// the navigation bar the way iOS does it rather than the way CSS imitates it.
struct OverviewScreen: View {
    @ObservedObject var model: OverviewModel
    @ObservedObject var chrome: ChromeState
    /// Switches the native tab bar. A tile that opens another tab must move the
    /// selection with it, or the user lands on a screen the bar says they are
    /// not on.
    var route: (TabRoute, String) -> Void = { _, _ in }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var pushed: [String] = []
    @State private var adding = false
    @State private var addingAccount = false
    @State private var connectingBank = false
    @State private var upcomingExpanded = false
    @State private var attachExpanded = false
    @State private var reviewExpanded = false
    @State private var scrubbed: PatrimonyPoint?
    @State private var range: Range = .year
    @State private var showGross = false
    /// The delta line answers two different questions; a tap swaps them.
    @State private var showSaving = false
    /// The movement whose destination is being asked about.
    @State private var attaching: Transaction?
    /// Ids already offered this session, so the sheet asks once and the group
    /// below carries it from then on.
    @State private var asked: Set<String> = []

    /// The served table once it exists, the bundled one before it does — the
    /// failed state renders with no feed behind it, by definition.
    private var t: Strings { model.overview?.t ?? .device }

    enum Range: String, CaseIterable, Identifiable {
        case month, quarter, half, year, all
        var id: String { rawValue }

        /// Served, like every other string — "1A" and "Tout" are French, and a
        /// hardcoded label is exactly how half a screen ends up in the wrong
        /// language.
        var key: (String, String) {
            switch self {
            case .month: return ("v2.range.1m", "1M")
            case .quarter: return ("v2.range.3m", "3M")
            case .half: return ("v2.range.6m", "6M")
            case .year: return ("v2.range.1y", "1A")
            case .all: return ("v2.range.all", "Tout")
            }
        }

        var days: Double {
            switch self {
            case .month: return 31
            case .quarter: return 92
            case .half: return 183
            case .year: return 366
            case .all: return .infinity
            }
        }
    }

    var body: some View {
        NavigationStack(path: $pushed) {
            ZStack {
                Backdrop(tint: TabRoute.overview.tint)
                content
            }
            // Plan, Review, Categories and Tools have no tab of their own, so
            // they push here instead of stealing an unrelated one.
            .navigationDestination(for: String.self) { target in
                WebScreen(
                    base: model.base,
                    path: target,
                    homeTab: nil,
                    appearance: colorScheme,
                    chrome: chrome,
                    onRequestSettings: {},
                    onCrossTab: route,
                    onPush: { pushed.append($0) }
                )
            }
            // No navigation bar at all: the wordmark repeated what the app
            // icon already says, and the sync control moved into the action arc
            // where the thumb is. Removing the bar hands ~56pt back to the
            // figure that matters.
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $connectingBank) {
            BankingSettings(onConnected: {
                connectingBank = false
                Task { await model.load(showSpinner: false) }
            })
        }
        .sheet(isPresented: $addingAccount) {
            AddAccountSheet(onSaved: { Task { await model.load(showSpinner: false) } })
        }
        .sheet(item: $attaching) { tx in
            AttachTransferSheet(
                transaction: tx,
                accounts: model.overview?.accounts ?? [],
                locale: model.overview?.localeTag ?? "fr-FR",
                currency: model.overview?.currency ?? "EUR",
                t: t,
                onAttach: { await attach(tx, to: $0) },
                onSpending: { route(.activity, "/m/transactions?needsReview=1") }
            )
        }
        /*
         * Asked once, when it is fresh.
         *
         * A card alone can be ignored for months while the net worth stays
         * wrong; a prompt on every launch would be nagging about something
         * that happens twice a year. So the sheet comes up the first time a
         * movement is seen, and the group on the dashboard keeps it reachable
         * afterwards.
         */
        .task(id: model.overview?.generatedAt) {
            guard attaching == nil, adding == false else { return }
            if let first = model.dangling.first(where: { !asked.contains($0.id) }) {
                asked.insert(first.id)
                attaching = first
            }
        }
        .sheet(isPresented: $adding) {
            if let data = model.overview {
                AddTransactionSheet(
                    data: data,
                    submit: { try await model.add($0) },
                    onTransfer: { try await model.addTransfer($0) }
                )
            }
        }
        .task { await model.onForeground() }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from the background is the moment the figures are most
            // likely stale; the bank pull behind this is throttled to six hours.
            if phase == .active { Task { await model.onForeground() } }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView().controlSize(.large).tint(Florin.text3)
        case .failed(let message):
            ContentUnavailableView {
                Label(offlineTitle, systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                VStack(spacing: 10) {
                    Button(t("v2.common.retry", "Réessayer")) {
                        Task { await model.load() }
                    }
                    .buttonStyle(.borderedProminent)
                    .modifier(GlassProminentButton())

                    // Half the reasons this screen appears are fixed in
                    // Settings — a wrong address, a missing token — so put the
                    // door right here instead of making the user find it.
                    Button(t("v2.settings.title", "Réglages")) {
                        route(.settings, TabRoute.settings.rootPath)
                    }
                }
            }
        case .loaded(let data):
            loaded(data)
        }
    }

    /// Writes through an animation, so the curve stretches into its new window
    /// instead of being replaced by it.
    private var animatedRange: Binding<Range> {
        Binding(
            get: { range },
            set: { next in
                guard next != range else { return }
                scrubbed = nil
                withAnimation(.smooth(duration: 0.55)) { range = next }
            }
        )
    }

    /// First of the current month, for the "spent this month" filter link.
    private var monthStart: String {
        let now = Date()
        let c = Calendar.current.dateComponents([.year, .month], from: now)
        return String(format: "%04d-%02d-01", c.year ?? 2026, c.month ?? 1)
    }

    /// The curve the headline is currently naming.
    ///
    /// These are genuinely two different shapes, not one shifted copy: the
    /// server rebuilds the loan balance at every past date, so the net line
    /// dips further back when more was owed while the gross line — assets, which
    /// never involved the loan — keeps its own path. Older servers send neither,
    /// in which case both fall back to the single series they do send.
    private func curve(_ data: Overview) -> [PatrimonyPoint] {
        let full = showGross ? (data.grossSeries ?? data.series) : (data.netSeries ?? data.series)
        guard range != .all, let last = full.last else { return full }
        let from = last.day.addingTimeInterval(-range.days * 86_400)
        let slice = full.filter { $0.day >= from }
        return slice.count >= 2 ? slice : Array(full.suffix(2))
    }

    private func loaded(_ data: Overview) -> some View {
        let points = curve(data)
        let first = points.first?.balance ?? data.netWorth.net
        // Tapping the hero swaps net for gross. Both are the "how much do I
        // have" answer and which one you want changes with the question; a
        // second permanent figure would just be clutter. Scrubbing always shows
        // net, because the curve is the net-worth series.
        let headline = showGross ? data.netWorth.gross : data.netWorth.net
        let shown = scrubbed?.balance ?? headline
        let delta = scrubbed.map { $0.balance - first }
            ?? (data.netWorth.net - (data.netWorth.netMonthAgo ?? data.netWorth.net))

        /*
         * Nothing to show is a different screen, not a screen of zeros.
         *
         * A fresh install landed on 0,00 EUR of net worth, 0 left to spend,
         * -0 spent and a flat chart. Every figure was right and the screen was
         * useless: it answered questions nobody had yet, offered nothing to do
         * about it, and looked broken rather than new.
         */
        if data.accounts.isEmpty && data.recent.isEmpty {
            return AnyView(
                ScrollView {
                    EmptyStart(
                        t: data.t,
                        // Opens the thing it names. Routing to the settings
                        // tab and leaving someone to find the right row there
                        // is not what "Connecter ma banque" says it does.
                        onConnectBank: { connectingBank = true },
                        onAddManually: { addingAccount = true }
                    )
                }
                .scrollIndicators(.hidden)
            )
        }

        return AnyView(
            ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                // Say plainly that these figures are not live, rather than
                // letting an hour-old balance pass for the current one.
                if let staleSince = model.staleSince {
                    HStack(spacing: 7) {
                        Image(systemName: "wifi.slash").font(.system(size: 12, weight: .semibold))
                        Text(
                            data.t("v2.overview.offline", "Hors ligne — données de {date}",
                                   ["date": DayLabel.string(staleSince, locale: data.localeTag, t: data.t)])
                        )
                        .font(.system(size: 12.5))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Florin.text2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .florinGlass(in: Capsule())
                    .padding(.horizontal, Florin.gutter)
                }

                hero(data, points: points, shown: shown, delta: delta)
                /*
                 * An account but no money in it yet is its own screen too.
                 *
                 * The zeros screen was already replaced for someone with
                 * nothing at all — but finishing onboarding creates an
                 * account, so nobody reached that state and everyone landed
                 * back on it: an empty curve, "Aucun salaire détecté sur
                 * 90 jours", −0 € spent, and an empty "Dernières opérations"
                 * heading. Every figure true, the whole screen useless.
                 *
                 * Until there is a first transaction, the honest screen is the
                 * account they just created and the two ways to fill it.
                 */
                if data.recent.isEmpty {
                    firstSteps(data)
                    accounts(data)
                } else {
                    /*
                     * Straight after the hero, before the tiles.
                     *
                     * Opening the app to "what just happened" is the whole reason
                     * anyone opens it, and a list is the one section that survives
                     * being cut off by the tab bar — you can see there is more and
                     * scroll. A KPI tile clipped in half just looks broken, which
                     * is exactly what "Reste à vivre" did sitting in this slot.
                     */
                    recent(data)
                    kpis(data)
                    monthEnd(data)
                    accounts(data)
                    allocation(data)
                    savings(data)
                    if let goal = data.goal, goal.target > 0 { goalCard(goal, data) }
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 104)
        }
            .scrollIndicators(.hidden)
            // Drives the tab bar's collapse, same signal the web tabs report.
            .modifier(ScrollReporter { chrome.scrolled(to: $0) })
            // iOS 26 fades content into the bars instead of hard-clipping it.
            .modifier(SoftScrollEdge())
            // Pull down to actually pull the banks, not just re-read the server.
            .refreshable { await model.refresh() }
        )
    }

    // MARK: - Sections

    /*
     * The headline, composed the way neobanks compose it.
     *
     * The old version pinned the figure to the top-left under the status bar,
     * which is where a document title goes, not where a balance goes — it read
     * as a label rather than the point of the screen. Revolut, Monzo and N26
     * all centre it in the upper third with air around it, a small caption
     * above, and an action row beneath. That is what this is: caption, figure,
     * a pill that goes where the figure leads, then the chart, then the round
     * actions. The colour behind it comes from `Backdrop`.
     */
    private func hero(_ data: Overview, points: [PatrimonyPoint], shown: Double, delta: Double) -> some View {
        VStack(spacing: 0) {
            headerRow(data)
                .padding(.horizontal, Florin.gutter)
                .padding(.bottom, 44)

            VStack(spacing: 10) {
                Text(
                    (showGross
                        ? data.t("v2.overview.gross", "Brut")
                        : data.t("v2.overview.netWorth", "Patrimoine"))
                        + " · " + data.currency
                )
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Florin.text2)

                HeroAmount(value: shown, locale: data.localeTag, currency: data.currency, size: 60)
                    .contentTransition(.numericText())

                HStack(spacing: 6) {
                    if showGross && scrubbed == nil {
                        Text(data.t("v2.overview.debt", "Dettes") + " "
                             + Money.string(data.netWorth.liability, locale: data.localeTag,
                                            currency: data.currency, decimals: false))
                            .font(.system(size: 14))
                            .foregroundStyle(Florin.text2)
                            .hiddenWhenPrivate()
                    } else if !data.recent.isEmpty, showSaving, let kept = data.leftToSpend.savedThisMonthToDate {
                        /*
                         * What you are keeping this month, against the same day
                         * of the last one.
                         *
                         * The line above it answers "how did last month go",
                         * which is stable and not what someone opening the app
                         * on the 28th wants to know. This answers "am I doing
                         * better than last month, right now" — and it has to
                         * count spending net of reimbursements, or a month with
                         * 986 € refunded reads as 298 € kept when the accounts
                         * gained 1 284 €.
                         */
                        Image(systemName: kept >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.system(size: 9))
                        AmountText(
                            value: abs(kept), locale: data.localeTag, currency: data.currency,
                            decimals: abs(kept) < 1000,
                            tone: kept >= 0 ? .positive : .negative, size: 14
                        )
                        /*
                         * Both figures, in as few words as they fit.
                         *
                         * "au même jour" was the honest phrasing and too long
                         * for a line sitting under a five-digit number. Naming
                         * the date does the same work in less room, and unlike
                         * a bare month name it cannot be misread as the whole
                         * of July — which would be a different, larger number.
                         *
                         * No verb either: the arrow already says the figure is
                         * a gain, and "gardés" only repeated it in a word.
                         */
                        Text(
                            data.leftToSpend.savedPrevMonthToDate.map {
                                data.t(
                                    "v2.overview.keptVsLastMonth", "vs {prev} ({date})",
                                    [
                                        "prev": Money.string(
                                            $0, locale: data.localeTag,
                                            currency: data.currency, decimals: false
                                        ),
                                        "date": Self.sameDayLastMonth(locale: data.localeTag),
                                    ]
                                )
                            } ?? data.t("v2.overview.keptThisMonth", "ce mois-ci")
                        )
                        .font(.system(size: 14))
                        .foregroundStyle(Florin.text2)
                    } else if !data.recent.isEmpty {
                        // "0,00 € sur un mois" on a ledger with no month behind
                        // it states a movement that never happened.
                        Image(systemName: delta >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.system(size: 9))
                        AmountText(
                            value: abs(delta), locale: data.localeTag, currency: data.currency,
                            decimals: abs(delta) < 1000,
                            tone: delta >= 0 ? .positive : .negative, size: 14
                        )
                        // The month it is, not "over a month". The figure is
                        // the last complete calendar month's change, and a
                        // caption that hides which month invites exactly the
                        // reading the old measure made wrong.
                        Text(
                            scrubbed.map { DayLabel.string($0.day, locale: data.localeTag, t: data.t) }
                                ?? data.t(
                                    "v2.overview.inMonth", "en {month}",
                                    ["month": MonthLabel.short(
                                        LocalQueries.lastCompleteMonth(), locale: data.localeTag
                                    )]
                                )
                        )
                            .font(.system(size: 14))
                            .foregroundStyle(Florin.text2)
                    }
                }
                .frame(height: 20)
                /*
                 * The delta line is its own question, so it takes its own tap.
                 *
                 * Last month's change is stable and says nothing about today;
                 * what you are keeping right now says nothing about whether the
                 * month closed well. Both are worth having and neither should
                 * displace the other, so one is a tap away from the other. The
                 * gesture sits inside the headline's and wins in its own frame,
                 * which keeps the big number's own tap intact.
                 */
                .contentShape(Rectangle())
                .onTapGesture {
                    guard scrubbed == nil, data.leftToSpend.savedThisMonthToDate != nil else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.smooth(duration: 0.35)) { showSaving.toggle() }
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                guard scrubbed == nil else { return }
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.smooth(duration: 0.5)) { showGross.toggle() }
            }
            .onLongPressGesture(minimumDuration: 0.45) { Privacy.shared.toggle() }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)

            // A ledger with no transactions draws a flat line at the opening
            // balance, which is not a history — it is a horizontal rule with a
            // date axis. Nothing is more honest than not drawing it.
            if !data.recent.isEmpty {
                NetWorthChart(
                    points: points,
                    selection: $scrubbed,
                    animationKey: range.rawValue + (showGross ? "-gross" : "-net"),
                    tint: showGross ? Florin.series[3] : Florin.accent
                )
                .padding(.top, 22)
            }

            // The range control picks a window over a history. With no
            // history it is four buttons that all do the same nothing.
            if !data.recent.isEmpty {
                Picker("", selection: animatedRange) {
                    ForEach(Range.allCases) { range in
                        let (key, fallback) = range.key
                        Text(data.t(key, fallback)).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, Florin.gutter)
                .padding(.top, 14)
            }
        }
    }

    /*
     * The screen for an account with nothing in it yet.
     *
     * Not a placeholder and not a tour: two things a person can do right now,
     * in the order most people will want them. The bank first, because it is
     * the one that fills the app on its own; by hand second, because it always
     * works and some accounts will never sync.
     *
     * Both open what they name. Sending someone to Réglages to hunt for the
     * right row is how a call to action becomes a chore.
     */
    private func firstSteps(_ data: Overview) -> some View {
        section(data.t("v2.overview.firstSteps", "Pour commencer")) {
            VStack(spacing: 10) {
                Text(
                    data.t(
                        "v2.overview.firstStepsBody",
                        "Votre compte est prêt. Il ne lui manque que des opérations — Florin s'occupe du reste."
                    )
                )
                .font(.system(size: 14))
                .foregroundStyle(Florin.text2)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 2)

                if model.base.scheme == "florin-local" {
                    firstStep(
                        symbol: "building.columns",
                        title: data.t("v2.empty.bankTitle", "Connecter ma banque"),
                        detail: data.t(
                            "v2.empty.bankBody",
                            "Comptes, soldes et opérations arrivent tout seuls. Environ deux minutes, une seule fois."
                        ),
                        prominent: true
                    ) { connectingBank = true }
                }

                firstStep(
                    symbol: "square.and.pencil",
                    title: data.t("v2.overview.firstStepManualTitle", "Ajouter une opération"),
                    detail: data.t(
                        "v2.overview.firstStepManual",
                        "Une dépense ou une entrée, saisie à la main."
                    ),
                    prominent: false
                ) { adding = true }
            }
            .padding(.horizontal, Florin.gutter)
        }
    }

    private func firstStep(
        symbol: String, title: String, detail: String, prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        }) {
            HStack(spacing: 13) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(prominent ? Florin.accent : Florin.text2)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Florin.text)
                    Text(detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Florin.text2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Florin.text3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .florinSurface()
            .overlay(
                RoundedRectangle(cornerRadius: Florin.cardRadius, style: .continuous)
                    .stroke(prominent ? Florin.accent.opacity(0.4) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "28 juil." — the same day one month back, clipped to that month's last
    /// day so the 31st does not name a date that never existed.
    private static func sameDayLastMonth(locale: String) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        guard let prev = calendar.date(byAdding: .month, value: -1, to: now) else { return "" }
        let last = calendar.range(of: .day, in: .month, for: prev)?.count ?? 28
        var parts = calendar.dateComponents([.year, .month], from: prev)
        parts.day = min(calendar.component(.day, from: now), last)
        guard let date = calendar.date(from: parts) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: locale)
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f.string(from: date)
    }

    private func attach(_ tx: Transaction, to accountId: String) async {
        do {
            try await model.attachTransfer(tx.id, to: accountId)
        } catch {
            model.toast = ToastMessage(text: error.localizedDescription, kind: .failure)
        }
    }

    /// Avatar, search, sync — the row every neobank puts above the balance.
    private func headerRow(_ data: Overview) -> some View {
        HStack(spacing: 10) {
            // Same bare gear as every other screen — see TopBar.
            Button { route(.settings, TabRoute.settings.rootPath) } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 21))
                    .foregroundStyle(Florin.text2)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(data.t("v2.settings.title", "Réglages"))

            Button { route(.activity, TabRoute.activity.rootPath) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                    Text(data.t("v2.common.search", "Rechercher"))
                        .font(.system(size: 15))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Florin.text2)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .florinGlass(in: Capsule())
            }
            .buttonStyle(.plain)

            /*
             * The one action with no home in the tab bar.
             *
             * The row of shortcuts under the chart went: Plan, Activité and
             * Analyse are tabs a thumb away, "Plus" only opened an arc whose
             * every item is now one tap, and the review queue says what it
             * needs to say as a badge on the Activité tab. Recording something
             * is the exception — so it takes the corner the sync button had.
             * Syncing still happens on every open, on pull-to-refresh, from
             * Comptes, and from Réglages; it did not need a fourth door.
             */
            CircleButton(symbol: "plus", size: 44, prominent: true) { adding = true }
                .accessibilityLabel(data.t("v2.add.transaction", "Transaction"))
        }
    }

    private func kpis(_ data: Overview) -> some View {
        let lts = data.leftToSpend
        return HStack(spacing: 12) {
            Button { route(.plan, TabRoute.plan.rootPath) } label: {
            FlorinCard {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: data.t("v2.overview.leftToSpend", "Reste à vivre"))
                    AmountText(
                        value: lts.leftToSpend, locale: data.localeTag, currency: data.currency,
                        decimals: false, tone: lts.leftToSpend >= 0 ? .neutral : .negative,
                        size: 26, weight: .light
                    )
                    Text(
                        lts.dailyBudgetRemaining.map { daily -> String in
                            let amount = Money.string(daily, locale: data.localeTag,
                                                      currency: data.currency, decimals: false)
                            let days = data.t("v2.overview.daysLeft", "{count} j restants",
                                              ["count": lts.daysRemaining])
                            return amount + data.t("v2.common.perDay", "/jour") + " · " + days
                        } ?? data.t("v2.overview.leftToSpendNone", "Aucun salaire détecté sur 90 jours")
                    )
                    .font(.system(size: 11.5))
                    .foregroundStyle(Florin.text3)
                    .hiddenWhenPrivate()
                }
            }
            }
            .buttonStyle(.plain)

            Button { route(.activity, "/m/transactions?direction=expense&from=\(monthStart)") } label: {
            FlorinCard {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: data.t("v2.overview.spent", "Dépensé"))
                    AmountText(
                        value: data.burnThisMonth, locale: data.localeTag, currency: data.currency,
                        decimals: false, size: 26, weight: .light
                    )
                    Text(data.t("v2.overview.spentAvg", "moy. 6 mois {amount}", ["amount": Money.string(data.burnAvg6, locale: data.localeTag, currency: data.currency, decimals: false)]))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Florin.text3)
                        .hiddenWhenPrivate()
                }
            }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Florin.gutter)
    }

    private func monthEnd(_ data: Overview) -> some View {
        let lts = data.leftToSpend
        /*
         * The same projection the web card runs — see computeMonthForecast.
         *
         * A month is two things: bills that land whichever day the bank
         * chooses but always land, and a daily habit that can genuinely be
         * lighter than usual. The fixed part is carried whole; the variable
         * part is a daily rate scaled to the month, blended with this
         * account's own history by how much of the month has been observed.
         *
         * It replaces a floor that clamped the projection to the six-month
         * average right up to the last day, so a month spent 500 € under
         * budget still reported an average month and the saving never showed.
         */
        // The prior's weight decays as the month fills in — three days say
        // nothing, the 28th says almost everything. 60 is where measurement
        // puts the minimum; see computeMonthForecast.
        let priorDays = 60.0
        let daysInMonth = Double(lts.daysElapsed + lts.daysRemaining)
        let elapsed = Double(lts.daysElapsed)
        let priorWeight = daysInMonth > 0 ? priorDays * (1 - elapsed / daysInMonth) : 0
        let expectedFixed = lts.expectedMonthlyFixed ?? 0
        let variable = max(0, lts.monthSpent - lts.monthSpentFixed)
        let observedDaily = elapsed > 0 ? variable / elapsed : 0
        let priorDaily = daysInMonth > 0
            ? max(0, lts.expectedMonthlySpend - expectedFixed) / daysInMonth
            : 0
        let weight = elapsed + priorWeight
        let blendedDaily = weight > 0
            ? (elapsed * observedDaily + priorWeight * priorDaily) / weight
            : observedDaily
        let fixedComponent = max(lts.monthSpentFixed, expectedFixed)
        let projectedGross = max(lts.monthSpent, blendedDaily * daysInMonth + fixedComponent)
        /*
         * Projected gross, margin net — see computeMonthForecast.
         *
         * Refunds arrive in lumps and late, so a model fed net spending stops
         * believing the month it describes. Gross is the predictable series;
         * the refunds already banked are simply known and subtracted. Future
         * ones are not predicted, which errs on the pessimistic side of a
         * margin — the harmless direction.
         */
        let refunds = lts.monthRefunds ?? 0
        let projected = max(lts.monthSpent - refunds, projectedGross - refunds)
        let margin = lts.monthIncome > 0 ? lts.monthIncome - projected : nil
        let ratio = lts.monthIncome > 0 ? min(1, projected / lts.monthIncome) : 1

        return section(data.t("v2.overview.forecast", "Fin de mois")) {
            Button { route(.plan, TabRoute.plan.rootPath) } label: {
            FlorinCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(data.t("v2.overview.forecastMargin", "Marge projetée")).font(.system(size: 12.5)).foregroundStyle(Florin.text2)
                            if let margin {
                                AmountText(
                                    value: margin, locale: data.localeTag, currency: data.currency,
                                    decimals: false, signed: true, tone: .auto, size: 24, weight: .light
                                )
                            } else {
                                Text("—").foregroundStyle(Florin.text3)
                            }
                        }
                        Spacer()
                        Text(data.t("v2.overview.daysLeft", "{count} j restants", ["count": lts.daysRemaining]))
                            .font(.system(size: 11.5)).foregroundStyle(Florin.text3)
                    }
                    ProgressView(value: ratio)
                        .tint((margin ?? 0) < 0 ? Florin.negative : Florin.accent)
                    HStack {
                        Text(Money.string(projected, locale: data.localeTag, currency: data.currency, decimals: false)
                             + " / " + Money.string(lts.monthIncome, locale: data.localeTag, currency: data.currency, decimals: false))
                        Spacer()
                        if lts.monthSpentFixed > 0 {
                            Text(data.t("v2.overview.forecastFixed", "dont {amount} de charges fixes", ["amount": Money.string(lts.monthSpentFixed, locale: data.localeTag, currency: data.currency, decimals: false)]))
                        }
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(Florin.text3)
                    .hiddenWhenPrivate()

                    if data.incomeIsEstimated {
                        // Otherwise the card quietly claims money that has not
                        // arrived: before payday the "income" is last month's.
                        Text(data.t(
                            "v2.overview.incomeEstimated",
                            "Salaire du mois pas encore reçu — basé sur le précédent"
                        ))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Florin.negative.opacity(0.9))
                    }
                }
            }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Florin.gutter)
        }
    }

    private func accounts(_ data: Overview) -> some View {
        section(data.t("v2.overview.yourAccounts", "Vos comptes")) {
            RowGroup {
                ForEach(Array(data.accounts.enumerated()), id: \.element.id) { index, account in
                    if index > 0 { Hairline() }
                    Button { route(.accounts, "/m/accounts/\(account.id)") } label: {
                        AccountRowView(account: account, locale: data.localeTag, currency: data.currency)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Florin.gutter)
        }
    }

    private func recent(_ data: Overview) -> some View {
        // Announced but not booked: dated ahead, so by date they crowd the top
        // of "dernières opérations", which is meant to answer what just
        // happened. Folded into one line above, and out of the six below.
        let upcoming = data.recent.filter(\.isUpcoming)
        // Waiting on the bank and waiting on you are two different queues, and
        // a row cannot be in both: an unsettled charge is not yours to file
        // yet. Split before either group is drawn.
        let toReview = data.recent.filter { !$0.isUpcoming && $0.needsReview }
        let settled = data.recent.filter { !$0.isUpcoming && !$0.needsReview }

        return section(data.t("v2.overview.recent", "Dernières opérations")) {
            VStack(spacing: 12) {
                if !upcoming.isEmpty {
                    UpcomingGroup(
                        transactions: upcoming,
                        locale: data.localeTag,
                        currency: data.currency,
                        t: data.t,
                        expanded: $upcomingExpanded
                    ) { tx in
                        // Same destination as every other row on this screen.
                        // A line you can tap everywhere except inside one
                        // collapsible group reads as broken, not as special.
                        Button { route(.activity, "/m/transactions") } label: {
                            TransactionRowView(
                                hideUpcomingChip: true,
                                tx: tx, locale: data.localeTag,
                                currency: data.currency, t: data.t
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                /*
                 * What is waiting on you, at the top and counted.
                 *
                 * Rows needing a look were scattered down the list among rows
                 * already dealt with, so the one thing the screen asks of you
                 * was the one thing you had to hunt for. Collapsed by default
                 * like the upcoming group — the count is the message, the list
                 * is there when you want it.
                 */
                let dangling = model.dangling
                if !dangling.isEmpty {
                    UpcomingGroup(
                        transactions: dangling,
                        locale: data.localeTag,
                        currency: data.currency,
                        t: data.t,
                        symbol: "arrow.left.arrow.right",
                        tint: Florin.accent,
                        caption: data.t(
                            "v2.attach.count", "{count} à rattacher", ["count": dangling.count]
                        ),
                        expanded: $attachExpanded
                    ) { tx in
                        Button { attaching = tx } label: {
                            TransactionRowView(
                                tx: tx, locale: data.localeTag,
                                currency: data.currency, t: data.t
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !toReview.isEmpty {
                    UpcomingGroup(
                        transactions: toReview,
                        locale: data.localeTag,
                        currency: data.currency,
                        t: data.t,
                        symbol: "questionmark.circle",
                        tint: Florin.warn,
                        caption: data.t(
                            "v2.review.toCheckCount", "{count} à vérifier",
                            ["count": max(data.reviewCount, toReview.count)]
                        ),
                        expanded: $reviewExpanded
                    ) { tx in
                        Button { route(.activity, "/m/transactions?needsReview=1") } label: {
                            TransactionRowView(
                                tx: tx, locale: data.localeTag,
                                currency: data.currency, t: data.t
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                RowGroup {
                    ForEach(Array(settled.prefix(6).enumerated()), id: \.element.id) { index, tx in
                        if index > 0 { Hairline() }
                        Button { route(.activity, "/m/transactions") } label: {
                            TransactionRowView(
                                tx: tx, locale: data.localeTag,
                                currency: data.currency, t: data.t
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, Florin.gutter)
        }
    }

    private func allocation(_ data: Overview) -> some View {
        let slices: [(String, Double, Color)] = [
            (data.t("v2.overview.cash", "Liquidités"), data.allocation.cash, Florin.series[0]),
            (data.t("v2.overview.invested", "Investi"), data.allocation.invested, Florin.series[2]),
        ].filter { $0.1 > 0 }
        let total = slices.reduce(0) { $0 + $1.1 }

        return Group {
            if total > 0 {
                section(data.t("v2.overview.allocation", "Répartition")) {
                    FlorinCard {
                        AllocationCard(
                            slices: slices.map { (label: $0.0, value: $0.1, color: $0.2) },
                            center: Money.compact(total, locale: data.localeTag, currency: data.currency),
                            caption: data.t("v2.overview.gross", "Brut"),
                            locale: data.localeTag,
                            currency: data.currency
                        )
                    }
                    .padding(.horizontal, Florin.gutter)
                }
            }
        }
    }

    private func savings(_ data: Overview) -> some View {
        section(data.t("v2.overview.savingsRate", "Taux d'épargne")) {
            FlorinCard {
                VStack(spacing: 10) {
                    HStack {
                        rate("3", data.savings.threeMonth, data)
                        rate("6", data.savings.sixMonth, data)
                        rate("12", data.savings.twelveMonth, data)
                    }
                    Text(data.t("v2.overview.savingsRateHint", "Épargné ÷ revenus, sur mois complets"))
                        .font(.system(size: 11.5)).foregroundStyle(Florin.text3)
                }
            }
            .padding(.horizontal, Florin.gutter)
        }
    }

    private var offlineTitle: String {
        t("v2.overview.syncFailed", "Florin est injoignable")
    }

    private func rate(_ label: String, _ value: Double?, _ data: Overview) -> some View {
        VStack(spacing: 4) {
            Text(Money.percent(value, locale: data.localeTag, digits: 0))
                .font(.system(size: 22, weight: .light))
                .monospacedDigit()
                .foregroundStyle(value == nil ? Florin.text3 : ((value ?? 0) >= 0 ? Florin.positive : Florin.negative))
            Text("\(label) " + data.t("v2.common.months", "mois")).font(.system(size: 11.5)).foregroundStyle(Florin.text3)
        }
        .frame(maxWidth: .infinity)
    }

    private func goalCard(_ goal: Goal, _ data: Overview) -> some View {
        let progress = goal.target > 0 ? goal.currentValue / goal.target : 0
        let reached: String? = goal.reachDateIso.flatMap { iso in
            guard let date = PatrimonyPoint(date: iso, balance: 0).day as Date?, date != .distantPast else { return nil }
            let f = DateFormatter()
            f.locale = Locale(identifier: data.localeTag)
            f.setLocalizedDateFormatFromTemplate("MMMMy")
            return f.string(from: date)
        }

        return section(data.t("v2.overview.goal", "Objectif")) {
            FlorinCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Bubble(label: "objectif", systemImage: "target")
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                AmountText(value: goal.currentValue, locale: data.localeTag, currency: data.currency, decimals: false)
                                Text(data.t("v2.common.of", "sur") + " " + Money.string(goal.target, locale: data.localeTag, currency: data.currency, decimals: false))
                                    .font(.system(size: 15)).foregroundStyle(Florin.text3)
                                    .hiddenWhenPrivate()
                            }
                            Text(reached.map { data.t("v2.overview.goalReach", "Atteint en {date}", ["date": $0]) } ?? data.t("v2.overview.goalNever", "Hors d'atteinte à ce rythme"))
                                .font(.system(size: 12.5)).foregroundStyle(Florin.text2)
                        }
                        Spacer()
                        Text("\(Int((progress * 100).rounded()))%")
                            .font(.system(size: 15, weight: .medium)).monospacedDigit()
                    }
                    ProgressView(value: min(1, max(0, progress))).tint(Florin.series[6])
                    /*
                     * These two are the projected split of the TARGET at the
                     * reach date, not money already moved: of the 100 000 €,
                     * this much will come from deposits and this much from the
                     * market. Side by side under "Versé" and "Marché" they read
                     * as past tense, which made the card look like it was
                     * claiming 67 000 € already paid in. The web card was fixed
                     * the same way; this one had been left behind.
                     */
                    Text(
                        data.t(
                            "v2.overview.goalSplit",
                            "À l'arrivée : {you} de tes versements, {market} du marché",
                            [
                                "you": Money.string(goal.contributed, locale: data.localeTag,
                                                    currency: data.currency, decimals: false),
                                "market": Money.string(goal.marketGrowth, locale: data.localeTag,
                                                       currency: data.currency, decimals: false),
                            ]
                        )
                    )
                    .font(.system(size: 11.5)).foregroundStyle(Florin.text3)
                    .hiddenWhenPrivate()
                }
            }
            .padding(.horizontal, Florin.gutter)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: title).padding(.horizontal, Florin.gutter)
            content()
        }
    }
}


private struct GlassProminentButton: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content
        }
    }
}


/// `onScrollGeometryChange` is iOS 18+; the app deploys to 17, where the bar
/// simply stays expanded rather than the build failing.
private struct ScrollReporter: ViewModifier {
    let report: (CGFloat) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top
            } action: { _, y in
                report(y)
            }
        } else {
            content
        }
    }
}
