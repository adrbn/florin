'use client'

import { useState, useTransition } from 'react'
import { Check, Inbox, Tags } from 'lucide-react'
import { useRouter } from 'next/navigation'
import { useV2T } from '../i18n/context'
import { useV2Config } from '../lib/config'
import { dayLabel } from '../lib/format'
import { Amount } from '../primitives/amount'
import { Empty } from '../primitives/atoms'
import { RowGroup } from '../primitives/row'
import { SwipeRow } from '../primitives/swipe-row'
import { Screen } from '../shell/screen'
import { CategoryPickerSheet } from './parts/category-picker-sheet'
import { TxRow } from './parts/tx-row'
import type { V2Category, V2Tx } from '../types'

/**
 * The review queue. One job — put a category on each row — so the whole screen
 * is built around making that one tap fast: swipe right-to-left for the two
 * actions, or tap the row to open the picker directly.
 */
export function ReviewScreen({
  transactions,
  categories,
  actions,
}: {
  transactions: V2Tx[]
  categories: V2Category[]
  actions: {
    updateTransactionCategory: (id: string, categoryId: string | null) => Promise<unknown>
    approveTransaction: (id: string) => Promise<unknown>
  }
}) {
  const t = useV2T()
  const { tag } = useV2Config()
  const router = useRouter()
  const [picking, setPicking] = useState<V2Tx | null>(null)
  const [, start] = useTransition()

  const approve = (id: string) =>
    start(async () => {
      await actions.approveTransaction(id)
      router.refresh()
    })

  const hero = (
    <div className="v2-gutter flex flex-col gap-1 pb-1">
      <h2 className="text-[30px] font-semibold leading-tight tracking-[-0.035em]">
        {t('v2.review.title', 'To review')}
      </h2>
      {transactions.length > 0 && (
        <p className="v2-sub">
          {t(
            'v2.review.count',
            { count: transactions.length },
            '{count} transactions to categorize',
          )}
        </p>
      )}
    </div>
  )

  return (
    <Screen title={t('v2.review.title', 'To review')} hero={hero} back="/m">
      {transactions.length === 0 ? (
        <Empty
          icon={<Check className="h-5 w-5" />}
          title={t('v2.review.done', 'All caught up')}
          hint={t('v2.review.doneHint', 'No transaction is waiting for a category.')}
        />
      ) : (
        <div className="v2-gutter">
          <RowGroup>
            {transactions.map((tx) => (
              <SwipeRow
                key={tx.id}
                actions={[
                  {
                    key: 'cat',
                    label: t('v2.activity.categorize', 'Categorize'),
                    icon: <Tags className="h-4 w-4" />,
                    background: 'var(--v2-accent)',
                    onSelect: () => setPicking(tx),
                  },
                  {
                    key: 'ok',
                    label: t('v2.activity.markReviewed', 'Reviewed'),
                    icon: <Check className="h-4 w-4" />,
                    background: 'var(--v2-pos)',
                    onSelect: () => approve(tx.id),
                  },
                ]}
              >
                <TxRow
                  tx={tx}
                  secondary={dayLabel(new Date(tx.date), tag, {
                    today: t('v2.common.today', 'Today'),
                    yesterday: t('v2.common.yesterday', 'Yesterday'),
                  })}
                  onClick={() => setPicking(tx)}
                />
              </SwipeRow>
            ))}
          </RowGroup>
        </div>
      )}

      <CategoryPickerSheet
        open={picking !== null}
        onClose={() => setPicking(null)}
        categories={categories}
        currentId={picking?.categoryId ?? null}
        onPick={async (categoryId) => {
          if (!picking) return
          await actions.updateTransactionCategory(picking.id, categoryId)
          // Categorising is the reviewer's decision — clear the flag too, or
          // the row stays in the queue and the count never goes down.
          await actions.approveTransaction(picking.id)
        }}
      />
    </Screen>
  )
}
