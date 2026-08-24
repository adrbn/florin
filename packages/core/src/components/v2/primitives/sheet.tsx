'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { X } from 'lucide-react'
import { cn } from '../../../lib/utils'

const CLOSE_MS = 200
/** Past this many pixels — or this fast — the sheet commits to closing. */
const DISMISS_PX = 110
const DISMISS_VELOCITY = 0.55

export interface SheetProps {
  open: boolean
  onClose: () => void
  title?: string
  /** Right-aligned header slot (a Save button, a filter count…). */
  action?: React.ReactNode
  children: React.ReactNode
  className?: string
}

/**
 * Bottom sheet with drag-to-dismiss.
 *
 * Two details make it feel native rather than "a modal that slides":
 *  - the drag is tracked on the *grab area only* (grabber + header), so a
 *    scrollable body still scrolls instead of dragging the sheet down;
 *  - release is judged on velocity as well as distance, so a quick flick
 *    dismisses even from 30px, which is how every iOS sheet behaves.
 */
export function Sheet({ open, onClose, title, action, children, className }: SheetProps) {
  const [mounted, setMounted] = useState(false)
  const [visible, setVisible] = useState(false)
  const [closing, setClosing] = useState(false)
  const panelRef = useRef<HTMLDivElement>(null)
  const drag = useRef<{ startY: number; startT: number; y: number } | null>(null)

  useEffect(() => setMounted(true), [])

  const finishClose = useCallback(() => {
    setClosing(true)
    window.setTimeout(() => {
      setVisible(false)
      setClosing(false)
      const el = panelRef.current
      if (el) el.style.transform = ''
      onClose()
    }, CLOSE_MS)
  }, [onClose])

  useEffect(() => {
    if (open) {
      setVisible(true)
      setClosing(false)
    } else if (visible && !closing) {
      // Parent closed us programmatically (e.g. after a successful save).
      setVisible(false)
    }
  }, [open, visible, closing])

  /*
   * Tell a native host that a sheet owns the screen.
   *
   * The iOS shell floats its tab bar above this web view, so without this the
   * bar sits on top of the sheet and covers its actions. There is no way for
   * the page to know it is embedded, so it just posts; in a browser the handler
   * is absent and the call is skipped.
   */
  useEffect(() => {
    const bridge = (
      window as unknown as {
        webkit?: { messageHandlers?: { florin?: { postMessage: (m: unknown) => void } } }
      }
    ).webkit?.messageHandlers?.florin
    bridge?.postMessage({ type: 'sheet', open: visible })
    return () => bridge?.postMessage({ type: 'sheet', open: false })
  }, [visible])

  // Escape closes; body scroll locks while a sheet owns the screen.
  useEffect(() => {
    if (!visible) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.stopPropagation()
        finishClose()
      }
    }
    document.addEventListener('keydown', onKey)
    const prev = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    panelRef.current?.focus({ preventScroll: true })
    return () => {
      document.removeEventListener('keydown', onKey)
      document.body.style.overflow = prev
    }
  }, [visible, finishClose])

  const onPointerDown = (e: React.PointerEvent) => {
    if (e.pointerType === 'mouse' && e.button !== 0) return
    drag.current = { startY: e.clientY, startT: performance.now(), y: 0 }
    ;(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId)
    const el = panelRef.current
    if (el) el.style.transition = 'none'
  }

  const onPointerMove = (e: React.PointerEvent) => {
    const d = drag.current
    const el = panelRef.current
    if (!d || !el) return
    // Rubber-band upward drags instead of letting the sheet fly off the top.
    const raw = e.clientY - d.startY
    d.y = raw > 0 ? raw : raw / 4
    el.style.transform = `translateY(${d.y}px)`
  }

  const onPointerUp = (e: React.PointerEvent) => {
    const d = drag.current
    const el = panelRef.current
    drag.current = null
    if (!d || !el) return
    ;(e.currentTarget as HTMLElement).releasePointerCapture?.(e.pointerId)
    el.style.transition = ''
    const velocity = d.y / Math.max(1, performance.now() - d.startT)
    if (d.y > DISMISS_PX || velocity > DISMISS_VELOCITY) {
      el.style.transform = 'translateY(100%)'
      window.setTimeout(() => {
        el.style.transform = ''
        setVisible(false)
        onClose()
      }, CLOSE_MS)
      return
    }
    el.style.transform = ''
  }

  if (!mounted || !visible) return null

  return createPortal(
    /*
     * The wrapper re-establishes the v2 token scope. `createPortal` moves this
     * subtree under <body>, outside `[data-florin-v2]`, so without it every
     * `var(--v2-*)` in the sheet resolves to nothing and the panel renders
     * transparent and unpadded. It is a static, zero-height element — both
     * children are position:fixed — so it costs no layout.
     */
    <div data-florin-v2>
      <div
        className="v2-backdrop"
        data-closing={closing || undefined}
        onClick={finishClose}
        aria-hidden
      />
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-label={title}
        tabIndex={-1}
        data-closing={closing || undefined}
        className={cn('v2-sheet outline-none', className)}
      >
        <div
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerUp}
          onPointerCancel={onPointerUp}
          className="flex-none touch-none"
        >
          <div className="v2-grabber" />
          {(title || action) && (
            <div className="flex items-center gap-3 px-[var(--v2-gutter)] pb-3 pt-1.5">
              <h2 className="min-w-0 flex-1 truncate text-[17px] font-semibold tracking-[-0.02em]">
                {title}
              </h2>
              {action}
              <button
                type="button"
                onClick={finishClose}
                aria-label="Close"
                className="v2-iconbtn h-8 w-8"
              >
                <X className="h-4 w-4" />
              </button>
            </div>
          )}
        </div>
        <div className="v2-sheet-body">{children}</div>
      </div>
    </div>,
    document.body,
  )
}
