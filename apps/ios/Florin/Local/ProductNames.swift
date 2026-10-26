import Foundation

/*
 * Ce que la caisse a voulu dire.
 *
 * Une caisse imprime sur vingt-quatre caractères, et abrège comme elle peut :
 * « AUR PROV VALP DOP » est un provolone Valpadana, « AUR NETT MULTIUSO » un
 * nettoyant ménager. Découper la ligne et en lire le prix ne demande rien
 * d'intelligent — c'est `ReceiptParser`, et il le fait sur l'appareil. Savoir
 * ce qui a été acheté demande une connaissance du monde que ni l'app ni le
 * téléphone n'ont.
 *
 * D'où un modèle, et trois précautions :
 *
 *  - Rien ne part sans clé. Tant que les réglages n'en portent pas une, cette
 *    classe ne fait aucun appel réseau et le ticket reste ce qu'il est.
 *  - Seuls les libellés et le nom du commerçant partent — jamais la photo,
 *    jamais les montants, jamais le reste du grand livre. Ce qui sort est ce
 *    qu'on lirait sur l'étiquette d'un rayon, et de quel magasin il s'agit :
 *    « PROV » ne dit pas la même chose chez un fromager et chez un droguiste.
 *  - Une lecture se garde. Un même libellé ne se demande qu'une fois : au
 *    bout de quelques semaines le panier habituel est connu hors ligne, et le
 *    modèle ne sert plus qu'aux nouveautés.
 *
 * Le modèle est Gemini Flash : il faut du multilingue (la caisse romaine
 * abrège en italien), une sortie structurée, et un quota gratuit très au-delà
 * de deux tickets par jour. Changer de fournisseur ne touche que `read`.
 */
enum ProductNames {
    /// Ce qu'on a compris d'un libellé.
    struct Reading: Equatable {
        let name: String
        let category: String?
    }

    /// La clé de rangement d'un libellé : sa forme repliée, pour que deux
    /// impressions du même article ne se demandent pas deux fois.
    static func key(_ label: String) -> String {
        label
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    // MARK: - Ce qui est déjà connu

    static func known(store: LocalStore, labels: [String]) throws -> [String: Reading] {
        let keys = Set(labels.map(key)).filter { !$0.isEmpty }
        guard !keys.isEmpty else { return [:] }
        let marks = keys.map { _ in "?" }.joined(separator: ", ")
        let rows = try store.database.query(
            "SELECT match_key, name, category FROM product_names WHERE match_key IN (\(marks))",
            keys.map { SQLiteValue.text($0) }
        )
        return rows.reduce(into: [:]) { out, row in
            guard let key = row.string("match_key"), let name = row.string("name") else { return }
            out[key] = Reading(name: name, category: row.string("category"))
        }
    }

    /// La lecture d'un libellé, si on l'a déjà faite.
    static func reading(store: LocalStore, label: String) -> Reading? {
        try? known(store: store, labels: [label])[key(label)]
    }

    static func remember(
        store: LocalStore, label: String, _ reading: Reading, source: String = "gemini"
    ) throws {
        let folded = key(label)
        guard !folded.isEmpty, !reading.name.isEmpty else { return }
        try store.database.run(
            """
            INSERT INTO product_names (match_key, name, category, source)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(match_key) DO UPDATE SET
                name = excluded.name, category = excluded.category, source = excluded.source
            """,
            [
                .text(folded), .text(reading.name),
                reading.category.map { SQLiteValue.text($0) } ?? .null, .text(source),
            ]
        )
    }

    // MARK: - La clé

    static let settingKey = "gemini_api_key"

    static func apiKey(store: LocalStore) -> String? {
        let value = try? store.database.scalar(
            "SELECT value FROM settings WHERE key = ?", [.text(settingKey)]
        )?.string
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return value.trimmingCharacters(in: .whitespaces)
    }

    static func setAPIKey(store: LocalStore, _ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try store.database.run("DELETE FROM settings WHERE key = ?", [.text(settingKey)])
            return
        }
        try store.database.run(
            """
            INSERT INTO settings (key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """,
            [.text(settingKey), .text(trimmed)]
        )
    }

