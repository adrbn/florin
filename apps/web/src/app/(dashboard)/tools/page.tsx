import { CompoundCalculator } from '@florin/core/components/tools/compound-calculator'
import { LoanCalculator } from '@florin/core/components/tools/loan-calculator'
import { getServerT } from '@/lib/locale'

/**
 * Tools — calculators that don't depend on user data. Each one is a fully
 * client-side widget; the page itself is server-rendered just to ship the
 * shell + headings.
 */
export default async function ToolsPage() {
  const t = await getServerT()
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">{t('tools.title', 'Tools')}</h1>
        <p className="text-muted-foreground">
          {t('tools.subtitle', "Pure-math helpers — they don't read your accounts.")}
        </p>
      </div>
      <CompoundCalculator />
      <LoanCalculator />
    </div>
  )
}
