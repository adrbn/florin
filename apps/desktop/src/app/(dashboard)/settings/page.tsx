import { count, eq, isNull } from 'drizzle-orm'
import { Card, CardContent, CardHeader, CardTitle } from '@florin/core/components/ui/card'
import { BuildInfo } from '@florin/core/components/settings/build-info'
import { SyncLogCard } from '@florin/core/components/settings/sync-log-card'
import pkg from '../../../../package.json'
import { db } from '@/db/client'
import { getServerT } from '@/lib/locale'
import { accounts, categories, settings, transactions } from '@/db/schema'
import { isPinEnabled } from '@/server/actions/pin'
import { listSyncLogRuns } from '@/server/banking/sync-log'
import { PinSettings } from '@/components/pin-settings'
import { BankingSettings } from '@/components/banking-settings'
import { LocaleSettings } from '@/components/locale-settings'
import { ImportData } from '@/components/import-data'

interface Stat {
  label: string
  value: string
}

/**
 * Settings — desktop version. No auth, no banking config — just operational
 * diagnostics and data export. The page surfaces storage stats and tips for
 * maintaining the local SQLite database.
 */
export default async function SettingsPage() {
  const t = await getServerT()
  const [
    accountCountRow,
    transactionCountRow,
    categoryCountRow,
    pinEnabled,
    ebAppIdRow,
    localeRow,
    currencyRow,
    syncLogRuns,
  ] = await Promise.all([
    db.select({ value: count() }).from(accounts).where(eq(accounts.isArchived, false)),
    db.select({ value: count() }).from(transactions).where(isNull(transactions.deletedAt)),
    db.select({ value: count() }).from(categories).where(eq(categories.isArchived, false)),
    isPinEnabled(),
    db.select().from(settings).where(eq(settings.key, 'eb_app_id')).get(),
    db.select().from(settings).where(eq(settings.key, 'user_locale')).get(),
    db.select().from(settings).where(eq(settings.key, 'user_currency')).get(),
    listSyncLogRuns(),
  ])

  const bankingConfigured = Boolean(ebAppIdRow?.value)
  const bankingAppId = ebAppIdRow?.value ?? null
  const currentLocale = localeRow?.value ?? 'en'
  const currentCurrency = currencyRow?.value ?? 'EUR'

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
  ]

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">{t('settings.title', 'Settings')}</h1>
        <p className="text-muted-foreground">
          {t(
            'settings.subtitle',
            'Operational diagnostics and exports for your Florin instance.',
          )}
        </p>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle className="text-base">{t('settings.profile', 'Profile')}</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4 text-sm">
            <Row
              label={t('settings.mode', 'Mode')}
              value={t('settings.modeDesktopValue', 'Desktop (SQLite)')}
            />
            <LocaleSettings currentLocale={currentLocale} currentCurrency={currentCurrency} />
            <p className="pt-1 text-[11px] text-muted-foreground">
              {t(
                'settings.modeDesktopHint',
                'Florin Desktop stores all data locally in a SQLite database. No server, no cloud.',
              )}
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">{t('settings.bankSync', 'Bank Sync')}</CardTitle>
          </CardHeader>
          <CardContent>
            <BankingSettings configured={bankingConfigured} currentAppId={bankingAppId} />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">{t('settings.data', 'Data')}</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3 text-sm">
            <p className="text-muted-foreground">
              {t(
                'settings.dataHint',
                'Download every table as a single JSON file. The export is safe to share — no secrets are included.',
              )}
            </p>
            <a
              href="/api/export/json"
              download
              className="inline-flex h-8 items-center rounded-md border border-input bg-background px-3 text-sm font-medium hover:bg-accent hover:text-accent-foreground"
            >
              {t('settings.exportAll', 'Export all data (JSON)')}
            </a>
            <div className="border-t border-border/40 pt-3">
              <ImportData />
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">{t('settings.pinLock', 'PIN Lock')}</CardTitle>
          </CardHeader>
          <CardContent>
            <PinSettings pinEnabled={pinEnabled} />
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

        <Card>
          <CardHeader>
            <CardTitle className="text-base">{t('settings.about', 'About')}</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm text-muted-foreground">
            <p>
              <strong className="text-foreground">
                {t('settings.aboutDatabaseLabel', 'Database:')}
              </strong>{' '}
              {t('settings.aboutDatabaseDesc', 'SQLite with WAL mode. Your data lives in')}{' '}
              <code className="tabular-nums">
                {process.env.FLORIN_DB_PATH || '~/Library/Application Support/Florin/florin.db'}
              </code>
            </p>
            <p>
              <strong className="text-foreground">
                {t('settings.aboutPrivacyLabel', 'Privacy:')}
              </strong>{' '}
              {t(
                'settings.aboutPrivacyDesc',
                'there is no telemetry, no analytics, no third-party scripts. Everything runs on your machine.',
              )}
            </p>
            <BuildInfo version={pkg.version} label={t('settings.aboutBuildLabel', 'Build:')} />
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
      <span className="truncate tabular-nums text-foreground">{value}</span>
    </div>
  )
}
