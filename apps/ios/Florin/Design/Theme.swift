import SwiftUI

/// The Obsidian palette, ported from `packages/core/src/components/v2/theme/v2.css`.
///
/// The web tokens are a deliberately flat set of custom properties precisely so
/// they could cross to native without re-deriving anything. Keep the two in
/// step: a drift here shows up as a phone that does not look like the browser.
enum Florin {
    // MARK: Surfaces
    static let bg = dynamic(light: 0xFBFBFD, dark: 0x0D0E12)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x1B1D23)
    static let surface2 = dynamic(light: 0xF3F3F6, dark: 0x22242B)
    static let surface3 = dynamic(light: 0xEAEAEF, dark: 0x2B2D36)

    // MARK: Text
    static let text = dynamic(light: 0x22242C, dark: 0xFAFAFC)
    static let text2 = dynamic(light: 0x63656F, dark: 0xA6A8B3)
    static let text3 = dynamic(light: 0x8E909B, dark: 0x6E7180)

    // MARK: Accent and semantics
    static let accent = dynamic(light: 0x4B4FD6, dark: 0x8C8CF7)
    static let positive = dynamic(light: 0x1F8B5F, dark: 0x5FD9A0)
    static let negative = dynamic(light: 0xC4392F, dark: 0xF08072)
    /// Needs a decision — not an error. Red already means "money left", so a
    /// review flag drawn in it reads as a loss rather than as a question.
    static let warn = dynamic(light: 0xB4690E, dark: 0xF0B357)

    /// Categorical series — never the semantic green or red, so a spending bar
    /// can't read as a gain.
    static let series: [Color] = [
        dynamic(light: 0x4B57D2, dark: 0x8C93F2),
        dynamic(light: 0x1E7FA0, dark: 0x63C3DE),
        dynamic(light: 0x148A93, dark: 0x5CCBD3),
        dynamic(light: 0x9A6A18, dark: 0xE0B45C),
        dynamic(light: 0xB25C1E, dark: 0xEFA26A),
        dynamic(light: 0xA33C86, dark: 0xEC85C9),
        dynamic(light: 0x7B45B8, dark: 0xBB92EF),
        dynamic(light: 0x4E6B8F, dark: 0x97AECC),
    ]

    static let cardRadius: CGFloat = 26
    static let rowRadius: CGFloat = 14
    static let gutter: CGFloat = 18

    /// Stable colour per label, matching the web `seriesVar` FNV-1a hash so a
    /// category is the same hue on both surfaces.
    static func seriesColor(for label: String) -> Color {
        var hash: UInt32 = 0x811c_9dc5
        for unit in label.utf16 {
            hash ^= UInt32(unit)
            hash = hash &* 0x0100_0193
        }
        return series[Int(hash % UInt32(series.count))]
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Building blocks

struct FlorinCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .florinSurface()
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.0)
            .foregroundStyle(Florin.text3)
    }
}

struct Pill: View {
    let text: String
    var tone: Color = Florin.text2
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tone)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tone.opacity(0.12), in: Capsule())
    }
}


/// The Florin wordmark.
///
/// San Francisco, like everything else in the app. The brand serif was a web
/// idiom carried across; on iOS a second typeface in the chrome reads as a
/// theme rather than as a system app, and it is the one thing that made these
/// screens look imported. Weight and tracking carry the identity instead.
struct Wordmark: View {
    var size: CGFloat = 19

    var body: some View {
        Text("Florin")
            .font(.system(size: size, weight: .semibold, design: .default))
            .kerning(-0.5)
            .foregroundStyle(Florin.text)
            .accessibilityAddTraits(.isHeader)
    }
}


extension View {
    /// Content surface.
    ///
    /// Deliberately *not* Liquid Glass: on iOS 26 glass belongs to the
    /// interface layer — bars, floating controls, the toast — and putting it
    /// behind content is the mistake that makes an app look like it discovered
    /// a new material and used it everywhere. Content gets a tonal fill and a
    /// hairline. The heavy drop shadow this replaced was a web idiom; 26
    /// separates with tone, so the shadow is now a whisper.
    func florinSurface(radius: CGFloat = Florin.cardRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            // Clip first: rows paint their own backgrounds (the amber wash on a
            // "à vérifier" line), and without this they run square into the
            // card's rounded corners.
            .clipShape(shape)
            .background(Florin.surface, in: shape)
            .overlay(shape.strokeBorder(Florin.text.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 3)
    }
}


/// App appearance. Dark is the default — see RootView.
enum Appearance: String, CaseIterable, Identifiable {
    case dark
    case light
    case system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark: return "Sombre"
        case .light: return "Clair"
        case .system: return "Système"
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
