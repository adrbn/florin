'use client'

import { useState, useTransition } from 'react'
import { Button } from '../ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'
import { Input } from '../ui/input'
import type {
  ActionResult,
  CreateCategoryInput,
  UpdateCategoryInput,
  CreateGroupInput,
} from '../../types/index'

interface CategoryRow {
  id: string
  name: string
  emoji: string | null
  isFixed: boolean
}

interface GroupRow {
  id: string
  name: string
  kind: 'income' | 'expense'
  color: string | null
  categories: ReadonlyArray<CategoryRow>
}

export interface CategoryActions {
  onCreateCategory: (input: CreateCategoryInput) => Promise<ActionResult<{ id: string }>>
  onUpdateCategory: (input: UpdateCategoryInput) => Promise<ActionResult>
  onDeleteCategory: (id: string) => Promise<ActionResult>
  onCreateCategoryGroup: (input: CreateGroupInput) => Promise<ActionResult<{ id: string }>>
  onUpdateCategoryGroup: (input: CreateGroupInput & { id: string }) => Promise<ActionResult>
  onDeleteCategoryGroup: (id: string) => Promise<ActionResult>
}

interface CategoriesEditorProps {
  groups: ReadonlyArray<GroupRow>
  actions: CategoryActions
}

/**
 * Editable Categories page. Each group is a card with inline create/edit/
 * delete for its categories. A "+ New group" tile at the end opens an inline
 * group creator. Optimistic updates are kept simple — we let server actions
 * revalidate `/categories` and Next.js re-renders the page.
 */
export function CategoriesEditor({ groups, actions }: CategoriesEditorProps) {
  const [showNewGroup, setShowNewGroup] = useState(false)

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-end">
        <Button size="sm" variant="default" onClick={() => setShowNewGroup((v) => !v)}>
          {showNewGroup ? 'Cancel' : '+ New group'}
        </Button>
      </div>

      {showNewGroup && <NewGroupForm onDone={() => setShowNewGroup(false)} actions={actions} />}

      {groups.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center text-muted-foreground">
            No category groups yet. Click "+ New group" above.
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          {groups.map((group) => (
            <GroupCard key={group.id} group={group} actions={actions} />
          ))}
        </div>
      )}
    </div>
  )
}

function GroupCard({ group, actions }: { group: GroupRow; actions: CategoryActions }) {
  const [editing, setEditing] = useState(false)
  const [adding, setAdding] = useState(false)
  const [pending, startTransition] = useTransition()
  const [error, setError] = useState<string | null>(null)

  const onDelete = () => {
    const ok = window.confirm(
      `Delete group "${group.name}"? This will delete all ${group.categories.length} categories inside it. Transactions categorized here will become uncategorized. Continue?`,
    )
    if (!ok) return
    setError(null)
    startTransition(async () => {
      const result = await actions.onDeleteCategoryGroup(group.id)
      if (!result.success) setError(result.error ?? 'Failed')
    })
  }

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        {editing ? (
          <EditGroupForm group={group} onDone={() => setEditing(false)} actions={actions} />
        ) : (
          <>
            <div className="flex items-center gap-2">
              <CardTitle className="text-base">{group.name}</CardTitle>
              <span
                className={`inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-medium uppercase tracking-wide ${
                  group.kind === 'income'
                    ? 'bg-emerald-500/15 text-emerald-700 dark:text-emerald-300'
                    : 'bg-rose-500/15 text-rose-700 dark:text-rose-300'
                }`}
              >
                {group.kind}
              </span>
            </div>
            <div className="flex items-center gap-1">
              <Button size="xs" variant="ghost" onClick={() => setEditing(true)}>
                Edit
              </Button>
              <Button size="xs" variant="ghost" onClick={onDelete} disabled={pending}>
                Delete
              </Button>
            </div>
          </>
        )}
      </CardHeader>
      <CardContent className="space-y-2">
        {error && <p className="text-xs text-destructive">{error}</p>}
        {group.categories.length === 0 ? (
          <p className="text-xs text-muted-foreground">No categories yet.</p>
        ) : (
          <ul className="space-y-1">
            {group.categories.map((category) => (
              <CategoryItem key={category.id} category={category} actions={actions} />
            ))}
          </ul>
        )}
        {adding ? (
          <NewCategoryForm groupId={group.id} onDone={() => setAdding(false)} actions={actions} />
        ) : (
          <Button
            size="xs"
            variant="ghost"
            className="w-full justify-start text-muted-foreground"
            onClick={() => setAdding(true)}
          >
            + Add category
          </Button>
        )}
      </CardContent>
    </Card>
  )
}

