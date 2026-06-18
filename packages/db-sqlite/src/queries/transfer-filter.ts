import { sql, type SQL } from 'drizzle-orm'
import { transactions } from '../schema'

/**
 * Outgoing SEPA transfer payee prefixes across the locales Enable Banking
 * surfaces. Banks label self-transfers differently per country/language
 * (French "VIREMENT", German "ÜBERWEISUNG", Spanish "TRANSFERENCIA",
 * Italian "BONIFICO", generic "TRANSFER"/"SEPA", abbreviated "VIR"). Matched
 * as a prefix followed by a space, mirroring the original `'VIREMENT %'`
 * behavior (the trailing space avoids matching unrelated payees that merely
 * start with these letters).
 */
const TRANSFER_PAYEE_PREFIXES = [
  'VIREMENT',
  'VIR',
  'ÜBERWEISUNG',
  'UEBERWEISUNG',
  'TRANSFER',
  'TRANSFERENCIA',
  'BONIFICO',
  'SEPA',
] as const

/**
 * SQL condition that is TRUE for an uncategorized outgoing transfer row — i.e.
 * a row whose payee starts with one of the {@link TRANSFER_PAYEE_PREFIXES} and
 * that has no category assigned. These are money moving between the user's own
 * accounts, not real spending, so they're excluded from spend/burn metrics.
 *
 * A user can always categorize such a row to override the heuristic (the
 * `categoryId IS NULL` qualifier means only uncategorized rows are filtered).
 */
export function isUncategorizedTransfer(): SQL {
  const likeClauses = TRANSFER_PAYEE_PREFIXES.map(
    (prefix) => sql`UPPER(${transactions.payee}) LIKE ${prefix + ' %'}`,
  )
  return sql`((${sql.join(likeClauses, sql` OR `)}) AND ${transactions.categoryId} IS NULL)`
}

/** Inverse of {@link isUncategorizedTransfer}: keep rows that are NOT such transfers. */
export function notUncategorizedTransfer(): SQL {
  return sql`NOT ${isUncategorizedTransfer()}`
}
