# PaperclipAI on Docker — Reference Documentation

> Written 2026-06-25. Purpose: document the working PaperclipAI Docker setup on warp10 in full detail, as a kickstart reference for building a Home Assistant add-on that replicates this setup inside HAOS.

---

## What is PaperclipAI?

PaperclipAI is an **open-source, self-hosted AI project management platform**. It gives AI agents (Claude Code, Codex, Gemini CLI, OpenCode) a structured company/project/issue board to work from. Agents autonomously pick up issues, check out code, do the work, and report back — like a virtual engineering team.

- **GitHub:** https://github.com/paperclipai/paperclip
- **License:** Open source (self-host)
- **Latest release tags:** `v2026.529.0`, `v2026.609.0`, `v2026.618.0` (as of 2026-06-25)
- **Web UI** runs on port `3100`
- **CLI tool:** `pnpm paperclipai <command>`

---

## Host Machine (warp10)

| Property | Value |
|---|---|
| Hostname | `warp10-build-01` |
| IP | `192.168.1.181` |
| OS | Ubuntu 24.04.4 LTS, kernel `6.8.0-110-generic`, x86_64 |
| CPU | 12× Intel Core Ultra 9 275HX |
| RAM | 3.7 GB RAM, 4 GB swap |
| SSH | `warp10@192.168.1.181` (passwordless from HA host via `claude-code@ha` key) |
| Docker | Running, `docker0` bridge |
| Source location | `/home/warp10/paperclip/` (git clone of upstream) |
| Data location | `/home/warp10/paperclip/data/docker-paperclip/` (persistent volume) |
| Workspaces | `/home/warp10/workspaces/` (mounted into container as `/workspaces`) |

---

## Source Code Setup

PaperclipAI is built from source (no pre-built Docker image is published). The repo is cloned directly on warp10:

```bash
git clone https://github.com/paperclipai/paperclip.git /home/warp10/paperclip
```

**Updating:**
```bash
cd /home/warp10/paperclip
git pull origin master
cd docker
docker compose -f docker-compose.quickstart.yml build
docker compose -f docker-compose.quickstart.yml up -d --force-recreate
```

> **Lesson learned:** The Dockerfile has changed between releases. Always `git checkout Dockerfile` before pulling if you have local modifications, or stash first. In our case the Dockerfile was accidentally collapsed during a failed build attempt.

---

## Dockerfile (multi-stage build)

Location: `/home/warp10/paperclip/Dockerfile`

The build has three stages:

### Stage 1: `base`
- Based on `node:lts-trixie-slim`
- Installs system tools: `ca-certificates gosu curl gh git wget ripgrep python3 openssh-client jq`
- GitHub CLI (`gh`) is now installed from the standard apt repo (was previously a manual keyring install — simpler now)
- Enables `corepack` (pnpm)
- Remaps `node` user UID/GID to match host via `ARG USER_UID/USER_GID` (default 1000)

### Stage 2: `deps` + `build`
- Copies all `package.json` files and runs `pnpm install --frozen-lockfile`
- Builds: UI (`@paperclipai/ui`), plugin SDK, server (`@paperclipai/server`)
- Packages included: `shared`, `db`, `adapter-utils`, `mcp-server`, `skills-catalog`, `teams-catalog`
- Adapters included: `acpx-local`, `claude-local`, `codex-local`, `cursor-cloud`, `cursor-local`, `gemini-local`, `grok-local`, `openclaw-gateway`, `opencode-local`, `pi-local`
- Plugins included: `sdk`, sandbox providers, `paperclip-plugin-fake-sandbox`, `plugin-llm-wiki`, `plugin-workspace-diff`

### Stage 3: `production`
- Globally installs AI CLI tools:
  - `@anthropic-ai/claude-code@latest` — Claude Code
  - `@openai/codex@latest` — OpenAI Codex CLI
  - `opencode-ai` — OpenCode
  - `@google/gemini-cli@latest` — Gemini CLI
- Creates `/paperclip` directory owned by `node` user
- Sets `HOME=/paperclip` so all AI tools write their config/cache there

