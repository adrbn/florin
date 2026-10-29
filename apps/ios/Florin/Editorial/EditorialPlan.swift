import SwiftUI

/*
 * Plan, dans le langage Éditorial.
 *
 * Le mois en très grand, ce qu'il reste à répartir en négatif, puis les
 * enveloppes en filets plutôt qu'en cartes. Les chiffres et les gestes sont
 * ceux de `PlanScreen` — même `PlanModel`, même feuille d'affectation : seule
 * la façon de le dire change.
 *
 * C'est aussi d'ici qu'on atteint Analyse, qui n'a plus d'onglet : le total
 * dépensé du mois est un lien, souligné pour qu'on voie qu'il en est un.
 */
struct EditorialPlan: View {
    @ObservedObject var overview: OverviewModel
    var route: (TabRoute, String) -> Void = { _, _ in }
    var onOpenSettings: () -> Void = {}
    @ObservedObject var chrome: ChromeState

    @StateObject private var model: PlanModel
    /*
     * Une seule modale pour trois destinations.
     *
     * Empiler deux `.sheet` sur la même vue est documenté comme non spécifié —
     * c'est la même raison qu'en Obsidienne, et le même remède : un énoncé qui
     * dit laquelle on veut.
     */
    @State private var dest: Dest?
    @State private var pickingSource = false

    private enum Dest: Identifiable {
        case assign(PlanCategory)
        case shape(CategoryDraft)
        /// Le compte voyage avec : la question ne se pose que parce qu'il n'est
        /// pas nul, et la feuille le dit avant de demander.
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
        onOpenSettings: @escaping () -> Void = {},
        chrome: ChromeState
    ) {
        self.overview = overview
        self.route = route
        self.onOpenSettings = onOpenSettings
        self.chrome = chrome
        _model = StateObject(wrappedValue: PlanModel(base: overview.base))
    }

