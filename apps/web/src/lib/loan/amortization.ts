/**
 * Loan amortization math — re-exported from `@florin/core/lib/loan/amortization`.
 *
 * Previously a byte-for-byte copy of the core module; kept here only as a thin
 * re-export so the web app's `@/lib/loan/amortization` alias (used by the
 * account page and unit tests) resolves to the single source of truth in core.
 */

export * from '@florin/core/lib/loan/amortization'
