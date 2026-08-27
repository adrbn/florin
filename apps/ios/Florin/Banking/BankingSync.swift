import Foundation
import OSLog

/// Pulling accounts and transactions from the bank into the device's ledger.
///
/// A port of `syncConnection()`: for each live connection, walk the session's
/// account UIDs, upsert the account, take its balance, then page through its
/// transactions. Idempotent by `(source, external_id)`, so running it twice
/// changes nothing — which matters more here than on a server, because a phone
/// will run it on every reopen.
enum BankingSync {
    private static let log = Logger(subsystem: "com.adrbn.florin", category: "banking-sync")

    struct Result {
        var accounts = 0
        var inserted = 0
        var skipped = 0
        var failures: [String] = []
    }

    @discardableResult
    static func run(store: LocalStore, config: EnableBanking.Config) async throws -> Result {
        var result = Result()

        let connections = try store.database.query(
            """
            SELECT id, session_id, aspsp_name, sync_start_date
            FROM bank_connections WHERE status = 'active'
            """
        )

        for connection in connections {
            guard let connectionId = connection.string("id"),
                  let sessionId = connection.string("session_id")
            else { continue }

            do {
                let session = try await EnableBanking.session(config, id: sessionId)
                let uids = session.accounts ?? []
                if uids.isEmpty {
                    /*
                     * Zero accounts is a real answer, not a failure.
                     *
                     * Some institutions expose consent but no account data over
                     * PSD2 — PayPal is the known one. Recording it as an error
                     * would have the user re-authorising forever; recording the
                     * count lets the UI say what actually happened.
                     */
                    result.failures.append(
                        Strings.device(
                            "v2.connect.noAccountsForBank",
                            "{bank} : 0 compte exposé",
                            ["bank": connection.string("aspsp_name") ?? "?"]
                        )
                    )
                }

                for uid in uids {
                    let accountId = try await upsertAccount(
                        store: store, config: config, uid: uid, connectionId: connectionId
                    )
                    result.accounts += 1
                    let counts = try await importTransactions(
                        store: store, config: config, uid: uid, accountId: accountId,
                        since: connection.string("sync_start_date")
                    )
                    result.inserted += counts.inserted
                    result.skipped += counts.skipped
                }

                /*
                 * Name what just arrived, from what is already here.
                 *
                 * Bank rows land uncategorised, which makes the review queue a
                 * list of raw labels — and leaves an upcoming debit saying
                 * nothing about what it is, when seeing that before it lands is
                 * most of the reason to look at it. The ledger already knows:
                 * this payee has been filed the same way for months.
                 */
                let dropped = try Self.collapseSettledDuplicates(store: store)
                if dropped > 0 {
                    log.notice("dropped \(dropped, privacy: .public) settled duplicates")
                }

                let named = try LocalCategoriser.backfill(store: store)
                if named > 0 { log.notice("categorised \(named, privacy: .public) rows") }

                try store.database.run(
                    """
                    UPDATE bank_connections
                    SET last_synced_at = datetime('now'), last_sync_error = NULL,
                        updated_at = datetime('now')
                    WHERE id = ?
                    """,
                    [.text(connectionId)]
                )
            } catch {
                // Kept on the row rather than only raised: the next screen the
                // user opens should be able to say why a bank is stale.
                try? store.database.run(
                    """
                    UPDATE bank_connections
                    SET last_sync_error = ?, updated_at = datetime('now') WHERE id = ?
                    """,
                    [.text(error.localizedDescription), .text(connectionId)]
                )
                result.failures.append(error.localizedDescription)
                log.error("sync failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return result
    }

    // MARK: - Accounts

    private static func upsertAccount(
        store: LocalStore,
        config: EnableBanking.Config,
        uid: String,
        connectionId: String
    ) async throws -> String {
        let details = try await EnableBanking.accountDetails(config, uid: uid)
        let balance = try await EnableBanking.balances(config, uid: uid).preferred ?? 0

        let existing = try store.database.scalar(
            "SELECT id FROM accounts WHERE sync_external_id = ?", [.text(uid)]
        )?.string

        if let existing {
            /*
             * The bank owns the balance, the user owns the name.
             *
             * Overwriting the name on every sync would undo a rename the moment
             * it was made — banks return things like "COMPTE CHEQUE 12345"
             * that nobody wants on their dashboard.
             */
            try store.database.run(
                """
                UPDATE accounts
                SET current_balance = ?, last_synced_at = datetime('now'),
                    updated_at = datetime('now')
                WHERE id = ?
                """,
                [.real(balance), .text(existing)]
            )
            return existing
        }

        let id = UUID().uuidString
        try store.database.run(
            """
            INSERT INTO accounts
                (id, name, kind, currency, current_balance, opening_balance,
                 sync_provider, sync_external_id, bank_connection_id, last_synced_at)
            VALUES (?, ?, ?, ?, ?, 0, 'enable_banking', ?, ?, datetime('now'))
            """,
            [
                .text(id), .text(details.displayName), .text(kind(for: details)),
                .text(details.currency ?? "EUR"), .real(balance),
                .text(uid), .text(connectionId),
            ]
        )
        return id
    }

    /// Enable Banking's `cash_account_type` follows ISO 20022: CACC is a
    /// current account, SVGS a savings one. Anything else is treated as
    /// current, which is the safer default — a savings account shown as
    /// current is a cosmetic error, the reverse hides money from the budget.
    private static func kind(for details: AccountDetails) -> String {
        switch details.cashAccountType {
        case "SVGS": "savings"
        default: "checking"
        }
    }

    // MARK: - Transactions

    private static func importTransactions(
        store: LocalStore,
        config: EnableBanking.Config,
        uid: String,
        accountId: String,
        since: String?
    ) async throws -> (inserted: Int, skipped: Int) {
        let calendar = Calendar(identifier: .gregorian)
        /*
         * Ninety days back, not "since we connected".
         *
         * `sync_start_date` defaults to the moment the connection was made, so
         * using it as the window meant the very first sync asked the bank for
         * today only — three transactions on an account with years of history.
         * The first pull takes everything the consent allows; later ones can
         * narrow, but never past the earliest row already held, or a gap opens
         * that nothing will ever fill.
         */
        _ = since
        let to = LocalQueries.dayFormatter.string(from: Date())

        var inserted = 0
        var skipped = 0
        /// Local rows already claimed in this run, so two bank rows cannot
        /// collapse onto one and quietly lose a transaction.
        var adopted: Set<String> = []
        var continuationKey: String?

        /*
         * Ask for everything, settle for what the bank gives.
         *
         * Ninety days was a guess dressed up as a limit. What a bank actually
         * exposes under one consent varies — some go back two years, some
         * refuse a window wider than a year outright, with an error rather
         * than a truncated answer. So the widest window is tried first and
         * narrowed only when it is refused: the ceiling ends up being the
         * bank's, which is the only real one, instead of ours.
         */
        /*
         * An account that already has history only needs what came after it.
         *
         * A ledger seeded from a server and then attached to a bank held both
         * copies of the same months: the server's rows and the bank's, keyed
         * differently, so nothing recognised them as the same money. Net worth
         * over thirty days read 4497 where it should read 1065 — roughly one
         * salary counted twice — and the curve grew spikes where a duplicated
         * credit landed.
         *
         * So the window starts at the newest row this account already holds,
         * minus a few days: banks book late, and re-reading a handful of
         * settled days is free because the external id makes it idempotent.
         * An account with nothing still gets everything.
         */
        let existing = try store.database.scalar(
            """
            SELECT max(occurred_at) FROM transactions
            WHERE account_id = ? AND deleted_at IS NULL
            """,
            [.text(accountId)]
        )?.string

        var windows = [730, 365, 90]
        if let existing, existing.count >= 10,
           let newest = LocalQueries.dayFormatter.date(from: String(existing.prefix(10))) {
            let days = calendar.dateComponents([.day], from: newest, to: Date()).day ?? 0
            windows = [max(days + 3, 3)]
            log.notice("account already holds history to \(existing.prefix(10), privacy: .public)")
        }
        var from = ""
        var firstPage: TransactionsResponse?
        var lastFailure: Error?

        while !windows.isEmpty {
            let days = windows.removeFirst()
            let start = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            from = LocalQueries.dayFormatter.string(from: start)
            do {
                firstPage = try await EnableBanking.transactions(
                    config, uid: uid, from: from, to: to
                )
                log.notice("history window accepted: \(days) days")
                break
            } catch {
                lastFailure = error
                log.notice("history window refused at \(days) days, narrowing")
            }
        }
        guard var page = firstPage else {
            throw lastFailure ?? EnableBanking.Failure.malformed
        }

        while true {
            for transaction in page.transactions {
                if try insert(
                    transaction, store: store, accountId: accountId,
                    uid: uid, adopted: &adopted
                ) {
                    inserted += 1
                } else {
                    skipped += 1
                }
            }
            continuationKey = page.continuationKey
            guard let key = continuationKey else { break }
            page = try await EnableBanking.transactions(
                config, uid: uid, from: from, to: to, continuationKey: key
            )
        }

        try recomputeBalanceFromOpening(store: store, accountId: accountId)
        return (inserted, skipped)
    }

    private static func insert(
        _ transaction: BankTransaction,
        store: LocalStore,
        accountId: String,
        uid: String,
        adopted: inout Set<String>
    ) throws -> Bool {
        guard let day = transaction.date else { return false }
        /*
         * A day is not a timestamp, and every screen here reads timestamps.
         *
         * Enable Banking books transactions on a date — "2026-08-26" — while
         * the rest of this app parses `occurred_at` as ISO-8601 with a time.
         * Stored raw, every imported row fell back to distantPast and printed
         * "1 janv. 1" under a real amount. Midnight UTC is the honest reading
         * of a booking date: the bank did not tell us the hour.
         */
        var date = day.count == 10 ? "\(day)T00:00:00Z" : day

        /*
         * Prefer the date the bank wrote in the label over the one it booked.
         *
         * The server already does this, which is exactly why the two sides
         * disagreed: it had the purchase on the 25th and the bank returned the
         * 26th. Reading the same date here makes the two agree at the source,
         * instead of widening the matching window until two genuinely
         * different purchases of the same amount start merging into one.
         */
        let label = ([transaction.counterparty]
            + (transaction.remittanceInformation ?? [])).joined(separator: " ")
        if let booked = LocalQueries.dayFormatter.date(from: String(date.prefix(10))),
           let real = TrueDate.extract(from: label, bookedAt: booked) {
            date = LocalQueries.dayFormatter.string(from: real) + "T00:00:00Z"
        }

        /*
         * The external id has to include the account.
         *
         * Some banks — La Banque Postale among them — number entries by their
         * position in the statement rather than by anything stable, so the same
         * reference can mean different rows on different accounts. Scoping the
         * key to the account is what stops one bank's counter colliding with
         * another's.
         */
        let reference = transaction.entryReference
            ?? "\(date):\(transaction.signedAmount):\(transaction.counterparty)"
        let externalId = "\(uid):\(reference)"

        let already = try store.database.scalar(
            "SELECT id FROM transactions WHERE source = 'enable_banking' AND external_id = ?",
            [.text(externalId)]
        )?.string
        guard already == nil else { return false }

        /*
         * The same row may already be here under someone else's name.
         *
         * The window deliberately re-reads a few settled days, on the grounds
         * that the external id makes re-insertion harmless. It does — for rows
         * this bank put here. A ledger seeded from a server holds those same
         * days keyed as "server:<id>", which no bank id will ever match, so
         * every sync re-inserted the overlap as new: yesterday's purchases
         * came back marked "à vérifier" days after they had been reviewed.
         *
         * Same account, same day, same amount is a match worth trusting inside
         * a window this small. The existing row is adopted — it keeps its
         * category and its reviewed state, and gains the bank id so the next
         * sync recognises it directly.
         */
        /*
         * Within a few days, not on the same day.
         *
         * The two sides date the same purchase differently: a server that
         * recorded the value date has "Casa E CO −26,68" on the 25th while the
         * bank, returning the booking date, has it on the 26th. Requiring an
         * exact day meant every such row was re-inserted as new and came back
         * unreviewed — twenty of them, on a server that had none left to
         * review.
         *
         * One day of tolerance, now that both sides read the date out of the
         * label the same way. Three was needed while they disagreed, and it
         * was too wide for someone who buys the same coffee at the same price
         * on consecutive days — those would have merged into one.
         */
        let bookedDay = String(date.prefix(10))
        /*
         * Amount and date narrow it down; the name decides.
         *
         * Two transfers of the same amount a day apart would otherwise be
         * indistinguishable — and a row whose label carries no date still
         * needs that day of tolerance. So candidates are gathered and then
         * judged: an exact date is trusted on its own, a neighbouring day only
         * when the names agree. The bank sends a counterparty ("Adrien
         * Robino") while the ledger holds the whole label ("VIREMENT INSTANTANE
         * DE Adrien Robino"), so one containing the other is the test.
         *
         * `adopted` stops two bank rows landing on the same local one, which
         * would silently drop a real transaction.
         */
        /*
         * A provisional row can be replaced, whoever wrote it.
         *
         * The search used to skip anything the bank had already written, on
         * the reasoning that a bank row is authoritative and should not be
         * overwritten. True of a settled one — and wrong about the case this
         * exists for: a bank announces a transfer under one reference while it
         * is pending and books it under another, so the settled version came
         * back as a second row and the salary appeared twice, once in "en
         * prévision" under its IBAN and once as itself. Anything still pending
         * or still dated ahead is provisional by definition and is exactly
         * what the arriving row supersedes.
         */
        let needle = LocalLedger.normalize(transaction.counterparty)
        let candidates = try store.database.query(
            """
            SELECT id, normalized_payee,
                   abs(julianday(substr(occurred_at, 1, 10)) - julianday(?)) AS drift
            FROM transactions
            WHERE account_id = ? AND deleted_at IS NULL
              AND abs(julianday(substr(occurred_at, 1, 10)) - julianday(?)) <= 1
              AND abs(amount - ?) < 0.005
              AND (source <> 'enable_banking' OR external_id IS NULL
                   OR is_pending = 1
                   OR substr(occurred_at, 1, 10) > date('now'))
            ORDER BY drift
            """,
            [
                .text(bookedDay),
                .text(accountId),
                .text(bookedDay),
                .real(transaction.signedAmount),
            ]
        )

        let match = candidates.first { row in
            guard let id = row.string("id"), !adopted.contains(id) else { return false }
            if (row.double("drift") ?? 1) < 0.5 { return true }
            guard !needle.isEmpty, let payee = row.string("normalized_payee"), !payee.isEmpty
            else { return false }
            return payee.contains(needle) || needle.contains(payee)
        }

        if let twin = match?.string("id") {
            adopted.insert(twin)
            /*
             * Settling is a change worth writing down.
             *
             * An authorisation becomes a booking with a real date and,
             * sometimes, a different amount — a restaurant adds the tip, a
             * fuel pump releases the hold. And a row parked outside the review
             * queue while it was unsettled has to enter it once it is real,
             * or it is filed away having never been looked at.
             */
            let nowPending = transaction.status == "PDNG"
            try store.database.run(
                """
                UPDATE transactions
                SET source = 'enable_banking', external_id = ?, is_pending = ?,
                    occurred_at = ?, amount = ?,
                    needs_review = CASE
                        WHEN is_pending = 1 AND ? = 0 THEN 1
                        ELSE needs_review
                    END,
                    updated_at = datetime('now')
                WHERE id = ?
                """,
                [
                    .text(externalId),
                    .integer(nowPending ? 1 : 0),
                    .text(date),
                    .real(transaction.signedAmount),
                    .integer(nowPending ? 1 : 0),
                    .text(twin),
                ]
            )
            return false
        }

        let bookedToday = LocalQueries.dayFormatter.string(from: Date())
        let upcoming = transaction.status == "PDNG" || String(date.prefix(10)) > bookedToday
        let payee = transaction.counterparty
        try store.database.run(
            """
            INSERT INTO transactions
                (id, account_id, occurred_at, amount, currency, payee, normalized_payee,
                 memo, source, external_id, status, needs_review, is_pending)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'enable_banking', ?, 'cleared', ?, ?)
            """,
            [
                .text(UUID().uuidString), .text(accountId), .text(date),
                .real(transaction.signedAmount),
                .text(transaction.transactionAmount?.currency ?? "EUR"),
                .text(payee), .text(LocalLedger.normalize(payee)),
                (transaction.remittanceInformation?.joined(separator: " ")).map {
                    $0.isEmpty ? SQLiteValue.null : .text($0)
                } ?? .null,
                .text(externalId),
                /*
                 * Not for review until it has happened.
                 *
                 * Keyed on the status alone this only covered what the bank
                 * flags as pending — and La Banque Postale publishes a direct
                 * debit for the 31st with no flag at all, so two rows dated in
                 * the future still sat in the queue asking to be checked. The
                 * date decides; they join when they are real.
                 */
                .integer(upcoming ? 0 : 1),
                .integer(transaction.status == "PDNG" ? 1 : 0),
            ]
        )
        return true
    }

    /// A bank-synced account's balance is what the bank says, so the opening
    /// balance is derived backwards from it rather than the other way round.
    private static func recomputeBalanceFromOpening(
        store: LocalStore,
        accountId: String
    ) throws {
        let balance = try store.database.scalar(
            "SELECT current_balance FROM accounts WHERE id = ?", [.text(accountId)]
        )?.double ?? 0
        let moved = try store.database.scalar(
            """
            SELECT coalesce(sum(amount), 0) FROM transactions
            WHERE account_id = ? AND deleted_at IS NULL AND status = 'cleared'
            """,
            [.text(accountId)]
        )?.double ?? 0
        try store.database.run(
            "UPDATE accounts SET opening_balance = ? WHERE id = ?",
            [.real(((balance - moved) * 100).rounded() / 100), .text(accountId)]
        )
    }
}

extension BankingSync {
    /*
     * Drop provisional rows the settled version left behind.
     *
     * Adoption only fires while both versions are in front of it. A transfer
     * announced under one reference and booked under another escaped that
     * window, and nothing would ever clear it: a bank stops returning a
     * pending entry once it settles, so the ghost sat in "en prévision" until
     * its date passed and then counted a second time in the balance.
     *
     * Same rule as adoption — same account, same amount to the cent, a day
     * apart at most — applied the other way round, and only ever removing the
     * provisional side. Run after a sync and at launch, because the ledger a
     * launch opens may already carry one from before the fix.
     */
    @discardableResult
    static func collapseSettledDuplicates(store: LocalStore) throws -> Int {
        let ghosts = try store.database.query(
            """
            SELECT p.id AS id
            FROM transactions p
            JOIN transactions s
              ON s.account_id = p.account_id
             AND s.id <> p.id
             AND s.deleted_at IS NULL
             AND s.is_pending = 0
             AND substr(s.occurred_at, 1, 10) <= date('now')
             AND abs(s.amount - p.amount) < 0.005
             AND abs(julianday(substr(s.occurred_at, 1, 10))
                     - julianday(substr(p.occurred_at, 1, 10))) <= 1
            WHERE p.deleted_at IS NULL
              AND p.source = 'enable_banking'
              AND (p.is_pending = 1 OR substr(p.occurred_at, 1, 10) > date('now'))
            """
        )
        for ghost in ghosts {
            guard let id = ghost.string("id") else { continue }
            try store.database.run(
                "UPDATE transactions SET deleted_at = datetime('now') WHERE id = ?",
                [.text(id)]
            )
        }
        return ghosts.count
    }
}
