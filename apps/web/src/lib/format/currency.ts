// Re-export the configurable global formatters from core. The active currency
// + locale are set once per request in the root layout via setCurrencyConfig
// (driven by APP_CURRENCY + the user's locale), so these honour the deploy-time
// currency instead of a hardcoded EUR. Prefer importing from '@florin/core/lib/format'
// directly; this module exists for backwards-compatibility.
export { formatCurrency, formatCurrencySigned } from '@florin/core/lib/format'
