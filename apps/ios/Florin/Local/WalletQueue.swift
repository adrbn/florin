import Foundation

/*
 * Les paiements que le grand livre n'a pas pu recevoir, gardés ailleurs.
 *
 * Remplacer l'app remplace son conteneur, et pendant ces quelques secondes la
 * base ne s'ouvre pas. Une action lancée par Wallet à cet instant-là n'a nulle
 * part où écrire — pas même au journal, qui est une table de cette même base.
 * Le paiement n'était alors ni enregistré, ni même constatable : rien nulle
 * part, et une soirée à se demander ce qui s'est passé.
 *
 * Il attend désormais dans les réglages de l'app, le seul endroit encore
 * debout quand la base ne s'ouvre pas, et le lancement suivant le reprend à
 * l'heure où la carte a été présentée.
 */
enum WalletQueue {
    private static let key = "florin.wallet.pending"

    struct Pending: Codable {
        let amountText: String
        let merchant: String
        let card: String?
        let at: Date
    }

    /// Met un paiement de côté. Ne jette jamais : c'est déjà le chemin de
    /// secours, il n'a pas de secours à lui.
    static func hold(
        amountText: String, merchant: String, card: String?, at moment: Date = Date(),
        in defaults: UserDefaults = .standard
    ) {
        var waiting = pending(in: defaults)
        waiting.append(Pending(amountText: amountText, merchant: merchant, card: card, at: moment))
        guard let data = try? JSONEncoder().encode(waiting) else { return }
        defaults.set(data, forKey: key)
    }

    static func pending(in defaults: UserDefaults = .standard) -> [Pending] {
        guard let data = defaults.data(forKey: key),
              let waiting = try? JSONDecoder().decode([Pending].self, from: data)
        else { return [] }
        return waiting
    }

    static func clear(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    /*
     * Reprend ce qui attendait, et le dit.
     *
     * Chaque paiement repris laisse sa ligne au journal — sans quoi il
     * apparaîtrait dans le grand livre sans que rien n'explique d'où il
     * sort, l'inverse exact de ce que le journal est là pour offrir. Un
     * montant que Wallet a donné dans une forme illisible ne peut pas être
     * repris davantage au deuxième essai qu'au premier : sa ligne dit
     * pourquoi, et la file est vidée dans tous les cas plutôt que de
     * retenter à chaque lancement.
     */
    @discardableResult
    static func drain(store: LocalStore, in defaults: UserDefaults = .standard) -> Int {
        let waiting = pending(in: defaults)
        guard !waiting.isEmpty else { return 0 }
        clear(in: defaults)
        var taken = 0
        for payment in waiting {
            let attempt = WalletLog.begin(
                store: store, amountText: payment.amountText,
                merchant: payment.merchant, card: payment.card
            )
            do {
                try LocalWallet.record(
                    store: store, amountText: payment.amountText, merchant: payment.merchant,
                    card: payment.card, accountId: nil, on: payment.at
                )
                WalletLog.finish(
                    store: store, id: attempt, outcome: .recorded,
                    detail: Strings.device("v2.wallet.resumed", "Repris au lancement")
                )
                taken += 1
            } catch {
                WalletLog.finish(
                    store: store, id: attempt, outcome: .failed,
                    detail: error.localizedDescription
                )
            }
        }
        return taken
    }
}
