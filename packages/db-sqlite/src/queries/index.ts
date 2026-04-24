import { asc, eq } from 'drizzle-orm'
import type {
  FlorinQueries,
  Account,
  BankConnection,
  Category,
  CategoryGroup,
  CategoryGroupWithCategories,
  CategorizationRule,
  TransactionWithRelations,
  AccountKind,
  SyncProvider,
  CategoryKind,
  TransactionSource,
} from '@florin/core/types'
import type { SqliteDB } from '../client'
import {
  accounts,
  bankConnections,
  categories,
  categorizationRules,
  categoryGroups,
  transactions,
} from '../schema'
import {
  getNetWorth,
  getMonthBurn,
  getAvgMonthlyBurn,
  getPatrimonyTimeSeries,
  getMonthByCategory,
  getTopExpenses,
  countUncategorizedExpensesThisMonth,
  getDataSourceInfo,
  getLeftToSpendThisMonth,
  getDailySpend,
  getDailySpendByCategory,
  getSavingsRates,
  getSubscriptions,
} from './dashboard'
import {
  getMonthlyFlows,
  getCategoryBreakdown,
  getAgeOfMoney,
  getAgeOfMoneyHistory,
  getNetWorthSeries,
  getCategorySpendingSeries,
} from './reflect'
import { getMonthPlanQuery } from './plan'

export { getNetWorth } from './dashboard'
export { getLoanLiabilities } from './loan-liabilities'

// ============ SQLite -> Core model mappers ============

function toDate(s: string | null | undefined): Date | null {
  return s ? new Date(s) : null
}

function toDateRequired(s: string): Date {
  return new Date(s)
}

function mapAccount(row: typeof accounts.$inferSelect): Account {
  return {
    ...row,
    kind: row.kind as AccountKind,
    currentBalance: String(row.currentBalance),
    lastSyncedAt: toDate(row.lastSyncedAt),
    syncProvider: row.syncProvider as SyncProvider,
    loanOriginalPrincipal: row.loanOriginalPrincipal === null ? null : String(row.loanOriginalPrincipal),
    loanInterestRate: row.loanInterestRate === null ? null : String(row.loanInterestRate),
    loanStartDate: toDate(row.loanStartDate),
    loanTermMonths: row.loanTermMonths,
    loanMonthlyPayment: row.loanMonthlyPayment === null ? null : String(row.loanMonthlyPayment),
    createdAt: toDateRequired(row.createdAt),
    updatedAt: toDateRequired(row.updatedAt),
  }
}

function mapBankConnection(row: typeof bankConnections.$inferSelect): BankConnection {
  return {
    ...row,
    validUntil: toDateRequired(row.validUntil),
    syncStartDate: toDateRequired(row.syncStartDate),
    lastSyncedAt: toDate(row.lastSyncedAt),
    createdAt: toDateRequired(row.createdAt),
    updatedAt: toDateRequired(row.updatedAt),
  }
}

function mapCategory(row: typeof categories.$inferSelect): Category {
  return {
    ...row,
    createdAt: toDateRequired(row.createdAt),
  }
}

function mapCategoryGroup(row: typeof categoryGroups.$inferSelect): CategoryGroup {
  return {
    ...row,
    kind: row.kind as CategoryKind,
    createdAt: toDateRequired(row.createdAt),
  }
}

function mapCategorizationRule(row: typeof categorizationRules.$inferSelect): CategorizationRule {
  return {
    ...row,
    matchMinAmount: row.matchMinAmount === null ? null : String(row.matchMinAmount),
    matchMaxAmount: row.matchMaxAmount === null ? null : String(row.matchMaxAmount),
    lastHitAt: toDate(row.lastHitAt),
    createdAt: toDateRequired(row.createdAt),
    updatedAt: toDateRequired(row.updatedAt),
  }
}

type SqliteTransactionWithRelations = typeof transactions.$inferSelect & {
  account: typeof accounts.$inferSelect | null
  category: typeof categories.$inferSelect | null
}

function mapTransactionWithRelations(row: SqliteTransactionWithRelations): TransactionWithRelations {
  return {
    id: row.id,
    accountId: row.accountId,
    occurredAt: toDateRequired(row.occurredAt),
    recordedAt: toDateRequired(row.recordedAt),
    amount: String(row.amount),
    currency: row.currency,
    payee: row.payee,
    normalizedPayee: row.normalizedPayee,
    memo: row.memo,
    categoryId: row.categoryId,
    source: row.source as TransactionSource,
    externalId: row.externalId,
    legacyId: row.legacyId,
    isPending: row.isPending,
    needsReview: row.needsReview,
    transferPairId: row.transferPairId,
    rawData: row.rawData,
    deletedAt: toDate(row.deletedAt),
    createdAt: toDateRequired(row.createdAt),
    updatedAt: toDateRequired(row.updatedAt),
    account: row.account ? mapAccount(row.account) : null,
    category: row.category ? mapCategory(row.category) : null,
  }
}

