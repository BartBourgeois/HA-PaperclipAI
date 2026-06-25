#!/usr/bin/env bash
# =============================================================================
# PaperclipAI — Home Assistant add-on entrypoint
#
# Responsibilities (in order):
#   1. Reconcile persistence: point HOME/PAPERCLIP_HOME/PAPERCLIP_CONFIG at the
#      persistent /data volume instead of the image's ephemeral /paperclip.
#   2. Require BETTER_AUTH_SECRET (the server refuses to start without it).
#   3. Map add-on options -> canonical env vars (only when non-empty).
#   4. Re-assert the headless xdg-open shim.
#   5. Background: seed the hostname allowlist + surface the first-run CEO invite.
#   6. exec the PaperclipAI server as the unprivileged `node` user (embedded
#      Postgres refuses to run as root).
#
# Plain bash — no s6/bashio needed for this single-service add-on.
# =============================================================================
set -eo pipefail

CONFIG_PATH="/data/options.json"
PAPERCLIP_DATA="/data/paperclip"

# Read one option from options.json. JSON booleans are normalised to lowercase
# ("true"/"false") so they match what the upstream env vars expect (Python would
# otherwise print "True"/"False").
opt() {
  python3 - "$1" <<'PY'
import json, sys
v = json.load(open("/data/options.json")).get(sys.argv[1], "")
print(str(v).lower() if isinstance(v, bool) else v)
PY
}

# ---------------------------------------------------------------------------
# 1. Persistence + HOME reconciliation.
#    HOME, PAPERCLIP_HOME and PAPERCLIP_CONFIG are the only baked vars that
#    reference /paperclip; repointing them at /data/paperclip means nothing
#    writes to the image's ephemeral dir afterwards.
# ---------------------------------------------------------------------------
mkdir -p "${PAPERCLIP_DATA}"
chown -R node:node "${PAPERCLIP_DATA}"
export HOME="${PAPERCLIP_DATA}"
export PAPERCLIP_HOME="${PAPERCLIP_DATA}"
export PAPERCLIP_CONFIG="${PAPERCLIP_DATA}/instances/default/config.json"

# ---------------------------------------------------------------------------
# 2. Required: BETTER_AUTH_SECRET.
# ---------------------------------------------------------------------------
BETTER_AUTH_SECRET="$(opt better_auth_secret)"
if [ -z "${BETTER_AUTH_SECRET}" ]; then
  echo "[FATAL] 'better_auth_secret' is required but is empty." >&2
  echo "[FATAL] Generate one with:  openssl rand -hex 32" >&2
  echo "[FATAL] then set it in the add-on Configuration tab and restart." >&2
  exit 1
fi
export BETTER_AUTH_SECRET

# ---------------------------------------------------------------------------
# 3. Map options -> canonical env vars, only when non-empty so an empty option
#    never clobbers a value baked into the image.
# ---------------------------------------------------------------------------
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
exp opencode_allow_all_models             OPENCODE_ALLOW_ALL_MODELS

# ---------------------------------------------------------------------------
# 4. Re-assert the headless xdg-open shim (baked into the image; recreate if
#    somehow missing) so `paperclipai auth login` can't crash on ENOENT.
# ---------------------------------------------------------------------------
if [ ! -x /usr/local/bin/xdg-open ]; then
  printf '#!/bin/sh\nexit 0\n' > /usr/local/bin/xdg-open
  chmod a+x /usr/local/bin/xdg-open
fi

# ---------------------------------------------------------------------------
# 5. Background: once the server (and its embedded Postgres) is listening, seed
#    the hostname allowlist and, on first run, print the CEO invite URL.
#    All steps tolerate failure so they never take the server down.
# ---------------------------------------------------------------------------
cd /app
(
  # Wait until the server accepts connections (any HTTP response = up).
  for _ in $(seq 1 60); do
    curl -s -o /dev/null "http://localhost:3100" && break
    sleep 2
  done

  LANIP="$(hostname -i 2>/dev/null | awk '{print $1}')"
  HOSTS="$(python3 -c "import json;print(' '.join(json.load(open('${CONFIG_PATH}')).get('allowed_hostnames',[])))")"
  for h in ${HOSTS} localhost homeassistant.local "${LANIP}"; do
    [ -n "$h" ] && gosu node pnpm paperclipai allowed-hostname "$h" >/dev/null 2>&1 || true
  done

  if [ ! -f "${PAPERCLIP_DATA}/.ha_bootstrapped" ]; then
    echo "=================== PAPERCLIPAI FIRST-RUN ==================="
    echo "Creating the one-time CEO (admin) invite. Open the URL printed"
    echo "below in your browser to create your admin account:"
    echo "------------------------------------------------------------"
    gosu node pnpm paperclipai auth bootstrap-ceo || true
    echo "------------------------------------------------------------"
    echo "Missed it? From the add-on console run:"
    echo "  pnpm paperclipai auth bootstrap-ceo --force"
    echo "============================================================"
    touch "${PAPERCLIP_DATA}/.ha_bootstrapped"
  fi
) &

# ---------------------------------------------------------------------------
# 6. Hand off to the PaperclipAI server as the unprivileged `node` user.
# ---------------------------------------------------------------------------
exec gosu node node --import ./server/node_modules/tsx/dist/loader.mjs server/dist/index.js
