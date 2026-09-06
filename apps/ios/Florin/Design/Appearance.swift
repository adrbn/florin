import SwiftUI

/*
 * Split out of Theme.swift, which the widget target now compiles.
 *
 * The palette is design tokens and nothing else, and a widget extension needs
 * exactly that. This enum is a settings concern: it reads the string table to
 * name itself, and the table is resolved from UserDefaults the extension does
 * not share. Leaving it in Theme.swift made the palette unshareable for a
 * reason that had nothing to do with colour.
 */

/// App appearance. Dark is the default — see RootView.
enum Appearance: String, CaseIterable, Identifiable {
    case dark
    case light
    case system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark: return Strings.device("v2.settings.theme.dark", "Sombre")
        case .light: return Strings.device("v2.settings.theme.light", "Clair")
        case .system: return Strings.device("v2.settings.theme.system", "Système")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}
