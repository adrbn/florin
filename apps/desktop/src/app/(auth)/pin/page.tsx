import { redirect } from 'next/navigation'
import { cookies } from 'next/headers'
import { PinGate } from './pin-gate'

export const dynamic = 'force-dynamic'

export default async function PinPage() {
  // If already authenticated, skip the PIN screen
  const cookieStore = await cookies()
  const authed = cookieStore.get('florin-pin-ok')
  if (authed?.value === '1') {
    redirect('/')
  }

  return (
    <div className="flex min-h-dvh flex-col items-center justify-center gap-8 bg-background p-8">
      <div className="text-center">
        <h1 className="text-2xl font-bold tracking-tight text-foreground">Enter PIN</h1>
        <p className="mt-1 text-sm text-muted-foreground">Enter your PIN to unlock Florin.</p>
      </div>
      <PinGate />
    </div>
  )
}
