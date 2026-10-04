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
         * Backed up. The reasoning that excluded it has expired.
         *
         * It was excluded because a WAL database restored mid-write is corrupt,
         * and because this one was "a local projection of a ledger that is
         * either on the user's server or re-derivable from their bank". That
         * second clause is what justified the trade, and it is no longer true:
         * this ledger now holds accounts, transactions, transfers, categories
         * and budgets that exist nowhere else. Losing the phone would lose them
         * outright.
         *
         * The corruption risk is real and is answered where it arises — the
         * write-ahead log is checkpointed when the app leaves the foreground,
         * so what a backup captures is a settled file rather than a database
         * caught mid-sentence. Apple asks that regenerable caches stay out of
         * backups; a person's own ledger is the opposite of regenerable.
         */
        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        try? file.setResourceValues(values)
        return file
    }

    private func migrate() throws {
        try database.exec(LocalSchema.ddl)
        try addBankPayee()
        /*
         * Une image choisie à la main pour un marchand.
         *
         * Le site d'un petit commerçant n'a souvent pas d'icône — ou pas de
         * site du tout — et l'emoji ne fait pas toujours l'affaire. Même
         * raison que `bank_payee` pour l'`ALTER` : un grand livre déjà créé
         * ne gagne pas une colonne par `CREATE TABLE IF NOT EXISTS`.
         */
        try addColumn("merchant_marks", "image", "BLOB")
        /*
         * La date à laquelle la banque a comptabilisé, distincte de celle
         * qu'elle avait annoncée.
         *
         * Enable Banking envoie trois dates — `booking_date`, `transaction_date`,
         * `value_date` — et le grand livre n'en gardait qu'une, la première
         * non nulle. Or c'est justement la présence de `booking_date` qui
         * sépare une opération passée d'une opération promise. On la garde
         * telle quelle : vide tant que la banque n'a rien comptabilisé.
         */
        try addColumn("transactions", "booked_at", "TEXT")
        /*
         * L'échéancier auquel une échéance appartient.
         *
         * Les échéances d'un achat en plusieurs fois s'écrivaient comme des
         * opérations à venir ordinaires, et rien ne les en distinguait : une
         * seule chose les reliait, un mémo traduit « En 4 fois (1/4) », qu'on
         * ne va pas se mettre à relire pour construire un écran.
         *
         * Un même identifiant sur les N lignes suffit, et se contente d'être
         * vide partout ailleurs — les opérations déjà écrites restent donc
         * exactement ce qu'elles étaient.
         */
        try addColumn("transactions", "instalment_plan_id", "TEXT")
        /*
         * Le prix d'achat, que les échéances ne disent pas.
         *
         * Un achat de 100 € en 3 fois avec 2 € de frais entre au grand livre
         * comme trois lignes de 34 € : le prix affiché en magasin n'y figure
         * nulle part, et les 2 € de frais sont donc irrécupérables une fois la
         * sheet fermée. Or c'est le seul chiffre qui dise ce que la facilité
         * de paiement coûte vraiment (voir `LocalInstalments.annualRate`).
         *
         * Une table à part plutôt qu'une colonne sur les lignes : le prix est
         * un fait de l'échéancier, pas de chacune de ses échéances, et le
         * rapprochement bancaire retire les lignes une par une — celle qui
         * aurait porté le prix finirait par disparaître. Table propre à
         * l'appareil, comme l'échéancier lui-même : le serveur n'a pas cette
         * notion, donc elle ne figure pas dans `LocalSchema`, qui est le
         * schéma de `db-sqlite` tel quel.
         */
        try database.exec(
            """
            CREATE TABLE IF NOT EXISTS instalment_plans (
                id TEXT PRIMARY KEY,
                purchase REAL NOT NULL,
                purchased_on TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
              );
            """
        )
        try adoptOlderInstalmentPlans()
        try carryPlansThroughSettlement()
        try priceOlderPlansAtWhatTheyCharged()
        try rekeyMerchantNames()
        // `settings` is exactly (key, value) in this schema — no timestamps.
        try database.run(
            "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
            [.text("schema_version"), .text(String(LocalSchema.version))]
        )
        try repairOpeningBalances()
    }

    /*
     * Ce que la banque, elle, appelait cette ligne.
     *
     * `payee` est à la fois le libellé de la banque et le nom que son
     * propriétaire lui donne : renommer une opération efface le premier. Or
     * c'est le premier que la synchro interroge pour reconnaître une ligne
     * qu'elle a déjà écrite — un virement annoncé puis renommé devenait
     * méconnaissable à sa propre banque, revenait en double, et la version
     * corrigée était effacée comme doublon. La banque écrit désormais son
     * libellé dans une colonne à elle, qu'une modification ne touche pas.
     *
     * Le schéma est en `IF NOT EXISTS`, qui ne fait rien à une table déjà là :
     * un grand livre existant ne gagne la colonne que par un `ALTER TABLE`, et
     * SQLite n'a pas d'`ADD COLUMN IF NOT EXISTS`. Demander ce que la table
     * contient est la seule façon de savoir.
     *
     * Les lignes déjà écrites la remplissent quand leur clé porte encore le
     * libellé d'origine — c'est le cas des annonces, que la banque publie sans
     * référence stable, donc précisément celles qui se font renommer.
     */
    /*
     * Les renommages, recalés quand la règle qui les range change.
     *
     * Un nom donné à la main est rangé sous la clé du marchand, et cette clé
     * est ce que `MerchantNames.merchantWords` tire du libellé. Resserrer ce
     * calcul — retirer la forme juridique, le numéro de caisse — déplace donc
     * les clés : « prel de telecom sa » devient « telecom », et le renommage
     * rangé sous l'ancienne clé ne répond plus à rien. Silencieusement : la
     * ligne réaffiche le libellé de la banque comme si on ne l'avait jamais
     * renommée.
     *
     * Les clés sont donc réécrites par la règle du jour. Rien à versionner :
     * le calcul est un point fixe, donc une clé déjà à jour ne bouge pas et la
     * passe ne fait rien aux lancements suivants.
     *
     * Deux anciennes clés peuvent se ranger sous la même nouvelle — « le
     * comptoir » et « le comptoir srl ». `OR REPLACE` garde la dernière
     * écrite, et l'ordre par `updated_at` fait que c'est la plus récente.
     */
    private func rekeyMerchantNames() throws {
        for table in ["payee_aliases", "merchant_marks"] {
            let rows = try database.query("SELECT match_key FROM \(table) ORDER BY updated_at ASC")
            for row in rows {
                guard let old = row.string("match_key") else { continue }
                // Une clé de série n'est pas un libellé : la recalculer la
                // détruirait.
                if old.hasPrefix(MerchantNames.seriesSign) { continue }
                let fresh = MerchantNames.key(old)
                guard fresh != old, !fresh.isEmpty else { continue }
                try database.run(
                    "UPDATE OR REPLACE \(table) SET match_key = ? WHERE match_key = ?",
                    [.text(fresh), .text(old)]
                )
            }
        }
    }

    /// Ajoute une colonne à une table déjà créée. SQLite n'a pas d'`ADD COLUMN
    /// IF NOT EXISTS` : lire la table est la seule façon de savoir.
    private func addColumn(_ table: String, _ column: String, _ type: String) throws {
        let columns = try database.query("PRAGMA table_info(\(table))")
        guard !columns.contains(where: { $0.string("name") == column }) else { return }
        try database.run("ALTER TABLE \(table) ADD COLUMN \(column) \(type)")
    }

    private func addBankPayee() throws {
        let columns = try database.query("PRAGMA table_info(transactions)")
        guard !columns.contains(where: { $0.string("name") == "bank_payee" }) else { return }
        try database.run("ALTER TABLE transactions ADD COLUMN bank_payee TEXT")
        let rows = try database.query(
            "SELECT id, external_id FROM transactions WHERE source = 'enable_banking'"
        )
        for row in rows {
            guard let id = row.string("id"),
                  let label = LocalWallet.bankLabel(inKey: row.string("external_id") ?? "")
            else { continue }
            try database.run(
                "UPDATE transactions SET bank_payee = ? WHERE id = ?", [.text(label), .text(id)]
            )
        }
    }

    /*
     * Rendre vrai l'invariant dont tout le reste dépend.
     *
     * `LocalLedger.recomputeBalance` recalcule un solde comme
     * `ouverture + Σ lignes` après chaque ajout, suppression ou appariement.
     * C'est juste — à condition que l'ouverture soit le solde réel du compte
     * au premier jour connu de son historique.
     *
     * Sur un grand livre repris d'ailleurs, elle ne l'est pas. Un livret
     * repris peut porter quelques lignes pour deux ans, dont la somme n'a rien
     * à voir avec l'ouverture ni avec le solde réel. Un tel compte est à **une
     * seule opération** de s'effondrer sur un chiffre arbitraire — et c'est
     * arrivé, sous zéro après une correction d'un euro.
     *
     * Le solde affiché fait foi : c'est celui que la banque a posé, ou celui
     * que son propriétaire a saisi. L'ouverture absorbe l'écart, c'est-à-dire
     * la part de l'histoire que Florin n'a jamais vue — ce pour quoi elle
     * existe. Une fois par ouverture de base, et sans effet là où les comptes
     * étaient déjà cohérents.
     */
    /// Rattache les échéanciers saisis avant que la colonne n'existe.
    ///
    /// Ceux-là n'ont que leur mémo pour dire ce qu'ils sont, et un mémo est
    /// traduit : on ne construit pas un regroupement là-dessus. Ce qui les
    /// identifie sans ambiguïté, c'est leur écriture — un échéancier naît
    /// d'une seule boucle, donc ses lignes partagent la seconde
    /// d'enregistrement, le compte et l'enseigne, tout en tombant à des dates
    /// différentes. Aucune autre écriture de l'app ne produit cela : une
    /// automatisation Wallet écrit une ligne, pas plusieurs échelonnées.
    ///
    /// L'identifiant reconstruit n'est pas un UUID mais la clé du groupe
    /// elle-même : deux passages donnent le même résultat, et la reprise peut
    /// donc rejouer sans jamais scinder un plan déjà rattaché.
    private func adoptOlderInstalmentPlans() throws {
        try database.run(
            """
            UPDATE transactions AS t
               SET instalment_plan_id = 'legacy:' || t.account_id || ':'
                   || t.normalized_payee || ':' || t.recorded_at
             WHERE t.instalment_plan_id IS NULL
               AND t.source = 'ios_shortcut'
               AND EXISTS (
                     SELECT 1 FROM transactions o
                      WHERE o.id <> t.id
                        AND o.account_id = t.account_id
                        AND o.normalized_payee = t.normalized_payee
                        AND o.recorded_at = t.recorded_at
                        AND o.occurred_at <> t.occurred_at
                   )
            """
        )
    }

    /*
     * Un échéancier survit à son prélèvement.
     *
     * Quand la banque prélève une échéance, `LocalWallet.settle` retire la
     * ligne annoncée et garde celle de la banque — mais l'identifiant
     * d'échéancier restait sur la ligne retirée. Un paiement en quatre fois
     * perdait donc un membre à chaque prélèvement : « 4 échéances » devenait
     * « 3 », puis « 2 », et « 2 sur 4 payées » était inécrivable puisque les
     * payées n'étaient plus du plan.
     *
     * `settle` le transporte désormais. Pour les échéances déjà éteintes, la
     * ligne retirée pointe encore vers celle qui l'a remplacée
     * (`merge_suggested_tx_id`) : le lien est exact, il suffit de le suivre.
     */
    private func carryPlansThroughSettlement() throws {
        try database.run(
            """
            UPDATE transactions AS b
               SET instalment_plan_id = (
                       SELECT t.instalment_plan_id FROM transactions t
                        WHERE t.merge_suggested_tx_id = b.id
                          AND t.instalment_plan_id IS NOT NULL
                        LIMIT 1
                   )
             WHERE b.instalment_plan_id IS NULL
               AND EXISTS (
                     SELECT 1 FROM transactions t
                      WHERE t.merge_suggested_tx_id = b.id
                        AND t.instalment_plan_id IS NOT NULL
                   )
            """
        )
    }

    /*
     * Les échéanciers d'avant le prix d'achat valent ce qu'ils ont prélevé.
     *
     * Rien ne permet de retrouver un prix qui n'a jamais été écrit, et
     * inventer des frais serait pire que de n'en pas afficher : on prend donc
     * la somme des échéances, c'est-à-dire l'hypothèse « sans frais », qui est
     * celle de la quasi-totalité des offres en plusieurs fois et la seule que
     * le grand livre atteste. `INSERT OR IGNORE` : un échéancier déjà tarifé
     * n'est jamais réécrit, et la reprise peut donc rejouer à chaque lancement.
     */
    private func priceOlderPlansAtWhatTheyCharged() throws {
        try database.run(
            """
            INSERT OR IGNORE INTO instalment_plans (id, purchase, purchased_on)
            SELECT t.instalment_plan_id,
                   round(sum(abs(t.amount)), 2),
                   min(substr(t.occurred_at, 1, 10))
              FROM transactions t
             WHERE t.instalment_plan_id IS NOT NULL AND t.deleted_at IS NULL
             GROUP BY t.instalment_plan_id
            """
        )
    }

    private func repairOpeningBalances() throws {
        try database.run(
            """
            UPDATE accounts
            SET opening_balance = round((current_balance - coalesce((
                    SELECT sum(t.amount) FROM transactions t
                    WHERE t.account_id = accounts.id AND t.deleted_at IS NULL
                      AND t.status = 'cleared'
                ), 0)) * 100) / 100.0
            WHERE kind <> 'broker_portfolio'
              AND abs(
                opening_balance + coalesce((
                    SELECT sum(t.amount) FROM transactions t
                    WHERE t.account_id = accounts.id AND t.deleted_at IS NULL
                      AND t.status = 'cleared'
                ), 0) - current_balance
              ) > 0.005
            """
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

    /*
     * Settle the write-ahead log.
     *
     * A backup taken while the -wal file holds uncommitted pages restores a
     * database caught mid-sentence. Folding it back into the main file when the
     * app leaves the foreground means whatever iCloud copies is a whole ledger
     * — which is the condition under which including it in backups is safe at
     * all.
     */
    static func checkpoint() {
        guard let store = shared else { return }
        try? store.database.exec("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    /*
     * Le rangement du lancement, hors du premier frame.
     *
     * Il tournait dans `App.init()`, donc avant que SwiftUI ait dessiné quoi
     * que ce soit : migration, amorçage, cinq réparations et une passe du
     * catégoriseur, pendant lesquelles iOS n'avait rien d'autre à montrer que
     * l'aplat noir de l'écran de lancement. On le voyait flasher.
     *
     * Rien ne justifiait cet ordre. La pièce du splash tourne deux secondes et
     * l'aperçu se charge derrière elle ; le rangement tient largement dedans.
     * Il part donc au lancement sur un fil à lui, avec sa propre connexion —
     * la base est en WAL avec un délai d'attente, deux connexions s'y
     * côtoient — et la première lecture de l'aperçu l'attend, pour ne jamais
     * afficher un doublon que la passe allait retirer.
     */
    static let launchPass = Task.detached(priority: .userInitiated) {
        probeAtLaunch()
    }

    /// Rend la main une fois le rangement du lancement terminé. Immédiat
    /// ensuite : une tâche finie rend sa valeur sans attendre.
    static func settled() async {
        await launchPass.value
    }

    private static func probeAtLaunch() {
        do {
            probeBankingKey()
            let store = try LocalStore()
            // A fresh install gets the same starting categories the other
            // surfaces create, so the first screen is a budget and not a form.
            let seeded = try LocalBootstrap.run(
                on: store,
                locale: Locale.current.identifier
            )
            /*
             * Name whatever arrived while the app was closed.
             *
             * The sync that brings rows in runs its own pass, but rows can
             * predate the categoriser — or land in a background sync whose
             * history was thinner than it is now. One indexed query when
             * nothing is waiting, so a ledger with no unfiled bank rows pays
             * almost nothing for it.
             */
            // Les paiements que Wallet a présentés pendant que la base était
            // fermée : repris avant tout le reste, puisque la suite les apparie.
            let resumed = WalletQueue.drain(store: store)
            if resumed > 0 {
                log.notice("resumed \(resumed, privacy: .public) payments held while closed")
            }
            // Puis le filet : ce que l'automatisation a écrit elle-même, pour
            // les fois où l'action de Florin n'a pas été appelée du tout.
            WalletInbox.drain(store: store)
            WalletInbox.ensureExists()

            // A duplicate left by an earlier build outlives the sync that
            // created it, so the repair has to run where every launch sees it.
            let unlabelled = try BankingSync.clearMirrorCategories(store: store)
            if unlabelled > 0 {
                log.notice("cleared \(unlabelled, privacy: .public) mirror categories")
            }

            let dropped = try BankingSync.collapseSettledDuplicates(store: store)
            if dropped > 0 {
                log.notice("dropped \(dropped, privacy: .public) settled duplicates")
            }

            let renamed = try BankingSync.restoreBankLabels(store: store)
            if renamed > 0 {
                log.notice("restored \(renamed, privacy: .public) bank labels")
            }

            let unadopted = try LocalWallet.repairAdopted(store: store)
            if unadopted > 0 {
                log.notice("restored \(unadopted, privacy: .public) card payments a sync had adopted")
            }
            _ = try LocalWallet.settle(store: store)

            let relabelled = try BankingSync.collapseRelabelledDuplicates(store: store)
            if relabelled > 0 {
                log.notice("dropped \(relabelled, privacy: .public) relabelled duplicates")
            }

            /*
             * Repayments filed before the mirror existed, given their
             * counterpart. Runs before the categoriser so a row it files this
             * launch is mirrored by the categoriser itself rather than waiting
             * for the next one.
             */
            // Before adding any, take back the ones a broken catch-up added.
            let undone = try LocalLedger.dropDuplicateLoanMirrors(store: store)
            if undone > 0 {
                log.notice("removed \(undone, privacy: .public) duplicate loan mirrors")
            }

            let mirrored = try LocalLedger.reconcileLoanMirrors(store: store)
            if mirrored > 0 {
                log.notice("wrote \(mirrored, privacy: .public) missing loan mirrors")
            }

            let named = try LocalCategoriser.backfill(store: store)
            if named > 0 {
                log.notice("categorised \(named, privacy: .public) waiting rows")
            }

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
