/**
 * Number and date shaping for the v2 mobile UI.
 *
 * The one that matters: `splitAmount`. Trade Republic's headline numbers read
 * expensive because the cents are typographically demoted — "128 404" at full
 * size, ",17 €" small and muted. Doing that needs the integer part, the
 * decimal separator and the fraction as separate strings, which only
 * `Intl.NumberFormat.formatToParts` gives us. Everything else in this file is
 * support for that idea.
 */

export interface AmountParts {
  /** '-' for negatives, '+' when `signed` was requested, '' otherwise. */
  sign: string
  /** Grouped integer digits, e.g. "128 404". */
  integer: string
  /** Locale decimal separator, e.g. ",". Empty when `decimals` is false. */
  decimal: string
  /** Fraction digits, e.g. "17". Empty when `decimals` is false. */
  fraction: string
  /** Currency symbol, e.g. "€". */
  currency: string
  /** True for locales that put the symbol before the number (en-US "$1"). */
  currencyFirst: boolean
}

/**
 * French Intl output uses U+202F between thousands groups, which at 56px is a
 * hairline gap that reads as "128404". Widen it to a regular no-break space —
 * same fix the v1 formatter applies, kept local so v2 owns its own pipeline.
 */
function widen(s: string): string {
  return s.replace(/\u202F/g, '\u00A0')
}

export function splitAmount(
  value: number,
  opts: { locale: string; currency: string; signed?: boolean; decimals?: boolean } = {
    locale: 'fr-FR',
    currency: 'EUR',
  },
): AmountParts {
  const { locale, currency, signed = false, decimals = true } = opts
  const safe = Number.isFinite(value) ? value : 0
  const parts = new Intl.NumberFormat(locale, {
    style: 'currency',
    currency,
    signDisplay: signed ? 'always' : 'auto',
    minimumFractionDigits: decimals ? 2 : 0,
    maximumFractionDigits: decimals ? 2 : 0,
  }).formatToParts(safe)

  const out: AmountParts = {
    sign: '',
    integer: '',
    decimal: '',
    fraction: '',
    currency: '',
    currencyFirst: false,
  }
  let seenNumber = false
  for (const p of parts) {
    switch (p.type) {
      case 'minusSign':
        out.sign = '\u2212' // U+2212, the real minus — a hyphen looks like a bullet at 56px
        break
      case 'plusSign':
        out.sign = '+'
        break
      case 'integer':
      case 'group':
        out.integer += widen(p.value)
        seenNumber = true
        break
      case 'decimal':
        out.decimal = p.value
        break
      case 'fraction':
        out.fraction = p.value
        break
      case 'currency':
        out.currency = p.value
        if (!seenNumber) out.currencyFirst = true
        break
      default:
        break
    }
  }
  return out
}

/** Flat one-line currency string — for rows, tooltips, labels. */
export function money(
  value: number,
  opts: { locale: string; currency: string; signed?: boolean; decimals?: boolean },
): string {
  const p = splitAmount(value, opts)
  const num = `${p.integer}${p.decimal}${p.fraction}`
  return p.currencyFirst
    ? `${p.sign}${p.currency} ${num}`
    : `${p.sign}${num} ${p.currency}`
}

/** Axis / chip form: "128 k €", "1,2 M €". */
export function moneyCompact(
  value: number,
  opts: { locale: string; currency: string },
): string {
  return widen(
    new Intl.NumberFormat(opts.locale, {
      style: 'currency',
      currency: opts.currency,
      notation: 'compact',
      maximumFractionDigits: 1,
    }).format(Number.isFinite(value) ? value : 0),
  )
}

export function percent(value: number | null, locale: string, digits = 1): string {
  if (value === null || !Number.isFinite(value)) return '—'
  return new Intl.NumberFormat(locale, {
    style: 'percent',
    signDisplay: 'exceptZero',
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  }).format(value / 100)
}

// ---------------------------------------------------------------- dates

function atMidnight(d: Date): number {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
}

/** Whole days between two dates, ignoring the time of day. */
export function dayDelta(a: Date, b: Date): number {
  return Math.round((atMidnight(a) - atMidnight(b)) / 86_400_000)
}

/**
 * Local calendar day as `YYYY-MM-DD`.
 *
 * Grouping a transaction list on the ISO string's first ten characters groups
 * by *UTC* day, while the heading beside it is formatted in local time — so a
 * 22:00 UTC transaction lands in a different bucket from a 23:00 one, and the
 * list shows two consecutive groups both titled "Hier". Group and label have to
 * agree on which calendar they are using.
 */
