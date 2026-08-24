'use client'

import { ChevronLeft, User } from 'lucide-react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useV2T } from '../i18n/context'
import { useScrollChrome } from '../lib/use-scroll'
import { cn } from '../../../lib/utils'
import { useV2Chrome } from './chrome'

export interface ScreenProps {
  /** Shown large above the fold, and again small in the bar once scrolled. */
  title: string
  /** Optional oversized block under the title — hero number, chart, tabs. */
  hero?: React.ReactNode
  /** Header right slot, before the profile avatar. */
  action?: React.ReactNode
  /** Renders a back chevron instead of nothing on the left. */
  back?: string | true
  /** Hide the profile avatar (the settings screen owns the whole surface). */
  hideProfile?: boolean
  children: React.ReactNode
  className?: string
}

/**
 * Screen frame: a sticky header that turns to glass on scroll, the large title
 * that hands its job over to the bar as it leaves, then the content.
 *
 * The title cross-fade is the small thing that makes a web page stop feeling
 * like a web page — you always know what screen you are on without spending a
 * permanent 44px band on saying so.
 */
export function Screen({
  title,
  hero,
  action,
  back,
  hideProfile = false,
  children,
  className,
}: ScreenProps) {
  const { stuck } = useScrollChrome({ stickAt: 44 })
  const { openProfile, reviewCount, chromeless } = useV2Chrome()
  const router = useRouter()
  const t = useV2T()

  return (
    <div className={cn('flex flex-col', className)}>
      <header className="v2-header" data-stuck={stuck || undefined}>
        <div className="v2-gutter flex h-[52px] items-center gap-2">
          {back ? (
            typeof back === 'string' ? (
              <Link
                href={back as never}
                aria-label={t('v2.a11y.back', 'Back')}
                className="v2-iconbtn -ml-1"
              >
                <ChevronLeft className="h-5 w-5" />
              </Link>
            ) : (
              <button
                type="button"
                onClick={() => router.back()}
                aria-label={t('v2.a11y.back', 'Back')}
                className="v2-iconbtn -ml-1"
              >
                <ChevronLeft className="h-5 w-5" />
              </button>
            )
          ) : null}

          <h1 className="v2-header-title min-w-0 flex-1 truncate text-[16px] font-semibold tracking-[-0.02em]">
            {title}
          </h1>

          {action}

          {!hideProfile && !chromeless && (
            <button
              type="button"
              onClick={openProfile}
              aria-label={t('v2.a11y.openProfile', 'Open profile')}
              className="v2-iconbtn relative"
            >
              <User className="h-[17px] w-[17px]" />
              {reviewCount > 0 && (
                <span
                  aria-hidden
                  className="absolute -right-0.5 -top-0.5 h-2.5 w-2.5 rounded-full bg-[var(--v2-neg)] ring-2 ring-[var(--v2-bg)]"
                />
              )}
            </button>
          )}
        </div>
      </header>

      {hero !== undefined ? (
        hero
      ) : (
        <div className="v2-gutter pb-1 pt-1">
          <h2 className="text-[30px] font-semibold leading-tight tracking-[-0.035em]">{title}</h2>
        </div>
      )}

      <div className="flex flex-col gap-6 pt-4">{children}</div>
    </div>
  )
}
