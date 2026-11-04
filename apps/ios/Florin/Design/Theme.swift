import SwiftUI

/// Les jetons de dessin, lus dans le thème actif.
///
/// Les valeurs vivent dans `Palette.swift`, une palette par thème ; ici il ne
/// reste que les noms.
///
/// Chaque jeton est CALCULÉ, et ce n'est pas un détail de style : un
/// `UIColor(dynamicProvider:)` garde la couleur qu'il a résolue pour un jeu de
/// traits donné. Tant que les jetons étaient des `static let`, une seule
/// instance servait tout le process — changer de thème ou d'accent ne
/// changeait plus rien à l'écran tant qu'on n'avait pas quitté et relancé
/// l'app, et forcer un rendu n'y pouvait rien puisque la couleur rendue était
/// la même instance déjà résolue. Une instance neuve par lecture n'a rien à
/// garder. Le coût est une allocation par couleur lue, ce que SwiftUI fait de
/// toute façon à chaque image.
///
/// Le jeu de noms reste celui de `packages/core/src/components/v2/theme/v2.css`
/// — une dérive entre le web et le natif se voit comme un téléphone qui ne
/// ressemble pas au navigateur.
enum Florin {
    /// La largeur au-delà de laquelle une colonne cesse de se lire.
    ///
    /// Un iPhone ordinaire est plus étroit que ça : la limite ne sert que sur
    /// les écrans qui ne sont pas un téléphone — un iPhone Duo ouvert — où
    /// une carte étirée sur toute la largeur éloigne son libellé de son
    /// montant au point qu'il faut traverser l'écran pour les rapprocher.
    static let readableWidth: CGFloat = 620

    // MARK: Surfaces
    static var bg: Color { token(\.bg) }
    static var surface: Color { token(\.surface) }
    static var surface2: Color { token(\.surface2) }
    static var surface3: Color { token(\.surface3) }

    // MARK: Text
    static var text: Color { token(\.text) }
    static var text2: Color { token(\.text2) }
    static var text3: Color { token(\.text3) }

    // MARK: Accent and semantics
    static var accent: Color { token(\.accent) }

    /*
     * La teinte des contrôles du système — bascules, sélecteurs, curseurs.
     *
     * C'est l'accent partout, sauf en éditorial où l'accent est réservé au
     * héros et aux alertes : une bascule orange y crierait au danger pour dire
     * « oui ». Un seul jeton plutôt qu'une bascule par écran, parce que la
     * dixième qu'on oublie est celle qu'on voit.
     */
    static var control: Color {
        FlorinPalette.selected == .editorial ? text : accent
    }
    /*
     * Ce qui s'écrit SUR l'accent, et qui n'est pas la même encre des deux
     * côtés.
     *
     * L'accent est pâle en sombre et soutenu en clair — c'est voulu, il doit
     * ressortir sur son fond. Mais un bouton rempli d'accent portait du noir
     * en dur : lisible sur le lavande du mode sombre, illisible sur l'indigo
     * du mode clair. Un jeton plutôt qu'un littéral, et les deux cas tombent
     * juste.
     */
    static var onAccent: Color { token(\.onAccent) }
    static var positive: Color { token(\.positive) }
    static var negative: Color { token(\.negative) }
    /// Needs a decision — not an error. Red already means "money left", so a
    /// review flag drawn in it reads as a loss rather than as a question.
    static var warn: Color { token(\.warn) }

    /// Categorical series — never the semantic green or red, so a spending bar
    /// can't read as a gain.
    ///
    /// Huit, dans tous les thèmes. Le rang vaut la même chose partout.
    static let seriesCount = 8

    static var series: [Color] { (0 ..< seriesCount).map { rank in
        Color(UIColor { traits in
            let tone = Palette.current.series[rank]
            return UIColor(hex: traits.userInterfaceStyle == .dark ? tone.dark : tone.light)
        })
    } }

