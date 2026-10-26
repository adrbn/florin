import Foundation

/// Payments recorded the moment a card is tapped, before the bank books them.
///
/// A Shortcuts automation on the Wallet "transaction" trigger hands Florin the
/// merchant and the amount at the till; the bank shows the same debit one to
/// three days later. In between, the money is spent and the ledger does not
/// know it. This writes the payment as an upcoming row, and lets the bank's
/// own row take its place when it lands.
///
/// The row is `scheduled` and pending: it shows under "upcoming" and in the
/// month's projection, but not in the balance. The balance of a synced account
/// is the bank's figure, and counting the payment there before the bank does
/// would have the next sync count it twice.
enum LocalWallet {
    /// The `source` these rows carry — what the reconciliation looks for.
    /// `ios_shortcut` has been in every schema's source list since the first
    /// migration, waiting for exactly this; Postgres rejects any other word,
    /// so mirroring the phone onto a server keeps these rows.
    static let source = "ios_shortcut"

    enum Failure: LocalizedError {
        case noStore
        case noAccount
        case serverMode
        case badAmount(String)

        var errorDescription: String? {
            switch self {
            case .noStore:
                Strings.device("v2.common.errorNoDatabase", "Florin n'a pas pu ouvrir sa base de données sur cet appareil.")
            case .noAccount:
                Strings.device("v2.wallet.noAccount", "Aucun compte courant dans Florin pour y ajouter ce paiement.")
            case .serverMode:
                Strings.device("v2.wallet.serverMode", "Florin affiche votre serveur : les paiements ne peuvent être ajoutés qu'aux comptes de cet appareil.")
            case .badAmount(let text):
                Strings.device("v2.wallet.badAmount", "Montant illisible : {amount}")
                    .replacingOccurrences(of: "{amount}", with: text)
            }
        }
    }

    /// What was recorded, for the automation's confirmation.
    struct Recorded {
        let payee: String
        let amount: Double
        let accountName: String
    }

    // MARK: - Recording

    /*
     * The amount as Wallet hands it over.
     *
     * The trigger's "Amount" arrives as text in the phone's own format —
     * "4,10 €", "€4.10", "1 234,56 €", sometimes with a narrow no-break space
     * as the thousands separator. A payment is always money leaving, so the
     * sign is ours to set.
     */
    static func parseAmount(_ text: String) -> Double? {
        var cleaned = text.filter { $0.isNumber || $0 == "," || $0 == "." }
        guard !cleaned.isEmpty else { return nil }
        if let comma = cleaned.lastIndex(of: ","), let dot = cleaned.lastIndex(of: ".") {
            // Whichever comes last is the decimal separator.
            if comma > dot {
                cleaned = cleaned.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            }
        } else if cleaned.contains(",") {
            cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        }
        guard let value = Double(cleaned), value > 0 else { return nil }
        return (value * 100).rounded() / 100
    }

    /// The account a payment lands on when the shortcut does not say: the
    /// first current account, the way the accounts list orders them.
    static func defaultAccount(store: LocalStore) throws -> (id: String, name: String)? {
        let row = try store.database.query(
            """
            SELECT id, name FROM accounts
            WHERE is_archived = 0 AND kind = 'checking'
            ORDER BY display_order, name LIMIT 1
            """
        ).first
        guard let id = row?.string("id") else { return nil }
        return (id, row?.string("name") ?? "")
    }

    /// Deux tapes identiques chez le même marchand à moins de ça d'écart sont
    /// la même tape. Large devant l'écart entre les chemins — le fichier date
    /// à la minute, l'action à la seconde — et étroit devant deux achats
    /// réellement distincts.
    static let sameTapWindow: TimeInterval = 300

