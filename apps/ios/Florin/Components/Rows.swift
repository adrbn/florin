import SwiftUI

/// Merchant / account bubble: the category emoji when there is one, initials
/// over a stable hue otherwise.
struct Bubble: View {
    let label: String
    var emoji: String?
    var systemImage: String?
    var size: CGFloat = 40
    /// The merchant's own icon (`MerchantLogos`), over everything else.
    var logo: UIImage?

    private var tint: Color { Florin.seriesColor(for: label) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.33, style: .continuous)
                .fill(tint.opacity(0.15))
            if let logo {
                logoFace(logo)
            } else if let emoji, !emoji.isEmpty {
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

    /*
     * A touch icon is a finished square: it fills the bubble. A favicon is a
     * small mark on nothing, and blown up to fill it, it blurs — so it sits
     * on white, at the size it can bear.
     */
    private func logoFace(_ logo: UIImage) -> some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.33, style: .continuous)
        let full = LogoFetcher.pixels(logo) >= LogoFetcher.crisp
        return Image(uiImage: logo)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .padding(full ? 0 : size * 0.2)
            .frame(width: size, height: size)
            .background(Color.white)
            .clipShape(shape)
    }

    static func initials(_ label: String) -> String {
        let base = MerchantNames.shared.name(for: label) ?? PayeeText.clean(label)
        let words = base.split(whereSeparator: { " -_/".contains($0) })
        guard let first = words.first else { return "·" }
        if words.count == 1 { return String(first.prefix(2)).uppercased() }
        return (String(first.prefix(1)) + String(words[1].prefix(1))).uppercased()
    }
}

/// La marque d'un miroir : la contrepartie que Florin écrit en face d'un
/// virement. Nommée ici parce que trois endroits doivent s'accorder dessus —
/// celui qui l'écrit, celui qui la retire du nom, et les tests.
enum Transfers {
    static let mirrorMark = "↳"
}

/// Ce qu'une ligne dit sous son nom.
///
/// Extrait de la vue parce que c'est une règle, pas une mise en page : une
/// dépense montre sa catégorie et sa date, un virement montre qu'il en est un
/// et de quel côté on le regarde.
enum RowText {
    static func subtitle(
        title: String,
        category: String?,
        account: String,
        when: String,
        isTransfer: Bool,
        t: Strings = .empty
    ) -> String {
        /*
         * Un virement ne manque pas de catégorie, il n'en a pas.
         *
         * Écrire « Sans catégorie » sous ses deux jambes, c'est le mot que
         * porte une dépense qu'on a oublié de classer : une réparation
         * réclamée pour quelque chose d'intact. Et les deux jambes portent le
         * même nom — ce qui les distingue est le compte où on les regarde,
         * l'une sortant l'argent, l'autre faisant baisser la dette. La date,
         * elle, est la même des deux côtés : elle ne distingue rien.
         */
        if isTransfer {
            return join(t("v2.common.ownTransfer", "Virement"), account)
        }
        let category = category ?? t("v2.common.uncategorized", "Sans catégorie")
        // La catégorie est déjà le titre : la répéter ne dit rien de plus.
        return join(title == category ? "" : category, when)
    }

    private static func join(_ first: String, _ second: String) -> String {
        if first.isEmpty { return second }
        return second.isEmpty ? first : "\(first) · \(second)"
    }
}

