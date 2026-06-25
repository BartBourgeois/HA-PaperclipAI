# =============================================================================
# PaperclipAI — Home Assistant add-on image
#
# PaperclipAI publishes no pre-built image, so this Dockerfile clones the
# upstream repo at a pinned tag and reproduces its multi-stage build locally on
# the HA host, then overlays the HA "glue" (run.sh entrypoint, xdg-open shim).
#
# Hardcoded `FROM node:lts-trixie-slim` (HA's BUILD_FROM is intentionally
# ignored — there is no build.yaml). amd64 only.
#
# ⚠️ MAINTENANCE — on every tag bump (PAPERCLIP_REF):
#   1. Diff upstream's Dockerfile at the new tag.
#   2. Re-verify the three `pnpm --filter ... build` lines below.
#   3. Re-verify the server start command in CMD (run.sh) / `server/dist/index.js`.
#   4. Rebuild. The `test -f server/dist/index.js` guard turns a silent upstream
#      layout change into a hard build failure.
# =============================================================================

# ---------- base ----------
FROM node:lts-trixie-slim AS base
ARG PAPERCLIP_REF=v2026.618.0
ENV PNPM_HOME=/pnpm PATH="/pnpm:$PATH"
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates gosu curl gh git wget ripgrep python3 openssh-client jq \
 && rm -rf /var/lib/apt/lists/* && corepack enable
WORKDIR /app
RUN git clone --depth 1 --branch "${PAPERCLIP_REF}" \
      https://github.com/paperclipai/paperclip.git /app

# ---------- deps ----------
FROM base AS deps
RUN pnpm install --frozen-lockfile

# ---------- build ----------
FROM deps AS build
# RE-VERIFY these filters against upstream's Dockerfile on every tag bump.
RUN pnpm --filter @paperclipai/ui build \
 && pnpm --filter @paperclipai/plugin-sdk build \
 && pnpm --filter @paperclipai/server build \
 && test -f server/dist/index.js   # hard-fail if upstream layout drifts

# ---------- production ----------
FROM node:lts-trixie-slim AS production
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates gosu curl gh git wget ripgrep python3 openssh-client jq \
 && rm -rf /var/lib/apt/lists/* && corepack enable \
 && npm install --global --omit=dev \
      @anthropic-ai/claude-code@latest @openai/codex@latest \
      opencode-ai @google/gemini-cli@latest \
 && mkdir -p /paperclip
COPY --from=build /app /app

# Materialise the pinned pnpm (from upstream package.json "packageManager") into a
# shared corepack cache so the runtime `gosu node pnpm paperclipai …` calls in run.sh
# resolve OFFLINE. Without this, the first runtime pnpm call — made as the `node` user
# whose HOME is the fresh, empty /data volume — would try to download pnpm over the
# network and silently fail on an offline host (taking the hostname seeding and
# first-run CEO bootstrap down with it).
ENV COREPACK_HOME=/opt/corepack COREPACK_ENABLE_DOWNLOAD_PROMPT=0
RUN cd /app && pnpm --version && chown -R node:node /opt/corepack

# Baked, static identity only — NEVER bake secrets. Runtime values (HOME,
# PAPERCLIP_HOME, PAPERCLIP_CONFIG, BETTER_AUTH_SECRET, PAPERCLIP_PUBLIC_URL,
# all ANTHROPIC_*/CLAUDE_CODE_*/OPENAI_API_KEY) are set by run.sh.
ENV NODE_ENV=production HOST=0.0.0.0 PORT=3100 SERVE_UI=true \
    PAPERCLIP_INSTANCE_ID=default \
    PAPERCLIP_DEPLOYMENT_MODE=authenticated \
    PAPERCLIP_DEPLOYMENT_EXPOSURE=private \
    OPENCODE_ALLOW_ALL_MODELS=true GEMINI_SANDBOX=false

# HA glue: headless xdg-open shim + our entrypoint. Override upstream's
# docker-entrypoint.sh / node CMD entirely.
COPY xdg-open /usr/local/bin/xdg-open
COPY run.sh /run.sh
RUN chmod a+x /usr/local/bin/xdg-open /run.sh
EXPOSE 3100
ENTRYPOINT []
CMD ["/bin/bash", "/run.sh"]
