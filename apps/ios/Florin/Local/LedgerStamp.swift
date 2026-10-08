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

    func body(content: Content) -> some View {
        content.task {
            let now = LedgerStamp.current
            guard now != seen else { return }
            seen = now
            await reload()
        }
    }
}
