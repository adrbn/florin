import { count, eq, isNull } from 'drizzle-orm'
import { ExportButton } from '@florin/core/components/settings/export-button'
import { SyncLogCard } from '@florin/core/components/settings/sync-log-card'
import { Card, CardContent, CardHeader, CardTitle } from '@florin/core/components/ui/card'
import { db } from '@/db/client'
import { accounts, bankConnections, categories, transactions } from '@/db/schema'
import { getServerT } from '@/lib/locale'
import { exportAllData } from '@/server/actions/export'
import { auth } from '@/server/auth'
import { isEnableBankingConfigured } from '@/server/banking/enable-banking'
import { listSyncLogRuns } from '@/server/banking/sync-log'
import { env } from '@/server/env'

interface Stat {
  label: string
  value: string
}

/**
 * Settings — single-user, mostly read-only at the moment because Florin
 * is a single-tenant self-hosted app and the "user" is the env vars.
 * The page surfaces what *is* configurable plus operational diagnostics:
 *   - profile (email, locale, currency)
 *   - data export
 *   - bank API status
 *   - storage stats
 *   - guidance for rotating secrets / open-sourcing
 */
export default async function SettingsPage() {
  const t = await getServerT()
  const session = await auth()
  const bankingEnabled = isEnableBankingConfigured()

  const [
    accountCountRow,
    transactionCountRow,
    categoryCountRow,
    activeBankRow,
    activeTransactionRow,
    syncLogRuns,
  ] = await Promise.all([
    db.select({ value: count() }).from(accounts).where(eq(accounts.isArchived, false)),
    db.select({ value: count() }).from(transactions).where(isNull(transactions.deletedAt)),
    db.select({ value: count() }).from(categories).where(eq(categories.isArchived, false)),
    db.select({ value: count() }).from(bankConnections).where(eq(bankConnections.status, 'active')),
    db
      .select({ value: count() })
      .from(transactions)
      .where(eq(transactions.source, 'enable_banking')),
    listSyncLogRuns(),
  ])

  const stats: Stat[] = [
    {
      label: t('settings.storageAccountsActive', 'Accounts (active)'),
      value: String(accountCountRow[0]?.value ?? 0),
    },
    {
      label: t('settings.storageTransactionsAlive', 'Transactions (alive)'),
      value: String(transactionCountRow[0]?.value ?? 0),
    },
    {
      label: t('settings.storageCategories', 'Categories'),
      value: String(categoryCountRow[0]?.value ?? 0),
    },
    {
      label: t('settings.storageBankConnections', 'Bank connections'),
      value: String(activeBankRow[0]?.value ?? 0),
    },
    {
      label: t('settings.storageBankApiTransactions', 'Bank-API transactions'),
      value: String(activeTransactionRow[0]?.value ?? 0),
    },
  ]

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">{t('settings.title', 'Settings')}</h1>
        <p className="text-muted-foreground">
          {t('settings.subtitle', 'Operational diagnostics and exports for your Florin instance.')}
        </p>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle className="text-base">{t('settings.profile', 'Profile')}</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <Row
              label={t('settings.signedInAs', 'Signed in as')}
              value={session?.user?.email ?? '—'}
            />
            <Row label={t('settings.locale', 'Language')} value="fr-FR" />
            <Row label={t('settings.baseCurrency', 'Base currency')} value="EUR" />
            <p className="pt-2 text-[11px] text-muted-foreground">
              {t(
                'settings.profileHintWeb',
                'Florin is single-tenant — profile values come from environment variables. To change them, edit .env and restart.',
              )}
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">{t('settings.data', 'Data')}</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3 text-sm">
            <p className="text-muted-foreground">
              {t(
                'settings.dataHintWeb',
                'Download every table as a single JSON file. Bank consent tokens are stripped from the export so the file is safe to share.',
              )}
            </p>
            <ExportButton onExportAllData={exportAllData} />
            <p className="text-[11px] text-muted-foreground">
              {t(
                'settings.dataHintPgDump',
                'Tip: schedule pg_dump separately for backups that include indexes + history.',
              )}
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">
              {t('accounts.bankConnections', 'Bank connections')} (Enable Banking)
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <Row
              label={t('common.status', 'Status')}
              value={
                bankingEnabled
                  ? `✅ ${t('settings.bankStatusConfigured', 'Configured')}`
                  : `❌ ${t('settings.bankStatusNotConfigured', 'Not configured')}`
              }
            />
            <Row
              label={t('settings.bankAppId', 'App ID')}
              value={env.ENABLE_BANKING_APP_ID ?? '—'}
            />
            <Row
              label={t('settings.bankRedirectUrl', 'Redirect URL')}
              value={env.ENABLE_BANKING_REDIRECT_URL}
            />
            <p className="pt-2 text-[11px] text-muted-foreground">
              {t('settings.bankLinksHint', 'Manage individual bank links from the Accounts page.')}
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">{t('settings.storage', 'Storage')}</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            {stats.map((s) => (
              <Row key={s.label} label={s.label} value={s.value} />
            ))}
          </CardContent>
        </Card>

        <div className="lg:col-span-2">
          <SyncLogCard runs={syncLogRuns} />
        </div>

        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle className="text-base">
              {t('settings.selfHostTitle', 'Self-hosting tips')}
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm text-muted-foreground">
            <p>
              <strong className="text-foreground">
                {t('settings.rotateSecretsLabel', 'Rotate secrets:')}
              </strong>{' '}
              {t(
                'settings.rotateSecretsDesc',
                'regenerate NEXTAUTH_SECRET with openssl rand -base64 48 if you ever suspect leakage. Restart the app afterwards — sessions will be invalidated.',
              )}
            </p>
            <p>
              <strong className="text-foreground">
                {t('settings.dbBackupsLabel', 'Database backups:')}
              </strong>{' '}
              <code className="font-mono">
                docker compose exec db pg_dump -U postgres florin &gt; backup.sql
              </code>
            </p>
            <p>
              <strong className="text-foreground">
                {t('settings.bankQuotaLabel', 'Bank API quota:')}
              </strong>{' '}
              {t(
                'settings.bankQuotaDesc',
                "Enable Banking's free tier caps live data at 90 days unattended. Past that the app falls back to whatever was previously synced.",
              )}
            </p>
            <p>
              <strong className="text-foreground">
                {t('settings.openSourceLabel', 'Open source posture:')}
              </strong>{' '}
              {t(
                'settings.openSourceDesc',
                'there is no telemetry, no analytics, no third-party scripts. Everything runs against your own Postgres.',
              )}
            </p>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-baseline justify-between gap-3 border-b border-border/40 pb-1.5 last:border-0">
      <span className="text-xs uppercase tracking-wide text-muted-foreground">{label}</span>
      <span className="truncate font-mono text-foreground">{value}</span>
    </div>
  )
}
