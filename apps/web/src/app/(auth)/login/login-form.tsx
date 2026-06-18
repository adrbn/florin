'use client'

import { useRouter } from 'next/navigation'
import { signIn } from 'next-auth/react'
import { useState } from 'react'
import { Button } from '@florin/core/components/ui/button'
import { Input } from '@florin/core/components/ui/input'
import { Label } from '@florin/core/components/ui/label'
import { useT } from '@florin/core/i18n/context'

interface LoginFormProps {
  /**
   * False when ADMIN_EMAIL / ADMIN_PASSWORD_HASH are not both configured.
   * Surfaces a distinct, actionable message instead of "Invalid credentials".
   */
  adminConfigured: boolean
}

export function LoginForm({ adminConfigured }: LoginFormProps) {
  const t = useT()
  const router = useRouter()
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    if (!adminConfigured) {
      setError(
        t(
          'login.noAdmin',
          'No admin account configured — set ADMIN_EMAIL and ADMIN_PASSWORD_HASH.',
        ),
      )
      return
    }
    setLoading(true)
    setError(null)
    const formData = new FormData(e.currentTarget)
    const result = await signIn('credentials', {
      email: formData.get('email'),
      password: formData.get('password'),
      redirect: false,
    })
    if (result?.error) {
      setError(t('login.invalid', 'Invalid credentials'))
      setLoading(false)
      return
    }
    router.push('/')
    router.refresh()
  }

  return (
    <form onSubmit={onSubmit} className="space-y-4">
      {!adminConfigured && (
        <p className="rounded-md bg-destructive/10 p-2 text-sm text-destructive">
          {t(
            'login.noAdmin',
            'No admin account configured — set ADMIN_EMAIL and ADMIN_PASSWORD_HASH.',
          )}
        </p>
      )}
      <div className="space-y-2">
        <Label htmlFor="email">{t('login.email', 'Email')}</Label>
        <Input id="email" name="email" type="email" required autoComplete="email" />
      </div>
      <div className="space-y-2">
        <Label htmlFor="password">{t('login.password', 'Password')}</Label>
        <Input
          id="password"
          name="password"
          type="password"
          required
          autoComplete="current-password"
        />
      </div>
      {error && <p className="text-sm text-destructive">{error}</p>}
      <Button type="submit" className="w-full" disabled={loading}>
        {loading ? t('login.submitting', 'Signing in…') : t('login.submit', 'Sign in')}
      </Button>
    </form>
  )
}
