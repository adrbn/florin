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

    /*
     * Un seul pictogramme pour les réglages, et toujours à droite.
     *
     * Trois boutons différents ouvraient la même page : trois barres sur
     * l'accueil et l'analyse, une tête dans un rond sur le plan et
     * l'activité. Les trois barres annoncent un menu de navigation, la tête
     * un compte utilisateur : aucun des deux ne dit « réglages ». Un
     * engrenage le dit, et le dernier rond à droite est le même endroit sur
     * les cinq onglets.
     */
    static let settingsSymbol = "gearshape"

    /// Le resserrement des grandes tailles, en points plutôt qu'en pourcents.
    static func tracking(_ size: CGFloat, _ ratio: CGFloat) -> CGFloat { -size * ratio }

    /// L'espace fine que tout titre resserré porte en queue, pour que l'encre
    /// du dernier glyphe tienne dans sa propre ligne — voir `EdHero`.
    static let inkRoom = "\u{2009}" 
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
    /*
     * La taille d'une étiquette, et celle d'un bouton.
     *
     * Une pastille qui NOMME (« Plan 2026 ») se lit à 12 pt et ne se touche
     * pas. Une pastille qui CHANGE l'écran se touche, donc elle a besoin de
     * ses 44 pt de cible et d'un texte qu'on lit en passant le pouce.
     * Mêmes bords, deux tailles, un seul composant.
     */
    var large = false

    var body: some View {
        Text(text)
            .font(.system(size: large ? 15 : 12, weight: large ? .semibold : .regular))
            .foregroundStyle(filled ? Florin.bg : tone)
            .lineLimit(1)
            .padding(.horizontal, large ? 15 : 10)
            .frame(height: large ? 36 : 24)
            .background(
                Capsule().fill(filled ? tone : .clear)
            )
            .overlay(
                Capsule().strokeBorder(filled ? .clear : tone.opacity(0.32), lineWidth: 1)
            )
            .edEnter()
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
                Text(String(line) + Ed.inkRoom)
                    .font(.system(size: size, weight: .medium))
                    /*
                     * Une espace fine finale, et rien d'autre ne marche.
                     *
                     * MESURÉ, après quatre corrections manquées : à 64 pt,
                     * `kerning(-3,2)` ramène l'avance de « Today » de 175,7 à
                     * 151,6 pt alors que le tracé du « y » va jusqu'à 154,0 —
                     * l'encre dépasse de 2,44 pt, et c'est le bras droit du
                     * « y » qu'on voit coupé net à la verticale.
                     *
                     * Ce qui coupe est la LIGNE de texte, pas le cadre : ni
                     * un cadre élargi à toute la colonne, ni une marge
                     * `trailing` de la valeur du cran rendu, n'y ont rien
                     * changé — ils agrandissent la vue autour, pas la ligne
                     * qui rend les glyphes. Une espace fine, elle, entre dans
                     * la ligne : l'avance passe à 155,1 pt et l'encre rentre
                     * (−1,06). Une espace d'écart serait du vide visible,
                     * une espace ultra-fine ne suffit pas (+2,18).
                     */
                    .kerning(Ed.tracking(size, 0.05))
                    .lineLimit(oneLine ? 1 : nil)
                    .minimumScaleFactor(oneLine ? 0.46 : 1)
            }
        }
        .foregroundStyle(Florin.text)
        .fixedSize(horizontal: false, vertical: true)
        /*
         * Le cadre prend la colonne, et c'est ÇA qui arrête le rognage.
         *
         * Une pile alignée à gauche se taille sur son plus large enfant : ici
         * la largeur que le texte ANNONCE. Or l'encre déborde un peu de cette
         * largeur — la queue du « y » de « Today » passe sous l'avance du
         * glyphe — et `edEnter()` pose par-dessus un calque de composition,
         * qui borne au cadre ce qui en déborde. D'où la coupure verticale
         * nette au ras de la dernière lettre.
         *
         * Ni `tracking`, ni `kerning`, ni une marge n'y pouvaient rien : une
         * marge `trailing` retire autant de place proposée au texte qu'elle en
         * ajoute au cadre. Le cadre prend donc toute la largeur disponible, où
         * le débord a largement de quoi se poser.
         */
        .frame(maxWidth: .infinity, alignment: .leading)
        .edEnter()
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
        PrivateText(text)
            .font(.system(size: size, weight: .medium))
            .monospacedDigit()
            .kerning(Ed.tracking(size, 0.045))
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

extension View {
    /// `edEnter`, mais seulement quand c'est l'éditorial qui regarde : les
    /// quatre autres thèmes n'ont pas ce mouvement.
    @ViewBuilder
    func edEnterIfEditorial() -> some View {
        if FlorinPalette.selected == .editorial { edEnter() } else { self }
    }
}

