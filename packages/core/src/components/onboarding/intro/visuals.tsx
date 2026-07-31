'use client'

/**
 * Slide artwork. Deliberately hand-drawn SVG rather than a chart library: these
 * illustrate an idea at a glance, they are not plotting the user's data (there
 * isn't any yet during onboarding). Each one animates in once, and every
 * animation is gated behind `motion-reduce:animate-none`.
 *
 * Colours come from the app's own tokens so the artwork stays correct in dark
 * mode and never fights the palette.
 */

interface VisualProps {
  /** Re-mount key changes per slide so the draw-on animation replays. */
  active: boolean
}

/** Growth curve — "your money, on one screen". */
export function GrowthVisual({ active }: VisualProps) {
  return (
    <svg
      viewBox="0 0 320 180"
      role="img"
      aria-label=""
      className="h-full w-full"
      preserveAspectRatio="xMidYMid meet"
    >
      <defs>
        <linearGradient id="fl-growth-fill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="var(--primary)" stopOpacity="0.22" />
          <stop offset="100%" stopColor="var(--primary)" stopOpacity="0" />
        </linearGradient>
      </defs>

      {/* baseline grid — three hairlines, no axis furniture */}
      {[40, 90, 140].map((y) => (
        <line
          key={y}
          x1="0"
          y1={y}
          x2="320"
          y2={y}
          stroke="currentColor"
          strokeOpacity="0.08"
          strokeWidth="1"
        />
      ))}

      <path
        d="M0 152 C 40 148, 62 128, 92 132 S 140 106, 168 96 S 214 84, 244 58 S 292 40, 320 26 L320 180 L0 180 Z"
        fill="url(#fl-growth-fill)"
        className={active ? 'opacity-100 transition-opacity duration-1000 delay-500' : 'opacity-0'}
      />
      <path
        d="M0 152 C 40 148, 62 128, 92 132 S 140 106, 168 96 S 214 84, 244 58 S 292 40, 320 26"
        fill="none"
        stroke="var(--primary)"
        strokeWidth="2.5"
        strokeLinecap="round"
        pathLength={1}
        style={{
          strokeDasharray: 1,
          strokeDashoffset: active ? 0 : 1,
          transition: 'stroke-dashoffset 1400ms cubic-bezier(0.22, 1, 0.36, 1) 150ms',
        }}
        className="motion-reduce:![transition:none]"
      />
      {/* the "you are here" dot */}
      <circle
        cx="320"
        cy="26"
        r="4.5"
        fill="var(--primary)"
        className={
          active
            ? 'opacity-100 transition-opacity duration-500 delay-[1400ms] motion-reduce:transition-none'
            : 'opacity-0'
        }
      />
    </svg>
  )
}

/** Category split — "every euro has a job". */
export function BudgetVisual({ active }: VisualProps) {
  const rows = [
    { label: 'Logement', pct: 78, tone: 'var(--primary)' },
    { label: 'Courses', pct: 52, tone: 'var(--primary)' },
    { label: 'Loisirs', pct: 34, tone: 'var(--primary)' },
    { label: 'Épargne', pct: 61, tone: 'var(--primary)' },
  ]
  return (
    <div className="flex h-full w-full flex-col justify-center gap-3.5">
      {rows.map((r, i) => (
        <div key={r.label} className="flex items-center gap-3">
          <span className="w-16 shrink-0 text-[11px] text-muted-foreground sm:w-20">{r.label}</span>
          <span className="h-1.5 flex-1 overflow-hidden rounded-full bg-foreground/10">
            <span
              className="block h-full rounded-full motion-reduce:!transition-none"
              style={{
                background: r.tone,
                opacity: 0.35 + i * 0.18,
                width: active ? `${r.pct}%` : '0%',
                transition: `width 900ms cubic-bezier(0.22, 1, 0.36, 1) ${180 + i * 110}ms`,
              }}
            />
          </span>
        </div>
      ))}
    </div>
  )
}

/** A machine holding its own data — "nothing leaves this computer". */
export function PrivacyVisual({ active }: VisualProps) {
  return (
    <svg
      viewBox="0 0 320 180"
      role="img"
      aria-label=""
      className="h-full w-full"
      preserveAspectRatio="xMidYMid meet"
    >
      {/* the machine */}
      <rect
        x="86"
        y="44"
        width="148"
        height="94"
        rx="10"
        fill="none"
        stroke="currentColor"
        strokeOpacity="0.25"
        strokeWidth="2"
      />
      <line
        x1="120"
        y1="150"
        x2="200"
        y2="150"
        stroke="currentColor"
        strokeOpacity="0.25"
        strokeWidth="2"
        strokeLinecap="round"
      />
      {/* contents stay inside: three bars settling in place */}
      {[
        { x: 108, w: 44, d: 0 },
        { x: 108, w: 82, d: 110 },
        { x: 108, w: 62, d: 220 },
      ].map((b, i) => (
        <rect
          key={i}
          x={b.x}
          y={70 + i * 20}
          width={active ? b.w : 0}
          height="8"
          rx="4"
          fill="var(--primary)"
          opacity={0.75 - i * 0.18}
          style={{ transition: `width 700ms cubic-bezier(0.22, 1, 0.36, 1) ${b.d}ms` }}
          className="motion-reduce:![transition:none]"
        />
      ))}
      {/* the closed loop around it */}
      <circle
        cx="160"
        cy="92"
        r="78"
        fill="none"
        stroke="var(--primary)"
        strokeOpacity="0.35"
        strokeWidth="1.5"
        strokeDasharray="4 7"
        pathLength={1}
        style={{
          strokeDasharray: active ? '4 7' : '0 11',
          transition: 'stroke-dasharray 1200ms cubic-bezier(0.22, 1, 0.36, 1) 250ms',
        }}
        className="motion-reduce:![transition:none]"
      />
    </svg>
  )
}

/** Three numbered beats — "connect your bank, once". */
export function BankVisual({ active }: VisualProps) {
  return (
    <div className="flex h-full w-full flex-col justify-center gap-3">
      {[1, 2, 3].map((n, i) => (
        <div
          key={n}
          className="flex items-center gap-3 motion-reduce:!translate-y-0 motion-reduce:!opacity-100"
          style={{
            opacity: active ? 1 : 0,
            transform: active ? 'translateY(0)' : 'translateY(8px)',
            transition: `opacity 600ms ease-out ${160 + i * 140}ms, transform 600ms cubic-bezier(0.22, 1, 0.36, 1) ${160 + i * 140}ms`,
          }}
        >
          <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full border border-primary/30 text-[11px] font-semibold text-primary">
            {n}
          </span>
          <span className="h-1.5 rounded-full bg-foreground/10" style={{ width: `${58 - i * 12}%` }} />
        </div>
      ))}
    </div>
  )
}
