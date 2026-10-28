import Charts
import SwiftUI

/// The hero chart: one hairline, a soft gradient, no axes — and a scrub that
/// hands the touched point back so the headline figure can rewrite itself.
struct NetWorthChart: View {
    let points: [PatrimonyPoint]
    var height: CGFloat = 150
    @Binding var selection: PatrimonyPoint?
    /// Changes whenever the window changes. Swift Charts interpolates marks
    /// between two data sets, but only if something tells it the change is
    /// animated — without this the curve teleports from 1M to 1A, which is the
    /// single most jarring transition on the screen.
    var animationKey: String = ""
    var tint: Color = Florin.accent

    /// Calculées une fois par jeu de points, pas à chaque évaluation du corps.
    /// Le corps est réévalué à chaque déplacement du doigt ; parcourir trois
    /// cent soixante-cinq soldes soixante fois par seconde pour retrouver deux
    /// nombres qui n'ont pas bougé est un travail que le scrub payait cher.
    private let bounds: (min: Double, max: Double)
    /// La date sous le doigt, telle que Swift Charts la rapporte.
    @State private var touched: Date?

    /// Ce qui s'est passé, relevé jour par jour.
    private let measured: [PatrimonyPoint]

    /*
     * La tendance : une seule droite, deux points.
     *
     * Les dents de scie disent le mois vécu ; elles ne disent pas où ça va.
     * La droite le dit, et c'est la même pente que la prévision — pas une
     * régression indépendante qui ferait un coude au présent. Elle passe par
     * le dernier solde relevé et se prolonge d'un an.
     *
     * Deux points suffisent à une droite. Les trois cent soixante-cinq points
     * de la prévision restent dans `points` pour que le scrub ait une valeur à
     * lire sous le doigt, mais les dessiner un par un faisait reconstruire
     * autant de marques à chaque image.
     */
    private let trendPast: [PatrimonyPoint]
    private let trendAhead: [PatrimonyPoint]

    /*
     * Les deux séries existent toujours, même sans prévision à montrer.
     *
     * Une série qui apparaît est une série que Swift Charts n'a pas à
     * interpoler : elle surgit d'un coup, posée par-dessus une courbe qui,
     * elle, s'étire. Repliées sur le point d'aujourd'hui tant qu'il n'y a rien
     * à prévoir, les deux droites *sortent* du dernier solde quand on demande
     * la prévision — l'une vers la gauche, l'autre vers la droite — au lieu de
     * se poser dessus.
     *
     * Repliées, leurs deux points sont confondus : un trait de longueur nulle.
     * D'où le bout carré plus bas, qui n'en dessine rien ; un bout rond y
     * laisserait un point sur la courbe en permanence.
     */
    private let hasTrend: Bool

    init(
        points: [PatrimonyPoint], height: CGFloat = 150,
        selection: Binding<PatrimonyPoint?>, animationKey: String = "",
        tint: Color = Florin.accent
    ) {
        self.points = points
        self.height = height
        _selection = selection
        self.animationKey = animationKey
        self.tint = tint

        let real = points.filter { $0.projected != true }
        let future = points.filter { $0.projected == true }
        measured = real

        /*
         * La pente se lit sur la prévision elle-même.
         *
         * Elle est déjà une droite — deux de ses points en donnent la pente
         * exacte, sans que le graphique ait à savoir comment le grand livre
         * l'a calculée. Le jour où la prévision cessera d'être droite, ces
         * deux points en seront la corde, ce qui reste la bonne tendance.
         */
        if let anchor = real.last, let opening = real.first, real.count >= 2 {
            let horizon = future.count >= 2 ? future.last : nil
            hasTrend = horizon != nil
            let step = future.count >= 2
                ? future[1].day.timeIntervalSince(future[0].day) / 86_400
                : 0
            let slope = step > 0 ? (future[1].balance - future[0].balance) / step : 0
            let back = anchor.day.timeIntervalSince(opening.day) / 86_400
            // Sans prévision, les deux bouts sont le point d'aujourd'hui : la
            // droite est là, de longueur nulle, prête à s'ouvrir.
            trendPast = [
                hasTrend
                    ? PatrimonyPoint(
                        date: opening.date, balance: anchor.balance - slope * back,
                        projected: false
                    )
                    : anchor,
                PatrimonyPoint(date: anchor.date, balance: anchor.balance, projected: false),
            ]
            trendAhead = [
                PatrimonyPoint(date: anchor.date, balance: anchor.balance, projected: false),
                horizon.map {
                    PatrimonyPoint(date: $0.date, balance: $0.balance, projected: true)
                } ?? anchor,
            ]
        } else {
            hasTrend = false
            trendPast = []
            trendAhead = []
        }

        // La droite remontée en arrière peut descendre sous le plus bas relevé :
        // les bornes la comptent, sinon elle sort du cadre par le bas.
        let values = (points + trendPast + trendAhead).map(\.balance)
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        // A dead-flat series must not collapse onto one row of pixels.
        bounds = lo == hi
            ? (lo - max(1, abs(lo) * 0.02), hi + max(1, abs(hi) * 0.02))
            : (lo, hi)
    }

