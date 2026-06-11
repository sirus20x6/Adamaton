# Local development bring-up

This document gives a fresh agent or developer a complete, ordered checklist for
getting every local service running so they can iterate against the full
Adamaton stack on the workstation.

## Prerequisites

- `git`, `go` >= 1.25, `docker` + `docker compose`, `gh` CLI, `zig` (for ztok +
  Zig sidecars), `temporal` CLI (`go install
  go.temporal.io/server/cmd/temporal@latest`)
- SSH key registered with GitHub (`gh auth status` must pass)
- Workstation is `amd64` Linux; arm64 cross-compile paths are marked in the
  `Makefile` (`pi-*` targets)

---

## Step 1 — Clone and initialize submodules

```bash
git clone --recursive git@github.com:sirus20x6/Adamaton.git
cd Adamaton
```

If you already cloned without `--recursive`:

```bash
git submodule update --init --recursive
```

## Step 2 — Doctor and hooks

```bash
bin/adam doctor        # checks git user.name/email, gh auth, go version,
                       # 7 submodules initialized, hooks installed
bin/adam sync-hooks    # installs pre-commit / pre-push / commit-msg into
                       # umbrella + every submodule .git/hooks/
```

Fix anything `doctor` flags before continuing — the hooks will hard-reject
commits on main otherwise.

## Step 3 — Postgres

Two logical Postgres instances are used in development:

| Instance | Image | Port | User/DB | Purpose |
|----------|-------|------|---------|---------|
| gogents (paradedb) | `pgvector/pgvector:pg16` | **5433** | `gogents`/`gogents` | delegator tasks, budget, contextmode, dashboard workflows |
| evo (evo schema) | system postgres or compose | **5432** | `postgres`/`postgres` | evo/evolve tables, ccsaver mirror |

The workstation compose (`deploy/workstation/docker-compose.yml`) starts a
single postgres on :5433 using the `pgvector/pgvector:pg16` image. The default
credentials match `core/config/config.go`:

```bash
cd /thearray/git/Adamaton
docker compose -f deploy/workstation/docker-compose.yml up -d postgres
```

Default DSN (used by all Go services when `POSTGRES_DSN` is unset):

```
postgres://gogents:gogents-dev@localhost:5433/gogents?sslmode=disable
```

Migrations run automatically when each service boots (each binary accepts a
`--migrate` flag or auto-migrates on startup via `core/pgutil`).

To open a shell:

```bash
docker exec -it adamaton-workstation-postgres \
  psql -U gogents -d gogents
```

### Connecting delegator-mcp

The MCP binary hard-fails at startup if `POSTGRES_DSN` is not set (no tools
register). Add it to `~/.claude.json` under `mcpServers.delegator.env`:

```json
{
  "mcpServers": {
    "delegator": {
      "env": {
        "POSTGRES_DSN": "postgres://gogents:gogents-dev@localhost:5433/gogents?sslmode=disable"
      }
    }
  }
}
```

## Step 4 — Temporal

Most workers and the dashboard apiserver require Temporal on `:7233`. The
workstation compose includes a `temporal-dev` service (in-memory SQLite
persistence — state is wiped on restart):

```bash
docker compose -f deploy/workstation/docker-compose.yml up -d temporal-dev
```

Ports exposed:
- `7233` — gRPC frontend (required by every worker + the apiserver)
- `7234` — HTTP API
- `8233` — Temporal Web UI

Alternatively, run temporal standalone (same in-memory dev mode):

```bash
temporal server start-dev --ip 0.0.0.0 --port 7233 --http-port 7234 --ui-port 8233
```

**The apiserver will not boot without Temporal reachable at `:7233`.** The SDK
logs a warning every few seconds and continues retrying, but workflow-related
endpoints return 503 until the connection succeeds.

## Step 5 — ztok (required for r2g + reindex)

`knowledge/r2g` tokenizes text via the `ztok` cgo binding. The `ztok` source
lives at `/thearray/git/ztok` (not a git submodule in Adamaton). Build the
native library once:

