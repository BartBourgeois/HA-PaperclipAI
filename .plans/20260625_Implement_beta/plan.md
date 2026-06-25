# HA-PaperclipAI — Initial Implementation Plan

## Context

The repo is in its documentation/init phase: only `README.md`, `CLAUDE.md`, and
`context.md` exist. The goal of this session is to **scaffold the actual add-on** so
it can be installed on a Home Assistant host and build PaperclipAI from upstream
source. We are porting the working warp10 Docker setup (documented in `context.md`)
into a single-addon HA repository, following the `HA-LiteLLM` layout.

PaperclipAI ships **no pre-built image**, so the add-on `Dockerfile` clones the
upstream repo at a pinned tag and reproduces its multi-stage build locally on the HA
host, then overlays the HA "glue" (options → env, persistence, hostname allowlist,
`xdg-open` shim, first-run bootstrap). The end result: a user adds the repo, installs
the add-on, sets `better_auth_secret`, and reaches the PaperclipAI web UI on `:3100`.

### Decisions locked this session
- **/workspaces mount → `share:rw`** (agent git checkouts land in HA's `/share`, so
  repos can also be dropped in via Samba/SSH).
- **Pinned tag → `v2026.618.0`** (clone `--branch v2026.618.0`, never `master`).
- **Scope → full scaffold + docs**: `config.yaml`, `Dockerfile`, `run.sh`,
  `repository.yaml`, `xdg-open`, `DOCS.md`, `translations/en.yaml`, placeholder
  `icon.png`/`logo.png`.
- **No `image:` field and no `build.yaml`** → HA builds the Dockerfile locally; the
  Dockerfile hardcodes `FROM node:lts-trixie-slim` (HA-LiteLLM pattern — `BUILD_FROM`
  is simply ignored).
- **Run server as `node` via `gosu`** (the upstream entrypoint does this; embedded
  PostgreSQL refuses to run as root). `chown` the persistent dir to `node` first.

---

## File tree to create

```
HA-PaperclipAI/
├── repository.yaml                 # NEW — repo manifest
├── README.md                       # exists (already user-facing & accurate)
├── CLAUDE.md / context.md          # exist, keep
└── paperclipai/                    # NEW add-on folder
    ├── config.yaml                 # manifest — NO image:, NO build.yaml
    ├── Dockerfile                  # clone@tag + multi-stage build + HA glue
    ├── run.sh                      # options.json → env, persistence, hostnames, exec
    ├── xdg-open                    # static stub: #!/bin/sh / exit 0
    ├── DOCS.md                     # in-UI add-on docs
    ├── icon.png / logo.png         # placeholder branding
    └── translations/en.yaml        # option labels for the config UI
```

---

## 1. `repository.yaml` (root)

Mirror `HA-LiteLLM/repository.yaml`:

```yaml
name: PaperclipAI Home Assistant Add-on Repository
url: https://github.com/BartBourgeois/HA-PaperclipAI
maintainer: Bart Bourgeois <bbourgeois@telenet.be>
```

---

## 2. `paperclipai/Dockerfile`

Self-contained multi-stage build. Hardcoded `FROM node:lts-trixie-slim`; clone at the
pinned tag via `ARG PAPERCLIP_REF`; keep upstream's 4 stages to keep the final image
lean; **override** upstream's `ENTRYPOINT`/`CMD` with our `run.sh`; bake the
`xdg-open` shim. Install AI CLIs exactly as upstream (`npm install --global
--omit=dev`).

ENV split:
- **Baked (static identity):** `NODE_ENV`, `HOST`, `PORT`, `SERVE_UI`,
  `PAPERCLIP_INSTANCE_ID`, `PAPERCLIP_DEPLOYMENT_MODE=authenticated`,
  `PAPERCLIP_DEPLOYMENT_EXPOSURE=private`, `OPENCODE_ALLOW_ALL_MODELS`,
  `GEMINI_SANDBOX=false`.
- **Set at runtime in run.sh:** `HOME`, `PAPERCLIP_HOME`, `PAPERCLIP_CONFIG`,
  `BETTER_AUTH_SECRET`, `PAPERCLIP_PUBLIC_URL`, all `ANTHROPIC_*` / `CLAUDE_CODE_*` /
  `OPENAI_API_KEY`. **Never bake secrets.**

