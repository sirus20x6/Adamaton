# Deploy

## Hosts

| Host | Role | Compose |
|---|---|---|
| **pi5** | Main stack: postgres, temporal, knowledge backends, deepresearch, platform, frontend, caddy | `deploy/pi5/docker-compose.yml` |
| **pi5-speaker** | Replica: nano-research-worker, figure-renderer | `deploy/pi5-speaker/docker-compose.yml` |
| **blackwell** | GPU node: vLLM, evo-worker (KernelBench), distill trainer | `deploy/blackwell/compose-*.yml` |
| **workstation** | Local dev: postgres + temporal-dev only | `deploy/workstation/docker-compose.yml` |

## Bring-up

```bash
bin/adam deploy <host>
```

This runs `deploy/<host>/up.sh`, which:

1. Reads the umbrella's current submodule pins.
2. For each image that ships on `<host>`: cross-compiles the binary on the workstation, builds the arm64/amd64 OCI image, rsyncs the tar (wifi-friendly per `pi_caddy_bind_mount_inode` lesson).
3. rsyncs the host-specific compose/Caddyfile/.env from `deploy/<host>/` to `<host>:~/Adamaton-deploy/`.
4. SSH-execs `docker compose up -d && docker compose ps`.

Image tags use the umbrella SHA: `adamaton-platform:<umbrella-sha-short>`. Every deploy is reproducible from one ref. `latest` is updated only by `bin/adam deploy --promote`.

## Per-host quickstart

### Pi #1 (pi5)

First-time setup:
- SSH key from workstation already trusted (`~/.ssh/authorized_keys`)
- Docker + docker compose installed
- Postgres data volume preserved across deploys

Routine:
```bash
bin/adam deploy pi5
```

### Pi #2 (pi5-speaker)

Prereqs: Pi #1 exposes `postgres:5432`, `temporal:7233`, `skills-rae:7376` on `0.0.0.0` (one-time per `nano-research/deploy/pi-replica/expose_pi1_ports.sh` in the evo archive, ported to `deploy/pi5/scripts/`).

Routine:
```bash
bin/adam deploy pi5-speaker
```

### Blackwell

Prereqs: vLLM running with `--enable-lora` (for distill LoRA hot-swaps); ssh key trusted; `/path/to/checkpoints/` directory exists.

Routine:
```bash
bin/adam deploy blackwell
```

### Workstation (dev)

```bash
bin/adam deploy workstation
# brings up local postgres + temporal-dev
# does not start any worker containers — run `go run ./cmd/<worker>` from each submodule for foreground dev
```

## Pre-deploy schema-migration coordination

Not every service migrates the shared Postgres schema, and the ones that do
migrate different slices of it. Getting the **order** wrong means a service
boots against tables/columns that don't exist yet.

Who migrates what:

- **evolve store** (`evolve/evolve/store`, embedded `migrations/*.sql`,
  migration table `schema_migrations_evo`): runs automatically inside
  `store.Open` — i.e. **on worker boot**. Anything that opens the store
  migrates: `adamaton-worker` (via its evo registration), `evo-worker`,
  `evo-cli`. This is the schema the apiserver/`evo-api` *reads*
  (`evo.tasks`, kanban, workers, jobs, …).
- **apiserver / evo-api** (`platform/dashboard/apiserver`): does **NOT**
  migrate the evo schema. At boot it only runs its *own* namespaced
  migrations (`schema_migrations_experiments`, `schema_migrations_datasets`),
  and those are **best-effort** — a failure logs a warning and the server
  keeps serving anyway.

Consequence: when a release includes evolve-store schema changes, the
**worker must boot (and finish migrating) before the apiserver serves
traffic** that touches the new tables. Compose `depends_on` does not order
this — the apiserver has no dependency on the worker.

Pre-flight for any deploy that includes evo schema changes:

```bash
# 1. Roll the worker first and let it migrate on boot:
ssh pi5 'cd ~/Adamaton-deploy && docker compose up -d adamaton-worker'
ssh pi5 'cd ~/Adamaton-deploy && docker compose logs --tail 50 adamaton-worker'
#    (confirm a clean boot / migration lines, no crash-loop)

# 2. Verify the schema version landed:
ssh pi5 "docker exec \$(docker ps -qf name=postgres) \
  psql -U gogents -c 'select * from schema_migrations_evo'"

# 3. Only then roll the apiserver:
ssh pi5 'cd ~/Adamaton-deploy && docker compose up -d evo-api'
```

One-shot alternative (no worker restart wanted): run any store-opening binary
against the same DSN — e.g. `evo-cli` — since `store.Open` migrates
unconditionally; a `docker compose run --rm` of the worker image with a
command that opens the store and exits does the same.

Rules of thumb:

- **Additive-only migrations** (new tables, nullable columns): the ordering
  above is sufficient; the old apiserver keeps working mid-roll.
- **Destructive/renaming migrations**: don't, in one release. Split into
  add → deploy → backfill → drop across two releases, so no running binary
  ever sees a schema it doesn't understand.
- **Rollback**: nothing runs the `.down.sql` files automatically —
  `bin/adam deploy --rollback` rolls binaries, not schema. Rolling a binary
  back past a schema bump is only safe if the bump was additive.

## Rollback

Every umbrella commit is a deploy ref. To revert pi5 to a known-good state:

```bash
# At the umbrella, find the good SHA:
git log --oneline -- deploy/pi5/

# Roll the umbrella back:
git checkout <good-sha>
bin/adam deploy pi5

# Or use the explicit rollback flag (same effect):
bin/adam deploy pi5 --rollback=<good-sha>
```

The `--rollback` form leaves the umbrella's HEAD unchanged and ships the older deploy/ + image tags directly.

## Troubleshooting

### Caddy doesn't pick up new frontend bundle

Per the `pi_caddy_bind_mount_inode` memory: `mv newfile oldfile` on the host pins the OLD inode in the bind-mounted frontend container. Fix:

```bash
ssh pi5 'cd ~/Adamaton-deploy && docker compose restart frontend'
```

Not `caddy reload` — Caddy itself is fine; the bind-mount file handle is the problem.

### Cross-compile cache misses

`make pi-<sub>` runs the Go cross-compile in a Docker context with cgo enabled. Cache lives at `~/.cache/adam-cross/`. Clear with:

```bash
rm -rf ~/.cache/adam-cross/
```

### Submodule SHA mismatch on Pi

The Pi's `Adamaton-deploy/` only contains the deploy/ files, not the source tree. If `docker compose pull` reports the wrong tag, the umbrella's pin was updated but `bin/adam deploy` was never re-run — re-run it.
