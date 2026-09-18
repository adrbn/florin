import Foundation

/// Payments recorded the moment a card is tapped, before the bank books them.
///
/// A Shortcuts automation on the Wallet "transaction" trigger hands Florin the
/// merchant and the amount at the till; the bank shows the same debit one to
/// three days later. In between, the money is spent and the ledger does not
/// know it. This writes the payment as an upcoming row, and lets the bank's
/// own row take its place when it lands.
///
/// The row is `scheduled` and pending: it shows under "upcoming" and in the
/// month's projection, but not in the balance. The balance of a synced account
/// is the bank's figure, and counting the payment there before the bank does
/// would have the next sync count it twice.
enum LocalWallet {
    /// The `source` these rows carry — what the reconciliation looks for.
    /// `ios_shortcut` has been in every schema's source list since the first
    /// migration, waiting for exactly this; Postgres rejects any other word,
    /// so mirroring the phone onto a server keeps these rows.
    static let source = "ios_shortcut"

    enum Failure: LocalizedError {
        case noStore
        case noAccount
        case serverMode
        case badAmount(String)

        var errorDescription: String? {
            switch self {
            case .noStore:
                Strings.device("v2.common.errorNoDatabase", "Florin n'a pas pu ouvrir sa base de données sur cet appareil.")
            case .noAccount:
                Strings.device("v2.wallet.noAccount", "Aucun compte courant dans Florin pour y ajouter ce paiement.")
            case .serverMode:
                Strings.device("v2.wallet.serverMode", "Florin affiche votre serveur : les paiements ne peuvent être ajoutés qu'aux comptes de cet appareil.")
            case .badAmount(let text):
                Strings.device("v2.wallet.badAmount", "Montant illisible : {amount}")
                    .replacingOccurrences(of: "{amount}", with: text)
            }
        }
    }

    /// What was recorded, for the automation's confirmation.
    struct Recorded {
        let payee: String
        let amount: Double
        let accountName: String
    }

    // MARK: - Recording

    /*
     * The amount as Wallet hands it over.
     *
     * The trigger's "Amount" arrives as text in the phone's own format —
     * "4,10 €", "€4.10", "1 234,56 €", sometimes with a narrow no-break space
     * as the thousands separator. A payment is always money leaving, so the
     * sign is ours to set.
     */
    static func parseAmount(_ text: String) -> Double? {
        var cleaned = text.filter { $0.isNumber || $0 == "," || $0 == "." }
        guard !cleaned.isEmpty else { return nil }
        if let comma = cleaned.lastIndex(of: ","), let dot = cleaned.lastIndex(of: ".") {
            // Whichever comes last is the decimal separator.
            if comma > dot {
                cleaned = cleaned.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            }
        } else if cleaned.contains(",") {
            cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        }
        guard let value = Double(cleaned), value > 0 else { return nil }
        return (value * 100).rounded() / 100
    }

    /// The account a payment lands on when the shortcut does not say: the
    /// first current account, the way the accounts list orders them.
    static func defaultAccount(store: LocalStore) throws -> (id: String, name: String)? {
        let row = try store.database.query(
            """
            SELECT id, name FROM accounts
            WHERE is_archived = 0 AND kind = 'checking'
            ORDER BY display_order, name LIMIT 1
            """
        ).first
        guard let id = row?.string("id") else { return nil }
        return (id, row?.string("name") ?? "")
    }

    @discardableResult
    static func record(
        store: LocalStore,
        amountText: String,
        merchant: String,
        card: String?,
        accountId: String?,
        on day: Date = Date()
    ) throws -> Recorded {
        guard let amount = parseAmount(amountText) else { throw Failure.badAmount(amountText) }

        let account: (id: String, name: String)
        if let accountId,
           let name = try store.database.scalar(
               "SELECT name FROM accounts WHERE id = ? AND is_archived = 0", [.text(accountId)]
           )?.string {
            account = (accountId, name)
        } else if let fallback = try defaultAccount(store: store) {
            account = fallback
        } else {
            throw Failure.noAccount
        }

        let payee = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = payee.isEmpty ? "Apple Pay" : payee
        let memo = card.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : "Apple Pay · \($0)" } ?? "Apple Pay"

