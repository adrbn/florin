import Foundation
import Testing
import UIKit
@testable import Florin

/*
 * The device's own arithmetic, tested where it runs.
 *
 * 266 tests cover the web and the desktop; the phone had none, and the phone is
 * where the ledger actually lives. Two things shipped broken this week for
 * exactly that reason — an export no reader could open, and a recursive
 * initialiser that took the process down on the first import — and both were
 * found by hand-built harnesses that were thrown away afterwards. These are
 * those harnesses, kept.
 */

// MARK: - Reading statements

@Suite("Import")
struct ImportTests {
    private func rows(_ text: String, _ file: String = "releve.csv") throws -> [LocalImport.Row] {
        try LocalImport.parse(data: Data(text.utf8), fileName: file).rows
    }

    @Test("a French export: semicolons, comma decimals, spaced thousands")
    func french() throws {
        let parsed = try rows("""
        Date;Libellé;Montant
        28/08/2026;VIREMENT INSTANTANE CREDIT;13,00
        27/08/2026;ACHAT CB BOULANGERIE DU PARC;-4,50
        27/08/2026;VIREMENT SALAIRE EMPLOYEUR;2 500,00
        """)
        #expect(parsed.count == 3)
        #expect(parsed[0].day == "2026-08-28")
        #expect(parsed[0].amount == 13.00)
        #expect(parsed[2].amount == 2500.00)
    }

    @Test("separate debit and credit columns become one signed amount")
    func debitCredit() throws {
        let parsed = try rows("""
        Date opération;Libellé;Débit;Crédit
        15/07/2026;VERSEMENT LEP;;2 000,00
        02/08/2026;RETRAIT;150,50;
        """)
        #expect(parsed.map(\.amount) == [2000.00, -150.50])
    }

    @Test("a label containing the delimiter survives its quotes")
    func quoted() throws {
        let parsed = try rows("""
        Date;Libellé;Montant
        16/08/2026;"CARREFOUR MARKET; PARIS 11";-42,49
        """)
        #expect(parsed.count == 1)
        #expect(parsed[0].payee == "CARREFOUR MARKET; PARIS 11")
    }

    @Test("OFX in the unclosed-tag dialect most French banks emit")
    func ofx() throws {
        let parsed = try rows("""
        <OFX><BANKTRANLIST>
        <STMTTRN><TRNTYPE>DEBIT<DTPOSTED>20260817<TRNAMT>-33.98<NAME>DECATHLON
        <STMTTRN><TRNTYPE>CREDIT<DTPOSTED>20260828<TRNAMT>13.00<NAME>VIREMENT RECU
        </BANKTRANLIST></OFX>
        """, "releve.ofx")
        #expect(parsed.count == 2)
        #expect(parsed[0].day == "2026-08-17")
        #expect(parsed[1].amount == 13.00)
    }

    @Test("a lone date is read day-first, and an impossible one is refused")
    func dates() {
        #expect(LocalImport.date(from: "03/04/2026") == "2026-04-03")
        #expect(LocalImport.date(from: "13/04/2026") == "2026-04-13")
        #expect(LocalImport.date(from: "04/13/2026") == nil)
        #expect(LocalImport.date(from: "2026-08-28") == "2026-08-28")
        #expect(LocalImport.date(from: "20260828") == "2026-08-28")
    }

    @Test("the file decides which way round its dates are")
    func dateOrder() {
        #expect(LocalImport.order(of: ["03/04/2026", "28/08/2026"]) == .dayFirst)
        #expect(LocalImport.order(of: ["04/13/2026", "01/02/2026"]) == .monthFirst)
        // Everything under thirteen: nothing can tell, and it says so.
        #expect(LocalImport.order(of: ["03/04/2026", "01/02/2026"]) == .ambiguous)
        // The calendar refutes what the ">12" test alone would accept: there is
        // no thirty-first of February either way round.
        #expect(LocalImport.order(of: ["31/02/2026"]) == .inconsistent)
        // A statement reopened in Excel: some rows swapped, some left alone.
        #expect(LocalImport.order(of: ["28/08/2026", "04/13/2026"]) == .inconsistent)
    }

    @Test("two digits are a year in the past, not in 2099")
    func century() {
        #expect(LocalImport.century(26) == 2026)
        #expect(LocalImport.century(99) == 1999)
        #expect(LocalImport.century(2026) == 2026)
    }

    @Test("a row whose date will not read is counted, not quietly dropped")
    func rejected() throws {
        let parsed = try LocalImport.parse(
            data: Data("""
            Date;Libellé;Montant
            28/08/2026;VIREMENT;13,00
            pas-une-date;QUELQUE CHOSE;-4,50
            """.utf8),
            fileName: "releve.csv"
        )
        #expect(parsed.rows.count == 1)
        #expect(parsed.rejected == 1)
    }

    @Test("an American export is read the American way, not silently reversed")
    func american() throws {
        let parsed = try LocalImport.parse(
            data: Data("""
            Date,Description,Amount
            04/13/2026,Whole Foods,-52.10
            04/02/2026,Paycheck,2100.00
            """.utf8),
            fileName: "export.csv"
        )
        #expect(parsed.order == .monthFirst)
        // Without the file-wide decision this second row became 4 February.
        #expect(parsed.rows.map(\.day) == ["2026-04-13", "2026-04-02"])
    }

    @Test("a statement that opens with its account number still reads")
    func preamble() throws {
        // What a French bank actually sends: three lines that are not a table.
        let parsed = try rows("""
        Compte;N°0000000X000
        Solde au 28/08/2026;1 234,56
        Période;du 01/08/2026 au 28/08/2026

        Date;Libellé;Montant
        28/08/2026;VIREMENT INSTANTANE CREDIT;13,00
        27/08/2026;ACHAT CB BOULANGERIE DU PARC;-4,50
        """)
        #expect(parsed.count == 2)
        #expect(parsed[0].payee == "VIREMENT INSTANTANE CREDIT")
    }

    @Test("French numbers, including a trailing minus and a thin space")
    func numbers() {
        #expect(LocalImport.number("1 234,56") == 1234.56)
        #expect(LocalImport.number("-1.234,56") == -1234.56)
        #expect(LocalImport.number("42,49-") == -42.49)
        #expect(LocalImport.number("\u{202F}2 500,00") == 2500.00)
        #expect(LocalImport.number("") == nil)
    }

    @Test("an English number is not divided by a thousand")
    func englishNumbers() {
        // The first rule read the comma as decimal wherever it appeared, so
        // 1,234.56 came back as 1.23456 — every amount in a British or American
        // statement silently a thousandth of itself.
        #expect(LocalImport.number("1,234.56") == 1234.56)
        #expect(LocalImport.number("12,345.67") == 12345.67)
        #expect(LocalImport.number("-1,234.56") == -1234.56)
        // Three digits after the separator group thousands; one or two divide.
        #expect(LocalImport.number("1,234") == 1234)
        #expect(LocalImport.number("1.234") == 1234)
        #expect(LocalImport.number("1,23") == 1.23)
        #expect(LocalImport.number("1.23") == 1.23)
        // And the continental forms still read the continental way.
        #expect(LocalImport.number("1.234,56") == 1234.56)
        #expect(LocalImport.number("1 234,56") == 1234.56)
    }

    /*
     * Real header rows, taken from real exports.
     *
     * Four of the biggest French banks open a statement with an account number,
     * a balance and a period before the columns start, and La Banque Postale's
     * preamble contains a line that itself begins "Date" — which is why finding
     * the table takes two roles and not one.
     */
    @Test("La Banque Postale, whose preamble names a date three lines early")
    func banquePostale() throws {
        let parsed = try rows("""
        Numéro Compte    ;05345678900
        Type             ;CCP
        Compte tenu en   ;EUROS
        Date             ;01/01/2015
        Solde (EUROS)    ;1 234,56
        Solde (FRANCS)   ;8 098,45

        Date;Libellé;Montant(EUROS);Montant(FRANCS)
        28/08/2026;VIREMENT INSTANTANE CREDIT;13,00;85,27
        27/08/2026;ACHAT CB BOULANGERIE DU PARC;-4,50;-29,52
        """)
        #expect(parsed.count == 2)
        #expect(parsed[0].amount == 13.00)
    }

    @Test("Crédit Agricole: a download line, then débit and crédit columns")
    func creditAgricole() throws {
        let parsed = try rows("""
        Téléchargement du  19/03/2026;
        Date;Date valeur;Libellé;Débit Euros;Crédit Euros;
        15/03/2026;15/03/2026;VIREMENT SALAIRE;;2 500,00;
        16/03/2026;16/03/2026;CARTE INTERMARCHE;77,77;;
        """)
        #expect(parsed.map(\.amount) == [2500.00, -77.77])
    }

    @Test("Société Générale, whose amount column is not called montant alone")
    func societeGenerale() throws {
        let parsed = try rows("""
        ="0201900016400270";17/05/2026;16/11/2026;
        date_comptabilisation;libellé_complet_operation;montant_operation;devise;
        12/08/2026;CARTE X1234 DECATHLON;-33,98;EUR;
        """)
        #expect(parsed.count == 1)
        #expect(parsed[0].amount == -33.98)
    }

    @Test("N26 in French: Bénéficiaire, and Montant (EUR)")
    func n26() throws {
        let parsed = try rows("""
        Date,Bénéficiaire,Numéro de compte,Type de transaction,Montant (EUR),Montant (Devise étrangère)
        2026-08-16,Amazon Marketplace,DE123,Presentment,-49.99,
        """)
        #expect(parsed.count == 1)
        #expect(parsed[0].payee == "Amazon Marketplace")
        #expect(parsed[0].amount == -49.99)
    }

    @Test("a file with no date column is refused rather than half-read")
    func noDate() {
        #expect(throws: (any Error).self) {
            try rows("Libellé;Montant\nACHAT;-4,50")
        }
    }
}

// MARK: - Timestamps

@Suite("Timestamps")
struct TimestampTests {
    @Test("both shapes a row can be written in are readable")
    func bothShapes() {
        // What SQLite's own datetime('now') writes, and what every parser here
        // used to reject — silently, which is how the background refresh
        // stopped skipping.
        #expect(Timestamp.parse("2026-08-29 07:15:00") != nil)
        #expect(Timestamp.parse("2026-08-29T07:15:00Z") != nil)
        #expect(Timestamp.parse("2026-08-29T07:15:00.123Z") != nil)
        #expect(Timestamp.parse(nil) == nil)
        #expect(Timestamp.parse("") == nil)
    }

    @Test("what it writes, it can read")
    func roundTrip() {
        #expect(Timestamp.parse(Timestamp.now()) != nil)
    }
}

// MARK: - What is still owed

/*
 * An invented loan, and a reference worked out away from the code it checks:
 * 12 000 € over 84 months at 4,20 %, instalment 165,13 €, first payment
 * 31 March 2024. The remaining balance below comes from the closed-form
 * amortisation, computed outside this target — so a bug in `LocalLoan` cannot
 * quietly define its own expected answer.
 *
 * The phone reported this loan's debt as the sum of the repayments sitting on
 * the loan account — 3 543 € after twenty-six instalments, which is the money
 * already paid. The bank's capital restant dû at that point is a little over
 * seven thousand.
 */
@Suite("Loan")
struct LoanTests {
    private let principal = 12_000.0
    private let rate = 0.042
    private let term = 84
    private let payment = 165.13

    private func debt(after payments: Int) -> Double {
        LocalLoan.liability(
            principal: principal, annualRate: rate, termMonths: term,
            monthlyPayment: payment, paymentsMade: payments
        ).remainingDebt
    }

    @Test("the periodic rate is recovered from principal, payment and term")
    func calibration() {
        // The instalment was built from this rate, so the solver has to
        // hand it back — that round trip is the whole point of the method.
        let solved = LocalLoan.solveAnnualRate(
            principal: principal, monthlyPayment: payment, termMonths: term
        )
        #expect(solved != nil)
        #expect(abs((solved ?? 0) - 0.0420) < 0.0005)
        // And it reproduces the instalment it was solved from.
        let check = LocalLoan.monthlyPayment(
            principal: principal, annualRate: solved ?? 0, termMonths: term
        )
        #expect(abs(check - payment) < 0.01)
    }

    @Test("capital restant dû lands within a euro of the amortisation table")
    func matchesTheBank() {
        // 8 788,93 € after twenty-five instalments, by the closed form
        // B(k) = P(1+i)^k − m((1+i)^k − 1)/i, computed outside this target.
        // The server asserts the same figure, so the two builds agree by
        // construction rather than by coincidence.
        #expect(abs(debt(after: 25) - 8788.93) < 1)
    }

    @Test("what is owed is not what has been paid")
    func notTheAmountPaid() {
        // Twenty-six instalments of 165,13 € is 4 293,38 € handed over — the
        // number the phone used to print as the debt. The debt is more than
        // twice that.
        let paid = 26.0 * payment
        #expect(debt(after: 26) > 8_000)
        #expect(abs(debt(after: 26) - paid) > 3_500)
    }

    @Test("each instalment moves it, which is what validating one is for")
    func eachPaymentCounts() {
        let before = debt(after: 25)
        let after = debt(after: 26)
        #expect(after < before)
        // Early in a loan most of the instalment is interest, so the debt
        // falls by less than the 165,13 € paid.
        let step = before - after
        #expect(step > 100 && step < payment)
    }

    @Test("the loan closes on its contractual term")
    func closes() {
        #expect(debt(after: term) < 1)
    }

    @Test("a zero-interest loan solves to zero, an impossible one to nothing")
    func edges() {
        #expect(LocalLoan.solveAnnualRate(principal: 1200, monthlyPayment: 100, termMonths: 12) == 0)
        #expect(LocalLoan.solveAnnualRate(principal: 10_000, monthlyPayment: 50, termMonths: 12) == nil)
    }

    @Test("an unconfigured loan falls back rather than reporting zero owed")
    func unconfigured() {
        let l = LocalLoan.liability(
            principal: 0, annualRate: 0, termMonths: 0, monthlyPayment: 0,
            paymentsMade: 0, fallbackBalance: -2_400
        )
        #expect(l.remainingDebt == 2_400)
        #expect(!l.fromSchedule)
    }
}

// MARK: - Filing a repayment

