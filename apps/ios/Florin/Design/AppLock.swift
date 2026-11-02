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
 * Pas de titre : il disait « Florin est verrouillé » à quelqu'un qui voit
 * déjà l'invite Face ID du système par-dessus. Pas de bouton non plus — il
 * n'apparaissait qu'en cas d'échec, et son apparition POUSSAIT la pièce vers
 * le haut : le seul objet de l'écran changeait de place au moment où il
 * fallait le regarder.
 *
 * L'issue de secours est l'écran lui-même : une invite refusée ou ratée se
 * redemande d'une touche n'importe où. Rien à lire, rien qui bouge.
 */
struct LockScreen: View {
    @ObservedObject var lock = AppLock.shared

    var body: some View {
        ZStack {
            Backdrop(tint: TabRoute.overview.tint).ignoresSafeArea()

            CoinLock(open: lock.opened, side: 64)
                .accessibilityLabel(
                    Strings.device("v2.lock.title", "Florin est verrouillé")
                )
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(
                    Strings.device("v2.lock.retry", "Toucher pour réessayer")
                )
        }
        .contentShape(Rectangle())
        .onTapGesture { Task { await lock.unlock() } }
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
    /// L'arc occupe à lui seul 0,27 : au-dessus de la pièce il ne reste donc
    /// qu'un cheveu de patte droite, et c'est voulu — plus longues, elles
    /// faisaient un cadenas de vestiaire posé sur la pièce.
    private var rise: CGFloat { side * 0.32 }
    private var plunge: CGFloat { side * 0.22 }

    /// L'or de la pièce, relevé sur son axe vertical : le liseré du haut,
    /// le plein du champ, l'ombre du bas. Une anse noire à côté d'un métal
    /// rendu en volume ressemblait à un pictogramme collé dessus.
    private static let metal = LinearGradient(
        colors: [
            Color(red: 0.969, green: 0.929, blue: 0.584),
            Color(red: 0.957, green: 0.863, blue: 0.561),
            Color(red: 0.659, green: 0.486, blue: 0.184),
        ],
        startPoint: .top, endPoint: .bottom
    )

    var body: some View {
        ZStack(alignment: .bottom) {
            Shackle()
                .stroke(
                    Self.metal,
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
        /*
         * Aplati AVANT le fondu de sortie.
         *
         * Une opacité posée sur un conteneur s'applique à chaque calque, pas
         * à l'image qu'ils forment : à mi-fondu, la pièce devenue translucide
         * laissait voir les pattes cachées derrière elle, et l'anse semblait
         * passer par-dessus au tout dernier moment. Groupés, les deux calques
         * sont composés d'abord et le fondu ne porte plus que sur le résultat.
         */
        .compositingGroup()
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
