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
