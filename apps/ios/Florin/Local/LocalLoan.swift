import Foundation

/*
 * What is still owed, rather than what has been paid.
 *
 * The phone reported a loan's debt as `abs(balance)` — the sum of the
 * repayment rows sitting on the loan account, which is the money already
 * handed over. On this ledger that read 3 543 € after twenty-six instalments
 * of 165,13 €, and called it the remaining debt. It is very nearly the exact
 * opposite: the debt was the part not in that number.
 *
 * The server has computed this properly since the loan feature shipped —
 * `packages/core/src/lib/loan` — and the reason it is a hundred lines rather
 * than `principal − paid` is written there: subtraction ignores interest, and
 * a bank's "capital restant dû" line is the balance after walking a real
 * amortisation schedule. This is that walk, ported so the two agree.
 */
enum LocalLoan {
    struct Liability: Equatable {
        /// Capital restant dû, positive.
        var remainingDebt: Double
        var principalPaid: Double
        var interestPaid: Double
        /// False when the parameters were too incomplete to build a schedule
        /// and the figure fell back to arithmetic that ignores interest.
        var fromSchedule: Bool
    }

    struct Inputs {
        var principal: Double
        var annualRate: Double
        var termMonths: Int
        var monthlyPayment: Double
    }

    private static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }

    /// M = P·r·(1+r)^n / ((1+r)^n − 1), and P/n when the rate is zero, because
    /// interest-free loans exist — family, some student loans.
    static func monthlyPayment(principal: Double, annualRate: Double, termMonths: Int) -> Double {
        guard termMonths > 0 else { return 0 }
        let r = annualRate / 12
        guard r != 0 else { return principal / Double(termMonths) }
        let factor = pow(1 + r, Double(termMonths))
        return principal * r * factor / (factor - 1)
    }

    /*
     * The rate the contract actually amortises on.
     *
     * A bank quotes the TAEG and amortises on the taux débiteur, so dividing
     * the advertised rate by twelve drifts a few euros over a couple of years
     * and spills an extra month at the end. When principal, payment and term
     * are all known the periodic rate is recoverable from them exactly, by
     * bisection — and then the schedule matches the bank to the cent.
     */
    static func solveAnnualRate(principal p: Double, monthlyPayment m: Double, termMonths n: Int) -> Double? {
        guard p > 0, m > 0, n > 0 else { return nil }
        let zeroRatePayment = p / Double(n)
        if m <= zeroRatePayment + 1e-9 {
            return m >= zeroRatePayment - 1e-9 ? 0 : nil
        }
        func paymentAt(_ r: Double) -> Double {
            guard r > 0 else { return p / Double(n) }
            let factor = pow(1 + r, Double(n))
            return p * r * factor / (factor - 1)
        }
        var lo = 0.0
        var hi = 1.0
        var guardCount = 0
        while paymentAt(hi) < m, guardCount < 64 {
            hi *= 2
            guardCount += 1
        }
        for _ in 0..<128 {
            let mid = (lo + hi) / 2
            let pm = paymentAt(mid)
            if abs(pm - m) < 1e-11 { return mid * 12 }
            if pm < m { lo = mid } else { hi = mid }
        }
        return ((lo + hi) / 2) * 12
    }

    /// One row of the walk: what the instalment paid in interest, what it paid
    /// off, and what remained after it.
    struct Row {
        var interest: Double
        var principal: Double
        var balanceAfter: Double
    }

    static func schedule(_ inputs: Inputs, finalMonth: Int = 0) -> [Row] {
        var rows: [Row] = []
        let r = inputs.annualRate / 12
        var balance = inputs.principal
        // Twice the term, so a rate high enough that interest exceeds the
        // instalment cannot loop for ever.
        let maxMonths = max(inputs.termMonths * 2, 1)

        for i in 1...maxMonths {
            if balance <= 0.005 { break }
            let interest = round2(balance * r)
            var principal = round2(inputs.monthlyPayment - interest)
            // An instalment that does not cover the interest would go
            // backwards; hold at zero rather than grow the debt.
            if principal < 0 { principal = 0 }
            if principal > balance { principal = balance }
            /*
             * The contractual last instalment absorbs the rounding residual,
             * so the loan closes on its term instead of trailing a few cents
             * into an extra month.
             */
            if finalMonth > 0, i >= finalMonth, balance - principal > 0.005 {
                principal = balance
            }
            balance = round2(balance - principal)
            rows.append(Row(interest: interest, principal: principal, balanceAfter: balance))
        }
        return rows
    }

    /*
     * The liability after a given number of instalments.
     *
     * `paymentsMade` is counted the way the server counts it: rows on the loan
     * account that are half of a transfer pair. An instalment only exists here
     * once its counterpart has been written, which is what makes validating a
     * repayment move this number.
     */
    static func liability(
        principal: Double,
        annualRate: Double,
        termMonths: Int,
        monthlyPayment: Double,
        paymentsMade: Int,
        fallbackBalance: Double = 0,
        totalPaid: Double = 0
    ) -> Liability {
        func naive() -> Liability {
            if principal > 0 {
                return Liability(
                    remainingDebt: max(0, principal - totalPaid),
                    principalPaid: totalPaid,
                    interestPaid: 0,
                    fromSchedule: false
                )
            }
            return Liability(
                remainingDebt: abs(fallbackBalance),
                principalPaid: 0,
                interestPaid: 0,
                fromSchedule: false
            )
        }

        guard principal > 0, annualRate >= 0 else { return naive() }
        var term = termMonths > 0 ? termMonths : 0
        if term <= 0 {
            guard monthlyPayment > 0 else { return naive() }
            // Without a term, how many instalments the payment implies.
            let r = annualRate / 12
            if r == 0 {
                term = Int((principal / monthlyPayment).rounded(.up))
            } else {
                let ratio = monthlyPayment / (monthlyPayment - principal * r)
                guard ratio > 0 else { return naive() }
                term = Int((log(ratio) / log(1 + r)).rounded(.up))
            }
            guard term > 0 else { return naive() }
        }

        let hasExplicitTerm = termMonths > 0
        let calibrate = hasExplicitTerm && monthlyPayment > 0
        let rate = calibrate
            ? (solveAnnualRate(principal: principal, monthlyPayment: monthlyPayment, termMonths: term) ?? annualRate)
            : annualRate
        let inputs = Inputs(
            principal: principal,
            annualRate: rate,
            termMonths: term,
            monthlyPayment: monthlyPayment > 0
                ? monthlyPayment
                : self.monthlyPayment(principal: principal, annualRate: rate, termMonths: term)
        )
        let rows = schedule(inputs, finalMonth: calibrate ? term : 0)
        guard !rows.isEmpty else { return naive() }

        if paymentsMade <= 0 {
            return Liability(
                remainingDebt: principal, principalPaid: 0, interestPaid: 0, fromSchedule: true
            )
        }
        let cursor = min(paymentsMade, rows.count) - 1
        let walked = rows[0...cursor]
        return Liability(
            remainingDebt: max(0, rows[cursor].balanceAfter),
            principalPaid: walked.reduce(0) { $0 + $1.principal },
            interestPaid: walked.reduce(0) { $0 + $1.interest },
            fromSchedule: true
        )
    }

    /*
     * Ce que le contrat prévoit, face à ce que le journal a vu passer.
     *
     * Le capital restant dû se déduit du NOMBRE de mensualités enregistrées :
     * une seule qui manque, et la dette garde une marche de capital qu'elle
     * devrait avoir rendue — 113,47 € sur un prêt de 10 000 € à 84 mois, soit
     * plus que la mensualité n'en rembourse à ce stade. Et rien ne le disait :
     * l'écran affichait un montant faux avec le même aplomb qu'un vrai.
     *
     * C'est arrivé pour une raison qui se reproduira : la banque prélève le
     * 30, le 30 février n'existe pas, l'échéance est tombée le 2 mars, et le
     * rapprochement automatique — qui tolère cinq jours d'écart pour ne jamais
     * payer deux fois la même — a pris le miroir du 28 février pour le sien.
     *
     * On ne corrige donc PAS cette tolérance : elle est ce qui empêche les
     * doublons, et un doublon avait déjà divisé la dette par deux. On ne
     * tente pas non plus d'apparier un pour un — deux prélèvements peuvent
     * légitimement tomber le même mois quand celui du mois d'avant a glissé.
     *
     * On compte ce qui ne peut pas mentir : depuis la première mensualité,
     * le contrat en prévoit une par mois. Si le journal en a moins, il manque
     * quelque chose, et le dire vaut mieux que de deviner laquelle.
     */
    /*
     * Une échéance n'est pas en retard le jour même.
     *
     * La banque prélève « le 30 », ce qui veut dire le 30, le 2, ou le lundi
     * suivant. Compter une mensualité comme due dès sa date ferait apparaître
     * le même avertissement chaque mois pendant quelques jours, pour un
     * prélèvement parfaitement normal — et un avertissement qui crie au loup
     * tous les mois n'est plus lu quand il a raison.
     *
     * On compare donc deux nombres arrêtés à la MÊME date : ce que le contrat
     * prévoyait au-delà de ce délai, et ce que le journal avait enregistré à
     * cette date-là. Sans cela, une mensualité ancienne qui manque se trouve
     * compensée par une récente qui vient d'arriver, et le trou disparaît.
     */
    static let settlementGrace: TimeInterval = 7 * 86_400

    static func expectedPayments(
        firstPayment: Date, termMonths: Int, asOf now: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Int {
        guard termMonths > 0, firstPayment <= now else { return 0 }
        let months = calendar.dateComponents(
            [.month], from: calendar.startOfDay(for: firstPayment),
            to: calendar.startOfDay(for: now)
        ).month ?? 0
        // Le mois écoulé compte la mensualité qui l'ouvrait : un prêt dont la
        // première échéance est tombée hier en a déjà prélevé une.
        return min(max(months + 1, 0), termMonths)
    }

    /// Combien il en manque au journal, en arrêtant les deux comptes au même
    /// jour. `nil` quand le prêt n'est pas assez renseigné pour que la
    /// question ait un sens.
    static func missingPayments(
        _ db: SQLiteDatabase, accountId: String, asOf now: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) throws -> Int? {
        let cutoff = now.addingTimeInterval(-settlementGrace)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"

        guard let row = try db.query(
            """
            SELECT loan_start_date, loan_term_months,
                   (SELECT count(*) FROM transactions
                    WHERE account_id = a.id AND transfer_pair_id IS NOT NULL
                      AND deleted_at IS NULL
                      AND substr(occurred_at, 1, 10) <= ?) AS made
            FROM accounts a WHERE a.id = ? AND a.kind = 'loan'
            """,
            [.text(formatter.string(from: cutoff)), .text(accountId)]
        ).first,
            let start = row.string("loan_start_date"),
            let first = Timestamp.parse(start),
            let term = row.int("loan_term_months"), term > 0
        else { return nil }

        let expected = expectedPayments(
            firstPayment: first, termMonths: term, asOf: cutoff, calendar: calendar
        )
        return max(0, expected - (row.int("made") ?? 0))
    }
}