function CategoryItem({ category, actions }: { category: CategoryRow; actions: CategoryActions }) {
  const [editing, setEditing] = useState(false)
  const [pending, startTransition] = useTransition()

  const onDelete = () => {
    const ok = window.confirm(
      `Delete "${category.name}"? Transactions categorized here will become uncategorized.`,
    )
    if (!ok) return
    startTransition(async () => {
      await actions.onDeleteCategory(category.id)
    })
  }

  if (editing) {
    return (
      <li>
        <EditCategoryForm category={category} onDone={() => setEditing(false)} actions={actions} />
      </li>
    )
  }

  return (
    <li className="group flex items-center justify-between gap-2 rounded-md px-1.5 py-1 text-sm hover:bg-muted/50">
      <span className="flex items-center gap-2">
        {category.emoji && (
          <span className="text-base" aria-hidden>
            {category.emoji}
          </span>
        )}
        <span className="text-foreground">{category.name}</span>
        {category.isFixed && (
          <span className="rounded-full bg-sky-500/15 px-1.5 py-0.5 text-[9px] font-medium uppercase tracking-wide text-sky-700 dark:text-sky-300">
            fixed
          </span>
        )}
      </span>
      <span className="flex items-center gap-0.5 opacity-0 transition-opacity group-hover:opacity-100">
        <Button size="xs" variant="ghost" onClick={() => setEditing(true)}>
          Edit
        </Button>
        <Button size="xs" variant="ghost" onClick={onDelete} disabled={pending}>
          Delete
        </Button>
      </span>
    </li>
  )
}

function NewCategoryForm({ groupId, onDone, actions }: { groupId: string; onDone: () => void; actions: CategoryActions }) {
  const [pending, startTransition] = useTransition()
  const [name, setName] = useState('')
  const [emoji, setEmoji] = useState('')
  const [isFixed, setIsFixed] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const submit = (e: React.FormEvent) => {
    e.preventDefault()
    if (!name.trim()) return
    setError(null)
    startTransition(async () => {
      const result = await actions.onCreateCategory({
        groupId,
        name: name.trim(),
        emoji: emoji.trim() || null,
        isFixed,
      })
      if (!result.success) {
        setError(result.error ?? 'Failed')
        return
      }
      onDone()
    })
  }

  return (
    <form onSubmit={submit} className="space-y-1.5 rounded-md border border-border bg-muted/30 p-2">
      <div className="flex gap-1.5">
        <Input
          placeholder="Name"
          value={name}
          onChange={(e) => setName(e.target.value)}
          autoFocus
          className="h-7 text-xs"
        />
        <Input
          placeholder="🍕"
          value={emoji}
          onChange={(e) => setEmoji(e.target.value)}
          maxLength={4}
          className="h-7 w-12 text-center text-xs"
        />
      </div>
      <label className="flex items-center gap-1.5 text-[11px] text-muted-foreground">
        <input type="checkbox" checked={isFixed} onChange={(e) => setIsFixed(e.target.checked)} />
        Recurring/fixed expense
      </label>
      {error && <p className="text-[11px] text-destructive">{error}</p>}
      <div className="flex gap-1.5">
        <Button type="submit" size="xs" variant="default" disabled={pending}>
          {pending ? 'Saving…' : 'Add'}
        </Button>
        <Button type="button" size="xs" variant="ghost" onClick={onDone}>
          Cancel
        </Button>
      </div>
    </form>
  )
}

