# Dashboard apiserver — local development

The platform dashboard is a Go HTTP server at
`platform/dashboard/cmd/api/main.go` that serves the REST API consumed by the
React frontend. It aggregates data from Postgres, Temporal, the delegator
orchestrator, and several knowledge-plane services.

The dashboard is in scheduled migration to the new `platform/backend` +
`frontend` stack (see `platform/dashboard/DEPRECATED.md`), but it is the
active backend for the current Vite SPA.

---

## Dependencies

| Dependency | Default address | Required? |
|------------|----------------|-----------|
| Postgres (`gogents` DB) | `localhost:5433` | Required; server refuses to start without a pool |
| Temporal | `localhost:7233` | Required; Temporal-backed endpoints return 503 if unavailable |
| skills-rae | `localhost:7376` | Optional; skill search endpoints return 503 if unavailable |
| nano-research | `localhost:7378` | Optional; research proxy |

See [docs/LOCAL_DEV.md](LOCAL_DEV.md) for how to bring up Postgres and Temporal.

---

## Environment variables

The server reads configuration through `core/config` (Viper + env-var overlay).
All vars have defaults; override as needed.

| Env var | Default | Purpose |
|---------|---------|---------|
| `PORT` | `9123` | Listen port — **port 8080 is banned** |
| `POSTGRES_DSN` or `GOGENTS_POSTGRES_DSN` | `postgres://gogents:gogents-dev@localhost:5433/gogents?sslmode=disable` | Postgres connection string |
| `TEMPORAL_ADDRESS` or `GOGENTS_TEMPORAL_ADDRESS` | `localhost:7233` | Temporal gRPC frontend |
| `TEMPORAL_NAMESPACE` | `default` | Temporal namespace |
| `TEMPORAL_TASK_QUEUE` | `pr-review` | Default task queue name |
| `LOG_LEVEL` | `info` | Logrus log level |
| `EVO_HOME` | `/opt/evo` | Root for plugin YAML search paths |
| `EVO_PLUGIN_DIRS` | (derived from `EVO_HOME`) | Colon-separated override for plugin YAML dirs |
| `GOGENTS_APISERVER_MAX_INFLIGHT_WORKFLOWS` | `50` | Semaphore cap on concurrent workflow triggers |
| `HEALTH_TOPOLOGY_PATH` | unset | Path to `health-topology.yml` for fleet health endpoints |

### Minimal working set

```bash
PORT=9123 \
POSTGRES_DSN="postgres://gogents:gogents-dev@localhost:5433/gogents?sslmode=disable" \
TEMPORAL_ADDRESS="localhost:7233" \
  go run ./cmd/api
```

---

## Running the server

From the sub-repo:

```bash
cd /thearray/git/Adamaton/platform/dashboard
go run ./cmd/api
```

From the umbrella (builds via `go.work`):

```bash
cd /thearray/git/Adamaton
PORT=9123 go run ./platform/dashboard/cmd/api
```

The server logs its listen address on startup:

```
INFO  API server listening on :9123
```

---

## Proxying the Vite frontend

The React SPA lives in `frontend/` and talks to the apiserver over
`/api/v1/*`. In production Caddy forwards `/api/v1/*` to `platform.dashboard`
on localhost; in development you have two options:

**Option A: Vite dev server (hot reload)**

```bash
cd /thearray/git/Adamaton/frontend
pnpm install
VITE_EVO_API_BASE=http://localhost:9123 pnpm dev
```

The Vite server starts on `:5173` and proxies `/api/v1/*` to the apiserver.
Open `http://localhost:5173` in the browser.

**Option B: Serve the built dist via the apiserver**

```bash
cd /thearray/git/Adamaton/frontend
pnpm build          # outputs dist/ relative to the frontend sub-repo
```

The apiserver does not serve static files directly — serve the dist with a
local Caddy or nginx if you need to test the production build path.

---

## Key API endpoints

| Endpoint | Purpose |
|----------|---------|
| `GET /api/v1/health` | Server health |
| `GET /api/v1/dashboard/stats` | Dashboard aggregate stats |
| `GET /api/v1/nodes` | Registered Temporal workers |
| `GET /api/v1/jobs` | Recent workflow jobs |
| `GET /api/v1/memory/files` | Memory file index |
| `GET /api/v1/skills/search?q=<query>` | Skill RAE search (requires skills-rae) |
| `GET /api/v1/evo/runs` | Evolutionary run history |
| `GET /api/v1/delegator/tasks` | Delegator task list |
| `GET /api/v1/nodes/fleet-health` | Fleet-wide health topology |
| `POST /api/v1/workflows/trigger` | Trigger a workflow |

Hit the root health endpoint:

```bash
curl http://localhost:9123/api/v1/health
```

---

## Modules and imports

`platform/dashboard/go.mod` imports:
- `adamaton-core` — config, types, metrics
- `adamaton-delegator/delegator` — task store + orchestrator
- `adamaton-evolve/workflow-builder` — workflow store + plugin loader
- `adamaton-platform/temporal` — Gitea + workflow activities

All resolved via `go.work` in local dev. Each has a `replace ../../<repo>`
directive in `go.mod` for sub-repo-only CI builds. See
[docs/CROSS_MODULE.md](CROSS_MODULE.md) for worktree gotchas.

---

## Cross-links

- [docs/LOCAL_DEV.md](LOCAL_DEV.md) — full local bring-up checklist
- [docs/CROSS_MODULE.md](CROSS_MODULE.md) — go.work / replace gotchas
- [platform/dashboard/DEPRECATED.md](../platform/dashboard/DEPRECATED.md) — migration plan