export function isoDay(d: Date): string {
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${d.getFullYear()}-${m}-${day}`
}

/**
 * Day separator label: "Aujourd'hui" / "Hier" / "lun. 18 août" — and the year
 * only once we're outside the current one, which keeps the sticky bars short.
 */
export function dayLabel(
  date: Date,
  locale: string,
  labels: { today: string; yesterday: string },
  now = new Date(),
): string {
  const delta = dayDelta(now, date)
  if (delta === 0) return labels.today
  if (delta === 1) return labels.yesterday
  const sameYear = date.getFullYear() === now.getFullYear()
  return new Intl.DateTimeFormat(locale, {
    weekday: 'short',
    day: 'numeric',
    month: 'long',
    ...(sameYear ? {} : { year: 'numeric' }),
  }).format(date)
}

export function shortDate(date: Date, locale: string): string {
  return new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short' }).format(date)
}

export function monthLabel(iso: string, locale: string, long = false): string {
  // `iso` is a YYYY-MM key from the query layer.
  const [y, m] = iso.split('-').map(Number)
  const d = new Date(y ?? 1970, (m ?? 1) - 1, 1)
  return new Intl.DateTimeFormat(locale, { month: long ? 'long' : 'short' }).format(d)
}

/** "il y a 2 h" / "2 h ago" via Intl.RelativeTimeFormat — no date library. */
export function relativeTime(date: Date, locale: string, now = new Date()): string {
  const rtf = new Intl.RelativeTimeFormat(locale, { numeric: 'auto', style: 'short' })
  const seconds = Math.round((date.getTime() - now.getTime()) / 1000)
  const abs = Math.abs(seconds)
  if (abs < 60) return rtf.format(Math.round(seconds), 'second')
  if (abs < 3600) return rtf.format(Math.round(seconds / 60), 'minute')
  if (abs < 86_400) return rtf.format(Math.round(seconds / 3600), 'hour')
  if (abs < 2_592_000) return rtf.format(Math.round(seconds / 86_400), 'day')
  if (abs < 31_536_000) return rtf.format(Math.round(seconds / 2_592_000), 'month')
  return rtf.format(Math.round(seconds / 31_536_000), 'year')
}

// ---------------------------------------------------------------- identity

/**
 * Turn a raw bank payee into something a human wants to read.
 *
 * PSD2 feeds hand over strings like "ACHAT CB CRF ST MARTIN 17.08.2026 CARTE
 * 4589" — an operation code, the merchant, the capture date and the card
 * number, all shouting in caps. Three passes fix it:
 *   1. drop leading rail/operation words ("ACHAT CB", "PRLV SEPA", "VIR");
 *   2. drop the trailing capture date and card number, which repeat data the
 *      row already shows in its own columns;
 *   3. de-shout — an all-caps list is exhausting to scan, and the sentence
 *      case a neobank uses is the single cheapest legibility win here.
 * The original string is kept whenever cleaning would leave nothing.
 */
const PAYEE_LEAD =
  /^(achat|cb|carte|paiement|paiment|prlv|prelevement|prélèvement|vir|virement|sepa|ach|pos|tpe|retrait|dab|facture|remise\s+de)\s+/i
const PAYEE_TAIL = [
  /\s+\d{2}[./-]\d{2}[./-]\d{2,4}.*$/, // trailing capture date and anything after it
  /\s+carte\s+\d{2,}$/i,
  /\s+n[o°]?\s*\d{4,}$/i,
]

export function cleanPayee(payee: string): string {
  let s = payee.trim().replace(/\s+/g, ' ')
  // Three passes: "CB PAIEMENT CARREFOUR" stacks several rail words.
  for (let i = 0; i < 3; i++) s = s.replace(PAYEE_LEAD, '').trim()
  for (const re of PAYEE_TAIL) s = s.replace(re, '').trim()
  return s || payee.trim()
}

/**
 * De-shout a bank payee, token by token.
 *
 * An all-or-nothing check ("is the whole string uppercase?") fails on the very
 * common "REGULARISATION CARTE BANCAIRE Du 18/08" — one lowercase word and the
 * entire line keeps shouting. Casing each token independently fixes those, and
 * leaves genuinely mixed-case names ("iTunes", "McDonald's") untouched because
 * they are not uppercase to begin with.
 *
 * Acronyms must survive: "SNCF" is not shouting, it is a name. Nothing tells
 * an acronym from a word for certain, so the rule is length plus vowels —
 * three letters or fewer (EDF, SFR, BNP), or up to five with no vowel at all
 * (SNCF). Everything else is a word: IKEA and LIDL genuinely do write
 * themselves Ikea and Lidl.
 */
const VOWELS = /[AEIOUY]/

function isAcronym(word: string): boolean {
  return word.length <= 3 || (word.length <= 5 && !VOWELS.test(word))
}

export function humanizePayee(payee: string): string {
  return cleanPayee(payee)
    .split(' ')
    .map((word) => {
      if (word !== word.toUpperCase()) return word
      if (isAcronym(word)) return word
      return word
        .toLowerCase()
        .replace(/(^|[-'/])(\p{L})/gu, (_, sep: string, ch: string) => sep + ch.toUpperCase())
    })
    .join(' ')
}

export function initials(label: string): string {
  const words = cleanPayee(label)
    .split(/[\s\-_/]+/)
    .filter((w) => /\p{L}|\p{N}/u.test(w))
  if (words.length === 0) return '·'
  if (words.length === 1) return words[0]!.slice(0, 2).toUpperCase()
  return (words[0]![0]! + words[1]![0]!).toUpperCase()
}

/**
 * Stable colour per label, so "Carrefour" is the same hue on every screen and
 * across reloads. FNV-1a — tiny, and better distributed than a char-sum.
 */
export function seriesVar(label: string, slots = 8): string {
  let h = 0x811c9dc5
  for (let i = 0; i < label.length; i++) {
    h ^= label.charCodeAt(i)
    h = Math.imul(h, 0x01000193)
  }
  return `var(--v2-s${(Math.abs(h) % slots) + 1})`
}

export function clamp(n: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, n))
}
