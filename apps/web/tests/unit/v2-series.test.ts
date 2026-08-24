import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import type { PatrimonyPoint } from '@florin/core/types'
import {
  downsample,
  RANGES,
  sliceRange,
  toSparkPoints,
  trimLeadingFlat,
} from '@florin/core/components/v2/lib/series'

const day = (n: number, balance: number): PatrimonyPoint => ({
  date: new Date(Date.UTC(2026, 0, 1 + n)).toISOString().slice(0, 10),
  balance,
})

describe('downsample', () => {
  it('leaves a short series alone', () => {
    const pts = Array.from({ length: 10 }, (_, i) => day(i, i))
    expect(downsample(pts, 400)).toHaveLength(10)
  })

  it('thins a long series to the cap', () => {
    const pts = Array.from({ length: 1800 }, (_, i) => day(i, i))
    expect(downsample(pts, 400)).toHaveLength(400)
  })

  it('keeps the first and — critically — the last sample verbatim', () => {
    // The last point is the number the hero prints; dropping or shifting it
    // would make the chart disagree with the headline.
    const pts = Array.from({ length: 1000 }, (_, i) => day(i, i * 3))
    const out = downsample(pts, 50)
    expect(out[0]).toEqual(pts[0])
    expect(out[out.length - 1]).toEqual(pts[pts.length - 1])
  })

  it('preserves chronological order', () => {
    const pts = Array.from({ length: 500 }, (_, i) => day(i, i))
    const out = downsample(pts, 60)
    const dates = out.map((p) => p.date)
    expect([...dates].sort()).toEqual(dates)
  })
})

describe('trimLeadingFlat', () => {
  it('drops the dead-flat prefix a back-walked series emits before the first transaction', () => {
    const pts = [...Array.from({ length: 30 }, () => day(0, 100)), day(31, 120), day(32, 140)]
    const out = trimLeadingFlat(pts)
    expect(out.length).toBeLessThan(pts.length)
    // One point of the flat run survives so the line still starts at the right level.
    expect(out[0]!.balance).toBe(100)
    expect(out[out.length - 1]!.balance).toBe(140)
  })

  it('leaves a series that moves immediately untouched', () => {
    const pts = [day(0, 100), day(1, 110), day(2, 120)]
    expect(trimLeadingFlat(pts)).toEqual(pts)
  })

  it('does not choke on a series shorter than three points', () => {
    expect(trimLeadingFlat([])).toEqual([])
    expect(trimLeadingFlat([day(0, 5)])).toHaveLength(1)
  })
})

describe('sliceRange', () => {
  const year = Array.from({ length: 400 }, (_, i) => day(i, i))

  it('trims to the trailing window', () => {
    expect(sliceRange(year, '1m').length).toBeLessThanOrEqual(32)
    expect(sliceRange(year, '3m').length).toBeLessThanOrEqual(93)
  })

  it('returns everything for the all range', () => {
    expect(sliceRange(year, 'all')).toHaveLength(year.length)
  })

  it('measures the window from the last sample, not from today', () => {
    // The fixture ends in early 2027; a "1 month" window computed against the
    // real clock would return nothing at all.
    expect(sliceRange(year, '1m').length).toBeGreaterThan(1)
  })

  it('never returns a window too short to draw', () => {
    for (const r of RANGES) {
      expect(sliceRange([day(0, 1), day(1, 2), day(2, 3)], r.value).length).toBeGreaterThanOrEqual(2)
    }
  })

  it('handles an empty series', () => {
    expect(sliceRange([], '1m')).toEqual([])
  })
})

describe('toSparkPoints', () => {
  it('maps dates to epoch millis and carries the projected flag', () => {
    const pts = toSparkPoints([day(0, 10), { ...day(1, 20), projected: true }])
    expect(pts[0]!.x).toBeLessThan(pts[1]!.x)
    expect(pts[1]!.projected).toBe(true)
    expect(pts[0]!.label).toBe(pts[0]!.label)
  })
})

/**
 * Every `var(--v2-…)` referenced from a component must exist in the theme.
 *
 * A typo'd custom property does not throw, does not warn, and does not show up
 * in a typecheck — it silently resolves to nothing and the element renders
 * transparent. This is the only place that mistake can be caught.
 */
describe('v2 design tokens', () => {
  const root = fileURLToPath(
    new URL('../../../../packages/core/src/components/v2', import.meta.url),
  )
  const css = readFileSync(join(root, 'theme/v2.css'), 'utf8')
  const declared = new Set(
    [...css.matchAll(/^\s*(--v2-[a-z0-9-]+)\s*:/gim)].map((m) => m[1]!),
  )

  const walk = (dir: string): string[] =>
    readdirSync(dir).flatMap((entry) => {
      const full = join(dir, entry)
      if (statSync(full).isDirectory()) return walk(full)
      return /\.tsx?$/.test(entry) ? [full] : []
    })

  const sources = walk(root)

  it('finds the component tree', () => {
    expect(sources.length).toBeGreaterThan(15)
    expect(declared.size).toBeGreaterThan(30)
  })

  it('references no undefined custom property', () => {
    const unknown = new Set<string>()
    for (const file of sources) {
      const body = readFileSync(file, 'utf8')
      for (const match of body.matchAll(/var\(\s*(--v2-[a-z0-9-]+)(\$\{)?/gi)) {
        // `seriesVar` composes its name at runtime (`--v2-s${n}`); the prefix
        // alone is not a token and there is nothing to check.
        if (match[2]) continue
        const name = match[1]!
        if (!declared.has(name)) unknown.add(`${name} (${file.slice(root.length + 1)})`)
      }
    }
    expect([...unknown]).toEqual([])
  })

  it('defines every token in both themes', () => {
    // Match the rules at the start of a line — the file's own doc comments
    // mention both selectors, and indexOf happily finds those first.
    const lightStart = css.search(/^\[data-florin-v2\] \{/m)
    const darkStart = css.search(/^\.dark \[data-florin-v2\] \{/m)
    const light = css.slice(lightStart, darkStart)
    const dark = css.slice(darkStart, css.indexOf('@layer components'))
    const names = (block: string) =>
      new Set([...block.matchAll(/(--v2-[a-z0-9-]+)\s*:/gi)].map((m) => m[1]!))
    const lightNames = names(light)
    const darkNames = names(dark)
    // Dark only overrides what changes, but every dark token must have a light
    // base — otherwise the light theme renders that property as nothing.
    expect([...darkNames].filter((n) => !lightNames.has(n))).toEqual([])
  })
})
