'use client'

import { Tags } from 'lucide-react'
import { useV2T } from '../i18n/context'
import { useMoney } from '../lib/config'
import { seriesVar } from '../lib/format'
import { Amount } from '../primitives/amount'
import { Empty, Pill, Section, Track } from '../primitives/atoms'
import { Row, RowGroup } from '../primitives/row'
import { Screen } from '../shell/screen'

export interface CategoriesGroup {
  id: string
  name: string
  kind: string
  categories: Array<{
    id: string
    name: string
    emoji: string | null
    isFixed: boolean
    /** Absolute spend this month, for the inline bar. */
    monthTotal: number
  }>
}

export function CategoriesScreen({ groups }: { groups: CategoriesGroup[] }) {
  const t = useV2T()
  const m = useMoney()

  const count = groups.reduce((s, g) => s + g.categories.length, 0)

  const hero = (
    <div className="v2-gutter flex flex-col gap-1 pb-1">
      <h2 className="text-[30px] font-semibold leading-tight tracking-[-0.035em]">
        {t('v2.categories.title', 'Categories')}
      </h2>
      <p className="v2-sub">
        {t(
          'v2.categories.count',
          { count, groups: groups.length },
          '{count} categories across {groups} groups',
        )}
      </p>
    </div>
  )

  return (
    <Screen title={t('v2.categories.title', 'Categories')} hero={hero} back="/m">
      {groups.length === 0 && (
        <Empty icon={<Tags className="h-5 w-5" />} title={t('v2.categories.empty', 'No categories')} />
      )}

      {groups.map((g) => {
        const max = Math.max(1, ...g.categories.map((c) => c.monthTotal))
        const total = g.categories.reduce((s, c) => s + c.monthTotal, 0)
        return (
          <Section
            key={g.id}
            title={g.name}
            action={
              total > 0 ? (
                <Amount value={total} decimals={false} tone="muted" className="text-[12px]" />
              ) : undefined
            }
          >
            <div className="v2-gutter">
              <RowGroup>
                {g.categories.map((c) => (
                  <Row
                    key={c.id}
                    leading={
                      <span
                        className="v2-bubble"
                        style={{
                          background: `color-mix(in oklab, ${seriesVar(c.name)} 14%, transparent)`,
                          color: seriesVar(c.name),
                        }}
                      >
                        {c.emoji ?? c.name.slice(0, 1).toUpperCase()}
                      </span>
                    }
                    title={
                      // The badge must never win the width fight: a long
                      // category name has to truncate, not push the pill off.
                      <span className="flex min-w-0 items-center gap-2">
                        <span className="min-w-0 truncate">{c.name}</span>
                        {c.isFixed && (
                          <Pill className="flex-none text-[10px]">
                            {t('v2.categories.fixed', 'Fixed cost')}
                          </Pill>
                        )}
                      </span>
                    }
                    subtitle={
                      c.monthTotal > 0 ? (
                        <Track
                          pct={(c.monthTotal / max) * 100}
                          color={seriesVar(c.name)}
                          className="mt-1 h-[4px] w-24"
                        />
                      ) : undefined
                    }
                    value={
                      c.monthTotal > 0 ? (
                        <Amount value={c.monthTotal} decimals={false} />
                      ) : (
                        <span className="v2-micro">—</span>
                      )
                    }
                  />
                ))}
              </RowGroup>
            </div>
          </Section>
        )
      })}
    </Screen>
  )
}
