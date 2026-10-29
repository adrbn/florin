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
    /// Quand le texte doit tenir sur une ligne quoi qu'il arrive : il se réduit
    /// plutôt que de se couper. « Bon après-midi Adrien » est deux fois plus
    /// long que « Bonjour », et un salut coupé en deux n'est plus un salut.
    var oneLine = false

    var body: some View {
        VStack(alignment: .leading, spacing: Ed.heroLeading(size)) {
            ForEach(Array(text.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                Text(String(line))
                    .font(.system(size: size, weight: .medium))
                    .tracking(Ed.tracking(size, 0.05))
                    .lineLimit(oneLine ? 1 : nil)
                    .minimumScaleFactor(oneLine ? 0.46 : 1)
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
private var edTabs: [TabRoute] { edTabOrder }

/// Le pictogramme de la maquette, qui n'est pas celui de la barre d'origine :
/// une maison, une horloge, une liste. Trois traits, aucune couleur.
private func edSymbol(_ tab: TabRoute) -> String {
    switch tab {
    case .accounts: return "rectangle.stack"
    case .plan: return "clock"
    case .activity: return "list.bullet"
    // Sans ce cas, Analyse tombait sur le `default` et portait la maison de
    // l'accueil : deux onglets, la même icône.
    case .analysis: return "chart.xyaxis.line"
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
                    jump(to: tab)
                }
            }
            item(symbol: "plus", label: t("v2.nav.add", "Ajouter"), active: false,
                 action: onAdd)
        }
        .padding(.horizontal, 8)
        .frame(height: 60)
        /*
         * Un aplat, et pas du verre.
         *
         * Le verre a été essayé, teinté de la même encre et `.interactive()`
         * pour qu'il se tienne sous le doigt. Il coûtait deux choses :
         * `.interactive()` installe sa propre gestion du toucher sur le
         * conteneur et avale le clic avant les boutons — c'est la raison déjà
         * écrite dans `FloatingTabBar` — et la présence d'un verre fait poser
         * à iOS 26 son effet de bord sur les listes, ce bandeau opaque en
         * haut d'écran derrière lequel le contenu disparaît au lieu de se
         * fondre. Deux régressions pour une matière : l'aplat reste.
         */
        .background(Capsule().fill(Florin.text))
    }

    /*
     * Un onglet voisin glisse, un onglet lointain saute.
     *
     * En style page, changer de sélection fait défiler jusque-là — et donc
     * traverser ce qu'il y a entre : d'Accueil à Activité on voyait passer
     * Comptes et Plan en un clin d'œil, ce qui ressemble à un bug plutôt qu'à
     * un trajet. Un pas de côté garde son glissement, parce qu'il dit la même
     * chose qu'un balayage ; au-delà, la barre se comporte comme une barre
     * d'onglets, qui n'a jamais rien fait défiler.
     */
    private func jump(to tab: TabRoute) {
        let from = edTabOrder.firstIndex(of: selection) ?? 0
        let to = edTabOrder.firstIndex(of: tab) ?? 0
        if abs(to - from) == 1 {
            withAnimation(EdMotion.spring) { selection = tab }
        } else {
            // `Transaction` tout court, ici, c'est une opération bancaire.
            var instant = SwiftUI.Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { selection = tab }
        }
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
                // Six items — cinq onglets et « Ajouter » — dans la largeur
                // d'un téléphone : 52 pt débordaient, 46 tiennent, et la
                // cible reste à 44 pt de haut.
                .frame(width: 46, height: 44)
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
    /// Il tourne pendant qu'il travaille. Un aller-retour bancaire prend des
    /// secondes, et éteindre le bouton se lit « indisponible », pas « occupé ».
    var spinning = false
    var action: () -> Void

    @State private var angle: Double = 0

    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Florin.text)
                .rotationEffect(.degrees(angle))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .onChange(of: spinning) { _, now in
            if now {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            } else {
                withAnimation(EdMotion.spring) { angle = 0 }
            }
        }
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

/*
 * Ce qu'on touche répond — par la taille, jamais par l'opacité.
 *
 * L'opacité marchait tant que rien ne se chevauchait. Dans la pile de cartes
 * de l'accueil, appuyer sur une carte la rendait translucide et laissait voir
 * celle de dessous au travers : un bouton pressé doit s'enfoncer, pas
 * s'effacer. Deux pour cent de retrait disent la même chose sans trahir ce
 * qu'il y a derrière.
 */
struct EdPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
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

/*
 * Le salut de l'accueil.
 *
 * Trois clés existaient dans `Strings.json` depuis toujours — matin, après-midi,
 * soir — et aucun écran ne les lisait : l'accueil disait « Bonjour » à minuit.
 * L'heure décide du mot, le réglage décide s'il y a un prénom derrière, et un
 * prénom vide rend exactement la phrase d'avant.
 */
enum Greeting {
    static let key = "florin.firstName"

    static func line(_ t: Strings, name: String, at date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let hello: String
        switch hour {
        case 5 ..< 12: hello = t("v2.overview.morning", "Bonjour")
        case 12 ..< 18: hello = t("v2.overview.afternoon", "Bon après-midi")
        default: hello = t("v2.overview.evening", "Bonsoir")
        }
        let who = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return who.isEmpty ? hello : "\(hello) \(who)"
    }
}

/// Le pictogramme d'une ligne de formulaire — et rien du tout en éditorial,
/// où six taches orange en colonne ne font que redire six mots déjà écrits à
/// côté. Une seule définition, pour que les cinq lignes restent d'accord.
struct RowIcon: View {
    let symbol: String
    init(_ symbol: String) { self.symbol = symbol }

    var body: some View {
        if FlorinPalette.selected != .editorial {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Florin.accent.opacity(0.85))
                .frame(width: 22)
        }
    }
}

extension EdSymbols {
    /// « 🍔 Courses », ou « Courses » tout court en éditorial — où l'émoji
    /// devant un nom de catégorie fait un confetti au milieu d'une page qui
    /// n'a que du noir, du blanc et un orange.
    static func label(_ emoji: String?, _ name: String) -> String {
        guard FlorinPalette.selected != .editorial, let emoji else { return name }
        return "\(emoji) \(name)"
    }
}

/*
 * Passer d'un onglet à l'autre au pouce.
 *
 * `simultaneousGesture` et non `highPriorityGesture` : la page doit continuer
 * de défiler verticalement pendant que le geste est observé, sinon le swipe
 * confisque le défilement, qui est le geste cent fois plus fréquent. D'où les
 * deux gardes — soixante points parcourus, et deux fois plus en largeur qu'en
 * hauteur : un défilement légèrement oblique ne change pas d'écran.
 *
 * Rien ne se passe si l'onglet courant n'est pas dans la liste (on est arrivé
 * sur un écran qui n'a pas de place dans la barre) ni aux deux bouts : la
 * liste ne boucle pas, parce qu'un geste qui ramène au début après le dernier
 * onglet fait perdre où l'on est.
 */
extension View {
    func edSwipe<Value: Hashable>(
        _ order: [Value], selection: Binding<Value>, enabled: Bool = true
    ) -> some View {
        simultaneousGesture(
            // Quarante points, pas vingt-quatre : en dessous, un défilement
            // vertical un peu oblique rentrait dans la fourchette et l'écran
            // partait de côté à la fin du geste.
            DragGesture(minimumDistance: 40)
                .onEnded { move in
                    // Le doigt qui suit la courbe ne demande pas de page.
                    guard enabled, !EdGesture.shared.scrubbing else { return }
                    let dx = move.translation.width
                    let dy = move.translation.height
                    guard abs(dx) > 60, abs(dx) > abs(dy) * 2,
                          let here = order.firstIndex(of: selection.wrappedValue)
                    else { return }
                    let next = dx < 0 ? here + 1 : here - 1
                    guard order.indices.contains(next) else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(EdMotion.spring) { selection.wrappedValue = order[next] }
                }
        )
    }
}

/// L'ordre des onglets de la barre éditoriale, pour que le swipe et la barre
/// soient d'accord sur « le suivant » — une seule liste, pas deux à tenir
/// synchronisées.
/*
 * L'ordre de la capsule EST l'ordre des pages.
 *
 * Ce sont deux listes différentes dans le code — celle-ci et l'ordre de
 * déclaration du `TabView` — et tant qu'elles divergeaient, un onglet posé à
 * droite dans la capsule entrait par la gauche : Activité → Plan glissait à
 * l'envers parce que Plan était deuxième ici et quatrième là-bas.
 *
 * Comptes reprend sa place. Il était poussé depuis les cartes de l'accueil,
 * et restait pourtant une page du défilement : on le voyait passer en allant
 * ailleurs, sans jamais pouvoir y aller. Une page qu'on traverse est une page
 * qui mérite son onglet.
 */
let edTabOrder: [TabRoute] = [.overview, .accounts, .plan, .activity, .analysis]

/*
 * Le doigt est pris ailleurs.
 *
 * Pendant qu'on suit la courbe, le geste est horizontal par nature : le swipe
 * d'onglet le lisait comme une demande de changer de page et l'écran partait
 * sous le doigt à la fin du relevé. Un seul drapeau, posé par le graphique et
 * lu par le swipe — c'est la seule chose que ces deux-là ont à se dire.
 */
@MainActor
final class EdGesture: ObservableObject {
    static let shared = EdGesture()
    @Published var scrubbing = false
}

/// Le style page, mais seulement en éditorial : les deux branches gardent la
/// même vue, c'est le conteneur qui change de façon de la présenter.
struct EdPaging: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.tabViewStyle(.page(indexDisplayMode: .never))
        } else {
            content
        }
    }
}


