.PHONY: help install dev build test lint format up down logs migrate seed import-legacy deploy deploy-status

# ---- remote deployment knobs ----
# Override at the command line or via your shell profile:
#   FLORIN_DEPLOY_HOST  ssh target (alias, user@host, or plain host)
#   FLORIN_DEPLOY_PATH  path to the florin repo on the remote
#   FLORIN_DEPLOY_WRAP  optional wrapper for the remote command, useful when
#                      the compose stack lives inside an LXC container, e.g.
#                      "pct exec 100 --"
#   FLORIN_HEALTH_URL   URL to poll after the rebuild (default: localhost)
FLORIN_DEPLOY_HOST ?=
FLORIN_DEPLOY_PATH ?= /opt/florin
FLORIN_DEPLOY_WRAP ?=
FLORIN_HEALTH_URL  ?= http://localhost:3000/api/health

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
	@echo "  deploy         Push main and rebuild on FLORIN_DEPLOY_HOST"
	@echo "  deploy-status  Curl FLORIN_HEALTH_URL to verify the deployment"

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
	cd apps/web && node --env-file=.env --import tsx scripts/import-legacy-xlsx.ts $(FILE)

# ---- deploy: push main then rebuild the remote stack ----
# Idempotent: `git push` is a no-op if the host is already at HEAD, so this
# target is safe to run repeatedly. The rebuild script is piped to the remote
# over ssh stdin (`bash -s`) so there's no nested-quoting hell when
# FLORIN_DEPLOY_WRAP is something like `pct exec 100 --`.
deploy:
	@if [ -z "$(FLORIN_DEPLOY_HOST)" ]; then \
	  echo "FLORIN_DEPLOY_HOST is not set — see README › Updating › Remote one-liner"; \
	  exit 1; \
	fi
	@echo "▶ pushing main to origin..."
	@git push origin main
	@echo "▶ rebuilding Florin on $(FLORIN_DEPLOY_HOST):$(FLORIN_DEPLOY_PATH)"
	@printf '%s\n' \
	  'set -e' \
	  'cd $(FLORIN_DEPLOY_PATH)' \
	  'git fetch --quiet origin main' \
	  'git reset --keep origin/main' \
	  'docker compose up -d --build web' \
	  'docker image prune -f >/dev/null' \
	  | ssh $(FLORIN_DEPLOY_HOST) "$(FLORIN_DEPLOY_WRAP) bash -s"
	@$(MAKE) --no-print-directory deploy-status

deploy-status:
	@echo "▶ health $(FLORIN_HEALTH_URL)"
	@for i in 1 2 3 4 5 6 7 8 9 10; do \
	  out=$$(curl -sk -m 5 $(FLORIN_HEALTH_URL) 2>/dev/null); \
	  if echo "$$out" | grep -q '"status":"ok"'; then \
	    echo "   ok — $$out"; exit 0; \
	  fi; \
	  echo "   waiting ($$i/10)..."; sleep 3; \
	done; \
	echo "   health check did not go green in 30s"; exit 1
