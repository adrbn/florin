import Foundation

/// The date a card purchase actually happened, dug out of the bank's own text.
///
/// A port of `extractTrueDateFromText`, which the server already applies — and
/// the reason the two sides disagreed about when things happened. Many European
/// banks book a card payment on the next business day and never at weekends, so
/// a Friday evening bar tab arrives dated Monday. The real date is usually
/// sitting in the free-text line:
///
///     "ACHAT CB BAR LO FARO 14.04.26 EUR 7,00 CARTE NO 469 OC APPLE PAY"
///
/// Matching a bank row against one the server had already corrected therefore
/// meant matching two different days. Reading the same date here removes the
/// disagreement at its source, instead of widening a tolerance window until it
/// starts merging genuinely different purchases of the same amount.
enum TrueDate {
    private static let pattern = try? NSRegularExpression(
        pattern: #"\b(\d{1,2})[./\-](\d{1,2})[./\-](\d{2,4})\b"#
    )

    /// The first plausible `DD.MM.YY` in `text`, when it sits within
    /// `maxDrift` days of the booked date.
    ///
    /// The window matters: a string of digits in a reference number can parse
    /// as a valid date, and a merchant's "01.01.20" would drag a transaction
    /// years out of place. Outside the window the booked date is kept — a
    /// slightly late date is a nuisance, a wrong year corrupts the timeline.
    static func extract(from text: String, bookedAt: Date, maxDrift: Int = 14) -> Date? {
        guard let pattern, !text.isEmpty else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let limit = Double(maxDrift) * 86_400

        var found: Date?
        pattern.enumerateMatches(in: text, range: range) { match, _, stop in
            guard found == nil, let match, match.numberOfRanges == 4 else { return }
            func part(_ index: Int) -> Int? {
                guard let r = Range(match.range(at: index), in: text) else { return nil }
                return Int(text[r])
            }
            guard let day = part(1), let month = part(2), let rawYear = part(3) else { return }

            let year = rawYear >= 1900 ? rawYear : (rawYear >= 100 ? 2000 + rawYear % 100 : 2000 + rawYear)
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!

            // `date(from:)` happily rolls 31 February into March; comparing the
            // parts back is what rejects a match that is not a real date.
            guard let candidate = calendar.date(from: components) else { return }
            let back = calendar.dateComponents([.year, .month, .day], from: candidate)
            guard back.year == year, back.month == month, back.day == day else { return }

            if abs(candidate.timeIntervalSince(bookedAt)) <= limit {
                found = candidate
                stop.pointee = true
            }
        }
        return found
    }
}
