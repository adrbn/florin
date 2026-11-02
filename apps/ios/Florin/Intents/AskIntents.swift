import AppIntents
import Foundation

/*
 * Deux questions qu'on pose sans ouvrir l'app.
 *
 * Elles ne changent rien : elles lisent le grand livre et répondent une
 * phrase. C'est ce qui les rend bonnes à la voix — une action vocale qui
 * écrit demanderait une confirmation, et une confirmation à la voix coûte
 * plus cher que d'ouvrir l'app.
 *
 * Les titres et descriptions sont lus par iOS, donc ils viennent du catalogue
 * `Intents`. La RÉPONSE, elle, vient de la table de l'app (`Strings.device`),
 * parce qu'elle porte un montant : la devise et le format de nombre suivent le
 * réglage de langue de l'app, et une phrase dans une autre langue que le
 * montant qu'elle contient se lit mal.
 */

/// Ce qu'il reste à dépenser ce mois-ci.
struct LeftToSpendIntent: AppIntent {
    static let title = LocalizedStringResource(
        "intent.left.title", defaultValue: "How much is left this month", table: "Intents"
    )
    static let description = IntentDescription(LocalizedStringResource(
        "intent.left.description",
        defaultValue: "Answers with what is left to spend this month, from the ledger on this device.",
        table: "Intents"
    ))
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let data = try FlorinAsk.read()
        let t = Strings.device
        let left = data.leftToSpend.leftToSpend
        let figure = Money.string(abs(left), locale: t.localeTag, currency: data.currency)
        // Au-dessus du plafond, la phrase change de verbe plutôt que de signe :
        // « il vous reste −18 € » ne se comprend pas à l'oreille.
        let said = left >= 0
            ? t("v2.siri.left", "Il vous reste {amount} à dépenser ce mois-ci.", ["amount": figure])
            : t("v2.siri.over", "Vous avez dépassé de {amount} ce mois-ci.", ["amount": figure])
        return .result(value: said, dialog: IntentDialog(stringLiteral: said))
    }
}

/// Le patrimoine, net de ce qui est dû.
struct NetWorthIntent: AppIntent {
    static let title = LocalizedStringResource(
        "intent.worth.title", defaultValue: "What my net worth is", table: "Intents"
    )
    static let description = IntentDescription(LocalizedStringResource(
        "intent.worth.description",
        defaultValue: "Answers with your net worth, from the ledger on this device.",
        table: "Intents"
    ))
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let data = try FlorinAsk.read()
        let t = Strings.device
        let figure = Money.string(data.netWorth.net, locale: t.localeTag, currency: data.currency)
        let said = t("v2.siri.worth", "Votre patrimoine est de {amount}.", ["amount": figure])
        return .result(value: said, dialog: IntentDialog(stringLiteral: said))
    }
}

/// Ce que les deux questions ont en commun.
enum FlorinAsk {
    enum Failure: LocalizedError {
        case noLedger
        case serverMode

        var errorDescription: String? {
            switch self {
            case .noLedger:
                Strings.device("v2.siri.noLedger", "Florin n'a pas pu ouvrir votre grand livre.")
            case .serverMode:
                Strings.device(
                    "v2.siri.serverMode",
                    "Florin lit un serveur : ouvrez l'app pour voir vos chiffres."
                )
            }
        }
    }

    /*
     * Le grand livre RÉEL, comme pour un paiement.
     *
     * Le mode démonstration ouvre un autre fichier, et répondre à la voix
     * avec les chiffres inventés de la démonstration serait pire que de ne
     * pas répondre — rien ne dirait, sans écran, que ce ne sont pas les
     * siens. Voir `LocalStore.realLedger`.
     */
    static func read() throws -> Overview {
        if UserDefaults.standard.string(forKey: "florin.dataSource") == DataSource.server.rawValue {
            throw Failure.serverMode
        }
        guard let store = LocalStore.realLedger else { throw Failure.noLedger }
        return try LocalQueries.overview(store: store, locale: Strings.preferredShortLocale)
    }
}
