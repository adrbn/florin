# syntax=docker/dockerfile:1.7
#
# Multi-stage build for the @florin/web Next.js app. Built from the
# monorepo root so workspace dependencies (@florin/core, @florin/db-pg,
# @florin/db-sqlite) resolve via pnpm workspaces.
#
# Build context: repo root (configured in compose.yaml).

# ============ deps ============
FROM node:22-alpine AS deps
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@10.33.0 --activate

# Copy workspace descriptors first so `pnpm install` is cache-friendly.
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/web/package.json ./apps/web/
COPY apps/desktop/package.json ./apps/desktop/
COPY packages/core/package.json ./packages/core/
COPY packages/db-pg/package.json ./packages/db-pg/
COPY packages/db-sqlite/package.json ./packages/db-sqlite/

RUN pnpm install --frozen-lockfile

# ============ build ============
FROM node:22-alpine AS build
WORKDIR /app
# `git` is needed so scripts/build-info.mjs can capture the commit SHA and
# inline it as NEXT_PUBLIC_BUILD_SHA at build time. ~5MB, cached layer.
RUN apk add --no-cache git
RUN corepack enable && corepack prepare pnpm@10.33.0 --activate
COPY --from=deps /app ./
COPY . .
# Dummy env values so next build can import the validated env module.
# Real values are injected at runtime via docker compose.
ENV DATABASE_URL=postgres://build:build@localhost:5432/build \
    NEXTAUTH_SECRET=build-time-placeholder-secret-32-chars-min \
    NEXTAUTH_URL=http://localhost:3000 \
    APP_BASE_URL=http://localhost:3000 \
    NODE_ENV=production
RUN node scripts/build-info.mjs web
RUN pnpm --filter @florin/web build

# ============ runner ============
FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup -S nodejs && adduser -S nextjs -G nodejs

# Next.js standalone output bundles the workspace packages it traced,
# preserving the monorepo layout (so server.js lives at apps/web/server.js).
COPY --from=build /app/apps/web/public ./apps/web/public
COPY --from=build --chown=nextjs:nodejs /app/apps/web/.next/standalone ./
COPY --from=build --chown=nextjs:nodejs /app/apps/web/.next/static ./apps/web/.next/static
COPY --from=build /app/apps/web/drizzle ./apps/web/drizzle

USER nextjs
EXPOSE 3000
ENV PORT=3000 \
    HOSTNAME=0.0.0.0

CMD ["node", "apps/web/server.js"]
