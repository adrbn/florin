'use client'

import { useState } from 'react'

const PRESETS: ReadonlyArray<{ icon: string; label: string }> = [
  { icon: '💵', label: 'Cash' },
  { icon: '🏦', label: 'Bank' },
  { icon: '💳', label: 'Card' },
  { icon: '💰', label: 'Savings' },
  { icon: '📈', label: 'Invest' },
  { icon: '🏠', label: 'House' },
  { icon: '🚗', label: 'Car' },
  { icon: '🎓', label: 'Loan' },
  { icon: '⭐', label: 'Star' },
  { icon: '🪙', label: 'Coin' },
  { icon: '🧾', label: 'Receipt' },
  { icon: '💎', label: 'Gem' },
]

const COLOR_PRESETS: ReadonlyArray<string> = [
  '#10b981', // emerald
  '#3b82f6', // blue
  '#f59e0b', // amber
  '#ef4444', // red
  '#a855f7', // purple
  '#0ea5e9', // sky
  '#ec4899', // pink
  '#64748b', // slate
]

interface IconPickerProps {
  iconName: string
  iconValue: string | null
  colorName: string
  colorValue: string | null
}

/**
 * Compact icon + color picker for the account form. Renders hidden inputs
 * (so the existing form action keeps working) plus visible quick-pick swatches
 * the user can click instead of typing emoji codes by hand.
 */
export function IconPicker({ iconName, iconValue, colorName, colorValue }: IconPickerProps) {
  const [icon, setIcon] = useState<string>(iconValue ?? '')
  const [color, setColor] = useState<string>(colorValue ?? '')

  return (
    <div className="space-y-3">
      <input type="hidden" name={iconName} value={icon} />
      <input type="hidden" name={colorName} value={color} />
      <div>
        <p className="mb-2 text-xs font-medium text-muted-foreground">Icon</p>
        <div className="flex flex-wrap gap-1.5">
          {PRESETS.map((p) => (
            <button
              key={p.icon}
              type="button"
              onClick={() => setIcon(p.icon)}
              title={p.label}
              className={`flex h-8 w-8 items-center justify-center rounded-md border text-base transition-colors ${
                icon === p.icon ? 'border-primary bg-primary/10' : 'border-input hover:bg-muted'
              }`}
            >
              {p.icon}
            </button>
          ))}
          <button
            type="button"
            onClick={() => setIcon('')}
            title="Clear icon"
            className="flex h-8 w-8 items-center justify-center rounded-md border border-input text-xs text-muted-foreground hover:bg-muted"
          >
            ✕
          </button>
        </div>
      </div>
      <div>
        <p className="mb-2 text-xs font-medium text-muted-foreground">Color tint</p>
        <div className="flex flex-wrap gap-1.5">
          {COLOR_PRESETS.map((c) => (
            <button
              key={c}
              type="button"
              onClick={() => setColor(c)}
              title={c}
              className={`h-7 w-7 rounded-full border-2 transition-transform ${
                color === c ? 'scale-110 border-foreground' : 'border-transparent'
              }`}
              style={{ backgroundColor: c }}
            />
          ))}
          <button
            type="button"
            onClick={() => setColor('')}
            title="Clear color"
            className="flex h-7 w-7 items-center justify-center rounded-full border border-input text-[10px] text-muted-foreground hover:bg-muted"
          >
            ✕
          </button>
        </div>
      </div>
    </div>
  )
}
