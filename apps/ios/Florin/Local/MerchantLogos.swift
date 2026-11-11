import Combine
import SwiftUI
import UIKit

/*
 * What a merchant's bubble shows: its logo, or an emoji someone chose.
 *
 * Initials and category icons tell rows apart; a logo is recognised before
 * it is read, which is why every neobank shows one. The usual way to get
 * them — a logo service queried with the merchant's name — would tell that
 * service where each of its users shops, and Florin's whole promise is that
 * nobody learns that. So the phone asks the merchant's own website for its
 * icon, the way a browser would, with no cookies, and keeps it.
 *
 * The site comes from the person (the merchant sheet), or from
 * `KnownMerchants` for the big names. An emoji, when chosen, wins over the
 * logo. With neither, the bubble stays what it was.
 */
@MainActor
final class MerchantLogos: ObservableObject {
    static let shared = MerchantLogos()

    /// Bumps when a logo arrives or a merchant's mark changes.
    @Published private(set) var revision = 0

    static let enabledKey = "florin.merchantLogos"

    struct Mark: Equatable {
        var domain: String?
        var emoji: String?
        /// Une image a été choisie pour ce marchand. Le drapeau seulement :
        /// charger les vignettes de tous les marchands pour dessiner une liste
        /// coûterait bien plus que de lire celles qu'on affiche.
        var hasPicture = false
    }

    enum Face {
        case emoji(String)
        case logo(UIImage)

        var emoji: String? { if case .emoji(let e) = self { e } else { nil } }
        var logo: UIImage? { if case .logo(let i) = self { i } else { nil } }
    }

    private var marks: [String: Mark]?
    private var keys: [String: String] = [:]
    private var images: [String: UIImage] = [:]
    /// Les images choisies à la main, par clé de marchand, lues à la demande.
    private var pictures: [String: UIImage] = [:]
    private var missed: Set<String> = []
    private var pending: [String] = []
    private var queued: Set<String> = []
    private var running = 0

    private static let parallel = 4

    var enabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    // MARK: - Reading

    func face(for payee: String) -> Face? {
        face(forKey: key(payee))
    }

    /// La tête d'une ligne : celle de son achat en plusieurs fois quand il en
    /// a un et qu'on la lui a donnée, sinon celle de son marchand — qui est
    /// le rail, et ne dit pas lequel. Voir `MerchantNames.planKey`.
    func face(for payee: String, plan: String?) -> Face? {
        if let plan, let own = face(forKey: MerchantNames.planKey(plan)) { return own }
        return face(for: payee)
    }

    func face(forKey key: String) -> Face? {
        guard !key.isEmpty else { return nil }
        // Sous sa clé, ou sous celle que la banque a tronquée — voir
        // `MerchantNames.resolve` : la tête suit le nom.
        let found = located(key)
        let mark = found?.mark
        // Une image choisie pour ce marchand passe avant tout : c'est le
        // geste le plus délibéré des trois, et le plus précis.
        if mark?.hasPicture == true, let found, let picture = picture(forKey: found.key) {
            return .logo(picture)
        }
        if let emoji = mark?.emoji, !emoji.isEmpty { return .emoji(emoji) }
        guard enabled, let domain = mark?.domain ?? knownDomain(forKey: key) else { return nil }
        return logo(domain: domain).map(Face.logo)
    }

    func mark(forKey key: String) -> Mark? {
        located(key)?.mark
    }

