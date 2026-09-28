import Foundation
import OSLog

/*
 * Le double des paiements, écrit par Raccourcis lui-même.
 *
 * L'action de Florin ne s'exécute que si iOS veut bien réveiller l'app, et le
 * lien entre une automatisation et l'action d'une app se défait quand l'app
 * est remplacée — un simple build de développement suffit. L'automatisation
 * continue alors de se déclencher, l'action ne fait plus rien, et rien ne le
 * dit : ni ligne au grand livre, ni tentative au journal, puisque le journal
 * s'écrit depuis l'action. Trois jours de paiements ont disparu comme ça.
 *
 * Une action native, elle, ne dépend d'aucune app. Placée **en tête** de la
 * même automatisation — avant l'action de Florin, pour qu'une action qui
 * échoue n'interrompe pas le raccourci avant elle — « Ajouter au fichier »
 * écrit une ligne par paiement dans le dossier que Fichiers montre sous
 * « Florin ». Cette ligne-là ne manque jamais : c'est le même mécanisme que
 * l'automatisation du tableur, qui n'a pas raté un paiement de la semaine.
 *
 * Florin relit le fichier à chaque ouverture et rattrape ce que l'action n'a
 * pas pris. Le rattrapage ne peut pas doubler : un paiement n'est repris que
 * si le grand livre n'a pas déjà la même somme chez le même marchand à la même
 * minute — y compris une ligne supprimée, car une opération que la banque a
 * confirmée est précisément celle qu'il ne faut pas réécrire.
 */
enum WalletInbox {
    /// Le nom à donner au fichier dans « Ajouter au fichier ».
    static let fileName = "paiements.txt"

    /// Deux paiements identiques chez le même marchand à moins de ça d'écart
    /// sont le même paiement. Large devant le décalage entre l'action native
    /// et celle de Florin, qui se suivent dans la même automatisation ; étroit
    /// devant deux achats réellement distincts.
    static let window: TimeInterval = 300

    private static let log = Logger(subsystem: "com.adrbn.florin", category: "wallet-inbox")

    /// Une ligne du fichier, lue.
    struct Entry: Equatable {
        let at: Date
        let amountText: String
        let card: String?
        let merchant: String
        /// `false` quand la date de la ligne était illisible : le paiement est
        /// repris quand même, à l'heure du rattrapage, et le journal le dit.
        let timed: Bool
    }

    // MARK: - Le fichier

