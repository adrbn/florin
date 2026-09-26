import AppIntents
import Foundation
import UserNotifications

/*
 * A Shortcuts action: a card payment, recorded as upcoming.
 *
 * Meant for a personal automation on the Wallet "transaction" trigger, which
 * runs when a card is presented and hands over the merchant, the amount and
 * the card. Florin records the payment under "upcoming" without opening, and
 * the bank's own row replaces it when it arrives — see `LocalWallet`.
 *
 * Every text here is read by iOS rather than by the app, so it comes from the
 * `Intents` string catalog instead of the app's own tables.
 */
struct RecordPaymentIntent: AppIntent {
    static let title = LocalizedStringResource(
        "intent.payment.title", defaultValue: "Add an upcoming payment", table: "Intents"
    )
    static let description = IntentDescription(LocalizedStringResource(
        "intent.payment.description",
        defaultValue: "Records a card payment as upcoming in Florin. When your bank books it, the bank's transaction replaces this one.",
        table: "Intents"
    ))
    /// Nothing to show: the point is that paying does not mean opening an app.
    static let openAppWhenRun = false

    @Parameter(title: LocalizedStringResource("intent.payment.amount", defaultValue: "Amount", table: "Intents"))
    var amount: String

    @Parameter(title: LocalizedStringResource("intent.payment.merchant", defaultValue: "Merchant", table: "Intents"))
    var merchant: String

    @Parameter(title: LocalizedStringResource("intent.payment.card", defaultValue: "Card", table: "Intents"))
    var card: String?

    @Parameter(title: LocalizedStringResource("intent.payment.account", defaultValue: "Account", table: "Intents"))
    var account: FlorinAccountEntity?

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        /*
         * La tentative est inscrite avant tout le reste.
         *
         * Ouverte ici, close par son issue : ce que Wallet a donné est gardé
         * même quand rien n'a pu être enregistré — et c'est justement ce
         * cas-là qu'on ne pouvait pas lire. Le journal ne doit jamais empêcher
         * un paiement d'entrer, d'où le magasin optionnel et les écritures qui
         * ne jettent pas.
         */
        let attempt = LocalStore.shared.map {
            WalletLog.begin(store: $0, amountText: amount, merchant: merchant, card: card)
        }
        func close(_ outcome: WalletLog.Outcome, _ detail: String? = nil) {
            guard let store = LocalStore.shared, let attempt else { return }
            WalletLog.finish(store: store, id: attempt, outcome: outcome, detail: detail)
        }
        do {
            let done = try await record()
            close(.recorded)
            return done
        } catch {
            close(.failed, error.localizedDescription)
            /*
             * Un paiement qui n'est pas entré doit le dire.
             *
             * L'automatisation tourne sans ouvrir l'app et son « me prévenir
             * lors de l'exécution » est décoché — c'est tout l'intérêt. Mais
             * alors une action qui échoue ne laisse rien du tout : pas de
             * ligne, pas de bandeau, pas de trace. L'ardoise reste muette
             * pendant des jours et on croit que la détection s'est arrêtée
             * d'elle-même. Le succès se signale déjà ; l'échec le doit
             * davantage, puisque lui seul demande quelque chose.
             */
            await Self.notify(
                title: Strings.device("v2.wallet.notifyFailed", "Paiement non ajouté"),
                body: error.localizedDescription
            )
            throw error
        }
    }

    private func record() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        // Against a server the ledger on screen is the server's; a row written
        // on the phone would be invisible there.
        if UserDefaults.standard.string(forKey: "florin.dataSource") == DataSource.server.rawValue {
            throw LocalWallet.Failure.serverMode
        }
        /*
         * Une base fermée ne fait pas disparaître un paiement.
         *
         * Remplacer l'app remplace son conteneur : pendant ces quelques
         * secondes le grand livre ne s'ouvre pas, et jusqu'ici l'action
         * renonçait — sans ligne, et sans même une tentative au journal,
         * qui est une table de cette base. Le paiement est mis de côté là
         * où les réglages tiennent debout, et la prochaine ouverture le
         * reprend à l'heure de la carte.
         */
        guard let store = LocalStore.shared else {
            WalletQueue.hold(amountText: amount, merchant: merchant, card: card)
            let held = Strings.device(
                "v2.wallet.heldBody", "{merchant} — ajouté à la prochaine ouverture de Florin",
                ["merchant": merchant]
            )
            await Self.notify(
                title: Strings.device("v2.wallet.notifyHeld", "Paiement mis en attente"),
                body: held
            )
            return .result(value: held, dialog: IntentDialog(stringLiteral: held))
        }
        let recorded = try LocalWallet.record(
            store: store,
            amountText: amount,
            merchant: merchant,
            card: card,
            accountId: account?.id
        )
        // The name the merchant was given in Florin, when it has one.
        let name = PayeeText.humanize(recorded.payee)
        // A payment, so no minus sign: the sentence already says which way.
        let figure = Money.string(abs(recorded.amount), locale: Strings.device.localeTag, currency: "EUR")
        await Self.notify(
            title: Strings.device("v2.wallet.notifyTitle", "Paiement ajouté"),
            body: "\(figure) — \(name)"
        )
        let summary = Strings.device("v2.wallet.dialog", "{merchant} : {amount} à venir",
                                     ["merchant": name, "amount": figure])
        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
    }

    /*
     * Said by Florin, not by Shortcuts.
     *
     * An automation's own confirmation arrives under the Shortcuts icon, which
     * says that something ran rather than what was recorded. When Florin may
     * notify, it says it itself; the automation's "show when run" can then be
     * switched off. Without permission nothing is posted — the action still
     * returns the same line for the shortcut to show.
     */
    /*
     * Two words, a figure and the shop.
     *
     * The first version titled it "Paiement ajouté aux opérations à venir",
     * which a banner truncates, and put the merchant, a signed amount and the
     * account on one line joined by a middle dot. What is left is the amount
     * and the merchant under the name it has in Florin — the renamed one when
     * it has been renamed, so the banner says "Le Comptoir" where the terminal
     * said "SARL LE COMPTOIR 1234". No sign: a payment only goes one way.
     */
    private static func notify(title: String, body: String) async {
        let centre = UNUserNotificationCenter.current()
        guard await centre.notificationSettings().authorizationStatus == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        try? await centre.add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}

/// An account, as Shortcuts lists it for the action's "Account" parameter.
struct FlorinAccountEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("intent.entity.account", defaultValue: "Account", table: "Intents")
    )
    static let defaultQuery = FlorinAccountQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct FlorinAccountQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FlorinAccountEntity] {
        accounts().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [FlorinAccountEntity] {
        accounts()
    }

    /// The accounts a card can draw on: current accounts first, then cash.
    private func accounts() -> [FlorinAccountEntity] {
        guard let store = LocalStore.shared,
              let rows = try? store.database.query(
                  """
                  SELECT id, name FROM accounts
                  WHERE is_archived = 0 AND kind IN ('checking', 'cash')
                  ORDER BY kind = 'cash', display_order, name
                  """
              ) else { return [] }
        return rows.compactMap { row in
            guard let id = row.string("id"), let name = row.string("name") else { return nil }
            return FlorinAccountEntity(id: id, name: name)
        }
    }
}
