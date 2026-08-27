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
    @ViewBuilder var middle: Middle
    @ViewBuilder var trailing: Trailing

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
                Image(systemName: back ? "xmark" : "gearshape")
                    .font(.system(size: back ? 17 : 21, weight: back ? .bold : .regular))
                    .foregroundStyle(Florin.text2)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                back
                    ? Strings.device("v2.common.close", "Fermer")
                    : Strings.device("v2.settings.title", "Réglages")
            )

            middle
            trailing
        }
        .padding(.horizontal, Florin.gutter)
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
    @ViewBuilder var sub: Sub

    var body: some View {
        VStack(spacing: 10) {
            Text(caption)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Florin.text2)

            HeroAmount(value: value, locale: locale, currency: currency, size: size)
                .contentTransition(.numericText())

            sub.frame(minHeight: 20)
        }
        .frame(maxWidth: .infinity)
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

/// iOS 26 fades content into the bars instead of hard-clipping it.
struct SoftScrollEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
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
     * Fills the width when the chips fit, scrolls when they do not.
     *
     * A scroll view sizes itself to its content, so four short chips left a
     * ragged gap down the right of the screen — the row read as an unfinished
     * list rather than a set of tabs. `ViewThatFits` takes the laid-out row
     * when there is room for it and falls back to scrolling for a longer set,
     * which is the only honest way to do this without hard-coding a count.
     */
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(options, id: \.value) { chip($0, fill: true) }
            }
            .padding(.horizontal, Florin.gutter)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.value) { chip($0, fill: false) }
                }
                .padding(.horizontal, Florin.gutter)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func chip(
        _ option: (value: Value, label: String, badge: Int),
        fill: Bool
    ) -> some View {
        let active = option.value == selection
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy(duration: 0.2)) { selection = option.value }
        } label: {
            HStack(spacing: 6) {
                Text(option.label)
                    .font(.system(size: 14, weight: active ? .semibold : .medium))
                    .lineLimit(1)
                    // Filling the width makes every chip a quarter of the row,
                    // and "Tendances" does not fit a quarter at 14pt. Shrinking
                    // a hair is invisible; truncating to "Tendan…" is not.
                    .minimumScaleFactor(fill ? 0.72 : 1)
                if option.badge > 0 {
                    Text("\(option.badge)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Florin.negative, in: Capsule())
                }
            }
            .foregroundStyle(active ? Florin.text : Florin.text2)
            .padding(.horizontal, fill ? 6 : 15)
            .padding(.vertical, 9)
            .frame(maxWidth: fill ? .infinity : nil)
            .modifier(ChipGlass(active: active))
        }
        .buttonStyle(.plain)
    }
}

private struct ChipGlass: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
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
