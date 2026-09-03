import SwiftUI

/// Plan, natively — envelope budgeting for the month.
///
/// The one figure that matters is at the top and it is a verdict, not a total:
/// "à répartir" is either a positive number you still have to give a job to, or
/// a negative one meaning you have promised money you do not have. Everything
/// below is the same month broken down, and every line is editable in place —
/// a budget you cannot adjust from the phone is a budget you adjust never.
struct PlanScreen: View {
    @ObservedObject var overview: OverviewModel
    var route: (TabRoute, String) -> Void = { _, _ in }
    var onOpenSettings: () -> Void = {}

    @StateObject private var model: PlanModel
    @State private var collapsed: Set<String> = []
    /*
     * One sheet modifier, two destinations.
     *
     * Stacking two `.sheet` modifiers on the same view happens to work here
     * and is documented as undefined: which one owns the presentation is not
     * specified, and the loser can present detached content. A single modifier
     * over an enum has one owner, and the screen already needs somewhere to
     * say which of the two it wants.
     */
    @State private var sheet: PlanSheet?
    @State private var pickingSource = false
    /// How far the page has been dragged, how wide it is, and whether a turn
    /// is already under way — one gesture per page or the two animations
    /// overlap and fight each other.
    @State private var dragX: CGFloat = 0
    @State private var pageWidth: CGFloat = 400
    @State private var turning = false

    private enum PlanSheet: Identifiable {
        case assign(PlanCategory)
        case shape(CategoryDraft)
        /// Carries the count so the sheet can say how much is at stake before
        /// the user picks — the question only exists because it is not zero.
        case remove(PlanCategory, Int)

        var id: String {
            switch self {
            case let .assign(category): "assign:\(category.id)"
            case let .shape(draft): "shape:\(draft.id)"
            case let .remove(category, _): "remove:\(category.id)"
            }
        }
    }

    init(
        overview: OverviewModel,
        route: @escaping (TabRoute, String) -> Void = { _, _ in },
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.overview = overview
        self.route = route
        self.onOpenSettings = onOpenSettings
        _model = StateObject(wrappedValue: PlanModel(base: overview.base))
    }

    private var t: Strings { overview.overview?.t ?? .device }
    private var locale: String { overview.overview?.localeTag ?? "fr-FR" }
    private var currency: String { overview.overview?.currency ?? "EUR" }

    var body: some View {
        TabScaffold(tint: TabRoute.plan.tint, refresh: { await model.load() }) {
            TopBar(onProfile: onOpenSettings) {
                monthStepper
            } trailing: {
                CircleButton(symbol: "arrow.left.arrow.right", size: 44) {
                    route(.activity, TabRoute.activity.rootPath)
                }
            }
            .padding(.bottom, 24)

            if let plan = model.plan {
                /*
                 * The month turns like a page — one movement, not two.
                 *
                 * A keyed view with a move transition looked right on paper and
                 * jolted twice on the phone: the finger's offset was released
                 * back to zero in the same update that started the transition,
                 * so the page snapped home before setting off again. The two
                 * animations were describing the same motion and neither knew
                 * about the other.
                 *
                 * One offset owns it instead. The drag carries it, the release
                 * carries it the rest of the way out, the month changes while
                 * the page is off-screen, and it comes back from the far side.
                 * Nothing else moves, so there is nothing left to disagree.
                 */
                VStack(alignment: .leading, spacing: 30) {
                    hero(plan)
                        .contentShape(Rectangle())
                    summary(plan)
                    emptyPlanOffer(plan)
                    ForEach(plan.groups) { group in
                        groupSection(group)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { pageWidth = proxy.size.width }
                            .onChange(of: proxy.size.width) { _, width in
                                pageWidth = width
                            }
                    }
                }
                .offset(x: dragX)
                // A page on its way out is not a page you can read.
                .opacity(pageWidth > 0 ? 1 - min(0.55, abs(dragX) / pageWidth) : 1)
            } else if let failure = model.failure {
                VStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark").font(.system(size: 28))
                    Text(failure).font(.system(size: 14)).multilineTextAlignment(.center)
                }
                .foregroundStyle(Florin.text2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 60)
            }
        }
        /*
         * The whole page turns, not just its headline.
         *
         * Simultaneously, which is the difference: an exclusive drag on a
         * container beats the recogniser every Button already uses, and the
         * rows stopped opening the last time this was tried. Sharing the
         * gesture costs the rows nothing, and the list keeps its own vertical
         * scrolling because the swipe only fires on a drag that is plainly
         * sideways.
         */
        .simultaneousGesture(monthSwipe)
        .sheet(isPresented: $pickingSource) {
            PlanCopySheet(
                sources: model.planSources,
                hasAmounts: (model.plan?.totalAssigned ?? 0) > 0,
                t: t,
                locale: locale,
                currency: currency
            ) { source in
                await model.copyPlan(from: source)
            }
        }
        .task { if model.plan == nil { await model.load() } }