```dockerfile
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
ENV NODE_ENV=production HOST=0.0.0.0 PORT=3100 SERVE_UI=true \
    PAPERCLIP_INSTANCE_ID=default \
    PAPERCLIP_DEPLOYMENT_MODE=authenticated \
    PAPERCLIP_DEPLOYMENT_EXPOSURE=private \
    OPENCODE_ALLOW_ALL_MODELS=true GEMINI_SANDBOX=false
COPY xdg-open /usr/local/bin/xdg-open
COPY run.sh /run.sh
RUN chmod a+x /usr/local/bin/xdg-open /run.sh
EXPOSE 3100
ENTRYPOINT []
CMD ["/bin/bash", "/run.sh"]
```

> The three `pnpm --filter ... build` lines and the server start command are the parts
> that drift between releases. On each tag bump: diff upstream's `Dockerfile`, update
> the filters + CMD, rebuild. The `test -f server/dist/index.js` guard converts a
> silent layout change into a hard failure.

---

## 3. `paperclipai/config.yaml`

No `image:` (forces local build). `/data` is always persistent → no `map:` entry is
needed for core state; only declare `/workspaces`. Postgres `:54329` is never listed.

```yaml
name: "PaperclipAI"
version: "0.1.0"
slug: "paperclipai"
description: "Self-hosted AI project-management board for AI coding agents (builds from source)"
url: "https://github.com/BartBourgeois/HA-PaperclipAI"
arch:
  - amd64
init: false
startup: "application"
boot: "auto"
ports:
  3100/tcp: 3100
ports_description:
  3100/tcp: "PaperclipAI web UI"
map:
  - type: share
    read_only: false
    path: /workspaces
options:
  better_auth_secret: ""
  public_url: "http://homeassistant.local:3100"
  allowed_hostnames: ["homeassistant.local", "localhost"]
  anthropic_base_url: ""
  anthropic_auth_token: ""
  anthropic_api_key: ""
  anthropic_model: ""
  anthropic_small_fast_model: ""
  anthropic_default_haiku_model: ""
  anthropic_default_sonnet_model: ""
  anthropic_default_opus_model: ""
  claude_code_subagent_model: ""
  claude_code_effort: ""
  claude_code_experimental_agent_teams: ""
  claudecode: ""
  disable_prompt_caching: ""
  claude_code_disable_thinking: ""
  claude_code_disable_adaptive_thinking: ""
  claude_code_use_bedrock: ""
  claude_code_use_vertex: ""
  openai_api_key: ""
  opencode_allow_all_models: true
schema:
  better_auth_secret: "str"
  public_url: "str?"
  allowed_hostnames: ["str"]
  anthropic_base_url: "str?"
  anthropic_auth_token: "str?"
  anthropic_api_key: "str?"
  anthropic_model: "str?"
  anthropic_small_fast_model: "str?"
  anthropic_default_haiku_model: "str?"
  anthropic_default_sonnet_model: "str?"
  anthropic_default_opus_model: "str?"
  claude_code_subagent_model: "str?"
  claude_code_effort: "str?"
  claude_code_experimental_agent_teams: "str?"
  claudecode: "str?"
  disable_prompt_caching: "str?"
  claude_code_disable_thinking: "str?"
  claude_code_disable_adaptive_thinking: "str?"
  claude_code_use_bedrock: "str?"
  claude_code_use_vertex: "str?"
  openai_api_key: "str?"
  opencode_allow_all_models: "bool?"
```

Schema notes: Claude Code flags stay `str?` (upstream consumes string values like
`"1"`/`"0"`/`"high"`, several are tri-state — avoid HA's `bool`→`true/false`
mismatch). `better_auth_secret` is `str`, but HA accepts empty for `str`, so `run.sh`
hard-validates non-empty.

---

## 4. `paperclipai/run.sh`

Parser: **inline `python3`** (HA-LiteLLM pattern — `python3` is in the image, handles
the `allowed_hostnames` list and empty-string defaults cleanly). Plain bash, no
s6/bashio. Responsibilities in order:

1. `set -eo pipefail`; `CONFIG_PATH=/data/options.json`; `PAPERCLIP_DATA=/data/paperclip`.
2. **Persistence/HOME reconciliation (recommended approach):** `mkdir -p` the data
   dir, `chown -R node:node` it, and **override the baked `/paperclip` env vars** to
   point into `/data/paperclip` — `HOME`, `PAPERCLIP_HOME`, and
   `PAPERCLIP_CONFIG=$PAPERCLIP_DATA/instances/default/config.json`. These three are
   the only baked paths referencing `/paperclip`; nothing then writes to the image's
   ephemeral `/paperclip`. (Fallback only if a hardcoded literal `/paperclip` path
   surfaces in testing: also `rm -rf /paperclip && ln -s /data/paperclip /paperclip`.)
