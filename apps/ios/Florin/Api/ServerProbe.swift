import Foundation

/// What actually happened when we tried to reach a Florin server.
///
/// A bare "ça ne marche pas" is the worst possible answer here, because the
/// four ways this can fail need four different fixes: wrong address, server too
/// old, missing token, or a token the server rejects. Each case below maps to a
/// sentence that tells the user what to *do*.
enum ServerStatus: Equatable {
    case unknown
    case checking
    /// Nothing answered — wrong host, wrong port, or not on the right network.
    case unreachable(String)
    /// Something answered, but it is not a Florin.
    case notFlorin
    /// A Florin, but one without the v2 API this app speaks.
    case tooOld
    /// A Florin with the API, refusing us: no token, or the wrong one.
    case unauthorized
    case ready

    var isBlocking: Bool {
        switch self {
        case .ready, .unknown, .checking: return false
        default: return true
        }
    }
}

enum ServerProbe {
    /// Probes health first, then the v2 feed.
    ///
    /// Two calls rather than one because the difference between them is the
    /// whole diagnosis: `/api/health` answering while `/api/v2/overview` 404s
    /// means the box is up and simply predates this app — which is a deploy,
    /// not a typo.
    static func check(_ base: URL) async -> ServerStatus {
        var config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)

        func status(_ path: String) async -> Int? {
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
            components?.path = path
            guard let url = components?.url else { return nil }
            guard let (_, response) = try? await session.data(for: FlorinAuth.request(url)),
                  let http = response as? HTTPURLResponse
            else { return nil }
            return http.statusCode
        }

        guard let health = await status("/api/health") else {
            return .unreachable(base.host ?? "?")
        }
        guard health == 200 else { return .notFlorin }

        switch await status("/api/v2/overview") {
        case .none: return .unreachable(base.host ?? "?")
        case .some(200): return .ready
        case .some(401), .some(403): return .unauthorized
        case .some(404): return .tooOld
        case .some: return .notFlorin
        }
    }
}
