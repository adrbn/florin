# syntax=docker/dockerfile:1.7

# ============ deps ============
FROM node:22-alpine AS deps
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@10.33.0 --activate
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

# ============ build ============
FROM node:22-alpine AS build
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@10.33.0 --activate
COPY --from=deps /app/node_modules ./node_modules
COPY . .
# Dummy env values so next build can import the validated env module.
# Real values are injected at runtime via docker compose.
ENV DATABASE_URL=postgres://build:build@localhost:5432/build \
    NEXTAUTH_SECRET=build-time-placeholder-secret-32-chars-min \
    NEXTAUTH_URL=http://localhost:3000 \
    APP_BASE_URL=http://localhost:3000 \
    NODE_ENV=production
RUN pnpm build

# ============ runner ============
FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup -S nodejs && adduser -S nextjs -G nodejs

COPY --from=build /app/public ./public
COPY --from=build --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=build --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=build /app/drizzle ./drizzle

USER nextjs
EXPOSE 3000
ENV PORT=3000 \
    HOSTNAME=0.0.0.0

CMD ["node", "server.js"]
