import SwiftUI

/// The composition every tab shares.
///
/// The dashboard settled on a shape — coloured ground, a small top row of round
/// controls, a centred headline with air around it, a row of labelled bubbles,
/// then content — and the other tabs looked like a different app until they used
/// it too. Rather than copy it four times, it lives here: `TabScaffold` owns the
/// scroll view, the backdrop, the bottom clearance and the pull-to-refresh, and
/// each screen supplies its own header, hero and body.
struct TabScaffold<Content: View>: View {
    let tint: Color
    var refresh: (() async -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Backdrop(tint: tint)
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    content
                }
                .padding(.top, 6)
                // Clears the floating bar plus its scrim, so the last row is
                // never left half-legible behind glass.
                .padding(.bottom, 116)
                /*
                 * Une colonne, même sur un grand écran.
                 *
                 * Ouvert, l'iPhone Duo fait près de mille points de large :
                 * les cartes s'étireraient sur toute cette largeur, un
                 * libellé à un bout et son montant à l'autre, et le regard
                 * ferait le voyage à chaque ligne. La colonne garde donc sa
                 * largeur de lecture et se centre ; sur un téléphone, où
                 * l'écran est plus étroit que cette limite, rien ne change.
                 */
                .frame(maxWidth: Florin.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .modifier(SoftScrollEdge())
            .refreshable { await refresh?() }
        }
    }
}

/// Avatar, a wide middle control, one trailing action — the row every neobank
/// puts above the balance.
struct TopBar<Middle: View, Trailing: View>: View {
    let onProfile: () -> Void
    /// A pushed screen puts a back chevron here instead of the avatar. The
    /// avatar *worked* as a back button, but nothing on screen said so — it
    /// still read "open settings", which is the wrong promise.
    var back = false
    /*
     * Centre the middle on the screen rather than on what is left of it.
     *
     * The bar is a row — gear, middle, trailing — so a middle that fills the
     * remaining width centres itself between the gear and the buttons. With one
     * control on the left and two on the right that midpoint is not the
     * screen's, and a title reads as nudged off-centre by exactly the width of
     * the difference.
     *
     * Only for a title. A search field is *supposed* to take the space that is
     * left, and centring it would leave a gap under the buttons.
     */
    var centersMiddle = false
    @ViewBuilder var middle: Middle
    @ViewBuilder var trailing: Trailing

    private var editorial: Bool { FlorinPalette.selected == .editorial }