/// Bank payees arrive as "ACHAT CB SUPERMARCHE 17.08.2026 CARTE 4589".
/// Same cleaning rules as the web `cleanPayee` / `humanizePayee`.
enum PayeeText {
    private static let leadWords: Set<String> = [
        "achat", "cb", "carte", "paiement", "prlv", "prel", "prelevement", "prélèvement",
        "vir", "virement", "sepa", "ach", "pos", "tpe", "retrait", "dab", "facture",
        // La marque que Florin met devant le miroir d'un virement. Elle dit
        // d'où vient la ligne, pas qui a été payé : la laisser dans le nom
        // donnait au miroir une identité propre, donc un nom à renommer à
        // part de la ligne qu'il reflète. La ligne porte déjà les flèches.
        Transfers.mirrorMark,
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
        //
        // La ponctuation qui colle à la date en fait partie : certaines
        // banques écrivent « 07.03.26, EUR 11,50 », et la virgule suffisait à
        // ce que la date ne soit plus une date — le libellé restait entier,
        // montant et numéro de carte compris, en guise de nom de commerçant.
        if let cut = words.firstIndex(where: { $0.range(of: #"^\d{2}[./-]\d{2}[./-]\d{2,4}[,;.]?$"#, options: .regularExpression) != nil }) {
            words = Array(words[..<cut])
        }
        /*
         * An account number is not a name.
         *
         * A transfer the bank has not yet booked carries no merchant at all:
         * it is announced under the account it moves to, so the row read as a
         * barcode and truncated mid-number. Dropping the IBAN leaves whatever
         * the label says besides it, and when it says nothing else the raw
         * payee still shows — better a barcode than an empty line.
         */
        words.removeAll {
            $0.range(of: #"^[A-Za-z]{2}\d{2}[A-Za-z0-9]{10,30}$"#, options: .regularExpression) != nil
        }
        let result = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? payee.trimmingCharacters(in: .whitespaces) : result
    }

    /// De-shout token by token; keep acronyms (≤3 chars, or ≤5 with no vowel).
    /// A merchant given a name of its own is shown by that name instead.
    static func humanize(_ payee: String) -> String {
        if let given = MerchantNames.shared.name(for: payee) { return given }
        // Un libellé qui ne nomme que le compte d'arrivée ne nomme personne.
        if OwnAccounts.shared.named(by: payee) {
            return Strings.device("v2.common.ownTransfer", "Virement")
        }
        return bankName(payee)
    }

    /*
     * Ce que la ligne est, quand son libellé ne dit rien.
     *
     * Une banque qui annonce un virement le nomme d'après le compte d'arrivée
     * — donc d'après son titulaire. Afficher ça, c'est renvoyer à quelqu'un
     * son propre nom en guise de commerçant. Il n'y a pas de marchand à
     * trouver : la ligne porte alors sa catégorie, la seule chose qu'on sache
     * d'elle. Un nom donné à la main passe avant, toujours.
     */
    static func title(_ payee: String, category: String?) -> String {
        if MerchantNames.shared.name(for: payee) == nil,
           OwnAccounts.shared.named(by: payee),
           let category, !category.isEmpty {
            return category
        }
        return humanize(payee)
    }

    /*
     * The merchant alone, as short as the app can say it.
     *
     * `bankName` takes off the rail and the capture date, which is all a card
     * label needs — a direct debit carries a mandate reference instead, and
     * the word "DE" the rail left behind, so it read "DE Telecom SA REF :
     * 98765432…" and truncated inside the reference. This is the trimming
     * the merchant *identity* already uses, so a row is labelled with the same
     * thing a rename would rename.
     */
    static func merchant(_ payee: String) -> String {
        MerchantNames.shared.name(for: payee) ?? deShout(MerchantNames.merchantWords(payee))
    }

    /// The bank's own label, de-shouted — what a merchant is called before
    /// anyone renames it.
    static func bankName(_ payee: String) -> String {
        deShout(clean(payee))
    }

    private static func deShout(_ label: String) -> String {
        label
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
                HStack(spacing: 6) {
                    Text(account.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Florin.text)
                    /*
                     * Which accounts keep themselves up to date.
                     *
                     * Once a ledger mixes bank-synced accounts with hand-kept
                     * ones, "why has this balance not moved" has two completely
                     * different answers, and nothing on screen said which kind
                     * you were looking at.
                     */
                    if account.isSynced == true {
                        Image(systemName: "arrow.trianglehead.2.clockwise")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(Florin.accent)
                            .padding(4)
                            .background(Florin.accent.opacity(0.16), in: Circle())
                    }
                }
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
    /// Set inside the "en prévision" group, where the header already says it —
    /// and where only the rows the bank happens to flag would wear the chip,
    /// making two of three look different for no reason a reader could act on.
    var hideUpcomingChip = false
    /// Set where every row is the same day and the header already says which.
    /// Repeating the date under each payee is noise, and it is the half that
    /// gets truncated — so the account takes its place, which is the thing a
    /// reader of one day actually cannot infer.
    var dateIsGiven = false

    let tx: Transaction
    let locale: String
    let currency: String
    var t: Strings = .empty
    /// Observed so a merchant renamed from its sheet is renamed in every list
    /// behind it at once, not at the next reload.
    @ObservedObject private var names = MerchantNames.shared
    @ObservedObject private var logos = MerchantLogos.shared

    /*
     * Ce que la ligne est, quand son libellé ne dit rien.
     *
     * Une banque qui annonce un virement le nomme d'après le compte d'arrivée
     * — donc d'après son titulaire. Afficher ça, c'est renvoyer à quelqu'un
     * son propre nom en guise de commerçant. Il n'y a pas de marchand à
     * trouver : la ligne porte alors sa catégorie, qui est la seule chose
     * qu'on sache d'elle. Un nom donné à la main passe avant, toujours.
     */
    private var title: String { PayeeText.title(tx.payee, category: tx.categoryName) }

    private var subtitle: String {
        RowText.subtitle(
            title: title,
            category: tx.categoryName,
            account: tx.accountName,
            when: dateIsGiven
                ? tx.accountName
                : DayLabel.string(tx.day, locale: locale, t: t),
            isTransfer: tx.isTransfer,
            t: t
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            // A transfer between one's own accounts keeps its arrows: the
            // "merchant" there is oneself.
            let face = tx.isTransfer ? nil : logos.face(for: tx.payee)
            Bubble(
                label: tx.categoryName ?? tx.payee,
                emoji: face?.emoji ?? tx.categoryEmoji,
                systemImage: tx.isTransfer ? "arrow.left.arrow.right" : nil,
                logo: face?.logo
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
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
                /*
                 * Both states, when both are true.
                 *
                 * "À vérifier" used to hide "En attente", and they answer
                 * different questions: one asks whether you have looked at the
                 * row, the other whether the money has actually moved. A bank
                 * announces a direct debit days before taking it — dated in the
                 * future, sitting at the top of the list — and showing only the
                 * review state made it read as spent.
                 */
                if tx.isPending, !hideUpcomingChip {
                    Text(t("v2.activity.pending", "En attente"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Florin.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Florin.accent.opacity(0.16), in: Capsule())
                }

                // Reviewing a row whose amount can still change is asking a
                // question too early; it comes back to the queue once booked.
                if tx.needsReview, !tx.isUpcoming {
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
        /*
         * La ligne entière, pas seulement ce qui y est écrit.
         *
         * Sans forme déclarée, une vue n'est touchable que là où elle peint :
         * le nom, la bulle, le montant. Les blancs entre eux ne répondaient
         * à rien. Un tap finissait par tomber juste — on vise un mot sans y
         * penser — mais l'appui long, lui, demande de rester immobile 0,5 s
         * sur un pixel peint, et le menu contextuel ne s'ouvrait donc
         * quasiment jamais depuis l'Aperçu. La ligne déclare sa surface, une
         * fois, pour tous les écrans qui l'affichent.
         */
        .contentShape(Rectangle())
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


/// The rows a bank has announced but not yet booked, folded away.
///
/// A direct debit published four days early, or an authorisation still
/// settling, is not what anyone opens this screen to read — and interleaved by
/// date it sits *above* everything that actually happened, because its date is
/// in the future. Out of the totals already; out of the way here, behind one
/// line that says how many and what they come to.
/*
 * Un pli, un décompte, un total — et ce qu'on y range.
 *
 * Générique sur l'élément, et plus seulement sur les transactions : un
 * échéancier n'est pas une opération, mais il attend de la même façon, se
 * replie de la même façon et totalise de la même façon. Le total est donné de
 * l'extérieur pour cette raison — ce qu'il reste à payer sur quatre achats
 * n'est pas la somme de lignes qu'on afficherait.
 */
struct UpcomingGroup<Item: Identifiable, Row: View>: View {
    let items: [Item]
    /// Ce que le groupe pèse, en haut à droite du pli.
    let total: Double
    let locale: String
    let currency: String
    let t: Strings
    /// The glyph and its colour. Defaults to the upcoming clock; the review
    /// queue passes its own so the two groups read as different kinds of
    /// waiting rather than as one list split in half.
    var symbol: String = "clock"
    var tint: Color = Florin.accent
    /// Overrides the "{count} en prévision" line.
    var caption: String?
    /// Actions belonging to the group, drawn inside the card under the rows
    /// and only while it is open — a line of links floating under a closed
    /// card belongs to nothing on screen.
    var footer: AnyView?
    @Binding var expanded: Bool
    @ViewBuilder var row: (Item) -> Row

    init(
        items: [Item], total: Double, locale: String, currency: String, t: Strings,
        symbol: String = "clock", tint: Color = Florin.accent, caption: String? = nil,
        footer: AnyView? = nil, expanded: Binding<Bool>,
        @ViewBuilder row: @escaping (Item) -> Row
    ) {
        self.items = items
        self.total = total
        self.locale = locale
        self.currency = currency
        self.t = t
        self.symbol = symbol
        self.tint = tint
        self.caption = caption
        self.footer = footer
        self._expanded = expanded
        self.row = row
    }

    /// Le cas d'origine : des opérations, dont le total est la somme.
    init(
        transactions: [Transaction], locale: String, currency: String, t: Strings,
        symbol: String = "clock", tint: Color = Florin.accent, caption: String? = nil,
        footer: AnyView? = nil, expanded: Binding<Bool>,
        @ViewBuilder row: @escaping (Transaction) -> Row
    ) where Item == Transaction {
        self.init(
            items: transactions, total: transactions.reduce(0) { $0 + $1.amount },
            locale: locale, currency: currency, t: t, symbol: symbol, tint: tint,
            caption: caption, footer: footer, expanded: expanded, row: row
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.snappy(duration: 0.24)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(tint)
                    Text(
                        caption
                            ?? t("v2.activity.upcomingCount", "{count} en prévision",
                                 ["count": items.count])
                    )
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Florin.text2)
                    Spacer(minLength: 8)
                    AmountText(
                        value: total, locale: locale, currency: currency,
                        decimals: false, signed: true, tone: .muted, size: 13,
                        weight: .semibold
                    )
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Florin.text3)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.horizontal, Florin.gutter)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(items) { item in
                    Hairline()
                    row(item)
                }
                if let footer {
                    Hairline()
                    footer
                }
            }
        }
        .florinSurface()
    }
}
