import SwiftUI

/// Where Florin reads from — and an explicit way to say so.
///
/// This used to be implicit: a server address on file meant server mode, its
/// absence meant the device. Which made switching a matter of clearing a text
/// field, left no way to keep a server configured while working locally, and
/// gave the settings screen nothing honest to show. A server and an on-device
/// ledger are two different sets of books; which one you are looking at is a
/// choice, not a side effect.
enum DataSource: String, CaseIterable, Identifiable {
    case server
    case device

    var id: String { rawValue }

    var label: String {
        switch self {
        case .server: Strings.device("v2.source.server", "Mon serveur")
        case .device: "Cet appareil"
        }
    }

    var detail: String {
        switch self {
        case .server:
            Strings.device("v2.source.serverDetail", "Florin lit votre serveur, y compris les comptes que la banque ne suit pas.")
        case .device:
            Strings.device("v2.source.deviceDetail", "Tout est stocké sur ce téléphone. Rien ne sort.")
        }
    }

    var symbol: String {
        switch self {
        case .server: "externaldrive.badge.wifi"
        case .device: "iphone"
        }
    }
}
