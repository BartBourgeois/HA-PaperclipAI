# Init HA-PaperclipAI — Documentation Phase

## Context

`HA-PaperclipAI` will become a Home Assistant add-on that runs **PaperclipAI**
(an open-source, self-hosted AI project-management platform that gives AI coding
agents a company/project/issue board) inside HAOS — replicating the working Docker
setup currently running on the `warp10` machine.

This session is **documentation/init only**. We produce two files — `CLAUDE.md`
and `README.md` — that capture everything needed so the *next* session can scaffold
and write the actual add-on code. No add-on code (config.yaml, Dockerfile, run.sh)
is created this session.

The full working reference setup is documented in [context.md](context.md). Two
existing HA add-on repos are used as structural references:
- [D:\DEV\bbourgeois.github.com\HA-LiteLLM](D:/DEV/bbourgeois.github.com/HA-LiteLLM) — minimal single-addon repo (`repository.yaml` + addon folder; `config.yaml` + `Dockerfile` + `run.sh` parsing `/data/options.json`; no S6/bashio).
- [D:\DEV\HA-Addons](D:/DEV/HA-Addons) — richer patterns: `build.yaml` `build_from`, the open-webui `FROM upstream + run.sh` wrapper, the Grafana `image:`/GHCR + `translations/` + GitHub Actions builder patterns, ingress, icons/logos.

## Locked architecture decisions (from user)

1. **Build strategy: build locally on HA install.** No CI, no GHCR pre-build.
   The add-on `Dockerfile` builds PaperclipAI from its GitHub source at a pinned
   release tag during add-on installation on the HA host. `config.yaml` does **not**
   use an `image:` field (that forces a local Dockerfile build).
2. **UI access: direct port `3100/tcp`.** No HA ingress. Matches the current
   working setup; avoids better-auth + hostname-allowlist + WebSocket proxying issues.
3. **Architecture: `amd64` only.** Matches warp10 (x86_64) and the heavy workload
   (Node + embedded Postgres + bundled AI CLIs).

## Deliverables (this session)

Two files at the repo root `d:\DEV\bbourgeois.github.com\HA-PaperclipAI\`:

### 1. `CLAUDE.md` — guidance for future coding sessions

Audience: the AI assistant in the next session. Sections:

- **Project overview & current status** — what this add-on is; that it ports the
  warp10 PaperclipAI Docker setup; status = "documentation/init phase, no code yet".
- **Locked architecture decisions** — the 3 decisions above + rationale.
- **Planned repository structure** (to be created next session), following the
  single-addon HA-LiteLLM layout:
  ```
  HA-PaperclipAI/
  ├── repository.yaml            # repo manifest (name/url/maintainer)
  ├── README.md                  # this session
  ├── CLAUDE.md                  # this session
  ├── context.md                 # existing reference (keep)
  └── paperclipai/               # the add-on
      ├── config.yaml            # manifest: ports, options, schema, map, arch
      ├── build.yaml             # build_from base image (amd64)
      ├── Dockerfile             # clone+build PaperclipAI from source + HA glue
      ├── run.sh                 # options.json → env, xdg-open shim, exec server
      ├── DOCS.md                # in-UI add-on docs
      ├── icon.png / logo.png    # branding (placeholder ok)
      └── translations/en.yaml   # option labels (optional)
  ```
- **PaperclipAI build approach (the hard part)** — the add-on `Dockerfile` must
  reproduce upstream's 3-stage build (`base` → `deps/build` → `production`) by
  cloning `https://github.com/paperclipai/paperclip` at a **pinned tag**
  (e.g. `v2026.618.0`). Document: base `node:lts-trixie-slim`; system deps
  (`ca-certificates gosu curl gh git wget ripgrep python3 openssh-client jq`);
  `corepack`/pnpm; global AI CLIs (`@anthropic-ai/claude-code`, `@openai/codex`,
  `opencode-ai`, `@google/gemini-cli`); `HOME=/paperclip`. **Maintenance note:**
  upstream's Dockerfile changes between releases (context.md), so updating = bump
  tag + re-verify build steps. (Ref: context.md "Dockerfile (multi-stage build)".)
- **HA glue requirements** — concrete tasks derived from context.md "Lessons
  Learned", each mapped to where it's handled:
  - Mandatory `BETTER_AUTH_SECRET` → add-on option, persisted; refuse start if empty.
  - Dummy `xdg-open` (exit 0) installed in image/entrypoint (prevents `auth login` crash).
  - Hostname allowlist → entrypoint pre-populates `homeassistant.local`/LAN IP/`localhost`, or expose option.
  - Embedded Postgres on `:54329` is **internal only** — never expose.
  - `HOME=/paperclip` so all AI tool config/cache lands in the persistent volume.
