import LocalAuthentication
import SwiftUI

/*
 * Face ID over the whole ledger.
 *
 * "Masquer les montants" says of itself that it hides rather than locks —
 * shaking the phone brings everything back, which is the point of it. That
 * leaves the actual protection of a year of banking to whoever is holding an
 * unlocked phone. This is the other half: nothing is drawn until the person is
 * the person.
 *
 * Off by default, and deliberately so. An app that demands a face before it
 * has shown anyone what it is for is asking for trust it has not earned yet.
 */
@MainActor
final class AppLock: ObservableObject {
    static let shared = AppLock()

    /// Whether the ledger is currently hidden behind the lock.
    @Published private(set) var locked: Bool
    /// Le voile du sélecteur d'apps : opaque, muet, sans Face ID. Voir
    /// `cover()`.
    @Published private(set) var shielded = false
    /// Set when a prompt fails or is dismissed, so the screen can offer another
    /// go rather than sit there blank.
    @Published private(set) var failure: String?
    /// Le visage est passé : l'anse du cadenas s'ouvre, le rideau n'est pas
    /// encore levé. Voir `unlock()`.
    @Published private(set) var opened = false

    private var enabled: Bool {
        UserDefaults.standard.bool(forKey: Self.key)
    }

    static let key = "florin.lock"

    private init() {
        locked = UserDefaults.standard.bool(forKey: Self.key)
    }

    /// What this device can actually do, for labelling the setting honestly:
    /// "Face ID" on a phone with it, "Touch ID" on one without, and nothing at
    /// all where no biometry is enrolled.
    static var biometryName: String? {
        let context = LAContext()
        guard context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: nil
        ) else { return nil }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return nil
        }
    }

    func set(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.key)
        // Turning it on must not lock the person out of the screen they are
        // standing on; it takes effect the next time the app is left.
        if !on { locked = false }
    }

    /*
     * Un voile, puis un verrou — et ce ne sont pas le même moment.
     *
     * Verrouiller dès que l'app n'est plus « active » revenait à réclamer
     * Face ID pour une capture d'écran, un centre de contrôle tiré, une
     * bannière de notification : tout cela passe par `.inactive` sans que
     * personne n'ait quitté l'app. Ce qu'il faut protéger à cet instant,
     * c'est l'image que iOS prend pour le sélecteur d'apps — un voile opaque
     * y suffit, et il se lève tout seul au retour.
     *
     * Le verrou, lui, attend un vrai départ : `.background`.
     */
    func cover() {
        guard enabled, !locked else { return }
        shielded = true
    }

    /*
     * Le retour au premier plan demande le visage, tout seul.
     *
     * `LockScreen` a bien un `.task` qui le demande — mais il part UNE fois,
     * à l'apparition du rideau, et le rideau apparaît au moment où l'app
     * s'en va : il n'y a personne devant l'écran pour répondre, et au retour
     * la vue existe déjà, donc rien ne repart. Il restait un bouton à
     * appuyer pour rien. C'est la reprise elle-même qui doit redemander.
     */
    func uncover() {
        shielded = false
        guard locked else { return }
        Task { await unlock() }
    }

    /// L'app est partie en arrière-plan. Là, on verrouille.
    func leaveForeground() {
        guard enabled else { return }
        shielded = false
        opened = false
        locked = true
    }

    /// Une invite à la fois : `LockScreen` en demande une à l'apparition, la
    /// reprise au premier plan une autre, et les deux peuvent tomber ensemble.
    private var prompting = false

    func unlock() async {
        guard locked, !prompting else { return }
        prompting = true
        defer { prompting = false }
        let context = LAContext()
        context.localizedFallbackTitle = ""
        do {
            /*
             * `deviceOwnerAuthentication`, not the biometrics-only policy.
             *
             * A face that will not read — gloves, a bad angle, a twin — should
             * fall through to the passcode rather than into a locked app with
             * no way forward. This is the same policy the system uses for its
             * own sensitive screens.
             */
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: Strings.device(
                    "v2.lock.reason", "Déverrouiller Florin"
                )
            )
            failure = nil
            /*
             * Le pêne s'ouvre avant que le rideau ne se lève.
             *
             * `locked = false` retire `LockScreen` en 0,18 s : l'anse aurait
             * bien pivoté, mais sur une vue déjà en train de disparaître —
             * personne ne l'aurait vue. On publie donc l'ouverture d'abord, et
             * on garde le rideau le temps du ressort. Sans animation (mouvement
             * réduit), il n'y a rien à regarder : on ne fait pas attendre.
             */
            if ok {
                opened = true
                if !UIAccessibility.isReduceMotionEnabled {
                    try? await Task.sleep(for: .milliseconds(520))
                }
            }
            locked = !ok
        } catch {
            failure = error.localizedDescription
        }
    }
}