/// Le titre d'une section, un cran sous le héros.
struct EdSection: View {
    let text: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(text + Ed.inkRoom)
                .font(.system(size: 34, weight: .medium))
                // Voir `EdHero` : le cran retiré après le dernier caractère
                // est rendu en marge, sinon l'encre du « y » passe sous le
                // bord du calque de composition.
                .kerning(Ed.tracking(34, 0.045))
                .foregroundStyle(Florin.text)
            if let trailing {
                Spacer(minLength: 8)
                PrivateText(trailing)
                    .font(.system(size: 18))
                    .monospacedDigit()
                    .foregroundStyle(Florin.text2)
            } else {
                // Voir `EdHero` : sans montant à droite, la rangée se taillait
                // sur l'encre du titre et `edEnter()` rognait ce qui dépasse.
                Spacer(minLength: 0)
            }
        }
        .edEnter()
    }
}

// MARK: - Les lignes de liste

/// Le montant d'une ligne, dans sa pastille.
struct EdAmountPill: View {
    let text: String
    var tone: Color = Florin.text

    var body: some View {
        PrivateText(text)
            .font(.system(size: 14))
            .monospacedDigit()
            .foregroundStyle(tone)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 28)
            // Le filet suit l'encre : une pastille rouge cerclée de gris se
            // lit comme un rouge posé par erreur.
            .overlay(Capsule().strokeBorder(
                tone == Florin.text ? Florin.text.opacity(0.28) : tone.opacity(0.42),
                lineWidth: 1
            ))
            .edEnter()
    }
}

/*
 * Un volet d'attente : ce qui n'est pas encore passé, replié.
 *
 * Deux usages, le même volet : l'onglet Activité et la fiche d'un compte
 * posent tous les deux « 3 à venir » et « 2 en plusieurs fois ». La fiche
 * portait les volets d'Obsidienne — un pictogramme dans un rond, une carte
 * grise, une légende à 11 pt — sous la typo éditoriale, parce que la liste
 * d'opérations est un composant partagé qui ne connaissait pas la maquette.
 *
 * Le second est en NÉGATIF. Deux volets au même filet, l'un sous l'autre, se
 * lisent comme un seul bloc coupé en deux ; l'encre pleine dit que c'est une
 * autre question — voir `EdFoldSkin`, qui tient les deux visages.
 */
struct EdFold<Content: View>: View {
    let title: String
    let total: Double
    let locale: String
    let currency: String
    @Binding var open: Bool
    let inverse: Bool
    @ViewBuilder var content: Content

    /// Mesurée sur le contenu lui-même : un volet dont le nombre de lignes
    /// change n'a pas à être renseigné deux fois.
    @State private var height: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(EdMotion.spring) { open.toggle() }
            } label: {
                HStack(spacing: 10) {
                    EdInk(text: title, size: 15)
                    Spacer(minLength: 8)
                    EdInk(
                        text: Money.string(
                            total, locale: locale, currency: currency,
                            decimals: false, signed: true
                        ),
                        size: 17, weight: .medium, money: true
                    )
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(inverse ? Florin.bg.opacity(0.7) : Florin.text2)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.edPress)
            .modifier(EdFoldSkin(inverse: inverse))

            /*
             * Un volet se replie ; il ne s'efface pas.
             *
             * `if open { content.transition(.opacity) }` retire la vue de
             * l'arbre : le contenu fondait sur place en gardant sa hauteur,
             * et la liste dessous sautait d'un bloc à la fin du fondu — on
             * voyait « Hier » et toute la suite remonter d'un coup, sans
             * rapport avec le geste qui venait d'être fait. Une transition
             * d'opacité ne peut pas faire autrement : elle n'a pas d'avis sur
             * la mise en page.
             *
             * Le contenu reste donc là, et c'est sa HAUTEUR qu'on anime,
             * de zéro à celle qu'il occupe. Ce chiffre-là, l'animation sait
             * l'interpoler, donc la liste dessous monte et descend avec le
             * volet. Il se mesure pendant que le volet est ouvert et ne coûte
             * rien de plus : ces volets tiennent quelques lignes, pas une
             * liste paginée.
             *
             * `allowsHitTesting` parce qu'un contenu rogné reste touchable :
             * sans ça, replier un volet laissait ses boutons sous le doigt.
             */
            /*
             * Un contenu de `@ViewBuilder` est un GROUPE, pas une vue.
             *
             * Les modificateurs posés dessus s'appliquent alors à chacune de
             * ses vues : la hauteur du volet entier se retrouvait sur CHAQUE
             * échéancier, et la marge du haut entre chacun — deux cents
             * points de blanc entre deux lignes. Un `VStack` autour en fait
             * une vue unique, et les modificateurs portent enfin sur le bloc.
             */
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.top, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                /*
                 * Mesurer une vue dont on fixe la hauteur est une boucle.
                 *
                 * Sans ce `fixedSize`, le contenu acceptait la hauteur qu'on
                 * venait de lui poser et s'étirait pour la remplir — ses
                 * lignes s'écartaient les unes des autres —, la mesure
                 * suivante rendait donc un chiffre plus grand, qu'on reposait
                 * aussitôt. Le volet grandissait jusqu'à ce que ça se calme,
                 * avec deux cents points de blanc entre deux échéanciers.
                 *
                 * Il garde maintenant sa hauteur idéale quelle que soit la
                 * proposition : la mesure ne dépend plus de ce qu'on en fait.
                 */
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: EdFoldHeight.self, value: geo.size.height
                        )
                    }
                )
                .frame(height: open ? height : 0, alignment: .top)
                .clipped()
                .opacity(open ? 1 : 0)
                .allowsHitTesting(open)
                .accessibilityHidden(!open)
                .onPreferenceChange(EdFoldHeight.self) { measured in
                    if measured > 0 { height = measured }
                }
        }
    }
}

