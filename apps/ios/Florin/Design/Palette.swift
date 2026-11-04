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

    /// Ce ton, tiré vers un autre — chaque face avec sa propre proportion,
    /// parce qu'une teinte posée sur du blanc et la même posée sur du noir ne
    /// se voient pas à la même dose.
    func mixed(with other: Tone, light l: Double, dark d: Double) -> Tone {
        Tone(light: Tone.blend(light, other.light, l),
             dark: Tone.blend(dark, other.dark, d))
    }

    private static func blend(_ a: UInt32, _ b: UInt32, _ amount: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let from = Double((a >> shift) & 0xFF)
            let to = Double((b >> shift) & 0xFF)
            return UInt32((from + (to - from) * amount).rounded())
        }
        return (channel(16) << 16) | (channel(8) << 8) | channel(0)
    }

    /// Ce ton, dilué : la même teinte, reposée à une LUMINANCE imposée.
    ///
    /// La luminance, pas la clarté HSL, et c'est tout l'intérêt : à clarté
    /// égale un cyan est deux fois plus lumineux qu'un violet. Un premier jet
    /// imposait la clarté, et les rangs tombant dans les verts-bleus
    /// sortaient à 1,3:1 sur le papier — une barre de répartition invisible,
    /// pour un accent sur deux. Viser la luminance rend l'éventail
    /// indifférent à l'angle : chaque rang se détache autant, quel que soit
    /// l'accent choisi.
    ///
    /// Une par face, parce qu'une encre catégorielle est claire sur du noir
    /// et foncée sur du blanc.
    func diluted(saturation scale: Double, light l: Double, dark d: Double) -> Tone {
        Tone(light: Tone.dilute(light, 0, scale, l, Tone.inkBand),
             dark: Tone.dilute(dark, 0, scale, d, Tone.inkBand))
    }

    /// Le même, mais la teinte TOURNÉE sur la roue : une autre couleur, en
    /// relation d'harmonie avec l'accent, reposée à la luminance imposée.
    /// C'est ce qui fabrique un accord plutôt qu'une dilution.
    func spun(
        hue offset: Double, saturation scale: Double,
        light l: Double, dark d: Double, band: ClosedRange<Double> = Tone.inkBand
    ) -> Tone {
        Tone(light: Tone.dilute(light, offset, scale, l, band),
             dark: Tone.dilute(dark, offset, scale, d, band))
    }

    /// La fenêtre de saturation d'une encre catégorielle.
    ///
    /// Le plancher : sans lui, un accent presque gris (Graphite, Ardoise)
    /// rendrait huit gris, une légende où aucune pastille ne se reconnaît.
    ///
    /// Le plafond, c'est l'autre moitié et il a coûté un build : à pleine
    /// saturation, huit aplats pleine largeur sur une feuille blanche font
    /// une boîte de crayons. Éditorial est un thème noir et blanc où la
    /// couleur est une ponctuation — elle doit rester une encre, pas un
    /// surligneur.
    /// La fenêtre d'un DÉGRADÉ : la teinte ne bouge pas, donc rien d'autre
    /// que la densité ne distingue deux rangs, et un aplat trop saturé
    /// tiendrait toute la page.
    static let inkBand = 0.30 ... 0.55

    /// Celle d'un ACCORD, plus haute : ici c'est la teinte qui sépare les
    /// rangs, et une couleur lavée ne se nomme plus — un bleu et un vert
    /// désaturés au même niveau finissent tous deux « gris-bleu ».
    static let chordBand = 0.46 ... 0.78

    private static func dilute(
        _ rgb: UInt32, _ turn: Double, _ scale: Double, _ target: Double,
        _ band: ClosedRange<Double>
    ) -> UInt32 {
        let (base, saturation, _) = hsl(rgb)
        let ink = min(max(saturation, band.lowerBound), band.upperBound) * scale

        // La luminance croît avec la clarté à teinte et saturation fixes :
        // quatorze pas de dichotomie suffisent à tomber sous le demi-ton.
        var low = 0.0
        var high = 1.0
        var packed: UInt32 = 0
        for _ in 0 ..< 14 {
            let middle = (low + high) / 2
            packed = pack(hue: base + turn, saturation: ink, lightness: middle)
            if luminance(packed) < target { low = middle } else { high = middle }
        }
        return packed
    }

    private static func luminance(_ rgb: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((rgb >> shift) & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    private static func hsl(_ rgb: UInt32) -> (hue: Double, saturation: Double, lightness: Double) {
        let red = Double((rgb >> 16) & 0xFF) / 255
        let green = Double((rgb >> 8) & 0xFF) / 255
        let blue = Double(rgb & 0xFF) / 255
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let lightness = (high + low) / 2
        guard high > low else { return (0, 0, lightness) }
        let span = high - low
        let saturation = lightness > 0.5 ? span / (2 - high - low) : span / (high + low)
        var hue: Double
        switch high {
        case red: hue = (green - blue) / span + (green < blue ? 6 : 0)
        case green: hue = (blue - red) / span + 2
        default: hue = (red - green) / span + 4
        }
        return (hue * 60, saturation, lightness)
    }

    private static func pack(hue: Double, saturation: Double, lightness: Double) -> UInt32 {
        /*
         * La teinte ramenée dans le tour AVANT tout le reste.
         *
         * Le reste de cette fonction indexe une table par sixième de roue, et
         * la table n'a pas de rang négatif. Quand `dilute` s'est mis à tourner
         * la teinte, les rotations négatives sont sorties sous zéro — pour un
         * accent à 42°, −150° donne −108° — et `Int(-1,8) % 6` vaut −1 en
         * Swift : le `switch` tombait dans `default`, où `second` valait
         * −0,8 × chroma, rogné à zéro juste après. Soit (chroma, 0, 0) : un
         * ROUGE PUR, saturation 1,00, à la place de la couleur demandée.
         *
         * Deux rangs de l'accord sur huit, donc deux cartes de l'accueil
         * rouge vif pendant que les six autres suivaient l'accent. C'est ici
         * que ça se répare, pas chez l'appelant : la table est à cette
         * fonction, l'invariant qu'elle suppose lui appartient aussi.
         */
        let turn = hue.truncatingRemainder(dividingBy: 360)
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = (turn < 0 ? turn + 360 : turn) / 60
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let lift = lightness - chroma / 2
        let (red, green, blue): (Double, Double, Double)
        switch Int(sector) % 6 {
        case 0: (red, green, blue) = (chroma, second, 0)
        case 1: (red, green, blue) = (second, chroma, 0)
        case 2: (red, green, blue) = (0, chroma, second)
        case 3: (red, green, blue) = (0, second, chroma)
        case 4: (red, green, blue) = (second, 0, chroma)
        default: (red, green, blue) = (chroma, 0, second)
        }
        func byte(_ value: Double) -> UInt32 {
            UInt32((min(max(value + lift, 0), 1) * 255).rounded())
        }
        return (byte(red) << 16) | (byte(green) << 8) | byte(blue)
    }
}

struct Palette {
    var bg, surface, surface2, surface3: Tone
    var text, text2, text3: Tone
    var accent, onAccent, positive, negative, warn: Tone
    /// Huit encres catégorielles, jamais le vert ni le rouge sémantiques.
    /*
     * Huit teintes d'UNE SEULE famille, pas huit points de la roue.
     *
     * Les séries faisaient le tour complet : bleu, cyan, menthe, ocre,
     * orange, magenta, violet, ardoise. Un écran qui n'en montrait que deux
     * ou trois — la répartition — se lisait comme une palette tenue ; la pile
     * de cartes de l'accueil, qui les tire au hasard du nom, en montrait six
     * et se lisait comme une autre. Même boîte, deux impressions, et
     * l'impression de deux palettes vient de là, pas de la façon de piocher.
     *
     * Chaque thème garde donc sa famille et s'y tient : Obsidienne va du bleu
     * au vert menthe, Ardoise de la sarcelle au bleu, Sépia du brun à la
     * sauge, Papier est une rampe de gris. Les teintes se distinguent par
     * leur valeur plutôt que par leur teinte — c'est ce qui fait qu'un écran
     * entier tient ensemble. Le rouge et le vert restent dehors : ils disent
     * perdu et gagné.
     */
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

    /// Jette la palette gardée : la prochaine lecture la recalcule.
    static func forget() { cached = nil }

    /// Applique et retient le choix, des deux côtés de la cloison.
    static func use(_ choice: FlorinPalette) {
        cached = choice.palette
        UserDefaults.standard.set(choice.rawValue, forKey: key)
        UserDefaults(suiteName: suite)?.set(choice.rawValue, forKey: key)
    }

    /*
     * Le thème choisi, par son nom — pour le réglage qui le coche, et pour
     * tout dessin qui ne vaut que sous Éditorial.
     *
     * Le bidon partagé D'ABORD, dans le même ordre que `resolved`. Lu depuis
     * la vignette, `UserDefaults.standard` est celui de l'EXTENSION, où rien
     * n'a jamais été écrit : la couleur suivait bien le thème (elle passe par
     * `resolved`) pendant que la mise en page répondait « obsidian » et
     * dessinait l'ancienne.
     */
    static var selected: FlorinPalette {
        let stored = UserDefaults(suiteName: suite)?.string(forKey: key)
            ?? UserDefaults.standard.string(forKey: key)
        return FlorinPalette(rawValue: stored ?? "") ?? .obsidian
    }
}

/*
 * L'accent d'Éditorial, au choix.
 *
 * Six encres, pas une roue chromatique : chacune doit porter du blanc à
 * 4,5:1 en clair comme en sombre, et une couleur quelconque tirée d'un
 * sélecteur ne le garantit pas. Les noms sont ceux de la matière, pas ceux
 * d'une teinte — on choisit un ton, pas un hexadécimal.
 */
/*
 * Dix-huit encres, rangées comme une roue.
 *
 * L'ordre n'est pas décoratif : les cases défilent dans l'ordre de
 * déclaration, et une grille de pastilles rangée par famille se parcourt du
 * regard, alors qu'une grille rangée par ordre d'ajout se fouille. Chaudes,
 * puis vertes, puis bleues, puis violettes, puis les terres et les gris.
 *
 * Chaque ton clair tient au moins 4,1:1 sur blanc — le plancher du jeu
 * d'origine, mesuré sur l'ocre — et son ton sombre est le même assombri d'un
 * huitième, comme les six premiers. Vérifié par `scripts/check-accents.py`.
 */
enum EdAccent: String, CaseIterable, Identifiable {
    case cerise
    case brique
    case terracotta
    case cuivre
    case safran
    case ocre
    case moutarde
    case olive
    case fougere
    case sauge
    case foret
    case jade
    case canard
    case lagon
    case azur
    case denim
    case marine
    case outremer
    case encre
    case iris
    case lavande
    case mauve
    case aubergine
    case prune
    case framboise
    case rosebois
    case bordeaux
    case chocolat
    case ardoise
    case graphite

    var id: String { rawValue }

    var name: String {
        switch self {
        case .cerise: return "Cerise"
        case .brique: return "Brique"
        case .terracotta: return "Terracotta"
        case .cuivre: return "Cuivre"
        case .safran: return "Safran"
        case .ocre: return "Ocre"
        case .moutarde: return "Moutarde"
        case .olive: return "Olive"
        case .fougere: return "Fougère"
        case .sauge: return "Sauge"
        case .foret: return "Forêt"
        case .jade: return "Jade"
        case .canard: return "Canard"
        case .lagon: return "Lagon"
        case .azur: return "Azur"
        case .denim: return "Denim"
        case .marine: return "Marine"
        case .outremer: return "Outremer"
        case .encre: return "Encre"
        case .iris: return "Iris"
        case .lavande: return "Lavande"
        case .mauve: return "Mauve"
        case .aubergine: return "Aubergine"
        case .prune: return "Prune"
        case .framboise: return "Framboise"
        case .rosebois: return "Bois de rose"
        case .bordeaux: return "Bordeaux"
        case .chocolat: return "Chocolat"
        case .ardoise: return "Ardoise"
        case .graphite: return "Graphite"
        }
    }

    var tone: Tone {
        switch self {
        case .cerise: return Tone(light: 0xB3261E, dark: 0x9D211A)
        case .brique: return Tone(light: 0x983724, dark: 0x8E3421)
        case .terracotta: return Tone(light: 0xD9481F, dark: 0xC93D17)
        case .cuivre: return Tone(light: 0xA4542A, dark: 0x904924)
        case .safran: return Tone(light: 0x995E17, dark: 0x8F5915)
        case .ocre: return Tone(light: 0xA4740C, dark: 0x8F640A)
        case .moutarde: return Tone(light: 0x7E700E, dark: 0x77690D)
        case .olive: return Tone(light: 0x5E6B1C, dark: 0x525E18)
        case .fougere: return Tone(light: 0x406A1C, dark: 0x3D641A)
        case .sauge: return Tone(light: 0x356C3D, dark: 0x326539)
        case .foret: return Tone(light: 0x1C6B4A, dark: 0x185C3F)
        case .jade: return Tone(light: 0x12705D, dark: 0x116957)
        case .canard: return Tone(light: 0x0E6B73, dark: 0x0C5E65)
        case .lagon: return Tone(light: 0x126A81, dark: 0x106378)
        case .azur: return Tone(light: 0x1F6FB2, dark: 0x1B619C)
        case .denim: return Tone(light: 0x3A568D, dark: 0x365185)
        case .marine: return Tone(light: 0x1F3A5F, dark: 0x1B3353)
        case .outremer: return Tone(light: 0x423CA3, dark: 0x3D3899)
        case .encre: return Tone(light: 0x2F4DBF, dark: 0x2A44AD)
        case .iris: return Tone(light: 0x5B3FA8, dark: 0x503793)
        case .lavande: return Tone(light: 0x77489F, dark: 0x6F4396)
        case .mauve: return Tone(light: 0x8D3793, dark: 0x85338A)
        case .aubergine: return Tone(light: 0x4A2545, dark: 0x41203C)
        case .prune: return Tone(light: 0x8C2F6B, dark: 0x7A295D)
        case .framboise: return Tone(light: 0xAE2A5E, dark: 0x992452)
        case .rosebois: return Tone(light: 0xA44656, dark: 0x9A4250)
        case .bordeaux: return Tone(light: 0x7C1F33, dark: 0x6D1B2C)
        case .chocolat: return Tone(light: 0x5A3B2A, dark: 0x4F3324)
        case .ardoise: return Tone(light: 0x3F4C5A, dark: 0x36424E)
        case .graphite: return Tone(light: 0x35383D, dark: 0x2E3135)
        }
    }

    static let key = "florin.editorialAccent"

    /// Le bidon partagé d'abord : la vignette n'a pas accès aux préférences
    /// de l'app, et un widget qui garde l'orange pendant que l'écran est vert
    /// trahit l'écran qu'il résume.
    static var selected: EdAccent {
        let stored = UserDefaults(suiteName: FlorinPalette.suite)?.string(forKey: key)
            ?? UserDefaults.standard.string(forKey: key)
        return EdAccent(rawValue: stored ?? "") ?? .terracotta
    }

    /// Retient le choix et jette la palette gardée, sans quoi l'écran
    /// continue de peindre l'ancien accent jusqu'au prochain lancement.
    static func use(_ choice: EdAccent) {
        UserDefaults.standard.set(choice.rawValue, forKey: key)
        UserDefaults(suiteName: FlorinPalette.suite)?.set(choice.rawValue, forKey: key)
        FlorinPalette.forget()
    }
}

/*
 * Comment Éditorial tire ses huit encres catégorielles.
 *
 * Deux gestes différents, et aucun ne remplace l'autre. La PALETTE est le
 * jeu d'origine : huit teintes franches et sans parenté, qui disent huit
 * catégories. Le DÉGRADÉ n'est qu'une encre, diluée huit fois, qui dit un
 * thème. L'un se lit mieux, l'autre se tient mieux — c'est un goût, donc un
 * réglage.
 *
 * Seul Éditorial le propose : les quatre autres thèmes ont leur propre jeu
 * de huit, dessiné avec eux.
 */
enum EdInks: String, CaseIterable, Identifiable {
    case palette
    case gradient

    var id: String { rawValue }

    static let key = "florin.editorialInks"

    static var selected: EdInks {
        let stored = UserDefaults(suiteName: FlorinPalette.suite)?.string(forKey: key)
            ?? UserDefaults.standard.string(forKey: key)
        return EdInks(rawValue: stored ?? "") ?? .palette
    }

    static func use(_ choice: EdInks) {
        UserDefaults.standard.set(choice.rawValue, forKey: key)
        UserDefaults(suiteName: FlorinPalette.suite)?.set(choice.rawValue, forKey: key)
        FlorinPalette.forget()
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
            Tone(light: 0x148A93, dark: 0x5CCBD3),
            Tone(light: 0x1E5FA8, dark: 0x6FA8DC),
            Tone(light: 0x2A7F6A, dark: 0x6FD4B4),
            Tone(light: 0x1E7FA0, dark: 0x63C3DE),
            Tone(light: 0x4E6B8F, dark: 0x97AECC),
            Tone(light: 0x146B74, dark: 0x8FDCE2),
            Tone(light: 0x6168C4, dark: 0xAEB3F7),
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
            Tone(light: 0x3F6B4A, dark: 0x9ECF9E),
            Tone(light: 0x6B5A2A, dark: 0xC9B273),
            Tone(light: 0x5A6B45, dark: 0xB2C491),
            Tone(light: 0x7A6B3A, dark: 0xD4BC80),
            Tone(light: 0x4A5A3A, dark: 0x9AAD80),
            Tone(light: 0x8A6B45, dark: 0xD9B88E),
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
            Tone(light: 0x15607A, dark: 0x5FB5CC),
            Tone(light: 0x1A7A6B, dark: 0x58D4BC),
            Tone(light: 0x46606E, dark: 0x93AEBF),
            Tone(light: 0x1F4C7A, dark: 0x7FB0E0),
            Tone(light: 0x35708A, dark: 0x86C2D6),
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
    /*
     * L'accent est un choix, pas une constante.
     *
     * L'orange de la maquette reste le défaut ; c'est le seul endroit coloré
     * d'un écran par ailleurs noir et blanc, donc c'est le seul qu'on ait
     * envie de choisir. Il repeint du même coup l'alerte, qui est la même
     * encre dans ce thème.
     *
     * Mais PAS le négatif, et c'était un bug déguisé en règle. Le motif
     * écrit ici — « un accent orange avec un négatif rouge ferait deux
     * rouges voisins » — n'est vrai que de l'orange par défaut. Avec un
     * accent prune, toutes les dépenses de l'app sortaient en prune : la
     * couleur d'une perte suivait un réglage décoratif au lieu de dire une
     * perte, et le commentaire d'`editorialBase` juste en dessous affirmait
     * exactement le contraire sans jamais s'appliquer.
     *
     * Ce qu'on paie : avec l'accent orange, l'alerte et le négatif sont deux
     * rouges voisins. C'est le moindre des deux maux — un montant dont la
     * couleur ment se lit tous les jours, deux rouges proches se remarquent
     * une fois.
     */
    static var editorial: Palette {
        var base = editorialBase
        let ink = EdAccent.selected.tone
        base.accent = ink
        base.warn = ink

        /*
         * Le papier reste BLANC. Il a été teinté pendant quatre builds, et
         * c'était une béquille.
         *
         * Au moment où `negative` a cessé de suivre l'accent — une dépense
         * doit être rouge — il ne restait plus à l'accent qu'un bouton et
         * deux pastilles : en changer ne changeait rien de visible. Teinter
         * la feuille de 9 % a rendu le réglage sensible, au prix du geste
         * même d'Éditorial, qui est du noir sur du blanc PUR. Avec un accent
         * chocolat la page virait au beige, avec un bordeaux au rose.
         *
         * Le dégradé a réglé le problème pour de bon : l'accent tient
         * maintenant les huit encres, le héros et l'alerte. Il n'a plus
         * besoin de déteindre sur la feuille pour exister.
         */


        /*
         * Et, si on l'a demandé, les huit encres catégorielles en descendent.
         *
         * C'était le vrai manque. Le papier teinté se voit à peine, mais ce
         * qui FAIT la couleur d'un écran de Florin, ce sont les cartes de
         * comptes, les barres de répartition et les pastilles de légende —
         * toutes tirées de `series`. Tant que `series` restait la roue fixe
         * de huit teintes, choisir « Forêt » laissait un accueil orange,
         * magenta et ocre : le réglage n'avait aucun effet sur ce que l'œil
         * appelle la couleur de l'app.
         *
         * Donc l'éventail, pas la roue. Huit encres dans un arc de ±64°
         * autour de l'accent, chacune à une clarté propre : un vert choisi
         * donne huit verts-à-sarcelle-à-olive, un prune donne huit prunes.
         * On perd la séparabilité d'une roue complète — deux rangs voisins
         * sont plus proches qu'avant — et on l'accepte : dans ce thème la
         * couleur est décorative, chaque pastille est étiquetée, et le seul
         * endroit où trois encres se touchent sans texte (la barre de
         * répartition) prend les rangs 0, 2 et 4, écartés de 72° et de deux
         * crans de clarté.
         */
        /*
         * Les DEUX modes en descendent, et c'est la correction du build 586.
         *
         * « Palette » livrait la roue fixe : trente pastilles au-dessus d'un
         * mode qui les ignorait. Le mot ne voulait pourtant rien dire d'autre
         * qu'une palette de couleurs — des teintes qui vont ensemble parce
         * qu'elles sont parentes. Les deux modes font donc le même travail,
         * les huit encres des cartes, à partir du même accent ; ils diffèrent
         * par la PARENTÉ qu'ils en tirent : voisines pour l'une, une seule
         * diluée pour l'autre.
         */
        base.series = EdInks.selected == .gradient
            ? editorialRamp(from: ink)
            : editorialFan(from: ink)
        return base
    }

    /*
     * Palette : un ACCORD, comme en sort un générateur de palettes.
     *
     * Deux essais ont tourné la teinte de ±64° puis de ±24° autour de
     * l'accent, et le second était la bouillie annoncée : huit briques sur
     * un accent terracotta, qu'on ne distingue pas dans une légende. Des
     * couleurs voisines ne font pas une palette, elles font une tache.
     *
     * Ce que fait un color-palette : il prend les RELATIONS de la roue.
     * L'accent, ses deux analogues à ±30°, sa complémentaire à 180°, les
     * deux split-complémentaires à ±150°, les deux tétradiques à ±90°. Huit
     * positions qui couvrent le tour entier — donc huit couleurs qu'on
     * nomme différemment — et dont chacune a un nom de relation avec celle
     * que la personne a choisie. C'est ça, l'harmonie : pas la proximité.
     *
     * Ce qui les tient ensemble n'est donc pas la teinte, c'est le RESTE :
     * une même fenêtre de saturation et une bande de luminance étroite
     * (0,098 à 0,190 en clair, un rapport de deux là où la rampe en prend
     * dix). Même matière, même densité d'encre, huit teintes. C'est aussi
     * pourquoi la fenêtre de saturation monte ici : à bas niveau, un bleu
     * et un vert tournés au même endroit redeviennent deux gris.
     *
     * L'ordre des rangs n'est pas celui de la roue, et c'est voulu : deux
     * rangs consécutifs sont toujours à 60° au moins l'un de l'autre, parce
     * qu'une légende se lit de haut en bas et que deux lignes qui se
     * suivent sont les deux qu'on compare.
     */
    private static func editorialFan(from ink: Tone) -> [Tone] {
        // Relation à l'accent, saturation, luminance claire, luminance sombre.
        let chord: [(turn: Double, ink: Double, light: Double, dark: Double)] = [
            (0, 1.00, 0.120, 0.42),     // l'accent lui-même
            (150, 0.94, 0.165, 0.50),   // split-complémentaire
            (-150, 1.00, 0.098, 0.38),  // l'autre split-complémentaire
            (30, 0.90, 0.190, 0.54),    // analogue
            (180, 0.96, 0.140, 0.45),   // complémentaire
            (-30, 1.00, 0.112, 0.40),   // l'autre analogue
            (90, 0.92, 0.175, 0.52),    // tétradique
            (-90, 0.98, 0.150, 0.47),   // l'autre tétradique
        ]
        return chord.map { step in
            ink.spun(hue: step.turn, saturation: step.ink,
                     light: step.light, dark: step.dark, band: Tone.chordBand)
        }
    }

    /*
     * Dégradé : UNE encre, huit dilutions — du presque-noir au lavis.
     *
     * Rouge vers blanc, bleu vers
     * blanc : la teinte ne bouge pas d'un degré, seule la dilution change —
     * la luminance d'abord, de 0,04 à 0,41 en clair, soit un rapport de dix,
     * et la saturation avec elle, parce qu'une encre diluée perd sa chroma en
     * même temps que sa densité.
     *
     * Ce qu'on paie : deux rangs voisins sont plus proches qu'avec huit
     * teintes distinctes. C'est le prix d'un dégradé, et il est juste — chaque
     * carte porte son nom, et la barre de répartition prend les rangs 0, 2 et
     * 4, soit trois crans sur huit.
     */
    private static func editorialRamp(from ink: Tone) -> [Tone] {
        // Saturation, luminance en clair, luminance en sombre. La teinte,
        // elle, ne bouge pas d'un degré.
        let ramp: [(ink: Double, light: Double, dark: Double)] = [
            (1.00, 0.040, 0.100),
            (0.97, 0.065, 0.145),
            (0.94, 0.100, 0.200),
            (0.90, 0.145, 0.265),
            (0.84, 0.200, 0.340),
            (0.77, 0.265, 0.420),
            (0.69, 0.335, 0.510),
            (0.60, 0.410, 0.600),
        ]
        return ramp.map { step in
            ink.diluted(saturation: step.ink, light: step.light, dark: step.dark)
        }
    }

    private static let editorialBase = Palette(
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
        /*
         * Un gain est vert, une perte est rouge — y compris ici.
         *
         * La maquette ne voulait aucune couleur hors alerte, et tout un écran
         * de comptes en est ressorti en nuances de gris : des barres de
         * répartition qu'on ne distingue plus l'une de l'autre, et des
         * montants dont il fallait relire le signe. Le sens d'un chiffre
         * d'argent se lit à sa couleur avant de se lire à son signe ; c'est
         * la seule chose que ce thème rendait plus difficile qu'avant.
         */
        positive: Tone(light: 0x1F8B5F, dark: 0x5FD9A0),
        negative: Tone(light: 0xC4392F, dark: 0xF08072),
        warn: Tone(light: 0xB4690E, dark: 0xF0B357),
        series: [
            Tone(light: 0x1F6FB2, dark: 0x6FB8EE),
            Tone(light: 0x148A93, dark: 0x5CCBD3),
            Tone(light: 0x1F5C8C, dark: 0x6FA8DC),
            Tone(light: 0x2A7F6A, dark: 0x6FD4B4),
            Tone(light: 0x1E7FA0, dark: 0x63C3DE),
            Tone(light: 0x4E6B8F, dark: 0x97AECC),
            Tone(light: 0x146B74, dark: 0x8FDCE2),
            Tone(light: 0x6168C4, dark: 0xAEB3F7),
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
