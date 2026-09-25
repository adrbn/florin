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
 * The same loan the server's own tests use, and the same reference: a real
 * statement from La Banque Postale. 10 000 € over 84 months at an advertised
 * 3,90 %, instalment 135,91 €, first payment 30 June 2024.
 *
 * The phone reported this loan's debt as the sum of the repayments sitting on
 * the loan account — 3 543 € after twenty-six instalments, which is the money
 * already paid. The bank's capital restant dû at that point is a little over
 * seven thousand.
 */
@Suite("Loan")
struct LoanTests {
    private let principal = 10_000.0
    private let rate = 0.039
    private let term = 84
    private let payment = 135.91

    private func debt(after payments: Int) -> Double {
        LocalLoan.liability(
            principal: principal, annualRate: rate, termMonths: term,
            monthlyPayment: payment, paymentsMade: payments
        ).remainingDebt
    }

    @Test("the periodic rate is recovered from principal, payment and term")
    func calibration() {
        // The bank quotes the TAEG and amortises on the taux débiteur; taking
        // the advertised rate drifts a few euros and spills an extra month.
        let solved = LocalLoan.solveAnnualRate(
            principal: principal, monthlyPayment: payment, termMonths: term
        )
        #expect(solved != nil)
        #expect(abs((solved ?? 0) - 0.0383) < 0.0005)
        // And it reproduces the instalment it was solved from.
        let check = LocalLoan.monthlyPayment(
            principal: principal, annualRate: solved ?? 0, termMonths: term
        )
        #expect(abs(check - payment) < 0.01)
    }

    @Test("capital restant dû lands within a euro of the bank's own figure")
    func matchesTheBank() {
        // The statement says 7 298,12 € after twenty-five instalments. This is
        // the assertion the server makes, so the two builds agree by
        // construction rather than by coincidence.
        #expect(abs(debt(after: 25) - 7298.12) < 1)
    }

    @Test("what is owed is not what has been paid")
    func notTheAmountPaid() {
        // Twenty-six instalments of 135,91 € is 3 533,66 € handed over — the
        // number the phone used to print as the debt. The debt is more than
        // twice that.
        let paid = 26.0 * payment
        #expect(debt(after: 26) > 7_000)
        #expect(abs(debt(after: 26) - paid) > 3_500)
    }

    @Test("each instalment moves it, which is what validating one is for")
    func eachPaymentCounts() {
        let before = debt(after: 25)
        let after = debt(after: 26)
        #expect(after < before)
        // Early in a loan most of the instalment is interest, so the debt
        // falls by less than the 135,91 € paid.
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
          VALUES ('\(loan)', 'Prêt', 'loan', 'EUR', 10000, 0.039, 84, 135.91, '2024-06-30');
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
            VALUES (?, ?, '2026-08-05', -135.91, 'EUR', 'PRELEVEMENT LBP', 'prelevement lbp',
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
        #expect(row?.double("amount") == 135.91)
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
        // less than the 135,91 € handed over.
        #expect(before - after < 135.91)
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
            VALUES (?, ?, '2026-08-05', 135.91, 'EUR', '↳ PRELEVEMENT LBP', 'prelevement lbp',
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
            VALUES (?, ?, '2026-09-01', 135.91, 'EUR', '↳ x', 'x', 'server', 'cleared', 0, ?)
            """,
            [.text(UUID().uuidString), .text(loan), .text(UUID().uuidString)]
        )
        let id = UUID().uuidString
        try store.database.run(
            """
            INSERT INTO transactions
                (id, account_id, occurred_at, amount, currency, payee, normalized_payee,
                 source, status, needs_review)
            VALUES (?, ?, '2026-08-30', -135.91, 'EUR', 'PRELEVEMENT LBP', 'prelevement lbp',
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
                VALUES (?, ?, '2026-08-05', 135.91, 'EUR', '↳ x', 'x', 'manual', 'cleared', 0, ?)
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
          VALUES ('\(conn)', 'enable_banking', 's-\(conn)', 'active', 'LBP', 'FR', '2026-12-01');
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
            store, on: account, amount: -135.91, payee: "PREL DE LA BANQUE POSTALE",
            externalId: "uid:2026-08-31T00:00:00Z:-135.91:PREL DE LA BANQUE POSTALE"
        )
        let stale = try row(
            store, on: account, amount: -135.91, payee: "PRELEVEMENT DE LA BANQUE POSTALE",
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
            store, on: account, amount: -135.91, payee: "PREL DE LA BANQUE POSTALE",
            externalId: "uid:2026-08-31T00:00:00Z:-135.91:PREL", pair: "orphan"
        )
        try row(
            store, on: account, amount: -135.91, payee: "PRELEVEMENT DE LA BANQUE POSTALE",
            externalId: "uid:2026-08-31.0", pair: "real"
        )
        try row(
            store, on: loan, amount: 135.91, payee: "↳ PRELEVEMENT",
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
