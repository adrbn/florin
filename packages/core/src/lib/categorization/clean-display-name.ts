/**
 * Turn a raw bank transaction description into a human-readable merchant name
 * for display (subscriptions radar, etc).
 *
 * Unlike {@link normalizePayee} — whose job is to produce a stable *lowercase*
 * grouping key — this keeps the merchant readable:
 *
 * - drops reference noise ("ref : 1041355744819, …") and trailing code runs
 * - drops a leading French preposition ("de paypal …" → "paypal …") and the
 *   usual banking prefixes (ACHAT CB, PRLV, VIR, …)
 * - keeps only the first meaningful clause before a comma
 * - restores capitalisation: ALL CAPS / all-lowercase input is title-cased,
 *   but input that already has mixed case (e.g. "PayPal") is trusted as-is
 *
 * "de paypal europe s.a, l. et cie s.c.a, ref : 1041355744819, …" → "Paypal Europe S.A"
 */
const LEADING_NOISE: ReadonlyArray<RegExp> = [
  /^achat\s+cb\s+/i,
  /^paiement\s+(?:carte|cb)\s+/i,
  /^cb\s+/i,
  /^vir(?:ement)?(?:\s+inst(?:antane)?)?\s+/i,
  /^prlv\s+/i,
  /^prelevement\s+/i,
  /^de\s+/i,
  /^du\s+/i,
  /^des\s+/i,
  /^d['’]\s*/i,
]

export function cleanDisplayName(input: string | null | undefined): string {
  if (!input) {
    return ''
  }
  let s = input.replace(/\s+/g, ' ').trim()
  if (s === '') {
    return ''
  }

  // Cut everything from a reference marker onward ("ref :", "réf:", "ref").
  s = s.replace(/[,;]?\s*r[ée]f\.?\s*:?.*$/i, '')
  // Drop a trailing "/path" segment ("…/paypal mensuel").
  s = s.replace(/\/.*$/, '')
  // Drop trailing long digit runs (reference numbers left over).
  s = s.replace(/[\s,;-]+\d{4,}\s*$/, '')

  // Strip leading prepositions / banking prefixes (repeat for stacked ones).
  let changed = true
  while (changed) {
    changed = false
    for (const re of LEADING_NOISE) {
      const next = s.replace(re, '')
      if (next !== s) {
        s = next
        changed = true
      }
    }
  }

  // Keep only the first meaningful clause before a comma when one exists.
  const firstClause = s.split(',')[0]?.trim() ?? s
  if (firstClause.length >= 3) {
    s = firstClause
  }

  s = s.replace(/\s+/g, ' ').trim()
  return smartCase(s)
}

/** French legal-form suffixes worth keeping upper-cased ("orange sa" → "Orange SA"). */
const KNOWN_ACRONYMS = new Set([
  'sa',
  'sas',
  'sasu',
  'sarl',
  'eurl',
  'sca',
  'sci',
  'scs',
  'snc',
  'gie',
  'plc',
  'inc',
  'llc',
  'bv',
  'gmbh',
])

/**
 * Capitalise sensibly: trust input that is already mixed-case, otherwise
 * title-case it. Dotted acronyms (s.a, s.c.a) and known legal-form suffixes
 * (SA, SAS, SARL, …) are upper-cased.
 */
function smartCase(s: string): string {
  if (s === '') {
    return ''
  }
  const hasLower = /[a-z]/.test(s)
  const hasUpper = /[A-Z]/.test(s)
  if (hasLower && hasUpper) {
    return s
  }
  return s
    .toLowerCase()
    .split(' ')
    .map((word) => {
      if (word === '') return word
      // Dotted acronym like "s.a" or "s.c.a" → upper-case.
      if (/^[a-z](?:\.[a-z])*\.?$/.test(word) && word.includes('.')) {
        return word.toUpperCase()
      }
      if (KNOWN_ACRONYMS.has(word)) {
        return word.toUpperCase()
      }
      return word.charAt(0).toUpperCase() + word.slice(1)
    })
    .join(' ')
}