function EditCategoryForm({ category, onDone, actions }: { category: CategoryRow; onDone: () => void; actions: CategoryActions }) {
  const [pending, startTransition] = useTransition()
  const [name, setName] = useState(category.name)
  const [emoji, setEmoji] = useState(category.emoji ?? '')
  const [isFixed, setIsFixed] = useState(category.isFixed)
  const [error, setError] = useState<string | null>(null)

  const submit = (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    startTransition(async () => {
      const result = await actions.onUpdateCategory({
        id: category.id,
        name: name.trim(),
        emoji: emoji.trim() || null,
        isFixed,
      })
      if (!result.success) {
        setError(result.error ?? 'Failed')
        return
      }
      onDone()
    })
  }

  return (
    <form onSubmit={submit} className="space-y-1.5 rounded-md border border-border bg-muted/30 p-2">
      <div className="flex gap-1.5">
        <Input
          value={name}
          onChange={(e) => setName(e.target.value)}
          autoFocus
          className="h-7 text-xs"
        />
        <Input
          value={emoji}
          onChange={(e) => setEmoji(e.target.value)}
          maxLength={4}
          className="h-7 w-12 text-center text-xs"
        />
      </div>
      <label className="flex items-center gap-1.5 text-[11px] text-muted-foreground">
        <input type="checkbox" checked={isFixed} onChange={(e) => setIsFixed(e.target.checked)} />
        Recurring/fixed expense
      </label>
      {error && <p className="text-[11px] text-destructive">{error}</p>}
      <div className="flex gap-1.5">
        <Button type="submit" size="xs" variant="default" disabled={pending}>
          {pending ? 'Saving…' : 'Save'}
        </Button>
        <Button type="button" size="xs" variant="ghost" onClick={onDone}>
          Cancel
        </Button>
      </div>
    </form>
  )
}

function NewGroupForm({ onDone, actions }: { onDone: () => void; actions: CategoryActions }) {
  const [pending, startTransition] = useTransition()
  const [name, setName] = useState('')
  const [kind, setKind] = useState<'income' | 'expense'>('expense')
  const [error, setError] = useState<string | null>(null)

  const submit = (e: React.FormEvent) => {
    e.preventDefault()
    if (!name.trim()) return
    setError(null)
    startTransition(async () => {
      const result = await actions.onCreateCategoryGroup({ name: name.trim(), kind })
      if (!result.success) {
        setError(result.error ?? 'Failed')
        return
      }
      onDone()
    })
  }

  return (
    <Card>
      <CardContent className="pt-4">
        <form onSubmit={submit} className="flex flex-wrap items-end gap-2">
          <div className="flex flex-col gap-1">
            <label className="text-[11px] uppercase tracking-wide text-muted-foreground">
              Group name
            </label>
            <Input
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. Groceries"
              autoFocus
              className="h-8 w-48"
            />
          </div>
          <div className="flex flex-col gap-1">
            <label className="text-[11px] uppercase tracking-wide text-muted-foreground">
              Kind
            </label>
            <select
              value={kind}
              onChange={(e) => setKind(e.target.value as 'income' | 'expense')}
              className="h-8 rounded-md border border-input bg-background px-2 text-sm"
            >
              <option value="expense">Expense</option>
              <option value="income">Income</option>
            </select>
          </div>
          <Button type="submit" size="sm" variant="default" disabled={pending}>
            {pending ? 'Creating…' : 'Create group'}
          </Button>
          {error && <p className="text-xs text-destructive">{error}</p>}
        </form>
      </CardContent>
    </Card>
  )
}

function EditGroupForm({ group, onDone, actions }: { group: GroupRow; onDone: () => void; actions: CategoryActions }) {
  const [pending, startTransition] = useTransition()
  const [name, setName] = useState(group.name)
  const [kind, setKind] = useState<'income' | 'expense'>(group.kind)
  const [error, setError] = useState<string | null>(null)

  const submit = (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    startTransition(async () => {
      const result = await actions.onUpdateCategoryGroup({
        id: group.id,
        name: name.trim(),
        kind,
        color: group.color,
      })
      if (!result.success) {
        setError(result.error ?? 'Failed')
        return
      }
      onDone()
    })
  }

  return (
    <form onSubmit={submit} className="flex flex-1 items-center gap-1.5">
      <Input
        value={name}
        onChange={(e) => setName(e.target.value)}
        autoFocus
        className="h-7 flex-1 text-sm"
      />
      <select
        value={kind}
        onChange={(e) => setKind(e.target.value as 'income' | 'expense')}
        className="h-7 rounded-md border border-input bg-background px-1.5 text-xs"
      >
        <option value="expense">Expense</option>
        <option value="income">Income</option>
      </select>
      <Button type="submit" size="xs" variant="default" disabled={pending}>
        Save
      </Button>
      <Button type="button" size="xs" variant="ghost" onClick={onDone}>
        ✕
      </Button>
      {error && <p className="text-[10px] text-destructive">{error}</p>}
    </form>
  )
}
