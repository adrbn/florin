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
    @State private var editing: PlanCategory?
    @State private var collapsed: Set<String> = []

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

    private var t: Strings { overview.overview?.t ?? .empty }
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
                hero(plan)
                summary(plan)
                ForEach(plan.groups) { group in
                    groupSection(group)
                }
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
        .task { if model.plan == nil { await model.load() } }
        .sheet(item: $editing) { category in
            AssignSheet(
                category: category,
                locale: locale,
                currency: currency,
                t: t,
                readyToAssign: model.plan?.readyToAssign ?? 0
            ) { amount in
                await model.assign(amount, to: category.id)
            }
        }
        .florinToast($model.toast)
    }

    /// Month navigation lives in the middle of the top row, where the title
    /// would otherwise be — on this screen the month *is* the title.
    private var monthStepper: some View {
        HStack(spacing: 4) {
            Button { model.step(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 44)
            }
            Text(MonthLabel.long(model.month, locale: locale))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Florin.text)
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())
            Button { model.step(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 44)
            }
        }
        .foregroundStyle(Florin.text2)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .florinGlass(in: Capsule())
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
                t(
                    "v2.plan.ofIncome",
                    "sur {income} de revenus",
                    ["income": Money.string(plan.income, locale: locale,
                                            currency: currency, decimals: false)]
                )
            )
            .font(.system(size: 13))
            .foregroundStyle(over ? Florin.negative : Florin.text2)
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
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.snappy(duration: 0.22)) {
                    if open { collapsed.insert(group.id) } else { collapsed.remove(group.id) }
                }
            } label: {
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
                }
                .padding(.horizontal, Florin.gutter)
            }
            .buttonStyle(.plain)

            if open {
                RowGroup {
                    ForEach(Array(group.categories.enumerated()), id: \.element.id) { index, category in
                        if index > 0 { Hairline() }
                        Button { editing = category } label: {
                            PlanRow(
                                category: category,
                                locale: locale,
                                currency: currency,
                                t: t
                            )
                        }
                        .buttonStyle(.plain)
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
                VStack(alignment: .trailing, spacing: 1) {
                    AmountText(
                        value: category.available, locale: locale, currency: currency,
                        decimals: false, tone: over ? .negative : (category.available > 0 ? .neutral : .muted),
                        size: 14.5
                    )
                    Text(t("v2.plan.available", "restant"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Florin.text3)
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
        }
        .padding(.horizontal, Florin.gutter)
        .padding(.vertical, 12)
        .background(over ? Florin.negative.opacity(0.05) : Color.clear)
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
    let onSave: (Double) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var saving = false
    @FocusState private var focused: Bool

    init(
        category: PlanCategory,
        locale: String,
        currency: String,
        t: Strings,
        readyToAssign: Double,
        onSave: @escaping (Double) async -> Void
    ) {
        self.category = category
        self.locale = locale
        self.currency = currency
        self.t = t
        self.readyToAssign = readyToAssign
        self.onSave = onSave
        _text = State(initialValue: category.assigned > 0 ? Self.plain(category.assigned) : "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 6) {
                        Text(category.emoji ?? "•").font(.system(size: 34))
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
                    }
                    .padding(.top, 10)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        TextField("0", text: $text)
                            .font(.system(size: 44, weight: .light))
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .focused($focused)
                            .frame(maxWidth: 200)
                        Text(Money.currencySymbol(locale: locale, currency: currency))
                            .font(.system(size: 22))
                            .foregroundStyle(Florin.text3)
                    }

                    HStack(spacing: 10) {
                        if category.spent > 0 {
                            shortcut(
                                t("v2.plan.matchSpent", "Couvrir le dépensé"),
                                category.spent
                            )
                        }
                        if readyToAssign > 0 {
                            shortcut(
                                t("v2.plan.assignRest", "Tout le reste"),
                                category.assigned + readyToAssign
                            )
                        }
                    }
                    .padding(.horizontal, Florin.gutter)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
            }
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
        .presentationDetents([.medium])
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
            }
            .foregroundStyle(Florin.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .florinGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
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
