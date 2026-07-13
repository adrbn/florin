'use client'

import { Download, Loader2, RefreshCw } from 'lucide-react'
import { useT } from '../../i18n/context'
import { cn } from '../../lib/utils'

export type UpdateState = 'available' | 'downloading' | 'ready'

export interface UpdateInfo {
  /** Version being offered, without a leading `v` (e.g. `"1.2.25"`). */
  version: string
  state: UpdateState
}

interface UpdatePillProps {
  /** `null` → the app is current; the pill renders nothing. */
  update: UpdateInfo | null
  /**
   * Clicked the pill. The caller decides what that means: the web app opens a
   * modal with the redeploy command, the desktop app restarts to install.
   */
  onClick: () => void
  className?: string
}

/**
 * Attention-drawing "update available" chip for the foot of the sidebar. It is
 * purely presentational — it neither checks for updates nor applies one; the
 * host app wires the `update` state and the `onClick` action. Renders nothing
 * when `update` is `null`, so a current install leaves the sidebar untouched.
 *
 * A single pulsing dot (disabled under `prefers-reduced-motion`) does the
 * attention-grabbing; the pill itself stays readable rather than flashing.
 */
export function UpdatePill({ update, onClick, className }: UpdatePillProps) {
  const t = useT()
  if (!update) return null

  const { state, version } = update
  const downloading = state === 'downloading'
  const ready = state === 'ready'

  const label = downloading
    ? t('update.downloading', 'Downloading update…')
    : ready
      ? t('update.ready', 'Restart to update')
      : t('update.available', 'Update available')

  const Icon = downloading ? Loader2 : ready ? RefreshCw : Download

  return (
    <button
      type="button"
      onClick={onClick}
      disabled={downloading}
      aria-label={`${label} — v${version}`}
      className={cn(
        'flex w-full items-center gap-3 rounded-md border px-3 py-2 text-sm font-medium transition-colors',
        'border-emerald-500/30 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300',
        'hover:bg-emerald-500/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500/40',
        'disabled:cursor-default disabled:hover:bg-emerald-500/10',
        ready && 'border-emerald-500/50 bg-emerald-500/15',
        className,
      )}
    >
      <Icon className={cn('h-4 w-4 shrink-0', downloading && 'animate-spin')} />
      <span className="flex min-w-0 flex-1 flex-col items-start leading-tight">
        <span className="truncate">{label}</span>
        <span className="text-[11px] font-normal text-emerald-700/70 dark:text-emerald-300/70">
          v{version}
        </span>
      </span>
      {!downloading && (
        <span className="relative flex h-2 w-2 shrink-0" aria-hidden="true">
          <span className="absolute inline-flex h-full w-full rounded-full bg-emerald-500/70 motion-safe:animate-ping" />
          <span className="relative inline-flex h-2 w-2 rounded-full bg-emerald-500" />
        </span>
      )}
    </button>
  )
}
