import CoreLocation
import Foundation

/*
 * Où sont les marchands — et seulement parce qu'on a dit oui.
 *
 * Florin ne sort rien du téléphone, et une carte ne doit pas être
 * l'exception. Chercher « Antico Caffè » chez un fournisseur de cartes
 * reviendrait à lui dire où l'on boit son café : le nom suffit à trahir.
 * Donc aucun nom ne part, aucune adresse n'est demandée, rien n'est
 * géocodé. La seule source est le GPS de l'appareil, lu pendant qu'on est
 * sur place, et le réglage est ÉTEINT tant qu'on ne l'allume pas.
 *
 * L'épingle appartient au MARCHAND, pas à l'opération.
 *
 * C'est ce qui rend la chose jouable : la banque livre sa ligne des heures
 * après le paiement, quand on n'y est plus — une épingle par opération ne
 * se remplirait jamais. Posée sur le marchand, une seule visite éclaire
 * tout son historique d'un coup, et le même point répond pour les
 * variantes de libellé que la caisse invente, puisque c'est
 * `MerchantNames.sameMerchant` qui décide qui est qui.
 *
 * Deux moments où l'appareil peut témoigner : l'automatisation Wallet, qui
 * tourne la carte à la main, et le bouton « j'y suis » d'une fiche. Aucun
 * suivi en arrière-plan : ni nécessaire, ni souhaitable.
 */
enum LocalPlaces {
    static let enabledKey = "florin.places"

