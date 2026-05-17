# LDR (Local Deep Research) bring-up — pi5

Temporary upstream Python LDR service for Phase A. Removed in Phase B.9 after
the Go reimplementation passes the parity gate. See task A.0a.

## Generate the shared secret

API endpoints are gated at the edge (Caddy) by an `X-LDR-API-Key` header check
(see [API auth](#api-auth) below — we don't build LDR ourselves, so a Flask
middleware patch was not viable; same trust boundary, simpler ship). Generate
the shared secret once and reuse it on both the Go bridge and the Caddy
container:

```bash
openssl rand -hex 32
```

## Wire the secret into the pi5 stack

The pi5 stack reads from `deploy/pi5/.env` (the same file consumed by
`backend`, `evo-api`, `skills-worker`, `frontend` (Caddy), etc. — `frontend`
loads it via `env_file: [.env]`, which is what makes `{env.LDR_API_KEY}` in
the Caddyfile substitute correctly). Append:

```
LDR_API_KEY=<paste output of openssl rand -hex 32>
```

### Env vars needed in pi5 .env

| Var            | Consumer(s)                          | Required |
|----------------|--------------------------------------|----------|
| `LDR_API_KEY`  | `frontend` (Caddy edge auth), `ldr`, nano-research bridge | yes |

Optional overrides — defaulted in `docker-compose.yml`, no action needed
unless you want different values:

```
LDR_LLM_PROVIDER=openai_endpoint                       # default
LDR_LLM_OPENAI_ENDPOINT_URL=http://10.0.4.37:9080/v1   # workstation vLLM
LDR_LLM_OPENAI_ENDPOINT_API_KEY=                       # empty if vLLM is unauth
LDR_LLM_MODEL=qwen3.6-27b-nvfp8                        # default
```

Note: LDR uses per-user SQLCipher databases in `/data` (the `ldr_data`
volume) — there is no shared Postgres DSN to configure. The Go bridge owns
the single LDR account it uses; credentials get provisioned via the LDR web
UI on first boot, then locked in `LDR_APP_ALLOW_REGISTRATIONS=false` (already
set in compose).

## Bring up

```bash
cd deploy/pi5
docker compose up -d ldr
```

`searxng` is the only hard dependency and is already part of the stack.

## Health check

```bash
# Internal (container network):
docker compose exec ldr curl -fsS http://localhost:5000/api/v1/health

# External (via Caddy reverse proxy):
curl -fsSk https://ldr.local/api/v1/health
```

Self-signed TLS — first hit per device will warn until you trust Caddy's
local CA (printed at frontend startup; also at
`/data/caddy/pki/authorities/local/root.crt` inside the `frontend` container).

## API auth

The upstream `localdeepresearch/local-deep-research:latest` image has no
header-auth middleware and we're not patching it. Instead, Caddy gates the
API surface at the edge:

- `/research/api/*` and `/api/*` require a `X-LDR-API-Key` header that
  matches `${LDR_API_KEY}` from `deploy/pi5/.env`. No match → `401
  unauthorized`.
- Everything else (`/`, `/auth/login`, `/auth/register`, static assets,
  `/health`, the browser UI under `/research/*` minus the API prefix)
  passes through untouched. The browser flow still relies on the LDR
  Flask login session + Flask-WTF CSRF — that's authoritative for users.

The nano-research Go bridge (task A.1) reads the same `LDR_API_KEY` from its
environment and sets the header on every outbound request. There is no
fallback unauthenticated path for the API; if you bring a new client up,
it has to send the header.

### Verify

After `docker compose up -d frontend ldr` (and confirming `LDR_API_KEY` is
set in your shell, sourced from `deploy/pi5/.env`):

```bash
# With the header → 200 (or whatever LDR's start endpoint returns on success).
curl -sk -o /dev/null -w "%{http_code}\n" \
  https://ldr.local/research/api/start \
  -H "X-LDR-API-Key: $LDR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query":"hello","iterations":1}'

# Without the header → 401.
curl -sk -o /dev/null -w "%{http_code}\n" \
  https://ldr.local/research/api/start \
  -H "Content-Type: application/json" \
  -d '{"query":"hello","iterations":1}'
```

The browser UI (e.g. `https://ldr.local/`) should keep working without any
header — only `/research/api/*` and `/api/*` are gated.