    /// The Overview tab's ground, and the widget's.
    ///
    /// It lives here rather than beside its five siblings in `Backdrop` because
    /// the widget target needs it and cannot take `TabRoute` with it. One
    /// definition, two consumers: a widget that drifts from the screen it
    /// mirrors is the kind of thing nobody notices until it looks cheap.
    static var overviewTint: Color { ground(.overview) }

    static let cardRadius: CGFloat = 26
    static let rowRadius: CGFloat = 14
    static let gutter: CGFloat = 18

    /// Stable colour per label, matching the web `seriesVar` FNV-1a hash so a
    /// category is the same hue on both surfaces.
    static func seriesColor(for label: String) -> Color {
        series[seriesIndex(for: label)]
    }

    /*
     * Plusieurs libellés montrés ensemble, et aucun deux fois la même teinte.
     *
     * Une seule règle dans toute l'app : une chose colorée prend la teinte
     * que son nom possède dans les huit. Les comptes le faisaient déjà ; la
     * barre de répartition, elle, tapait des rangs en dur — 0, 2, 4 — donc
     * deux écrans tiraient dans la même palette par deux règles différentes
     * et l'ensemble se lisait comme deux palettes.
     *
     * La clé passée ici ne doit pas être un libellé traduit : « Liquidités »
     * et « Cash » ne tombent pas au même rang, et changer de langue
     * changerait les couleurs. Une clé stable, comme l'identifiant d'un
     * compte.
     */
    static func seriesColors(for keys: [String], avoiding reserved: Set<Int> = []) -> [Color] {
        var taken = reserved
        return keys.map { key in
            var slot = seriesIndex(for: key)
            var tries = 0
            while taken.contains(slot), tries < seriesCount {
                slot = (slot + 1) % seriesCount
                tries += 1
            }
            taken.insert(slot)
            return series[slot]
        }
    }

    /// Le rang que ce libellé tire dans `series`.
    ///
    /// Exposé à part parce qu'un appelant qui dessine PLUSIEURS libellés côte
    /// à côte doit pouvoir écarter deux rangs identiques : huit teintes et six
    /// comptes, c'est une collision plus d'une fois sur deux.
    static func seriesIndex(for label: String) -> Int {
        var hash: UInt32 = 0x811c_9dc5
        for unit in label.utf16 {
            hash ^= UInt32(unit)
            hash = hash &* 0x0100_0193
        }
        return Int(hash % UInt32(seriesCount))
    }