@Suite("Loan mirror", .serialized)
struct LoanMirrorTests {
    /// A current account, a loan, and the category that mirrors it.
    private func ledger() throws -> (LocalStore, ccp: String, loan: String, category: String) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("florin-loan-\(UUID().uuidString).db")
        let store = try LocalStore(url: url)
        let ccp = UUID().uuidString, loan = UUID().uuidString
        let group = UUID().uuidString, category = UUID().uuidString
        try store.database.exec("""
        INSERT INTO category_groups (id, name, kind) VALUES ('\(group)', 'Charges', 'expense');
        INSERT INTO accounts (id, name, kind, currency) VALUES ('\(ccp)', 'CCP', 'checking', 'EUR');
        INSERT INTO accounts (id, name, kind, currency, loan_original_principal,
                              loan_interest_rate, loan_term_months, loan_monthly_payment,
                              loan_start_date)
          VALUES ('\(loan)', 'Prêt', 'loan', 'EUR', 12000, 0.042, 84, 165.13, '2024-03-31');
        INSERT INTO categories (id, group_id, name, linked_loan_account_id)
          VALUES ('\(category)', '\(group)', 'Remboursement du prêt', '\(loan)');
        """)
        return (store, ccp, loan, category)
    }

    private func payment(_ store: LocalStore, on account: String) throws -> String {
        let id = UUID().uuidString
        try store.database.run(
            """
            INSERT INTO transactions
                (id, account_id, occurred_at, amount, currency, payee, normalized_payee,
                 source, status, needs_review)
            VALUES (?, ?, '2026-08-05', -165.13, 'EUR', 'PRELEVEMENT CREDIT MAISON', 'prelevement credit maison',
                    'enable_banking', 'cleared', 1)
            """,
            [.text(id), .text(account)]
        )
        return id
    }

    private func mirrors(_ store: LocalStore, on loan: String) -> Int {
        ((try? store.database.scalar(
            "SELECT count(*) FROM transactions WHERE account_id = ? AND deleted_at IS NULL",
            [.text(loan)]
        )?.int) as? Int ?? -1) ?? -1
    }

    @Test("filing the instalment writes the other half on the loan")
    func writesTheMirror() throws {
        let (store, ccp, loan, category) = try ledger()
        let id = try payment(store, on: ccp)
        #expect(mirrors(store, on: loan) == 0)

        try LocalLedger.patch(store: store, id: id, TxPatch(categoryId: .some(category)))

        #expect(mirrors(store, on: loan) == 1)
        // Opposite sign, no category of its own — the plan sums spending by
        // category across accounts, so a categorised mirror would cancel the
        // instalment it represents.
        let row = try store.database.query(
            "SELECT amount, category_id, transfer_pair_id FROM transactions WHERE account_id = ?",
            [.text(loan)]
        ).first
        #expect(row?.double("amount") == 165.13)
        #expect(row?.string("category_id") == nil)
        #expect(row?.string("transfer_pair_id") != nil)
    }

    @Test("the remaining debt goes down, by the principal and not by the payment")
    func debtMoves() throws {
        let (store, ccp, loan, category) = try ledger()
        func debt() throws -> Double {
            try LocalQueries.readAccounts(store.database)
                .first { $0.id == loan }?.debt ?? -1
        }
        let before = try debt()
        try LocalLedger.patch(
            store: store, id: try payment(store, on: ccp), TxPatch(categoryId: .some(category))
        )
        let after = try debt()
        #expect(after < before)
        // Early in a loan most of the instalment is interest; the debt falls by
        // less than the 165,13 € handed over.
        #expect(before - after < 165.13)
        #expect(before - after > 90)
    }

    @Test("saying it was something else takes the step back")
    func undo() throws {
        let (store, ccp, loan, category) = try ledger()
        // Another category, so the ledger is being told plainly that this debit
        // is not the loan.
        let other = UUID().uuidString
        try store.database.run(
            """
            INSERT INTO categories (id, group_id, name)
            VALUES (?, (SELECT id FROM category_groups LIMIT 1), 'Courses')
            """,
            [.text(other)]
        )
        let id = try payment(store, on: ccp)
        try LocalLedger.patch(store: store, id: id, TxPatch(categoryId: .some(category)))
        #expect(mirrors(store, on: loan) == 1)

        try LocalLedger.patch(store: store, id: id, TxPatch(categoryId: .some(other)))
        #expect(mirrors(store, on: loan) == 0)
    }

    @Test("clearing the category leaves the amount to speak")
    func clearedStaysDetected() throws {
        let (store, ccp, loan, category) = try ledger()
        let id = try payment(store, on: ccp)
        try LocalLedger.patch(store: store, id: id, TxPatch(categoryId: .some(category)))
        // Unfiled is not "not the loan": the debit still matches the contract
        // to the cent, and the money still went there.
        try LocalLedger.patch(store: store, id: id, TxPatch(categoryId: .some(nil)))
        #expect(mirrors(store, on: loan) == 1)
    }

    @Test("a repayment filed before the mirror existed gets its counterpart")
    func reconcile() throws {
        let (store, ccp, loan, category) = try ledger()
        // Filed the way the categoriser files: straight into the column, with
        // no mirror — which is how every automatic repayment landed.
        let id = try payment(store, on: ccp)
        try store.database.run(
            "UPDATE transactions SET category_id = ? WHERE id = ?",
            [.text(category), .text(id)]
        )
        #expect(mirrors(store, on: loan) == 0)

        #expect(try LocalLedger.reconcileLoanMirrors(store: store) == 1)
        #expect(mirrors(store, on: loan) == 1)
        // And it does not do it again on the next launch.
        #expect(try LocalLedger.reconcileLoanMirrors(store: store) == 0)
    }

    @Test("the categoriser writes the mirror when it files a repayment itself")
    func categoriserMirrors() throws {
        let (store, ccp, loan, category) = try ledger()
        // A payee the ledger has filed before, so the categoriser is certain.
        for _ in 0..<6 {
            let past = try payment(store, on: ccp)
            try store.database.run(
                "UPDATE transactions SET category_id = ?, needs_review = 0 WHERE id = ?",
                [.text(category), .text(past)]
            )
        }
        _ = try LocalLedger.reconcileLoanMirrors(store: store)
        let fresh = try payment(store, on: ccp)
        _ = try LocalCategoriser.backfill(store: store)

        let filed = try store.database.scalar(
            "SELECT category_id FROM transactions WHERE id = ?", [.text(fresh)]
        )?.string
        #expect(filed == category)
        // Seven repayments, seven counterparts.
        #expect(mirrors(store, on: loan) == 7)
    }

    @Test("an instalment is recognised by its amount, with no category at all")
    func detectedByAmount() throws {
        let (store, ccp, loan, _) = try ledger()
        // Never categorised, never linked — just a debit matching the contract.
        _ = try payment(store, on: ccp)
        #expect(mirrors(store, on: loan) == 0)

        #expect(try LocalLedger.reconcileLoanMirrors(store: store) == 1)
        #expect(mirrors(store, on: loan) == 1)
    }

    @Test("a second debit in the same month is not a second instalment")
    func onePerMonth() throws {
        let (store, ccp, loan, _) = try ledger()
        _ = try payment(store, on: ccp)
        _ = try LocalLedger.reconcileLoanMirrors(store: store)
        // A coincidence — same amount, same month. The loan is already paid
        // for August and must not be paid twice.
        _ = try payment(store, on: ccp)
        _ = try LocalLedger.reconcileLoanMirrors(store: store)
        #expect(mirrors(store, on: loan) == 1)
    }

    @Test("a nearby amount is not the instalment")
    func exactToTheCent() throws {
        let (store, ccp, loan, _) = try ledger()
        let id = UUID().uuidString
        try store.database.run(
            """
            INSERT INTO transactions
                (id, account_id, occurred_at, amount, currency, payee, normalized_payee,
                 source, status, needs_review)
            VALUES (?, ?, '2026-08-05', -135.90, 'EUR', 'AUTRE CHOSE', 'autre chose',
                    'enable_banking', 'cleared', 1)
            """,
            [.text(id), .text(ccp)]
        )
        #expect(try LocalLedger.reconcileLoanMirrors(store: store) == 0)
        #expect(mirrors(store, on: loan) == 0)
    }

    @Test("a ledger whose pair ids do not match is not paid twice")
    func importedPairsAreNotDoubled() throws {
        let (store, ccp, loan, category) = try ledger()
        // What a server import leaves behind: both legs present, each with its
        // own pair id, so nothing links them. The catch-up used to read that
        // as "no counterpart" and write a second one.
        let id = try payment(store, on: ccp)
        try store.database.run(
            "UPDATE transactions SET category_id = ?, transfer_pair_id = ? WHERE id = ?",
            [.text(category), .text("imported:a"), .text(id)]
        )
        try store.database.run(
            """
            INSERT INTO transactions
                (id, account_id, occurred_at, amount, currency, payee, normalized_payee,
                 source, status, needs_review, transfer_pair_id)
            VALUES (?, ?, '2026-08-05', 165.13, 'EUR', '↳ PRELEVEMENT CREDIT MAISON', 'prelevement credit maison',
                    'server', 'cleared', 0, 'imported:b')
            """,
            [.text(UUID().uuidString), .text(loan)]
        )
        #expect(mirrors(store, on: loan) == 1)

        #expect(try LocalLedger.reconcileLoanMirrors(store: store) == 0)
        #expect(mirrors(store, on: loan) == 1)
    }

    @Test("a payment on the 30th is not a second instalment for the 1st")
    func acrossAMonthBoundary() throws {
        let (store, ccp, loan, _) = try ledger()
        // The bank takes it on the 30th of one month and posts the counterpart
        // on the 1st of the next. Keyed on the calendar month those look like
        // two different instalments; they are one.
        try store.database.run(
            """
            INSERT INTO transactions
                (id, account_id, occurred_at, amount, currency, payee, normalized_payee,
                 source, status, needs_review, transfer_pair_id)
            VALUES (?, ?, '2026-09-01', 165.13, 'EUR', '↳ x', 'x', 'server', 'cleared', 0, ?)
            """,
            [.text(UUID().uuidString), .text(loan), .text(UUID().uuidString)]
        )
        let id = UUID().uuidString
        try store.database.run(
            """
            INSERT INTO transactions
                (id, account_id, occurred_at, amount, currency, payee, normalized_payee,
                 source, status, needs_review)
            VALUES (?, ?, '2026-08-30', -165.13, 'EUR', 'PRELEVEMENT CREDIT MAISON', 'prelevement credit maison',
                    'enable_banking', 'cleared', 1)
            """,
            [.text(id), .text(ccp)]
        )
        #expect(try LocalLedger.reconcileLoanMirrors(store: store) == 0)
        #expect(mirrors(store, on: loan) == 1)
    }

    @Test("counterparts written twice are taken back")
    func dropsDuplicates() throws {
        let (store, ccp, loan, _) = try ledger()
        _ = try payment(store, on: ccp)
        for _ in 0..<2 {
            try store.database.run(
                """
                INSERT INTO transactions
                    (id, account_id, occurred_at, amount, currency, payee, normalized_payee,
                     source, status, needs_review, transfer_pair_id)
                VALUES (?, ?, '2026-08-05', 165.13, 'EUR', '↳ x', 'x', 'manual', 'cleared', 0, ?)
                """,
                [.text(UUID().uuidString), .text(loan), .text(UUID().uuidString)]
            )
        }
        #expect(mirrors(store, on: loan) == 2)
        #expect(try LocalLedger.dropDuplicateLoanMirrors(store: store) == 1)
        #expect(mirrors(store, on: loan) == 1)
    }

    @Test("filing the same payment twice does not pay the loan twice")
    func idempotent() throws {
        let (store, ccp, loan, category) = try ledger()
        let id = try payment(store, on: ccp)
        try LocalLedger.patch(store: store, id: id, TxPatch(categoryId: .some(category)))
        try LocalLedger.patch(store: store, id: id, TxPatch(categoryId: .some(category)))
        #expect(mirrors(store, on: loan) == 1)
    }
}

// MARK: - When the phone asks the bank

@Suite("Background")
struct BackgroundTests {
    private func at(_ iso: String) -> Date {
        ISO8601DateFormatter.florinNoFraction.date(from: iso)!
    }

    private func hourAndMinute(_ date: Date) -> (Int, Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? -1, c.minute ?? -1)
    }

    @Test("the wake-up is aimed at the morning after the bank posts")
    func morning() {
        // Whatever the hour, the next request lands at 07:15.
        for iso in ["2026-08-29T09:00:00Z", "2026-08-29T23:30:00Z", "2026-08-29T03:00:00Z"] {
            let next = BackgroundRefresh.nextMorning(from: at(iso))
            #expect(hourAndMinute(next) == (7, 15))
            #expect(next > at(iso))
        }
    }

    @Test("a run at seven does not ask to be woken again at a quarter past")
    func notImmediately() {
        // The hour of clearance: otherwise the task fires, reschedules for
        // fifteen minutes later, and spends the day waking up.
        let justBefore = BackgroundRefresh.nextMorning(from: at("2026-08-29T05:10:00Z"))
        #expect(justBefore.timeIntervalSince(at("2026-08-29T05:10:00Z")) >= 3600)
    }
}

// MARK: - Backup

// Serialised: these share the Documents folder, where an export prunes the
// copies before it — run in parallel they delete each other's files.
@Suite("Backup", .serialized)
struct BackupTests {
    /// A ledger with the shapes that broke the first attempt: an account
    /// pointing at a bank connection the copy does not carry, and a category
    /// pointing back at an account.
    private func seeded() throws -> LocalStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("florin-test-\(UUID().uuidString).db")
        let store = try LocalStore(url: url)
        let conn = UUID().uuidString, ccp = UUID().uuidString
        let loan = UUID().uuidString, group = UUID().uuidString
        try store.database.exec("""
        INSERT INTO bank_connections
            (id, provider, session_id, status, aspsp_name, aspsp_country, valid_until)
          VALUES ('\(conn)', 'enable_banking', 's-\(conn)', 'active', 'BANQUE EXEMPLE', 'FR', '2026-12-01');
        INSERT INTO category_groups (id, name, kind) VALUES ('\(group)', 'Dépenses', 'expense');
        INSERT INTO accounts (id, name, kind, currency, bank_connection_id)
          VALUES ('\(ccp)', 'CCP', 'checking', 'EUR', '\(conn)');
        INSERT INTO accounts (id, name, kind, currency)
          VALUES ('\(loan)', 'Prêt', 'loan', 'EUR');
        INSERT INTO categories (id, group_id, name, linked_loan_account_id)
          VALUES ('\(UUID().uuidString)', '\(group)', 'Remboursement', '\(loan)');
        INSERT INTO transactions (id, account_id, occurred_at, amount, currency, payee, source)
          VALUES ('\(UUID().uuidString)', '\(ccp)', '2026-08-27', -4.50, 'EUR', 'Forno', 'manual');
        """)
        return store
    }

    private func count(_ store: LocalStore, _ table: String) -> Int {
        ((try? store.database.scalar("SELECT count(*) FROM \(table)")?.int) as? Int ?? -1) ?? -1
    }

    @Test("an exported file can actually be opened again")
    func exportIsReadable() throws {
        // It could not. The copy carried WAL mode in its header, and a WAL
        // database cannot be opened read-only without writing beside it, so the
        // app could not count the rows in its own backup.
        let store = try seeded()
        let file = try LocalBackup.export(from: store)
        let summary = LocalBackup.inspect(file)
        #expect(summary != nil)
        #expect(summary?.transactions == 1)
        #expect(summary?.accounts == 2)
    }

    @Test("a restore reproduces the ledger on a phone that never saw it")
    func restore() throws {
        let old = try seeded()
        let file = try LocalBackup.export(from: old)

        let new = try seeded()          // its own accounts, its own ids
        _ = try LocalBackup.restore(from: file, into: new)

        #expect(count(new, "accounts") == count(old, "accounts"))
        #expect(count(new, "transactions") == count(old, "transactions"))
        #expect(count(new, "categories") == count(old, "categories"))
    }

    @Test("restoring twice lands in the same place")
    func idempotent() throws {
        let old = try seeded()
        let file = try LocalBackup.export(from: old)
        let new = try seeded()
        let first = try LocalBackup.restore(from: file, into: new)
        let second = try LocalBackup.restore(from: file, into: new)
        #expect(first == second)
    }

    @Test("a file that is not a ledger is refused")
    func notALedger() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("not-a-ledger-\(UUID().uuidString).txt")
        try Data("bonjour".utf8).write(to: url)
        #expect(LocalBackup.inspect(url) == nil)
    }
}

/*
 * The same debit, arriving twice under two different names.
 *
 * La Banque Postale numbers entries by their rank in the day — "2026-08-31.0"
 * means "the first row of the 31st" and nothing more — so a second fetch of a
 * month already written renames every row in it. The ledger took the new names
 * for new transactions and the plan showed two mensualités for a month with
 * one.
 */
@Suite("Relabelled bank rows", .serialized)
struct RelabelledDuplicateTests {
    private func ledger() throws -> (LocalStore, account: String) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("florin-relabel-\(UUID().uuidString).db")
        let store = try LocalStore(url: url)
        let account = UUID().uuidString
        try store.database.exec("""
        INSERT INTO accounts (id, name, kind, currency)
          VALUES ('\(account)', 'CCP', 'checking', 'EUR');
        """)
        return (store, account)
    }

    @discardableResult
    private func row(
        _ store: LocalStore, on account: String, amount: Double, payee: String,
        externalId: String, pair: String? = nil, day: String = "2026-08-31"
    ) throws -> String {
        let id = UUID().uuidString
        try store.database.run(
            """
            INSERT INTO transactions
                (id, account_id, occurred_at, amount, currency, payee, normalized_payee,
                 source, external_id, status, needs_review, transfer_pair_id)
            VALUES (?, ?, ?, ?, 'EUR', ?, ?, 'enable_banking', ?, 'cleared', 0, ?)
            """,
            [
                .text(id), .text(account), .text(day), .real(amount), .text(payee),
                .text(payee.lowercased()), .text(externalId),
                pair.map { SQLiteValue.text($0) } ?? .null,
            ]
        )
        return id
    }

    private func live(_ store: LocalStore, on account: String) -> Int {
        ((try? store.database.scalar(
            "SELECT count(*) FROM transactions WHERE account_id = ? AND deleted_at IS NULL",
            [.text(account)]
        )?.int) as? Int ?? -1) ?? -1
    }

    @Test("a positional reference is not an identity")
    func recognisesPositionalReferences() {
        #expect(BankTransaction.isPositional("2026-08-31.0"))
        #expect(BankTransaction.isPositional("2026-08-31.12"))
        // A real identifier that merely contains a dot is not positional.
        #expect(!BankTransaction.isPositional("TRX-2026-08-31.PAYPAL"))
        #expect(!BankTransaction.isPositional("9c27f562-06ab-4d28-9914-f9064d8f4715"))
        #expect(!BankTransaction.isPositional("2026-08-31"))
    }

    @Test("the row renamed by the bank is taken back, the first one kept")
    func collapsesTheRelabelledTwin() throws {
        let (store, account) = try ledger()
        let kept = try row(
            store, on: account, amount: -165.13, payee: "PREL DE CREDIT MAISON",
            externalId: "uid:2026-08-31T00:00:00Z:-165.13:PREL DE CREDIT MAISON"
        )
        let stale = try row(
            store, on: account, amount: -165.13, payee: "PRELEVEMENT DE CREDIT MAISON",
            externalId: "uid:2026-08-31.0"
        )

        #expect(try BankingSync.collapseRelabelledDuplicates(store: store) == 1)
        #expect(live(store, on: account) == 1)

        let gone = try store.database.scalar(
            "SELECT deleted_at FROM transactions WHERE id = ?", [.text(stale)]
        )?.string
        #expect(gone != nil)
        let survivor = try store.database.scalar(
            "SELECT deleted_at FROM transactions WHERE id = ?", [.text(kept)]
        )?.string
        #expect(survivor == nil)
    }

    @Test("the survivor inherits the pairing that has a counterpart")
    func movesTheLivePairing() throws {
        let (store, account) = try ledger()
        let loan = UUID().uuidString
        try store.database.exec("""
        INSERT INTO accounts (id, name, kind, currency)
          VALUES ('\(loan)', 'Prêt', 'loan', 'EUR');
        """)
        // The row kept carries a pair id whose other half was never written;
        // the row discarded is the one the mirror is actually attached to.
        let kept = try row(
            store, on: account, amount: -165.13, payee: "PREL DE CREDIT MAISON",
            externalId: "uid:2026-08-31T00:00:00Z:-165.13:PREL", pair: "orphan"
        )
        try row(
            store, on: account, amount: -165.13, payee: "PRELEVEMENT DE CREDIT MAISON",
            externalId: "uid:2026-08-31.0", pair: "real"
        )
        try row(
            store, on: loan, amount: 165.13, payee: "↳ PRELEVEMENT",
            externalId: "uid:mirror", pair: "real"
        )

        #expect(try BankingSync.collapseRelabelledDuplicates(store: store) == 1)

        let pair = try store.database.scalar(
            "SELECT transfer_pair_id FROM transactions WHERE id = ?", [.text(kept)]
        )?.string
        #expect(pair == "real")
    }

    @Test("two genuine purchases of the same amount on one day are both kept")
    func leavesGenuineTwinsAlone() throws {
        let (store, account) = try ledger()
        // Two train tickets, same price, same day — written under the same
        // scheme, which is what says they are two transactions and not one
        // renamed.
        try row(
            store, on: account, amount: -3.60, payee: "TRAINLINE",
            externalId: "uid:2026-08-31.0"
        )
        try row(
            store, on: account, amount: -3.60, payee: "TRAINLINE",
            externalId: "uid:2026-08-31.1"
        )

        #expect(try BankingSync.collapseRelabelledDuplicates(store: store) == 0)
        #expect(live(store, on: account) == 2)
    }

    @Test("a different day is a different transaction")
    func leavesOtherDaysAlone() throws {
        let (store, account) = try ledger()
        try row(
            store, on: account, amount: -9.99, payee: "PayPal",
            externalId: "uid:2026-08-30T00:00:00Z:-9.99:PayPal", day: "2026-08-30"
        )
        try row(
            store, on: account, amount: -9.99, payee: "PayPal",
            externalId: "uid:2026-08-31.0", day: "2026-08-31"
        )

        #expect(try BankingSync.collapseRelabelledDuplicates(store: store) == 0)
        #expect(live(store, on: account) == 2)
    }
}