    @discardableResult
    static func record(
        store: LocalStore,
        amountText: String,
        merchant: String,
        card: String?,
        accountId: String?,
        on day: Date = Date()
    ) throws -> Recorded {
        guard let amount = parseAmount(amountText) else { throw Failure.badAmount(amountText) }

        let account: (id: String, name: String)
        if let accountId,
           let name = try store.database.scalar(
               "SELECT name FROM accounts WHERE id = ? AND is_archived = 0", [.text(accountId)]
           )?.string {
            account = (accountId, name)
        } else if let fallback = try defaultAccount(store: store) {
            account = fallback
        } else {
            throw Failure.noAccount
        }

        let payee = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = payee.isEmpty ? "Apple Pay" : payee
        let memo = card.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : "Apple Pay · \($0)" } ?? "Apple Pay"

        /*
         * The hour of the tap, not midnight.
         *
         * Wallet knows when the card was presented, and a payment recorded at
         * midnight throws that away. Every screen reads the day out of
         * `substr(occurred_at, 1, 10)`, so the date stays the local one —
         * hence the local wall clock under a Z rather than a true instant.
         * Nothing sorts on the hour (`LocalQueries.readTransactions` explains
         * why it cannot), but the ledger should not be made to forget it.
         */
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: day
        )
        let occurred = String(
            format: "%04d-%02d-%02dT%02d:%02d:%02dZ",
            parts.year!, parts.month!, parts.day!, parts.hour!, parts.minute!, parts.second!
        )

        /*
         * La même tape, déjà écrite par l'autre chemin.
         *
         * Trois chemins mènent ici — l'action de Raccourcis, la file reprise
         * au lancement, le fichier rattrapé — et ils décrivent tous la même
         * carte présentée une fois. Le filet n'existait que du côté du
         * fichier, qui interroge le grand livre avant d'écrire : l'ordre
         * habituel voulait que l'action passe la première et que le fichier
         * se taise. Quand l'app se rouvre pendant que l'automatisation court,
         * l'ordre s'inverse, et plus rien ne retenait l'action.
         *
         * La question se pose donc ici, où tout le monde passe, plutôt qu'à
         * une entrée sur trois.
         */
        if alreadyRecorded(store: store, amount: amount, payee: label, at: day) {
            return Recorded(payee: label, amount: amount, accountName: account.name)
        }

        try insertUpcoming(
            store: store, accountId: account.id, occurredAt: occurred,
            amount: -amount, payee: label, memo: memo, categoryId: nil
        )
        return Recorded(payee: label, amount: amount, accountName: account.name)
    }

    /*
     * Deux tapes identiques de ce côté-ci de la fenêtre sont une seule tape.
     *
     * Les lignes supprimées comptent : une opération que la banque a reprise
     * est précisément celle qu'il ne faut pas réécrire.
     *
     * La fenêtre absorbe l'écart entre les chemins — le fichier date à la
     * minute, l'action à la seconde — et reste étroite devant deux achats
     * réellement distincts. Deux cafés du même prix à cinq minutes d'écart
     * sont possibles ; le second est alors perdu ici, et revient par la ligne
     * de la banque, qui finit toujours par arriver.
     */
    static func alreadyRecorded(
        store: LocalStore, amount: Double, payee: String, at moment: Date
    ) -> Bool {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.timeZone = .current
        stamp.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return alreadyRecorded(
            store: store, amount: amount, payee: payee, at: stamp.string(from: moment)
        )
    }

    /// La même question posée à une date déjà écrite — « 2026-10-19T10:00:00Z »
    /// comme le grand livre la garde, seconde comprise.
    static func alreadyRecorded(
        store: LocalStore, amount: Double, payee: String, at occurred: String
    ) -> Bool {
        let moment = occurred.prefix(19).replacingOccurrences(of: "T", with: " ")
        let name = payee.trimmingCharacters(in: .whitespacesAndNewlines)
        return (try? store.database.scalar(
            """
            SELECT 1 FROM transactions
            WHERE source = ? AND normalized_payee = ? AND abs(amount + ?) < 0.005
              AND abs(julianday(replace(substr(occurred_at, 1, 19), 'T', ' '))
                      - julianday(?)) * 86400.0 <= ?
            LIMIT 1
            """,
            [
                .text(source),
                .text(LocalLedger.normalize(name.isEmpty ? "Apple Pay" : name)),
                .real(amount), .text(String(moment)), .real(sameTapWindow),
            ]
        )) != nil
    }

    /*
     * The same row, entered by hand.
     *
     * The automation only fires when Wallet sees the payment, and Wallet sees
     * nothing without a connection — a card tapped in a shop with no signal
     * leaves no trace until the bank books it days later. Typed in from the
     * add sheet, the payment waits under "upcoming" and the bank's row takes
     * its place exactly as it would have for one recorded at the till.
     */
    static func recordUpcoming(store: LocalStore, _ tx: NewTransaction) throws {
        /*
         * Deux fois « Ajouter », une seule dépense.
         *
         * Le filet du même achat écrit deux fois était posé sur l'action et
         * sur le fichier de l'automatisation, pas sur la feuille de saisie —
         * qui écrit pourtant la même sorte de ligne. Deux envois à dix-sept
         * secondes d'intervalle ont donc donné deux fois le même sandwich,
         * dont un seul pouvait être repris par la ligne de la banque :
         * l'autre est resté « en prévision » pour toujours.
         *
         * Une échéance n'est pas concernée : les mensualités d'un même achat
         * sont à un mois l'une de l'autre, très loin de la fenêtre.
         */
        if alreadyRecorded(
            store: store, amount: -tx.amount, payee: tx.payee, at: tx.occurredAt
        ) { return }
        try insertUpcoming(
            store: store, accountId: tx.accountId, occurredAt: tx.occurredAt,
            amount: tx.amount, payee: tx.payee, memo: tx.memo,
            categoryId: tx.categoryId, instalmentPlanId: tx.instalmentPlanId
        )
    }

    /*
     * L'argent qui revient, annoncé le jour où on l'apprend.
     *
     * Un remboursement n'arrive jamais sur le coup : le commerçant le lance
     * quand ça l'arrange, et entre l'instant où l'on sait qu'il vient et
     * celui où la banque le crédite il y a des jours. Jusqu'ici la seule
     * façon de l'inscrire était la feuille de saisie, où tout est à retaper —
     * le bénéficiaire, le montant, la catégorie — alors que la ligne de la
     * dépense les porte déjà toutes.
     *
     * La date est celle du jour, pas celle de la dépense : c'est aujourd'hui
     * qu'on attend l'argent. La catégorie est reprise, sans quoi le
     * remboursement d'une course ne viendrait pas s'annuler là où la course a
     * été comptée. Le libellé est repris tel quel, et c'est lui qui ramène le
     * logo, le nom donné et le site — ils sont attachés au marchand, pas à la
     * ligne.
     *
     * Écrite comme un paiement annoncé, et c'est tout l'intérêt : `settle`
     * sait déjà faire céder la place à la ligne de la banque, et sait déjà
     * qu'un crédit peut se poser sur un crédit comptabilisé jusqu'à quinze
     * jours *avant* lui (voir son commentaire). Un remboursement saisi ici
     * est donc apparié tout seul le jour où la banque le passe, sans
     * doublon et sans un mot de code en plus.
     *
     * Rien dans les chiffres ne bouge en attendant : soldes, marge, reste à
     * dépenser et taux d'épargne ne comptent que les lignes `cleared`. Un
     * remboursement qui n'arriverait jamais encombre « en prévision » et ne
     * ment sur rien.
     */
    static func recordRefund(store: LocalStore, of tx: Transaction) throws {
        guard let accountId = tx.accountId else { throw Failure.noAccount }
        let today = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())
            ?? Date()
        let note = Strings.device("v2.refund.memo", "Remboursement attendu")
        try recordUpcoming(store: store, NewTransaction(
            accountId: accountId,
            amount: abs(tx.amount),
            payee: tx.payee,
            occurredAt: ISO8601DateFormatter.florinNoFraction.string(from: today),
            memo: note,
            categoryId: tx.categoryId,
            upcoming: true
        ))
    }

    private static func insertUpcoming(
        store: LocalStore, accountId: String, occurredAt: String,
        amount: Double, payee: String, memo: String?, categoryId: String?,
        instalmentPlanId: String? = nil
    ) throws {
        try store.database.run(
            """
            INSERT INTO transactions
                (id, account_id, occurred_at, amount, currency, payee, normalized_payee,
                 memo, category_id, source, instalment_plan_id,
                 status, is_pending, needs_review)
            VALUES (?, ?, ?, ?, 'EUR', ?, ?, ?, ?, ?, ?, 'scheduled', 1, 0)
            """,
            [
                .text(UUID().uuidString), .text(accountId), .text(occurredAt),
                .real(amount), .text(payee), .text(LocalLedger.normalize(payee)),
                memo.map { .text($0) } ?? .null, categoryId.map { .text($0) } ?? .null,
                .text(source), instalmentPlanId.map { .text($0) } ?? .null,
            ]
        )
        // Filed from history straight away, so the upcoming row already says
        // what it is — the café it has been every other time.
        _ = try? LocalCategoriser.backfill(store: store)
    }

    // MARK: - Letting the bank's row take over

    /*
     * The bank's row replaces the one recorded at the till.
     *
     * Same account, same amount to the cent, dated from the day of the tap to
     * a week after it — card payments reach the statement in one to three
     * working days, and a weekend or a bank holiday stretches that. Never
     * before: the bank cannot book a payment that has not happened, and a
     * day's slack backwards would let yesterday's identical coffee settle
     * today's. Each
     * bank row settles at most one payment, the nearest in date, so two coffees
     * at the same price on two days are two coffees.
     *
     * If the payment was filed while it waited and the bank's row was not, the
     * category moves across: it is the same purchase.
     */
    /*
     * The merchant first, then the date.
     *
     * Day and amount alone cannot tell apart two card debits of the same
     * amount on the same day — a lunch and a bakery bill — and
     * whichever came first took the tap. So the taps are matched in two passes: first only to a bank
     * row whose label names the same shop, then, for the taps left over, to
     * the nearest row of that amount as before. A label rarely carries the
     * name Wallet shows, so the second pass is still most of the work; the
     * first is what stops it guessing wrong when it has a choice.
     *
     * A bank row still pending is enough: the tap is the same announcement,
     * and keeping both would list the payment twice under "en prévision".
    *
     * A refund is the exception to "never before".
     *
     * Money coming back is not a payment made at a till: the shop refunds when
     * it gets round to it, and the row is often typed in days later, from the
     * receipt or from noticing it. Its date is the day it was entered, not the
     * day the bank moved the money — which can be a week earlier, and was, so
     * the credit sat under "en prévision" for ever while the bank's own credit
     * stood beside it. A credit may therefore settle onto a bank row up to a
     * fortnight before it, and only in the pass where the labels name the same
     * shop.
     *
     * A debit has the same exception, one size down.
     *
     * "A payment cannot be booked before it is made" describes a tap written
     * the second it happens, and most are. Some are not: a transit operator
     * submits a day's rides a day or three later, so Wallet reveals the fare
     * — and the tap gets written — after the bank has already booked it. With
     * no room behind, those two can never meet, and both stay for good: a
     * fare booked on the 3rd beside its own tap dated the 4th, neither one
     * able to claim the other.
     *
     * Three days back, and only where the labels name the same shop. The
     * blind pass keeps none: with no name to agree on, the same amount a few
     * days earlier is a different coffee.
     */
    @discardableResult
    static func settle(store: LocalStore) throws -> Int {
        let pending = try store.database.query(
            """
            SELECT id, account_id, amount, payee, substr(occurred_at, 1, 10) AS day,
                   category_id, instalment_plan_id
            FROM transactions
            WHERE source = ? AND deleted_at IS NULL
            ORDER BY occurred_at
            """,
            [.text(source)]
        )
        var claimed = Set<String>()
        var done = Set<String>()
        var settled = 0
        for byName in [true, false] {
            /*
             * La paire la plus proche d'abord, pas le premier venu.
             *
             * Chaque tape prenait, dans sa fenêtre, la ligne libre la plus
             * proche — en commençant par la plus ancienne des tapes. Un café
             * quotidien au même prix décalait alors tout le monde d'un cran :
             * la tape du 9 prenait la ligne du 13, celle du 13 la ligne du
             * 14, et la tape du 14 ne trouvait plus rien. Le décalage ne se
             * rattrape jamais, et l'orpheline reste « en prévision » à vie
             * en doublant une dépense déjà comptabilisée.
             *
             * Les paires possibles sont donc toutes constituées d'abord, puis
             * attribuées par écart croissant : la ligne du 13 revient à la
             * tape du 13, qui est à zéro jour, et non à celle du 9, qui est à
             * quatre. Ce qui reste sans partenaire est alors ce qui n'en a
             * réellement pas.
             */
            /*
             * Sans le nom pour corroborer, une semaine en avant est un pari.
             *
             * La banque date une ligne de carte au jour de l'achat — pas une
             * exception sur tout le grand livre — donc la ligne d'une tape est
             * à zéro jour, ou n'existe pas encore. Chercher jusqu'à sept jours
             * plus loin sans que le nom soit d'accord, c'était prendre la
             * ligne d'un achat qui n'avait pas encore été tapé : une tape d'un
             * café prenait un prélèvement d'assurance du même montant six
             * jours plus tard, et la tape du jour de ce prélèvement se
             * retrouvait orpheline à vie. L'erreur ne se voyait pas — elle se
             * voyait six jours plus loin, sur quelqu'un d'autre.
             *
             * Un jour reste, parce qu'une carte passée par un intermédiaire
             * est débitée le lendemain sous le nom de l'intermédiaire, et que
             * là le nom ne peut pas être d'accord. Au-delà, c'est au nom de
             * parler.
             */
            var pairs: [(tap: SQLiteRow, bank: SQLiteRow, drift: Double)] = []
            for row in pending {
                guard let id = row.string("id"), !done.contains(id),
                      let account = row.string("account_id"),
                      let amount = row.double("amount"), let day = row.string("day") else { continue }
                let candidates = try store.database.query(
                    """
                    SELECT id, category_id, normalized_payee, payee,
                           abs(julianday(substr(occurred_at, 1, 10)) - julianday(?)) AS drift
                    FROM transactions
                    WHERE account_id = ? AND deleted_at IS NULL
                      AND source <> ? AND status = 'cleared'
                      AND abs(amount - ?) < 0.005
                      AND julianday(substr(occurred_at, 1, 10))
                          BETWEEN julianday(?) - ? AND julianday(?) + ?
                    ORDER BY abs(julianday(substr(occurred_at, 1, 10)) - julianday(?))
                    """,
                    [.text(day), .text(account), .text(source), .real(amount), .text(day),
                     .real(byName ? (amount > 0 ? 14 : 3) : 0), .text(day),
                     .real(byName ? 7 : 1), .text(day)]
                )
                let tap = row.string("payee") ?? ""
                for candidate in candidates
                where !byName || namesAgree(tap, candidate.string("normalized_payee") ?? "") {
                    pairs.append((row, candidate, candidate.double("drift") ?? 99))
                }
            }
            pairs.sort { $0.drift < $1.drift }

            for pair in pairs {
                let row = pair.tap, match = pair.bank
                guard let id = row.string("id"), !done.contains(id),
                      let bankId = match.string("id"), !claimed.contains(bankId),
                      !isAlreadySettling(store, bankId) else { continue }
                claimed.insert(bankId)
                done.insert(id)

                if match.string("category_id") == nil, let category = row.string("category_id") {
                    try store.database.run(
                        "UPDATE transactions SET category_id = ?, updated_at = datetime('now') WHERE id = ?",
                        [.text(category), .text(bankId)]
                    )
                }
                /*
                 * Le nom que vous avez donné passe aussi, et sa vignette.
                 *
                 * Une tape porte le nom du commerce ; la ligne de la banque
                 * porte « ACHAT CB … 23.10.26 EUR », qui ne se replie pas sur
                 * la même clé. Au moment où la banque comptabilise, le nom et
                 * le site disparaissaient donc de l'écran et il fallait les
                 * reposer à la main — sur une clé qui, elle non plus, ne
                 * vaudra que pour ce commerçant-là. La catégorie et
                 * l'échéancier passaient déjà : c'est le même achat, et son
                 * identité en fait partie.
                 *
                 * `DO NOTHING` : ce qui a déjà été décidé sur la clé de la
                 * banque est une décision, et ne se laisse pas écraser.
                 */
                try adoptIdentity(
                    store, tap: row.string("payee") ?? "", bank: match.string("payee") ?? ""
                )
                /*
                 * Et les tickets de caisse.
                 *
                 * Ils sont attachés à la ligne, par son identifiant. La tape
                 * étant retirée, un ticket resté sur elle n'est plus affiché
                 * nulle part : la photo est toujours en base, mais plus aucun
                 * écran n'y mène. Photographier un ticket revenait donc à le
                 * perdre le lendemain, quand la banque comptabilisait.
                 */
                try store.database.run(
                    "UPDATE receipts SET transaction_id = ? WHERE transaction_id = ?",
                    [.text(bankId), .text(id)]
                )
                /*
                 * L'échéancier passe sur la ligne de la banque.
                 *
                 * Comme la catégorie, et pour la même raison : c'est le même
                 * achat. Sans ce transport, un paiement en quatre fois perdait
                 * une échéance à chaque prélèvement — le plan maigrissait au
                 * lieu de se remplir, et « 2 sur 4 payées » n'était pas
                 * calculable puisque les payées n'en faisaient plus partie.
                 */
                if let plan = row.string("instalment_plan_id") {
                    try store.database.run(
                        """
                        UPDATE transactions
                        SET instalment_plan_id = ?, updated_at = datetime('now')
                        WHERE id = ?
                        """,
                        [.text(plan), .text(bankId)]
                    )
                }
                // The link stays on the retired payment, so this bank row is never
                // offered to a second one on a later sync.
                try store.database.run(
                    """
                    UPDATE transactions
                    SET deleted_at = datetime('now'), merge_suggested_tx_id = ?
                    WHERE id = ?
                    """,
                    [.text(bankId), .text(id)]
                )
                settled += 1
            }
        }
        // Les noms et vignettes qu'on vient de faire passer : les tables sont
        // lues une fois et gardées, et une comptabilisation arrive aussi en
        // pleine session, après une synchro.
        if settled > 0 {
            MerchantNames.shared.invalidate()
            Task { @MainActor in MerchantLogos.shared.invalidate() }
        }
        try expireUnclaimed(store: store)
        return settled
    }

    /// Passé ce délai sans que la banque l'ait réclamée, une tape ne sera
    /// jamais comptabilisée. Large devant le temps que met une banque à
    /// écrire une ligne — un à trois jours, le week-end compris.
    static let unclaimedGrace: Double = 7

    /*
     * Une tape que la banque n'a jamais réclamée.
     *
     * Une tape est une note provisoire : elle existe pour tenir la place
     * d'une ligne de relevé en attendant qu'elle arrive. Quand elle n'arrive
     * pas — l'automatisation a écrit deux fois, le paiement a été refusé, le
     * commerçant n'a pas encaissé — la note restait « en prévision » pour
     * toujours. Elle faussait le total du volet, et la seule issue était de
     * la balayer à la main, un travail de ménage que l'app devrait faire
     * elle-même.
     *
     * Le délai ne suffit pas à décider : un grand livre pas synchronisé
     * depuis deux semaines n'a rien reçu non plus, et retirer alors toutes
     * les tapes du mois serait une perte sèche. Ce qui décide, c'est que la
     * banque ait parlé APRÈS : s'il existe sur ce compte une ligne postérieure
     * à la tape plus le délai, alors le relevé a dépassé cette date et la
     * ligne attendue n'y était pas.
     *
     * La suppression est douce, comme celle qu'écrit `settle` : la tape reste
     * dans la base, et l'argent, lui, n'a jamais bougé.
     */
    @discardableResult
    static func expireUnclaimed(store: LocalStore) throws -> Int {
        let stale = try store.database.query(
            """
            SELECT t.id AS id FROM transactions t
            WHERE t.source = ? AND t.deleted_at IS NULL
              AND t.merge_suggested_tx_id IS NULL
              AND julianday(substr(t.occurred_at, 1, 10)) <= julianday('now') - ?
              AND EXISTS (
                SELECT 1 FROM transactions b
                WHERE b.account_id = t.account_id AND b.deleted_at IS NULL
                  AND b.source <> ? AND b.status = 'cleared'
                  AND julianday(substr(b.occurred_at, 1, 10))
                      > julianday(substr(t.occurred_at, 1, 10)) + ?
              )
            """,
            [.text(source), .real(unclaimedGrace), .text(source), .real(unclaimedGrace)]
        )
        guard !stale.isEmpty else { return 0 }
        try store.database.transaction {
            for id in stale.compactMap({ $0.string("id") }) {
                try store.database.run(
                    """
                    UPDATE transactions
                    SET deleted_at = datetime('now'), updated_at = datetime('now')
                    WHERE id = ?
                    """,
                    [.text(id)]
                )
            }
        }
        return stale.count
    }

    /// Whether a bank label names the shop Wallet named: a word of four
    /// letters or more in common. "Le Comptoir" is in "ACHAT CB SARL LE
    /// COMPTOIR"; it is not in "ACHAT CB CHEZ ROSA".
    static func namesAgree(_ tap: String, _ label: String) -> Bool {
        LocalLedger.namesAgree(tap, label, whenUnsure: false)
    }

    /*
     * Card payments a bank sync took for its own rows.
     *
     * Until the sync learnt to leave taps to `settle`, it adopted them: the
     * bank's key moved onto the tap, which kept the name Wallet gave it and
     * the `scheduled` status — so a booked debit read "Prévu" for good, and
     * where two debits shared an amount the name could land on the wrong one.
     * Such a row is put back as `settle` would have left it: cleared, under
     * the bank's own label, which the key still carries when the bank gave no
     * stable reference ("<account>:<date>:<amount>:<label>").
     */
    @discardableResult
    static func repairAdopted(store: LocalStore) throws -> Int {
        let rows = try store.database.query(
            """
            SELECT id, external_id FROM transactions
            WHERE source = 'enable_banking' AND status = 'scheduled'
              AND is_pending = 0 AND deleted_at IS NULL
            """
        )
        for row in rows {
            guard let id = row.string("id") else { continue }
            if let label = bankLabel(inKey: row.string("external_id") ?? "") {
                try store.database.run(
                    """
                    UPDATE transactions
                    SET status = 'cleared', payee = ?, normalized_payee = ?, updated_at = datetime('now')
                    WHERE id = ?
                    """,
                    [.text(label), .text(LocalLedger.normalize(label)), .text(id)]
                )
            } else {
                try store.database.run(
                    "UPDATE transactions SET status = 'cleared', updated_at = datetime('now') WHERE id = ?",
                    [.text(id)]
                )
            }
        }
        return rows.count
    }

    /*
     * Les tickets restés sur une tape que la banque a remplacée.
     *
     * `settle` transportait la catégorie et l'échéancier, pas les tickets :
     * ceux d'avant sont attachés à une ligne retirée, donc invisibles. La
     * tape dit elle-même où elle est passée — `merge_suggested_tx_id` porte
     * la ligne qui l'a remplacée — et il suffit de suivre ce lien.
     *
     * Rien n'est écrasé : le ticket change de ligne, il ne change pas de
     * contenu, et une ligne de banque peut en porter plusieurs.
     */
    @discardableResult
    static func rehomeReceipts(store: LocalStore) throws -> Int {
        let strays = try store.database.query(
            """
            SELECT r.id AS id, t.merge_suggested_tx_id AS bank
            FROM receipts r JOIN transactions t ON t.id = r.transaction_id
            WHERE t.deleted_at IS NOT NULL AND t.merge_suggested_tx_id IS NOT NULL
              AND EXISTS (SELECT 1 FROM transactions b
                          WHERE b.id = t.merge_suggested_tx_id AND b.deleted_at IS NULL)
            """
        )
        guard !strays.isEmpty else { return 0 }
        try store.database.transaction {
            for row in strays {
                guard let id = row.string("id"), let bank = row.string("bank") else { continue }
                try store.database.run(
                    "UPDATE receipts SET transaction_id = ? WHERE id = ?",
                    [.text(bank), .text(id)]
                )
            }
        }
        return strays.count
    }

    /// The label at the end of a reference-less bank key, if that is its shape.
    static func bankLabel(inKey key: String) -> String? {
        let pattern = #"^[^:]+:\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z:-?[0-9.]+:(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let hit = regex.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)),
              let range = Range(hit.range(at: 1), in: key) else { return nil }
        let label = key[range].trimmingCharacters(in: .whitespaces)
        return label.isEmpty ? nil : label
    }

    /// A bank row that already replaced an earlier payment is not free to
    /// replace another.
    /// Le nom et la vignette d'une tape, posés sur la clé de la ligne que la
    /// banque vient d'écrire. Voir l'appel, dans `settle`.
    private static func adoptIdentity(_ store: LocalStore, tap: String, bank: String) throws {
        let tapKey = MerchantNames.key(tap), bankKey = MerchantNames.key(bank)
        guard !tapKey.isEmpty, !bankKey.isEmpty, tapKey != bankKey else { return }
        // Le nom montré pour la tape : son renommage s'il en a un, sinon ce
        // qui a été tapé — c'est déjà un nom, pas une ligne de relevé.
        let shown = (try? store.database.scalar(
            "SELECT display_name FROM payee_aliases WHERE match_key = ?", [.text(tapKey)]
        )?.string) ?? nil
        let display = shown ?? tap.trimmingCharacters(in: .whitespaces)
        guard !display.isEmpty else { return }
        try store.database.run(
            """
            INSERT INTO payee_aliases (id, match_key, display_name) VALUES (?, ?, ?)
            ON CONFLICT(match_key) DO NOTHING
            """,
            [.text(UUID().uuidString), .text(bankKey), .text(display)]
        )
        try store.database.run(
            """
            INSERT INTO merchant_marks (match_key, domain, emoji, image)
            SELECT ?, domain, emoji, image FROM merchant_marks WHERE match_key = ?
            ON CONFLICT(match_key) DO NOTHING
            """,
            [.text(bankKey), .text(tapKey)]
        )
    }

    private static func isAlreadySettling(_ store: LocalStore, _ bankId: String) -> Bool {
        (try? store.database.scalar(
            "SELECT 1 FROM transactions WHERE source = ? AND merge_suggested_tx_id = ? LIMIT 1",
            [.text(source), .text(bankId)]
        )) != nil
    }
}
