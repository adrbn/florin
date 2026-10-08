import Foundation

/// Mirrors of the v2 view models the server already serialises.
///
/// Field names match `packages/core/src/components/v2/types.ts` and the query
/// layer's result types exactly, so the JSON decodes without a key strategy and
/// a rename on either side fails loudly at decode time rather than silently
/// rendering a zero.
struct Overview: Decodable, Sendable {
    let generatedAt: String
    let locale: String
    /// The v2 dictionary for `locale`, English underneath.
    let strings: [String: String]
    let lastSyncedAt: String?
    let bankSyncConfigured: Bool
    let currency: String
    let netWorth: NetWorth
    let monthlyTrend: Double
    let series: [PatrimonyPoint]
    /// Assets only, with the loan added back at every date.
    let grossSeries: [PatrimonyPoint]?
    /// Assets minus the debt *as it stood then*, not as it stands today.
    let netSeries: [PatrimonyPoint]?
    let leftToSpend: LeftToSpend
    let burnThisMonth: Double
    let burnAvg6: Double
    let savings: SavingsRates
    let allocation: Allocation
    let goal: Goal?
    let reviewCount: Int
    /// This month's salary has not landed; the income figure is last month's. 
    let incomeIsEstimated: Bool
    let accounts: [Account]
    let categories: [Category]
    let recent: [Transaction]

    var t: Strings { Strings(strings, localeTag: localeTag) }

    var lastSynced: Date? {
        guard let lastSyncedAt else { return nil }
        return Timestamp.parse(lastSyncedAt)
            ?? ISO8601DateFormatter.florinNoFraction.date(from: lastSyncedAt)
    }

    /// BCP-47 tag for the formatters; the server sends the short app locale.
    /// The same table as the rest of the app: a switch of its own here knew
    /// only French and Dutch, so Italian, Spanish, Catalan, German and
    /// Portuguese read their months in English and their amounts the American way.
    var localeTag: String { Strings.tag(for: locale) }
}

struct NetWorth: Decodable, Sendable {
    let gross: Double
    let liability: Double
    let net: Double
    let netMonthAgo: Double?
}

struct PatrimonyPoint: Decodable, Sendable, Identifiable {
    let date: String
    let balance: Double
    var projected: Bool?

    var id: String { date }
    var day: Date { PatrimonyPoint.parser.date(from: String(date.prefix(10))) ?? .distantPast }

    nonisolated(unsafe) private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

struct LeftToSpend: Decodable, Sendable {
    let salaryCategoryName: String?
    let monthIncome: Double
    let monthSpent: Double
    let monthSpentFixed: Double
    let expectedMonthlySpend: Double
    /// The fixed part of a typical month, over complete months. Bills land
    /// whichever day the bank chooses but always land, so the projection
    /// carries the whole expected amount rather than a prorated share.
    /// Optional: a server that predates the field falls back to zero.
    var expectedMonthlyFixed: Double?
    /// What comes back in a usual month: six months of gross spending minus
    /// six of net. The forecast projects it rather than assuming no refund
    /// will land after today. Optional, like the fixed prior.
    var expectedMonthlyRefunds: Double?
    /// What was left over at this same day of the previous month, measured the
    /// same way — the month's salary counted whether or not it had landed by
    /// then, because a payslip arriving on the 29th would otherwise make the
    /// 28th of that month look like a catastrophe.
    /// What has actually been kept this month: income minus spending NET of
    /// reimbursements. `leftToSpend` counts gross on purpose — a refund should
    /// not erase a purchase from a ceiling meant to restrain you — and that
    /// same choice makes it the wrong number for saving: a month with 986 € of
    /// reimbursements read +298 € kept where the accounts had gained 1 284 €.
    /// Reimbursements already received this month — gross spending minus net.
    /// Kept apart because a ceiling should not forgive a refunded purchase
    /// while a margin must: the money really did come back.
    var monthRefunds: Double?
    var savedThisMonthToDate: Double?
    var savedPrevMonthToDate: Double?
    let leftToSpend: Double
    let dailyAvgSpent: Double
    let dailyBudgetRemaining: Double?
    let daysElapsed: Int
    let daysRemaining: Int
}

struct SavingsRates: Decodable, Sendable {
    let threeMonth: Double?
    let sixMonth: Double?
    let twelveMonth: Double?
}

struct Allocation: Decodable, Sendable {
    let cash: Double
    let invested: Double
    let loans: Double
}

struct Goal: Decodable, Sendable {
    let target: Double
    let currentValue: Double
    let monthsToReach: Int?
    let reachDateIso: String?
    let contributed: Double
    let marketGrowth: Double
}

struct Account: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let kind: String
    let institution: String?
    let balance: Double
    let marketValue: Double
    let total: Double
    let netContribution: Double
    let debt: Double?
    /*
     * The contract behind the debt.
     *
     * `debt` is the server's answer at the moment it was asked, and it freezes
     * the instant it is copied. These four are what let the device walk the
     * schedule itself, so a repayment recorded here moves the figure instead of
     * leaving it where the last import found it.
     */
    var loanOriginalPrincipal: Double?
    var loanInterestRate: Double?
    var loanTermMonths: Int?
    var loanMonthlyPayment: Double?
    let isIncludedInNetWorth: Bool
    let isArchived: Bool
    let displayIcon: String?
    /// Whether a bank keeps this one up to date. Optional because the server
    /// feed does not send it, and absent is not the same as false.
    let isSynced: Bool?