    var body: some View {
        HStack(spacing: 10) {
            /*
             * A bare gear, no glass around it.
             *
             * The lettered avatar was borrowed from banking apps that have an
             * account behind it; Florin has one user and no profile, so the "F"
             * was decoration promising something that does not exist. A gear
             * says what the control does, and without a bubble it sits back
             * where a utility belongs instead of competing with the search
             * field beside it.
             */
            Button(action: onProfile) {
                // En éditorial le réglage est un trait de menu à l'encre, pas
                // un engrenage gris : la maquette n'a qu'une encre et aucun
                // pictogramme figuratif dans son bandeau.
                // Un chevron en éditorial, pas une croix : ces écrans-là ne
                // se ferment pas, on en revient — et une croix promet de
                // refermer quelque chose qui n'a pas été ouvert par-dessus.
                Image(systemName: editorial
                    ? (back ? "chevron.left" : "line.3.horizontal")
                    : (back ? "xmark" : "gearshape"))
                    .font(.system(
                        size: editorial ? 18 : (back ? 17 : 21),
                        weight: editorial ? .medium : (back ? .bold : .regular)
                    ))
                    .foregroundStyle(editorial ? Florin.text : Florin.text2)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                back
                    ? Strings.device("v2.common.close", "Fermer")
                    : Strings.device("v2.settings.title", "Réglages")
            )

            /*
             * Rien n'est centré en éditorial.
             *
             * Un titre centré à 17 points est la chose la plus étrangère à
             * cette maquette : elle lit sur une colonne alignée à gauche et
             * tire sa hiérarchie du corps, pas de la position. Le titre
             * reprend donc sa place dans la rangée, à côté du menu.
             */
            if centersMiddle, !editorial {
                Spacer(minLength: 0)
                trailing
            } else {
                middle
                Spacer(minLength: 8)
                trailing
            }
        }
        .padding(.horizontal, Florin.gutter)
        .overlay {
            if centersMiddle, !editorial {
                middle
                    // Clear of the widest side, so a long title shrinks rather
                    // than sliding under a button.
                    .padding(.horizontal, 104)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// The centred headline: caption, figure, one line under it, an optional pill.
struct HeroBlock<Sub: View>: View {
    let caption: String
    let value: Double
    let locale: String
    let currency: String
    /// Matches the dashboard's hero exactly — the two screens answer the same
    /// question and a different type size made them look unrelated.
    var size: CGFloat = 60
    var onTap: (() -> Void)?
    /// A bank sync is running: the figure spins (`SlotAmount`).
    var spinning = false
    @ViewBuilder var sub: Sub

    var body: some View {
        /*
         * Le même héros, dans deux grammaires.
         *
         * Ailleurs il est centré : c'est le chiffre du haut d'une page, posé
         * comme un titre d'affiche. En éditorial rien n'est centré — la page
         * se lit sur une colonne alignée à gauche, l'étiquette est une
         * pastille au contour, et le chiffre porte le poids plutôt que la
         * position. Trois lignes de différence plutôt qu'un second composant
         * qui dériverait du premier.
         */
        let editorial = FlorinPalette.selected == .editorial
        return VStack(alignment: editorial ? .leading : .center, spacing: editorial ? 8 : 10) {
            if editorial {
                EdPill(text: caption)
            } else {
                Text(caption)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Florin.text2)
            }

            /*
             * Le même chiffre partout, ou deux typographies pour une question.
             *
             * `SlotAmount` dessine le héros d'Obsidienne : maigre, les
             * centimes rognés à 44 % et grisés, un crénage serré. Posé tel
             * quel dans un écran éditorial, le solde d'un compte n'avait rien
             * à voir avec le patrimoine de l'accueil, qui est pourtant la
             * même phrase à une échelle près. Les bobines sont communes ;
             * seul le visage change.
             */
            if editorial {
                SlotReels(value: value, spinning: spinning) { rolling in
                    EdAmount(
                        text: Money.string(rolling, locale: locale, currency: currency),
                        size: size
                    )
                }
            } else {
                SlotAmount(
                    value: value, spinning: spinning,
                    locale: locale, currency: currency, size: size
                )
            }

            sub.frame(minHeight: 20)
        }
        .frame(maxWidth: .infinity, alignment: editorial ? .leading : .center)
        .padding(.horizontal, editorial ? Ed.gutter : 0)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let onTap else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            onTap()
        }
        // Hold the figure to cover every figure. Shaking is the fast way; this
        // is the one you find without being told.
        .onLongPressGesture(minimumDuration: 0.45) { Privacy.shared.toggle() }
        .accessibilityElement(children: .combine)
    }
}

extension HeroBlock where Sub == EmptyView {
    init(
        caption: String,
        value: Double,
        locale: String,
        currency: String,
        size: CGFloat = 60,
        onTap: (() -> Void)? = nil
    ) {
        self.init(
            caption: caption, value: value, locale: locale, currency: currency,
            size: size, onTap: onTap, sub: { EmptyView() }
        )
    }
}

/// A glass capsule under the hero — Revolut's "Comptes" / "Ajouter" affordance.
struct HeroPill: View {
    let label: String
    var symbol: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                }
                Text(label).font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Florin.text)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .florinGlass(in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A titled block, gutter-aligned like every other section.
struct ScreenSection<Content: View>: View {
    let title: String
    var trailing: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(text: title)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Florin.text3)
                        // Most section trailers are a total.
                        .hiddenWhenPrivate()
                }
            }
            .padding(.horizontal, Florin.gutter)
            content
        }
    }
}

/// What the top edge of a scrolling page does.
///
/// Two things, and they are not the same thing. iOS 26's own effect fades
/// content into the *bars* instead of hard-clipping it — but a tab root has no
/// bars: it hides the navigation bar so the headline can be ours, which leaves
/// the status bar with nothing but the page under it. `TopScrim` is what blurs
/// what arrives there. See there.
struct SoftScrollEdge: ViewModifier {
    /// How far the page has scrolled from rest, read from the scroll view
    /// itself so no screen has to report it.
    @State private var scrolled: CGFloat = 0

    func body(content: Content) -> some View {
        tracked(system(content))
            .overlay(alignment: .top) { TopScrim(scrolled: scrolled) }
    }

    private func system(_ content: Content) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                content.scrollEdgeEffectStyle(.soft, for: .top)
            } else {
                content
            }
        }
    }

    @ViewBuilder
    private func tracked<V: View>(_ view: V) -> some View {
        if #available(iOS 18.0, *) {
            view.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, distance in
                scrolled = distance
            }
        } else {
            view
        }
    }
}

/// Segmented control in the app's own idiom, for the sub-tabs the Analyse and
/// Activité screens need. A `Picker` would work, but it cannot scroll and these
/// screens have four and five options with real words in them.
struct ChipBar<Value: Hashable>: View {
    let options: [(value: Value, label: String, badge: Int)]
    @Binding var selection: Value

