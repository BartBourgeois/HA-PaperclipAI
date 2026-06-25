# Home Assistant Add-on: PaperclipAI

Run **[PaperclipAI](https://github.com/paperclipai/paperclip)** — an open-source,
self-hosted AI project-management platform — as a Home Assistant add-on.

PaperclipAI gives AI coding agents (Claude Code, Codex, Gemini CLI, OpenCode) a
structured **company / project / issue board** to work from. Agents autonomously
pick up issues, check out code, do the work, and report back — like a virtual
engineering team running inside your Home Assistant box.

> **Status:** beta. The add-on is now scaffolded — `config.yaml`, `Dockerfile`,
> `run.sh` and docs live under [paperclipai/](paperclipai/) and build PaperclipAI
> from upstream source (pinned tag `v2026.618.0`) on the HA host. It has not yet been
> build-tested on a live HAOS host. See [CLAUDE.md](CLAUDE.md) and [context.md](context.md).

---

## Features

- 🧠 **Self-hosted AI agent board** — issues, projects, agents, approvals, heartbeats.
- 🗄️ **Bundled embedded PostgreSQL** — no separate database add-on; Postgres runs
  inside the container (internal only).
- 🔌 **Bring your own LLM** — works with the Anthropic API directly, or any
  OpenAI/Anthropic-compatible endpoint such as a [LiteLLM](https://github.com/BartBourgeois/HA-LiteLLM)
  proxy (point it at local models).
- 💾 **Persistent** — all state (database, secrets, logs, agent instructions) lives
  on the add-on's persistent volume and survives restarts and updates.
- 🖥️ **Direct web UI** on port `3100`.

---

## Requirements & caveats

- **`amd64` only.** PaperclipAI plus its embedded PostgreSQL and bundled AI CLIs are
  heavy; ARM (Raspberry Pi etc.) is not supported.
- **Builds from source on install.** PaperclipAI publishes no Docker image, so the
  add-on compiles it from upstream source the first time you install it. Expect a
  **~1 GB image** and a **multi-minute build**. A low-RAM HAOS host may struggle —
  a machine with several GB of RAM is recommended.
- **`BETTER_AUTH_SECRET` is required** before the server will start (see below).

---

## Installation

1. In Home Assistant, go to **Settings → Add-ons → Add-on Store**.
2. Open the **⋮** menu (top right) → **Repositories** and add this repository's URL.
3. Find **PaperclipAI** in the store and click **Install**.
   _(First install builds from source and takes several minutes — this is normal.)_
4. Set the required options (next section), then **Start** the add-on.

---

## Configuration

Set these in the add-on's **Configuration** tab. The most important is
`better_auth_secret`.

| Option | Required | Description |
|--------|----------|-------------|
| `better_auth_secret` | ✅ | Signing secret for authentication. Generate once with `openssl rand -hex 32` and keep it stable. |
| `public_url` | – | Public URL of the UI, e.g. `http://homeassistant.local:3100`. |
| `allowed_hostnames` | – | Hostnames/IPs allowed to access the UI (e.g. `homeassistant.local`, your LAN IP). |
| `anthropic_base_url` | – | Override the Anthropic API base URL — set to a LiteLLM/compatible endpoint. |
| `anthropic_auth_token` | – | Token for that endpoint (e.g. the LiteLLM master key). |
| `anthropic_api_key` | – | Real Anthropic key. Leave empty when using a custom endpoint. |
| `anthropic_model` | – | Model name as known to your endpoint. |
| `anthropic_default_haiku_model` / `_sonnet_model` / `_opus_model` | – | Per-tier model overrides. |
| `openai_api_key` | – | OpenAI key (for Codex), if used. |
| `claude_code_*` | – | Advanced Claude Code flags (effort, agent teams, caching, thinking). |

> Generate the auth secret:
> ```bash
> openssl rand -hex 32
> ```

---

## First-time setup

1. **Start** the add-on and open its **Log** tab.
2. Generate the one-time CEO invite (run from the add-on console / `docker exec`):
   ```bash
   pnpm paperclipai auth bootstrap-ceo
   ```
   This prints an invite URL.
3. Open that URL in your browser and create your admin account.
4. In the web UI, create your **company** and first **project**.
5. Hire agents and assign them issues.

If the UI shows *"Hostname '…' is not allowed"*, add it to the allowlist:
```bash
pnpm paperclipai allowed-hostname <hostname-or-ip>
```
then restart the add-on.

---

## LLM routing

PaperclipAI talks to LLMs through the Anthropic-compatible env vars. Two common setups:

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

> ⚠️ When you hire an agent via the web UI, its model may be hardcoded (e.g.
> `claude-sonnet-4-6`), which bypasses custom routing. Fix by setting the agent's
> model to `null`:
> ```bash
> curl -X PATCH http://localhost:3100/api/agents/<AGENT_ID> \
>   -H "Content-Type: application/json" \
>   -H "Authorization: Bearer <AGENT_API_KEY>" \
>   -d '{"adapterConfig": {"model": null}}'
> ```

---

## Usage

Once running, open the web UI:

```
http://homeassistant.local:3100
```

(or `http://<your-ha-ip>:3100`). Use the bootstrap admin account from first-time setup.

---

## Storage & persistence

All PaperclipAI state is kept on the add-on's persistent volume (`/data`) and
survives restarts and updates:

- Embedded **PostgreSQL** data directory
- **Secrets** (encryption master key)
- Instance **config** and **logs**
- **Agent instruction** files (`AGENTS.md`, `SOUL.md`, `HEARTBEAT.md`, `TOOLS.md`)
- CLI auth context, run logs, hourly DB backups

The embedded PostgreSQL listens on port `54329` **inside the container only** and is
never exposed.

---

## Updating

1. Update the add-on (bump version / reinstall from the store).
2. The image rebuilds from the pinned PaperclipAI source.

Your data in `/data` is **never touched** during an update.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `auth login` crashes the process | The add-on installs a dummy `xdg-open`. Open the printed URL manually in your browser. |
| *"Hostname '…' is not allowed"* | `pnpm paperclipai allowed-hostname <host>` then restart. |
| Agent ignores your custom model / hits Anthropic | The hired agent has a hardcoded model — PATCH it to `"model": null` (see LLM routing). |
| Server won't start | Ensure `better_auth_secret` is set. |
| Install/build is slow | Expected — it builds ~1 GB from source. Give it time and enough RAM. |

---

## Architecture

```
┌─────────────────────────── Home Assistant host (amd64) ───────────────────────────┐
│  PaperclipAI add-on container                                                       │
│  ┌───────────────────────────┐        ┌──────────────────────────────┐             │
│  │ PaperclipAI server         │        │ Embedded PostgreSQL 17        │             │
│  │ (Node, port 3100)          │◄──────►│ (port 54329, internal only)   │             │
│  │ + AI CLIs (Claude/Codex/…) │        └──────────────────────────────┘             │
│  └─────────────┬─────────────┘                                                       │
│                │  state → /data (persistent)                                         │
└────────────────┼─────────────────────────────────────────────────────────────────┘
                 │
        ┌────────▼────────┐         ┌──────────────────────────────┐
        │ Browser :3100   │         │ LLM endpoint (Anthropic API   │
        │ (web UI)        │         │ or LiteLLM / local models)    │
        └─────────────────┘         └──────────────────────────────┘
```

---

## Links

- PaperclipAI: <https://github.com/paperclipai/paperclip>
- better-auth: <https://better-auth.com>
- Home Assistant add-on docs: <https://developers.home-assistant.io/docs/add-ons/>
- Reference setup notes: [context.md](context.md)

---

## License

This add-on is a packaging wrapper. PaperclipAI is licensed under its upstream
license — see the [PaperclipAI repository](https://github.com/paperclipai/paperclip).
