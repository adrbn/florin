'use client'

import { useState, useTransition } from 'react'
import { ChevronLeft, ChevronRight } from 'lucide-react'
import { usePathname, useRouter } from 'next/navigation'
import type { MonthPlan, PlanCategory } from '../../../types'
import { parseDecimalInput } from '../../../lib/format/currency'
import { useV2T } from '../i18n/context'
import { useMoney, useV2Config } from '../lib/config'
import { Amount } from '../primitives/amount'
import { Card, Empty, Pill, Section, Track } from '../primitives/atoms'
import { RowGroup } from '../primitives/row'
import { Sheet } from '../primitives/sheet'
import { Screen } from '../shell/screen'
import { cn } from '../../../lib/utils'

export function PlanScreen({
  plan,
  onSetAssigned,
}: {
  plan: MonthPlan
  onSetAssigned: (input: {
    year: number
    month: number
    categoryId: string
    amount: number
  }) => Promise<unknown>
}) {
  const t = useV2T()
  const { tag } = useV2Config()
  const router = useRouter()
  const pathname = usePathname() ?? '/m/plan'
  const [editing, setEditing] = useState<PlanCategory | null>(null)

  const monthDate = new Date(plan.year, plan.month - 1, 1)
  const monthName = new Intl.DateTimeFormat(tag, { month: 'long', year: 'numeric' }).format(
    monthDate,
  )

  const step = (delta: number) => {
    const d = new Date(plan.year, plan.month - 1 + delta, 1)
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
    router.push(`${pathname}?month=${key}` as never)
  }

  const over = plan.readyToAssign < 0

  const hero = (
    <div className="v2-gutter flex flex-col gap-3 pb-1">
      {/* One control, not two. Round icon buttons here read as a second row of
          back/forward navigation directly under the header's own back chevron;
          wrapping the stepper in a single pill makes it obviously a month
          picker instead. */}
      <div className="v2-inset mx-auto flex h-9 items-center gap-1 self-center px-1">
        <button
          type="button"
          onClick={() => step(-1)}
          aria-label={t('v2.plan.prevMonth', 'Previous month')}
          className="grid h-7 w-7 place-items-center rounded-full text-[var(--v2-text-2)] active:scale-90"
        >
          <ChevronLeft className="h-4 w-4" />
        </button>
        <span className="v2-title min-w-[9.5rem] text-center capitalize">{monthName}</span>
        <button
          type="button"
          onClick={() => step(1)}
          aria-label={t('v2.plan.nextMonth', 'Next month')}
          className="grid h-7 w-7 place-items-center rounded-full text-[var(--v2-text-2)] active:scale-90"
        >
          <ChevronRight className="h-4 w-4" />
        </button>
      </div>

      <Card className="flex flex-col gap-2 p-4">
        <span className="v2-eyebrow">
          {over ? t('v2.plan.overAssigned', 'Assigned too much') : t('v2.plan.readyToAssign', 'Ready to assign')}
        </span>
        <Amount
          value={plan.readyToAssign}
          tone={over ? 'negative' : 'positive'}
          className="text-[32px] font-light leading-none"
        />
        <div className="flex flex-wrap items-center gap-2 pt-1">
          <Pill>
            {plan.incomeIsEstimated
              ? t('v2.plan.incomeExpected', 'Income expected')
              : t('v2.plan.income', 'Income this month')}{' '}
            {plan.incomeIsEstimated && '≈ '}
            <Amount value={plan.expectedIncome ?? plan.income} decimals={false} />
          </Pill>
          <Pill>
            {t('v2.plan.assigned', 'Assigned')}{' '}
            <Amount value={plan.totalAssigned} decimals={false} />
          </Pill>
          {plan.overspentCount > 0 && (
            <Pill tone="negative">
              {t('v2.plan.overspent', { count: plan.overspentCount }, '{count} overspent')}
            </Pill>
          )}
        </div>
      </Card>
    </div>
  )

  return (
    <Screen title={t('v2.plan.title', 'Plan')} hero={hero} back="/m">
      {plan.groups.length === 0 && (
        <Empty title={t('v2.plan.empty', 'No expense categories')} />
      )}

      {plan.groups.map((group) => (
        <Section
          key={group.id}
          title={group.name}
          action={
            <span className="v2-micro">
              <Amount value={group.available} decimals={false} tone="muted" />
            </span>
          }
        >
          <div className="v2-gutter">
            <RowGroup>
              {group.categories.map((c) => {
                const pct = c.assigned > 0 ? (c.spent / c.assigned) * 100 : c.spent > 0 ? 100 : 0
                const overspent = c.available < 0
                return (
                  <button
                    key={c.id}
                    type="button"
                    onClick={() => setEditing(c)}
                    className="v2-row v2-row-tap flex-col items-stretch gap-2"
                  >
                    <span className="flex items-baseline gap-2">
                      {c.emoji && <span className="text-[14px] leading-none">{c.emoji}</span>}
                      <span className="v2-title min-w-0 flex-1 truncate text-left">{c.name}</span>
                      <Amount
                        value={c.available}
                        decimals={false}
                        tone={overspent ? 'negative' : 'neutral'}
                        className="text-[14px]"
                      />
                    </span>
                    <Track
                      pct={pct}
                      color={overspent ? 'var(--v2-neg)' : 'var(--v2-accent)'}
                      className="h-[5px]"
                    />
                    <span className="v2-micro flex justify-between">
                      <span>
                        {t('v2.plan.spent', 'Spent')}{' '}
                        <Amount value={c.spent} decimals={false} tone="muted" />
                      </span>
                      <span>
                        {t('v2.plan.assigned', 'Assigned')}{' '}
                        <Amount value={c.assigned} decimals={false} tone="muted" />
                      </span>
                    </span>
                  </button>
                )
              })}
            </RowGroup>
          </div>
        </Section>
      ))}

      <AssignSheet
        category={editing}
        year={plan.year}
        month={plan.month}
        onClose={() => setEditing(null)}
        onSetAssigned={onSetAssigned}
      />
    </Screen>
  )
}

