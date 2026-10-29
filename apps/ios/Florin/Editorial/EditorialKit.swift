import SwiftUI

/*
 * Le langage visuel « Éditorial », et rien d'autre.
 *
 * Une maquette, lue littéralement : fond blanc pur ou noir pur, une seule
 * couleur — l'orange — réservée à ce qui alerte, et une hiérarchie qui vient
 * de la taille du texte et non d'une boîte de plus. Les filets séparent les
 * lignes ; les cartes ne servent que là où la maquette en pose une.
 *
 * Les couleurs ne sont pas écrites ici : ce sont les jetons de `Florin`, qui
 * résolvent la palette active. Éditorial est une palette ET une mise en page,
 * et c'est le choix du thème qui bascule les deux — l'ancienne app reste
 * entière sous les quatre autres thèmes.
 *
 * Tout est en points, jamais en pixels de maquette : la maquette est large de
 * 390 pt, un 16 Pro de 402, un Pro Max de 440. Les marges sont fixes et le
 * reste s'étire.
 */
enum Ed {
    /// La gouttière de la maquette.
    static let gutter: CGFloat = 24

    // MARK: Rayons
    static let smallCard: CGFloat = 18
    static let largeCard: CGFloat = 20
    static let inverseCard: CGFloat = 22
    static let sheet: CGFloat = 28

    /*
     * L'interligne du titre héros.
     *
     * La maquette demande 0,95 — plus serré que la boîte de ligne que SwiftUI
     * réserve. `lineSpacing` ne prend pas de valeur négative, donc un titre de
     * deux lignes s'empile à la main : une `Text` par ligne, et l'écart entre
     * elles ramené à ce qu'il manque.
     */
    static func heroLeading(_ size: CGFloat) -> CGFloat { -(size * 0.22) }

    /// Le resserrement des grandes tailles, en points plutôt qu'en pourcents.
    static func tracking(_ size: CGFloat, _ ratio: CGFloat) -> CGFloat { -size * ratio }
}

// MARK: - La pastille de contexte

/*
 * Ce qui tient lieu de titre d'écran.
 *
 * Elle se pose au-dessus du héros et dit de quoi il s'agit — « Patrimoine
 * net », « Plan · 2026 » — là où une barre de navigation aurait mis un titre
 * de 17 pt au milieu. Elle porte un trait, jamais un fond : un fond ferait
 * une étiquette, et une étiquette attire plus que le chiffre qu'elle annonce.
 */
struct EdPill: View {
    let text: String
    var tone: Color = Florin.text
    var filled = false

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(filled ? Florin.bg : tone)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                Capsule().fill(filled ? tone : .clear)
            )
            .overlay(
                Capsule().strokeBorder(filled ? .clear : tone.opacity(0.32), lineWidth: 1)
            )
    }
}

// MARK: - Le titre héros

/// Le sujet de l'écran, en très grand. Une ligne par retour à la ligne.
struct EdHero: View {
    let text: String
    var size: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: Ed.heroLeading(size)) {
            ForEach(Array(text.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                Text(String(line))
                    .font(.system(size: size, weight: .medium))
                    .tracking(Ed.tracking(size, 0.05))
            }
        }
        .foregroundStyle(Florin.text)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

/// Un montant, à la taille du héros mais sans son interligne : il tient sur
/// une ligne ou il se réduit, il ne se coupe pas en deux.
struct EdAmount: View {
    let text: String
    var size: CGFloat = 40
    var tone: Color = Florin.text
    /// Ce qui a changé, pour que les chiffres roulent. Facultatif : un montant
    /// qui ne bouge jamais n'a rien à animer.
    var value: Double?

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .medium))
            .monospacedDigit()
            .tracking(Ed.tracking(size, 0.045))
            .foregroundStyle(tone)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .modifier(EdNumericIfNeeded(value: value))
    }
}

/// `contentTransition` sans valeur à suivre ne transite pas ; avec une valeur
/// absente, il ne faut pas l'appliquer du tout. D'où ce passage obligé.
private struct EdNumericIfNeeded: ViewModifier {
    let value: Double?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let value {
            content.edNumeric(value)
        } else {
            content
        }
    }
}

/// Le titre d'une section, un cran sous le héros.
struct EdSection: View {
    let text: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(text)
                .font(.system(size: 34, weight: .medium))
                .tracking(Ed.tracking(34, 0.045))
                .foregroundStyle(Florin.text)
            if let trailing {
                Spacer(minLength: 8)
                Text(trailing)
                    .font(.system(size: 18))
                    .foregroundStyle(Florin.text2)
            }
        }
    }
}

// MARK: - Les lignes de liste