/*
 * Ce que le propriétaire a corrigé lui appartient.
 *
 * La banque annonce un virement pendant qu'il est en attente, puis le comptabilise
 * sous une autre référence et parfois sous un autre libellé. Entre les deux,
 * la ligne annoncée a été renommée et catégorisée à la main — et c'est
 * justement ce renommage qui la rendait méconnaissable à sa propre banque :
 * l'appariement comparait le libellé qui arrive au nom que le propriétaire
 * avait écrit. La ligne comptabilisée entrait donc en étrangère, et la version
 * corrigée était effacée comme un doublon, sans rien transmettre.
 */
@Suite("Corrected bank rows", .serialized)
struct CorrectedBankRowTests {
    private func ledger() throws -> (LocalStore, account: String, category: String) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("florin-corrected-\(UUID().uuidString).db")
        let store = try LocalStore(url: url)
        let account = UUID().uuidString
        let group = UUID().uuidString
        let category = UUID().uuidString
        try store.database.exec("""
        INSERT INTO accounts (id, name, kind, currency)
          VALUES ('\(account)', 'CCP', 'checking', 'EUR');
        INSERT INTO category_groups (id, name, kind) VALUES ('\(group)', 'Vie courante', 'expense');
        INSERT INTO categories (id, group_id, name) VALUES ('\(category)', '\(group)', 'Restaurants');
        """)
        return (store, account, category)
    }

    /// The row a bank writes when it announces a transfer it has not booked yet.
    @discardableResult
    private func announced(
        _ store: LocalStore, on account: String, amount: Double, label: String,
        day: String, key: String
    ) throws -> String {
        let id = UUID().uuidString
        try store.database.run(
            """
            INSERT INTO transactions
                (id, account_id, occurred_at, amount, currency, payee, normalized_payee,
                 bank_payee, source, external_id, status, needs_review, is_pending)
            VALUES (?, ?, ?, ?, 'EUR', ?, ?, ?, 'enable_banking', ?, 'cleared', 0, 1)
            """,
            [
                .text(id), .text(account), .text("\(day)T00:00:00Z"), .real(amount),
                .text(label), .text(LocalLedger.normalize(label)), .text(label), .text(key),
            ]
        )
        return id
    }

    private func correct(
        _ store: LocalStore, _ id: String, payee: String, category: String
    ) throws {
        try store.database.run(
            """
            UPDATE transactions
            SET payee = ?, normalized_payee = ?, category_id = ? WHERE id = ?
            """,
            [.text(payee), .text(LocalLedger.normalize(payee)), .text(category), .text(id)]
        )
    }

    private func booking(
        reference: String, amount: Double, day: String, label: String
    ) -> BankTransaction {
        BankTransaction(
            transactionId: reference,
            entryReference: nil,
            transactionAmount: BalancesResponse.Amount(
                amount: String(abs(amount)), currency: "EUR"
            ),
            creditDebitIndicator: amount < 0 ? "DBIT" : "CRDT",
            bookingDate: day,
            valueDate: nil,
            transactionDate: nil,
            creditorName: amount < 0 ? label : nil,
            debtorName: amount < 0 ? nil : label,
            remittanceInformation: nil,
            status: "BOOK"
        )
    }

    private func live(_ store: LocalStore, on account: String) -> Int {
        ((try? store.database.scalar(
            "SELECT count(*) FROM transactions WHERE account_id = ? AND deleted_at IS NULL",
            [.text(account)]
        )?.int) as? Int ?? -1) ?? -1
    }

    private func read(_ store: LocalStore, _ id: String, _ column: String) throws -> String? {
        try store.database.scalar(
            "SELECT \(column) FROM transactions WHERE id = ?", [.text(id)]
        )?.string
    }

    /*
     * Le renommage ne doit pas rendre la ligne méconnaissable.
     *
     * L'appariement demandait « ce libellé ressemble-t-il au nom de cette
     * ligne ? » — alors que le nom de la ligne est celui que le propriétaire a
     * tapé. Il demande maintenant « ressemble-t-il à ce que la banque avait
     * appelé cette ligne ? », ce que la ligne retient désormais à part.
     */
    @Test("a transfer the owner renamed is still recognised when the bank books it")
    func adoptsTheRowItRenamed() throws {
        let (store, account, category) = try ledger()
        let id = try announced(
            store, on: account, amount: -820, label: "VIREMENT SEPA SARL LE COMPTOIR",
            day: "2026-09-20",
            key: "uid:2026-09-20T00:00:00Z:-820.0:VIREMENT SEPA SARL LE COMPTOIR"
        )
        try correct(store, id, payee: "Chez Rosa", category: category)

        var adopted: Set<String> = []
        let written = try BankingSync.insert(
            booking(
                reference: "TRX-90210", amount: -820, day: "2026-09-20",
                label: "SARL LE COMPTOIR"
            ),
            store: store, accountId: account, uid: "uid", adopted: &adopted
        )

        #expect(!written)
        #expect(live(store, on: account) == 1)
        #expect(try read(store, id, "payee") == "Chez Rosa")
        #expect(try read(store, id, "category_id") == category)
        #expect(try read(store, id, "external_id") == "uid:TRX-90210")
        // And it now remembers the bank's newest word for itself.
        #expect(try read(store, id, "bank_payee") == "SARL LE COMPTOIR")
    }

    /// Un vrai homonyme reste refusé : c'est la raison d'être du test de nom.
    @Test("a purchase still cannot take the place of a debit of the same amount")
    func refusesAStranger() throws {
        let (store, account, _) = try ledger()
        try announced(
            store, on: account, amount: -12, label: "PRELEVEMENT TELECOM SA",
            day: "2026-09-20", key: "uid:2026-09-20T00:00:00Z:-12.0:PRELEVEMENT TELECOM SA"
        )

        var adopted: Set<String> = []
        let written = try BankingSync.insert(
            booking(
                reference: "TRX-77", amount: -12, day: "2026-09-20", label: "CHEZ ROSA"
            ),
            store: store, accountId: account, uid: "uid", adopted: &adopted
        )

        #expect(written)
        #expect(live(store, on: account) == 2)
    }

    /*
     * Et pour celles qui sont déjà là en double.
     *
     * L'annonce écartée est la même opération que la ligne comptabilisée :
     * le nom écrit à la main, la catégorie, la note et l'appariement lui
     * survivent au lieu de partir avec elle.
     */
    @Test("the discarded announcement hands over what the owner wrote on it")
    func theGhostHandsOverItsCorrections() throws {
        let (store, account, category) = try ledger()
        let ghost = try announced(
            store, on: account, amount: -820, label: "VIREMENT SEPA SARL LE COMPTOIR",
            day: "2026-09-20", key: "uid:old"
        )
        try correct(store, ghost, payee: "Chez Rosa", category: category)
        let booked = try announced(
            store, on: account, amount: -820, label: "SARL LE COMPTOIR",
            day: "2026-09-20", key: "uid:TRX-90210"
        )
        try store.database.run(
            "UPDATE transactions SET is_pending = 0, occurred_at = '2000-01-02T00:00:00Z' WHERE id = ?",
            [.text(booked)]
        )
        try store.database.run(
            "UPDATE transactions SET occurred_at = '2000-01-01T00:00:00Z' WHERE id = ?",
            [.text(ghost)]
        )

        #expect(try BankingSync.collapseSettledDuplicates(store: store) == 1)
        #expect(live(store, on: account) == 1)
        #expect(try read(store, ghost, "deleted_at") != nil)
        #expect(try read(store, booked, "payee") == "Chez Rosa")
        #expect(try read(store, booked, "category_id") == category)
        // The bank's own word for the surviving row is untouched by the handover.
        #expect(try read(store, booked, "bank_payee") == "SARL LE COMPTOIR")
    }

    /// Une annonce que personne n'a touchée n'a rien à transmettre.
    @Test("an untouched announcement leaves the booked label alone")
    func theUntouchedGhostChangesNothing() throws {
        let (store, account, _) = try ledger()
        let ghost = try announced(
            store, on: account, amount: -820, label: "VIREMENT SEPA SARL LE COMPTOIR",
            day: "2026-09-20", key: "uid:old"
        )
        let booked = try announced(
            store, on: account, amount: -820, label: "SARL LE COMPTOIR",
            day: "2026-09-20", key: "uid:TRX-90210"
        )
        try store.database.run(
            "UPDATE transactions SET is_pending = 0, occurred_at = '2000-01-02T00:00:00Z' WHERE id = ?",
            [.text(booked)]
        )
        try store.database.run(
            "UPDATE transactions SET occurred_at = '2000-01-01T00:00:00Z' WHERE id = ?",
            [.text(ghost)]
        )

        #expect(try BankingSync.collapseSettledDuplicates(store: store) == 1)
        #expect(try read(store, booked, "payee") == "SARL LE COMPTOIR")
    }
}
// MARK: - Naming merchants

@Suite("Merchant names")
struct MerchantNameTests {
    /*
     * La Banque Postale's label format, with made-up merchants. The key has to survive everything that
     * changes from one visit to the next — the date, the amount, "APPLE PAY",
     * a mandate reference — and nothing else, or a rename would stick to one
     * row, or spill onto another merchant.
     */
    @Test("a card merchant keeps one key across dates, amounts and Apple Pay", arguments: [
        "ACHAT CB SARL LE COMPTOIR 07.09.26 EUR          4,10 CARTE NO  123 OC",
        "ACHAT CB SARL LE COMPTOIR 02.09.26 EUR          6,20 CARTE NO  123 OC",
        "ACHAT CB SARL LE COMPTOIR 06.07.26 EUR          6,20 CARTE NO  123 OC APPLE PAY",
    ])
    func card(_ payee: String) {
        #expect(MerchantNames.key(payee) == "sarl le comptoir")
    }

    @Test("a direct debit is cut at its reference")
    func directDebit() {
        #expect(MerchantNames.key(
            "PRELEVEMENT DE TELECOM SA REF : 9876543210987654321012345 0 Votre abonnement mobile: 06XXXXX"
        ) == "telecom sa")
        #expect(MerchantNames.key(
            "PRELEVEMENT DE BOX INTERNET REF : abcd-12345678 IDENT : FR00ZZZ000000 MANDAT : BOX-ABCDEF-1"
        ) == "box internet")
    }

    @Test("an instant transfer is cut at its transaction number")
    func instantTransfer() {
        #expect(MerchantNames.key(
            "VIREMENT INSTANTANE DE PAYPAL 12345678901234567 INSTANT TRANSFER"
        ) == "paypal")
        #expect(MerchantNames.key(
            "VIREMENT INSTANTANE DE PAYPAL 76543210987654321 INSTANT TRANSFER"
        ) == "paypal")
    }

    @Test("two merchants never share a key")
    func distinct() {
        #expect(MerchantNames.key("ACHAT CB SARL LE COMPTOIR 07.09.26 EUR 4,10")
            != MerchantNames.key("ACHAT CB BOULANGERIE DU PARC 27.08.26 EUR 4,50"))
    }

    @Test("case and accents do not split a merchant")
    func folding() {
        #expect(MerchantNames.key("ACHAT CB CAFÉ DU PARC 01.09.26")
            == MerchantNames.key("ACHAT CB Cafe du Parc 02.09.26"))
    }

    @Test("a name made only of a reference still has a key")
    func neverEmpty() {
        #expect(!MerchantNames.key("VIREMENT 12345678901234567").isEmpty)
    }

    /*
     * Le miroir d'un prêt n'est pas un autre commerçant.
     *
     * Il est écrit « ↳ » + le libellé de la ligne qu'il reflète, et la flèche
     * entrait dans la clé : la jambe débit trouvait le nom donné au prêt,
     * son miroir gardait le libellé brut de la banque. Une même échéance
     * s'affichait donc sous deux noms, dont un illisible.
     */
    @Test("a mirror shares the key of the row it mirrors")
    func mirror() {
        let paid = "PRELEVEMENT DE PRET ETUDIANT REF : 12345678901234"
        #expect(MerchantNames.key("↳ " + paid) == MerchantNames.key(paid))
        #expect(MerchantNames.key("↳ " + paid) == "pret etudiant")
    }
}

// MARK: - Annoncée, ou vraiment passée

/*
 * Une date promise n'est pas une date tenue.
 *
 * Le salaire annoncé pour le 28 quittait « en prévision » à 00:00 ce jour-là ;
 * la banque ne l'a comptabilisé qu'à 23:31. Vingt-trois heures durant
 * lesquelles l'app affirmait un mouvement qui n'avait pas eu lieu, sur la
 * seule foi du calendrier.
 */
@Suite("Announced, or actually settled")
struct AnnouncedTests {
    private let mine: Set<String> = ["FR7612345678901234567890123"]

    private func row(_ payee: String, on day: String, pending: Bool = false) -> Transaction {
        Transaction(
            id: UUID().uuidString, date: day, amount: 2_400, payee: payee, memo: nil,
            categoryName: nil, categoryEmoji: nil, accountName: "Compte courant",
            isTransfer: false, needsReview: false, isPending: pending, isScheduled: false
        )
    }

    private var today: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: Date())
    }

    @Test("a row still named after one's own account has not been settled")
    func announced() {
        let announced = row("FR76 1234 5678 9012 3456 7890 123 DUPONT", on: today)
        #expect(announced.isAnnounced(among: mine))
        #expect(announced.isUpcoming(among: mine))
    }

    @Test("the day it is booked the bank names the payer, and it settles")
    func booked() {
        let booked = row("VIREMENT DE EMPLOYEUR EXEMPLE SA", on: today)
        #expect(!booked.isAnnounced(among: mine))
        #expect(!booked.isUpcoming(among: mine))
    }

    /// Les deux se lisent sur la même ligne, à une heure d'intervalle : c'est
    /// le libellé qui bascule, pas la date.
    @Test("the same date, two labels, two answers")
    func theLabelDecides() {
        #expect(row("FR76 1234 5678 9012 3456 7890 123 DUPONT", on: today).isUpcoming(among: mine))
        #expect(!row("VIREMENT DE EMPLOYEUR EXEMPLE SA", on: today).isUpcoming(among: mine))
    }

    /// Un virement écrit à la main nomme un compte par son nom, pas par son
    /// numéro — il ne doit pas passer pour une annonce.
    @Test("a hand-written transfer to one's own account is not an announcement")
    func handWritten() {
        #expect(!row("Transfer to Livret A", on: today).isAnnounced(among: mine))
    }

    @Test("a future date is still enough on its own")
    func future() {
        #expect(row("ACHAT CB BOULANGERIE DU PARC", on: "2099-01-01").isUpcoming(among: mine))
    }

    @Test("a ledger that knows no account number accuses nothing")
    func noAccounts() {
        #expect(!row("FR76 1234 5678 9012 3456 7890 123 DUPONT", on: today).isAnnounced(among: []))
    }
}

// MARK: - Ce qu'une ligne dit sous son nom

@Suite("Row subtitle")
struct RowSubtitleTests {
    /*
     * Un virement ne manque pas de catégorie : il n'en a pas.
     *
     * Les deux jambes portaient « Sans catégorie », le même mot que porte une
     * dépense qu'on a oublié de classer — donc une invitation à réparer
     * quelque chose qui n'est pas cassé. Et comme elles portent désormais le
     * même nom, c'est le compte qui les distingue, pas la date.
     */
    @Test("a transfer says what it is and which side it is")
    func transfer() {
        #expect(RowText.subtitle(
            title: "Mensualité prêt étudiant", category: nil,
            account: "Compte courant", when: "mer. 30 sept.", isTransfer: true
        ) == "Virement · Compte courant")
        #expect(RowText.subtitle(
            title: "Mensualité prêt étudiant", category: nil,
            account: "Prêt étudiant", when: "mer. 30 sept.", isTransfer: true
        ) == "Virement · Prêt étudiant")
    }

    @Test("an unfiled expense still asks to be filed")
    func unfiled() {
        #expect(RowText.subtitle(
            title: "Boulangerie du Parc", category: nil,
            account: "Compte courant", when: "lun. 5 oct.", isTransfer: false
        ) == "Sans catégorie · lun. 5 oct.")
    }

    @Test("a filed row shows its category")
    func filed() {
        #expect(RowText.subtitle(
            title: "Boulangerie du Parc", category: "Food / Courses",
            account: "Compte courant", when: "lun. 5 oct.", isTransfer: false
        ) == "Food / Courses · lun. 5 oct.")
    }

    /// Le titre vaut déjà la catégorie quand le libellé ne nomme personne.
    @Test("a category already in the title is not repeated")
    func noEcho() {
        #expect(RowText.subtitle(
            title: "Salaires", category: "Salaires",
            account: "Compte courant", when: "mar. 28 sept.", isTransfer: false
        ) == "mar. 28 sept.")
    }

    @Test("nothing to say on either side says nothing")
    func empty() {
        #expect(RowText.subtitle(
            title: "Virement", category: nil,
            account: "", when: "", isTransfer: true
        ) == "Virement")
    }
}

