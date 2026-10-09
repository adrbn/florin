import SwiftUI

/*
 * Ce qu'on montre quand la base existe mais ne s'ouvre pas.
 *
 * L'app n'avait que deux réponses à « combien de comptes ? » : un nombre, ou
 * l'onboarding. Une base qu'on n'arrive pas à ouvrir rendait zéro, donc
 * l'onboarding — par-dessus un grand livre entier, intact sur le disque, avec
 * un bouton qui proposait de créer un premier compte. C'est le pire écran
 * possible à ce moment précis : il affirme une perte qui n'a pas eu lieu, et
 * la première chose qu'il offre est d'écrire dans le fichier qu'il n'a pas su
 * lire.
 *
 * Trois états, pas deux. « Rien encore » et « pas maintenant » ne sont pas la
 * même phrase, et seule la première autorise à créer quoi que ce soit.
 */
struct LedgerUnavailable: View {
    let onRetry: () -> Void

    @State private var retrying = false

    var body: some View {
        ZStack {
            Backdrop(tint: Florin.accent).ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "lock.rectangle.stack")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Florin.accent)
                Text(Strings.device(
                    "v2.ledger.unavailableTitle",
                    "Florin n'a pas pu ouvrir sa base"
                ))
                .font(.system(size: 26, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Florin.text)
                // Dire que rien n'est perdu, parce que rien ne l'est : le
                // fichier est là, c'est l'accès qui a manqué.
                Text(Strings.device(
                    "v2.ledger.unavailableBody",
                    """
                    Tes données sont toujours sur cet appareil. Déverrouille \
                    l'iPhone, puis réessaie — si ça persiste, ferme Florin \
                    complètement et rouvre-la.
                    """
                ))
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(Florin.text2)
                if let reason = LocalStore.lastFailure?.localizedDescription {
                    Text(reason)
                        .font(.system(size: 12, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Florin.text3)
                }
                Spacer()
                Button {
                    retrying = true
                    onRetry()
                    retrying = false
                } label: {
                    HStack(spacing: 8) {
                        if retrying { ProgressView().tint(.black) }
                        Text(Strings.device("v2.ledger.retry", "Réessayer"))
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Florin.accent, in: Capsule())
                }
                .buttonStyle(PressScale())
            }
            .padding(.horizontal, Florin.gutter)
            .padding(.bottom, 24)
        }
        .preferredColorScheme(.dark)
    }
}
