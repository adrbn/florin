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
                        "\(connection.string("aspsp_name") ?? "?") : 0 compte exposé"
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
        var windows = [730, 365, 90]
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
                if try insert(transaction, store: store, accountId: accountId, uid: uid) {
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
        uid: String
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
        let date = day.count == 10 ? "\(day)T00:00:00Z" : day

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

        let payee = transaction.counterparty
        try store.database.run(
            """
            INSERT INTO transactions
                (id, account_id, occurred_at, amount, currency, payee, normalized_payee,
                 memo, source, external_id, status, needs_review, is_pending)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'enable_banking', ?, 'cleared', 1, ?)
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
