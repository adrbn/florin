'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { useT } from '@florin/core/i18n/context'
import { setAppConfig } from '@/server/actions/app-config'

interface AppConfigSettingsProps {
  goalTarget: number
  goalReturnPct: number
  peaCeiling: number
}

export function AppConfigSettings({ goalTarget, goalReturnPct, peaCeiling }: AppConfigSettingsProps) {
  const router = useRouter()
  const t = useT()
  const [goalTargetValue, setGoalTargetValue] = useState(String(goalTarget))
  const [goalReturnPctValue, setGoalReturnPctValue] = useState(String(goalReturnPct))
  const [peaCeilingValue, setPeaCeilingValue] = useState(String(peaCeiling))
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)

  function clamp(raw: string): number {
    const n = Number(raw)
    return Number.isFinite(n) && n >= 0 ? n : 0
  }

  async function handleSave() {
    setSaving(true)
    setSaved(false)
    try {
      await setAppConfig({
        goalTarget: clamp(goalTargetValue),
        goalReturnPct: clamp(goalReturnPctValue),
        peaCeiling: clamp(peaCeilingValue),
      })
      setSaved(true)
      router.refresh()
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="space-y-4 text-sm">
      <p className="text-muted-foreground">{t('appConfig.subtitle', 'Tune the goal target, assumed return, and tax-wrapper ceiling used across your dashboard.')}</p>

      <Field
        label={t('appConfig.goalTarget', 'Goal target')}
        value={goalTargetValue}
        onChange={(v) => { setGoalTargetValue(v); setSaved(false) }}
        disabled={saving}
      />
      <Field
        label={t('appConfig.goalReturnPct', 'Assumed annual return (%)')}
        value={goalReturnPctValue}
        onChange={(v) => { setGoalReturnPctValue(v); setSaved(false) }}
        disabled={saving}
        step="0.1"
      />
      <div className="space-y-1">
        <Field
          label={t('appConfig.peaCeiling', 'PEA / tax-wrapper ceiling')}
          value={peaCeilingValue}
          onChange={(v) => { setPeaCeilingValue(v); setSaved(false) }}
          disabled={saving}
        />
        <p className="text-[11px] text-muted-foreground">{t('appConfig.peaCeilingHint', 'Set to 0 to hide the contribution gauge for accounts with no such cap.')}</p>
      </div>

      <div className="flex items-center gap-3 pt-1">
        <button
          type="button"
          onClick={handleSave}
          disabled={saving}
          className="rounded-md border border-border px-3 py-1.5 text-sm font-medium hover:bg-muted disabled:opacity-50"
        >
          {saving ? t('common.saving', 'Saving…') : t('common.save', 'Save')}
        </button>
        {saved && !saving && (
          <span className="text-xs text-muted-foreground">{t('common.saved', 'Saved')}</span>
        )}
      </div>
    </div>
  )
}

interface FieldProps {
  label: string
  value: string
  onChange: (value: string) => void
  disabled: boolean
  step?: string
}

function Field({ label, value, onChange, disabled, step }: FieldProps) {
  return (
    <div className="flex items-baseline justify-between gap-3 border-b border-border/40 pb-1.5">
      <span className="text-xs uppercase tracking-wide text-muted-foreground">{label}</span>
      <input
        type="number"
        min={0}
        step={step}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        disabled={disabled}
        className="w-32 rounded-md border border-border bg-background px-2 py-1 text-right text-sm tabular-nums text-foreground"
      />
    </div>
  )
}