/// La hauteur que prend le contenu d'un volet, remontée pour pouvoir
/// l'animer. Voir `EdFold`.
private struct EdFoldHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Le filet qui sépare deux lignes. Jamais une carte par ligne.
struct EdRule: View {
    var body: some View {
        Rectangle()
            .fill(Florin.text.opacity(0.08))
            .frame(height: 1)
            .edEnter()
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
    /// Un chiffre, donc quelque chose que l'œil barré doit couvrir.
    var money = false

    var body: some View {
        Group {
            if money { PrivateText(text) } else { Text(text) }
        }
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
/// une maison, un calendrier, une horloge. Trois traits, aucune couleur.
///
/// Le calendrier va au Plan, qui parle de mois à venir ; l'horloge à
/// l'Activité, qui est un historique. L'inverse se lisait de travers.
/// `calendar` et `clock` sont dessinés dans un carré plus serré que la maison
/// ou la pile : au même corps ils paraissent en retrait de leurs voisins, donc
/// ils en prennent deux points de plus.
private func edSymbolSize(_ symbol: String) -> CGFloat {
    symbol == "calendar" || symbol == "clock" ? 20 : 18
}

private func edSymbol(_ tab: TabRoute) -> String {
    switch tab {
    case .accounts: return "rectangle.stack"
    case .plan: return "calendar"
    case .activity: return "clock"
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
            edOpen {
                UISelectionFeedbackGenerator().selectionChanged()
                action()
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: edSymbolSize(symbol), weight: .medium))
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
    /// `.top` quand la gauche tient sur plusieurs lignes : les boutons restent
    /// sur la première, et la rangée grandit sous eux.
    var alignment: VerticalAlignment = .center
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: alignment) {
            leading
            Spacer(minLength: 0)
            trailing
        }
        .frame(minHeight: 44)
        .padding(.horizontal, -10)
        .edEnter()
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
            edOpen {
                UISelectionFeedbackGenerator().selectionChanged()
                action()
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Florin.text)
                .rotationEffect(.degrees(angle))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .edEnter()
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
        modifier(EdEnter())
    }
}

/*
 * L'entrée en scène, et une seule par branche.
 *
 * Elle est posée à la fois dans les briques — un titre, une pastille, un
 * symbole de l'en-tête — et sur les blocs qui les contiennent, parce que les
 * deux doivent fondre selon l'écran qu'on regarde. Empilées, elles se
 * multiplient : deux fois douze points de décalage et une opacité au carré,
 * ce qui donne un bloc qui part trop vite et trop loin.
 *
 * La plus extérieure gagne et le dit à sa descendance. Une brique posée seule
 * fond donc pour elle-même ; la même brique dans une carte fond avec la carte.
 */
private struct EdEnterApplied: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var edEnterApplied: Bool {
        get { self[EdEnterApplied.self] }
        set { self[EdEnterApplied.self] = newValue }
    }
}

