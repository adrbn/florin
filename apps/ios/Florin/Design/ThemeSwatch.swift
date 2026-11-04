import SwiftUI

/*
 * Le thème, en miniature.
 *
 * Deux écrans le proposent — les réglages, et la deuxième page de l'accueil —
 * et il n'y a qu'une façon de le montrer : la page du thème en petit, son
 * fond, son encre, son gris, sa couleur d'accent. Un rond de couleur ne
 * suffirait pas, parce que ce qui change d'un thème à l'autre est surtout le
 * FOND, et deux thèmes clairs ne se distinguent que par le reste.
 */
struct ThemeSwatch: View {
    let choice: FlorinPalette
    let chosen: Bool
    var height: CGFloat = 44
    let pick: () -> Void

    var body: some View {
        let palette = choice.palette
        return Button {
            guard !chosen else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            pick()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    palette.bg.color
                    if choice == .editorial { editorialFace(palette) } else { cardFace(palette) }
                }
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            chosen ? Florin.accent : Florin.text.opacity(0.12),
                            lineWidth: chosen ? 2 : 0.5
                        )
                )
                Text(choice.name)
                    .font(.system(size: 11, weight: chosen ? .semibold : .regular))
                    .foregroundStyle(chosen ? Florin.text : Florin.text3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
    }

    /*
     * Deux aperçus, parce que deux choses changent.
     *
     * Les cinq pastilles dessinaient le même croquis dans cinq fonds : le
     * choix se lisait comme « cinq couleurs », alors qu'Éditorial n'est pas
     * une couleur de plus — c'est l'autre mise en page. Un aperçu qui ne
     * montre pas ça ne sert qu'à départager des gris.
     *
     * Le croquis classique montre ce qu'on verra : une carte, une tuile de
     * couleur, deux lignes de texte. L'éditorial montre ce qu'on ne verra
     * plus : pas de carte, pas de tuile — un chiffre, un filet, du texte.
     */
    private func cardFace(_ palette: Palette) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(palette.accent.color.opacity(0.22))
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 3) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(palette.text.color).frame(width: 22, height: 3)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(palette.text3.color).frame(width: 13, height: 3)
            }
        }
        .padding(7)
        .background(palette.surface.color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func editorialFace(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(palette.text.color).frame(width: 27, height: 6)
            Rectangle().fill(palette.text3.color.opacity(0.5)).frame(width: 34, height: 0.5)
            HStack(spacing: 4) {
                Circle().fill(palette.accent.color).frame(width: 5, height: 5)
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(palette.text3.color).frame(width: 18, height: 2.5)
            }
        }
    }
}
