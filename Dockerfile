# ---- Build (deps + compile) ----
FROM --platform=$BUILDPLATFORM node:20 AS builder

WORKDIR /calcom

# Build-time args
ARG DATABASE_URL
ARG MAX_OLD_SPACE_SIZE=4096
ARG NEXT_PUBLIC_LICENSE_CONSENT
ARG NEXTAUTH_SECRET=secret
ARG CALENDSO_ENCRYPTION_KEY=secret

# Runtime (passed here for Next.js compile-time)
ARG NEXT_PUBLIC_WEBSITE_TERMS_URL
ARG NEXT_PUBLIC_WEBSITE_PRIVACY_POLICY_URL
ARG NEXT_PUBLIC_API_V2_URL
ARG CALCOM_TELEMETRY_DISABLED
ARG NEXT_PUBLIC_SINGLE_ORG_SLUG
ARG ORGANIZATIONS_ENABLED

ENV NEXT_PUBLIC_WEBAPP_URL=http://NEXT_PUBLIC_WEBAPP_URL_PLACEHOLDER \
    NEXT_PUBLIC_API_V2_URL=$NEXT_PUBLIC_API_V2_URL \
    NEXT_PUBLIC_LICENSE_CONSENT=$NEXT_PUBLIC_LICENSE_CONSENT \
    NEXT_PUBLIC_WEBSITE_TERMS_URL=$NEXT_PUBLIC_WEBSITE_TERMS_URL \
    NEXT_PUBLIC_WEBSITE_PRIVACY_POLICY_URL=$NEXT_PUBLIC_WEBSITE_PRIVACY_POLICY_URL \
    CALCOM_TELEMETRY_DISABLED=$CALCOM_TELEMETRY_DISABLED \
    DATABASE_URL=$DATABASE_URL \
    DATABASE_DIRECT_URL=$DATABASE_URL \
    NEXTAUTH_SECRET=${NEXTAUTH_SECRET} \
    CALENDSO_ENCRYPTION_KEY=${CALENDSO_ENCRYPTION_KEY} \
    NEXT_PUBLIC_SINGLE_ORG_SLUG=$NEXT_PUBLIC_SINGLE_ORG_SLUG \
    ORGANIZATIONS_ENABLED=$ORGANIZATIONS_ENABLED \
    NODE_OPTIONS=--max-old-space-size=${MAX_OLD_SPACE_SIZE} \
    BUILD_STANDALONE=true

# --- source lives at repo root now ---
COPY package.json yarn.lock .yarnrc.yml playwright.config.ts turbo.json i18n.json ./
COPY .yarn ./.yarn
COPY apps/web ./apps/web
COPY apps/api/v2 ./apps/api/v2
COPY packages ./packages
COPY tests ./tests

RUN yarn config set httpTimeout 1200000
# Install Turborepo globally so "turbo" is available in PATH
RUN npm i -g turbo@2.5.5
RUN npx turbo prune --scope=@calcom/web --scope=@calcom/trpc --docker
RUN yarn install

# Build and make embed servable from web/public/embed folder
RUN yarn workspace @calcom/trpc run build
RUN yarn --cwd packages/embeds/embed-core workspace @calcom/embed-core run build
RUN yarn --cwd apps/web workspace @calcom/web run build

# Trim caches
RUN rm -rf node_modules/.cache .yarn/cache apps/web/.next/cache


# ---- Pack (assembly for runtime) ----
FROM node:20-slim AS builder-two

WORKDIR /calcom
ARG NEXT_PUBLIC_WEBAPP_URL=http://localhost:3555
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1

# --- source lives at repo root now ---
COPY package.json .yarnrc.yml turbo.json i18n.json ./
COPY .yarn ./.yarn
COPY --from=builder /calcom/yarn.lock ./yarn.lock
COPY --from=builder /calcom/node_modules ./node_modules
COPY --from=builder /calcom/packages ./packages
COPY --from=builder /calcom/apps/web ./apps/web
COPY --from=builder /calcom/packages/prisma/schema.prisma ./prisma/schema.prisma
COPY scripts ./scripts

# Persist value used during this build stage
ENV NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL \
    BUILT_NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL

RUN ./scripts/replace-placeholder.sh http://NEXT_PUBLIC_WEBAPP_URL_PLACEHOLDER ${NEXT_PUBLIC_WEBAPP_URL}


# ---- Runtime ----
FROM node:20-slim AS runner

WORKDIR /calcom
COPY --from=builder-two /calcom ./

ARG NEXT_PUBLIC_WEBAPP_URL=http://localhost:3555
ENV NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL \
    BUILT_NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL \
    NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1

EXPOSE 3555

HEALTHCHECK --interval=30s --timeout=30s --retries=5 \
    CMD curl -fsS http://localhost:3555 || exit 1

CMD ["/bin/sh", "/calcom/scripts/start.sh"]
