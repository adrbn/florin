'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { Plus } from 'lucide-react'
import { Input } from '@florin/core/components/ui/input'
import { Label } from '@florin/core/components/ui/label'
import { Button } from '@florin/core/components/ui/button'

interface AccountOption {
  id: string
  name: string
}

interface CategoryOption {
  id: string
  name: string
  emoji: string | null
  groupName: string
}

interface QuickAddFabProps {
  accounts: ReadonlyArray<AccountOption>
  categories: ReadonlyArray<CategoryOption>
  onAddTransaction: (input: {
    accountId: string
    occurredAt: Date
    amount: number
    payee: string
    memo?: string | null
    categoryId?: string | null
  }) => Promise<{ success: boolean; error?: string }>
}

export function QuickAddFab({ accounts, categories, onAddTransaction }: QuickAddFabProps) {
  const router = useRouter()
  const [open, setOpen] = useState(false)
  const [pending, startTransition] = useTransition()
  const [error, setError] = useState<string | null>(null)

  const today = new Date().toISOString().slice(0, 10)

  const onSubmit = (formData: FormData) => {
    setError(null)
    const input = {
      accountId: String(formData.get('accountId') ?? ''),
      occurredAt: new Date(String(formData.get('occurredAt') ?? today)),
      amount: Number(formData.get('amount') ?? 0),
      payee: String(formData.get('payee') ?? ''),
      memo: String(formData.get('memo') ?? '') || null,
      categoryId: String(formData.get('categoryId') ?? '') || null,
    }

    startTransition(async () => {
      const result = await onAddTransaction(input)
      if (!result.success) {
        setError(result.error ?? 'Unknown error')
        return
      }
      setOpen(false)
      router.refresh()
    })
  }

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="fixed bottom-6 right-6 z-40 flex h-12 w-12 items-center justify-center rounded-full bg-emerald-600 text-white shadow-lg transition-transform hover:scale-105 hover:bg-emerald-500 active:scale-95"
        title="Add transaction"
      >
        <Plus className="h-6 w-6" />
      </button>

      {open && (
        <div
          className="fixed inset-0 z-50 flex items-start justify-center pt-[15vh]"
          onClick={() => setOpen(false)}
        >
          <div className="fixed inset-0 bg-black/50 backdrop-blur-sm" />
          <div
            className="relative w-full max-w-md overflow-hidden rounded-xl border border-border bg-popover p-6 shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 className="mb-1 text-lg font-semibold">Quick add transaction</h2>
            <p className="mb-4 text-xs text-muted-foreground">
              Negative amount = expense, positive = income.
            </p>

            <form action={onSubmit} className="space-y-3">
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-1">
                  <Label htmlFor="fab-account" className="text-xs">Account</Label>
                  <select
                    id="fab-account"
                    name="accountId"
                    required
                    defaultValue={accounts[0]?.id ?? ''}
                    className="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
                  >
                    {accounts.map((a) => (
                      <option key={a.id} value={a.id}>{a.name}</option>
                    ))}
                  </select>
                </div>
                <div className="space-y-1">
                  <Label htmlFor="fab-date" className="text-xs">Date</Label>
                  <Input id="fab-date" name="occurredAt" type="date" defaultValue={today} required />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-1">
                  <Label htmlFor="fab-payee" className="text-xs">Payee</Label>
                  <Input id="fab-payee" name="payee" required maxLength={200} placeholder="Grocery store" autoFocus />
                </div>
                <div className="space-y-1">
                  <Label htmlFor="fab-amount" className="text-xs">Amount</Label>
                  <Input id="fab-amount" name="amount" type="number" step="0.01" placeholder="-12.34" required />
                </div>
              </div>

              <div className="space-y-1">
                <Label htmlFor="fab-category" className="text-xs">Category</Label>
                <select
                  id="fab-category"
                  name="categoryId"
                  defaultValue=""
                  className="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
                >
                  <option value="">— Auto —</option>
                  {categories.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.emoji ? `${c.emoji} ` : ''}{c.groupName} / {c.name}
                    </option>
                  ))}
                </select>
              </div>

              <div className="space-y-1">
                <Label htmlFor="fab-memo" className="text-xs">Memo (optional)</Label>
                <Input id="fab-memo" name="memo" maxLength={500} />
              </div>

              {error && <p className="text-sm text-destructive">{error}</p>}

              <div className="flex gap-2 pt-1">
                <Button type="submit" disabled={pending} className="flex-1 bg-emerald-600 hover:bg-emerald-500">
                  {pending ? 'Saving…' : 'Save'}
                </Button>
                <Button type="button" variant="outline" onClick={() => setOpen(false)}>
                  Cancel
                </Button>
              </div>
            </form>
          </div>
        </div>
      )}
    </>
  )
}
