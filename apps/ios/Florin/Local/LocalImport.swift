import Foundation

/*
 * A statement, read on the phone.
 *
 * PSD2 exposes what a bank chooses to expose, and for a French savings account
 * that is often nothing at all. The statement can still be downloaded from the
 * bank's own site — so the gap is not the data, it is the way in. This is that
 * way in: the same CSV and OFX the desktop build has read since the beginning,
 * ported rather than reinvented, so a file that works on one works on both.
 *
 * Deliberately French-first where the two conventions collide. `03/04/2026` is
 * the third of April, not the fourth of March: the desktop parser tries the
 * European reading first and falls back to the American one, which quietly
 * turns `04/13/2026` into month thirteen. Here an ambiguous date is European
 * and a date that cannot be read that way is refused, because a wrong date in a
 * ledger is worse than a row that did not import.
 */
enum LocalImport {
    struct Row {
        let day: String        // yyyy-MM-dd
        let payee: String
        let amount: Double
        let memo: String?
    }

    /*
     * Which way round the day and the month are.
     *
     * Reading every ambiguous date as European is right for the person this app
     * was written for and silently wrong for anyone else: "04/12/2026" becomes
     * the fourth of December instead of the twelfth of April, with no error and
     * no way to notice. A single date cannot say which it is — but a file
     * usually can, because somewhere in a month of transactions there is a day
     * above the twelfth.
     */
    enum DateOrder {
        case dayFirst
        case monthFirst
        /// Every date in the file has both parts under thirteen. Read as
        /// day-first, and said out loud rather than assumed.
        case ambiguous
        /// Neither reading fits every row. Refused rather than halved.
        case inconsistent

        var dayIsFirst: Bool { self != .monthFirst }
    }

    struct Parsed {
        var rows: [Row]
        var order: DateOrder = .dayFirst
        /// Lines that looked like data and whose date would not read. Counted
        /// rather than dropped: a file half of whose rows are missing should
        /// not import looking complete.
        var rejected: Int = 0
    }

    struct Preview {
        var rows: [Row] = []
        var duplicates: Int = 0
        var earliest: String?
        var latest: String?
        var total: Double = 0
    }

    /*
     * What a column can be called, gathered from real exports.
     *
     * The amount pattern is anchored at the start and deliberately not at the
     * end: banks qualify the column rather than rename it — "Montant(EUROS)",
     * "montant_operation", "Montant (EUR)", "Montant net". Anchoring both ends
     * rejected all four while the leading anchor still keeps "Original Amount"
     * and "accountbalance" out, and in a file with two amount columns the first
     * match is the euro one.
     */
    enum Role {
        static let date = "date|datum|valeur"
        static let payee =
            "payee|description|libell|label|merchant|name|nature|motif"
            + "|bénéficiaire|beneficiaire|empfänger|contrepartie|intitul|objet"
        static let amount = "^\"?(amount|montant|betrag|somme)"
        static let debit = "debit|débit|ausgabe|retrait|paid out|sortie"
        static let credit = "credit|crédit|einnahme|depot|dépôt|paid in|entrée"
        static let memo = "memo|note|reference|référence|comment|détail|detail"
    }

    enum Failure: LocalizedError {
        case unreadable
        case noDateColumn
        case noAmountColumn
        case empty

        var errorDescription: String? {
            switch self {
            case .unreadable: "Ce fichier n'a pas pu être lu."
            case .noDateColumn: "Aucune colonne de date trouvée."
            case .noAmountColumn: "Aucune colonne de montant trouvée."
            case .empty: "Aucune opération dans ce fichier."
            }
        }
    }

    // MARK: - Reading a file

    static func parse(data: Data, fileName: String) throws -> Parsed {
        /*
         * Latin-1 as the fallback, not a failure.
         *
         * French banks still export windows-1252: one accented character in a
         * payee and a strict UTF-8 read returns nil for the whole file. The
         * accents come back wrong under Latin-1 in the rare mismatch, which is
         * a cosmetic loss against losing the statement entirely.
         */
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(data: data, encoding: .windowsCP1252)
        guard let text, !text.isEmpty else { throw Failure.unreadable }

        let ext = (fileName as NSString).pathExtension.lowercased()
        // OFX carries YYYYMMDD, which has no ambiguity to resolve.
        let parsed = (ext == "ofx" || ext == "qfx")
            ? Parsed(rows: parseOFX(text))
            : try parseCSV(text)
        guard !parsed.rows.isEmpty else { throw Failure.empty }
        return parsed
    }

