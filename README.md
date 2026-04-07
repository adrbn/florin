# Florin

> **Status:** under active development — not yet ready for production use.

**Florin** is a self-hostable, open-source personal finance dashboard for European households. It aggregates bank accounts via Open Banking (PSD2), Trade Republic via `pytr`, and manual entries — and gives you a beautiful interface to track your net worth, expenses, and loans.

## Features (target v1.0)

- Daily auto-sync of bank accounts via [Enable Banking](https://enablebanking.com) (free Personal tier)
- Trade Republic portfolio sync via [pytr](https://github.com/pytr-org/pytr)
- YNAB-style categorization with regex auto-rules
- Loan tracking with full amortization schedule and divergence detection
- Net worth, burn rate, and patrimony evolution dashboards
- Single-user-per-instance, runs on your own hardware
- Installable as a PWA on iOS and Android

## Quick start (Phase 1: local data only)

```bash
git clone https://github.com/<your-org>/florin
cd florin
cp .env.example .env
# Edit .env, set DB_PASSWORD and NEXTAUTH_SECRET
docker compose up -d
# Open http://localhost:3000
```

## License

AGPL-3.0. See [LICENSE](./LICENSE).
