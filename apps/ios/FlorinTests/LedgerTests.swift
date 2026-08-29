import Foundation
import Testing
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
        27/08/2026;ACHAT CB FORNO CAMPO;-4,50
        27/08/2026;VIREMENT DE DIRECTION SPE FINANC;2 998,98
        """)
        #expect(parsed.count == 3)
        #expect(parsed[0].day == "2026-08-28")
        #expect(parsed[0].amount == 13.00)
        #expect(parsed[2].amount == 2998.98)
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
        Compte;N°1264549N035
        Solde au 28/08/2026;3 497,82
        Période;du 01/08/2026 au 28/08/2026

        Date;Libellé;Montant
        28/08/2026;VIREMENT INSTANTANE CREDIT;13,00
        27/08/2026;ACHAT CB FORNO CAMPO;-4,50
        """)
        #expect(parsed.count == 2)
        #expect(parsed[0].payee == "VIREMENT INSTANTANE CREDIT")
    }

    @Test("French numbers, including a trailing minus and a thin space")
    func numbers() {
        #expect(LocalImport.number("1 234,56") == 1234.56)
        #expect(LocalImport.number("-1.234,56") == -1234.56)
        #expect(LocalImport.number("42,49-") == -42.49)
        #expect(LocalImport.number("\u{202F}2 998,98") == 2998.98)
        #expect(LocalImport.number("") == nil)
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
        27/08/2026;ACHAT CB FORNO CAMPO;-4,50;-29,52
        """)
        #expect(parsed.count == 2)
        #expect(parsed[0].amount == 13.00)
    }

    @Test("Crédit Agricole: a download line, then débit and crédit columns")
    func creditAgricole() throws {
        let parsed = try rows("""
        Téléchargement du  19/03/2026;
        Date;Date valeur;Libellé;Débit Euros;Crédit Euros;
        15/03/2026;15/03/2026;VIREMENT SALAIRE;;2 998,98;
        16/03/2026;16/03/2026;CARTE INTERMARCHE;77,77;;
        """)
        #expect(parsed.map(\.amount) == [2998.98, -77.77])
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
