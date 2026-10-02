import SwiftUI

/// The fade under the floating tab bar.
///
/// Without it the list ran on underneath the bar and out through the home
/// indicator, so the bar's lower glass edge read as a seam laid over the
/// content.
///
/// Deliberately restrained. A full-height progressive blur washed the bottom
/// third of the screen a pale grey — the material brightens in dark mode, and
/// three stacked layers brightened it three times over. What is wanted is the
/// last ~30pt going quietly dark, not a frosted band. So: one soft blur layer
/// confined to the very bottom, and a short dark gradient carrying most of the
/// work.
struct BottomScrim: View {
    var height: CGFloat = 142

    var body: some View {
        ZStack {
            // Two layers so the blur ramps rather than switching on at a
            // line, but both confined to the lower half — three full-height
            // layers washed the bottom third of the screen pale grey, because
            // the material brightens in dark mode and stacking brightens it
            // again each time.
            ForEach(0..<2, id: \.self) { layer in
                let start = 0.34 + Double(layer) * 0.22
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: start),
                                .init(color: .black.opacity(0.9), location: min(1, start + 0.34)),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            // Carries most of the work, and keeps the result dark rather than
            // frosted.
            LinearGradient(
                stops: [
                    .init(color: Florin.bg.opacity(0), location: 0),
                    .init(color: Florin.bg.opacity(0.22), location: 0.4),
                    .init(color: Florin.bg.opacity(0.60), location: 0.72),
                    .init(color: Florin.bg.opacity(0.88), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(height: height)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// The same idea at the top of the screen, and nothing more than that.
///
/// A tab root hides the navigation bar and lets its content scroll under the
/// clock, so rows arrived at the status bar at full contrast and the time sat
/// on top of a figure.
///
/// Blur only. The first version fell to the page's own ground — `Florin.bg`
/// plus the section's hue — which was far too strong and, being coloured,
/// read as a band of the backdrop laid over the content rather than as the
/// content softening. What is wanted up there is that the words lose their
/// edges, not that they disappear behind anything.
///
/// The black is not decoration: `.ultraThinMaterial` *brightens* what is
/// under it in dark mode, so blur alone would leave a pale strip under the
/// clock. A little black cancels that out and nothing more — the bottom scrim
/// learnt the same lesson.
///
/// Invisible at rest, since nothing is under the clock until you scroll.
struct TopScrim: View {
    /// How far the page has scrolled from rest.
    let scrolled: CGFloat

    /// The status bar / island, measured rather than assumed.
    private static var safeTop: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.top) ?? 59
    }

    /// Dense at the clock, gone by the foot of the strip. One ramp, eased, so
    /// the blur arrives gradually rather than at a line — two stacked layers
    /// blurred twice over, which is how the first attempt got heavy.
    private static let ramp = LinearGradient(
        stops: [
            .init(color: .black, location: 0),
            .init(color: .black.opacity(0.55), location: 0.45),
            .init(color: .black.opacity(0.16), location: 0.75),
            .init(color: .clear, location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            // Just enough to stop the material reading as a pale strip.
            .overlay(Color.black.opacity(0.14))
            .mask(Self.ramp)
            .frame(height: Self.safeTop + 24)
            .opacity(min(max(scrolled / 20, 0), 1))
            .ignoresSafeArea(.container, edges: .top)
            .allowsHitTesting(false)
    }
}