    /*
     * La marque de ce marchand — la sienne d'abord, celle de son nom ensuite.
     *
     * Une boutique encaisse sous sa raison sociale et se saisit à la main
     * sous le nom qu'on lui donne : deux libellés sans une lettre en commun,
     * dont un seul a reçu une tête. Leur donner le même nom est la seule
     * façon qu'on ait de dire que c'est le même endroit — alors la tête suit.
     *
     * Rien n'est recopié : le lien se lit à chaque affichage, donc changer la
     * photo d'un côté la change des deux, et renommer le défait.
     */
    private func located(_ key: String) -> (key: String, mark: Mark)? {
        if let own = marked(key) { return own }
        for twin in MerchantNames.shared.keysSharingName(with: key) {
            if let found = marked(twin) { return found }
        }
        // Le nom donné EST un libellé. Le terminal encaisse sous un nom, la
        // ligne tapée à la main en porte un autre, et c'est celle-là qui a
        // reçu la photo — mais elle n'a jamais été renommée, donc elle ne
        // figure dans aucune liste de jumeaux. La chercher sous son nom la
        // retrouve.
        if let name = MerchantNames.shared.name(forKey: key),
           let found = marked(MerchantNames.key(name)) { return found }
        return sameSite(key)
    }

    /*
     * Deux libellés que la liste des grandes enseignes envoie sur le même
     * site sont le même marchand.
     *
     * Un abonnement et une commande arrivent sous deux libellés différents du
     * même commerçant. Sans cela, la photo choisie pour l'un ne vaut que pour
     * lui, et l'autre retombe sur l'icône que le site publie — souvent pâle à
     * côté d'une marque posée à la main.
     *
     * Seules une photo et un emoji s'héritent : un site hérité n'apporterait
     * rien de plus que celui qu'on vient d'y lire.
     */
    private func sameSite(_ key: String) -> (key: String, mark: Mark)? {
        guard let site = KnownMerchants.domain(forKey: key) else { return nil }
        var best: (key: String, mark: Mark)?
        for (other, mark) in table() where other != key {
            guard mark.hasPicture || mark.emoji?.isEmpty == false else { continue }
            guard KnownMerchants.domain(forKey: other) == site else { continue }
            if best == nil || other.count > best!.key.count { best = (other, mark) }
        }
        return best
    }

    /// Sous sa clé, ou sous une troncature de celle-ci. La plus longue gagne :
    /// c'est la plus précise.
    private func marked(_ key: String) -> (key: String, mark: Mark)? {
        let table = table()
        if let exact = table[key] { return (key, exact) }
        guard key.count >= MerchantNames.truncationFloor else { return nil }
        var best: (key: String, mark: Mark)?
        for (other, mark) in table where MerchantNames.sameMerchant(other, key) {
            if best == nil || other.count > best!.key.count { best = (other, mark) }
        }
        return best
    }

    /// L'image choisie pour ce marchand, lue une fois puis gardée.
    func picture(forKey key: String) -> UIImage? {
        if let hit = pictures[key] { return hit }
        guard !key.isEmpty, let store = LocalStore.shared,
              let data = try? store.database.scalar(
                  "SELECT image FROM merchant_marks WHERE match_key = ?", [.text(key)]
              )?.data,
              let image = UIImage(data: data)
        else { return nil }
        pictures[key] = image
        return image
    }

    /*
     * Une image donnée par son propriétaire.
     *
     * Une photo d'iPhone pèse plusieurs mégaoctets et n'a rien à faire dans
     * une base qu'on sauvegarde et qu'on recopie. Elle est donc réduite à la
     * taille où elle sera vue, recadrée au carré depuis son centre — les
     * bulles sont rondes, une image déformée s'y verrait tout de suite — et
     * réencodée : quelques dizaines de kilo-octets, comme un logo.
     */
    func setPicture(key: String, image: UIImage?) throws {
        guard let store = LocalStore.shared, !key.isEmpty else { return }
        pictures[key] = nil
        guard let image else {
            try store.database.run(
                "UPDATE merchant_marks SET image = NULL, updated_at = datetime('now') WHERE match_key = ?",
                [.text(key)]
            )
            // Un marchand dont il ne reste rien ne garde pas de ligne.
            try store.database.run(
                """
                DELETE FROM merchant_marks
                WHERE match_key = ? AND domain IS NULL AND emoji IS NULL AND image IS NULL
                """,
                [.text(key)]
            )
            invalidate()
            return
        }
        guard let data = Self.thumbnail(image) else { return }
        try store.database.run(
            """
            INSERT INTO merchant_marks (match_key, image) VALUES (?, ?)
            ON CONFLICT(match_key) DO UPDATE SET
                image = excluded.image,
                updated_at = datetime('now')
            """,
            [.text(key), .blob(data)]
        )
        invalidate()
    }