    /*
     * Decided over the whole file, and by what the calendar allows.
     *
     * Neither hledger nor GnuCash will guess this — they make you declare the
     * format, and refuse or ask when you have not. A phone reading a file has
     * nowhere to put that question before it is answered, so the file is asked
     * first: a component above twelve can only be a day, and a date the
     * calendar rejects — the thirty-first of February — refutes the reading
     * that produced it. Only when the file will say nothing is the person
     * asked, and they are told which way it was read either way.
     */
    static func order(of dates: [String]) -> DateOrder {
        let triples = dates.compactMap { raw -> (Int, Int, Int)? in
            let parts = raw.prefix(10).split(whereSeparator: { "/-.".contains($0) })
            guard parts.count == 3, let a = Int(parts[0]), let b = Int(parts[1]),
                  let c = Int(parts[2])
            else { return nil }
            // A four-digit leading group is a year, and those dates are already
            // unambiguous — they say nothing about the rest of the file.
            guard parts[0].count < 4 else { return nil }
            return (a, b, c)
        }
        guard !triples.isEmpty else { return .ambiguous }

        /*
         * The year has to be placed before the day and the month can be.
         *
         * "26-01-02" is either the twenty-sixth of January or the second of
         * January 2026, and testing "26 > 12, therefore day-first" answers a
         * question that was never asked. When every group is two digits and
         * none exceeds thirty-one, nothing here can tell.
         */
        guard triples.allSatisfy({ $0.2 > 31 || String($0.2).count == 4 || $0.2 > 12 })
                || triples.contains(where: { $0.0 > 31 || $0.1 > 31 })
        else {
            // The last group is small too: could be a year, could be a day.
            return triples.allSatisfy({ $0.2 <= 12 }) ? .ambiguous : .dayFirst
        }

        let dayFirstHolds = triples.allSatisfy { valid(day: $0.0, month: $0.1, year: $0.2) }
        let monthFirstHolds = triples.allSatisfy { valid(day: $0.1, month: $0.0, year: $0.2) }
        switch (dayFirstHolds, monthFirstHolds) {
        case (true, false): return .dayFirst
        case (false, true): return .monthFirst
        case (true, true): return .ambiguous
        /*
         * Neither reading fits the whole file.
         *
         * The usual cause is a statement opened in Excel under an American
         * locale: it silently swaps the rows it can read as month-first and
         * leaves the rest alone, so the file ends up carrying both. Picking one
         * would import half of it wrong, quietly.
         */
        case (false, false): return .inconsistent
        }
    }