        .sheet(item: $sheet) { destination in
            switch destination {
            case let .assign(category):
                AssignSheet(
                    category: category,
                    locale: locale,
                    currency: currency,
                    t: t,
                    readyToAssign: model.plan?.readyToAssign ?? 0,
                    month: model.month,
                    base: overview.base
                ) { amount in
                    await model.assign(amount, to: category.id)
                }
            case let .remove(category, count):
                CategoryRemovalSheet(
                    category: category,
                    count: count,
                    candidates: (model.plan?.groups.flatMap(\.categories) ?? [])
                        .filter { $0.id != category.id },
                    t: t
                ) { how in
                    await model.removeCategory(
                        category.id, named: category.name, how: how, t: t
                    )
                }

            case let .remove(category, count):
                CategoryRemovalSheet(
                    category: category,
                    count: count,
                    candidates: (model.plan?.groups.flatMap(\.categories) ?? [])
                        .filter { $0.id != category.id },
                    t: t
                ) { how in
                    await model.removeCategory(
                        category.id, named: category.name, how: how, t: t
                    )
                }

            case let .shape(draft):
                CategoryEditorSheet(draft: draft, t: t) { name, emoji, isFixed in
                    if let existing = draft.category {
                        await model.editCategory(
                            existing.id, name: name, emoji: emoji, isFixed: isFixed
                        )
                    } else {
                        await model.addCategory(
                            to: draft.groupId, name: name, emoji: emoji, isFixed: isFixed
                        )
                    }
                }
            }
        }
        .florinToast($model.toast)
    }

    /// Horizontal only, and past a real distance, so it cannot be mistaken for
    /// the vertical scroll it sits on top of.
    private var monthSwipe: some Gesture {
        /*
         * Horizontal, and only horizontal.
         *
         * An earlier version put this on the whole screen with `.gesture` and
         * the rows stopped opening: an exclusive drag recogniser on a container
         * wins against the one every Button already uses. Attached
         * simultaneously it competes with nothing — and the two conditions keep
         * it out of the way of the list's own scrolling, which is the other
         * gesture it shares the screen with. A drag has to be half again as
         * wide as it is tall, and wider than sixty points, before it counts as
         * turning a page.
         */
        DragGesture(minimumDistance: 24)
            .onChanged { drag in
                let dx = drag.translation.width
                guard !turning, abs(dx) > abs(drag.translation.height) * 1.5 else { return }
                // Damped past the point where the page would turn: the drag
                // keeps answering the finger without the content ever leaving
                // the screen while it is still being held.
                let give: CGFloat = 60
                dragX = abs(dx) > give
                    ? (dx < 0 ? -1 : 1) * (give + (abs(dx) - give) / 3)
                    : dx
            }
            .onEnded { drag in
                guard !turning else { return }
                let dx = drag.translation.width
                guard abs(dx) > abs(drag.translation.height) * 1.5, abs(dx) > 60 else {
                    withAnimation(.snappy(duration: 0.2)) { dragX = 0 }
                    return
                }
                UISelectionFeedbackGenerator().selectionChanged()
                turn(dx < 0 ? 1 : -1)
            }
    }

    /*
     * Out the way it was pushed, then in from the far side.
     *
     * The month changes in the completion, while the page is off-screen, so
     * the new figures are never seen arriving — and the return leg starts from
     * a parked offset rather than from a transition, which is what keeps the
     * whole thing one movement.
     */
    private func turn(_ delta: Int) {
        let direction: CGFloat = delta > 0 ? -1 : 1
        turning = true
        withAnimation(.easeOut(duration: 0.16), completionCriteria: .logicallyComplete) {
            dragX = direction * pageWidth
        } completion: {
            Task {
                /*
                 * The month is read while the page is off screen.
                 *
                 * On the device that is a query against a file and takes no
                 * time at all, so the page can come back already made. Against
                 * a server it is a round trip, and holding an empty screen for
                 * the length of one would be worse than the thing this fixes —
                 * so there the load runs behind the movement, as before.
                 */
                if model.isLocal {
                    await model.stepAndLoad(delta)
                } else {
                    model.step(delta)
                }
                dragX = -direction * pageWidth
                withAnimation(.easeOut(duration: 0.22)) { dragX = 0 }
                turning = false
            }
        }
    }

    /// Month navigation lives in the middle of the top row, where the title
    /// would otherwise be — on this screen the month *is* the title.
    /*
     * A month with nothing in it, and the one thing worth doing about it.
     *
     * An empty plan is a screen of zeros with twenty amounts to type, and the
     * amounts are almost the ones from last month. Offered where the emptiness
     * is visible — directly under the two tiles that are reading zero — rather
     * than behind a corner button nobody presses on a screen they have just
     * opened for the first time this month.
     */
    @ViewBuilder
    private func emptyPlanOffer(_ plan: MonthPlan) -> some View {
        if plan.totalAssigned == 0, !model.planSources.isEmpty {
            Button { pickingSource = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Florin.accent)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("v2.plan.emptyTitle", "Ce mois est vide"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Florin.text)
                        Text(t(
                            "v2.plan.emptyHint",
                            "Reprenez les montants d'un mois déjà réparti."
                        ))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Florin.text2)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Florin.text3)
                }
                .padding(14)
                .florinSurface()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Florin.gutter)
        }
    }

    /// "août 2026", in the reader's own language.
    private static func monthName(_ year: Int, _ month: Int) -> String {
        var components = DateComponents()
        components.year = year
        components.month = month
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components) else { return "\(month)/\(year)" }
        let f = DateFormatter()
        f.locale = Locale(identifier: Strings.device.localeTag)
        f.setLocalizedDateFormatFromTemplate("MMMMy")
        return f.string(from: date)
    }

    private var monthStepper: some View {
        HStack(spacing: 4) {
            Button { turn(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 44)
            }
            /*
             * One line, whatever the month is called.
             *
             * "Septembre 2026" is the longest label French produces, and with a
             * second button now in the corner the capsule lost the width to
             * hold it — so it wrapped, and a two-line month inside a
             * fixed-height capsule sits off-centre as well as broken. It
             * shrinks instead, which no month needs by more than a hair.
             */
            Text(MonthLabel.long(model.month, locale: locale))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Florin.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())
            Button { turn(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 44)
            }
        }
        .foregroundStyle(Florin.text2)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .florinGlass(in: Capsule())
        .contentShape(Capsule())
        // The control that shows the month should also be the one you can
        // throw sideways.
        .simultaneousGesture(monthSwipe)
        /*
         * The rarer thing, on the thing it acts on.
         *
         * Copying a plan happens once a month at most, and a button for it in
         * the corner sat beside one used every day, competing for a place it
         * did not need. Held, the month offers what can be done to a month.
         */
        .contextMenu {
            if !model.planSources.isEmpty {
                Button {
                    pickingSource = true
                } label: {
                    Label(
                        t("v2.plan.copyPlan", "Reprendre le plan d'un autre mois"),
                        systemImage: "doc.on.doc"
                    )
                }
            }
        }
    }

    private func hero(_ plan: MonthPlan) -> some View {
        let over = plan.readyToAssign < 0
        return HeroBlock(
            caption: over
                ? t("v2.plan.assignedTooMuch", "Trop réparti")
                : t("v2.plan.readyToAssign", "À répartir"),
            value: abs(plan.readyToAssign),
            locale: locale,
            currency: currency,
            size: 50
        ) {
            Text(
                plan.isEstimated
                    ? t(
                        "v2.plan.ofExpectedIncome",
                        "sur environ {income} attendus",
                        ["income": Money.string(plan.plannedAgainst, locale: locale,
                                                currency: currency, decimals: false)]
                    )
                    : t(
                        "v2.plan.ofIncome",
                        "sur {income} de revenus",
                        ["income": Money.string(plan.income, locale: locale,
                                                currency: currency, decimals: false)]
                    )
            )
            .font(.system(size: 13))
            .foregroundStyle(over ? Florin.negative : Florin.text2)
            .hiddenWhenPrivate()
        }
    }

    private func summary(_ plan: MonthPlan) -> some View {
        HStack(spacing: 12) {
            statCard(
                t("v2.plan.assigned", "Réparti"),
                plan.totalAssigned,
                tone: .neutral
            )
            statCard(
                t("v2.plan.overspentLabel", "En dépassement"),
                Double(plan.overspentCount),
                tone: plan.overspentCount > 0 ? .negative : .muted,
                isCount: true
            )
        }
        .padding(.horizontal, Florin.gutter)
    }

    private func statCard(
        _ title: String,
        _ value: Double,
        tone: AmountText.Tone,
        isCount: Bool = false
    ) -> some View {
        FlorinCard {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: title)
                if isCount {
                    Text("\(Int(value))")
                        .font(.system(size: 26, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(
                            tone == .negative ? Florin.negative : Florin.text3
                        )
                } else {
                    AmountText(
                        value: value, locale: locale, currency: currency,
                        decimals: false, tone: tone, size: 26, weight: .light
                    )
                }
            }
        }
    }

    private func groupSection(_ group: PlanGroup) -> some View {
        let open = !collapsed.contains(group.id)

        return VStack(alignment: .leading, spacing: 10) {
            Group {
                HStack(spacing: 8) {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Florin.text3)
                    Eyebrow(text: group.name)
                    if group.overspentCount > 0 {
                        Text("\(group.overspentCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Florin.negative, in: Capsule())
                    }
                    Spacer()
                    AmountText(
                        value: group.available, locale: locale, currency: currency,
                        decimals: false, tone: group.available < 0 ? .negative : .muted,
                        size: 11.5, weight: .semibold
                    )
                    /*
                     * Adding an envelope belongs next to the group it joins.
                     *
                     * A single "+" in the top bar would make the user name the
                     * group afterwards, from a list — one more decision, taken
                     * away from the place where the answer is already on
                     * screen. Its own tap gesture sits inside the header's, and
                     * wins inside its own frame, so the row still collapses
                     * everywhere else along it.
                     */
                    if model.canEditCategories, open {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Florin.accent)
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                sheet = .shape(
                            CategoryDraft(groupId: group.id, groupName: group.name)
                        )
                            }
                            .padding(.leading, 2)
                    }
                }
                .padding(.horizontal, Florin.gutter)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.snappy(duration: 0.22)) {
                    if open { collapsed.insert(group.id) } else { collapsed.remove(group.id) }
                }
            }

            if open {
                RowGroup {
                    ForEach(Array(group.categories.enumerated()), id: \.element.id) { index, category in
                        if index > 0 { Hairline() }
                        /*
                         * A tap gesture, not a Button.
                         *
                         * Wrapped in a Button these rows simply never fired —
                         * not the sheet, not even the group's collapse toggle
                         * next to them — while the same TabScaffold's rows on
                         * Activité worked and this screen's own header buttons
                         * worked. Whatever the ButtonStyle was doing inside
                         * this particular stack, an explicit content shape with
                         * a tap on it is unambiguous and does fire.
                         */
                        PlanRow(
                            category: category,
                            locale: locale,
                            currency: currency,
                            t: t
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            UISelectionFeedbackGenerator().selectionChanged()
                            sheet = .assign(category)
                        }
                        .contextMenu {
                            if model.canEditCategories {
                                Button {
                                    sheet = .shape(
                                        CategoryDraft(
                                            groupId: group.id, groupName: group.name,
                                            category: category
                                        )
                                    )
                                } label: {
                                    Label(t("v2.common.edit", "Modifier"), systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    /*
                                     * An unused envelope is just deleted. One
                                     * with history asks what becomes of it —
                                     * only the person who filed those rows can
                                     * answer, and the screen used to decide
                                     * for them without saying so.
                                     */
                                    let used = model.categoryUsage(category.id)
                                    if used == 0 {
                                        Task {
                                            await model.removeCategory(
                                                category.id, named: category.name,
                                                how: .detach, t: t
                                            )
                                        }
                                    } else {
                                        sheet = .remove(category, used)
                                    }
                                } label: {
                                    Label(
                                        t("v2.common.delete", "Supprimer"), systemImage: "trash"
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Florin.gutter)
            }
        }
    }
}

/// One envelope: what you gave it, what left, what is left.
///
/// The bar is the point. A row of three numbers is a spreadsheet; a bar that
/// fills up and turns red when it overflows is a budget you can read at a
/// glance, which is the only way anyone actually checks one.
struct PlanRow: View {
    let category: PlanCategory
    let locale: String
    let currency: String
    let t: Strings

    private var ratio: Double {
        guard category.assigned > 0 else { return category.spent > 0 ? 1 : 0 }
        return min(1, category.spent / category.assigned)
    }

    private var over: Bool { category.available < -0.005 }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(category.emoji ?? "•").font(.system(size: 15)).frame(width: 22)
                Text(category.name)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Florin.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    AmountText(
                        value: category.available, locale: locale, currency: currency,
                        decimals: false, tone: over ? .negative : (category.available > 0 ? .neutral : .muted),
                        size: 14.5
                    )
                    if over {
                        Text(t("v2.plan.overspentChip", "Dépassé"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Florin.negative)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Florin.negative.opacity(0.16), in: Capsule())
                    } else {
                        Text(t("v2.plan.available", "restant"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(Florin.text3)
                    }
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Florin.text.opacity(0.07))
                    Capsule()
                        .fill(over ? Florin.negative : Florin.accent)
                        .frame(width: max(category.assigned > 0 || category.spent > 0 ? 3 : 0,
                                          geo.size.width * ratio))
                }
            }
            .frame(height: 5)

            HStack {
                Text(
                    t("v2.plan.assignedShort", "Réparti")
                        + " " + Money.string(category.assigned, locale: locale,
                                             currency: currency, decimals: false)
                )
                Spacer()
                Text(
                    t("v2.plan.spentShort", "Dépensé")
                        + " " + Money.string(category.spent, locale: locale,
                                             currency: currency, decimals: false)
                )
            }
            .font(.system(size: 11))
            .foregroundStyle(Florin.text3)
            .hiddenWhenPrivate()
        }
        .padding(.horizontal, Florin.gutter)
        .padding(.vertical, 12)
        // No wash. A tint on the row sits inside the card's clip as a second
        // rounded shape with its own apparent radius, and the two never agree —
        // the same thing that made the review rows read as pills in a table.
        // Overspending is already carried by the red figure and the red bar; a
        // chip beside the amount names it without inventing a shape.
    }
}

