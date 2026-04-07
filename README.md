# Florin

> A self-hostable, open-source personal finance dashboard for European households.
>
> **Status:** Phase 1 complete — manual transactions + legacy XLSX import + dashboard. Open Banking and Trade Republic integration coming in Phase 2.

## Features (Phase 1)

- Multi-account tracking (checking, savings, cash, loans, brokerage)
- Manual transaction entry with auto-categorization rules
- YNAB-style category hierarchy (Bills / Needs / Wants / Savings / Income)
- Dashboard with net worth, burn rate, safety gauge, 12-month patrimony chart, category pie, top expenses
- One-shot legacy XLSX importer (compatible with YNAB-style spreadsheets)
- Installable as a PWA on iOS / Android
- Single `docker compose up`
- Single-user-per-instance — your data stays on your hardware
- AGPL-3.0 license

## Roadmap

- **Phase 1** (this release): foundation, manual entry, legacy import, dashboard
- **Phase 2** (next): Enable Banking integration for La Banque Postale (and other PSD2 banks)
- **Phase 3**: Trade Republic via `pytr` (Python sidecar)
- **Phase 4**: Loans with full amortization schedule and divergence detection
- **Phase 5**: Production deployment recipes (Tailscale Serve, Caddy, backups, CI/CD)
- **Phase 6**: Polish — i18n, PWA full offline, advanced filters, observability

## Quick start

### 1. Clone and configure

```bash
git clone https://github.com/<you>/florin
cd florin
cp .env.example .env
```

### 2. Generate secrets

```bash
# A strong DB password
openssl rand -base64 32
# A NextAuth secret (≥32 chars)
openssl rand -base64 32
```

Edit `.env`:

```bash
DB_PASSWORD=<paste-1>
NEXTAUTH_SECRET=<paste-2>
ADMIN_EMAIL=you@example.com
```

### 3. Generate your password hash

```bash
cd apps/web
pnpm install
pnpm tsx scripts/hash-password.ts "your-strong-password"
```

Copy the bcrypt hash into `.env`:

```bash
ADMIN_PASSWORD_HASH=$2b$12$...
```

### 4. Start the stack

```bash
cd ..  # back to florin/
docker compose up -d
```

Wait ~30 seconds for the web container to be healthy.

> The Postgres container is mapped to host port **5433** (not 5432) to avoid conflict with any system Postgres. The internal `DATABASE_URL` used by the web container still points at port 5432 on the compose network, so nothing leaks outside.

### 5. Run database migrations & seed default categories

```bash
cd apps/web
pnpm drizzle-kit migrate
pnpm tsx src/db/seed.ts
```

### 6. (Optional) Import a legacy YNAB-style XLSX

```bash
node --env-file=../../.env --import tsx ../../scripts/import-legacy-xlsx.ts /path/to/your/finances.xlsx
```

The script is **idempotent** — you can re-run it safely. It uses the YNAB `Cleared` UUID column for deduplication.

### 7. Open the app

Visit `http://localhost:3000`, sign in with your credentials, and explore.

## Repository layout

```
florin/
├── apps/web/              # Next.js 15 + Drizzle + Postgres
├── scripts/               # one-shot scripts (legacy import, etc.)
├── docs/superpowers/      # design specs and implementation plans
├── compose.yaml           # Docker Compose stack (db + web)
└── Makefile               # convenience targets
```

## Development

```bash
make install   # pnpm install in apps/web
make dev       # next dev
make test      # vitest run
make lint      # biome check
make format    # biome format --write
make migrate   # drizzle-kit migrate
make seed      # seed default categories
```

## License

[AGPL-3.0](./LICENSE) — copyleft, ensures any hosted derivative must publish its source.
