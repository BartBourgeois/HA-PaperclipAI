# PaperclipAI — Home Assistant Add-on

Run **[PaperclipAI](https://github.com/paperclipai/paperclip)** inside Home Assistant:
an open-source, self-hosted AI project-management board that gives AI coding agents
(Claude Code, Codex, Gemini CLI, OpenCode) a structured company / project / issue
board to work from.

> **Builds from source.** PaperclipAI publishes no Docker image, so this add-on
> clones the upstream repo at a pinned tag (`v2026.618.0`) and builds it **locally on
> your HA host** the first time you install it. Expect a **~1 GB image** and a
> **multi-minute build**. `amd64` only; give the host several GB of RAM.

---

## Quick start

1. Install the add-on (first install builds from source — be patient).
2. Open **Configuration** and set **`better_auth_secret`** — generate it once with:
   ```bash
   openssl rand -hex 32
   ```
   The server **refuses to start** without it.
3. (Optional) set `public_url` to how you reach HA, e.g.
   `http://homeassistant.local:3100`.
4. **Start** the add-on and open the **Log** tab.
5. On first run the log prints a **one-time CEO invite URL** — open it in your browser
   and create your admin account.
6. Open the UI at `http://homeassistant.local:3100` (or `http://<ha-ip>:3100`).

---

## Configuration options

### Required

| Option | Description |
|--------|-------------|
| `better_auth_secret` | Signing secret for authentication ([better-auth](https://better-auth.com)). Generate once with `openssl rand -hex 32` and keep it **stable** — changing it invalidates existing sessions. |

### General

| Option | Description |
|--------|-------------|
| `public_url` | Public URL of the UI, e.g. `http://homeassistant.local:3100`. Maps to `PAPERCLIP_PUBLIC_URL`. |
| `allowed_hostnames` | List of hostnames/IPs allowed to reach the UI. `homeassistant.local`, `localhost` and the container's LAN IP are auto-seeded on every boot; add anything else here. |

### LLM routing (Anthropic-compatible)

PaperclipAI drives all agents through Anthropic-compatible env vars. Point them at the
real Anthropic API **or** any compatible endpoint (e.g. a [LiteLLM](https://github.com/BartBourgeois/HA-LiteLLM)
proxy in front of local models).

| Option | Env var | Description |
|--------|---------|-------------|
| `anthropic_base_url` | `ANTHROPIC_BASE_URL` | Override the API base URL — set to your LiteLLM/compatible endpoint. |
| `anthropic_auth_token` | `ANTHROPIC_AUTH_TOKEN` | Token for that endpoint (e.g. the LiteLLM master key). |
| `anthropic_api_key` | `ANTHROPIC_API_KEY` | Real Anthropic key. Leave **empty** when using a custom endpoint to avoid falling back to Anthropic. |
| `anthropic_model` | `ANTHROPIC_MODEL` | Model name as known to your endpoint. |
| `anthropic_small_fast_model` | `ANTHROPIC_SMALL_FAST_MODEL` | Small/fast model override. |
| `anthropic_default_haiku_model` | `ANTHROPIC_DEFAULT_HAIKU_MODEL` | Haiku-tier override. |
| `anthropic_default_sonnet_model` | `ANTHROPIC_DEFAULT_SONNET_MODEL` | Sonnet-tier override. |
| `anthropic_default_opus_model` | `ANTHROPIC_DEFAULT_OPUS_MODEL` | Opus-tier override. |
| `openai_api_key` | `OPENAI_API_KEY` | OpenAI key (for the Codex CLI), if used. |

### Claude Code flags (advanced)

These are passed through verbatim as strings, because upstream consumes values like
`"1"`, `"0"`, `"high"` (several are tri-state). Leave empty unless you know you need them.

| Option | Env var |
|--------|---------|
| `claude_code_subagent_model` | `CLAUDE_CODE_SUBAGENT_MODEL` |
| `claude_code_effort` | `CLAUDE_CODE_EFFORT` |
| `claude_code_experimental_agent_teams` | `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` |
| `claudecode` | `CLAUDECODE` |
| `disable_prompt_caching` | `DISABLE_PROMPT_CACHING` |
| `claude_code_disable_thinking` | `CLAUDE_CODE_DISABLE_THINKING` |
| `claude_code_disable_adaptive_thinking` | `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` |
| `claude_code_use_bedrock` | `CLAUDE_CODE_USE_BEDROCK` |
| `claude_code_use_vertex` | `CLAUDE_CODE_USE_VERTEX` |
| `opencode_allow_all_models` | `OPENCODE_ALLOW_ALL_MODELS` (default `true`) |

---

## First-run / bootstrap-ceo flow

On the **first start**, the entrypoint waits for the server to come up, then runs:

```bash
pnpm paperclipai auth bootstrap-ceo
```

and prints the resulting **invite URL** in a banner in the add-on **Log**. Open it,
create your admin account, then build your company and first project in the UI.

A marker file (`/data/paperclip/.ha_bootstrapped`) prevents this from re-running on
later boots. To regenerate the invite, open the add-on console and run:

```bash
pnpm paperclipai auth bootstrap-ceo --force
```

---

## LLM routing — two common setups

**A) Anthropic directly**
```yaml
anthropic_api_key: "sk-ant-..."
anthropic_model: "claude-sonnet-4-6"
```

**B) Through a LiteLLM proxy (local models)**
```yaml
anthropic_base_url: "http://192.168.1.131:4000"
anthropic_auth_token: "<litellm-master-key>"
anthropic_api_key: ""                 # empty to avoid falling back to Anthropic
anthropic_model: "qwen3-coder-gx10-vllm"
anthropic_default_haiku_model: "qwen3-coder-gx10-vllm"
anthropic_default_sonnet_model: "qwen3-coder-gx10-vllm"
anthropic_default_opus_model: "qwen3-coder-gx10-vllm"
```

### ⚠️ Hired-agent model override

When you hire an agent via the web UI, PaperclipAI may hardcode `adapter_config.model`
to a real Anthropic model (e.g. `claude-sonnet-4-6`), which **bypasses your custom
routing** and sends traffic straight to Anthropic. Fix it by PATCHing the agent's
model to `null` so it inherits the add-on's env vars:

```bash
curl -X PATCH http://localhost:3100/api/agents/<AGENT_ID> \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <AGENT_API_KEY>" \
  -d '{"adapterConfig": {"model": null}}'
```

---

## Hostname allowlist

With `deploymentMode=authenticated`, every hostname/IP used to reach the UI must be
allowlisted, or you get *"Hostname '…' is not allowed for this Paperclip instance."*

The add-on **auto-seeds** `homeassistant.local`, `localhost`, the container LAN IP, and
everything in your `allowed_hostnames` option on **every boot**. To add a brand-new
custom host, add it to `allowed_hostnames` (or run the CLI) and **restart** the add-on —
the running server caches the allowlist, so a restart is required:

```bash
pnpm paperclipai allowed-hostname <hostname-or-ip>
```

---

## Workspaces (repos for code agents)

The add-on maps Home Assistant's **`/share`** to **`/workspaces`** inside the container.
Drop a git checkout into `/share` (via Samba/SSH or by cloning into it), then set a
project's **execution workspace** to the path **as seen inside the container**:

```
/workspaces/<repo-name>
```

> Use the *in-container* path (`/workspaces/...`), **not** the host path, or agents get
> "path not found". Providing git/`gh` credentials for those repos is out of scope for
> the add-on — configure them inside the workspace as you would on any dev box.

---

## Storage & persistence

All state lives on the add-on's persistent **`/data`** volume (repointed from the
image's `/paperclip`), and survives restarts and updates:

```
/data/paperclip/
├── instances/default/
│   ├── config.json            server config (deployment mode, ports, allowlist)
│   ├── db/                     embedded PostgreSQL 17 data directory
│   ├── secrets/master.key     encryption key for DB secrets
│   ├── logs/server.log        server log (~30s heartbeats)
│   ├── data/{backups,run-logs,storage}
│   └── companies/.../agents/.../instructions/{AGENTS,SOUL,HEARTBEAT,TOOLS}.md
├── context.json               CLI auth context
└── .ha_bootstrapped           first-run marker (managed by the add-on)
```

The embedded **PostgreSQL** listens on `54329` **inside the container only** and is
never exposed to the host.

---

## Updating

Bump the add-on version (and the pinned `PAPERCLIP_REF` for a new upstream release),
then rebuild from the store. Your `/data` is **never touched** during an update.

> **Maintainer note:** upstream's Dockerfile drifts between releases. On each tag bump,
> diff upstream's `Dockerfile`, re-verify the three `pnpm --filter ... build` steps and
> the server start command, and rebuild. The `test -f server/dist/index.js` guard in
> the Dockerfile turns a silent upstream layout change into a hard build failure.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Server won't start, exits immediately | Ensure `better_auth_secret` is set (the log prints a `[FATAL]` line if empty). |
| `auth login` crashes the process | The add-on installs a dummy `xdg-open`. Open the printed URL manually in your browser. |
| *"Hostname '…' is not allowed"* | Add the host to `allowed_hostnames` (or run `pnpm paperclipai allowed-hostname <host>`) and **restart**. |
| Agent ignores your custom model / hits Anthropic | Hired agent has a hardcoded model — PATCH it to `"model": null` (see above). |
| Install/build is slow or OOMs | Expected — it builds ~1 GB from source. Give it time and enough RAM. |
| Postgres errors about running as root | The add-on already runs the server as the `node` user via `gosu` and `chown`s `/data/paperclip`. If you see this, the persistent dir may have wrong ownership — restart re-applies it. |

---

## Links

- PaperclipAI: <https://github.com/paperclipai/paperclip>
- better-auth: <https://better-auth.com>
- Home Assistant add-on docs: <https://developers.home-assistant.io/docs/add-ons/>
