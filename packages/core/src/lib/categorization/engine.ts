/**
 * Pure categorization engine.
 *
 * - Filters active rules
 * - Sorts by priority desc
 * - Applies AND semantics across all non-null match fields
 * - First matching rule wins; returns its categoryId or null
 *
 * Match dimensions:
 *   - matchAccountId: equality on the txn account
 *   - matchPayeeRegex: case-insensitive regex on the (already normalized) payee
 *   - matchMinAmount/matchMaxAmount: amount range (inclusive)
 *
 * A rule with a malformed regex is silently skipped.
 */
export interface Rule {
  id: string
  priority: number
  categoryId: string
  isActive: boolean
  matchPayeeRegex: string | null
  matchMinAmount: number | null
  matchMaxAmount: number | null
  matchAccountId: string | null
}

export interface CandidateTxn {
  payee: string
  amount: number
  accountId: string
}

function ruleMatches(rule: Rule, txn: CandidateTxn): boolean {
  if (rule.matchAccountId !== null && rule.matchAccountId !== txn.accountId) {
    return false
  }

  if (rule.matchPayeeRegex !== null) {
    let regex: RegExp
    try {
      regex = new RegExp(rule.matchPayeeRegex, 'i')
    } catch {
      return false
    }
    if (!regex.test(txn.payee)) {
      return false
    }
  }

  if (rule.matchMinAmount !== null && txn.amount < rule.matchMinAmount) {
    return false
  }

  if (rule.matchMaxAmount !== null && txn.amount > rule.matchMaxAmount) {
    return false
  }

  return true
}

export function matchRule(txn: CandidateTxn, rules: ReadonlyArray<Rule>): string | null {
  const sorted = rules.filter((r) => r.isActive).sort((a, b) => b.priority - a.priority)

  for (const rule of sorted) {
    if (ruleMatches(rule, txn)) {
      return rule.categoryId
    }
  }

  return null
}
