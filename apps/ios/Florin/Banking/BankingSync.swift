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
    /// - Parameter pending: also ask for transactions the bank has received
    ///   but not yet booked. One extra call per account, so it is left to the
    ///   caller: worth it when someone is watching and waiting for a payment,
    ///   not worth it for a scheduled pull in the middle of the night.
    /// - Parameter trigger: who asked — `manual`, `scheduler` or `initial`.
    ///   Recorded so a sync that found nothing can be told apart from one that
    ///   never ran.
    static func run(
        store: LocalStore,
        config: EnableBanking.Config,
        pending: Bool = true,
        trigger: String = "manual"
    ) async throws -> Result {
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

            /*
             * The run is opened before the first network call.
             *
             * The two tables this writes have been in the schema since the
             * start and nothing on the phone ever filled them, which is why
             * "the bank shows it and Florin does not" could only ever be
             * answered by reasoning. A row per run, a row per account, and the
             * question becomes a query.
             *
             * Opened up-front rather than written at the end, so a sync that
             * dies — a crash, a killed background task, a bank that never
             * answers — leaves evidence that it was tried at all.
             */
            let runId = UUID().uuidString
            let startedAt = Date()
            try? store.database.run(
                """
                INSERT INTO bank_sync_runs
                    (id, connection_id, trigger, started_at, status)
                VALUES (?, ?, ?, ?, 'running')
                """,
                [
                    .text(runId), .text(connectionId), .text(trigger),
                    .text(Timestamp.now()),
                ]
            )
            var accountsOk = 0
            var accountsTotal = 0

            do {
                let session = try await EnableBanking.session(config, id: sessionId)
                let uids = session.accounts ?? []
                accountsTotal = uids.count
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
                    /*
                     * One account failing is not the sync failing.
                     *
                     * A bank that answers for the current account and refuses
                     * for the savings one used to abort the whole run at the
                     * first refusal, so the accounts after it in the list were
                     * never even tried. Each is recorded on its own row and the
                     * run carries on.
                     */
                    let line = UUID().uuidString
                    do {
                        let accountId = try await upsertAccount(
                            store: store, config: config, uid: uid, connectionId: connectionId
                        )
                        result.accounts += 1
                        let counts = try await importTransactions(
                            store: store, config: config, uid: uid, accountId: accountId,
                            since: connection.string("sync_start_date"), pending: pending
                        )
                        result.inserted += counts.inserted
                        result.skipped += counts.skipped
                        accountsOk += 1
                        try? store.database.run(
                            """
                            INSERT INTO bank_sync_account_results
                                (id, run_id, account_uid, account_id, balance_fetched,
                                 tx_fetched, tx_inserted)
                            VALUES (?, ?, ?, ?, 1, ?, ?)
                            """,
                            [
                                .text(line), .text(runId), .text(uid), .text(accountId),
                                .integer(Int64(counts.inserted + counts.skipped)),
                                .integer(Int64(counts.inserted)),
                            ]
                        )
                    } catch {
                        result.failures.append("\(uid): \(error.localizedDescription)")
                        try? store.database.run(
                            """
                            INSERT INTO bank_sync_account_results
                                (id, run_id, account_uid, balance_fetched, tx_error)
                            VALUES (?, ?, ?, 0, ?)
                            """,
                            [
                                .text(line), .text(runId), .text(uid),
                                .text(error.localizedDescription),
                            ]
                        )
                    }
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

                /*
                 * A repayment that just arrived pays the loan now, not at the
                 * next launch. The month's instalment is the one transaction
                 * whose effect someone actively looks for after a sync.
                 */
                let repaid = try LocalLedger.reconcileLoanMirrors(store: store)
                if repaid > 0 {
                    log.notice("loan repayments recorded: \(repaid, privacy: .public)")
                }

                try store.database.run(
                    """
                    UPDATE bank_connections
                    SET last_synced_at = ?, last_sync_error = NULL,
                        updated_at = datetime('now')
                    WHERE id = ?
                    """,
                    [.text(Timestamp.now()), .text(connectionId)]
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

            /*
             * Close the run, whichever way it went.
             *
             * `partial` is the state worth having a word for: the sync reached
             * the bank and came back with some accounts and not others, which
             * looks like success from the outside and is the shape almost every
             * real complaint takes.
             */
            let status: String
            if accountsTotal == 0 {
                status = result.failures.isEmpty ? "ok" : "error"
            } else if accountsOk == accountsTotal {
                status = "ok"
            } else if accountsOk > 0 {
                status = "partial"
            } else {
                status = "error"
            }
            try? store.database.run(
                """
                UPDATE bank_sync_runs
                SET finished_at = ?, status = ?, accounts_total = ?, accounts_ok = ?,
                    tx_inserted = ?, error_summary = ?, duration_ms = ?
                WHERE id = ?
                """,
                [
                    .text(Timestamp.now()), .text(status),
                    .integer(Int64(accountsTotal)), .integer(Int64(accountsOk)),
                    .integer(Int64(result.inserted)),
                    result.failures.isEmpty
                        ? .null
                        : .text(result.failures.joined(separator: " · ")),
                    .integer(Int64(Date().timeIntervalSince(startedAt) * 1000)),
                    .text(runId),
                ]
            )
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
        since: String?,
        pending: Bool
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

        /*
         * What has arrived but is not yet written down.
         *
         * A balance is live and a statement is not: an instant transfer credits
         * the account the second it lands, while the line describing it appears
         * only once the bank books it — that evening, or the next working day.
         * Until then the money is visible as a total and invisible as an event,
         * which reads exactly like a bug.
         *
         * Asking for it explicitly is the only way to see it early, because the
         * API returns booked entries unless told otherwise. Best effort in both
         * directions: plenty of banks publish nothing here, and a bank that
         * refuses the question must not fail a sync that has already succeeded.
         */
        if pending {
            do {
                let waiting = try await EnableBanking.transactions(
                    config, uid: uid, from: from, to: to, status: "PDNG"
                )
                for transaction in waiting.transactions {
                    if try insert(
                        transaction, store: store, accountId: accountId,
                        uid: uid, adopted: &adopted
                    ) {
                        inserted += 1
                    } else {
                        skipped += 1
                    }
                }
                log.notice("pending: \(waiting.transactions.count, privacy: .public) offered")
            } catch {
                log.notice("bank does not publish pending transactions")
            }
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
        let stable = transaction.transactionId
            ?? transaction.entryReference.flatMap {
                BankTransaction.isPositional($0) ? nil : $0
            }
        let reference = stable
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
         * when the names agree. The bank sends a counterparty ("Jean
         * Dupont") while the ledger holds the whole label ("VIREMENT INSTANTANE
         * DE Jean Dupont"), so one containing the other is the test.
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
              /*
               * A settled bank row is no longer off limits either.
               *
               * It was, on the reasoning that the bank had already spoken and
               * nothing should overwrite it. That held only while a reference
               * meant one transaction for ever. It does not: La Banque Postale
               * renumbers, this app has itself keyed rows two different ways,
               * and every re-identification of an already-written row arrived
               * here as a stranger and was filed as a second debit.
               *
               * Nothing is lost by allowing it. `adopted` keeps the match
               * one-to-one, so two genuine purchases of the same amount on the
               * same day still claim one row each; and a row whose twin never
               * comes back simply keeps the key it had.
               */
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
    /*
     * A transfer's mirror leg carries no category.
     *
     * The leg that lands against a loan is not spending — the spending is the
     * money leaving the current account, and the category belongs there. A
     * mirror that carries one cancels the row it mirrors in any query that
     * does not exclude transfer legs, and one of these had drifted onto
     * "Rent", which is not even the right bill.
     *
     * New mirrors are written without a category; these are the ones from
     * before that was true.
     */
    @discardableResult
    static func clearMirrorCategories(store: LocalStore) throws -> Int {
        let rows = try store.database.query(
            """
            SELECT t.id AS id
            FROM transactions t
            JOIN accounts a ON a.id = t.account_id
            WHERE a.kind = 'loan' AND t.deleted_at IS NULL
              AND t.amount > 0 AND t.category_id IS NOT NULL
              AND t.transfer_pair_id IS NOT NULL
            """
        )
        for row in rows {
            guard let id = row.string("id") else { continue }
            try store.database.run(
                "UPDATE transactions SET category_id = NULL WHERE id = ?", [.text(id)]
            )
        }
        return rows.count
    }

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

    /*
     * The same debit, written twice because the bank renamed it.
     *
     * On 28 August the loan instalment and the Orange bill were fetched and
     * keyed by their contents. On 1 September the same two came back carrying
     * La Banque Postale's entry references — "2026-08-31.0", "2026-08-31.1",
     * the row's rank in the day and nothing else — and were written again as
     * strangers. The plan then showed two mensualités for a month with one.
     *
     * Refusing positional references stops it happening again; this takes back
     * the four rows it already made. What identifies a pair here is not that
     * two rows look alike — two identical train tickets on one day are two
     * tickets — but that one of them is keyed by a scheme this app no longer
     * writes and the other is not. Genuine twins share a scheme, so they are
     * never touched.
     *
     * The survivor inherits the discarded row's transfer pairing, or a loan
     * mirror would be left attached to a row that no longer exists and the
     * debt would keep a step it never took.
     */
    private static func counterpartExists(
        _ store: LocalStore, pair: String, excluding id: String
    ) throws -> Bool {
        guard !pair.isEmpty else { return false }
        return try store.database.scalar(
            """
            SELECT 1 FROM transactions
            WHERE transfer_pair_id = ? AND id <> ? AND deleted_at IS NULL
            LIMIT 1
            """,
            [.text(pair), .text(id)]
        ) != nil
    }

    static func collapseRelabelledDuplicates(store: LocalStore) throws -> Int {
        let pairs = try store.database.query(
            """
            SELECT stale.id AS drop_id, stale.transfer_pair_id AS drop_pair,
                   kept.id AS keep_id, kept.transfer_pair_id AS keep_pair,
                   stale.account_id AS account_id
            FROM transactions stale
            JOIN transactions kept
              ON kept.account_id = stale.account_id
             AND kept.id <> stale.id
             AND kept.deleted_at IS NULL
             AND kept.source = 'enable_banking'
             AND abs(kept.amount - stale.amount) < 0.005
             AND substr(kept.occurred_at, 1, 10) = substr(stale.occurred_at, 1, 10)
             AND kept.external_id NOT GLOB
                 '*:[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].[0-9]*'
            WHERE stale.deleted_at IS NULL
              AND stale.source = 'enable_banking'
              AND stale.external_id GLOB
                  '*:[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].[0-9]*'
            ORDER BY stale.created_at
            """
        )

        var spent: Set<String> = []
        var touched: Set<String> = []
        var removed = 0
        for pair in pairs {
            guard let dropId = pair.string("drop_id"),
                  let keepId = pair.string("keep_id"),
                  !spent.contains(dropId), !spent.contains(keepId)
            else { continue }
            spent.insert(dropId)
            spent.insert(keepId)

            /*
             * The survivor takes the pairing that still means something.
             *
             * Having a pair id is not the same as having a counterpart: the
             * row kept here carries one whose other half was never written,
             * while the row being discarded is the one the loan mirror is
             * actually attached to. Comparing the ids alone would keep the
             * empty pairing and leave the mirror hanging off a deleted row.
             */
            if let inherited = pair.string("drop_pair"),
               try counterpartExists(store, pair: inherited, excluding: dropId),
               try !counterpartExists(
                   store, pair: pair.string("keep_pair") ?? "", excluding: keepId
               ) {
                try store.database.run(
                    "UPDATE transactions SET transfer_pair_id = ? WHERE id = ?",
                    [.text(inherited), .text(keepId)]
                )
            }
            try store.database.run(
                "UPDATE transactions SET deleted_at = datetime('now') WHERE id = ?",
                [.text(dropId)]
            )
            if let account = pair.string("account_id") { touched.insert(account) }
            removed += 1
        }
        for account in touched {
            try recomputeBalanceFromOpening(store: store, accountId: account)
        }
        return removed
    }
}