struct EdEnter: ViewModifier {
    @Environment(\.edEnterApplied) private var applied
    /*
     * Rien ne fond tant que la page n'a pas sa géométrie.
     *
     * `scrollTransition` demande sa phase avant que le défilement ait mesuré
     * ses bornes : au premier rendu d'un onglet, tout ce qui est pourtant à
     * l'écran se voit attribuer la phase d'entrée — douze points plus bas,
     * transparent — puis saute à sa place au passage suivant. C'est le
     * sursaut qu'on voit deux dixièmes après avoir changé d'onglet, et le
     * sens le prouve : ça REMONTE de douze points, exactement l'offset
     * d'entrée.
     *
     * Armé après coup, l'effet ne vaut plus que pour ce qui arrive vraiment
     * par le bord, ce qui est tout son objet.
     */
    @State private var armed = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if applied {
            content
        } else {
            content
                .scrollTransition(axis: .vertical) { view, phase in
                    view
                        .opacity(!armed || phase.isIdentity ? 1 : 0)
                        .offset(y: !armed || phase.isIdentity ? 0 : 12)
                }
                .environment(\.edEnterApplied, true)
                .task {
                    try? await Task.sleep(for: .milliseconds(150))
                    armed = true
                }
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
/// Ce qu'on touche s'enfonce d'un pour cent.
///
/// Rien de plus : un `DragGesture` maison sur chaque bouton pour refuser les
/// glissements avait pris le pas sur le défilement des listes. Le refus se
/// fait là où il coûte zéro — dans l'action, qui lit le drapeau partagé que
/// `edSwipeBack` lève déjà. Voir `EdGesture`.
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
    /*
     * En éditorial, une catégorie n'a pas de vignette — et surtout pas un
     * point à la place.
     *
     * Le point médian était là pour tenir la colonne où les autres thèmes
     * posent un emoji. Mais un glyphe mis pour occuper une place se lit comme
     * un glyphe RATÉ : dans le sélecteur de catégories, soixante lignes
     * commençaient par « · » et on cherchait l'icône qui n'avait pas chargé.
     * La colonne reste (les noms s'alignent), elle est juste vide.
     */
    static func bullet(_ emoji: String?) -> String {
        if FlorinPalette.selected == .editorial { return "" }
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
        /*
         * Le prénom à la ligne.
         *
         * « Bon après-midi Adrien » sur une seule ligne de 64 pt fait deux
         * fois la largeur de l'écran : `minimumScaleFactor` le ramenait à
         * 0,46, c'est-à-dire 29 pt, et un titre réduit de moitié qui touche
         * les deux bords ne ressemble plus à un titre — il a l'air centré.
         * Sur deux lignes il garde son corps, et l'interligne négatif du
         * héros fait que la seconde ne coûte pas une ligne entière.
         */
        return who.isEmpty ? hello : "\(hello)\n\(who)"
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
    /*
     * `nested` est un parametre, et il l'est pour une raison de cout.
     *
     * Il a d'abord ete passe par l'environnement — le pere ecrivait, le fils
     * lisait. Sauf que le pere ici enveloppe le `TabView` entier : ecrire dans
     * l'environnement a cet endroit le reecrit a chaque changement de
     * selection, et l'arbre invalide dessous est celui des cinq pages. Changer
     * d'onglet prenait une a deux secondes.
     *
     * Il n'y a que deux `edSwipe` imbriques dans toute l'app ; celui du dedans
     * peut le dire lui-meme en un mot, et ca ne coute rien.
     */
    func edSwipe<Value: Hashable>(
        _ order: [Value], selection: Binding<Value>, enabled: Bool = true
    ) -> some View {
        modifier(EdSwipe(order: order, selection: selection, enabled: enabled))
    }

    /*
     * Des sous-onglets qui repondent au balayage, sans poser de geste.
     *
     * Voir `EdGesture.inner` : poser ici un second `DragGesture` revenait a
     * couper le defilement vertical de l'ecran, parce qu'il serait pose a
     * l'interieur de lui. On s'inscrit, et le balayage d'onglets vient
     * demander avant de bouger.
     */
    func edInnerPager<Value: Hashable>(
        _ order: [Value], selection: Binding<Value>, enabled: Bool = true
    ) -> some View {
        modifier(EdInnerPager(order: order, selection: selection, enabled: enabled))
    }
}

private struct EdInnerPager<Value: Hashable>: ViewModifier {
    let order: [Value]
    @Binding var selection: Value
    let enabled: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { register() }
            .onDisappear { EdGesture.shared.inner = nil }
            // La reponse est refaite a chaque changement : elle doit dire
            // « je peux bouger » depuis le sous-onglet d'AUJOURD'HUI.
            .onChange(of: enabled) { _, _ in register() }
            .onChange(of: order) { _, _ in register() }
    }

    private func register() {
        guard enabled else { EdGesture.shared.inner = nil; return }
        EdGesture.shared.inner = { dx in
            guard let here = order.firstIndex(of: selection) else { return false }
            let next = dx < 0 ? here + 1 : here - 1
            guard order.indices.contains(next) else { return false }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(EdMotion.spring) { selection = order[next] }
            return true
        }
    }
}

/*
 * Un geste à la fois : horizontal OU vertical, jamais les deux.
 *
 * Les deux reconnaisseurs partent ensemble par construction, et un balayage
 * n'est jamais parfaitement droit : un degré d'obliquité suffisait pour que la
 * page change ET que l'écran défile sous le doigt en même temps. Les deux
 * gestes étaient « réussis », et le résultat était illisible.
 *
 * D'où le verrou d'axe, qui est ce que fait un pagineur : dès que le geste est
 * franchement horizontal — quatorze points, et deux fois plus en largeur qu'en
 * hauteur, la même proportion qui décidera du changement de page — le
 * défilement vertical rend la main pour la durée du geste. La décision
 * elle-même ne bouge pas : soixante points à la fin, même proportion.
 *
 * Le verrou se pose sur une proportion stricte, pas sur la distance seule : un
 * défilement vertical oblique ne le déclenche pas, et ne se retrouve donc
 * jamais figé.
 */
private struct EdSwipe<Value: Hashable>: ViewModifier {
    let order: [Value]
    @Binding var selection: Value
    let enabled: Bool

    @State private var locked = false