/// Le montant d'une ligne, dans sa pastille.
struct EdAmountPill: View {
    let text: String
    var tone: Color = Florin.text

    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .monospacedDigit()
            .foregroundStyle(tone)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .overlay(Capsule().strokeBorder(Florin.text.opacity(0.28), lineWidth: 1))
    }
}

/// Le filet qui sépare deux lignes. Jamais une carte par ligne.
struct EdRule: View {
    var body: some View {
        Rectangle()
            .fill(Florin.text.opacity(0.08))
            .frame(height: 1)
    }
}

// MARK: - Les cartes

/// La carte inverse : le chiffre-clé de l'écran, en négatif.
struct EdInverse<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Florin.text, in: RoundedRectangle(cornerRadius: Ed.inverseCard, style: .continuous))
            // Ce qui s'écrit dessus est le fond de l'écran : l'inverse exact,
            // et non un blanc en dur qui serait sale sur un thème crème.
            .environment(\.edInverse, true)
    }
}

/// Dans une carte inverse, l'encre et le fond s'échangent. Les vues filles
/// lisent ça plutôt que de recevoir deux couleurs en paramètre.
private struct EdInverseKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var edInverse: Bool {
        get { self[EdInverseKey.self] }
        set { self[EdInverseKey.self] = newValue }
    }
}

/// L'encre courante : celle de l'écran, ou son inverse dans une carte noire.
struct EdInk: View {
    @Environment(\.edInverse) private var inverse
    let text: String
    var size: CGFloat = 15
    var weight: Font.Weight = .regular
    var dim = false

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(
                inverse
                    ? (dim ? Florin.bg.opacity(0.68) : Florin.bg)
                    : (dim ? Florin.text2 : Florin.text)
            )
    }
}

// MARK: - La barre d'onglets

/// Les trois destinations de la maquette, dans l'ordre de la capsule.
///
/// Comptes et Analyse n'y sont plus : la maquette les atteint depuis Accueil
/// et depuis Plan. Ils restent des `TabRoute`, donc un lien profond y arrive
/// toujours — simplement aucune pastille ne s'allume, ce qui est exactement ce
/// qu'on veut d'un écran qu'on a poussé.
private let edTabs: [TabRoute] = [.overview, .plan, .activity]

/// Le pictogramme de la maquette, qui n'est pas celui de la barre d'origine :
/// une maison, une horloge, une liste. Trois traits, aucune couleur.
private func edSymbol(_ tab: TabRoute) -> String {
    switch tab {
    case .plan: return "clock"
    case .activity: return "list.bullet"
    default: return "house"
    }
}

/*
 * La capsule, posée au-dessus du contenu.
 *
 * Noire sur fond clair, claire sur fond noir : c'est l'encre du texte qui la
 * remplit, donc elle suit le thème sans qu'on ait à la peindre deux fois.
 * L'onglet actif est une pastille en négatif à l'intérieur — pas une teinte,
 * pas un point sous l'icône : l'inversion se voit de loin et ne coûte aucune
 * couleur au thème.
 */
struct EdTabBar: View {
    @Binding var selection: TabRoute
    let t: Strings
    let onAdd: () -> Void

    /// La pastille active est une seule vue qui se déplace, pas quatre qui
    /// s'allument : `matchedGeometryEffect` la fait glisser d'un onglet au
    /// suivant, ce qui dit le changement mieux qu'un clignotement.
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(edTabs) { tab in
                item(symbol: edSymbol(tab),
                     label: t(tab.titleKey.0, tab.titleKey.1),
                     active: tab == selection) {
                    withAnimation(EdMotion.spring) { selection = tab }
                }
            }
            item(symbol: "plus", label: t("v2.nav.add", "Ajouter"), active: false,
                 action: onAdd)
        }
        .padding(.horizontal, 8)
        .frame(height: 60)
        .background(Capsule().fill(Florin.text))
    }

    private func item(
        symbol: String, label: String, active: Bool, action: @escaping () -> Void
    ) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(active ? Florin.text : Florin.bg)
                .frame(width: 52, height: 44)
                .background {
                    if active {
                        Capsule()
                            .fill(Florin.bg)
                            .matchedGeometryEffect(id: "edTabPill", in: pill)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}

// MARK: - L'en-tête d'écran

/// Les deux boutons de 44 pt qui coiffent chaque écran, alignés sur la
/// gouttière par un débord de 10 pt — la cible reste pleine, le pictogramme
/// tombe sur la marge.
struct EdHeader<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            leading
            Spacer(minLength: 0)
            trailing
        }
        .frame(height: 44)
        .padding(.horizontal, -10)
    }
}

