'use client'

import { useState } from 'react'
import { getSeedCategories } from '../../../../i18n/seed-categories'
import type { SeedCategoryGroup, SeedCategory } from '../../../../i18n/seed-categories'

interface CategoryPreviewStepProps {
  locale: string
  onConfirm: (groups: SeedCategoryGroup[]) => Promise<void>
}

export function CategoryPreviewStep({ locale, onConfirm }: CategoryPreviewStepProps) {
  const [groups, setGroups] = useState<SeedCategoryGroup[]>(() => getSeedCategories(locale))
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  function renameCategory(groupIdx: number, catIdx: number, newName: string) {
    setGroups((prev) =>
      prev.map((g, gi) =>
        gi !== groupIdx
          ? g
          : {
              ...g,
              categories: g.categories.map((c, ci) =>
                ci !== catIdx ? c : { ...c, name: newName },
              ),
            },
      ),
    )
  }

  function deleteCategory(groupIdx: number, catIdx: number) {
    setGroups((prev) =>
      prev.map((g, gi) =>
        gi !== groupIdx
          ? g
          : { ...g, categories: g.categories.filter((_, ci) => ci !== catIdx) },
      ),
    )
  }

  function addCategory(groupIdx: number) {
    const newCat: SeedCategory = { name: '', emoji: '📌' }
    setGroups((prev) =>
      prev.map((g, gi) =>
        gi !== groupIdx ? g : { ...g, categories: [...g.categories, newCat] },
      ),
    )
  }

  async function handleConfirm() {
    setSaving(true)
    setError(null)
    try {
      await onConfirm(groups)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save categories')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="space-y-6">
      <div className="space-y-1">
        <h2 className="text-xl font-semibold">Default Categories</h2>
        <p className="text-sm text-muted-foreground">
          Here are the categories Florin will create for you. Rename or remove any before
          continuing — you can always edit them later.
        </p>
      </div>

      <div className="max-h-64 space-y-4 overflow-y-auto pr-1">
        {groups.map((group, gi) => (
          <div key={group.name} className="space-y-1.5">
            <div className="flex items-center gap-2">
              <span
                className="h-2.5 w-2.5 flex-shrink-0 rounded-full"
                style={{ backgroundColor: group.color }}
              />
              <span className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                {group.name}
              </span>
              <span className="rounded-full border border-border px-1.5 py-0.5 text-[10px] text-muted-foreground">
                {group.kind}
              </span>
            </div>

            <div className="ml-4 space-y-1">
              {group.categories.map((cat, ci) => (
                <div key={ci} className="flex items-center gap-2">
                  <span className="text-base leading-none">{cat.emoji}</span>
                  <input
                    type="text"
                    value={cat.name}
                    onChange={(e) => renameCategory(gi, ci, e.target.value)}
                    className="flex-1 rounded border border-transparent bg-transparent px-1 py-0.5 text-sm hover:border-border focus:border-ring focus:outline-none focus:ring-1 focus:ring-ring"
                  />
                  <button
                    type="button"
                    onClick={() => deleteCategory(gi, ci)}
                    className="text-muted-foreground transition-colors hover:text-destructive"
                    aria-label={`Remove ${cat.name}`}
                  >
                    ×
                  </button>
                </div>
              ))}
              <button
                type="button"
                onClick={() => addCategory(gi)}
                className="ml-6 text-xs text-primary hover:underline"
              >
                + Add
              </button>
            </div>
          </div>
        ))}
      </div>

      {error && <p className="text-sm text-destructive">{error}</p>}

      <button
        type="button"
        onClick={handleConfirm}
        disabled={saving}
        className="w-full rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90 disabled:opacity-50"
      >
        {saving ? 'Creating categories…' : 'Confirm & Continue'}
      </button>
    </div>
  )
}
