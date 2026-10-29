import SwiftUI

/*
 * Les thèmes.
 *
 * `Theme.swift` portait une palette unique — Obsidian — en littéraux. Un
 * thème n'est pas un mode : « clair » et « sombre » sont les deux faces d'une
 * même palette, et choisir un thème change la palette elle-même, les deux
 * faces avec. Les deux réglages se composent donc au lieu de se concurrencer :
 * Papier en sombre est du blanc sur noir, Papier en clair du noir sur blanc.
 *
 * Ce fichier ne contient que des données et aucune logique d'app : l'extension
 * widget le compile comme elle compile `Theme.swift`, pour que la vignette
 * suive le thème au lieu de rester sur celui d'origine.
 */

/// Une encre, vue des deux côtés.
struct Tone {
    let light: UInt32
    let dark: UInt32

    /// La même valeur de part et d'autre — pour un fond coloré, qui ne
    /// s'inverse pas.
    init(_ both: UInt32) { light = both; dark = both }
    init(light: UInt32, dark: UInt32) { self.light = light; self.dark = dark }
}

struct Palette {
    var bg, surface, surface2, surface3: Tone
    var text, text2, text3: Tone
    var accent, onAccent, positive, negative, warn: Tone
    /// Huit encres catégorielles, jamais le vert ni le rouge sémantiques.
    var series: [Tone]
    /*
     * Les fonds colorés : un par onglet, puis celui des feuilles.
     *
     * Un tableau et non un dictionnaire par onglet, parce que `TabRoute`
     * appartient à l'app et ce fichier doit rester compilable par le widget.
     * L'ordre est fixé par `Ground` juste en dessous.
     */
    var grounds: [Tone]
    /// Le poids du fond coloré. 0 = fond plat, c'est-à-dire minimal.
    var ground: Double

    enum Ground: Int {
        case overview, accounts, plan, activity, analysis, settings, sheet
    }

    func ground(_ which: Ground) -> Tone { grounds[which.rawValue] }
}

enum FlorinPalette: String, CaseIterable, Identifiable {
    case obsidian
    case papier
    case sepia
    case ardoise
    case editorial

    var id: String { rawValue }

    /// Des noms propres : ils ne se traduisent pas.
    var name: String {
        switch self {
        case .obsidian: return "Obsidienne"
        case .papier: return "Papier"
        case .sepia: return "Sépia"
        case .ardoise: return "Ardoise"
        case .editorial: return "Éditorial"
        }
    }

    var palette: Palette {
        switch self {
        case .obsidian: return .obsidian
        case .papier: return .papier
        case .sepia: return .sepia
        case .ardoise: return .ardoise
        case .editorial: return .editorial
        }
    }

    // MARK: Le thème actif

    static let key = "florin.palette"
    /// Le même bidon que la vignette lit — sans quoi le widget garderait la
    /// palette d'origine et trahirait l'écran qu'il résume.
    static let suite = "group.com.adrbn.florin"

    private nonisolated(unsafe) static var cached: Palette?

    /// La palette active, résolue une fois puis gardée. Les jetons de `Florin`
    /// passent par `Palette.current`, qui mène ici.
    static var resolved: Palette {
        if let cached { return cached }
        let stored = UserDefaults(suiteName: suite)?.string(forKey: key)
            ?? UserDefaults.standard.string(forKey: key)
        let resolved = (FlorinPalette(rawValue: stored ?? "") ?? .obsidian).palette
        cached = resolved
        return resolved
    }

    /// Applique et retient le choix, des deux côtés de la cloison.
    static func use(_ choice: FlorinPalette) {
        cached = choice.palette
        UserDefaults.standard.set(choice.rawValue, forKey: key)
        UserDefaults(suiteName: suite)?.set(choice.rawValue, forKey: key)
    }

    /// Le thème choisi, par son nom — pour le réglage qui le coche.
    static var selected: FlorinPalette {
        FlorinPalette(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .obsidian
    }
}

// MARK: - Les palettes

extension Palette {
    /// Le thème actif. Le nom vit du côté des jetons, qui le lisent.
    static var current: Palette { FlorinPalette.resolved }


