import SwiftUI
import UIKit

/*
 * Ce qu'on a déjà, proposé pendant qu'on écrit.
 *
 * Une bande de pastilles sous le champ, qui change à chaque frappe. Le champ
 * reste un champ — on peut toujours tout taper — mais la réponse probable est
 * à une tape, avec la tête du marchand ou l'emoji de la catégorie, donc on la
 * reconnaît sans la lire.
 *
 * Même forme partout : bénéficiaire, catégorie, recherche, nom de marchand.
 * C'est la même promesse à chaque fois — « celui-là, tu le connais déjà » — et
 * une forme par endroit obligerait à réapprendre quatre fois qu'une pastille
 * se tapote.
 */
struct SuggestionPills: View {
    struct Item: Identifiable, Equatable {
        let id: String
        let label: String
        var emoji: String?
        var logo: UIImage?
        /// Déjà la réponse en place : la pastille reste, cochée. Elle
        /// disparaissait au moment précis où elle avait quelque chose à
        /// confirmer.
        var chosen = false

        static func == (a: Item, b: Item) -> Bool { a.id == b.id && a.chosen == b.chosen }
    }

    let items: [Item]
    /// L'alignement du premier bord : 16 dans une feuille de saisie, la
    /// gouttière sur une page.
    var inset: CGFloat = 16
    let onPick: (Item) -> Void

    var body: some View {
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            onPick(item)
                        } label: {
                            pill(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, inset)
            }
            // La bande bouge au rythme de la frappe : sans ressort, les
            // pastilles se téléportent d'un mot à l'autre.
            .animation(.snappy(duration: 0.22), value: items)
        }
    }

    private func pill(_ item: Item) -> some View {
        HStack(spacing: 7) {
            Bubble(label: item.label, emoji: item.emoji, size: 20, logo: item.logo)
            Text(item.label)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Florin.text)
                .lineLimit(1)
            if item.chosen {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Florin.accent)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 11)
        .padding(.vertical, 6)
        .background(Florin.accent.opacity(item.chosen ? 0.3 : 0.13), in: Capsule())
    }
}