    /// Éteint tant qu'on ne l'allume pas. `bool(forKey:)` rend `false` pour
    /// une clé jamais écrite, ce qui est exactement la valeur voulue.
    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: enabledKey)
    }

    static var authorized: Bool {
        switch CLLocationManager().authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: true
        default: false
        }
    }

    /*
     * Le point que le système a déjà, sans rien demander de neuf.
     *
     * L'automatisation Wallet tourne sans ouvrir l'app, et attendre un
     * relevé frais y ferait patienter un paiement. iOS garde le dernier
     * point connu : à la caisse, l'écran vient de s'allumer, il a quelques
     * secondes. Trop vieux ou trop flou, on préfère pas d'épingle du tout à
     * une fausse — une épingle fausse ne se voit pas, une absente si.
     */
    static var lastKnown: CLLocation? {
        guard enabled, authorized, let fix = CLLocationManager().location else { return nil }
        return usable(fix) ? fix : nil
    }

    static func usable(_ fix: CLLocation) -> Bool {
        fix.horizontalAccuracy > 0 && fix.horizontalAccuracy <= 150
            && Date().timeIntervalSince(fix.timestamp) <= 300
    }

    // MARK: - Écrire

    /*
     * Sous quelle clé l'épingle de ce marchand est-elle rangée ?
     *
     * Celle du libellé d'aujourd'hui, ou une voisine : la caisse rallonge,
     * la banque tronque, et `sameMerchant` tranche. Sans ce détour, poser
     * une épingle depuis une variante du libellé en créait une DEUXIÈME
     * pour le même marchand, et la retirer depuis la première ne retirait
     * jamais la bonne.
     */
    private static func storedKey(store: LocalStore, key: String) -> String? {
        guard !key.isEmpty else { return nil }
        let keys = (try? store.database.query("SELECT match_key FROM merchant_places")) ?? []
        return keys.compactMap { $0.string("match_key") }
            .first { MerchantNames.sameMerchant($0, key) }
    }

    /// Pose, ou déplace, l'épingle de ce marchand.
    @discardableResult
    static func remember(store: LocalStore, payee: String, at fix: CLLocation?) -> Bool {
        guard enabled, let fix, usable(fix) else { return false }
        return set(
            store: store, payee: payee,
            lat: fix.coordinate.latitude, lon: fix.coordinate.longitude,
            accuracy: fix.horizontalAccuracy
        )
    }

    /// Écrit un point choisi — relevé GPS, ou ajusté à la main sur la carte.
    @discardableResult
    static func set(
        store: LocalStore, payee: String, lat: Double, lon: Double, accuracy: Double
    ) -> Bool {
        let fresh = MerchantNames.key(payee)
        guard enabled, !fresh.isEmpty else { return false }
        let key = storedKey(store: store, key: fresh) ?? fresh
        try? store.database.run(
            """
            INSERT INTO merchant_places (match_key, lat, lon, accuracy, updated_at)
              VALUES (?, ?, ?, ?, datetime('now'))
            ON CONFLICT(match_key) DO UPDATE
              SET lat = excluded.lat, lon = excluded.lon,
                  accuracy = excluded.accuracy, updated_at = excluded.updated_at
            """,
            [.text(key), .real(lat), .real(lon), .real(accuracy)]
        )
        return true
    }

    /*
     * Le libellé corrigé emmène son épingle.
     *
     * L'automatisation écrit l'épingle à la caisse, sous le nom DICTÉ : c'est
     * le seul instant où l'appareil est au bon endroit. Siri entend parfois
     * autre chose — « Lumière » pour « Lumio » — et la correction suit dans
     * minute, sur la ligne. Le libellé changeait, l'épingle restait sur le
     * la minute, sur la ligne. Le libellé changeait, l'épingle restait sur
     * commerçant réel sans point alors qu'on venait d'y être.
     *
     * Elle ne part QUE si l'ancien nom n'était que celui de cette ligne.
     * Reclasser une ligne d'une enseigne vers une autre ne dit rien du lieu
     * de la première — ses cent autres lignes le disent encore — et déplacer
     * son épingle poserait la seconde là où elle n'a jamais été. Un nom né
     * d'une seule ligne, lui, n'a pas d'autre sens que cette ligne-là.
     */
    static func follow(store: LocalStore, from old: String, to new: String, excluding id: String) {
        let before = MerchantNames.key(old), after = MerchantNames.key(new)
        guard enabled, !before.isEmpty, !after.isEmpty, before != after,
              let source = storedKey(store: store, key: before) else { return }
        let others = (try? store.database.query(
            """
            SELECT DISTINCT payee FROM transactions
             WHERE deleted_at IS NULL AND payee <> '' AND id <> ?
            """,
            [.text(id)]
        )) ?? []
        let stillNamed = others.compactMap { $0.string("payee") }
            .contains { MerchantNames.sameMerchant(MerchantNames.key($0), before) }
        guard !stillNamed else { return }
        try? store.database.run(
            """
            INSERT INTO merchant_places (match_key, lat, lon, accuracy, updated_at)
            SELECT ?, lat, lon, accuracy, updated_at
              FROM merchant_places WHERE match_key = ?
            ON CONFLICT(match_key) DO NOTHING
            """,
            [.text(after), .text(source)]
        )
        try? store.database.run(
            "DELETE FROM merchant_places WHERE match_key = ?", [.text(source)]
        )
    }

    static func forget(store: LocalStore, payee: String) {
        guard let key = storedKey(store: store, key: MerchantNames.key(payee)) else { return }
        try? store.database.run("DELETE FROM merchant_places WHERE match_key = ?", [.text(key)])
    }

    /// Où est l'épingle de ce marchand, s'il en a une.
    static func coordinate(store: LocalStore, payee: String) -> CLLocationCoordinate2D? {
        guard let key = storedKey(store: store, key: MerchantNames.key(payee)),
              let row = (try? store.database.query(
                  "SELECT lat, lon FROM merchant_places WHERE match_key = ?", [.text(key)]
              ))?.first,
              let lat = row.double("lat"), let lon = row.double("lon")
        else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Ce marchand a-t-il déjà une épingle ? Sous sa clé ou sous une voisine.
    static func pinned(store: LocalStore, payee: String) -> Bool {
        storedKey(store: store, key: MerchantNames.key(payee)) != nil
    }

    // MARK: - Lire

    struct Place: Identifiable, Equatable {
        let key: String
        let name: String
        let lat: Double
        let lon: Double
        /// Combien de passages, et combien dépensé, chez ce marchand.
        let visits: Int
        let spent: Double
        /// La première et la dernière fois — « depuis mars dernier » dit
        /// quelque chose qu'un total ne dit pas.
        let first: Date?
        let last: Date?
        var id: String { key }
    }

    /*
     * Les épingles, avec ce qu'on a dépensé derrière chacune.
     *
     * Les totaux se somment sur TOUS les libellés du marchand, pas sur la
     * clé qui porte l'épingle : la caisse rallonge son libellé, la banque le
     * tronque ailleurs, et c'est la même boulangerie. La règle est celle qui
     * sert déjà au nom et à la tête, donc une épingle posée aujourd'hui
     * éclaire l'historique entier.
     */
    static func all(store: LocalStore) -> [Place] {
        let pins = (try? store.database.query(
            "SELECT match_key, lat, lon FROM merchant_places"
        )) ?? []
        guard !pins.isEmpty else { return [] }
        /*
         * On groupe par LIBELLÉ, et c'est la clé du libellé qu'on compare.
         *
         * Le regroupement se faisait sur `normalized_payee`, qui est le
         * relevé entier normalisé — date, montant et numéro de carte
         * compris. Donc un libellé par achat, et une clé de marchand qui
         * n'y ressemblait jamais : « tigre » ne retrouvait que les quatre
         * lignes saisies à la main sous ce nom, pas les cent vingt-cinq du
         * relevé. La carte annonçait « 4 passages » pour un marchand qu'on
         * visite deux fois par semaine, et « 0 passage » pour tous ceux que
         * la banque nomme à sa façon.
         *
         * La clé se calcule donc en Swift, une fois par libellé distinct —
         * comme dans `MerchantNames.usage(ofKey:)`, pour la même raison.
         */
        let spending = (try? store.database.query(
            """
            SELECT payee, count(*) AS n, sum(amount) AS total,
                   min(occurred_at) AS first_at, max(occurred_at) AS last_at
              FROM transactions
             WHERE deleted_at IS NULL AND amount < 0 AND payee <> ''
             GROUP BY payee
            """
        )) ?? []
        let folded: [(key: String, row: SQLiteRow)] = spending.compactMap { row in
            guard let payee = row.string("payee") else { return nil }
            let key = MerchantNames.key(payee)
            return key.isEmpty ? nil : (key, row)
        }

        let names = MerchantNames.shared
        return pins.compactMap { pin in
            guard let key = pin.string("match_key"),
                  let lat = pin.double("lat"), let lon = pin.double("lon") else { return nil }
            let twins = names.keysNaming(key)
            var visits = 0
            var spent = 0.0
            var first: Date?
            var last: Date?
            for entry in folded {
                guard MerchantNames.sameMerchant(key, entry.key)
                    || twins.contains(where: { MerchantNames.sameMerchant($0, entry.key) })
                else { continue }
                visits += entry.row.int("n") ?? 0
                spent += abs(entry.row.double("total") ?? 0)
                if let begin = entry.row.string("first_at").flatMap(day) {
                    first = min(first ?? begin, begin)
                }
                if let end = entry.row.string("last_at").flatMap(day) {
                    last = max(last ?? end, end)
                }
            }
            return Place(
                key: key, name: names.name(forKey: key) ?? PayeeText.bankName(key.uppercased()),
                lat: lat, lon: lon, visits: visits, spent: spent, first: first, last: last
            )
        }
        .sorted { $0.spent > $1.spent }
    }

    /// Les dates sont stockées en ISO, parfois avec l'heure, parfois sans.
    private static func day(_ iso: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(iso.prefix(10)))
    }
}

/*
 * Un relevé frais, demandé une fois, écran allumé.
 *
 * Le point gardé par le système suffit à la caisse ; il ne suffit pas quand
 * on pose une épingle à la main, parce que c'est le geste où l'on affirme
 * « c'est ICI ». Et c'est aussi le seul moment où l'on peut demander
 * l'autorisation : une question posée pendant que la personne regarde.
 */
@MainActor
final class PlaceFinder: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiting: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// Nil si la personne refuse, ou si rien d'exploitable n'arrive.
    func fix() async -> CLLocation? {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            // Laisser la feuille système répondre avant de demander un point.
            try? await Task.sleep(for: .seconds(1))
        }
        guard LocalPlaces.authorized else { return nil }
        if let known = manager.location, LocalPlaces.usable(known) { return known }
        return await withCheckedContinuation { (hold: CheckedContinuation<CLLocation?, Never>) in
            waiting = hold
            manager.requestLocation()
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                self?.settle(nil)
            }
        }
    }

    private func settle(_ fix: CLLocation?) {
        guard let hold = waiting else { return }
        waiting = nil
        hold.resume(returning: fix)
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        let last = locations.last
        Task { @MainActor in self.settle(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.settle(nil) }
    }
}