/// Assign an amount to one envelope.
///
/// Two shortcuts because they cover most real edits: match what has already
/// been spent (so the envelope stops being red), and take whatever is left to
/// assign. Typing is still there for the rest.
struct AssignSheet: View {
    let category: PlanCategory
    let locale: String
    let currency: String
    let t: Strings
    let readyToAssign: Double
    /// The month on screen, `yyyy-MM`, and where to read its rows from.
    let month: String
    let base: URL
    let onSave: (Double) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var saving = false
    @State private var rows: [Transaction] = []
    @State private var loadingRows = true
    @FocusState private var focused: Bool

    init(
        category: PlanCategory,
        locale: String,
        currency: String,
        t: Strings,
        readyToAssign: Double,
        month: String,
        base: URL,
        onSave: @escaping (Double) async -> Void
    ) {
        self.category = category
        self.locale = locale
        self.currency = currency
        self.t = t
        self.readyToAssign = readyToAssign
        self.month = month
        self.base = base
        self.onSave = onSave
        _text = State(initialValue: category.assigned > 0 ? Self.plain(category.assigned) : "")
    }

    var body: some View {
        NavigationStack {
            /*
             * One scroll for the whole sheet.
             *
             * The spending list used to scroll inside its own ScrollView, which
             * meant two scroll areas stacked in a 430pt sheet: you dragged the
             * rows and the sheet stayed put, or dragged the sheet and the rows
             * stayed put, and neither gesture did the obvious thing. Now the
             * sheet itself scrolls and grows — drag it up and the transactions
             * come with it.
             */
            ScrollView {
                VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text(category.emoji ?? "•").font(.system(size: 32))
                    Text(category.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Florin.text)
                    Text(
                        t("v2.plan.spentShort", "Dépensé") + " "
                            + Money.string(category.spent, locale: locale,
                                           currency: currency, decimals: false)
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(Florin.text2)
                    .hiddenWhenPrivate()
                }
                .padding(.top, 6)

                /*
                 * The figure sits in the middle of the sheet.
                 *
                 * A right-aligned field with the symbol beside it drifted off
                 * centre as soon as the number got shorter, so the one thing
                 * the screen is about moved every time you typed. Measuring the
                 * text and sizing the field to it keeps the number *and* the
                 * symbol centred as a unit at every length.
                 */
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TextField("0", text: $text)
                        .font(.system(size: 46, weight: .light))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .keyboardType(.decimalPad)
                        .focused($focused)
                        .fixedSize()
                    Text(Money.currencySymbol(locale: locale, currency: currency))
                        .font(.system(size: 22))
                        .foregroundStyle(Florin.text3)
                }
                .frame(maxWidth: .infinity)

                // What this choice does to the envelope, live.
                Text(outcome)
                    .font(.system(size: 13))
                    .foregroundStyle(outcomeTone)
                    .hiddenWhenPrivate()
                    .frame(height: 18)
                    .contentTransition(.numericText())

                HStack(spacing: 10) {
                    if category.spent > 0 {
                        shortcut(t("v2.plan.matchSpent", "Couvrir le dépensé"), category.spent)
                    }
                    if readyToAssign > 0 {
                        shortcut(
                            t("v2.plan.assignRest", "Tout le reste"),
                            category.assigned + readyToAssign
                        )
                    }
                    if category.assigned > 0 {
                        shortcut(t("v2.plan.clear", "Remettre à zéro"), 0)
                    }
                }
                .padding(.horizontal, Florin.gutter)

                    spending
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Backdrop(tint: TabRoute.plan.tint))
            .navigationTitle(t("v2.plan.assign", "Répartir"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.cancel", "Annuler")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("v2.common.save", "Enregistrer"), action: save)
                        .disabled(saving || parsed == nil)
                }
            }
            .onAppear { focused = true }
        }
        // Sized to the content rather than half the screen: a medium detent
        // left a void between the shortcuts and the keypad.
        .presentationDetents([.height(430), .large])
        .presentationDragIndicator(.visible)
    }

    /*
     * What the envelope actually paid for, this month.
     *
     * Deciding what to assign to "Courses" without seeing the eleven rows that
     * emptied it is guesswork — the figure above says how much went, and this
     * says where. Scrolls on its own so the amount field and the shortcuts stay
     * put while you read.
     */
    @ViewBuilder
    private var spending: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(text: t("v2.plan.thisMonth", "Ce mois-ci"))
                Spacer()
                if !rows.isEmpty {
                    Text(t("v2.activity.count", "{count} opérations", ["count": rows.count]))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Florin.text3)
                }
            }
            .padding(.horizontal, Florin.gutter)

            if loadingRows {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if rows.isEmpty {
                Text(t("v2.plan.noSpending", "Rien de dépensé sur cette catégorie ce mois-ci"))
                    .font(.system(size: 13))
                    .foregroundStyle(Florin.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Florin.gutter)
                    .padding(.bottom, 12)
            } else {
                RowGroup {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, tx in
                        if index > 0 { Hairline() }
                        TransactionRowView(tx: tx, locale: locale, currency: currency, t: t)
                    }
                }
                .padding(.horizontal, Florin.gutter)
            }
        }
        .task(id: category.id) { await loadRows() }
    }

    /*
     * Through the seam, not around it.
     *
     * This built an HTTP URL and called URLSession directly. On the device the
     * base is `florin-local://device`, which URLSession cannot open at all —
     * and the failure was swallowed by a `guard … else { return }`, so the
     * sheet said "Rien de dépensé sur cette catégorie ce mois-ci" directly
     * under a heading reading "Dépensé 70 €". Two numbers from the same screen
     * contradicting each other, with nothing to suggest the list had simply
     * failed to load.
     *
     * `FlorinClient.transactions` already answers both sources. The only
     * reason this call was written by hand is that it was written before the
     * seam existed.
     */
    private func loadRows() async {
        loadingRows = true
        defer { loadingRows = false }

        var filter = TxFilter()
        filter.categoryId = category.id
        filter.from = Self.day("\(month)-01")
        filter.to = Self.day(Self.lastDay(of: month))

        guard let page = try? await FlorinClient(base: base)
            .transactions(filter: filter, offset: 0, limit: 100)
        else { return }
        rows = page.transactions
    }

    private static func day(_ iso: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.date(from: iso)
    }

    /// The route's `to` is inclusive of that day, so the window has to end on
    /// the month's real last day rather than on the 30th of every month.
    private static func lastDay(of month: String) -> String {
        let parts = month.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return "\(month)-28" }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        let calendar = Calendar(identifier: .gregorian)
        guard let start = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: start)
        else { return "\(month)-28" }
        return String(format: "%@-%02d", month, range.count)
    }

    private func shortcut(_ label: String, _ amount: Double) -> some View {
        Button {
            text = Self.plain(amount)
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: 2) {
                Text(label).font(.system(size: 12.5, weight: .medium))
                Text(Money.string(amount, locale: locale, currency: currency, decimals: false))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .hiddenWhenPrivate()
            }
            .foregroundStyle(Florin.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .florinGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// The envelope's balance if this amount were saved.
    private var outcome: String {
        guard let value = parsed else { return "" }
        let available = value - category.spent
        if available < -0.005 {
            return t(
                "v2.plan.willOverspend", "Il manquera {amount}",
                ["amount": Money.string(-available, locale: locale, currency: currency, decimals: false)]
            )
        }
        return t(
            "v2.plan.willRemain", "Il restera {amount}",
            ["amount": Money.string(available, locale: locale, currency: currency, decimals: false)]
        )
    }

    private var outcomeTone: Color {
        guard let value = parsed else { return Florin.text3 }
        return value - category.spent < -0.005 ? Florin.negative : Florin.text2
    }

    private var parsed: Double? {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return 0 }
        return Double(
            text.replacingOccurrences(of: ",", with: ".")
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "\u{202F}", with: "")
        )
    }

    private func save() {
        guard let value = parsed else { return }
        saving = true
        Task {
            await onSave(max(0, value))
            saving = false
            dismiss()
        }
    }

    /// The server takes a plain number; the field shows one too, so what you
    /// typed is what gets sent.
    private static func plain(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value.rounded()))
            : String(format: "%.2f", value)
    }
}
