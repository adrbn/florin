import SwiftUI
import UIKit

extension Notification.Name {
    static let florinShake = Notification.Name("florin.shake")
    /// The ledger was emptied from settings; the app goes back to its welcome.
    static let florinLedgerErased = Notification.Name("florin.ledgerErased")
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
/// away, and it looks like a rendering bug.
///
/// Puis une barre pleine, qui ne disait rien de juste non plus : posée au
/// milieu d'une page, elle se lit comme un bloc de chargement — quelque chose
/// qui va arriver — alors qu'ici rien n'arrivera tant que le rideau est tiré.
/// Des croix sont un signe, pas un gabarit : on voit qu'un chiffre est couvert
/// et on ne devine ni sa longueur ni ses décimales. La hauteur vient de la
/// ligne remplacée, donc la mise en page ne saute pas quand on bascule.
struct Redactable: ViewModifier {
    @ObservedObject private var privacy = Privacy.shared
    var tint: Color = Florin.text

    func body(content: Content) -> some View {
        content
            .opacity(privacy.hidden ? 0 : 1)
            .overlay {
                if privacy.hidden {
                    GeometryReader { geo in
                        Crosses(tint: tint, box: geo.size)
                            .frame(
                                width: geo.size.width, height: geo.size.height,
                                alignment: .trailing
                            )
                    }
                    .transition(.opacity)
                }
            }
            .accessibilityValue(privacy.hidden ? Strings.device("v2.a11y.hidden", "Masqué") : "")
    }
}

/// Les croix qui remplacent un chiffre couvert.
///
/// Leur nombre ne dépend pas de celui des chiffres — ce serait rendre la
/// longueur du montant, qui est justement ce qu'on cache. Quatre, toujours,
/// dimensionnées sur la hauteur de la ligne qu'elles occupent pour qu'un
/// grand nombre soit couvert par de grandes croix et une ligne de liste par
/// de petites.
private struct Crosses: View {
    let tint: Color
    let box: CGSize

    var body: some View {
        let unit = min(max(box.height * 0.52, 7), 26)
        HStack(spacing: unit * 0.34) {
            ForEach(0 ..< 4, id: \.self) { _ in
                Image(systemName: "xmark")
                    .font(.system(size: unit, weight: .semibold))
            }
        }
        .foregroundStyle(tint.opacity(0.42))
        .frame(maxHeight: box.height, alignment: .center)
    }
}

extension View {
    /// Amounts, and anything else that is a figure about money.
    func redactable(tint: Color = Florin.text) -> some View {
        modifier(Redactable(tint: tint))
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