3. **Validate** `better_auth_secret`; if empty, log a clear FATAL line
   (`openssl rand -hex 32`) and `exit 1`.
4. Export option-driven env under canonical names **only when non-empty** (so empties
   never clobber baked ENV) via a small `exp <option> <ENV>` helper.
5. Re-assert the `xdg-open` shim if missing.
6. **Background task** (so it can wait for the server): poll `http://localhost:3100`,
   then `pnpm paperclipai allowed-hostname <h>` for each configured host + auto-detected
   LAN IP + `homeassistant.local` + `localhost` (tolerate failures); and on first run
   (no `$PAPERCLIP_DATA/.ha_bootstrapped` marker) run `pnpm paperclipai auth
   bootstrap-ceo` and echo the invite URL in a prominent banner, then `touch` the marker.
7. `cd /app` and `exec gosu node node --import ./server/node_modules/tsx/dist/loader.mjs server/dist/index.js`.

Core skeleton:

```bash
#!/usr/bin/env bash
set -eo pipefail
CONFIG_PATH="/data/options.json"
PAPERCLIP_DATA="/data/paperclip"
opt() { python3 -c "import json,sys;print(json.load(open('${CONFIG_PATH}')).get(sys.argv[1],''))" "$1"; }

mkdir -p "${PAPERCLIP_DATA}"
chown -R node:node "${PAPERCLIP_DATA}"
export HOME="${PAPERCLIP_DATA}"
export PAPERCLIP_HOME="${PAPERCLIP_DATA}"
export PAPERCLIP_CONFIG="${PAPERCLIP_DATA}/instances/default/config.json"

BETTER_AUTH_SECRET="$(opt better_auth_secret)"
if [ -z "${BETTER_AUTH_SECRET}" ]; then
  echo "[FATAL] 'better_auth_secret' is required. Generate one with: openssl rand -hex 32" >&2
  exit 1
fi
export BETTER_AUTH_SECRET

exp() { local v; v="$(opt "$1")"; [ -n "$v" ] && export "$2"="$v" || true; }
exp public_url                            PAPERCLIP_PUBLIC_URL
exp anthropic_base_url                    ANTHROPIC_BASE_URL
exp anthropic_auth_token                  ANTHROPIC_AUTH_TOKEN
exp anthropic_api_key                     ANTHROPIC_API_KEY
exp anthropic_model                       ANTHROPIC_MODEL
exp anthropic_small_fast_model            ANTHROPIC_SMALL_FAST_MODEL
exp anthropic_default_haiku_model         ANTHROPIC_DEFAULT_HAIKU_MODEL
exp anthropic_default_sonnet_model        ANTHROPIC_DEFAULT_SONNET_MODEL
exp anthropic_default_opus_model          ANTHROPIC_DEFAULT_OPUS_MODEL
exp claude_code_subagent_model            CLAUDE_CODE_SUBAGENT_MODEL
exp claude_code_effort                    CLAUDE_CODE_EFFORT
exp claude_code_experimental_agent_teams  CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
exp claudecode                            CLAUDECODE
exp disable_prompt_caching                DISABLE_PROMPT_CACHING
exp claude_code_disable_thinking          CLAUDE_CODE_DISABLE_THINKING
exp claude_code_disable_adaptive_thinking CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING
exp claude_code_use_bedrock               CLAUDE_CODE_USE_BEDROCK
exp claude_code_use_vertex                CLAUDE_CODE_USE_VERTEX
exp openai_api_key                        OPENAI_API_KEY
OAAM="$(opt opencode_allow_all_models)"; [ -n "$OAAM" ] && export OPENCODE_ALLOW_ALL_MODELS="$OAAM"

[ -x /usr/local/bin/xdg-open ] || { printf '#!/bin/sh\nexit 0\n' > /usr/local/bin/xdg-open; chmod a+x /usr/local/bin/xdg-open; }

cd /app
(
  for i in $(seq 1 60); do curl -sf "http://localhost:3100" >/dev/null 2>&1 && break; sleep 2; done
  LANIP="$(hostname -i 2>/dev/null | awk '{print $1}')"
  HOSTS="$(python3 -c "import json;print(' '.join(json.load(open('${CONFIG_PATH}')).get('allowed_hostnames',[])))")"
  for h in $HOSTS localhost homeassistant.local "$LANIP"; do
    [ -n "$h" ] && gosu node pnpm paperclipai allowed-hostname "$h" >/dev/null 2>&1 || true
  done
  if [ ! -f "${PAPERCLIP_DATA}/.ha_bootstrapped" ]; then
    echo "=================== PAPERCLIPAI FIRST-RUN ==================="
    gosu node pnpm paperclipai auth bootstrap-ceo || true
    echo "Open the invite URL above to create your admin account."
    echo "============================================================"
    touch "${PAPERCLIP_DATA}/.ha_bootstrapped"
  fi
) &

exec gosu node node --import ./server/node_modules/tsx/dist/loader.mjs server/dist/index.js
```

