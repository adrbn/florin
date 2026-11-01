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
            locked = !ok
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// The curtain. Deliberately says nothing about the ledger behind it.
struct LockScreen: View {
    @ObservedObject var lock = AppLock.shared

    private var editorial: Bool { FlorinPalette.selected == .editorial }

    private var unlockLabel: String {
        AppLock.biometryName.map {
            Strings.device("v2.lock.unlockWith", "Déverrouiller avec {method}", ["method": $0])
        } ?? Strings.device("v2.lock.unlock", "Déverrouiller")
    }

    var body: some View {
        ZStack {
            Backdrop(tint: TabRoute.overview.tint).ignoresSafeArea()
            if editorial { editorialCurtain } else { curtain }
        }
        .task { await lock.unlock() }
    }

    private var curtain: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Florin.text2)

            Text(Strings.device("v2.lock.title", "Florin est verrouillé"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Florin.text)

            Button {
                Task { await lock.unlock() }
            } label: {
                Text(unlockLabel)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Florin.onAccent)
                    .frame(height: 50)
                    .padding(.horizontal, 28)
                    .background(Florin.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    /*
     * Le rideau, à l'encre.
     *
     * La version colorée est juste dans Obsidienne, où une pilule d'accent est
     * un bouton parmi d'autres. Sur du papier, c'était la seule couleur de
     * l'écran, et elle criait plus fort que la phrase qu'elle sert — d'autant
     * que l'accent d'Éditorial se choisit : la prune de quelqu'un devenait le
     * ton d'un écran de sécurité. Ici le contraste fait tout le travail, comme
     * partout ailleurs dans la maquette : le cadenas et le titre en encre
     * pleine, le bouton en négatif, et rien d'autre.
     *
     * Aligné à gauche sur la gouttière, pas centré : un titre centré est une
     * boîte de dialogue, et la maquette n'en a aucune.
     */
    private var editorialCurtain: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "lock")
                .font(.system(size: 30, weight: .ultraLight))
                .foregroundStyle(Florin.text)

            Text(Strings.device("v2.lock.title", "Florin est verrouillé") + Ed.inkRoom)
                .font(.system(size: 34, weight: .medium))
                .kerning(Ed.tracking(34, 0.045))
                .foregroundStyle(Florin.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 22)

            Button {
                Task { await lock.unlock() }
            } label: {
                Text(unlockLabel)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Florin.bg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Florin.text, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 28)
        }
        .padding(.horizontal, Ed.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