    func body(content: Content) -> some View {
        content
            .scrollDisabled(locked)
            .simultaneousGesture(
                // Quatorze points pour OBSERVER, soixante pour décider : le
                // reconnaisseur doit démarrer tôt pour avoir le temps de poser
                // le verrou, sinon le défilement a déjà quarante points
                // d'avance quand on s'aperçoit que le geste est horizontal.
                DragGesture(minimumDistance: 14)
                    .onChanged { move in
                        guard enabled, !EdGesture.shared.scrubbing, !locked else { return }
                        let dx = move.translation.width
                        let dy = move.translation.height
                        if abs(dx) > 14, abs(dx) > abs(dy) * 2 {
                            locked = true
                            // Le verrou d'axe est l'instant où ce doigt cesse
                            // d'être un appui : les rangées sous lui doivent
                            // le savoir avant qu'il se lève. Voir `edOpen`.
                            EdGesture.shared.swiping = true
                            /*
                             * Le verrou rend la main tout seul.
                             *
                             * Il coupe le défilement de l'écran, et il n'était
                             * baissé que dans `onEnded` — qui ne vient pas
                             * quand le reconnaisseur est annulé. Un seul manque
                             * et l'écran ne défilait plus du tout, pour de bon.
                             * Deux secondes de garde : le chemin normal le
                             * baisse bien avant, et un geste qui dure plus
                             * longtemps que ça n'est plus un balayage.
                             */
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                if locked { locked = false }
                            }
                        }
                    }
                    .onEnded { move in
                        let mine = locked
                        locked = false
                        if mine {
                            // Levé un peu après : l'action de la rangée part
                            // au lever du doigt, pas avant.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                EdGesture.shared.swiping = false
                            }
                        }
                        /*
                         * `mine` dit qu'on a bien pris ce doigt : sans
                         * verrou, le geste appartenait à quelqu'un d'autre
                         * dès le départ.
                         */
                        guard enabled, mine, !EdGesture.shared.scrubbing else { return }
                        let dx = move.translation.width
                        let dy = move.translation.height
                        guard abs(dx) > 60, abs(dx) > abs(dy) * 2 else { return }
                        // Les sous-onglets de l'ecran d'abord, s'il y en a et
                        // s'ils ont ou aller — voir `EdGesture.inner`.
                        if let inner = EdGesture.shared.inner, inner(dx) { return }
                        guard let here = order.firstIndex(of: selection) else { return }
                        let next = dx < 0 ? here + 1 : here - 1
                        guard order.indices.contains(next) else { return }
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(EdMotion.spring) { selection = order[next] }
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

    /*
     * Un drapeau qui se leve tout seul.
     *
     * Ils etaient baisses dans `onEnded`, et SwiftUI ne garantit pas
     * `onEnded` : un reconnaisseur annule — parce que la vue qui le porte est
     * demontee sous le doigt, ce qui arrive precisement quand un pagineur
     * change de page pendant le geste — ne le recoit jamais. Un seul manque,
     * et le drapeau restait leve POUR DE BON : plus un seul balayage d'onglet
     * et plus une seule rangee qui s'ouvre, jusqu'au relancement de l'app.
     *
     * Chaque `onChanged` repose la date ; au-dela d'un delai de garde, le
     * drapeau est lu comme baisse. Les baisses explicites restent — elles
     * seules ont le bon tempo, 0,25 s apres le lever du doigt — et le delai
     * n'est que le filet, quatre secondes de rien plutot que l'infini.
     *
     * Quatre et non deux : la courbe du patrimoine pose `scrubbing` depuis
     * `chartXSelection`, qui ne renvoie rien tant que le doigt ne bouge pas.
     * Un doigt arrete sur un point pour en lire le montant ne doit pas rendre
     * la main au balayage d'onglets, et personne ne s'arrete quatre secondes
     * au milieu d'un geste.
     */
    private static let ttl: TimeInterval = 4

    private var scrubUntil = Date.distantPast
    private var swipeUntil = Date.distantPast

    /*
     * Deux drapeaux, parce qu'ils ne sont pas lus par les mêmes.
     *
     * `scrubbing` arbitre entre GESTES : celui qui l'a posé garde le doigt,
     * les autres reconnaisseurs horizontaux renoncent. Le changement d'onglet
     * ne peut donc pas le poser — il n'y a qu'un `edSwipe` dans l'app, mais
     * la courbe du patrimoine en pose un, et le balayage d'onglets doit
     * pouvoir lire le sien sans l'avoir efface.
     *
     * `swiping` ne dit qu'une chose, à l'ACTION d'une rangée : un doigt est en
     * train de balayer, ce toucher n'est pas un appui. Aucun geste ne le lit,
     * donc en poser un de plus n'arbitre rien et ne casse rien.
     */
    var swiping: Bool {
        get { swipeUntil > Date() }
        set { swipeUntil = newValue ? Date().addingTimeInterval(Self.ttl) : .distantPast }
    }

    var scrubbing: Bool {
        get { scrubUntil > Date() }
        set { scrubUntil = newValue ? Date().addingTimeInterval(Self.ttl) : .distantPast }
    }

    /*
     * Le pagineur du dedans, quand il y en a un a l'ecran.
     *
     * Il y en avait deux, et c'etait un `DragGesture` de trop : celui du
     * dedans etait pose SUR LE CONTENU, c'est-a-dire a l'interieur du
     * defilement de l'ecran. Un reconnaisseur de glissement place sous une
     * zone defilante prend le doigt avant elle — c'est la regle d'UIKit, un
     * descendant passe devant — et il le prend des quatorze points PEU
     * IMPORTE LE SENS. Donc sur Analyse, le pouce pose sur le contenu ne
     * faisait plus defiler la page du tout : le geste vertical etait reclame
     * par le pagineur des sous-onglets, qui n'en faisait rien.
     *
     * C'est pour ca que seul Analyse etait touche : celui des onglets est
     * pose sur le `TabView`, donc AU-DESSUS du defilement, et un ancetre perd
     * contre lui. Un seul geste dans toute l'app, celui du haut ; celui du
     * dedans n'est plus un geste mais une REPONSE — « ce balayage, je le
     * prends » — que le geste du haut vient lui proposer.
     *
     * Il se sert d'abord, et seulement s'il peut bouger : au bout de ses
     * sous-onglets il refuse et le doigt passe a l'onglet suivant, ce qui est
     * exactement ce que fait un pagineur dans un pagineur partout ailleurs
     * sur iOS.
     */
    var inner: ((Double) -> Bool)?
}


/// Ouvre, sauf si le doigt était en train de balayer.
///
/// Un `ButtonStyle` ne peut pas refuser : l'action appartient au `Button` et
/// part au lever du doigt, glissement ou pas. Un `PrimitiveButtonStyle` le
/// pourrait, mais son `DragGesture` maison prend le pas sur le défilement des
/// listes. Le refus se lit donc là où il coûte zéro — dans l'action.
@MainActor
func edOpen(_ body: () -> Void) {
    guard !EdGesture.shared.swiping, !EdGesture.shared.scrubbing else { return }
    body()
}

extension View {
    /*
     * Ce balayage horizontal appartient à CE défilement, pas à l'onglet.
     *
     * Une rangée de pastilles qui défile de côté vit à l'intérieur d'un écran
     * où le balayage horizontal veut dire « onglet suivant ». Les deux gestes
     * partaient donc ensemble : on faisait glisser les sous-onglets et on
     * changeait d'onglet par-dessus — ou, là où il n'y a pas d'onglet suivant,
     * on sortait de l'écran pour rien.
     *
     * `edSwipe` renonce déjà quand un doigt est en train de suivre quelque
     * chose (`scrubbing`, posé par la courbe du patrimoine). On pose le même
     * drapeau, et on le lève un peu après la fin du geste : `onEnded` des deux
     * reconnaisseurs tombe dans un ordre qui n'est pas garanti.
     */
    func edHoldsSwipe() -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { move in
                    /*
                     * Horizontal SEULEMENT, et ça manquait.
                     *
                     * Six points dans n'importe quel sens : le pouce posé sur
                     * la rangée de pastilles pour faire défiler la page
                     * VERTICALEMENT réclamait le doigt, et ce drapeau-là est
                     * celui que lit `edOpen`. On faisait défiler l'écran et
                     * plus aucune rangée ne s'ouvrait — alors que ce geste
                     * n'avait rien à voir avec le défilement de côté qu'on
                     * voulait protéger.
                     */
                    guard abs(move.translation.width) > abs(move.translation.height)
                    else { return }
                    EdGesture.shared.scrubbing = true
                }
                .onEnded { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        EdGesture.shared.scrubbing = false
                    }
                }
        )
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
            content
            .onReceive(
                NotificationCenter.default.publisher(for: .florinTabReselected)
            ) { note in
                guard note.object as? TabRoute == tab, !chrome.detailOpen else { return }
                withAnimation(EdMotion.spring) {
                    proxy.scrollTo(edTopAnchor, anchor: .top)
                }
            }
            .onChange(of: chrome.left) { _, left in
                guard left == tab else { return }
                /*
                 * On remonte une fois la page sortie, pas en sortant.
                 *
                 * `chrome.left` est posé quand la sélection bascule,
                 * c'est-à-dire au début du glissement : la page qu'on quitte
                 * est encore à l'écran pour un tiers de seconde, et on la
                 * voyait remonter en partant. Le temps d'attente est celui
                 * du glissement du pagineur.
                 *
                 * Et sans animation : si le doigt revient en arrière plus
                 * vite que prévu, mieux vaut la trouver déjà en haut que la
                 * surprendre en train d'y aller.
                 */
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(420))
                    guard chrome.left == tab else { return }
                    // `Transaction` tout court est le modèle de l'app.
                    var instant = SwiftUI.Transaction()
                    instant.disablesAnimations = true
                    withTransaction(instant) {
                        proxy.scrollTo(edTopAnchor, anchor: .top)
                    }
                }
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
 * Les bords, on les laisse tranquilles.
 *
 * C'est la build 515 qui a tranché, en la reposant sur le téléphone : ce
 * qu'il faut aux deux bords est l'effet de bord d'iOS 26 TEL QUEL — celui
 * que le SDK 27 allume tout seul — par-dessus `edEnter`, qui décale et
 * éteint chaque élément selon sa place dans le défilement. Les deux
 * ensemble font qu'une ligne s'en va au lieu d'être coupée, en haut comme
 * en bas, jusqu'au bord de l'écran.
 *
 * Tout ce qui a été ajouté par-dessus était de trop, et la liste vaut d'être
 * gardée : un matériau flouté, qui éclaircit ce qu'il couvre et vire au gris
 * sur du noir ; un dégradé du fond, qui éteint un titre encore en plein
 * milieu ; un masque sur tout le défilement, qui laisse un vide en haut dès
 * que la zone sûre est comptée deux fois. Et l'erreur suivante a été de
 * faire taire l'effet du système en même temps : il ne restait plus rien.
 *
 * Donc ce modificateur ne fait RIEN. Il reste parce qu'il est posé sur les
 * cinq écrans éditoriaux et qu'il nomme la décision : ici, on ne touche pas
 * aux bords.
 */
