import { resolveAppConfig, type AppConfig } from '@florin/core/lib/app-config'

/**
 * Web resolves the tunable defaults from environment variables (the web app is
 * a single-tenant self-host, so config lives in `.env`, mirroring APP_CURRENCY).
 * Unset / invalid values fall back to the France/EUR-first defaults.
 *
 *   APP_GOAL_TARGET      — long-term wealth target (default 100000)
 *   APP_GOAL_RETURN_PCT  — assumed net annual return % (default 7)
 *   APP_PEA_CEILING      — tax-wrapper contribution cap; 0 hides it (default 150000)
 */
export function getAppConfig(): AppConfig {
  return resolveAppConfig({
    goalTarget: process.env.APP_GOAL_TARGET,
    goalReturnPct: process.env.APP_GOAL_RETURN_PCT,
    peaCeiling: process.env.APP_PEA_CEILING,
    plannedMonthlyInvestment: process.env.APP_DCA_MONTHLY,
  })
}
