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

/// The same thing at the top of the screen.
///
/// A tab root hides the navigation bar and lets its content scroll under the
/// clock, so rows arrived at the status bar at full contrast and the time sat
/// on top of a figure. This thins them out before they get there.
///
/// Two differences from the bottom. The colour is the page's own ground, not
/// `Florin.bg`: up there the backdrop is at its most saturated, and a neutral
/// fade read as a grey slab laid across the top of the screen. And it is
/// invisible at rest — nothing is under the clock until you scroll — so it
/// fades in over the first few points instead of being always on.
struct TopScrim: View {
    /// The section's hue, as `Backdrop` receives it.
    let tint: Color
    /// How far the page has scrolled from rest.
    let scrolled: CGFloat

    /// The status bar / island, measured rather than assumed.
    private static var safeTop: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.top) ?? 59
    }

    var body: some View {
        ZStack {
            // Mirrors the bottom's ramp, turned over: two layers so the blur
            // arrives gradually rather than at a line, both confined to the
            // extreme edge.
            ForEach(0..<2, id: \.self) { layer in
                let end = 0.66 - Double(layer) * 0.22
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(0.9), location: max(0, end - 0.34)),
                                .init(color: .clear, location: end),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            // The ground as it is at the very top of the screen — `Backdrop`'s
            // first stop — so the fade reads as the page itself thickening,
            // with no edge and no change of hue.
            ZStack {
                Florin.bg
                tint.opacity(0.62)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.92), location: 0),
                        .init(color: .black.opacity(0.60), location: 0.5),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .frame(height: Self.safeTop + 34)
        .opacity(min(max(scrolled / 16, 0), 1))
        .ignoresSafeArea(.container, edges: .top)
        .allowsHitTesting(false)
    }
}