/// L'ancre du haut d'un écran éditorial. `EdRewind` y revient.
let edTopAnchor = "edTop"

/// Revenir sur un onglet le reprend au début — voir `ChromeState.left`.
struct EdRewind: ViewModifier {
    let tab: TabRoute
    @ObservedObject var chrome: ChromeState

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content.onChange(of: chrome.left) { _, left in
                guard left == tab else { return }
                proxy.scrollTo(edTopAnchor, anchor: .top)
            }
        }
    }
}

extension View {
    func edRewind(_ tab: TabRoute, chrome: ChromeState) -> some View {
        modifier(EdRewind(tab: tab, chrome: chrome))
    }
}


/*
 * Le fondu des bords, doux — en haut comme en bas.
 *
 * iOS 26 pose un « effet de bord » sur les défilements. En `.hard` c'est un
 * aplat net : un bloc de la couleur du fond derrière lequel le contenu
 * disparaît d'un coup. En `.soft`, c'est un fondu progressif — exactement ce
 * qu'on veut ici, et ce qui donne, avec le décalage de `edEnter()`, la
 * sensation que les lignes sortent de la vue au lieu d'être coupées.
 *
 * Il a d'abord été posé seulement en haut, puis retiré tout court. Les deux
 * étaient des erreurs : il le faut aux deux bords, et doux.
 */
/// Le même bord haut que partout ailleurs.
///
/// Éditorial avait l'effet du système, les écrans classiques avaient le
/// nôtre : deux fondus différents selon l'onglet, et celui du système ne
/// commence pas au bord de l'écran mais sous la zone sûre. Un seul fondu,
/// le nôtre, qui part du bord. Le bas est déjà tenu par `BottomScrim`,
/// posé une fois pour toute l'app.
struct EdPlainEdges: ViewModifier {
    func body(content: Content) -> some View {
        content.modifier(SoftScrollEdge())
    }
}

extension View {
    func edPlainEdges() -> some View { modifier(EdPlainEdges()) }
}