struct EdPlainEdges: ViewModifier {
    func body(content: Content) -> some View { content }
}

extension View {
    func edPlainEdges() -> some View { modifier(EdPlainEdges()) }
}

/*
 * Rendre le balayage de retour à un écran sans barre de navigation.
 *
 * Cacher la barre (`toolbar(.hidden, for: .navigationBar)`) ne cache pas
 * qu'elle : UIKit coupe en même temps le geste de retour, parce que ce geste
 * est normalement l'autre façon d'appuyer sur un chevron qui n'existe plus.
 * Nos écrans dessinent leur propre chevron, donc le geste doit revenir.
 *
 * Le délégué remis à plat est repris par le nôtre, et non laissé à `nil` : à
 * `nil`, le geste part aussi depuis la racine de la pile, où il n'y a rien à
 * dépiler — et l'app reste figée sur un retour qui ne se termine jamais.
 */
private struct EdSwipeBack: UIViewRepresentable {
    final class Keeper: NSObject, UIGestureRecognizerDelegate {
        weak var nav: UINavigationController?

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            (nav?.viewControllers.count ?? 0) > 1
        }

        func gestureRecognizer(
            _ recognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { false }
    }

    func makeCoordinator() -> Keeper { Keeper() }

    func makeUIView(context: Context) -> UIView {
        let marker = UIView(frame: .zero)
        marker.isUserInteractionEnabled = false
        DispatchQueue.main.async { restore(from: marker, with: context.coordinator) }
        return marker
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async { restore(from: uiView, with: context.coordinator) }
    }

