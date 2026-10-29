import Foundation
import OSLog

/// Keeping a portfolio's value current without a server.
///
/// A broker account's worth is quantity × price, and the price is the half the
/// ledger cannot know. On the server a scheduler fetches it; on the device that
/// half simply stopped moving, so a PEA sat at whatever it was worth on the day
/// it was last imported — a figure that looks live and is not.
///
/// The quote comes from the same place the server asks: a public endpoint that
/// needs no key, so nothing has to be configured and nothing has to be stored.
/// Only the symbol is sent — never a balance, a holding size, or anything that
/// says whose portfolio it is.
enum LocalPricing {
    private static let log = Logger(subsystem: "com.adrbn.florin", category: "pricing")

    struct Result { let updated: Int; let failed: Int }

    @discardableResult
    static func refresh(store: LocalStore) async -> Result {
        let holdings = (try? store.database.query(
            """
            SELECT h.id, h.quote_symbol, h.account_id
            FROM holdings h
            JOIN accounts a ON a.id = h.account_id
            WHERE h.quote_symbol IS NOT NULL AND h.quote_symbol <> ''
              AND a.is_archived = 0
            """
        )) ?? []
        guard !holdings.isEmpty else { return Result(updated: 0, failed: 0) }

        var updated = 0, failed = 0
        var touched = Set<String>()
        for row in holdings {
            guard let id = row.string("id"), let symbol = row.string("quote_symbol"),
                  let account = row.string("account_id")
            else { continue }
            guard let series = await quote(symbol), let price = series.last?.close
            else { failed += 1; continue }
            // La série entière vient dans la même réponse ; la garder ne coûte
            // qu'une écriture, et c'est elle qui dessine la courbe du titre.
            for point in series {
                try? store.database.run(
                    """
                    INSERT INTO quote_history (symbol, day, close) VALUES (?, ?, ?)
                    ON CONFLICT(symbol, day) DO UPDATE SET close = excluded.close
                    """,
                    [.text(symbol), .text(point.day), .real(point.close)]
                )
            }
            try? store.database.run(
                """
                UPDATE holdings
                SET last_price = ?, last_price_at = datetime('now'), updated_at = datetime('now')
                WHERE id = ?
                """,
                [.real(price), .text(id)]
            )
            updated += 1
            touched.insert(account)
        }

        // The account's market value is the sum of its holdings, so it is
        // recomputed rather than nudged: a price that failed to fetch leaves a
        // stale line, not a wrong total.
        for account in touched {
            let value = (try? store.database.scalar(
                """
                SELECT coalesce(sum(quantity * coalesce(last_price, 0)), 0)
                FROM holdings WHERE account_id = ?
                """,
                [.text(account)]
            )?.double) ?? 0
            try? store.database.run(
                "UPDATE accounts SET market_value = ?, updated_at = datetime('now') WHERE id = ?",
                [.real(((value ?? 0) * 100).rounded() / 100), .text(account)]
            )
        }
        if updated > 0 {
            log.notice("priced \(updated, privacy: .public) holdings")
        }
        return Result(updated: updated, failed: failed)
    }

    struct Point { let day: String; let close: Double }

    /// Six mois de cours. Un échec reste silencieux par choix — un portefeuille
    /// au prix d'hier vaut bien mieux qu'un portefeuille qui affiche une erreur.
    ///
    /// `range=6mo` là où il y avait `range=1d` : le même appel, la même
    /// dépense, et la courbe en plus. Le dernier point sert de prix du jour,
    /// ce qui évite d'avoir deux chiffres qui peuvent se contredire.
    private static func quote(_ symbol: String) async -> [Point]? {
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(
                string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)"
                    + "?range=6mo&interval=1d"
              )
        else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = json["chart"] as? [String: Any],
              let results = chart["result"] as? [[String: Any]],
              let result = results.first,
              let stamps = result["timestamp"] as? [Double],
              let quotes = result["indicators"] as? [String: Any],
              let closes = (quotes["quote"] as? [[String: Any]])?.first?["close"] as? [Double?]
        else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")

        // Une bourse fermée rend un trou, pas un zéro : les sauter laisse la
        // courbe continue au lieu de la faire plonger un jour férié.
        var points: [Point] = []
        for (index, stamp) in stamps.enumerated() where index < closes.count {
            guard let close = closes[index], close.isFinite, close > 0 else { continue }
            points.append(
                Point(
                    day: formatter.string(from: Date(timeIntervalSince1970: stamp)),
                    close: close
                )
            )
        }
        return points.isEmpty ? nil : points
    }

    /// La courbe d'un titre, telle qu'elle a été gardée.
    static func history(store: LocalStore, symbol: String) -> [Point] {
        ((try? store.database.query(
            "SELECT day, close FROM quote_history WHERE symbol = ? ORDER BY day",
            [.text(symbol)]
        )) ?? []).compactMap {
            guard let day = $0.string("day"), let close = $0.double("close") else { return nil }
            return Point(day: day, close: close)
        }
    }
}
