import SwiftUI
import UIKit

/// Shared chrome state. The native scroll view, the embedded web views and the
/// web sheets all drive it, so it cannot live inside any one of them.
@MainActor
final class ChromeState: ObservableObject {
    /// A sheet is open inside a web tab. The bar must get out of its way.
    @Published var sheetOpen = false

    /// Kept so the web tabs and the native scroll views have somewhere to
    /// report to. The bar used to collapse on scroll; it no longer does — a bar
    /// that moves while you are reading is one more thing shifting under the
    /// eye, and it earned back 44pt nobody had asked for.
    func scrolled(to offset: CGFloat) {}

    func reset() {}

    func setSheetOpen(_ open: Bool) {
        guard open != sheetOpen else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { sheetOpen = open }
    }
}

/// Apple's own segmented selection indicator, borrowed.
///
/// Reproducing the travelling Liquid Glass pill in SwiftUI does not work.
/// `matchedGeometryEffect` slides a coloured capsule, and even `glassEffectID`
/// morphing between two `glassEffect` views renders flat — confirmed on an
/// iPhone 16 Pro running 26.3, not just in the Simulator.
///
/// The fix, taken from unionst/union-tab-view: put a real `UISegmentedControl`
/// *behind* the tab items and hide every one of its image subviews except the
/// last, which is the selection indicator itself. UIKit then draws and animates
/// that indicator with the system's own rendering — the actual Liquid Glass, not
/// an impression of it — and its easing and haptics come along for free. The
/// SwiftUI items sit on top purely as visuals; plain `Text` and `Image` do not
/// consume touches, so taps fall through to the control underneath.
private struct SegmentedSelection: UIViewRepresentable {
    let size: CGSize
    let count: Int
    let tint: Color
    @Binding var index: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: Array(repeating: "", count: count))
        control.selectedSegmentIndex = index
        control.backgroundColor = .clear
        control.selectedSegmentTintColor = UIColor(tint)
        control.addTarget(
            context.coordinator,
            action: #selector(Coordinator.changed(_:)),
            for: .valueChanged
        )
        context.coordinator.stripChrome(control)
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        if control.selectedSegmentIndex != index {
            control.selectedSegmentIndex = index
        }
        control.selectedSegmentTintColor = UIColor(tint)
        // Re-run after every layout pass: UIKit rebuilds these subviews when the
        // control resizes, which brings the hidden backgrounds straight back.
        context.coordinator.stripChrome(control)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UISegmentedControl,
        context: Context
    ) -> CGSize? {
        size
    }

    final class Coordinator: NSObject {
        private let parent: SegmentedSelection

        init(_ parent: SegmentedSelection) { self.parent = parent }

        /// Hide the segment backgrounds and dividers, keep the indicator. The
        /// indicator is the *last* image subview; everything before it is the
        /// chrome our own items replace.
        @MainActor func stripChrome(_ control: UISegmentedControl) {
            DispatchQueue.main.async {
                for subview in control.subviews
                where subview is UIImageView && subview != control.subviews.last {
                    subview.alpha = 0
                }
            }
        }

        @MainActor @objc func changed(_ control: UISegmentedControl) {
            parent.index = control.selectedSegmentIndex
        }
    }
}

/// The app's own tab bar.
///
/// Custom rather than the system one for two reasons the system cannot give:
/// iOS 26 minimises its bar toward the *leading* edge with no API to centre it,
/// and it offers no long-press on a tab item. The selection indicator, however,
/// is Apple's — see `SegmentedSelection`.
struct FloatingTabBar: View {
    @Binding var selection: TabRoute
    @ObservedObject var chrome: ChromeState
    let title: (TabRoute) -> String
    /// Outstanding review count, shown on the Activité tab.
    var reviewCount: Int = 0

    private var indexBinding: Binding<Int> {
        Binding(
            // Settings has no slot; while it is showing, leave the indicator
            // where it was rather than snapping it to a tab that isn't there.
            get: { TabRoute.tabs.firstIndex(of: selection) ?? 0 },
            set: { next in
                let tabs = TabRoute.tabs
                guard next >= 0, next < tabs.count, tabs[next] != selection else { return }
                UISelectionFeedbackGenerator().selectionChanged()
                selection = tabs[next]
            }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TabRoute.tabs) { tab in
                label(tab).frame(maxWidth: .infinity)
            }
        }
        /*
         * The labels are paint, nothing else.
         *
         * SwiftUI's Text and Image are hit-testable, so they were swallowing
         * taps that were meant for the UISegmentedControl underneath — the bar
         * looked right and simply did not switch tabs. Turning hit testing off
         * on the visual layer lets every touch reach the control, which is what
         * the whole arrangement depends on: UIKit owns the selection, the
         * indicator animation and the haptic, and we only draw over it.
         */
        .allowsHitTesting(false)
        .background {
            GeometryReader { geo in
                SegmentedSelection(
                    size: geo.size,
                    count: TabRoute.tabs.count,
                    tint: Florin.accent.opacity(0.26),
                    index: indexBinding
                )
            }
        }
        .padding(5)
        .modifier(BarGlass())
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        // Clear of the home indicator. Flush to the safe area the bar's lower
        // glass edge sat a couple of points off the screen bottom, which reads
        // as a stray rule rather than as a floating control.
        .padding(.bottom, 6)
        // Out of the way while a sheet is up: the bar floats above the web
        // content, so an open sheet was having its action buttons covered.
        .offset(y: chrome.sheetOpen ? 140 : 0)
        .opacity(chrome.sheetOpen ? 0 : 1)
        .allowsHitTesting(!chrome.sheetOpen)
    }

    private func label(_ tab: TabRoute) -> some View {
        let active = tab == selection
        return VStack(spacing: 3) {
            Image(systemName: tab.symbol)
                .font(.system(size: 18, weight: active ? .semibold : .regular))
                .symbolVariant(active ? .fill : .none)
                /*
                 * The queue announces itself from wherever you are.
                 *
                 * It used to be a shortcut on the dashboard, which meant you
                 * only learned there was work waiting if you happened to be on
                 * that screen. A badge on the tab is both smaller and more
                 * useful, and it is the convention every app on the phone
                 * already uses.
                 */
                .overlay(alignment: .topTrailing) {
                    if tab == .activity, reviewCount > 0 {
                        Text(reviewCount > 99 ? "99+" : "\(reviewCount)")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Florin.negative, in: Capsule())
                            .offset(x: 11, y: -6)
                            .fixedSize()
                    }
                }
            Text(title(tab))
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(active ? Florin.accent : Florin.text3)
        .padding(.vertical, 7)
        .accessibilityHidden(true)
    }
}

/// The bar's own material.
///
/// Deliberately *not* `.interactive()`. Interactive glass installs its own
/// touch handling on the container and swallows the tap before the
/// `UISegmentedControl` behind the labels can see it — which is what broke tab
/// switching, and what pushed us into driving the selection programmatically
/// (and losing the indicator's animation with it). Plain glass lets the touch
/// through, so UIKit handles the selection itself and animates its own
/// indicator: the real Liquid Glass morph, its easing and its haptic, for free.
private struct BarGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.florinGlass(in: Capsule())
        }
    }
}
