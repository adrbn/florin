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
