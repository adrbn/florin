import SwiftUI

/// Merchant / account bubble: the category emoji when there is one, initials
/// over a stable hue otherwise.
struct Bubble: View {
    let label: String
    var emoji: String?
    var systemImage: String?
    var size: CGFloat = 40

    private var tint: Color { Florin.seriesColor(for: label) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.33, style: .continuous)
                .fill(tint.opacity(0.15))
            if let emoji, !emoji.isEmpty {
                Text(emoji).font(.system(size: size * 0.42))
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(tint)
            } else {
                Text(Self.initials(label))
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
    }

    static func initials(_ label: String) -> String {
        let words = PayeeText.clean(label).split(whereSeparator: { " -_/".contains($0) })
        guard let first = words.first else { return "·" }
        if words.count == 1 { return String(first.prefix(2)).uppercased() }
        return (String(first.prefix(1)) + String(words[1].prefix(1))).uppercased()
    }
}

/// Bank payees arrive as "ACHAT CB CRF ST MARTIN 17.08.2026 CARTE 4589".
/// Same cleaning rules as the web `cleanPayee` / `humanizePayee`.
enum PayeeText {
    private static let leadWords: Set<String> = [
        "achat", "cb", "carte", "paiement", "prlv", "prelevement", "prélèvement",
        "vir", "virement", "sepa", "ach", "pos", "tpe", "retrait", "dab", "facture",
    ]

    static func clean(_ payee: String) -> String {
        var words = payee.split(separator: " ").map(String.init)
        // Drop the rail prefix — up to three stacked ("CB PAIEMENT CARREFOUR").
        var dropped = 0
        while dropped < 3, let head = words.first, leadWords.contains(head.lowercased()) {
            words.removeFirst()
            dropped += 1
        }
        // Drop the trailing capture date and anything after it.
        if let cut = words.firstIndex(where: { $0.range(of: #"^\d{2}[./-]\d{2}[./-]\d{2,4}$"#, options: .regularExpression) != nil }) {
            words = Array(words[..<cut])
        }
        let result = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? payee.trimmingCharacters(in: .whitespaces) : result
    }

    /// De-shout token by token; keep acronyms (≤3 chars, or ≤5 with no vowel).
    static func humanize(_ payee: String) -> String {
        clean(payee)
            .split(separator: " ")
            .map { word -> String in
                let s = String(word)
                guard s == s.uppercased() else { return s }
                let vowelless = s.rangeOfCharacter(from: CharacterSet(charactersIn: "AEIOUY")) == nil
                if s.count <= 3 || (s.count <= 5 && vowelless) { return s }
                return s.prefix(1) + s.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }
}

struct AccountRowView: View {
    let account: Account
    let locale: String
    let currency: String

    private var icon: String {
        switch account.kind {
        case "checking": return "creditcard.fill"
        case "savings": return "banknote.fill"
        case "cash": return "eurosign.circle.fill"
        case "broker_cash", "broker_portfolio": return "chart.line.uptrend.xyaxis"
        case "loan": return "building.columns.fill"
        default: return "wallet.bifold.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Bubble(label: account.name, emoji: account.displayIcon, systemImage: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Florin.text)
                if let institution = account.institution, !institution.isEmpty {
                    Text(institution)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Florin.text2)
                }
            }
            Spacer(minLength: 8)
            AmountText(
                value: account.displayValue,
                locale: locale,
                currency: currency,
                decimals: false,
                tone: account.isLoan ? .negative : .neutral
            )
        }
        .padding(.horizontal, Florin.gutter)
        .padding(.vertical, 12)
    }
}

struct TransactionRowView: View {
    let tx: Transaction
    let locale: String
    let currency: String
    var t: Strings = .empty

    private var subtitle: String {
        let category = tx.categoryName ?? t("v2.common.uncategorized", "Sans catégorie")
        return "\(category) · \(DayLabel.string(tx.day, locale: locale, t: t))"
    }

    var body: some View {
        HStack(spacing: 12) {
            Bubble(
                label: tx.categoryName ?? tx.payee,
                emoji: tx.categoryEmoji,
                systemImage: tx.isTransfer ? "arrow.left.arrow.right" : nil
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(PayeeText.humanize(tx.payee))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Florin.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Florin.text2)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                AmountText(value: tx.amount, locale: locale, currency: currency, signed: true, tone: .auto)
                if tx.needsReview {
                    Text(t("v2.activity.needsReview", "À vérifier"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Florin.warn)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Florin.warn.opacity(0.16), in: Capsule())
                } else if tx.isScheduled {
                    Text(t("v2.activity.scheduled", "Prévu"))
                        .font(.system(size: 11)).foregroundStyle(Florin.text3)
                }
            }
        }
        .padding(.horizontal, Florin.gutter)
        .padding(.vertical, 12)
    }
}

enum DayLabel {
    static func string(_ date: Date, locale: String, t: Strings = .empty, now: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return t("v2.common.today", "Aujourd'hui") }
        if cal.isDateInYesterday(date) { return t("v2.common.yesterday", "Hier") }
        let f = DateFormatter()
        f.locale = Locale(identifier: locale)
        f.setLocalizedDateFormatFromTemplate(
            cal.component(.year, from: date) == cal.component(.year, from: now) ? "EEEdMMM" : "dMMMy"
        )
        return f.string(from: date)
    }
}

/// A card that hosts rows edge to edge, with hairlines between them.
struct RowGroup<Content: View>: View {
    /// Colours the whole card rather than its rows — see `florinSurface`.
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .florinSurface(tint: tint)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Florin.text.opacity(0.07))
            .frame(height: 1)
            .padding(.leading, Florin.gutter)
    }
}
