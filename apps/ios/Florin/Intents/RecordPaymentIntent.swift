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
        // Against a server the ledger on screen is the server's; a row written
        // on the phone would be invisible there.
        if UserDefaults.standard.string(forKey: "florin.dataSource") == DataSource.server.rawValue {
            throw LocalWallet.Failure.serverMode
        }
        guard let store = LocalStore.shared else { throw LocalWallet.Failure.noStore }
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
            body: figure
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
     * Two words and a figure.
     *
     * The first version titled it "Paiement ajouté aux opérations à venir",
     * which a banner truncates, and put the merchant, a signed amount and the
     * account on one line joined by a middle dot. Someone who has just paid
     * knows where; what the banner confirms is that Florin has it, and how much.
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
