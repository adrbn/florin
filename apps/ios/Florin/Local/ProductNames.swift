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
        /// Le mot du modèle, au plus près : « poulet », « provolone ».
        let category: String?
        /// L'une des dix familles, celle qui se compte. Voir `families`.
        var family: String?
    }

    /*
     * Dix familles, et pas une de plus.
     *
     * Une catégorie libre ne s'additionne pas : « poulet », « volaille » et
     * « blanc de poulet » sont trois barres d'un article là où il n'y a
     * qu'une viande. La liste est donc fermée, courte, et tient dans une
     * phrase — c'est elle qu'on demande au modèle EN PLUS de son mot à lui,
     * jamais à la place. « autre » existe pour que rien ne soit perdu quand
     * rien ne colle, et un panier où « autre » domine dit que la liste est à
     * revoir, ce qu'un classement forcé aurait caché.
     */
    static let families = [
        "viande", "poisson", "fruits & légumes", "crémerie", "épicerie",
        "boisson", "hygiène", "entretien", "maison", "autre",
    ]

    /// La famille d'un mot, telle qu'elle est écrite — une casse ou un accent
    /// de travers ne doit pas créer une onzième famille.
    static func family(of raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let folded = key(raw)
        return families.first { key($0) == folded }
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
            "SELECT match_key, name, category, family FROM product_names WHERE match_key IN (\(marks))",
            keys.map { SQLiteValue.text($0) }
        )
        return rows.reduce(into: [:]) { out, row in
            guard let key = row.string("match_key"), let name = row.string("name") else { return }
            out[key] = Reading(
                name: name, category: row.string("category"), family: row.string("family")
            )
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
            INSERT INTO product_names (match_key, name, category, family, source)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(match_key) DO UPDATE SET
                name = excluded.name, category = excluded.category,
                /*
                 * Une correction à la main ne connaît pas les familles.
                 *
                 * Elle rend un nom, et seulement lui : écraser la famille
                 * avec son vide ferait retomber dans « à ranger » un article
                 * déjà classé, à chaque fois qu'on corrige une faute de
                 * frappe. Le vide ne remplace donc rien.
                 */
                family = coalesce(excluded.family, product_names.family),
                source = excluded.source
            """,
            [
                .text(folded), .text(reading.name),
                reading.category.map { SQLiteValue.text($0) } ?? .null,
                family(of: reading.family).map { SQLiteValue.text($0) } ?? .null,
                .text(source),
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

    // MARK: - Le modèle

    /*
     * Le nom du modèle n'est pas une constante, c'est une réponse du service.
     *
     * Google retire et renomme ses modèles sans prévenir, et un nom écrit en
     * dur finit par rendre 404 — un défaut que personne ne peut diagnostiquer
     * depuis un téléphone, et qui ressemble à une clé cassée alors que la clé
     * est bonne. La liste, elle, dit la vérité du jour : on la demande, on
     * garde le nom qui marche, et on ne la redemande qu'au prochain 404.
     */
    static let modelSetting = "gemini_model"
    static let defaultModel = "gemini-2.5-flash"

    static func model(store: LocalStore) -> String {
        let value = try? store.database.scalar(
            "SELECT value FROM settings WHERE key = ?", [.text(modelSetting)]
        )?.string
        guard let value, !value.isEmpty else { return defaultModel }
        return value
    }

    static func setModel(store: LocalStore, _ value: String) throws {
        try store.database.run(
            """
            INSERT INTO settings (key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """,
            [.text(modelSetting), .text(value)]
        )
    }

    /// Ce que la clé peut vraiment appeler aujourd'hui. Sert aussi de contrôle
    /// de la clé : le service refuse la liste avant de refuser une génération,
    /// et pour rien — vérifier ne consomme pas de quota.
    static func availableModel(apiKey: String) async throws -> String {
        guard let first = try await availableModels(apiKey: apiKey).first else {
            throw Failure.noModel
        }
        return first
    }

    /*
     * Tous les candidats, du meilleur au moins bon — pas seulement le premier.
     *
     * Figurer dans la liste avec `generateContent` ne garantit pas de
     * répondre à l'appel : un modèle d'aperçu disparaît entre deux écrans, un
     * autre n'accepte pas un schéma de sortie. Le premier nom rendait alors
     * 404 à son tour, et c'est ce second 404 — celui du repli — qui
     * s'affichait, en disant « aucun modèle disponible pour cette clé » alors
     * qu'il en restait dix à essayer.
     *
     * La liste est AUSSI paginée : cinquante noms par page, et Google en
     * publie davantage. Sans suivre `nextPageToken`, le classement se faisait
     * sur une tranche arbitraire du catalogue.
     */
    static func availableModels(apiKey: String) async throws -> [String] {
        var usable: [String] = []
        var token: String?
        // Borne haute : la pagination vient du service, pas de nous.
        for _ in 0..<4 {
            var components = URLComponents(
                string: "https://generativelanguage.googleapis.com/v1beta/models"
            )!
            components.queryItems = [URLQueryItem(name: "pageSize", value: "100")]
                + (token.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
            var request = URLRequest(url: components.url!)
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
                request.timeoutInterval = 12

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw Failure.http(http.statusCode)
            }
            guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = envelope["models"] as? [[String: Any]]
            else { throw Failure.unreadable }

            usable += models.compactMap { model -> String? in
                guard let name = model["name"] as? String,
                      let methods = model["supportedGenerationMethods"] as? [String],
                      methods.contains("generateContent")
                else { return nil }
                return name.replacingOccurrences(of: "models/", with: "")
            }
            token = envelope["nextPageToken"] as? String
            if token == nil { break }
        }
        /*
         * Un « flash » d'abord : c'est celui qui porte le quota gratuit, et
         * lire vingt libellés ne demande pas le grand modèle. Sans « lite »,
         * qui rend des noms de produits trop approximatifs pour servir.
         *
         * Écartés d'office, ceux qui annoncent `generateContent` sans savoir
         * rendre du texte : la parole, l'image, la vidéo, l'intégration.
         */
        let refused = ["tts", "image", "audio", "video", "embedding", "live", "vision"]
        let text = usable.filter { name in !refused.contains(where: name.contains) }
        func rank(_ name: String) -> Int {
            if name.contains("flash"), !name.contains("lite") { return 0 }
            if name.contains("flash") { return 1 }
            return 2
        }
        // Les aperçus en dernier de leur rang : ils s'évaporent sans préavis.
        let ranked = text.enumerated().sorted { a, b in
            let ka = (rank(a.element), a.element.contains("preview") ? 1 : 0, a.offset)
            let kb = (rank(b.element), b.element.contains("preview") ? 1 : 0, b.offset)
            return ka < kb
        }.map(\.element)
        guard !ranked.isEmpty else { throw Failure.noModel }
        return ranked
    }

    // MARK: - Demander

    /// Le motif d'un échec, en deux mots — un message d'erreur entier par
    /// candidat ferait un pavé illisible sur un téléphone.
    private static func reason(_ error: Error) -> String {
        if case let Failure.http(code) = error { return "\(code)" }
        if let url = error as? URLError {
            return url.code == .timedOut ? "délai dépassé" : "réseau"
        }
        return "illisible"
    }

    enum Failure: LocalizedError {
        case noKey
        case http(Int)
        case unreadable
        case noModel
        /// Les modèles essayés, dans l'ordre : sans leurs noms, un échec de
        /// bout en bout ne se diagnostique pas depuis un téléphone.
        case noneAnswered([String])

        var errorDescription: String? {
            switch self {
            case .noKey: "Pose une clé d'API dans Réglages → Tickets de caisse."
            case let .http(code):
                switch code {
                case 400, 401, 403: "Clé refusée par le service."
                case 404: "Aucun modèle disponible pour cette clé."
                case 429: "Quota épuisé pour aujourd'hui."
                default: "Le service a répondu \(code)."
                }
            case .unreadable: "Réponse illisible."
            case .noModel: "Cette clé ne donne accès à aucun modèle."
            case let .noneAnswered(tried):
                "Aucun modèle n'a répondu : \(tried.joined(separator: ", "))."
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

        var readings: [String: Reading]
        do {
            readings = try await read(
                labels: asked, merchant: merchant, apiKey: apiKey, model: model(store: store)
            )
        } catch let first as Failure {
            /*
             * Un service surchargé n'est pas un modèle disparu.
             *
             * Seul le 404 déclenchait le repli, et Google rend des 503 par
             * rafales aux heures pleines : l'écran disait « le service a
             * répondu 503 » et s'arrêtait là, alors qu'un deuxième essai deux
             * secondes plus tard passe. Le 429 et les 5xx reprennent donc le
             * même chemin, en commençant par le modèle en place — c'est lui
             * qu'on veut garder quand ce n'est que de l'encombrement, et le
             * remplacer n'aurait rien arrangé.
             */
            guard case let .http(code) = first,
                  code == 404 || code == 429 || code >= 500
            else { throw first }
            if code != 404 { try? await Task.sleep(for: .seconds(2)) }
            /*
             * Le nom retenu n'existe plus. On redemande la liste, et on
             * descend les candidats jusqu'à ce que l'un réponde — un seul
             * essai ne suffisait pas, le repli pouvait rendre 404 lui aussi
             * et c'est ce second échec qui s'affichait. Le nom qui a marché
             * est gardé : le prochain ticket part directement au bon endroit.
             */
            // Une liste qu'on n'obtient pas ne doit pas effacer le seul nom
            // qu'on avait : sous 503, elle échoue comme le reste.
            let fresh = (try? await availableModels(apiKey: apiKey)) ?? []
            let current = model(store: store)
            /*
             * Le modèle qui vient d'échouer ne se réessaye que s'il peut
             * réussir : un 5xx est un encombrement passager, et c'est lui
             * qu'on veut reprendre. Un 404 dit qu'il n'existe plus et un 429
             * que SON quota est épuisé — dans les deux cas le redemander ne
             * fait que brûler un des quatre essais, ce qu'il faisait : la
             * liste le reproposait en deuxième position et il rendait le
             * même 404.
             */
            let others = fresh.filter { $0 != current }
            let candidates = code >= 500 ? [current] + others : others
            guard !candidates.isEmpty else { throw first }
            var found: [String: Reading]?
            /*
             * Chaque candidat avec SA raison d'avoir échoué.
             *
             * Le filtre ne retenait que les 404 : un délai dépassé sur le
             * premier nom — le réseau d'un téléphone en ville — arrêtait net
             * une boucle qui en avait quatre autres à essayer, et l'écran
             * disait « la requête a expiré » sans dire laquelle. Tout échec
             * fait maintenant passer au suivant, et ce qui s'affiche quand
             * aucun n'a répondu nomme chacun avec son motif.
             */
            var tried: [String] = []
            for candidate in candidates.prefix(4) {
                do {
                    found = try await read(
                        labels: asked, merchant: merchant, apiKey: apiKey, model: candidate
                    )
                    try? setModel(store: store, candidate)
                    break
                } catch {
                    tried.append("\(candidate) (\(reason(error)))")
                }
            }
            guard let found else { throw Failure.noneAnswered(tried) }
            readings = found
        }
        var learnt = 0
        for (label, reading) in readings {
            try remember(store: store, label: label, reading)
            learnt += 1
        }
        return learnt
    }

    // MARK: - Ranger ce qui a été appris avant les familles

    /// Les mots de catégorie encore sans famille, chacun une fois.
    static func unsorted(store: LocalStore) -> [String] {
        let rows = (try? store.database.query(
            """
            SELECT DISTINCT category FROM product_names
            WHERE family IS NULL AND category IS NOT NULL AND category <> ''
            ORDER BY category
            """
        )) ?? []
        return rows.compactMap { $0.string("category") }
    }

    /*
     * Ranger tout l'historique en UN appel, et sur des mots seuls.
     *
     * Relire les tickets pour retrouver les familles serait payer deux fois
     * la même lecture, et faire repartir des libellés de caisse. Or la
     * question ne porte pas sur les tickets : « poulet appartient-il à la
     * viande » se répond sans savoir qui l'a acheté, ni quand, ni pour
     * combien. Ce qui part est donc une liste de mots de dictionnaire —
     * quelques dizaines, une seule fois, sans montant, sans date, sans
     * marchand — et ce qui revient range tous les articles qui portaient ce
     * mot. Deux cents produits se classent pour le prix d'une phrase.
     */
    @discardableResult
    static func sortIntoFamilies(store: LocalStore) async throws -> Int {
        guard let apiKey = apiKey(store: store) else { throw Failure.noKey }
        let words = unsorted(store: store)
        guard !words.isEmpty else { return 0 }

        let instruction = """
            Range chacun de ces mots de catégorie de produit dans EXACTEMENT \
            l'une de ces familles, et rien d'autre : \
            \(families.joined(separator: ", ")).
            Quand rien ne colle, mets « autre ». Ne commente pas, \
            n'ajoute ni ne retire de mot.

            Mots :
            \(words.map { "- \($0)" }.joined(separator: "\n"))
            """
        let schema: [String: Any] = [
            "type": "ARRAY",
            "items": [
                "type": "OBJECT",
                "properties": [
                    "category": ["type": "STRING"],
                    "family": ["type": "STRING", "enum": families],
                ],
                "required": ["category", "family"],
            ],
        ]
        let rows = try await structured(
            instruction: instruction, schema: schema, apiKey: apiKey,
            model: model(store: store)
        )
        var sorted = 0
        for row in rows {
            guard let word = row["category"] as? String,
                  let named = family(of: row["family"] as? String)
            else { continue }
            try store.database.run(
                "UPDATE product_names SET family = ? WHERE category = ? AND family IS NULL",
                [.text(named), .text(word)]
            )
            sorted += 1
        }
        return sorted
    }

    /// Ce que veut dire une poignée de libellés de caisse — la question, sa
    /// forme de réponse, et rien du fournisseur, qui est dans `structured`.
    static func read(
        labels: [String], merchant: String, apiKey: String, model: String
    ) async throws -> [String: Reading] {
        let instruction = """
            Voici les lignes d'un ticket de caisse\
            \(merchant.isEmpty ? "" : " du commerçant « \(merchant) »").
            La caisse abrège les noms d'articles, parfois en italien, en français \
            ou en anglais. Pour chaque libellé, donne trois choses :
            - « name » : le nom du produit en clair en français, court, tel \
            qu'on le dirait (« provolone Valpadana DOP », « nettoyant ménager ») ;
            - « category » : une catégorie courte et PRÉCISE en français \
            (« fromage », « poulet », « lessive », « pain ») ;
            - « family » : EXACTEMENT l'une de ces familles, rien d'autre — \
            \(families.joined(separator: ", ")).
            Si un libellé ne t'évoque rien, répète-le tel quel, laisse la \
            catégorie vide et mets « autre » en famille.
            Ne commente pas, ne complète pas la liste.

            Libellés :
            \(labels.map { "- \($0)" }.joined(separator: "\n"))
            """
        let schema: [String: Any] = [
            "type": "ARRAY",
            "items": [
                "type": "OBJECT",
                "properties": [
                    "label": ["type": "STRING"],
                    "name": ["type": "STRING"],
                    "category": ["type": "STRING"],
                    "family": ["type": "STRING", "enum": families],
                ],
                "required": ["label", "name", "family"],
            ],
        ]
        let rows = try await structured(
            instruction: instruction, schema: schema, apiKey: apiKey, model: model
        )
        var out: [String: Reading] = [:]
        for row in rows {
            guard let label = row["label"] as? String,
                  let name = (row["name"] as? String)?.trimmingCharacters(in: .whitespaces),
                  !name.isEmpty
            else { continue }
            let category = (row["category"] as? String)?.trimmingCharacters(in: .whitespaces)
            out[label] = Reading(
                name: name, category: (category?.isEmpty ?? true) ? nil : category,
                family: family(of: row["family"] as? String)
            )
        }
        return out
    }

    /*
     * Une question, un schéma, une liste d'objets — et rien du fournisseur
     * au-dehors.
     *
     * Deux questions la posent : ce que veut dire un libellé de caisse, et
     * dans quelle famille range un mot de catégorie. Elles ne partagent ni
     * leur texte ni leur forme de réponse, mais tout le reste : l'adresse, la
     * clé en en-tête, la température à zéro, la sortie contrainte, le délai.
     * Changer de fournisseur ne touche donc toujours qu'un seul endroit.
     *
     * Sans réflexion préalable : nommer un yaourt n'est pas un problème. Les
     * modèles « flash » récents réfléchissent par défaut, et avec une sortie
     * contrainte cela dépassait les vingt-cinq secondes sur le réseau d'un
     * téléphone. Un modèle qui refuse l'option rend 400, et la même question
     * repart aussitôt sans elle, une fois — ici et pas chez l'appelant, sinon
     * un 400 remonterait en « clé refusée », ce qu'il n'est pas.
     */
    static func structured(
        instruction: String, schema: [String: Any], apiKey: String, model: String
    ) async throws -> [[String: Any]] {
        do {
            return try await post(
                instruction: instruction, schema: schema, apiKey: apiKey,
                model: model, thinking: false
            )
        } catch Failure.http(400) {
            return try await post(
                instruction: instruction, schema: schema, apiKey: apiKey,
                model: model, thinking: true
            )
        }
    }

    private static func post(
        instruction: String, schema: [String: Any], apiKey: String,
        model: String, thinking: Bool
    ) async throws -> [[String: Any]] {
        // Température à zéro : la même caisse doit donner la même réponse d'un
        // ticket à l'autre, sinon le cache garde une loterie.
        var config: [String: Any] = [
            "temperature": 0,
            "responseMimeType": "application/json",
            "responseSchema": schema,
        ]
        if !thinking { config["thinkingConfig"] = ["thinkingBudget": 0] }
        let body: [String: Any] = [
            "contents": [["parts": [["text": instruction]]]],
            "generationConfig": config,
        ]

        var request = URLRequest(
            url: URL(
                string: "https://generativelanguage.googleapis.com/v1beta/models"
                    + "/\(model):generateContent"
            )!
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // En en-tête plutôt que dans l'URL : une clé dans une adresse se
        // retrouve dans les journaux de tout ce qui la relaie.
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 25

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
        return rows
    }
}