// MARK: - Demo ledger

@Suite("Demo ledger", .serialized)
struct DemoLedgerTests {
    private func freshStore(locale: String) throws -> LocalStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("florin-demo-\(UUID().uuidString).db")
        let store = try LocalStore(url: url)
        _ = try LocalBootstrap.run(on: store, locale: locale)
        return store
    }

    private func count(_ store: LocalStore, _ sql: String) throws -> Int {
        try store.database.scalar(sql)?.int ?? 0
    }

    /*
     * What App Review lands on after "Explore with sample data": four
     * accounts, a year of history filed into categories, a plan and a
     * portfolio — in whatever language the categories were seeded in.
     */
    @Test("fills a fresh ledger in every language", arguments: ["fr_FR", "en_US", "it_IT", "es_ES", "nl_NL", "ca_ES", "de_DE", "pt_PT"])
    func fills(_ locale: String) throws {
        let store = try freshStore(locale: locale)
        try LocalDemo.seed(into: store)

        #expect(try count(store, "SELECT count(*) FROM accounts") == 4)
        #expect(try count(store, "SELECT count(*) FROM transactions") > 150)
        #expect(try count(store, "SELECT count(*) FROM holdings") == 2)
        #expect(try count(store, "SELECT count(*) FROM monthly_budgets") == 10)
        // Every row but the two left for the review queue has a category —
        // transfers aside, which have none by design.
        #expect(try count(store, "SELECT count(*) FROM transactions WHERE category_id IS NULL AND transfer_pair_id IS NULL") == 2)
        // The loan's instalments are paired, so its remaining capital moves.
        #expect(try count(store, "SELECT count(*) FROM transactions t JOIN accounts a ON a.id = t.account_id WHERE a.kind = 'loan' AND t.transfer_pair_id IS NOT NULL") >= 12)
        #expect(try count(store, "SELECT count(*) FROM transactions WHERE substr(occurred_at, 1, 10) > date('now')") == 0)
        #expect(LocalDemo.isActive(in: store))
    }

    @Test("keeps the balance invariant every write relies on")
    func invariant() throws {
        let store = try freshStore(locale: "fr_FR")
        try LocalDemo.seed(into: store)
        let broken = try count(store, """
            SELECT count(*) FROM accounts a
            WHERE a.kind IN ('checking', 'savings')
              AND abs(a.opening_balance + coalesce((SELECT sum(amount) FROM transactions t
                     WHERE t.account_id = a.id AND t.deleted_at IS NULL), 0) - a.current_balance) > 0.005
            """)
        #expect(broken == 0)
        #expect(try store.database.scalar(
            "SELECT current_balance FROM accounts WHERE kind = 'checking'"
        )?.double == 2418.63)
    }

    @Test("leaving the demo empties the ledger and keeps the categories")
    func erase() throws {
        let store = try freshStore(locale: "fr_FR")
        let categories = try count(store, "SELECT count(*) FROM categories")
        try LocalDemo.seed(into: store)
        try LocalDemo.erase(from: store)

        #expect(try count(store, "SELECT count(*) FROM accounts") == 0)
        #expect(try count(store, "SELECT count(*) FROM transactions") == 0)
        #expect(try count(store, "SELECT count(*) FROM categories") == categories)
        #expect(!LocalDemo.isActive(in: store))
    }
}

// MARK: - Month names

@Suite("Month names")
struct MonthNameTests {
    /*
     * The plan's month reads in the app's language. The overview's locale tag
     * once knew only French and Dutch, so every other language got English
     * months — "September 2026" on a Catalan screen.
     */
    @Test("September, in every language the app ships", arguments: [
        ("fr", "septembre"), ("en", "September"), ("nl", "september"),
        ("it", "settembre"), ("es", "septiembre"), ("ca", "setembre"),
        ("de", "September"), ("pt", "setembro"), ("tr", "Eylül"),
    ])
    func september(_ language: String, _ expected: String) {
        let label = MonthLabel.long("2026-09", locale: Strings.tag(for: language))
        #expect(label.lowercased().contains(expected.lowercased()), "\(language): \(label)")
    }
}

// MARK: - Filing a refund

/*
 * A shop's credit belongs with the shop, not with a month's earnings.
 *
 * The sign guard read both ways: money out could not be earnings, and money
 * in could not be spending. The second half made the ledger's own answer
 * unreachable for a refund — the only categories left were the income ones,
 * so a shirt sent back arrived as income and the shirt stayed at full price.
 */
@Suite("Refunds")
struct RefundTests {
    private func ledger() throws -> (LocalStore, account: String, clothes: String, extra: String) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("florin-refund-\(UUID().uuidString).db")
        let store = try LocalStore(url: url)
        let account = UUID().uuidString
        let spending = UUID().uuidString, earning = UUID().uuidString
        let clothes = UUID().uuidString, extra = UUID().uuidString
        try store.database.exec("""
        INSERT INTO category_groups (id, name, kind) VALUES ('\(spending)', 'Envies', 'expense');
        INSERT INTO category_groups (id, name, kind) VALUES ('\(earning)', 'Revenus', 'income');
        INSERT INTO categories (id, group_id, name) VALUES ('\(clothes)', '\(spending)', 'Vêtements');
        INSERT INTO categories (id, group_id, name) VALUES ('\(extra)', '\(earning)', 'Gains');
        INSERT INTO accounts (id, name, kind, currency) VALUES ('\(account)', 'CCP', 'checking', 'EUR');
        """)
        return (store, account, clothes, extra)
    }

    @discardableResult
    private func row(
        _ store: LocalStore, _ account: String, _ payee: String, _ amount: Double,
        category: String?, review: Int = 0
    ) throws -> String {
        let id = UUID().uuidString
        try store.database.run(
            """
            INSERT INTO transactions
                (id, account_id, occurred_at, amount, currency, payee, normalized_payee,
                 source, status, needs_review, category_id)
            VALUES (?, ?, '2026-08-05', ?, 'EUR', ?, ?, 'enable_banking', 'cleared', ?, ?)
            """,
            [.text(id), .text(account), .real(amount), .text(payee),
             .text(payee.lowercased()), .integer(Int64(review)),
             category.map { SQLiteValue.text($0) } ?? .null]
        )
        return id
    }

    /// Six purchases at one shop, then the shop pays one of them back.
    ///
    /// The suggestion is what is asserted, not the write: a credit whose label
    /// shares only the merchant's words sits below the apply threshold and
    /// goes to review, where this is the category offered.
    @Test("a shop's credit is matched to the shop, not to income")
    func creditGoesToTheShop() throws {
        let (store, account, clothes, extra) = try ledger()
        for _ in 0..<6 {
            try row(store, account, "ACHAT CB LE COMPTOIR VIA ROMA", -39.90, category: clothes)
        }
        try row(store, account, "VIREMENT INSTANTANE CREDIT", 50, category: extra)

        let memory = try LocalCategoriser.remember(store: store)
        let hit = LocalCategoriser.suggest(
            memory, payee: "CREDIT CARTE BANCAIRE LE COMPTOIR VIA ROMA",
            amount: 39.90, accountId: account
        )
        #expect(hit?.categoryId == clothes)
    }

    /// The same shop, the same label it always sends: the ledger has answered
    /// this one before, so the refund is filed unattended.
    @Test("a credit whose label the ledger knows is filed without asking")
    func knownCreditIsFiled() throws {
        let (store, account, clothes, _) = try ledger()
        for _ in 0..<4 {
            try row(store, account, "LE COMPTOIR VIA ROMA", -39.90, category: clothes)
        }
        let refund = try row(
            store, account, "LE COMPTOIR VIA ROMA", 39.90, category: nil, review: 1
        )
        _ = try LocalCategoriser.backfill(store: store)

        let filed = try store.database.scalar(
            "SELECT category_id FROM transactions WHERE id = ?", [.text(refund)]
        )?.string
        #expect(filed == clothes)
    }

    /// The half of the guard that was there for a reason: a transfer out
    /// carrying the owner's own name used to match the salary rows. With only
    /// earnings in the past, money leaving has no candidate at all.
    @Test("money leaving is never matched to income")
    func debitIsNeverIncome() throws {
        let (store, account, _, extra) = try ledger()
        for _ in 0..<6 {
            try row(store, account, "VIREMENT INSTANTANE DE JEAN MARTIN", 500, category: extra)
        }

        let memory = try LocalCategoriser.remember(store: store)
        let hit = LocalCategoriser.suggest(
            memory, payee: "VIREMENT INSTANTANE A JEAN MARTIN",
            amount: -500, accountId: account
        )
        #expect(hit == nil)
    }
}

// MARK: - The radar for what repeats

/*
 * A subscription is recognised by its words, not by its label.
 *
 * The grouping was the bank's own label with the case taken off, and a card
 * label carries the date of the charge and the number of the card — so every
 * instalment of one subscription arrived under a different name and the radar
 * found nothing at all.
 */
@Suite("Category hints")
struct CategoryHintTests {
    private func ledger() throws -> (LocalStore, account: String, food: String, gifts: String) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("florin-hint-\(UUID().uuidString).db")
        let store = try LocalStore(url: url)
        let account = UUID().uuidString
        let spending = UUID().uuidString
        let food = UUID().uuidString, gifts = UUID().uuidString
        try store.database.exec("""
        INSERT INTO category_groups (id, name, kind) VALUES ('\(spending)', 'Besoins', 'expense');
        INSERT INTO categories (id, group_id, name) VALUES ('\(food)', '\(spending)', 'Courses');
        INSERT INTO categories (id, group_id, name) VALUES ('\(gifts)', '\(spending)', 'Cadeaux');
        INSERT INTO accounts (id, name, kind, currency) VALUES ('\(account)', 'CCP', 'checking', 'EUR');
        """)
        return (store, account, food, gifts)
    }

    private func row(
        _ store: LocalStore, _ account: String, _ payee: String, _ amount: Double, category: String?
    ) throws {
        try store.database.run(
            """
            INSERT INTO transactions
                (id, account_id, occurred_at, amount, payee, normalized_payee, source, category_id)
            VALUES (?, ?, '2026-05-04T10:00:00Z', ?, ?, ?, 'enable_banking', ?)
            """,
            [
                .text(UUID().uuidString), .text(account), .real(amount),
                .text(payee), .text(LocalLedger.normalize(payee)),
                category.map { .text($0) } ?? .null,
            ]
        )
    }

    /// Le cas qui a motivé la proposition : le moteur tient la bonne réponse et
    /// se tait, parce qu'il ne classe qu'au-dessus de 0,80. Un mot venu d'une
    /// autre catégorie suffit à diviser le score sans rendre le candidat faux.
    @Test("a candidate too weak to file is still worth offering")
    func weakCandidateIsOffered() throws {
        let (store, account, food, gifts) = try ledger()
        for _ in 0..<3 { try row(store, account, "ACHAT CB PANETTERIA AURORA", -4.20, category: food) }
        try row(store, account, "BOUTIQUE GIRASOLE", -22.00, category: gifts)

        let memory = try LocalCategoriser.remember(store: store)
        let hit = CategoryHint.suggest(
            memory, payee: "Panetteria Aurora Girasole", amount: -3.80, accountId: account
        )
        #expect(hit?.categoryId == food)
        #expect((hit?.confidence ?? 1) < LocalCategoriser.applyThreshold)
        #expect((hit?.confidence ?? 0) >= CategoryHint.floor)
    }

    /*
     * Un mot vu une seule fois pèse autant qu'une habitude.
     *
     * La concentration d'un mot se mesure sur ses occurrences : vu une fois,
     * il est par construction « concentré à 100 % » sur la catégorie où on l'a
     * vu, et son poids écrase des mots vus dix fois. C'est ainsi qu'une
     * boulangerie connue de longue date s'est fait proposer « Cadeaux » par un
     * mot emprunté à un fleuriste. Amortir la concentration corrige ce cas-là
     * et en casse autant d'autres — mesuré, c'est un jeu à somme nulle — donc
     * le moteur ne tranche pas : il propose, et le geste reste à la personne.
     */
    @Test("a word seen once can outrank a habit, which is why nothing is applied")
    func oneSightingCanMislead() throws {
        let (store, account, food, gifts) = try ledger()
        for _ in 0..<3 { try row(store, account, "ACHAT CB PANETTERIA AURORA", -4.20, category: food) }
        try row(store, account, "BOUTIQUE GIRASOLE", -22.00, category: gifts)

        let memory = try LocalCategoriser.remember(store: store)
        let hit = CategoryHint.suggest(
            memory, payee: "Panetteria Girasole", amount: -3.80, accountId: account
        )
        // Proposé, jamais appliqué : c'est toute la différence entre les deux.
        #expect(hit != nil)
        #expect((hit?.confidence ?? 1) < LocalCategoriser.applyThreshold)
    }

    /// Un libellé dont aucun mot n'a de passé ne propose rien : mieux vaut la
    /// liste complète qu'un nom tiré au hasard.
    @Test("a merchant the ledger has never seen proposes nothing")
    func unknownMerchantProposesNothing() throws {
        let (store, account, food, _) = try ledger()
        for _ in 0..<3 { try row(store, account, "ACHAT CB PANETTERIA ROMA", -4.20, category: food) }

        let memory = try LocalCategoriser.remember(store: store)
        #expect(CategoryHint.suggest(
            memory, payee: "Zzyrkan Vittore", amount: -6.50, accountId: account
        ) == nil)
    }

    /// Le plancher n'est pas décoratif : en dessous, le candidat ne vaut pas
    /// mieux qu'un tirage au sort et n'a rien à faire en tête de liste.
    @Test("the floor sits below the filing threshold and above nothing")
    func floorIsBetweenSilenceAndFiling() {
        #expect(CategoryHint.floor > 0)
        #expect(CategoryHint.floor < LocalCategoriser.applyThreshold)
    }

    /// Ce qui est déjà classé ne se fait pas proposer autre chose, et un
    /// virement interne n'est pas une dépense à ranger.
    @Test("a filed row and a transfer are left alone")
    func filedRowsAreLeftAlone() {
        let categories = [Category(
            id: "c1", name: "Courses", emoji: nil, groupName: "Besoins",
            linkedLoanAccountId: nil, groupKind: "expense"
        )]
        let filed = Transaction(
            id: "t1", date: "2026-05-04T10:00:00Z", amount: -4.20, payee: "Panetteria",
            memo: nil, categoryName: "Courses", categoryEmoji: nil, accountName: "CCP",
            isTransfer: false, needsReview: false, isPending: false, isScheduled: false,
            accountId: "a1", categoryId: "c1"
        )
        #expect(CategoryHint.category(for: filed, in: categories) == nil)

        let transfer = Transaction(
            id: "t2", date: "2026-05-04T10:00:00Z", amount: -4.20, payee: "Panetteria",
            memo: nil, categoryName: nil, categoryEmoji: nil, accountName: "CCP",
            isTransfer: true, needsReview: false, isPending: false, isScheduled: false,
            accountId: "a1", categoryId: nil
        )
        #expect(CategoryHint.category(for: transfer, in: categories) == nil)
    }
}

@Suite("Subscriptions")
struct SubscriptionTests {
    private func ledger() throws -> (LocalStore, account: String) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("florin-subs-\(UUID().uuidString).db")
        let store = try LocalStore(url: url)
        let account = UUID().uuidString
        try store.database.exec("""
        INSERT INTO accounts (id, name, kind, currency) VALUES ('\(account)', 'CCP', 'checking', 'EUR');
        """)
        return (store, account)
    }

    /// `daysAgo` days back, as the ledger writes a day.
    private func day(_ daysAgo: Int) -> String {
        let date = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return LocalQueries.dayFormatter.string(from: date)
    }

    private func charge(
        _ store: LocalStore, _ account: String, _ label: String, _ amount: Double, daysAgo: Int
    ) throws {
        try store.database.run(
            """
            INSERT INTO transactions (id, account_id, occurred_at, amount, currency, payee,
                normalized_payee, source, status, is_pending)
            VALUES (?, ?, ?, ?, 'EUR', ?, ?, 'enable_banking', 'cleared', 0)
            """,
            [.text(UUID().uuidString), .text(account), .text("\(day(daysAgo))T00:00:00Z"),
             .real(amount), .text(label), .text(LocalLedger.normalize(label))]
        )
    }

    @Test("a monthly charge is found even when the label carries the date and the card")
    func labelNoiseDoesNotHideIt() throws {
        let (store, account) = try ledger()
        for month in 0..<6 {
            let daysAgo = 15 + month * 30
            try charge(
                store, account,
                "ACHAT CB LE COMPTOIR VIA ROMA \(day(daysAgo)) CARTE NUMERO 4979",
                -9.99, daysAgo: daysAgo
            )
        }

        let matches = try LocalAnalysis.subscriptions(store.database)
        #expect(matches.count == 1)
        #expect(matches.first?.amount == 9.99)
        #expect(matches.first?.samples == 6)
        #expect(matches.first?.annualCost == 119.88)
    }

    /// A café most weeks averages seven days between visits without being a
    /// subscription — the beat has to be kept, not merely averaged.
    @Test("a shop visited whenever is not a subscription")
    func irregularVisitsAreNotASubscription() throws {
        let (store, account) = try ledger()
        for daysAgo in [3, 4, 5, 26, 27, 52, 53, 54] {
            try charge(store, account, "ACHAT CB CHEZ ROSA", -4.50, daysAgo: daysAgo)
        }

        #expect(try LocalAnalysis.subscriptions(store.database).isEmpty)
    }

    /// Two payments is a coincidence, and a price that moves every month is
    /// not one price.
    @Test("two charges, or a moving amount, are not enough")
    func thinEvidenceIsRefused() throws {
        let (store, account) = try ledger()
        try charge(store, account, "ACHAT CB CHEZ ROSA", -12, daysAgo: 20)
        try charge(store, account, "ACHAT CB CHEZ ROSA", -12, daysAgo: 50)
        for month in 0..<5 {
            let daysAgo = 10 + month * 30
            try charge(
                store, account, "PRELEVEMENT LE COMPTOIR",
                -(20 + Double(month) * 6), daysAgo: daysAgo
            )
        }

        #expect(try LocalAnalysis.subscriptions(store.database).isEmpty)
    }
}

