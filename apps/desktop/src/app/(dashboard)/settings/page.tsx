import { count, eq, isNull } from 'drizzle-orm'
import { ExportButton } from '@florin/core/components/settings/export-button'
import { Card, CardContent, CardHeader, CardTitle } from '@florin/core/components/ui/card'
import { db } from '@/db/client'
import { accounts, categories, transactions } from '@/db/schema'
import { exportAllData } from '@/server/actions/export'
import { isPinEnabled } from '@/server/actions/pin'
import { PinSettings } from '@/components/pin-settings'

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
  const [
    accountCountRow,
    transactionCountRow,
    categoryCountRow,
    pinEnabled,
  ] = await Promise.all([
    db.select({ value: count() }).from(accounts).where(eq(accounts.isArchived, false)),
    db.select({ value: count() }).from(transactions).where(isNull(transactions.deletedAt)),
    db.select({ value: count() }).from(categories).where(eq(categories.isArchived, false)),
    isPinEnabled(),
  ])

  const stats: Stat[] = [
    { label: 'Accounts (active)', value: String(accountCountRow[0]?.value ?? 0) },
    { label: 'Transactions (alive)', value: String(transactionCountRow[0]?.value ?? 0) },
    { label: 'Categories', value: String(categoryCountRow[0]?.value ?? 0) },
  ]

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Settings</h1>
        <p className="text-muted-foreground">
          Operational diagnostics and exports for your Florin instance.
        </p>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Profile</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <Row label="Mode" value="Desktop (SQLite)" />
            <Row label="Locale" value="fr-FR" />
            <Row label="Base currency" value="EUR" />
            <p className="pt-2 text-[11px] text-muted-foreground">
              Florin Desktop stores all data locally in a SQLite database. No server, no cloud.
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">Data</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3 text-sm">
            <p className="text-muted-foreground">
              Download every table as a single JSON file. The export is safe to share — no secrets
              are included.
            </p>
            <ExportButton onExportAllData={exportAllData} />
            <p className="text-[11px] text-muted-foreground">
              Tip: back up the <code className="font-mono">florin.db</code> file separately for
              full database snapshots.
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">PIN Lock</CardTitle>
          </CardHeader>
          <CardContent>
            <PinSettings pinEnabled={pinEnabled} />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">Storage</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            {stats.map((s) => (
              <Row key={s.label} label={s.label} value={s.value} />
            ))}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">About</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm text-muted-foreground">
            <p>
              <strong className="text-foreground">Database:</strong> SQLite with WAL mode. Your data
              lives in{' '}
              <code className="font-mono">
                {process.env.FLORIN_DB_PATH || '~/Library/Application Support/Florin/florin.db'}
              </code>
            </p>
            <p>
              <strong className="text-foreground">Privacy:</strong> there is no telemetry, no
              analytics, no third-party scripts. Everything runs on your machine.
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
