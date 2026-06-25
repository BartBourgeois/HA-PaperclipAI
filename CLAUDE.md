# CLAUDE.md — HA-PaperclipAI

Guidance for AI assistants (Claude Code) working in this repository.

---

## 1. Project overview & current status

**HA-PaperclipAI** is a Home Assistant add-on that runs **PaperclipAI** inside
HAOS. PaperclipAI is an open-source, self-hosted AI project-management platform:
it gives AI coding agents (Claude Code, Codex, Gemini CLI, OpenCode) a structured
company/project/issue board to work from. Agents autonomously pick up issues, check
out code, do the work, and report back — like a virtual engineering team.

This add-on **ports the working Docker setup** currently running on the `warp10`
machine. That setup is documented exhaustively in [context.md](context.md) — it is
the single most important reference in this repo. **Read it before writing any code.**

- Upstream project: <https://github.com/paperclipai/paperclip>
- Web UI port: `3100`
- CLI: `pnpm paperclipai <command>` (inside the container)

**Current status: documentation / init phase.** Only `README.md`, `CLAUDE.md`, and
`context.md` exist. No add-on code (`config.yaml`, `Dockerfile`, `run.sh`, …) has
been written yet — that is the next session's work (see §10).

---

## 2. Locked architecture decisions

These were decided with the user during init. Do not revisit without asking.

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Build locally on HA install** (no CI, no GHCR pre-build) | PaperclipAI has no published Docker image. The add-on `Dockerfile` builds it from GitHub source at a pinned tag during install. `config.yaml` must **not** set an `image:` field — its presence makes HA pull instead of build. |
| 2 | **Direct port `3100/tcp`** (no HA ingress) | Matches the working setup; avoids better-auth + hostname-allowlist + WebSocket proxying complexity that ingress would introduce. |
| 3 | **`amd64` only** | Matches warp10 (x86_64) and the heavy workload (Node + embedded Postgres + bundled AI CLIs). ARM is underpowered for this. |

---

## 3. Planned repository structure

Single-addon repo, following the [HA-LiteLLM](D:/DEV/bbourgeois.github.com/HA-LiteLLM)
layout. Items marked _(next session)_ do not exist yet.

```
HA-PaperclipAI/
├── repository.yaml            # repo manifest (name/url/maintainer)   (next session)
├── README.md                  # user-facing docs                      (this session)
├── CLAUDE.md                  # this file                             (this session)
├── context.md                 # warp10 reference setup (keep, do not delete)
└── paperclipai/               # the add-on                            (next session)
    ├── config.yaml            # manifest: ports, options, schema, map, arch
    ├── build.yaml             # build_from base image (amd64)
    ├── Dockerfile             # clone + build PaperclipAI from source + HA glue
    ├── run.sh                 # options.json → env, xdg-open shim, exec server
    ├── DOCS.md                # in-UI add-on documentation
    ├── icon.png / logo.png    # branding (placeholder ok initially)
    └── translations/en.yaml   # option labels (optional)
```

---

## 4. PaperclipAI build approach (the hard part)

There is **no pre-built PaperclipAI image** to pull. The add-on `Dockerfile` must
build it from source during local install. Reproduce upstream's 3-stage build —
see context.md → "Dockerfile (multi-stage build)" for the authoritative detail.

- **Pin a release tag.** Clone `https://github.com/paperclipai/paperclip` at a
  specific tag (e.g. `v2026.618.0`) — never `master` — for reproducibility.
- **Stage `base`:** `node:lts-trixie-slim`; install system tools
  `ca-certificates gosu curl gh git wget ripgrep python3 openssh-client jq`;
  enable `corepack` (pnpm).
- **Stage `deps`/`build`:** `pnpm install --frozen-lockfile`; build UI, plugin SDK,
  and server (`@paperclipai/server`).
- **Stage `production`:** globally install the AI CLIs
  `@anthropic-ai/claude-code@latest`, `@openai/codex@latest`, `opencode-ai`,
  `@google/gemini-cli@latest`; set `HOME=/paperclip`.
- **Server start command** (from context.md):
  `node --import ./server/node_modules/tsx/dist/loader.mjs server/dist/index.js`

> ⚠️ **Maintenance note:** upstream's Dockerfile changes between releases
> (context.md, "Lesson learned"). Updating the add-on = bump the pinned tag **and**
> re-verify the build steps against the new upstream Dockerfile.

> ⚠️ **Build cost:** ~1 GB image, several minutes to build on the HA host. State
> this clearly to users (README) and expect failures on low-RAM HAOS hosts.

---

## 5. HA "glue" requirements

Concrete tasks distilled from context.md → "Lessons Learned". Each must be handled
in the add-on (`Dockerfile` and/or `run.sh`):

- **`BETTER_AUTH_SECRET` is mandatory.** The server refuses to start without it.
  Expose it as a required add-on option; persist it; fail fast with a clear log
  message if empty. Generate with `openssl rand -hex 32`.
- **Dummy `xdg-open`.** `paperclipai auth login` calls `xdg-open`, which crashes the
  Node process (`ENOENT`) in a headless container. Install a stub that just
  `exit 0` (in the image or entrypoint) **before** any auth flow runs.
- **Hostname allowlist.** With `deploymentMode=authenticated`, every hostname/IP used
  to reach the UI must be allowlisted. Pre-seed `homeassistant.local`, the LAN IP,
  and `localhost` in the entrypoint, and/or expose an `allowed_hostnames` option.
  CLI: `pnpm paperclipai allowed-hostname <host>` (updates `config.json` + DB).