// ============ Query factory ============

/**
 * Build a FlorinQueries implementation backed by a SQLite connection.
 * Each method delegates to the standalone query function, passing in the
 * shared `db` instance so the query layer stays free of global singletons.
 *
 * Where the SQLite schema infers different types than the core model
 * interfaces (e.g. `text()` -> `string` vs `Date`, `real()` -> `number`
 * vs `string`), mapper functions bridge the gap.
 */
export function createSqliteQueries(db: SqliteDB): FlorinQueries {
  return {
    getNetWorth: () => getNetWorth(db),
    getMonthBurn: (opts) => getMonthBurn(db, opts),
    getAvgMonthlyBurn: (months) => getAvgMonthlyBurn(db, months),
    getPatrimonyTimeSeries: (months) => getPatrimonyTimeSeries(db, months),
    getMonthByCategory: () => getMonthByCategory(db),
    getTopExpenses: (n, days, categoryId) => getTopExpenses(db, n, days, categoryId),
    countUncategorizedExpensesThisMonth: () => countUncategorizedExpensesThisMonth(db),
    getDataSourceInfo: () => getDataSourceInfo(db),
    getMonthlyFlows: (months) => getMonthlyFlows(db, months),
    getCategoryBreakdown: (days) => getCategoryBreakdown(db, days),
    getAgeOfMoney: (days) => getAgeOfMoney(db, days),
    getAgeOfMoneyHistory: (months) => getAgeOfMoneyHistory(db, months),
    getNetWorthSeries: (months) => getNetWorthSeries(db, months),
    getCategorySpendingSeries: (months) => getCategorySpendingSeries(db, months),
    getMonthPlan: async (year, month) => getMonthPlanQuery(db, year, month),
    getLeftToSpendThisMonth: () => getLeftToSpendThisMonth(db),
    getDailySpend: (days) => getDailySpend(db, days),
    getDailySpendByCategory: (days) => getDailySpendByCategory(db, days),
    getSavingsRates: () => getSavingsRates(db),
    getSubscriptions: () => getSubscriptions(db),

    // ---------- listing queries ----------

    listTransactions: async (options = {}) => {
      const { listTransactionsQuery } = await import('./transactions')
      const rows = await listTransactionsQuery(db, options)
      return rows.map((r) => mapTransactionWithRelations(r as SqliteTransactionWithRelations))
    },
    countTransactions: async (options = {}) => {
      const { countTransactionsQuery } = await import('./transactions')
      return countTransactionsQuery(db, options)
    },
    countNeedsReview: async () => {
      const { countNeedsReviewQuery } = await import('./transactions')
      return countNeedsReviewQuery(db)
    },

    listAccounts: async (options = {}) => {
      const where = options.includeArchived ? undefined : eq(accounts.isArchived, false)
      const query = db
        .select()
        .from(accounts)
        .orderBy(asc(accounts.displayOrder), asc(accounts.name))
      const rows = where ? await query.where(where) : await query
      return rows.map(mapAccount)
    },

    getAccountById: async (id) => {
      const row = await db.query.accounts.findFirst({
        where: eq(accounts.id, id),
        with: { bankConnection: true },
      })
      if (!row) return null
      const mapped = mapAccount(row)
      const bankConn = row.bankConnection
        ? mapBankConnection(row.bankConnection)
        : null
      return { ...mapped, bankConnection: bankConn }
    },

    listBankConnections: async () => {
      const rows = await db.select().from(bankConnections)
      return rows.map(mapBankConnection)
    },

    listCategoriesByGroup: async () => {
      const rows = await db.query.categoryGroups.findMany({
        orderBy: (g) => [asc(g.displayOrder), asc(g.name)],
        with: {
          categories: {
            orderBy: (c) => [asc(c.displayOrder), asc(c.name)],
          },
        },
      })
      return rows.map((g): CategoryGroupWithCategories => ({
        ...mapCategoryGroup(g),
        categories: g.categories.map(mapCategory),
      }))
    },

    listCategoriesFlat: async () => {
      return db
        .select({
          id: categories.id,
          name: categories.name,
          emoji: categories.emoji,
          groupName: categoryGroups.name,
          linkedLoanAccountId: categories.linkedLoanAccountId,
        })
        .from(categories)
        .innerJoin(categoryGroups, eq(categories.groupId, categoryGroups.id))
        .orderBy(asc(categoryGroups.name), asc(categories.name))
    },

    listCategorizationRules: async () => {
      const rows = await db.select().from(categorizationRules)
      return rows.map(mapCategorizationRule)
    },
  }
}
