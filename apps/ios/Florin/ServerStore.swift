import Foundation
import SwiftUI

/// Where this phone should find Florin.
///
/// The address is the app's only real configuration: a self-hosted instance on
/// the user's LAN or VPN, or the desktop app's local server. Stored in
/// `UserDefaults` rather than compiled in, so moving the server does not mean
/// rebuilding the app.
@MainActor
final class ServerStore: ObservableObject {
    private static let key = "florin.serverURL"

    /// Bumping this remounts the web view — used after a settings change so the
    /// new host loads without the user having to kill the app.
    @Published private(set) var reloadToken = UUID()

    @Published var rawURL: String {
        didSet { UserDefaults.standard.set(rawURL, forKey: Self.key) }
    }

    /// Bearer token for a web deployment. Empty for the desktop server, which
    /// has no authentication. Stored in the Keychain — see `FlorinAuth`.
    @Published var apiToken: String {
        didSet { FlorinAuth.token = apiToken.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    init() {
        rawURL = UserDefaults.standard.string(forKey: Self.key) ?? ""
        apiToken = FlorinAuth.token ?? ""
    }

    /// The v2 mobile surface lives under `/m`; everything else is the desktop
    /// layout and would be miserable on a phone.
    static let mobilePath = "/m"

    /// Prefilled into the setup field on first run — nothing is contacted until
    /// the user confirms. It points at the machine this build came from, which
    /// is the one address that is certainly reachable right now; anyone else
    /// just types their own.
    /*
     * Empty on purpose.
     *
     * This used to be a hardcoded 192.168.1.135:3999 — one developer's machine,
     * years ago. It looked like an answer, so the field arrived pre-filled with
     * something that was wrong for everyone, and "does not respond" was the
     * first thing a new install ever said. A placeholder that shows the *shape*
     * of an address teaches more than a fake one.
     */
    static let suggestedHost = ""

    /// The two apps expose the locale cookie at different paths — desktop keeps
    /// its user settings under /api/settings, the web build does not. The client
    /// tries both rather than making the user tell it which build it is talking
    /// to.
    static let localeEndpoints = ["/api/settings/locale", "/api/locale"]

    /// Normalised URL, or nil when nothing usable is configured yet.
    var resolvedURL: URL? { Self.normalise(rawURL) }

    /// True when the address should be reached over TLS. Split out so the
    /// setup screen can explain the choice in one line.
    static func inferredScheme(for host: String) -> Bool {
        let bare = host.split(separator: "/").first.map(String.init) ?? host
        let parts = bare.split(separator: ":")
        let name = parts.first.map(String.init) ?? bare
        if parts.count > 1, let port = Int(parts[1]) {
            return port == 443 || port == 8443
        }
        if name.hasSuffix(".local") { return false }
        // A bare IPv4 is a box on this network.
        let octets = name.split(separator: ".")
        if octets.count == 4, octets.allSatisfy({ Int($0) != nil }) { return false }
        return name.contains(".")
    }

    func apply(_ candidate: String) {
        rawURL = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        reloadToken = UUID()
    }

    /*
     * Accepts what a human actually types and fills in the rest.
     *
     * Nobody should have to work out whether this field wants a scheme, and the
     * old guess ("has a colon → probably a LAN box → http") sent
     * `asgard.example.ts.net:8443` to plain HTTP, which simply failed. The rules
     * are now explicit, and — more importantly — whatever they produce is shown
     * back to the user before anything is contacted, so the heuristic never has
     * to be guessed at.
     *
     *   scheme given            → kept as typed
     *   port 443 / 8443 / 8080… → 443 and 8443 mean TLS, everything else plain
     *   no port, has a dot      → https (a real hostname on the internet or a
     *                             tailnet), unless it is .local or an IP
     *   .local or a bare IP     → http (a box on this network)
     */
    static func normalise(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if !text.contains("://") {
            text = (inferredScheme(for: text) ? "https://" : "http://") + text
        }

        guard var components = URLComponents(string: text), components.host != nil else { return nil }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty || "/\(path)" == mobilePath {
            components.path = mobilePath
        }
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
