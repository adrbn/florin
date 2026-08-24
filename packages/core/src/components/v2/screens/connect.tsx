'use client'

import { useMemo, useState, useTransition } from 'react'
import { CircleAlert, Landmark, RefreshCw, Search, ShieldCheck } from 'lucide-react'
import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { useV2T } from '../i18n/context'
import { useV2Config } from '../lib/config'
import { Card, Empty, Pill, Section } from '../primitives/atoms'
import { Row, RowGroup } from '../primitives/row'
import { Screen } from '../shell/screen'
import { V2_BASE } from '../shell/nav'
import { cn } from '../../../lib/utils'

export interface V2Bank {
  name: string
  country: string
  logo: string | null
  maxConsentDays?: number
}

export interface V2Connection {
  id: string
  aspspName: string
  status: string
  validUntil: string
  lastSyncedAt: string | null
  lastSyncError: string | null
}

/**
 * Enable Banking covers one country at a time, and the bank list is fetched
 * server-side per country — so the picker drives a navigation, not local state.
 * Without it the screen silently assumed France, which is fine until you bank
 * anywhere else.
 */
export const CONNECT_COUNTRIES: ReadonlyArray<{ code: string; name: string }> = [
  { code: 'FR', name: 'France' },
  { code: 'BE', name: 'Belgique' },
  { code: 'DE', name: 'Allemagne' },
  { code: 'ES', name: 'Espagne' },
  { code: 'IT', name: 'Italie' },
  { code: 'NL', name: 'Pays-Bas' },
  { code: 'PT', name: 'Portugal' },
  { code: 'LU', name: 'Luxembourg' },
]

