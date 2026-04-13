'use client'

import { useRouter } from 'next/navigation'
import { PinInput } from '@/components/pin-input'
import { verifyPinAndSetCookie } from './actions'

export function PinGate() {
  const router = useRouter()

  async function handleSubmit(pin: string): Promise<boolean> {
    const ok = await verifyPinAndSetCookie(pin)
    if (ok) {
      // Hard navigation so the middleware sees the new cookie immediately
      window.location.href = '/'
    }
    return ok
  }

  return <PinInput onSubmit={handleSubmit} />
}
