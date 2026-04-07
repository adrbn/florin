.PHONY: help install dev build test lint format up down logs migrate seed import-legacy

help:
	@echo "Florin — make targets:"
	@echo "  install        Install all dependencies"
	@echo "  dev            Run web app in dev mode"
	@echo "  build          Build web app for production"
	@echo "  test           Run all tests"
	@echo "  lint           Lint everything"
	@echo "  format         Format everything"
	@echo "  up             docker compose up -d"
	@echo "  down           docker compose down"
	@echo "  logs           Tail logs from all services"
	@echo "  migrate        Run database migrations"
	@echo "  seed           Seed default categories"
	@echo "  import-legacy  Import legacy XLSX into database"

install:
	cd apps/web && pnpm install

dev:
	cd apps/web && pnpm dev

build:
	cd apps/web && pnpm build

test:
	cd apps/web && pnpm test

lint:
	cd apps/web && pnpm lint

format:
	cd apps/web && pnpm format

up:
	docker compose up -d

down:
	docker compose down

logs:
	docker compose logs -f

migrate:
	cd apps/web && pnpm drizzle-kit migrate

seed:
	cd apps/web && pnpm tsx src/db/seed.ts

import-legacy:
	cd apps/web && pnpm tsx ../../scripts/import-legacy-xlsx.ts $(FILE)