    /// `Documents/paiements.txt`, le seul dossier de l'app que Fichiers
    /// expose (voir `UIFileSharingEnabled`) et donc le seul où Raccourcis
    /// puisse écrire sans rien demander.
    static func fileURL(in folder: URL? = nil) -> URL? {
        let base = folder ?? (try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ))
        return base?.appendingPathComponent(fileName)
    }

    // MARK: - La lecture

    /*
     * Ce que Raccourcis peut écrire sans qu'on lui demande trop.
     *
     * Le séparateur est la barre verticale : une virgule et un point-virgule
     * se trouvent dans les noms d'enseignes, pas elle. Le marchand vient en
     * dernier et garde tout ce qui suit, y compris une barre, parce que c'est
     * le seul champ qu'on ne contrôle pas.
     */
    static func parse(_ text: String, now: Date = Date()) -> [Entry] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
            guard !line.isEmpty else { return nil }
            let fields = line.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count == 4 else { return nil }
            let merchant = fields[3]
            guard !merchant.isEmpty, !fields[1].isEmpty else { return nil }
            let moment = date(from: fields[0])
            return Entry(
                at: moment ?? now,
                amountText: fields[1],
                card: fields[2].isEmpty ? nil : fields[2],
                merchant: merchant,
                timed: moment != nil
            )
        }
    }

    /*
     * L'heure, écrite comme Raccourcis a bien voulu l'écrire.
     *
     * Le guide demande un format fixe, mais une variable « Date actuelle »
     * déposée telle quelle dans le texte sort au format du téléphone. Une
     * heure approximative vaut infiniment mieux qu'un paiement perdu, donc
     * tout ce qui ressemble à une date est accepté, et ce qui ne ressemble à
     * rien ne fait pas jeter la ligne.
     */
    static func date(from text: String) -> Date? {
        // « 28/09/2026 à 15:47 » : la préposition est une décoration de la
        // langue, pas une information. Même chose pour les espaces insécables
        // que les formats français glissent devant l'heure.
        let text = text
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: " à ", with: " ")
            .replacingOccurrences(of: " at ", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let parsed = iso.date(from: text) { return parsed }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = iso.date(from: text) { return parsed }
        for pattern in [
            "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd",
            "dd/MM/yyyy, HH:mm:ss", "dd/MM/yyyy, HH:mm", "dd/MM/yyyy HH:mm:ss", "dd/MM/yyyy HH:mm",
            "MM/dd/yyyy, h:mm:ss a", "MM/dd/yyyy, h:mm a",
        ] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = pattern
            if let parsed = formatter.date(from: text) { return parsed }
        }
        /*
         * Et, en dernier recours, la langue du téléphone.
         *
         * Une variable « Date actuelle » déposée telle quelle sort au format
         * de la région, qu'aucune liste de motifs ne peut couvrir pour toutes
         * les langues. Les styles, eux, sont exactement ce que le système a
         * utilisé pour l'écrire.
         */
        for style in [DateFormatter.Style.short, .medium, .long] {
            for time in [DateFormatter.Style.short, .medium, .none] {
                let formatter = DateFormatter()
                formatter.locale = .current
                formatter.timeZone = .current
                formatter.dateStyle = style
                formatter.timeStyle = time
                if let parsed = formatter.date(from: text) { return parsed }
            }
        }
        return nil
    }

    // MARK: - Le rattrapage

    /// Le grand livre a-t-il déjà ce paiement ? Les lignes supprimées
    /// comptent : celles que la banque a confirmées le sont.
    static func alreadyKnown(store: LocalStore, _ entry: Entry) -> Bool {
        guard let amount = LocalWallet.parseAmount(entry.amountText) else { return false }
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.timeZone = .current
        stamp.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let payee = entry.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        return (try? store.database.scalar(
            """
            SELECT 1 FROM transactions
            WHERE source = ? AND normalized_payee = ? AND abs(amount + ?) < 0.005
              AND abs(julianday(replace(substr(occurred_at, 1, 19), 'T', ' '))
                      - julianday(?)) * 86400.0 <= ?
            LIMIT 1
            """,
            [
                .text(LocalWallet.source), .text(LocalLedger.normalize(payee.isEmpty ? "Apple Pay" : payee)),
                .real(amount), .text(stamp.string(from: entry.at)), .real(window),
            ]
        )) != nil
    }

    /*
     * Reprend du fichier ce que l'action n'a pas pris, et vide le fichier.
     *
     * Vider n'est pas ce qui empêche de doubler — c'est le grand livre qui
     * l'empêche, et c'est heureux : un rattrapage interrompu à la moitié
     * laisse le fichier entier, et la reprise suivante ne réécrira que ce qui
     * manque encore. Vider ne fait qu'éviter au fichier de grossir et au
     * journal de reconstater les mêmes lignes à chaque ouverture.
     */
    @discardableResult
    static func drain(store: LocalStore, at url: URL? = nil, now: Date = Date()) -> Int {
        guard let url = url ?? fileURL(),
              let data = try? Data(contentsOf: url), !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return 0 }
        let entries = parse(text, now: now)
        var taken = 0
        for entry in entries where !alreadyKnown(store: store, entry) {
            let attempt = WalletLog.begin(
                store: store, amountText: entry.amountText,
                merchant: entry.merchant, card: entry.card, at: entry.at
            )
            do {
                try LocalWallet.record(
                    store: store, amountText: entry.amountText, merchant: entry.merchant,
                    card: entry.card, accountId: nil, on: entry.at
                )
                WalletLog.finish(
                    store: store, id: attempt, outcome: .recorded,
                    detail: entry.timed
                        ? Strings.device("v2.wallet.fromFile", "Repris du fichier de l'automatisation")
                        : Strings.device("v2.wallet.fromFileUndated", "Repris du fichier, heure illisible")
                )
                taken += 1
            } catch {
                WalletLog.finish(
                    store: store, id: attempt, outcome: .failed, detail: error.localizedDescription
                )
            }
        }
        // Écrit vide plutôt que supprimé : « Ajouter au fichier » recrée un
        // fichier absent, mais un fichier présent est ce que la personne voit
        // dans Fichiers et cherche quand elle doute que quelque chose marche.
        try? Data().write(to: url, options: .atomic)
        if taken > 0 {
            log.notice("recovered \(taken, privacy: .public) payments from the shortcut file")
        }
        return taken
    }
}
