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

    private var bounds: (min: Double, max: Double) {
        let values = points.map(\.balance)
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        // A dead-flat series must not collapse onto one row of pixels.
        return lo == hi ? (lo - max(1, abs(lo) * 0.02), hi + max(1, abs(hi) * 0.02)) : (lo, hi)
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

            if let selection {
                RuleMark(x: .value("Date", selection.day))
                    .foregroundStyle(Florin.text.opacity(0.18))
                    .lineStyle(StrokeStyle(lineWidth: 1))

                PointMark(x: .value("Date", selection.day), y: .value("Solde", selection.balance))
                    .foregroundStyle(Florin.bg)
                    .symbolSize(90)
                PointMark(x: .value("Date", selection.day), y: .value("Solde", selection.balance))
                    .foregroundStyle(tint)
                    .symbolSize(38)
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
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                guard let plot = proxy.plotFrame else { return }
                                let x = drag.location.x - geo[plot].origin.x
                                guard let date: Date = proxy.value(atX: x) else { return }
                                // Snap to the nearest sample, not the one to the
                                // left — the dot should sit under the finger.
                                let hit = points.min {
                                    abs($0.day.timeIntervalSince(date)) < abs($1.day.timeIntervalSince(date))
                                }
                                if hit?.id != selection?.id {
                                    selection = hit
                                    UISelectionFeedbackGenerator().selectionChanged()
                                }
                            }
                            .onEnded { _ in selection = nil }
                    )
            }
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
