import Foundation

/// Enable Banking, called straight from the phone.
///
/// A port of `packages/core/src/banking/enable-banking.ts`. Every request
/// carries a short-lived JWT signed RS256 with the app's RSA key — the key
/// itself never leaves the Keychain, only signatures do.
///
/// No JWT library. `SecKeyCreateSignature` produces RS256 directly, and a
/// credential that reads someone's bank is not a good place to add a
/// dependency whose source nobody in this project has read.
enum EnableBanking {
    static let apiBase = URL(string: "https://api.enablebanking.com")!

    /// Enable Banking accepts up to an hour; fifty minutes means a cached
    /// token never expires mid-request.
    private static let jwtLifetime: TimeInterval = 50 * 60

    private struct CachedJWT {
        let token: String
        let expiresAt: Date
    }

    nonisolated(unsafe) private static var cache: CachedJWT?
    private static let cacheLock = NSLock()

    struct Config {
        /// The application id registered with Enable Banking — the JWT's `kid`.
        let appId: String
        let redirectURL: String
    }

    enum Failure: LocalizedError {
        case notConfigured
        case http(Int, String)
        case malformed
        /// Something this app refused to do, in its own words.
        case rejected(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                Strings.device(
                    "v2.connect.notConfigured",
                    "La synchronisation bancaire n'est pas encore configurée."
                ) + " " + Strings.device(
                    "v2.connect.notConfiguredHint",
                    "Ouvre les Réglages pour renseigner ton App ID Enable Banking."
                )
            case let .http(code, body):
                body.isEmpty
                    ? Strings.device(
                        "v2.connect.providerStatus",
                        "Enable Banking a répondu {code}.",
                        ["code": code]
                    )
                    : "Enable Banking: \(body)"
            case .malformed:
                Strings.device(
                    "v2.connect.providerUnreadable",
                    "Enable Banking a envoyé quelque chose que l'app n'a pas su lire."
                )
            case let .rejected(message):
                message
            }
        }
    }

    // MARK: - The token

    static func jwt(_ config: Config) throws -> String {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        // Refreshed five minutes early, to absorb clock skew between a phone
        // and Enable Banking's clock.
        if let cache, cache.expiresAt.addingTimeInterval(-300) > Date() {
            return cache.token
        }

        let now = Date()
        let header = ["typ": "JWT", "alg": "RS256", "kid": config.appId]
        let payload: [String: Any] = [
            "iss": "enablebanking.com",
            "aud": "api.enablebanking.com",
            "iat": Int(now.timeIntervalSince1970),
            "exp": Int(now.addingTimeInterval(jwtLifetime).timeIntervalSince1970),
        ]

        let headerPart = base64URL(try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys]))
        let payloadPart = base64URL(try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]))
        let signingInput = "\(headerPart).\(payloadPart)"
        let signature = try BankingKey.sign(Data(signingInput.utf8))
        let token = "\(signingInput).\(base64URL(signature))"

        cache = CachedJWT(token: token, expiresAt: now.addingTimeInterval(jwtLifetime))
        return token
    }

    /// Forget the cached token — after the key is regenerated, when every
    /// signature made with the old one is worthless.
    static func forgetToken() {
        cacheLock.lock()
        cache = nil
        cacheLock.unlock()
    }

    // MARK: - Requests

    static func request<T: Decodable>(
        _ config: Config,
        _ path: String,
        method: String = "GET",
        query: [String: String] = [:],
        body: [String: Any]? = nil
    ) async throws -> T {
        var components = URLComponents(
            url: apiBase.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw Failure.malformed }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try jwt(config))", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.malformed }
        guard (200..<300).contains(http.statusCode) else {
            // Enable Banking puts the useful part in the body, not the status —
            // "consent expired" and "unknown ASPSP" are both 400.
            throw Failure.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        if T.self == Empty.self, let empty = Empty() as? T { return empty }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as DecodingError {
            /*
             * Say which field, not "the format is not correct".
             *
             * That is DecodingError's localizedDescription, and it is useless:
             * it names neither the field nor what was expected, on a response
             * with dozens of them that differ from bank to bank. The path and
             * the mismatch are right there in the error — printing them turns
             * an afternoon of guessing into one line.
             */
            throw Failure.rejected("\(path) — \(Self.describe(error))")
        }
    }

    struct Empty: Decodable {}

    static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            let parts = context.codingPath.map(\.stringValue)
            return parts.isEmpty
                ? Strings.device("v2.connect.decodeRoot", "racine")
                : parts.joined(separator: ".")
        }
        switch error {
        case let .keyNotFound(key, context):
            return Strings.device(
                "v2.connect.decodeMissingField",
                "champ manquant « {field} » dans {path}",
                ["field": key.stringValue, "path": path(context)]
            )
        case let .typeMismatch(type, context):
            return Strings.device(
                "v2.connect.decodeWrongType",
                "type inattendu à {path} : {type} attendu",
                ["path": path(context), "type": String(describing: type)]
            )
        case let .valueNotFound(type, context):
            return Strings.device(
                "v2.connect.decodeNullValue",
                "valeur nulle à {path} alors que {type} est requis",
                ["path": path(context), "type": String(describing: type)]
            )
        case let .dataCorrupted(context):
            return Strings.device(
                "v2.connect.decodeUnreadable",
                "données illisibles à {path}",
                ["path": path(context)]
            )
        @unknown default:
            return error.localizedDescription
        }
    }

    // MARK: - The calls this app makes

    static func aspsps(_ config: Config, country: String) async throws -> AspspList {
        try await request(config, "/aspsps", query: ["country": country])
    }

    /// Start a consent flow; the response carries the bank's own sign-in URL.
    static func startAuth(
        _ config: Config,
        aspsp: Aspsp,
        state: String,
        validUntil: Date
    ) async throws -> StartAuthResponse {
        try await request(
            config,
            "/auth",
            method: "POST",
            body: [
                "access": ["valid_until": ISO8601DateFormatter().string(from: validUntil)],
                "aspsp": ["name": aspsp.name, "country": aspsp.country],
                "state": state,
                "redirect_url": config.redirectURL,
                "psu_type": "personal",
            ]
        )
    }

    static func createSession(_ config: Config, code: String) async throws -> SessionResponse {
        try await request(config, "/sessions", method: "POST", body: ["code": code])
    }

    static func session(_ config: Config, id: String) async throws -> SessionResponse {
        try await request(config, "/sessions/\(id)")
    }

    static func accountDetails(_ config: Config, uid: String) async throws -> AccountDetails {
        try await request(config, "/accounts/\(uid)/details")
    }

    static func balances(_ config: Config, uid: String) async throws -> BalancesResponse {
        try await request(config, "/accounts/\(uid)/balances")
    }

    static func transactions(
        _ config: Config,
        uid: String,
        from: String,
        to: String,
        continuationKey: String? = nil
    ) async throws -> TransactionsResponse {
        var query = ["date_from": from, "date_to": to]
        if let continuationKey { query["continuation_key"] = continuationKey }
        return try await request(config, "/accounts/\(uid)/transactions", query: query)
    }

    // MARK: - Bits

    /// Base64url: the JWT alphabet, no padding.
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
