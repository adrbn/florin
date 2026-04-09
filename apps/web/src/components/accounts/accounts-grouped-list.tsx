'use client'

import {
  closestCenter,
  DndContext,
  type DragEndEvent,
  KeyboardSensor,
  PointerSensor,
  useSensor,
  useSensors,
} from '@dnd-kit/core'
import {
  arrayMove,
  SortableContext,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
} from '@dnd-kit/sortable'
import { CSS } from '@dnd-kit/utilities'
import { ChevronDown, GripVertical } from 'lucide-react'
import { startTransition, useEffect, useState } from 'react'
import { AccountRowLink } from '@/components/accounts/account-row-link'
import { Card } from '@/components/ui/card'
import { formatCurrency } from '@/lib/format/currency'
import { reorderAccounts } from '@/server/actions/accounts'

export interface GroupedAccount {
  id: string
  name: string
  kind: string
  currentBalance: string | number
  displayIcon: string | null
  displayColor: string | null
  isArchived: boolean
}

interface AccountsGroupedListProps {
  accounts: ReadonlyArray<GroupedAccount>
}

const KIND_LABEL: Record<string, string> = {
  checking: 'Cash',
  savings: 'Cash',
  cash: 'Cash',
  loan: 'Loan',
  broker_cash: 'Investing',
  broker_portfolio: 'Investing',
  other: 'Other',
}

const KIND_ORDER: ReadonlyArray<string> = ['Cash', 'Investing', 'Loan', 'Other']

interface GroupBucket {
  label: string
  accounts: GroupedAccount[]
  total: number
}

function bucketize(accounts: ReadonlyArray<GroupedAccount>): GroupBucket[] {
  const map = new Map<string, GroupBucket>()
  for (const a of accounts) {
    const label = KIND_LABEL[a.kind] ?? 'Other'
    const bucket = map.get(label) ?? { label, accounts: [], total: 0 }
    bucket.accounts.push(a)
    bucket.total += Number(a.currentBalance)
    map.set(label, bucket)
  }
  return KIND_ORDER.flatMap((label) => {
    const b = map.get(label)
    return b ? [b] : []
  })
}

/**
 * Grouped, collapsible, drag-reorderable list of accounts. State for
 * collapsed/expanded sections is local. The order is persisted via the
 * reorderAccounts server action — we optimistically reorder in local state
 * first so the drop feels instant, then revalidatePath on the server
 * refreshes the page with the canonical order. Reordering is per-bucket; you
 * can't drag a Cash account into the Loan section (that'd change its kind,
 * which is a separate concern handled by the edit form).
 */
