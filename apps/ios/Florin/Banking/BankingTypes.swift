import Foundation

/// What Enable Banking sends back.
///
/// Deliberately partial: only the fields this app reads are decoded, because
/// every field declared here is a field that can break the whole response when
/// the API adds or renames something. Everything is optional for the same
/// reason — banks differ wildly in what they expose, and a missing IBAN should
/// cost one label, not the sync.

struct Aspsp: Decodable, Identifiable, Hashable {
    let name: String
    let country: String
    let logo: String?
    /// Which PSD2 features the bank actually exposes. A bank listing no
    /// transaction access is worth showing differently rather than letting
    /// someone connect it and find an empty ledger.
    let psuTypes: [String]?

    var id: String { "\(country):\(name)" }

    enum CodingKeys: String, CodingKey {
        case name, country, logo
        case psuTypes = "psu_types"
    }
}

struct AspspList: Decodable {
    let aspsps: [Aspsp]
}

struct StartAuthResponse: Decodable {
    let url: String
}

struct SessionResponse: Decodable {
    let sessionId: String?
    /// Account UIDs, however the API chose to spell them this time.
    let accounts: [String]?
    let accessValidUntil: String?
    let aspsp: Aspsp?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case accounts
        case accessValidUntil = "access_valid_until"
        case aspsp
    }

    /*
     * `accounts` arrives as bare uid strings, or as objects carrying one.
     *
     * The shared TypeScript types declare `ReadonlyArray<string>` and say so in
     * a comment — but La Banque Postale's real POST /sessions answered with
     * objects, and decoding stopped dead on it. Rather than pick a side and be
     * wrong for somebody's bank, take either: a string is the uid, an object is
     * asked for its `uid`. Anything else is skipped instead of failing the
     * whole session, because one unreadable entry should not cost the other
     * accounts.
     */
    private struct AccountRef: Decodable {
        let uid: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        accessValidUntil = try container.decodeIfPresent(String.self, forKey: .accessValidUntil)
        aspsp = try container.decodeIfPresent(Aspsp.self, forKey: .aspsp)

        if var list = try? container.nestedUnkeyedContainer(forKey: .accounts) {
            var uids: [String] = []
            while !list.isAtEnd {
                if let uid = try? list.decode(String.self) {
                    uids.append(uid)
                } else if let ref = try? list.decode(AccountRef.self) {
                    if let uid = ref.uid { uids.append(uid) }
                } else {
                    _ = try? list.decode(AnyIgnored.self)
                }
            }
            accounts = uids
        } else {
            accounts = nil
        }
    }
}

/// Consumes one element of unknown shape so an unkeyed container can move on.
private struct AnyIgnored: Decodable {
    init(from decoder: Decoder) throws {}
}

struct AccountDetails: Decodable {
    let uid: String?
    let name: String?
    let product: String?
    let currency: String?
    let accountId: AccountIdentifier?
    let usage: String?
    let cashAccountType: String?

    enum CodingKeys: String, CodingKey {
        case uid, name, product, currency, usage
        case accountId = "account_id"
        case cashAccountType = "cash_account_type"
    }

    struct AccountIdentifier: Decodable {
        let iban: String?
        let other: Other?

        struct Other: Decodable {
            let identification: String?
        }
    }

    /// What to call this account on screen, in the order a person would pick.
    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let product, !product.isEmpty { return product }
        if let iban = accountId?.iban, iban.count > 4 { return "•••• " + String(iban.suffix(4)) }
        return "Compte"
    }
}

struct BalancesResponse: Decodable {
    let balances: [Balance]

    struct Balance: Decodable {
        let name: String?
        let balanceAmount: Amount?
        let balanceType: String?

        enum CodingKeys: String, CodingKey {
            case name
            case balanceAmount = "balance_amount"
            case balanceType = "balance_type"
        }
    }

    struct Amount: Decodable {
        let amount: String?
        let currency: String?

        var value: Double { Double(amount ?? "") ?? 0 }
    }

    /*
     * Which balance is "the" balance.
     *
     * Banks return several and they disagree on purpose: CLBD is what has
     * settled, XPCD includes what is on its way, ITAV is what you can actually
     * spend. Preferring the interim available figure matches what the bank's
     * own app shows, which is the number the user will compare against.
     */
    var preferred: Double? {
        let order = ["ITAV", "XPCD", "CLBD"]
        for type in order {
            if let match = balances.first(where: { $0.balanceType == type }) {
                return match.balanceAmount?.value
            }
        }
        return balances.first?.balanceAmount?.value
    }
}

struct TransactionsResponse: Decodable {
    let transactions: [BankTransaction]
    let continuationKey: String?

    enum CodingKeys: String, CodingKey {
        case transactions
        case continuationKey = "continuation_key"
    }
}

struct BankTransaction: Decodable {
    let entryReference: String?
    let transactionAmount: BalancesResponse.Amount?
    let creditDebitIndicator: String?
    let bookingDate: String?
    let valueDate: String?
    let transactionDate: String?
    let creditorName: String?
    let debtorName: String?
    let remittanceInformation: [String]?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case entryReference = "entry_reference"
        case transactionAmount = "transaction_amount"
        case creditDebitIndicator = "credit_debit_indicator"
        case bookingDate = "booking_date"
        case valueDate = "value_date"
        case transactionDate = "transaction_date"
        case creditorName = "creditor_name"
        case debtorName = "debtor_name"
        case remittanceInformation = "remittance_information"
        case status
    }

    /// Signed the way this ledger stores money: out is negative.
    var signedAmount: Double {
        let magnitude = abs(transactionAmount?.value ?? 0)
        return creditDebitIndicator == "CRDT" ? magnitude : -magnitude
    }

    /// The date the money moved, preferring what the bank booked over what it
    /// valued — booking is what the user sees in their own app.
    var date: String? { bookingDate ?? transactionDate ?? valueDate }

    /// Who it was with. The counterparty depends on direction: for money going
    /// out it is the creditor, coming in it is the debtor.
    var counterparty: String {
        let name = creditDebitIndicator == "CRDT" ? debtorName : creditorName
        if let name, !name.isEmpty { return name }
        let remittance = (remittanceInformation ?? []).joined(separator: " ")
        return remittance.isEmpty ? "Opération" : remittance
    }
}