    var isLoan: Bool { kind == "loan" }
    /// What the row should print: a loan shows its amortized debt, negative.
    var displayValue: Double { isLoan ? -(debt ?? total) : total }
}

struct Category: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let emoji: String?
    let groupName: String
    /*
     * The loan this category mirrors.
     *
     * Filing a repayment here is what tells the ledger the debt moved. Without
     * it a device holding its own copy has no way to know which category
     * carries that meaning, so the money left the current account and the loan
     * sat exactly where it was — every instalment widening the gap.
     */
    var linkedLoanAccountId: String?
    /*
     * Optional because older servers do not send it.
     *
     * A device that keeps its own copy of the ledger cannot tell Revenus from
     * Courses by name, and rebuilding every group as an expense makes salaries
     * count as negative spending. Where it is missing the import falls back to
     * asking the plan which groups are expenses — everything else is income.
     */
    let groupKind: String?
}

/// What the phone posts back to record a transaction.
/// Money moved between two of the user's own accounts.
///
/// Not a transaction with a sign — two rows sharing a pair id, which is what
/// makes every "is this spending?" query answer no without being taught a new
/// rule. Recording one on the account a bank also syncs is deliberate: the
/// real row arrives later and absorbs this one, the same way a settled charge
/// absorbs the authorisation it replaces.
struct NewTransfer: Encodable, Sendable {
    let fromAccountId: String
    let toAccountId: String
    /// Always positive; the two legs take their own signs.
    let amount: Double
    let occurredAt: String
    let memo: String?
}

struct NewTransaction: Encodable, Sendable {
    let accountId: String
    /// Signed: the expense/income toggle decides, never the server.
    let amount: Double
    let payee: String
    let occurredAt: String
    let memo: String?
    let categoryId: String?
    /// Not at the bank yet: kept under "upcoming" until the bank's own row
    /// replaces it (`LocalWallet.settle`). Device ledger only, never encoded.
    var upcoming = false
    /// L'échéancier dont elle fait partie. Comme `upcoming`, il ne quitte
    /// jamais l'appareil : le serveur n'a pas cette notion.
    var instalmentPlanId: String?

    private enum CodingKeys: String, CodingKey {
        case accountId, amount, payee, occurredAt, memo, categoryId
    }
}

/*
 * Un achat réparti sur plusieurs mois.
 *
 * Ce n'est pas une opération : c'est ce qu'il faut pour en écrire plusieurs,
 * et le prix d'achat y figure en plus des échéances parce que lui seul dit ce
 * que les frais coûtent vraiment (voir `LocalInstalments.annualRate`).
 */
struct InstalmentPlan: Sendable {
    let accountId: String
    let payee: String
    /// Le prix affiché en magasin, positif.
    let purchase: Double
    /// Ce qui sera prélevé, mois après mois, la première à la date d'achat.
    let instalments: [Double]
    let first: Date
    let memo: String?
    let categoryId: String?
}

struct Transaction: Decodable, Sendable, Identifiable {
    let id: String
    let date: String
    let amount: Double
    let payee: String
    let memo: String?
    let categoryName: String?
    let categoryEmoji: String?
    let accountName: String
    let isTransfer: Bool
    let needsReview: Bool
    let isPending: Bool
    let isScheduled: Bool
    /*
     * The ids behind the two names above.
     *
     * A row carried `accountName` and `categoryName` because that is all a
     * list has to draw. The edit sheet has to *preselect* them, and a name
     * cannot be put back into a picker whose values are ids — two accounts
     * may share a name, and matching on one would move money between them.
     *
     * Optional and last, so the server can leave them out and the four places
     * that build a row by hand need not all be touched at once. The device
     * ledger fills them in.
     */
    var accountId: String?
    var categoryId: String?

    /// L'échéancier dont cette ligne est une échéance, s'il y en a un.
    /// Vide pour tout le reste, c'est-à-dire pour presque tout.
    var instalmentPlanId: String?

    /*
     * Le genre du compte, parce que le signe ne veut pas dire la même chose
     * sur un passif.
     *
     * Sur un compte courant, +165,13 € est une rentrée, et le vert le dit
     * bien. Sur un prêt, la même ligne est la mensualité qui ronge la dette :
     * la lire comme un encaissement, c'est croire qu'on a été remboursé alors
     * qu'on a remboursé. Le grand livre garde les deux faces et leurs signes —
     * c'est ce qui fait bouger les deux soldes — mais l'affichage a besoin de
     * savoir sur quel genre de compte il écrit.
     */
    var accountKind: String?

    /// Une mensualité vue depuis le prêt : elle fait baisser la dette, elle
    /// n'entre pas d'argent.
    var isDebtRepayment: Bool { accountKind == "loan" && amount > 0 }