    var body: some View {
        Chart {
            ForEach(measured) { point in
                AreaMark(
                    x: .value("Date", point.day),
                    yStart: .value("Base", bounds.min),
                    yEnd: .value("Solde", point.balance)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [tint.opacity(hasTrend ? 0.10 : 0.22), tint.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Date", point.day),
                    y: .value("Solde", point.balance),
                    series: .value("Série", "réel")
                )
                .foregroundStyle(tint.opacity(hasTrend ? 0.32 : 1))
                .lineStyle(
                    StrokeStyle(
                        lineWidth: hasTrend ? 1 : 1.6, lineCap: .round, lineJoin: .round
                    )
                )
                .interpolationMethod(.monotone)
            }

            /*
             * Trois traits, trois séries nommées.
             *
             * Un seul `LineMark` dont le style changerait selon le point ne
             * marche pas : Swift Charts dessine un trait par série, et un
             * style posé point par point s'applique au trait entier — tout
             * serait pointillé ou rien.
             *
             * Le passé de la tendance est plein, son avenir pointillé, et les
             * deux partagent le point d'aujourd'hui pour qu'il n'y ait pas de
             * trou au présent. `.linear` plutôt que `.monotone` : c'est une
             * droite, et une interpolation lissée sur deux points lui donnerait
             * une courbure qu'elle n'a pas.
             *
             * Pas d'aire sous les pointillés : le dégradé dit « voilà ce que
             * j'ai », et une moyenne mensuelle étalée sur un an n'a pas droit
             * au même aplomb que des soldes relevés.
             */
            /*
             * Indexées, pas datées.
             *
             * `PatrimonyPoint` s'identifie par sa date, et c'est justement la
             * date de ces deux points qui bouge quand la droite s'ouvre : avec
             * cette identité-là, Swift Charts voit disparaître deux marques et
             * en apparaître deux autres, donc ne les interpole pas — la droite
             * surgit au lieu de sortir de la courbe. Le rang, lui, ne bouge
             * pas : c'est le même début et la même fin, ailleurs.
             */
            ForEach(Array(trendPast.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Date", point.day),
                    y: .value("Solde", point.balance),
                    series: .value("Série", "tendance")
                )
                .foregroundStyle(tint)
                // Bout carré tant qu'elle est repliée : un trait de longueur
                // nulle ne dessine alors rien, là où un bout rond poserait un
                // point sur la courbe dans toutes les autres fenêtres.
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: hasTrend ? .round : .butt))
                .interpolationMethod(.linear)
            }

            ForEach(Array(trendAhead.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Date", point.day),
                    y: .value("Solde", point.balance),
                    series: .value("Série", "prévu")
                )
                .foregroundStyle(tint.opacity(0.6))
                .lineStyle(
                    StrokeStyle(
                        lineWidth: 1.6, lineCap: hasTrend ? .round : .butt, dash: [2, 4.5]
                    )
                )
                .interpolationMethod(.linear)
            }
        }
        .chartYScale(domain: bounds.min...bounds.max)
        // The y-domain moves too: a shorter window is a much tighter range, so
        // animating the marks while snapping the scale would stretch the curve
        // in one frame and slide it in the next.
        .animation(.smooth(duration: 0.55), value: animationKey)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { $0.padding(.vertical, 8) }
        .frame(height: height)
        /*
         * Le scrub passe par `chartXSelection`, pas par un `DragGesture`.
         *
         * Un `DragGesture` posé sur un graphique dans une liste réserve la
         * séquence de touches dès le premier contact : le balayage vertical
         * n'atteignait jamais le défilement, et le tirer-pour-rafraîchir était
         * hors d'atteinte. Ni un seuil minimal ni `simultaneousGesture` n'y
         * changent rien — SwiftUI a déjà décidé à qui appartient le doigt.
         *
         * `chartXSelection` est l'API qu'Apple a écrite pour ce cas exact, et
         * qu'elle utilise dans Bourse et Santé : le scrub démarre sur un appui
         * maintenu, donc un simple balayage vertical reste au défilement. Le
         * geste est arbitré par le système au lieu d'être disputé.
         */
        .chartXSelection(value: $touched)
        .onChange(of: touched) { _, date in
            guard let date else { selection = nil; return }
            // Snap to the nearest sample, not the one to the left — the dot
            // should sit under the finger.
            let hit = points.min {
                abs($0.day.timeIntervalSince(date)) < abs($1.day.timeIntervalSince(date))
            }
            if hit?.id != selection?.id {
                selection = hit
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                /*
                 * Le repère est dessiné par-dessus, plus dedans.
                 *
                 * `RuleMark` et `PointMark` vivaient dans le `Chart`, ce qui
                 * paraît naturel et coûte tout : changer la sélection change le
                 * contenu du graphique, et Swift Charts reconstruit alors ses
                 * trois cent soixante-cinq marques — à chaque déplacement du
                 * doigt. D'où l'à-coup. Deux formes posées en surcouche se
                 * repositionnent sans que la courbe soit recalculée.
                 */
                if let selection, let plot = proxy.plotFrame,
                   let x = proxy.position(forX: selection.day),
                   let y = proxy.position(forY: selection.balance) {
                    let frame = geo[plot]
                    Rectangle()
                        .fill(Florin.text.opacity(0.18))
                        .frame(width: 1, height: frame.height)
                        .position(x: frame.origin.x + x, y: frame.midY)
                    Circle()
                        .fill(Florin.bg)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().fill(tint).frame(width: 7, height: 7))
                        .position(x: frame.origin.x + x, y: frame.origin.y + y)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// Allocation ring with the total in the middle.
struct AllocationRing: View {
    let slices: [(label: String, value: Double, color: Color)]
    let center: String
    let caption: String
    var size: CGFloat = 150

    var body: some View {
        Chart(Array(slices.enumerated()), id: \.offset) { _, slice in
            SectorMark(
                angle: .value(slice.label, slice.value),
                innerRadius: .ratio(0.72),
                angularInset: 2
            )
            .foregroundStyle(slice.color)
            .cornerRadius(4)
        }
        .frame(width: size, height: size)
        .chartLegend(.hidden)
        .overlay {
            VStack(spacing: 1) {
                Text(center)
                    .font(.system(size: size < 130 ? 14 : 16, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Florin.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(caption)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Florin.text3)
            }
            .padding(.horizontal, size * 0.18)
            // The ring's own shape says nothing about the amounts; the total in
            // the middle says all of it.
            .hiddenWhenPrivate()
        }
    }
}

/// Ring and legend side by side.
///
/// Stacked, the donut ate the width and pushed the figures into a second block
/// below it; the card was 300pt tall to show three numbers. Beside each other
/// the ring is the shape and the list is the detail, and the whole thing fits
/// in half the height.
struct AllocationCard: View {
    let slices: [(label: String, value: Double, color: Color)]
    let center: String
    let caption: String
    let locale: String
    let currency: String

    private var total: Double { slices.reduce(0) { $0 + $1.value } }

    var body: some View {
        HStack(spacing: 16) {
            AllocationRing(slices: slices, center: center, caption: caption, size: 112)

            VStack(spacing: 10) {
                ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                    HStack(spacing: 8) {
                        Circle().fill(slice.color).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(slice.label)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Florin.text2)
                                .lineLimit(1)
                            AmountText(
                                value: slice.value, locale: locale, currency: currency,
                                decimals: false, size: 14
                            )
                        }
                        Spacer(minLength: 4)
                        Text("\(Int((slice.value / max(total, 1) * 100).rounded()))%")
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Florin.text3)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
