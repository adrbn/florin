import SwiftUI

/// Gérer ses catégories, sans passer par le plan du mois.
///
/// Elles se créaient et se supprimaient dans l'onglet Plan, où l'on vient
/// répartir un budget : un « + » minuscule au bout d'un groupe, et un appui
/// long pour supprimer. Un geste qu'il faut connaître pour le trouver, sur un
/// écran où l'on venait faire autre chose.
///
/// Ici chaque geste porte son nom. Les groupes sont là pour situer, pas pour
/// être manipulés — leur nombre est fixe et leur nature aussi, entrées ou
/// dépenses, ce qui décide où une catégorie compte.
struct CategoriesScreen: View {
    let t: Strings

    @Environment(\.dismiss) private var dismiss
    @State private var groups: [Group] = []
    @State private var draft: CategoryDraft?
    @State private var removing: Removal?
    @State private var failure: String?

    struct Group: Identifiable {
        let id: String
        let name: String
        let kind: String
        var categories: [PlanCategory]
    }

    /// Une suppression en attente, avec ce qu'elle emporterait.
    struct Removal: Identifiable {
        let category: PlanCategory
        let count: Int
        let candidates: [PlanCategory]
        var id: String { category.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    ForEach(groups) { group in
                        section(group)
                    }
                    if groups.isEmpty {
                        Text(t("v2.categories.empty", "Aucune catégorie"))
                            .font(.system(size: 14))
                            .foregroundStyle(Florin.text2)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                }
                .padding(.vertical, 18)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle(t("v2.nav.categories", "Catégories"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.close", "Fermer")) { dismiss() }
                }
            }
        }
        .presentationBackground { Backdrop(tint: TabRoute.plan.tint, floor: true) }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { load() }
        .sheet(item: $draft) { draft in
            CategoryEditorSheet(draft: draft, t: t) { name, emoji, isFixed in
                await save(draft, name: name, emoji: emoji, isFixed: isFixed)
            }
        }
        .sheet(item: $removing) { pending in
            CategoryRemovalSheet(
                category: pending.category,
                count: pending.count,
                candidates: pending.candidates,
                t: t
            ) { how in
                await remove(pending.category, how: how)
            }
        }
        .alert(
            t("v2.nav.categories", "Catégories"),
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    // MARK: - Un groupe et ses catégories

    private func section(_ group: Group) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(text: group.name)
                Spacer()
                /*
                 * Le groupe dit ce qu'il compte.
                 *
                 * Une catégorie de dépense et une catégorie d'entrée ne se
                 * comportent pas pareil — l'une pèse sur le reste à vivre,
                 * l'autre l'alimente — et rien à l'écran ne le disait. C'est la
                 * seule chose que le groupe décide, donc c'est la seule qu'il
                 * annonce.
                 */
                Text(kindLabel(group.kind))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Florin.text3)
            }
            .padding(.horizontal, Florin.gutter)

            RowGroup {
                ForEach(Array(group.categories.enumerated()), id: \.element.id) { index, category in
                    if index > 0 { Hairline() }
                    row(category, in: group)
                }
                if !group.categories.isEmpty { Hairline() }
                Button {
                    draft = CategoryDraft(groupId: group.id, groupName: group.name, category: nil)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Florin.accent)
                            .frame(width: 24)
                        Text(t("v2.categories.addTo", "Ajouter dans {group}", ["group": group.name]))
                            .font(.system(size: 15))
                            .foregroundStyle(Florin.accent)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Florin.gutter)
        }
    }

    private func row(_ category: PlanCategory, in group: Group) -> some View {
        HStack(spacing: 12) {
            Text(category.emoji ?? "•")
                .font(.system(size: 19))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(category.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Florin.text)
                    .lineLimit(1)
                if category.isFixed == true {
                    Text(t("v2.categories.fixed", "Charge fixe"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Florin.text3)
                }
            }
            Spacer(minLength: 8)
            // Deux boutons nommés plutôt qu'un appui long : le geste caché
            // était la seule façon de supprimer, et rien ne l'annonçait.
            Button {
                draft = CategoryDraft(
                    groupId: group.id, groupName: group.name, category: category
                )
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Florin.text2)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                prepareRemoval(category)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Florin.negative)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 8)
    }

    private func kindLabel(_ kind: String) -> String {
        switch kind {
        case "income": t("v2.analysis.income", "Revenus")
        case "adjustment": t("v2.balance.adjustments", "Ajustements")
        default: t("v2.analysis.expenses", "Dépenses")
        }
    }

    // MARK: - Lecture

    private func load() {
        guard let store = LocalStore.shared else { return }
        let rows = (try? store.database.query(
            """
            SELECT g.id AS group_id, g.name AS group_name, g.kind AS kind,
                   c.id, c.name, c.emoji, c.is_fixed
            FROM category_groups g
            LEFT JOIN categories c ON c.group_id = g.id AND c.is_archived = 0
            ORDER BY g.display_order, g.name, c.display_order, c.name
            """
        )) ?? []

        var order: [String] = []
        var built: [String: Group] = [:]
        for row in rows {
            guard let gid = row.string("group_id") else { continue }
            if built[gid] == nil {
                order.append(gid)
                built[gid] = Group(
                    id: gid,
                    name: row.string("group_name") ?? "—",
                    kind: row.string("kind") ?? "expense",
                    categories: []
                )
            }
            guard let id = row.string("id"), let name = row.string("name") else { continue }
            built[gid]?.categories.append(
                PlanCategory(
                    id: id, name: name, emoji: row.string("emoji"),
                    assigned: 0, spent: 0, available: 0, note: nil,
                    isFixed: (row.int("is_fixed") ?? 0) == 1
                )
            )
        }
        groups = order.compactMap { built[$0] }
    }

    // MARK: - Écritures

    private func save(
        _ draft: CategoryDraft, name: String, emoji: String, isFixed: Bool
    ) async {
        guard let store = LocalStore.shared else { return }
        do {
            if let existing = draft.category {
                try LocalCategories.update(
                    store: store, id: existing.id, name: name, emoji: emoji, isFixed: isFixed
                )
            } else {
                _ = try LocalCategories.create(
                    store: store, groupId: draft.groupId,
                    name: name, emoji: emoji, isFixed: isFixed
                )
            }
            load()
        } catch {
            failure = error.localizedDescription
        }
    }

    /*
     * Ce qu'une suppression emporte, compté avant de la proposer.
     *
     * Une catégorie vide s'en va sans question. Une catégorie qui porte trois
     * cents opérations pose un vrai choix — les laisser sans classement, les
     * déplacer, ou seulement retirer la catégorie du plan — et ce choix n'a de
     * sens qu'une fois le nombre connu.
     */
    private func prepareRemoval(_ category: PlanCategory) {
        guard let store = LocalStore.shared else { return }
        let count = (try? LocalCategories.usage(store: store, id: category.id)) ?? 0
        removing = Removal(
            category: category,
            count: count,
            candidates: groups.flatMap(\.categories).filter { $0.id != category.id }
        )
    }

    private func remove(_ category: PlanCategory, how: LocalCategories.Removal) async {
        guard let store = LocalStore.shared else { return }
        do {
            try LocalCategories.remove(store: store, id: category.id, how: how)
            load()
        } catch {
            failure = error.localizedDescription
        }
    }
}
