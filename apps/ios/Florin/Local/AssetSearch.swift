import Foundation

/*
 * Trouver le symbole d'un titre sans le connaître.
 *
 * Le cours se demande par symbole — « CW8.PA », « VWCE.DE » — et personne ne
 * les retient. Pire : un même tracker cote sur plusieurs places, dans des
 * devises différentes, et choisir la mauvaise donne un cours plausible et
 * faux. Le fournisseur sait tout ça ; il suffit de lui demander.
 *
 * Même hôte que les cours, même absence de clé, même discrétion : ce qui part
 * est le texte tapé dans le champ, rien d'autre. Ni quantité, ni montant, ni
 * de quel compte il s'agit.
 */
enum AssetSearch {
    struct Match: Identifiable, Equatable {
        let symbol: String
        let name: String
        let exchange: String
        /// « ETF », « EQUITY », « MUTUALFUND »… tel que le fournisseur le nomme.
        let kind: String

        var id: String { symbol }
    }

    /// Rend `nil` sur un échec réseau — à distinguer d'une recherche qui n'a
    /// simplement rien trouvé, qui rend une liste vide.
    static func find(_ query: String) async -> [Match]? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2,
              let encoded = trimmed.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
              ),
              let url = URL(
                string: "https://query1.finance.yahoo.com/v1/finance/search"
                    + "?q=\(encoded)&quotesCount=15&newsCount=0"
              )
        else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        // Sans en-tête d'agent, l'hôte renvoie parfois une page au lieu du JSON.
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)",
            forHTTPHeaderField: "User-Agent"
        )

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let quotes = json["quotes"] as? [[String: Any]]
        else { return nil }

        return quotes.compactMap { quote in
            guard let symbol = quote["symbol"] as? String, !symbol.isEmpty else { return nil }
            let name = (quote["longname"] as? String)
                ?? (quote["shortname"] as? String)
                ?? symbol
            return Match(
                symbol: symbol,
                name: name,
                exchange: (quote["exchDisp"] as? String) ?? (quote["exchange"] as? String) ?? "",
                kind: (quote["typeDisp"] as? String) ?? (quote["quoteType"] as? String) ?? ""
            )
        }
    }
}
