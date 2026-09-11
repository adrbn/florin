import SwiftUI

/*
 * The figure itself says the bank is being asked.
 *
 * Pull-to-refresh held the whole screen down under a spinner for as long as
 * the bank took, then laid "À jour" over the search field. The pull now
 * springs straight back, and the balance it would change carries the wait
 * instead: its digits dim and a band of light runs across them — the "slide
 * to unlock" sweep — until the new figure rolls in.
 *
 * With Reduce Motion the digits only dim.
 */
struct SyncShimmer: ViewModifier {
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .opacity(active ? 0.45 : 1)
            .overlay {
                if active && !reduceMotion {
                    GeometryReader { geo in
                        let band = geo.size.width * 0.55
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.9), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: band)
                        .offset(x: -band + phase * (geo.size.width + band))
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                    .onAppear {
                        phase = 0
                        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                            phase = 1
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: active)
    }
}

extension View {
    func syncShimmer(_ active: Bool) -> some View {
        modifier(SyncShimmer(active: active))
    }
}