// MARK: - The catalogue the screens read

/*
 * A language ships when every screen can speak it, not when its file exists.
 *
 * The two resources are written by hand, one language at a time, and a key
 * that was added to English and forgotten elsewhere shows up as a French
 * sentence on a Turkish screen — or, for the seed, as an English category
 * list in a freshly installed app. Both are silent at runtime: the lookup
 * falls back rather than failing, which is right in front of a user and
 * useless to the author.
 */
@Suite("Translations")
struct TranslationTests {
    /// `Bundle.main`, as the app itself reads them: the tests are hosted
    /// inside Florin, and the resources are the app's, not the bundle's.
    private func catalogue() throws -> [String: [String: String]] {
        let url = try #require(Bundle.main.url(forResource: "Strings", withExtension: "json"))
        return try JSONDecoder().decode([String: [String: String]].self, from: Data(contentsOf: url))
    }

    @Test("every language has every key English has")
    func parity() throws {
        let all = try catalogue()
        let english = try #require(all["en"])
        for (language, table) in all where language != "en" {
            let missing = Set(english.keys).subtracting(table.keys).sorted()
            let extra = Set(table.keys).subtracting(english.keys).sorted()
            #expect(missing.isEmpty, "\(language) is missing \(missing.count): \(missing.prefix(5))")
            #expect(extra.isEmpty, "\(language) has \(extra.count) English doesn't: \(extra.prefix(5))")
        }
    }

    /// A dropped `{amount}` reads as a sentence with a hole in it.
    @Test("every translation keeps its placeholders")
    func placeholders() throws {
        let all = try catalogue()
        let english = try #require(all["en"])
        for (language, table) in all where language != "en" {
            for (key, source) in english {
                guard let translation = table[key] else { continue }
                #expect(Self.names(source) == Self.names(translation),
                        "\(language)/\(key): \(Self.names(translation)) vs \(Self.names(source))")
            }
        }
    }

    @Test("every language seeds its own categories")
    func seeds() throws {
        let languages = Set(try catalogue().keys)
        let url = try #require(
            Bundle.main.url(forResource: "SeedCategories", withExtension: "json"))
        let seeds = try JSONDecoder()
            .decode([String: [LocalBootstrap.SeedGroup]].self, from: Data(contentsOf: url))
        #expect(Set(seeds.keys) == languages)
        let english = try #require(seeds["en"])
        for (language, groups) in seeds {
            #expect(groups.count == english.count, "\(language): \(groups.count) groups")
            #expect(groups.flatMap(\.categories).count == english.flatMap(\.categories).count,
                    "\(language): categories")
        }
    }

    private static func names(_ text: String) -> Set<String> {
        var found: Set<String> = []
        var name: String?
        for character in text {
            if character == "{" { name = "" } else if character == "}" {
                if let name, !name.isEmpty { found.insert(name) }
                name = nil
            } else if name != nil {
                name?.append(character)
            }
        }
        return found
    }
}

// MARK: - Payments recorded at the till

@Suite("Wallet payments", .serialized)
struct WalletPaymentTests {
    private func ledger() throws -> (LocalStore, checking: String, other: String) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("florin-wallet-\(UUID().uuidString).db")
        let store = try LocalStore(url: url)
        let checking = UUID().uuidString, other = UUID().uuidString
        try store.database.exec("""
        INSERT INTO accounts (id, name, kind, currency, current_balance, opening_balance, display_order)
          VALUES ('\(checking)', 'Compte courant', 'checking', 'EUR', 500, 500, 0);
        INSERT INTO accounts (id, name, kind, currency, current_balance, opening_balance, display_order)
          VALUES ('\(other)', 'Autre', 'checking', 'EUR', 100, 100, 1);
        """)
        return (store, checking, other)
    }

    private func day(_ iso: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
    }

    /// The same day at a given hour, local time — what a card tap carries.
    private func at(_ hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 11, hour: hour, minute: 30)
        )!
    }

    private func bankRow(
        _ store: LocalStore, _ account: String, _ iso: String, _ amount: Double,
        label: String = "ACHAT CB SARL LE COMPTOIR"
    ) throws -> String {
        let id = UUID().uuidString
        try store.database.run(
            """
            INSERT INTO transactions (id, account_id, occurred_at, amount, payee, normalized_payee,
                source, status, is_pending)
            VALUES (?, ?, ?, ?, ?, ?, 'enable_banking', 'cleared', 0)
            """,
            [.text(id), .text(account), .text("\(iso)T00:00:00Z"), .real(amount),
             .text(label), .text(LocalLedger.normalize(label))]
        )
        return id
    }

    /*
     * Two debits of one amount on one day, one tap: the name decides.
     *
     * The bank row that does not name the shop arrives first, and on day and
     * amount alone it took the tap — the tap's name ended up on the wrong
     * purchase, and the right one was listed again beside it.
     */
    @Test("a tap is settled by the bank row that names its shop, not the first of that amount")
    func settledByName() throws {
        let (store, checking, _) = try ledger()
        try LocalWallet.record(
            store: store, amountText: "14,00", merchant: "Le Comptoir",
            card: nil, accountId: checking, on: day("2026-09-13")
        )
        let other = try bankRow(store, checking, "2026-09-13", -14, label: "ACHAT CB CHEZ ROSA 13.09.26")
        let named = try bankRow(store, checking, "2026-09-13", -14, label: "ACHAT CB SARL LE COMPTOIR 13.09.26")

        #expect(try LocalWallet.settle(store: store) == 1)
        let link = try store.database.scalar(
            "SELECT merge_suggested_tx_id FROM transactions WHERE source = ?", [.text(LocalWallet.source)]
        )?.string
        #expect(link == named)
        #expect(link != other)
    }

    /*
     * A tap an earlier sync adopted is put back as settling would have left
     * it: booked, under the bank's own label.
     */
    @Test("a card payment adopted by an earlier sync reads as the bank's booked row")
    func repairsAdopted() throws {
        let (store, checking, _) = try ledger()
        let id = UUID().uuidString
        try store.database.run(
            """
            INSERT INTO transactions (id, account_id, occurred_at, amount, payee, normalized_payee,
                source, external_id, status, is_pending)
            VALUES (?, ?, '2026-09-13T00:00:00Z', -14, 'Le Comptoir', 'le comptoir',
                'enable_banking', ?, 'scheduled', 0)
            """,
            [.text(id), .text(checking),
             .text("acct-1:2026-09-13T00:00:00Z:-14.0:ACHAT CB CHEZ ROSA 13.09.26")]
        )
        #expect(try LocalWallet.repairAdopted(store: store) == 1)
        let row = try #require(try store.database.query(
            "SELECT status, payee FROM transactions WHERE id = ?", [.text(id)]
        ).first)
        #expect(row.string("status") == "cleared")
        #expect(row.string("payee") == "ACHAT CB CHEZ ROSA 13.09.26")
        #expect(LocalWallet.bankLabel(inKey: "acct-1:some-stable-reference") == nil)
    }

    /*
     * A direct debit and a card purchase of one amount on one day are two
     * merchants; the bank's boilerplate is not a name they share.
     */
    @Test("names agree on a merchant word, not on bank boilerplate")
    func namesAgreeOnMerchant() {
        #expect(LocalLedger.namesAgree("PREL DE SARL LE COMPTOIR ADHESION", "PRELEVEMENT DE SARL LE COMPTOIR", whenUnsure: false))
        #expect(!LocalLedger.namesAgree("PREL DE SARL LE COMPTOIR ADHESION", "ACHAT CB CHEZ ROSA 07.09.26 CARTE", whenUnsure: true))
        #expect(!LocalLedger.namesAgree("ACHAT CB CHEZ ROSA", "ACHAT CB LE COMPTOIR", whenUnsure: true))
        #expect(LocalLedger.namesAgree("CB 07.09.26", "ACHAT CB CHEZ ROSA", whenUnsure: true))
        #expect(!LocalLedger.namesAgree("CB 07.09.26", "ACHAT CB CHEZ ROSA", whenUnsure: false))
    }

    /*
     * A refund typed in from the receipt is dated that day; the bank credited
     * it days earlier, and the pair has to find each other anyway.
     */
    @Test("a refund settles onto a credit the bank booked before it was entered")
    func refundSettlesBackwards() throws {
        let (store, checking, _) = try ledger()
        let credit = try bankRow(store, checking, "2026-09-12", 61.20,
                                 label: "CREDIT CARTE BANCAIRE SARL LE COMPTOIR")
        let older = try bankRow(store, checking, "2026-09-09", -6.3, label: "ACHAT CB CHEZ ROSA")
        try store.database.run(
            """
            INSERT INTO transactions (id, account_id, occurred_at, amount, payee, normalized_payee,
                source, status, is_pending)
            VALUES (?, ?, '2026-09-16T17:00:00Z', 61.20, 'Le Comptoir', 'le comptoir',
                'ios_shortcut', 'scheduled', 1)
            """,
            [.text(UUID().uuidString), .text(checking)]
        )
        // A payment, not a refund: the identical one a week earlier is another
        // purchase and must be left alone.
        try store.database.run(
            """
            INSERT INTO transactions (id, account_id, occurred_at, amount, payee, normalized_payee,
                source, status, is_pending)
            VALUES (?, ?, '2026-09-17T11:00:00Z', -6.3, 'Chez Rosa', 'chez rosa',
                'ios_shortcut', 'scheduled', 1)
            """,
            [.text(UUID().uuidString), .text(checking)]
        )
        #expect(try LocalWallet.settle(store: store) == 1)
        #expect(try store.database.scalar(
            "SELECT count(*) FROM transactions WHERE merge_suggested_tx_id = ?", [.text(credit)]
        )?.int == 1)
        #expect(try store.database.scalar(
            "SELECT count(*) FROM transactions WHERE merge_suggested_tx_id = ?", [.text(older)]
        )?.int == 0)
    }

    /*
     * A fare the operator submitted late: the bank booked the ride on the day
     * it happened, Wallet only revealed it afterwards, so the tap is dated
     * after the row that already holds it.
     */
    @Test("a payment recorded late settles onto the row the bank booked before it")
    func debitSettlesSlightlyBackwards() throws {
        let (store, checking, _) = try ledger()
        let fare = try bankRow(store, checking, "2026-09-03", -1.80,
                               label: "ACHAT CB TRANSPORTS DU FLEUVE")
        try store.database.run(
            """
            INSERT INTO transactions (id, account_id, occurred_at, amount, payee, normalized_payee,
                source, status, is_pending)
            VALUES (?, ?, '2026-09-04T09:10:00Z', -1.80, 'Transports du Fleuve',
                'transports du fleuve', 'ios_shortcut', 'scheduled', 1)
            """,
            [.text(UUID().uuidString), .text(checking)]
        )
        #expect(try LocalWallet.settle(store: store) == 1)
        #expect(try store.database.scalar(
            "SELECT count(*) FROM transactions WHERE merge_suggested_tx_id = ?", [.text(fare)]
        )?.int == 1)
    }

    /// Three days, not a week: beyond that the room behind buys nothing but
    /// the chance of claiming a different purchase of the same price.
    @Test("a week earlier is another purchase, name or no name")
    func debitDoesNotReachTooFarBack() throws {
        let (store, checking, _) = try ledger()
        _ = try bankRow(store, checking, "2026-09-01", -1.80,
                        label: "ACHAT CB TRANSPORTS DU FLEUVE")
        try store.database.run(
            """
            INSERT INTO transactions (id, account_id, occurred_at, amount, payee, normalized_payee,
                source, status, is_pending)
            VALUES (?, ?, '2026-09-09T09:10:00Z', -1.80, 'Transports du Fleuve',
                'transports du fleuve', 'ios_shortcut', 'scheduled', 1)
            """,
            [.text(UUID().uuidString), .text(checking)]
        )
        #expect(try LocalWallet.settle(store: store) == 0)
        #expect(try live(store, source: LocalWallet.source) == 1)
    }

    @Test("a bank row that took another merchant's name gets its own back")
    func restoresBankLabel() throws {
        let (store, checking, _) = try ledger()
        let taken = UUID().uuidString
        let renamed = UUID().uuidString
        let key = "acct-1:2026-09-07T00:00:00Z:-12.0:ACHAT CB CHEZ ROSA 07.09.26"
        for (id, payee) in [(taken, "PREL DE SARL LE COMPTOIR ADHESION"), (renamed, "Rosa")] {
            try store.database.run(
                """
                INSERT INTO transactions (id, account_id, occurred_at, amount, payee, normalized_payee,
                    memo, source, external_id, status, is_pending, needs_review)
                VALUES (?, ?, '2026-09-07T00:00:00Z', -12, ?, ?, 'PREL DE SARL LE COMPTOIR ADHESION',
                    'enable_banking', ?, 'cleared', 0, 0)
                """,
                [.text(id), .text(checking), .text(payee), .text(LocalLedger.normalize(payee)),
                 .text(id == taken ? key : key + " ")]
            )
        }
        #expect(try BankingSync.restoreBankLabels(store: store) == 1)
        let row = try #require(try store.database.query(
            "SELECT payee, memo, needs_review FROM transactions WHERE id = ?", [.text(taken)]
        ).first)
        #expect(row.string("payee") == "ACHAT CB CHEZ ROSA 07.09.26")
        #expect(row.string("memo") == "ACHAT CB CHEZ ROSA 07.09.26")
        #expect(row.int("needs_review") == 1)
        #expect(try store.database.scalar("SELECT payee FROM transactions WHERE id = ?", [.text(renamed)]) == .text("Rosa"))
        #expect(try BankingSync.restoreBankLabels(store: store) == 0)
    }

    /*
     * Past the twelve latest rows, Aperçu still sees the whole queue — its
     * groups were cut out of the latest twelve and disagreed with Activité.
     */
    @Test("rows waiting for review further down still reach the overview")
    func waitingBeyondLatest() throws {
        let (store, checking, _) = try ledger()
        let old = try bankRow(store, checking, "2026-01-05", -3)
        try store.database.run("UPDATE transactions SET needs_review = 1 WHERE id = ?", [.text(old)])
        for n in 0..<15 {
            let id = try bankRow(store, checking, String(format: "2026-09-%02d", n + 1), -1)
            try store.database.run("UPDATE transactions SET needs_review = 0 WHERE id = ?", [.text(id)])
        }
        let recent = try LocalQueries.overview(store: store, locale: "fr").recent
        #expect(recent.contains { $0.id == old })
    }

    /*
     * Seventeen things due does not mean nothing happened.
     *
     * The section took the twelve newest rows by date, and a row dated ahead
     * is newer than anything that has actually happened — so a queue of a
     * dozen scheduled payments took all twelve places and "dernières
     * opérations" showed one folded line and not a single operation. What
     * belongs there is the last operations *past*, however long the queue.
     */
    @Test("a queue of upcoming rows does not push out what already happened")
    func settledSurviveTheQueue() throws {
        let (store, checking, _) = try ledger()
        func day(_ offset: Int) -> String {
            LocalQueries.dayFormatter.string(
                from: Date().addingTimeInterval(86_400 * Double(offset))
            )
        }
        for n in 1...15 {
            let id = try bankRow(store, checking, day(n), -20)
            try store.database.run(
                "UPDATE transactions SET is_pending = 1, status = 'scheduled', needs_review = 0 WHERE id = ?",
                [.text(id)]
            )
        }
        var happened: [String] = []
        for n in 1...3 {
            let id = try bankRow(store, checking, day(-n), -4.10)
            try store.database.run(
                "UPDATE transactions SET needs_review = 0 WHERE id = ?", [.text(id)]
            )
            happened.append(id)
        }

        let recent = try LocalQueries.overview(store: store, locale: "fr").recent
        let settled = recent.filter { !$0.isUpcoming && !$0.needsReview }
        #expect(settled.map(\.id).sorted() == happened.sorted())
        // And the queue is still whole, not cut to what fitted.
        #expect(recent.filter(\.isUpcoming).count == 15)
    }

    /*
     * Filed from history the moment it is recorded.
     *
     * Wallet hands over the merchant as the shop calls itself — "Boulangerie
     * du Parc" — while the bank wrote "ACHAT CB BOULANGERIE DU PARC 01.09.26
     * EUR 4,10 CARTE NO 123 OC" every other time. The categoriser has to see
     * the same merchant through both, or every tap arrives unfiled.
     */
    /*
     * Typed in by hand after paying with no signal: the same wait, the same
     * handover to the bank's row — and the automation's badge is not claimed.
     */
    @Test("a payment entered by hand waits under upcoming and is settled by the bank")
    func enteredByHand() throws {
        let (store, checking, _) = try ledger()
        try LocalLedger.add(store: store, NewTransaction(
            accountId: checking, amount: -4.10, payee: "Le Comptoir",
            occurredAt: "2026-09-11T12:00:00Z", memo: nil, categoryId: nil, upcoming: true
        ))
        let row = try #require(try store.database.query(
            "SELECT status, is_pending, source, memo FROM transactions WHERE deleted_at IS NULL"
        ).first)
        #expect(row.string("status") == "scheduled")
        #expect(row.int("is_pending") == 1)
        #expect(row.string("source") == LocalWallet.source)
        #expect(row.string("memo") == nil)
        // Not in the balance until the bank has it.
        let balance = try store.database.scalar(
            "SELECT current_balance FROM accounts WHERE id = ?", [.text(checking)]
        )?.double
        #expect(balance == 500)

        _ = try bankRow(store, checking, "2026-09-13", -4.10)
        #expect(try LocalWallet.settle(store: store) == 1)
        #expect(try store.database.scalar(
            "SELECT count(*) FROM transactions WHERE deleted_at IS NULL"
        )?.int == 1)
    }

    /*
     * Three shops in one afternoon, in the order they were paid.
     *
     * They tied on `occurred_at` — a payment used to be recorded at midnight —
     * and the list broke the tie on random identifiers, so the "en prévision"
     * group came out shuffled. The row typed in by hand made it worse: filed
     * at noon, it outranked every tap of the day on a timestamp comparison.
     * The day and then the moment Florin learned of the row is the order the
     * card's own list of payments has.
     */
    @Test("the same day's payments are listed as the card lists them")
    func sameDayOrder() throws {
        let (store, checking, _) = try ledger()
        for (hour, merchant) in [(9, "Le Comptoir"), (13, "Grande Epicerie"), (19, "Chez Rosa")] {
            try LocalWallet.record(
                store: store, amountText: "4,10", merchant: merchant,
                card: nil, accountId: checking, on: at(hour)
            )
            // Three taps are minutes apart; three inserts in a test are not,
            // and `created_at` counts in seconds.
            try store.database.run(
                "UPDATE transactions SET created_at = ? WHERE payee = ?",
                [.text(String(format: "2026-09-11 %02d:30:00", hour)), .text(merchant)]
            )
        }
        // Typed in from the add sheet at midday, after the fact.
        try LocalLedger.add(store: store, NewTransaction(
            accountId: checking, amount: 12, payee: "Remboursement",
            occurredAt: "2026-09-11T12:00:00Z", memo: nil, categoryId: nil, upcoming: true
        ))
        let rows = try LocalQueries.readTransactions(store.database, limit: 10)
        #expect(rows.map(\.payee)
            == ["Remboursement", "Chez Rosa", "Grande Epicerie", "Le Comptoir"])
    }

    @Test("a payment arrives already filed when its merchant has a history")
    func filedFromHistory() throws {
        let (store, checking, _) = try ledger()
        let group = UUID().uuidString, groceries = UUID().uuidString
        try store.database.exec("""
        INSERT INTO category_groups (id, name, kind) VALUES ('\(group)', 'Besoins', 'expense');
        INSERT INTO categories (id, group_id, name) VALUES ('\(groceries)', '\(group)', 'Courses');
        """)
        for (n, iso) in ["2026-08-04", "2026-08-11", "2026-08-18"].enumerated() {
            try store.database.run(
                """
                INSERT INTO transactions (id, account_id, occurred_at, amount, payee, normalized_payee,
                    category_id, source, status, is_pending)
                VALUES (?, ?, ?, ?, ?, ?, ?, 'enable_banking', 'cleared', 0)
                """,
                [.text(UUID().uuidString), .text(checking), .text("\(iso)T00:00:00Z"), .real(-4.1 - Double(n)),
                 .text("ACHAT CB BOULANGERIE DU PARC \(iso.suffix(2)).08.26 EUR 4,10 CARTE NO 123 OC"),
                 .text("achat cb boulangerie du parc"), .text(groceries)]
            )
        }

        try LocalWallet.record(store: store, amountText: "3,80", merchant: "Boulangerie du Parc", card: nil, accountId: nil)

        let filed = try store.database.scalar(
            "SELECT category_id FROM transactions WHERE source = ? AND deleted_at IS NULL",
            [.text(LocalWallet.source)]
        )?.string
        #expect(filed == groceries)
    }

    private func live(_ store: LocalStore, source: String) throws -> Int {
        try store.database.scalar(
            "SELECT count(*) FROM transactions WHERE source = ? AND deleted_at IS NULL", [.text(source)]
        )?.int ?? 0
    }

    @Test("reads the amount the way Wallet writes it", arguments: [
        ("4,10 €", 4.10), ("€4.10", 4.10), ("1 234,56 €", 1234.56),
        ("1\u{202F}234,56 €", 1234.56), ("$1,234.56", 1234.56), ("12", 12.0),
    ])
    func amounts(_ text: String, _ expected: Double) {
        #expect(LocalWallet.parseAmount(text) == expected)
    }

    @Test("an unreadable amount is refused, not recorded as zero")
    func unreadable() throws {
        let (store, _, _) = try ledger()
        #expect(throws: LocalWallet.Failure.self) {
            try LocalWallet.record(store: store, amountText: "gratuit", merchant: "Café", card: nil, accountId: nil)
        }
        #expect(try live(store, source: LocalWallet.source) == 0)
    }

    @Test("records an upcoming, pending debit on the first current account, outside the balance")
    func records() throws {
        let (store, checking, _) = try ledger()
        let recorded = try LocalWallet.record(
            store: store, amountText: "4,10 €", merchant: "Café du Parc", card: "Visa", accountId: nil
        )
        #expect(recorded.accountName == "Compte courant")
        let row = try store.database.query(
            "SELECT account_id, amount, status, is_pending, memo FROM transactions WHERE source = 'ios_shortcut'"
        ).first
        #expect(row?.string("account_id") == checking)
        #expect(row?.double("amount") == -4.10)
        #expect(row?.string("status") == "scheduled")
        #expect(row?.int("is_pending") == 1)
        #expect(row?.string("memo") == "Apple Pay · Visa")
        #expect(try store.database.scalar(
            "SELECT current_balance FROM accounts WHERE id = ?", [.text(checking)]
        )?.double == 500)
    }

    @Test("the bank's row replaces the payment and takes its category")
    func settles() throws {
        let (store, checking, _) = try ledger()
        try LocalWallet.record(
            store: store, amountText: "4,10", merchant: "Café", card: nil, accountId: checking, on: day("2026-09-07")
        )
        let group = UUID().uuidString, category = UUID().uuidString
        try store.database.exec("""
        INSERT INTO category_groups (id, name, kind) VALUES ('\(group)', 'Sorties', 'expense');
        INSERT INTO categories (id, group_id, name) VALUES ('\(category)', '\(group)', 'Cafés');
        UPDATE transactions SET category_id = '\(category)' WHERE source = 'ios_shortcut';
        """)
        let bank = try bankRow(store, checking, "2026-09-09", -4.10)

        #expect(try LocalWallet.settle(store: store) == 1)
        #expect(try live(store, source: LocalWallet.source) == 0)
        #expect(try store.database.scalar(
            "SELECT category_id FROM transactions WHERE id = ?", [.text(bank)]
        )?.string == category)
    }

    @Test("one bank row settles one payment, even across syncs")
    func oneToOne() throws {
        let (store, checking, _) = try ledger()
        try LocalWallet.record(store: store, amountText: "4,10", merchant: "Café", card: nil, accountId: checking, on: day("2026-09-07"))
        _ = try bankRow(store, checking, "2026-09-08", -4.10)
        #expect(try LocalWallet.settle(store: store) == 1)

        // The next day, the same coffee at the same price — its bank row has
        // not arrived yet, so it must stay.
        try LocalWallet.record(store: store, amountText: "4,10", merchant: "Café", card: nil, accountId: checking, on: day("2026-09-08"))
        #expect(try LocalWallet.settle(store: store) == 0)
        #expect(try live(store, source: LocalWallet.source) == 1)
    }

    @Test("another amount, another account or an earlier row does not settle it")
    func noFalseMatch() throws {
        let (store, checking, other) = try ledger()
        try LocalWallet.record(store: store, amountText: "4,10", merchant: "Café", card: nil, accountId: checking, on: day("2026-09-07"))
        _ = try bankRow(store, checking, "2026-09-08", -4.20)   // different amount
        _ = try bankRow(store, other, "2026-09-08", -4.10)      // different account
        _ = try bankRow(store, checking, "2026-09-06", -4.10)   // the day before the tap
        _ = try bankRow(store, checking, "2026-09-20", -4.10)   // too late
        #expect(try LocalWallet.settle(store: store) == 0)
        #expect(try live(store, source: LocalWallet.source) == 1)
    }
}

