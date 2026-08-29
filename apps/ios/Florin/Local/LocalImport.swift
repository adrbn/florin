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

    struct Preview {
        var rows: [Row] = []
        var duplicates: Int = 0
        var earliest: String?
        var latest: String?
        var total: Double = 0
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

    static func parse(data: Data, fileName: String) throws -> [Row] {
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
        let rows = (ext == "ofx" || ext == "qfx") ? parseOFX(text) : try parseCSV(text)
        guard !rows.isEmpty else { throw Failure.empty }
        return rows
    }

    // MARK: - CSV

    static func parseCSV(_ text: String) throws -> [Row] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        guard let header = lines.first else { throw Failure.empty }

        // Guessed from the header, because a French export is semicolons and an
        // English one is commas, and both call themselves .csv.
        let delimiter: Character = header.contains("\t") ? "\t"
            : header.contains(";") ? ";" : ","
        let columns = split(header, by: delimiter).map {
            $0.lowercased().trimmingCharacters(in: .whitespaces)
        }

        func find(_ pattern: String) -> Int? {
            columns.firstIndex { $0.range(of: pattern, options: .regularExpression) != nil }
        }
        guard let dateAt = find("date|datum|valeur") else { throw Failure.noDateColumn }
        let payeeAt = find("payee|description|libell|label|merchant|name|nature|motif")
        let amountAt = find("^\"?(amount|montant|betrag|somme)\"?$")
        let debitAt = find("debit|débit|ausgabe|retrait")
        let creditAt = find("credit|crédit|einnahme|depot|dépôt")
        let memoAt = find("memo|note|reference|référence|commentaire")
        guard amountAt != nil || debitAt != nil || creditAt != nil else {
            throw Failure.noAmountColumn
        }

        var out: [Row] = []
        for line in lines.dropFirst() {
            let cells = split(line, by: delimiter)
            func cell(_ index: Int?) -> String {
                guard let index, index < cells.count else { return "" }
                return cells[index].trimmingCharacters(in: .whitespaces)
            }
            guard let day = date(from: cell(dateAt)) else { continue }

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
        return out
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
        // A comma present means the comma is the decimal mark, so any dot in
        // the same number is a thousands separator.
        if value.contains(",") {
            value = value.replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
        }
        return Double(value)
    }

    /// ISO first, then European, then OFX's `YYYYMMDD`. Never American: this
    /// app is French-first and `03/04` has to mean one thing.
    static func date(from raw: String) -> String? {
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
        guard parts.count == 3, let d = Int(parts[0]), let m = Int(parts[1]),
              var y = Int(parts[2]), d >= 1, d <= 31, m >= 1, m <= 12
        else { return nil }
        if y < 100 { y += 2000 }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}
