import SwiftUI
import UIKit

/*
 * Revenir à l'accueil d'un onglet déjà ouvert.
 *
 * C'est la convention de l'iPhone : retaper l'onglet où l'on est ferme ce
 * qui est posé par-dessus et remonte en haut. Les deux moitiés se font ici,
 * en UIKit, et non écran par écran — et c'est délibéré. Une feuille peut
 * être présentée par n'importe lequel des cinq écrans, ou par une feuille
 * elle-même ; une liste qui défile peut venir d'un écran, d'un composant
 * partagé, ou d'un écran qui n'existe pas encore. Demander à chacun de
 * s'inscrire au raccourci, c'est écrire la même ligne six fois et l'oublier
 * la septième. En passant par la fenêtre, le raccourci vaut pour tout ce
 * qu'elle contient, y compris ce qui sera ajouté après.
 */
@MainActor
enum BackToTop {
    static func run() {
        guard let window = Self.window else { return }
        // Fermer d'abord : tant qu'une feuille est là, c'est la sienne qui
        // défile, et remonter celle du dessous ne se verrait pas. Fermer la
        // plus basse emporte celles qu'elle a présentées.
        if let presented = window.rootViewController?.presentedViewController {
            presented.dismiss(animated: true) { scrollUp(in: window) }
        } else {
            scrollUp(in: window)
        }
    }

    private static var window: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow
    }

    private static func scrollUp(in window: UIWindow) {
        guard let scroller = content(of: window) else { return }
        let top = -scroller.adjustedContentInset.top
        // Déjà en haut : ne pas jouer une animation qui ne bouge rien.
        guard scroller.contentOffset.y > top + 1 else { return }
        scroller.setContentOffset(CGPoint(x: scroller.contentOffset.x, y: top), animated: true)
    }

    /*
     * La vue qui défile sous les yeux.
     *
     * La fenêtre en contient plusieurs à la fois : les onglets déjà visités
     * restent montés de part et d'autre, et un graphique peut défiler
     * horizontalement dans son coin. On ne garde donc que celles qui
     * défilent verticalement, qui occupent la largeur de l'écran, et qui
     * sont effectivement dessus — un onglet voisin est à côté de la fenêtre,
     * pas dedans. La plus grande des restantes est le contenu.
     */
    static func content(of window: UIWindow) -> UIScrollView? {
        var best: (view: UIScrollView, area: CGFloat)?
        var queue: [UIView] = [window]
        while let view = queue.first {
            queue.removeFirst()
            queue.append(contentsOf: view.subviews)
            guard let scroller = view as? UIScrollView,
                  !scroller.isHidden, scroller.alpha > 0.01,
                  scroller.contentSize.height > scroller.bounds.height
            else { continue }
            let onScreen = window.bounds.intersection(scroller.convert(scroller.bounds, to: window))
            guard onScreen.width >= window.bounds.width * 0.6 else { continue }
            let area = onScreen.width * onScreen.height
            if best == nil || area > best!.area { best = (scroller, area) }
        }
        return best?.view
    }
}
