'use client'

import type { ComponentType, SVGProps } from 'react'
import { ChevronRight, Bug, FileText } from 'lucide-react'
import Image from 'next/image'
import { useT } from '@florin/core/i18n/context'
import { BugReport } from '@/components/bug-report'
import pkg from '../../../../package.json'

const REPO_URL = 'https://github.com/adrbn/florin'

function GithubIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden {...props}>
      <path d="M12 .5C5.7.5.5 5.7.5 12c0 5.1 3.3 9.4 7.9 10.9.6.1.8-.2.8-.6v-2c-3.2.7-3.9-1.5-3.9-1.5-.5-1.3-1.3-1.7-1.3-1.7-1.1-.7.1-.7.1-.7 1.2.1 1.8 1.2 1.8 1.2 1 1.8 2.7 1.3 3.4 1 .1-.8.4-1.3.7-1.6-2.6-.3-5.3-1.3-5.3-5.7 0-1.3.5-2.3 1.2-3.1-.1-.3-.5-1.5.1-3.2 0 0 1-.3 3.2 1.2.9-.3 1.9-.4 2.9-.4s2 .1 2.9.4c2.2-1.5 3.2-1.2 3.2-1.2.6 1.7.2 2.9.1 3.2.7.8 1.2 1.8 1.2 3.1 0 4.4-2.7 5.4-5.3 5.7.4.4.8 1.1.8 2.2v3.3c0 .3.2.7.8.6 4.6-1.5 7.9-5.8 7.9-10.9C23.5 5.7 18.3.5 12 .5z" />
    </svg>
  )
}

export default function AboutPage() {
  const t = useT()
  const version = pkg.version

  const links: Array<{ label: string; href: string; icon: ComponentType<SVGProps<SVGSVGElement>> }> = [
    { label: t('about.repository', 'GitHub repository'), href: REPO_URL, icon: GithubIcon },
    { label: t('about.reportIssue', 'Report an issue'), href: `${REPO_URL}/issues/new`, icon: Bug },
    { label: t('about.releaseNotes', 'Release notes'), href: `${REPO_URL}/releases`, icon: FileText },
  ]

  return (
    <div className="mx-auto max-w-lg space-y-8 py-8">
      <div className="space-y-2 text-center">
        <div className="mx-auto h-20 w-20 overflow-hidden rounded-2xl shadow-sm">
          <Image src="/icon.png" alt="Florin" width={160} height={160} priority />
        </div>
        <h1 className="text-2xl font-bold tracking-tight">Florin</h1>
        <p className="text-sm text-muted-foreground">{t('about.tagline', 'Your finances, your machine.')}</p>
      </div>

      <div className="space-y-4 rounded-lg border bg-card p-6">
        <Row label={t('about.version', 'Version')} value={version} />
        <Row label={t('about.developer', 'Developer')} value="Goldian" />
        <Row label={t('about.license', 'License')} value={t('about.licenseValue', 'Commercial')} />
      </div>

      <div className="overflow-hidden rounded-lg border bg-card">
        <h2 className="border-b px-6 py-3 text-sm font-semibold">{t('about.links', 'Links')}</h2>
        <ul className="divide-y">
          {links.map(({ label, href, icon: Icon }) => (
            <li key={href}>
              <a
                href={href}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-3 px-6 py-3 text-sm transition-colors hover:bg-accent hover:text-accent-foreground"
              >
                <Icon className="h-4 w-4 text-muted-foreground" />
                <span className="flex-1">{label}</span>
                <ChevronRight className="h-4 w-4 text-muted-foreground" />
              </a>
            </li>
          ))}
        </ul>
      </div>

      <BugReport version={version} />

      <p className="text-center text-xs text-muted-foreground">
        {t('about.footer', 'Privacy-first personal finance dashboard.')}
        <br />
        {t('about.footerData', 'All data stays on your computer.')}
      </p>
    </div>
  )
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between text-sm">
      <span className="text-muted-foreground">{label}</span>
      <span className="font-medium">{value}</span>
    </div>
  )
}
