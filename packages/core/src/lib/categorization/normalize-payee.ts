/**
 * Normalize a payee string for categorization and de-duplication.
 *
 * - Strips French banking prefixes (ACHAT CB, PAIEMENT CARTE, VIR, PRLV, ...)
 * - Strips trailing 4-8 digit transaction codes
 * - Collapses whitespace
 * - Lowercases
 */
const PREFIX_PATTERNS: ReadonlyArray<RegExp> = [
  /^achat\s+cb\s+/i,
  /^paiement\s+carte\s+/i,
  /^paiement\s+cb\s+/i,
  /^cb\s+/i,
  /^vir\s+inst(?:antane)?\s+/i,
  /^vir(?:ement)?\s+/i,
  /^prlv\s+/i,
  /^prelevement\s+/i,
]

const TRAILING_CODE = /\s+\d{4,8}\s*$/

export function normalizePayee(input: string): string {
  if (!input) {
    return ''
  }

  let result = input.trim()
  if (result === '') {
    return ''
  }

  // Strip known prefixes (apply repeatedly in case of stacked prefixes)
  let changed = true
  while (changed) {
    changed = false
    for (const pattern of PREFIX_PATTERNS) {
      const next = result.replace(pattern, '')
      if (next !== result) {
        result = next
        changed = true
      }
    }
  }

  // Strip trailing transaction code
  result = result.replace(TRAILING_CODE, '')

  // Collapse whitespace
  result = result.replace(/\s+/g, ' ').trim()

  return result.toLowerCase()
}
