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
            guard let price = await quote(symbol) else { failed += 1; continue }
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

    /// One quote. A failure is silent by design — a portfolio showing
    /// yesterday's price is a great deal better than one showing an error.
    private static func quote(_ symbol: String) async -> Double? {
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(
                string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)"
                    + "?range=1d&interval=1d"
              )
        else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = json["chart"] as? [String: Any],
              let results = chart["result"] as? [[String: Any]],
              let meta = results.first?["meta"] as? [String: Any],
              let price = meta["regularMarketPrice"] as? Double,
              price.isFinite, price > 0
        else { return nil }
        return price
    }
}
