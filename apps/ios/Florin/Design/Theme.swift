import SwiftUI

/// Les jetons de dessin, lus dans le thème actif.
///
/// Les valeurs vivent dans `Palette.swift`, une palette par thème ; ici il ne
/// reste que les noms. Chaque jeton est une couleur dynamique dont la fonction
/// de résolution relit `Palette.current` au moment du rendu : changer de thème
/// n'a donc qu'à forcer un nouveau rendu, pas à reconstruire la palette.
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
    static let bg = token(\.bg)
    static let surface = token(\.surface)
    static let surface2 = token(\.surface2)
    static let surface3 = token(\.surface3)

    // MARK: Text
    static let text = token(\.text)
    static let text2 = token(\.text2)
    static let text3 = token(\.text3)

    // MARK: Accent and semantics
    static let accent = token(\.accent)

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
    static let onAccent = token(\.onAccent)
    static let positive = token(\.positive)
    static let negative = token(\.negative)
    /// Needs a decision — not an error. Red already means "money left", so a
    /// review flag drawn in it reads as a loss rather than as a question.
    static let warn = token(\.warn)

    /// Categorical series — never the semantic green or red, so a spending bar
    /// can't read as a gain.
    ///
    /// Huit, dans tous les thèmes : la taille est fixe pour que les couleurs
    /// restent des `let` liés à leur rang plutôt que reconstruits à chaque
    /// lecture.
    static let series: [Color] = (0 ..< 8).map { rank in
        Color(UIColor { traits in
            let tone = Palette.current.series[rank]
            return UIColor(hex: traits.userInterfaceStyle == .dark ? tone.dark : tone.light)
        })
    }

    /// The Overview tab's ground, and the widget's.
    ///
    /// It lives here rather than beside its five siblings in `Backdrop` because
    /// the widget target needs it and cannot take `TabRoute` with it. One
    /// definition, two consumers: a widget that drifts from the screen it
    /// mirrors is the kind of thing nobody notices until it looks cheap.
    static let overviewTint = ground(.overview)

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
