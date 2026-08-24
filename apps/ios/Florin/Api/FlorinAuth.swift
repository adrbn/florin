import Foundation
import Security

/// The bearer token this phone presents to a Florin server.
///
/// The desktop build's local server has no authentication — it is bound to the
/// machine. A self-hosted *web* deployment does: its v2 routes accept either a
/// NextAuth session cookie or a bearer token, and a native app has no cookie to
/// present. So the app carries a token, and sends it on every request; servers
/// that do not need one ignore it.
///
/// It lives in the Keychain rather than `UserDefaults`. A token is a password
/// for the whole ledger, and `UserDefaults` is a plist in the app container —
/// readable by anything that gets a backup of the device.
enum FlorinAuth {
    private static let service = "com.adrbn.florin"
    private static let account = "api-token"

    /// Cached so a request does not hit the Keychain on every call; the setter
    /// is the only thing that ever changes it.
    private nonisolated(unsafe) static var cached: String??

    static var token: String? {
        get {
            if let cached { return cached }
            let value = read()
            cached = .some(value)
            return value
        }
        set {
            cached = .some(newValue)
            write(newValue)
        }
    }

    /// A GET request carrying the token, if there is one.
    static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        authorize(&request)
        return request
    }

    static func authorize(_ request: inout URLRequest) {
        guard let token, !token.isEmpty else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    // MARK: - Keychain

    private static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty
        else { return nil }
        return text
    }

    private static func write(_ value: String?) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)

        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var insert = base
        insert[kSecValueData as String] = data
        // Available once the device has been unlocked, so a background refresh
        // still works, but never leaves this device in a backup.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(insert as CFDictionary, nil)
    }
}
