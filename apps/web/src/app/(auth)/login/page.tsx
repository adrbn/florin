import { Card, CardContent, CardHeader, CardTitle } from '@florin/core/components/ui/card'
import { isAdminConfigured } from '@/server/env'
import { LoginForm } from './login-form'

export default function LoginPage() {
  // Read the admin-config status on the server and hand it to the form so a
  // self-hoster who forgot ADMIN_EMAIL / ADMIN_PASSWORD_HASH gets a clear
  // message instead of an endless "Invalid credentials".
  return (
    <main className="min-h-screen flex items-center justify-center bg-muted/30 p-4">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle className="text-2xl">Sign in to Florin</CardTitle>
        </CardHeader>
        <CardContent>
          <LoginForm adminConfigured={isAdminConfigured} />
        </CardContent>
      </Card>
    </main>
  )
}
