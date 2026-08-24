import SwiftUI

/// The launch animation: the app's coin, flicked and left to settle.
///
/// Two seconds, once per cold start, over the same gradient the dashboard
/// stands on — so the app never cuts from a static launch image to a
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
/// The rotation is a flick, not a motor: a steep ease-out over three and a half
/// turns, landing square. Small on purpose — a launch mark is a punctuation
/// mark, and the wordmark that used to sit under it only repeated what the
/// Home Screen already said.
struct SplashView: View {
    let onFinish: () -> Void

    @State private var spin: CGFloat = 0
    @State private var dropped = false
    @State private var leaving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let turns: Double = 3.5
    private static let spinDuration: Double = 1.55
    private static let total: Double = 2.0
    private static let size: CGFloat = 62

    private var angle: Double { Double(spin) * 360 * Self.turns }
    private var radians: Double { angle * .pi / 180 }
    /// 0 face-on, 1 edge-on.
    private var edgeness: Double { 1 - abs(cos(radians)) }
    private var showingBack: Bool { cos(radians) < 0 }

    var body: some View {
        ZStack {
            Backdrop(tint: TabRoute.overview.tint)

            VStack(spacing: 16) {
                coin
                shadow
            }
            .offset(y: dropped ? 0 : -54)
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
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.easeIn(duration: 0.3)) { leaving = true }
            onFinish()
            return
        }

        withAnimation(.spring(response: 0.62, dampingFraction: 0.58)) { dropped = true }
        withAnimation(.timingCurve(0.06, 0.78, 0.12, 1, duration: Self.spinDuration)) { spin = 1 }

        try? await Task.sleep(for: .seconds(Self.total - 0.32))
        // Leaves toward the viewer rather than fading in place: the app arrives
        // *through* the mark instead of after it.
        withAnimation(.easeIn(duration: 0.32)) { leaving = true }
        try? await Task.sleep(for: .milliseconds(320))
        onFinish()
    }

    private var coin: some View {
        ZStack {
            // The edge, revealed as the face turns away from us.
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.44, green: 0.32, blue: 0.07),
                            Color(red: 0.97, green: 0.86, blue: 0.52),
                            Color(red: 0.62, green: 0.46, blue: 0.13),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: Self.size * 0.085, height: Self.size * 0.985)
                .opacity(edgeness * edgeness)

            Image("CoinFace")
                .resizable()
                .scaledToFit()
                .frame(width: Self.size, height: Self.size)
                // The back of a coin is the mirror of what you would see
                // through it; without this the face reads as printed on glass.
                .scaleEffect(x: showingBack ? -1 : 1, y: 1)
                .overlay(specular)
                .mask(Circle())
                .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.72)
                // A few degrees of tilt so it is a disc in a room, not a circle
                // on a page.
                .rotation3DEffect(.degrees(9), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
        }
        .shadow(color: Color(red: 1, green: 0.82, blue: 0.42).opacity(0.28 * (1 - edgeness)),
                radius: 18)
        .shadow(color: .black.opacity(0.5), radius: 14, y: 10)
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
