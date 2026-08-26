import Foundation

/// The device's own copy of the ledger.
///
/// The app is a thin client today: every figure on every screen is computed on
/// a server and fetched over HTTP, so with no network there is nothing to show.
/// This is the first piece of the way out of that — a real database on the
/// phone, holding the same schema the desktop build already uses, so the
/// arithmetic can move here one query at a time and be checked against the
/// server's answer while both still exist.
///
/// It deliberately does not yet own anything. Nothing reads from it until a
/// ported query has been proved to agree with the live figures to the cent.
final class LocalStore {
    static let shared = try? LocalStore()

    let database: SQLiteDatabase
    let url: URL

    init(url: URL? = nil) throws {
        let resolved = try url ?? Self.defaultURL()
        self.url = resolved
        database = try SQLiteDatabase(path: resolved.path)
        try migrate()
    }

    /// Application Support, not Documents.
    ///
    /// Documents is user-visible in Files and gets backed up as documents; a
    /// database is neither. Application Support is where a private store
    /// belongs, and it is the same choice the desktop build makes.
    private static func defaultURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = base.appendingPathComponent("Florin", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var file = folder.appendingPathComponent("florin.db")
        /*
         * Excluded from iCloud backup, on purpose.
         *
         * A WAL database restored mid-write is a corrupt database, and this one
         * is reconstructible: it is a local projection of a ledger that is
         * either on the user's server or re-derivable from their bank. Backing
         * it up trades a real corruption risk for a convenience we do not need.
         */
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? file.setResourceValues(values)
        return file
    }

    private func migrate() throws {
        try database.exec(LocalSchema.ddl)
        // `settings` is exactly (key, value) in this schema — no timestamps.
        try database.run(
            "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
            [.text("schema_version"), .text(String(LocalSchema.version))]
        )
    }

    // MARK: - Facts about what is here

    /// How many live transactions the device holds. Zero means "never seeded".
    func transactionCount() throws -> Int {
        try database.scalar(
            "SELECT count(*) FROM transactions WHERE deleted_at IS NULL"
        )?.int ?? 0
    }

    /// The newest and oldest dates held, for showing what a seed actually got.
    func dateRange() throws -> (earliest: String, latest: String)? {
        let rows = try database.query(
            """
            SELECT min(occurred_at) AS earliest, max(occurred_at) AS latest
            FROM transactions WHERE deleted_at IS NULL
            """
        )
        guard let row = rows.first,
              let earliest = row.string("earliest"),
              let latest = row.string("latest")
        else { return nil }
        return (earliest, latest)
    }
}

import OSLog

extension LocalStore {
    private static let log = Logger(subsystem: "com.adrbn.florin", category: "local-store")

    /// Open the store once at launch and report what is in it.
    ///
    /// Deliberately non-fatal: the app does not depend on this yet, so a
    /// failure here must not stop someone using the client they already have.
    /// It is loud in the log precisely because a silent failure would let the
    /// schema rot until the first ported query trips over it.
    /*
     * A one-shot self-test for the banking key, behind a debug flag.
     *
     * The signing path cannot be checked by reading it: a JWT with a subtly
     * wrong DER header or a base64 variant that keeps its padding is accepted
     * by every compiler and rejected by Enable Banking with a 401 that says
     * nothing. This makes the phone produce a real key, a real PEM and a real
     * signature so they can be verified against an independent implementation
     * before any bank is involved.
     */
    static func probeBankingKey() {
        guard ProcessInfo.processInfo.environment["FLORIN_BANKING_SELFTEST"] == "1" else { return }
        do {
            try BankingKey.generate()
            let pem = try BankingKey.publicKeyPEM()
            let token = try EnableBanking.jwt(
                .init(appId: "selftest-app-id", redirectURL: "florin://banking/callback")
            )
            // One line, unwrapped: a PEM read back out of a multi-line log is
            // one dropped line away from looking like a broken key.
            let flat = pem
                .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
                .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
                .replacingOccurrences(of: "\n", with: "")
            log.notice("banking selftest spki \(flat, privacy: .public)")

            // The certificate is what Enable Banking's console actually takes;
            // a bare public key is rejected there.
            let certificate = try BankingKey.certificatePEM()
            let flatCertificate = certificate
                .replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
                .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
                .replacingOccurrences(of: "\n", with: "")
            log.notice("banking selftest cert \(flatCertificate, privacy: .public)")
            log.notice("banking selftest jwt \(token, privacy: .public)")
        } catch {
            log.error("banking selftest failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func probeAtLaunch() {
        do {
            probeBankingKey()
            let store = try LocalStore()
            // A fresh install gets the same starting categories the other
            // surfaces create, so the first screen is a budget and not a form.
            let seeded = try LocalBootstrap.run(
                on: store,
                locale: Locale.current.identifier
            )
            let count = try store.transactionCount()
            let categories = try store.categoryCount()
            let range = try store.dateRange()
            log.notice("""
                local ledger ready at \(store.url.path, privacy: .public) \
                — schema v\(LocalSchema.version) \
                — \(count) transactions, \(categories) categories\(seeded ? " (just seeded)" : "", privacy: .public) \
                \(range.map { "(\($0.earliest) … \($0.latest))" } ?? "(empty)", privacy: .public)
                """)
        } catch {
            log.error("local ledger unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }
}
