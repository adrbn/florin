import Foundation

/// Translations, served with the data.
///
/// The dictionary comes from the server's `/api/v2/overview` feed, which means
/// the phone speaks whatever language Florin is set to rather than whatever the
/// device is set to — the setting lives with the finances, not with the handset.
/// It also means a native screen is translated the moment the web one is; there
/// is no second copy of the strings to keep in step.
struct Strings: Sendable {
    private let table: [String: String]
    let localeTag: String

    init(_ table: [String: String], localeTag: String) {
        self.table = table
        self.localeTag = localeTag
    }

    /// Empty table: renders the inline fallbacks, which is what the very first
    /// frame before the feed arrives should show.
    static let empty = Strings([:], localeTag: "fr-FR")

    /*
     * The language before there is any data to carry it.
     *
     * Onboarding, the server form and the bank setup all run before a feed
     * exists — and they are the first screens anyone sees, so falling back to
     * the author's French there means a new English or Dutch user meets the
     * app in a language they did not choose. This reads the same bundled
     * dictionary the offline ledger uses, keyed on the handset's language,
     * because at that moment the handset is the only preference there is.
     *
     * Resolved once: it reads a file, and these screens ask for it per frame.
     */
    /// The language the app is in: the one chosen in settings, or the
    /// handset's until someone chooses.
    ///
    /// `florin.locale` is empty by default, which means "follow the phone" —
    /// the right behaviour for a fresh install, and one a person can override
    /// without having to change the language of their whole phone.
    static var preferredShortLocale: String {
        let chosen = UserDefaults.standard.string(forKey: "florin.locale") ?? ""
        if !chosen.isEmpty { return chosen }
        return LocalQueries.shortLocale(Locale.preferredLanguages.first ?? "en")
    }

    static func tag(for short: String) -> String {
        ["fr": "fr-FR", "nl": "nl-NL"][short] ?? "en-US"
    }

    /*
     * Cached per language rather than resolved once.
     *
     * This used to be a `static let`, read from the handset at first use and
     * fixed for the life of the process — so choosing a language in settings
     * left every pre-login screen, all of onboarding and the whole bank setup
     * speaking the old one until the app was killed. It is keyed on the choice
     * now, and still reads the file only once per language, because these
     * screens ask for it on every frame.
     */
    private static var cache = [String: Strings]()

    static var device: Strings {
        let short = preferredShortLocale
        if let hit = cache[short] { return hit }
        let table = (try? LocalQueries.strings(for: short)) ?? [:]
        let value = Strings(table, localeTag: tag(for: short))
        cache[short] = value
        return value
    }

    /// Drop the cached tables, so the next read picks up a new choice.
    static func forget() { cache.removeAll() }

    func callAsFunction(_ key: String, _ fallback: String) -> String {
        table[key] ?? fallback
    }

    /// Interpolates `{name}` placeholders, and picks the `_one` variant when a
    /// `count` argument lands in the locale's "one" plural category — French
    /// counts 0 as one ("0 opération"), English does not.
    func callAsFunction(_ key: String, _ fallback: String, _ args: [String: CustomStringConvertible]) -> String {
        var resolved = key
        if let count = args["count"] as? Int {
            let variant = "\(key)_\(pluralCategory(count))"
            if table[variant] != nil { resolved = variant }
        }
        var text = table[resolved] ?? fallback
        for (name, value) in args {
            text = text.replacingOccurrences(of: "{\(name)}", with: value.description)
        }
        return text
    }

    /// `Intl.PluralRules` has no Foundation equivalent, so encode the two rules
    /// the shipped locales actually need instead of pretending to be general.
    private func pluralCategory(_ count: Int) -> String {
        let language = localeTag.split(separator: "-").first.map(String.init) ?? "en"
        switch language {
        case "fr":
            return abs(count) < 2 ? "one" : "other"
        default:
            return abs(count) == 1 ? "one" : "other"
        }
    }
}