export function ConnectScreen({
  configured,
  banks,
  connections,
  country,
  onStart,
  onSync,
  openUrl,
}: {
  configured: boolean
  banks: V2Bank[]
  connections: V2Connection[]
  /** ISO-3166 alpha-2 of the list currently shown. */
  country: string
  onStart: (bank: V2Bank) => Promise<{ success: boolean; url?: string; error?: string }>
  onSync: (connectionId: string) => Promise<unknown>
  /**
   * How to hand the user to the bank's SCA page. The web app navigates the
   * tab; the desktop app must push it to the system browser instead, because
   * the consent page has to run in a real browser the bank recognises.
   */
  openUrl?: (url: string) => void
}) {
  const t = useV2T()
  const { tag } = useV2Config()
  const router = useRouter()
  const pathname = usePathname() ?? `${V2_BASE}/accounts/connect`
  const [query, setQuery] = useState('')
  const [pending, start] = useTransition()
  const [error, setError] = useState<string | null>(null)

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    const list = q ? banks.filter((b) => b.name.toLowerCase().includes(q)) : banks
    // Without a query the full ASPSP list is ~200 rows of identical-looking
    // names; showing everything makes the screen feel like a database dump.
    return q ? list.slice(0, 40) : list.slice(0, 12)
  }, [banks, query])

  const connect = (bank: V2Bank) => {
    setError(null)
    start(async () => {
      const res = await onStart(bank)
      if (!res.success || !res.url) {
        setError(res.error ?? t('v2.common.error', 'Something went wrong'))
        return
      }
      if (openUrl) openUrl(res.url)
      else window.location.assign(res.url)
    })
  }

  const hero = (
    <div className="v2-gutter flex flex-col gap-2 pb-1">
      <h2 className="text-[30px] font-semibold leading-tight tracking-[-0.035em]">
        {t('v2.connect.title', 'Connect a bank')}
      </h2>
      <p className="v2-sub flex items-start gap-2">
        <ShieldCheck aria-hidden className="mt-0.5 h-4 w-4 flex-none text-[var(--v2-pos)]" />
        <span>
          {t(
            'v2.connect.lead',
            'Florin reads your transactions read-only through the European banking API. No payment is ever possible.',
          )}
        </span>
      </p>
    </div>
  )

  return (
    <Screen title={t('v2.connect.title', 'Connect a bank')} hero={hero} back={`${V2_BASE}/accounts`}>
      {connections.length > 0 && (
        <Section title={t('v2.connect.connected', 'Connected banks')}>
          <div className="v2-gutter">
            <RowGroup>
              {connections.map((c) => {
                const expired = new Date(c.validUntil).getTime() < Date.now()
                return (
                  <Row
                    key={c.id}
                    leading={
                      <span className="v2-bubble">
                        <Landmark className="h-4 w-4" />
                      </span>
                    }
                    title={c.aspspName}
                    subtitle={
                      c.lastSyncError
                        ? c.lastSyncError
                        : expired
                          ? t('v2.connect.expired', 'Expired — reconnect')
                          : t(
                              'v2.connect.expires',
                              {
                                date: new Intl.DateTimeFormat(tag, { dateStyle: 'medium' }).format(
                                  new Date(c.validUntil),
                                ),
                              },
                              'Expires on {date}',
                            )
                    }
                    value={
                      <button
                        type="button"
                        aria-label={t('v2.account.sync', 'Sync')}
                        disabled={pending}
                        onClick={() =>
                          start(async () => {
                            await onSync(c.id)
                            router.refresh()
                          })
                        }
                        className="v2-iconbtn h-8 w-8"
                      >
                        <RefreshCw className={cn('h-3.5 w-3.5', pending && 'animate-spin')} />
                      </button>
                    }
                  />
                )
              })}
            </RowGroup>
          </div>
        </Section>
      )}

      {!configured ? (
        <div className="v2-gutter">
          <Card className="flex flex-col gap-3 p-4">
            <span className="flex items-center gap-2">
              <CircleAlert aria-hidden className="h-4 w-4 flex-none text-[var(--v2-warn)]" />
              <span className="v2-title">
                {t('v2.connect.notConfigured', "Bank sync isn't configured yet.")}
              </span>
            </span>
            <p className="v2-sub">
              {t(
                'v2.connect.notConfiguredHint',
                'Open Settings to enter your Enable Banking App ID.',
              )}
            </p>
            <Link href={`${V2_BASE}/settings` as never} className="v2-btn v2-btn-primary w-full">
              {t('v2.connect.openSettings', 'Open settings')}
            </Link>
          </Card>
        </div>
      ) : (
        <Section>
          <div className="v2-gutter flex flex-col gap-3">
            <div className="flex flex-col gap-1.5">
              <span className="v2-eyebrow">{t('v2.connect.country', 'Pays')}</span>
              <select
                value={country}
                onChange={(e) =>
                  router.push(`${pathname}?country=${e.target.value}` as never)
                }
                aria-label={t('v2.connect.country', 'Pays')}
                className="v2-input"
              >
                {CONNECT_COUNTRIES.map((c) => (
                  <option key={c.code} value={c.code}>
                    {c.name}
                  </option>
                ))}
              </select>
            </div>

            <label className="relative block">
              <Search
                aria-hidden
                className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-[var(--v2-text-3)]"
              />
              <input
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                type="search"
                placeholder={t('v2.connect.search', 'Search your bank')}
                aria-label={t('v2.connect.search', 'Search your bank')}
                className="v2-input pl-10"
              />
            </label>

            {error && (
              <p role="alert" className="text-[12.5px] text-[var(--v2-neg)]">
                {error}
              </p>
            )}

            {filtered.length === 0 ? (
              <Empty title={t('v2.connect.noResults', 'No bank found')} />
            ) : (
              <RowGroup>
                {filtered.map((b) => (
                  <Row
                    key={`${b.country}-${b.name}`}
                    leading={
                      <span className="v2-bubble">
                        {b.logo ? (
                          // eslint-disable-next-line @next/next/no-img-element
                          <img src={b.logo} alt="" className="h-full w-full object-contain" />
                        ) : (
                          <Landmark className="h-4 w-4" />
                        )}
                      </span>
                    }
                    title={b.name}
                    subtitle={b.country}
                    value={<Pill tone="accent">{t('v2.connect.action', 'Connecter')}</Pill>}
                    onClick={() => connect(b)}
                  />
                ))}
              </RowGroup>
            )}
          </div>
        </Section>
      )}
    </Screen>
  )
}
