import SwiftUI

/// Currency formatting, matching the web `splitAmount`.
enum Money {
    nonisolated(unsafe) private static var cache: [String: NumberFormatter] = [:]

    static func formatter(locale: String, currency: String, decimals: Bool, signed: Bool) -> NumberFormatter {
        let key = "\(locale)|\(currency)|\(decimals)|\(signed)"
        if let hit = cache[key] { return hit }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: locale)
        f.currencyCode = currency
        f.minimumFractionDigits = decimals ? 2 : 0
        f.maximumFractionDigits = decimals ? 2 : 0
        if signed { f.positivePrefix = "+" + f.positivePrefix }
        cache[key] = f
        return f
    }

    static func string(
        _ value: Double,
        locale: String,
        currency: String,
        decimals: Bool = true,
        signed: Bool = false
    ) -> String {
        let text = formatter(locale: locale, currency: currency, decimals: decimals, signed: signed)
            .string(from: NSNumber(value: value)) ?? "—"
        // A hyphen-minus reads as a bullet next to lining figures.
        return text.replacingOccurrences(of: "-", with: "\u{2212}")
    }

    /// "12,3 k €" for axes and chips.
    static func compact(_ value: Double, locale: String, currency: String) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: locale)
        f.numberStyle = .currency
        f.currencyCode = currency
        f.maximumFractionDigits = abs(value) >= 10_000 ? 0 : 1
        if abs(value) >= 1000 {
            let scaled = value / 1000
            f.maximumFractionDigits = 1
            let n = f.string(from: NSNumber(value: scaled)) ?? "—"
            /*
             * Where the "k" goes depends on where the currency sign goes.
             *
             * French writes "12,3 k €" — sign trailing, so "k" slots in
             * before it. English writes "€12.3k" — sign leading, so the same
             * substitution produced "k €2.4", with the multiplier stranded in
             * front of the whole amount. The sign's own position is what
             * decides, not a hardcoded assumption about one locale.
             */
            let symbol = currencySymbol(locale: locale, currency: currency)
            if n.hasPrefix(symbol) || n.hasPrefix("\u{2212}" + symbol) || n.hasPrefix("-" + symbol) {
                return n + "k"
            }
            return n.replacingOccurrences(of: symbol, with: "k " + symbol)
        }
        return f.string(from: NSNumber(value: value)) ?? "—"
    }

    static func currencySymbol(locale: String, currency: String) -> String {
        formatter(locale: locale, currency: currency, decimals: true, signed: false).currencySymbol ?? currency
    }

    /*
     * A share count, written the way a broker writes it.
     *
     * Not currency: 569 units of a fund is not 569 €, and formatting it as
     * money on a screen full of money is how someone reads a quantity as a
     * balance. Fractional shares are real — brokers sell them by the euro —
     * so the decimals stay when they exist and go when they do not.
     */
    static func quantity(_ value: Double, locale: String) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: locale)
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = value == value.rounded() ? 0 : 4
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func percent(_ value: Double?, locale: String, digits: Int = 1) -> String {
        guard let value, value.isFinite else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .percent
        f.locale = Locale(identifier: locale)
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        f.positivePrefix = "+" + (f.positivePrefix ?? "")
        return (f.string(from: NSNumber(value: value / 100)) ?? "—")
            .replacingOccurrences(of: "-", with: "\u{2212}")
    }
}

/// The headline figure, with the cents typographically demoted.
///
/// This is the single move that separates a premium finance app from a
/// spreadsheet: "7 769" at full size, ",41 €" small and muted beside it. Doing
/// it needs the integer part and the fraction as separate runs, which means
/// splitting the formatted string on the locale's decimal separator rather
/// than assembling it by hand — the grouping, the symbol side and the sign all
/// have to stay whatever the locale says they are.
struct HeroAmount: View {
    let value: Double
    let locale: String
    let currency: String
    var size: CGFloat = 52
    var tone: Color = Florin.text

    var body: some View {
        let text = Money.string(value, locale: locale, currency: currency)
        let separator = Locale(identifier: locale).decimalSeparator ?? ","

        // Split at the LAST separator so a grouping character that happens to
        // match (some locales group with ".") cannot cut the number in half.
        if let range = text.range(of: separator, options: .backwards) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(text[text.startIndex..<range.lowerBound])
                    .font(.system(size: size, weight: .light))
                Text(text[range.lowerBound...])
                    .font(.system(size: size * 0.44, weight: .regular))
                    .foregroundStyle(Florin.text3)
            }
            .monospacedDigit()
            .kerning(-1.2)
            .foregroundStyle(tone)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .redactable(tint: tone, minWidth: size * 2.4)
        } else {
            Text(text)
                .font(.system(size: size, weight: .light))
                .monospacedDigit()
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .redactable(tint: tone, minWidth: size * 2.4)
        }
    }
}

/// Inline amount for rows and chips.
struct AmountText: View {
    let value: Double
    let locale: String
    let currency: String
    var decimals: Bool = true
    var signed: Bool = false
    var tone: Tone = .neutral
    var size: CGFloat = 15
    var weight: Font.Weight = .medium

    enum Tone { case neutral, auto, muted, positive, negative }

    private var color: Color {
        switch tone {
        case .neutral: return Florin.text
        case .muted: return Florin.text3
        case .positive: return Florin.positive
        case .negative: return Florin.negative
        case .auto: return value > 0 ? Florin.positive : (value < 0 ? Florin.negative : Florin.text)
        }
    }

    var body: some View {
        Text(Money.string(value, locale: locale, currency: currency, decimals: decimals, signed: signed))
            .font(.system(size: size, weight: weight))
            .monospacedDigit()
            .foregroundStyle(color)
            .redactable(tint: color, minWidth: size * 2.2)
    }
}