    /*
     * One size of type across the row, whatever the row has to do to fit.
     *
     * Every chip used to take an equal share of the width, which is a quite
     * different constraint from "the row fits": five equal fifths cannot hold
     * "Tendances" and "Calendrier" at 14pt, so those two shrank a step and then
     * truncated anyway while "Flux" sat in a half-empty capsule — one row, three
     * sizes of type and two ellipses.
     *
     * A chip is as wide as its own word now and the leftover width is shared
     * out as padding (`SharedSlack`). What gives way when the row is tight is
     * the padding, in two steps, and then the row scrolls. The type never
     * scales and a label is never cut.
     */
    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(padding: 16, spacing: 8)
            row(padding: 12, spacing: 7)
            row(padding: 8, spacing: 6)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.value) { chip($0, padding: 15) }
                }
                .padding(.horizontal, Florin.gutter)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func row(padding: CGFloat, spacing: CGFloat) -> some View {
        SharedSlack(spacing: spacing) {
            ForEach(options, id: \.value) { chip($0, padding: padding) }
        }
        .padding(.horizontal, Florin.gutter)
    }

    private func chip(
        _ option: (value: Value, label: String, badge: Int),
        padding: CGFloat
    ) -> some View {
        let active = option.value == selection
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy(duration: 0.2)) { selection = option.value }
        } label: {
            HStack(spacing: 6) {
                label(option.label, active: active)
                if option.badge > 0 {
                    Text("\(option.badge)")
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Florin.negative, in: Capsule())
                }
            }
            // Sur une capsule pleine d'encre, le mot s'écrit dans le fond de
            // la page — sans quoi il disparaît dans son propre remplissage.
            .foregroundStyle(
                active
                    ? (FlorinPalette.selected == .editorial ? Florin.bg : Florin.text)
                    : Florin.text2
            )
            .padding(.horizontal, padding)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .modifier(ChipGlass(active: active))
        }
        .buttonStyle(.plain)
    }

    /// Always measured in the heavier weight it wears when selected, so moving
    /// the selection does not re-measure the row and shuffle its neighbours.
    private func label(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .hidden()
            .overlay {
                Text(text)
                    .font(.system(size: 14, weight: active ? .semibold : .medium))
                    .lineLimit(1)
                    .fixedSize()
            }
    }
}

/// A row where every view keeps its natural width and the leftover space is
/// shared out equally between them.
///
/// `HStack` with `maxWidth: .infinity` on each child does the opposite: it hands
/// everyone the same width whether their content fits it or not, which is how a
/// short word gets a wide capsule and a long one gets an ellipsis. Reporting the
/// natural width as its own is also what lets `ViewThatFits` see that a row is
/// too wide — a view that stretches to whatever it is offered always "fits".
struct SharedSlack: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let natural = sizes.reduce(0) { $0 + $1.width } + gaps(subviews.count)
        return CGSize(
            width: max(natural, proposal.width ?? natural),
            height: sizes.map(\.height).max() ?? 0
        )
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        guard !subviews.isEmpty else { return }
        let widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        let slack = max(0, bounds.width - widths.reduce(0, +) - gaps(subviews.count))
        let share = slack / CGFloat(subviews.count)
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() {
            let width = widths[index] + share
            subview.place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }

    private func gaps(_ count: Int) -> CGFloat { spacing * CGFloat(max(count - 1, 0)) }
}

private struct ChipGlass: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        /*
         * En éditorial, l'onglet choisi est plein d'encre, les autres sont des
         * contours — exactement la barre d'onglets du bas, pour que « choisi »
         * veuille dire la même chose aux deux bouts de l'écran. Le verre d'iOS
         * 26 et le lavis orange sont justement ce que ce style ne pose pas.
         */
        if FlorinPalette.selected == .editorial {
            content
                .background(active ? Florin.text : Color.clear, in: Capsule())
                .overlay {
                    if !active {
                        Capsule().strokeBorder(Florin.text.opacity(0.22), lineWidth: 1)
                    }
                }
        } else if #available(iOS 26.0, *) {
            content.glassEffect(
                active ? .regular.tint(Florin.accent.opacity(0.35)).interactive()
                       : .regular.interactive(),
                in: .capsule
            )
        } else {
            content
                .background(active ? Florin.accent.opacity(0.24) : Florin.surface2, in: Capsule())
        }
    }
}

/// A hairline bar showing one row's share of the largest in its set.
///
/// Under an account row it turns a column of numbers into a shape: you can see
/// that the LEP holds most of it without reading a single figure.
struct ShareBar: View {
    let share: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Florin.text.opacity(0.05))
                Capsule()
                    .fill(tint.opacity(0.75))
                    .frame(width: max(2, geo.size.width * min(1, max(0, share))))
            }
        }
        .frame(height: 3)
    }
}