/// Un bouton d'en-tête : 44 pt de cible, un pictogramme au milieu.
struct EdIconButton: View {
    let symbol: String
    let label: String
    var action: () -> Void

    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Florin.text)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

// MARK: - Le mouvement

/*
 * Ce style bouge, et c'est la moitié du travail.
 *
 * Une direction éditoriale sans mouvement n'est qu'une feuille de style : ce
 * qui fait qu'un écran se lit, c'est l'ordre dans lequel il arrive. Trois
 * gestes seulement, pour qu'ils restent reconnaissables :
 *
 *   — un chiffre qui change roule, il ne saute pas (`edNumeric`) ;
 *   — ce qui entre par le bas entre en s'asseyant (`edEnter`) ;
 *   — ce qu'on touche s'enfonce d'un pour cent (`EdPress`).
 *
 * Aucun n'invente de durée : elles viennent des ressorts du système, donc
 * elles s'accordent aux transitions qu'iOS fait déjà par-dessus.
 */
enum EdMotion {
    /// Le ressort commun. Court, sans rebond : l'écran est sérieux.
    static let spring = Animation.spring(response: 0.34, dampingFraction: 0.86)
    /// Pour ce qui entre : un peu plus long, le temps qu'on le voie venir.
    static let enter = Animation.spring(response: 0.46, dampingFraction: 0.88)
}

extension View {
    /// Un montant qui se recalcule roule chiffre par chiffre au lieu de
    /// clignoter. `value` est ce qui déclenche : sans lui SwiftUI ne sait pas
    /// qu'il y a eu changement et garde la transition pour lui.
    func edNumeric(_ value: Double) -> some View {
        contentTransition(.numericText(value: value))
            .animation(EdMotion.spring, value: value)
    }

    /*
     * L'entrée en scène, au défilement.
     *
     * `scrollTransition` donne la position de la vue dans la fenêtre : on s'en
     * sert pour que ce qui arrive par le bas monte de douze points en
     * apparaissant. Rien ne bouge en haut — la vue déjà lue reste fixe, sinon
     * le défilement devient du flottement.
     */
    func edEnter() -> some View {
        scrollTransition(axis: .vertical) { view, phase in
            view
                .opacity(phase.isIdentity ? 1 : 0)
                .offset(y: phase.isIdentity ? 0 : 12)
        }
    }
}

/// Ce qu'on touche répond. Un pour cent suffit : plus, et l'écran a l'air
/// mou ; rien, et on doute d'avoir appuyé.
struct EdPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(EdMotion.spring, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == EdPress {
    static var edPress: EdPress { EdPress() }
}

// MARK: - La présentation des feuilles

extension View {
    /*
     * Ce qui fait qu'une feuille est éditoriale, posé du dehors.
     *
     * Les vingt-deux feuilles de l'app peignent déjà leur fond par `Backdrop`
     * et `florinGlass`, qui savent tous deux lire le thème — donc elles sont
     * à plat sans qu'on les ouvre. Restent le rayon du haut et la poignée,
     * qui sont des propriétés de la *présentation* et non du contenu : elles
     * s'appliquent depuis l'écran qui présente, ce qui évite d'aller les
     * recopier dans chaque feuille et d'en oublier une.
     *
     * 28 pt, comme la maquette. La poignée reste visible : ces feuilles se
     * ferment en les tirant vers le bas, et rien d'autre ne le dit.
     */
    func edSheet() -> some View {
        presentationCornerRadius(Ed.sheet)
            .presentationDragIndicator(.visible)
            .presentationBackground(Florin.bg)
    }
}

// MARK: - Les emojis, ou leur absence

/// Là où un emoji est posé en clair plutôt que dans une `Bubble`, ce passage
/// décide à sa place. Un point médian tient la colonne sans y mettre de
/// couleur : la ligne garde son alignement, l'écran garde sa palette.
enum EdSymbols {
    static func bullet(_ emoji: String?) -> String {
        if FlorinPalette.selected == .editorial { return "·" }
        return emoji ?? "•"
    }
}

/// La peau d'un pli : en négatif pour le second, au filet pour le premier.
/// La maquette alterne les deux afin qu'on les distingue d'un coup d'œil sans
/// avoir à les lire.
struct EdFoldSkin: ViewModifier {
    let inverse: Bool

    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Ed.smallCard, style: .continuous)
                    .fill(inverse ? Florin.text : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Ed.smallCard, style: .continuous)
                    .strokeBorder(
                        inverse ? .clear : Florin.text.opacity(0.18), lineWidth: 1
                    )
            )
            .environment(\.edInverse, inverse)
    }
}
