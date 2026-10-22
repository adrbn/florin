import SwiftUI

/// The launch animation: the app's coin, flicked and left to settle.
///
/// A little over a second, once per cold start — it was two, which read as
/// waiting — over the same gradient the dashboard stands on — so the app never cuts from a static launch image to a
/// different-looking screen.
///
/// Making a flat picture read as a coin takes more than a rotation:
///  - real perspective, or it reads as a horizontal squash;
///  - an *edge*: at 90° a coin is a gold sliver, not nothing, so a lit strip is
///    revealed underneath as the face narrows;
///  - a mirrored back, because past 90° you are looking at the other side;
///  - a specular sweep that tracks the angle, which is what sells metal;
///  - a contact shadow that tightens as the coin drops toward it, which is what
///    puts the coin in a place rather than on a layer.
///
/// The rotation is a flick, not a motor: a steep ease-out over two and a half
/// turns, landing square. Small on purpose — a launch mark is a punctuation
/// mark, and the wordmark that used to sit under it only repeated what the
/// Home Screen already said.
struct SplashView: View {
    let onFinish: () -> Void

    @State private var spin: CGFloat = 0
    @State private var dropped = false
    @State private var leaving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Trois tours pleins, pas deux et demi : une pièce lâchée retombe sur
    /// une face, et un demi-tour de plus la laissait au repos sur son propre
    /// reflet — le dos d'une pièce qui n'en a pas.
    private static let turns: Double = 3
    private static let spinDuration: Double = 1.0
    private static let total: Double = 1.15
    private static let size: CGFloat = 62
    /// L'épaisseur, en points, et le nombre de disques qui la remplissent :
    /// assez pour qu'ils se touchent encore quand la tranche est face à nous.
    private static let thickness: CGFloat = 5.4
    private static let slices = 8

    private var angle: Double { Double(spin) * 360 * Self.turns }
    private var radians: Double { angle * .pi / 180 }
    /// 0 face-on, 1 edge-on.
    private var edgeness: Double { 1 - abs(cos(radians)) }
    private var showingBack: Bool { cos(radians) < 0 }

    var body: some View {
        ZStack {
            Backdrop(tint: TabRoute.overview.tint)

            /*
             * La pièce tombe, son ombre reste au sol.
             *
             * Les deux descendaient ensemble — l'ombre portée suivait la pièce
             * à seize points sous elle, ce qui est la seule chose qu'une ombre
             * de contact ne fasse jamais. Le rapprochement est le mouvement :
             * c'est lui qui dit qu'il y a un sol, et sans lui la pièce
             * glissait sur une vitre.
             */
            VStack(spacing: 16) {
                coin.offset(y: dropped ? 0 : -54)
                shadow
            }
            .opacity(leaving ? 0 : 1)
            .scaleEffect(leaving ? 1.35 : 1)
        }
        .opacity(leaving ? 0 : 1)
        .task { await play() }
        .accessibilityHidden(true)
    }

    private func play() async {
        guard !reduceMotion else {
            // No spin, but the same beat: an app that flashes past its own
            // launch screen reads as broken rather than fast.
            withAnimation(.easeOut(duration: 0.3)) { dropped = true }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeIn(duration: 0.25)) { leaving = true }
            onFinish()
            return
        }

        // Une chute part immobile et accélère, puis se pose : c'est ce que
        // fait un ressort qu'on ne lance pas, pas une courbe qui démarre à
        // pleine vitesse.
        withAnimation(.interpolatingSpring(stiffness: 210, damping: 15)) { dropped = true }
        // Le lancer, lui, part vite et s'épuise — mais pas d'un coup : la
        // courbe précédente faisait deux tours et demi dans le premier
        // dixième de seconde, puis rampait.
        withAnimation(.timingCurve(0.13, 0.68, 0.2, 1, duration: Self.spinDuration)) { spin = 1 }

