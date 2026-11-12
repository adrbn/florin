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

    /// Pose, ou déplace, l'épingle de ce marchand.
    @discardableResult
    static func remember(store: LocalStore, payee: String, at fix: CLLocation?) -> Bool {
        let key = MerchantNames.key(payee)
        guard enabled, !key.isEmpty, let fix, usable(fix) else { return false }
        try? store.database.run(
            """
            INSERT INTO merchant_places (match_key, lat, lon, accuracy, updated_at)
              VALUES (?, ?, ?, ?, datetime('now'))
            ON CONFLICT(match_key) DO UPDATE
              SET lat = excluded.lat, lon = excluded.lon,
                  accuracy = excluded.accuracy, updated_at = excluded.updated_at
            """,
            [
                .text(key), .real(fix.coordinate.latitude), .real(fix.coordinate.longitude),
                .real(fix.horizontalAccuracy),
            ]
        )
        return true
    }

    static func forget(store: LocalStore, payee: String) {
        let key = MerchantNames.key(payee)
        guard !key.isEmpty else { return }
        try? store.database.run("DELETE FROM merchant_places WHERE match_key = ?", [.text(key)])
    }

    /// Ce marchand a-t-il déjà une épingle ? Sous sa clé ou sous une voisine.
    static func pinned(store: LocalStore, payee: String) -> Bool {
        let key = MerchantNames.key(payee)
        guard !key.isEmpty else { return false }
        let keys = (try? store.database.query("SELECT match_key FROM merchant_places")) ?? []
        return keys.compactMap { $0.string("match_key") }.contains {
            MerchantNames.sameMerchant($0, key)
        }
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
        let spending = (try? store.database.query(
            """
            SELECT normalized_payee AS k, count(*) AS n, sum(amount) AS total
              FROM transactions
             WHERE deleted_at IS NULL AND amount < 0 AND normalized_payee <> ''
             GROUP BY normalized_payee
            """
        )) ?? []
        let names = MerchantNames.shared
        return pins.compactMap { pin in
            guard let key = pin.string("match_key"),
                  let lat = pin.double("lat"), let lon = pin.double("lon") else { return nil }
            let twins = names.keysNaming(key)
            var visits = 0
            var spent = 0.0
            for row in spending {
                guard let other = row.string("k") else { continue }
                guard MerchantNames.sameMerchant(key, other)
                    || twins.contains(where: { MerchantNames.sameMerchant($0, other) })
                else { continue }
                visits += row.int("n") ?? 0
                spent += abs(row.double("total") ?? 0)
            }
            return Place(
                key: key, name: names.name(forKey: key) ?? PayeeText.humanize(key),
                lat: lat, lon: lon, visits: visits, spent: spent
            )
        }
        .sorted { $0.spent > $1.spent }
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
