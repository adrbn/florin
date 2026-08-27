import Foundation

/// The account kinds the ledger actually uses.
///
/// Taken from the four values present in a real Florin database rather than
/// invented for this screen, so an account created on the phone is the same
/// shape as one created anywhere else.
enum AccountKind: String, CaseIterable {
    case checking
    case savings
    case broker = "broker_portfolio"
    case loan

    var label: String {
        switch self {
        case .checking: "Courant"
        case .savings: "Épargne"
        case .broker: "Titres"
        case .loan: "Prêt"
        }
    }

    var emoji: String {
        switch self {
        case .checking: "🏦"
        case .savings: "🐖"
        case .broker: "📈"
        case .loan: "🎓"
        }
    }

    /// A loan is money owed, so its balance is negative however it was typed.
    /// Getting this wrong on day one puts someone's net worth out by twice the
    /// loan, which is the kind of first impression an app does not recover from.
    func signed(_ balance: Double) -> Double {
        self == .loan ? -abs(balance) : balance
    }
}

/// Writes what the onboarding collected into the device's ledger.
enum LocalOnboarding {
    /// Recorded in `settings` next to the seed marker, for the same reason:
    /// the answer to "has this person set up yet" belongs with the data, not
    /// beside it in preferences that outlive a deleted database.
    static let marker = "onboarded_at"

    /// Finish onboarding without creating an account.
    ///
    /// The bank path has nothing to write: the accounts and their balances
    /// arrive from the bank itself, and a placeholder would be a fictional
    /// account in a real ledger.
    static func markComplete() throws {
        guard let store = LocalStore.shared else { throw Failure.noStore }
        try store.database.run(
            "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
            [.text(marker), .text(ISO8601DateFormatter().string(from: Date()))]
        )
    }

    /// Adds an account without touching the onboarding marker — for the ones
    /// created later, from the app itself.
    static func createAccount(name: String, kind: AccountKind, balance: Double) throws {
        guard let store = LocalStore.shared else { throw Failure.noStore }
        let label = name.isEmpty ? kind.label : name
        let signed = kind.signed(balance)
        try store.database.run(
            """
            INSERT INTO accounts
                (id, name, kind, currency, current_balance, opening_balance, display_order)
            VALUES (?, ?, ?, 'EUR', ?, ?,
                    (SELECT coalesce(max(display_order) + 1, 0) FROM accounts))
            """,
            [
                .text(UUID().uuidString), .text(label), .text(kind.rawValue),
                .real(signed), .real(signed),
            ]
        )
    }

    static func createFirstAccount(name: String, kind: AccountKind, balance: Double) throws {
        guard let store = LocalStore.shared else { throw Failure.noStore }
        let label = name.isEmpty ? kind.label : name
        let signed = kind.signed(balance)

        try store.database.transaction {
            try store.database.run(
                """
                INSERT INTO accounts
                    (id, name, kind, currency, current_balance, opening_balance, display_order)
                VALUES (?, ?, ?, 'EUR', ?, ?, 0)
                """,
                [
                    .text(UUID().uuidString), .text(label), .text(kind.rawValue),
                    .real(signed), .real(signed),
                ]
            )
            try store.database.run(
                "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                [.text(marker), .text(ISO8601DateFormatter().string(from: Date()))]
            )
        }
    }

    /// True once someone has been through the flow on this device.
    static var isComplete: Bool {
        guard let store = LocalStore.shared else { return false }
        guard let value = try? store.database.scalar(
            "SELECT value FROM settings WHERE key = ?", [.text(marker)]
        ) else { return false }
        return value.string != nil
    }

    enum Failure: LocalizedError {
        case noStore
        var errorDescription: String? {
            "Florin could not open its database on this device."
        }
    }
}
