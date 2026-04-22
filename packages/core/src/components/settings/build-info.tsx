/**
 * Tiny "version · sha · date" badge for Settings pages. Reads build
 * provenance from `NEXT_PUBLIC_BUILD_SHA` / `NEXT_PUBLIC_BUILD_DATE`,
 * which `scripts/build-info.mjs` writes into `apps/<app>/.env.production.local`
 * at build time. Dev builds (no script run) see 'dev' and '—'.
 */
interface BuildInfoProps {
  /** Human-readable app version from package.json (e.g. '1.0.0'). */
  version: string
  /** Label for the preceding line, e.g. 'Build' — localized by caller. */
  label: string
}

export function BuildInfo({ version, label }: BuildInfoProps) {
  const sha = process.env.NEXT_PUBLIC_BUILD_SHA ?? 'dev'
  const rawDate = process.env.NEXT_PUBLIC_BUILD_DATE

  let formattedDate = '—'
  if (rawDate) {
    const parsed = new Date(rawDate)
    if (!Number.isNaN(parsed.getTime())) {
      formattedDate = parsed.toLocaleString(undefined, {
        dateStyle: 'short',
        timeStyle: 'short',
      })
    }
  }

  return (
    <p>
      <strong className="text-foreground">{label}</strong>{' '}
      <code className="font-mono tabular-nums">
        {version} · {sha} · {formattedDate}
      </code>
    </p>
  )
}
