// =============================================================================
// heal-agent-models.js — PaperclipAI HA add-on model-override reconciler
//
// Problem: when an agent is hired/edited in the PaperclipAI web UI, the model
// dropdown's concrete default (e.g. "claude-sonnet-4-6") gets persisted into
// `agents.adapter_config.model`. For `claude_local` agents that value is passed
// to Claude Code as a literal `--model <id>`, OVERRIDING the container's
// ANTHROPIC_MODEL env var. With custom LLM routing (e.g. a LiteLLM proxy that
// only knows your local model), the agent then sends an unknown model id and
// every run fails at init with HTTP 400 "Invalid model name".
//
// Fix: surgically null that field so the agent falls back to ANTHROPIC_MODEL.
// We do it in the DB with jsonb_set rather than via `PATCH /api/agents/:id`,
// because that endpoint REPLACES the whole adapterConfig instead of merging
// (upstream issue #964) and would wipe cwd / instruction paths / permissions.
//
// run.sh invokes this on a loop (default every 60s) when `enforce_env_model` is
// on, so newly hired agents self-heal within a minute. It is intentionally
// QUIET and NON-FATAL: a missing DB (Postgres not up yet) or any error exits 0
// without noise, so it can never take the server down. It only logs when it
// actually changes something.
// =============================================================================

// Resolve the `pg` module from wherever pnpm placed it for the server package.
// (A bare require('pg') from /app does not resolve under pnpm's symlinked layout.)
let Client;
try {
  ({ Client } = require(require.resolve('pg', { paths: ['/app/server', '/app'] })));
} catch (_) {
  // pg unavailable — nothing we can do; stay silent and let the loop retry.
  process.exit(0);
}

const env = process.env;
const client = new Client({
  host: env.PAPERCLIP_PG_HOST || 'localhost',
  port: Number(env.PAPERCLIP_PG_PORT || 54329),
  user: env.PAPERCLIP_PG_USER || 'paperclip',
  password: env.PAPERCLIP_PG_PASSWORD || 'paperclip',
  database: env.PAPERCLIP_PG_DB || 'paperclip',
  // Keep the loop snappy: if Postgres isn't accepting connections yet, fail fast
  // and let the next iteration retry rather than hanging.
  connectionTimeoutMillis: 5000,
});

// Null `model` ONLY for Claude adapters (codex_local legitimately materialises a
// concrete model, so leave it alone). jsonb_set touches only the `model` key and
// preserves every other field in adapter_config. Idempotent: rows already at JSON
// null are excluded by the `->>'model' IS NOT NULL` guard.
const SQL = `
  UPDATE agents
  SET adapter_config = jsonb_set(adapter_config, '{model}', 'null'::jsonb)
  WHERE adapter_type IN ('claude_local', 'claude-local')
    AND adapter_config ? 'model'
    AND adapter_config->>'model' IS NOT NULL
`;

client
  .connect()
  .then(() => client.query(SQL))
  .then((res) => {
    if (res.rowCount > 0) {
      console.log(`[heal] reset hardcoded model override on ${res.rowCount} agent(s) -> inherit ANTHROPIC_MODEL`);
    }
  })
  .catch(() => {
    // Postgres not ready / transient error — silent by design; the loop retries.
  })
  .finally(() => {
    client.end().catch(() => {});
  });