    /// Le côté du carré conservé : trois fois la plus grande bulle, de quoi
    /// rester net sur un écran à trois points par pixel.
    nonisolated static let pictureSide: CGFloat = 180

    /// Recadre au centre, réduit, puis encode. Nil si l'image est illisible.
    nonisolated static func thumbnail(_ image: UIImage) -> Data? {
        let width = image.size.width, height = image.size.height
        guard width > 0, height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let box = CGSize(width: pictureSide, height: pictureSide)
        /*
         * Un logo est un MOT, et un mot est plus large que haut.
         *
         * Recadré au carré depuis son centre, il en perdait les deux bouts :
         * une marque de cinq lettres n'en montrait plus que trois, sans que
         * rien ne dise que le reste existait. Une photo, elle, se recadre très
         * bien — d'où un partage sur la FORME et non sur l'usage : au-delà
         * d'un quart de différence entre les côtés, l'image entre entière dans
         * le carré et le blanc comble ce qui reste ; en deçà, on recadre comme
         * avant. Dans les deux cas le rapport est gardé : les bulles sont
         * rondes, une image déformée s'y verrait tout de suite.
         */
        let oblong = max(width, height) / min(width, height) > 1.25
        let ratio = oblong
            ? min(box.width / width, box.height / height)
            : max(box.width / width, box.height / height)
        let drawn = UIGraphicsImageRenderer(size: box, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: box))
            let drawnSize = CGSize(width: width * ratio, height: height * ratio)
            image.draw(in: CGRect(
                x: (box.width - drawnSize.width) / 2,
                y: (box.height - drawnSize.height) / 2,
                width: drawnSize.width, height: drawnSize.height
            ))
        }
        return drawn.jpegData(compressionQuality: 0.82)
    }

    /// The site the list knows for this merchant — under the bank's label or
    /// under the name it was given ("SARL MEDIA SERVICES" renamed "Netflix").
    func knownDomain(forKey key: String) -> String? {
        KnownMerchants.domain(forKey: key)
            ?? MerchantNames.shared.name(forKey: key).flatMap(KnownMerchants.domain(forKey:))
    }

    /// The logo for a site, if it is here; otherwise it is fetched and the
    /// views are told when it lands.
    func logo(domain: String) -> UIImage? {
        if let hit = images[domain] { return hit }
        if missed.contains(domain) { return nil }
        if let stored = LogoCache.read(domain) {
            images[domain] = stored
            return stored
        }
        if LogoCache.recentlyMissed(domain) {
            missed.insert(domain)
            return nil
        }
        enqueue(domain)
        return nil
    }

    /// The key is computed per distinct label, not per row per redraw.
    private func key(_ payee: String) -> String {
        if let hit = keys[payee] { return hit }
        let key = MerchantNames.key(payee)
        keys[payee] = key
        return key
    }

    // MARK: - Writing

    func setMark(key: String, domain: String?, emoji: String?) throws {
        guard let store = LocalStore.shared, !key.isEmpty else { return }
        let domain = domain.flatMap(Self.normalizedDomain)
        let emoji = emoji.flatMap { $0.isEmpty ? nil : $0 }
        if domain == nil, emoji == nil {
            // Sans site ni emoji il peut rester une image : on n'efface la
            // ligne que lorsqu'il n'y a plus rien du tout.
            try store.database.run(
                "UPDATE merchant_marks SET domain = NULL, emoji = NULL WHERE match_key = ?",
                [.text(key)]
            )
            try store.database.run(
                "DELETE FROM merchant_marks WHERE match_key = ? AND image IS NULL", [.text(key)]
            )
        } else {
            try store.database.run(
                """
                INSERT INTO merchant_marks (match_key, domain, emoji) VALUES (?, ?, ?)
                ON CONFLICT(match_key) DO UPDATE SET
                    domain = excluded.domain,
                    emoji = excluded.emoji,
                    updated_at = datetime('now')
                """,
                [.text(key), domain.map { .text($0) } ?? .null, emoji.map { .text($0) } ?? .null]
            )
        }
        // A site typed on purpose is worth another try, even one that failed.
        if let domain {
            missed.remove(domain)
            LogoCache.forgetMiss(domain)
        }
        invalidate()
    }

    func invalidate() {
        marks = nil
        pictures.removeAll()
        revision += 1
    }

    /// Turning logos back on retries the sites that failed while offline.
    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        missed.removeAll()
        revision += 1
    }

    /// "https://www.Le-Comptoir.fr/menu" → "le-comptoir.fr". Nil when it is not a site.
    nonisolated static func normalizedDomain(_ text: String) -> String? {
        var host = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let range = host.range(of: "://") { host = String(host[range.upperBound...]) }
        host = String(host.prefix { $0 != "/" && $0 != "?" && $0 != "#" })
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard !host.isEmpty, host.unicodeScalars.allSatisfy(allowed.contains),
              let tld = host.split(separator: ".").last, host.contains("."),
              tld.count >= 2, tld.allSatisfy(\.isLetter),
              !host.hasPrefix("."), !host.hasPrefix("-"), !host.contains("..")
        else { return nil }
        return host
    }

    // MARK: - Fetching

    private func enqueue(_ domain: String) {
        guard !queued.contains(domain) else { return }
        queued.insert(domain)
        pending.append(domain)
        pump()
    }

    /// A few at a time: a first screenful can name fifty merchants.
    private func pump() {
        while running < Self.parallel, !pending.isEmpty {
            let domain = pending.removeFirst()
            running += 1
            Task {
                let image = await LogoFetcher.fetch(domain: domain)
                self.finish(domain, image)
            }
        }
    }

    private func finish(_ domain: String, _ image: UIImage?) {
        running -= 1
        queued.remove(domain)
        if let image {
            images[domain] = image
            LogoCache.write(image, for: domain)
        } else {
            missed.insert(domain)
            LogoCache.rememberMiss(domain)
        }
        revision += 1
        pump()
    }

    private func table() -> [String: Mark] {
        if let marks { return marks }
        var read: [String: Mark] = [:]
        if let store = LocalStore.shared,
           let rows = try? store.database.query(
               """
               SELECT match_key, domain, emoji, image IS NOT NULL AS has_image
               FROM merchant_marks
               """
           ) {
            for row in rows {
                guard let key = row.string("match_key") else { continue }
                read[key] = Mark(
                    domain: row.string("domain"), emoji: row.string("emoji"),
                    hasPicture: (row.int("has_image") ?? 0) == 1
                )
            }
        }
        marks = read
        return read
    }
}

