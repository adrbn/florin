'use client'

import { useMemo, useState } from 'react'
import { calculateCompound } from '../../../lib/calculators/compound'
import { calculateLoan } from '../../../lib/calculators/loan'
import { parseDecimalInput } from '../../../lib/format/currency'
import { useV2T } from '../i18n/context'
import { useMoney } from '../lib/config'
import { Amount } from '../primitives/amount'
import { Card } from '../primitives/atoms'
import { Segmented } from '../primitives/segmented'
import { Sparkline } from '../primitives/sparkline'
import { Screen } from '../shell/screen'

type Tool = 'compound' | 'loan'

/**
 * Two simulators. Both recompute on every keystroke — there is no "Calculate"
 * button, because on a phone the result appearing as you type is the whole
 * feeling of the thing.
 */
export function ToolsScreen() {
  const t = useV2T()
  const [tool, setTool] = useState<Tool>('compound')

  const hero = (
    <div className="v2-gutter flex flex-col gap-3 pb-1">
      <h2 className="text-[30px] font-semibold leading-tight tracking-[-0.035em]">
        {t('v2.tools.title', 'Tools')}
      </h2>
      <Segmented
        value={tool}
        onChange={setTool}
        options={[
          { value: 'compound', label: t('v2.tools.compound', 'Compound interest') },
          { value: 'loan', label: t('v2.tools.loan', 'Loan') },
        ]}
      />
    </div>
  )

  return (
    <Screen title={t('v2.tools.title', 'Tools')} hero={hero} back="/m">
      {tool === 'compound' ? <CompoundTool /> : <LoanTool />}
    </Screen>
  )
}

function NumField({
  label,
  value,
  onChange,
  suffix,
}: {
  label: string
  value: string
  onChange: (v: string) => void
  suffix?: string
}) {
  return (
    <label className="flex flex-col gap-1.5">
      <span className="v2-eyebrow">{label}</span>
      <span className="relative block">
        <input
          value={value}
          onChange={(e) => onChange(e.target.value)}
          inputMode="decimal"
          autoComplete="off"
          className="v2-input v2-num"
        />
        {suffix && (
          <span className="pointer-events-none absolute right-3.5 top-1/2 -translate-y-1/2 text-[13px] text-[var(--v2-text-3)]">
            {suffix}
          </span>
        )}
      </span>
    </label>
  )
}

function CompoundTool() {
  const t = useV2T()
  const m = useMoney()
  const [initial, setInitial] = useState('5000')
  const [monthly, setMonthly] = useState('300')
  const [rate, setRate] = useState('7')
  const [years, setYears] = useState('20')

  const result = useMemo(
    () =>
      calculateCompound({
        initial: parseDecimalInput(initial, 0),
        monthlyContribution: parseDecimalInput(monthly, 0),
        annualRatePct: parseDecimalInput(rate, 0),
        years: Math.min(60, Math.max(0, parseDecimalInput(years, 0))),
      }),
    [initial, monthly, rate, years],
  )

  return (
    <div className="v2-gutter flex flex-col gap-4">
      <Card className="flex flex-col gap-3 p-4">
        <span className="v2-eyebrow">{t('v2.tools.result', 'Final value')}</span>
        <Amount
          value={result.finalBalance}
          decimals={false}
          className="text-[34px] font-light leading-none"
        />
        <Sparkline
          data={result.series.map((p) => ({ x: p.month, y: p.balance }))}
          height={92}
          color="var(--v2-pos)"
        />
        <div className="flex items-center justify-between">
          <span className="v2-micro">
            {t('v2.tools.contributed', 'Contributed')}{' '}
            <Amount value={result.totalContributed} decimals={false} tone="muted" />
          </span>
          <span className="v2-micro">
            {t('v2.tools.interest', 'Interest')}{' '}
            <Amount value={result.totalInterest} decimals={false} tone="positive" />
          </span>
        </div>
      </Card>

      <div className="grid grid-cols-2 gap-3">
        <NumField label={t('v2.tools.initial', 'Starting capital')} value={initial} onChange={setInitial} suffix={m.currency === 'EUR' ? '€' : ''} />
        <NumField label={t('v2.tools.monthly', 'Monthly contribution')} value={monthly} onChange={setMonthly} suffix={m.currency === 'EUR' ? '€' : ''} />
        <NumField label={t('v2.tools.rate', 'Annual return')} value={rate} onChange={setRate} suffix="%" />
        <NumField label={t('v2.tools.years', 'Duration (years)')} value={years} onChange={setYears} />
      </div>
    </div>
  )
}

function LoanTool() {
  const t = useV2T()
  const m = useMoney()
  const [principal, setPrincipal] = useState('200000')
  const [rate, setRate] = useState('3.5')
  const [years, setYears] = useState('20')

  const result = useMemo(
    () =>
      calculateLoan({
        principal: parseDecimalInput(principal, 0),
        annualRatePct: parseDecimalInput(rate, 0),
        years: Math.min(50, Math.max(0, parseDecimalInput(years, 0))),
      }),
    [principal, rate, years],
  )

  return (
    <div className="v2-gutter flex flex-col gap-4">
      <Card className="flex flex-col gap-3 p-4">
        <span className="v2-eyebrow">{t('v2.tools.payment', 'Monthly payment')}</span>
        <Amount
          value={result.monthlyPayment}
          className="text-[34px] font-light leading-none"
        />
        {result.schedule.length > 1 && (
          <Sparkline
            data={result.schedule.map((s) => ({ x: s.month, y: s.remaining }))}
            height={92}
            color="var(--v2-neg)"
          />
        )}
        <div className="flex items-center justify-between">
          <span className="v2-micro">
            {t('v2.tools.totalPaid', 'Total repaid')}{' '}
            <Amount value={result.totalPaid} decimals={false} tone="muted" />
          </span>
          <span className="v2-micro">
            {t('v2.tools.totalCost', 'Total interest cost')}{' '}
            <Amount value={result.totalInterest} decimals={false} tone="negative" />
          </span>
        </div>
      </Card>

      <div className="grid grid-cols-2 gap-3">
        <NumField label={t('v2.tools.amount', 'Amount borrowed')} value={principal} onChange={setPrincipal} suffix={m.currency === 'EUR' ? '€' : ''} />
        <NumField label={t('v2.tools.loanRate', 'Annual rate')} value={rate} onChange={setRate} suffix="%" />
        <NumField label={t('v2.tools.loanYears', 'Duration (years)')} value={years} onChange={setYears} />
      </div>
    </div>
  )
}
