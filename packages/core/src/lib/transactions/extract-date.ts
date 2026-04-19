/**
 * Many European banks book a card purchase on the business day AFTER the
 * actual transaction, and never during weekends — so a Friday evening bar
 * tab shows up in Florin dated the following Monday. The true transaction
 * date is usually embedded in the free-text payee line:
 *
 *   "ACHAT CB BAR LO FARO 14.04.26 EUR 7,00 CARTE NO 469 OC APPLE PAY"
 *
 * This helper pulls out that date and, when it's plausibly close to the
 * booked date, returns it so the caller can override the display date.
 *
 * Rules:
 *  - First `DD.MM.YY` / `DD/MM/YY` / `DD-MM-YY` match wins.
 *  - 2-digit year expands to 20YY (YY >= 70 ⇒ 19YY would be absurd here).
 *  - Only returns the extracted date when it sits within ±`maxDriftDays`
 *    of the booked date. Outside that window it's almost certainly
 *    something else (an amount, a reference number, the merchant's birth
 *    year, whatever) — keep the booked date rather than risk corrupting
 *    the timeline.
 */
export interface ExtractedDate {
  date: Date
  /** The raw `DD.MM.YY` substring that matched, useful for debug logs. */
  match: string
}

const DATE_PATTERN = /\b(\d{1,2})[./\-](\d{1,2})[./\-](\d{2,4})\b/g

function expandYear(yy: number): number {
  if (yy >= 1900) return yy
  if (yy >= 100) return 2000 + (yy % 100)
  // Two-digit year: future-safe for a decade or two. Real bank ledgers
  // only need 2000–2099.
  return 2000 + yy
}

function isValidCalendarDate(y: number, m: number, d: number): boolean {
  if (m < 1 || m > 12) return false
  if (d < 1 || d > 31) return false
  const probe = new Date(Date.UTC(y, m - 1, d))
  return (
    probe.getUTCFullYear() === y &&
    probe.getUTCMonth() === m - 1 &&
    probe.getUTCDate() === d
  )
}

export function extractTrueDateFromText(
  text: string,
  bookedAt: Date,
  maxDriftDays = 14,
): ExtractedDate | null {
  if (!text) return null
  const maxDriftMs = maxDriftDays * 24 * 60 * 60 * 1000
  const bookedMs = bookedAt.getTime()

  DATE_PATTERN.lastIndex = 0
  let m: RegExpExecArray | null
  while ((m = DATE_PATTERN.exec(text)) !== null) {
    const [match, dStr, mStr, yStr] = m
    const d = Number(dStr)
    const mo = Number(mStr)
    const yRaw = Number(yStr)
    const y = expandYear(yRaw)
    if (!isValidCalendarDate(y, mo, d)) continue
    const candidate = new Date(Date.UTC(y, mo - 1, d))
    const diff = Math.abs(candidate.getTime() - bookedMs)
    if (diff <= maxDriftMs) return { date: candidate, match }
  }
  return null
}

/**
 * Convenience wrapper that returns an ISO date string (YYYY-MM-DD) if a
 * true date was extracted, else returns the fallback.
 */
export function resolveOccurredDate(
  text: string,
  bookedAt: Date,
  maxDriftDays = 14,
): Date {
  const hit = extractTrueDateFromText(text, bookedAt, maxDriftDays)
  return hit ? hit.date : bookedAt
}
