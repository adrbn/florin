import SwiftUI

/// The app's coloured ground.
///
/// Neobanks (Revolut, Monzo, N26) all do the same thing: a saturated wash at
/// the top that falls away to near-black by mid-screen, re-tinted per section.
/// It does real work — it gives the headline figure a stage instead of leaving
/// it stranded on flat black, it tells you which section you are in before you
/// read a word, and it gives the glass bar something worth refracting.
///
/// Florin's version stays darker than Revolut's: the palette is Obsidian and
/// the figures have to keep their contrast. The colour lives in the top third,
/// the reading area stays quiet.
struct Backdrop: View {
    let tint: Color
    /*
     * Le mode clair n'est pas le mode sombre avec les couleurs échangées.
     *
     * Ce fond a été réglé pour du noir : une teinte à soixante pour cent en
     * haut, et deux foyers posés en `plusLighter` pour que le bas ne soit
     * jamais d'une seule valeur. Sur un fond presque blanc, la teinte lave
     * l'écran d'un violet qu'aucune maquette n'a demandé, et `plusLighter`
     * sature vers le blanc pur — donc ne fait rien, sauf là où il déborde.
     *
     * En clair, le fond redevient ce qu'il doit être : blanc. Il reste une
     * trace de teinte sur la première poignée de centimètres, juste de quoi
     * dire dans quelle pièce on se trouve, puis plus rien. Les foyers
     * disparaissent : leur raison d'être était d'empêcher un noir plat, et le
     * blanc plat ne pose pas ce problème.
     */
    @Environment(\.colorScheme) private var scheme
    /*
     * A sheet is shorter than a screen and reaches the bottom of the display.
     *
     * The tab gradient is tuned for a tall scroll: it dips to almost nothing
     * in the middle so figures keep their contrast, then lifts again at the
     * very bottom. Inside a sheet that dip lands in the middle of the content
     * and the last third reads as flat near-black. This holds a floor under it
     * instead.
     */
    var floor = false

    /*
     * Combien ce fond pèse, selon le thème.
     *
     * Obsidienne vaut 1 : les valeurs ci-dessous sont les siennes, réglées sur
     * elle. Papier vaut 0, et c'est la seule façon d'être réellement minimal —
     * un voile violet très pâle reste un voile violet. Les thèmes
     * intermédiaires l'adoucissent sans l'éteindre.
     */
    private var weight: Double { Palette.current.ground }