- **Embedded Postgres on `:54329` is internal only.** Never map/expose it. No sidecar
  DB container is needed — Postgres 17 runs inside the same container.
- **`HOME=/paperclip`.** All AI tool config/cache (Claude Code, Codex, Gemini,
  OpenCode) writes here, so it must live on the persistent volume.
- **Hired-agent model override.** New agents may get `adapter_config.model` hardcoded
  to a real Anthropic model, bypassing custom LLM routing. Document the fix: PATCH the
  agent to set `"model": null`. (Not strictly add-on code — document in README/DOCS.)

---

## 6. Persistence / volume mapping plan

PaperclipAI keeps **all** state under `/paperclip` inside the container (embedded
Postgres data dir, secrets/`master.key`, logs, instance `config.json`, agent
instruction markdown, CLI `context.json`, run logs, backups). See context.md →
"Persistent Data Volume Structure".

- Map PaperclipAI's `/paperclip` to HA's persistent **`/data`** (e.g. bind or symlink
  `/data/paperclip`). `/data` survives add-on restarts and updates.
- Optional **`/workspaces`** (per-agent git checkouts so code agents have repos to
  work in) → HA `share` or `addon_config`. **Decide in next session** (see §10).
- The path agents use must be the path **inside the container**, not the host path
  (context.md lesson #7 / "Project & Workspace Setup").

---

## 7. Config options schema (planned)

Mirror the env vars from context.md → ".env File". Proposed `config.yaml` options
(finalize names/types next session):

- `better_auth_secret` — **required** string.
- `public_url` — `PAPERCLIP_PUBLIC_URL` (e.g. `http://homeassistant.local:3100`).
- `allowed_hostnames` — list of hostnames/IPs to allowlist.
- LLM routing: `anthropic_base_url`, `anthropic_auth_token`, `anthropic_api_key`,
  `anthropic_model`, and the tier overrides `anthropic_default_haiku_model` /
  `…_sonnet_model` / `…_opus_model`, plus `claude_code_subagent_model`.
- Claude Code flags: `claude_code_effort`, `claude_code_experimental_agent_teams`,
  `claudecode`, `disable_prompt_caching`, `claude_code_disable_thinking`,
  `claude_code_disable_adaptive_thinking`, `claude_code_use_bedrock`,
  `claude_code_use_vertex`.
- `openai_api_key`, `opencode_allow_all_models`.

Use HA schema validation (`str`, `str?`, `port`, `[str]`, `bool`, etc.) as in the
HA-LiteLLM / Grafana references.

---

## 8. Runtime entrypoint (`run.sh`) responsibilities

Follow the HA-LiteLLM (`python3` JSON parse) or open-webui (`jq`) pattern for reading
HA options. The script should:

1. Read `/data/options.json` and export each option as the matching `PAPERCLIP_*` /
   `ANTHROPIC_*` / `CLAUDE_CODE_*` env var.
2. Validate `better_auth_secret` is set; exit with a clear error if not.
3. Install the dummy `xdg-open` shim (if not baked into the image).
4. Ensure the persistent dir exists (`/data/paperclip`) and `HOME` points at it.
5. Pre-seed allowed hostnames.
6. `exec` the PaperclipAI server (see §4 for the start command).

Keep it a single bash script — S6/bashio are **not** required for this single-service
add-on (HA-LiteLLM proves a plain `run.sh` is sufficient).

---

## 9. Reference locations

- **[context.md](context.md)** — the warp10 PaperclipAI setup. Primary reference.
- **HA-LiteLLM** — `D:\DEV\bbourgeois.github.com\HA-LiteLLM` — minimal single-addon
  repo: `repository.yaml`, `LiteLLM/config.yaml`, `Dockerfile`, `run.sh`, `README.md`.
  Closest structural match to what we're building.
- **HA-Addons** — `D:\DEV\HA-Addons` — pattern library: `addon-open-webui-main`
  (`FROM upstream` + `run.sh` env wrapper), `home-assistant-addons-main/grafana_cloud`
  (`build.yaml`, `translations/`, builder workflow), `addon-vscode-main` (rich config,
  s6 — more than we need here).
- Upstream PaperclipAI: <https://github.com/paperclipai/paperclip>
- HA add-on dev docs: <https://developers.home-assistant.io/docs/add-ons/>
- HA add-on config reference: <https://developers.home-assistant.io/docs/add-ons/configuration>
- better-auth: <https://better-auth.com>

---

## 10. Open TODOs for the coding session

- [ ] Choose the pinned PaperclipAI release tag (e.g. `v2026.618.0`); verify its
      Dockerfile against §4.
- [ ] Finalize the `/workspaces` mapping (HA `share` vs `addon_config`).
- [ ] Decide options parsing: `python3` (HA-LiteLLM) vs `jq` (open-webui).
- [ ] Decide: expose `allowed_hostnames` as an option vs auto-seed in entrypoint
      (or both).
- [ ] Create icon/logo assets (placeholder acceptable initially).
- [ ] Scaffold all files in §3 and test a local build on the HA host.
- [ ] Surface the `bootstrap-ceo` invite URL in the add-on logs on first run.

---

## 11. Conventions

- Single-addon repo layout (one `repository.yaml` at root + one addon folder).
- Semantic version in `config.yaml` (`version: "x.y.z"`); bump on each change.
- `amd64` only in `arch:` / `build.yaml`.
- Plain `run.sh` entrypoint; no S6/bashio unless a real need appears.
- Keep README user-facing; keep deep build/architecture notes here and in DOCS.md.
- Never expose Postgres `:54329`. Never commit secrets (`BETTER_AUTH_SECRET`, API keys).
