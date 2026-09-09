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
        let values = points.map(\.balance)
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        // A dead-flat series must not collapse onto one row of pixels.
        bounds = lo == hi
            ? (lo - max(1, abs(lo) * 0.02), hi + max(1, abs(hi) * 0.02))
            : (lo, hi)
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Date", point.day),
                    yStart: .value("Base", bounds.min),
                    yEnd: .value("Solde", point.balance)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [tint.opacity(0.22), tint.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(x: .value("Date", point.day), y: .value("Solde", point.balance))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
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