// MARK: - Merchant logos

@Suite("Merchant logos")
struct MerchantLogoTests {
    @Test("a known merchant is found by whole words, the more specific name first", arguments: [
        ("netflix com", "netflix.com"),
        ("uber eats help uber com", "ubereats.com"),
        ("uber bv", "uber.com"),
        ("h&m 1234", "hm.com"),
        ("amzn mktp fr", "amazon.com"),
        ("prime video", "primevideo.com"),
    ])
    func known(_ key: String, _ domain: String) {
        #expect(KnownMerchants.domain(forKey: key) == domain)
    }

    @Test("a person or a small shop gets no brand's logo", arguments: [
        "claude martin", "le comptoir", "boulangerie du coin", "applebees", "", "orangerie du parc",
    ])
    func unknown(_ key: String) {
        #expect(KnownMerchants.domain(forKey: key) == nil)
    }

    @Test("a typed address comes down to the site's name")
    func domains() {
        #expect(MerchantLogos.normalizedDomain("https://www.Le-Comptoir.fr/menu?x=1") == "le-comptoir.fr")
        #expect(MerchantLogos.normalizedDomain("  shop.example.co.uk ") == "shop.example.co.uk")
        #expect(MerchantLogos.normalizedDomain("le comptoir") == nil)
        #expect(MerchantLogos.normalizedDomain("comptoir") == nil)
        #expect(MerchantLogos.normalizedDomain("comptoir.1") == nil)
        #expect(MerchantLogos.normalizedDomain("") == nil)
    }

    @Test("the touch icon comes first, then the largest, never an SVG")
    func iconLinks() throws {
        let html = """
        <head>
          <link rel="icon" href="/favicon-32.png" sizes="32x32">
          <link rel='shortcut icon' href='favicon.ico'>
          <link rel="icon" type="image/svg+xml" href="/logo.svg">
          <link rel="stylesheet" href="/site.css">
          <LINK REL="apple-touch-icon" SIZES="180x180" HREF="https://cdn.example.org/touch.png">
        </head>
        """
        let base = try #require(URL(string: "https://www.example.org/fr/"))
        #expect(LogoFetcher.iconLinks(in: html, base: base).map(\.absoluteString) == [
            "https://cdn.example.org/touch.png",
            "https://www.example.org/favicon-32.png",
            "https://www.example.org/fr/favicon.ico",
        ])
    }

    @Test("the emoji field keeps pictographs, not digits or signs", arguments: [
        ("🥐", true), ("❤️", true), ("🇮🇹", true), ("1", false), ("#", false), ("a", false),
    ])
    func emoji(_ text: String, _ isEmoji: Bool) throws {
        let character = try #require(text.first)
        #expect(MerchantNameSheet.isEmoji(character) == isEmoji)
    }
}

// MARK: - What the automation tried

/*
 * Le journal d'une action qui tourne sans écran.
 *
 * Toute la valeur du journal tient dans un cas : celui où le paiement n'a pas
 * pu être enregistré. Ce sont donc les échecs qu'on éprouve ici, pas les
 * réussites — et le fait qu'une tentative ouverte puis jamais close se lise
 * quand même, parce qu'un processus tué en arrière-plan ne repasse pas.
 */
@Suite("Automation journal", .serialized)
struct WalletJournalTests {
    @Test("A failed attempt keeps what Wallet handed over, and why it failed")
    func failureKeepsTheInput() throws {
        let store = try ledger()
        let id = WalletLog.begin(
            store: store, amountText: "12,50 €", merchant: "Chez Rosa", card: "MA BANQUE"
        )
        WalletLog.finish(store: store, id: id, outcome: .failed, detail: "Montant illisible")

        let attempt = try #require(WalletLog.recent(store: store).first)
        #expect(attempt.outcome == .failed)
        #expect(attempt.amountText == "12,50 €")
        #expect(attempt.merchant == "Chez Rosa")
        #expect(attempt.detail == "Montant illisible")
    }

    @Test("An attempt never closed stays readable as interrupted")
    func interruptedStaysOpen() throws {
        let store = try ledger()
        WalletLog.begin(store: store, amountText: "4,10", merchant: "Le Comptoir", card: nil)

        let attempt = try #require(WalletLog.recent(store: store).first)
        #expect(attempt.outcome == .started)
    }

    @Test("The newest attempt comes first, and the table does not grow forever")
    func newestFirstAndBounded() throws {
        let store = try ledger()
        for index in 1...(WalletLog.keep + 5) {
            let id = WalletLog.begin(
                store: store, amountText: "\(index),00", merchant: "Le Comptoir", card: nil
            )
            WalletLog.finish(store: store, id: id, outcome: .recorded)
        }
        let kept = try #require(
            try store.database.scalar("SELECT COUNT(*) FROM wallet_attempts")?.int
        )
        #expect(kept == WalletLog.keep)
    }

    private func ledger() throws -> LocalStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("florin-journal-\(UUID().uuidString).db")
        return try LocalStore(url: url)
    }
}

// MARK: - A merchant's own picture

@Suite("Merchant picture")
struct MerchantPictureTests {
    /*
     * Une photo d'iPhone pèse quelques mégaoctets ; la base la porte, la
     * sauvegarde la recopie, et la bulle qui l'affiche fait cinquante points.
     * Ce qui est gardé doit donc être petit, carré, et non déformé.
     */
    @Test("A wide photo is squared and shrunk to a few tens of kilobytes")
    func wideBecomesSmallSquare() throws {
        let wide = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 900)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1600, height: 900))
        }
        let data = try #require(MerchantLogos.thumbnail(wide))
        let kept = try #require(UIImage(data: data))
        #expect(kept.size.width == MerchantLogos.pictureSide)
        #expect(kept.size.height == MerchantLogos.pictureSide)
        #expect(data.count < 80_000)
    }
}

// MARK: - The same shop under two labels

/*
 * La banque tronque, Apple Pay pas.
 *
 * Le relevé ne garde que les premiers caractères du commerçant — « SumUp
 * *LE COMPTO » — là où Wallet transmet « SumUp *LE COMPTOIR SARL ». Deux
 * libellés pour une seule boutique, donc deux clés, donc deux renommages à
 * faire pour un seul marchand. Une clé qui est le préfixe exact d'une autre
 * est précisément ce que produit une troncature : les deux désignent le
 * même commerce.
 *
 * Éprouvé sur la résolution seule, à qui l'on donne sa table : le magasin
 * partagé est celui de l'app, et un test n'a rien à y écrire.
 */
@Suite("Truncated bank labels")
struct TruncatedLabelTests {
    private let named = ["sumup *le comptoir sarl": "Le Comptoir"]
    private let truncated = ["sumup *le compto": "Le Comptoir"]

    @Test("Naming the Apple Pay label also names the bank's truncated one")
    func renameReachesTheBankLabel() {
        #expect(MerchantNames.resolve("sumup *le compto", in: named) == "Le Comptoir")
    }

    @Test("And the other way round: the bank's label covers Apple Pay's")
    func renameReachesTheWalletLabel() {
        #expect(MerchantNames.resolve("sumup *le comptoir sarl", in: truncated) == "Le Comptoir")
    }

    @Test("A name given to this very label wins over a truncation of it")
    func exactNameWins() {
        let table = ["chez rosa": "Chez Rosa", "chez rosa traiteur": "Rosa Traiteur"]
        #expect(MerchantNames.resolve("chez rosa traiteur", in: table) == "Rosa Traiteur")
        #expect(MerchantNames.resolve("chez rosa", in: table) == "Chez Rosa")
    }

    @Test("Too short to be a truncation, so it stays its own merchant")
    func shortKeysStayApart() {
        // « bar » n'est pas une troncature : c'est un mot.
        #expect(MerchantNames.resolve("bar", in: ["bar du coin": "Bar du Coin"]) == nil)
    }

    @Test("Two merchants that merely start alike are not merged")
    func neighboursStayApart() {
        let table = ["boulangerie du port": "Le Fournil"]
        #expect(MerchantNames.resolve("boulangerie centrale", in: table) == nil)
    }
}

/*
 * Un virement dont la banque change le libellé.
 *
 * Le salaire arrive annoncé sous un numéro de compte, puis comptabilisé sous
 * le nom de l'employeur : deux libellés sans un mot en commun. Les mots ne
 * peuvent rien en dire — pire, le nom de famille traverse tous les virements
 * du grand livre et tire vers la mauvaise catégorie de revenus. Ce qui ne
 * bouge pas, c'est la forme : même compte, même montant, même semaine.
 */