    var body: some View {
        ZStack {
            Florin.bg

            /*
             * Full height, deliberately.
             *
             * The first version put all the colour in the top third and let the
             * rest fall to flat near-black — which looks right on the first
             * screenful and turns into a grey slab the moment you scroll past
             * it. Revolut's ground never dies: it is dark in the middle and
             * lifts again at the bottom, so wherever you are there is something
             * behind the content. These stops do the same, with the mid-screen
             * band kept low enough that figures keep their contrast.
             */
            if scheme == .light {
                LinearGradient(
                    stops: [
                        .init(color: tint.opacity(0.10 * weight), location: 0.00),
                        .init(color: tint.opacity(0.045 * weight), location: 0.18),
                        .init(color: tint.opacity(0.015 * weight), location: 0.38),
                        .init(color: .clear, location: 0.60),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    stops: [
                        .init(color: tint.opacity(0.62 * weight), location: 0.00),
                        .init(color: tint.opacity(0.32 * weight), location: 0.14),
                        .init(color: tint.opacity(0.15 * weight), location: 0.30),
                        .init(color: tint.opacity((floor ? 0.16 : 0.06) * weight), location: 0.50),
                        .init(color: tint.opacity((floor ? 0.18 : 0.05) * weight), location: 0.72),
                        .init(color: tint.opacity((floor ? 0.22 : 0.13) * weight), location: 1.00),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            // A soft hotspot behind the headline, so the number sits in light
            // rather than on a flat band. Dark only: see the note on `scheme`.
            if scheme != .light {
                RadialGradient(
                    colors: [tint.opacity(0.30 * weight), .clear],
                    center: UnitPoint(x: 0.5, y: 0.10),
                    startRadius: 0,
                    endRadius: 420
                )
                .blendMode(.plusLighter)

                // And a second, much wider one low and off-centre. Barely visible
                // on its own; what it buys is that the lower half is never one flat
                // value, which is the difference between "dark" and "unfinished".
                RadialGradient(
                    colors: [tint.opacity(0.16 * weight), .clear],
                    center: UnitPoint(x: 0.14, y: 0.94),
                    startRadius: 0,
                    endRadius: 560
                )
                .blendMode(.plusLighter)
            }
        }
        .ignoresSafeArea()
    }
}

extension TabRoute {
    /// One hue per section, the way a neobank signals where you are before you
    /// have read anything. Kept in the same family as the accent so the app
    /// still looks like one app.
    var tint: Color {
        // Saturated on purpose, dans Obsidienne. A muted set was tried and it
        // made the five screens read as one long grey scroll; the whole point
        // of the coloured ground is that you know which room you are in before
        // you read a word. Chaque thème a son propre jeu — voir
        // `Palette.grounds` — et Papier les éteint par son poids, pas en les
        // remplaçant par du gris.
        Florin.ground(ground)
    }

    private var ground: Palette.Ground {
        switch self {
        case .overview: return .overview
        case .accounts: return .accounts
        case .plan: return .plan
        case .activity: return .activity
        case .analysis: return .analysis
        case .settings: return .settings
        }
    }
}

extension Florin {
    /*
     * The ground for sheets that compose something.
     *
     * The five tabs each own a hue so you know which room you are in. A sheet
     * is not a room — it is an action taken from wherever you were — and
     * borrowing the host tab's colour made it read as more of the same screen,
     * while leaving it untinted let the gradient die into black by the third
     * row. Jade is the one part of the wheel no tab uses, and being a ground
     * rather than text it cannot be mistaken for the green that means a gain.
     */
    static let sheetTint = ground(.sheet)
}

/// A round icon button on the coloured ground — the Revolut header/action
/// vocabulary. Glass so it belongs to the same layer as the tab bar.
struct CircleButton: View {
    let symbol: String
    var size: CGFloat = 46
    var prominent = false
    /*
     * Turns the glyph, not the button.
     *
     * Rotating the whole thing spun the glass disc with it, which looks like a
     * rendering fault rather than progress — the button appeared to come loose
     * from the layout. Only the symbol should move.
     */
    var spinning = false
    let action: () -> Void

    @State private var angle: Double = 0

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(prominent ? Florin.accent : Florin.text)
                .rotationEffect(.degrees(angle))
                .frame(width: size, height: size)
                .florinGlass(in: Circle())
                /*
                 * Say where the button is.
                 *
                 * Without this the hit area is inferred from the glyph and
                 * whatever the glass material decides to report, and on iOS 26
                 * that is sometimes nothing: the close button on the bank
                 * sheet drew correctly and swallowed every tap. A circle the
                 * size of the button is the shape a person is aiming at
                 * anyway.
                 */
                .contentShape(Circle())
                .onChange(of: spinning) { _, active in
                    if active {
                        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                            angle = 360
                        }
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) { angle = 0 }
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

/// A small glass capsule: icon, label, optional count.
///
/// Replaces the row of 56pt circles with 32pt labels underneath. Those were
/// ~96pt of screen for four shortcuts, three of which the tab bar already
/// offers — the row read as important and was mostly redundant. This is ~38pt,
/// sits on one line, and only carries what is genuinely not a tab.
struct QuickPill: View {
    let symbol: String
    let label: String
    var badge: Int = 0
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Florin.negative, in: Capsule())
                }
            }
            .foregroundStyle(prominent ? Florin.accent : Florin.text)
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .florinGlass(in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A labelled round action, stacked like Revolut's "Ajouter de l'argent" row.
struct ActionBubble: View {
    let symbol: String
    let label: String
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Florin.text)
                        .frame(width: 56, height: 56)
                        .florinGlass(in: Circle())
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Florin.negative, in: Capsule())
                            .offset(x: 6, y: -4)
                    }
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Florin.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(height: 32, alignment: .top)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