    /// La palette d'origine, portée de `packages/core/.../v2.css`. Les valeurs
    /// sont celles que `Theme.swift` écrivait en dur : ne pas les dériver.
    static let obsidian = Palette(
        bg: Tone(light: 0xFBFBFD, dark: 0x0D0E12),
        surface: Tone(light: 0xFFFFFF, dark: 0x1B1D23),
        surface2: Tone(light: 0xF3F3F6, dark: 0x22242B),
        surface3: Tone(light: 0xEAEAEF, dark: 0x2B2D36),
        text: Tone(light: 0x22242C, dark: 0xFAFAFC),
        text2: Tone(light: 0x63656F, dark: 0xA6A8B3),
        text3: Tone(light: 0x8E909B, dark: 0x6E7180),
        accent: Tone(light: 0x4B4FD6, dark: 0x8C8CF7),
        onAccent: Tone(light: 0xFFFFFF, dark: 0x101218),
        positive: Tone(light: 0x1F8B5F, dark: 0x5FD9A0),
        negative: Tone(light: 0xC4392F, dark: 0xF08072),
        warn: Tone(light: 0xB4690E, dark: 0xF0B357),
        series: [
            Tone(light: 0x4B57D2, dark: 0x8C93F2),
            Tone(light: 0x1E7FA0, dark: 0x63C3DE),
            Tone(light: 0x148A93, dark: 0x5CCBD3),
            Tone(light: 0x9A6A18, dark: 0xE0B45C),
            Tone(light: 0xB25C1E, dark: 0xEFA26A),
            Tone(light: 0xA33C86, dark: 0xEC85C9),
            Tone(light: 0x7B45B8, dark: 0xBB92EF),
            Tone(light: 0x4E6B8F, dark: 0x97AECC),
        ],
        grounds: [
            Tone(0x5C54E6), Tone(0x1A6BC7), Tone(0x9E4D9E),
            Tone(0x8038D1), Tone(0x14858A), Tone(0x4D4F94), Tone(0x17705E),
        ],
        ground: 1.0
    )

    /*
     * Papier : noir sur blanc, et rien d'autre.
     *
     * Le fond coloré tombe à zéro — c'est la seule façon d'être réellement
     * minimal, un voile violet pâle reste un voile violet. Les séries
     * deviennent une rampe de gris : huit catégories se distinguent moins
     * bien, et c'est exactement ce qu'on demande en demandant du minimal. Le
     * vert et le rouge restent, assourdis : ils ne décorent pas, ils disent
     * le signe d'un montant.
     */
    static let papier = Palette(
        bg: Tone(light: 0xFFFFFF, dark: 0x000000),
        surface: Tone(light: 0xFFFFFF, dark: 0x0B0B0B),
        surface2: Tone(light: 0xF5F5F5, dark: 0x161616),
        surface3: Tone(light: 0xE9E9E9, dark: 0x222222),
        text: Tone(light: 0x000000, dark: 0xFFFFFF),
        text2: Tone(light: 0x595959, dark: 0xA3A3A3),
        text3: Tone(light: 0x8C8C8C, dark: 0x6B6B6B),
        accent: Tone(light: 0x000000, dark: 0xFFFFFF),
        onAccent: Tone(light: 0xFFFFFF, dark: 0x000000),
        positive: Tone(light: 0x1A6B4A, dark: 0x58C695),
        negative: Tone(light: 0x9E2A20, dark: 0xE07268),
        warn: Tone(light: 0x7A5200, dark: 0xD9A14F),
        series: [
            Tone(light: 0x141414, dark: 0xF5F5F5),
            Tone(light: 0x3D3D3D, dark: 0xD4D4D4),
            Tone(light: 0x5C5C5C, dark: 0xB8B8B8),
            Tone(light: 0x757575, dark: 0x9C9C9C),
            Tone(light: 0x8F8F8F, dark: 0x858585),
            Tone(light: 0xA8A8A8, dark: 0x6E6E6E),
            Tone(light: 0xC2C2C2, dark: 0x575757),
            Tone(light: 0xD6D6D6, dark: 0x424242),
        ],
        grounds: Array(repeating: Tone(light: 0x000000, dark: 0xFFFFFF), count: 7),
        ground: 0.0
    )

    /// Sépia : encre brune sur crème. Une page, pas un écran.
    static let sepia = Palette(
        bg: Tone(light: 0xFAF5EB, dark: 0x120F0A),
        surface: Tone(light: 0xFFFCF5, dark: 0x1C1811),
        surface2: Tone(light: 0xF2EADB, dark: 0x262118),
        surface3: Tone(light: 0xE6DBC6, dark: 0x332C20),
        text: Tone(light: 0x2B2116, dark: 0xF3EADA),
        text2: Tone(light: 0x6B5A45, dark: 0xB8A88E),
        text3: Tone(light: 0x96886F, dark: 0x83765F),
        accent: Tone(light: 0x8A5A24, dark: 0xD9A460),
        onAccent: Tone(light: 0xFFF8EC, dark: 0x1A1409),
        positive: Tone(light: 0x4A6B2A, dark: 0x9ECF6B),
        negative: Tone(light: 0xA33A22, dark: 0xE8896B),
        warn: Tone(light: 0x8A6510, dark: 0xE0B05A),
        series: [
            Tone(light: 0x8A5A24, dark: 0xD9A460),
            Tone(light: 0x6B5A2A, dark: 0xC9B273),
            Tone(light: 0x3F6B4A, dark: 0x9ECF9E),
            Tone(light: 0x2A6B6B, dark: 0x73C9C9),
            Tone(light: 0x6B4A6B, dark: 0xC993C9),
            Tone(light: 0x8A4A3A, dark: 0xE89A86),
            Tone(light: 0x5A5A8A, dark: 0x9A9AD9),
            Tone(light: 0x7A7A4A, dark: 0xCBCB86),
        ],
        grounds: [
            Tone(0xA5753A), Tone(0x8A6B3A), Tone(0x9E6B4A),
            Tone(0x8A5A4A), Tone(0x6B7A4A), Tone(0x7A6B55), Tone(0x6B7A5A),
        ],
        ground: 0.55
    )