    private func restore(from view: UIView, with keeper: Keeper) {
        var responder: UIResponder? = view
        while let current = responder {
            if let nav = current as? UINavigationController {
                keeper.nav = nav
                nav.interactivePopGestureRecognizer?.isEnabled = true
                nav.interactivePopGestureRecognizer?.delegate = keeper
                return
            }
            responder = current.next
        }
    }
}

extension View {
    /// Le chevron est dessiné à la main, le geste doit l'être aussi.
    ///
    /// Deux gestes, pas un. Celui d'UIKit, rendu ci-dessus, part du bord
    /// gauche et suit le doigt — c'est le retour qu'on connaît. Mais dans
    /// cette app le balayage horizontal veut dire « onglet suivant »
    /// n'importe où sur l'écran, et tant qu'un relevé est posé par-dessus,
    /// l'onglet ne bouge pas : le balayage tombait dans le vide. Il dépile
    /// donc depuis n'importe où — mais VERS LA DROITE, et seulement.
    ///
    /// Les deux sens ont été essayés, pour que le geste ne tombe jamais dans
    /// le vide, et c'est pire : un retour qui part vers la gauche est un
    /// retour à l'envers, le contraire de ce que tout le reste du téléphone
    /// fait. Un balayage vers la gauche sur un écran posé ne fait donc rien,
    /// et c'est la bonne réponse.
    ///
    /// Le seuil est double — soixante-dix points, et deux fois plus
    /// horizontal que vertical — pour qu'un défilement un peu de travers ne
    /// referme pas l'écran qu'on est en train de lire.
    func edSwipeBack(_ pop: @escaping () -> Void) -> some View {
        background(EdSwipeBack().frame(width: 0, height: 0))
            .simultaneousGesture(
                DragGesture(minimumDistance: 30, coordinateSpace: .global)
                    /*
                     * Ce doigt-là est pris — voir `edHoldsSwipe`.
                     *
                     * Dépiler et changer d'onglet sont deux
                     * `simultaneousGesture` qu'un même balayage vers la
                     * droite satisfait : on revenait de la fiche d'un compte
                     * à la liste, et l'onglet glissait vers l'accueil dans la
                     * foulée. Le drapeau partagé est exactement ce qui sert à
                     * se le dire.
                     */
                    .onChanged { value in
                        guard abs(value.translation.width)
                            > abs(value.translation.height) else { return }
                        if !EdGesture.shared.scrubbing {
                            EdGesture.shared.scrubbing = true
                            EdGesture.shared.swiping = true
                        }
                    }
                    .onEnded { value in
                        // Levé un peu après : l'ordre des `onEnded` de deux
                        // reconnaisseurs n'est pas garanti.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            EdGesture.shared.scrubbing = false
                            EdGesture.shared.swiping = false
                        }
                        let side = value.translation.width
                        guard side > 70, side > abs(value.translation.height) * 2
                        else { return }
                        pop()
                    }
            )
    }
}

