import Foundation

/*
 * Les tickets de caisse d'une opération, et ce qu'ils contiennent.
 *
 * Le découpage du texte est ailleurs, et pur (`ReceiptParser`). Ici il n'y a
 * que le rangement : la photo dans un fichier, le texte reconnu et ses lignes
 * dans la base, et la soustraction qui dit ce que les articles n'expliquent
 * pas encore du montant.
 */
enum LocalReceipts {
    struct Item: Identifiable, Equatable {
        let id: String
        let label: String
        let amount: Double
    }

    struct Receipt: Identifiable, Equatable {
        let id: String
        /// Relatif au dossier de la base — un chemin absolu change à chaque
        /// réinstallation, le conteneur de l'app n'étant pas stable.
        let imagePath: String?
        let scannedAt: String
        let items: [Item]

        var total: Double { items.reduce(0) { $0 + $1.amount } }
    }

    // MARK: - Lecture

    static func receipts(store: LocalStore, transactionId: String) throws -> [Receipt] {
        let heads = try store.database.query(
            """
            SELECT id, image_path, scanned_at FROM receipts
             WHERE transaction_id = ? ORDER BY scanned_at, id
            """,
            [.text(transactionId)]
        )
        let lines = try store.database.query(
            """
            SELECT id, receipt_id, label, amount FROM receipt_items
             WHERE transaction_id = ? ORDER BY receipt_id, line_no
            """,
            [.text(transactionId)]
        )
        return heads.compactMap { head in
            guard let id = head.string("id") else { return nil }
            return Receipt(
                id: id,
                imagePath: head.string("image_path"),
                scannedAt: head.string("scanned_at") ?? "",
                items: lines
                    .filter { $0.string("receipt_id") == id }
                    .compactMap { row in
                        guard let itemId = row.string("id"),
                              let label = row.string("label"),
                              let amount = row.double("amount")
                        else { return nil }
                        return Item(id: itemId, label: label, amount: amount)
                    }
            )
        }
    }

    static func count(store: LocalStore, transactionId: String) throws -> Int {
        try store.database.scalar(
            "SELECT count(*) FROM receipts WHERE transaction_id = ?",
            [.text(transactionId)]
        )?.int ?? 0
    }

    /// Ce que les articles lus n'expliquent pas encore.
    ///
    /// Le montant de l'opération est sûr — il vient de la banque, d'Apple Pay
    /// ou de la main de son propriétaire. La somme des articles, elle, vient
    /// d'une lecture de photo. L'écart ne met donc jamais le total en doute :
    /// il dit seulement ce qu'il reste à trouver, parce qu'une ligne a été mal
    /// lue ou qu'un deuxième ticket n'est pas encore scanné. Jamais un refus.
    static func unexplained(total: Double, items: [Item]) -> Double {
        abs(total) - items.reduce(0) { $0 + $1.amount }
    }

    // MARK: - Écriture

    @discardableResult
    static func save(
        store: LocalStore,
        transactionId: String,
        image: Data?,
        text: String,
        items: [ReceiptParser.Item]
    ) throws -> Receipt {
        let id = UUID().uuidString
        let path = try image.flatMap { data -> String? in
            let folder = store.url.deletingLastPathComponent()
                .appendingPathComponent("receipts", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = "receipts/\(id).jpg"
            try data.write(to: store.url.deletingLastPathComponent()
                .appendingPathComponent(name), options: .atomic)
            return name
        }
        let saved = try store.database.transaction { () -> Receipt in
            try store.database.run(
                """
                INSERT INTO receipts (id, transaction_id, image_path, raw_text)
                VALUES (?, ?, ?, ?)
                """,
                [
                    .text(id), .text(transactionId),
                    path.map { SQLiteValue.text($0) } ?? .null,
                    .text(text),
                ]
            )
            let stored = try insert(
                store: store, receiptId: id, transactionId: transactionId, items: items
            )
            return Receipt(id: id, imagePath: path, scannedAt: "", items: stored)
        }
        return saved
    }

    private static func insert(
        store: LocalStore, receiptId: String, transactionId: String, items: [ReceiptParser.Item]
    ) throws -> [Item] {
        var stored: [Item] = []
        for (index, item) in items.enumerated() {
            let itemId = UUID().uuidString
            try store.database.run(
                """
                INSERT INTO receipt_items
                    (id, receipt_id, transaction_id, label, amount, line_no)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(itemId), .text(receiptId), .text(transactionId),
                    .text(item.label), .real(item.amount), .integer(Int64(index)),
                ]
            )
            stored.append(Item(id: itemId, label: item.label, amount: item.amount))
        }
        return stored
    }

    /*
     * Les tickets découpés par une version qui comptait leurs totaux.
     *
     * Le texte reconnu est gardé, et les articles n'en sont qu'une lecture —
     * personne ne les corrige à la main. Une lecture peut donc se refaire, et
     * seulement là où elle allait mal : une somme d'articles *supérieure* au
     * débit ne s'explique que par une ligne comptée deux fois, puisque la
     * banque, elle, ne se trompe pas. Une lecture incomplète — somme sous le
     * débit — n'est pas touchée : elle n'a rien à gagner à être refaite.
     *
     * Et la nouvelle lecture ne remplace l'ancienne que si elle serre le
     * débit de plus près, ce qui évite de refaire le même travail à chaque
     * lancement quand le découpage n'a rien à offrir de mieux.
     */
    @discardableResult
    static func reparse(store: LocalStore) throws -> Int {
        let rows = try store.database.query(
            """
            SELECT r.id AS id, r.transaction_id AS tx, r.raw_text AS text, t.amount AS amount,
                   (SELECT coalesce(sum(i.amount), 0) FROM receipt_items i
                     WHERE i.receipt_id = r.id) AS total
            FROM receipts r JOIN transactions t ON t.id = r.transaction_id
            WHERE r.raw_text IS NOT NULL AND t.deleted_at IS NULL
            """
        )
        var repaired = 0
        for row in rows {
            guard let id = row.string("id"), let tx = row.string("tx"),
                  let text = row.string("text"), let amount = row.double("amount"),
                  let was = row.double("total"), was > abs(amount) + 0.005
            else { continue }
            let items = ReceiptParser.items(
                from: text.components(separatedBy: .newlines), total: amount
            )
            let now = items.reduce(0) { $0 + $1.amount }
            guard abs(abs(amount) - now) < abs(abs(amount) - was) else { continue }
            try store.database.transaction {
                try store.database.run(
                    "DELETE FROM receipt_items WHERE receipt_id = ?", [.text(id)]
                )
                _ = try insert(store: store, receiptId: id, transactionId: tx, items: items)
            }
            repaired += 1
        }
        return repaired
    }

    static func delete(store: LocalStore, receiptId: String) throws {
        let path = try store.database.scalar(
            "SELECT image_path FROM receipts WHERE id = ?",
            [.text(receiptId)]
        )?.string
        try store.database.transaction {
            try store.database.run("DELETE FROM receipt_items WHERE receipt_id = ?", [.text(receiptId)])
            try store.database.run("DELETE FROM receipts WHERE id = ?", [.text(receiptId)])
        }
        if let path {
            try? FileManager.default.removeItem(at: url(store: store, path: path))
        }
    }

    static func url(store: LocalStore, path: String) -> URL {
        store.url.deletingLastPathComponent().appendingPathComponent(path)
    }
}
