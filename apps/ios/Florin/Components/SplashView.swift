import SwiftUI

/// The launch animation: the app's coin, flicked and left to settle.
///
/// A little over a second, once per cold start, over the same gradient the
/// dashboard stands on — so the app never cuts from a static launch image to a
/// different-looking screen.
///
/// The coin is not drawn here. Faking a thick coin in SwiftUI means faking
/// everything a renderer does for free — the edge, its own shadow, the light
/// sliding on metal, the silhouette when it stands sideways — and every
/// approximation showed somewhere: a halo, a notch on the rim, a highlight
/// that did not follow. So the turn is rendered once on a Mac, as a real
/// cylinder of real gold under real light (`scripts/render-coin.swift`), and
/// the app only plays the pictures: nothing to compute at launch, nothing left
/// that can break.
///
/// The flick is a flick, not a motor: very fast, then settling, three turns
/// landing square on the face. Small on purpose — a launch mark is a
/// punctuation mark, and the wordmark that used to sit under it only repeated
/// what the Home Screen already said.
struct SplashView: View {
    let onFinish: () -> Void

    @State private var start = Date()
    @State private var dropped = false
    @State private var leaving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// La planche d'images : 30 vues d'un tour, six par ligne, dans l'ordre de
    /// lecture (voir `scripts/render-coin.swift`).
    private static let columns = 6
    private static let rows = 5
    private static let frames = columns * rows
    /// Le côté d'une image. La pièce n'occupe que le centre de la sienne : une
    /// vue de profil est plus haute que large, et toutes gardent la même
    /// marge, sinon la pièce changerait de taille en tournant.
    private static let cell: CGFloat = 74
    private static let turns: Double = 3
    private static let spinDuration: Double = 0.95
    private static let total: Double = 1.15

    var body: some View {
        ZStack {
            Backdrop(tint: TabRoute.overview.tint)

            /*
             * Une horloge, pas une animation.
             *
             * `withAnimation` interpole ce qu'une vue sait interpoler — une
             * rotation, une opacité. Un numéro d'image ne s'interpole pas : il
             * sauterait d'un coup à la dernière vue. C'est donc le temps qui
             * est lu à chaque rafraîchissement, et la courbe du lancer qui en
             * déduit où la pièce en est.
             */
            TimelineView(.animation) { timeline in
                let turned = progress(at: timeline.date)
                VStack(spacing: 16) {
                    coin(turned)
                    shadow(turned)
                }
                .offset(y: dropped ? 0 : -54)
                .opacity(leaving ? 0 : 1)
                .scaleEffect(leaving ? 1.35 : 1)
            }
        }
        .opacity(leaving ? 0 : 1)
        .task { await play() }
        .accessibilityHidden(true)
    }

    private func play() async {
        start = Date()
        guard !reduceMotion else {
            // No spin, but the same beat: an app that flashes past its own
            // launch screen reads as broken rather than fast.
            withAnimation(.easeOut(duration: 0.3)) { dropped = true }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeIn(duration: 0.25)) { leaving = true }
            onFinish()
            return
        }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { dropped = true }
        try? await Task.sleep(for: .seconds(Self.total - 0.25))
        // Leaves toward the viewer rather than fading in place: the app arrives
        // *through* the mark instead of after it.
        withAnimation(.easeIn(duration: 0.25)) { leaving = true }
        try? await Task.sleep(for: .milliseconds(250))
        onFinish()
    }

    /// La part du lancer déjà faite, de 0 à 1. Très vive au départ, elle
    /// s'installe — c'est la chiquenaude, et non un moteur à vitesse fixe.
    private func progress(at now: Date) -> Double {
        guard !reduceMotion else { return 1 }
        let elapsed = now.timeIntervalSince(start) / Self.spinDuration
        let u = min(max(elapsed, 0), 1)
        return 1 - pow(1 - u, 3.2)
    }

    /// L'image du tour qui correspond. Trois tours exactement : la dernière
    /// vue est la première, la pièce retombe donc pile de face.
    private func coin(_ turned: Double) -> some View {
        let step = Int((turned * Self.turns * Double(Self.frames)).rounded())
        let index = ((step % Self.frames) + Self.frames) % Self.frames
        return Color.clear
            .frame(width: Self.cell, height: Self.cell)
            .overlay(alignment: .topLeading) {
                Image("CoinSpin")
                    .resizable()
                    .interpolation(.high)
                    .frame(
                        width: Self.cell * CGFloat(Self.columns),
                        height: Self.cell * CGFloat(Self.rows)
                    )
                    .offset(
                        x: -Self.cell * CGFloat(index % Self.columns),
                        y: -Self.cell * CGFloat(index / Self.columns)
                    )
            }
            .clipped()
    }

    /// Contact shadow. It narrows as the coin turns edge-on and tightens as the
    /// coin lands, which is what reads as a drop rather than a fade-in.
    private func shadow(_ turned: Double) -> some View {
        let radians = turned * Self.turns * 2 * .pi
        let edgeness = 1 - abs(cos(radians))
        return Ellipse()
            .fill(Color.black.opacity(0.42))
            .frame(
                width: Self.cell * (0.26 + 0.34 * (1 - edgeness)),
                height: Self.cell * 0.085
            )
            .blur(radius: dropped ? 5 : 11)
            .opacity(dropped ? 1 : 0.35)
    }
}