@Suite("Recurring credits")
struct RecurringCreditTests {
    private func ledger() throws -> (LocalStore, account: String, salary: String, extra: String) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("florin-rhythm-\(UUID().uuidString).db")
        let store = try LocalStore(url: url)
        let account = UUID().uuidString
        let earning = UUID().uuidString
        let salary = UUID().uuidString, extra = UUID().uuidString
        try store.database.exec("""
        INSERT INTO accounts (id, name, kind, currency)
          VALUES ('\(account)', 'CCP', 'checking', 'EUR');
        INSERT INTO category_groups (id, name, kind) VALUES ('\(earning)', 'Revenus', 'income');
        INSERT INTO categories (id, group_id, name) VALUES ('\(salary)', '\(earning)', 'Salaires');
        INSERT INTO categories (id, group_id, name) VALUES ('\(extra)', '\(earning)', 'Gains additionnels');
        """)
        return (store, account, salary, extra)
    }

    @discardableResult
    private func row(
        _ store: LocalStore, _ account: String, _ date: String, _ payee: String,
        _ amount: Double, category: String?
    ) throws -> String {
        let id = UUID().uuidString
        try store.database.run(
            """
            INSERT INTO transactions
                (id, account_id, occurred_at, amount, currency, payee, normalized_payee,
                 source, status, needs_review, category_id)
            VALUES (?, ?, ?, ?, 'EUR', ?, ?, 'enable_banking', 'cleared', 0, ?)
            """,
            [.text(id), .text(account), .text(date), .real(amount), .text(payee),
             .text(payee.lowercased()), category.map { SQLiteValue.text($0) } ?? .null]
        )
        return id
    }

    /// Cinq mois du même virement, puis un sixième sous un libellé inédit.
    private func salaried(_ store: LocalStore, _ account: String, _ salary: String) throws {
        for (index, day) in ["2026-04-27", "2026-05-27", "2026-06-26", "2026-07-29", "2026-08-27"].enumerated() {
            try row(store, account, day, "VIREMENT DE TELECOM SA", 2000 + Double(index), category: salary)
        }
    }

    @Test("a credit the words cannot name is named by its rhythm")
    func rhythmNamesTheSalary() throws {
        let (store, account, salary, _) = try ledger()
        try salaried(store, account, salary)

        let memory = try LocalCategoriser.remember(store: store)
        let hit = LocalCategoriser.suggest(
            memory, payee: "FR7630000000000000000000123 DUPONT", amount: 2006,
            accountId: account, date: "2026-09-28"
        )
        #expect(hit?.categoryId == salary)
        #expect((hit?.confidence ?? 0) >= LocalCategoriser.applyThreshold)
    }

    /// Le même virement, mais le grand livre n'a pas encore quatre mois à
    /// montrer : trois fois n'est pas une habitude.
    @Test("three months are not a habit")
    func threeMonthsAreNotEnough() throws {
        let (store, account, salary, _) = try ledger()
        for day in ["2026-06-26", "2026-07-29", "2026-08-27"] {
            try row(store, account, day, "VIREMENT DE TELECOM SA", 2000, category: salary)
        }

        let memory = try LocalCategoriser.remember(store: store)
        let hit = LocalCategoriser.suggest(
            memory, payee: "FR7630000000000000000000123 DUPONT", amount: 2000,
            accountId: account, date: "2026-09-28"
        )
        #expect(hit == nil)
    }

    /// Un passé partagé ne décide rien : quatre mois, deux catégories.
    @Test("a divided past decides nothing")
    func dividedPastStaysSilent() throws {
        let (store, account, salary, extra) = try ledger()
        try row(store, account, "2026-05-27", "VIREMENT DE TELECOM SA", 2000, category: salary)
        try row(store, account, "2026-06-26", "VIREMENT DE TELECOM SA", 2000, category: salary)
        try row(store, account, "2026-07-29", "VIREMENT DE TELECOM SA", 2000, category: extra)
        try row(store, account, "2026-08-27", "VIREMENT DE TELECOM SA", 2000, category: salary)

        let memory = try LocalCategoriser.remember(store: store)
        let hit = LocalCategoriser.suggest(
            memory, payee: "FR7630000000000000000000123 DUPONT", amount: 2000,
            accountId: account, date: "2026-09-28"
        )
        #expect(hit == nil)
    }

    /// Le même montant, le même compte, mais versé n'importe quand : une
    /// rentrée régulière tombe dans la même semaine, pas à trois semaines près.
    @Test("a credit that lands anywhere in the month is not recurring")
    func scatteredDaysStaySilent() throws {
        let (store, account, salary, _) = try ledger()
        for day in ["2026-05-03", "2026-06-14", "2026-07-08", "2026-08-11"] {
            try row(store, account, day, "VIREMENT DE TELECOM SA", 2000, category: salary)
        }

        let memory = try LocalCategoriser.remember(store: store)
        let hit = LocalCategoriser.suggest(
            memory, payee: "FR7630000000000000000000123 DUPONT", amount: 2000,
            accountId: account, date: "2026-09-28"
        )
        #expect(hit == nil)
    }

    /// Une dépense mensuelle du même montant ne suffit pas : trop d'achats se
    /// répètent au même prix sans être la même chose.
    @Test("a monthly debit of the same size is left alone")
    func debitsAreLeftAlone() throws {
        let (store, account, _, _) = try ledger()
        let spending = UUID().uuidString, rent = UUID().uuidString
        try store.database.exec("""
        INSERT INTO category_groups (id, name, kind) VALUES ('\(spending)', 'Charges', 'expense');
        INSERT INTO categories (id, group_id, name) VALUES ('\(rent)', '\(spending)', 'Loyer');
        """)
        for day in ["2026-05-02", "2026-06-02", "2026-07-02", "2026-08-02"] {
            try row(store, account, day, "PRELEVEMENT JOIVY", -800, category: rent)
        }

        let memory = try LocalCategoriser.remember(store: store)
        let hit = LocalCategoriser.suggest(
            memory, payee: "FR7630000000000000000000123 DUPONT", amount: -800,
            accountId: account, date: "2026-09-02"
        )
        #expect(hit == nil)
    }

    /// Le numéro de compte quitte la ligne, ce qui l'accompagne reste.
    @Test("an account number is not shown as a name")
    func ibanLeavesTheLabel() throws {
        #expect(PayeeText.clean("FR7630000000000000000000123 DUPONT") == "DUPONT")
        // Rien d'autre à dire : mieux vaut le code-barres qu'une ligne vide.
        #expect(PayeeText.clean("FR7630000000000000000000123") == "FR7630000000000000000000123")
    }

    /// Le libellé ne nomme que le compte d'arrivée : la ligne porte ce qu'elle
    /// est, pas le nom de famille de celui qui la lit.
    @Test("a label that names only the account is titled by its category")
    func ownAccountRowIsTitledByCategory() throws {
        #expect(
            PayeeText.title("VIREMENT DE TELECOM SA", category: "Salaires")
                == PayeeText.humanize("VIREMENT DE TELECOM SA")
        )
        let named = MerchantNames.shared.name(for: "FR7630000000000000000000123 DUPONT")
        // Sans compte connu de ce numéro, rien ne change : c'est la liste des
        // comptes qui autorise la substitution, pas la forme du libellé.
        #expect(named == nil)
        #expect(
            PayeeText.title("FR7630000000000000000000123 DUPONT", category: "Salaires") == "Dupont"
        )
    }
}

// MARK: - Announcements settling into bookings

/*
 * Une banque annonce un virement, puis le comptabilise sous un autre nom.
 *
 * Les deux libellés ne partagent alors aucun mot : l'annonce nomme le compte
 * d'arrivée, la comptabilisation nomme l'émetteur. La ligne annoncée doit
 * pourtant céder la place à celle qui la réalise, faute de quoi le mois
 * compte deux fois le même virement.
 */
@Suite("Announced then booked")
struct AnnouncedThenBookedTests {
    private let own: Set<String> = ["FR7630000000000000000000123"]

    @Test("an announcement made under one's own account number gives way")
    func ownNumberAnnouncementSettles() {
        #expect(
            BankingSync.labelsAgree(
                "VIREMENT DE ATELIERS MARTIN",
                "FR7630000000000000000000123 DUPONT",
                own: own
            )
        )
    }

    /// C'est la liste des comptes qui tranche, pas la forme du libellé : sans
    /// elle, les deux textes restent deux opérations distinctes.
    @Test("without the ledger's accounts the two labels stay apart")
    func withoutTheAccountsTheyStayApart() {
        #expect(
            !BankingSync.labelsAgree(
                "VIREMENT DE ATELIERS MARTIN",
                "FR7630000000000000000000123 DUPONT",
                own: []
            )
        )
    }

    /// Le même numéro écrit autrement reste le même compte.
    @Test("the same number written differently is the same account")
    func theSameNumberWrittenDifferently() {
        #expect(
            BankingSync.labelsAgree(
                "VIREMENT DE ATELIERS MARTIN",
                "fr76 3000 0000 0000 0000 0000 123 DUPONT",
                own: own
            )
        )
    }

    /// Un numéro qui n'est pas le sien ne donne aucun passe-droit.
    @Test("someone else's account number decides nothing")
    func anotherNumberDecidesNothing() {
        #expect(
            !BankingSync.labelsAgree(
                "VIREMENT DE ATELIERS MARTIN",
                "FR7612345678901234567890999 ROSA",
                own: own
            )
        )
    }

    /// Le garde-fou tient toujours : deux commerçants du même montant le même
    /// jour restent deux opérations.
    @Test("two merchants still disagree")
    func twoMerchantsStillDisagree() {
        #expect(!BankingSync.labelsAgree("LE COMPTOIR", "CHEZ ROSA", own: own))
    }

    @Test("a shared word is still enough")
    func aSharedWordIsEnough() {
        #expect(
            BankingSync.labelsAgree(
                "PRELEVEMENT DE TELECOM SA", "TELECOM SA REF 9876543210", own: own
            )
        )
    }

    /// Un libellé qui ne dit rien ne peut rien contredire.
    @Test("a label with nothing to say is not weighed")
    func anEmptyLabelIsNotWeighed() {
        #expect(BankingSync.labelsAgree("", "CHEZ ROSA", own: own))
    }
}

// MARK: - Payments held while the ledger was closed

/*
 * Un paiement présenté pendant que la base ne s'ouvrait pas.
 *
 * C'est la fenêtre d'une installation : quelques secondes où l'action Wallet
 * n'a nulle part où écrire, pas même au journal. Elle mettait le paiement à
 * la poubelle ; elle le met désormais de côté.
 */
@Suite("Payments held while closed", .serialized)
struct WalletQueueTests {
    private func ledger() throws -> (LocalStore, defaults: UserDefaults) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("florin-held-\(UUID().uuidString).db")
        let store = try LocalStore(url: url)
        try store.database.exec("""
        INSERT INTO accounts (id, name, kind, currency)
          VALUES ('\(UUID().uuidString)', 'CCP', 'checking', 'EUR');
        """)
        let defaults = try #require(UserDefaults(suiteName: "florin.tests.\(UUID().uuidString)"))
        return (store, defaults)
    }

    @Test("a payment held while closed enters the ledger at the next launch")
    func heldPaymentIsResumed() throws {
        let (store, defaults) = try ledger()
        let tapped = Date(timeIntervalSince1970: 1_750_000_000)
        WalletQueue.hold(
            amountText: "4,10 €", merchant: "Le Comptoir", card: "MA BANQUE",
            at: tapped, in: defaults
        )

        #expect(WalletQueue.drain(store: store, in: defaults) == 1)

        let row = try #require(
            try store.database.query(
                "SELECT payee, amount, status FROM transactions"
            ).first
        )
        #expect(row.string("payee") == "Le Comptoir")
        #expect(row.double("amount") == -4.10)
        #expect(row.string("status") == "scheduled")
    }

    /// Reprendre laisse sa trace : sans elle, la ligne apparaîtrait dans le
    /// grand livre sans que rien ne dise d'où elle sort.
    @Test("resuming leaves its line in the journal")
    func resumingIsWrittenDown() throws {
        let (store, defaults) = try ledger()
        WalletQueue.hold(amountText: "4,10 €", merchant: "Le Comptoir", card: nil, in: defaults)
        WalletQueue.drain(store: store, in: defaults)

        let attempt = try #require(WalletLog.recent(store: store).first)
        #expect(attempt.outcome == .recorded)
        #expect(attempt.merchant == "Le Comptoir")
    }

    /// La file se vide : un lancement de plus n'ajoute pas le paiement une
    /// seconde fois.
    @Test("a resumed payment is not entered twice")
    func resumingIsNotRepeated() throws {
        let (store, defaults) = try ledger()
        WalletQueue.hold(amountText: "4,10 €", merchant: "Le Comptoir", card: nil, in: defaults)
        WalletQueue.drain(store: store, in: defaults)

        #expect(WalletQueue.drain(store: store, in: defaults) == 0)
        #expect(WalletQueue.pending(in: defaults).isEmpty)
        let count = try #require(
            try store.database.scalar("SELECT COUNT(*) FROM transactions")?.int
        )
        #expect(count == 1)
    }

    /// Un montant illisible ne le devient pas au lancement suivant : sa ligne
    /// dit pourquoi, et la file ne le retient pas pour toujours.
    @Test("an unreadable amount is dropped, with its reason")
    func unreadableAmountIsDropped() throws {
        let (store, defaults) = try ledger()
        WalletQueue.hold(amountText: "", merchant: "Le Comptoir", card: nil, in: defaults)

        #expect(WalletQueue.drain(store: store, in: defaults) == 0)
        let attempt = try #require(WalletLog.recent(store: store).first)
        #expect(attempt.outcome == .failed)
        #expect(WalletQueue.pending(in: defaults).isEmpty)
    }

    /// Deux paiements dans la même fenêtre attendent tous les deux.
    @Test("two payments held in the same window both come back")
    func twoHeldPaymentsBothReturn() throws {
        let (store, defaults) = try ledger()
        WalletQueue.hold(amountText: "1,50 €", merchant: "Le Comptoir", card: nil, in: defaults)
        WalletQueue.hold(amountText: "9,90 €", merchant: "Chez Rosa", card: nil, in: defaults)

        #expect(WalletQueue.drain(store: store, in: defaults) == 2)
    }
}

/*
 * Le filet : ce que l'automatisation a écrit elle-même.
 *
 * L'action de Florin peut cesser d'être appelée sans que rien ne le dise —
 * remplacer l'app détache le lien. Une action native placée devant elle écrit
 * chaque paiement dans un fichier, et Florin le relit à l'ouverture. Ce qui
 * est éprouvé ici, c'est surtout l'inverse du rattrapage : qu'il ne double
 * jamais une opération déjà entrée.
 */
@Suite("The shortcut's own file", .serialized)
struct WalletInboxTests {
    private func ledger() throws -> (store: LocalStore, file: URL) {
        let id = UUID().uuidString
        let store = try LocalStore(
            url: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("florin-inbox-\(id).db")
        )
        try store.database.exec("""
        INSERT INTO accounts (id, name, kind, currency)
          VALUES ('\(UUID().uuidString)', 'CCP', 'checking', 'EUR');
        """)
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("florin-inbox-\(id)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (store, folder.appendingPathComponent(WalletInbox.fileName))
    }

    private func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }

    private let tapped = Date(timeIntervalSince1970: 1_750_000_000)

