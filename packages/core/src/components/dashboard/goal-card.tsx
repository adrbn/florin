'use client'

import { useMemo } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'
import { useT } from '../../i18n/context'
import { createCurrencyFormatter } from '../../lib/format/currency'
import type { GoalProjection } from '../../types/index'

export interface GoalCardProps {
  projection: GoalProjection
  locale: string
}

/** Colours for the versé-vs-marché split bar (match the holdings palette). */
const CONTRIBUTED_COLOR = '#3b82f6'
const MARKET_COLOR = '#10b981'

/**
 * Format a month count as "X ans et Y mois" / "X yrs Y mo" using the locale.
 * Single-unit cases ("2 ans", "5 mois") drop the empty part.
 */
function formatDuration(
  months: number,
  t: ReturnType<typeof useT>,
): string {
  const years = Math.floor(months / 12)
  const rem = months % 12
  const yearsPart =
    years > 0 ? t('goal.years', { n: years }, `${years} yr${years === 1 ? '' : 's'}`) : ''
  const monthsPart =
    rem > 0 || years === 0
      ? t('goal.months', { n: rem }, `${rem} mo`)
      : ''
  if (yearsPart && monthsPart) {
    return t('goal.yearsMonths', { years: yearsPart, months: monthsPart }, `${yearsPart} ${monthsPart}`)
  }
  return yearsPart || monthsPart
}

/**
 * 100 k€ goal projection card. Given a {@link GoalProjection} computed upstream
 * (DCA + assumed return), it shows the headline reach date, the versé-vs-marché
 * split of the eventual target, and the assumptions used — with the return rate
 * clearly flagged as a non-guaranteed hypothesis.
 *
 * When the target is unreachable (no contribution and no growth), it renders an
 * empty state nudging the user to increase their savings rate. Receives the
 * locale as a prop so it builds its own formatter and stays server-free.
 */
export function GoalCard({ projection, locale }: GoalCardProps) {
  const t = useT()
  const fmt = useMemo(() => createCurrencyFormatter(locale, 'EUR'), [locale])
  const dateFmt = useMemo(
    () => new Intl.DateTimeFormat(locale, { month: 'long', year: 'numeric' }),
    [locale],
  )

  const targetLabel = fmt.format(projection.target)
  const reachable = projection.monthsToReach !== null

  const split = useMemo(() => {
    const total = projection.contributed + projection.marketGrowth
    if (total <= 0) return { contributedPct: 0, marketPct: 0 }
    return {
      contributedPct: (projection.contributed / total) * 100,
      marketPct: (projection.marketGrowth / total) * 100,
    }
  }, [projection.contributed, projection.marketGrowth])

  const headline = useMemo(() => {
    if (projection.monthsToReach === null) return null
    if (projection.monthsToReach === 0) {
      return t('goal.alreadyReached', { target: targetLabel }, `${targetLabel} already reached`)
    }
    const dateStr = projection.reachDateIso
      ? dateFmt.format(new Date(`${projection.reachDateIso}T00:00:00`))
      : formatDuration(projection.monthsToReach, t)
    return t(
      'goal.headline',
      { target: targetLabel, when: dateStr },
      `At this pace, ${targetLabel} reached by ${dateStr}`,
    )
  }, [projection.monthsToReach, projection.reachDateIso, targetLabel, dateFmt, t])

  return (
    <Card className="flex h-full flex-col">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium">
          {t('goal.title', { target: targetLabel }, `Goal: ${targetLabel}`)}
        </CardTitle>
        <p className="mt-0.5 text-[11px] text-muted-foreground">
          {t('goal.currentValue', { amount: fmt.format(projection.currentValue) }, `Today: ${fmt.format(projection.currentValue)}`)}
        </p>
      </CardHeader>
      <CardContent className="flex min-h-0 flex-1 flex-col gap-3 pb-3">
        {!reachable ? (
          <div className="flex flex-1 flex-col justify-center gap-1.5 rounded-md border border-border/60 bg-muted/20 p-3">
            <p className="text-sm font-medium">{t('goal.emptyTitle', 'No projection yet')}</p>
            <p className="text-xs text-muted-foreground">
              {t('goal.empty', 'Augmente ton épargne pour voir une projection.')}
            </p>
          </div>
        ) : (
          <>
            <p className="text-sm font-semibold leading-snug">{headline}</p>

            {/* versé vs marché split */}
            <div className="space-y-1.5">
              <div className="flex h-2.5 w-full overflow-hidden rounded-full bg-muted">
                {split.contributedPct > 0 && (
                  <div
                    style={{ width: `${split.contributedPct}%`, backgroundColor: CONTRIBUTED_COLOR }}
                    aria-hidden="true"
                  />
                )}
                {split.marketPct > 0 && (
                  <div
                    style={{ width: `${split.marketPct}%`, backgroundColor: MARKET_COLOR }}
                    aria-hidden="true"
                  />
                )}
              </div>
              <div className="grid grid-cols-2 gap-2 text-[11px] tabular-nums">
                <div className="flex items-center gap-1.5">
                  <span
                    className="inline-block h-2 w-2 shrink-0 rounded-full"
                    style={{ backgroundColor: CONTRIBUTED_COLOR }}
                    aria-hidden="true"
                  />
                  <span className="min-w-0">
                    <span className="text-muted-foreground">{t('goal.contributed', 'Versé')}: </span>
                    <span className="font-medium">{fmt.format(projection.contributed)}</span>
                  </span>
                </div>
                <div className="flex items-center justify-end gap-1.5 text-right">
                  <span
                    className="inline-block h-2 w-2 shrink-0 rounded-full"
                    style={{ backgroundColor: MARKET_COLOR }}
                    aria-hidden="true"
                  />
                  <span className="min-w-0">
                    <span className="text-muted-foreground">{t('goal.market', 'Marché')}: </span>
                    <span className="font-medium">{fmt.format(projection.marketGrowth)}</span>
                  </span>
                </div>
              </div>
            </div>

            {/* assumptions */}
            <div className="mt-auto space-y-0.5 border-t border-border/40 pt-2 text-[11px] text-muted-foreground">
              <p>
                {t(
                  'goal.assumptions',
                  {
                    contribution: fmt.format(projection.monthlyContribution),
                    rate: String(projection.annualReturnPct),
                  },
                  `${fmt.format(projection.monthlyContribution)}/mo · ${projection.annualReturnPct}%/yr`,
                )}
              </p>
              <p className="italic">
                {t('goal.disclaimer', 'Hypothèse, non garanti.')}
              </p>
            </div>
          </>
        )}
      </CardContent>
    </Card>
  )
}
