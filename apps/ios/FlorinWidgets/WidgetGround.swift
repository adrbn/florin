import SwiftUI

/// The Overview tab's ground, at widget scale.
///
/// The widget used to paint two hardcoded violets, top to bottom. Beside the
/// app that was close enough to look like a near-miss rather than a match, and
/// it stayed dark on a phone whose owner had chosen the light theme — the one
/// thing a home-screen tile cannot get away with, because it sits inches from
/// the app it claims to belong to.
///
/// This is `Backdrop`'s construction on a smaller canvas: the same ground, the
/// same tint, the same hotspot behind the figure so the number sits in light
/// rather than on a flat band. Two stops instead of six, because a 155-point
/// tile has no middle for a dip to land in.
struct WidgetGround: View {
    /*
     * Le poids du fond, et c'est ce qui manquait.
     *
     * `Backdrop` multiplie chacune de ses opacités par `Palette.ground` :
     * c'est par ce POIDS que Papier et Éditorial éteignent le fond coloré,
     * pas en nommant du gris. La vignette, elle, avait les opacités écrites
     * en dur — alors sous Éditorial, dont la teinte de fond EST l'encre à
     * poids 0, elle peignait du noir à 55 % sur du papier blanc et rendait
     * une tuile gris métal à côté d'une app blanche.
     */
    private var weight: Double { Palette.current.ground }

    var body: some View {
        ZStack {
            Florin.bg

            LinearGradient(
                stops: [
                    .init(color: Florin.overviewTint.opacity(0.55 * weight), location: 0.00),
                    .init(color: Florin.overviewTint.opacity(0.18 * weight), location: 0.45),
                    .init(color: Florin.overviewTint.opacity(0.10 * weight), location: 1.00),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [Florin.overviewTint.opacity(0.28 * weight), .clear],
                center: UnitPoint(x: 0.5, y: 0.05),
                startRadius: 0,
                endRadius: 190
            )
            .blendMode(.plusLighter)
        }
    }
}