    @Test("a line the action never recorded enters the ledger")
    func lineIsRecovered() throws {
        let (store, file) = try ledger()
        try "\(stamp(tapped))|4,10 €|MA BANQUE|Le Comptoir\n".write(to: file, atomically: true, encoding: .utf8)

        #expect(WalletInbox.drain(store: store, at: file, now: tapped) == 1)

        let row = try #require(try store.database.query(
            "SELECT payee, amount, status, memo FROM transactions"
        ).first)
        #expect(row.string("payee") == "Le Comptoir")
        #expect(row.double("amount") == -4.10)
        #expect(row.string("status") == "scheduled")
        #expect(row.string("memo") == "Apple Pay · MA BANQUE")
    }

    /// Le cas courant, et le seul qui compte vraiment : l'action a marché, le
    /// fichier dit la même chose, et il ne doit rien ajouter.
    @Test("a payment the action already recorded is not doubled")
    func recordedPaymentIsNotDoubled() throws {
        let (store, file) = try ledger()
        try LocalWallet.record(
            store: store, amountText: "4,10 €", merchant: "Le Comptoir",
            card: "MA BANQUE", accountId: nil, on: tapped
        )
        try "\(stamp(tapped))|4,10 €|MA BANQUE|Le Comptoir\n".write(to: file, atomically: true, encoding: .utf8)

        #expect(WalletInbox.drain(store: store, at: file, now: tapped) == 0)
        #expect(try store.database.scalar("SELECT COUNT(*) FROM transactions")?.int == 1)
    }

    /*
     * Une opération que la banque a confirmée est supprimée, pas effacée.
     *
     * C'est le piège du rattrapage : la ligne du paiement disparaît de
     * l'écran quand la banque prend le relais, et un filet qui ne regarde que
     * les lignes vivantes la réécrirait des jours plus tard, en double de
     * l'opération bancaire.
     */
    @Test("a payment the bank has already settled is not written again")
    func settledPaymentIsNotRewritten() throws {
        let (store, file) = try ledger()
        try LocalWallet.record(
            store: store, amountText: "4,10 €", merchant: "Le Comptoir",
            card: nil, accountId: nil, on: tapped
        )
        try store.database.run("UPDATE transactions SET deleted_at = datetime('now')")
        try "\(stamp(tapped))|4,10 €||Le Comptoir\n".write(to: file, atomically: true, encoding: .utf8)

        #expect(WalletInbox.drain(store: store, at: file, now: tapped) == 0)
    }

    /// Deux cafés identiques dans la même journée restent deux cafés.
    @Test("the same amount at the same shop an hour later is another payment")
    func twoIdenticalPaymentsAreKept() throws {
        let (store, file) = try ledger()
        try LocalWallet.record(
            store: store, amountText: "1,50 €", merchant: "Le Comptoir",
            card: nil, accountId: nil, on: tapped
        )
        let later = tapped.addingTimeInterval(3600)
        try "\(stamp(later))|1,50 €||Le Comptoir\n".write(to: file, atomically: true, encoding: .utf8)

        #expect(WalletInbox.drain(store: store, at: file, now: later) == 1)
        #expect(try store.database.scalar("SELECT COUNT(*) FROM transactions")?.int == 2)
    }

    /// Vidé après coup : le fichier ne grossit pas et le journal ne
    /// reconstate pas les mêmes lignes à chaque ouverture.
    @Test("the file is emptied once it has been read")
    func fileIsEmptied() throws {
        let (store, file) = try ledger()
        try "\(stamp(tapped))|4,10 €||Le Comptoir\n".write(to: file, atomically: true, encoding: .utf8)
        WalletInbox.drain(store: store, at: file, now: tapped)

        #expect(try Data(contentsOf: file).isEmpty)
        #expect(WalletInbox.drain(store: store, at: file, now: tapped) == 0)
    }

    /// Le marchand est le dernier champ et garde tout ce qui suit : c'est le
    /// seul dont on ne choisit pas le contenu.
    @Test("a merchant carrying the separator survives")
    func merchantKeepsTheSeparator() throws {
        let entries = WalletInbox.parse("\(stamp(tapped))|4,10 €|MA BANQUE|Bar | Tabac")
        #expect(entries.count == 1)
        #expect(entries.first?.merchant == "Bar | Tabac")
    }

    /// Une heure illisible ne fait pas perdre le paiement — elle se dit.
    @Test("an unreadable time still records the payment, and says so")
    func unreadableTimeStillRecords() throws {
        let (store, file) = try ledger()
        try "n'importe quoi|4,10 €||Le Comptoir\n".write(to: file, atomically: true, encoding: .utf8)

        #expect(WalletInbox.drain(store: store, at: file, now: tapped) == 1)
        let attempt = try #require(WalletLog.recent(store: store).first)
        #expect(attempt.outcome == .recorded)
        #expect(attempt.detail?.isEmpty == false)
    }

    /// Le journal raconte les paiements, pas les rattrapages : une tentative
    /// reprise le soir pour un café de midi se lit à midi.
    @Test("the journal keeps the hour of the payment, not of the recovery")
    func journalKeepsThePaymentHour() throws {
        let (store, file) = try ledger()
        try "\(stamp(tapped))|4,10 €||Le Comptoir\n".write(to: file, atomically: true, encoding: .utf8)
        WalletInbox.drain(store: store, at: file, now: tapped.addingTimeInterval(36_000))

        let attempt = try #require(WalletLog.recent(store: store).first)
        let started = try #require(attempt.startedAt)
        #expect(abs(started.timeIntervalSince(tapped)) < 1)
    }

    /// Une ligne incomplète est ignorée, sans emporter les autres.
    @Test("a malformed line is skipped and the rest goes through")
    func malformedLineIsSkipped() throws {
        let entries = WalletInbox.parse(
            "\(stamp(tapped))|4,10 €\n\n\(stamp(tapped))|9,90 €|MA BANQUE|Chez Rosa\n"
        )
        #expect(entries.count == 1)
        #expect(entries.first?.merchant == "Chez Rosa")
    }

    /// Les formats de date que Raccourcis peut produire sans qu'on l'y force.
    @Test("the dates Shortcuts writes are all read")
    func datesAreRead() throws {
        #expect(WalletInbox.date(from: "2026-09-28 14:23:05") != nil)
        #expect(WalletInbox.date(from: "2026-09-28T14:23:05+02:00") != nil)
        #expect(WalletInbox.date(from: "28/09/2026, 14:23") != nil)
        #expect(WalletInbox.date(from: "28/09/2026 14:23:05") != nil)
        #expect(WalletInbox.date(from: "28/09/2026 à 14:23") != nil)
        #expect(WalletInbox.date(from: "28/09/2026 à 14:23:05") != nil)
        #expect(WalletInbox.date(from: "") == nil)
    }

    /// Le fichier est créé vide pour que Raccourcis puisse le choisir : son
    /// champ de chemin ne se tape pas, il se sélectionne.
    @Test("the file is created empty so Shortcuts can point at it")
    func fileIsCreatedForThePicker() throws {
        let (_, file) = try ledger()
        WalletInbox.ensureExists(at: file)
        #expect(FileManager.default.fileExists(atPath: file.path))

        try "\(stamp(tapped))|4,10 €||Le Comptoir\n".write(to: file, atomically: true, encoding: .utf8)
        WalletInbox.ensureExists(at: file)
        #expect(try Data(contentsOf: file).isEmpty == false)
    }

    /// Rien à lire ne coûte rien et n'écrit rien : c'est le cas de presque
    /// toutes les ouvertures.
    @Test("no file, nothing done")
    func noFileNoWork() throws {
        let (store, file) = try ledger()
        #expect(WalletInbox.drain(store: store, at: file, now: tapped) == 0)
        #expect(try store.database.scalar("SELECT COUNT(*) FROM transactions")?.int == 0)
    }
}

/*
 * « 3 fois sans frais », et les autres.
 *
 * Le partage doit tomber juste au centime, les échéances doivent entrer comme
 * des opérations à venir pour que le rapprochement les éteigne, et surtout le
 * coût annoncé doit être ramené à l'année — 2,2 % de frais en trois fois, ce
 * n'est pas un crédit à 2,2 %.
 */
@Suite("Paying in instalments", .serialized)
struct InstalmentTests {
    private func ledger() throws -> (store: LocalStore, account: String) {
        let store = try LocalStore(
            url: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("florin-split-\(UUID().uuidString).db")
        )
        let account = UUID().uuidString
        try store.database.exec("""
        INSERT INTO accounts (id, name, kind, currency)
          VALUES ('\(account)', 'CCP', 'checking', 'EUR');
        """)
        return (store, account)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return calendar
    }

    @Test("the split is exact to the cent")
    func splitIsExact() {
        #expect(LocalInstalments.split(100, over: 3) == [33.34, 33.33, 33.33])
        #expect(LocalInstalments.split(300, over: 3) == [100, 100, 100])
        #expect(LocalInstalments.split(99.99, over: 4).reduce(0, +) == 99.99)
        #expect(LocalInstalments.split(40, over: 1) == [40])
    }

    /*
     * Un multiple ne s'annonce que lorsque c'en est un.
     *
     * Le récapitulatif affichait « 3 × 33,34 € » en face de « 100,00 € », et
     * trois fois 33,34 font 100,02 : il multipliait la première échéance,
     * celle-là même qui porte les centimes de l'arrondi.
     */
    @Test("the recap groups equal instalments and names the odd one")
    func describesTheRealShape() {
        let plain = { (v: Double) in String(format: "%.2f", v) }
        #expect(LocalInstalments.describe(LocalInstalments.split(99, over: 3), money: plain)
            == "3 × 33.00")
        #expect(LocalInstalments.describe(LocalInstalments.split(100, over: 3), money: plain)
            == "33.34 + 2 × 33.33")
        #expect(LocalInstalments.describe([33.33, 33.33, 33.34], money: plain)
            == "2 × 33.33 + 33.34")
        #expect(LocalInstalments.describe([], money: plain) == "")
    }

    /*
     * La mensualité annoncée fait foi, et la dernière échéance encaisse le
     * centime qui ne tombe pas juste — mais pas un euro : au-delà d'un centime
     * par échéance, l'écart est le coût de l'offre et doit rester visible.
     */
    @Test("a quoted instalment stands, and only rounding lands on the last")
    func quotedInstalmentsAbsorbOnlyRounding() {
        #expect(LocalInstalments.quoted(33.34, count: 3, total: 100)
            == [33.34, 33.34, 33.32])
        #expect(LocalInstalments.quoted(33.33, count: 3, total: 100)
            == [33.33, 33.33, 33.34])
        // Deux euros de frais sur trois échéances : pas un arrondi.
        #expect(LocalInstalments.quoted(34, count: 3, total: 100) == [34, 34, 34])
        #expect(LocalInstalments.quoted(20, count: 5, total: 100) == [20, 20, 20, 20, 20])
    }

    /// Les centimes se voient sur l'échéance qu'on paie au comptoir, la seule
    /// qu'on puisse confronter au ticket.
    @Test("the odd cents fall on the instalment paid at the till")
    func oddCentsComeFirst() {
        let parts = LocalInstalments.split(100, over: 3)
        #expect(parts.first == 33.34)
        #expect(parts.dropFirst().allSatisfy { $0 == 33.33 })
    }

    @Test("without fees the rate is nothing, not nothing-to-say")
    func freeCreditIsZero() {
        #expect(LocalInstalments.annualRate(purchase: 300, instalments: [100, 100, 100]) == 0)
    }

    /*
     * Le chiffre que l'offre ne montre pas.
     *
     * 2 % de frais sur trois fois, c'est un tiers remboursé tout de suite et
     * deux tiers prêtés un mois et deux mois. Ramené à l'année, on est très
     * au-delà de vingt pour cent — l'ordre de grandeur d'un découvert, pas
     * celui d'un prêt.
     */
    @Test("two percent of fees over three months is a quarter a year")
    func feesAreWorseThanTheySound() throws {
        let rate = try #require(
            LocalInstalments.annualRate(purchase: 300, instalments: [102, 102, 102])
        )
        #expect(rate > 0.20 && rate < 0.35)
    }

    /// Plus l'échéancier est long, moins les mêmes frais coûtent par an : on
    /// emprunte plus longtemps pour le même prix.
    @Test("the same fees spread further cost less per year")
    func longerIsCheaperPerYear() throws {
        let short = try #require(
            LocalInstalments.annualRate(purchase: 300, instalments: [102, 102, 102])
        )
        let long = try #require(
            LocalInstalments.annualRate(purchase: 300, instalments: LocalInstalments.split(306, over: 10))
        )
        #expect(long < short)
    }

    @Test("a single payment has no rate to speak of")
    func oneInstalmentHasNoRate() {
        #expect(LocalInstalments.annualRate(purchase: 300, instalments: [300]) == nil)
        #expect(LocalInstalments.annualRate(purchase: 0, instalments: [10, 10]) == nil)
    }

    @Test("the fees are what is handed back on top of the purchase")
    func feesAreTheExtra() {
        #expect(LocalInstalments.fees(purchase: 300, instalments: [102, 102, 102]) == 6)
        #expect(LocalInstalments.fees(purchase: 300, instalments: [100, 100, 100]) == 0)
    }

    /// Un 31 janvier ne déborde pas sur le 3 mars.
    @Test("a month later than the 31st is the end of the month")
    func monthEndDoesNotOverflow() throws {
        var parts = DateComponents()
        parts.year = 2027; parts.month = 1; parts.day = 31; parts.hour = 12
        let january = try #require(calendar.date(from: parts))
        let days = LocalInstalments.dates(from: january, count: 3, calendar: calendar)
        #expect(calendar.component(.month, from: days[1]) == 2)
        #expect(calendar.component(.day, from: days[1]) == 28)
        #expect(calendar.component(.month, from: days[2]) == 3)
        #expect(calendar.component(.day, from: days[2]) == 31)
    }

    @Test("each instalment enters as an upcoming payment, a month apart")
    func instalmentsEnterTheLedger() throws {
        let (store, account) = try ledger()
        var parts = DateComponents()
        parts.year = 2027; parts.month = 3; parts.day = 10; parts.hour = 12
        let day = try #require(calendar.date(from: parts))

        let written = try LocalInstalments.record(
            store: store, accountId: account, payee: "Le Comptoir", memo: nil,
            categoryId: nil, from: day, instalments: LocalInstalments.split(300, over: 3),
            calendar: calendar
        )
        #expect(written == 3)

        let rows = try store.database.query(
            "SELECT occurred_at, amount, status, memo FROM transactions ORDER BY occurred_at"
        )
        #expect(rows.count == 3)
        #expect(rows.allSatisfy { $0.string("status") == "scheduled" })
        #expect(rows.allSatisfy { $0.double("amount") == -100 })
        #expect(rows.map { String(($0.string("occurred_at") ?? "").prefix(10)) }
                == ["2027-03-10", "2027-04-10", "2027-05-10"])
        #expect(rows.first?.string("memo")?.isEmpty == false)
    }

    /// La source est celle des opérations à venir, sans quoi le rapprochement
    /// ne les verrait pas et les échéances resteraient prévues pour toujours.
    @Test("the bank's own debit retires an instalment")
    func theBankSettlesAnInstalment() throws {
        let (store, account) = try ledger()
        var parts = DateComponents()
        parts.year = 2027; parts.month = 3; parts.day = 10; parts.hour = 12
        let day = try #require(calendar.date(from: parts))
        try LocalInstalments.record(
            store: store, accountId: account, payee: "Le Comptoir", memo: nil,
            categoryId: nil, from: day, instalments: [100, 100, 100], calendar: calendar
        )
        try store.database.run(
            """
            INSERT INTO transactions
                (id, account_id, occurred_at, amount, currency, payee, normalized_payee,
                 source, status, needs_review)
            VALUES (?, ?, '2027-03-12T10:00:00Z', -100, 'EUR', 'ACHAT CB LE COMPTOIR',
                    'achat cb le comptoir', 'enable_banking', 'cleared', 0)
            """,
            [.text(UUID().uuidString), .text(account)]
        )

        #expect(try LocalWallet.settle(store: store) == 1)
        let left = try #require(try store.database.scalar(
            "SELECT COUNT(*) FROM transactions WHERE status = 'scheduled' AND deleted_at IS NULL"
        )?.int)
        #expect(left == 2)
    }
}

// MARK: - Spending nobody has filed

/*
 * Une journée affichée à zéro sous la liste de ses propres dépenses.
 *
 * Le total du jour joignait la table des catégories, ce qui écartait
 * silencieusement tout ce qui n'en avait pas — et une dépense non classée
 * reste de l'argent parti.
 */
@Suite("Unfiled spending")
struct UnfiledSpendingTests {
    private func ledger() throws -> (LocalStore, account: String, category: String) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("florin-unfiled-\(UUID().uuidString).db")
        let store = try LocalStore(url: url)
        let account = UUID().uuidString, group = UUID().uuidString, category = UUID().uuidString
        try store.database.exec("""
        INSERT INTO accounts (id, name, kind, currency)
          VALUES ('\(account)', 'CCP', 'checking', 'EUR');
        INSERT INTO category_groups (id, name, kind) VALUES ('\(group)', 'Courses', 'expense');
        INSERT INTO categories (id, group_id, name) VALUES ('\(category)', '\(group)', 'Alimentation');
        """)
        return (store, account, category)
    }

    private func row(
        _ store: LocalStore, _ account: String, _ amount: Double, category: String?,
        pending: Bool = false, day: String = "2026-09-25"
    ) throws {
        try store.database.run(
            """
            INSERT INTO transactions
                (id, account_id, occurred_at, amount, currency, payee, normalized_payee,
                 source, status, is_pending, needs_review, category_id)
            VALUES (?, ?, ?, ?, 'EUR', 'Le Comptoir', 'le comptoir',
                    'enable_banking', ?, ?, 0, ?)
            """,
            [.text(UUID().uuidString), .text(account), .text("\(day)T12:00:00Z"), .real(amount),
             .text(pending ? "scheduled" : "cleared"), .integer(pending ? 1 : 0),
             category.map { SQLiteValue.text($0) } ?? .null]
        )
    }

    @Test("money that left without a category is still money that left")
    func unfiledSpendingCounts() throws {
        let (store, account, _) = try ledger()
        try row(store, account, -91, category: nil)

        let day = try LocalDay.detail(store: store, day: "2026-09-25")
        #expect(day.spent == 91)
    }

    @Test("it shows as its own slice, unnamed")
    func unfiledHasItsOwnSlice() throws {
        let (store, account, category) = try ledger()
        try row(store, account, -91, category: nil)
        try row(store, account, -9, category: category)

        let day = try LocalDay.detail(store: store, day: "2026-09-25")
        #expect(day.spent == 100)
        let unfiled = try #require(day.categories.first { $0.id == LocalAnalysis.uncategorized })
        #expect(unfiled.amount == 91)
        #expect(unfiled.name.isEmpty)
        #expect(day.categories.reduce(0) { $0 + $1.amount } == day.spent)
    }

    /// Un mouvement rentrant sans catégorie n'est pas une dépense : rien ne
    /// dit ce qu'il est, et le compter effacerait des dépenses réelles.
    @Test("an unfiled credit is not spending")
    func unfiledCreditIsNotSpending() throws {
        let (store, account, _) = try ledger()
        try row(store, account, -91, category: nil)
        try row(store, account, 500, category: nil)

        let day = try LocalDay.detail(store: store, day: "2026-09-25")
        #expect(day.spent == 91)
    }

    /// Une carte présentée est de l'argent parti, que la banque l'ait
    /// comptabilisée ou non : l'attendre un à trois jours affichait zéro sur
    /// la semaine en cours, la seule qu'on regarde.
    @Test("a payment the bank has not booked yet still counts")
    func pendingCountsToo() throws {
        let (store, account, category) = try ledger()
        try row(store, account, -1.50, category: nil, pending: true)
        try row(store, account, -9.90, category: category, pending: true)

        let day = try LocalDay.detail(store: store, day: "2026-09-25")
        #expect(day.spent == 11.40)
    }

    /// Un virement entre ses propres comptes n'est toujours pas une dépense.
    @Test("a transfer is still not spending")
    func transferIsStillNotSpending() throws {
        let (store, account, category) = try ledger()
        try row(store, account, -9, category: category)
        try store.database.run(
            """
            INSERT INTO transactions
                (id, account_id, occurred_at, amount, currency, payee, normalized_payee,
                 source, status, is_pending, needs_review, category_id, transfer_pair_id)
            VALUES (?, ?, '2026-09-25T12:00:00Z', -300, 'EUR', 'Virement', 'virement',
                    'enable_banking', 'cleared', 0, 0, ?, 'pair-1')
            """,
            [.text(UUID().uuidString), .text(account), .text(category)]
        )

        let day = try LocalDay.detail(store: store, day: "2026-09-25")
        #expect(day.spent == 9)
    }
}