/*
 * Le rideau : la pièce, et rien.
 *
 * Il y avait un titre et un bouton. Le titre disait « Florin est
 * verrouillé » à quelqu'un qui voit déjà l'invite Face ID du système
 * par-dessus, et le bouton réclamait un geste pour ce qui part tout seul à
 * l'apparition comme au retour au premier plan. Un cadenas fermé dit la même
 * chose sans mot, dans les neuf langues.
 *
 * Le bouton revient quand le visage n'est PAS passé — là, il y a vraiment
 * quelque chose à faire, et aucune invite à l'écran pour le dire.
 */
struct LockScreen: View {
    @ObservedObject var lock = AppLock.shared

    private var unlockLabel: String {
        AppLock.biometryName.map {
            Strings.device("v2.lock.unlockWith", "Déverrouiller avec {method}", ["method": $0])
        } ?? Strings.device("v2.lock.unlock", "Déverrouiller")
    }

    var body: some View {
        ZStack {
            Backdrop(tint: TabRoute.overview.tint).ignoresSafeArea()

            VStack(spacing: 24) {
                CoinLock(open: lock.opened, side: 64)
                    .accessibilityLabel(
                        Strings.device("v2.lock.title", "Florin est verrouillé")
                    )

                if lock.failure != nil {
                    Button {
                        Task { await lock.unlock() }
                    } label: {
                        Text(unlockLabel)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Florin.text)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task { await lock.unlock() }
    }
}

/*
 * La pièce de Florin, en cadenas.
 *
 * Un `lock.fill` disait « verrouillé » et rien d'autre ; la pièce, elle, dit
 * aussi de quoi il s'agit. L'anse est dessinée DERRIÈRE la pièce, c'est ce qui
 * fait plonger ses pattes dedans au lieu de la poser dessus — sans ça, on voit
 * deux objets côte à côte, pas un cadenas.
 *
 * À l'ouverture elle pivote autour de la patte droite et se soulève d'un
 * cheveu, pour que la patte gauche sorte visiblement de son logement. Le
 * déverrouillage prend le temps de se regarder : voir `unlock()`.
 */
struct CoinLock: View {
    /// L'anse décrochée.
    let open: Bool
    /// Le diamètre de la pièce ; tout le reste en découle.
    var side: CGFloat = 44

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Ce qui dépasse au-dessus de la pièce, et ce qui s'enfonce dedans.
    private var rise: CGFloat { side * 0.42 }
    private var plunge: CGFloat { side * 0.22 }

    var body: some View {
        ZStack(alignment: .bottom) {
            Shackle()
                .stroke(
                    Florin.text,
                    style: StrokeStyle(lineWidth: side * 0.075, lineCap: .round)
                )
                .frame(width: side * 0.54, height: rise + plunge)
                .rotationEffect(.degrees(open ? 32 : 0), anchor: .bottomTrailing)
                .offset(y: -(side - plunge) - (open ? side * 0.06 : 0))
                .animation(
                    reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.62),
                    value: open
                )

            Image("CoinFace")
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
        }
        // L'anse déborde vers le haut sans peser sur la mise en page : on lui
        // réserve la place ici, sinon elle vient se poser sur le titre.
        .frame(width: side, height: side + rise, alignment: .bottom)
    }
}

/// Un U à l'envers : patte, demi-cercle, patte.
private struct Shackle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.width / 2
        let crown = rect.minY + radius
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: crown))
        path.addArc(
            center: CGPoint(x: rect.midX, y: crown), radius: radius,
            startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}