    /// Ardoise : gris froid et sarcelle. Le plus proche d'un outil.
    static let ardoise = Palette(
        bg: Tone(light: 0xF6F8F9, dark: 0x0A1013),
        surface: Tone(light: 0xFFFFFF, dark: 0x141C21),
        surface2: Tone(light: 0xEDF1F3, dark: 0x1C262C),
        surface3: Tone(light: 0xDFE5E9, dark: 0x26323A),
        text: Tone(light: 0x15202A, dark: 0xF2F6F8),
        text2: Tone(light: 0x55646F, dark: 0x9DAFB9),
        text3: Tone(light: 0x86939C, dark: 0x6B7A84),
        accent: Tone(light: 0x0E6E7A, dark: 0x48C6D4),
        onAccent: Tone(light: 0xFFFFFF, dark: 0x06161A),
        positive: Tone(light: 0x177A57, dark: 0x55D4A2),
        negative: Tone(light: 0xB33628, dark: 0xEE7B6E),
        warn: Tone(light: 0x9A6408, dark: 0xE7B257),
        series: [
            Tone(light: 0x0E6E7A, dark: 0x48C6D4),
            Tone(light: 0x1F5C8C, dark: 0x6FA8DC),
            Tone(light: 0x2A7A5A, dark: 0x5FD0A0),
            Tone(light: 0x6B6B2A, dark: 0xC9C96B),
            Tone(light: 0x8A5A2A, dark: 0xE0A06B),
            Tone(light: 0x8A3A6B, dark: 0xE07BB8),
            Tone(light: 0x5A3A8A, dark: 0xA88ADC),
            Tone(light: 0x46606E, dark: 0x93AEBF),
        ],
        grounds: [
            Tone(0x1A6E7A), Tone(0x15597A), Tone(0x4A5A8A),
            Tone(0x2A6B8A), Tone(0x177A6B), Tone(0x2E4652), Tone(0x15605A),
        ],
        ground: 0.85
    )

    /*
     * Éditorial : une page de magazine, pas un tableau de bord.
     *
     * Blanc pur ou noir pur, et une seule couleur — un orange — réservée à ce
     * qui alerte. Tout le reste est gris : la hiérarchie vient de la taille du
     * texte, pas d'une pastille colorée de plus.
     *
     * Conséquence assumée : un gain n'est pas vert, il est de l'encre
     * ordinaire. Dans un thème où la couleur ne sert qu'à alerter, peindre en
     * vert ce qui va bien rend l'orange moins audible — et le signe devant le
     * montant dit déjà le sens.
     */
    static let editorial = Palette(
        bg: Tone(light: 0xFFFFFF, dark: 0x000000),
        surface: Tone(light: 0xF2F2F4, dark: 0x1C1C1E),
        surface2: Tone(light: 0xEFEFF1, dark: 0x2C2C2E),
        // Le filet de la maquette (0xEFEFF1) se pose sur du blanc ; ici la même
        // encre sert aussi à séparer sur une carte grise, où elle disparaîtrait.
        surface3: Tone(light: 0xE4E4E7, dark: 0x1F1F22),
        text: Tone(light: 0x0A0A0A, dark: 0xF5F5F7),
        text2: Tone(light: 0x5C5C61, dark: 0xA1A1A6),
        // Le gris des bordures de pastille (0xC7C7CC / 0x48484A) est une encre
        // de trait : lu comme du texte il tombe sous le contraste minimal.
        text3: Tone(light: 0x8A8A8F, dark: 0x76767C),
        accent: Tone(light: 0xD9481F, dark: 0xC93D17),
        onAccent: Tone(light: 0xFFFFFF, dark: 0xFFFFFF),
        positive: Tone(light: 0x0A0A0A, dark: 0xF5F5F7),
        negative: Tone(light: 0xD9481F, dark: 0xFF7A52),
        warn: Tone(light: 0xD9481F, dark: 0xFF7A52),
        series: [
            Tone(light: 0x0A0A0A, dark: 0xF5F5F7),
            Tone(light: 0x3A3A3E, dark: 0xD2D2D7),
            Tone(light: 0x5C5C61, dark: 0xA1A1A6),
            Tone(light: 0x76767C, dark: 0x8A8A8F),
            Tone(light: 0x8A8A8F, dark: 0x76767C),
            Tone(light: 0xA1A1A6, dark: 0x5C5C61),
            Tone(light: 0xC7C7CC, dark: 0x48484A),
            Tone(light: 0xDEDEE2, dark: 0x343438),
        ],
        grounds: Array(repeating: Tone(light: 0x0A0A0A, dark: 0xF5F5F7), count: 7),
        // Ni dégradé ni voile teinté : la maquette n'en a aucun.
        ground: 0.0
    )
}

// MARK: - Encre vers couleur

extension Tone {
    /// Cette encre, hors du thème actif — pour montrer un thème qu'on n'a pas
    /// encore choisi. Suit quand même clair/sombre : une pastille de thème qui
    /// ne montre pas la face qu'on va voir ne montre rien.
    var color: Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