        /*
         * The hour of the tap, not midnight.
         *
         * Wallet knows when the card was presented, and a payment recorded at
         * midnight throws that away. Every screen reads the day out of
         * `substr(occurred_at, 1, 10)`, so the date stays the local one —
         * hence the local wall clock under a Z rather than a true instant.
         * Nothing sorts on the hour (`LocalQueries.readTransactions` explains
         * why it cannot), but the ledger should not be made to forget it.
         */
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: day
        )
        let occurred = String(
            format: "%04d-%02d-%02dT%02d:%02d:%02dZ",
            parts.year!, parts.month!, parts.day!, parts.hour!, parts.minute!, parts.second!
        )

        try insertUpcoming(
            store: store, accountId: account.id, occurredAt: occurred,
            amount: -amount, payee: label, memo: memo, categoryId: nil
        )
        return Recorded(payee: label, amount: amount, accountName: account.name)
    }

    /*
     * The same row, entered by hand.
     *
     * The automation only fires when Wallet sees the payment, and Wallet sees
     * nothing without a connection — a card tapped in a shop with no signal
     * leaves no trace until the bank books it days later. Typed in from the
     * add sheet, the payment waits under "upcoming" and the bank's row takes
     * its place exactly as it would have for one recorded at the till.
     */
    static func recordUpcoming(store: LocalStore, _ tx: NewTransaction) throws {
        try insertUpcoming(
            store: store, accountId: tx.accountId, occurredAt: tx.occurredAt,
            amount: tx.amount, payee: tx.payee, memo: tx.memo, categoryId: tx.categoryId
        )
    }

    private static func insertUpcoming(
        store: LocalStore, accountId: String, occurredAt: String,
        amount: Double, payee: String, memo: String?, categoryId: String?
    ) throws {
        try store.database.run(
            """
            INSERT INTO transactions
                (id, account_id, occurred_at, amount, currency, payee, normalized_payee,
                 memo, category_id, source, status, is_pending, needs_review)
            VALUES (?, ?, ?, ?, 'EUR', ?, ?, ?, ?, ?, 'scheduled', 1, 0)
            """,
            [
                .text(UUID().uuidString), .text(accountId), .text(occurredAt),
                .real(amount), .text(payee), .text(LocalLedger.normalize(payee)),
                memo.map { .text($0) } ?? .null, categoryId.map { .text($0) } ?? .null,
                .text(source),
            ]
        )
        // Filed from history straight away, so the upcoming row already says
        // what it is — the café it has been every other time.
        _ = try? LocalCategoriser.backfill(store: store)
    }

    // MARK: - Letting the bank's row take over

    /*
     * The bank's row replaces the one recorded at the till.
     *
     * Same account, same amount to the cent, dated from the day of the tap to
     * a week after it — card payments reach the statement in one to three
     * working days, and a weekend or a bank holiday stretches that. Never
     * before: the bank cannot book a payment that has not happened, and a
     * day's slack backwards would let yesterday's identical coffee settle
     * today's. Each
     * bank row settles at most one payment, the nearest in date, so two coffees
     * at the same price on two days are two coffees.
     *
     * If the payment was filed while it waited and the bank's row was not, the
     * category moves across: it is the same purchase.
     */
    /*
     * The merchant first, then the date.
     *
     * Day and amount alone cannot tell apart two card debits of the same
     * amount on the same day — a lunch and a bakery bill — and
     * whichever came first took the tap. So the taps are matched in two passes: first only to a bank
     * row whose label names the same shop, then, for the taps left over, to
     * the nearest row of that amount as before. A label rarely carries the
     * name Wallet shows, so the second pass is still most of the work; the
     * first is what stops it guessing wrong when it has a choice.
     *
     * A bank row still pending is enough: the tap is the same announcement,
     * and keeping both would list the payment twice under "en prévision".
    *
     * A refund is the exception to "never before".
     *
     * Money coming back is not a payment made at a till: the shop refunds when
     * it gets round to it, and the row is often typed in days later, from the
     * receipt or from noticing it. Its date is the day it was entered, not the
     * day the bank moved the money — which can be a week earlier, and was, so
     * the credit sat under "en prévision" for ever while the bank's own credit
     * stood beside it. A credit may therefore settle onto a bank row up to a
     * fortnight before it, and only in the pass where the labels name the same
     * shop. Debits keep the old rule: a payment cannot be booked before it is
     * made, and the same coffee at the same price a week earlier is a
     * different coffee.
     */
    @discardableResult
    static func settle(store: LocalStore) throws -> Int {
        let pending = try store.database.query(
            """
            SELECT id, account_id, amount, payee, substr(occurred_at, 1, 10) AS day, category_id
            FROM transactions
            WHERE source = ? AND deleted_at IS NULL
            ORDER BY occurred_at
            """,
            [.text(source)]
        )
        var claimed = Set<String>()
        var done = Set<String>()
        var settled = 0
        for byName in [true, false] {
            for row in pending {
                guard let id = row.string("id"), !done.contains(id),
                      let account = row.string("account_id"),
                      let amount = row.double("amount"), let day = row.string("day") else { continue }
                let candidates = try store.database.query(
                    """
                    SELECT id, category_id, normalized_payee FROM transactions
                    WHERE account_id = ? AND deleted_at IS NULL
                      AND source <> ? AND status = 'cleared'
                      AND abs(amount - ?) < 0.005
                      AND julianday(substr(occurred_at, 1, 10))
                          BETWEEN julianday(?) - ? AND julianday(?) + 7
                    ORDER BY abs(julianday(substr(occurred_at, 1, 10)) - julianday(?))
                    """,
                    [.text(account), .text(source), .real(amount), .text(day),
                     .real(byName && amount > 0 ? 14 : 0), .text(day), .text(day)]
                )
                let tap = row.string("payee") ?? ""
                guard let match = candidates.first(where: {
                    guard let candidate = $0.string("id") else { return false }
                    return !claimed.contains(candidate) && !isAlreadySettling(store, candidate)
                        && (!byName || namesAgree(tap, $0.string("normalized_payee") ?? ""))
                }), let bankId = match.string("id") else { continue }
                claimed.insert(bankId)
                done.insert(id)

                if match.string("category_id") == nil, let category = row.string("category_id") {
                    try store.database.run(
                        "UPDATE transactions SET category_id = ?, updated_at = datetime('now') WHERE id = ?",
                        [.text(category), .text(bankId)]
                    )
                }
                // The link stays on the retired payment, so this bank row is never
                // offered to a second one on a later sync.
                try store.database.run(
                    """
                    UPDATE transactions
                    SET deleted_at = datetime('now'), merge_suggested_tx_id = ?
                    WHERE id = ?
                    """,
                    [.text(bankId), .text(id)]
                )
                settled += 1
            }
        }
        return settled
    }

    /// Whether a bank label names the shop Wallet named: a word of four
    /// letters or more in common. "Le Comptoir" is in "ACHAT CB SARL LE
    /// COMPTOIR"; it is not in "ACHAT CB CHEZ ROSA".
    static func namesAgree(_ tap: String, _ label: String) -> Bool {
        LocalLedger.namesAgree(tap, label, whenUnsure: false)
    }

    /*
     * Card payments a bank sync took for its own rows.
     *
     * Until the sync learnt to leave taps to `settle`, it adopted them: the
     * bank's key moved onto the tap, which kept the name Wallet gave it and
     * the `scheduled` status — so a booked debit read "Prévu" for good, and
     * where two debits shared an amount the name could land on the wrong one.
     * Such a row is put back as `settle` would have left it: cleared, under
     * the bank's own label, which the key still carries when the bank gave no
     * stable reference ("<account>:<date>:<amount>:<label>").
     */
    @discardableResult
    static func repairAdopted(store: LocalStore) throws -> Int {
        let rows = try store.database.query(
            """
            SELECT id, external_id FROM transactions
            WHERE source = 'enable_banking' AND status = 'scheduled'
              AND is_pending = 0 AND deleted_at IS NULL
            """
        )
        for row in rows {
            guard let id = row.string("id") else { continue }
            if let label = bankLabel(inKey: row.string("external_id") ?? "") {
                try store.database.run(
                    """
                    UPDATE transactions
                    SET status = 'cleared', payee = ?, normalized_payee = ?, updated_at = datetime('now')
                    WHERE id = ?
                    """,
                    [.text(label), .text(LocalLedger.normalize(label)), .text(id)]
                )
            } else {
                try store.database.run(
                    "UPDATE transactions SET status = 'cleared', updated_at = datetime('now') WHERE id = ?",
                    [.text(id)]
                )
            }
        }
        return rows.count
    }

    /// The label at the end of a reference-less bank key, if that is its shape.
    static func bankLabel(inKey key: String) -> String? {
        let pattern = #"^[^:]+:\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z:-?[0-9.]+:(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let hit = regex.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)),
              let range = Range(hit.range(at: 1), in: key) else { return nil }
        let label = key[range].trimmingCharacters(in: .whitespaces)
        return label.isEmpty ? nil : label
    }

    /// A bank row that already replaced an earlier payment is not free to
    /// replace another.
    private static func isAlreadySettling(_ store: LocalStore, _ bankId: String) -> Bool {
        (try? store.database.scalar(
            "SELECT 1 FROM transactions WHERE source = ? AND merge_suggested_tx_id = ? LIMIT 1",
            [.text(source), .text(bankId)]
        )) != nil
    }
}
