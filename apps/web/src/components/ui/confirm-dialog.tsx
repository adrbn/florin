'use client'

import { AlertTriangle } from 'lucide-react'
import type { ReactNode } from 'react'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { cn } from '@/lib/utils'

/**
 * Shared confirmation modal used before any destructive or semi-destructive
 * action (delete, disconnect, merge, reset sync). Looks nicer than
 * `window.confirm`, respects the app theme, and gives the destructive action
 * a red tint so the button weight matches the consequence.
 *
 * Parent owns the open state + the real action handler — the dialog is a
 * purely presentational wrapper around `Dialog` with two buttons.
 */
interface ConfirmDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  title: string
  /** Body copy. Accepts a string or rich nodes so callers can include
   * inline emphasis / a warning list. */
  description: ReactNode
  confirmLabel?: string
  cancelLabel?: string
  /** true → red confirm button + warning icon in the header. */
  destructive?: boolean
  /** Disables the confirm button + shows a pending label. Driven by the
   * parent's `useTransition` pending flag so the user can't double-click. */
  pending?: boolean
  onConfirm: () => void
}

export function ConfirmDialog({
  open,
  onOpenChange,
  title,
  description,
  confirmLabel = 'Confirm',
  cancelLabel = 'Cancel',
  destructive = false,
  pending = false,
  onConfirm,
}: ConfirmDialogProps) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent showCloseButton={false} className="sm:max-w-md">
        <DialogHeader>
          <div className="flex items-start gap-3">
            {destructive && (
              <div
                aria-hidden
                className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-destructive/10 text-destructive"
              >
                <AlertTriangle className="h-4 w-4" />
              </div>
            )}
            <div className="space-y-1.5">
              <DialogTitle>{title}</DialogTitle>
              <DialogDescription className="whitespace-pre-line">
                {description}
              </DialogDescription>
            </div>
          </div>
        </DialogHeader>
        <DialogFooter>
          <Button
            variant="outline"
            onClick={() => onOpenChange(false)}
            disabled={pending}
          >
            {cancelLabel}
          </Button>
          <Button
            variant={destructive ? 'destructive' : 'default'}
            onClick={onConfirm}
            disabled={pending}
            className={cn(pending && 'opacity-70')}
          >
            {pending ? 'Working…' : confirmLabel}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
