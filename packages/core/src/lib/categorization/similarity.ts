/**
 * History-based category suggestion.
 *
 * This is the "layer 3" auto-categoriser: when explicit rules don't match a
 * new transaction, we look at the user's own categorised history and copy
 * the category of the most similar past transaction.
 *
 * Two paths, tried in order:
 *
 *   A. Exact normalised-payee match.
 *      Group history by `normalizedPayee`. If the candidate's payee appears
 *      in the pool, pick the modal category across all past txs with that
 *      same payee. This is the dominant case in real bank data — "NETFLIX"
 *      bills every month with the same payee string, so exact match wins.
 *
 *   B. Token-overlap fallback.
 *      When there's no exact match, Jaccard similarity over the multiset of
 *      ≥3-char tokens from both payees, plus small bonuses for account
 *      match and amount being in the same ±30% bucket. Capped at 0.85 so
 *      fuzzy matches can never outrank a clean exact-match hit.
 *
 * Everything runs on data the user already has locally. No network, no
 * model, no training — deterministic and auditable.
 */

export interface HistoryEntry {
  normalizedPayee: string
  categoryId: string
  amount: number
  accountId: string
}

export interface Candidate {
  normalizedPayee: string
  amount: number
  accountId: string
}

export interface Suggestion {
  categoryId: string
  /** 0..1. The sync path auto-applies at ≥ 0.8; review-queue at ≥ 0.5. */
  confidence: number
  /** Human-readable trace for the UI ("9 past tx with this exact payee"). */
  reason: string
}

const MIN_TOKEN_LEN = 3

function tokens(s: string): string[] {
  return s
    .toLowerCase()
    .split(/[^a-z0-9àâäéèêëïîôöùûüç]+/i)
    .filter((t) => t.length >= MIN_TOKEN_LEN)
}

function jaccard(a: ReadonlyArray<string>, b: ReadonlyArray<string>): number {
  if (a.length === 0 || b.length === 0) return 0
  const setA = new Set(a)
  const setB = new Set(b)
  let intersection = 0
  for (const t of setA) if (setB.has(t)) intersection++
  const union = setA.size + setB.size - intersection
  return union === 0 ? 0 : intersection / union
}

/** Pick the most common category among a list of entries. Breaks ties by recency of insertion (list order). */
function modeCategory(entries: ReadonlyArray<HistoryEntry>): { categoryId: string; count: number; total: number } {
  const counts = new Map<string, number>()
  for (const e of entries) counts.set(e.categoryId, (counts.get(e.categoryId) ?? 0) + 1)
  let bestId = entries[0]!.categoryId
  let bestCount = 0
  for (const [id, n] of counts) {
    if (n > bestCount) {
      bestId = id
      bestCount = n
    }
  }
  return { categoryId: bestId, count: bestCount, total: entries.length }
}

/**
 * Given a candidate transaction and a pool of categorised history, propose
 * a category with a confidence score. Returns null when no signal is strong
 * enough to say anything at all (caller leaves the tx uncategorised).
 */
export function suggestCategory(
  candidate: Candidate,
  history: ReadonlyArray<HistoryEntry>,
): Suggestion | null {
  if (history.length === 0 || !candidate.normalizedPayee) return null

  // --- Path A: exact normalized_payee match ---
  const exactMatches = history.filter((h) => h.normalizedPayee === candidate.normalizedPayee)
  if (exactMatches.length > 0) {
    const { categoryId, count, total } = modeCategory(exactMatches)
    const agreementRatio = count / total
    // Single past tx with this payee → 0.75 (still strong, but not conclusive
    // — a one-off charge could be mis-categorised). Two+ with unanimous
    // agreement → 0.95. Conflicting categories hurt confidence fast.
    let confidence: number
    if (total === 1) confidence = 0.75
    else if (agreementRatio >= 0.9) confidence = 0.95
    else if (agreementRatio >= 0.7) confidence = 0.85
    else confidence = 0.6 // disagreement in history — flag for review, don't auto-apply
    return {
      categoryId,
      confidence,
      reason:
        total === 1
          ? `1 past transaction with this exact payee`
          : `${count} of ${total} past transactions with this payee categorised this way`,
    }
  }

  // --- Path B: token-overlap fallback ---
  const candTokens = tokens(candidate.normalizedPayee)
  if (candTokens.length === 0) return null

  let bestScore = 0
  let bestEntry: HistoryEntry | null = null
  for (const entry of history) {
    const entTokens = tokens(entry.normalizedPayee)
    const score = jaccard(candTokens, entTokens)
    if (score > bestScore) {
      bestScore = score
      bestEntry = entry
    }
  }

  if (!bestEntry || bestScore < 0.5) return null

  // Boost when the account and amount bucket also line up — small signals
  // that add up when the payee alone is ambiguous.
  let confidence = bestScore
  if (bestEntry.accountId === candidate.accountId) confidence += 0.05
  if (sameAmountBucket(candidate.amount, bestEntry.amount)) confidence += 0.05
  confidence = Math.min(0.85, confidence) // fuzzy matches never beat a clean exact match

  return {
    categoryId: bestEntry.categoryId,
    confidence,
    reason: `Token overlap with “${bestEntry.normalizedPayee}” (score ${bestScore.toFixed(2)})`,
  }
}

function sameAmountBucket(a: number, b: number): boolean {
  if (Math.sign(a) !== Math.sign(b)) return false
  const absA = Math.abs(a)
  const absB = Math.abs(b)
  if (absA === 0 || absB === 0) return absA === absB
  const ratio = Math.min(absA, absB) / Math.max(absA, absB)
  return ratio >= 0.7 // within ±30%
}

/**
 * Build a compact history pool from raw DB rows. Dedupes & caps to the
 * freshest N entries so the hot loop in `suggestCategory` stays cheap even
 * with a decade of history.
 */
export function buildHistoryPool(
  rows: ReadonlyArray<HistoryEntry & { occurredAt: Date }>,
  maxEntries = 5000,
): HistoryEntry[] {
  const sorted = rows.slice().sort((a, b) => b.occurredAt.getTime() - a.occurredAt.getTime())
  return sorted.slice(0, maxEntries).map(({ occurredAt: _occurredAt, ...rest }) => rest)
}
