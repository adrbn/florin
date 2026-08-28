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

    /// How many transactions carry this category. What "delete" can mean
    /// depends entirely on this number.
    static func usage(store: LocalStore, id: String) throws -> Int {
        try store.database.scalar(
            "SELECT count(*) FROM transactions WHERE category_id = ? AND deleted_at IS NULL",
            [.text(id)]
        )?.int ?? 0
    }

    /*
     * Deleting a category is three different decisions.
     *
     * The screen used to make one of them silently: a category with history was
     * archived, and the confirmation said so while its button said "Supprimer".
     * The user was told the outcome after choosing, in language describing an
     * action they had not asked for.
     *
     * Nothing here is guessed on the user's behalf. An unused category is just
     * deleted; one with transactions asks what should become of them, because
     * only the person who filed them knows.
     */
    enum Removal {
        /// Move the transactions somewhere else, then delete the category.
        case reassign(to: String)
        /// Delete it and leave the transactions unclassified — they re-enter
        /// the review queue, because they now need a decision that was made
        /// for them once and has just been withdrawn.
        case detach
        /// Keep the transactions labelled and take the category out of the
        /// plan and the pickers. Nothing is lost; the charts still read.
        case archive
    }

    static func remove(store: LocalStore, id: String, how: Removal) throws {
        try store.database.transaction {
            switch how {
            case let .reassign(target):
                try store.database.run(
                    """
                    UPDATE transactions SET category_id = ?, updated_at = datetime('now')
                    WHERE category_id = ? AND deleted_at IS NULL
                    """,
                    [.text(target), .text(id)]
                )
                try purge(store: store, id: id)

            case .detach:
                try store.database.run(
                    """
                    UPDATE transactions
                    SET category_id = NULL, needs_review = 1, updated_at = datetime('now')
                    WHERE category_id = ? AND deleted_at IS NULL
                    """,
                    [.text(id)]
                )
                try purge(store: store, id: id)

            case .archive:
                try store.database.run(
                    "UPDATE categories SET is_archived = 1 WHERE id = ?", [.text(id)]
                )
            }
        }
    }

    private static func purge(store: LocalStore, id: String) throws {
        try store.database.run("DELETE FROM monthly_budgets WHERE category_id = ?", [.text(id)])
        try store.database.run("DELETE FROM categories WHERE id = ?", [.text(id)])
    }
}