    // MARK: - Demander

    enum Failure: LocalizedError {
        case noKey
        case http(Int)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .noKey: "Pose une clé d'API dans Réglages → Tickets de caisse."
            case let .http(code): "Le service a répondu \(code)."
            case .unreadable: "Réponse illisible."
            }
        }
    }

    /// Les libellés d'un ticket qu'on ne sait pas encore lire, lus et gardés.
    ///
    /// Rend le nombre de nouveautés apprises. Ne lève que sur un échec franc —
    /// un libellé que le modèle laisse de côté reste simplement inconnu.
    @discardableResult
    static func resolve(store: LocalStore, labels: [String], merchant: String) async throws -> Int {
        guard let apiKey = apiKey(store: store) else { throw Failure.noKey }
        let seen = try known(store: store, labels: labels)
        let missing = labels.filter { !$0.isEmpty && seen[key($0)] == nil }
        // Deux impressions du même article dans un ticket ne font qu'une question.
        var asked: [String] = []
        for label in missing where !asked.contains(where: { key($0) == key(label) }) {
            asked.append(label)
        }
        guard !asked.isEmpty else { return 0 }

        let readings = try await read(labels: asked, merchant: merchant, apiKey: apiKey)
        var learnt = 0
        for (label, reading) in readings {
            try remember(store: store, label: label, reading)
            learnt += 1
        }
        return learnt
    }

    /*
     * L'appel, et le seul endroit qui connaît le fournisseur.
     *
     * Température à zéro : la même caisse doit donner la même réponse d'un
     * ticket à l'autre, sinon le cache garde une loterie. La sortie est
     * contrainte par un schéma, donc la réponse se décode sans rattrapage.
     */
    static func read(
        labels: [String], merchant: String, apiKey: String
    ) async throws -> [String: Reading] {
        let instruction = """
            Voici les lignes d'un ticket de caisse\
            \(merchant.isEmpty ? "" : " du commerçant « \(merchant) »").
            La caisse abrège les noms d'articles, parfois en italien, en français \
            ou en anglais. Pour chaque libellé, donne le nom du produit en clair \
            en français, court, tel qu'on le dirait (« provolone Valpadana DOP », \
            « nettoyant ménager »), et une catégorie courte en français \
            (« fromage », « boisson », « entretien », « viande », « pain »).
            Si un libellé ne t'évoque rien, répète-le tel quel et laisse la \
            catégorie vide. Ne commente pas, ne complète pas la liste.

            Libellés :
            \(labels.map { "- \($0)" }.joined(separator: "\n"))
            """

        let body: [String: Any] = [
            "contents": [["parts": [["text": instruction]]]],
            "generationConfig": [
                "temperature": 0,
                "responseMimeType": "application/json",
                "responseSchema": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            "label": ["type": "STRING"],
                            "name": ["type": "STRING"],
                            "category": ["type": "STRING"],
                        ],
                        "required": ["label", "name"],
                    ],
                ],
            ],
        ]

        var request = URLRequest(
            url: URL(
                string: "https://generativelanguage.googleapis.com/v1beta/models"
                    + "/gemini-2.5-flash:generateContent"
            )!
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // En en-tête plutôt que dans l'URL : une clé dans une adresse se
        // retrouve dans les journaux de tout ce qui la relaie.
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.http(http.statusCode)
        }
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = envelope["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.compactMap({ $0["text"] as? String }).first,
              let rows = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]]
        else { throw Failure.unreadable }

        var out: [String: Reading] = [:]
        for row in rows {
            guard let label = row["label"] as? String,
                  let name = (row["name"] as? String)?.trimmingCharacters(in: .whitespaces),
                  !name.isEmpty
            else { continue }
            let category = (row["category"] as? String)?.trimmingCharacters(in: .whitespaces)
            out[label] = Reading(
                name: name, category: (category?.isEmpty ?? true) ? nil : category
            )
        }
        return out
    }
}
