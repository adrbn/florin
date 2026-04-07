import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

export default function DashboardPage() {
  return (
    <div className="space-y-6">
      <h1 className="text-3xl font-bold tracking-tight">Dashboard</h1>
      <p className="text-muted-foreground">Welcome to your finances command center.</p>
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
        <Card>
          <CardHeader>
            <CardTitle>Net worth</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-bold">—</p>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
