/**
 * Loan liability helper — re-exported from `@florin/core/lib/loan`.
 *
 * This used to be a full copy of the core amortization/liability math, which
 * risked drifting out of sync with the version the dashboard net-worth query
 * and the desktop app already import from core. It is now a thin re-export so
 * there is a single source of truth for "capital restant dû" everywhere.
 */

export {
  computeLoanLiability,
  type LoanAccountFields,
  type LoanLiability,
} from '@florin/core/lib/loan'
