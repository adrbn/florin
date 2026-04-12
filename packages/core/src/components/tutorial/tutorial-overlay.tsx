'use client'

import { useEffect, useRef, useState } from 'react'
import { cn } from '../../lib/utils'
import { Button } from '../ui/button'
import type { TutorialStep } from './tutorial-steps'

interface ElementRect {
  top: number
  left: number
  width: number
  height: number
}

interface TooltipPosition {
  top: number
  left: number
}

interface TutorialOverlayProps {
  steps: TutorialStep[]
  onDismiss: () => void
}

function getElementRect(selector: string): ElementRect | null {
  const el = document.querySelector(selector)
  if (!el) return null
  const rect = el.getBoundingClientRect()
  return {
    top: rect.top + window.scrollY,
    left: rect.left + window.scrollX,
    width: rect.width,
    height: rect.height,
  }
}

const TOOLTIP_WIDTH = 280
const TOOLTIP_OFFSET = 12

function computeTooltipPosition(
  rect: ElementRect,
  tooltipRef: React.RefObject<HTMLDivElement | null>,
): TooltipPosition {
  const tooltipHeight = tooltipRef.current?.offsetHeight ?? 120
  const viewportW = window.innerWidth
  const viewportH = window.innerHeight + window.scrollY

  // Prefer placing tooltip below the target; fall back to above
  let top = rect.top + rect.height + TOOLTIP_OFFSET
  if (top + tooltipHeight > viewportH) {
    top = rect.top - tooltipHeight - TOOLTIP_OFFSET
  }

  // Horizontally center on the target, clamped to viewport
  let left = rect.left + rect.width / 2 - TOOLTIP_WIDTH / 2
  left = Math.max(TOOLTIP_OFFSET, Math.min(left, viewportW - TOOLTIP_WIDTH - TOOLTIP_OFFSET))

  return { top, left }
}

export function TutorialOverlay({ steps, onDismiss }: TutorialOverlayProps) {
  const [currentIndex, setCurrentIndex] = useState(0)
  const [targetRect, setTargetRect] = useState<ElementRect | null>(null)
  const tooltipRef = useRef<HTMLDivElement>(null)

  const step = steps[currentIndex]
  const isFirst = currentIndex === 0
  const isLast = currentIndex === steps.length - 1

  useEffect(() => {
    if (!step) return
    const rect = getElementRect(step.selector)
    setTargetRect(rect)
  }, [step])

  useEffect(() => {
    const handleResize = () => {
      if (!step) return
      setTargetRect(getElementRect(step.selector))
    }
    window.addEventListener('resize', handleResize)
    return () => window.removeEventListener('resize', handleResize)
  }, [step])

  if (!step) return null

  const tooltipPos: TooltipPosition =
    targetRect && tooltipRef.current
      ? computeTooltipPosition(targetRect, tooltipRef)
      : { top: -9999, left: -9999 }

  const handleNext = () => {
    if (isLast) {
      onDismiss()
    } else {
      setCurrentIndex((i) => i + 1)
    }
  }

  const handleBack = () => {
    setCurrentIndex((i) => Math.max(0, i - 1))
  }

  return (
    <div className="pointer-events-none fixed inset-0 z-50">
      {/* Dimmed backdrop with cut-out for the highlighted element */}
      <div className="absolute inset-0 bg-black/50" />

      {targetRect && (
        <div
          className="absolute rounded-md ring-2 ring-primary ring-offset-2 ring-offset-transparent"
          style={{
            top: targetRect.top - 4,
            left: targetRect.left - 4,
            width: targetRect.width + 8,
            height: targetRect.height + 8,
            boxShadow: '0 0 0 9999px rgba(0,0,0,0.5)',
          }}
        />
      )}

      {/* Tooltip */}
      <div
        ref={tooltipRef}
        className={cn(
          'pointer-events-auto absolute z-10 w-[280px] rounded-xl border border-border bg-background p-4 shadow-xl',
        )}
        style={{ top: tooltipPos.top, left: tooltipPos.left }}
      >
        {/* Step indicator */}
        <div className="mb-2 flex items-center justify-between">
          <span className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
            {currentIndex + 1} / {steps.length}
          </span>
          <button
            onClick={onDismiss}
            className="text-[11px] text-muted-foreground underline underline-offset-2 hover:text-foreground"
            type="button"
          >
            Skip tour
          </button>
        </div>

        {/* Dot indicators */}
        <div className="mb-3 flex gap-1">
          {steps.map((_, i) => (
            <span
              key={i}
              className={cn(
                'h-1.5 rounded-full transition-all duration-200',
                i === currentIndex ? 'w-4 bg-primary' : 'w-1.5 bg-muted-foreground/30',
              )}
            />
          ))}
        </div>

        <p className="mb-0.5 text-sm font-semibold">{step.title}</p>
        <p className="mb-4 text-sm text-muted-foreground">{step.description}</p>

        <div className="flex items-center justify-between gap-2">
          <Button
            variant="ghost"
            size="sm"
            onClick={handleBack}
            disabled={isFirst}
            className="h-7 px-2 text-xs"
          >
            ← Back
          </Button>
          <Button size="sm" onClick={handleNext} className="h-7 px-3 text-xs">
            {isLast ? 'Done' : 'Next →'}
          </Button>
        </div>
      </div>
    </div>
  )
}