    /// Noir ou blanc, selon ce qui se lit sur cette teinte.
    ///
    /// Les teintes de `series` vont du jaune clair au bleu sombre : une encre
    /// fixe en perd la moitié. La luminance relative est résolue dans
    /// l'apparence où la couleur est dessinée, parce qu'une teinte dynamique
    /// n'a pas la même clarté en clair et en sombre.
    static func readable(on background: Color) -> Color {
        Color(UIColor { traits in
            var (red, green, blue, alpha): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            UIColor(background).resolvedColor(with: traits)
                .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            func linear(_ channel: CGFloat) -> CGFloat {
                channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
            return luminance > 0.42 ? UIColor(white: 0.04, alpha: 1) : .white
        })
    }

    /*
     * Two colours mixed, each resolved for the appearance it is drawn in.
     *
     * `Color.mix(with:by:)` is iOS 18 and the floor here is 17.4. Resolving
     * inside the trait callback is the part that matters: mixing the light
     * values once and handing the result to a dark screen is how a ramp ends
     * up glowing. Interpolated in sRGB where the web says oklab — over five
     * steps of one hue the difference is not visible, and the alternative is
     * a colour-space conversion nothing else here needs.
     */
    static func mix(_ base: Color, _ other: Color, _ amount: Double) -> Color {
        let ratio = CGFloat(min(max(amount, 0), 1))
        return Color(UIColor { traits in
            let from = UIColor(base).resolvedColor(with: traits)
            let to = UIColor(other).resolvedColor(with: traits)
            var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            from.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            to.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            return UIColor(
                red: r1 + (r2 - r1) * ratio,
                green: g1 + (g2 - g1) * ratio,
                blue: b1 + (b2 - b1) * ratio,
                alpha: a1 + (a2 - a1) * ratio
            )
        })
    }

    /// Un jeton : la teinte est relue dans le thème actif à chaque résolution.
    private static func token(_ path: KeyPath<Palette, Tone>) -> Color {
        Color(UIColor { traits in
            let tone = Palette.current[keyPath: path]
            return UIColor(hex: traits.userInterfaceStyle == .dark ? tone.dark : tone.light)
        })
    }

    /// Un fond coloré, par son rang. Voir `Palette.grounds`.
    static func ground(_ which: Palette.Ground) -> Color {
        Color(UIColor { traits in
            let tone = Palette.current.ground(which)
            return UIColor(hex: traits.userInterfaceStyle == .dark ? tone.dark : tone.light)
        })
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

/*
 * Le titre d'une section — et c'est le même mot dans les deux grammaires.
 *
 * Partout ailleurs : petites capitales grises, un sous-titre qui se tient à
 * l'écart. En éditorial : le titre EST la hiérarchie, écrit en bas de casse à
 * une taille qu'on lit de loin, parce que ce style ne met rien dans une boîte
 * et n'a que la typo pour dire ce qui compte.
 *
 * Une seule définition, donc tous les écrans de l'app suivent — y compris ceux
 * qu'on n'a pas réécrits.
 */
struct Eyebrow: View {
    let text: String
    var body: some View {
        if FlorinPalette.selected == .editorial {
            Text(text)
                .font(.system(size: 22, weight: .medium))
                .tracking(-0.5)
                .foregroundStyle(Florin.text)
                .lineLimit(2)
        } else {
            Text(text.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Florin.text3)
        }
    }
}

struct Pill: View {
    let text: String
    var tone: Color = Florin.text2
    var body: some View {
        let editorial = FlorinPalette.selected == .editorial
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(editorial ? Florin.text : tone)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            // Contour plutôt que lavis : la maquette ne pose aucun aplat
            // teinté, et dix pastilles lavées font dix cases sur une page qui
            // n'en veut pas.
            .background(editorial ? Color.clear : tone.opacity(0.12), in: Capsule())
            .overlay {
                if editorial {
                    Capsule().strokeBorder(Florin.text.opacity(0.28), lineWidth: 1)
                }
            }
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
    /// - Parameter tint: blended over the surface for a card that is *about*
    ///   something — the review queue, say. Tinting the rows instead gives two
    ///   nested shapes with two radii, and the inner one always looks wrong.
    func florinSurface(radius: CGFloat = Florin.cardRadius, tint: Color? = nil) -> some View {
        /*
         * En éditorial, une carte est un trait, pas un relief.
         *
         * C'est la seule définition de « carte » dans l'app : la tordre ici
         * repeint les lignes d'un formulaire, les blocs de réglage et les
         * cartons de l'accueil d'un coup, sans ouvrir un seul des écrans qui
         * les posent. L'ombre portée et la surface grise sont justement ce que
         * la maquette refuse — elle hiérarchise par la typo, pas par le relief.
         */
        let editorial = FlorinPalette.selected == .editorial
        let shape = RoundedRectangle(
            cornerRadius: editorial ? 18 : radius, style: .continuous
        )
        return self
            // Clip first: rows paint their own backgrounds (the amber wash on a
            // "à vérifier" line), and without this they run square into the
            // card's rounded corners.
            .clipShape(shape)
            .background(editorial ? Color.clear : Florin.surface, in: shape)
            .background(tint ?? .clear, in: shape)
            .overlay(shape.strokeBorder(
                Florin.text.opacity(editorial ? 0.14 : 0.06), lineWidth: editorial ? 1 : 0.5
            ))
            .shadow(
                color: .black.opacity(editorial ? 0 : 0.10),
                radius: editorial ? 0 : 8, x: 0, y: editorial ? 0 : 3
            )
    }
}