// MARK: - The site's own icon

enum LogoFetcher {
    /*
     * A browser's visit, minus what a browser leaves behind.
     *
     * Ephemeral: no cookies kept or sent, no cache shared with anything else.
     * A Safari user agent because a good share of big sites answer an unknown
     * client with a bot wall instead of a page.
     */
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 "
                + "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
        ]
        return URLSession(configuration: config)
    }()

    /// Big enough to fill the bubble without a visible blur, at 3×.
    static let crisp: CGFloat = 96

    /*
     * The icon the site declares, then the two it most likely has anyway.
     *
     * The home page names its icons in <link rel="…icon…">; the touch icon is
     * the one made for exactly this — a square, 180 px, meant for a home
     * screen. Failing that, /apple-touch-icon.png and /favicon.ico are where
     * nearly every site keeps them without saying so.
     */
    static func fetch(domain: String) async -> UIImage? {
        guard let home = URL(string: "https://\(domain)/") else { return nil }
        var candidates: [URL] = []
        if let (data, response) = try? await session.data(from: home),
           let html = String(data: data.prefix(400_000), encoding: .utf8)
               ?? String(data: data.prefix(400_000), encoding: .isoLatin1) {
            candidates += iconLinks(in: html, base: response.url ?? home)
        }
        for path in ["apple-touch-icon.png", "apple-touch-icon-precomposed.png", "favicon.ico"] {
            if let url = URL(string: path, relativeTo: home)?.absoluteURL { candidates.append(url) }
        }

        var best: UIImage?
        var seen = Set<URL>()
        for url in candidates where seen.insert(url).inserted {
            guard seen.count <= 6 else { break }
            guard let image = await image(at: url) else { continue }
            if pixels(image) > pixels(best) { best = image }
            if pixels(image) >= crisp { break }
        }
        guard let best, pixels(best) >= 16 else { return nil }
        return downscaled(best, to: 180)
    }

    /// The icons a page declares, the most suitable first.
    static func iconLinks(in html: String, base: URL) -> [URL] {
        guard let tag = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: .caseInsensitive),
              let attribute = try? NSRegularExpression(
                  pattern: "([a-zA-Z-]+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
              ) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var found: [(url: URL, score: Int)] = []
        for match in tag.matches(in: html, range: range) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let text = String(html[tagRange])
            var attrs: [String: String] = [:]
            for a in attribute.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let name = Range(a.range(at: 1), in: text) else { continue }
                let value = (2...4).lazy
                    .compactMap { Range(a.range(at: $0), in: text) }
                    .first.map { String(text[$0]) } ?? ""
                attrs[text[name].lowercased()] = value
            }
            guard let rel = attrs["rel"]?.lowercased(), rel.contains("icon"),
                  let href = attrs["href"], !href.isEmpty, !href.hasPrefix("data:"),
                  !href.lowercased().hasSuffix(".svg"), attrs["type"]?.contains("svg") != true,
                  let url = URL(string: href.trimmingCharacters(in: .whitespaces), relativeTo: base)?.absoluteURL,
                  url.scheme == "https" || url.scheme == "http"
            else { continue }
            let size = attrs["sizes"]
                .flatMap { $0.lowercased().split(separator: "x").first }
                .flatMap { Int($0) } ?? 0
            let touch = rel.contains("apple-touch-icon") ? 1000 : 0
            found.append((url, touch + size))
        }
        return found.sorted { $0.score > $1.score }.map(\.url)
    }

    private static func image(at url: URL) async -> UIImage? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
              data.count < 2_000_000
        else { return nil }
        return UIImage(data: data)
    }

    static func pixels(_ image: UIImage?) -> CGFloat {
        guard let image else { return 0 }
        return min(image.size.width, image.size.height) * image.scale
    }

    private static func downscaled(_ image: UIImage, to side: CGFloat) -> UIImage {
        guard pixels(image) > side else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let ratio = side / pixels(image)
        let size = CGSize(width: image.size.width * image.scale * ratio, height: image.size.height * image.scale * ratio)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Kept on the phone

/// Logos in Caches — iOS may clear them, and they come back on the next look.
/// A site that had no usable icon is not asked again for a week.
enum LogoCache {
    private static let folder: URL? = {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let url = base.appendingPathComponent("MerchantLogos", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static let retryAfter: TimeInterval = 7 * 24 * 3600

    private static func file(_ domain: String, _ ext: String) -> URL? {
        folder?.appendingPathComponent("\(domain).\(ext)")
    }

    static func read(_ domain: String) -> UIImage? {
        guard let url = file(domain, "png"), let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func write(_ image: UIImage, for domain: String) {
        guard let url = file(domain, "png"), let data = image.pngData() else { return }
        try? data.write(to: url, options: .atomic)
        forgetMiss(domain)
    }

    static func recentlyMissed(_ domain: String) -> Bool {
        guard let url = file(domain, "miss"),
              let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        else { return false }
        return Date().timeIntervalSince(date) < retryAfter
    }

    static func rememberMiss(_ domain: String) {
        guard let url = file(domain, "miss") else { return }
        try? Data().write(to: url, options: .atomic)
    }

    static func forgetMiss(_ domain: String) {
        guard let url = file(domain, "miss") else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
