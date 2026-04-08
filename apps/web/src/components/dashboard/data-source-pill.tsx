import { CloudOff, Database, FileSpreadsheet, PlugZap } from 'lucide-react'
import { getDataSourceInfo } from '@/server/queries/dashboard'

const FR_DATETIME = new Intl.DateTimeFormat('fr-FR', {
  day: '2-digit',
  month: 'short',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
})

/**
 * Header pill that exposes WHERE the dashboard numbers come from.
 *
 * Three sources are possible:
 *   - `enable_banking` — live PSD2 sync via Enable Banking (real bank API)
 *   - `legacy` — one-shot import from FINANCES.xlsx (frozen snapshot)
 *   - `manual` — created/edited via the Accounts page
 *
 * The pill makes the active source unmissable so you never wonder whether the
 * dashboard is showing fetched data or a copy-paste of your spreadsheet.
 */
export async function DataSourcePill() {
  const info = await getDataSourceInfo()

  if (info.kind === 'empty') {
    return (
      <span className="inline-flex items-center gap-1.5 rounded-full border border-dashed border-muted-foreground/40 bg-muted/30 px-2.5 py-1 text-xs text-muted-foreground">
        <Database className="h-3.5 w-3.5" />
        No accounts yet
      </span>
    )
  }

  if (info.hasBankApi) {
    return (
      <span className="inline-flex items-center gap-1.5 rounded-full border border-emerald-500/40 bg-emerald-500/10 px-2.5 py-1 text-xs text-emerald-700 dark:text-emerald-300">
        <PlugZap className="h-3.5 w-3.5" />
        Bank API · live
      </span>
    )
  }

  const importedLabel = info.lastImportAt
    ? `imported ${FR_DATETIME.format(info.lastImportAt)}`
    : 'no recent import'

  if (info.kind === 'legacy_xlsx') {
    return (
      <span
        className="inline-flex items-center gap-1.5 rounded-full border border-amber-500/40 bg-amber-500/10 px-2.5 py-1 text-xs text-amber-800 dark:text-amber-200"
        title="Numbers come from the legacy XLSX importer — they are NOT fetched from any bank API. Re-run the importer or edit accounts manually to update."
      >
        <FileSpreadsheet className="h-3.5 w-3.5" />
        Legacy XLSX · {importedLabel}
      </span>
    )
  }

  if (info.kind === 'mixed') {
    return (
      <span
        className="inline-flex items-center gap-1.5 rounded-full border border-amber-500/40 bg-amber-500/10 px-2.5 py-1 text-xs text-amber-800 dark:text-amber-200"
        title={`${info.legacyAccounts} legacy XLSX + ${info.manualAccounts} manual accounts. No live bank-API sync.`}
      >
        <CloudOff className="h-3.5 w-3.5" />
        XLSX + manual · no bank sync
      </span>
    )
  }

  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-full border border-sky-500/40 bg-sky-500/10 px-2.5 py-1 text-xs text-sky-800 dark:text-sky-200"
      title="All accounts are manually maintained. No bank API sync configured."
    >
      <Database className="h-3.5 w-3.5" />
      Manual entry only
    </span>
  )
}
