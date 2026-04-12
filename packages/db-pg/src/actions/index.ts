import type { FlorinMutations } from '@florin/core/types'
import type { PgDB } from '../client'
import {
  createAccountMutation,
  updateAccountMutation,
  deleteAccountMutation,
  setAccountArchivedMutation,
  reorderAccountsMutation,
  mergeAccountMutation,
  updateLoanSettingsMutation,
} from './accounts'
import {
  addTransactionMutation,
  updateTransactionCategoryMutation,
  softDeleteTransactionMutation,
  approveTransactionMutation,
  approveAllTransactionsMutation,
  bulkUpdateTransactionCategoryMutation,
  bulkApproveTransactionsMutation,
  bulkSoftDeleteTransactionsMutation,
} from './transactions'
import {
  createCategoryMutation,
  updateCategoryMutation,
  deleteCategoryMutation,
  createCategoryGroupMutation,
  updateCategoryGroupMutation,
  deleteCategoryGroupMutation,
  setCategoryLoanLinkMutation,
} from './categories'

// Re-export standalone functions for callers that need them directly
export { reconcileLoanMirrorsForCategory, recomputeAccountBalance } from './helpers'
export { listTransactionsForAccountQuery, listLoanPaymentsForAccountQuery } from './transactions'
export { exportAllDataMutation } from './export'

/**
 * Build a FlorinMutations implementation backed by a PostgreSQL connection.
 */
export function createPgMutations(db: PgDB): FlorinMutations {
  return {
    // Accounts
    createAccount: (input) => createAccountMutation(db, input),
    updateAccount: (input) => updateAccountMutation(db, input),
    deleteAccount: (id) => deleteAccountMutation(db, id),
    setAccountArchived: (id, archived) => setAccountArchivedMutation(db, id, archived),
    reorderAccounts: (orderedIds) => reorderAccountsMutation(db, orderedIds),
    mergeAccount: (sourceId, targetId) => mergeAccountMutation(db, sourceId, targetId),
    updateLoanSettings: (input) => updateLoanSettingsMutation(db, input),

    // Transactions
    addTransaction: (input) => addTransactionMutation(db, input),
    updateTransactionCategory: (transactionId, categoryId) =>
      updateTransactionCategoryMutation(db, transactionId, categoryId),
    softDeleteTransaction: (id) => softDeleteTransactionMutation(db, id),
    approveTransaction: (transactionId) => approveTransactionMutation(db, transactionId),
    approveAllTransactions: () => approveAllTransactionsMutation(db),
    bulkUpdateTransactionCategory: (ids, categoryId) =>
      bulkUpdateTransactionCategoryMutation(db, ids, categoryId),
    bulkApproveTransactions: (ids) => bulkApproveTransactionsMutation(db, ids),
    bulkSoftDeleteTransactions: (ids) => bulkSoftDeleteTransactionsMutation(db, ids),

    // Categories
    createCategory: (input) => createCategoryMutation(db, input),
    updateCategory: (input) => updateCategoryMutation(db, input),
    deleteCategory: (id) => deleteCategoryMutation(db, id),
    createCategoryGroup: (input) => createCategoryGroupMutation(db, input),
    updateCategoryGroup: (input) => updateCategoryGroupMutation(db, input),
    deleteCategoryGroup: (id) => deleteCategoryGroupMutation(db, id),
    setCategoryLoanLink: (categoryId, loanAccountId) =>
      setCategoryLoanLinkMutation(db, categoryId, loanAccountId),
  }
}
