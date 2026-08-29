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
        try LocalImport.parse(data: Data(text.utf8), fileName: file)
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

    @Test("an ambiguous date is European, and an impossible one is refused")
    func dates() {
        #expect(LocalImport.date(from: "03/04/2026") == "2026-04-03")
        #expect(LocalImport.date(from: "13/04/2026") == "2026-04-13")
        // The desktop turns this into month thirteen. Refusing is the point.
        #expect(LocalImport.date(from: "04/13/2026") == nil)
        #expect(LocalImport.date(from: "2026-08-28") == "2026-08-28")
        #expect(LocalImport.date(from: "20260828") == "2026-08-28")
    }

    @Test("French numbers, including a trailing minus and a thin space")
    func numbers() {
        #expect(LocalImport.number("1 234,56") == 1234.56)
        #expect(LocalImport.number("-1.234,56") == -1234.56)
        #expect(LocalImport.number("42,49-") == -42.49)
        #expect(LocalImport.number("\u{202F}2 998,98") == 2998.98)
        #expect(LocalImport.number("") == nil)
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