```bash
cd /thearray/git/ztok
zig build -Doptimize=ReleaseFast -p "$PWD/zig-out"
```

Then point `pkg-config` at the built output before building or testing any
module that imports r2g or reindex:

```bash
export PKG_CONFIG_PATH="/thearray/git/ztok/zig-out/lib/pkgconfig"
export LD_LIBRARY_PATH="/thearray/git/ztok/zig-out/lib"
```

You also need a symlink at the umbrella root so the relative `replace
../../ztok/bindings/go` in `knowledge/r2g/go.mod` resolves:

```bash
cd /thearray/git/Adamaton
ln -s /thearray/git/ztok ztok   # temp symlink; do NOT commit
```

Docker image builds do not need the symlink — the Dockerfile `COPY ztok` uses
the real directory (see docs/CROSS_MODULE.md for the COPY gotcha).

## Step 6 — go.work

The umbrella's `go.work` aggregates all Go modules so that cross-component
imports resolve to local paths during development:

```
./core
./deepresearch/nano-research
./delegator/delegator
./delegator/mcp
./evolve/dataset-manager
./evolve/evolve
./evolve/workflow-builder
./knowledge/r2g
./knowledge/reindex
./knowledge/skills
./knowledge/skills-rae
./platform/dashboard
./platform/dispatch
./platform/plugin-host
./platform/temporal
./platform/worker
```

Running `go build ./...` or `go test ./...` from the umbrella root picks up all
modules via `go.work`. From inside a sub-repo directory you get the same
behavior because `go` walks up to find the nearest `go.work`.

**Building without go.work** (simulates per-sub-repo CI):

```bash
GOWORK=off go build ./...   # from a sub-repo dir
```

If a sub-repo's `go.mod` has no `replace` directives for its cross-repo deps,
this will fail with "no such file or directory" errors — that is intentional CI
enforcement (see docs/CROSS_MODULE.md).

## Step 7 — skills-rae (optional but useful)

`deepresearch/nano-research` and the dashboard both call `skills-rae` on
`:7376` for skill retrieval. Start it locally:

```bash
cd /thearray/git/Adamaton/knowledge/skills-rae
POSTGRES_DSN="postgres://gogents:gogents-dev@localhost:5433/gogents?sslmode=disable" \
  go run ./cmd/skills-rae
```

If skills-rae is not running, nano-research logs a connection error per request
but continues functioning; the dashboard skill endpoints return 503.

## Step 8 — Dashboard apiserver

```bash
cd /thearray/git/Adamaton/platform/dashboard
PORT=9123 \
POSTGRES_DSN="postgres://gogents:gogents-dev@localhost:5433/gogents?sslmode=disable" \
TEMPORAL_ADDRESS="localhost:7233" \
  go run ./cmd/api
```

The server listens on `:9123`. See [docs/DASHBOARD_DEV.md](DASHBOARD_DEV.md)
for the full env-var reference and how to proxy the Vite frontend.

## Bring-up order summary

1. Postgres `:5433` — all services need it
2. Temporal `:7233` — dashboard apiserver + every worker
3. (Optional) skills-rae `:7376` — nano-research + dashboard skill endpoints
4. (Optional) bge-embed `:8092` — r2g embedding (workstation compose includes
   a `bge-embed` service if you need local embeddings)
5. Dashboard apiserver `:9123` — UI backend
6. Frontend `pnpm dev` `:5173` — proxied through apiserver in prod; direct in dev

## Cross-links

- [docs/DASHBOARD_DEV.md](DASHBOARD_DEV.md) — full apiserver env vars + Vite proxy
- [docs/TESTING.md](TESTING.md) — running tests, skipping docker deps
- [docs/CROSS_MODULE.md](CROSS_MODULE.md) — go.work / replace / worktree gotchas
- [DEPLOY.md](DEPLOY.md) — deploying to Pi fleet