    private var t: Strings { overview.overview?.t ?? .device }
    private var locale: String { overview.overview?.localeTag ?? "fr-FR" }
    private var currency: String { overview.overview?.currency ?? "EUR" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                .edEnter()
                .id(edTopAnchor)
                if let plan = model.plan {
                    EdPill(text: "\(t("v2.plan.title", "Plan")) · \(plan.year)")
                        .padding(.top, 18)
                    /*
                     * Le rare, sur ce qu'il modifie.
                     *
                     * Reprendre un plan arrive une fois par mois ; un bouton
                     * de barre lui donnerait la place d'un geste quotidien.
                     * Tenu, le mois offre ce qu'on fait à un mois.
                     */
                    EdHero(text: monthName(plan.year, plan.month))
                        .padding(.top, 10)
                        .contextMenu {
                            if !model.planSources.isEmpty {
                                Button { pickingSource = true } label: {
                                    Label(
                                        t("v2.plan.copyPlan", "Reprendre le plan d'un autre mois"),
                                        systemImage: "doc.on.doc"
                                    )
                                }
                            }
                        }
                    emptyOffer(plan).edEnter()
                    readyToAssign(plan).edEnter()
                    spending(plan).edEnter()
                    envelopes(plan)
                } else if let failure = model.failure {
                    Text(failure)
                        .font(.system(size: 15))
                        .foregroundStyle(Florin.text2)
                        .padding(.top, 40)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Florin.text3)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal, Ed.gutter)
            .padding(.top, 10)
            .padding(.bottom, 120)
        }
        .edRewind(.plan, chrome: chrome)
        .scrollIndicators(.hidden)
        .edPlainEdges()
        .background(Florin.bg)
        .refreshable { await model.load() }
        .task { if model.plan == nil { await model.load() } }
        .reloadsOnLedgerChange { await model.load() }
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
            .edSheet()
        }
        .sheet(item: $dest) { destination in
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
                .edSheet()
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
                .edSheet()
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
                .edSheet()
            }
        }
        .florinToast($model.toast)
    }

    // MARK: Le bandeau

    /// Les deux chevrons tiennent lieu de titre : le mois est écrit en 64 pt
    /// juste dessous, il n'a pas à l'être une seconde fois dans la barre.
    private var header: some View {
        EdHeader {
            HStack(spacing: 0) {
                EdIconButton(
                    symbol: "chevron.left",
                    label: t("v2.plan.prevMonth", "Mois précédent")
                ) { model.step(-1) }
                EdIconButton(
                    symbol: "chevron.right",
                    label: t("v2.plan.nextMonth", "Mois suivant")
                ) { model.step(1) }
            }
        } trailing: {
            EdIconButton(
                symbol: "person.crop.circle",
                label: t("v2.settings.title", "Réglages"),
                action: onOpenSettings
            )
        }
    }

    /// « août 2026 » sans son année : elle est déjà dans la pastille.
    private func monthName(_ year: Int, _ month: Int) -> String {
        var components = DateComponents()
        components.year = year
        components.month = month
        guard let date = Calendar(identifier: .gregorian).date(from: components)
        else { return "\(month)/\(year)" }
        let f = DateFormatter()
        f.locale = Locale(identifier: locale)
        f.setLocalizedDateFormatFromTemplate("MMMM")
        let name = f.string(from: date)
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    // MARK: Le mois vide

    /*
     * Le mois vide le dit lui-même.
     *
     * Le menu tenu existe aussi, mais une action qu'on fait une fois par mois
     * ne s'apprend pas par un appui long : la première fois, elle doit être à
     * l'écran, juste sous le mois qui n'a rien.
     */
    @ViewBuilder
    private func emptyOffer(_ plan: MonthPlan) -> some View {
        if plan.totalAssigned == 0, !model.planSources.isEmpty {
            Button { pickingSource = true } label: {
                HStack(spacing: 10) {
                    EdInk(text: t("v2.plan.emptyTitle", "Ce mois est vide"), size: 15)
                    Image(systemName: "arrow.forward")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Florin.text2)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.edPress)
            .padding(.top, 10)
        }
    }

    // MARK: À répartir

    private func readyToAssign(_ plan: MonthPlan) -> some View {
        EdInverse {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    EdInk(text: t("v2.plan.readyToAssign", "À répartir"), size: 13, dim: true)
                    Spacer(minLength: 8)
                    if plan.overspentCount > 0 {
                        // L'alerte garde sa couleur jusque dans le négatif :
                        // c'est la seule chose de cette carte qui n'est pas
                        // qu'un contraste.
                        EdPill(
                            text: t(
                                "v2.plan.overspent", "{count} en dépassement",
                                ["count": plan.overspentCount]
                            ),
                            tone: Florin.negative
                        )
                    }
                }
                EdAmount(
                    text: Money.string(
                        plan.readyToAssign, locale: locale, currency: currency
                    ),
                    size: 48,
                    tone: plan.readyToAssign < 0 ? Florin.negative : Florin.bg,
                    value: plan.readyToAssign
                )
                EdInk(
                    text: Money.string(
                        plan.totalAssigned, locale: locale, currency: currency,
                        decimals: false
                    ) + " · " + t(
                        plan.isEstimated ? "v2.plan.ofExpectedIncome" : "v2.plan.ofIncome",
                        "sur {income}",
                        ["income": Money.string(
                            plan.plannedAgainst, locale: locale, currency: currency,
                            decimals: false
                        )]
                    ),
                    size: 13,
                    dim: true
                )
                .redactable(tint: Florin.bg)
            }
        }
        .padding(.top, 28)
    }

    // MARK: Les dépenses, et la porte d'Analyse

    /// Les quatre premiers postes du mois, en barres. La plus haute prend
    /// l'accent — pas parce qu'elle va mal, parce que c'est elle qu'on
    /// cherchait du regard.
    private func spending(_ plan: MonthPlan) -> some View {
        let top = plan.groups
            .flatMap(\.categories)
            .filter { $0.spent > 0 }
            .sorted { $0.spent > $1.spent }
            .prefix(4)
        let total = plan.groups.reduce(0) { $0 + $1.spent }
        let ceiling = top.first?.spent ?? 1

        return VStack(alignment: .leading, spacing: 14) {
            EdPill(text: t("v2.plan.thisMonth", "Ce mois"))
            Button {
                route(.analysis, TabRoute.analysis.rootPath)
            } label: {
                HStack(alignment: .lastTextBaseline) {
                    EdSection(text: t("v2.plan.spent", "Dépensé"))
                    Spacer(minLength: 8)
                    Text(Money.string(
                        total, locale: locale, currency: currency, decimals: false
                    ))
                    .font(.system(size: 18, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Florin.text)
                    .underline()
                    .redactable()
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(t("v2.analysis.title", "Analyse")))

            if !top.isEmpty {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(top.enumerated()), id: \.element.id) { index, category in
                        bar(category, share: ceiling > 0 ? category.spent / ceiling : 0,
                            leading: index == 0)
                    }
                }
                .frame(height: 220)
                .animation(EdMotion.enter, value: plan.key)
            }
        }
        .padding(.top, 34)
    }

    private func bar(_ category: PlanCategory, share: Double, leading: Bool) -> some View {
        VStack(spacing: 8) {
            // Un plancher de 24 pt : une barre invisible ne dit pas « peu »,
            // elle dit « rien », ce qui est faux.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(leading ? Florin.accent : Florin.surface2)
                .frame(maxWidth: .infinity)
                .frame(height: max(24, 180 * share))
            Text(category.name)
                .font(.system(size: 11))
                .foregroundStyle(Florin.text2)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
    }

    // MARK: Les enveloppes

    private func envelopes(_ plan: MonthPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(plan.groups) { group in
                EdSection(
                    text: group.name,
                    trailing: Money.string(
                        group.available, locale: locale, currency: currency, decimals: false
                    )
                )
                .padding(.top, 34)
                .padding(.bottom, 6)
                .contextMenu {
                    if model.canEditCategories {
                        Button {
                            dest = .shape(
                                CategoryDraft(groupId: group.id, groupName: group.name)
                            )
                        } label: {
                            Label(
                                t("v2.plan.newCategory", "Nouvelle enveloppe"),
                                systemImage: "plus"
                            )
                        }
                    }
                }

                ForEach(group.categories) { category in
                    EdRule()
                    Button { dest = .assign(category) } label: { row(category) }
                        .buttonStyle(.edPress)
                        .edEnter()
                        .contextMenu {
                            if model.canEditCategories {
                                Button {
                                    dest = .shape(
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
                                     * Une enveloppe jamais servie se supprime.
                                     * Celle qui a un passé demande ce qu'il
                                     * devient — seul celui qui a classé ces
                                     * lignes peut répondre.
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
                                        dest = .remove(category, used)
                                    }
                                } label: {
                                    Label(
                                        t("v2.common.delete", "Supprimer"), systemImage: "trash"
                                    )
                                }
                            }
                        }
                }
                EdRule()
            }
        }
    }

    private func row(_ category: PlanCategory) -> some View {
        let over = category.available < 0
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Florin.text)
                    .lineLimit(1)
                Text(
                    Money.string(
                        category.spent, locale: locale, currency: currency, decimals: false
                    ) + " / " + Money.string(
                        category.assigned, locale: locale, currency: currency, decimals: false
                    )
                )
                .font(.system(size: 13))
                .foregroundStyle(over ? Florin.negative : Florin.text2)
                .redactable(tint: Florin.text2)
            }
            Spacer(minLength: 8)
            EdAmountPill(
                text: Money.string(
                    category.available, locale: locale, currency: currency, decimals: false
                ),
                tone: over ? Florin.negative : Florin.text
            )
        }
        .frame(minHeight: 62)
        .contentShape(Rectangle())
    }
}
