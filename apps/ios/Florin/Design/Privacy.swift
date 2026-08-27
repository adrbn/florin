import SwiftUI
import UIKit

extension Notification.Name {
    static let florinShake = Notification.Name("florin.shake")
}

/// Hide every figure on screen, instantly.
///
/// The point is the moment someone leans over on a train: you need the numbers
/// gone *before* you have finished reacting, without unlocking a menu. So the
/// gesture is a shake — no target to hit, works one-handed, works with the
/// phone already moving — backed by a switch in Settings for anyone who would
/// rather not shake their phone in public, and a long press on the headline
/// figure itself, which is the thing you are trying to cover.
///
/// It is deliberately *not* security: anyone holding the phone can shake it
/// back. It is a curtain, not a lock, and pretending otherwise would be worse
/// than useless. The state persists across launches so it survives the app
/// being backgrounded mid-conversation.
@MainActor
final class Privacy: ObservableObject {
    static let shared = Privacy()

    private static let key = "florin.hideAmounts"

    @Published private(set) var hidden: Bool {
        didSet { UserDefaults.standard.set(hidden, forKey: Self.key) }
    }

    private init() {
        hidden = UserDefaults.standard.bool(forKey: Self.key)
    }

    func toggle() {
        // A distinct thump either way: you should be able to tell it worked
        // with the phone face-down on a table.
        UIImpactFeedbackGenerator(style: hidden ? .light : .rigid).impactOccurred()
        withAnimation(.snappy(duration: 0.28)) { hidden.toggle() }
    }

    func set(_ value: Bool) {
        guard value != hidden else { return }
        withAnimation(.snappy(duration: 0.28)) { hidden = value }
    }
}

/// A figure that disappears with the curtain.
///
/// Blur was the first attempt and it is the wrong tool: a blurred number is
/// still a number-shaped smear whose length and rough digits read from a metre
/// away, and it looks like a rendering bug. A solid bar of the same width says
/// "withheld" unambiguously and gives nothing away — the width comes from the
/// text it replaces, so the layout does not jump when it toggles.
struct Redactable: ViewModifier {
    @ObservedObject private var privacy = Privacy.shared
    var tint: Color = Florin.text
    /// Keeps the bar honest: a two-digit figure should not redact to the same
    /// width as a six-digit one, but neither should the bar leak the exact
    /// count, so it is clamped.
    var minWidth: CGFloat = 44

    func body(content: Content) -> some View {
        content
            .opacity(privacy.hidden ? 0 : 1)
            .overlay {
                if privacy.hidden {
                    GeometryReader { geo in
                        Capsule()
                            .fill(tint.opacity(0.22))
                            .frame(
                                width: max(minWidth, min(geo.size.width, geo.size.width * 0.86)),
                                height: max(6, geo.size.height * 0.42)
                            )
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .trailing)
                    }
                    .transition(.opacity)
                }
            }
            .accessibilityValue(privacy.hidden ? Strings.device("v2.a11y.hidden", "Masqué") : "")
    }
}

extension View {
    /// Amounts, and anything else that is a figure about money.
    func redactable(tint: Color = Florin.text, minWidth: CGFloat = 44) -> some View {
        modifier(Redactable(tint: tint, minWidth: minWidth))
    }

    /// Hides a whole block — chart axis labels, a ring's centre total — where a
    /// bar in its place would be noise rather than information.
    func hiddenWhenPrivate() -> some View {
        modifier(HideWhenPrivate())
    }
}

struct HideWhenPrivate: ViewModifier {
    @ObservedObject private var privacy = Privacy.shared

    func body(content: Content) -> some View {
        content.opacity(privacy.hidden ? 0 : 1)
    }
}

/// Turns a device shake into a notification.
///
/// A `UIWindow` extension override is the usual recipe for this and it works,
/// but it is a category override on a class we do not own — the kind of thing
/// that stops working without warning. Owning the responder instead is the same
/// three lines and is simply correct.
struct ShakeDetector: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ShakeController { ShakeController() }
    func updateUIViewController(_ controller: ShakeController, context: Context) {}

    final class ShakeController: UIViewController {
        override var canBecomeFirstResponder: Bool { true }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            becomeFirstResponder()
        }

        override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
            guard motion == .motionShake else { return }
            NotificationCenter.default.post(name: .florinShake, object: nil)
        }
    }
}
