import Foundation
import SwiftUI

/*
 * Combien d'écritures le grand livre a vues depuis l'ouverture de l'app.
 *
 * Un onglet ne se recharge pas quand on revient dessus : une liste paginée
 * qui se reconstruit perd la position de lecture, et c'est presque toujours
 * pour rien. Presque. Un achat en plusieurs fois saisi depuis l'Aperçu
 * restait invisible dans Activité jusqu'au prochain lancement — alors on le
 * saisissait une deuxième fois, et là il y en avait deux.
 *
 * SQLite compte lui-même les lignes qu'il écrit sur sa connexion, et l'app
 * n'en ouvre qu'une. Rien à publier, rien à oublier au prochain point
 * d'écriture — intention, widget, synchro bancaire ou sheet : si le compteur
 * a bougé, la page affichée est périmée.
 */
enum LedgerStamp {
    static var current: Int { LocalStore.shared?.database.changes ?? 0 }

    /*
     * « Va revoir ton compteur. »
     *
     * Le compteur suffisait tant qu'un onglet était RECONSTRUIT en y
     * revenant : `task` repartait, le compteur était relu. Le pagineur du
     * système garde les cinq pages montées — une page lue une fois ne
     * repasse plus jamais par `task`, donc une opération saisie à l'instant
     * n'apparaissait qu'après avoir tiré la liste à la main.
     *
     * D'où ce signal : il ne dit pas ce qui a changé, seulement qu'il est
     * temps de relire le compteur. C'est lui qui décide ensuite s'il y a
     * vraiment de quoi recharger — un signal pour rien ne coûte qu'une
     * comparaison d'entiers.
     */
    static let recheck = Notification.Name("florin.ledgerRecheck")

    static func touch() {
        NotificationCenter.default.post(name: recheck, object: nil)
    }
}

extension View {
    /// Recharge en revenant sur l'onglet, mais seulement si le grand livre a
    /// changé entre-temps.
    func reloadsOnLedgerChange(_ reload: @escaping () async -> Void) -> some View {
        modifier(LedgerChangeReload(reload: reload))
    }
}

private struct LedgerChangeReload: ViewModifier {
    let reload: () async -> Void
    @State private var seen = LedgerStamp.current
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task { await settle() }
            // Un signal, et le retour d'arrière-plan : le widget et les
            // intentions écrivent sans que l'app soit à l'écran.
            .onReceive(NotificationCenter.default.publisher(for: LedgerStamp.recheck)) { _ in
                Task { await settle() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await settle() }
            }
    }

    private func settle() async {
        let now = LedgerStamp.current
        guard now != seen else { return }
        seen = now
        await reload()
    }
}