- **Persistence / volume mapping plan** — PaperclipAI's `/paperclip` (DB, secrets,
  logs, config, agent instructions, CLI `context.json`) → HA persistent `/data`
  (e.g. bind `/data/paperclip`). Optional `/workspaces` (agent git checkouts) →
  HA `share` or `addon_config` (decide next session).
- **Config options schema (planned)** — `better_auth_secret` (required),
  `public_url`, LLM routing (`anthropic_base_url`, `anthropic_auth_token`,
  `anthropic_api_key`, `anthropic_model` + tier overrides), `CLAUDE_CODE_*` flags,
  `openai_api_key`, `allowed_hostnames`. Mirror env vars from context.md ".env File".
- **Runtime entrypoint (`run.sh`) responsibilities** — read `/data/options.json`
  (python/jq, per HA-LiteLLM / open-webui patterns) → export env; install xdg-open
  shim; ensure `/data/paperclip` exists; pre-seed allowed hostnames; `exec` the
  PaperclipAI server (`node --import .../tsx/.../loader.mjs server/dist/index.js`).
- **Reference locations** — context.md; HA-LiteLLM path; HA-Addons path; upstream
  repo + HA add-on dev docs URLs (from context.md "For the HA Add-on Builder").
- **First-run / bootstrap** — `paperclipai auth bootstrap-ceo` prints an invite URL;
  document surfacing it in add-on logs.
- **Open TODOs for coding session** — finalize `/workspaces` mapping; decide
  python-vs-jq options parsing; pick pinned PaperclipAI tag; icon/logo assets;
  whether to expose an `allowed_hostnames` option vs auto-seed.

### 2. `README.md` — user-facing add-on documentation

Follows the HA-LiteLLM README structure (tables, code blocks, ASCII diagram). Sections:

- **Title + intro** — what PaperclipAI is; that this add-on runs it in HAOS.
- **Features** — self-hosted AI agent board; bundled embedded Postgres (no sidecar);
  works with Anthropic API or any OpenAI/Anthropic-compatible endpoint (e.g. LiteLLM);
  persistent data; amd64.
- **Requirements / caveats** — amd64 only; heavy (~1GB image, multi-minute local
  build on install); resource expectations.
- **Installation** — add this repo to HA add-on store; install (note: builds from
  source locally, takes several minutes).
- **Configuration** — options table (`better_auth_secret` required — generate with
  `openssl rand -hex 32`; LLM routing vars; etc.).
- **First-time setup** — start add-on → run `bootstrap-ceo` → open invite URL →
  create company/project; allowed-hostname note.
- **LLM routing** — Anthropic-direct vs LiteLLM-proxy examples (from context.md).
- **Usage** — access UI at `http://homeassistant.local:3100`.
- **Storage & persistence** — what lives in `/data` and survives restarts/updates.
- **Updating** — bump add-on version / rebuild; data preserved.
- **Troubleshooting** — distilled from context.md lessons (xdg-open, hostname
  allowlist, hardcoded model in hired agents → set `model: null`, orphan containers n/a).
- **Architecture** — ASCII diagram (HA add-on container → PaperclipAI server +
  embedded Postgres :54329; outbound to LLM endpoint).
- **Links** — upstream repo, better-auth, HA add-on docs.
- **License** — note PaperclipAI upstream license + this wrapper.

## Critical files

- Create: `d:\DEV\bbourgeois.github.com\HA-PaperclipAI\CLAUDE.md`
- Create: `d:\DEV\bbourgeois.github.com\HA-PaperclipAI\README.md`
- Read-only references: [context.md](context.md), HA-LiteLLM (`config.yaml`,
  `Dockerfile`, `run.sh`, `README.md`, `repository.yaml`), HA-Addons (open-webui
  `Dockerfile`/`run.sh`, grafana `config.yaml`/`build.yaml`/`translations`).

## Verification

- Re-read both files for technical accuracy against [context.md](context.md)
  (ports, env var names, volume paths, lessons learned) — no contradictions.
- Confirm the locked decisions (build-locally / port 3100 / amd64) are stated
  consistently in both files.
- Markdown sanity: headings, tables, and fenced code blocks render correctly;
  relative links resolve.
- Confirm with the user that CLAUDE.md is a sufficient brief to start coding next
  session, then stop (no code this session).

## Out of scope (next session)

`repository.yaml`, `paperclipai/config.yaml`, `build.yaml`, `Dockerfile`, `run.sh`,
`DOCS.md`, icons, translations — all the actual add-on code.
