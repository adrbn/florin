import Foundation
import Security

/// The RSA key Enable Banking knows this app by.
///
/// On the desktop build this is a `.pem` file the user downloads from Enable
/// Banking's console and points the app at. A phone has no file to point at and
/// no good place to keep one, so the key is generated on the device and never
/// leaves it: the private half lives in the Keychain, and only the public half
/// is ever shown, to be pasted into the console once.
///
/// `kSecAttrIsPermanent` plus `WhenUnlockedThisDeviceOnly` is deliberate. The
/// key is the credential that lets this install read someone's bank; it should
/// not travel in an iCloud backup to a device the user no longer has, and it
/// should be unreadable while the phone is locked.
enum BankingKey {
    private static let tag = "com.adrbn.florin.banking.key".data(using: .utf8)!

    enum Failure: LocalizedError {
        case generate(String)
        case missing
        case export(String)
        case sign(String)

        var errorDescription: String? {
            switch self {
            case let .generate(message): "Could not create the banking key: \(message)"
            case .missing: "No banking key on this device yet."
            case let .export(message): "Could not read the banking key: \(message)"
            case let .sign(message): "Could not sign the request: \(message)"
            }
        }
    }

    /// True once a key exists, so settings can show the right step.
    static var exists: Bool { (try? load()) != nil }