export function AccountsGroupedList({ accounts }: AccountsGroupedListProps) {
  // Mirror the server prop into local state so optimistic reorders feel
  // instant. `accounts` can change on revalidation (new data, archive, etc.)
  // so we re-sync whenever it does.
  const [localAccounts, setLocalAccounts] = useState<GroupedAccount[]>(() => [...accounts])
  useEffect(() => {
    setLocalAccounts([...accounts])
  }, [accounts])

  const buckets = bucketize(localAccounts)
  const [collapsed, setCollapsed] = useState<Record<string, boolean>>({})

  const sensors = useSensors(
    // Activation distance > 0 so clicks through to the row link still work —
    // the drag only starts once the pointer has actually moved.
    useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  )

  const toggle = (label: string) => {
    setCollapsed((prev) => ({ ...prev, [label]: !prev[label] }))
  }

  const handleDragEnd = (bucket: GroupBucket) => (event: DragEndEvent) => {
    const { active, over } = event
    if (!over || active.id === over.id) return
    const oldIndex = bucket.accounts.findIndex((a) => a.id === active.id)
    const newIndex = bucket.accounts.findIndex((a) => a.id === over.id)
    if (oldIndex < 0 || newIndex < 0) return
    const reordered = arrayMove(bucket.accounts, oldIndex, newIndex)

    // Rebuild the flat list preserving every other bucket and swapping the
    // affected one. This keeps `localAccounts` coherent so bucketize keeps
    // producing stable groups on the next render.
    const affectedIds = new Set(bucket.accounts.map((a) => a.id))
    const byId = new Map(localAccounts.map((a) => [a.id, a]))
    const next: GroupedAccount[] = []
    let bucketCursor = 0
    for (const account of localAccounts) {
      if (affectedIds.has(account.id)) {
        const replacement = reordered[bucketCursor]
        bucketCursor++
        if (replacement) {
          const real = byId.get(replacement.id)
          if (real) next.push(real)
        }
      } else {
        next.push(account)
      }
    }
    setLocalAccounts(next)

    // Persist just the affected bucket — the server only needs the ids that
    // actually moved to assign stable display_order values.
    startTransition(async () => {
      await reorderAccounts({ orderedIds: reordered.map((a) => a.id) })
    })
  }

  if (accounts.length === 0) {
    return <Card className="py-12 text-center text-sm text-muted-foreground">No accounts yet.</Card>
  }

  return (
    <div className="space-y-3">
      {buckets.map((bucket) => {
        const isCollapsed = collapsed[bucket.label] === true
        const isNegative = bucket.total < 0
        return (
          <section key={bucket.label} className="space-y-1.5">
            <button
              type="button"
              onClick={() => toggle(bucket.label)}
              className="flex w-full items-center gap-2 px-1 text-left"
            >
              <ChevronDown
                className={`h-3.5 w-3.5 text-muted-foreground transition-transform ${
                  isCollapsed ? '-rotate-90' : ''
                }`}
              />
              <span className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">
                {bucket.label}
              </span>
              <span
                className={`ml-auto text-sm font-semibold ${
                  isNegative ? 'text-destructive' : 'text-foreground'
                }`}
              >
                {formatCurrency(bucket.total)}
              </span>
            </button>
            {!isCollapsed && (
              <Card className="divide-y divide-border/60 overflow-hidden p-0">
                <DndContext
                  sensors={sensors}
                  collisionDetection={closestCenter}
                  onDragEnd={handleDragEnd(bucket)}
                >
                  <SortableContext
                    items={bucket.accounts.map((a) => a.id)}
                    strategy={verticalListSortingStrategy}
                  >
                    {bucket.accounts.map((a) => (
                      <SortableAccountRow
                        key={a.id}
                        id={a.id}
                        name={a.name}
                        balance={a.currentBalance}
                        icon={a.displayIcon}
                        color={a.displayColor}
                        isArchived={a.isArchived}
                      />
                    ))}
                  </SortableContext>
                </DndContext>
              </Card>
            )}
          </section>
        )
      })}
    </div>
  )
}

interface SortableAccountRowProps {
  id: string
  name: string
  balance: string | number
  icon: string | null
  color: string | null
  isArchived: boolean
}

/**
 * Wraps a single AccountRowLink with dnd-kit sortable behavior. The drag
 * listeners attach to the GripVertical handle on the left — clicks on the
 * rest of the row fall through to the Link so tapping an account still
 * navigates to its detail page.
 */
function SortableAccountRow({ id, name, balance, icon, color, isArchived }: SortableAccountRowProps) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id,
  })
  const style: React.CSSProperties = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.7 : undefined,
    zIndex: isDragging ? 10 : undefined,
    position: 'relative',
  }

  return (
    <div ref={setNodeRef} style={style} className="flex items-stretch bg-background">
      <button
        type="button"
        aria-label={`Reorder ${name}`}
        {...attributes}
        {...listeners}
        className="flex shrink-0 cursor-grab items-center px-2 text-muted-foreground/60 hover:text-foreground active:cursor-grabbing"
      >
        <GripVertical className="h-3.5 w-3.5" />
      </button>
      <div className="min-w-0 flex-1">
        <AccountRowLink
          id={id}
          name={name}
          balance={balance}
          icon={icon}
          color={color}
          isArchived={isArchived}
        />
      </div>
    </div>
  )
}