        try? await Task.sleep(for: .seconds(Self.total - 0.25))
        // Leaves toward the viewer rather than fading in place: the app arrives
        // *through* the mark instead of after it.
        withAnimation(.easeIn(duration: 0.25)) { leaving = true }
        try? await Task.sleep(for: .milliseconds(250))
        onFinish()
    }

    /*
     * L'épaisseur, pour de vrai.
     *
     * Une capsule dorée dessinée derrière la face ne se voyait qu'au moment
     * où celle-ci disparaissait : entre les deux, la pièce n'avait pas de
     * tranche, elle avait un bord. Une pièce épaisse est un empilement de
     * disques, et c'est la rotation qui les écarte — vus de face ils se
     * recouvrent exactement, à mi-tour ils s'étalent et font le cylindre.
     *
     * `anchorZ` est ce qui les sépare : une couche tournée autour d'un axe
     * placé à la profondeur z se retrouve décalée de z·sin(angle), donc huit
     * couches réparties dans l'épaisseur se déploient d'elles-mêmes, sans
     * qu'aucune position ne soit écrite à la main.
     */
    private var coin: some View {
        ZStack {
            ForEach(0..<Self.slices, id: \.self) { index in
                Circle()
                    .fill(rim)
                    .frame(width: Self.size, height: Self.size)
                    // Les disques du fond sont dans l'ombre de ceux de devant.
                    .brightness(-0.1 * (1 - Double(index) / Double(Self.slices - 1)))
                    .modifier(Turned(angle: angle, depth: depth(index)))
            }

            Image("CoinFace")
                .resizable()
                .scaledToFit()
                .frame(width: Self.size, height: Self.size)
                // The back of a coin is the mirror of what you would see
                // through it; without this the face reads as printed on glass.
                .scaleEffect(x: showingBack ? -1 : 1, y: 1)
                .overlay(specular)
                .mask(Circle())
                // Posée sur celle des deux tranches qui nous fait face.
                .modifier(Turned(
                    angle: angle,
                    depth: showingBack ? -Self.thickness / 2 : Self.thickness / 2
                ))
        }
        /*
         * Une seule lueur, pas neuf.
         *
         * `shadow` posé sur un conteneur se propage à chaque enfant, qui la
         * dessine pour son propre compte : les huit disques de la tranche et
         * la face en faisaient neuf, empilées au même endroit, et la pièce
         * est arrivée dans une boule de lumière. `compositingGroup` aplatit
         * la pièce avant le filtre, qui n'a plus qu'une forme à éclairer.
         */
        .compositingGroup()
        .shadow(color: Color(red: 1, green: 0.82, blue: 0.42).opacity(0.28 * (1 - edgeness)),
                radius: 18)
        .shadow(color: .black.opacity(0.5), radius: 14, y: 10)
    }

    /// La profondeur du disque numéro `index`, du fond vers nous.
    private func depth(_ index: Int) -> CGFloat {
        let t = CGFloat(index) / CGFloat(Self.slices - 1)
        return (t - 0.5) * Self.thickness
    }

    /// La tranche : or sombre aux bords, lumière au milieu.
    private var rim: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.44, green: 0.32, blue: 0.07),
                Color(red: 0.97, green: 0.86, blue: 0.52),
                Color(red: 0.62, green: 0.46, blue: 0.13),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// La même rotation pour toutes les couches, à la profondeur près — et le
    /// même filé de quelques degrés, pour un disque posé dans une pièce
    /// plutôt qu'un cercle sur une page.
    private struct Turned: ViewModifier {
        let angle: Double
        let depth: CGFloat

        func body(content: Content) -> some View {
            content
                .rotation3DEffect(
                    .degrees(angle), axis: (x: 0, y: 1, z: 0),
                    anchorZ: -depth, perspective: 0.72
                )
                .rotation3DEffect(.degrees(9), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
        }
    }

    /// Contact shadow. It narrows as the coin turns edge-on and tightens as the
    /// coin lands, which is what reads as a drop rather than a fade-in.
    private var shadow: some View {
        Ellipse()
            .fill(Color.black.opacity(0.42))
            .frame(
                width: Self.size * (0.34 + 0.44 * (1 - edgeness)),
                height: Self.size * 0.1
            )
            .blur(radius: dropped ? 5 : 11)
            .opacity(dropped ? 1 : 0.35)
    }

    /// A band of light sliding across the face. Metal is only convincing when
    /// the highlight moves independently of the object.
    private var specular: some View {
        LinearGradient(
            colors: [.clear, .white.opacity(0.7), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .rotationEffect(.degrees(28))
        .frame(width: Self.size * 0.55)
        .offset(x: CGFloat(sin(radians)) * Self.size * 0.7)
        .blendMode(.softLight)
        .allowsHitTesting(false)
    }
}
