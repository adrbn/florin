'use client'

import { useState } from 'react'
import { AlertCircle, CheckCircle2, ChevronDown, ChevronRight, Clock } from 'lucide-react'
import { useT } from '../../i18n/context'
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'

export interface SyncLogAccountRow {
  accountUid: string
  accountName: string | null
  balanceFetched: boolean
  balanceError: string | null
  detailsError: string | null
  txFetched: number
  txInserted: number
  txError: string | null
}

export interface SyncLogRunRow {
  id: string
  connectionLabel: string
  trigger: 'manual' | 'scheduler' | 'initial' | string
  startedAt: string // ISO
  finishedAt: string | null // ISO
  status: 'running' | 'ok' | 'partial' | 'error' | string
  accountsTotal: number
  accountsOk: number
  txInserted: number
  errorSummary: string | null
  durationMs: number | null
  accounts: ReadonlyArray<SyncLogAccountRow>
}

export interface SyncLogCardProps {
  runs: ReadonlyArray<SyncLogRunRow>
}

/**
 * Settings → Sync log. Shows the last N sync runs with per-account detail.
 *
 * This is deliberately dense and not interactive beyond expansion: it's a
 * forensic panel for "why did the bank return 0 transactions", not a report
 * view. Each run header summarizes counts; clicking it drops down a table of
 * per-account results with error text so the user can paste them into an
 * issue or email when something breaks.
 */
export function SyncLogCard({ runs }: SyncLogCardProps) {
  const t = useT()

  if (runs.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="text-base">{t('settings.syncLog', 'Sync log')}</CardTitle>
        </CardHeader>
        <CardContent className="text-sm text-muted-foreground">
          {t(
            'settings.syncLogEmpty',
            'No sync runs recorded yet. Connect a bank and the first sync will appear here.',
          )}
        </CardContent>
      </Card>
    )
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">{t('settings.syncLog', 'Sync log')}</CardTitle>
      </CardHeader>
      <CardContent className="p-0">
        <ul className="divide-y divide-border/60">
          {runs.map((run) => (
            <SyncLogRun key={run.id} run={run} />
          ))}
        </ul>
      </CardContent>
    </Card>
  )
}

function SyncLogRun({ run }: { run: SyncLogRunRow }) {
  const t = useT()
  const [open, setOpen] = useState(false)
  const Icon =
    run.status === 'ok'
      ? CheckCircle2
      : run.status === 'running'
        ? Clock
        : AlertCircle
  const iconTint =
    run.status === 'ok'
      ? 'text-emerald-500'
      : run.status === 'partial'
        ? 'text-amber-500'
        : run.status === 'error'
          ? 'text-red-500'
          : 'text-muted-foreground'

  return (
    <li>
      <button
        type="button"
        className="flex w-full items-center gap-3 px-4 py-2.5 text-left hover:bg-muted/40"
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
      >
        {open ? (
          <ChevronDown className="h-3.5 w-3.5 text-muted-foreground" />
        ) : (
          <ChevronRight className="h-3.5 w-3.5 text-muted-foreground" />
        )}
        <Icon className={`h-4 w-4 shrink-0 ${iconTint}`} />
        <div className="flex min-w-0 flex-1 items-baseline gap-3">
          <span className="truncate text-sm font-medium">{run.connectionLabel}</span>
          <span className="shrink-0 text-[11px] uppercase tracking-wide text-muted-foreground">
            {run.trigger}
          </span>
          <span className="ml-auto shrink-0 text-xs tabular-nums text-muted-foreground">
            {formatStartedAt(run.startedAt)}
          </span>
        </div>
      </button>
      <div className="flex flex-wrap gap-x-4 gap-y-1 px-4 pb-2 pl-11 text-[11px] text-muted-foreground">
        <span>
          {t('settings.syncLogAccounts', 'Accounts')}: {run.accountsOk}/{run.accountsTotal}
        </span>
        <span>
          {t('settings.syncLogInserted', 'New tx')}: <span className="tabular-nums">{run.txInserted}</span>
        </span>
        {run.durationMs != null && (
          <span>
            {t('settings.syncLogDuration', 'Duration')}:{' '}
            <span className="tabular-nums">{formatDuration(run.durationMs)}</span>
          </span>
        )}
      </div>
      {run.errorSummary && (
        <p className="px-4 pb-2 pl-11 text-[11px] text-red-500/80 break-words">{run.errorSummary}</p>
      )}
      {open && (
        <div className="border-t border-border/40 bg-muted/20 px-4 py-3 pl-11">
          {run.accounts.length === 0 ? (
            <p className="text-[11px] text-muted-foreground">
              {t(
                'settings.syncLogNoAccounts',
                'This run never reached the account list — likely a session or network error.',
              )}
            </p>
          ) : (
            <table className="w-full text-[11px]">
              <thead className="text-muted-foreground">
                <tr>
                  <th className="pb-1 text-left font-medium">
                    {t('settings.syncLogColAccount', 'Account')}
                  </th>
                  <th className="pb-1 text-right font-medium">
                    {t('settings.syncLogColFetched', 'Fetched')}
                  </th>
                  <th className="pb-1 text-right font-medium">
                    {t('settings.syncLogColInserted', 'Inserted')}
                  </th>
                  <th className="pb-1 text-left font-medium">
                    {t('settings.syncLogColIssues', 'Issues')}
                  </th>
                </tr>
              </thead>
              <tbody className="align-top">
                {run.accounts.map((a) => (
                  <tr key={a.accountUid} className="border-t border-border/30">
                    <td className="py-1 pr-2">
                      <div className="font-medium">{a.accountName ?? '—'}</div>
                      <div className="text-muted-foreground">
                        <code className="text-[10px]">{a.accountUid.slice(0, 8)}…</code>
                      </div>
                    </td>
                    <td className="py-1 text-right tabular-nums">{a.txFetched}</td>
                    <td className="py-1 text-right tabular-nums">{a.txInserted}</td>
                    <td className="py-1 pl-2">
                      {a.detailsError && <Issue label="details" msg={a.detailsError} />}
                      {a.balanceError && <Issue label="balance" msg={a.balanceError} />}
                      {!a.balanceError && !a.balanceFetched && !a.detailsError && (
                        <span className="text-muted-foreground">
                          {t('settings.syncLogNoBalance', 'balance: not fetched')}
                        </span>
                      )}
                      {a.txError && <Issue label="tx" msg={a.txError} />}
                      {!a.detailsError && !a.balanceError && !a.txError && (
                        <span className="text-emerald-500">
                          {t('settings.syncLogOk', 'ok')}
                        </span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}
    </li>
  )
}

function Issue({ label, msg }: { label: string; msg: string }) {
  return (
    <div className="text-red-500/80">
      <span className="font-medium">{label}:</span> {msg}
    </div>
  )
}

function formatStartedAt(iso: string): string {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return iso
  const now = Date.now()
  const diff = now - d.getTime()
  const minutes = Math.floor(diff / 60_000)
  if (minutes < 1) return 'just now'
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  if (days < 7) return `${days}d ago`
  return d.toLocaleDateString()
}

function formatDuration(ms: number): string {
  if (ms < 1000) return `${ms}ms`
  const s = ms / 1000
  if (s < 60) return `${s.toFixed(1)}s`
  const m = Math.floor(s / 60)
  const rem = Math.round(s - m * 60)
  return `${m}m ${rem}s`
}
