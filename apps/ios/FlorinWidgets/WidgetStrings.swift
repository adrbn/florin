import Foundation

/// The widget's reader for the app's string table.
///
/// It cannot use `Strings` itself: that resolves the language from
/// `UserDefaults.standard`, and an extension has its own — the widget would
/// read an empty preference and settle on the handset's language while the app
/// beside it spoke the one its owner picked. The snapshot carries the tag the
/// app was last displaying, which is the better source anyway: the widget
/// should say what the app says, not what iOS guesses.
///
/// The table is the same `Strings.json`, listed in this target so it lands in
/// the extension's own bundle.
struct WidgetStrings {
    private let table: [String: String]
    private let language: String

    init(locale tag: String) {
        language = Self.short(tag)
        guard let url = Bundle.main.url(forResource: "Strings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let all = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        else {
            table = [:]
            return
        }
        table = all[language] ?? all["en"] ?? [:]
    }

    func callAsFunction(_ key: String, _ fallback: String) -> String {
        table[key] ?? fallback
    }

    /// Interpolates `{name}`, and picks the `_one` variant the way the app
    /// does — French counts 0 as one ("0 jour restant"), English does not.
    func callAsFunction(
        _ key: String, _ fallback: String, _ args: [String: CustomStringConvertible]
    ) -> String {
        var resolved = key
        if let count = args["count"] as? Int {
            let variant = "\(key)_\(plural(count))"
            if table[variant] != nil { resolved = variant }
        }
        var text = table[resolved] ?? fallback
        for (name, value) in args {
            text = text.replacingOccurrences(of: "{\(name)}", with: value.description)
        }
        return text
    }

    private func plural(_ count: Int) -> String {
        switch language {
        case "fr": abs(count) < 2 ? "one" : "other"
        default: abs(count) == 1 ? "one" : "other"
        }
    }

    private static func short(_ tag: String) -> String {
        let lower = tag.lowercased()
        for candidate in ["fr", "nl"] where lower.hasPrefix(candidate) { return candidate }
        return "en"
    }
}