    private static func valid(day: Int, month: Int, year: Int) -> Bool {
        guard month >= 1, month <= 12, day >= 1 else { return false }
        return day <= daysIn(month: month, year: century(year))
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: 31
        case 4, 6, 9, 11: 30
        default: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        }
    }

    /*
     * Two digits, resolved backwards.
     *
     * `+ 2000` turns "99" into 2099. A statement is a record of what has
     * happened, so the year is the most recent one that reading allows.
     */
    static func century(_ raw: Int) -> Int {
        guard raw < 100 else { return raw }
        let calendar = Calendar(identifier: .gregorian)
        let thisYear = calendar.component(.year, from: Date())
        let candidate = 2000 + raw
        return candidate > thisYear + 1 ? candidate - 100 : candidate
    }

    // MARK: - CSV

    static func parseCSV(_ text: String) throws -> Parsed {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        /*
         * The header is rarely the first line, and rarely the first line that
         * mentions a date either.
         *
         * French banks open a statement with the account number, the balance
         * and the period — and La Banque Postale's preamble contains a line
         * that literally begins "Date", three lines above the real header.
         * Looking for a date is not enough to find the table; a preamble line
         * naming one scores a single role, while a header scores several. Two
         * distinct roles is the test: a date column and something holding an
         * amount. Nothing above the line that passes is read.
         */
        var headerAt = 0
        var delimiter: Character = ","
        var columns: [String] = []
        for (index, line) in lines.prefix(20).enumerated() {
            let guess: Character = line.contains("\t") ? "\t"
                : line.contains(";") ? ";" : ","
            let cells = split(line, by: guess).map {
                $0.lowercased().trimmingCharacters(in: .whitespaces)
            }
            guard cells.count >= 2 else { continue }
            func names(_ pattern: String) -> Bool {
                cells.contains { $0.range(of: pattern, options: .regularExpression) != nil }
            }
            guard names(Role.date) else { continue }
            guard names(Role.amount) || names(Role.debit) || names(Role.credit) else { continue }
            headerAt = index
            delimiter = guess
            columns = cells
            break
        }
        guard !columns.isEmpty else { throw Failure.noDateColumn }

        func find(_ pattern: String) -> Int? {
            columns.firstIndex { $0.range(of: pattern, options: .regularExpression) != nil }
        }
        guard let dateAt = find(Role.date) else { throw Failure.noDateColumn }
        let payeeAt = find(Role.payee)
        let amountAt = find(Role.amount)
        let debitAt = find(Role.debit)
        let creditAt = find(Role.credit)
        let memoAt = find(Role.memo)
        guard amountAt != nil || debitAt != nil || creditAt != nil else {
            throw Failure.noAmountColumn
        }

        // Two passes: the first only to learn which way round the dates are,
        // because that cannot be decided from the row being read.
        let body = Array(lines.dropFirst(headerAt + 1))
        let order = Self.order(of: body.compactMap { line -> String? in
            let cells = split(line, by: delimiter)
            guard dateAt < cells.count else { return nil }
            return cells[dateAt].trimmingCharacters(in: .whitespaces)
        })

        var out: [Row] = []
        var rejected = 0
        for line in body {
            let cells = split(line, by: delimiter)
            func cell(_ index: Int?) -> String {
                guard let index, index < cells.count else { return "" }
                return cells[index].trimmingCharacters(in: .whitespaces)
            }
            guard let day = date(from: cell(dateAt), dayFirst: order.dayIsFirst) else {
                // A trailing "Solde en début de période" carries no date and is
                // not a loss; a row that should have parsed is.
                if !cell(dateAt).isEmpty { rejected += 1 }
                continue
            }

            let amount: Double
            if let amountAt, !cell(amountAt).isEmpty {
                amount = number(cell(amountAt)) ?? 0
            } else {
                // Two columns, one of which is filled: a credit is money in, a
                // debit is money out whichever sign the bank wrote it with.
                let credit = number(cell(creditAt)) ?? 0
                let debit = number(cell(debitAt)) ?? 0
                amount = credit != 0 ? abs(credit) : -abs(debit)
            }
            guard amount != 0 else { continue }

            let payee = cell(payeeAt)
            out.append(
                Row(
                    day: day,
                    payee: payee.isEmpty ? "Import" : payee,
                    amount: amount,
                    memo: cell(memoAt).isEmpty ? nil : cell(memoAt)
                )
            )
        }
        return Parsed(rows: out, order: order, rejected: rejected)
    }

    /// Quote-aware, because a French label contains the delimiter often enough
    /// to matter: `"CARREFOUR MARKET; PARIS"`.
    private static func split(_ line: String, by delimiter: Character) -> [String] {
        var cells: [String] = []
        var current = ""
        var quoted = false
        for character in line {
            if character == "\"" {
                quoted.toggle()
            } else if character == delimiter, !quoted {
                cells.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        cells.append(current)
        return cells
    }

    // MARK: - OFX

    static func parseOFX(_ text: String) -> [Row] {
        // The XML dialect first; the SGML one — unclosed tags — is what most
        // French banks actually emit, so it is a fallback rather than a
        // curiosity.
        var blocks = matches(in: text, pattern: "<STMTTRN>([\\s\\S]*?)</STMTTRN>")
        if blocks.isEmpty {
            let chunks = text.components(separatedBy: "<STMTTRN>")
            blocks = Array(chunks.dropFirst())
        }
        return blocks.compactMap { block in
            guard let raw = tag("DTPOSTED", in: block),
                  let day = date(from: raw),
                  let amount = number(tag("TRNAMT", in: block) ?? ""), amount != 0
            else { return nil }
            let payee = tag("NAME", in: block) ?? tag("MEMO", in: block) ?? "Import"
            return Row(day: day, payee: payee, amount: amount, memo: tag("MEMO", in: block))
        }
    }

    private static func tag(_ name: String, in block: String) -> String? {
        matches(in: block, pattern: "<\(name)>([^<\r\n]*)").first?
            .trimmingCharacters(in: .whitespaces)
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            guard $0.numberOfRanges > 1, let r = Range($0.range(at: 1), in: text) else { return nil }
            return String(text[r])
        }
    }

    // MARK: - Fields

    /// French numbers: `1 234,56`, `-1.234,56`, and a trailing minus some banks
    /// still emit. A thin space is not a space to `Double`.
    static func number(_ raw: String) -> Double? {
        var value = raw
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "EUR", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        if value.hasSuffix("-") { value = "-" + value.dropLast() }
        /*
         * Whichever separator comes last is the decimal one.
         *
         * The first rule here was "a comma means the comma is decimal", which
         * is true of 1.234,56 and quietly wrong about 1,234.56 — it stripped
         * the dot and returned 1.23456, so a British or American statement
         * imported with every amount divided by a thousand and no error to say
         * so. Position settles it: in a well-formed number the decimal mark is
         * the rightmost separator, and everything before it groups thousands.
         */
        let lastComma = value.lastIndex(of: ",")
        let lastDot = value.lastIndex(of: ".")
        switch (lastComma, lastDot) {
        case let (comma?, dot?):
            let decimal: Character = comma > dot ? "," : "."
            let grouping: Character = decimal == "," ? "." : ","
            value = value.replacingOccurrences(of: String(grouping), with: "")
                .replacingOccurrences(of: String(decimal), with: ".")
        /*
         * One separator, and the digits after it decide.
         *
         * "1,234" is one-and-a-bit in France and a thousand-odd in Britain;
         * "1.234" is the same problem mirrored. Nothing in the character
         * settles it — but money is written with one or two decimals and
         * thousands are grouped in threes, so the count does. Exactly three
         * digits after the separator means it groups; anything else means it
         * divides.
         *
         * It is a heuristic, and it is wrong for an amount written with three
         * decimals — 12,500 read as twelve thousand five hundred. Bank
         * statements do not do that; unit prices sometimes do.
         */
        case let (comma?, nil):
            value = value.replacingOccurrences(
                of: ",", with: value.distance(from: value.index(after: comma), to: value.endIndex) == 3 ? "" : "."
            )
        case let (nil, dot?):
            if value.distance(from: value.index(after: dot), to: value.endIndex) == 3 {
                value = value.replacingOccurrences(of: ".", with: "")
            }
        default:
            break
        }
        return Double(value)
    }

    /// ISO first, then European, then OFX's `YYYYMMDD`. Never American: this
    /// app is French-first and `03/04` has to mean one thing.
    static func date(from raw: String, dayFirst: Bool = true) -> String? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }

        if value.count >= 10, value.prefix(4).allSatisfy(\.isNumber),
           Array(value)[4] == "-" {
            return String(value.prefix(10))
        }
        if value.count >= 8, value.prefix(8).allSatisfy(\.isNumber) {
            let digits = value.prefix(8)
            let year = digits.prefix(4)
            let month = digits.dropFirst(4).prefix(2)
            let day = digits.dropFirst(6).prefix(2)
            return "\(year)-\(month)-\(day)"
        }
        let parts = value.prefix(10).split(whereSeparator: { "/-.".contains($0) })
        guard parts.count == 3, let first = Int(parts[0]), let second = Int(parts[1]),
              var y = Int(parts[2])
        else { return nil }
        let d = dayFirst ? first : second
        let m = dayFirst ? second : first
        y = century(y)
        // The calendar, not just the range: the thirty-first of February is
        // what tells one reading of a file from the other.
        guard valid(day: d, month: m, year: y) else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}
