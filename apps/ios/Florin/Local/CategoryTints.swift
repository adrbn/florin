import Combine
import SwiftUI

/*
 * La couleur qu'on a choisie pour une catégorie.
 *
 * Les pastilles tiraient déjà une teinte du nom (`Florin.seriesColor`) : c'est
 * stable, mais tiré au sort. Huit teintes pour trente enveloppes, donc des
 * jumelles partout, et aucune façon de dire « les courses, c'est le vert ».
 *
 * Le rang est écrit dans `categories.display_color` sous la même forme que
 * pour les comptes — « series-3 », un RANG et non un code hexadécimal, pour
 * que la couleur suive le thème au lieu de jurer avec lui. Voir
 * `HomeCards.colorSlot`, qui en est la seule lecture.
 *
 * Deux index pour une table : l'identifiant, parce que c'est ce qu'un
 * éditeur tient en main, et le nom replié, parce que c'est tout ce qu'une
 * pastille reçoit. Le nom est ce que la base écrit, pas la traduction
 * affichée — une catégorie ajoutée à la main n'en a d'ailleurs qu'un.
 *
 * Le même contrat que `MerchantNames` : lu une fois, gardé, et un numéro de
 * révision que les vues observent pour se redessiner quand il change. Les
 * écrans qui n'ont pas de grand livre local (mode serveur) n'y trouvent rien
 * et retombent sur le hachage, comme avant.
 */
final class CategoryTints: ObservableObject {
    static let shared = CategoryTints()

    /// Change à chaque couleur posée : une vue qui l'observe se redessine.
    @Published private(set) var revision = 0

    /// Le grand livre à lire. Celui de l'app, sauf pour une épreuve, qui s'en
    /// pose un à elle — c'est la seule raison d'être de cette porte.
    var ledger: LocalStore?
    private var book: LocalStore? { ledger ?? LocalStore.shared }

    private let lock = NSLock()
    private var byId: [String: Int]?
    private var byName: [String: Int] = [:]

    // MARK: - Lecture

    /// Le rang choisi pour cette catégorie, s'il y en a un.
    func slot(forId id: String) -> Int? {
        load()
        lock.lock()
        defer { lock.unlock() }
        return byId?[id]
    }

    /// La couleur choisie pour ce nom de catégorie, s'il y en a une.
    ///
    /// Rend `nil` plutôt qu'une teinte de repli : l'appelant sait, lui, ce
    /// qu'il dessine quand personne n'a choisi — un hachage dans la plupart
    /// des thèmes, de l'encre en éditorial.
    func color(forName name: String) -> Color? {
        slot(forName: name).map { Florin.series[$0] }
    }

    /*
     * Le RANG, et pas la couleur, pour qui veut comparer.
     *
     * `Florin.series` fabrique un `Color` dynamique neuf à chaque accès — il
     * relit la palette au rendu, c'est tout l'intérêt — donc deux teintes
     * identiques ne sont jamais égales entre elles. Un rang, si.
     */
    func slot(forName name: String) -> Int? {
        guard !name.isEmpty else { return nil }
        load()
        lock.lock()
        let slot = byName[Self.fold(name)]
        lock.unlock()
        guard let slot, slot >= 0, slot < Florin.seriesCount else { return nil }
        return slot
    }

    /// Replié comme on compare deux noms : sans casse ni accent.
    private static func fold(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func load() {
        lock.lock()
        let already = byId != nil
        lock.unlock()
        guard !already, let store = book else { return }

        let rows = (try? store.database.query(
            "SELECT id, name, display_color FROM categories WHERE display_color IS NOT NULL"
        )) ?? []
        var ids: [String: Int] = [:]
        var names: [String: Int] = [:]
        for row in rows {
            guard let id = row.string("id"),
                  let slot = HomeCards.colorSlot(row.string("display_color"))
            else { continue }
            ids[id] = slot
            if let name = row.string("name") { names[Self.fold(name)] = slot }
        }
        lock.lock()
        byId = ids
        byName = names
        lock.unlock()
    }

    // MARK: - Écriture

    /// Pose le rang, ou le retire pour revenir à l'automatique.
    func set(_ slot: Int?, forId id: String) {
        guard let store = book else { return }
        try? store.database.run(
            "UPDATE categories SET display_color = ? WHERE id = ?",
            [slot.map { .text(HomeCards.slotName($0)) } ?? .null, .text(id)]
        )
        invalidate()
    }

    /// Relit la table au prochain affichage, et le fait savoir.
    func invalidate() {
        lock.lock()
        byId = nil
        byName = [:]
        lock.unlock()
        if Thread.isMainThread {
            revision += 1
        } else {
            DispatchQueue.main.async { self.revision += 1 }
        }
    }
}