function AssignSheet({
  category,
  year,
  month,
  onClose,
  onSetAssigned,
}: {
  category: PlanCategory | null
  year: number
  month: number
  onClose: () => void
  onSetAssigned: (input: {
    year: number
    month: number
    categoryId: string
    amount: number
  }) => Promise<unknown>
}) {
  const t = useV2T()
  const m = useMoney()
  const router = useRouter()
  const [pending, start] = useTransition()
  const [draft, setDraft] = useState('')
  const [seen, setSeen] = useState<string | null>(null)

  // Seed the field from the category the sheet was opened for, once per open.
  if (category && seen !== category.id) {
    setSeen(category.id)
    setDraft(category.assigned ? String(category.assigned) : '')
  }
  if (!category && seen !== null) setSeen(null)

  const submit = () => {
    if (!category) return
    start(async () => {
      await onSetAssigned({
        year,
        month,
        categoryId: category.id,
        amount: parseDecimalInput(draft, 0),
      })
      router.refresh()
      onClose()
    })
  }

  return (
    <Sheet
      open={category !== null}
      onClose={onClose}
      title={category ? `${category.emoji ? `${category.emoji} ` : ''}${category.name}` : undefined}
    >
      {category && (
        <div className="v2-gutter flex flex-col gap-4 pb-4 pt-1">
          <div className="grid grid-cols-2 gap-3">
            <div className="v2-inset flex flex-col gap-1 p-3.5">
              <span className="v2-eyebrow">{t('v2.plan.spent', 'Spent')}</span>
              <Amount value={category.spent} className="text-[18px] font-light" />
            </div>
            <div className="v2-inset flex flex-col gap-1 p-3.5">
              <span className="v2-eyebrow">{t('v2.plan.available', 'Available')}</span>
              <Amount
                value={category.available}
                tone={category.available < 0 ? 'negative' : 'neutral'}
                className="text-[18px] font-light"
              />
            </div>
          </div>

          <label className="flex flex-col gap-1.5">
            <span className="v2-eyebrow">{t('v2.plan.setAmount', 'Assigned amount')}</span>
            <input
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              inputMode="decimal"
              autoComplete="off"
              placeholder="0"
              className="v2-input v2-num text-[20px]"
            />
          </label>

          {/* Two shortcuts that cover most of the real editing: match what was
              actually spent, or clear the line entirely. */}
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => setDraft(String(Math.round(category.spent)))}
              className="v2-pill"
            >
              = {m.fmt(category.spent, { decimals: false })}
            </button>
            <button type="button" onClick={() => setDraft('0')} className="v2-pill">
              0
            </button>
          </div>

          <button
            type="button"
            disabled={pending}
            onClick={submit}
            className={cn('v2-btn v2-btn-primary w-full')}
          >
            {pending ? t('v2.common.saving', 'Saving…') : t('v2.common.save', 'Save')}
          </button>
        </div>
      )}
    </Sheet>
  )
}
