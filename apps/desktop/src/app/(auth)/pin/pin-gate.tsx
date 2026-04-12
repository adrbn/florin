'use client'

import { useRouter } from 'next/navigation'
import { PinInput } from '@/components/pin-input'
import { verifyPinAndSetCookie } from './actions'

export function PinGate() {
  const router = useRouter()

  async function handleSubmit(pin: string): Promise<boolean> {
    const ok = await verifyPinAndSetCookie(pin)
    if (ok) {
      router.push('/')
      router.refresh()
    }
    return ok
  }

  return <PinInput onSubmit={handleSubmit} />
}
