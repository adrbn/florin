import Foundation

/// Shaping the envelopes themselves, not just their amounts.
///
/// The seeded list is a starting point, not a verdict: someone who never eats
/// out and rides a motorbike needs different envelopes than the defaults, and
/// a budget made of categories that do not match a life gets abandoned in a
/// month. So the categories are editable from the phone — created, renamed,
/// retired — in the one screen where the user is already thinking about them.
///
/// Server mode does not go through here. There, categories live on the server
/// and are edited there; the device is a view of that ledger, not a second
/// authority over it.
enum LocalCategories {
    enum Failure: LocalizedError {
        case duplicate(String)
        var errorDescription: String? {
            switch self {
            case let .duplicate(name): Strings.device("v2.plan.duplicateCategory", "« {name} » existe déjà dans ce groupe.", ["name": name])
            }
        }
    }

    @discardableResult
    static func create(
        store: LocalStore, groupId: String, name: String, emoji: String, isFixed: Bool
    ) throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = try store.database.scalar(
            "SELECT id FROM categories WHERE group_id = ? AND lower(name) = lower(?)",
            [.text(groupId), .text(clean)]
        )
        if taken?.string != nil { throw Failure.duplicate(clean) }

        let order = try store.database.scalar(
            "SELECT coalesce(max(display_order), -1) + 1 FROM categories WHERE group_id = ?",
            [.text(groupId)]
        )?.int ?? 0

        let id = UUID().uuidString
        try store.database.run(
            """
            INSERT INTO categories (id, group_id, name, emoji, is_fixed, display_order)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            [
                .text(id), .text(groupId), .text(clean),
                emoji.isEmpty ? .null : .text(emoji),
                .integer(isFixed ? 1 : 0), .integer(Int64(order)),
            ]
        )
        return id
    }

    static func update(
        store: LocalStore, id: String, name: String, emoji: String, isFixed: Bool
    ) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = try store.database.scalar(
            """
            SELECT c.id FROM categories c
            WHERE c.group_id = (SELECT group_id FROM categories WHERE id = ?)
              AND lower(c.name) = lower(?) AND c.id <> ?
            """,
            [.text(id), .text(clean), .text(id)]
        )
        if taken?.string != nil { throw Failure.duplicate(clean) }

        try store.database.run(
            "UPDATE categories SET name = ?, emoji = ?, is_fixed = ? WHERE id = ?",
            [.text(clean), emoji.isEmpty ? .null : .text(emoji), .integer(isFixed ? 1 : 0), .text(id)]
        )
    }

    /// What "delete" means depends on whether the envelope has a past.
    ///
    /// An unused category is removed outright. One that has already classified
    /// transactions is archived instead: deleting it would either orphan those
    /// rows or rewrite history, and a year of spending should not disappear
    /// from the charts because its label stopped being useful. Archived
    /// categories leave the picker and the plan; their transactions keep them.
    @discardableResult
    static func remove(store: LocalStore, id: String) throws -> Bool {
        let used = try store.database.scalar(
            "SELECT count(*) FROM transactions WHERE category_id = ? AND deleted_at IS NULL",
            [.text(id)]
        )?.int ?? 0

        if used > 0 {
            try store.database.run(
                "UPDATE categories SET is_archived = 1 WHERE id = ?", [.text(id)]
            )
            return false
        }
        try store.database.run("DELETE FROM monthly_budgets WHERE category_id = ?", [.text(id)])
        try store.database.run("DELETE FROM categories WHERE id = ?", [.text(id)])
        return true
    }
}
