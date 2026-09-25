import Foundation

/*
 * Les comptes du grand livre, reconnus à leur numéro.
 *
 * Une banque qui annonce un virement avant de le comptabiliser n'a pas encore
 * de contrepartie à nommer, alors elle nomme la ligne d'après le compte où
 * l'argent atterrit : « FR76… DUPONT ». Le libellé ne désigne donc personne —
 * c'est le compte qu'on est en train de regarder — et l'afficher revient à
 * dire à quelqu'un son propre nom de famille en guise de commerçant.
 *
 * Reconnaître ce cas demande la seule chose qu'un libellé ne porte jamais : la
 * liste des comptes. Elle est lue une fois et gardée, comme les renommages.
 */
final class OwnAccounts {
    static let shared = OwnAccounts()

    private let lock = NSLock()
    private var loaded: Set<String>?

    /// Le libellé ne nomme qu'un compte du grand livre.
    func named(by payee: String) -> Bool {
        let folded = payee.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let squeezed = folded.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        guard squeezed.count >= 15 else { return false }
        let numbers = table()
        guard !numbers.isEmpty else { return false }
        return numbers.contains { squeezed.contains($0) }
    }

    func invalidate() {
        lock.lock()
        loaded = nil
        lock.unlock()
    }

    private func table() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        if let loaded { return loaded }
        let read = Self.read()
        loaded = read
        return read
    }

    private static func read() -> Set<String> {
        guard let store = LocalStore.shared,
              let rows = try? store.database.query(
                  "SELECT iban FROM accounts WHERE iban IS NOT NULL AND iban != ''"
              )
        else { return [] }
        var out = Set<String>()
        for row in rows {
            guard let iban = row.string("iban") else { continue }
            let squeezed = iban
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
            // Un numéro trop court ne prouve rien s'il se retrouve dans un
            // libellé par hasard.
            guard squeezed.count >= 15 else { continue }
            out.insert(squeezed)
        }
        return out
    }
}