    /// Create the key, replacing any previous one.
    ///
    /// Replacing invalidates the app registration in Enable Banking's console
    /// until the new public key is pasted there — which is why the caller has
    /// to ask first.
    @discardableResult
    static func generate() throws -> SecKey {
        try? delete()

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ],
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw Failure.generate(message(from: error))
        }
        return key
    }

    static func load() throws -> SecKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecReturnRef as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let key = item
        else { throw Failure.missing }
        // swiftlint:disable:next force_cast
        return key as! SecKey
    }

    static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// The public half, as the PEM Enable Banking's console expects.
    ///
    /// `SecKeyCopyExternalRepresentation` hands back a bare PKCS#1 RSA key;
    /// the console wants SubjectPublicKeyInfo, so the RSA algorithm identifier
    /// is prepended by hand. Without that header the console accepts the paste
    /// and every later request fails to verify, which is a miserable thing to
    /// debug from a phone.
    static func publicKeyPEM() throws -> String {
        let privateKey = try load()
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw Failure.export("no public half")
        }
        var error: Unmanaged<CFError>?
        guard let raw = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw Failure.export(message(from: error))
        }

        /// DER: SEQUENCE { SEQUENCE { OID rsaEncryption, NULL }, BIT STRING }
        let rsaOID: [UInt8] = [
            0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
            0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00,
        ]
        var bitString = Data([0x00])
        bitString.append(raw)
        var inner = Data(rsaOID)
        inner.append(der(tag: 0x03, payload: bitString))
        let spki = der(tag: 0x30, payload: inner)

        let body = spki.base64EncodedString()
        let wrapped = stride(from: 0, to: body.count, by: 64).map { offset -> String in
            let start = body.index(body.startIndex, offsetBy: offset)
            let end = body.index(start, offsetBy: min(64, body.count - offset))
            return String(body[start..<end])
        }
        return (["-----BEGIN PUBLIC KEY-----"] + wrapped + ["-----END PUBLIC KEY-----"])
            .joined(separator: "\n")
    }

    /*
     * A self-signed X.509 certificate wrapping the public key.
     *
     * Enable Banking's console asks for a certificate, not a bare public key —
     * its own instructions are `openssl req -new -x509`. A SPKI public key
     * pasted into that field is rejected, so the device has to produce a real
     * certificate.
     *
     * Hand-built rather than pulled from a package: this is the credential that
     * reads someone's bank, the structure below is small and fixed, and the
     * result is checkable — `openssl x509 -text` either parses it or does not.
     * A dependency would be more code to trust, not less.
     */
    static func certificatePEM(
        commonName: String = "Florin iOS",
        days: Int = 3650
    ) throws -> String {
        let privateKey = try load()
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw Failure.export("no public half")
        }
        var error: Unmanaged<CFError>?
        guard let rawPublic = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw Failure.export(message(from: error))
        }

        let rsaOID: [UInt8] = [
            0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
            0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00,
        ]
        var publicBits = Data([0x00])
        publicBits.append(rawPublic)
        var spkiInner = Data(rsaOID)
        spkiInner.append(der(tag: 0x03, payload: publicBits))
        let spki = der(tag: 0x30, payload: spkiInner)

        /// sha256WithRSAEncryption, as both the TBS and the outer algorithm —
        /// they have to agree or every verifier rejects the certificate.
        let signatureOID: [UInt8] = [
            0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
            0xf7, 0x0d, 0x01, 0x01, 0x0b, 0x05, 0x00,
        ]

        // A single CN, used as both issuer and subject: self-signed means the
        // two are the same name by definition.
        let name = distinguishedName(commonName: commonName)

        let now = Date()
        let notAfter = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: days, to: now) ?? now
        var validity = Data()
        validity.append(utcTime(now))
        validity.append(utcTime(notAfter))
        let validitySeq = der(tag: 0x30, payload: validity)

        var tbs = Data()
        // [0] EXPLICIT version, v3 = 2.
        tbs.append(der(tag: 0xa0, payload: der(tag: 0x02, payload: Data([0x02]))))
        // Serial: positive, non-zero, and unique per certificate.
        tbs.append(der(tag: 0x02, payload: serialNumber()))
        tbs.append(Data(signatureOID))
        tbs.append(name)
        tbs.append(validitySeq)
        tbs.append(name)
        tbs.append(spki)
        let tbsCertificate = der(tag: 0x30, payload: tbs)

        let signature = try sign(tbsCertificate)
        var signatureBits = Data([0x00])
        signatureBits.append(signature)

        var certificate = Data()
        certificate.append(tbsCertificate)
        certificate.append(Data(signatureOID))
        certificate.append(der(tag: 0x03, payload: signatureBits))

        return pem(der(tag: 0x30, payload: certificate), label: "CERTIFICATE")
    }

    /// RDNSequence with one RDN: CN=<commonName>, as a PrintableString.
    private static func distinguishedName(commonName: String) -> Data {
        let commonNameOID: [UInt8] = [0x06, 0x03, 0x55, 0x04, 0x03]
        var attribute = Data(commonNameOID)
        attribute.append(der(tag: 0x13, payload: Data(commonName.utf8)))
        let typeAndValue = der(tag: 0x30, payload: attribute)
        let rdn = der(tag: 0x31, payload: typeAndValue)
        return der(tag: 0x30, payload: rdn)
    }

    /// UTCTime, YYMMDDHHMMSSZ in UTC — the encoding X.509 uses for dates
    /// before 2050.
    private static func utcTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return der(tag: 0x17, payload: Data(formatter.string(from: date).utf8))
    }

    /// Random, and forced positive: DER integers are signed, so a leading byte
    /// above 0x7f would encode a negative serial, which parsers reject.
    private static func serialNumber() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        bytes[0] &= 0x7f
        if bytes[0] == 0 { bytes[0] = 1 }
        return Data(bytes)
    }

    private static func pem(_ der: Data, label: String) -> String {
        let body = der.base64EncodedString()
        let wrapped = stride(from: 0, to: body.count, by: 64).map { offset -> String in
            let start = body.index(body.startIndex, offsetBy: offset)
            let end = body.index(start, offsetBy: min(64, body.count - offset))
            return String(body[start..<end])
        }
        return (["-----BEGIN \(label)-----"] + wrapped + ["-----END \(label)-----"])
            .joined(separator: "\n")
    }

    /// RS256 over the JWT's signing input.
    static func sign(_ input: Data) throws -> Data {
        let key = try load()
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key, .rsaSignatureMessagePKCS1v15SHA256, input as CFData, &error
        ) as Data? else {
            throw Failure.sign(message(from: error))
        }
        return signature
    }

    // MARK: - DER

    /// One DER TLV. Lengths under 128 are a single byte; above that the long
    /// form says how many length bytes follow. A 2048-bit key lands in the
    /// two-byte case, so getting this wrong is not theoretical.
    private static func der(tag: UInt8, payload: Data) -> Data {
        var out = Data([tag])
        let count = payload.count
        if count < 0x80 {
            out.append(UInt8(count))
        } else {
            var length = count
            var bytes: [UInt8] = []
            while length > 0 {
                bytes.insert(UInt8(length & 0xff), at: 0)
                length >>= 8
            }
            out.append(UInt8(0x80 | bytes.count))
            out.append(contentsOf: bytes)
        }
        out.append(payload)
        return out
    }

    private static func message(from error: Unmanaged<CFError>?) -> String {
        guard let error else { return "unknown error" }
        return (error.takeRetainedValue() as Error).localizedDescription
    }
}
