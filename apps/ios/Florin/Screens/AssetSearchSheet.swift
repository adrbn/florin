import SwiftUI

/*
 * Attacher un titre à une ligne de portefeuille.
 *
 * Jusqu'ici, rien dans l'app n'écrivait jamais `quote_symbol` : une ligne
 * créée sur le téléphone n'avait pas de symbole, donc `LocalPricing` ne la
 * voyait pas, donc son cours ne bougeait plus jamais. Elle affichait le prix
 * du jour de sa création, indéfiniment, avec l'aplomb d'un chiffre à jour.
 *
 * Il aurait suffi d'un champ texte — à condition de connaître le symbole
 * exact du fournisseur. « CW8.PA » ne se devine pas, et se tromper de place
 * boursière donne un cours dans la mauvaise devise sans rien signaler. La
 * recherche demande donc au fournisseur lui-même : on tape le nom du tracker,
 * il rend ses cotations, et on choisit la bonne place.
 *
 * Ce qui sort du téléphone : ce qu'on tape dans le champ. Jamais une quantité,
 * jamais un montant, jamais le nom du compte — la requête ressemble à celle de
 * n'importe qui cherchant le même tracker.
 */
struct AssetSearchSheet: View {
    let t: Strings
    /// Rend le symbole retenu et le nom affichable du titre.
    let onPick: (AssetSearch.Match) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var matches: [AssetSearch.Match] = []
    @State private var searching = false
    @State private var failed = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Florin.text3)
                    TextField(
                        t("v2.asset.searchPlaceholder", "Nom du titre ou code ISIN"),
                        text: $query
                    )
                    .font(.system(size: 16))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit { run() }
                    if searching { ProgressView().controlSize(.small) }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Florin.surface2, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, Florin.gutter)
                .padding(.top, 10)

                if failed {
                    Text(t("v2.asset.searchFailed", "Recherche impossible pour le moment."))
                        .font(.system(size: 13))
                        .foregroundStyle(Florin.text3)
                        .padding(.top, 28)
                } else if matches.isEmpty {
                    Text(t(
                        "v2.asset.searchHint",
                        "Cherche le tracker ou l'action, puis choisis sa place de cotation : c'est elle qui fixe la devise du cours."
                    ))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Florin.text3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 28)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(matches) { match in
                                Button {
                                    onPick(match)
                                    dismiss()
                                } label: { row(match) }
                                .buttonStyle(.plain)
                                if match.id != matches.last?.id { Hairline() }
                            }
                        }
                        .florinSurface()
                        .padding(.horizontal, Florin.gutter)
                        .padding(.top, 14)
                    }
                    .scrollDismissesKeyboard(.immediately)
                }
                Spacer(minLength: 0)
            }
            .background(Florin.bg)
            .navigationTitle(t("v2.asset.search", "Chercher un titre"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.cancel", "Annuler")) { dismiss() }
                }
            }
        }
        .onAppear { focused = true }
        /*
         * Une frappe n'est pas une recherche.
         *
         * Interroger à chaque caractère enverrait huit requêtes pour « amundi »
         * et afficherait les résultats de « amun » par-dessus ceux de « amundi »
         * si elles reviennent dans le désordre. Un tiers de seconde de silence
         * suffit à n'en envoyer qu'une, et la tâche précédente est annulée.
         */
        .task(id: query) {
            guard query.trimmingCharacters(in: .whitespaces).count >= 2 else {
                matches = []
                return
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private func row(_ match: AssetSearch.Match) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(match.name)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Florin.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 5) {
                    Text(match.symbol)
                        .font(.system(size: 11.5, weight: .medium))
                        .monospaced()
                        .foregroundStyle(Florin.accent)
                    if !match.exchange.isEmpty {
                        Text(match.exchange)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Florin.text3)
                    }
                    if !match.kind.isEmpty {
                        Text(match.kind)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Florin.text3)
                    }
                }
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Florin.text3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func run() { Task { await search() } }

    private func search() async {
        searching = true
        failed = false
        let found = await AssetSearch.find(query)
        searching = false
        guard let found else { failed = true; matches = []; return }
        matches = found
    }
}
