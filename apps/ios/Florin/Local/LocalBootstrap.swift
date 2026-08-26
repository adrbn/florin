import Foundation

/// What a fresh install finds when it opens the app.
///
/// The serverless build has to be usable by someone who has never run Florin
/// anywhere — not only by a person restoring an existing ledger. An empty
/// database with no categories is not a budgeting app; it is a form. So the
/// first launch lays down the same starting categories the web and desktop
/// onboarding already create, in the same language, and stops there: accounts
/// and money are the user's to add.
///
/// The category list is not retyped here. `SeedCategories.json` is generated
/// from `packages/core/src/i18n/seed-categories.ts`, the one definition the
/// other two surfaces use, so a category added there reaches the phone by
/// regenerating the file rather than by someone remembering to.
enum LocalBootstrap {
    struct SeedCategory: Decodable {
        let name: String
        let emoji: String
        let isFixed: Bool?
    }

    struct SeedGroup: Decodable {
        let name: String
        let kind: String
        let color: String
        let categories: [SeedCategory]
    }

    /// Ran already? Recorded in `settings` rather than in UserDefaults, so that
    /// deleting the database and keeping the app's preferences cannot leave a
    /// ledger that believes it was seeded when it holds nothing.
    private static let marker = "bootstrapped_at"

    static func run(on store: LocalStore, locale: String) throws -> Bool {
        let already = try store.database.scalar(
            "SELECT value FROM settings WHERE key = ?", [.text(marker)]
        )
        guard already?.string == nil else { return false }

        let groups = try seedGroups(for: locale)
        try store.database.transaction {
            for (groupIndex, group) in groups.enumerated() {
                let groupId = UUID().uuidString
                try store.database.run(
                    """
                    INSERT INTO category_groups (id, name, kind, color, display_order)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    [
                        .text(groupId), .text(group.name), .text(group.kind),
                        .text(group.color), .integer(Int64(groupIndex)),
                    ]
                )
                for (index, category) in group.categories.enumerated() {
                    try store.database.run(
                        """
                        INSERT INTO categories (id, group_id, name, emoji, is_fixed, display_order)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                        [
                            .text(UUID().uuidString), .text(groupId), .text(category.name),
                            .text(category.emoji),
                            .integer(category.isFixed == true ? 1 : 0), .integer(Int64(index)),
                        ]
                    )
                }
            }
            try store.database.run(
                "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                [.text(marker), .text(ISO8601DateFormatter().string(from: Date()))]
            )
        }
        return true
    }

    /// The device's language decides the labels, the way the wizard does on the
    /// other surfaces. Anything unsupported falls back to English rather than
    /// to whichever locale happens to be first in the file.
    private static func seedGroups(for locale: String) throws -> [SeedGroup] {
        guard let url = Bundle.main.url(forResource: "SeedCategories", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { throw LocalStore.BootstrapFailure.missingSeed }

        let all = try JSONDecoder().decode([String: [SeedGroup]].self, from: data)
        let lower = locale.lowercased()
        let match = all.keys.first { lower.hasPrefix($0) }
        return all[match ?? "en"] ?? []
    }
}

extension LocalStore {
    enum BootstrapFailure: LocalizedError {
        case missingSeed
        var errorDescription: String? {
            "The bundled starting categories are missing from the app."
        }
    }

    /// Rows the device holds that a person would recognise as "my setup".
    func categoryCount() throws -> Int {
        try database.scalar("SELECT count(*) FROM categories")?.int ?? 0
    }
}
