/**
 * Detecting a bank's own re-booking of a transaction it already sent.
 *
 * Some banks book an instant transfer twice: first a provisional entry with a
 * generic label ("VIREMENT INSTANTANE CREDIT"), then, a day or two later, the
 * settled entry carrying the counterparty ("VIREMENT INSTANTANE DE MME ROBINO
 * AGNES"). La Banque Postale does exactly this.
 *
 * Florin's uniqueness is `(source, external_id)`, and LBP supplies no stable
 * `transaction_id` — the fallback is `entry_reference`, which for that bank is
 * *positional* (`2026-08-23.1` = second entry booked on 23 August). The settled
 * entry therefore arrives with a brand-new reference and no conflict, so it is
 * inserted as a second row. Eleven such pairs had accumulated over ten weeks.
 *
 * The signal that distinguishes a re-booking from a genuinely repeated payment
 * is the *shape of the label*: the earlier row says nothing the later one does
 * not, and what it adds beyond the shared opening is a direction word. Two real
 * Leclerc purchases of the same amount share "achat cb leclerc" — the older one
 * adds a merchant, not a direction — so they do not match.
 */

/**
 * Words that carry no information about *who* was paid: they describe the rail
 * or the direction. A row whose only distinguishing words are these is a
 * placeholder waiting to be enriched.
 */
const DIRECTION_WORDS = new Set([
  'credit',
  'debit',
  'virement',
  'paiement',
  'achat',
  'operation',
  'transfert',
  'transfer',
  'in',
  'out',
])

/** How many opening words the two labels must share before the test applies. */
const SHARED_PREFIX_WORDS = 2

function words(payee: string): string[] {
  return payee
    .normalize('NFD')
    // Strip accents so "crédit" and "credit" are the same word.
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter(Boolean)
}

/**
 * Is `earlier` the bank's un-enriched first booking of `later`?
 *
 * Both payees are compared on words, accent- and case-insensitively. True when
 * they open with the same {@link SHARED_PREFIX_WORDS} words, `earlier` is the
 * shorter of the two, and everything `earlier` adds beyond that shared opening
 * is a direction word.
 */
export function isPlaceholderOf(earlier: string, later: string): boolean {
  const a = words(earlier)
  const b = words(later)
  if (a.length < SHARED_PREFIX_WORDS || b.length <= a.length) return false

  for (let i = 0; i < SHARED_PREFIX_WORDS; i++) {
    if (a[i] !== b[i]) return false
  }

  const rest = a.slice(SHARED_PREFIX_WORDS)
  // A bare "VIREMENT INSTANTANE" with nothing after it is a placeholder too.
  if (rest.length === 0) return true
  return rest.every((w) => DIRECTION_WORDS.has(w))
}
