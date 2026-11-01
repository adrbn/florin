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
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(palette.text.color)
                            .frame(width: 24, height: 3)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(palette.text3.color)
                            .frame(width: 16, height: 3)
                        Circle()
                            .fill(palette.accent.color)
                            .frame(width: 9, height: 9)
                            .padding(.top, 1)
                    }
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
}
