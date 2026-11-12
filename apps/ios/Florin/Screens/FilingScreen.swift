import SwiftUI

/*
 * Classer un grand livre entier, un marchand à la fois.
 *
 * Trois mille opérations tiennent en trois cent cinquante marchands, dont
 * les trente premiers portent les deux tiers des lignes. « La boulangerie du
 * coin, c'est un repas » est une décision qu'on prenait trois cents fois ;
 * ici on la prend une fois.
 *
 * Triée par nombre d'opérations : on vient pour arrêter de reclasser la même
 * chose, et c'est la répétition qui fatigue, pas la somme. Le travail utile
 * est donc en haut, et l'écran se referme avant la longue traîne — ce qui est
 * le résultat voulu, pas un abandon.
 */
struct FilingScreen: View {
    let locale: String
    let currency: String
    let t: Strings

    @Environment(\.dismiss) private var dismiss
    @State private var tallies: [LocalFiling.Tally] = []
    @State private var categories: [Category] = []
    @State private var picking: LocalFiling.Tally?
    @State private var query = ""
    @State private var onlyUnfiled = true
    @State private var toast: ToastMessage?
    @State private var failure: String?

    private var shown: [LocalFiling.Tally] {
        let needle = TxSearch.fold(query)
        return tallies.filter { tally in
            if onlyUnfiled, tally.unfiled == 0, !tally.mixed { return false }
            guard !needle.isEmpty else { return true }
            return TxSearch.fold(tally.name).contains(needle)
                || TxSearch.fold(tally.key).contains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if shown.isEmpty {
                        Text(onlyUnfiled
                             ? t("v2.filing.allDone", "Tout est classé.")
                             : t("v2.filing.none", "Aucun marchand."))
                            .font(.system(size: 14))
                            .foregroundStyle(Florin.text2)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        RowGroup {
                            ForEach(Array(shown.enumerated()), id: \.element.key) { index, tally in
                                if index > 0 { Hairline() }
                                Button { picking = tally } label: { row(tally) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Florin.gutter)
                    }
                }
                .padding(.vertical, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .searchable(text: $query, prompt: t("v2.filing.search", "Chercher un marchand"))
            .navigationTitle(t("v2.filing.title", "Classer par marchand"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.close", "Fermer")) { dismiss() }
                }
            }
        }
        .presentationBackground { Backdrop(tint: TabRoute.settings.tint, floor: true) }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .florinToast($toast)
        .task { load() }
        .sheet(item: $picking) { tally in
            CategoryPicker(
                categories: categories,
                selected: tally.categoryName,
                t: t
            ) { chosen in
                guard let chosen else { return }
                file(tally, into: chosen)
            }
        }
        .alert(
            t("v2.filing.title", "Classer par marchand"),
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    // MARK: - Ce que l'écran annonce

    /*
     * Combien de lignes restent à décider, pas combien de marchands.
     *
     * Dire « cent douze marchands » devant une liste où les trente premiers
     * règlent les deux tiers du travail décourage pour rien : ce qui avance,
     * c'est le nombre d'opérations que chaque tape emporte avec elle.
     */
    private var header: some View {
        let pending = tallies.filter { $0.unfiled > 0 || $0.mixed }
        let lines = pending.reduce(0) { $0 + max($1.unfiled, $1.mixed ? $1.count : 0) }
        return VStack(alignment: .leading, spacing: 10) {
            Text(t(
                "v2.filing.lead",
                "{lines} opérations attendent une décision, portées par {merchants} marchands. Les plus gros d'abord.",
                ["lines": lines, "merchants": pending.count]
            ))
            .font(.system(size: 13.5))
            .foregroundStyle(Florin.text2)
            .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $onlyUnfiled.animation(.snappy(duration: 0.2))) {
                Text(t("v2.filing.onlyUnfiled", "Seulement ce qui reste"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Florin.text)
            }
            .tint(Florin.accent)
        }
        .padding(.horizontal, Florin.gutter)
    }

    private func row(_ tally: LocalFiling.Tally) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tally.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Florin.text)
                    .lineLimit(1)
                Text(detail(tally))
                    .font(.system(size: 11.5))
                    .foregroundStyle(tally.mixed ? Florin.negative : Florin.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                PrivateText(Money.string(
                    tally.total, locale: locale, currency: currency, decimals: false
                ))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Florin.text)
                Text(t("v2.activity.count", "{count} opérations", ["count": tally.count]))
                    .font(.system(size: 11))
                    .foregroundStyle(Florin.text3)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Florin.text3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func detail(_ tally: LocalFiling.Tally) -> String {
        if tally.mixed {
            return t("v2.filing.mixed", "Réparti sur plusieurs catégories")
        }
        if let name = tally.categoryName {
            return tally.unfiled > 0
                ? name + " · " + t("v2.filing.remaining", "{count} sans catégorie",
                                   ["count": tally.unfiled])
                : name
        }
        return t("v2.common.uncategorized", "Sans catégorie")
    }

    // MARK: - Lire, ranger

    private func load() {
        guard let store = LocalStore.shared else { return }
        tallies = (try? LocalFiling.tallies(store: store)) ?? []
        categories = (try? LocalQueries.readCategories(store.database)) ?? []
    }

    private func file(_ tally: LocalFiling.Tally, into categoryId: String) {
        guard let store = LocalStore.shared else { return }
        do {
            let moved = try LocalFiling.file(store: store, key: tally.key, categoryId: categoryId)
            load()
            toast = ToastMessage(
                text: t("v2.filing.filed", "{count} opérations classées", ["count": moved]),
                kind: .success
            )
        } catch {
            failure = error.localizedDescription
        }
    }
}
