/**
 * Interpret a transaction search box query as an amount.
 *
 * The transactions search box is primarily a payee search, but a user often
 * remembers a transaction by its amount ("the 22,99 charge"). When the query
 * is a clean number — accepting both ',' and '.' decimals and an optional
 * currency symbol — we return its **absolute** value (rounded to cents) so the
 * caller can match transactions of that magnitude regardless of sign (a
 * +22.99 refund and a −22.99 charge both match).
 *
 * Returns `null` when the query is not purely numeric, so a normal text search
 * like "netflix" never triggers an amount comparison.
 */
export function parseAmountSearch(search: string): number | null {
  const cleaned = search
    .trim()
    .replace(/[\s  ]/g, '')
    .replace(/[€$£]/g, '')
    .replace(',', '.')
  if (!/^-?\d*\.?\d+$/.test(cleaned)) {
    return null
  }
  const n = Number(cleaned)
  if (!Number.isFinite(n)) {
    return null
  }
  return Math.round(Math.abs(n) * 100) / 100
}