// MARK: - Une phrase qui revient à la ligne

/*
 * La disposition qu'il faut pour que des mots soient des boutons.
 *
 * Un `Text` sait revenir à la ligne mais pas porter un toucher par mot ; un
 * `HStack` sait porter des boutons mais pas revenir à la ligne. « Tu as
 * dépensé 550,20 € en Alimentation en septembre » a besoin des deux : les
 * mots s'enchaînent comme une phrase et deux d'entre eux s'ouvrent.
 *
 * Chaque enfant est mesuré à sa taille idéale, posé à la suite, et la ligne
 * se casse quand le suivant ne tient plus. C'est tout — pas d'alignement
 * justifié, pas de césure : une phrase de six morceaux n'en a pas besoin.
 */
struct EdFlow: Layout {
    var spacing: CGFloat = 5
    var lineSpacing: CGFloat = 7

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height }
            + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(
            width: proposal.width ?? (rows.map(\.width).max() ?? 0),
            height: height
        )
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Subviews.Index] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let next = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if next > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

/// Un mot de la phrase qu'on peut changer : souligné, donc visiblement vivant.
struct EdWord: View {
    let text: String
    var size: CGFloat = 22

    var body: some View {
        /*
         * Cliquable sans être souligné.
         *
         * Le trait orange sous un mot de 22 pt traversait la phrase de part
         * en part et se lisait comme une faute de frappe signalée. Le mot
         * porte son propre filet, dans l'encre du texte et à distance de la
         * ligne de base : c'est l'affordance, pas une correction.
         */
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Florin.text)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(Florin.text3)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Florin.text.opacity(0.07))
        )
    }
}

/*
 * Le rouge d'un montant n'est pas l'accent.
 *
 * Dans ce thème, `Florin.negative` EST l'accent — c'est voulu : l'alerte et
 * le manque sont la même encre, et deux rouges voisins ne valent rien. Mais
 * l'accent se choisit, et un accent bleu rendrait les dépenses bleues. Les
 * montants gardent donc le rouge et le vert de la palette de base : une
 * sortie se lit à sa couleur avant son signe, et jamais comme une alerte.
 */
enum EdMoney {
    static let minus = Tone(light: 0xC4392F, dark: 0xF08072).color
    static let plus = Tone(light: 0x1F8B5F, dark: 0x5FD9A0).color

    /// L'encre d'un mouvement, par son sens.
    static func tone(_ amount: Double) -> Color { amount < 0 ? minus : plus }
}

/*
 * Choisir un mot dans la phrase, sans le menu du système.
 *
 * `Menu` ouvre la feuille contextuelle d'iOS : un fond translucide, une
 * typographie, des coins et un rythme qui ne sont ceux d'aucun écran d'ici,
 * posés par-dessus un écran qui ne vit que de ça. Une `popover` compacte
 * s'ancre au même endroit et se dessine entièrement — c'est le même geste,
 * dans la langue de l'app.
 */
struct EdWordPicker<Value: Hashable>: View {
    let label: String
    let options: [(value: Value, label: String)]
    let pick: (Value) -> Void

    @State private var open = false

    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            open = true
        } label: {
            EdWord(text: label)
        }
        .buttonStyle(.edPress)
        .popover(isPresented: $open) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element.value) { index, option in
                        if index > 0 { EdRule() }
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            pick(option.value)
                            open = false
                        } label: {
                            HStack(spacing: 12) {
                                Text(option.label)
                                    .font(.system(size: 17))
                                    .foregroundStyle(Florin.text)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                if option.label == label {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Florin.accent)
                                }
                            }
                            .frame(minHeight: 46)
                            .padding(.horizontal, 20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.edPress)
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .frame(minWidth: 230, maxHeight: 420)
            .presentationCompactAdaptation(.popover)
            .presentationBackground(Florin.bg)
        }
    }
}

/*
 * On tourne le mois comme on tourne une page.
 *
 * `simultaneousGesture` et non `gesture` : la vue dessous garde ses propres
 * gestes — le défilement vertical de la page, le tap d'une case. Le drapeau
 * partagé `EdGesture.scrubbing` prévient le balayage d'onglets que ce doigt
 * est déjà pris.
 */
struct EdMonthSwipe: ViewModifier {
    let step: (Int) -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onChanged { move in
                    guard abs(move.translation.width) > abs(move.translation.height) else {
                        return
                    }
                    EdGesture.shared.scrubbing = true
                }
                .onEnded { move in
                    defer {
                        DispatchQueue.main.async { EdGesture.shared.scrubbing = false }
                    }
                    let dx = move.translation.width
                    guard abs(dx) > 50, abs(dx) > abs(move.translation.height) * 1.5
                    else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    step(dx < 0 ? 1 : -1)
                }
        )
    }
}