---

## 5. `paperclipai/xdg-open`

Two-line static stub, baked into the image at `/usr/local/bin/xdg-open` (prevents the
`ENOENT` crash when `paperclipai auth login` opens a browser headlessly):

```sh
#!/bin/sh
exit 0
```

---

## 6. `paperclipai/DOCS.md`, `translations/en.yaml`, branding

- **DOCS.md** — in-UI documentation: config option reference, first-run/bootstrap-ceo
  flow, LLM routing (Anthropic-direct vs LiteLLM), the hired-agent `model: null` PATCH
  fix, allowed-hostname + restart note, troubleshooting. Mostly distill the existing
  `README.md` (which is already accurate).
- **translations/en.yaml** — `configuration:` block with a `name:`/`description:` pair
  per option (grafana_cloud format), so the HA config UI shows friendly labels.
- **icon.png / logo.png** — placeholder PNGs (paperclip motif). Replace with real
  branding later; placeholders are acceptable for the initial version.

---

## Risks / edge cases to keep in mind during implementation

1. **Build RAM/time on HAOS** — `pnpm install` + UI/server build + global CLIs is heavy
   (~1 GB, multi-minute); low-RAM hosts may OOM. README already warns; keep multi-stage.
2. **Upstream Dockerfile drift** — pinned tag + the `test -f` guard + a tag-bump
   checklist (diff upstream Dockerfile → update filters + CMD → rebuild).
3. **Postgres-as-root** — embedded PG refuses root; mitigated by `chown` + `gosu node`.
4. **Allowed-hostname restart** — adding a host updates config+DB but the running server
   caches the allowlist; seeding on every boot covers the common case, a newly added
   *custom* hostname needs one restart. Document.
5. **Hired-agent `model` hardcoding** — doc-only PATCH-to-`null` fix (already in README).
6. **git/gh creds for agent workspaces** — out of add-on scope; note in DOCS.

---

## Verification / testing

**Static (Windows dev box — do NOT build this heavy image locally):**
- Confirm `config.yaml` has no `image:` field, no `build.yaml` exists, `arch: [amd64]`.
- `bash -n run.sh` (+ shellcheck if available).
- Re-fetch upstream's `Dockerfile` at `v2026.618.0` and diff its build steps + CMD
  against our stages.

**On the HA host (the real test):**
1. Add the repo URL; confirm the add-on appears in the store.
2. Install; watch the build log for clone-at-tag → `pnpm install` → the three builds →
   the `test -f server/dist/index.js` guard → CLI install. Note build time + peak RAM.
3. Set `better_auth_secret` + `public_url`; **Start**.
4. Negative test: clear `better_auth_secret` → expect the FATAL line + clean exit.
5. Persistence: confirm `/data/paperclip/instances/default/{db,secrets/master.key,
   logs/server.log}` appear; restart; confirm no re-init and data persists.
6. First-run: find the bootstrap-ceo invite banner in the Log; open it; create admin.
7. Hostname allowlist: reach the UI at `homeassistant.local:3100` and the LAN IP with
   no "not allowed" error; add a custom host, restart, confirm.
8. Ports: `3100/tcp` reachable; confirm `:54329` is NOT exposed on the host.
9. Postgres health: `server.log` shows ~30s heartbeats (confirms `gosu node` works).
10. LLM routing smoke test against a LiteLLM endpoint; apply `model: null` if an agent
    still hits Anthropic.
11. Workspaces: drop a repo into `/share` (→ `/workspaces/<repo>` in container), point
    a project's execution workspace at the in-container path, confirm the agent reads it.
12. Update path: bump `version` + `PAPERCLIP_REF`, rebuild, confirm `/data` untouched.
```