**Key environment variables baked into the image:**
```
NODE_ENV=production
HOME=/paperclip
HOST=0.0.0.0
PORT=3100
SERVE_UI=true
PAPERCLIP_HOME=/paperclip
PAPERCLIP_INSTANCE_ID=default
PAPERCLIP_CONFIG=/paperclip/instances/default/config.json
PAPERCLIP_DEPLOYMENT_MODE=authenticated
PAPERCLIP_DEPLOYMENT_EXPOSURE=private
OPENCODE_ALLOW_ALL_MODELS=true
GEMINI_SANDBOX=false
```

**Entrypoint:** `/usr/local/bin/docker-entrypoint.sh`
- Remaps `node` user UID/GID at runtime to match `USER_UID`/`USER_GID` env vars
- Uses `gosu node` to drop privileges before starting the server
- If already running unprivileged (e.g. Kubernetes), skips remapping and warns

**CMD:**
```
node --import ./server/node_modules/tsx/dist/loader.mjs server/dist/index.js
```

---

## docker-compose.quickstart.yml

Location: `/home/warp10/paperclip/docker/docker-compose.quickstart.yml`

This is the compose file actually used (NOT `docker-compose.yml` which has a separate `db` service and named volumes — that's unused here).

```yaml
services:
  paperclip:
    build:
      context: ..
      dockerfile: Dockerfile
    ports:
      - "${PAPERCLIP_PORT:-3100}:3100"
    environment:
      HOST: "0.0.0.0"
      PAPERCLIP_HOME: "/paperclip"
      PAPERCLIP_DEPLOYMENT_MODE: "authenticated"
      PAPERCLIP_DEPLOYMENT_EXPOSURE: "private"
      PAPERCLIP_PUBLIC_URL: "${PAPERCLIP_PUBLIC_URL:-http://localhost:3100}"
      BETTER_AUTH_SECRET: "${BETTER_AUTH_SECRET:?BETTER_AUTH_SECRET must be set}"
      # LLM routing
      ANTHROPIC_BASE_URL: "${ANTHROPIC_BASE_URL}"
      ANTHROPIC_AUTH_TOKEN: "${ANTHROPIC_AUTH_TOKEN}"
      ANTHROPIC_API_KEY: "${ANTHROPIC_API_KEY:-}"
      ANTHROPIC_MODEL: "${ANTHROPIC_MODEL}"
      ANTHROPIC_SMALL_FAST_MODEL: "${ANTHROPIC_SMALL_FAST_MODEL}"
      ANTHROPIC_DEFAULT_HAIKU_MODEL: "${ANTHROPIC_DEFAULT_HAIKU_MODEL}"
      ANTHROPIC_DEFAULT_SONNET_MODEL: "${ANTHROPIC_DEFAULT_SONNET_MODEL}"
      ANTHROPIC_DEFAULT_OPUS_MODEL: "${ANTHROPIC_DEFAULT_OPUS_MODEL}"
      CLAUDE_CODE_SUBAGENT_MODEL: "${CLAUDE_CODE_SUBAGENT_MODEL}"
      CLAUDE_CODE_EFFORT: "${CLAUDE_CODE_EFFORT}"
      CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS}"
      CLAUDECODE: "${CLAUDECODE}"
      DISABLE_PROMPT_CACHING: "${DISABLE_PROMPT_CACHING}"
      CLAUDE_CODE_DISABLE_THINKING: "${CLAUDE_CODE_DISABLE_THINKING}"
      CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING: "${CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING}"
      CLAUDE_CODE_USE_BEDROCK: "${CLAUDE_CODE_USE_BEDROCK}"
      CLAUDE_CODE_USE_VERTEX: "${CLAUDE_CODE_USE_VERTEX}"
      OPENAI_API_KEY: "${OPENAI_API_KEY:-}"
      OPENCODE_ALLOW_ALL_MODELS: "${OPENCODE_ALLOW_ALL_MODELS:-true}"
    volumes:
      - "${PAPERCLIP_DATA_DIR:-../data/docker-paperclip}:/paperclip"
      - "/home/warp10/workspaces:/workspaces"
```

**Important notes:**
- **No separate database container.** PaperclipAI uses an **embedded PostgreSQL** instance that runs inside the same container, listening on port `54329` (internal only, not exposed to host).
- The bind mount `${PAPERCLIP_DATA_DIR}:/paperclip` is the **only persistence mechanism**. All state lives there.
- `/workspaces` is mounted so agents can access cloned git repos. Without this, agents cannot reach repos on the host filesystem.
- The `quickstart` compose file has a single service named `paperclip`, resulting in container name `docker-paperclip-1`.
- The other `docker-compose.yml` in the same folder has a `server` + `db` service with named volumes — **do not mix the two files** or you'll get orphan containers.

---

## .env File

Location: `/home/warp10/paperclip/docker/.env`

Docker Compose reads this automatically when running from the `docker/` directory.

```env
PAPERCLIP_PORT=3100
PAPERCLIP_PUBLIC_URL=http://192.168.1.181:3100
BETTER_AUTH_SECRET=<random 64-char hex>
PAPERCLIP_DATA_DIR=../data/docker-paperclip

# LiteLLM proxy (replaces direct Anthropic API)
ANTHROPIC_BASE_URL=http://192.168.1.131:4000
ANTHROPIC_AUTH_TOKEN=<litellm_api_key>
ANTHROPIC_API_KEY=
ANTHROPIC_MODEL=qwen3-coder-gx10-vllm
ANTHROPIC_SMALL_FAST_MODEL=qwen3-coder-gx10-vllm
ANTHROPIC_DEFAULT_HAIKU_MODEL=qwen3-coder-gx10-vllm
ANTHROPIC_DEFAULT_SONNET_MODEL=qwen3-coder-gx10-vllm
ANTHROPIC_DEFAULT_OPUS_MODEL=qwen3-coder-gx10-vllm
CLAUDE_CODE_SUBAGENT_MODEL=qwen3-coder-gx10-vllm
CLAUDE_CODE_EFFORT=high
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
CLAUDECODE=1
DISABLE_PROMPT_CACHING=1
CLAUDE_CODE_DISABLE_THINKING=0
CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1
CLAUDE_CODE_USE_BEDROCK=0
CLAUDE_CODE_USE_VERTEX=0
OPENAI_API_KEY=
OPENCODE_ALLOW_ALL_MODELS=true
```

**`BETTER_AUTH_SECRET`** must be set — PaperclipAI uses [better-auth](https://better-auth.com) for authentication and this is the signing secret. Generate with: `openssl rand -hex 32`

---

## LiteLLM Integration (local model routing)

On warp10 we route ALL AI traffic through a LiteLLM proxy running on the HA host (`192.168.1.131:4000`) instead of calling Anthropic directly. This is how to point PaperclipAI at any OpenAI-compatible or Anthropic-compatible endpoint:

| Variable | Purpose |
|---|---|
| `ANTHROPIC_BASE_URL` | Override the Anthropic API base URL — set to LiteLLM endpoint |
| `ANTHROPIC_AUTH_TOKEN` | The LiteLLM master key (NOT an Anthropic key) |
| `ANTHROPIC_API_KEY` | Set to empty string to avoid fallback to real Anthropic |
| `ANTHROPIC_MODEL` | Model name as known to LiteLLM (e.g. `qwen3-coder-gx10-vllm`) |
| `ANTHROPIC_DEFAULT_HAIKU/SONNET/OPUS_MODEL` | Override each model tier to the same local model |

> **Lesson learned:** When a new agent is created/edited via the web UI hire flow, the
> model dropdown's concrete default (e.g. `claude-sonnet-4-6`) gets persisted into the
> agent's `adapter_config.model` in the database. For `claude_local` agents the adapter
> passes it to Claude Code as a literal `--model`, overriding the container-level env
> vars and sending traffic straight to Anthropic (or, against a proxy that doesn't know
> that id, failing every run at init with `400 Invalid model name`). Agents whose model
> is still null keep working, so only *some* runs break.
>
> **Fix — null the model surgically in the DB** (preserves all other `adapter_config`
> fields). Do **not** use the API `PATCH /api/agents/<id>` with `{"adapterConfig":{"model":null}}`:
> upstream issue [#964](https://github.com/paperclipai/paperclip/issues/964) makes that
> endpoint *replace* the whole `adapterConfig` instead of merging, wiping `cwd`,
> instruction paths and permissions.
>
> ```bash
> docker exec docker-paperclip-1 node -e "
> const {Client}=require(require.resolve('pg',{paths:['/app/server','/app']}));
> const c=new Client({host:'localhost',port:54329,user:'paperclip',password:'paperclip',database:'paperclip'});
> c.connect().then(()=>c.query(\"UPDATE agents SET adapter_config=jsonb_set(adapter_config,'{model}','null'::jsonb) WHERE adapter_type IN ('claude_local','claude-local') AND adapter_config->>'model' IS NOT NULL\"))
>  .then(r=>{console.log('reset model on',r.rowCount,'agent(s)');return c.end();});
> "
> ```
>
> The HA add-on automates exactly this with a background reconciler
> (`heal-agent-models.js`, gated by the `enforce_env_model` option).

---

## Persistent Data Volume Structure

Everything under `/paperclip` inside the container maps to `/home/warp10/paperclip/data/docker-paperclip/` on the host.

```
/paperclip/   (→ host: /home/warp10/paperclip/data/docker-paperclip/)
├── instances/
│   └── default/
│       ├── config.json               ← server config (deployment mode, ports, storage, secrets)
│       ├── config.json.backup        ← auto-backup of config before changes
│       ├── .env                      ← instance-level env overrides (JWT secret for agents)
│       ├── db/                       ← embedded PostgreSQL data directory (postgres 17)
│       ├── secrets/
│       │   └── master.key            ← encryption key for secrets stored in DB
│       ├── logs/
│       │   └── server.log            ← server log (heartbeat cycles every ~30s)
│       ├── data/
│       │   ├── backups/              ← hourly DB backups (retained 30 days)
│       │   ├── run-logs/             ← per-agent per-issue run logs (ndjson)
│       │   ├── storage/              ← file attachments/uploads
│       │   └── workspace-operation-logs/
│       ├── telemetry/
│       │   └── state.json
│       ├── companies/
│       │   └── <company-uuid>/
│       │       ├── agents/
│       │       │   └── <agent-uuid>/
│       │       │       └── instructions/
│       │       │           ├── AGENTS.md    ← main agent instructions + org chart
│       │       │           ├── SOUL.md      ← persona + values
│       │       │           ├── HEARTBEAT.md ← what to do on each wake-up cycle
│       │       │           └── TOOLS.md     ← tool usage guidance
│       │       └── claude-prompt-cache/     ← cached bundled prompts (ephemeral)
│       ├── projects/
│       │   └── <company-uuid>/
│       │       └── <project-uuid>/          ← project-scoped data
│       └── workspaces/
│           └── <agent-uuid>/               ← per-agent git checkouts
│               └── (cloned repo contents)
├── .codex/skills/                          ← PaperclipAI skills for Codex CLI (symlinks)
├── .claude/skills/                         ← PaperclipAI skills for Claude Code (symlinks)
└── context.json                            ← CLI auth context (api-base, company-id, token)
```

**What lives in PostgreSQL (not on disk):**
- Agent name, role, title, status, icon
- `adapter_type` and `adapter_config` (model, cwd, timeouts, instruction paths)
- `runtime_config` (heartbeat settings: enabled, intervalSec, cooldownSec)
- All issues, comments, approvals, projects
- User accounts and sessions (via better-auth)
- Execution workspace records

**What lives on disk:**
- Agent instruction markdown files (AGENTS.md, SOUL.md, HEARTBEAT.md, TOOLS.md)
- The embedded PostgreSQL data directory itself
- Run logs, backups, file storage

---

## Embedded PostgreSQL

PaperclipAI runs its own PostgreSQL 17 instance **inside the container** on port `54329`. It is NOT exposed to the host. Access it from inside the container via:

```bash
docker exec docker-paperclip-1 node -e "
const {Client} = require('/app/node_modules/.pnpm/pg@8.18.0/node_modules/pg');
const c = new Client({host:'localhost',port:54329,user:'paperclip',password:'paperclip',database:'paperclip'});
c.connect().then(() => c.query('SELECT id,name,role FROM agents')).then(r => { console.log(r.rows); c.end(); });
"
```

> **Note:** `psql` and `sqlite3` are not installed in the container. Use Node.js with the bundled `pg` module at the path shown above.

The data directory is at `/paperclip/instances/default/db/` (inside container) = `/home/warp10/paperclip/data/docker-paperclip/instances/default/db/` on the host. **Never delete or modify this while the container is running.**

Hourly backups are written to `/paperclip/instances/default/data/backups/` (retention: 30 days).

---

## instance config.json

Location inside container: `/paperclip/instances/default/config.json`

This is written by `paperclipai onboard` or `paperclipai configure` and is NOT edited manually. Key fields:

```json
{
  "database": {
    "mode": "embedded-postgres",
    "embeddedPostgresDataDir": "/paperclip/instances/default/db",
    "embeddedPostgresPort": 54329,
    "backup": { "enabled": true, "intervalMinutes": 60, "retentionDays": 30 }
  },
  "server": {
    "deploymentMode": "authenticated",
    "exposure": "private",
    "host": "0.0.0.0",
    "port": 3100,
    "allowedHostnames": ["192.168.1.181", "192.168.1.197"],
    "serveUi": true
  },
  "secrets": {
    "provider": "local_encrypted",
    "localEncrypted": { "keyFilePath": "/paperclip/instances/default/secrets/master.key" }
  },
  "storage": { "provider": "local_disk" }
}
```

---

## Allowed Hostnames

PaperclipAI enforces a hostname allowlist when `deploymentMode=authenticated`. If you access the UI from a hostname/IP not in the list you get:

```
Hostname '192.168.1.X' is not allowed for this Paperclip instance.
If you want to allow this hostname, please run pnpm paperclipai allowed-hostname 192.168.1.X
```

**Fix:**
```bash
docker exec docker-paperclip-1 pnpm paperclipai allowed-hostname <hostname-or-ip>
docker restart docker-paperclip-1
```

The allowed list is stored in `config.json` under `server.allowedHostnames` AND in the database. Adding via the CLI updates both.

---

## CLI Tool (paperclipai)

The CLI is available inside the container:

```bash
docker exec docker-paperclip-1 pnpm paperclipai <command>
```

**Authentication:** The CLI uses a context file at `/paperclip/context.json` (inside container). Set it up with:

```bash
docker exec docker-paperclip-1 pnpm paperclipai context set \
  --api-base http://localhost:3100 \
  --company-id <UUID>
```

**Board user login** (interactive — requires browser):
```bash
docker exec docker-paperclip-1 pnpm paperclipai auth login --api-base http://localhost:3100
```

> **Lesson learned:** The container has no display server, so `xdg-open` (used to open the auth URL in a browser) crashes the process with an uncaught `ENOENT` error before the CLI can poll for approval. Fix: install a dummy `xdg-open` in the container:
> ```bash
> docker exec docker-paperclip-1 sh -c 'echo "#!/bin/sh\nexit 0" > /usr/local/bin/xdg-open && chmod +x /usr/local/bin/xdg-open'
> ```
> Then re-run `auth login`, manually open the printed URL in your browser, and the CLI will pick up the approval.

**Key CLI commands:**

```bash
# Company management
pnpm paperclipai company list
pnpm paperclipai company delete <id> --confirm <id> --yes
pnpm paperclipai company export <id>
pnpm paperclipai company import <path>

# Agent management
pnpm paperclipai agent list --company-id <id>
pnpm paperclipai agent get <agentId>
pnpm paperclipai agent local-cli <agentId> --company-id <id>   # creates API key + installs skills

# Issue management
pnpm paperclipai issue list --status todo
pnpm paperclipai issue create --title "..." --project-id <id>
pnpm paperclipai issue checkout <issueId>

# Approvals (hire agent flow)
pnpm paperclipai approval list --company-id <id>
pnpm paperclipai approval approve <approvalId>

# Heartbeat (trigger agent manually)
pnpm paperclipai heartbeat run --debug

# Auth
pnpm paperclipai auth whoami
pnpm paperclipai auth bootstrap-ceo          # one-time admin invite URL
pnpm paperclipai auth bootstrap-ceo --force  # regenerate invite
pnpm paperclipai allowed-hostname <host>

# Configuration
pnpm paperclipai configure --section llm
pnpm paperclipai doctor
```

---

## First-Time Setup (bootstrap flow)

1. Start the container
2. Generate a one-time CEO invite:
   ```bash
   docker exec docker-paperclip-1 pnpm paperclipai auth bootstrap-ceo
   ```
3. Open the printed URL in a browser → create admin account
4. Create your company and first project in the web UI
5. Note the company UUID from the URL (`/RAP/dashboard` → shortname, or look in `config.json`)
6. Set CLI context:
   ```bash
   docker exec docker-paperclip-1 pnpm paperclipai context set \
     --api-base http://localhost:3100 --company-id <UUID>
   ```
7. Generate agent API key + install Claude Code skills:
   ```bash
   docker exec docker-paperclip-1 pnpm paperclipai agent local-cli <agentUUID> \
     --api-base http://localhost:3100 --company-id <UUID>
   ```

---

## Agent Architecture

Agents are stored in PostgreSQL. Key fields:

| Field | Description |
|---|---|
| `adapter_type` | `claude_local` — runs Claude Code inside the container |
| `adapter_config.cwd` | Working directory for the agent (e.g. `/workspaces/ClaudeUsageCatcher`) |
| `adapter_config.model` | Override model — **set to `null`** to inherit from env vars |
| `adapter_config.maxTurnsPerRun` | Max Claude turns per heartbeat run (CEO: 1000, engineers: 100) |
| `adapter_config.instructionsFilePath` | Path to `AGENTS.md` inside container |
| `adapter_config.instructionsBundleMode` | `managed` — PaperclipAI manages the instruction bundle |
| `adapter_config.dangerouslySkipPermissions` | `true` — agents run without permission prompts |
| `runtime_config.heartbeat.enabled` | Whether the agent auto-wakes on schedule |
| `runtime_config.heartbeat.intervalSec` | Heartbeat interval (default 300s) |
| `runtime_config.heartbeat.wakeOnDemand` | Wake when an issue is assigned |

**Agent instruction files** (on disk, per agent):
- `AGENTS.md` — primary instructions: role, responsibilities, how to use PaperclipAI API
- `SOUL.md` — persona, values, communication style
- `HEARTBEAT.md` — procedure for each wake-up cycle (check issues → checkout → work → comment → mark done)
- `TOOLS.md` — tool usage guidance (usually minimal)

**Hiring new agents:** Done via the web UI hire flow, which creates a `hire_agent` approval request. You (as board user) approve it. The agent is then created in the DB.

> **Lesson learned:** After hiring via the web UI, check `adapter_config.model` — the UI may set it to a hardcoded model string (e.g. `claude-sonnet-4-6`). Always null it out so the agent inherits the container-level model env vars.

---

## PaperclipAI Skills for Claude Code

Running `agent local-cli` installs PaperclipAI skills into `~/.claude/skills/` (and `~/.codex/skills/`). Inside the container, `HOME=/paperclip`, so skills land at `/paperclip/.claude/skills/`.

Skills installed:
- `paperclip` — core skill: list/get/checkout/comment on issues
- `paperclip-create-agent` — create new agents
- `paperclip-create-plugin` — create plugins

These are **symlinks** inside the container pointing to `/app/skills/`. To copy them to an external machine:

```bash
docker exec docker-paperclip-1 tar -C /app/skills -cf - paperclip paperclip-create-agent paperclip-create-plugin \
  | tar -C ~/.claude/skills -xf -
```

Then set these env vars on the external machine:

```bash
export PAPERCLIP_API_URL='http://192.168.1.181:3100'
export PAPERCLIP_COMPANY_ID='<company-uuid>'
export PAPERCLIP_AGENT_ID='<agent-uuid>'
export PAPERCLIP_API_KEY='pcp_...'
```

---

## Project & Workspace Setup

Projects are created in the web UI. Each project can have an **execution workspace** — a path to a git repo checkout where agents will run Claude Code.

In our setup:
- Repos are cloned to `/home/warp10/workspaces/` on the host
- This directory is mounted into the container as `/workspaces`
- The project execution workspace path is set to `/workspaces/<repo-name>` (the path as seen from inside the container)

**Clone a repo for agents to use:**
```bash
# On warp10 host
git config --global credential.helper store
git clone https://<user>:<PAT>@dev.azure.com/... /home/warp10/workspaces/MyProject
```

The container can then read/write it at `/workspaces/MyProject`.

> **Lesson learned:** If you set the workspace path to the host path (e.g. `/home/warp10/workspaces/...`) without the volume mount, agents get "path not found" errors. The path must be as seen from **inside the container**.

---

## Agent Instructions Git Repository

Agent instruction markdown files are version-controlled separately from the application.

**Repo:** `https://dev.azure.com/raptox/Raptox%20INC/_git/Raptox%20INC`

**Structure:**
```
Raptox INC/
├── manifest.json          ← maps human names → UUIDs + company metadata
├── sync.sh                ← bidirectional sync script
├── .gitignore             ← ignores: agents/ (UUID dirs), claude-prompt-cache/
└── agents-named/
    ├── CEO/
    │   └── instructions/
    │       ├── AGENTS.md
    │       ├── SOUL.md
    │       ├── HEARTBEAT.md
    │       └── TOOLS.md
    └── CodeReviewer/
        └── instructions/
            └── AGENTS.md
```

**Workflow:**
```bash
# Edit instructions on any machine, commit, push
git clone https://dev.azure.com/raptox/Raptox%20INC/_git/Raptox%20INC
# edit agents-named/CEO/instructions/AGENTS.md ...
git commit -am "refine CEO heartbeat" && git push

# On warp10: pull and apply to PaperclipAI
git pull && ./sync.sh push   # copies named → UUID dirs

# If PaperclipAI updated instructions itself:
./sync.sh pull && git commit -am "sync from paperclip"
```

---

## Networking

| Endpoint | Access |
|---|---|
| `http://192.168.1.181:3100` | PaperclipAI web UI (LAN only) |
| `http://localhost:3100` | From inside the container |
| Embedded Postgres `:54329` | Internal only, not exposed |

The container runs with `--network bridge` (default Docker networking). No special network configuration needed.

---

## Lessons Learned (Critical for HA Add-on)

### 1. No pre-built image — must build from source
There is no `docker pull paperclipai/paperclip` or similar. You must clone the GitHub repo and run `docker build`. This means the HA add-on will need either:
- A pre-built image pushed to a registry (GHCR), OR
- A build step that runs on the HA host (slow, resource-heavy)

**Recommendation for HA add-on:** Pre-build the image on a capable machine and push to `ghcr.io`. The HA add-on then just pulls it.

### 2. Embedded PostgreSQL runs inside the container
No external database needed. The embedded Postgres starts automatically when the container starts. This simplifies the HA add-on (single container, no sidecar). Data directory must be on a persistent volume.

### 3. BETTER_AUTH_SECRET is mandatory
The container will refuse to start without `BETTER_AUTH_SECRET`. Generate once with `openssl rand -hex 32` and store persistently in the add-on config.

### 4. xdg-open crash in headless environments
The `paperclipai auth login` command tries to open a browser via `xdg-open`, which crashes the Node.js process in a headless container. Must install a dummy `xdg-open` that exits 0 before running any auth login flow. The HA add-on should include this in the image or entrypoint.

### 5. Hostname allowlist
Every IP/hostname used to access the UI must be added to the allowlist. The HA add-on entrypoint should pre-populate `allowedHostnames` with common HA hostnames (`homeassistant.local`, `192.168.x.x`, `localhost`) or expose a config option.

### 6. Model hardcoding in hired agents
When agents are hired via the web UI, `adapter_config.model` may be set to a hardcoded Anthropic model name. With a custom LLM endpoint this breaks routing. The add-on should document this or patch new agents automatically.

### 7. Volumes: two separate mounts needed
- `/paperclip` — persistent state (DB, secrets, logs, config, agent instructions)
- `/workspaces` — git repos for agents to work in (optional but needed for code agents)

### 8. HOME=/paperclip inside container
The image sets `HOME=/paperclip`. This means Claude Code, Codex, Gemini CLI, and OpenCode all write their config and cache to `/paperclip/`. This ensures everything is captured in the persistent volume.

### 9. Port 54329 is internal-only
The embedded PostgreSQL never needs to be exposed externally. Do not map it in the add-on config.

### 10. Skills are symlinks — they break on copy
The PaperclipAI skills in `/paperclip/.claude/skills/` are symlinks to `/app/skills/`. Copying them to an external machine requires `tar` (not `cp -r`). The symlinks themselves work fine inside the container.

### 11. context.json persists CLI auth
The CLI context file at `/paperclip/context.json` (inside container) stores the board user token. Since `/paperclip` is a persistent volume, CLI auth survives container restarts and upgrades — you only need to log in once.

### 12. orphan containers from multiple compose files
The `docker/` directory contains multiple compose files (`docker-compose.yml`, `docker-compose.quickstart.yml`, `docker-compose.untrusted-review.yml`). Running them in the same directory creates containers in the same Docker Compose project, leading to orphan warnings. Always use `--remove-orphans` or stick to one compose file.

---

## Update Procedure

1. `git pull origin master` in `/home/warp10/paperclip/`
2. Check `git diff Dockerfile` — restore if accidentally modified: `git checkout Dockerfile`
3. `docker compose -f docker-compose.quickstart.yml build` (takes ~5–10 min)
4. `docker compose -f docker-compose.quickstart.yml up -d --force-recreate --remove-orphans`
5. Verify: check env vars still present, test web UI, check heartbeat logs

Data is **never touched** during an update — it lives in the bind-mounted volume.

---

## For the HA Add-on Builder

**What the add-on needs:**

| Item | Details |
|---|---|
| Base image | Pre-built from https://github.com/paperclipai/paperclip (multi-stage, ~1 GB compressed) |
| Port | `3100/tcp` |
| Persistent volume | Map to `/paperclip` inside container |
| Optional volume | Map a repo directory to `/workspaces` inside container |
| Required config | `BETTER_AUTH_SECRET`, `PAPERCLIP_PUBLIC_URL`, `ANTHROPIC_*` or `OPENAI_*` keys |
| Optional config | All `CLAUDE_CODE_*`, `ANTHROPIC_MODEL`, `ANTHROPIC_BASE_URL` for custom LLM routing |
| Entrypoint hook | Install dummy `xdg-open` before server starts |
| First-run | Run `pnpm paperclipai auth bootstrap-ceo` and show URL to user |
| HA ingress | PaperclipAI serves its own UI — use HA ingress or direct port forwarding |

**Reference files on warp10:**
- Source: `/home/warp10/paperclip/`
- Compose: `/home/warp10/paperclip/docker/docker-compose.quickstart.yml`
- Env: `/home/warp10/paperclip/docker/.env`
- Data: `/home/warp10/paperclip/data/docker-paperclip/`
- Workspaces: `/home/warp10/workspaces/`

**Useful URLs:**
- GitHub repo: https://github.com/paperclipai/paperclip
- better-auth docs: https://better-auth.com
- HA add-on development docs: https://developers.home-assistant.io/docs/add-ons/
- HA add-on config reference: https://developers.home-assistant.io/docs/add-ons/configuration
- HAOS Docker base images: https://github.com/home-assistant/docker-base
