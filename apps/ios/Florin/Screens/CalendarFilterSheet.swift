import SwiftUI

/// What the calendar counts.
///
/// A month of squares is dominated by whatever is biggest, and for most people
/// that is the rent: one dark cell on the 4th, a fortnight of pale ones around
/// it, and the pattern of how the money is actually *spent* is invisible under
/// the one payment nobody makes a decision about. Taking a category out is the
/// whole point of the screen, not a refinement of it.
///
/// It is a lens, not a setting: the filter lives with the screen and is gone
/// when the app is, because a total quietly missing its rent three weeks later
/// is a bug report waiting to happen.
struct CalendarFilterSheet: View {
    let categories: [SpendCategory]
    /// What each category was worth over the window, so the list can be
    /// ordered by weight and each line can say what taking it out would do.
    let totals: [String: Double]
    let locale: String
    let currency: String
    let t: Strings
    @Binding var hidden: Set<String>

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Set<String>

    init(
        categories: [SpendCategory],
        totals: [String: Double],
        locale: String,
        currency: String,
        t: Strings,
        hidden: Binding<Set<String>>
    ) {
        self.categories = categories
        self.totals = totals
        self.locale = locale
        self.currency = currency
        self.t = t
        _hidden = hidden
        _draft = State(initialValue: hidden.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                presets
                ForEach(groups, id: \.name) { group in
                    Section {
                        ForEach(group.categories) { category in
                            row(category)
                        }
                    } header: {
                        HStack {
                            Text(group.name)
                            Spacer()
                            Button(allShown(group) ? t("v2.calendar.none", "Aucune")
                                                   : t("v2.calendar.all", "Toutes")) {
                                toggle(group)
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .textCase(nil)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle(t("v2.calendar.filterTitle", "Ce que compte le calendrier"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.cancel", "Annuler")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("v2.filters.apply", "Appliquer")) {
                        hidden = draft
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationBackground { Backdrop(tint: TabRoute.analysis.tint, floor: true) }
        .presentationDetents([.large])
    }

    // MARK: - Presets

    /// Named starting points, both of them derived from the ledger rather than
    /// from a list of category names in the code — "hors charges fixes" is
    /// whatever is marked as a fixed cost in Catégories, which is a thing the
    /// reader controls and can see.
    private var presets: some View {
        Section {
            preset(
                label: t("v2.calendar.presetAll", "Tout"),
                detail: t("v2.calendar.presetAllHint", "Chaque dépense de la période"),
                selection: []
            )
            if !fixed.isEmpty {
                preset(
                    label: t("v2.calendar.presetNoFixed", "Hors charges fixes"),
                    detail: fixed
                        .sorted { (totals[$0.id] ?? 0) > (totals[$1.id] ?? 0) }
                        .map(\.name)
                        .joined(separator: " · "),
                    selection: Set(fixed.map(\.id))
                )
            }
        } header: {
            Text(t("v2.calendar.presets", "Préréglages"))
        } footer: {
            Text(
                t(
                    "v2.calendar.presetsHint",
                    "Une charge fixe se coche sur la catégorie elle-même, dans Catégories."
                )
            )
        }
    }

    private func preset(label: String, detail: String, selection: Set<String>) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            draft = selection
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).foregroundStyle(Florin.text)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Florin.text3)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                if draft == selection {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Florin.accent)
                }
            }
        }
    }

    // MARK: - Category by category

    private func row(_ category: SpendCategory) -> some View {
        let shown = !draft.contains(category.id)
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            if shown { draft.insert(category.id) } else { draft.remove(category.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: shown ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(shown ? Florin.accent : Florin.text3)
                Text("\(category.emoji.map { $0 + " " } ?? "")\(category.name)")
                    .foregroundStyle(shown ? Florin.text : Florin.text2)
                    .lineLimit(1)
                Spacer(minLength: 8)
                // Nothing spent in the window is worth saying: it explains why
                // hiding this line would change nothing on the grid.
                Text(
                    (totals[category.id] ?? 0) > 0
                        ? Money.string(totals[category.id] ?? 0, locale: locale,
                                       currency: currency, decimals: false)
                        : "—"
                )
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(Florin.text3)
                .hiddenWhenPrivate()
            }
        }
    }

    // MARK: - Shape of the list

    private struct Group {
        let name: String
        let categories: [SpendCategory]
        let total: Double
    }

    /// Heaviest group first, heaviest category first inside it — the order in
    /// which someone looking to take something out will find it.
    private var groups: [Group] {
        var order: [String] = []
        var byName: [String: [SpendCategory]] = [:]
        for category in categories {
            if byName[category.groupName] == nil { order.append(category.groupName) }
            byName[category.groupName, default: []].append(category)
        }
        return order
            .map { name in
                let rows = (byName[name] ?? [])
                    .sorted { (totals[$0.id] ?? 0) > (totals[$1.id] ?? 0) }
                return Group(
                    name: name,
                    categories: rows,
                    total: rows.reduce(0) { $0 + (totals[$1.id] ?? 0) }
                )
            }
            .sorted { $0.total > $1.total }
    }

    private var fixed: [SpendCategory] { categories.filter(\.isFixed) }

    private func allShown(_ group: Group) -> Bool {
        group.categories.allSatisfy { !draft.contains($0.id) }
    }

    private func toggle(_ group: Group) {
        UISelectionFeedbackGenerator().selectionChanged()
        if allShown(group) {
            draft.formUnion(group.categories.map(\.id))
        } else {
            draft.subtract(group.categories.map(\.id))
        }
    }
}

/// How a filter reads in one line, wherever it has to be shown.
enum CalendarFilterLabel {
    static func short(hidden: Set<String>, categories: [SpendCategory], t: Strings) -> String {
        guard !hidden.isEmpty else { return t("v2.calendar.presetAll", "Tout") }
        let fixed = Set(categories.filter(\.isFixed).map(\.id))
        if !fixed.isEmpty, hidden == fixed {
            return t("v2.calendar.presetNoFixed", "Hors charges fixes")
        }
        if hidden.count == 1, let only = categories.first(where: { $0.id == hidden.first }) {
            return t("v2.calendar.without", "Hors {name}", ["name": only.name])
        }
        return t("v2.calendar.hiddenCount", "{count} catégories masquées", ["count": hidden.count])
    }
}
