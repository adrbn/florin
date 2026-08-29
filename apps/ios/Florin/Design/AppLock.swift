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

    /// Called when the app leaves the foreground. Locks ahead of time so the
    /// ledger is already hidden in the app switcher, not just once someone
    /// returns to it.
    func willResignActive() {
        guard enabled else { return }
        locked = true
    }

    func unlock() async {
        guard locked else { return }
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

    var body: some View {
        ZStack {
            Backdrop(tint: TabRoute.overview.tint).ignoresSafeArea()

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
                    Text(
                        AppLock.biometryName.map {
                            Strings.device(
                                "v2.lock.unlockWith", "Déverrouiller avec {method}",
                                ["method": $0]
                            )
                        } ?? Strings.device("v2.lock.unlock", "Déverrouiller")
                    )
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(height: 50)
                    .padding(.horizontal, 28)
                    .background(Florin.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .task { await lock.unlock() }
    }
}
