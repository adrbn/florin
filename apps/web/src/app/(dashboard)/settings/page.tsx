import { count, eq, isNull } from 'drizzle-orm'
import { ExportButton } from '@florin/core/components/settings/export-button'
import { Card, CardContent, CardHeader, CardTitle } from '@florin/core/components/ui/card'
import { db } from '@/db/client'
import { accounts, bankConnections, categories, transactions } from '@/db/schema'
import { getServerT } from '@/lib/locale'
import { exportAllData } from '@/server/actions/export'
import { auth } from '@/server/auth'
import { isEnableBankingConfigured } from '@/server/banking/enable-banking'
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
  ] = await Promise.all([
    db.select({ value: count() }).from(accounts).where(eq(accounts.isArchived, false)),
    db.select({ value: count() }).from(transactions).where(isNull(transactions.deletedAt)),
    db.select({ value: count() }).from(categories).where(eq(categories.isArchived, false)),
    db.select({ value: count() }).from(bankConnections).where(eq(bankConnections.status, 'active')),
    db
      .select({ value: count() })
      .from(transactions)
      .where(eq(transactions.source, 'enable_banking')),
  ])

  const stats: Stat[] = [
    { label: 'Accounts (active)', value: String(accountCountRow[0]?.value ?? 0) },
    { label: 'Transactions (alive)', value: String(transactionCountRow[0]?.value ?? 0) },
    { label: 'Categories', value: String(categoryCountRow[0]?.value ?? 0) },
    { label: 'Bank connections', value: String(activeBankRow[0]?.value ?? 0) },
    { label: 'Bank-API transactions', value: String(activeTransactionRow[0]?.value ?? 0) },
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
            <Row label="Signed in as" value={session?.user?.email ?? '—'} />
            <Row label={t('settings.locale', 'Language')} value="fr-FR" />
            <Row label={t('settings.baseCurrency', 'Base currency')} value="EUR" />
            <p className="pt-2 text-[11px] text-muted-foreground">
              Florin is single-tenant — profile values come from environment variables. To change
              them, edit <code className="font-mono">.env</code> and restart.
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">{t('settings.data', 'Data')}</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3 text-sm">
            <p className="text-muted-foreground">
              Download every table as a single JSON file. Bank consent tokens are stripped from the
              export so the file is safe to share.
            </p>
            <ExportButton onExportAllData={exportAllData} />
            <p className="text-[11px] text-muted-foreground">
              Tip: schedule <code className="font-mono">pg_dump</code> separately for backups that
              include indexes + history.
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
              value={bankingEnabled ? '✅ Configured' : '❌ Not configured'}
            />
            <Row label="App ID" value={env.ENABLE_BANKING_APP_ID ?? '—'} />
            <Row label="Redirect URL" value={env.ENABLE_BANKING_REDIRECT_URL} />
            <p className="pt-2 text-[11px] text-muted-foreground">
              Manage individual bank links from the Accounts page.
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

        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle className="text-base">Self-hosting tips</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm text-muted-foreground">
            <p>
              <strong className="text-foreground">Rotate secrets:</strong> regenerate{' '}
              <code className="font-mono">NEXTAUTH_SECRET</code> with{' '}
              <code className="font-mono">openssl rand -base64 48</code> if you ever suspect
              leakage. Restart the app afterwards — sessions will be invalidated.
            </p>
            <p>
              <strong className="text-foreground">Database backups:</strong>{' '}
              <code className="font-mono">
                docker compose exec db pg_dump -U postgres florin &gt; backup.sql
              </code>
            </p>
            <p>
              <strong className="text-foreground">Bank API quota:</strong> Enable Banking's free
              tier caps live data at 90 days unattended. Past that the app falls back to whatever
              was previously synced.
            </p>
            <p>
              <strong className="text-foreground">Open source posture:</strong> there is no
              telemetry, no analytics, no third-party scripts. Everything runs against your own
              Postgres.
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
