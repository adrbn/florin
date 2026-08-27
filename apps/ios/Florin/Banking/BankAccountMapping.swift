import Foundation

/// One account the bank exposes, and what it should become here.
///
/// Connecting a bank to a device that already holds a ledger is the moment two
/// sets of books meet. The bank calls the account "MR ROBINO ADRIEN"; the
/// server that seeded this device calls it "CCP". No name, no balance and no
/// identifier reliably links them, so guessing would silently produce two
/// accounts for the same money — and the second one would look right.
///
/// So it is asked, once, and the answer is remembered in `sync_external_id`.
struct DiscoveredAccount: Identifiable, Equatable {
    let uid: String
    let name: String
    let iban: String?
    let balance: Double
    let currency: String
    /// The local account this should attach to; nil means "create a new one".
    var target: String?

    var id: String { uid }

    /// The last four of the IBAN when there is one — the only thing on screen
    /// a person can actually match against their own bank app.
    var subtitle: String {
        if let iban, iban.count > 4 { return "•••• " + String(iban.suffix(4)) }
        return currency
    }
}

/// A local account offered as a target.
struct MappingCandidate: Identifiable, Equatable {
    let id: String
    let name: String
    let kind: String
    let balance: Double
}

extension BankingSync {
    /// What the session can see, before anything is written.
    static func discover(
        store: LocalStore,
        config: EnableBanking.Config,
        sessionId: String
    ) async throws -> [DiscoveredAccount] {
        let session = try await EnableBanking.session(config, id: sessionId)
        var found: [DiscoveredAccount] = []
        for uid in session.accounts ?? [] {
            let details = try await EnableBanking.accountDetails(config, uid: uid)
            let balance = (try? await EnableBanking.balances(config, uid: uid).preferred) ?? nil
            found.append(
                DiscoveredAccount(
                    uid: uid,
                    name: details.displayName,
                    iban: details.accountId?.iban,
                    balance: balance ?? 0,
                    currency: details.currency ?? "EUR",
                    target: nil
                )
            )
        }
        return found
    }

    /// Accounts already here that no bank is syncing yet.
    ///
    /// Anything already tied to a bank uid is left out: it is somebody else's
    /// account and offering it would invite attaching two banks to one row.
    static func candidates(store: LocalStore) throws -> [MappingCandidate] {
        try store.database.query(
            """
            SELECT id, name, kind, current_balance
            FROM accounts
            WHERE is_archived = 0
              AND (sync_external_id IS NULL OR sync_external_id LIKE 'server:%')
            ORDER BY display_order, name
            """
        ).map { row in
            MappingCandidate(
                id: row.string("id") ?? "",
                name: row.string("name") ?? "",
                kind: row.string("kind") ?? "checking",
                balance: row.double("current_balance") ?? 0
            )
        }
    }

    /// Attaches the chosen local accounts to their bank uid.
    ///
    /// After this the ordinary sync finds them by uid and updates in place, so
    /// the history the server seeded keeps its rows and the bank simply carries
    /// on from where it left off. Accounts left unmapped are created by the
    /// sync as new ones, which is the right outcome for a genuinely new one.
    static func applyMapping(
        store: LocalStore,
        accounts: [DiscoveredAccount],
        connectionId: String?
    ) throws {
        try store.database.transaction {
            for account in accounts {
                guard let target = account.target, !target.isEmpty else { continue }
                try store.database.run(
                    """
                    UPDATE accounts
                    SET sync_external_id = ?, sync_provider = 'enable_banking',
                        bank_connection_id = ?, updated_at = datetime('now')
                    WHERE id = ?
                    """,
                    [
                        .text(account.uid),
                        connectionId.map { SQLiteValue.text($0) } ?? .null,
                        .text(target),
                    ]
                )
            }
        }
    }
}
