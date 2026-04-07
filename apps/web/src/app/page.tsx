import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

export default function Page() {
  return (
    <main className="min-h-screen p-8 bg-background">
      <Card className="max-w-md mx-auto">
        <CardHeader>
          <CardTitle>Florin 🪙</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <p className="text-muted-foreground">Personal finance, beautifully self-hosted.</p>
          <Button>Let&apos;s go</Button>
        </CardContent>
      </Card>
    </main>
  )
}
