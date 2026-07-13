'use client'

import { useState } from 'react'
import { Check, Copy, ExternalLink } from 'lucide-react'
import { Button } from '../ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '../ui/dialog'
import { useT } from '../../i18n/context'

interface UpdateModalProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  /** Version being offered, without a leading `v` (e.g. `"1.2.25"`). */
  version: string
  /** GitHub release page for the changelog. */
  changelogUrl: string
  /** Shell command that redeploys the self-hosted container. */
  command: string
}

/**
 * Shown when the self-hosted web instance is behind the latest GitHub release.
 * A Docker container can't replace itself, so rather than fake a one-click
 * "update" we give the user exactly what they need to do it themselves: the new
 * version, a changelog link, and the redeploy command ready to copy.
 */
export function UpdateModal({
  open,
  onOpenChange,
  version,
  changelogUrl,
  command,
}: UpdateModalProps) {
  const t = useT()
  const [copied, setCopied] = useState(false)

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(command)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch {
      // Clipboard blocked (insecure context / denied permission) — the command
      // is on screen for manual copy, so fail quietly rather than error.
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t('update.modalTitle', 'Update available')}</DialogTitle>
          <DialogDescription>
            {t(
              'update.modalBody',
              { version },
              'Florin v{version} is available. Redeploy your self-hosted instance to update:',
            )}
          </DialogDescription>
        </DialogHeader>

        <div className="flex items-stretch gap-2">
          <code className="min-w-0 flex-1 overflow-x-auto whitespace-pre rounded-md border border-border bg-muted/50 px-3 py-2 font-mono text-[12px] leading-relaxed">
            {command}
          </code>
          <Button
            type="button"
            variant="outline"
            size="icon"
            onClick={copy}
            aria-label={t('update.copyCommand', 'Copy command')}
            className="shrink-0 self-center"
          >
            {copied ? <Check className="text-emerald-500" /> : <Copy />}
          </Button>
        </div>

        <a
          href={changelogUrl}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-1.5 text-[13px] text-muted-foreground underline-offset-4 hover:text-foreground hover:underline"
        >
          <ExternalLink className="h-3.5 w-3.5" />
          {t('update.viewChangelog', 'View changelog on GitHub')}
        </a>
      </DialogContent>
    </Dialog>
  )
}