    /// Une échéance d'un achat payé en plusieurs fois — à distinguer d'une
    /// opération simplement annoncée : la banque n'a rien promis, c'est vous
    /// qui savez qu'elle viendra.
    var isInstalment: Bool { instalmentPlanId != nil }

    /// The same row, marked reviewed — for optimistic bulk approval.
    func approved() -> Transaction {
        Transaction(
            id: id, date: date, amount: amount, payee: payee, memo: memo,
            categoryName: categoryName, categoryEmoji: categoryEmoji,
            accountName: accountName, isTransfer: isTransfer,
            needsReview: false, isPending: isPending, isScheduled: isScheduled,
            accountId: accountId, categoryId: categoryId,
            instalmentPlanId: instalmentPlanId, accountKind: accountKind
        )
    }

    /*
     * Announced, not settled — whatever the bank calls it.
     *
     * La Banque Postale publishes a direct debit days ahead without marking it
     * pending, so trusting the status alone left tomorrow's 165.13 sitting in
     * the list as though it had already gone. A date after today is the fact
     * that settles it: it has not happened.
     */
    var isUpcoming: Bool { isUpcoming(among: OwnAccounts.shared.numbers()) }

    /// La même question, posée à une liste donnée — ce que les tests
    /// interrogent, et ce que peut réutiliser qui pèse plusieurs lignes
    /// d'affilée sans relire les comptes à chaque fois.
    func isUpcoming(among numbers: Set<String>) -> Bool {
        isPending || isAnnounced(among: numbers)
            || day > Calendar(identifier: .gregorian).startOfDay(
                for: Date().addingTimeInterval(86_400)
            )
    }

    /*
     * Annoncée, et toujours pas comptabilisée.
     *
     * La date d'une annonce est celle que la banque promet, pas celle où elle
     * tient parole : un salaire annoncé pour le 28 quittait « en prévision »
     * à 00:00 ce jour-là et la banque ne l'a passé qu'à 23:31. Vingt-trois
     * heures où l'app affirmait un mouvement qui n'avait pas eu lieu, sur la
     * seule foi du calendrier.
     *
     * Ce qu'une banque n'a pas encore comptabilisé, elle ne sait pas le
     * nommer : elle n'a pas de contrepartie, alors elle nomme la ligne
     * d'après le compte d'arrivée — « FR76… DUPONT ». Le libellé est donc
     * l'aveu, et il tombe au moment exact de la comptabilisation, quand la
     * banque le remplace par le vrai payeur. On compare des numéros de
     * compte, pas des noms, pour qu'un virement écrit à la main « vers
     * Livret A » ne s'y trompe pas.
     */
    var isAnnounced: Bool { isAnnounced(among: OwnAccounts.shared.numbers()) }

    func isAnnounced(among numbers: Set<String>) -> Bool {
        OwnAccounts.named(by: payee, among: numbers)
    }

    /*
     * Four shapes, one date.
     *
     * The server sends ISO-8601; SQLite's own `datetime('now')` writes
     * "2026-08-06 00:00:00" with a space and no zone, and a ledger can hold a
     * bare "2026-08-06". Only the ISO forms were parsed, so anything written
     * by the device itself fell through to `.distantPast` and rendered as
     * "1 janv. 1" — a row correct in every other respect, dated two thousand
     * years ago.
     */
    var day: Date {
        ISO8601DateFormatter.florin.date(from: date)
            ?? ISO8601DateFormatter.florinNoFraction.date(from: date)
            ?? Transaction.plain.date(from: date)
            ?? Transaction.dayOnly.date(from: String(date.prefix(10)))
            ?? .distantPast
    }

    nonisolated(unsafe) private static let plain: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    nonisolated(unsafe) private static let dayOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

extension ISO8601DateFormatter {
    nonisolated(unsafe) static let florin: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) static let florinNoFraction = ISO8601DateFormatter()
}

/*
 * Two ways a timestamp gets into this ledger, and both have to read.
 *
 * A server sends ISO-8601 — "2026-08-29T07:15:00Z". SQLite's own
 * `datetime('now')` writes "2026-08-29 07:15:00": a space instead of the T, no
 * zone, and no ISO parser accepts it. Rows written by the phone were therefore
 * unreadable by the phone, silently: the background refresh asks when it last
 * synced to decide whether to sync again, got nil every time, and so never
 * skipped — spending unattended bank calls it had already spent.
 *
 * New writes use `Timestamp.now()`. This reads either, because every row
 * written before that is still in the old shape.
 */
enum Timestamp {
    /// Now, in the one format everything here can read back.
    static func now() -> String {
        ISO8601DateFormatter.florinNoFraction.string(from: Date())
    }

    /// A stored timestamp, whichever of the two shapes it is in.
    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let date = ISO8601DateFormatter.florin.date(from: value) { return date }
        if let date = ISO8601DateFormatter.florinNoFraction.date(from: value) { return date }
        // SQLite's own, read as UTC — which is what datetime('now') produces.
        return sqlite.date(from: value)
    }

    private nonisolated(unsafe) static let sqlite: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
}
